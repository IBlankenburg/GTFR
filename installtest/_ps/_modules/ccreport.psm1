Function New-CCReport($config) {
    $reportName=$config.misc.ccreportName
    
    try {
        Write-LogInfo "Starting step: Create CC Report"

        # -- Eingabe einsammeln --
        $filelist = Get-ChildItem -Path (Join-Path $config.folders.root "_t\allresults") -Recurse -Filter 'SQLLifetime.csv'
        $header = @(
            "Testcase";"Version";"StartTime";"EndTime";"Lifetime";"MailsIn";"MailsOut";"Attachments";"MailBytes";
            "Quarantined";"Badmailed";"Mails_Second_In";"Mails_Second_Out";"PeakMemoryUsage";"Current_PrivBytes";
            "LastComObjects";"CurrentComObjects";"ConfiguredThreads";"Result"
        )
        if ($filelist.Count -eq 0) {
            stop-script -code 2016 -message "No SQLLifetime.csv files found in _t\allresults"
            return
        } else {
            Write-LogVerbose "Found $($filelist.Count) test result file(s) in _t\allresults"
        }

        # -- CSVs ohne Header einlesen, zusammenführen --
        $allRows = foreach ($f in $filelist) {
            try {
                Import-Csv -Path $f.FullName -Header $header -Delimiter ';' | ForEach-Object { $_ }
            } catch {
                Write-LogWarn "Konnte '$($f.FullName)' nicht einlesen: $($_.Exception.Message)"
            }
        }

        # -- Ergebnis-CSV (Debug/Tracing) --
        $allRows | ConvertTo-Csv | Out-File -FilePath (Join-Path $config.folders.log 'summary.csv')

        # === Einstellungen / Setup ===
        $reportPath = Join-Path $config.folders.log $reportName #name muss so sein da sonst die Piplines angepasst werden müssen
        $inv = [System.Globalization.CultureInfo]::InvariantCulture

        # === Daten normalisieren ===
        $rows = ConvertTo-Enumerable $allRows
        if ($rows.Count -eq 0) {
            throw "NUnit-Report: `$allRows ist leer."
        }

        # === XML Grundgerüst ===
        $doc = New-Object System.Xml.XmlDocument
        $now = Get-Date
        $testname = "Regtest - $($env:COMPUTERNAME) {$($config.ticket.type)  # $($config.ticket.version)}"

        $rootNode = $doc.CreateElement('test-results'); [void]$doc.AppendChild($rootNode)
        $rootNode.SetAttribute('name',  $testname)
        $rootNode.SetAttribute('total', '0')
        $rootNode.SetAttribute('errors','0')
        $rootNode.SetAttribute('failures','0')
        $rootNode.SetAttribute('not-run','0')
        $rootNode.SetAttribute('inconclusive','0')
        $rootNode.SetAttribute('ignored','0')
        $rootNode.SetAttribute('skipped','0')
        $rootNode.SetAttribute('invalid','0')
        $rootNode.SetAttribute('date', $now.ToString('yyyy-MM-dd', $inv))
        $rootNode.SetAttribute('time', $now.ToString('HH:mm:ss', $inv))

        # === Suiten-Hierarchie (NUnit 2-konform) ===
        # Oberste Suite: Assembly
        $assemblySuite = $doc.CreateElement('test-suite')
        $assemblySuite.SetAttribute('type','Assembly')
        $assemblySuite.SetAttribute('name',$testname)
        $assemblySuite.SetAttribute('executed','True')
        $assemblySuite.SetAttribute('asserts','0')
        [void]$rootNode.AppendChild($assemblySuite)

        $assemblyResults = $doc.CreateElement('results')
        [void]$assemblySuite.AppendChild($assemblyResults)

        # Zwischenebene: TestFixture
        $fixtureSuite = $doc.CreateElement('test-suite')
        $fixtureSuite.SetAttribute('type','TestFixture')
        $fixtureSuite.SetAttribute('name',$testname)
        $fixtureSuite.SetAttribute('executed','True')
        $fixtureSuite.SetAttribute('asserts','0')
        [void]$assemblyResults.AppendChild($fixtureSuite)

        $fixtureResults = $doc.CreateElement('results')
        [void]$fixtureSuite.AppendChild($fixtureResults)

        # === Counter ===
        $counts = @{
            total        = 0
            errors       = 0
            failures     = 0
            notrun       = 0
            inconclusive = 0
            ignored      = 0
            skipped      = 0
            invalid      = 0
        }

        # Liste der Debug-Properties, die bei Failure in den stack-trace geschrieben werden
        $debugKeys = @(
            'StartTime','EndTime','Lifetime','Version','Result',
            'MailsIn','MailsOut','Attachments','MailBytes','Quarantined','Badmailed',
            'Mails_Second_In','Mails_Second_Out','PeakMemoryUsage','Current_PrivBytes',
            'LastComObjects','CurrentComObjects','ConfiguredThreads'
        )

        # === Testfälle ===
        foreach ($row in $rows) {
            $counts.total++

            $name = if ($row.Testcase) { "$($row.Testcase)" } else { "Test $($counts.total)" }
            $sec  = Get-SecondsFromLifetime $row.Lifetime
            $map  = ConvertTo-ResultMap $row.Result
            if ($map.counter) { $counts[$map.counter]++ }

            $tc = $doc.CreateElement('test-case')
            $tc.SetAttribute('name',     $name)
            $tc.SetAttribute('executed', ($map.executed).ToString())
            $tc.SetAttribute('result',   $map.result)
            $tc.SetAttribute('success',  ($map.result -eq 'Success').ToString())
            $tc.SetAttribute('start-time', "$($row.StartTime)")
            $tc.SetAttribute('end-time',   "$($row.EndTime)")
            $tc.SetAttribute('time',       ([string]::Format($inv, '{0:0.###}', [double]$sec)))
            $tc.SetAttribute('asserts','0')

            if ($map.result -eq 'Failure') {
                # Failure-Block mit Message + Debug-Infos im Stack-Trace
                $failure = $doc.CreateElement('failure')

                $msg = $doc.CreateElement('message')
                $msg.InnerText = "Result='$($row.Result)'"
                [void]$failure.AppendChild($msg)

                $st  = $doc.CreateElement('stack-trace')
                $propLines = foreach ($k in $debugKeys) {
                    if ($row.PSObject.Properties.Name -contains $k) {
                        "$k=$($row.$k)"
                    }
                }
                $st.InnerText = ($propLines -join [Environment]::NewLine)
                [void]$failure.AppendChild($st)

                [void]$tc.AppendChild($failure)
            }
            # Bei Success: KEINE <properties> anhängen (absichtlich weggelassen)

            [void]$fixtureResults.AppendChild($tc)
        }

        # === Aggregat / Abschluss ===
        $sumSeconds = ($rows | ForEach-Object { [double](Get-SecondsFromLifetime $_.Lifetime) } | Measure-Object -Sum).Sum

        # Fixture-Resultate
        $fixtureSuite.SetAttribute('result', $(if ($counts.failures -gt 0) { 'Failure' } else { 'Success' }))
        $fixtureSuite.SetAttribute('success', ($counts.failures -eq 0).ToString())
        $fixtureSuite.SetAttribute('time',    ([string]::Format($inv, '{0:0.###}', [double]$sumSeconds)))

        # Assembly-Resultate (spiegeln Fixture)
        $assemblySuite.SetAttribute('result',  $(if ($counts.failures -gt 0) { 'Failure' } else { 'Success' }))
        $assemblySuite.SetAttribute('success', ($counts.failures -eq 0).ToString())
        $assemblySuite.SetAttribute('time',    ([string]::Format($inv, '{0:0.###}', [double]$sumSeconds)))

        # Root counters
        $rootNode.SetAttribute('total',        "$($counts.total)")
        $rootNode.SetAttribute('errors',       "$($counts.errors)")
        $rootNode.SetAttribute('failures',     "$($counts.failures)")
        $rootNode.SetAttribute('not-run',      "$($counts.notrun)")
        $rootNode.SetAttribute('inconclusive', "$($counts.inconclusive)")
        $rootNode.SetAttribute('ignored',      "$($counts.ignored)")
        $rootNode.SetAttribute('skipped',      "$($counts.skipped)")
        $rootNode.SetAttribute('invalid',      "$($counts.invalid)")

        # === Schreiben (UTF-8 ohne BOM, mit Einrückung) ===
        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
        $fs = [System.IO.File]::Create($reportPath)
        $writer = [System.Xml.XmlWriter]::Create($fs, $settings)
        $doc.Save($writer)
        $writer.Close()
        $fs.Close()

        Write-LogVerbose "NUnit2 Report geschrieben: $reportPath (Total=$($counts.total), Failures=$($counts.failures))"
    } catch {
        stop-script -code 2015 -message "Failed to create CC report: $($_.Exception.Message)"
    }
}

