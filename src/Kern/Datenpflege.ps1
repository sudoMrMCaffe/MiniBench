#region ---------- Datenpflege (ab v2.7): nicht vergleichbare Lasttests, unvollständige und kurze Läufe ins Archiv ----------
# Lasttestergebnisse sind erst ab dieser Version untereinander vergleichbar: v2.67 hat die CPU- und RAM-Last in einen
# eigenen Prozess verlegt und die Rechenschleife umgebaut (Sinus als Polynom, andere Rechendurchläufe, keine
# Unterbrechungen durch die Speicherbereinigung). Das Rechenwerk des Benchmarks blieb gleich, Benchmark- und
# Diagnoseläufe älterer Versionen bleiben deshalb in der Datenbank (Entscheidung vom 03.10.2026).
$script:MessreiheAb = '2.67'

# Versionsnummer als Dezimalzahl: 2.7 liegt nach 2.67 (2.70), [version] würde 2.7 vor 2.67 einordnen
function ConvertTo-VersionNumber([string]$Version) {
    $v = ([string]$Version).Trim().TrimStart('v', 'V')
    if ($v -match '^(\d+)(?:\.(\d+))?') {
        $d = 0.0
        $txt = '{0}.{1}' -f $Matches[1], $(if ($Matches[2]) { $Matches[2] } else { '0' })
        if ([double]::TryParse($txt, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    }
    return 0.0
}

# Ist ein Lasttest dieser Version mit heutigen Lasttests vergleichbar?
function Test-MessreiheAktuell([string]$Version) { return ((ConvertTo-VersionNumber $Version) -ge (ConvertTo-VersionNumber $script:MessreiheAb)) }

function Read-DatenpflegeJson([string]$Path) {
    try { return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

# Dauer "hh:mm:ss" aus dem Lasttest-Text eines Datenbankeintrags in Sekunden (oder $null)
function Get-DatenpflegeDauer([string]$Text) {
    if ($Text -match 'Dauer (\d+):(\d\d):(\d\d)') { return ([int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3]) }
    return $null
}

# Einordnung eines Datenbankeintrags. Rückgabe: '' (behalten) oder Objekt mit Ziel (Unterordner im Archiv) und Grund.
#   Messreihe     Lauf mit Lasttest aus einer Version vor $script:MessreiheAb (Benchmark und Diagnose allein bleiben)
#   Kurz          Lasttest von Hand vorzeitig beendet und kürzer als die Hälfte der geplanten Dauer, Lauf ohne jedes
#                 Messergebnis (kein Wert, kein Lasttest) oder Funktionstest; jeweils nur, wenn keine Diagnose dabei war
# Ein Lasttest, den die Abbruchschwelle beendet hat, ist ein Befund und bleibt.
function Get-DatenpflegeEinordnung($Entry) {
    if (-not $Entry) { return $null }
    $mod = [string]$Entry.Module
    $werte = @(); if ($Entry.Werte) { $werte = @($Entry.Werte.PSObject.Properties) }
    $last = [string]$Entry.Lasttest
    $hatLast = [bool]$last -or ($mod -match 'Lasttest')
    if ($hatLast -and -not (Test-MessreiheAktuell ([string]$Entry.Version))) {
        return [pscustomobject]@{ Ziel = ('Lasttest_vor_v{0}' -f $script:MessreiheAb); Art = 'Messreihe'; Grund = ('Lasttest aus v{0}, mit Lasttests ab v{1} nicht vergleichbar' -f $Entry.Version, $script:MessreiheAb) }
    }
    $diag = ($mod -match 'Diagnose \((vollständig|schnell|benutzerdefiniert)') -or ($mod -match 'Reparatur')
    if ($diag) { return $null }
    if ($mod -match 'Diagnose \(Funktionstest\)') { return [pscustomobject]@{ Ziel = 'Kurz'; Art = 'Kurz'; Grund = 'Funktionstest (prüft nur das Skript)' } }
    if (-not $werte.Count -and -not $last -and $mod -match 'Benchmark|Lasttest') { return [pscustomobject]@{ Ziel = 'Kurz'; Art = 'Kurz'; Grund = 'Lauf ohne Messergebnis' } }
    if ($last -match 'vorzeitig beendet' -and -not $werte.Count) {
        $dauer = Get-DatenpflegeDauer $last
        $plan = @([regex]::Matches($mod, '(\d+) Min\.') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Descending) | Select-Object -First 1
        if ($null -ne $dauer -and $plan -and $dauer -lt ($plan * 60 / 2)) {
            return [pscustomobject]@{ Ziel = 'Kurz'; Art = 'Kurz'; Grund = ('Lasttest nach {0} s von Hand beendet (geplant {1} Min.)' -f $dauer, $plan) }
        }
    }
    return $null
}

# Berichtsordner vollständig? (Bericht als TXT oder HTML vorhanden)
function Test-BerichtVollstaendig([string]$Dir) {
    return ((Test-Path -LiteralPath (Join-Path $Dir 'Diagnosebericht.txt')) -or (Test-Path -LiteralPath (Join-Path $Dir 'Diagnosebericht.html')))
}

# Zielpfad ohne Überschreiben: bei Namensgleichheit _2, _3 ...
function Get-DatenpflegeZiel([string]$Dir, [string]$Leaf, [switch]$Ordner) {
    $t = Join-Path $Dir $Leaf
    $n = 2
    $base = [IO.Path]::GetFileNameWithoutExtension($Leaf); $ext = [IO.Path]::GetExtension($Leaf)
    if ($Ordner) { $ext = ''; $base = $Leaf }
    while (Test-Path -LiteralPath $t) { $t = Join-Path $Dir ('{0}_{1}{2}' -f $base, $n, $ext); $n++ }
    return $t
}

# Plan und Ausführung. -NurPlan zeigt nur, was geschähe. -MindestAlterMin schützt frische Läufe (Start der Oberfläche: 60).
# -ArchivDir: Ziel (Standard: Minibench-Daten\Archiv; Bauen.cmd nimmt das Archiv des Projektordners).
# Rückgabe: Objekt mit Verschoben, Geloescht, Fehler, Zeilen (Text je Eintrag) und Kurz (eine Zeile für die Oberfläche).
function Invoke-Datenpflege {
    param([string]$DataDir = $script:DataDir, [string]$ArchivDir = '', [switch]$NurPlan, [int]$MindestAlterMin = 0)
    $res = [pscustomobject]@{ Verschoben = 0; Geloescht = 0; Fehler = 0; Zeilen = (New-Object System.Collections.Generic.List[string]); Kurz = ''; Archiv = ''; BytesGeloescht = 0L; BytesVerschoben = 0L; FreigegebenMB = 0.0 }
    if (-not $DataDir -or -not (Test-Path -LiteralPath $DataDir)) { $res.Kurz = 'kein Datenordner'; return $res }
    if (-not $ArchivDir) { $ArchivDir = Join-Path $DataDir 'Archiv' }
    $res.Archiv = $ArchivDir
    $now = Get-Date
    $dbDir = Join-Path $DataDir 'Datenbank'; $repDir = Join-Path $DataDir 'Berichte'
    $plan = New-Object System.Collections.Generic.List[object]
    $add = { param($Pfad, $Unterordner, $Grund, $Art) $plan.Add([pscustomobject]@{ Pfad = $Pfad; Unterordner = $Unterordner; Grund = $Grund; Art = $Art }) }
    $alt = { param($p) try { $i = Get-Item -LiteralPath $p -Force -ErrorAction Stop; return (($now - $i.LastWriteTime).TotalMinutes -ge $MindestAlterMin) } catch { return $false } }
    $getSize = {
        param($p)
        try {
            if (-not (Test-Path -LiteralPath $p)) { return 0L }
            if (Test-Path -LiteralPath $p -PathType Leaf) { return (Get-Item -LiteralPath $p -Force).Length }
            $sum = 0L
            foreach ($item in @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue)) {
                $sum += $item.Length
            }
            return $sum
        } catch { return 0L }
    }

    # Läufe, deren Absturzanalyse noch aussteht (laufend.json), bleiben unangetastet
    $busy = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($lf in @(Get-ChildItem -LiteralPath (Join-Path $DataDir 'Laufzeit') -Filter 'laufend.json' -Recurse -File -ErrorAction SilentlyContinue)) {
        $j = Read-DatenpflegeJson $lf.FullName
        if ($j -and $j.OutputDir) { [void]$busy.Add(@(([string]$j.OutputDir).TrimEnd('\', '/') -split '[\\/]')[-1]) }
    }

    # 1. Datenbankeinträge mit ihren Berichtsordnern
    $taken = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $keep = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @(Get-ChildItem -LiteralPath $dbDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $e = Read-DatenpflegeJson $f.FullName
        if (-not $e) {
            # 0-Byte oder beschädigte JSON-Datei ins Archiv verschieben
            if (& $alt $f.FullName) {
                & $add $f.FullName (Join-Path 'Beschaedigt' 'Datenbank') 'beschädigte oder leere JSON-Datei' 'Beschädigt'
            }
            continue
        }
        $ein = Get-DatenpflegeEinordnung $e
        # Ordner relativ zum Datenordner (Berichte\<Lauf>) oder absolut; Trenner \ oder /
        $leaf = $(if ($e.Ordner) { @(([string]$e.Ordner).TrimEnd('\', '/') -split '[\\/]')[-1] } else { '' })
        if ($leaf -and $busy.Contains($leaf)) { [void]$keep.Add($f.Name); continue }

        # Verwaister Datenbankeintrag: Ordner war benannt, existiert aber im Berichtsordner nicht mehr
        if (-not $ein -and $leaf -and (& $alt $f.FullName)) {
            $rd = Join-Path $repDir $leaf
            if (-not (Test-Path -LiteralPath $rd -PathType Container)) {
                $ein = [pscustomobject]@{ Ziel = 'Verwaist'; Art = 'Verwaist'; Grund = ('zugehöriger Berichtsordner nicht mehr vorhanden ({0})' -f $leaf) }
            }
        }

        if (-not $ein) { [void]$keep.Add($f.Name); continue }
        if ($ein.Art -eq 'Kurz' -and -not (& $alt $f.FullName)) { [void]$keep.Add($f.Name); continue }
        & $add $f.FullName (Join-Path $ein.Ziel 'Datenbank') $ein.Grund $ein.Art
        if ($leaf) {
            $rd = Join-Path $repDir $leaf
            if (Test-Path -LiteralPath $rd -PathType Container) { & $add $rd (Join-Path $ein.Ziel 'Berichte') $ein.Grund $ein.Art; [void]$taken.Add($leaf) }
        }
    }

    # 2. Berichtsordner ohne Datenbankeintrag: ohne Bericht (abgebrochen, leer) oder Lasttest vor v2.67
    #    (Version und Module stehen im Kopf von Diagnosebericht.txt)
    foreach ($d in @(Get-ChildItem -LiteralPath $repDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'Vergleiche' } | Sort-Object Name)) {
        if ($taken.Contains($d.Name) -or $busy.Contains($d.Name)) { continue }
        if (Test-BerichtVollstaendig $d.FullName) {
            $kopf = ''; try { $kopf = (Get-Content -LiteralPath (Join-Path $d.FullName 'Diagnosebericht.txt') -TotalCount 8 -Encoding UTF8 -ErrorAction Stop) -join "`n" } catch { }
            if ($kopf -match 'DIAGNOSEBERICHT\s+\S+\s+v([\d.]+)') {
                $kv = $Matches[1]
                if ($kopf -match 'Module\s*:\s*.*Lasttest' -and -not (Test-MessreiheAktuell $kv)) { & $add $d.FullName (Join-Path ('Lasttest_vor_v{0}' -f $script:MessreiheAb) 'Berichte') ('Lasttest aus v{0}, mit Lasttests ab v{1} nicht vergleichbar' -f $kv, $script:MessreiheAb) 'Messreihe' }
            }
            continue
        }
        if (-not (& $alt $d.FullName)) { continue }
        $files = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
        & $add $d.FullName (Join-Path 'Unvollstaendig' 'Berichte') $(if ($files.Count) { 'Lauf ohne Bericht (abgebrochen; Teilbericht und Rohdaten bleiben im Archiv)' } else { 'leerer Berichtsordner' }) 'Unvollständig'
    }

    # 3. Systemvergleiche, deren Quellen nicht mehr in der Datenbank stehen. Ein Vergleich nennt im Fuß seine Quellen
    #    ("Leos Minibench 2.65. Quellen: a.json, b.json"). Die Referenz (Referenz.json) bleibt: sie enthält nur Benchmarkwerte.
    $vgl = Join-Path $repDir 'Vergleiche'
    foreach ($v in @(Get-ChildItem -LiteralPath $vgl -Filter '*.html' -File -ErrorAction SilentlyContinue)) {
        $txt = ''; try { $txt = [IO.File]::ReadAllText($v.FullName, [Text.Encoding]::UTF8) } catch { continue }
        $src = @(); if ($txt -match 'Quellen: ([^<]+)</footer>') { $src = @($Matches[1] -split ',\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        $out = @($src | Where-Object { $n = $_; @($plan | Where-Object { $_.Pfad -like ('*' + $n) }).Count })
        if ($out.Count) { & $add $v.FullName (Join-Path ('Lasttest_vor_v{0}' -f $script:MessreiheAb) 'Vergleiche') ('Systemvergleich mit Läufen, die ins Archiv gehen ({0})' -f ($out -join ', ')) 'Vergleich' }
    }

    # 4. Werkzeuge: Aus smartmontools braucht Leos Minibench nur smartctl.exe und dessen Laufwerksdatenbank drivedb.h.
    #    Der Rest des Pakets (smartd, Mailer, Updater, Hilfsprogramme) liegt ungenutzt im Tools-Ordner.
    $smb = Join-Path (Join-Path (Join-Path $DataDir 'Tools') 'smartmontools') 'bin'
    foreach ($x in @(Get-ChildItem -LiteralPath $smb -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'smartctl.exe', 'drivedb.h' })) {
        & $add $x.FullName (Join-Path (Join-Path 'Werkzeuge_unbenutzt' 'smartmontools') 'bin') 'Teil von smartmontools, den Leos Minibench nicht ausführt (gebraucht werden nur smartctl.exe und drivedb.h)' 'Werkzeug'
    }

    # 5. Ausführen
    foreach ($p in $plan) {
        $rel = $p.Pfad.Substring($DataDir.Length).TrimStart('\', '/')
        $zielDir = Join-Path $ArchivDir $p.Unterordner
        $line = ('{0} -> {1}: {2}' -f $rel, $p.Unterordner, $p.Grund)
        if ($NurPlan) { $res.Zeilen.Add('geplant: ' + $line); continue }
        try {
            $sz = & $getSize $p.Pfad
            New-Item -ItemType Directory -Path $zielDir -Force -ErrorAction Stop | Out-Null
            $ziel = Get-DatenpflegeZiel $zielDir (Split-Path $p.Pfad -Leaf) -Ordner:(Test-Path -LiteralPath $p.Pfad -PathType Container)
            Move-Item -LiteralPath $p.Pfad -Destination $ziel -ErrorAction Stop
            $res.Verschoben++
            $res.BytesVerschoben += $sz
            $res.Zeilen.Add($line)
        } catch { $res.Fehler++; $res.Zeilen.Add(('nicht verschoben: {0} ({1})' -f $line, $_.Exception.Message)) }
    }

    # 6. Reste ohne Wert löschen: ältere Übersetzungen im Cache (sie entstehen bei Bedarf neu) und verwaiste Laufzeitdaten
    if (-not $NurPlan) {
        $cache = Join-Path $DataDir 'Cache'
        $groups = @(Get-ChildItem -LiteralPath $cache -Filter 'LeosMinibench-*.dll' -File -ErrorAction SilentlyContinue | Group-Object { $_.Name -replace '-[0-9a-f]{12}\.dll$', '' })
        foreach ($g in $groups) {
            foreach ($x in @($g.Group | Sort-Object LastWriteTime -Descending | Select-Object -Skip 1)) {
                try {
                    $sz = & $getSize $x.FullName
                    Remove-Item -LiteralPath $x.FullName -Force -ErrorAction Stop
                    $res.Geloescht++
                    $res.BytesGeloescht += $sz
                    $res.Zeilen.Add(('Cache\{0} gelöscht: ältere Übersetzung' -f $x.Name))
                } catch { }
            }
        }
        $lz = Join-Path $DataDir 'Laufzeit'
        if (Test-Path -LiteralPath $lz) {
            # Stoppdateien, verwaiste Locks und abgebrochene Checkpoints im Laufzeitordner
            foreach ($pc in @(Get-ChildItem -LiteralPath $lz -Directory -ErrorAction SilentlyContinue)) {
                $hasActiveRun = $false
                $lf = Join-Path $pc.FullName 'laufend.json'
                if (Test-Path -LiteralPath $lf) {
                    $fi = Get-Item -LiteralPath $lf -Force -ErrorAction SilentlyContinue
                    if ($fi -and ($now - $fi.LastWriteTime).TotalDays -lt 7) { $hasActiveRun = $true }
                    else {
                        try {
                            $sz = & $getSize $lf
                            Remove-Item -LiteralPath $lf -Force -ErrorAction Stop
                            $res.Geloescht++; $res.BytesGeloescht += $sz
                            $res.Zeilen.Add(('Laufzeit\{0}\laufend.json gelöscht: veralteter Laufzeit-Marker' -f $pc.Name))
                        } catch { }
                    }
                }
                if (-not $hasActiveRun) {
                    foreach ($s in @(Get-ChildItem -LiteralPath $pc.FullName -Filter 'sensor.stop' -File -ErrorAction SilentlyContinue | Where-Object { ($now - $_.LastWriteTime).TotalMinutes -ge 30 })) {
                        try {
                            $sz = & $getSize $s.FullName
                            Remove-Item -LiteralPath $s.FullName -Force -ErrorAction Stop
                            $res.Geloescht++; $res.BytesGeloescht += $sz
                            $res.Zeilen.Add(('Laufzeit\{0}\sensor.stop gelöscht: Rest der Live-Ansicht' -f $pc.Name))
                        } catch { }
                    }
                    # -Include wirkt unter PS 5.1 ohne -Recurse nicht, daher Namensfilter per Where-Object (ab v3.54)
                    foreach ($tmp in @(Get-ChildItem -LiteralPath $pc.FullName -File -ErrorAction SilentlyContinue | Where-Object { ($_.Name -like '*.tmp' -or $_.Name -like '*.lock' -or $_.Name -like 'checkpoint*.json') -and ($now - $_.LastWriteTime).TotalHours -ge 2 })) {
                        try {
                            $sz = & $getSize $tmp.FullName
                            Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction Stop
                            $res.Geloescht++; $res.BytesGeloescht += $sz
                            $res.Zeilen.Add(('Laufzeit\{0}\{1} gelöscht: verwaiste temporäre Datei' -f $pc.Name, $tmp.Name))
                        } catch { }
                    }
                }
                if (-not @(Get-ChildItem -LiteralPath $pc.FullName -Force -ErrorAction SilentlyContinue).Count) {
                    try { Remove-Item -LiteralPath $pc.FullName -Force -ErrorAction Stop } catch { }
                }
            }
            # Wurzel-Dateien im Laufzeitordner: nur temporäre Reste. PawnIO_<PC>.txt (Merker für die Entfernung des Treibers
            # nach einem Absturz) und Start.log bleiben (bis 3.53 wurde alles älter als 2 Stunden gelöscht).
            foreach ($rt in @(Get-ChildItem -LiteralPath $lz -File -ErrorAction SilentlyContinue | Where-Object { ($_.Name -like '*.tmp' -or $_.Name -like '*.lock') -and ($now - $_.LastWriteTime).TotalHours -ge 2 })) {
                try {
                    $sz = & $getSize $rt.FullName
                    Remove-Item -LiteralPath $rt.FullName -Force -ErrorAction Stop
                    $res.Geloescht++; $res.BytesGeloescht += $sz
                    $res.Zeilen.Add(('Laufzeit\{0} gelöscht: temporärer Rest' -f $rt.Name))
                } catch { }
            }
        }
    }

    $res.FreigegebenMB = [math]::Round($res.BytesGeloescht / 1MB, 2)

    # 7. Protokoll im Archiv
    if (-not $NurPlan -and ($res.Verschoben -or $res.Geloescht -or $res.Fehler)) {
        try {
            New-Item -ItemType Directory -Path $ArchivDir -Force -ErrorAction Stop | Out-Null
            $log = New-Object System.Text.StringBuilder
            [void]$log.AppendLine(('{0:yyyy-MM-dd HH:mm} Datenpflege v{1}, Datenordner {2}' -f $now, $ScriptVersion, $DataDir))
            [void]$log.AppendLine(('  Status: {0} Läufe/Einträge verschoben, {1} temporäre Dateien/Reste bereinigt, {2:N2} MB freigegeben' -f $res.Verschoben, $res.Geloescht, $res.FreigegebenMB))
            foreach ($z in $res.Zeilen) { [void]$log.AppendLine('  ' + $z) }
            [IO.File]::AppendAllText((Join-Path $ArchivDir 'Datenpflege.log'), $log.ToString(), (New-Object Text.UTF8Encoding($true)))
        } catch { }
    }
    $nM = @($plan | Where-Object { $_.Art -eq 'Messreihe' -and $_.Pfad -like '*.json' -and $_.Pfad -like ($dbDir + '*') }).Count
    $nU = @($plan | Where-Object { $_.Art -eq 'Unvollständig' }).Count
    $nK = @($plan | Where-Object { $_.Art -eq 'Kurz' -and $_.Pfad -like ($dbDir + '*') }).Count
    $nV = @($plan | Where-Object { $_.Art -in 'Verwaist', 'Beschädigt' }).Count
    $parts = @()
    if ($nM) { $parts += ('{0} {1} vor v{2}' -f $nM, $(if ($nM -eq 1) { 'Lasttest' } else { 'Lasttests' }), $script:MessreiheAb) }
    if ($nK) { $parts += ('{0} {1}' -f $nK, $(if ($nK -eq 1) { 'kurzer Lauf' } else { 'kurze Läufe' })) }
    if ($nU) { $parts += ('{0} {1}' -f $nU, $(if ($nU -eq 1) { 'unvollständiger Lauf' } else { 'unvollständige Läufe' })) }
    if ($nV) { $parts += ('{0} verwaiste {1}' -f $nV, $(if ($nV -eq 1) { 'Eintrag' } else { 'Einträge' })) }
    $nW = @($plan | Where-Object { $_.Art -eq 'Werkzeug' }).Count
    if ($nW) { $parts += ('{0} ungenutzte {1} von smartmontools' -f $nW, $(if ($nW -eq 1) { 'Datei' } else { 'Dateien' })) }
    $res.Kurz = $(if ($parts.Count) { '{0} {1}{2}' -f ($parts -join ', '), $(if ($NurPlan) { 'würden ins Archiv verschoben' } else { 'ins Archiv verschoben' }), $(if ($res.Fehler) { ', {0} nicht möglich' -f $res.Fehler } else { '' }) } else { 'nichts zu archivieren' })
    return $res
}

# Aufruf über die Befehlszeile (Bauen.cmd) oder die Oberfläche (Schaltfläche Aufräumen): -Datenpflege [-ArchivDir <Ordner>]
if ($Datenpflege) {
    $dp = Invoke-Datenpflege -DataDir $script:DataDir -ArchivDir $ArchivDir
    foreach ($z in $dp.Zeilen) { Write-Host ('  ' + $z) }
    $cleanText = $(if ($dp.Geloescht -gt 0) { (' ({0} Temp-Dateien bereinigt, {1:N1} MB frei)' -f $dp.Geloescht, $dp.FreigegebenMB) } else { '' })
    Write-Host ('Datenpflege: {0}{1}. Archiv: {2}' -f $dp.Kurz, $cleanText, $dp.Archiv)
    Send-GuiEvent 'RESULT' ('{0}{1}' -f $dp.Kurz, $cleanText)
    exit $(if ($dp.Fehler) { 1 } else { 0 })
}
#endregion
