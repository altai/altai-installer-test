#!/bin/bash

cd "$(dirname $0)"

RUN_USER="jenkins"
RUN_SERVER="openstack-xcat.vm.griddynamics.net"

PARAM=$1
NODE_NAME=$2
shift

if [ $# -ge 1  ]; then
        ENV=$1
else
        ENV=""
fi

shift

exec_remote() {
        ssh "$RUN_USER"@"$RUN_SERVER" "$@"

}

deploy_install_script() {
        sudo yum install -y rsync
        echo "REPO_PATH="$REPO_PATH
        echo $REPO_PATH > ./altai-deploy-scripts/repo_path
        echo "NODE_NAME="$NODE_NAME
        echo $NODE_NAME > ./altai-deploy-scripts/node_name
        rsync -av "./altai-deploy-scripts" "$RUN_USER@$RUN_SERVER:~/"
}

retcode=0

case "PARAM" in
    compute)
        echo "Creating new HW machine on $NODE_NAME"
        echo "Installing as compute node"
        deploy_install_script
        exec_remote "~/altai-deploy-scripts/install-nodes.sh compute"
        retcode=$?
        ;;
    master)
        echo "Creating new HW machine on $NODE_NAME"
        echo "Installing as master node"
        deploy_install_script
        exec_remote "~/altai-deploy-scripts/install-nodes.sh master"
        retcode=$?
        ;;
    *)
        echo "Creating new HW machine on $NODE_NAME"
        echo "Installing as master+compute node"
        deploy_install_script
        exec_remote "~/altai-deploy-scripts/install-nodes.sh full"
        retcode=$?
        ;;

esac

exit $retcode
