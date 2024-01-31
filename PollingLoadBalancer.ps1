
<#------------- CONNECT TO SWIS -------------#>
# load the snappin if it's not already loaded (step 1)
if (!(Get-PSSnapin | Where-Object { $_.Name -eq "SwisSnapin" })) {
    Add-PSSnapin "SwisSnapin"
}

#define target host and credentials

$hostname = 'localhost'
#$user = "admin"
#$password = "password"
# create a connection to the SolarWinds API
#$swis = connect-swis -host $hostname -username $user -password $password -ignoresslerrors
$swis = Connect-Swis -Hostname $hostname -Trusted

<#------------- ACTUAL SCRIPT -------------#>

# how wide of a range of polling loads do we want to allow before nodes get moved?
$loadDelta = "0"

$query = @"
select top 1 n.uri, n.caption, e.HighServer, e.HighEngine, e.HighUsage, count(n.uri) as [Elements], low.LowServer, low.LowEngine, low.LowUsage, (e.HighUsage-low.LowUsage) as LoadDelta

from orion.nodes n
join (select top 1 p.engine.Servername as HighServer, engineid as HighEngine,currentusage as HighUsage from orion.PollingUsage p where scalefactor='orion.standard.polling' order by currentusage desc) e on e.HighEngine=n.engineid
join (select 
n.uri
from orion.nodes n

union all 
(select i.node.uri
from orion.npm.Interfaces i)

union all 
(select v.node.uri
from orion.volumes v)) c on c.uri=n.uri
join (select top 1 p.engine.servername as LowServer, engineid as LowEngine, currentusage as LowUsage from orion.PollingUsage p where scalefactor='orion.standard.polling' order by currentusage) low on low.Lowengine != n.engineid

Where e.HighUsage-low.LowUsage > $loadDelta
and n.objectsubtype != 'Agent'
group by n.uri, n.caption, e.HighEngine, e.HighUsage, low.LowEngine, low.LowUsage, e.HighServer, low.LowServer

order by [Elements] desc
"@

# get highest engine and its largest node
$polling = Get-SwisData $swis $query 

# while the difference between those is more than the delta move nodes
While ( $polling.length -eq 1 ) {
    # move highnode to lowengine
    "Moving $($polling.Caption) from $($polling.HighServer) to $($polling.LowServer)"
    Set-SwisObject -SwisConnection $swis -Uri $polling.uri -properties @{EngineID = $polling.Lowengine}  
    # let time pass for polling loads to update
    Start-Sleep -s 15
    # update Polling
    $polling = Get-SwisData $swis $query
    }

"All engines are within $loadDelta % of each other"

$results = Get-SwisData $swis @"
select distinct e.HighEngine, e.HighEngineID, e.HighUsage, low.LowEngine, low.LowEngineID, low.LowUsage, (e.HighUsage-low.LowUsage) as LoadDelta
from orion.engines n
join (select top 1 p.Engine.ServerName as HighEngine, engineid as HighEngineID,currentusage as HighUsage from orion.PollingUsage p where scalefactor='orion.standard.polling' order by currentusage desc) e on e.HighEngineid=n.engineid
left join (select top 1 p.Engine.ServerName as LowEngine, engineid as LowEngineID, currentusage as LowUsage from orion.PollingUsage p where scalefactor='orion.standard.polling' order by currentusage) low on low.Lowengineid != n.engineid
"@

$results
