#!/bin/bash

# Copyright (C) 2012-2013 Ori Tzoran <ori.tzoran@tikalk.com>
# This file is part of Topstein, Tikal's OpenStack Installer. 
# Legal disclaimer is in 'install-ostk.sh'

# This script is executed on all ostk nodes (controller, compute etc)
# It verifies some settings and installs prerequisite packages

# Exec/Programming:
# verifications or installations that may require reboot are located here.
# This allows a simple restart (comment out this script from the caller)
#
# TODO 
# v/ cpu_check
# v/ NTP sed replace manual edit
# v: verify_networking 
# :: NTP server ... prefer :: elaborate

set -o errexit -o errtrace

prog=$(basename $0)
configfile=openstack.conf

# check run as root
uid=$(id -u) 
if [ $uid -ne 0 -a "$USER" != "ori" ]; then
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

NODE_TYPE=$1
if [[ -z $NODE_TYPE ]]; then
	printf "$prog [Error]: missing NODE_TYPE {ARGV[1]}\n"
	exit 1 
fi
case $NODE_TYPE in
	"all-in-one"|controller|compute)
		;;
	*)
		printf "$prog Error: $NODE_TYPE not supported\n"
		exit 1
		;;
esac

cat << EndOfIntro

Install Openstack $OSTK_RELEASE prerequisites 
Checklist
 1. $configfile customized 
 2. /etc/network/interfaces edited 
 3. nova.conf.template is in sync with those two

If /etc/network/interfaces has changed since the last boot:
   /etc/init.d/networking restart
to apply the changes

EndOfIntro

printf "Hit return to continue: "; read ANS; echo


function verify_networking
{
	#
	# check exist (ip link) for PUBLIC_INTERFACE, PRIVATE_INTERFACE and BRIDGE_INTERFACE
	#
	printf "Checking network interaces against declarations in $configfile\n"
	for param in PUBLIC_INTERFACE PRIVATE_INTERFACE BRIDGE_INTERFACE; do
		iface=$(eval echo '$'${param})
		if ! ip link show $iface > /dev/null 2>&1 ; then
			printf "$prog Error: $param $iface doesn't exist.\n"
			printf "  fix that in $configfile or define it in /etc/network/interfaces\n\n"
			printf "  and start over\n\n"
			exit 1
		fi
	done

	# TODO
	# check iface up
	# check IP ranges
	return 0

}

function set_hostname_properly
{
	printf "Checking /etc/hosts for proper hostname declaration\n"
	hname=$(uname -n)
	if grep -q "127.0.1.1[ \t]*${hname}" /etc/hosts; then
		sed -i 	\
			-e "s/127.0.1.1\([ \t]*${hname}\)/$MYSQL_SERVER\1/" /etc/hosts
		printf "... IP $MYSQL_SERVER now set in /etc/hosts ... recheck \n"
	fi
	if grep    "${hname}[ \t]*${hname}" /etc/hosts; then
		printf "... ok\n"
		return 0
	fi

		# if we're here then the substit failed, do it manually:
	printf "\nOpen a 2nd term, as root, edit /etc/hosts, replace the line:\n"
	printf "127.0.1.1	$hname\n\tby this:\n"
	printf "$MYSQL_SERVER	$hname\n\n"
	printf "hit Enter after you finished that: "; read ANS; echo
	return 0
}

function preseed_grub_pc
{
	##
	## This unholy function is intended to skip confusing questions about the 
	## boot device amid 'apt-get upgrade' - if and when grub itself is updated
	## The unholy assumption is that a vbox will have /dev/sda as its only boot device - 
	## this may be wrong... especially if this is run on something else
	## The idea is Kevin Jackson's (thanx), i added some caution
	## TODO: 
	## improve check, verify that lv_root is on sda before exec this:

	BOOT_DISK="/dev/sda"

	if dmesg | grep "VBOX HARDDISK" > /dev/null; then
		echo "grub-pc grub-pc/install_devices multiselect $BOOT_DISK"               | debconf-set-selections
		echo "grub-pc grub-pc/install_devices_disks_changed multiselect $BOOT_DISK" | debconf-set-selections
	fi
}

