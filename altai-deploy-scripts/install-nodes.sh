#!/bin/bash
echo "Starting script $0 $@"

PARAM=$1
shift

cd "$(dirname $0)"

#DIRTY INSTALLER TEST SCRIPT
VAR=${VAR:-VAL}

INSTALLER_REPO=${INSTALLER_REPO:-"https://github.com/griddynamics/altai.git"}
INSTALLER_VERSION=${INSTALLER_VERSION:-"v0.1"}
INSTALLER_DIR=${INSTALLER_DIR:-"altai"}
[ -n "$SSH_KEY" ] || SSH_KEY=$(< ~/.ssh/id_rsa.pub)

ADMIN=`grep "admin-login-email"  master-node.json | sed 's/\s*"admin-login-email":\s\"//g' | sed 's/\",$//g'`
PASSWORD=`grep "admin-login-password"  master-node.json | sed 's/\s*"admin-login-password":\s\"//g' | sed 's/\",$//g'`



#-----------
NODE_NAME=`cat ~/altai-deploy-scripts/node_name`
NODE_IP=`lsdef $NODE_NAME -i ip | grep "ip=" | awk -F"=" {'print $2'}`


# If we have full install we should set master ip to use_master param
if [ -e ~/altai-deploy-scripts/use_master ]; then
    MASTER_NAME=`cat ~/altai-deploy-scripts/use_master`
    MASTER_NODE_IP=`lsdef $MASTER_NAME -i ip | grep "ip=" | awk -F"=" {'print $2'}`
    sed -i s/MASTER_NODE_IP/$MASTER_NODE_IP/ *.json
else
    sed -i s/MASTER_NODE_IP/$NODE_IP/ *.json
fi

#-----------
RUN_USER=root
export RUN_SERVER=$NODE_IP

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
COMPUTE_TCP_PORTS="22"
COMPUTE_UDP_PORTS="123"


