@if not defined PACKER_DEBUG (@echo off) else (@echo on)
setlocal EnableDelayedExpansion EnableExtensions

:: Installation:
:: @powershell -Command "Start-BitsTransfer http://tinyurl.com/puppet-me-win-8-1 '%TEMP%\zz.cmd'" && type %TEMP%\zz.cmd | more /p > %TEMP%\puppet-me.cmd && %TEMP%\puppet-me.cmd Virtualization
:::: Using type+more allows to change CR (unix) into CRLF (dos). Executing cmd files in unix mode leads to heisenbugs.
:::: [Virtualization] should be one of the following (case insensitive) values: Virtualbox, VMWare
set CURRENT_DIR=%~dp0%
set VERSION=0.5.0
set posh=%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile

set GITHUB_ROOT=https://raw.githubusercontent.com/inin-apac/puppet-me
set TOOLS_ROOT=%GITHUB_ROOT%/master
set CACHE_CONFIG=%GITHUB_ROOT%/%VERSION%/config/sources.json
if "%DAAS_CACHE%"      == "" set DAAS_CACHE=%ProgramData%\DaaS\cache
set NETWORK=
if "%PACKER_HOME%"     == "" set PACKER_HOME=%USERPROFILE%\Documents\packer
if "%VAGRANT_HOME%"    == "" set VAGRANT_HOME=%USERPROFILE%\.vagrant.d
set VAGRANT_VMWARE_LICENSE=
set VMWARE_LICENSE=
goto main