function add_repo_cloud_archive
{
	##
	# Ubuntu provides 2 versions: precise-updates and the less stable precise-proposed
	# see http://www.ubuntu.com/download/help/cloud-archive-instructions
	# I use precise-updates

	REPO_VERSION=precise-updates/$OSTK_RELEASE

	printf "\nEnabling Ubuntu Cloud Archive: using $REPO_VERSION\n"
		echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu $REPO_VERSION main" \
			> /etc/apt/sources.list.d/OpenStack.list
	apt-get install ubuntu-cloud-keyring

	apt-get update 
	apt-get upgrade

		# Ubuntu specific
	if [ -f /var/run/reboot-required ]; then
		cat /var/run/reboot-required		# will say *** System restart required ***
		echo
		exit 1
	fi

	printf "\nCompleted apt-get upgrade. system is up2date\n\n"
	printf "Hit Enter to continue: "; read ANS; echo
}

	##
	## virtualization_checks 
	# Is called for all-in-one && compute
	# it's preformed here to avoid interrupting the installation midway if 
	# a BIOS change is required
	# - see http://docs.openstack.org/grizzly/openstack-compute/install/apt/content/kvm.html
	# - see man kvm-ok
	# also I internally check LIBVIRT_TYPE against host arch
	##
function virtualization_checks
{

	fname=${FUNCNAME[0]}
	[[ $NODE_TYPE == controller ]] && return 0

	cpu_model=$(sed -n 's/^model name[ \t]*: //p;' /proc/cpuinfo | head -1)
	cpu_count=$(grep -c '^model name' /proc/cpuinfo)
	CPUs=CPU; [ $cpu_count -gt 1 ] && CPUs=CPUs
	printf "Found $cpu_count $CPUs of type $cpu_model\n"


	set -x
	apt-get install -y cpu-checker
	set +x
	vt_enabled=0
	printf "\nChecking VT (Virtualization Technology) flags in CPU, BIOS and $configfile:\n"
	echo
	set +e
		kvm_says=$(kvm-ok)
		kvm_status=$?		# this works only in bash 4.x
	set -e
	echo $kvm_says
	if [[ $kvm_status == 0 ]]; then
		if [[ $LIBVIRT_TYPE == "kvm" ]]; then
			printf "Config file is ok and VT is enabled\nDecide what's next based on INFO above\n" 
		else
			printf "Warning: config mismatch\n"
			printf "Reason: In $configfile, you've set LIBVIRT_TYPE to $LIBVIRT_TYPE.\n"
			printf "This host can run kvm, yielding better performance. Change that and rerun\n"
		fi  
	else
			## 1) vbox: status==1, message:
			# INFO: Your CPU does not support KVM extensions
			# KVM acceleration can NOT be used
			## 2) Xeon: vt in cpu ok but disabled in bios. status==1, message:
			# INFO: /dev/kvm does not exist
			# HINT:   sudo modprobe kvm_intel
			# INFO: Your CPU supports KVM extensions
			# INFO: KVM (vmx) is disabled by your BIOS
			# HINT: Enter your BIOS setup and enable Virtualization Technology (VT),
			# 	  and then hard poweroff/poweron your system
			# 	  KVM acceleration can NOT be used

		if [[ $LIBVIRT_TYPE == "qemu" ]]; then
			printf "Config is ok\nReason: VT isn't enabled and LIBVIRT_TYPE set correctly to qemu\n"
		elif [[ $LIBVIRT_TYPE == "kvm" ]]; then
			printf "Config error\nReason: VT isn't enabled and LIBVIRT_TYPE=kvm\n"
			printf "1. If you believe this CPU supports VT, enable it in the BIOS first\n"
			printf "2. If not, Edit $configfile and set LIBVIRT_TYPE=qemu\n"
			printf "Aborting\n\n"
			exit 1
		else
			printf "Config error\nReason: unsupported LIBVIRT_TYPE=$LIBVIRT_TYPE\n"
			printf "Edit $configfile, set it to qemu or kvm\n"
			printf "Aborting\n\n"
			exit 1
		fi  
	fi

	printf "\nHit Enter to continue or ^C to abort: "; read ANS; echo

}


function install_prerequisites
{

		#
		# git was required for horizon [Folsom]
		# I use etckeeper for bookeeping, it requires a dvcs, i use git
	dep=git
	printf "\nInstalling convenience package: $dep\n"
	apt-get install $dep

	dep=etckeeper
	#TODO: skip if already installed cause the commit below exit 1 if already exists!
	printf "\nInstalling convenience package: $dep\n"
	apt-get install $dep

		# set etckeeper VCS to git - replace bzr
	sed -i '/^VCS=/s:^:#:; /^#VCS=["]*git/s:^#::'  /etc/etckeeper/etckeeper.conf
	pushd /etc > /dev/null
		etckeeper init; 
		git commit --quiet -a -m 'etckeeper initial commit'
	popd > /dev/null
	printf "\nhit Enter to cont: "; read ANS; echo

	dep=bridge-utils
	printf "\nInstalling prerequisites for OpenStack: $dep\n"
	apt-get install $dep
}

