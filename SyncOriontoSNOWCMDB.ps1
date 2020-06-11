[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#snow values
$instance = "YOURINSTANCE.service-now.com"
$user = "SNOWUser"
#handling secure password
if((test-path -Path "c:/scripts/") -eq $false) {
    new-item -path "c:/scripts/" -itemtype "Directory"
}
if((test-path -Path "c:/scripts/SNOWcred-$env:UserName.txt") -eq $false) {
    
    read-host "Enter the ServiceNow password for $user" -AsSecureString | ConvertFrom-SecureString | set-content "c:/scripts/SNOWcred-$env:UserName.txt"
} 
$pwdTxt = Get-Content "c:/scripts/SNOWcred-$env:UserName.txt"
$securePwd = $pwdTxt | ConvertTo-SecureString 
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

#orion values
$orionhostname = "YOURORIONSERVER"
$orionuser = "ORIONUSERACCOUNT"
#handling secure password
if((test-path -Path "c:/scripts/") -eq $false) {
    new-item -path "c:/scripts/" -itemtype "Directory"
}
if((test-path -Path "c:/scripts/Orioncred-$env:UserName.txt") -eq $false) {
    read-host "Enter the Orion password for $orionuser" -AsSecureString | ConvertFrom-SecureString | set-content "c:/scripts/Orioncred-$env:UserName.txt"
} 
$pwdTxt = Get-Content "c:/scripts/Orioncred-$env:UserName.txt"
$securePwd = $pwdTxt | ConvertTo-SecureString 
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$orionpass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

<#----------------------------------------------------------[START LOGGING]----------------------------------------------------------#>
clear-host

if (!(Get-PSSnapin | Where-Object { $_.Name -eq "SwisSnapin" })) {
    Add-PSSnapin "SwisSnapin"
}

$now = Get-Date -Format "yyyyMMdd_HHmm"
$script = $MyInvocation.MyCommand
if($script.path){ $dir = Split-Path $script.path }
else { $dir = [Environment]::GetFolderPath("Desktop") }
$Logfile = "$dir\$($script.name)_$now.log"

Start-Transcript -Path $Logfile -Append -IncludeInvocationHeader | Out-Null

<#----------------------------------------------------------[BODY]----------------------------------------------------------#>

#getting SNOW data
# Build auth header
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $pass)))

# Set proper headers
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add('Authorization',('Basic {0}' -f $base64AuthInfo))
$headers.Add('Accept','application/json')


# Specify endpoint uri

#You will want to use the SNOW REST API Explorer to narrow down your search, as this sits it would pull back everything in the CMDB
$CiSearch = "https://$instance/api/now/table/cmdb_ci?" 
$CiResult = Invoke-WebRequest -Uri $ciSearch -Method GET -Headers $headers -UseBasicParsing

    if ($CiResult.StatusCode -ne 200) {
        Write-Output "Failed to Connect to $url"
    } else {
        $CiJson = ($CiResult.Content | ConvertFrom-Json).result
    }

#getting Orion Data
$swis = Connect-Swis -Hostname $orionhostname -UserName $orionuser -Password $orionpass

#modify this line to match your custom properties that you want to sync
$Nodes = get-swisdata $swis "select n.nodeid, n.caption, n.ipaddress, n.sysname, n.dns, n.customproperties.uri, n.customproperties.sn_ci, n.customproperties.SN_Criticality, n.customproperties.Serial_Number, n.customproperties.Device_Type, n.customproperties.Model_Name, n.customproperties.SN_Location, n.customproperties.site, n.customproperties.site_class, n.customproperties.Building, n.customproperties.Floor, n.customproperties.Room, n.customproperties.Rack_Number, n.customproperties.Rack_Unit, n.customproperties.SN_Operational_Status, n.customproperties.Department from orion.nodes n"  

