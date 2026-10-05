#region ---------- Grafische Bausteine für die Berichte ----------
$script:GroupOfKey = @{ 'CPU' = 'Prozessor'; 'RAM' = 'Arbeitsspeicher'; 'GPU' = 'Grafik'; 'DISK' = 'Laufwerke'; 'LW' = 'Laufwerke'; 'WINSAT' = 'WinSAT-Bewertung' }

# Balken 0 bis 150 % mit Markierung bei 100 %
function Get-RefBar($Pct, [string]$Cls = 'info', [switch]$Small) {
    if ($null -eq $Pct -or "$Pct" -eq '') { return '' }
    $w = [math]::Round([math]::Min(150.0, [math]::Max(0.0, [double]$Pct)) / 150.0 * 100.0, 1)
    return [string]::Format($script:Inv, '<span class="rb{0}" title="{1} % der Referenz"><span class="rbf {2}" style="width:{3}%"></span><span class="rbm"></span></span>', $(if ($Small) { ' s' } else { '' }), $Pct, $Cls, $w)
}

# Abweichung farbig: positiv = besser
function Get-DeltaHtml([string]$Text) {
    if (-not $Text) { return '' }
    $m = [regex]::Match($Text, '^([+-]?\d+)')
    $c = ''
    if ($m.Success) { $d = [int]$m.Groups[1].Value; $c = $(if ($d -le -10) { 'warnt' } elseif ($d -ge 3) { 'okt' } else { '' }) }
    return ('<span class="dl {0}">{1}</span>' -f $c, (ConvertTo-HtmlText $Text))
}

