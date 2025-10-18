#!/usr/bin/env bash
# Multi-target orchestrator for Raspberry Pi RAID setup.
# Supports simultaneous installation with aggregated summary and per-device logging.
# Logs use the target hostname, not the jumpbox hostname.

set -euo pipefail

SSH_USER="pi"
SSH_PORT="22"
INSTALL_SCRIPT_NAME="raid_server_manager.sh"  # now runs all local scripts
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

get_remote_hostname() {
  local ip="$1"
  ssh -o ConnectTimeout=5 -p "$SSH_PORT" "${SSH_USER}@${ip}" 'hostname' 2>/dev/null || echo "$ip"
}

run_full_install() {
  local ip="$1"
  local hostname
  hostname="$(get_remote_hostname "$ip")"
  local remote_tmp="/tmp/${INSTALL_SCRIPT_NAME}"
  local local_log="${SCRIPT_DIR}/install_${hostname}.log"

  echo -e "${YELLOW}[${hostname}] Starting installation...${NC}"
  {
    echo "===== RAID INSTALL START: $(date) ====="
    echo "Target: ${hostname} (${ip})"
  } >"$local_log"

  {
    echo "[${hostname}] Copying orchestration script..."
    scp -q -P "$SSH_PORT" "$SCRIPT_DIR"/*.sh "${SSH_USER}@${ip}:/tmp/"

    echo "[${hostname}] Running remote RAID setup..."
    ssh -t -p "$SSH_PORT" "${SSH_USER}@${ip}" bash -lc "
      set -euo pipefail
      cd /tmp
      sudo chmod +x ${INSTALL_SCRIPT_NAME}
      sudo ./${INSTALL_SCRIPT_NAME}
    "

    echo "[${hostname}] Installation completed successfully."
  } >>"$local_log" 2>&1

  local status=$?
  if [[ $status -eq 0 ]]; then
    echo -e "${GREEN}[${hostname}] ✅ Installation succeeded.${NC}"
  else
    echo -e "${RED}[${hostname}] ❌ Installation failed. See ${local_log}${NC}"
  fi

  echo "${hostname},${ip},${status},${local_log}" >>"${SCRIPT_DIR}/raid_install_summary.csv"
}

remote_list_usb_disks() {
  local ip="$1"
  local hostname
  hostname="$(get_remote_hostname "$ip")"

  log "Querying USB disks on ${hostname} (${ip})..."
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
  printf "%-15s | %-15s | %-10s | %-35s\n" "HOSTNAME" "IP" "STATUS" "LOG FILE"
  echo "--------------------------------------------------------------------------"

  while IFS=, read -r hostname ip status logfile; do
    if [[ "$status" -eq 0 ]]; then
      printf "%-15s | %-15s | ${GREEN}%-10s${NC} | %s\n" "$hostname" "$ip" "SUCCESS" "$logfile"
    else
      printf "%-15s | %-15s | ${RED}%-10s${NC} | %s\n" "$hostname" "$ip" "FAILED" "$logfile"
    fi
  done <"${SCRIPT_DIR}/raid_install_summary.csv"

  echo "=========================================================================="
}

main() {
  if [[ $# -lt 1 ]]; then usage; exit 2; fi

  local MODE="install"
  local targets=()
  local count=0

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
    remote_list_usb_disks "${targets[0]}"
    exit 0
  fi

  # Clean previous summary
  rm -f "${SCRIPT_DIR}/raid_install_summary.csv"

  log "Starting RAID installations on ${#targets[@]} devices (max $MAX_PARALLEL parallel)..."

  for ip in "${targets[@]}"; do
    check_ssh "$ip"
    run_full_install "$ip" &
    ((++count >= MAX_PARALLEL)) && wait -n && ((count--))
  done

  wait
  draw_summary_table
}

main "$@"
