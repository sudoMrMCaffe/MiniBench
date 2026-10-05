#region ---------- GPU-Rendertest (ab v2.6) ----------
# Renderer in C# (Kern\Grafiktest.cs, Direct3D 11, je Grafikeinheit ein eigenes Gerät). Hier: Auswahl der
# Grafikeinheiten, Einstellungen, Kennzahlen, Befunde und Diagramme für Benchmark und Lasttest.
$script:GpuRender = [System.Collections.Generic.List[object]]::new()   # Ergebnisse des Benchmarks je Grafikeinheit
$script:GpuLoad   = [System.Collections.Generic.List[object]]::new()   # Ergebnisse des Lasttests je Grafikeinheit
$script:DisplayRates = @()                                              # Bildwiederholraten der Monitore (Bildratengrenze)

# Auflösung aus "1280x720" bzw. "1920x1080"; Unbekanntes ergibt 1280x720
function Get-RenderSize([string]$Text) {
    if (([string]$Text).Trim() -match '^(\d{3,4})\s*[x×]\s*(\d{3,4})$') {
        $w = [int]$Matches[1]; $h = [int]$Matches[2]
        if ($w -ge 320 -and $h -ge 180 -and $w -le 7680 -and $h -le 4320) { return @($w, $h) }
    }
    return @(1280, 720)
}

# Anzeige: 0 ohne, 1 Fenster, 2 Vollbild
function Get-RenderPreviewMode([string]$Text) {
    switch -Regex (([string]$Text).Trim().ToLowerInvariant()) {
        '^voll' { return 2 }
        '^(aus|ohne|keine|0)$' { return 0 }
        default { return 1 }
    }
}

# Hardware-Grafikeinheiten laut DXGI: Grafikkarte vor Prozessorgrafik. Software-Adapter (Microsoft Basic Render
# Driver, WARP) und virtuelle Adapter (Remotedesktop, Hyper-V) zählen nicht.
function Get-RenderAdapters($Raw = $null) {
    if ($null -eq $Raw) {
        if (-not $GpuTypesLoaded) { return @() }
        try { $Raw = @([DiagGpu]::Adapters()) } catch { $Raw = @() }
    }
    $seen = @{}
    $list = @()
    foreach ($a in @($Raw)) {
        if (-not $a -or $a.Software) { continue }
        $key = [string]$a.Luid
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $kind = Get-GpuKind ([string]$a.Name)
        if ($kind -eq 'virtuell') { continue }
        $list += [pscustomobject]@{
            Index = [int]$a.Index; Name = ([string]$a.Name).Trim(); Art = $kind; Hersteller = [string]$a.Vendor; SpeicherMB = [long]$a.DedicatedMB
            Bezeichnung = $(switch ($kind) { 'dGPU' { 'Grafikkarte' } 'iGPU' { 'Prozessorgrafik' } default { 'Grafik' } })
        }
    }
    return @($list | Sort-Object @{ e = { switch ($_.Art) { 'dGPU' { 0 } 'iGPU' { 1 } default { 2 } } } }, Index)
}

