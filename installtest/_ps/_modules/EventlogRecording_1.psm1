# EventlogRecording.psm1
#requires -Version 5.1

function Start-EventlogRecording {
    [CmdletBinding()]
    param(
        [string] $LogName = 'Application'
    )
    $start = (Get-WinEvent -LogName $LogName -MaxEvents 1 -ErrorAction Stop).RecordId
    [pscustomobject]@{
        LogName = $LogName
        Start   = [long]$start
        End     = ""
        Entrys  = ""
    }
}

function Stop-EventlogRecording {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $Eventlog,
        [switch] $CommonFields
    )
    process {
        $logName = if ($Eventlog.LogName) { $Eventlog.LogName } else { 'Application' }
        $start   = [long]$Eventlog.Start

        try {
            $end = (Get-WinEvent -LogName $logName -MaxEvents 1 -ErrorAction Stop).RecordId
        } catch {
            return [pscustomobject]@{
                LogName = $logName
                Start   = $start
                End     = ""
                Entrys  = "error: $($_.Exception.Message)"
            }
        }

        if ($end -le $start) {
            return [pscustomobject]@{
                LogName = $logName
                Start   = $start
                End     = [long]$end
                Entrys  = "no entrys"
            }
        }

        $xPath = "*[System[(EventRecordID > $start) and (EventRecordID <= $end)]]"
        try {
            $events = Get-WinEvent -LogName $logName -FilterXPath $xPath -ErrorAction Stop
            if ($CommonFields) {
                $events = $events | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, RecordId, Message
            }
            if (-not $events -or $events.Count -eq 0) { $events = "no entrys" }
        } catch {
            $events = "error: $($_.Exception.Message)"
        }

        [pscustomobject]@{
            LogName = $logName
            Start   = $start
            End     = [long]$end
            Entrys  = $events
        }
    }
}

Export-ModuleMember -Function Start-EventlogRecording, Stop-EventlogRecording
