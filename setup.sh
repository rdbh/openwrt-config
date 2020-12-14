#!/bin/sh
# Script for setting up a new OpenWRT device
# Copyright 2020 R Dawson
# v0.2.2

# Exit on errors
set -e

# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

printf "\nStep 1 - Updating Repository\n\n"
opkg update
printf "Step 2 - software installation\n"
printf "\tStep 2a - Installing tmux\n"
opkg install tmux
printf "\tStep 2b - Installing python 2.7\n"
opkg install python-light
printf "\tStep 2c - Installing git\n"
opkg install git
# 0.2.2 removed nano to save space and simplify install
# printf "Step 2d - Installing nano"
# opkg install nano

printf "\nStep 3 - Installing py-kms\n\n"
printf "\tStep 3a - cloning repository\n"
git clone git://github.com/radawson/py-kms
printf "\tStep 3b - Transitioning to py-kms install script\n"
cd py-kms
sh install.sh

# Pull openssl modification 
printf "\nStep 4 - Installing http redirect\n\n"
printf "\tStep 4a - Installing lighttpd-mod-redirect\n"
opkg install lighttpd-mod-redirect
printf "\tStep 4b - Modifying 30-openssl.conf\n"
wget https://raw.githubusercontent.com/rdbh/openwrt-config/master/config.txt
cat config.txt >> /etc/lighttpd/conf.d/30-openssl.conf

# Clean up config.txt
printf "\tStep 4c - Removing temporary files\n"
rm config.txt

# Restart the service
printf "\tStep 4d - Restarting http service\n"
/etc/init.d/lighttpd restart

# Completion Message
printf "Installation Complete"