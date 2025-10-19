#!/usr/bin/env bash
# ============================================================
# install_raid_orchestration.sh
# ------------------------------------------------------------
# ROLE:
#   Orchestrates RAID installations across multiple Raspberry Pi targets.
#   Handles SSH verification, script distribution, and parallel execution.
#
# EXECUTION:
#   ./install_raid_orchestration.sh one two three
#
# DEPENDENCIES:
#   - ssh_setup.sh  : Ensures passwordless SSH is configured
#   - install_raid_target.sh : Main per-target setup script
#   - install_raid_server.sh : Actual RAID creation logic
#   - device_updater.sh, firewall_setup.sh, raid_checks.sh : Helper scripts
#
# OUTPUT:
#   Logs in ./logs/install_<hostname>.log
#   Summary: ./logs/raid_install_summary.csv
# ============================================================

set -euo pipefail

# --- Configuration ---
SSH_USER="pi"
SSH_PORT=22
LOG_DIR="/home/pinas/raid-server/logs"
SUMMARY_FILE="${LOG_DIR}/raid_install_summary.csv"
CLEANUP_SCRIPT="/tmp/cleanup_remote_processes.sh"
SCRIPTS_DIR="/home/pinas/raid-server/scripts"

# --- Script file names (centralized) ---
SCRIPT_INSTALL_TARGET="install_raid_target.sh"
SCRIPT_INSTALL_RAID="install-raid-server.sh"
SCRIPT_DEVICE_UPDATER="device_updater.sh"
SCRIPT_FIREWALL_SETUP="firewall_setup.sh"
SCRIPT_RAID_CHECKS="raid_checks.sh"

# --- Ensure log directory exists ---
mkdir -p "$LOG_DIR"

# --- Helper functions ---
log()   { printf "[INFO]  %s\n" "$*"; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

trap 'rc=$?; error "Script failed at line $LINENO. Exit code: $rc"; exit $rc' ERR

# --- Arguments check ---
if [[ $# -lt 1 ]]; then
    error "Usage: $0 <target1> [target2 ...]"
fi
TARGETS=("$@")

log "===== RAID INSTALL START: $(date) ====="

# --- Cleanup function ---
cleanup_remote() {
    local target="$1"
    ssh -p "$SSH_PORT" "${SSH_USER}@${target}" "bash -s" <<'EOF'
        echo "[INFO] Cleaning up old RAID install processes and temp files..."
        sudo pkill -f "/tmp/install-raid-server.sh|/tmp/install_raid_target.sh|/tmp/device_updater.sh|/tmp/firewall_setup.sh|/tmp/raid_checks.sh" 2>/dev/null || true
        sudo rm -f /tmp/install-raid-server.sh /tmp/install_raid_target.sh /tmp/device_updater.sh /tmp/firewall_setup.sh /tmp/raid_checks.sh 2>/dev/null || true
EOF
}

# --- Start of orchestration ---
log "Preparing RAID installation orchestration for ${#TARGETS[@]} targets..."
printf "HOSTNAME,IP,STATUS,LOG FILE\n" > "$SUMMARY_FILE"

for target in "${TARGETS[@]}"; do
    TARGET_LOG="${LOG_DIR}/install_${target}.log"
    echo "--------------------------------------------------------------------------------" | tee -a "$TARGET_LOG"
    log "Processing target: ${target}"

    # 1️⃣ Initial cleanup
    log "[${target}] Performing pre-cleanup..."
    cleanup_remote "$target"

    # 2️⃣ Copy required scripts
    log "[${target}] Copying scripts to /tmp..."
    scp -P "$SSH_PORT" \
        "${SCRIPTS_DIR}/${SCRIPT_INSTALL_TARGET}" \
        "${SCRIPTS_DIR}/${SCRIPT_INSTALL_RAID}" \
        "${SCRIPTS_DIR}/${SCRIPT_DEVICE_UPDATER}" \
        "${SCRIPTS_DIR}/${SCRIPT_FIREWALL_SETUP}" \
        "${SCRIPTS_DIR}/${SCRIPT_RAID_CHECKS}" \
        "${SSH_USER}@${target}:/tmp/" >>"$TARGET_LOG" 2>&1

    # 3️⃣ Run installation remotely
    log "[${target}] Executing RAID target installer..."
    ssh -p "$SSH_PORT" "${SSH_USER}@${target}" "sudo bash /tmp/${SCRIPT_INSTALL_TARGET}" | tee -a "$TARGET_LOG"

    STATUS=$?
    if [[ $STATUS -eq 0 ]]; then
        RESULT="SUCCESS"
    else
        RESULT="FAILURE"
    fi

    # 4️⃣ Final cleanup
    log "[${target}] Performing post-cleanup..."
    cleanup_remote "$target"

    # 5️⃣ Capture IP and write summary
    IP_ADDR=$(ssh -p "$SSH_PORT" "${SSH_USER}@${target}" "hostname -I | awk '{print \$1}'" 2>/dev/null || echo "N/A")
    printf "%s,%s,%s,%s\n" "$target" "$IP_ADDR" "$RESULT" "$TARGET_LOG" >> "$SUMMARY_FILE"

    log "[${target}] Installation ${RESULT}"
done

log "===== RAID INSTALL COMPLETE: $(date) ====="
log "Summary written to: $SUMMARY_FILE"
echo "----------------------------------------------------------------------------------------------------"
column -t -s, "$SUMMARY_FILE"


printf "========================================\n"
