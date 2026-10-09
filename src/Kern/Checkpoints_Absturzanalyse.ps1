# ---------- Checkpoints: Protokoll, das auch einen harten Absturz übersteht ----------
$script:CpLog     = $(if ($script:CpDir) { Join-Path $script:CpDir 'checkpoint.log' } else { '' })
$script:CpFlag    = $(if ($script:CpDir) { Join-Path $script:CpDir 'laufend.json' } else { '' })
$script:CpStream  = $null
$script:CpLastHb  = [datetime]::MinValue
$script:CpCurrent = ''

function Write-Durable([string]$Path, [string]$Text) {
    $enc = New-Object Text.UTF8Encoding($true)
    $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read, 65536, [IO.FileOptions]::WriteThrough)
    try { $pre = $enc.GetPreamble(); $fs.Write($pre, 0, $pre.Length); $b = $enc.GetBytes($Text); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
    finally { $fs.Close() }
}

# Ab v2.6 gedrosselt (Stick schonen): Zeilen sammeln sich im Speicher und gehen bei jedem Schrittwechsel (BEGINN, START,
# OK, FEHLER, ABBRUCH, ENDE ...) sofort auf den Datenträger, Pulse höchstens alle 10 Sekunden.
$script:CpBuffer    = New-Object System.Text.StringBuilder
$script:CpLastFlush = [datetime]::MinValue
$script:CpWrites    = 0
function Write-Checkpoint([string]$Kind, [string]$Text) {
    if (-not $script:CpStream) { return }
    $now = Get-Date
    $line = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:yyyy-MM-dd HH:mm:ss} | {1,-7} | {2}', $now, $Kind, $Text)
    [void]$script:CpBuffer.Append($line).Append("`r`n")
    if ($Kind -notin 'PULS', 'PARALL', 'INFO' -or ($now - $script:CpLastFlush).TotalSeconds -ge 10) { Flush-Checkpoint }
}

function Flush-Checkpoint {
    if (-not $script:CpStream -or $script:CpBuffer.Length -eq 0) { return }
    $b = [Text.Encoding]::UTF8.GetBytes($script:CpBuffer.ToString())
    [void]$script:CpBuffer.Clear()
    $script:CpLastFlush = Get-Date
    try { $script:CpStream.Write($b, 0, $b.Length); $script:CpStream.Flush($true); $script:CpWrites++ } catch { }
}

function Write-Heartbeat([string]$Text) {
    if (-not $script:CpStream) { return }
    $now = Get-Date
    if (($now - $script:CpLastHb).TotalSeconds -lt 10) { return }
    $script:CpLastHb = $now
    $extra = ''
    if ($TypesLoaded) { try { $extra = ' | RAM belegt {0} %' -f [DiagSys]::MemoryLoad() } catch { } }
    Write-Checkpoint 'PULS' ('{0} | {1}{2}' -f $script:CpCurrent, $Text, $extra)
}

function Open-Checkpoint {
    try {
        New-Item -ItemType Directory -Path $script:CpDir -Force | Out-Null
        $script:CpStream = New-Object IO.FileStream($script:CpLog, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read, 4096, [IO.FileOptions]::WriteThrough)
        $modus = Get-ModeLabel
        $flagObj = [ordered]@{ Start = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture); Version = $ScriptVersion; Modus = $modus; OutputDir = $OutputDir; Computer = $env:COMPUTERNAME }
        Write-Durable $script:CpFlag ($flagObj | ConvertTo-Json)
        Write-Checkpoint 'BEGINN' ('Leos Minibench v{0}, Modus {1}, Ausgabe {2}' -f $ScriptVersion, $modus, $OutputDir)
        $os = Get-CimCached Win32_OperatingSystem | Select-Object -First 1
        Write-Checkpoint 'SYSTEM' ('Letzter Systemstart {0}, RAM frei {1:N1} GB' -f $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture), ($os.FreePhysicalMemory / 1MB))
    } catch { $script:CpStream = $null }
}

