#!/usr/bin/perl
#================
# FILE          : kiwi.pl
#----------------
# PROJECT       : OpenSUSE Build-Service
# COPYRIGHT     : (c) 2006 SUSE LINUX Products GmbH, Germany
#               :
# AUTHOR        : Marcus Schaefer <ms@suse.de>
#               :
# BELONGS TO    : Operating System images
#               :
# DESCRIPTION   : This is the main script to provide support
#               : for creating operating system images
#               : 
#               :
# STATUS        : $LastChangedBy: ms $
#               : $LastChangedRevision: 1 $
#----------------
use lib './modules';
use lib '/usr/share/kiwi/modules';
use strict;

#============================================
# perl debugger setup
#--------------------------------------------
$DB::inhibit_exit = 0;

#============================================
# Modules
#--------------------------------------------
use warnings;
use Carp qw (cluck);
use Getopt::Long;
use File::Spec;
use KIWIRoot;
use KIWIXML;
use KIWILog;
use KIWIImage;
use KIWIBoot;
use KIWIMigrate;
use KIWIOverlay;
use KIWIQX;
use KIWITest;
use KIWIImageFormat;

#============================================
# Globals (Version)
#--------------------------------------------
our $Version       = "4.65";
our $Publisher     = "SUSE LINUX Products GmbH";
our $Preparer      = "KIWI - http://kiwi.berlios.de";
our $openSUSE      = "http://download.opensuse.org";
our @openSUSE      = ("distribution","repositories");
our $ConfigFile    = "$ENV{'HOME'}/.kiwirc";
our $ConfigName    = "config.xml";
our $Partitioner   = "parted";
our $TT            = "Trace Level ";
our $ConfigStatus  = 0;
our $TL            = 1;
our $BT;
#============================================
# Read $HOME/.kiwirc
#--------------------------------------------
if ( -f $ConfigFile) {
	my $kiwi = new KIWILog("tiny");
	if (! do $ConfigFile) {
		$kiwi -> warning ("Invalid $ConfigFile file...");
		$kiwi -> skipped ();
	} else {
		$kiwi -> info ("Using $ConfigFile");
		$kiwi -> done ();
		$ConfigStatus = 1;
	}
}
#============================================
# Globals
#--------------------------------------------
our $BasePath;         # configurable base kiwi path
our $Gzip;             # configurable gzip command
our $LogServerPort;    # configurable log server port
our $LuksCipher;       # stored luks passphrase
our $System;           # configurable baes kiwi image desc. path
our @UmountStack;      # command list to umount
if ( ! defined $BasePath ) {
	$BasePath = "/usr/share/kiwi";
}
if (! defined $Gzip) {
	$Gzip = "gzip -9";
}
if (! defined $LogServerPort) {
	$LogServerPort = "off";
}
if ( ! defined $System ) {
	$System  = $BasePath."/image";
}
our $Tools    = $BasePath."/tools";
our $Schema   = $BasePath."/modules/KIWISchema.rng";
our $SchemaTST= $BasePath."/modules/KIWISchemaTest.rng";
our $KConfig  = $BasePath."/modules/KIWIConfig.sh";
our $KMigrate = $BasePath."/modules/KIWIMigrate.txt";
our $KMigraCSS= $BasePath."/modules/KIWIMigrate.tgz";
our $KSplit   = $BasePath."/modules/KIWISplit.txt";
our $Revision = $BasePath."/.revision";
our $TestBase = $BasePath."/tests";
our $SchemaCVT= $BasePath."/xsl/master.xsl";
our $Pretty   = $BasePath."/xsl/print.xsl";
our $InitCDir = "/var/cache/kiwi/image";

#==========================================
# Globals (Supported filesystem names)
#------------------------------------------
our %KnownFS;
$KnownFS{ext4}{tool}      = findExec("mkfs.ext4");
$KnownFS{ext3}{tool}      = findExec("mkfs.ext3");
$KnownFS{ext2}{tool}      = findExec("mkfs.ext2");
$KnownFS{squashfs}{tool}  = findExec("mksquashfs");
$KnownFS{clicfs}{tool}    = findExec("mkclicfs");
$KnownFS{clic}{tool}      = findExec("mkclicfs");
$KnownFS{unified}{tool}   = findExec("mksquashfs");
$KnownFS{compressed}{tool}= findExec("mksquashfs");
$KnownFS{reiserfs}{tool}  = findExec("mkreiserfs");
$KnownFS{btrfs}{tool}     = findExec("mkfs.btrfs");
$KnownFS{xfs}{tool}       = findExec("mkfs.xfs");
$KnownFS{cpio}{tool}      = findExec("cpio");
$KnownFS{ext3}{ro}        = 0;
$KnownFS{ext4}{ro}        = 0;
$KnownFS{ext2}{ro}        = 0;
$KnownFS{squashfs}{ro}    = 1;
$KnownFS{clicfs}{ro}      = 1;
$KnownFS{clic}{ro}        = 1;
$KnownFS{unified}{ro}     = 1;
$KnownFS{compressed}{ro}  = 1;
$KnownFS{reiserfs}{ro}    = 0;
$KnownFS{btrfs}{ro}       = 0;
$KnownFS{xfs}{ro}         = 0;
$KnownFS{cpio}{ro}        = 0;

#============================================
# Globals
#--------------------------------------------
our $Build;                 # run prepare and create in one step
our $Prepare;               # control XML file for building chroot extend
our $Create;                # image description for building image extend
our $InitCache;             # create image cache(s) from given description
our $CreateInstSource;      # create installation source from meta packages
our $Upgrade;               # upgrade physical extend
our $Destination;           # destination directory for logical extends
our $RunTestSuite;          # run tests on prepared tree
our @RunTestName;           # run specified tests
our $LogFile;               # optional file name for logging
our $RootTree;              # optional root tree destination
our $Survive;               # if set to "yes" don't exit kiwi
our $BootStick;             # deploy initrd booting from USB stick
our $BootStickSystem;       # system image to be copied on an USB stick
our $BootStickDevice;       # device to install stick image on
our $BootVMSystem;          # system image to be copied on a VM disk
our $BootVMDisk;            # deploy initrd booting from a VM 
our $BootVMSize;            # size of virtual disk
our $InstallCD;             # Installation initrd booting from CD
our $InstallCDSystem;       # virtual disk system image to be installed on disk
our $BootCD;                # Boot initrd booting from CD
our $BootUSB;               # Boot initrd booting from Stick
our $InstallStick;          # Installation initrd booting from USB stick
our $InstallStickSystem;    # virtual disk system image to be installed on disk
our $StripImage;            # strip shared objects and binaries
our $CreateHash;            # create .checksum.md5 for given description
our $SetupSplash;           # setup splash screen (bootsplash or splashy)
our $ImageName;             # filename of current image, used in Modules
our %ForeignRepo;           # may contain XML::LibXML::Element objects
our @AddRepository;         # add repository for building physical extend
our @AddRepositoryType;     # add repository type
our @AddRepositoryAlias;    # alias name for the repository
our @AddRepositoryPriority; # priority for the repository
our @AddPackage;            # add packages to the image package list
our @AddPattern;            # add patterns to the image package list
our $ImageCache;            # build an image cache for later re-use
our @RemovePackage;         # remove package by adding them to the remove list
our $IgnoreRepos;           # ignore repositories specified so far
our $SetRepository;         # set first repository for building physical extend
our $SetRepositoryType;     # set firt repository type
our $SetRepositoryAlias;    # alias name for the repository
our $SetRepositoryPriority; # priority for the repository
our $SetImageType;          # set image type to use, default is primary type
our $Migrate;               # migrate running system to image description
our @Exclude;               # exclude directories in migrate search
our @Skip;                  # skip this package in migration mode
our @Profiles;              # list of profiles to include in image
our @ProfilesOrig;          # copy of original Profiles option value 
our $ForceNewRoot;          # force creation of new root directory
our $CacheRoot;             # Cache file set via selectCache()
our $CacheRootMode;         # Cache mode set via selectCache()
our $NoColor;               # do not used colored output (done/failed messages)
our $LogPort;               # specify alternative log server port
our $GzipCmd;               # command to run to gzip things
our $PrebuiltBootImage;     # directory where a prepared boot image may be found
our $PreChrootCall;         # program name called before chroot switch
our $listXMLInfo;           # list XML information for this operation
our @listXMLInfoSelection;  # info selection for listXMLInfo
our $CreatePassword;        # create crypted password
our $ISOCheck;              # create checkmedia boot entry
our $PackageManager;        # package manager to use for this image
our $FSBlockSize;           # filesystem block size
our $FSInodeSize;           # filesystem inode size
our $FSJournalSize;         # filesystem journal size
our $FSMaxMountCount;       # filesystem (ext2-4) max mount count between checks
our $FSCheckInterval;       # filesystem (ext2-4) max interval between fs checks
our $FSInodeRatio;          # filesystem bytes/inode ratio
our $Verbosity = 0;         # control the verbosity level
our $TargetArch;            # target architecture -> writes zypp.conf
our $CheckKernel;           # check for kernel matches in boot and system image
our $Clone;                 # clone existing image description
our $LVM;                   # use LVM partition setup for virtual disk
our $Debug;                 # activates the internal stack trace output
our $GrubChainload;         # install grub loader in first partition not MBR
our $MigrateNoFiles;        # migrate: don't create overlay files
our $MigrateNoTemplate;     # migrate: don't create image description template
our $Convert;               # convert image into given format/configuration
our $Format;                # format to convert to, vmdk, ovf, etc...
our $defaultAnswer;         # default answer to any questions
our $targetDevice;          # alternative device instead of a loop device
our $kiwi;                  # global logging handler object

#============================================
# Globals
#--------------------------------------------
my $root;       # KIWIRoot  object for installations
my $image;      # KIWIImage object for logical extends
my $boot;       # KIWIBoot  object for logical extends
my $migrate;    # KIWIMigrate object for system to image migration

#============================================
# createDirInteractive
#--------------------------------------------
sub createDirInteractive {
	my $kiwi = shift;
	my $targetDir = shift;
	if (! -d $targetDir) {
		my $prefix = $kiwi -> getPrefix (1);
		my $answer = (defined $defaultAnswer) ? "yes" : "unknown";
		$kiwi -> info ("Destination: $Destination doesn't exist\n");
		while ($answer !~ /^yes$|^no$/) {
			print STDERR $prefix,
				"Would you like kiwi to create it [yes/no] ? ";
			chomp ($answer = <>);
		}
		if ($answer eq "yes") {
			qxx ("mkdir -p $Destination");
			return 1;
		}
	} else {
		# Directory exists
		return 1;
	}
	# Directory does not exist and user did
	# not request dir creation.
	return undef;
}

#============================================
# findExec
#--------------------------------------------
sub findExec {
	my $execName = shift;
	my $execPath = qxx ("which $execName 2>&1"); chomp $execPath;
	my $code = $? >> 8;
	if ($code != 0) {
		if ($kiwi) {
			$kiwi -> loginfo ("warning: $execName not found\n");
		}
		return undef;
	}
	return $execPath;
}

