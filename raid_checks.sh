#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/var/log/raid_setup.log"

log()   { printf '[CHECKS] [INFO]  %s\n' "$*" | tee -a "$LOG_FILE"; }
error() { printf '[CHECKS] [ERROR] %s\n' "$*" | tee -a "$LOG_FILE" >&2; }

log "Running system pre-checks..."

if [[ $(uname -s) != "Linux" ]]; then
    error "Not a Linux system."
    exit 1
fi
if ! sudo -n true 2>/dev/null; then
    error "User lacks sudo privileges."
    exit 1
fi
if [[ "$(hostname)" == "jumpbox" ]]; then
    error "Script must not run on jumpbox."
    exit 1
fi

log "Pre-checks passed. Enumerating block devices..."
root_disk="$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null || true)"
devices=$(lsblk -ndo NAME,TYPE,TRAN | awk -v rd="$root_disk" '$2=="disk" && $1!=rd {print "/dev/"$1}')

if [[ -z "$devices" ]]; then
    error "No available block devices found."
    exit 1
fi

log "Found candidate disks:"
echo "$devices" | tee -a "$LOG_FILE"
