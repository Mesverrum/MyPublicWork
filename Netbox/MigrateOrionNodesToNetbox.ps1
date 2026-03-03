# Generated via LLM, note this has not been testing yet but passes my initial sniff test.
# Running Variables - You may need to change these
$orionHostname  = '1.2.3.4'
$netboxHostname = 'netbox.example.com'   # NetBox FQDN or IP
$netboxSite     = 'Default'              # NetBox site name to assign devices to (must already exist)
$netboxRole     = 'Unknown'              # NetBox device role to assign (must already exist)
$netboxManufacturer = 'Unknown'          # NetBox manufacturer (must already exist)
$netboxDeviceType   = 'Generic'          # NetBox device type model name (must already exist)

#####-----------------------------------------------------------------------------------------#####
#region Logging

Clear-Host
$logTime = Get-Date -Format "yyyyMMdd_HHmm"
$script = ($MyInvocation.MyCommand)
if ($script.Path) { $dir = (Split-Path $script.Path) + "\logs" }
else { $dir = ([Environment]::GetFolderPath("Desktop")) + "\logs" }
if ((Test-Path $dir) -eq $false) { mkdir -Path $dir }
$Logfile = "$dir\$($script.name)_$logTime.log"
$removed = (Get-ChildItem -Path "$dir").Where{ $_.Name -like "*.log" -and $_.LastWriteTime -lt (Get-Date).AddDays(-31) }
$removed | Remove-Item
if ($removed) {
    "Removed the following files:"
    $removed.Name
}

Start-Transcript -Path $Logfile -Append -IncludeInvocationHeader

$stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "The stopwatch has started" -ForegroundColor Yellow

if (!$env:sessionname) {
    if ("${IP}" -eq "") { $scriptMode = 'TaskScheduler' }
    else { $scriptMode = 'SAM Script' }
} else {
    if (!$MyInvocation.MyCommand.Name) { $scriptMode = "Interactive - Ad hoc code" }
    else { $scriptMode = "Interactive - Full execution from $($host.Name)" }
}
"Mode -> $scriptMode"

#endregion Logging
#####-----------------------------------------------------------------------------------------#####
#region Connections

# Ignore SSL errors
if (!([System.Net.ServicePointManager]::CertificatePolicy -like "TrustAllCertsPolicy")) {
    Add-Type @"
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
}

# Gather credentials from token files
$tokenDir = ([Environment]::GetFolderPath("User")) + "\ScriptTokens"
if ((Test-Path $tokenDir) -eq $false) { mkdir -Path $tokenDir }

# OrionApi  - username/password credential stored as SecureString file
# NetboxApi - API token stored as SecureString file (store the raw token as the "password", username can be anything e.g. "token")
$credTypes = @("OrionApi", "NetboxApi")

