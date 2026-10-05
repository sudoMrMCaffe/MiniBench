#region ---------- Vergleichsdatenbank ----------
# Format 2 (ab 2.2): zusätzlich Geraet = Kennung (SHA-256 aus Mainboard und Firmware), Güte und Quellen der Kennung.
# Format 1 bleibt lesbar; solche Einträge werden über den Computernamen einem Gerät zugeordnet.
$script:DbFormat = 'PC-Diagnose-DB/2'
function Get-SafeName([string]$s) { (($s -replace '[\\/:*?"<>|\s]+', '_').Trim('_')) }

function Save-DbEntry {
    param($Sorted, [int]$NK, [int]$NW, [int]$NI)
    if (-not $script:DbDir -or $KeineDatenbank -or $AnalyzeLastRun) { return '' }
    $w = Get-CurrentRefValues
    if ($Kurztest -and -not $w.Count) { return '' }
    try { New-Item -ItemType Directory -Path $script:DbDir -Force -ErrorAction Stop | Out-Null } catch { return '' }
    $hw = [ordered]@{
        CPU = $(if ($script:BenchShort.CPU) { $script:BenchShort.CPU } else { [string]$script:Facts['Prozessor'] })
        RAM = $(if ($script:BenchShort.RAM) { $script:BenchShort.RAM } else { [string]$script:Facts['Arbeitsspeicher'] })
        GPU = $(if ($script:BenchShort.GPU) { $script:BenchShort.GPU } else { [string]$script:Facts['Grafik'] })
        IGPU = $(try { [string](@(Get-GpuAdapters | Where-Object { $_.Art -eq 'iGPU' } | ForEach-Object { Get-ShortGpuName $_.Name }) | Select-Object -First 1) } catch { '' })
        GPUGemessen = [string]$script:BenchGpuMeasured
        Datentraeger = ([string]$script:Facts['Datenträger'] -replace "`r?`n", '; ')
        Betriebssystem = [string]$script:Facts['Betriebssystem']
        Mainboard = [string]$script:Facts['Mainboard']
        WindowsInstalliert = [string]$script:Facts['Windows installiert']
    }
    $dev = Get-DeviceIdentity
    $o = [ordered]@{
        Format    = $script:DbFormat
        Name      = $(if ($script:BenchRefName) { $script:BenchRefName } else { '{0} ({1})' -f $env:COMPUTERNAME, ((@($hw.CPU, $hw.RAM, $hw.GPU) | Where-Object { $_ }) -join ', ') })
        Computer  = $env:COMPUTERNAME
        Geraet    = [ordered]@{ Id = $dev.Id; Guete = $dev.Guete; Quellen = @($dev.Quellen) }
        Datum     = (Get-Date).ToString('yyyy-MM-dd HH:mm', $script:Inv)
        Version   = $ScriptVersion
        Quelle    = 'Lauf'
        Module    = (Get-ModeLabel)
        Messdauer = $(if ($BenchmarkKurz) { 'kurz' } else { 'normal' })
        System    = [string]$script:Facts['System']
        Hardware  = $hw
        Werte     = $w
        Messwerte = $(if ($script:BenchNew.Count) { $mw = [ordered]@{}; foreach ($b in $script:BenchNew) { $mw[$b.Key] = $b.Wert }; $mw } else { [ordered]@{} })
        Ordner    = $(if ($script:DataDir -and $OutputDir -like ($script:DataDir + '*')) { $OutputDir.Substring($script:DataDir.Length).TrimStart('\') } else { $OutputDir })
        Laufwerke = @($script:BenchDisks | Where-Object { $_.SR -gt 0 } | ForEach-Object { [ordered]@{ Laufwerk = $_.Laufwerk; Klasse = $_.Klasse; SR = [math]::Round($_.SR); SW = [math]::Round($_.SW); R1 = [math]::Round($_.R1); R8 = [math]::Round($_.R8); W1 = [math]::Round($_.W1) } })
        Befunde   = [ordered]@{ Kritisch = $NK; Warnungen = $NW; Hinweise = $NI; Liste = @($Sorted | ForEach-Object { '[{0}] {1}: {2}' -f $_.Stufe, $_.Bereich, $_.Befund }) }
        Lasttest  = $script:LoadSummary
        # ab v2.6: Rendertest je Grafikeinheit und Schreibzugriffe auf den Datenträger des Datenordners
        Rendertest = @($script:GpuRender | ForEach-Object { [ordered]@{ Grafik = $_.Name; Art = $_.Art; Aufloesung = $_.Aufloesung; Fps = $_.Fps; Low1 = $_.Low1; Punkte = $_.Punkte; Bildfehler = $_.Bildfehler; Treiberreset = $_.Treiberreset; Fehler = $_.Fehler } })
        Schreibzugriffe = $(if ($script:WriteInfo) { [ordered]@{ Laufwerk = $script:WriteInfo.Laufwerk; Art = $script:WriteInfo.Art; Vorgaenge = $script:WriteInfo.Vorgaenge; MB = $script:WriteInfo.MB } } else { $null })
        Ablauf    = $(if ($SchnellerModus) { 'schneller Modus' } else { 'normal' })
        Sensoren  = $(if ($script:SensorDb.Count) { $script:SensorDb } else { [ordered]@{} })
        # ab v2.8: Modul Optimierung (angewendete Einträge und Kennzahlen vorher und nachher)
        Optimierung = $(if (@($script:OptLog).Count) { [ordered]@{ Eintraege = @($script:OptLog | ForEach-Object { [ordered]@{ Id = $_.Id; Ergebnis = $_.Ergebnis; Aenderungen = $_.Aenderungen } }); Vorher = $script:OptMetricsBefore; Nachher = $script:OptMetricsAfter } } else { $null })
        Akku      = @($script:BatteryInfo | ForEach-Object { [ordered]@{ Name = $_.Name; DesignmWh = $_.DesignmWh; VollmWh = $_.VollmWh; VerschleissProzent = $_.VerschleissProzent; Zyklen = $_.Zyklen
            LaufzeitVollMin = $(if ($_.LaufzeitVoll) { [math]::Round($_.LaufzeitVoll.TotalMinutes) } else { $null }); Quelle = $_.Quelle } })
    }
    $file = Join-Path $script:DbDir ('{0}_{1}.json' -f (Get-SafeName $env:COMPUTERNAME), (Get-Date -Format 'yyyyMMdd_HHmmss'))
    try { [IO.File]::WriteAllText($file, ($o | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false))); return $file } catch { return '' }
}

# Ältere Ausgabeordner (Version 1.x) in die Datenbank übernehmen
function Import-LegacyRun([string]$Folder) {
    $name = Split-Path $Folder -Leaf
    $tmp = $null; $csvPath = $null
    try {
        $zip = Join-Path $Folder 'Anhang.zip'
        foreach ($c in @((Join-Path $Folder 'Benchmark.csv'), (Join-Path (Join-Path $Folder 'Anhang') 'Benchmark.csv'))) { if (Test-Path -LiteralPath $c) { $csvPath = $c; break } }
        if (-not $csvPath -and (Test-Path -LiteralPath $zip)) {
            $tmp = Join-Path $(if ($script:DataDir) { Join-Path $script:DataDir 'Laufzeit' } else { $env:TEMP }) ('Import-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force -ErrorAction Stop
            $c = Join-Path $tmp 'Benchmark.csv'; if (Test-Path $c) { $csvPath = $c }
        }
        $txtPath = Join-Path $Folder 'Diagnosebericht.txt'; $htmlPath = Join-Path $Folder 'Diagnosebericht.html'
        $txt = $(if (Test-Path -LiteralPath $txtPath) { [IO.File]::ReadAllText($txtPath) } else { '' })
        $html = $(if (Test-Path -LiteralPath $htmlPath) { [IO.File]::ReadAllText($htmlPath) } else { '' })
        if (-not $csvPath -and -not $txt) { return ('{0}: keine Berichtsdaten gefunden.' -f $name) }

        $facts = @{}
        foreach ($m in [regex]::Matches($html, '(?s)<dt>(.*?)</dt><dd>(.*?)</dd>')) { $facts[[Net.WebUtility]::HtmlDecode($m.Groups[1].Value)] = ([Net.WebUtility]::HtmlDecode(($m.Groups[2].Value -replace '<br>', '; '))) }
        $rows = @(); if ($csvPath) { $rows = @(Import-Csv -LiteralPath $csvPath -Delimiter ';' -Encoding UTF8) }
        $computer = $(if ($rows.Count -and $rows[0].Computer) { $rows[0].Computer } elseif ($facts['Computer']) { $facts['Computer'] } elseif ($txt -match 'DIAGNOSEBERICHT\s+(\S+)') { $Matches[1] } else { $name })
        $datum = $(if ($rows.Count -and $rows[0].Datum) { $rows[0].Datum } elseif ($txt -match 'Erstellt\s*:\s*(\d{2})\.(\d{2})\.(\d{4}) (\d{2}:\d{2})') { '{0}-{1}-{2} {3}' -f $Matches[3], $Matches[2], $Matches[1], $Matches[4] } else { '' })
        $ver = $(if ($txt -match 'DIAGNOSEBERICHT\s+\S+\s+v([\d.]+)') { $Matches[1] } else { '1.x' })

        $map = @{ 'CPU|Einzelkern' = 'CPU|ST'; 'CPU|Mehrkern' = 'CPU|MT'; 'CPU|AES-256 verschlüsseln' = 'CPU|AES'; 'CPU|SHA-256 Prüfsumme' = 'CPU|SHA'; 'CPU|Kompression (Deflate)' = 'CPU|DEFL'
                  'RAM|Lesen' = 'RAM|Lesen'; 'RAM|Schreiben' = 'RAM|Schreiben'; 'RAM|Kopieren' = 'RAM|Kopieren'; 'RAM|Latenz' = 'RAM|Latenz'
                  'GPU|Grafikspeicher-Durchsatz' = 'GPU|VMB'; 'GPU|Desktop-Komposition' = 'GPU|DWM' }
        $w = @{}; $dsk = [ordered]@{}; $byCls = @{}
        foreach ($r in $rows) {
            $val = 0.0; if (-not [double]::TryParse([string]$r.Wert, [Globalization.NumberStyles]::Float, $script:Inv, [ref]$val) -or $val -le 0) { continue }
            $mk = '{0}|{1}' -f $r.Gruppe, $r.Messung
            if ($map.ContainsKey($mk)) { $w[$map[$mk]] = [math]::Round($val, 1); continue }
            if ($r.Gruppe -eq 'Laufwerke' -and $r.Messung -match '^(.+?) (seq\. lesen|seq\. schreiben|4K zufällig QD1|4K zufällig 8 Threads|4K zufällig schreiben QD1)$') {
                $lbl = $Matches[1]; $kind = @{ 'seq. lesen' = 'SR'; 'seq. schreiben' = 'SW'; '4K zufällig QD1' = 'R1'; '4K zufällig 8 Threads' = 'R8'; '4K zufällig schreiben QD1' = 'W1' }[$Matches[2]]
                if (-not $dsk.Contains($lbl)) { $dsk[$lbl] = [ordered]@{ Laufwerk = $lbl; Klasse = ''; SR = 0; SW = 0; R1 = 0; R8 = 0; W1 = 0 } }
                $dsk[$lbl][$kind] = [math]::Round($val)
                if ($kind -eq 'SR' -and $r.Hinweis -match 'typisch für (.+?):') { $dsk[$lbl].Klasse = $Matches[1] } elseif ($kind -eq 'SR' -and -not $dsk[$lbl].Klasse) { $dsk[$lbl].Klasse = [string]$r.Hinweis }
            }
        }
        foreach ($d in $dsk.Values) {
            $cls = ''
            if ($d.Klasse -match 'NVMe PCIe (\d)\.0 x(\d+)') { if ([int]$Matches[1] -ge 3 -and [int]$Matches[2] -ge 4) { $cls = 'NVMe' + $Matches[1] } }
            elseif ($d.Klasse -match 'NVMe PCIe (\d)\.0 \(geschätzt\)') { if ([int]$Matches[1] -ge 3) { $cls = 'NVMe' + $Matches[1] } }
            elseif ($d.Klasse -match 'SATA-SSD') { $cls = 'SATA-SSD' } elseif ($d.Klasse -match 'Festplatte') { $cls = 'HDD' }
            if (-not $cls) { continue }
            foreach ($k in 'SR', 'SW', 'R1', 'R8', 'W1') { if ($d[$k] -gt 0) { $key = "DISK|$cls|$k"; if (-not $byCls.ContainsKey($key)) { $byCls[$key] = New-Object System.Collections.ArrayList }; [void]$byCls[$key].Add([double]$d[$k]) } }
        }
        foreach ($k in $byCls.Keys) { $w[$k] = [math]::Round((($byCls[$k] | Measure-Object -Average).Average), 0) }

        # Kurzbezeichnungen aus den Kopfzeilen der Benchmark-Gruppen
        $short = @{}
        foreach ($g in @(@('PROZESSOR', 'CPU'), @('ARBEITSSPEICHER', 'RAM'), @('GRAFIK', 'GPU'))) {
            if ($txt -match ('(?m)^  {0}\s+\[[^\]]*\].*\r?\n  (.+?)(?: · |\r?$)' -f $g[0])) { $short[$g[1]] = ($Matches[1] -replace ', \d+ Kan.le$', '').Trim() }
        }
        $nk = 0; $nw = 0; $ni = 0
        if ($txt -match 'ERGEBNIS:\s*(\d+) kritisch, (\d+) Warnungen, (\d+) Hinweise') { $nk = [int]$Matches[1]; $nw = [int]$Matches[2]; $ni = [int]$Matches[3] }
        $list = @([regex]::Matches($txt, '(?m)^  \[(KRITISCH|WARNUNG|INFO)\s*\]\s+(\S+)\s+(.+?)\s*$') | ForEach-Object { '[{0}] {1}: {2}' -f $_.Groups[1].Value, $_.Groups[2].Value, $_.Groups[3].Value })

        foreach ($e in (Get-DbEntries)) { if ($e.Computer -eq $computer -and $e.Datum -eq $datum) { return ('{0}: {1} vom {2} ist bereits in der Datenbank.' -f $name, $computer, $datum) } }
        $hw = [ordered]@{
            CPU = $(if ($short.CPU) { $short.CPU } else { [string]$facts['Prozessor'] }); RAM = $(if ($short.RAM) { $short.RAM } else { [string]$facts['Arbeitsspeicher'] })
            GPU = $(if ($short.GPU) { $short.GPU } else { [string]$facts['Grafik'] }); Datentraeger = [string]$facts['Datenträger']; Betriebssystem = [string]$facts['Betriebssystem']; Mainboard = ''; WindowsInstalliert = ''
        }
        $cpuS = ($hw.CPU -replace '^(AMD|Intel\(R\))\s*', '' -replace '\((R|TM)\)', '').Trim()
        $gpuS = ($hw.GPU -replace '^(AMD|NVIDIA|Intel\(R\))\s*', '').Trim()
        $o = [ordered]@{
            Format = $script:DbFormat; Name = ('{0} ({1})' -f $computer, ((@($cpuS, $hw.RAM, $gpuS) | Where-Object { $_ }) -join ', ')); Computer = $computer
            Geraet = [ordered]@{ Id = ''; Guete = 'unbekannt'; Quellen = @() }; Datum = $datum; Version = $ver
            Quelle = ('Import aus ' + $name); Module = 'Import'; Messdauer = 'unbekannt'; System = [string]$facts['System']; Hardware = $hw; Werte = $w
            Laufwerke = @($dsk.Values); Befunde = [ordered]@{ Kritisch = $nk; Warnungen = $nw; Hinweise = $ni; Liste = $list }; Lasttest = ''
        }
        New-Item -ItemType Directory -Path $script:DbDir -Force | Out-Null
        $stamp = $(if ($datum -match '^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})') { '{0}{1}{2}_{3}{4}00' -f $Matches[1], $Matches[2], $Matches[3], $Matches[4], $Matches[5] } else { Get-Date -Format 'yyyyMMdd_HHmmss' })
        $file = Join-Path $script:DbDir ('{0}_{1}.json' -f (Get-SafeName $computer), $stamp)
        [IO.File]::WriteAllText($file, ($o | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
        return ('{0}: {1} vom {2} importiert ({3} Messwerte, {4} Laufwerke).' -f $name, $computer, $datum, $w.Count, $dsk.Count)
    } catch {
        return ('{0}: Import fehlgeschlagen: {1}' -f $name, $_.Exception.Message)
    } finally {
        if ($tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Import-LegacyFolder([string]$Root) {
    if (-not $script:DbDir) { Write-Host 'Kein beschreibbarer Datenordner vorhanden.'; return }
    $isRun = { param($d) (Test-Path -LiteralPath (Join-Path $d 'Diagnosebericht.txt')) -or (Test-Path -LiteralPath (Join-Path $d 'Anhang.zip')) -or (Test-Path -LiteralPath (Join-Path $d 'Benchmark.csv')) }
    $dirs = @()
    if (& $isRun $Root) { $dirs = @($Root) } else { $dirs = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Where-Object { & $isRun $_.FullName } | ForEach-Object { $_.FullName }) }
    if (-not $dirs.Count) { Write-Host ('In {0} wurde kein Ausgabeordner von Leos Minibench oder PC-Diagnose gefunden.' -f $Root); return }
    foreach ($d in $dirs) { Write-Host (Import-LegacyRun $d) }
}
#endregion

