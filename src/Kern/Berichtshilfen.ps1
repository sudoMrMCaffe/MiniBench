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

function Get-PsuEfficiency {
    param(
        [double]$P_DC,
        [int]$PsuWattage = 650,
        [string]$PsuRating = '80 PLUS Bronze',
        [string]$LoadStage = 'Load'
    )
    $curves = @{
        'Unbekannt'          = @(78.0, 82.0, 86.0, 88.0, 85.0)
        '80 PLUS White'      = @(76.0, 80.0, 84.0, 86.0, 83.0)
        '80 PLUS Bronze'     = @(79.0, 83.0, 86.5, 88.5, 85.5)
        '80 PLUS Silver'     = @(81.0, 85.0, 88.5, 90.5, 88.0)
        '80 PLUS Gold'       = @(83.5, 87.5, 90.5, 92.5, 90.0)
        '80 PLUS Platinum'   = @(85.5, 89.5, 92.5, 94.0, 91.5)
        '80 PLUS Titanium'   = @(88.0, 91.5, 94.5, 96.0, 93.5)
    }
    $ratingKey = $PsuRating
    if (-not $curves.ContainsKey($ratingKey)) {
        $found = @($curves.Keys | Where-Object { $_ -like "*$ratingKey*" -or $ratingKey -like "*$_*" })
        if ($found.Count) { $ratingKey = $found[0] } else { $ratingKey = '80 PLUS Bronze' }
    }
    $points = $curves[$ratingKey]
    $xVals = @(5.0, 10.0, 20.0, 50.0, 100.0)

    if ($PsuWattage -gt 0) {
        $loadPct = ($P_DC / [double]$PsuWattage) * 100.0
        $eta = 80.0
        if ($loadPct -le 0.0) {
            $eta = 70.0
        } elseif ($loadPct -lt 5.0) {
            # Unter 5 % flach abfallend extrapolieren (Min-Cap bei 70 %)
            $slope = ($points[0] - 70.0) / 5.0
            $eta = [math]::Max(70.0, 70.0 + $loadPct * $slope)
        } elseif ($loadPct -le 100.0) {
            for ($i = 0; $i -lt 4; $i++) {
                if ($loadPct -ge $xVals[$i] -and $loadPct -le $xVals[$i + 1]) {
                    $x0 = $xVals[$i]; $x1 = $xVals[$i + 1]
                    $y0 = $points[$i]; $y1 = $points[$i + 1]
                    $eta = $y0 + ($loadPct - $x0) * (($y1 - $y0) / ($x1 - $x0))
                    break
                }
            }
        } else {
            # Über 100 % leicht abfallend extrapolieren bzw. bei 100 %-Stützwert minus 2 % deckeln
            $minCap = $points[4] - 2.0
            $eta = [math]::Max($minCap, $points[4] - ($loadPct - 100.0) * 0.1)
        }
        return [pscustomobject]@{
            EtaPercent   = [math]::Round($eta, 1)
            EtaFraction  = [math]::Round($eta / 100.0, 4)
            LoadPercent  = [math]::Round($loadPct, 1)
            PsuWattage   = $PsuWattage
            PsuRating    = $ratingKey
        }
    } else {
        # PsuWattage == 0: feste Stützstellen (Idle: 10 %, Teillast: 20 %, Gaming/Volllast: 50 %)
        $idx = switch ($LoadStage) {
            'Idle'     { 1 }
            'Teillast' { 2 }
            default    { 3 }
        }
        $eta = $points[$idx]
        return [pscustomobject]@{
            EtaPercent   = [math]::Round($eta, 1)
            EtaFraction  = [math]::Round($eta / 100.0, 4)
            LoadPercent  = $null
            PsuWattage   = 0
            PsuRating    = $ratingKey
        }
    }
}

