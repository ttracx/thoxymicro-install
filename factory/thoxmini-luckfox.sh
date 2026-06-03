#!/usr/bin/env bash
#
# factory/thoxmini-luckfox.sh - factory provisioning composite installer.
#
# Intended for the manufacturing line. Runs the thoxymicro-edge installer with
# production defaults and a stable device identity, then enables OTA updates.
#
# One-liner:
#   curl -fsSL https://install.thox.ai/thoxymicro | sudo bash
# (where install.thox.ai resolves to the raw URL of this script in the install repo)

set -euo pipefail

RAW="${THOXY_INSTALL_RAW_BASE:-https://raw.githubusercontent.com/ttracx/thoxymicro-install/main}"

# Production defaults. Override only with explicit env vars.
export VARIANT="${VARIANT:-thoxymicro-edge}"
export THOXY_VERSION="${THOXY_VERSION:-latest}"
export THOXY_USER="${THOXY_USER:-thoxy}"
export THOXY_HOSTNAME="${THOXY_HOSTNAME:-thoxymicro-$(date +%y%m%d%H%M%S)}"
export THOXY_API_PORT="${THOXY_API_PORT:-8787}"
export THOXY_DATA_DIR="${THOXY_DATA_DIR:-/var/lib/thoxymicro}"

# Hub credentials are supplied at manufacturing time via env or a token file.
if [[ -z "${THOXY_HUB_URL:-}" && -r /etc/thoxy-factory/hub.url ]]; then
  THOXY_HUB_URL="$(cat /etc/thoxy-factory/hub.url)"
  export THOXY_HUB_URL
fi
if [[ -z "${THOXMINI_DEVICE_TOKEN:-}" && -r /etc/thoxy-factory/device.token ]]; then
  THOXMINI_DEVICE_TOKEN="$(cat /etc/thoxy-factory/device.token)"
  export THOXMINI_DEVICE_TOKEN
fi

echo "[factory] running install.sh with VARIANT=${VARIANT} hostname=${THOXY_HOSTNAME}"
curl -fsSL "${RAW}/install.sh" | bash

# Install OTA update helper.
install -m 0755 -D /dev/stdin /usr/local/sbin/thoxy-ota <<'OTA'
#!/usr/bin/env bash
# thoxy-ota - simple OTA update for ThoxyMicro devices.
set -euo pipefail
RAW="${THOXY_INSTALL_RAW_BASE:-https://raw.githubusercontent.com/ttracx/thoxymicro-install/main}"
VARIANT="${VARIANT:-thoxymicro-edge}"
VERSION="${THOXY_VERSION:-latest}"
echo "[ota] updating ${VARIANT} to ${VERSION}"
curl -fsSL "${RAW}/install.sh" | VARIANT="$VARIANT" THOXY_VERSION="$VERSION" bash
OTA

# Cron-friendly weekly check (disabled by default; uncomment to enable).
cat >/etc/cron.weekly/thoxy-ota <<'CRON'
#!/bin/sh
# Uncomment to enable weekly OTA polling:
# /usr/local/sbin/thoxy-ota || logger -t thoxy-ota "weekly OTA failed"
exit 0
CRON
chmod 0755 /etc/cron.weekly/thoxy-ota

echo "[factory] provisioning complete"
