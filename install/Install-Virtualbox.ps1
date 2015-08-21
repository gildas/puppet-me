[CmdLetBinding(SupportsShouldProcess)]
Param(
  [Parameter(Mandatory=$false)]
  [string] $VirtualMachinesHome,
  [Parameter(Mandatory=$false)]
  [switch] $NoExtensionPack
)
process
{
  # 1. Intall Virtualbox via Chocolatey
  if ((choco list -l | Where { $_ -match 'virtualbox.*' }) -eq $null)
  {
    Write-Output "Installing Virtualbox"
    choco install -y virtualbox
  }
  else
  {
    Write-Verbose "Checking Virtualbox"
    $results = choco list virtualbox | Select-String -Pattern '^virtualbox\s+(.*)'

    if ($results.matches.Length -gt 0)
    {
      $available = $results.matches[0].Groups[1].Value
      $results = choco list -l virtualbox | Select-String -Pattern '^virtualbox\s+(.*)'

      Write-Verbose "  Virtualbox v$available is available"
      if ($results.matches.Length -gt 0)
      {
        $current = $results.matches[0].Groups[1].Value
        Write-Verbose "  Virtualbox v$current is installed"
        if ($current -ne $available)
        {
          Write-Output "  Upgrading to Virtualbox v$available"
          choco upgrade -y virtualbox
        }
        else
        {
          Write-Verbose "Virtualbox v$available is already installed"
        }
      }
    }
  }

  # 2. Get VBoxManage
  if ($env:VBOX_MSI_INSTALL_PATH -eq $null) { $env:VBOX_MSI_INSTALL_PATH = [System.Environment]::GetEnvironmentVariable("VBOX_MSI_INSTALL_PATH", "Machine") }
  $vboxManage=Join-Path $env:VBOX_MSI_INSTALL_PATH 'VBoxManage.Exe'

  $vboxVersion= & $vboxManage --version
  if (! $?) { return $LastExitCode }

  # 3. Set Virtual Machine Home
  if ($PSBoundParameters.ContainsKey('VirtualMachinesHome'))
  {
    $results = & $vboxManage list systemproperties | Select-String -Pattern '^Default machine folder:\s*(.*)'

    if ($results.matches.Length -gt 0)
    {
      $current_home = $results.matches[0].Groups[1].Value
      Write-Verbose "Current Virtual Machines Home: $current_home"
      if ($current_home -ne $VirtualMachinesHome)
      {
        Write-Verbose "  Updating to $VirtualMachinesHome"
        & $vboxManage setproperty machinefolder "$VirtualMachinesHome"
        if (! $?) { return $LastExitCode }
      }
    }
    else
    {
      Write-Warning "There is no default machine folder in Virtualbox at the moment"
    }
  }

  # 4. Install or Upgrade the Extension Pack
  $vboxExtensionPackInfo = & $vboxManage list extpacks | % { if ($_ -match "(.*)\s*:\s+(.*)") { @{ $matches[1]=$matches[2]; } } }

  if ($vboxVersion -ne "$($vboxExtensionPackInfo.Version)r$($vboxExtensionPackInfo.Revision)")
  {
    $vboxExtensionPack="Oracle_VM_VirtualBox_Extension_Pack-$($vboxVersion -replace 'r','-').vbox-extpack"
    $url="http://download.virtualbox.org/virtualbox/$($vboxVersion -replace 'r.*','')/${vboxExtensionPack}"

    Write-Output "Downloading $url"
    Start-BitsTransfer -Source $url -Destination (Join-Path $env:TEMP $vboxExtensionPack) -Verbose:$false
    if (! $?) { return $LastExitCode }

    Write-Output "Installing Extension pack version v${vboxVersion}"
    & $vboxManage extpack install --replace (Join-Path $env:TEMP $vboxExtensionPack)
    if (! $?)
    {
      $lec = $LastExitCode
      return $lec
    }
  }
  else
  {
    Write-Verbose "Virtualbox Extension Pack v$vboxVersion is already installed"
  }
}
