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
# SCHRITT 3: HTML-Berichte aktualisieren (neue Kacheln, Effizienz, Rechner, CSS, JS)
# -------------------------------------------------------------------------------------
Write-Host "`n[3/4] HTML-Berichte aktualisieren ..." -ForegroundColor Yellow

$css = Get-ReportCss

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

        $prof = Get-SystemPowerProfile -Entry $entry

        # 1. CSS aktualisieren
        $html = [regex]::Replace($html, '(?s)<style>.*?</style>', ('<style>' + $css + '</style>'))

        # 2. Power-Card in die Kopf-Kacheln einbinden
        $pwrCard = ''
        if ($prof -and $prof.Volllast -and $prof.Volllast.Verfuegbar) {
            $subTxt = $(if ($prof.Leerlauf -and $prof.Leerlauf.Verfuegbar) { '~{0:N0} W Leerlauf' -f $prof.Leerlauf.P_AC } else { 'Volllast geschätzt' })
            $pwrCard = ('<div class="card pwr hit" data-tip="{0}"><b>~{1:N0} W</b><span>Verbrauch Last ({2})</span></div>' -f `
                (ConvertTo-HtmlText $prof.Volllast.Aufschluesselung), [math]::Round($prof.Volllast.P_AC), (ConvertTo-HtmlText $subTxt))
        }

        if ($pwrCard) {
            if ($html -match 'class="card pwr') {
                $html = [regex]::Replace($html, '(?s)<div class="card pwr[^>]*>.*?</div>', $pwrCard)
            } else {
                $html = [regex]::Replace($html, '(?s)(<section class="cards"[^>]*>.*?)(</section>)', ('${1}' + $pwrCard + '${2}'))
            }
        }

        # 3. System-Fakten (Leerlauf / Volllast) in die Tabelle einfügen
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
            $html = [regex]::Replace($html, '(?s)(<section class="box" data-section="hardware"><h2>System</h2><dl>.*?)(</dl>)', ('${1}' + $factsHtml + '${2}'))
        }

        # 4. PowerEfficiencyHtml (Kacheln, Effizienz, Rechner) in den Sensoren-/Lasttest-Abschnitt
        if ($prof -and $prof.Volllast -and $prof.Volllast.Verfuegbar) {
            $effHtml = New-PowerEfficiencyHtml -Profile $prof
            if ($effHtml) {
                if ($html -match 'class="pwr-box"') {
                    $html = [regex]::Replace($html, '(?s)<div class="pwr-box".*?</div>\s*(?=</section>|$)', $effHtml)
                } else {
                    if ($html -match 'data-section="sensoren"') {
                        # Am Ende des letzten Sensoren/Lasttest-Abschnitts anfügen
                        $mS = [regex]::Matches($html, '(?s)<section class="box" data-section="sensoren">.*?</section>')
                        if ($mS.Count -gt 0) {
                            $lastS = $mS[$mS.Count - 1].Value
                            $newS = [regex]::Replace($lastS, '(?s)(.*?)(</section>)', ('${1}' + $effHtml + '${2}'))
                            $html = $html.Replace($lastS, $newS)
                        }
                    } else {
                        # Box anfügen nach Hardware
                        $box = ('<section class="box" data-section="sensoren"><h2>Energie &amp; Effizienz</h2>' + $effHtml + '</section>')
                        $html = [regex]::Replace($html, '(?s)(<section class="box" data-section="hardware">.*?</section>)', ('${1}' + $box))
                    }
                }
            }
        }

        # 5. Link zum Dashboard überprüfen & sicherstellen
        $compParam = [uri]::EscapeDataString($(if ($entry) { $entry.Computer } else { $rf.Name }))
        if ($html -notmatch 'btn-dash') {
            $dashLink = ('<a href="../Dashboard.html?system={0}" class="tab-btn btn-dash" target="_blank" title="Vergleichsdashboard für diesen PC im neuen Tab öffnen">📊 Vergleichsdashboard</a>' -f $compParam)
            $html = [regex]::Replace($html, '(?s)(<nav class="report-nav">.*?)(</nav>)', ('${1}' + $dashLink + '${2}'))
        }

        # Speichern mit UTF-8 BOM
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($htmlPath, ($html -replace "`r?`n", "`r`n"), $utf8Bom)
        Write-Host "  -> Bericht aktualisiert: $($rf.Name)\Diagnosebericht.html" -ForegroundColor Green
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
