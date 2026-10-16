function Get-TelemetryTip {
    param($Sample)
    $t = [int]$Sample.T
    $mm = [int][math]::Floor($t / 60); $ss = [int]($t % 60)
    $lines = @("<div style='font-weight:700;margin-bottom:4px;border-bottom:1px solid var(--line);padding-bottom:2px'>⏱ {0:00}:{1:00} min ({2} s)</div>" -f $mm, $ss, $t)
    $cpuT = $(if ($null -ne $Sample.CpuTemp) { $Sample.CpuTemp } elseif ($null -ne $Sample.Temp) { $Sample.Temp } else { $null })
    if ($null -ne $cpuT) { $lines += ("<div style='color:var(--crit,#ef4444);font-weight:600'>CPU: {0:N1} °C</div>" -f [double]$cpuT) }
    if ($null -ne $Sample.GpuTemp -and [double]$Sample.GpuTemp -gt 0) { $lines += ("<div style='color:#c2410c;font-weight:600'>GPU: {0:N1} °C</div>" -f [double]$Sample.GpuTemp) }
    $cpuMhz = $(if ($null -ne $Sample.CpuMHz -and [double]$Sample.CpuMHz -gt 0) { $Sample.CpuMHz } elseif ($null -ne $Sample.MHz -and [double]$Sample.MHz -gt 0) { $Sample.MHz } else { $null })
    if ($null -ne $cpuMhz) { $lines += ("<div style='color:var(--info,#2563eb);font-weight:600'>CPU-Takt: {0:N2} GHz</div>" -f ([double]$cpuMhz / 1000.0)) }
    if ($null -ne $Sample.GpuMHz -and [double]$Sample.GpuMHz -gt 0) { $lines += ("<div style='color:#ea580c'>GPU-Takt: {0:N0} MHz</div>" -f [double]$Sample.GpuMHz) }
    if ($null -ne $Sample.CpuW -and [double]$Sample.CpuW -gt 0) { $lines += ("<div>CPU-Paket: {0:N1} W</div>" -f [double]$Sample.CpuW) }
    if ($null -ne $Sample.GpuW -and [double]$Sample.GpuW -gt 0) { $lines += ("<div>GPU: {0:N1} W</div>" -f [double]$Sample.GpuW) }
    if ($null -ne $Sample.GpuLoad -and [double]$Sample.GpuLoad -ge 0) { $lines += ("<div>GPU-Auslastung: {0:N0} %</div>" -f [double]$Sample.GpuLoad) }
    if ($null -ne $Sample.Fps -and [double]$Sample.Fps -gt 0) { $lines += ("<div>{0:N1} Bilder/s</div>" -f [double]$Sample.Fps) }
    if ($null -ne $Sample.Fan -and [double]$Sample.Fan -gt 0) { $lines += ("<div>Lüfter: {0:N0} U/min</div>" -f [double]$Sample.Fan) }
    if ($null -ne $Sample.DiskMBs -and [double]$Sample.DiskMBs -gt 0) { $lines += ("<div>Datenträger: {0:N0} MB/s</div>" -f [double]$Sample.DiskMBs) }
    return ($lines -join '')
}

