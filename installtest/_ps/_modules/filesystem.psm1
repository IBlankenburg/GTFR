function New-FoldersIfMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Paths,

        [switch]$ForceRemove
    )

    process {
        foreach ($dir in $Paths) {
            try {
                if (Test-Path -LiteralPath $dir) {
                    if ($ForceRemove) {
                        Remove-Item -LiteralPath $dir -Recurse -Force
                        Write-LogVerbose "Removed existing folder: $dir"
                        New-Item -ItemType Directory -Path $dir -Force | Out-Null
                        Write-LogVerbose "Recreated folder: $dir"
                    }
                    else {
                        Write-LogVerbose "Folder already exists: $dir"
                    }
                }
                else {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    Write-LogVerbose "Created folder: $dir"
                }
            }
            catch {
                Write-LogWarning "Could not process folder: $dir - $($_.Exception.Message)"
            }
        }
    }
}
function Copy-Files($source, $destination) {
    try {
        # Treffer für Quelle (auch bei Wildcards)
        $items = Get-Item -Path $source -ErrorAction SilentlyContinue
        if (-not $items) {
            Write-LogWarning "Source path or pattern did not match any files: $source"
            return
        }

        # Zielordner sicherstellen
        if (-not (Test-Path -Path $destination)) {
            Write-LogVerbose "Creating destination folder: $destination"
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
        }

        # Wildcards erkennen
        $hasWildcard = [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($source)

        # Wenn Quelle ein Ordner und KEIN Pattern -> nur Inhalt kopieren
        if (-not $hasWildcard -and (Test-Path -Path $source -PathType Container)) {
            $copyFrom = Join-Path $source '*'
        }
        else {
            # Bei Datei oder Pattern -> direkt kopieren
            $copyFrom = $source
        }

        Write-LogVerbose "Copying from '$copyFrom' to '$destination'"
        Copy-Item -Path $copyFrom -Destination $destination -Recurse -Force

        Write-LogVerbose "Copy completed: '$copyFrom' -> '$destination'"
    }
    catch {
        Write-LogError "Failed to copy from $source to $destination - $($_.Exception.Message)"
    }
}
