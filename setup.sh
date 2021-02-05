#!/bin/sh
# Script for setting up a new OpenWRT device
# wget https://raw.githubusercontent.com/rdbh/openwrt-config/master/setup.sh 
# Copyright 2020, 2021 Richard Dawson
# v0.3.1

# Exit on errors
set -e

# Set the step variable to 0 globally
step=0

#------------------------------------------------------
# Individual Functions
#------------------------------------------------------

autoinstall_device(){
clear
printf "\nTrying to identify this device\n"

	# Determine which device we are operating on
	# TODO: get model information from /etc/board.json

	model="$(hostname)"
	case $model in
		"GL-MT1300")
			printf "GL-MT1300 Beryl detected\n"
			setup_mt1300;;
		"GL-AR750"|"GL-AR750S")
			printf "GL-AR750 Slate detected\n"
			setup_ar750;;
		*)
			printf "Unrecognized device %s\n" "$model"
			read "Press [ENTER] to continue" -r
	esac
}

expand_storage(){
	# Install required software
	printf "\n\nStep %s - installing required packages\n" "$step"
	opkg install block-mount
	opkg install kmod-fs-ext4
	opkg install kmod-usb-storage
	opkg install kmod-usb-ohci
	opkg install kmod-usb-uhci
	opkg install e2fsprogs
	opkg install fdisk
	step=$((step + 1))

	# preserve the ability to access the rootfs_data
	printf "\nCreating access point for rootfs_data\n"
	printf "\trootfs_data can be found at /rwn\n"
	DEVICE="$(sed -n -e "/\s\/overlay\s.*$/s///p" /etc/mtab)"
	uci -q delete fstab.rwm
	uci set fstab.rwm="mount"
	uci set fstab.rwm.device="${DEVICE}"
	uci set fstab.rwm.target="/rwm"
	uci commit fstab
	step=$((step + 1))
	
	# get available drives
	printf "\nDetermine which drive is your expansion drive:\n"
	mounted_blocks=$(block info)
	# TODO: make a menu here
	printf "%s\n" "$mounted_blocks"
	printf "\nType the name of the device you want to format\n"
	printf "\tExample for \"/dev/sda1\" type \"sda1\"\n"
	read -r mount_drive
	printf "WARNING: you are about to format /dev/%s\n" "$mount_drive"
	read "Enter Y to format drive: " -r ans1

	if [[ "$ans1" == "Y" || "$ans1" == "y" ]]; then
		mkfs.ext4 -F /dev/"$mount_drive"
	fi
	step=$((step + 1))

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
	step=$((step + 1))

	# Copy the current overlay into the new drive
	printf "\nCopying the current rootfs to the new drive overlay\n"
	mount -t ext4 /dev/"$mount_drive" /mnt 
	cp -f -a /overlay/. /mnt
	umount /mnt
	step=$((step + 1))

	# Reboot
	printf "\nCheck the preceding text for errors, and troubleshoot as necessary\n"
	printf "\nCtrl-C (^C) will terminate the script without rebooting\n"
	read "Otherwise, press [ENTER] to reboot"
	reboot
}

force_https(){
	# Pull openssl modification 
	printf "\nStep %s - Installing http redirect\n\n" "$step"
	printf "\n\tStep %sa - Installing lighttpd-mod-redirect\n" "$step"
	opkg install lighttpd-mod-redirect
	printf "\n\tStep %sb - Modifying 30-openssl.conf\n" "$step"
	wget https://raw.githubusercontent.com/rdbh/openwrt-config/master/config.txt
	cat config.txt >> /etc/lighttpd/conf.d/30-openssl.conf
	# Restart the http service
	printf "\nStep %sc - Restarting http service\n" "$step"
	/etc/init.d/lighttpd restart
	step=$((step + 1))
}

full_upgrade(){
	# WARNING - this can lead to unpredictable results, so   
	# this should only be done if you are willing to troubleshoot
	# this is equivalent to apt upgrade
	opkg list-upgradable | cut -f 1 -d ' ' | xargs opkg upgrade 
	step=$((step + 1))
}

install_git(){
	printf "\nStep %s - Installing git\n" "$step"
	opkg install git
	opkg install git-http
	step=$((step + 1))
}

install_nano(){
	printf "\nStep %s - Installing nano" "$step"
	opkg install nano
	step=$((step + 1))
}

