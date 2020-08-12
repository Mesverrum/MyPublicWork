#region Top of Script
#Requires -Module ImportExcel

<#
.SYNOPSIS
	Queries the New Relic API to audit alert policies and their associated NRQL alert conditions and notification channels
.DESCRIPTION
    https://docs.newrelic.com/docs/alerts/rest-api-alerts/new-relic-alerts-rest-api/rest-api-calls-new-relic-alerts
.INPUTS
    Various credentials to access New Relic subaccounts
.OUTPUTS
    Creates an output folder in the directory that the script runs from with timestamped .xlsx files each run.
.EXAMPLE
    .\nr_alertPolicyInventory.ps1 -AccountID '<accountid>' -AccountAPIKey '<AccountAPIKey>' -AdminUserAPIKey '<AdminUserAPIKey>' -QueryAPIKey '<QueryAPIKey>'
.NOTES
	Version:		1.0
	Author:			Zack Mutchler
	Creation Date:	02/15/2019
   	Purpose/Change:	Initial script development
	
    	Version:		1.1
	Author:			Zack Mutchler
	Creation Date:	05/02/2019
    	Purpose/Change:	Updated API Key variable definition
	
    	Version:		1.2
	Author:			Marc Netterfield
	Creation Date:	2020/08/12
    	Purpose/Change:	Added functions for all alert types
                    	Added export to excel capabilities
#>

#endregion Top of Script
#####-----------------------------------------------------------------------------------------#####
#region Script Parameters

Param (
    [ Parameter( Mandatory = $true ) ] [ ValidateNotNullOrEmpty() ] [ String ] $AccountID,
    [ Parameter( Mandatory = $true ) ] [ ValidateNotNullOrEmpty() ] [ String ] $AccountAPIKey,
    [ Parameter( Mandatory = $true ) ] [ ValidateNotNullOrEmpty() ] [ String ] $AdminUserAPIKey,
    [ Parameter( Mandatory = $true ) ] [ ValidateNotNullOrEmpty() ] [ String ] $QueryAPIKey
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
    Write-Host "`nQuerying Account for Policies at: $( $url )..." -ForegroundColor Yellow

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
        [ Parameter ( Mandatory = $true ) ] [ ValidateSet( 'APM', 'NRQL', 'External', 'Synthetics', 'Plugins' ) ] [ String ] $AlertType
    )

    # Set the target URI
    switch( $AlertType ) {
        'APM' { $uri = "https://api.newrelic.com/v2/alerts_conditions.json?policy_id=$PolicyID" }
        'NRQL' { $uri = "https://api.newrelic.com/v2/alerts_nrql_conditions.json?policy_id=$PolicyID" }
        'External' { $uri = "https://api.newrelic.com/v2/alerts_external_service_conditions.json?policy_id=$PolicyID" }
        'Synthetics' { $uri = "https://api.newrelic.com/v2/alerts_synthetics_conditions.json?policy_id=$PolicyID" }
        'Plugins' { $uri = "https://api.newrelic.com/v2/alerts_plugins_conditions.json?policy_id=$PolicyID" }
    }

    # Set the headers to pass
    $headers = @{
	    'X-Api-Key' = $AccountAPIKey;
	    'Content-Type' = 'application/json'
	}

    # Query the API
    $results = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers

    Return $results
}

