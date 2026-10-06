# Lasttest im HTML-Bericht: Drosselnachweis und Kurven für Temperatur, Takt, Leistung und Lüfter.
# Ab v2.7 auch für den Benchmark: eigene Messreihe, Marken am Beginn jedes Abschnitts, ohne Drosselnachweis.
function New-LoadChartsHtml {
    param($Series = $script:LoadSeries, $Throttle = $script:LoadThrottle, $Abort = $script:LoadAbort, $Limits = $script:LoadLimits, $Marken = $null, $GpuLoad = $script:GpuLoad)
    $S = @($Series)
    $sb = New-Object System.Text.StringBuilder
    $pts = { param($prop) @($S | Where-Object { $null -ne $_.$prop -and "$($_.$prop)" -ne '' } | ForEach-Object { [pscustomobject]@{ T = $_.T; V = [double]$_.$prop } }) }
    $th = $Throttle
    if ($th) {
        $c = switch ($th.Status) { 'keine' { 'ok' } 'thermisch' { 'warn' } 'nicht bewertbar' { 'info' } default { $(if ($th.Stufe -eq 'WARNUNG') { 'warn' } else { 'info' }) } }
        $lab = switch ($th.Status) { 'keine' { 'Keine Drosselung' } 'thermisch' { 'Thermische Drosselung' } 'Leistungsgrenze' { 'Leistungsgrenze' } 'Firmware' { 'Begrenzung durch Firmware' } 'unklar' { 'Taktabfall ohne klaren Grund' } default { 'Nicht bewertbar' } }
        [void]$sb.Append(('<div class="thr {0}"><b>Drosselnachweis: {1}</b><br>{2}<ul>' -f $c, $lab, (ConvertTo-HtmlText $th.Befund)))
        foreach ($b in $th.Belege) { [void]$sb.Append(('<li>{0}</li>' -f (ConvertTo-HtmlText $b))) }
        [void]$sb.Append('</ul></div>')
    }
    # Marken: vorgegeben (Benchmark: Beginn je Abschnitt) oder aus dem Lasttest (Abbruch, Ende der CPU-Last, Takt sinkt).
    # Eigener Parametername: $Marks und $marks wären in PowerShell dieselbe Variable.
    $marks = @()
    if ($null -ne $Marken) { $marks = @($Marken) }
    else {
        $cpuEnd = @($S | Where-Object { $_.Cpu } | Select-Object -Last 1)
        if ($Abort) { $marks += @{ T = $Abort.T; Label = 'Abbruch' } }
        elseif ($cpuEnd.Count -and @($S | Where-Object { -not $_.Cpu -and $_.T -gt $cpuEnd[0].T }).Count) { $marks += @{ T = $cpuEnd[0].T; Label = 'CPU-Last Ende' } }
        if ($th -and $th.Beginn -and $th.Status -ne 'keine') { $marks += @{ T = $th.Beginn; Label = 'Takt sinkt' } }
    }
    # Temperatur: Sensorwerte, sonst ACPI-Thermalzone (nur wenn veränderlich)
    $ser = @()
    $cpuSens = @($S | Where-Object { $null -ne $_.CpuTemp -and $_.CpuTempQ -ne 'ACPI' })
    if ($cpuSens.Count -ge 2) { $ser += @{ Name = 'CPU'; Cls = 's1'; Points = @($cpuSens | ForEach-Object { [pscustomobject]@{ T = $_.T; V = [double]$_.CpuTemp } }) } }
    elseif (@($S | Where-Object { $_.Temp } | ForEach-Object { $_.Temp } | Select-Object -Unique).Count -gt 1) { $ser += @{ Name = 'ACPI-Thermalzone (keine Kerntemperatur)'; Cls = 's1'; Points = (& $pts 'Temp') } }
    $ser += @{ Name = 'GPU'; Cls = 's2'; Points = (& $pts 'GpuTemp') }
    $ser += @{ Name = 'Prozessorgrafik'; Cls = 's5'; Points = (& $pts 'IGpuTemp') }
    $ser += @{ Name = 'Datenträger'; Cls = 's3'; Points = (& $pts 'DiskTemp') }
    $refs = @()
    if ($Limits -and $Limits.Cpu -gt 0 -and $cpuSens.Count) { $refs += @{ V = $Limits.Cpu; Label = ('Abbruchschwelle CPU {0:N0} °C' -f $Limits.Cpu); Cls = 'lim' } }
    if ($Limits -and $Limits.TjMax -and $cpuSens.Count -and $Limits.TjMax -ne $Limits.Cpu) { $refs += @{ V = $Limits.TjMax; Label = ('TjMax {0:N0} °C' -f $Limits.TjMax); Cls = 'tj' } }
    $svg = New-MultiLineSvg $ser '°C' $refs $marks
    if ($svg) { [void]$sb.Append('<h3>Temperatur (°C)</h3>' + $svg) }
    $ser = @()
    if (@($S | ForEach-Object { $_.MHz } | Select-Object -Unique).Count -gt 1) { $ser += @{ Name = 'CPU'; Cls = 's1'; Points = (& $pts 'MHz') } }
    $ser += @{ Name = 'CPU höchster Kerntakt'; Cls = 's4'; Points = (& $pts 'CpuMHz') }
    $ser += @{ Name = 'GPU'; Cls = 's2'; Points = (& $pts 'GpuMHz') }
    $ser += @{ Name = 'Prozessorgrafik'; Cls = 's5'; Points = (& $pts 'IGpuMHz') }
    $svg = New-MultiLineSvg $ser 'MHz' @() $marks
    if ($svg) { [void]$sb.Append('<h3>Takt (MHz)</h3>' + $svg) }
    $svg = New-MultiLineSvg @(@{ Name = 'CPU-Paket'; Cls = 's1'; Points = (& $pts 'CpuW') }, @{ Name = 'GPU'; Cls = 's2'; Points = (& $pts 'GpuW') }, @{ Name = 'Prozessorgrafik'; Cls = 's5'; Points = (& $pts 'IGpuW') }) 'W' @() $marks
    if ($svg) { [void]$sb.Append('<h3>Leistung (W)</h3>' + $svg) }
    # Bilder/s des Rendertests (ab v2.6): je Grafikeinheit eine Kurve
    $gl = @($GpuLoad)
    $svg = New-MultiLineSvg @(@{ Name = $(if ($gl.Count) { '{0} ({1})' -f $gl[0].Name, $gl[0].Bezeichnung } else { 'Grafik' }); Cls = 's2'; Points = (& $pts 'Fps') }, @{ Name = $(if ($gl.Count -gt 1) { '{0} ({1})' -f $gl[1].Name, $gl[1].Bezeichnung } else { 'Grafik 2' }); Cls = 's5'; Points = (& $pts 'Fps2') }) 'Bilder/s' @() $marks
    if ($svg) { [void]$sb.Append('<h3>Rendertest (Bilder/s)</h3>' + $svg) }
    $svg = New-MultiLineSvg @(@{ Name = 'GPU'; Cls = 's2'; Points = (& $pts 'GpuLoad') }, @{ Name = 'Prozessorgrafik'; Cls = 's5'; Points = (& $pts 'IGpuLoad') }) '%' @() $marks
    if ($svg -and $gl.Count) { [void]$sb.Append('<h3>Grafik-Auslastung (%)</h3>' + $svg) }
    $svg = New-MultiLineSvg @(@{ Name = 'Lüfter'; Cls = 's3'; Points = (& $pts 'Fan') }) 'U/min' @() $marks
    if ($svg) { [void]$sb.Append('<h3>Lüfter (U/min)</h3>' + $svg) }
    if ($S.Count -and -not $cpuSens.Count) { [void]$sb.Append(('<p class="note tight">Keine echte CPU-Temperatur{0}: {1}.</p>' -f $(if (@($S | Where-Object { $_.CpuW -gt 0 }).Count) { '' } else { ' und keine CPU-Leistung' }), (ConvertTo-HtmlText (Get-SensorGapText)))) }
    return $sb.ToString()
}