function Close-Checkpoint([switch]$RemoveFlag) {
    try { Flush-Checkpoint } catch { }
    try { if ($script:CpStream) { $script:CpStream.Close() } } catch { }
    $script:CpStream = $null
    if ($RemoveFlag) { Remove-Item $script:CpFlag -Force -ErrorAction SilentlyContinue }
}

# Zwischenstand für die Absturzanalyse. Ab v2.6 höchstens einmal je Minute (Stick schonen), vor Lasttest, Benchmark,
# CPU- und RAM-Test sowie Reparaturen sofort (-Force).
$script:PartialLast = [datetime]::MinValue
$script:PartialWrites = 0
function Save-Partial([switch]$Force) {
    if (-not $Force -and ((Get-Date) - $script:PartialLast).TotalSeconds -lt 60) { return }
    if (-not $OutputDir) { return }
    $script:PartialLast = Get-Date
    $script:PartialWrites++
    try {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine(('ZWISCHENSTAND, Lauf noch nicht abgeschlossen ({0:dd.MM.yyyy HH:mm:ss}, zuletzt: {1})' -f (Get-Date), $script:CpCurrent))
        foreach ($f in $script:Findings) { [void]$sb.AppendLine(('  [{0,-8}] {1,-14} {2}' -f $f.Stufe, $f.Bereich, $f.Befund)) }
        [void]$sb.AppendLine()
        [void]$sb.Append($script:Report.ToString())
        Write-Durable (Join-Path $OutputDir 'Diagnosebericht_teilweise.txt') $sb.ToString()
    } catch { }
}

function Get-BugcheckName([int64]$Code) {
    $m = @{
        0x0A  = 'IRQL_NOT_LESS_OR_EQUAL (Treiber oder RAM)'
        0x19  = 'BAD_POOL_HEADER (Treiber oder RAM)'
        0x4E  = 'PFN_LIST_CORRUPT (RAM oder Treiber)'
        0x9C  = 'MACHINE_CHECK_EXCEPTION (Hardwarefehler)'
        0x109 = 'CRITICAL_STRUCTURE_CORRUPTION (Treiber oder RAM)'
        0x12B = 'FAULTY_HARDWARE_CORRUPTED_PAGE (RAM)'
        0x1A  = 'MEMORY_MANAGEMENT (häufig RAM, EXPO/XMP oder Übertaktung)'
        0x1E  = 'KMODE_EXCEPTION_NOT_HANDLED (Treiber)'
        0x3B  = 'SYSTEM_SERVICE_EXCEPTION (Treiber)'
        0x50  = 'PAGE_FAULT_IN_NONPAGED_AREA (RAM, Treiber oder Datenträger)'
        0x7A  = 'KERNEL_DATA_INPAGE_ERROR (Datenträger, Kabel oder Controller)'
        0x7E  = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED (Treiber)'
        0x9F  = 'DRIVER_POWER_STATE_FAILURE (Treiber, Energiesparmodus)'
        0xA0  = 'INTERNAL_POWER_ERROR'
        0xC2  = 'BAD_POOL_CALLER (Treiber)'
        0xD1  = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL (Treiber)'
        0xEF  = 'CRITICAL_PROCESS_DIED'
        0xF4  = 'CRITICAL_OBJECT_TERMINATION (oft Datenträger)'
        0x101 = 'CLOCK_WATCHDOG_TIMEOUT (CPU reagiert nicht: Übertaktung, Spannung, CPU)'
        0x116 = 'VIDEO_TDR_FAILURE (Grafikkarte oder Grafiktreiber)'
        0x117 = 'VIDEO_TDR_TIMEOUT_DETECTED (Grafikkarte oder Grafiktreiber)'
        0x119 = 'VIDEO_SCHEDULER_INTERNAL_ERROR (Grafik)'
        0x124 = 'WHEA_UNCORRECTABLE_ERROR (Hardwarefehler: CPU, RAM, Spannung, Übertaktung)'
        0x133 = 'DPC_WATCHDOG_VIOLATION (Treiber oder SSD-Firmware)'
        0x139 = 'KERNEL_SECURITY_CHECK_FAILURE (Treiber oder RAM)'
        0x13A = 'KERNEL_MODE_HEAP_CORRUPTION (Treiber)'
        0x154 = 'UNEXPECTED_STORE_EXCEPTION (Datenträger)'
    }
    # Stoppcodes ab 0x80000000 (z. B. 0xC000021A, 0xDEADDEAD) passen nicht in [int]: dann gibt es keinen Eintrag
    $c = [int64]$Code -band 0xFFFFFFFFL
    if ($c -le [int]::MaxValue -and $m.ContainsKey([int]$c)) { return $m[[int]$c] }
    return '(Stoppcode im Internet nachschlagen)'
}

