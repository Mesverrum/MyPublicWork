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
# Connect to SWIS
clear-host
$ScriptName = $MyInvocation.MyCommand.Name
$Logfile = "D:\Scripts\$ScriptName.log"


$hostname = "localhost" #Read-Host -Prompt "Hostname or IP Address of your SolarWinds server"

$swis = Set-SwisConnection -SolarWindsServer $hostname -ConnectionType trusted
"`n`n`nBegin Execution" | Write-Log
"hostname $hostname" | Write-Log
<#------------- ACTUAL SCRIPT -------------#>
##### Phase 1 #######
# Updates Dependency table to reflect the node EdgeID property, automatically deletes entries for nodes that no longer exist and updates based on changes to the custom property



$query = @"
MERGE SolarWindsOrion.dbo.Dependencies AS Target  
USING  
(SELECT  
n.NodeID  
,n.Caption  
,n.Site 
,replace(replace(n.EdgeID,'n:',''),'c:','') as EdgeID
,'Scripted - Child N:' + CONVERT(NVARCHAR(250),n.NodeID) + ' of ' + n.EdgeID AS 'DependencyName'  
,'swis://' + (SELECT settingvalue from [dbo].[WebSettings] where settingname = 'SwisUriSystemIdentifier') + case when n.edgeid like 'c:%' then '/Orion/Orion.Groups/ContainerID='+replace(n.EdgeID,'C:','') when n.edgeid like 'n:%' then '/Orion/Orion.Nodes/NodeID='+replace(n.EdgeID,'N:','') end AS 'ParentUri'  
,'swis://' + (SELECT settingvalue from [dbo].[WebSettings] where settingname = 'SwisUriSystemIdentifier') + '/Orion/Orion.Nodes/NodeID='+CONVERT(NVARCHAR(250),n.NodeID) AS 'ChildUri'  
, case when n.edgeid like 'c:%' then 'Orion.Groups' when n.edgeid like 'n:%' then 'Orion.Nodes' end as ParentEntityType
FROM SolarWindsOrion.dbo.Nodes n 
LEFT JOIN SolarWindsOrion.dbo.Dependencies d ON (d.ChildUri LIKE '%='+CONVERT(NVARCHAR(250),n.NodeID) AND d.Name LIKE 'auto_g%')  
) AS Source (NodeID, Caption, Site, EdgeID, DependencyName, ParentUri, ChildUri, ParentEntityType) ON (Target.ChildUri = Source.ChildUri AND Target.Name = Source.DependencyName)  
-- DELETE RECORD...  
WHEN NOT MATCHED BY source --if node no longer exist in Nodes table...  
  AND Target.Name LIKE 'Scripted -%' --and providing that record has been created by this automation  
THEN DELETE  
-- DELETE RECORD...  
WHEN MATCHED --if node exist...  
  AND Target.Name LIKE 'Scripted -%' --and providing that record has been created by this automation  
  AND (  
  Source.Site IS NULL --and either site was not specified  
  OR Source.EdgeID IS NULL --or edge was not specified for this site  
  OR Source.NodeID IN --or node is a member of the edge itself  
    (SELECT n_excl.EntityID  
     FROM SolarwindsOrion.dbo.ContainerMemberSnapshots n_excl  
     WHERE  
       n_excl.EntityType = 'Orion.Nodes'
       AND Source.ParentEntityType = 'Orion.Groups'
       AND n_excl.ContainerID = Source.EdgeID))  
THEN DELETE  
-- UPDATE RECORD...  
WHEN MATCHED --when it is already there...  
  AND Target.Name LIKE 'Scripted -%' --and providing that record has been created by this automation...  
  AND Source.ParentUri <> Target.ParentUri --and edge group has been changed (this can be due to site for the node has been changed or edge group has been changed for the entire site)  
THEN UPDATE  
  SET  
   Name = Source.DependencyName,  
   ParentUri = Source.ParentUri,  
   LastUpdateUtc = GetUtcDate()  
-- INSERT NEW RECORD...  
WHEN NOT MATCHED BY target --when it does not already exist...  
  AND Source.Site IS NOT NULL --and site has been specified...  
  AND Source.EdgeID IS NOT NULL --and edge group has been specified...  
  AND Source.NodeID NOT IN --and node is not a member of the Edge group itself  
    (SELECT n_excl.EntityID  
     FROM SolarwindsOrion.dbo.ContainerMemberSnapshots n_excl  
     WHERE  
       n_excl.EntityType = 'Orion.Nodes'
       AND Source.ParentEntityType = 'Orion.Groups'
       AND n_excl.ContainerID = Source.EdgeID)  
THEN 
  INSERT (Name, ParentUri, ChildUri, LastUpdateUtc, ParentNetObjectID, ChildNetObjectID, ParentEntityType, ChildEntityType) 
  VALUES (Source.DependencyName, Source.ParentUri, Source.ChildUri, GetUtcDate(), Source.EdgeID, Source.NodeID, Source.ParentEntityType, 'Orion.Nodes') 
;
"@

$result = Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' $query 

"`nFinished" | Write-Log
"Errors below"  | Write-Log
$Error | Write-Log
