
$ParsedLogs = @( )
$Logs = Get-ChildItem -Path $env:ProgramData\SolarWinds\Logs\ -recurse | Where-Object {$_.name -like "*log" } #-and $_.name -notlike "*probes_*" -and $_.name -notlike "*servicehost_*" -and $_.name -notlike "*jobs_*" -and $_.name -notlike "*job_*" -and $_.name -notlike "*queries_*" -and $_.name -notlike "agentworker_*" -and $_.Directory -notlike "*Applicationlogs*" -and $_.Directory -notlike "*Installer*"} 
$APMProbes = $null
$ApplicationLogs = $null
$AIJobs = $null
$HWHJobs = $null
$CCJobs = $null
$CTCJobs = $null
$ICJobs = $null
$SEUMAgents = $null
$SRMJobs = $null
$SRMQueries = $null

ForEach ($log in $logs) {

    "Parsing $($log.fullname)"
    
    $Errors = @(Select-String $($log.FullName) -Pattern '] ERROR ' | 
        where { $_ -match "^(?<Path>^\S:\S*?(?=:\d*:)):(?<Line>\d*):(?<Timestamp>\d{4}-\d{1,2}-\d{1,2}\s\d{2}:\d{2}:\d{2},\d{0,4}).*(?<Message>ERROR\s[\s|\S]*$)" } | 
            foreach { new-object PSObject –Property @{ 
                    Path=$matches['Path']
                    Line=$matches['Line']
                    Timestamp=$matches['Timestamp']
                    Message=$matches['Message']
            } 
        }
    )


    $Warns = @(Select-String $($log.FullName) -Pattern '] WARN ' | 
        where { $_ -match "^(?<Path>^\S:\S*?(?=:\d*:)):(?<Line>\d*):(?<Timestamp>\d{4}-\d{1,2}-\d{1,2}\s\d{2}:\d{2}:\d{2},\d{0,4}).*(?<Message>WARN\s[\s|\S]*$)" } | 
            foreach { new-object PSObject –Property @{ 
                    Path=$matches['Path']
                    Line=$matches['Line']
                    Timestamp=$matches['Timestamp']
                    Message=$matches['Message']
            } 
        }
    )

    if ( $Errors -or $Warns ) {
        "   Problems found within $($log.fullname), adding to results"

        $ParsedLog = New-Object -TypeName PSObject
        Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'Name' -Value $log.Name
        Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'Directory' -Value $log.Directory
        Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'CreationTime' -Value $log.CreationTime
        Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'LastWriteTime' -Value $log.LastWriteTime
        Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'FullName' -Value $log.FullName
        Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'Length' -Value $log.Length
        Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'Errors' -Value $Errors
        Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'ErrorsCount' -Value $Errors.Length
        #Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'TopErrors' -Value ($ParsedLog.Errors | group-object -Property Message -noelement | % { $h = @{} } { $h[$_.Name] = $_.Count } { $h } | sort count -Descending | select -first 3)
        Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'Warns' -Value $Warns
        Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'WarnsCount' -Value $Warns.Length
        #Add-Member -InputObject $ParsedLog -MemberType 'NoteProperty' -Name 'TopWarns' -Value ($ParsedLog.Warns | group-object -Property Message -noelement | % { $h = @{} } { $h[$_.Name] = $_.Count } { $h } | sort count -Descending | select -first 3)
        
        switch -wildcard ($ParsedLog.FullName) {
            "*apm.probes_*" {
                if ( !$APMProbes ) {
                    $APMProbes = @( )
                    $APMProbe = $ParsedLog
                    $APMProbe.Name = ($APMProbe.Name -replace "_\[\d*].","_[].")
                    $APMProbe.FullName = ($APMProbe.FullName -replace "_\[\d*].","_[].")
                    $APMProbes += $APMProbe
                    "   $(($APMProbes.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($APMProbes.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                else {
                    $APMProbe2 = $ParsedLog
                    $APMProbe2.Name = ($APMProbe2.Name -replace "_\[\d*].","_[].")
                    $APMProbe2.FullName = ($APMProbe2.FullName -replace "_\[\d*].","_[].")
                    $APMProbes += $APMProbe2
                    
                    $APMProbe.CreationTime = ($APMProbes.creationtime | measure -minimum).Minimum
                    $APMProbe.LastWriteTime = ($APMProbes.LastWriteTime | measure -maximum).Maximum
                    $APMProbe.Length = ($APMProbe.length + $APMProbe2.length)
                    $APMProbe.Errors += ($APMProbe2.Errors)
                    $APMProbe.ErrorsCount = ($APMProbe.ErrorsCount + $APMProbe2.ErrorsCount)

                    $APMProbe.Warns  += ($APMProbe2.Warns)
                    $APMProbe.WarnsCount = ($APMProbe.WarnsCount + $APMProbe2.WarnsCount)
                    $APMProbes = @( )
                    $APMProbes += $APMProbe
                    "   $(($APMProbes.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($APMProbes.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                ; break 
            }
            "*ApplicationLogs\AppId*" {
                if ( !$ApplicationLogs ) {
                    $ApplicationLogs = @( )
                    $ApplicationLog = $ParsedLog
                    $out = $ApplicationLog.FullName -match "(?<=ApplicationLogs\\)AppId\d*"
                    [string]$AppID = $Matches.values
                    $AppID = $AppID + ".logs"
                    $ApplicationLog.Name = $AppID
                    $ApplicationLog.FullName = ($ApplicationLog.FullName -replace "(?<=\\)\d{4}-\d{2}-\d{2}_\S*\.log","$AppID")
                    $ApplicationLogs += $ApplicationLog
                    "   $(($ApplicationLogs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($ApplicationLogs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                else {
                    $ApplicationLog2 = $ParsedLog
                    $out = $ApplicationLog2.FullName -match "(?<=ApplicationLogs\\)AppId\d*"
                    [string]$AppID = $Matches.values
                    $AppID = $AppID + ".logs"
                    $ApplicationLog2.Name = $AppID
                    $ApplicationLog2.FullName = ($ApplicationLog2.FullName -replace "(?<=\\)\d{4}-\d{2}-\d{2}_\S*\.log","$AppID")
                    $ApplicationLogs += $ApplicationLog2
                    
                    $ApplicationLog.CreationTime = ($ApplicationLogs.creationtime | measure -minimum).Minimum
                    $ApplicationLog.LastWriteTime = ($ApplicationLogs.LastWriteTime | measure -maximum).Maximum
                    $ApplicationLog.Length = ($ApplicationLog.length + $ApplicationLog2.length)
                    $ApplicationLog.Errors += ($ApplicationLog2.Errors)
                    $ApplicationLog.ErrorsCount = ($ApplicationLog.ErrorsCount + $ApplicationLog2.ErrorsCount)
                    $ApplicationLog.Warns  += ($ApplicationLog2.Warns)
                    $ApplicationLog.WarnsCount = ($ApplicationLog.WarnsCount + $ApplicationLog2.WarnsCount)
                    $ApplicationLogs = @( )
                    $ApplicationLogs += $ApplicationLog
                    "   $(($ApplicationLogs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($ApplicationLogs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                ; break 
            }
            "*AssetInventory.Collector.Jobs_*" {
                if ( !$AIJobs ) {
                    $AIJobs = @( )
                    $AIJob = $ParsedLog
                    $AIJob.Name = ($AIJob.Name -replace "_\[\d*].","_[].")
                    $AIJob.FullName = ($AIJob.FullName -replace "_\[\d*].","_[].")
                    $AIJobs += $AIJob
                    "   $(($AIJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($AIJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                else {
                    $AIJob2 = $ParsedLog
                    $AIJob2.Name = ($AIJob2.Name -replace "_\[\d*].","_[].")
                    $AIJob2.FullName = ($AIJob2.FullName -replace "_\[\d*].","_[].")
                    $AIJobs += $AIJob2
                    
                    $AIJob.CreationTime = ($AIJobs.creationtime | measure -minimum).Minimum
                    $AIJob.LastWriteTime = ($AIJobs.LastWriteTime | measure -maximum).Maximum
                    $AIJob.Length = ($AIJob.length + $AIJob2.length)
                    $AIJob.Errors += ($AIJob2.Errors)
                    $AIJob.ErrorsCount = ($AIJob.ErrorsCount + $AIJob2.ErrorsCount)
                    $AIJob.Warns  += ($AIJob2.Warns)
                    $AIJob.WarnsCount = ($AIJob.WarnsCount + $AIJob2.WarnsCount)
                    $AIJobs = @( )
                    $AIJobs += $AIJob
                    "   $(($AIJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($AIJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                ; break 
            }
            "*HardwareHealth.Collector.Jobs_*" {
                if ( !$HWHJobs ) {
                    $HWHJobs = @( )
                    $HWHJob = $ParsedLog
                    $HWHJob.Name = ($HWHJob.Name -replace "_\[\d*].","_[].")
                    $HWHJob.FullName = ($HWHJob.FullName -replace "_\[\d*].","_[].")
                    $HWHJobs += $HWHJob
                    "   $(($HWHJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($HWHJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                else {
                    $HWHJob2 = $ParsedLog
                    $HWHJob2.Name = ($HWHJob2.Name -replace "_\[\d*].","_[].")
                    $HWHJob2.FullName = ($HWHJob2.FullName -replace "_\[\d*].","_[].")
                    $HWHJobs += $HWHJob2
                    
                    $HWHJobs.CreationTime = ($HWHJobs.creationtime | measure -minimum).Minimum
                    $HWHJobs.LastWriteTime = ($HWHJobs.LastWriteTime | measure -maximum).Maximum
                    $HWHJobs.Length = ($HWHJob.length + $HWHJob2.length)
                    $HWHJobs.Errors += ($HWHJob2.Errors)
                    $HWHJobs.ErrorsCount = ($HWHJob.ErrorsCount + $HWHJob2.ErrorsCount)
                    $HWHJobs.Warns  += ($HWHJob2.Warns)
                    $HWHJobs.WarnsCount = ($HWHJob.WarnsCount + $HWHJob2.WarnsCount)
                    $HWHJobs = @( )
                    $HWHJobs += $HWHJob
                    "   $(($HWHJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($HWHJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                ; break 
            }
            "*Core.Collector.Jobs_*" {
                if ( !$CCJobs ) {
                    $CCJobs = @( )
                    $CCJob = $ParsedLog
                    $CCJob.Name = ($CCJob.Name -replace "_\[\d*].","_[].")
                    $CCJob.FullName = ($CCJob.FullName -replace "_\[\d*].","_[].")
                    $CCJobs += $CCJob
                    "   $(($CCJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($CCJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                else {
                    $CCJob2 = $ParsedLog
                    $CCJob2.Name = ($CCJob2.Name -replace "_\[\d*].","_[].")
                    $CCJob2.FullName = ($CCJob2.FullName -replace "_\[\d*].","_[].")
                    $CCJobs += $CCJob2
                    
                    $CCJob.CreationTime = ($CCJobs.creationtime | measure -minimum).Minimum
                    $CCJob.LastWriteTime = ($CCJobs.LastWriteTime | measure -maximum).Maximum
                    $CCJob.Length = ($CCJob.length + $CCJob2.length)
                    $CCJob.Errors += ($CCJob2.Errors)
                    $CCJob.ErrorsCount = ($CCJob.ErrorsCount + $CCJob2.ErrorsCount)
                    $CCJob.Warns  += ($CCJob2.Warns)
                    $CCJob.WarnsCount = ($CCJob.WarnsCount + $CCJob2.WarnsCount)
                    $CCJobs = @( )
                    $CCJobs += $CCJob
                    "   $(($CCJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($CCJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                ; break 
            }
            "*Core.Topology.Collector.Jobs_*" {
                if ( !$CTCJobs ) {
                    $CTCJobs = @( )
                    $CTCJob = $ParsedLog
                    $CTCJob.Name = ($CTCJob.Name -replace "_\[\d*].","_[].")
                    $CTCJob.FullName = ($CTCJob.FullName -replace "_\[\d*].","_[].")
                    $CTCJobs += $CTCJob
                    "   $(($CTCJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($CTCJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                else {
                    $CTCJob2 = $ParsedLog
                    $CTCJob2.Name = ($CTCJob2.Name -replace "_\[\d*].","_[].")
                    $CTCJob2.FullName = ($CTCJob2.FullName -replace "_\[\d*].","_[].")
                    $CTCJobs += $CTCJob2
                    
                    $CTCJob.CreationTime = ($CTCJobs.creationtime | measure -minimum).Minimum
                    $CTCJob.LastWriteTime = ($CTCJobs.LastWriteTime | measure -maximum).Maximum
                    $CTCJob.Length = ($CTCJob.length + $CTCJob2.length)
                    $CTCJob.Errors += ($CTCJob2.Errors)
                    $CTCJob.ErrorsCount = ($CTCJob.ErrorsCount + $CTCJob2.ErrorsCount)
                    $CTCJob.Warns  += ($CTCJob2.Warns)
                    $CTCJob.WarnsCount = ($CTCJob.WarnsCount + $CTCJob2.WarnsCount)
                    $CTCJobs = @( )
                    $CTCJobs += $CTCJob
                    "   $(($CTCJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($CTCJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                ; break 
            }
            "*Interfaces.Collector.Jobs_*" {
                if ( !$ICJobs ) {
                    $ICJobs = @( )
                    $ICJob = $ParsedLog
                    $ICJob.Name = ($ICJob.Name -replace "_\[\d*].","_[].")
                    $ICJob.FullName = ($ICJob.FullName -replace "_\[\d*].","_[].")
                    $ICJobs += $ICJob
                    "   $(($ICJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($ICJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                else {
                    $ICJob2 = $ParsedLog
                    $ICJob2.Name = ($ICJob2.Name -replace "_\[\d*].","_[].")
                    $ICJob2.FullName = ($ICJob2.FullName -replace "_\[\d*].","_[].")
                    $ICJobs += $ICJob2
                    
                    $ICJob.CreationTime = ($ICJobs.creationtime | measure -minimum).Minimum
                    $ICJob.LastWriteTime = ($ICJobs.LastWriteTime | measure -maximum).Maximum
                    $ICJob.Length = ($ICJob.length + $ICJob2.length)
                    $ICJob.Errors += ($ICJob2.Errors)
                    $ICJob.ErrorsCount = ($ICJob.ErrorsCount + $ICJob2.ErrorsCount)
                    $ICJob.Warns  += ($ICJob2.Warns)
                    $ICJob.WarnsCount = ($ICJob.WarnsCount + $ICJob2.WarnsCount)
                    $ICJobs = @( )
                    $ICJobs += $ICJob
                    "   $(($ICJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($ICJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                ; break 
            }
            "*SEUM\AgentWorker_*" {
                if ( !$SEUMAgents ) {
                    $SEUMAgents = @( )
                    $SEUMAgent = $ParsedLog
                    $SEUMAgent.Name = ($SEUMAgent.Name -replace "_\[\d*].","_[].")
                    $SEUMAgent.FullName = ($SEUMAgent.FullName -replace "_\[\d*].","_[].")
                    $SEUMAgents += $SEUMAgent
                    "   $(($SEUMAgents.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($SEUMAgents.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                else {
                    $SEUMAgent2 = $ParsedLog
                    $SEUMAgent2.Name = ($SEUMAgent2.Name -replace "_\[\d*].","_[].")
                    $SEUMAgent2.FullName = ($SEUMAgent2.FullName -replace "_\[\d*].","_[].")
                    $SEUMAgents += $SEUMAgent2
                    
                    $SEUMAgent.CreationTime = ($SEUMAgents.creationtime | measure -minimum).Minimum
                    $SEUMAgent.LastWriteTime = ($SEUMAgents.LastWriteTime | measure -maximum).Maximum
                    $SEUMAgent.Length = ($SEUMAgent.length + $SEUMAgent2.length)
                    $SEUMAgent.Errors += ($SEUMAgent2.Errors)
                    $SEUMAgent.ErrorsCount = ($SEUMAgent.ErrorsCount + $SEUMAgent2.ErrorsCount)
                    $SEUMAgent.Warns  += ($SEUMAgent2.Warns)
                    $SEUMAgent.WarnsCount = ($SEUMAgent.WarnsCount + $SEUMAgent2.WarnsCount)
                    $SEUMAgents = @( )
                    $SEUMAgents += $SEUMAgent
                    "   $(($SEUMAgents.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($SEUMAgents.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                ; break 
            }
            "*SRM.Pollers.Jobs_*" {
                if ( !$SRMJobs ) {
                    $SRMJobs = @( )
                    $SRMJob = $ParsedLog
                    $SRMJob.Name = ($SRMJob.Name -replace "_\[\d*].","_[].")
                    $SRMJob.FullName = ($SRMJob.FullName -replace "_\[\d*].","_[].")
                    $SRMJobs += $SRMJob
                    "   $(($SRMJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($SRMJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                else {
                    $SRMJob2 = $ParsedLog
                    $SRMJob2.Name = ($SRMJob2.Name -replace "_\[\d*].","_[].")
                    $SRMJob2.FullName = ($SRMJob2.FullName -replace "_\[\d*].","_[].")
                    $SRMJobs += $SRMJob2
                    
                    $SRMJob.CreationTime = ($SRMJobs.creationtime | measure -minimum).Minimum
                    $SRMJob.LastWriteTime = ($SRMJobs.LastWriteTime | measure -maximum).Maximum
                    $SRMJob.Length = ($SRMJob.length + $SRMJob2.length)
                    $SRMJob.Errors += ($SRMJob2.Errors)
                    $SRMJob.ErrorsCount = ($SRMJob.ErrorsCount + $SRMJob2.ErrorsCount)
                    $SRMJob.Warns  += ($SRMJob2.Warns)
                    $SRMJob.WarnsCount = ($SRMJob.WarnsCount + $SRMJob2.WarnsCount)
                    $SRMJobs = @( )
                    $SRMJobs += $SRMJob
                    "   $(($SRMJobs.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($SRMJobs.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                ; break 
            }
            "*SRM.Pollers.Queries_*" {
                if ( !$SRMQueries ) {
                    $SRMQueries = @( )
                    $SRMQuery = $ParsedLog
                    $SRMQuery.Name = ($SRMQuery.Name -replace "_\[\d*].","_[].")
                    $SRMQuery.FullName = ($SRMQuery.FullName -replace "_\[\d*].","_[].")
                    $SRMQueries += $SRMQuery
                    "   $(($SRMQueries.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($SRMQueries.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                else {
                    $SRMQuery2 = $ParsedLog
                    $SRMQuery2.Name = ($SRMQuery2.Name -replace "_\[\d*].","_[].")
                    $SRMQuery2.FullName = ($SRMQuery2.FullName -replace "_\[\d*].","_[].")
                    $SRMQueries += $SRMQuery2
                    
                    $SRMQuery.CreationTime = ($SRMQueries.creationtime | measure -minimum).Minimum
                    $SRMQuery.LastWriteTime = ($SRMQueries.LastWriteTime | measure -maximum).Maximum
                    $SRMQuery.Length = ($SRMQuery.length + $SRMQuery2.length)
                    $SRMQuery.Errors += ($SRMQuery2.Errors)
                    $SRMQuery.ErrorsCount = ($SRMQuery.ErrorsCount + $SRMQuery2.ErrorsCount)
                    $SRMQuery.Warns  += ($SRMQuery2.Warns)
                    $SRMQuery.WarnsCount = ($SRMQuery.WarnsCount + $SRMQuery2.WarnsCount)
                    $SRMQueries = @( )
                    $SRMQueries += $SRMQuery
                    "   $(($SRMQueries.ErrorsCount | Measure-Object -sum).sum) Errors"
                    "   $(($SRMQueries.WarnsCount | Measure-Object -sum).sum) Warns"
                }
                ; break 
            }
            default {$ParsedLogs += $ParsedLog
                "   $(($ParsedLogs.ErrorsCount | Measure-Object -sum).sum) Errors"
                "   $(($ParsedLogs.WarnsCount | Measure-Object -sum).sum) Warns"
                ; break
            }
        }
        
        $ParsedLogs += $APMProbes
        $ParsedLogs += $ApplicationLogs
        $ParsedLogs += $AIJobs
        $ParsedLogs += $HWHJobs
        $ParsedLogs += $CCJobs
        $ParsedLogs += $CTCJobs
        $ParsedLogs += $ICJobs
        $ParsedLogs += $SEUMAgents
        $ParsedLogs += $SRMJobs
        $ParsedLogs += $SRMQueries
    }
}
"`n`nTop Error Messages"
$ParsedLogs.errors.Message | group-object | sort-object -Property "Count" -Descending | select -first 10 | ft -Property ("Count", "Name");

"`n`nTop Warning Messages"
$ParsedLogs.warns.Message | group-object | sort-object -Property "Count" -Descending | select -first 10 | ft -Property ("Count", "Name");

"`n`nOldest log"
($ParsedLogs.CreationTime | measure-object -minimum).minimum

"`n`nLatest log edit"
($ParsedLogs.LastWriteTime | measure-object -maximum).maximum

"`n`nErrors in specific log file - ConfigurationWizard.log"
$parsedlogs.errors | where-object { $_.Path -like "*ConfigurationWizard.log" }
