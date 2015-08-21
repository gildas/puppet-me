[CmdLetBinding(SupportsShouldProcess)]
Param()
process
{
  $hyperv_status = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -Verbose:$False

  if ($hyperv_status.State -eq 'Enabled')
  {
    Write-Verbose "Enabling Hyper-V"
    Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -NoRestart

    $hyperv_status = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -Verbose:$False

    if ($hyperv_status.State -eq 'Enabled')
    {
      Throw "Unable to uninstall Hyper-V"
    }
    elseif ($hyperv_status.State -eq 'DisablePending')
    {
      Write-Warning "Hyper-V is uninstalled, but needs a restart"
    }
  }
  elseif ($hyperv_status.State -eq 'EnablePending')
  {
    Write-Warning "Hyper-V is installed, but needs a restart before you can uninstall it"
  }
  elseif  ($hyperv_status.State -eq 'Disabled')
  {
    Write-Verbose "Hyper-V is already uninstalled"
  }
}
