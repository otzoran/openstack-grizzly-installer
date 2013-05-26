#!/bin/bash

# Copyright (C) 2012-2013 Ori Tzoran <ori.tzoran@tikalk.com>
# This file is part of Topstein, Tikal's OpenStack Installer. 
# Legal disclaimer is in 'install-ostk.sh'

# Assumptions:
# 1. Ubuntu ships /etc/glance/*conf with skeleton %SERVICE_TENANT_NAME% to be replaced here

#OO WARN: 
# if glance config is screwed up (for ex. mysql access failure due to pass, perms etc)
# expect /var/log/glance and ../upstart to choke 100% the root FS
# to disable the glance services while working on a remedy:
# for ff in /etc/init/glance-*.conf; do mv $ff ${ff//.conf/.disable}; done
# and stop the services

set -o errexit -o errtrace

prog=$(basename $0)
configfile=openstack.conf

# check run as root
uid=$(id -u) 
if [ $uid -ne 0 ]; then
	echo "$prog [Error]: user $USER doesnt have permissions, rerun as root"
	exit 1
fi

# Source in configuration file
if [ -f $configfile ]; then
	. $configfile
else
	echo "$prog [Error]: Configuration file \"$configfile\" not found"
	exit 1
fi

# Source in functions 
if [ -f xfunctions.sh ]; then
	.   xfunctions.sh
else
	echo "$prog [Error]: functions file\"xfunctions.sh\" not found"
	exit 1
fi

echo
printf "==============================================================================\n"
printf "Installing Openstack Glance image service                                     \n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo


      GLANCE_API_CONF=/etc/glance/glance-api.conf
     GLANCE_API_PASTE=/etc/glance/glance-api-paste.ini
 GLANCE_REGISTRY_CONF=/etc/glance/glance-registry.conf
GLANCE_REGISTRY_PASTE=/etc/glance/glance-registry-paste.ini

function glance_install
{
	# OO: The Instal&Deploy Doc has only "glance"; the list below isfrom Basic-Install 
	# Basic-Install says: apt-get install glance glance-api glance-common python-glanceclient glance-registry
	# which is almost identical to Folson (that had also python-glance, omitted in Grizzly?)

	# OO: The note about "re-install the python-keystoneclient" is probably obsolete
	set -x
	apt-get install glance 
	set +x

	rm -v /var/lib/glance/glance.sqlite

}

function glance_configure
{
	printf "\nConfiguring glance:\n"

	mysql_create_service_database "glance"

	# Glance API Paste
	sed -i	\
		-e "s/127.0.0.1/$KEYSTONE_ENDPOINT/g" 			\
		-e "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" 	\
		-e "s/%SERVICE_USER%/glance/g" 					\
		-e "s/%SERVICE_PASSWORD%/$SERVICE_PASS/g"  $GLANCE_API_PASTE

	# Glance Registry Paste
	sed -i	\
		-e "s/127.0.0.1/$KEYSTONE_ENDPOINT/g" 			\
		-e "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" 	\
		-e "s/%SERVICE_USER%/glance/g" 					\
		-e "s/%SERVICE_PASSWORD%/$SERVICE_PASS/g"  $GLANCE_REGISTRY_PASTE

	# Glance API Conf
	sed -i	\
		-e "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" 	\
		-e "s/%SERVICE_USER%/glance/g" 					\
		-e "s/%SERVICE_PASSWORD%/$SERVICE_PASS/g" 		\
		-e "s,^sql_connection.*,sql_connection = mysql://glance:$MYSQL_USER_PASS@$MYSQL_SERVER/glance,g" \
		-e "s,^#config_file.*,config_file = /etc/glance/glance-api-paste.ini,g" 	\
			 $GLANCE_API_CONF

	# Glance Registry Conf
	sed -i	\
		-e "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" 	\
		-e "s/%SERVICE_USER%/glance/g" 					\
		-e "s/%SERVICE_PASSWORD%/$SERVICE_PASS/g" 		\
		-e "s,^sql_connection.*,sql_connection = mysql://glance:$MYSQL_USER_PASS@$MYSQL_SERVER/glance,g" \
		-e "s,^#config_file.*,config_file = /etc/glance/glance-registry-paste.ini,g" 	\
			 $GLANCE_REGISTRY_CONF

	set -x
	glance-manage version_control 0

	glance-manage db_sync
	set +x
}

function glance_restart
{
	printf "\nRestarting the glance services: \n"
	set -x
	service glance-api restart
	service glance-registry restart
	set +x
}

function glance_upload_image
{
	## for ttylinux (preloaded on the appliance) see 
	# http://docs.openstack.org/folsom/openstack-compute/install/apt/content/images-verifying-install.html

	## cirros test
	printf "\nTest loading a small image to glance:\n"
	printf "hit Enter to cont: "; read ANS; echo
	CIRROS_PATH=/home/ostk/ostk-install
	if [ -r ./cirros.img ]; then
		printf "Found local cirros.img in $PWD \n"
		CIRROS_IMG=$PWD/cirros.img
	elif [ -r $CIRROS_PATH/cirros.img ]; then
		CIRROS_IMG=$CIRROS_PATH/cirros.img
		printf "Found local cirros.img in $CIRROS_PATH \n"
	else
		set -x
		wget -c https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-disk.img \
			-O cirros.img
		set +x
		CIRROS_IMG=$PWD/cirros.img
	fi

	#OO: keystonerc created by keystone script
	. keystonerc
	glance image-create --name="cirros-0.3.0-x86_64" 	\
		--public --disk-format=qcow2 --container-format=bare < $CIRROS_IMG

	printf "\nVerify the output from \"glance image-list\":\n"
	set -x
	glance image-list
	set +x

	printf "\nTroubleshoot using the logs in /var/log/glance\n"
	printf "hit Enter to cont: "; read ANS; echo
}

function fix_broken_keystoneclient
{
		# This is from Folsom; 
	cat << EOF
	! Attention !
	When using the Ubuntu Cloud Archive, you need to re-install python-keystoneclient 
	after installing the glance packages listed above, otherwise you see an error.
		see Chapter 6. "Installing OpenStack Compute and Image Service"
		this notice was valid for the 2012-11-09 version of the Doc, check at
		http://docs.openstack.org/folsom/openstack-compute/install/apt/content/install-glance.html
EOF
	printf "\nReinstall package python-keystoneclient? [y]: "; read ANS; [ -z "$ANS" ] && ANS=y; 
	case $ANS in
		y*|Y*) ANS=y
			;;
	esac
	if [ "$ANS" == "y" ]; then
		set -x
		apt-get install --reinstall python-keystoneclient
		set +x
	else
		printf "\nRead again the above warning, hit Enter to cont: "; read ANS; echo
	fi
}

# Main 
glance_install
glance_configure
glance_restart
glance_upload_image
#fix_broken_keystoneclient

printf "==============================================================================\n"
printf "Glance installation and configuration is complete.                            \n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo

exit 0
