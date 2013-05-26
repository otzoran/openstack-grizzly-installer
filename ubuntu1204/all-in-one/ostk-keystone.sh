#!/bin/bash

# Copyright (C) 2012-2013 Ori Tzoran <ori.tzoran@tikalk.com>
# This file is part of Topstein, Tikal's OpenStack Installer. 
# Legal disclaimer is in 'install-ostk.sh'

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
printf "Installing Keystone, setup tenants, users, roles, services and endpoints      \n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo


#echo "!!!!!!!!!!!!!!!!!!!!!!!!!! Attention !!!!!!!!!!!!!!!!!!!!"
#
# Note: from http://docs.openstack.org/folsom/openstack-compute/install/apt/content/install-glance.html
# from 2012-10-10, last verified 2012-12-03
#echo "[from Chapter 6. Installing OpenStack Compute and Image Service]"
#echo "When using the Ubuntu Cloud Archive, you need to "
#echo "re-install the python-keystoneclient "
#echo "after installing the glance packages listed above, otherwise you see an error."
#
# this warn is in grizzly Install&Deploy... not sure it's still valid


function keystone_install
{

	#OO: missing: in Doc apt-get keystone only - not python-keystone python-keystoneclient
	#OO: in grizzly's Basic-Install it's ok
	printf "\n\n"
	set -x
	apt-get install keystone python-keystone python-keystoneclient
	set +x

	# Config backend = Database
	printf "\n\nConfiguring keystone to use mysql\n"

	# edit keystone.conf
	# replace the sqlite connection by mysql [1]
	# uncomment the service token 
	KEYSTONE_CONF=/etc/keystone/keystone.conf
	sed -i	\
		-e "s,^connection[ \t]*=.*,connection = mysql://keystone:$MYSQL_USER_PASS@$MYSQL_SERVER/keystone,g" \
		-e "1,5s/^# admin_token =.*/admin_token = $SERVICE_TOKEN/"		\
		 $KEYSTONE_CONF

	## replace the sqlite connection by mysql [2]
	rm -v /var/lib/keystone/keystone.db

	#OO: Note on permissions: 
	# keystone.conf is shipped as root:root 644 (in the ubuntu pack)
	# but /etc/keystone is keystone:keystone 700 so the files under it are protected from
	# unauthorized users

}

function create_keystone_db
{
	printf "\nCreating keystone database and user:\n"
	mysql_create_service_database "keystone"

	# New in grizzly: 
	# By default Keystone will use ssl encryption between it and all of the other services. 
	printf "Create the encryption certificates:\n"
	keystone-manage pki_setup
	chown -R keystone:keystone /etc/keystone/*

	service keystone restart

	# Create the empty tables in keystone DB; 
	keystone-manage db_sync

	printf "keystone DB tables were just created, now empty.\nYou may test that running:\n"
	printf "     mysql -ukeystone -p$MYSQL_USER_PASS -e \"use keystone; show tables;\"\n"
	printf "hit Enter after you finished that: "; read ANS; echo
}




function setup_tenants_users_roles
{

	#OO: the "--enabled true" isn't in the grizz doc...
	printf "First, create a default tenant:\n"
	keystone tenant-create --name $DEFAULT_TENANT --description "Default Tenant" 
	DEFAULT_TENANT_ID=$(keystone tenant-list | grep "\ $DEFAULT_TENANT\ " | awk '{print $2}')

	# the Doc names the default user = admin; confusion with role "admin" (which is hardcoded in
	# the json files!)
	#ADMIN_USER=u_Admin # defined in openstack.conf
	printf "Create a default user named $ADMIN_USER:\n"
	set -x
	keystone user-create --name $ADMIN_USER --tenant_id $DEFAULT_TENANT_ID	\
		--pass $ADMIN_USER_PASSWORD --email root@localhost 
	set +x
	ADMIN_USER_ID=$(keystone user-list | grep "\ $ADMIN_USER\ " | awk '{print $2}')

	printf "Create an administrative role based on keystone's default policy.json file, admin:\n"
	keystone role-create --name admin
	ADMIN_ROLE_ID=$(keystone role-list       | grep "\ admin\ " | awk '{print $2}')

	printf "Grant the admin role to the admin user in the $DEFAULT_TENANT tenant:\n"
	set -x
	keystone user-role-add --user_id $ADMIN_USER_ID --role_id $ADMIN_ROLE_ID --tenant_id $DEFAULT_TENANT_ID
	set +x

	# Service Tenant
	printf "\nCreate a Service Tenant to contain all the services listed in the service catalog:\n"
	set -x
	keystone tenant-create --name "service" --description "Service Tenant" 
	set +x
	SERVICE_TENANT_ID=$(keystone tenant-list | grep "\ service\ " | awk '{print $2}')

	printf "\nCreate a Service User in the Service Tenant for each OSTK component\n"
	printf "and grant him the 'admin' role:"
	# Add services to service tenant
	for srv in $SERVICES
	do
		set -x
	    keystone user-create --name $srv --pass $SERVICE_PASS 	\
			--tenant_id $SERVICE_TENANT_ID --email $srv@localhost 
		set +x
	    SERVICE_ID=$(keystone user-list | grep "\ $srv\ " | awk '{print $2}')
	    # Grant admin role to the $srv user in the service tenant
		set -x
	    keystone user-role-add --user_id $SERVICE_ID --role_id ${ADMIN_ROLE_ID} --tenant_id $SERVICE_TENANT_ID
		set +x
	done
}

function assert_keystone_catalog_sql
{
	printf "\nVerify that keystone.conf is configured to use mysql:\n"
	tmpf=/tmp/keystone_catalog.$$
	sed '/^#.*/d' /etc/keystone/keystone.conf | fgrep -A5 '[catalog]' > $tmpf
	if grep -q '^driver[ \t]*=[ \t]*keystone.catalog.backends.sql.Catalog' $tmpf; then
		printf "... ok\n"
	else
		printf "Check that /etc/keystone/keystone.conf has those lines:\n "; 
		printf "  [catalog]\n"
		printf "  driver = keystone.catalog.backends.sql.Catalog\n"
		printf "hit Enter to cont: "; read ANS; echo
	fi
}

