
<#------------- CONNECT TO SWIS -------------#>
#define host, credentials, and sql connection string

$hostname = "localhost"
#$user = "user"
#$password = "pass"
# create a connection to the SolarWinds API
#$swis = connect-swis -host $hostname -username $user -password $password -ignoresslerrors
$swis = Connect-Swis -Hostname $hostname -UserName "Admin"

<#------------- ACTUAL SCRIPT -------------#>

$SQLquery = @"
SELECT distinct s.NodeID, ncp.uri
FROM Orion.AssetInventory.Software s
join orion.NodesCustomProperties ncp on ncp.NodeID=s.NodeID
where name like 'Microsoft SQL Server%'
"@

$sqlNodes = get-swisdata $swis $SQLquery


foreach ($node in $sqlNodes ) {
    Set-SwisObject -SwisConnection $swis -Uri $node.uri -Properties @{ApplicationRole = "Database"}
}

$SWquery = @"
SELECT distinct s.NodeID, ncp.uri, ncp.application
FROM Orion.AssetInventory.Software s
join orion.NodesCustomProperties ncp on ncp.NodeID=s.NodeID
where Name = 'SolarWinds Platform' and ( ncp.application != 'SolarWinds' or ncp.application is not null)
"@

$swNodes = get-swisdata $swis $SWquery

foreach ($node in $swNodes ) {
    Set-SwisObject -SwisConnection $swis -Uri $node.uri -Properties @{Application = "SolarWinds"}
}


$AppsToCheck = @(
    @{SoftwareName = "SolarWinds Platform"; Tag="SolarWinds" };
)

foreach($app in $AppsToCheck) {
    $ApplicationQuery = @"
        SELECT distinct s.NodeID, ncp.uri, ncp.application
        FROM Orion.AssetInventory.Software s
        join orion.NodesCustomProperties ncp on ncp.NodeID=s.NodeID
        where Name = '$($app.SoftwareName)' and ( ncp.application != '$($app.Tag)' or ncp.application is not null)
"@

        $Nodes = get-swisdata $swis $ApplicationQuery

        foreach ($node in $Nodes ) {
            Set-SwisObject -SwisConnection $swis -Uri $node.uri -Properties @{Application = "$($app.Tag)"}
        }
}





