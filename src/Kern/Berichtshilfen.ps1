function Add-Line([string]$Text = '') { [void]$script:Report.AppendLine($Text) }

function Add-Section([string]$Title, [string]$Prefix = '') {
    Add-Line; Add-Line ('=' * 100); Add-Line ('  ' + $Title.ToUpper()); Add-Line ('=' * 100)
    Write-Host ''
    Write-Host ('[{0}] {1}>> {2}' -f (Get-Date -Format 'HH:mm:ss'), $Prefix, $Title) -ForegroundColor Cyan
}

function Add-Sub([string]$Title) { Add-Line; Add-Line (('--- {0} ' -f $Title).PadRight(100, '-')) }

function Out-Report {
    param([Parameter(ValueFromPipeline = $true)]$InputObject, [switch]$List)
    begin   { $buf = New-Object System.Collections.ArrayList }
    process { if ($null -ne $InputObject) { [void]$buf.Add($InputObject) } }
    end {
        if ($buf.Count -eq 0) { Add-Line '  (keine Einträge)'; return }
        if ($buf[0] -is [string]) { Add-Line (($buf | ForEach-Object { '  ' + $_ }) -join "`r`n"); return }
        if ($List) { $t = $buf | Format-List * | Out-String -Width 300 }
        elseif ($buf[0].PSObject.BaseObject -is [System.Management.Automation.PSCustomObject]) {
            # ohne ausdrückliche Spaltenliste zeigt Format-Table höchstens 10 Spalten
            $props = @($buf[0].PSObject.Properties | ForEach-Object { $_.Name })
            $t = $buf | Format-Table -Property $props -AutoSize -Wrap | Out-String -Width 400
        }
        else       { $t = $buf | Format-Table -AutoSize -Wrap | Out-String -Width 300 }
        Add-Line ($t.Trim("`r", "`n"))
    }
}

function Add-Finding {
    param([ValidateSet('KRITISCH', 'WARNUNG', 'INFO')][string]$Level, [string]$Area, [string]$Text)
    if ($script:FindKeys -and -not $script:FindKeys.Add(('{0}|{1}|{2}' -f $Level, $Area, $Text))) { return }
    $script:Findings.Add([pscustomobject]@{ Stufe = $Level; Bereich = $Area; Befund = $Text })
    Send-GuiEvent 'FIND' $Level $Area $Text
    $color = @{ KRITISCH = 'Red'; WARNUNG = 'Yellow'; INFO = 'DarkCyan' }[$Level]
    Write-Host ('    [{0}] {1}: {2}' -f $Level, $Area, $Text) -ForegroundColor $color
}

function Write-Step([string]$Text) { Write-Host ('[{0}]    {1}' -f (Get-Date -Format 'HH:mm:ss'), $Text) -ForegroundColor Gray }

