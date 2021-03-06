function get_gateway() {
    gates=`ip route | grep default | awk '{print $3}'`
    for gate in $gates; do
        if [ -n "$gate" ]; then
            echo $gate
            break
        fi
    done
}

function get_netmask() {
    netmask=`ifconfig $1 | grep "Mask:" | awk -F ':' '{print $4}'`
    echo $netmask
}

function update_network_interfaces() {
    gateway=`get_gateway`
    netmask=`get_netmask $EXTERNAL_INTERFACE`

    cp etc/network/interfaces /etc/network/interfaces
    sed -i "s/EXTERNAL_INTERFACE_IP/$EXTERNAL_INTERFACE_IP/g" /etc/network/interfaces
    sed -i "s/NETMASK/$netmask/g" /etc/network/interfaces
    sed -i "s/GATEWAY/$gateway/g" /etc/network/interfaces
    sed -i "s/INTERNAL_INTERFACE_IP/$INTERNAL_INTERFACE_IP/g" /etc/network/interfaces

    /etc/init.d/networking restart
}

function make_dpkg_packages() {
    if [ -e /var/lib/dpkg/lock ]; then
        rm /var/lib/dpkg/lock
    fi
    if [ -e /var/cache/apt/archives/lock ]; then
        rm /var/cache/apt/archives/lock
    fi

    tar zxvf debs.tgz
    cp debs/* /var/cache/apt/archives/
    echo "deb file:/var/cache/apt/ archives/" > /etc/apt/sources.list
    apt-get update
}

function update_system() {
    apt-get install -y --force-yes ntp
    apt-get install -y --force-yes python-mysqldb
    apt-get install -y --force-yes python-software-properties
    apt-get update && apt-get -y --force-yes dist-upgrade
}

function install_mysql() {
    cat <<MYSQL_PRESEED | debconf-set-selections
mysql-server-5.5 mysql-server/root_password password $MYSQL_PASSWD
mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PASSWD
mysql-server-5.5 mysql-server/start_on_boot boolean true
MYSQL_PRESEED

    apt-get install -y --force-yes mysql-server

    sed -i "s/127.0.0.1/0.0.0.0/g" /etc/mysql/my.cnf
    sed -i "/^character_set_server/d" /etc/mysql/my.cnf
    sed -i "/^\[mysqld\]/a character_set_server=utf8" /etc/mysql/my.cnf

    service mysql restart

    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON *.* to 'root'@'%' IDENTIFIED BY '$MYSQL_PASSWD' WITH GRANT OPTION;"
    mysql -uroot -p$MYSQL_PASSWD -e "USE mysql; DELETE FROM user WHERE user='';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS nova;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE nova;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS glance;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE glance;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS keystone;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE keystone;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS neutron;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE neutron;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS cinder;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE cinder;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$CINDER_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS dash;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE dash;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON dash.* TO 'dash'@'localhost' IDENTIFIED BY '$DASH_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON dash.* TO 'dash'@'%' IDENTIFIED BY '$DASH_DBPASS';"
}

function install_rabbitmq() {
    apt-get install -y --force-yes rabbitmq-server

    rabbitmqctl change_password guest $RABBIT_PASS
}

function install_keystone() {
    apt-get install -y --force-yes keystone

    cp etc/keystone/keystone.conf /etc/keystone/keystone.conf
    sed -i "s/CONTROLLER/$CONTROLLER/g" /etc/keystone/keystone.conf
    sed -i "s/ADMIN_TOKEN/$ADMIN_TOKEN/g" /etc/keystone/keystone.conf
    sed -i "s/KEYSTONE_DBPASS/$KEYSTONE_DBPASS/g" /etc/keystone/keystone.conf

    service keystone restart

    keystone-manage db_sync
}

function init_keystone_data() {
    source keystone_data.sh
}

function install_glance() {
    apt-get install -y --force-yes glance python-glanceclient

    cp etc/glance/glance-api.conf /etc/glance/glance-api.conf
    sed -i "s/CONTROLLER/$CONTROLLER/g" /etc/glance/glance-api.conf
    sed -i "s/GLANCE_DBPASS/$GLANCE_DBPASS/g" /etc/glance/glance-api.conf
    sed -i "s/GLANCE_PASS/$GLANCE_PASS/g" /etc/glance/glance-api.conf

    cp etc/glance/glance-registry.conf /etc/glance/glance-registry.conf
    sed -i "s/CONTROLLER/$CONTROLLER/g" /etc/glance/glance-registry.conf
    sed -i "s/GLANCE_DBPASS/$GLANCE_DBPASS/g" /etc/glance/glance-registry.conf
    sed -i "s/GLANCE_PASS/$GLANCE_PASS/g" /etc/glance/glance-registry.conf

    glance-manage db_sync

    service glance-registry restart
    service glance-api restart
}

function update_nova_conf() {
    cp etc/nova/nova.conf /etc/nova/nova.conf
    sed -i "s/CONTROLLER/$CONTROLLER/g" /etc/nova/nova.conf
    sed -i "s/RABBIT_PASS/$RABBIT_PASS/g" /etc/nova/nova.conf
    sed -i "s/NOVA_DBPASS/$NOVA_DBPASS/g" /etc/nova/nova.conf
    sed -i "s/NOVA_PASS/$NOVA_PASS/g" /etc/nova/nova.conf
    sed -i "s/MY_IP/$INTERNAL_INTERFACE_IP/g" /etc/nova/nova.conf
    sed -i "s/EXTERNAL_INTERFACE_IP/$EXTERNAL_INTERFACE_IP/g" /etc/nova/nova.conf
    sed -i "s/NEUTRON_PASS/$NEUTRON_PASS/g" /etc/nova/nova.conf
    sed -i "s/METADATA_PASS/$NEUTRON_PASS/g" /etc/nova/nova.conf

    cp etc/nova/api-paste.ini /etc/nova/api-paste.ini
    sed -i "s/CONTROLLER/$CONTROLLER/g" /etc/nova/api-paste.ini
    sed -i "s/NOVA_PASS/$NOVA_PASS/g" /etc/nova/api-paste.ini
}

function install_controller_nova() {
    apt-get install -y --force-yes nova-novncproxy novnc nova-api \
        nova-ajax-console-proxy nova-cert nova-conductor \
        nova-consoleauth nova-doc nova-scheduler python-novaclient

    update_nova_conf

    nova-manage db sync

    service nova-api restart
    service nova-cert restart
    service nova-consoleauth restart
    service nova-scheduler restart
    service nova-conductor restart
    service nova-novncproxy restart
}

function install_compute_nova() {
    apt-get install -y --force-yes nova-compute-kvm python-guestfs

    # make the current kernel readable
    #dpkg-statoverride --update --add root root 0644 /boot/vmlinuz-$(uname -r)
    chmod 0644 /boot/vmlinuz-*

    update_nova_conf

    service nova-compute restart
}

function update_network_packet_conf() {
    sed -i -e "
s/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g;
s/^#net.ipv4.conf.all.rp_filter=1/net.ipv4.conf.all.rp_filter=0/g;
s/^#net.ipv4.conf.default.rp_filter=1/net.ipv4.conf.default.rp_filter=0/g;
" /etc/sysctl.conf
    sysctl -p

    service networking restart
}

function update_neutron_conf() {
    cp etc/neutron/neutron.conf /etc/neutron/neutron.conf
    sed -i "s/CONTROLLER/$CONTROLLER/g" /etc/neutron/neutron.conf
    sed -i "s/RABBIT_PASS/$RABBIT_PASS/g" /etc/neutron/neutron.conf
    sed -i "s/NEUTRON_DBPASS/$NEUTRON_DBPASS/g" /etc/neutron/neutron.conf
    sed -i "s/NEUTRON_PASS/$NEUTRON_PASS/g" /etc/neutron/neutron.conf

    cp etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini
    cp etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini

    cp etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini
    sed -i "s/DATA_INTERFACE_IP/$INTERNAL_INTERFACE_IP/g" /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini
}

function install_controller_neutron() {
    update_network_packet_conf

    apt-get install -y --force-yes neutron-server neutron-dhcp-agent neutron-l3-agent \
        neutron-plugin-openvswitch-agent openvswitch-datapath-dkms neutron-plugin-openvswitch

    update_neutron_conf

    cp etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini
    sed -i "s/CONTROLLER/$CONTROLLER/g" /etc/neutron/metadata_agent.ini
    sed -i "s/NEUTRON_PASS/$NEUTRON_PASS/g" /etc/neutron/metadata_agent.ini
    sed -i "s/METADATA_PASS/$NEUTRON_PASS/g" /etc/neutron/metadata_agent.ini

    service openvswitch-switch restart

    ovs-vsctl add-br br-int
    ovs-vsctl add-br br-ex
    ovs-vsctl add-port br-ex $EXTERNAL_INTERFACE

    update_network_interfaces

    service neutron-server restart
    service neutron-dhcp-agent restart
    service neutron-l3-agent restart
    service neutron-metadata-agent restart
    service neutron-plugin-openvswitch-agent restart
}

function init_neutron_data() {
    source openrc.sh

    export LC_ALL=C
    neutron net-create ext-net --router:external=True --provider:network_type gre --provider:segmentation_id 2
    neutron subnet-create ext-net --allocation-pool start=$FLOATING_IP_START,end=$FLOATING_IP_END \
        --gateway=$EXTERNAL_INTERFACE_GATEWAY --enable_dhcp=False $EXTERNAL_INTERFACE_CIDR
    neutron router-create ext-to-int
    neutron router-gateway-set ext-to-int ext-net
}

function install_compute_neutron() {
    update_network_packet_conf

    apt-get install -y --force-yes neutron-plugin-openvswitch-agent openvswitch-datapath-dkms

    update_neutron_conf

    service openvswitch-switch restart

    ovs-vsctl add-br br-int

    service neutron-plugin-openvswitch-agent restart
}

function update_cinder_conf() {
    cp etc/cinder/cinder.conf /etc/cinder/cinder.conf
    sed -i "s/CONTROLLER/$CONTROLLER/g" /etc/cinder/cinder.conf
    sed -i "s/RABBIT_PASS/$RABBIT_PASS/g" /etc/cinder/cinder.conf
    sed -i "s/CINDER_DBPASS/$CINDER_DBPASS/g" /etc/cinder/cinder.conf

    cp etc/cinder/api-paste.ini /etc/cinder/api-paste.ini
    sed -i "s/CONTROLLER/$CONTROLLER/g" /etc/cinder/api-paste.ini
    sed -i "s/CINDER_PASS/$CINDER_PASS/g" /etc/cinder/api-paste.ini
}

function install_controller_cinder() {
    apt-get install -y --force-yes cinder-api cinder-scheduler

    update_cinder_conf

    cinder-manage db sync

    service cinder-scheduler restart
    service cinder-api restart
}

function install_block_cinder() {
    apt-get install -y --force-yes lvm2 cinder-volume

    volume_dev=`findfs LABEL=$CINDER_VOLUMES`
    pvcreate $volume_dev
    vgcreate cinder-volumes $volume_dev

    update_cinder_conf

    service cinder-volume restart
    service tgt restart
}

function install_dashboard() {
    apt-get install -y --force-yes memcached libapache2-mod-wsgi openstack-dashboard

    # This theme prevents translations
    #apt-get remove -y --purge openstack-dashboard-ubuntu-theme

    service apache2 restart
    service memcached restart
}
