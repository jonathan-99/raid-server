#!/usr/bin/env bash
# Multi-target Raspberry Pi RAID orchestrator
# Only this script needs chmod +x locally. Helpers are copied to target.

set -euo pipefail

SSH_USER="pi"
SSH_PORT="22"
MAX_PARALLEL=3
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# Helper scripts to copy to target
HELPER_SCRIPTS=("ssh_setup.sh" "device_updater.sh" "firewall_setup.sh" "raid_checks.sh" "install-raid-server.sh")

# Color codes
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

log()   { echo -e "[INFO]  $*"; }
warn()  { echo -e "${YELLOW}[WARN]  $*${NC}" >&2; }
error() { echo -e "${RED}[ERROR] $*${NC}" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") <TARGET_IP> [TARGET_IP ...] [options]

Options:
  --user <user>           SSH username (default: pi)
  --port <port>           SSH port (default: 22)
  --max-parallel <n>      Limit concurrent installations (default: 3)
  --help                  Show this help
EOF
}

check_ssh() {
    local ip="$1"
    ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$SSH_PORT" "${SSH_USER}@${ip}" "echo ok" >/dev/null 2>&1 || \
        warn "SSH to $ip may require password."
}

run_install_on_target() {
    local ip="$1"
    local target_log="$LOG_DIR/install_${ip}.log"
    local summary_csv="$LOG_DIR/raid_install_summary.csv"

    echo "===== RAID INSTALL START: $(date) =====" >"$target_log"
    echo "Target: $ip" >>"$target_log"

    log "[${ip}] Copying orchestration and helper scripts..."
    for script in "${HELPER_SCRIPTS[@]}"; do
        scp -q -P "$SSH_PORT" "$SCRIPT_DIR/$script" "${SSH_USER}@${ip}:/tmp/$script" >>"$target_log" 2>&1
        ssh -t -p "$SSH_PORT" "${SSH_USER}@${ip}" "chmod +x /tmp/$script" >>"$target_log" 2>&1
    done

    log "[${ip}] Running RAID setup..."
    ssh -t -p "$SSH_PORT" "${SSH_USER}@${ip}" "/tmp/install-raid-server.sh" >>"$target_log" 2>&1

    local status=$?
    echo "$ip,$status" >>"$summary_csv"

    if [[ $status -eq 0 ]]; then
        echo -e "${GREEN}[${ip}] ✅ Installation succeeded${NC}"
    else
        echo -e "${RED}[${ip}] ❌ Installation failed. See $target_log${NC}"
    fi
}

draw_summary_table() {
    local summary_csv="$LOG_DIR/raid_install_summary.csv"
    [[ -f "$summary_csv" ]] || { warn "No summary CSV found."; return; }

    echo
    echo "========= RAID INSTALL SUMMARY ========="
    printf "%-15s | %-10s | %-30s\n" "HOSTNAME/IP" "STATUS" "LOG FILE"
    echo "----------------------------------------"

    while IFS=, read -r ip status; do
        if [[ "$status" -eq 0 ]]; then
            printf "%-15s | ${GREEN}%-10s${NC} | %s\n" "$ip" "SUCCESS" "$LOG_DIR/install_${ip}.log"
        else
            printf "%-15s | ${RED}%-10s${NC} | %s\n" "$ip" "FAILED" "$LOG_DIR/install_${ip}.log"
        fi
    done <"$summary_csv"
    echo "========================================"
}

main() {
    [[ $# -lt 1 ]] && usage && exit 2

    local targets=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user) SSH_USER="${2:-}"; shift 2 ;;
            --port) SSH_PORT="${2:-}"; shift 2 ;;
            --max-parallel) MAX_PARALLEL="${2:-3}"; shift 2 ;;
            --help|-h) usage; exit 0 ;;
            *) targets+=("$1"); shift ;;
        esac
    done

    [[ ${#targets[@]} -eq 0 ]] && { error "No target IPs provided."; exit 2; }

    local summary_csv="$LOG_DIR/raid_install_summary.csv"
    >"$summary_csv"

    log "Running SSH checks..."
    for ip in "${targets[@]}"; do
        check_ssh "$ip"
    done

    log "Starting RAID installations on ${#targets[@]} targets (max $MAX_PARALLEL parallel)..."

    local count=0
    for ip in "${targets[@]}"; do
        run_install_on_target "$ip" &
        ((++count >= MAX_PARALLEL)) && wait -n && ((count--))
    done

    wait
    draw_summary_table
}

main "$@"
