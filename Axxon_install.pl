#!/usr/bin/perl
#
# Licensed Materials - Property of IBM
# Script: Axxon_health_centre.pl
# (C) Copyright IBM Corp. 2006. All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
# Priya Mallya/India/IBM
# 01/07/2013
#

# import modules
use strict;
use FindBin qw($Bin);

use lib "$Bin/../../../lib/perl";
use lib "$Bin/../../lib/perl";
use lib "$Bin/../lib/perl";

require "$Bin/install.conf";
my %conf=get_conf();

# standard perl modules
use Cwd;
use File::Path;
use File::Copy;
use File::Spec::Functions;
use Getopt::Long;
use File::Basename;
use common::JVMModes;
use File::Find;


# This installs the Win32::API module (used by the JTC::ProcessMgmt package) if it is missing
# The BEGIN block makes sure it is executed before the 'use' statements (which require the module to be installed first)
BEGIN
{
	if ($^O eq 'MSWin32')
	{
   		eval("use Win32::API;");

		if($@)
	   	{
			`ppm install Win32::API`;
		    if($?)
			{
				die "Install command for Win32::API returned a bad return code.";	
			}
		}
	}
}

#Result store uploader module
use ResultStore::Uploader;

# javatest modules
use common::setup qw(:all);
use common::setmode qw(:all);
use common::Constants qw(:all);
use common::util;
use common::automate qw(:all);
use common::ras;
use Aotjxe::AOTClasspath;

my %options = ( resultsbase   => undef,
                mode          => undef,
                timeout       => 1200,
                extraJavaOpts => undef,
                appAOT        => undef,
                sdkAOT        => undef,
                kill          => $TRUE,
                autoClean     => $FALSE,
                resultStore   => $FALSE,
                job           => "",
                batch         => "",
                axxonServer   => "",
                pkg_name	  => "",
				dist_site	  => "",
                jim			  => "");                       

            
# declare variables 
my $timestamp_size = 28;
my $default_timeout = 120;
my $testsuite = "install";
my $testcase = "install";
 
# Get current wporking directory
my $cwd = getcwd();

my $ps = ":";
my $quote = "\'";
my $cpquote = "";
my $quote_str = "'";


if ($^O eq 'MSWin32')
{
   $ps = ";";
   $quote = "\"";
   $quote_str = "\\\"";
   $cpquote       = "\"";   
}

# $now used as a unique id
my ($now, $date, $time) = common::util->getnow(date => $TRUE, time => $TRUE);

# hash table to keep the test information in...     
my $upload;

# get the value of the options overriden on the command line
GetOptions( 'all!'          => \$options{"all"},
            'resultsbase=s' => \$options{"resultsbase"},
            'mode=s'        => \$options{"mode"},
            'timeout=i'     => \$options{"timeout"},
            'jvmopts=s'     => \$options{"extraJavaOpts"},
            'appaot!'       => \$options{"appAOT"},
            'sdkaot!'       => \$options{"sdkAOT"},
            'kill!'         => \$options{"kill"},
            'autoclean!'    => \$options{"autoClean"},
            'resultStore!'  => \$options{"resultStore"}, 
            'job=i'         => \$options{"job"},
            'batch=i'       => \$options{"batch"},
            'axxonServer=s' => \$options{"axxonServer"},
            'platform=s'    => \$options{"platform"},
			'java_version=s'=> \$options{"java_version"},
			'sr_level=s'	=> \$options{"sr_level"},
			'fp_level=s'	=> \$options{"fp_level"},
			'java_home=s'	=> \$options{"java_home"},
			'ref_java_home=s'	=> \$options{"ref_java_home"},
			'ga_year=s'		=> \$options{"ga_year"},
			'build_id=s'	=> \$options{"build_id"},
			'package_type=s'	=> \$options{"package_type"},
			'reference_file=s'	=> \$options{"reference_file"},
			'reference_build=s' => \$options{"reference_build"},
			'reference_build_url=s' => \$options{"reference_build_url"},
			'package=s'			=> \$options{"package"},
            'H|h|help|?'    => \&usage);

# if the batch id isn't a number then assume we're not on Axxon
if ($options{"batch"} !~ /\d+$/)
{ 
	$options{"resultStore"} = $FALSE;
}

# create results directory and log variables

if( defined($options{resultsbase}) ) {
  $ENV{RESULTSBASE} = $options{resultsbase};
}

# set the mode_str used to create the results directory to "default" if no mode was supplied
my $mode_str = "default";
if (defined $options{"mode"})
{
	$mode_str = $options{"mode"};   
}

if( !defined ($ENV{RESULTSBASE}) and !defined ($ENV{RESULTSDIR})) {
  logBlankLine();	
  logMsg("ERROR:  Base Results Directory must be defined.  To define this set ");
  logMsg("        the RESULTSBASE environment variable or use the --resultsbase option.");
  logBlankLine();	
  die( "TEST FAILED\n" );
}

# Check for mandatory arguments that need to be passed to the perl script
if( !defined $options{"platform"} || !defined $options{"java_version"} || !defined $options{"sr_level"} || !defined $options{"java_home"} || !defined $options{"ga_year"} || !defined $options{"build_id"} || !defined $options{"package_type"} || !defined $options{"package"}) {
  logBlankLine();	
  logMsg("ERROR:  The following are mandatory arguments for the script\n");
  logMsg("platform				<The platform for which packages need to be downloaded> Eg: -platform=linux_x86-32");
  logMsg("java_version			<The java version for which the packages need to be downloaded> Eg: -java_version=java6 ");
  logMsg("sr_level				<The SR Level of the java version specified for which packages need to be downloaded> Eg: -sr_level=5|4fp2");
  logMsg("java_home				<The path where java under test is installed> Eg: -java_home=c:\ibmjava or /tmp/ibmjava");
  logMsg("ga_year				<The year in which the product is expected to GA> Eg: -ga_year=2014");
  logMsg("build_id				<The build level under test> Eg: -build_id=20140701_01");
  logMsg("package				<The package under test> Eg: -package=sdk|jre");
  logMsg("package_type			<The type of the package under test> Eg: -package_type=jar|zip|exe|bin|rpm");
  logMsg("Please refer usage for more details\n\n");
  #usage();
  logBlankLine();	
  die( "TEST FAILED\n" );
}
if(!defined $options{"reference_file"} and !defined $options{"reference_build"} and !defined $options{"ref_java_home"} )
{
  logBlankLine();	
  logMsg("USAGE ERROR: Options reference_file or reference_build or ref_java_home should be passed to the script");
  logMsg("Please refer usage for more details\n\n");
  die( "TEST FAILED\n" );  
}

