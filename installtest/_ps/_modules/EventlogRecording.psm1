function Stop-EventlogRecording {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $Eventlog,
        [object[]] $Validator
    )
    process {
        $logName = if ($Eventlog.LogName) { $Eventlog.LogName } else { 'Application' }
        $start   = 0
        if ($Eventlog.Start -ne $null -and "$($Eventlog.Start)" -ne '') { $start = [long]$Eventlog.Start }

        # --- Wait/Retry-Konfig auslesen ---
        $waitCfg      = $Validator | Where-Object { $_.type -match '^wait$' } | Select-Object -First 1
        $retries      = if ($waitCfg.retry)          { [int]$waitCfg.retry }          else { 1 }
        $sleepSeconds = if ($waitCfg.RetrySeconds)   { [int]$waitCfg.RetrySeconds }   else { 1 }
        $timeoutMin   = if ($waitCfg.timeoutMinutes) { [int]$waitCfg.timeoutMinutes } else { 0 }
        $deadline     = if ($timeoutMin -gt 0) { (Get-Date).AddMinutes($timeoutMin) } else { [datetime]::MaxValue }

        $eventRules   = @($Validator | Where-Object { $_.type -match '^event$' })

        Write-LogVerbose ("Stop-EventlogRecording: start='{0}', log='{1}', rules={2}, retries={3}, retryDelay={4}s, timeout={5}min, deadline='{6:yyyy-MM-dd HH:mm:ss}'" -f `
            $start, $logName, $eventRules.Count, $retries, $sleepSeconds, $timeoutMin, $deadline)

        $end    = $start
        $events = @()
        $sw     = [System.Diagnostics.Stopwatch]::StartNew()

        for ($attempt = 0; $attempt -lt $retries; $attempt++) {
            $attemptDisplay = $attempt + 1
            $remaining = if ($deadline -ne [datetime]::MaxValue) { [int]([math]::Max(0, ($deadline - (Get-Date)).TotalSeconds)) } else { -1 }
            Write-LogVerbose "Stop-EventlogRecording: attempt $attemptDisplay/$retries (remaining ${remaining}s)"

            # Aktuelles End ermitteln
            try {
                $end = (Get-WinEvent -LogName $logName -MaxEvents 1 -ErrorAction Stop).RecordId
                Write-LogVerbose "Stop-EventlogRecording: latest RecordId (End)=$end"
            } catch {
                Write-LogWarning "Stop-EventlogRecording: could not read latest RecordId — $($_.Exception.Message)"
                return [pscustomobject]@{ LogName=$logName; Start=$start; End=$end; Entrys=@() }
            }

            # Events seit Start einsammeln (<= End)
            if ($end -le $start) {
                $events = @()
                Write-LogVerbose "Stop-EventlogRecording: no new events (End <= Start)"
            } else {
                $xPath = "*[System[(EventRecordID > $start) and (EventRecordID <= $end)]]"
                Write-LogVerbose "Stop-EventlogRecording: querying events with XPath: $xPath"
                try {
                    $events = Get-WinEvent -LogName $logName -FilterXPath $xPath -ErrorAction Stop
                    Write-LogVerbose ("Stop-EventlogRecording: fetched {0} events in attempt {1}" -f $events.Count, $attemptDisplay)
                } catch {
                    Write-LogWarning "Stop-EventlogRecording: Get-WinEvent failed — $($_.Exception.Message)"
                    $events = @()
                }
            }

            # Regeln prüfen (inkl. detaillierter Match-Logs)
            $allOk     = $true
            $fatalStop = $false   # sofortiger Abbruch, wenn unerwünschtes Event gefunden wurde

            if ($eventRules.Count -gt 0) {
                foreach ($rule in $eventRules) {
                    $id        = [int]$rule.eventid
                    $src       = [string]$rule.source
                    $mustExist = [bool]$rule.Exist

                    Write-LogVerbose ("Validate Rule [attempt {3}]: EventID={0}, Source='{1}', mustExist={2}" -f $id, $src, $mustExist, $attemptDisplay)

                    $matches = $events | Where-Object {
                        $_.Id -eq $id -and (
                            ($_.ProviderName -and $_.ProviderName -ieq $src) -or
                            ($_.Source       -and $_.Source       -ieq $src)
                        )
                    }

                    $count = ($matches | Measure-Object).Count
                    Write-LogVerbose ("Validate Rule [attempt {1}]: match count={0}" -f $count, $attemptDisplay)

                    if ($count -gt 0) {
                        foreach ($m in $matches) {
                            $time     = if ($m.TimeCreated) { $m.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss.fff') } else { '' }
                            $provider = if ($m.ProviderName) { $m.ProviderName } elseif ($m.Source) { $m.Source } else { '' }
                            $msg      = if ($m.Message) { $m.Message } else { '' }

                            Write-LogInfo ("Rule match → Rule(EventID={0}, Source='{1}', mustExist={2}) | Event: Id={3}, Time='{4}', Provider='{5}', RecordId={6}, Message={7}" -f `
                                $id, $src, $mustExist, $m.Id, $time, $provider, $m.RecordId, $msg)
                        }
                    }

                    if ($mustExist) {
                        if ($count -eq 0) {
                            $allOk = $false
                            Write-LogVerbose "Rule not satisfied: expected event not found"
                            # weiter versuchen
                        }
                    } else {
                        if ($count -gt 0) {
                            Write-LogWarning "Rule violated: unexpected event present — aborting validation/retries"
                            $allOk     = $false
                            $fatalStop = $true
                            break
                        }
                    }
                }
            } else {
                Write-LogVerbose "Stop-EventlogRecording: no event rules provided — skipping rule validation"
            }

            # Abbruch, wenn „verbotenes“ Event gefunden wurde
            if ($fatalStop) { break }

            if ($allOk) {
                Write-LogInfo ("Validate Eventlog: success at attempt {0} (elapsed {1} ms)" -f $attemptDisplay, $sw.ElapsedMilliseconds)
                break
            }

            if ((Get-Date) -ge $deadline) {
                Write-LogWarning "Validate Eventlog: deadline reached — stop retrying"
                break
            }

            Write-LogVerbose ("Validate Eventlog: retrying (attempt {0}/{1}), sleeping {2}s…" -f $attemptDisplay, $retries, $sleepSeconds)
            Start-Sleep -Seconds $sleepSeconds
        } # <— schließt die for-Schleife

        $sw.Stop()

        # Projektion auf gängige Felder
        $proj = $events | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, RecordId, Message

        # Zusammenfassung
        $firstTime = $null; $lastTime = $null
        if ($proj.Count -gt 0) {
            $firstTime = ($proj | Select-Object -First 1).TimeCreated
            $lastTime  = ($proj | Select-Object -Last  1).TimeCreated
        }
        Write-LogVerbose ("Stop-EventlogRecording: summary -> Start={0}, End={1}, Events={2}, First='{3}', Last='{4}', Elapsed={5} ms" -f `
            $start, $end, ($proj | Measure-Object).Count, $firstTime, $lastTime, $sw.ElapsedMilliseconds)

        [pscustomobject]@{
            LogName = $logName
            Start   = $start
            End     = [long]$end
            Entrys  = @($proj)
        }
    }
}
