# ---------- Referenzwerte (Baseline) ----------
# Ab v2.65 gibt es keine eingebauten Referenzwerte mehr. Referenz (100 %) ist nur, was mit "Dieses System als Referenz
# festlegen" (-ReferenzSpeichern) in Minibench-Daten\Referenz.json gespeichert wurde, oder auf Wunsch der Median der
# Vergleichsdatenbank bzw. eine gewählte Datei (-ReferenzDatei). Ohne Referenz zeigt der Benchmark Index und Verlauf.
# Laufwerke werden nach Klasse verglichen.
$script:RefNone = @{ Name = ''; Datum = ''; Quelle = ''; Werte = @{}; Herkunft = @{} }
$script:Ref = $script:RefNone
$script:RefSavedNow = $false   # ab v2.8: in diesem Lauf als Referenz gespeichert
$script:BenchDisks = [System.Collections.Generic.List[object]]::new()
$script:BenchGroupOrder = @('CPU', 'RAM', 'GPU', 'Laufwerke', 'WinSAT')
$script:BenchGroupNames = @{ 'CPU' = 'Prozessor'; 'RAM' = 'Arbeitsspeicher'; 'GPU' = 'Grafik'; 'Laufwerke' = 'Laufwerke'; 'WinSAT' = 'WinSAT-Bewertung' }
$script:BenchHead = @{}
$script:WinsatTotal = 0.0
$script:BenchShort = @{}
$script:BenchRefSummary = ''
$script:BenchRefName = ''

# Messgrößen für Referenz, Vergleich und Datenbank
$script:MetricDefs = @(
    @{ K = 'CPU|ST';        N = 'Prozessor Einzelkern';    U = 'Punkte';   F = 'N0' }
    @{ K = 'CPU|MT';        N = 'Prozessor Mehrkern';      U = 'Punkte';   F = 'N0' }
    @{ K = 'CPU|AES';       N = 'AES-256 verschlüsseln';   U = 'MB/s';     F = 'N0' }
    @{ K = 'CPU|SHA';       N = 'SHA-256 Prüfsumme';       U = 'MB/s';     F = 'N0' }
    @{ K = 'CPU|DEFL';      N = 'Kompression (Deflate)';   U = 'MB/s';     F = 'N0' }
    @{ K = 'RAM|Lesen';     N = 'RAM Lesen';               U = 'GB/s';     F = 'N1' }
    @{ K = 'RAM|Schreiben'; N = 'RAM Schreiben';           U = 'GB/s';     F = 'N1' }
    @{ K = 'RAM|Kopieren';  N = 'RAM Kopieren';            U = 'GB/s';     F = 'N1' }
    @{ K = 'RAM|Latenz';    N = 'RAM Latenz';              U = 'ns';       F = 'N0'; L = $true }
    @{ K = 'GPU|VMB';       N = 'Grafikspeicher-Durchsatz'; U = 'GB/s';    F = 'N1' }
    @{ K = 'GPU|DWM';       N = 'Desktop-Komposition';     U = 'Bilder/s'; F = 'N0' }
    # ab v2.6: eigener Rendertest (Direct3D 11), Leitwert = Grafikkarte, sonst die einzige Grafikeinheit
    @{ K = 'GPU|REND';      N = 'Rendertest';              U = 'Bilder/s'; F = 'N0' }
    @{ K = 'GPU|REND1';     N = 'Rendertest 1-%-Low';      U = 'Bilder/s'; F = 'N0' }
    @{ K = 'GPU|RPKT';      N = 'Rendertest Punktzahl';    U = 'Punkte';   F = 'N0' }
)
$script:DiskClassNames = [ordered]@{ 'NVMe5' = 'NVMe PCIe 5.0'; 'NVMe4' = 'NVMe PCIe 4.0'; 'NVMe3' = 'NVMe PCIe 3.0'; 'SATA-SSD' = 'SATA-SSD'; 'HDD' = 'Festplatte' }

