#region Top of Script
#Requires -Module ImportExcel

<#
.SYNOPSIS
	Queries the New Relic API to audit alert policies and their associated NRQL alert conditions and notification channels
.DESCRIPTION
	https://docs.newrelic.com/docs/alerts/rest-api-alerts/new-relic-alerts-rest-api/rest-api-calls-new-relic-alerts
.OUTPUTS
	Creates an output folder in the directory that the script runs from with timestamped .xlsx files each run.
.EXAMPLE
	.\nr_alertPolicyInventory.ps1 -AccountAPIKey '<AccountAPIKey>' -AdminUserAPIKey '<AdminUserAPIKey>'
#>

#endregion Top of Script
#####-----------------------------------------------------------------------------------------#####
#region Script Parameters

Param (
    [ Parameter( Mandatory = $true ) ] [ String ] $AccountAPIKey,
    [ Parameter( Mandatory = $true ) ] [ String ] $AdminUserAPIKey
)

#endregion Script Parameters
#####-----------------------------------------------------------------------------------------#####
#region Functions

Function Get-Policies {
	Param (
		[ Parameter ( Mandatory = $true ) ] [ string ] $AccountAPIKey
	)

	# Set the target URL
	$url = "https://api.newrelic.com/v2/alerts_policies.json"

	# Set the headers to pass
	$headers = @{
		'X-Api-Key' = $AccountAPIKey
	}

	# Query the API
	$results = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -ContentType 'application/json' | Select-Object -ExpandProperty policies

	RETURN $results
}

Function Get-NotificationChannels {
	Param(
		[ Parameter ( Mandatory = $true ) ] [ string ] $AdminUserAPIKey
	)

	# Set the target URI
	$uri = 'https://api.newrelic.com/v2/alerts_channels.json'

	# Set the headers to pass
	$headers = @{
		'X-Api-Key' = $AdminUserAPIKey
	}

	# Post the new policy to the API
	$results = (Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ContentType 'application/json').channels

	RETURN $results
}

Function Get-Conditions {
	Param (
		[ Parameter ( Mandatory = $true ) ] [ string ] $AccountAPIKey,
		[ Parameter ( Mandatory = $true ) ] [ int ] $PolicyID,
		[ Parameter ( Mandatory = $true ) ] [ ValidateSet( 'APM', 'NRQL', 'External', 'Synthetics' ) ] [ String ] $AlertType
	)
	# Set the headers to pass
	$headers = @{
		'X-Api-Key' = $AccountAPIKey;
		'Content-Type' = 'application/json'
	}

	# Set the target URI
	switch( $AlertType ) {
		'APM' { 
			$uri = "https://api.newrelic.com/v2/alerts_conditions.json?policy_id=$PolicyID" 
			$results = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers 
			while( $results.conditions.count -ne $results.meta.total -and $null -ne $results.meta.total ) {
				$results.conditions += (Invoke-RestMethod -Method Get -Uri "https://api.newrelic.com/v2/alerts_conditions.json?offset=$($results.conditions.count)&policy_id=$PolicyID" -Headers $headers).conditions
			}
		}
		'NRQL' { 
			$uri = "https://api.newrelic.com/v2/alerts_nrql_conditions.json?policy_id=$PolicyID" 
			$results = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers 
			while( $results.nrql_conditions.count -ne $results.meta.total -and $null -ne $results.meta.total ) {
				$results.nrql_conditions += (Invoke-RestMethod -Method Get -Uri "https://api.newrelic.com/v2/alerts_nrql_conditions.json?offset=$($results.nrql_conditions.count)&policy_id=$PolicyID" -Headers $headers).nrql_conditions
			}
		}
		'External' { 
			$uri = "https://api.newrelic.com/v2/alerts_external_service_conditions.json?policy_id=$PolicyID" 
			$results = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers 
			while( $results.external_service_conditions.count -ne $results.meta.total -and $null -ne $results.meta.total ) {
				$results.external_service_conditions += (Invoke-RestMethod -Method Get -Uri "https://api.newrelic.com/v2/alerts_external_service_conditions.json?offset=$($results.external_service_conditions.count)&policy_id=$PolicyID" -Headers $headers).external_service_conditions
			}
		}
		'Synthetics' { 
			$uri = "https://api.newrelic.com/v2/alerts_synthetics_conditions.json?policy_id=$PolicyID" 
			$results = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers 
			while( $results.synthetics_conditions.count -ne $results.meta.total -and $null -ne $results.meta.total ) {
				$results.synthetics_conditions += (Invoke-RestMethod -Method Get -Uri "https://api.newrelic.com/v2/alerts_synthetics_conditions.json?offset=$($results.synthetics_conditions.count)&policy_id=$PolicyID" -Headers $headers).synthetics_conditions
			}
		}
	}
	# Query the API

	Return $results
}

