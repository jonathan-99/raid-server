#!/bin/bash
# RAID 1 Setup Script for Raspberry Pi
# Logs to /var/log/raid_setup.log

LOG_FILE="/var/log/raid_setup.log"

# ---------- Logging ----------
log()   { echo "[INFO]  $*" | tee -a "$LOG_FILE"; }
warn()  { echo "[WARN]  $*" | tee -a "$LOG_FILE"; }
error() { echo "[ERROR] $*" | tee -a "$LOG_FILE" >&2; }

# Trap unexpected errors
trap 'error "Script failed at line $LINENO. Exit code: $?"' ERR

# ---------- Functions ----------
install_prerequisites() {
    log "Checking and installing prerequisites..."
    sudo apt-get update -y | tee -a "$LOG_FILE"
    sudo apt-get upgrade -y | tee -a "$LOG_FILE"
    sudo apt-get install -y mdadm ufw python3-pip | tee -a "$LOG_FILE"

    pip3 install --upgrade setuptools docker | tee -a "$LOG_FILE"
}

pre_checks() {
    set -eu -o pipefail

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
    sudo ufw allow ssh
    sudo ufw allow 80
    sudo ufw allow 443
    sudo ufw allow 3142

    # Deny IPv6 (optional, depending on environment)
    if grep -q "IPV6=" /etc/default/ufw; then
        sudo sed -i 's/IPV6=.*/IPV6=no/' /etc/default/ufw
    else
        echo "IPV6=no" | sudo tee -a /etc/default/ufw >/dev/null
    fi
    log "Firewall rules applied. IPv6 disabled."
}

get_block_devices() {
    # Adjust pattern for your device type (USB drives often show as /dev/sdX)
    lsblk -ndo NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}'
}

check_block_devices_are_sufficient() {
    local devices
    devices=($(get_block_devices))

    if [ "${#devices[@]}" -lt 2 ]; then
        error "Insufficient block devices found for RAID setup (found ${#devices[@]})."
        exit 1
    fi
    log "Found ${#devices[@]} block devices: ${devices[*]}"
    echo "${devices[@]}"
}

format_and_mount_drive() {
    local device_path="$1"
    local mount_point="$2"

    log "Formatting $device_path as ext4..."
    sudo mkfs.ext4 -F -v -m 0.1 -b 4096 "$device_path" | tee -a "$LOG_FILE"

    log "Mounting $device_path at $mount_point..."
    sudo mkdir -p "$mount_point"
    sudo mount "$device_path" "$mount_point"
    log "$device_path mounted at $mount_point."
}

# ---------- Main ----------
log "Starting RAID 1 installation on Raspberry Pi..."

install_prerequisites
pre_checks
setting_unit_firewall_rules

# Identify and prepare devices
devices=($(check_block_devices_are_sufficient))
log "Creating RAID1 with devices: ${devices[0]} ${devices[1]}"

# Create RAID device
RAID_DEV="/dev/md0"
sudo mdadm --create --verbose "$RAID_DEV" --level=1 --raid-devices=2 "${devices[0]}" "${devices[1]}" | tee -a "$LOG_FILE"

# Save RAID config
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf >/dev/null

# Format and mount RAID
format_and_mount_drive "$RAID_DEV" "/mnt/raid"

log "RAID setup completed successfully."
sudo mdadm --detail "$RAID_DEV" | tee -a "$LOG_FILE"
