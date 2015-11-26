puppet-me
=========

Mac OS/X Yosemite
-----------------

On OS/X, run in a shell:

```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash
```

By default only Homebrew and puppet are installed and configured.

It is possible to install more modules with:

```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- --modules=homebrew,vagrant,packer
```

Modules dependencies are automatically computed.
For example, if you specify the module list as "packer,homebrew", the installer will automatically install homebrew first and then packer, since the latter depends on the former.

As of today, the following modules can be installed:

[homebrew](http://brew.sh), cache, [packer](https://packer.io), [puppet](https://puppetlabs.com), rubytools, [vagrant](https://vagrantup.com), [virtualbox](https://www.virtualbox.org), [vmware](http://www.vmware.com/products/fusion), [parallels](http://www.parallels.com), updateme.

The module list can be bundled using the special --macmini options.

- --macmini-vmware  
  => homebrew, rubytools, puppet, vmware, vagrant, cache, and packer.
- --macmini-parallels  
  => homebrew, rubytools, puppet, parallels, vagrant, cache, and packer.
- --macmini-virtualbox  
  => homebrew, rubytools, puppet, virtualbox, vagrant, cache, and packer.
- --macmini-all  
  => homebrew, rubytools, puppet, parallels, virtualbox, vmware, vagrant, cache, and packer.
- --macmini  
  is an alias to --macmini-vmware

For example, the following line will install the default macmini list:
```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- --macmini
```

The following line will install the default macmini list and will try to use a local folder for the files to cache (like a mounted USB disk), then a network share (ftp, smb, or afp), then whatever is matched in the cache configuration file:
```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- --macmini --cache-source /Volumes/JetDrive/ISO --cache-source afp://nas/public/ISO
```

There are some useful options to change the default behavior:

You can always get help with:
```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- --help
```

The possible options are:

- --cache-root *path*  
  Contains the location of the cache for ISO, MSI, etc files.  
  Default: /var/cache/daas
- --cache-config *url*  
  Contains the URL of the configuration file for the cached sources.  
  Default: [sources.json on cdn.rawgit.com](https://cdn.rawgit.com/inin-apac/puppet-me/f74d7ec3242afce03a29e061eb93ed36cca1e9ee/config/sources.json)
- --cache-keep  
  Keep previous versions of downloads (e.g., keep CIC 2015R1, 2015R2, patches)  
  Default: previous versions are deleted  
- --cache-sources *urls*  
  Contains the URL of the configuration file for the cached sources.  
- --cache-source *path_or_url*  
  Contains the URL or the path where the sources can be downloaded before the configuration.  
  This option can be repeated.  
- --cache-source *path_or_url*  
  Contains a comma separated list of URsL or paths where the sources can be downloaded before the configuration.  
--credentials *url*  
  Store the credentials from the given url to the keychain.  
  Note the credentials have to follow [RFC 3986](https://tools.ietf.org/html/rfc3986).  
  Examples: ftp://myuser:s3cr3t@ftp.acme.com  
            smb://acme;myuser:s3cr3t@files.acme.com/share  
  Note: if the password contains the @ sign, it should be replaced with %40  
- --force  
  Force all updates to happen (downloads still do not happen if already done).
- --gui  
  Force prompts to use a dialog box to query the user (whenever possible).   
- --no-gui  
  Force prompts to not use a dialog box to query the user.  
- --help  
  Prints some help on the output.
- --macmini-parallels  
  will install a default set of modules (see before).
- --macmini-virtualbox  
  will install a default set of modules (see before).
- --macmini-vmware or --macmini  
  will install a default set of modules (see before).
- --modules  
  contains a comma-separated list of modules to install.  
  The complete list can be obtained with --help.  
  The --macmini options will change that list.  
  Default: homebrew,puppet,rubytools
- --network  *ip_address*/*cidr*
  can be used to force the script to believe it is run in a given network.  
  Both an ip address and a network (in the cidr form) must be given.  
  Default: N/A.
- --noop, --dry-run  
  Do not execute instructions that would make changes to the system (write files, install software, etc).
- --packer-home *path*  
  Contains the location where packer user work data will be stored.  
  Default value: $HOME/Documents/packer
- --packer-build *tasks*  
  Will tell [packer-windows](https://github.com/gildas/packer-windows) to build boxes (comma separated list).  
  If the virtualization software for a build is not installed, the script will produce an error.  
  E.g.:  
  ```sh
  --packer-build vmware:windows-2012R2-core-standard-eval  
  ```
  will build the box windows 2012R2 Core edition (evaluation license) for [VMWare Fusion](http://www.vmware.com/products/fusion).  
  ```sh
  --packer-build virtualbox:all  
  ```
  will build all boxes known to [packer-windows](https://github.com/gildas/packer-windows) for [Virtualbox](http://www.virtualbox.org).  
  Default value: N/A  
- --packer-load *tasks*  
  Will tell [packer-windows](https://github.com/gildas/packer-windows) to load (and build before as needed) boxes in [Vagrant](http://vagrantup.com) (comma separated list).  
  If the virtualization software for a build is not installed, the script will produce an error.  
  E.g.:  
  ```sh
  --packer-load vmware:windows-2012R2-core-standard-eval  
  ```
  will (build and) load the box windows 2012R2 Core edition (evaluation license) for [VMWare Fusion](http://www.vmware.com/products/fusion).  
  ```sh
  --packer-build virtualbox:all  
  ```
  will (build and load) all boxes known to [packer-windows](https://github.com/gildas/packer-windows) for [Virtualbox](http://www.virtualbox.org).  
  Default value: N/A  
- --parallels-home *path*  
  Contains the location virtual machine data will be stored.  
  Default value: $HOME/Documents/Virtual Machines
- --parallels-license *key*  
  Contains the license key to configure [Parallels Desktop](http://www.parallels.com/products/desktop/).  
- --password *password*  
  Contains the sudo password for elevated tasks.  
  Warning: The password will be viewable in your shell history as well as on the current command line.  
- --quiet  
  Runs the script without any message.
- --userid *value*  
  contains the default user for various authentications (like cifs/smb).  
  Default: current user.
- --vagrant-home *path*  
  Contains the location where [Vagrant](http://vagrantup.com) user work data will be stored.  
  Default value: $HOME/.vagrant.d
- --vagrant-vmware-license *path*  
  Contains the location of the license file for the [Vagrant VMWare Plugin](https://www.vagrantup.com/vmware).
- --verbose  
  Runs the script verbosely, that's by default.
- --virtualbox-home *path*  
  Contains the location virtual machine data will be stored.  
  Default value: $HOME/Documents/Virtual Machines
- --vmware-home *path*  
  Contains the location virtual machine data will be stored.  
  Default value: $HOME/Documents/Virtual Machines
- --vmware-license *key*  
  Contains the license key to configure VMWare Fusion.  
  If not provided here and [VMWare Fusion](http://www.vmware.com/products/fusion) needs to be configured,  
  The [VMWare Fusion](http://www.vmware.com/products/fusion) initialization script will request it.  
- --yes, --assumeyes, -y  
  Answers yes to any questions automatically.

For example, if your Mac mini has an HDD and an SSD, you would want to run all virtual machines as well as their builds on the SSD. If the SSD is at /Volumes/SSD, the install invocation would be:

```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- --macmini-virtualbox --packer-home /Volumes/SSD/packer --vagrant-home /Volumes/SSD/vagrant --virtualbox-home /Volumes/SSD/Virtualbox
```


Windows 8.1 and Windows 2012R2
------------------------------

On Windows, open a **Powershell** as an Administrator, and type:
```powershell
Start-BitsTransfer http://tinyurl.com/puppet-me-win-8 $env:TEMP\_.ps1 ; & $env:TEMP\_.ps1 [options]
```

Where *options* are:

- -Branch *name*  
  Use a different git branch to run puppet-me.  
  This is used for Beta, Release Candidate phases.  
- -BridgedNetAdapterName  
  Contains the name of the network adapter to build a bridged switch for the Virtual Machines.  
- -CacheKeep  
  Keep previous versions of downloads (e.g., keep CIC 2015R1, 2015R2, patches)  
  Default: previous versions are deleted  
- -CacheRoot *path*  
  Contains the location of the cache for ISO, MSI, etc files.    
  When used, it will update $env:DAAS_CACHE  
  Alias: DaasCache  
  Default: $env:DAAS_CACHE or $env:ProgramData\DaaS\Cache  
- -CacheSource *list of path_or_url*  
  Contains a comma separated list of URLs or paths where the sources can be downloaded before the configuration.  
  Alias: CacheSources  
  Default: None  
- -Credential *credential*  
  Contains some **[PSCredential](https://msdn.microsoft.com/en-us/library/system.management.automation.pscredential.aspx)** to use by default when connecting to VPNs, Windows Share, etc.  
  To get a dialog box that queries for the credentials, use the following:  
  ```powershell
  Start-BitsTransfer ... win-8.1-client.ps1 -Credential (Get-Credential) [options]
  ```
  Or, with a user:  
  ```powershell
  Start-BitsTransfer ... win-8.1-client.ps1 -Credential (Get-Credential ACME\john.doe) [options]
  ```
- -HyperV  
  When used, Hyper-V will be configured.  
  A reboot might be necessary before building the first box.  
  Only one of -HyperV, -Virtualbox, -VMWare can be specified.  
- -PackerBuild  
  When all software is installed, [packer-windows](https://github.com/gildas/packer-windows) will build the given list of [Vagrant](http://vagrantup.com) boxes.  
- -PackerHome *path*  
  Contains the location where the [packer-windows](https://github.com/gildas/packer-windows) building environment will be stored.  
  When used, it will update $env:PACKER_HOME  
  Warning: This folder can grow quite big!  
  Default: $env:PACKER_HOME or $env:UserProfile\Documents\packer  
- -PackerLoad  
  When all software is installed, [packer-windows](https://github.com/gildas/packer-windows) will be build and load the given list of [Vagrant](http://vagrantup.com) boxes.  
- -Usage  
  Prints this help and exits.  
- -VagrantHome *path*  
  Contains the location where [Vagrant](http://vagrantup.com) Data will be stored such as Vagrant boxes.    
  When used, it will update $env:VAGRANT_HOME  
  Warning: This folder can grow quite big!  
  Default value: $env:VAGRANT_HOME or $env:UserProfile/.vagrant.d  
- -VagrantVMWareLicense *path*  
  Contains the location of the license file for the [Vagrant VMWare Plugin](https://www.vagrantup.com/vmware).  
- -Version  
  Displays the version of this installer and exists.  
- -Virtualbox  
  When used, [Virtualbox](http://www.virtualbox.org) will be installed and configured.  
  Only one of -HyperV, -Virtualbox, -VMWare can be specified.  
- -VirtualHardDiskPath *path*  
  Contains the location where virtual hard disks will be stored, this is for Hyper-V only.  
  Alias: VHDHome, VirtualHardDisks, VirtualHardDisksHome, VirtualHardDisksPath  
- -VirtualMachinePath *path*  
  Contains the location virtual machines will be stored.    
  The Default value depends on the Virtualization platform that was chosen.  
  Alias: VMHome, VirtualMachines, VirtualMachinesHome  
- -VMWare  
  When used, [VMWare Workstation](http://www.vmware.com/products/workstation) will be installed and configured.  
  Only one of -HyperV, -Virtualbox, -VMWare can be specified.  
- -VMWareLicense *key*  
  Contains the license key to configure [VMWare Workstation](http://www.vmware.com/products/workstation).    
  If not provided, the license key will have to be entered manually the first time [VMWare Workstation](http://www.vmware.com/products/workstation) is used.  

Note:
-----

To use the development version, use this command instead:
```powershell
Start-BitsTransfer http://tinyurl.com/puppet-me-win-8-dev $env:TEMP\_.ps1 ; & $env:TEMP\_.ps1 -Branch dev [options]
```

AUTHORS
=======
[![endorse](https://api.coderwall.com/gildas/endorsecount.png)](https://coderwall.com/gildas)
