#!/usr/bin/env bash
# This script is for when you take over an existing Linux server and need to know if there are any active
#   cron jobs going on.

# check cron job, vixiecron
echo "==[ /etc/crontab ]=="
grep -v "^#\|^$" /etc/crontab
echo ""

# Any active jobs in the timed directories
for CRONJOB in hourly daily weekly monthly; do
	echo "==[ Cron directory cron.${CRONJOB}>"
	ls -al /etc/cron.${CRONJOB}
echo ""
done

# Any active jobs in the cron.d directory
echo "==[ /etc/cron.d/ directory ]=="
for CRONJOB in /etc/cron.d/*; do
	echo "# ${CRONJOB}:" ; grep -v "^#\|^$" ${CRONJOB} 
done
echo ""

# Any cron jobs in user crontabs
echo "==[ User Crontabs ]=="
	for foo in /var/spool/cron/crontabs/*; do 
	echo "# User Crontab $foo>"; 
	grep -v "^#\|^$" $foo
echo ""
done