function Test-MemoryBugcheck([int64]$Code) { return (([int64]$Code -band 0xFFFFFFFFL) -in 0x0A, 0x19, 0x1A, 0x4E, 0x50, 0x109, 0x12B, 0x139) }


function Get-TestHint([string]$Step) {
    switch -Regex ($Step) {
        '^Lasttest'             { return 'Absturz unter Dauerlast: Netzteil, Kühlung, Übertaktung, Undervolting und EXPO/XMP prüfen.' }
        'Benchmark: Datentr'    { return 'Absturz beim Laufwerks-Benchmark: Laufwerk, Kabel, Controllertreiber und SSD-Firmware prüfen.' }
        'Benchmark'             { return 'Absturz im Benchmark (kurze Volllast): Netzteil, Übertaktung und Treiber prüfen.' }
        'CPU'                   { return 'Absturz unter CPU-Volllast: Kühlung und Lüfter, CPU-Übertaktung/PBO/Curve Optimizer, BIOS-Version und Netzteil prüfen.' }
        'Test: Arbeitsspeicher' { return 'Absturz im RAM-Test: EXPO/XMP testweise deaktivieren und die Module einzeln mit MemTest86 prüfen.' }
        'WinSAT'                { return 'Absturz bei der Leistungsbewertung (CPU, RAM, Grafik und Datenträger unter Last): Netzteil, Grafikkarte und Grafiktreiber prüfen.' }
        'Dateisystem|SMART|Datenträger' { return 'Absturz bei Datenträgerzugriffen: Laufwerk, Kabel, Controllertreiber und SSD-Firmware prüfen.' }
        'Defender'              { return 'Absturz beim Virenscan (hohe Datenträger- und CPU-Last): Datenträger und Treiber prüfen.' }
        'Test: Netzwerk'        { return 'Absturz beim Netzwerktest: Netzwerk- oder WLAN-Treiber aktualisieren.' }
        'Energie'               { return 'Absturz bei Energieanalyse oder DxDiag: Treiberproblem wahrscheinlich, besonders Grafik- und Chipsatztreiber.' }
        '^Reparatur'            { return 'Absturz während einer Reparatur: Datenträger und Arbeitsspeicher prüfen, Reparatur danach einzeln wiederholen.' }
        default                 { return 'Absturz beim Auslesen von Systeminformationen: meist Treiberproblem.' }
    }
}

# Welcher Abschnitt soll nach einem Absturz beim nächsten Lauf ausgelassen werden
function Get-SkipSwitch([string]$Step) {
    switch -Regex ($Step) {
        # ab v2.8 vor den übrigen Mustern: Kategorietitel der Optimierung können Wörter wie Defender enthalten
        '^Optimierung: (.+)$'             { $t = $Matches[1]; foreach ($k in @(Get-OptCategories)) { if ($k.Titel -eq $t) { return ('Opt8:' + $k.Key) } }; return $null }
        '^Lasttest'                       { return 'Last:alle' }
        'Benchmark: Prozessor'            { return 'Bench:CPU' }
        'Benchmark: Arbeitsspeicher'      { return 'Bench:RAM' }
        'Benchmark: Grafik'               { return 'Bench:GPU' }
        'Benchmark: Datentr'              { return 'Bench:Disk' }
        'Benchmark: WinSAT'               { return 'Bench:WinSAT' }
        'Arbeitsspeicher \(Mustertest\)'  { return 'Opt:RamTest' }
        'Dateisystem und Systemdateien'   { return 'Opt:Integritaet' }
        'Defender'                        { return 'Opt:Defender' }
        'Test: Netzwerk'                  { return 'Opt:Netzwerk' }
        'SMART-Langtest'                  { return 'Opt:SmartLang' }
        '^Energie'                        { return 'Opt:Energieanalyse' }
        '^Reparatur: (.+)$'               { $t = $Matches[1]; foreach ($k in $script:RepTitles.Keys) { if ($script:RepTitles[$k] -eq $t) { return ('Rep:' + $k) } }; return $null }
        default                           { return $null }
    }
}

