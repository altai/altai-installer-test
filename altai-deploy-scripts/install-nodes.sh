#!/bin/bash -x

cd "$(dirname $0)"

#DIRTY INSTALLER TEST SCRIPT
VAR=${VAR:-VAL}

INSTALLER_REPO=${INSTALLER_REPO:-"https://github.com/griddynamics/altai.git"}
INSTALLER_VERSION=${INSTALLER_VERSION:-"v0.1"}
INSTALLER_DIR=${INSTALLER_DIR:-"altai"}
#MASTER_NET=172.18.36.0/24

#MASTER_NODE_PUBLIC=172.18.36.123
#COMPUTE1=172.18.36.124
#COMPUTE2=172.18.36.125

#SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQC+CvHo/7GsS7OvRF/eRx3kpvCY0IsF0Yd129OJ/KH6O+/5wrWjm4XmdhlxzIGTxYMYDzc//hkaypJ0AxrWHw3vmlTtAqrSyQIEKAcGuy4S53C7pBSRqSrURKb07BcJAh9C5qiRqgkLMKGodUb5k5edPEpmK6t+ZVe9ZqtOe0Vl7w== vkhomenko@griddynamics.com"
[ -n "$SSH_KEY" ] || SSH_KEY=$(< ~/.ssh/id_rsa.pub)

#ADMIN=`grep "admin-login-name"  master-node.json | sed 's/\s*"admin-login-name":\s\"//g' | sed 's/\",$//g'`
ADMIN=`grep "admin-login-email"  master-node.json | sed 's/\s*"admin-login-email":\s\"//g' | sed 's/\",$//g'`
PASSWORD=`grep "admin-login-password"  master-node.json | sed 's/\s*"admin-login-password":\s\"//g' | sed 's/\",$//g'`
#MASTER_NODE_PUBLIC=`grep "master-ip-public"  master-node.json | sed 's/\s*"master-ip-public":\s\"//g' | sed 's/\",$//g'`

#-----------
NODE_NAME=`cat ~/altai-deploy-scripts/node_name`
echo "NODE_NAME=$NODE_NAME"
MASTER_NODE_PUBLIC=`lsdef $NODE_NAME -i ip | grep "ip=" | awk -F"=" {'print $2'}`
echo "NODE_IP=$MASTER_NODE_PUBLIC"
sed -i s/MASTER_NODE_IP/$MASTER_NODE_PUBLIC/ *.json

#-----------
RUN_USER=root
export RUN_SERVER=$MASTER_NODE_PUBLIC

MASTER_SERVICES="memcached
focus
odb
mysqld
glance-api
glance-registry
ntpd
nova-api
nova-network
nova-scheduler
nova-objectstore
nova-xvpvncproxy
nova-billing-heart
nova-billing-os-amqp
rabbitmq-server
keystone
pdns
nova-dns"

MASTER_TCP_PORTS="80
5000"

MASTER_UDP_PORTS="53"

COMPUTE_SERVICES="ntpd
libvirtd
nova-compute"


COMPUTE_TCP_PORTS="80
5000"

COMPUTE_UDP_PORTS="53"


PARAM=$1
shift

