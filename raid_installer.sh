#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/var/log/raid_setup.log"

log()   { printf '[RAID] [INFO]  %s\n' "$*" | tee -a "$LOG_FILE"; }
warn()  { printf '[RAID] [WARN]  %s\n' "$*" | tee -a "$LOG_FILE" >&2; }
error() { printf '[RAID] [ERROR] %s\n' "$*" | tee -a "$LOG_FILE" >&2; }

format_and_mount_drive() {
    local device_path="$1" mount_point="$2"
    log "Formatting $device_path as ext4..."
    sudo mkfs.ext4 -F -v -m 0.1 "$device_path" | tee -a "$LOG_FILE"

    log "Mounting $device_path at $mount_point..."
    sudo mkdir -p "$mount_point"
    sudo mount "$device_path" "$mount_point" || warn "$mount_point already mounted."

    local uuid
    uuid="$(sudo blkid -s UUID -o value "$device_path" 2>/dev/null || true)"
    [[ -n "$uuid" ]] && echo "UUID=$uuid  $mount_point  ext4  defaults,noatime  0  2" | sudo tee -a /etc/fstab >/dev/null
}

create_raid() {
    local d1="$1" d2="$2" raid_dev="/dev/md0"
    log "Creating RAID1 array at $raid_dev with $d1 and $d2"
    sudo modprobe md_mod || true
    sudo mdadm --stop "$raid_dev" >/dev/null 2>&1 || true
    sudo mdadm --zero-superblock --force "$d1" "$d2" || true
    sudo mdadm --create --verbose "$raid_dev" --level=1 --raid-devices=2 "$d1" "$d2" | tee -a "$LOG_FILE"

    sleep 3
    cat /proc/mdstat | tee -a "$LOG_FILE"
    sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf >/dev/null
    sudo update-initramfs -u || warn "initramfs update failed."

    format_and_mount_drive "$raid_dev" "/mnt/raid"
    log "RAID setup complete."
}

main() {
    if [[ $# -lt 2 ]]; then
        error "Usage: $0 <disk1> <disk2>"
        exit 1
    fi
    create_raid "$1" "$2"
}

main "$@"
