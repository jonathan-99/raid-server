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

set -euo pipefail

TARGET_HOSTNAME="$(hostname)"
LOG_FILE="/tmp/cleanup_remote_${TARGET_HOSTNAME}.log"

# --- Logging functions ---
log()   { printf "[%s] [INFO]  %s\n" "$TARGET_HOSTNAME" "$*"; }
warn()  { printf "[%s] [WARN]  %s\n" "$TARGET_HOSTNAME" "$*" >&2; }
error() { printf "[%s] [ERROR] %s\n" "$TARGET_HOSTNAME" "$*" >&2; exit 1; }

trap 'rc=$?; error "Script failed at line $LINENO. Exit code: $rc"; exit $rc' ERR

log " [cleanup] Starting cleanup of old RAID processes and temp files..."

# --- Step 1: Kill leftover RAID orchestration processes ---
# Processes to target:
PROCESSES_TO_KILL=(
    "/tmp/install_raid_server.sh"
    "/tmp/install_raid_target.sh"
    "/tmp/device_updater.sh"
    "/tmp/firewall_setup.sh"
    "/tmp/raid_checks.sh"
)

for proc in "${PROCESSES_TO_KILL[@]}"; do
    if pgrep -f "$proc" >/dev/null 2>&1; then
        log "[CLEANUP] Killing process: $proc"
        sudo pkill -f "$proc" || warn "Failed to kill $proc (may not exist)"
    else
        # log "No running process found for: $proc"
    fi
done

# --- Step 2: Remove temporary scripts ---
TMP_FILES=(
    "/tmp/install-raid-server.sh"
    "/tmp/install_raid_target.sh"
    "/tmp/device_updater.sh"
    "/tmp/firewall_setup.sh"
    "/tmp/raid_checks.sh"
)

for file in "${TMP_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        # log " [cleanup] Removing temporary file: $file"
        sudo rm -f "$file" || warn "Failed to remove $file"
    else
        log "[cleanup]  No temporary file found: $file"
    fi
log "[CLEANUP] Removed temporary files"
done

log " [cleanup] Cleanup completed successfully on ${TARGET_HOSTNAME}."
