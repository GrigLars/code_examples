#!/bin/bash

# VMWare fix 
# Back from 2012-2016, I worked for a company that had a problem: they had a VMWARE CentOS image that would boot, and then
#  needed not only to be standardized, but know how to "find itself," including set up its own NIC independently.  Nowadays,
#  I would fix this with ansible or puppet, but puppet was still not universal due to how our network was isolated, and 
#  ansible was still too new, too unproven when I started.

# Every so often, I would re-do the Linux image, which would have updated packages, the newest version of this 
#   script, and so on.

# I always had a version, so I knew how old the image or version of the program was.
VERSION="3.31" # grig@example-company.org 2016-02-01
# - Removed the "Check host via nslookup
# - Made a few minor cosmetic changes

# VERSION="3.22" # grig@example-company.org 2016-01-05
# - Shut down docker (if available) - docker sometimes messed with network modules reading

# VERSION="3.21" # grig@example-company.org 2015-08-22
# - Changed passwords for all machines
# - Added 192.168.122 subnet for my VMs for testing
# - Changed 10.1.3 from PRD_KEY back to INT_KEY (correcting mistake)

### [ VARIABLES ] #############################################################
#

MYDATE=$(date +%F' '%H':'%M' '%Z)
NOOHOST=
NOODOMAIN=
FIXEDIP=
FIXEDGATEWAY=
FIXEDNETMASK="255.255.255.0"
DEFAULT_DOMAIN="example-company.org"
DNS1="[DHCP]"
DNS2="[DHCP]"
DNS3="[DHCP]"
MYOLDMAC=$(ip a | grep "link/ether" | awk '{print $2}')
WHATSMYIP=$(ip a show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
MACHINETYPE="Development"
ISSUE_BANNER="issue.dev"	# default issue banner
NIC_MODULE=
DHCP_HOSTNAME=

# You would make these by running 
#   openssl passwd -1 "SomeAwe$$om3 p4$$w3rd"
# 
#   Obviously, these (and all other passwords and such) are fake for this example code
DEV_KEY='$1$HSOIp9Vw$c6SyLTgtseEg555-1212/.'
STG_KEY='$1$TwRES1NH$T//KNAukTv/555-1212.'
PRD_KEY='$1$M581o./d$89492IWeOhaSp555-1212/'
INT_KEY='$1$cEwuaKx1$3xkOSd.PyB3P5l555-1212'
# Default "duh" key, no not example-company.1234
DEF_KEY='$1$5DqGcgG4$2sWe6T11.BdJ4D555-1212/'
# My stupid throwaway key for testing purposes
PNK_KEY='$1$ZqE3AQGW$9yupamsK75CRbw555-1212.'


FLOGPATH="./VMware-netfix.changelog"
MakeFixedIPScriptPATH="./fixed_IP_transmogrifier.bash"
CONNECTED_NET_STATUS=0
#
######################################################### [ END VARIABLES] ####

### [ FUNCTIONS ] #############################################################
#

### Color schemes for messages to make things look purdy
	Alert () { echo -e "\e[41;33;1m$1\e[0m"; }
	Header () { echo -e "\e[42;37m$1\e[0m"; }
	Info () { echo -e "\e[30;1m$1\e[0m"; }
	Green () { echo -e "\e[32;1m$1\e[0m"; }
	Red () { echo -e "\e[31;1m$1\e[0m"; }
	White () { echo -e "\e[37;1m$1\e[0m"; }
	Yellow () { echo -e "\e[33;1m$1\e[0m"; }
	Magenta () { echo -e "\e[35;1m$1\e[0m"; }
	Cyan () { echo -e "\e[36;1m$1\e[0m"; }
###

fLog () {
  # My crude, homemade logging tool
  TIMESTAMP=$(date +%F' '%H':'%M' '%Z)
  echo "$TIMESTAMP - $1" >> $FLOGPATH
}

ShutDownDocker () {
# Some systems had docker, which back then needed to be shut down before updating.
	service docker stop
	sleep 2
}

GetUserHostInput () {
  read -p "Type in the new host name, WITHOUT domain: " NOOHOST
  read -p "What is the domain for \"$NOOHOST\" [$DEFAULT_DOMAIN]?: " NOODOMAIN
  if [ -z $NOODOMAIN ]; then
    NOODOMAIN=$DEFAULT_DOMAIN
  fi
fLog "Host been declared as $NOOHOST.$NOODOMAIN"
}

CheckForVMwareNIC () {
# There were two types of NIC that VMWare was serving, and to activate it and assign an IP
#  I had to know which one it was, or if it wasn't assigned at all.  E1000 was the "old and 
#  busted," VMXNET3 was the "new hotness"
  E1000=$(lsmod | grep e1000 | awk '{print $1}')
  VMXNET3=$(lsmod | grep vmxnet3 | awk '{print $1}')
  echo "E1000 = $E1000"
  echo "VMXNET3 = $VMXNET3"

  if [ $E1000 ]; then
	  Cyan "I have an E1000 NIC [meh]... "
	  NIC_MODULE="e1000"
	  fLog "I have a crummy e1000 NIC"
  elif [ $VMXNET3 ]; then
	  Green "I have a VMXNET3 NIC [yay...]"
	  NIC_MODULE="vmxnet3"
	  fLog "SWEET! A wild $VMXNET3 has appeared!"
  else
	  Alert "I have no idea what kind of network module I have!"
	  Red "I was expecting an e1000 or vmxnet3, but neither"
	  Red "showed up on an lsmod call.  This script will now"
	  Red "abort: no changes have been made."
	  fLog "Script aborted because it didn't know if it had an e1000 or VMXNET3 NIC in CheckForVMwareNIC()"
	  exit 1
  fi
}

WhatsMyIp () {
# Sometimes the dev machines were ported to QA, and we had to change the address.
  if [ $WHATSMYIP ]; then
	  echo -n "I already seem to have an IP of "
	  Alert "$WHATSMYIP"
	  fLog "Detected existing IP of $WHATSMYIP"
	  read -p "Proceed anyway? [y/n]? " PROCEED
	  if [ $PROCEED != "y" ]; then
		  fLog "User quit because they wanted to keep the IP in WhatsMyIp()"
		  echo "Quitting..."
		  exit 1
	  fi
  fi
}

ResetNetNIC () {
# Here was the original reason for this script.  The UDEV rules at the time would reboot and detect a new NIC
#  **all the time** and then put it at eth1.  This script would blow away the rules and "rediscover" the NIC
#  to assure that it would be on the right interface (eth0) and not just add a new one.
  read -p "If this machine will get an IP by DHCP, just hit RETURN (type \"F\" to set IP manually): " IPTYPE
  
  if [ -z $IPTYPE ]; then
        IPTYPE="DHCP"
        FIXEDIP="[DHCP]"
        FIXEDGATEWAY="[DHCP]"
        FIXEDNETMASK="[DHCP]"
        fLog "User chose DHCP (default) for getting IP"
  else
        IPTYPE="FIXED"
        read -p "Please enter in the IP address: " FIXEDIP
        read -p "Netmask [enter for $FIXEDNETMASK]: " TEMPMASK
        if [ $TEMPMASK ]; then
                FIXEDNETMASK=$TEMPMASK
        fi
        FIXEDGATEWAY=$(echo $FIXEDIP | cut -d. -f1,2,3)
        if [ "$FIXEDGATEWAY" == "10.111.11" ]; then
		FIXEDGATEWAY="10.111.11.254"
	else	
		FIXEDGATEWAY="$FIXEDGATEWAY.1"
        fi
        read -p "Type in default Gateway [enter for $FIXEDGATEWAY]: " READGATE
        if [ $READGATE ]; then
                FIXEDGATEWAY=$READGATE
        fi
        read -p "IP Address from Primary DNS: " DNS1
        read -p "IP Address from Secondary DNS: " DNS2
        read -p "IP Address from Tertiary DNS: " DNS3
        fLog "User chose a fixed IP of $FIXEDIP Netmask $FIXEDNETMASK and Gateway $FIXEDGATEWAY"
        fLog "User DNS Pri/Sec/Ter is $DNS1/$DNS2/$DNS3"
  fi

  DHCP_HOSTNAME="$NOOHOST.$NOODOMAIN"
  
  echo "CONFIRMING:
  Hostname: $DHCP_HOSTNAME
  IP Address: $FIXEDIP
  Netmask: $FIXEDNETMASK
  Default Gateway: $FIXEDGATEWAY
  DNS1: $DNS1
  DNS2: $DNS2
  DNS3: $DNS3
  "
  
  Alert "THIS CHANGE WILL BE PERMANENT, AND THE SCRIPT WILL GO ON AUTOPILOT"
  
  read -p "Hit cntl +c if this is bad, or you want to exit before a permenant change is made, otherwise hit enter: " TEMPYN
  
  Info "Stopping network..."
    /sbin/service network stop
  Info "Removing $NIC_MODULE module..."
    /sbin/rmmod $NIC_MODULE
    
    # This comment is for refrenece purposes only
    # /lib/udev/write_net_rules
    # /sbin/udevadm

  Info "Deleting old udev script for MAC $MYOLDMAC..."
    rm -f /etc/udev/rules.d/70-persistent-net.rules
  Info "Re-adding $NIC_MODULE module..."
    /sbin/modprobe $NIC_MODULE
  Info "Changing hosts file..."
    echo "# 
# This hosts file was created on $MYDATE
#  by script $0
127.0.0.1       $NOOHOST $NOOHOST.$NOODOMAIN
127.0.0.1       localhost localhost.localdomain
#" > /etc/hosts
  
  Info "Changing networking settings..."
  echo "# This network file was created on $MYDATE
#  by script $0
NETWORKING=yes
HOSTNAME=$NOOHOST.$NOODOMAIN
" > /etc/sysconfig/network

    if [ $IPTYPE == "DHCP" ]; then
	  Info "I THINK I AM DHCP"
	  echo "# This ifcfg for eth0 file was created on $MYDATE
  # by script $0
  DEVICE=\"eth0\"
  NM_CONTROLLED=\"yes\"
  ONBOOT=\"yes\"
  BOOTPROTO=\"dhcp\"
  DHCP_HOSTNAME=\"$NOOHOST.$NOODOMAIN\"
  " > /etc/sysconfig/network-scripts/ifcfg-eth0

    else
	  Info "I THINK I HAVE A FIXED ADDRESS"
	  sleep 5
	  echo "# This ifcfg for eth0 file was created on $MYDATE
  # by script $0
  DEVICE=eth0
  NM_CONTROLLED=yes
  TYPE=Ethernet
  ONBOOT=yes
  BOOTPROTO=none
  IPADDR=$FIXEDIP
  NETMASK=$FIXEDNETMASK
  GATEWAY=$FIXEDGATEWAY
  " > /etc/sysconfig/network-scripts/ifcfg-eth0
    fi

  Info "Starting network..."
    /sbin/service network start

Green "Here's your IP:"

MYIP=$(/sbin/ifconfig | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}' | head -n1)
echo $MYIP
  
  Info "Attempting to ping Gateway: "
  if [ "$IPTYPE" == "FIXED" ]; then
	  ping -c 4 $FIXEDGATEWAY
	  CONNECTED_NET_STATUS=$?
  else
	  DHCPGATEWAY=$(ip route | grep default | awk '{print $3}')
	  ping -c 4 $DHCPGATEWAY
	  CONNECTED_NET_STATUS=$?
  fi

  if [ $CONNECTED_NET_STATUS==0 ]; then
	  IPRESULT=$(host $MYIP | tail -n 1 | cut -d' ' -f5)
	  SERVERRESULT="$DHCP_HOSTNAME."
	  if [ "$SERVERRESULT" == "$IPRESULT" ]; then
		  echo -e "\e[32;1mServer name match! \e[33m:D\e[0m"
	  else
		  Alert "The $SERVERRESULT does not match $IPRESULT for $MYIP"
	  fi

  else
	  echo -e "\e[31;7m * I don't seem to have any network connectivity *"
		      echo "Please check that the NIC is connected in Edit > "
		      echo "Settings in vSphere. Also check the network VLAN "
		      echo "and DHCP (and GIP Services have been restarted). "
	  echo -e "\e[0m"
	  read -p "Hit any key to continue or [CNTL + C] to quit and try again: " TEMP
  fi

  echo -e "\e[33mOLD MAC address: \e[m $MYOLDMAC"
  MYNEWMAC=$(ip a | grep "link/ether" | awk '{print $2}')
  echo -e "\e[32mNew MAC address: \e[m $MYNEWMAC"
  
  hostname $DHCP_HOSTNAME
 
}

MakeFixedIPScript () {
# This was added to make an "emergency make a fixed IP" kind of thing

echo "\#/!bin/bash" > $MakeFixedIPScriptPATH
echo "\# This script was created by $0 at $MYDATE" >> $MakeFixedIPScriptPATH
echo "ifconfig -a eth0 $IPADDR netmask 255.255.255.0" >> $MakeFixedIPScriptPATH
echo "route add default gw $DHCPGATEWAY" >> $MakeFixedIPScriptPATH
echo "echo \"IP set to $IPADDR/24 with gateway $DHCPGATEWAY\"" >> $MakeFixedIPScriptPATH
echo "exit 0" $MakeFixedIPScriptPATH

}

WhatMachineTypeAmI () {
# In this compnay, the networks were segregated, so if you knew what IP address you had, you knew what kind of machine
#   you should be.
  IPADDR=$(ip a show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
  VLANIP=$(echo $IPADDR | cut -d. -f1,2,3)
      case $VLANIP in
                        10.1.3)
                                MACHINETYPE="Production"
                                DEF_KEY=$INT_KEY
                                ISSUE_BANNER="issue.prod"
                                ;;
                        10.1.4)
                                MACHINETYPE="Staging"
                                DEF_KEY=$STG_KEY
                                ISSUE_BANNER="issue.stage"
                                ;;
                        10.1.6)
                                MACHINETYPE="Development"
                                DEF_KEY=$DEV_KEY
                                ;;
                        10.1.7)
                                MACHINETYPE="Production"
                                DEF_KEY=$PRD_KEY
			                          ISSUE_BANNER="issue.prod"
                                ;;
                        192.168.103)
                                MACHINETYPE="Staging"
                                DEF_KEY=$STG_KEY
                                ISSUE_BANNER="issue.stage"
                                ;;
                        192.168.101)
                                MACHINETYPE="Production"
                                DEF_KEY=$PRD_KEY
                                ISSUE_BANNER="issue.prod"
                                ;;
                        192.168.102)
                                MACHINETYPE="Production"
                                DEF_KEY=$PRD_KEY
                                ISSUE_BANNER="issue.prod"
                                ;;
                        192.168.11)
                                MACHINETYPE="Production"
                                DEF_KEY=$PRD_KEY
                                ISSUE_BANNER="issue.prod"
                                ;;
                        192.168.12)
                                MACHINETYPE="Production"
                                DEF_KEY=$PRD_KEY
                                ISSUE_BANNER="issue.prod"
                                ;;
                        192.168.13)
                                MACHINETYPE="Staging"
                                DEF_KEY=$STG_KEY
                                ISSUE_BANNER="issue.stage"
                                ;;
                       192.168.122)
                                MACHINETYPE="Punkadyne VM on KVM "
                                DEF_KEY=$PNK_KEY
                                ISSUE_BANNER="issue.punkadyne"
				;;
                        10.111.11)
                                MACHINETYPE="Punkadyne"
                                DEF_KEY=$PNK_KEY
                                ISSUE_BANNER="issue.punkadyne"				
				;;
                        *)
                                MACHINETYPE="Unknown"
                                ;;
                esac
                
      fLog "I have been declared a $MACHINETYPE machine in WhatMachineTypeAmI()"
}

