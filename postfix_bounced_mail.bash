#!/usr/bin/env bash

# I worked in a place that had the customer set up alerts to be sent to their phone via SMS/MMS and email. 
#   Some customers were sending way too many alerts from multiple appliances, like 8-9/minute or more, and
#   many of them either just junked them, or forgot about them, and then the emails got canceled.  In any
#   case, large email sites like Gmail or Verizon, along with those who used email filtering services 
#   would send our sender reputation down.  We looked like a spammer because we would send a lot of mail
#   to a single address that didn't exist or didn't read them. So I needed a way to filter out all bounced
#   emails automatically.

# Run via /bin/bash /root/mail_bounced.bash | mail -s "Bounced and Discarded mail on $(hostname) on $(date)" ${mail_add} -r no-reply@example.com
#
# This was used alongside pflogsumm: http://jimsun.linxnet.com/postfix_contrib.html and run daily

mail_log_path="/var/log/mail.log"

echo "Bounced mail report for ${HOSTNAME}"
echo "=========================================="
echo ""

echo ""'Gmail reporting "Over quota":'
sudo grep 'OverQuotaTemp' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
echo ""

echo ""'Gmail reporting "Disabled User":'
sudo grep  'DisabledUser' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
echo ""

echo ""'Outlook365 reporting "Access denied":'
sudo grep 'Access denied' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
echo ""

echo ""'Text messaging reporting "Text message exceeds fixed limit":'
sudo grep 'Message size exceeds fixed limit' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'exceeds size limit' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'nternal error AUP#1270' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
echo ""

echo ""'Mail service Reporting "No Such User": '
sudo grep 'NoSuchUser' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'Email address could not be found' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'User unknown' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'Not our Customer' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'recipient does not exist' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 't have a yahoo.com account' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 't have a aol.com account' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'x.co/irbounce' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'Email address could not be found' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'mailbox unavailable' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep '550-Invalid recipient' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'DisabledUser' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
echo ""

echo ""'Recipient Mailbox rejecting - unknown reason:'
sudo grep 'community.mimecast.com' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'Relaying denied' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'RBL 521' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep '554-gmx.net' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
sudo grep 'mail.live.com/mail/troubleshooting.asp' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
echo ""

echo ""'Recipient domain not found or to MX replying at that address'
sudo grep 'Host not found' ${mail_log_path} | awk '{print $7}' | grep 'to=' | sort | uniq -c | sort -rn
echo ""

echo ""'Mail that is bouncing:'
sudo grep status=bounced /var/log/mail.log | awk '{print $7}' | sort | uniq -c | sort -rn
echo ""
echo ""'Mail that is still being discarded:'
sudo grep postfix/discard /var/log/mail.log | awk '{print $7}' | sort | uniq -c | sort -rn
echo ""
echo "==========[ End of report ]============"

TEMP_TRANSPORT="/tmp/transport"

# This takes all the "discarded" emails already on the transport list STILL showing up in the logs
# then adding the new ones bouncing that are NOT being discarded yet.

# Header of the transport file
echo "# I am having these rerouted for now, since they are more accepted
# when sent from the old mailserver
# [some email address] smtp:[other postfix server]
# [some other email address] smtp:[other postfix server]
# The rest of these are blocked because they bounced too many times
#   and it's affecting our sender reputation.
" > ${TEMP_TRANSPORT}

for foo in $(sudo grep "postfix/discard\|status=bounced" /var/log/mail.log | awk '{print $7}' | sort | uniq -c | sort -rn | awk -F "<|>" '{print $2}')
    do echo -e "$foo discard:" >> ${TEMP_TRANSPORT}
done

# Copy over the temp file to the transport file, re-run postmap, and reload the mail server.  In main.cf, you need
#   transport_maps = hash:/etc/postfix/transport
# See http://www.postfix.org/transport.5.html

cp ${TEMP_TRANSPORT} /etc/postfix/transport
postmap /etc/postfix/transport
systemctl reload postfix 
