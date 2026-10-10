# =====================================================================================
#             LEOS MINIBENCH: BENCHMARK- & DIAGNOSE-DASHBOARD (HTML5/VANILLA-JS)
# =====================================================================================
# Wiederverwendbare Daten- und HTML-Bausteine für das interaktive Benchmark- und
# Diagnose-Dashboard (Fluent 2 / Wintoys-Look, Multi-System-Vergleich, 100 % offline-fähig).

function Export-BenchDashboardData {
    [CmdletBinding()]
    param(
        [Alias('DatenOrdner', 'AppDir')]
        [string]$DatabaseDir = '',
        [string]$ReportDir = '',
        [string[]]$SystemPaths = @(),
        [switch]$IncludeReferences = $true,
        [string]$OutputPath = '',
        [switch]$AsJson
    )

    # 1. Datenbank- und Berichtsverzeichnisse ermitteln
    $dbDir = $DatabaseDir
    if ($dbDir -and (Test-Path -LiteralPath (Join-Path $dbDir 'Datenbank'))) {
        $dbDir = (Join-Path $dbDir 'Datenbank')
    }
    if (-not $dbDir -or -not (Test-Path -LiteralPath $dbDir)) {
        if ($script:DbDir -and (Test-Path -LiteralPath $script:DbDir)) { $dbDir = $script:DbDir }
        elseif (Test-Path -LiteralPath 'Minibench-Daten\Datenbank') { $dbDir = (Convert-Path 'Minibench-Daten\Datenbank') }
        elseif (Test-Path -LiteralPath (Join-Path (Get-Location) 'Minibench-Daten\Datenbank')) { $dbDir = (Join-Path (Get-Location) 'Minibench-Daten\Datenbank') }
        else { $dbDir = '' }
    }

    $repDir = $ReportDir
    if (-not $repDir -or -not (Test-Path -LiteralPath $repDir)) {
        if ($script:ReportDir -and (Test-Path -LiteralPath $script:ReportDir)) { $repDir = $script:ReportDir }
        elseif (Test-Path -LiteralPath 'Minibench-Daten\Berichte') { $repDir = (Convert-Path 'Minibench-Daten\Berichte') }
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
            $zipPath = Join-Path $cand 'Anhang.zip'
            if (Test-Path -LiteralPath $rawCsv) {
                try { $lines = @([System.IO.File]::ReadAllLines($rawCsv, [System.Text.Encoding]::UTF8)); if ($lines.Count -gt 1) { break } } catch { }
            }
            if (Test-Path -LiteralPath $zipPath) {
                try {
                    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
                    $entry = $zip.GetEntry('Lasttest-Verlauf.csv')
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
        }
        return $lines
    }

    $extractReportTxt = {
        param([string]$LeafFolder)
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
            $txtPath = Join-Path $cand 'Diagnosebericht.txt'
            if (Test-Path -LiteralPath $txtPath) {
                try { return [System.IO.File]::ReadAllText($txtPath, [System.Text.Encoding]::UTF8) } catch { }
            }
            $zipPath = Join-Path $cand 'Anhang.zip'
            if (Test-Path -LiteralPath $zipPath) {
                try {
                    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
                    $entry = $zip.GetEntry('Diagnosebericht.txt')
                    if ($entry) {
                        $sr = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
                        $content = $sr.ReadToEnd()
                        $sr.Dispose()
                        $zip.Dispose()
                        return $content
                    }
                    $zip.Dispose()
                } catch { }
            }
        }
        return ''
    }

    $getLasttestArt = {
        param([string]$Summary, [int]$SeriesDuration = 0)
        $min = 0
        if ($Summary -match 'Dauer\s*(\d+):(\d+):(\d+)') {
            $hrs = [int]$matches[1]; $m = [int]$matches[2]; $s = [int]$matches[3]
            $min = [math]::Max(1, [int][math]::Round(($hrs * 3600 + $m * 60 + $s) / 60.0))
        } elseif ($SeriesDuration -gt 0) {
            $min = [math]::Max(1, [int][math]::Round($SeriesDuration / 60.0))
        }
        $minStr = if ($min -gt 0) { ' {0} Min.' -f $min } else { '' }

        $hasCpu = ($Summary -match '\bProzessor\b')
        $hasGpu = ($Summary -match '\bGrafik\b')
        $hasRam = ($Summary -match '\bArbeitsspeicher\b')
        $hasDisk = ($Summary -match '\bDatenträger\b|\bDatentraeger\b')

        if ($hasCpu -and $hasGpu -and ($hasRam -or $hasDisk)) {
            return ('Lasttest Voll{0}' -f $minStr)
        } elseif ($hasCpu -and $hasGpu) {
            return ('Lasttest CPU & Grafik{0}' -f $minStr)
        } elseif ($hasCpu) {
            return ('Lasttest CPU{0}' -f $minStr)
        } elseif ($hasGpu) {
            return ('Lasttest Grafik{0}' -f $minStr)
        } elseif ($hasRam) {
            return ('Lasttest RAM{0}' -f $minStr)
        } elseif ($Summary -match '^Lasttest\s+(.+)$') {
            return $Summary
        } elseif ($min -gt 0) {
            return ('Lasttest{0}' -f $minStr)
        } else {
            return 'Lasttest'
        }
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
        $cpuRaw = $(if ($j.Hardware -and $j.Hardware.CPU) { [string]$j.Hardware.CPU } else { '' })
        $kerne = $(if ($j.Hardware -and $null -ne $j.Hardware.Kerne) { [int]$j.Hardware.Kerne } else { $null })
        $threads = $(if ($j.Hardware -and $null -ne $j.Hardware.Threads) { [int]$j.Hardware.Threads } else { $null })

        if ($null -eq $kerne -or $null -eq $threads) {
            if ($cpuRaw -match '(\d+)\s*Kerne,\s*(\d+)\s*Threads') {
                $kerne = [int]$Matches[1]; $threads = [int]$Matches[2]
            } else {
                $txtReport = & $extractReportTxt ([string]$j.Ordner)
                if ($txtReport -and $txtReport -match '(?m)^\s*Kerne\s*/\s*Threads\s*:\s*(\d+)\s*/\s*(\d+)') {
                    $kerne = [int]$Matches[1]; $threads = [int]$Matches[2]
                } elseif ($txtReport -and $txtReport -match '(\d+)\s*Kerne,\s*(\d+)\s*Threads') {
                    $kerne = [int]$Matches[1]; $threads = [int]$Matches[2]
                }
            }
        }

        $cleanCpu = if (Get-Command Get-CpuAnzeigename -ErrorAction SilentlyContinue) { Get-CpuAnzeigename $cpuRaw } else { $cpuRaw }
        if ($null -ne $kerne -and $null -ne $threads -and $kerne -gt 0 -and $threads -gt 0) {
            $cpuFull = '{0} ({1} Kerne, {2} Threads)' -f $cleanCpu, $kerne, $threads
            $ktDisplay = '{0} / {1}' -f $kerne, $threads
        } else {
            $cpuFull = $cleanCpu
            $ktDisplay = 'n/v'
        }

        $ram = $(if ($j.Hardware -and $j.Hardware.RAM) { [string]$j.Hardware.RAM } else { '' })
        $gpu = $(if ($j.Hardware -and $j.Hardware.GPU) { [string]$j.Hardware.GPU } elseif ($j.Hardware -and $j.Hardware.GPUGemessen) { [string]$j.Hardware.GPUGemessen } else { '' })
        $diskInfo = $(if ($j.Hardware -and $j.Hardware.Datentraeger) { [string]$j.Hardware.Datentraeger } else { '' })
        $mb = $(if ($j.Hardware -and $j.Hardware.Mainboard) { [string]$j.Hardware.Mainboard } else { '' })
        $os = $(if ($j.Hardware -and $j.Hardware.Betriebssystem) { [string]$j.Hardware.Betriebssystem } elseif ($j.System) { [string]$j.System } else { '' })
        $winInst = $(if ($j.Hardware -and $j.Hardware.WindowsInstalliert) { [string]$j.Hardware.WindowsInstalliert } else { '' })
        $sysBoard = $(if ($j.System) { [string]$j.System } else { '' })

        # Befunde
        $crit = 0; $warn = 0; $info = 0; $liste = @()
        if ($j.Befunde -is [System.Collections.IDictionary] -or ($j.Befunde -and $j.Befunde.PSObject.Properties['Kritisch'])) {
            $crit = [int]$j.Befunde.Kritisch
            $warn = [int]$j.Befunde.Warnungen
            $info = [int]$j.Befunde.Hinweise
            if ($j.Befunde.Liste) { $liste = @($j.Befunde.Liste | ForEach-Object { [string]$_ }) }
        } elseif ($j.Befunde -is [string] -and $j.Befunde -match '^(\d+)/(\d+)/(\d+)$') {
            $crit = [int]$Matches[1]; $warn = [int]$Matches[2]; $info = [int]$Matches[3]
        }
        if ($j.BefundeDetails) {
            $liste = @($j.BefundeDetails | ForEach-Object {
                if ($_ -is [string]) { $_ }
                elseif ($_.Text) {
                    $st = $(if ($_.Stufe) { [string]$_.Stufe } else { 'Hinweis' }).ToUpperInvariant()
                    $br = $(if ($_.Bereich) { [string]$_.Bereich } else { 'System' })
                    '[{0}] {1}: {2}' -f $st, $br, $_.Text
                } else { [string]$_ }
            })
        }
        $befunde = [ordered]@{
            Kritisch  = $crit
            Warnungen = $warn
            Hinweise  = $info
            Liste     = $liste
        }

        # Benchmark-Kernmesswerte
        $cpuSt = $(if ($werte.ContainsKey('CPU|ST')) { [double]$werte['CPU|ST'] } else { 0.0 })
        $cpuMt = $(if ($werte.ContainsKey('CPU|MT')) { [double]$werte['CPU|MT'] } else { 0.0 })
        $cpuAes = $(if ($werte.ContainsKey('CPU|AES')) { [double]$werte['CPU|AES'] } else { 0.0 })
        $cpuSha = $(if ($werte.ContainsKey('CPU|SHA')) { [double]$werte['CPU|SHA'] } else { 0.0 })
        $cpuDefl = $(if ($werte.ContainsKey('CPU|DEFL')) { [double]$werte['CPU|DEFL'] } else { 0.0 })

        $ramLesen = $(if ($werte.ContainsKey('RAM|Lesen')) { [double]$werte['RAM|Lesen'] } else { 0.0 })
        $ramSchreiben = $(if ($werte.ContainsKey('RAM|Schreiben')) { [double]$werte['RAM|Schreiben'] } else { 0.0 })
        $ramKopieren = $(if ($werte.ContainsKey('RAM|Kopieren')) { [double]$werte['RAM|Kopieren'] } else { 0.0 })
        $ramLatenz = $(if ($werte.ContainsKey('RAM|Latenz')) { [double]$werte['RAM|Latenz'] } else { 0.0 })

        $gpuRend = $(if ($werte.ContainsKey('GPU|REND')) { [double]$werte['GPU|REND'] } else { 0.0 })
        $gpuRend1 = $(if ($werte.ContainsKey('GPU|REND1')) { [double]$werte['GPU|REND1'] } else { 0.0 })
        $gpuRend01 = $(if ($werte.ContainsKey('GPU|REND01')) { [double]$werte['GPU|REND01'] } else { 0.0 })
        $gpuStutter = $(if ($werte.ContainsKey('GPU|STUTTER')) { [double]$werte['GPU|STUTTER'] } else { 0.0 })
        $gpuVmb = $(if ($werte.ContainsKey('GPU|VMB')) { [double]$werte['GPU|VMB'] } else { 0.0 })

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
            if ($idxMhz -lt 0) { $idxMhz = [array]::IndexOf($header, 'CpuMHzMax') }
            $idxCpuTemp = [array]::IndexOf($header, 'CpuTemp')
            if ($idxCpuTemp -lt 0) { $idxCpuTemp = [array]::IndexOf($header, 'Temp') }
            $idxCpuW = [array]::IndexOf($header, 'CpuW')
            if ($idxCpuW -lt 0) { $idxCpuW = [array]::IndexOf($header, 'Leistung') }
            $idxGpuTemp = [array]::IndexOf($header, 'GpuTemp')
            $idxGpuMhz = [array]::IndexOf($header, 'GpuMHz')
            $idxGpuW = [array]::IndexOf($header, 'GpuW')
            $idxIGpuTemp = [array]::IndexOf($header, 'IGpuTemp')
            $idxIGpuMhz = [array]::IndexOf($header, 'IGpuMHz')
            $idxIGpuW = [array]::IndexOf($header, 'IGpuW')
            $idxFps = [array]::IndexOf($header, 'Fps')

            $step = [math]::Max(1, [int][math]::Floor(($csvLines.Count - 1) / 70))
            for ($r = 1; $r -lt $csvLines.Count; $r += $step) {
                $cols = @($csvLines[$r] -split ';') | ForEach-Object { $_.Trim('"').Trim() }
                if ($cols.Count -le $idxT -or $cols[$idxT] -eq '') { continue }
                $t = 0.0; [double]::TryParse($cols[$idxT].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$t) | Out-Null
                $mhz = 0.0; if ($idxMhz -ge 0 -and $cols.Count -gt $idxMhz -and $cols[$idxMhz]) { [double]::TryParse($cols[$idxMhz].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$mhz) | Out-Null }
                $temp = 0.0; if ($idxCpuTemp -ge 0 -and $cols.Count -gt $idxCpuTemp -and $cols[$idxCpuTemp]) { [double]::TryParse($cols[$idxCpuTemp].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$temp) | Out-Null }
                $gTemp = 0.0; if ($idxGpuTemp -ge 0 -and $cols.Count -gt $idxGpuTemp -and $cols[$idxGpuTemp]) { [double]::TryParse($cols[$idxGpuTemp].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$gTemp) | Out-Null }
                $w = 0.0; if ($idxCpuW -ge 0 -and $cols.Count -gt $idxCpuW -and $cols[$idxCpuW]) { [double]::TryParse($cols[$idxCpuW].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$w) | Out-Null }
                $gMhz = 0.0; if ($idxGpuMhz -ge 0 -and $cols.Count -gt $idxGpuMhz -and $cols[$idxGpuMhz]) { [double]::TryParse($cols[$idxGpuMhz].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$gMhz) | Out-Null }
                $gW = 0.0; if ($idxGpuW -ge 0 -and $cols.Count -gt $idxGpuW -and $cols[$idxGpuW]) { [double]::TryParse($cols[$idxGpuW].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$gW) | Out-Null }
                $igTemp = 0.0; if ($idxIGpuTemp -ge 0 -and $cols.Count -gt $idxIGpuTemp -and $cols[$idxIGpuTemp]) { [double]::TryParse($cols[$idxIGpuTemp].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$igTemp) | Out-Null }
                $igMhz = 0.0; if ($idxIGpuMhz -ge 0 -and $cols.Count -gt $idxIGpuMhz -and $cols[$idxIGpuMhz]) { [double]::TryParse($cols[$idxIGpuMhz].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$igMhz) | Out-Null }
                $igW = 0.0; if ($idxIGpuW -ge 0 -and $cols.Count -gt $idxIGpuW -and $cols[$idxIGpuW]) { [double]::TryParse($cols[$idxIGpuW].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$igW) | Out-Null }
                $fps = 0.0; if ($idxFps -ge 0 -and $cols.Count -gt $idxFps -and $cols[$idxFps]) { [double]::TryParse($cols[$idxFps].Replace(',', '.'), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$fps) | Out-Null }

                $series.Add([ordered]@{
                    T        = [math]::Round($t, 1)
                    Temp     = $(if ($temp -gt 0) { [math]::Round($temp, 1) } else { $null })
                    MHz      = $(if ($mhz -gt 0) { [math]::Round($mhz, 0) } else { $null })
                    CpuW     = $(if ($w -gt 0) { [math]::Round($w, 1) } else { $null })
                    GpuTemp  = $(if ($gTemp -gt 0) { [math]::Round($gTemp, 1) } else { $null })
                    GpuMHz   = $(if ($gMhz -gt 0) { [math]::Round($gMhz, 0) } else { $null })
                    GpuW     = $(if ($gW -gt 0) { [math]::Round($gW, 1) } else { $null })
                    IGpuTemp = $(if ($igTemp -gt 0) { [math]::Round($igTemp, 1) } else { $null })
                    IGpuMHz  = $(if ($igMhz -gt 0) { [math]::Round($igMhz, 0) } else { $null })
                    IGpuW    = $(if ($igW -gt 0) { [math]::Round($igW, 1) } else { $null })
                    Fps      = $(if ($fps -gt 0) { [math]::Round($fps, 1) } else { $null })
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

        # Ermittlung des Berichts-Pfads für Direktverlinkung (v3.52)
        $reportUrl = ''
        if (-not $isRef) {
            if ($j.BerichtPfad) {
                $reportUrl = [string]$j.BerichtPfad
            } elseif ($j.Ordner) {
                $pOrd = [string]$j.Ordner
                $pNorm = $pOrd -replace '\\', '/'
                if ($pNorm -match 'Diagnosebericht\.html$') {
                    $reportUrl = $pNorm
                } else {
                    $reportUrl = $pNorm.TrimEnd('/') + '/Diagnosebericht.html'
                }
            } elseif ($sourceFile -and (Split-Path $sourceFile -Parent)) {
                $parentDir = Split-Path $sourceFile -Parent
                $grandParent = Split-Path $parentDir -Parent
                if ($grandParent) {
                    $candRel = Join-Path $grandParent ('Berichte\' + (Split-Path $parentDir -Leaf) + '\Diagnosebericht.html')
                    if (Test-Path -LiteralPath $candRel) {
                        $reportUrl = (Split-Path $parentDir -Leaf) + '/Diagnosebericht.html'
                    } else {
                        # Suche nach Diagnosebericht.html im Geschwister-Ordner Berichte
                        $candRep = Join-Path $grandParent 'Berichte'
                        if (Test-Path -LiteralPath $candRep) {
                            $found = @(Get-ChildItem -LiteralPath $candRep -Filter 'Diagnosebericht.html' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like "*$($j.Computer)*" })
                            if ($found.Count) {
                                $folderLeaf = Split-Path (Split-Path $found[0].FullName -Parent) -Leaf
                                $reportUrl = $folderLeaf + '/Diagnosebericht.html'
                            }
                        }
                    }
                }
            }
            if (-not $reportUrl -and $j.Datum -and $j.Computer) {
                $dClean = ($j.Datum -replace '-', '') -replace ' ', '_' -replace ':', ''
                $reportUrl = ('{0}_{1}/Diagnosebericht.html' -f $j.Computer, $dClean)
            }
        }

        # URL-Pfad normalisieren: Relative Links relativ zu Dashboard.html (in Berichte/ gelegen)
        if ($reportUrl) {
            $reportUrl = $reportUrl -replace '\\', '/'
            $idx = $reportUrl.IndexOf('/Berichte/', [StringComparison]::OrdinalIgnoreCase)
            if ($idx -ge 0) {
                $reportUrl = $reportUrl.Substring($idx + 10)
            } else {
                $reportUrl = $reportUrl -replace '^Berichte/', ''
            }
            $reportUrl = $reportUrl.TrimStart('/')
        }

        $seriesDur = if ($series.Count -gt 0) { [int]$series[$series.Count - 1].T } else { 0 }
        $lasttestArt = & $getLasttestArt ([string]$j.Lasttest) $seriesDur

        return [ordered]@{
            Id          = $id
            ReportUrl   = $reportUrl
            Computer    = $comp
            DisplayName = $name
            Datum       = $datum
            IsReference = $isRef
            OS          = $os
            Hardware    = [ordered]@{
                CPU                = $cpuRaw
                CpuKurz            = $cleanCpu
                CleanCpu           = $cleanCpu
                CpuDisplay         = $cpuFull
                Kerne              = $kerne
                Threads            = $threads
                KerneThreads       = $ktDisplay
                RAM                = $ram
                GPU                = $gpu
                Datentraeger       = $diskInfo
                Mainboard          = $(if ($mb) { $mb } elseif ($sysBoard) { $sysBoard } else { '' })
                Betriebssystem     = $os
                WindowsInstalliert = $winInst
                FastestDisk        = $(if ($fastestDisk) { $fastestDisk.Model } else { '' })
                System             = $sysBoard
            }
            Befunde     = $befunde
            Scores      = [ordered]@{
                Overall     = $overallScore
                Gaming      = $gamingScore
                Desktop     = $desktopScore
                Workstation = $workstationScore
            }
            Metrics     = [ordered]@{
                CPU_ST        = $cpuSt
                CPU_MT        = $cpuMt
                CPU_AES       = $cpuAes
                CPU_SHA       = $cpuSha
                CPU_DEFL      = $cpuDefl
                RAM_Lesen     = $ramLesen
                RAM_Schreiben = $ramSchreiben
                RAM_Kopieren  = $ramKopieren
                RAM_Latenz    = $ramLatenz
                GPU_REND      = $gpuRend
                GPU_REND1     = $gpuRend1
                GPU_REND01    = $gpuRend01
                GPU_STUTTER   = $gpuStutter
                GPU_VMB       = $gpuVmb
                FastestDisk   = $fastestDisk
                Disks         = @($disksList)
                DisksByClass  = $disksByClass
            }
            Telemetry   = [ordered]@{
                TestType                 = $lasttestArt
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
    $isRefEntry = {
        param($j, $p)
        if ($j.Typ -eq 'Referenz' -or $j.Format -eq 'PC-Diagnose-Referenz' -or $j.Id -like 'Desktop_*' -or $j.Id -like 'Workstation_*' -or $j.Id -like 'Notebook_*' -or $j.Id -like 'MiniPC_*') { return $true }
        if ($p -and (Split-Path $p -Leaf) -match '^(Desktop_|Workstation_|Notebook_|MiniPC_).*\.json$') { return $true }
        return $false
    }
    $systems = [System.Collections.Generic.List[object]]::new()
    $references = [System.Collections.Generic.List[object]]::new()
    $preselectedIds = [System.Collections.Generic.List[string]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # A) Datenbank-Dateien
    # 1. Spezifisch übergebene Pfade zuerst
    if ($SystemPaths -and $SystemPaths.Count -gt 0) {
        foreach ($p in $SystemPaths) {
            if (Test-Path -LiteralPath $p) {
                try {
                    $full = (Convert-Path -LiteralPath $p)
                    if ($seenPaths.Add($full)) {
                        $raw = [IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
                        $parsed = $raw | ConvertFrom-Json
                        if ($parsed.Format -like 'PC-Diagnose-DB*') {
                            $isRef = & $isRefEntry $parsed $full
                            if (-not $isRef) {
                                $sysObj = & $parseSystemEntry $parsed $false $full
                                if ($sysObj) {
                                    $systems.Add($sysObj)
                                    $preselectedIds.Add([string]$sysObj.Id)
                                }
                            }
                        }
                    }
                } catch { }
            }
        }
    }

    # 2. Weitere Datenbank-Dateien aus $dbDir laden
    if ($dbDir -and (Test-Path -LiteralPath $dbDir)) {
        $otherDb = @(Get-ChildItem -LiteralPath $dbDir -Filter '*.json' -File | Where-Object { $_.Name -ne 'Referenz.json' })
        foreach ($f in $otherDb) {
            if ($seenPaths.Add($f.FullName)) {
                try {
                    $raw = [IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
                    $parsed = $raw | ConvertFrom-Json
                    if ($parsed.Format -like 'PC-Diagnose-DB*') {
                        $isRef = & $isRefEntry $parsed $f.FullName
                        if (-not $isRef) {
                            $sysObj = & $parseSystemEntry $parsed $false $f.FullName
                            if ($sysObj) { $systems.Add($sysObj) }
                        }
                    }
                } catch { }
            }
        }
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
        Version        = $(if ($script:ScriptVersion) { $script:ScriptVersion } else { '3.4' })
        Generated      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        PreselectedIds = @($preselectedIds)
        Systems        = @($systems)
        References     = @($references)
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
      --bg: #F5F6F8;
      --card-bg: #FFFFFF;
      --card-border: #E2E5EA;
      --card-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
      --text: #1C2330;
      --text-muted: #5F6878;
      --text-subtle: #8A92A0;
      --accent: #0067C0;
      --accent-hover: #005A9E;
      --accent-soft: #EBF3FB;
      --accent-border: #BDD7EE;
      --ok-bg: #E2F5E9;
      --ok-text: #11703F;
      --ok-border: #7CD6A0;
      --warn-bg: #FDF2D8;
      --warn-text: #9A5B00;
      --warn-border: #F3C26E;
      --crit-bg: #FDECEB;
      --crit-text: #B42318;
      --crit-border: #FF8F86;
      --neutral-bg: #F1F3F6;
      --neutral-text: #4B5563;
      --grid-line: #E2E5EA;
      --canvas-bg: #FFFFFF;
      --tooltip-bg: rgba(255, 255, 255, 0.96);
      --tooltip-shadow: 0 8px 24px rgba(0, 0, 0, 0.12);
      --curve-temp: #B42318;
      --curve-temp-fill: rgba(180, 35, 24, 0.08);
      --curve-mhz: #0067C0;
      --curve-mhz-fill: rgba(0, 103, 192, 0.06);
      --curve-gpu: #C2410C;
    }

    [data-theme="dark"] {
      --bg: #111419;
      --card-bg: #1A1F27;
      --card-border: #2B323D;
      --card-shadow: 0 4px 14px rgba(0, 0, 0, 0.35);
      --text: #E5E8EE;
      --text-muted: #98A1B0;
      --text-subtle: #7A8494;
      --accent: #4CC2FF;
      --accent-hover: #60CDFF;
      --accent-soft: #233446;
      --accent-border: #1E4E79;
      --ok-bg: #14321F;
      --ok-text: #7CD6A0;
      --ok-border: #11703F;
      --warn-bg: #3A2D12;
      --warn-text: #F3C26E;
      --warn-border: #9A5B00;
      --crit-bg: #3B1D1C;
      --crit-text: #FF8F86;
      --crit-border: #B42318;
      --neutral-bg: #252B35;
      --neutral-text: #D1D5DB;
      --grid-line: #2B323D;
      --canvas-bg: #1A1F27;
      --tooltip-bg: rgba(26, 31, 39, 0.96);
      --tooltip-shadow: 0 8px 24px rgba(0, 0, 0, 0.45);
      --curve-temp: #FF8F86;
      --curve-temp-fill: rgba(255, 143, 134, 0.12);
      --curve-mhz: #4CC2FF;
      --curve-mhz-fill: rgba(76, 194, 255, 0.08);
      --curve-gpu: #FB923C;
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
      max-width: 1360px;
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
      padding-bottom: 12px;
      border-bottom: 1px solid var(--card-border);
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 14px;
    }
    .brand-icon {
      width: 44px;
      height: 44px;
      border-radius: 10px;
      background: linear-gradient(135deg, var(--accent), #004578);
      color: white;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 22px;
      box-shadow: 0 4px 10px rgba(0, 103, 192, 0.25);
    }
    .brand-titles h1 {
      font-size: 1.45rem;
      font-weight: 700;
      letter-spacing: -0.01em;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .badge-ver {
      font-size: 0.72rem;
      font-weight: 600;
      padding: 2px 7px;
      border-radius: 20px;
      background: var(--accent-soft);
      color: var(--accent);
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
    }
    .theme-switch-container {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 0.85rem;
      color: var(--text-muted);
      user-select: none;
    }
    .toggle-switch {
      width: 44px;
      height: 24px;
      border-radius: 12px;
      background: var(--card-border);
      border: none;
      cursor: pointer;
      position: relative;
      transition: background-color 0.2s ease;
      outline: none;
    }
    .toggle-switch[aria-checked="true"] {
      background: var(--accent);
    }
    .toggle-thumb {
      width: 18px;
      height: 18px;
      border-radius: 50%;
      background: white;
      position: absolute;
      top: 3px;
      left: 3px;
      transition: transform 0.2s cubic-bezier(0.4, 0.0, 0.2, 1);
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
    }
    .toggle-switch[aria-checked="true"] .toggle-thumb {
      transform: translateX(20px);
    }

    /* SELECTOR CARDS */
    .selector-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 10px;
      padding: 16px 20px;
      box-shadow: var(--card-shadow);
      display: flex;
      flex-direction: column;
      gap: 14px;
    }
    .selector-top {
      display: flex;
      flex-wrap: wrap;
      gap: 16px;
      align-items: center;
      justify-content: space-between;
    }
    .selector-base-wrap {
      flex: 1;
      min-width: 280px;
    }
    .selector-label {
      font-size: 0.82rem;
      font-weight: 600;
      color: var(--text-muted);
      margin-bottom: 6px;
      display: flex;
      align-items: center;
      gap: 6px;
      text-transform: uppercase;
      letter-spacing: 0.03em;
    }
    .select-wrapper {
      position: relative;
      width: 100%;
    }
    select {
      width: 100%;
      appearance: none;
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      padding: 9px 34px 9px 12px;
      font-size: 0.92rem;
      color: var(--text);
      cursor: pointer;
      transition: border-color 0.15s ease, box-shadow 0.15s ease;
      font-family: inherit;
    }
    select:focus {
      outline: none;
      border-color: var(--accent);
      box-shadow: 0 0 0 2px var(--accent-soft);
    }
    .select-arrow {
      position: absolute;
      right: 12px;
      top: 50%;
      transform: translateY(-50%);
      pointer-events: none;
      font-size: 0.75rem;
      color: var(--text-muted);
    }
    .multi-select-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      flex-wrap: wrap;
      gap: 8px;
    }
    .multi-actions {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
    }
    .btn-chip {
      background: var(--neutral-bg);
      border: 1px solid var(--card-border);
      color: var(--text);
      font-size: 0.75rem;
      padding: 3px 8px;
      border-radius: 6px;
      cursor: pointer;
      transition: all 0.15s ease;
      font-family: inherit;
    }
    .btn-chip:hover {
      background: var(--accent-soft);
      border-color: var(--accent);
      color: var(--accent);
    }
    .compare-checkbox-grid {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      max-height: 160px;
      overflow-y: auto;
      padding: 10px;
      background: var(--neutral-bg);
      border: 1px solid var(--card-border);
      border-radius: 8px;
    }
    .compare-chip {
      display: inline-flex;
      align-items: center;
      gap: 7px;
      padding: 6px 12px;
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 6px;
      cursor: pointer;
      font-size: 0.84rem;
      user-select: none;
      transition: all 0.15s ease;
    }
    .compare-chip:hover {
      border-color: var(--accent);
    }
    .compare-chip.active {
      background: var(--accent-soft);
      border-color: var(--accent);
      font-weight: 600;
    }
    .compare-chip input[type="checkbox"] {
      cursor: pointer;
      accent-color: var(--accent);
    }
    .sys-dot {
      width: 10px;
      height: 10px;
      border-radius: 50%;
      display: inline-block;
      flex-shrink: 0;
    }
    .badge-count {
      font-size: 0.75rem;
      font-weight: 600;
      padding: 2px 8px;
      border-radius: 12px;
      background: var(--accent);
      color: white;
      margin-left: 6px;
    }

    /* SECTION CARDS */
    .dash-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 10px;
      padding: 20px;
      box-shadow: var(--card-shadow);
      display: flex;
      flex-direction: column;
      gap: 14px;
    }
    .card-head {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      flex-wrap: wrap;
      gap: 8px;
    }
    .card-head h2 {
      font-size: 1.15rem;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .card-head p {
      font-size: 0.82rem;
      color: var(--text-muted);
    }

    /* MATRIX TABLES */
    .table-scroll {
      width: 100%;
      overflow-x: auto;
      border: 1px solid var(--card-border);
      border-radius: 8px;
    }
    .matrix-table {
      width: 100%;
      border-collapse: separate;
      border-spacing: 0;
      font-size: 0.86rem;
      min-width: 650px;
    }
    .matrix-table th, .matrix-table td {
      padding: 8px 12px;
      border-bottom: 1px solid var(--card-border);
      vertical-align: middle;
    }
    .matrix-table th {
      background: var(--neutral-bg);
      color: var(--text-muted);
      font-weight: 600;
      font-size: 0.8rem;
      text-transform: uppercase;
      letter-spacing: 0.03em;
      position: sticky;
      top: 0;
      z-index: 1;
    }
    .matrix-table th.col-feature {
      text-align: left;
      width: 220px;
      min-width: 180px;
      position: sticky;
      left: 0;
      z-index: 2;
    }
    .matrix-table td.col-feature {
      text-align: left;
      font-weight: 500;
      background: var(--card-bg);
      position: sticky;
      left: 0;
      z-index: 1;
      border-right: 1px solid var(--card-border);
    }
    .matrix-table tr.category-header td {
      background: var(--accent-soft);
      color: var(--accent);
      font-weight: 700;
      font-size: 0.88rem;
      padding: 7px 12px;
      border-top: 1px solid var(--accent-border);
      border-bottom: 1px solid var(--accent-border);
    }
    .matrix-table td.sys-val {
      text-align: right;
      white-space: nowrap;
    }
    .matrix-table td.sys-val.is-best {
      background: var(--ok-bg);
      font-weight: 700;
    }
    .badge-best {
      display: inline-block;
      font-size: 0.7rem;
      font-weight: 700;
      padding: 1px 5px;
      border-radius: 4px;
      background: var(--ok-text);
      color: #FFFFFF;
      margin-left: 5px;
      vertical-align: 1px;
    }
    .val-main {
      font-weight: 600;
    }
    .val-sub {
      font-size: 0.75rem;
      color: var(--text-muted);
      margin-left: 4px;
    }

    /* PILL BADGES */
    .pill {
      font-size: 0.72rem;
      font-weight: 600;
      padding: 2px 6px;
      border-radius: 10px;
      display: inline-block;
      margin-left: 6px;
      vertical-align: middle;
    }
    .pill.ok { background: var(--ok-bg); color: var(--ok-text); border: 1px solid var(--ok-border); }
    .pill.warn { background: var(--warn-bg); color: var(--warn-text); border: 1px solid var(--warn-border); }
    .pill.crit { background: var(--crit-bg); color: var(--crit-text); border: 1px solid var(--crit-border); }
    .pill.neutral { background: var(--neutral-bg); color: var(--neutral-text); }
    .badge {
      display: inline-block;
      padding: 2px 7px;
      border-radius: 12px;
      font-size: 0.75rem;
      font-weight: 600;
    }
    .badge.crit { background: var(--crit-bg); color: var(--crit-text); }
    .badge.warn { background: var(--warn-bg); color: var(--warn-text); }
    .badge.info { background: var(--accent-soft); color: var(--accent); }
    .badge.ok   { background: var(--ok-bg); color: var(--ok-text); }

    /* PROFILES GRID */
    .profiles-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 16px;
    }
    .profile-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 10px;
      padding: 16px;
      box-shadow: var(--card-shadow);
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .profile-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-weight: 600;
      font-size: 1rem;
    }
    .profile-sys-list {
      display: flex;
      flex-direction: column;
      gap: 6px;
      margin-top: 4px;
    }
    .profile-sys-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 0.85rem;
      padding: 4px 6px;
      border-radius: 6px;
      background: var(--neutral-bg);
    }
    .profile-sys-row.is-base {
      border-left: 3px solid var(--accent);
      background: var(--accent-soft);
      font-weight: 600;
    }

    /* TELEMETRY & CHART */
    .chart-controls {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      align-items: center;
    }
    .chart-btn {
      background: var(--neutral-bg);
      border: 1px solid var(--card-border);
      color: var(--text);
      font-size: 0.8rem;
      font-weight: 500;
      padding: 5px 12px;
      border-radius: 6px;
      cursor: pointer;
      transition: all 0.15s ease;
      font-family: inherit;
    }
    .chart-btn.active {
      background: var(--accent);
      color: white;
      border-color: var(--accent);
    }
    .chart-container {
      position: relative;
      width: 100%;
      height: 380px;
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
    .chart-tooltip {
      position: absolute;
      display: none;
      background: var(--tooltip-bg);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      padding: 10px 14px;
      font-size: 0.8rem;
      color: var(--text);
      box-shadow: var(--tooltip-shadow);
      pointer-events: none;
      z-index: 10;
      min-width: 200px;
      max-width: 320px;
      line-height: 1.45;
    }
    .chart-legend {
      display: flex;
      flex-wrap: wrap;
      gap: 14px;
      font-size: 0.8rem;
      color: var(--text-muted);
      align-items: center;
      padding-top: 4px;
    }
    .legend-item {
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .legend-color {
      width: 14px;
      height: 14px;
      border-radius: 3px;
      flex-shrink: 0;
    }

    /* FINDINGS ACCORDION */
    .findings-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 12px;
    }
    .finding-card {
      background: var(--neutral-bg);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      padding: 12px;
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
    .finding-card-head {
      display: flex;
      align-items: center;
      gap: 6px;
      font-weight: 600;
      font-size: 0.88rem;
    }
    .finding-card-badges {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
    }
    details summary {
      cursor: pointer;
      font-size: 0.84rem;
      font-weight: 600;
      color: var(--accent);
      user-select: none;
      outline: none;
    }
    details summary:hover {
      text-decoration: underline;
    }
    .findings-list {
      margin-top: 8px;
      display: flex;
      flex-direction: column;
      gap: 6px;
      font-size: 0.8rem;
    }
    .finding-item {
      display: flex;
      gap: 8px;
      align-items: flex-start;
      padding: 6px 8px;
      border-radius: 4px;
      background: var(--card-bg);
      border: 1px solid var(--card-border);
    }

    /* FOOTER */
    footer {
      text-align: center;
      font-size: 0.8rem;
      color: var(--text-muted);
      padding: 24px 0 12px 0;
      border-top: 1px solid var(--card-border);
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
        <h1>Leos Minibench <span class="badge-ver">v3.31</span></h1>
        <p>Interaktives Benchmark- & Diagnose-Dashboard (Multi-System-Vergleich)</p>
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

  <!-- MULTI-SYSTEM SELECTOR -->
  <section class="selector-card">
    <div class="selector-top">
      <div class="selector-base-wrap">
        <div class="selector-label">🎯 Basis- / Referenzsystem (100 % Bezugspunkt)</div>
        <div class="select-wrapper">
          <select id="baseSelect"></select>
          <span class="select-arrow">▼</span>
        </div>
      </div>
      <div>
        <span id="comparedCountBadge" class="badge-count">1 System</span>
      </div>
    </div>

    <div>
      <div class="multi-select-header">
        <div class="selector-label">🔍 Vergleichssysteme auswählen (N &ge; 1 zusätzliche Systeme):</div>
        <div class="multi-actions">
          <button id="btnSelectAll" class="btn-chip" type="button">Alle auswählen</button>
          <button id="btnSelectNone" class="btn-chip" type="button">Keine</button>
          <button id="btnSelectDbOnly" class="btn-chip" type="button">Nur Datenbank</button>
          <button id="btnSelectRefOnly" class="btn-chip" type="button">Nur Referenzen</button>
        </div>
      </div>
      <div id="compareChips" class="compare-checkbox-grid"></div>
    </div>
  </section>

  <!-- HARDWARE-SPEZIFIKATIONEN IM DIREKTVERGLEICH -->
  <section class="dash-card">
    <div class="card-head">
      <div>
        <h2>🖥️ Hardware-Spezifikationen im Direktvergleich</h2>
        <p>Vollständige Gegenüberstellung aller verglichenen Systeme nebeneinander.</p>
      </div>
    </div>
    <div class="table-scroll">
      <table id="specsTable" class="matrix-table">
        <!-- Generiert durch JavaScript -->
      </table>
    </div>
  </section>

  <!-- NUTZUNGSPROFILE IM MULTI-SYSTEM-VERGLEICH -->
  <section class="dash-card">
    <div class="card-head">
      <div>
        <h2>🎮 Nutzungsprofile &amp; Gesamtbewertung</h2>
        <p>Scores und prozentuales Delta relativ zum gewählten Basissystem.</p>
      </div>
    </div>
    <div id="profilesGrid" class="profiles-grid">
      <!-- Generiert durch JavaScript -->
    </div>
  </section>

  <!-- VOLLSTÄNDIGE BENCHMARK-MATRIX -->
  <section class="dash-card">
    <div class="card-head">
      <div>
        <h2>📊 Vollständige Benchmark-Matrix</h2>
        <p>Gegenüberstellung aller vorliegenden Messwerte mit Bestwert-Hervorhebung (👑) und Abweichung zum Basissystem.</p>
      </div>
    </div>
    <div class="table-scroll">
      <table id="matrixTable" class="matrix-table">
        <!-- Generiert durch JavaScript -->
      </table>
    </div>
  </section>

  <!-- INTERAKTIVER SYSTEMVERGLEICH-CHART -->
  <section class="dash-card">
    <div class="card-head">
      <div>
        <h2>Lasttest-Telemetrie &amp; Multi-System-Sensorverlauf</h2>
        <p>Sensorverlauf über die Belastungsdauer mit Farbcodierung je System.</p>
      </div>
      <div class="chart-controls">
        <button id="btnModeCpu" class="chart-btn active" type="button">CPU</button>
        <button id="btnModeGpu" class="chart-btn" type="button">GPU</button>
      </div>
    </div>

    <!-- CANVAS TELEMETRY CHART -->
    <div class="chart-container" id="chartWrapper">
      <canvas id="telemetryCanvas"></canvas>
      <div id="chartTooltip" class="chart-tooltip"></div>
    </div>

    <div id="chartLegend" class="chart-legend">
      <!-- Generiert durch JavaScript -->
    </div>
  </section>

  <!-- BEFUNDE-VERGLEICH -->
  <section class="dash-card">
    <div class="card-head">
      <div>
        <h2>Befunde der Systeme im Vergleich</h2>
        <p>Synoptische Gegenüberstellung aller Diagnose-Befunde (Kritisch, Warnungen, Hinweise).</p>
      </div>
    </div>
    <div id="findingsGrid" class="findings-grid">
      <!-- Generiert durch JavaScript -->
    </div>
  </section>

  <!-- FOOTER -->
  <footer>
    Leos Minibench v3.31 &middot; Multi-System Benchmark- &amp; Diagnose-Dashboard &middot; 100 % Offline &middot; UTF-8
  </footer>

</div>

<script>
/* __DASHBOARD_DATA__ */
window.MINIBENCH_DASHBOARD_DATA = window.MINIBENCH_DASHBOARD_DATA || null;

(function() {
  'use strict';

  let data = window.MINIBENCH_DASHBOARD_DATA;
  let baseSystem = null;
  let comparedSystems = [];
  let selectedCompareIds = new Set();
  let chartMode = 'cpu'; // 'cpu', 'gpu'

  function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // Farbpalette für bis zu N Systeme
  const SYSTEM_COLORS = [
    { stroke: '#0078D4', strokeDark: '#4CC2FF', fill: 'rgba(0, 120, 212, 0.12)', fillDark: 'rgba(76, 194, 255, 0.12)' },
    { stroke: '#E81123', strokeDark: '#FF5A5A', fill: 'rgba(232, 17, 35, 0.12)', fillDark: 'rgba(255, 90, 90, 0.12)' },
    { stroke: '#107C41', strokeDark: '#6CCB5F', fill: 'rgba(16, 124, 65, 0.12)', fillDark: 'rgba(108, 203, 95, 0.12)' },
    { stroke: '#8E44AD', strokeDark: '#B388FF', fill: 'rgba(142, 68, 173, 0.12)', fillDark: 'rgba(179, 136, 255, 0.12)' },
    { stroke: '#F7630C', strokeDark: '#FFA057', fill: 'rgba(247, 99, 12, 0.12)', fillDark: 'rgba(255, 160, 87, 0.12)' },
    { stroke: '#009688', strokeDark: '#26A69A', fill: 'rgba(0, 150, 136, 0.12)', fillDark: 'rgba(38, 166, 154, 0.12)' },
    { stroke: '#C239B3', strokeDark: '#FF77E9', fill: 'rgba(194, 57, 179, 0.12)', fillDark: 'rgba(255, 119, 233, 0.12)' },
    { stroke: '#D83B01', strokeDark: '#FF8A65', fill: 'rgba(216, 59, 1, 0.12)', fillDark: 'rgba(255, 138, 101, 0.12)' }
  ];

  function getSysColor(idx, isDark) {
    const c = SYSTEM_COLORS[idx % SYSTEM_COLORS.length];
    return isDark ? c.strokeDark : c.stroke;
  }

  // DOM-Elemente
  const themeToggle = document.getElementById('themeToggle');
  const baseSelect = document.getElementById('baseSelect');
  const compareChips = document.getElementById('compareChips');
  const comparedCountBadge = document.getElementById('comparedCountBadge');
  const specsTable = document.getElementById('specsTable');
  const profilesGrid = document.getElementById('profilesGrid');
  const matrixTable = document.getElementById('matrixTable');
  const findingsGrid = document.getElementById('findingsGrid');
  const chartWrapper = document.getElementById('chartWrapper');
  const canvas = document.getElementById('telemetryCanvas');
  const tooltip = document.getElementById('chartTooltip');
  const chartLegend = document.getElementById('chartLegend');

  const btnModeCpu = document.getElementById('btnModeCpu');
  const btnModeGpu = document.getElementById('btnModeGpu');

  const btnSelectAll = document.getElementById('btnSelectAll');
  const btnSelectNone = document.getElementById('btnSelectNone');
  const btnSelectDbOnly = document.getElementById('btnSelectDbOnly');
  const btnSelectRefOnly = document.getElementById('btnSelectRefOnly');

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

  // HILFSFUNKTIONEN
  function getAllSystems() {
    if (!data) return [];
    const list = [];
    const seen = new Set();
    const addSys = s => {
      if (!s) return;
      const key = String(s.Id || s.DisplayName || s.Computer || '').trim().toLowerCase();
      if (key && !seen.has(key)) {
        seen.add(key);
        list.push(s);
      }
    };
    (data.Systems || []).forEach(addSys);
    (data.References || []).forEach(addSys);
    return list;
  }

  function getSystemById(id) {
    if (!id) return null;
    const sId = String(id);
    return getAllSystems().find(s => String(s.Id) === sId) || null;
  }

  function fmtNum(n, decimals = 0) {
    if (n === null || n === undefined || isNaN(n) || n === 0) return '-';
    return Number(n).toLocaleString('de-DE', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
  }

  function calcDelta(currVal, refVal, lowerIsBetter = false) {
    if (!currVal || !refVal || currVal <= 0 || refVal <= 0) return null;
    let pct = 0;
    if (lowerIsBetter) {
      pct = ((refVal - currVal) / refVal) * 100.0;
    } else {
      pct = ((currVal - refVal) / refVal) * 100.0;
    }
    return pct;
  }

  function renderPill(pct, lowerIsBetter = false) {
    if (pct === null || isNaN(pct)) return '<span class="pill neutral">n/v</span>';
    const sign = pct > 0 ? '+' : '';
    const txt = sign + pct.toFixed(1) + ' %';
    let cls = 'neutral';
    if (pct >= 2.0) cls = 'ok';
    else if (pct <= -5.0) cls = 'crit';
    return `<span class="pill ${cls}">${txt}</span>`;
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

  // INITIALISIERUNG
  function init() {
    initTheme();
    if (!data || (!data.Systems && !data.References)) {
      console.warn('Keine Benchmark-Daten eingebettet.');
      return;
    }

    populateBaseSelect();

    // Vorauswahl ermitteln
    const preselected = data.PreselectedIds || [];
    if (preselected && preselected.length > 0) {
      baseSelect.value = String(preselected[0]);
      selectedCompareIds.clear();
      for (let i = 1; i < preselected.length; i++) {
        selectedCompareIds.add(String(preselected[i]));
      }
    } else {
      if (data.Systems && data.Systems.length > 0) {
        baseSelect.value = String(data.Systems[0].Id);
      }
      selectedCompareIds.clear();
      if (data.References && data.References.length > 0) {
        const mid = data.References.find(r => r.DisplayName.includes('Mittelklasse')) || data.References[0];
        selectedCompareIds.add(String(mid.Id));
      } else if (data.Systems && data.Systems.length > 1) {
        selectedCompareIds.add(String(data.Systems[1].Id));
      }
    }

    // URL-Parameter oder Hash für System-Vorauswahl prüfen (?system=... oder #...)
    let paramSys = null;
    try {
      const urlParams = new URLSearchParams(window.location.search);
      paramSys = urlParams.get('system') || urlParams.get('pc') || urlParams.get('id');
      if (!paramSys && window.location.hash) {
        paramSys = decodeURIComponent(window.location.hash.replace(/^#/, ''));
      }
    } catch(e) {}
    if (paramSys) {
      const targetStr = String(paramSys).trim().toLowerCase();
      const all = getAllSystems();
      const match = all.find(s =>
        (s.Id && String(s.Id).toLowerCase() === targetStr) ||
        (s.Computer && String(s.Computer).toLowerCase() === targetStr) ||
        (s.DisplayName && String(s.DisplayName).toLowerCase().includes(targetStr))
      );
      if (match) {
        baseSelect.value = String(match.Id);
        selectedCompareIds.delete(String(match.Id));
        if (selectedCompareIds.size === 0) {
          if (data.References && data.References.length > 0) {
            const mid = data.References.find(r => r.DisplayName && r.DisplayName.includes('Mittelklasse')) || data.References[0];
            selectedCompareIds.add(String(mid.Id));
          } else {
            const other = all.find(s => String(s.Id) !== String(match.Id));
            if (other) selectedCompareIds.add(String(other.Id));
          }
        }
      }
    }

    renderCompareChips();
    updateDashboard();

    baseSelect.addEventListener('change', () => {
      // Falls das neue Basissystem in der Vergleichsauswahl war, entfernen
      selectedCompareIds.delete(baseSelect.value);
      renderCompareChips();
      updateDashboard();
    });

    btnSelectAll.addEventListener('click', () => {
      getAllSystems().forEach(s => {
        if (String(s.Id) !== baseSelect.value) selectedCompareIds.add(String(s.Id));
      });
      renderCompareChips();
      updateDashboard();
    });

    btnSelectNone.addEventListener('click', () => {
      selectedCompareIds.clear();
      renderCompareChips();
      updateDashboard();
    });

    btnSelectDbOnly.addEventListener('click', () => {
      selectedCompareIds.clear();
      (data.Systems || []).forEach(s => {
        if (String(s.Id) !== baseSelect.value) selectedCompareIds.add(String(s.Id));
      });
      renderCompareChips();
      updateDashboard();
    });

    btnSelectRefOnly.addEventListener('click', () => {
      selectedCompareIds.clear();
      (data.References || []).forEach(r => {
        if (String(r.Id) !== baseSelect.value) selectedCompareIds.add(String(r.Id));
      });
      renderCompareChips();
      updateDashboard();
    });

    // Chart Modus-Umschalter
    btnModeCpu.addEventListener('click', () => { setChartMode('cpu'); });
    btnModeGpu.addEventListener('click', () => { setChartMode('gpu'); });

    window.addEventListener('resize', renderChart);
  }

  function setChartMode(mode) {
    chartMode = mode;
    btnModeCpu.classList.toggle('active', mode === 'cpu');
    btnModeGpu.classList.toggle('active', mode === 'gpu');
    renderChart();
  }

  function populateBaseSelect() {
    baseSelect.innerHTML = '';
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

    baseSelect.appendChild(sysGroup);
    baseSelect.appendChild(refGroup);
  }

  function renderCompareChips() {
    compareChips.innerHTML = '';
    const all = getAllSystems();
    const curBaseId = baseSelect.value;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    let colorIdx = 1;
    all.forEach(sys => {
      const sId = String(sys.Id);
      if (sId === curBaseId) return; // Basissystem nicht in Vergleichsliste anzeigen

      const isChecked = selectedCompareIds.has(sId);
      const label = document.createElement('label');
      label.className = 'compare-chip' + (isChecked ? ' active' : '');

      const chk = document.createElement('input');
      chk.type = 'checkbox';
      chk.checked = isChecked;
      chk.value = sId;
      chk.addEventListener('change', () => {
        if (chk.checked) selectedCompareIds.add(sId);
        else selectedCompareIds.delete(sId);
        label.classList.toggle('active', chk.checked);
        updateDashboard();
      });

      const dot = document.createElement('span');
      dot.className = 'sys-dot';
      dot.style.background = isChecked ? getSysColor(colorIdx, isDark) : 'var(--text-subtle)';

      const txt = document.createElement('span');
      txt.textContent = (sys.IsReference ? '⭐ ' : '') + sys.DisplayName + (sys.Datum ? ' (' + sys.Datum.split(' ')[0] + ')' : '');

      label.appendChild(chk);
      label.appendChild(dot);
      label.appendChild(txt);
      compareChips.appendChild(label);

      if (isChecked) colorIdx++;
    });
  }

  function updateDashboard() {
    baseSystem = getSystemById(baseSelect.value);
    if (!baseSystem && getAllSystems().length > 0) {
      baseSystem = getAllSystems()[0];
      baseSelect.value = String(baseSystem.Id);
    }

    // Liste aller aktiven Systeme: Basissystem zuerst, dann die angehakten
    comparedSystems = [];
    if (baseSystem) comparedSystems.push(baseSystem);

    selectedCompareIds.forEach(id => {
      const s = getSystemById(id);
      if (s && s !== baseSystem) comparedSystems.push(s);
    });

    const totalN = comparedSystems.length;
    comparedCountBadge.textContent = totalN + (totalN === 1 ? ' System' : ' Systeme im Vergleich');

    renderSpecsTable();
    renderProfilesGrid();
    renderMatrixTable();
    renderFindingsGrid();
    renderChartLegend();
    renderChart();
  }

  // 1. HARDWARE-SPEZIFIKATIONEN TABELLE
  function renderSpecsTable() {
    if (!specsTable) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    let html = '<thead><tr><th class="col-feature">Merkmal</th>';
    comparedSystems.forEach((s, idx) => {
      const color = getSysColor(idx, isDark);
      const isBase = (idx === 0);
      const sName = escapeHtml(s.DisplayName || s.Computer);
      const repUrl = s.ReportUrl ? escapeHtml(s.ReportUrl) : '';
      const nameHtml = repUrl
        ? `<a href="${repUrl}" target="_blank" title="Diagnosebericht für ${sName} im Browser öffnen" style="color:inherit; text-decoration:underline; font-weight:600; cursor:pointer;">${sName}</a>`
        : `<span>${sName}</span>`;
      const repBadge = repUrl
        ? `<a href="${repUrl}" target="_blank" class="report-badge-btn" title="Diagnosebericht öffnen" style="margin-left:auto; display:inline-flex; align-items:center; gap:3px; padding:2px 8px; font-size:0.75rem; border-radius:4px; background:var(--accent-subtle); color:var(--accent); text-decoration:none; border:1px solid var(--accent); font-weight:600; cursor:pointer;">Bericht</a>`
        : '';
      html += `<th>
        <div style="display: flex; align-items: center; gap: 6px;">
          <span class="sys-dot" style="background: ${color};"></span>
          ${nameHtml}
          ${isBase ? '<span class="pill ok">Basis</span>' : ''}
          ${repBadge}
        </div>
        <div style="font-size: 0.72rem; color: var(--text-muted); font-weight: normal;">${escapeHtml(s.Datum || 'Referenz')}</div>
      </th>`;
    });
    html += '</tr></thead><tbody>';

    const rows = [
      { key: 'Bericht', label: 'Diagnosebericht', get: s => s.ReportUrl ? `<a href="${escapeHtml(s.ReportUrl)}" target="_blank" style="color:var(--accent); text-decoration:underline; font-weight:600;">Diagnosebericht.html öffnen</a>` : '<span style="color:var(--text-muted);">-</span>' },
      { key: 'Computer', label: 'Rechnername', get: s => escapeHtml(s.Computer || '-') },
      { key: 'CPU', label: 'Prozessor (CPU)', get: s => escapeHtml(s.Hardware?.CpuKurz || s.Hardware?.CPU || '-') },
      { key: 'KerneThreads', label: 'Kerne / Threads', get: s => escapeHtml((s.Hardware?.Kerne && s.Hardware?.Threads) ? `${s.Hardware.Kerne} / ${s.Hardware.Threads}` : (s.Hardware?.KerneThreads || 'n/v')) },
      { key: 'RAM', label: 'Arbeitsspeicher (RAM)', get: s => escapeHtml(s.Hardware?.RAM || '-') },
      { key: 'GPU', label: 'Grafikkarte (GPU)', get: s => escapeHtml(s.Hardware?.GPU || '-') },
      { key: 'Disk', label: 'Datenträger', get: s => escapeHtml(s.Hardware?.Datentraeger || s.Hardware?.FastestDisk || '-') },
      { key: 'Mainboard', label: 'Mainboard / System', get: s => escapeHtml(s.Hardware?.Mainboard || s.Hardware?.System || '-') },
      { key: 'OS', label: 'Betriebssystem', get: s => escapeHtml(s.OS || s.Hardware?.Betriebssystem || '-') },
      { key: 'Installiert', label: 'Windows installiert', get: s => escapeHtml(s.Hardware?.WindowsInstalliert || '-') },
      { key: 'Befunde', label: 'Diagnose-Befunde', get: s => {
        const b = s.Befunde || { Kritisch: 0, Warnungen: 0, Hinweise: 0 };
        return `<span class="badge ${b.Kritisch > 0 ? 'crit' : 'neutral'}">${b.Kritisch} kritisch</span>
                <span class="badge ${b.Warnungen > 0 ? 'warn' : 'neutral'}">${b.Warnungen} Warnungen</span>
                <span class="badge info">${b.Hinweise} Hinweise</span>`;
      }}
    ];

    rows.forEach(r => {
      html += `<tr><td class="col-feature">${r.label}</td>`;
      comparedSystems.forEach(s => {
        html += `<td>${r.get(s)}</td>`;
      });
      html += '</tr>';
    });

    html += '</tbody>';
    specsTable.innerHTML = html;
  }

  // 2. NUTZUNGSPROFILE GRID
  function renderProfilesGrid() {
    if (!profilesGrid) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    const profiles = [
      { key: 'Gaming', title: 'Gaming', desc: 'GPU- & Single-Thread-Fokus' },
      { key: 'Desktop', title: 'Büro / Desktop', desc: 'Reaktionszeit & SSD-Leistung' },
      { key: 'Workstation', title: 'Workstation', desc: 'Mehrkern- & RAM-Durchsatz' }
    ];

    let html = '';
    profiles.forEach(p => {
      const baseScore = baseSystem?.Scores?.[p.key] || 0;
      html += `<div class="profile-card">
        <div class="profile-header">
          <span>${escapeHtml(p.title)}</span>
          <span style="font-size: 0.78rem; color: var(--text-muted); font-weight: normal;">${escapeHtml(p.desc)}</span>
        </div>
        <div class="profile-sys-list">`;

      const items = comparedSystems.map((s, idx) => {
        const sc = s.Scores?.[p.key];
        const hasScore = (typeof sc === 'number' && sc > 0);
        const isBase = (String(s.Id) === String(baseSystem?.Id));
        return {
          sys: s,
          idx: idx,
          score: hasScore ? sc : 0,
          hasScore: hasScore,
          isBase: isBase
        };
      });

      items.sort((a, b) => {
        if (a.hasScore && b.hasScore) return b.score - a.score;
        if (a.hasScore && !b.hasScore) return -1;
        if (!a.hasScore && b.hasScore) return 1;
        return a.idx - b.idx;
      });

      items.forEach(item => {
        const s = item.sys;
        const sc = item.score;
        const isBase = item.isBase;
        const color = getSysColor(item.idx, isDark);
        const sName = escapeHtml(s.DisplayName || s.Computer);
        const repUrl = s.ReportUrl ? escapeHtml(s.ReportUrl) : '';

        const delta = isBase ? 0 : (item.hasScore && baseScore > 0 ? calcDelta(sc, baseScore) : null);
        let deltaHtml = '';
        if (isBase) {
          deltaHtml = '<span class="pill ok">100 % (Basis)</span>';
        } else if (delta !== null) {
          deltaHtml = renderPill(delta);
        } else {
          deltaHtml = '<span class="pill neutral">n/v</span>';
        }

        const scoreText = item.hasScore ? fmtNum(sc) : 'n/v';

        const nameLink = repUrl
          ? `<a href="${repUrl}" target="_blank" title="Diagnosebericht für ${sName} öffnen" style="color:inherit; text-decoration:underline; cursor:pointer;">${sName}</a>`
          : `<span>${sName}</span>`;

        html += `<div class="profile-sys-row ${isBase ? 'is-base' : ''}">
          <div style="display: flex; align-items: center; gap: 6px;">
            <span class="sys-dot" style="background: ${color};"></span>
            <span style="max-width: 150px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${nameLink}</span>
          </div>
          <div style="display: flex; align-items: center; gap: 4px;">
            <span style="font-weight: 700;">${scoreText}</span>
            ${deltaHtml}
          </div>
        </div>`;
      });

      html += `</div></div>`;
    });

    profilesGrid.innerHTML = html;
  }

  // 3. VOLLSTÄNDIGE BENCHMARK-MATRIX
  function renderMatrixTable() {
    if (!matrixTable) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    let html = '<thead><tr><th class="col-feature">Messgröße</th>';
    comparedSystems.forEach((s, idx) => {
      const color = getSysColor(idx, isDark);
      const isBase = (idx === 0);
      const sName = escapeHtml(s.DisplayName || s.Computer);
      const repUrl = s.ReportUrl ? escapeHtml(s.ReportUrl) : '';
      const nameLink = repUrl
        ? `<a href="${repUrl}" target="_blank" title="Diagnosebericht für ${sName} im Browser öffnen" style="color:inherit; text-decoration:underline; font-weight:600; cursor:pointer;">${sName}</a>`
        : `<span>${sName}</span>`;
      const repBtn = repUrl
        ? `<a href="${repUrl}" target="_blank" title="Diagnosebericht öffnen" style="font-size:0.75rem; color:var(--accent); text-decoration:none; margin-left:4px;">Bericht</a>`
        : '';
      html += `<th style="text-align: right;">
        <div style="display: flex; align-items: center; justify-content: flex-end; gap: 6px;">
          <span class="sys-dot" style="background: ${color};"></span>
          ${nameLink}
          ${isBase ? '<span class="pill ok">Basis</span>' : ''}
          ${repBtn}
        </div>
      </th>`;
    });
    html += '</tr></thead><tbody>';

    const categories = [
      {
        name: 'Prozessor (CPU)',
        metrics: [
          { key: 'CPU_ST', label: 'Single-Thread (ST)', unit: 'Punkte', dec: 0, lower: false },
          { key: 'CPU_MT', label: 'Multi-Thread (MT)', unit: 'Punkte', dec: 0, lower: false },
          { key: 'CPU_AES', label: 'AES-256 Verschlüsselung', unit: 'MB/s', dec: 0, lower: false },
          { key: 'CPU_SHA', label: 'SHA-256 Prüfsumme', unit: 'MB/s', dec: 0, lower: false },
          { key: 'CPU_DEFL', label: 'Deflate Kompression', unit: 'MB/s', dec: 0, lower: false }
        ]
      },
      {
        name: 'Arbeitsspeicher (RAM)',
        metrics: [
          { key: 'RAM_Lesen', label: 'Lesen Durchsatz', unit: 'GB/s', dec: 1, lower: false },
          { key: 'RAM_Schreiben', label: 'Schreiben Durchsatz', unit: 'GB/s', dec: 1, lower: false },
          { key: 'RAM_Kopieren', label: 'Kopieren Durchsatz', unit: 'GB/s', dec: 1, lower: false },
          { key: 'RAM_Latenz', label: 'Zugriffslatenz', unit: 'ns', dec: 1, lower: true }
        ]
      },
      {
        name: 'Grafik (GPU)',
        metrics: [
          { key: 'GPU_REND', label: 'Renderleistung (Ø FPS)', unit: 'FPS', dec: 1, lower: false },
          { key: 'GPU_REND1', label: '1 %-Low Bildrate', unit: 'FPS', dec: 1, lower: false },
          { key: 'GPU_REND01', label: '0,1 %-Low Bildrate', unit: 'FPS', dec: 1, lower: false },
          { key: 'GPU_STUTTER', label: 'Mikroruckler-Anteil', unit: '%', dec: 1, lower: true },
          { key: 'GPU_VMB', label: 'Videospeicher-Bandbreite', unit: 'GB/s', dec: 1, lower: false }
        ]
      },
      {
        name: 'Datenträger (Speicher)',
        metrics: [
          { key: 'DISK_SR', label: 'Sequentiell Lesen', unit: 'MB/s', dec: 0, lower: false, get: s => s.Metrics?.FastestDisk?.SR || s.RawValues?.['DISK|NVMe4|SR'] || 0 },
          { key: 'DISK_SW', label: 'Sequentiell Schreiben', unit: 'MB/s', dec: 0, lower: false, get: s => s.Metrics?.FastestDisk?.SW || s.RawValues?.['DISK|NVMe4|SW'] || 0 },
          { key: 'DISK_R1', label: '4K Zufall QD1', unit: 'IOPS', dec: 0, lower: false, get: s => s.Metrics?.FastestDisk?.R1 || s.RawValues?.['DISK|NVMe4|R1'] || 0 },
          { key: 'DISK_R8', label: '4K Zufall 8 Threads', unit: 'IOPS', dec: 0, lower: false, get: s => s.Metrics?.FastestDisk?.R8 || s.RawValues?.['DISK|NVMe4|R8'] || 0 },
          { key: 'DISK_W1', label: '4K Schreiben', unit: 'IOPS', dec: 0, lower: false, get: s => s.Metrics?.FastestDisk?.W1 || s.RawValues?.['DISK|NVMe4|W1'] || 0 }
        ]
      }
    ];

    categories.forEach(cat => {
      html += `<tr class="category-header"><td class="col-feature" colspan="${comparedSystems.length + 1}">${cat.name}</td></tr>`;

      cat.metrics.forEach(m => {
        // Werte aller Systeme sammeln
        const vals = comparedSystems.map(s => {
          if (m.get) return m.get(s);
          return s.Metrics?.[m.key] || s.RawValues?.[m.key.replace('_', '|')] || 0;
        });

        // Bestwert ermitteln (nur unter Werten > 0)
        const validVals = vals.filter(v => v !== null && v !== undefined && v > 0);
        let bestVal = null;
        if (validVals.length > 1) {
          bestVal = m.lower ? Math.min(...validVals) : Math.max(...validVals);
        }

        const baseVal = vals[0] || 0;

        html += `<tr><td class="col-feature">${m.label} <span style="font-size: 0.72rem; color: var(--text-muted);">(${m.unit}${m.lower ? ', niedriger = besser' : ''})</span></td>`;

        vals.forEach((v, idx) => {
          const isBase = (idx === 0);
          const isBest = (bestVal !== null && v === bestVal);
          const delta = (isBase || v <= 0 || baseVal <= 0) ? null : calcDelta(v, baseVal, m.lower);

          html += `<td class="sys-val ${isBest ? 'is-best' : ''}">
            <span class="val-main">${fmtNum(v, m.dec)}</span>
            <span class="val-sub">${m.unit}</span>
            ${isBest ? '<span class="badge-best" title="Bestwert aller Systeme">👑 Bestwert</span>' : ''}
            ${!isBase && delta !== null ? renderPill(delta, m.lower) : ''}
          </td>`;
        });

        html += `</tr>`;
      });
    });

    html += '</tbody>';
    matrixTable.innerHTML = html;
  }

  // 4. BEFUNDE-VERGLEICH
  function renderFindingsGrid() {
    if (!findingsGrid) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    let html = '';
    comparedSystems.forEach((s, idx) => {
      const color = getSysColor(idx, isDark);
      const b = s.Befunde || { Kritisch: 0, Warnungen: 0, Hinweise: 0, Liste: [] };
      const list = b.Liste || [];

      const sName = escapeHtml(s.DisplayName || s.Computer);
      const repUrl = s.ReportUrl ? escapeHtml(s.ReportUrl) : '';
      const nameLink = repUrl
        ? `<a href="${repUrl}" target="_blank" title="Diagnosebericht für ${sName} im Browser öffnen" style="color:inherit; text-decoration:underline; font-weight:600; cursor:pointer;">${sName}</a>`
        : `<span>${sName}</span>`;
      const repBadge = repUrl
        ? `<a href="${repUrl}" target="_blank" class="report-badge-btn" title="Diagnosebericht öffnen" style="margin-left:auto; display:inline-flex; align-items:center; gap:3px; padding:2px 8px; font-size:0.75rem; border-radius:4px; background:var(--accent-subtle); color:var(--accent); text-decoration:none; border:1px solid var(--accent); font-weight:600; cursor:pointer;">Bericht</a>`
        : '';

      html += `<div class="finding-card">
        <div class="finding-card-head" style="display:flex; align-items:center; gap:6px;">
          <span class="sys-dot" style="background: ${color};"></span>
          ${nameLink}
          ${repBadge}
        </div>
        <div class="finding-card-badges">
          <span class="badge ${b.Kritisch > 0 ? 'crit' : 'neutral'}">${b.Kritisch} kritisch</span>
          <span class="badge ${b.Warnungen > 0 ? 'warn' : 'neutral'}">${b.Warnungen} Warnungen</span>
          <span class="badge info">${b.Hinweise} Hinweise</span>
        </div>`;

      if (list.length > 0) {
        html += `<details>
          <summary>${list.length} Befunde anzeigen</summary>
          <div class="findings-list">`;
        list.forEach(f => {
          let bCls = 'info';
          let txt = String(f);
          if (txt.includes('[KRITISCH]') || txt.includes('[FEHLER]')) bCls = 'crit';
          else if (txt.includes('[WARNUNG]')) bCls = 'warn';

          html += `<div class="finding-item">
            <span class="badge ${bCls}" style="flex-shrink: 0;">${bCls.toUpperCase()}</span>
            <span>${escapeHtml(txt.replace(/^\[\w+\]\s*/, ''))}</span>
          </div>`;
        });
        html += `</div></details>`;
      } else {
        html += `<div style="font-size: 0.8rem; color: var(--text-muted);">Keine Auffälligkeiten oder Befunde dokumentiert.</div>`;
      }

      html += `</div>`;
    });

    findingsGrid.innerHTML = html;
  }

  // 5. CHART-LEGENDE
  function renderChartLegend() {
    if (!chartLegend) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    let html = '';
    comparedSystems.forEach((s, idx) => {
      const color = getSysColor(idx, isDark);
      const isBase = (String(s.Id) === String(baseSystem?.Id));
      const sName = escapeHtml(s.DisplayName || s.Computer);
      const label = (isBase ? 'Basis: ' : '') + sName;
      const hasSeries = (s.Telemetry?.Series && s.Telemetry.Series.length > 0);
      const testType = hasSeries ? (s.Telemetry?.TestType || 'Lasttest') : 'keine Zeitreihe';
      html += `<div class="legend-item">
        <div class="legend-color" style="background: ${color};"></div>
        <span>${label} (${escapeHtml(testType)})</span>
      </div>`;
    });

    chartLegend.innerHTML = html;
  }

  // 6. CANVAS CHART RENDERING (MULTI-SYSTEM CANVAS)
  function renderChart() {
    if (!canvas || !chartWrapper) return;
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

    if (comparedSystems.length === 0) {
      ctx.fillStyle = isDark ? '#A0A0A0' : '#5F6368';
      ctx.font = '14px system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('Keine Systeme zur Anzeige ausgewählt.', width / 2, height / 2);
      return;
    }

    const padding = { top: 30, right: 60, bottom: 40, left: 55 };
    const chartW = width - padding.left - padding.right;
    const chartH = height - padding.top - padding.bottom;

    // Maximale Zeit ermitteln
    let tMax = 120;
    comparedSystems.forEach(s => {
      const srs = s.Telemetry?.Series || [];
      if (srs.length > 0) {
        const lastT = srs[srs.length - 1].T;
        if (lastT > tMax) tMax = lastT;
      }
    });

    const tempMax = 110;
    const getX = t => padding.left + (t / tMax) * chartW;
    const getYTemp = temp => padding.top + chartH - (temp / tempMax) * chartH;

    // GRID LINES (Temperaturskala 0..100 °C)
    ctx.strokeStyle = isDark ? '#363636' : '#ECEFF1';
    ctx.lineWidth = 1;
    ctx.fillStyle = isDark ? '#808080' : '#888888';
    ctx.font = '11px system-ui, sans-serif';

    [0, 25, 50, 75, 100].forEach(deg => {
      const y = getYTemp(deg);
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(padding.left + chartW, y);
      ctx.stroke();

      ctx.textAlign = 'right';
      ctx.fillText(deg + ' °C', padding.left - 8, y + 4);
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

    // KURVEN ZEICHNEN
    comparedSystems.forEach((s, idx) => {
      const srs = s.Telemetry?.Series || [];
      if (srs.length < 2) return;
      const color = getSysColor(idx, isDark);
      const isBase = (String(s.Id) === String(baseSystem?.Id));

      ctx.save();
      ctx.strokeStyle = color;
      ctx.lineWidth = isBase ? 3.0 : 2.0;
      if (!isBase && idx % 2 === 1) ctx.setLineDash([6, 3]);

      let inSegment = false;
      srs.forEach(pt => {
        const val = (chartMode === 'cpu')
          ? pt.Temp
          : (pt.GpuTemp != null ? pt.GpuTemp : pt.IGpuTemp);

        if (val != null && val > 0) {
          const x = getX(pt.T);
          const y = getYTemp(val);
          if (!inSegment) {
            ctx.beginPath();
            ctx.moveTo(x, y);
            inSegment = true;
          } else {
            ctx.lineTo(x, y);
          }
        } else {
          if (inSegment) {
            ctx.stroke();
            inSegment = false;
          }
        }
      });
      if (inSegment) ctx.stroke();
      ctx.restore();
    });

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

      renderChartStatic();

      const cx = padding.left + ratio * chartW;

      // Crosshair
      ctx.save();
      ctx.strokeStyle = isDark ? '#707070' : '#A0A0A0';
      ctx.setLineDash([2, 2]);
      ctx.beginPath();
      ctx.moveTo(cx, padding.top);
      ctx.lineTo(cx, padding.top + chartH);
      ctx.stroke();

      // Tooltip HTML bauen
      const mm = Math.floor(targetT / 60);
      const ss = Math.floor(targetT % 60);
      const timeStr = String(mm).padStart(2, '0') + ':' + String(ss).padStart(2, '0');

      let tipHtml = `
        <div style="font-weight: 700; margin-bottom: 6px; border-bottom: 1px solid var(--card-border); padding-bottom: 3px;">
          Zeit: ${timeStr} (${targetT.toFixed(0)} s)
        </div>
      `;

      comparedSystems.forEach((s, idx) => {
        const srs = s.Telemetry?.Series || [];
        if (srs.length === 0) return;

        let closest = srs[0];
        let minDiff = Infinity;
        srs.forEach(pt => {
          const diff = Math.abs(pt.T - targetT);
          if (diff < minDiff) { minDiff = diff; closest = pt; }
        });

        const color = getSysColor(idx, isDark);
        const isBase = (String(s.Id) === String(baseSystem?.Id));
        const sName = escapeHtml(s.DisplayName || s.Computer);
        const name = (isBase ? 'Basis: ' : '') + sName;

        if (chartMode === 'cpu') {
          const tempStr = closest.Temp != null ? closest.Temp.toFixed(1) + ' °C' : 'n/v';
          const mhzStr = closest.MHz != null ? closest.MHz.toFixed(0) + ' MHz' : 'n/v';
          const wattStr = closest.CpuW != null ? closest.CpuW.toFixed(1) + ' W' : 'n/v';

          tipHtml += `<div style="display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-top: 3px;">
            <span style="color: ${color}; font-weight: 600;">● ${name}</span>
            <span style="font-weight: 700;">${tempStr} &middot; ${mhzStr} &middot; ${wattStr}</span>
          </div>`;

          if (closest.Temp != null && closest.Temp > 0) {
            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.arc(cx, getYTemp(closest.Temp), 4.5, 0, Math.PI * 2);
            ctx.fill();
          }
        } else {
          // GPU
          const gTemp = closest.GpuTemp != null ? closest.GpuTemp : closest.IGpuTemp;
          const gMhz = closest.GpuMHz != null ? closest.GpuMHz : closest.IGpuMHz;
          const gWatt = closest.GpuW != null ? closest.GpuW : closest.IGpuW;

          const tempStr = gTemp != null ? gTemp.toFixed(1) + ' °C' : 'n/v';
          const mhzStr = gMhz != null ? gMhz.toFixed(0) + ' MHz' : 'n/v';
          const wattStr = gWatt != null ? gWatt.toFixed(1) + ' W' : 'n/v';
          const fpsStr = closest.Fps != null ? (' &middot; ' + closest.Fps.toFixed(0) + ' Bilder/s') : '';

          tipHtml += `<div style="display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-top: 3px;">
            <span style="color: ${color}; font-weight: 600;">● ${name}</span>
            <span style="font-weight: 700;">${tempStr} &middot; ${mhzStr} &middot; ${wattStr}${fpsStr}</span>
          </div>`;

          if (gTemp != null && gTemp > 0) {
            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.arc(cx, getYTemp(gTemp), 4.5, 0, Math.PI * 2);
            ctx.fill();
          }
        }
      });

      ctx.restore();

      tooltip.innerHTML = tipHtml;
      tooltip.style.display = 'block';

      let tooltipX = cx + 15;
      if (tooltipX + 240 > width) tooltipX = cx - 250;
      tooltip.style.left = Math.max(10, tooltipX) + 'px';
      tooltip.style.top = (padding.top + 10) + 'px';
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
    $json = $json -replace '</', '<\/'
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
        [Alias('DatenOrdner', 'AppDir')]
        [string]$DatabaseDir = '',
        [string]$ReportDir = '',
        [string[]]$SystemPaths = @()
    )

    $target = $OutputPath
    if (-not $target) {
        if ($DatabaseDir -and (Test-Path -LiteralPath $DatabaseDir) -and (Test-Path -LiteralPath (Join-Path $DatabaseDir 'Datenbank'))) {
            $rep = Join-Path $DatabaseDir 'Berichte'
            if (-not (Test-Path -LiteralPath $rep)) { New-Item -ItemType Directory -Path $rep -Force | Out-Null }
            $target = Join-Path $rep 'Dashboard.html'
        } elseif ($script:DataDir -and (Test-Path -LiteralPath $script:DataDir)) {
            $target = Join-Path $script:DataDir 'Berichte\Dashboard.html'
        } elseif (Test-Path -LiteralPath 'Minibench-Daten\Berichte') {
            $target = (Convert-Path 'Minibench-Daten\Berichte') + '\Dashboard.html'
        } elseif (Test-Path -LiteralPath 'Aktueller Build\Minibench-Daten\Berichte') {
            $target = (Convert-Path 'Aktueller Build\Minibench-Daten\Berichte') + '\Dashboard.html'
        } else {
            $target = Join-Path (Get-Location) 'Dashboard.html'
        }
    }

    return (New-BenchDashboardHtml -OutputPath $target -DatabaseDir $DatabaseDir -ReportDir $ReportDir -SystemPaths $SystemPaths)
}

function Show-BenchDashboard {
    [CmdletBinding()]
    param(
        [string]$DatabaseDir = '',
        [string]$ReportDir = '',
        [string]$OutputPath = '',
        [string[]]$SystemPaths = @()
    )

    $f = Export-BenchDashboardHtml -OutputPath $OutputPath -DatabaseDir $DatabaseDir -ReportDir $ReportDir -SystemPaths $SystemPaths
    if ($f -and (Test-Path -LiteralPath $f)) {
        Start-Process $f
    }
    return $f
}