foreach ($credType in $credTypes) {
    $tokens = @( (Get-ChildItem -Path "$tokenDir/*" -Filter "$($credType)_*").Name )
    if (($tokens[0].Length) -eq 0) {
        if ($scriptMode -like "interactive*") {
            "Please provide a credential for $credType..."
            "  For NetboxApi: enter anything as the username and your NetBox API token as the password."
            Start-Sleep -Seconds 2
            $credential = Get-Credential
            $userCleanup = ($credential.UserName).Replace('\', '_')
            $credential.Password | ConvertFrom-SecureString | Set-Content -Path "$tokenDir\$($credType)_$userCleanup"
        } else {
            "Missing credential file for $credType - run script interactively to create credential file"
        }
    }
}

$creds = [pscustomobject]@{
    OrionApi  = $null
    NetboxApi = $null
}

foreach ($credType in $credTypes) {
    $tokens = @( (Get-ChildItem -Path "$tokenDir/*" -Filter "$($credType)_*").Name )
    if (($tokens[0].Length) -ne 0) {
        $tokenFile = "$tokenDir\$($tokens[0])"
        $credUser  = [string]$tokens[0].Replace("$($credType)_", "").Replace('_', '\')
        [securestring]$tokenString = Get-Content $tokenFile | ConvertTo-SecureString
        $cred = New-Object System.Management.Automation.PSCredential ($credUser, $tokenString)
        if ($credType -eq "OrionApi")  { $creds.OrionApi  = $cred }
        if ($credType -eq "NetboxApi") { $creds.NetboxApi = $cred }
    }
}

if ($creds.OrionApi.GetType().Name -ne "PSCredential" -or $creds.NetboxApi.GetType().Name -ne "PSCredential") {
    "Invalid or missing credential files. Please review contents of $tokenDir"
    Stop-Transcript
    exit 1
}

# Connect to SolarWinds SWIS
$swis = Connect-Swis -Host $orionHostname -Credential $creds.OrionApi
$swisTest = Get-SwisData $swis "SELECT TOP 1 servername FROM Orion.Websites"

"Testing Connection to Orion..."
if (!$swisTest) {
    "Unable to connect to Orion server $orionHostname as $($creds.OrionApi.UserName)"
    Stop-Transcript
    exit 1
}
"Connected to $orionHostname successfully as $($creds.OrionApi.UserName)"

# Build NetBox API headers using the stored token (password field of the credential)
$netboxToken   = $creds.NetboxApi.GetNetworkCredential().Password
$netboxHeaders = @{
    Authorization  = "Token $netboxToken"
    "Content-Type" = "application/json"
    Accept         = "application/json"
}
$netboxBaseUrl = "https://$netboxHostname/api"

# Verify NetBox connectivity
"Testing Connection to NetBox..."
try {
    $netboxTest = Invoke-RestMethod -Uri "$netboxBaseUrl/status/" -Headers $netboxHeaders -Method Get
    "Connected to NetBox $($netboxTest.netbox_version) at $netboxHostname"
} catch {
    "Unable to connect to NetBox at $netboxHostname : $_"
    Stop-Transcript
    exit 1
}

#endregion Connections
#####-----------------------------------------------------------------------------------------#####
#region Helper Functions

function Get-NetboxObjectId {
    <#
    .SYNOPSIS
        Look up the numeric ID of a NetBox object by name from a given endpoint.
    #>
    param(
        [string]$Endpoint,   # e.g. "dcim/sites"
        [string]$Name
    )
    $uri    = "$netboxBaseUrl/$Endpoint/?name=$([uri]::EscapeDataString($Name))&limit=1"
    $result = Invoke-RestMethod -Uri $uri -Headers $netboxHeaders -Method Get
    if ($result.count -gt 0) { return $result.results[0].id }
    return $null
}

function Get-OrCreateNetboxId {
    <#
    .SYNOPSIS
        Return the ID of a NetBox object, creating it first if it does not exist.
    .NOTES
        Only covers the simple objects needed here (site, role, manufacturer, device-type).
        Extend $createBody per endpoint as needed.
    #>
    param(
        [string]$Endpoint,
        [string]$Name,
        [hashtable]$ExtraFields = @{}
    )
    $id = Get-NetboxObjectId -Endpoint $Endpoint -Name $Name
    if ($id) { return $id }

    "  NetBox object '$Name' not found at $Endpoint - creating..."
    $body = @{ name = $Name; slug = ($Name -replace '[^a-zA-Z0-9]', '-').ToLower() } + $ExtraFields
    $response = Invoke-RestMethod -Uri "$netboxBaseUrl/$Endpoint/" -Headers $netboxHeaders -Method Post -Body ($body | ConvertTo-Json -Depth 5)
    return $response.id
}

#endregion Helper Functions
#####-----------------------------------------------------------------------------------------#####
#region Execution

# Discover all defined node custom properties
"Querying SolarWinds for node custom property definitions..."
$customPropFields = Get-SwisData $swis @"
SELECT Field, Description, DataType
FROM Orion.CustomProperty
WHERE TargetEntity = 'Orion.NodesCustomProperties'
ORDER BY Field
"@
"Found $($customPropFields.Count) custom properties: $($customPropFields.Field -join ', ')"

# Build dynamic SELECT list - each custom property referenced via dot notation
$baseColumns = @(
    "n.NodeID",
    "n.Caption",
    "n.IPAddress",
    "n.DNS",
    "n.SysName",
    "n.Vendor",
    "n.MachineType",
    "n.NodeDescription",
    "n.Status",
    "n.EngineID"
)
$customColumns = $customPropFields | ForEach-Object { "n.CustomProperties.$($_.Field)" }
$selectList = ($baseColumns + $customColumns) -join ",`n    "

# Query SolarWinds for all managed nodes including custom properties
"Querying SolarWinds for nodes..."
$query = @"
SELECT
    $selectList
FROM Orion.Nodes n
WHERE n.ObjectSubType != 'Agent'
ORDER BY n.Caption
"@

$nodes = Get-SwisData $swis $query
"Found $($nodes.Count) nodes in SolarWinds"

# Resolve NetBox lookup IDs once (avoids repeated API calls per device)
"Resolving NetBox reference IDs..."
$siteId         = Get-OrCreateNetboxId -Endpoint "dcim/sites"         -Name $netboxSite
$roleId         = Get-OrCreateNetboxId -Endpoint "dcim/device-roles"  -Name $netboxRole
$manufacturerId = Get-OrCreateNetboxId -Endpoint "dcim/manufacturers" -Name $netboxManufacturer
$deviceTypeId   = Get-OrCreateNetboxId -Endpoint "dcim/device-types"  -Name $netboxDeviceType `
                    -ExtraFields @{ manufacturer = $manufacturerId }

if (!$siteId -or !$roleId -or !$manufacturerId -or !$deviceTypeId) {
    "Failed to resolve one or more required NetBox reference objects. Aborting."
    Stop-Transcript
    exit 1
}

# Retrieve existing NetBox devices keyed by name for duplicate checking
"Fetching existing NetBox devices..."
$existingDevices = @{}
$nbUrl = "$netboxBaseUrl/dcim/devices/?limit=1000"
do {
    $page = Invoke-RestMethod -Uri $nbUrl -Headers $netboxHeaders -Method Get
    foreach ($d in $page.results) { $existingDevices[$d.name] = $d.id }
    $nbUrl = $page.next
} while ($nbUrl)
"Found $($existingDevices.Count) existing devices in NetBox"

# Sync nodes into NetBox
$created = 0
$skipped = 0
$errors  = 0

foreach ($node in $nodes) {
    $deviceName = if ($node.Caption) { $node.Caption } else { $node.IPAddress }

    # Truncate comments to 200 chars (NetBox field limit)
    $comments = if ($node.NodeDescription) { $node.NodeDescription.Substring(0, [Math]::Min(200, $node.NodeDescription.Length)) } else { "" }

    if ($existingDevices.ContainsKey($deviceName)) {
        "  SKIP  : $deviceName already exists in NetBox (ID $($existingDevices[$deviceName]))"
        $skipped++
        continue
    }

    # Build custom_fields: fixed SW fields + all dynamic custom properties
    $customFields = @{
        sw_node_id  = [string]$node.NodeID
        sw_vendor   = $node.Vendor
        sw_sysdescr = $node.MachineType
    }
    foreach ($prop in $customPropFields) {
        $fieldName  = "sw_cp_$($prop.Field.ToLower() -replace '[^a-z0-9]','_')"
        $fieldValue = $node."$($prop.Field)"
        if ($null -ne $fieldValue) { $customFields[$fieldName] = [string]$fieldValue }
    }

    $body = @{
        name        = $deviceName
        device_type = $deviceTypeId
        role        = $roleId
        site        = $siteId
        status      = "active"
        comments    = $comments
        custom_fields = $customFields
    } | ConvertTo-Json -Depth 5

    try {
        $newDevice = Invoke-RestMethod -Uri "$netboxBaseUrl/dcim/devices/" -Headers $netboxHeaders -Method Post -Body $body
        "  CREATED: $deviceName (NetBox ID $($newDevice.id))"

        # Add primary IP if we have one
        if ($node.IPAddress) {
            try {
                $ipBody = @{
                    address = "$($node.IPAddress)/32"
                    status  = "active"
                    dns_name = if ($node.DNS) { $node.DNS } else { "" }
                    assigned_object_type = "dcim.device"
                    assigned_object_id   = $newDevice.id
                } | ConvertTo-Json
                $newIp = Invoke-RestMethod -Uri "$netboxBaseUrl/ipam/ip-addresses/" -Headers $netboxHeaders -Method Post -Body $ipBody

                # Set as primary IP on the device
                $patchBody = @{ primary_ip4 = $newIp.id } | ConvertTo-Json
                Invoke-RestMethod -Uri "$netboxBaseUrl/dcim/devices/$($newDevice.id)/" -Headers $netboxHeaders -Method Patch -Body $patchBody | Out-Null
                "           IP $($node.IPAddress) assigned as primary"
            } catch {
                "           WARNING: Could not assign IP $($node.IPAddress) to $deviceName : $_"
            }
        }
        $created++
    } catch {
        "  ERROR  : Failed to create $deviceName : $_"
        $errors++
    }
}

#endregion Execution
#####-----------------------------------------------------------------------------------------#####
#region Cleanup

""
"==== Sync Complete ===="
"  Nodes queried : $($nodes.Count)"
"  Created       : $created"
"  Skipped       : $skipped"
"  Errors        : $errors"

$stopWatch.Stop()
Write-Host "Script duration: $($stopWatch.Elapsed.Minutes) min, $($stopWatch.Elapsed.Seconds) sec" -ForegroundColor Yellow

Stop-Transcript

#endregion Cleanup