if [ $# -ge 1  ]; then
        ENV=$1
else
        ENV="full"
fi

shift


REPO="openstack-$OS"

die() {
        echo "$1"
        return 1
}


exec_remote() {
        #ssh -q "${RUN_USER}@${RUN_SERVER}" "chroot /mnt/sys /bin/bash -c 'cd /root/; $@' "
        ssh -q "${RUN_USER}@${RUN_SERVER}" "$@"
}

exec_in_dir() {
        exec_remote "cd $1 && " "$2"
}


setup_env_repo() {
        echo "Setting YUM repo on test server to environment: $ENV"
        if [ "$ENV" == "master" ]; then
                REPO_PATH="/unstable"
        else
                REPO_PATH="/unstable/$ENV"
        fi

        SED_CMD="s#baseurl=http://osc-build.vm.griddynamics.net/.*openstack-.*#baseurl=http://osc-build.vm.griddynamics.net$REPO_PATH/openstack-$OS#g"
        exec_remote "sudo sed -i \"$SED_CMD\" /etc/yum.repos.d/os-env.repo"
        exec_remote "cat /etc/yum.repos.d/os-env.repo"
}

json_change() {
        param=$1
        value=$2
        jsonfile=$3
        sed -i "s/^.*\"$param\":.*/\t\"$param\": \"$value\",/" $jsonfile
}

get_installer() {
        pwd
        REPO_PATH=`cat ~/altai-deploy-scripts/repo_path`
        echo "REPO_PATH_1="${REPO_PATH}
        exec_remote "yum -y install git"
        exec_remote "git clone $INSTALLER_REPO && cd $INSTALLER_DIR && git checkout $INSTALLER_VERSION && \
        sed -i 's#http://yum.griddynamics.net/yum/altai_v0.1_centos/altai-release-0.1-0.el6.noarch.rpm#${REPO_PATH}#g' ~/$INSTALLER_DIR/cookbooks/devgrid/attributes/default.rb "
}

config_installer() {
        rsync -av *.json "$RUN_USER"@"$RUN_SERVER":~/$INSTALLER_DIR/
}

install_master() {
        exec_remote "cd ~/$INSTALLER_DIR ; echo 'Showing master-node.json:'; cat master-node.json ; ./install.sh master ; retcode=$?; echo 'Exit code: $retcode'; cat install.log; exit $retcode"
}

install_node() {
        exec_remote "cd ~/$INSTALLER_DIR  ; echo 'Showing compute-node.json:'; cat compute-node.json ; ./install.sh compute; retcode=$?; cat install.log; exit $retcode "
}

spawn_master() {
        echo "Showing master-node.json:"; cat master-node.json
        #RUN_SERVER=$MASTER_NODE_PUBLIC
        #HW_IPADDR=$MASTER_NODE_PUBLIC HW_NAME="installer-test-master" ./xcat-spawn
        
        #NODE_NAME=`cat ~/altai-deploy-scripts/node_name`
        RUN_SERVER=$MASTER_NODE_PUBLIC
        HW_IPADDR=$MASTER_NODE_PUBLIC
        HW_NAME="installer-test-master" 
        ./xcat-spawn-n $NODE_NAME
        
        # NODE_NAME=`cat ~/altai-deploy-scripts/node_name`
        # rsetboot $NODE_NAME net
        # rpower $NODE_NAME reset
        # echo -n "$NODE_NAME: booting"
        # until [[ `nodels $NODE_NAME nodelist.status` =~ "booted" ]]; do echo -n "."; sleep 5; done
        # echo "."
        # echo "$NODE_NAME: ready!"
}

spawn_node() {
        RUN_SERVER=$COMPUTE1
        HW_IPADDR=$COMPUTE1 HW_NAME="installer-test-compute1" ./xcat-spawn
}

check_services() {
        echo "Checking services... "
        for service in $SERVICES; do
            retcode=0
            exec_remote "ps aux | grep -v grep | grep  "$service" >/dev/null" || retcode=1
            if [ $retcode -eq 0 ]; then  echo "Service: $service - ok"
            else die "Service: $service - NOT running";
            fi
        done
}

check_ports() {
        echo "Checking open ports..."
        for port in $TCP_PORTS; do
            retcode1=0
            exec_remote "netstat -anp | grep -i 'tcp.*LISTEN'| grep ':$port'" || retcode1=1
            if [ $retcode -eq 0 ]; then  echo "TCP Port: $port - ok"
            else die "TCP Port: $port - NOT listening";
            fi
        done

        for port in $UDP_PORTS; do
            retcode2=0
            exec_remote "netstat -anp | grep -i 'udp.*0\:\*' | grep ':$port' | grep -v 'dnsmasq'" || retcode2=1
            if [ $retcode -eq 0 ]; then  echo "UDP Port: $port - ok"
            else die "UDP Port:$port - NOT listening";
            fi
        done
        retcode=1
        [ $retcode1 -eq 0 ] && [ $retcode2 -eq 0 ] && retcode=0
}



check_master() {
        SERVICES=$MASTER_SERVICES
        check_services
        TCP_PORTS=$MASTER_TCP_PORTS
        UDP_PORTS=$MASTER_UDP_PORTS
        check_ports
        # wget
        echo "Checking web UI title:"
        wget -qO - $MASTER_NODE_PUBLIC:8080 | grep "Altai Private Cloud" || die "Web UI ERROR"
}

check_node() {
        SERVICES=$COMPUTE_SERVICES
        check_services
}


success() {
        echo ""
        echo ""
        echo "------------------------------------------"
        echo "   Try it here:"
        echo "   URL:            http://$MASTER_NODE_PUBLIC:8080"
        echo "   Login:          $ADMIN"
        echo "   Password:       $PASSWORD"
}

show_info() {
        retcode=$?
        echo "Privious task exit code: $retcode"
}

retcode=0

#json_change "master-ip-public" "$MASTER_NODE_PUBLIC" "master-node.json"
#json_change "master-ip-public" "$MASTER_NODE_PUBLIC" "compute-node.json"

# FIXME: why was it commented out?
#json_change "master-ip-private" "$MASTER_NODE_PRIVATE" "master-node.json"
#json_change "master-ip-private" "$MASTER_NODE_PRIVATE" "compute-node.json"

case "$PARAM" in
    clean)
#        lxc-stop -n installer-test-compute1
#        lxc-destroy -n installer-test-compute1
#        lxc-stop -n installer-test-master
#        lxc-destroy -n installer-test-master
        ;;
    full)
#        export $SSH_KEY
        show_info
        spawn_master && get_installer && config_installer && install_master && check_master && check_node || retcode=1
#        spawn_node && get_installer && config_installer && install_node && check_node || retcode=1

        ;;
    *)
        echo "Unknown parameter"
        ;;
esac

if [ $retcode -eq 0 ]; then 
    echo "Installation Successful"
    success
else
    echo "Installation failed. Try to debug"
    success
fi
exit $retcode