:: functions {{{
:: Function: SetErrorLevel {{{2
:SetErrorLevel    
exit /b %~1
:: Function: SetErrorLevel }}}2

:: Function: Download(url, dest_path) {{{2
:Download    
set URL=%~1
set DEST=%~2
set zz=%URL%z
for /f "tokens=* delims=/" %%f in ("%zz:~0,-1%") do set filename=%%~nxf
set DEST=%DEST%\%filename%
echo Downloading %URL% into %DEST%
%posh% -Command "Start-BitsTransfer -Source %URL% -Destination '%DEST%'"
goto :EOF
:: Function: Download }}}2

:: Function: DownloadTools {{{2
:DownloadTools    
  call :Download "%TOOLS_ROOT%/install/Install-Virtualbox.ps1" %TEMP%
  if errorlevel 1 goto :EOF
  call :Download "%TOOLS_ROOT%/install/Install-VMWare.ps1" %TEMP%
  if errorlevel 1 goto :EOF
  call :Download "%TOOLS_ROOT%/install/Install-Hyper-V.ps1" %TEMP%
  if errorlevel 1 goto :EOF
  call :Download "%TOOLS_ROOT%/install/Uninstall-Hyper-V.ps1" %TEMP%
  if errorlevel 1 goto :EOF
  call :Download "%TOOLS_ROOT%/install/Install-Cache.ps1" %TEMP%
  if errorlevel 1 goto :EOF
goto :EOF
:: Function: DownloadTools }}}2

:: Function: InstallChocolatey {{{2
:InstallChocolatey    
where.exe /q chocolatey.exe
if %ERRORLEVEL% EQU 0 goto InstallChocolateyOK
if exist %ALLUSERSPROFILE%\chocolatey\bin\chocolatey.exe (
  SET PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin
  goto InstallChocolateyOK
)
title Installing Chocolatey...
echo Downloading Chocolatey Installer...
call :Download "https://chocolatey.org/install.ps1" %TEMP%
if errorlevel 1 goto :EOF
echo Installing Chocolatey...
%posh% -ExecutionPolicy ByPass -Command "& '%TEMP%\install.ps1' %*"
if errorlevel 1 goto :EOF
SET PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin
:InstallChocolateyOK    
echo Chocolatey is installed
goto :EOF
:: Function: InstallChocolatey }}}2

:: Function: ChocolateyInstall {{{2
:ChocolateyInstall    
set conmmand=install
set package=
set version=
:CI_Getopts
  set arg=%1
  if /I %arg% == --version set version=-version %~2 shift
  if /I %arg% == --upgrade set command=upgrade
  shift
if %arg:~0,1%  == "-" goto :CI_Getopts
set package=%arg%
choco list -l | findstr /I /C:"%package%" >NUL
if %ERRORLEVEL% EQU 0 goto :CI_Upgrade  
title Installing %package%...
echo Installing %package%
choco install --limitoutput --yes %package% %version%
if errorlevel 1 goto :EOF
:CI_Upgrade
if not "%command%" == "upgrade" goto :CI_OK
title Upgrading %~1...
choco upgrade --limitoutput --yes %package% %version%
:CI_OK    
echo package %package% is installed
goto :EOF
:: Function: InstallChocolatey }}}2

:: Function: GemInstall {{{2
:GemInstall   
set gem=%~1
call gem list --local | findstr /C:"%gem%" >NUL
if %ERRORLEVEL% EQU 0 goto GemInstallOK
title Installing Ruby gem %~1...
call gem install  %gem%
if errorlevel 1 goto :EOF
:GemInstallOK    
echo Ruby gem %gem% is installed
goto :EOF
:: Function: GemInstall }}}2

:: Function: InstallHyperV {{{2
:InstallHyperV    
  %posh% -ExecutionPolicy ByPass -Command "& '%TEMP%\Install-Hyper-V.ps1' -Verbose"
  if errorlevel 1 goto :EOF
goto :EOF
:: Function: InstallHyperV }}}2

:: Function: UninstallHyperV {{{2
:UninstallHyperV    
  %posh% -ExecutionPolicy ByPass -Command "& '%TEMP%\Uninstall-Hyper-V.ps1' -Verbose"
  if errorlevel 1 goto :EOF
goto :EOF
:: Function: UninstallHyperV }}}2

:: Function: VagrantPluginInstall {{{2
:: See http://www.dostips.com/forum/viewtopic.php?f=3&t=3487 for explanation about while/for/goto
:: We have to try the install severak times as it can fail from time
::   to time for no real good reason!!!
:VagrantPluginInstall    
set plugin=%~1
C:\HashiCorp\Vagrant\bin\vagrant.exe plugin list | findstr /C:"%plugin%"
if %ERRORLEVEL% EQU 0 goto VagrantPluginInstallOK
title Installing Vagrant plugin %~1...
set try_index=0
:While_VPI
  if %try_index% geq 5 goto :EndWhile_VPI
  C:\HashiCorp\Vagrant\bin\vagrant.exe plugin install  %plugin%
  if %ERRORLEVEL% EQU 0 goto :VagrantPluginInstallOK
  set STASH_ERRORLEVEL=%ERRORLEVEL%
  echo Trying again...
  set /A try_index+=1
  goto :While_VPI
:EndWhile_VPI
echo Vagrant plugin %plugin% failed 5 times... giving up
call :SetErrorLevel %STASH_ERRORLEVEL%
goto :EOF
:VagrantPluginInstallOK    
echo Vagrant plugin %plugin% is installed
goto :EOF
:: Function: VagrantPluginInstall }}}2

:: Function: InstallVirtualBox {{{2
:InstallVirtualBox    
  call :UninstallHyperV
  if errorlevel 1 goto :error
  set args=
  if "X%VIRTUALBOX_HOME%" NEQ "X" set args=%args% -VirtualMachinesHome '%VIRTUALBOX_HOME%'
  %posh% -ExecutionPolicy ByPass -Command "& '%TEMP%\Install-Virtualbox.ps1' %args% -Verbose"
  if errorlevel 1 goto :error
:InstallVirtualBoxOK    
goto :EOF
:: Function: InstallVirtualBox }}}2

:: Function: InstallVMWare {{{2
:InstallVMWare    
  call :UninstallHyperV
  if errorlevel 1 goto :error
  set args=
  if "X%VMWARE_HOME%"    NEQ "X" set args=%args% -VirtualMachinesHome '%VMWARE_HOME%'
  if "X%VMWARE_LICENSE%" NEQ "X" set args=%args% -License '%VMWARE_LICENSE%'
  %posh% -ExecutionPolicy ByPass -Command "& '%TEMP%\Install-VMWare.ps1' %args% -Verbose"
  if errorlevel 1 goto :error
:InstallVMWareOK    
goto :EOF
:: Function: InstallVMWare }}}2

:: Function: CacheStuff {{{2
:CacheStuff    
set root=%~1
set source=%~2

%posh% -ExecutionPolicy ByPass -Command "& '%TEMP%\Install-Cache.ps1' -Uri %source% -CacheRoot '%root%' -Verbose"
:CacheStuffOK    
goto :EOF
:: Function: CacheStuff }}}2

:: functions }}}

