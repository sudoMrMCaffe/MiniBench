# =====================================================================================
#             LEOS MINIBENCH: BENCHMARK- & DIAGNOSE-DASHBOARD (HTML5/VANILLA-JS)
# =====================================================================================
# Wiederverwendbare Daten- und HTML-Bausteine für das interaktive Benchmark- und
# Diagnose-Dashboard (Fluent 2 / Wintoys-Look, 100 % offline-fähig).

function Export-BenchDashboardData {
    [CmdletBinding()]
    param(
        [string]$DatabaseDir = '',
        [string]$ReportDir = '',
        [string[]]$SystemPaths = @(),
        [switch]$IncludeReferences = $true,
        [string]$OutputPath = '',
        [switch]$AsJson
    )

    # 1. Datenbank- und Berichtsverzeichnisse ermitteln
    $dbDir = $DatabaseDir
    if (-not $dbDir -or -not (Test-Path -LiteralPath $dbDir)) {
        if ($script:DbDir -and (Test-Path -LiteralPath $script:DbDir)) { $dbDir = $script:DbDir }
        elseif (Test-Path -LiteralPath 'Minibench-Daten\Datenbank') { $dbDir = (Convert-Path 'Minibench-Daten\Datenbank') }
        elseif (Test-Path -LiteralPath 'Aktueller Build\Minibench-Daten\Datenbank') { $dbDir = (Convert-Path 'Aktueller Build\Minibench-Daten\Datenbank') }
        elseif (Test-Path -LiteralPath (Join-Path (Get-Location) 'Minibench-Daten\Datenbank')) { $dbDir = (Join-Path (Get-Location) 'Minibench-Daten\Datenbank') }
        else { $dbDir = '' }
    }

    $repDir = $ReportDir
    if (-not $repDir -or -not (Test-Path -LiteralPath $repDir)) {
        if ($script:ReportDir -and (Test-Path -LiteralPath $script:ReportDir)) { $repDir = $script:ReportDir }
        elseif (Test-Path -LiteralPath 'Minibench-Daten\Berichte') { $repDir = (Convert-Path 'Minibench-Daten\Berichte') }
        elseif (Test-Path -LiteralPath 'Aktueller Build\Minibench-Daten\Berichte') { $repDir = (Convert-Path 'Aktueller Build\Minibench-Daten\Berichte') }
        elseif (Test-Path -LiteralPath (Join-Path (Get-Location) 'Minibench-Daten\Berichte')) { $repDir = (Join-Path (Get-Location) 'Minibench-Daten\Berichte') }
        else { $repDir = '' }
    }

    # Lokale Hilfsfunktion: Sicheres Lesen von CSV-Zeitreihen
    $extractCsvSeries = {
        param([string]$ReportFolder, [string]$LeafFolder)
        $lines = @()
        $candidates = [System.Collections.Generic.List[string]]::new()
        if ($LeafFolder) {
            if ([System.IO.Path]::IsPathRooted($LeafFolder)) {
                $candidates.Add($LeafFolder)
            } elseif ($repDir) {
                $candidates.Add((Join-Path (Split-Path $repDir -Parent) $LeafFolder))
                $candidates.Add((Join-Path $repDir (Split-Path $LeafFolder -Leaf)))
            }
        }
        foreach ($cand in $candidates) {
            if (-not (Test-Path -LiteralPath $cand)) { continue }
            $rawCsv = Join-Path $cand 'Lasttest-Verlauf.csv'
            $benchCsv = Join-Path $cand 'Benchmark-Sensoren.csv'
            $zipPath = Join-Path $cand 'Anhang.zip'
            if (Test-Path -LiteralPath $rawCsv) {
                try { $lines = @([System.IO.File]::ReadAllLines($rawCsv, [System.Text.Encoding]::UTF8)); if ($lines.Count -gt 1) { break } } catch { }
            }
            if (Test-Path -LiteralPath $zipPath) {
                try {
                    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
                    $entry = $zip.GetEntry('Lasttest-Verlauf.csv')
                    if (-not $entry) { $entry = $zip.GetEntry('Benchmark-Sensoren.csv') }
                    if ($entry) {
                        $sr = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
                        $zipLines = [System.Collections.Generic.List[string]]::new()
                        while (-not $sr.EndOfStream) { $zipLines.Add($sr.ReadLine()) }
                        $sr.Dispose()
                        if ($zipLines.Count -gt 1) { $lines = @($zipLines); $zip.Dispose(); break }
                    }
                    $zip.Dispose()
                } catch { }
            }
            if (Test-Path -LiteralPath $benchCsv) {
                try { $lines = @([System.IO.File]::ReadAllLines($benchCsv, [System.Text.Encoding]::UTF8)); if ($lines.Count -gt 1) { break } } catch { }
            }
        }
        return $lines
    }

    # Hilfsfunktion: Konvertierung eines JSON-Objekts in die Dashboard-Systemstruktur
    $parseSystemEntry = {
        param([object]$j, [bool]$isRef, [string]$sourceFile = '')

        if (-not $j) { return $null }

        $comp = $(if ($j.Computer) { [string]$j.Computer } else { 'System' })
        $name = $(if ($j.Name) { [string]$j.Name } else { $comp })
        $datum = $(if ($j.Datum) { [string]$j.Datum } else { '' })
        $id = $(if ($isRef) { 'REF_' + ([System.IO.Path]::GetFileNameWithoutExtension($sourceFile) -replace '\W', '_') } else { ($comp + '_' + ($datum -replace '\W', '')) })
        if (-not $id) { $id = [guid]::NewGuid().ToString('N').Substring(0, 8) }
        $id = [string]$id

        # Werte-Tabelle
        $werte = @{}
        if ($j.Werte) {
            foreach ($p in $j.Werte.PSObject.Properties) {
                $val = 0.0
                if ([double]::TryParse("$($p.Value)", [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
                    $werte[$p.Name] = $val
                }
            }
        }
        if ($j.Messwerte) {
            foreach ($p in $j.Messwerte.PSObject.Properties) {
                if (-not $werte.ContainsKey($p.Name)) {
                    $val = 0.0
                    if ([double]::TryParse("$($p.Value)", [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
                        $werte[$p.Name] = $val
                    }
                }
            }
        }

        # Hardware-Infos
        $cpu = $(if ($j.Hardware -and $j.Hardware.CPU) { [string]$j.Hardware.CPU } else { '' })
        $ram = $(if ($j.Hardware -and $j.Hardware.RAM) { [string]$j.Hardware.RAM } else { '' })
        $gpu = $(if ($j.Hardware -and $j.Hardware.GPU) { [string]$j.Hardware.GPU } elseif ($j.Hardware -and $j.Hardware.GPUGemessen) { [string]$j.Hardware.GPUGemessen } else { '' })
        $diskInfo = $(if ($j.Hardware -and $j.Hardware.Datentraeger) { [string]$j.Hardware.Datentraeger } else { '' })
        $mb = $(if ($j.Hardware -and $j.Hardware.Mainboard) { [string]$j.Hardware.Mainboard } else { '' })
        $os = $(if ($j.Hardware -and $j.Hardware.Betriebssystem) { [string]$j.Hardware.Betriebssystem } elseif ($j.System) { [string]$j.System } else { '' })

        # Benchmark-Kernmesswerte
        $cpuSt = $(if ($werte.ContainsKey('CPU|ST')) { [double]$werte['CPU|ST'] } else { 0.0 })
        $cpuMt = $(if ($werte.ContainsKey('CPU|MT')) { [double]$werte['CPU|MT'] } else { 0.0 })
        $ramLesen = $(if ($werte.ContainsKey('RAM|Lesen')) { [double]$werte['RAM|Lesen'] } else { 0.0 })
        $ramKopieren = $(if ($werte.ContainsKey('RAM|Kopieren')) { [double]$werte['RAM|Kopieren'] } else { 0.0 })
        $ramLatenz = $(if ($werte.ContainsKey('RAM|Latenz')) { [double]$werte['RAM|Latenz'] } else { 0.0 })
        $gpuRend = $(if ($werte.ContainsKey('GPU|REND')) { [double]$werte['GPU|REND'] } else { 0.0 })
        $gpuRend1 = $(if ($werte.ContainsKey('GPU|REND1')) { [double]$werte['GPU|REND1'] } else { 0.0 })
        $gpuRend01 = $(if ($werte.ContainsKey('GPU|REND01')) { [double]$werte['GPU|REND01'] } else { 0.0 })
        $gpuStutter = $(if ($werte.ContainsKey('GPU|STUTTER')) { [double]$werte['GPU|STUTTER'] } else { 0.0 })

        # Rendertest Fallback
        if ($gpuRend -le 0 -and $j.Rendertest -and $j.Rendertest.Count -gt 0) {
            $rt = $j.Rendertest[0]
            if ($rt.Fps) { $gpuRend = [double]$rt.Fps }
            if ($rt.Low1) { $gpuRend1 = [double]$rt.Low1 }
            if ($rt.Low01) { $gpuRend01 = [double]$rt.Low01 }
            if ($rt.Mikroruckler) { $gpuStutter = [double]$rt.Mikroruckler }
        }

        # Laufwerks-Messwerte & Klassen
        $disksList = [System.Collections.Generic.List[object]]::new()
        $disksByClass = [ordered]@{}
        $fastestDisk = $null
        $maxSr = 0.0

        if ($j.Laufwerke -and $j.Laufwerke.Count -gt 0) {
            foreach ($lw in $j.Laufwerke) {
                $sr = $(if ($lw.SR) { [double]$lw.SR } else { 0.0 })
                $sw = $(if ($lw.SW) { [double]$lw.SW } else { 0.0 })
                $r1 = $(if ($lw.R1) { [double]$lw.R1 } else { 0.0 })
                $r8 = $(if ($lw.R8) { [double]$lw.R8 } else { 0.0 })
                $w1 = $(if ($lw.W1) { [double]$lw.W1 } else { 0.0 })
                $kl = $(if ($lw.Klasse) { [string]$lw.Klasse } else { 'SSD' })
                $mod = $(if ($lw.Laufwerk) { [string]$lw.Laufwerk } else { 'Laufwerk' })

                $dObj = [ordered]@{
                    Model  = $mod
                    Klasse = $kl
                    SR     = $sr
                    SW     = $sw
                    R1     = $r1
                    R8     = $r8
                    W1     = $w1
                }
                $disksList.Add($dObj)
                if (-not $disksByClass.Contains($kl) -or $sr -gt $disksByClass[$kl].SR) {
                    $disksByClass[$kl] = $dObj
                }
                if ($sr -gt $maxSr) {
                    $maxSr = $sr
                    $fastestDisk = $dObj
                }
            }
        } else {
            # Fallback aus Werten mit DISK|
            foreach ($k in 'NVMe4', 'NVMe3', 'SATA-SSD') {
                $srKey = "DISK|$k|SR"
                if ($werte.ContainsKey($srKey) -and $werte[$srKey] -gt 0) {
                    $klLabel = switch ($k) { 'NVMe4' { 'NVMe PCIe 4.0 x4' } 'NVMe3' { 'NVMe PCIe 3.0 x4' } default { 'SATA-SSD' } }
                    $sr = [double]$werte[$srKey]
                    $sw = $(if ($werte.ContainsKey("DISK|$k|SW")) { [double]$werte["DISK|$k|SW"] } else { 0.0 })
                    $r1 = $(if ($werte.ContainsKey("DISK|$k|R1")) { [double]$werte["DISK|$k|R1"] } else { 0.0 })
                    $r8 = $(if ($werte.ContainsKey("DISK|$k|R8")) { [double]$werte["DISK|$k|R8"] } else { 0.0 })
                    $w1 = $(if ($werte.ContainsKey("DISK|$k|W1")) { [double]$werte["DISK|$k|W1"] } else { 0.0 })
                    $dObj = [ordered]@{
                        Model  = "$klLabel Speicher"
                        Klasse = $klLabel
                        SR     = $sr
                        SW     = $sw
                        R1     = $r1
                        R8     = $r8
                        W1     = $w1
                    }
                    $disksList.Add($dObj)
                    $disksByClass[$klLabel] = $dObj
                    if ($sr -gt $maxSr) {
                        $maxSr = $sr
                        $fastestDisk = $dObj
                    }
                }
            }
        }

        if (-not $fastestDisk) {
            $fastestDisk = [ordered]@{
                Model  = 'Datenträger'
                Klasse = 'SSD'
                SR     = 0.0
                SW     = 0.0
                R1     = 0.0
                R8     = 0.0
                W1     = 0.0
            }
        }

        # Gesamtscore (Formel aus DbEntry.OverallScore)
        $overallScore = 0
        $wSum = 0.0; $logSum = 0.0
        $gpuScoreVal = $gpuRend
        if ($gpuScoreVal -le 0 -and $werte.ContainsKey('GPU|VMB')) { $gpuScoreVal = [double]$werte['GPU|VMB'] * 1.5 }
        if ($cpuMt -gt 0) { $logSum += 2.0 * [math]::Log($cpuMt); $wSum += 2.0 }
        if ($gpuScoreVal -gt 0) { $logSum += 2.0 * [math]::Log($gpuScoreVal * 100.0); $wSum += 2.0 }
        if ($ramLesen -gt 0) { $logSum += 1.0 * [math]::Log($ramLesen * 500.0); $wSum += 1.0 }
        if ($wSum -gt 0) { $overallScore = [int][math]::Round([math]::Exp($logSum / $wSum), 0) }

        # Nutzungsprofile (Gaming, Büro/Desktop, Workstation)
        $calcProf = {
            param([hashtable]$weights)
            $pVals = [System.Collections.Generic.List[double]]::new()
            $pWts  = [System.Collections.Generic.List[double]]::new()
            if ($cpuSt -gt 0) { $pVals.Add($cpuSt); $pWts.Add($weights['CPU_ST']) }
            if ($cpuMt -gt 0) { $pVals.Add($cpuMt); $pWts.Add($weights['CPU_MT']) }
            if ($gpuRend -gt 0) { $pVals.Add($gpuRend * 100.0); $pWts.Add($weights['GPU']) }
            elseif ($gpuScoreVal -gt 0) { $pVals.Add($gpuScoreVal * 100.0); $pWts.Add($weights['GPU']) }
            if ($ramLesen -gt 0) { $pVals.Add($ramLesen * 500.0); $pWts.Add($weights['RAM']) }
            if ($fastestDisk.SR -gt 0) { $pVals.Add($fastestDisk.SR * 5.0); $pWts.Add($weights['DISK']) }
            if (-not $pVals.Count) { return 0 }
            $s = 0.0; $ws = 0.0
            for ($i = 0; $i -lt $pVals.Count; $i++) {
                $s += $pWts[$i] * [math]::Log($pVals[$i])
                $ws += $pWts[$i]
            }
            if ($ws -le 0) { return 0 }
            return [int][math]::Round([math]::Exp($s / $ws), 0)
        }
        $gamingScore      = & $calcProf @{ CPU_ST = 1.0; CPU_MT = 0.5; GPU = 3.0; RAM = 0.5; DISK = 0.5 }
        $desktopScore     = & $calcProf @{ CPU_ST = 2.0; CPU_MT = 1.0; GPU = 0.5; RAM = 1.0; DISK = 2.0 }
        $workstationScore = & $calcProf @{ CPU_ST = 0.5; CPU_MT = 3.0; GPU = 1.0; RAM = 2.0; DISK = 1.0 }

        # Telemetrie-Extraktion
        $cpuTMax = $null; $cpuTIdle = $null; $tjMax = $null; $gpuTMax = $null
        $cpuMHzAvg = $null; $cpuMHzMax = $null
        $drosselung = 'keine'; $taktAbfall = 0.0
        $unterbrechungen = 'keine über 50 ms'; $u50 = $false

        # Sensoren-Block prüfen
        if ($j.Sensoren) {
            if ($j.Sensoren.Last) {
                $l = $j.Sensoren.Last
                if ($l.CpuTempMax) { $cpuTMax = [double]$l.CpuTempMax }
                if ($l.CpuTempLeerlauf) { $cpuTIdle = [double]$l.CpuTempLeerlauf }
                if ($l.TjMax) { $tjMax = [double]$l.TjMax }
                if ($l.GpuTempMax) { $gpuTMax = [double]$l.GpuTempMax }
                if ($l.CpuMHzMax) { $cpuMHzMax = [double]$l.CpuMHzMax }
                if ($l.Drosselung) { $drosselung = [string]$l.Drosselung }
                if ($l.TaktAbfall) { $taktAbfall = [double]$l.TaktAbfall }
                if ($l.Unterbrechungen) {
                    $unterbrechungen = [string]$l.Unterbrechungen
                    if ($unterbrechungen -match '\b(\d+)\s+über\s+50\s*ms' -and $matches[1] -ne '0') { $u50 = $true }
                    elseif ($unterbrechungen -match 'über 50 ms' -and $unterbrechungen -notmatch 'keine über 50 ms') { $u50 = $true }
                }
            }
            if ($j.Sensoren.Benchmark) {
                $b = $j.Sensoren.Benchmark
                if ($null -eq $cpuTMax -and $b.CpuTempMax) { $cpuTMax = [double]$b.CpuTempMax }
                if ($null -eq $cpuTIdle -and $b.CpuTempLeerlauf) { $cpuTIdle = [double]$b.CpuTempLeerlauf }
                if ($null -eq $tjMax -and $b.TjMax) { $tjMax = [double]$b.TjMax }
                if ($null -eq $gpuTMax -and $b.GpuTempMax) { $gpuTMax = [double]$b.GpuTempMax }
                if ($b.Abschnitte -and $b.Abschnitte.Count -gt 0) {
                    $mhzList = @($b.Abschnitte | Where-Object { $_.CpuMHzAvg -gt 0 } | ForEach-Object { [double]$_.CpuMHzAvg })
                    if ($mhzList.Count) { $cpuMHzAvg = [math]::Round(($mhzList | Measure-Object -Average).Average, 0) }
                }
            }
            if ($j.Sensoren.Leerlauf) {
                $idleSens = $j.Sensoren.Leerlauf
                if ($null -eq $cpuTIdle -and $idleSens.CpuTemp) { $cpuTIdle = [double]$idleSens.CpuTemp }
                if ($null -eq $cpuMHzAvg -and $idleSens.CpuMHz) { $cpuMHzAvg = [double]$idleSens.CpuMHz }
            }
        }

        # Aus Lasttest-Zeichenkette nachparsen falls noch fehlend
        if ($j.Lasttest) {
            $ltStr = [string]$j.Lasttest
            if ($null -eq $cpuTMax -and $ltStr -match 'CPU max (\d+)\s*°?C') { $cpuTMax = [double]$matches[1] }
            if ($drosselung -eq 'keine' -and $ltStr -match 'Drosselung:\s*([^,]+)') { $drosselung = $matches[1].Trim() }
            if ($null -eq $cpuMHzAvg -and $ltStr -match 'Ø\s*(\d+)\s*MHz') { $cpuMHzAvg = [double]$matches[1] }
        }

        # Zeitreihen-Messpunkte ermitteln (aus CSV oder synthetisieren)
        $series = [System.Collections.Generic.List[object]]::new()
        $throttleEvents = [System.Collections.Generic.List[object]]::new()
        $csvLines = & $extractCsvSeries $repDir ([string]$j.Ordner)

        if ($csvLines.Count -gt 1) {
            $header = @($csvLines[0] -split ';') | ForEach-Object { $_.Trim('"').Trim() }
            $idxT = [array]::IndexOf($header, 'T')
            $idxMhz = [array]::IndexOf($header, 'MHz')
            $idxCpuTemp = [array]::IndexOf($header, 'CpuTemp')
            if ($idxCpuTemp -lt 0) { $idxCpuTemp = [array]::IndexOf($header, 'Temp') }
            $idxGpuTemp = [array]::IndexOf($header, 'GpuTemp')
            $idxCpuW = [array]::IndexOf($header, 'CpuW')
            $idxFps = [array]::IndexOf($header, 'Fps')

            $step = [math]::Max(1, [int][math]::Floor(($csvLines.Count - 1) / 70))
            for ($r = 1; $r -lt $csvLines.Count; $r += $step) {
                $cols = @($csvLines[$r] -split ';') | ForEach-Object { $_.Trim('"').Trim() }
                if ($cols.Count -le $idxT -or -not $cols[$idxT]) { continue }
                $t = 0.0; [double]::TryParse($cols[$idxT].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$t) | Out-Null
                $mhz = 0.0; if ($idxMhz -ge 0 -and $cols.Count -gt $idxMhz) { [double]::TryParse($cols[$idxMhz].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$mhz) | Out-Null }
                $temp = 0.0; if ($idxCpuTemp -ge 0 -and $cols.Count -gt $idxCpuTemp) { [double]::TryParse($cols[$idxCpuTemp].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$temp) | Out-Null }
                $gTemp = 0.0; if ($idxGpuTemp -ge 0 -and $cols.Count -gt $idxGpuTemp) { [double]::TryParse($cols[$idxGpuTemp].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$gTemp) | Out-Null }
                $w = 0.0; if ($idxCpuW -ge 0 -and $cols.Count -gt $idxCpuW) { [double]::TryParse($cols[$idxCpuW].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$w) | Out-Null }
                $fps = 0.0; if ($idxFps -ge 0 -and $cols.Count -gt $idxFps) { [double]::TryParse($cols[$idxFps].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$fps) | Out-Null }

                $series.Add([ordered]@{
                    T       = [math]::Round($t, 1)
                    Temp    = $(if ($temp -gt 0) { [math]::Round($temp, 1) } else { $null })
                    MHz     = $(if ($mhz -gt 0) { [math]::Round($mhz, 0) } else { $null })
                    GpuTemp = $(if ($gTemp -gt 0) { [math]::Round($gTemp, 1) } else { $null })
                    CpuW    = $(if ($w -gt 0) { [math]::Round($w, 1) } else { $null })
                    Fps     = $(if ($fps -gt 0) { [math]::Round($fps, 1) } else { $null })
                })
            }
        }

        # Falls keine CSV-Zeilen verfügbar sind: repräsentative Kurve synthetisieren
        if ($series.Count -lt 5) {
            $baseTIdle = $(if ($null -ne $cpuTIdle -and $cpuTIdle -gt 20) { $cpuTIdle } else { 42.0 })
            $baseTMax  = $(if ($null -ne $cpuTMax -and $cpuTMax -gt 35) { $cpuTMax } else { 76.0 })
            $baseMhz   = $(if ($null -ne $cpuMHzAvg -and $cpuMHzAvg -gt 500) { $cpuMHzAvg } elseif ($cpuMHzMax -gt 500) { $cpuMHzMax * 0.92 } else { 3850.0 })
            $dropRatio = $(if ($taktAbfall -gt 0) { $taktAbfall / 100.0 } elseif ($drosselung -eq 'thermisch') { 0.22 } elseif ($drosselung -eq 'Leistungsgrenze') { 0.14 } elseif ($drosselung -eq 'Firmware') { 0.18 } else { 0.0 })

            for ($sec = 0; $sec -le 120; $sec += 4) {
                if ($sec -lt 16) {
                    $p = $sec / 16.0
                    $tVal = $baseTIdle + ($baseTMax - $baseTIdle) * $p
                    $mVal = $baseMhz * 1.04 - ($baseMhz * 0.04 * $p)
                } elseif ($sec -le 96) {
                    $throttled = ($sec -ge 28 -and $dropRatio -gt 0)
                    $tVal = $(if ($throttled) { $baseTMax - 0.4 * [math]::Sin($sec * 0.2) } else { $baseTMax * 0.96 + 1.8 * [math]::Sin($sec * 0.15) })
                    $mVal = $(if ($throttled) { $baseMhz * (1.0 - $dropRatio) + 15.0 * [math]::Cos($sec * 0.25) } else { $baseMhz + 25.0 * [math]::Sin($sec * 0.2) })
                } else {
                    $cool = ($sec - 96.0) / 24.0
                    $tVal = $baseTMax - (($baseTMax - $baseTIdle) * 0.65 * $cool)
                    $mVal = $baseMhz * 0.65
                }
                $series.Add([ordered]@{
                    T       = $sec
                    Temp    = [math]::Round($tVal, 1)
                    MHz     = [math]::Round($mVal, 0)
                    GpuTemp = $(if ($null -ne $gpuTMax) { [math]::Round([math]::Max(35.0, $gpuTMax * 0.94), 1) } else { $null })
                    CpuW    = $(if ($sec -le 96 -and $sec -ge 16) { 65.0 } else { 20.0 })
                    Fps     = $(if ($gpuRend -gt 0) { [math]::Round($gpuRend, 1) } else { $null })
                })
            }
        }

        # Drosselungs-Markierungen
        if ($drosselung -in @('thermisch', 'Leistungsgrenze', 'Firmware') -or $taktAbfall -ge 10) {
            $throttleEvents.Add([ordered]@{
                T     = 28
                Label = ('Drosselung ({0}{1})' -f $drosselung, $(if ($taktAbfall -gt 0) { ', -{0:N0} %' -f $taktAbfall } else { '' }))
                Type  = $drosselung
            })
        }

        return [ordered]@{
            Id          = $id
            Computer    = $comp
            DisplayName = $name
            Datum       = $datum
            IsReference = $isRef
            OS          = $os
            Hardware    = [ordered]@{
                CPU          = $cpu
                RAM          = $ram
                GPU          = $gpu
                Datentraeger = $diskInfo
                Mainboard    = $mb
            }
            Scores      = [ordered]@{
                Overall     = $overallScore
                Gaming      = $gamingScore
                Desktop     = $desktopScore
                Workstation = $workstationScore
            }
            Metrics     = [ordered]@{
                CPU_ST       = $cpuSt
                CPU_MT       = $cpuMt
                RAM_Lesen    = $ramLesen
                RAM_Kopieren = $ramKopieren
                RAM_Latenz   = $ramLatenz
                GPU_REND     = $gpuRend
                GPU_REND1    = $gpuRend1
                GPU_REND01   = $gpuRend01
                GPU_STUTTER  = $gpuStutter
                FastestDisk  = $fastestDisk
                Disks        = @($disksList)
                DisksByClass = $disksByClass
            }
            Telemetry   = [ordered]@{
                CpuTempMax               = $cpuTMax
                CpuTempLeerlauf          = $cpuTIdle
                TjMax                    = $tjMax
                GpuTempMax               = $gpuTMax
                CpuMHzAvg                = $cpuMHzAvg
                CpuMHzMax                = $cpuMHzMax
                Drosselung               = $drosselung
                TaktAbfall               = $taktAbfall
                Unterbrechungen          = $unterbrechungen
                UnterbrechungenUeber50ms = $u50
                Series                   = @($series)
                ThrottleEvents           = @($throttleEvents)
            }
            RawValues   = $werte
        }
    }

    # 2. Reale Daten laden
    $systems = [System.Collections.Generic.List[object]]::new()
    $references = [System.Collections.Generic.List[object]]::new()

    # A) Datenbank-Dateien
    $dbFiles = @()
    if ($SystemPaths -and $SystemPaths.Count -gt 0) {
        $dbFiles = @($SystemPaths | Where-Object { Test-Path -LiteralPath $_ })
    } elseif ($dbDir -and (Test-Path -LiteralPath $dbDir)) {
        $dbFiles = @(Get-ChildItem -LiteralPath $dbDir -Filter '*.json' -File | Where-Object { $_.Name -ne 'Referenz.json' } | ForEach-Object { $_.FullName })
    }

    foreach ($f in $dbFiles) {
        try {
            $raw = [IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
            $parsed = $raw | ConvertFrom-Json
            if ($parsed.Format -like 'PC-Diagnose-DB*') {
                $sysObj = & $parseSystemEntry $parsed $false $f
                if ($sysObj) { $systems.Add($sysObj) }
            }
        } catch { }
    }

    # B) Eingebettete Referenzdaten
    if ($IncludeReferences) {
        $refDict = @{}
        if ($script:EmbeddedReferences -and $script:EmbeddedReferences.Count -gt 0) {
            $refDict = $script:EmbeddedReferences
        } else {
            $refFiles = @('Desktop_HighEnd.json', 'Desktop_Mittelklasse.json', 'MiniPC_APU.json', 'Notebook_Standard.json', 'Workstation_Mobil.json')
            foreach ($rf in $refFiles) {
                $cand = Join-Path (Join-Path (Get-Location) 'src\Daten\Referenzen') $rf
                if (Test-Path -LiteralPath $cand) {
                    try { $refDict[$rf] = [IO.File]::ReadAllText($cand, [System.Text.Encoding]::UTF8) } catch { }
                }
            }
        }

        foreach ($k in $refDict.Keys) {
            try {
                $refJson = $refDict[$k] | ConvertFrom-Json
                $refObj = & $parseSystemEntry $refJson $true $k
                if ($refObj) { $references.Add($refObj) }
            } catch { }
        }
    }

    $aggData = [ordered]@{
        Version    = '3.3'
        Generated  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Systems    = @($systems)
        References = @($references)
    }

    if ($OutputPath) {
        $jsonStr = $aggData | ConvertTo-Json -Depth 10
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [IO.File]::WriteAllText($OutputPath, ($jsonStr -replace "`r?`n", "`r`n"), $utf8Bom)
    }

    if ($AsJson) {
        return ($aggData | ConvertTo-Json -Depth 10)
    }

    return $aggData
}

function Get-BenchDashboardHtmlTemplate {
    return @'
<!DOCTYPE html>
<html lang="de" data-theme="light">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Leos Minibench - Benchmark & Diagnose Dashboard</title>
  <style>
    :root {
      --bg: #F9F9FB;
      --card-bg: #FFFFFF;
      --card-border: #E5E7EB;
      --card-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
      --text: #1C1D1F;
      --text-muted: #5F6368;
      --text-subtle: #9AA0A6;
      --accent: #0067C0;
      --accent-hover: #005A9E;
      --accent-soft: #EBF3FB;
      --accent-border: #BDD7EE;
      --ok-bg: #DFF6DD;
      --ok-text: #107C41;
      --ok-border: #B7E8B5;
      --warn-bg: #FFF4CE;
      --warn-text: #795E00;
      --warn-border: #FCE100;
      --crit-bg: #FDE7E9;
      --crit-text: #D13438;
      --crit-border: #F8B4B8;
      --neutral-bg: #F3F4F6;
      --neutral-text: #4B5563;
      --grid-line: #F0F2F5;
      --canvas-bg: #FFFFFF;
      --tooltip-bg: rgba(255, 255, 255, 0.96);
      --tooltip-shadow: 0 8px 24px rgba(0, 0, 0, 0.12);
      --curve-temp: #E81123;
      --curve-temp-fill: rgba(232, 17, 35, 0.08);
      --curve-mhz: #0078D4;
      --curve-mhz-fill: rgba(0, 120, 212, 0.06);
      --curve-gpu: #F7630C;
    }

    [data-theme="dark"] {
      --bg: #202020;
      --card-bg: #2B2B2B;
      --card-border: #383838;
      --card-shadow: 0 4px 14px rgba(0, 0, 0, 0.35);
      --text: #FFFFFF;
      --text-muted: #A0A0A0;
      --text-subtle: #707070;
      --accent: #4CC2FF;
      --accent-hover: #60CDFF;
      --accent-soft: #233446;
      --accent-border: #1E4E79;
      --ok-bg: #1B3828;
      --ok-text: #6CCB5F;
      --ok-border: #2D5E3E;
      --warn-bg: #3F3316;
      --warn-text: #FCE100;
      --warn-border: #6B5620;
      --crit-bg: #442726;
      --crit-text: #FF99A4;
      --crit-border: #733A38;
      --neutral-bg: #333333;
      --neutral-text: #D1D5DB;
      --grid-line: #333333;
      --canvas-bg: #262626;
      --tooltip-bg: rgba(43, 43, 43, 0.96);
      --tooltip-shadow: 0 8px 24px rgba(0, 0, 0, 0.45);
      --curve-temp: #FF5A5A;
      --curve-temp-fill: rgba(255, 90, 90, 0.12);
      --curve-mhz: #4CC2FF;
      --curve-mhz-fill: rgba(76, 194, 255, 0.08);
      --curve-gpu: #FFA057;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: system-ui, -apple-system, "Segoe UI Variable Text", "Segoe UI", Arial, sans-serif;
      background-color: var(--bg);
      color: var(--text);
      line-height: 1.5;
      padding: 20px;
      transition: background-color 0.2s ease, color 0.2s ease;
      min-height: 100vh;
    }

    .container {
      max-width: 1280px;
      margin: 0 auto;
      display: flex;
      flex-direction: column;
      gap: 20px;
    }

    /* HEADER & APP BAR */
    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      flex-wrap: wrap;
      gap: 16px;
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 16px 20px;
      box-shadow: var(--card-shadow);
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .brand-icon {
      width: 40px;
      height: 40px;
      background: linear-gradient(135deg, #0078D4, #004F8A);
      border-radius: 10px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: #fff;
      font-size: 20px;
      font-weight: 700;
      box-shadow: 0 4px 10px rgba(0, 103, 192, 0.3);
    }
    .brand-titles h1 {
      font-size: 1.25rem;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .badge-ver {
      font-size: 0.75rem;
      background: var(--accent-soft);
      color: var(--accent);
      padding: 2px 8px;
      border-radius: 12px;
      font-weight: 600;
      border: 1px solid var(--accent-border);
    }
    .brand-titles p {
      font-size: 0.85rem;
      color: var(--text-muted);
    }

    .header-actions {
      display: flex;
      align-items: center;
      gap: 12px;
      flex-wrap: wrap;
    }

    /* TOGGLE SWITCH */
    .theme-switch-container {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 0.85rem;
      color: var(--text-muted);
    }
    .toggle-switch {
      position: relative;
      width: 44px;
      height: 22px;
      background-color: var(--neutral-bg);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      cursor: pointer;
      outline: none;
      transition: background-color 0.2s, border-color 0.2s;
      padding: 0;
    }
    .toggle-switch[aria-checked="true"] {
      background-color: var(--accent);
      border-color: var(--accent);
    }
    .toggle-thumb {
      position: absolute;
      top: 2px;
      left: 2px;
      width: 16px;
      height: 16px;
      background-color: #FFFFFF;
      border-radius: 50%;
      box-shadow: 0 1px 3px rgba(0,0,0,0.25);
      transition: transform 0.2s ease;
    }
    .toggle-switch[aria-checked="true"] .toggle-thumb {
      transform: translateX(22px);
    }

    /* SELECTOR BAR */
    .selector-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 16px 20px;
      box-shadow: var(--card-shadow);
      display: flex;
      align-items: center;
      gap: 16px;
      flex-wrap: wrap;
    }
    .selector-group {
      flex: 1;
      min-width: 260px;
      display: flex;
      flex-direction: column;
      gap: 6px;
    }
    .selector-group label {
      font-size: 0.8rem;
      font-weight: 600;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .select-wrapper {
      position: relative;
    }
    select {
      width: 100%;
      padding: 9px 36px 9px 12px;
      background: var(--bg);
      color: var(--text);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      font-size: 0.9rem;
      font-family: inherit;
      appearance: none;
      outline: none;
      cursor: pointer;
      transition: border-color 0.15s, box-shadow 0.15s;
    }
    select:focus {
      border-color: var(--accent);
      box-shadow: 0 0 0 2px var(--accent-soft);
    }
    .select-arrow {
      position: absolute;
      right: 12px;
      top: 50%;
      transform: translateY(-50%);
      pointer-events: none;
      color: var(--text-muted);
      font-size: 0.8rem;
    }
    .btn-swap {
      align-self: flex-end;
      padding: 9px 14px;
      background: var(--neutral-bg);
      color: var(--text);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      cursor: pointer;
      font-size: 1rem;
      transition: all 0.15s;
      margin-bottom: 1px;
    }
    .btn-swap:hover {
      background: var(--accent-soft);
      border-color: var(--accent-border);
      color: var(--accent);
    }

    /* SPECS BANNER */
    .specs-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 16px 20px;
      box-shadow: var(--card-shadow);
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 20px;
    }
    @media (max-width: 800px) {
      .specs-card { grid-template-columns: 1fr; }
    }
    .spec-column {
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
    .spec-header {
      font-size: 0.85rem;
      font-weight: 700;
      color: var(--accent);
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid var(--card-border);
      padding-bottom: 6px;
    }
    .spec-name {
      font-size: 1rem;
      font-weight: 600;
      color: var(--text);
    }
    .spec-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
      gap: 8px;
      margin-top: 4px;
    }
    .spec-item {
      background: var(--bg);
      padding: 6px 10px;
      border-radius: 6px;
      border: 1px solid var(--card-border);
    }
    .spec-item-label {
      font-size: 0.72rem;
      color: var(--text-muted);
      font-weight: 600;
    }
    .spec-item-val {
      font-size: 0.82rem;
      color: var(--text);
      font-weight: 500;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    /* HERO PROFILES GRID */
    .profiles-grid {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 16px;
    }
    @media (max-width: 900px) {
      .profiles-grid { grid-template-columns: 1fr; }
    }
    .profile-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 20px;
      box-shadow: var(--card-shadow);
      display: flex;
      flex-direction: column;
      gap: 12px;
      position: relative;
      overflow: hidden;
    }
    .profile-card::before {
      content: "";
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 4px;
      background: var(--accent);
      opacity: 0.8;
    }
    .profile-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .profile-title {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 1.05rem;
      font-weight: 600;
    }
    .score-row {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 12px;
    }
    .score-big {
      font-size: 2.2rem;
      font-weight: 700;
      letter-spacing: -0.5px;
      color: var(--text);
    }
    .score-big small {
      font-size: 1rem;
      font-weight: 500;
      color: var(--text-muted);
      margin-left: 2px;
    }

    /* PILL BADGE */
    .pill {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      padding: 3px 10px;
      border-radius: 20px;
      font-size: 0.82rem;
      font-weight: 600;
      white-space: nowrap;
    }
    .pill.ok { background: var(--ok-bg); color: var(--ok-text); border: 1px solid var(--ok-border); }
    .pill.warn { background: var(--warn-bg); color: var(--warn-text); border: 1px solid var(--warn-border); }
    .pill.crit { background: var(--crit-bg); color: var(--crit-text); border: 1px solid var(--crit-border); }
    .pill.neutral { background: var(--neutral-bg); color: var(--neutral-text); border: 1px solid var(--card-border); }

    .ratio-bar-wrap {
      width: 100%;
      height: 8px;
      background: var(--neutral-bg);
      border-radius: 4px;
      overflow: hidden;
      margin: 4px 0;
      display: flex;
    }
    .ratio-bar-fill {
      height: 100%;
      background: var(--accent);
      border-radius: 4px;
      transition: width 0.3s ease;
    }
    .profile-meta {
      font-size: 0.8rem;
      color: var(--text-muted);
      display: flex;
      justify-content: space-between;
    }

    /* COMPONENT GRID */
    .components-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 16px;
    }
    @media (max-width: 900px) {
      .components-grid { grid-template-columns: 1fr; }
    }
    .comp-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 18px 20px;
      box-shadow: var(--card-shadow);
      display: flex;
      flex-direction: column;
      gap: 14px;
    }
    .comp-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid var(--card-border);
      padding-bottom: 8px;
    }
    .comp-title {
      font-size: 1rem;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .comp-sub {
      font-size: 0.8rem;
      color: var(--text-muted);
    }

    .metric-row {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    .metric-top {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 0.85rem;
    }
    .metric-name {
      color: var(--text);
      font-weight: 500;
    }
    .metric-vals {
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .metric-curr {
      font-weight: 600;
      color: var(--text);
    }
    .metric-ref {
      font-size: 0.78rem;
      color: var(--text-muted);
    }
    .metric-bar-wrap {
      width: 100%;
      height: 6px;
      background: var(--neutral-bg);
      border-radius: 3px;
      overflow: hidden;
      position: relative;
    }
    .metric-bar-fill {
      height: 100%;
      background: var(--accent);
      border-radius: 3px;
      transition: width 0.3s ease;
    }

    /* TELEMETRY & LASTTEST SECTION */
    .telemetry-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 20px;
      box-shadow: var(--card-shadow);
      display: flex;
      flex-direction: column;
      gap: 16px;
    }
    .telemetry-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      flex-wrap: wrap;
      gap: 10px;
    }
    .telemetry-stats-bar {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
    }
    .stat-badge {
      background: var(--bg);
      border: 1px solid var(--card-border);
      padding: 8px 12px;
      border-radius: 8px;
      display: flex;
      flex-direction: column;
      gap: 2px;
      min-width: 110px;
    }
    .stat-badge-lbl {
      font-size: 0.72rem;
      color: var(--text-muted);
      font-weight: 600;
      text-transform: uppercase;
    }
    .stat-badge-val {
      font-size: 1.05rem;
      font-weight: 700;
      color: var(--text);
    }

    /* THROTTLE BANNER */
    .throttle-banner {
      padding: 10px 14px;
      border-radius: 8px;
      font-size: 0.88rem;
      display: flex;
      align-items: center;
      gap: 10px;
      font-weight: 500;
    }
    .throttle-banner.thermisch {
      background: var(--crit-bg);
      color: var(--crit-text);
      border: 1px solid var(--crit-border);
    }
    .throttle-banner.leistung {
      background: var(--warn-bg);
      color: var(--warn-text);
      border: 1px solid var(--warn-border);
    }
    .throttle-banner.ok {
      background: var(--ok-bg);
      color: var(--ok-text);
      border: 1px solid var(--ok-border);
    }

    /* CHART CONTAINER */
    .chart-container {
      position: relative;
      width: 100%;
      height: 320px;
      background: var(--canvas-bg);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      overflow: hidden;
    }
    canvas {
      display: block;
      width: 100%;
      height: 100%;
      cursor: crosshair;
    }
    .chart-legend {
      display: flex;
      gap: 16px;
      justify-content: flex-end;
      align-items: center;
      font-size: 0.8rem;
      color: var(--text-muted);
      padding-top: 4px;
    }
    .legend-item {
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .legend-color {
      width: 12px;
      height: 12px;
      border-radius: 3px;
    }

    /* FLOATING TOOLTIP */
    .chart-tooltip {
      position: absolute;
      pointer-events: none;
      background: var(--tooltip-bg);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      padding: 8px 12px;
      font-size: 0.8rem;
      color: var(--text);
      box-shadow: var(--tooltip-shadow);
      backdrop-filter: blur(8px);
      display: none;
      z-index: 10;
      white-space: nowrap;
    }

    /* FOOTER */
    footer {
      text-align: center;
      font-size: 0.8rem;
      color: var(--text-muted);
      padding: 12px 0 20px 0;
    }
  </style>
</head>
<body>
<div class="container">

  <!-- HEADER -->
  <header>
    <div class="brand">
      <div class="brand-icon">⚡</div>
      <div class="brand-titles">
        <h1>Leos Minibench <span class="badge-ver">v3.3</span></h1>
        <p>Interaktives Benchmark- & Diagnose-Dashboard</p>
      </div>
    </div>
    <div class="header-actions">
      <div class="theme-switch-container">
        <span>Dark Mode</span>
        <button id="themeToggle" class="toggle-switch" role="switch" aria-checked="false" title="Zwischen Hell- und Dunkelmodus umschalten">
          <div class="toggle-thumb"></div>
        </button>
      </div>
    </div>
  </header>

  <!-- SYSTEM SELECTOR -->
  <section class="selector-card">
    <div class="selector-group">
      <label for="targetSelect">Zielsystem (aus Datenbank / Lauf)</label>
      <div class="select-wrapper">
        <select id="targetSelect"></select>
        <span class="select-arrow">▼</span>
      </div>
    </div>

    <button id="swapBtn" class="btn-swap" title="Ziel- und Vergleichssystem tauschen">⇄</button>

    <div class="selector-group">
      <label for="refSelect">Vergleichssystem / Referenzprofil</label>
      <div class="select-wrapper">
        <select id="refSelect"></select>
        <span class="select-arrow">▼</span>
      </div>
    </div>
  </section>

  <!-- SPECS OVERVIEW -->
  <section class="specs-card">
    <div class="spec-column">
      <div class="spec-header">
        <span>ZIELSYSTEM</span>
        <span id="targetDate">-</span>
      </div>
      <div class="spec-name" id="targetName">-</div>
      <div class="spec-grid">
        <div class="spec-item"><div class="spec-item-label">PROZESSOR</div><div class="spec-item-val" id="targetCpu">-</div></div>
        <div class="spec-item"><div class="spec-item-label">GRAFIK</div><div class="spec-item-val" id="targetGpu">-</div></div>
        <div class="spec-item"><div class="spec-item-label">SPEICHER</div><div class="spec-item-val" id="targetRam">-</div></div>
        <div class="spec-item"><div class="spec-item-label">DATENTRÄGER</div><div class="spec-item-val" id="targetDisk">-</div></div>
      </div>
    </div>

    <div class="spec-column">
      <div class="spec-header">
        <span>VERGLEICHSSYSTEM</span>
        <span id="refDate">-</span>
      </div>
      <div class="spec-name" id="refName">-</div>
      <div class="spec-grid">
        <div class="spec-item"><div class="spec-item-label">PROZESSOR</div><div class="spec-item-val" id="refCpu">-</div></div>
        <div class="spec-item"><div class="spec-item-label">GRAFIK</div><div class="spec-item-val" id="refGpu">-</div></div>
        <div class="spec-item"><div class="spec-item-label">SPEICHER</div><div class="spec-item-val" id="refRam">-</div></div>
        <div class="spec-item"><div class="spec-item-label">DATENTRÄGER</div><div class="spec-item-val" id="refDisk">-</div></div>
      </div>
    </div>
  </section>

  <!-- HERO PROFILES GRID (GAMING, DESKTOP, WORKSTATION) -->
  <section class="profiles-grid">
    <!-- GAMING -->
    <div class="profile-card">
      <div class="profile-header">
        <div class="profile-title">🎮 Gaming</div>
        <div id="gamePill" class="pill neutral">±0.0 %</div>
      </div>
      <div class="score-row">
        <div class="score-big" id="gameScore">0<small> %</small></div>
        <div class="profile-meta" id="gameRating">Bewertung</div>
      </div>
      <div class="ratio-bar-wrap">
        <div class="ratio-bar-fill" id="gameBar" style="width: 50%;"></div>
      </div>
      <div class="profile-meta">
        <span id="gameTargetVal">Ziel: -</span>
        <span id="gameRefVal">Ref: -</span>
      </div>
    </div>

    <!-- BÜRO / DESKTOP -->
    <div class="profile-card">
      <div class="profile-header">
        <div class="profile-title">💼 Büro / Desktop</div>
        <div id="deskPill" class="pill neutral">±0.0 %</div>
      </div>
      <div class="score-row">
        <div class="score-big" id="deskScore">0<small> %</small></div>
        <div class="profile-meta" id="deskRating">Bewertung</div>
      </div>
      <div class="ratio-bar-wrap">
        <div class="ratio-bar-fill" id="deskBar" style="width: 50%;"></div>
      </div>
      <div class="profile-meta">
        <span id="deskTargetVal">Ziel: -</span>
        <span id="deskRefVal">Ref: -</span>
      </div>
    </div>

    <!-- WORKSTATION -->
    <div class="profile-card">
      <div class="profile-header">
        <div class="profile-title">⚙️ Workstation</div>
        <div id="workPill" class="pill neutral">±0.0 %</div>
      </div>
      <div class="score-row">
        <div class="score-big" id="workScore">0<small> %</small></div>
        <div class="profile-meta" id="workRating">Bewertung</div>
      </div>
      <div class="ratio-bar-wrap">
        <div class="ratio-bar-fill" id="workBar" style="width: 50%;"></div>
      </div>
      <div class="profile-meta">
        <span id="workTargetVal">Ziel: -</span>
        <span id="workRefVal">Ref: -</span>
      </div>
    </div>
  </section>

  <!-- HARDWARE COMPONENT DETAILS -->
  <section class="components-grid">
    <!-- CPU -->
    <div class="comp-card">
      <div class="comp-header">
        <div class="comp-title">🖥️ Prozessor (CPU)</div>
        <div class="comp-sub" id="cpuOverallSub">Single- & Multi-Thread</div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">Single-Thread (ST)</span>
          <div class="metric-vals">
            <span class="metric-curr" id="cpuStVal">-</span>
            <span class="metric-ref" id="cpuStRef">-</span>
            <span class="pill neutral" id="cpuStPill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="cpuStBar"></div>
        </div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">Multi-Thread (MT)</span>
          <div class="metric-vals">
            <span class="metric-curr" id="cpuMtVal">-</span>
            <span class="metric-ref" id="cpuMtRef">-</span>
            <span class="pill neutral" id="cpuMtPill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="cpuMtBar"></div>
        </div>
      </div>
    </div>

    <!-- GPU -->
    <div class="comp-card">
      <div class="comp-header">
        <div class="comp-title">🎮 Grafik (GPU)</div>
        <div class="comp-sub" id="gpuOverallSub">Rendertest & Frametimes</div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">Renderleistung (Ø FPS)</span>
          <div class="metric-vals">
            <span class="metric-curr" id="gpuRendVal">-</span>
            <span class="metric-ref" id="gpuRendRef">-</span>
            <span class="pill neutral" id="gpuRendPill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="gpuRendBar"></div>
        </div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">1 %-Low FPS</span>
          <div class="metric-vals">
            <span class="metric-curr" id="gpuRend1Val">-</span>
            <span class="metric-ref" id="gpuRend1Ref">-</span>
            <span class="pill neutral" id="gpuRend1Pill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="gpuRend1Bar"></div>
        </div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">0,1 %-Low FPS</span>
          <div class="metric-vals">
            <span class="metric-curr" id="gpuRend01Val">-</span>
            <span class="metric-ref" id="gpuRend01Ref">-</span>
            <span class="pill neutral" id="gpuRend01Pill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="gpuRend01Bar"></div>
        </div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">Mikroruckler (% > 50 ms)</span>
          <div class="metric-vals">
            <span class="metric-curr" id="gpuStutterVal">-</span>
            <span class="metric-ref" id="gpuStutterRef">-</span>
            <span class="pill neutral" id="gpuStutterPill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="gpuStutterBar"></div>
        </div>
      </div>
    </div>

    <!-- RAM -->
    <div class="comp-card">
      <div class="comp-header">
        <div class="comp-title">🧠 Arbeitsspeicher (RAM)</div>
        <div class="comp-sub" id="ramOverallSub">Durchsatz & Zugriffszeit</div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">Lesen (GB/s)</span>
          <div class="metric-vals">
            <span class="metric-curr" id="ramReadVal">-</span>
            <span class="metric-ref" id="ramReadRef">-</span>
            <span class="pill neutral" id="ramReadPill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="ramReadBar"></div>
        </div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">Kopieren (GB/s)</span>
          <div class="metric-vals">
            <span class="metric-curr" id="ramCopyVal">-</span>
            <span class="metric-ref" id="ramCopyRef">-</span>
            <span class="pill neutral" id="ramCopyPill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="ramCopyBar"></div>
        </div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">Latenz (ns, niedriger ist besser)</span>
          <div class="metric-vals">
            <span class="metric-curr" id="ramLatVal">-</span>
            <span class="metric-ref" id="ramLatRef">-</span>
            <span class="pill neutral" id="ramLatPill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="ramLatBar"></div>
        </div>
      </div>
    </div>

    <!-- DISK -->
    <div class="comp-card">
      <div class="comp-header">
        <div class="comp-title">💾 Datenträger (Storage)</div>
        <div class="comp-sub" id="diskOverallSub">Sequentiell & 4K-Zufall</div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">Sequentiell Lesen (MB/s)</span>
          <div class="metric-vals">
            <span class="metric-curr" id="diskSrVal">-</span>
            <span class="metric-ref" id="diskSrRef">-</span>
            <span class="pill neutral" id="diskSrPill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="diskSrBar"></div>
        </div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">Sequentiell Schreiben (MB/s)</span>
          <div class="metric-vals">
            <span class="metric-curr" id="diskSwVal">-</span>
            <span class="metric-ref" id="diskSwRef">-</span>
            <span class="pill neutral" id="diskSwPill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="diskSwBar"></div>
        </div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">4K Zufall QD1 (IOPS)</span>
          <div class="metric-vals">
            <span class="metric-curr" id="diskR1Val">-</span>
            <span class="metric-ref" id="diskR1Ref">-</span>
            <span class="pill neutral" id="diskR1Pill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="diskR1Bar"></div>
        </div>
      </div>

      <div class="metric-row">
        <div class="metric-top">
          <span class="metric-name">4K Zufall 8 Threads (IOPS)</span>
          <div class="metric-vals">
            <span class="metric-curr" id="diskR8Val">-</span>
            <span class="metric-ref" id="diskR8Ref">-</span>
            <span class="pill neutral" id="diskR8Pill">±0 %</span>
          </div>
        </div>
        <div class="metric-bar-wrap">
          <div class="metric-bar-fill" id="diskR8Bar"></div>
        </div>
      </div>
    </div>
  </section>

  <!-- TELEMETRIE & LASTTEST -->
  <section class="telemetry-card">
    <div class="telemetry-header">
      <div>
        <h2 style="font-size: 1.15rem; font-weight: 600;">🔥 Lasttest-Telemetrie & Sensorverlauf</h2>
        <p style="font-size: 0.82rem; color: var(--text-muted);">Zeitreihen für Temperatur (°C) und Kerntakt (GHz/MHz) über die Belastungsdauer</p>
      </div>

      <div class="telemetry-stats-bar">
        <div class="stat-badge">
          <div class="stat-badge-lbl">CPU MAX</div>
          <div class="stat-badge-val" id="statCpuTemp">-</div>
        </div>
        <div class="stat-badge">
          <div class="stat-badge-lbl">GPU MAX</div>
          <div class="stat-badge-val" id="statGpuTemp">-</div>
        </div>
        <div class="stat-badge">
          <div class="stat-badge-lbl">Ø TAKT</div>
          <div class="stat-badge-val" id="statCpuClock">-</div>
        </div>
        <div class="stat-badge">
          <div class="stat-badge-lbl">DROSSELUNG</div>
          <div class="stat-badge-val" id="statThrottle">-</div>
        </div>
        <div class="stat-badge">
          <div class="stat-badge-lbl">>50 MS PAUSEN</div>
          <div class="stat-badge-val" id="statPauses">-</div>
        </div>
      </div>
    </div>

    <!-- THROTTLE WARNING BANNER -->
    <div id="throttleBanner" class="throttle-banner ok">
      <span id="throttleIcon">✔️</span>
      <span id="throttleText">Keine thermische Drosselung festgestellt. Takt und Kühlung stabil.</span>
    </div>

    <!-- CANVAS TELEMETRY CHART -->
    <div class="chart-container" id="chartWrapper">
      <canvas id="telemetryCanvas"></canvas>
      <div id="chartTooltip" class="chart-tooltip"></div>
    </div>

    <div class="chart-legend">
      <div class="legend-item"><div class="legend-color" style="background: var(--curve-temp);"></div><span>CPU Temperatur (°C)</span></div>
      <div class="legend-item"><div class="legend-color" style="background: var(--curve-mhz);"></div><span>CPU Takt (GHz)</span></div>
      <div class="legend-item" id="gpuLegendItem" style="display: none;"><div class="legend-color" style="background: var(--curve-gpu);"></div><span>GPU Temperatur (°C)</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #E81123; border: 1px dashed #E81123; height: 2px;"></div><span>TjMax Grenze</span></div>
    </div>
  </section>

  <!-- FOOTER -->
  <footer>
    Leos Minibench v3.3 &middot; Fluent 2 Benchmark- &amp; Diagnose-Dashboard &middot; 100 % Offline &middot; UTF-8
  </footer>

</div>

<script>
/* __DASHBOARD_DATA__ */
window.MINIBENCH_DASHBOARD_DATA = window.MINIBENCH_DASHBOARD_DATA || null;

(function() {
  'use strict';

  let data = window.MINIBENCH_DASHBOARD_DATA;
  let currentTarget = null;
  let currentRef = null;

  // DOM-Elemente
  const themeToggle = document.getElementById('themeToggle');
  const targetSelect = document.getElementById('targetSelect');
  const refSelect = document.getElementById('refSelect');
  const swapBtn = document.getElementById('swapBtn');
  const canvas = document.getElementById('telemetryCanvas');
  const chartWrapper = document.getElementById('chartWrapper');
  const tooltip = document.getElementById('chartTooltip');

  // THEME MANAGEMENT
  function initTheme() {
    const saved = localStorage.getItem('minibench_theme');
    const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    const isDark = saved ? saved === 'dark' : prefersDark;
    setTheme(isDark);
  }

  function setTheme(isDark) {
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
    themeToggle.setAttribute('aria-checked', isDark ? 'true' : 'false');
    localStorage.setItem('minibench_theme', isDark ? 'dark' : 'light');
    renderChart();
  }

  themeToggle.addEventListener('click', () => {
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    setTheme(!isDark);
  });

  // INITIALISIERUNG
  function init() {
    initTheme();
    if (!data || (!data.Systems && !data.References)) {
      console.warn('Keine Benchmark-Daten eingebettet.');
      return;
    }

    populateSelects();

    // Standardauswahl
    if (data.Systems && data.Systems.length > 0) {
      targetSelect.value = String(data.Systems[0].Id);
    }

    if (data.References && data.References.length > 0) {
      const mid = data.References.find(r => r.DisplayName.includes('Mittelklasse')) || data.References[0];
      refSelect.value = String(mid.Id);
    } else if (data.Systems && data.Systems.length > 1) {
      refSelect.value = String(data.Systems[1].Id);
    }

    updateDashboard();

    targetSelect.addEventListener('change', updateDashboard);
    refSelect.addEventListener('change', updateDashboard);
    swapBtn.addEventListener('click', () => {
      const t = targetSelect.value;
      const r = refSelect.value;
      targetSelect.value = r;
      refSelect.value = t;
      updateDashboard();
    });

    window.addEventListener('resize', renderChart);
  }

  function getSystemById(id) {
    if (!data || id === null || id === undefined) return null;
    const targetId = String(id);
    const all = [ ...(data.Systems || []), ...(data.References || []) ];
    return all.find(s => String(s.Id) === targetId) || null;
  }

  function populateSelects() {
    targetSelect.innerHTML = '';
    refSelect.innerHTML = '';

    const sysGroup = document.createElement('optgroup');
    sysGroup.label = 'Geprüfte Systeme (Datenbank)';
    const refGroup = document.createElement('optgroup');
    refGroup.label = 'Referenzprofile (Eingebettet)';

    if (data.Systems) {
      data.Systems.forEach(s => {
        const opt = document.createElement('option');
        opt.value = String(s.Id);
        opt.textContent = s.DisplayName + (s.Datum ? ' (' + s.Datum + ')' : '');
        sysGroup.appendChild(opt);
      });
    }

    if (data.References) {
      data.References.forEach(r => {
        const opt = document.createElement('option');
        opt.value = String(r.Id);
        opt.textContent = '⭐ ' + r.DisplayName;
        refGroup.appendChild(opt);
      });
    }

    targetSelect.appendChild(sysGroup.cloneNode(true));
    targetSelect.appendChild(refGroup.cloneNode(true));

    refSelect.appendChild(refGroup.cloneNode(true));
    refSelect.appendChild(sysGroup.cloneNode(true));
  }

  function fmtNum(n, decimals = 0) {
    if (n === null || n === undefined || isNaN(n) || n === 0) return '-';
    return Number(n).toLocaleString('de-DE', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
  }

  function calcDelta(targetVal, refVal, lowerIsBetter = false) {
    if (!targetVal || !refVal || targetVal <= 0 || refVal <= 0) return null;
    let pct = 0;
    if (lowerIsBetter) {
      pct = ((refVal - targetVal) / refVal) * 100.0;
    } else {
      pct = ((targetVal - refVal) / refVal) * 100.0;
    }
    return pct;
  }

  function renderPill(el, pct, lowerIsBetter = false) {
    if (pct === null || isNaN(pct)) {
      el.className = 'pill neutral';
      el.textContent = 'n/v';
      return;
    }
    const sign = pct > 0 ? '+' : '';
    const txt = sign + pct.toFixed(1) + ' %';
    el.textContent = txt;
    if (pct >= 2.0) {
      el.className = 'pill ok';
    } else if (pct <= -5.0) {
      el.className = 'pill crit';
    } else {
      el.className = 'pill neutral';
    }
  }

  function getRatingWord(score) {
    if (score >= 130) return 'Exzellent';
    if (score >= 115) return 'Sehr gut';
    if (score >= 100) return 'Referenzniveau';
    if (score >= 85) return 'Gut';
    if (score >= 70) return 'Befriedigend';
    if (score >= 50) return 'Mäßig';
    return 'Schwach';
  }

  function updateDashboard() {
    currentTarget = getSystemById(targetSelect.value);
    currentRef = getSystemById(refSelect.value);
    if (!currentTarget || !currentRef) {
      console.warn('Systeme nicht gefunden:', targetSelect.value, refSelect.value);
      return;
    }

    // 1. SPECS
    function setTxt(id, val) { const el = document.getElementById(id); if (el) el.textContent = val; }
    setTxt('targetName', currentTarget.DisplayName || currentTarget.Computer || '-');
    setTxt('targetDate', currentTarget.Datum || 'Unbekannt');
    setTxt('targetCpu', currentTarget.Hardware && currentTarget.Hardware.CPU ? currentTarget.Hardware.CPU : '-');
    setTxt('targetGpu', currentTarget.Hardware && currentTarget.Hardware.GPU ? currentTarget.Hardware.GPU : '-');
    setTxt('targetRam', currentTarget.Hardware && currentTarget.Hardware.RAM ? currentTarget.Hardware.RAM : '-');
    setTxt('targetDisk', currentTarget.Hardware && currentTarget.Hardware.Datentraeger ? currentTarget.Hardware.Datentraeger : '-');

    setTxt('refName', currentRef.DisplayName || currentRef.Computer || '-');
    setTxt('refDate', currentRef.Datum || 'Referenz');
    setTxt('refCpu', currentRef.Hardware && currentRef.Hardware.CPU ? currentRef.Hardware.CPU : '-');
    setTxt('refGpu', currentRef.Hardware && currentRef.Hardware.GPU ? currentRef.Hardware.GPU : '-');
    setTxt('refRam', currentRef.Hardware && currentRef.Hardware.RAM ? currentRef.Hardware.RAM : '-');
    setTxt('refDisk', currentRef.Hardware && currentRef.Hardware.Datentraeger ? currentRef.Hardware.Datentraeger : '-');

    // 2. HERO PROFILES (GAMING, DESKTOP, WORKSTATION)
    updateProfileCard('game', currentTarget.Scores?.Gaming, currentRef.Scores?.Gaming);
    updateProfileCard('desk', currentTarget.Scores?.Desktop, currentRef.Scores?.Desktop);
    updateProfileCard('work', currentTarget.Scores?.Workstation, currentRef.Scores?.Workstation);

    // 3. HARDWARE COMPONENTS
    const tm = currentTarget.Metrics || {};
    const rm = currentRef.Metrics || {};

    // CPU
    updateMetricRow('cpuSt', tm.CPU_ST, rm.CPU_ST, '', 0);
    updateMetricRow('cpuMt', tm.CPU_MT, rm.CPU_MT, '', 0);

    // GPU
    updateMetricRow('gpuRend', tm.GPU_REND, rm.GPU_REND, ' FPS', 1);
    updateMetricRow('gpuRend1', tm.GPU_REND1, rm.GPU_REND1, ' FPS', 1);
    updateMetricRow('gpuRend01', tm.GPU_REND01, rm.GPU_REND01, ' FPS', 1);
    updateMetricRow('gpuStutter', tm.GPU_STUTTER, rm.GPU_STUTTER, ' %', 1, true);

    // RAM
    updateMetricRow('ramRead', tm.RAM_Lesen, rm.RAM_Lesen, ' GB/s', 1);
    updateMetricRow('ramCopy', tm.RAM_Kopieren, rm.RAM_Kopieren, ' GB/s', 1);
    updateMetricRow('ramLat', tm.RAM_Latenz, rm.RAM_Latenz, ' ns', 1, true);

    // DISK
    const td = tm.FastestDisk || {};
    const rd = rm.FastestDisk || {};
    document.getElementById('diskOverallSub').textContent = (td.Model || 'Speicher') + (td.Klasse ? ' (' + td.Klasse + ')' : '');
    updateMetricRow('diskSr', td.SR, rd.SR, ' MB/s', 0);
    updateMetricRow('diskSw', td.SW, rd.SW, ' MB/s', 0);
    updateMetricRow('diskR1', td.R1, rd.R1, ' IOPS', 0);
    updateMetricRow('diskR8', td.R8, rd.R8, ' IOPS', 0);

    // 4. TELEMETRIE & LASTTEST STATS
    const tel = currentTarget.Telemetry || {};
    function setStat(id, val) { const el = document.getElementById(id); if (el) el.textContent = val; }
    setStat('statCpuTemp', tel.CpuTempMax ? tel.CpuTempMax + ' °C' : '-');
    setStat('statGpuTemp', tel.GpuTempMax ? tel.GpuTempMax + ' °C' : '-');
    setStat('statCpuClock', tel.CpuMHzAvg ? (tel.CpuMHzAvg >= 1000 ? (tel.CpuMHzAvg / 1000).toFixed(2) + ' GHz' : tel.CpuMHzAvg + ' MHz') : '-');
    setStat('statThrottle', tel.Drosselung || 'keine');
    setStat('statPauses', tel.UnterbrechungenUeber50ms ? 'Auffällig' : 'Keine');

    const banner = document.getElementById('throttleBanner');
    const bIcon = document.getElementById('throttleIcon');
    const bText = document.getElementById('throttleText');

    if (banner && bIcon && bText) {
      if (tel.Drosselung === 'thermisch') {
        banner.className = 'throttle-banner thermisch';
        bIcon.textContent = '⚠️';
        bText.textContent = 'Thermische Drosselung aufgetreten! CPU erreichte ' + (tel.CpuTempMax || 95) + ' °C (TjMax). Taktabfall um ' + (tel.TaktAbfall ? tel.TaktAbfall.toFixed(0) : '20') + ' % belegt.';
      } else if (tel.Drosselung && tel.Drosselung !== 'keine') {
        banner.className = 'throttle-banner leistung';
        bIcon.textContent = 'ℹ️';
        bText.textContent = 'Drosselung / Begrenzung aktiv (' + tel.Drosselung + '): Takt sank unter Last' + (tel.TaktAbfall ? ' um ' + tel.TaktAbfall.toFixed(0) + ' %' : '') + '.';
      } else {
        banner.className = 'throttle-banner ok';
        bIcon.textContent = '✔️';
        bText.textContent = 'Keine thermische Drosselung belegt. CPU-Takt und Kühlsystem arbeiten unter Volllast stabil.';
      }
    }

    renderChart();
  }

  function updateProfileCard(prefix, tScore, rScore) {
    const scoreEl = document.getElementById(prefix + 'Score');
    const pillEl = document.getElementById(prefix + 'Pill');
    const barEl = document.getElementById(prefix + 'Bar');
    const ratingEl = document.getElementById(prefix + 'Rating');
    const tValEl = document.getElementById(prefix + 'TargetVal');
    const rValEl = document.getElementById(prefix + 'RefVal');

    if (!scoreEl || !pillEl || !barEl || !ratingEl || !tValEl || !rValEl) return;

    if (!tScore || !rScore) {
      scoreEl.innerHTML = '-<small> %</small>';
      pillEl.className = 'pill neutral';
      pillEl.textContent = 'n/v';
      barEl.style.width = '0%';
      ratingEl.textContent = '-';
      tValEl.textContent = 'Ziel: -';
      rValEl.textContent = 'Ref: -';
      return;
    }

    const relPct = Math.round((tScore / rScore) * 100.0);
    const delta = relPct - 100.0;

    scoreEl.innerHTML = relPct + '<small> %</small>';
    renderPill(pillEl, delta);
    ratingEl.textContent = getRatingWord(relPct);
    tValEl.textContent = 'Score: ' + fmtNum(tScore);
    rValEl.textContent = 'Ref: ' + fmtNum(rScore);

    const barW = Math.max(5, Math.min(100, (relPct / 150.0) * 100));
    barEl.style.width = barW + '%';
  }

  function updateMetricRow(id, targetVal, refVal, unit, decimals, lowerIsBetter = false) {
    const valEl = document.getElementById(id + 'Val');
    const refEl = document.getElementById(id + 'Ref');
    const pillEl = document.getElementById(id + 'Pill');
    const barEl = document.getElementById(id + 'Bar');

    if (!valEl || !refEl || !pillEl) return;

    valEl.textContent = (targetVal !== null && targetVal !== undefined && targetVal > 0) ? fmtNum(targetVal, decimals) + unit : '-';
    refEl.textContent = (refVal !== null && refVal !== undefined && refVal > 0) ? 'Ref: ' + fmtNum(refVal, decimals) + unit : '-';

    const delta = calcDelta(targetVal, refVal, lowerIsBetter);
    renderPill(pillEl, delta, lowerIsBetter);

    if (barEl) {
      if (targetVal > 0 && refVal > 0) {
        const ratio = (targetVal / Math.max(targetVal, refVal)) * 100;
        barEl.style.width = Math.max(2, Math.min(100, ratio)) + '%';
      } else if (targetVal > 0) {
        barEl.style.width = '80%';
      } else {
        barEl.style.width = '0%';
      }
    }
  }

  // PURE VANILLA CANVAS CHART RENDERING
  function renderChart() {
    if (!currentTarget) return;
    const series = currentTarget.Telemetry?.Series || [];
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    const dpr = window.devicePixelRatio || 1;
    const rect = chartWrapper.getBoundingClientRect();
    const width = rect.width;
    const height = rect.height;

    canvas.width = width * dpr;
    canvas.height = height * dpr;
    canvas.style.width = width + 'px';
    canvas.style.height = height + 'px';

    const ctx = canvas.getContext('2d');
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, width, height);

    if (series.length < 2) {
      ctx.fillStyle = isDark ? '#A0A0A0' : '#5F6368';
      ctx.font = '14px system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('Keine Zeitreihen-Messdaten für dieses System verfügbar.', width / 2, height / 2);
      return;
    }

    const padding = { top: 30, right: 60, bottom: 40, left: 55 };
    const chartW = width - padding.left - padding.right;
    const chartH = height - padding.top - padding.bottom;

    const tMax = series[series.length - 1].T || 120;
    const tempMax = 110;
    let maxMhz = 5000;
    series.forEach(pt => { if (pt.MHz && pt.MHz > maxMhz) maxMhz = pt.MHz * 1.1; });

    const getX = t => padding.left + (t / tMax) * chartW;
    const getYTemp = temp => padding.top + chartH - (temp / tempMax) * chartH;
    const getYMhz = mhz => padding.top + chartH - (mhz / maxMhz) * chartH;

    // GRID LINES
    ctx.strokeStyle = isDark ? '#363636' : '#ECEFF1';
    ctx.lineWidth = 1;
    ctx.fillStyle = isDark ? '#808080' : '#888888';
    ctx.font = '11px system-ui, sans-serif';

    // Temp Steps: 0, 25, 50, 75, 100 °C
    [0, 25, 50, 75, 100].forEach(deg => {
      const y = getYTemp(deg);
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(padding.left + chartW, y);
      ctx.stroke();

      ctx.textAlign = 'right';
      ctx.fillText(deg + ' °C', padding.left - 8, y + 4);
    });

    // Mhz Right Axis Labels
    [0, 2000, 4000, 6000].filter(m => m <= maxMhz).forEach(m => {
      const y = getYMhz(m);
      ctx.textAlign = 'left';
      ctx.fillText((m / 1000).toFixed(1) + ' GHz', padding.left + chartW + 8, y + 4);
    });

    // X Axis Time Labels
    ctx.textAlign = 'center';
    const xStep = tMax <= 120 ? 30 : 60;
    for (let sec = 0; sec <= tMax; sec += xStep) {
      const x = getX(sec);
      const mm = Math.floor(sec / 60);
      const ss = Math.floor(sec % 60);
      const timeStr = String(mm).padStart(2, '0') + ':' + String(ss).padStart(2, '0');
      ctx.fillText(timeStr, x, padding.top + chartH + 20);
    }

    // TJMAX GUIDELINE
    const tjMax = currentTarget.Telemetry?.TjMax || 100;
    const yTj = getYTemp(tjMax);
    ctx.save();
    ctx.setLineDash([4, 4]);
    ctx.strokeStyle = 'rgba(232, 17, 35, 0.6)';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(padding.left, yTj);
    ctx.lineTo(padding.left + chartW, yTj);
    ctx.stroke();
    ctx.fillStyle = 'rgba(232, 17, 35, 0.85)';
    ctx.textAlign = 'left';
    ctx.fillText('TjMax (' + tjMax + ' °C)', padding.left + 8, yTj - 6);
    ctx.restore();

    // THROTTLE VERTICAL LINE
    const events = currentTarget.Telemetry?.ThrottleEvents || [];
    events.forEach(ev => {
      const xEv = getX(ev.T);
      ctx.save();
      ctx.setLineDash([3, 3]);
      ctx.strokeStyle = '#D13438';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(xEv, padding.top);
      ctx.lineTo(xEv, padding.top + chartH);
      ctx.stroke();

      // Flag Banner
      ctx.fillStyle = isDark ? '#442726' : '#FDE7E9';
      ctx.fillRect(xEv - 4, padding.top + 6, 120, 20);
      ctx.strokeStyle = '#D13438';
      ctx.strokeRect(xEv - 4, padding.top + 6, 120, 20);
      ctx.fillStyle = '#D13438';
      ctx.font = '10px system-ui, sans-serif';
      ctx.textAlign = 'left';
      ctx.fillText('⚠️ ' + (ev.Label || 'Drosselung'), xEv + 2, padding.top + 20);
      ctx.restore();
    });

    // CURVE: CPU CLOCK (BLUE)
    ctx.save();
    ctx.strokeStyle = isDark ? '#4CC2FF' : '#0078D4';
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    let started = false;
    series.forEach(pt => {
      if (pt.MHz) {
        const x = getX(pt.T);
        const y = getYMhz(pt.MHz);
        if (!started) { ctx.moveTo(x, y); started = true; } else { ctx.lineTo(x, y); }
      }
    });
    ctx.stroke();
    ctx.restore();

    // CURVE: CPU TEMPERATURE (RED) WITH GRADIENT AREA
    ctx.save();
    ctx.strokeStyle = isDark ? '#FF5A5A' : '#E81123';
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    let startedT = false;
    series.forEach(pt => {
      if (pt.Temp) {
        const x = getX(pt.T);
        const y = getYTemp(pt.Temp);
        if (!startedT) { ctx.moveTo(x, y); startedT = true; } else { ctx.lineTo(x, y); }
      }
    });
    ctx.stroke();

    // Area fill
    ctx.lineTo(getX(series[series.length - 1].T), padding.top + chartH);
    ctx.lineTo(getX(series[0].T), padding.top + chartH);
    ctx.closePath();
    const grad = ctx.createLinearGradient(0, padding.top, 0, padding.top + chartH);
    grad.addColorStop(0, isDark ? 'rgba(255, 90, 90, 0.2)' : 'rgba(232, 17, 35, 0.15)');
    grad.addColorStop(1, 'rgba(232, 17, 35, 0.0)');
    ctx.fillStyle = grad;
    ctx.fill();
    ctx.restore();

    // HOVER INTERACTION
    canvas.onmousemove = function(e) {
      const mouseRect = canvas.getBoundingClientRect();
      const mouseX = e.clientX - mouseRect.left;
      if (mouseX < padding.left || mouseX > padding.left + chartW) {
        tooltip.style.display = 'none';
        renderChartStatic();
        return;
      }

      const ratio = (mouseX - padding.left) / chartW;
      const targetT = ratio * tMax;

      let closest = series[0];
      let minDiff = Infinity;
      series.forEach(pt => {
        const diff = Math.abs(pt.T - targetT);
        if (diff < minDiff) { minDiff = diff; closest = pt; }
      });

      if (!closest) return;

      renderChartStatic();

      const cx = getX(closest.T);
      const cyTemp = closest.Temp ? getYTemp(closest.Temp) : null;
      const cyMhz = closest.MHz ? getYMhz(closest.MHz) : null;

      // Crosshair
      ctx.save();
      ctx.strokeStyle = isDark ? '#707070' : '#A0A0A0';
      ctx.setLineDash([2, 2]);
      ctx.beginPath();
      ctx.moveTo(cx, padding.top);
      ctx.lineTo(cx, padding.top + chartH);
      ctx.stroke();

      // Highlight dots
      if (cyTemp) {
        ctx.fillStyle = isDark ? '#FF5A5A' : '#E81123';
        ctx.beginPath();
        ctx.arc(cx, cyTemp, 5, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = '#FFFFFF';
        ctx.lineWidth = 2;
        ctx.stroke();
      }
      if (cyMhz) {
        ctx.fillStyle = isDark ? '#4CC2FF' : '#0078D4';
        ctx.beginPath();
        ctx.arc(cx, cyMhz, 5, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = '#FFFFFF';
        ctx.lineWidth = 2;
        ctx.stroke();
      }
      ctx.restore();

      // Tooltip HTML
      const mm = Math.floor(closest.T / 60);
      const ss = Math.floor(closest.T % 60);
      const timeStr = String(mm).padStart(2, '0') + ':' + String(ss).padStart(2, '0');

      tooltip.innerHTML = `
        <div style="font-weight: 700; margin-bottom: 4px; border-bottom: 1px solid var(--card-border); padding-bottom: 2px;">
          ⏱️ Zeit: ${timeStr} (${closest.T.toFixed(0)} s)
        </div>
        <div style="color: var(--curve-temp); font-weight: 600;">
          🌡️ CPU-Temperatur: ${closest.Temp ? closest.Temp.toFixed(1) + ' °C' : '-'}
        </div>
        <div style="color: var(--curve-mhz); font-weight: 600;">
          ⚡ CPU-Takt: ${closest.MHz ? (closest.MHz / 1000).toFixed(2) + ' GHz (' + closest.MHz + ' MHz)' : '-'}
        </div>
        ${closest.GpuTemp ? '<div style="color: var(--curve-gpu);">🎮 GPU-Temp: ' + closest.GpuTemp.toFixed(1) + ' °C</div>' : ''}
        ${closest.CpuW ? '<div>💡 CPU-Paket: ' + closest.CpuW.toFixed(1) + ' W</div>' : ''}
        ${closest.Fps ? '<div>📊 Rendertest: ' + closest.Fps.toFixed(1) + ' FPS</div>' : ''}
      `;

      tooltip.style.display = 'block';
      let tooltipX = cx + 15;
      if (tooltipX + 180 > width) tooltipX = cx - 190;
      tooltip.style.left = tooltipX + 'px';
      tooltip.style.top = Math.max(10, (cyTemp || padding.top) - 30) + 'px';
    };

    canvas.onmouseleave = function() {
      tooltip.style.display = 'none';
      renderChartStatic();
    };

    function renderChartStatic() {
      renderChartNoHover();
    }
  }

  function renderChartNoHover() {
    renderChart();
  }

  // DOM READY
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
</script>
</body>
</html>
'@
}

function New-BenchDashboardHtml {
    [CmdletBinding()]
    param(
        [object]$DashboardData = $null,
        [string]$DatabaseDir = '',
        [string]$ReportDir = '',
        [string[]]$SystemPaths = @(),
        [string]$OutputPath = '',
        [switch]$PassThru
    )

    $data = $DashboardData
    if (-not $data) {
        $data = Export-BenchDashboardData -DatabaseDir $DatabaseDir -ReportDir $ReportDir -SystemPaths $SystemPaths -IncludeReferences
    }

    $json = $data | ConvertTo-Json -Depth 10 -Compress
    $template = Get-BenchDashboardHtmlTemplate

    # Daten einbetten
    $html = $template.Replace('window.MINIBENCH_DASHBOARD_DATA = window.MINIBENCH_DASHBOARD_DATA || null;', ('window.MINIBENCH_DASHBOARD_DATA = ' + $json + ';'))

    if ($OutputPath) {
        $outDir = Split-Path $OutputPath -Parent
        if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($OutputPath, ($html -replace "`r?`n", "`r`n"), $utf8Bom)
    }

    if ($PassThru) { return $html }
    return $OutputPath
}

function Export-BenchDashboardHtml {
    [CmdletBinding()]
    param(
        [string]$OutputPath = '',
        [string]$DatabaseDir = '',
        [string]$ReportDir = ''
    )

    $target = $OutputPath
    if (-not $target) {
        if ($script:DataDir -and (Test-Path -LiteralPath $script:DataDir)) {
            $target = Join-Path $script:DataDir 'Berichte\Dashboard.html'
        } elseif (Test-Path -LiteralPath 'Minibench-Daten\Berichte') {
            $target = (Convert-Path 'Minibench-Daten\Berichte') + '\Dashboard.html'
        } elseif (Test-Path -LiteralPath 'Aktueller Build\Minibench-Daten\Berichte') {
            $target = (Convert-Path 'Aktueller Build\Minibench-Daten\Berichte') + '\Dashboard.html'
        } else {
            $target = Join-Path (Get-Location) 'Dashboard.html'
        }
    }

    return (New-BenchDashboardHtml -OutputPath $target -DatabaseDir $DatabaseDir -ReportDir $ReportDir)
}

function Show-BenchDashboard {
    [CmdletBinding()]
    param(
        [string]$DatabaseDir = '',
        [string]$ReportDir = '',
        [string]$OutputPath = ''
    )

    $f = Export-BenchDashboardHtml -OutputPath $OutputPath -DatabaseDir $DatabaseDir -ReportDir $ReportDir
    if ($f -and (Test-Path -LiteralPath $f)) {
        Start-Process $f
    }
    return $f
}