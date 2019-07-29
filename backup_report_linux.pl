#!/usr/bin/perl
#
# [   [  [ [[ BACKUP REPORT GENERATOR ]] ]  ]   ]
#
# written by Grig Larson, 2005, for Example Company, Inc.
#

# 2007-05-10: Due to Veritas fucking up perli on STEL10,
#             I had to resort to doing this from the
#	      backup report server, which is probably just 
#             as well.

# 2009-09-24: Added "PC-X64" to clients list when we added
#	      exchange.exampleco.net.

use strict;
use POSIX qw(strftime);
use CGI ':standard';
use DBI;
use Mail::Sender;

	my $report_output_directory='/home/backup_user/backup_report/';
	
	my $daily_date=strftime("%d",localtime);
        # WIN # my $html_report_name=$report_output_directory.$daily_date."_backup_report.html";

	my $html_report_name=$report_output_directory.$daily_date."_backup_report.html";

	our $bpclclients_output_file='/home/backup_user/upload/bpclclients_output.txt';
	my $backstat_output_file='/home/backup_user/upload/backstat_output.txt';
	my $bpreport_output_file='/home/backup_user/upload/bpreport_output.txt';

# Some lovely variables...
  my %client_by_OS=qw();
  my %client_by_bpID=qw();
  my %client_by_policy=qw();
  my %client_by_schedlabel=qw();
  my %client_by_retention_label=qw();
  my %client_by_elapsed_time=qw();
  my %client_by_size_gb=qw();
  my %client_by_number_of_fragments=qw();
  my %client_by_number_of_files=qw();
  my %client_total_size_GB=qw();
  my %client_exit_status=qw();
  my %client_exception_reason=qw();

  my $percent_free=qw();
  my $extra_mail_alert=qw();
  my %veritas_errorcode=qw();
  my $customer_backup_export='/home/backup_user/config/customer_backup_export.txt';
  my $exception_list='/home/backup_user/config/exceptions.txt';
  my $disk_stats=qw();

# [0] = Disk used
# [1] = total space
# [2] = Space free
# [3] = Hashbar
# [4] = Percent free
# [5] = Warnings or notes

# my @foo = GetFreeSpaceGB('/home/backup_user/upload/diskfree_f.txt');
# print "Disk Used: $foo[3] $foo[2]gb of $foo[1]gb unused, $foo[4]\% free $foo[5]\n";


# Start the preparations
  MatchErrorCodes();
  Generate_Client_List();
  Populate_Client_Data();
  Create_HTML_Report_Header();
  WriteToCustomerExportFile();

# Create the data and send it to the tables.  Please note that I have selected
# "%client_by_OS" as the basis of listing all the backup policies.  This is
#  because this is the only list which will have ALL backup policies.  The rest
#  only have policies that *succeeded.*  Note this will also list the ones in
#  "Suspended," but doesn't assign them a Policy because they never run

my $key=qw(); # "$key" being blahblah.exampleco.backup or whatever
foreach $key (sort keys %client_by_OS) {
  $client_total_size_GB{$key}=GetTotalDiskSpaceBackupUsingGB($key);
  $client_exit_status{$key}=GetExitStatus($key);

  # If the $client_exit_statusin an X and policy is blank, then
  #  change the policy to "Suspended"
  if ($client_exit_status{$key} eq "X" && $client_by_policy{$key} eq "") {
    $client_by_policy{$key}="Suspended";
  }

  Create_HTML_Report_Row(
                          $key,
                          $client_exit_status{$key},
                          $client_by_OS{$key},
                          $client_by_policy{$key},
                          $client_by_bpID{$key},
                          $client_by_schedlabel{$key},
                          $client_by_retention_label{$key},
                          $client_by_elapsed_time{$key},
                          $client_by_number_of_fragments{$key},
                          $client_by_number_of_files{$key},
                          $client_by_size_gb{$key},
                          $client_total_size_GB{$key},
                          );
  my $what_customer_sees_as_OS=qw();
  if ($client_by_OS{$key} =~ m/RedHat/) {
    $what_customer_sees_as_OS="Linux";
  }
  elsif ($client_by_OS{$key} =~ m/FreeBSD/) {
    $what_customer_sees_as_OS="FreeBSD";
  }
  elsif ($client_by_OS{$key} =~ m/WindowsNET/) {
    $what_customer_sees_as_OS="Windows2003";
  }
  else {
   $what_customer_sees_as_OS=$client_by_OS{$key};
  }

  WriteToCustomerExportFile(
                          $key,
                          $client_exit_status{$key},
                          $what_customer_sees_as_OS,
                          $client_by_policy{$key},
                          $client_by_bpID{$key},
                          $client_by_schedlabel{$key},
                          $client_by_retention_label{$key},
                          $client_by_elapsed_time{$key},
                          $client_by_number_of_fragments{$key},
                          $client_by_number_of_files{$key},
                          $client_by_size_gb{$key},
                          $client_total_size_GB{$key},
                          );
  ExportToDatabase(
                  $key,
                  $client_by_elapsed_time{$key},
                  $client_by_number_of_fragments{$key},
                  $client_by_number_of_files{$key},
                  $client_by_size_gb{$key},
                  $client_total_size_GB{$key},
                  $client_by_policy{$key},
                  $client_by_schedlabel{$key},
                  );
}

# if ($percent_free < 10) {
#  $extra_mail_alert=$extra_mail_alert."! F:\\ has less than 10\% free space!";
# }

Create_HTML_Report_Footer();

MailAdminReport($extra_mail_alert);


#---------------------------------------
### ONLY SUBROUTINES BELOW THIS LINE ###
#---------------------------------------

sub Generate_Client_List {
  # This goes through the client listing and assigns the OS Type
  #  to the client ID
  my $client_record=qw();
  my @clients=qw();
  open (BPCLIENTLIST, $bpclclients_output_file);

    while ($client_record=<BPCLIENTLIST>) {
     chomp $client_record;
     @clients=split / +/,$client_record;
     $clients[0]=uc($clients[0]);

     # There's only two options here currently, "PC" for Windows
     #  or "INTEL" for Linux/BSD, all the rest are extraneous.  If
     #  you have some new type down the road, like "SOLARIS" or
     #  something not appearing in the reports, it's because of here.

     if ($clients[0] eq "PC" || $clients[0] eq "INTEL" || $clients[0] eq "LINUX" || $clients[0] eq "PC-X64") {
        # print "$clients[0],$clients[1],$clients[2]\n";
        $client_by_OS{$clients[2]}= $clients[1];
        }
     }
  close (BPCLIENTLIST);
}

