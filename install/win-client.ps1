param(
  [Parameter(Mandatory=$True)[string[]] $Modules

#  [Parameter(Mandatory=$True)][string]  $PuppetMaster,
#  [Parameter(Mandatory=$False)][string] $CertServer = $PuppetMaster,
#  [Parameter(Mandatory=$True)][string]  $Certname,
#  [Parameter(Mandatory=$False)][string] $Environment='production'
)

function Start-ProcessAsAdmin( # {{{2
  [string] $FilePath,
  [string] $Arguments)
{
  if ($FilePath -match ".*powershell")
  {
    $Arguments = "-NoProfile -ExecutionPolicy Unrestricted -Command `"$Arguments`""
  }

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo.Filename               = $FilePath
  $process.StartInfo.Arguments              = $Arguments
  $process.StartInfo.RedirectStandardOutput = $true
  $process.StartInfo.RedirectStandardError  = $true
  $process.StartInfo.UseShellExecute        = $false

  if(([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
  {
    Write-Verbose "Running in elevated process"
    $process.StartInfo.Verb = 'runAs'
  }
  else
  {
    Write-Verbose "Running in an already elevated process"
  }
  if ($process.Start())
  {
    $process.WaitForExit()
    [string] $err = $process.StandardError.ReadToEnd()
    if ( $err -ne "" )
    {
      throw $err
    }
    [string] $out = $process.StandardOutput.ReadToEnd()
    $out
  }
  else
  {
    Write-Error "Cannot start process"
  }
} # }}}2

function Read-HostEx( # {{{2
  [string] $Prompt,
  [string] $CurrentValue,
  [string] $Default,
  [switch] $Force)
{
  Write-Debug "[Read-HostEx]: prompt='$Prompt', current value=$CurrentValue, default=$Default, force=$Force"
  if (! $CurrentValue -or $Force)
  {
    $result = Read-Host -Prompt "$Prompt [$Default]"
    if (! $result)
    {
      Write-Debug "[Read-HostEx]: result was empty, defaulting to $Default"
      $result = $Default
    }
    return $result
  }
  return $CurrentValue
} # }}}2

function Get-Info( # {{{2
  [string] $Module,
  [string] $Version,
  [string] $Source)
{
  $downloader=New-Object Net.Webclient

  Write-Debug "[Get-Info]: getting file list from $Source"
  if ($downloader.DownloadString($Source).Split("`n") | where { $_ -match "$Module-\d\.\d\.\d\.msi" } | Select-Object -Last 1 | %{ $_ -match '.*href="(?<filename>[^"]*)".*' })
  {
    Write-Debug "[Get-Info]: matches=@{$(($matches.keys | %{ "$_ = $($matches[$_])"}) -join ', ' | Out-String)}"
    $filename=$matches['filename']
    Write-Debug "[Get-Info]: analyzing $filename"
    $matched = $filename -match "$Module-(?<version>\d.\d.\d)\.msi"
    Write-Debug "[Get-Info]: matches=@{$(($matches.keys | %{ "$_ = $($matches[$_])"}) -join ', ' | Out-String)}"
    $version = $matches['version']
    $target  = Join-Path $env:TEMP $filename
    $source  = "$Source/$filename"
    Write-Debug "[Get-Info]: filename=$filename, version=$version, target=$target, source=$source"
    New-Object -TypeName PSObject -Property @{ target = $target; source = $source; version = $version }
  }
  else
  {
    $null
  }
} # }}}2

function Download-File( # {{{2
  [string] $Target,
  [string] $Source,
  [switch] $Force)
{
  if ($Force -or ! (Test-Path $Target))
  {
    $downloader=New-Object Net.Webclient

    Write-Host "Downloading $Source into $Target"
    $downloader.DownloadFile($Source, $Target)
  }
  else
  {
    Write-Debug "[Download-File]: Already downloaded"
  }
} # }}}2

function PuppetStuff() # {{{2
{
$PuppetConfig = 'C:/ProgramData/PuppetLabs/puppet/etc/puppet.conf'
$info = Get-Info -Module 'puppet' -Version "*" -Source "http://downloads.puppetlabs.com/windows"
Write-Host "Checking if puppet version $($info.version) is installed already"
$puppet_version = (Get-ItemProperty HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -eq 'Puppet' }).DisplayVersion

if ($puppet_version -ne $null)
{
  Write-Debug "[main]: Command $module has been installed already, collecting current configuration"
  $config = (Get-Content $PuppetConfig | where {$_ -match '^\s*(ca_server|certname|server|environment)\s*='}) -join "`n" | ConvertFrom-StringData
  Write-Debug "[main]: config=@{$(($config.keys | %{ "$_ = $($config[$_])"}) -join ', ' | Out-String)}"
  $DefaultPuppetMaster= $config['server']
  $DefaultCertServer  = $config['ca_server']
  $DefaultCertname    = $config['certname']
  $DefaultEnvironment = $config['environment']
  $DefaultRunInterval = $config['runinterval']
  $want_install = ! ($puppet_version -eq $info.version)
  Write-Debug "[main]: Current puppet is at version: $puppet_version, required version: $($info.version), install required: $want_install"
}
else
{
  Write-Debug "[main]: Command $module has never been installed, building a default configuration"
  $want_install        = $true
  $DefaultPuppetMaster = 'puppet'
  $DefaultCertServer   = 'puppet'
  if (! ('Administrator', 'Admin', 'IT', 'I3 User', 'I3User', 'Guest') -contains $ENV:USERNAME)
  {
    $ID=$ENV:USERNAME
  }
  else
  {
    $ID=(Get-WmiObject Win32_NetworkAdapterConfiguration | where {$_.IpEnabled -eq $True}).MACAddress.Replace(':', '').ToLower()
    if (! $ID)
    {
      $ID=$ENV:COMPUTERNAME
    }
  }
  $DefaultCertname="windows-$ID"
  Write-Debug "[main]: config=[server=$DefaultPuppetMaster, ca_server=$DefaultCertServer, certname=$DefaultCertname, environment=$Environment]"
}

if ($want_install)
{
  Write-Debug "[main]: We need to download!"
  Download-File -Target $info.target -Source $info.source

  # Let's start puppet manually, so we can work on puppet.conf after the installer. We will configure the StartupMode later
  $StartupMode  = 'Manual'
  $PuppetMaster = Read-HostEx -Prompt "Puppet Master" -CurrentValue $PuppetMaster -Default $DefaultPuppetMaster -Force
  if ($DefaultCertServer -eq 'puppet')
  {
    $DefaultCertServer = $PuppetMaster
  }
  $CertServer   = Read-HostEx -Prompt "Certificate Server" -CurrentValue $CertServer -Default $DefaultCertServer -Force
  $UserId       = Read-HostEx -Prompt "What is your user identifier (typically firstname.lastname)" -CurrentValue '' -Default '' -Force
  $Hostname     = Read-HostEx -Prompt "Hostname" -CurrentValue $ID -Default $ID -Force
  $Environment  = Read-HostEx -Prompt "Environment" -CurrentValue $Environment -Default $DefaultEnvironment -Force
  $Certname     = "windows-$Environment-$UserId-$Hostname"

  Write-Host "Installing Puppet against master [$PuppetMaster] as [$Certname]"
  $MSI_Path=$info.target
  $MSI_Logs="C:/Windows/Logs/install-puppet-$(Get-Date -UFormat '%Y%m%d%H%M%S').log"
  $MSI_Arguments="PUPPET_MASTER_SERVER=$PuppetMaster PUPPET_AGENT_CERTNAME=$($Certname.ToLower())"
  if ($CertServer)  { $MSI_Arguments="$MSI_Arguments PUPPET_CA_SERVER=$CertServer" }
  if ($Environment) { $MSI_Arguments="$MSI_Arguments PUPPET_AGENT_ENVIRONMENT=$Environment" }
  $MSI_Arguments="$MSI_Arguments PUPPET_AGENT_STARTUP_MODE=$StartupMode"
  Write-Debug "MSI Arguments: $MSI_Arguments"

  Start-ProcessAsAdmin "msiexec.exe" "/qn /i $MSI_Path /l*v $MSI_Logs $MSI_Arguments"

  # Update the runinterval to 5 minutes, so puppet can configure this host earlier
  if (get-Content $PuppetConfig  | Where-Object { $_ -match "^\s*runinterval\*=" })
  {
    Write-Host "Puppet Service: Replacing the runinterval to 300 seconds"
    Start-ProcessAsAdmin powershell "Get-Content $PuppetConfig | ForEach-Object { $_ -replace "(^\s*runinterval\s*=\s*)\d+$","$1 300" } | Set-Content $PuppetConfig"
  }
  else
  {
    Write-Host "Puppet Service: Adding a runinterval of 300 seconds"
    $process = Start-ProcessAsAdmin powershell "Add-Content $PuppetConfig '`n  runinterval = 300' -Force"
  }

  # Configure and starts the puppet service
  if (get-Content $PuppetConfig  | Where-Object { $_ -match "^\s*runinterval\*=" })
  {
    Write-Host "Configuring and Starting Puppet Windows Service"
    Start-ProcessAsAdmin powershell "Set-Service puppet -StartupType Automatic -Status Running"
  }
  else
  {
    Write-Error "Could not set the runinterval"
  }
}
else
{
  Write-Debug "[main]: No need to install a new version"
  Write-Host "Validating Puppet Configuration:"

  $PuppetMaster = Read-HostEx -Prompt "Puppet Master" -CurrentValue $PuppetMaster -Default $DefaultPuppetMaster -Force
  if ($DefaultCertServer -eq 'puppet')
  {
    $DefaultCertServer = $PuppetMaster
  }
  $NewCertServer   = Read-HostEx -Prompt "Certificate Server" -CurrentValue $CertServer -Default $DefaultCertServer -Force
  $NewCertname     = Read-HostEx -Prompt "Certificate Name" -CurrentValue $Certname -Default $DefaultCertname -Force
  $NewEnvironment  = Read-HostEx -Prompt "Environment" -CurrentValue $Environment -Default $DefaultEnvironment -Force

  # Update the runinterval to 5 minutes, so puppet can configure this host earlier
  Write-Host "Checking runinterval"
  if (get-Content $PuppetConfig  | Where-Object { $_ -match "^\s*runinterval\s*=\s*(\d+)$" })
  {
    Write-Host "runinterval is configured to $($Matches[1])"
    if ($Matches[1] -ne 300)
    {
      Write-Host "Puppet Service: Setting the runinterval to 300 seconds from $($Matches[1]) seconds"
      Start-ProcessAsAdmin powershell "Stop-Service puppet"
      (Get-Content $PuppetConfig) -replace '(^\s*runinterval\s*=\s*)\d+$','$1 300' | Set-Content C:\Windows\TEMP\puppet.conf
      Start-ProcessAsAdmin powershell "Move-Item C:\Windows\TEMP\puppet.conf $PuppetConfig -Force"
    }
  }
  else
  {
    Write-Host "Puppet Service: Adding a runinterval of 300 seconds"
    Start-ProcessAsAdmin powershell "Stop-Service puppet"
    Start-ProcessAsAdmin powershell "Add-Content $PuppetConfig '`r`n  runinterval = 300' -Force"
  }
  if (get-Content $PuppetConfig  | Where-Object { $_ -match "^\s*runinterval\*=\*300$" })
  {
    Write-Host "Configuring and Starting Puppet Windows Service"
    Start-ProcessAsAdmin powershell "Set-Service puppet -StartupType Automatic -Status Running"
  }
  else
  {
    Write-Error "Could not set the runinterval"
  }
}
} # }}}2
Function Install-Chocolatey() # {{{2
{
  Start-ProcessAsAdmin 'powershell' "iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))"
} # }}}2

process
{
  $Modules = 'chocolatey'

  Install-Chocolatey
}
# TODO:
# chocolatey
# git
# 7zip
# md5
# ruby
# imdisk
# vagrant 1.6.5
# packer, packer-windows-plugins
# virtualbox
# vmware, vagrant-vmware
# folders
