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

- --macmini-vmware will install: homebrew, rubytools, puppet, vmware, vagrant, cache, and packer.
- --macmini-parallels will install: homebrew, rubytools, puppet, parallels, vagrant, cache, and packer.
- --macmini-virtualbox will install: homebrew, rubytools, puppet, virtualbox, vagrant, cache, and packer.
- --macmini-all will install: homebrew, rubytools, puppet, parallels, virtualbox, vmware, vagrant, cache, and packer.
- --macmini is an alias to --macmini-vmware

For example, the following line will install the default macmini list:
```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- --macmini
```

There are some useful options to change the default behavior:

You can always get help with:
```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- --help
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
