$orionhostname = "localhost"



<# This is one methos of storing secure credentials as files on the server#>

# Gather the necessary credentials from files
$tokenDir = ([Environment]::Getfolderpath("User")) + "\ScriptTokens"
if((test-path $tokenDir) -eq $false) { mkdir -path $tokenDir }

# Powershell Invoke-SqlCmd does not allow for specifying alternate accounts when using AD based logins to SQL, will pass through the cred of the current user
# Would be able to use specified SQL local accounts if desired
#$credTypes = ("OrionApi","SqlServer")

$credTypes = ("OrionApi","WMI")
foreach($credType in $credTypes) {
    $tokens = @( (Get-ChildItem -Path "$tokenDir/*" -filter "$($credType)_*").Name )
    # Check for existing token file, will only try to use the first file for each type
    if(($tokens[0].length) -eq 0) {
        if( $scriptMode -like "interactive*" ) {
            "Please provide a credential for $credType..."
            Start-Sleep -seconds 2
            $credential = get-credential
            $userCleanup = ($credential.UserName).replace('\','_')
            $credential.Password | ConvertFrom-SecureString | Set-Content -Path "$tokendir\$($credType)_$userCleanup"
        } else {
            "Missing credential file, run script interactively to create credential file"
        }
    } 
}

# populate credentials object
$creds = [pscustomobject]@{
    OrionApi = $null
    SqlServer = $null
    WMI = $null
}

foreach($credType in $credTypes) {
    $tokens = @( (Get-ChildItem -Path "$tokenDir/*" -filter "$($credType)_*").Name )
    # Check for existing token file
    if(($tokens[0].length) -ne 0) {
        # Found a matching credential file, will only use the first match per credType
        $tokenFile = "$tokenDir\$($tokens[0])"
        $credUser = [string]$tokens[0].replace("$($credType)_","").replace('_','\')
        
        [securestring]$tokenString = Get-Content $tokenFile | ConvertTo-SecureString 
        $cred = New-Object System.Management.Automation.PSCredential ($credUser, $tokenString)
        if( $credType -eq "OrionApi" ) { $creds.OrionApi = $cred }
        if( $credType -eq "SqlServer" ) { $creds.SqlServer = $cred }
        if( $credType -eq "WMI" ) { $creds.WMI = $cred }
    } 
}

# Only checking for the Orion creds since we use pass through AD creds for SQL
#if( $creds.OrionApi.GetType().Name -ne "PSCredential" -or $creds.SqlServer.GetType().Name -ne "PSCredential" ) {
# spot check that we have the necessary creds for Orion and SQL
if( $creds.OrionApi.GetType().Name -ne "PSCredential" ) {
    "Invalid Credential file, please review contents of $tokenDir"
    Stop-Transcript
    exit 1
}

# create a connection to the SolarWinds API
$swis = connect-swis -host $orionhostname -credential $($creds.OrionApi)
$swisTest =  get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites"

"Testing Connection to Orion"
if ( !$swisTest ) { 
    "Unable to connect to Orion server $orionhostname as $($creds.OrionApi.UserName)"
    Stop-Transcript
    exit 1
}

"Connected to $orionhostname successfully as $($creds.OrionApi.UserName)"

$credentialToChange = Get-SwisData $swis "SELECT ID, Name FROM Orion.Credential where Name = '$($creds.WMI.UserName)'"

$results = Invoke-SwisVerb $swis Orion.Credential UpdateUsernamePasswordCredentials @($($credentialToChange.Id), "$($creds.WMI.UserName)", "$($creds.WMI.UserName)", "($creds.WMI).GetNetworkCredential().Password" )

if( $results.nil -eq $true ) {
    "Credential successfully changed for $($creds.WMI.UserName)"
}