# Load SwisPowerShell
Import-Module SwisPowerShell
 
$hostname = "localhost"
$username = "admin"
$password = ""
$swis = Connect-Swis -Hostname $hostname -Username $username -Password $password
$profileName = "Example123"

$connectionProfile = ([xml]"
<ConnectionProfile xmlns:i='http://www.w3.org/2001/XMLSchema-instance' xmlns='http://schemas.solarwinds.com/2007/08/informationservice/propertybag'>
<ConnectionData xmlns:d2p1='http://schemas.solarwinds.com/2013/Ncm'><d2p1:EnableLevel></d2p1:EnableLevel><d2p1:EnablePassword></d2p1:EnablePassword><d2p1:Password></d2p1:Password><d2p1:SshPort>0</d2p1:SshPort><d2p1:TelnetPort>0</d2p1:TelnetPort><d2p1:Username></d2p1:Username></ConnectionData>
  <EnableLevel></EnableLevel>
  <EnablePassword>somePassword</EnablePassword>
  <ExecuteScriptProtocol>SSH Auto</ExecuteScriptProtocol>
  <ID>0</ID>
  <Name>$profileName</Name>
  <Password>somePassword</Password>
  <RequestConfigProtocol>SSH Auto</RequestConfigProtocol>
  <SSHPort>22</SSHPort>
  <TelnetPort>23</TelnetPort>
  <TransferConfigProtocol>SSH Auto</TransferConfigProtocol>
  <UseForAutoDetect>false</UseForAutoDetect>
  <UserName>someUser</UserName>
</ConnectionProfile>
").DocumentElement
 
$result = Invoke-SwisVerb $swis Cirrus.Nodes AddConnectionProfile @($connectionProfile)
Write-Host $result.InnerXml

$profiles = (Invoke-SwisVerb $swis Orion.Reporting ExecuteSQL "SELECT * FROM [dbo].[NCM_ConnectionProfiles]").childnodes.documentelement.executesqlresults

$ProfileID = ($profiles | where {$_.name -like $profileName}).id[1]

$nodeToAddtoNCM = get-swisdata $swis -Query "select top 1 nodeid from orion.nodes where vendor = 'Cisco'"

Invoke-SwisVerb $swis Cirrus.Nodes AddNodeToNCM $nodeToAddtoNCM

$query = "
    SELECT top 1 Uri
    FROM Cirrus.Nodes
"
$uri = Get-SwisData $swis $query
 
$properties = @{
    ConnectionProfile = $profileID
} 
Set-SwisObject $swis $uri $properties

