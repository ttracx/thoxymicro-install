#!/usr/bin/env bash
#
# variants/thoxymicro.sh - install the full Go dev codebase.
#
# Use this for engineer/dev hosts where you want every adapter compiled in
# and the membench eval suite available. For field devices, prefer
# variants/thoxy-micro.sh or variants/thoxymicro-edge.sh.

set -euo pipefail

RAW="${THOXY_INSTALL_RAW_BASE:-https://raw.githubusercontent.com/ttracx/thoxymicro-install/main}"

# Source shared primitives.
tmp_common="$(mktemp)"
trap 'rm -f "$tmp_common"' EXIT
curl -fsSL "${RAW}/lib/common.sh" -o "$tmp_common"
# shellcheck disable=SC1090
. "$tmp_common"

require_root

# ---- Config ----
PREFIX="${THOXY_PREFIX:-/usr/local}"
USER_NAME="${THOXY_USER:-thoxy}"
USER_PW="${THOXY_USER_PW:-}"
ROOT_PW="${THOXY_ROOT_PW:-}"
HOSTNAME_NEW="${THOXY_HOSTNAME:-}"
VERSION="${THOXY_VERSION:-latest}"
API_PORT="${THOXY_API_PORT:-8080}"
DATA_DIR="${THOXY_DATA_DIR:-/var/lib/thoxymicro}"
REPO="ttracx/thoxymicro"

arch="$(detect_arch)"
os="$(detect_os)"
board="$(detect_board)"
info "arch=${arch} os=${os} board=${board}"

case "$arch" in
  armv7|aarch64|amd64) ;;
  *) die "unsupported arch: $arch (full codebase needs armv7, aarch64, or amd64)" ;;
esac

[[ -n "$HOSTNAME_NEW" ]] && { hostnamectl set-hostname "$HOSTNAME_NEW" 2>/dev/null || echo "$HOSTNAME_NEW" > /etc/hostname; ok "hostname set: $HOSTNAME_NEW"; }
[[ -n "$ROOT_PW" ]] && set_user_password root "$ROOT_PW"

ensure_user "$USER_NAME"
[[ -n "$USER_PW" ]] && set_user_password "$USER_NAME" "$USER_PW"

# Download the prebuilt binary for this architecture.
asset="thoxymicro-${arch}.tar.gz"
work="$(mktemp -d)"
trap 'rm -rf "$work" "$tmp_common"' EXIT
download_release_asset "$REPO" "$VERSION" "$asset" "${work}/${asset}"
tar -xzf "${work}/${asset}" -C "$work"

install_binary "${work}/thoxymicro" "${PREFIX}/bin/thoxymicro"
install -m 0755 -d "$DATA_DIR" "$(dirname "$DATA_DIR")/thoxymicro/cache" "/etc/thoxymicro"
chown -R "${USER_NAME}:${USER_NAME}" "$DATA_DIR"

cat >/etc/thoxymicro/thoxymicro.env <<ENV
THOXYMICRO_LISTEN=0.0.0.0:${API_PORT}
THOXYMICRO_DATA_DIR=${DATA_DIR}
THOXYMICRO_LOG_LEVEL=info
ENV
chmod 0644 /etc/thoxymicro/thoxymicro.env

cat >/tmp/thoxymicro.service <<UNIT
[Unit]
Description=THOX.ai ThoxyMicro (full codebase)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
Group=${USER_NAME}
EnvironmentFile=/etc/thoxymicro/thoxymicro.env
ExecStart=${PREFIX}/bin/thoxymicro serve
Restart=always
RestartSec=2
WatchdogSec=60
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
UNIT

if ! install_systemd_unit /tmp/thoxymicro.service thoxymicro; then
  install_busybox_init "${work}/init/S99thoxymicro" thoxymicro 2>/dev/null || warn "no systemd or busybox-init found; configure service manually"
fi

start_service thoxymicro || warn "service did not start; check 'journalctl -u thoxymicro'"
verify_health "http://127.0.0.1:${API_PORT}/health" 20 || true

print_completion thoxymicro "$VERSION" "$board" "$API_PORT"
