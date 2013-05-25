#!/bin/bash

# Copyright (C) 2012-2013 Ori Tzoran <ori.tzoran@tikalk.com>
# This file is part of Topstein, Tikal's OpenStack Installer. 

# Tikal's OpenStack Installer is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as published by
# the Free Software Foundation.

# Tikal's OpenStack Installer is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# A copy of the GNU General Public License should be in /usr/share/common-licenses/GPL-3. 
# If not, check http://www.gnu.org/licenses

set -o errexit -o errtrace

prog=$(basename $0)
configfile=openstack.conf

# check run as root
uid=$(id -u) 
if [ $uid -ne 0 -a "$USER" != "ori" ]; then
	echo "$prog [Error]: user $USER doesnt have permissions, rerun as root"
	exit 1
fi

# check configuration file
if [ -r $configfile ]; then
	source $configfile
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

function usage
{
	cat << EOF
  Topstein (Tikal's OpenStack Extensible Installer) will install OpenStack $OSTK_RELEASE on this host. 
  USAGE: 
         $prog [-t all-in-one | controller | compute] [-r] [-h]

  OPTIONS:
        -t      Type of installation is one of all-in-one, controller, compute; no default
        -r      Resume a previous run [not implemented yet]
        -h      Help

EOF
}

function parse_args
{
	fname=${FUNCNAME[0]}

	NODE_TYPE=""
	while getopts "hrt:" OPTION
	do
		case $OPTION in
			t) NODE_TYPE=$OPTARG
			   ;;
			r) printf "$prog[$fname]: option -r not implemented yet\n"
			   exit 1
			   ;; 
			h) usage 
			   exit 0 
			   ;; 
			?) usage
			   exit 1
			   ;; 
		esac
	done
	if [[ -z $NODE_TYPE ]]; then
		 printf "$prog[$fname] Error: missing installation type. Try -h. \n"
		 exit 1
	fi
	case $NODE_TYPE in
		all-in-one|all*)
						NODE_TYPE="all-in-one"
						;;
		controller|cont*)
						NODE_TYPE="controller"
						;;
		compute|comp*)
						NODE_TYPE="compute"
						;;
		*)
						printf "$prog[$fname] Error: $NODE_TYPE not supported\n"
						exit 1
						;;
	esac
	return 0

}

parse_args $@

./ostk-prerequisites.sh $NODE_TYPE
if [[ $NODE_TYPE == "compute" ]]; then
	./ostk-nova.sh	    $NODE_TYPE
else 
		# all-in-one or controller
	./ostk-keystone.sh
	./ostk-glance.sh
	./ostk-nova.sh	    $NODE_TYPE
	./ostk-cinder.sh
	./ostk-horizon.sh
fi

printf "\nFinished Openstack Installation \n\n"
exit 0
