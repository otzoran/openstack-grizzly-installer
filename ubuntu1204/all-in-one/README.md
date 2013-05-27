Topstein All-in-One
===================
Simplify installation of **_OpenStack Grizzly_** inside a Virtualbox VM following 
the _official OpenStack Install_ guide.   
Fixes to doc errata are included in the code herein.

    Copyright (C) 2012-2013 Ori Tzoran <ori.tzoran@tikalk.com>
    This file is part of Topstein, Tikal's OpenStack Extensible Installer. 

Branches
========
- **master** current OSTK grizzly

Ingredients
===========
- Host PC, laptop or desktop, Minimal:
	* BIOS: VT enabled
	* CPU : x64 recommended
	* RAM : 4GB at least 
	* disk: 20GB free 
	* net : one nic, connected to the internet (wifi will do too)
	* OS  : any of **Linux**, **Windows** or **MacOS** are supported (and tested)
- Virtualbox 4.1 (4.2 may work, not tested)
- Ubuntu Server 12.04 LTS amd64 ISO
- This.git.repo

Bootstrap
=========
See my blog at tikalk.com for detailed instructions and explanations
## Highlights:
* configure 2 virtualbox Host-only Networks:
	* `vboxnet0` IPv4 172.16.0.254     mask 255.255.0.0   noDHCP
	* `vboxnet1` IPv4 192.168.100.254  mask 255.255.255.0 noDHCP
* create a virtualbox VM
	* from scratch: 10GB disk, 1G RAM, 1vCPU (those are the min values)
	* or import OVA appliance (not covered here)
* configure the VM before booting
	* Settings->Network: make sure it has 3 network interfaces: NAT, vboxnet0, vboxnet1 
* install Ubuntu server in the VM
	* with partitions and LVM configured to enable Cinder (cinder-volumes)

Login
=====
from the host PC, ssh to the VM. Using the preconfigured OVA this looks like this:   

    ssh ostk@172.16.0.5 	# _password is 1122_

from now on, all actions are performed **inside the VM**

Become root
===========
    sudo -i
    apt-get install git

Get the scripts
===============
In a 2nd terminal, as user **ostk**:

    git clone https://github.com/otzoran/openstack-grizzly-installer.git topstein
    cd topstein/ubuntu1204/all-in-one
    git checkout master 

Configure & Install
===================
There're no surprises, the script tells you what's about to happen and asks confirmation.
As root, go to where the scripts are, r.g:

    cd ~/ostk/topstein/ubuntu1204/all-in-one
    ./install-ostk.sh -h

And may the Force be with you...

#References
## official OpenStack Doc 
Install - [OpenStack Install and Deploy Manual - Ubuntu] (http://docs.openstack.org/grizzly/openstack-compute/install/apt/content/index.html) 
Grizzly, 2013.1 (Object Storage 1.8.0)
revision 2013-04-30

Admin - [OpenStack Compute Administration Manual] (http://docs.openstack.org/grizzly/openstack-compute/admin/content/index.html) 
"Grizzly, 2013.1"