function Read-JsonFile([string]$Path) {
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function ConvertTo-ValueTable($Obj) {
    $w = @{}
    if ($Obj) { foreach ($p in $Obj.PSObject.Properties) { try { $w[$p.Name] = [double]$p.Value } catch { } } }
    return $w
}

# Alle Systeme der Vergleichsdatenbank (Format 1 und 2; Format 2 trägt die Geräteidentität)
function Get-DbEntries {
    $list = [System.Collections.Generic.List[object]]::new()
    if (-not $script:DbDir -or -not (Test-Path $script:DbDir)) { return @() }
    foreach ($f in Get-ChildItem -LiteralPath $script:DbDir -Filter '*.json' -File -ErrorAction SilentlyContinue) {
        $j = Read-JsonFile $f.FullName
        if (-not $j) { continue }
        $list.Add([pscustomobject]@{
            Path = $f.FullName; Name = [string]$j.Name; Computer = [string]$j.Computer; Datum = [string]$j.Datum
            Werte = (ConvertTo-ValueTable $j.Werte); Messwerte = (ConvertTo-ValueTable $j.Messwerte); Messdauer = [string]$j.Messdauer
            Hardware = $j.Hardware; Befunde = $j.Befunde; Laufwerke = @($j.Laufwerke); Ordner = [string]$j.Ordner
            Format = [string]$j.Format; GeraetId = $(if ($j.Geraet) { [string]$j.Geraet.Id } else { '' }); Version = [string]$j.Version; Quelle = [string]$j.Quelle
        })
    }
    Set-DbDeviceKeys $list
    return $list.ToArray()
}

# Je Gerät nur der neueste Eintrag mit Messwerten; -ExcludeCurrent lässt das Gerät dieses Laufs weg
function Get-DbLatest($Entries, [switch]$ExcludeCurrent) {
    $dev = $(if ($ExcludeCurrent) { (Get-DeviceIdentity).Id } else { '' })
    @($Entries | Where-Object { $_.Werte.Count -and $_.Computer -and -not ($ExcludeCurrent -and (Test-SameDevice $_ $dev $env:COMPUTERNAME)) } | Group-Object GeraetKey |
        ForEach-Object { $_.Group | Sort-Object Datum -Descending | Select-Object -First 1 })
}

# Kleinere Werte sind besser (Latenzen)
function Test-LowerBetterKey([string]$Key) { return ($Key -match '\|Latenz$') }

# Gespeicherte Referenz (Referenz.json im Datenordner, ältere Ablage PC-Diagnose-Referenz.json), sonst $null
function Get-SavedReference([string]$Path = '') {
    $cands = @()
    if ($Path) { $cands += $Path }
    if ($script:DataDir) { $cands += (Join-Path $script:DataDir 'Referenz.json'), (Join-Path $script:DataDir 'PC-Diagnose-Referenz.json') }
    foreach ($f in $cands) {
        if (-not $f -or -not (Test-Path -LiteralPath $f)) { continue }
        $j = Read-JsonFile $f
        if (-not $j) { continue }
        $w = ConvertTo-ValueTable $j.Werte
        if (-not $w.Count) { continue }
        $h = @{}
        if ($j.Herkunft) { foreach ($p in $j.Herkunft.PSObject.Properties) { $h[$p.Name] = [string]$p.Value } }
        return @{ Name = [string]$j.Name; Datum = [string]$j.Datum; Werte = $w; Herkunft = $h; Quelle = $f; Computer = [string]$j.Computer; GeraetId = [string]$j.GeraetId }
    }
    return $null
}

function Import-BenchReference {
    $script:Ref = $script:RefNone
    if ($ReferenzDatei -eq '*median') {
        $entries = @(Get-DbLatest (Get-DbEntries) -ExcludeCurrent)
        if ($entries.Count) {
            $w = @{}
            $keys = @($entries | ForEach-Object { $_.Werte.Keys } | Select-Object -Unique)
            foreach ($k in $keys) { $m = Get-Median @($entries | ForEach-Object { $_.Werte[$k] } | Where-Object { $_ -gt 0 }); if ($m) { $w[$k] = [math]::Round($m, 1) } }
            $script:Ref = @{ Name = ('Median von {0} Systemen der Vergleichsdatenbank' -f $entries.Count); Datum = (Get-Date).ToString('yyyy-MM-dd', $script:Inv); Werte = $w; Herkunft = @{}; Quelle = 'Vergleichsdatenbank' }
            return
        }
        Add-Line '  Die Vergleichsdatenbank enthält noch keine anderen Systeme, daher gilt die gespeicherte Referenz.'
    }
    $r = Get-SavedReference $(if ($ReferenzDatei -and $ReferenzDatei -ne '*median') { $ReferenzDatei } else { '' })
    if ($r) { $script:Ref = $r }
}

# Gibt es eine Referenz mit Werten?
function Test-HasReference { return [bool]($script:Ref -and $script:Ref.Werte -and $script:Ref.Werte.Count) }

# Name einer Messgröße für Tabellen (Schlüssel wie CPU|ST oder DISK|NVMe4|SR)
function Get-MetricName([string]$Key) {
    $d = @($script:MetricDefs | Where-Object { $_.K -eq $Key }) | Select-Object -First 1
    if ($d) { return $d.N }
    if ($Key -match '^DISK\|([^|]+)\|(\w+)$') {
        $cls = $(if ($script:DiskClassNames.Contains($Matches[1])) { $script:DiskClassNames[$Matches[1]] } else { $Matches[1] })
        $kind = @{ SR = 'seq. lesen'; SW = 'seq. schreiben'; R1 = '4K zufällig QD1'; R8 = '4K zufällig 8 Threads'; W1 = '4K zufällig schreiben QD1' }[$Matches[2]]
        return ('{0} {1}' -f $cls, $(if ($kind) { $kind } else { $Matches[2] }))
    }
    return $Key
}

# Referenzwerte der in diesem Lauf verglichenen Messgrößen mit Herkunft
function Get-ReferenceRows {
    if (-not $script:Ref -or -not $script:Ref.Werte) { return @() }
    $keys = @($script:BenchResults | Where-Object { $_.RefKey -and $null -ne $_.RefPct } | ForEach-Object { $_.RefKey } | Select-Object -Unique)
    foreach ($k in $keys) {
        if (-not $script:Ref.Werte.ContainsKey($k)) { continue }
        $u = @($script:MetricDefs | Where-Object { $_.K -eq $k } | ForEach-Object { $_.U }) | Select-Object -First 1
        if (-not $u) { $u = $(if ($k -match '\|(SR|SW)$') { 'MB/s' } elseif ($k -like 'DISK|*') { 'IOPS' } else { '' }) }
        $v = [double]$script:Ref.Werte[$k]
        [pscustomobject][ordered]@{ Key = $k; 'Messgröße' = (Get-MetricName $k); Wert = $v; Referenz = ('{0} {1}' -f $(if ($v -ge 100) { '{0:N0}' -f $v } else { '{0:N1}' -f $v }), $u).Trim()
            Herkunft = $(if ($script:Ref.Herkunft -and $script:Ref.Herkunft.ContainsKey($k)) { [string]$script:Ref.Herkunft[$k] } else { [string]$script:Ref.Quelle }) }
    }
}

function Get-RefPct([string]$RefKey, [double]$Wert, [switch]$LowerBetter) {
    if (-not $RefKey -or -not $script:Ref -or -not $script:Ref.Werte.ContainsKey($RefKey)) { return $null }
    $r = [double]$script:Ref.Werte[$RefKey]
    if ($r -le 0 -or $Wert -le 0) { return $null }
    if ($LowerBetter) { return [int][math]::Round($r / $Wert * 100.0) }
    return [int][math]::Round($Wert / $r * 100.0)
}

function Get-StatusRank([string]$s) { switch ($s) { 'Fehler' { 3 } 'Warnung' { 2 } 'Info' { 1 } default { 0 } } }

function Get-GeoMean($Values, $Weights = $null) {
    if (-not $Values) { return $null }
    $valList = @($Values)
    $weightList = $(if ($Weights) { @($Weights) } else { $null })
    $s = 0.0
    $wSum = 0.0
    for ($i = 0; $i -lt $valList.Count; $i++) {
        $x = $valList[$i]
        if ($null -ne $x -and [double]$x -gt 0) {
            $w = $(if ($weightList -and $i -lt $weightList.Count -and $null -ne $weightList[$i] -and [double]$weightList[$i] -gt 0) { [double]$weightList[$i] } else { 1.0 })
            $s += $w * [math]::Log([double]$x)
            $wSum += $w
        }
    }
    if ($wSum -le 0) { return $null }
    return [int][math]::Round([math]::Exp($s / $wSum))
}

# Zusammenfassung einer Benchmark-Gruppe: schlechtester Status, Referenz-% (geometrisches Mittel), Kopfzeile
function Get-BenchGroup([string]$Gruppe) {
    $items = @($script:BenchResults | Where-Object { $_.Gruppe -eq $Gruppe })
    $disks = @()
    if ($Gruppe -eq 'Laufwerke') { $disks = @($script:BenchDisks) }
    $all = @($items) + @($disks)
    $st = 'OK'; foreach ($i in $all) { if ((Get-StatusRank $i.Status) -gt (Get-StatusRank $st)) { $st = $i.Status } }
    $ref = $(if ($Gruppe -eq 'Laufwerke') {
        Get-GeoMean ($disks | ForEach-Object { $_.RefPct })
    } elseif ($Gruppe -eq 'GPU') {
        $validItems = @($items | Where-Object { $null -ne $_.RefPct -and [double]$_.RefPct -gt 0 })
        if ($validItems.Count) {
            # Gemessene FPS-Renderleistung (Direct3D 11 Rendertest) erhält ein deutlich höheres Gewicht (3x) gegenüber theoretischen Werten
            $weights = @(foreach ($it in $validItems) {
                if ($it.Key -match 'REND|RPKT' -or $it.RefKey -match 'REND|RPKT') { 3.0 } else { 1.0 }
            })
            Get-GeoMean ($validItems | ForEach-Object { $_.RefPct }) $weights
        } else { $null }
    } else {
        Get-GeoMean ($items | ForEach-Object { $_.RefPct })
    })
    $head = [string]$script:BenchHead[$Gruppe]
    return [pscustomobject]@{ Gruppe = $Gruppe; Name = [string]$script:BenchGroupNames[$Gruppe]; Status = $st; RefPct = $ref
        Referenz = $(if ($null -ne $ref) { '{0} %' -f $ref } else { '' }); Kopf = $head; Anzahl = $all.Count; Items = $items; Disks = $disks }
}

# Gesamtbewertung über alle Gruppen (Prozessor und Grafik 2x gewichtet gegenüber RAM und Laufwerken)
function Get-BenchOverall {
    $weights = @{ 'CPU' = 2.0; 'GPU' = 2.0; 'RAM' = 1.0; 'Laufwerke' = 1.0 }
    $vals = [System.Collections.Generic.List[double]]::new()
    $w = [System.Collections.Generic.List[double]]::new()
    foreach ($gk in 'CPU', 'RAM', 'GPU', 'Laufwerke') {
        $g = Get-BenchGroup $gk
        if ($null -ne $g.RefPct -and [double]$g.RefPct -gt 0) {
            $vals.Add([double]$g.RefPct)
            $w.Add($weights[$gk])
        }
    }
    if (-not $vals.Count) { return $null }
    return Get-GeoMean $vals $w
}

function Send-BenchGroup([string]$Gruppe) {
    $g = Get-BenchGroup $Gruppe
    if ($g.Anzahl) { Send-GuiEvent 'BGRP' $Gruppe $g.Name $g.Status $g.Kopf $g.Referenz }
}

# Messwerte dieses Laufs als Referenzwerte (Laufwerke als Mittelwert je Klasse)
function Get-CurrentRefValues {
    $w = @{}
    foreach ($b in $script:BenchResults) { if ($b.RefKey -and $b.Wert -gt 0 -and $b.RefKey -notlike 'DISK|*') { $w[$b.RefKey] = [math]::Round([double]$b.Wert, 1) } }
    $byKey = @{}
    foreach ($b in $script:BenchResults) { if ($b.RefKey -like 'DISK|*' -and $b.Wert -gt 0) { if (-not $byKey.ContainsKey($b.RefKey)) { $byKey[$b.RefKey] = New-Object System.Collections.ArrayList }; [void]$byKey[$b.RefKey].Add([double]$b.Wert) } }
    foreach ($k in $byKey.Keys) { $w[$k] = [math]::Round((($byKey[$k] | Measure-Object -Average).Average), 0) }
    return $w
}

# Referenz speichern (Haken "Dieses System als Referenz festlegen"). Ist schon eine Referenz desselben Geräts gespeichert,
# bleiben deren Messgrößen erhalten, die dieser Lauf nicht gemessen hat (z. B. Benchmark nur mit CPU); ein anderes Gerät
# ersetzt die Referenz ganz. Herkunft je Messgröße für den Bericht.
function Save-BenchReference {
    $cur = Get-CurrentRefValues
    $dev = ''; try { $dev = [string](Get-DeviceIdentity).Id } catch { }
    $label = ('Lauf vom {0} (v{1})' -f (Get-Date).ToString('dd.MM.yyyy', $script:Inv), $ScriptVersion)
    $w = [ordered]@{}; $h = [ordered]@{}
    $old = Get-SavedReference
    $same = $old -and (($dev -and $old.GeraetId -eq $dev) -or ($old.Computer -and $old.Computer -eq $env:COMPUTERNAME))
    if ($same) { foreach ($k in @($old.Werte.Keys | Sort-Object)) { $w[$k] = $old.Werte[$k]; $h[$k] = $(if ($old.Herkunft.ContainsKey($k)) { $old.Herkunft[$k] } else { 'früherer Lauf' }) } }
    foreach ($k in @($cur.Keys | Sort-Object)) { $w[$k] = $cur[$k]; $h[$k] = $label }
    $o = [ordered]@{ Name = $(if ($script:BenchRefName) { $script:BenchRefName } else { [Environment]::MachineName }); Computer = $env:COMPUTERNAME; GeraetId = $dev; Datum = (Get-Date).ToString('yyyy-MM-dd', $script:Inv); Version = $ScriptVersion; Werte = $w; Herkunft = $h }
    $json = $o | ConvertTo-Json -Depth 4
    $saved = @()
    $targets = @()
    if ($script:DataDir) { $targets += (Join-Path $script:DataDir 'Referenz.json') }
    foreach ($f in $targets) {
        try { [IO.File]::WriteAllText($f, $json, (New-Object Text.UTF8Encoding($false))); $saved += $f } catch { }
    }
    return $saved
}

# Vergleich mit Systemen aus der Datenbank: eine Zeile je Messgröße
function Get-CompareRows {
    $cur = Get-CurrentRefValues
    $sys = @($script:CmpSystems)
    $latest = @(Get-DbLatest (Get-DbEntries) -ExcludeCurrent)
    $defs = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $script:MetricDefs) { $defs.Add($d) }
    foreach ($cls in $script:DiskClassNames.Keys) {
        $has = $cur.ContainsKey("DISK|$cls|SR") -or @($sys | Where-Object { $_.Werte.ContainsKey("DISK|$cls|SR") }).Count
        if (-not $has) { continue }
        $cn = $script:DiskClassNames[$cls]
        $defs.Add(@{ K = "DISK|$cls|SR"; N = "$cn seq. lesen"; U = 'MB/s'; F = 'N0' })
        $defs.Add(@{ K = "DISK|$cls|SW"; N = "$cn seq. schreiben"; U = 'MB/s'; F = 'N0' })
        $defs.Add(@{ K = "DISK|$cls|R1"; N = "$cn 4K zufällig QD1"; U = 'IOPS'; F = 'N0' })
    }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $defs) {
        $mine = $(if ($cur.ContainsKey($d.K)) { [double]$cur[$d.K] } else { $null })
        $vals = @($sys | ForEach-Object { if ($_.Werte.ContainsKey($d.K)) { [double]$_.Werte[$d.K] } else { $null } })
        if ($null -eq $mine -or -not @($vals | Where-Object { $null -ne $_ }).Count) { continue }
        $rank = ''
        if ($null -ne $mine) {
            $pool = @($latest | ForEach-Object { if ($_.Werte.ContainsKey($d.K)) { [double]$_.Werte[$d.K] } } | Where-Object { $_ -gt 0 })
            if ($pool.Count) {
                $better = @($pool | Where-Object { if ($d.L) { $_ -lt $mine } else { $_ -gt $mine } }).Count
                $rank = 'Platz {0} von {1}' -f ($better + 1), ($pool.Count + 1)
            }
        }
        $rows.Add([pscustomobject]@{ Key = $d.K; Messung = $d.N; Einheit = $d.U; Format = $d.F; LowerBetter = [bool]$d.L; Dieses = $mine; Werte = $vals; Rang = $rank })
    }
    return $rows.ToArray()
}

