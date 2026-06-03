#!/usr/bin/env bash
#
# variants/thoxy-micro.sh - install the shipping daemon (5.1 MB ARMv7 firmware floor).
#
# Use this on devices that should run the smallest possible binary. CLI + HTTP
# adapters are default; all other channels are opt-in via Go build tags at
# build time, not at install time.

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
REPO="ttracx/thoxy-micro"

arch="$(detect_arch)"
os="$(detect_os)"
board="$(detect_board)"
info "arch=${arch} os=${os} board=${board}"

case "$arch" in
  armv7) ;;
  aarch64|amd64) warn "thoxy-micro is tuned for ARMv7 (Luckfox Pico Mini B); $arch will work but is not the design target" ;;
  *) die "unsupported arch: $arch (thoxy-micro targets armv7)" ;;
esac

[[ -n "$HOSTNAME_NEW" ]] && { hostnamectl set-hostname "$HOSTNAME_NEW" 2>/dev/null || echo "$HOSTNAME_NEW" > /etc/hostname; ok "hostname set: $HOSTNAME_NEW"; }
[[ -n "$ROOT_PW" ]] && set_user_password root "$ROOT_PW"

ensure_user "$USER_NAME"
[[ -n "$USER_PW" ]] && set_user_password "$USER_NAME" "$USER_PW"

asset="thoxy-micro-linux-${arch}"
work="$(mktemp -d)"
trap 'rm -rf "$work" "$tmp_common"' EXIT
download_release_asset "$REPO" "$VERSION" "$asset" "${work}/thoxy-micro"

install_binary "${work}/thoxy-micro" "${PREFIX}/bin/thoxy-micro"
install -m 0755 -d "$DATA_DIR" "/etc/thoxymicro"
chown -R "${USER_NAME}:${USER_NAME}" "$DATA_DIR"

cat >/etc/thoxymicro/thoxmini.luckfox.json <<CFG
{
  "device": { "name": "ThoxyMicro", "board": "luckfox-pico-mini-b-rv1103", "memory_mb": 64, "flash_mb": 128, "npu_tops": "0.5 int4/int8/int16" },
  "runtime": { "mode": "edge-micro", "max_workers": 1, "max_payload_kb": 64, "telemetry": true },
  "adapters": { "cli": true, "http": true }
}
CFG
chmod 0644 /etc/thoxymicro/thoxmini.luckfox.json

cat >/tmp/thoxy-micro.service <<UNIT
[Unit]
Description=THOX.ai thoxy-micro (shipping daemon)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
Group=${USER_NAME}
ExecStart=${PREFIX}/bin/thoxy-micro -config /etc/thoxymicro/thoxmini.luckfox.json -addr 0.0.0.0:${API_PORT}
Restart=always
RestartSec=2
WatchdogSec=60
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
UNIT

if ! install_systemd_unit /tmp/thoxy-micro.service thoxy-micro; then
  cat >/tmp/S99thoxy-micro <<RC
#!/bin/sh
case "\$1" in
  start) ${PREFIX}/bin/thoxy-micro -config /etc/thoxymicro/thoxmini.luckfox.json -addr 0.0.0.0:${API_PORT} >/var/log/thoxy-micro.log 2>&1 &
         echo \$! >/run/thoxy-micro.pid
         ;;
  stop)  [ -r /run/thoxy-micro.pid ] && kill "\$(cat /run/thoxy-micro.pid)" 2>/dev/null; rm -f /run/thoxy-micro.pid ;;
  restart) \$0 stop; sleep 1; \$0 start ;;
  *) echo "usage: \$0 {start|stop|restart}"; exit 1 ;;
esac
RC
  install_busybox_init /tmp/S99thoxy-micro thoxy-micro
fi

start_service thoxy-micro || warn "service did not start; check logs"
verify_health "http://127.0.0.1:${API_PORT}/health" 15 || true

print_completion thoxy-micro "$VERSION" "$board" "$API_PORT"
