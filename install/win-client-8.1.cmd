@if not defined PACKER_DEBUG (@echo off) else (@echo on)
setlocal EnableDelayedExpansion EnableExtensions

title DaaS setup

set CURRENT_DIR=%~dp0%

goto main

:: functions
:Download
echo Downloading %~1 into %~2
for /f "useback tokens=* delims=/" %%a in ("%~1") do set filename=%%a
echo Filename: %filename%
::%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy ByPass -Command "((new-object net.webclient).DownloadFile('https://chocolatey.org/install.ps1', '%TEMP%\install.ps1'))"

goto :EOF

:main

echo Checking Chocolatey...
where.exe /q chocolatey.exe
if %ERRORLEVEL% EQU 0 goto installed_chocolatey
if EXIST %ALLUSERSPROFILE%\chocolatey\bin\chocolatey.exe (
  SET PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin
  goto installed_chocolatey
)
goto installing_chocolatey

:installing_chocolatey
title Installing Chocolatey...
echo Downloading Chocolatey Installer...
::call :Download "https://chocolatey.org/install.ps1" %TEMP%
%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy ByPass -Command "((new-object net.webclient).DownloadFile('https://chocolatey.org/install.ps1', '%TEMP%\install.ps1'))"
if errorlevel 1 goto installing_chocolatey
echo Installing Chocolatey...
%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy ByPass -Command "& '%TEMP%\install.ps1' %*"
if errorlevel 1 goto installing_chocolatey
SET PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin
goto installed_chocolatey

:installed_chocolatey
echo Chocolatey is installed
call :Download "https://chocolatey.org/install.ps1" %TEMP%

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
