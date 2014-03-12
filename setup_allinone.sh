#! /bin/bash

if [ `whoami` != "root" ]; then
    echo "The script only run in root."
    exit
fi

source config.sh
source common.sh

make_dpkg_packages
update_system
install_mysql
install_rabbitmq
install_keystone
init_keystone_data
install_glance
install_controller_nova
install_compute_nova
install_dashboard
