#! /bin/bash

if [ `whoami` != "root" ]; then
    echo "The script only run in root."
    exit
fi

source config.sh
source common.sh

make_dpkg_packages
update_system

install_block_cinder