function Invoke-CrashAnalysis {
    if (-not (Test-Path $script:CpFlag)) {
        if ($AnalyzeLastRun) {
            Add-Section 'Absturzanalyse des letzten Laufs'
            Add-Line '  Kein unterbrochener Lauf gefunden. Der letzte Lauf wurde regulär beendet oder es gab noch keinen.'
            Write-Host '  Kein unterbrochener Lauf gefunden.' -ForegroundColor Green
        }
        return
    }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $toTime = {
        param($l)
        $t = [datetime]::MinValue
        if ($l -and $l.Length -ge 19 -and [datetime]::TryParseExact($l.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', $inv, [Globalization.DateTimeStyles]::None, [ref]$t)) { $t } else { $null }
    }
    $flag = $null
    try { $flag = Get-Content $script:CpFlag -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    $lines = @()
    if (Test-Path $script:CpLog) { $lines = @(Get-Content $script:CpLog -Encoding UTF8 | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2} ' }) }
    $lastLine  = $lines | Select-Object -Last 1
    $lastTime  = & $toTime $lastLine
    if (-not $lastTime -and $flag) { $lastTime = & $toTime $flag.Start }
    if (-not $lastTime) { $lastTime = (Get-Date).AddDays(-1) }
    $startLine = $lines | Where-Object { $_ -match '\|\s*START\s*\|' } | Select-Object -Last 1
    $step      = $(if ($startLine) { (($startLine -split '\|', 3)[2]).Trim() } else { 'unbekannt (vor dem ersten Schritt)' })
    $stepName  = $step -replace '^\[\d+/\d+\]\s*', ''
    $pulse     = $lines | Where-Object { $_ -match '\|\s*PULS\s*\|' } | Select-Object -Last 1
    $smartBg   = ($lines -match 'OK\s*\| Test: SMART-Langtest wird gestartet') -and -not ($lines -match 'OK\s*\| Test: SMART-Langtest Ergebnis')

    $bootEv = Get-Ev @{ LogName = 'System'; ProviderName = 'EventLog'; Id = 6005; StartTime = $lastTime } 50 | Sort-Object TimeCreated | Select-Object -First 1
    $rebooted = [bool]$bootEv
    $boot = $(if ($bootEv) { $bootEv.TimeCreated } else { (Get-CimCached Win32_OperatingSystem | Select-Object -First 1).LastBootUpTime })
    $from = $lastTime.AddMinutes(-2)
    $to   = $(if ($rebooted) { $boot.AddMinutes(20) } else { Get-Date })

    $kp      = Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $from; EndTime = $to } 5
    $bsod    = Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $from; EndTime = $to.AddMinutes(30) } 5
    $whea    = Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $from; EndTime = $to } 20
    $e6008   = Get-Ev @{ LogName = 'System'; ProviderName = 'EventLog'; Id = 6008; StartTime = $from; EndTime = $to } 3
    $planned = Get-Ev @{ LogName = 'System'; ProviderName = 'User32'; Id = 1074; StartTime = $from; EndTime = $boot } 3
    $dumpErr = Get-Ev @{ LogName = 'System'; ProviderName = 'volmgr'; Id = 161; StartTime = $from; EndTime = $to } 3
    $psErr   = @(Get-Ev @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $from } 20 | Where-Object { "$($_.Properties[0].Value)" -match 'powershell' })
    $dumps   = @(Get-ChildItem "$env:windir\Minidump\*.dmp", "$env:windir\MEMORY.DMP" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $from })

    $code = $null
    if ($kp.Count) { try { $code = [int64]$kp[0].Properties[0].Value } catch { } }
    if (-not $code -and $bsod.Count -and $bsod[0].Message -match '0x([0-9a-fA-F]{8})') { $code = [Convert]::ToInt64($Matches[1], 16) }

    $level = 'KRITISCH'
    if (-not $rebooted) {
        if ($psErr.Count) { $cause = 'PowerShell selbst ist abgestürzt, Windows lief weiter (kein Systemabsturz).'; $level = 'WARNUNG' }
        else { $cause = 'Seitdem gab es keinen Neustart. Der Lauf wurde vermutlich von Hand beendet (Fenster geschlossen oder Strg+C).'; $level = 'INFO' }
    } elseif ($code) {
        $cause = 'Bluescreen mit Stoppcode 0x{0:X} {1}.' -f $code, (Get-BugcheckName $code)
    } elseif ($kp.Count) {
        $cause = 'Harter Absturz ohne Bluescreen (Kernel-Power 41, Stoppcode 0): Der PC ist schlagartig ausgegangen oder neu gestartet. Typisch für Netzteil, Überhitzung, instabile Übertaktung oder Spannung, Stromausfall oder Reset-Taste.'
    } elseif ($planned.Count) {
        $cause = 'Der PC wurde regulär heruntergefahren oder neu gestartet: ' + (Get-ShortText $planned[0].Message 160); $level = 'INFO'
    } elseif ($e6008.Count) {
        $cause = 'Unerwartetes Herunterfahren ohne weitere Details (EventLog 6008).'
    } else {
        $cause = 'Seitdem wurde neu gestartet, Windows hat aber keine Ursache protokolliert.'; $level = 'WARNUNG'
    }
    $hint = Get-TestHint $stepName

    Add-Section 'Absturzanalyse des letzten Laufs'
    Add-Line ('  Ergebnis               : {0}' -f $cause)
    if ($level -ne 'INFO') { Add-Line ('  Einordnung             : {0}' -f $hint) }
    if ($smartBg -and $level -ne 'INFO') { Add-Line '  Zusätzlich aktiv       : SMART-Langtest im Hintergrund (Laufwerksfirmware)' }
    Add-Line ('  Letzter Lauf gestartet : {0} (Version {1}, Modus {2})' -f $flag.Start, $flag.Version, $flag.Modus)
    Add-Line ('  Letzter Checkpoint     : {0:dd.MM.yyyy HH:mm:ss}' -f $lastTime)
    Add-Line ('  Laufender Schritt      : {0}' -f $step)
    if ($pulse) { Add-Line ('  Letzter Messwert       : {0}' -f (($pulse -split '\|', 3)[2]).Trim()) }
    Add-Line ('  Neustart danach        : {0}' -f $(if ($rebooted) { 'ja, Systemstart {0:dd.MM.yyyy HH:mm:ss}' -f $boot } else { 'nein' }))
    if ($whea.Count) {
        Add-Line ('  WHEA-Hardwarefehler    : {0} Ereignis(se) im Absturzzeitraum' -f $whea.Count)
        Add-Finding KRITISCH 'Absturz' ('WHEA meldet {0} Hardwarefehler im Absturzzeitraum (CPU, RAM oder PCIe).' -f $whea.Count)
    }
    if ($dumps.Count) { Add-Line ('  Absturzabbild          : {0}' -f (($dumps | ForEach-Object { $_.FullName }) -join ', ')) }
    elseif ($rebooted -and $level -eq 'KRITISCH') { Add-Line '  Absturzabbild          : keins erstellt' }
    if ($dumpErr.Count) { Add-Line ('  Abbild-Erstellung      : fehlgeschlagen ({0})' -f (Get-ShortText $dumpErr[0].Message 120)) }

    $evAll = @($kp) + @($bsod) + @($whea) + @($e6008) + @($planned) + @($dumpErr) + @($psErr) | Where-Object { $_ } | Sort-Object TimeCreated
    if ($evAll.Count) {
        Add-Sub 'Ereignisse im Absturzzeitraum'
        $evAll | Select-Object TimeCreated, Id, ProviderName, @{n = 'Meldung'; e = { Get-ShortText $_.Message 170 } } | Out-Report
    }
    Add-Sub 'Letzte Checkpoints vor dem Abbruch'
    ($lines | Select-Object -Last 15) | Out-Report

    Add-Finding $level 'Absturz' ('Letzter Lauf endete während "{0}" um {1:dd.MM. HH:mm:ss}: {2}' -f $stepName, $lastTime, $cause)

    Write-Host ''
    $col = @{ KRITISCH = 'Red'; WARNUNG = 'Yellow'; INFO = 'Cyan' }[$level]
    Write-Host ('  ' + ('!' * 76)) -ForegroundColor $col
    Write-Host '   DER LETZTE DIAGNOSELAUF WURDE NICHT BEENDET' -ForegroundColor $col
    Write-Host ('   Schritt : {0}' -f $step) -ForegroundColor $col
    Write-Host ('   Zeit    : {0:dd.MM.yyyy HH:mm:ss}' -f $lastTime) -ForegroundColor $col
    Write-Host ('   Ursache : {0}' -f $cause) -ForegroundColor $col
    if ($level -ne 'INFO') { Write-Host ('   Hinweis : {0}' -f $hint) -ForegroundColor $col }
    Write-Host ('  ' + ('!' * 76)) -ForegroundColor $col
    Write-Host ''

    # Belege sichern
    try {
        $arch = Join-Path $script:CpDir ('checkpoint_{0:yyyyMMdd_HHmmss}_unterbrochen.log' -f $lastTime)
        if (Test-Path $script:CpLog) { Move-Item $script:CpLog $arch -Force; Copy-Item $arch (Join-Path $RawDir 'Checkpoint_unterbrochener_Lauf.log') -Force }
        if ($flag.OutputDir) {
            $part = Join-Path $flag.OutputDir 'Diagnosebericht_teilweise.txt'
            if (Test-Path $part) { Copy-Item $part (Join-Path $RawDir 'Diagnosebericht_unterbrochener_Lauf.txt') -Force; Add-Line ('  Teilbericht des abgebrochenen Laufs: {0}' -f $part) }
        }
    } catch { }
    Remove-Item $script:CpFlag -Force -ErrorAction SilentlyContinue

    # Absturzursache nicht erneut auslösen
    if ($rebooted -and $level -ne 'INFO' -and -not $AnalyzeLastRun) {
        $sk = Get-SkipSwitch $stepName
        if ($sk -and (Test-StepEnabled $sk)) {
            # Ist der Abschnitt das Einzige, was dieser Lauf tun soll, läuft er trotzdem: sonst entstünde ein leerer Bericht
            if ((Get-EnabledStepCount) -le 1) {
                Add-Line ('  Nicht übersprungen: {0} ist der einzige gewählte Schritt dieses Laufs.' -f $stepName)
                Add-Finding INFO 'Absturz' ('Der letzte Lauf ist bei "{0}" abgestürzt. Der Abschnitt läuft trotzdem, weil er der einzige gewählte ist; stürzt der PC erneut ab, Kühlung, Netzteil und Stabilität prüfen.' -f $stepName)
            } else {
                Disable-Step $sk
                $script:SkippedByCrash = $stepName
                Add-Line ('  Beim aktuellen Lauf übersprungen: {0}' -f $stepName)
                Add-Finding INFO 'Absturz' ('Der Abschnitt "{0}" wird in diesem Lauf ausgelassen, weil der letzte Lauf dabei abgestürzt ist.' -f $stepName)
            }
        }
    }
}

