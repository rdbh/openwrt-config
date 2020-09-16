#!/bin/sh
# Script for setting up a new OpenWRT device

opkg update
opkg install tmux python git nano

git clone git://github.com/radawson/py-kms
cd py-kms
sh install.sh

# TODO: Add https redirect
