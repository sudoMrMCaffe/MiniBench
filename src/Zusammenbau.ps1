# Fügt die Quelltextteile aus src\ zu einer einzigen LeosMinibench.ps1 zusammen.
# Verwendet von Bauen.cmd, Testen.cmd und den Pester-Tests. Läuft unter Windows PowerShell 5.1 und PowerShell 7.
#
#   . .\src\Zusammenbau.ps1
#   $r = Invoke-MinibenchBuild -SrcDir .\src -OutFile .\LeosMinibench.ps1
#   $r.Fehler    # leer, wenn alles in Ordnung ist
#
# Regeln
#   Bauplan.txt   eine Datei je Zeile (relativ zu src), Reihenfolge = Reihenfolge im Ergebnis, # leitet Kommentare ein
#   #>> EINBINDEN <Datei>   eine Zeile in einem Teil, die durch den Inhalt der Datei ersetzt wird (C#-Code, Modulverträge)
#   Alle Dateien müssen UTF-8 sein (mit oder ohne BOM). Das Ergebnis ist UTF-8 mit BOM und CRLF, wie Windows PowerShell 5.1 es braucht.

function ConvertTo-SrcPath([string]$SrcDir, [string]$Rel) {
    $r = $Rel.Trim() -replace '[\\/]', [string][IO.Path]::DirectorySeparatorChar
    return (Join-Path $SrcDir $r)
}

