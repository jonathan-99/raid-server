#!/usr/bin/env bash
# Raspberry Pi RAID 1 Setup Script
# Executes on each target device.
# Uses helper scripts: device_updater.sh, firewall_setup.sh, raid_checks.sh, install-raid-server.sh
# Logs to /tmp/raid_target_<hostname>.log

set -euo pipefail

# --- Script paths ---
DEVICE_UPDATER="/tmp/device_updater.sh"
FIREWALL_SETUP="/tmp/firewall_setup.sh"
RAID_CHECKS="/tmp/raid_checks.sh"
RAID_INSTALL="/tmp/install-raid-server.sh"

# --- Logging ---
TARGET_HOSTNAME="$(hostname)"
LOG_FILE="/tmp/raid_target_${TARGET_HOSTNAME}.log"
mkdir -p "$(dirname "$LOG_FILE")"

log()   { printf "[%s] [INFO]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE"; }
warn()  { printf "[%s] [WARN]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; }
error() { printf "[%s] [ERROR] %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; exit 1; }

trap 'rc=$?; error "Script failed at line $LINENO. Exit code: $rc"; exit $rc' ERR

# --- Step 1: Run device updater ---
if [[ -x "$DEVICE_UPDATER" ]]; then
    log "Running device updater..."
    "$DEVICE_UPDATER" | stdbuf -oL tee -a "$LOG_FILE"
else
    warn "device_updater.sh not found or not executable."
fi

# --- Step 2: Run firewall setup ---
if [[ -x "$FIREWALL_SETUP" ]]; then
    log "Setting up firewall..."
    "$FIREWALL_SETUP" | stdbuf -oL tee -a "$LOG_FILE"
else
    warn "firewall_setup.sh not found or not executable."
fi

# --- Step 3: Run RAID checks ---
if [[ -x "$RAID_CHECKS" ]]; then
    log "Performing pre-installation RAID checks..."
    "$RAID_CHECKS" | stdbuf -oL tee -a "$LOG_FILE"
else
    warn "raid_checks.sh not found or not executable."
fi

# --- Step 4: RAID installation ---
if [[ -x "$RAID_INSTALL" ]]; then
    log "Running RAID installation..."
    "$RAID_INSTALL" | stdbuf -oL tee -a "$LOG_FILE"
else
    error "install-raid-server.sh not found or not executable."
fi

log "RAID setup completed successfully on ${TARGET_HOSTNAME}."