function ntp_install
{
	dep=ntp
	printf "\nInstalling prerequisites for OpenStack: $dep\n"
	apt-get install $dep

	#TODO: ntp improvements require further investigations
	# on node[s] OTHER THAN the controller, designate the CC as preferred NTP source:\n"
	# check again the restrict (may screw the CC); alternate use broadcast + broadcastclient
	# hints in /etc/ntp.conf
	# broadcast is suspected to cause a huge drift (at least on a vbox)
	#	printf "3. on the controller, allow sync from other nodes, e.g. for subnet 192.168.1.0/24: \n"
	#	printf "\trestrict 192.168.1.0 mask 255.255.255.0 nomodify notrap\n"

	echo
	NTP_CONF=/etc/ntp.conf
	VANILLA=/etc/ntp.conf.vanilla
	if [ -r $VANILLA ]; then
		printf "Found vanilla from a previous run, reconfiguring based on it\n"
		mv -v $NTP_CONF ${NTP_CONF}.old
		mv -v $VANILLA $NTP_CONF
	fi
	cp -vp $NTP_CONF $VANILLA
	stmp=$(date "+%F %H:%M")
	if [[ $NODE_TYPE == "compute" ]]; then
		cc_line="server $CC_HOST prefer"
	else
		cc_line=" "
	fi
	cat <<- NTP_SECTION >> $NTP_CONF

		#
		# $stmp Added by $prog for OpenStack
		#
		server $NTPSERVER_LOCAL prefer
		$cc_line
		interface listen $PUBLIC_INTERFACE  #Public
		interface listen $BRIDGE_INTERFACE  #VM
	NTP_SECTION

	NN=8
	echo "=== Last $NN lines from $NTP_CONF ==="
	tail -$NN $NTP_CONF
	echo "=== === ==="
	printf "Review lines added to $NTP_CONF. hit Enter when done: "; read ANS; echo

	printf "\nSynchronizing system clock:\n"
	set -x
	service ntp stop
	ntpdate $NTPSERVER_LOCAL
	service ntp start
	set +x
	printf "\nYou may check the clock in 10-30 minutes running\n\tntpq -p\n"

	return 0
}


function mysql_install
{
	##
	# merged here code from folsom, essex and the Install-Doc
	##
	printf "Pre-seed MySQL based on $configfile\n"

	cat <<MYSQL_PRESEED | debconf-set-selections
mysql-server-5.5 mysql-server/root_password password $MYSQL_ROOT_PASS
mysql-server-5.5 mysql-server/root_password_again password $MYSQL_ROOT_PASS
mysql-server-5.5 mysql-server/start_on_boot boolean true
mysql-server-5.5 mysql-server/root_password seen true
mysql-server-5.5 mysql-server/root_password_again seen true
MYSQL_PRESEED

	apt-get install  mysql-server python-mysqldb

	printf "\n\nConfigure mysql: set bind-address in my.cnf\n"
	MYSQL_CONF=/etc/mysql/my.cnf
	sed -i 	\
		-e 's/127.0.0.1/0.0.0.0/g' 	\
		-e "s/bind-address.*/bind-address     = $MYSQL_SERVER/" $MYSQL_CONF
	#TODO: now git cmmit in /etc with ostk message

	service mysql restart

	printf "\n\n"

}


function mysql_remedy_error_1045
{
	##
	##OO: This is a solution to MySQL errors 1044 and 1045 
	## which are due to permission race between ''@'localhost' and 'user'@'%'
	## and related to the hostname defined in /etc/hosts
	## i elaborated on that in 
	#  http://www.tikalk.com/alm/blog/solution-mysql-error-1045-access-denied-userlocalhost-breaks-openstack

	hname=$(uname -n)
	printf "\nFix for MySQL errors 1044 and 1045:\n"
	set -x
	mysql -uroot -p$MYSQL_ROOT_PASS -e 	\
		"DELETE FROM mysql.user WHERE Host='"$hname"'  AND User=''; 
		 DELETE FROM mysql.user WHERE Host='localhost' AND User=''; 
		 FLUSH PRIVILEGES;"
	set +x
	printf "hit Enter to cont: "; read ANS; echo

}

function rabbitmq_install
{
	printf "Install the messaging queue server:\n"
	apt-get install rabbitmq-server
}

# Main
verify_networking
set_hostname_properly		#needed for mysql setup
preseed_grub_pc
add_repo_cloud_archive
virtualization_checks		#for all-in-one & compute
install_prerequisites
ntp_install
if [[ $NODE_TYPE == controller || $NODE_TYPE == "all-in-one" ]] ; then
		# in folsom this was inside keystone, grizzly moved it here - what4?
	mysql_install
	mysql_remedy_error_1045
		# in folsom this was inside nova, grizzly moved it here ...
	rabbitmq_install
fi

printf "\nInstalling prerequisites for OpenStack finished\n"
exit 0