:main
title DaaS setup
::Parse Options {{{
:Opts_Start
  if /I "%~1" == ""                       goto :Opts_End
  if /I "%~1" == "--"                     goto :Opts_End
  set arg=%~1
  if /I "%arg:~0,1%" NEQ "-"              goto :Opts_End
  shift

  if /I %arg%   == --cache-config           set CACHE_CONFIG=%~1
  if /I %arg%   == --cache-root             set DAAS_CACHE=%~1
  if /I %arg%   == --daas-cache             set DAAS_CACHE=%~1
  if /I %arg%   == --network                set NETWORK=%~1
  ::if /I %arg% == --packer-build
  ::if /I %arg% == --packer-load
  if /I %arg%   == --packer-home            set PACKER_HOME=%~1
  if /I %arg%   == --vagrant-home           set VAGRANT_HOME=%~1
  if /I %arg%   == --vagrant-vmware-license set VAGRANT_VMWARE_LICENSE=%~1
  if /I %arg%   == --virtual                set DAAS_VIRTUAL=%~1
  if /I %arg%   == --virtualbox-home        set VIRTUALBOX_HOME=%~1
  if /I %arg%   == --vmware-home            set VMWARE_HOME=%~1
  if /I %arg%   == --vmware-license         set VMWARE_LICENSE=%~1

  ::if /I %arg% == --noop    set NOOP=-WhatIf
  ::if /I %arg% == --dry-run
  ::if /I %arg% == --whatif
  if /I %arg%   == --version ( echo %VERSION% & goto :eof )
  if /I %arg%   == --help    goto :Usage
  :Opts_Next
  shift
goto :Opts_Start
:Opts_End
echo(
goto :Opts_Validate
::Parse Options }}}

::Usage {{{
:Usage
echo Puppet Me for Windows 8.1 v%VERSION%
echo(
echo   Options are:
echo(
echo   --cache-root             Where the DaaS Cache should be created
echo                            Default: %DAAS_CACHE%
echo   --packer-home            where the Packer Windows project should live
echo                            Default: %PACKER_HOME%
echo   --vagrant-home           where Vagrant boxes should be stored
echo                            Default: %VAGRANT_HOME%
echo   --vagrant-vmware-license points to the license file 
echo   --virtual                The Virtualization Kit to use (one of):
echo                            Valid values: hyper-v, virtualbox, vmware
echo   --virtualbox-home        where Virtual Machines should be created
echo                            Default: %VIRTUALBOX_HOME%
echo   --vmware-home            where Virtual Machines should be created
echo                            Default: %VMWARE_HOME%
echo   --vmware-license         contains the VMWare License Key

echo   --help                   shows this help
echo   --version                shows the version of this application
goto :eof
::Usage }}}

::Validation {{{
:Opts_Validate
if    "%DAAS_VIRTUAL%" EQU ""           goto :E_NOVIRTUAL
if /I "%DAAS_VIRTUAL%" EQU "Hyper V"    goto :OK_HyperV
if /I "%DAAS_VIRTUAL%" EQU "Hyper-V"    goto :OK_HyperV
if /I "%DAAS_VIRTUAL%" EQU "HyperV"     goto :OK_HyperV
if /I "%DAAS_VIRTUAL%" EQU "vmware"     goto :OK_VIRTUAL
if /I "%DAAS_VIRTUAL%" EQU "Virtualbox" goto :OK_VIRTUAL
echo Invalid Virtualization kit: %DAAS_VIRTUAL%
exit /b 1
:E_NOVIRTUAL
echo Missing Virtualization kit
exit /b 1
:OK_HyperV
set DAAS_VIRTUAL=hyper-v
:OK_VIRTUAL
if "X%DAAS_VIRTUAL%"    NEQ "X" setx DAAS_VIRTUAL    "%DAAS_VIRTUAL%" >NUL
if "X%DAAS_CACHE%"      NEQ "X" setx DAAS_CACHE      "%DAAS_CACHE%" >NUL
if "X%PACKER_HOME%"     NEQ "X" setx PACKER_HOME     "%PACKER_HOME%" >NUL
if "X%VAGRANT_HOME%"    NEQ "X" setx VAGRANT_HOME    "%VAGRANT_HOME%" >NUL
if "X%VIRTUALBOX_HOME%" NEQ "X" setx VIRTUALBOX_HOME "%VIRTUALBOX_HOME%" >NUL
if "X%VMWARE_HOME%"     NEQ "X" setx VMWARE_HOME     "%VMWARE_HOME%" >NUL

:Opts_OK

:SUDO_Validate
net session >NUL 2>&1
if %ERRORLEVEL% NEQ 0 (
  echo Error: You must run this program as an Administrator
  exit /b %ERRORLEVEL%
)
:SUDO_OK
::Validation }}}

call :DownloadTools
if errorlevel 1 goto :error

call :InstallChocolatey
if errorlevel 1 goto :error

call :ChocolateyInstall md5
if errorlevel 1 goto :error

call :ChocolateyInstall 7zip
if errorlevel 1 goto :error
SET PATH=%PATH%;"%ProgramFiles%\7-zip"

call :ChocolateyInstall git --upgrade
if errorlevel 1 goto :error
SET PATH=%PATH%;"%ProgramFiles%\Git\cmd"

call :ChocolateyInstall imdisk
if errorlevel 1 goto :error

call :ChocolateyInstall ruby --upgrade
if errorlevel 1 goto :error
:: TODO: Allow ruby through the firewall?
SET PATH=%PATH%;C:\tools\ruby21\bin

call :GemInstall bundler
if errorlevel 1 goto :error

if /I "%DAAS_VIRTUAL%" EQU "Virtualbox" (
  call :InstallVirtualBox
  if errorlevel 1 goto :error
  SET PATH=%PATH%;"%ProgramFiles%\Oracle\VirtualBox"
)

if /I "%DAAS_VIRTUAL%" EQU "VMWare" (
  call :InstallVMWare
  if errorlevel 1 goto :error
  SET PATH=%PATH%;"%ProgramFiles(x86)%\VMWare\VMWare Workstation"
)

if /I "%DAAS_VIRTUAL%" EQU "Hyper-V" (
  call :InstallHyperV
  if errorlevel 1 goto :error
)

call :ChocolateyInstall packer --upgrade
if errorlevel 1 goto :error

echo Installing Packer Provisioner Wait
echo   Downloading from github...
%posh% -Command "(New-Object System.Net.WebClient).DownloadFile('https://github.com/gildas/packer-provisioner-wait/releases/download/v0.1.0/packer-provisioner-wait-0.1.0-win.7z', '%TEMP%\packer-provisioner-wait-0.1.0-win.7z')"
if errorlevel 1 goto :error
echo   Extracting in packer tools...
7z.exe e -y -oC:\ProgramData\chocolatey\lib\packer\tools %TEMP%\packer-provisioner-wait-0.1.0-win.7z
if errorlevel 1 goto :error

call :ChocolateyInstall vagrant --upgrade
if errorlevel 1 goto :error
SET PATH=%PATH%;C:\HashiCorp\Vagrant\bin

::C:\HashiCorp\Vagrant\bin\vagrant.exe plugin update
if errorlevel 1 goto :error

call :VagrantPluginInstall vagrant-host-shell
if errorlevel 1 goto :error

if /I "%virtual_kit%" EQU "VMWare" (
  call :VagrantPluginInstall vagrant-vmware-workstation
  if errorlevel 1 goto :error
)

:: Installing the Packer Windows project
echo Installing packer windows...
set packer_windows=%PACKER_HOME%\packer-windows
if not exist "%packer_windows%" mkdir "%packer_windows%"
if not exist "%packer_windows%\.git" (
  echo   Cloning repository
  git clone https://github.com/gildas/packer-windows.git "%packer_windows%"
  if errorlevel 1 goto :error
) else (
   echo Updating repository
  git -C "%packer_windows%" pull
  if errorlevel 1 goto :error
)
if exist "%packer_windows%\Gemfile" (
  pushd "%packer_windows%"
  echo   Installing Ruby Gem
  call bundle install
  if errorlevel 1 (
    popd
    goto :error
  )
  popd
)

::Download sources
echo Preparing the DaaS cache 
call :CacheStuff "%DAAS_CACHE%" "%CACHE_CONFIG%"
if errorlevel 1 goto :EOF

:: Load CIC box

goto :success

:success    
title _
echo Your computer is now ready
pause 5
echo exit
goto :EOF

:error    
title error!
if %ERRORLEVEL% GTR 0 echo Error: %ERRORLEVEL%
echo Your computer is not ready
goto :EOF
:: vim:fileformat=dos
