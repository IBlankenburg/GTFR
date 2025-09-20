function Merge-NUnitResults {
    param(
        [string]$SourceFolder = 'C:\reports',
        [string]$Pattern      = '*_step.xml',
        [string]$OutputFile   = 'C:\reports\result.xml'
    )

    $files = Get-ChildItem -Path (Join-Path $SourceFolder $Pattern) -File
    if (-not $files) {
        Write-Warning "Keine Dateien gefunden unter $SourceFolder\$Pattern"
        return
    }

    # erste Datei als Basis
    [xml]$base = Get-Content $files[0].FullName
    $root = $base.DocumentElement   # z.B. <test-results> oder <test-run>

    foreach ($f in $files[1..($files.Count-1)]) {
        [xml]$x = Get-Content $f.FullName
        $r = $x.DocumentElement

        # Kinder übernehmen
        foreach ($child in $r.ChildNodes) {
            $import = $base.ImportNode($child, $true)
            $root.AppendChild($import) | Out-Null
        }

        # Zähler-Attribute summieren (falls numerisch)
        foreach ($attr in $r.Attributes) {
            if ($attr.Value -as [int]) {
                $old = [int]($root.GetAttribute($attr.Name))
                $root.SetAttribute($attr.Name, ($old + [int]$attr.Value))
            }
        }
    }

    $base.Save($OutputFile)
    Write-Host "Merge abgeschlossen: $OutputFile"
}