SetSNMPSettings () {
  Info "Changing SNMP Settings...."
  SNMPID=$(echo $IPADDR | cut -d. -f1)
  SNMPDCOMMUNITY='
rocommunity EXAMPLCOMonpubl # snmpd.conf string EXAMPLCOMonpubl for all 10.1.x.x networks
'
    if [ "$SNMPID" == "192" ]; then
    SNMPDCOMMUNITY='
rocommunity 3XT_3XMPL-CO-Mon # snmpd.conf string 3XT_3XMPL-CO-Mon for all 192.168.x.x networks
'
    fi

  echo $SNMPDCOMMUNITY > /etc/snmp/snmpd.conf

}

CreateOrionUser () {
# We had orion monitoring 
  echo -e "\nI am a \e[33m Creating orion user...\e[m"
  TEMPYN=$(grep orion /etc/passwd)
  if [ $TEMPYN ]; then
	  echo "... orion already exists"
	  fLog "Orion is already a user on this box"
  else
	  useradd orion
	  echo 'orion:!C0nn3ct.' | chpasswd
	  echo "... added user orion."
	  fLog "Orion added as a user."
  fi

}

ChangePassword () {
  echo -e "\nI am a \e[33m >> $MACHINETYPE <<\e[m machine!  Changing password...\n"
  usermod --pass="$DEF_KEY" root
  fLog "Password changed as a $MACHINETYPE server"
  sleep 1
}

