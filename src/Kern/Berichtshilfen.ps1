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
    param([string]$Title, [scriptblock]$Body)
    $script:StepNo++
    $total = [math]::Max((Get-PlannedSteps), $script:StepNo)
    Add-Section $Title ('[{0}/{1}] ' -f $script:StepNo, $total)
    Show-Overall $Title
    Hide-Sub
    $script:CpCurrent = $Title
    Write-Checkpoint 'START' ('[{0}/{1}] {2}' -f $script:StepNo, $total, $Title)
    # Vor Abschnitten, bei denen ein Absturz am ehesten droht, den Zwischenstand sofort sichern (sonst gedrosselt)
    if ($Title -match '^(Lasttest|Benchmark|Test: (CPU|Arbeitsspeicher)|Reparatur|Optimierung)') { Save-Partial -Force }
    # Schneller Modus: exklusive Messungen warten auf die Hintergrundprüfungen
    try { Enter-SectionSchedule $Title } catch { }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { & $Body }
    catch {
        $ln = $(if ($_.InvocationInfo) { $_.InvocationInfo.ScriptLineNumber } else { 0 })
        Add-Line ('  FEHLER in diesem Abschnitt: {0} (Zeile {1})' -f $_.Exception.Message, $ln)
        Write-Warning ('{0}: {1}' -f $Title, $_.Exception.Message)
        Write-Checkpoint 'FEHLER' ('{0}: {1} (Zeile {2})' -f $Title, $_.Exception.Message, $ln)
        # sichtbar in Befunden und Tests, nicht nur in den Details: ein abgebrochener Abschnitt darf nicht wie ein leerer Bericht aussehen
        if ($null -ne $script:SectionErrors) { $script:SectionErrors.Add([pscustomobject]@{ Abschnitt = $Title; Meldung = $_.Exception.Message; Zeile = $ln }) }
        Add-Finding WARNUNG 'Ablauf' ('Abschnitt "{0}" wurde wegen eines Skriptfehlers abgebrochen: {1} (Zeile {2}). Details in Checkpoint.log und in der KI-Datei.' -f $Title, $_.Exception.Message, $ln)
    }
    $sw.Stop()
    $script:Timings.Add([pscustomobject]@{ Abschnitt = $Title; Dauer = ('{0:hh\:mm\:ss}' -f $sw.Elapsed) })
    Write-Checkpoint 'OK' ('{0} ({1:hh\:mm\:ss})' -f $Title, $sw.Elapsed)
    try { Exit-SectionSchedule $Title } catch { }
    Save-Partial
}

# Statische WMI-Klassen (Hardware) nur einmal je Lauf abfragen
$script:CimCache = @{}
function Get-CimCached([string]$Class) {
    if (-not $script:CimCache.ContainsKey($Class)) { $script:CimCache[$Class] = @(Get-CimInstance $Class -ErrorAction SilentlyContinue) }
    return $script:CimCache[$Class]
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
    param([string]$File, [string]$Arguments = '', [int]$TimeoutSec = 600, [Text.Encoding]$Encoding = $script:OemEnc, [string]$Progress = '', [int]$ExpectedSec = 0)
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

