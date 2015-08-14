@if not defined PACKER_DEBUG (@echo off) else (@echo on)
setlocal EnableDelayedExpansion EnableExtensions

:: Installation:
:: bitsadmin /transfer puppet-me /download /priority normal https://raw.githubusercontent.com/inin-apac/puppet-me/windows/install/win-8.1-client.cmd %TEMP%\zz.cmd && type %TEMP%\zz.cmd | more /p > %TEMP%\win-8.1-client.cmd && %TEMP%\win-8.1-client.cmd Virtualization
:::: bitsadmin will take care of the download.
:::: Using type+more allows to change CR (unix) into CRLF (dos). Executing cmd files in unix mode leads to heisenbugs.
:::: [Virtualization] should be one of the following (case insensitive) values: Virtualbox, VMWare
set CURRENT_DIR=%~dp0%
set posh=%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile

set CACHE_ROOT=%ProgramData%\DaaS\cache
set CACHE_CONFIG=https://cdn.rawgit.com/inin-apac/puppet-me/608341359a0ad4c0bd335f80bcaac7b9b7c411a1/config/sources.json
set MODULE_PACKER_HOME=%USERPROFILE%\Documents\packer
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
call gem list --local | findstr /C:"%gem%" >NUL
if %ERRORLEVEL% EQU 0 goto GemInstallOK
title Installing Ruby gem %~1...
call gem install  %gem%
if errorlevel 1 goto :EOF
:GemInstallOK    
echo Ruby gem %gem% is installed
goto :EOF
:: Function: GemInstall }}}2

:: Function: VagrantPluginInstall {{{2
:: See http://www.dostips.com/forum/viewtopic.php?f=3&t=3487 for explanation about while/for/goto
:: We have to try the install severak times as it can fail from time
::   to time for no real good reason!!!
:VagrantPluginInstall    
set plugin=%~1
C:\HashiCorp\Vagrant\bin\vagrant.exe plugin list | findstr /C:"%plugin%" >NUL
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
:: TODO: Allow ruby through the firewall?

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

::Download sources
if not exist "%CACHE_ROOT%" mkdir "%CACHE_ROOT%"
echo Downloading DaaS cache sources configuration...
call :Download "%CACHE_CONFIG%" %TEMP%
if errorlevel 1 goto :EOF

:: Installing the Packer Windows project
set packer_windows=%MODULE_PACKER_HOME%\packer-windows
if not exist "%packer_windows%" mkdir "%packer_windows%"
if not exist "%packer_windows%\.git" (
  "%ProgramFiles(x86)%\Git\cmd\git.exe" clone https://github.com/gildas/packer-windows.git "%packer_windows%"
  if errorlevel 1 goto :error
) else (
  "%ProgramFiles(x86)%\Git\cmd\git.exe" -C "%packer_windows%" pull
  if errorlevel 1 goto :error
)
if exist "%packer_windows%\Gemfile" (
  pushd "%packer_windows%"
  call C:\tools\ruby21\bin\bundle.bat install
  if errorlevel 1 (
    popd
    goto :error
  )
  popd
)

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
