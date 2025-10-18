#!/usr/bin/env bash
# Raspberry Pi RAID 1 Setup Script
# This script is copied and executed on the TARGET device by the orchestrator.
# It configures prerequisites, firewall, builds mdadm RAID1, formats, and mounts it.
# Logs to /var/log/raid_setup.log

set -euo pipefail

LOG_FILE="/var/log/raid_setup.log"

log()   { printf '[JUMPBOX] [INFO]  %s\n' "$*" | tee -a "$LOG_FILE"; }
warn()  { printf '[JUMPBOX] [WARN]  %s\n' "$*" | tee -a "$LOG_FILE" >&2; }
error() { printf '[JUMPBOX] [ERROR] %s\n' "$*" | tee -a "$LOG_FILE" >&2; }

# Trap unexpected errors (capture exit code)
trap 'rc=$?; error "Script failed at line $LINENO. Exit code: $rc"; exit $rc' ERR

install_prerequisites() {
    log "Checking and installing prerequisites..."
    export DEBIAN_FRONTEND=noninteractive

    sudo apt-get update -y            | tee -a "$LOG_FILE"
    sudo apt-get full-upgrade -y      | tee -a "$LOG_FILE"

    # Install mdadm, ufw and python venv support non-interactively
    sudo apt-get install -y mdadm ufw python3-venv python3-pip --no-install-recommends | tee -a "$LOG_FILE"

    # Create an isolated venv for optional Python tools (avoids PEP 668 externally-managed error)
    if python3 -m venv /opt/raid-venv 2>/dev/null; then
        log "Created venv at /opt/raid-venv for optional Python tooling."
        # shellcheck disable=SC1091
        source /opt/raid-venv/bin/activate
        python -m pip install --upgrade pip setuptools wheel >>"$LOG_FILE" 2>&1 || warn "Failed to upgrade pip inside venv."
        # Example optional packages; failures shouldn't block the script
        python -m pip install docker >>"$LOG_FILE" 2>&1 || warn "Optional pip installs failed or unavailable."
        deactivate
    else
        warn "Could not create venv at /opt/raid-venv; skipping optional Python installs."
    fi
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
    if [[ "$(hostname)" == "jumpbox" ]]; then
        error "This script is running on the jumpbox (hostname=$(hostname)). Aborting."
        exit 1
    fi

    log "Pre-checks passed."
}

setting_unit_firewall_rules() {
    log "Configuring UFW firewall rules..."
    sudo ufw allow ssh || true
    sudo ufw allow 80    || true
    sudo ufw allow 443   || true
    sudo ufw allow 3142  || true

    # Disable IPv6 for UFW (optional)
    if grep -qE '^IPV6=' /etc/default/ufw 2>/dev/null; then
        sudo sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
    else
        echo "IPV6=no" | sudo tee -a /etc/default/ufw >/dev/null
    fi

    # Enable UFW (idempotent)
    sudo ufw --force enable >/dev/null 2>&1 || true
    log "Firewall rules applied. IPv6 disabled for UFW."
}

# Return *all* block devices (disks) — excludes the disk containing the root FS.
get_block_devices() {
    # Determine root device's parent disk (if possible)
    local root_src root_part root_disk
    root_src="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
    if [[ -n "$root_src" && "$root_src" =~ ^/dev/ ]]; then
        # e.g. /dev/mmcblk0p2 -> mmcblk0
        root_part="$(basename "$root_src")"
        root_disk="$(lsblk -no PKNAME "/dev/$root_part" 2>/dev/null || true)"
    else
        root_disk=""
    fi

    # Print candidate disks, one per line, excluding root disk and loop/ram
    # Columns: NAME TYPE TRAN
    lsblk -ndo NAME,TYPE,TRAN | awk -v rd="$root_disk" '
      $2=="disk" {
        name=$1
        if (name ~ /^loop/ || name ~ /^ram/) next
        if (rd != "" && name == rd) next
        print "/dev/" name
      }'
}

