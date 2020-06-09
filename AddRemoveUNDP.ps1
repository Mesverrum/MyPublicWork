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
# get a list of nodes that should have this poller
$nodes = get-swisdata $swis @"
SELECT n.nodeid--,n.caption, n.vendor
from orion.nodes n 
where n.vendor='Cisco' and n.caption like '%edge%asr%'
"@

"Nodes:"
$nodes

#get a list of UNDP pollers to assign
$pollers = get-swisdata $swis @"
select cp.CustomPollerID--, uniquename
from orion.npm.CustomPollers cp
where cp.UniqueName like 'tested'
"@
"Pollers:"
$pollers.Guid

foreach ($node in $nodes) {
#check if node already has each poller
    foreach ($poller in $pollers) {
        $check = get-swisdata $swis @"
select cpon.AssignmentName, cpon.uri--, cpon.NodeID ,cpon.CustomPollerID
from orion.npm.CustomPollerAssignmentOnNode cpon
where cpon.NodeID = '$node'
and cpon.CustomPollerID = '$poller'
"@

        if ($check) {
            " Already Assigned, $($check.AssignmentName) "
            # To remove pollers you can use the next two lines
            # Remove-SwisObject $swis $check.uri
            # "Deleting $($check.AssignmentName)"

        }
        else {
            " Creating poller "
            New-SwisObject $swis Orion.NPM.CustomPollerAssignmentOnNode @{NodeID=$node;CustomPollerID=$poller}
        }
    }


}
