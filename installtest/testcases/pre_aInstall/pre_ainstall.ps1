function pre_ainstall($validator) {
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
        $codedir=(Get-ItemProperty HKLM:\SOFTWARE\GBS\iQ.Suite\General\ -ErrorAction Stop).code    
        get-item "$codedir\bin\gtadmin.exe" -ErrorAction Stop
        $result.Setup.installed="gtadmin found"
        return $result
    }catch{
        $result.Setup.installed=0
    }
    
    # start Eventlog Recording
    $result.Eventlog = Start-EventlogRecording

    # --- Services stoppen/deaktivieren ---
    # MSExchangeTransport (falls vorhanden)
    try {
        $svc = Get-Service -Name 'MSExchangeTransport' -ErrorAction SilentlyContinue
        if ($null -ne $svc) {
            try {
                if ($svc.Status -ne 'Stopped') {
                    Stop-Service -Name $svc.Name -Force -ErrorAction Stop
                }
            } catch {
                Write-LogWarning "$($result.setup.function): Konnte Dienst '$($svc.Name)' nicht stoppen: $($_.Exception.Message)"
            }
            try {
                Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
            } catch {
                Write-LogWarning "$($result.setup.function): Konnte Starttyp für '$($svc.Name)' nicht auf Disabled setzen: $($_.Exception.Message)"
            }
        }
    } catch {
        Write-LogWarning "$($result.setup.function): Abfrage von 'MSExchangeTransport' fehlgeschlagen: $($_.Exception.Message)"
    }

    # Alle iqsuite* Dienste (falls vorhanden)
        try {
            $iqSvcs = Get-Service -Name 'iqsuite*' -ErrorAction SilentlyContinue
            foreach ($s in $iqSvcs) {
                try {
                    if ($s.Status -ne 'Stopped') {
                        Stop-Service -Name $s.Name -Force -ErrorAction Stop
                    }
                } catch {
                    Write-Warning "$($result.setup.function): Konnte Dienst '$($s.Name)' nicht stoppen: $($_.Exception.Message)"
                }
                try {
                    Set-Service -Name $s.Name -StartupType Disabled -ErrorAction Stop
                } catch {
                    Write-Warning "$($result.setup.function): Konnte Starttyp für '$($s.Name)' nicht auf Disabled setzen: $($_.Exception.Message)"
                }
            }
        } catch {
            Write-Warning "$($result.setup.function): Abfrage der iqsuite* Dienste fehlgeschlagen: $($_.Exception.Message)"
        }

    # --- Setup vorbereiten ---
        $result.setup.exe       = Join-Path -Path $config.folders.testcases -ChildPath 'pre_ainstall\setup_msx_IQSUITE.exe'
        $result.Setup.logFile   = Join-Path -Path $config.folders.log -ChildPath "$($result.setup.function)_setup.log"
        $result.setup.arguments = ('/s /v"/qn GRP_FLAG_FORCE_PS=1 /L*v ""{0}"""' -f $result.Setup.logFile)
        # Optional (InstallShield): /SMS hinzufügen, damit der Wrapper auf msiexec wartet
        # $result.setup.arguments = ('/s /SMS /v"/qn GRP_FLAG_FORCE_PS=1 /L*v ""{0}"""' -f $result.Setup.logFile)

    # Setup starten
        if (-not (Test-Path -LiteralPath $result.setup.exe)) {
            $result.Setup.result = "setup not found [$($result.setup.exe)]"
            write-logError "$($result.setup.function): $result.Setup.result"
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
            $msi   = Get-Process -Name 'msiexec' -ErrorAction SilentlyContinue
            $setup = Get-Process -Name 'setup*'  -ErrorAction SilentlyContinue

            if (-not $msi -and -not $setup) { break }   # nichts mehr aktiv → fertig

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
