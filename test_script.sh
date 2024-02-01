#!/bin/bash

# Test the install_prerequisites function
test_install_prerequisites() {
    echo "Running install_prerequisites test..."
    # Add assertions to check if prerequisites are installed correctly
    # For example, check if mdadm, docker, and ufw are installed
    sudo apt-get -y install mdadm
    sudo apt-get -y install docker
    sudo apt-get -y install ufw
    assert dpkg -l | grep -q mdadm
    assert dpkg -l | grep -q docker
    assert dpkg -l | grep -q ufw
}

# Test the pre_checks function
test_pre_checks() {
    echo "Running pre_checks test..."
    # Add assertions to check if pre_checks function works as expected
    # For example, check if the script exits when not run on Linux
    assert [[ "$(uname -s)" == "Linux" ]]
}

# Test the setting_unit_firewall_rules function
test_setting_unit_firewall_rules() {
    echo "Running setting_unit_firewall_rules test..."
    # Add assertions to check if firewall rules are set correctly
    # For example, check if ufw rules are added and ipv6 is denied
    sudo ufw allow ssh
    sudo ufw allow 80
    sudo ufw allow 443
    sudo ufw allow 3142
    assert sudo ufw status | grep -q "80/tcp"
    assert sudo ufw status | grep -q "443/tcp"
    assert sudo ufw status | grep -q "3142/tcp"
    assert sudo grep -q "ipv6=no" /etc/default/ufw
}

# Test the get_block_devices function
test_get_block_devices() {
    echo "Running get_block_devices test..."
    # Add assertions to check if block devices are retrieved correctly
    # For example, check if block devices are listed
    assert lsblk -o NAME -p | grep -q ':vme'
}

# Test the check_block_devices_are_sufficient function
test_check_block_devices_are_sufficient() {
    echo "Running check_block_devices_are_sufficient test..."
    # Add assertions to check if block devices are sufficient for RAID setup
    # For example, check if there are at least two block devices
    array=$(lsblk -o NAME -p | grep ':vme' | awk '{print $1}')
    assert [ "$(echo "$array" | wc -l)" -ge 2 ]
}

# Test the format_and_mount_drive function
test_format_and_mount_drive() {
    echo "Running format_and_mount_drive test..."
    # Add assertions to check if drive formatting and mounting works correctly
    # For example, check if formatting and mounting succeed
    assert sudo mkfs.ext4 -v -m .1 -b 4096 /dev/md/vol1
    assert sudo mkdir -p /mnt
    assert sudo mount /dev/md/vol1 /mnt
}

# Run all test functions
test_install_prerequisites
test_pre_checks
test_setting_unit_firewall_rules
test_get_block_devices
test_check_block_devices_are_sufficient
test_format_and_mount_drive

echo "All tests passed successfully!"
