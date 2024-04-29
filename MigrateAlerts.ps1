<#------------- CONNECT TO SWIS -------------#>
#define old host, credentials, and sql connection string

$hostnameold = 'oldserver'
#$userold = "user"
#$passwordold = "pass"
# create a connection to the SolarWinds API
#$swissource = connect-swis -host $hostnameold -username $userold -password $passwordold -ignoresslerrors
$swissource = Connect-Swis -Hostname $hostnameold -Trusted

#define new host, credentials, no sql string is necessary
$hostnamenew = 'newserver'
#$usernew = "user"
#$passwordnew = "pass"
# create a connection to the SolarWinds API
#$swisdest = connect-swis -host $hostnamenew -username $usernew -password $passwordnew -ignoresslerrors
$swisdest = Connect-Swis -Hostname $hostnamenew -Trusted

<#------------- ACTUAL SCRIPT -------------#>

# get Alert IDs for enabled alerts
$AlertIDs = Get-SwisData -SwisConnection $swissource -Query "SELECT AlertID FROM Orion.AlertConfigurations WHERE Enabled = 'true' and name not like '%syslog%'"

# migrate the alerts
foreach ($AlertID in $AlertIDs) {
    $AlertName = Get-SwisData -SwisConnection $swissource -Query "SELECT Name FROM Orion.AlertConfigurations WHERE AlertID = $AlertID"
    $Existing = Get-SwisData -SwisConnection $swisdest "select name from orion.alertconfigurations where name = '$AlertName'"
    if ($existing.count -eq 0) { 
        write-output "Migrating alert named: $AlertName"
        $ExportedAlert = Invoke-SwisVerb $swissource Orion.AlertConfigurations Export $AlertID
        Invoke-SwisVerb $swisdest Orion.AlertConfigurations Import $ExportedAlert
    } else { 
        "Alert named: $AlertName already exists, skipping" 
    }
}
