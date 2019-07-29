#!/bin/bash
# 
# This is an example of a huge bash report, which, really, should be written in python but I didn't have a python interpreter at the time
#   and my python skills were still low, boto3 wasn't out yet, excuses excuses.  But what a bash file, huh?  WOW-WIE.  This
#   will:
#   - Get your current AWS EC2 inventory
#   - Check for various versions of things (docker, php, etc)
#   - Parse it out to spreadsheets (csv files)
#   - Setup a web page which can be pushed to a web server
# 
# For debugging purposes
# set -eu

# The way I have this is that that are two profiles in my ~/.aws/config set up thusly (and a default)
# 
# [profile examplco]
#   region=us-east-1
#   output=json
# [profile examplcotech]
#   region=us-east-1
#   output=json
# [default]
#   output = json
#   region = us-east-1
# export AWS_DEFAULT_PROFILE=examplco

# *** NOTE: THIS IS NEEDED IF IT IS TO BE RUN AS A CRONJOB
export HOME=/home/glarson
# ... or wherever your aws config is

# TAGS
# ---------------
# Name             - The AWS name (project-purpose-environment, like bva-db-dev)
# Environment      - Development/Testing/Production
# Project Code     - The project code this is billed to
# Project URLs     - The URL or URLs this server answers to
# EXAMPLE-CO Admin        - Engineering contact (Fred, Grig, Ken, Carlos, etc)
# EXAMPLE-CO Developer    - Software Development contact (Dean, Liz, Jason, Li, etc)
# Jira Ticket      - JIRA ticket URL
# Application      - Drupal, mysql dabatase, custom html, etc
# EXAMPLE-CO Program Lead - who regularly coordinates activities between our team and the client.
# Client Name      - Project contact name
# Client Email     - Project contact email
# Notes            - Any extra weird, but VITAL information 
# Windows Version  - If a Windows swerver, what version? [Windows only]

DATE_INVENTORY=$(date -Ins | awk -F, '{print $1}')

WORKING_DIR="/home/glarson/code/adelade_aws"
OUTPUT_CSV="${WORKING_DIR}/aws_inventory_${DATE_INVENTORY}.csv"
INSTANCE_RAWDATA="${WORKING_DIR}/aws_raw.txt"
INSTANCE_IDS="${WORKING_DIR}/aws_instance_ids.txt"
ANSIBLE_IP_FILE="${WORKING_DIR}/ansible_list.txt"
ANSIBLE_HOST_FILE="${WORKING_DIR}/ansible_hosts.txt"
AWS_JSON="${WORKING_DIR}/aws.json"
CURRENT_LINK="${WORKING_DIR}/current_inventory.csv"
HTML_HEADER="/home/glarson/code/html_header"
HTML_FOOTER="/home/glarson/code/html_footer"
HTML_FILE="${WORKING_DIR}/index.html"
DOMAIN_AUDIT_FILE="${WORKING_DIR}/domain_audit.csv"

# These are just for my laptop convenience, comment out on a real server - Grig
MY_HOSTS_FILE="${WORKING_DIR}/hosts_file.txt"
MY_BASH_COMPLETION="/home/glarson/.bash_aliases"
GRIG_BASH_COMPLETION="glarson@127.0.0.1"
ANSIBLE_KEY="/home/glarson/.ssh/id_rsa"
# ANSIBLE_KEY="/home/glarson/.ssh/devops.pem"
ANSIBLE_SERVER_IP="127.0.0.1"

SSH_LOGIN="glarson"
SSH_COMMAND="ssh -qt -i ${ANSIBLE_KEY} -o ConnectTimeout=5 -o StrictHostKeyChecking=no"
AWS_COMMAND="/home/glarson/.local/bin/aws" 	# Note, due to the python nature, this has to be a full path

# Note, all arrays have to be declared or else you'll get errors like:
#    get_aws_reports.bash: line 341: i-00c62f6d925551212: value too great for base (error token is "00c62f6d925551212")
#  because bash interprets certain strings of instance IDs that start with "0" as octal

# Hashes                                # Explanations/Examples/Formats
# =============================================================================
# AWS Fields
declare -A INSTANCE_AVAILABILITY_ZONE   #  us-east-1d
declare -A INSTANCE_DATE_LAUNCHED       #  2016-09-28T18:03:07.000Z
declare -A INSTANCE_KEYPAIR             #  EXAMPLE-CO-EC2-May-2016
declare -A INSTANCE_OS_TYPE             #  linux/windows
declare -A INSTANCE_PRIVATE_IP          #  10.50.4.1
declare -A INSTANCE_PUBLIC_IP           #  23.45.1.6
declare -A INSTANCE_RESERVATION_ID      #  1764303f-723f-47d7-838c-2d6cc5551212
declare -A INSTANCE_STATE               #  running/stopped
declare -A INSTANCE_TYPE                #  t2.large

# AWS .Fields[].Tags [NOTE: We need to data scrub here for things like commas]
declare -A INSTANCE_ENVIRONMENT_NAME    #  dev/qa/prod/freemium/etc
declare -A INSTANCE_SERVER_ROLE         #  
declare -A INSTANCE_NAME                #  project-purpose-environment, bva-web-dev
declare -A INSTANCE_NOTES               #  256 char limit: "This is the Ultron server for Chrome deployment."

