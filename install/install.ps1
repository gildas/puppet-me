param(
  [Parameter(Mandatory=$True)][string]  $PuppetMaster,
  [Parameter(Mandatory=$False)][string] $CertServer = $PuppetMaster,
  [Parameter(Mandatory=$True)][string]  $Certname,
  [Parameter(Mandatory=$False)][string] $Environment='production'
)

function Read-HostEx(
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
}

function Get-Info(
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
}

function Download-File(
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
}

$info = Get-Info -Module 'puppet' -Version "*" -Source "http://downloads.puppetlabs.com/windows"
Write-Host "Checking if puppet version $($info.version) is installed already"

if (Get-Command 'puppet' 2> $null)
{
  Write-Debug "[main]: Command $module has been installed already, collecting current configuration"
  $config = (Get-Content C:/ProgramData/PuppetLabs/puppet/etc/puppet.conf | where {$_ -match '^\s*(ca_server|certname|server|environment)\s*='}) -join "`n" | ConvertFrom-StringData
  Write-Debug "[main]: config=@{$(($config.keys | %{ "$_ = $($config[$_])"}) -join ', ' | Out-String)}"
  $DefaultPuppetMaster=$config['server']
  $DefaultCertServer  =$config['ca_server']
  $DefaultCertname    =$config['certname']
  $DefaultEnvironment =$config['environment']
  $puppet_version=$(puppet --version)
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

  $PuppetMaster = Read-HostEx -Prompt "Puppet Master" -CurrentValue $PuppetMaster -Default $DefaultPuppetMaster -Force
  if ($DefaultCertServer -eq 'puppet')
  {
    $DefaultCertServer = $PuppetMaster
  }
  $CertServer   = Read-HostEx -Prompt "Certificate Server" -CurrentValue $CertServer -Default $DefaultCertServer -Force
  $Certname     = Read-HostEx -Prompt "Certificate Name" -CurrentValue $Certname -Default $DefaultCertname -Force
  $Environment  = Read-HostEx -Prompt "Environment" -CurrentValue $Environment -Default $DefaultEnvironment -Force

  Write-Host "Installing Puppet against master [$PuppetMaster] as [$Certname]"
  $MSI_Path=$info.target
  $MSI_Logs="C:/Windows/Logs/install-puppet-$(Get-Date -UFormat '%Y%m%d%H%M%S').log"
  $MSI_Arguments="PUPPET_MASTER_SERVER=$PuppetMaster PUPPET_AGENT_CERTNAME=$($Certname.ToLower())"
  if ($CertServer)  { $MSI_Arguments="$MSI_Arguments PUPPET_CA_SERVER=$CertServer" }
  if ($Environment) { $MSI_Arguments="$MSI_Arguments PUPPET_AGENT_ENVIRONMENT=$Environment" }
  Write-Debug "MSI Arguments: $MSI_Arguments"
  if(([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
  {
    Write-Debug "Running in an already elevated process"
    Start-Process -File "msiexec.exe" -arg "/qn /i $MSI_Path /l*v $MSI_Logs $MSI_Arguments" -PassThru | Wait-Process
  }
  else
  {
    Write-Host "Running installer in elevated process"
    Start-Process -Verb runAs -File "msiexec.exe" -arg "/qn /i $MSI_Path /l*v $MSI_Logs $MSI_Arguments" -PassThru | Wait-Process
  }
}
else
{
  Write-Debug "[main]: No need to install a new version"
}