# Akku: Kennzahlen und Kapazitätsverlauf (volle Ladekapazität über die Zeit, Designkapazität als Bezugslinie)
function New-BatteryHtml {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<section class="box" data-section="hardware"><h2>Akku</h2>')
    foreach ($b in @($script:BatteryInfo)) {
        $wear = $b.VerschleissProzent
        $c = $(if ($null -eq $wear) { 'info' } elseif ($wear -ge 50) { 'warn' } elseif ($wear -ge 30) { 'info' } else { 'ok' })
        [void]$sb.Append(('<p><b>{0}</b>{1} &middot; Verschleiß <span class="badge {2}">{3}</span></p><dl>' -f (ConvertTo-HtmlText $b.Name), $(if ($b.Hersteller -or $b.Chemie) { ' (' + (ConvertTo-HtmlText ((@($b.Hersteller, $b.Chemie) | Where-Object { $_ }) -join ', ')) + ')' } else { '' }), $c, $(if ($null -ne $wear) { '{0:N1} %' -f $wear } else { 'nicht ermittelbar' })))
        foreach ($kv in @(@('Designkapazität', $(if ($b.DesignmWh) { '{0:N0} mWh' -f $b.DesignmWh })), @('Volle Ladekapazität', $(if ($b.VollmWh) { '{0:N0} mWh' -f $b.VollmWh })), @('Ladezyklen', $(if ($null -ne $b.Zyklen) { '{0:N0}' -f $b.Zyklen } else { 'nicht gemeldet' })),
                @('Geschätzte Laufzeit', $(if ($b.LaufzeitVoll) { (Format-Duration $b.LaufzeitVoll) + $(if ($b.LaufzeitDesign) { ', im Neuzustand ' + (Format-Duration $b.LaufzeitDesign) } else { '' }) })), @('Quelle', $b.Quelle))) {
            if ($kv[1]) { [void]$sb.Append(('<dt>{0}</dt><dd>{1}</dd>' -f $kv[0], (ConvertTo-HtmlText ([string]$kv[1])))) }
        }
        [void]$sb.Append('</dl>')
        $hist = @($b.Verlauf | Where-Object { $_.VollmWh })
        if ($hist.Count -ge 2) {
            $pts = @(for ($i = 0; $i -lt $hist.Count; $i++) { [pscustomobject]@{ T = $i * 60; V = [double]$hist[$i].VollmWh } })
            $refs = @(); if ($b.DesignmWh) { $refs += @{ V = [double]$b.DesignmWh; Label = ('Designkapazität {0:N0} mWh' -f $b.DesignmWh); Cls = 'tj' } }
            $svg = New-MultiLineSvg @(@{ Name = 'volle Ladekapazität'; Cls = 's1'; Points = $pts }) 'mWh' $refs @()
            if ($svg) { [void]$sb.Append(('<h3>Kapazitätsverlauf ({0} bis {1})</h3>' -f (ConvertTo-HtmlText (($hist[0].Zeitraum -split ' bis ')[0])), (ConvertTo-HtmlText (($hist[$hist.Count - 1].Zeitraum -split ' bis ')[-1]))) + ($svg -replace '>(\d+) min<', '><')) }
        }
    }
    [void]$sb.Append('<p class="note tight">Verschleiß = 1 minus volle Ladekapazität durch Designkapazität. Ab 30 % ist die Laufzeit spürbar kürzer, ab 50 % lohnt ein Austausch.</p></section>')
    return $sb.ToString()
}

