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

```sh
homebrew cache packer puppet rubytools vagrant virtualbox vmware parallels
```

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

There are some useful options to change the default behavior:

You can always get help with:
```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- --help
```

The possible options are:

- --cache-root *path*  
  Contains the location of the cache for ISO, MSI, etc files.  
  Default: /var/cache/daas
- --cache-source *url*  
  Contains the URL of the configuration file for the cached sources.  
  Default: [sources.json on cdn.rawgit.com](https://cdn.rawgit.com/inin-apac/puppet-me/da22e817bcbf197e5a5454f781c79ceaf98b93af/config/sources.json)
--credentials *url*  
  Store the credentials from the given url to the keychain.  
  Note the credentials have to follow [RFC 3986](https://tools.ietf.org/html/rfc3986).  
  Examples: ftp://myuser:s3cr3t@ftp.acme.com  
            smb://acme;myuser:s3cr3t@files.acme.com/share  
  Note: if the password contains the @ sign, it should be replaced with %40  
- --force  
  Force all updates to happen (downloads still do not happen if already done).
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
- --parallels-home *path*  
  Contains the location virtual machine data will be stored.  
  Default value: $HOME/Documents/Virtual Machines
- --quiet  
  Runs the script without any message.
- --userid *value*  
  contains the default user for various authentications (like cifs/smb).  
  Default: current user.
- --vagrant-home *path*  
  Contains the location where vagrant user work data will be stored.  
  Default value: $HOME/.vagrant.d
- --vagrant-vmware-license *path*  
  Contains the location of the license file for the Vagrant VMWare Plugin.
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
  If not provided here and VMWare needs to be configured,  
  The VMWare initialization script will request it.  
- --yes, --assumeyes, -y  
  Answers yes to any questions automatically.

For example, if your Mac mini has an HDD and an SSD, you would want to run all virtual machines as well as their builds on the SSD. If the SSD is at /Volumes/SSD, the install invocation would be:

```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- --macmini-virtualbox --packer-home /Volumes/SSD/packer --vagrant-home /Volumes/SSD/vagrant --virtualbox-home /Volumes/SSD/Virtualbox
```


Windows 8.1 and Windows 2012R2
------------------------------

On Windows, run in a command:
```cmd
@powershell -NoProfile -ExecutionPolicy unrestricted -Command "iex ((new-object net.webclient).DownloadString('http://tinyurl.com/kfrj7tn'))"
```

AUTHORS
=======
[![endorse](https://api.coderwall.com/gildas/endorsecount.png)](https://coderwall.com/gildas)
