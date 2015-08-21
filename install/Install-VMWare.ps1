[CmdLetBinding(SupportsShouldProcess)]
Param(
  [Parameter(Mandatory=$false)]
  [string] $VirtualMachinesHome,
  [Parameter(Mandatory=$false)]
  [string] $License
)
function ConvertFrom-Ini
{
  Param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [string] $InputObject
  )
  process
  {
    $config = [ordered]@{}
    $InputObject -split "`n" | Foreach {
      switch -regex ($_)
      {
        '(.+?)\s*=\s*"(.*)"' # Key
        {
            $name,$value = $matches[1..2]
            $config[$name] = $value
        }
      }
    }
    return $config
  }
}

  # 1. Intall VMWare via Chocolatey
  if ((choco list -l | Where { $_ -match 'vmwareworkstation.*' }) -eq $null)
  {
    Write-Output "Installing VMWare Workstation"
    if ($PSBoundParameters.ContainsKey('License'))
    {
      choco install -y vmwareworkstation --installarguments "SERIALNUMBER=$License"
    }
    else
    {
      choco install -y vmwareworkstation
    }
  }
  else
  {
    Write-Verbose "Checking VMWare Workstation"
    $results = choco list vmwareworkstation | Select-String -Pattern '^vmwareworkstation\s+(.*)'

    if ($results.matches.Length -gt 0)
    {
      $available = $results.matches[0].Groups[1].Value
      $results = choco list -l vmwareworkstation | Select-String -Pattern '^vmwareworkstation\s+(.*)'

      Write-Verbose "  VMWare Workstation v$available is available"
      if ($results.matches.Length -gt 0)
      {
        $current = $results.matches[0].Groups[1].Value
        Write-Verbose "  VMWare Workstation v$current is installed"
        if ($current -ne $available)
        {
          Write-Output "  Upgrading to VMWare Workstation v$available"
          choco upgrade -y vmwareworkstation
        }
        else
        {
          Write-Verbose "VMWare Workstation v$available is already installed"
        }
      }
    }
  }

  # 2. Set Virtual Machine Home
  if ($PSBoundParameters.ContainsKey('VirtualMachinesHome'))
  {
    if (! (Test-Path $VirtualMachinesHome))
    {
      New-Item -ItemType 'Directory' -Path $VirtualMachinesHome
    }

    $filename = Join-Path $env:APPDATA (Join-Path 'VMWare' 'preferences.ini')
    if (Test-Path $filename)
    {
      $preferences  = Get-Content -Raw -Path $filename | ConvertFrom-Ini
    }
    else
    {
      $preferences  = @{}
    }
    $current_home = $preferences['prefvmx.defaultVMPath']

    Write-Verbose "Current Virtual Machines Home: $current_home"
    if (($current_home -eq $null) -or ($current_home -ne $VirtualMachinesHome))
    {
      Write-Verbose "  Updating to $VirtualMachinesHome"
      $preferences['prefvmx.defaultVMPath'] = $VirtualMachinesHome
      If (! (Test-Path (Join-Path $env:APPDATA 'VMWare'))) { mkdir Join-Path $env:APPDATA 'VMWare' }
      $preferences.Keys | Foreach { Write-Output "$_ = `"$($preferences[$_])`"" } | Set-Content -Path $filename
    }
    else
    {
      Write-Verbose "  is already set properly"

    }
  }
