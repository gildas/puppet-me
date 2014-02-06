param(
  [Parameter(Mandatory=$true)][string] $PuppetMaster,
  [Parameter(Mandatory=$true)][string] $ClientCert,
  [string] $Environment='production'
)

function Curl-File(
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

$destination = Curl-File -Module "Puppet" -Version "*" -Source "http://downloads.puppetlabs.com/windows/"

Write-Host "Installing $destination"
Start-Process -File "msiexec.exe" -arg "/qn /i $destination /l*v install-puppet.log PUPPET_MASTER_SERVER=$PuppetMaster PUPPET_AGENT_CERTNAME=$ClientCert" -PassThru | Wait-Process
