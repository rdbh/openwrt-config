#!/bin/sh
# Script for setting up a new OpenWRT device
# wget https://raw.githubusercontent.com/rdbh/openwrt-config/master/setup.sh
# Copyright 2020, 2021 Richard Dawson
# v0.5.0

## VARIABLES
# Create a log file with current date and time
DATE_VAR=$(date +'%y%m%d-%H%M')
LOG_FILE="${DATE_VAR}_install.log"

touch $LOG_FILE

# Exit on errors
set -e

# Set the STEP variable to 0 globally
STEP=0

#------------------------------------------------------
# Individual Functions
#------------------------------------------------------

autoinstall_device() {
	clear
	printf "\nTrying to identify this device\n"

	# Determine which device we are operating on

	MODEL="$(grep '"id":' /etc/board.json | awk -F ': ' '{print $NF}' |
		awk -F '"' '{print $2}' | sed 's/glinet,//')"
	case $MODEL in
	"axt1800")
		printf "\nGL-AX1800 Slate detected\n\n"
		read -p "If this is correct, enter y to continue: " -r ans
		if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
			setup_ax1800
		else
			return
		fi
		;;

	"gl-mt1300")
		printf "\nGL-MT1300 Beryl detected\n\n"
		read -p "If this is correct, enter y to continue: " -r ans
		if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
			setup_mt1300
		else
			return
		fi
		;;

	"gl-ar750" | "gl-ar750s" | "gl-ar750s-nor-nand")
		printf "\nGL-AR750 Slate detected\n\n"
		read -p "If this is correct, enter y to continue: " -r ans
		if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
			setup_ar750
		else
			return
		fi
		;;
	"gl-e750")
		printf "\nGL-E750 Mudi detected\n\n"
		read -p "If this is correct, enter y to continue: " -r ans
		if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
			setup_ar750
		else
			return
		fi
		;;
	"gl-mv1000")
		printf "\nGL-MV1000 (Brume) detected\n\n"
		read -p "If this is correct, enter y to continue: " -r ans
		if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
			setup_mv1000
		else
			return
		fi
		;;
	"gl-usb150")
		printf "\nGL-USB150 detected\n\n"
		read -p "If this is correct, enter y to continue: " -r ans
		if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
			setup_usb150
		else
			return
		fi
		;;
	*)
		printf "\nUnrecognized device ${STEP}\n" "$model"
		printf "\nSelect model config or individual items from the menu\n\n"
		pause
		;;
	esac
}

clean_up() {
	printf "\nStep ${STEP} - Removing temporary files\n"
	# (0.2.4) add root directory to reset cleanup
	sed -i -e "/^\/root/d" /etc/sysupgrade.conf
	STEP=$((STEP + 1))
}

debug_echo() {
	if [[ "${DEBUG}" = 'true' ]]; then
		printf "\n${1}\n"
	fi
}