function Invoke-Section {
    param(
        [Parameter(Position = 0, Mandatory = $true)][string]$Title,
        [Parameter(Position = 1, Mandatory = $true)][scriptblock]$Body,
        [switch]$Skippable
    )
    $script:StepNo++
    $total = [math]::Max((Get-PlannedSteps), $script:StepNo)
    Add-Section $Title ('[{0}/{1}] ' -f $script:StepNo, $total)
    Show-Overall $Title
    Hide-Sub
    $script:CpCurrent = $Title
    Write-Checkpoint 'START' ('[{0}/{1}] {2}' -f $script:StepNo, $total, $Title)
    $isSkippable = [bool]($Skippable -or ($Title -match '^(Updates|Test: Microsoft Defender|Test: SMART-Langtest|Test: Arbeitsspeicher \(Mustertest\)|Energie$|Test: Dateisystem und Systemdateien|Benchmark: (Prozessor|Grafik))'))
    if (Get-Command Send-GuiEvent -ErrorAction SilentlyContinue) { Send-GuiEvent 'SKIP_ALLOWED' $(if ($isSkippable) { '1' } else { '0' }) }
    if ($isSkippable -and (Get-Command Test-SkipRequested -ErrorAction SilentlyContinue) -and (Test-SkipRequested)) {
        if (Get-Command Send-StepSkipped -ErrorAction SilentlyContinue) { Send-StepSkipped $Title }
        Add-Line ('  ÜBERSPRUNGEN: Schritt durch Benutzer übersprungen.')
        if (Get-Command Add-TestResult -ErrorAction SilentlyContinue) { Add-TestResult $Title 'ÜBERSPRUNGEN' 'Schritt durch Benutzer übersprungen' }
        Add-Finding INFO 'Ablauf' ('Schritt "{0}" wurde auf Benutzeranforderung übersprungen.' -f $Title)
        Write-Checkpoint 'SKIP' ('{0} (übersprungen)' -f $Title)
        Save-Partial
        if (Get-Command Send-GuiEvent -ErrorAction SilentlyContinue) { Send-GuiEvent 'SKIP_ALLOWED' '0' }
        return
    }
    # Vor Abschnitten, bei denen ein Absturz am ehesten droht, den Zwischenstand sofort sichern (sonst gedrosselt)
    if ($Title -match '^(Lasttest|Benchmark|Test: (CPU|Arbeitsspeicher)|Reparatur|Optimierung)') { Save-Partial -Force }
    # Schneller Modus: exklusive Messungen warten auf die Hintergrundprüfungen
    try { Enter-SectionSchedule $Title } catch { }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $wasSkipped = $false
    try { & $Body }
    catch {
        if ($isSkippable -and ($_.Exception -is [System.OperationCanceledException] -or $_.Exception.Message -match 'übersprungen')) {
            $wasSkipped = $true
            Send-StepSkipped $Title
            Add-Line ('  ÜBERSPRUNGEN: Schritt durch Benutzer übersprungen.')
            if (Get-Command Add-TestResult -ErrorAction SilentlyContinue) { Add-TestResult $Title 'ÜBERSPRUNGEN' 'Schritt durch Benutzer übersprungen' }
            Add-Finding INFO 'Ablauf' ('Schritt "{0}" wurde auf Benutzeranforderung übersprungen.' -f $Title)
            Write-Checkpoint 'SKIP' ('{0} (übersprungen)' -f $Title)
        } else {
            $ln = $(if ($_.InvocationInfo) { $_.InvocationInfo.ScriptLineNumber } else { 0 })
            Add-Line ('  FEHLER in diesem Abschnitt: {0} (Zeile {1})' -f $_.Exception.Message, $ln)
            Write-Warning ('{0}: {1}' -f $Title, $_.Exception.Message)
            Write-Checkpoint 'FEHLER' ('{0}: {1} (Zeile {2})' -f $Title, $_.Exception.Message, $ln)
            # sichtbar in Befunden und Tests, nicht nur in den Details: ein abgebrochener Abschnitt darf nicht wie ein leerer Bericht aussehen
            if ($null -ne $script:SectionErrors) { $script:SectionErrors.Add([pscustomobject]@{ Abschnitt = $Title; Meldung = $_.Exception.Message; Zeile = $ln }) }
            Add-Finding WARNUNG 'Ablauf' ('Abschnitt "{0}" wurde wegen eines Skriptfehlers abgebrochen: {1} (Zeile {2}). Details in Checkpoint.log und in der KI-Datei.' -f $Title, $_.Exception.Message, $ln)
        }
    }
    finally {
        if (Get-Command Send-GuiEvent -ErrorAction SilentlyContinue) { Send-GuiEvent 'SKIP_ALLOWED' '0' }
    }
    $sw.Stop()
    $script:Timings.Add([pscustomobject]@{ Abschnitt = $Title; Dauer = ('{0:hh\:mm\:ss}' -f $sw.Elapsed) })
    if (-not $wasSkipped) { Write-Checkpoint 'OK' ('{0} ({1:hh\:mm\:ss})' -f $Title, $sw.Elapsed) }
    try { Exit-SectionSchedule $Title } catch { }
    Save-Partial
}

# Statische WMI-Klassen (Hardware) nur einmal je Lauf abfragen
$script:CimCache = @{}
function Get-CimCached([string]$Class, [string]$Namespace = '') {
    $k = if ($Namespace) { "$Namespace`:$Class" } else { $Class }
    if (-not $script:CimCache.ContainsKey($k)) {
        if ($Namespace) {
            $script:CimCache[$k] = @(Get-CimInstance -Namespace $Namespace -ClassName $Class -ErrorAction SilentlyContinue)
        } else {
            $script:CimCache[$k] = @(Get-CimInstance -ClassName $Class -ErrorAction SilentlyContinue)
        }
    }
    return $script:CimCache[$k]
}