AuditUsers () {
# This removed ANYONE not allowed on production or staging systems.  The rule was 
#  dev = admin users, all developers
#  qa = admin users, all developers
#  staging = admin users only, test and QA folks only in special cases
#  production = admin users only
#  
#  So if a user, "dev1" was on the dev machines, and it got cloned to staging, they'd be automatically removed.
#  This prevented them from logging in, or having a process running under their name

  if [ "$MACHINETYPE" == "Staging" -o "$MACHINETYPE" == "Production" ]
  then

	  USERSOVER500=$(awk -F: ' $3>=500 {print $1}' /etc/passwd)
	  EXCEPTIONS="alek millosh glarson nfsnobody orion nginx riak sherman_ sherman_display sherman_scraper eoldham"

	  for USERNAME in $USERSOVER500
	  do
	  ISEXCEPTION=$(echo $EXCEPTIONS | sed -e 's/\ //g' | grep $USERNAME)

	  if [ -z $ISEXCEPTION ]
	  then
		echo -e "\e[31m**!! User $USERNAME is normally not allowed on $MACHINETYPE system!**  Remove?\e[m [y/N]"
		fLog "The login $USERNAME was discovered."
		read FOZZIE
          	if [ "$FOZZIE" == "Y" -o "$FOZZIE" == "y" ]; then
			fLog "Because this is a $MACHINETYPE system, unauthorized user $USERNAME was removed by request."
                        ADMINSUDO="/etc/sudoers.d/10_$USERNAME"
                        if [ -a $ADMINSUDO ]; then 
				fLog "... in addition, the admin user file $ADMINSUDO was removed"
				rm -f $ADMINSUDO
			fi
                        userdel -r $USERNAME
			
		else
			fLog "The login $USERNAME was kept."
		fi
	
	  else
		  echo -e "\e[32m$USERNAME is allowed on a staging or prodcution machine\e[m"
		  fLog "$USERNAME allowed on a $MACHINETYPE system (which may be due to a vital app that had a UID over 500)."	  
	  fi
	  done

  fi
  sleep 3
}

