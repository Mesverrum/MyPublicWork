# needs to be run with elevated permissions to access IIS log directories

# how far back in hours do we want to review logs?
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
                    URIQuery        = $matches['URIQuery']
                    User            = $matches['User']
                    IP              = $matches['IP']
                    Response        = $matches['Response']
                    ServerBytesSent = $matches['ServerBytesSent']
                    ClientBytesSent = $matches['ClientBytesSent']
                    MS              = $matches['MS']
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