if [ $# -ge 1  ]; then
        ENV=$1
else
        ENV="full"
fi

shift


REPO="openstack-$OS"

die() {
        log "$1"
        return 1
}

log() {
        echo "    $1 $2 $3"
}



exec_remote() {
        #ssh -q "${RUN_USER}@${RUN_SERVER}" "chroot /mnt/sys /bin/bash -c 'cd /root/; $@' "
        ssh -q "${RUN_USER}@${RUN_SERVER}" "$@"
}

exec_in_dir() {
        exec_remote "cd $1 && " "$2"
}


setup_env_repo() {
        log "Setting YUM repo on test server to environment: $ENV"
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
        REPO_PATH=`cat ~/altai-deploy-scripts/repo_path`
        log "Cloning installer from $INSTALLER_REPO on host $RUN_SERVER"
        exec_remote "yum -y install git"
        exec_remote "git clone $INSTALLER_REPO && cd $INSTALLER_DIR && git checkout $INSTALLER_VERSION && \
        sed -i 's#http://yum.griddynamics.net/yum/altai_v0.1_centos/altai-release-0.1-0.el6.noarch.rpm#${REPO_PATH}#g' ~/$INSTALLER_DIR/cookbooks/devgrid/attributes/default.rb "
}

config_installer() {
        rsync -av *.json "$RUN_USER"@"$RUN_SERVER":~/$INSTALLER_DIR/
}

install_master() {
        log "Running ./install.sh master on $RUN_SERVER"
        exec_remote "cd ~/$INSTALLER_DIR ; echo 'Showing master-node.json:'; cat master-node.json ; ./install.sh master ; retcode=$?; echo 'Exit code: $retcode'; exit $retcode"
        log "Done, exit code: $retcode"
}

install_node() {
        log "Running ./install.sh compute on $RUN_SERVER"
        exec_remote "cd ~/$INSTALLER_DIR  ; echo 'Showing compute-node.json:'; cat compute-node.json ; ./install.sh compute; retcode=$?; exit $retcode "
        log "Done, exit code: $retcode"
}

spawn_hw_node() {
        log "Spawning HW node $NODE_NAME"
        RUN_SERVER=$NODE_IP
        ./xcat-spawn-n $NODE_NAME
        log "Done, exit code: $retcode"
}


check_services() {
        log "Checking services... "
        for service in $SERVICES; do
            retcode=0
            exec_remote "ps aux | grep -v grep | grep  "$service" >/dev/null" || retcode=1
            if [ $retcode -eq 0 ]; then  log "Service: $service - ok"
            else die "Service: $service - NOT running";
            fi
        done
}

check_ports() {
        log "Checking open ports..."
        for port in $TCP_PORTS; do
            retcode1=0
            exec_remote "netstat -anp | grep -i 'tcp.*LISTEN'| grep ':$port'" || retcode1=1
            if [ $retcode -eq 0 ]; then  log "TCP Port: $port - ok"
            else die "TCP Port: $port - NOT listening";
            fi
        done

        for port in $UDP_PORTS; do
            retcode2=0
            exec_remote "netstat -anp | grep -i 'udp.*0\:\*' | grep ':$port' | grep -v 'dnsmasq'" || retcode2=1
            if [ $retcode -eq 0 ]; then  log "UDP Port: $port - ok"
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
        log "Checking web UI title:"
        wget -qO - http://$NODE_IP:80 | grep "Altai Private Cloud" || die "Web UI ERROR"
        log "Checking nova-manage:"
        exec_remote "nova-manage service list | grep enabled | grep compute | grep $NODE_NAME" || die "Compute service error"
}

check_node() {
        SERVICES=$COMPUTE_SERVICES
        check_services
        TCP_PORTS=$COMPUTE_TCP_PORTS
        UDP_PORTS=$COMPUTE_UDP_PORTS
        check_ports
}


success() {
        log ""
        log ""
        log "------------------------------------------"
        log "   Try it here:"
        log "   URL:            http://$MASTER_NODE_IP"
        log "   Login:          $ADMIN"
        log "   Password:       $PASSWORD"
}

show_info() {
        retcode=$?
        log "Privious task exit code: $retcode"
}

upload_image() {
        exec_remote "wget http://osc-build.vm.griddynamics.net/images/mini_image.img"
        exec_remote 'OS_USERNAME="admin" && OS_PASSWORD="topsecret" && OS_TENANT_NAME="systenant" && OS_AUTH_URL="http://172.18.40.107:5000/v2.0/" && OS_COMPUTE_API_VERSION="1.1" && OS_AUTH_STRATEGY="keystone" && NOVA_VERSION=1.1 && USE_KEYSTONE=true && glance add name="test-suite-image" disk_format=qcow2 container_format=ovf <mini_image.img'
}


retcode=0

#json_change "master-ip-public" "$MASTER_NODE_PUBLIC" "master-node.json"
#json_change "master-ip-public" "$MASTER_NODE_PUBLIC" "compute-node.json"

# FIXME: why was it commented out?
#json_change "master-ip-private" "$MASTER_NODE_PRIVATE" "master-node.json"
#json_change "master-ip-private" "$MASTER_NODE_PRIVATE" "compute-node.json"




case "$PARAM" in
    full)
        show_info
        spawn_hw_node && get_installer && config_installer && install_master && check_master && check_node || retcode=1
        success

        ;;
    master)  ## It's not functional yet
        show_info
        spawn_hw_node && get_installer && config_installer && install_master && check_master && check_node || retcode=1
        success
        ;;

    compute)
        show_info
        spawn_hw_node && get_installer && config_installer && install_node && check_node || retcode=1
        ;;

    upload-image)
        upload_image
        ;;
    *)
        log "Unknown parameter"
        ;;
esac


if [ $retcode -eq 0 ]; then
    log "Installation Successful"
else
    log "Installation failed. Try to debug"
fi

log "Exiting with code: $retcode"
exit $retcode 
