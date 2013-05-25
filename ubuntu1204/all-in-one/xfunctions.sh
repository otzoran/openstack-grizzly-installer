###
### ostk utility functions
###
# vim:filetype=sh:ts=4:sw=4:ai:nows: 
###

# Copyright (C) 2012-2013 Ori Tzoran <ori.tzoran@tikalk.com>
# This file is part of Tikal's OpenStack Installer. See legal disclaimer install-ostk.sh

# Functions used by ostk-*.sh or for post-installation

function check_keystonerc
{
	local fname=${FUNCNAME[0]}

		##TODOD: tighter verif
	if [ -z "$OS_AUTH_URL" ]; then
		printf "OS_AUTH_URL not defined, source keystonerc...\n"
		return 1
	else
		return 0
	fi
}

function create_instance
{
		# create instance flavor m1.tiny from cirros image 
		#OO: select keypair on the fly
	local fname=${FUNCNAME[0]}

	check_keystonerc || return 1

	if [[ $# == 1 ]]; then
		vm_name=$1
		printf "[$fname] will create vm name = $vm_name\n"
		printf "Enter to confirm: "; read ANS; echo
	elif [[ $# == 0 ]]; then
		printf "[$fname] missing arg, expecting vm_name\n"
		return 1
	else
		printf "[$fname] too many args, expecting only one = vm_name\n"
		return 1
	fi

	printf "Creating an instance from the cirros image:\n"
	printf "We use the nova *-list commands to construct the boot command:\n"
	printf "\tnova flavor-list\n\tnova image-list\n\tnova keypair-list\n"

	printf "Selecting a cirros image:\n"
	image_id=$(nova image-list | awk '$4 ~ /cirros/ {print $2}')

	printf "Selecting the m1.tiny flavor:\n"
	flavor_id=$(nova flavor-list | awk '$4 ~ /m1.tiny/ {print $2}')
	boot_cmd="nova boot --flavor $flavor_id --image $image_id --key_name tikal_keypair --security_group default $vm_name --poll"
	printf "constructed this command:\n\t$boot_cmd\n"
	printf "run it [y]: "; read ANS; [ -z "$ANS" ] && ANS="y"
	if [ $ANS = "y" ]; then
		set -x
		$boot_cmd
		set +x
	fi
	printf "\nIf it fails, start troubleshoot in /var/log/nova/nova-compute.log\n"

	printf "\n == Useful commands == \n"
	printf "\tnova list                    list instances\n"
	printf "\tnova console-log $vm_name    view instance console\n"
	printf "Reminders:\n"
	printf "+ source keystonerc if you want to use nova commands in another term\n"
	printf "+ You can ping your instance's private IP from the CC only!\n"
	printf "+ You can ssh your instance with the keypair e.g. \n"
	printf "\tssh -i tikal.id_rsa cirros@192.168.100.2\n"
	printf "or using the password (printed in the console-log)\n"

	printf "\n\nFinally, to bring down/delete an instance use:\n"
	printf "\tnova delete <name> | <id>\n"
}

function attach_floating_ip 
{
	#OO: ref code see http://devstack.org/exercises/floating_ips.sh.html
	local fname=${FUNCNAME[0]}

	printf "::TODO:: rewrite $fname \n\n" 
	return 0
	nova floating-ip-create
	nova floating-ip-list
	#nova add-floating-ip <instance-name> <new-ip>

	printf "\n\nSo far, we can ssh to the instance only from the compute node hosting it.\n"
	printf "If we try it from the laptop it'll fail.\n\tssh cirros@192.168.100.2\n"
	printf "Lets attach a floating IP to the instance:\n"
	set -x
	nova add-floating-ip $vm_name  172.16.172.1
	set +x
	printf "\nNow try this from a term on your laptop: ssh cirros@172.16.172.1\n"
	printf "hit Enter to cont: "; read ANS; echo

	printf "\n\nnova installation and setup is done.\n"
}


function copy_etc_files_to_here
{

	local fname=${FUNCNAME[0]}

	etc_files="nova.conf cinder.conf interfaces"
	log_files="dpkg.log apt_history.log"
	mkdir -p Logs
	if [[ $HOSTNAME && $USER ]]; then
		for ff in $etc_files $log_files
		do
			case $ff in 
				nova.conf) 	
							sudo cp -vp /etc/nova/nova.conf nova.conf-$HOSTNAME
							sudo chown $USER:$USER nova.conf-$HOSTNAME
							;;
				cinder.conf) 
							sudo cp -vp /etc/cinder/cinder.conf cinder.conf-$HOSTNAME
							sudo chown $USER:$USER cinder.conf-$HOSTNAME
							;;
				interfaces) 
							sudo cp -vp /etc/network/interfaces interfaces-$HOSTNAME
							sudo chown $USER:$USER interfaces-$HOSTNAME
							;;
				dpkg.log)
							cp -vp /var/log/dpkg.log* Logs
							;;
				apt_history.log)
							cp -vp /var/log/apt/history.log* Logs
							;;
			esac
		done

		ll nova.conf-$HOSTNAME interfaces-$HOSTNAME cinder.conf-$HOSTNAME	\
			Logs/{dpkg,history}.*
		echo
	else
		printf "cannot run function $fname: either HOSTNAME or USER not defined\n"
		return 1
	fi
	return 0
}

function mysql_create_service_database
{
	# Create Database (or recreate, since it starts by droping it)
	# OO: each User is created twice: once for local and once for %
	# This follows Install&Deploy Doc (and other ostk manuals), but i dont like it:
	# see function to treat the errors 1044 and 1045 this may induce

	ostk_user=$1 

	set -x
	mysql -uroot -p$MYSQL_ROOT_PASS 	\
		-e "DROP DATABASE IF EXISTS $ostk_user;"
	mysql -uroot -p$MYSQL_ROOT_PASS 	\
		-e "CREATE DATABASE $ostk_user;"
	mysql -uroot -p$MYSQL_ROOT_PASS 	\
		-e "GRANT ALL ON $ostk_user.* TO $ostk_user@'%' IDENTIFIED BY \"$MYSQL_USER_PASS\";"
	mysql -uroot -p$MYSQL_ROOT_PASS 	\
		-e "GRANT ALL ON $ostk_user.* TO $ostk_user@\"localhost\" IDENTIFIED BY \"$MYSQL_USER_PASS\";"
	set +x
	echo
	return 0

}