# Nutzungsprofile (Gaming / Büro / Workstation) im UserBenchmark-Stil
function New-ProfileCards {
    $gCpu = Get-BenchGroup 'CPU'
    $gGpu = Get-BenchGroup 'GPU'
    $gRam = Get-BenchGroup 'RAM'
    $gDsk = Get-BenchGroup 'Laufwerke'

    # Nur anzeigen, wenn mindestens 3 der 4 Hauptgruppen (CPU, GPU, RAM, Laufwerke) Referenzdaten haben
    $hasRef = 0
    foreach ($g in $gCpu, $gGpu, $gRam, $gDsk) {
        if ($null -ne $g.RefPct -and [double]$g.RefPct -gt 0) { $hasRef++ }
    }
    if ($hasRef -lt 3) { return '' }

    # Einzelwerte für CPU-ST und CPU-MT ermitteln (falls vorhanden, sonst Fallback auf CPU-Gruppenwert)
    $cpuSt = @($script:BenchResults | Where-Object { ($_.Key -eq 'CPU|ST' -or $_.RefKey -eq 'CPU|ST') -and $null -ne $_.RefPct -and [double]$_.RefPct -gt 0 } | Select-Object -First 1).RefPct
    $cpuMt = @($script:BenchResults | Where-Object { ($_.Key -eq 'CPU|MT' -or $_.RefKey -eq 'CPU|MT') -and $null -ne $_.RefPct -and [double]$_.RefPct -gt 0 } | Select-Object -First 1).RefPct
    if ($null -eq $cpuSt -and $null -ne $gCpu.RefPct) { $cpuSt = $gCpu.RefPct }
    if ($null -eq $cpuMt -and $null -ne $gCpu.RefPct) { $cpuMt = $gCpu.RefPct }

    $profiles = @(
        @{ Name = 'Gaming';       Icon = '🎮'; W = @{ 'CPU_ST' = 1.0; 'CPU_MT' = 0.5; 'GPU' = 3.0; 'RAM' = 0.5; 'DISK' = 0.5 } }
        @{ Name = 'Büro/Desktop'; Icon = '💼'; W = @{ 'CPU_ST' = 2.0; 'CPU_MT' = 1.0; 'GPU' = 0.5; 'RAM' = 1.0; 'DISK' = 2.0 } }
        @{ Name = 'Workstation';  Icon = '⚙️'; W = @{ 'CPU_ST' = 0.5; 'CPU_MT' = 3.0; 'GPU' = 1.0; 'RAM' = 2.0; 'DISK' = 1.0 } }
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<div class="ov profile-grid">')
    foreach ($p in $profiles) {
        $vals = [System.Collections.Generic.List[double]]::new()
        $weights = [System.Collections.Generic.List[double]]::new()

        if ($null -ne $cpuSt -and [double]$cpuSt -gt 0) { $vals.Add([double]$cpuSt); $weights.Add($p.W['CPU_ST']) }
        if ($null -ne $cpuMt -and [double]$cpuMt -gt 0) { $vals.Add([double]$cpuMt); $weights.Add($p.W['CPU_MT']) }
        if ($null -ne $gGpu.RefPct -and [double]$gGpu.RefPct -gt 0) { $vals.Add([double]$gGpu.RefPct); $weights.Add($p.W['GPU']) }
        if ($null -ne $gRam.RefPct -and [double]$gRam.RefPct -gt 0) { $vals.Add([double]$gRam.RefPct); $weights.Add($p.W['RAM']) }
        if ($null -ne $gDsk.RefPct -and [double]$gDsk.RefPct -gt 0) { $vals.Add([double]$gDsk.RefPct); $weights.Add($p.W['DISK']) }

        if (-not $vals.Count) { continue }
        $score = Get-GeoMean $vals $weights
        $word = Get-BenchRatingWord $score
        $bar = Get-RefBar $score 'ok'

        [void]$sb.Append(('<div class="tile profile"><h4>{0} {1}</h4><div class="big">{2}<small> %</small></div><div class="pword">{3}</div>{4}</div>' -f
            $p.Icon, (ConvertTo-HtmlText $p.Name), $score, (ConvertTo-HtmlText $word), $bar))
    }
    [void]$sb.Append('</div>')
    return $sb.ToString()
}

# Kacheln über dem Benchmark: eine je Gruppe mit Referenzbalken
function New-BenchOverview {
    $bcls = @{ OK = 'ok'; Info = 'info'; Warnung = 'warn'; Fehler = 'crit' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<div class="ov">')
    foreach ($gk in $script:BenchGroupOrder) {
        $g = Get-BenchGroup $gk
        if (-not $g.Anzahl) { continue }
        $c = $bcls[$g.Status]; if (-not $c) { $c = 'info' }
        $kopf = $g.Kopf
        if ($gk -eq 'WinSAT' -and $script:WinsatTotal -gt 0) {
            $big = '{0:N1}<small> von 9,9</small>' -f $script:WinsatTotal
            $kopf = 'Gesamtwert = niedrigster Teilwert'
            $bar = [string]::Format($script:Inv, '<span class="rb"><span class="rbf {0}" style="width:{1:0.#}%"></span></span>', (Get-WinsatClass $script:WinsatTotal), ($script:WinsatTotal / 9.9 * 100))
        } elseif ($null -ne $g.RefPct) {
            $big = '{0}<small> % der Referenz</small>' -f $g.RefPct
            $bar = Get-RefBar $g.RefPct $c
        } else {
            $big = ConvertTo-HtmlText $g.Status
            $bar = ''
        }
        [void]$sb.Append(('<a class="tile t{0}" href="#bg-{1}" onclick="document.getElementById(''bg-{1}'').open=true"><h4>{2}<i class="dot {0}" title="{3}"></i></h4><div class="big">{4}</div>{5}<p>{6}</p></a>' -f
            $c, $gk, (ConvertTo-HtmlText $g.Name), (ConvertTo-HtmlText $g.Status), $big, $bar, (ConvertTo-HtmlText $kopf)))
    }
    [void]$sb.Append('</div>')
    return $sb.ToString()
}

function Get-WinsatClass([double]$v) { if ($v -ge 7) { 'ok' } elseif ($v -ge 5) { 'info' } elseif ($v -ge 3.5) { 'warn' } else { 'crit' } }

# WinSAT-Teilwerte als Balkendiagramm (Skala 1,0 bis 9,9, gestrichelte Linie = Gesamtwert)
function New-WinsatSvg($Items, [double]$Total) {
    $inv = $script:Inv
    $items = @($Items | Where-Object { [double]$_.Wert -gt 0 })
    if (-not $items.Count) { return '' }
    $W = 860; $rowH = 38; $ml = 175; $mr = 150; $mt = 26; $mb = 30
    $H = $mt + $items.Count * $rowH + $mb
    $pw = $W - $ml - $mr
    $fx = { param($v) $ml + ([math]::Max(1.0, [double]$v) - 1.0) / 8.9 * $pw }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append([string]::Format($inv, '<svg class="chart ws" viewBox="0 0 {0} {1}" role="img" aria-label="WinSAT-Teilwerte">', $W, $H))
    foreach ($t in 1, 2, 3, 4, 5, 6, 7, 8, 9, 9.9) {
        $x = & $fx $t
        [void]$sb.Append([string]::Format($inv, '<line class="grid" x1="{0:0.#}" x2="{0:0.#}" y1="{1}" y2="{2}"/><text x="{0:0.#}" y="{3}" text-anchor="middle">{4}</text>', $x, $mt - 6, $H - $mb, $H - 10, ('{0:0.#}' -f $t)))
    }
    $y = $mt
    foreach ($i in $items) {
        $v = [double]$i.Wert
        $cls = Get-WinsatClass $v
        [void]$sb.Append([string]::Format($inv, '<text class="l" x="{0}" y="{1:0.#}" text-anchor="end" dominant-baseline="middle">{2}</text>', $ml - 12, $y + $rowH / 2, (ConvertTo-HtmlText $i.Messung)))
        [void]$sb.Append([string]::Format($inv, '<rect class="bg" x="{0}" y="{1:0.#}" width="{2:0.#}" height="20" rx="5"/>', $ml, $y + ($rowH - 20) / 2, $pw))
        [void]$sb.Append([string]::Format($inv, '<rect class="b-{0}" x="{1}" y="{2:0.#}" width="{3:0.#}" height="20" rx="5"><title>{4}: {5:N1} von 9,9</title></rect>', $cls, $ml, $y + ($rowH - 20) / 2, [math]::Max(6.0, (& $fx $v) - $ml), (ConvertTo-HtmlText $i.Messung), $v))
        $cmp = $(if ($i.Vergleich) { '  ' + $i.Vergleich -replace ' zum letzten Lauf', ' zuletzt' -replace ' zu (\d+) Läufen', ' zu $1 Läufen' } else { '' })
        [void]$sb.Append([string]::Format($inv, '<text class="v" x="{0:0.#}" y="{1:0.#}" dominant-baseline="middle">{2}<tspan class="d">{3}</tspan></text>', $ml + $pw + 10, $y + $rowH / 2, ('{0:N1}' -f $v), (ConvertTo-HtmlText $cmp)))
        $y += $rowH
    }
    if ($Total -gt 0) {
        $x = & $fx $Total
        [void]$sb.Append([string]::Format($inv, '<line class="tot" x1="{0:0.#}" x2="{0:0.#}" y1="{1}" y2="{2}"/><text class="tl" x="{0:0.#}" y="{3}" text-anchor="middle">Gesamt {4}</text>', $x, $mt - 4, $H - $mb, $mt - 10, ('{0:N1}' -f $Total)))
    }
    [void]$sb.Append('</svg>')
    return $sb.ToString()
}

# Eine Messgröße für mehrere Systeme als Balkengruppe, immer aufsteigend sortiert (niedrigster Wert oben, nicht
# gemessene Systeme am Ende). Farbe und Name bleiben dem System zugeordnet; -Own markiert das eigene System.
# Mode Base: Abstand zum eigenen System (positiv = besser), Best: Abstand zum Bestwert, Abs: feste Skala bis AbsMax
function New-MetricBarsHtml {
    param([string]$Label, [string]$Unit, [string]$Fmt, [bool]$LowerBetter, [object[]]$Values, [string[]]$Names, [string]$Mode = 'Best', [double]$AbsMax = 0, [string]$Extra = '', [string]$Hint = '', [int]$Own = -1)
    $valid = @($Values | Where-Object { $null -ne $_ -and [double]$_ -gt 0 } | ForEach-Object { [double]$_ })
    if (-not $valid.Count) { return '' }
    if ($Mode -eq 'Base' -and $Own -lt 0) { $Own = 0 }
    $max = ($valid | Measure-Object -Maximum).Maximum; $min = ($valid | Measure-Object -Minimum).Minimum
    $best = $(if ($LowerBetter) { $min } else { $max })
    $ownV = $(if ($Own -ge 0 -and $Own -lt $Values.Count -and $null -ne $Values[$Own] -and [double]$Values[$Own] -gt 0) { [double]$Values[$Own] } else { $null })
    $sub = @($(if ($Unit) { $Unit }), $(if ($LowerBetter) { 'niedriger ist besser' } else { 'höher ist besser' }), 'aufsteigend sortiert', $Extra) | Where-Object { $_ }
    $order = @(0..($Names.Count - 1) | Sort-Object @{ e = { $v = $(if ($_ -lt $Values.Count) { $Values[$_] } else { $null }); if ($null -ne $v -and [double]$v -gt 0) { 0 } else { 1 } } }, @{ e = { $v = $(if ($_ -lt $Values.Count) { $Values[$_] } else { $null }); if ($null -ne $v) { [double]$v } else { 0 } } }, @{ e = { $_ } })
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(('<div class="mrow"><div class="mlab">{0}<small>{1}</small>{2}</div><div class="mbars">' -f (ConvertTo-HtmlText $Label), (ConvertTo-HtmlText ($sub -join ' · ')), $(if ($Hint) { '<small class="hint">' + (ConvertTo-HtmlText $Hint) + '</small>' } else { '' })))
    foreach ($i in $order) {
        $v = $(if ($i -lt $Values.Count -and $null -ne $Values[$i] -and [double]$Values[$i] -gt 0) { [double]$Values[$i] } else { $null })
        $ownCls = $(if ($i -eq $Own) { ' own' } else { '' })
        if ($null -eq $v) {
            [void]$sb.Append(('<div class="mb{2}"><span class="mn"><i class="sw c{0}"></i>{1}</span><span class="mt"></span><span class="mv na">nicht gemessen</span></div>' -f ($i % 6), (ConvertTo-HtmlText $Names[$i]), $ownCls))
            continue
        }
        $w = $(if ($Mode -eq 'Abs' -and $AbsMax -gt 0) { $v / $AbsMax } elseif ($LowerBetter) { $min / $v } else { $v / $max }) * 100
        $d = ''
        if ($Mode -eq 'Base') {
            if ($i -ne $Own -and $null -ne $ownV) { $rel = Get-RelText $ownV $v $LowerBetter; if ($rel) { $d = Get-DeltaHtml $rel } }
        } elseif ($valid.Count -gt 1) {
            if ($v -eq $best) { $d = '<span class="dl okt">Bestwert</span>' }
            else { $p = $(if ($LowerBetter) { ($best / $v - 1) * 100 } else { ($v / $best - 1) * 100 }); $d = '<span class="dl">{0:+0;-0;0} %</span>' -f $p }
        }
        [void]$sb.Append([string]::Format($script:Inv, '<div class="mb{0}{6}"><span class="mn" title="{1}"><i class="sw c{2}"></i>{1}</span><span class="mt"><span class="mf c{2}" style="width:{3:0.#}%"></span></span><span class="mv">{4}{5}</span></div>',
            $(if ($valid.Count -gt 1 -and $v -eq $best) { ' best' } else { '' }), (ConvertTo-HtmlText $Names[$i]), ($i % 6), [math]::Max(1.5, [math]::Min(100.0, $w)), (ConvertTo-HtmlText (Format-Metric $v $Fmt $Unit)), $d, $ownCls))
    }
    [void]$sb.Append('</div></div>')
    return $sb.ToString()
}

function Get-Short([string]$s, [int]$n) { if (-not $s) { return '' }; if ($s.Length -le $n) { return $s }; return $s.Substring(0, $n - 1).TrimEnd() + '…' }

# Systemvergleich aus der Datenbank, ohne neuen Benchmark
function New-CompareReport([string[]]$Paths) {
    $sys = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $Paths) {
        $j = Read-JsonFile $p
        if (-not $j) { Write-Host ('Nicht lesbar: {0}' -f $p); continue }
        $lw = @($j.Laufwerke | Where-Object { $_ -and [double]$_.SR -gt 0 })
        $sys.Add([pscustomobject]@{ Path = $p; Computer = [string]$j.Computer; Datum = [string]$j.Datum; Name = [string]$j.Name; Hw = $j.Hardware; System = [string]$j.System
            Werte = (ConvertTo-ValueTable $j.Werte); Messwerte = (ConvertTo-ValueTable $j.Messwerte); Messdauer = [string]$j.Messdauer; Version = [string]$j.Version; Quelle = [string]$j.Quelle
            Befunde = $j.Befunde; Laufwerke = $lw; Label = '' })
    }
    if ($sys.Count -lt 2) { Write-Host 'Für einen Vergleich werden mindestens zwei lesbare Systeme benötigt.'; return '' }
    foreach ($s in $sys) {
        $s.Label = $(if (@($sys | Where-Object { $_.Computer -eq $s.Computer }).Count -gt 1) { '{0} {1}' -f $s.Computer, ($s.Datum -replace '^\d{4}-(\d\d)-(\d\d).*$', '$2.$1.') } else { $s.Computer })
        if (-not $s.Label) { $s.Label = Get-Short $s.Name 22 }
    }
    $names = [string[]]@($sys | ForEach-Object { $_.Label })
    # eigenes System hervorheben: der PC, auf dem der Vergleich erstellt wird (neuester Eintrag, falls mehrere)
    $own = -1; for ($i = 0; $i -lt $sys.Count; $i++) { if ($sys[$i].Computer -eq $env:COMPUTERNAME -and ($own -lt 0 -or $sys[$i].Datum -gt $sys[$own].Datum)) { $own = $i } }
    # schnellstes Laufwerk je System (nach sequentiellem Lesen)
    foreach ($s in $sys) {
        $f = $s.Laufwerke | Sort-Object { [double]$_.SR } -Descending | Select-Object -First 1
        if ($f) { foreach ($k in 'SR', 'SW', 'R1', 'R8', 'W1') { $s.Werte['LW|' + $k] = [double]$f.$k }; $s | Add-Member -NotePropertyName Fastest -NotePropertyValue ([string]$f.Laufwerk) -Force }
        else {
            foreach ($k in 'SR', 'SW', 'R1', 'R8', 'W1') { $m = @($s.Werte.Keys | Where-Object { $_ -like "DISK|*|$k" } | ForEach-Object { $s.Werte[$_] } | Measure-Object -Maximum).Maximum; if ($m) { $s.Werte['LW|' + $k] = [double]$m } }
            $s | Add-Member -NotePropertyName Fastest -NotePropertyValue '' -Force
        }
    }
    # Bezug 100 %: gespeicherte Referenz (Referenz.json); fehlt sie oder eine Messgröße darin, je Messgröße das beste
    # der verglichenen Systeme (nach dem schnellsten Laufwerk, damit auch die Laufwerke einen Bezug haben)
    $refObj = $null; try { $refObj = Get-SavedReference } catch { }
    $best = @{}
    foreach ($k in @($sys | ForEach-Object { $_.Werte.Keys } | Select-Object -Unique)) {
        $vs = @($sys | ForEach-Object { [double]$_.Werte[$k] } | Where-Object { $_ -gt 0 })
        if ($vs.Count) { $best[$k] = $(if (Test-LowerBetterKey $k) { ($vs | Measure-Object -Minimum).Minimum } else { ($vs | Measure-Object -Maximum).Maximum }) }
    }
    $ref = $(if ($refObj) { $refObj.Werte } else { $best })
    $refLabel = $(if ($refObj) { [string]$refObj.Name } else { 'je Messgröße das beste der verglichenen Systeme' })
    $lwDefs = @(
        @{ K = 'LW|SR'; N = 'Sequentiell lesen'; U = 'MB/s'; F = 'N0'; R = 'DISK|NVMe4|SR' }
        @{ K = 'LW|SW'; N = 'Sequentiell schreiben'; U = 'MB/s'; F = 'N0'; R = 'DISK|NVMe4|SW' }
        @{ K = 'LW|R1'; N = '4K zufällig lesen QD1'; U = 'IOPS'; F = 'N0'; R = 'DISK|NVMe4|R1' }
        @{ K = 'LW|R8'; N = '4K zufällig lesen, 8 Threads'; U = 'IOPS'; F = 'N0'; R = 'DISK|NVMe4|R8' }
        @{ K = 'LW|W1'; N = '4K zufällig schreiben'; U = 'IOPS'; F = 'N0'; R = 'DISK|NVMe4|W1' }
    )
    # Gesamtbild: gewichtetes geometrisches Mittel je Gruppe in % der Standardreferenz, nur über Messgrößen, die alle Systeme haben
    # Bei der Grafik wird die reale Renderleistung (FPS) 3-fach gegenüber theoretischen Werten gewichtet
    $groups = [ordered]@{ 'Prozessor' = @($script:MetricDefs | Where-Object { $_.K -like 'CPU|*' }); 'Arbeitsspeicher' = @($script:MetricDefs | Where-Object { $_.K -like 'RAM|*' })
        'Grafik' = @($script:MetricDefs | Where-Object { $_.K -like 'GPU|*' }); 'Laufwerke' = @($lwDefs | Where-Object { $_.K -in 'LW|SR', 'LW|SW', 'LW|R1' }) }
    $ovRows = [System.Collections.Generic.List[object]]::new()
    foreach ($gn in $groups.Keys) {
        $defs = @($groups[$gn])
        $common = @($defs | Where-Object { $d = $_; @($sys | Where-Object { $_.Werte[$d.K] -gt 0 }).Count -eq $sys.Count })
        $use = $(if ($common.Count) { $common } else { $defs })
        $vals = @(foreach ($s in $sys) {
            $r = [System.Collections.Generic.List[double]]::new()
            $w = [System.Collections.Generic.List[double]]::new()
            foreach ($d in $use) {
                $rk = $(if ($d.R -and $refObj) { $d.R } else { $d.K }); $v = [double]$s.Werte[$d.K]; $rv = [double]$ref[$rk]
                if ($rv -le 0) { $rv = [double]$best[$d.K] }
                if ($v -gt 0 -and $rv -gt 0) {
                    $r.Add($(if ($d.L) { $rv / $v * 100 } else { $v / $rv * 100 }))
                    # Gemessene FPS-Renderleistung erhält 3-faches Gewicht gegenüber theoretischen Durchsatzwerten
                    $w.Add($(if ($gn -eq 'Grafik' -and $d.K -match 'REND|RPKT') { 3.0 } else { 1.0 }))
                }
            }
            Get-GeoMean $r $w
        })
        if (@($vals | Where-Object { $_ }).Count) { $ovRows.Add([pscustomobject]@{ N = $gn; V = $vals; Basis = (@($use | ForEach-Object { $_.N }) -join ', ') }) }
    }
    # Prozessor und Grafik erhalten im Gesamtwert ein höheres Gewicht (2x) als Arbeitsspeicher und Laufwerke (1x)
    $groupWeights = @{ 'Prozessor' = 2.0; 'Grafik' = 2.0; 'Arbeitsspeicher' = 1.0; 'Laufwerke' = 1.0 }
    $gesamt = @(for ($i = 0; $i -lt $sys.Count; $i++) {
        $x = [System.Collections.Generic.List[double]]::new()
        $gw = [System.Collections.Generic.List[double]]::new()
        foreach ($row in $ovRows) {
            if ($row.V[$i]) {
                $x.Add($row.V[$i])
                $gw.Add($(if ($groupWeights.ContainsKey($row.N)) { $groupWeights[$row.N] } else { 1.0 }))
            }
        }
        if ($x.Count -eq $ovRows.Count) { Get-GeoMean $x $gw } else { $null }
    })

    $sb = New-Object System.Text.StringBuilder
    $title = 'Systemvergleich ' + (($sys | ForEach-Object { $_.Label }) -join ', ')
    [void]$sb.Append(('<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{0}</title><style>{1}</style></head><body><main>' -f (ConvertTo-HtmlText $title), (Get-ReportCss)))
    [void]$sb.Append(('<header><div><h1>Leos Minibench <span>Systemvergleich</span></h1><p class="meta">{0} Systeme aus der Vergleichsdatenbank &middot; erstellt am {1:dd.MM.yyyy HH:mm} Uhr &middot; Version {2}</p></div></header>' -f $sys.Count, (Get-Date), $ScriptVersion))

    # Systemkarten
    [void]$sb.Append('<section class="syscards">')
    for ($i = 0; $i -lt $sys.Count; $i++) {
        $s = $sys[$i]; $hw = $s.Hw
        $bf = $s.Befunde
        $dat = $s.Datum; try { $dat = [datetime]::ParseExact($s.Datum, 'yyyy-MM-dd HH:mm', $script:Inv).ToString('dd.MM.yyyy HH:mm') } catch { }
        [void]$sb.Append(('<div class="sys k{0}"><h3><i class="sw c{0}"></i>{1}</h3><p class="meta">{2}{3}</p><dl>' -f ($i % 6), (ConvertTo-HtmlText $s.Label), (ConvertTo-HtmlText $dat), $(if ($s.Messdauer -and $s.Messdauer -ne 'normal') { ' &middot; Messdauer ' + (ConvertTo-HtmlText $s.Messdauer) } else { '' })))
        foreach ($kv in @(@('Prozessor', $hw.CPU), @('RAM', $hw.RAM), @('Grafik', $(if ($hw.GPUGemessen -and [string]$hw.GPUGemessen -notlike ('*' + [string]$hw.GPU + '*')) { '{0} (gemessen: {1})' -f $hw.GPU, $hw.GPUGemessen } elseif ($hw.IGPU) { '{0} + {1}' -f $hw.GPU, $hw.IGPU } else { $hw.GPU })), @('System', $s.System), @('Windows', ($hw.Betriebssystem -replace '^Microsoft\s+', '')), @('Installiert', $hw.WindowsInstalliert), @('Schnellstes LW', $s.Fastest))) {
            if ($kv[1]) { [void]$sb.Append(('<dt>{0}</dt><dd>{1}</dd>' -f $kv[0], (ConvertTo-HtmlText (Get-Short ([string]$kv[1]) 70)))) }
        }
        [void]$sb.Append('</dl>')
        if ($bf) { [void]$sb.Append(('<p class="bfc"><span class="badge crit">{0} kritisch</span> <span class="badge warn">{1} {2}</span> <span class="badge info">{3} {4}</span></p>' -f [int]$bf.Kritisch, [int]$bf.Warnungen, $(if ([int]$bf.Warnungen -eq 1) { 'Warnung' } else { 'Warnungen' }), [int]$bf.Hinweise, $(if ([int]$bf.Hinweise -eq 1) { 'Hinweis' } else { 'Hinweise' }))) }
        [void]$sb.Append('</div>')
    }
    [void]$sb.Append('</section>')

    $notes = @()
    if (@($sys | ForEach-Object { $_.Messdauer } | Select-Object -Unique).Count -gt 1) { $notes += 'Die Messdauer unterscheidet sich (kurz, normal oder unbekannt bei Importen). Kurze Messungen fallen meist einige Prozent niedriger aus.' }
    if (@($sys | Where-Object { $_.Quelle -like 'Import*' }).Count) { $notes += 'Importierte Läufe älterer Versionen enthalten nicht alle Messgrößen.' }
    if ($notes.Count) { [void]$sb.Append(('<p class="note">{0}</p>' -f (ConvertTo-HtmlText ($notes -join ' ')))) }

    if ($ovRows.Count) {
        [void]$sb.Append('<section class="box"><h2>Gesamtbild</h2>')
        [void]$sb.Append(('<p class="note">Geometrisches Mittel je Bereich in Prozent der Referenz ({0}). Gezählt werden nur Messgrößen, die alle Systeme haben. Prozessor und Grafik werden im Gesamtwert höher gewichtet (2×), bei der Grafik zählt die reale Renderleistung dreifach gegenüber Durchsatzwerten. Laufwerke: jeweils das schnellste Laufwerk im Vergleich zu NVMe PCIe 4.0.</p>' -f (ConvertTo-HtmlText $refLabel)))
        foreach ($r in $ovRows) { [void]$sb.Append((New-MetricBarsHtml -Label $r.N -Unit '%' -Fmt 'N0' -LowerBetter $false -Values $r.V -Names $names -Mode 'Best' -Hint $r.Basis -Own $own)) }
        if (@($gesamt | Where-Object { $_ }).Count) { [void]$sb.Append((New-MetricBarsHtml -Label 'Gesamt' -Unit '%' -Fmt 'N0' -LowerBetter $false -Values $gesamt -Names $names -Mode 'Best' -Hint 'Gewichtetes Mittel der Bereiche (Prozessor und Grafik 2×)' -Own $own)) }
        [void]$sb.Append('</section>')
    }

    # Einzelwerte je Bereich
    $sections = [ordered]@{
        'Prozessor' = @($script:MetricDefs | Where-Object { $_.K -like 'CPU|*' })
        'Arbeitsspeicher' = @($script:MetricDefs | Where-Object { $_.K -like 'RAM|*' })
        'Grafik' = @($script:MetricDefs | Where-Object { $_.K -like 'GPU|*' })
        'Laufwerke (jeweils das schnellste)' = $lwDefs
    }
    foreach ($sn in $sections.Keys) {
        $part = New-Object System.Text.StringBuilder
        foreach ($d in $sections[$sn]) {
            $vals = @(foreach ($s in $sys) { $(if ($s.Werte[$d.K] -gt 0) { [double]$s.Werte[$d.K] } else { $null }) })
            [void]$part.Append((New-MetricBarsHtml -Label $d.N -Unit $d.U -Fmt $d.F -LowerBetter ([bool]$d.L) -Values $vals -Names $names -Mode 'Best' -Own $own))
        }
        if ($part.Length) { [void]$sb.Append(('<section class="box"><h2>{0}</h2>{1}</section>' -f (ConvertTo-HtmlText $sn), $part.ToString())) }
    }

    # WinSAT, falls vorhanden
    $wsDefs = @(@('WINSAT|CPU', 'Prozessor'), @('WINSAT|RAM', 'Arbeitsspeicher'), @('WINSAT|DISK', 'Systemlaufwerk'), @('WINSAT|GFX', 'Grafik (Desktop)'))
    $wsPart = New-Object System.Text.StringBuilder
    foreach ($w in $wsDefs) {
        $vals = @(foreach ($s in $sys) { $(if ($s.Messwerte[$w[0]] -gt 0) { [double]$s.Messwerte[$w[0]] } else { $null }) })
        [void]$wsPart.Append((New-MetricBarsHtml -Label $w[1] -Unit 'von 9,9' -Fmt 'N1' -LowerBetter $false -Values $vals -Names $names -Mode 'Abs' -AbsMax 9.9 -Own $own))
    }
    if ($wsPart.Length) { [void]$sb.Append(('<section class="box"><h2>WinSAT-Bewertung</h2>{0}</section>' -f $wsPart.ToString())) }

    # alle gemessenen Laufwerke
    if (@($sys | Where-Object { $_.Laufwerke.Count }).Count) {
        [void]$sb.Append('<section class="box"><h2>Alle gemessenen Laufwerke</h2><div class="tw"><table class="disks"><thead><tr><th>System</th><th>Laufwerk</th><th>Klasse</th><th class="r">Lesen<br><small>MB/s</small></th><th class="r">Schreiben<br><small>MB/s</small></th><th class="r">4K QD1<br><small>IOPS</small></th><th class="r">4K 8 Thr.<br><small>IOPS</small></th><th class="r">4K schr.<br><small>IOPS</small></th></tr></thead><tbody>')
        $maxSR = [double](@($sys | ForEach-Object { $_.Laufwerke } | ForEach-Object { [double]$_.SR }) | Measure-Object -Maximum).Maximum
        # aufsteigend nach sequentiellem Lesen, das eigene System fett
        $rowsLw = @(for ($i = 0; $i -lt $sys.Count; $i++) { foreach ($d in $sys[$i].Laufwerke) { [pscustomobject]@{ I = $i; D = $d } } }) | Sort-Object { [double]$_.D.SR }
        foreach ($rw in $rowsLw) {
            $i = $rw.I; $d = $rw.D
            $n = { param($v) if ([double]$v -gt 0) { '{0:N0}' -f [double]$v } else { '' } }
            $bw = $(if ($maxSR -gt 0) { [math]::Max(2.0, [double]$d.SR / $maxSR * 100) } else { 0 })
            [void]$sb.Append([string]::Format($script:Inv, '<tr{10}><td class="nw"><i class="sw c{0}"></i>{1}</td><td>{2}</td><td class="muted">{3}</td><td class="num r"><span class="mini"><span class="mf c{0}" style="width:{4:0.#}%"></span></span>{5}</td><td class="num r">{6}</td><td class="num r">{7}</td><td class="num r">{8}</td><td class="num r">{9}</td></tr>',
                ($i % 6), (ConvertTo-HtmlText $sys[$i].Label), (ConvertTo-HtmlText $d.Laufwerk), (ConvertTo-HtmlText $d.Klasse), $bw, (& $n $d.SR), (& $n $d.SW), (& $n $d.R1), (& $n $d.R8), (& $n $d.W1), $(if ($i -eq $own) { ' style="font-weight:700"' } else { '' })))
        }
        [void]$sb.Append('</tbody></table></div></section>')
    }

    # Befunde je System
    $cls = @{ KRITISCH = 'crit'; WARNUNG = 'warn'; INFO = 'info' }
    [void]$sb.Append('<section class="box"><h2>Befunde der Läufe</h2>')
    for ($i = 0; $i -lt $sys.Count; $i++) {
        $s = $sys[$i]; $list = @($s.Befunde.Liste | Where-Object { $_ })
        [void]$sb.Append(('<details><summary><i class="sw c{0}"></i>{1} <span class="gref">{2} Einträge</span></summary>' -f ($i % 6), (ConvertTo-HtmlText $s.Label), $list.Count))
        if ($list.Count) {
            [void]$sb.Append('<table><tbody>')
            foreach ($l in $list) {
                $m = [regex]::Match([string]$l, '^\[(\w+)\]\s*([^:]+):\s*(.*)$')
                if ($m.Success) { $c = $cls[$m.Groups[1].Value.ToUpper()]; if (-not $c) { $c = 'info' }; [void]$sb.Append(('<tr><td><span class="badge {0}">{1}</span></td><td class="nw">{2}</td><td>{3}</td></tr>' -f $c, (ConvertTo-HtmlText $m.Groups[1].Value), (ConvertTo-HtmlText $m.Groups[2].Value), (ConvertTo-HtmlText $m.Groups[3].Value))) }
                else { [void]$sb.Append(('<tr><td colspan="3">{0}</td></tr>' -f (ConvertTo-HtmlText $l))) }
            }
            [void]$sb.Append('</tbody></table>')
        } else { [void]$sb.Append('<p class="empty">Keine Befunde gespeichert.</p>') }
        [void]$sb.Append('</details>')
    }
    [void]$sb.Append('</section>')
    [void]$sb.Append(('<footer>Leos Minibench {0}. Quellen: {1}</footer></main></body></html>' -f $ScriptVersion, (ConvertTo-HtmlText ((@($sys | ForEach-Object { Split-Path $_.Path -Leaf })) -join ', '))))

    $dir = $(if ($script:DataDir) { Join-Path $script:DataDir 'Berichte\Vergleiche' } else { Join-Path $env:TEMP 'LeosMinibench-Vergleiche' })
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    $file = Join-Path $dir ('Vergleich_{0}_{1}.html' -f (Get-SafeName ((@($sys | ForEach-Object { $_.Computer } | Select-Object -Unique) | Select-Object -First 4) -join '-')), (Get-Date -Format 'yyyyMMdd_HHmmss'))
    [IO.File]::WriteAllText($file, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))
    Write-Host ('Vergleich gespeichert: {0}' -f $file)
    return $file
}
#endregion