function Get-EstimatedSystemPower {
    param(
        $CpuW,
        $GpuW = 0.0,
        [switch]$IsNotebook,
        $GpuName = '',
        [int]$DimmCount = 0,
        [switch]$RamOc,
        $Disks = $null,
        [int]$DiskCount = 0,
        [double]$NvmeTemp = 0.0,
        [switch]$DiskLoad,
        [int]$FanCount = 0,
        [switch]$IsIdle,
        [switch]$IsTeillast,
        $PsuWattage = $null,
        $PsuRating = $null,
        [string]$Stage = '',
        [switch]$OnBattery,
        $BatteryDischargeW = $null,
        # Abwärtskompatibilität für ältere Aufrufe
        [double]$RamGb = 0.0,
        [double]$RamLoadPct = 0.0
    )

    $hasCpu = ($null -ne $CpuW -and "$CpuW" -ne '' -and -not [double]::IsNaN([double]$CpuW) -and [double]$CpuW -gt 0)
    $hasBat = ($OnBattery -and $null -ne $BatteryDischargeW -and "$BatteryDischargeW" -ne '' -and -not [double]::IsNaN([double]$BatteryDischargeW) -and [double]$BatteryDischargeW -gt 0)

    if (-not $hasCpu -and -not $hasBat) {
        return [pscustomobject]@{
            Verfuegbar           = $false
            Text                 = 'n/v (kein Leistungssensor)'
            P_AC                 = $null
            P_DC                 = $null
            CpuW                 = $null
            GpuW                 = $null
            RamW                 = $null
            BoardW               = $null
            DiskW                = $null
            FanW                 = $null
            VrmW                 = $null
            Wirkungsgrad         = $null
            WirkungsgradProzent  = $null
            LoadPercent          = $null
            PsuWattage           = $(if ($null -ne $PsuWattage) { [int]$PsuWattage } elseif ($script:PsuWattage -ne $null) { [int]$script:PsuWattage } else { 650 })
            PsuRating            = $(if ($PsuRating) { [string]$PsuRating } elseif ($script:PsuRating) { [string]$script:PsuRating } else { '80 PLUS Bronze' })
            IsNotebook           = [bool]$IsNotebook
            Aufschluesselung     = 'Kein Leistungssensor vorhanden (RAPL/LHM erforderlich)'
            AufschluesselungKurz = 'n/v (kein Leistungssensor)'
        }
    }

    $cW = $(if ($hasCpu) { [double]$CpuW } else { 0.0 })
    $gWSensor = $(if ($null -ne $GpuW -and "$GpuW" -ne '' -and -not [double]::IsNaN([double]$GpuW) -and [double]$GpuW -gt 0) { [double]$GpuW } else { 0.0 })

    $pWatt = if ($null -ne $PsuWattage) { [int]$PsuWattage } elseif ($script:PsuWattage -ne $null) { [int]$script:PsuWattage } else { 650 }
    $pRate = if ($PsuRating) { [string]$PsuRating } elseif ($script:PsuRating) { [string]$script:PsuRating } else { '80 PLUS Bronze' }

    $stageName = if ($Stage) { $Stage } elseif ($IsIdle) { 'Idle' } elseif ($IsTeillast) { 'Teillast' } else { 'Load' }

    if ($IsNotebook) {
        if ($hasBat) {
            $pDc = [double]$BatteryDischargeW
            $pAc = $pDc
            $eta = 1.0
            $aufschluesselung = ('Akkubetrieb: Reale Entladeleistung {0:N1} W laut Akkusensor' -f $pDc)
            return [pscustomobject]@{
                Verfuegbar           = $true
                Text                 = ('~{0:N0} W' -f [math]::Round($pAc))
                P_AC                 = [math]::Round($pAc, 1)
                P_DC                 = [math]::Round($pDc, 1)
                CpuW                 = [math]::Round($cW, 1)
                GpuW                 = [math]::Round($gWSensor, 1)
                RamW                 = 0.0
                BoardW               = 0.0
                DiskW                = 0.0
                FanW                 = 0.0
                VrmW                 = 0.0
                Wirkungsgrad         = $eta
                WirkungsgradProzent  = 100.0
                LoadPercent          = $null
                PsuWattage           = 0
                PsuRating            = 'Akku'
                IsNotebook           = $true
                Aufschluesselung     = $aufschluesselung
                AufschluesselungKurz = ('~{0:N0} W (Akkubetrieb)' -f [math]::Round($pAc))
            }
        }

        # Notebook Netzbetrieb
        $vrmPct = if ($stageName -eq 'Idle') { 0.05 } else { 0.10 }
        $vrm = [math]::Round($cW * $vrmPct, 1)

        $gW = $gWSensor
        if ($gWSensor -gt 0 -and $GpuName -match '(?i)AMD|Radeon' -and $GpuName -notmatch '(?i)Graphics\s*$') {
            $gW = if ($gWSensor -lt 30.0) { $gWSensor + 4.0 } else { [math]::Round($gWSensor * 1.15, 1) }
        }

        $boardDisplay = switch ($stageName) {
            'Idle'     { 7.0 }
            'Teillast' { 8.0 }
            default    { 9.0 }
        }
        $ramSsd = switch ($stageName) {
            'Idle'     { 2.5 }
            'Teillast' { 3.5 }
            default    { 4.5 }
        }
        $pDc = [math]::Round($cW + $gW + $vrm + $boardDisplay + $ramSsd, 1)
        $eta = 0.90
        $pAc = [math]::Round($pDc / $eta, 1)

        $shortInfo = ('~{0:N0} W an der Steckdose (intern ~{1:N0} W | ~90 % Effizienz [OEM Netzteil])' -f [math]::Round($pAc), [math]::Round($pDc))
        $aufschluesselung = ('Gemessen: CPU {0:N0} W{1} + Zuschlag: Display & Plattform {2:N0} W, RAM & SSD {3:N1} W, VRM {4:N1} W = DC {5:N0} W / ~{6:N0} W an der Steckdose (Wirkungsgrad 90 %)' -f `
            $cW, $(if ($gW -gt 0) { ', GPU {0:N0} W' -f $gW } else { '' }), $boardDisplay, $ramSsd, $vrm, [math]::Round($pDc), [math]::Round($pAc))

        return [pscustomobject]@{
            Verfuegbar           = $true
            Text                 = ('~{0:N0} W' -f [math]::Round($pAc))
            P_AC                 = [double]$pAc
            P_DC                 = [double]$pDc
            CpuW                 = [math]::Round($cW, 1)
            GpuW                 = [math]::Round($gW, 1)
            RamW                 = $ramSsd
            BoardW               = $boardDisplay
            DiskW                = 0.0
            FanW                 = 0.0
            VrmW                 = $vrm
            Wirkungsgrad         = $eta
            WirkungsgradProzent  = 90.0
            LoadPercent          = $null
            PsuWattage           = 0
            PsuRating            = 'OEM Netzteil'
            IsNotebook           = $true
            Aufschluesselung     = $aufschluesselung
            AufschluesselungKurz = $shortInfo
        }
    } else {
        # Desktop
        # 1. CPU VRM: Idle 5 %, sonst 10 %
        $vrmPct = if ($stageName -eq 'Idle') { 0.05 } else { 0.10 }
        $vrm = [math]::Round($cW * $vrmPct, 1)

        # 2. GPU: AMD Radeon Offset bzw. 15% Aufschlag
        $gW = $gWSensor
        $isAmdGpu = ($gWSensor -gt 0) -and ($GpuName -match '(?i)AMD|Radeon') -and ($GpuName -notmatch '(?i)Graphics\s*$')
        if ($isAmdGpu) {
            $gW = if ($gWSensor -lt 30.0) { $gWSensor + 4.0 } else { [math]::Round($gWSensor * 1.15, 1) }
        }

        # 3. Mainboard-Basisverbrauch: 10 W (Idle), 12 W (Teillast), 14 W (Volllast)
        $boardW = switch ($stageName) {
            'Idle'     { 10.0 }
            'Teillast' { 12.0 }
            default    { 14.0 }
        }

        # 4. RAM: Zähle DIMMs (Fallback: 2 Module)
        $dCount = if ($DimmCount -gt 0) { $DimmCount } elseif ($RamGb -ge 32.0) { 2 } else { 2 }
        $ramPerMod = switch ($stageName) {
            'Idle'     { 1.5 }
            'Teillast' { 2.5 }
            default    { if ($RamOc) { 4.0 } else { 4.0 } }
        }
        $ramW = [math]::Round($dCount * $ramPerMod, 1)

        # 5. Datenträger (NVMe, SATA SSD, HDD)
        $nvmeC = 0; $sataC = 0; $hddC = 0
        if ($Disks -and @($Disks).Count -gt 0) {
            foreach ($d in @($Disks)) {
                $dStr = "$d"
                if ($dStr -match '(?i)NVMe') { $nvmeC++ }
                elseif ($dStr -match '(?i)HDD|Festplatte|ST\d{3,}|WD\d{3,}') { $hddC++ }
                else { $sataC++ }
            }
        } elseif ($DiskCount -gt 0) {
            $nvmeC = 1
            if ($DiskCount -gt 1) { $sataC = $DiskCount - 1 }
        } else {
            $nvmeC = 1
        }

        $nvmeIdle = if ($NvmeTemp -gt 45.0) { 2.2 } else { 1.8 }
        $nvmeW = switch ($stageName) {
            'Idle'     { $nvmeIdle }
            'Teillast' { 3.0 }
            default    { if ($DiskLoad) { 5.5 } else { 2.5 } }
        }
        $sataW = switch ($stageName) {
            'Idle'     { 0.8 }
            'Teillast' { 1.5 }
            default    { 2.5 }
        }
        $hddW = switch ($stageName) {
            'Idle'     { 4.5 }
            default    { 7.5 }
        }
        $diskW = [math]::Round(($nvmeC * $nvmeW) + ($sataC * $sataW) + ($hddC * $hddW), 1)

        # 6. Kühlung / Lüfter
        $fCount = if ($FanCount -gt 0) { $FanCount } else { 3 }
        $fanPerFan = switch ($stageName) {
            'Idle'     { 0.6 }
            'Teillast' { 1.0 }
            default    { 1.5 }
        }
        $fanW = [math]::Round($fCount * $fanPerFan, 1)

        $pDc = [math]::Round($cW + $gW + $vrm + $boardW + $ramW + $diskW + $fanW, 1)

        $effData = Get-PsuEfficiency -P_DC $pDc -PsuWattage $pWatt -PsuRating $pRate -LoadStage $stageName
        $eta = $effData.EtaFraction
        $etaPct = $effData.EtaPercent
        $loadPct = $effData.LoadPercent
        $pAc = [math]::Round($pDc / $eta)

        $shortInfo = if ($pWatt -gt 0 -and $null -ne $loadPct) {
            ('~{0:N0} W an der Steckdose (intern ~{1:N0} W | PSU-Last ~{2:N0} % @ ~{3:N1} % Effizienz [{4} W, {5}])' -f `
                $pAc, $pDc, [math]::Round($loadPct), $etaPct, $pWatt, $effData.PsuRating)
        } else {
            ('~{0:N0} W an der Steckdose (intern ~{1:N0} W | ~{2:N1} % Effizienz [{3}])' -f `
                $pAc, $pDc, $etaPct, $effData.PsuRating)
        }

        $aufschluesselung = ('Gemessen: CPU {0:N0} W{1} + Wandler/VRM {2:N1} W, Mainboard {3:N0} W, RAM {4:N1} W ({5} DIMMs), Datenträger {6:N1} W, Lüfter {7:N1} W ({8} Lüfter) = intern ~{9:N0} W | {10}' -f `
            $cW, $(if ($gWSensor -gt 0) { ', GPU {0:N0} W{1}' -f $gWSensor, $(if ($isAmdGpu) { ' (+AMD-TBP)' } else { '' }) } else { '' }), `
            $vrm, $boardW, $ramW, $dCount, $diskW, $fanW, $fCount, $pDc, $shortInfo)

        return [pscustomobject]@{
            Verfuegbar           = $true
            Text                 = ('~{0:N0} W' -f $pAc)
            P_AC                 = [double]$pAc
            P_DC                 = [double]$pDc
            CpuW                 = [math]::Round($cW, 1)
            GpuW                 = [math]::Round($gW, 1)
            RamW                 = $ramW
            BoardW               = $boardW
            DiskW                = $diskW
            FanW                 = $fanW
            VrmW                 = $vrm
            Wirkungsgrad         = $eta
            WirkungsgradProzent  = $etaPct
            LoadPercent          = $loadPct
            PsuWattage           = $pWatt
            PsuRating            = $effData.PsuRating
            IsNotebook           = $false
            Aufschluesselung     = $aufschluesselung
            AufschluesselungKurz = $shortInfo
        }
    }
}

function Get-SystemPowerProfile($Entry = $null) {
    $isNb = $(if ($Entry) {
        if (Get-Command 'Test-EntryIsNotebook' -ErrorAction SilentlyContinue) { [bool](& 'Test-EntryIsNotebook' $Entry) } else { $false }
    } else {
        if (Get-Command 'Test-IsNotebookSystem' -ErrorAction SilentlyContinue) { [bool](& 'Test-IsNotebookSystem') } else { $false }
    })

    # Netzteil-Konfiguration
    $psuWatt = if ($Entry -and $Entry.Netzteil -and $Entry.Netzteil.Wattage) { [int]$Entry.Netzteil.Wattage }
               elseif ($Entry -and $Entry.PsuWattage) { [int]$Entry.PsuWattage }
               elseif ($script:PsuWattage -ne $null) { [int]$script:PsuWattage }
               else { 650 }
    $psuRate = if ($Entry -and $Entry.Netzteil -and $Entry.Netzteil.Rating) { [string]$Entry.Netzteil.Rating }
               elseif ($Entry -and $Entry.PsuRating) { [string]$Entry.PsuRating }
               elseif ($script:PsuRating) { [string]$script:PsuRating }
               else { '80 PLUS Bronze' }

    # RAM-Größe und DIMMs
    $ramGb = 16.0
    $dimmCount = 2
    $ramOc = $false
    $ramStr = $(if ($Entry -and $Entry.Hardware -and $Entry.Hardware.RAM) { [string]$Entry.Hardware.RAM }
                elseif ($script:Facts -and $script:Facts['Arbeitsspeicher']) { [string]$script:Facts['Arbeitsspeicher'] }
                else { '' })
    if ($ramStr -match '(\d+)\s*GB') { $ramGb = [double]$matches[1] }
    if ($ramStr -match '(\d+)x') { $dimmCount = [int]$matches[1] }
    elseif (Get-Command Get-CimCached -ErrorAction SilentlyContinue) {
        $mems = @(Get-CimCached Win32_PhysicalMemory -ErrorAction SilentlyContinue)
        if ($mems.Count) { $dimmCount = $mems.Count }
    }
    if ($ramStr -match 'DDR5|EXPO|XMP|6000|5600|6400') { $ramOc = $true }

    # Laufwerke
    $disksList = @()
    if ($Entry -and $Entry.Laufwerke) {
        $disksList = @($Entry.Laufwerke)
    } elseif ($script:BenchDisks) {
        $disksList = @($script:BenchDisks | ForEach-Object { "$($_.Klasse) $($_.Laufwerk)" })
    }
    $diskCount = [math]::Max(1, $disksList.Count)

    # Lüfter
    $fanCount = 0
    if ($script:SensorDb -and $script:SensorDb['Leerlauf'] -and $script:SensorDb['Leerlauf'].Luefter) {
        if ([double]$script:SensorDb['Leerlauf'].Luefter -gt 0) { $fanCount = 3 }
    }
    if ($fanCount -le 0 -and -not $isNb) { $fanCount = 3 }

    # GPU
    $gpuName = ''
    $hasDgpu = $false
    if ($Entry) {
        $gpuStr = $(if ($Entry.Hardware -and $Entry.Hardware.GPU) { [string]$Entry.Hardware.GPU } else { '' })
        $gpuName = $gpuStr
        if ($gpuStr -and (Get-Command 'Get-GpuKind' -ErrorAction SilentlyContinue)) {
            $hasDgpu = ((& 'Get-GpuKind' $gpuStr) -eq 'dGPU')
        } elseif ($gpuStr) {
            $hasDgpu = ($gpuStr -match 'NVIDIA|GeForce|Quadro|Tesla|\bRTX\b|\bGTX\b|Radeon RX|Radeon Pro|FirePro|\bArc\b') -and ($gpuStr -notmatch 'Graphics\s*$|\b\d{3}M\b')
        }
    } else {
        if (Get-Command 'Get-GpuAdapters' -ErrorAction SilentlyContinue) {
            $gAdapters = @(& 'Get-GpuAdapters')
            $dg = @($gAdapters | Where-Object { $_.Art -eq 'dGPU' }) | Select-Object -First 1
            if ($dg) { $hasDgpu = $true; $gpuName = $dg.Name }
        }
        if (-not $gpuName -and $script:Facts -and $script:Facts['Grafikkarte']) {
            $gpuName = [string]$script:Facts['Grafikkarte']
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
        if ($Entry.Lasttest) {
            if ($null -eq $cpuWMax) {
                if ($Entry.Lasttest.CpuWMax) { $cpuWMax = [double]$Entry.Lasttest.CpuWMax }
                elseif ($Entry.Lasttest -match 'max (\d+)\s*W') { $cpuWMax = [double]$matches[1] }
            }
            if ($null -eq $gpuWMax -and $Entry.Lasttest.GpuWMax) {
                $gpuWMax = [double]$Entry.Lasttest.GpuWMax
            }
        }
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

    if (-not $hasDgpu) { $gpuWIdle = 0.0; $gpuWMax = 0.0 }
    elseif ($null -eq $gpuWIdle -and $hasDgpu) { $gpuWIdle = $(if ($isNb) { 5.0 } else { 12.0 }) }

    if ($null -eq $cpuWIdle -and $null -ne $cpuWMax -and $cpuWMax -gt 0) {
        $cpuWIdle = $(if ($isNb) { [math]::Min(10.0, [math]::Max(4.0, [math]::Round($cpuWMax * 0.15, 1))) } else { [math]::Min(25.0, [math]::Max(12.0, [math]::Round($cpuWMax * 0.18, 1))) })
    }

    # Teillast (Alltag & Büro): CPU_Idle + 20 W, GPU_Idle + 15 W + Teillast-Restsystem
    $cpuWPart = $null; $gpuWPart = $null
    if ($null -ne $cpuWIdle) {
        $cpuWPart = [math]::Round($cpuWIdle + 20.0, 1)
    } elseif ($null -ne $cpuWMax) {
        $cpuWPart = [math]::Round($cpuWMax * 0.40, 1)
    }

    if ($hasDgpu) {
        if ($null -ne $gpuWIdle) {
            $gpuWPart = [math]::Round($gpuWIdle + 15.0, 1)
        } elseif ($null -ne $gpuWMax) {
            $gpuWPart = [math]::Round($gpuWMax * 0.25, 1)
        }
    } else {
        $gpuWPart = 0.0
    }

    # Gaming: CPU-Schnitt während Grafik-Benchmark (Fallback: min(CPU_Max * 0.75, 65 W)) + maximale GPU-Last
    $cpuWGaming = $null
    if ($null -ne $cpuWMax -and $cpuWMax -gt 0) {
        $cpuWGaming = [math]::Min($cpuWMax * 0.75, 65.0)
    }

    $pIdle = Get-EstimatedSystemPower -CpuW $cpuWIdle -GpuW $gpuWIdle -IsNotebook:$isNb -GpuName $gpuName -DimmCount $dimmCount -RamOc:$ramOc -Disks $disksList -DiskCount $diskCount -FanCount $fanCount -IsIdle -Stage 'Idle' -PsuWattage $psuWatt -PsuRating $psuRate
    $pPart = Get-EstimatedSystemPower -CpuW $cpuWPart -GpuW $gpuWPart -IsNotebook:$isNb -GpuName $gpuName -DimmCount $dimmCount -RamOc:$ramOc -Disks $disksList -DiskCount $diskCount -FanCount $fanCount -IsTeillast -Stage 'Teillast' -PsuWattage $psuWatt -PsuRating $psuRate
    $pGaming = Get-EstimatedSystemPower -CpuW $cpuWGaming -GpuW $gpuWMax -IsNotebook:$isNb -GpuName $gpuName -DimmCount $dimmCount -RamOc:$ramOc -Disks $disksList -DiskCount $diskCount -FanCount $fanCount -Stage 'Gaming' -PsuWattage $psuWatt -PsuRating $psuRate
    $pLoad = Get-EstimatedSystemPower -CpuW $cpuWMax  -GpuW $gpuWMax  -IsNotebook:$isNb -GpuName $gpuName -DimmCount $dimmCount -RamOc:$ramOc -Disks $disksList -DiskCount $diskCount -DiskLoad -FanCount $fanCount -Stage 'Load' -PsuWattage $psuWatt -PsuRating $psuRate

    # Befund / Warnung bei Überlastung (> 85 %)
    if (-not $Entry -and $pLoad.Verfuegbar -and $pLoad.PsuWattage -gt 0 -and $null -ne $pLoad.LoadPercent -and $pLoad.LoadPercent -gt 85) {
        if (Get-Command Add-Finding -ErrorAction SilentlyContinue) {
            Add-Finding 'WARNUNG' 'Energie' ('Netzteil unter Volllast zu {0:N0} % ausgelastet ({1:N0} W von {2:N0} W Nennleistung). Wenig Puffer für Lastspitzen und Transienten.' -f $pLoad.LoadPercent, $pLoad.P_DC, $pLoad.PsuWattage)
        }
    }

    # Effizienz-Indizes ermitteln
    $eff = [ordered]@{
        CpuMT_PerWatt  = $null
        Gpu_PerWatt    = $null
        System_PerWatt = $null
    }

    $cpuMtScore = 0.0
    $gpuFps = $null
    $gpuPoints = $null
    $overallScore = 0.0

    if ($Entry) {
        if ($Entry.Score -and [double]$Entry.Score -gt 0) {
            $overallScore = [double]$Entry.Score
        } elseif ($Entry.Scores -and $Entry.Scores.Overall -and [double]$Entry.Scores.Overall -gt 0) {
            $overallScore = [double]$Entry.Scores.Overall
        }
        if ($Entry.Werte) {
            $wMt = if ($Entry.Werte -is [System.Collections.IDictionary]) { $Entry.Werte['CPU|MT'] } else { $Entry.Werte.'CPU|MT' }
            if ($null -ne $wMt -and [double]$wMt -gt 0) { $cpuMtScore = [double]$wMt }

            $wRend = if ($Entry.Werte -is [System.Collections.IDictionary]) { $Entry.Werte['GPU|REND'] } else { $Entry.Werte.'GPU|REND' }
            if ($null -ne $wRend -and [double]$wRend -gt 0) { $gpuFps = [double]$wRend }

            $wRpkt = if ($Entry.Werte -is [System.Collections.IDictionary]) { $Entry.Werte['GPU|RPKT'] } else { $Entry.Werte.'GPU|RPKT' }
            if ($null -ne $wRpkt -and [double]$wRpkt -gt 0) { $gpuPoints = [double]$wRpkt }

            if ($overallScore -le 0 -or $overallScore -gt 500) {
                $wSum = 0.0; $logSum = 0.0
                $cPct = if ($cpuMtScore -gt 0) { ($cpuMtScore / 28000.0) * 100.0 } else { 0.0 }
                $gPct = if ($null -ne $gpuFps -and $gpuFps -gt 0) { ($gpuFps / 100.0) * 100.0 } elseif ($null -ne $gpuPoints -and $gpuPoints -gt 0) { ($gpuPoints / 10000.0) * 100.0 } elseif ($Entry.Werte['GPU|VMB']) { ([double]$Entry.Werte['GPU|VMB'] / 300.0) * 100.0 } else { 0.0 }
                $rPct = if ($Entry.Werte['RAM|Lesen']) { ([double]$Entry.Werte['RAM|Lesen'] / 50.0) * 100.0 } else { 0.0 }
                if ($cPct -gt 0) { $logSum += 2.0 * [math]::Log($cPct); $wSum += 2.0 }
                if ($gPct -gt 0) { $logSum += 2.0 * [math]::Log($gPct); $wSum += 2.0 }
                if ($rPct -gt 0) { $logSum += 1.0 * [math]::Log($rPct); $wSum += 1.0 }
                if ($wSum -gt 0) { $overallScore = [int][math]::Round([math]::Exp($logSum / $wSum), 0) }
            }
        }
        if ($Entry.Sensoren -and $Entry.Sensoren.Verbrauch -and $Entry.Sensoren.Verbrauch.Effizienz) {
            $eEff = $Entry.Sensoren.Verbrauch.Effizienz
            if ($null -ne $eEff.CpuMT_PerWatt -and "$($eEff.CpuMT_PerWatt)" -ne '') { $eff.CpuMT_PerWatt = [double]$eEff.CpuMT_PerWatt }
            if ($null -ne $eEff.Gpu_PerWatt -and "$($eEff.Gpu_PerWatt)" -ne '') {
                $oldEff = [double]$eEff.Gpu_PerWatt
                if ($oldEff -le 10.0) { $eff.Gpu_PerWatt = $oldEff }
            }
            if ($null -ne $eEff.System_PerWatt -and "$($eEff.System_PerWatt)" -ne '') { $eff.System_PerWatt = [double]$eEff.System_PerWatt }
        }
    } else {
        if ($script:BenchResults) {
            $mtRow = @($script:BenchResults | Where-Object { $_.RefKey -eq 'CPU|MT' -and $_.Wert -gt 0 }) | Select-Object -First 1
            if ($mtRow) { $cpuMtScore = [double]$mtRow.Wert }
            $rendRow = @($script:BenchResults | Where-Object { $_.RefKey -eq 'GPU|REND' -and $_.Wert -gt 0 }) | Select-Object -First 1
            if ($rendRow) { $gpuFps = [double]$rendRow.Wert }
            $rpktRow = @($script:BenchResults | Where-Object { $_.RefKey -eq 'GPU|RPKT' -and $_.Wert -gt 0 }) | Select-Object -First 1
            if ($rpktRow) { $gpuPoints = [double]$rpktRow.Wert }
        }
        if (Get-Command Get-BenchOverall -ErrorAction SilentlyContinue) {
            $ov = Get-BenchOverall
            if ($null -ne $ov) { $overallScore = [double]$ov }
        }
    }

    if ($null -eq $eff.CpuMT_PerWatt -and $cpuMtScore -gt 0 -and $null -ne $cpuWMax -and $cpuWMax -gt 0) {
        $eff.CpuMT_PerWatt = [math]::Round($cpuMtScore / $cpuWMax, 1)
    }
    if ($null -eq $eff.Gpu_PerWatt -and $null -ne $gpuFps -and $gpuFps -gt 0 -and $null -ne $gpuWMax -and $gpuWMax -gt 0) {
        $eff.Gpu_PerWatt = [math]::Round($gpuFps / $gpuWMax, 2)
    }

    # Gesamtsystem-Effizienz: gewichtetes harmonisches Mittel der gemessenen Teillast-/Benchmark-Effizienzen
    $pCpuLoad = Get-EstimatedSystemPower -CpuW $cpuWMax -GpuW $gpuWIdle -IsNotebook:$isNb -GpuName $gpuName -DimmCount $dimmCount -RamOc:$ramOc -Disks $disksList -DiskCount $diskCount -FanCount $fanCount -Stage 'CpuLoad' -PsuWattage $psuWatt -PsuRating $psuRate
    $pCpuAc = if ($pCpuLoad.Verfuegbar -and $pCpuLoad.P_AC -gt 0) { $pCpuLoad.P_AC } elseif ($null -ne $cpuWMax -and $cpuWMax -gt 0) { $cpuWMax * 1.25 + 25.0 } else { $null }
    $pGpuAc = if ($pGaming.Verfuegbar -and $pGaming.P_AC -gt 0) { $pGaming.P_AC } elseif ($null -ne $gpuWMax -and $gpuWMax -gt 0) { ($gpuWMax + 50.0) * 1.25 + 25.0 } else { $null }

    $effCpuNorm = if ($cpuMtScore -gt 0 -and $null -ne $pCpuAc -and $pCpuAc -gt 0) { (($cpuMtScore / 28000.0) * 100.0 / $pCpuAc) * 100.0 } else { $null }
    $sGpu = if ($null -ne $gpuFps -and $gpuFps -gt 0) { ($gpuFps / 100.0) * 100.0 } elseif ($null -ne $gpuPoints -and $gpuPoints -gt 0) { ($gpuPoints / 10000.0) * 100.0 } elseif ($Entry -and $Entry.Werte -and $Entry.Werte['GPU|VMB'] -gt 0) { ([double]$Entry.Werte['GPU|VMB'] / 300.0) * 100.0 } else { $null }
    $effGpuNorm = if ($null -ne $sGpu -and $sGpu -gt 0 -and $null -ne $pGpuAc -and $pGpuAc -gt 0) { ($sGpu / $pGpuAc) * 100.0 } else { $null }

    $newSysEff = $null
    if ($null -ne $effCpuNorm -and $effCpuNorm -gt 0 -and $null -ne $effGpuNorm -and $effGpuNorm -gt 0) {
        $wCpu = 1.0; $wGpu = 1.0
        $newSysEff = ($wCpu + $wGpu) / (($wCpu / $effCpuNorm) + ($wGpu / $effGpuNorm))
    } elseif ($null -ne $effCpuNorm -and $effCpuNorm -gt 0) {
        $newSysEff = $effCpuNorm
    } elseif ($null -ne $effGpuNorm -and $effGpuNorm -gt 0) {
        $newSysEff = $effGpuNorm
    }

    if ($null -ne $newSysEff -and $newSysEff -gt 0) {
        $eff.System_PerWatt = [math]::Round($newSysEff, 1)
    } elseif ($null -eq $eff.System_PerWatt -and $overallScore -gt 0 -and $pLoad.Verfuegbar -and $pLoad.P_AC -gt 0) {
        $eff.System_PerWatt = [math]::Round(($overallScore / $pLoad.P_AC) * 100.0, 1)
    }

    return [pscustomobject]@{
        IsNotebook  = $isNb
        Leerlauf    = $pIdle
        Teillast    = $pPart
        Gaming      = $pGaming
        Volllast    = $pLoad
        Effizienz   = [pscustomobject]$eff
        PsuWattage  = $psuWatt
        PsuRating   = $psuRate
    }
}

#endregion
