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
    $kerne = $null; $threads = $null
    if ($script:Facts['Prozessor'] -match '(\d+)\s*Kerne,\s*(\d+)\s*Threads') {
        $kerne = [int]$Matches[1]; $threads = [int]$Matches[2]
    } else {
        try {
            $cpus = @(Get-CimCached Win32_Processor)
            if ($cpus.Count) {
                $kerne = [int](($cpus | Measure-Object NumberOfCores -Sum).Sum)
                $threads = [int](($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
            }
        } catch { }
    }
    $cpuRaw = $(if ($script:BenchShort.CPU) { $script:BenchShort.CPU } else { [string]$script:Facts['Prozessor'] })
    $hw = [ordered]@{
        CPU = $(if ($cpuRaw) { if (Get-Command 'Get-CpuAnzeigename' -ErrorAction SilentlyContinue) { Get-CpuAnzeigename $cpuRaw } else { $cpuRaw } } else { '' })
        Kerne = $kerne
        Threads = $threads
        RAM = $(if ($script:BenchShort.RAM) { $script:BenchShort.RAM } else { [string]$script:Facts['Arbeitsspeicher'] })
        GPU = $(if ($script:BenchShort.GPU) { $script:BenchShort.GPU } else { [string]$script:Facts['Grafik'] })
        IGPU = $(try { [string](@(Get-GpuAdapters | Where-Object { $_.Art -eq 'iGPU' } | ForEach-Object { Get-ShortGpuName $_.Name }) | Select-Object -First 1) } catch { '' })
        GPUGemessen = [string]$script:BenchGpuMeasured
        Datentraeger = ([string]$script:Facts['Datenträger'] -replace "`r?`n", '; ')
        Betriebssystem = [string]$script:Facts['Betriebssystem']
        Mainboard = [string]$script:Facts['Mainboard']
        WindowsInstalliert = [string]$script:Facts['Windows installiert']
    }
    if (Get-Command 'Get-SystemPowerProfile' -ErrorAction SilentlyContinue) {
        $pProfile = Get-SystemPowerProfile
        if ($pProfile -and $script:SensorDb) { $script:SensorDb['Verbrauch'] = $pProfile }
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
        Ablauf    = [ordered]@{
            Modus           = $(if ($SchnellerModus) { 'schneller Modus' } else { 'normal' })
            Hintergrundlast = [bool]$script:AblaufHintergrundlast
            Akkubetrieb     = [bool]$script:AblaufAkkubetrieb
        }
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
        $kerne = $null; $threads = $null
        if ($txt -match '(?m)^\s*Kerne\s*/\s*Threads\s*:\s*(\d+)\s*/\s*(\d+)') {
            $kerne = [int]$Matches[1]; $threads = [int]$Matches[2]
        } elseif ($txt -match '(\d+)\s*Kerne,\s*(\d+)\s*Threads') {
            $kerne = [int]$Matches[1]; $threads = [int]$Matches[2]
        }
        $rawCpu = $(if ($short.CPU) { $short.CPU } else { [string]$facts['Prozessor'] })
        $hw = [ordered]@{
            CPU = $(if ($rawCpu) { Get-CpuAnzeigename $rawCpu } else { '' })
            Kerne = $kerne
            Threads = $threads
            RAM = $(if ($short.RAM) { $short.RAM } else { [string]$facts['Arbeitsspeicher'] })
            GPU = $(if ($short.GPU) { $short.GPU } else { [string]$facts['Grafik'] })
            Datentraeger = [string]$facts['Datenträger']; Betriebssystem = [string]$facts['Betriebssystem']; Mainboard = ''; WindowsInstalliert = ''
        }
        $cpuS = $(if ($hw.CPU) { $hw.CPU } else { '' })
        $gpuS = ($hw.GPU -replace '^(AMD|NVIDIA|Intel\(R\))\s*', '').Trim()

        # ab v3.61: Berichtsordner in den Datenordner übernehmen, wenn er noch woanders liegt
        $leaf = Split-Path $Folder -Leaf
        $destReportDir = Join-Path (Join-Path $script:DataDir 'Berichte') $leaf
        if ($script:DataDir -and (Test-Path -LiteralPath $script:DataDir)) {
            try {
                $fullFolder = [IO.Path]::GetFullPath($Folder).TrimEnd('\', '/')
                $fullDest = [IO.Path]::GetFullPath($destReportDir).TrimEnd('\', '/')
                if ($fullFolder -ine $fullDest -and -not (Test-Path -LiteralPath $destReportDir)) {
                    Copy-Item -LiteralPath $Folder -Destination $destReportDir -Recurse -Force -ErrorAction Stop
                    $Folder = $destReportDir
                }
            } catch { }
        }
        $relOrdner = $(if ($script:DataDir -and $Folder -like ($script:DataDir + '*')) {
            $Folder.Substring($script:DataDir.Length).TrimStart('\', '/')
        } else {
            'Berichte\' + $leaf
        })

        $o = [ordered]@{
            Format = $script:DbFormat; Name = ('{0} ({1})' -f $computer, ((@($cpuS, $hw.RAM, $gpuS) | Where-Object { $_ }) -join ', ')); Computer = $computer
            Geraet = [ordered]@{ Id = ''; Guete = 'unbekannt'; Quellen = @() }; Datum = $datum; Version = $ver
            Quelle = ('Import aus ' + $name); Module = 'Import'; Messdauer = 'unbekannt'; System = [string]$facts['System']; Hardware = $hw; Werte = $w
            Ordner = $relOrdner
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

# ab v3.61: Lauf aus Ordner mit bereits vorhandener Datenbank.json importieren
function Import-RunFromDirWithJson([string]$SourceDir, [string]$DbJsonPath, [string]$PreferredName = '', [string]$OriginalName = '') {
    if (-not $OriginalName) { $OriginalName = Split-Path $SourceDir -Leaf }
    try {
        $jsonTxt = [IO.File]::ReadAllText($DbJsonPath, [Text.Encoding]::UTF8)
        $o = $jsonTxt | ConvertFrom-Json
        $computer = [string]$o.Computer
        $datum = [string]$o.Datum

        foreach ($e in (Get-DbEntries)) {
            if ($e.Computer -eq $computer -and $e.Datum -eq $datum) {
                return ('{0}: {1} vom {2} ist bereits in der Datenbank.' -f $OriginalName, $computer, $datum)
            }
        }

        $stamp = $(if ($datum -match '^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})') { '{0}{1}{2}_{3}{4}00' -f $Matches[1], $Matches[2], $Matches[3], $Matches[4], $Matches[5] } else { Get-Date -Format 'yyyyMMdd_HHmmss' })
        $folderLeaf = $(
            if ($o.Ordner) { Split-Path ([string]$o.Ordner).TrimEnd('\', '/') -Leaf }
            elseif ($PreferredName) { $PreferredName }
            else { '{0}_{1}' -f (Get-SafeName $computer), $stamp }
        )
        $destReportDir = Join-Path (Join-Path $script:DataDir 'Berichte') $folderLeaf
        if (-not (Test-Path -LiteralPath $destReportDir)) {
            New-Item -ItemType Directory -Path $destReportDir -Force | Out-Null
        }
        foreach ($f in @(Get-ChildItem -LiteralPath $SourceDir -File -Force -ErrorAction SilentlyContinue)) {
            if ($f.Name -ieq 'Datenbank.json' -or $f.Extension -ieq '.minibench') { continue }
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $destReportDir $f.Name) -Force
        }

        $relOrdner = 'Berichte\' + $folderLeaf
        $o | Add-Member -NotePropertyName Ordner -NotePropertyValue $relOrdner -Force
        $o | Add-Member -NotePropertyName Quelle -NotePropertyValue ('Import aus ' + $OriginalName) -Force

        New-Item -ItemType Directory -Path $script:DbDir -Force | Out-Null
        $dbFile = Join-Path $script:DbDir ('{0}_{1}.json' -f (Get-SafeName $computer), $stamp)
        [IO.File]::WriteAllText($dbFile, ($o | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))

        return ('{0}: {1} vom {2} erfolgreich importiert (Bericht verknüpft).' -f $OriginalName, $computer, $datum)
    } catch {
        return ('{0}: Import fehlgeschlagen: {1}' -f $OriginalName, $_.Exception.Message)
    }
}

# ab v3.61: Lauf aus einem .minibench- oder .zip-Archiv importieren
function Import-ArchiveRun([string]$ArchivePath) {
    $name = Split-Path $ArchivePath -Leaf
    $baseName = [IO.Path]::GetFileNameWithoutExtension($ArchivePath)
    $tmp = Join-Path $(if ($script:DataDir) { Join-Path $script:DataDir 'Laufzeit' } else { [IO.Path]::GetTempPath() }) ('ImportArchive_' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        if ('System.IO.Compression.ZipFile' -as [type]) {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $tmp)
        } else {
            Expand-Archive -LiteralPath $ArchivePath -DestinationPath $tmp -Force -ErrorAction Stop
        }

        $dbJson = Join-Path $tmp 'Datenbank.json'
        if (Test-Path -LiteralPath $dbJson) {
            return (Import-RunFromDirWithJson -SourceDir $tmp -DbJsonPath $dbJson -PreferredName $baseName -OriginalName $name)
        } elseif ((Test-Path -LiteralPath (Join-Path $tmp 'Diagnosebericht.txt')) -or (Test-Path -LiteralPath (Join-Path $tmp 'Diagnosebericht.html')) -or (Test-Path -LiteralPath (Join-Path $tmp 'Benchmark.csv'))) {
            $destReportDir = Join-Path (Join-Path $script:DataDir 'Berichte') $baseName
            if (-not (Test-Path -LiteralPath $destReportDir)) {
                New-Item -ItemType Directory -Path $destReportDir -Force | Out-Null
            }
            foreach ($f in @(Get-ChildItem -LiteralPath $tmp -Force -ErrorAction SilentlyContinue)) {
                Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $destReportDir $f.Name) -Recurse -Force
            }
            return (Import-LegacyRun $destReportDir)
        } else {
            return ('{0}: Im Archiv wurden weder Datenbank.json noch Berichtsdaten gefunden.' -f $name)
        }
    } catch {
        return ('{0}: Archiv konnte nicht entpackt werden: {1}' -f $name, $_.Exception.Message)
    } finally {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ab v3.61: Einzelne .json-Datenbankdatei importieren
function Import-JsonRun([string]$JsonPath) {
    $name = Split-Path $JsonPath -Leaf
    try {
        $jsonTxt = [IO.File]::ReadAllText($JsonPath, [Text.Encoding]::UTF8)
        $o = $jsonTxt | ConvertFrom-Json
        $computer = [string]$o.Computer
        $datum = [string]$o.Datum

        foreach ($e in (Get-DbEntries)) {
            if ($e.Computer -eq $computer -and $e.Datum -eq $datum) {
                return ('{0}: {1} vom {2} ist bereits in der Datenbank.' -f $name, $computer, $datum)
            }
        }

        $parent = Split-Path $JsonPath -Parent
        $baseName = [IO.Path]::GetFileNameWithoutExtension($JsonPath)
        $candReport = @()
        if ($o.Ordner) {
            $candReport += Join-Path $parent ($o.Ordner)
            $candReport += Join-Path (Split-Path $parent -Parent) ($o.Ordner)
            $candReport += Join-Path $parent (Split-Path ([string]$o.Ordner).TrimEnd('\', '/') -Leaf)
        }
        $candReport += Join-Path $parent $baseName
        $candReport += Join-Path (Join-Path $parent 'Berichte') $baseName

        $foundReport = $null
        foreach ($cr in $candReport) {
            if ($cr -and (Test-Path -LiteralPath $cr -PathType Container) -and ((Test-Path -LiteralPath (Join-Path $cr 'Diagnosebericht.html')) -or (Test-Path -LiteralPath (Join-Path $cr 'Diagnosebericht.txt')))) {
                $foundReport = $cr; break
            }
        }

        $stamp = $(if ($datum -match '^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})') { '{0}{1}{2}_{3}{4}00' -f $Matches[1], $Matches[2], $Matches[3], $Matches[4], $Matches[5] } else { Get-Date -Format 'yyyyMMdd_HHmmss' })
        if ($foundReport) {
            $folderLeaf = Split-Path $foundReport -Leaf
            $destReportDir = Join-Path (Join-Path $script:DataDir 'Berichte') $folderLeaf
            if (-not (Test-Path -LiteralPath $destReportDir)) {
                Copy-Item -LiteralPath $foundReport -Destination $destReportDir -Recurse -Force
            }
            $o | Add-Member -NotePropertyName Ordner -NotePropertyValue ('Berichte\' + $folderLeaf) -Force
        }

        New-Item -ItemType Directory -Path $script:DbDir -Force | Out-Null
        $dbFile = Join-Path $script:DbDir ('{0}_{1}.json' -f (Get-SafeName $computer), $stamp)
        [IO.File]::WriteAllText($dbFile, ($o | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
        return ('{0}: {1} vom {2} importiert{3}.' -f $name, $computer, $datum, $(if ($foundReport) { ' (Bericht kopiert)' } else { '' }))
    } catch {
        return ('{0}: Import fehlgeschlagen: {1}' -f $name, $_.Exception.Message)
    }
}

# ab v3.61: Einzelnes Element (Datei oder Ordner) importieren
function Import-SingleRunItem([string]$Item) {
    if (-not (Test-Path -LiteralPath $Item)) {
        return ('{0}: Datei oder Ordner nicht gefunden.' -f $Item)
    }
    if ($Item -match '\.(minibench|zip)$') {
        return (Import-ArchiveRun $Item)
    }
    if ($Item -match '\.json$') {
        return (Import-JsonRun $Item)
    }
    if (Test-Path -LiteralPath $Item -PathType Container) {
        $dbJson = Join-Path $Item 'Datenbank.json'
        if (Test-Path -LiteralPath $dbJson) {
            return (Import-RunFromDirWithJson -SourceDir $Item -DbJsonPath $dbJson)
        }
        $isRun = (Test-Path -LiteralPath (Join-Path $Item 'Diagnosebericht.txt')) -or `
                 (Test-Path -LiteralPath (Join-Path $Item 'Diagnosebericht.html')) -or `
                 (Test-Path -LiteralPath (Join-Path $Item 'Benchmark.csv')) -or `
                 (Test-Path -LiteralPath (Join-Path $Item 'Anhang.zip'))
        if ($isRun) {
            return (Import-LegacyRun $Item)
        }
        $subDirs = @(Get-ChildItem -LiteralPath $Item -Directory -ErrorAction SilentlyContinue | Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'Diagnosebericht.txt')) -or `
            (Test-Path -LiteralPath (Join-Path $_.FullName 'Diagnosebericht.html')) -or `
            (Test-Path -LiteralPath (Join-Path $_.FullName 'Datenbank.json')) -or `
            (Test-Path -LiteralPath (Join-Path $_.FullName 'Benchmark.csv')) -or `
            (Test-Path -LiteralPath (Join-Path $_.FullName 'Anhang.zip'))
        } | ForEach-Object { $_.FullName })
        $subFiles = @(Get-ChildItem -LiteralPath $Item -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -match '^\.(minibench|zip|json)$'
        } | ForEach-Object { $_.FullName })
        $all = $subDirs + $subFiles
        if (-not $all.Count) {
            return ('In {0} wurde kein Ausgabeordner von Leos Minibench oder PC-Diagnose gefunden.' -f $Item)
        }
        $lines = @()
        foreach ($sub in $all) {
            $lines += Import-SingleRunItem $sub
        }
        return ($lines -join "`r`n")
    }
    return ('{0}: Nicht unterstütztes Format.' -f $Item)
}

function Import-LegacyFolder([string]$Root) {
    if (-not $script:DbDir) { Write-Host 'Kein beschreibbarer Datenordner vorhanden.'; return }
    $items = @($Root -split '\|' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })
    if (-not $items.Count) { Write-Host 'Kein Pfad zum Importieren angegeben.'; return }
    foreach ($item in $items) {
        Write-Host (Import-SingleRunItem $item)
    }
}
#endregion

