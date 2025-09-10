#!/usr/bin/env bash
# Raspberry Pi RAID 1 Setup Script
# This script is copied and executed on the TARGET device by the orchestrator.
# It configures prerequisites, firewall, builds mdadm RAID1, formats, and mounts it.
# Logs to /var/log/raid_setup.log

set -euo pipefail

LOG_FILE="/var/log/raid_setup.log"

log()   { echo "[INFO]  $*" | tee -a "$LOG_FILE"; }
warn()  { echo "[WARN]  $*" | tee -a "$LOG_FILE"; }
error() { echo "[ERROR] $*" | tee -a "$LOG_FILE" >&2; }

# Trap unexpected errors
trap 'error "Script failed at line $LINENO. Exit code: $?"' ERR

install_prerequisites() {
    log "Checking and installing prerequisites..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -y           | tee -a "$LOG_FILE"
    sudo apt-get full-upgrade -y     | tee -a "$LOG_FILE"
    # Install mdadm non-interactively
    sudo apt-get install -y mdadm ufw python3-pip | tee -a "$LOG_FILE"

    # Useful Python tooling (optional)
    pip3 install --upgrade setuptools docker | tee -a "$LOG_FILE" || warn "pip3 optional installs failed or unavailable."
}

pre_checks() {
    if [[ $(uname -s) != "Linux" ]]; then
        error "This script is only intended to run on Linux."
        exit 1
    fi
    if ! sudo -n true 2>/dev/null; then
        error "You must have sudo privileges to run this script."
        exit 1
    fi
    log "Pre-checks passed."
}

setting_unit_firewall_rules() {
    log "Configuring UFW firewall rules..."
    sudo ufw allow ssh || true
    sudo ufw allow 80  || true
    sudo ufw allow 443 || true
    sudo ufw allow 3142 || true

    # Disable IPv6 for UFW (optional)
    if grep -q "^IPV6=" /etc/default/ufw; then
        sudo sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
    else
        echo "IPV6=no" | sudo tee -a /etc/default/ufw >/dev/null
    fi
    log "Firewall rules applied. IPv6 disabled for UFW."
}

# Return *all* block devices (disks) — you may restrict to USB disks if preferred
get_block_devices() {
    # Prefer to build a RAID using disks that are NOT the boot/root device.
    # We'll filter out the root device by comparing against the disk of the root filesystem.
    local root_disk
    root_disk="$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null || true)"
    lsblk -ndo NAME,TYPE,TRAN | awk -v rd="$root_disk" '
      $2=="disk" {
        name=$1; tran=$3;
        # Skip loop/ram devices and the root disk if known
        if (name ~ /^loop/ || name ~ /^ram/) next;
        if (rd != "" && name == rd) next;
        print "/dev/"name
      }'
}

check_block_devices_are_sufficient() {
    mapfile -t devices < <(get_block_devices)
    if (( ${#devices[@]} < 2 )); then
        error "Insufficient block devices found for RAID setup (found ${#devices[@]})."
        lsblk
        exit 1
    fi
    log "Found candidate block devices: ${devices[*]}"
    printf '%s\n' "${devices[@]}"
}

format_and_mount_drive() {
    local device_path="$1"
    local mount_point="$2"

    log "Formatting $device_path as ext4..."
    sudo mkfs.ext4 -F -v -m 0.1 -b 4096 "$device_path" | tee -a "$LOG_FILE"

    log "Mounting $device_path at $mount_point..."
    sudo mkdir -p "$mount_point"
    sudo mount "$device_path" "$mount_point"

    # Persist mount (by UUID)
    local uuid
    uuid="$(blkid -s UUID -o value "$device_path")"
    if ! grep -q "$uuid" /etc/fstab; then
        echo "UUID=$uuid  $mount_point  ext4  defaults,noatime  0  2" | sudo tee -a /etc/fstab >/dev/null
        log "Added mount to /etc/fstab for $device_path (UUID=$uuid)."
    fi
}

create_and_format_raid() {
    local d1="$1" d2="$2"
    local RAID_DEV="/dev/md0"
    log "Creating RAID1 array at $RAID_DEV with $d1 $d2"

    # Ensure md module is loaded
    sudo modprobe md_mod || true

    # Stop any pre-existing array at md0 to avoid conflicts
    if sudo mdadm --detail "$RAID_DEV" >/dev/null 2>&1; then
        warn "$RAID_DEV already exists; stopping it before re-creating."
        sudo mdadm --stop "$RAID_DEV" || true
    fi

    # Zap existing superblocks to be safe
    sudo mdadm --zero-superblock --force "$d1" || true
    sudo mdadm --zero-superblock --force "$d2" || true

    # Create
    sudo mdadm --create --verbose "$RAID_DEV" \
      --level=1 --raid-devices=2 "$d1" "$d2" | tee -a "$LOG_FILE"

    # Wait for sync to start (optional: wait for full sync)
    sleep 2
    cat /proc/mdstat | tee -a "$LOG_FILE"

    # Persist mdadm config so the array auto-assembles at boot
    if ! grep -qE '^ARRAY ' /etc/mdadm/mdadm.conf 2>/dev/null; then
        echo "# mdadm arrays" | sudo tee -a /etc/mdadm/mdadm.conf >/dev/null
    fi
    sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf >/dev/null
    sudo update-initramfs -u || true

    # Create filesystem and mount
    format_and_mount_drive "$RAID_DEV" "/mnt/raid"

    log "RAID setup completed."
    sudo mdadm --detail "$RAID_DEV" | tee -a "$LOG_FILE"
}

main() {
    log "Starting RAID 1 installation on Raspberry Pi..."
    install_prerequisites
    pre_checks
    setting_unit_firewall_rules

    # Choose the first two candidate disks
    mapfile -t devices < <(check_block_devices_are_sufficient)
    local d1="${devices[0]}"
    local d2="${devices[1]}"

    create_and_format_raid "$d1" "$d2"
    log "All done."
}

main "$@"
