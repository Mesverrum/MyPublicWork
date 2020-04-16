<#------------- FUNCTIONS -------------#>
Function Set-SwisConnection {  
    Param(  
        [Parameter(Mandatory=$true, HelpMessage = "What SolarWinds server are you connecting to (Hostname or IP)?" ) ] [string] $solarWindsServer,  
        [Parameter(Mandatory=$true, HelpMessage = "Do you want to use the credentials from PowerShell [Trusted], or a new login [Explicit]?" ) ] [ ValidateSet( 'Trusted', 'Explicit' ) ] [ string ] $connectionType,  
        [Parameter(HelpMessage = "Which credentials should we use for an explicit logon type" ) ] $creds
    )  
     
    IF ( $connectionType -eq 'Trusted'  ) {  
        $swis = Connect-Swis -Trusted -Hostname $solarWindsServer  
    } ELSEIF(!$creds) {  
        $creds = Get-Credential -Message "Please provide a Domain or Local Login for SolarWinds"  
        $swis = Connect-Swis -Credential $creds -Hostname $solarWindsServer  
    } ELSE {
        $swis = Connect-Swis -Credential $creds -Hostname $solarWindsServer  
    } 

    RETURN $swis  
}  

function Export-Resource {
    param(
        [Parameter(Mandatory=$true)] [Validatenotnullorempty()] $swis,
        [Parameter(Mandatory=$true, HelpMessage = "What resourceID are we exporting?" )] [int] $resourceID,
        [Parameter(HelpMessage = "Do we need to save this resource to an XML file?" )] $exportXML,
        [Parameter(HelpMessage = "What path should the XML be saved to?" )] $exportXMLpath
    )

    <#
    Example of a correctly formatted resource definition XML: 
    <resource name="Top CPUs by Percent Load" file="/Orion/NetPerfMon/Resources/MultiSourceCharts/MultipleObjectChart.ascx" column="2" position="3" title="Top CPUs by Percent Load" subtitle="">  
      <properties>  
        <property name="ChartName" value="AvgCPUMultiLoad"/>  
        <property name="EntityName" value="Orion.Nodes"/>  
        <property name="FilterEntities" value="False"/>  
        <property name="ManualSelect" value="False"/>  
        <property name="Period" value="Today"/>  
        <property name="SampleSize" value="30M"/>  
        <property name="ShowSum" value="NoSum"/>  
        <property name="AutoHide" value="1"/>  
      </properties>  
    </resource>  
    #>

    $Resource = get-swisdata $swis @"
select distinct ResourceID, ViewColumn, Position, replace(replace(ResourceName,'&','ampersand'),'"','doublequotes') as ResourceName, ResourceFile, replace(replace(ResourceTitle,'&','ampersand'),'"','doublequotes') as ResourceTitle, replace(replace(ResourceSubTitle,'&','ampersand'),'"','doublequotes') as ResourceSubTitle, viewgroup
from orion.Views v
left join orion.Resources r on r.ViewID=v.ViewID
where r.resourceid = '$ResourceID'
"@

    
    $header = @"
<resource name="$($resource.ResourceName)" file="$($resource.ResourceFile)" column="$($resource.ViewColumn)" position="$($resource.Position)" title="$($resource.ResourceTitle)" subtitle="$($resource.ResourceSubTitle)">  
<properties>  
"@

    $rquery = @"
select propertyname, replace(replace(propertyvalue,char(10),'linebreak'),char(38),'ampersand') as propertyvalue
FROM resourceproperties rp 
where rp.resourceid=$($resource.ResourceID)
"@
    $resourceProperties = Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' @($rquery)

    $xmlRequest = $header
foreach ($p in $resourceproperties.childnodes.documentelement.executesqlresults) {
        $xmlRequest += '<property name = "' + $($p.propertyname) + '" value="' + ([System.Net.WebUtility]::HtmlEncode($p.propertyvalue)) + '" />'
    }
    $xmlRequest += '</properties></resource>'

    if($exportXML) {
        $namecleanup = "$($resource.ResourceTitle)_$($resource.ResourceID)"
        $namecleanup = $namecleanup.Replace("\", " ").Replace("/", " ").replace("<"," ").replace(">"," ").replace(":"," ").replace("|"," ").replace("?", " ").replace("*"," ")
        if(!$exportXMLpath) {
            $exportXMLpath ="$($env:USERPROFILE)\Desktop\$($namecleanup).xml"
        }
        
        $xmlRequest | Export-Clixml -Path ($exportXMLpath + "$($namecleanup).xml")
    }
    return $xmlRequest
}

<#------------- ACTUAL SCRIPT -------------#>
clear-host

$now = Get-Date -Format "yyyyMMdd_HHmm"
$script = $MyInvocation.MyCommand
if ($script.path) { $dir = Split-Path $script.path }
else { $dir = [Environment]::GetFolderPath("Desktop")}
$Logfile = "$dir\$($script.name)_$now.log"
Start-Transcript -Path $Logfile -Append -IncludeInvocationHeader | Out-Null

while(!$swistest) {
    $hostname = Read-Host -Prompt "what server should we connect to?" 
    $connectionType = Read-Host -Prompt "Should we use the current powershell credentials [Trusted], or specify credentials [Explicit]?" 
    $swis = Set-SwisConnection $hostname $connectionType
    $swistest = get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites" 
}

"Connected to $hostname Successfully using $connectiontype credentials"


$viewid = $null
while ($viewid -eq $null ) {
    $viewid = get-swisdata $swis "select viewid from orion.views"
}

#$viewid
foreach($view in $viewid) {
    $viewdata = (Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' @"
select viewgroup, v.viewid, rtrim(ViewKey) AS ViewKey, rtrim(ViewTitle) as ViewTitle, case when viewgroup is null then 'NoViewGroup' 
else isnull(rtrim(viewgroupname),cast(viewgroup as nvarchar)) end as viewgroupname, ViewType, ViewGroupPosition
, ViewIcon, Columns, Column1Width, Column2Width, Column3Width, Column4Width, Column5Width, Column6Width
, 'N' as System, Customizable, NOCView, NOCViewRotationInterval, vc.condition
From Views v
left join [ViewConditions]vc on vc.viewid=v.viewid 
where v.viewid = $view
"@).childnodes.documentelement.executesqlresults | select-object -first 1

    $UserPath = "$($env:USERPROFILE)\Desktop\ViewExports\$($viewdata.ViewGroupName)\$($viewdata.ViewTitle)\"
    
    " Exporting view $($viewdata.viewtitle) to $UserPath"
    if((test-path $userpath) -eq $false) {$newfolder = md -path $UserPath}
    $viewdata | Export-Clixml ($UserPath + "ViewData.xml")

    #get a list of all resources on the view we want to migrate over
    $resourceids = get-swisdata $swis @"
    select distinct ResourceID, r.ResourceTitle
    from orion.Resources r
    where viewid = $view
"@

    foreach($resourceid in $resourceids) {
        "   Exporting Resource $($Resourceid.Resourcetitle)"
        $Resource = Export-Resource $swis $resourceid.resourceid True $UserPath
    }
}

"Finished"

Stop-Transcript
