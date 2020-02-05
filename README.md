# Examples of my code style

Often, employers want to know my code examples.  Here are some of them.  I am great at debugging code or applications, although I would not consider myself a "master programmer," at this time.  I like and do much better with Linux system administraion, but in the Linux world, you also have to know how to do basic programing and now the DevOps roles certainly demand it.  I prefer to use git and save my scripts or yaml files that way. As of this writing (2019), I am working on polishing up my python3 skills.  All of this was my own code from the ground up, not scripts I found somewhere and altered.

## aws_report.bash
A bash script, a mostrous AWS report which dumps multiple spreadsheets and pushes data to a web page.

## backup_report_linux.pl
An example of perl.  I had to take a data dump of the Netbackup status, and create a report sorted by service type that was parsed and used with our scripts.  I know, I know.  Nobody uses perl anymore.  I am sure this wouldn't run now, but it was the bee's knees when I needed to send customers reports on how much backup space they were taking up 9and could be billed overages).

## backup_report_by_service.pl
An example of perl.  I had to take a data dump of the Netbackup status via a Windows box, and create a report sorted by service type.  Similar to above.

## check_drive_encryption.py
Python that checks my AWS EC2 instances to see if the drive is encrypted or not.  This was part of our HIPAA compliance.

## get_access_keys.bash
Bash script that reports outdated AWS API keys 

## osVersion_report.py
Python report on AWS instances and what version of OS they were.

## postfix_bounced_mail.bash
Bash script that scans your postfix logs, looks for bounced or discarded mails, and filters them out from being sent again.  This is helpful when you need a good sender reputation.

## ru_up.py
Small python that checks to see what instances are up, and if it can't ssh into them, throw a reason why.  We did this after monthly
maintenance

## vmware-netfix.bash: 
Huge bash self-configuration setup. A while ago, I worked for a company that had VMWare images that needed to set themselves on the proper network, and identify themselves with banners, settings, and so on based on their network identity.  This is a bash program I am proud of, even if by now, it's a little outdated as far as need.
