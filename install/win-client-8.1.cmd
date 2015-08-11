@if not defined PACKER_DEBUG (@echo off) else (@echo on)
setlocal EnableDelayedExpansion EnableExtensions

title DaaS setup

set CURRENT_DIR=%~dp0%

echo Checking Explorer...
@powershell -NoProfile -ExecutionPolicy unrestricted -Command "Get-Command 'explorer' -TotalCount 1 -ErrorAction SilentlyContinue | ForEach-Object { $_.Path }"
echo Errorlevel: %ERRORLEVEL%
if errorlevel 0 echo installed
if errorlevel 1 echo not installed

echo Checking Chocolatey...
@powershell -NoProfile -ExecutionPolicy unrestricted -Command "Get-Command 'chocolatey' -TotalCount 1 -ErrorAction SilentlyContinue | ForEach-Object { $_.Path }"
echo Errorlevel: %ERRORLEVEL%
if errorlevel 0 echo installed
if errorlevel 1 echo not installed

echo Checking Chocolatey...
@powershell -NoProfile -ExecutionPolicy unrestricted -Command "Get-Command 'chocolatey' -TotalCount 1 -ErrorAction SilentlyContinue | ForEach-Object { $_.Path }"
if errorlevel 1 goto installing_chocolatey
goto installed_chocolatey

:installing_chocolatey
title Installing Chocolatey...
echo Installing Chocolatey...
%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy ByPass -Command "((new-object net.webclient).DownloadFile('https://chocolatey.org/install.ps1', '%TEMP%\install.ps1'))"
if errorlevel 1 goto installing_chocolatey
%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy ByPass -Command "& '%TEMP%\install.ps1' %*"
if errorlevel 1 goto installing_chocolatey
goto installed_chocolatey

:installed_chocolatey
echo Chocolatey is installed

goto success

:success
title _
echo Your computer is now ready
goto end

:error
title error!
echo Your computer is not ready
goto end

:end
