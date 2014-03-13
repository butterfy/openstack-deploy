openstack-deploy
================

Openstack Havana deploy shell scripts on ubuntu server.

Precondition:
 * Open CPU virtualization in BIOS
 * Config network
    $ cat /etc/hosts
    127.0.0.1   localhost
    10.0.0.10   controller
    10.0.0.11   compute1
