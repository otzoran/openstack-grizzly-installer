#!/bin/bash

# Copyright (C) 2012-2013 Ori Tzoran <ori.tzoran@tikalk.com>
# This file is part of Tikal's OpenStack Installer. See legal disclaimer install-ostk.sh

#TODO: see Install-Doc =Installing and configuring Cinder=
# http://docs.openstack.org/folsom/openstack-compute/install/apt/content/osfolubuntu-cinder.html

set -e

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

if [ -x ./nova_services.sh ]; then
	function nova_services { $PWD/nova_services.sh $1; }
else
	printf "$prog [Error]: missing script nova_services.sh\n"
	exit 1
fi

echo
printf "==============================================================================\n"
printf "Installing Openstack Cinder volume service\n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo


function cinder_install
{
	printf "\nVerifying nova-volume is NOT installed:\n"
	if dpkg -l nova-volume; then
		printf "nova-volume is installed. Run now in a 2nd term, as root:\n"
		printf "\t \"apt-get purge nova-volume\" \n"
		printf "hit Enter to cont: "; read ANS; echo
		#exit 1
	else
		# if not installed, dpkg returns !=0 (No packages found...) and this aborts us
		printf "ok\n"
	fi

	printf "\nInstalling cinder packages\n"
	set -x
	apt-get install cinder-api cinder-scheduler cinder-volume open-iscsi python-cinderclient tgt
	set +x
}

function cinder_auth
{
	##TODO: move from keystone here

	# Mysql: Create (verif) Database and user
	# mysql -u root -popenstack -e "show databases" | grep cinder
	#mysql -u root -popenstack 	\
	#	-e "SELECT user,host,password FROM mysql.user where user like 'cinder';"

	# Keystone: user
	# mysql -ukeystone -popenstack keystone -e "select extra from user where name='cinder';"

	# Keystone: endpoint, service 

	return 0
}


CINDER_CONF=/etc/cinder/cinder.conf
CINDER_API_PASTE=/etc/cinder/api-paste.ini
NOVA_CONF=/etc/nova/nova.conf

function config_etc 
{
	fname=${FUNCNAME[0]}

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
		printf "$prog[$fname] Error: edit $NOVA_CONF set volume_api_class = nova.volume.cinder.API\n"
		return 1
	fi

	#printf "\nIn 2nd term edit /etc/nova/nova.conf - replace VOLUMES section by this:\n"
	#cat << EOF
	## Cinder
	#volume_api_class=nova.volume.cinder.API
	#enabled_apis=ec2,osapi_compute,metadata
	#EOF

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

function config_tgt
{
	## NOTE: 
	# after install on opens9: 
	# file /etc/tgt/conf.d/cinder_tgt.conf is in package cinder-volume, so the instructions below are irrelevant

		# $state_path=/var/lib/cinder/ and 
		# $volumes_dir = $state_path/volumes by default and path MUST exist!.
		#printf "\nconfig_tgt\n"
		#printf "get $state_path and $volumes_dir from /etc/cinder/cinder.conf \n"
		#printf "This line will go into /etc/tgt/conf.d/cinder.conf\n"
		#printf "\tinclude \$volumes_dir/*\n"
		#printf "This should be:\n"
		#printf "\tinclude /var/lib/cinder/volumes/*\n"

	TGT_CINDER_CONF=/etc/tgt/conf.d/cinder_tgt.conf

	if [[ -r $TGT_CINDER_CONF ]]; then
		printf "Found $TGT_CINDER_CONF with this content:\n"
		set -x
		cat $TGT_CINDER_CONF
		set +x
	else
		printf "WARNING: missing file $TGT_CINDER_CONF\n"
		printf "This file should be in package cinder-volume.\nRead the script (%s) comments to fix.\n" $prog
	fi
	printf "Hit enter to continue: "; read ANS; echo
	set -x
	service tgt restart
	set +x
}

function cinder_restart 
{
	#stop cinder-api
	#start cinder-api
	service cinder-api restart
	#stop cinder-volume
	#start cinder-volume
	service cinder-volume restart
}

function cinder_create_volume
{
	#TODO: move to xfunctions
	printf "Create a 1 GB test volume\n"
	set -x
	cinder create --display_name test 1
	cinder list
	set +x
}

# Main
cinder_install
config_etc
config_vgs	
config_tgt

cinder-manage db sync

printf "hit Enter to restart nova services: "; read ANS; echo
nova_services restart
cinder_restart 

printf "==============================================================================\n"
printf "Cinder installation and configuration is complete.\n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo

exit 0