expand_storage() {
	# Install required software
	printf "\n\nStep ${STEP} - installing required packages\n"
	printf "\tRequired for overlay expansion\n"
	opkg update >>$LOG_FILE
	opkg install block-mount >>$LOG_FILE
	opkg install kmod-fs-ext4 >>$LOG_FILE
	opkg install kmod-usb-storage >>$LOG_FILE
	opkg install kmod-usb-ohci >>$LOG_FILE
	opkg install kmod-usb-uhci >>$LOG_FILE
	opkg install e2fsprogs >>$LOG_FILE
	opkg install fdisk >>$LOG_FILE
	STEP=$((STEP + 1))

	# preserve the ability to access the rootfs_data
	printf "\nCreating access point for rootfs_data\n"
	printf "\trootfs_data can be found at /rwn\n"
	DEVICE="$(sed -n -e "/\s\/overlay\s.*$/s///p" /etc/mtab)"
	uci -q delete fstab.rwm
	uci set fstab.rwm="mount"
	uci set fstab.rwm.device="${DEVICE}"
	uci set fstab.rwm.target="/rwm"
	uci commit fstab
	debug_echo "recreated fstab"
	STEP=$((STEP + 1))

	# get available drives
	printf "\nDetermine which drive is your expansion drive:\n"
	MOUNTED_BLOCKS=$(block info | awk -F ':' '{print $1}')
	# TODO: make a menu here
	printf "${MOUNTED_BLOCKS}\n"
	printf "\nType the name of the device you want to format\n"
	printf "\tExample for \"/dev/sda1\" type \"sda1\"\n"
	printf "\n\tPress [ENTER] for default mmcblk0p1\n"
	read -r MOUNT_DRIVE
	if [[ "${MOUNT_DRIVE}" = "" ]]; then
		MOUNT_DRIVE="mmcblk0p1"
	fi
	# Check if storage device is mounted
	printf "\nChecking to see if the storage device is currently mounted\n\n"
	#TODO: make this cleaner
	set +e
	umount /mnt/"${MOUNT_DRIVE}"

	# Format the storage device
	printf "WARNING: you are about to format /dev/${MOUNT_DRIVE}\n"
	read -p "Enter Y to format drive: " -r ans1

	if [ "${ans1}" = "Y" ] || [ "${ans1}" = "y" ]; then
		mkfs.ext4 -F /dev/"${MOUNT_DRIVE}"
	else
		printf "\nAborted\n"
		return
	fi
	STEP=$((STEP + 1))

	# Add the external drive to the overlay
	printf "\nAdding ${STEP} to the overlay\n" "${MOUNT_DRIVE}"
	DEVICE="/dev/${MOUNT_DRIVE}"
	eval $(block info "${DEVICE}" | grep -o -e "UUID=\S*")
	uci -q delete fstab.overlay
	uci set fstab.overlay="mount"
	uci set fstab.overlay.uuid="${UUID}"
	uci set fstab.overlay.target="/overlay"
	uci set fstab.@global[0].delay_root="15"
	uci commit fstab
	STEP=$((STEP + 1))
	set -e

	# Copy the current overlay into the new drive
	printf "\nCopying the current rootfs to the new drive overlay\n"
	mount -t ext4 /dev/"${MOUNT_DRIVE}" /mnt
	cp -f -a /overlay/. /mnt
	umount /mnt
	STEP=$((STEP + 1))

	# Reboot
	printf "\nCheck the preceding text for errors, and troubleshoot as necessary\n"
	printf "\nCtrl-C (^C) will terminate the script without rebooting\n"
	read -p "Otherwise, press [ENTER] to reboot" -r
	reboot
}

force_https() {
	# Pull openssl modification
	printf "\nStep ${STEP} - Installing http redirect\n\n"
	printf "\n\tStep ${STEP}a - Installing lighttpd-mod-redirect\n"
	opkg install lighttpd-mod-redirect
	printf "\n\tStep ${STEP}b - Modifying 30-openssl.conf\n"
	wget https://raw.githubusercontent.com/rdbh/openwrt-config/master/config.txt
	cat config.txt >>/etc/lighttpd/conf.d/30-openssl.conf
	# Restart the http service
	printf "\nStep ${STEP}c - Restarting http service\n"
	/etc/init.d/lighttpd restart
	# Clean up config.txt
	rm config.txt
	STEP=$((STEP + 1))
}

full_upgrade() {
	# WARNING - this can lead to unpredictable results, so
	# this should only be done if you are willing to troubleshoot
	# This is equivalent to apt upgrade
	opkg list-upgradable | cut -f 1 -d ' ' | xargs opkg upgrade
	STEP=$((STEP + 1))
}

install_git() {
	printf "\nStep ${STEP} - Installing git\n"
	opkg install git >>$LOG_FILE
	opkg install git-http >>$LOG_FILE
	STEP=$((STEP + 1))
}

