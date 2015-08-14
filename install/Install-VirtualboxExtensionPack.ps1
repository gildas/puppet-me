
$url="http://download.virtualbox.org/virtualbox"
$vboxManage=Join-Path $env:VBOX_MSI_INSTALL_PATH 'VBoxManage.Exe'

$vboxVersion= & $vboxManage --version
$vboxExtensionPack="Oracle_VM_VirtualBox_Extension_Pack-$($vboxVersion -replace 'r','-').vbox-extpack"
$url="${url}/$($vboxVersion -replace 'r.*','')/${vboxExtensionPack}"

Write-Output "Downloading $url"
Invoke-webRequest -Uri $url -OutFile (Join-Path $env:TEMP $vboxExtensionPack)

Write-Output "Installing Extension pack version ${vboxVersion}"
& $vboxManage extpack install --replace (Join-Path $env:TEMP $vboxExtensionPack) 2>&1
