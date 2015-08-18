[CmdLetBinding(SupportsShouldProcess)]
Param(
  [Parameter(Mandatory=$true)]
  [string] $Uri,
  [Parameter(Mandatory=$true)]
  [string] $CacheRoot,
  [Parameter(Mandatory=$false)]
  [string] $Network
)
begin
{
  if ($PSBoundParameters.ContainsKey('Network'))
  {
    $local_ip_address = $Network
  }
  else
  {
    $ipconfig = Get-NetIPAddress | ? { ($_.AddressFamily -eq 'IPv4') -and ($_.PrefixOrigin -eq 'Dhcp') }
    $local_ip_address = "$($ipconfig.IPAddress)/$($ipconfig.PrefixLength)"
  }
  Write-Verbose "My address: $local_ip_address"
}
process
{
  if (! (Test-Path $CacheRoot))
  {
    Write-Output "Creating Cache folder: $CacheRoot"
    New-Item -Path $CacheRoot -ItemType Directory | Out-Null
    if (! $?) { return $LastExitCode }
  }

  Write-Verbose "Downloading sources configuration"
  if ($PSCmdlet.ShouldProcess($Uri, "Downloading sources configuration"))
  {
    #Start-BitsTransfer -Source $Uri -Destination (Join-Path $CacheRoot 'config.json') -Verbose:$false
    (New-Object System.Net.Webclient).DownloadFile($Uri, (Join-Path $CacheRoot 'config.json'))
    if (! $?) { return $LastExitCode }

    $sources = (Get-Content -Raw -Path (Join-Path $CacheRoot 'config.json') | ConvertFrom-Json)
  }
  else
  {
    #Start-BitsTransfer -Source $Uri -Destination (Join-Path $CacheRoot 'config.json') -Verbose:$false
    (New-Object System.Net.Webclient).DownloadFile($Uri, (Join-Path $env:TEMP 'config.json'))
    if (! $?) { return $LastExitCode }

    $sources = (Get-Content -Raw -Path (Join-Path $env:TEMP 'config.json') | ConvertFrom-Json)
  }

  Write-Verbose "Downloading $($sources.Count) sources"
  foreach ($source in $sources)
  {
    switch ($source.action)
    {
      delete
      {
        $path = Join-Path $CacheRoot $source.destination
        if (Test-Path $path)
        {
          Write-Output "Deleting $($source.Name)..."
          Remove-Item $path -Recurse
        }
      }
      default
      {
        Write-Verbose "Validating $($source.Name)..."
        $destination = $cacheRoot
        if ($source.destination -ne $null)
        {
          $destination = Join-Path $CacheRoot $source.destination
        }
        if (! (Test-Path $destination))
        {
          New-Item -Path $destination -ItemType Directory
        }
        if (($source.filename -notlike '*`**') -and ($source.filename -notlike '*`?*'))
        {
          $destination = Join-Path $destination $source.filename
        }

        if ((Test-Path $destination) -and ($source.checksum -ne $null))
        {
          # TODO: What if the type is not written in the config?
          $checksum = (Get-FileHash $destination -Algorithm $source.checksum.type).Hash
          if ($checksum -eq $source.checksum.value)
          {
            Write-Output "  is already downloaded and verified ($($source.checksum.type))"
            continue
          }
        }
        $location=$null
        foreach ($loc in $source.locations)
        {
          Write-Verbose "  Checking in $($loc.location), regex: $($loc.network)"
          if ($local_ip_address -match $loc.network)
          {
            $location=$loc
            break
          }
        }
        if ($location -ne $null)
        {
          if ($location.vpn -ne $null)
          {
            Write-Verbose "Starting VPN $($location.vpn)"
          }
          Write-Output  "Downloading $($source.Name)..."
          Write-Output  "  From $($location.location)"
          $source_url="$($location.url)$($source.filename)"
          if ($source_url -match '^([^:]+)://([^/]+)/([^/]+)/(.*)')
          {
            $source_protocol = $matches[1].ToLower()
            $source_host     = $matches[2]
            if ($source_protocol -eq 'smb')
            {
              $source_share = [System.Web.HttpUtility]::UrlDecode($matches[3])
              $source_path  = [System.Web.HttpUtility]::UrlDecode($matches[4]) -replace '/', '\'
              $source_url   = "\\${source_host}\${source_share}\${source_path}"
            }
            else
            {
              $source_share = ''
              $source_path  = [System.Web.HttpUtility]::UrlDecode($matches[3]) + '/' + [System.Web.HttpUtility]::UrlDecode($matches[4])
            }
          }
          else
          {
            Write-Error "Invalid URL: $source_url"
            continue
          }
          Write-Verbose "  Source: $source_url"
          Write-Verbose "  Dest:   $destination"
          $request_args=@{}

          # 1st, try with the logged in user
          if ($PSCmdlet.ShouldProcess($destination, "Downloading from $($location.location)"))
          {
            if (-not (Start-BitsTransfer -Source $source_url -Destination $destination @request_args))
            {
              if (($location.need_auth -ne $null) -and $location.need_auth)
              {
                Write-Verbose "Collecting credential"
                if ($PSCmdlet.ShouldProcess($source_url, "Getting credential for $source_host"))
                {
                  if ($source_protocol -eq 'smb')
                  {
                    $message = "Enter your credentials to connect to share $source_share on $source_host"
                  }
                  else
                  {
                    $message = "Enter your credentials to connect to $source_host over $source_protocol"
                  }
                  $request_args['Credential'] = Get-Credential -Message $message
                }
              }
              Start-BitsTransfer -Source $source_url -Destination $destination @request_args
            }
          }
          if (! $?) { return $LastExitCode }
        }
        else
        {
          Write-Warning " Cannot download $($source.Name), no location found"
        }
      }
    }
  }
  }
