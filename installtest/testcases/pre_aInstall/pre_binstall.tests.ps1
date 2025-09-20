BeforeAll {
    . $PSCommandPath.Replace('.tests.ps1', '.ps1')
    $validate = @(
        @{ type='wait'; timeoutMinutes=60; retry=20; RetrySeconds=20},
        @{ type='event'; source='MsiInstaller'; eventid=1033; Exist=$true }       # EMH engine instance 13301 is running with 3 threads on configuration 'C:\Program Files\GBS\iQ.Suite\Config\ConfigData.xml[2025-08-30T15:59:24]'.
    )
    
    $result = pre_binstall -validator $validate
    # Normalisierte Flag-Variable: installiert == '0' ?
    $script:SetupInstalledIsZero = ([string]$result.Setup.installed -eq '0')
}

Describe "pre_binstall" -Tag @('all','Systemtest','PRE') {
    #TODO: wass passiert wenn Setup Exe nicht vorhanden ?
    Context "Setup Check"{
        it "iQ.Suite was already installed" {$result.Setup.installed | Should -Be 0 }
    }
    Context "Setup" -Skip:($result.Setup.installed -ne 0) {
        It "Setup finished without failure" {$result.Setup.result    | Should -be $true}
        It "ExitCode is 0"                  {$result.Setup.exitcode  | Should -Be 0 }
    }

    Context "Eventlog" -Skip:($result.Setup.installed -ne 0) {
        It "End is set"                     {$result.Eventlog.End | Should -Not -BeNullOrEmpty}
        It "Start <= End"                   {[int64]$result.Eventlog.Start | Should -BeLessOrEqual ([int64]$result.Eventlog.End)}

        It "EMH is running" -Skip:(-not ($result.Eventlog.Entrys -is [System.Array])) {
            ($result.Eventlog.Entrys | Where-Object {$_.Id -eq 1033 -and ($_.ProviderName -ieq 'MsiInstaller' -or $_.Source -ieq 'MsiInstaller')}) | Should -Not -BeNullOrEmpty
        }
    }

    # Optional: Bei Fehlschlag hilfreiche Ausgabe
    AfterAll {
        #json
        $outFile = Join-Path $global:config.folders.log 'pre_binstall_result.json'
        $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $outFile -Encoding UTF8
        #xml
        $outFile = Join-Path $global:config.folders.log 'pre_ainstall_result.clixml'
        $result | Export-Clixml -Path $outFile
        ##
        write-logInfo "Result gespeichert in $outFile"

        if ($result.Setup.failed) {
            Write-logError "iQ.Suite Webclient Setup failed: $($result.Setup.failed)"
        }else{
            Write-LogSuccess "iQ.Suite Webclient Setup done..."
        }
    }
}
