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

<#------------- ACTUAL SCRIPT -------------#>
clear-host

$now = Get-Date -Format "yyyyMMdd_HHmm"
$script = $MyInvocation.MyCommand
if($script.path){ $dir = Split-Path $script.path }
else { $dir = [Environment]::GetFolderPath("Desktop") }
$Logfile = "$dir\$($script.name)_$now.log"

Start-Transcript -Path $Logfile -Append -IncludeInvocationHeader

while(!$swistest) {
    $hostname = Read-Host -Prompt "What server should we connect to?" 
    $connectionType = Read-Host -Prompt "Should we use the current powershell credentials [Trusted], or specify credentials [Explicit]?" 
    $swis = Set-SwisConnection $hostname $connectionType
    $swistest = get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites"
}
$swistest = $null

"Connected to $hostname Successfully using $connectiontype credentials"

$quit = $null
while ($quit -ne "Quit" ) {

    "`nPlease provide the folder to import"
    $quit = Read-Host 'Press Enter to select file to import, or type [Quit] to exit'
    switch -regex ($quit) {
        "quit" { "`n`nQuitting"; $quit="Quit" ; break}
            
        default {
            $inputfolder = $null
            $inputfolder =  New-Object -Typename System.Windows.Forms.FolderBrowserDialog 
            $inputfolder.ShowDialog()
            $inputfolder =  $inputfolder.selectedpath
            "$inputfolder selected..."

            $isView = test-path ("$inputfolder\Viewdata.xml")
            $importedViews = @()
        
            if($isview -eq $false) {
                $folders = Get-ChildItem -Path $inputfolder -directory
            } else {
                $folders = "\"
            }

            foreach($folder in $folders) {
                $isView = test-path ("$inputfolder\$($folder.name)\Viewdata.xml")
                if ($isView -eq $false) {
                    "   Folder contains invalid data, missing $inputfolder\$($folder.name)\ViewData.xml"
                } else {
                    $viewdata = Import-Clixml -path ("$inputfolder\$($folder.name)\ViewData.xml")
                    $resources = Get-ChildItem -Path "$inputfolder\$($folder.name)" | Where-Object {$_.name -like "*.xml" -and $_.name -notlike "viewdata.xml"}
                    "`nThis folder contains the view $($viewdata.Viewgroupname) : $($viewdata.viewtitle) `nand the following resources`n"
                    $resources.name
                    if($viewData.viewgroupname -eq "NoViewGroup") { $viewData.viewgroupname = $null;}
                    $importedresources = @()
                    foreach ($resource in $resources) {
                        
                        $resourceproperties = Import-Clixml ("$inputfolder\$($folder.name)\$($resource.name)")
                        $Importedresource = New-Object -TypeName PSObject
                            Add-Member -InputObject $Importedresource -MemberType 'NoteProperty' -Name 'Name' -value $resource.name
                            Add-Member -InputObject $Importedresource -MemberType 'NoteProperty' -Name 'resourceproperties' -value $resourceproperties
                        $importedresources += $importedResource
                    }
                        

                    $ImportedView = New-Object -TypeName PSObject
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'viewgroupname' -value $viewdata.viewgroupname
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'ViewKey' -value $viewdata.ViewKey
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'ViewTitle' -value $viewdata.ViewTitle
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'ViewType' -value $viewdata.ViewType
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'ViewGroupPosition' -value $viewdata.ViewGroupPosition
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'ViewIcon' -value $viewdata.ViewIcon
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'Columns' -value $viewdata.Columns
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'Column1Width' -value $viewdata.Column1Width
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'Column2Width' -value $viewdata.Column2Width
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'Column3Width' -value $viewdata.Column3Width
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'Column4Width' -value $viewdata.Column4Width
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'Column5Width' -value $viewdata.Column5Width
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'Column6Width' -value $viewdata.Column6Width
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'System' -value $viewdata.System
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'Customizable' -value $viewdata.Customizable
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'NOCView' -value $viewdata.NOCView
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'NOCViewRotationInterval' -value $viewdata.NOCViewRotationInterval
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'condition' -value $viewdata.condition
                        Add-Member -InputObject $ImportedView -MemberType 'NoteProperty' -Name 'Resources' -value $importedresources

                    $importedViews += $ImportedView
                }
            }

            foreach($view in $importedViews) {
                " Checking on $($view.viewgroupname) : $($view.viewtitle)"
                if($view.viewgroupname -eq $null) {
                    $existingview = Get-SwisData $swis "select top 1 viewid, uri from orion.views v where v.viewtitle = '$($view.viewtitle)' and (viewgroupname is null or viewgroupname = '')"
                } else {
                    $existingview = Get-SwisData $swis "select top 1 viewid, uri from orion.views v where v.viewtitle = '$($view.viewtitle)' and v.viewgroupname = '$($view.viewgroupname)'"
                }
                $viewgroup = Get-SwisData $swis "select distinct viewgroup from orion.views v where v.viewgroupname = '$($view.viewgroupname)'"
                if($viewgroup -notmatch "\d+") {$viewgroup = $null}
                if($view.viewgroupname -ne $null -and $viewgroup -eq $null){
                    #generate the next available viewgroup number
                    $viewgroup = get-swisdata $swis "select min(viewgroup+1) as Nextgroup from orion.views where viewgroup is not null and viewgroup+1 not in (select distinct viewgroup from orion.views where viewgroup is not null) "
                }
                
                
                if(!$existingview) {
                    " Creating $($view.Viewgroupname) : $($view.ViewTitle)"
                    $viewprops = @{
                        "ViewGroup" = $viewgroup
                        "ViewGroupName" = $($view.ViewGroupName)
                        "Viewkey" = $($view.ViewKey)
                        "ViewTitle" = $($view.ViewTitle)
                        "ViewType" = $($view.ViewType)
                        "ViewGroupPosition" = $($view.ViewGroupPosition)
                        "ViewIcon" = $($view.ViewIcon)
                        "Columns" = $($view.Columns)
                        "Column1Width" = $($view.Column1Width)
                        "Column2Width" = $($view.Column2Width)
                        "Column3Width" = $($view.Column3Width)
                        "Column4Width" = $($view.Column4Width)
                        "Column5Width" = $($view.Column5Width)
                        "Column6Width" = $($view.Column6Width)
                        "System" = $($view.System)
                        "Customizable" = $($view.Customizable)
                        "NOCView" = $($view.NOCView)
                        "NOCViewRotationInterval" = $($view.NOCViewRotationInterval)
                    }

                    $newview = New-SwisObject $swis -EntityType "Orion.Views" -properties $viewprops
                    $viewid = Get-SwisData $swis "select viewid from orion.views where uri = '$newview'"
                    "New view created - $viewid"
                    }
                if($existingview) {
                    $viewid = $existingview.viewid
                    $menu = $null
                    while($menu -eq $null) {
                        $menu = Read-Host " View already exists as ViewID $viewid, should we [Add] the resouces to the view, [Replace] the contents of the view, or [Quit]?"
                        switch -regex ($menu) {
                            "quit" { "`n`nQuitting"; $menu="Quit" ; break}
                            "replace" {
                                $oldresources = get-swisdata $swis "SELECT uri FROM Orion.Resources where viewid = $($existingview.viewid)"
                                foreach ($r in $oldresources) {
                                    "  Removing old resources from view $viewid"
                                    Remove-SwisObject $swis -Uri $r | Out-Null
                                }
                            }
                            "add" { break } 
                            default {$menu = $null; "Invalid response, please re-enter"; break}

                        }
                    }
                }

                if($menu -ne "quit") {
                    foreach($r in $View.resources) {
                        "  Adding resource $($r.Name)"
                        $resourceResults = Invoke-SwisVerb $swis Orion.Views AddResourceToView @($viewid, $r.ResourceProperties)
                    }
                
                    "`nCleaning Up"
                    $cleanup = Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' @"
update resourceproperties set propertyvalue = replace(replace(propertyvalue, 'linebreak', char(10)),'ampersand',char(38)) where propertyvalue like '%linebreak%' or propertyvalue like '%ampersand%'
update resources set resourcename = replace(replace(ResourceName,'ampersand',char(38)),'doublequotes',char(34)), resourcetitle = replace(replace(ResourceTitle,'ampersand',char(38)),'doublequotes',char(34)), resourcesubtitle = replace(replace(resourcesubtitle,'ampersand',char(38)),'doublequotes',char(34)) where resourcename like '%ampersand%' or resourcetitle like '%ampersand%' or resourcesubtitle like '%ampersand%' or resourcename like '%doublequotes%' or resourcetitle like '%doublequotes%' or resourcesubtitle like '%doublequotes%'
"@

                    if($ImportedView.condition) {
                        $sqlcondition = Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' "SELECT condition FROM [dbo].[ViewConditions] where viewid = $viewid"
                        if(!$sqlcondition.ChildNodes.documentelement.executesqlresults) {Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' "insert into [dbo].[ViewConditions] values ( $viewid,'$($ImportedView.condition)' )"}
                        else {Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' "update [ViewConditions] set condition = '$($ImportedView.condition)' where viewid = '$viewid'" | out-null}
                    }
                }
            }
        }
    }
}

"Finished"

Stop-Transcript
