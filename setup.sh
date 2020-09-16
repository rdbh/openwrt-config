#!/bin/sh
# Script for setting up a new OpenWRT device

opkg update
opkg install tmux python git nano

git clone git://github.com/radawson/py-kms
cd py-kms
sh install.sh

# Pull openssl modification 
wget wget https://raw.githubusercontent.com/rdbh/openwrt-config/master/config.txt
cat config.txt >> /etc/lighttpd/conf.d/30-openssl.conf

# Clean up config.txt
rm config.txt

# Restart the service
/etc/init.d/lighttpd restart