#!/usr/bin/env bash
# ============================================
# install_raid_server.sh
# --------------------------------------------
# ROLE: Executes the actual RAID 1 setup (mdadm, mounting, etc.)
# CALLED BY: install_raid_target.sh
# Logs to: /tmp/raid_target_<hostname>.log
# ============================================

set -euo pipefail

TARGET_HOSTNAME="$(hostname)"
LOG_FILE="/tmp/raid_target_${TARGET_HOSTNAME}.log"

log() { printf "[%s] [INFO]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE"; }
error() { printf "[%s] [ERROR] %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; exit 1; }

log "Starting RAID setup on ${TARGET_HOSTNAME}..."

# Example RAID creation (customize as needed)
RAID_DEVICE="/dev/md0"
DISK1="/dev/sda"
DISK2="/dev/sdc"
MOUNT_POINT="/mnt/raid1"

log "Creating RAID 1 array on ${DISK1} and ${DISK2}..."
if ! sudo mdadm --create --verbose "$RAID_DEVICE" --level=1 --raid-devices=2 "$DISK1" "$DISK2"; then
    error "Failed to create RAID 1 array."
fi

log "Formatting RAID device..."
sudo mkfs.ext4 -F "$RAID_DEVICE" || error "Formatting failed."

log "Creating mount point at ${MOUNT_POINT}..."
sudo mkdir -p "$MOUNT_POINT"
sudo mount "$RAID_DEVICE" "$MOUNT_POINT" || error "Mount failed."

log "Updating /etc/fstab..."
UUID=$(blkid -s UUID -o value "$RAID_DEVICE")
echo "UUID=${UUID} ${MOUNT_POINT} ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

log "RAID setup completed successfully."