my $java_version = $options{"java_version"};
my $platform = $options{"platform"};
my $java_home = $options{"java_home"};
#my $ref_java_home = $options{"ref_java_home"};
my $sr_level = $options{"sr_level"};
my $ga_year = $options{"ga_year"};
my $build_id = $options{"build_id"};
my $package = $options{"package"};
my $package_type = $options{"package_type"};
#my $reference_file = $options{"reference_file"};
#my $reference_build = $options{"reference_build"};
my $reference_build_url = $options{"reference_build_url"};
my $fp_level;

if(defined $options{"fp_level"}) {
	$fp_level = $options{"fp_level"};
}


# Create the results directory and define the log for storing test messages
my ($results_root_dir, $resultsdir) =
  common::util->createResultsDir( $testsuite,
                                  $testcase,
                                  $mode_str);
                                                                                 
my $log = catfile($resultsdir, $testcase."log");

chdir $resultsdir;

# initialise the logging preferences
setLogPrefs(log => $log, prefix => ">> ", timestamp => $TRUE, echo => $TRUE);

logBlankLine();
logMsg("  Directing results to $resultsdir");

logBlankLine();
logMsg("  To ensure cores are not overwritten, change current directory to $resultsdir");
if( !chdir($resultsdir) ) {
  logBlankLine();	
  logMsg("ERROR: Unable to change to results directory");
  logBlankLine();	
  die( "TEST FAILED\n" );
}
						 
# run the test...
my $title = "Running ${testcase} test...";
logBlankLine();
logDivider("*", $timestamp_size + length($title));                
logMsg($title);
logDivider("*", $timestamp_size + length($title));                
logBlankLine();
        
logMsg("  ${testcase} Test Starting");
logBlankLine();

# define the files to collect the STDOUT and STDERR in
my $stdout = catfile($resultsdir, "std.out");
my $stderr  = catfile($resultsdir, "std.err");

# run the test - this function starts the test, monitors it,
# killing the test if it runs for more then the exittime.
# The function returns the names of any cores etc detected
# and the return code, exit status and message

my $total_fails = 0;

# Check license information
logMsg ("Sub Test: Verify License....Starting\n");
my $license_result = verify_license ($java_version, $java_home, $platform);
if ((($license_result == 3) && ($java_version ne "java7")) || (($license_result == 2) && ($java_version eq "java7")) || (($license_result == 2) && ($java_version eq "java6") && (($platform =~ /zos/) || ($platform =~ /aix/)))) {
	logBlankLine();
	logMsg ("Sub test: Verifying Licence....Complete - Passed\n\n");
}
else {
	logBlankLine();
	logMsg ("Sub test: Verifying Licence....Complete - Failed\n\n");
	$total_fails++;
}

logBlankLine();

logMsg ("Sub Test: Verify Copyright....Starting\n");
# Check Copyright information
if ($platform =~ /aix/ && $package eq "jre" && ($package_type eq "jar" || $package_type eq "tarz")) {
	logMsg ("No Copyright files present on this build type. Skipping verification.\n");
}
else {
	if (verify_copyright ($java_home, $ga_year)) {
		logBlankLine();
		logMsg ("Sub test: Verifying Copyright....Complete - Passed\n\n");
	}
	else {
		logBlankLine();
		logMsg ("Sub test: Verifying Copyright....Complete - Failed\n\n");
		$total_fails++;
	}
}
logBlankLine();

logMsg ("Sub Test: Verify java -fullversion....Starting\n");
# Check java -fullversion
if (verify_fullversion ($java_version, $sr_level, $fp_level, $build_id, $platform, $java_home, $package, $package_type)) {
	logBlankLine();
	logMsg ("Sub test: Verifying fullversion....Complete - Passed\n\n");
}
else {
	logBlankLine();
	logMsg ("Sub test: Verifying fullversion....Complete - Failed\n\n");
	$total_fails++;
}

logBlankLine();

logMsg ("Sub Test: Verify java -version....Starting\n");
# Check java -version
if (verify_version ($java_version, $sr_level, $fp_level, $build_id, $platform, $java_home, $package, $package_type)) {
	logBlankLine();
	logMsg ("Sub test: Verifying version....Complete - Passed\n\n");
}
else {
	logBlankLine();
	logMsg ("Sub test: Verifying version....Complete - Failed\n\n");
	$total_fails++;
}

logBlankLine();

# Commenting verify_cmptagfiles => verify_files_and_directories should take care of ALL missing and extra files - including cmptag files.
# This check might be required for a GA release. The install.html document still lists this test - so, unlikely that SVT will miss executing it.
# We will uncomment if we come across situations where we will need to explicitly check something with cmptag files.

# Check cmptag files for non-cloud(sfj) packages only
#if ($package ne "cloud") {
#	logMsg ("Sub Test: Verify cmptag files....Starting\n");
#	if (verify_cmptagFiles ($java_version, $platform, $java_home)) {
#		logBlankLine();
#		logMsg ("Sub test: Verifying cmptag files....Complete - Passed\n\n");
#	}
#	else {
#		logBlankLine();
#		logMsg ("Sub test: Verifying cmptag files....Complete - Failed\n\n");
#		$total_fails++;
#	}
#}
#logBlankLine();

