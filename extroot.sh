#!/bin/sh
# Script for extending an openWRT device storage
# wget https://raw.githubusercontent.com/rdbh/openwrtconfig/master/extroot.sh
# (C) Richard Dawson 2020

# script assumes you are running as root
if ! [ $(id -u) = 0 ]; then
   echo "this script must be run as root"
   exit 1
fi

# update packages and install required software
printf "\nUpdating and installing required packages\n"
opkg update 
opkg install block-mount 
opkg install kmod-fs-ext4 
opkg install kmod-usb-storage 
opkg install kmod-usb-ohci 
opkg install kmod-usb-uhci 
opkg install e2fsprogs 
opkg install fdisk

# preserve the ability to access the rootfs_data
printf "\nCreating access point for rootfs_data\n"
printf "\trootfs_data can be found at /rwn\n"
DEVICE="$(sed -n -e "/\s\/overlay\s.*$/s///p" /etc/mtab)"
uci -q delete fstab.rwm
uci set fstab.rwm="mount"
uci set fstab.rwm.device="${DEVICE}"
uci set fstab.rwm.target="/rwm"
uci commit fstab

# get available drives
printf "\nDetermine which drive is your expansion drive:\n"
mounted_blocks=$(block info)
# TODO: make a menu here
printf "%s\n" "$mounted_blocks"

printf "\nType the name of the device you want to format\n"
printf "\tExample for \"/dev/sda1\" type \"sda1\"\n"
read mount_drive

printf "WARNING: you are about to format /dev/%s\n" "$mount_drive"
read -p "Enter Y to format drive: " -r ans1

if [[ "$ans1" == "Y" ]]; then
  mkfs.ext4 -F /dev/$mount_drive
fi

# Add the external drive to the overlay
printf "\nAdding %s to the overlay\n" "$mount_drive"
DEVICE="/dev/$mount_drive"
eval $(block info "${DEVICE}" | grep -o -e "UUID=\S*")
uci -q delete fstab.overlay
uci set fstab.overlay="mount"
uci set fstab.overlay.uuid="${UUID}"
uci set fstab.overlay.target="/overlay"
uci set fstab.@global[0].delay_root="15"
uci commit fstab

# Copy the current overlay into the new drive
printf "\nCopying the current rootfs to the new drive overlay\n\n"
mount -t ext4 /dev/$mount_drive /mnt
cp -f -a /overlay/. /mnt
umount /mnt

# Reboot
read -p "Unless you saw errors, press [ENTER] to reboot" -r ans2
reboot
