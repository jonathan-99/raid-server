#!/bin/bash

# Function to check and install prerequisites
install_prerequisites() {
    echo "Checking and installing prerequisites"
    while read -r p ; do sudo "$p" -y ; done < <(cat << "EOF"
        apt-get update
        apt upgrade
        apt-get install mdadm
EOF
    )

    while read -r p ; do sudo "$p" ; done < <(cat << "EOF"
        pip3 install --upgrade setuptools
        pip3 install docker
        pip3 install ufw
EOF
    )
}

pre_checks() {
    set -eu -o pipefail # fail on error and report it, debug all lines

    # Check if the operating system is Linux
    if [[ $(uname -s) != "Linux" ]]; then
        echo "This script is only intended to run on Linux."
        exit 1
    fi

    # Proceed with the installation steps for Linux
    sudo -n true
    test $? -eq 0 || exit 1
    # "you should have sudo privilege to run this script"
}

setting_unit_firewall_rules() {
    # Set ufw
    echo "Set ufw rules"
    while read -r p ; do sudo "$p" ; done < <(cat <<EOF
        ufw allow ssh
        ufw allow 80
        ufw allow 443
        ufw allow 3142
EOF
    )
    # Deny ipv6
    sed -i '/\[ipv6=\]/i no' /etc/default/ufw
    echo "Denied ipv6"
}

get_block_devices() {
    lsblk -o NAME -p | grep ':vme' | awk '{print $1}'
}

check_block_devices_are_sufficient() {
    array=$(get_block_devices)

    # Check if there are at least two block devices
    if [ "$(echo "$array" | wc -l)" -lt 2 ]; then
    echo "Insufficient block devices found for RAID setup"
    exit 1
fi
}

format_and_mount_drive() {
    local device_path="$1"

    # Making the new drive ext4 format
    echo "Make the drive ext4 format"
    mkfs.ext4 -v -m .1 -b 4096 "$device_path"

    # Mount the drive
    echo "Mount the drive"
    mkdir -p /mnt
    mount "$device_path" /mnt
}


echo "This will install a RAID 1 [Mirroring] server on a Raspberry Pi."
install_prerequisites
pre_checks
# check the sda for the usb
lsblk
setting_unit_firewall_rules
check_block_devices_are_sufficient

# make the usb drives raid devices
echo Make usb devices raid devices
location=$("/dev/md/vo1")
mdadm --create --verbose "$location" --level=1 --raid-devices=2 "$array"
format_and_mount_drive "$location"

# setting variables
echo "setting variables - none at this time"

# demonstrate success
echo sudo mdadm --detail /dev/md/vol1