install_jq() {
	# jq used for reading JSON
	printf "\nStep ${STEP} - Installing jq\n"
	opkg install jq >>$LOG_FILE
	STEP=$((STEP + 1))
}

install_nano() {
	printf "\nStep ${STEP} - Installing nano"
	opkg install nano >>$LOG_FILE
	STEP=$((STEP + 1))
}

install_python() {
	printf "\nStep ${STEP} - Installing python 3.x\n"
	# (0.2.4) Install python light to save space
	opkg install python3-light
	# (0.2.4) The following additional libraries are required for py-kms
	opkg install python3-logging >>$LOG_FILE
	opkg install python3-xml >>$LOG_FILE
	opkg install python3-multiprocessing >>$LOG_FILE
	STEP=$((STEP + 1))
}

install_pykms() {
	printf "\nStep ${STEP} - Installing py-kms\n\n"
	printf "\n\tStep ${STEP}a - Cloning repository\n"
	git clone https://github.com/radawson/py-kms-1
	printf "\n\tStep ${STEP}b - Transitioning to py-kms install script\n"
	cd py-kms-1
	rm -rf docker
	sh install.sh -o
	STEP=$((STEP + 1))
}

install_tmux() {
	printf "\nStep ${STEP} - Installing tmux\n"
	opkg install tmux >>$LOG_FILE
	STEP=$((STEP + 1))
}

install_usb3() {
	# (0.2.4) added file drivers to make USB sharing easier
	printf "\nStep ${STEP} - Installing drivers for file sharing\n"
	opkg install e2fsprogs >>$LOG_FILE
	opkg install kmod-usb3 >>$LOG_FILE
	STEP=$((STEP + 1))
}

install_utilities() {
	install_git
	install_nano
	install_tmux
}

pause() {
	printf "\n\n\tPress [ENTER] to continue\n"
	read -r cont
}

update_dns_kms() {
	printf "\n\tStep ${STEP} - Adding DNS entries for KMS\n"
	if [[ -r /etc/config/dhcp && $(grep "_vlmcs._tcp" /etc/config/dhcp) == "" ]]; then
		uci add dhcp srvhost
		uci set dhcp.@srvhost[-1].srv="_vlmcs._tcp.lan"
		uci set dhcp.@srvhost[-1].target="console.gl-inet.com"
		uci set dhcp.@srvhost[-1].port="1688"
		uci set dhcp.@srvhost[-1].class="0"
		uci set dhcp.@srvhost[-1].weight="0"
		uci commit dhcp
		/etc/init.d/dnsmasq restart
	fi
}

update_opkg() {
	printf "\nStep ${STEP} - Updating Repository\n\n"
	opkg update >>$LOG_FILE
	STEP=$((STEP + 1))
	printf "Package repository update complete"
}

#------------------------------------------------------
# DEVICE PROTOCOLS
#------------------------------------------------------

setup_ar750() {
	update_opkg
	install_git
	install_nano
	install_python
	install_pykms
	install_usb3
	# force_https deprecated as of firmware 3.201
	clean_up
}

setup_ax1800() {
	update_opkg
	install_git
	install_nano
	install_python
	install_pykms
	update_dns_kms
	clean_up
}

setup_mv1000() {
	update_opkg
	install_git
	install_python
	install_pykms
	install_usb3
	# force_https deprecated as of firmware 3.201
	clean_up
}

setup_mt1300() {
	# Check to see if the /overlay has been expanded
	overlay_size=$(df | grep -w overlayfs: | awk ' { print $2 } ')
	if [ $overlay_size -gt 16000 ]; then
		printf "\nExpanded /overlay found, installing packages\n"
		update_opkg
		install_git
		install_python
		install_pykms
		# force_https deprecated as of firmware 3.201
		install_usb3
		clean_up
	else
		printf "\nOverlay storage must be expanded before installing packages\n"
		expand_storage
	fi
}

