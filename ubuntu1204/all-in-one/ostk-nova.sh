#!/bin/bash

# Copyright (C) 2012-2013 Ori Tzoran <ori.tzoran@tikalk.com>
# This file is part of Topstein, Tikal's OpenStack Installer. 
# Legal disclaimer is in 'install-ostk.sh'

# Installs nova
# handles CC, CN type
# see configure_compute::doc for assumptions on entrance

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

if [ -r nova.conf.template ]; then
	:
else
	printf "$prog [Error]: missing file nova.conf.template\n"
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

echo
printf "==============================================================================\n"
printf "Installing Openstack nova on host $HOSTNAME node type $NODE_TYPE              \n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo

     NOVA_CONF=/etc/nova/nova.conf
NOVA_API_PASTE=/etc/nova/api-paste.ini
    CN_TARBALL=nova-compute-installer.tgz

function check_set_ip_forwarding
{
	printf "\nChecking whether ip_forward is enabled: "
	if grep '^net.ipv4.ip_forward=1' /etc/sysctl.conf > /dev/null; then 
		printf "yes\n"
	elif grep '^#net.ipv4.ip_forward=1' /etc/sysctl.conf > /dev/null; then
		printf "not yet\nUncommenting it in /etc/sysctl.conf . . . "
		sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
	fi

	## verify done before we continue
	if grep '^net.ipv4.ip_forward=1' /etc/sysctl.conf > /dev/null; then 
		sysctl -p		#doc-bug: missing activation
		printf "done\n"
		return 0
	fi

	## if we got here something unexpected, bail out
	printf "$prog [Error]: in check_set_ip_forwarding, failed to set net.ipv4.ip_forward=1\n"
	exit 1
} # check_set_ip_forwarding

function install_compute
{
		#OO: packages are as listed in Install&Deploy
		#OO: vbox wont run nova-compute-kvm (libvirtError.... 'hvm')

	case $LIBVIRT_TYPE in
		kvm) NOVA_COMPUTE_HYPER=nova-compute-kvm
			;;
		qemu) NOVA_COMPUTE_HYPER=nova-compute-qemu
			;;
		*) printf "Unsupported LIBVIRT_TYPE $LIBVIRT_TYPE"
			exit 1
			;;
	esac

	#OO: added pm-utils cause libvirt doesn't suggest it [see bug #994476]
	# TODO: check if fixed...
	printf "\n\nInstalling nova packages for compute\n"
	set -x
	apt-get install nova-compute $NOVA_COMPUTE_HYPER	
	set +x

	# pm-utils is used by libvirt, for some reason it's not in "suggested"
	printf "\nInstalling additional packages (fix dependencies)\n"
	set -x
	apt-get install  pm-utils
	set +x

	if [[ $NODE_TYPE == "compute" ]]; then
		printf "\nstopping nova services:\n"
		nova_services stop
		printf "\nFinished compute related nova installation. nova services were stopped till configured.\n"
	fi
	printf "hit Enter to cont: "; read ANS; echo
	return 0
} # install_compute

function install_controller
{
	printf "\n\nInstalling nova packages for controller\n"
	set -x
	apt-get install 			\
		nova-api			\
		nova-cert			\
		nova-consoleauth	\
		nova-conductor		\
		nova-doc			\
		nova-network		\
		nova-novncproxy		\
		nova-scheduler		\
		novnc				
	set +x

	printf "\nstopping nova services:\n"
	# Stop the nova- services prior to running db sync. 
	# Otherwise your logs show errors because the database has not yet been populated
	nova_services stop

	printf "\nFinished controller related nova installation. nova services were stopped till configured.\n"
	printf "hit Enter to cont: "; read ANS; echo
	return 0

} # install_controller


