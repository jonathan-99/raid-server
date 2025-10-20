#!/usr/bin/env bash
# ============================================
# install_raid_target.sh
# --------------------------------------------
# NAME: install_raid_target.sh
#
# ROLE:
#   Installs RAID 1 on the Raspberry Pi target.
#   Runs device updater, firewall setup, RAID checks, and RAID creation.
#
# EXECUTION:
#   Called remotely by install_raid_orchestration.sh
# STEPS:
#   1. Run device updater
#   2. Run firewall setup
#   3. Run RAID pre-checks
#   4. Run the actual RAID installer (install_raid_server.sh)
#
# Logs to: /tmp/raid_target_<hostname>.log
# ============================================

set -euo pipefail

TARGET_HOSTNAME="${HOST:-$(hostname)}"
log()   { printf "[INFO]  [$TARGET_HOSTNAME] %s\n" "$*"; }
warn()  { printf "[WARN]  [$TARGET_HOSTNAME] %s\n" "$*" >&2; }
error() { printf "[ERROR] [$TARGET_HOSTNAME] %s\n" "$*" >&2; exit 1; }

RAID_MOUNT="/mnt/raid"
RAID_DEVICES=("/dev/sda" "/dev/sdc")   # default; can be adjusted
RAID_NAME="raid1array"

log "===== RAID INSTALL START ON $TARGET_HOSTNAME: $(date) ====="

# --- 1️⃣ Device updater ---
log "Running device updater..."
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y mdadm ufw python3-pip python3-venv
log "Device updater completed."

# --- 2️⃣ Firewall setup ---
log "Setting up firewall..."
sudo ufw allow ssh
sudo ufw --force enable
log "Firewall setup completed."

# --- 3️⃣ Pre-installation RAID checks ---
log "Performing pre-installation RAID checks..."
AVAILABLE_DISKS=($(lsblk -ndo NAME,TYPE | awk '$2=="disk" {print "/dev/"$1}'))
log "Available disks: ${AVAILABLE_DISKS[*]}"

if [[ ${#AVAILABLE_DISKS[@]} -lt 2 ]]; then
    error "Not enough disks for RAID. Require at least 2, found ${#AVAILABLE_DISKS[@]}."
fi

# Use first two disks as RAID devices
RAID_DEVICES=("${AVAILABLE_DISKS[0]}" "${AVAILABLE_DISKS[1]}")
log "RAID devices selected: ${RAID_DEVICES[*]}"

# --- 4️⃣ Check if RAID array exists ---
if sudo mdadm --detail --scan | grep -q "$RAID_NAME"; then
    warn "RAID array '$RAID_NAME' already exists. Skipping creation."
else
    # --- 5️⃣ Create RAID 1 array ---
    log "Creating RAID 1 array on ${RAID_DEVICES[*]}..."
    if sudo mdadm --create --verbose --level=1 --raid-devices=2 /dev/md0 "${RAID_DEVICES[@]}" 2>&1 | tee /tmp/mdadm_creation.log; then
        log "RAID 1 array created successfully."
    else
        warn "Failed to create RAID 1 array. Devices might be busy or array already exists."
        log "Check /tmp/mdadm_creation.log for details."
    fi
fi

# --- 6️⃣ Create mount point and mount RAID ---
sudo mkdir -p "$RAID_MOUNT"
if mountpoint -q "$RAID_MOUNT"; then
    log "RAID already mounted at $RAID_MOUNT"
else
    log "Mounting RAID at $RAID_MOUNT..."
    sudo mkfs.ext4 -F /dev/md0 || warn "Filesystem already exists on /dev/md0"
    sudo mount /dev/md0 "$RAID_MOUNT"
    log "RAID mounted at $RAID_MOUNT"
fi

# --- 7️⃣ Save mdadm config ---
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf

log "===== RAID INSTALL COMPLETE ON [$TARGET_HOSTNAME]: $(date) ====="
