#!/bin/bash
echo "Starting script $0 $@"

cd "$(dirname $0)"

RUN_USER="jenkins"
RUN_SERVER="openstack-xcat.vm.griddynamics.net"

PARAM=$1
NODE_NAME=$2
OS_MODE=$3
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

log() {
        echo "    $1 $2 $3"
}

deploy_install_script() {
        log "Using repo: "$REPO_PATH
        echo $REPO_PATH > ./altai-deploy-scripts/repo_path
        echo "Deploying to node: "$NODE_NAME
        echo $NODE_NAME > ./altai-deploy-scripts/node_name
        [[ $MNODE ]] && echo $MNODE > ./altai-deploy-scripts/use_master
        [[ $INSTALLER_VERSION ]] && echo $INSTALLER_VERSION > ./altai-deploy-scripts/INSTALLER_VERSION
        echo "INSTALLER_VERSION="$INSTALLER_VERSION
	rsync -av "./altai-deploy-scripts" "$RUN_USER@$RUN_SERVER:~/"
}

clean() {
        rm -f ./altai-deploy-scripts/repo_path ./altai-deploy-scripts/node_name ./altai-deploy-scripts/use_master ./altai-deploy-scripts/INSTALLER_VERSION
        exec_remote "rm -f ./altai-deploy-scripts/repo_path ./altai-deploy-scripts/node_name ./altai-deploy-scripts/use_master ./altai-deploy-scripts/INSTALLER_VERSION"
}

retcode=0



case "$PARAM" in
    compute)
        log "Running install compute script machine $NODE_NAME"
        deploy_install_script
        exec_remote "~/altai-deploy-scripts/install-nodes.sh compute"
        retcode=$?
        clean
        ;;
    master)
        log "Running install master script machine $NODE_NAME"
        deploy_install_script
        exec_remote "~/altai-deploy-scripts/install-nodes.sh master"
        retcode=$?
        clean
        ;;
    master-compute)
        log "Running install master+compute script machine $NODE_NAME"
        deploy_install_script
        exec_remote "~/altai-deploy-scripts/install-nodes.sh full $OS_MODE"
        retcode=$?
        clean
        ;;
    upload-image)
        exec_remote "~/altai-deploy-scripts/install-nodes.sh upload-image"
        ;;
    *)
        log "Wrong parameter"
        exit 1
        ;;
esac
log "Exiting with code: $retcode"
exit $retcode