Function Get-InfraConditions {
    Param (
        [ Parameter ( Mandatory = $true ) ] [ string ] $AdminUserAPIKey,
        [ Parameter ( Mandatory = $true ) ] [ int ] $PolicyID
    )

    # Set the target URI
    $uri = "https://infra-api.newrelic.com/v2/alerts/conditions?policy_id=$PolicyID"

    # Set the headers to pass
    $headers = @{
	    'X-Api-Key' = $AdminUserAPIKey;
	    'Content-Type' = 'application/json'
	}

    # Query the API
    $results = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers

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

#endregion Logging
#####-----------------------------------------------------------------------------------------#####
#region TLS Handling

add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

#endregion TLS handling
#####-----------------------------------------------------------------------------------------#####
#region Execution


Write-Host "`n`nREGION: Getting Notification Channels" -ForegroundColor Green

# Query the account's existing channels
$existingChannels = Get-NotificationChannels -AdminUserAPIKey $AdminUserAPIKey
Write-Host "`nFound $( $existingChannels.channels.Count ) total notification channels" -ForegroundColor Cyan


Write-Host "`n`nREGION: Getting Policies" -ForegroundColor Green

# Grab any existing policies in the account
try {
    $currentPolicies = Get-Policies -AccountAPIKey $AccountAPIKey | Select-Object -Property name,id,incident_preference,conditions,channels
    Write-Host "Found $( $currentPolicies.Count ) current policies in the sub-account`n" -ForegroundColor Cyan
} catch {
    $errorMessage = $_.Exception.Message
    Write-Host "FAILED TO QUERY CURRENT POLICIES`n$( $errorMessage )`n" -ForegroundColor Red
}


Write-Host "`n`nREGION: Getting Conditions" -ForegroundColor Green

$AlertTypes = ('APM', 'NRQL', 'External', 'Synthetics', 'Plugins')

# Find all existing conditions the policy
foreach( $policy in $currentPolicies ) {
    $ConditionList = [System.Collections.generic.list[object]]@()
        
    "`n $($policy.name) - $($policy.id)"

    # Everything except Infra uses the same format for requests so I have a single function for them all
    foreach( $alertType in $alertTypes ) {
        "  Getting $alertType conditions"
        $conditions = Get-Conditions -AccountAPIKey $AccountAPIKey -PolicyID $policy.id -AlertType $alertType 
        switch( $alertType ) {
            "APM" { 
                if( $conditions.conditions.count -gt 0 ) { "   Found $($conditions.conditions.count)"; $data = $conditions.conditions }
            }
            "NRQL" { 
                if( $conditions.nrql_conditions.count -gt 0 ) { "   Found $($conditions.nrql_conditions.count)"; $data = $conditions.nrql_conditions }
            }
            "External" { 
                if( $conditions.external_service_conditions.count -gt 0 ) { "   Found $($conditions.external_service_conditions.count)"; $data = $conditions.external_service_conditions }
            }
            "Synthetics" { 
                if( $conditions.synthetics_conditions.count -gt 0 ) { "   Found $($conditions.synthetics_conditions.count)"; $data = $conditions.synthetics_conditions }
            }
            "Plugins" { 
                if( $conditions.plugins_conditions.count -gt 0 ) { "   Found $($conditions.plugins_conditions.count)"; $data = $conditions.plugins_conditions }
            }
        }

        $ConditionList.add( $data )
    }
    
    # Since Infra is a snowflake it has to be handled separately
    "  Getting Infra conditions"
    $conditions = Get-InfraConditions -AdminUserAPIKey $AdminUserAPIKey -PolicyID $policy.id
    if( $conditions.data.count -gt 0 ) { "   Found $($conditions.data.count)"; $data = $conditions.data }
    $ConditionList.add( $conditions.data )

    $policy.conditions = $ConditionList
    
    $policy.channels = foreach( $channel in $existingChannels ) {
        if( $channel.links.policy_ids -contains $policy.id ) { $channel }
    }
}    
#endregion Execution
#####-----------------------------------------------------------------------------------------#####
#region Outputs

$script = ($MyInvocation.MyCommand)
if($script.Path){ $dir = (Split-Path $script.path) + "\outputs" }
else { $dir = ([Environment]::GetFolderPath("Desktop")) + "\outputs" }
if((test-path $dir) -eq $false) { mkdir -path $dir }
$Excelfile = "$dir\$($script.name)_$logTime.xlsx"

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
$outPolicies = foreach ( $p in $currentPolicies ) {
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
$outPolicies | Export-Excel $Excelfile -WorksheetName 'PoliciesAndConditions' -AutoSize -AutoFilter

#endregion Outputs
#####-----------------------------------------------------------------------------------------#####
#region Cleanup

"Completed"

$stopWatch.Stop()
Write-Host "Script duration: $( $stopWatch.Elapsed.Minutes ) min, $( $stopWatch.Elapsed.Seconds ) sec" -ForegroundColor Yellow

Stop-Transcript

#endregion Cleanup
