$duration = 48

if(!$creds) {$creds = Get-Credential}
$sites = get-iissite
$ParsedLogs = $null
$ParsedLogs = [System.Collections.ArrayList]@()
foreach($site in $sites ) {
    Write-host " Checking $site Logs" -foregroundcolor Green
    $logDir = $site.logfile.directory + "\w3svc" + $site.id
    Write-host "  $logDir"  -foregroundcolor DarkGray
    $logs = Get-ChildItem -Path $logDir | Where-Object {$_.LastWriteTime -ge [DateTime]::Now.Addhours(-$duration)}

    ForEach ($log in $logs) {

        Write-host "   Parsing $($log.fullname)" -foregroundcolor DarkGreen
    
        $results = @(
            Select-String $log -Pattern ' GET ', ' POST ' |
            where { $_ -match "^(?<Timestamp>\S+ \S+) \S+ \S+ \S+ (?<Method>\S+) (?<URIQuery>\S+ \S+) \d+ (?<User>\S+) (?<IP>\S+) \S+ \S+ \S+ \S+ \S+ (?<Response>\S+) \S+ \S+ (?<ServerBytesSent>\d+) (?<ClientBytesSent>\d+) (?<MS>\d+)" } | 
            foreach { 
                new-object PSObject –Property @{ 
                    Server          = $server
                    Timestamp       = $matches['Timestamp']
                    Method          = $matches['Method']
                    URIQuery        = ($matches['URIQuery']).Replace(' ','?')
                    User            = $matches['User']
                    IP              = $matches['IP']
                    Response        = $matches['Response']
                    ServerBytesSent = [int]$matches['ServerBytesSent']
                    ClientBytesSent = [int]$matches['ClientBytesSent']
                    MS              = [int]$matches['MS']
                } } )
        [void]$ParsedLogs.Add($results)
    }
}


# Examples of using the data

# most frequently requested pages
$ParsedLogs.URIQuery | where-object {$_ -like "*.aspx*" }| group-object | sort-object -Property "Count" -Descending | select -first 20 | ft -Property ("Count", "Name");

# most frequent User
#$ParsedLogs.User | group-object | sort-object -Property "Count" -Descending | select -first 10 | ft -Property ("Count", "Name");

# most frequent IP
#$ParsedLogs.IP | group-object | sort-object -Property "Count" -Descending | select -first 10 | ft -Property ("Count", "Name");

<# URI with the longest total aounts of time, this number can be affected by the client side as well as the server execution time.

$aggs = @()
foreach($obj in $parsedlogs) {
    foreach($row in $obj) {
        if($row.uriquery -notin $aggs.uriquery) {
            "Adding new row for $($row.uriquery)"
            $new = new-object PSObject –Property @{
                URIQuery = $row.uriquery
                TotalMS  = $row.ms
            }
            $aggs += $new
        } else {
            $index = $aggs.IndexOf($row.uriquery)
            $aggs[$index].TotalMS = ($aggs[$index].TotalMS + $row.ms)
            "Incrementing $($row.uriquery) by $($row.ms) ms to get $($aggs[$index].TotalMS) ms"
        }
    }
}

$aggs | sort-object -property totalms -Descending | select -first 10 | ft -Property ("totalms", "uriquery");

#>
