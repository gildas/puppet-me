function Install-Package
{
  param
  (
    [string]$Source,
    [string]$Version,
    [string]$Package
  )
  
  $package = '1234.msi'
  $url = $Source + $package
  $destination = Join-Path $env:TEMP $package
  Write-Host "Downloading $url to $file"
  ((new-object net.webclient).DownloadFile($url, $destination)
}

# install PuppetLabs from their website
Install-Package -Source 'http://downloads.puppetlabs.com/windows/' -Version '*' -Package facter