# Stuff I have to SSH for
declare -A INSTANCE_DB_SERVER           #  mysqld  Ver 5.6.30-0ubuntu0.14.04.1 for debian-linux-gnu on x86_64 ((Ubuntu))
declare -A INSTANCE_DRUPAL              #  from CHANGELOG.txt
declare -A INSTANCE_KERNEL              #  4.4.30-32.54.amzn1.x86_64
declare -A INSTANCE_OS_VERSION          #  Amazon Linux AMI release 2016.09, Ubuntu 14.04.4 LTS
declare -A INSTANCE_PACKAGE_MANAGER     #  deb or yum (needed for ansible to determine package names)
declare -A INSTANCE_PHP_VERSION         #  PHP 5.5.9-1ubuntu4.17
declare -A INSTANCE_UPTIME              #  17 days 19 hours 
declare -A INSTANCE_WEB_SERVER          #  Apache/2.4.7 (Ubuntu),nginx/1.10.1
declare -A INSTANCE_OPENSSH_VERSION		#  OpenSSH_6.6.1p1 Ubuntu-2ubuntu2.10, OpenSSL 1.0.1f 6 Jan 2014 [TWO FER ONE]
# declare -A INSTANCE_OPENSSL_VERSION	#  OpenSSL 1.0.2g  1 Mar 2016
declare -A INSTANCE_DOCKER		#  Docker version 17.05.0-ce, build 89658be

# Stuff I "Figure out" based on other stuff
declare -A INSTANCE_ANISBLE_READY       #  Is Ansible on this server ready to go?
declare -A INSTANCE_ANSIBLE_IP          #  The IP ansible uses to log in.  

declare -A ANSIBLE_EXCEPTIONS		#  Sometimes, you don't want ansible touching some old-assed, dumb blond of a server
# ANSIBLE_EXCEPTIONS[10.5.1.60]="Portal, which has some fragile dependencies"
# ANSIBLE_EXCEPTIONS[10.5.14.242]="OpenEDx Ubuntu 12.04, delecate proprietary setup"
# ANSIBLE_EXCEPTIONS[10.5.33.41]="ABCDZ-db-sec with no outside Internet access, so yum will fail"
ANSIBLE_EXCEPTIONS[10.3.1.33]="Custom Redhat Box"
ANSIBLE_EXCEPTIONS[10.3.7.69]="Custom FreeBSD box"

# Arrays                                # Explanations/Examples/Formats
# =============================================================================
ANSIBLE_PROD=""			        # All production machines
ANSIBLE_FREEMIUM=""			# All freemium machines
ANSIBLE_INTERFACE=""			# All interface machines
ANSIBLE_DEV=""			        # All development machines
ANSIBLE_QA=""			        # All qa servers
ANSIBLE_SHARED=""			# All shared servers
ANSIBLE_MYSTERY=""			# Mysterious unknown machines

function ZeroFiles {
	# Create the header
	# THE 504 SPEADSHEET: Profile,NewInstanceName,Project Code,OS,OS Version,Last Updated,KeyPair,Public IP,Private IP,SSH Update,CDN?,Ansible,InstanceState 
	
	echo "InstanceID,Instance Name,Status,Environment,OS,Profile,Type,Private IP,Public IP,Ansible IP,Ansible Ready?,OS Version,Kernel,PkgMgr,Uptime,Web Server,OpenSSH_svr,OpenSSL,DB Server,PHP,Docker,AVB Zone,KeyPair,ReservationID,Date Launched,Server Role,Inventory Date,Notes," > ${OUTPUT_CSV}
	
	echo -en "# This ansible host file was auto-created by an inventory script\n#  $0 \n#  on hostname $HOSTNAME\n#  at ${DATE_INVENTORY}\n# \n\n"> ${ANSIBLE_HOST_FILE}
	# This saves old aliases
        cp ${MY_BASH_COMPLETION} ${MY_BASH_COMPLETION}.bak
	
	# Zero out the data files
	> ${INSTANCE_RAWDATA}
	> ${INSTANCE_IDS}
	> ${ANSIBLE_IP_FILE}
	> ${AWS_JSON}
	> ${MY_BASH_COMPLETION}
	> ${DOMAIN_AUDIT_FILE}

	cp ${HTML_HEADER} ${HTML_FILE}
	UPDATED=$(date)
	UPDATED="created on ${HOSTNAME} ${UPDATED}"
	sed -i -e "s/FNORD/${UPDATED}/" ${HTML_FILE}

	# Put the ansible headers in the associated arrays
	ANSIBLE_PROD=(${ANSIBLE_PROD[@]} '[prod]')
	ANSIBLE_QA=(${ANSIBLE_QA[@]} '[qa]')
	ANSIBLE_SHARED=(${ANSIBLE_SHARED[@]} '[shared]')
	ANSIBLE_DEV=(${ANSIBLE_DEV[@]} '[dev]')
	ANSIBLE_INTERFACE=(${ANSIBLE_DEV_DEB[@]} '[interface]')
        ANSIBLE_FREEMIUM=(${ANSIBLE_FREEMIUM[@]} '[freemium]')
	ANSIBLE_MYSTERY=(${ANSIBLE_MYSTERY[@]} '[LOL_wut]')

# exit 0

}

function DisplayTime {
  local T=$1
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))
  (( $D > 0 )) && printf '%d days ' $D
  (( $H > 0 )) && printf '%d hours ' $H
  # (( $M > 0 )) && printf '%d minutes ' $M
  # (( $D > 0 || $H > 0 || $M > 0 )) && printf 'and '
  # printf '%d seconds\n' $S
}

