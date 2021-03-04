<#------------- CONNECT TO SWIS -------------#>
# load the snappin if it's not already loaded (step 1)
if (!(Get-PSSnapin | Where-Object { $_.Name -eq "SwisSnapin" })) {
    Add-PSSnapin "SwisSnapin"
}

#define host, credentials, and sql connection string

$hostname = "localhost"
#$user = "user"
#$password = "pass"
# create a connection to the SolarWinds API
#$swis = connect-swis -host $hostname -username $user -password $password -ignoresslerrors
$swis = Connect-Swis -Hostname $hostname -Trusted


<#------------- ACTUAL SCRIPT -------------#>


# get list of all views types with a map option
$viewkeys = get-swisdata $swis "SELECT distinct ViewKey FROM Orion.Views where viewtitle = 'map' and viewkey like '%StaticSubview' "

foreach ($viewkey in $viewkeys) 
    {
        "Working on $viewkey"
        
        #get the viewgroup to use for our parent clone
        $mapviewgroup = get-swisdata $swis "select top 1 viewgroup from orion.views where viewkey = '$viewkey'"
        
        #this will be the viewid of the parent of our clones
        $cloneviewparent = get-swisdata $swis "select viewid, uri from orion.views where viewgroup = '$mapviewgroup' and viewkey = '$viewkey'"
        " View to clone is $($cloneviewparent.viewid)"

        #get the correct viewkey
        $viewkeytoadd = get-swisdata $swis "select viewkey from orion.views where viewgroup = '$mapviewgroup' and (viewgroupposition = 1 or viewgroupposition is null)"

        #find any instances of that viewtype that don't already have a map
        $viewgrouptoadd = get-swisdata $swis "select viewgroup, viewgroupname, viewkey, viewtype, viewgroupposition from orion.views where viewkey = '$viewkeytoadd' and viewgroup not in (select viewgroup from orion.views where viewkey like '$viewkey%')"
        "Number of view groups to clone into is $($viewgrouptoadd.viewgroup.count)"

        foreach ($vg in $viewgrouptoadd.viewgroup )
            {
               $vieworder = get-swisdata $swis "select viewgroupname, max(viewgroupposition)+1 as position from orion.views where viewgroup = '$vg' group by viewgroupname "
               "  Cloning map to $($vieworder.viewgroupname) position $($vieworder.position)" 
               
               $newview = Invoke-SwisVerb $swis Orion.Views CloneView @($cloneviewparent.viewid , "Map")
               "   New Viewid is $($newview.'#text')"
               $newviewuri = get-swisdata $swis " select uri from orion.views where viewid = $($newview.'#text')"
               "   New view Uri is $newviewuri"
               Set-SwisObject $swis -Uri "$newviewuri" -Properties @{"ViewGroupName"="$($vieworder.viewgroupname)"; “ViewGroup” = "$vg"; "ViewGroupPosition"="$($vieworder.position)" } 
            }

    }
