# Running Variables - You may need to change these
$orionhostname = '1.2.3.4'
$sqlInstance = '1.2.3.5'
# how wide of a range of polling loads do we want to allow before nodes get moved?
$loadDelta = "10"

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
    if( !$MyInvocation.MyCommand.Name ) { $scriptMode = "Interactive - Ad hoc code" } 
    else { $scriptMode = "Interactive - Full execution from $($host.Name)" }
}
"Mode -> $scriptMode "

#endregion Logging
#####-----------------------------------------------------------------------------------------#####
#region Connections

# ignore SSL errors
if( !([System.Net.ServicePointManager]::CertificatePolicy -like "TrustAllCertsPolicy") ) {
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
    $AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

# Gather the necessary credentials from files
$tokenDir = ([Environment]::Getfolderpath("User")) + "\ScriptTokens"
if((test-path $tokenDir) -eq $false) { mkdir -path $tokenDir }

# Powershell Invoke-SqlCmd does not allow for specifying alternate accounts when using AD based logins to SQL, will pass through the cred of the current user
# Would be able to use specified SQL local accounts if desired
#$credTypes = ("OrionApi","SqlServer")

$credTypes = ("OrionApi")
foreach($credType in $credTypes) {
    $tokens = @( (Get-ChildItem -Path "$tokenDir/*" -filter "$($credType)_*").Name )
    # Check for existing token file, will only try to use the first file for each type
    if(($tokens[0].length) -eq 0) {
        if( $scriptMode -like "interactive*" ) {
            "Please provide a credential for $credType..."
            Start-Sleep -seconds 2
            $credential = get-credential
            $userCleanup = ($credential.UserName).replace('\','_')
            $credential.Password | ConvertFrom-SecureString | Set-Content -Path "$tokendir\$($credType)_$userCleanup"
        } else {
            "Missing credential file, run script interactively to create credential file"
        }
    } 
}

# populate credentials object
$creds = [pscustomobject]@{
    OrionApi = $null
    SqlServer = $null
}

foreach($credType in $credTypes) {
    $tokens = @( (Get-ChildItem -Path "$tokenDir/*" -filter "$($credType)_*").Name )
    # Check for existing token file
    if(($tokens[0].length) -ne 0) {
        # Found a matching credential file, will only use the first match per credType
        $tokenFile = "$tokenDir\$($tokens[0])"
        $credUser = [string]$tokens[0].replace("$($credType)_","").replace('_','\')
        
        [securestring]$tokenString = Get-Content $tokenFile | ConvertTo-SecureString 
        $cred = New-Object System.Management.Automation.PSCredential ($credUser, $tokenString)
        if( $credType -eq "OrionApi" ) { $creds.OrionApi = $cred }
        if( $credType -eq "SqlServer" ) { $creds.SqlServer = $cred }
    } 
}

# Only checking for the Orion creds since we use pass through AD creds for SQL
#if( $creds.OrionApi.GetType().Name -ne "PSCredential" -or $creds.SqlServer.GetType().Name -ne "PSCredential" ) {
# spot check that we have the necessary creds for Orion and SQL
if( $creds.OrionApi.GetType().Name -ne "PSCredential" ) {
    "Invalid Credential file, please review contents of $tokenDir"
    Stop-Transcript
    exit 1
}



# create a connection to the SolarWinds API
$swis = connect-swis -host $orionhostname -credential $($creds.OrionApi)
$swisTest =  get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites"

"Testing Connection to Orion"
if ( !$swisTest ) { 
    "Unable to connect to Orion server $orionhostname as $($creds.OrionApi.UserName)"
    Stop-Transcript
    exit 1
}

"Connected to $orionhostname successfully as $($creds.OrionApi.UserName)"

#endregion Connections
#####-----------------------------------------------------------------------------------------#####
#region Execution


$query = @"
select top 1 n.uri, n.caption, e.HighServer, e.HighEngine, e.HighUsage, count(n.uri) as [Elements], low.LowServer, low.LowEngine, low.LowUsage, (e.HighUsage-low.LowUsage) as LoadDelta
from orion.nodes n
join (select top 1 p.engine.Servername as HighServer, engineid as HighEngine,case when p.engine.servertype = 'Primary' then (isnull(p.currentusage,0) * 4) else isnull(p.currentusage,0) end as HighUsage from orion.PollingUsage p where scalefactor='orion.standard.polling' order by HighUsage desc) e on e.HighEngine=n.engineid
join (select 
n.uri
from orion.nodes n
union all 
(select i.node.uri
from orion.npm.Interfaces i)
union all 
(select v.node.uri
from orion.volumes v)) c on c.uri=n.uri
join (
select top 1 e.servername as LowServer, e.engineid as LowEngine, case when p.engine.servertype = 'Primary' then (isnull(p.currentusage,0) * 4) else isnull(p.currentusage,0) end as LowUsage 
from Orion.Engines e
left join orion.PollingUsage p on p.EngineID = e.EngineID and scalefactor='orion.standard.polling' 
order by LowUsage
) low on low.Lowengine != n.engineid
Where e.HighUsage-low.LowUsage > $loadDelta
and n.objectsubtype != 'Agent'
group by n.uri, n.caption, e.HighEngine, e.HighUsage, low.LowEngine, low.LowUsage, e.HighServer, low.LowServer
order by [Elements] desc
"@

# get highest engine and its largest node
$polling = Get-SwisData $swis $query 

# while the difference between those is more than the delta move nodes
While ( $polling.LoadDelta -gt $loadDelta ) {
    # move highnode to lowengine
    "Moving $($polling.Caption) from $($polling.HighServer) to $($polling.LowServer)"
    Set-SwisObject -SwisConnection $swis -Uri $polling.uri -properties @{EngineID = $polling.Lowengine}  
    # let time pass for polling loads to update
    Start-Sleep -s 15
    # update Polling
    $polling = Get-SwisData $swis $query
    }

"All engines are within $loadDelta % of each other, after adjusting for primary poller load"

$results = Get-SwisData $swis @"
select distinct e.HighEngine, e.HighEngineID, e.HighUsage, low.LowEngine, low.LowEngineID, low.LowUsage, (e.HighUsage-low.LowUsage) as LoadDelta
from orion.engines n
join (
select top 1 p.Engine.ServerName as HighEngine, engineid as HighEngineID,case when p.engine.servertype = 'Primary' then (isnull(p.currentusage,0) * 4) else isnull(p.currentusage,0) end as HighUsage from orion.PollingUsage p where scalefactor='orion.standard.polling' order by HighUsage desc
) e on e.HighEngineid=n.engineid
left join (
select top 1 e.servername as LowEngine, e.engineid as LowEngineID, case when p.engine.servertype = 'Primary' then (isnull(p.currentusage,0) * 4) else isnull(p.currentusage,0) end as LowUsage 
from Orion.Engines e
left join orion.PollingUsage p on p.EngineID = e.EngineID and scalefactor='orion.standard.polling' 
order by LowUsage
) low on low.LowEngineID != n.engineid
"@

$results

#endregion Execution
#####-----------------------------------------------------------------------------------------#####
#region Cleanup

"Completed"

$stopWatch.Stop()
Write-Host "Script duration: $( $stopWatch.Elapsed.Minutes ) min, $( $stopWatch.Elapsed.Seconds ) sec" -ForegroundColor Yellow

Stop-Transcript

#endregion Cleanup
