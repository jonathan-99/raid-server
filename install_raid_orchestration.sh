#!/usr/bin/env bash
# Multi-target orchestrator for Raspberry Pi RAID setup.
# Supports simultaneous installation with aggregated summary and per-device logging.

set -euo pipefail

SSH_USER="pi"
SSH_PORT="22"
INSTALL_SCRIPT_NAME="install-raid-server.sh"
MAX_PARALLEL=3

# --- Color codes ---
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
NC="\033[0m"  # No color

usage() {
  cat <<EOF
Usage:
  $(basename "$0") <TARGET_IP> [TARGET_IP ...] [options]

Examples:
  # Install RAID on 3 devices simultaneously
  $(basename "$0") 192.168.3.101 192.168.3.102 192.168.3.103

  # Just list USB disks on one device
  $(basename "$0") 192.168.3.101 --return-usb-devices

Options:
  --return-usb-devices        List USB disks on one target only.
  --user <user>               SSH username (default: pi)
  --port <port>               SSH port (default: 22)
  --max-parallel <n>          Limit concurrent installations (default: 3)
  --help                      Show this help message
EOF
}

log()   { echo -e "[INFO]  $*"; }
warn()  { echo -e "${YELLOW}[WARN]  $*${NC}" >&2; }
error() { echo -e "${RED}[ERROR] $*${NC}" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_files() {
  [[ -f "$SCRIPT_DIR/$INSTALL_SCRIPT_NAME" ]] || {
    error "Missing required file: $SCRIPT_DIR/$INSTALL_SCRIPT_NAME"
    exit 1
  }
}

check_ssh() {
  local ip="$1"
  if ! ssh -o BatchMode=yes -o ConnectTimeout=8 -p "$SSH_PORT" "${SSH_USER}@${ip}" 'true' 2>/dev/null; then
    warn "SSH to $ip may require password or key passphrase."
  fi
}

run_full_install() {
  local ip="$1"
  local remote_tmp="/tmp/${INSTALL_SCRIPT_NAME}"
  local log_file="/tmp/raid_install_${ip}.log"

  echo -e "${YELLOW}[$ip] Starting installation...${NC}"
  {
    echo "===== RAID INSTALL START: $(date) ====="
    echo "Target: $ip"
  } >"$log_file"

  {
    echo "[INFO] Copying install script..."
    scp -q -P "$SSH_PORT" "$SCRIPT_DIR/$INSTALL_SCRIPT_NAME" "${SSH_USER}@${ip}:${remote_tmp}"

    echo "[INFO] Running remote installation..."
    ssh -t -p "$SSH_PORT" "${SSH_USER}@${ip}" bash -lc "
      set -euo pipefail
      sudo chmod +x '${remote_tmp}'
      sudo '${remote_tmp}'
    "

    echo "[INFO] Installation completed successfully."
  } >>"$log_file" 2>&1

  local status=$?
  if [[ $status -eq 0 ]]; then
    echo -e "${GREEN}[$ip] ✅ Installation succeeded.${NC}"
  else
    echo -e "${RED}[$ip] ❌ Installation failed. See $log_file${NC}"
  fi
  echo "$ip,$status" >>/tmp/raid_install_summary.csv
}

remote_list_usb_disks() {
  local ip="$1"
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

draw_summary_table() {
  echo
  echo "========= RAID INSTALL SUMMARY ========="
  printf "%-15s | %-10s | %-30s\n" "DEVICE" "STATUS" "LOG FILE"
  echo "----------------------------------------"

  while IFS=, read -r ip status; do
    if [[ "$status" -eq 0 ]]; then
      printf "%-15s | ${GREEN}%-10s${NC} | %s\n" "$ip" "SUCCESS" "/tmp/raid_install_${ip}.log"
    else
      printf "%-15s | ${RED}%-10s${NC} | %s\n" "$ip" "FAILED" "/tmp/raid_install_${ip}.log"
    fi
  done </tmp/raid_install_summary.csv

  echo "========================================"
}

main() {
  if [[ $# -lt 1 ]]; then usage; exit 2; fi

  local MODE="install"
  local targets=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --return-usb-devices) MODE="list_usb"; shift ;;
      --user) SSH_USER="${2:-}"; shift 2 ;;
      --port) SSH_PORT="${2:-}"; shift 2 ;;
      --max-parallel) MAX_PARALLEL="${2:-3}"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *)
        if [[ "$1" == -* ]]; then
          error "Unknown option: $1"; usage; exit 2
        fi
        targets+=("$1"); shift
        ;;
    esac
  done

  if [[ ${#targets[@]} -eq 0 ]]; then
    error "No target IPs provided."; usage; exit 2
  fi

  require_files

  # Single-device USB listing mode
  if [[ "$MODE" == "list_usb" ]]; then
    if [[ ${#targets[@]} -ne 1 ]]; then
      error "--return-usb-devices must be used with exactly one target."
      exit 2
    fi
    local ip="${targets[0]}"
    log "Querying USB disks on $ip..."
    remote_list_usb_disks "$ip"
    exit 0
  fi

  # Clean previous summary
  rm -f /tmp/raid_install_summary.csv

  log "Starting RAID installations on ${#targets[@]} devices (max $MAX_PARALLEL parallel)..."

  # Run in parallel
  for ip in "${targets[@]}"; do
    check_ssh "$ip"
    run_full_install "$ip" &
    ((++count >= MAX_PARALLEL)) && wait -n && ((count--))
  done

  wait
  draw_summary_table
}

main "$@"
