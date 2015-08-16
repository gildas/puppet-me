if ($env:VBOX_MSI_INSTALL_PATH -eq $null) { $env:VBOX_MSI_INSTALL_PATH = [System.Environment]::GetEnvironmentVariable("VBOX_MSI_INSTALL_PATH", "Machine") }
$vboxManage=Join-Path $env:VBOX_MSI_INSTALL_PATH 'VBoxManage.Exe'

$vboxVersion= & $vboxManage --version
if (! $?) { return $LastExitCode }

$vboxExtensionPackInfo = & $vboxManage list extpacks | % { if ($_ -match "(.*)\s*:\s+(.*)") { @{ $matches[1]=$matches[2]; } } }

if ($vboxVersion -ne "$($vboxExtensionPackInfo.Version)r$($vboxExtensionPackInfo.Revision)")
{
  $vboxExtensionPack="Oracle_VM_VirtualBox_Extension_Pack-$($vboxVersion -replace 'r','-').vbox-extpack"
  $url="http://download.virtualbox.org/virtualbox/$($vboxVersion -replace 'r.*','')/${vboxExtensionPack}"

  Write-Output "Downloading $url"
  Start-BitsTransfer -Source $url -Destination (Join-Path $env:TEMP $vboxExtensionPack) -Verbose:$false
  if (! $?) { return $LastExitCode }

  Write-Output "Installing Extension pack version ${vboxVersion}"
  & $vboxManage extpack install --replace (Join-Path $env:TEMP $vboxExtensionPack)
  if (! $?)
  {
    $lec = $LastExitCode
    return $lec
  }
}
else
{
  Write-Output "Virtualbox Extension Pack $vboxVersion is already installed"
}
