param()

Write-host "## Install-Test revision  2025-08-30 12:00"

Set-StrictMode -Off
$global:ProgressPreference    = 'SilentlyContinue'   # unterdrückt Write-Progress
$global:VerbosePreference     = 'SilentlyContinue'   # killt -Verbose / Write-Verbose
$global:InformationPreference = 'SilentlyContinue'   # killt Write-Information

# find root
if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
    $root = $PSScriptRoot
}elseif(-not [string]::IsNullOrEmpty($MyInvocation.MyCommand.Path)) {
    $root = Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    # Fallback: aktuelles Verzeichnis
    $root = Get-Location
}
if(-not(Test-Path -Path "$root\main.ps1")) {
    Write-Error "invalid root path: $root - main.ps1 not found"
    exit 1
}

# Create global configuration object
$global:config = [PSCustomObject]@{
    folders = [PSCustomObject]@{
        root    = $root
        modules = Join-Path -Path $root -ChildPath '_ps\_modules'
        log     = Join-Path -Path $root -ChildPath '\log'
        testcases = Join-Path -Path $root -ChildPath '\testcases'
    }
    tools= [PSCustomObject]@{
        sevenZip = Join-Path -Path $root -ChildPath '_ps\_tools\7-Zip\7z.exe'
        extent   = Join-Path -Path $root -ChildPath '_ps\_tools\extent.exe'
    }
    misc=[PSCustomObject]@{
        ccreportName="ccreport.xml" # Name der CCREPORT Datei
    }
    log = [PSCustomObject]@{
        consoleLogLevel = 'Trace'     # trace, debug, information, warning, error, critical, none
        fileLogLevel    = 'Trace'     # currently not used
        buffer          = ''          # buffer if logToFile is true and filename not set
        showTimestamp   = $true       # show timestamp in log
        filename        = ''          # filename if logToFile is true
        logtoFile       = $true       # log to file enable 
        format          = 'yyyyMMdd-HHmmss' 
        asUtc           = $false      # log timestamps as UTC (only powershell 7+) 
        logLevels       = @(
            [PSCustomObject]@{ Level = 0; Tag = 'trc'; Color = 8;  DotNetLogLevel = 'Trace' }
            [PSCustomObject]@{ Level = 1; Tag = 'vrb'; Color = 11; DotNetLogLevel = 'Debug' }
            [PSCustomObject]@{ Level = 2; Tag = 'inf'; Color = 15; DotNetLogLevel = 'Information' }
            [PSCustomObject]@{ Level = 3; Tag = 'wrn'; Color = 14; DotNetLogLevel = 'Warning' }
            [PSCustomObject]@{ Level = 4; Tag = 'err'; Color = 12; DotNetLogLevel = 'Error' }
            [PSCustomObject]@{ Level = 5; Tag = 'crt'; Color = 13; DotNetLogLevel = 'Critical' }
            [PSCustomObject]@{ Level = 6; Tag = '---'; Color = 7;  DotNetLogLevel = 'None' }
        )
    
    }
}


$config=$global:config
#Set Consol LogLevel
# $config.log.consoleLogLevel = "Trace" # trace, debug, information, warning, error, critical, none

# Load modules
foreach($module in Get-ChildItem -Path $global:config.folders.modules -Filter '*.psm1') {
    $modulePath = Join-Path -Path $global:config.folders.modules -ChildPath $module.Name
    Import-Module -Name $modulePath -Force
}
write-logInfo "Modules loaded from $($global:config.folders.modules)"

#create workdir if not exists

New-FoldersIfMissing -Path "$($global:config.folders.log)"  -ForceRemove 


#create logfile
# $config.log.filename = Join-Path -Path $global:config.folders.log -ChildPath "log-$((Get-Date).ToString($config.log.format)).txt"
$config.log.filename = Join-Path -Path $global:config.folders.log -ChildPath "Build-Summary.log"
Write-LogVerbose "Log file will be written to $($config.log.filename)"

# pre test
invoke-pester "$($config.folders.testcases)\pre_ainstall\pre_ainstall.tests.ps1"

$global:ProgressPreference    = 'Continue'
$global:VerbosePreference     = 'Continue'
$global:InformationPreference = 'Continue'
exit 0