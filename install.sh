#!/usr/bin/env bash
#
# install.sh - THOX.ai ThoxyMicro one-liner installer router.
#
# Dispatches to the variant-specific installer based on the VARIANT env var.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ttracx/thoxymicro-install/main/install.sh | \
#     sudo VARIANT=thoxymicro-edge bash
#
# Supported variants:
#   thoxymicro        Full Go dev codebase (engineer machine)
#   thoxy-micro       Shipping daemon (firmware floor, ~5 MB)
#   thoxymicro-edge   Edge agent with hub offload + RKNPU2 (production device)
#
# Env vars:
#   VARIANT             (required) one of the three above
#   THOXY_VERSION       (optional) release tag; defaults to "latest"
#   THOXY_HOSTNAME      (optional) sets the device hostname
#   THOXY_USER          (optional) service user; default "thoxy"
#   THOXY_USER_PW       (optional) password for THOXY_USER; default unset (locked)
#   THOXY_ROOT_PW       (optional) root password to set; default unset (no change)
#   THOXY_HUB_URL       (optional, edge only) hub URL for chat offload
#   THOXMINI_DEVICE_TOKEN (optional, edge only) bearer for the hub
#   THOXY_GITHUB_TOKEN  (optional but recommended) PAT with read:packages + repo for private releases
#   THOXY_API_PORT      (optional) listen port; default 8080
#   THOXY_DATA_DIR      (optional) data dir; default /var/lib/thoxymicro
#   THOXY_PREFIX        (optional) install prefix; default /usr/local
#   THOXY_DRY_RUN       (optional) "1" to print actions without running

set -euo pipefail
umask 022

# Color theme (THOX emerald + ink). Disabled when not a TTY.
if [[ -t 1 ]]; then
  C_EMERALD=$'\e[38;5;48m'
  C_PURPLE=$'\e[38;5;141m'
  C_AMBER=$'\e[38;5;214m'
  C_DIM=$'\e[2m'
  C_BOLD=$'\e[1m'
  C_RESET=$'\e[0m'
else
  C_EMERALD=""; C_PURPLE=""; C_AMBER=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

banner() {
  printf '%s\n' "${C_EMERALD}=========================================${C_RESET}"
  printf '%s\n' "${C_BOLD}THOX.ai ThoxyMicro Installer${C_RESET}"
  printf '%s\n' "${C_DIM}https://thox.ai${C_RESET}"
  printf '%s\n' "${C_EMERALD}=========================================${C_RESET}"
}

die() {
  printf '%s[!]%s %s\n' "${C_AMBER}" "${C_RESET}" "$*" >&2
  exit 1
}

info() {
  printf '%s[*]%s %s\n' "${C_PURPLE}" "${C_RESET}" "$*"
}

ok() {
  printf '%s[+]%s %s\n' "${C_EMERALD}" "${C_RESET}" "$*"
}

# Resolve repo root + raw URL prefix.
RAW="${THOXY_INSTALL_RAW_BASE:-https://raw.githubusercontent.com/ttracx/thoxymicro-install/main}"

main() {
  banner

  [[ $EUID -eq 0 ]] || die "must run as root: prefix with sudo"

  local variant="${VARIANT:-}"
  case "$variant" in
    thoxymicro|thoxy-micro|thoxymicro-edge) ;;
    "") die "VARIANT env var not set. Use one of: thoxymicro, thoxy-micro, thoxymicro-edge" ;;
    *) die "unknown VARIANT '$variant'. Use one of: thoxymicro, thoxy-micro, thoxymicro-edge" ;;
  esac

  info "Variant: ${C_BOLD}${variant}${C_RESET}"
  info "Version: ${C_BOLD}${THOXY_VERSION:-latest}${C_RESET}"
  info "Prefix:  ${C_BOLD}${THOXY_PREFIX:-/usr/local}${C_RESET}"
  info "Service user: ${C_BOLD}${THOXY_USER:-thoxy}${C_RESET}"

  if [[ "${THOXY_DRY_RUN:-0}" == "1" ]]; then
    info "DRY RUN: skipping fetch + apply"
    return 0
  fi

  local script_url="${RAW}/variants/${variant}.sh"
  info "Fetching variant installer: ${script_url}"

  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT

  if ! curl -fsSL "$script_url" -o "$tmp"; then
    die "fetch failed. If this is a private repo, set THOXY_GITHUB_TOKEN and use the gh-auth flow (see README)."
  fi

  # Sanity: file must be a bash script.
  head -1 "$tmp" | grep -q '^#!.*bash' || die "downloaded script does not look like bash: $(head -1 "$tmp")"

  ok "Variant installer fetched ($(wc -c <"$tmp") bytes). Executing."
  bash "$tmp"
}

main "$@"