install_python(){
	printf "\nStep %s - Installing python 3.x\n" "$step"
	# (0.2.4) Install python light to save space
	opkg install python3-light
	# (0.2.4) The following additional libraries are required for py-kms 
	opkg install python3-logging
	opkg install python3-xml
	opkg install python3-multiprocessing
	step=$((step + 1))
}

install_pykms(){
	printf "\nStep %s - Installing py-kms\n\n" "$step"
	printf "\n\tStep %sa - Cloning repository\n" "$step"
	git clone git://github.com/radawson/py-kms-1
	printf "\n\tStep %sb - Transitioning to py-kms install script\n" "$step"
	cd py-kms-1
	rm -rf docker
	sh install.sh
	step=$((step + 1))
}

install_tmux(){
	printf "\nStep %s - Installing tmux\n" "$step"
	opkg install tmux
	step=$((step + 1))
}

install_usb3(){
	# (0.2.4) added file drivers to make USB sharing easier	
	printf "\nStep %s - Installing drivers for file sharing\n" "$step"
	opkg install e2fsprogs
	opkg install kmod-usb3
	step=$((step + 1))
}

clean_up(){
	printf "\nStep %s - Removing temporary files\n" "$step"
	# Clean up config.txt
	rm config.txt
	# (0.2.4) add root directory to reset cleanup
	sed -i -e "/^\/root/d" /etc/sysupgrade.conf
	step=$((step + 1))
}

update_opkg(){
	printf "\nStep %s - Updating Repository\n\n" "$step"
	opkg update
	step=$((step + 1))
	printf "Package repository update complete"
}

#------------------------------------------------------
# DEVICE PROTOCOLS
#------------------------------------------------------

setup_ar750(){
	update_opkg
	install_git
	install_python
	install_pykms
	install_usb3
	clean_up
}

setup_mt1300(){
	update_opkg
	install_git
	install_python
	install_pykms
	install_usb3
	clean_up
	
	expand_storage
}

#------------------------------------------------------
# MENU PROMPTS
#------------------------------------------------------
amenu="a.  Automatic Install "                	;
bmenu="b.  Install for AR-750 "        			; 
cmenu="c.  Install for MT-1300 "    			; 
dmenu="d.  Expand Memory "                 		;
emenu="e.  Install KMS Server "                 ;
fmenu="f.  Force HTTPS "                 		;
 
#------------------------------------------------------
# MENU FUNCTION DEFINITIONS
#------------------------------------------------------
  
# Define a function for invalid menu picks
# The function loads an error message into a variable
badchoice () { MSG="Invalid Selection ... Please Try Again" ; } 

apick() { autoinstall_device ; }
bpick() { step=1 ; setup_ar750 ; }
cpick() { step=1 ; setup_mt1300 ; }
dpick() { step=1 ; update_opkg ; expand_storage ; }
epick() { step=1 ; update_opkg ; install_pykms ; }
fpick() { step=1 ; update_opkg ; force_https ; }

 
#------------------------------------------------------
# DISPLAY MENU
#------------------------------------------------------

run_menu(){
	now=$(date +'%m/%d/%Y')
	# Displays the menu options
	clear
	printf "%s" "$now"
	printf "\n\t\t\tRouter Update Menu\n"
	printf "\n\t\tPlease Select:\n"
	printf "\n\t\t\t%s" "$amenu"
	printf "\n\t\t\t%s" "$bmenu"
	printf "\n\t\t\t%s" "$cmenu"
	printf "\n\t\t\t%s" "$dmenu"
	printf "\n\t\t\t%s" "$emenu"
	printf "\n\t\t\t%s" "$fmenu"
	printf "\n\t\t\tx. Exit\n"
	printf "\n%s\n" "$MSG"
	printf "\nSelect by pressing the letter and then ENTER\n\t"
}

#------------------------------------------------------
# MAIN LOGIC
#------------------------------------------------------
clear

# Check to see if we are running as root 
if ! [ $(id -u) = 0 ]; then 
	printf "\nThis script must be run as root" 
	exit 1 
fi

while :
do
	run_menu
	read -r answer
	MSG=""
	case $answer in
		a|A) apick;;
		b|B) bpick;;
		c|C) cpick;;
		d|D) dpick;;
		e|E) epick;;
		f|F) fpick;;
		x|X) break;;
		*) badchoice;;
	esac
done

# Completion Message
printf "Installation Complete\n\n"
