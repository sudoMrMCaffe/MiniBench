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
        param([string]$ReportFolder, [string]$LeafFolder, [string[]]$FileNames = @('Lasttest-Verlauf.csv', 'Sensoren_Lasttest.csv'))
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
            foreach ($fn in $FileNames) {
                $rawCsv = Join-Path $cand $fn
                if (Test-Path -LiteralPath $rawCsv) {
                    try { $lines = @([System.IO.File]::ReadAllLines($rawCsv, [System.Text.Encoding]::UTF8)); if ($lines.Count -gt 1) { break } } catch { }
                }
            }
            if ($lines.Count -gt 1) { break }

            $zipPath = Join-Path $cand 'Anhang.zip'
            if (Test-Path -LiteralPath $zipPath) {
                try {
                    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
                    foreach ($fn in $FileNames) {
                        $entry = $zip.GetEntry($fn)
                        if (-not $entry) {
                            $entry = @($zip.Entries | Where-Object { $_.Name -ieq $fn }) | Select-Object -First 1
                        }
                        if ($entry) {
                            $sr = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
                            $zipLines = [System.Collections.Generic.List[string]]::new()
                            while (-not $sr.EndOfStream) { $zipLines.Add($sr.ReadLine()) }
                            $sr.Dispose()
                            if ($zipLines.Count -gt 1) { $lines = @($zipLines); break }
                        }
                    }
                    $zip.Dispose()
                    if ($lines.Count -gt 1) { break }
                } catch { }
            }

            # Auch .minibench-Archive im oder beim Ordner prüfen
            $mbCandidates = [System.Collections.Generic.List[string]]::new()
            if ($cand -like '*.minibench' -and (Test-Path -LiteralPath $cand -PathType Leaf)) {
                $mbCandidates.Add($cand)
            }
            if (Test-Path -LiteralPath ($cand + '.minibench') -PathType Leaf) {
                $mbCandidates.Add($cand + '.minibench')
            }
            if (Test-Path -LiteralPath $cand -PathType Container) {
                foreach ($mbf in @(Get-ChildItem -LiteralPath $cand -Filter '*.minibench' -File -ErrorAction SilentlyContinue)) {
                    $mbCandidates.Add($mbf.FullName)
                }
            }
            foreach ($mbPath in $mbCandidates) {
                try {
                    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                    $mbZip = [System.IO.Compression.ZipFile]::OpenRead($mbPath)
                    foreach ($fn in $FileNames) {
                        $mbEntry = @($mbZip.Entries | Where-Object { $_.Name -ieq $fn }) | Select-Object -First 1
                        if ($mbEntry) {
                            $sr = New-Object System.IO.StreamReader($mbEntry.Open(), [System.Text.Encoding]::UTF8)
                            $zipLines = [System.Collections.Generic.List[string]]::new()
                            while (-not $sr.EndOfStream) { $zipLines.Add($sr.ReadLine()) }
                            $sr.Dispose()
                            if ($zipLines.Count -gt 1) { $lines = @($zipLines); break }
                        } else {
                            # Falls Anhang.zip innerhalb des .minibench-Archivs liegt
                            $innerZipEntry = @($mbZip.Entries | Where-Object { $_.Name -ieq 'Anhang.zip' }) | Select-Object -First 1
                            if ($innerZipEntry) {
                                $ms = New-Object System.IO.MemoryStream
                                $st = $innerZipEntry.Open()
                                $st.CopyTo($ms)
                                $st.Dispose()
                                $ms.Position = 0
                                $innerArchive = New-Object System.IO.Compression.ZipArchive($ms)
                                $innerCsv = @($innerArchive.Entries | Where-Object { $_.Name -ieq $fn }) | Select-Object -First 1
                                if ($innerCsv) {
                                    $sr = New-Object System.IO.StreamReader($innerCsv.Open(), [System.Text.Encoding]::UTF8)
                                    $zipLines = [System.Collections.Generic.List[string]]::new()
                                    while (-not $sr.EndOfStream) { $zipLines.Add($sr.ReadLine()) }
                                    $sr.Dispose()
                                    if ($zipLines.Count -gt 1) { $lines = @($zipLines); $innerArchive.Dispose(); $ms.Dispose(); break }
                                }
                                $innerArchive.Dispose()
                                $ms.Dispose()
                            }
                        }
                    }
                    $mbZip.Dispose()
                    if ($lines.Count -gt 1) { break }
                } catch { }
            }
            if ($lines.Count -gt 1) { break }
        }

        # Fallback: Falls der Durchlauf gerade abgeschlossen wurde und im Arbeitsordner liegt
        if ($lines.Count -le 1) {
            $fallbackList = [System.Collections.Generic.List[string]]::new()
            foreach ($fn in $FileNames) {
                if ($script:WorkDir) {
                    $fallbackList.Add((Join-Path $script:WorkDir ('Anhang\' + $fn)))
                    $fallbackList.Add((Join-Path $script:WorkDir $fn))
                }
                if ($RawDir) {
                    $fallbackList.Add((Join-Path $RawDir $fn))
                }
            }
            foreach ($fb in $fallbackList) {
                if (Test-Path -LiteralPath $fb) {
                    try {
                        $fl = @([System.IO.File]::ReadAllLines($fb, [System.Text.Encoding]::UTF8))
                        if ($fl.Count -gt 1) { $lines = $fl; break }
                    } catch { }
                }
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

        # Nutzungsprofile (Gaming, Büro/Desktop, Workstation) - neu gewichtet ab v3.67
        $calcGeoScore = {
            param([System.Collections.Generic.List[double]]$vals, [System.Collections.Generic.List[double]]$wts)
            if (-not $vals -or $vals.Count -eq 0) { return 0 }
            $s = 0.0; $ws = 0.0
            for ($i = 0; $i -lt $vals.Count; $i++) {
                if ($vals[$i] -gt 0 -and $wts[$i] -gt 0) {
                    $s += $wts[$i] * [math]::Log($vals[$i])
                    $ws += $wts[$i]
                }
            }
            if ($ws -le 0) { return 0 }
            return [int][math]::Round([math]::Exp($s / $ws), 0)
        }

        # 1. Gaming (70 % GPU Render-FPS & Frametimes, 20 % Single-Core IPC, 10 % RAM & SSD; MT über 8 Kerne fließt nicht ein)
        $gVals = [System.Collections.Generic.List[double]]::new()
        $gWts  = [System.Collections.Generic.List[double]]::new()
        $gpuGamingVal = 0.0
        if ($gpuRend -gt 0) {
            if ($gpuRend1 -gt 0) {
                $gpuGamingVal = ($gpuRend * 0.7 + $gpuRend1 * 0.3) * 100.0
            } else {
                $gpuGamingVal = $gpuRend * 100.0
            }
        } elseif ($gpuScoreVal -gt 0) {
            $gpuGamingVal = $gpuScoreVal * 100.0
        }
        if ($gpuGamingVal -gt 0) { $gVals.Add($gpuGamingVal); $gWts.Add(0.70) }
        if ($cpuSt -gt 0) { $gVals.Add($cpuSt); $gWts.Add(0.20) }
        $ramGaming = $(if ($ramLesen -gt 0) { $ramLesen * 500.0 } else { 0.0 })
        $ssdGaming = $(if ($fastestDisk.R1 -gt 0) { $fastestDisk.R1 } elseif ($fastestDisk.SR -gt 0) { $fastestDisk.SR * 5.0 } else { 0.0 })
        if ($ramGaming -gt 0 -and $ssdGaming -gt 0) {
            $gVals.Add($ramGaming); $gWts.Add(0.05)
            $gVals.Add($ssdGaming); $gWts.Add(0.05)
        } elseif ($ramGaming -gt 0) {
            $gVals.Add($ramGaming); $gWts.Add(0.10)
        } elseif ($ssdGaming -gt 0) {
            $gVals.Add($ssdGaming); $gWts.Add(0.10)
        }
        $gamingScore = & $calcGeoScore $gVals $gWts

        # 2. Büro / Desktop (45 % SSD 4K Random Response R1/W1, 35 % CPU-ST Alltagsleistung, 20 % RAM-Latenz; 0 % GPU & MT)
        $dVals = [System.Collections.Generic.List[double]]::new()
        $dWts  = [System.Collections.Generic.List[double]]::new()
        $ssd4k = 0.0
        if ($fastestDisk.R1 -gt 0 -and $fastestDisk.W1 -gt 0) {
            $ssd4k = ($fastestDisk.R1 * 0.6 + $fastestDisk.W1 * 0.4)
        } elseif ($fastestDisk.R1 -gt 0) {
            $ssd4k = $fastestDisk.R1
        } elseif ($fastestDisk.SR -gt 0) {
            $ssd4k = $fastestDisk.SR * 5.0
        }
        if ($ssd4k -gt 0) { $dVals.Add($ssd4k); $dWts.Add(0.45) }
        if ($cpuSt -gt 0) { $dVals.Add($cpuSt); $dWts.Add(0.35) }
        $ramResp = 0.0
        if ($ramLatenz -gt 0) {
            $ramResp = 200000.0 / $ramLatenz
        } elseif ($ramLesen -gt 0) {
            $ramResp = $ramLesen * 100.0
        }
        if ($ramResp -gt 0) { $dVals.Add($ramResp); $dWts.Add(0.20) }
        $desktopScore = & $calcGeoScore $dVals $dWts

        # 3. Workstation (60 % CPU-MT, 15 % RAM, 10 % DISK, 10 % GPU, 5 % CPU-ST)
        $wVals = [System.Collections.Generic.List[double]]::new()
        $wWts  = [System.Collections.Generic.List[double]]::new()
        if ($cpuMt -gt 0) { $wVals.Add($cpuMt); $wWts.Add(0.60) }
        $ramBw = 0.0
        if ($ramLesen -gt 0 -or $ramSchreiben -gt 0 -or $ramKopieren -gt 0) {
            $ramBw = (($ramLesen * 1.0 + $ramSchreiben * 1.0 + $ramKopieren * 1.0) / 3.0) * 500.0
        }
        if ($ramBw -gt 0) { $wVals.Add($ramBw); $wWts.Add(0.15) }
        $ssdThru = 0.0
        if ($fastestDisk.SR -gt 0 -and $fastestDisk.SW -gt 0) {
            $ssdThru = ($fastestDisk.SR * 0.4 + $fastestDisk.SW * 0.6) * 5.0
        } elseif ($fastestDisk.SR -gt 0) {
            $ssdThru = $fastestDisk.SR * 5.0
        }
        if ($ssdThru -gt 0) { $wVals.Add($ssdThru); $wWts.Add(0.10) }
        $gpuVal = 0.0
        if ($gpuRend -gt 0) { $gpuVal = $gpuRend * 150.0 }
        elseif ($gpuVmb -gt 0) { $gpuVal = $gpuVmb * 40.0 }
        if ($gpuVal -gt 0) { $wVals.Add($gpuVal); $wWts.Add(0.10) }
        if ($cpuSt -gt 0) { $wVals.Add($cpuSt * 7.0); $wWts.Add(0.05) }
        $workstationScore = & $calcGeoScore $wVals $wWts

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

        # Aus Lasttest-Zeichenkette oder -Objekt nachparsen falls noch fehlend
        $cpuWMax = $null; $gpuWMax = $null
        if ($j.Sensoren -and $j.Sensoren.Last) {
            if ($j.Sensoren.Last.CpuWMax) { $cpuWMax = [double]$j.Sensoren.Last.CpuWMax }
            if ($j.Sensoren.Last.GpuWMax) { $gpuWMax = [double]$j.Sensoren.Last.GpuWMax }
        }
        if ($j.Lasttest) {
            if ($j.Lasttest -is [psobject] -or $j.Lasttest -is [System.Collections.IDictionary]) {
                if ($null -eq $cpuTMax -and $j.Lasttest.CpuTempMax) { $cpuTMax = [double]$j.Lasttest.CpuTempMax }
                if ($null -eq $gpuTMax -and $j.Lasttest.GpuTempMax) { $gpuTMax = [double]$j.Lasttest.GpuTempMax }
                if ($null -eq $cpuWMax -and $j.Lasttest.CpuWMax) { $cpuWMax = [double]$j.Lasttest.CpuWMax }
                if ($null -eq $gpuWMax -and $j.Lasttest.GpuWMax) { $gpuWMax = [double]$j.Lasttest.GpuWMax }
                if ($drosselung -eq 'keine' -and $j.Lasttest.Drosselung) { $drosselung = [string]$j.Lasttest.Drosselung }
                if ($taktAbfall -eq 0 -and $null -ne $j.Lasttest.TaktAbfall) { $taktAbfall = [double]$j.Lasttest.TaktAbfall }
            } else {
                $ltStr = [string]$j.Lasttest
                if ($null -eq $cpuTMax -and $ltStr -match 'CPU max (\d+)\s*°?C') { $cpuTMax = [double]$matches[1] }
                if ($drosselung -eq 'keine' -and $ltStr -match 'Drosselung:\s*([^,]+)') { $drosselung = $matches[1].Trim() }
                if ($null -eq $cpuMHzAvg -and $ltStr -match 'Ø\s*(\d+)\s*MHz') { $cpuMHzAvg = [double]$matches[1] }
                if ($null -eq $cpuWMax -and $ltStr -match 'max (\d+)\s*W') { $cpuWMax = [double]$matches[1] }
            }
        }

        # Zeitreihen-Messpunkte ermitteln (aus CSV oder synthetisieren)
        $series = [System.Collections.Generic.List[object]]::new()
        $throttleEvents = [System.Collections.Generic.List[object]]::new()
                $isNb = if (Get-Command Test-EntryIsNotebook -ErrorAction SilentlyContinue) { Test-EntryIsNotebook $j } else { $false }
        $ramGb = 16.0
        $ramStr = $(if ($j.Hardware -and $j.Hardware.RAM) { [string]$j.Hardware.RAM } else { '' })
        if ($ramStr -match '(\d+)\s*GB') { $ramGb = [double]$matches[1] }
        $diskCount = $(if ($j.Laufwerke) { [math]::Max(1, @($j.Laufwerke).Count) } else { 1 })

        $isBenchFallback = $false
        $csvLines = & $extractCsvSeries $repDir ([string]$j.Ordner) @('Lasttest-Verlauf.csv', 'Sensoren_Lasttest.csv')
        if ($csvLines.Count -le 1) {
            $benchCsv = & $extractCsvSeries $repDir ([string]$j.Ordner) @('Benchmark-Sensoren.csv', 'Sensoren_Benchmark.csv')
            if ($benchCsv.Count -gt 1) {
                $csvLines = $benchCsv
                $isBenchFallback = $true
            }
        }

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

                $sysW = $null
                if ($w -gt 0) {
                    $pEstPt = if (Get-Command Get-EstimatedSystemPower -ErrorAction SilentlyContinue) {
                        Get-EstimatedSystemPower -CpuW $w -GpuW $gW -IsNotebook:$isNb -RamGb $ramGb -DiskCount $diskCount -RamLoadPct 50.0 -DiskLoad
                    } else { $null }
                    if ($pEstPt -and $pEstPt.Verfuegbar) { $sysW = [math]::Round($pEstPt.P_AC, 1) }
                }

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
                    SysW     = $sysW
                })
            }
        }

        if ($series.Count -eq 0) {
            $objSeries = $null
            if ($j.LoadSeries -and @($j.LoadSeries).Count -gt 1) {
                $objSeries = @($j.LoadSeries)
            } elseif ($j.Sensoren_Lasttest -and @($j.Sensoren_Lasttest).Count -gt 1) {
                $objSeries = @($j.Sensoren_Lasttest)
            } elseif ($j.BenchSeries -and @($j.BenchSeries).Count -gt 1) {
                $objSeries = @($j.BenchSeries); $isBenchFallback = $true
            } elseif ($j.Sensoren_Benchmark -and @($j.Sensoren_Benchmark).Count -gt 1) {
                $objSeries = @($j.Sensoren_Benchmark); $isBenchFallback = $true
            } elseif ($script:BenchSeries -and @($script:BenchSeries).Count -gt 1 -and (-not $script:LoadSeries -or @($script:LoadSeries).Count -le 1)) {
                $objSeries = @($script:BenchSeries); $isBenchFallback = $true
            }

            if ($objSeries) {
                $step = [math]::Max(1, [int][math]::Floor($objSeries.Count / 70))
                for ($r = 0; $r -lt $objSeries.Count; $r += $step) {
                    $pt = $objSeries[$r]
                    $t = if ($null -ne $pt.T) { [double]$pt.T } else { 0.0 }
                    $temp = if ($null -ne $pt.CpuTemp) { [double]$pt.CpuTemp } elseif ($null -ne $pt.Temp) { [double]$pt.Temp } else { 0.0 }
                    $mhz = if ($null -ne $pt.MHz) { [double]$pt.MHz } elseif ($null -ne $pt.CpuMHzMax) { [double]$pt.CpuMHzMax } elseif ($null -ne $pt.CpuMHz) { [double]$pt.CpuMHz } else { 0.0 }
                    $w = if ($null -ne $pt.CpuW) { [double]$pt.CpuW } elseif ($null -ne $pt.Leistung) { [double]$pt.Leistung } else { 0.0 }
                    $gTemp = if ($null -ne $pt.GpuTemp) { [double]$pt.GpuTemp } else { 0.0 }
                    $gMhz = if ($null -ne $pt.GpuMHz) { [double]$pt.GpuMHz } else { 0.0 }
                    $gW = if ($null -ne $pt.GpuW) { [double]$pt.GpuW } else { 0.0 }
                    $igTemp = if ($null -ne $pt.IGpuTemp) { [double]$pt.IGpuTemp } else { 0.0 }
                    $igMhz = if ($null -ne $pt.IGpuMHz) { [double]$pt.IGpuMHz } else { 0.0 }
                    $igW = if ($null -ne $pt.IGpuW) { [double]$pt.IGpuW } else { 0.0 }
                    $fps = if ($null -ne $pt.Fps) { [double]$pt.Fps } else { 0.0 }

                    $sysW = $null
                    if ($w -gt 0) {
                        $pEstPt = if (Get-Command Get-EstimatedSystemPower -ErrorAction SilentlyContinue) {
                            Get-EstimatedSystemPower -CpuW $w -GpuW $gW -IsNotebook:$isNb -RamGb $ramGb -DiskCount $diskCount -RamLoadPct 50.0 -DiskLoad
                        } else { $null }
                        if ($pEstPt -and $pEstPt.Verfuegbar) { $sysW = [math]::Round($pEstPt.P_AC, 1) }
                    }

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
                        SysW     = $sysW
                    })
                }
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

                $pProf = if (Get-Command Get-SystemPowerProfile -ErrorAction SilentlyContinue) { Get-SystemPowerProfile -Entry $j } else { $null }
        $pDisplay = $(if ($pProf -and $pProf.Volllast -and $pProf.Volllast.Verfuegbar) {
            $(if ($pProf.Leerlauf -and $pProf.Leerlauf.Verfuegbar) {
                '~{0:N0} W / ~{1:N0} W' -f $pProf.Volllast.P_AC, $pProf.Leerlauf.P_AC
            } else {
                '~{0:N0} W' -f $pProf.Volllast.P_AC
            })
        } elseif ($pProf -and $pProf.Leerlauf -and $pProf.Leerlauf.Verfuegbar) {
            '~{0:N0} W (Leerlauf)' -f $pProf.Leerlauf.P_AC
        } else { 'n/v' })
        $pLoadVal = $(if ($pProf -and $pProf.Volllast -and $pProf.Volllast.Verfuegbar) { [math]::Round($pProf.Volllast.P_AC, 1) } else { $null })
        $pIdleVal = $(if ($pProf -and $pProf.Leerlauf -and $pProf.Leerlauf.Verfuegbar) { [math]::Round($pProf.Leerlauf.P_AC, 1) } else { $null })
        $pLoadTip = $(if ($pProf -and $pProf.Volllast) { $pProf.Volllast.Aufschluesselung } else { '' })
        $pIdleTip = $(if ($pProf -and $pProf.Leerlauf) { $pProf.Leerlauf.Aufschluesselung } else { '' })
        $effCpu = $(if ($pProf -and $pProf.Effizienz) { $pProf.Effizienz.CpuMT_PerWatt } else { $null })
        $effGpu = $(if ($pProf -and $pProf.Effizienz) { $pProf.Effizienz.Gpu_PerWatt } else { $null })
        $effSys = $(if ($pProf -and $pProf.Effizienz) { $pProf.Effizienz.System_PerWatt } else { $null })

        $seriesDur = if ($series.Count -gt 0) { [int]$series[$series.Count - 1].T } else { 0 }
        $lasttestArt = if ($isBenchFallback) { 'Benchmark' } else { & $getLasttestArt ([string]$j.Lasttest) $seriesDur }

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
                PowerDisplay       = $pDisplay
                PowerLoad          = $pLoadVal
                PowerIdle          = $pIdleVal
                PowerLoadTip       = $pLoadTip
                PowerIdleTip       = $pIdleTip
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
                LAST_CpuTemp  = $cpuTMax
                LAST_GpuTemp  = $gpuTMax
                LAST_CpuWatt  = $cpuWMax
                LAST_TaktStab = $(if ($null -ne $taktAbfall -and $taktAbfall -ge 0) { [math]::Round(100 - $taktAbfall, 1) } else { $null })
                LAST_TaktAbfall = $taktAbfall
                POWER_LOAD      = $pLoadVal
                POWER_IDLE      = $pIdleVal
                EFF_CPU         = $effCpu
                EFF_GPU         = $effGpu
                EFF_SYS         = $effSys
            }
            Telemetry   = [ordered]@{
                TestType                 = $(if ($isBenchFallback) { 'Benchmark' } elseif ($lasttestArt) { $lasttestArt } else { 'Lasttest' })
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
                PowerProfile             = $pProf
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
        Version        = $(if ($script:ScriptVersion) { $script:ScriptVersion } else { '3.7' })
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
#>> EINBINDEN_DASHBOARD_TEMPLATE
    $dashDir = Join-Path $PSScriptRoot 'Dashboard'
    if (Test-Path -LiteralPath (Join-Path $dashDir 'dashboard.html')) {
        $rawHtml = [System.IO.File]::ReadAllText((Join-Path $dashDir 'dashboard.html'), [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        $rawCss  = [System.IO.File]::ReadAllText((Join-Path $dashDir 'dashboard.css'), [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        $rawDaten = [System.IO.File]::ReadAllText((Join-Path $dashDir 'daten.js'), [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        $rawProf = [System.IO.File]::ReadAllText((Join-Path $dashDir 'profile.js'), [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        $rawMat  = [System.IO.File]::ReadAllText((Join-Path $dashDir 'matrix.js'), [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        $rawDiag = [System.IO.File]::ReadAllText((Join-Path $dashDir 'diagramme.js'), [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        $js = @($rawDaten, $rawProf, $rawMat, $rawDiag) -join "`r`n`r`n"
        $html = $rawHtml.Replace('{{TITEL}}', 'Leos Minibench - Benchmark &amp; Diagnose Dashboard').Replace('{{THEME}}', 'data-theme="light"').Replace('{{CSS}}', $rawCss).Replace('{{JS}}', $js)
        return $html
    }
    return ''
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
    $curVer = if ($script:ScriptVersion) { $script:ScriptVersion } else { '3.7' }
    $html = $template.Replace('v3.7', ('v' + $curVer))

    # Daten einbetten
    $html = $html.Replace('window.MINIBENCH_DASHBOARD_DATA = window.MINIBENCH_DASHBOARD_DATA || null;', ('window.MINIBENCH_DASHBOARD_DATA = ' + $json + ';'))

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
