#region Functions 

Function New-OrionDiscovery {
    Param(
        [ Parameter( Mandatory = $true ) ] [ ValidateNotNullOrEmpty() ] [ String ] $discoveryName,
        [ Parameter( Mandatory = $true ) ] [ ValidateNotNullOrEmpty() ] $swis,
        [ Parameter( Mandatory = $true ) ] [ ValidateNotNullOrEmpty() ] [ int ] $engineID,
        [ Parameter( Mandatory = $true ) ] [ ValidateNotNullOrEmpty() ]  [string[] ] $nodes,
        [ Parameter( Mandatory = $false ) ] [ValidateSet('all','snmp','wmi')] $credTypesToTry = "all",
        [ Parameter( Mandatory = $false ) ] [ Boolean ] $disableIcmp = $false
    )

    # Testing Connection to Orion
    if ( !( $swistest = get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites" ) ) { 
        throw $error[0]
    }

    #Look up credentials
    switch ($CredTypesToTry) {
        "all" {
            $credType = "'SolarWinds.Orion.Core.Models.Credentials.SnmpCredentialsV2','SolarWinds.Orion.Core.Models.Credentials.SnmpCredentialsV3','SolarWinds.Orion.Core.SharedCredentials.Credentials.UsernamePasswordCredential'"
            break
        }
        "snmp" {
            $credType = "'SolarWinds.Orion.Core.Models.Credentials.SnmpCredentialsV2','SolarWinds.Orion.Core.Models.Credentials.SnmpCredentialsV3'"
            break
        }
        "wmi" {
            $credType = "'SolarWinds.Orion.Core.SharedCredentials.Credentials.UsernamePasswordCredential'"
            break
        }
    }
    
    $credquery = @"
SELECT id
FROM Orion.Credential
where credentialowner='Orion' 
and credentialtype in ( $credType )
"@

    $creds = Get-SwisData $swis $credquery
    $order = 1
    $credentials = "<Credentials>"
    foreach ($row in $creds) {
        $credentials += "<SharedCredentialInfo><CredentialID>$($row)</CredentialID><Order>$order</Order></SharedCredentialInfo>"
        $order ++
    }
    $credentials += "</Credentials>"

    # Built list of nodes
    $bulklist = "<BulkList>"
    foreach ($node in $nodes) {
        $bulklist += "<IpAddress><Address>$($node)</Address></IpAddress>"
    }
    $bulklist += "</BulkList>"
    
    $header = "<CorePluginConfigurationContext xmlns='http://schemas.solarwinds.com/2012/Orion/Core' xmlns:i='http://www.w3.org/2001/XMLSchema-instance'>"
    $footer = "<WmiRetriesCount>1</WmiRetriesCount><WmiRetryIntervalMiliseconds>1000</WmiRetryIntervalMiliseconds></CorePluginConfigurationContext>"

    $CorePluginConfigurationContext = ([xml]($header + $bulklist + $credentials + $footer)).DocumentElement
    $CorePluginConfiguration = Invoke-SwisVerb $swis Orion.Discovery CreateCorePluginConfiguration @($CorePluginConfigurationContext)

    $StartDiscoveryContext = ([xml]"
    <StartDiscoveryContext xmlns='http://schemas.solarwinds.com/2012/Orion/Core' xmlns:i='http://www.w3.org/2001/XMLSchema-instance'>
        <Name>$discoveryName</Name>
        <EngineId>$EngineID</EngineId>
        <JobTimeoutSeconds>36000</JobTimeoutSeconds>
        <SearchTimeoutMiliseconds>2000</SearchTimeoutMiliseconds>
        <SnmpTimeoutMiliseconds>2000</SnmpTimeoutMiliseconds>
        <SnmpRetries>1</SnmpRetries>
        <RepeatIntervalMiliseconds>1500</RepeatIntervalMiliseconds>
        <SnmpPort>161</SnmpPort>
        <HopCount>0</HopCount>
        <PreferredSnmpVersion>SNMP2c</PreferredSnmpVersion>
        <DisableIcmp>$($disableIcmp.ToString().ToLower())</DisableIcmp>
        <AllowDuplicateNodes>false</AllowDuplicateNodes>
        <IsAutoImport>false</IsAutoImport>
        <IsHidden>false</IsHidden>
        <PluginConfigurations>
            <PluginConfiguration>
                <PluginConfigurationItem>$($CorePluginConfiguration.InnerXml)</PluginConfigurationItem>
            </PluginConfiguration>
        </PluginConfigurations>
    </StartDiscoveryContext>
    ").DocumentElement


    $DiscoveryProfileID = (Invoke-SwisVerb $swis Orion.Discovery StartDiscovery @($StartDiscoveryContext)).InnerText

    RETURN $DiscoveryProfileID
}

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
    else { $scriptMode = "Full execution from $($host.Name)" }
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

$orionhostname = "YOURSERVERNAME"
$orionuser = "$env:userdomain\$env:username"
$swis = Connect-Swis $orionhostname -trusted

"Testing Connection to Orion"
if ( !( get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites" ) ) { 
    "Unable to connect to Orion server $orionhostname as $orionuser"
    Stop-Transcript
    exit 1
}

"Connected to $orionhostname successfully as $orionuser"

#endregion Connections
#####-----------------------------------------------------------------------------------------#####
#region Execution

# Get a list of hostnames/ip addresses, in this case I want to rediscover all my existing nodes to check for new volumes and interfaces so I'll take my list from Orion
# This would be easy to modify to pull a list from cmdb, or a csv, or a different database instead.
$nodesList = Get-SwisData $swis "select ip_address from orion.nodes n "

# I've seen a lot of Orion discoveries start failing when they get close to 1k nodes in them, so im breaking them into batches of <500 
$nodeSets = [System.Collections.Generic.List[System.Object]]::new()
for ($i = 0; $i -lt $nodesList.Count; $i += 500) {
    if (($nodesList.Count - $i) -gt 499  ) {
        $nodeSet = @{
            nodes = ($nodesList[$i..($i + 499)])
        }
        $nodeSets.add($nodeSet)
    }
    else {
        $nodeSet = @{
            nodes = ($nodesList[$i..($i + 499)])
        }
        $nodeSets.add($nodeSet)
    }
}

#get an engineid to use for the discovery jobs, you could split these up across multiple pollers if the environment is large
$engineID = get-swisdata $swis "select max(e.EngineID) as EngineID from orion.Engines e"

foreach( $set in $nodeSets ) {
    $discoveryName = "Auto Rediscovery - $(Get-Date -Format "yyyyMMdd_HHmm")"

    #create and start discovery job, ignore nodes that don't respond to SNMP/WMI as they don't matter for this use case
    $discoveryID = New-OrionDiscovery -discoveryName $discoveryName -swis $swis -engineID $engineID -nodes $set.nodes -disableIcmp $true

    Write-Host "Discovery profile #$discoveryID - $discoveryName running. These jobs can take a couple hours to complete."

    # Wait until the discovery completes
    do {
        Write-Host -NoNewline "."
        Start-Sleep -Seconds 60
        $Status = Get-SwisData $swis "SELECT Status FROM Orion.DiscoveryProfiles WHERE ProfileID = $discoveryID"
    } while ($Status -eq 1)

    # If $DeleteProfileAfterDiscoveryCompletes is true, then the profile will be gone at this point, but we can still get the result from Orion.DiscoveryLogs
    $result = Get-SwisData $swis "SELECT Result, ResultDescription, ErrorMessage, BatchID FROM Orion.DiscoveryLogs WHERE ProfileID = $discoveryID"

    $Result.ResultDescription
    $Result.ErrorMessage

    if ($Result.Result -ne 0) { # if discovery did not complete successfully
        "Discovery was not successful"
        Stop-Transcript
        exit 1
    }

    # Now that the discovery job is done we want to filter out interfaces and volumes and app templates that we don't want. 
    # You could do this as one big sql query or break it up, whatever seems manageable to you
    $cleanupQuery = @"
    -- I don't want discovery automatically adding appinsight templates
    DELETE FROM [SolarWindsOrion].[dbo].[APM_DiscoveredExchangeServers]
    DELETE FROM [SolarWindsOrion].[dbo].[APM_DiscoveredBlackBoxWstmInstances]
    DELETE FROM [SolarWindsOrion].[dbo].[APM_DiscoveredBlackBoxIISInstances]
    DELETE FROM [SolarWindsOrion].[dbo].[APM_DiscoveredBlackBoxSqlInstances]
  
    delete dv --cleaning up volumes
    --select *
    from solarwindsorion.dbo.DiscoveredVolumes dv
    join SolarWindsOrion.dbo.discoveredNodes dn on dn.nodeid=dv.DiscoveredNodeID and dn.ProfileID = dv.ProfileID
    where volumetype not in (4) --only want fixed disks
    or vendor not in ('Windows','Linux','net-snmp') --keep drives for servers, remove them for anything else
    
    delete from solarwindsorion.dbo.DiscoveredInterfaces --all interfaces rule
    where InterfaceTypeDescription in ('Loopback','VMware Virtual Network Interface','Proprietary Multiplexor') --we currently never monitor these types of interfaces and can delete them wherever they show up
    or OperStatus != 1 --we don't want to add new interfaces in any status beside up
    or interfacename like '%miniport%' -- these are useless sub interfaces that show up on windows snmp nodes
    or interfacename like '%-0000' -- these are useless sub interfaces that show up on windows snmp nodes

    delete di --special rule for Cisco interfaces
    --select *
    from DiscoveredInterfaces di
    join discoveredNodes dn on dn.nodeid=di.DiscoveredNodeID and dn.ProfileID = di.ProfileID
    where vendor = 'Cisco'
    and di.InterfaceAlias not like '%*%' -- for Cisco specifically I only want up interfaces with descriptions that follow my pattern
    
    delete di --special rule for Meraki interfaces
    --select *
    from DiscoveredInterfaces di
    join discoveredNodes dn on dn.nodeid=di.DiscoveredNodeID and dn.ProfileID = di.ProfileID
    where vendor = 'Meraki Networks, Inc.'
    and di.InterfaceTypeDescription != 'Ethernet' --for Meraki I only am looking for up ethernet ports, not lags or tunnels etc
    "@
    
    $sqlResult = ( Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' $cleanupQuery ).childnodes.documentelement.executesqlresults

    $importConfiguration = ([xml]"
    <DiscoveryImportConfiguration xmlns='http://schemas.solarwinds.com/2008/Core'>
        <DeleteProfileAfterImport>false</DeleteProfileAfterImport>
        <NodeIDs xmlns:a='http://schemas.microsoft.com/2003/10/Serialization/Arrays' />
        <ProfileID>$discoveryID</ProfileID>
    </DiscoveryImportConfiguration>
    ").DocumentElement
    $importResult = Invoke-SwisVerb $swis 'Orion.Discovery' 'ImportDiscoveryResults' $importConfiguration
}

#endregion Execution
#####-----------------------------------------------------------------------------------------#####
#region Cleanup

"Completed"

$stopWatch.Stop()
Write-Host "Script duration: $( $stopWatch.Elapsed.Minutes ) min, $( $stopWatch.Elapsed.Seconds ) sec" -ForegroundColor Yellow

Stop-Transcript

#endregion Cleanup
