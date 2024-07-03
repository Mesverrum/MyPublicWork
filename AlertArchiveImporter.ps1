#Requires -Modules pcsx

<#------------- FUNCTIONS -------------#>
Function Set-SwisConnection {
  Param(
      [Parameter(Mandatory=$true, HelpMessage = "What SolarWinds server are you connecting to (Hostname or IP)?" ) ] [string] $solarWindsServer,
      [Parameter(Mandatory=$true, HelpMessage = "Do you want to use the credentials from PowerShell [Trusted], or a new login [Explicit]?" ) ] [ ValidateSet( 'Trusted', 'Explicit' ) ] [ string ] $connectionType,
      [Parameter(HelpMessage = "Which credentials should we use for an explicit logon type" ) ] $creds
  )
  IF ( $connectionType -eq 'Trusted' ) {
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
try { $dir = Split-Path $script.path }
catch { }

$Logfile = "$dir\$($script.name)_$now.log"
Start-Transcript -Path $Logfile -Append -IncludeInvocationHeader | Out-Null

while(!$swistest) {
  $hostname = Read-Host -Prompt "what server should we connect to?"
  $connectionType = Read-Host -Prompt "Should we use the current powershell credentials [Trusted], or specify credentials [Explicit]?"
  $swis = Set-SwisConnection $hostname $connectionType
  $swistest = get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites"
}

"Connected to $hostname Successfully using $connectiontype credentials"

# set up path to current user desktop
$UserPath = "$($env:USERPROFILE)\Desktop\AlertExports\"

# get exported alerts from folder
$Alerts = (Get-ChildItem -Path $($UserPath+"\*.xml") -Recurse -Force).FullName

foreach ($Alert in $Alerts) {
   "Importing $Alert"
   $toDo = ([xml](get-content -Path $Alert)).return
   $result = Invoke-SwisVerb $swis Orion.AlertConfigurations Import $toDo
}

"Finished"
Stop-Transcript
