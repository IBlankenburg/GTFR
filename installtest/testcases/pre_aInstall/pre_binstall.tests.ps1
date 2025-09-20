BeforeAll {
    . $PSCommandPath.Replace('.tests.ps1', '.ps1')
    $validate = @(
        @{ type='wait'; timeoutMinutes=60; retry=20; RetrySeconds=20},
        @{ type='event'; source='MsiInstaller'; eventid=1033; Exist=$true }       # EMH engine instance 13301 is running with 3 threads on configuration 'C:\Program Files\GBS\iQ.Suite\Config\ConfigData.xml[2025-08-30T15:59:24]'.
    )
    
    $result = pre_binstall -validator $validate
    # Normalisierte Flag-Variable: installiert == '0' ?
    $SetupInstalledIsZero = ([string]$result.Setup.installed -eq '0')
    ## Save $result as xml/json
    $outFile = Join-Path $global:config.folders.log "pre_binstall_result" # change name
    write-logInfo "Result gespeichert in $outFile"
    $result | Export-Clixml -Path "$($outFile).cliXML"
    $result | ConvertTo-Json | Out-File -FilePath "$($outFile).json" -Encoding UTF8
}

Describe "pre_binstall" -Tag @('all','Systemtest','PRE') {
    #TODO: wass passiert wenn Setup Exe nicht vorhanden ?
    Context "Setup Check"{
        it "iQ.Suite was already installed" { $SetupInstalledIsZero | Should -Be $true }
    }

    Context "Setup" -Skip:(-not $SetupInstalledIsZero) {
        It "Setup finished without failure" { $result.Setup.result   | Should -be $true }
        It "ExitCode is 0"                 { $result.Setup.exitcode | Should -Be 0 }
    }

    Context "Eventlog" -Skip:(-not $SetupInstalledIsZero) {
        It "End is set"       { $result.Eventlog.End | Should -Not -BeNullOrEmpty }
        It "Start <= End"     { [int64]$result.Eventlog.Start | Should -BeLessOrEqual ([int64]$result.Eventlog.End) }
        It "Setup is done" {@($result.Eventlog.Entrys | Where-Object {$_.Id -eq 1033 -and ($_.ProviderName -ieq 'MsiInstaller' -or $_.Source -ieq 'MsiInstaller')}) | Should -Not -BeNullOrEmpty}
    }

    # Optional: Bei Fehlschlag hilfreiche Ausgabe
    AfterAll {
    
    write-logInfo "Result gespeichert in $outFile"
        if ($result.Setup.failed) {
            Write-logError "iQ.Suite Webclient Setup failed: $($result.Setup.failed)"
        } else {
            Write-LogSuccess "iQ.Suite Webclient Setup done..."
        }
    }
}