sub Populate_Client_Data {
#  This grabs from the HUGE backup report, and grabs data from there.
#  The entire report is sparated by a blank line and then the
#   like that begins with "Client:"

  my $client_data=qw();
  my $client_ID=qw();
  my $backup_ID=qw();
  my $policy_ID=qw();
  my $sched_label=qw();
  my $retention_level=qw();
  my $backup_time=qw();
  my $elapsed_time=qw();
  my $expiration_time=qw();
  my $kilobytes=qw();
  my $number_of_files=qw();
  my $number_of_fragments=qw();  # Each fragment is max 2gb
  my @clients=qw();

  open (BPREPORT, $bpreport_output_file);

    while ($client_data = <BPREPORT>) {
     chomp $client_data; # Ah, yes... MS text formatting strikes again.
    @clients = split / +/,$client_data;
      if ($clients[0] eq "") {
    # If it encounterfs a blank line, then zero it all out
			$client_ID=qw();
			$backup_ID=qw();
			$policy_ID=qw();
			$sched_label=qw();
			$retention_level=qw();
			$backup_time=qw();
			$elapsed_time=qw();
			$expiration_time=qw();
			$kilobytes=qw();
			$number_of_files=qw();
			$number_of_fragments=qw();
      }
      elsif ($clients[0] eq "Client:") {
        #  Next, it should find "Client:"
        $client_ID=$clients[1];
         # print "Client:$clients[1]\n";
      }
      elsif ($clients[0] eq "Backup" && $clients[1] eq "ID:") {
        my @temp=split /_/,$clients[2];
        $client_by_bpID{$client_ID}= $temp[1];
	# print "Client_bpID:$client_by_bpID{$client_ID}\n";
      }
      elsif ($clients[0] eq "Policy:") {
        $client_by_policy{$client_ID}= $clients[1];
      }
      elsif ($clients[0] eq "Sched" && $clients[1] eq "Label:") {
        $client_by_schedlabel{$client_ID}= $clients[2];
      }
      elsif ($clients[0] eq "Retention" && $clients[1] eq "Level:") {
        $client_by_retention_label{$client_ID}= $clients[2].$clients[3];
      }
      elsif ($clients[0] eq "Backup" && $clients[1] eq "Time:") {
	# Changed with Version 6.5 (sorry)
        # $client_by_retention_label{$client_ID}= "$clients[3]-$clients[4]-$clients[5] $clients[6]";
        $client_by_retention_label{$client_ID}= "$clients[2] $clients[3] $clients[4]";
      }
      elsif ($clients[0] eq "Elapsed" && $clients[1] eq "Time:") {
         $client_by_elapsed_time{$client_ID}= convert_seconds_to_hhmmss($clients[2]);
      }
      elsif ($clients[0] eq "Kilobytes:") {
        my $temp = ($clients[1]/1024/1024);
        $client_by_size_gb{$client_ID}= sprintf("%.2f",$temp);
      }
      elsif ($clients[0] eq "Number" && $clients[2] eq "Fragments:") {
        $client_by_number_of_fragments{$client_ID}= $clients[3];
      }
      elsif ($clients[0] eq "Number" && $clients[2] eq "Files:") {
        $client_by_number_of_files{$client_ID}= $clients[3];
      }
      else {
         print;
      }
    }
  close (BPREPORT);
}

sub convert_seconds_to_hhmmss {
# This reverses the polarity of the neutron flow

  my $hourz=int($_[0]/3600);
  my $leftover=$_[0] % 3600;
  my $minz=int($leftover/60);
  my $secz=int($leftover % 60);
  return sprintf ("%02d:%02d:%02d", $hourz,$minz,$secz)
}

sub Create_HTML_Report_Header {
# This sets the HTML header, makes it HTML compliant, puts in headers, and
#   sets the opening table.

   open (HTML, "> $html_report_name");
   my $iso_date=strftime("%Y-%m-%d",localtime);
   my $iso_time=strftime("%H:%M:%S",localtime);
   print HTML start_html(
                          -title=>"VERTAS BACKUP REPORT $iso_date",
                          -bgcolor=>'#FEFEFE',
                          );
   print HTML "<center><h3>VERTAS BACKUP REPORT $iso_date<\/h3>";
   # print HTML br();
   print HTML "created $iso_time on backup.exampleco.net<\/center>\n";
   print HTML p();
   my @disk_free_list_C=GetFreeSpaceGB("/home/backup_user/upload/diskfree_c.txt");
   my @disk_free_list_F=GetFreeSpaceGB("/home/backup_user/upload/diskfree_f.txt");   
   # my @disk_free_list_G=GetFreeSpaceGB("/home/backup_user/upload/diskfree_g.txt");

   open (DISKSTATS, "> /home/backup_user/upload/disk_stats.txt");
   $disk_stats="Disk Used on C: $disk_free_list_C[3] $disk_free_list_C[2]gb of $disk_free_list_C[1]gb unused, $disk_free_list_C[4]\% free $disk_free_list_C[5]\nDisk Used on F: $disk_free_list_F[3] $disk_free_list_F[2]gb of $disk_free_list_F[1]gb unused, $disk_free_list_F[4]\% free $disk_free_list_F[5]\n";

# Disk Used on G: $disk_free_list_G[3] $disk_free_list_G[2]gb of $disk_free_list_G[1]gb unused, $disk_free_list_G[4]\% free $disk_free_list_G[5]\n";

   print DISKSTATS $disk_stats;
   close (DISKSTATS);


   print HTML "\nDisk Used on C: <TT>$disk_free_list_C[3]</TT> $disk_free_list_C[2]gb of $disk_free_list_C[1]gb unused, <B>$disk_free_list_C[4]\% free</B> $disk_free_list_C[5]\n<BR>";
   print HTML "Disk Used on F: <TT>$disk_free_list_F[3]</TT> $disk_free_list_F[2]gb of $disk_free_list_F[1]gb unused, <B>$disk_free_list_F[4]\% free</B> $disk_free_list_F[5]\n<BR>";
   # print HTML "Disk Used on G: <TT>$disk_free_list_G[3]</TT> $disk_free_list_G[2]gb of $disk_free_list_G[1]gb unused, <B>$disk_free_list_G[4]\% free</B> $disk_free_list_G[5]\n<BR>";
 
   print HTML p();
   print HTML "<TABLE BGCOLOR=\"\#D7EBFF\" width=100\% border=0>\n";
   print HTML "<TR bgcolor=\"\#C6DAEE\">
                \t<TD><B>Customer<\/B><\/TD>\n
                \t<TD><B>Status<\/B><\/TD>\n
                \t<TD><B>OS<\/B><\/TD>\n
                \t<TD><B>Policy<\/B><\/TD>\n
                \t<TD><B>Backup ID<\/B><\/TD>\n
                \t<TD><B>Type<\/B><\/TD>\n
                \t<TD><B>Start<\/B><\/TD>\n
                \t<TD><B>Elapsed<\/B><\/TD>\n
                \t<TD align=right><B>#Frg<\/B><\/TD>\n
                \t<TD align=right><B>#Files<\/B><\/TD>\n
                \t<TD align=right><B>SizeGB<\/B><\/TD>\n
                \t<TD align=right><B>TotalGB<\/B><\/TD>\n
            ";

   close (HTML);
}