check_block_devices_are_sufficient() {
    # Read devices into an array, but do NOT print logs to stdout (to avoid contaminating command args)
    mapfile -t devices < <(get_block_devices)

    if (( ${#devices[@]} < 2 )); then
        error "Insufficient block devices found for RAID setup (found ${#devices[@]})."
        # Print lsblk to the log for debugging
        lsblk | tee -a "$LOG_FILE"
        return 1
    fi

    # Use log() (writes to file) but do NOT echo the devices to stdout
    log "Found candidate block devices: ${devices[*]}"
    # Return devices via stdout only if caller explicitly expects them; here we'll output them one-per-line
    printf '%s\n' "${devices[@]}"
}

format_and_mount_drive() {
    local device_path="$1"
    local mount_point="$2"

    log "Formatting $device_path as ext4..."
    # Force ext4 creation (non-interactive)
    sudo mkfs.ext4 -F -v -m 0.1 -b 4096 "$device_path" | tee -a "$LOG_FILE"

    log "Mounting $device_path at $mount_point..."
    sudo mkdir -p "$mount_point"
    # Mount; if already mounted this is idempotent
    if ! mountpoint -q "$mount_point"; then
        sudo mount "$device_path" "$mount_point"
    else
        log "$mount_point already mounted."
    fi

    # Persist mount (by UUID)
    local uuid
    uuid="$(sudo blkid -s UUID -o value "$device_path" 2>/dev/null || true)"
    if [[ -n "$uuid" ]]; then
        if ! grep -q "$uuid" /etc/fstab 2>/dev/null; then
            echo "UUID=$uuid  $mount_point  ext4  defaults,noatime  0  2" | sudo tee -a /etc/fstab >/dev/null
            log "Added mount to /etc/fstab for $device_path (UUID=$uuid)."
        else
            log "Existing fstab entry found for UUID=$uuid; skipping."
        fi
    else
        warn "Could not determine UUID for $device_path; /etc/fstab not updated."
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

    # Create the RAID device (use array syntax with array elements as an array)
    # Important: pass devices as separate args
    sudo mdadm --create --verbose "$RAID_DEV" --level=1 --raid-devices=2 "$d1" "$d2" | tee -a "$LOG_FILE"

    # Wait up to N seconds for /dev/md0 to appear and mdstat to show assembling
    local attempts=0 max_attempts=15
    while [[ ! -e "$RAID_DEV" && $attempts -lt $max_attempts ]]; do
        sleep 1
        attempts=$((attempts + 1))
    done

    if [[ ! -e "$RAID_DEV" ]]; then
        error "RAID device $RAID_DEV did not appear after create. Aborting."
        cat /proc/mdstat | tee -a "$LOG_FILE"
        return 1
    fi

    # Short pause to let mdadm start the sync
    sleep 2
    cat /proc/mdstat | tee -a "$LOG_FILE"

    # Persist mdadm config so the array auto-assembles at boot
    # Avoid duplicate ARRAY entries
    local scan
    scan="$(sudo mdadm --detail --scan 2>/dev/null || true)"
    if [[ -n "$scan" ]]; then
        if ! sudo grep -qF "$scan" /etc/mdadm/mdadm.conf 2>/dev/null; then
            echo "# mdadm arrays" | sudo tee -a /etc/mdadm/mdadm.conf >/dev/null
            echo "$scan" | sudo tee -a /etc/mdadm/mdadm.conf >/dev/null
            log "Appended mdadm array definition to /etc/mdadm/mdadm.conf"
        else
            log "mdadm.conf already contains the array definition; skipping append."
        fi
    else
        warn "mdadm --detail --scan produced no output; mdadm.conf not updated."
    fi

    # Update initramfs (best-effort)
    sudo update-initramfs -u || warn "update-initramfs failed; continue."

    # Create filesystem and mount on the RAID device
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
    # check_block_devices_are_sufficient writes devices to stdout (one per line) and logs summary to file
    mapfile -t devices < <(check_block_devices_are_sufficient)
    if (( ${#devices[@]} < 2 )); then
        error "Not enough candidate devices to continue."
        exit 1
    fi

    local d1="${devices[0]}"
    local d2="${devices[1]}"

    log "Selected devices for RAID: $d1 and $d2"

    create_and_format_raid "$d1" "$d2"
    log "All done."
}

main "$@"
