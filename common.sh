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
    apt-get install -y --force-yes python-software-properties
    apt-get update && apt-get -y --force-yes dist-upgrade
    apt-get install -y --force-yes python-mysqldbS
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

    #mysql -uroot -p$MYSQL_PASSWD -e "grant all privileges on *.* to 'root'@'%' identified by '$MYSQL_PASSWD' with grant option;"
    #mysql -uroot -p$MYSQL_PASSWD -e "use mysql;delete from user where user='';"
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
}

function install_keystone() {
    apt-get install -y --force-yes keystone

    sed -i "s/[# ]*connection[ ]*=.*/connection = mysql:\/\/keystone:$KEYSTONE_DBPASS@controller\/keystone/g" /etc/keystone/keystone.conf
    sed -i "s/[# ]*token_format[ ]*=.*/token_format = UUID/g" /etc/keystone/keystone.conf
    sed -i "s/[# ]*admin_token[ ]*=.*/admin_token = $ADMIN_TOKEN/g" /etc/keystone/keystone.conf

    service keystone restart
    keystone-manage db_sync
}

function init_keystone_data() {
    source keystone_data.sh
}

function install_glance() {
    apt-get install -y --force-yes glance

    sed -i -e "
s/^auth_host =.*/auth_host = controller/g;
s/^admin_tenant_name =.*/admin_tenant_name = service/g;
s/^admin_user =.*/admin_user = glance/g;
s/^admin_password =.*/admin_password = $GLANCE_PASS/g;
" /etc/glance/glance-api.conf

    sed -i -e "
s/^auth_host =.*/auth_host = controller/g;
s/^admin_tenant_name =.*/admin_tenant_name = service/g;
s/^admin_user =.*/admin_user = glance/g;
s/^admin_password =.*/admin_password = $GLANCE_PASS/g;
" /etc/glance/glance-registry.conf

    sed -i "s/^sql_connection[ ]*=.*/sql_connection = mysql:\/\/glance:$GLANCE_DBPASS@controller\/glance/g" /etc/glance/glance-api.conf
    sed -i "s/[# ]*flavor[ ]*=/flavor = keystone/g" /etc/glance/glance-api.conf
    if ! grep -q "flavor = keystone" /etc/glance/glance-api.conf; then
        echo "flavor = keystone" >> /etc/glance/glance-api.conf
    fi

    service glance-registry restart
    service glance-api restart
    glance-manage db_sync
}

function install_controller_nova() {
    apt-get install -y --force-yes nova-novncproxy novnc nova-api \
        nova-ajax-console-proxy nova-cert nova-conductor \
        nova-consoleauth nova-doc nova-scheduler

    sed -i -e "
s/^auth_host =.*/auth_host = controller/g;
s/^admin_tenant_name =.*/admin_tenant_name = service/g;
s/^admin_user =.*/admin_user = nova/g;
s/^admin_password =.*/admin_password = $NOVA_PASS/g;
" /etc/nova/api-paste.ini

    cat <<EOF >/etc/nova/nova.conf
[DEFAULT]
dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova
force_dhcp_release=True
iscsi_helper=tgtadm
libvirt_use_virtio_for_bridges=True
connection_type=libvirt
root_helper=sudo nova-rootwrap /etc/nova/rootwrap.conf
verbose=True
ec2_private_dns_show_ip=True
api_paste_config=/etc/nova/api-paste.ini
volumes_path=/var/lib/nova/volumes
enabled_apis=ec2,osapi_compute,metadata

# RabbitMQ
rpc_backend = nova.rpc.impl_kombu
rabbit_host = controller
rabbit_password = $RABBIT_PASS

# vnc
my_ip = controller
vncserver_listen = controller
vncserver_proxyclient_address = controller

auth_strategy=keystone

network_api_class=nova.network.neutronv2.api.API
neutron_url=http://controller:9696
neutron_auth_strategy=keystone
neutron_admin_tenant_name=service
neutron_admin_username=neutron
neutron_admin_password=$NEUTRON_PASS
neutron_admin_auth_url=http://controller:35357/v2.0
linuxnet_interface_driver=nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver=nova.virt.firewall.NoopFirewallDriver
security_group_api=neutron

[database]
# The SQLAlchemy connection string used to connect to the database
connection = mysql://nova:$NOVA_DBPASS@controller/nova

[keystone_authtoken]
auth_host = controller
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = nova
admin_password = $NOVA_PASS
EOF

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
    #chmod 0644 /boot/vmlinuz*

    sed -i -e "
s/^auth_host =.*/auth_host = controller/g;
s/^admin_tenant_name =.*/admin_tenant_name = service/g;
s/^admin_user =.*/admin_user = nova/g;
s/^admin_password =.*/admin_password = $NOVA_PASS/g;
" /etc/nova/api-paste.ini

    cat <<EOF >/etc/nova/nova.conf
[DEFAULT]
dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova
force_dhcp_release=True
iscsi_helper=tgtadm
libvirt_use_virtio_for_bridges=True
connection_type=libvirt
root_helper=sudo nova-rootwrap /etc/nova/rootwrap.conf
verbose=True
ec2_private_dns_show_ip=True
api_paste_config=/etc/nova/api-paste.ini
volumes_path=/var/lib/nova/volumes
enabled_apis=ec2,osapi_compute,metadata

# RabbitMQ
rpc_backend = nova.rpc.impl_kombu
rabbit_host = controller
rabbit_password = $RABBIT_PASS

# vnc
my_ip = $MY_IP
vnc_enabled = True
vncserver_listen = 0.0.0.0
vncserver_proxyclient_address = $MY_IP
novncproxy_base_url=http://controller:6080/vnc_auto.html

auth_strategy=keystone

glance_host=controller

network_api_class=nova.network.neutronv2.api.API
neutron_url=http://controller:9696
neutron_auth_strategy=keystone
neutron_admin_tenant_name=service
neutron_admin_username=neutron
neutron_admin_password=$NEUTRON_PASS
neutron_admin_auth_url=http://controller:35357/v2.0
linuxnet_interface_driver=nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver=nova.virt.firewall.NoopFirewallDriver
security_group_api=neutron

[database]
# The SQLAlchemy connection string used to connect to the database
connection = mysql://nova:$NOVA_DBPASS@controller/nova

[keystone_authtoken]
auth_host = controller
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = nova
admin_password = $NOVA_PASS
EOF

    service nova-compute restart
}

