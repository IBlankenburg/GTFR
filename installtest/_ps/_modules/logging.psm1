function Write-Log {
    param(
        [int]$level,
        [string]$message,
        [string]$tag,
        [int]$color
    )
    # Globale Konfig erforderlich


    # Lookup für Level-Definition
    $logcfg = $config.log.logLevels | Where-Object Level -eq $level
    if(-not $logcfg){ return }

    # Defaults aus Tabelle + optionale Overrides
    $_color = if($PSBoundParameters.ContainsKey('color')){ $color } else { $logcfg.Color }
    $_tag   = if($PSBoundParameters.ContainsKey('tag'))  { $tag }   else { $logcfg.Tag   }

    # Schwellenwerte aus Konfiguration (Console/File)
    $consoleThreshold = ($config.log.logLevels | Where-Object DotNetLogLevel -eq $config.log.consoleLogLevel).Level
    $fileThreshold    = ($config.log.logLevels | Where-Object DotNetLogLevel -eq $config.log.fileLogLevel).Level

    # Timestamp, robust bzgl. -AsUTC
    $hasAsUtc = (Get-Command Get-Date).Parameters.ContainsKey('AsUTC')
    if($hasAsUtc){
        $timestamp = Get-Date -Format $config.log.format -AsUTC:$config.log.asUtc
    }else{
        $timestamp = Get-Date -Format $config.log.format
    }

    $entry = "$timestamp [$_tag] $message"

    # === Buffering (in der Config halten, nicht in lokaler Variable) ===
    if($config.log.logtoFile -and [string]::IsNullOrEmpty($config.log.filename)){
        $config.log.buffer += ($entry + [Environment]::NewLine)
    }

    # === Konsole ===
    if($level -ge $consoleThreshold -and $level -lt 6){
        if($config.log.showTimestamp){ Write-Host "$timestamp " -NoNewline }
        # Farbe sicher casten (Enum 0..15)
        Write-Host "[$_tag] " -ForegroundColor ([ConsoleColor]$_color) -NoNewline
        Write-Host "$message"
    }

    # === Datei ===
    if($config.log.logtoFile -and -not [string]::IsNullOrEmpty($config.log.filename)){
        # Erst Buffer flushen (falls vorhanden)
        if(-not [string]::IsNullOrEmpty($config.log.buffer)){
            $config.log.buffer | Out-File -FilePath $config.log.filename -Append -Encoding UTF8
            $config.log.buffer = ""
        }
        # Schreiben je nach fileThreshold
        if($level -ge $fileThreshold){
            $entry | Out-File -FilePath $config.log.filename -Append -Encoding UTF8
        }
    }
}

function Write-LogTrace    { param([string]$message) Write-Log 0 $message }
function Write-LogVerbose  { param([string]$message) Write-Log 1 $message }
function Write-LogInfo     { param([string]$message) Write-Log 2 $message }
function Write-LogSuccess  { param([string]$message) Write-Log 2 $message -tag 'suc' -color 10 }
function Write-LogWarning  { param([string]$message) Write-Log 3 $message }
function Write-LogError    { param([string]$message) Write-Log 4 $message }
function Write-LogCritical { param([string]$message) Write-Log 5 $message }
function Write-LogNone     { param([string]$message) Write-Log 6 $message }


function stop-script($code,$message) {
    #2000 Script hat keine Parameter
    #2001 Prepare Folders
    
    if([string]::IsNullOrEmpty($message)){
        $message = "Script stopped with unknown error"
        $code=9999
    }
    
    $suiteName= "Regtest $($env:COMPUTERNAME) $($config.ticket.version) $($config.ticket.type)"
	$report = "<test-results name=""Regtest $($env:COMPUTERNAME)"" total=""1"" passed=""0"" failures=""1"" not-run=""0"" ignored=""0"" skipped=""0"" invalid=""0"" inconclusive=""0"" date=""$(get-date -Format "yyyy.MM.DD")"" time=""$((get-date -Format "HH:mm:ss"))"">"
	$report+= "   <test-suite name=""$suiteName"" success=""False"" executed=""True"" type=""TestFixture"">"
    $report+= "       <results>"
	$report+= "         <test-case name=""Initialize"" result=""Failure"" success=""False"" time=""$((get-date -Format "HH:mm:ss"))""> executed=""True"">"
	$report+= "             <failure>"
	$report+= "               <message>Error $code - $message</message>"
	$report+= "             </failure>"
	$report+= "          </test-case>"
	$report+= "       </results>"
	$report+= "   </test-suite>"
	$report+= "</test-results>"
	
    $report | Out-File -FilePath (Join-Path -Path $global:config.folders.reports -ChildPath "ccreport.xml") -Encoding UTF8
    Write-LogError "Script stopped with error code $code - $message"
    exit 1
}


Export-ModuleMember -Function Write-Log, Write-LogTrace, Write-LogVerbose, Write-LogInfo, Write-LogWarning, Write-LogError, Write-LogCritical, Write-LogNone,Write-LogSuccess,stop-script

<# Sample
    # Test
    $config.log.consoleLogLevel="trace"
    Write-LogTrace "Test to buffer 1"
    write-logVerbose "Test to buffer 2"
    write-logInfo "Test to buffer 2"


    $config.log.filename = "test_logging.log"
    write-logWarning "Logfile configured: $($config.log.filename)"
    write-logError "Test to file 2"
    write-logCritical "Test to file 2"
    write-logNone "Test to file 2"
#>