# === Helfer ===
function ConvertTo-Enumerable($x) {
    if ($null -eq $x) { return @() }
    if ($x -is [System.Collections.IEnumerable] -and -not ($x -is [string])) { return $x }
    return ,$x
}
function Get-SecondsFromLifetime([object]$v) {
    if ($null -eq $v) { return 0.0 }
    $s = "$v".Trim()
    if ($s -eq '') { return 0.0 }
    $s = $s -replace ',', '.'
    try { return ([TimeSpan]::Parse($s)).TotalSeconds } catch { return 0.0 }
}
function ConvertTo-ResultMap([string]$r) {
    if ($null -eq $r) { return @{ result='NotRunnable'; executed=$false; counter='notrun' } }
    $t = $r.Trim().ToUpperInvariant()
    switch ($t) {
        'SUCCESS' { @{ result='Success'; executed=$true;  counter=$null      } }
        'PASS'    { @{ result='Success'; executed=$true;  counter=$null      } }
        'PASSED'  { @{ result='Success'; executed=$true;  counter=$null      } }
        'FAIL'    { @{ result='Failure'; executed=$true;  counter='failures' } }
        'FAILED'  { @{ result='Failure'; executed=$true;  counter='failures' } }
        'ERROR'   { @{ result='Failure'; executed=$true;  counter='failures' } }
        'IGNORED' { @{ result='Ignored'; executed=$false; counter='ignored'  } }
        'SKIPPED' { @{ result='Skipped'; executed=$false; counter='skipped'  } }
        'NOTRUN'  { @{ result='NotRunnable'; executed=$false; counter='notrun' } }
        default   { @{ result='Failure'; executed=$true;  counter='failures' } }
    }
}
