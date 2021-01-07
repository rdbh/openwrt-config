#!/bin/sh
# Script for setting up a new OpenWRT device
# Copyright 2020 R Dawson
# v0.2.3

# Exit on errors
set -e

printf "\nStep 1 - Updating Repository\n\n"
opkg update
# opkg list-upgradable | cut -f 1 -d ' ' | xargs opkg upgrade 
printf "\nStep 2 - software installation\n"
printf "\n\tStep 2a - Installing tmux\n"
opkg install tmux
printf "\n\tStep 2b - Installing python 3.x\n"
opkg install python3-light
opkg install python3-logging
printf "\n\tStep 2c - Installing git\n"
opkg install git
# 0.2.2 removed nano to save space and simplify install
# printf "Step 2d - Installing nano"
# opkg install nano

printf "\nStep 3 - Installing py-kms\n\n"
printf "\n\tStep 3a - Cloning repository\n"
git clone git://github.com/radawson/py-kms-1
printf "\n\tStep 3b - Transitioning to py-kms install script\n"
cd py-kms-1
rm -rf docker
sh install.sh

# Pull openssl modification 
printf "\nStep 4 - Installing http redirect\n\n"
printf "\n\tStep 4a - Installing lighttpd-mod-redirect\n"
opkg install lighttpd-mod-redirect
printf "\n\tStep 4b - Modifying 30-openssl.conf\n"
wget https://raw.githubusercontent.com/rdbh/openwrt-config/master/config.txt
cat config.txt >> /etc/lighttpd/conf.d/30-openssl.conf

# Clean up config.txt
printf "\nStep 5 - Removing temporary files\n"
rm config.txt
sed -i -e "/^\/root/d" /etc/sysupgrade.conf

# Restart the service
printf "\nStep 6 - Restarting http service\n"
/etc/init.d/lighttpd restart

# Completion Message
printf "Installation Complete\n\n"
