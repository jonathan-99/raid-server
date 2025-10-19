#!/usr/bin/env bash
# ============================================
# install_raid_target.sh
# --------------------------------------------
# OLD NAME: install_raid_server.sh
# NEW NAME: install_raid_target.sh
#
# ROLE: Executes setup steps locally on the target device.
# STEPS:
#   1. Run device updater
#   2. Run firewall setup
#   3. Run RAID pre-checks
#   4. Run the actual RAID installer (install_raid_server.sh)
#
# Logs to: /tmp/raid_target_<hostname>.log
# ============================================

set -euo pipefail

# --- Script references (centralized here for maintainability) ---
DEVICE_UPDATER="/tmp/device_updater.sh"
FIREWALL_SETUP="/tmp/firewall_setup.sh"
RAID_CHECKS="/tmp/raid_checks.sh"
RAID_INSTALLER="/tmp/install_raid_server.sh"

# --- Logging setup ---
TARGET_HOSTNAME="$(hostname)"
LOG_FILE="/tmp/raid_target_${TARGET_HOSTNAME}.log"
mkdir -p "$(dirname "$LOG_FILE")"

log()   { printf "[%s] [INFO]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE"; }
warn()  { printf "[%s] [WARN]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; }
error() { printf "[%s] [ERROR] %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; exit 1; }

trap 'rc=$?; error "Script failed at line $LINENO. Exit code: $rc"; exit $rc' ERR

log "===== RAID INSTALL START: $(date) ====="
log "Target: ${TARGET_HOSTNAME}"

# --- Step 1: Device updater ---
if [[ -x "$DEVICE_UPDATER" ]]; then
    log "Running device updater..."
    "$DEVICE_UPDATER" | stdbuf -oL tee -a "$LOG_FILE"
else
    warn "device_updater.sh not found or not executable."
fi

# --- Step 2: Firewall setup ---
if [[ -x "$FIREWALL_SETUP" ]]; then
    log "Setting up firewall..."
    "$FIREWALL_SETUP" | stdbuf -oL tee -a "$LOG_FILE"
else
    warn "firewall_setup.sh not found or not executable."
fi

# --- Step 3: RAID checks ---
if [[ -x "$RAID_CHECKS" ]]; then
    log "Performing pre-installation RAID checks..."
    "$RAID_CHECKS" | stdbuf -oL tee -a "$LOG_FILE"
else
    warn "raid_checks.sh not found or not executable."
fi

# --- Step 4: RAID installation ---
if [[ -x "$RAID_INSTALLER" ]]; then
    log "Running RAID installation..."
    "$RAID_INSTALLER" | stdbuf -oL tee -a "$LOG_FILE"
else
    error "install_raid_server.sh not found or not executable."
fi

log "RAID setup completed successfully on ${TARGET_HOSTNAME}."
