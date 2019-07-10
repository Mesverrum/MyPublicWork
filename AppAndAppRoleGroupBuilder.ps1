
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
##### Phase 1 - Create groups tree #######



#########get applications list
$applications = get-swisdata $swis @"
select distinct n.CustomProperties.Applications
from orion.nodes n 
left join orion.Container c on c.name = n.CustomProperties.Applications
where n.CustomProperties.Applications is not null and n.CustomProperties.Applications not in ('') 
order by n.CustomProperties.Applications
"@

foreach($app in $applications)
    {
    #get groupid for parent folder
    $parent = get-swisdata $swis "select top 1 containerid from orion.container where name='Applications'"

    $appcheck = get-swisdata $swis "select containerid from orion.container where name = '$app'"
    if(!$appcheck)         {
            "   Creating group for $app"
            $members = @(
    	    	    @{ Name = "$app Nodes"; Definition = "filter:/Orion.Nodes[Contains(CustomProperties.Applications,'$app') AND CustomProperties.ApplicationsRole='Unknown']" },
                    @{ Name = "$app Applications"; Definition = "filter:/Orion.APM.GenericApplication[Contains(CustomProperties.Applications,'$app') AND CustomProperties.ApplicationsRole='Unknown']" },
    	            @{ Name = "$app IIS"; Definition = "filter:/Orion.APM.IIS.Application[Contains(CustomProperties.Applications,'$app') AND CustomProperties.ApplicationsRole='Unknown']" },
    	            @{ Name = "$app SQL"; Definition = "filter:/Orion.APM.SqlServerApplication[Contains(CustomProperties.Applications,'$app') AND CustomProperties.ApplicationsRole='Unknown']" }
    	        )
            $appid = (invoke-swisverb $swis "orion.container" "CreateContainerWithParent" @(
            "$parent",
            "$app",
            "Core",
            300,
            0,
            "$app child nodes and applications"
            "true",
            ([xml]@("<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>",
	        [string]($members |% {
    	        "<MemberDefinitionInfo><Name>$($_.Name)</Name><Definition>$($_.Definition)</Definition></MemberDefinitionInfo>"
    		        } 
            ),
            "</ArrayOfMemberDefinitionInfo>"
            )).DocumentElement 
            )).innertext 
        }
    else
        {
            "   $app already exists"
        }




############get components list
$roles = get-swisdata $swis @"
select distinct toupper(concat(n.CustomProperties.Applications,' ',n.CustomProperties.ApplicationsRole)) as Components
from orion.nodes n 
left join orion.Container c on c.name= concat(n.CustomProperties.Applications,' ',n.CustomProperties.ApplicationsRole)
where n.CustomProperties.Applications is not null and n.CustomProperties.Applications not in ('','unknown','N/A','not applicable')
and n.CustomProperties.ApplicationsRole is not null and n.CustomProperties.ApplicationsRole not in ('','unknown','N/A','not applicable')
and n.CustomProperties.Applications = '$app'
and n.CustomProperties.ApplicationsRole not like '%,%'
order by concat(n.CustomProperties.Applications,' ',n.CustomProperties.ApplicationsRole)
"@

    foreach($role in $roles)
   	    {

        #get groupid for parent folder
        $parent = get-swisdata $swis "select top 1 containerid from orion.container where name='$app'"

        $rolecheck = get-swisdata $swis "select containerid from orion.container where name = '$role'"
        if($rolecheck.length -eq 0)
            {
                #creating variables for definitions
                $role2 = $role -replace "$app ",''
                
                "    Creating group for $role"
                $members = @(
    	    	    @{ Name = "$role Nodes"; Definition = "filter:/Orion.Nodes[Contains(CustomProperties.Applications,'$app') AND Contains(CustomProperties.ApplicationsRole,'$role2')]" },
                    @{ Name = "$role Applications"; Definition = "filter:/Orion.APM.GenericApplication[Contains(CustomProperties.Applications,'$app') AND Contains(CustomProperties.ApplicationsRole,'$role2')]" },
    	            @{ Name = "$role IIS"; Definition = "filter:/Orion.APM.IIS.Application[Contains(CustomProperties.Applications,'$app') AND Contains(CustomProperties.ApplicationsRole,'$role2')]" },
    	            @{ Name = "$role SQL"; Definition = "filter:/Orion.APM.SqlServerApplication[Contains(CustomProperties.Applications,'$app') AND Contains(CustomProperties.ApplicationsRole,'$role2')]" }
    	        )
                $envid = (invoke-swisverb $swis "orion.container" "CreateContainerWithParent" @(
                "$parent",
                "$role",
                "Core",
                300,
                0,
                "$role child nodes and applications",
                "true",
                ([xml]@("<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>",
	            [string]($members |% {
    	            "<MemberDefinitionInfo><Name>$($_.Name)</Name><Definition>$($_.Definition)</Definition></MemberDefinitionInfo>"
    		            } 
                ),
                "</ArrayOfMemberDefinitionInfo>"
                )).DocumentElement 
                )).innertext 
            }
        else
            {
                "    $role already exists"
            }
        }
    }