function Read-SrcLines([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $strict = New-Object Text.UTF8Encoding($false, $true)
    try { $t = $strict.GetString($bytes) } catch { throw ('{0} ist nicht als UTF-8 gespeichert.' -f $Path) }
    $t = $t.TrimStart([char]0xFEFF) -replace "`r`n", "`n" -replace "`r", "`n"
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    return , ($t -split "`n")
}

function Update-EmbeddedReferences([string]$SrcDir) {
    $refDir = Join-Path $SrcDir 'Daten\Referenzen'
    if (-not (Test-Path -LiteralPath $refDir)) { return }
    $files = @(Get-ChildItem -LiteralPath $refDir -Filter '*.json' | Sort-Object Name)
    if ($files.Count -eq 0) { return }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Eingebettete Referenzprofile für Leos Minibench (v3.0)')
    [void]$sb.AppendLine('$script:EmbeddedReferences = @{')
    foreach ($f in $files) {
        $json = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
        [void]$sb.AppendLine(('    ''{0}'' = @''' -f $f.Name))
        [void]$sb.AppendLine($json.Trim())
        [void]$sb.AppendLine('''@')
    }
    [void]$sb.AppendLine('}')
    $target = Join-Path $SrcDir 'Kern\Referenzen_Eingebettet.ps1'
    $utf8Bom = New-Object Text.UTF8Encoding($true)
    $text = $sb.ToString().Replace("`r`n", "`n").Replace("`n", "`r`n")
    $cur = if (Test-Path -LiteralPath $target) { [IO.File]::ReadAllText($target, [Text.Encoding]::UTF8) } else { '' }
    if ($cur -ne $text) {
        [IO.File]::WriteAllText($target, $text, $utf8Bom)
    }
}

function Invoke-MinibenchBuild {
    param(
        [Parameter(Mandatory = $true)][string]$SrcDir,
        [string]$OutFile = '',
        [switch]$Erzwingen
    )
    $SrcDir = (Resolve-Path -LiteralPath $SrcDir).Path
    try { Update-EmbeddedReferences $SrcDir } catch { }
    $fehler = New-Object System.Collections.Generic.List[string]
    $warn = New-Object System.Collections.Generic.List[string]
    $out = New-Object System.Collections.Generic.List[string]
    $map = New-Object System.Collections.Generic.List[object]   # Herkunft jeder Ausgabezeile: Datei und Zeile
    $used = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $teile = New-Object System.Collections.Generic.List[string]

    $plan = Join-Path $SrcDir 'Bauplan.txt'
    if (-not (Test-Path -LiteralPath $plan)) { throw ('Bauplan.txt fehlt in {0}.' -f $SrcDir) }
    $planLines = @(Read-SrcLines $plan | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })

    foreach ($rel in $planLines) {
        $p = ConvertTo-SrcPath $SrcDir $rel
        if (-not (Test-Path -LiteralPath $p)) { $fehler.Add(('Bauplan: {0} fehlt.' -f $rel)); continue }
        [void]$used.Add((Resolve-Path -LiteralPath $p).Path)
        $teile.Add($rel)
        $lines = Read-SrcLines $p
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i]
            if ($ln -match '^\s*#>> EINBINDEN\s+(.+?)\s*$') {
                $incRel = $Matches[1]
                $ip = ConvertTo-SrcPath $SrcDir $incRel
                if (-not (Test-Path -LiteralPath $ip)) { $fehler.Add(('{0}, Zeile {1}: einzubindende Datei {2} fehlt.' -f $rel, ($i + 1), $incRel)); continue }
                [void]$used.Add((Resolve-Path -LiteralPath $ip).Path)
                $inc = Read-SrcLines $ip
                for ($k = 0; $k -lt $inc.Count; $k++) {
                    # Ein Zeilenanfang '@ oder "@ würde den Here-String vorzeitig beenden
                    if ($inc[$k] -match "^\s*['""]@") { $fehler.Add(('{0}, Zeile {1}: beginnt mit {2} und würde den Here-String beenden.' -f $incRel, ($k + 1), $inc[$k].Trim().Substring(0, 2))) }
                    if ($inc[$k] -match '^\s*#>> EINBINDEN') { $fehler.Add(('{0}, Zeile {1}: verschachteltes EINBINDEN wird nicht unterstützt.' -f $incRel, ($k + 1))) }
                    $out.Add($inc[$k]); $map.Add([pscustomobject]@{ Datei = $incRel; Zeile = $k + 1 })
                }
                continue
            }
            $out.Add($ln); $map.Add([pscustomobject]@{ Datei = $rel; Zeile = $i + 1 })
        }
    }

    # Dateien in src, die weder im Bauplan stehen noch eingebunden werden, gehen beim Bauen verloren
    # Endung per Where-Object: -Include wirkt in Windows PowerShell 5.1 zusammen mit -LiteralPath nicht (alle Dateien kämen durch)
    foreach ($f in @(Get-ChildItem -LiteralPath $SrcDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.ps1', '.cs', '.psd1' })) {
        if ($f.Name -eq 'Zusammenbau.ps1') { continue }
        if (-not $used.Contains($f.FullName)) { $warn.Add(('{0} wird nicht verwendet (fehlt im Bauplan).' -f $f.FullName.Substring($SrcDir.Length).TrimStart('\', '/'))) }
    }

    $text = ($out -join "`r`n") + "`r`n"
    $tokens = $null; $perr = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$perr)
    foreach ($e in @($perr)) {
        $n = $e.Extent.StartLineNumber
        $src = $(if ($n -ge 1 -and $n -le $map.Count) { '{0}, Zeile {1}' -f $map[$n - 1].Datei, $map[$n - 1].Zeile } else { 'Zeile ' + $n })
        $fehler.Add(('Syntax: {0}: {1}' -f $src, $e.Message))
    }
    $ver = ''
    if ($text -match '(?m)^\$ScriptVersion\s*=\s*''([^'']+)''') { $ver = $Matches[1] } else { $fehler.Add('$ScriptVersion wurde nicht gefunden.') }

    $written = ''
    if ($OutFile -and (-not $fehler.Count -or $Erzwingen)) {
        [IO.File]::WriteAllText($OutFile, $text, (New-Object Text.UTF8Encoding($true)))
        $written = $OutFile
    }
    return [pscustomobject]@{
        Datei = $written; Version = $ver; Zeilen = $out.Count; Teile = $teile.ToArray()
        Fehler = $fehler.ToArray(); Warnungen = $warn.ToArray(); Text = $text; Herkunft = $map.ToArray()
    }
}
