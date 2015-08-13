@if not defined PACKER_DEBUG (@echo off) else (@echo on)
setlocal EnableDelayedExpansion EnableExtensions

:: Installation:
:: bitsadmin /transfer puppet-me /download /priority normal https://raw.githubusercontent.com/inin-apac/puppet-me/windows/install/win-8.1-client.cmd %TEMP%\win-client-8.1.cmd && %TEMP%\win-client-8.1.cmd Virtualization

set CURRENT_DIR=%~dp0%
set posh=%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile

set MODULE_PACKER_HOME=%USERPROFILE%\Documents\packer
goto main

:: functions {{{
:: Function: Download(url, dest_path) {{{2
:Download
set URL=%~1
set DEST=%~2
set zz=%URL%z
for /f "tokens=* delims=/" %%f in ("%zz:~0,-1%") do set filename=%%~nxf
set DEST=%DEST%\%filename%
echo Downloading %URL% into %DEST%
%posh% -Command "Invoke-WebRequest -Uri %URL% -OutFile '%DEST%'"
goto :EOF
:: Function: Download }}}2

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
set package=%~1
set version=
if "X%~2X" NEQ "XX" ( set version=-version %~2 )
choco list -l | findstr /I /C:"%package%" >NUL
if %ERRORLEVEL% EQU 0 goto ChocolateyInstallOK
title Installing %~1...
choco install --limitoutput --yes %package% %version%
if errorlevel 1 goto :EOF
:ChocolateyInstallOK
echo package %package% is installed
goto :EOF
:: Function: InstallChocolatey }}}2

:: Function: GemInstall {{{2
:GemInstall
set gem=%~1
gem list --local | findstr /C:"%gem%" >NUL
if %ERRORLEVEL% EQU 0 goto GemInstallOK
title Installing Ruby gem %~1...
gem install  %gem%
if errorlevel 1 goto :EOF
:GemInstallOK
echo Ruby gem %gem% is installed
goto :EOF
:: Function: GemInstall }}}2

:: Function: VagrantPluginInstall {{{2
:VagrantPluginInstall
set plugin=%~1
C:\HashiCorp\Vagrant\bin\vagrant.exe plugin list | findstr /C:"%plugin%" >NUL
if %ERRORLEVEL% EQU 0 goto VagrantPluginInstallOK
title Installing Vagrant plugin %~1...
C:\HashiCorp\Vagrant\bin\vagrant.exe plugin install  %plugin%
if errorlevel 1 goto :EOF
:VagrantPluginInstallOK
echo Vagrant plugin %plugin% is installed
goto :EOF
:: Function: VagrantPluginInstall }}}2

:: function }}}

:main
title DaaS setup
set virtual_kit=%~1
if "X%~1X" EQU "XX" (
  echo Missing Virtualization Kit
  echo Valid values are: VMWare, Virtualbox
  goto :error
)
if /I "%~1" EQU "VMWare"     goto :OptionVirtualizationOK
if /I "%~1" EQU "Virtualbox" goto :OptionVirtualizationOK
echo Invalid Virtualization Kit: %~1
echo Valid values are: VMWare, Virtualbox
goto :error
:OptionVirtualizationOK

call :InstallChocolatey
if errorlevel 1 goto :error

call :ChocolateyInstall md5
if errorlevel 1 goto :error

call :ChocolateyInstall 7zip
if errorlevel 1 goto :error

call :ChocolateyInstall git
if errorlevel 1 goto :error

call :ChocolateyInstall imdisk
if errorlevel 1 goto :error

call :ChocolateyInstall ruby
if errorlevel 1 goto :error

SET PATH=%PATH%;C:\tools\ruby21\bin

call :GemInstall bundler
if errorlevel 1 goto :error

if /I "%virtual_kit%" EQU "Virtualbox" (
  call :ChocolateyInstall virtualbox
  if errorlevel 1 goto :error

  call :ChocolateyInstall virtualbox.extensionpack
  if errorlevel 1 goto :error
)

if /I "%virtual_kit%" EQU "VMWare" (
  call :ChocolateyInstall vmwareworkstation
  if errorlevel 1 goto :error
)

call :ChocolateyInstall packer
if errorlevel 1 goto :error

call :ChocolateyInstall vagrant
if errorlevel 1 goto :error

::C:\HashiCorp\Vagrant\bin\vagrant.exe plugin update
if errorlevel 1 goto :error

call :VagrantPluginInstall vagrant-host-shell
if errorlevel 1 goto :error

if /I "%virtual_kit%" EQU "VMWare" (
  call :VagrantPluginInstall vagrant-vmware-workstation
  if errorlevel 1 goto :error
)

::Create sources folder
::Download sources

:: Installing the Packer Windows project
set packer_windows=%MODULE_PACKER_HOME%\packer-windows
if not exist "%MODULE_PACKER_HOME%" mkdir "%MODULE_PACKER_HOME%"
if not exist "%packer_windows%"     mkdir "%packer_windows%"
if not exist "%packer_windows%\.git" (
  "%ProgramFiles(x86)%\Git\cmd\git.exe" clone https://github.com/gildas/packer-windows.git "%packer_windows%"
  if errorlevel 1 goto :error
) else (
  "%ProgramFiles(x86)%\Git\cmd\git.exe" -C "%packer_windows%" pull
  if errorlevel 1 goto :error
)
if exist "%packer_windows%\Gemfile" (
  pushd "%packer_windows%"
  C:\tools\ruby21\bin\bundle.bat install
  if errorlevel 1 (
    popd
    goto :error
  )
  popd
)

goto success

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
