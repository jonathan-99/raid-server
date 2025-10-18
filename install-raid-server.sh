#!/usr/bin/env bash
# Raspberry Pi RAID 1 Setup Script
# Executes on each target device.
# Uses helper scripts: device_updater.sh, firewall_setup.sh, raid_checks.sh
# Logs to /tmp/raid_target_<hostname>.log

set -euo pipefail

TARGET_HOSTNAME="$(hostname)"
LOG_FILE="/tmp/raid_target_${TARGET_HOSTNAME}.log"

mkdir -p "$(dirname "$LOG_FILE")"

log()   { printf "[%s] [INFO]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE"; }
warn()  { printf "[%s] [WARN]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; }
error() { printf "[%s] [ERROR] %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; exit 1; }

trap 'rc=$?; error "Script failed at line $LINENO. Exit code: $rc"; exit $rc' ERR

# --- Step 1: Run device updater ---
if [[ -x /tmp/device_updater.sh ]]; then
    log "Running device updater..."
    /tmp/device_updater.sh | stdbuf -oL tee -a "$LOG_FILE"
else
    warn "device_updater.sh not found or not executable."
fi

# --- Step 2: Run firewall setup ---
if [[ -x /tmp/firewall_setup.sh ]]; then
    log "Setting up firewall..."
    /tmp/firewall_setup.sh | stdbuf -oL tee -a "$LOG_FILE"
else
    warn "firewall_setup.sh not found or not executable."
fi

# --- Step 3: Run RAID checks ---
if [[ -x /tmp/raid_checks.sh ]]; then
    log "Performing pre-installation RAID checks..."
    /tmp/raid_checks.sh | stdbuf -oL tee -a "$LOG_FILE"
else
    warn "raid_checks.sh not found or not executable."
fi

# --- Step 4: RAID installation ---
if [[ -x /tmp/install-raid-server.sh ]]; then
    log "Running RAID installation..."
    /tmp/install-raid-server.sh | stdbuf -oL tee -a "$LOG_FILE"
else
    error "install-raid-server.sh not found or not executable."
fi

log "RAID setup completed successfully on ${TARGET_HOSTNAME}."