logMsg ("Sub Test: Verify files and directories....Starting\n");
# Check files and directories
if( defined($options{reference_build})){
	logMsg("Verifying files and directories using reference_build option");
	my $reference_build = $options{reference_build};
	if (verify_files_and_directories2 ($java_version, $platform, $java_home, $package, $package_type, $reference_build, $reference_build_url)) {
		logBlankLine();
		logMsg ("Sub test: Verifying files and directories....Complete - Passed\n\n");
	}
	else {
		logBlankLine();
		logMsg ("Sub test: Verifying files and directories....Complete - Failed\n\n");
		$total_fails++;
	}
	goto Label1;
}
if( defined($options{ref_java_home})){
    my $ref_java_home = $options{ref_java_home};
	logMsg("Verifying files and directories using ref_java_home option");
	if (verify_files_and_directories3 ($java_version, $platform, $java_home, $package, $package_type, $ref_java_home)) {
		logBlankLine();
		logMsg ("Sub test: Verifying files and directories....Complete - Passed\n\n");
	}
	else {
		logBlankLine();
		logMsg ("Sub test: Verifying files and directories....Complete - Failed\n\n");
		$total_fails++;
	}
	goto Label1;
}
if( defined($options{reference_file})){
    my $reference_file = $options{reference_file};
	logMsg("Verifying files and directories using reference_file option");
	if (verify_files_and_directories1 ($java_version, $platform, $java_home, $package, $package_type, $reference_file)) {
		logBlankLine();
		logMsg ("Sub test: Verifying files and directories....Complete - Passed\n\n");
	}
	else {
		logBlankLine();
		logMsg ("Sub test: Verifying files and directories....Complete - Failed\n\n");
		$total_fails++;
	}
}
Label1:
logMsg("  Test Complete");
logBlankLine();
      
logDivider("*", $timestamp_size + length($title));                
logBlankLine();
logBlankLine();
setLogPrefs(log => $log, prefix => ">> ", timestamp => $TRUE, echo => $TRUE);
	 
if ($total_fails != 0)
{
    logMsg("${testcase} test failed...");           
    logBlankLine();
}

my $summary = "";
my $passed = $FALSE;

if ($total_fails == 0)
{
  $summary = "Axxon_".$testcase.".pl TEST SUMMARY - TEST PASSED";
  $upload = $FALSE; 
  $passed = $TRUE; 
} 
elsif ($total_fails > 0)
{
  $summary = "Axxon_".$testcase.".pl TEST SUMMARY - TEST FAILED"; 
  $upload = $TRUE;
  $passed = $FALSE;
  logBlankLine();
  logMsg("Standard Output: ");
  if (-e $stdout)
  {
  	my $lines;
    $lines = common::util->storeFile($stdout);
    foreach my $line (@{$lines})
    {
    	print $line;
    }
  }
  logBlankLine();
  logMsg("Standard Error:");
  if (-e $stderr)
  {
  	my $lines;
    $lines = common::util->storeFile($stderr);
    # Strip out messages relating to missing permissions, because we may be on an NFS mount on zOS
	$lines = common::util->strip_zos_perms_messages($lines);
    foreach my $line (@{$lines})
    {
    	print $line;
    }
  }
}
else
{
  $summary = "Axxon_".$testcase.".pl TEST SUMMARY - UNEXPECTED RESULTS - TEST FAILED"; 
  $upload = $TRUE;
  $passed = $FALSE;
  logBlankLine();
  logMsg("Standard Output: ");
  if (-e $stdout)
  {
  	my $lines;
    $lines = common::util->storeFile($stdout);
    foreach my $line (@{$lines})
    {
    	print $line;
    }
  }
  logBlankLine();
  logMsg("Standard Error:");
  if (-e $stderr)
  {
  	my $lines;
    $lines = common::util->storeFile($stderr);
    # Strip out messages relating to missing permissions, because we may be on an NFS mount on zOS
	$lines = common::util->strip_zos_perms_messages($lines);
    foreach my $line (@{$lines})
    {
    	print $line;
    }
  }
}   

logDivider( "*", $timestamp_size + length($summary) );
logMsg($summary);
logDivider( "*", $timestamp_size + length($summary) );
logBlankLine();
    
# Forcing upload to be false at all times. This test does not need any files to be uploaded. The axxon job output page should provide all details.
# Any time in future, if upload becomes necessary, simply comment the $upload assignment in the line below.
$upload = $FALSE;
chdir($cwd);
common::util->cleanUp("resultsdir" => $resultsdir, "upload" => $upload, "passed" => $passed,
                      "autoClean" => $options{"autoClean"}, "axxonServer" => $options{"axxonServer"}, 
                      "resultStore" => $options{"resultStore"}, "batch" => $options{"batch"}, "job" => $options{"job"});

if ( $passed == $FALSE ) {
  exit 1;
}
else {
  exit 0;
}

#------------------------------------------------------------#
# 
# INTERNAL METHODS
#
#------------------------------------------------------------#

