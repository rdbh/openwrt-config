#!/bin/bash
# Script for setting up a new OpenWRT device

opkg update
opkg install tmux python git

git clone https://github.com/radawson/py-kms
cd py-kms
./install.sh

# TODO: Add https redirect
