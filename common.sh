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

    sed -i "s/127.0.0.1/controller/g" /etc/mysql/my.cnf
    sed -i "/^character_set_server/d" /etc/mysql/my.cnf
    sed -i "/^\[mysqld\]/a character_set_server=utf8" /etc/mysql/my.cnf

    service mysql restart

    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON *.* to 'root'@'%' IDENTIFIED BY '$MYSQL_PASSWD' WITH GRANT OPTION;"
    mysql -uroot -p$MYSQL_PASSWD -e "USE mysql; DELETE FROM user WHERE user='';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS nova;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE nova;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS glance;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE glance;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS keystone;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE keystone;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS neutron;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE neutron;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS cinder;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE cinder;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_DBPASS';"
    mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE IF EXISTS dash;"
    mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE dash;"
    mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON dash.* TO 'dash'@'%' IDENTIFIED BY '$DASH_DBPASS';"
}

function install_rabbitmq() {
    apt-get install -y --force-yes rabbitmq-server

    rabbitmqctl change_password guest $RABBIT_PASS
}

function install_keystone() {
    apt-get install -y --force-yes keystone

    sed -i "s/ADMIN_TOKEN/$ADMIN_TOKEN/g" etc/keystone/keystone.conf
    sed -i "s/KEYSTONE_DBPASS/$KEYSTONE_DBPASS/g" etc/keystone/keystone.conf
    cp etc/keystone/keystone.conf /etc/keystone/keystone.conf

    service keystone restart
    keystone-manage db_sync
}

function init_keystone_data() {
    source keystone_data.sh
}

function install_glance() {
    apt-get install -y --force-yes glance python-glanceclient

    sed -i "s/GLANCE_DBPASS/$GLANCE_DBPASS/g" etc/glance/glance-api.conf
    sed -i "s/GLANCE_PASS/$GLANCE_PASS/g" etc/glance/glance-api.conf
    cp etc/glance/glance-api.conf /etc/glance/glance-api.conf

    sed -i "s/GLANCE_DBPASS/$GLANCE_DBPASS/g" etc/glance/glance-registry.conf
    sed -i "s/GLANCE_PASS/$GLANCE_PASS/g" etc/glance/glance-registry.conf
    cp etc/glance/glance-registry.conf /etc/glance/glance-registry.conf

    service glance-registry restart
    service glance-api restart
    glance-manage db_sync
}

function install_controller_nova() {
    apt-get install -y --force-yes nova-novncproxy novnc nova-api \
        nova-ajax-console-proxy nova-cert nova-conductor \
        nova-consoleauth nova-doc nova-scheduler python-novaclient

    sed -i "s/RABBIT_PASS/$RABBIT_PASS/g" etc/nova/nova.conf
    sed -i "s/NOVA_DBPASS/$NOVA_DBPASS/g" etc/nova/nova.conf
    sed -i "s/NOVA_PASS/$NOVA_PASS/g" etc/nova/nova.conf
    sed -i "s/MY_IP/$MY_IP/g" etc/nova/nova.conf
    sed -i "s/NEUTRON_PASS/$NEUTRON_PASS/g" etc/nova/nova.conf
    sed -i "s/METADATA_PASS/$NEUTRON_PASS/g" etc/nova/nova.conf
    cp etc/nova/nova.conf /etc/nova/nova.conf

    sed -i "s/NOVA_PASS/$NOVA_PASS/g" etc/nova/api-paste.ini
    cp etc/nova/api-paste.ini /etc/nova/api-paste.conf

    service nova-api restart
    service nova-cert restart
    service nova-consoleauth restart
    service nova-scheduler restart
    service nova-conductor restart
    service nova-novncproxy restart
    nova-manage db sync
}

