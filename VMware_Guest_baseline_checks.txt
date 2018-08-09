
<# Title : Verify VM CIS benchmark attributes #>

<# Create a read-only user (vm_rouser here) and generate the clixml file. Please the file in the same dir in which this script is placed.
   This script can then be scheduled via a batch job in task scheduler to generate reports daily.
   In the same dir create a file vclist.txt and populate it with a list of vcenters
   #>

<# Import the module #>
Import-Module vmware.vimautomation.core

$key = (2,3,56,34,254,222,1,1,2,23,42,54,33,233,1,34,2,7,6,5,35,43,6,6,6,6,6,6,31,33,60,23)
$secpass = Import-Clixml vm_rouser.clixml
$pw = $secpass | ConvertTo-SecureString -key $key
$usr = "vm_rouser@abc.com"
$cred = New-Object System.Management.Automation.PSCredential $usr,$pw

Function vc-connect ($vcenter) {
  Connect-Viserver $vcenter -Credential $cred
}

Function get-par ($par) {
  Get-AdvancedSetting -Entity $vm -Name $par | Select Value
}

Function logit ($sec,$msg) {
  write-output "$vc,$vm,$vmos,$sec,$msg" | Out-File $csvfile -Append
}

Function check-true ($sec,$par) {
  $val=Get-AdvancedSetting -Entity $vm -Name $par | Select Value
  if ($val.value -ne "true" -Or ([string]::IsNullOrWhiteSpace($val.value))) {
    write-output "$vc,$vm,$vmos,$sec,set $par to true" | Out-File $csvfile -Append
  }
}

Function check-false ($sec,$par) {
  $val=Get-AdvancedSetting -Entity $vm -Name $par | Select Value
  if ($val.value -ne "false" -Or ([string]::IsNullOrWhiteSpace($val.value))) {
    write-output "$vc,$vm,$vmos,$sec,Set $par to false" | Out-File $csvfile -Append
  }
}

Function Get-ParallelPort { 
    Param ( 
        [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)] 
        $VM 
    ) 
    Process { 
        Foreach ($VMachine in $VM) { 
            Foreach ($Device in $VMachine.ExtensionData.Config.Hardware.Device) { 
                If ($Device.gettype().Name -eq "VirtualParallelPort"){ 
                    $Details = New-Object PsObject 
                    $Details | Add-Member Noteproperty VM -Value $VMachine 
                    $Details | Add-Member Noteproperty Name -Value $Device.DeviceInfo.Label 
                    If ($Device.Backing.FileName) { $Details | Add-Member Noteproperty Filename -Value $Device.Backing.FileName } 
                    If ($Device.Backing.Datastore) { $Details | Add-Member Noteproperty Datastore -Value $Device.Backing.Datastore } 
                    If ($Device.Backing.DeviceName) { $Details | Add-Member Noteproperty DeviceName -Value $Device.Backing.DeviceName } 
                    $Details | Add-Member Noteproperty Connected -Value $Device.Connectable.Connected 
                    $Details | Add-Member Noteproperty StartConnected -Value $Device.Connectable.StartConnected 
                    $Details 
                } 
            } 
        } 
    } 
}

Function Get-SerialPort { 
    Param ( 
        [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)] 
        $VM 
    ) 
    Process { 
        Foreach ($VMachine in $VM) { 
            Foreach ($Device in $VMachine.ExtensionData.Config.Hardware.Device) { 
                If ($Device.gettype().Name -eq "VirtualSerialPort"){ 
                    $Details = New-Object PsObject 
                    $Details | Add-Member Noteproperty VM -Value $VMachine 
                    $Details | Add-Member Noteproperty Name -Value $Device.DeviceInfo.Label 
                    If ($Device.Backing.FileName) { $Details | Add-Member Noteproperty Filename -Value $Device.Backing.FileName } 
                    If ($Device.Backing.Datastore) { $Details | Add-Member Noteproperty Datastore -Value $Device.Backing.Datastore } 
                    If ($Device.Backing.DeviceName) { $Details | Add-Member Noteproperty DeviceName -Value $Device.Backing.DeviceName } 
                    $Details | Add-Member Noteproperty Connected -Value $Device.Connectable.Connected 
                    $Details | Add-Member Noteproperty StartConnected -Value $Device.Connectable.StartConnected 
                    $Details 
                } 
            } 
        } 
    } 
}

$csvfile = "DVM_baseline_validation.csv"
$vclist = Get-Content "vclist.txt"

<# clear the output csvfile for a fresh run #>
if (Test-Path $csvfile)
{
  clear-content $csvfile
} else {
  New-Item $csvfile -ItemType File
}


