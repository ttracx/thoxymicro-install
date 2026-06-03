# thoxymicro-install

[![THOX.ai](https://img.shields.io/badge/THOX.ai-thoxymicro--install-1f6feb?style=flat-square)](https://thox.ai)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Status: Shipping](https://img.shields.io/badge/Status-Shipping-2da44e?style=flat-square)](#)
[![Hardware: Luckfox Pico Mini B](https://img.shields.io/badge/Hardware-Luckfox%20Pico%20Mini%20B-c51a4a?style=flat-square)](https://www.luckfox.com/Luckfox-Pico-Mini)
[![Shell: bash](https://img.shields.io/badge/Shell-bash-4eaa25?style=flat-square&logo=gnu-bash&logoColor=white)](#)
[![Variants: 3](https://img.shields.io/badge/Variants-3-8957e5?style=flat-square)](#one-liners)
[![Inventors: Craig Ross + Phamy Xaypanya](https://img.shields.io/badge/Inventors-C.%20Ross%20%2B%20P.%20Xaypanya-555?style=flat-square)](NOTICE)

> One-liner curl-pipe-bash installers for every ThoxyMicro variant. Drops the right binary, config, systemd unit (or busybox-init rc script), and creates the service user. Production-line ready.

This repository hosts the install scripts. The binaries themselves live as GitHub Release assets on the variant repositories ([ttracx/thoxymicro](https://github.com/ttracx/thoxymicro), [ttracx/thoxy-micro](https://github.com/ttracx/thoxy-micro), [ttracx/thoxymicro-edge](https://github.com/ttracx/thoxymicro-edge)).

## One-liners

> **Private-repo caveat.** All ThoxyMicro source repos are private. Curl-piped installers can only fetch release assets if either (a) this repo is flipped to public AND the source-repo release assets are public, or (b) the caller sets `THOXY_GITHUB_TOKEN` to a PAT with `repo` read on the private source repos. The scripts honor both modes.

### Full Go codebase (engineer / dev host)

```sh
curl -fsSL https://raw.githubusercontent.com/ttracx/thoxymicro-install/main/install.sh | \
  sudo VARIANT=thoxymicro bash
```

### Shipping daemon (firmware floor, ~5 MB ARMv7 binary)

```sh
curl -fsSL https://raw.githubusercontent.com/ttracx/thoxymicro-install/main/install.sh | \
  sudo VARIANT=thoxy-micro bash
```

### Edge agent with hub offload + RKNPU2 (production Luckfox Pico Mini B)

```sh
curl -fsSL https://raw.githubusercontent.com/ttracx/thoxymicro-install/main/install.sh | \
  sudo VARIANT=thoxymicro-edge \
       THOXY_HUB_URL=https://thoxy.your-tailnet.ts.net \
       THOXMINI_DEVICE_TOKEN=<bearer> \
       bash
```

### With THOX.ai branding and credentials

```sh
curl -fsSL https://raw.githubusercontent.com/ttracx/thoxymicro-install/main/install.sh | \
  sudo VARIANT=thoxymicro-edge \
       THOXY_HOSTNAME=thoxymicro-01 \
       THOXY_USER=thoxy \
       THOXY_USER_PW=thoxy-thoxy \
       THOXY_ROOT_PW=root-root \
       bash
```

### Pin to a specific release version

```sh
curl -fsSL https://raw.githubusercontent.com/ttracx/thoxymicro-install/main/install.sh | \
  sudo VARIANT=thoxy-micro THOXY_VERSION=v1.0.0 bash
```

### Factory provisioning (manufacturing line)

```sh
curl -fsSL https://install.thox.ai/thoxymicro | sudo bash
```

The short URL `install.thox.ai/thoxymicro` is a DNS redirect to [`factory/thoxmini-luckfox.sh`](factory/thoxmini-luckfox.sh) in this repo. The factory script:

- Locks `VARIANT=thoxymicro-edge`
- Generates a stable per-device hostname `thoxymicro-<YYMMDDhhmmss>`
- Reads hub URL from `/etc/thoxy-factory/hub.url` if present
- Reads device token from `/etc/thoxy-factory/device.token` if present
- Installs the OTA update helper at `/usr/local/sbin/thoxy-ota`
- Stages a weekly cron job (commented out by default)

### Without curl (private-repo gh-auth flow)

If you cannot make the install repo public:

```sh
gh auth login                              # one-time
gh repo clone ttracx/thoxymicro-install
cd thoxymicro-install
sudo VARIANT=thoxymicro-edge THOXY_GITHUB_TOKEN="$(gh auth token)" ./install.sh
```

## Environment variables

| Variable | Default | Used by | Meaning |
|---|---|---|---|
| `VARIANT` | (required) | router | `thoxymicro` / `thoxy-micro` / `thoxymicro-edge` |
| `THOXY_VERSION` | `latest` | all | Release tag to install |
| `THOXY_HOSTNAME` | (unset) | all | Sets system hostname before service start |
| `THOXY_USER` | `thoxy` | all | Service user (created if missing) |
| `THOXY_USER_PW` | (unset) | all | Password for `THOXY_USER` (none if unset) |
| `THOXY_ROOT_PW` | (unset) | all | Optional new root password |
| `THOXY_API_PORT` | `8787` / `8080` | all | HTTP API listen port |
| `THOXY_DATA_DIR` | `/var/lib/thoxymicro` | all | Per-device state dir |
| `THOXY_PREFIX` | `/usr/local` | all | Install prefix |
| `THOXY_HUB_URL` | (unset) | edge | Hub URL for chat-class offload |
| `THOXMINI_DEVICE_TOKEN` | (unset) | edge | Bearer token for the hub |
| `THOXY_GITHUB_TOKEN` | (unset) | all | PAT for private-repo release downloads |
| `THOXY_DRY_RUN` | `0` | router | Set to `1` to print actions without applying |
| `THOXY_INSTALL_RAW_BASE` | `raw.githubusercontent.com/ttracx/thoxymicro-install/main` | all | Override for self-hosted mirrors |

## What every installer does

1. Detect arch (`armv7` for Luckfox, `aarch64` / `amd64` accepted on the full codebase).
2. Detect OS (Debian/Buildroot/OpenWRT compatible).
3. Detect board via `/proc/device-tree/model` and `/proc/cpuinfo`.
4. Create the `thoxy` service user (idempotent).
5. Set hostname, root password, user password if requested.
6. Download the appropriate release asset (private-repo aware via `THOXY_GITHUB_TOKEN`).
7. Install the binary at `${THOXY_PREFIX}/bin/`.
8. Drop the variant-specific config under `/etc/thoxymicro/`.
9. Install the systemd unit (or busybox-init `S99` rc script if no systemd).
10. Enable the watchdog (`WatchdogSec=60`).
11. Start the service and poll `/health` for up to 20 seconds.
12. Print the standard THOX completion banner.

## Completion banner

```
===========================================
THOX.ai ThoxyMicro Installed
===========================================
Device:  ThoxyMicro prototype
Board:   Luckfox Pico Mini B
Variant: thoxymicro-edge
Version: v1.0.0

API:
  http://127.0.0.1:8787/health
  http://127.0.0.1:8787/status

Service:
  systemctl status thoxymicro
  journalctl -u thoxymicro -f

THOX.ai Ready
===========================================
```

## Repository layout

```
thoxymicro-install/
+- install.sh                       router; dispatches by VARIANT
+- lib/
|  +- common.sh                     shared primitives (detect_*, ensure_user, install_*, verify_health)
+- variants/
|  +- thoxymicro.sh                 full Go dev codebase
|  +- thoxy-micro.sh                shipping daemon (~5 MB ARMv7)
|  +- thoxymicro-edge.sh            edge agent with hub offload + RKNPU2
+- factory/
|  +- thoxmini-luckfox.sh           manufacturing-line composite installer
+- README.md
+- LICENSE                          MIT
+- NOTICE                           inventor attribution (Craig Ross + Phamy Xaypanya, IP-015-i)
```

## Variant routing

| `VARIANT=` | Source repo | Binary asset | Service name | Default port |
|---|---|---|---|---|
| `thoxymicro` | [ttracx/thoxymicro](https://github.com/ttracx/thoxymicro) | `thoxymicro-<arch>.tar.gz` | `thoxymicro.service` | 8080 |
| `thoxy-micro` | [ttracx/thoxy-micro](https://github.com/ttracx/thoxy-micro) | `thoxy-micro-linux-<arch>` | `thoxy-micro.service` | 8787 |
| `thoxymicro-edge` | [ttracx/thoxymicro-edge](https://github.com/ttracx/thoxymicro-edge) | `thoxymicro-edge-thoxmini-<arch>.tar.gz` | `thoxymicro.service` | 8787 |

## Hardware support matrix

| Board | SoC | Default variant |
|---|---|---|
| Luckfox Pico Mini B | Rockchip RV1103 | `thoxymicro-edge` |
| Generic ARMv7 Linux | varies | `thoxy-micro` |
| Generic aarch64 / amd64 Linux | varies | `thoxymicro` |

This is NOT a ThoxMini installer. ThoxMini canonical SoC remains Milk-V Duo. The ThoxyMicro family is a separate standalone Luckfox Pico Mini B prototype track.

## Naming and IP

Filed under THOX IP-015-i ("ThoxyMicro installer suite"). Inventors of record: Craig Ross and Phamy Xaypanya. See [NOTICE](NOTICE).

## License

MIT. See [LICENSE](LICENSE).

---

THOX.ai - Curl. Pipe. Boot. The whole installer fits in a tweet.