function install_compute_nova() {
    apt-get install -y --force-yes nova-compute-kvm python-guestfs

    # make the current kernel readable
    #dpkg-statoverride --update --add root root 0644 /boot/vmlinuz-$(uname -r)
    chmod 0644 /boot/vmlinuz-*

    sed -i "s/RABBIT_PASS/$RABBIT_PASS/g" etc/nova/nova.conf
    sed -i "s/NOVA_DBPASS/$NOVA_DBPASS/g" etc/nova/nova.conf
    sed -i "s/NOVA_PASS/$NOVA_PASS/g" etc/nova/nova.conf
    sed -i "s/MY_IP/$MY_IP/g" etc/nova/nova.conf
    sed -i "s/NEUTRON_PASS/$NEUTRON_PASS/g" etc/nova/nova.conf
    sed -i "s/METADATA_PASS/$NEUTRON_PASS/g" etc/nova/nova.conf
    cp etc/nova/nova.conf /etc/nova/nova.conf

    sed -i "s/NOVA_PASS/$NOVA_PASS/g" etc/nova/api-paste.ini
    cp etc/nova/api-paste.ini /etc/nova/api-paste.conf

    service nova-compute restart
}

function install_controller_neutron() {
    apt-get install -y --force-yes neutron-server neutron-dhcp-agent neutron-l3-agent \
        neutron-plugin-openvswitch-agent neutron-plugin-openvswitch openvswitch-switch

    sed -i -e "
s/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g;
s/^#net.ipv4.conf.all.rp_filter=1/net.ipv4.conf.all.rp_filter=0/g;
s/^#net.ipv4.conf.default.rp_filter=1/net.ipv4.conf.default.rp_filter=0/g;
" /etc/sysctl.conf
    sysctl -p

    sed -i "s/RABBIT_PASS/$RABBIT_PASS/g" etc/neutron/neutron.conf
    sed -i "s/NEUTRON_DBPASS/$NEUTRON_DBPASS/g" etc/neutron/neutron.conf
    sed -i "s/NEUTRON_PASS/$NEUTRON_PASS/g" etc/neutron/neutron.conf
    cp etc/neutron/neutron.conf /etc/neutron/neutron.conf

    sed -i "s/NEUTRON_PASS/$NEUTRON_PASS/g" etc/neutron/metadata_agent.ini
    sed -i "s/METADATA_PASS/$NEUTRON_PASS/g" etc/neutron/metadata_agent.ini
    cp etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini

    sed -i "s/DATA_INTERFACE_IP/$MY_IP/g" etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini
    cp etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini

    service neutron-server restart
    service neutron-dhcp-agent restart
    service neutron-l3-agent restart
    service neutron-metadata-agent restart
    service neutron-plugin-openvswitch-agent restart
    service openvswitch-switch restart

    ovs-vsctl add-br br-int
    ovs-vsctl add-br br-ex
    ovs-vsctl add-port br-ex eth0   # EXTERNAL_INTERFACES
}

function install_compute_neutron() {
    apt-get install -y --force-yes neutron-plugin-openvswitch-agent openvswitch-switch

    sed -i -e "
s/^#net.ipv4.conf.all.rp_filter=1/net.ipv4.conf.all.rp_filter=0/g;
s/^#net.ipv4.conf.default.rp_filter=1/net.ipv4.conf.default.rp_filter=0/g;
" /etc/sysctl.conf
    sysctl -p

    sed -i "s/RABBIT_PASS/$RABBIT_PASS/g" etc/neutron/neutron.conf
    sed -i "s/NEUTRON_DBPASS/$NEUTRON_DBPASS/g" etc/neutron/neutron.conf
    sed -i "s/NEUTRON_PASS/$NEUTRON_PASS/g" etc/neutron/neutron.conf
    cp etc/neutron/neutron.conf /etc/neutron/neutron.conf

    sed -i "s/DATA_INTERFACE_IP/$MY_IP/g" etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini
    cp etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini

    service neutron-plugin-openvswitch-agent restart
    service openvswitch-switch restart

    ovs-vsctl add-br br-int
}

function install_dashboard() {
    apt-get install -y --force-yes memcached libapache2-mod-wsgi openstack-dashboard

    # This theme prevents translations
    apt-get remove --purge openstack-dashboard-ubuntu-theme
}