# Laufzeit seit dem Start lesbar (ab v2.8): "5 Std 21 Min", "3 Tage 2 Std", ohne "0 Tage"
function Format-Uptime([TimeSpan]$Span) {
    if ($Span.TotalMinutes -lt 1) { return 'unter 1 Min' }
    $p = @()
    if ($Span.Days -gt 0) { $p += ('{0} {1}' -f $Span.Days, $(if ($Span.Days -eq 1) { 'Tag' } else { 'Tage' })) }
    if ($Span.Hours -gt 0) { $p += ('{0} Std' -f $Span.Hours) }
    if ($Span.Days -lt 2 -and $Span.Minutes -gt 0) { $p += ('{0} Min' -f $Span.Minutes) }
    return ($p -join ' ')
}

# Ausgabe in UTF-8, gelesen als OEM-Codepage (ab v2.8): Neuere netsh-Meldungen kommen unter Windows 11 in UTF-8, auch wenn
# die Konsole OEM 850 nutzt ("ben├Âtigen" statt "benötigen"). Nur wenn die Rückwandlung gültiges UTF-8 ergibt und
# typische Fehlzeichen verschwinden, wird der Text ersetzt.
function Repair-Utf8AsOem([string]$Text) {
    if (-not $Text -or $Text -notmatch '[\u251C\u00D4\u00C3\u2502]') { return $Text }
    try {
        $b = $script:OemEnc.GetBytes($Text)
        $u = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($b)
        if ($u -ne $Text -and $u -notmatch '[\u251C\u2502]') { return $u }
    } catch { }
    return $Text
}

function Invoke-External {
    param([string]$File, [string]$Arguments = '', [int]$TimeoutSec = 600, [Text.Encoding]$Encoding = $script:OemEnc, [string]$Progress = '', [int]$ExpectedSec = 0, [switch]$OhneUeberspringen)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File; $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    # Arbeitsordner = Anhang des Berichts: Dateien, die Werkzeuge ungefragt im aktuellen Ordner ablegen, landen nicht auf dem PC
    if ($RawDir -and (Test-Path -LiteralPath $RawDir)) { $psi.WorkingDirectory = $RawDir }
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Encoding; $psi.StandardErrorEncoding = $Encoding
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try { [void]$p.Start() } catch { return [pscustomobject]@{ ExitCode = -1; Output = ''; Error = $_.Exception.Message; TimedOut = $false } }
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    $sw = [Diagnostics.Stopwatch]::StartNew(); $timedOut = $false
    while (-not $p.WaitForExit(500)) {
        # -OhneUeberspringen: Hilfsmodi außerhalb eines Laufs (winget der Seite Tools) reagieren nicht auf skip.flag eines laufenden Laufs
        if (-not $OhneUeberspringen -and (Get-Command Test-SkipRequested -ErrorAction SilentlyContinue) -and (Test-SkipRequested)) {
            try { $p.Kill() } catch { }
            throw (New-Object System.OperationCanceledException 'Vom Benutzer übersprungen')
        }
        if ($Progress) {
            $st = 'läuft seit {0:hh\:mm\:ss}' -f $sw.Elapsed
            if ($ExpectedSec -gt 0) { Show-Sub $Progress ($st + ('   (üblich: ca. {0} Min.)' -f [math]::Ceiling($ExpectedSec / 60))) ([int]([math]::Min(99.0, $sw.Elapsed.TotalSeconds / $ExpectedSec * 100.0))) }
            else { Show-Sub $Progress $st }
            # ab v2.7: Sensoren des Benchmarks während WinSAT
            if ($script:BenchSens -and $script:BenchSens.On) { Add-BenchSensorSample }
        }
        if ($sw.Elapsed.TotalSeconds -ge $TimeoutSec) { $timedOut = $true; break }
    }
    if ($Progress) { Hide-Sub }
    if ($timedOut) { try { $p.Kill() } catch { } ; [void]$p.WaitForExit(5000) }
    $res = [pscustomobject]@{
        ExitCode = $(if ($timedOut) { -2 } else { $p.ExitCode })
        Output   = ($o.Result -replace "`0", '')
        Error    = ($e.Result -replace "`0", '')
        TimedOut = $timedOut
    }
    $p.Dispose()
    return $res
}

