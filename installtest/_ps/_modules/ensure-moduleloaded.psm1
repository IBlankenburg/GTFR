function Ensure-ModuleLoaded {
    param(
        [Parameter(Mandatory = $true)][string]$name,
        [string]$version = '',
        [switch]$allowglobber
    )

    # interne Log-Helfer: falls die custom Log-Funktionen noch nicht geladen sind, auf Write-Host zurückfallen
    $logInfo = {
        param($m)
        if (Get-Command -Name Write-LogInfo -ErrorAction SilentlyContinue) { Write-LogInfo $m } else { Write-Host $m }
    }
    $logWarn = {
        param($m)
        if (Get-Command -Name Write-LogWarning -ErrorAction SilentlyContinue) { Write-LogWarning $m } else { Write-Warning $m }
    }
    $logErr = {
        param($m)
        if (Get-Command -Name Write-LogError -ErrorAction SilentlyContinue) { Write-LogError $m } else { Write-Error $m }
    }

    try {
        # gewünschte Mindestversion (falls gesetzt)
        $minVersion = if ($version) { [version]$version } else { $null }

        # prüfe vorhandene Module (mindestens die gewünschte Version)
        if ($minVersion) {
            $found = Get-Module -ListAvailable -Name $name | Where-Object { $_.Version -ge $minVersion } | Sort-Object -Property Version -Descending
        } else {
            $found = Get-Module -ListAvailable -Name $name | Sort-Object -Property Version -Descending
        }

        if ($found) {
            & $logInfo "Modul '$name' (Version: $($found[0].Version)) gefunden. Versuche Import."
            $importParams = @{ Name = $name; Force = $true; ErrorAction = 'Stop' }
            # Wenn wir eine Mindestversion gesucht haben, importiere die tatsächlich gefundene Version
            if ($minVersion) { $importParams['RequiredVersion'] = $found[0].Version.ToString() }
            Import-Module @importParams
            & $logInfo "Modul '$name' erfolgreich importiert."
            return $true
        }

        & $logWarn "Modul '$name' nicht lokal gefunden. Versuche Installation aus PSGallery."

        if (-not (Get-Command -Name Install-Module -ErrorAction SilentlyContinue)) {
            & $logErr "Install-Module wird nicht gefunden. PowerShellGet / NuGet Provider fehlt?"
            return $false
        }

        $scope = if ($allowglobber) { 'AllUsers' } else { 'CurrentUser' }
        $installSplat = @{
            Name        = $name
            Force       = $true
            Repository  = 'PSGallery'
            Scope       = $scope
            ErrorAction = 'Stop'
        }
        if ($allowglobber) { $installSplat['AllowClobber'] = $true }

        # Installiere eine Version >= gewünschter Mindestversion
        if ($minVersion) {
            $installCmd = Get-Command -Name Install-Module -ErrorAction SilentlyContinue
            if ($installCmd.Parameters.ContainsKey('MinimumVersion')) {
                # Install-Module unterstützt MinimumVersion => direkt nutzen
                $installSplat['MinimumVersion'] = $minVersion.ToString()
                Install-Module @installSplat
                # versuche die tatsächlich installierte Version zu bestimmen
                $installed = Get-Module -ListAvailable -Name $name | Where-Object { $_.Version -ge $minVersion } | Sort-Object Version -Descending | Select-Object -First 1
                if ($installed) {
                    Import-Module -Name $name -RequiredVersion $installed.Version -Force -ErrorAction Stop
                } else {
                    # Fallback: einfach Import ohne Version
                    Import-Module -Name $name -Force -ErrorAction Stop
                }
            } else {
                # ältere PowerShellGet: finde passendes Modul und installiere genau diese Version
                $foundRemote = Find-Module -Name $name -Repository 'PSGallery' -MinimumVersion $minVersion -ErrorAction Stop
                if (-not $foundRemote) {
                    & $logErr "Keine passende Version von '$name' in PSGallery gefunden (>= $minVersion)."
                    return $false
                }
                Install-Module -Name $name -RequiredVersion $foundRemote.Version -Repository 'PSGallery' -Scope $scope -Force -ErrorAction Stop -AllowClobber:($allowglobber.IsPresent)
                Import-Module -Name $name -RequiredVersion $foundRemote.Version -Force -ErrorAction Stop
            }
        } else {
            # keine Mindestversion angegeben => normale Installation der neuesten verfügbaren Version
            Install-Module @installSplat
            Import-Module -Name $name -Force -ErrorAction Stop
        }

        & $logInfo "Modul '$name' installiert und importiert."
        return $true
    }
    catch {
        & $logErr "Fehler beim Laden/Installieren von Modul '$name': $_"
        return $false
    }
}