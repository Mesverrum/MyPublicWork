<#------------- CONNECT TO SWIS -------------#>
# load the snappin if it's not already loaded (step 1)
if (!(Get-PSSnapin | Where-Object { $_.Name -eq "SwisSnapin" })) {
    Add-PSSnapin "SwisSnapin"
}


$hostname = "localhost"
$swis = Connect-Swis -Hostname $hostname -Trusted

#alternative connection method
#$user = "user"
#$password = "pass"
#$swis = connect-swis -host $hostname -username $user -password $password -ignoresslerrors

<#------------- ACTUAL SCRIPT -------------#>

$MenuTitle = Read-Host -Prompt "What is the title of the drop down menu you want to work with?"

# check if that drop down already exiss
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

$ViewURL = Read-Host -Prompt "What is the URL you want to add to this menu? (You can provide full URL's or use relative links by starting the address with a '/')"
$ViewTitle = Read-Host -Prompt "What is the title you want to give to this item?"

$ViewProps = @{
    Name = $ViewTitle.replace(' ','-')
    DefaultTitle = $ViewTitle
    Type = "legacy"
    URL = $ViewURL
    IsCustom = "True"
    SortOrder = 0
    OpenInNewWindow = "False"
}

"`Creating new menu item called $ViewTitle under $MenuTitle"
$ViewResults = New-SwisObject -SwisConnection $swis -EntityType "Orion.Web.View" -Properties $ViewProps

$MenuID = get-swisdata $swis @"
SELECT ID FROM Orion.Web.ViewGroup where uri = '$MenuResults'
"@

$ViewID = get-swisdata $swis @"
SELECT ID FROM Orion.Web.View where uri = '$ViewResults'
"@

$LinkViewtoGroup = Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' @"
INSERT WebViewGroupWebView (WebViewGroupID, WebViewID, SortOrder)  
VALUES ($MenuID,$ViewID,0) 
"@

$ClearCache = Invoke-SwisVerb $swis 'Orion.Web.Menu' 'ClearCache' -Arguments ""