# Auswahl der Grafikeinheiten (ab v2.65, Parameter -GpuAuswahl): Alle, Grafikkarte, Prozessorgrafik oder der Name einer
# Einheit. Passt die Auswahl auf diesem PC zu keiner Einheit (Voreinstellung von einem anderen PC), gelten alle Einheiten.
function Select-RenderAdapters($Adapters, [string]$Auswahl = 'Alle') {
    $all = @($Adapters | Where-Object { $_ })
    $a = ([string]$Auswahl).Trim()
    $res = [pscustomobject]@{ Adapter = $all; Hinweis = ''; Auswahl = 'alle Grafikeinheiten' }
    if (-not $a -or $a -match '^(alle|all|\*)$') { return $res }
    $pick = @()
    switch -Regex ($a) {
        '^(grafikkarte|dgpu)$' { $pick = @($all | Where-Object { $_.Art -eq 'dGPU' }); $res.Auswahl = 'nur Grafikkarte'; break }
        '^(prozessorgrafik|igpu)$' { $pick = @($all | Where-Object { $_.Art -eq 'iGPU' }); $res.Auswahl = 'nur Prozessorgrafik'; break }
        default {
            $n = ($a -replace '^(name:)', '').Trim()
            $pick = @($all | Where-Object { ([string]$_.Name).Trim() -eq $n })
            if (-not $pick.Count) { $pick = @($all | Where-Object { ([string]$_.Name).IndexOf($n, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) }
            $res.Auswahl = ('nur {0}' -f $n)
        }
    }
    if ($pick.Count) { $res.Adapter = $pick; return $res }
    if ($all.Count) { $res.Hinweis = ('Auswahl "{0}" passt auf diesem PC zu keiner Grafikeinheit, getestet werden alle.' -f $res.Auswahl); $res.Auswahl = 'alle Grafikeinheiten' }
    return $res
}

# Bildwiederholraten der angeschlossenen Monitore (für die Erkennung einer Bildratengrenze)
function Get-DisplayRefreshRates {
    $r = @()
    try { $r = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { [int]$_.CurrentRefreshRate } | Where-Object { $_ -gt 20 -and $_ -lt 1000 } | Sort-Object -Unique) } catch { }
    return $r
}

# Bildratengrenze erkennen (ab v2.65). Die Gegenprobe rendert dieselbe Szene mit voller und mit einem Viertel der
# Rechenlast. Begrenzt nur die Grafikeinheit, steigen die Bilder/s mit weniger Last mindestens um 30 %. Bleiben sie
# gleich, begrenzt etwas anderes: liegt der Wert knapp unter einer Bildwiederholrate oder einer üblichen Grenze, ist es
# fast immer eine Bildratengrenze im Grafiktreiber (Radeon Chill, FRTC, NVIDIA Max Frame Rate, Intel Frame Limiter).
function Get-FpsLimitAssessment($Full, $Light, $RefreshRates = @()) {
    $f = 0.0; $l = 0.0
    try { $f = [double]$Full; $l = [double]$Light } catch { return $null }
    if ($f -le 0 -or $l -le 0) { return $null }
    $ratio = $l / $f
    $res = [pscustomobject]@{ Begrenzt = $false; Faktor = [math]::Round($ratio, 2); Grenze = $null; Voll = [math]::Round($f, 1); Leicht = [math]::Round($l, 1); Text = '' }
    if ($ratio -ge 1.3) { return $res }
    $caps = @(@($RefreshRates | Where-Object { $_ -gt 20 } | ForEach-Object { [double]$_ }) + @(30, 50, 60, 72, 75, 90, 100, 120, 144, 165, 170, 175, 180, 200, 240) | Sort-Object -Unique)
    $near = @($caps | Where-Object { $f -ge $_ * 0.85 -and $f -le $_ * 1.03 } | Sort-Object { [math]::Abs($f - $_) }) | Select-Object -First 1
    $res.Begrenzt = $true
    if ($null -ne $near) {
        $res.Grenze = [int]$near
        $res.Text = ('Bildratengrenze aktiv: {0:N0} Bilder/s mit voller und {1:N0} mit einem Viertel der Rechenlast, knapp unter {2} Hz. Begrenzung im Grafiktreiber abschalten (AMD: Radeon Chill oder Frame Rate Target Control, NVIDIA: Max. Bildrate, Intel: Frame Rate Limiter), sonst sind die Werte nicht mit anderen PCs vergleichbar.' -f $f, $l, $res.Grenze)
    } else {
        $res.Text = ('Die Bilder/s steigen mit einem Viertel der Rechenlast kaum ({0:N0} statt {1:N0}). Eine Bildratengrenze im Grafiktreiber oder der Prozessor bremst den Rendertest; Werte sind nur eingeschränkt vergleichbar.' -f $l, $f)
    }
    return $res
}

function Get-RenderUnavailableText {
    if (-not $GpuTypesLoaded) { return 'Rendertest nicht verfügbar: C#-Routinen nicht geladen (Constrained Language Mode oder Fehler beim Übersetzen)' }
    $e = ''; try { $e = [string][DiagGpu]::LastError } catch { }
    if ($e) { return ('Rendertest nicht möglich: {0}' -f $e) }
    return 'Rendertest nicht möglich: keine Hardware-Grafikeinheit erreichbar (z. B. Remotedesktop ohne Grafikbeschleunigung oder fehlender Grafiktreiber)'
}

# Kennzahlen eines Laufs für Bericht, Datenbank und KI-Datei
function ConvertTo-RenderResult($Run, $Adapter) {
    # Renderthread antwortet nicht mehr (Treiber hängt): Zwischenstand berechnen und als Fehler kennzeichnen
    $hung = -not $Run.Done
    if ($hung) { try { [DiagGpu]::Summarize($Run) } catch { } }
    $err = [string]$Run.Error
    if ($hung -and -not $err) { $err = 'Grafiktreiber reagiert nicht, der Rendertest ließ sich nicht beenden (Werte bis dahin)' }
    $sec = [double]$Run.Seconds; if ($sec -le 0) { $sec = [double]$Run.ElapsedSec }
    [pscustomobject]@{
        Name = $(if ($Run.AdapterName) { [string]$Run.AdapterName } else { [string]$Adapter.Name }); Art = [string]$Adapter.Art; Bezeichnung = [string]$Adapter.Bezeichnung; Index = [int]$Adapter.Index
        Ok = ([bool]$Run.Ok -and -not $hung); Fehler = $err; Haengt = $hung; Aufloesung = ('{0}x{1}' -f $Run.Width, $Run.Height); Width = [int]$Run.Width; Height = [int]$Run.Height
        Ebene = [string]$Run.FeatureLevel; Sekunden = [math]::Round($sec, 1); Bilder = [long]$Run.MeasuredFrames
        Fps = [math]::Round([double]$Run.AvgFps, 1); Low1 = [math]::Round([double]$Run.Low1Fps, 1); Low01 = [math]::Round([double]$Run.Low01Fps, 1); Mikroruckler = [math]::Round([double]$Run.StutterPct, 2); MinFps = [math]::Round([double]$Run.MinFps, 1); MaxFps = [math]::Round([double]$Run.MaxFps, 1)
        MedianMs = [math]::Round([double]$Run.MedianMs, 2); P99Ms = [math]::Round([double]$Run.P99Ms, 2); MaxMs = [math]::Round([double]$Run.MaxMs, 1); Punkte = [math]::Round([double]$Run.Score)
        Treiberreset = [bool]$Run.DeviceRemoved; ResetGrund = [string]$Run.RemovedReason; Esc = [bool]$Run.EscPressed
        Bildpruefungen = [int]$Run.ImageChecks; Bildfehler = [int]$Run.ImageErrors; Referenzbild = [string]$Run.RefHash
        FpsVerlauf = @($Run.FpsPerSecond | ForEach-Object { [math]::Round([double]$_, 1) }); Bildzeiten = $Run.FrameMs
        Beginn = $Run.Started; Ende = $Run.Ended
        ProbeVoll = [math]::Round([double]$Run.ProbeFpsFull, 1); ProbeLeicht = [math]::Round([double]$Run.ProbeFpsLight, 1)
        Grenze = $(if ([bool]$Run.ProbeLimit) { Get-FpsLimitAssessment $Run.ProbeFpsFull $Run.ProbeFpsLight $script:DisplayRates } else { $null })
    }
}

# Bildzeiten verdichten: höchstens $Max Punkte, je Abschnitt die längste Bildzeit (Ruckler bleiben sichtbar)
function Get-FrameTimePoints($FrameMs, [int]$Max = 480) {
    $f = @($FrameMs)
    if ($f.Count -lt 2) { return @() }
    $per = [math]::Max(1, [int][math]::Ceiling($f.Count / [double]$Max))
    $res = New-Object System.Collections.Generic.List[object]
    $t = 0.0; $i = 0
    while ($i -lt $f.Count) {
        $mx = 0.0; $n = [math]::Min($per, $f.Count - $i)
        for ($k = 0; $k -lt $n; $k++) { $v = [double]$f[$i + $k]; $t += $v / 1000.0; if ($v -gt $mx) { $mx = $v } }
        $res.Add([pscustomobject]@{ T = [math]::Round($t, 2); V = [math]::Round($mx, 2) })
        $i += $n
    }
    return $res.ToArray()
}

# Bilder/s seit dem letzten Messpunkt des Lasttests (Eintrag mit Run, Frames0, T0). Der erste Wert nach dem Start
# enthält Probe und Fensteraufbau und nimmt deshalb die Bilder/s der letzten halben Sekunde.
function Get-FpsSince($Entry, $Now = $null) {
    if (-not $Entry -or -not $Entry.Run) { return $null }
    if ($null -eq $Now) { $Now = Get-Date }
    $f = [long]$Entry.Run.Frames
    $dt = ($Now - $Entry.T0).TotalSeconds
    if ($dt -lt 0.5) { return $null }
    $v = $null
    if ([long]$Entry.Frames0 -le 0) { if ($f -gt 0) { $v = [math]::Round([double]$Entry.Run.LiveFps, 1) } }
    elseif ($f -ge [long]$Entry.Frames0) { $v = [math]::Round(($f - [long]$Entry.Frames0) / $dt, 1) }
    $Entry.Frames0 = $f; $Entry.T0 = $Now
    return $v
}

# Abfall der Bilder/s unter Dauerlast: Mittel der ersten gegen das der letzten Minute (in %, positiv = langsamer geworden)
function Get-FpsDrop($FpsPerSecond) {
    $v = @($FpsPerSecond | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($v.Count -lt 90) { return $null }
    $n = [math]::Min(60, [int]($v.Count / 3))
    $a = ($v[0..($n - 1)] | Measure-Object -Average).Average
    $b = ($v[($v.Count - $n)..($v.Count - 1)] | Measure-Object -Average).Average
    if ($a -le 0) { return $null }
    return [math]::Round(($a - $b) / $a * 100, 1)
}

# Treiber-Resets (TDR): System-Ereignis 4101 der Quelle Display ("Anzeigetreiber reagiert nicht mehr und wurde wiederhergestellt")
function Get-TdrEvents([datetime]$Since) {
    return @(Get-Ev @{ LogName = 'System'; ProviderName = 'Display'; Id = 4101; StartTime = $Since } 50)
}

# Ereignisse 4101 einer Grafikeinheit zuordnen: Treibername in der Meldung (nvlddmkm, igfx, amdkmdag ...).
# Nennt die Meldung keinen bekannten Treiber, zählt sie für die erste Grafikeinheit ($Fallback).
function Select-TdrEvents($Events, $Adapter, [bool]$Fallback = $false) {
    $pat = switch -Regex ([string]$Adapter.Hersteller + ' ' + [string]$Adapter.Name) {
        'NVIDIA' { 'nvlddmkm'; break }
        'Intel' { 'igfx|iigd|igdkmd|intel'; break }
        'AMD|Radeon' { 'amdkmdag|atikmdag|amdwddmg|amd'; break }
        default { '' }
    }
    $known = 'nvlddmkm|igfx|iigd|igdkmd|amdkmdag|atikmdag|amdwddmg'
    return @(@($Events) | Where-Object { $_ } | Where-Object { ($pat -and ([string]$_.Message) -match $pat) -or ($Fallback -and ([string]$_.Message) -notmatch $known) })
}

# Befunde eines Rendertests (Benchmark oder Lasttest). Rückgabe: Status OK, Info, Warnung oder Fehler
function Add-RenderFindings($Res, [string]$Context, $Tdr = @()) {
    $st = $(if ($Res.Ok) { 'OK' } else { 'Info' })
    $who = ('{0} ({1})' -f $Res.Name, $Res.Bezeichnung)
    $tdrN = @($Tdr).Count
    if ($Res.Treiberreset -or $tdrN) {
        $why = @()
        if ($Res.Treiberreset) { $why += ('Direct3D meldet {0}' -f $(if ($Res.ResetGrund) { $Res.ResetGrund } else { 'ein entferntes Gerät' })) }
        if ($tdrN) { $why += ('{0}x Ereignis 4101 (Display) im Systemprotokoll' -f $tdrN) }
        Add-Finding WARNUNG 'Grafik' ('Treiber-Reset (TDR) während des {0} auf {1}: {2}. Grafiktreiber aktualisieren oder sauber neu installieren, Übertaktung zurücknehmen, Kühlung und Netzteil prüfen.' -f $Context, $who, ($why -join ', '))
        $st = 'Fehler'
    }
    if ($Res.Bildfehler -gt 0) {
        Add-Finding WARNUNG 'Grafik' ('Bildfehler im {0} auf {1}: {2} von {3} Prüfbildern weichen vom Referenzbild ab. Hinweis auf Fehler im Grafikspeicher oder Grafikchip unter Last (Übertaktung, Temperatur, Defekt).' -f $Context, $who, $Res.Bildfehler, $Res.Bildpruefungen)
        if ((Get-StatusRank $st) -lt 3) { $st = 'Fehler' }
    }
    if ($Res.Haengt -and -not $Res.Treiberreset) {
        Add-Finding WARNUNG 'Grafik' ('Grafiktreiber reagiert nicht: Der Rendertest auf {0} ließ sich während des {1} nicht beenden. Grafiktreiber aktualisieren oder neu installieren; tritt das wiederholt auf, die Grafikeinheit unter Last prüfen lassen.' -f $who, $Context)
        return 'Fehler'
    }
    if (-not $Res.Ok -and -not $Res.Treiberreset -and $Res.Fehler -and $Res.Fehler -notmatch 'vor Beginn der Messung beendet') {
        Add-Finding INFO 'Grafik' ('{0} auf {1} nicht möglich: {2}' -f $(if ($Context -match 'Lasttest') { 'Grafiklast' } else { 'Rendertest' }), $who, $Res.Fehler)
    }
    return $st
}

# Benchmark: jede Grafikeinheit nacheinander (Messungen nie parallel), Aufwärmen und Messen mit fester Szene
function Invoke-RenderBenchmark($Adapters, [int]$Width, [int]$Height, [int]$Preview, [int]$WarmupMs, [int]$MeasureMs) {
    $out = New-Object System.Collections.Generic.List[object]
    $n = 0
    foreach ($ad in @($Adapters)) {
        $n++
        $label = ('Rendertest {0} ({1}, {2}x{3})' -f $ad.Name, $ad.Bezeichnung, $Width, $Height)
        Write-Step ('{0} ...' -f $label)
        $t0 = Get-Date
        $r = New-Object GpuRun
        $r.AdapterIndex = $ad.Index; $r.Width = $Width; $r.Height = $Height; $r.WarmupMs = $WarmupMs; $r.MeasureMs = $MeasureMs
        $r.Preview = $Preview; $r.CheckEveryMs = 0; $r.Title = 'Benchmark'; $r.ProbeLimit = $true
        [void][DiagGpu]::Start($r)
        $total = [double]($WarmupMs + $MeasureMs + 6600)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $r.Done) {
            $pc = [int][math]::Min(99.0, $sw.ElapsedMilliseconds / $total * 100.0)
            Show-Sub ('Benchmark Grafik: Rendertest {0}/{1}' -f $n, @($Adapters).Count) ('{0}   {1}   {2:N0} Bilder/s' -f $ad.Name, $r.Phase, $r.LiveFps) $pc
            # Frist: 2 Minuten über der geplanten Dauer anhalten, nach weiteren 30 s ohne Antwort aufgeben (Treiber hängt)
            if ($sw.Elapsed.TotalSeconds -gt ($total / 1000.0 + 120)) { $r.Stop = $true }
            if ($sw.Elapsed.TotalSeconds -gt ($total / 1000.0 + 150)) { break }
            # ab v2.7: Sensoren des Benchmarks (Temperatur und Takt der Grafik während der Messung)
            if ($script:BenchSens -and $script:BenchSens.On) { Add-BenchSensorSample }
            Start-Sleep -Milliseconds 400
        }
        Hide-Sub
        $res = ConvertTo-RenderResult $r $ad
        $res | Add-Member -NotePropertyName Tdr -NotePropertyValue @(Get-TdrEvents $t0.AddSeconds(-2)) -Force
        $out.Add($res)
        if ($res.Esc) { Write-Step 'Rendertest mit Esc beendet, weitere Grafikeinheiten werden übersprungen.'; break }
        if ($res.Haengt) { Write-Step 'Rendertest reagiert nicht, weitere Grafikeinheiten werden übersprungen.'; break }
    }
    return $out.ToArray()
}

# HTML: Bildzeiten und Bilder/s je Grafikeinheit (Benchmark) als Kurven
function New-RenderChartsHtml {
    $runs = @($script:GpuRender | Where-Object { $_.Ok })
    if (-not $runs.Count) { return '' }
    $sb = New-Object System.Text.StringBuilder
    $cls = @('s2', 's5', 's1', 's4')
    $ser = @(); $k = 0
    foreach ($r in $runs) { $ser += @{ Name = ('{0} ({1})' -f $r.Name, $r.Bezeichnung); Cls = $cls[$k % $cls.Count]; Points = @(Get-FrameTimePoints $r.Bildzeiten) }; $k++ }
    $svg = New-MultiLineSvg $ser 'ms' @() @() 'N1'
    if ($svg) { [void]$sb.Append('<h3>Rendertest: Bildzeiten (ms, längste je Abschnitt)</h3>' + $svg) }
    [void]$sb.Append('<div class="tw"><table><thead><tr><th>Grafikeinheit</th><th>Auflösung</th><th class="r">Ø Bilder/s</th><th class="r">1-%-Low</th><th class="r">0,1-%-Low</th><th class="r">Mikroruckler</th><th class="r">Bildzeit Median</th><th class="r">99 %</th><th class="r">Punktzahl</th><th>Bildprüfung</th></tr></thead><tbody>')
    foreach ($r in @($script:GpuRender)) {
        [void]$sb.Append(('<tr><td>{0}<small class="hint">{1}{2}</small></td><td class="nw">{3}</td><td class="num r">{4}</td><td class="num r">{5}</td><td class="num r">{6}</td><td class="num r">{7}</td><td class="num r">{8}</td><td class="num r">{9}</td><td class="num r">{10}</td><td>{11}</td></tr>' -f
            (ConvertTo-HtmlText $r.Name), (ConvertTo-HtmlText $r.Bezeichnung), $(if ($r.Ebene) { ', Direct3D Feature-Level ' + $r.Ebene } else { '' }), $r.Aufloesung,
            $(if ($r.Ok) { '{0:N1}' -f $r.Fps } else { ConvertTo-HtmlText $r.Fehler }),
            $(if ($r.Ok) { '{0:N1}' -f $r.Low1 } else { '' }),
            $(if ($r.Ok) { '{0:N1}' -f $r.Low01 } else { '' }),
            $(if ($r.Ok) { '{0:N1} %' -f $r.Mikroruckler } else { '' }),
            $(if ($r.Ok) { '{0:N2} ms' -f $r.MedianMs } else { '' }),
            $(if ($r.Ok) { '{0:N2} ms' -f $r.P99Ms } else { '' }),
            $(if ($r.Ok) { '{0:N0}' -f $r.Punkte } else { '' }),
            $(if ($r.Bildpruefungen) { $(if ($r.Bildfehler) { '{0} von {1} abweichend' -f $r.Bildfehler, $r.Bildpruefungen } else { 'gleich ({0}x)' -f $r.Bildpruefungen }) } else { '' })))
    }
    [void]$sb.Append('</tbody></table></div>')
    foreach ($r in @($script:GpuRender | Where-Object { $_.Grenze -and $_.Grenze.Begrenzt })) { [void]$sb.Append(('<div class="thr warn"><b>{0}: Bildratengrenze</b><br>{1}</div>' -f (ConvertTo-HtmlText $r.Name), (ConvertTo-HtmlText $r.Grenze.Text))) }
    [void]$sb.Append('<p class="note tight">Eigener Rendertest mit Direct3D 11: fester Fell-Torus mit Volumennebel, ohne VSync, je Grafikeinheit einzeln. 1-%-Low = Bilder/s aus den langsamsten 1 % der Bildzeiten. Punktzahl = Ø Bilder/s x Pixel je Bild / 10 000. Bildprüfung: ein Referenzbild vor und nach der Messung muss bitgleich sein. Gegenprobe: dieselbe Szene mit einem Viertel der Rechenlast muss deutlich mehr Bilder/s ergeben, sonst bremst eine Bildratengrenze.</p>')
    return $sb.ToString()
}
#endregion
