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
    $hostname = Read-Host -Prompt "what server should we connect to?" 
    $connectionType = Read-Host -Prompt "Should we use the current powershell credentials [Trusted], or specify credentials [Explicit]?" 
    $swis = Set-SwisConnection $hostname $connectionType
    $swistest = get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites" 
}

"Connected to $hostname Successfully using $connectiontype credentials"

$quit = $null
while ($quit -ne "Quit" ) {

    "`nPlease provide the resource to import"
    $quit = Read-Host 'Press Enter to select file to import, or type [Quit] to exit'
    switch -regex ($quit) {
        "quit" { "`n`nQuitting"; $quit="Quit" ; break}
            
        default {
            Add-Type -AssemblyName System.Windows.Forms
            $inputfolder = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
                InitialDirectory = [Environment]::GetFolderPath('Desktop') 
                Filter = 'XML (*.xml)|*.xml'
            }
            $null = $inputfolder.ShowDialog()
            $inputfolder = $inputfolder.FileName
            "$inputfolder selected..."

            $resourceproperties = Import-Clixml ("$inputfolder")

            $viewid = Read-Host -Prompt "Which ViewID # should we add this resource to?"
            
            $resourceResults = Invoke-SwisVerb $swis Orion.Views AddResourceToView @($viewid, $ResourceProperties)
            
            "`nCleaning Up"
            $cleanup = Invoke-SwisVerb $swis 'Orion.Reporting' 'ExecuteSQL' @"
update resourceproperties set propertyvalue = replace(replace(propertyvalue, 'linebreak', char(10)),'ampersand',char(38)) where propertyvalue like '%linebreak%' or propertyvalue like '%ampersand%'
update resources set resourcename = replace(replace(ResourceName,'ampersand',char(38)),'doublequotes',char(34)), resourcetitle = replace(replace(ResourceTitle,'ampersand',char(38)),'doublequotes',char(34)), resourcesubtitle = replace(replace(resourcesubtitle,'ampersand',char(38)),'doublequotes',char(34)) where resourcename like '%ampersand%' or resourcetitle like '%ampersand%' or resourcesubtitle like '%ampersand%' or resourcename like '%doublequotes%' or resourcetitle like '%doublequotes%' or resourcesubtitle like '%doublequotes%'
"@

        }
    }
}

"Finished"

Stop-Transcript
