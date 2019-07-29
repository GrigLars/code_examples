#!/usr/bin/env python
# This script is to check all the EC2 instances we have for a drive that is NOT encrypted (thus, potentially
#   violating HIPAA requirements)

import boto3
import time
import commands
from datetime import datetime

# FOR RUNNIG LOCALLY:
ec2 = boto3.resource('ec2')

instances = ec2.instances.filter(Filters=[])
for instance in instances:
  volumes = [v for v in instance.volumes.all()]
  tags = instance.tags or []
  names = [tag.get('Value') for tag in tags if tag.get('Key') == 'Name']
  name = names[0] if names else None
  
  if volumes:
    for volname in volumes:    
      if volname.encrypted:
        volume_encrypted = volname.encrypted
	vol_attachments = volname.attachments
        device_name = vol_attachments[0] 
        # print '{0:30} {1:8} is encrypted '.format(name,device_name.items()[5][1])
      else:
        print '{0:30} {1:8} is not encrypted'.format(name,device_name.items()[5][1])

# Output looks like:

# aws-test-interface             /dev/sda1 is not encrypted
# adc1                           xvdf     is not encrypted
# openvpn-shared                 xvdf     is not encrypted
# sas-oa-shared                  /dev/sdg is not encrypted
# adc2                           xvdf     is not encrypted
# ManageEngine-shared            xvdf     is not encrypted
# sas                            /dev/sdh is not encrypted
# internal-fake-vpn-test         /dev/xvda is not encrypted
# airflowtest-dev                /dev/sda1 is not encrypted
# winjump-shared                 xvdb     is not encrypted
# strongswan-interface           /dev/sda1 is not encrypted
# generic-qa                     /dev/sda1 is not encrypted
# docker2-prod                   /dev/sda1 is not encrypted
# flask-test-prod                /dev/sda1 is not encrypted
