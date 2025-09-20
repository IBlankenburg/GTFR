function pre_binstall($validator) {
    $result = @{
        Eventlog = @{
            Start  = ""
            End    = ""
            Entrys = ""
        }
        Setup = @{
            installed = 1
            function  = $($MyInvocation.MyCommand.Name)
            exe       = ""
            arguments = ""
            logfile   = ""
            proc      = $null
            result    = $False
            exitcode  = $null
        }
    }
    Import-Module "$($config.folders.modules)\EventlogRecording.psm1" -Force

    # breits installiert ?
    try{
        get-item "C:\Program Files\GBS\iQ.Suite WebClient\webapp\bin\De.Group.Msx.Frontend.WebClient.dll" -ErrorAction Stop
        $result.Setup.installed="De.Group.Msx.Frontend.WebClient.dll"
        return $result
    }catch{
        $result.Setup.installed=0
    }
    
    # start Eventlog Recording
    $result.Eventlog = Start-EventlogRecording

    # --- Setup vorbereiten ---
        $result.setup.exe       = Join-Path -Path $config.folders.testcases -ChildPath '_sources\setup_FE.exe'
        $result.Setup.logFile   = Join-Path -Path $config.folders.log -ChildPath "$($result.setup.function)_setup.log"
        $result.setup.arguments = $result.setup.arguments = ('/s /v"/qn GRP_SITE_WEBSITE=1 GRP_SITE_DEFAULT_APPNAME=webclient /L*v \"{0}\""' -f $result.Setup.logFile)

    # Setup starten
        if (-not (Test-Path -LiteralPath $result.setup.exe)) {
            $result.Setup.result = "setup not found [$($result.setup.exe)]"
            write-logError "$($result.setup.function): $($result.Setup.result)"
            return $result
        }

    # Zeitstempel EINMAL vor Start nehmen
        $startedAt = Get-Date

        try {
            write-logInfo "$($result.setup.function): Starting Setup # $($result.setup.exe ) $($result.setup.arguments)"
            $result.setup.proc = Start-Process -FilePath $result.setup.exe `
                                            -ArgumentList $result.setup.arguments `
                                            -WorkingDirectory (Split-Path -Parent $result.setup.exe) `
                                            -PassThru
        } catch {
            $result.Setup.result = "failed to start setup: $($_.Exception.Message)"
            write-logError "$($result.setup.function): $result.Setup.result"
            return $result
        }

    # auf anlaufen des Installers warten
        start-sleep 10 
    
    # Warten bis keine Installer-Prozesse mehr laufen (max. 20 Minuten)
        $timeoutMs = 20 * 60 * 1000
        $deadline  = (Get-Date).AddMilliseconds($timeoutMs)

        while ($true) {
            $setup = Get-Process -Name 'setup_*'  -ErrorAction SilentlyContinue

            if (-not $setup) { break }   # nichts mehr aktiv → fertig

            if ((Get-Date) -ge $deadline) {
                try { $msi, $setup | Where-Object { $_ } | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
                $result.Setup.result = "Timeout ($([int]($timeoutMs/1000)) s): Installer-Prozesse laufen noch."
                return $result
            }
            Start-Sleep -Seconds 2
        }

    # ExitCode (vom Wrapper; kann $null sein, wenn er schon beendet war)
        try { $result.Setup.exitcode = $result.setup.proc.ExitCode } catch { $result.Setup.exitcode = $null }

        if ($result.Setup.exitcode -eq 0 -or $null -eq $result.Setup.exitcode) {
            $result.Setup.result = $true
        } else {
            $result.Setup.result = "ExitCode not 0 - [$($result.Setup.exitcode)]"
            write-logError $result.Setup.result
        }

    # End Eventlog Recording
        write-logInfo "$($result.setup.function): Starting Validator"
        $result.Eventlog = $result.Eventlog | Stop-EventlogRecording -Validator $validator
 
    # build log schreiben
        $result.Setup.GetEnumerator() |
        Sort-Object Key |
        ForEach-Object {
            $fn = $result.Setup.function; if (-not $fn) { $fn = "$($MyInvocation.MyCommand.Name)" }
            Write-LogVerbose ("{0} {1} = {2}" -f $fn, $_.Key, $_.Value)
        }

    # eventlog exportieren
        $eventlog = Join-Path -Path $config.folders.log -ChildPath "$($result.setup.function)_events.csv"
        if ($result.Eventlog.Entrys -is [System.Array] -and $result.Eventlog.Entrys.Count -gt 0) {
            $result.Eventlog.Entrys |
                Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, RecordId, Message |
                Export-Csv -Path $eventlog -NoTypeInformation -Encoding UTF8
        } else {
            $eventlogTxt = [System.IO.Path]::ChangeExtension($eventlog, '.txt')
            Set-Content -Path $eventlogTxt -Value ([string]$result.Eventlog.Entrys) -Encoding UTF8
        }

    return $result
}