#==========================================
# main
#------------------------------------------
sub main {
	# ...
	# This is the KIWI project to prepare and build operating
	# system images from a given installation source. The system
	# will create a chroot environment representing the needs
	# of a XML control file. Once prepared KIWI can create several
	# OS image types.
	# ---
	#==========================================
	# Initialize and check options
	#------------------------------------------
	if ((! defined $Survive) || ($Survive ne "yes")) {
		init();
	}
	#==========================================
	# Create logger object
	#------------------------------------------
	if (! defined $kiwi) {
		$kiwi = new KIWILog();
	}
	#==========================================
	# remove pre-defined smart channels
	#------------------------------------------
	if (glob ("/etc/smart/channels/*")) {
		qxx ( "rm -f /etc/smart/channels/*" );
	}
	#==========================================
	# Check for nocolor option
	#------------------------------------------
	if (defined $NoColor) {
		$kiwi -> info ("Switching off colored output\n");
		if (! $kiwi -> setColorOff ()) {
			my $code = kiwiExit (1); return $code;
		}
	}
	#==========================================
	# Setup logging location
	#------------------------------------------
	if (defined $LogFile) {
		if ((! defined $Survive) || ($Survive ne "yes")) {
			$kiwi -> info ("Setting log file to: $LogFile\n");
			if (! $kiwi -> setLogFile ( $LogFile )) {
				my $code = kiwiExit (1); return $code;
			}
		}
	}
	#========================================
	# Prepare and Create in one step
	#----------------------------------------
	if (defined $Build) {
		#==========================================
		# Create destdir if needed
		#------------------------------------------
		my $dirCreated = createDirInteractive($kiwi, $Destination);
		if (! defined $dirCreated) {
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Setup prepare 
		#------------------------------------------
		$main::Prepare = $Build;
		$main::RootTree= $Destination."/build/image-root";
		$main::Survive = "yes";
		$main::ForceNewRoot = 1;
		undef $main::Build;
		mkdir $Destination."/build";
		if (! defined main::main()) {
			$main::Survive = "default";
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Setup create 
		#------------------------------------------
		undef $main::Prepare;
		undef $main::ForceNewRoot;
		$main::Survive = "default";
		$main::Create = $RootTree;
		main::main();
	}

	#========================================
	# Create image cache(s)
	#----------------------------------------
	if (defined $InitCache) {
		#==========================================
		# Process system image description
		#------------------------------------------
		$kiwi -> info ("Reading image description [Cache]...\n");
		my $xml = new KIWIXML ($kiwi,$InitCache,\%ForeignRepo,undef,\@Profiles);
		if (! defined $xml) {
			my $code = kiwiExit (1); return $code;
		}
		my %type = %{$xml->getImageTypeAndAttributes()};
		#==========================================
		# Create cache(s)...
		#------------------------------------------
		if (! defined $ImageCache) {
			$ImageCache = $main::InitCDir;
		}
		my $cacheInit = initializeCache($xml,\%type,$InitCache);
		if (! createCache ($xml,$cacheInit)) {
			my $code = kiwiExit (1); return $code;
		}
		kiwiExit (0);
	}

	#========================================
	# Prepare image and build chroot system
	#----------------------------------------
	if (defined $Prepare) {
		#==========================================
		# Process system image description
		#------------------------------------------
		$kiwi -> info ("Reading image description [Prepare]...\n");
		my $xml = new KIWIXML ( $kiwi,$Prepare,\%ForeignRepo,undef,\@Profiles );
		if (! defined $xml) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $xml -> haveMD5File()) {
			$kiwi -> warning ("Description provides no MD5 hash, check");
			$kiwi -> skipped ();
		}
		my %type = %{$xml->getImageTypeAndAttributes()};
		#==========================================
		# Check for bootprofile in xml descr.
		#------------------------------------------
		if (! @Profiles) {
			if ($type{"type"} eq "cpio") {
				if ($type{bootprofile}) {
					push @Profiles, split (/,/,$type{bootprofile});
				}
				if ($type{bootkernel}) {
					push @Profiles, split (/,/,$type{bootkernel});
				}
			}
		}
		#==========================================
		# Check for bootkernel in xml descr.
		#------------------------------------------		
		if ($type{"type"} eq "cpio") {
			my %phash = ();
			my $found = 0;
			my @pname = $xml -> getProfiles();
			foreach my $profile (@pname) {
				my $name = $profile -> {name};
				my $descr= $profile -> {description};
				if ($descr =~ /KERNEL:/) {
					$phash{$name} = $profile -> {description};
				}
			}
			foreach my $profile (@Profiles) {
				if ($phash{$profile}) {
					# /.../
					# ok, a kernel from the profile list is
					# already selected
					# ----
					$found = 1;
					last;
				}
			}
			if (! $found) {
				# /.../
				# no kernel profile selected use standard (std)
				# profile which is defined in each boot image
				# description
				# ----
				push @Profiles, "std";
			}
			if (! $xml -> checkProfiles (\@Profiles)) {
				my $code = kiwiExit (1); return $code;
			}
			my $theme = $xml -> getBootTheme();
			if ($theme) {
				$kiwi -> info ("Using boot theme: $theme");
			} else {
				$kiwi -> warning ("No boot theme set, default is openSUSE");
			}
			$kiwi -> done ();
		}
		#==========================================
		# Check for default root in XML
		#------------------------------------------	
		if (! defined $RootTree) {
			$kiwi -> info ("Checking for default root in XML data...");
			$RootTree = $xml -> getImageDefaultRoot();
			if ($RootTree) {
				if ($RootTree !~ /^\//) {
					my $workingDir = qxx ( "pwd" ); chomp $workingDir;
					$RootTree = $workingDir."/".$RootTree;
				}
				$kiwi -> done();
			} else {
				undef $RootTree;
				$kiwi -> notset();
			}
		}
		#==========================================
		# Check for ignore-repos option
		#------------------------------------------
		if (defined $IgnoreRepos) {
			$xml -> ignoreRepositories ();
		}
		#==========================================
		# Check for set-repo option
		#------------------------------------------
		if (defined $SetRepository) {
			$xml -> setRepository (
				$SetRepositoryType,$SetRepository,
				$SetRepositoryAlias,$SetRepositoryPriority
			);
		}
		#==========================================
		# Check for add-repo option
		#------------------------------------------
		if (defined @AddRepository) {
			$xml -> addRepository (
				\@AddRepositoryType,\@AddRepository,
				\@AddRepositoryAlias,\@AddRepositoryPriority
			);
		}
		#==========================================
		# Check for add-package option
		#------------------------------------------
		if (defined @AddPackage) {
			$xml -> addImagePackages (@AddPackage);
		}
		#==========================================
		# Check for add-pattern option
		#------------------------------------------
		if (defined @AddPattern) {
			$xml -> addImagePatterns (@AddPattern);
		}
		#==========================================
		# Check for del-package option
		#------------------------------------------
		if (defined @RemovePackage) {
			$xml -> addRemovePackages (@RemovePackage);
		}
		#==========================================
		# Check for inheritance
		#------------------------------------------
		if (! $xml -> setupImageInheritance()) {
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Select cache if requested and exists
		#------------------------------------------
		if ($ImageCache) {
			my $cacheInit = initializeCache($xml,\%type,$Prepare);
			selectCache ($xml,$cacheInit);
		}
		#==========================================
		# Initialize root system
		#------------------------------------------
		$root = new KIWIRoot (
			$kiwi,$xml,$Prepare,$RootTree,
			"/base-system",undef,undef,undef,
			$CacheRoot,$CacheRootMode,
			$TargetArch
		);
		if (! defined $root) {
			$kiwi -> error ("Couldn't create root object");
			$kiwi -> failed ();
			my $code = kiwiExit (1); return $code;
		}
		if (! defined $CacheRoot) {
			if (! defined $root -> init ()) {
				$kiwi -> error ("Base initialization failed");
				$kiwi -> failed ();
				$root -> copyBroken();
				undef $root;
				my $code = kiwiExit (1); return $code;
			}
		}
		#==========================================
		# Check for pre chroot call
		#------------------------------------------
		if (defined $PreChrootCall) {
			$kiwi -> info ("Calling pre-chroot program: $PreChrootCall");
			my $path = $root -> getRootPath();
			my $data = qxx ("$PreChrootCall $path 2>&1");
			my $code = $? >> 8;
			if ($code != 0) {
				$kiwi -> failed ();
				$kiwi -> info   ($data);
				$kiwi -> failed ();
				$root -> copyBroken();
				undef $root;
				my $code = kiwiExit (1); return $code;
			} else {
				$kiwi -> loginfo ("$PreChrootCall: $data");
			}
			$kiwi -> done ();
		}
		#==========================================
		# Install root system
		#------------------------------------------
		if (! $root -> install ()) {
			$kiwi -> error ("Image installation failed");
			$kiwi -> failed ();
			$root -> cleanMount ();
			$root -> copyBroken();
			undef $root;
			my $code = kiwiExit (1); return $code;
		}
		if (! $root -> installArchives ()) {
			$kiwi -> error ("Archive installation failed");
			$kiwi -> failed ();
			$root -> cleanMount ();
			$root -> copyBroken();
			undef $root;
			my $code = kiwiExit (1); return $code;
		}
		if (! $root -> setup ()) {
			$kiwi -> error ("Couldn't setup image system");
			$kiwi -> failed ();
			$root -> cleanMount ();
			$root -> copyBroken();
			undef $root;
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Clean up
		#------------------------------------------
		$root -> cleanMount ();
		$root -> cleanBroken();
		undef $root;
		kiwiExit (0);
	}

	#==========================================
	# Create image from chroot system
	#------------------------------------------
	if (defined $Create) {
		#==========================================
		# Check the tree first...
		#------------------------------------------
		if (-f "$Create/.broken") {
			$kiwi -> error  ("Image root tree $Create is broken");
			$kiwi -> failed ();
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Check for bootprofile in xml descr
		#------------------------------------------
		my $xml;
		my %attr;
		my $origcreate = $Create;
		if (! @Profiles) {
			$kiwi -> info ("Reading image description [Create]...\n");
			$xml = new KIWIXML (
				$kiwi,"$Create/image",\%ForeignRepo,$SetImageType
			);
			if (! defined $xml) {
				my $code = kiwiExit (1); return $code;
			}
			%attr = %{$xml->getImageTypeAndAttributes()};
			if (($attr{"type"} eq "cpio") && ($attr{bootprofile})) {
				@Profiles = split (/,/,$attr{bootprofile});
				if (! $xml -> checkProfiles (\@Profiles)) {
					my $code = kiwiExit (1); return $code;
				}
			}
		}
		if (! defined $xml) {
			$kiwi -> info ("Reading image description [Create]...\n");
			$xml = new KIWIXML (
				$kiwi,"$Create/image",undef,$SetImageType,\@Profiles
			);
			if (! defined $xml) {
				my $code = kiwiExit (1); return $code;
			}
			%attr = %{$xml->getImageTypeAndAttributes()};
		}
		#==========================================
		# Check for default destination in XML
		#------------------------------------------
		if (! defined $Destination) {
			$kiwi -> info ("Checking for defaultdestination in XML data...");
			$Destination = $xml -> getImageDefaultDestination();
			if (! $Destination) {
				$kiwi -> failed ();
				$kiwi -> info   ("No destination directory specified");
				$kiwi -> failed ();
				my $code = kiwiExit (1); return $code;
			}
			$kiwi -> done();
		}
		#==========================================
		# Check for ignore-repos option
		#------------------------------------------
		if (defined $IgnoreRepos) {
			$xml -> ignoreRepositories ();
		}
		#==========================================
		# Check for set-repo option
		#------------------------------------------
		if (defined $SetRepository) {
			$xml -> setRepository (
				$SetRepositoryType,$SetRepository,
				$SetRepositoryAlias,$SetRepositoryPriority
			);
		}
		#==========================================
		# Check for add-repo option
		#------------------------------------------
		if (defined @AddRepository) {
			$xml -> addRepository (
				\@AddRepositoryType,\@AddRepository,
				\@AddRepositoryAlias,\@AddRepositoryPriority
			);
		}
		#==========================================
		# Create destdir if needed
		#------------------------------------------
		my $dirCreated = createDirInteractive($kiwi, $Destination);
		if (! defined $dirCreated) {
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Check tool set
		#------------------------------------------
		my $para = checkType ( \%attr );
		if (! defined $para) {
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Check for packages updates if needed
		#------------------------------------------
		my @addonList;   # install this packages
		my @deleteList;  # remove this packages
		my @replAdd;
		my @replDel;
		$xml -> getBaseList();
		@replAdd = $xml -> getReplacePackageAddList();
		@replDel = $xml -> getReplacePackageDelList();
		if (@replAdd) {
			push @addonList,@replAdd;
		}
		if (@replDel) {
			push @deleteList,@replDel;
		}
		$xml -> getInstallList();
		@replAdd = $xml -> getReplacePackageAddList();
		@replDel = $xml -> getReplacePackageDelList();
		if (@replAdd) {
			push @addonList,@replAdd;
		}
		if (@replDel) {
			push @deleteList,@replDel;
		}
		$xml -> getTypeList();
		@replAdd = $xml -> getReplacePackageAddList();
		@replDel = $xml -> getReplacePackageDelList();
		if (@replAdd) {
			push @addonList,@replAdd;
		}
		if (@replDel) {
			push @deleteList,@replDel;
		}
		if (@addonList) {
			my %uniq;
			foreach my $item (@addonList) { $uniq{$item} = $item; }
			@addonList = keys %uniq;
		}
		if (@deleteList) {
			my %uniq;
			foreach my $item (@deleteList) { $uniq{$item} = $item; }
			@deleteList = keys %uniq;
		}
		if ((@addonList) || (@deleteList)) {
			$kiwi -> info ("Image update:");
			if (@addonList) {
				$kiwi -> info ("--> Install/Update: @addonList\n");
			}
			if (@deleteList) {
				$kiwi -> info ("--> Remove: @deleteList\n");
			}
			$main::Survive       = "yes";
			$main::Upgrade       = $main::Create;
			@main::AddPackage    = @addonList;
			@main::RemovePackage = @deleteList;
			my $backupCreate     = $main::Create;
			undef $main::Create;
			if (! defined main::main()) {
				$main::Survive = "default";
				my $code = kiwiExit (1); return $code;
			}
			$main::Survive = "default";
			$main::Create  = $backupCreate;
			undef $main::Upgrade;
		}
		#==========================================
		# Check for overlay structure
		#------------------------------------------
		my $overlay = new KIWIOverlay (
			$kiwi,$Create,$CacheRoot,$CacheRootMode
		);
		if (! defined $overlay) {
			my $code = kiwiExit (1); return $code;
		}
		$Create = $overlay -> mountOverlay();
		if (! defined $Create) {
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Cleanup the tree according to prev runs
		#------------------------------------------
		if (-f "$Create/rootfs.tar") {
			qxx ("rm -f $Create/rootfs.tar");
		}
		if (-f "$Create/recovery.tar.gz") {
			qxx ("rm -f $Create/recovery.*");
		}
		#==========================================
		# Update .profile env, current type
		#------------------------------------------
		$kiwi -> info ("Updating type in .profile environment");
		my $type = $attr{type};
		qxx (
			"sed -i -e 's#kiwi_type=.*#kiwi_type=\"$type\"#' $Create/.profile"
		);
		$kiwi -> done();
		#==========================================
		# Create recovery archive if specified
		#------------------------------------------
		if ($type eq "oem") {
			my $configure = new KIWIConfigure (
				$kiwi,$xml,$Create,$Create."/image",$Destination
			);
			if (! defined $configure) {
				my $code = kiwiExit (1); return $code;
			}
			if (! $configure -> setupRecoveryArchive($attr{filesystem})) {
				my $code = kiwiExit (1); return $code;
			}
		}
		#==========================================
		# Close overlay mount if active
		#------------------------------------------
		undef $overlay;
		$Create  = $origcreate;
		#==========================================
		# Create KIWIImage object
		#------------------------------------------
		$image = new KIWIImage (
			$kiwi,$xml,$Create,$Destination,$StripImage,
			"/base-system",$Create
		);
		if (! defined $image) {
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Initialize logical image extend
		#------------------------------------------
		my $ok;
		SWITCH: for ($attr{type}) {
			/^ext2/     && do {
				$ok = $image -> createImageEXT2 ( $targetDevice );
				last SWITCH;
			};
			/^ext3/     && do {
				$ok = $image -> createImageEXT3 ( $targetDevice );
				last SWITCH;
			};
			/^ext4/     && do {
				$ok = $image -> createImageEXT4 ( $targetDevice );
				last SWITCH;
			};
			/^reiserfs/ && do {
				$ok = $image -> createImageReiserFS ( $targetDevice );
				last SWITCH;
			};
			/^btrfs/    && do {
				$ok = $image -> createImageBTRFS ( $targetDevice );
				last SWITCH;
			};
			/^squashfs/ && do {
				$ok = $image -> createImageSquashFS ();
				last SWITCH;
			};
			/^clicfs/   && do {
				$ok = $image -> createImageClicFS ();
				last SWITCH;
			};
			/^cpio/     && do {
				$ok = $image -> createImageCPIO ();
				last SWITCH;
			};
			/^iso/      && do {
				$ok = $image -> createImageLiveCD ( $para );
				last SWITCH;
			};
			/^split/    && do {
				$ok = $image -> createImageSplit ( $para );
				last SWITCH;
			};
			/^usb/      && do {
				$ok = $image -> createImageUSB ( $para );
				last SWITCH;
			};
			/^vmx/      && do {
				$ok = $image -> createImageVMX ( $para );
				last SWITCH;
			};
			/^oem/      && do {
				$ok = $image -> createImageVMX ( $para );
				last SWITCH;
			};
			/^pxe/      && do {
				$ok = $image -> createImagePXE ( $para );
				last SWITCH;
			};
			/^xfs/    && do {
				$ok = $image -> createImageXFS ();
				last SWITCH;
			};
			$kiwi -> error  ("Unsupported type: $attr{type}");
			$kiwi -> failed ();
			undef $image;
			my $code = kiwiExit (1); return $code;
		}
		undef $image;
		if ($ok) {
			my $code = kiwiExit (0); return $code;
		} else {
			my $code = kiwiExit (1); return $code;
		}
	}

	#==========================================
	# Run test suite on prepared root tree 
	#------------------------------------------
	if (defined $RunTestSuite) {
		#==========================================
		# install testing packages if any
		#------------------------------------------
		$kiwi -> info ("Reading image description [TestSuite]...\n");
		my $xml = new KIWIXML (
			$kiwi,"$RunTestSuite/image",undef,undef,\@Profiles
		);
		if (! defined $xml) {
			my $code = kiwiExit (1); return $code;
		}
		my @testingPackages = $xml -> getTestingList();
		if (@testingPackages) {
			#==========================================
			# Initialize root system, use existing root
			#------------------------------------------
			$root = new KIWIRoot (
				$kiwi,$xml,$RunTestSuite,undef,
				"/base-system",$RunTestSuite,undef,undef,
				$CacheRoot,$CacheRootMode,
				$TargetArch
			);
			if (! defined $root) {
				$kiwi -> error ("Couldn't create root object");
				$kiwi -> failed ();
				my $code = kiwiExit (1); return $code;
			}
			if (! $root -> prepareTestingEnvironment()) {
				$root -> cleanMount ();
				$root -> copyBroken();
				undef $root;
				my $code = kiwiExit (1); return $code;
			}
			if (! $root -> installTestingPackages(\@testingPackages)) {
				$root -> cleanMount ();
				$root -> copyBroken();
				undef $root;
				my $code = kiwiExit (1); return $code;
			}
		}
		#==========================================
		# create package manager for operations
		#------------------------------------------
		my $manager = new KIWIManager (
			$kiwi,$xml,$xml,$RunTestSuite,
			$xml->getPackageManager(),$TargetArch
		);
		#==========================================
		# set default tests if no names are set
		#------------------------------------------
		if (! @RunTestName) {
			@RunTestName = ("rpm","ldd");
		}
		#==========================================
		# run all tests in @RunTestName
		#------------------------------------------
		my $testCount = @RunTestName;
		my $result_success = 0;
		my $result_failed  = 0;
		$kiwi -> info ("Test suite, evaluating ".$testCount." test(s)\n");
		foreach my $run (@RunTestName) {
			my $runtest = $run;
			if ($runtest !~ /^\.*\//) {
				# if test does not begin with '/' or './' add default path
				$runtest = $TestBase."/".$run;
			}
			my $test = new KIWITest (
				$runtest,$RunTestSuite,$SchemaTST,$manager
			);
			my $testResult = $test -> run();
			$kiwi -> info (
				"Testcase ".$test->getName()." - ".$test->getSummary()
			);
			if ($testResult == 0) {
				$kiwi -> done();
				$result_success += 1;
			} else {
				$kiwi -> failed();
				$result_failed +=1;
				my @outputArray = @{$test -> getAllResults()};
				$kiwi -> warning ("Error message : \n");
				my $txtmsg=$test->getOverallMessage();
				$kiwi -> note($txtmsg);
			}
		}
		#==========================================
		# uninstall testing packages
		#------------------------------------------
		if (@testingPackages) {
			if (! $root -> uninstallTestingPackages(\@testingPackages)) {
				$root -> cleanupTestingEnvironment();
				$root -> cleanMount ();
				$root -> copyBroken();
				undef $root;
				my $code = kiwiExit (1); return $code;
			}
			$root -> cleanupTestingEnvironment();
			$root -> cleanMount ();
		}
		#==========================================
		# print test report
		#------------------------------------------	
		if ($result_failed == 0) {
			$kiwi -> info (
				"Tests finished : ".$result_success.
				" test passed, "
			);
			$kiwi -> done();
			$root -> cleanBroken();
			undef $root;
			kiwiExit (0);
		} else {
			$kiwi -> info (
				"Tests finished : ". $result_failed .
				" of ". ($result_failed+$result_success) .
				" tests failed"
			);
			$kiwi -> failed();
			$root -> copyBroken();
			undef $root;
			kiwiExit (1);
		}
	}	

	#==========================================
	# Upgrade image in chroot system
	#------------------------------------------
	if (defined $Upgrade) {
		$kiwi -> info ("Reading image description [Upgrade]...\n");
		my $xml = new KIWIXML (
			$kiwi,"$Upgrade/image",undef,undef,\@ProfilesOrig
		);
		if (! defined $xml) {
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Check for ignore-repos option
		#------------------------------------------
		if (defined $IgnoreRepos) {
			$xml -> ignoreRepositories ();
		}
		#==========================================
		# Check for set-repo option
		#------------------------------------------
		if (defined $SetRepository) {
			$xml -> setRepository (
				$SetRepositoryType,$SetRepository,
				$SetRepositoryAlias,$SetRepositoryPriority
			);
		}
		#==========================================
		# Check for add-repo option
		#------------------------------------------
		if (defined @AddRepository) {
			$xml -> addRepository (
				\@AddRepositoryType,\@AddRepository,
				\@AddRepositoryAlias,\@AddRepositoryPriority
			);
		}
		#==========================================
		# Check for add-pattern option
		#------------------------------------------
		if (defined @AddPattern) {
			foreach my $pattern (@AddPattern) {
				push (@AddPackage,"pattern:$pattern");
			}
		}
		#==========================================
		# Initialize root system, use existing root
		#------------------------------------------
		$root = new KIWIRoot (
			$kiwi,$xml,$Upgrade,undef,
			"/base-system",$Upgrade,\@AddPackage,\@RemovePackage,
			$CacheRoot,$CacheRootMode,
			$TargetArch
		);
		if (! defined $root) {
			$kiwi -> error ("Couldn't create root object");
			$kiwi -> failed ();
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Upgrade root system
		#------------------------------------------
		if (! $root -> upgrade ()) {
			$kiwi -> error ("Image Upgrade failed");
			$kiwi -> failed ();
			$root -> cleanMount ();
			$root -> copyBroken();
			undef $root;
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# clean up
		#------------------------------------------ 
		$root -> cleanMount ();
		$root -> cleanBroken();
		undef $root;
		kiwiExit (0);
	}

	#==========================================
	# Migrate system to image description
	#------------------------------------------
	if (defined $Migrate) {
		$kiwi -> info ("Starting system to image migration");
		$Destination = "/tmp/$Migrate";
		$migrate = new KIWIMigrate (
			$kiwi,$Destination,$Migrate,\@Exclude,\@Skip,
			\@AddRepository,\@AddRepositoryType,
			\@AddRepositoryAlias,\@AddRepositoryPriority
		);
		#==========================================
		# Check object and repo setup, mandatory
		#------------------------------------------
		if (! defined $migrate) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $migrate -> getRepos()) {
			$migrate -> cleanMount();
			my $code = kiwiExit (1); return $code;
		}
		#==========================================
		# Create report HTML file, errors allowed
		#------------------------------------------
		if (! $MigrateNoFiles) {
			$migrate -> setSystemOverlayFiles();
		}
		$migrate -> getPackageList();
		$migrate -> createReport();
		if (! $MigrateNoTemplate) {
			if (! $migrate -> setTemplate()) {
				$migrate -> cleanMount();
				my $code = kiwiExit (1); return $code;
			}
			if (! $migrate -> setPrepareConfigSkript()) {
				$migrate -> cleanMount();
				my $code = kiwiExit (1); return $code;
			}
			if (! $migrate -> setInitialSetup()) {
				$migrate -> cleanMount();
				my $code = kiwiExit (1); return $code;
			}
		}
		$migrate -> cleanMount();
		kiwiExit (0);
	}

	#==========================================
	# setup a splash initrd
	#------------------------------------------
	if (defined $SetupSplash) {
		$boot = new KIWIBoot ($kiwi,$SetupSplash);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		$boot -> setupSplash();
		undef $boot;
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Write a initrd/system image to USB stick
	#------------------------------------------
	if (defined $BootStick) {
		$kiwi -> info ("Creating boot USB stick from: $BootStick...\n");
		$boot = new KIWIBoot (
			$kiwi,$BootStick,$BootStickSystem,undef,
			$BootStickDevice,$LVM
		);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $boot -> setupBootStick()) {
			undef $boot;
			my $code = kiwiExit (1); return $code;
		}
		undef $boot;
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Create a boot Stick (USB)
	#------------------------------------------
	if (defined $BootUSB) {
		$kiwi -> info ("Creating boot USB stick from: $BootUSB...\n");
		$boot = new KIWIBoot ($kiwi,$BootUSB);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $boot -> setupInstallStick()) {
			undef $boot;
			my $code = kiwiExit (1); return $code;
		}
		undef $boot;
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Create a boot CD (ISO)
	#------------------------------------------
	if (defined $BootCD) {
		$kiwi -> info ("Creating boot ISO from: $BootCD...\n");
		$boot = new KIWIBoot ($kiwi,$BootCD);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $boot -> setupInstallCD()) {
			undef $boot;
			my $code = kiwiExit (1); return $code;
		}
		undef $boot;
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Create an install CD (ISO)
	#------------------------------------------
	if (defined $InstallCD) {
		$kiwi -> info ("Creating install ISO from: $InstallCD...\n");
		if (! defined $InstallCDSystem) {
			$kiwi -> error  ("No Install system image specified");
			$kiwi -> failed ();
			my $code = kiwiExit (1);
			return $code;
		}
		$boot = new KIWIBoot ($kiwi,$InstallCD,$InstallCDSystem);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $boot -> setupInstallCD()) {
			undef $boot;
			my $code = kiwiExit (1); return $code;
		}
		undef $boot;
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Create an install USB stick
	#------------------------------------------
	if (defined $InstallStick) {
		$kiwi -> info ("Creating install Stick from: $InstallStick...\n");
		if (! defined $InstallStickSystem) {
			$kiwi -> error  ("No Install system image specified");
			$kiwi -> failed ();
			my $code = kiwiExit (1);
			return $code;
		}
		$boot = new KIWIBoot ($kiwi,$InstallStick,$InstallStickSystem);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $boot -> setupInstallStick()) {
			undef $boot;
			my $code = kiwiExit (1); return $code;
		}
		undef $boot;
		my $code = kiwiExit (0); return $code;
	}

	#==========================================
	# Create a virtual disk image
	#------------------------------------------
	if (defined $BootVMDisk) {
		$kiwi -> info ("Creating boot VM disk from: $BootVMDisk...\n");
		if (! defined $BootVMSystem) {
			$kiwi -> error  ("No VM system image specified");
			$kiwi -> failed ();
			my $code = kiwiExit (1);
			return $code;
		}
		qxx ( "file $BootVMSystem | grep -q 'gzip compressed data'" );
		my $code = $? >> 8;
		if ($code == 0) {
			$kiwi -> failed ();
			$kiwi -> error  ("Can't use compressed VM system");
			$kiwi -> failed ();
			my $code = kiwiExit (1);
			return $code;
		}
		$boot = new KIWIBoot (
			$kiwi,$BootVMDisk,$BootVMSystem,
			$BootVMSize,undef,$LVM,\@ProfilesOrig
		);
		if (! defined $boot) {
			my $code = kiwiExit (1); return $code;
		}
		if (! $boot -> setupBootDisk($targetDevice)) {
			undef $boot;
			my $code = kiwiExit (1); return $code;
		}
		undef $boot;
		$code = kiwiExit (0); return $code;
	}
	
	#==========================================
	# Convert image into format/configuration
	#------------------------------------------
	if (defined $Convert) {
		$kiwi -> info ("Starting image format conversion...\n");
		my $format = new KIWIImageFormat ($kiwi,$Convert,$Format);
		if (! $format) {
			my $code = kiwiExit (1);
			return $code;
		}
		$format -> createFormat();
		$format -> createMaschineConfiguration();
		my $code = kiwiExit (0); return $code;
	}
	return 1;
}

#==========================================
# init
#------------------------------------------
sub init {
	# ...
	# initialize, check privilege and options. KIWI
	# requires you to perform at least one action.
	# An action is either to prepare or create an image
	# ---
	$SIG{"HUP"}      = \&quit;
	$SIG{"TERM"}     = \&quit;
	$SIG{"INT"}      = \&quit;
	my $kiwi = new KIWILog("tiny");
	#==========================================
	# get options and call non-root tasks
	#------------------------------------------
	my $result = GetOptions(
		"version"               => \&version,
		"targetdevice=s"        => \$targetDevice,
		"v|verbose+"            => \$Verbosity,
		"logfile=s"             => \$LogFile,
		"build|b=s"             => \$Build,
		"init-cache=s"          => \$InitCache,
		"prepare|p=s"           => \$Prepare,
		"add-profile=s"         => \@Profiles,
		"migrate|m=s"           => \$Migrate,
		"notemplate"            => \$MigrateNoTemplate,
		"nofiles"               => \$MigrateNoFiles,
		"exclude|e=s"           => \@Exclude,
		"skip=s"                => \@Skip,
		"list|l"                => \&listImage,
		"create|c=s"            => \$Create,
		"testsuite=s"           => \$RunTestSuite,
		"test=s"                => \@RunTestName,
		"create-instsource=s"   => \$CreateInstSource,
		"ignore-repos"          => \$IgnoreRepos,
		"add-repo=s"            => \@AddRepository,
		"add-repotype=s"        => \@AddRepositoryType,
		"add-repoalias=s"       => \@AddRepositoryAlias,
		"add-repopriority=i"    => \@AddRepositoryPriority,
		"add-package=s"         => \@AddPackage,
		"add-pattern=s"         => \@AddPattern,
		"cache=s"               => \$ImageCache,
		"del-package=s"         => \@RemovePackage,
		"set-repo=s"            => \$SetRepository,
		"set-repotype=s"        => \$SetRepositoryType,
		"set-repoalias=s"       => \$SetRepositoryAlias,
		"set-repopriority=i"    => \$SetRepositoryPriority,
		"type|t=s"              => \$SetImageType,
		"upgrade|u=s"           => \$Upgrade,
		"destdir|d=s"           => \$Destination,
		"root|r=s"              => \$RootTree,
		"bootstick=s"           => \$BootStick,
		"bootvm=s"              => \$BootVMDisk,
		"bootstick-system=s"    => \$BootStickSystem,
		"bootstick-device=s"    => \$BootStickDevice,
		"bootvm-system=s"       => \$BootVMSystem,
		"bootvm-disksize=s"     => \$BootVMSize,
		"installcd=s"           => \$InstallCD,
		"installcd-system=s"    => \$InstallCDSystem,
		"bootcd=s"              => \$BootCD,
		"bootusb=s"             => \$BootUSB,
		"installstick=s"        => \$InstallStick,
		"installstick-system=s" => \$InstallStickSystem,
		"strip|s"               => \$StripImage,
		"createpassword"        => \$CreatePassword,
		"isocheck"              => \$ISOCheck,
		"createhash=s"          => \$CreateHash,
		"setup-splash=s"        => \$SetupSplash,
		"force-new-root"        => \$ForceNewRoot,
		"nocolor"               => \$NoColor,
		"log-port=i"            => \$LogPort,
		"gzip-cmd=s"            => \$GzipCmd,
		"package-manager=s"     => \$PackageManager,
		"prebuiltbootimage=s"   => \$PrebuiltBootImage,
		"prechroot-call=s"      => \$PreChrootCall,
		"info|i=s"              => \$listXMLInfo,
		"select=s"              => \@listXMLInfoSelection,
		"fs-blocksize=i"        => \$FSBlockSize,
		"fs-journalsize=i"      => \$FSJournalSize,
		"fs-inodesize=i"        => \$FSInodeSize,
		"fs-inoderatio=i"       => \$FSInodeRatio,
		"fs-max-mount-count=i"  => \$FSMaxMountCount,
		"fs-check-interval=i"   => \$FSCheckInterval,
		"partitioner=s"         => \$Partitioner,
		"target-arch=s"         => \$TargetArch,
		"check-kernel"          => \$CheckKernel,
		"clone|o=s"             => \$Clone,
		"lvm"                   => \$LVM,
		"grub-chainload"        => \$GrubChainload,
		"format|f=s"            => \$Format,
		"convert=s"             => \$Convert,
        "yes|y"                 => \$defaultAnswer,
		"debug"                 => \$Debug,
		"help|h"                => \&usage,
		"<>"                    => \&usage
	);
	#============================================
	# check Partitioner according to device
	#--------------------------------------------
	if (($targetDevice) && ($targetDevice =~ /\/dev\/dasd/)) {
		$Partitioner = "fdasd";
	}
	#========================================
	# turn destdir into absolute path
	#----------------------------------------
	if (defined $Destination) {
		$Destination = File::Spec->rel2abs ($Destination);
	}
	#========================================
	# store original value of Profiles
	#----------------------------------------
	@ProfilesOrig = @Profiles;
	#========================================
	# set default inode ratio for ext2/3
	#----------------------------------------
	if (! defined $FSInodeRatio) {
		$FSInodeRatio = 16384;
	}
	#========================================
	# set default inode size for ext2/3
	#----------------------------------------
	if (! defined $FSInodeSize) {
		$FSInodeSize = 256;
	}
	#==========================================
	# non root task: Create crypted password
	#------------------------------------------
	if (defined $CreatePassword) {
		createPassword();
	}
	#========================================
	# non root task: create inst source
	#----------------------------------------
	if (defined $CreateInstSource) {
		createInstSource();
	}
	#==========================================
	# non root task: create md5 hash
	#------------------------------------------
	if (defined $CreateHash) {
		createHash();
	}
	#==========================================
	# non root task: Clone image 
	#------------------------------------------
	if (defined $Clone) {
		cloneImage();
	}
	#==========================================
	# Check for root privileges
	#------------------------------------------
	if ($< != 0) {
		$kiwi -> error ("Only root can do this");
		$kiwi -> failed ();
		usage();
	}
	if ( $result != 1 ) {
		usage();
	}
	#==========================================
	# Check option combination/values
	#------------------------------------------
	if (
		(! defined $Build)              &&
		(! defined $Prepare)            &&
		(! defined $Create)             &&
		(! defined $InitCache)          &&
		(! defined $BootStick)          &&
		(! defined $InstallCD)          &&
		(! defined $Upgrade)            &&
		(! defined $SetupSplash)        &&
		(! defined $BootVMDisk)         &&
		(! defined $Migrate)            &&
		(! defined $InstallStick)       &&
		(! defined $listXMLInfo)        &&
		(! defined $CreatePassword)     &&
		(! defined $BootCD)             &&
		(! defined $BootUSB)            &&
		(! defined $Clone)              &&
		(! defined $RunTestSuite)       &&
		(! defined $Convert)
	) {
		$kiwi -> error ("No operation specified");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if (($targetDevice) && (! -b $targetDevice)) {
		$kiwi -> error ("Target device $targetDevice doesn't exist");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if ((defined $IgnoreRepos) && (defined $SetRepository)) {
		$kiwi -> error ("Can't use ignore repos together with set repos");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if ((defined @AddRepository) && (! defined @AddRepositoryType)) {
		$kiwi -> error ("No repository type specified");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if ((defined $RootTree) && ($RootTree !~ /^\//)) {
		my $workingDir = qxx ( "pwd" ); chomp $workingDir;
		$RootTree = $workingDir."/".$RootTree;
	}
	if (defined $LogPort) {
		$kiwi -> info ("Setting log server port to: $LogPort");
		$LogServerPort = $LogPort;
		$kiwi -> done ();
	}
	if (defined $GzipCmd) {
		$kiwi -> info ("Setting gzip command to: $GzipCmd");
		$Gzip = $GzipCmd;
		$kiwi -> done ();
	}
	if ((defined $PreChrootCall) && (! -x $PreChrootCall)) {
		$kiwi -> error ("pre-chroot program: $PreChrootCall");
		$kiwi -> failed ();
		$kiwi -> error ("--> 1) no such file or directory\n");
		$kiwi -> error ("--> 2) and/or not in executable format\n");
		my $code = kiwiExit (1); return $code;
	}
	if ((defined $BootStick) && (! defined $BootStickSystem)) {
		$kiwi -> error ("USB stick setup must specify a bootstick-system");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if ((defined $BootVMDisk) && (! defined $BootVMSystem)) {
		$kiwi -> error ("Virtual Disk setup must specify a bootvm-system");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if (defined $Partitioner) {
		if (
			($Partitioner ne "fdisk")  &&
			($Partitioner ne "parted") &&
			($Partitioner ne "fdasd")
		) {
			$kiwi -> error ("Invalid partitioner, expected fdisk|parted");
			$kiwi -> failed ();
			my $code = kiwiExit (1); return $code;
		}
	}
	if ((defined $Build) && (! defined $Destination)) {
		$kiwi -> error  ("No destination directory specified");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if (defined $listXMLInfo) {
		listXMLInfo();
	}
}

#==========================================
# usage
#------------------------------------------
sub usage {
	# ...
	# Explain the available options for this
	# image creation system
	# ---
	my $kiwi = new KIWILog("tiny");
	my $date = qxx ( "bash -c 'LANG=POSIX date -I'" ); chomp $date;
	print "Linux KIWI setup  (image builder) ($date)\n";
	print "Copyright (c) 2007 - SUSE LINUX Products GmbH\n";
	print "\n";

	print "Usage:\n";
	print "    kiwi -l | --list\n";
	print "Image Cloning:\n";
	print "    kiwi -o | --clone <image-path> -d <destination>\n";
	print "Image Creation in one step:\n";
	print "    kiwi -b | --build <image-path> -d <destination>\n";
	print "Image Preparation/Creation in two steps:\n";
	print "    kiwi -p | --prepare <image-path>\n";
	print "       [ --root <image-root> --cache <dir> ]\n";
	print "    kiwi -c | --create  <image-root> -d <destination>\n";
	print "       [ --type <image-type> ]\n";
	print "Image Cache:\n";
	print "    kiwi --image-cache <image-path>\n";
	print "       [ --cache <dir> ]\n";
	print "Image Upgrade:\n";
	print "    kiwi -u | --upgrade <image-root>\n";
	print "       [ --add-package <name> --add-pattern <name> ]\n";
	print "System to Image migration:\n";
	print "    kiwi -m | --migrate <name>\n";
	print "       [ --exclude <directory> --exclude <...> ]\n";
	print "       [ --skip <package> --skip <...> ]\n";
	print "       [ --nofiles --notemplate ]\n";
	print "Image postprocessing modes:\n";
	print "    kiwi --bootstick <initrd> --bootstick-system <systemImage>\n";
	print "       [ --bootstick-device <device> ]\n";
	print "    kiwi --bootvm <initrd> --bootvm-system <systemImage>\n";
	print "       [ --bootvm-disksize <size> ]\n";
	print "    kiwi --bootcd  <initrd>\n";
	print "    kiwi --bootusb <initrd>\n";
	print "    kiwi --installcd <initrd>\n";
	print "       [ --installcd-system <vmx-system-image> ]\n";
	print "    kiwi --installstick <initrd>\n";
	print "       [ --installstick-system <vmx-system-image> ]\n";
	print "Image format conversion:\n";
	print "    kiwi --convert <systemImage> [ --format <vmdk|ovf|qcow2> ]\n";
	print "Testsuite:\n";
	print "    kiwi --testsuite <image-root> \n";
	print "       [ --test name --test name ... ]\n";
	print "Helper Tools:\n";
	print "    kiwi --createpassword\n";
	print "    kiwi --createhash <image-path>\n";
	print "    kiwi --info <image-path> --select <\n";
	print "           repo-patterns|patterns|types|sources|\n";
	print "           size|profiles|packages\n";
	print "         > --select ...\n";
	print "    kiwi --setup-splash <initrd>\n";
	print "\n";

	print "Global Options:\n";
	print "    [ --add-profile <profile-name> ]\n";
	print "      Use the specified profile.\n";
	print "\n";
	print "    [ --set-repo <URL> ]\n";
	print "      Set/Overwrite repo URL for the first listed repo.\n";
	print "\n";
	print "    [ --set-repoalias <name> ]\n";
	print "      Set/Overwrite alias name for the first listed repo.\n";
	print "\n";
	print "    [ --set-repoprio <number> ]\n";
	print "      Set/Overwrite priority for the first listed repo.\n";
	print "      Works with the smart packagemanager only\n";
	print "\n";
	print "    [ --set-repotype <type> ]\n";
	print "      Set/Overwrite repo type for the first listed repo.\n";
	print "\n";
	print "    [ --add-repo <repo-path> --add-repotype <type> ]\n";
	print "      [ --add-repotype <type> ]\n";
	print "      [ --add-repoalias <name> ]\n";
	print "      [ --add-repoprio <number> ]\n";
	print "      Add the repository to the list of repos.\n";
	print "\n";
	print "    [ --ignore-repos ]\n";
	print "      Ignore all repos specified so-far, in XML or otherwise.\n";
	print "\n";
	print "    [ --logfile <filename> | terminal ]\n";
	print "      Write to the log file \`<filename>'\n";
	print "\n";
	print "    [ --gzip-cmd <cmd> ]\n";
	print "      Specify an alternate gzip command\n";
	print "\n";
	print "    [ --log-port <port-number> ]\n";
	print "      Set the log server port. By default port 9000 is used.\n";
	print "\n";
	print "    [ --package-manager <smart|zypper> ]\n";
	print "      Set the package manager to use for this image.\n";
	print "\n";
	print "    [ -A | --target-arch <i586|x86_64|armv5tel|ppc> ]\n";
	print "      Set a special target-architecture. This overrides the \n";
	print "      used architecture for the image-packages in zypp.conf.\n";
	print "      When used with smart this option doesn't have any effect.\n";
	print "\n";
	print "    [ --debug ]\n";
	print "      Prints a stack trace in case of internal errors\n";
	print "\n";
	print "    [ -v | --verbose <1|2|3> ]\n";
	print "      Controls the verbosity level for the instsource module\n";
	print "\n";
	print "    [ -y | --yes ]\n";
	print "      Answer any interactive questions with yes\n";
	print "\n";

	print "Image Preparation Options:\n";
	print "    [ -r | --root <image-root> ]\n";
	print "      Use the given directory as new image root path\n";
	print "\n";
	print "    [ --force-new-root ]\n";
	print "      Force creation of new root directory. If the directory\n";
	print "      already exists, it is deleted.\n";
	print "\n";

	print "Image Upgrade/Preparation Options:\n";
	print "    [ --add-package <package> ]\n";
	print "      Adds the given package name to the list of image packages.\n";
	print "\n";
	print "    [ --add-pattern <name> ]\n";
	print "      Adds the given pattern name to the list of image patters.\n";
	print "\n";
	print "    [ --del-package <package> ]\n";
	print "      Removes the given package by adding it the list of packages\n";
	print "      to become removed.\n";
	print "\n";

	print "Image Creation Options:\n";
	print "    [ -d | --destdir <destination-path> ]\n";
	print "      Specify destination directory to store the image file(s)\n";
	print "\n";
	print "    [ -t | --type <image-type> ]\n";
	print "      Specify the output image type. The selected type must be\n";
	print "      part of the XML description\n";
	print "\n";
	print "    [ -s | --strip ]\n";
	print "      Strip shared objects and executables.\n";
	print "\n";
	print "    [ --prebuiltbootimage <directory> ]\n";
	print "      search in <directory> for pre-built boot images\n";
	print "\n";
	print "    [ --isocheck ]\n";
	print "      in case of an iso image the checkmedia program generates\n";
	print "      a md5sum into the iso header. If the --isocheck option is\n";
	print "      specified a new boot menu entry will be generated which\n";
	print "      allows to check this media\n";
	print "\n";
	print "    [ --lvm ]\n";
	print "      use the logical volume manager for disk images\n";
	print "\n";
	print "    [ --fs-blocksize <number> ]\n";
	print "      Set the block size in Bytes. For ramdisk based ISO images\n";
	print "      a blocksize of 4096 bytes is required\n";
	print "\n";
	print "    [ --fs-journalsize <number> ]\n";
	print "      Set the journal size in MB for ext[23] based filesystems\n";
	print "      and in blocks if the reiser filesystem is used\n"; 
	print "\n";
	print "    [ --fs-inodesize <number> ]\n";
	print "      Set the inode size in Bytes. This option has no effect\n";
	print "      if the reiser filesystem is used\n";
	print "\n";
	print "    [ --fs-inoderatio <number> ]\n";
	print "      Set the bytes/inode ratio. This option has no\n";
	print "      effect if the reiser filesystem is used\n";
	print "\n";
	print "    [ --fs-max-mount-count <number> ]\n";
	print "      Set the number of mounts after which the filesystem will\n";
	print "      be checked for ext[234]. Set to 0 to disable checks.\n";
	print "\n";
	print "    [ --fs-check-interval <number> ]\n";
	print "      Set the maximal time between two filesystem checks for ext[234].\n";
	print "      Set to 0 to disable time-dependent checks.\n";
	print "\n";
	print "    [ --partitioner <fdisk|parted> ]\n";
	print "      Select the tool to create partition tables. Supported are\n";
	print "      fdisk (sfdisk) and parted. By default fdisk is used\n";
	print "\n";
	print "    [ --check-kernel ]\n";
	print "      Activates check for matching kernels between boot and\n";
	print "      system image. The kernel check also tries to fix the boot\n";
	print "      image if no matching kernel was found.\n";
	print "--\n";
	version();
}

#==========================================
# listImage
#------------------------------------------
sub listImage {
	# ...
	# list known image descriptions and exit
	# ---
	my $kiwi = new KIWILog("tiny");
	opendir (FD,$System);
	my @images = readdir (FD); closedir (FD);
	foreach my $image (@images) {
		if ($image =~ /^\./) {
			next;
		}
		if (-l "$System/$image") {
			next;
		}
		if (getControlFile ($System."/".$image)) {
			$kiwi -> info ($image);
			my $xml = new KIWIXML ( $kiwi,$System."/".$image);
			if (! $xml) {
				next;
			}
			my $version = $xml -> getImageVersion();
			$kiwi -> note (" -> Version: $version");
			$kiwi -> done();
		}
	}
	exit 0;
}

#==========================================
# listXMLInfo
#------------------------------------------
sub listXMLInfo {
	# ...
	# print information about the XML description. The
	# information listed here is for information only
	# before a prepare and/or create command is called
	# ---
	my $internal = shift;
	my %select;
	my $gotselection = 0;
	my $meta;
	my $delete;
	my $solfile;
	my $satlist;
	my $solp;
	my $rpat;
	#==========================================
	# Create info block description
	#------------------------------------------
	$select{"repo-patterns"} = "List available patterns from repos";
	$select{"patterns"}      = "List configured patterns";
	$select{"types"}         = "List configured types";
	$select{"sources"}       = "List configured source URLs";
	$select{"size"}          = "List install/delete size estimation";
	$select{"packages"}      = "List of packages to become installed";
	$select{"profiles"}      = "List profiles";
	#==========================================
	# Create log object
	#------------------------------------------
	$kiwi = new KIWILog("tiny");
	#==========================================
	# Setup logging location
	#------------------------------------------
	if (defined $LogFile) {
		if ((! defined $Survive) || ($Survive ne "yes")) {
			$kiwi -> info ("Setting log file to: $LogFile\n");
			if (! $kiwi -> setLogFile ( $LogFile )) {
				exit 1;
			}
		}
	}
	#==========================================
	# Check selection list
	#------------------------------------------
	foreach my $info (@listXMLInfoSelection) {
		if (defined $select{$info}) {
			$gotselection = 1; last;
		}
	}
	if (! $gotselection) {
		$kiwi -> error  ("Can't find info for given selection");
		$kiwi -> failed ();
		$kiwi -> info   ("Choose between the following:\n");
		foreach my $info (keys %select) {
			my $s = sprintf ("--> %-15s:%s\n",$info,$select{$info});
			$kiwi -> info ($s); 
		}
		exit 1;
	}
	$kiwi -> info ("Reading image description [ListXMLInfo]...\n");
	my $xml  = new KIWIXML ($kiwi,$listXMLInfo,undef,undef,\@Profiles);
	if (! defined $xml) {
		exit 1;
	}
	#==========================================
	# Check for ignore-repos option
	#------------------------------------------
	if (defined $IgnoreRepos) {
		$xml -> ignoreRepositories ();
	}
	#==========================================
	# Check for set-repo option
	#------------------------------------------
	if (defined $SetRepository) {
		$xml -> setRepository (
			$SetRepositoryType,$SetRepository,
			$SetRepositoryAlias,$SetRepositoryPriority
		);
	}
	#==========================================
	# Check for add-repo option
	#------------------------------------------
	if (defined @AddRepository) {
		$xml -> addRepository (
			\@AddRepositoryType,\@AddRepository,
			\@AddRepositoryAlias,\@AddRepositoryPriority
		);
	}
	#==========================================
	# Setup loop sources
	#------------------------------------------
	my @mountInfolist = ();
	if ($xml->{urlhash}) {
		foreach my $source (keys %{$xml->{urlhash}}) {
			#==========================================
			# iso:// sources
			#------------------------------------------
			if ($source =~ /^iso:\/\/(.*)/) {
				my $iso  = $1;
				my $dir  = $xml->{urlhash}->{$source};
				my $data = qxx ("mkdir -p $dir; mount -o loop $iso $dir 2>&1");
				my $code = $? >> 8;
				if ($code != 0) {
					$kiwi -> failed ();
					$kiwi -> error  ("Failed to loop mount ISO path: $data");
					$kiwi -> failed ();
					rmdir $dir;
					exit 1;
				}
				push (@mountInfolist,$dir);
			}
		}
	}
	sub newCleanMount {
		my @list = shift;
		return sub {
			foreach my $dir (@list) {
				next if ! defined $dir;
				qxx ("umount $dir ; rmdir $dir 2>&1");
			}
		}
	}
	*cleanInfoMount = newCleanMount (@mountInfolist);
	#==========================================
	# Initialize XML imagescan element
	#------------------------------------------
	my $scan = new XML::LibXML::Element ("imagescan");
	#==========================================
	# Walk through selection list
	#------------------------------------------
	foreach my $info (@listXMLInfoSelection) {
		SWITCH: for ($info) {
			#==========================================
			# repo-patterns
			#------------------------------------------
			/^repo-patterns/ && do {
				if (! $meta) {
					($meta,$delete,$solfile,$satlist,$solp,$rpat) =
						$xml->getInstallSize();
					if (! $meta) {
						$kiwi -> failed();
						cleanInfoMount();
						exit 1;
					}
				}
				if (! $rpat) {
					$kiwi -> info ("No patterns in repo solvable\n");
				} else {
					foreach my $p (@{$rpat}) {
						next if ($p eq "\n");
						$p =~ s/^\s+//;
						$p =~ s/\s+$//;
						my $pattern = new XML::LibXML::Element ("repopattern");
						$pattern -> setAttribute ("name","$p");
						$scan -> appendChild ($pattern);
					}
				}
				last SWITCH;
			};
			#==========================================
			# patterns
			#------------------------------------------
			/^patterns/      && do {
				if (! $meta) {
					($meta,$delete,$solfile,$satlist,$solp) =
						$xml->getInstallSize();
					if (! $meta) {
						$kiwi -> failed();
						cleanInfoMount();
						exit 1;
					}
				}
				if (! keys %{$meta}) {
					$kiwi -> info ("No packages/patterns solved\n");
				} else {
					foreach my $p (sort keys %{$meta}) {
						if ($p =~ /pattern:(.*)/) {
							my $name = $1;
							my $pattern = new XML::LibXML::Element ("pattern");
							$pattern -> setAttribute ("name","$name");
							$scan -> appendChild ($pattern);
						}
					}
				}
				last SWITCH;
			};
			#==========================================
			# types
			#------------------------------------------
			/^types/         && do {
				foreach my $t ($xml -> getTypes()) {
					my %type = %{$t};
					my $type = new XML::LibXML::Element ("type");
					$type -> setAttribute ("name","$type{type}");
					$type -> setAttribute ("primary","$type{primary}");
					if (defined $type{boot}) {
						$type -> setAttribute ("boot","$type{boot}");
					}
					$scan -> appendChild ($type);
				}
				last SWITCH;
			};
			#==========================================
			# sources
			#------------------------------------------
			/^sources/       && do {
				foreach my $url (@{$xml->{urllist}}) {
					my $source = new XML::LibXML::Element ("source");
					$source -> setAttribute ("path","$url");
					$scan -> appendChild ($source);
				}
				last SWITCH;
			};
			#==========================================
			# size
			#------------------------------------------
			/^size/          && do {
				if (! $meta) {
					($meta,$delete,$solfile,$satlist,$solp) =
						$xml->getInstallSize();
					if (! $meta) {
						$kiwi -> failed();
						cleanInfoMount();
						exit 1;
					}
				}
				my $size = 0;
				my %meta = %{$meta};
				foreach my $p (keys %meta) {
					my @metalist = split (/:/,$meta{$p});
					$size += $metalist[0];
				}
				my $sizenode = new XML::LibXML::Element ("size");
				if ($size > 0) {
					$sizenode -> setAttribute ("rootsizeKB","$size");
				}
				$size = 0;
				if ($delete) {
					foreach my $del (@{$delete}) {
						if ($meta{$del}) {
							my @metalist = split (/:/,$meta{$del});
							$size += $metalist[0];
						}
					}
				}
				if ($size > 0) {
					$sizenode -> setAttribute ("deletionsizeKB","$size");
				}
				$scan -> appendChild ($sizenode);
				last SWITCH;
			};
			#==========================================
			# packages
			#------------------------------------------
			/^packages/     && do {
				if (! $meta) {
					($meta,$delete,$solfile,$satlist,$solp) =
						$xml->getInstallSize();
					if (! $meta) {
						$kiwi -> failed();
						cleanInfoMount();
						exit 1;
					}
				}
				if (! keys %{$meta}) {
					$kiwi -> info ("No packages/patterns solved\n");
				} else {
					foreach my $p (sort keys %{$meta}) {
						if ($p =~ /pattern:.*/) {
							next;
						}
						my @m = split (/:/,$meta->{$p});
						my $pacnode = new XML::LibXML::Element ("package");
						$pacnode -> setAttribute ("name","$p");
						$pacnode -> setAttribute ("arch","$m[1]");
						$pacnode -> setAttribute ("version","$m[2]");
						$scan -> appendChild ($pacnode);
					}
				}
				last SWITCH;
			};
			#==========================================
			# profiles
			#------------------------------------------
			/^profiles/      && do {
				my @profiles = $xml -> getProfiles ();
				if ((scalar @profiles) == 0) {
					$kiwi -> info ("No profiles available\n");
				} else {
					foreach my $profile (@profiles) {
						my $name = $profile -> {name};
						my $desc = $profile -> {description};
						my $pnode = new XML::LibXML::Element ("profile");
						$pnode -> setAttribute ("name","$name");
						$pnode -> setAttribute ("description","$desc");
						$scan -> appendChild ($pnode);
					}
				}
				last SWITCH;
			};
		}
	}
	#==========================================
	# Cleanup mount list
	#------------------------------------------
	cleanInfoMount();
	#==========================================
	# print scan results
	#------------------------------------------
	if ($internal) {
		return $scan;
	} else {
		open (my $F, "|xsltproc $main::Pretty -");
		print $F $scan->toString();
		close $F;
		exit 0;
	}
}

#==========================================
# cloneImage
#------------------------------------------
sub cloneImage {
	# ...
	# clone an existing image description by copying
	# the tree to the given destination the possibly
	# existing checksum will be removed as we assume
	# that the clone will be changed
	# ----
	my $answer = "unknown";
	#==========================================
	# Check destination definition
	#------------------------------------------
	my $kiwi = new KIWILog("tiny");
	if (! defined $Destination) {
		$kiwi -> error  ("No destination directory specified");
		$kiwi -> failed ();
		kiwiExit (1);
	} else {
		$kiwi -> info ("Cloning image $Clone -> $Destination...");
	}
	#==========================================
	# Evaluate image path or name 
	#------------------------------------------
	if (($Clone !~ /^\//) && (! -d $Clone)) {
		$Clone = $main::System."/".$Clone;
	}
	my $cfg = $Clone."/".$main::ConfigName;
	my $md5 = $Destination."/.checksum.md5";
	if (! -f $cfg) {
		my @globsearch = glob ($Clone."/*.kiwi");
		my $globitems  = @globsearch;
		if ($globitems == 0) {
			$kiwi -> failed ();
			$kiwi -> error ("Cannot find control file: $cfg");
			$kiwi -> failed ();
			kiwiExit (1);
		} elsif ($globitems > 1) {
			$kiwi -> failed ();
			$kiwi -> error ("Found multiple *.kiwi control files");
			$kiwi -> failed ();
			kiwiExit (1);
		} else {
			$cfg = pop @globsearch;
		}
	}
	#==========================================
	# Check if destdir exists or not 
	#------------------------------------------
	if (! -d $Destination) {
		my $prefix = $kiwi -> getPrefix (1);
		$kiwi -> note ("\n");
		$kiwi -> info ("Destination: $Destination doesn't exist\n");
		while ($answer !~ /^yes$|^no$/) {
			print STDERR $prefix,
				"Would you like kiwi to create it [yes/no] ? ";
			chomp ($answer = <>);
		}
		if ($answer eq "yes") {
			qxx ("mkdir -p $Destination");
		} else {
			kiwiExit (1);
		}
	}
	#==========================================
	# Copy path to destination 
	#------------------------------------------
	my $data = qxx ("cp -a $Clone/* $Destination 2>&1");
	my $code = $? >> 8;
	if ($code != 0) {
		$kiwi -> failed ();
		$kiwi -> error ("Failed to copy $Clone: $data");
		$kiwi -> failed ();
		kiwiExit (1);
	}
	#==========================================
	# Remove checksum 
	#------------------------------------------
	if (-f $md5) {
		qxx ("rm -f $md5 2>&1");
	}
	if ($answer ne "yes") {
		$kiwi -> done();
	}
	kiwiExit (0);
}

#==========================================
# exit
#------------------------------------------
sub kiwiExit {
	# ...
	# private Exit function, exit safely
	# ---
	my $code = $_[0];
	#==========================================
	# Write temporary XML changes to logfile
	#------------------------------------------
	if (defined $kiwi) {
		$kiwi -> writeXML();
	}
	#==========================================
	# Survive because kiwi called itself
	#------------------------------------------
	if ((defined $Survive) && ($Survive eq "yes")) {
		if ($code != 0) {
			return undef;
		}
		return $code;
	}
	#==========================================
	# Create log object if we don't have one...
	#------------------------------------------
	if (! defined $kiwi) {
		$kiwi = new KIWILog("tiny");
	}
	#==========================================
	# Reformat log file for human readers...
	#------------------------------------------
	$kiwi -> setLogHumanReadable();
	#==========================================
	# Check for backtrace and clean flag...
	#------------------------------------------
	if ($code != 0) {
		if (defined $Debug) {
			$kiwi -> printBackTrace();
		}
		$kiwi -> printLogExcerpt();
		$kiwi -> error  ("KIWI exited with error(s)");
		$kiwi -> done ();
	} else {
		$kiwi -> info ("KIWI exited successfully");
		$kiwi -> done ();
	}
	#==========================================
	# Move process log to final logfile name...
	#------------------------------------------
	$kiwi -> finalizeLog();
	#==========================================
	# Cleanup and exit now...
	#------------------------------------------
	$kiwi -> cleanSweep();
	exit $code;
}

#==========================================
# quit
#------------------------------------------
sub quit {
	# ...
	# signal received, exit safely
	# ---
	if (! defined $kiwi) {
		$kiwi = new KIWILog("tiny");
	} else {
		$kiwi -> reopenRootChannel();
	}
	$kiwi -> note ("\n*** $$: Received signal $_[0] ***\n");
	$kiwi -> setLogHumanReadable();
	$kiwi -> cleanSweep();
	if (defined $CreatePassword) {
		system "stty echo";
	}
	if (defined $boot) {
		$boot -> cleanLoop ();
	}
	if (defined $root) {
		$root  -> copyBroken  ();
		$root  -> cleanLock   ();
		$root  -> cleanManager();
		$root  -> cleanSource ();
		$root  -> cleanMount  ();
	}
	if (defined $image) {
		$image -> cleanMount ();
		$image -> restoreCDRootData ();
		$image -> restoreSplitExtend ();
	}
	if (defined $migrate) {
		$migrate -> cleanMount ();
	}
	exit 1;
}

#==========================================
# version
#------------------------------------------
sub version {
	# ...
	# Version information
	# ---
	if (! defined $kiwi) {
		$kiwi = new KIWILog("tiny");
	}
	my $rev  = "unknown";
	if (open FD,$Revision) {
		$rev = <FD>; close FD;
	}
	$kiwi -> info ("kiwi version v$Version\nGIT Commit: $rev\n");
	$kiwi -> cleanSweep();
	exit 0;
}

#==========================================
# createPassword
#------------------------------------------
sub createPassword {
	# ...
	# Create a crypted password which can be used in the xml descr.
	# users sections. The crypt() call requires root rights because
	# dm-crypt is used to access the crypto pool
	# ----
	my $pwd = shift;
	my @legal_enc = ('.', '/', '0'..'9', 'A'..'Z', 'a'..'z');
	if (! defined $kiwi) {
		$kiwi = new KIWILog("tiny");
	}
	my $word2 = 2;
	my $word1 = 1;
	my $tmp = (time + $$) % 65536;
	my $salt;
	srand ($tmp);
	$salt = $legal_enc[sprintf "%u", rand (@legal_enc)];
	$salt.= $legal_enc[sprintf "%u", rand (@legal_enc)];
	if (defined $pwd) {
		$word1 = $word2 = $pwd;
	}
	while ($word1 ne $word2) {
		$kiwi -> info ("Enter Password: ");
		system "stty -echo";
		chomp ($word1 = <STDIN>);
		system "stty echo";
		$kiwi -> done ();
		$kiwi -> info ("Reenter Password: ");
		system "stty -echo";
		chomp ($word2 = <STDIN>);
		system "stty echo";
		if ( $word1 ne $word2 ) {
			$kiwi -> failed ();
			$kiwi -> info ("*** Passwords differ, please try again ***");
			$kiwi -> failed ();
		}
	}
	my $encrypted = crypt ($word1, $salt);
	if (defined $pwd) {
		return $encrypted;
	}
	$kiwi -> done ();
	$kiwi -> info ("Your password:\n\t$encrypted\n");
	my $code = kiwiExit (0); return $code;
}
#==========================================
# createHash
#------------------------------------------
sub createHash {
	# ...
	# Sign your image description with a md5 sum. The created
	# file .checksum.md5 is checked on runtime with the md5sum
	# command
	# ----
	if (! defined $kiwi) {
		$kiwi = new KIWILog("tiny");
	}
	$kiwi -> info ("Creating MD5 sum for $CreateHash...");
	if (! -d $CreateHash) {
		$kiwi -> failed ();
		$kiwi -> error  ("Not a directory: $CreateHash: $!");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	if (! getControlFile ($CreateHash)) {
		$kiwi -> failed ();
		$kiwi -> error  ("Not a kiwi description: no xml description found");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	my $cmd  = "find -L -type f | grep -v .svn | grep -v .checksum.md5";
	my $status = qxx (
		"cd $CreateHash && $cmd | xargs md5sum > .checksum.md5"
	);
	my $result = $? >> 8;
	if ($result != 0) {
		$kiwi -> error  ("Failed creating md5 sum: $status: $!");
		$kiwi -> failed ();
	}
	$kiwi -> done();
	my $code = kiwiExit (0); return $code;
}

#==========================================
# checkType
#------------------------------------------
sub checkType {
	my (%type) = %{$_[0]};
	my $para   = "ok";
	#==========================================
	# check for required filesystem tool(s)
	#------------------------------------------
	my $type  = $type{type};
	my $flags = $type{flags};
	my $fs    = $type{filesystem};
	if (($flags) || ($fs)) {
		my @fs = ();
		if (($flags) && ($type eq "iso")) {
			push (@fs,$type{flags});
		} else {
			@fs = split (/,/,$type{filesystem});
		}
		foreach my $fs (@fs) {
			my %result = checkFileSystem ($fs);
			if (%result) {
				if (! $result{hastool}) {
					$kiwi -> error (
						"Can't find filesystem tool for: $result{type}"
					);
					$kiwi -> failed ();
					return undef;
				}
			} else {
				$kiwi -> error ("Can't check filesystem attributes from: $fs");
				$kiwi -> failed ();
				return undef;
			}
		}
	}
	#==========================================
	# build and check KIWIImage method params
	#------------------------------------------
	SWITCH: for ($type{type}) {
		/^iso/ && do {
			if (! defined $type{boot}) {
				$kiwi -> error ("$type{type}: No boot image specified");
				$kiwi -> failed ();
				return undef;
			}
			$para = $type{boot};
			if ((defined $type{flags}) && ($type{flags} ne "")) {
				$para .= ",$type{flags}";
			} 
			last SWITCH;
		};
		/^split/ && do {
			if (! defined $type{filesystem}) {
				$kiwi -> error ("$type{type}: No filesystem pair specified");
				$kiwi -> failed ();
				return undef;
			}
			$para = $type{filesystem};
			if (defined $type{boot}) {
				$para .= ":".$type{boot};
			}
			last SWITCH;
		};
		/^usb|vmx|oem|pxe/ && do {
			if (! defined $type{filesystem}) {
				$kiwi -> error ("$type{type}: No filesystem specified");
				$kiwi -> failed ();
				return undef;
			}
			if (! defined $type{boot}) {
				$kiwi -> error ("$type{type}: No boot image specified");
				$kiwi -> failed ();
				return undef;
			}
			$para = $type{filesystem}.":".$type{boot};
			last SWITCH;
		};
	}
	return $para;
}

#==========================================
# checkFSOptions
#------------------------------------------
sub checkFSOptions {
	# /.../
	# checks the $FS* option values and build an option
	# string for the relevant filesystems
	# ---
	my %result = ();
	my $fs_maxmountcount;
	my $fs_checkinterval;
	foreach my $fs (keys %KnownFS) {
		my $blocksize;   # block size in bytes
		my $journalsize; # journal size in MB (ext) or blocks (reiser)
		my $inodesize;   # inode size in bytes (ext only)
		my $inoderatio;  # bytes/inode ratio
		my $fsfeature;   # filesystem features (ext only)
		SWITCH: for ($fs) {
			#==========================================
			# EXT2-4
			#------------------------------------------
			/ext[432]/   && do {
				if ($FSBlockSize)   {$blocksize   = "-b $FSBlockSize"}
				if (($FSInodeSize) && ($FSInodeSize != 256)) {
					$inodesize = "-I $FSInodeSize"
				}
				if ($FSInodeRatio)  {$inoderatio  = "-i $FSInodeRatio"}
				if ($FSJournalSize) {$journalsize = "-J size=$FSJournalSize"}
				if ($FSMaxMountCount) {
					$fs_maxmountcount = " -c $FSMaxMountCount";
				}
				if ($FSCheckInterval) {
					$fs_checkinterval = " -i $FSCheckInterval";
				}
				$fsfeature = "-F -O resize_inode";
				last SWITCH;
			};
			#==========================================
			# reiserfs
			#------------------------------------------
			/reiserfs/  && do {
				if ($FSBlockSize)   {$blocksize   = "-b $FSBlockSize"}
				if ($FSJournalSize) {$journalsize = "-s $FSJournalSize"}
				last SWITCH;
			};
			# no options for this filesystem...
		};
		if (defined $inodesize) {
			$result{$fs} .= $inodesize." ";
		}
		if (defined $inoderatio) {
			$result{$fs} .= $inoderatio." ";
		}
		if (defined $blocksize) {
			$result{$fs} .= $blocksize." ";
		}
		if (defined $journalsize) {
			$result{$fs} .= $journalsize." ";
		}
		if (defined $fsfeature) {
			$result{$fs} .= $fsfeature." ";
		}
	}
	if ($fs_maxmountcount || $fs_checkinterval) {
		$result{extfstune} = "$fs_maxmountcount$fs_checkinterval";
	}
	return %result;
}

#==========================================
# mount
#------------------------------------------
sub mount {
	# /.../
	# implements a generic mount function for all supported
	# file system types
	# ---
	my $source= shift;
	my $dest  = shift;
	my $salt  = int (rand(20));
	my %fsattr = main::checkFileSystem ($source);
	my $type   = $fsattr{type};
	my $cipher = $main::LuksCipher;
	my $status;
	my $result;
	#==========================================
	# Check result of filesystem detection
	#------------------------------------------
	if (! %fsattr) {
		$kiwi -> error  ("Couldn't detect filesystem on: $source");
		$kiwi -> failed ();
		return undef;
	}
	#==========================================
	# Check for DISK file
	#------------------------------------------
	if (-f $source) {
		my $boot = "'boot sector'";
		my $null = "/dev/null";
		$status= qxx (
			"dd if=$source bs=512 count=1 2>$null|file - | grep -q $boot"
		);
		$result= $? >> 8;
		if ($result == 0) {			
			$status = qxx ("/sbin/losetup -s -f $source 2>&1"); chomp $status;
			$result = $? >> 8;
			if ($result != 0) {
				$kiwi -> error  (
					"Couldn't loop bind disk file: $status"
				);
				$kiwi -> failed (); umount();
				return undef;
			}
			my $loop = $status;
			push @UmountStack,"losetup -d $loop";
			$status = qxx ("kpartx -a $loop 2>&1");
			$result = $? >> 8;
			if ($result != 0) {
				$kiwi -> error (
					"Couldn't loop bind disk partition(s): $status"
				);
				$kiwi -> failed (); umount();
				return undef;
			}
			push @UmountStack,"kpartx -d $loop";
			$loop =~ s/\/dev\///;
			$source = "/dev/mapper/".$loop."p1";
			if (! -b $source) {
				$kiwi -> error ("No such block device $source");
				$kiwi -> failed (); umount();
				return undef;
			}
		}
	}
	#==========================================
	# Check for LUKS extension
	#------------------------------------------
	if ($type eq "luks") {
		if (-f $source) {
			$status = qxx ("/sbin/losetup -s -f $source 2>&1"); chomp $status;
			$result = $? >> 8;
			if ($result != 0) {
				$kiwi -> error  ("Couldn't loop bind logical extend: $status");
				$kiwi -> failed (); umount();
				return undef;
			}
			$source = $status;
			push @UmountStack,"losetup -d $source";
		}
		if ($cipher) {
			$status = qxx (
				"echo $cipher | cryptsetup luksOpen $source luks-$salt 2>&1"
			);
		} else {
			$status = qxx ("cryptsetup luksOpen $source luks-$salt 2>&1");
		}
		$result = $? >> 8;
		if ($result != 0) {
			$kiwi -> error  ("Couldn't open luks device: $status");
			$kiwi -> failed (); umount();
			return undef;
		}
		$source = "/dev/mapper/luks-".$salt;
		push @UmountStack,"cryptsetup luksClose luks-$salt";
	}
	#==========================================
	# Mount device or loop mount file
	#------------------------------------------
	if ((-f $source) && ($type ne "clicfs")) {
		$status = qxx ("mount -o loop $source $dest 2>&1");
		$result = $? >> 8;
		if ($result != 0) {
			$kiwi -> error ("Failed to loop mount $source to: $dest: $status");
			$kiwi -> failed (); umount();
			return undef;
		}
	} else {
		if ($type eq "clicfs") {
			$status = qxx ("clicfs -m 512 $source $dest 2>&1");
			$result = $? >> 8;
			if ($result == 0) {
				$status = qxx ("resize2fs $dest/fsdata.ext3 2>&1");
				$result = $? >> 8;
			}
		} else {
			$status = qxx ("mount $source $dest 2>&1");
			$result = $? >> 8;
		}
		if ($result != 0) {
			$kiwi -> error ("Failed to mount $source to: $dest: $status");
			$kiwi -> failed (); umount();
			return undef;
		}
	}
	push @UmountStack,"umount $dest";
	#==========================================
	# Post mount actions
	#------------------------------------------
	if (-f $dest."/fsdata.ext3") {
		$source = $dest."/fsdata.ext3";
		$status = qxx ("mount -o loop $source $dest 2>&1");
		$result = $? >> 8;
		if ($result != 0) {
			$kiwi -> error ("Failed to loop mount $source to: $dest: $status");
			$kiwi -> failed (); umount();
			return undef;
		}
		push @UmountStack,"umount $dest";
	}
	return $dest;
}

#==========================================
# umount
#------------------------------------------
sub umount {
	# /.../
	# implements an umount function for filesystems mounted
	# via main::mount(). The function walks through the
	# contents of the UmountStack list
	# ---
	my $status;
	my $result;
	qxx ("sync");
	foreach my $cmd (reverse @UmountStack) {
		$status = qxx ("$cmd 2>&1");
		$result = $? >> 8;
		if ($result != 0) {
			$kiwi -> warning ("UmountStack failed: $cmd: $status\n");
		}
	}
	@UmountStack = ();
}

#==========================================
# isize
#------------------------------------------
sub isize {
	# /.../
	# implements a size function like the -s operator
	# but also works for block specials using blockdev
	# ---
	my $target = shift;
	if (! defined $target) {
		return 0;
	}
	if (-b $target) {
		my $size = qxx ("blockdev --getsize64 $target 2>&1");
		my $code = $? >> 8;
		if ($code == 0) {
			chomp  $size;
			return $size;
		}
	} elsif (-f $target) {
		return -s $target;
	}
	return 0;
}

#==========================================
# checkFileSystem
#------------------------------------------
sub checkFileSystem {
	# /.../
	# checks attributes of the given filesystem(s) and returns
	# a summary hash containing the following information
	# ---
	# $filesystem{hastool}  --> has the tool to create the filesystem
	# $filesystem{readonly} --> is a readonly filesystem
	# $filesystem{type}     --> what filesystem type is this
	# ---
	my $fs     = shift;
	my %result = ();
	if (defined $KnownFS{$fs}) {
		#==========================================
		# got a known filesystem type
		#------------------------------------------
		$result{type}     = $fs;
		$result{readonly} = $KnownFS{$fs}{ro};
		$result{hastool}  = 0;
		if (($KnownFS{$fs}{tool}) && (-x $KnownFS{$fs}{tool})) {
			$result{hastool} = 1;
		}
	} else {
		#==========================================
		# got a file, block special or something
		#------------------------------------------
		if (-e $fs) {
			my $data = qxx ("dd if=$fs bs=128k count=1 2>/dev/null | file -");
			my $code = $? >> 8;
			my $type;
			if ($code != 0) {
				if ($main::kiwi -> trace()) {
					$main::BT.=eval { Carp::longmess ($main::TT.$main::TL++) };
				}
				return undef;
			}
			SWITCH: for ($data) {
				/ext4/      && do {
					$type = "ext4";
					last SWITCH;
				};
				/ext3/      && do {
					$type = "ext3";
					last SWITCH;
				};
				/ext2/      && do {
					$type = "ext2";
					last SWITCH;
				};
				/ReiserFS/  && do {
					$type = "reiserfs";
					last SWITCH;
				};
				/BTRFS/     && do {
					$type = "btrfs";
					last SWITCH;
				};
				/Squashfs/  && do {
					$type = "squashfs";
					last SWITCH;
				};
				/LUKS/      && do {
					$type = "luks";
					last SWITCH;
				};
				/XFS/     && do {
					$type = "xfs";
					last SWITCH;
				};
				# unknown filesystem type check clicfs...
				$data = qxx (
					"dd if=$fs bs=128k count=1 2>/dev/null | grep -q CLIC"
				);
				$code = $? >> 8;
				if ($code == 0) {
					$type = "clicfs";
					last SWITCH;
				}
				# unknown filesystem type use auto...
				$type = "auto";
			};
			$result{type}     = $type;
			$result{readonly} = $KnownFS{$type}{ro};
			$result{hastool}  = 0;
			if (defined $KnownFS{$type}{tool}) {
				if (-x $KnownFS{$type}{tool}) {
					$result{hastool} = 1;
				}
			}
		} else {
			if ($main::kiwi -> trace()) {
				$main::BT.=eval { Carp::longmess ($main::TT.$main::TL++) };
			}
			return ();
		}
	}
	return %result;
}

#==========================================
# getControlFile
#------------------------------------------
sub getControlFile {
	# /.../
	# This function receives a directory as parameter
	# and searches for a kiwi xml description in it.
	# ----
	my $dir    = shift;
	my $config = "$dir/$ConfigName";
	if (! -d $dir) {
		if (($main::kiwi) && ($main::kiwi -> trace())) {
			$main::BT.=eval { Carp::longmess ($main::TT.$main::TL++) };
		}
		return undef;
	}
	if (-f $config) {
		return $config;
	}
	my @globsearch = glob ($dir."/*.kiwi");
	my $globitems  = @globsearch;
	if ($globitems == 0) {
		if (($main::kiwi) && ($main::kiwi -> trace())) {
			$main::BT.=eval { Carp::longmess ($main::TT.$main::TL++) };
		}
		return undef;
	} elsif ($globitems > 1) {
		if (($main::kiwi) && ($main::kiwi -> trace())) {
			$main::BT.=eval { Carp::longmess ($main::TT.$main::TL++) };
		}
		return undef;
	} else {
		$config = pop @globsearch;
	}
	return $config;
}

#==========================================
# createInstSource
#------------------------------------------
sub createInstSource {
	# /.../
	# create instsource requires the module "KIWICollect.pm".
	# If it is not available, the option cannot be used.
	# kiwi then issues a warning and exits.
	# ----
	$kiwi = new KIWILog("tiny");
	$kiwi -> deactivateBackTrace();
	my $mod = "KIWICollect";
	eval "require $mod";
	if($@) {
		$kiwi->error("Module <$mod> is not available!");
		my $code = kiwiExit (3);
		return $code;
	}
	else {
		$kiwi->info("Module KIWICollect loaded successfully...");
		$kiwi->done();
	}
	$kiwi -> info ("Reading image description [InstSource]...\n");
	my $xml = new KIWIXML ( $kiwi,$CreateInstSource );
	if (! defined $xml) {
		my $code = kiwiExit (1); return $code;
	}
	#==========================================
	# Initialize installation source tree
	#------------------------------------------
	my $root = $xml -> createTmpDirectory ( undef, $RootTree );
	if (! defined $root) {
		$kiwi -> error ("Couldn't create instsource root");
		$kiwi -> failed ();
		my $code = kiwiExit (1); return $code;
	}
	#==========================================
	# Create object...
	#----------------------------------------
	my $collect = new KIWICollect ( $kiwi, $xml, $root, $Verbosity );
	if (! defined( $collect) ) {
		$kiwi -> error( "Unable to create KIWICollect module." );
		$kiwi -> failed ();
		my $code = kiwiExit( 1 ); return $code;
	}
	if (! defined( $collect -> Init () ) ) {
		$kiwi -> error( "Object initialisation failed!" );
		$kiwi -> failed ();
		my $code = kiwiExit( 1 ); return $code;
	}
	#==========================================
	# Call the *CENTRAL* method for it...
	#----------------------------------------
	my $ret = $collect -> mainTask ();
	if ( $ret != 0 ) {
		$kiwi -> warning( "KIWICollect had runtime error." );
		$kiwi -> skipped ();
		my $code = kiwiExit ( $ret ); return $code;
	}
	$kiwi->info( "KIWICollect completed successfully." );
	$kiwi->done();
	kiwiExit (0);
}

#==========================================
# initializeCache
#------------------------------------------
sub initializeCache {
	$kiwi -> info ("Initialize image cache...\n");
	#==========================================
	# Variable setup
	#------------------------------------------
	my $xml  = $_[0];
	my %type = %{$_[1]};
	my $mode = $_[2];
	#==========================================
	# Variable setup
	#------------------------------------------
	my $CacheDistro;   # cache base name
	my @CachePatterns; # image patterns building the cache
	my @CachePackages; # image packages building the cache
	my $CacheScan;     # image scan, for cache package check
	#==========================================
	# Check boot type of the image
	#------------------------------------------
	my $name = $xml -> getImageName();
	if (($type{boot}) && ($type{boot} =~ /.*\/(.*)/)) {
		$CacheDistro = $1;
	} elsif (($type{type} eq "cpio") && ($name =~ /initrd-.*boot-(.*)/)) {
		$CacheDistro = $1;
	} else {
		$kiwi -> warning ("Can't setup cache without a boot type");
		$kiwi -> skipped ();
		undef $ImageCache;
		return undef;
	}
	#==========================================
	# Check for cachable patterns
	#------------------------------------------
	my @sections = ("bootstrap","image");
	foreach my $section (@sections) {
		my @list = $xml -> getList ($section);
		foreach my $pac (@list) {
			if ($pac =~ /^pattern:(.*)/) {
				push @CachePatterns,$1;
			} elsif ($pac =~ /^product:(.*)/) {
				# no cache for products at the moment
			} else {
				push @CachePackages,$pac;
			}
		}
	}
	if ((! @CachePatterns) && (! @CachePackages)) {
		$kiwi -> warning ("No cachable patterns/packages in this image");
		$kiwi -> skipped ();
		undef $ImageCache;
		return undef;
	}
	#==========================================
	# Create image package list
	#------------------------------------------
	$listXMLInfo = $mode;
	@listXMLInfoSelection = ("packages");
	$CacheScan = listXMLInfo ("internal");
	if (! $CacheScan) {
		undef $ImageCache;
		return undef;
	}
	undef $listXMLInfo;
	undef @listXMLInfoSelection;
	#==========================================
	# Return result list
	#------------------------------------------
	return [
		$CacheDistro,\@CachePatterns,
		\@CachePackages,$CacheScan
	];
}

#==========================================
# selectCache
#------------------------------------------
sub selectCache {
	my $xml  = $_[0];
	my $init = $_[1];
	if ((! $init) || (! $ImageCache)) {
		return undef;
	}
	my $CacheDistro   = $init->[0];
	my @CachePatterns = @{$init->[1]};
	my @CachePackages = @{$init->[2]};
	my $CacheScan     = $init->[3];
	my $haveCache     = 0;
	my %plist         = ();
	my %Cache         = ();
	#==========================================
	# Search for a suitable cache
	#------------------------------------------
	my @packages = $CacheScan -> getElementsByTagName ("package");
	foreach my $node (@packages) {
		my $name = $node -> getAttribute ("name");
		my $arch = $node -> getAttribute ("arch");
		my $pver = $node -> getAttribute ("version");
		$plist{"$name-$pver.$arch"} = $name;
	}
	my $pcnt = keys %plist;
	my @file = ();
	#==========================================
	# setup cache file names...
	#------------------------------------------
	if (@CachePackages) {
		my $cstr = $xml -> getImageName();
		my $cdir = $ImageCache."/".$CacheDistro."-".$cstr.".clicfs";
		push @file,$cdir;
	}
	foreach my $pattern (@CachePatterns) {
		my $cdir = $ImageCache."/".$CacheDistro."-".$pattern.".clicfs";
		push @file,$cdir;
	}
	#==========================================
	# walk through cache files
	#------------------------------------------
	foreach my $clic (@file) {
		my $meta = $clic;
		$meta =~ s/\.clicfs$/\.cache/;
		#==========================================
		# check cache files
		#------------------------------------------
		my $CACHE_FD;
		if (! open ($CACHE_FD,$meta)) {
			next;
		}
		#==========================================
		# read cache file
		#------------------------------------------
		my @cpac = <$CACHE_FD>; chomp @cpac;
		my $ccnt = @cpac; close $CACHE_FD;
		$kiwi -> loginfo (
			"Cache: $meta $ccnt packages, Image: $pcnt packages\n"
		);
		#==========================================
		# check validity of cache
		#------------------------------------------
		my $invalid = 0;
		if ($ccnt > $pcnt) {
			# cache is bigger than image solved list
			$invalid = 1;
		} else {
			foreach my $p (@cpac) {
				if (! defined $plist{$p}) {
					# cache package not part of image solved list
					$kiwi -> loginfo (
						"Cache: $meta $p not in image list\n"
					);
					$invalid = 1; last;
				}
			}
		}
		#==========================================
		# store valid cache
		#------------------------------------------
		if (! $invalid) {
			$Cache{$clic} = int (100 * ($ccnt / $pcnt));
			$haveCache = 1;
		}
	}
	#==========================================
	# Use/select cache if possible
	#------------------------------------------
	if ($haveCache) {
		my $max = 0;
		#==========================================
		# Find best match
		#------------------------------------------
		$kiwi -> info ("Cache list:\n");
		foreach my $clic (keys %Cache) {
			$kiwi -> info ("--> [ $Cache{$clic}% packages ]: $clic\n");
			if ($Cache{$clic} > $max) {
				$max = $Cache{$clic};
			}
		}
		#==========================================
		# Setup overlay for best match
		#------------------------------------------
		foreach my $clic (keys %Cache) {
			if ($Cache{$clic} == $max) {
				$kiwi -> info ("Using cache: $clic");
				$CacheRoot = $clic;
				$CacheRootMode = "union";
				$kiwi -> done();
				return $CacheRoot;
			}
		}
	}
	return undef;
}

#==========================================
# createCache
#------------------------------------------
sub createCache {
	my $xml  = $_[0];
	my $init = $_[1];
	if ((! $init) || (! $ImageCache)) {
		return undef;
	}
	#==========================================
	# Variable setup and reset function
	#------------------------------------------
	sub reset_sub {
		my $backupSurvive      = $main::Survive;
		my @backupProfiles     = @main::Profiles;
		my $backupCreate       = $main::Create;
		my $backupPrepare      = $main::Prepare;
		my $backupRootTree     = $main::RootTree;
		my $backupForceNewRoot = $main::ForceNewRoot;
		my @backupPatterns     = @main::AddPattern;
		my @backupPackages     = @main::AddPackage;
		return sub {
			@main::Profiles     = @backupProfiles;
			$main::Prepare      = $backupPrepare;
			$main::Create       = $backupCreate;
			$main::ForceNewRoot = $backupForceNewRoot;
			@main::AddPattern   = @backupPatterns;
			@main::AddPackage   = @backupPackages;
			$main::RootTree     = $backupRootTree;
			$main::Survive      = $backupSurvive;
		}
	}
	my $resetVariables     = reset_sub();
	my $CacheDistro        = $init->[0];
	my @CachePatterns      = @{$init->[1]};
	my @CachePackages      = @{$init->[2]};
	my $imageCacheDir      = $ImageCache;
	my $imagePrepareDir    = $main::Prepare;
	#==========================================
	# undef ImageCache for recursive kiwi call
	#------------------------------------------
	undef $ImageCache;
	undef $InitCache;
	#==========================================
	# setup variables for kiwi prepare call
	#------------------------------------------
	qxx ("mkdir -p $imageCacheDir 2>&1");
	if (@CachePackages) {
		push @CachePatterns,"package-cache"
	}
	foreach my $pattern (@CachePatterns) {
		if ($pattern eq "package-cache") {
			$pattern = $xml -> getImageName();
			push @CachePackages,$xml->getPackageManager();
			undef @main::AddPattern;
			@main::AddPackage = @CachePackages;
			$kiwi -> info (
				"--> Building cache file for plain package list\n"
			);
		} else {
			@main::AddPackage = $xml->getPackageManager();
			@main::AddPattern = $pattern;
			$kiwi -> info (
				"--> Building cache file for pattern: $pattern\n"
			);
		}
		#==========================================
		# use KIWICache.kiwi for cache creation
		#------------------------------------------
		$main::Prepare      = $BasePath."/modules";
		$main::RootTree     = $imageCacheDir."/";
		$main::RootTree    .= $CacheDistro."-".$pattern;
		$main::Survive      = "yes";
		$main::ForceNewRoot = 1;
		undef @main::Profiles;
		undef $main::Create;
		undef $main::kiwi;
		#==========================================
		# Prepare new cache tree
		#------------------------------------------
		if (! defined main::main()) {
			&{$resetVariables}; return undef;
		}
		#==========================================
		# Create cache meta data
		#------------------------------------------
		my $meta   = $main::RootTree.".cache";
		my $root   = $main::RootTree;
		my $ignore = "'gpg-pubkey|bundle-lang'";
		my $rpmopts= "'%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n'";
		my $rpm    = "rpm --root $root";
		qxx ("$rpm -qa --qf $rpmopts | grep -vE $ignore > $meta");
		qxx ("rm -f $root/image/config.xml");
		qxx ("rm -f $root/image/*.kiwi");
		#==========================================
		# Turn cache into clicfs file
		#------------------------------------------
		$kiwi -> info (
			"--> Building clicfs cache...\n"
		);
		my $image = new KIWIImage (
			$kiwi,$xml,$root,$imageCacheDir,undef,"/base-system"
		);
		if (! defined $image) {
			&{$resetVariables}; return undef;
		}
		if (! $image -> createImageClicFS ()) {
			&{$resetVariables}; return undef;
		}
		my $name = $imageCacheDir."/".$image -> buildImageName();
		qxx ("mv $name $main::RootTree.clicfs");
		qxx ("rm $name.clicfs $name.md5");
		qxx ("rm -f  $imageCacheDir/initrd-*");
		qxx ("rm -rf $main::RootTree");
		#==========================================
		# Reformat log file for human readers...
		#------------------------------------------
		$kiwi -> setLogHumanReadable();
		#==========================================
		# Move process log to final cache log...
		#------------------------------------------
		$kiwi -> finalizeLog();
	}
	&{$resetVariables};
	return $imageCacheDir;
}

main();

# vim: set noexpandtab:
