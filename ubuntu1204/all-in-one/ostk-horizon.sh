#!/bin/bash

# Copyright (C) 2012-2013 Ori Tzoran <ori.tzoran@tikalk.com>
# This file is part of Topstein, Tikal's OpenStack Installer. 
# Legal disclaimer is in 'install-ostk.sh'

##TODO:
# How do I adjust the dimensions of the VNC window image in horizon?
# src http://docs.openstack.org/trunk/openstack-compute/admin/content/faq-about-vnc.html
# you must edit the template file _detail_vnc.html 
# on 12.04 find it under 
# /usr/share/pyshared/horizon/dashboards/nova/templates/nova/instances_and_volumes/instances/_detail_vnc.html
# Modify the width and height parameters
#  <iframe src="{{ vnc_url }}" width="720" height="430"></iframe>
# DOC bug: file is here:
# /usr/share/pyshared/horizon/dashboards/nova/instances/templates/instances/_detail_vnc.html

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

echo
printf "==============================================================================\n"
printf "Installing Openstack Horizon service                                          \n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo


HORIZON_CONF=/etc/openstack-dashboard/local_settings.py
VANILLA=${HORIZON_CONF}.vanilla

function horizon_install
{
	# list from I&D
	printf "\nInstalling OpenStack Horizon\n"
	set -x
	apt-get install openstack-dashboard memcached libapache2-mod-wsgi
	set +x
	printf "\nRemove the ubuntu theme:\n"
	apt-get remove --purge openstack-dashboard-ubuntu-theme
	printf "hit Enter to cont: "; read ANS; echo
}

function horizon_configure
{
	cp -pv $HORIZON_CONF $VANILLA

	#OO: i dont use QUANTUM (see Installing and configuring Dashboard" in Appx B,
	# http://docs.openstack.org/trunk/openstack-compute/install/apt/content/osfolubuntu-dashboardservice.html

	printf "\nConfiguring OpenStack Horizon\n"
		# OPENSTACK_HOST is used in HORIZON_CONF this way:
		# 	OPENSTACK_KEYSTONE_URL = "http://%s:5000/v2.0" % OPENSTACK_HOST
		# So value for it need be derived as follows:
	sed -e "s/^OPENSTACK_HOST.*/OPENSTACK_HOST = \"$KEYSTONE_ENDPOINT\"/g" 	\
		-e '
/^TEMPLATE_DEBUG/ a\
QUANTUM_ENABLED = False
'		$VANILLA > $HORIZON_CONF

	# The I&D doc says to verify that "CACHE_BACKEND in /etc/openstack-dashboard/local_settings.py 
	# match the ones set in /etc/memcached.conf"
	# TODO: 2013-05-26 not found there
	#printf "\nChecking CACHE_BACKEND value:\n"
	#grep CACHE_BACKEND /etc/openstack-dashboard/local_settings.py

	# COMPRESS_OFFLINE = True
	# seems related to The Ubuntu package; may need to comment that

	# TIME_ZONE
	# default is TIME_ZONE = "UTC"

}

function horizon_restart
{
	service apache2 restart
	service memcached restart
}

# Main
horizon_install
horizon_configure
horizon_restart

cat << EOMMM
  
  You've just finished installing OpenStack Horizon. To use it, 
  point Firefox at http://$CC_HOST/horizon 
  + Note1: the above URL is the right one (the mistake is in the doc) 
  + Note2: Chrome has a known issue with VNC console (at least as of 2012-11-09)

  Login
    User Name: $ADMIN_USER
    Passowrd : $ADMIN_USER_PASSWORD

  Create an Instance: 
    Project
      Images & Snapshots
      Images
        check Image cirros-0.3.0-x86_64, click Launch
        fill in: Details - Instance Name
                 Accesss & Security - Keypair, check Security Groups
       don't fill "Volume Options" and "Post-Creation"

EOMMM

printf "==============================================================================\n"
printf "Horizon installation and configuration is complete.\n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo

exit 0
