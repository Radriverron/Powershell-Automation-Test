<#
# VMDeployer.ps1 - The Script can be used to deploy multiple Windows VMs from a csv file.
# Author: Saby Sengupta
# Version: Initial Working
#
CSV Field Definitions.
	Name - Name of new VM
	Template - Name of existing template to clone
    	OSCustSpec - Name of existing OS Customiation Spec to use
    	vmHost - Name of the ESXi Host
	Datastore - Datastore placement - Can be a datastore or datastore cluster
	IPAddress - IP Address for NIC
	SubnetMask - Subnet Mask for NIC
	Gateway - Gateway for NIC
	pDNS - Primary DNS (Windows Only)
        sDNS - Secondary DNS (Windows Only)
# Header of csv: Name,Template,OSCustSpec,vmHost,Datastore,IPAddress,SubnetMask,Gateway,pDNS,sDNS
# If you supply a csv file location it is recommended to use the name as vms2deploy.csv
# Script execution command: .\VMDeployer.ps1 -vcenter <ip or name of Vcenter server>
# Thanks: Hector Tobar Martinez (hector.martineztobar@cerner.com) for his contribution with Powercli module cmdlets
#>

Param
(
    [Parameter(HelpMessage = "What is the hostname/fqdn of the vCenter Server?")]
    [string] $vcenter
)

# User Defined Variables
$date = Get-Date
$scriptName = "VMDeployer.ps1"
$scriptDir = "$PSscriptroot"
$csvfile = "$scriptDir\vms2deploy.csv"
$logdir = $scriptDir + "\Logs\"
$logfile = "$logdir\$scriptName" + "_" + "log.txt"

# Function for Error Logging
Function Out-Log {
    [cmdletbinding()]
    Param
    (
        [Parameter(Mandatory)]
        [string]$LineValue
    )
    Add-Content -Path $logfile -Value $LineValue
    Write-Host $LineValue
}
# Function to Open file dialogue box to locate the $csvfile
Function FileBrowser {
    Add-Type -AssemblyName System.Windows.Forms
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath('Desktop') }
    $FileBrowser.MultiSelect = $false
    $null = $FileBrowser.ShowDialog()
    return $FileBrowser.FileName
}

# Check the Log directory path. Create if it doesn't exist
If (!(Test-Path $logDir)) { 
    New-Item -ItemType directory -Path $logDir | Out-Null
}

# Write the Log file header
Out-Log "ScriptName: $scriptName | Start Time: $Date >>>>>>>>>>>>`n`n"
Out-Log "Path to csv file is >>>> $csvfile`n"


# Import VMware.Powercli module
$vmmodule = Get-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
$Error.Clear()
if ( $vmmodule -eq $null) {
    Import-Module VMware.VimAutomation.Core
    if ($error.Count -eq 0) {
        Out-Log "vmware module was successfully enabled."
    }
    else {
        Write-Host "ERROR: Check log" -ForegroundColor Yellow
        Out-Log "`n$Error importing VMware module.Exiting the script now"
        Exit
    }
}
else {
    Out-Log "Vmware module has alreday been enabled. Moving on.."
}

# Start Logging

# Test to ensure csv file is available, else browse to the file
If ($csvfile -eq "" -or !(Test-Path $csvfile)) {
    Out-Log "Path to vms2deploy.csv not specified...browse to the csv file`n"
    $csvfile = FileBrowser
}
If ($csvfile -eq "") { # Removing requirement on the name of csv file
    Out-Log "`nNo csv file specified. Exiting ...`n"
    Exit
}

# Connect to vCenter server. Log error
$Error.clear()
If ($vcenter -eq "") { 
    $vcenter = Read-Host "`nEnter vCenter server FQDN or IP" 
}
Try {
    Write-Host "Attempting to connect to $vcenter" -ForegroundColor Cyan
    Connect-VIServer $vcenter -ErrorAction Stop | Out-Null
}
Catch {
    Out-Log "`r`nUnable to connect to $vcenter.$error. `nExiting !`n"
    Exit
}
Out-Log "Connected to Vcenter >> $vcenter"

# Import variables from the csv
$newVMs = Import-Csv -Path $csvfile

# Do the below tasks for each VM
Foreach ($VM in $newVMs) {
    $Error.Clear()
    $vmName = $VM.Name
    # Create New OS Custumization spec from the OSCustSpec field in the csv.
    # This new Specification will be deleted in the end to free up space
    $spec = Get-OSCustomizationSpec -Name $VM.OSCustSpec | New-OSCustomizationSpec -Name $vmName
    $tempspec = Get-OscustomizationNicMapping -OSCustomizationSpec $spec
    Set-OSCustomizationNicMapping -OSCustomizationNicMapping $tempspec -Position 1 -IpMode UseStaticIp -IpAddress $VM.IPAddress -SubnetMask $VM.SubnetMask `
    -DefaultGateway $VM.Gateway -Dns $VM.pDNS, $VM.sDNS -Confirm:$false

    Start-Sleep -Seconds 5

    # Create new VMs
    $Error.clear()
    try
    {
        Out-Log "Deploying $vmName"
        $task = New-VM -Name $VM.Name -VMHost $VM.vmHost -Datastore $VM.Datastore -Template $VM.Template -OSCustomizationSpec $spec -ErrorAction Stop
    }
    catch
    {
        Out-Log "`r`nUnable to deploy $vmName`n $task`n $error`n Exiting !`n"
        Exit
    }

    Start-Sleep -Seconds 10
    Write-Output $task

    Out-Log "`n`nBootup and Configuration to Progress..`n"

    #Boot VM
    Out-Log "Booting $vmName"
    Start-VM -VM $vmName -Confirm:$false
    Wait-Tools -VM $vmName -TimeoutSeconds 240
    Start-Sleep -Seconds 5
    $PowerState = (Get-VM -Name $vmName).powerstate
    Out-Log "$vmName is $PowerState"

    #Enable network only if $PowerState = PoweredOn
    if ($PowerState -match "PoweredOn")
    {
        Write-Host "Getting VMware Tools Status for $vmName" -ForegroundColor Cyan
        $toolstate = (Get-VM -Name $vmName).Guest.ExtensionData.ToolsStatus
        Out-Log "The VM:$vmName has VMware tools status of $toolstate"
        $toolsversion = (Get-VM -Name $vmName).Guest.ToolsVersion
        Out-Log "The VM:$vmName is deployed and has VMware tools version of $toolsversion`n"
        Start-Sleep -Seconds 5

        # Enable Network for Booted VMs
        Write-Host "Enabling network adapter for $vmName"
        Get-VM $vmName | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$true -Confirm:$false
        Start-Sleep -Seconds 10
    }
    else
    {
        Write-Host "Something could be wrong with Vmware tools" -ForegroundColor Yellow
        Out-Log "`r`nUnable to enable network $vmName. because VM is $PowerState. `nExiting !`n"
        Remove-OSCustomizationSpec -OSCustomizationSpec $vmName -Confirm:$false
        Exit
    }

    # Remove temp OS Custumization spec to cleanup
    Remove-OSCustomizationSpec -OSCustomizationSpec $vmName -Confirm:$false
    Start-Sleep -Seconds 4

}

# Close Connections
Write-Host "Done !. Check the Log for more info" -ForegroundColor Cyan
Out-Log "All VMs Deployed..Disconnecting from Vcenter and Exiting"
Disconnect-VIServer -Server $vcenter -Force -Confirm:$false
Write-Host "Disconnected from $vcenter" -ForegroundColor Cyan

# End Logging
$date = Get-Date
Out-Log "`nScriptName: $scriptName | Finish Time: $date"
exit
