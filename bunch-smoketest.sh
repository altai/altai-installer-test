#!/bin/bash

ROBOT_USER=${ROBOT_USER:-"osc-robot"}
DEV_SERVER=${DEV_SERVER:-"172.18.40.10"}
SHAREDIR="/usr/local/share/openstack-core-test"

OS=$1
shift

if [ $# -ge 1  ]; then
	ENV=$1
else
	ENV="master"
fi

shift

REPO="openstack-"$OS

exec_remote() {
        ssh "$ROBOT_USER"@"$DEV_SERVER" "$@"
}

exec_in_dir() {
	exec_remote "cd $1 && " "$2"
}


not_supported() {
        echo "Platform $1 is not currently supported"
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


get_latest_tests() {
	#exec_in_dir "~/bunch" "git clone git.griddynamics.net:~skosyrev/repos/openstack-core-test"
	exec_remote "sudo yum remove -y openstack-core-test python-bunch python-lettuce-bunch"
	exec_remote "sudo yum clean all"
	exec_remote "sudo yum install -y openstack-core-test"
	#
	exec_in_dir "~/bunch" "rm -rf openstack-core-test"
        exec_remote "rsync -avz --delete-after $SHAREDIR/ ~/bunch/openstack-core-test"
	
}

tune_bunch_smoke_config() {
	exec_in_dir "~/bunch" "sed -i 's/build_environment:.*/build_environment: '$1'/' openstack-core-test/smoketests/basic/config.yaml"
	exec_in_dir "~/bunch" "sed -i 's/yum_repository:.*/yum_repository: '$2'/' openstack-core-test/smoketests/basic/config.yaml"
}

bunch_smoke() {
	exec_in_dir "~/bunch" "bash -x start.sh"
        if [ "$ENV" == "master" ]; then
                exec_in_dir "~/bunch" "bash -x start_all.sh"
        else
                exec_in_dir "~/bunch" "bash -x light_test.sh"
        fi
}

do_yum_cache_clean() {
	exec_remote "sudo yum clean all" 
}

do_rpm_update() {
	exec_remote "sudo yum -y update || sudo yum -y update --skip-broken"
}

collect_results() {
	echo "Grab XML report"
	rm -rf $WORKSPACE/results
	mkdir -p $WORKSPACE/results
	rsync -avz --delete-after  --include='*/' --include='*.log' --include='*.xml'  --exclude='*'  -e ssh  "$ROBOT_USER"@"$DEV_SERVER":'~/bunch/results/*'  $WORKSPACE/results/
	for f in `ls -1 $WORKSPACE/results/*/*.log`; 
	do 
		echo "[[ATTACHMENT|$f]]"
		cat $f; 
	done
        echo "Grab HTML report"
        rsync -avz -e ssh "$ROBOT_USER"@"$DEV_SERVER":'~/bunch/bunch-reports'  '/var/www'
}

fake_empty_results() {
	rm -rf $WORKSPACE/results/*
	#echo '<?xml version="1.0" ?>' > $WORKSPACE/results/dummy.xml
	rm -f $WORKSPACE/results/dummy.xml
	echo '<?xml version="1.0" ?>' > $WORKSPACE/results/dummy.xml
	echo '<testsuite failed="0" tests="1"><testcase classname="Dummy" name="Tes" time="0.0"/></testsuite>' >> $WORKSPACE/results/dummy.xml
}

fix_stale_services() {
	exec_remote "sudo service messagebus restart"
	exec_remote "sudo service avahi-daemon restart"
}

retcode=0

case "$OS" in
        rhel)
	setup_env_repo
	get_latest_tests
	tune_bunch_smoke_config $ENV $REPO
	fix_stale_services
	bunch_smoke $ENV
        retcode=$?
	collect_results
	;;
        *) 
	not_supported $OS
	fake_empty_results

        ;;
esac

exit $retcode
