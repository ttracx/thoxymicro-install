#!/usr/bin/env bash
#
# common.sh - shared install primitives for THOX.ai ThoxyMicro variants.
# Sourced from variants/<variant>.sh. Do not call directly.

set -euo pipefail
umask 022

# Color theme (re-export from router or define locally if invoked standalone).
if [[ -t 1 ]]; then
  C_EMERALD="${C_EMERALD:-$'\e[38;5;48m'}"
  C_PURPLE="${C_PURPLE:-$'\e[38;5;141m'}"
  C_AMBER="${C_AMBER:-$'\e[38;5;214m'}"
  C_DIM="${C_DIM:-$'\e[2m'}"
  C_BOLD="${C_BOLD:-$'\e[1m'}"
  C_RESET="${C_RESET:-$'\e[0m'}"
else
  C_EMERALD=""; C_PURPLE=""; C_AMBER=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

info()  { printf '%s[*]%s %s\n' "${C_PURPLE}"  "${C_RESET}" "$*"; }
ok()    { printf '%s[+]%s %s\n' "${C_EMERALD}" "${C_RESET}" "$*"; }
warn()  { printf '%s[!]%s %s\n' "${C_AMBER}"   "${C_RESET}" "$*" >&2; }
die()   { printf '%s[X]%s %s\n' "${C_AMBER}"   "${C_RESET}" "$*" >&2; exit 1; }

# ---------- platform detection ----------

detect_arch() {
  local m
  m="$(uname -m)"
  case "$m" in
    armv7l|armhf) echo "armv7" ;;
    aarch64|arm64) echo "aarch64" ;;
    x86_64|amd64)  echo "amd64" ;;
    i386|i686)     echo "i386" ;;
    *) echo "unknown:$m" ;;
  esac
}

detect_os() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "${ID:-linux}-${VERSION_ID:-unknown}"
  elif command -v openwrt >/dev/null 2>&1 || [[ -r /etc/openwrt_release ]]; then
    echo "openwrt"
  else
    echo "linux-unknown"
  fi
}

detect_board() {
  if [[ -r /proc/device-tree/model ]]; then
    tr -d '\0' </proc/device-tree/model
  elif [[ -r /proc/cpuinfo ]]; then
    awk -F': ' '/Hardware|Model/ { print $2; exit }' /proc/cpuinfo
  else
    echo "unknown"
  fi
}

require_root() {
  [[ $EUID -eq 0 ]] || die "must run as root"
}

# ---------- user + permissions ----------

ensure_user() {
  local user="${1:-thoxy}"
  if id "$user" >/dev/null 2>&1; then
    info "user '$user' already exists"
    return 0
  fi
  if command -v adduser >/dev/null 2>&1; then
    adduser --system --group --shell /bin/sh --home "/var/lib/$user" "$user" || die "adduser failed for $user"
  else
    useradd --system --shell /bin/sh --home-dir "/var/lib/$user" --create-home "$user" || die "useradd failed for $user"
  fi
  ok "user '$user' created"
}

set_user_password() {
  local user="$1" pw="${2:-}"
  if [[ -z "$pw" ]]; then return 0; fi
  if command -v chpasswd >/dev/null 2>&1; then
    printf '%s:%s\n' "$user" "$pw" | chpasswd
    ok "password set for $user"
  else
    warn "chpasswd not available; cannot set password for $user"
  fi
}

# ---------- binary install ----------

install_binary() {
  local src="$1" dst="$2" mode="${3:-0755}"
  install -m "$mode" -D "$src" "$dst"
  ok "installed binary: $dst ($(stat -c '%s' "$dst") bytes)"
}

# ---------- service install ----------

install_systemd_unit() {
  local unit_src="$1" name="$2"
  if ! command -v systemctl >/dev/null 2>&1; then
    return 1
  fi
  install -m 0644 -D "$unit_src" "/etc/systemd/system/${name}.service"
  systemctl daemon-reload
  systemctl enable "$name" >/dev/null 2>&1 || true
  ok "systemd unit installed: ${name}.service"
  return 0
}

install_busybox_init() {
  local rc_src="$1" name="$2"
  install -m 0755 -D "$rc_src" "/etc/init.d/${name}"
  if command -v rc-update >/dev/null 2>&1; then
    rc-update add "$name" default || true
  elif [[ -d /etc/rcS.d ]]; then
    ln -sf "/etc/init.d/${name}" "/etc/rcS.d/S99${name}" || true
  fi
  ok "busybox-init script installed: /etc/init.d/${name}"
}

start_service() {
  local name="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart "$name" || die "failed to start service: $name"
    sleep 1
    systemctl is-active --quiet "$name" || die "service $name did not stay active"
  elif [[ -x "/etc/init.d/$name" ]]; then
    "/etc/init.d/$name" restart || die "failed to restart $name"
  else
    warn "no service manager found; service not started"
    return 1
  fi
  ok "service started: $name"
}

# ---------- health verification ----------

verify_health() {
  local url="${1:-http://127.0.0.1:8080/health}"
  local timeout="${2:-30}"
  local elapsed=0
  info "verifying $url (timeout ${timeout}s)"
  while (( elapsed < timeout )); do
    if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
      ok "health check passed: $url"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  warn "health check did not pass within ${timeout}s"
  return 1
}

# ---------- release download ----------

download_release_asset() {
  local repo="$1" tag="$2" asset="$3" out="$4"
  local url
  if [[ -n "${THOXY_GITHUB_TOKEN:-}" ]]; then
    local api="https://api.github.com/repos/${repo}/releases"
    [[ "$tag" == "latest" ]] && api="${api}/latest" || api="${api}/tags/${tag}"
    url="$(curl -fsSL -H "Authorization: Bearer ${THOXY_GITHUB_TOKEN}" -H 'Accept: application/vnd.github+json' "$api" |
      awk -v name="$asset" 'BEGIN{RS=","} /browser_download_url/ && index($0,name)>0 {gsub(/.*"browser_download_url"[ :]*"|"$/,"",$0); print; exit}')"
    [[ -n "$url" ]] || die "release asset not found: $repo $tag $asset"
    curl -fsSL -H "Authorization: Bearer ${THOXY_GITHUB_TOKEN}" -H 'Accept: application/octet-stream' "$url" -o "$out"
  else
    if [[ "$tag" == "latest" ]]; then
      url="https://github.com/${repo}/releases/latest/download/${asset}"
    else
      url="https://github.com/${repo}/releases/download/${tag}/${asset}"
    fi
    curl -fsSL "$url" -o "$out" || die "release asset fetch failed (set THOXY_GITHUB_TOKEN for private repos): $url"
  fi
  ok "downloaded: $asset ($(stat -c '%s' "$out") bytes)"
}

# ---------- completion banner ----------

print_completion() {
  local variant="$1" version="$2" board="$3" port="${4:-8080}"
  cat <<COMPLETE
${C_EMERALD}===========================================${C_RESET}
${C_BOLD}THOX.ai ThoxyMicro Installed${C_RESET}
${C_EMERALD}===========================================${C_RESET}
Device:  ${C_BOLD}ThoxyMicro prototype${C_RESET}
Board:   ${C_BOLD}${board}${C_RESET}
Variant: ${C_BOLD}${variant}${C_RESET}
Version: ${C_BOLD}${version}${C_RESET}

API:
  http://127.0.0.1:${port}/health
  http://127.0.0.1:${port}/status

Service:
  systemctl status ${variant}
  journalctl -u ${variant} -f

THOX.ai Ready
${C_EMERALD}===========================================${C_RESET}
COMPLETE
}
