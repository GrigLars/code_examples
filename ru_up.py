#!/usr/bin/env python
# This gets api keys
import boto3
import time
# import pprint
import commands
from datetime import datetime

# pp = pprint.PrettyPrinter(indent=4).pprint

private_key_location="/home/glarson/.ssh/devops.pem"
login_name="ubuntu"
ssh_options="ConnectTimeout=5 -o StrictHostKeyChecking=no"

exceptions = {
              "192.168.48.8":"Windows box",
              "192.168.48.6":"Windows box",
              "192.168.48.7":"Windows box",
              "192.168.18.81":"Windows box",
              "192.168.10.107":"Windows box",
              "192.168.1.12":"Windows box",
              "192.168.8.13":"Windows box",
              "192.168.2.83":"Custom Redhat Box",
              "192.168.4.75":"Custom Redhat Box",
              "192.168.7.69":"FreeBSD",
              "192.168.3.12":"FreeBSD"
             }

print '{0:19} {1:30} {2:8} {3:15} {4:}'.format("Instance ID", "Name", "State", "Private IP", "Uptime")

# FOR RUNNING LOCALLY:
ec2 = boto3.resource('ec2')

instances = ec2.instances.filter(Filters=[])
for instance in instances:

  tags = instance.tags or []
  names = [tag.get('Value') for tag in tags if tag.get('Key') == 'Name']
  name = names[0] if names else None

  try:
    exception_value=exceptions[instance.private_ip_address]
    print '{0:19} {1:30} {2:8} {3:15} {4:}'.format(instance.id, name, instance.state[ "Name" ],instance.private_ip_address, exception_value)    
  except KeyError:
    if instance.state[ "Name" ] == 'running':
      ssh_stdout=commands.getstatusoutput("ssh -q -i {} -o {} {}@{} 'uptime'".format(private_key_location,ssh_options,login_name,instance.private_ip_address))
      result=ssh_stdout[1]
      if ssh_stdout[0] != 0: result = "Connect error"
      print '{0:19} {1:30} {2:8} {3:15} {4:}'.format(instance.id, name, instance.state[ "Name" ],instance.private_ip_address, result)
    else:
      print '{0:19} {1:30} {2:8} {3:15} {4:}'.format(instance.id, name, instance.state[ "Name" ],instance.private_ip_address,instance.state[ "Name" ])

# Example output
# Instance ID         Name                           State    Private IP      Uptime
# i-e57b5849          v2-interface                   running  192.168.4.225   18:06:53 up 18 days, 17:01,  0 users,  load average: 0.00, 0.01, 0.05
# i-9b4e6d37          v1-interface                   running  192.168.107     18:06:53 up 18 days, 17:01,  0 users,  load average: 0.00, 0.01, 0.05
# i-9d1d3b3d          test-interface                 stopped  192.168.5.235   stopped
# i-30b09e81          adc1                           running  192.168.1.12    Windows box
# i-0c30cdbc          openvpn                        running  192.168.7.69    FreeBSD
# i-0be3fd837192d3e05 sas-oa                         running  192.168.192.8   Custom Redhat Box
# i-06f64bf64a06e6700 db-dev                         running  10.0.0.12       18:06:54 up 18 days, 17:02,  0 users,  load average: 1.49, 1.96, 2.06
# i-0a2376e63e6b0de94 eks-1                          running  10.7.3.4        Connect error
# i-03c3e49008bcef810 eks-1                          running  10.7.3.17       Connect error
# i-0530c679efb1620ce adc2                           running  192.168.8.13    Windows box
# i-0659cb46fb6614db2 ManageEngine-shared            running  192.168.10.107  Windows box