setup_usb150() {
	update_opkg
	printf "\nUSB150 has very limited storage.\n"
	printf "\nOnly installing nano for config editing\n"
	install_nano
	clean_up
}

#------------------------------------------------------
# MENU PROMPTS
#------------------------------------------------------
_1menu="1.  Install for AR-750 "
_2menu="2.  Install for MT-1300 "
_3menu="3.  Install for MV-1000 "
_4menu="4.  Install for USB-150 "
_5menu="5.  Install for AX-1800 "
amenu="a.  Automatic Install "
bmenu="b.  Expand Memory "
cmenu="c.  Install KMS Server "
dmenu="d.  Force HTTPS ! Deprecated !"
emenu="e.  Install Utilities "
fmenu="f.  Install Python 3 "
gmenu="  "
hmenu="  "
imenu="  "

#------------------------------------------------------
# MENU FUNCTION DEFINITIONS
#------------------------------------------------------

# Define a function for invalid menu picks
# The function loads an error message into a variable
badchoice() { MSG="Invalid Selection ... Please Try Again"; }

_1pick() {
	step=1
	setup_ar750
	pause
}
_2pick() {
	step=1
	setup_mt1300
	pause
}
_3pick() {
	step=1
	setup_mv1000
	pause
}
_4pick() {
	step=1
	setup_usb150
	pause
}
_5pick() {
	step=1
	setup_ax1800
	pause
}

apick() {
	step=1
	autoinstall_device
	pause
}
bpick() {
	step=1
	update_opkg
	expand_storage
	pause
}
cpick() {
	step=1
	update_opkg
	install_pykms
	pause
}
dpick() {
	step=1
	update_opkg
	force_https
	pause
}
epick() {
	step=1
	update_opkg
	install_utilities
	pause
}
fpick() {
	step=1
	update_opkg
	install_python
	pause
}

#------------------------------------------------------
# DISPLAY MENU
#------------------------------------------------------

run_menu() {
	now=$(date +'%m/%d/%Y')
	# Displays the menu options
	clear
	printf "${now}"
	printf "\n\t\t\tRouter Update Menu\n"
	printf "\n\t\tPlease Select:\n"
	printf "\n\t\t\t${_1menu}"
	printf "\n\t\t\t$_2menu"
	printf "\n\t\t\t$_3menu"
	printf "\n\t\t\t$_4menu"
	printf "\n\t\t\t$_5menu"
	printf "\n\t\t\t$amenu"
	printf "\n\t\t\t$bmenu"
	printf "\n\t\t\t$cmenu"
	printf "\n\t\t\t$dmenu"
	printf "\n\t\t\t$emenu"
	printf "\n\t\t\t$fmenu"
	printf "\n\t\t\t$gmenu"
	printf "\n\t\t\t$hmenu"
	printf "\n\t\t\t$imenu"
	printf "\n"
	printf "\n\t\t\tx. Exit\n"
	printf "\n${MSG}\n"
	printf "\nSelect by pressing the letter and then ENTER\n\t"
}

#------------------------------------------------------
# MAIN LOGIC
#------------------------------------------------------
clear

# Check to ensure script is run as root
if [[ "${UID}" -ne 0 ]]; then
	UNAME=$(id -un)
	printf "This script must be run as root\nYou are currently running as ${UNAME}\n" >&2
	exit 1
fi

while :; do
	run_menu
	read -r answer
	MSG=""
	case $answer in
	'1') _1pick ;;
	'2') _2pick ;;
	'3') _3pick ;;
	'4') _4pick ;;
	'5') _5pick ;;

	h | H) gpick ;;
	a | A) apick ;;
	b | B) bpick ;;
	c | C) cpick ;;
	d | D) dpick ;;
	e | E) epick ;;
	f | F) fpick ;;

	x | X) break ;;
	*) badchoice ;;
	esac
done

# Completion Message
printf "Installation Complete\n\n"