function Get-ReportJs {
    return @'
<script>
function switchSection(sec, btn) {
    var tabs = document.querySelectorAll('.tab-btn');
    for (var i = 0; i < tabs.length; i++) tabs[i].classList.remove('active');
    if (btn) btn.classList.add('active');
    var sections = document.querySelectorAll('main > section');
    for (var i = 0; i < sections.length; i++) {
        var s = sections[i];
        var ds = s.getAttribute('data-section');
        if (!ds || sec === 'all' || ds === sec) {
            s.style.display = '';
        } else {
            s.style.display = 'none';
        }
    }
}
var currentLevel = 'all';
function setLevelFilter(lvl, btn) {
    currentLevel = lvl;
    var chips = document.querySelectorAll('.fchip');
    for (var i = 0; i < chips.length; i++) chips[i].classList.remove('active');
    if (btn) btn.classList.add('active');
    filterBefunde();
}
function filterBefunde() {
    var input = document.getElementById('befundSearch');
    var q = input ? input.value.toLowerCase().trim() : '';
    var table = document.getElementById('befundeTable');
    if (!table) return;
    var rows = table.querySelectorAll('tbody tr');
    var visible = 0;
    for (var i = 0; i < rows.length; i++) {
        var tr = rows[i];
        var lvlCell = tr.querySelector('td[data-level]');
        var lvl = lvlCell ? lvlCell.getAttribute('data-level') : '';
        var text = tr.textContent.toLowerCase();
        var matchLvl = (currentLevel === 'all' || lvl === currentLevel);
        var matchQuery = (!q || text.indexOf(q) !== -1);
        if (matchLvl && matchQuery) {
            tr.style.display = '';
            visible++;
        } else {
            tr.style.display = 'none';
        }
    }
    var countEl = document.getElementById('befundCount');
    if (countEl) {
        countEl.textContent = visible + ' von ' + rows.length + ' Befunden';
    }
}
function initBefundCounts() {
    var table = document.getElementById('befundeTable');
    if (!table) return;
    var rows = table.querySelectorAll('tbody tr');
    var total = rows.length;
    var crit = 0, warn = 0, info = 0;
    for (var i = 0; i < rows.length; i++) {
        var lvlCell = rows[i].querySelector('td[data-level]');
        var lvl = lvlCell ? lvlCell.getAttribute('data-level') : '';
        if (lvl === 'KRITISCH') crit++;
        else if (lvl === 'WARNUNG') warn++;
        else if (lvl === 'INFO') info++;
    }
    var elAll = document.getElementById('cntAll'); if (elAll) elAll.textContent = total;
    var elCrit = document.getElementById('cntCrit'); if (elCrit) elCrit.textContent = crit;
    var elWarn = document.getElementById('cntWarn'); if (elWarn) elWarn.textContent = warn;
    var elInfo = document.getElementById('cntInfo'); if (elInfo) elInfo.textContent = info;
    var countEl = document.getElementById('befundCount'); if (countEl) countEl.textContent = total + ' Befunde';
}
(function() {
    var tip = document.createElement('div');
    tip.className = 'chart-tooltip';
    tip.style.opacity = '0';
    document.body.appendChild(tip);
    document.addEventListener('mouseover', function(e) {
        var hit = e.target.closest('.hit');
        if (hit && hit.getAttribute('data-tip')) {
            tip.textContent = hit.getAttribute('data-tip');
            tip.style.opacity = '1';
        }
    });
    document.addEventListener('mousemove', function(e) {
        if (tip.style.opacity === '1') {
            tip.style.left = (e.pageX + 12) + 'px';
            tip.style.top = (e.pageY - 28) + 'px';
        }
    });
    document.addEventListener('mouseout', function(e) {
        var hit = e.target.closest('.hit');
        if (hit) {
            tip.style.opacity = '0';
        }
    });
})();
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initBefundCounts);
} else {
    initBefundCounts();
}
</script>
'@
}

