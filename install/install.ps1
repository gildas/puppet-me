param(
  [Parameter(Mandatory=$True)][string] $PuppetMaster,
  [Parameter(Mandatory=$True)][string] $ClientCert,
  [string] $Environment='production'
)

if (! $PuppetMaster)
{
  $DefaultPuppetMaster='puppet'
  $PuppetMaster = Read-Host "Puppet Master [$DefaultPuppetMaster]"
  if (! $PuppetMaster)
  {
    $PuppetMaster=$DefaultPuppetMaster
  }
}

if (! $ClientCert)
{
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
  $DefaultClientCert="windows-$Environment-$ID"
  $ClientCert = Read-Host "Client Certificate Name [$DefaultClientCert]"
  if (! $ClientCert)
  {
    $ClientCert=$DefaultClientCert
  }
}

function Download-File(
  [string] $Module,
  [string] $Version,
  [string] $Source)
{
  $downloader=New-Object Net.Webclient

  $result=$downloader.DownloadString($Source).Split("`n") | where { $_ -match "$Module-\d\.\d\.\d\.msi" } | Select-Object -Last 1 | %{ $_ -match '.*href="(?<filename>[^"]*)".*' }
  $filename=$matches['filename']

  $destination = Join-Path (Join-Path $env:USERPROFILE "DownLoads") $filename

  Write-Host "Downloading $Source/$filename into $destination"
  $downloader.DownloadFile("$Source/$filename", $destination)

  return $destination
}

$destination = Download-File -Module "Puppet" -Version "*" -Source "http://downloads.puppetlabs.com/windows"

Write-Host "Installing Puppet against master [$PuppetMaster] as [$ClientCert]"
if(([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
  Start-Process -File "msiexec.exe" -arg "/qn /i $destination /l*v install-puppet.log PUPPET_MASTER_SERVER=$PuppetMaster PUPPET_AGENT_CERTNAME=$ClientCert" -PassThru | Wait-Process
}
else
{
  Write-Host "Running installer in elevated process"
  Start-Process -Verb runAs -File "msiexec.exe" -arg "/qn /i $destination /l*v install-puppet.log PUPPET_MASTER_SERVER=$PuppetMaster PUPPET_AGENT_CERTNAME=$ClientCert" -PassThru | Wait-Process
}
