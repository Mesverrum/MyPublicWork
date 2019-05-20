
#define target host and credentials

$hostname = 'localhost'
#$user = "admin"
#$password = "password"
# create a connection to the SolarWinds API
#$swis = connect-swis -host $hostname -username $user -password $password -ignoresslerrors
$swis = Connect-Swis -Hostname $hostname -Trusted

<#------------- ACTUAL SCRIPT -------------#>

$query = @"
SELECT Nodes.customproperties.Uri, Nodes.Caption, nodes.customproperties.applicationsrole
FROM Orion.Nodes AS Nodes
where nodes.nodeid in 
(select distinct nodeid 
from orion.AssetInventory.Software
where name like 'Microsoft SQL Server%bit%')
and
(nodes.customproperties.applicationsrole is null 
or nodes.customproperties.applicationsrole not like '%MSSQL database%')

"@
$Nodes = Get-SwisData $swis $query 

foreach($Node in $Nodes)  
    {      
        if(!$Node.applicationsrole) {
            $applicationsrole = 'MSSQL Database'
        } else {
            $applicationsrole = "$($Node.applicationsrole), MSSQL Database"
        }
        "Setting $($Node.Caption) ApplicationsRole to $applicationsrole"    
        Set-SwisObject -SwisConnection $swis -Uri $Node.uri -properties @{applicationsrole = $applicationsrole }
    }  
