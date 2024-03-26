#Requires -version 2
#Requires -Modules SwisPowerShell
#region Top of Script
<#
.SYNOPSIS
  Work around for an snmp bug in Meraki mx68 firmware where interface status indicators are incorrect
.DESCRIPTION
  Pulls the WAN interface status from Meraki REST API and sets the value inside Orion based on that instead of SNMP polling
  Meraki API Documentation here https://dashboard.meraki.com/api_docs/v0
  Solarwinds API Documentations here https://github.com/solarwinds/OrionSDK
.INPUTS
  None
.OUTPUTS
  Log file stored in _scriptouput directory
.NOTES
  Version:        1.0
  Author:         Marc Netterfield and Dave Shelton
  Creation Date:  2020/06/18
  Purpose/Change: Initial script development
#>
#endregion Top of Script
#####-----------------------------------------------------------------------------------------#####
#region Functions 

function callGETService {
    $base_url = "https://api.meraki.com/api/v1"
	$uri = $base_url + $args[0];
	Write-Host "Calling URI (GET): $uri"
	try {
		$response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
	} catch {
		$ret = [pscustomobject]@{
            "statuscode" = $_.Exception.Response.StatusCode.value__
			"statusmsg" = $_.Exception.Response.StatusDescription
		}
		$response = $ret | ConvertTo-Json
	}
	return $response
}

#endregion Functions 
#####-----------------------------------------------------------------------------------------#####
#region Logging
clear-host

$now = Get-Date -Format "yyyyMMdd_HHmm"
$script = $MyInvocation.MyCommand
if($script.path){ $dir = Split-Path $script.path }
else { $dir = [Environment]::GetFolderPath("Desktop") }
$Logfile = "$dir\$($script.name)_$now.log"

# Start the timer
$stopWatch = [ System.Diagnostics.Stopwatch ]::StartNew()
Write-Host "The stopwatch has started" -ForegroundColor Yellow

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

# Meraki
$apiKey = 'abc123'
$headers = @{
	"Content-Type" = "application/json"
	"Accept" = "application/json"
	"X-Cisco-Meraki-API-Key" = "$apiKey"
}

#Orion
$orionhostname = "myOrionServer"
$orionuser = "$env:userdomain\$env:username"
$swis = Connect-Swis $orionhostname -trusted