<# Now iterate over the VC and the VMs in it to generate the deviations report #>
foreach($vc in $vclist)
{	
  vc-connect $vc
  $vms = Get-VM
  foreach($vm in $vms)
  {
    $getos = Get-VM $vm | Get-View
    $vmos = $getos.summary.config.guestfullname

<#8.1.1 Limit informational messages from the VM to the VMX file #>
    $val=get-par "tools.setInfo.sizeLimit"
    if ($val.value -ne "1048576") {
      logit 8.1.1 "tools.setInfo.sizeLimit is not set to 1048576"
    }

<#8.1.2 Limit sharing of console connections#>
    $val=get-par "RemoteDisplay.maxConnections"
    if ($val.value -ne "1") {
      logit 8.1.2 "RemoteDisplay.maxConnections is not set to 1"
    }

<#8.2.1 Disconnect unauthorized devices - Floppy Devices#>
    $flp = Get-FloppyDrive -vm $vm | Select Parent, Name, ConnectionState 
    if($flp) {
      logit 8.2.1 "Floppy drive enabled.Disable it"
    }

<#EXCLUDED 8.2.2 Disconnect unauthorized devices - CD/DVD Devices#>

<#8.2.3 Disconnect unauthorized devices - Parallel Devices#>
    $prl = $vm | Get-ParallelPort
    if($prl) {
      logit 8.2.3 "Parallel port device enabled.Disable it"
    }

<#8.2.4 Disconnect unauthorized devices - Serial Devices#>
    $srl = $vm | Get-SerialPort
    if($srl) {
      logit 8.2.4 "Serial device enabled.Disable it"
    }

<#8.2.5 Disconnect unauthorized devices - USB Devices#>
    $usb = $vm | Get-SerialPort
    if($usb) {
      logit 8.2.5 "USB device enabled.Disable it"
    }

<#8.2.6 Prevent unauthorized removal and modification of devices#>
    check-true 8.2.6 "isolation.device.edit.disable"

<#8.2.7 Prevent unauthorized connection of device#>
    check-true 8.2.7 "isolation.device.connectable.disable"

<#8.3.1 Disable unnecessary or superfluous functions inside VMs (Unused services by ITS Windows Support/ ITS Unix Support and virtual devices by VMware Admins)#>
<#8.3.2 Minimize use of the VM console Not Scored) Remote console already set to 1#>
<#8.3.3 Use secure protocols for virtual serial port access | Can't determine with script #>
<#8.3.4 Use templates to deploy VMs whenever possible | Can't determine with script #>

<#8.4.5 Disable Autologon#>
    check-true 8.4.5 "isolation.tools.ghi.autologon.disable"

<#8.4.6 Disable BIOS BBS#>
    check-true 8.4.6 "isolation.bios.bbs.disable"

<#8.4.7 Disable Guest Host Interaction Protocol Handler#>
    check-true 8.4.7 "isolation.tools.ghi.protocolhandler.info.disable"

<#8.4.8 Disable Unity Taskbar#>
    check-true 8.4.8 "isolation.tools.unity.taskbar.disable"

<#8.4.9 Disable Unity Active#>
    check-true 8.4.9 "isolation.tools.unityActive.disable"

<#8.4.10 Disable Unity Window Contents#>
    check-true 8.4.10 "isolation.tools.unity.windowContents.disable"

<#8.4.11 Disable Unity Push Update#>
    check-true 8.4.11 "isolation.tools.unity.push.update.disable"

<#8.4.12 Disable Drag and Drop Version Get#>
    check-true 8.4.12 "isolation.tools.vmxDnDVersionGet.disable"

<#8.4.13 Disable Drag and Drop Version Set#>
    check-true 8.4.13 "isolation.tools.guestDnDVersionSet.disable"

<#8.4.14 Disable Shell Action#>
    check-true 8.4.14 "isolation.ghi.host.shellAction.disable"

<#8.4.15 Disable Request Disk Topology#>
    check-true 8.4.15 "isolation.tools.dispTopoRequest.disable"

<#8.4.16 Disable Trash Folder State#>
    check-true 8.4.16 "isolation.tools.trashFolderState.disable"

<#8.4.17 Disable Guest Host Interaction Tray Icon#>
    check-true 8.4.17 "isolation.tools.ghi.trayicon.disable"

<#8.4.18 Disable Unity#>
    check-true 8.4.18 "isolation.tools.unity.disable"

<#8.4.19 Disable Unity Interlock#>
    check-true 8.4.19 "isolation.tools.unityInterlockOperation.disable"

<#8.4.20 Disable GetCreds#>
    check-true 8.4.20 "isolation.tools.getCreds.disable"

<#8.4.21 Disable Host Guest File System Server#>
    check-true 8.4.21 "isolation.tools.hgfsServerSet.disable"

<#8.4.22 Disable Guest Host Interaction Launch Menu#>
    check-true 8.4.22 "isolation.tools.ghi.launchmenu.change"

<#8.4.23 Disable memSchedFakeSampleStats#>
    check-true 8.4.23 "isolation.tools.memSchedFakeSampleStats.disable"

<#8.4.24 Disable VM Console Copy operations#>
    check-true 8.4.24 "isolation.tools.copy.disable"

<#8.4.25 Disable VM Console Drag and Drop operations#>
    check-true 8.4.25 "isolation.tools.dnd.disable"

<#8.4.26 Disable VM Console GUI Options#>
    check-false 8.4.26 "isolation.tools.setGUIOptions.enable"

<#8.4.27 Disable VM Console Paste operations#>
    check-true 8.4.27 "isolation.tools.paste.disable"

<#8.4.28 Control access to VM console via VNC protocol#>
    check-false 8.4.28 "RemoteDisplay.vnc.enabled"

<#8.4.29 EXCLUDED - Disable all but VGA mode on virtual machines#>

<#1.1.2 Disable virtual disk shrinking#>
    check-true 1.1.2 "isolation.tools.diskShrink.disable"

<#1.1.3 Disable virtual disk wiping#>
    check-true 1.1.3 "isolation.tools.diskWiper.disable"

<#1.1.4 Disable VIX messages from the VM#>
    check-true 1.1.4 "isolation.tools.vixMessage.disable"

<#1.1.5 Limit number of VM log files#>
    $val=Get-AdvancedSetting -Entity $vm -Name "log.keepOld" | Select Value
    if ($val.value -ne "10") {
      logit 1.1.5 "log.keepOld is not set to 10"
    }

<#1.1.6 Do not send host information to guests#>
    check-false 1.1.6 "tools.guestlib.enableHostInfo"

  }
  Disconnect-VIServer -Confirm:$false
}




