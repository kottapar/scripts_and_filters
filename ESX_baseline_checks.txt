
<#
Title : Verify Vcenter CIS benchmark attributes
#>

<# Create a read-only user (vm_rouser here) and generate the clixml file. Please the file in the same dir in which this script is placed.
   This script can then be scheduled via a batch job in task scheduler to generate reports daily.
   In the same dir create a file vclist.txt and populate it with a list of vcenters
   #>
   
<# CHANGELOG
28-03-2018-Ravi-Removed distributed switch checks

#>

<# Import the module #>
Import-Module vmware.vimautomation.core

cd D:\ESX_validation

<# decrypt the password key for the user #>
$key = (2,3,56,34,254,222,1,1,2,23,42,54,33,233,1,34,2,7,6,5,35,43,6,6,6,6,6,6,31,33,60,23)
$secpass = Import-Clixml vm_rouser.clixml
$pw = $secpass | ConvertTo-SecureString -key $key
$usr = "vm_rouser@rakbank.co.ae"
$cred = New-Object System.Management.Automation.PSCredential $usr,$pw

Function vc-connect ($vcenter) {
  Connect-Viserver $vcenter -Credential $cred
}

Function get-par ($par) {
  Get-AdvancedSetting -Entity $vm -Name $par | Select Value
}

Function logit ($msg) {
  write-output "$vc,$vhname,$msg" | Out-File $csvfile -Append
}


$csvfile = "ESX_baseline_validation.csv"
$vclist = Get-Content "vclist.txt"

<# clear the output csvfile for a fresh run #>
if (Test-Path $csvfile)
{
  clear-content $csvfile
} else {
  New-Item $csvfile -ItemType File
}

<# Connect to the VC and generate the deviation report #>
foreach($vc in $vclist)
{
  vc-connect $vc
  $vhs = Get-VMHost
  foreach($vh in Get-VMHost)
    {
      $vhname = $vh.Name
 
      $ntptmp = Get-VMHostNtpServer -VMHost $vh
      if ($ntptmp -notcontains "10.17.10.11" -or $ntptmp -notcontains "10.16.10.11") {
        logit "NTP servers is not equal to 10.17.10.11 10.16.10.11"
      }
    
      $dvfilter = Get-VMHost -Name $vh | Get-AdvancedSetting Net.DVFilterBindIpAddress | Select -ExpandProperty value
      if ($dvfilter) {
        logit "dvfilter ip address found.Remove unless it is a security appliance ip"  
      }

      $perslog = Get-VMHost -Name $vh | Get-AdvancedSetting Syslog.global.logDir | Select -ExpandProperty value
      if (! $perslog) {
        logit "No persistent logging found"
      }


      $remlog = Get-VMHost -Name $vh | Get-AdvancedSetting Syslog.global.logHost | Select -ExpandProperty value
      if ($remlog -ne "10.17.8.55:514,10.16.8.37:514" -and $remlog -ne "10.16.8.37:514,10.17.8.55:514") {
        logit "No remote logging specified"
      }
        
      $dom_tmp = Get-VMHost  -Name $vh | Get-VMHostAuthentication
      $dom_mem = $dom_tmp.DomainMembershipStatus
      if (! $dom_mem) {
        logit "No Domain membership status"
      }    
   
      $dom = $dom_tmp.Domain
      if (! $dom) {
        logit "No Domain defined"
      }
        
      $esxishell = Get-VMHost -Name $vh |  Get-VMHostService | Where { $_.key -eq "TSM" }
      $shellval = $esxishell.running
      if ($shellval -notmatch "false") {
        logit "ESXi shell is running.Stop and disable it"
      }
        
      $remacc = Get-VMHost -Name $vh | Select @{N="Lockdown";E={$_.Extensiondata.Config.lockdownmode}}
      if ($remacc.lockdown -notmatch "lockdownDisabled") {
        logit "Remote access not in lockdowndisabled"
      }    
    
      $idletmout = Get-VMHost -Name $vh | Get-AdvancedSetting UserVars.ESXiShellInteractiveTimeOut | Select -ExpandProperty value
      if ($idletmout -notmatch "300") {
        logit "ESXi shell idle timeout is not set to 300"
      }
     
      $shelltmout = Get-VMHost -Name $vh | Get-AdvancedSetting UserVars.ESXiShellTimeOut | Select -ExpandProperty value
      if ($shelltmout -notmatch "3600") {
        logit "ESXi shell timeout is not set to 3600"
      }
        
      $dcui = Get-VMHost -Name $vh | Get-AdvancedSetting -Name DCUI.Access | select -Expandproperty value
      if ($dcui -notmatch "root") {
        logit "DCUI access is not set to root"
      }

<# Fetch the details for the standard switches#>
      foreach ($vsw in Get-VirtualSwitch -Standard $vh|Select-String 'usb' -NotMatch) {
        $swmac = Get-VirtualSwitch -Standard -VMHost $vh -Name $vsw|Select @{N="Macchanges";E={$_.ExtensionData.Spec.Policy.Security.MacChanges}}
        $swfrg = Get-VirtualSwitch -Standard -VMHost $vh -Name $vsw|Select @{N="ForgedTransmits";E={$_.ExtensionData.Spec.Policy.Security.ForgedTransmits}}
        $swprm = Get-VirtualSwitch -Standard -VMHost $vh -Name $vsw|Select @{N="allowpromiscuous";E={$_.ExtensionData.Spec.Policy.Security.allowpromiscuous}}
        if ($swmac.macchanges -notmatch "False") {
          logit "$vsw macchanges not set to reject" 
        }
        if ($swfrg.ForgedTransmits -notmatch "False") {
          logit "$vsw ForgedTransmits not set to reject" 
        }
        if ($swprm.allowpromiscuous -notmatch "False") {
          logit "$vsw allowpromiscuous not set to reject" 
        }
      }

    }
  Disconnect-VIServer $vc -Confirm:$false
}










