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
  if (! $CurrentValue -or $Force)
  {
    $result = Read-Host -Prompt "$Prompt [$Default]"
    if (! $result)
    {
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

  $downloader.DownloadString($Source).Split("`n") | where { $_ -match "$Module-\d\.\d\.\d\.msi" } | Select-Object -Last 1 | %{ $_ -match '.*href="(?<filename>[^"]*)".*' }
  $filename=$matches['filename']
  $filename -match "$Module-(?<version>\d.\d.\d)\.msi"
  $version = $matches['version']
  $target  = Join-Path (Join-Path $env:USERPROFILE "DownLoads") $filename
  $source  = "$Source/$filename"
  return New-Object -TypeName PSObject -Property @{ 'target' = $target, 'source' = $source, 'version' = $version }
}

function Download-File(
  [string] $Target,
  [string] $Source,
  [switch] $Force)
{
  if ($Force -or ! Test-Path $Target)
  {
    $downloader=New-Object Net.Webclient

    Write-Host "Downloading $Source into $Target"
    $downloader.DownloadFile($Source, $Target)
  }
}

$module = "puppet"
$info = Get-Version -Module $module -Version "*" -Source "http://downloads.puppetlabs.com/windows"

if (Get-Command $module)
{
  $config = $module config | where {$_ -match 'ˆ(ca_server|certname|server|environment) ='} | ConvertFrom-StringData
  $DefaultPuppetMaster=$config.server
  $DefaultCertServer  =$config.ca_server
  $DefaultCertname    =$config.certname
  $DefaultEnvironment =$config.environment
}
else
{
  $DefaultPuppetMaster = 'puppet'
  $DefaultCertServer   = 'puppet'
  if (! ('Administrator', 'Admin', 'IT', 'I3 User', 'I3User', 'Guest') -contains $ENV:USERNAME)
  {
    $ID=$ENV:USERNAME
  }
  else
  {
    $ID=(Get-WmiObject Win32_NetworkAdapterConfiguration | where {$_.IpEnabled -eq $True}).MACAddress.Replace(':', '')
    if (! $ID)
    {
      $ID=$ENV:COMPUTERNAME
    }
  }
  $DefaultCertname="windows-$Environment-$ID"
}

$PuppetMaster = Read-HostEx -Prompt "Puppet Master" -CurrentValue $PuppetMaster -Default $DefaultPuppetMaster -Force
$CertServer   = Read-HostEx -Prompt "Certificate Server" -CurrentValue $CertServer -Default $DefaultCertServer -Force
$Certname     = Read-HostEx -Prompt "Certificate Name" -CurrentValue $Certname -Default $DefaultCertname -Force
$Environment  = Read-HostEx -Prompt "Environment" -CurrentValue $Environment -Default $DefaultEnvironment -Force

if (!Get-Command 'puppet' -or ! $(puppet --version) -eq $info.version)
{
  Download-File -Target $info.target -Source $info.source

  Write-Host "Installing Puppet against master [$PuppetMaster] as [$ClientCert]"
  $MSI_Path=$info.target
  $MSI_Logs="C:/Windows/Logs/install-puppet.log"
  $MSI_Arguments="PUPPET_MASTER_SERVER=$PuppetMaster PUPPET_CA_SERVER=$CertServer PUPPET_AGENT_CERTNAME=$Certname PUPPET_AGENT_ENVIRONMENT=$Environment"
  if(([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
  {
    Start-Process -File "msiexec.exe" -arg "/qn /i $MSI_Path /l*v $MSI_Logs $MSI_Arguments" -PassThru | Wait-Process
  }
  else
  {
    Write-Host "Running installer in elevated process"
    Start-Process -Verb runAs -File "msiexec.exe" -arg "/qn /i $MSI_Path /l*v $MSI_Logs $MSI_Arguments" -PassThru | Wait-Process
  }
}
