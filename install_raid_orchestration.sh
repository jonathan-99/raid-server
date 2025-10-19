#!/usr/bin/env bash
# ============================================================
# install_raid_orchestration.sh
# ------------------------------------------------------------
# ROLE:
#   Orchestrates RAID installations across multiple Raspberry Pi targets.
#   Handles SSH verification, script distribution, cleanup, and execution.
#
# EXECUTION:
#   ./install_raid_orchestration.sh one two three
#
# DEPENDENCIES:
#   - ssh_setup.sh
#   - install_raid_target.sh
#   - install_raid_server.sh
#   - device_updater.sh, firewall_setup.sh, raid_checks.sh
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
SCRIPTS_DIR="/home/pinas/raid-server"

# --- Script file names (centralized) ---
SCRIPT_INSTALL_TARGET="install_raid_target.sh"
SCRIPT_INSTALL_RAID="install_raid_server.sh"
SCRIPT_DEVICE_UPDATER="device_updater.sh"
SCRIPT_FIREWALL_SETUP="firewall_setup.sh"
SCRIPT_RAID_CHECKS="raid_checks.sh"
SCRIPT_CLEANUP="cleanup_remote_processes.sh"

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
printf "HOSTNAME,IP,STATUS,LOG FILE\n" > "$SUMMARY_FILE"

# --- Cleanup function ---
cleanup_remote() {
    local target="$1"
    ssh -p "$SSH_PORT" "${SSH_USER}@${target}" "bash -s" < "$SCRIPTS_DIR/$SCRIPT_CLEANUP"
}

# --- Function to copy a single script ---
copy_script() {
    local target="$1"
    local script="$2"
    local target_log="$3"

    # log "[${target}] Copying ${script} to /tmp..."
    if scp -P "$SSH_PORT" "$SCRIPTS_DIR/$script" "${SSH_USER}@${target}:/tmp/" >>"$target_log" 2>&1; then
        ssh -p "$SSH_PORT" "${SSH_USER}@${target}" "sudo chmod +x /tmp/${script}" \
            || error "[${target}] Failed to set executable permission on ${script}!"
        # log "[${target}] ${script} copied and chmod +x successfully."
    else
        error "[${target}] Failed to copy ${script}!"
    fi
}

# --- Start orchestration ---
log "Preparing RAID installation orchestration for ${#TARGETS[@]} targets..."

for target in "${TARGETS[@]}"; do
    TARGET_LOG="${LOG_DIR}/install_${target}.log"
    echo "--------------------------------------------------------------------------------" | tee -a "$TARGET_LOG"
    log "Processing target: ${target}"

    # 1️⃣ Pre-cleanup
    log "[${target}] Performing pre-cleanup..."
    cleanup_remote "$target"

    # 2️⃣ Copy required scripts (one at a time)
    copy_script "$target" "$SCRIPT_INSTALL_TARGET" "$TARGET_LOG"
    copy_script "$target" "$SCRIPT_INSTALL_RAID" "$TARGET_LOG"
    copy_script "$target" "$SCRIPT_DEVICE_UPDATER" "$TARGET_LOG"
    copy_script "$target" "$SCRIPT_FIREWALL_SETUP" "$TARGET_LOG"
    copy_script "$target" "$SCRIPT_RAID_CHECKS" "$TARGET_LOG"
    copy_script "$target" "$SCRIPT_CLEANUP" "$TARGET_LOG"

    # 3️⃣ Run installation remotely (tee as root)
    log "[${target}] Executing RAID target installer..."
    ssh -p "$SSH_PORT" "${SSH_USER}@${target}" \
    "sudo touch /tmp/raid_target_${target}.log && sudo chown root:root /tmp/raid_target_${target}.log && sudo chmod 666 /tmp/raid_target_${target}.log"

    ssh -p "$SSH_PORT" "${SSH_USER}@${target}" \
        "sudo bash -c '/tmp/${SCRIPT_INSTALL_TARGET} | tee -a /tmp/raid_target_${target}.log'"



    STATUS=$?
    RESULT=$([[ $STATUS -eq 0 ]] && echo "SUCCESS" || echo "FAILURE")

    # 4️⃣ Post-cleanup
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