# Werte einer Vergleichszeile aufsteigend: "LIZZZ 21,3 GB/s < Dieser PC 57,4 GB/s < TORRENT 61,8 GB/s"
function Get-CompareOrderText($Row, [switch]$Gui) {
    $items = @([pscustomobject]@{ N = $(if ($Gui) { '▶ Dieser PC' } else { 'Dieser PC' }); V = $Row.Dieses; Own = $true })
    for ($k = 0; $k -lt $script:CmpSystems.Count; $k++) { if ($null -ne $Row.Werte[$k]) { $items += [pscustomobject]@{ N = $script:CmpSystems[$k].Computer; V = $Row.Werte[$k]; Own = $false } } }
    $items = @($items | Where-Object { $null -ne $_.V -and [double]$_.V -gt 0 } | Sort-Object { [double]$_.V })
    $txt = @($items | ForEach-Object { $rel = $(if (-not $_.Own) { Get-RelText $Row.Dieses $_.V $Row.LowerBetter } else { '' }); '{0} {1}{2}' -f $_.N, (Format-Metric $_.V $Row.Format $Row.Einheit), $(if ($rel) { ' (' + $rel + ')' } else { '' }) })
    return ($txt -join $(if ($Gui) { '  <  ' } else { ' < ' }))
}

function Format-Metric($Value, [string]$Fmt, [string]$Unit) {
    if ($null -eq $Value -or [double]$Value -le 0) { return '' }
    return ('{0:' + $Fmt + '} {1}') -f [double]$Value, $Unit
}

