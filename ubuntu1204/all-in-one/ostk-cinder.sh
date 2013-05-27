#!/bin/bash

# Copyright (C) 2012-2013 Ori Tzoran <ori.tzoran@tikalk.com>
# This file is part of Topstein, Tikal's OpenStack Installer. 
# Legal disclaimer is in 'install-ostk.sh'

#TODO: see Install-Doc =Installing and configuring Cinder=
# http://docs.openstack.org/folsom/openstack-compute/install/apt/content/osfolubuntu-cinder.html

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

if [ -r keystonerc ]; then
	source keystonerc
else
	printf "$prog [Error]: missing keystonerc (created by keystone script)\n"
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
printf "Installing Openstack Cinder volume service                                    \n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo


function cinder_install
{

	# I&D doc has same list as Folsom:
	#  cinder-api cinder-scheduler cinder-volume open-iscsi python-cinderclient tgt
	# Grizzly's list from B-I doc
	printf "\nInstalling cinder packages\n"
	set -x
	apt-get install cinder-api cinder-scheduler cinder-volume iscsitarget open-iscsi \
		iscsitarget-dkms python-cinderclient
	set +x
}


CINDER_CONF=/etc/cinder/cinder.conf
CINDER_API_PASTE=/etc/cinder/api-paste.ini
NOVA_CONF=/etc/nova/nova.conf

function cinder_config
{
	fname=${FUNCNAME[0]}

	printf "\nCreating database cinder:\n"
	mysql_create_service_database "cinder"

	printf "\nConfigure & start the iSCSI services:\n"
	set -x
	sed -i 's/false/true/g' /etc/default/iscsitarget
	service iscsitarget start
	service open-iscsi start
	set +x

	printf "\nConfiguring cinder. Original files are saved as .vanilla\n"
	VANILLA=${CINDER_API_PASTE}.vanilla
	cp -p $CINDER_API_PASTE $VANILLA
	sed -e "s/127.0.0.1/$KEYSTONE_ENDPOINT/g" 			\
		-e "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" 	\
		-e "s/%SERVICE_USER%/cinder/g" 					\
		-e "s/%SERVICE_PASSWORD%/$SERVICE_PASS/g" $VANILLA > $CINDER_API_PASTE

	# Database
	#OO: the sql_connection line is missing from the vanilla install !
	printf "Checking whether sql_connection is in $CINDER_CONF:\n" 
	if grep "^sql_connection" $CINDER_CONF ; then
		sed -i "s,^sql_connection.*,sql_connection = mysql://cinder:$MYSQL_USER_PASS@$MYSQL_SERVER/cinder,g" $CINDER_CONF
	else
		printf "adding it....\n" 
		cat >> $CINDER_CONF << EOFF
#Adding SQL connection line to fix missing 
sql_connection = mysql://cinder:$MYSQL_USER_PASS@$MYSQL_SERVER/cinder
EOFF
	fi

	printf "Checking whether rabbit_host is in $CINDER_CONF:\n" 
	if grep "^rabbit_host" $CINDER_CONF ; then
		sed -i "s,^rabbit_host.*,rabbit_host = $RABBIT_ENDPOINT,g" $CINDER_CONF
	else
		##OO: TODO: replace the public IP in RABBIT_ENDPOINT with an IP on Mgmt
		printf "adding it....\n" 
		cat <<- EOFF >> $CINDER_CONF 
			#Adding rabbit_host fix missing
			rabbit_host = $RABBIT_ENDPOINT
		EOFF
	fi

	chown cinder:cinder $CINDER_CONF
	chmod 0640 $CINDER_CONF				# it comes with 0644 from the package

	if [ ! -r $NOVA_CONF ]; then
		printf "$prog[$fname] Error: missing file $NOVA_CONF \n"
		return 1
	fi
	printf "\nVerifying $NOVA_CONF flag enabled_apis:\n"
	if grep 'enabled_apis=.*osapi_volume' $NOVA_CONF; then
		printf "$prog[$fname] Error: edit $NOVA_CONF and remove osapi_volume from enabled_apis\n"
		return 1
	else
		printf "ok\n"
	fi
	printf "\nVerifying $NOVA_CONF flag volume_api_class:\n"
	if grep 'volume_api_class[ =]*nova.volume.cinder.API' $NOVA_CONF; then
		printf "ok\n"
	else
		printf "$prog[$fname] Error: edit $NOVA_CONF to set volume_api_class = nova.volume.cinder.API\n"
		return 1
	fi

	printf "hit Enter to cont: "; read ANS; echo

}

function config_vgs 
{
	# Configure raw disk for use by Cinder if set
	ENABLE_VG_CREATE=0
	if [[ $ENABLE_VG_CREATE == 1 ]]; then
		BLOCK_DEV_CINDER=/dev/sda6			#need a better way to handle this
		partprobe
		pvcreate /dev/sda6 					# Physical volume "/dev/sda6" successfully created
		vgcreate cinder-volumes /dev/sda6 	# Volume group "cinder-volumes" successfully created
	fi

	# test also [ -d /dev/cinder-volumes ]
	printf "Verifying cinder volume group:\n"
	if vgdisplay cinder-volumes > /dev/null; then
		printf "VG cinder-volumes exists\n"
	else
		printf "WARNING: missing cinder-volumes\n"
	fi
	printf "Hit enter to continue: "; read ANS; echo
}

# Main
cinder_install
cinder_config
config_vgs	

cinder-manage db sync

printf "hit Enter to restart nova services: "; read ANS; echo
nova_services restart
cinder_services restart

printf "==============================================================================\n"
printf "Cinder installation and configuration is complete.                            \n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo

exit 0
