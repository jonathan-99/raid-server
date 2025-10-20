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
#   Logs:   ./logs/install_<hostname>.log
#   Summary: <RAID_DIR>/raid_install_summary.csv
# ============================================================

set -euo pipefail

# --- Configuration ---
SSH_USER="pi"
SSH_PORT=22
RAID_DIR="/home/pinas/raid-server"
LOG_DIR="${RAID_DIR}/logs"
SUMMARY_FILE="${RAID_DIR}/raid_install_summary.csv"
SCRIPTS_DIR="${RAID_DIR}"

# --- Script names ---
SCRIPT_INSTALL_TARGET="install_raid_target.sh"
SCRIPT_INSTALL_RAID="install-raid-server.sh"
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

# --- Check arguments ---
if [[ $# -lt 1 ]]; then
    error "Usage: $0 <target1> [target2 ...]"
fi
TARGETS=("$@")

# --- Utilities ---
get_host_ip() {
    ssh -p "$SSH_PORT" "${SSH_USER}@${1}" "hostname -I | awk '{print \$1}'" 2>/dev/null || echo "N/A"
}

cleanup_remote() {
    local target="$1"
    ssh -p "$SSH_PORT" "${SSH_USER}@${target}" "bash -s" < "$SCRIPTS_DIR/$SCRIPT_CLEANUP" >/dev/null 2>&1 || true
}

copy_script() {
    local target="$1"
    local script="$2"
    local target_log="$3"

    log "[${target}] Copying ${script} to /tmp..."
    if scp -P "$SSH_PORT" "$SCRIPTS_DIR/$script" "${SSH_USER}@${target}:/tmp/" >>"$target_log" 2>&1; then
        ssh -p "$SSH_PORT" "${SSH_USER}@${target}" "sudo chmod +x /tmp/${script}" >>"$target_log" 2>&1
        log "[${target}] ${script} copied successfully."
    else
        error "[${target}] Failed to copy ${script}!"
    fi
}

get_raid_devices() {
    local target="$1"
    ssh -p "$SSH_PORT" "${SSH_USER}@${target}" \
        "lsblk -ndo NAME,TYPE | awk '\$2==\"disk\" {print \"/dev/\"\$1}' | head -n 2 | tr '\n' ' '" 2>/dev/null || echo "N/A"
}

# --- Start orchestration ---
log "===== RAID INSTALL START: $(date) ====="
echo "HOSTNAME,IP,STATUS,RAID_DEVICES,MOUNT_POINT" > "$SUMMARY_FILE"
log "Preparing RAID installation orchestration for ${#TARGETS[@]} targets..."

for target in "${TARGETS[@]}"; do
    TARGET_LOG="${LOG_DIR}/install_${target}.log"
    echo "--------------------------------------------------------------------------------" | tee -a "$TARGET_LOG"
    log "Processing target: ${target}"

    # 1️⃣ Pre-cleanup
    log "[${target}] Performing pre-cleanup..."
    cleanup_remote "$target"

    # 2️⃣ Copy all scripts
    for script in \
        "$SCRIPT_INSTALL_TARGET" "$SCRIPT_INSTALL_RAID" "$SCRIPT_DEVICE_UPDATER" \
        "$SCRIPT_FIREWALL_SETUP" "$SCRIPT_RAID_CHECKS" "$SCRIPT_CLEANUP"; do
        copy_script "$target" "$script" "$TARGET_LOG"
    done

    # 3️⃣ Run remote installer
    log "[${target}] Executing RAID target installer..."
    if ssh -p "$SSH_PORT" "${SSH_USER}@${target}" \
        "sudo bash /tmp/${SCRIPT_INSTALL_TARGET} | sudo tee -a /tmp/raid_target_${target}.log"; then
        STATUS="SUCCESS"
    else
        STATUS="FAILURE"
    fi

    # 4️⃣ Post-cleanup
    cleanup_remote "$target"

    # 5️⃣ Gather details for summary
    IP_ADDR=$(get_host_ip "$target")
    RAID_DEVICES=$(get_raid_devices "$target")
    MOUNT_POINT=$(ssh -p "$SSH_PORT" "${SSH_USER}@${target}" \
        "grep -m1 'Mounting RAID at' /tmp/raid_target_${target}.log | awk '{print \$NF}'" 2>/dev/null)
    [[ -z "$MOUNT_POINT" ]] && MOUNT_POINT="/mnt/raid"

    printf "%s,%s,%s,%s,%s\n" "$target" "$IP_ADDR" "$STATUS" "$RAID_DEVICES" "$MOUNT_POINT" >> "$SUMMARY_FILE"
    log "[${target}] Installation ${STATUS}"
done

log "===== RAID INSTALL COMPLETE: $(date) ====="
log "Summary written to: $SUMMARY_FILE"
echo "----------------------------------------------------------------------------------------------------"
column -t -s, "$SUMMARY_FILE"
echo "===================================================================================================="
