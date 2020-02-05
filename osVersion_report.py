#!/usr/bin/env python3
# I had a job where we had some very outdated ec2 instances, and I had to generate a report where I showed which ones
#   were which version of Ubuntu on a regular basis.

import boto3
import time
import subprocess
from datetime import datetime

private_key_location="~/.ssh/ansible_id_rsa"
login_name="ansible"
ssh_options="ConnectTimeout=5 -o StrictHostKeyChecking=no"

ubuntu1204="\
=============================\
Ubuntu 12.04 - EOL April 2017\
-----------------------------\
"

ubuntu1404="\
=============================\
Ubuntu 14.04 - EOL April 2019\
-----------------------------\
"

ubuntu1604="\
=============================\
Ubuntu 16.04 - EOL April 2021\
-----------------------------\
"

ubuntu1804="\
=============================\
Ubuntu 18.04 - EOL April 2023\
-----------------------------\
"

unknown_running="\
===============================\
Unknown Linux version - running\
-------------------------------\
"

unknown_stopped="\
===============================\
Unknown Linux version - stopped\
-------------------------------\
"

# List of machines we don't want to poll for whatever reason
exceptions = {
              "10.2.6.101":"jsmith-testing",
              "10.2.000.000":"As a reminder, last one ends with no comma"
             }

ec2 = boto3.resource('ec2')
instances = ec2.instances.filter(Filters=[])
for instance in instances:

  tags = instance.tags or []
  names = [tag.get('Value') for tag in tags if tag.get('Key') == 'Name']
  if names is None or instance.state[ "Name" ] == "terminated":
    name = "Unknown"
  else: 
    name = names[0]

  # We had hundreds of auto-scaling and spot instances that did NOT need inventoried.
  if not name.startswith('autoscaling') and \
    name != 'production-drone-' and \
    name != 'production-mp3scrubber':

    # If the ip address started with 10.2.x.x, it was reachable from the ansible server.
    #   Otherwise, it was reachable from the external IP.
    if instance.private_ip_address is None: 
      ansible_ip=""
    elif instance.private_ip_address.startswith('10.2'):
      ansible_ip=instance.private_ip_address
    else:
      ansible_ip=instance.public_ip_address

    try:
      exception_value=exceptions[ansible_ip]
    except KeyError:
      if instance.state[ "Name" ] == 'running':
        # We want to ssh into this box and try and see what the distribution is
        ssh_stdout=subprocess.getstatusoutput("ssh -q -i {} -o {} {}@{} 'lsb_release -ds'".format(private_key_location,ssh_options,login_name,ansible_ip))
        result=ssh_stdout[1]
        if ssh_stdout[0] != 0: result = "Unknown"  # Best guess
        result = result.strip('\"')
        # if ssh_stdout[0] != 0: result = "Connect error"
        print('{0},{1},{2},{3},{4},'.format(instance.id, name, instance.state[ "Name" ],ansible_ip, result))

      elif instance.state[ "Name" ] == 'stopped':
        result="Unknown"
        print('{0},{1},{2},{3},{4},'.format(instance.id, name, instance.state[ "Name" ],ansible_ip,result))

      else:
        result="Unknown"
        print('{0},{1},{2},{3},{4},'.format(instance.id, name, instance.state[ "Name" ],ansible_ip,result))
