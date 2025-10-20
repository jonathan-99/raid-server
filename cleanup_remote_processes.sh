#!/usr/bin/env bash
# ============================================================
# cleanup_remote_processes.sh
# ------------------------------------------------------------
# ROLE:
#   Cleans up leftover RAID orchestration processes and temporary scripts.
#   Designed to be executed remotely via SSH or locally on the target.
#
# DEPENDENCIES:
#   None (uses standard Bash and sudo)
#
# LOGGING:
#   Outputs to stdout/stderr for orchestration script capture
# ============================================================

set -uo pipefail  # remove 'e' to avoid exit on minor issues

TARGET_HOSTNAME="$(hostname)"
LOG_FILE="/tmp/cleanup_remote_${TARGET_HOSTNAME}.log"

# --- Logging functions ---
log()   { printf "[%s] [INFO]  %s\n" "$TARGET_HOSTNAME" "$*"; }
warn()  { printf "[%s] [WARN]  %s\n" "$TARGET_HOSTNAME" "$*" >&2; }

log "[cleanup] Starting cleanup of old RAID processes and temp files..."

# --- Step 1: Kill leftover RAID orchestration processes ---
PROCESSES_TO_KILL=(
    "/tmp/install_raid_server.sh"
    "/tmp/install_raid_target.sh"
    "/tmp/device_updater.sh"
    "/tmp/firewall_setup.sh"
    "/tmp/raid_checks.sh"
    "/tmp/cleanup_remote_processes.sh"
    "/tmp/install_raid_orchestration.sh"
    "/tmp/test_script.sh"
    "/tmp/ssh_setup.sh"
    "/tmp/mdadm_creation.log"    
    "/tmp/raid_target_one.log"
)

for proc in "${PROCESSES_TO_KILL[@]}"; do
    if pgrep -f "$proc" >/dev/null 2>&1; then
        log "[CLEANUP] Killing process: $proc"
        sudo pkill -f "$proc" || warn "Failed to kill $proc (may not exist)"
    else
        log "No running process found for: $proc"
    fi
done

# --- Step 2: Remove temporary scripts ---
TMP_FILES=(
    "/tmp/install_raid_server.sh"
    "/tmp/install_raid_target.sh"
    "/tmp/device_updater.sh"
    "/tmp/firewall_setup.sh"
    "/tmp/raid_checks.sh"
    "/tmp/cleanup_remote_processes.sh"
    "/tmp/install_raid_orchestration.sh"
    "/tmp/ssh_setup"
    "/tmp/test_script"
    "/tmp/raid_installer.sh"
    "/tmp/raid_server_manager.sh"
)

for file in "${TMP_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        sudo rm -f "$file" && log "[CLEANUP] Removed temporary file: $file" \
            || warn "Failed to remove $file"
    else
        log "[cleanup] No temporary file found: $file"
    fi
done

log "[cleanup] Cleanup completed successfully on ${TARGET_HOSTNAME}."
