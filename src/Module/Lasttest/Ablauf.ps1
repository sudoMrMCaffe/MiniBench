# =====================================================================================
#                                     LASTTEST
# =====================================================================================
# Ab 2.3 mit Sensoren: Temperatur-, Takt-, Leistungs- und Lüfterkurven, Drosselnachweis und Abbruchschwelle.
# Ab 2.6 Grafiklast mit dem eigenen Rendertest (Direct3D 11) auf allen Grafikeinheiten gleichzeitig: Bilder/s-Verlauf,
# Treiber-Resets (TDR) und Bildfehler. Sensoren und Buchführung dürfen die Last nie abbrechen (Praxistest 02.10.2026:
# ein Fehler beim Zählen unplausibler Sensorwerte beendete den CPU-Lasttest nach 15 Sekunden ohne Ergebnis).
# Ab 2.65: Auswahl der Grafikeinheiten (-GpuAuswahl), Gegenprobe auf eine Bildratengrenze, Bilder/s im Verlauf als
# Mittel seit dem letzten Messpunkt, Sensorwerte wieder vollständig (sie kamen doppelt verpackt an und fielen alle weg).
if ($ModLast -and (Test-StepEnabled 'Last:alle')) {
    $ltNames = @{ CPU = 'CPU'; RAM = 'RAM'; GPU = 'Grafik'; Disk = 'Datenträger' }
    $ltTitle = (@($script:LastPlan.Keys | Where-Object { $script:LastPlan[$_] -gt 0 } | ForEach-Object { '{0} {1} Min.' -f $ltNames[$_], $script:LastPlan[$_] }) -join ', ')
    Invoke-Section ('Lasttest ({0})' -f $ltTitle) {
        if (-not $TypesLoaded) { Add-Line '  Übersprungen: C#-Routinen nicht verfügbar (Constrained Language Mode).'; Add-TestResult 'Lasttest' 'Übersprungen' 'Constrained Language Mode'; return }
        $plan = $script:LastPlan
        $threads = [Environment]::ProcessorCount

        # Sensoren öffnen und Leerlaufwerte messen, bevor die Last beginnt
        # Sensoren sind Beiwerk: Fehler beim Öffnen oder Lesen dürfen die Last nie verhindern
        # Öffnen höchstens 30 Sekunden (DiagSensors.OpenTimed), danach geht es mit den Windows-Werten weiter
        Show-Sub 'Lasttest' 'Sensoren werden geöffnet (höchstens 30 Sekunden)' -1
        try { [void](Open-SensorSession -Treiber:$SensorTreiber) } catch { Add-Line ('  Sensoren ließen sich nicht öffnen: {0}. Der Lasttest läuft mit Windows-Werten.' -f $_.Exception.Message) }
        $script:LoadBadSeen = @{}
        # verzögerte Sensorabfragen nur für den Lasttest zählen (nicht aus der Diagnose davor)
        try { [DiagSensors]::ResetStats() } catch { }
        $readLead = {
            param($CpuSample, [switch]$Disk)
            # ohne @(): Get-SensorReadings gibt die Liste schon als ein Array zurück, @() verpackte sie ein zweites Mal
            # (bis v2.6 fehlten dadurch im Lasttest alle Sensorwerte)
            $rd = @()
            try { $rd = ConvertTo-FlatReadings (Get-SensorReadings -CpuSample $CpuSample -MitDatentraeger:$Disk) } catch { try { $rd = @(ConvertFrom-CpuSampleReadings $CpuSample) } catch { $rd = @() } }
            try { Register-BadReadings $rd $script:LoadBadSeen } catch { }
            try { return (Get-SensorLead $rd) } catch { return (Get-SensorLead @()) }
        }
        Test-HintergrundlastVorMessung -Phase 'Lasttest'
        $cpuOf = { try { return (Get-CpuSample) } catch { return [pscustomobject]@{ Last = 0; Leistung = 0; MaxLeistung = 0; MaxFreq = 0; MHz = 0; MaxMHz = 0; Temp = $null; Quelle = 'Fehler' } } }
        $idleSamples = New-Object System.Collections.Generic.List[object]
        Show-Sub 'Lasttest' 'Leerlaufwerte werden gemessen' -1
        for ($i = 0; $i -lt 3; $i++) { [void]$idleSamples.Add((& $readLead (& $cpuOf) -Disk:($i -eq 0))); Start-Sleep -Milliseconds 700 }
        $idle = $idleSamples[$idleSamples.Count - 1]
        $tjMax = $null
        $tjFirst = @($idleSamples | Where-Object { $_.TjMax } | ForEach-Object { $_.TjMax }) | Select-Object -First 1
        if ($tjFirst) { $tjMax = [double]$tjFirst }
        $cpuLimit = Get-AbortLimit $LastAbbruchCpu $tjMax 100
        $gpuLimit = Get-AbortLimit $LastAbbruchGpu $null 90
        # automatisch: an TjMax erst nach rund einer Minute (20 Messpunkte), feste Schwellen nach rund 10 Sekunden
        $cpuHold = $(if (([string]$LastAbbruchCpu).Trim().ToLowerInvariant() -eq 'auto') { 20 } else { 3 })
        $script:LoadLimits = [pscustomobject]@{ Cpu = $cpuLimit; Gpu = $gpuLimit; TjMax = $tjMax }
        Send-GuiEvent 'SENSLIM' (Format-SensorValue $cpuLimit) (Format-SensorValue $gpuLimit) (Format-SensorValue $tjMax)
        Add-Line ('  Sensoren: {0}' -f (Get-SensorSourceText))
        Add-SensorGapFinding 'Der Lasttest'
        $isIdle = ($null -eq $idle.CpuLoad -or $idle.CpuLoad -lt 15)
        $leadPrefix = if ($isIdle) { 'Leerlauf vor der Last' } else { 'Sensoren vor der Last (bei {0} % Last)' -f [math]::Round($idle.CpuLoad) }
        Add-Line ('  {0}: CPU {1}, GPU {2}, Paketleistung {3}' -f $leadPrefix, $(if ($null -ne $idle.CpuTemp) { '{0:N0} °C ({1})' -f $idle.CpuTemp, $idle.CpuTempQ } else { 'Temperatur nicht verfügbar' }), $(if ($null -ne $idle.GpuTemp) { '{0:N0} °C' -f $idle.GpuTemp } else { 'nicht verfügbar' }), $(if ($null -ne $idle.CpuW) { '{0:N0} W' -f $idle.CpuW } else { 'nicht verfügbar' }))
        Add-Line ('  Abbruchschwelle: CPU {0}, GPU {1}. Der Test endet, wenn die CPU {2} oder die GPU rund 10 Sekunden darüber liegt.' -f $(if ($cpuLimit) { '{0:N0} °C{1}' -f $cpuLimit, $(if ($LastAbbruchCpu -eq 'auto') { $(if ($tjMax) { ' (TjMax)' } else { ' (automatisch)' }) } else { '' }) } else { 'aus' }), $(if ($gpuLimit) { '{0:N0} °C' -f $gpuLimit } else { 'aus' }), $(if ($cpuHold -ge 10) { 'rund eine Minute' } else { 'rund 10 Sekunden' }))
        if ($cpuLimit -and $idle.CpuTempQ -eq 'ACPI') { Add-Line '  Hinweis: Als CPU-Temperatur steht nur die ACPI-Thermalzone zur Verfügung; sie zählt für den Abbruch erst, wenn sie sich unter Last bewegt.' }
        elseif ($cpuLimit -and $null -eq $idle.CpuTemp) { Add-Line '  Hinweis: Keine CPU-Temperatur verfügbar, die CPU-Abbruchschwelle kann nicht greifen.' }

        $t0 = Get-Date
        $end = @{}
        foreach ($k in @($plan.Keys)) { if ($plan[$k] -gt 0) { $end[$k] = $t0.AddMinutes($plan[$k]) } }
        $tEnd = @($end.Values | Sort-Object -Descending)[0]
        $stopFile = Join-Path $script:CpDir 'stop.flag'
        Remove-Item $stopFile -Force -ErrorAction SilentlyContinue
        [DiagCpu]::Stop = $false; [DiagRam]::Stop = $false; [DiagDiskStress]::Stop = $false
        $cpuTask = $null; $ramTask = $null; $diskTask = $null; $gpuRuns = @()
        $script:LoadLimitNotes = New-Object System.Collections.Generic.List[string]
        $diskPath = $null; $diskLetter = ''
        $script:LoadGpuSkipped = ''

        Add-Line '  Belastet werden gleichzeitig, jeweils mit eigener Dauer:'
        # try/finally: Was auch passiert, keine Last läuft nach diesem Abschnitt weiter (Folgemodule, Testdatei, Vorschaufenster)
        $script:LoadPause = $null
        try {
        Start-PauseWatch
        if ($end.ContainsKey('CPU')) {
            # ab v2.67 in einem eigenen Prozess ohne Speicherbereinigung (LoadJob, DiagLoadHost)
            $cpuTask = Start-LoadJob 'cpu' ([int]($plan.CPU * 60) + 60) $threads
            Add-Line ('    Prozessor      : {0} Min., {1} Threads mit Ergebnisprüfung{2}' -f $plan.CPU, $threads, $(if ($cpuTask.External) { ', eigener Prozess' } elseif ($cpuTask.Note) { ', ' + $cpuTask.Note } else { '' }))
        }
        if ($end.ContainsKey('RAM')) {
            # RAM-Test eine Stufe unter normal und mit CPU-Last nur auf einem Teil der Kerne: sonst nimmt er dem
            # Grafiktreiber und der CPU-Last die Rechenzeit, Bilder/s und Auslastung schwanken stark (Praxistest 02.10.)
            $ramMax = $(if ($end.ContainsKey('CPU')) { [math]::Max(2, [int][math]::Floor($threads / 4)) } else { 0 })
            $os = Get-CimCached Win32_OperatingSystem | Select-Object -First 1
            $ramTarget = [long]([double]$os.FreePhysicalMemory * 1KB * $LastRamProzent / 100)
            if (-not [Environment]::Is64BitProcess) { $ramTarget = [math]::Min($ramTarget, 1.2GB) }
            $ramTask = Start-LoadJob 'ram' ([int]($plan.RAM * 60) + 60) $threads $ramTarget $ramMax -Low
            Add-Line ('    Arbeitsspeicher: {0} Min., Mustertest über {1} ({2} % des freien RAM){3}' -f $plan.RAM, (Format-Size $ramTarget), $LastRamProzent, $(if ($ramTask.External) { ', eigener Prozess' } elseif ($ramTask.Note) { ', ' + $ramTask.Note } else { '' }))
        }
        if ($end.ContainsKey('GPU')) {
            # Rendertest auf jeder Grafikeinheit, jede mit eigenem Gerät und Thread; Vollbild nur für die erste
            $gSize = Get-RenderSize $GpuAufloesung; $gMode = Get-RenderPreviewMode $GpuAnzeige
            $gSel = Select-RenderAdapters @(Get-RenderAdapters) $GpuAuswahl
            $gAds = @($gSel.Adapter)
            if ($gSel.Hinweis) { Add-Line ('    Grafik         : {0}' -f $gSel.Hinweis) }
            $script:DisplayRates = @(Get-DisplayRefreshRates)
            if (-not $gAds.Count) {
                $script:LoadGpuSkipped = Get-RenderUnavailableText
                Add-Line ('    Grafik         : entfällt, {0}' -f $script:LoadGpuSkipped)
                [void]$end.Remove('GPU')
            } else {
                $k = 0
                foreach ($ad in $gAds) {
                    $r = New-Object GpuRun
                    $r.AdapterIndex = $ad.Index; $r.Width = $gSize[0]; $r.Height = $gSize[1]; $r.WarmupMs = 0; $r.MeasureMs = 0
                    $r.Preview = $(if ($gMode -eq 2 -and $k -gt 0) { 1 } else { $gMode }); $r.CheckEveryMs = 30000; $r.Title = 'Lasttest'; $r.ProbeLimit = $true
                    [void][DiagGpu]::Start($r)
                    $gpuRuns += [pscustomobject]@{ Ad = $ad; Run = $r; Geprueft = $false; Frames0 = 0L; T0 = (Get-Date) }
                    $k++
                }
                Add-Line ('    Grafik         : {0} Min., Rendertest {1}x{2} auf {3}, Bildprüfung alle 30 Sekunden{4}' -f $plan.GPU, $gSize[0], $gSize[1], (($gAds | ForEach-Object { '{0} ({1})' -f $_.Name, $_.Bezeichnung }) -join ' und '), $(if ($gSel.Auswahl -ne 'alle Grafikeinheiten') { ' (' + $gSel.Auswahl + ')' } else { '' }))
                Write-Checkpoint 'INFO' ('Lasttest Grafik auf {0}' -f (($gAds | ForEach-Object { $_.Name }) -join ', '))
            }
        }
        if ($end.ContainsKey('Disk')) {
            $diskLetter = $(if ($LastDiskLaufwerk) { $LastDiskLaufwerk.Substring(0, 1).ToUpperInvariant() } else { $env:SystemDrive.Substring(0, 1) })
            # freier Platz über .NET statt Get-Volume (WMI-Speicheranbieter, kann bei auffälligen USB-Datenträgern hängen)
            $vol = Get-DriveSpace $diskLetter
            if (-not $vol -or $vol.SizeRemaining -lt 2GB) {
                Add-Line ('    Datenträger    : Laufwerk {0}: hat zu wenig freien Platz oder fehlt, Datenträgerlast entfällt.' -f $diskLetter)
                $end.Remove('Disk')
            } else {
                $sizeB = Get-DiskStressBytes ([double]$vol.SizeRemaining)
                # FAT32 erlaubt höchstens 4 GB je Datei
                if ([string]$vol.FileSystem -match 'FAT') { $sizeB = [long][math]::Min([double]$sizeB, [double](4GB - 64MB)) }
                $diskPath = '{0}:\LeosMinibench-Lasttest.tmp' -f $diskLetter
                $diskTask = [DiagDiskStress]::RunAsync($diskPath, $sizeB, [int]($plan.Disk * 60))
                Add-Line ('    Datenträger    : {0} Min., Laufwerk {1}: mit {2} Testdatei, Schreiben, Lesen und Datenprüfung' -f $plan.Disk, $diskLetter, (Format-Size $sizeB))
                Write-Checkpoint 'INFO' ('Lasttest Datenträger auf {0}' -f $diskPath)
            }
        }
        # Ende neu bestimmen: Grafik oder Datenträger können oben entfallen sein
        $tEnd = $(if ($end.Count) { @($end.Values | Sort-Object -Descending)[0] } else { $t0 })
        Send-GuiEvent 'STOP' '1'
        Write-Step ('Lasttest läuft bis ca. {0:HH:mm} Uhr. Die Schaltfläche "Test beenden"{1} beendet ihn vorzeitig.' -f $tEnd, $(if ($gpuRuns.Count -and $gMode -gt 0) { ' oder Esc im Fenster des Rendertests' } else { '' }))

        $samples = New-Object System.Collections.ArrayList
        $done = @{}; $stopped = $false; $abort = $null; $diskStopAt = $null; $diskHung = $false
        $lastBytes = 0L; $lastT = Get-Date
        while ($true) {
            $now = Get-Date
            foreach ($lj in @($cpuTask, $ramTask)) { if ($lj) { try { $lj.Refresh() } catch { } } }
            if ($cpuTask -and -not $done.ContainsKey('CPU') -and ($now -ge $end.CPU -or $stopped -or $cpuTask.Done)) { $cpuTask.Stop(); $done.CPU = $now }
            if ($ramTask -and -not $done.ContainsKey('RAM') -and ($now -ge $end.RAM -or $stopped -or $ramTask.Done)) { $ramTask.Stop(); $done.RAM = $now }
            if ($end.ContainsKey('GPU') -and -not $done.ContainsKey('GPU')) {
                if (@($gpuRuns | Where-Object { $_.Run.EscPressed }).Count -and -not $stopped) { $stopped = $true; Write-Step 'Rendertest mit Esc beendet, der Lasttest endet vorzeitig.' }
                $allGone = -not @($gpuRuns | Where-Object { -not $_.Run.Done }).Count
                if ($now -ge $end.GPU -or $stopped -or $allGone) { foreach ($g in $gpuRuns) { $g.Run.Stop = $true }; $done.GPU = $now }
            }
            if ($diskTask -and -not $done.ContainsKey('Disk')) {
                if (($stopped -or $now -ge $end.Disk) -and -not $diskStopAt) { [DiagDiskStress]::Stop = $true; $diskStopAt = $now }
                if ($diskTask.IsCompleted) { $done.Disk = $now }
                # hängender Lese- oder Schreibzugriff (sterbendes Laufwerk, abgezogener USB-Datenträger): nach 2 Minuten aufgeben
                elseif ($diskStopAt -and ($now - $diskStopAt).TotalSeconds -ge 120) {
                    $done.Disk = $now; $diskHung = $true
                    Write-Step ('Datenträgertest auf Laufwerk {0}: reagiert seit 2 Minuten nicht, der Lasttest endet ohne ihn.' -f $diskLetter)
                    Write-Checkpoint 'INFO' ('Lasttest Datenträger hängt auf {0}' -f $diskPath)
                }
            }
            $pending = @($end.Keys | Where-Object { -not $done.ContainsKey($_) })
            if (-not $pending.Count) { break }

            $s = & $cpuOf
            $lead = & $readLead $s
            $el = ($now - $t0).TotalSeconds
            $bytes = [DiagDiskStress]::BytesRead + [DiagDiskStress]::BytesWritten
            $dMBs = $(if ($diskTask -and -not $done.ContainsKey('Disk')) { [math]::Round(($bytes - $lastBytes) / 1MB / [math]::Max(0.5, ($now - $lastT).TotalSeconds)) } else { $null })
            $lastBytes = $bytes; $lastT = $now
            $gpuOn = ($gpuRuns.Count -and -not $done.ContainsKey('GPU'))
            # Bilder/s als Mittel seit dem letzten Messpunkt (bis v2.6 die letzte halbe Sekunde, die oft genau in das
            # Lesen der Sensoren fiel und die Kurve zackig machte)
            $fpsNow = @(foreach ($g in $gpuRuns) { $fv = $null; try { $fv = Get-FpsSince $g } catch { }; $fv })
            $fps1 = $(if ($gpuOn -and $gpuRuns.Count -and -not $gpuRuns[0].Run.Done) { $fpsNow[0] } else { $null })
            $fps2 = $(if ($gpuOn -and $gpuRuns.Count -gt 1 -and -not $gpuRuns[1].Run.Done) { $fpsNow[1] } else { $null })
            # Gegenprobe auf eine Bildratengrenze: Ergebnis gleich nach den ersten Sekunden melden
            foreach ($g in $gpuRuns) {
                if ($g.Geprueft -or -not $g.Run.ProbeDone) { continue }
                $g.Geprueft = $true
                $lim = $null; try { $lim = Get-FpsLimitAssessment $g.Run.ProbeFpsFull $g.Run.ProbeFpsLight $script:DisplayRates } catch { }
                if ($lim -and $lim.Begrenzt) {
                    $txt = ('{0} ({1}): {2}' -f $g.Ad.Name, $g.Ad.Bezeichnung, $lim.Text)
                    $script:LoadLimitNotes.Add($txt)
                    Add-Finding WARNUNG 'Grafik' $txt
                    Write-Step ('Bildratengrenze auf {0}: die Grafikeinheit wird nicht voll belastet.' -f $g.Ad.Name)
                }
            }
            try { [void]$samples.Add((New-LoadSample $el $s $lead $dMBs ([bool]($cpuTask -and -not $done.ContainsKey('CPU'))) $fps1 $fps2)) } catch { }
            try { Send-SensorLead $el $lead $fps1 $fps2 } catch { }
            # Abbruchschwelle: drei Messpunkte in Folge (rund 10 Sekunden) an oder über der Grenze
            if (-not $abort -and -not $stopped -and $samples.Count) {
                $recent = $samples.GetRange([math]::Max(0, $samples.Count - 25), [math]::Min(25, $samples.Count))
                $ab = $null; try { $ab = Test-LoadAbort $recent $cpuLimit $gpuLimit 3 $cpuHold } catch { }
                if ($ab -and $ab.Abbruch) {
                    $abort = $ab; $stopped = $true
                    $script:LoadAbort = [pscustomobject]@{ T = [int]$el; Grund = $ab.Grund; Art = $ab.Art; Wert = $ab.Wert }
                    Write-Step ('Lasttest abgebrochen: {0}.' -f $ab.Grund)
                    Write-Checkpoint 'INFO' ('Lasttest-Abbruch: {0}' -f $ab.Grund)
                    continue
                }
            }
            $pc = [int][math]::Min(99.0, $el / [math]::Max(1.0, ($tEnd - $t0).TotalSeconds) * 100.0)
            $left = $tEnd - $now; if ($left.TotalSeconds -lt 0) { $left = [TimeSpan]::Zero }
            $tTxt = $(if ($null -ne $lead.CpuTemp) { '{0:N0} °C{1}' -f $lead.CpuTemp, $(if ($lead.CpuTempQ -eq 'ACPI') { ' (ACPI)' } else { '' }) } else { 'n/v' })
            $st = @('CPU {0} %   Takt {1} MHz{2}   Temp {3}' -f $s.Last, $s.MHz, $(if ($null -ne $lead.CpuMHzMax) { ' (höchster Kern {0} MHz)' -f $lead.CpuMHzMax } else { '' }), $tTxt)
            if ($null -ne $lead.CpuW) { $st += ('{0:N0} W' -f $lead.CpuW) }
            if ($null -ne $lead.GpuTemp) { $st += ('GPU {0:N0} °C' -f $lead.GpuTemp) }
            if ($null -ne $lead.GpuMHz) { $st += ('GPU {0:N0} MHz' -f $lead.GpuMHz) }
            if ($null -ne $lead.GpuW) { $st += ('GPU {0:N0} W' -f $lead.GpuW) }
            if ($gpuOn) {
                $fpsAll = @($gpuRuns | Where-Object { -not $_.Run.Done } | ForEach-Object { '{0:N0}' -f [double]$_.Run.LiveFps })
                if ($fpsAll.Count) { $st += ('{0} Bilder/s' -f ($fpsAll -join ' und ')) }
            }
            if ($cpuTask) { $st += ('Rechenfehler {0}' -f $cpuTask.Errors) }
            if ($ramTask) { $st += ('RAM-Fehler {0}' -f $ramTask.Errors) }
            if ($diskTask) { $st += ('Datenträger {0} MB/s, Fehler {1}' -f $(if ($null -ne $dMBs) { $dMBs } else { 0 }), ([DiagDiskStress]::Errors + [DiagDiskStress]::IoErrors)) }
            Show-Sub ('Lasttest   {0} %   noch {1:hh\:mm\:ss}   aktiv: {2}' -f $pc, $left, (($pending | ForEach-Object { $ltNames[$_] }) -join ', ')) ($st -join '   ') $pc
            for ($w = 0; $w -lt 5 -and -not $stopped; $w++) {
                Start-Sleep -Milliseconds 500
                if ((Test-Path $stopFile) -or (Test-SkipRequested)) { Remove-Item $stopFile -Force -ErrorAction SilentlyContinue; $stopped = $true; Write-Step 'Lasttest wird vorzeitig beendet ...' }
            }
            # nach dem Stopp warten die Komponenten auf ihr Ende: nicht im Leerlauf kreisen
            if ($stopped) { Start-Sleep -Milliseconds 500 }
        }
        [DiagCpu]::Stop = $true; [DiagRam]::Stop = $true; [DiagDiskStress]::Stop = $true
        foreach ($lj in @($cpuTask, $ramTask)) { if ($lj) { try { $lj.Stop() } catch { } } }
        Send-GuiEvent 'STOP' '0'
        Show-Sub 'Lasttest' 'wird beendet' -1
        try { if ($cpuTask) { [void]$cpuTask.Wait(30000) } } catch { }
        try { if ($ramTask) { [void]$ramTask.Wait(120000) } } catch { }
        try { if ($diskTask) { [void]$diskTask.Wait(120000) } } catch { }
        foreach ($g in $gpuRuns) { $g.Run.Stop = $true }
        $gw = [Diagnostics.Stopwatch]::StartNew()
        while (@($gpuRuns | Where-Object { -not $_.Run.Done }).Count -and $gw.Elapsed.TotalSeconds -lt 20) { Start-Sleep -Milliseconds 200 }
        }
        finally {
            [DiagCpu]::Stop = $true; [DiagRam]::Stop = $true; [DiagDiskStress]::Stop = $true
            # Lastprozesse: beenden lassen, wer dann noch läuft, wird beendet
            foreach ($lj in @($cpuTask, $ramTask)) { if ($lj) { try { $lj.Stop(); if (-not $lj.Wait(5000)) { $lj.Kill() }; $lj.Cleanup() } catch { } } }
            foreach ($g in @($gpuRuns)) { try { $g.Run.Stop = $true } catch { } }
            Send-GuiEvent 'STOP' '0'
            try { [DiagRam]::MaxThreads = 0; [DiagRam]::LowPriority = $false } catch { }
            if (-not $script:LoadPause) { $script:LoadPause = Stop-PauseWatch ((Get-Date) - $t0).TotalSeconds }
        }
        if ($diskPath) { Remove-Item $diskPath -Force -ErrorAction SilentlyContinue }
        $real = (Get-Date) - $t0
        # Abkühlung: 30 Sekunden nachmessen, wie schnell die Temperatur fällt
        $coolStart = Get-Date
        if ($samples.Count -and $null -ne $samples[$samples.Count - 1].CpuTemp) {
            while (((Get-Date) - $coolStart).TotalSeconds -lt 30) {
                Show-Sub 'Lasttest' ('Abkühlung wird gemessen ({0:N0} s)' -f (30 - ((Get-Date) - $coolStart).TotalSeconds)) -1
                $s = & $cpuOf; $lead = & $readLead $s
                $el = ((Get-Date) - $t0).TotalSeconds
                try { $cs0 = New-LoadSample $el $s $lead $null $false; $cs0.Abkuehlung = $true; [void]$samples.Add($cs0) } catch { }
                try { Send-SensorLead $el $lead } catch { }
                Start-Sleep -Milliseconds 2500
            }
        }
        Hide-Sub
        $whea = @(Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $t0 } 50)
        $wheaHard = @($whea | Where-Object { $_.Level -le 2 })
        $fwEv = @(Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'; Id = 37; StartTime = $t0 } 100)
        $setStatus = { param($s) if ((Get-StatusRank $s) -gt (Get-StatusRank $script:LtStatus)) { $script:LtStatus = $s } }
        $script:LtStatus = 'OK'
        $dur = { param($k) $d = $(if ($done.ContainsKey($k)) { $done[$k] - $t0 } else { $real }); '{0:hh\:mm\:ss}' -f $d }
        $stopTxt = $(if ($abort) { ' (abgebrochen: {0})' -f $abort.Grund } elseif ($stopped) { ' (vorzeitig beendet)' } else { '' })
        $loadS = @($samples | Where-Object { -not $_.Abkuehlung })
        Add-Line
        Add-Line ('  Gesamtdauer: {0:hh\:mm\:ss}{1}, WHEA-Ereignisse: {2}' -f $real, $stopTxt, $whea.Count)
        # Unterbrechungen: hält die Speicherbereinigung einen Prozess an, steht dort jede Last. CPU und RAM laufen ab v2.67
        # in eigenen Prozessen (dort gemessen), Grafik, Datenträger und Sensoren im Arbeitsprozess.
        $pauseRows = New-Object System.Collections.Generic.List[object]
        foreach ($pj in @(@{ J = $cpuTask; N = 'CPU-Last'; K = 'CPU' }, @{ J = $ramTask; N = 'RAM-Last'; K = 'RAM' })) {
            if (-not $pj.J) { continue }
            $pt = Get-LoadJobPauseText $pj.J ((& $dur $pj.K) -as [TimeSpan]).TotalSeconds
            if ($pt) { $pauseRows.Add([pscustomobject]@{ Zeile = ('der {0} (eigener Prozess)' -f $pj.N); Kurz = $pj.N; P = $pt }) }
        }
        $ext = $pauseRows.Count
        if ($script:LoadPause -and ($gpuRuns.Count -or $diskTask -or -not $ext)) {
            $pauseRows.Add([pscustomobject]@{ Zeile = $(if ($ext) { 'im Arbeitsprozess (Grafik, Datenträger, Sensoren)' } else { 'der Last' }); Kurz = $(if ($ext) { 'Arbeitsprozess' } else { 'Last' }); P = $script:LoadPause })
        }
        foreach ($pr in $pauseRows) {
            Add-Line ('  Unterbrechungen {0}: {1}' -f $pr.Zeile, $pr.P.Text)
            if ($pr.P.Auffaellig) { Add-Finding INFO 'Lasttest' ('Die Last lief nicht gleichmäßig ({0}): {1}. In diesen Momenten stand die Last still, Auslastung und Bilder/s brachen ein.' -f $pr.Kurz, $pr.P.Text) }
        }
        foreach ($lj in @($cpuTask, $ramTask)) { if ($lj -and $lj.Note) { Add-Line ('  Hinweis {0}-Last: {1}' -f $(if ($lj.Mode -eq 'ram') { 'RAM' } else { 'CPU' }), $lj.Note) } }

        # Kennzahlen und Zeilen gemeinsam mit dem Benchmark (ab v2.7: Get-SensorSeriesStats, Get-SensorSeriesLines)
        $sst = Get-SensorSeriesStats $loadS
        $mhzAll = $sst.Mhz; $tv = @($sst.Acpi); $tStatic = $sst.AcpiFest; $tMax = $sst.AcpiMax
        $cpuTMax = $sst.CpuTMax; $gpuTMax = $sst.GpuTMax; $cpuWMax = $sst.CpuWMax; $gpuWMax = $sst.GpuWMax
        $fanMax = $sst.FanMax; $diskTMax = $sst.DiskTMax; $coreAll = @($sst.Kern)
        $igTMax = $sst.IGpuTMax; $igWMax = $sst.IGpuWMax
        $gpuMhz = @($sst.GpuMhz); $igMhz = @($sst.IGpuMhz)
        $gName = $(if ($idle.GpuName) { $idle.GpuName } else { [string]$lead.GpuName }); $igName = $(if ($idle.IGpuName) { $idle.IGpuName } else { [string]$lead.IGpuName })
        foreach ($ln in @(Get-SensorSeriesLines $sst $idle $tjMax $script:LoadBadSeen $gName $igName -GpuErwartet:([bool]$gpuRuns.Count))) { Add-Line $ln }
        $cool = @($samples | Where-Object { $_.Abkuehlung -and $null -ne $_.CpuTemp })
        if ($cool.Count -and $null -ne $cpuTMax) { Add-Line ('  Abkühlung: {0} s nach Lastende {1:N0} °C, {2:N0} K unter dem Höchstwert' -f ($cool[$cool.Count - 1].T - $loadS[$loadS.Count - 1].T), $cool[$cool.Count - 1].CpuTemp, ($cpuTMax - $cool[$cool.Count - 1].CpuTemp)) }
        if (@($loadS | ForEach-Object { $_.MHz } | Select-Object -Unique).Count -le 1 -and $loadS.Count -gt 3) { Add-Line '  Hinweis: Der Taktwert von Windows blieb über alle Messpunkte gleich (Festwert des Leistungszählers); bewertet wird der Sensortakt, falls vorhanden.' }

        if ($cpuTask) {
            $cpuErr = $cpuTask.Errors
            $cs = @($loadS | Where-Object { $_.Cpu })
            $perfMin = (@($cs | Where-Object { $_.T -ge 20 }) | Measure-Object Leistung -Minimum).Minimum
            $mhz = $cs | Measure-Object MHz -Average
            $cpuMin = ((& $dur 'CPU') -as [TimeSpan]).TotalMinutes
            $th = Get-ThrottleAnalysis -Samples $cs -TjMax $tjMax -FirmwareEvents $fwEv.Count
            $script:LoadThrottle = $th
            $st = 'OK'
            if ($cpuErr -gt 0) { Add-Finding KRITISCH 'Lasttest' ('{0} Rechenfehler unter CPU-Dauerlast: CPU instabil (Übertaktung, Undervolting, Spannung, Kühlung oder Netzteil).' -f $cpuErr); $st = 'Fehler' }
            Add-Line '  Drosselnachweis:'
            Add-Line ('    Ergebnis: {0}' -f $th.Befund)
            foreach ($b in $th.Belege) { Add-Line ('    ' + $b) }
            if ($th.Beginn) { Add-Line ('    Takt dauerhaft gesunken ab {0}:{1:00} min' -f [int][math]::Floor($th.Beginn / 60), [int]($th.Beginn % 60)) }
            # Ein Effekt, ein Befund: Fällt der Takt unter den Basistakt, gehört das zum Drosselnachweis
            $lowPerf = ($perfMin -and $perfMin -lt 70)
            $lowTxt = $(if ($lowPerf) { ' Der Takt fiel dabei zeitweise auf {0} % des Basistakts, also unter den zugesicherten Grundtakt.' -f $perfMin } else { '' })
            if ($th.Stufe -and ($cpuMin -ge 2 -or $th.Status -eq 'thermisch')) {
                $lvl = $th.Stufe; $txt = $th.Befund + $lowTxt
                if ($lowPerf -and $th.Status -eq 'Leistungsgrenze') { $lvl = 'WARNUNG'; $txt += ' Energieprofil des Herstellers, Netzteilleistung und Akkubetrieb prüfen.' }
                elseif ($lowPerf) { $lvl = 'WARNUNG' }
                Add-Finding $lvl 'Lasttest' $txt
                if ($lvl -eq 'WARNUNG' -and $st -eq 'OK') { $st = 'Warnung' }
            } else {
                if ($th.Status -eq 'nicht bewertbar' -and $cpuMin -ge 3) { Add-Finding INFO 'Lasttest' ('Drosselnachweis nicht möglich: {0}.' -f $th.Befund) }
                if ($lowPerf) { Add-Finding WARNUNG 'Lasttest' ('Der CPU-Takt fiel unter Dauerlast zeitweise auf {0} % des Basistakts.' -f $perfMin); if ($st -eq 'OK') { $st = 'Warnung' } }
            }
            if ($null -ne $cpuTMax -and $cpuTMax -ge 95 -and $th.Status -ne 'thermisch') { Add-Finding INFO 'Lasttest' ('Die CPU erreichte unter Dauerlast {0:N0} °C.' -f $cpuTMax) }
            elseif ($null -eq $cpuTMax -and $tMax -and -not $tStatic -and $tMax -ge 95) { Add-Finding WARNUNG 'Lasttest' ('Die Thermalzone erreichte {0} °C unter Dauerlast.' -f $tMax); if ($st -eq 'OK') { $st = 'Warnung' } }
            $det = ('{0} Threads, {1:N0} Rechendurchläufe, {2} Rechenfehler, Ø {3:N0} MHz, Taktverlauf {4:+0.0;-0.0;0} %{5}{6}, Drosselung: {7}' -f $threads, $cpuTask.Count, $cpuErr, $mhz.Average, $(if ($null -ne $th.Abfall) { -$th.Abfall } else { 0 }),
                $(if ($null -ne $cpuTMax) { ', max {0:N0} °C' -f $cpuTMax } else { '' }), $(if ($null -ne $cpuWMax) { ', max {0:N0} W' -f $cpuWMax } else { '' }), $th.Status)
            Add-Line ('  Prozessor      : {0}, {1}' -f (& $dur 'CPU'), $det)
            $script:LoadParts.Add([pscustomobject]@{ Komponente = 'Prozessor'; Dauer = (& $dur 'CPU'); Ergebnis = $st; Details = $det }); & $setStatus $st
        }
        if ($ramTask) {
            $ramErr = $ramTask.Errors
            $st = $(if ($ramErr -gt 0) { 'Fehler' } else { 'OK' })
            if ($ramErr -gt 0) { Add-Finding KRITISCH 'Lasttest' ('{0} Bitfehler im RAM unter Dauerlast: EXPO/XMP deaktivieren und die Module einzeln prüfen (MemTest86).' -f $ramErr) }
            $det = ('{0} geprüft, {1} Bitfehler' -f (Format-Size $ramTask.Count), $ramErr)
            Add-Line ('  Arbeitsspeicher: {0}, {1}' -f (& $dur 'RAM'), $det)
            try { $rr = [string]$ramTask.Result; ($rr -split "`r?`n" | Where-Object { $_ -match 'erwartet' } | Select-Object -First 10) | ForEach-Object { Add-Line ('    ' + $_.Trim()) } } catch { }
            $script:LoadParts.Add([pscustomobject]@{ Komponente = 'Arbeitsspeicher'; Dauer = (& $dur 'RAM'); Ergebnis = $st; Details = $det }); & $setStatus $st
        }
        if ($gpuRuns.Count) {
            $tdrAll = @(Get-TdrEvents $t0)
            $gi = 0
            foreach ($g in $gpuRuns) {
                $res = ConvertTo-RenderResult $g.Run $g.Ad
                $script:GpuLoad.Add($res)
                $tdrMine = @(Select-TdrEvents $tdrAll $g.Ad $(if ($gi -eq 0) { $true } else { $false }))
                $st = Add-RenderFindings $res 'Lasttests' $tdrMine
                $drop = Get-FpsDrop $res.FpsVerlauf
                # Sensorwerte gehören zur Einheit gleichen Namens (Leitwert Gpu*, zweite Einheit IGpu*), sonst nach Reihenfolge
                $nm = ([string]$res.Name).Trim()
                $sens = $(if ($nm -and $nm -eq ([string]$idle.GpuName).Trim()) { 'Gpu' } elseif ($nm -and $nm -eq ([string]$idle.IGpuName).Trim()) { 'IGpu' } elseif ($gi -eq 0) { 'Gpu' } elseif ($gi -eq 1 -and $g.Ad.Art -eq 'iGPU') { 'IGpu' } else { '' })
                $tMx = $(switch ($sens) { 'Gpu' { $gpuTMax } 'IGpu' { $igTMax } default { $null } }); $wMx = $(switch ($sens) { 'Gpu' { $gpuWMax } 'IGpu' { $igWMax } default { $null } })
                $mMx = $(switch ($sens) { 'Gpu' { if ($gpuMhz.Count) { $gpuMhz[0].Average } } 'IGpu' { if ($igMhz.Count) { $igMhz[0].Average } } default { $null } })
                $limTxt = @($script:LoadLimitNotes | Where-Object { $_ -like ($res.Name + ' (*') }) | Select-Object -First 1
                if ($limTxt -and (Get-StatusRank $st) -lt 2) { $st = 'Warnung' }
                $ldCol = $(if ($sens) { $sens + 'Load' } else { '' })
                $fpsCol = $(switch ($gi) { 0 { 'Fps' } 1 { 'Fps2' } default { '' } })
                $ldV = @(if ($ldCol) { $loadS | Where-Object { $null -ne $_.$ldCol -and (-not $fpsCol -or $null -ne $_.$fpsCol) } })
                $ldAvg = $(if ($ldV.Count) { [math]::Round(($ldV | Measure-Object $ldCol -Average).Average) } else { $null })
                if ($null -ne $drop -and $drop -ge 15) {
                    Add-Finding INFO 'Lasttest' ('{0} ({1}): Die Bilder/s fielen unter Dauerlast um {2:N0} % (erste gegen letzte Minute). Hinweis auf thermische Drosselung oder eine Leistungsgrenze der Grafik.' -f $res.Name, $res.Bezeichnung, $drop)
                    if ($st -eq 'OK') { $st = 'Info' }
                }
                if ($res.Esc) { $st = $(if ($st -eq 'OK') { 'Info' } else { $st }) }
                $det = ('{0} ({1}), {2}, Ø {3:N0} Bilder/s (min {4:N0}, max {5:N0}), {6:N0} Bilder{7}{8}{9}{10}, Bildprüfung {11}{12}' -f $res.Name, $res.Bezeichnung, $res.Aufloesung, $res.Fps, $res.MinFps, $res.MaxFps, $res.Bilder,
                    $(if ($null -ne $drop) { ', Verlauf {0:+0.0;-0.0;0} %' -f (-$drop) } else { '' }), $(if ($null -ne $ldAvg) { ', Auslastung Ø {0} %' -f $ldAvg } else { '' }),
                    ($(if ($null -ne $mMx) { ', Takt Ø {0:N0} MHz' -f $mMx } else { '' }) + $(if ($null -ne $tMx) { ', max {0:N0} °C' -f $tMx } else { '' })), $(if ($null -ne $wMx) { ', max {0:N0} W' -f $wMx } else { '' }),
                    $(if ($res.Bildpruefungen) { '{0} von {1} abweichend' -f $res.Bildfehler, $res.Bildpruefungen } else { 'nicht erfolgt' }),
                    ($(if ($res.Treiberreset) { ', Treiber-Reset ' + $res.ResetGrund } elseif (-not $res.Ok -and $res.Fehler) { ', ' + $res.Fehler } elseif ($res.Esc) { ', mit Esc beendet' } else { '' }) + $(if ($limTxt) { ', Bildratengrenze aktiv' } else { '' })))
                Add-Line ('  Grafik         : {0}, {1}' -f (& $dur 'GPU'), $det)
                $script:LoadParts.Add([pscustomobject]@{ Komponente = ('Grafik ({0})' -f $res.Bezeichnung); Dauer = (& $dur 'GPU'); Ergebnis = $st; Details = $det }); & $setStatus $st
                $gi++
            }
        } elseif ($script:LoadGpuSkipped) {
            Add-Line ('  Grafik         : {0}' -f $script:LoadGpuSkipped)
            Add-Finding INFO 'Lasttest' ('Grafiklast entfällt: {0}.' -f $script:LoadGpuSkipped)
            $script:LoadParts.Add([pscustomobject]@{ Komponente = 'Grafik'; Dauer = '00:00:00'; Ergebnis = 'Info'; Details = $script:LoadGpuSkipped })
        }
        if ($diskTask) {
            $res = ''
            if ($diskHung -and -not $diskTask.IsCompleted) { $res = 'Abbruch: Datenträgertest reagiert nicht' }
            else { try { $res = [string]$diskTask.Result } catch { $res = $_.Exception.Message } }
            $dErr = [DiagDiskStress]::Errors; $ioErr = [DiagDiskStress]::IoErrors
            $dEv = @(foreach ($pv in 'disk', 'storahci', 'stornvme') { Get-Ev @{ LogName = 'System'; ProviderName = $pv; Level = 1, 2, 3; StartTime = $t0 } 200 })
            $st = 'OK'
            if ($diskHung) { Add-Finding WARNUNG 'Lasttest' ('Der Datenträgertest auf Laufwerk {0}: reagierte nach dem Ende 2 Minuten lang nicht (Lese- oder Schreibzugriff hängt). Laufwerk, Kabel und Controller prüfen, wichtige Daten sichern. Die Testdatei {1} entfernt die Rückstandskontrolle, sobald sie frei ist (spätestens beim nächsten Lauf).' -f $diskLetter, $diskPath); $st = 'Warnung' }
            if ($dErr -gt 0) { Add-Finding KRITISCH 'Lasttest' ('{0} Datenfehler beim Datenträgertest auf Laufwerk {1}: (zurückgelesene Daten weichen ab). Laufwerk, Kabel, Controller und Arbeitsspeicher prüfen, wichtige Daten sichern.' -f $dErr, $diskLetter); $st = 'Fehler' }
            if ($ioErr -gt 0) { Add-Finding WARNUNG 'Lasttest' ('{0} Ein-/Ausgabefehler beim Datenträgertest auf Laufwerk {1}: ({2}).' -f $ioErr, $diskLetter, [DiagDiskStress]::LastError); if ($st -eq 'OK') { $st = 'Warnung' } }
            if ($dEv.Count) { Add-Finding WARNUNG 'Lasttest' ('Während des Lasttests meldete Windows {0} Datenträger- oder Controllerereignisse (z. B. {1} {2}).{3}' -f $dEv.Count, $dEv[0].ProviderName, $dEv[0].Id, (Get-DiskRefText $dEv)); if ($st -eq 'OK') { $st = 'Warnung' } }
            if ($null -ne $diskTMax -and $diskTMax -ge 70) { Add-Finding WARNUNG 'Lasttest' ('Ein Datenträger erreichte unter Last {0:N0} °C: Kühlung des Laufwerks prüfen (NVMe drosseln ab etwa 70 °C).' -f $diskTMax); if ($st -eq 'OK') { $st = 'Warnung' } }
            $mbs = @($loadS | Where-Object { $null -ne $_.DiskMBs } | Measure-Object DiskMBs -Average -Minimum)
            $det = ('Laufwerk {0}:, {1:N0} MB gelesen, {2:N0} MB geschrieben, Ø {3:N0} MB/s, {4} Datenfehler, {5} E/A-Fehler, {6} Windows-Ereignisse{7}' -f $diskLetter, ([DiagDiskStress]::BytesRead / 1MB), ([DiagDiskStress]::BytesWritten / 1MB), $(if ($mbs.Count) { $mbs[0].Average } else { 0 }), $dErr, $ioErr, $dEv.Count, $(if ($null -ne $diskTMax) { ', max {0:N0} °C' -f $diskTMax } else { '' }))
            Add-Line ('  Datenträger    : {0}, {1}' -f (& $dur 'Disk'), $det)
            ($res -split "`r?`n" | Where-Object { $_ -match 'Block|Abbruch' } | Select-Object -First 10) | ForEach-Object { Add-Line ('    ' + $_.Trim()) }
            $script:LoadParts.Add([pscustomobject]@{ Komponente = 'Datenträger'; Dauer = (& $dur 'Disk'); Ergebnis = $st; Details = $det }); & $setStatus $st
        }
        if ($abort) {
            Add-Finding WARNUNG 'Lasttest' ('Lasttest nach {0}:{1:00} min abgebrochen: {2}. Kühlung prüfen, bevor der Test erneut läuft.' -f [int][math]::Floor($script:LoadAbort.T / 60), [int]($script:LoadAbort.T % 60), $abort.Grund)
            & $setStatus 'Warnung'
        }
        if ($wheaHard.Count) { Add-Finding KRITISCH 'Lasttest' ('{0} schwere WHEA-Hardwarefehler während des Lasttests.' -f $wheaHard.Count); & $setStatus 'Fehler' }
        elseif ($whea.Count) { Add-Finding WARNUNG 'Lasttest' ('{0} korrigierte WHEA-Hardwarefehler während des Lasttests (CPU, RAM oder PCIe an der Grenze).' -f $whea.Count); & $setStatus 'Warnung' }

        $script:LoadSeries = @($samples)
        try { $samples | Select-Object T, MHz, Last, Leistung, MaxFreq, Temp, CpuTemp, CpuTempQ, @{n = 'CpuMHzMax'; e = { $_.CpuMHz } }, CpuW, GpuTemp, GpuMHz, GpuW, GpuLoad, IGpuTemp, IGpuMHz, IGpuW, IGpuLoad, Fps, Fps2, Fan, DiskTemp, DiskMBs, Cpu | Export-Csv -Path (Join-Path $RawDir 'Lasttest-Verlauf.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8 } catch { }
        $script:LoadSummary = ('Dauer {0:hh\:mm\:ss}{1}, {2}, {3} WHEA-Ereignisse{4}' -f $real, $stopTxt, (($script:LoadParts | ForEach-Object { '{0} {1}' -f $_.Komponente, $_.Ergebnis }) -join ', '), $whea.Count,
            $(if ($null -ne $cpuTMax) { ', CPU max {0:N0} °C' -f $cpuTMax } else { '' }) + $(if ($script:LoadThrottle) { ', Drosselung: ' + $script:LoadThrottle.Status } else { '' }) +
            ((@($script:GpuLoad | Where-Object { $_.Ok }) | ForEach-Object { ', {0} Ø {1:N0} Bilder/s' -f $_.Bezeichnung, $_.Fps }) -join ''))
        $script:SensorDb['Last'] = [ordered]@{
            CpuTempLeerlauf = $idle.CpuTemp; CpuTempMax = $cpuTMax; TjMax = $tjMax; CpuWMax = $cpuWMax; CpuMHzMax = $(if ($coreAll.Count -and $coreAll[0].Count) { [math]::Round($coreAll[0].Maximum) } else { $null })
            Gpu = [string]$idle.GpuName; GpuTempMax = $gpuTMax; GpuWMax = $gpuWMax; IGpu = [string]$idle.IGpuName; IGpuTempMax = $igTMax; IGpuWMax = $igWMax
            LuefterMax = $fanMax; DatentraegerTempMax = $diskTMax; Unplausibel = @($script:LoadBadSeen.Values | ForEach-Object { '{0} {1} ({2:N0})' -f $_.Geraet, $_.Name, $_.Max })
            Rendertest = @($script:GpuLoad | ForEach-Object { [ordered]@{ Grafik = $_.Name; Art = $_.Art; Aufloesung = $_.Aufloesung; Fps = $_.Fps; MinFps = $_.MinFps; Bildfehler = $_.Bildfehler; Treiberreset = $_.Treiberreset; Fehler = $_.Fehler } })
            Drosselung = $(if ($script:LoadThrottle) { $script:LoadThrottle.Status } else { '' }); TaktAbfall = $(if ($script:LoadThrottle) { $script:LoadThrottle.Abfall } else { $null })
            Abbruch = $(if ($abort) { $abort.Grund } else { '' }); Quelle = (Get-SensorSourceText)
            Unterbrechungen = (@($pauseRows | ForEach-Object { '{0}: {1}' -f $_.Kurz, $_.P.Text }) -join '; ')
        }
        foreach ($p in $script:LoadParts) { Add-TestResult ('Lasttest {0} ({1})' -f $p.Komponente, $p.Dauer) $p.Ergebnis $p.Details }
    }
}