function install_dashboard() {
    apt-get install -y --force-yes memcached libapache2-mod-wsgi openstack-dashboard
}

function install_controller_neutron() {
    apt-get install -y --force-yes neutron-server openvswitch-switch

    sed -i -e "
s/^auth_host =.*/auth_host = controller/g;
s/^admin_tenant_name =.*/admin_tenant_name = service/g;
s/^admin_user =.*/admin_user = neutron/g;
s/^admin_password =.*/admin_password = $NEUTRON_PASS/g;
" /etc/neutron/neutron.conf

    sed -i -e "
s/^# rabbit_host = .*/rabbit_host = controller/g;
s/^# rabbit_password = .*/rabbit_password = $RABBIT_PASS/g;
" /etc/neutron/neutron.conf

    sed -i "s/^connection[ ]*=.*/connection = mysql:\/\/neutron:$NEUTRON_DBPASS@controller\/neutron/g" /etc/neutron/neutron.conf

    service neutron-server restart

    apt-get install -y --force-yes neutron-plugin-openvswitch

    cat <<PLUGIN > /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini
[securitygroup]
# Firewall driver for realizing neutron security group function.
firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

[agent]

[ovs]
tenant_network_type = gre
tunnel_id_ranges = 1:1000
enable_tunneling = True
integration_bridge = br-int
tunnel_bridge = br-tun
local_ip = controller
PLUGIN

    service openvswitch-switch restart
}

function install_compute_neutron() {
    sed -i -e "
s/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g;
s/^#net.ipv4.conf.all.rp_filter=1/net.ipv4.conf.all.rp_filter=0/g;
s/^#net.ipv4.conf.default.rp_filter=1/net.ipv4.conf.default.rp_filter=0/g;
" /etc/sysctl.conf
    sysctl -p

    apt-get install -y --force-yes neutron-plugin-openvswitch-agent

    sed -i -e "
s/^auth_host =.*/auth_host = controller/g;
s/^admin_tenant_name =.*/admin_tenant_name = service/g;
s/^admin_user =.*/admin_user = neutron/g;
s/^admin_password =.*/admin_password = $NEUTRON_PASS/g;
" /etc/neutron/neutron.conf

    sed -i -e "
s/^# rabbit_host = .*/rabbit_host = controller/g;
s/^# rabbit_password = .*/rabbit_password = $RABBIT_PASS/g;
" /etc/neutron/neutron.conf

    sed -i "s/^connection[ ]*=.*/connection = mysql:\/\/neutron:$NEUTRON_DBPASS@controller\/neutron/g" /etc/neutron/neutron.conf

    service neutron-plugin-openvswitch-agent restart
    ovs-vsctl add-br br-int
}
