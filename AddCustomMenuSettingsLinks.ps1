<#------------- CONNECT TO SWIS -------------#>

$hostname = "localhost"
#$swis = Connect-Swis -Hostname $hostname -Trusted

#alternative connection method
$user = "Admin"
#$password = "pass"
$swis = connect-swis -host $hostname -username $user -ignoresslerrors

<#------------- ACTUAL SCRIPT -------------#>

$MenuTitle = "Settings"

# check if that drop down already exists
$MenuTest = get-swisdata $swis @"
SELECT ID, Name, DefaultTitle, Tags, SortOrder, OrionFeatureName, URI
FROM Orion.Web.ViewGroup
where DefaultTitle = '$MenuTitle'
"@

if (!$MenuTest) {
    $MenuProps = @{
    Name = $MenuTitle.replace(' ','')
    DefaultTitle = $MenuTitle
    Tags = "navigation"
    SortOrder = 99
}
    "`Creating new menu called $MenuTitle"
    $MenuResults = New-SwisObject -SwisConnection $swis -EntityType "Orion.Web.ViewGroup" -Properties $MenuProps

} else {
    $MenuResults = $MenuTest.URI
}

"`Menu called $MenuTitle exists..."

$Links = @(
    @{ URL = "/Orion/Nodes/Add/Default.aspx"; Title = "Add Node";},  
    @{ URL = "/Orion/AgentManagement/Admin/ManageAgents.aspx"; Title = "Manage Agents";},
    @{ URL = "/Orion/Admin/Accounts/Accounts.aspx"; Title = "Manage Orion Accounts";},
    @{ URL = "/Orion/Alerts/Default.aspx"; Title = "Manage Alerts";}, 
    @{ URL = "/Orion/Admin/PollingSettings.aspx"; Title = "Polling Settings";}, 
    @{ URL = "/Orion/Admin/Credentials/CredentialManager.aspx"; Title = "Manage Orion Credentials - Windows";}, 
    @{ URL = "/Orion/Admin/Credentials/SNMPCredentialManager.aspx"; Title = "Manage Orion Credentials - SNMPv3";}, 
    @{ URL = "/Orion/Admin/CPE/Default.aspx"; Title = "Manage Custom Properties";}, 
    @{ URL = "/Orion/Admin/CPE/InlineEditor.aspx"; Title = "Edit Custom Properties";}, 
    @{ URL = "/Orion/Admin/DependenciesView.aspx"; Title = "Manage Dependencies";}, 
    @{ URL = "/Orion/Admin/Containers/Default.aspx"; Title = "Manage Groups";}, 
    @{ URL = "/Orion/Reports/Default.aspx"; Title = "Manage Reports";}, 
    @{ URL = "/Orion/Admin/ListViews.aspx"; Title = "Manage Views";}, 
    @{ URL = "/Orion/WorldMap/Manage.aspx?"; Title = "Manage Worldwide Map";}, 
    @{ URL = "/Orion/APM/Admin/Default.aspx"; Title = "SAM Settings";}, 
    @{ URL = "/Orion/APM/Admin/Applications/Default.aspx"; Title = "Manage Assigned Applications";}, 
    @{ URL = "/Orion/APM/Admin/ApplicationTemplates.aspx"; Title = "Manage Application Templates";}, 
    @{ URL = "/Orion/APM/Admin/Components/Templates.aspx"; Title = "Manage Application Components";}, 
    @{ URL = "/Orion/NCM/Admin/Default.aspx"; Title = "NCM Settings";}, 
    @{ URL = "/Orion/TrafficAnalysis/Admin/NetflowSettings.aspx"; Title = "NTA Settings";},  
    @{ URL = "/Orion/Admin/Details/ModulesDetailsHost.aspx"; Title = "License Details";}
)


$sqlStuff = [System.Collections.Generic.List[System.Object]]::new()

$Order = 1
foreach ($Link in $links) {
    $ViewURL = $Link.URL
    $ViewTitle = $Link.Title

    $ViewProps = @{
        Name = $ViewTitle.replace(' ','-')
        DefaultTitle = $ViewTitle
        Type = "legacy"
        URL = $ViewURL
        IsCustom = "True"
        SortOrder = $Order++ # alternatively you can set all your rows to have the same order and Orion will sort alphabetically
        OpenInNewWindow = "False"
    }

    "`Creating new menu item called $ViewTitle under $MenuTitle"
    $ViewResults = New-SwisObject -SwisConnection $swis -EntityType "Orion.Web.View" -Properties $ViewProps

    $MenuID = get-swisdata $swis " SELECT ID FROM Orion.Web.ViewGroup where uri = '$MenuResults' "

    $ViewID = get-swisdata $swis " SELECT ID FROM Orion.Web.View where uri = '$ViewResults' "
    $SQLQuery = @"
INSERT WebViewGroupWebView (WebViewGroupID, WebViewID, SortOrder)  
VALUES ($MenuID,$ViewID,$Order) 
"@

    $sqlStuff.Add($SQLQuery)

    # ExecuteSQL verb has been locked down, cannot insert rows to WebViewGroupWebView anymore due to security changes
    #$LinkViewtoGroup = Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' @"
#INSERT WebViewGroupWebView (WebViewGroupID, WebViewID, SortOrder)  
#VALUES ($MenuID,$ViewID,$Order) 
#"@
}

$ClearCache = Invoke-SwisVerb $swis 'Orion.Web.Menu' 'ClearCache' -Arguments ""

"These SQL commands need to be run in Database Manager or SSMS"
$sqlStuff
