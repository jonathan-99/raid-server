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
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
SUMMARY_FILE="$LOG_DIR/raid_install_summary.csv"

require_files() {
  [[ -f "$SCRIPT_DIR/$INSTALL_SCRIPT_NAME" ]] || {
    error "Missing required file: $SCRIPT_DIR/$INSTALL_SCRIPT_NAME"
    exit 1
  }
}

get_remote_hostname() {
  local ip="$1"
  ssh -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=5 "${SSH_USER}@${ip}" "hostname" 2>/dev/null || echo "$ip"
}

run_full_install() {
  local ip="$1"
  local remote_tmp="/tmp/${INSTALL_SCRIPT_NAME}"
  local hostname
  hostname="$(get_remote_hostname "$ip")"
  local log_file="$LOG_DIR/${hostname}_install.log"

  echo -e "${YELLOW}[$hostname] Starting installation...${NC}"
  {
    echo "===== RAID INSTALL START: $(date) ====="
    echo "Target Hostname: $hostname"
    echo "Target IP: $ip"
    echo
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
    echo -e "${GREEN}[$hostname] ✅ Installation succeeded.${NC}"
  else
    echo -e "${RED}[$hostname] ❌ Installation failed. See $log_file${NC}"
  fi

  echo "$hostname,$ip,$status,$log_file" >>"$SUMMARY_FILE"
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
  printf "%-15s | %-15s | %-10s | %-40s\n" "HOSTNAME" "IP" "STATUS" "LOG FILE"
  echo "----------------------------------------------------------------------------------------------------"

  while IFS=, read -r hostname ip status logfile; do
    if [[ "$status" -eq 0 ]]; then
      printf "%-15s | %-15s | ${GREEN}%-10s${NC} | %s\n" "$hostname" "$ip" "SUCCESS" "$logfile"
    else
      printf "%-15s | %-15s | ${RED}%-10s${NC} | %s\n" "$hostname" "$ip" "FAILED" "$logfile"
    fi
  done <"$SUMMARY_FILE"

  echo "===================================================================================================="
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

  # 1️⃣ Run SSH setup script first
  log "Running SSH setup verification for all targets..."
  "$SCRIPT_DIR/ssh_setup.sh" "${targets[@]}"

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
  rm -f "$SUMMARY_FILE"

  log "Starting RAID installations on ${#targets[@]} devices (max $MAX_PARALLEL parallel)..."

  local count=0
  for ip in "${targets[@]}"; do
    run_full_install "$ip" &
    ((++count >= MAX_PARALLEL)) && wait -n && ((count--))
  done

  wait
  draw_summary_table
}

main "$@"
