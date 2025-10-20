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

set -uo pipefail  # 'e' intentionally omitted to continue on minor errors

TARGET_HOSTNAME="$(hostname)"
LOG_FILE="/tmp/cleanup_remote_${TARGET_HOSTNAME}.log"

# --- Logging functions ---
log()   { printf "[%s] [INFO]  %s\n" "$TARGET_HOSTNAME" "$*"; }
warn()  { printf "[%s] [WARN]  %s\n" "$TARGET_HOSTNAME" "$*" >&2; }

log "[cleanup] Starting cleanup of old RAID processes and temp files..."

# --- Step 0: Stop mdadm and unmount if needed ---
if sudo pgrep mdadm >/dev/null 2>&1; then
    sudo pkill -9 mdadm && log "[CLEANUP] Killed mdadm processes." || warn "Failed to kill mdadm."
fi

if mount | grep -q '/mnt/raid'; then
    sudo umount -l /mnt/raid && log "[CLEANUP] Unmounted /mnt/raid." || warn "Failed to unmount /mnt/raid."
fi

if sudo mdadm --detail --scan | grep -q '/dev/md0'; then
    sudo mdadm --stop /dev/md0 && log "[CLEANUP] Stopped /dev/md0." || warn "Failed to stop /dev/md0."
    sudo mdadm --remove /dev/md0 && log "[CLEANUP] Removed /dev/md0." || warn "Failed to remove /dev/md0."
fi

# --- Step 1: Kill leftover RAID orchestration processes ---
PROCESSES_TO_KILL=(
    "install_raid_server.sh"
    "install_raid_target.sh"
    "device_updater.sh"
    "firewall_setup.sh"
    "raid_checks.sh"
    "cleanup_remote_processes.sh"
    "install_raid_orchestration.sh"
    "test_script.sh"
    "ssh_setup.sh"
)

for proc in "${PROCESSES_TO_KILL[@]}"; do
    if pgrep -f "$proc" >/dev/null 2>&1; then
        log "[CLEANUP] Killing process: $proc"
        sudo pkill -f "$proc" || warn "Failed to kill $proc (may not exist)"
    else
        log "No running process found for: $proc"
    fi
done

# --- Step 2: Remove temporary files ---
TMP_FILES=(
    "/tmp/install_raid_server.sh"
    "/tmp/install_raid_target.sh"
    "/tmp/device_updater.sh"
    "/tmp/firewall_setup.sh"
    "/tmp/raid_checks.sh"
    "/tmp/cleanup_remote_processes.sh"
    "/tmp/install_raid_orchestration.sh"
    "/tmp/raid_installer.sh"
    "/tmp/raid_server_manager.sh"
    "/tmp/test_script.sh"
    "/tmp/ssh_setup.sh"
    "/tmp/mdadm_creation.log"
    "/tmp/raid_target_${TARGET_HOSTNAME}.log"
)

for file in "${TMP_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        sudo rm -f "$file" && log "[CLEANUP] Removed temporary file: $file" \
            || warn "Failed to remove $file"
    else
        log "[cleanup] No temporary file found: $file"
    fi
done

# --- Step 3: General cleanup for any leftover scripts or logs ---
find /tmp -maxdepth 1 -type f -name "raid_target_*.log" -exec sudo rm -f {} \; 2>/dev/null
find /tmp -maxdepth 1 -type f -name "*.sh" -exec sudo rm -f {} \; 2>/dev/null

log "[cleanup] Cleanup completed successfully on ${TARGET_HOSTNAME}."
