requires -version 2
<#
.SYNOPSIS
  <Overview of script>
.DESCRIPTION
  <Brief description of script>
.PARAMETER <Parameter_Name>
    <Brief description of parameter input required. Repeat this attribute if required>
.INPUTS
  <Inputs if any, otherwise state None>
.OUTPUTS
  <Outputs if any, otherwise state None - example: Log file stored in C:\Windows\Temp\<name>.log>
.NOTES
  Version:        1.0
  Author:         <Name>
  Creation Date:  <Date>
  Purpose/Change: Initial script development
  
.EXAMPLE
  <Example goes here. Repeat this attribute for more than one example>
#>
<#----------------------------------------------------------[VARIABLE DECLARATIONS]----------------------------------------------------------#>


<#----------------------------------------------------------------[FUNCTIONS]----------------------------------------------------------------#>
Function Set-SwisConnection {  
    Param(  
        [Parameter(Mandatory=$true, HelpMessage = "What SolarWinds server are you connecting to (Hostname or IP)?" ) ] [string] $solarWindsServer,  
        [Parameter(Mandatory=$true, HelpMessage = "Do you want to use the credentials from PowerShell (Trusted), or a new login (Explicit)?" ) ] [ ValidateSet( 'Trusted', 'Explicit' ) ] [ string ] $connectionType,  
        [Parameter(HelpMessage = "Which credentials should we use for an explicit logon type" ) ] $creds
    )
    IF ( $connectionType -eq 'Trusted'  ) { $swis = Connect-Swis -Trusted -Hostname $solarWindsServer }
    ELSEIF(!$creds) {  
        $creds = Get-Credential -Message "Please provide a Domain or Local Login for SolarWinds"  
        $swis = Connect-Swis -Credential $creds -Hostname $solarWindsServer  
    } ELSE { $swis = Connect-Swis -Credential $creds -Hostname $solarWindsServer } 
    RETURN $swis  
}  



<#----------------------------------------------------------[START LOGGING]----------------------------------------------------------#>
clear-host

Start-Transcript -Path $Logfile -Append -IncludeInvocationHeader | Out-Null

if (!(Get-PSSnapin | Where-Object { $_.Name -eq "SwisSnapin" })) {
    Add-PSSnapin "SwisSnapin"
}

$now = Get-Date -Format "yyyyMMdd_HHmm"
$script = $MyInvocation.MyCommand
if($script.path){ $dir = Split-Path $script.path }
else { $dir = [Environment]::GetFolderPath("Desktop") }
$Logfile = "$dir\$($script.name)_$now.log"

<#----------------------------------------------------------[ORION CONNECTION]----------------------------------------------------------#>

while (!$swistest) {
    if(!$hostname) {
        $hostname = "localhost"
        $connectionType = "Trusted"
        $swis = Set-SwisConnection $hostname $connectionType
        $swistest = get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites" 
        if (!$swistest) {
            "`nFailed to connect to SWIS using $hostname address and $connectiontype credentials"
            $hostname = Read-Host -Prompt "what server should we connect to?" 
            $connectionType = Read-Host -Prompt "Should we use the current powershell credentials [Trusted], or specify credentials [Explicit]?" 
            $swis = Set-SwisConnection $hostname $connectionType
            $swistest = get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites" 
        }
    } else {
        $swistest = get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites"
        if (!$swistest) {
            "`nFailed to connect to SWIS using $hostname address and $connectiontype credentials"
            $hostname = Read-Host -Prompt "what server should we connect to?" 
            $connectionType = Read-Host -Prompt "Should we use the current powershell credentials [Trusted], or specify credentials [Explicit]?" 
            $swis = Set-SwisConnection $hostname $connectionType
            $swistest = get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites" 
        }
    }
}

$swistest = $null
"Connected to $hostname Successfully using $connectiontype credentials"


<#----------------------------------------------------------[BODY]----------------------------------------------------------#>









<#----------------------------------------------------------[POST SCRIPT]----------------------------------------------------------#>

"`n`nFinished"

Stop-Transcript