function Get-RelText($Mine, $Other, [bool]$LowerBetter) {
    if ($null -eq $Mine -or $null -eq $Other -or [double]$Mine -le 0 -or [double]$Other -le 0) { return '' }
    # positiv = das andere System ist besser
    $d = $(if ($LowerBetter) { ([double]$Mine / [double]$Other - 1) * 100 } else { ([double]$Other / [double]$Mine - 1) * 100 })
    return '{0:+0;-0;0} %' -f $d
}

# Skala der y-Achse (ab v2.8): runde Schritte mit so vielen Nachkommastellen, wie der Schritt braucht. Bis v2.7 wurden
# Schritte wie 0,5 ohne Nachkommastellen beschriftet (62, 62, 61, 61, 60). Ganzzahlige Messreihen (Temperatur in °C,
# Takt, Drehzahl) bekommen mindestens Schritt 1.
function Get-ChartScale([double]$Min, [double]$Max, [switch]$Integer) {
    $raw = ($Max - $Min) / 4; if ($raw -le 0) { $raw = [math]::Max(1.0, [math]::Abs($Max) * 0.05) }
    $mag = [math]::Pow(10, [math]::Floor([math]::Log10($raw)))
    $nice = $mag; foreach ($f in 1, 2, 2.5, 5, 10) { if ($Integer -and $f -eq 2.5 -and $mag -le 1) { continue }; if ($f * $mag -ge $raw - 1e-9) { $nice = $f * $mag; break } }
    if ($Integer -and $nice -lt 1) { $nice = 1.0 }
    $y0 = [math]::Floor($Min / $nice + 1e-9) * $nice; $y1 = [math]::Ceiling($Max / $nice - 1e-9) * $nice; if ($y1 -le $y0) { $y1 = $y0 + $nice }
    # Nachkommastellen nach dem Bruchteil des Schritts (0,5 eine, 0,25 und 2,5 bei 0,25 bzw. eine)
    $dec = 0
    while ($dec -lt 6 -and [math]::Abs([math]::Round($nice, $dec) - $nice) -gt 1e-9) { $dec++ }
    if ($dec -eq 0 -and [math]::Abs([math]::Round($y0, 0) - $y0) -gt 1e-9) { $dec = 1 }
    $ticks = New-Object System.Collections.Generic.List[double]
    $n = [int][math]::Round(($y1 - $y0) / $nice)
    for ($i = 0; $i -le $n; $i++) { $ticks.Add([math]::Round($y0 + $i * $nice, 6)) }
    return [pscustomobject]@{ Y0 = $y0; Y1 = $y1; Step = $nice; Format = ('N{0}' -f $dec); Ticks = $ticks.ToArray() }
}