Function Get-InfraConditions {
	Param(
		[ Parameter (Mandatory = $true ) ] [ string ] $AdminUserAPIKey,
		[ Parameter (Mandatory = $true ) ] [ int ] $PolicyID
	)
	# The NR Infrastructure API behaves differently than the other NR API's and has to be handled separately
	# Sub accounts created before Dec 2020 used an individual Admin User Key, after Dec they switched to creating a GraphiQL User key.
	# They decided to also change the required header type for those new accounts

	# Set the target URI
	$getInfraUri = 'https://infra-api.newrelic.com/v2/alerts/conditions?policy_id=' + $PolicyID

	if( $AdminUserAPIKey -like 'NRAK*' ) {
		# Set the headers to pass
		$headers = @{
			'Api-Key' = $AdminUserAPIKey;
			'Content-Type' = 'application/json'
		}
	} else {
		# Set the headers to pass
		$headers = @{
			'X-Api-Key' = $AdminUserAPIKey;
			'Content-Type' = 'application/json'
		}
	}

	# Query the API
	$results = Invoke-RestMethod -Method Get -Uri $getInfraUri -Headers $headers
	Return $results
}

#endregion Functions
#####-----------------------------------------------------------------------------------------#####
#region Logging

clear-host
$logTime = Get-Date -Format "yyyyMMdd_HHmm"
$script = ($MyInvocation.MyCommand)
if($script.Path){ $dir = (Split-Path $script.path) + "\logs" }
else { $dir = ([Environment]::GetFolderPath("Desktop")) + "\logs" }
if((test-path $dir) -eq $false) { mkdir -path $dir }
$Logfile = "$dir\$($script.name)_$logTime.log"
$removed = (get-ChildItem -Path "$dir").where{ $_.name -like "*.log" -and $_.LastWriteTime -lt (Get-Date).AddDays(-31) } 
$removed | Remove-Item
if( $removed ) {
	"Removed the following files:"
	$removed.name
}

Start-Transcript -Path $Logfile -Append -IncludeInvocationHeader

# Start the timer
$stopWatch = [ System.Diagnostics.Stopwatch ]::StartNew()
Write-Host "The stopwatch has started" -ForegroundColor Yellow

# Used to verify how code is being called, helpful debugging scripts and deciding if we can prompt the user for info, nesting it inside a function breaks the intended purpose
if( !$env:sessionname ) { 
	if( "${IP}" -eq "" ) { $scriptMode = 'TaskScheduler' } 
	else { $scriptMode = 'SAM Script' }
} else { 
	if( !$MyInvocation.MyCommand.Name ) { $scriptMode = "Ad Hoc code" } 
	else { $scriptMode = "Full execution from $($host.Name)" }
}
"Mode -> $scriptMode "

#endregion Logging
#####-----------------------------------------------------------------------------------------#####
#region TLS Handling

