#!/usr/bin/env perl
# [   [  [ [[ BACKUP REPORT BY SERVICE GENERATOR ]] ]  ]   ]
#
# written by Grig Larson, 2006, for Example-Company Online, Inc.
#
# Converted to Linux by Grig Larson 2007-05-22
 
use strict;
use POSIX qw(strftime);
use CGI ':standard';
use DBI;
use Mail::Sender;

# Set up some of the reports, put in comments
  my $daily_date=strftime("%d",localtime);
  my $html_report_name='/home/backup_user/backup_report/'.$daily_date.'_group_report.html';
  my $groupreport_list='/home/backup_user/config/groupreport_list.txt';
  my $customer_backup_export='/home/backup_user/config/customer_backup_export.txt';

  my %report_group=();
  my %backup_by_OS=();
  my %backup_by_size=();
  my %backup_by_total_size=();
  my %backup_by_time_started=();
  my %backup_by_time_elapsed=();
  my %backup_by_file_fragments=();
  my %backup_by_backup_type=(); # Daily, weekly, yearly, chocolate, etc...
  my %backup_by_color=qw(); # Color of html bar in table
  
  my $output=qw();
  my $html_table_output=qw();
  
GetReportList();
GetOutputOfReport();
Create_HTML_Report_Header();
OutputtoHTMLReport("<HR>");
ParseOutReport();
MailAdminReport($output);

