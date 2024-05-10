# Running Variables - You may need to change these
$csvPath = "E:\Scripts\something.csv"


$hostname1 = '1.2.3.4'
$hostname2 = '1.2.3.6'
$hostname3 = '1.2.3.7'

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
$orionHostnames = $($hostname1,$hostname2,$hostname3)
$swisHash = @{}
foreach( $orion in $orionHostnames ) {
    $swis = connect-swis -host $orion -credential $($creds.OrionApi)
    $swisTest =  get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites"

    "Testing Connection to Orion"
    if ( !$swisTest ) { 
        "Unable to connect to Orion server $orion as $($creds.OrionApi.UserName)"
        Stop-Transcript
        exit 1
    }

    "Connected to $orion successfully as $($creds.OrionApi.UserName)"
    $swisHash[$orion] = $swis
}

#endregion Connections
#####-----------------------------------------------------------------------------------------#####
#region Execution

# Get a list of interfaces with custom bandwidth to set
$csvNodes = $null
"Beginning work with $csvPath"

$csvNodes = import-csv $csvPath #| select -ExpandProperty "IP Address"
if ( !$csvNodes ) { 
    "Unable to find file at $csvPath"
    Stop-Transcript
    exit 1
}
#this code converts the arrays into an indexed hash tables for performance
"Building CSV hash table"
$csvHash = @{}
foreach( $item in $csvNodes ) {
    $identifier = "$($item.Hostname.replace('.corp.company.com','').replace('.ap.company.com','').replace('.corp.eu.company.com','')),$($item.Interface.replace('Interface ','').replace(' ',','))"
    $item | Add-Member -Name 'csvIdentifier' -Type NoteProperty -Value $identifier
    $csvHash[$identifier] = $item
}


$orionHash = @{}
foreach( $orion in $orionHostnames ) {
    "Querying $orion"
    # Get a list of hostnames and their current sitecode
    $nodesQuery = @"
    select n.Caption, ncp.SiteCode, ncp.Uri as NCPURI
    , i.ifname, i.InterfaceIndex, i.CustomBandwidth,i.InBandwidth, i.OutBandwidth,i.uri as IURI
    ,'$($orion)' as Orion

    from orion.nodes n
    join orion.NodesCustomProperties ncp on ncp.nodeid=n.nodeid
    join orion.npm.Interfaces i on i.nodeid=n.nodeid
"@
    $orionNodes = Get-SwisData $swisHash[$orion] $nodesQuery
    "Building $orion hash table"
    foreach( $item in $orionNodes ) {
        $identifier = "$($item.Caption.replace('.corp.company.com','').replace('.ap.company.com','').replace('.corp.eu.company.com','')),$($item.ifname),$($item.interfaceindex)"
        $item | Add-Member -Name 'orionIdentifier' -Type NoteProperty -Value $identifier
        $orionHash[$identifier] = $item
    }
}

$unmatched = [System.Collections.Generic.List[string]]::new()
#$test = "hostname,interface,ifindex"
#foreach( $csvNode in $csvHash[$test] ) {
foreach( $csvNode in $csvHash.Values ) {
    $orionMatch = $orionHash[$csvNode.csvIdentifier]
    if( $orionMatch ) {
        "Found Match in Orion: $($orionMatch.orionIdentifier)"

        $device = [pscustomobject]@{
            csvHostname = $csvNode.HostName.replace('corp.company.com','').replace('ap.company.com','').replace('corp.eu.company.com','')
            csvSiteName = $csvNode.'Site Name'
            csvInterface = $csvNode.Interface.split(' ')[1]
            csvSpeedBps = ([long]$csvNode.'Total speed'*1000000)
            csvIdentifier = $csvNode.csvIdentifier
            orionIdentifier = $orionMatch.orionIdentifier
            orionCaption = $orionMatch.Caption
            orionSiteCode = $orionMatch.SiteCode
            orionIfName = $orionMatch.ifname
            orionInterfaceIndex = [long]$orionMatch.InterfaceIndex
            orionCustomBandwidth = $orionMatch.CustomBandwidth
            orionInBps = [long]$orionMatch.InBandwidth
            orionOutBps = [long]$orionMatch.OutBandwidth
            orionInstance = $orionMatch.Orion
            orionIntUri = $orionMatch.IURI
        }

        $propsToChange = @{}
        if( $device.orionCustomBandwidth -ne "True" ) {
            "Enabling custom bandwidth in Orion"
            $propsToChange.CustomBandwidth = "True"
        }

        if( $device.csvSpeedBps -ne $device.orionInBps -or $device.csvSpeedBps -ne $device.orionOutBps  ) {
            "Setting custom bandwidth in Orion to $($device.csvSpeedBps) bps"
            $propsToChange.InBandwidth = $device.csvSpeedBps
            $propsToChange.OutBandwidth = $device.csvSpeedBps
        }

        if( $propsToChange.count -ne 0 ) {
            $result = Set-SwisObject -swis $swisHash[$device.orionInstance] -Uri $device.orionIntUri -Properties $propsToChange
        }

    } else {
        "No matching object monitored in Orion for $($csvNode.csvIdentifier)"
        $unmatched.Add($csvNode.csvIdentifier)
    }
}

if( $unmatched.Count -ne 0 ) {
    "The following interfaces could not be matched"
    $unmatched
}

#endregion Execution
#####-----------------------------------------------------------------------------------------#####
#region Cleanup

"Completed"

$stopWatch.Stop()
Write-Host "Script duration: $( $stopWatch.Elapsed.Minutes ) min, $( $stopWatch.Elapsed.Seconds ) sec" -ForegroundColor Yellow

Stop-Transcript

#endregion Cleanup