# Lasttest im HTML-Bericht: Drosselnachweis und Kurven für Temperatur, Takt, Leistung und Lüfter.
# Ab v2.7 auch für den Benchmark: eigene Messreihe, Marken am Beginn jedes Abschnitts, ohne Drosselnachweis.
function New-LoadChartsHtml {
    param($Series = $script:LoadSeries, $Throttle = $script:LoadThrottle, $Abort = $script:LoadAbort, $Limits = $script:LoadLimits, $Marken = $null, $GpuLoad = $script:GpuLoad)
    $S = @($Series)
    $sb = New-Object System.Text.StringBuilder
    $tipMap = @{}
    $calcTip = {
        param($Sample)
        $t = [int]$Sample.T
        $mm = [int][math]::Floor($t / 60); $ss = [int]($t % 60)
        $lines = @("<div style='font-weight:700;margin-bottom:4px;border-bottom:1px solid var(--line);padding-bottom:2px'>⏱ {0:00}:{1:00} min ({2} s)</div>" -f $mm, $ss, $t)
        $cpuT = $(if ($null -ne $Sample.CpuTemp) { $Sample.CpuTemp } elseif ($null -ne $Sample.Temp) { $Sample.Temp } else { $null })
        if ($null -ne $cpuT) { $lines += ("<div style='color:var(--crit,#ef4444);font-weight:600'>CPU: {0:N1} °C</div>" -f [double]$cpuT) }
        if ($null -ne $Sample.GpuTemp -and [double]$Sample.GpuTemp -gt 0) { $lines += ("<div style='color:#c2410c;font-weight:600'>GPU: {0:N1} °C</div>" -f [double]$Sample.GpuTemp) }
        $cpuMhz = $(if ($null -ne $Sample.CpuMHz -and [double]$Sample.CpuMHz -gt 0) { $Sample.CpuMHz } elseif ($null -ne $Sample.MHz -and [double]$Sample.MHz -gt 0) { $Sample.MHz } else { $null })
        if ($null -ne $cpuMhz) { $lines += ("<div style='color:var(--info,#2563eb);font-weight:600'>CPU-Takt: {0:N2} GHz</div>" -f ([double]$cpuMhz / 1000.0)) }
        if ($null -ne $Sample.GpuMHz -and [double]$Sample.GpuMHz -gt 0) { $lines += ("<div style='color:#ea580c'>GPU-Takt: {0:N0} MHz</div>" -f [double]$Sample.GpuMHz) }
        if ($null -ne $Sample.CpuW -and [double]$Sample.CpuW -gt 0) { $lines += ("<div>CPU-Paket: {0:N1} W</div>" -f [double]$Sample.CpuW) }
        if ($null -ne $Sample.GpuW -and [double]$Sample.GpuW -gt 0) { $lines += ("<div>GPU: {0:N1} W</div>" -f [double]$Sample.GpuW) }
        if ($null -ne $Sample.GpuLoad -and [double]$Sample.GpuLoad -ge 0) { $lines += ("<div>GPU-Auslastung: {0:N0} %</div>" -f [double]$Sample.GpuLoad) }
        if ($null -ne $Sample.Fps -and [double]$Sample.Fps -gt 0) { $lines += ("<div>{0:N1} Bilder/s</div>" -f [double]$Sample.Fps) }
        if ($null -ne $Sample.Fan -and [double]$Sample.Fan -gt 0) { $lines += ("<div>Lüfter: {0:N0} U/min</div>" -f [double]$Sample.Fan) }
        if ($null -ne $Sample.DiskMBs -and [double]$Sample.DiskMBs -gt 0) { $lines += ("<div>Datenträger: {0:N0} MB/s</div>" -f [double]$Sample.DiskMBs) }
        return ($lines -join '')
    }
    foreach ($row in $S) {
        if ($null -ne $row.T) {
            $tipMap[[int]$row.T] = if (Get-Command Get-TelemetryTip -ErrorAction SilentlyContinue) { Get-TelemetryTip $row } else { & $calcTip $row }
        }
    }
    $pts = { param($prop) @($S | Where-Object { $null -ne $_.$prop -and "$($_.$prop)" -ne '' } | ForEach-Object {
        $tInt = [int]$_.T
        $tTip = $(if ($tipMap.ContainsKey($tInt)) { $tipMap[$tInt] } else { $null })
        [pscustomobject]@{ T = $_.T; V = [double]$_.$prop; Tip = $tTip }
    }) }
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
    if ($cpuSens.Count -ge 2) {
        $ser += @{
            Name = 'CPU'; Cls = 's1';
            Points = @($cpuSens | ForEach-Object {
                $tInt = [int]$_.T
                $tTip = $(if ($tipMap.ContainsKey($tInt)) { $tipMap[$tInt] } else { $null })
                [pscustomobject]@{ T = $_.T; V = [double]$_.CpuTemp; Tip = $tTip }
            })
        }
    }
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
    var table = document.getElementById('befundeTable');
    if (!table) return;
    var rows = table.querySelectorAll('tbody tr');
    var visible = 0;
    for (var i = 0; i < rows.length; i++) {
        var tr = rows[i];
        var lvlCell = tr.querySelector('td[data-level]');
        var lvl = lvlCell ? lvlCell.getAttribute('data-level') : '';
        var matchLvl = (currentLevel === 'all' || lvl === currentLevel);
        if (matchLvl) {
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

    function showTip(html, x, y) {
        tip.innerHTML = html;
        tip.style.opacity = '1';
        var pad = 14;
        var tw = tip.offsetWidth || 180;
        var left = x + pad;
        if (left + tw > window.innerWidth - 10) {
            left = Math.max(10, x - tw - pad);
        }
        tip.style.left = left + 'px';
        tip.style.top = Math.max(10, y - 32) + 'px';
    }

    function hideTip() {
        tip.style.opacity = '0';
    }

    document.addEventListener('mouseover', function(e) {
        var hit = e.target.closest('.hit');
        if (hit && hit.getAttribute('data-tip')) {
            showTip(hit.getAttribute('data-tip'), e.pageX, e.pageY);
        }
    });

    document.addEventListener('mousemove', function(e) {
        var hit = e.target.closest('.hit');
        if (hit && hit.getAttribute('data-tip')) {
            showTip(hit.getAttribute('data-tip'), e.pageX, e.pageY);
            return;
        }
        var svg = e.target.closest('svg.chart.ml');
        if (svg) {
            var hits = svg.querySelectorAll('.hit');
            if (hits.length > 0) {
                var rect = svg.getBoundingClientRect();
                var svgX = (e.clientX - rect.left) / rect.width * 960;
                var bestHit = null;
                var minDiff = 40;
                for (var i = 0; i < hits.length; i++) {
                    var cx = parseFloat(hits[i].getAttribute('cx'));
                    var diff = Math.abs(cx - svgX);
                    if (diff < minDiff) {
                        minDiff = diff;
                        bestHit = hits[i];
                    }
                }
                if (bestHit && bestHit.getAttribute('data-tip')) {
                    showTip(bestHit.getAttribute('data-tip'), e.pageX, e.pageY);
                    return;
                }
            }
        }
        if (tip.style.opacity === '1') {
            hideTip();
        }
    });

    document.addEventListener('mouseout', function(e) {
        var svg = e.target.closest('svg.chart.ml');
        if (svg && (!e.relatedTarget || !e.relatedTarget.closest('svg.chart.ml'))) {
            hideTip();
        }
    });

    var btnTop = document.createElement('button');
    btnTop.className = 'back-to-top';
    btnTop.setAttribute('title', 'Nach oben springen');
    btnTop.setAttribute('aria-label', 'Nach oben springen');
    btnTop.innerHTML = '&#9650;';
    btnTop.onclick = function() {
        window.scrollTo({ top: 0, behavior: 'smooth' });
    };
    document.body.appendChild(btnTop);

    window.addEventListener('scroll', function() {
        if (window.pageYOffset > 300) {
            btnTop.classList.add('visible');
        } else {
            btnTop.classList.remove('visible');
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

function New-PowerEfficiencyHtml($Profile) {
    if (-not $Profile) { return '' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<div class="pwr-box">')
    [void]$sb.Append('<h2>Geschätzter Gesamtsystemverbrauch &amp; Energieeffizienz</h2>')
    $hwTyp = $(if ($Profile.IsNotebook) { 'Notebook-Plattform mit SoC/Display-Modell' } else { 'Desktop-PC mit ATX-Mainboard & 80-PLUS-Netzteil' })
    [void]$sb.Append(('<p class="note">Mathematisch modellierter Gesamtverbrauch (DC intern und AC an der Steckdose) auf Basis der gemessenen Sensorwerte (CPU-Package und GPU-Board) sowie Plattform-Zuschlägen ({0}). Echte Sensormesswerte bleiben unangetastet.</p>' -f $hwTyp))

    # Interaktive Netzteil-Konfigurationsleiste direkt im Bericht (nur Desktop-PCs; Notebooks nutzen OEM-Modell)
    if (-not $Profile.IsNotebook) {
        $curWatt = if ($Profile.PsuWattage -gt 0) { [int]$Profile.PsuWattage } else { 650 }
        $curRate = if ($Profile.PsuRating) { [string]$Profile.PsuRating } else { '80 PLUS Bronze' }
        $rOpts = @('Unbekannt', '80 PLUS White', '80 PLUS Bronze', '80 PLUS Silver', '80 PLUS Gold', '80 PLUS Platinum', '80 PLUS Titanium')
        $rSb = New-Object System.Text.StringBuilder
        foreach ($ro in $rOpts) {
            $sel = if ($ro -eq $curRate) { ' selected' } else { '' }
            [void]$rSb.Append(('<option value="{0}"{1}>{0}</option>' -f $ro, $sel))
        }
        $cfgTpl = @'
<div class="pwr-cfg-bar" style="margin:12px 0 16px;padding:12px 16px;background:var(--code);border:1px solid var(--line);border-radius:10px;display:flex;gap:18px;align-items:center;flex-wrap:wrap;">
  <div style="font-weight:650;font-size:13.5px;color:var(--text);display:flex;align-items:center;gap:6px;">
    <span>⚡</span><span>Netzteil-Konfiguration:</span>
  </div>
  <div style="display:flex;align-items:center;gap:8px;">
    <label for="cfgPsuWatt" style="font-size:13px;color:var(--muted);font-weight:500;">Nennleistung:</label>
    <input type="number" id="cfgPsuWatt" value="{0}" min="200" max="2500" step="50" style="width:85px;padding:5px 8px;border-radius:6px;border:1px solid var(--line);background:var(--panel);color:var(--text);font:inherit;font-size:13px;" oninput="recalcPsuModel()" title="Nennleistung des verbauten Netzteils in Watt (z. B. 550, 650, 750, 850, 1000 W)">
    <span style="font-size:13px;color:var(--muted);">W</span>
  </div>
  <div style="display:flex;align-items:center;gap:8px;">
    <label for="cfgPsuRating" style="font-size:13px;color:var(--muted);font-weight:500;">Effizienzklasse:</label>
    <select id="cfgPsuRating" style="padding:5px 10px;border-radius:6px;border:1px solid var(--line);background:var(--panel);color:var(--text);font:inherit;font-size:13px;" onchange="recalcPsuModel()" title="80 PLUS Zertifizierung (230V EU Effizienzkurve)">
      {1}
    </select>
  </div>
  <div id="cfgPsuHint" style="font-size:12.5px;color:var(--muted);margin-left:auto;">
    230V EU Effizienzmodell aktiv
  </div>
</div>
'@
        [void]$sb.Append(($cfgTpl -f $curWatt, $rSb.ToString()))
    } else {
        [void]$sb.Append('<p class="note" style="margin:10px 0 14px;"><b>Notebook-Plattform:</b> Berechnung nutzt das mobile OEM-Netzteil- und Akkumodell (90 % Effizienz, kein austauschbares ATX-Netzteil).</p>')
    }

    # Kacheln für Leerlauf, Teillast, Gaming, Volllast
    [void]$sb.Append('<div class="pwr-grid">')

    # 1. Leerlauf
    $idle = $Profile.Leerlauf
    $idleAc = $(if ($idle -and $idle.Verfuegbar) { '~{0:N0} W' -f [math]::Round($idle.P_AC) } else { 'n/v' })
    $idleDc = $(if ($idle -and $idle.Verfuegbar) { 'intern DC ~{0:N0} W' -f [math]::Round($idle.P_DC) } else { 'kein Leistungssensor' })
    $idleTip = $(if ($idle -and $idle.Verfuegbar) { $idle.Aufschluesselung } else { 'Keine Messwerte für CPU-Package-Power im Leerlauf vorhanden.' })
    $idleDcNum = $(if ($idle -and $idle.Verfuegbar) { [string]::Format($script:Inv, '{0:0.#}', $idle.P_DC) } else { '0' })
    [void]$sb.Append(('<div class="pwr-card hit" id="pwrCardIdle" data-stage="Idle" data-dc="{0}" data-tip="{1}"><h4>Leerlauf (Idle)</h4><div class="pwr-val" id="pwrValIdle">{2}</div><div class="pwr-sub" id="pwrSubIdle">{3}</div></div>' -f `
        $idleDcNum, (ConvertTo-HtmlText $idleTip), $idleAc, (ConvertTo-HtmlText $idleDc)))

    # 2. Teillast
    $part = $Profile.Teillast
    $partAc = $(if ($part -and $part.Verfuegbar) { '~{0:N0} W' -f [math]::Round($part.P_AC) } else { 'n/v' })
    $partDc = $(if ($part -and $part.Verfuegbar) { 'intern DC ~{0:N0} W' -f [math]::Round($part.P_DC) } else { 'kein Leistungssensor' })
    $partTip = $(if ($part -and $part.Verfuegbar) { $part.Aufschluesselung } else { 'Keine Messwerte für Teillast vorhanden.' })
    $partDcNum = $(if ($part -and $part.Verfuegbar) { [string]::Format($script:Inv, '{0:0.#}', $part.P_DC) } else { '0' })
    [void]$sb.Append(('<div class="pwr-card hit" id="pwrCardPart" data-stage="Teillast" data-dc="{0}" data-tip="{1}"><h4>Teillast (Alltag & Büro)</h4><div class="pwr-val" id="pwrValPart">{2}</div><div class="pwr-sub" id="pwrSubPart">{3}</div></div>' -f `
        $partDcNum, (ConvertTo-HtmlText $partTip), $partAc, (ConvertTo-HtmlText $partDc)))

    # 3. Typisches Gaming
    $game = $Profile.Gaming
    if ($game -and $game.Verfuegbar) {
        $gameAc = '~{0:N0} W' -f [math]::Round($game.P_AC)
        $gameDc = 'intern DC ~{0:N0} W' -f [math]::Round($game.P_DC)
        $gameTip = $game.Aufschluesselung
        $gameDcNum = [string]::Format($script:Inv, '{0:0.#}', $game.P_DC)
        [void]$sb.Append(('<div class="pwr-card hit" id="pwrCardGame" data-stage="Gaming" data-dc="{0}" data-tip="{1}"><h4>Typisches Gaming</h4><div class="pwr-val" id="pwrValGame">{2}</div><div class="pwr-sub" id="pwrSubGame">{3}</div></div>' -f `
            $gameDcNum, (ConvertTo-HtmlText $gameTip), $gameAc, (ConvertTo-HtmlText $gameDc)))
    }

    # 4. Volllast
    $load = $Profile.Volllast
    $loadAc = $(if ($load -and $load.Verfuegbar) { '~{0:N0} W' -f [math]::Round($load.P_AC) } else { 'n/v' })
    $loadDc = $(if ($load -and $load.Verfuegbar) { 'intern DC ~{0:N0} W' -f [math]::Round($load.P_DC) } else { 'kein Leistungssensor' })
    $loadTip = $(if ($load -and $load.Verfuegbar) { $load.Aufschluesselung } else { 'Keine Messwerte unter Volllast vorhanden.' })
    $loadDcNum = $(if ($load -and $load.Verfuegbar) { [string]::Format($script:Inv, '{0:0.#}', $load.P_DC) } else { '0' })
    [void]$sb.Append(('<div class="pwr-card hit" id="pwrCardLoad" data-stage="Load" data-dc="{0}" data-tip="{1}"><h4>Volllast (Lasttest / Peak)</h4><div class="pwr-val" id="pwrValLoad">{2}</div><div class="pwr-sub" id="pwrSubLoad">{3}</div></div>' -f `
        $loadDcNum, (ConvertTo-HtmlText $loadTip), $loadAc, (ConvertTo-HtmlText $loadDc)))

    [void]$sb.Append('</div>')
    if ($load -and $load.AufschluesselungKurz) {
        $warnDisplay = $(if ($load.LoadPercent -gt 85) { 'display:block;' } else { 'display:none;' })
        $warnLoad = $(if ($load.LoadPercent) { [math]::Round($load.LoadPercent) } else { 0 })
        [void]$sb.Append(('<p class="note" style="margin:10px 0 14px;"><b>Volllast-Aufschlüsselung:</b> <span id="pwrLoadBreakdown">{0}</span></p>' -f (ConvertTo-HtmlText $load.AufschluesselungKurz)))
        [void]$sb.Append(('<div id="pwrLoadWarn" style="{0}margin:-6px 0 14px;padding:8px 12px;border-radius:8px;background:var(--warn-bg);border:1px solid var(--warn);color:var(--warn);font-size:13px;font-weight:600;">⚠️ Netzteil unter Volllast zu {1} % ausgelastet. Wenig Puffer für Lastspitzen.</div>' -f $warnDisplay, $warnLoad))
    }

    # Effizienz-Indizes
    $eff = $Profile.Effizienz
    $effParts = @()
    if ($eff) {
        if ($null -ne $eff.CpuMT_PerWatt) {
            $effParts += ('<b>CPU-Effizienz:</b> {0:N1} Punkte/W <small class="muted">(Mehrkern-Score je Watt CPU-Paket)</small>' -f $eff.CpuMT_PerWatt)
        }
        if ($null -ne $eff.Gpu_PerWatt) {
            $effParts += ('<b>GPU-Effizienz:</b> {0:N2} FPS/W <small class="muted">(Renderleistung je Watt Grafik)</small>' -f $eff.Gpu_PerWatt)
        }
        if ($null -ne $eff.System_PerWatt) {
            $effParts += ('<b>Gesamtsystem-Effizienz:</b> {0:N1} Punkte/100 W <small class="muted">(Gesamtscore je 100 W an der Steckdose)</small>' -f $eff.System_PerWatt)
        }
    }
    if ($effParts.Count) {
        [void]$sb.Append('<div style="margin:10px 0 16px;padding:10px 14px;background:var(--code);border-radius:8px;border:1px solid var(--line);display:flex;gap:18px;flex-wrap:wrap;font-size:13.5px;">')
        foreach ($ep in $effParts) { [void]$sb.Append(('<div>{0}</div>' -f $ep)) }
        [void]$sb.Append('</div>')
    }

    # Stromkosten-Kalkulator
    $pTeilNum = $(if ($part -and $part.Verfuegbar -and $part.P_AC -gt 0) { [math]::Round($part.P_AC) } else { 0 })
    $pVollNum = $(if ($load -and $load.Verfuegbar -and $load.P_AC -gt 0) { [math]::Round($load.P_AC) } else { 0 })
    if ($pTeilNum -gt 0 -or $pVollNum -gt 0) {
        $initKwh = [math]::Round((4 * $pTeilNum + 2 * $pVollNum) * 365 / 1000.0, 1)
        $initCost = [math]::Round($initKwh * 0.35, 2)
        [void]$sb.Append('<details open style="margin-top:14px;border:1px solid var(--line);border-radius:10px;padding:10px 16px;"><summary style="font-weight:650;color:var(--accent);cursor:pointer;">Jährliche Stromkosten-Schätzung (Verbrauchskalkulator)</summary>')
        $calcTpl = @'
<div class="calc-grid">
<input type="hidden" id="calcPTeil" value="{0}">
<input type="hidden" id="calcPVoll" value="{1}">
<div class="calc-field"><label for="calcHTeil">Alltagsbetrieb / Büro (h/Tag):</label><input type="number" id="calcHTeil" value="4" min="0" max="24" step="0.5" oninput="recalcPowerCost()"></div>
<div class="calc-field"><label for="calcHVoll">Volllast / Gaming (h/Tag):</label><input type="number" id="calcHVoll" value="2" min="0" max="24" step="0.5" oninput="recalcPowerCost()"></div>
<div class="calc-field"><label for="calcPrice">Strompreis (Cent/kWh):</label><input type="number" id="calcPrice" value="35" min="1" max="150" step="1" oninput="recalcPowerCost()"></div>
<div class="calc-res"><span>Jahresverbrauch</span><b id="calcOutKwh">{2:N0} kWh</b></div>
<div class="calc-res"><span>Geschätzte Kosten</span><b id="calcOutCost">{3:N2} €</b></div>
</div><p class="note" id="calcCostNote" style="margin-top:8px;">Berechnung basiert auf angenommenen 365 Tagen/Jahr mit den modellierten AC-Leistungswerten (~{0} W Teillast, ~{1} W Volllast).</p>
'@
        [void]$sb.Append(($calcTpl -f $pTeilNum, $pVollNum, $initKwh, $initCost))
        [void]$sb.Append(@'
<script>
var psuCurves = {
  "Unbekannt":         [78.0, 82.0, 86.0, 88.0, 85.0],
  "80 PLUS White":    [76.0, 80.0, 84.0, 86.0, 83.0],
  "80 PLUS Bronze":   [79.0, 83.0, 86.5, 88.5, 85.5],
  "80 PLUS Silver":   [81.0, 85.0, 88.5, 90.5, 88.0],
  "80 PLUS Gold":     [83.5, 87.5, 90.5, 92.5, 90.0],
  "80 PLUS Platinum": [85.5, 89.5, 92.5, 94.0, 91.5],
  "80 PLUS Titanium": [88.0, 91.5, 94.5, 96.0, 93.5]
};
var loadSteps = [5, 10, 20, 50, 100];

function calcPsuEta(pDc, pWatt, rating, stage) {
  var curve = psuCurves[rating] || psuCurves["80 PLUS Bronze"];
  if (!pWatt || pWatt <= 0) {
    var eff = 86.0;
    if (stage === 'Idle') eff = curve[1];
    else if (stage === 'Teillast') eff = curve[2];
    else eff = curve[3];
    return { eta: eff / 100.0, etaPct: eff, loadPct: null };
  }
  var loadPct = (pDc / pWatt) * 100.0;
  var eff = 80.0;
  if (loadPct <= 5.0) {
    eff = Math.max(70.0, curve[0] - (5.0 - loadPct) * 1.5);
  } else if (loadPct >= 100.0) {
    eff = Math.max(70.0, curve[4] - (loadPct - 100.0) * 0.1);
  } else {
    for (var i = 0; i < loadSteps.length - 1; i++) {
      if (loadPct >= loadSteps[i] && loadPct <= loadSteps[i + 1]) {
        var x0 = loadSteps[i], x1 = loadSteps[i + 1];
        var y0 = curve[i], y1 = curve[i + 1];
        eff = y0 + ((loadPct - x0) / (x1 - x0)) * (y1 - y0);
        break;
      }
    }
  }
  return { eta: eff / 100.0, etaPct: Math.round(eff * 10) / 10, loadPct: Math.round(loadPct * 10) / 10 };
}

function recalcPsuModel() {
  var eW = document.getElementById('cfgPsuWatt'), eR = document.getElementById('cfgPsuRating');
  if (!eW || !eR) return;
  var pWatt = parseInt(eW.value, 10) || 0;
  var rating = eR.value;

  try {
    localStorage.setItem('minibench_psu_watt', pWatt);
    localStorage.setItem('minibench_psu_rating', rating);
  } catch(e) {}

  var cards = [
    { id: 'pwrCardIdle', vId: 'pwrValIdle', sId: 'pwrSubIdle', stage: 'Idle' },
    { id: 'pwrCardPart', vId: 'pwrValPart', sId: 'pwrSubPart', stage: 'Teillast' },
    { id: 'pwrCardGame', vId: 'pwrValGame', sId: 'pwrSubGame', stage: 'Gaming' },
    { id: 'pwrCardLoad', vId: 'pwrValLoad', sId: 'pwrSubLoad', stage: 'Load' }
  ];

  var newAcPart = 0, newAcLoad = 0;

  cards.forEach(function(c) {
    var el = document.getElementById(c.id);
    if (!el) return;
    var pDc = parseFloat(el.getAttribute('data-dc'));
    if (isNaN(pDc) || pDc <= 0) return;
    var res = calcPsuEta(pDc, pWatt, rating, c.stage);
    var pAc = Math.round(pDc / res.eta);
    var vEl = document.getElementById(c.vId);
    var sEl = document.getElementById(c.sId);
    if (vEl) vEl.textContent = '~' + pAc + ' W';
    if (sEl) {
      if (res.loadPct !== null) {
        sEl.textContent = 'intern DC ~' + Math.round(pDc) + ' W (PSU-Last ~' + Math.round(res.loadPct) + ' % @ ~' + res.etaPct.toLocaleString('de-DE') + ' % Effizienz)';
      } else {
        sEl.textContent = 'intern DC ~' + Math.round(pDc) + ' W (~' + res.etaPct.toLocaleString('de-DE') + ' % Effizienz)';
      }
    }
    if (c.stage === 'Teillast') newAcPart = pAc;
    if (c.stage === 'Load') {
      newAcLoad = pAc;
      var bdEl = document.getElementById('pwrLoadBreakdown');
      if (bdEl) {
        if (pWatt > 0 && res.loadPct !== null) {
          bdEl.textContent = '~' + pAc + ' W an der Steckdose (intern ~' + Math.round(pDc) + ' W | PSU-Last ~' + Math.round(res.loadPct) + ' % @ ~' + res.etaPct.toLocaleString('de-DE') + ' % Effizienz [' + pWatt + ' W, ' + rating + '])';
        } else {
          bdEl.textContent = '~' + pAc + ' W an der Steckdose (intern ~' + Math.round(pDc) + ' W | ~' + res.etaPct.toLocaleString('de-DE') + ' % Effizienz [' + rating + '])';
        }
      }
      var wEl = document.getElementById('pwrLoadWarn');
      if (wEl) {
        if (pWatt > 0 && res.loadPct > 85) {
          wEl.style.display = 'block';
          wEl.textContent = '⚠️ Netzteil unter Volllast zu ' + Math.round(res.loadPct) + ' % ausgelastet (~' + Math.round(pDc) + ' W von ' + pWatt + ' W Nennleistung). Wenig Puffer für Lastspitzen.';
        } else {
          wEl.style.display = 'none';
        }
      }
    }
  });

  var elPT = document.getElementById('calcPTeil'), elPV = document.getElementById('calcPVoll');
  if (elPT && newAcPart > 0) elPT.value = newAcPart;
  if (elPV && newAcLoad > 0) elPV.value = newAcLoad;
  var noteEl = document.getElementById('calcCostNote');
  if (noteEl && newAcPart > 0 && newAcLoad > 0) {
    noteEl.textContent = 'Berechnung basiert auf angenommenen 365 Tagen/Jahr mit den modellierten AC-Leistungswerten (~' + newAcPart + ' W Teillast, ~' + newAcLoad + ' W Volllast).';
  }
  if (typeof recalcPowerCost === 'function') recalcPowerCost();
}

function recalcPowerCost(){
  var eHT=document.getElementById('calcHTeil'),eHV=document.getElementById('calcHVoll'),eP=document.getElementById('calcPrice'),ePT=document.getElementById('calcPTeil'),ePV=document.getElementById('calcPVoll');
  if(!eHT||!eHV||!eP||!ePT||!ePV)return;
  var hT=parseFloat(eHT.value)||0,hV=parseFloat(eHV.value)||0,pr=parseFloat(eP.value)||0,pT=parseFloat(ePT.value)||0,pV=parseFloat(ePV.value)||0;
  var kwhD=(hT*pT+hV*pV)/1000,kwhY=kwhD*365,cst=kwhY*(pr/100);
  var oK=document.getElementById('calcOutKwh'),oC=document.getElementById('calcOutCost');
  if(oK)oK.textContent=Math.round(kwhY)+' kWh';
  if(oC)oC.textContent=cst.toLocaleString('de-DE',{minimumFractionDigits:2,maximumFractionDigits:2})+' €';
}

(function initPsuFromStorage() {
  try {
    var eW = document.getElementById('cfgPsuWatt');
    var eR = document.getElementById('cfgPsuRating');
    if (!eW || !eR) return;
    var sW = localStorage.getItem('minibench_psu_watt');
    var sR = localStorage.getItem('minibench_psu_rating');
    if (sW && eW) eW.value = sW;
    if (sR && eR) eR.value = sR;
    if (sW || sR) recalcPsuModel();
  } catch(e) {}
})();
</script></details>
'@)
    }

    [void]$sb.Append('</div>')
    return $sb.ToString()
}

function New-BootPerformanceHtml {
    param($BootPerf)
    if (-not $BootPerf) { return '' }
    $sb = New-Object System.Text.StringBuilder
    $biosSec = if ($BootPerf.BiosSekunden -and [double]$BootPerf.BiosSekunden -gt 0) { [double]$BootPerf.BiosSekunden } else { 0.0 }
    $kernSec = if ($BootPerf.KernelSekunden) { [double]$BootPerf.KernelSekunden } else { 0.0 }
    $postSec = if ($BootPerf.DesktopSekunden) { [double]$BootPerf.DesktopSekunden } else { 0.0 }
    $totSec  = $biosSec + $kernSec + $postSec
    if ($totSec -le 0) { $totSec = if ($BootPerf.SystemGesamtSekunden) { [double]$BootPerf.SystemGesamtSekunden } else { 1.0 } }
    $secText = if ($BootPerf.Verfuegbar) { 'Desktop einsatzbereit nach: {0:N1} s &middot; Vollständiger Leerlauf nach: {1:N1} s' -f $kernSec, $totSec } else { '' }
    [void]$sb.Append('<details class="box grp" data-section="system" open><summary style="cursor:pointer;font-size:1.15em;font-weight:600;"><span class="gname">System-Startzeit</span>' + $(if ($secText) { '<span class="gsub">' + $secText + '</span>' } else { '' }) + '</summary>')
    if (-not $BootPerf.Verfuegbar) {
        $msg = if ($BootPerf.StatusText) { $BootPerf.StatusText } else { 'Nicht verfügbar (Diagnostics-Performance-Protokoll deaktiviert)' }
        [void]$sb.Append(('<p class="empty" style="margin:12px 0;">{0}</p>' -f (ConvertTo-HtmlText $msg)))
        [void]$sb.Append('</details>')
        return $sb.ToString()
    }

    $pBios = if ($totSec -gt 0) { [math]::Round(($biosSec / $totSec) * 100.0, 1) } else { 0.0 }
    $pKern = if ($totSec -gt 0) { [math]::Round(($kernSec / $totSec) * 100.0, 1) } else { 0.0 }
    $pPost = [math]::Max(0.0, [math]::Round(100.0 - $pBios - $pKern, 1))

    $biosNote = $(if ($biosSec -gt 0) { ' (davon BIOS/POST: {0:N1} s, Windows: {1:N1} s)' -f $biosSec, $BootPerf.OsBootSekunden } else { '' })
    [void]$sb.Append(('<p class="note" style="margin:10px 0;"><b>Desktop einsatzbereit nach: {0:N1} s &middot; Vollständiger Leerlauf nach: {1:N1} s</b>{2}</p>' -f $kernSec, $totSec, $biosNote))
    [void]$sb.Append(('<div style="margin:8px 0 14px;padding:10px 14px;background:var(--code);border-radius:8px;border:1px solid var(--line);font-size:13px;line-height:1.45;">' + `
        '<b>Aufschlüsselung der Startphasen (Ereignis-ID 100 aus dem Windows-Diagnoseprotokoll):</b><br>' + `
        '1. <b>Desktop sichtbar (Kernel &amp; Treiber):</b> <code>MainPathBootTime</code> ({0:N1} s) &ndash; Dauer vom Bootloader bis zum Erscheinen des Desktops bzw. Anmeldebildschirms (gefühlte Startzeit).<br>' + `
        '2. <b>Hintergrund-Initialisierung (Autostart bis Leerlauf):</b> <code>BootPostBootTime</code> ({1:N1} s) &ndash; Zeitspanne nach Erscheinen des Desktops, bis alle Autostart-Programme und Hintergrunddienste geladen sind und die CPU-Aktivität für mindestens 10 Sekunden unter 80 % sinkt.' + `
        '</div>' -f $kernSec, $postSec))
    [void]$sb.Append('<div class="boot-bar-container"><div class="boot-bar">')
    if ($biosSec -gt 0) {
        [void]$sb.Append(('<div class="boot-seg boot-bios" style="width:{0}%" title="BIOS / Firmware: {1:N1} s ({0} %)">BIOS {1:N1} s</div>' -f $pBios, $biosSec))
    }
    [void]$sb.Append(('<div class="boot-seg boot-kernel" style="width:{0}%" title="Kernel &amp; Treiber: {1:N1} s ({0} %)">Kernel {1:N1} s</div>' -f $pKern, $kernSec))
    [void]$sb.Append(('<div class="boot-seg boot-post" style="width:{0}%" title="Desktop &amp; Autostart: {1:N1} s ({0} %)">Desktop {1:N1} s</div>' -f $pPost, $postSec))
    [void]$sb.Append('</div></div>')

    [void]$sb.Append('<div class="boot-legend">')
    if ($biosSec -gt 0) {
        [void]$sb.Append(('<div class="boot-leg-item"><i class="boot-dot boot-bios"></i><b>BIOS / Firmware:</b> {0:N1} s</div>' -f $biosSec))
    }
    [void]$sb.Append(('<div class="boot-leg-item"><i class="boot-dot boot-kernel"></i><b>Kernel &amp; Treiber:</b> {0:N1} s</div>' -f $kernSec))
    [void]$sb.Append(('<div class="boot-leg-item"><i class="boot-dot boot-post"></i><b>Desktop &amp; Autostart:</b> {0:N1} s</div>' -f $postSec))
    [void]$sb.Append(('<div class="boot-leg-item"><i class="boot-dot" style="background:var(--text)"></i><b>Betriebssystem gesamt:</b> {0:N1} s</div>' -f $BootPerf.OsBootSekunden))
    [void]$sb.Append('</div>')

    if (@($BootPerf.Verzoegerer).Count -gt 0) {
        [void]$sb.Append('<h3 style="margin-top:16px">Autostart-Verzögerer (&ge; 1,0 s)</h3>')
        [void]$sb.Append('<div class="tw"><table><thead><tr><th>Anwendung / Komponente</th><th class="r">Verzögerung</th><th>Art / Ereignis</th></tr></thead><tbody>')
        foreach ($v in @($BootPerf.Verzoegerer)) {
            [void]$sb.Append(('<tr><td><code>{0}</code></td><td class="num r"><b>{1:N1} s</b></td><td>{2}</td></tr>' -f (ConvertTo-HtmlText $v.Name), $v.DauerSekunden, (ConvertTo-HtmlText $v.Typ)))
        }
        [void]$sb.Append('</tbody></table></div>')
    }
    [void]$sb.Append('</details>')
    return $sb.ToString()
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
    [void]$sb.Append(('<nav class="report-nav"><button type="button" class="tab-btn active" onclick="switchSection(''all'', this)">Alle Abschnitte</button><button type="button" class="tab-btn" onclick="switchSection(''system'', this)">Systemübersicht</button><button type="button" class="tab-btn" onclick="switchSection(''benchmark'', this)">Benchmark</button><button type="button" class="tab-btn" onclick="switchSection(''befunde'', this)">Befunde</button><button type="button" class="tab-btn" onclick="switchSection(''hardware'', this)">Hardware</button><button type="button" class="tab-btn" onclick="switchSection(''sensoren'', this)">Sensoren</button><a href="../Dashboard.html?system={0}" class="tab-btn btn-dash" target="_blank" title="Vergleichsdashboard für diesen PC im neuen Tab öffnen">Vergleichsdashboard</a></nav>' -f $compParam))
    $stCard = ''
    if ($script:Stability) { $stCard = ('<div class="card st {0}"><b>{1}</b><span>Zuverlässigkeit von 10 ({2})</span></div>' -f $script:Stability.Klasse, ('{0:N1}' -f $script:Stability.Index), (ConvertTo-HtmlText $script:Stability.Stufe)) }
    $benchCard = ''
    $overall = Get-BenchOverall
    if ($null -ne $overall -and [double]$overall -gt 0) {
        $benchCard = ('<div class="card bench"><b>{0} %</b><span>Gesamtleistung (Referenz)</span></div>' -f [math]::Round([double]$overall))
    }
    $pProfile = if (Get-Command Get-SystemPowerProfile -ErrorAction SilentlyContinue) { Get-SystemPowerProfile } else { $null }

    # Befunde-Kachel (Zusammenfassung von kritisch, Warnungen, Hinweise)
    $totBefunde = $NK + $NW + $NI
    $befCls = $(if ($NK -gt 0) { 'crit' } elseif ($NW -gt 0) { 'warn' } elseif ($NI -gt 0) { 'info' } else { 'ok' })
    $befSub = $(if ($totBefunde -eq 0) { 'Keine Auffälligkeiten' } else { '{0} kritisch &middot; {1} Warn. &middot; {2} Hinw.' -f $NK, $NW, $NI })
    $befTip = $(if ($totBefunde -eq 0) { 'Keine Auffälligkeiten gefunden' } else { '{0} kritische Befunde, {1} Warnungen, {2} Hinweise' -f $NK, $NW, $NI })
    $befCard = ('<div class="card {0} hit" data-tip="{1}"><b>{2}</b><span>Befunde ({3})</span></div>' -f `
        $befCls, (ConvertTo-HtmlText $befTip), $totBefunde, $befSub)

    # Multicore-Score
    $mtCard = ''
    $mtVal = $null
    if ($script:BenchResults) {
        $r = @($script:BenchResults | Where-Object { $_.RefKey -eq 'CPU|MT' -and [double]$_.Wert -gt 0 }) | Select-Object -First 1
        if ($r) { $mtVal = [double]$r.Wert }
    }
    if ($null -eq $mtVal -and $script:BenchNew) {
        $r = @($script:BenchNew | Where-Object { ($_.Key -eq 'CPU|MT' -or $_.RefKey -eq 'CPU|MT') -and [double]$_.Wert -gt 0 }) | Select-Object -First 1
        if ($r) { $mtVal = [double]$r.Wert }
    }
    if ($null -ne $mtVal) {
        $mtCard = ('<div class="card metric cpu"><b>{0:N0}</b><span>Multicore-Score (CPU)</span></div>' -f $mtVal)
    }

    # Grafik / FPS (Renderleistung)
    $fpsCard = ''
    $fpsVal = $null
    if ($script:BenchResults) {
        $r = @($script:BenchResults | Where-Object { $_.RefKey -in 'GPU|REND', 'GPU|REND1' -and [double]$_.Wert -gt 0 }) | Select-Object -First 1
        if ($r) { $fpsVal = [double]$r.Wert }
    }
    if ($null -eq $fpsVal -and $script:GpuRender) {
        $r = @($script:GpuRender | Where-Object { [double]$_.Fps -gt 0 }) | Select-Object -First 1
        if ($r) { $fpsVal = [double]$r.Fps }
    }
    if ($null -eq $fpsVal -and $script:LoadSummary -and "$script:LoadSummary" -match '(\d+(?:[.,]\d+)?)\s*Bilder/s') {
        $fpsVal = [double]($matches[1] -replace ',', '.')
    }
    if ($null -ne $fpsVal) {
        $fpsCard = ('<div class="card metric gpu"><b>{0:N0} FPS</b><span>Grafik (Rendertest)</span></div>' -f $fpsVal)
    }

    # Schnellster Lesewert einer SSD in GB/s
    $ssdCard = ''
    $maxSsdSr = $null
    if ($script:BenchDisks) {
        $srList = @($script:BenchDisks | ForEach-Object { [double]$_.SR } | Where-Object { $_ -gt 0 })
        if ($srList.Count) { $maxSsdSr = ($srList | Measure-Object -Maximum).Maximum }
    }
    if ($null -ne $maxSsdSr -and $maxSsdSr -gt 0) {
        $ssdGb = [math]::Round($maxSsdSr / 1000.0, 1)
        $ssdCard = ('<div class="card metric disk"><b>{0:N1} GB/s</b><span>Schnellste SSD (Lesen)</span></div>' -f $ssdGb)
    }

    # Effizienz-Wert prominent statt Verbrauch Last
    $effCard = ''
    if ($pProfile) {
        if ($pProfile.Effizienz -and $pProfile.Effizienz.System_PerWatt -and [double]$pProfile.Effizienz.System_PerWatt -gt 0) {
            $subTxt = $(if ($pProfile.Volllast -and $pProfile.Volllast.Verfuegbar) { '~{0:N0} W Volllast' -f $pProfile.Volllast.P_AC } else { 'Gesamteffizienz' })
            $effCard = ('<div class="card eff hit" data-tip="{0}"><b>{1:N1} <small>Pkt/100W</small></b><span>Effizienz ({2})</span></div>' -f `
                (ConvertTo-HtmlText $pProfile.Volllast.Aufschluesselung), [double]$pProfile.Effizienz.System_PerWatt, (ConvertTo-HtmlText $subTxt))
        } elseif ($pProfile.Effizienz -and $pProfile.Effizienz.CpuMT_PerWatt -and [double]$pProfile.Effizienz.CpuMT_PerWatt -gt 0) {
            $subTxt = $(if ($pProfile.Volllast -and $pProfile.Volllast.Verfuegbar) { '~{0:N0} W Volllast' -f $pProfile.Volllast.P_AC } else { 'CPU-Effizienz' })
            $effCard = ('<div class="card eff hit" data-tip="{0}"><b>{1:N0} <small>Pkt/W</small></b><span>CPU-Effizienz ({2})</span></div>' -f `
                (ConvertTo-HtmlText $pProfile.Volllast.Aufschluesselung), [double]$pProfile.Effizienz.CpuMT_PerWatt, (ConvertTo-HtmlText $subTxt))
        } elseif ($pProfile.Volllast -and $pProfile.Volllast.Verfuegbar) {
            $subTxt = $(if ($pProfile.Leerlauf -and $pProfile.Leerlauf.Verfuegbar) { '~{0:N0} W Leerlauf' -f $pProfile.Leerlauf.P_AC } else { 'Volllast geschätzt' })
            $effCard = ('<div class="card pwr hit" data-tip="{0}"><b>~{1:N0} W</b><span>Verbrauch Last ({2})</span></div>' -f `
                (ConvertTo-HtmlText $pProfile.Volllast.Aufschluesselung), [math]::Round($pProfile.Volllast.P_AC), (ConvertTo-HtmlText $subTxt))
        }
    }
    [void]$sb.Append(('<section class="cards" data-section="system">{0}{1}{2}{3}{4}{5}{6}</section>' -f $befCard, $benchCard, $mtCard, $fpsCard, $ssdCard, $effCard, $stCard))
    if ($script:Stability -and $script:Stability.Erklaerung) { [void]$sb.Append(('<section class="box stab {0}" data-section="system"><h2>Zuverlässigkeit {1:N1} von 10</h2><p>{2}</p></section>' -f $script:Stability.Klasse, $script:Stability.Index, (ConvertTo-HtmlText $script:Stability.Erklaerung))) }

    if ($script:Facts.Count) {
        [void]$sb.Append('<section class="box" data-section="hardware"><h2>System</h2><dl>')
        foreach ($k in $script:Facts.Keys) {
            if ($k -like 'Geschätzter Gesamtsystemverbrauch*') { continue }
            [void]$sb.Append(('<dt>{0}</dt><dd>{1}</dd>' -f (ConvertTo-HtmlText $k), ((ConvertTo-HtmlText ([string]$script:Facts[$k])) -replace "`r?`n", '<br>')))
        }
        [void]$sb.Append('</dl></section>')
    }

    if (@($script:BatteryInfo).Count) { [void]$sb.Append((New-BatteryHtml)) }

    [void]$sb.Append('<section class="box" data-section="befunde"><h2>Befunde</h2>')
    if ($Sorted.Count) {
        [void]$sb.Append('<div class="filter-bar"><div class="filter-chips"><button type="button" class="fchip active" data-level="all" onclick="setLevelFilter(''all'', this)">Alle (<span id="cntAll">0</span>)</button><button type="button" class="fchip chip-crit" data-level="KRITISCH" onclick="setLevelFilter(''KRITISCH'', this)">Kritisch (<span id="cntCrit">0</span>)</button><button type="button" class="fchip chip-warn" data-level="WARNUNG" onclick="setLevelFilter(''WARNUNG'', this)">Warnung (<span id="cntWarn">0</span>)</button><button type="button" class="fchip chip-info" data-level="INFO" onclick="setLevelFilter(''INFO'', this)">Hinweis (<span id="cntInfo">0</span>)</button></div><span id="befundCount" class="filter-count"></span></div>')
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
        [void]$sb.Append(('<p class="note">Index 100 in den Tabellen entspricht dem typischen Wert der Hardwareklasse.{0} Vergleich bezieht sich auf frühere Läufe auf diesem PC, grün besser, orange mindestens 10 % schlechter. Für den Systemvergleich das Dashboard nutzen.</p>' -f $refNote))
        if (Get-Command 'New-ProfileCards' -ErrorAction SilentlyContinue) {
            $pCards = New-ProfileCards
            if ($pCards) { [void]$sb.Append($pCards) }
        }
        if (Get-Command 'New-BenchOverview' -ErrorAction SilentlyContinue) {
            $bOv = New-BenchOverview
            if ($bOv) { [void]$sb.Append($bOv) }
        }
        foreach ($gk in $script:BenchGroupOrder) {
            $g = Get-BenchGroup $gk
            if (-not $g.Anzahl) { continue }
            $gc = $bcls[$g.Status]; if (-not $gc) { $gc = 'info' }
            $open = $(if ((Get-StatusRank $g.Status) -ge 2) { ' open' } else { '' })
            [void]$sb.Append(('<details class="grp" id="bg-{4}"{0}><summary><span class="gname">{1}</span><span class="badge {2}">{3}</span></summary>' -f $open,
                (ConvertTo-HtmlText $g.Name), $gc, (ConvertTo-HtmlText $g.Status), $gk))
            $compName = $(if ($script:BenchHead.ContainsKey($gk) -and $script:BenchHead[$gk]) { [string]$script:BenchHead[$gk] } elseif ($g.Kopf) { $g.Kopf } else { $g.Name })
            $word = if ($null -ne $g.RefPct -and [double]$g.RefPct -gt 0) { Get-BenchRatingWord $g.RefPct } else { '' }
            $scorePart = if ($null -ne $g.RefPct -and [double]$g.RefPct -gt 0) { ('<b>{0} %</b> &middot; <span class="pword">{1}</span>' -f $g.RefPct, (ConvertTo-HtmlText $word)) } else { '' }
            $bar = if ($null -ne $g.RefPct -and [double]$g.RefPct -gt 0) { ('<div class="gh-bar">{0}</div>' -f (Get-RefBar $g.RefPct $gc)) } else { '' }
            [void]$sb.Append(('<div class="grp-head"><div><div class="comp-title">{0}</div>{1}</div><div class="comp-score">{2}</div></div>' -f
                (ConvertTo-HtmlText $compName), $bar, $scorePart))
            if ($gk -eq 'Laufwerke') {
                [void]$sb.Append('<div class="tw"><table class="disks"><thead><tr><th>Laufwerk</th><th>Klasse</th><th class="r">Lesen<br><small>MB/s</small></th><th class="r">Schreiben<br><small>MB/s</small></th><th class="r">4K QD1<br><small>IOPS</small></th><th class="r">4K 8 Thr.<br><small>IOPS</small></th><th class="r">4K schr.<br><small>IOPS</small></th><th>Index</th><th>Ergebnis</th></tr></thead><tbody>')
                foreach ($d in $g.Disks) {
                    $c = $bcls[$d.Status]; if (-not $c) { $c = 'info' }
                    $n = { param($v) if ([double]$v -gt 0) { '{0:N0}' -f [double]$v } else { '' } }
                    [void]$sb.Append(('<tr title="{0}"><td>{1}</td><td class="muted">{2}</td><td class="num r">{3}</td><td class="num r">{4}</td><td class="num r">{5}</td><td class="num r">{6}</td><td class="num r">{7}</td><td class="idx">{8}</td><td><span class="badge {9}">{10}</span></td></tr>' -f
                        (ConvertTo-HtmlText (($d.Hinweis, $d.Vergleich | Where-Object { $_ }) -join '; ')), (ConvertTo-HtmlText $d.Laufwerk), (ConvertTo-HtmlText $d.Klasse),
                        (& $n $d.SR), (& $n $d.SW), (& $n $d.R1), (& $n $d.R8), (& $n $d.W1), (& $idxHtml $d.Index $d.Status -Small), $c, (ConvertTo-HtmlText $d.Status)))
                }
                [void]$sb.Append('</tbody></table></div><p class="note tight">Lesen und Schreiben sequentiell mit 1 MiB-Blöcken, 4K-Werte in Zugriffen pro Sekunde, jeweils ohne Windows-Cache. Details beim Überfahren einer Zeile.</p>')
            } else {
                [void]$sb.Append('<div class="tw"><table><thead><tr><th>Messung</th><th class="r">Wert</th><th>Index</th><th>Vergleich</th><th>Ergebnis</th></tr></thead><tbody>')
                foreach ($b in $g.Items) {
                    $c = $bcls[[string]$b.Status]; if (-not $c) { $c = 'info' }
                    [void]$sb.Append(('<tr><td>{0}{1}</td><td class="num r">{2}</td><td class="idx">{3}</td><td class="nw">{4}</td><td><span class="badge {5}">{6}</span></td></tr>' -f
                        (ConvertTo-HtmlText $b.Messung), $(if ($b.Hinweis) { '<small class="hint">' + (ConvertTo-HtmlText $b.Hinweis) + '</small>' } else { '' }), (ConvertTo-HtmlText $b.Anzeige),
                        (& $idxHtml $b.Index $b.Status), (Get-DeltaHtml $b.Vergleich), $c, (ConvertTo-HtmlText $b.Status)))
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
    # ab v3.71: Geschätzter Gesamtsystemverbrauch & Energieeffizienz direkt vor den Sensoren
    if ($pProfile -and ($pProfile.Leerlauf.Verfuegbar -or $pProfile.Volllast.Verfuegbar)) {
        [void]$sb.Append('<section class="box" data-section="sensoren">')
        [void]$sb.Append((New-PowerEfficiencyHtml -Profile $pProfile))
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

    # ab v3.7: System-Startzeit (Boot Performance Breakdown)
    if ($script:BootPerformance) { [void]$sb.Append((New-BootPerformanceHtml $script:BootPerformance)) }

    $text = $script:Report.ToString()
    $ms = [regex]::Matches($text, '(?m)^={100}\r?\n  (.+?)\r?\n={100}\r?$')
    if ($ms.Count) {
        [void]$sb.Append('<details class="box grp" data-section="system"><summary style="cursor:pointer;font-size:1.15em;font-weight:600;"><span class="gname">Details</span></summary><div style="margin-top:12px"><div class="bar"><h2>Rohdaten-Abschnitte</h2><button onclick="var d=this.closest(''details'').querySelectorAll(''details''),o=!d[0].open;for(var i=0;i<d.length;i++)d[i].open=o">Alle auf- oder zuklappen</button></div>')
        for ($i = 0; $i -lt $ms.Count; $i++) {
            $bs = $ms[$i].Index + $ms[$i].Length
            $be = $(if ($i + 1 -lt $ms.Count) { $ms[$i + 1].Index } else { $text.Length })
            $body = $text.Substring($bs, $be - $bs).Trim("`r", "`n")
            [void]$sb.Append(('<details><summary>{0}</summary><pre>{1}</pre></details>' -f (ConvertTo-HtmlText $ms[$i].Groups[1].Value.Trim()), (ConvertTo-HtmlText $body)))
        }
        [void]$sb.Append('</div></details>')
    }

    if ($script:Timings.Count) {
        [void]$sb.Append('<details class="box grp" data-section="system"><summary style="cursor:pointer;font-size:1.15em;font-weight:600;"><span class="gname">Zeitbedarf</span></summary><div style="margin-top:12px"><table><thead><tr><th>Abschnitt</th><th>Dauer</th></tr></thead><tbody>')
        foreach ($t in $script:Timings) { [void]$sb.Append(('<tr><td>{0}</td><td>{1}</td></tr>' -f (ConvertTo-HtmlText $t.Abschnitt), $t.Dauer)) }
        [void]$sb.Append('</tbody></table></div></details>')
    }
    [void]$sb.Append((Get-ReportJs))
    [void]$sb.Append(('<footer>Ausgabeordner: {0} &middot; Protokolle und Rohdaten liegen in Anhang.zip. Für eine erweiterte Auswertung die Datei {1} in ein KI-Modell hochladen: Sie enthält Auftrag, Bericht und Rohdaten.{2}</footer></main></body></html>' -f (ConvertTo-HtmlText $OutputDir), (ConvertTo-HtmlText $kiLeaf), $(if ($script:DbSaved) { ' &middot; Datenbankeintrag: ' + (ConvertTo-HtmlText $script:DbSaved) } else { '' })))
    [IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))
}

