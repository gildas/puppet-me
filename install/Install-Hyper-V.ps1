[CmdLetBinding(SupportsShouldProcess)]
Param()
process
{
  $hyperv_status = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -Verbose:$False

  if ($hyperv_status.State -eq 'Disabled')
  {
    Write-Verbose "Enabling Hyper-V"
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart

    $hyperv_status = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -Verbose:$False
    if ($hyperv_status.State -eq 'Disabled')
    {
      Throw "Unable to install Hyper-V"
    }
    elseif ($hyperv_status.State -eq 'EnablePending')
    {
      Write-Warning "Hyper-V is installed, but needs a restart before being usable"
    }
  }
  elseif  ($hyperv_status.State -eq 'Enabled')
  {
    Write-Verbose "Hyper-V is already enabled"
    return
  }
  elseif ($hyperv_status.State -eq 'EnablePending')
  {
    Write-Warning "Hyper-V is already installed, but needs a restart before being usable"
  }
}