"Testing Connection to Orion"
if ( !( $swistest = get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites" ) ) { 
    "Unable to connect to Orion server $orionhostname as $($env:USERDOMAIN)\$($env:USERNAME)"
    Stop-Transcript
    exit 1
}

"Connected to $orionhostname successfully as $orionuser"

#endregion Connections
#####-----------------------------------------------------------------------------------------#####
#region Execution

"Getting list of devices from Meraki API"
$devicelist =  [System.Collections.generic.list[object]]@()

$organizations = callGETService '/organizations'
Foreach ($org in $organizations) {
    "Organization"
	$org
    $networks = callGETService "/organizations/$($org.id)/networks"
    Foreach ($net in $networks) {
        "Network"
	    $net
        $devices = callGETService "/networks/$($Net.id)/devices" 
        foreach( $dev in $devices ) {
            "Device"
            $dev
            
            $uplinks = callGETService "/networks/$($Net.id)/devices/$($dev.serial)/uplink"
            foreach( $up in $uplinks) {
                "Uplink"
                $up

            }

            <#
            This doesnt seem to be working for any of our gear, but the documentation is pretty sparse and its newish so maybe there is some kind of firmware update requirement on the devices, 
            it also generates the same errors when I try it through their web based API explorer so I don't think it's an issue in this code
            $ports = callGETService "/devices/$($dev.serial)/switchPorts" 
            foreach( $port in $ports) {
                "Switch Port"
                $port
            }
            #>

            $devProps = @{
                Name = $dev.name
                wan1Ip = $dev.wan1ip
                wan2Ip = $dev.wan2Ip
                url = $dev.url
                mac = $dev.mac
                serial = $dev.serial
                firmware = $dev.firmware
                model = $dev.model
                lat = $dev.lat
                lng = $dev.lng
                organization = $org.name
                network = $net.name
                timeZone = $net.timeZone
                tags = $net.tags
                uplinks = $uplinks
                #ports = $ports
            }

            $devicelist.add($devProps) 
        }
    }
}


foreach( $device in $devicelist ) {
    "Searching for matching Orion node for $($Device.name) ($($Device.mac))"
    
    $nodequery = @"
        select n.caption, n.nodeid, n.IP_Address, n.Uri
        , i1.caption as Wan1, i1.status as status1, i1.uri as uri1
        , i2.caption as Wan2, i2.status as status2, i2.uri as uri2
        , ns.SettingName, ns.SettingValue, ns.uri as weburi
        from orion.nodes n
        left join orion.npm.Interfaces i1 on i1.nodeid=n.nodeid and i1.caption = 'port1'
        left join orion.npm.Interfaces i2 on i2.nodeid=n.nodeid and i2.caption = 'port2'
        left join orion.NodeSettings ns on ns.NodeID=n.nodeid and ns.SettingName = 'Core.WebBrowseTemplate'
        where n.nodeid in
        (
            SELECT distinct
            n.nodeid
            FROM orion.nodes n
            left join Orion.NodeMACAddresses mac on mac.NodeID=n.NodeID
            where n.NodeDescription like '%mx%68%'
            and mac.mac = replace('$($device.mac)',':','')
        )
"@
    $node = get-swisdata $swis "select n.nodeid, n.caption from orion.nodes n where n.caption like '$($Device.name)%'" #$nodequery

    # if node is not found dont do anything
    if( !$node ) {
        "No matching Orion Node found for $($Device.name) $($device.mac)"
    } 
    
    # If Wan1 is missing, add it
    if( $node -and !$node.Wan1 ) {
        "Interface not found for Wan1, creating interface"


        $props = @{
            "NodeID" = "$($node.nodeid)"
            "ObjectSubType" = 'SNMP'
            "Name" = 'port1'
            "Index" = '1'
            "Icon" = '6.gif'
            "Type" = '6'
            "TypeName" = 'ethernetCsmacd'
            "TypeDescription" = 'Ethernet'
            "Speed" = '1000000000'
            "MTU" = '1500'
            "PhysicalAddress" = 'AC17C8000000'
            "AdminStatus" = '1'
            "OperStatus" = '1'
            "StatusIcon" = 'Up.gif'
            "InBandwidth" = '1000000000'
            "OutBandwidth" = '1000000000'
            "Caption" = 'port1'
            "FullName" = "$($node.caption) - port1"
            "Counter64" = 'Y'
            "Alias" = 'port1'
            "IfName" = ''
            "Severity" = '0'
            "CustomBandwidth" = 'False'
            "CustomPollerLastStatisticsPoll" = '1899-12-30 04:00:00'
            "PollInterval" = '120'
            "RediscoveryInterval" = '30'
            "StatCollection" = '7'
            "UnPluggable" = 'False'
            "InterfaceSubType" = '0'
            "AdminStatusLED" = 'Up.gif'
            "OperStatusLED" = 'Up.gif'
            "DuplexMode" = '0'
            "Status" = '1'
        }

        $result = new-swisobject $swis -entitytype 'orion.npm.interfaces' -properties $props
        $Interfaceid = $result.Substring(($result.indexof('InterfaceID=')+12))
        
        $pollertypes = @("I.StatisticsErrors32.SNMP.IfTable","I.StatisticsTraffic.SNMP.Universal","I.Status.SNMP.IfTable","I.Rediscovery.SNMP.IfTable" )
        foreach( $poller in $pollertypes ) {
            $pollerProps = @{
                "PollerType" = "$poller"
                "NetObject" = "I:$Interfaceid"
                "NetObjectType" = "I"
                "NetObjectID" = "$Interfaceid"
                "Enabled" = "True"
            }

            $pollerresult = new-swisobject $swis -EntityType 'Orion.Pollers' -Properties $pollerprops
        }

        $node = get-swisdata $swis $nodequery
    }

    # If Wan2 is missing, add it
    if( $node -and !$node.Wan2 ) {
        "Interface not found for Wan2, creating interface"
        $props = @{
            "NodeID" = "$($node.nodeid)"
            "ObjectSubType" = 'SNMP'
            "Name" = 'port2'
            "Index" = '2'
            "Icon" = '6.gif'
            "Type" = '6'
            "TypeName" = 'ethernetCsmacd'
            "TypeDescription" = 'Ethernet'
            "Speed" = '1000000000'
            "MTU" = '1500'
            "PhysicalAddress" = 'AC17C8000000'
            "AdminStatus" = '1'
            "OperStatus" = '1'
            "StatusIcon" = 'Up.gif'
            "InBandwidth" = '1000000000'
            "OutBandwidth" = '1000000000'
            "Caption" = 'port2'
            "FullName" = "$($node.caption) - port2"
            "Counter64" = 'Y'
            "Alias" = 'port2'
            "IfName" = ''
            "Severity" = '0'
            "CustomBandwidth" = 'False'
            "CustomPollerLastStatisticsPoll" = '1899-12-30 04:00:00'
            "PollInterval" = '120'
            "RediscoveryInterval" = '30'
            "StatCollection" = '7'
            "UnPluggable" = 'False'
            "InterfaceSubType" = '0'
            "AdminStatusLED" = 'Up.gif'
            "OperStatusLED" = 'Up.gif'
            "DuplexMode" = '0'
            "Status" = '1'
        }

        $result = new-swisobject $swis -entitytype 'orion.npm.interfaces' -properties $props
        $Interfaceid = $result.Substring(($result.indexof('InterfaceID=')+12))
        $pollertypes = @("I.StatisticsErrors32.SNMP.IfTable","I.StatisticsTraffic.SNMP.Universal","I.Status.SNMP.IfTable","I.Rediscovery.SNMP.IfTable" )
        foreach( $poller in $pollertypes ) {
            $pollerProps = @{
                "PollerType" = "$poller"
                "NetObject" = "I:$Interfaceid"
                "NetObjectType" = "I"
                "NetObjectID" = "$Interfaceid"
                "Enabled" = "True"
            }

            $pollerresult = new-swisobject $swis -EntityType 'Orion.Pollers' -Properties $pollerprops
        }
        $node = get-swisdata $swis $nodequery
    }

    #disable status pollers for Wan1 and Wan2
    $InterfacePollerQuery = @"
    select p.uri, p.Enabled
    from orion.nodes n
    join orion.npm.Interfaces i on i.nodeid=n.nodeid
    join orion.pollers p on i.InterfaceID=p.NetObjectID
    where n.nodeid = $($node.nodeid)
    and p.pollertype = 'I.Status.SNMP.IfTable'
    and i.caption in ('port1','port2')
    and p.enabled = 'true'
"@
    
    $InterfacePollersToDisable = get-swisdata $swis $InterfacePollerQuery
    foreach( $i in $InterfacePollersToDisable ) {
        set-swisobject $swis -Uri $i.uri -Properties @{ "Enabled" = "False" }
    }

    # if port1 Orion status doesnt match Meraki wan1, change it
    if( $node.status1 -eq 1 -and $device.uplinks[0].status -ne 'Active') {
        $props = @{
            "operstatus" = '2'
            "statusicon" = 'Down.gif'
            "operstatusled" = 'Down.gif'
            "status" = '2'
        }
        set-swisobject $swis -Uri $node.uri1 -Properties $props
    }
    if( $node.status1 -eq 2 -and $device.uplinks[0].status -eq 'Active') {
        $props = @{
            "operstatus" = '1'
            "statusicon" = 'Up.gif'
            "operstatusled" = 'Up.gif'
            "status" = '1'
        }
        set-swisobject $swis -Uri $node.uri1 -Properties $props
    }

    # if port2 Orion status doesnt match Meraki wan2, change it
    if( $node.status2 -eq 1 -and $device.uplinks[1].status -ne 'Active') {
        $props = @{
            "operstatus" = '2'
            "statusicon" = 'Down.gif'
            "operstatusled" = 'Down.gif'
            "status" = '2'
        }
        set-swisobject $swis -Uri $node.uri2 -Properties $props
    }
    if( $node.status2 -eq 2 -and $device.uplinks[1].status -eq 'Active') {
        $props = @{
            "operstatus" = '1'
            "statusicon" = 'Up.gif'
            "operstatusled" = 'Up.gif'
            "status" = '1'
        }
        set-swisobject $swis -Uri $node.uri2 -Properties $props
    }

    # if Orion web browse template doesn't match the Meraki URL change it
    if( $node.settingvalue -ne $device.url ) {
        $props = @{
            "settingvalue" = "$($device.url)"
        }
        set-swisobject $swis -Uri $node.weburi -Properties $props
    }
}

#Set the script up to run on a scheduled interval, maybe every 2-5 minutes depending on how fast it runs, look into maybe multithreading some of the foreach action?

#endregion Execution
#####-----------------------------------------------------------------------------------------#####
#region Cleanup

# Stop the clock and show us how long this took
$stopWatch.Stop()

Write-Host "SCRIPT DURATION: $( $stopWatch.Elapsed.Minutes )min $( $stopWatch.Elapsed.Seconds )sec" -ForegroundColor Yellow

Stop-Transcript

#endregion Cleanup