#------------------------------------------------------------#
# verify_license
#
# Usage: verify_license ($java_version, $java_home, $platform)
# 
# Verifies the PN, DN and LN numbers  
# 
#------------------------------------------------------------#
sub verify_license
{
	my ($java_ver, $java_home, $plat) = @_;
	my $result=0;

	logMsg ("Verifying license file information...");
	
	my $license_file = catfile ($java_home, "license_en.txt");
	logMsg ("License file = $license_file\n");
	
	my @dn_arr = @{$conf{$java_ver}{$plat}{DN}};
	my @pn_arr = @{$conf{$java_ver}{$plat}{PN}};

	my $dn_number = $dn_arr[0];
	my $pn_number = $pn_arr[0];
	
	my @ln_arr;
	my $ln_number;

	if (($java_ver ne "java7") && (!(($java_ver eq "java6") && (($plat =~ /zos/) || ($plat =~ /aix/))))) {
		@ln_arr = @{$conf{$java_ver}{$plat}{LN}};
		$ln_number = $ln_arr[0];
	}

	open (LFILE, $license_file) or die "Error: Could not open $license_file...Failed";
	while (<LFILE>) {
		my $num = $_;
		chomp ($num);
		if ($num =~ /D\/N/) {
			my @dn = split (/ /, $num);
			logMsg ("Verifying D/N...");
			logMsg ("Expecting: $dn_number");
			logMsg ("Found: $dn[$#dn]");
			if ($dn_number eq $dn[$#dn]) {
				logMsg ("D/N matches....Passed\n");
				$result++;
			}
			else {
				logMsg ("D/N does not match....Failed\n");
			}
		}	
		if ($num =~ /P\/N/) {
			my @pn = split (/ /, $num);
			logMsg ("Verifying P/N...");
			logMsg ("Expecting: $pn_number");
			logMsg ("Found: $pn[$#pn]");
			if ($pn_number eq $pn[$#pn]) {
				logMsg ("P/N matches....Passed\n");
				$result++;
			}
			else {
				logMsg ("P/N does not match....Failed\n");
			}
		}
		if (($num =~ /L\/N/)) {
			my @ln = split (/ /, $num);
			logMsg ("Verifying L/N...");
			logMsg ("Expecting: $ln_number");
			logMsg ("Found: $ln[$#ln]");
			if ($ln_number eq $ln[$#ln]) {
				logMsg ("L/N matches....Passed\n");
				$result++;
			}
			else {
				logMsg ("L/N does not match....Failed\n");
			}
		}
	}

	close LFILE;
	return $result;
}

#------------------------------------------------------------#
# verify_copyright
#
# Usage: verify_copyright ($java_version, $ga_year)
#
#  Verifies if the year in the copyright file matches the 
#  year of GA for the release
# 
#------------------------------------------------------------#
sub verify_copyright
{
	my ($java_ver, $ga_year) = @_;
	my $result=0;
	
	logMsg ("Verifying Copyright file information...");
	
	my $copyright_file = catfile ($java_home, "copyright");
	logMsg ("Copyright file = $copyright_file\n");

	open (CFILE, $copyright_file) or die "Error: Could not open $copyright_file...Failed";
	my @lines = <CFILE>;
	close CFILE;

	# Copyright year information is always on the 6th line of the file
	my @words = split (/ /, $lines[5]);

	# Year of GA for the sdk under test is always the 5th word on 6th line
	my $year = $words[4];

	chop ($year);

	logMsg ("Expecting: $ga_year");
	logMsg ("Found: $year");

	if ($year =~ /$ga_year/) {
		logMsg ("Copyright year matches....Passed");
		$result++;
	}
	else {
		logMsg ("Copyright year does not match....Failed");
	}

	return $result;

}

#------------------------------------------------------------#
# verify_fullversion
#
# Usage: verify_fullversion ($java_version, $sr_level, $fp_level, $build_id, $platform, $java_home)
#
#  Verifies the java -fullversion output
# 
#------------------------------------------------------------#
sub verify_fullversion
{
	my ($java_ver, $sr_level, $fp_level, $build_id, $plat, $java_home, $pkg, $pkg_type) = @_;
	my $result=0;

	my $javacmd;
	if ($plat =~ /zos/) {
		if ($java_ver eq "java6" && $pkg eq "sdk" && $pkg_type eq "jar") {
			$javacmd = "$java_home".${sl}."jre".${sl}."bin".${sl}."java -fullversion";
		}
		else {
			$javacmd = "$java_home".${sl}."bin".${sl}."java -fullversion";
		}
	}
	else {
		$javacmd = "$java_home".${sl}."jre".${sl}."bin".${sl}."java -fullversion";
	}
	logMsg ("Executing...$javacmd");
	
	my ($rc, $ExitStatus, $ExitMsg, $elapsed, $javacore, 
			$drwatson, $core, $heap, $jvmcore, $killed) = 
			common::automate->runTestCmd( cmd       => $javacmd,
				                          stdoutlog => $stdout,
					                      stderrlog => "fullver.log", 
						                  msglog    => $log,
							              logdir    => $resultsdir,
								          exittime  => $options{timeout}, 
									      kill      => $options{kill},
										  uid       => $now,
										  heartbeat => $TRUE,
										  heartbeat_period => 900,
			                              echo      => $FALSE);
	
	my $lines = common::util->storeFile('fullver.log');
	# Strip out messages relating to missing permissions, because we may be on an NFS mount on zOS
	$lines = common::util->strip_zos_perms_messages($lines);
	my $line = @{$lines}[0];

	chomp ($line);
	
	my @arr = @{$conf{$java_ver}{$plat}{fullversion}};
	my $fullver;
	my $sr_str1;
	my $sr_str2;
	if ($fp_level) {
		$sr_str1 = "sr".$sr_level."fp".$fp_level;
		if ($java_ver eq "java6") {
			$sr_str2 = " "."(SR".$sr_level." "."FP".$fp_level.")\"";
		}
		else {
			$sr_str2 = "(SR".$sr_level." "."FP".$fp_level.")";
		}
	}
	else {
		$sr_str1 = "sr".$sr_level;
		if ($java_ver eq "java6") {
				$sr_str2 = " "."(SR".$sr_level.")\"";
			}
			else {
				$sr_str2 = "(SR".$sr_level.")";
		}
	}

	if ($pkg eq "cloud") {
		$sr_str2 = $sr_str2." Small Footprint";
	}
	
	$fullver = $arr[0].$sr_str1."-".$build_id.$sr_str2;

	logMsg ("Expecting: $fullver");
	logMsg ("Found: $line");

	if ($fullver eq $line) {
		$result = 1;
	}
	return $result;
}

#------------------------------------------------------------#
# verify_version
#
# Usage: verify_version ($java_version, $sr_level, $fp_level, $build_id, $platform, $java_home)
#
#  Verifies java -version output
# 
#------------------------------------------------------------#
sub verify_version
{
	my ($java_ver, $sr_level, $fp_level, $build_id, $plat, $java_home, $pkg, $pkg_type) = @_;
	my $result=0;

	my $javacmd;
	if ($plat =~ /zos/) {
		if ($java_ver eq "java6" && $pkg eq "sdk" && $pkg_type eq "jar") {
			$javacmd = "$java_home".${sl}."jre".${sl}."bin".${sl}."java -version";
		}
		else {
			$javacmd = "$java_home".${sl}."bin".${sl}."java -version";
		}
	}
	else {
		$javacmd = "$java_home".${sl}."jre".${sl}."bin".${sl}."java -version";
	}
	logMsg ("Executing...$javacmd");
	
	my ($rc, $ExitStatus, $ExitMsg, $elapsed, $javacore, 
			$drwatson, $core, $heap, $jvmcore, $killed) = 
			common::automate->runTestCmd( cmd       => $javacmd,
				                          stdoutlog => $stdout,
					                      stderrlog => "ver.log", 
						                  msglog    => $log,
							              logdir    => $resultsdir,
								          exittime  => $options{timeout}, 
									      kill      => $options{kill},
										  uid       => $now,
										  heartbeat => $TRUE,
										  heartbeat_period => 900,
			                              echo      => $FALSE);
	
	my $lines = common::util->storeFile('ver.log');
	# Strip out messages relating to missing permissions, because we may be on an NFS mount on zOS
	$lines = common::util->strip_zos_perms_messages($lines);
	my $line = @{$lines}[1];
	
	chomp ($line);

	my @arr = @{$conf{$java_ver}{$plat}{version}};

	my $sr_str1;
	my $sr_str2;
	if ($fp_level) {
		$sr_str1 = "sr".$sr_level."fp".$fp_level;
		$sr_str2 = "(SR".$sr_level." "."FP".$fp_level.")";
	}
	else {
		$sr_str1 = "sr".$sr_level;
		$sr_str2 = "(SR".$sr_level.")";
	}
	
	if ($pkg eq "cloud") {
		$sr_str2 = $sr_str2." Small Footprint)";
	}
	else {
		$sr_str2 = $sr_str2.")";
	}

	my $ver = $arr[0].$sr_str1."-".$build_id.$sr_str2;
	logMsg ("Expecting: $ver");
	logMsg ("Found: $line");

	if ($ver eq $line) {
		$result = 1;
	}
	return $result;
}

#------------------------------------------------------------#
# print_reference_java_version
#
# Usage: print_reference_java_version ($java_ver, $plat, $ref_java_home, $pkg, $pkg_type)
#
#  Prints java -version output for reference Java
# 
#------------------------------------------------------------#
sub print_reference_java_version
{
	my ($java_ver, $plat, $ref_java_home, $pkg, $pkg_type) = @_;

	my $javacmd;
	if ($plat =~ /zos/) {
		if ($java_ver eq "java6" && $pkg eq "sdk" && $pkg_type eq "jar") {
			$javacmd = "$ref_java_home".${sl}."jre".${sl}."bin".${sl}."java -version";
		}
		else {
			$javacmd = "$ref_java_home".${sl}."bin".${sl}."java -version";
		}
	}
	else {
		$javacmd = "$ref_java_home".${sl}."jre".${sl}."bin".${sl}."java -version";
	}
	logMsg ("Executing...$javacmd");
	
	my ($rc, $ExitStatus, $ExitMsg, $elapsed, $javacore, 
			$drwatson, $core, $heap, $jvmcore, $killed) = 
			common::automate->runTestCmd( cmd       => $javacmd,
				                          stdoutlog => $stdout,
					                      stderrlog => "refjavaver.log", 
						                  msglog    => $log,
							              logdir    => $resultsdir,
								          exittime  => $options{timeout}, 
									      kill      => $options{kill},
										  uid       => $now,
										  heartbeat => $TRUE,
										  heartbeat_period => 900,
			                              echo      => $FALSE);
	
	open(INFILE, "refjavaver.log") or die "Cannot open file refjavaver.log\n";
	while(my $line = <INFILE>) {
		print $line;
	}
	close INFILE;
}
#------------------------------------------------------------#
# verify_cmptagFiles
#
# Usage: verify_cmptagfiles ($java_version, $platform, $java_home)
#
#  Verifies existense of all required and only required cmptag files
# 
#------------------------------------------------------------#
sub verify_cmptagFiles
{
	my ($java_ver, $plat, $java_home) = @_;
	my $result=0;
	
	# Get list of all files under JAVA_HOME/properties/version
	use File::Glob ':glob';
	use File::Basename;
	
	my $cmptagfile_loc = catfile($java_home,"${sl}properties${sl}version");

	my @temp_cmptag_files = bsd_glob(catfile("$cmptagfile_loc","*"));
	my @cmptag_files;
	foreach my $temp_cmptag_file (@temp_cmptag_files) {
		my @temp_arr1;
		if ($^O eq 'MSWin32')
		{
			@temp_arr1 = split (/\\/, $temp_cmptag_file);
		}
		else {
			@temp_arr1 = split (/\//, $temp_cmptag_file);
		}
		my @temp_arr2 = split (/\./, $temp_arr1[$#temp_arr1]);

		# Java6 and above has a file named default.jvm and compressedrefs.jvm (for 64 bit) => in that case, join the first two elements of the array before push.
		# Is there a better way of achieving this?
		if (($temp_arr2[0] eq "default") || ($temp_arr2[0] eq "compressedrefs")) {
			my $file_name = join('.',  $temp_arr2[0], $temp_arr2[1]);
			push (@cmptag_files, $file_name);
		}
		else {
			push (@cmptag_files, $temp_arr2[0]);
		}
		
	}

	my @expected_cmptag_files = @{$conf{$java_ver}{$plat}{cmptag_files}};
	my $found=0;

	my @missing;
	my @extra;

	foreach my $expected_file (@expected_cmptag_files) {
		$found = 0;
		foreach my $file (@cmptag_files) {
			if ($file eq $expected_file) {
				$found++;
			}
		}
		if ($found == 0) {
			push (@missing, $expected_file);
		}
	}

	foreach my $file (@cmptag_files) {
		$found = 0;
		foreach my $expected_file (@expected_cmptag_files) {
			if ($file eq $expected_file) {
				$found++;
			}
		}
		if ($found == 0) {
			push (@extra, $file);
		}
	}

	logBlankLine ();
	
	if ($#missing >= 0) {
		logMsg ("Missing file(s):");
		foreach my $missing_file (@missing) {
			logMsg ("$missing_file");
		}
	}

	logBlankLine ();

	if ($#extra >= 0) {
		logMsg ("Extra file(s):");
		foreach my $extra_file (@extra) {
			logMsg ("$extra_file");
		}
	}
	if (($#missing < 0) && ($#extra < 0)) {
		logMsg ("All expected cmptag files found....Passed");
		$result++;
	}

	return $result;
}

#------------------------------------------------------------#
# verify_files_and_directories
#
# Usage: verify_files_and_directories ($java_version, $platform, $java_home, $package, $package_type, $referece_file)
#
#  Verifies existence of all required and only required files and folders in JAVA_HOME
# 
#------------------------------------------------------------#
sub verify_files_and_directories1
{
	my ($java_ver, $plat, $java_home, $pkg, $pkg_type, $ref_file) = @_;
	my $result=0;

	my $ref_listing_file = $ref_file;
	my $test_listing_file = catfile ($resultsdir, "listing_test.txt");

	generate_file_listing ($java_home, $test_listing_file);

	open (REFFILE, $ref_listing_file) or die "Error: Could not open $ref_listing_file...Failed"; 
	open (TESTFILE, $test_listing_file) or die "Error: Could not open $test_listing_file...Failed"; 

	my @expected_files = <REFFILE>;
	my @test_files = <TESTFILE>;

	close (REFFILE);
	close (TESTFILE);

	my $found=0;
	my @missing;
	my @extra;

	foreach my $expected_file (@expected_files) {
		$found = 0;
		foreach my $file (@test_files) {
			if ($file eq $expected_file) {
				$found++;
			}
		}
		if ($found == 0) {
			push (@missing, $expected_file);
		}
	}
	
	foreach my $file (@test_files) {
		$found = 0;
		foreach my $expected_file (@expected_files) {
			if ($file eq $expected_file) {
				$found++;
			}
		}
		if ($found == 0) {
			push (@extra, $file);
		}
	}

	if ($#missing >= 0) {
		logMsg ("Missing file(s):");
		foreach my $missing_file (@missing) {
			logMsg ("$missing_file");
		}
	}

	logBlankLine ();

	if ($#extra >= 0) {
		logMsg ("Extra file(s):");
		foreach my $extra_file (@extra) {
			logMsg ("$extra_file");
		}
	}
	if (($#missing < 0) && ($#extra < 0)) {
		logMsg ("All files and directories found....Passed");
		$result++;
	}

	return $result;
}

#------------------------------------------------------------------
sub verify_files_and_directories2
{
	my ($java_ver, $plat, $java_home, $pkg, $pkg_type, $ref_build, $ref_build_url) = @_;
	my $result=0;
	
	logMsg("Install Reference Java");
	my $install_cmd_base = "perl ${quote}".catfile($Bin, "..", "..", "..", "tools", "install_scripts", "install_pkg.pl")."${quote} -use_lockfile -use_last_accessed_file -chmod=a+rwX -d=$options{reference_build}";
    my $testInstall = $install_cmd_base." -i=${quote}".catfile($resultsdir, "refjava")."${quote} -l=${quote}".$options{reference_build_url}."${quote}";
	logMsg("$testInstall");
   
    logMsg("Installing Reference Java Build ");
	my $test_log = catfile($resultsdir, "ref_java_install.log");
       my ($status, $exitstatus) = common::util->runTimedCmd(cmd    => $testInstall,
	   		 								                 log    => $test_log,
													         period => 1800);
	

       my ($tool_status) = common::automate->verifyToolExecution(
	                       tool           => "reference Java Install", 
 	   	    		       hang_status    => $status,
						   exitstatus     => $exitstatus,
						   stderr         => $test_log,
						   completion_msg => "Package State OK",
						   error_list     => [ "Failing!" ]
			      );

       if ($tool_status ne "SUCCESSFUL")
       {  
           logMsg("Reference Java Install failed, deleting Reference Java install... ");
       	   common::util->splatTree(catfile($resultsdir, "refjava"));
       }
	   else
	   {
		   logMsg("Reference Java install - completed successfully");
	   }
    my $folder = catfile($resultsdir, "refjava");
	my $ref_javahome;
	
	opendir(DIR, $folder) or die "Error: Could not open $folder...Failed";
	while (my $file = readdir(DIR)) {
        #Use a regular expression to ignore files beginning with a period
        next if ($file =~ m/^\./);
		# A file test to check that it is a directory
        next unless (-d "$folder/$file");
        $ref_javahome=catfile($folder, $file);
    }
    closedir(DIR);
	
	logMsg("\n");
	logMsg(" Printing Reference Java Verison");
	print_reference_java_version($java_ver, $plat, $ref_javahome, $pkg, $pkg_type);
	
	my $ref_listing_file = catfile ($resultsdir, "listing_ref.txt");
	generate_ref_file_listing ($ref_javahome, $ref_listing_file);
	
	my $test_listing_file = catfile ($resultsdir, "listing_test.txt");
	generate_file_listing ($java_home, $test_listing_file);

	open (REFFILE, $ref_listing_file) or die "Error: Could not open $ref_listing_file...Failed"; 
	open (TESTFILE, $test_listing_file) or die "Error: Could not open $test_listing_file...Failed"; 

	my @expected_files = <REFFILE>;
	my @test_files = <TESTFILE>;

	close (REFFILE);
	close (TESTFILE);

	my $found=0;
	my @missing;
	my @extra;

	foreach my $expected_file (@expected_files) {
		$found = 0;
		foreach my $file (@test_files) {
			if ($file eq $expected_file) {
				$found++;
			}
		}
		if ($found == 0) {
			push (@missing, $expected_file);
		}
	}
	
	foreach my $file (@test_files) {
		$found = 0;
		foreach my $expected_file (@expected_files) {
			if ($file eq $expected_file) {
				$found++;
			}
		}
		if ($found == 0) {
			push (@extra, $file);
		}
	}

	if ($#missing >= 0) {
		logMsg ("Missing file(s):");
		foreach my $missing_file (@missing) {
			logMsg ("$missing_file");
		}
	}

	logBlankLine ();

	if ($#extra >= 0) {
		logMsg ("Extra file(s):");
		foreach my $extra_file (@extra) {
			logMsg ("$extra_file");
		}
	}
	if (($#missing < 0) && ($#extra < 0)) {
		logMsg ("All files and directories found....Passed");
		$result++;
	}

	return $result;
}

#-------------------------------------------------
sub verify_files_and_directories3
{
	my ($java_ver, $plat, $java_home, $pkg, $pkg_type, $ref_javahome) = @_;
	my $result=0;
	
	my $ref_listing_file = catfile ($resultsdir, "listing_ref.txt");
	generate_ref_file_listing ($ref_javahome, $ref_listing_file);
	
	my $test_listing_file = catfile ($resultsdir, "listing_test.txt");
	generate_file_listing ($java_home, $test_listing_file);

	open (REFFILE, $ref_listing_file) or die "Error: Could not open $ref_listing_file...Failed"; 
	open (TESTFILE, $test_listing_file) or die "Error: Could not open $test_listing_file...Failed"; 

	my @expected_files = <REFFILE>;
	my @test_files = <TESTFILE>;

	close (REFFILE);
	close (TESTFILE);

	my $found=0;
	my @missing;
	my @extra;

	foreach my $expected_file (@expected_files) {
		$found = 0;
		foreach my $file (@test_files) {
			if ($file eq $expected_file) {
				$found++;
			}
		}
		if ($found == 0) {
			push (@missing, $expected_file);
		}
	}
	
	foreach my $file (@test_files) {
		$found = 0;
		foreach my $expected_file (@expected_files) {
			if ($file eq $expected_file) {
				$found++;
			}
		}
		if ($found == 0) {
			push (@extra, $file);
		}
	}

	if ($#missing >= 0) {
		logMsg ("Missing file(s):");
		foreach my $missing_file (@missing) {
			logMsg ("$missing_file");
		}
	}

	logBlankLine ();

	if ($#extra >= 0) {
		logMsg ("Extra file(s):");
		foreach my $extra_file (@extra) {
			logMsg ("$extra_file");
		}
	}
	if (($#missing < 0) && ($#extra < 0)) {
		logMsg ("All files and directories found....Passed");
		$result++;
	}

	return $result;
}

#------------------------------------------------------------#
# generate_file_listing
#
# Usage: generate_file_listing ($javapath, $list_file)
#
#  Generates a lit of all files and folders in $javapath
# 
#------------------------------------------------------------#
sub generate_file_listing {

	my ($javapath, $list_file)= @_;
	
	my $temp_javapath = quotemeta ($javapath);
	logMsg("\n");
	logMsg(" Printing Test Java Home value");
	logMsg("Test Java Home = $temp_javapath");
	my $replace_str = "JAVA_HOME";

	# This needs some rework but is a must do item
	#my $temp_javapath;
	#if (chop($temp_path) eq ${sl}) {
	#	substr $temp_path, -1;
	#	$temp_javapath = $temp_path;
	#}
	#else {
	#	$temp_javapath = $temp_path;
	#}

	logMsg ("Generating file listing of $javapath at $list_file...");

	open (LISTFILE, '>>', $list_file) or die "Error: Could not open $list_file...Failed"; 

	sub get_subdir {		  
		if (-l $_ && -d $_) {
			my $parentDir = $File::Find::name;
			find ({wanted => \&get_subdir, follow_fast => 1, follow_skip => 2}, $_);
		}

		if (-f $_) {
			unless (-l $File::Find::dir) {
				my $fileName = $File::Find::name;
				$fileName =~ s/$temp_javapath/$replace_str/g;

				# For jre packages on AIX platforms, sdk is not untarred/unjarred inside a specific "java_home" folder. 
				# If package is installed via install_pkg.pl, then the following files will be left behind and should not be considered as part of sdk.
				if (!($fileName =~ /installed_by.txt/ || $fileName =~ /state.txt/)) {
						print LISTFILE "$fileName\n";
				}
			}
		}
	}

	if ($^O =~ /win/i) {
		find( \&get_subdir, $javapath );
	}
	else {
		find( {wanted => \&get_subdir, follow_fast => 1, follow_skip => 2}, $javapath );
	}

	close (LISTFILE);	
}

#--------------
sub generate_ref_file_listing {

	my ($javapath, $list_file)= @_;
	
	my $temp_javapath = quotemeta ($javapath);
	logMsg("\n");
	logMsg(" Printing Reference Java Home value");
	logMsg("Reference Java Home = $temp_javapath");
	my $replace_str = "JAVA_HOME";

	# This needs some rework but is a must do item
	#my $temp_javapath;
	#if (chop($temp_path) eq ${sl}) {
	#	substr $temp_path, -1;
	#	$temp_javapath = $temp_path;
	#}
	#else {
	#	$temp_javapath = $temp_path;
	#}

	logMsg ("Generating file listing of $javapath at $list_file...");

	open (LISTFILE, '>>', $list_file) or die "Error: Could not open $list_file...Failed"; 

	sub get_subdir_ref {		  
		if (-l $_ && -d $_) {
			my $parentDir = $File::Find::name;
			find ({wanted => \&get_subdir_ref, follow_fast => 1, follow_skip => 2}, $_);
		}

		if (-f $_) {
		    #$File::Find::dir is the current directory name,
			unless (-l $File::Find::dir) {
				my $fileName = $File::Find::name;
				$fileName =~ s/$temp_javapath/$replace_str/g;

				# For jre packages on AIX platforms, sdk is not untarred/unjarred inside a specific "java_home" folder. 
				# If package is installed via install_pkg.pl, then the following files will be left behind and should not be considered as part of sdk.
				if (!($fileName =~ /installed_by.txt/ || $fileName =~ /state.txt/)) {
						print LISTFILE "$fileName\n";
				}
			}
		}
	}

	if ($^O =~ /win/i) {
		find( \&get_subdir_ref, $javapath );
	}
	else {
		find( {wanted => \&get_subdir_ref, follow_fast => 1, follow_skip => 2}, $javapath );
	}

	close (LISTFILE);	
}

#------------------------------------------------------------#
=head2 cleanUp

 Calls cleanUp utility to upload results anywhere during test execution

Usage:

	cleanUp($summary, $upload, $passed);

Arguments:

	$summary - message to be displayed
	$upload - whether results to be uploaded
	$passed - whether the test has passed or failed

Returns:

	 none

=cut

#------------------------------------------------------------#
sub cleanUp
{

	my ($summary,$upload,$passed) = @_;
	
	logBlankLine();
	logMsg ("Cleaning up results directory and uploading results for reference\n");
	logDivider( "*", $timestamp_size + length($summary) );
	logMsg($summary);
	logDivider( "*", $timestamp_size + length($summary) );
	logBlankLine();

	# do the final uploading and cleanup
	chdir($cwd);
	common::util->cleanUp("resultsdir" => $resultsdir, "upload" => $upload, "passed" => $passed,
                      "autoClean" => $options{"autoClean"}, "axxonServer" => $options{"axxonServer"}, 
                      "resultStore" => $options{"resultStore"}, "batch" => $options{"batch"}, "job" => $options{"job"});

	if ( $passed == $FALSE ) {
  		exit 1;
	} else {
  		exit 0;
	}
}
    

#===============================================================================
=head2 usage

 Displays the Axxon_download.pl usage 
Usage:

	usage($msg)

Arguments:

	$msg = optional error message to be printed after the usage

Returns:

	None
=cut
#===============================================================================

sub usage()
{
   my ($msg) = @_;
   
   # remove timestamp from preferences
   setLogPrefs(log => "", prefix => "  ", timestamp => $FALSE, echo => $TRUE);

   logMsg("Usage:");
   logMsg("  perl Axxon_install.pl [-mode -platform -java_version -sr_level -fp_level -java_home -ga_year -build_id -package -package_type -reference_file]");
   logMsg("OR");
   logMsg("  perl Axxon_install.pl [-mode -platform -java_version -sr_level -fp_level -java_home -ga_year -build_id -package -package_type -reference_build -reference_build_url]");
   logMsg("OR");
   logMsg("  perl Axxon_install.pl [-mode -platform -java_version -sr_level -fp_level -java_home -ga_year -build_id -package -package_type -ref_java_home]");
   logBlankLine();
   logMsg("  mode=Defines the mode the test will be run in.");
   logBlankLine();
   logMsg("  platform            = The platform for which the packages need to be downloaded");
   logMsg("  java_version        = The java version for which packages need to be downloaded."); 
   logMsg("                        Possible values are java5, java6, java626, java7, wrtv3");
   logMsg("	 sr_level            = The SR level of the java version specified.");
   logMsg("                        Eg: 4, 5, 12 etc");
   logMsg("	 fp_level            = The FP level of the java version specified."); 
   logMsg("                        Eg: 1, 2, 3 etc");
   logMsg("	 java_home			 = The path where java is installed.");
   logMsg("                        Eg: c:\java or /home/java");
   logMsg("	 ga_year	         = The year when the java under test is expected to release.");
   logMsg("                        Eg: 2014");
   logMsg("	 build_id            = The build identifier of the package under test");
   logMsg("                        Eg: 20140701_01");
   logMsg("	 package		     = The package under test.");
   logMsg("                        Eg: sdk or jre");
   logMsg("  package_type        = The type of package under test.");
   logMsg("                        Eg: zip, tgz, jar etc");
   logMsg("  reference_file      = The path where the reference file listings are stored.");
   logMsg("                        Eg: c:\temp\reference_listing.tx or /tmp/reference_listing.txt");
   logMsg("  ref_java_home       = The path where the reference java is installed");
   logMsg("                        Eg: c:\refjava or /home/testuser/refjava");
   logMsg("	 build_id            = The build identifier of the reference java package");
   logMsg("                        Eg: 20140608_01");
   logMsg("	 reference_build_url = The url of reference java build");
   logMsg("                        Eg: evftp://jsvtaxxon.hursley.ibm.com:1500/j9-60/Linux_AMD64/pxa6460sr16fp7/pxa6460sr16fp7-20150708_01-sdk.jar or evftp://axxon1.in.ibm.com:4444/j9-60/Linux_AMD64/pxa6460sr16fp7/pxa6460sr16fp7-20150708_01-sdk.jar");
   logBlankLine();
   logMsg("  resultsbase         = Defines the resultsbase, the location where the results");
   logMsg("                        will be written");  
   logBlankLine();
   logMsg("  help                Displays the usage for the script");
   logMsg("  autoclean           If the test passes, results are deleted");
   logMsg("  nokill              Prevent process termination if it overruns");
   logMsg("                      Removing the no prefix, reverses its meaning"); 
   logBlankLine();
   logMsg("  ResultStore Support"); 
   logMsg("  All these options need to be used together to allow the test");
   logMsg("  to upload its results to the result store system");
   logBlankLine();  
   logMsg("  resultstore  Enables upload to Axxon result store");
   logMsg("  batch        The Axxon batch number");
   logMsg("  job          The Axxon job number");
   logMsg("  axxonServer  The Axxon server and port number for connecting");
   logMsg("               to the ResultStore");   
   logBlankLine();
   logBlankLine();
   logBlankLine();

   if ($msg ne "" && $msg ne "H")
   {
      logMsg("USAGE ERROR: " . $msg);   
      logBlankLine();
      logBlankLine();
   }
   exit 1;
}