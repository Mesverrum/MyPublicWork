#region Top of Script
<#
.SYNOPSIS
    Takes process monitors from SolarWinds SAM templates and creates matching process alerts in New Relic Infrastructure.

.DESCRIPTION
    https://rpm.newrelic.com/api/explore
	
.EXAMPLE
    .\MigrateSamProcessMonitors.ps1 -AccountID 'accountID' -AccountAPIKey 'accountAPI' -AdminUserAPIKey 'adminAPI' -QueryApiKey 'queryAPI' -AssignmentGroup 'assignmentGroup' -OrionHostname 'servername'

.NOTES
    Version:        1.0
    Author:         Marc Netterfield
    Creation Date:  04/21/2020
    Purpose/Change: Initial Script development, based on 
    
    Version:        1.1
    Author:         Marc Netterfield
    Creation Date:  04/23/2020
    Purpose/Change: Addressed issues with NRQL queries being case sensitive

    Version:        1.2
    Author:         Marc Netterfield
    Creation Date:  05/11/2020
    Purpose/Change: Switched from using NRQL based alerts to using the infrastructure alerts API with a filter
                    instead of a where clause so it matches the style of user built alerts. This is also supposed 
                    to mitigate the problem of spamming for each process when an agent stops responding.
#>

#endregion Top of Script
#####-----------------------------------------------------------------------------------------#####
#region Script Parameters

Param (
    [ Parameter( Mandatory = $true ) ]  [ String ] $AccountID,
    [ Parameter( Mandatory = $true ) ]  [ String ] $AccountAPIKey,
    [ Parameter( Mandatory = $true ) ]  [ String ] $AdminUserAPIKey,
    [ Parameter( Mandatory = $true ) ]  [ String ] $QueryAPIKey,
    [ Parameter( Mandatory = $true ) ]  [ String ] $AssignmentGroup,
    [ Parameter( Mandatory = $true ) ]  [ String ] $OrionHostname
)

#endregion Script Parameters
#####-----------------------------------------------------------------------------------------#####
#region Functions

