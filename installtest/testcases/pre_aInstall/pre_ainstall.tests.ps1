BeforeAll {
    . $PSCommandPath.Replace('.tests.ps1', '.ps1')
    $validate = @(
        @{ type='wait'; timeoutMinutes=60; retry=20; RetrySeconds=20},
        @{ type='event'; source='iqsuite'; eventid=49; Exist=$true },       # EMH engine instance 13301 is running with 3 threads on configuration 'C:\Program Files\GBS\iQ.Suite\Config\ConfigData.xml[2025-08-30T15:59:24]'.
        @{ type='event'; source='iqsuite'; eventid=185; Exist=$false}       # Test for 'on access' scanner failed on directory 'C:\Program Files\GBS\iQ.Suite\GrpData\'.
    )
    $result = pre_ainstall -validator $validate
    # Normalisierte Flag-Variable: installiert == '0' ?
    $script:SetupInstalledIsZero = ([string]$result.Setup.installed -eq '0')
}

Describe "pre_ainstall" -Tag @('all','Systemtest','PRE') {
    Context "Setup Check"{
        it "iQ.Suite was already installed" {$result.Setup.installed | Should -Be 0 }
    }
    Context "Setup" -Skip:($result.Setup.installed -ne 0) {

        It "Setup finished without failure" {$result.Setup.result    | Should -be $true}
        It "ExitCode is 0"                  {$result.Setup.exitcode  | Should -Be 0 }
    }

    Context "Eventlog" -Skip:(-not $script:SetupInstalledIsZero) {
        It "End is set"                     {$result.Eventlog.End | Should -Not -BeNullOrEmpty}
        It "Start <= End"                   {[int64]$result.Eventlog.Start | Should -BeLessOrEqual ([int64]$result.Eventlog.End)}
        It "EMH is running" -Skip:(-not ($result.Eventlog.Entrys -is [System.Array])) {
            ($result.Eventlog.Entrys | Where-Object {$_.Id -eq 49 -and ($_.ProviderName -ieq 'iQSuite' -or $_.Source -ieq 'iQSuite')}) | Should -Not -BeNullOrEmpty
        }
        It "On Access Virusscanner is active" -Skip:(-not ($result.Eventlog.Entrys -is [System.Array])) {
            ($result.Eventlog.Entrys | Where-Object { $_.Id -eq 185 -and ($_.ProviderName -ieq 'iQSuite' -or $_.Source -ieq 'iQSuite') }) | Should -BeNullOrEmpty
        }
    }

    # Optional: Bei Fehlschlag hilfreiche Ausgabe
    AfterAll {
        if ($result.Setup.failed) {         Write-logError "Setup failed: $($result.Setup.failed)"}
    }
}
