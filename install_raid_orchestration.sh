#!/usr/bin/env bash
# Multi-target orchestrator for Raspberry Pi RAID setup.
# Supports simultaneous installation with aggregated summary and per-device logging.

set -euo pipefail

SSH_USER="pi"
SSH_PORT="22"
INSTALL_SCRIPT_NAME="install_raid_server.sh"
MAX_PARALLEL=3

# --- Color codes ---
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
NC="\033[0m"  # No color

# Set up scripts paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

SUMMARY_CSV="$LOG_DIR/raid_install_summary.csv"
# Clean previous summary
rm -f "$SUMMARY_CSV"


usage() {
  cat <<EOF
Usage:
  $(basename "$0") <TARGET_IP> [TARGET_IP ...] [options]

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

require_files() {
  local files=("$SCRIPT_DIR/$INSTALL_SCRIPT_NAME" "$SCRIPT_DIR/ssh_setup.sh" \
               "$SCRIPT_DIR/device_updater.sh" "$SCRIPT_DIR/firewall_setup.sh" "$SCRIPT_DIR/raid_checks.sh")
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || { error "Missing required file: $f"; exit 1; }
  done
}

check_ssh() {
  local ip="$1"
  if ! ssh -o BatchMode=yes -o ConnectTimeout=8 -p "$SSH_PORT" "${SSH_USER}@${ip}" 'true' 2>/dev/null; then
    warn "SSH to $ip may require password or key passphrase."
  fi
}

run_full_install() {
  local ip="$1"
  local log_file="$LOG_DIR/install_${ip}.log"
  echo "===== RAID INSTALL START: $(date) =====" >"$log_file"
  echo "Target: $ip" >>"$log_file"

  echo -e "${YELLOW}[$ip] Starting installation...${NC}"

  {
    # Step 1: Copy helper scripts to remote
    echo "[INFO] Copying orchestration and helper scripts..."
    scp -q -P "$SSH_PORT" "$SCRIPT_DIR/ssh_setup.sh" "${SSH_USER}@${ip}:/tmp/ssh_setup.sh"
    for script in device_updater.sh firewall_setup.sh raid_checks.sh "$INSTALL_SCRIPT_NAME"; do
      scp -q -P "$SSH_PORT" "$SCRIPT_DIR/$script" "${SSH_USER}@${ip}:/tmp/$script"
    done

    # Step 2: Run SSH setup on remote
    echo "[INFO] Running SSH setup on $ip..."
    ssh -p "$SSH_PORT" "${SSH_USER}@${ip}" bash -lc "chmod +x /tmp/ssh_setup.sh && /tmp/ssh_setup.sh"

    # Step 3: Run RAID installation on remote
    echo "[INFO] Running remote RAID setup..."
    ssh -t -p "$SSH_PORT" "${SSH_USER}@${ip}" bash -lc "
      set -euo pipefail
      for f in /tmp/device_updater.sh /tmp/firewall_setup.sh /tmp/raid_checks.sh /tmp/$INSTALL_SCRIPT_NAME; do
        [[ -x \$f ]] || chmod +x \$f
      done
      /tmp/$INSTALL_SCRIPT_NAME
    "

    echo "[INFO] Installation completed successfully."
  } | stdbuf -oL tee -a "$log_file"

  local status=${PIPESTATUS[0]}
  echo "$ip,$status" >>"$LOG_DIR/raid_install_summary.csv"

  if [[ $status -eq 0 ]]; then
    echo -e "${GREEN}[$ip] ✅ Installation succeeded.${NC}"
  else
    echo -e "${RED}[$ip] ❌ Installation failed. See $log_file${NC}"
  fi
}

draw_summary_table() {
  echo
  echo "========= RAID INSTALL SUMMARY ========="
  printf "%-15s | %-10s | %-40s\n" "HOSTNAME/IP" "STATUS" "LOG FILE"
  echo "----------------------------------------"
  while IFS=, read -r ip status; do
    local log_file="$LOG_DIR/install_${ip}.log"
    if [[ "$status" -eq 0 ]]; then
      printf "%-15s | ${GREEN}%-10s${NC} | %s\n" "$ip" "SUCCESS" "$log_file"
    else
      printf "%-15s | ${RED}%-10s${NC} | %s\n" "$ip" "FAILED" "$log_file"
    fi
  done <"$LOG_DIR/raid_install_summary.csv"
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
      --port) SSH_PORT="${2:-22}"; shift 2 ;;
      --max-parallel) MAX_PARALLEL="${2:-3}"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) targets+=("$1"); shift ;;
    esac
  done

  require_files

  # Clean previous summary
  rm -f "$LOG_DIR/raid_install_summary.csv"

  log "Running SSH setup verification for all targets..."
  for ip in "${targets[@]}"; do
    check_ssh "$ip"
  done

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
