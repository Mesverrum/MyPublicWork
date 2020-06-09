
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


$nodestomute = "example"


$query = @"
select n.Caption, n.uri, concat('N:',n.nodeid) as nodeid
from orion.nodes where n.caption like '%$nodestomute%'
"@
$Nodes = Get-SwisData $swis $query 



#times to unmanage between
$now = [DateTime]::UtcNow
$later = [DateTime]::UtcNow.AddDays(365)

# iterate through this list and update each group
foreach($Node in $Nodes)  
    {  
    # write out which group we're working with
    
    "   Unmanaging $($node.Caption) from $now to $later"
    Invoke-SwisVerb $swis Orion.Nodes Unmanage @($Node.nodeid, $now, $later, "false") | Out-Null

    "   Muting $($node.Caption) from $now to $later"
    Invoke-SwisVerb $swis Orion.AlertSuppression SuppressAlerts @(@($Node.uri), $now) | Out-Null 
    } 
