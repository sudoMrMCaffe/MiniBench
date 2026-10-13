# =====================================================================================
#             LEOS MINIBENCH: BERICHTE & DATENBANK AKTUALISIEREN
# =====================================================================================
# Aktualisiert alle vorhandenen HTML-Berichte, ergänzt fehlende Kerne/Threads sowie
# Sensor- und Stromverbrauchswerte aus Anhang.zip, berechnet realistische Systemleistungs-
# profile (inklusive Referenzen) und verschiebt veraltete Dateien ins Archiv.

[CmdletBinding()]
param(
    [string]$DataDir = 'Aktueller Build\MiniBench-Daten',
    [string]$AppDir = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$baseDir = if ($AppDir) { $AppDir } else { (Get-Location).Path }
$dataRoot = if ([System.IO.Path]::IsPathRooted($DataDir)) { $DataDir } else { Join-Path $baseDir $DataDir }

if (-not (Test-Path -LiteralPath $dataRoot)) {
    throw "Datenverzeichnis nicht gefunden: $dataRoot"
}

$dbDir = Join-Path $dataRoot 'Datenbank'
$repDir = Join-Path $dataRoot 'Berichte'
$archDir = Join-Path $dataRoot 'Archiv'

# 1. Kernmodule laden
. (Join-Path $baseDir 'src\Kern\Berichtshilfen.ps1')
. (Join-Path $baseDir 'src\Kern\Referenzen_Eingebettet.ps1')
. (Join-Path $baseDir 'src\Bericht\Stil.ps1')
. (Join-Path $baseDir 'src\Bericht\HtmlBericht.ps1')
. (Join-Path $baseDir 'src\Bericht\Bausteine_Dashboard.ps1')
. (Join-Path $baseDir 'src\Bericht\Bausteine_Systemvergleich.ps1')

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " LEOS MINIBENCH: BERICHTE & DATENBANK AKTUALISIEREN                   " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Datenordner: $dataRoot"

# -------------------------------------------------------------------------------------
# SCHRITT 1: Referenzprofile aktualisieren (eingebettet und Referenz.json)
# -------------------------------------------------------------------------------------
Write-Host "`n[1/4] Referenzprofile aktualisieren ..." -ForegroundColor Yellow

$refJsonPath = Join-Path $dataRoot 'Referenz.json'
if (Test-Path -LiteralPath $refJsonPath) {
    try {
        $refJ = [System.IO.File]::ReadAllText($refJsonPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $pRef = Get-SystemPowerProfile -Entry $refJ
        if ($pRef -and $pRef.Volllast -and $pRef.Volllast.Verfuegbar) {
            $refJ.Hardware | Add-Member -NotePropertyName 'PowerDisplay' -NotePropertyValue ('~{0:N0} W / ~{1:N0} W' -f $pRef.Volllast.P_AC, $pRef.Leerlauf.P_AC) -Force
            $refJ.Hardware | Add-Member -NotePropertyName 'PowerLoad' -NotePropertyValue ([math]::Round($pRef.Volllast.P_AC, 1)) -Force
            $refJ.Hardware | Add-Member -NotePropertyName 'PowerIdle' -NotePropertyValue ([math]::Round($pRef.Leerlauf.P_AC, 1)) -Force
            $refJ.Hardware | Add-Member -NotePropertyName 'PowerLoadTip' -NotePropertyValue $pRef.Volllast.Aufschluesselung -Force
            
            if (-not $refJ.Werte) { $refJ | Add-Member -NotePropertyName 'Werte' -NotePropertyValue (New-Object PSObject) -Force }
            $refJ.Werte | Add-Member -NotePropertyName 'POWER_LOAD' -NotePropertyValue ([math]::Round($pRef.Volllast.P_AC, 0)) -Force
            $refJ.Werte | Add-Member -NotePropertyName 'POWER_IDLE' -NotePropertyValue ([math]::Round($pRef.Leerlauf.P_AC, 0)) -Force
            if ($pRef.Effizienz.CpuMT_PerWatt) { $refJ.Werte | Add-Member -NotePropertyName 'EFF_CPU' -NotePropertyValue $pRef.Effizienz.CpuMT_PerWatt -Force }
            if ($pRef.Effizienz.Gpu_PerWatt) { $refJ.Werte | Add-Member -NotePropertyName 'EFF_GPU' -NotePropertyValue $pRef.Effizienz.Gpu_PerWatt -Force }
            
            $utf8Bom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($refJsonPath, ($refJ | ConvertTo-Json -Depth 10), $utf8Bom)
            Write-Host "  -> Referenz.json erfolgreich mit Systemleistungs-Profil ergänzt (~$([math]::Round($pRef.Volllast.P_AC)) W)." -ForegroundColor Green
        }
    } catch {
        Write-Warning "  Referenz.json konnte nicht aktualisiert werden: $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------------------------------
# SCHRITT 2: Datenbankeinträge ergänzen (Kerne, Threads, Watt, Effizienz)
# -------------------------------------------------------------------------------------
Write-Host "`n[2/4] Datenbankeinträge aus Berichten und Anhängen ergänzen ..." -ForegroundColor Yellow

$dbFiles = @(Get-ChildItem -LiteralPath $dbDir -Filter '*.json')
$reportFolders = @(Get-ChildItem -LiteralPath $repDir -Directory | Where-Object { $_.Name -ne 'Vergleiche' })

$folderMap = @{}
foreach ($rf in $reportFolders) {
    $folderMap[$rf.Name] = $rf
}

foreach ($dbFile in $dbFiles) {
    try {
        $j = [System.IO.File]::ReadAllText($dbFile.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $comp = [string]$j.Computer
        $ordnerLeaf = if ($j.Ordner) { Split-Path ([string]$j.Ordner) -Leaf } else { '' }
        
        # Passenden Berichtsordner finden
        $matchingFolder = $null
        if ($ordnerLeaf -and $folderMap.ContainsKey($ordnerLeaf)) {
            $matchingFolder = $folderMap[$ordnerLeaf]
        } else {
            # Suche nach Name / Datum
            $dClean = ($j.Datum -replace '\W', '')
            $found = $reportFolders | Where-Object { $_.Name -like "*$comp*" }
            if ($found.Count -eq 1) {
                $matchingFolder = $found[0]
            } elseif ($found.Count -gt 1) {
                $dMatch = $found | Where-Object { $_.Name -like "*$dClean*" }
                if ($dMatch) { $matchingFolder = $dMatch[0] } else { $matchingFolder = $found[0] }
            }
        }

        # Fehlenden Ordner eintragen
        if ($matchingFolder -and (-not $j.Ordner -or $j.Ordner -eq '')) {
            $j | Add-Member -NotePropertyName 'Ordner' -NotePropertyValue ('Berichte\' + $matchingFolder.Name) -Force
            Write-Host "  [$($dbFile.Name)] Ordner verknüpft: $($j.Ordner)" -ForegroundColor Cyan
        }

        $rfPath = if ($matchingFolder) { $matchingFolder.FullName } else { '' }
        
        # Daten aus Diagnosebericht.txt nachschlagen (Kerne / Threads)
        if ($rfPath) {
            $txtPath = Join-Path $rfPath 'Diagnosebericht.txt'
            if (Test-Path -LiteralPath $txtPath) {
                $txt = [System.IO.File]::ReadAllText($txtPath, [System.Text.Encoding]::UTF8)
                if ($null -eq $j.Hardware.Kerne -or $null -eq $j.Hardware.Threads -or $j.Hardware.Kerne -le 0) {
                    if ($txt -match '(?m)^\s*Kerne\s*/\s*Threads\s*:\s*(\d+)\s*/\s*(\d+)') {
                        $j.Hardware | Add-Member -NotePropertyName 'Kerne' -NotePropertyValue ([int]$matches[1]) -Force
                        $j.Hardware | Add-Member -NotePropertyName 'Threads' -NotePropertyValue ([int]$matches[2]) -Force
                        Write-Host "  [$($dbFile.Name)] Kerne/Threads ergänzt: $($j.Hardware.Kerne)/$($j.Hardware.Threads)" -ForegroundColor Cyan
                    } elseif ($txt -match '(\d+)\s*Kerne,\s*(\d+)\s*Threads') {
                        $j.Hardware | Add-Member -NotePropertyName 'Kerne' -NotePropertyValue ([int]$matches[1]) -Force
                        $j.Hardware | Add-Member -NotePropertyName 'Threads' -NotePropertyValue ([int]$matches[2]) -Force
                        Write-Host "  [$($dbFile.Name)] Kerne/Threads ergänzt: $($j.Hardware.Kerne)/$($j.Hardware.Threads)" -ForegroundColor Cyan
                    }
                }
            }

            # Daten aus Anhang.zip nachschlagen (Messreihen CPU-Package / GPU Leistung)
            $zipPath = Join-Path $rfPath 'Anhang.zip'
            $cpuWList = [System.Collections.Generic.List[double]]::new()
            $gpuWList = [System.Collections.Generic.List[double]]::new()
            $idleWList = [System.Collections.Generic.List[double]]::new()

            if (Test-Path -LiteralPath $zipPath) {
                try {
                    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
                    foreach ($csvName in 'Benchmark-Sensoren.csv', 'Lasttest-Verlauf.csv') {
                        $entry = $zip.GetEntry($csvName)
                        if ($entry) {
                            $sr = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
                            $hdr = $sr.ReadLine()
                            $cols = @($hdr -split ';' | ForEach-Object { $_.Trim('"') })
                            $idxCpuW = $cols.IndexOf('CpuW')
                            $idxGpuW = $cols.IndexOf('GpuW')
                            $idxLast = $cols.IndexOf('Last')
                            while (-not $sr.EndOfStream) {
                                $line = $sr.ReadLine()
                                $parts = @($line -split ';' | ForEach-Object { $_.Trim('"') -replace ',', '.' })
                                if ($idxCpuW -ge 0 -and $idxCpuW -lt $parts.Length) {
                                    $v = 0.0
                                    if ([double]::TryParse($parts[$idxCpuW], [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -gt 0) {
                                        $cpuWList.Add($v)
                                        if ($idxLast -ge 0 -and $idxLast -lt $parts.Length) {
                                            $lastVal = 0.0
                                            if ([double]::TryParse($parts[$idxLast], [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$lastVal) -and $lastVal -le 10) {
                                                $idleWList.Add($v)
                                            }
                                        }
                                    }
                                }
                                if ($idxGpuW -ge 0 -and $idxGpuW -lt $parts.Length) {
                                    $v = 0.0
                                    if ([double]::TryParse($parts[$idxGpuW], [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -gt 0) {
                                        $gpuWList.Add($v)
                                    }
                                }
                            }
                            $sr.Dispose()
                        }
                    }
                    $zip.Dispose()
                } catch { }
            }

            if ($cpuWList.Count -gt 0) {
                if (-not $j.Sensoren) { $j | Add-Member -NotePropertyName 'Sensoren' -NotePropertyValue (New-Object PSObject) -Force }
                if (-not $j.Sensoren.Last) { $j.Sensoren | Add-Member -NotePropertyName 'Last' -NotePropertyValue (New-Object PSObject) -Force }
                if (-not $j.Sensoren.Leerlauf) { $j.Sensoren | Add-Member -NotePropertyName 'Leerlauf' -NotePropertyValue (New-Object PSObject) -Force }

                $cMax = ($cpuWList | Measure-Object -Maximum).Maximum
                $j.Sensoren.Last | Add-Member -NotePropertyName 'CpuWMax' -NotePropertyValue $cMax -Force

                if ($idleWList.Count -gt 0) {
                    $cIdle = ($idleWList | Measure-Object -Minimum).Minimum
                    $j.Sensoren.Leerlauf | Add-Member -NotePropertyName 'CpuW' -NotePropertyValue $cIdle -Force
                }
            }

            if ($gpuWList.Count -gt 0) {
                if (-not $j.Sensoren) { $j | Add-Member -NotePropertyName 'Sensoren' -NotePropertyValue (New-Object PSObject) -Force }
                if (-not $j.Sensoren.Last) { $j.Sensoren | Add-Member -NotePropertyName 'Last' -NotePropertyValue (New-Object PSObject) -Force }
                $gMax = ($gpuWList | Measure-Object -Maximum).Maximum
                $j.Sensoren.Last | Add-Member -NotePropertyName 'GpuWMax' -NotePropertyValue $gMax -Force
            }
        }

        # Leistungsprofil für diesen Eintrag berechnen
        $prof = Get-SystemPowerProfile -Entry $j
        if ($prof -and $prof.Volllast -and $prof.Volllast.Verfuegbar) {
            $pDisp = $(if ($prof.Leerlauf -and $prof.Leerlauf.Verfuegbar) {
                '~{0:N0} W / ~{1:N0} W' -f $prof.Volllast.P_AC, $prof.Leerlauf.P_AC
            } else {
                '~{0:N0} W' -f $prof.Volllast.P_AC
            })
            $j.Hardware | Add-Member -NotePropertyName 'PowerDisplay' -NotePropertyValue $pDisp -Force
            $j.Hardware | Add-Member -NotePropertyName 'PowerLoad' -NotePropertyValue ([math]::Round($prof.Volllast.P_AC, 1)) -Force
            $j.Hardware | Add-Member -NotePropertyName 'PowerIdle' -NotePropertyValue $(if ($prof.Leerlauf -and $prof.Leerlauf.Verfuegbar) { [math]::Round($prof.Leerlauf.P_AC, 1) } else { $null }) -Force
            $j.Hardware | Add-Member -NotePropertyName 'PowerLoadTip' -NotePropertyValue $prof.Volllast.Aufschluesselung -Force

            if (-not $j.Werte) { $j | Add-Member -NotePropertyName 'Werte' -NotePropertyValue (New-Object PSObject) -Force }
            $j.Werte | Add-Member -NotePropertyName 'POWER_LOAD' -NotePropertyValue ([math]::Round($prof.Volllast.P_AC, 0)) -Force
            if ($prof.Leerlauf -and $prof.Leerlauf.Verfuegbar) {
                $j.Werte | Add-Member -NotePropertyName 'POWER_IDLE' -NotePropertyValue ([math]::Round($prof.Leerlauf.P_AC, 0)) -Force
            }
            if ($prof.Effizienz.CpuMT_PerWatt) {
                $j.Werte | Add-Member -NotePropertyName 'EFF_CPU' -NotePropertyValue $prof.Effizienz.CpuMT_PerWatt -Force
            }
            if ($prof.Effizienz.Gpu_PerWatt) {
                $j.Werte | Add-Member -NotePropertyName 'EFF_GPU' -NotePropertyValue $prof.Effizienz.Gpu_PerWatt -Force
            }
            Write-Host "  [$($dbFile.Name)] Leistungsprofil: $pDisp" -ForegroundColor Green
        } else {
            $j.Hardware | Add-Member -NotePropertyName 'PowerDisplay' -NotePropertyValue 'n/v (kein Leistungssensor)' -Force
            Write-Host "  [$($dbFile.Name)] Kein Leistungssensor (n/v)" -ForegroundColor DarkGray
        }

        # Aktualisierten Datenbankeintrag speichern
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($dbFile.FullName, ($j | ConvertTo-Json -Depth 10), $utf8Bom)
    } catch {
        Write-Warning "  Fehler bei $($dbFile.Name): $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------
# SCHRITT 3: HTML-Berichte aktualisieren (neue Kacheln, Effizienz, Rechner, CSS, JS)
# -------------------------------------------------------------------------------------
Write-Host "`n[3/4] HTML-Berichte modernisieren (Kopfzeile, Profilkarten, Stromrechner, Filter, CSS) ..." -ForegroundColor Yellow

$css = Get-ReportCss
$repJs = Get-ReportJs

function New-CustomProfileCardsHtml($CpuPct, $GpuPct, $RamPct, $DskPct) {
    $cSt = if ($null -ne $CpuPct) { [double]$CpuPct } else { $null }
    $cMt = if ($null -ne $CpuPct) { [double]$CpuPct } else { $null }
    $gpu = if ($null -ne $GpuPct) { [double]$GpuPct } else { $null }
    $ram = if ($null -ne $RamPct) { [double]$RamPct } else { $null }
    $dsk = if ($null -ne $DskPct) { [double]$DskPct } else { $null }

    $hasCount = 0
    foreach ($v in $cMt, $gpu, $ram, $dsk) { if ($null -ne $v -and $v -gt 0) { $hasCount++ } }
    if ($hasCount -lt 2) { return '' }

    $profiles = @(
        @{ Name = 'Gaming';       Icon = [char]0xD83C + [char]0xDFAE; W = @{ 'CPU_ST' = 1.0; 'CPU_MT' = 0.5; 'GPU' = 3.0; 'RAM' = 0.5; 'DISK' = 0.5 } }
        @{ Name = 'Büro/Desktop'; Icon = [char]0xD83D + [char]0xDCBC; W = @{ 'CPU_ST' = 2.0; 'CPU_MT' = 1.0; 'GPU' = 0.5; 'RAM' = 1.0; 'DISK' = 2.0 } }
        @{ Name = 'Workstation';  Icon = [char]0x2699 + [char]0xFE0F; W = @{ 'CPU_ST' = 0.5; 'CPU_MT' = 3.0; 'GPU' = 1.0; 'RAM' = 2.0; 'DISK' = 1.0 } }
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<div class="ov profile-grid">')
    foreach ($p in $profiles) {
        $vals = [System.Collections.Generic.List[double]]::new()
        $weights = [System.Collections.Generic.List[double]]::new()

        if ($null -ne $cSt -and $cSt -gt 0) { $vals.Add($cSt); $weights.Add($p.W['CPU_ST']) }
        if ($null -ne $cMt -and $cMt -gt 0) { $vals.Add($cMt); $weights.Add($p.W['CPU_MT']) }
        if ($null -ne $gpu -and $gpu -gt 0) { $vals.Add($gpu); $weights.Add($p.W['GPU']) }
        if ($null -ne $ram -and $ram -gt 0) { $vals.Add($ram); $weights.Add($p.W['RAM']) }
        if ($null -ne $dsk -and $dsk -gt 0) { $vals.Add($dsk); $weights.Add($p.W['DISK']) }

        if (-not $vals.Count) { continue }
        $s = 0.0; $ws = 0.0
        for ($i = 0; $i -lt $vals.Count; $i++) {
            $s += $weights[$i] * [math]::Log($vals[$i])
            $ws += $weights[$i]
        }
        $score = [int][math]::Round([math]::Exp($s / $ws), 0)
        $word = if (Get-Command Get-BenchRatingWord -ErrorAction SilentlyContinue) { Get-BenchRatingWord $score } else { 'Gut' }
        $bar = if (Get-Command Get-RefBar -ErrorAction SilentlyContinue) { Get-RefBar $score 'ok' } else { '' }

        [void]$sb.Append(('<div class="tile profile"><h4>{0} {1}</h4><div class="big">{2}<small> %</small></div><div class="pword">{3}</div>{4}</div>' -f
            $p.Icon, (ConvertTo-HtmlText $p.Name), $score, (ConvertTo-HtmlText $word), $bar))
    }
    [void]$sb.Append('</div>')
    return $sb.ToString()
}

foreach ($rf in $reportFolders) {
    $htmlPath = Join-Path $rf.FullName 'Diagnosebericht.html'
    if (-not (Test-Path -LiteralPath $htmlPath)) { continue }

    try {
        $html = [System.IO.File]::ReadAllText($htmlPath, [System.Text.Encoding]::UTF8)

        # Passenden Datenbankeintrag finden
        $dbMatch = $dbFiles | Where-Object {
            $fn = $_.FullName
            $dj = [System.IO.File]::ReadAllText($fn, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            ($dj.Ordner -and ($dj.Ordner -like "*$($rf.Name)*")) -or ($rf.Name -like "*$($dj.Computer)*")
        } | Select-Object -First 1

        $entry = $null
        if ($dbMatch) {
            $entry = [System.IO.File]::ReadAllText($dbMatch.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        }

        # Falls kein DB-Eintrag vorhanden ist, Basisdaten aus dem HTML extrahieren
        if (-not $entry) {
            $compName = if ($html -match '<dt>Computer</dt><dd>(.*?)</dd>') { $matches[1] } else { $rf.Name }
            $cpuName = if ($html -match '<dt>Prozessor</dt><dd>(.*?)</dd>') { $matches[1] } else { '' }
            $ramName = if ($html -match '<dt>Arbeitsspeicher</dt><dd>(.*?)</dd>') { $matches[1] } else { '' }
            $gpuName = if ($html -match '<dt>Grafik</dt><dd>(.*?)</dd>') { $matches[1] } else { '' }
            $entry = [pscustomobject]@{
                Computer = $compName
                Hardware = [pscustomobject]@{ CPU = $cpuName; RAM = $ramName; GPU = $gpuName }
                Sensoren = [pscustomobject]@{}
            }
        }

        $prof = Get-SystemPowerProfile -Entry $entry

        # 1. CSS aktualisieren
        $html = [regex]::Replace($html, '(?s)<style>.*?</style>', ('<style>' + $css + '</style>'))

        # 2. Navigation aktualisieren/sicherstellen
        $compParam = [uri]::EscapeDataString($(if ($entry -and $entry.Computer) { $entry.Computer } else { $rf.Name }))
        $targetNav = ('<nav class="report-nav"><button type="button" class="tab-btn active" onclick="switchSection(''all'', this)">Alle Abschnitte</button><button type="button" class="tab-btn" onclick="switchSection(''system'', this)">Systemübersicht</button><button type="button" class="tab-btn" onclick="switchSection(''benchmark'', this)">Benchmark</button><button type="button" class="tab-btn" onclick="switchSection(''befunde'', this)">Befunde</button><button type="button" class="tab-btn" onclick="switchSection(''hardware'', this)">Hardware</button><button type="button" class="tab-btn" onclick="switchSection(''sensoren'', this)">Sensoren</button><a href="../Dashboard.html?system={0}" class="tab-btn btn-dash" target="_blank" title="Vergleichsdashboard für diesen PC im neuen Tab öffnen">📊 Vergleichsdashboard</a></nav>' -f $compParam)
        if ($html -match '(?s)<nav class="report-nav">.*?</nav>') {
            $html = [regex]::Replace($html, '(?s)<nav class="report-nav">.*?</nav>', $targetNav)
        } else {
            $html = [regex]::Replace($html, '(?s)(</header>\s*)', ('${1}' + $targetNav))
        }

        # 3. data-section auf allen Abschnitten sicherstellen
        $html = [regex]::Replace($html, '(?s)<section class="box"(?! data-section)(.*?>\s*<h2>(.*?)</h2>)', {
            param($m)
            $h2 = $m.Groups[2].Value
            $sec = 'system'
            if ($h2 -match 'System|Akku|Absturzabbilder|Crash Dumps|Hardware|Optimierung') { $sec = 'hardware' }
            elseif ($h2 -match 'Befunde|Tests') { $sec = 'befunde' }
            elseif ($h2 -match 'Leistung|Benchmark|Vergleich') { $sec = 'benchmark' }
            elseif ($h2 -match 'Sensoren|Lasttest|Energie') { $sec = 'sensoren' }
            elseif ($h2 -match 'Details|Zeitbedarf|Zuverlässigkeit') { $sec = 'system' }
            return ('<section class="box" data-section="' + $sec + '"' + $m.Groups[1].Value)
        })
        $html = [regex]::Replace($html, '<section class="box stab\b([^"]*)"(?! data-section)', '<section class="box stab$1" data-section="system"')

        # 4. Befunde-Filterleiste und Tabelle modernisieren
        if ($html -match 'data-section="befunde"><h2>Befunde</h2>' -and $html -notmatch 'class="filter-bar"') {
            $nK = 0; $nW = 0; $nI = 0
            if ($entry -and $entry.Befunde) {
                $nK = [int]$entry.Befunde.Kritisch; $nW = [int]$entry.Befunde.Warnungen; $nI = [int]$entry.Befunde.Hinweise
            } else {
                if ($html -match 'class="card crit"><b>(\d+)</b>') { $nK = [int]$matches[1] }
                if ($html -match 'class="card warn"><b>(\d+)</b>') { $nW = [int]$matches[1] }
                if ($html -match 'class="card info"><b>(\d+)</b>') { $nI = [int]$matches[1] }
            }
            $totBefunde = $nK + $nW + $nI
            $fBar = ('<div class="filter-bar"><div class="filter-chips"><button type="button" class="fchip active" data-level="all" onclick="setLevelFilter(''all'', this)">Alle (<span id="cntAll">{0}</span>)</button><button type="button" class="fchip chip-crit" data-level="KRITISCH" onclick="setLevelFilter(''KRITISCH'', this)">Kritisch (<span id="cntCrit">{1}</span>)</button><button type="button" class="fchip chip-warn" data-level="WARNUNG" onclick="setLevelFilter(''WARNUNG'', this)">Warnung (<span id="cntWarn">{2}</span>)</button><button type="button" class="fchip chip-info" data-level="INFO" onclick="setLevelFilter(''INFO'', this)">Hinweis (<span id="cntInfo">{3}</span>)</button></div><span id="befundCount" class="filter-count"></span></div>' -f $totBefunde, $nK, $nW, $nI)
            $html = [regex]::Replace($html, '(<h2>Befunde</h2>\s*)(<table>)', ('$1' + $fBar + '<table id="befundeTable">'))
            $html = [regex]::Replace($html, '(?s)<tr><td><span class="badge (crit|warn|info)">(KRITISCH|WARNUNG|INFO)</span></td>', '<tr><td data-level="$2"><span class="badge $1">$2</span></td>')
        }

        # 5. Benchmark Profile-Cards (Gaming, Büro, Workstation)
        if ($html -notmatch 'class="tile profile"' -and $html -match '<h2>Leistung \(Benchmark\)</h2>') {
            $cpuPct = $null; $ramPct = $null; $gpuPct = $null; $dskPct = $null
            if ($html -match 'href="#bg-CPU".*?<div class="big">(\d+)<small>\s*%') { $cpuPct = [double]$matches[1] }
            if ($html -match 'href="#bg-RAM".*?<div class="big">(\d+)<small>\s*%') { $ramPct = [double]$matches[1] }
            if ($html -match 'href="#bg-GPU".*?<div class="big">(\d+)<small>\s*%') { $gpuPct = [double]$matches[1] }
            if ($html -match 'href="#bg-Laufwerke".*?<div class="big">(\d+)<small>\s*%') { $dskPct = [double]$matches[1] }

            if ($null -ne $cpuPct -or $null -ne $gpuPct) {
                $pCards = New-CustomProfileCardsHtml -CpuPct $cpuPct -GpuPct $gpuPct -RamPct $ramPct -DskPct $dskPct
                if ($pCards) {
                    $html = [regex]::Replace($html, '(?s)(<h2>Leistung \(Benchmark\)</h2>.*?</div>\s*)(<div class="ov">)', ('${1}' + $pCards + '${2}'))
                }
            }
        }

        # 6. Neue KPI-Karten in die Kopfzeile
        $nK = 0; $nW = 0; $nI = 0
        if ($entry -and $entry.Befunde) {
            $nK = [int]$entry.Befunde.Kritisch; $nW = [int]$entry.Befunde.Warnungen; $nI = [int]$entry.Befunde.Hinweise
        } else {
            if ($html -match 'class="card crit"><b>(\d+)</b>') { $nK = [int]$matches[1] }
            if ($html -match 'class="card warn"><b>(\d+)</b>') { $nW = [int]$matches[1] }
            if ($html -match 'class="card info"><b>(\d+)</b>') { $nI = [int]$matches[1] }
        }
        $totBefunde = $nK + $nW + $nI
        $befCls = if ($nK -gt 0) { 'crit' } elseif ($nW -gt 0) { 'warn' } elseif ($nI -gt 0) { 'info' } else { 'ok' }
        $befSub = if ($totBefunde -eq 0) { 'Keine Auffälligkeiten' } else { '{0} kritisch &middot; {1} Warn. &middot; {2} Hinw.' -f $nK, $nW, $nI }
        $befTip = if ($totBefunde -eq 0) { 'Keine Auffälligkeiten gefunden' } else { '{0} kritische Befunde, {1} Warnungen, {2} Hinweise' -f $nK, $nW, $nI }
        $befCard = ('<div class="card {0} hit" data-tip="{1}"><b>{2}</b><span>Befunde ({3})</span></div>' -f $befCls, (ConvertTo-HtmlText $befTip), $totBefunde, $befSub)

        $benchCard = ''
        $ovPct = $null
        if ($html -match 'class="card bench"><b>(\d+)\s*%</b>') {
            $ovPct = [int]$matches[1]
        } elseif ($entry -and $entry.Score -and [double]$entry.Score -gt 0) {
            $ovPct = [int][math]::Round([double]$entry.Score)
        }
        if ($ovPct) {
            $benchCard = ('<div class="card bench"><b>{0} %</b><span>Gesamtleistung (Referenz)</span></div>' -f $ovPct)
        }

        $mtCard = ''
        $mtVal = $null
        if ($entry -and $entry.Werte) {
            $wMt = if ($entry.Werte -is [System.Collections.IDictionary]) { $entry.Werte['CPU|MT'] } else { $entry.Werte.'CPU|MT' }
            if ($null -ne $wMt -and [double]$wMt -gt 0) { $mtVal = [double]$wMt }
        }
        if ($null -eq $mtVal -and $html -match 'Mehrkern\s+([\d.,]+)\s+Punkte') {
            $mtVal = [double]($matches[1] -replace '\.', '' -replace ',', '.')
        }
        if ($null -ne $mtVal -and $mtVal -gt 0) {
            $mtCard = ('<div class="card metric cpu"><b>{0:N0}</b><span>Multicore-Score (CPU)</span></div>' -f $mtVal)
        }

        $fpsCard = ''
        $fpsVal = $null
        if ($entry -and $entry.Werte) {
            $wGpu = if ($entry.Werte -is [System.Collections.IDictionary]) { $entry.Werte['GPU|REND'] } else { $entry.Werte.'GPU|REND' }
            if ($null -ne $wGpu -and [double]$wGpu -gt 0) { $fpsVal = [double]$wGpu }
        }
        if ($null -eq $fpsVal -and $entry -and $entry.Rendertest) {
            $rFps = @($entry.Rendertest | Where-Object { [double]$_.Fps -gt 0 } | ForEach-Object { [double]$_.Fps })
            if ($rFps.Count) { $fpsVal = $rFps[0] }
        }
        if ($null -eq $fpsVal -and $entry -and $entry.Lasttest -and "$($entry.Lasttest)" -match '(\d+(?:[.,]\d+)?)\s*Bilder/s') {
            $fpsVal = [double]($matches[1] -replace ',', '.')
        }
        if ($null -eq $fpsVal -and $html -match '(\d+(?:[.,]\d+)?)\s*(?:FPS|Bilder/s)') {
            $fpsVal = [double]($matches[1] -replace ',', '.')
        }
        if ($null -ne $fpsVal -and $fpsVal -gt 0) {
            $fpsCard = ('<div class="card metric gpu"><b>{0:N0} FPS</b><span>Grafik (Rendertest)</span></div>' -f $fpsVal)
        }

        $ssdCard = ''
        $maxSrMb = $null
        if ($entry -and $entry.Laufwerke) {
            $srList = @($entry.Laufwerke | ForEach-Object { [double]$_.SR } | Where-Object { $_ -gt 0 })
            if ($srList.Count) { $maxSrMb = ($srList | Measure-Object -Maximum).Maximum }
        }
        if ($null -eq $maxSrMb -and $html -match '<table class="disks">.*?<td class="num r">(\d+)</td>') {
            $maxSrMb = [double]$matches[1]
        }
        if ($null -eq $maxSrMb -and $html -match '(\d+)\s*MB/s') {
            $maxSrMb = [double]$matches[1]
        }
        if ($null -ne $maxSrMb -and $maxSrMb -gt 0) {
            $ssdGb = [math]::Round($maxSrMb / 1000.0, 1)
            $ssdCard = ('<div class="card metric disk"><b>{0:N1} GB/s</b><span>Schnellste SSD (Lesen)</span></div>' -f $ssdGb)
        }

        $effCard = ''
        if ($prof) {
            if ($prof.Effizienz -and $prof.Effizienz.System_PerWatt -and [double]$prof.Effizienz.System_PerWatt -gt 0) {
                $subTxt = if ($prof.Volllast -and $prof.Volllast.Verfuegbar) { '~{0:N0} W Volllast' -f $prof.Volllast.P_AC } else { 'Gesamteffizienz' }
                $effCard = ('<div class="card eff hit" data-tip="{0}"><b>{1:N1} <small>Pkt/100W</small></b><span>Effizienz ({2})</span></div>' -f `
                    (ConvertTo-HtmlText $prof.Volllast.Aufschluesselung), [double]$prof.Effizienz.System_PerWatt, (ConvertTo-HtmlText $subTxt))
            } elseif ($prof.Effizienz -and $prof.Effizienz.CpuMT_PerWatt -and [double]$prof.Effizienz.CpuMT_PerWatt -gt 0) {
                $subTxt = if ($prof.Volllast -and $prof.Volllast.Verfuegbar) { '~{0:N0} W Volllast' -f $prof.Volllast.P_AC } else { 'CPU-Effizienz' }
                $effCard = ('<div class="card eff hit" data-tip="{0}"><b>{1:N0} <small>Pkt/W</small></b><span>CPU-Effizienz ({2})</span></div>' -f `
                    (ConvertTo-HtmlText $prof.Volllast.Aufschluesselung), [double]$prof.Effizienz.CpuMT_PerWatt, (ConvertTo-HtmlText $subTxt))
            } elseif ($prof.Volllast -and $prof.Volllast.Verfuegbar) {
                $subTxt = if ($prof.Leerlauf -and $prof.Leerlauf.Verfuegbar) { '~{0:N0} W Leerlauf' -f $prof.Leerlauf.P_AC } else { 'Volllast geschätzt' }
                $effCard = ('<div class="card pwr hit" data-tip="{0}"><b>~{1:N0} W</b><span>Verbrauch Last ({2})</span></div>' -f `
                    (ConvertTo-HtmlText $prof.Volllast.Aufschluesselung), [math]::Round($prof.Volllast.P_AC), (ConvertTo-HtmlText $subTxt))
            }
        }

        $stCard = ''
        if ($html -match '(?s)(<div class="card st\b[^"]*"[^>]*>.*?</div>)') {
            $stCard = $matches[1]
        }

        $newCards = ('<section class="cards" data-section="system">{0}{1}{2}{3}{4}{5}{6}</section>' -f `
            $befCard, $benchCard, $mtCard, $fpsCard, $ssdCard, $effCard, $stCard)
        $html = [regex]::Replace($html, '(?s)<section class="cards"[^>]*>.*?</section>', $newCards)

        # 7. System-Fakten (Leerlauf / Volllast) in die Tabelle einfügen
        $factsHtml = ''
        if ($prof -and $prof.Leerlauf -and $prof.Leerlauf.Verfuegbar) {
            $factsHtml += ('<dt>Geschätzter Gesamtsystemverbrauch (Leerlauf)</dt><dd>{0} an der Steckdose (intern {1:N0} W)</dd>' -f $prof.Leerlauf.Text, $prof.Leerlauf.P_DC)
        }
        if ($prof -and $prof.Volllast -and $prof.Volllast.Verfuegbar) {
            $factsHtml += ('<dt>Geschätzter Gesamtsystemverbrauch (Volllast)</dt><dd>{0} an der Steckdose (intern {1:N0} W)</dd>' -f $prof.Volllast.Text, $prof.Volllast.P_DC)
        }

        if ($factsHtml) {
            if ($html -match 'Geschätzter Gesamtsystemverbrauch') {
                $html = [regex]::Replace($html, '(?s)<dt>Geschätzter Gesamtsystemverbrauch \(Leerlauf\)</dt><dd>.*?</dd>', '')
                $html = [regex]::Replace($html, '(?s)<dt>Geschätzter Gesamtsystemverbrauch \(Volllast\)</dt><dd>.*?</dd>', '')
            }
            $html = [regex]::Replace($html, '(?s)(<section class="box"[^>]*data-section="hardware"><h2>System</h2><dl>.*?)(</dl>)', ('${1}' + $factsHtml + '${2}'))
        }

        # 8. PowerEfficiencyHtml (Kacheln, Effizienz, Rechner) in den Sensoren-/Lasttest-Abschnitt
        if ($prof -and $prof.Volllast -and $prof.Volllast.Verfuegbar) {
            $effHtml = New-PowerEfficiencyHtml -Profile $prof
            if ($effHtml) {
                if ($html -match 'class="pwr-box"') {
                    $html = [regex]::Replace($html, '(?s)<div class="pwr-box".*?</div>\s*</div>\s*(?=</section>|$)', $effHtml)
                } else {
                    if ($html -match 'data-section="sensoren"') {
                        $mS = [regex]::Matches($html, '(?s)<section class="box"[^>]*data-section="sensoren">.*?</section>')
                        if ($mS.Count -gt 0) {
                            $lastS = $mS[$mS.Count - 1].Value
                            $newS = [regex]::Replace($lastS, '(?s)(.*?)(</section>)', ('${1}' + $effHtml + '${2}'))
                            $html = $html.Replace($lastS, $newS)
                        }
                    } else {
                        $box = ('<section class="box" data-section="sensoren"><h2>Energie &amp; Effizienz</h2>' + $effHtml + '</section>')
                        $html = [regex]::Replace($html, '(?s)(<section class="box"[^>]*data-section="hardware">.*?</section>)', ('${1}' + $box))
                    }
                }
            }
        }

        # 9. JavaScript aktualisieren
        if ($html -match '(?s)<script>.*?</script>') {
            $html = [regex]::Replace($html, '(?s)<script>.*?</script>\s*(?=<footer>|$)', $repJs)
        } else {
            $html = [regex]::Replace($html, '(?s)(?=<footer>|$)', $repJs)
        }

        # Speichern mit UTF-8 BOM
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($htmlPath, ($html -replace "`r?`n", "`r`n"), $utf8Bom)
        Write-Host "  -> Bericht modernisiert: $($rf.Name)\Diagnosebericht.html" -ForegroundColor Green
    } catch {
        Write-Warning "  Bericht $($rf.Name) konnte nicht aktualisiert werden: $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------------------------------
# SCHRITT 4: Veraltete Dateien ins Archiv verschieben
# -------------------------------------------------------------------------------------
Write-Host "`n[4/4] Veraltete Dateien ins Archiv verschieben ..." -ForegroundColor Yellow

$archAlt = Join-Path $archDir 'Berichte_Altdaten'
if (-not (Test-Path -LiteralPath $archAlt)) {
    New-Item -ItemType Directory -Path $archAlt -Force | Out-Null
}

$movedCount = 0
foreach ($rf in $reportFolders) {
    # 1. KI-Kurzfassung.txt verschieben (in v3.61 entfernt)
    $kurz = Join-Path $rf.FullName 'KI-Kurzfassung.txt'
    if (Test-Path -LiteralPath $kurz) {
        $destDir = Join-Path $archAlt $rf.Name
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Move-Item -LiteralPath $kurz -Destination (Join-Path $destDir 'KI-Kurzfassung.txt') -Force
        Write-Host "  -> Verschoben: $($rf.Name)\KI-Kurzfassung.txt -> Archiv" -ForegroundColor Gray
        $movedCount++
    }

    # 2. Lose Logs / CSVs verschieben, wenn Anhang.zip existiert und sie bereits enthält
    $zipPath = Join-Path $rf.FullName 'Anhang.zip'
    if (Test-Path -LiteralPath $zipPath) {
        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
            $zipEntries = @($zip.Entries | ForEach-Object { $_.Name })
            $zip.Dispose()

            $looseFiles = @(Get-ChildItem -LiteralPath $rf.FullName -File | Where-Object {
                $_.Name -notin 'Diagnosebericht.html', 'Diagnosebericht.txt', 'Anhang.zip' -and $_.Name -notlike 'KI-Analyse*'
            })

            foreach ($lf in $looseFiles) {
                if ($lf.Name -in $zipEntries) {
                    $destDir = Join-Path $archAlt $rf.Name
                    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                    Move-Item -LiteralPath $lf.FullName -Destination (Join-Path $destDir $lf.Name) -Force
                    Write-Host "  -> Verschoben (bereits in ZIP): $($rf.Name)\$($lf.Name) -> Archiv" -ForegroundColor Gray
                    $movedCount++
                }
            }
        } catch { }
    }
}

# 3. Alte statische Vergleichs-HTML-Dateien verschieben
$cmpFolder = Join-Path $repDir 'Vergleiche'
if (Test-Path -LiteralPath $cmpFolder) {
    $cmpFiles = @(Get-ChildItem -LiteralPath $cmpFolder -File)
    if ($cmpFiles.Count -gt 0) {
        $destCmp = Join-Path $archDir 'Vergleiche_Alt'
        if (-not (Test-Path -LiteralPath $destCmp)) { New-Item -ItemType Directory -Path $destCmp -Force | Out-Null }
        foreach ($cf in $cmpFiles) {
            Move-Item -LiteralPath $cf.FullName -Destination (Join-Path $destCmp $cf.Name) -Force
            Write-Host "  -> Verschoben: Vergleiche\$($cf.Name) -> Archiv" -ForegroundColor Gray
            $movedCount++
        }
    }
}

Write-Host "  $movedCount veraltete/redundante Dateien sicher ins Archiv überführt." -ForegroundColor Green

# -------------------------------------------------------------------------------------
# ABSCHLUSS: Multi-System Dashboard frisch exportieren
# -------------------------------------------------------------------------------------
Write-Host "`nMulti-System Dashboard (Dashboard.html) neu generieren ..." -ForegroundColor Yellow
try {
    $dashPath = Export-BenchDashboardHtml -DatabaseDir $dbDir -ReportDir $repDir
    Write-Host "Dashboard erfolgreich erzeugt: $dashPath" -ForegroundColor Green
} catch {
    Write-Warning "Dashboard-Export fehlgeschlagen: $($_.Exception.Message)"
}

Write-Host "`nAktualisierung erfolgreich abgeschlossen!" -ForegroundColor Green