function New-HtmlReport {
    param([string]$Path, $Sorted, [int]$NK, [int]$NW, [int]$NI, [datetime]$Start, [datetime]$End)
    $cls = @{ KRITISCH = 'crit'; WARNUNG = 'warn'; INFO = 'info'; OK = 'ok'; FEHLER = 'crit'; 'ÜBERSPRUNGEN' = 'skip'; REPARIERT = 'ok'; NEUSTART = 'info' }
    if ($NK) { $vc = 'crit'; $vt = 'Kritische Befunde' } elseif ($NW) { $vc = 'warn'; $vt = 'Warnungen vorhanden' } else { $vc = 'ok'; $vt = 'Keine Auffälligkeiten' }
    $modus = Get-ModeLabel
    $kiLeaf = $(if ($kiFile) { Split-Path $kiFile -Leaf } else { 'KI-Analyse.txt' })
    $css = Get-ReportCss
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
    [void]$sb.Append(('<title>Leos Minibench {0}</title><style>{1}</style></head><body><main>' -f (ConvertTo-HtmlText $env:COMPUTERNAME), $css))
    [void]$sb.Append(('<header><div><h1>Leos Minibench <span>{0}</span></h1><p class="meta">{1:dd.MM.yyyy HH:mm} bis {2:HH:mm} Uhr &middot; Dauer {3:hh\:mm\:ss} &middot; Modus {4} &middot; Risikostufe {8} &middot; Version {5}</p></div><div class="verdict {6}">{7}</div></header>' -f `
        (ConvertTo-HtmlText $env:COMPUTERNAME), $Start, $End, ($End - $Start), (ConvertTo-HtmlText $modus), $ScriptVersion, $vc, $vt, (Get-RiskLabel (Get-RunRisk))))
    $compParam = [uri]::EscapeDataString($env:COMPUTERNAME)
    [void]$sb.Append(('<nav class="report-nav"><button type="button" class="tab-btn active" onclick="switchSection(''all'', this)">Alle Abschnitte</button><button type="button" class="tab-btn" onclick="switchSection(''system'', this)">Systemübersicht</button><button type="button" class="tab-btn" onclick="switchSection(''benchmark'', this)">Benchmark</button><button type="button" class="tab-btn" onclick="switchSection(''befunde'', this)">Befunde</button><button type="button" class="tab-btn" onclick="switchSection(''hardware'', this)">Hardware</button><button type="button" class="tab-btn" onclick="switchSection(''sensoren'', this)">Sensoren</button><a href="../Dashboard.html?system={0}" class="tab-btn btn-dash" target="_blank" title="Vergleichsdashboard für diesen PC im neuen Tab öffnen">📊 Vergleichsdashboard</a></nav>' -f $compParam))
    $stCard = ''
    if ($script:Stability) { $stCard = ('<div class="card st {0}"><b>{1}</b><span>Zuverlässigkeit von 10 ({2})</span></div>' -f $script:Stability.Klasse, ('{0:N1}' -f $script:Stability.Index), (ConvertTo-HtmlText $script:Stability.Stufe)) }
    $benchCard = ''
    $overall = Get-BenchOverall
    if ($null -ne $overall -and [double]$overall -gt 0) {
        $benchCard = ('<div class="card bench"><b>{0} %</b><span>Gesamtleistung (Referenz)</span></div>' -f [math]::Round([double]$overall))
    }
    [void]$sb.Append(('<section class="cards" data-section="system"><div class="card crit"><b>{0}</b><span>kritisch</span></div><div class="card warn"><b>{1}</b><span>Warnungen</span></div><div class="card info"><b>{2}</b><span>Hinweise</span></div>{3}{4}</section>' -f $NK, $NW, $NI, $stCard, $benchCard))
    if ($script:Stability -and $script:Stability.Erklaerung) { [void]$sb.Append(('<section class="box stab {0}" data-section="system"><h2>Zuverlässigkeit {1:N1} von 10</h2><p>{2}</p></section>' -f $script:Stability.Klasse, $script:Stability.Index, (ConvertTo-HtmlText $script:Stability.Erklaerung))) }

    if ($script:Facts.Count) {
        [void]$sb.Append('<section class="box" data-section="hardware"><h2>System</h2><dl>')
        foreach ($k in $script:Facts.Keys) { [void]$sb.Append(('<dt>{0}</dt><dd>{1}</dd>' -f (ConvertTo-HtmlText $k), ((ConvertTo-HtmlText ([string]$script:Facts[$k])) -replace "`r?`n", '<br>'))) }
        [void]$sb.Append('</dl></section>')
    }

    if (@($script:BatteryInfo).Count) { [void]$sb.Append((New-BatteryHtml)) }

    [void]$sb.Append('<section class="box" data-section="befunde"><h2>Befunde</h2>')
    if ($Sorted.Count) {
        [void]$sb.Append('<div class="filter-bar"><input type="text" id="befundSearch" class="search-input" placeholder="Befunde durchsuchen (Stufe, Bereich, Text)..." oninput="filterBefunde()"><div class="filter-chips"><button type="button" class="fchip active" data-level="all" onclick="setLevelFilter(''all'', this)">Alle (<span id="cntAll">0</span>)</button><button type="button" class="fchip chip-crit" data-level="KRITISCH" onclick="setLevelFilter(''KRITISCH'', this)">Kritisch (<span id="cntCrit">0</span>)</button><button type="button" class="fchip chip-warn" data-level="WARNUNG" onclick="setLevelFilter(''WARNUNG'', this)">Warnung (<span id="cntWarn">0</span>)</button><button type="button" class="fchip chip-info" data-level="INFO" onclick="setLevelFilter(''INFO'', this)">Hinweis (<span id="cntInfo">0</span>)</button></div><span id="befundCount" class="filter-count"></span></div>')
        [void]$sb.Append('<table id="befundeTable"><thead><tr><th>Stufe</th><th>Bereich</th><th>Befund</th></tr></thead><tbody>')
        foreach ($f in $Sorted) { [void]$sb.Append(('<tr><td data-level="{0}"><span class="badge {1}">{0}</span></td><td>{2}</td><td>{3}</td></tr>' -f $f.Stufe, $cls[$f.Stufe], (ConvertTo-HtmlText $f.Bereich), (ConvertTo-HtmlText $f.Befund))) }
        [void]$sb.Append('</tbody></table>')
    } else { [void]$sb.Append('<p class="empty">Keine Auffälligkeiten gefunden.</p>') }
    [void]$sb.Append('</section>')

    if ($script:TestResults.Count) {
        [void]$sb.Append('<section class="box" data-section="befunde"><h2>Tests</h2><table><thead><tr><th>Test</th><th>Ergebnis</th><th>Details</th></tr></thead><tbody>')
        foreach ($t in $script:TestResults) {
            $c = $cls[[string]$t.Ergebnis]; if (-not $c) { $c = 'info' }
            [void]$sb.Append(('<tr><td>{0}</td><td><span class="badge {1}">{2}</span></td><td>{3}</td></tr>' -f (ConvertTo-HtmlText $t.Test), $c, (ConvertTo-HtmlText $t.Ergebnis), (ConvertTo-HtmlText $t.Details)))
        }
        [void]$sb.Append('</tbody></table></section>')
    }

    if (@($script:Minidumps).Count) {
        [void]$sb.Append('<section class="box" data-section="hardware"><h2>Absturzabbilder (Crash Dumps)</h2><div class="tw"><table><thead><tr><th>Zeitpunkt</th><th>Datei</th><th>Stoppcode / Fehler</th><th>Parameter</th><th>Empfehlung</th></tr></thead><tbody>')
        foreach ($d in @($script:Minidumps)) {
            $params = @($d.Parameter1, $d.Parameter2, $d.Parameter3, $d.Parameter4 | Where-Object { $_ -and $_ -ne '0x0' }) -join ', '
            [void]$sb.Append(('<tr><td class="num">{0:dd.MM.yyyy HH:mm}</td><td><code>{1}</code></td><td><b>{2}</b><br><small class="muted">{3}</small></td><td class="num"><small>{4}</small></td><td>{5}</td></tr>' -f
                $d.Zeit, (ConvertTo-HtmlText $d.Datei), (ConvertTo-HtmlText $d.Bugcheck), (ConvertTo-HtmlText $d.Name), (ConvertTo-HtmlText $params), (ConvertTo-HtmlText $d.Empfehlung)))
        }
        [void]$sb.Append('</tbody></table></div></section>')
    }

    if ($script:BenchResults.Count -or $script:BenchDisks.Count) {
        $bcls = @{ OK = 'ok'; Info = 'info'; Warnung = 'warn'; Fehler = 'crit' }
        $idxHtml = {
            param($Index, [string]$Status, [switch]$Small)
            if ($null -eq $Index -or "$Index" -eq '') { return '' }
            $c = $bcls[$Status]; if (-not $c) { $c = 'info' }
            $w = [math]::Round([math]::Min(150.0, [math]::Max(0.0, [double]$Index)) / 150.0 * 100.0, 1)
            return [string]::Format($script:Inv, '<span class="ib{3}" title="Index {2}, 100 = typisch"><span class="ibf {0}" style="width:{1}%"></span><span class="ibm"></span></span><b>{2}</b>', $c, $w, $Index, $(if ($Small) { ' s' } else { '' }))
        }
        $refDat = ''; try { if ($script:Ref.Datum) { $refDat = ' vom ' + [datetime]::ParseExact([string]$script:Ref.Datum, 'yyyy-MM-dd', $script:Inv).ToString('dd.MM.yyyy') } } catch { $refDat = ' vom ' + $script:Ref.Datum }
        $refNote = $(if ($script:RefSavedNow -and -not (Test-HasReference)) { ' Dieser Lauf wurde als Referenz gespeichert; ab dem nächsten Lauf ist dieser PC 100 %.' }
            elseif ($script:RefSavedNow) { ' Referenz 100 % = {0}{1}; dieser Lauf wurde als neue Referenz gespeichert und gilt ab dem nächsten Lauf.' -f $script:Ref.Name, $refDat } elseif (Test-HasReference) { ' Referenz 100 % = {0}{1}, Laufwerke im Vergleich zur gleichen Klasse.' -f $script:Ref.Name, $refDat } else { ' Keine Referenz festgelegt (Haken "Dieses System als Referenz festlegen" im Benchmark).' })
        [void]$sb.Append('<section class="box" data-section="benchmark"><div class="bar"><h2>Leistung (Benchmark)</h2><button onclick="var d=this.closest(''section'').querySelectorAll(''details''),o=!d[0].open;for(var i=0;i<d.length;i++)d[i].open=o">Alle auf- oder zuklappen</button></div>')
        [void]$sb.Append((New-ProfileCards))
        [void]$sb.Append((New-BenchOverview))
        [void]$sb.Append(('<p class="note">Kacheln: Ergebnis je Bereich in Prozent der Referenz (Strich = 100 %).{0} Im Gesamtbild werden Prozessor und Grafik höher gewichtet; bei der Grafik zählt die gemessene FPS-Renderleistung dreifach gegenüber Durchsatzwerten. Index 100 in den Tabellen entspricht dem typischen Wert der Hardwareklasse. Vergleich bezieht sich auf frühere Läufe auf diesem PC, grün besser, orange mindestens 10 % schlechter.</p>' -f (ConvertTo-HtmlText $refNote)))
        if (@($script:BenchRefRows).Count) {
            [void]$sb.Append(('<details class="grp"><summary><span class="gname">Referenzwerte</span><span class="gsub">{0}</span></summary><div class="tw"><table><thead><tr><th>Messgröße</th><th class="r">Referenz</th><th>Herkunft</th></tr></thead><tbody>' -f (ConvertTo-HtmlText $script:Ref.Name)))
            foreach ($r in @($script:BenchRefRows)) { [void]$sb.Append(('<tr><td>{0}</td><td class="num r">{1}</td><td>{2}</td></tr>' -f (ConvertTo-HtmlText $r.'Messgröße'), (ConvertTo-HtmlText $r.Referenz), (ConvertTo-HtmlText $r.Herkunft))) }
            [void]$sb.Append('</tbody></table></div></details>')
        }
        foreach ($gk in $script:BenchGroupOrder) {
            $g = Get-BenchGroup $gk
            if (-not $g.Anzahl) { continue }
            $gc = $bcls[$g.Status]; if (-not $gc) { $gc = 'info' }
            $open = $(if ((Get-StatusRank $g.Status) -ge 2 -or $gk -eq 'WinSAT') { ' open' } else { '' })
            [void]$sb.Append(('<details class="grp" id="bg-{6}"{0}><summary><span class="gname">{1}</span>{3}<span class="badge {4}">{5}</span></summary>' -f $open,
                (ConvertTo-HtmlText $g.Name), '', $(if ($g.Referenz) { '<span class="gref" title="im Vergleich zur Referenz">Referenz <b>' + $g.Referenz + '</b></span>' } else { '' }), $gc, (ConvertTo-HtmlText $g.Status), $gk))
            if ($gk -ne 'WinSAT') {
                $compName = $(if ($script:BenchHead.ContainsKey($gk) -and $script:BenchHead[$gk]) { [string]$script:BenchHead[$gk] } elseif ($g.Kopf) { $g.Kopf } else { $g.Name })
                $word = if ($null -ne $g.RefPct -and [double]$g.RefPct -gt 0) { Get-BenchRatingWord $g.RefPct } else { '' }
                $scorePart = if ($null -ne $g.RefPct -and [double]$g.RefPct -gt 0) { ('<b>{0} %</b> &middot; <span class="pword">{1}</span>' -f $g.RefPct, (ConvertTo-HtmlText $word)) } else { '' }
                $bar = if ($null -ne $g.RefPct -and [double]$g.RefPct -gt 0) { ('<div class="gh-bar">{0}</div>' -f (Get-RefBar $g.RefPct $gc)) } else { '' }
                [void]$sb.Append(('<div class="grp-head"><div><div class="comp-title">{0}</div>{1}</div><div class="comp-score">{2}</div></div>' -f
                    (ConvertTo-HtmlText $compName), $bar, $scorePart))
            }
            if ($gk -eq 'WinSAT') {
                [void]$sb.Append((New-WinsatSvg $g.Items $script:WinsatTotal))
                [void]$sb.Append('<p class="note tight">Windows-Leistungsbewertung auf einer Skala von 1,0 bis 9,9. Die gestrichelte Linie zeigt den Gesamtwert, er entspricht dem niedrigsten Teilwert. Die Spielegrafik-Bewertung ist seit Windows 10 fest auf 9,9 gesetzt und fehlt deshalb.</p>')
            } elseif ($gk -eq 'Laufwerke') {
                [void]$sb.Append('<div class="tw"><table class="disks"><thead><tr><th>Laufwerk</th><th>Klasse</th><th class="r">Lesen<br><small>MB/s</small></th><th class="r">Schreiben<br><small>MB/s</small></th><th class="r">4K QD1<br><small>IOPS</small></th><th class="r">4K 8 Thr.<br><small>IOPS</small></th><th class="r">4K schr.<br><small>IOPS</small></th><th>Index</th><th>Referenz</th><th>Ergebnis</th></tr></thead><tbody>')
                foreach ($d in $g.Disks) {
                    $c = $bcls[$d.Status]; if (-not $c) { $c = 'info' }
                    $n = { param($v) if ([double]$v -gt 0) { '{0:N0}' -f [double]$v } else { '' } }
                    [void]$sb.Append(('<tr title="{0}"><td>{1}</td><td class="muted">{2}</td><td class="num r">{3}</td><td class="num r">{4}</td><td class="num r">{5}</td><td class="num r">{6}</td><td class="num r">{7}</td><td class="idx">{8}</td><td class="num nw">{9}</td><td><span class="badge {10}">{11}</span></td></tr>' -f
                        (ConvertTo-HtmlText (($d.Hinweis, $d.Vergleich | Where-Object { $_ }) -join '; ')), (ConvertTo-HtmlText $d.Laufwerk), (ConvertTo-HtmlText $d.Klasse),
                        (& $n $d.SR), (& $n $d.SW), (& $n $d.R1), (& $n $d.R8), (& $n $d.W1), (& $idxHtml $d.Index $d.Status -Small), ((Get-RefBar $d.RefPct 'info' -Small) + (ConvertTo-HtmlText $d.Referenz)), $c, (ConvertTo-HtmlText $d.Status)))
                }
                [void]$sb.Append('</tbody></table></div><p class="note tight">Lesen und Schreiben sequentiell mit 1 MiB-Blöcken, 4K-Werte in Zugriffen pro Sekunde, jeweils ohne Windows-Cache. Details beim Überfahren einer Zeile.</p>')
            } else {
                [void]$sb.Append('<div class="tw"><table><thead><tr><th>Messung</th><th class="r">Wert</th><th>Index</th><th>Referenz</th><th>Vergleich</th><th>Ergebnis</th></tr></thead><tbody>')
                foreach ($b in $g.Items) {
                    $c = $bcls[[string]$b.Status]; if (-not $c) { $c = 'info' }
                    [void]$sb.Append(('<tr><td>{0}{1}</td><td class="num r">{2}</td><td class="idx">{3}</td><td class="num nw">{4}</td><td class="nw">{5}</td><td><span class="badge {6}">{7}</span></td></tr>' -f
                        (ConvertTo-HtmlText $b.Messung), $(if ($b.Hinweis) { '<small class="hint">' + (ConvertTo-HtmlText $b.Hinweis) + '</small>' } else { '' }), (ConvertTo-HtmlText $b.Anzeige),
                        (& $idxHtml $b.Index $b.Status), ((Get-RefBar $b.RefPct 'info' -Small) + (ConvertTo-HtmlText $b.Referenz)), (Get-DeltaHtml $b.Vergleich), $c, (ConvertTo-HtmlText $b.Status)))
                }
                [void]$sb.Append('</tbody></table></div>')
                if ($gk -eq 'GPU') { [void]$sb.Append((New-RenderChartsHtml)) }
            }
            [void]$sb.Append('</details>')
        }
        [void]$sb.Append('</section>')
    }
    if ($script:CmpRows.Count) {
        $cn = [string[]](@('Dieser PC') + @($script:CmpSystems | ForEach-Object { $_.Computer }))
        [void]$sb.Append('<section class="box" data-section="benchmark"><h2>Vergleich mit bereits geprüften Systemen</h2><p class="note">')
        for ($k = 0; $k -lt $cn.Count; $k++) { [void]$sb.Append(('<i class="sw c{0}"></i>{1}{2}&nbsp;&nbsp; ' -f $k, (ConvertTo-HtmlText $cn[$k]), $(if ($k) { ' (' + (ConvertTo-HtmlText $script:CmpSystems[$k - 1].Datum) + ')' } else { '' }))) }
        [void]$sb.Append(('<br>Längerer Balken = besser. Prozent: Abstand des anderen Systems zu diesem PC, grün = das andere System ist besser. Platz: Rang dieses PCs unter allen Systemen der Datenbank.</p><div style="margin:12px 0 16px"><a href="../Dashboard.html?system={0}" class="tab-btn btn-dash" target="_blank">📊 Interaktives Vergleichsdashboard öffnen (dieser PC vorausgewählt) &rarr;</a></div>' -f $compParam))
        $lastG = ''
        foreach ($r in $script:CmpRows) {
            $gname = $script:GroupOfKey[($r.Key -split '\|')[0]]
            if ($gname -ne $lastG) { [void]$sb.Append(('<div class="mgh">{0}</div>' -f (ConvertTo-HtmlText $gname))); $lastG = $gname }
            [void]$sb.Append((New-MetricBarsHtml -Label $r.Messung -Unit $r.Einheit -Fmt $r.Format -LowerBetter $r.LowerBetter -Values (@($r.Dieses) + @($r.Werte)) -Names $cn -Mode 'Base' -Extra $r.Rang))
        }
        [void]$sb.Append('</section>')
    }
    # ab v2.7: Sensoren während des Benchmarks (Tabelle je Abschnitt und Kurven wie im Lasttest)
    if (@($script:BenchSensorRows).Count) {
        [void]$sb.Append('<section class="box" data-section="sensoren"><h2>Sensoren während des Benchmarks</h2>')
        [void]$sb.Append(('<p class="note">{0}. Messpunkte in den Wartepausen der Messungen, höchstens alle 2 Sekunden.</p>' -f (ConvertTo-HtmlText (Get-SensorSourceText))))
        $tab = @(Format-BenchSensorTable $script:BenchSensorRows)
        if ($tab.Count) {
            $hd = @($tab[0].PSObject.Properties | ForEach-Object { $_.Name })
            [void]$sb.Append('<div class="tw"><table><thead><tr>')
            foreach ($c in $hd) { [void]$sb.Append(('<th{0}>{1}</th>' -f $(if ($c -in 'Abschnitt', 'Dauer') { '' } else { ' class="r"' }), (ConvertTo-HtmlText $c))) }
            [void]$sb.Append('</tr></thead><tbody>')
            foreach ($r in $tab) {
                [void]$sb.Append('<tr>')
                foreach ($c in $hd) { [void]$sb.Append(('<td{0}>{1}</td>' -f $(if ($c -in 'Abschnitt', 'Dauer') { '' } else { ' class="num r nw"' }), (ConvertTo-HtmlText ([string]$r.$c)))) }
                [void]$sb.Append('</tr>')
            }
            [void]$sb.Append('</tbody></table></div>')
        }
        if (@($script:BenchSeries).Count -ge 2) {
            $bm = @(@($script:BenchSens.Teile) | Where-Object { $_.Beginn -gt 0 } | ForEach-Object { @{ T = $_.Beginn; Label = $_.Teil } })
            $bl = $(if ($script:BenchSens -and $script:BenchSens.TjMax) { [pscustomobject]@{ Cpu = 0; Gpu = 0; TjMax = $script:BenchSens.TjMax } } else { $null })
            [void]$sb.Append((New-LoadChartsHtml -Series $script:BenchSeries -Throttle $null -Abort $null -Limits $bl -Marken $bm -GpuLoad @()))
        }
        [void]$sb.Append('</section>')
    }
    if ($script:LoadSeries.Count -ge 2 -or $script:LoadParts.Count) {
        [void]$sb.Append('<section class="box" data-section="sensoren"><h2>Lasttest</h2>')
        [void]$sb.Append(('<p class="note">{0}</p>' -f (ConvertTo-HtmlText $script:LoadSummary)))
        if ($script:LoadParts.Count) {
            [void]$sb.Append('<table><thead><tr><th>Komponente</th><th>Dauer</th><th>Ergebnis</th><th>Details</th></tr></thead><tbody>')
            foreach ($p in $script:LoadParts) { $c = $cls[[string]$p.Ergebnis]; if (-not $c) { $c = 'info' }; [void]$sb.Append(('<tr><td>{0}</td><td class="nw">{1}</td><td><span class="badge {2}">{3}</span></td><td>{4}</td></tr>' -f (ConvertTo-HtmlText $p.Komponente), $p.Dauer, $c, (ConvertTo-HtmlText $p.Ergebnis), (ConvertTo-HtmlText $p.Details))) }
            [void]$sb.Append('</tbody></table>')
        }
        [void]$sb.Append((New-LoadChartsHtml))
        if (@($script:LoadSeries | Where-Object { $_.DiskMBs -gt 0 }).Count -gt 1) {
            $svg3 = New-LineSvg ($script:LoadSeries | Where-Object { $null -ne $_.DiskMBs } | ForEach-Object { [pscustomobject]@{ T = $_.T; V = $_.DiskMBs } }) 'MB/s'
            if ($svg3) { [void]$sb.Append('<h3>Datenträger-Durchsatz (MB/s)</h3>' + $svg3) }
        }
        [void]$sb.Append('</section>')
    }
    # ab v2.8: Modul Optimierung, Kennzahlen vorher und nachher und die Einträge je Kategorie
    if (@($script:OptLog).Count) { [void]$sb.Append((New-OptHtml)) }

    $text = $script:Report.ToString()
    $ms = [regex]::Matches($text, '(?m)^={100}\r?\n  (.+?)\r?\n={100}\r?$')
    if ($ms.Count) {
        [void]$sb.Append('<section class="box" data-section="system"><div class="bar"><h2>Details</h2><button onclick="var d=this.closest(''section'').querySelectorAll(''details''),o=!d[0].open;for(var i=0;i<d.length;i++)d[i].open=o">Alle auf- oder zuklappen</button></div>')
        for ($i = 0; $i -lt $ms.Count; $i++) {
            $bs = $ms[$i].Index + $ms[$i].Length
            $be = $(if ($i + 1 -lt $ms.Count) { $ms[$i + 1].Index } else { $text.Length })
            $body = $text.Substring($bs, $be - $bs).Trim("`r", "`n")
            [void]$sb.Append(('<details><summary>{0}</summary><pre>{1}</pre></details>' -f (ConvertTo-HtmlText $ms[$i].Groups[1].Value.Trim()), (ConvertTo-HtmlText $body)))
        }
        [void]$sb.Append('</section>')
    }

    if ($script:Timings.Count) {
        [void]$sb.Append('<section class="box" data-section="system"><h2>Zeitbedarf</h2><table><thead><tr><th>Abschnitt</th><th>Dauer</th></tr></thead><tbody>')
        foreach ($t in $script:Timings) { [void]$sb.Append(('<tr><td>{0}</td><td>{1}</td></tr>' -f (ConvertTo-HtmlText $t.Abschnitt), $t.Dauer)) }
        [void]$sb.Append('</tbody></table></section>')
    }
    [void]$sb.Append((Get-ReportJs))
    [void]$sb.Append(('<footer>Ausgabeordner: {0} &middot; Protokolle und Rohdaten liegen in Anhang.zip. Für eine erweiterte Auswertung die Datei {1} in ein KI-Modell hochladen: Sie enthält Auftrag, Bericht und Rohdaten.{2}</footer></main></body></html>' -f (ConvertTo-HtmlText $OutputDir), (ConvertTo-HtmlText $kiLeaf), $(if ($script:DbSaved) { ' &middot; Datenbankeintrag: ' + (ConvertTo-HtmlText $script:DbSaved) } else { '' })))
    [IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))
}

