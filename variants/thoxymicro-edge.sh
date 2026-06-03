#!/usr/bin/env bash
#
# variants/thoxymicro-edge.sh - install the edge agent with hub offload + RKNPU2.
#
# Use this on Luckfox Pico Mini B field devices. The agent runs under a 28 MiB
# soft memory limit, dispatches local jobs through RKNPU2 when available, and
# offloads chat-class inference to a THOXY or MagStack hub via thoxy_client.

set -euo pipefail

RAW="${THOXY_INSTALL_RAW_BASE:-https://raw.githubusercontent.com/ttracx/thoxymicro-install/main}"
tmp_common="$(mktemp)"
trap 'rm -f "$tmp_common"' EXIT
curl -fsSL "${RAW}/lib/common.sh" -o "$tmp_common"
# shellcheck disable=SC1090
. "$tmp_common"

require_root

PREFIX="${THOXY_PREFIX:-/usr/local}"
USER_NAME="${THOXY_USER:-thoxy}"
USER_PW="${THOXY_USER_PW:-}"
ROOT_PW="${THOXY_ROOT_PW:-}"
HOSTNAME_NEW="${THOXY_HOSTNAME:-}"
VERSION="${THOXY_VERSION:-latest}"
API_PORT="${THOXY_API_PORT:-8787}"
DATA_DIR="${THOXY_DATA_DIR:-/var/lib/thoxymicro}"
HUB_URL="${THOXY_HUB_URL:-}"
DEVICE_TOKEN="${THOXMINI_DEVICE_TOKEN:-}"
REPO="ttracx/thoxymicro-edge"

arch="$(detect_arch)"
os="$(detect_os)"
board="$(detect_board)"
info "arch=${arch} os=${os} board=${board}"

case "$arch" in
  armv7) ;;
  *) warn "thoxymicro-edge is designed for ARMv7 (Luckfox Pico Mini B); proceeding on $arch anyway" ;;
esac

[[ -n "$HOSTNAME_NEW" ]] && { hostnamectl set-hostname "$HOSTNAME_NEW" 2>/dev/null || echo "$HOSTNAME_NEW" > /etc/hostname; ok "hostname set: $HOSTNAME_NEW"; }
[[ -n "$ROOT_PW" ]] && set_user_password root "$ROOT_PW"

ensure_user "$USER_NAME"
[[ -n "$USER_PW" ]] && set_user_password "$USER_NAME" "$USER_PW"

# Download the packaged deploy bundle.
asset="thoxymicro-edge-thoxmini-${arch}.tar.gz"
work="$(mktemp -d)"
trap 'rm -rf "$work" "$tmp_common"' EXIT
download_release_asset "$REPO" "$VERSION" "$asset" "${work}/${asset}"
tar -xzf "${work}/${asset}" -C "$work"

# Locate the extracted bundle dir.
bundle_dir="$(find "$work" -maxdepth 2 -type d -name 'thoxymicro-edge*' | head -n 1)"
[[ -n "$bundle_dir" ]] || die "could not locate extracted bundle in $work"

install_binary "${bundle_dir}/thoxymicro" "${PREFIX}/bin/thoxymicro"
install -m 0755 -d "$DATA_DIR" "/etc/thoxymicro" "/opt/thoxymicro/models"
chown -R "${USER_NAME}:${USER_NAME}" "$DATA_DIR" "/opt/thoxymicro/models"

# Config: device + runtime + hub + npu.
cat >/etc/thoxymicro/thoxmini.json <<CFG
{
  "device": { "name": "ThoxyMicro", "board": "luckfox-pico-mini-b-rv1103", "memory_mb": 64, "flash_mb": 128 },
  "runtime": { "memory_limit_mb": 28, "gogc": 30, "max_workers": 1, "telemetry": true },
  "npu": { "backend": "rknpu2", "models_dir": "/opt/thoxymicro/models" },
  "hub": { "client": "thoxy_client", "url": "${HUB_URL}", "token_env": "THOXMINI_DEVICE_TOKEN" }
}
CFG
chmod 0644 /etc/thoxymicro/thoxmini.json

cat >/etc/thoxymicro/thoxmini.env <<ENV
GOMEMLIMIT=28MiB
GOGC=30
GOMAXPROCS=1
THOXYMICRO_LISTEN=0.0.0.0:${API_PORT}
THOXYMICRO_CONFIG=/etc/thoxymicro/thoxmini.json
THOXY_HUB_URL=${HUB_URL}
THOXMINI_DEVICE_TOKEN=${DEVICE_TOKEN}
ENV
chmod 0600 /etc/thoxymicro/thoxmini.env
chown root:"$USER_NAME" /etc/thoxymicro/thoxmini.env

# systemd unit (preferred).
if [[ -r "${bundle_dir}/thoxymicro.service" ]]; then
  install_systemd_unit "${bundle_dir}/thoxymicro.service" thoxymicro || true
else
  cat >/tmp/thoxymicro.service <<UNIT
[Unit]
Description=THOX.ai thoxymicro-edge (Luckfox edge agent)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
Group=${USER_NAME}
EnvironmentFile=/etc/thoxymicro/thoxmini.env
ExecStart=${PREFIX}/bin/thoxymicro serve
Restart=always
RestartSec=2
WatchdogSec=60
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
LimitNOFILE=1024
LimitNPROC=64

[Install]
WantedBy=multi-user.target
UNIT
  install_systemd_unit /tmp/thoxymicro.service thoxymicro || \
    install_busybox_init "${bundle_dir}/S99thoxymicro" thoxymicro
fi

start_service thoxymicro || warn "service did not start; check logs"
verify_health "http://127.0.0.1:${API_PORT}/health" 20 || true

if [[ -z "$HUB_URL" ]]; then
  warn "THOXY_HUB_URL not set; chat-class flows will return a routing error until /etc/thoxymicro/thoxmini.env is updated"
fi
if [[ -z "$DEVICE_TOKEN" ]]; then
  warn "THOXMINI_DEVICE_TOKEN not set; the hub will reject auth until /etc/thoxymicro/thoxmini.env is updated"
fi

print_completion thoxymicro-edge "$VERSION" "$board" "$API_PORT"