SetBanners () {
  Info "Setting banners..."
  if [ "$MACHINETYPE" == "Development" ]; then
  
	  cp /etc/$ISSUE_BANNER /etc/issue
	  fLog "Copied dev banner to console login."
	  cp /etc/issue.login.banner /etc/issue.ssh

  elif [ "$MACHINETYPE" == "Staging" ]; then

	  rm -f /etc/issue.ssh
	  cp /etc/$ISSUE_BANNER /etc/issue
	  fLog "Copied staging banner to console login."
  else
  
	  rm -f /etc/issue.ssh
	  cp /etc/$ISSUE_BANNER /etc/issue
	  fLog "Copied $ISSUE_BANNER banner to console login."
  fi
}

SetMOTD () {

  MYBANNER=$NOOHOST

  # Crude word-wrapping
  if [ ${#NOOHOST} > 10 ]; then
	# MYBANNER=$(echo $NOOHOST | sed -e "s/\-/-\n/")
	MYBANNER=$(echo $NOOHOST | fold -s -w 10)
  fi

  # Check and see if we have figlet, and if not, try and get it.
  TEMPYN=$(rpm -qa | grep figlet)

  if [ $TEMPYN ]; then
	  echo $MYBANNER | figlet -p | boxes -d shell > /etc/motd
	  cat /etc/motd
	  echo -en "\e[32mIs this the banner format, name, and word-wrap you want [Y/n]? \e[m"
	  read TEMPYN

	  if [ "$TEMPYN" == "N" -o "$TEMPYN" == "n" ]; then
		  echo "Enter in the exact format and name, complete with line breaks below, end with a \"#\" character:"
		  read -d# MYBANNER
		  echo $MYBANNER | figlet -p | boxes -d shell > /etc/motd
		  echo ""
		  cat /etc/motd
	  fi
	  fLog "MOTD set to $MYBANNER"
  else
	  yum install -y figlet boxes 
	  fLog "Attempting to install figlet"
	  TEMPYN=$(rpm -qa | grep figlet)
	  if [ $TEMPYN ]; then
		  echo $MYBANNER | figlet -p | boxes -d shell > /etc/motd
		  cat /etc/motd
		  echo -en "\e[32mIs this the banner format, name, and word-wrap you want [Y/n]? \e[m"
		  read TEMPYN

		  if [ "$TEMPYN" == "N" -o "$TEMPYN" == "n" ]; then
			  echo "Enter in the exact format and name, complete with line breaks below, end with a \"#\" character:"
			  read -d# MYBANNER
			  echo $MYBANNER | figlet -p | boxes -d shell > /etc/motd
			  echo ""
			  cat /etc/motd
		  fi
		  fLog "MOTD set to $MYBANNER"
	  else
		  echo "##[[ $MYBANNER ]]##" > /etc/motd
		  cat /etc/motd
		  fLog "MOTD set to $MYBANNER"
	  fi
  fi


}

CheckMySQL () {
# This was in progress, but we had another manageent tool that the DBAs used that was better for them.
  CHECKMYSQL=$(chkconfig --list | grep mysqld)

  if [ $CHECKMYSQL ]; then
	  fLog "MySQL server found on this system."
	  echo -e "\e[31m YOU HAVE MYSQL INSTALLED ON THIS SYSTEM\e[m"
	  echo "
  This script does not have the intelligence to change the users yet, 
  but YOU MUST look at the users and passwords and CHANGE THEM if to 
  match a $MACHTINETYPE system!

  $CHECKMYSQL

  "

  read -p "Press any key to continue" TEMPYN

  fi

}

ResetKeysReboot () {

echo -e "\n\n\e[32m If this is a NEW host, please hit Y to the question below:\e[m\n"

read -p "Regenerate host keys, puppet, and check for new packages? [y/N] " TEMPYN

if [ "$TEMPYN" != "Y" -a "$TEMPYN" != "y" ]; then
	fLog "Host keys, puppet, new packages not installed... rebooting"
	echo "You have selected \"No\" for \"Do you wish to cancel autodestruct sequence?\"."
	sleep 1;
	echo "Auto destruct sequence initiated.  Please evacutate ship."
	BOOM=5
	while [ $BOOM -gt 0 ]; do echo "Complete annihilation in $BOOM seconds"; sleep 1; let BOOM=BOOM-1; done 
	sleep 2;
	echo "+++ATZ     NO CARRIER"
	/sbin/reboot
	exit 0
fi

fLog "Regenerating host keys, puppet certs, and updating packages via YUM.  Then rebooting."
echo -e "\n\n\e[34m Regenerating SSH Host keys...\e[m"
	rm -rfv /etc/ssh/*key*
	/sbin/service sshd restart

echo -e "\n\n\e[34m Running yum update.\e[m"

	yum clean all
	yum update -y

echo -e "\n\n\e[34m Clearing puppet certs - run \"puppet agent -t\" after reboot to generate new ones and connect to puppet master\e[m"
	service puppet stop 
	rm -rf /var/lib/puppet/ssl/* /etc/puppet/ssl/*
	# puppet agent --server puppet.example-company.org --waitforcert 10 --test --verbose
	chkconfig puppet on
        
echo "Hit [cntl] + C to stop rebooting sequence"
        sleep 1;
        echo "Reboot sequence initiated. Please take all you items and belongings with you."
        BOOM=5
        while [ $BOOM -gt 0 ]; do echo "Rebooting in $BOOM seconds"; sleep 1; let BOOM=BOOM-1; done
        sleep 2;
        echo "... see you on the other side."
        /sbin/reboot


exit 0

}
#
######################################################### [ END FUNCTIONS] ####

### [ MAIN SCRIPT ] ###########################################################
#

Header "=========[ VMWare cloning/migration Fixing script ver $VERSION ]=========="
echo "**
** This script will ERASE network, hostname, and other settings that
**       are a neccessary fix for CentOS 6 guests from clones
**          or MIGRATING a system from one VLAN to another.  
** 
**    Please hit any key to proceed, OR [Cntl] + c to cancel: "
Header "======================================================================"
read TEMPYN

fLog "Started $0 ver $VERSION"

GetUserHostInput
ShutDownDocker
CheckForVMwareNIC
WhatsMyIp 
ResetNetNIC
MakeFixedIPScript
WhatMachineTypeAmI 
SetSNMPSettings 
CreateOrionUser 
ChangePassword 
AuditUsers 
SetBanners 
SetMOTD 
CheckMySQL
ResetKeysReboot

#
###################################################### [ END MAIN SCRIPT ] ####

exit 0

