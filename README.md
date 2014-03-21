openstack-deploy
================

Openstack Havana deploy shell scripts on ubuntu server.

Ubuntu Version: ubuntu-12.04.4-server-amd64.iso

Precondition:

 * Make local dpkg packages debs.tgz

 * Open CPU virtualization in BIOS

 * Config network

    $ hostname controller

    $ cat /etc/hostname
    controller

    $ cat /etc/hosts
    127.0.0.1   localhost
    10.0.0.10   controller
    10.0.0.11   compute1

 * Fix config.sh

 * Fix etc/network/interfaces
