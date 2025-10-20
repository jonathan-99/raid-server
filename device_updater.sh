#!/usr/bin/env bash
# ============================================================
# device_updater.sh
# ------------------------------------------------------------
# ROLE:
#   Updates OS packages and installs prerequisites for RAID target.
#   Detects if RAID already exists and exits early if so.
# ============================================================

set -euo pipefail

TARGET_HOSTNAME="$(hostname)"
LOG_FILE="/tmp/raid_target_${TARGET_HOSTNAME}.log"

log()   { printf "[%s] [INFO]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE"; }
warn()  { printf "[%s] [WARN]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; }
error() { printf "[%s] [ERROR] %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; exit 1; }

log "Starting device updater on ${TARGET_HOSTNAME}..."
log "Checking for existing RAID setup..."

# --- Step 0: Detect existing RAID ---
if command -v mdadm >/dev/null 2>&1; then
    if grep -q "/dev/md" /proc/mdstat 2>/dev/null; then
        if mountpoint -q /mnt/raid; then
            log "Existing RAID array and /mnt/raid mount detected — skipping installation."
            exit 0
        else
            warn "RAID array detected but /mnt/raid is not mounted — manual inspection advised."
            exit 0
        fi
    fi
fi

# --- Step 1: Update and upgrade system ---
log "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y | stdbuf -oL tee -a "$LOG_FILE"
sudo apt-get full-upgrade -y | stdbuf -oL tee -a "$LOG_FILE"

# --- Step 2: Install prerequisites ---
log "Installing prerequisites: mdadm, ufw, python3-pip, python3-venv..."
sudo apt-get install -y mdadm ufw python3-pip python3-venv --no-install-recommends \
  | stdbuf -oL tee -a "$LOG_FILE"

log "Device updater completed successfully."