function configure_controller
{
	mysql_create_service_database "nova"

	printf "\nCopying template --> nova.conf:\n"
		mv -v $NOVA_CONF $NOVA_CONF.vanilla
		cp -v nova.conf.template $NOVA_CONF
		chown nova:nova $NOVA_CONF
		chmod 640 $NOVA_CONF

	# Paste file
	printf "\nConfiguring $NOVA_API_PASTE:\n"
		cp -vp $NOVA_API_PASTE $NOVA_API_PASTE.vanilla
        sed -i "s/127.0.0.1/$KEYSTONE_ENDPOINT/g"          $NOVA_API_PASTE
        sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" $NOVA_API_PASTE
        sed -i "s/%SERVICE_USER%/nova/g"                   $NOVA_API_PASTE
        sed -i "s/%SERVICE_PASSWORD%/$SERVICE_PASS/g"      $NOVA_API_PASTE

	printf "\nCreating nova tables in mysql...\n"
	set -x
	nova-manage db sync
	set +x
	printf "\nNo output means the command completed correctly (ignore DEBUG lines)\n"
	printf "If not, examine /var/log/nova/nova-manage.log\n"
	printf "hit Enter to cont: "; read ANS; echo

} # configure_controller


function verify_services
{

	printf "\nVerifying nova services are up:\n"
	printf " + nova-api isn't listed, that's ok (or at least isn't a surprise)\n"
	printf " + it may take up to a minute till the db is updated (after CN install)\n"
	set -x
	nova-manage service list 2>/dev/null
	set +x

	printf "\nVerifying images (previously installed by glance):\n"
	nova image-list
	printf "hit Enter to cont: "; read ANS; echo
	return 0
} 


function create_secgroup_default
{
	#see http://docs.openstack.org/trunk/openstack-compute/admin/content/enabling-ping-and-ssh-on-vms.html

	printf "\nEnabling Ping and SSH on VMs:\n"
	set -x
		nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
		nova secgroup-add-rule default tcp  22 22 0.0.0.0/0
	set +x
	return 0
}

function create_vmnetwork
{
	printf "\nCreating the Network for Compute VMs (Private, fixed_range)\n"
	#You must run the command that create the network that the virtual machines use. 
	#OO-bug: fixed_range_v4 undocumented
	#OO: to delete use this:
	# nova-manage network delete 192.168.100.0/24
	set -x
		nova-manage network create $VMNETWORK_NAME 	\
			--multi_host=False                  	\
			--fixed_range_v4=$FIXED_RANGE	    	\
			--bridge_interface=$BRIDGE_INTERFACE 
			# --num_networks=1 --network_size=16
	set +x
	printf "hit Enter to cont: "; read ANS; echo
	return 0
}

function create_floating_ips
{
	printf "\nCreating the Floating IPs\n"
	set -x
		nova-manage floating create --ip_range=$FLOATING_RANGE
	set +x

	printf "hit Enter to cont: "; read ANS; echo
	return 0

}

function add_keypair
{
	printf "\nAdding a keypair\n"
	printf "The Compute service can inject an SSH public key into an account on the instance\n"
	# will output fingerprint of public
	set -x
		nova keypair-add tikal_keypair | tee tikal.id_rsa
	set +x
	chmod 400 tikal.id_rsa

	#regenerate public key ==> file
	ssh-keygen -y -f tikal.id_rsa > tikal.id_rsa.pub
	printf "Verify fingerprints:\n"  
	set -x
	ssh-keygen -l -f tikal.id_rsa.pub
	nova keypair-list
	set +x

	printf "hit Enter to cont: "; read ANS; echo
	return 0
}


function create_cn_tarball
{
	printf "Copy CC config files here:\n"
		#cannot scp those from CN as root access is blocked and ostk cannot read /etc/nova
		cp -v /etc/nova/nova.conf       cc_nova.conf
		cp -v /etc/nova/api-paste.ini   cc_api-paste.ini
		cp -v /etc/network/interfaces   cc_interfaces
		grep $HOSTNAME /etc/hosts >     cc_hosts
	printf "Preparing tarball for compute-node[s] in $CN_TARBALL:\n"
		tar -czvf  $CN_TARBALL                                           \
			install-ostk.sh ostk-prereq.sh ostk-nova.sh nova_services.sh \
			openstack.conf nova.conf.template keystonerc tikal.id_rsa*      \
			cc_nova.conf cc_api-paste.ini cc_interfaces cc_hosts
		chown ostk $CN_TARBALL
		chmod 640  $CN_TARBALL
		mv -v $CN_TARBALL /home/ostk
	copy_cmd="scp ostk@$CC_HOST:$CN_TARBALL ."
	printf "\nFrom CN copy the tarball using this command:\n\t$copy_cmd\n"
	printf "hit Enter to cont: "; read ANS; echo
	return 0
} #create_cn_tarball