sub Create_HTML_Report_Row {
# This creates the "meat" of the table, populating it with data
#   the various tables are:

    # $_[0] = Netbackup Customer Name
    # $_[1] = Exit status (0=good, 1=OK, anything else... watch out!)
    # $_[2] = Operating System
    # $_[3] = Policy (UIX, Exampleco, etc)
    # $_[4] = Veritas backup ID (used for tracking)
    # $_[5] = Backup type (Daily, weekly, monthly, etc)
    # $_[6] = Date/Time of backup
    # $_[7] = How long the backup took HH:MM:SS
    # $_[8] = Number of fragments the backup takes (usually 2gb increments)
    # $_[9] = Number of files
    # $_[10] = Backup size GB (Total backup size)
    # $_[11] = Total used GB (Disk hog check)

    my $row_background_color=EvalBackupExit($_[0],$_[1]);

    my @table_row = ($_[0],$_[1],$_[2],$_[3],$_[4],$_[5],$_[6],$_[7],$_[8],$_[9],$_[10],$_[11]);
    open (HTML, ">> $html_report_name");
    print HTML "\n<TR bgcolor=\"$row_background_color\">\n";
    my $data=qw();

    foreach $data (@table_row){
    #  && $data ne "X" && $data ne "?"
      if ($data =~m/[A-z]/) {
        if ($data eq "Suspended") {
          print HTML "\t<TD><I>$data<\/I><\/TD>\n";
        }
        else {
          print HTML "\t<TD>$data<\/TD>\n";
        }
      }
      else {
      # I am fussy, I aligned numeric data to right-justify
        print HTML "\t<TD align=right>$data<\/TD>\n";
      }
    }


    print HTML "\n<\/TR>\n";
    close (HTML);
}

sub Create_HTML_Report_Footer {
# This is the end of the HTML report,
#   and makes it all HTML compliant and stuff.

   open (HTML, ">> $html_report_name");
   print HTML "<\/TABLE><P><HR><P> \n";
   print HTML "<TABLE bgcolor=\"\#FFFFFF\">\n<CAPTION><B><U>Summary of Errors, Warnings, and Exceptions<\/U><\/B><\/caption>\n<TR>\n<TD><PRE>\n";
   print HTML "$extra_mail_alert";
   print HTML "<\/PRE><\/TD><\/TR><\/TABLE>\n";
   print HTML end_html;
   close (HTML);
}

sub GetFreeSpaceGB {
# This gets total disk space by default, but "free" means
#   how much is free.  
# This was heavily modified in the Linux trasition: I use fsutil
#   on the box, and send it as a text file

# [0] = Disk used
# [1] = total space
# [2] = Space free
# [3] = Hashbar
# [4] = Percent free
# [5] = Warnings or notes

my @disk_stats=qw();
my $diskdata=qw();

open (DISKSTATFILE,$_[0]);
	while ($diskdata = <DISKSTATFILE>) {	
		chomp $diskdata;
		$diskdata=~ s/\s//g;
		my @diststat_dd=split/\:/,$diskdata;
		if ($diststat_dd[0] eq "Total#offreebytes") {
			$disk_stats[2]=$diststat_dd[1];			
		}
		elsif ($diststat_dd[0] eq "Total#ofbytes")  {
			$disk_stats[1]=$diststat_dd[1];
		}

	}

close (DISKSTATFILE);

$disk_stats[0]=$disk_stats[1] - $disk_stats[2];
$disk_stats[4]=int(($disk_stats[2]/$disk_stats[1])*1000)/10;
if ($disk_stats[4] < 10) {$disk_stats[5] = "** WARNING: DISK SPACE FREE IS LESS THAN 10%";}

my $total_hashmarks=25;
my $free_spaces=int($disk_stats[4]/4);
my $num_hashmarks=$total_hashmarks-$free_spaces;
$disk_stats[3]="["."\#" x $num_hashmarks. '_' x $free_spaces."]";

$disk_stats[0]=int($disk_stats[0]/ 1024 / 1024 / 1024 * 10)/10;
$disk_stats[1]=int($disk_stats[1]/ 1024 / 1024 / 1024 * 10)/10;
$disk_stats[2]=int($disk_stats[2]/ 1024 / 1024 / 1024 * 10)/10;

return @disk_stats;

}

sub GetTotalDiskSpaceBackupUsingGB {
# This gets total disk space used by any one client to see
#  who the disk hogs are
# WOW... I really had to do a kludge to export this to Linux
#  Thank you DOS! :(

my $file=qw();
my $space_in_bytes=0;

# print "Client asked for $_[0]:\n";
open (FILELIST, '/home/backup_user/upload/file_list_modified.txt');
	while ($file=<FILELIST>) {
	chomp $file;
	if ($file =~ m/$_[0]/) {
		# print "\t$file\t";
		my @fozzie_bear=split/\s/,$file;		
		$space_in_bytes=$space_in_bytes + $fozzie_bear[1];
		print "$space_in_bytes\n";
	}
	}
close (FILELIST);

my $space_in_gb=($space_in_bytes / 1024 / 1024 / 1024);
$space_in_gb= sprintf("%.2f", $space_in_gb);
return  $space_in_gb;

# ---------------------
#  my $space_in_bytes = qw();
#  my $drive = "F:\\";

#  opendir(DIR, $drive);
#    my @files = readdir(DIR);
#  closedir(DIR);

#  my $file=qw();
#  foreach $file (@files) {
#   if ($file =~ m/$_[0]/) {
#     $file=$drive.$file;
#     my @file_stats= stat $file;
#     $space_in_bytes=$space_in_bytes + $file_stats[7];
#   }
#  }
#    my $space_in_gb=($space_in_bytes / 1024 / 1024 / 1024);
#    $space_in_gb= sprintf("%.2f", $space_in_gb);
#    return  $space_in_gb;
}

sub GetExitStatus {
 # Sometimes there's more than one entry if the first run.  Maybe it just
 #  didn't work the first time, but was okay the second run; we want the
 #  output of the LAST entry from $backstat_output_file

  my $exit=qw();
  open (EXITSTATUS, $backstat_output_file);
  while (my $record=<EXITSTATUS>) {
    my @exit_stats=split / +/,$record;
    if ($exit_stats[8] eq $_[0]) {
      $exit=$exit_stats[18];
    }
   }
  close (EXITSTATUS);

  # What do we do if it's blank?  Well, we check for exceptions.
  if ($exit eq "") {
   $exit=CheckForExceptionsSuspensions($_[0]);
  }
  return $exit;
}

sub EvalBackupExit {
 # Right now, this just determines the color of the table row background
 #  but could be used a bit more intelligently later on

 if ($_[1] eq 0) {
  return "\#D7EBFF";
 }
 elsif ($_[1] eq 1) {
   $extra_mail_alert=$extra_mail_alert."? $_[0] reported success, but $veritas_errorcode{$_[1]}\n";
   return "\#FFFFB7";
 }
 elsif ($_[1] eq "X") {
   $extra_mail_alert=$extra_mail_alert."- $_[0] EXCEPTION: $client_exception_reason{$_[0]}\n";
   return "\#BBBBBB";
 }
 else {
  $extra_mail_alert=$extra_mail_alert."! $_[0] FAILED (error $_[1]: $veritas_errorcode{$_[1]})\n";
  return "\#FFC1C1";
 }
}