function Get-BugcheckRecommendation([int64]$Code) {
    $c = [int64]$Code -band 0xFFFFFFFFL
    switch ($c) {
        0x133 { return 'DPC Watchdog: SSD-Firmware aktualisieren, SATA/NVMe-Treiber prüfen, Antivirenprogramm testen.' }
        0x3B  { return 'System Service Exception: Grafik- und Netzwerktreiber aktualisieren, Systemdateien per SFC reparieren.' }
        0x116 { return 'Video TDR: Grafiktreiber sauber per DDU neu installieren, Grafikkarten-Takt und Temperatur prüfen.' }
        0x117 { return 'Video TDR Timeout: Grafiktreiber aktualisieren, PCIe-Steckplatz und Stromversorgung der GPU prüfen.' }
        0xD1  { return 'Driver IRQL: Zuletzt installierte Treiber prüfen, Netzwerktreiber aktualisieren, RAM per Test prüfen.' }
        0x0A  { return 'IRQL not less or equal: RAM mit Diagnosetest prüfen, Übertaktung/XMP/EXPO testweise deaktivieren.' }
        0x1A  { return 'Memory Management: RAM-Module einzeln mit MemTest86 prüfen, BIOS aktualisieren, XMP/EXPO anpassen.' }
        0x50  { return 'Page Fault: RAM und Dateisystem (chkdsk) prüfen, Virenscanner und Filtertreiber aktualisieren.' }
        0x7A  { return 'Kernel Data Inpage: Datenträgerzustand (SMART), SATA-/NVMe-Kabel und Dateisystem prüfen.' }
        0x7E  { return 'System Thread Exception: Abstürzenden Treiber anhand des Minidump-Treiberfelds ermitteln und aktualisieren.' }
        0x9F  { return 'Driver Power State: Energieverwaltungs- und Chipsatztreiber aktualisieren, Schnellstart testweise abschalten.' }
        0x101 { return 'Clock Watchdog Timeout: CPU-Übertaktung, PBO und Spannungen im BIOS zurücksetzen, BIOS-Update durchführen.' }
        0x124 { return 'WHEA Uncorrectable: Schwerer Hardwarefehler, CPU-Kühlung, RAM und Netzteilspannungen prüfen.' }
        0x139 { return 'Security Check Failure: Antiviren-Treiber oder beschädigten Treiber aktualisieren, RAM-Test ausführen.' }
        0x154 { return 'Unexpected Store Exception: SSD-Zustand (SMART) und Dateisystem prüfen, SSD-Firmware aktualisieren.' }
        default { return 'Stoppcode analysieren, Treiber und Windows auf aktuellen Stand bringen.' }
    }
}

