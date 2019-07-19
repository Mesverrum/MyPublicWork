#####-----------------------------------------------------------------------------------------#####
#region Functions
# Create a function to connect to the SolarWinds Information Service (SWIS)

Function Set-SwisConnection {
    Param(
        [ Parameter( Mandatory = $true, HelpMessage = "What SolarWinds server are you connecting to (Hostname or IP)?" ) ] [ string ] $SolarWindsServer,
        [ Parameter( Mandatory = $true, HelpMessage = "Do you want to use the credentials from PowerShell (Trusted), or a new login (Explicit)?" ) ] [ ValidateSet( 'Trusted', 'Explicit' ) ] [ string ] $ConnectionType
    )
    # Connect to SWIS

    IF ( $ConnectionType -eq 'Trusted'  ) {
        $swis = Connect-Swis -Trusted -Hostname $SolarWindsServer
    }

    ELSE {
        $creds = Get-Credential -Message "Please provide a Domain or Local Login for SolarWinds"
        $swis = Connect-Swis -Credential $creds -Hostname $SolarWindsServer
    }

RETURN $swis

}

Function Write-Log {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True,ValueFromPipeline)]
    [string]
    $Message
    )

    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $Line = "$Stamp $Message"
    Add-Content $logfile -Value $Line
    Write-Output $Line
}
#endregion Functions

#####-----------------------------------------------------------------------------------------#####
clear-host
$ScriptName = $MyInvocation.MyCommand.Name
$Logfile = "D:\Scripts\$ScriptName.log"


$hostname = "localhost" #Read-Host -Prompt "Hostname or IP Address of your SolarWinds server"

$swis = Set-SwisConnection -SolarWindsServer $hostname -ConnectionType trusted
"`n`n`nBegin Execution" | Write-Log
"hostname $hostname" | Write-Log
<#------------- ACTUAL SCRIPT -------------#>
##### Phase 1 #######

"Finding Dependencies group" | write-Log
$depParentID = Get-SwisData $swis "select containerid from orion.container where name = 'Dependencies'"


"Checking for Edge groups" | Write-Log
$edgeWANGroups = Get-swisdata $swis @"
select ncp.site, count(*) as wans
from orion.nodes n
join orion.NodesCustomProperties ncp on ncp.nodeid=n.nodeid
where n.caption like '%wan%'
group by ncp.site
having count(*) > 1
"@

foreach($wan in $edgeWANGroups) {
    "Working with $($wan.site)" | write-Log
    $parent = Get-SwisData $swis @"
        select top 1 'EDGE $($wan.site)' as Name, c.ContainerID
        from orion.nodes n
        left join orion.Container c on n.caption like '%' and c.name = 'EDGE $($wan.site)'
"@

    if(!$parent.ContainerID){
        "Creating Edge Group" | Write-Log
        $members = @(
            @{ Name = "$($wan.site) WAN NODES"; Definition = "filter:/Orion.Nodes[Contains(Caption,'WAN') AND CustomProperties.SIte='$($wan.site)']" }
        )
        $parent.Name = "EDGE $($wan.site)"
        $parent.ContainerID = (invoke-swisverb $swis "orion.container" "CreateContainerWithParent" @(
            $depParentID,
            "EDGE $($wan.site)",
            "Core",
            60,
            0,
            "",
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

    $edgeID = "C:"+$parent.ContainerID

    "Getting list of children of $($wan.site) EDGE" | Write-Log
    $children = Get-SwisData $swis @"
        select n.caption, ncp.uri, ncp.Edgeid
        from orion.nodes n
        join orion.NodesCustomProperties ncp on ncp.nodeid=n.nodeid
        where n.caption not like '%WAN%'
        and ncp.site = '$($wan.site)'
"@

    foreach($child in $children) {
        "Working with $($child.caption)" | Write-Log
        if($child.edgeid -eq $null) {
            " Setting EdgeID to $edgeID" | Write-Log
            Set-SwisObject $swis $child.uri -Properties @{ EdgeID = $edgeID }
        } else {
            " EdgeID already set to $($child.edgeid)" | Write-Log
        }
    }
}



"Checking for single nodes edges" | Write-Log
$edgeWANNodes = Get-swisdata $swis @"
select ncp.site, count(*) as wans
from orion.nodes n
join orion.NodesCustomProperties ncp on ncp.nodeid=n.nodeid
where n.caption like '%wan%'
group by ncp.site
having count(*) = 1
"@

foreach($wan in $edgeWANNodes) {
    $parent = Get-SwisData $swis @"
        select Caption as Name, n.nodeid
        from orion.nodes n
        where n.caption like '%wan%' and n.CustomProperties.site = '$($wan.site)'
"@

    $edgeID = "N:"+$parent.nodeid

    "Getting list of children of $($wan.site) EDGE" | Write-Log
    $children = Get-SwisData $swis @"
        select n.caption, ncp.uri, ncp.Edgeid
        from orion.nodes n
        join orion.NodesCustomProperties ncp on ncp.nodeid=n.nodeid
        where n.caption not like '%WAN%'
        and ncp.site = '$($wan.site)'
"@

    foreach($child in $children) {
        "Working with $($child.caption)" | Write-Log
        if($child.edgeid -eq $null) {
            " Setting EdgeID to $edgeID" | Write-Log
            Set-SwisObject $swis $child.uri -Properties @{ EdgeID = $edgeID }
        } else {
            " EdgeID already set to $($child.edgeid)" | Write-Log
        }
    }
}


"`nFinished" | Write-Log
"Errors below"  | Write-Log
$Error | Write-Log