sub MailAdminReport {
# Mail out the admin report.
#  $_[0] would be any extra warning we decide to toss in.

  my $fortune_cookie=GetFortune();
  my $smtp_server="wsmtp.exampleco.net";
  my $iso_date=strftime("%Y-%m-%d",localtime);
  my $mail_subject="Daily Veritas Backup Report $iso_date";
  my $mail_body="Good morning,

This is the backup report from STEL10.  Please take a look at the attachment 
and check on anything in red.  Flip to hosting if anything is in red or
failed to work.

\[code\] $_[0] \[\/code\]

$disk_stats

$fortune_cookie

:: Signed,
:: backups.exampleco.net
--------------------------
:: \"Your plastic pal who\'s fun to be with.\"";

  my $sender = new Mail::Sender {smtp => 'wsmtp.exampleco.net',
                                 from => 'hosting@exampleco.net'};
  # $sender->MailFile({to => 'hosting@exampleco.net',
  #$sender->MailFile({to => 'hosting@exampleco.net,hfchou@exampleco.net',
  $sender->MailFile({to => 'support@exampleco.net',
                    # replyto => 'SystemAdministrators',
                    subject => $mail_subject,
                    msg => $mail_body,
                    file => $html_report_name}
                    );


}

sub GetFortune {
	my $path_to_fortune='/usr/bin/fortune -s';
	my $fortune=`$path_to_fortune`;
        return $fortune

}

sub WriteToCustomerExportFile {
# This wites a CSV file that the customer report will use later
# print "@_\n";
 if ($_[0] eq "") {
  # A blank means clear out the file
  open (CUSTOMEREXPORT, "> $customer_backup_export");
  close (CUSTOMEREXPORT);
 }
 else {
  open (CUSTOMEREXPORT, ">> $customer_backup_export");
  my $exportline = join ',',@_;
  print CUSTOMEREXPORT "$exportline\n";
  close (CUSTOMEREXPORT);
 }
}