function Read-MinidumpFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $fi = New-Object System.IO.FileInfo($Path)
        $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.BinaryReader($stream)
        try {
            if ($stream.Length -lt 32) { return $null }
            $sig = $reader.ReadUInt32()
            $code = 0L
            $p1 = 0L; $p2 = 0L; $p3 = 0L; $p4 = 0L
            $timestamp = $fi.LastWriteTime

            # Format 1: Standard Minidump (MDMP = 0x504D444D)
            if ($sig -eq 0x504D444D) {
                $ver = $reader.ReadUInt32()
                $streamCount = $reader.ReadUInt32()
                $streamDirRva = $reader.ReadUInt32()
                $checksum = $reader.ReadUInt32()
                $unixTime = $reader.ReadUInt32()
                if ($unixTime -gt 0) {
                    try {
                        $timestamp = (New-Object DateTime(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).AddSeconds($unixTime).ToLocalTime()
                    } catch { }
                }

                if ($streamDirRva -gt 0 -and $streamCount -gt 0 -and $streamDirRva -lt $stream.Length) {
                    $stream.Position = $streamDirRva
                    for ($i = 0; $i -lt $streamCount -and ($stream.Position + 12) -le $stream.Length; $i++) {
                        $sType = $reader.ReadUInt32()
                        $dSize = $reader.ReadUInt32()
                        $rva = $reader.ReadUInt32()
                        if ($sType -eq 6) { # MINIDUMP_EXCEPTION_STREAM
                            if ($rva -gt 0 -and ($rva + 32) -le $stream.Length) {
                                $savePos = $stream.Position
                                $stream.Position = $rva
                                $threadId = $reader.ReadUInt32()
                                $align = $reader.ReadUInt32()
                                $code = [int64]$reader.ReadUInt32()
                                $flags = $reader.ReadUInt32()
                                $exRec = $reader.ReadUInt64()
                                $exAddr = $reader.ReadUInt64()
                                $paramCount = $reader.ReadUInt32()
                                $unused = $reader.ReadUInt32()
                                if ($paramCount -ge 1 -and ($stream.Position + 8) -le $stream.Length) { $p1 = $reader.ReadUInt64() }
                                if ($paramCount -ge 2 -and ($stream.Position + 8) -le $stream.Length) { $p2 = $reader.ReadUInt64() }
                                if ($paramCount -ge 3 -and ($stream.Position + 8) -le $stream.Length) { $p3 = $reader.ReadUInt64() }
                                if ($paramCount -ge 4 -and ($stream.Position + 8) -le $stream.Length) { $p4 = $reader.ReadUInt64() }
                                $stream.Position = $savePos
                            }
                            break
                        }
                    }
                }
            }
            # Format 2: Kernel Dump (PAGE / DU64 = 0x45474150)
            elseif ($sig -eq 0x45474150) {
                $valid = $reader.ReadUInt32()
                if ($valid -eq 0x34365544) { # DU64
                    if ($stream.Length -ge 0x60) {
                        $stream.Position = 0x38
                        $code = [int64]$reader.ReadUInt32()
                        $stream.Position = 0x40
                        $p1 = $reader.ReadUInt64()
                        $p2 = $reader.ReadUInt64()
                        $p3 = $reader.ReadUInt64()
                        $p4 = $reader.ReadUInt64()
                    }
                } elseif ($valid -eq 0x504D5544) { # DUMP
                    if ($stream.Length -ge 0x38) {
                        $stream.Position = 0x24
                        $code = [int64]$reader.ReadUInt32()
                        $stream.Position = 0x28
                        $p1 = [int64]$reader.ReadUInt32()
                        $p2 = [int64]$reader.ReadUInt32()
                        $p3 = [int64]$reader.ReadUInt32()
                        $p4 = [int64]$reader.ReadUInt32()
                    }
                }
            }

            if ($code -ne 0) {
                $bugHex = ('0x{0:X}' -f $code)
                return [pscustomobject]@{
                    Datei        = $fi.Name
                    Pfad         = $fi.FullName
                    Datum        = $timestamp
                    Zeit         = $timestamp
                    Groesse      = $fi.Length
                    Bugcheck     = $bugHex
                    BugcheckCode = $bugHex
                    BugcheckInt  = $code
                    Name         = (Get-BugcheckName $code)
                    Parameter1   = ('0x{0:X}' -f $p1)
                    Parameter2   = ('0x{0:X}' -f $p2)
                    Parameter3   = ('0x{0:X}' -f $p3)
                    Parameter4   = ('0x{0:X}' -f $p4)
                    Empfehlung   = (Get-BugcheckRecommendation $code)
                    AlterTage    = [math]::Round(((Get-Date) - $timestamp).TotalDays, 1)
                }
            }
            return $null
        }
        finally {
            $reader.Close()
            $stream.Close()
        }
    }
    catch {
        return $null
    }
}