Foreach($Node in $nodes) {
    "Checking CMDB for $($node.Caption)..."
    foreach ($ci in $CiJson) {
        #the below line defines all the comparisons for syncing
        if($ci.name -eq $node.caption -or $ci.name -eq $node.sn_ci -or $ci.name -eq $node.sysname -or $ci.name -eq $node.dns -or $ci.ip_address -eq $node.ip_address -or $ci.u_dns_host_name -eq $node.caption -or $ci.u_dns_host_name -eq $node.sysname -or $ci.u_dns_host_name -eq $node.dns -or $ci.name -eq $node.ip_address) {
            "Matched to CI property on node id $($node.nodeid)"
            $SN_CI = $ci.name;
            $SN_Criticality = $ci.u_criticality;
            $Serial_NUmber = $ci.serial_number;
            $Device_Type = $ci.short_description;
            $Model_Name = $ci.model_Number
            $SN_Location = ((Invoke-WebRequest -Uri $ci.location.link -Method GET -Headers $headers -UseBasicParsing).Content| convertfrom-json).result.name
            $site = ((Invoke-WebRequest -Uri "https://$instance/api/now/table/u_cmdb_ci_site?sysparm_query=location%3D$($ci.location.value)"  -Method GET -Headers $headers -UseBasicParsing).content | convertfrom-json).result.name
            $site_class = ((Invoke-WebRequest -Uri "https://$instance/api/now/table/u_cmdb_ci_site?sysparm_query=location%3D$($ci.location.value)"  -Method GET -Headers $headers -UseBasicParsing).content | convertfrom-json).result.u_site_class
            $Building = $ci.U_building;
            $Floor = $ci.u_floor;
            $Room = $ci.u_room;
            $Rack_number = $ci.u_rack_number;
            $Rack_Unit = $ci.u_rack_unit;
            $SN_Operational_Status = $ci.operational_status
            $Department = $ci.u_dept_code
            $CiProps = @{}
            if ($node.sn_ci -ne $SN_CI) {$CiProps.Add("SN_CI",$SN_CI)}
            if ($node.SN_Criticality -ne $SN_Criticality) {$CiProps.Add("SN_Criticality",$SN_Criticality)}
            if ($node.Serial_NUmber -ne $Serial_NUmber) {$CiProps.Add("Serial_NUmber",$Serial_NUmber)}
            if ($node.Device_Type -ne $Device_Type) {$CiProps.Add("Device_Type",$Device_Type)}
            if ($node.Model_Name -ne $Model_Name) {$CiProps.Add("Model_Name",$Model_Name)}
            if ($node.SN_Location -ne $SN_Location) {$CiProps.Add("SN_Location",$SN_Location)}
            if ($node.site -ne $site) {$CiProps.Add("site",$site)}
            if ($node.site_class -ne $site_class) {$CiProps.Add("site_class",$site_class)}
            if ($node.Building -ne $Building) {$CiProps.Add("Building",$Building)}
            if ($node.Floor -ne $Floor) {$CiProps.Add("Floor",$Floor)}
            if ($node.Room -ne $Room) {$CiProps.Add("Room",$Room)}
            if ($node.Rack_number -ne $Rack_number) {$CiProps.Add("Rack_number",$Rack_number)}
            if ($node.Rack_Unit -ne $Rack_Unit) {$CiProps.Add("Rack_Unit",$Rack_Unit)}
            if ($node.SN_Operational_Status -ne $SN_Operational_Status) {$CiProps.Add("SN_Operational_Status",$SN_Operational_Status)}
            if ($node.Department -ne $Department) {$CiProps.Add("Department",$Department)}
            if ($CiProps.Count -eq 0) {
            "No changed properties."
            Continue
            }
            $node
            $ci
            $CiProps
            Set-SwisObject $swis -Uri $node.uri -Properties $CiProps
        }
    }
}
<#----------------------------------------------------------[POST SCRIPT]----------------------------------------------------------#>

"`n`nFinished"

Stop-Transcript  
