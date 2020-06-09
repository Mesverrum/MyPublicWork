
<#------------- CONNECT TO SWIS -------------#>
# load the snappin if it's not already loaded (step 1)
if (!(Get-PSSnapin | Where-Object { $_.Name -eq "SwisSnapin" })) {
    Add-PSSnapin "SwisSnapin"
}

#define target host and credentials

$hostname = 'orion.epiqcorp.com'
#$user = "admin"
#$password = "password"
# create a connection to the SolarWinds API
#$swis = connect-swis -host $hostname -username $user -password $password -ignoresslerrors
$swis = Connect-Swis -Hostname $hostname -Trusted

<#------------- ACTUAL SCRIPT -------------#>

# build the query in SWQL
$query = @"
    SELECT
        n.Caption
        ,n.Uri
        , n.nodeid
    FROM Orion.nodes n
    where caption like 'l061slwapps01%'
"@

# run the query and assign the results to the $nodes array
$nodes = Get-SwisData $swis $query

# iterate over the array
foreach ($node in $nodes) {
    # write out which node we're working with
    "Working with node: $($node.Caption)..."

Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' @"
insert into deletednodes (nodeid)
Values ($($node.nodeid))
"@

    # delete the node
    Remove-SwisObject $swis -Uri $node.Uri | Out-Null


} 
