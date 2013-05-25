#!/bin/bash

## usage: nova_services.sh stop | start | status (etc, args to service(8))

## coding: in a function, for reuse

function nova_services 
{
	[ $# -lt 1 ] && { echo "missing arg: stop|start"; return 1; }
		# due to bug Ubuntu “nova” package Bugs Bug #1043864
		# libvirt-bin need be started before nova-compute


	action=$1		# expect: stop || start
	for nova_srv in 	\
		libvirt-bin		\
		nova-api		\
		nova-cert		\
		nova-compute	\
		nova-consoleauth 	\
		nova-network	\
		nova-novncproxy	\
		nova-objectstore 	\
		nova-scheduler	\
		nova-volume		\
		cinder-api		\
		cinder-volume	\
		cinder-scheduler	\
		tgt				\
		rabbitmq-server
	do
		if [ -e /etc/init.d/$nova_srv ]; then
			service $nova_srv $action
		fi
	done

	#TODO: 
	# services that may belong here:
	# + iscsi-network-interface
	# processes that stay around, suspected to be remainders of slopy stopped service:
	# - iscsi
	# - epmd (belongs to rabbitmq)
	# - dnsmasq (belongs to libvirt-dnsmasq) 

	return 0	# important - if not, may cause exit in caller (that sets errexit)
}

nova_services $1
