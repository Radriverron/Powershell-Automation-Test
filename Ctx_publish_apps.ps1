$PSCommandPath # path of the script
$PSScriptRoot # directory of the script

# Purpose: Deploy Applications on a delivery group
# Author: Saby Sengupta
# date: 11 Jan 2021
# Version 1.0
# Disclaimer: 
#	while the script has been written with every intention of minimising the potential for unintended consequences
#	please be aware to run this scripts at your own risk

# load Citrix snapin
asnp citrix*

# get Citrix deivery controller name
Param
(
    [Parameter(HelpMessage = "What is the hostname/fqdn of the Delivery controller?")]
    [string] $ddc
)

# create a log file
$logfile = "$PSScriptRoot\$((split-path $PSCommandPath -Leaf) -replace ('.ps1', '.log'))"

# create a log function. Replace Write-host calls with Log
Function LogWrite
{
   Param ([string]$logstr)
   Add-content $Logfile -value $logstr
   Write-Host $logstr
}

# start logging
LogWrite "Log starts on:  $(Get-Date -Format "dddd dd/MM/yyyy HH:mm")`n"

# read a file with the application path list and store it in an array
$applist = Get-Content -Path $PSScriptRoot\<insert filename with list of apps>.txt

# loop through the contents and get the application name then store those in a new array
$trimray = @()
$applist.foreach({
    $trimray += (Split-Path $_ -Leaf).TrimEnd(".exe") 
    
}) 
LogWrite "Array of application names $trimray`n"

# get the working directory for each app
$workdir = @()
$applist.foreach({
    $workdir += (Split-Path $_)
})
LogWrite "Working directory of each app $workdir`n"

# get the iconUID
$iconray = @()
$applist.foreach({
    $iconray += ((Get-BrokerIcon -ServerName "$ddc" -FileName "$_" -index 0 | New-BrokerIcon | Select-Object Uid).uid)
})
LogWrite "Array of iconUIDs $iconray`n"

# create the applications. The desktopGroupUid and AdminfolderUid can be predetermined or can be queried before this step.
$count = 0
while ($count -lt $applist.Length) {
    $nn = $trimray[$count]
    $ce = $applist[$count]
    $ice = $iconray[$count]
    $wdd = $workdir[$count]
    $dd = New-BrokerApplication -Name "$nn" -CommandLineExecutable "$ce" `
    -DesktopGroup 1 -AdminFolder 1 -ApplicationType HostedOnDesktop -MaxPerUserInstances 1 -Description "KEYWORDS: PROD" `
    -ClientFolder "PROD" -WaitForPrinterCreation $False -Priority 0 -WorkingDirectory "$wdd" `
    -IconUid $ice
    LogWrite $dd
    $count++
}

# end logging
LogWrite "`nLog ends on:  $(Get-Date -Format "dddd dd/MM/yyyy HH:mm")"