function Read-Minidumps {
    param([string]$Path = '')
    $dumps = New-Object System.Collections.ArrayList
    $files = @()
    if ($Path) {
        if (Test-Path -LiteralPath $Path) {
            if ((Get-Item -LiteralPath $Path) -is [System.IO.DirectoryInfo]) {
                $files = @(Get-ChildItem -LiteralPath $Path -Filter '*.dmp' -ErrorAction SilentlyContinue)
            } else {
                $files = @(Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue)
            }
        }
    } else {
        $sysRoot = $(if ($env:SystemRoot) { $env:SystemRoot } else { 'C:\Windows' })
        $dirs = @('C:\Windows\Minidump', (Join-Path $sysRoot 'Minidump')) | Select-Object -Unique
        foreach ($d in $dirs) {
            if (Test-Path -LiteralPath $d) {
                $files += @(Get-ChildItem -LiteralPath $d -Filter '*.dmp' -ErrorAction SilentlyContinue)
            }
        }
        $memDmp = Join-Path $sysRoot 'MEMORY.DMP'
        if (Test-Path -LiteralPath $memDmp) {
            $files += @(Get-Item -LiteralPath $memDmp -ErrorAction SilentlyContinue)
        }
    }
    foreach ($f in $files) {
        $res = Read-MinidumpFile $f.FullName
        if ($res) { [void]$dumps.Add($res) }
    }
    return @($dumps | Sort-Object Datum -Descending)
}

#endregion