# Beschriftungen der senkrechten Markierungen (Abschnitte, Lastende, Abbruch) ohne Überschneidung (ab v2.8): Breite
# geschätzt (11 px Schrift), jede Beschriftung in die erste Zeile, in der sie frei ist; am rechten Rand links der Linie.
# Rückgabe je Markierung X, Y, Anker (start|end) und Text.
function Get-ChartMarkLayout($Marks, [double]$Left, [double]$Right, [double]$Top, [scriptblock]$Fx, [double]$XMax, [int]$MaxLanes = 3) {
    $out = New-Object System.Collections.Generic.List[object]
    $lanes = @{}
    foreach ($m in @($Marks | Where-Object { $_ -and $null -ne $_.T -and [double]$_.T -ge 0 -and [double]$_.T -le $XMax } | Sort-Object { [double]$_.T })) {
        $x = & $Fx ([double]$m.T)
        $txt = [string]$m.Label
        $w = [math]::Ceiling($txt.Length * 6.3) + 4
        $anchor = 'start'; $a = $x + 4; $b = $a + $w
        if ($b -gt $Right) { $anchor = 'end'; $b = $x - 4; $a = $b - $w }
        if ($a -lt $Left) { $a = $Left; $b = $a + $w }
        $lane = -1
        for ($l = 0; $l -lt $MaxLanes; $l++) {
            $free = $true
            foreach ($iv in @($lanes[$l])) { if ($iv -and $a -lt $iv[1] + 6 -and $b + 6 -gt $iv[0]) { $free = $false; break } }
            if ($free) { $lane = $l; break }
        }
        if ($lane -lt 0) { $txt = ''; $lane = 0 } else { $lanes[$lane] = @($lanes[$lane]) + , @($a, $b) }
        $out.Add([pscustomobject]@{ LineX = $x; X = $(if ($anchor -eq 'end') { $x - 4 } else { $x + 4 }); Y = $Top + 11 + $lane * 13; Anchor = $anchor; Text = $txt; Label = [string]$m.Label })
    }
    return $out.ToArray()
}