if ( "TrustAllCertsPolicy" -as [type] ) {} else {
	Add-Type "using System.Net;using System.Security.Cryptography.X509Certificates;
	public class TrustAllCertsPolicy : ICertificatePolicy {
		public bool CheckValidationResult(
			ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem
		) {return true;}
	}"
	$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
	[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
	[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

#endregion TLS handling
#####-----------------------------------------------------------------------------------------#####
#region Execution

Write-Host "`n`nREGION: Getting Notification Channels" -ForegroundColor Green
$existingChannels = Get-NotificationChannels -AdminUserAPIKey $AdminUserAPIKey
Write-Host "`nFound $( $existingChannels.channels.Count ) total notification channels" -ForegroundColor Cyan

Write-Host "`n`nREGION: Getting Policies" -ForegroundColor Green
try {
    $currentPolicies = Get-Policies -AccountAPIKey $AccountAPIKey | Select-Object -Property name,id,incident_preference,conditions,channels
    Write-Host "Found $( $currentPolicies.Count ) current policies in the sub-account`n" -ForegroundColor Cyan
} catch {
    $errorMessage = $_.Exception.Message
    Write-Host "FAILED TO QUERY CURRENT POLICIES`n$( $errorMessage )`n" -ForegroundColor Red
}

Write-Host "`n`nREGION: Getting Conditions" -ForegroundColor Green
$AlertTypes = ('APM', 'NRQL', 'External', 'Synthetics')
foreach( $policy in $currentPolicies ) {
    $ConditionList = [System.Collections.generic.list[object]]@()
    $data = $null

    "`n $($policy.name) - $($policy.id)"

    # Everything except Infra uses the same format for requests so I have a single function for them all
    foreach( $alertType in $alertTypes ) {
        "  Getting $alertType conditions"
        $conditions = $null
        $data = $null
        $conditions = Get-Conditions -AccountAPIKey $AccountAPIKey -PolicyID $policy.id -AlertType $alertType 
        switch( $alertType ) {
            "APM" { 
                if( $conditions.conditions ) { "   Found $($conditions.conditions.count)"; $data = $conditions.conditions }
            }
            "NRQL" { 
                if( $conditions.nrql_conditions ) { "   Found $($conditions.nrql_conditions.count)"; $data = $conditions.nrql_conditions }
            }
            "External" { 
                if( $conditions.external_service_conditions ) { "   Found $($conditions.external_service_conditions.count)"; $data = $conditions.external_service_conditions }
            }
            "Synthetics" { 
                if( $conditions.synthetics_conditions ) { "   Found $($conditions.synthetics_conditions.count)"; $data = $conditions.synthetics_conditions }
            }
        }

        if( $data ) { 
            foreach( $condition in $data ) {
                $ConditionList.add( $condition )
            }
        }
    }

    # Since Infra is a snowflake it has to be handled separately
    "  Getting Infra conditions"
    $infraConditions = Get-InfraConditions -AdminUserAPIKey $AdminUserAPIKey -PolicyID $policy.id
    if( $infraConditions.data ) { 
        "   Found $($infraConditions.data.count)"
        foreach( $condition in $infraConditions.data ) {
            $ConditionList.add( $condition )
        }
    }
    $policy.conditions = $ConditionList
    $policy.channels = foreach( $channel in $existingChannels ) {
        if( $channel.links.policy_ids -contains $policy.id ) { $channel }
    }
}

#endregion Execution
#####-----------------------------------------------------------------------------------------#####
#region Outputs

#dumping results to excel workbooks
if($script.Path){ $dir = (Split-Path $script.path) + "\outputs" }
else { $dir = ([Environment]::GetFolderPath("Desktop")) + "\outputs" }
if((test-path $dir) -eq $false) { mkdir -path $dir }
$Excelfile = "$dir\$($subName)_$($script.name)_$logTime.xlsx"

"Exporting to $Excelfile, this may take several minutes if there are a high number of conditions"

#output sheet of all notification channels
$outChannels = foreach ( $c in $existingChannels ) {
    [PSCustomObject]@{
        Name = $c.name
        ID = $c.id
        Type = $c.type
        Configuration = $c.Configuration
        AssignedPolicies = ( $c.links.policy_ids -join ', ')
    }
}
$outChannels | Export-Excel $Excelfile -WorksheetName 'NotificationChannels' -AutoSize -AutoFilter

#output sheet of all policies
$outPolicies = foreach( $p in $currentPolicies ) {
    foreach( $cond in $p.conditions ) {
        [PSCustomObject]@{
            PolicyName = $p.name
            PolicyPreference = $p.incident_preference
            ConditionName = $cond.Name
            EnabledName = $cond.Enabled
            ConditionDefinition = $cond | ConvertTo-Json -Depth 10
            NotificationChannels = ($p.channels.id -join ', '  ) 
        }
    } 
}
"$($outPolicies.count) conditions to export"
$outPolicies | Export-Excel $Excelfile -WorksheetName 'PoliciesAndConditions' -AutoSize -AutoFilter

#endregion Outputs
#####-----------------------------------------------------------------------------------------#####
#region Cleanup

"Completed"

$stopWatch.Stop()
Write-Host "Script duration: $( $stopWatch.Elapsed.Minutes ) min, $( $stopWatch.Elapsed.Seconds ) sec" -ForegroundColor Yellow

Stop-Transcript

#endregion Cleanup