#region Set-SwisConnection
Function Set-SwisConnection {  
    Param(  
        [Parameter(Mandatory=$true, HelpMessage = "What SolarWinds server are you connecting to (Hostname or IP)?" ) ] [string] $solarWindsServer,  
        [Parameter(Mandatory=$true, HelpMessage = "Do you want to use the credentials from PowerShell [Trusted], or a new login [Explicit]?" ) ] [ ValidateSet( 'Trusted', 'Explicit' ) ] [ string ] $connectionType,  
        [Parameter(HelpMessage = "Which credentials should we use for an explicit logon type" ) ] [SecureString] $creds
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
#endregion Set-Swis-Connection

#region Get-Policies
# Create a function that queries an account for all defined Policies
Function Get-Policies {
    Param (
        [ Parameter ( Mandatory = $true ) ] [ string ] $AccountAPIKey
    )

    # Set the target URL
    $url = "https://api.newrelic.com/v2/alerts_policies.json"

    Write-Host "`nQuerying Account for Policies at: $( $url )..." -ForegroundColor Yellow

    # Set the headers to pass
    $headers = @{
        'X-Api-Key' = $AccountAPIKey
    }

    # Query the API
    $results = Invoke-RestMethod -Method Get  -Uri $url -Headers $headers -ContentType 'application/json' | Select-Object -ExpandProperty policies
    RETURN $results
}
#endregion Get-Policies

#region New-Policy

# Create a function that creates new Policies for an account
Function New-Policy {
    Param (
        [ Parameter ( Mandatory = $true ) ] [ string ] $AdminAPIKey,
        [ Parameter ( Mandatory = $true ) ] [ string ] $Policy,
        [ Parameter ( Mandatory = $true ) ] [ string ] $Body
    )

    # Set the target URL
    $url = "https://api.newrelic.com/v2/alerts_policies.json"

    # Set the headers to pass
    $headers = @{
        'X-Api-Key' = $AdminAPIKey
    }

    # Post the new policy to the API
    $results = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -ContentType 'application/json' -Body $Body
    RETURN $results
}
#endregion New-Policy

#region Get-NRQLCondition
# Create a function that lists all NRQL Conditions for a Policy
Function Get-NRQLCondition {
    Param(
        [ Parameter (Mandatory = $true ) ] [ string ] $AccountAPIKey,
        [ Parameter (Mandatory = $true ) ] [ int ] $PolicyID
    )

    # Set the target URI
    $getNrqlUri = 'https://api.newrelic.com/v2/alerts_nrql_conditions.json?policy_id=' + $PolicyID

    # Set the headers to pass
    $headers = @{
            'X-Api-Key' = $AccountAPIKey;
            'Content-Type' = 'application/json'
        }

    # Query the API
    $results = Invoke-RestMethod -Method Get  -Uri $getNrqlUri -Headers $headers
    Return $results
}
#endregion Get-NRQLCondition

#region Get-InfraCondition
# Create a function that lists all Infrastructure Conditions for a Policy
Function Get-InfraCondition {
    Param(
        [ Parameter (Mandatory = $true ) ] [ string ] $AdminUserAPIKey,
        [ Parameter (Mandatory = $true ) ] [ int ] $PolicyID
    )

    # Set the target URI
    $getInfraUri = 'https://infra-api.newrelic.com/v2/alerts/conditions?policy_id' + $PolicyID

    # Set the headers to pass
    $headers = @{
            'X-Api-Key' = $AdminUserAPIKey;
            'Content-Type' = 'application/json'
        }

    # Query the API
    $results = Invoke-RestMethod -Method Get  -Uri $getInfraUri -Headers $headers
    Return $results
}
#endregion Get-InfraCondition

#region New-NRQLCondition
# Create a function that creates a new NRQL Condition for a Policy
Function New-NRQLCondition {
    Param(
        [ Parameter (Mandatory = $true ) ] [ string ] $AdminAPIKey,
        [ Parameter (Mandatory = $true ) ] [ int ] $PolicyID,
        [ Parameter (Mandatory = $true ) ] [ string ] $Payload
    )

    # Set the target URI
    $newNrqlUri = 'https://api.newrelic.com/v2/alerts_nrql_conditions/policies/' + $PolicyID + '.json'

    # Set the headers to pass
    $headers = @{
            'X-Api-Key' = $AdminAPIKey;
            'Content-Type' = 'application/json'
        }

    # Query the API
    $results = Invoke-RestMethod -Method Post -Uri $newNrqlUri -Headers $headers -Body $Payload
    Return $results
}
#endregion New-NRQLCondition

#region New-InfraCondition
# Create a function that creates a new NRQL Condition for a Policy
Function New-InfraCondition {
    Param(
        [ Parameter (Mandatory = $true ) ] [ string ] $AdminAPIKey,
        [ Parameter (Mandatory = $true ) ] [ int ] $PolicyID,
        [ Parameter (Mandatory = $true ) ] [ string ] $Payload
    )

    # Set the target URI
    $newInfraUri = 'https://infra-api.newrelic.com/v2/alerts/conditions'

    # Set the headers to pass
    $headers = @{
            'X-Api-Key' = $AdminAPIKey;
            'Content-Type' = 'application/json'
        }

    # Query the API
    $results = Invoke-RestMethod -Method Post -Uri $newInfraUri -Headers $headers -Body $Payload
    Return $results
}
#endregion New-InfraCondition

#region Get-NRHostnames
# Create a function that queries all hostnames in an account
Function Get-NRHostnames {
    Param(
        [ Parameter (Mandatory = $true ) ] [ string ] $AccountID,
        [ Parameter (Mandatory = $true ) ] [ string ] $QueryKey
    )

    # Set the target URI
    $getNrqlUri = "https://insights-api.newrelic.com/v1/accounts/$accountID/query?nrql=SELECT uniques(hostname) FROM SystemSample LIMIT 1000 "

    Write-Host "Finding all Hostnames for Account: $( $AccountID )" -ForegroundColor Yellow

    # Set the headers to pass
    $headers = @{
        'X-Query-Key' = $QueryKey;
        'Content-Type' = 'application/json'
    }

    # Query the NRQL API and return hostnames without fqdn
    $results = ( Invoke-RestMethod -Method Get  -Uri $getNrqlUri -Headers $headers | Select-Object -ExpandProperty results).members | Sort-Object | ForEach-Object { $_.Substring($_.IndexOf(".") + 1) }
    Return $results
}
#endregion Get-NRHostnames



#endregion Functions
#####-----------------------------------------------------------------------------------------#####
#region Pre-Work

# Set the output file location
$outputFile = "C:\Scripts\_outputFiles\MigrateSAMProcessesToNR_" + $( $AccountID ) + "_" + ( Get-Date -Format MM-dd-yyyy_HHmm ) + ".log"

# Start the transcript
Start-Transcript -Path $outputFile -Force

# Start the timer
$stopWatch = [ System.Diagnostics.Stopwatch ]::StartNew()
Write-Host "The stopwatch has started" -ForegroundColor Yellow

#endregion Pre-Work
#####-----------------------------------------------------------------------------------------#####
#region get hosts from New Relic
$hostnames = get-nrhostnames $accountid $queryapikey
$hostsString = "'" + ($hostnames -join "','") + "'"

#region Connect to SWIS
while(!$swistest) {
    $hostname = $OrionHostname #Read-Host -Prompt "What server should we connect to?" 
    # To simplify my life I just run the script under a domain account that has admin rights in Orion and passes them through
    $connectionType = "trusted" #Read-Host -Prompt "Should we use the current powershell credentials [Trusted], or specify credentials [Explicit]?" 
    $swis = Set-SwisConnection $hostname $connectionType
    $swistest = get-swisdata $swis "SELECT TOP 1 servername FROM Orion.Websites" 
}

"Connected to $hostname Successfully using $connectiontype credentials"
$swistest = $null
#endregion Connect to SWIS

"Checking Orion for Solarwinds matches"
$nodes = get-swisdata $swis "select nodeid, caption from orion.nodes where caption in ( $hostsString )"
#$nodeString = "'" + ($nodes.caption -join "','") + "'"
$nodeIdString = ($nodes.nodeid -join ",")

"$($nodes.count) matches found in Solarwinds out of $($hostnames.count) hosts in New Relic Account"

" Matched results:"
$nodes.caption

#region Create Default Alert Policies
Write-Host "`n`nREGION: Create Default Policies" -ForegroundColor Green

# Grab any existing policies in the account
try {
    $currentPolicies = Get-Policies -AccountAPIKey $AccountAPIKey
    Write-Host "Found $( $currentPolicies.Count ) current policies in the sub-account`n" -ForegroundColor Cyan
} catch {
    $errorMessage = $_.Exception.Message
    Write-Host "FAILED TO QUERY CURRENT POLICIES`n$( $errorMessage )`n" -ForegroundColor Red
}

# Build an array of the new policy names
# These policy naming conventions are pretty strict in our environment as they feed into some other automations we use in our event platform
$appTeamProcess = $AssignmentGroup + ':INF:RS1:E:APP-PROCESS'

$verifyPolicies = @()
$verifyPolicies += $appTeamProcess

# Find the policies that don't already exist
$deltaPolicies = $verifyPolicies | Where-Object { $currentPolicies.name -notcontains $_ }

# Iterate through the Delta (missing) policies and create new ones
foreach ( $d in $deltaPolicies ) {
	# $appTeamProcess Policy
    if ( $d -eq $appTeamProcess ) {
        $body=@"
            {
                "policy": {
                    "incident_preference": "PER_CONDITION_AND_TARGET",
                    "name": "$appTeamProcess"
                }
            }
"@

        try {
            $appTeamProcessResults = New-Policy -AdminAPIKey $AdminUserAPIKey -Policy "$appTeamProcess" -Body $body
            Write-Host "Created $( $appTeamProcessResults.policy.name ), using $( $appTeamProcessResults.policy.incident_preference ) with ID: $( $appTeamProcessResults.policy.id )"

        }

        catch {
            $errorMessage = $_.Exception.Message
            Write-Host "FAILED TO CREATE POLICY: $( $appTeamProcess )`n$( $errorMessage )" -ForegroundColor Red
        }
    }
}

# Find the policies that we end up with
$matchingPolicies = Get-Policies -AccountAPIKey $AccountAPIKey

# Create an empty array to hold our results
$alertPolicies = @()

# Iterate through the Matching (pre-existing) policies and grab some details for use later
foreach ( $m in $matchingPolicies ) {
	# $appTeamProcess Policy
	if ( $m.name -ieq $appTeamProcess ) {
		# Add this policy to our array
		$alertPolicies += [ pscustomobject ]@{ id = $m.id; name = $m.name; preference = $m.incident_preference }
    }
}

# Show the policies found that match up
$createdString = $alertPolicies.name -join "`n`t"
Write-Host "POLICIES:`n`t$( $createdString )"

#endregion Create Default Alert Policies
#####-----------------------------------------------------------------------------------------#####
#region Create $appTeamProcess Condition Payloads

Write-Host "`n`nREGION: Create $( $appTeamProcess ) Payloads" -ForegroundColor Green

# this query is full of case logic that is driven by our internal policies, much of it wouldn't apply outside our team
$orionProcessList = get-swisdata $swis @"
SELECT 
processname
, displayname
, vendor
, prodstate
, alertdelay
, alertseverity
, shortname
, concat('SELECT count(processDisplayName) FROM ProcessSample FACET entityName WHERE processDisplayName LIKE ''',processname,''' AND operatingSystem = ''',vendor,''' AND entityName LIKE ''', SUBSTRING(nodeName,1,2),'%') as Q
, 'NR_Proc_'+displayname+'_'+prodstate+'_'+tostring(Alertdelay)+'m_'+substring(alertSeverity,1,1) as RuleName
, concat(case when vendor='Windows' then 'w' when vendor='linux' then 'l' end, case when prodstate='Prod' then 'p' when prodstate='stage' then 's' end) as hostfilter
FROM  (
SELECT distinct 
case when isnull(n.customproperties.prod_state,'') != '' then n.customproperties.prod_state
when n.caption like '_p______%' then 'Prod'
when n.caption like '_s______%' then 'Stage'
else 'Unknown' 
end as prodState
, case when n.Vendor = 'windows' then 'windows'
    when n.vendor in ('net-snmp','linux') then 'linux'
    else n.Vendor end as Vendor
, n.Caption AS [nodeName]
, case when substring(caption,5,4) < 'a' and (caption like 'lp%' or caption like 'ls%' or caption like 'wp%' or caption like 'ws%')
    then substring(caption, 9,100) 
    else caption
    end as shortName
, case when isnull(a.customproperties.a_sn_App_Name,'') != '' then a.customproperties.a_sn_App_Name
else a.Name 
end AS [appName]
, replace(replace(case when cd.name = 'Windows Service Monitor' then ca.ProcessName
else ISNULL( cs1.Value, cts1.Value ) end,'.exe',''),'.','') AS [displayname]
, tolower(case when cd.name = 'Windows Service Monitor' then ca.ProcessName
else ISNULL( cs1.Value, cts1.Value ) end ) as processName
, c.ComponentID
, c.name
, ISNULL( cs2.Value, cts2.Value ) AS [cliFilter]
, isnull(a.CustomProperties.alert_a_ComponentCritDown, a.CustomProperties.alert_a_MonitorCritDown) as AlertCritDown
, isnull(a.CustomProperties.alert_a_ComponentCritDown_Delay, a.CustomProperties.alert_a_MonitorCritDown_Delay) as AlertDelay
, isnull(a.CustomProperties.alert_a_ComponentCritDown_Severity, a.CustomProperties.alert_a_MonitorCritDown_Severity) as AlertSeverity
FROM orion.nodes n
join Orion.APM.Application a on a.nodeid=n.nodeid and (a.CustomProperties.alert_a_MonitorCritDown = true or a.CustomProperties.alert_a_ComponentCritDown = true)
join Orion.APM.Component c on a.applicationid = c.ApplicationID and c.ComponentType IN (1,8,9,46) and c.name not in ('newrelic-infra.exe','BESClient') and c.Disabled = 0 
join Orion.APM.ComponentDefinition cd on cd.ComponentType=c.componenttype
left join orion.apm.ComponentAlert ca on ca.ComponentID=c.ComponentID
LEFT JOIN Orion.APM.ComponentSetting AS [cs1] ON cs1.ComponentID = c.ComponentID AND cs1.Key in ('ServiceName','ProcessName')
LEFT JOIN Orion.APM.ComponentSetting AS [cs2] ON cs2.ComponentID = c.ComponentID AND cs2.Key = 'CommandLineFilter'
LEFT JOIN Orion.APM.ComponentTemplateSetting AS [cts1] ON cts1.ComponentTemplateID = c.TemplateID AND cts1.Key in ('ServiceName','ProcessName')
LEFT JOIN Orion.APM.ComponentTemplateSetting AS [cts2] ON cts2.ComponentTemplateID = c.TemplateID AND cts2.Key = 'CommandLineFilter'
where isnull(replace(replace(case when cd.name = 'Windows Service Monitor' then ca.ProcessName
else ISNULL( cs1.Value, cts1.Value ) end,'.exe',''),'.',''),'') != ''
and n.nodeid in (
$nodeIdString
)
and (a.CustomProperties.alert_a_MonitorCritDown = true or a.CustomProperties.alert_a_ComponentCritDown = true)
) procmon
where prodstate in ('stage','prod')
ORDER BY [q], [processName], [vendor], [prodstate], AlertDelay, AlertSeverity
"@

# Build and empty array to hold our payloads
$appProcessPayloads = $null
$appProcessPayloads = [System.Collections.ArrayList]@()

foreach($rule in $orionProcessList.ruleName | get-unique) {
    $orionProcessDetails = $orionProcessList | Where-Object { $_.ruleName -eq $rule }
    $arr =  @($orionProcessDetails.shortname)
    $nameFilter = $arr | ForEach-Object{
        $substr = for ($s = 0; $s -lt $_.length; $s++) {
            for ($l = 1; $l -le ($_.length - $s); $l++) {
                $_.substring($s, $l);
            }
        } 
        $substr | ForEach-Object{$_.toLower()} | Select-Object -unique
    } | Group-Object | where-object {$_.count -eq $arr.length} | sort-object {$_.name.length} | Select-Object -expand name -l 1

    $ruleName = ($orionProcessDetails.RuleName | get-unique)
    $ruleDelay = ($orionProcessDetails.alertDelay | get-unique)
    #$ruleSeverity = ($orionProcessDetails.alertSeverity | get-unique)
    #$ruleQuery = (($orionProcessDetails.q | get-unique)+$nameFilter+"%'")
    $ruleProcessName = ($orionProcessDetails.processName | get-unique)
    $ruleHostFilter = ($orionProcessDetails.hostFilter | get-unique)
    

    Write-Host "Creating payload for: $ruleName"
    
#    $rulePayload = @"
#{
#"nrql_condition": {
#"name": "$ruleName",
#"runbook_url": "https://wiki.cardinalhealth.net/New_Relic/Alerts",
#"violation_time_limit_seconds": 86400,
#"enabled": true,
#"terms": [
#    {
#    "duration": "$ruleDelay",
#    "operator": "equal",
#    "priority": "critical",
#    "threshold": "0",
#    "time_function": "all"
#    }
#],
#"value_function": "single_value",
#"nrql": {
#    "query": "$ruleQuery",
#    "since_value": "3"
#}
#}
#}
#"@
#    $fullPayload = [PSCustomObject]@{name = $ruleName; payload = $rulePayload}
#    $appProcessPayloads.Add($fullPayload) | Out-Null

    $rulePayload = @"
{
   "data":{
        "type":  "infra_process_running",
        "name":  "$ruleName",
        "runbook_url": "https://wiki.cardinalhealth.net/New_Relic/Alerts",
        "enabled":  true,
        "filter":  {
                       "and":  [
                                   {
                                       "like":  {
                                                    "displayName":  "$nameFilter"
                                                }
                                   },
                                   {     
                                       "like":  {
                                                    "entityName":  "$ruleHostFilter"
                                                }
                                   }
                               ]
                   },
        "policy_id":$($alertPolicies.id),
        "comparison":  "equal",
        "critical_threshold":  {
                                   "value":  0,
                                   "duration_minutes":  $ruleDelay
                               },
        "process_filter":  {
                               "and":  [
                                           {
                                               "like":  {
                                                          "processDisplayName":  "$ruleProcessName"
                                                      }
                                           }
                                       ]
                           }
    }
}
"@

    $fullPayload = [PSCustomObject]@{name = $ruleName; payload = $rulePayload}
    $appProcessPayloads.Add($fullPayload) | Out-Null
}

#endregion Create $appTeamProcess Condition Payloads
#####-----------------------------------------------------------------------------------------#####
#region Get all Existing Conditions

Write-Host "`n`nREGION: Get all Existing Conditions" -ForegroundColor Green

# Iterate through the Alert Policies and grab their conditions
#foreach ( $a in $alertPolicies ) {
#	# $appTeamProcess Policy
#	if ( $a.name -ieq $appTeamProcess ) {
#		# Query the Policy ID for all pre-existing Conditions
#		$appProcessConditions = Get-NRQLCondition -AccountAPIKey $AccountAPIKey -PolicyID $a.id
#		Write-Host "Found $( $appProcessConditions.nrql_conditions.Count ) pre-existing conditions in $( $a.name )" -ForegroundColor Cyan
#	}
#}

# Iterate through the Alert Policies and grab their conditions
foreach ( $a in $alertPolicies ) {
	# $appTeamProcess Policy
	if ( $a.name -ieq $appTeamProcess ) {
		# Query the Policy ID for all pre-existing Conditions
		$appProcessConditions = (Get-InfraCondition -AdminUserAPIKey $AdminUserAPIKey -PolicyID $a.id).data | where-object { $_.type -eq "infra_process_running" }
		Write-Host "Found $( $appProcessConditions.Count ) pre-existing conditions in $( $a.name )" -ForegroundColor Cyan
	}
}

#endregion Get all Existing Conditions
#####-----------------------------------------------------------------------------------------#####
#region Create App Team Alerts

Write-Host "`n`nREGION: Create App Team Alerts" -ForegroundColor Green

# Grab the App Team Process Policy
$appProcessPolicy = $alertPolicies | Where-Object { $_.name -ieq  $appTeamProcess }
Write-Host "Creating App Team Process Alerts for $( $appProcessPolicy.name ), ID: $( $appProcessPolicy.id )"

foreach ( $pay in $appProcessPayloads ) {
    if( $pay.name -notin $appProcessConditions.name ) {
        # Checks for an empty array. If empty, attempts to create
        # If NOT EMPTY, first check to see if the new conditions exists in the array.  If not, attempt to create
        if ( $appProcessConditions.Length -eq 0 ) {
            # Create alerts
		    try {
			    # Create alerts
			    Write-Host "Creating $( $pay.name )..." -ForegroundColor Cyan
			    New-InfraCondition -AdminAPIKey $AdminUserAPIKey -PolicyID $appProcessPolicy.id -Payload $pay.payload -ErrorAction Stop | Out-Null
		    }

		    catch {
			    $errorMessage = $_.Exception.Message
			    Write-Host "FAILED TO CREATE CONDITION: $( $pay.name ) IN POLICY: $( $appProcessPolicy.id )`n$( $ErrorMessage )`n" -ForegroundColor Red
		    }
        } else {
            try {
                # Create alert
                Write-Host "Creating $( $pay.name )..." -ForegroundColor Cyan
                New-InfraCondition -AdminAPIKey $AdminUserAPIKey -PolicyID $appProcessPolicy.id -Payload $pay.payload -ErrorAction Stop | Out-Null
            }

            catch {
                $errorMessage = $_.Exception.Message
                Write-Host "FAILED TO CREATE CONDITION: $( $pay.name ) IN POLICY: $( $appProcessPolicy.id )`n$( $ErrorMessage )`n" -ForegroundColor Red
            }
        }
    } else {
        if ( $appProcessConditions.name.Contains( $pay.name ) ) {
            Write-Host "Condition $( $pay.name ) already exists. Skipping..."
        }
    }
}

#endregion Create App Team Alerts
#####-----------------------------------------------------------------------------------------#####
#region Cleanup

# Stop the clock and show us how long this took
$stopWatch.Stop()

Write-Host "SCRIPT DURATION:`n  HOURS: $( $stopWatch.Elapsed.Hours )`n  MINUTES: $( $stopWatch.Elapsed.Minutes )`n  SECONDS: $( $stopWatch.Elapsed.Seconds )" -ForegroundColor Yellow

#Stop the transcript recording
Stop-Transcript

#endregion Cleanup