function New-LineSvg($Points, [string]$Unit) {
    $inv = $script:Inv
    $pts = @($Points | Where-Object { $null -ne $_.V -and $_.V -gt 0 })
    if ($pts.Count -lt 2) { return '' }
    $W = 960; $H = 260; $ml = 70; $mr = 20; $mt = 14; $mb = 38
    $xmax = [double](($pts | Measure-Object T -Maximum).Maximum); if ($xmax -le 0) { $xmax = 1 }
    $vmin = [double](($pts | Measure-Object V -Minimum).Minimum); $vmax = [double](($pts | Measure-Object V -Maximum).Maximum)
    if ($Unit -eq 'Bilder/s' -or $Unit -eq 'FPS') { $vmin = 0.0 }
    if ($Unit -eq '%') { $vmin = 0.0; if ($vmax -lt 100) { $vmax = 100.0 } }
    $sc = Get-ChartScale $vmin $vmax -Integer:$(-not @($pts | Where-Object { [double]$_.V -ne [math]::Round([double]$_.V) }).Count)
    $y0 = $sc.Y0; $y1 = $sc.Y1
    $pw = $W - $ml - $mr; $ph = $H - $mt - $mb
    $fx = { param($t) $ml + $t / $xmax * $pw }
    $fy = { param($v) $mt + ($y1 - $v) / ($y1 - $y0) * $ph }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append([string]::Format($inv, '<svg class="chart" viewBox="0 0 {0} {1}" role="img" preserveAspectRatio="xMidYMid meet">', $W, $H))
    foreach ($v in $sc.Ticks) {
        $y = & $fy $v
        [void]$sb.Append([string]::Format($inv, '<line class="grid" x1="{0}" x2="{1}" y1="{2:0.#}" y2="{2:0.#}"/>', $ml, $W - $mr, $y))
        [void]$sb.Append([string]::Format($inv, '<text x="{0}" y="{1:0.#}" text-anchor="end" dominant-baseline="middle">{2}</text>', $ml - 8, $y, $v.ToString($sc.Format, [Globalization.CultureInfo]::CurrentCulture)))
    }
    $tickS = 15
    foreach ($c in 15, 30, 60, 120, 300, 600, 900, 1800, 3600) { $tickS = $c; if ($xmax / $c -le 8) { break } }
    for ($t = 0; $t -le $xmax + 0.1; $t += $tickS) {
        $x = & $fx $t
        $lab = $(if ($tickS -ge 60) { '{0} min' -f [int]($t / 60) } else { '{0} s' -f [int]$t })
        [void]$sb.Append([string]::Format($inv, '<line class="tick" x1="{0:0.#}" x2="{0:0.#}" y1="{1}" y2="{2}"/><text x="{0:0.#}" y="{3}" text-anchor="middle">{4}</text>', $x, $mt + $ph, $mt + $ph + 5, $H - 12, $lab))
    }
    $poly = ($pts | ForEach-Object { [string]::Format($inv, '{0:0.#},{1:0.#}', (& $fx $_.T), (& $fy $_.V)) }) -join ' '
    [void]$sb.Append(('<polyline class="line" points="{0}"/>' -f $poly))
    $stepPts = [math]::Max(1, [int][math]::Ceiling($pts.Count / 300))
    for ($i = 0; $i -lt $pts.Count; $i += $stepPts) {
        $p = $pts[$i]
        $tl = '{0}:{1:00} min  ·  {2:N0} {3}' -f [int][math]::Floor($p.T / 60), [int]($p.T % 60), $p.V, $Unit
        [void]$sb.Append([string]::Format($inv, '<circle class="hit" cx="{0:0.#}" cy="{1:0.#}" r="6"><title>{2}</title></circle>', (& $fx $p.T), (& $fy $p.V), $tl))
    }
    [void]$sb.Append('</svg>')
    return $sb.ToString()
}