function configure_compute
{
	# Terminology
	#	CC = Cloud Controller
	#	CN = Compute Node
	#..................................................

	## Workflow
	# ostk installation is run on CC, during which 
	# a tarball is prepared for all CNs.
	# this tarball has all files necessary to 
	# install a CN
	#..................................................

	## CN installation
	# - ubuntu server with user ostk
	# - login as ostk, create ~ostk/OstkInstal
	# - scp the tarball from the CC to ~ostk/OstkInstal
	# - untar
	# - sudo -i && cd ~ostk/OstkInstal
	# - cc_interfaces -->> /etc/network/interfaces
	# - cc_hosts -->> add line to /etc/hosts
	# - run install-ostk.sh compute-node
	#..................................................


	fname=${FUNCNAME[0]}
	[[ $NODE_TYPE == compute ]] || return 0

	printf "Upon entering $fname I assume:\n"
	printf "+ /etc/network/interfaces edited/ready for CN (use cc_interfaces as template)\n"
	printf "+ /etc/hosts was updated to enlist the CC     (use cc_hosts for that)\n"
	printf "I will take care of cc_nova.conf and cc_api-paste.ini below\n" 
	printf "hit Enter to cont: "; read ANS; echo

	if [ -r cc_nova.conf ]; then
		mv -v $NOVA_CONF $NOVA_CONF.vanilla
		cp -v cc_nova.conf nova.conf.template
		printf "\nOpen another term. As root, Edit $PWD/nova.conf.template, modify it for Compute Node\n"
		printf "hit Enter when done: "; read ANS; echo
		printf "Are you sure? "; read ANS; echo
		cp -v nova.conf.template $NOVA_CONF
		chown -v nova:nova $NOVA_CONF
		chmod -v 640 $NOVA_CONF
	else
		printf "$prog[$fname] Error: File missing cc_nova.conf\n"
	fi

	if [ -r cc_api-paste.ini ]; then
		mv -v $NOVA_API_PASTE $NOVA_API_PASTE.vanilla
		cp -vp cc_api-paste.ini $NOVA_API_PASTE
	else
		printf "$prog[$fname] Error: File missing cc_api-paste.ini\n"
	fi

	printf "hit Enter to cont: "; read ANS; echo

	## add CC_HOST name to /etc/hosts

} #configure_compute

# Main

#OO: to allow vbox snap, move out: 
# X  create_vmnetwork 
# v/ create_instance
# v/ attach_floating_ip 

check_set_ip_forwarding
if [[ $NODE_TYPE == "all-in-one" || $NODE_TYPE == controller ]]; then
	install_controller		# nova_services are stopped here
	configure_controller
	nova_services start
	verify_services
	create_secgroup_default
	create_vmnetwork
	create_floating_ips
	add_keypair
	create_cn_tarball
fi
if [[ $NODE_TYPE == "all-in-one" || $NODE_TYPE == compute ]]; then
	install_compute
	configure_compute
	nova_services start		#on CN expect to start libvirt-bin nova-compute 
	verify_services
	printf "You may use the function \"delete_virbr0\" to wipe this interface\n"
fi

printf "\n\nAt this point you may create an instance from CLI:\n"
printf "   . keystonerc\n   . xfunctions.sh\n   create_instance MY_INSTANCE_NAME\n"
printf "and attach a floating IP to it:\nusing the function attach_floating_ip\n"
printf "use nova list to see instance status\n\n"

printf "==============================================================================\n"
printf "Nova installation and configuration is complete.                              \n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo

exit 0