sub CheckForExceptionsSuspensions {
 #$_[0] is the CustomerID
 my $record=qw();
 my $exception_value=qw();
 my @except=qw();

 # Check the exception list
 open (EXCEPTION, $exception_list);
  while ($record=<EXCEPTION>) {
    chomp $record;
    if ($record =~ m/^[^\#]/) {
      @except= split /=/,$record;
      if ($except[0] eq $_[0]) {
        $exception_value="X";
        $client_exception_reason{$_[0]}=$except[1];
      }
    }
  }
 close (EXCEPTION);

 # If we still don't know why, return "?"
 if ($exception_value eq "") {
  $exception_value="?";
  $client_exception_reason{$_[0]}="Unknown - please check";
 }

 return $exception_value;
}

sub ExportToDatabase {
# This right now writes to a text file, but one I get a database set up, it
#  will directly export to it.

# $_[0] =  clientID
# $_[1] =  elapsed time of backup
# $_[2] =  number of backup fragments
# $_[3] =  number of files backed up
# $_[4] =  GB of current backup
# $_[5] =  GB of Total backups for that clientID
# $_[6] =  policy (UNIX-1, etc)
# $_[7] =  shedule label (Daily, weekly, monthly)

# Databese used to be at 209.190.220.102
  my @data_row =(@_);
  my $iso_date=strftime("%Y-%m-%d",localtime);
#  my $dbh = DBI->connect('dbi:mysql:backups:127.0.0.1',
#                        'backup_user',
#                        'back_me_up') or die "I couldn't connect to the database";

  my $dbh = DBI->connect('dbi:mysql:backups:localhost',
                        'backup_db_user',
                        '7i$j#ezl') or die "I couldn't connect to the MySQLDB1 database... oh noes!";


  # my $data_key="$iso_date\_$_[0]";
  my $datafile = $report_output_directory."\\config\\data_export.txt";
  # unshift @data_row, "$data_key, $iso_date";
  my $dataline = join ',', $iso_date, @data_row;

  # The Insert SQL statement
#   my $sql = "INSERT INTO backups (date, clientID, length, fragments, files, sizeGB, totalGB) VALUES ($iso_date, $_[0], $_[1], $_[2], $_[3], $_[4], $_[5])";
my $sql = "INSERT INTO backups VALUES (\'$iso_date\', \'$_[0]\', \'$_[1]\', \'$_[2]\', \'$_[3]\', \'$_[4]\', \'$_[5]\', \'$_[6]\', \'$_[7]\')";
  my $sth = $dbh->prepare($sql);

  open (DATAFILE, ">> $datafile");
  print DATAFILE "$dataline\n";
  close (DATAFILE);
  $sth->execute || die "Could not execute SQL statement ... maybe invalid?";
  $dbh->disconnect();
}

sub MatchErrorCodes {

# Matches error codes to descriptions, which is sort of helpful.  These were grep'd
#  from the Veritas Netbakcup 5.1 Troubleshooter's guide.

$veritas_errorcode{"0"}="the requested operation was successfully completed ";
$veritas_errorcode{"1"}="the requested operation was partially successful ";
$veritas_errorcode{"2"}="none of the requested files were backed up ";
$veritas_errorcode{"3"}="valid archive image produced, but no files deleted due to non-fatal problems ";
$veritas_errorcode{"4"}="archive file removal failed ";
$veritas_errorcode{"5"}="the restore failed to recover the requested files ";
$veritas_errorcode{"6"}="the backup failed to back up the requested files ";
$veritas_errorcode{"7"}="the archive failed to back up the requested files ";
$veritas_errorcode{"8"}="unable to determine the status of rbak";
$veritas_errorcode{"9"}="an extension package is needed, but was not installed";
$veritas_errorcode{"10"}="allocation failed ";
$veritas_errorcode{"11"}="system call failed ";
$veritas_errorcode{"12"}="file open failed ";
$veritas_errorcode{"13"}="file read failed ";
$veritas_errorcode{"14"}="file write failed ";
$veritas_errorcode{"15"}="file close failed ";
$veritas_errorcode{"16"}="unimplemented feature";
$veritas_errorcode{"17"}="pipe open failed";
$veritas_errorcode{"18"}="pipe close failed ";
$veritas_errorcode{"19"}="getservbyname failed ";
$veritas_errorcode{"20"}="invalid command parameter ";
$veritas_errorcode{"21"}="socket open failed";
$veritas_errorcode{"22"}="socket close failed ";
$veritas_errorcode{"23"}="socket read failed";
$veritas_errorcode{"24"}="socket write failed";
$veritas_errorcode{"25"}="cannot connect on socket ";
$veritas_errorcode{"26"}="client/server handshaking failed ";
$veritas_errorcode{"27"}="child process killed by signal ";
$veritas_errorcode{"28"}="failed trying to fork a process ";
$veritas_errorcode{"29"}="failed trying to exec a command ";
$veritas_errorcode{"30"}="could not get passwd information ";
$veritas_errorcode{"31"}="could not set user id for process ";
$veritas_errorcode{"32"}="could not set group id for process ";
$veritas_errorcode{"33"}="failed while trying to send mail ";
$veritas_errorcode{"34"}="failed waiting for child process";
$veritas_errorcode{"35"}="cannot make required directory";
$veritas_errorcode{"36"}="failed trying to allocate memory ";
$veritas_errorcode{"37"}="operation requested by an invalid server ";
$veritas_errorcode{"38"}="could not get group information ";
$veritas_errorcode{"39"}="client name mismatch ";
$veritas_errorcode{"40"}="network connection broken ";
$veritas_errorcode{"41"}="network connection timed out ";
$veritas_errorcode{"42"}="network read failed ";
$veritas_errorcode{"43"}="unexpected message received";
$veritas_errorcode{"44"}="network write failed ";
$veritas_errorcode{"45"}="request attempted on a non reserved port ";
$veritas_errorcode{"46"}="server not allowed access ";
$veritas_errorcode{"47"}="host is unreachable ";
$veritas_errorcode{"48"}="client hostname could not be found ";
$veritas_errorcode{"49"}="client did not start ";
$veritas_errorcode{"50"}="client process aborted ";
$veritas_errorcode{"51"}="timed out waiting for database information";
$veritas_errorcode{"52"}="timed out waiting for media manager to mount volume ";
$veritas_errorcode{"53"}="backup restore manager failed to read the file list ";
$veritas_errorcode{"54"}="timed out connecting to client ";
$veritas_errorcode{"55"}="permission denied by client during rcmd";
$veritas_errorcode{"56"}="client's network is unreachable ";
$veritas_errorcode{"57"}="client connection refused ";
$veritas_errorcode{"58"}="can't connect to client ";
$veritas_errorcode{"59"}="access to the client was not allowed ";
$veritas_errorcode{"60"}="client cannot read the mount table ";
$veritas_errorcode{"63"}="process was killed by a signal ";
$veritas_errorcode{"64"}="timed out waiting for the client backup to start ";
$veritas_errorcode{"65"}="client timed out waiting for the continue message from the media manager ";
$veritas_errorcode{"66"}="client backup failed to receive the CONTINUE BACKUP message ";
$veritas_errorcode{"67"}="client backup failed to read the file list ";
$veritas_errorcode{"68"}="client timed out waiting for the file list ";
$veritas_errorcode{"69"}="invalid filelist specification";
$veritas_errorcode{"70"}="an entry in the filelist expanded to too many characters ";
$veritas_errorcode{"71"}="none of the files in the file list exist ";
$veritas_errorcode{"72"}="the client type is incorrect in the configuration database ";
$veritas_errorcode{"73"}="bpstart_notify failed ";
$veritas_errorcode{"74"}="client timed out waiting for bpstart_notify to complete ";
$veritas_errorcode{"75"}="client timed out waiting for bpend_notify to complete ";
$veritas_errorcode{"76"}="client timed out reading file ";
$veritas_errorcode{"77"}="execution of the specified system command returned a nonzero status";
$veritas_errorcode{"78"}="afs/dfs command failed ";
$veritas_errorcode{"79"}="unsupported image format for the requested database query ";
$veritas_errorcode{"80"}="Media Manager device daemon (ltid) is not active ";
$veritas_errorcode{"81"}="Media Manager volume daemon (vmd) is not active ";
$veritas_errorcode{"82"}="media manager killed by signal ";
$veritas_errorcode{"83"}="media open error ";
$veritas_errorcode{"84"}="media write error ";
$veritas_errorcode{"85"}="media read error ";
$veritas_errorcode{"86"}="media position error ";
$veritas_errorcode{"87"}="media close error ";
$veritas_errorcode{"89"}="problems encountered during setup of shared memory ";
$veritas_errorcode{"90"}="media manager received no data for backup image ";
$veritas_errorcode{"91"}="fatal NB media database error ";
$veritas_errorcode{"92"}="media manager detected image that was not in tar format ";
$veritas_errorcode{"93"}="media manager found wrong tape in drive ";
$veritas_errorcode{"94"}="cannot position to correct image ";
$veritas_errorcode{"95"}="requested media id was not found in NB media database and/or MM volume database ";
$veritas_errorcode{"96"}="unable to allocate new media for backup, storage unit has none available ";
$veritas_errorcode{"97"}="requested media id is in use, cannot process request ";
$veritas_errorcode{"98"}="error requesting media (tpreq) ";
$veritas_errorcode{"99"}="NDMP backup failure ";
$veritas_errorcode{"100"}="system error occurred while processing user command";
$veritas_errorcode{"101"}="failed opening mail pipe ";
$veritas_errorcode{"102"}="failed closing mail pipe";
$veritas_errorcode{"103"}="error occurred during initialization, check configuration file";
$veritas_errorcode{"104"}="invalid file pathname ";
$veritas_errorcode{"105"}="file pathname exceeds the maximum length allowed ";
$veritas_errorcode{"106"}="invalid file pathname found, cannot process request ";
$veritas_errorcode{"109"}="invalid date specified ";
$veritas_errorcode{"110"}="Cannot find the NetBackup configuration information ";
$veritas_errorcode{"111"}="No entry was found in the server list ";
$veritas_errorcode{"112"}="no files specified in the file list";
$veritas_errorcode{"116"}="VxSS authentication failed ";
$veritas_errorcode{"117"}="VxSS access denied ";
$veritas_errorcode{"118"}="VxSS authorization failed ";
$veritas_errorcode{"120"}="cannot find configuration database record for requested NB database backup ";
$veritas_errorcode{"121"}="no media is defined for the requested NB database backup ";
$veritas_errorcode{"122"}="specified device path does not exist ";
$veritas_errorcode{"123"}="specified disk path is not a directory ";
$veritas_errorcode{"124"}="NB database backup failed, a path was not found or is inaccessible ";
$veritas_errorcode{"125"}="another NB database backup is already in progress";
$veritas_errorcode{"126"}="NB database backup header is too large, too many paths specified ";
$veritas_errorcode{"127"}="specified media or path does not contain a valid NB database backup header ";
$veritas_errorcode{"128"}="NB database recovery failed, a process has encountered an exceptional condition ";
$veritas_errorcode{"130"}="system error occurred ";
$veritas_errorcode{"131"}="client is not validated to use the server ";
$veritas_errorcode{"132"}="user is not validated to use the server from this client";
$veritas_errorcode{"133"}="invalid request ";
$veritas_errorcode{"134"}="unable to process request because the server resources are busy";
$veritas_errorcode{"135"}="client is not validated to perform the requested operation ";
$veritas_errorcode{"136"}="tir info was pruned from the image file ";
$veritas_errorcode{"140"}="user id was not superuser ";
$veritas_errorcode{"141"}="file path specified is not absolute";
$veritas_errorcode{"142"}="file does not exist ";
$veritas_errorcode{"143"}="invalid command protocol ";
$veritas_errorcode{"144"}="invalid command usage ";
$veritas_errorcode{"145"}="daemon is already running ";
$veritas_errorcode{"146"}="cannot get a bound socket ";
$veritas_errorcode{"147"}="required or specified copy was not found";
$veritas_errorcode{"148"}="daemon fork failed ";
$veritas_errorcode{"149"}="master server request failed";
$veritas_errorcode{"150"}="termination requested by administrator ";
$veritas_errorcode{"151"}="Backup Exec operation failed ";
$veritas_errorcode{"152"}="required value not set ";
$veritas_errorcode{"153"}="server is not the master server ";
$veritas_errorcode{"154"}="storage unit characteristics mismatched to request ";
$veritas_errorcode{"155"}="disk is full ";
$veritas_errorcode{"156"}="snapshot error encountered ";
$veritas_errorcode{"157"}="suspend requested by administrator ";
$veritas_errorcode{"158"}="failed accessing daemon lock file ";
$veritas_errorcode{"159"}="licensed use has been exceeded";
$veritas_errorcode{"160"}="authentication failed ";
$veritas_errorcode{"161"}="Evaluation software has expired. See www.veritas.com for ordering information ";
$veritas_errorcode{"162"}="incorrect server platform for license ";
$veritas_errorcode{"163"}="media block size changed prior to resume ";
$veritas_errorcode{"164"}="unable to mount media because it is in a DOWN drive, misplaced, or otherwise not available ";
$veritas_errorcode{"165"}="NB image database contains no image fragments for requested backup id/copy number ";
$veritas_errorcode{"166"}="backups are not allowed to span media ";
$veritas_errorcode{"167"}="cannot find requested volume pool in Media Manager volume database ";
$veritas_errorcode{"168"}="cannot overwrite media, data on it is protected ";
$veritas_errorcode{"169"}="media id is either expired or will exceed maximum mounts ";
$veritas_errorcode{"170"}="third party copy backup failure ";
$veritas_errorcode{"171"}="media id must be 6";
$veritas_errorcode{"172"}="cannot read media header, may not be NetBackup media or is corrupted ";
$veritas_errorcode{"173"}="cannot read backup header, media may be corrupted ";
$veritas_errorcode{"174"}="media manager - system error occurred ";
$veritas_errorcode{"175"}="not all requested files were restored ";
$veritas_errorcode{"176"}="cannot perform specified media import operation ";
$veritas_errorcode{"177"}="could not deassign media due to Media Manager error";
$veritas_errorcode{"178"}="media id is not in NetBackup volume pool ";
$veritas_errorcode{"179"}="density is incorrect for the media id ";
$veritas_errorcode{"180"}="tar was successful";
$veritas_errorcode{"181"}="tar received an invalid argument ";
$veritas_errorcode{"182"}="tar received an invalid file name";
$veritas_errorcode{"183"}="tar received an invalid archive";
$veritas_errorcode{"184"}="tar had an unexpected error ";
$veritas_errorcode{"185"}="tar did not find all the files to be restored";
$veritas_errorcode{"186"}="tar received no data ";
$veritas_errorcode{"189"}="the server is not allowed to write to the client's filesystems ";
$veritas_errorcode{"190"}="found no images or media matching the selection criteria";
$veritas_errorcode{"191"}="no images were successfully processed";
$veritas_errorcode{"192"}="VxSS authentication is required but not available ";
$veritas_errorcode{"193"}="VxSS authentication is requested but not allowed ";
$veritas_errorcode{"194"}="the maximum number of jobs per client is set to 0";
$veritas_errorcode{"195"}="client backup was not attempted ";
$veritas_errorcode{"196"}="client backup was not attempted because backup window closed ";
$veritas_errorcode{"197"}="the specified schedule does not exist in the specified policy ";
$veritas_errorcode{"198"}="no active policies contain schedules of the requested type for this client ";
$veritas_errorcode{"199"}="operation not allowed during this time period ";
$veritas_errorcode{"200"}="scheduler found no backups due to run ";
$veritas_errorcode{"201"}="handshaking failed with server backup restore manager ";
$veritas_errorcode{"202"}="timed out connecting to server backup restore manager ";
$veritas_errorcode{"203"}="server backup restore manager's network is unreachable";
$veritas_errorcode{"204"}="connection refused by server backup restore manager ";
$veritas_errorcode{"205"}="cannot connect to server backup restore manager ";
$veritas_errorcode{"206"}="access to server backup restore manager denied ";
$veritas_errorcode{"207"}="error obtaining date of last backup for client ";
$veritas_errorcode{"208"}="failed reading user directed filelist ";
$veritas_errorcode{"209"}="error creating or getting message queue ";
$veritas_errorcode{"210"}="error receiving information on message queue ";
$veritas_errorcode{"211"}="scheduler child killed by signal ";
$veritas_errorcode{"212"}="error sending information on message queue ";
$veritas_errorcode{"213"}="no storage units available for use ";
$veritas_errorcode{"214"}="regular bpsched is already running ";
$veritas_errorcode{"215"}="failed reading global config database information ";
$veritas_errorcode{"216"}="failed reading retention database information ";
$veritas_errorcode{"217"}="failed reading storage unit database information ";
$veritas_errorcode{"218"}="failed reading policy database information ";
$veritas_errorcode{"219"}="the required storage unit is unavailable ";
$veritas_errorcode{"220"}="database system error ";
$veritas_errorcode{"221"}="continue ";
$veritas_errorcode{"222"}="done ";
$veritas_errorcode{"223"}="an invalid entry was encountered ";
$veritas_errorcode{"224"}="there was a conflicting specification ";
$veritas_errorcode{"225"}="text exceeded allowed length ";
$veritas_errorcode{"226"}="the entity already exists ";
$veritas_errorcode{"227"}="no entity was found ";
$veritas_errorcode{"228"}="unable to process request ";
$veritas_errorcode{"229"}="events out of sequence - image inconsistency";
$veritas_errorcode{"230"}="the specified policy does not exist in the configuration database";
$veritas_errorcode{"231"}="schedule windows overlap ";
$veritas_errorcode{"232"}="a protocol error has occurred ";
$veritas_errorcode{"233"}="premature eof encountered ";
$veritas_errorcode{"234"}="communication interrupted ";
$veritas_errorcode{"235"}="inadequate buffer space ";
$veritas_errorcode{"236"}="the specified client does not exist in an active policy within the configuration database ";
$veritas_errorcode{"237"}="the specified schedule does not exist in an active policy in the configuration database ";
$veritas_errorcode{"238"}="the database contains conflicting or erroneous entries ";
$veritas_errorcode{"239"}="the specified client does not exist in the specified policy ";
$veritas_errorcode{"240"}="no schedules of the correct type exist in this policy ";
$veritas_errorcode{"241"}="the specified schedule is the wrong type for this request ";
$veritas_errorcode{"242"}="operation would cause an illegal duplication ";
$veritas_errorcode{"243"}="the client is not in the configuration ";
$veritas_errorcode{"244"}="main bpsched is already running ";
$veritas_errorcode{"245"}="the specified policy is not of the correct client type ";
$veritas_errorcode{"246"}="no active policies in the configuration database are of the correct client type ";
$veritas_errorcode{"247"}="the specified policy is not active";
$veritas_errorcode{"248"}="there are no active policies in the configuration database";
$veritas_errorcode{"249"}="the file list is incomplete ";
$veritas_errorcode{"250"}="the image was not created with TIR information";
$veritas_errorcode{"251"}="the tir information is zero length ";
$veritas_errorcode{"252"}="the error status has been written to stderr ";
$veritas_errorcode{"253"}="the catalog image .f file has been archived";
$veritas_errorcode{"254"}="server name not found in the NetBackup configuration";
$veritas_errorcode{"256"}="logic error encountered";
$veritas_errorcode{"257"}="cannot create log file ";
$veritas_errorcode{"258"}="a child process failed for an unknown reason";
$veritas_errorcode{"259"}="vault configuration file not found";
$veritas_errorcode{"260"}="vault internal error 260";
$veritas_errorcode{"261"}="vault internal error 261";
$veritas_errorcode{"262"}="vault internal error 262";
$veritas_errorcode{"263"}="session id assignment failed ";
$veritas_errorcode{"265"}="session id file is empty or corrupt ";
$veritas_errorcode{"266"}="cannot find robot, vault, or profile in the vault configuration ";
$veritas_errorcode{"267"}="cannot find the local host name ";
$veritas_errorcode{"268"}="the vault session directory is either missing or inaccessible ";
$veritas_errorcode{"269"}="no vault session id was found ";
$veritas_errorcode{"270"}="unable to obtain process id, getpid failed ";
$veritas_errorcode{"271"}="the initialization of the vault configuration file failed ";
$veritas_errorcode{"272"}="execution of a vault notify script failed ";
$veritas_errorcode{"273"}="invalid job id";
$veritas_errorcode{"274"}="no profile was specified";
$veritas_errorcode{"275"}="a session is already running for this vault";
$veritas_errorcode{"276"}="invalid session id";
$veritas_errorcode{"277"}="unable to print reports";
$veritas_errorcode{"278"}="unimplemented error code";
$veritas_errorcode{"279"}="unimplemented error code";
$veritas_errorcode{"280"}="unimplemented error code";
$veritas_errorcode{"281"}="vault core error";
$veritas_errorcode{"282"}="vault core system error";
$veritas_errorcode{"283"}="vault core unhandled error";
$veritas_errorcode{"284"}="error caused by invalid data in vault configuration file ";
$veritas_errorcode{"285"}="unable to locate vault directory ";
$veritas_errorcode{"286"}="vault internal error";
$veritas_errorcode{"287"}="failed attempting to copy (consolidated) report file ";
$veritas_errorcode{"288"}="attempt to open a log file failed ";
$veritas_errorcode{"289"}="an error occurred when calling vault core ";
$veritas_errorcode{"290"}="one or more errors detected during eject processing ";
$veritas_errorcode{"291"}="number of media has exceeded capacity of MAP; must perform manual eject using vltopmenu or vlteject ";
$veritas_errorcode{"292"}="eject process failed to start ";
$veritas_errorcode{"293"}="eject process has been aborted ";
$veritas_errorcode{"294"}="database backup failed ";
$veritas_errorcode{"295"}="eject process could not obtain information about the robot ";
$veritas_errorcode{"296"}="process called but nothing to do ";
$veritas_errorcode{"297"}="all volumes are not available to eject ";
$veritas_errorcode{"298"}="the library is not ready to eject volumes ";
$veritas_errorcode{"299"}="there is no available MAP for ejecting ";
$veritas_errorcode{"300"}="vmchange eject verify not responding ";
$veritas_errorcode{"301"}="vmchange api_eject command failed ";
$veritas_errorcode{"302"}="error encountered attempting backup of catalog (multiple tape catalog backup) ";
$veritas_errorcode{"303"}="error encountered executing Media Manager command ";
$veritas_errorcode{"304"}="specified profile not found ";
$veritas_errorcode{"305"}="duplicate profile specified, use full robot/vault/profile ";
$veritas_errorcode{"306"}="errors encountered, partial success ";
$veritas_errorcode{"307"}="eject process has already been run for the requested vault session ";
$veritas_errorcode{"308"}="no images duplicated ";
$veritas_errorcode{"309"}="report requested without eject being run ";
$veritas_errorcode{"310"}="invalid configuration for duplication to disk ";
$veritas_errorcode{"311"}="Iron Mountain Report is already created for this session ";
$veritas_errorcode{"312"}="invalid container database entry ";
$veritas_errorcode{"313"}="container does not exist in container database ";
$veritas_errorcode{"314"}="container database truncate operation failed ";
$veritas_errorcode{"315"}="failed appending to container database ";
$veritas_errorcode{"316"}="container_id is not unique in container database ";
$veritas_errorcode{"317"}="container database close operation failed ";
$veritas_errorcode{"318"}="container database lock operation failed ";
$veritas_errorcode{"319"}="container database open operation failed ";
$veritas_errorcode{"320"}="the specified container is not empty ";
$veritas_errorcode{"321"}="container cannot hold any media from the specified robot ";
$veritas_errorcode{"322"}="cannot find vault in vault configuration file ";
$veritas_errorcode{"323"}="cannot find robot in vault configuration file";
$veritas_errorcode{"324"}="invalid data found in retention map file for duplication";
$veritas_errorcode{"325"}="unable to find policy/schedule for image using retention mapping ";
$veritas_errorcode{"326"}="specified file contains no valid entry ";
$veritas_errorcode{"327"}="no media ejected for the specified vault session ";
$veritas_errorcode{"328"}="invalid container id ";
$veritas_errorcode{"329"}="invalid recall status ";
$veritas_errorcode{"330"}="invalid volume database host ";
$veritas_errorcode{"331"}="invalid container description ";
$veritas_errorcode{"332"}="error getting information from volume database ";
$veritas_errorcode{"500"}="NB-Java application server not accessible - maximum number of connections exceeded. ";
$veritas_errorcode{"501"}="You are not authorized to use this application. ";
$veritas_errorcode{"502"}="No authorization entry exists in the auth.conf file for user name username. None of the NB-Java applications are available to you. ";
$veritas_errorcode{"503"}="Invalid username. ";
$veritas_errorcode{"504"}="Incorrect password. ";
$veritas_errorcode{"505"}="Can not connect to the NB-Java authentication service on the configured port - (port_number). ";
$veritas_errorcode{"506"}="Can not connect to the NB-Java user service on (host) on port (port_number). If successfully logged in prior to this, please retry your last operation. ";
$veritas_errorcode{"507"}="Socket connection to the NB-Java user service has been broken. Please retry your last operation. ";
$veritas_errorcode{"508"}="Can not write file. ";
$veritas_errorcode{"509"}="Can not execute program. ";
$veritas_errorcode{"510"}="File already exists: file_name ";
$veritas_errorcode{"511"}="NB-Java application server interface error: Java exception ";
$veritas_errorcode{"512"}="Internal error - a bad status packet was returned by NB-Java application server that did not contain an exit status code. ";
$veritas_errorcode{"513"}="bpjava-msvc: the client is not compatible with this server version (server_version). ";
$veritas_errorcode{"514"}="NB-Java: bpjava-msvc is not compatible with this application version (application_version). You may try login to a different NetBackup host or exit the application. The remote NetBackup host will have to be configured with the same version of NetBackup as the host you started the application on. ";
$veritas_errorcode{"516"}="Could not recognize or initialize the requested locale (locale_NB-Java_was_started_in). ";
$veritas_errorcode{"517"}="Can not connect to the NB-Java user service via VNETD on (host) on port (configured_port_number). If successfully logged in prior to this, please retry your last operation. ";
$veritas_errorcode{"518"}="No ports available in range (port_number) through (port_number) per the NBJAVA_CLIENT_PORT_WINDOW configuration option. ";
$veritas_errorcode{"519"}="Invalid NBJAVA_CLIENT_PORT_WINDOW configuration option value: (option_value). ";
$veritas_errorcode{"520"}="Invalid value for NB-Java configuration option (option_name): (option_value). ";
$veritas_errorcode{"521"}="NB-Java Configuration file (file_name) does not exist.";
$veritas_errorcode{"522"}="NB-Java Configuration file (file_name) is not readable due to the following";
$veritas_errorcode{"600"}="an exception condition occurred";
$veritas_errorcode{"601"}="unable to open listen socket ";
$veritas_errorcode{"602"}="cannot set non blocking mode on the listen socket ";
$veritas_errorcode{"603"}="cannot register handler for accepting new connections ";
$veritas_errorcode{"604"}="no target storage unit specified for the new job ";
$veritas_errorcode{"605"}="received error notification for the job ";
$veritas_errorcode{"606"}="no robot on which the media can be read ";
$veritas_errorcode{"607"}="no images were found to synthesize ";
$veritas_errorcode{"608"}="storage unit query failed ";
$veritas_errorcode{"609"}="reader failed ";
$veritas_errorcode{"610"}="end point terminated with an error ";
$veritas_errorcode{"611"}="no connection to reader ";
$veritas_errorcode{"612"}="cannot send extents to bpsynth ";
$veritas_errorcode{"613"}="cannot connect to read media server ";
$veritas_errorcode{"614"}="cannot start reader on the media server ";
$veritas_errorcode{"615"}="internal error 615 (yeah, THAT\'S helpful...)";
$veritas_errorcode{"616"}="internal error 616 (yeah, THAT\'S helpful...)";
$veritas_errorcode{"617"}="no drives available to start the reader process ";
$veritas_errorcode{"618"}="internal error 618 (yeah, THAT\'S helpful...)";
$veritas_errorcode{"619"}="internal error 619 (yeah, THAT\'S helpful...)";
$veritas_errorcode{"620"}="internal error 620 (yeah, THAT\'S helpful...)";
$veritas_errorcode{"621"}="internal error 621 (yeah, THAT\'S helpful...)";
$veritas_errorcode{"622"}="connection to the peer process does not exist ";
$veritas_errorcode{"623"}="execution of a command in a forked process failed ";
$veritas_errorcode{"624"}="unable to send a start command to a reader/writer process on media server ";
$veritas_errorcode{"625"}="data marshalling error ";
$veritas_errorcode{"626"}="data un-marshalling error ";
$veritas_errorcode{"627"}="unexpected message received from bpsynth ";
$veritas_errorcode{"628"}="insufficient data received ";
$veritas_errorcode{"629"}="no message was received from bptm ";
$veritas_errorcode{"630"}="unexpected message was received from bptm ";
$veritas_errorcode{"631"}="received an error from bptm request to suspend media ";
$veritas_errorcode{"632"}="received an error from bptm request to un-suspend media ";
$veritas_errorcode{"633"}="unable to listen and register service via vnetd ";
$veritas_errorcode{"634"}="no drives available to start the writer process ";
$veritas_errorcode{"635"}="unable to register handle with the reactor ";
$veritas_errorcode{"636"}="read from input socket failed ";
$veritas_errorcode{"637"}="write on output socket failed ";
$veritas_errorcode{"638"}="invalid arguments specified ";
$veritas_errorcode{"639"}="specified policy does not exist ";
$veritas_errorcode{"640"}="specified schedule was not found ";
$veritas_errorcode{"641"}="invalid media type specified in the storage unit ";
$veritas_errorcode{"642"}="duplicate backup images were found ";
$veritas_errorcode{"643"}="unexpected message received from bpcoord ";
$veritas_errorcode{"644"}="extent directive contained an unknown media id ";
$veritas_errorcode{"645"}="unable to start the writer on the media server ";
$veritas_errorcode{"646"}="unable to get the address of the local listen socket ";
$veritas_errorcode{"647"}="validation of synthetic image failed ";
$veritas_errorcode{"648"}="unable to send extent message to bpcoord ";
$veritas_errorcode{"649"}="unexpected message received from BPXM ";
$veritas_errorcode{"650"}="unable to send extent message to BPXM ";
$veritas_errorcode{"651"}="unable to issue the database query for policy ";
$veritas_errorcode{"652"}="unable to issue the database query for policy information ";
$veritas_errorcode{"653"}="unable to send a message to bpccord ";
$veritas_errorcode{"654"}="internal error 654";
$veritas_errorcode{"655"}="no target storage unit was specified via command line ";
$veritas_errorcode{"656"}="unable to send start synth message to bpcoord ";
$veritas_errorcode{"657"}="unable to accept connection from the reader ";
$veritas_errorcode{"658"}="unable to accept connection from the writer ";
$veritas_errorcode{"659"}="unable to send a message to the writer child process";
$veritas_errorcode{"660"}="specified target storage unit was not found in the database";
$veritas_errorcode{"661"}="unable to send exit message to the BPXM reader ";
$veritas_errorcode{"662"}="unknown image referenced in the synth context message from BPXM ";
$veritas_errorcode{"663"}="image does not have a fragment map ";
$veritas_errorcode{"664"}="zero extents in the synthetic image, cannot proceed ";
$veritas_errorcode{"665"}="termination requested by bpcoord ";
$veritas_errorcode{"667"}="unable to open pipe between bpsynth and bpcoord ";
$veritas_errorcode{"668"}="pipe fgets call from bpcoord failed ";
$veritas_errorcode{"669"}="bpcoord startup validation failure ";
$veritas_errorcode{"670"}="send buffer is full ";
}