# Mehrere Kurven in einem Diagramm (Lasttest): Serien @{ Name; Cls = 's1'..'s4'; Points = T/V }, Bezugslinien @{ V; Label; Cls = 'lim'|'tj' },
# Markierungen @{ T; Label } als senkrechte Linien (Lastende, Abbruch, Beginn der Drosselung). Leer, wenn keine Serie zwei Punkte hat.
function New-MultiLineSvg {
    param($Series, [string]$Unit, $RefLines = @(), $Marks = @(), [string]$Fmt = 'N0')
    $inv = $script:Inv
    $ser = @($Series | ForEach-Object { $s = $_; $p = @($s.Points | Where-Object { $null -ne $_.V -and -not [double]::IsNaN([double]$_.V) }); if ($p.Count -ge 2) { [pscustomobject]@{ Name = $s.Name; Cls = $s.Cls; Points = $p } } })
    if (-not $ser.Count) { return '' }
    $W = 960; $H = 250; $ml = 70; $mr = 20; $mt = 14; $mb = 38
    $allP = @($ser | ForEach-Object { $_.Points })
    $xmax = [double](($allP | Measure-Object T -Maximum).Maximum); if ($xmax -le 0) { $xmax = 1 }
    # Beschriftungen der Marken in einem eigenen Band über der Zeichenfläche (ab v2.8), damit sie keine Kurve verdecken
    $pw = $W - $ml - $mr
    $fx = { param($t) $ml + $t / $xmax * $pw }
    $markLay = @(Get-ChartMarkLayout $Marks $ml ($W - $mr) 0 $fx $xmax)
    $lanes = @($markLay | Where-Object { $_.Text } | ForEach-Object { [int](($_.Y - 11) / 13) } | Measure-Object -Maximum)
    if ($markLay.Count) { $band = 13 * ($(if ($lanes.Count -and $null -ne $lanes[0].Maximum) { [int]$lanes[0].Maximum } else { 0 }) + 1) + 4; $mt += $band; $H += $band }
    $vals = @($allP | ForEach-Object { [double]$_.V }) + @($RefLines | ForEach-Object { [double]$_.V })
    $vmin = [double](($vals | Measure-Object -Minimum).Minimum); $vmax = [double](($vals | Measure-Object -Maximum).Maximum)
    if ($Unit -eq 'Bilder/s' -or $Unit -eq 'FPS') { $vmin = 0.0 }
    if ($Unit -eq '%') { $vmin = 0.0; if ($vmax -lt 100) { $vmax = 100.0 } }
    $sc = Get-ChartScale $vmin $vmax -Integer:$(-not @($vals | Where-Object { $_ -ne [math]::Round($_) }).Count)
    $y0 = $sc.Y0; $y1 = $sc.Y1
    $pw = $W - $ml - $mr; $ph = $H - $mt - $mb
    $fx = { param($t) $ml + $t / $xmax * $pw }
    $fy = { param($v) $mt + ($y1 - $v) / ($y1 - $y0) * $ph }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<p class="lgd">')
    foreach ($s in $ser) {
        $lastV = [double]$s.Points[$s.Points.Count - 1].V; $maxV = [double](($s.Points | Measure-Object V -Maximum).Maximum)
        [void]$sb.Append(('<span><i class="sw {0}"></i>{1} <small>max {2} {3}</small></span>' -f $s.Cls, (ConvertTo-HtmlText $s.Name), $maxV.ToString($Fmt, [Globalization.CultureInfo]::CurrentCulture), (ConvertTo-HtmlText $Unit)))
    }
    foreach ($r in $RefLines) { [void]$sb.Append(('<span><i class="sw {0}"></i>{1}</span>' -f $r.Cls, (ConvertTo-HtmlText $r.Label))) }
    [void]$sb.Append('</p>')
    [void]$sb.Append([string]::Format($inv, '<svg class="chart ml" viewBox="0 0 {0} {1}" role="img" preserveAspectRatio="xMidYMid meet">', $W, $H))
    foreach ($v in $sc.Ticks) {
        $y = & $fy $v
        [void]$sb.Append([string]::Format($inv, '<line class="grid" x1="{0}" x2="{1}" y1="{2:0.#}" y2="{2:0.#}"/>', $ml, $W - $mr, $y))
        [void]$sb.Append([string]::Format($inv, '<text x="{0}" y="{1:0.#}" text-anchor="end" dominant-baseline="middle">{2}</text>', $ml - 8, $y, $v.ToString($sc.Format, [Globalization.CultureInfo]::CurrentCulture)))
    }
    $tickS = 15
    foreach ($c in 15, 30, 60, 120, 300, 600, 900, 1800, 3600) { $tickS = $c; if ($xmax / $c -le 8) { break } }
    for ($t = 0; $t -le $xmax + 0.1; $t += $tickS) {
        $x = & $fx $t
        $lab = $(if ($tickS -ge 60) { '{0} min' -f [int]($t / 60) } else { '{0} s' -f [int]$t })
        [void]$sb.Append([string]::Format($inv, '<line class="tick" x1="{0:0.#}" x2="{0:0.#}" y1="{1}" y2="{2}"/><text x="{0:0.#}" y="{3}" text-anchor="middle">{4}</text>', $x, $mt + $ph, $mt + $ph + 5, $H - 12, $lab))
    }
    foreach ($m in $markLay) {
        [void]$sb.Append([string]::Format($inv, '<line class="mark" x1="{0:0.#}" x2="{0:0.#}" y1="{1}" y2="{2}"><title>{3}</title></line>', $m.LineX, $(if ($m.Text) { $m.Y - 10 } else { $mt }), $mt + $ph, (ConvertTo-HtmlText $m.Label)))
        if ($m.Text) { [void]$sb.Append([string]::Format($inv, '<text class="mk" x="{0:0.#}" y="{1}" text-anchor="{2}">{3}</text>', $m.X, $m.Y, $m.Anchor, (ConvertTo-HtmlText $m.Text))) }
    }
    foreach ($r in $RefLines) {
        $y = & $fy ([double]$r.V)
        [void]$sb.Append([string]::Format($inv, '<line class="{3}" x1="{0}" x2="{1}" y1="{2:0.#}" y2="{2:0.#}"><title>{4}</title></line>', $ml, $W - $mr, $y, $r.Cls, (ConvertTo-HtmlText $r.Label)))
    }
    foreach ($s in $ser) {
        $poly = ($s.Points | ForEach-Object { [string]::Format($inv, '{0:0.#},{1:0.#}', (& $fx $_.T), (& $fy ([double]$_.V))) }) -join ' '
        [void]$sb.Append(('<polyline class="line {0}" points="{1}"/>' -f $s.Cls, $poly))
        $stepPts = [math]::Max(1, [int][math]::Ceiling($s.Points.Count / 200))
        for ($i = 0; $i -lt $s.Points.Count; $i += $stepPts) {
            $p = $s.Points[$i]
            $tl = '{0}:{1:00} min  ·  {2}: {3} {4}' -f [int][math]::Floor($p.T / 60), [int]($p.T % 60), $s.Name, ([double]$p.V).ToString($Fmt, [Globalization.CultureInfo]::CurrentCulture), $Unit
            [void]$sb.Append([string]::Format($inv, '<circle class="hit {3}" cx="{0:0.#}" cy="{1:0.#}" r="6"><title>{2}</title></circle>', (& $fx $p.T), (& $fy ([double]$p.V)), (ConvertTo-HtmlText $tl), $s.Cls))
        }
    }
    [void]$sb.Append('</svg>')
    return $sb.ToString()
}