# Text in Zeilen von höchstens $Width Zeichen umbrechen (an Leerzeichen), für den Kopf des Textberichts
function Split-TextLines([string]$Text, [int]$Width = 94) {
    $out = New-Object System.Collections.Generic.List[string]
    $line = ''
    foreach ($w in @(([string]$Text) -split '\s+' | Where-Object { $_ })) {
        if ($line.Length -and ($line.Length + 1 + $w.Length) -gt $Width) { $out.Add($line); $line = $w }
        else { $line = $(if ($line.Length) { $line + ' ' + $w } else { $w }) }
    }
    if ($line.Length) { $out.Add($line) }
    return $out.ToArray()
}

function Format-Size($Bytes) {
    if ($null -eq $Bytes) { return '' }
    $b = [double]$Bytes
    if ($b -ge 1TB) { return '{0:N2} TB' -f ($b / 1TB) }
    if ($b -ge 1GB) { return '{0:N1} GB' -f ($b / 1GB) }
    if ($b -ge 1MB) { return '{0:N0} MB' -f ($b / 1MB) }
    return '{0:N0} KB' -f ($b / 1KB)
}

function Get-Ev([hashtable]$Filter, [int]$Max = 1000) {
    try { @(Get-WinEvent -FilterHashtable $Filter -MaxEvents $Max -ErrorAction SilentlyContinue) } catch { @() }
}

