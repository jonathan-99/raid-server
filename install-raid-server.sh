#!/bin/bash
set -eu -o pipefail # fail on error and report it, debug all lines

sudo -n true
test $? -eq 0 || exit 1
# "you should have sudo privilege to run this script"

echo this will install a RAID 1 [Mirroring] server on a Raspbery Pi.

echo checking and installing pre-requisites
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


# check the sda for the usb
lsblk

array=$(lsblk | awk '{print $1}' | sed 's/^.*:vme//')
#array=$( ${array[@]:1} )
#for items in $array; do echo $items; done
array=$(echo $array | awk '{print $3,$4,$5}')

echo $array

# make the usb drives raid devices
echo Make usb devices raid devices
mdadm --create --verbose /dev/md/vo1 --level=1 --raid-devices=2 $array

# making the new drive ext4 format
echo Make the drive ext4 format
mkfs.ext4 -v -m .1 -b 4096

# mount the drive
echo Mount the drive
mkdir /mnt
mount /dev/md/vol1 /mnt

# setting variables
echo setting variables

# demonstrate success
echo sudo mdadm --detail /dev/md/vol1

# set ufw
echo Set ufw rules
while read -r p ; do sudo "$p" ; done < <(cat << "EOF"
    ufw allow ssh
    ufw allow 80
    ufw allow 443
    ufw allow 3142
EOF
)
# deny ipv6 "ipv6=no"
# ufw_rules=$(cat /etc/default/ufw)
sed  '/\[ipv6=\]/i no' /etc/default/ufw
echo Denied ipv6
