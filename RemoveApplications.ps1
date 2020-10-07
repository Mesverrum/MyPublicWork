
<#------------- CONNECT TO SWIS -------------#>
# load the snappin if it's not already loaded (step 1)
if (!(Get-PSSnapin | Where-Object { $_.Name -eq "SwisSnapin" })) {
    Add-PSSnapin "SwisSnapin"
}

#define target host and credentials

$hostname = 'yourserver'
# create a connection to the SolarWinds API
#$swis = connect-swis -host $hostname -username $user -password $password -ignoresslerrors
$swis = Connect-Swis -Hostname $hostname -Trusted

<#------------- ACTUAL SCRIPT -------------#>

# build the query in SWQL
$query = @"
select a.name, a.ApplicationID
from orion.apm.Application a
where a.node.caption like '%slwapps01%' and a.name = 'Microsoft IIS'
"@

# run the query and assign the results to the $applications array
$applications = Get-SwisData $swis $query

# iterate over the array
foreach ($app in $applications) {
    # write out which application we're working with
    "Working with application: $($app.name)..."

    # delete the application
    Invoke-SwisVerb $swis 'Orion.APM.Application' 'DeleteApplication' $app.applicationid
}
