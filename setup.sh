#!/bin/sh
# Script for setting up a new OpenWRT device
# Copyright 2020 R Dawson
# v0.2.1

echo "\nStep 1 - Updating Repository\n\n"
opkg update
echo "Step 2 - software installation\n"
echo "\tStep 2a - Installing tmux\n"
opkg install tmux
echo "\tStep 2b - Installing python 2.7\n"
opkg install python
echo "\tStep 2c - Installing git\n"
opkg install git
echo "\tStep 2d - Installing nano\n"
opkg install nano

echo "\nStep 3 - Installing py-kms\n"
echo "\tStep 3a - cloning repository\n"
git clone git://github.com/radawson/py-kms
echo "\tStep 3b - Transitioning to py-kms install script\n"
cd py-kms
sh install.sh

# Pull openssl modification 
echo "\nStep 4 - Installing http redirect\n"
echo "\tStep 4a - Installing lighttpd-mod-redirect\n"
opkg install lighttpd-mod-redirect
echo "\tStep 4b - Modifying 30-openssl.conf\n"
wget https://raw.githubusercontent.com/rdbh/openwrt-config/master/config.txt
cat config.txt >> /etc/lighttpd/conf.d/30-openssl.conf

# Clean up config.txt
echo "\tStep 4c - Removing temporary files\n"
rm config.txt

# Restart the service
echo "\tStep 4d - Restarting http service\n"
/etc/init.d/lighttpd restart