function GetInventory {

	# This is the main part where we get inventory
	#  Instead of asking aws every time, I started parsing from the JSON file after
	#  downloading it just once to massively speed up this script.

	${AWS_COMMAND} ec2 describe-instances --instance-ids --output json > ${AWS_JSON} || echo -e "\e[31;1mI couldn't get the raw data from profile ${AWS_SCRIPT_PROFILE}!! OH NOEZ!!1!\e[0m"
	# aws ec2 describe-instances --instance-ids --output json | jq -r '.Reservations[].Instances[].InstanceId' | sort > ${INSTANCE_RAWDATA} || echo -e "\e[31;1mI couldn't get the raw data from profile ${AWS_SCRIPT_PROFILE}!! OH NOEZ!!1!\e[0m"

	cat ${AWS_JSON} | jq -r '.Reservations[].Instances[].InstanceId' | sort > ${INSTANCE_RAWDATA}
	INSTANCE_RECORDS=$(cat ${INSTANCE_RAWDATA})
	INSTANCE_COUNT=$(wc -l ${INSTANCE_RAWDATA} | cut -d' ' -f 1)
	COUNT_SO_FAR=0

	echo "There are a total of ${INSTANCE_COUNT} ${AWS_SCRIPT_PROFILE} instances"

	for INSTANCE_LINE in ${INSTANCE_RECORDS}
	do
        
        let "COUNT_SO_FAR++"
 	echo -n "Working on ${COUNT_SO_FAR} of ${INSTANCE_COUNT} ..."

	# Let's get some basics first
	INSTANCE_STATE[${INSTANCE_LINE}]=$(cat ${AWS_JSON} | jq -r \
	'.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .State.Name')

	# If the instance is "terminated," this will cause some "jq: null" issues.  Need to fix that.
	#   Working on 41 of 54 ...jq: error (at <stdin>:6692): Cannot iterate over null (null)
	#   jq: error (at <stdin>:6692): Cannot iterate over null (null)
	#   jq: error (at <stdin>:6692): Cannot iterate over null (null)
	#   jq: error (at <stdin>:6692): Cannot iterate over null (null)
 	#   at  ... is terminated...  done
	# This may also fuck other things up if it's "starting..." or something.

	
	INSTANCE_NAME[${INSTANCE_LINE}]=$(cat ${AWS_JSON}  | jq -r \
	'.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .Tags[] | select (.Key=="Name") | .Value')
 
        # In case the "Name" tag field was left blank, just name it the instance-id ¯\_(ツ)_/¯
        if [ -z "${INSTANCE_NAME[${INSTANCE_LINE}]}" ]; then INSTANCE_NAME[${INSTANCE_LINE}]="${INSTANCE_LINE}"; fi
	
        INSTANCE_SERVER_ROLE[${INSTANCE_LINE}]=$(cat ${AWS_JSON}  | jq -r \
	'.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .Tags[] | select (.Key=="serverRole") | .Value')

	INSTANCE_ENVIRONMENT_NAME[${INSTANCE_LINE}]=$(cat ${AWS_JSON}  | jq -r \
        '.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .Tags[] | select (.Key=="environmentName") | .Value')

	INSTANCE_NOTES[${INSTANCE_LINE}]=$(cat ${AWS_JSON}  | jq -r \
        '.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .Tags[] | select (.Key=="Notes") | .Value' | tr "[:punct:]" "-")

	INSTANCE_NOTES[${INSTANCE_LINE}]="\"${INSTANCE_NOTES[${INSTANCE_LINE}]}\"" # Encasing this in quotes for data sanitizing

# These are some of the old ways we did on the aws cli command line, saved for reference
# INSTANCE_STATE[${INSTANCE_LINE}]=$(aws ec2 describe-instances --instance-ids ${INSTANCE_LINE} --output json | jq -r '.Reservations[].Instances[].State.Name')
# INSTANCE_NAME[${INSTANCE_LINE}]=$(aws ec2 describe-instances --instance-ids ${INSTANCE_LINE}  --output json | jq -r '.Reservations[].Instances[].Tags[] | select ( .Key | contains("Name") ) | .Value')
	
	# Special problem here: If it's Windows, it is "windows."  If it is Linux, it is the 
	#  actual word "null".  Dumb.  So we have to make ammends
	INSTANCE_OS_TYPE[${INSTANCE_LINE}]=$(cat ${AWS_JSON} | jq -r \
	'.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .Platform')
	
	if [[ ${INSTANCE_OS_TYPE[${INSTANCE_LINE}]} == "null" ]]
	then 
		INSTANCE_OS_TYPE[${INSTANCE_LINE}]="linux"
	fi

	# For now, "Windows Version" has to be manually entered in as a Tag.  Tip: if someone doesn't manually enter it in,
	#  you can get the version via the AMI name OR find out a version with a label that has the same AMI, which helped
	#  when someone creates "private AMIs." For Adelade, this isn't that relevant, as we only have 4 windows servers that rarely change
	if [[ ${INSTANCE_OS_TYPE[${INSTANCE_LINE}]} == "windows" ]]
	then
		INSTANCE_OS_VERSION[${INSTANCE_LINE}]=$(cat ${AWS_JSON}  | jq -r \
		'.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .Tags[] | select (.Key=="Windows Version") | .Value')
	fi
	
	# What keys we are using to log in
	INSTANCE_KEYPAIR[${INSTANCE_LINE}]=$(cat ${AWS_JSON} | jq -r \
	'.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .KeyName')

	# Now what IPs we have and we need to know which ones are external versus internal access 
	INSTANCE_PUBLIC_IP[${INSTANCE_LINE}]=$(cat ${AWS_JSON} | jq -r \
	'.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .PublicIpAddress')
	
	# I hate the term "null" as a string
	if [[ ${INSTANCE_PUBLIC_IP[${INSTANCE_LINE}]} == "null" ]]; then INSTANCE_PUBLIC_IP[${INSTANCE_LINE}]="" ;fi
	
	INSTANCE_PRIVATE_IP[${INSTANCE_LINE}]=$(cat ${AWS_JSON} | jq -r \
	'.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .PrivateIpAddress')
	
	# Right now, only the 10.x.x.x PrivateIP ranges can be logged into. 
	if [[ ${INSTANCE_PRIVATE_IP[${INSTANCE_LINE}]:0:3} == "10." ]]
	then 
		INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]=${INSTANCE_PRIVATE_IP[${INSTANCE_LINE}]}
	else
		INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]=${INSTANCE_PUBLIC_IP[${INSTANCE_LINE}]}
	fi 
	
	    if [[ ${INSTANCE_NAME[${INSTANCE_LINE}]} == *"eks"* ]]; then 
                ANSIBLE_EXCEPTIONS[${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}]="EKS Node"
            fi

	# I don't want the ansible ip written to the ansible list if I can't get in.  That includes
	#   null IPs, windows IPs (for now), or stopped systems
	if [[ ${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} == "null" || ${INSTANCE_OS_TYPE[${INSTANCE_LINE}]} == "windows" || ${INSTANCE_STATE[${INSTANCE_LINE}]} != "running" ]]
		then
			# I decided I wanted to make an alias anyway with a warning
			# echo "alias ${INSTANCE_NAME[${INSTANCE_LINE}]}=\"echo \'Warning - This IP was reported as an exception and may not be running, or is not a Linux system\';ssh ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}\"" >> ${MY_BASH_COMPLETION}
			echo "alias ${INSTANCE_NAME[${INSTANCE_LINE}]}=\"ssh ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}\"" >> ${MY_BASH_COMPLETION}
			# I hate seeing the word "null" for IP reports, and this messes up the ansible list
			INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]=""
			INSTANCE_ANISBLE_READY[${INSTANCE_LINE}]="no"
                elif [ -n "${ANSIBLE_EXCEPTIONS[${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}]}" ]
                then
			INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]=""
			INSTANCE_ANISBLE_READY[${INSTANCE_LINE}]="no"
			INSTANCE_NOTES[${INSTANCE_LINE}]=${ANSIBLE_EXCEPTIONS[${INSTANCE_PRIVATE_IP[${INSTANCE_LINE}]}]}
                elif [[ ${INSTANCE_NAME[${INSTANCE_LINE}]} == *"eks" ]]
                then
			INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]=""
			INSTANCE_ANISBLE_READY[${INSTANCE_LINE}]="no"
			INSTANCE_NOTES[${INSTANCE_LINE}]="An eks node"
                        
		else	
                        INSTANCE_ANISBLE_READY[${INSTANCE_LINE}]="yes"
			echo "alias ${INSTANCE_NAME[${INSTANCE_LINE}]}=\"ssh ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}\"" >> ${MY_BASH_COMPLETION}
			echo ${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} >> ${ANSIBLE_IP_FILE}
			
			case ${INSTANCE_ENVIRONMENT_NAME[${INSTANCE_LINE}]} in
			prod)
                            ANSIBLE_PROD=(${ANSIBLE_PROD[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
			    ;;
			dev)
                            ANSIBLE_DEV=(${ANSIBLE_DEV[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
			    ;;
			qa)
                            ANSIBLE_QA=(${ANSIBLE_QA[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
                            ;;
                        shared)
                            ANSIBLE_SHARED=(${ANSIBLE_SHARED[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
                            ;;
			freemium)
                            ANSIBLE_FREEMIUM=(${ANSIBLE_FREEMIUM[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
                            ;;
			interface)
                            ANSIBLE_INTERFACE=(${ANSIBLE_INTERFACE[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
                            ;;
                        *)
                            if [[ ${INSTANCE_NAME[${INSTANCE_LINE}]} =~ "dev" ]]; then 
                                INSTANCE_ENVIRONMENT_NAME[${INSTANCE_LINE}]="dev"
                                ANSIBLE_DEV=(${ANSIBLE_DEV[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
                            elif [[ ${INSTANCE_NAME[${INSTANCE_LINE}]} =~ "prod" ]]; then 
                                INSTANCE_ENVIRONMENT_NAME[${INSTANCE_LINE}]="prod"
                                ANSIBLE_PROD=(${ANSIBLE_PROD[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
                            elif [[ ${INSTANCE_NAME[${INSTANCE_LINE}]} =~ "qa" ]]; then 
                                INSTANCE_ENVIRONMENT_NAME[${INSTANCE_LINE}]="qa"
                                ANSIBLE_QA=(${ANSIBLE_QA[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
                            elif [[ ${INSTANCE_NAME[${INSTANCE_LINE}]} =~ "shared" ]]; then
                                INSTANCE_ENVIRONMENT_NAME[${INSTANCE_LINE}]="shared"
                                ANSIBLE_SHARED=(${ANSIBLE_SHARED[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
                            elif [[ ${INSTANCE_NAME[${INSTANCE_LINE}]} =~ "freemium" ]]; then
                                INSTANCE_ENVIRONMENT_NAME[${INSTANCE_LINE}]="freemium"
                                ANSIBLE_FREEMIUM=(${ANSIBLE_FREEMIUM[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
                            elif [[ ${INSTANCE_NAME[${INSTANCE_LINE}]} =~ "interface" ]]; then 
                                INSTANCE_ENVIRONMENT_NAME[${INSTANCE_LINE}]="interface"
                                ANSIBLE_INTERFACE=(${ANSIBLE_INTERFACE[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
                            else 
                                ANSIBLE_MYSTERY=(${ANSIBLE_MYSTERY[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")  
                            fi

                            ;;
			esac
			
	fi 
	
	# Little diagnostic help if we get stuck on some server
	echo -n "${INSTANCE_NAME[${INSTANCE_LINE}]} at ${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} ... "


	# We have to SSH for some of these
	
	TESTCHECK=$(${SSH_COMMAND} ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} 'exit')
	TESTCHECK=$?
	
	 if [[ ${INSTANCE_ANISBLE_READY[${INSTANCE_LINE}]} == "yes" && ${INSTANCE_STATE[${INSTANCE_LINE}]} == "running" && ${TESTCHECK} == 0 ]]
	 then
		
		INSTANCE_UPTIME[${INSTANCE_LINE}]=$(${SSH_COMMAND} ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} 'cat /proc/uptime' | awk -F. '{print $1}')
		INSTANCE_OS_VERSION[${INSTANCE_LINE}]=$(${SSH_COMMAND} ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} 'cat /etc/system-release 2> /dev/null || grep DISTRIB_DESCRIPTION /etc/lsb-release')
		INSTANCE_KERNEL[${INSTANCE_LINE}]=$(${SSH_COMMAND} ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} 'uname -r')
		INSTANCE_KERNEL[${INSTANCE_LINE}]=$(echo ${INSTANCE_KERNEL[${INSTANCE_LINE}]} | tr -d "\015")
		INSTANCE_UPTIME[${INSTANCE_LINE}]=$(DisplayTime ${INSTANCE_UPTIME[${INSTANCE_LINE}]})
		INSTANCE_PACKAGE_MANAGER[${INSTANCE_LINE}]=$(${SSH_COMMAND} ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} 'which apt-get || which yum' | xargs basename | tr -d "\015")
                # INSTANCE_OPENSSL_VERSION[${INSTANCE_LINE}]=$(${SSH_COMMAND} ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} 'openssl version' | tr -d "\015")
		INSTANCE_OPENSSH_VERSION[${INSTANCE_LINE}]=$(${SSH_COMMAND} ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} 'ssh -V' | tr -d "\015")
                INSTANCE_PHP_VERSION[${INSTANCE_LINE}]=$(${SSH_COMMAND} ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} 'php -v | head -n1' | tr -d "\015")
			if [[ "$INSTANCE_PHP_VERSION[${INSTANCE_LINE}]" == *"command not found"* ]]; then INSTANCE_PHP_VERSION[${INSTANCE_LINE}]=""; fi
		INSTANCE_DOCKER[${INSTANCE_LINE}]=$(${SSH_COMMAND} ${SSH_LOGIN}@${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]} 'docker -v | head -n1 | sed -e s/,//g' | tr -d "\015")                
		# Parse down to various sub-categories in ansible groups
# 		if [[ ${INSTANCE_ENVIRONMENT[${INSTANCE_LINE}]} == "Development" ]]; then
# 		  if [[ ${INSTANCE_PACKAGE_MANAGER[${INSTANCE_LINE}]} == "yum" ]]; then
# 		    ANSIBLE_DEV_AWS=(${ANSIBLE_DEV_AWS[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
# 		  else
# 		    ANSIBLE_DEV_DEB=(${ANSIBLE_DEV_DEB[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
# 		  fi
# 		elif [[ ${INSTANCE_ENVIRONMENT[${INSTANCE_LINE}]} == "Production" ]]; then
# 		  if [[ ${INSTANCE_PACKAGE_MANAGER[${INSTANCE_LINE}]} == "yum" ]]; then
#                     ANSIBLE_INTERFACE=(${ANSIBLE_INTERFACE[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
#                   else
#                     ANSIBLE_FREEMIUM=(${ANSIBLE_FREEMIUM[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
#                   fi
# 		else
# 		    ANSIBLE_MYSTERY=(${ANSIBLE_MYSTERY[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
# 		fi

		  
			
		# So, if it's Ubuntu or debian, it has DISTRIB_DESCRIPTION="Blah blah" as the standard LSB format
		#  AWS/CentOS/RedHat does not, and in addition, AWS puts a ^M (0x015) character in the file sometimes
		#  so we have to strip that out to make sure it's not interpreted as a return value
 		if [[ ${INSTANCE_OS_VERSION[${INSTANCE_LINE}]} =~ "DISTRIB_DESCRIPTION" ]]
 		then
 			INSTANCE_OS_VERSION[${INSTANCE_LINE}]=$(echo "${INSTANCE_OS_VERSION[${INSTANCE_LINE}]}" | awk -F\" '{print $2}')
 			ANSIBLE_QA=(${ANSIBLE_QA[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
 		else 
 			INSTANCE_OS_VERSION[${INSTANCE_LINE}]=$(echo -e "${INSTANCE_OS_VERSION[${INSTANCE_LINE}]}" | tr -d "\015")
 			ANSIBLE_SHARED=(${ANSIBLE_SHARED[@]} "${INSTANCE_NAME[${INSTANCE_LINE}]}~ansible_host=${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}")
 		fi
        else
		
		IP_TEMP=${INSTANCE_PRIVATE_IP[${INSTANCE_LINE}]}
		# echo -ne "  [$IP_TEMP]  "
                if [[ ${INSTANCE_STATE[${INSTANCE_LINE}]} != "running" ]]; then
                    echo -ne "\e[37mis ${INSTANCE_STATE[${INSTANCE_LINE}]}...\e[m "
                elif [[ ${INSTANCE_OS_TYPE[${INSTANCE_LINE}]} == "windows" ]]; then
                    echo -ne "\e[46;37;1mWindows...\e[m "
		elif [[ ! -z "${ANSIBLE_EXCEPTIONS[$IP_TEMP]}" ]]; then 
		    echo -ne "\e[35;1m Special case exception...\e[m (${ANSIBLE_EXCEPTIONS[${IP_TEMP}]})"
                else
                    echo -ne "\e[41;37;1mCONN ERR (${TESTCHECK}) ...\e[m "
                fi
    
	fi
	
	INSTANCE_TYPE[${INSTANCE_LINE}]=$(cat ${AWS_JSON}  | jq -r \
	'.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .InstanceType')

	INSTANCE_DATE_LAUNCHED[${INSTANCE_LINE}]=$(cat ${AWS_JSON} | jq -r \
	'.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .LaunchTime' | tr "T" " " | cut -d. -f1)
	
	INSTANCE_RESERVATION_ID[${INSTANCE_LINE}]=$(cat ${AWS_JSON} | jq -r '.Reservations[] | select (.Instances[].InstanceId=="'${INSTANCE_LINE}'")' | jq -r '.ReservationId')
	
	INSTANCE_AVAILABILITY_ZONE[${INSTANCE_LINE}]=$(cat ${AWS_JSON} | jq -r \
	'.Reservations[].Instances[] | select (.InstanceId=="'${INSTANCE_LINE}'") | .Placement.AvailabilityZone')

# Since ${INSTANCE_OPENSSH_VERSION[${INSTANCE_LINE}]} is a 2-for-1, if it's blank, we need to make it at a comma
if [[ ${INSTANCE_OPENSSH_VERSION[${INSTANCE_LINE}]} == "" ]]; then INSTANCE_OPENSSH_VERSION[${INSTANCE_LINE}]=","; fi


# Domain Audit
echo "${INSTANCE_LINE},${INSTANCE_NAME[${INSTANCE_LINE}]},${INSTANCE_PUBLIC_IP[${INSTANCE_LINE}]}" >> ${DOMAIN_AUDIT_FILE}


# Stuff everyone needs
echo -n "${INSTANCE_LINE},\
${INSTANCE_NAME[${INSTANCE_LINE}]},\
${INSTANCE_STATE[${INSTANCE_LINE}]},\
${INSTANCE_ENVIRONMENT_NAME[${INSTANCE_LINE}]},\
${INSTANCE_OS_TYPE[${INSTANCE_LINE}]},\
${AWS_SCRIPT_PROFILE},\
${INSTANCE_TYPE[${INSTANCE_LINE}]}," >> ${OUTPUT_CSV}

# Technical Backend
echo "${INSTANCE_PRIVATE_IP[${INSTANCE_LINE}]},\
${INSTANCE_PUBLIC_IP[${INSTANCE_LINE}]},\
${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]},\
${INSTANCE_ANISBLE_READY[${INSTANCE_LINE}]},\
${INSTANCE_OS_VERSION[${INSTANCE_LINE}]},\
${INSTANCE_KERNEL[${INSTANCE_LINE}]},\
${INSTANCE_PACKAGE_MANAGER[${INSTANCE_LINE}]},\
${INSTANCE_UPTIME[${INSTANCE_LINE}]},\
${INSTANCE_WEB_SERVER[${INSTANCE_LINE}]},\
${INSTANCE_OPENSSH_VERSION[${INSTANCE_LINE}]},\
${INSTANCE_DB_SERVER[${INSTANCE_LINE}]},\
${INSTANCE_PHP_VERSION[${INSTANCE_LINE}]},\
${INSTANCE_DOCKER[${INSTANCE_LINE}]},\
${INSTANCE_AVAILABILITY_ZONE[${INSTANCE_LINE}]},\
${INSTANCE_KEYPAIR[${INSTANCE_LINE}]},\
${INSTANCE_RESERVATION_ID[${INSTANCE_LINE}]},\
${INSTANCE_DATE_LAUNCHED[${INSTANCE_LINE}]},\
${INSTANCE_SERVER_ROLE[${INSTANCE_LINE}]},\
${DATE_INVENTORY},\
${INSTANCE_NOTES[${INSTANCE_LINE}]}," >> ${OUTPUT_CSV}

# The same stuff as above, but sent to an HTML file

# A fix for the blank/comma 
if [[ ${INSTANCE_OPENSSH_VERSION[${INSTANCE_LINE}]} == "," ]]; then INSTANCE_OPENSSH_VERSION[${INSTANCE_LINE}]="</td><td>"; fi

echo "<tr>
<td style="white-space:nowrap">${INSTANCE_LINE}</td>
<td style="white-space:nowrap">${INSTANCE_NAME[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_STATE[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_OS_TYPE[${INSTANCE_LINE}]}</td>
<td>${AWS_SCRIPT_PROFILE}</td>
<td>${INSTANCE_TYPE[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_PRIVATE_IP[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_PUBLIC_IP[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_ANSIBLE_IP[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_ANISBLE_READY[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_ENVIRONMENT_NAME[${INSTANCE_LINE}]}</td>
<td style="white-space:nowrap">${INSTANCE_OS_VERSION[${INSTANCE_LINE}]}</td>
<td style="white-space:nowrap">${INSTANCE_KERNEL[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_PACKAGE_MANAGER[${INSTANCE_LINE}]}</td>
<td style="white-space:nowrap">${INSTANCE_UPTIME[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_WEB_SERVER[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_OPENSSH_VERSION[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_DB_SERVER[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_PHP_VERSION[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_DOCKER[${INSTANCE_LINE}]}</td>
<td style="white-space:nowrap">${INSTANCE_AVAILABILITY_ZONE[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_KEYPAIR[${INSTANCE_LINE}]}</td>
<td style="white-space:nowrap">${INSTANCE_RESERVATION_ID[${INSTANCE_LINE}]}</td>
<td style="white-space:nowrap">${INSTANCE_DATE_LAUNCHED[${INSTANCE_LINE}]}</td>
<td>${INSTANCE_SERVER_ROLE[${INSTANCE_LINE}]}</td>
<td style="white-space:nowrap">${DATE_INVENTORY}</td>
<td>${INSTANCE_NOTES[${INSTANCE_LINE}]}</td>
</tr>
">> ${HTML_FILE}



echo " done"

# For testing so I don't have to go through EVERY server, ugh...
# if [[ $COUNT_SO_FAR = 10 ]]; then exit 0; fi
 
done

}

function WriteAnsibleHosts {

# Note: the hashes should take into account things actively running
#  and currently ansible ready (currently NO to Windows)

echo "Writing to ansible hosts file... "

# List of exceptions like "never update these guys"


# List if "ansible test" hosts	[test]
#  that we can test pushes to

# Put the ansible headers in the associated arrays
#        ANSIBLE_PROD=(${ANSIBLE_PROD[@]} '[prod_all]')
#        ANSIBLE_FREEMIUM=(${ANSIBLE_FREEMIUM[@]} '[prod_deb]')
#        ANSIBLE_INTERFACE=(${ANSIBLE_INTERFACE[@]} '[prod_aws]')
#        ANSIBLE_DEV=(${ANSIBLE_DEV[@]} '[dev_all]')
#        ANSIBLE_DEV_DEB=(${ANSIBLE_DEV_DEB[@]} '[dev_deb]')
#        ANSIBLE_DEV_AWS=(${ANSIBLE_DEV_AWS[@]} '[dev_aws]')
#        ANSIBLE_QA=(${ANSIBLE_QA[@]} '[all_deb]')
#        ANSIBLE_SHARED=(${ANSIBLE_SHARED[@]} '[all_aws]')



# Write all Production 		[prod]	
echo -e "\n# All Production Servers" >> ${ANSIBLE_HOST_FILE}
for ITEM in "${ANSIBLE_PROD[@]}" ; do echo ${ITEM} >> ${ANSIBLE_HOST_FILE}; done

# Write all Development		[dev]
echo -e "\n# All Development Servers" >> ${ANSIBLE_HOST_FILE}
for ITEM in "${ANSIBLE_DEV[@]}" ; do echo ${ITEM} >> ${ANSIBLE_HOST_FILE}; done

# Write all QA		[qa]
echo -e "\n# All *.deb Packaged Servers" >> ${ANSIBLE_HOST_FILE}
for ITEM in "${ANSIBLE_QA[@]}" ; do echo ${ITEM} >> ${ANSIBLE_HOST_FILE}; done

# Write all Shared		[shared]
echo -e "\n# All *.rpm Packaged Servers" >> ${ANSIBLE_HOST_FILE}
for ITEM in "${ANSIBLE_SHARED[@]}" ; do echo ${ITEM} >> ${ANSIBLE_HOST_FILE}; done

# Write all Freemium	[freemium]
echo -e "\n# All *.deb Produduction Servers" >> ${ANSIBLE_HOST_FILE}
for ITEM in "${ANSIBLE_FREEMIUM[@]}" ; do echo ${ITEM} >> ${ANSIBLE_HOST_FILE}; done

# Write all Interface	[interface]
echo -e "\n# All *.rpm Production Servers" >> ${ANSIBLE_HOST_FILE}
for ITEM in "${ANSIBLE_INTERFACE[@]}" ; do echo ${ITEM} >> ${ANSIBLE_HOST_FILE}; done

# Write all Interface	[LOL_wut]
echo -e "\n# Mystery Servers that didnt identify as prod OR dev" >> ${ANSIBLE_HOST_FILE}
for ITEM in "${ANSIBLE_MYSTERY[@]}" ; do echo "# ${ITEM}" >> ${ANSIBLE_HOST_FILE}; done

#  like Byactive, Rackspace, or localhost
# Add known non-aws servers		[various]

# Comment out any exceptions
for BAD_IP in "${!ANSIBLE_EXCEPTIONS[@]}"
do
	# echo "sed -i -e 's/^${BAD_IP}/\#\ ${BAD_IP}/' ${ANSIBLE_HOST_FILE}"
	# sed -i -e "s/^${BAD_IP}/\#\ ${BAD_IP}\ \#\ ${ANSIBLE_EXCEPTIONS[${BAD_IP}]}/" ${ANSIBLE_HOST_FILE}
	sed -i -e "/${BAD_IP}/ s/^/\#\ ${ANSIBLE_EXCEPTIONS[${BAD_IP}]}/" ${ANSIBLE_HOST_FILE}

done

# Remove the tilde we added earlier with a space
sed -i -e "s/\~/\ /g" ${ANSIBLE_HOST_FILE}

# Push to ansible
echo "Seexamplcong updated ansible hosts file to ansible server..."
scp -i ${ANSIBLE_KEY} ${ANSIBLE_HOST_FILE} ${SSH_LOGIN}@${ANSIBLE_SERVER_IP}:/etc/ansible/hosts

}

function UpdateAliases {

	# This updates Grig's alias file (and effectively replaces it)
	#   This can be commented out on a remote server
	echo "Changing ${MY_BASH_COMPLETION} ..."

	# Merge and sort uniq bash aliases
        cat ${MY_BASH_COMPLETION} ${MY_BASH_COMPLETION}.bak | sort | uniq > /tmp/.bash_alias_merge
	cp /tmp/.bash_alias_merge ${MY_BASH_COMPLETION}
	source ${MY_BASH_COMPLETION}

	# Wow, this was so lazy of me back when I had a separate ansible box.
	# cp ${MY_BASH_COMPLETION} /tmp/grig_bash
	# echo "alias excelsior=\"ssh glarson@10.10.71.61\"" >> /tmp/grig_bash
	# sed -i -e 's/ansible/glarson/g' /tmp/grig_bash
	# scp -q /tmp/grig_bash ${GRIG_BASH_COMPLETION}:/home/greg/.bash_aliases

}

function UpdateWebsite {

	BASENAME_CSV=$(basename ${OUTPUT_CSV})
	rm -f ${CURRENT_LINK}
	ln -s ${OUTPUT_CSV} ${CURRENT_LINK}

	echo "Seexamplcong updated web pages to inventory.examplco.org..."
	cat ${HTML_FOOTER} >> ${HTML_FILE}
	scp -i ${ANSIBLE_KEY} ${OUTPUT_CSV} ${SSH_LOGIN}@10.50.33.58:/var/www/html/inventory_csv
	scp -i ${ANSIBLE_KEY} ${HTML_FILE} ${SSH_LOGIN}@10.50.33.58:/var/www/html/index.html
	${SSH_COMMAND} ${SSH_LOGIN}@10.50.33.58 'rm -f /var/www/html/inventory_csv/current.csv'
	${SSH_COMMAND} ${SSH_LOGIN}@10.50.33.58 'ln -s /var/www/html/inventory_csv/'${BASENAME_CSV}' /var/www/html/inventory_csv/current.csv'


}

######################################
# Main function of the script
#####################################
ZeroFiles

# Our two profiles store in ~/.aws/config
# for AWS_SCRIPT_PROFILE in examplco examplcotech
for AWS_SCRIPT_PROFILE in example-company 
do
	export AWS_DEFAULT_PROFILE=${AWS_SCRIPT_PROFILE}
	GetInventory
done	

# WriteAnsibleHosts
# UpdateWebsite

echo "Finished!"
exit 0

######################################
# JSON Reference after this, no code:

# eg:
# aws ec2 describe-instances --instance-ids ${INSTANCE_LINE} --output json | jq -r '.Reservations[].Instances[].State.Name'
# running

 
#ansible@EXAMPLE-COL-GLARSON:~$ aws ec2 describe-instances --instance-ids i-b2f23a48 --output json | jq -r 
#{
#  "Reservations": [
#    {
#      "OwnerId": "770402430649",
#      "ReservationId": "r-c3570428",
#      "Groups": [
#        {
#          "GroupName": "EC2-DB-SVR",
#          "GroupId": "sg-fb4a9a90"
#        }
#      ],
#      "Instances": [
#        {
#          "Monitoring": {
#            "State": "disabled"
#          },
#          "PublicDnsName": "ec2-54-243-228-214.compute-1.amazonaws.com",
#          "RootDeviceType": "ebs",
#          "State": {
#            "Code": 16,
#            "Name": "running"
#          },
#          "EbsOptimized": false,
#          "LaunchTime": "2015-02-06T17:33:55.000Z",
#          "PublicIpAddress": "54.243.228.214",
#          "PrivateIpAddress": "10.169.117.156",
#          "ProductCodes": [],
#          "StateTransitionReason": "",
#          "InstanceId": "i-b2f23a48",
#          "ImageId": "ami-58632c30",
#          "PrivateDnsName": "ip-10-169-117-156.ec2.internal",
#          "KeyName": "EXAMPLE-CO_EC2_KPAIR",
#          "SecurityGroups": [
#            {
#              "GroupName": "EC2-DB-SVR",
#              "GroupId": "sg-fb4a9a90"
#            }
#          ],
#          "ClientToken": "XXPfO1423244035495",
#          "InstanceType": "m3.large",
#          "NetworkInterfaces": [],
#          "Placement": {
#            "Tenancy": "default",
#            "GroupName": "",
#            "AvailabilityZone": "us-east-1d"
#          },
#          "Hypervisor": "xen",
#          "BlockDeviceMappings": [
