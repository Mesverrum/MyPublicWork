
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

# check if application has a view already
$needviews = @"
select distinct toupper(ncp.applications) as applications, c.ContainerID, c.name, v.ViewID, v.ViewTitle, v.ViewGroupName
from orion.NodesCustomProperties ncp
left join orion.Container c on c.name like ncp.applications
left join orion.views v on v.viewtitle like ('Application - '+ c.name) or (v.ViewGroupName like ('Application - '+ c.name) and v.ViewGroupPosition=1)

where ncp.applications is not null and ncp.applications not in ('','N/A') and ncp.applications not like '%,%'
and v.viewid is null
"@

$views = get-swisdata $swis $needviews

$Gettemplate = @"
SELECT ViewID
FROM Orion.Views
where viewtitle = '_Template Application -'
"@
$viewtemplateid = get-swisdata $swis $Gettemplate

# clone applications view template
foreach($view in $views)
   	{
        "Creating view for $($view.applicationplatform)"
        
        invoke-swisverb $swis "Orion.Views" "CloneView" @(
           #View to clone
           "$viewtemplateid",
           #name to give
           "Application - $($view.applications)"
           )

$getnewview = @"
SELECT ViewID
FROM Orion.Views
where viewtitle = 'Application - $($view.applications)'
"@
$newviewid = get-swisdata $swis $getnewview
           
#copy resources from template to new view
invoke-swisverb $swis "Orion.Views" "CloneViewContents" @(
    #source view
    "$viewtemplateid",
    #destination view
    "$newviewid"   
    )
  }

  ########## Group Limitations ###########

$uriroot = get-swisdata $swis "SELECT SettingValue FROM Orion.WebSettings where settingname='SwisUriSystemIdentifier'"

#check for existing limitation
$limittype = get-swisdata $swis "SELECT LimitationTypeID FROM Orion.LimitationTypes where name  = 'Group of Groups'"

$needlimits = @"
select distinct toupper(ncp.applications) as applications, c.ContainerID, c.name, v.ViewID, v.ViewTitle, v.ViewGroupName, l.LimitationID 
from orion.NodesCustomProperties ncp
left join orion.Container c on c.name like ncp.applications
left join orion.views v on v.viewtitle like ('Application - '+ c.name) or (v.ViewGroupName like ('Application - '+ c.name) and v.ViewGroupPosition=1)
left join orion.Limitations l on l.WhereClause like ('% '+tostring(c.ContainerID)+')%') and LimitationTypeID=$limittype

where ncp.applications is not null and ncp.applications not in ('','N/A') and ncp.applications not like '%,%'
and l.limitationid is null
"@

$limitations = get-swisdata $swis $needlimits


#create application group based limitation
foreach($limit in $limitations)
   	{ 
        "Creating limitation for $($limit.applications)"
invoke-swisverb $swis "Orion.Limitations" "CreateLimitation" @( "$limittype",$null,@("$($limit.containerid)"),$null,$null )
}


$needtoapply = @"
select distinct toupper(ncp.applications) as applications, c.ContainerID, c.name, v.ViewID, v.ViewTitle, v.ViewGroupName, l.LimitationID 
from orion.NodesCustomProperties ncp
left join orion.Container c on c.name like ncp.applications
left join orion.views v on v.viewtitle like ('Application - '+ c.name) or (v.ViewGroupName like ('Application - '+ c.name) and v.ViewGroupPosition=1)
left join orion.Limitations l on l.WhereClause like ('% '+tostring(c.ContainerID)+')%') and LimitationTypeID=19

where ncp.applications is not null and ncp.applications not in ('','N/A') and ncp.applications not like '%,%'
and limitationid is not null
"@


$toapply = get-swisdata $swis $needtoapply


#create application group based limitation
foreach($view in $toapply)
   	{ 

#apply limitation to view
Set-SwisObject $swis -Uri "swis://$uriroot/Orion/Orion.Views/ViewID=$($view.viewid)" -Properties @{"limitationid"="$($view.limitationid)"}

}
