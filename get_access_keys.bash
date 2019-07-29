#!/bin/bash
# set -x

# Here is something that checks how old a key is without using boto3 (I did not have 
#  boto3 or python on this particular jump terminal system), then reports in csv format
#  if there are over 180 days old (in this particular case, see right below).

DAYS_OLD_LIMIT=179

export HOME=/home/glarson
AWS_COMMAND="/home/glarson/.local/bin/aws"
TODAYSDATE=$(date +%Y-%m-%d)
declare -A ACCESSKEYID_ARRAY
echo "Username,AccessKeyID,CreateDate,Daysold,KeyStatus"
for USERNAME in $(${AWS_COMMAND} iam list-users | jq -r '.Users[] | .UserName'); do

  # This can be returned as more than one result
  ACCESSKEYID_ARRAY=$(${AWS_COMMAND} iam list-access-keys --user-name ${USERNAME} | jq -r '.AccessKeyMetadata[] | .AccessKeyId')

  for ACCESSKEYID in ${ACCESSKEYID_ARRAY}; do
    if [ ${ACCESSKEYID} ]; then 
      # ${AWS_COMMAND} iam list-access-keys --user-name ${USERNAME} | jq -r '.AccessKeyMetadata[] | .CreateDate + " " + .AccessKeyId' | grep ${ACCESSKEYID}
      CREATEDATE=$(${AWS_COMMAND} iam list-access-keys --user-name ${USERNAME} | jq -r '.AccessKeyMetadata[] | .CreateDate + " " + .AccessKeyId' | grep ${ACCESSKEYID}) 
      CREATEDATE=${CREATEDATE:0:10}
      KEYDAYSOLD=$(echo $(( ($(date --date="${TODAYSDATE}" +%s) - $(date --date="${CREATEDATE}" +%s) )/(60*60*24) )))
      KEYSTATUS=$(${AWS_COMMAND} iam list-access-keys --user-name ${USERNAME} | jq -r '.AccessKeyMetadata[] | .Status + " " + .AccessKeyId' | grep ${ACCESSKEYID})
      KEYSTATUS=${KEYSTATUS:0:5}
      ACCESSKEYID=${ACCESSKEYID}
      if [ ${KEYDAYSOLD} -gt ${DAYS_OLD_LIMIT} ]; then
        echo "${USERNAME},${ACCESSKEYID},${CREATEDATE},${KEYDAYSOLD},(${KEYSTATUS})"
      fi
    else 
      echo "${USERNAME},[no AccessKeyID],n/a,n/a"
    fi
  
  done
done

exit 0