################################################################################
sub GetReportList {
my $output=();
   open (REPLIST, $groupreport_list);

    while (my $record=<REPLIST>) {
    chomp $record;
      if ($record =~ m/^[^\#]/) {
        my @reports=split /=/,$record;
        $report_group{$reports[0]}=$reports[1];
        my @aoi_backups=split /,/,$reports[1];
        
        foreach my $aoi_backup (@aoi_backups) {
          $output=$output."$reports[0] = $aoi_backup\n";
        }

      }
    }
  close (REPLIST);
return $output;
}

sub GetOutputOfReport {
  my $record=qw();
  my @backup_data=qw();

  open (EXPORTFILE, $customer_backup_export);
  # 002-05165-3.aoi.backup,0,RedHat2.4,Customers-UNIX,1131512832,Daily,Nov-09-2005 00:07:12,00:48:42,2,7737,3.79,69.50
  # 004-05736.aoi.backup,202,RedHat2.4,,,,,,,,,0.00

     while ($record=<EXPORTFILE>) {
     chomp $record;
     @backup_data=split /,/,$record;

      $backup_by_color{$backup_data[0]}="\#D7EBFF";
      # System Type:
      $backup_by_OS{$backup_data[0]}=$backup_data[2];
      if ($backup_by_OS{$backup_data[0]} eq "FreeBSD"){
        $backup_by_OS{$backup_data[0]}="FreeBSD"; }
      elsif ($backup_by_OS{$backup_data[0]} =~ m/Windows/){
        $backup_by_OS{$backup_data[0]} = "Windows"
      }

      # Backup Type:
      $backup_by_backup_type{$backup_data[0]}=$backup_data[5];
      if ($backup_by_backup_type{$backup_data[0]} eq "") {
        $backup_by_backup_type{$backup_data[0]}=" none";
        $backup_by_color{$backup_data[0]}="\#FFC1C1";
      }
      
      # Backup Start Time:
      $backup_by_time_started{$backup_data[0]}=$backup_data[6];
      if ($backup_by_time_started{$backup_data[0]} eq "" && $backup_data[1] eq "X") {
        $backup_by_time_started{$backup_data[0]}="  Backups Suspended ";
        $backup_by_color{$backup_data[0]}="\#BBBBBB";
      }
      elsif ($backup_by_time_started{$backup_data[0]} eq "" && $backup_data[1] ne "X") {
        $backup_by_time_started{$backup_data[0]}="~~~ ~~ ~~~~ --\:--\:--";
      }
        
      # Time Elapsed:
      $backup_by_time_elapsed{$backup_data[0]}=$backup_data[7];
      if ($backup_by_time_elapsed{$backup_data[0]} eq "") {
        $backup_by_time_elapsed{$backup_data[0]}="--\:--\:--";
        }
        
      # Backup Size: (GB)
      $backup_by_size{$backup_data[0]}=$backup_data[10];
      if ($backup_by_size{$backup_data[0]} eq "") {
        $backup_by_size{$backup_data[0]}="-.--";
        }

      # Total Backup Size: (GB)
      $backup_by_total_size{$backup_data[0]}=$backup_data[11];
      if ($backup_by_total_size{$backup_data[0]} eq "") {
        $backup_by_total_size{$backup_data[0]}="0.00";
        }

      # Number of Files (fragments):
      $backup_by_file_fragments{$backup_data[0]}=$backup_data[9];
      if ($backup_by_file_fragments{$backup_data[0]} eq "") {
        $backup_by_file_fragments{$backup_data[0]}="0";
        }
       # $output=$output."$backup_by_OS{$backup_data[0]} client $backup_data[0] has $backup_by_total_size{$backup_data[0]}gb\n";

  }
  close (EXPORT);
}

sub ParseOutReport {
  my %total_percent_of_group=qw();
  my $temp_output=qw();
  foreach my $key (sort keys %report_group) {
    $total_percent_of_group{$key}=0;
    
	#$output=$output."$key:\n-------------\n";   #$report_group{$key}\n\n
    
    # $html_table_output=$html_table_output."
    #	<B><U>$key</U></B>
    #	<TABLE WIDTH=\"900\" BGCOLOR=\"\#D7EBFF\" BORDER=0>
    #	";

    my @report_array=split /,/,$report_group{$key};
    foreach my $client (@report_array) {
    $temp_output=$temp_output.(sprintf '%-27s',"$client")
        .(sprintf'%10s', "$backup_by_OS{$client}")."  "
	.(sprintf'%7s', "$backup_by_backup_type{$client}")."  "
	."$backup_by_time_started{$client}"
        .(sprintf'%10s',"$backup_by_time_elapsed{$client}")
        .(sprintf'%6s',"$backup_by_size{$client}"). " gb of "
        .(sprintf'%6s',"$backup_by_total_size{$client}").
        " gb total\n";
     $total_percent_of_group{$key}= $total_percent_of_group{$key}+$backup_by_total_size{$client};
    $html_table_output=$html_table_output."
    <TR BGCOLOR=\"$backup_by_color{$client}\">
      <TD WIDTH=\"250\">$client<\/TD>
      <TD WIDTH=\"100\">$backup_by_OS{$client}<\/TD>
      <TD WIDTH=\"50\">$backup_by_backup_type{$client}<\/TD>
      <TD WIDTH=\"200\">$backup_by_time_started{$client}<\/TD>
      <TD WIDTH=\"150\">$backup_by_time_elapsed{$client}<\/TD>
      <TD WIDTH=\"150\" align=right>$backup_by_size{$client}gb <\/TD>
      <TD WIDTH=\"150\" align=right>of $backup_by_total_size{$client} gb total<\/TD>
    </TR>
    ";
    }
    $output=$output."$key  -  $total_percent_of_group{$key}gb total used on disk\n-------------\n$temp_output\n";

    $html_table_output="
	<B><U>$key</U> -  $total_percent_of_group{$key}gb  </B>total used on disk                                                                                                               
        <TABLE WIDTH=\"900\" BGCOLOR=\"\#D7EBFF\" BORDER=0>                                                                               
        "
	.$html_table_output
	."<\/TABLE>\n<HR WIDTH=\"900\" ALIGN=LEFT>\n\n
	";

    OutputtoHTMLReport($html_table_output);
    $html_table_output=qw();
    $temp_output=qw();
  }
}

sub MailAdminReport {
# Mail out the admin report.
#  $_[0] would be any extra warning we decide to toss in.

  my $smtp_server="wsmtp.example-company.net";
  my $iso_date=strftime("%Y-%m-%d",localtime);
  my $mail_subject="Backup Report by Service $iso_date";
  my $mail_body="Good morning,

This is the backup report by service from STEL10.  Please find HTML
report attached, text version below:

$_[0]

:: Signed,
:: STEL10
--------------------------
:: \"Your plastic pal who\'s fun to be with.\"";

  my $sender = new Mail::Sender {smtp => 'wsmtp.example-company.net',
                                 from => 'hosting@example-company.net',
                                 };

   $sender->MailFile({to => 'hosting@example-company.net,hfchou@example-company.net',
   # $sender->MailFile({to => 'glarson@example-company.net',
                    # replyto => 'SystemAdministrators',
                    headers => 'Content-type: html;',
                    subject => $mail_subject,
                    msg => $mail_body,
                    file => $html_report_name}
                    );


}

sub Create_HTML_Report_Header {
# This sets the HTML header, makes it HTML compliant, puts in headers, and
#   sets the opening table.

   open (HTML, "> $html_report_name");
   my $iso_date=strftime("%Y-%m-%d",localtime);
   my $iso_time=strftime("%H:%M:%S",localtime);
   print HTML start_html(
                          -title=>"VERTAS BACKUP REPORT - GROUPED BY SERVICE $iso_date",
                          -bgcolor=>'#FEFEFE',
                          );
   print HTML "<center><h3>VERTAS BACKUP REPORT - GROUPED BY SERVICE $iso_date<\/h3>";
   # print HTML br();
   print HTML "created $iso_time on backup.example-company.net<\/center>\n";
   print HTML p();
   # my $temp=GetFreeSpaceGB("f","free");
   # my $temp2=GetFreeSpaceGB("f","total");
   # my $percent_freef=int($temp/$temp2*100);

   # my $temp3=GetFreeSpaceGB("g","free");
   # my $temp4=GetFreeSpaceGB("g","total");
   # my $percent_freeg=int($temp3/$temp4*100);
   
   # print HTML "$temp remaining from $temp2 gb - <b>$percent_freef\% free<\/B> on F:\n<BR>";
   # print HTML "$temp3 remaining from $temp4 gb - <b>$percent_freeg\% free<\/B> on G:\n<BR>";
   # print HTML p();
	open (DISKSTAT, "/home/backup_user/upload/disk_stats.txt");
   	while (my $disk_stats=<DISKSTAT>){	
   print HTML "<BR>$disk_stats";
	}
	close (DISKSTAT);
   print HTML p();
   close (HTML);
}
sub OutputtoHTMLReport {
  open (HTML, ">> $html_report_name");
  print HTML $_[0];
  close (HTML);
}
sub Create_HTML_Report_Footer {
# This is the end of the HTML report,
#   and makes it all HTML compliant and stuff.

   open (HTML, ">> $html_report_name");
   print HTML "<\/TABLE><P><HR><P> \n";
   print HTML "<TABLE bgcolor=\"\#FFFFFF\">\n<CAPTION><B><U>Summary of Errors, Warnings, and Exceptions<\/U><\/B><\/caption>\n<TR>\n<TD><PRE>\n";
   # print HTML "$extra_mail_alert";
   print HTML "<\/PRE><\/TD><\/TR><\/TABLE>\n";
   print HTML end_html;
   close (HTML);
}

sub GetFreeSpaceGB {
# This gets total disk space by default, but "free" means
#   how much is free.  I did it this way so I can add more
#   features later like, "how many clusters are used" or whatever.
      my $drive=$_[0];
      my ($SectorsPerCluster,
          $BytesPerSector,
          $NumberOfFreeClusters,
          $TotalNumberOfClusters,
          $FreeBytesAvailableToCaller,
          $TotalNumberOfBytes,
          $TotalNumberOfFreeBytes) = Win32::DriveInfo::DriveSpace( $drive );

      if ($_[1] eq "free") {
        my $gb_free= $TotalNumberOfFreeBytes / 1024 / 1024 / 1024;
        $gb_free= sprintf("%.2f",$gb_free);
        return $gb_free;
        }
      else {
        my $gb_total= $TotalNumberOfBytes / 1024 / 1024 / 1024;
        $gb_total= sprintf("%.2f",$gb_total);
        return $gb_total;
      }
}

