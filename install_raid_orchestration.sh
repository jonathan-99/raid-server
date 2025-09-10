#!/usr/bin/env bash
# Orchestrator for Raspberry Pi RAID setup from a jumpbox.
# - You will chmod +x this script on the jumpbox.
# - Other scripts (like install-raid-server.sh) need not be executable locally;
#   this orchestrator will copy them to the target and chmod/execute remotely.

set -euo pipefail

# Defaults
SSH_USER="pi"
SSH_PORT="22"

# Files expected to be in the SAME DIRECTORY as this orchestrator
INSTALL_SCRIPT_NAME="install-raid-server.sh"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") <TARGET_IP> [--return-usb-devices] [--user <user>] [--port <port>] [--help]

Examples:
  # Run full RAID setup remotely on 192.168.1.50
  $(basename "$0") 192.168.1.50

  # Only list USB disk devices (read-only) on the target
  $(basename "$0") 192.168.1.50 --return-usb-devices

  # Specify SSH user and port
  $(basename "$0") 192.168.1.50 --user ubuntu --port 2222

Args:
  <TARGET_IP>                 IP address (or hostname) of the Raspberry Pi target.

Flags:
  --return-usb-devices        Print registered USB disk devices on the target (one per line), then exit.
  --user <user>               SSH username (default: pi).
  --port <port>               SSH port (default: 22).
  --help                      Show this help.

Notes:
  * This script runs on the jumpbox.
  * All project scripts should be in the same directory as this file.
  * The install script will be copied to the target and executed with sudo.
EOF
}

log()   { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

# Locate script dir (so we can SCP sibling files)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_files() {
  local missing=0
  for f in "$SCRIPT_DIR/$INSTALL_SCRIPT_NAME"; do
    if [[ ! -f "$f" ]]; then
      error "Missing required file: $f"
      missing=1
    fi
  done
  if [[ $missing -ne 0 ]]; then
    exit 1
  fi
}

# Return 0 if SSH is reachable
check_ssh() {
  local ip="$1"
  if ! timeout 5 bash -c "</dev/tcp/${ip}/${SSH_PORT}" >/dev/null 2>&1; then
    warn "TCP ${ip}:${SSH_PORT} not immediately reachable; continuing to try SSH anyway..."
  fi
  if ! ssh -o BatchMode=yes -o ConnectTimeout=8 -p "$SSH_PORT" "${SSH_USER}@${ip}" 'true' 2>/dev/null; then
    warn "Passwordless SSH may not be configured. You may be prompted for password or key passphrase."
  fi
}

# Copy and execute install script remotely
run_full_install() {
  local ip="$1"
  local remote_tmp="/tmp/${INSTALL_SCRIPT_NAME}"

  log "Copying ${INSTALL_SCRIPT_NAME} to ${ip}:${remote_tmp}"
  scp -P "$SSH_PORT" "$SCRIPT_DIR/$INSTALL_SCRIPT_NAME" "${SSH_USER}@${ip}:${remote_tmp}"

  log "Setting execute bit and running install on ${ip}..."
  # shellcheck disable=SC2029
  ssh -t -p "$SSH_PORT" "${SSH_USER}@${ip}" bash -lc "
    set -euo pipefail
    sudo chmod +x '${remote_tmp}'
    sudo '${remote_tmp}'
  "
  log "Install completed on ${ip}."
}

# Remote, read-only listing of USB disk devices
remote_list_usb_disks() {
  local ip="$1"
  # This command prefers lsblk TRAN; falls back to sysfs
  # shellcheck disable=SC2029
  ssh -p "$SSH_PORT" "${SSH_USER}@${ip}" bash -lc '
    set -euo pipefail
    if lsblk -ndo NAME,TYPE,TRAN >/dev/null 2>&1; then
      lsblk -ndo NAME,TYPE,TRAN | awk '"'"'$2=="disk" && $3=="usb"{print "/dev/"$1}'"'"'
    else
      for d in /sys/block/*; do
        name="$(basename "$d")"
        [[ "$name" == loop* || "$name" == ram* ]] && continue
        if readlink -f "$d" | grep -qi "/usb"; then
          echo "/dev/$name"
        fi
      done
    fi
  '
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 2
  fi

  local target_ip="$1"; shift || true
  local MODE="install"  # default behavior: run full install on target

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --return-usb-devices)
        MODE="list_usb"
        shift
        ;;
      --user)
        SSH_USER="${2:-}"; shift 2 || { error "--user requires a value"; exit 2; }
        ;;
      --port)
        SSH_PORT="${2:-}"; shift 2 || { error "--port requires a value"; exit 2; }
        ;;
      --help|-h)
        usage; exit 0 ;;
      *)
        error "Unknown argument: $1"; usage; exit 2 ;;
    esac
  done

  require_files
  check_ssh "$target_ip"

  if [[ "$MODE" == "list_usb" ]]; then
    log "Querying USB disk devices on ${target_ip}..."
    remote_list_usb_disks "$target_ip"
    exit 0
  fi

  # Default: copy and run install script on target
  run_full_install "$target_ip"
}

main "$@"