function Get-ShortText([string]$Text, [int]$Length = 160) {
    if (-not $Text) { return '' }
    $l = (($Text -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
    if (-not $l) { return '' }
    $l = $l.Trim()
    if ($l.Length -gt $Length) { $l.Substring(0, $Length) + '...' } else { $l }
}

function Format-SizeDec($Bytes) {
    if ($null -eq $Bytes) { return '' }
    $b = [double]$Bytes
    if ($b -ge 1e12) { return '{0:N1} TB' -f ($b / 1e12) }
    if ($b -ge 1e9)  { return '{0:N0} GB' -f ($b / 1e9) }
    return '{0:N0} MB' -f ($b / 1e6)
}

function ConvertTo-HtmlText([string]$Text) {
    if ($null -eq $Text) { return '' }
    return (($Text -replace '&', '&amp;') -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
}

function Get-CpuAnzeigename([string]$Name) {
    if (-not $Name) { return '' }
    $s = (($Name -as [string]) -replace '\s+', ' ').Trim()
    $s = $s -replace '\((R|TM|tm)\)', ''
    $s = $s -replace '\s*@\s*[\d.]+\s*[GM]Hz.*$', ''
    $s = $s -replace '\s*-\s*Qualcomm\s+Oryon\s+CPU.*$', ''
    $s = $s -replace '\s*Qualcomm\s+Oryon\s+CPU.*$', ''
    $s = $s -replace '\s*(-?\s*\d+-Core)?\s*(Processor|Prozessor).*$', ''
    $s = $s -replace '\s*\d+-Core.*$', ''
    $s = $s -replace '\s+CPU$', ''
    $s = $s -replace '\b(Intel|AMD)\b\s*', ''
    $s = ($s -replace '\s+-\s+', ' ').Trim()
    $s = ($s -replace '\s+', ' ').Trim()
    return $s
}

#region ---------- Gesamtsystemverbrauch & Effizienz (ab v3.63) ----------
# Mathematisches Modell zur realistischen Schätzung des Gesamtsystemverbrauchs (DC intern und AC an der Steckdose)
# anhand von Messwerten (CPU Package Power, GPU Board Power) und Plattform-Parametern (Desktop vs. Notebook).


function Test-IsNotebookSystem($Entry = $null) {
    if ($Entry) {
        if (Get-Command 'Test-EntryIsNotebook' -ErrorAction SilentlyContinue) { return [bool](& 'Test-EntryIsNotebook' $Entry) }
        return $false
    }
    if ($script:IsLaptop) { return $true }
    if (Get-Command 'Test-OnBattery' -ErrorAction SilentlyContinue) {
        if (& 'Test-OnBattery') { return $true }
    }
    if ($script:BatteryInfo -and @($script:BatteryInfo | Where-Object { $_.DesignmWh -gt 0 -or $_.VollmWh -gt 0 }).Count -gt 0) { return $true }
    if (Get-Command 'Get-CimCached' -ErrorAction SilentlyContinue) {
        $chassis = @(& 'Get-CimCached' Win32_SystemEnclosure -ErrorAction SilentlyContinue | ForEach-Object { $_.ChassisTypes } | ForEach-Object { $_ })
        foreach ($ct in $chassis) {
            if ($ct -in 8, 9, 10, 11, 12, 14, 30, 31, 32) { return $true }
        }
        $cs = & 'Get-CimCached' Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cs -and ("$($cs.Manufacturer) $($cs.Model)" -match '(?i)\b(Laptop|Notebook|Convertible|Subnotebook|Tablet|ThinkPad|ZenBook|EliteBook|Latitude|Precision \d{4})\b')) {
            return $true
        }
    }
    return $false
}

function Get-EstimatedSystemPower {
    param(
        $CpuW,
        $GpuW = 0.0,
        [switch]$IsNotebook,
        [double]$RamGb = 16.0,
        [double]$RamLoadPct = 10.0,
        [int]$DiskCount = 1,
        [switch]$DiskLoad,
        [switch]$OnBattery,
        $BatteryDischargeW = $null
    )

    $hasCpu = ($null -ne $CpuW -and "$CpuW" -ne '' -and -not [double]::IsNaN([double]$CpuW) -and [double]$CpuW -gt 0)
    $hasBat = ($OnBattery -and $null -ne $BatteryDischargeW -and "$BatteryDischargeW" -ne '' -and -not [double]::IsNaN([double]$BatteryDischargeW) -and [double]$BatteryDischargeW -gt 0)

    if (-not $hasCpu -and -not $hasBat) {
        return [pscustomobject]@{
            Verfuegbar       = $false
            Text             = 'n/v (kein Leistungssensor)'
            P_AC             = $null
            P_DC             = $null
            CpuW             = $null
            GpuW             = $null
            RamW             = $null
            BoardW           = $null
            DiskW            = $null
            VrmW             = $null
            Wirkungsgrad     = $null
            IsNotebook       = [bool]$IsNotebook
            Aufschluesselung = 'Kein Leistungssensor vorhanden (RAPL/LHM erforderlich)'
        }
    }

    $cW = $(if ($hasCpu) { [double]$CpuW } else { 0.0 })
    $gW = $(if ($null -ne $GpuW -and "$GpuW" -ne '' -and -not [double]::IsNaN([double]$GpuW) -and [double]$GpuW -gt 0) { [double]$GpuW } else { 0.0 })
    $rGb = $(if ($RamGb -gt 0) { [double]$RamGb } else { 16.0 })
    $rLoad = [math]::Max(0.0, [math]::Min(100.0, [double]$RamLoadPct))
    $dCount = [math]::Max(1, [int]$DiskCount)

    if ($IsNotebook) {
        if ($hasBat) {
            $pDc = [double]$BatteryDischargeW
            $pAc = $pDc
            $eta = 1.0
            $aufschluesselung = ('Akkubetrieb: Reale Entladeleistung {0:N1} W laut Akkusensor' -f $pDc)
            return [pscustomobject]@{
                Verfuegbar       = $true
                Text             = ('~{0:N0} W' -f [math]::Round($pAc))
                P_AC             = [math]::Round($pAc, 1)
                P_DC             = [math]::Round($pDc, 1)
                CpuW             = [math]::Round($cW, 1)
                GpuW             = [math]::Round($gW, 1)
                RamW             = 0.0
                BoardW           = 0.0
                DiskW            = 0.0
                VrmW             = 0.0
                Wirkungsgrad     = $eta
                IsNotebook       = $true
                Aufschluesselung = $aufschluesselung
            }
        }

        # Notebook Netzbetrieb
        $vrm = [math]::Round(0.05 * $cW, 1)
        $boardDisplay = 7.0 # Display ~4 W + Plattform/WLAN ~3 W
        $ramSsd = 3.0       # LPDDR/DDR-SO-DIMM und NVMe
        $pDc = $cW + $gW + $vrm + $boardDisplay + $ramSsd
        $eta = 0.90         # Ladenetzteil Wirkungsgrad ~90 %
        $pAc = $pDc / $eta

        $aufschluesselung = ('Gemessen: CPU {0:N0} W{1} + Zuschlag: Display & Plattform {2:N0} W, RAM & SSD {3:N0} W, VRM {4:N1} W = DC {5:N0} W / ~{6:N0} W an der Steckdose (Wirkungsgrad {7:N0} %)' -f `
            $cW, $(if ($gW -gt 0) { ', GPU {0:N0} W' -f $gW } else { '' }), $boardDisplay, $ramSsd, $vrm, $pDc, $pAc, ($eta * 100))

        return [pscustomobject]@{
            Verfuegbar       = $true
            Text             = ('~{0:N0} W' -f [math]::Round($pAc))
            P_AC             = [math]::Round($pAc, 1)
            P_DC             = [math]::Round($pDc, 1)
            CpuW             = [math]::Round($cW, 1)
            GpuW             = [math]::Round($gW, 1)
            RamW             = $ramSsd
            BoardW           = $boardDisplay
            DiskW            = 0.0
            VrmW             = $vrm
            Wirkungsgrad     = $eta
            IsNotebook       = $true
            Aufschluesselung = $aufschluesselung
        }
    } else {
        # Desktop
        $vrm = [math]::Round(0.08 * $cW, 1)
        # RAM: Basis 1.5 W + (RAM-GB / 16) * (1.5 W + Auslastung% * 2.5 W)
        $ramW = [math]::Round(1.5 + ($rGb / 16.0) * (1.5 + ($rLoad / 100.0) * 2.5), 1)
        # Mainboard: Chipsatz 15 W + Lüfter/RGB 5 W = 20 W
        $boardW = 20.0
        # Laufwerke: 1.5 W je SSD Leerlauf, +3.5 W unter Last
        $diskW = [math]::Round($dCount * $(if ($DiskLoad) { 5.0 } else { 1.5 }), 1)

        $pDc = $cW + $gW + $ramW + $boardW + $diskW + $vrm
        $eta = 0.88 # 80-PLUS Standard ~88 %
        $pAc = $pDc / $eta

        $aufschluesselung = ('Gemessen: CPU {0:N0} W{1} + Zuschlag: Mainboard {2:N0} W, RAM {3:N1} W, Laufwerke {4:N1} W, VRM {5:N1} W = DC {6:N0} W / ~{7:N0} W an der Steckdose (Wirkungsgrad {8:N0} %)' -f `
            $cW, $(if ($gW -gt 0) { ', GPU {0:N0} W' -f $gW } else { '' }), $boardW, $ramW, $diskW, $vrm, $pDc, $pAc, ($eta * 100))

        return [pscustomobject]@{
            Verfuegbar       = $true
            Text             = ('~{0:N0} W' -f [math]::Round($pAc))
            P_AC             = [math]::Round($pAc, 1)
            P_DC             = [math]::Round($pDc, 1)
            CpuW             = [math]::Round($cW, 1)
            GpuW             = [math]::Round($gW, 1)
            RamW             = $ramW
            BoardW           = $boardW
            DiskW            = $diskW
            VrmW             = $vrm
            Wirkungsgrad     = $eta
            IsNotebook       = $false
            Aufschluesselung = $aufschluesselung
        }
    }
}

function Get-SystemPowerProfile($Entry = $null) {
    $isNb = $(if ($Entry) {
        if (Get-Command 'Test-EntryIsNotebook' -ErrorAction SilentlyContinue) { [bool](& 'Test-EntryIsNotebook' $Entry) } else { $false }
    } else {
        if (Get-Command 'Test-IsNotebookSystem' -ErrorAction SilentlyContinue) { [bool](& 'Test-IsNotebookSystem') } else { $false }
    })

    # RAM-Größe in GB
    $ramGb = 16.0
    $ramStr = $(if ($Entry -and $Entry.Hardware -and $Entry.Hardware.RAM) { [string]$Entry.Hardware.RAM }
                elseif ($script:Facts -and $script:Facts['Arbeitsspeicher']) { [string]$script:Facts['Arbeitsspeicher'] }
                else { '' })
    if ($ramStr -match '(\d+)\s*GB') { $ramGb = [double]$matches[1] }

    # Laufwerksanzahl
    $disks = $(if ($Entry -and $Entry.Laufwerke) { @($Entry.Laufwerke).Count }
               elseif ($script:BenchDisks) { @($script:BenchDisks).Count }
               else { 1 })
    $diskCount = [math]::Max(1, [int]$disks)

    # Dedizierte GPU vorhanden?
    $hasDgpu = $false
    if ($Entry) {
        $gpuStr = $(if ($Entry.Hardware -and $Entry.Hardware.GPU) { [string]$Entry.Hardware.GPU } else { '' })
        if ($gpuStr -and (Get-Command 'Get-GpuKind' -ErrorAction SilentlyContinue)) {
            $hasDgpu = ((& 'Get-GpuKind' $gpuStr) -eq 'dGPU')
        }
    } else {
        if (Get-Command 'Get-GpuAdapters' -ErrorAction SilentlyContinue) {
            $gAdapters = @(& 'Get-GpuAdapters')
            $hasDgpu = [bool](@($gAdapters | Where-Object { $_.Art -eq 'dGPU' }).Count)
        }
    }

    # Sensorwerte: Leerlauf und Volllast
    $cpuWIdle = $null; $gpuWIdle = $null
    $cpuWMax = $null; $gpuWMax = $null

    if ($Entry) {
        if ($Entry.Sensoren) {
            if ($Entry.Sensoren.Leerlauf -and $Entry.Sensoren.Leerlauf.CpuW) { $cpuWIdle = [double]$Entry.Sensoren.Leerlauf.CpuW }
            if ($Entry.Sensoren.Last -and $Entry.Sensoren.Last.CpuWMax) { $cpuWMax = [double]$Entry.Sensoren.Last.CpuWMax }
            if ($Entry.Sensoren.Last -and $Entry.Sensoren.Last.GpuWMax) { $gpuWMax = [double]$Entry.Sensoren.Last.GpuWMax }
            if ($null -eq $cpuWMax -and $Entry.Sensoren.Benchmark -and $Entry.Sensoren.Benchmark.CpuWMax) { $cpuWMax = [double]$Entry.Sensoren.Benchmark.CpuWMax }
            if ($null -eq $gpuWMax -and $Entry.Sensoren.Benchmark -and $Entry.Sensoren.Benchmark.GpuWMax) { $gpuWMax = [double]$Entry.Sensoren.Benchmark.GpuWMax }
        }
        if ($null -eq $cpuWMax -and $Entry.Lasttest -and $Entry.Lasttest -match 'max (\d+)\s*W') { $cpuWMax = [double]$matches[1] }
    } else {
        if ($script:SensorDb) {
            if ($script:SensorDb['Leerlauf'] -and $script:SensorDb['Leerlauf'].CpuW) { $cpuWIdle = [double]$script:SensorDb['Leerlauf'].CpuW }
            if ($script:SensorDb['Leerlauf'] -and $script:SensorDb['Leerlauf'].GpuW) { $gpuWIdle = [double]$script:SensorDb['Leerlauf'].GpuW }
            if ($script:SensorDb['Last'] -and $script:SensorDb['Last'].CpuWMax) { $cpuWMax = [double]$script:SensorDb['Last'].CpuWMax }
            if ($script:SensorDb['Last'] -and $script:SensorDb['Last'].GpuWMax) { $gpuWMax = [double]$script:SensorDb['Last'].GpuWMax }
            if ($null -eq $cpuWMax -and $script:SensorDb['Benchmark'] -and $script:SensorDb['Benchmark'].CpuWMax) { $cpuWMax = [double]$script:SensorDb['Benchmark'].CpuWMax }
            if ($null -eq $gpuWMax -and $script:SensorDb['Benchmark'] -and $script:SensorDb['Benchmark'].GpuWMax) { $gpuWMax = [double]$script:SensorDb['Benchmark'].GpuWMax }
        }
        if ($null -eq $cpuWMax -and $script:LoadSeries) {
            $wVals = @($script:LoadSeries | ForEach-Object { $_.CpuW } | Where-Object { $null -ne $_ -and $_ -gt 0 })
            if ($wVals.Count) { $cpuWMax = ($wVals | Measure-Object -Maximum).Maximum }
        }
        if ($null -eq $gpuWMax -and $script:LoadSeries) {
            $gwVals = @($script:LoadSeries | ForEach-Object { $_.GpuW } | Where-Object { $null -ne $_ -and $_ -gt 0 })
            if ($gwVals.Count) { $gpuWMax = ($gwVals | Measure-Object -Maximum).Maximum }
        }
    }

    # Nur dGPU-Leistung werten; iGPU ist bereits im CPU-Package enthalten
    if (-not $hasDgpu) { $gpuWIdle = 0.0; $gpuWMax = 0.0 }
    elseif ($null -eq $gpuWIdle -and $hasDgpu) { $gpuWIdle = $(if ($isNb) { 5.0 } else { 12.0 }) }

    # Teillast abschätzen (Alltagsbetrieb / Büro / Video)
    $cpuWPart = $null; $gpuWPart = $null
    if ($null -ne $cpuWIdle -and $null -ne $cpuWMax) {
        $cpuWPart = [math]::Round($cpuWIdle + ($cpuWMax - $cpuWIdle) * 0.35, 1)
    } elseif ($null -ne $cpuWMax) {
        $cpuWPart = [math]::Round($cpuWMax * 0.40, 1)
    } elseif ($null -ne $cpuWIdle) {
        $cpuWPart = [math]::Round($cpuWIdle * 1.8, 1)
    }

    if ($hasDgpu) {
        if ($null -ne $gpuWIdle -and $null -ne $gpuWMax) {
            $gpuWPart = [math]::Round($gpuWIdle + ($gpuWMax - $gpuWIdle) * 0.20, 1)
        } elseif ($null -ne $gpuWMax) {
            $gpuWPart = [math]::Round($gpuWMax * 0.25, 1)
        }
    } else {
        $gpuWPart = 0.0
    }

    $pIdle = Get-EstimatedSystemPower -CpuW $cpuWIdle -GpuW $gpuWIdle -IsNotebook:$isNb -RamGb $ramGb -RamLoadPct 10.0 -DiskCount $diskCount
    $pPart = Get-EstimatedSystemPower -CpuW $cpuWPart -GpuW $gpuWPart -IsNotebook:$isNb -RamGb $ramGb -RamLoadPct 40.0 -DiskCount $diskCount
    $pLoad = Get-EstimatedSystemPower -CpuW $cpuWMax  -GpuW $gpuWMax  -IsNotebook:$isNb -RamGb $ramGb -RamLoadPct 90.0 -DiskCount $diskCount -DiskLoad

    # Effizienz-Indizes ermitteln
    $eff = [ordered]@{
        CpuMT_PerWatt  = $null
        Gpu_PerWatt    = $null
        System_PerWatt = $null
    }

    $cpuMtScore = 0.0
    $gpuScore = 0.0
    $overallScore = 0.0

    if ($Entry) {
        if ($Entry.Werte) {
            $wMt = if ($Entry.Werte -is [System.Collections.IDictionary]) { $Entry.Werte['CPU|MT'] } else { $Entry.Werte.'CPU|MT' }
            if ($null -ne $wMt -and [double]$wMt -gt 0) { $cpuMtScore = [double]$wMt }

            $wGpu = if ($Entry.Werte -is [System.Collections.IDictionary]) { $Entry.Werte['GPU|RPKT'] } else { $Entry.Werte.'GPU|RPKT' }
            if ($null -eq $wGpu) {
                $wGpu = if ($Entry.Werte -is [System.Collections.IDictionary]) { $Entry.Werte['GPU|REND'] } else { $Entry.Werte.'GPU|REND' }
            }
            if ($null -ne $wGpu -and [double]$wGpu -gt 0) { $gpuScore = [double]$wGpu }
        }
    } else {
        if ($script:BenchResults) {
            $mtRow = @($script:BenchResults | Where-Object { $_.RefKey -eq 'CPU|MT' -and $_.Wert -gt 0 }) | Select-Object -First 1
            if ($mtRow) { $cpuMtScore = [double]$mtRow.Wert }
            $rpktRow = @($script:BenchResults | Where-Object { $_.RefKey -in 'GPU|RPKT', 'GPU|REND' -and $_.Wert -gt 0 }) | Select-Object -First 1
            if ($rpktRow) { $gpuScore = [double]$rpktRow.Wert }
        }
        if (Get-Command Get-BenchOverall -ErrorAction SilentlyContinue) {
            $ov = Get-BenchOverall
            if ($null -ne $ov) { $overallScore = [double]$ov }
        }
    }

    if ($cpuMtScore -gt 0 -and $null -ne $cpuWMax -and $cpuWMax -gt 0) {
        $eff.CpuMT_PerWatt = [math]::Round($cpuMtScore / $cpuWMax, 1)
    }
    if ($gpuScore -gt 0 -and $null -ne $gpuWMax -and $gpuWMax -gt 0) {
        $eff.Gpu_PerWatt = [math]::Round($gpuScore / $gpuWMax, 2)
    }
    if ($overallScore -gt 0 -and $pLoad.Verfuegbar -and $pLoad.P_AC -gt 0) {
        $eff.System_PerWatt = [math]::Round(($overallScore / $pLoad.P_AC) * 100.0, 1)
    }

    return [pscustomobject]@{
        IsNotebook  = $isNb
        Leerlauf    = $pIdle
        Teillast    = $pPart
        Volllast    = $pLoad
        Effizienz   = [pscustomobject]$eff
    }
}
#endregion
