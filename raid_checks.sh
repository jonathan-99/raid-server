#!/usr/bin/env bash
# RAID pre-installation checks

set -euo pipefail

TARGET_HOSTNAME="$(hostname)"
LOG_FILE="/tmp/raid_target_${TARGET_HOSTNAME}.log"

log()   { printf "[%s] [INFO]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE"; }
warn()  { printf "[%s] [WARN]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; }
error() { printf "[%s] [ERROR] %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; exit 1; }

log "Listing available block devices..."
lsblk | stdbuf -oL tee -a "$LOG_FILE"

log "Checking if at least 2 candidate devices exist for RAID..."
NUM_DISKS=$(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print $1}' | wc -l)
if [[ "$NUM_DISKS" -lt 2 ]]; then
    error "Insufficient block devices for RAID. Found only $NUM_DISKS."
fi

log "RAID checks completed successfully."
