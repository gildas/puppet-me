puppet-me
=========
On OS/X, run in a shell:

```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash
```

By default only Homebrew and puppet are installed and configured.

It is possible to install more modules with:

```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- --modules=homebrew,vagrant,packer
```

As of today, the following modules can be installed:

```sh
homebrew ISO_cache packer puppet rubytools vagrant virtualbox vmware
```

Note: use the special argument "--macmini" to install the following modules: homebrew, puppet, vmware, vagrant, packer, rubytools, and ISO_cache, in the given order.

```sh
curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- --macmini
```

On Windows, run in a command:
```cmd
@powershell -NoProfile -ExecutionPolicy unrestricted -Command "iex ((new-object net.webclient).DownloadString('http://tinyurl.com/kfrj7tn'))"
```

AUTHORS
=======
[![endorse](https://api.coderwall.com/gildas/endorsecount.png)](https://coderwall.com/gildas)