function keystone_create_services
{
	# Create required services
	printf "\nCreating services:\n"
	keystone service-create --name keystone --type identity     --description 'Identity Service'
	keystone service-create --name nova     --type compute      --description 'Compute Service'
	keystone service-create --name glance   --type image        --description 'Image Service'
	keystone service-create --name cinder   --type volume       --description 'Volume Service'
	keystone service-create --name ec2      --type ec2          --description 'EC2 Compatibility'
}

function keystone_create_endpoints
{
	printf "\nCreating endpoints:\n"
	# Create endpoints on the services
	for srv in ${SERVICES^^}
	do
		ID=$(keystone service-list | grep -i "\ $srv\ " | awk '{print $2}')
		  PUBLIC=$(eval echo \$${srv}_PUBLIC_URL)
		   ADMIN=$(eval echo \$${srv}_ADMIN_URL)
		INTERNAL=$(eval echo \$${srv}_INTERNAL_URL)
		set -x
		keystone endpoint-create --region $OSTK_REGION --service_id $ID 	\
			--publicurl $PUBLIC --adminurl $ADMIN --internalurl $INTERNAL
		set +x
	done
}


function create_keystonerc
{
	# Create "keystonerc" resource file
	# In the Grizzly doc, there's a Doc mismatch between Install&Deploy vs. Basic-Install, regarding:
	# - port to use in OS_AUTH_URL (35357 in I&D, 5000 in B-I)
	#   This should be 35357, as "administrative commands MUST be performed against the admin API port: 35357"
	#   see http://docs.openstack.org/grizzly/openstack-compute/install/apt/content/verifying-identity-install.html
	#   BUT in verifying glance, OS_AUTH_URL is assigned port 5000 ...
	# - naming of SERVICE_ENDPOINT: with or w/o OS_
	# - naming of ERVICE_TOKEN: with or w/o OS_
	# - name of the RC file: I&D uses "keystonerc", B-I uses "openrc" ...
	# - when RC file is created (and used): I&D creates it AFTER, for verifications; B-I BEFORE creating services.

	RC_FILE=keystonerc
	if [[ -f $RC_FILE ]]
	then
		# Backup the existing file
		rm -f $RC_FILE.bak
		mv $RC_FILE{,.bak}
	fi

	cat << EOF  > $RC_FILE
	export OS_USERNAME=$ADMIN_USER
	export OS_PASSWORD=$ADMIN_USER_PASSWORD
	export OS_TENANT_NAME=$DEFAULT_TENANT
	export OS_AUTH_URL=http://$KEYSTONE_ENDPOINT:5000/v2.0/
	export OS_REGION_NAME=$OSTK_REGION
	#export OS_SERVICE_ENDPOINT=http://$KEYSTONE_ENDPOINT:35357/v2.0/
	#export OS_SERVICE_TOKEN=$SERVICE_TOKEN
EOF
	printf "\nCreated $RC_FILE in $PWD\n"

	printf "Verifying the Identity Service Installation:\n"
	unset OS_SERVICE_ENDPOINT OS_SERVICE_TOKEN
	source $RC_FILE
# this has too much output...
#	set -x
#	keystone token-get
#	set +x
	printf "Verifying admin account has authorization to perform administrative commands:\n"
	set -x
	keystone user-list
	set +x
	return 0
}

## Main

keystone_install
create_keystone_db

export OS_SERVICE_ENDPOINT=http://$KEYSTONE_ENDPOINT:35357/v2.0/
export OS_SERVICE_TOKEN=$SERVICE_TOKEN
setup_tenants_users_roles
assert_keystone_catalog_sql
SERVICES="keystone nova glance cinder ec2"
keystone_create_services
keystone_create_endpoints

create_keystonerc

printf "==============================================================================\n"
printf "Keystone installation and configuration is complete.\n"
printf "==============================================================================\n"
printf "Hit enter to continue: "; read ANS; echo

exit 0
