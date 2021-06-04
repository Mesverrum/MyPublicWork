#region Top of Script

<#
.SYNOPSIS
  Exports all application templates for backup, deletes unused templates
.DESCRIPTION
  Exports all application templates for backup, deletes unused templates.
  Includes an example of the syntax for imports.
.INPUTS
  None
.OUTPUTS
  Log file stored in same directory as script runs from, if script isn't run from a file then saves to user desktop.
  TemplateExports directory is created in the same path and filled with the exported data.
.NOTES
  Version:        1.0
  Author:         Marc Netterfield
  Creation Date:  2020/12/14
  Purpose/Change: Initial script development
#>

#endregion Top of Script
#####-----------------------------------------------------------------------------------------#####
#region Parameters

Param(
    [ Parameter( Mandatory = $false ) ] [ ValidateNotNullOrEmpty() ] [ String ] $Example = "Example"
)

#endregion Parameters
#####-----------------------------------------------------------------------------------------#####
#region Functions 

#region Set-SwisConnection
Function Set-SwisConnection {
    Param(
        [ Parameter( Mandatory = $true, HelpMessage = "What SolarWinds server are you connecting to (Hostname or IP)?" ) ] [ string ] $SolarWindsServer,
        [ Parameter( Mandatory = $true, HelpMessage = "Do you want to use the credentials from PowerShell (Trusted), or a new login (Explicit)?" ) ] [ ValidateSet( 'Trusted', 'Explicit' ) ] [ string ] $ConnectionType
    )
    # Connect to SWIS

    IF ( $ConnectionType -eq 'Trusted'  ) {
        $swis = Connect-Swis -Trusted -Hostname $SolarWindsServer
    } ELSE {
        $creds = Get-Credential -Message "Please provide a Domain or Local Login for SolarWinds"
        $swis = Connect-Swis -Credential $creds -Hostname $SolarWindsServer
    }

    RETURN $swis
}
#endregion Set-SwisConnection

#endregion Functions 
#####-----------------------------------------------------------------------------------------#####
#region Logging

clear-host
$logTime = Get-Date -Format "yyyyMMdd_HHmm"
$script = ($MyInvocation.MyCommand)
if($script.Path){ $dir = (Split-Path $script.path) + "\logs" }
else { $dir = ([Environment]::GetFolderPath("Desktop")) + "\logs" }
if((test-path $dir) -eq $false) { mkdir -path $dir }
$Logfile = "$dir\$($script.name)_$logTime.log"
$removed = (get-ChildItem -Path "$dir").where{ $_.name -like "*.log" -and $_.LastWriteTime -lt (Get-Date).AddDays(-31) } 
$removed | Remove-Item
if( $removed ) {
    "Removed the following files:"
    $removed.name
}

Start-Transcript -Path $Logfile -Append -IncludeInvocationHeader

# Start the timer
$stopWatch = [ System.Diagnostics.Stopwatch ]::StartNew()
Write-Host "The stopwatch has started" -ForegroundColor Yellow

# Used to verify how code is being called, helpful debugging scripts and deciding if we can prompt the user for info, nesting it inside a function breaks the intended purpose
if( !$env:sessionname ) { 
    if( "${IP}" -eq "" ) { $scriptMode = 'TaskScheduler' } 
    else { $scriptMode = 'SAM Script' }
} else { 
    if( !$MyInvocation.MyCommand.Name ) { $scriptMode = "Ad Hoc code" } 
    else { $scriptMode = "Full execution from $host.Name" }
}
"Mode -> $scriptMode "

#endregion Logging
#####-----------------------------------------------------------------------------------------#####
#region Connections

$hostname = "wpec5009swpol01" #Read-Host -Prompt "Hostname or IP Address of your SolarWinds server"
$swis = Set-SwisConnection -SolarWindsServer $hostname -ConnectionType trusted

#endregion Connections
#####-----------------------------------------------------------------------------------------#####  
#region Execution

"Finding templates to export"
$templates = get-swisdata $swis @"
select at.name as template, at.ApplicationTemplateID, a.name, count(*) as instances
from orion.apm.ApplicationTemplate at
left join orion.apm.Application a on a.ApplicationTemplateID=at.ApplicationTemplateID
group by at.name, a.name, at.ApplicationTemplateID
"@

$TempPath = "$dir\TemplateExports\"
if((test-path $TempPath) -eq $false) {$null = mkdir -path $TempPath}

foreach( $template in $templates ) {
    $templateXML = invoke-swisverb $swis "orion.apm.applicationtemplate" "ExportTemplate" $template.applicationtemplateid
    $namecleanup = "$($template.template)"
    $namecleanup = $namecleanup.Replace("\", " ").Replace("/", " ").replace("<"," ").replace(">"," ").replace(":"," ").replace("|"," ").replace("?", " ").replace("*"," ").replace("[","").replace("]","")

    " Exporting view $namecleanup.xml to $TempPath"
    
    $templateXML | Export-Clixml ($TempPath + "$namecleanup.xml")
}

<#
#import an alert back in
$templateXML = (import-clixml ($TempPath + "001_AV_Test_ParMed-SALES_App_Log_JobLogs_01.xml")).'#text'
invoke-swisverb $swis "orion.apm.applicationtemplate" "ImportTemplate" $templateXML
#>

$templatesToRemove = get-swisdata $swis @"
select at.name as template, at.ApplicationTemplateID, a.name, count(*) as instances
from orion.apm.ApplicationTemplate at
left join orion.apm.Application a on a.ApplicationTemplateID=at.ApplicationTemplateID
where a.name is null
and at.customapplicationtype is null
group by at.name, a.name, at.ApplicationTemplateID
order by at.name
"@

foreach( $template in $templatesToRemove ) {
    "Removing unused template - $($template.template)"
    invoke-swisverb $swis "orion.apm.applicationtemplate" "DeleteTemplate" $template.applicationtemplateid
}

#endregion Execution
#####-----------------------------------------------------------------------------------------#####
#region Cleanup

"`nCompleted"

$stopWatch.Stop()

Write-Host "Script duration: $( $stopWatch.Elapsed.Minutes ) min, $( $stopWatch.Elapsed.Seconds ) sec" -ForegroundColor Yellow

Stop-Transcript

#endregion Cleanup
