ostkInstal 
==========
Simplify installation of **_OpenStack Folsom_** inside a Virtualbox VM following 
the _official OpenStack Install_ guide.   
Fixes to doc errata are included in the code herein.

    Copyright (C) 2012-2013 Ori Tzoran <ori.tzoran@tikalk.com>
    
    This file is part of Tikal's OpenStack Installer.
    
    Tikal's OpenStack Installer is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License version 3 as published by
    the Free Software Foundation.
    
    Tikal's OpenStack Installer is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    
    A copy of the GNU General Public License is in `COPYING`. If not, try 
    /usr/share/common-licenses/GPL-3. If not, see <http://www.gnu.org/licenses/>


Branches
========
- **master** is for an all-in-one VM
- **yokamina** is for a 2-node setup (VMs or bare-metal) of flatDHCP, single-host and nova-network

Ingredients
===========
- Host PC, laptop or desktop , with:
	* BIOS: VT enabled
	* CPU : x64 recommended
	* RAM : 4GB at least 
	* disk: 20GB free 
	* nic : one, connected to the internet (wifi will do too)
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
* install Ubuntu server 
	* with partitions and LVM configured to enable Cinder (was nova-volume)
* configure the VM before boot
	* Settings->Network: make sure it has 3 network interfaces: NAT, vboxnet0, vboxnet1 

Login
=====
from the host PC, ssh to the VM. Using the preconfigured OVA this looks like this:   

    ssh ori@172.16.0.5 	# _password is 1122_

from now on, all actions are performed inside the VM

Become root
===========
    sudo -i
    apt-get install git

Get the scripts
===============
In a 2nd terminal, as user ori:

    git clone git@bitbucket.org:otzoran/ostkinstal.git
    cd ostkinstal
    git checkout master # _or yokamina_
	sudo -i			    # _and switch to root for the rest_

Configure & Install
===================
Instructions on what need to be done are printed before the installation is started.
The scripts are interactive, use one tty to run the script and a 2nd for execution.

As root:

    cd ~/ostkinstal
    ./install-ostk.sh


#References
## official OpenStack Doc 
Install - [OpenStack Install and Deploy Manual - Ubuntu] (http://docs.openstack.org/folsom/openstack-compute/install/apt/content/index.html) revision 2012-11-09 Folsom, Compute 2012.2, Network 2012.2, Object Storage 1.4.8

Admin - [OpenStack Compute Administration Manual] (http://docs.openstack.org/folsom/openstack-compute/admin/content/index.html) "Folsom, 2012.2"




