#region ---------- Grundgerüst und Auswahl ----------
$ErrorActionPreference = 'Continue'
$StartTime = Get-Date
$script:Inv = [Globalization.CultureInfo]::InvariantCulture

function Split-List([string]$Text) { @(([string]$Text) -split '[,;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

# Module laut Modulvertrag; unbekannte Namen werden gemeldet und übergangen
$modRes   = Resolve-ModuleList $Module
$modList  = @($modRes.Module | ForEach-Object { $_.ToLowerInvariant() })
if (-not $modList.Count) { $modList = @('diagnose') }
foreach ($u in $modRes.Unbekannt) { Write-Warning ('Unbekanntes Modul wird übergangen: {0}' -f $u) }
$ModDiag  = $modList -contains 'diagnose'
$ModBench = $modList -contains 'benchmark'
$ModLast  = $modList -contains 'lasttest'
$ModRep   = $modList -contains 'wartung' -or $modList -contains 'reparatur'
$ModOpt   = $modList -contains 'optimierung'
# Modul Sensoren = Live-Ansicht (Sondermodus ohne Bericht)
if ($modList -contains 'sensoren') { $SensorLive = $true }
if ($AnalyzeLastRun) { $ModDiag = $true; $ModBench = $false; $ModLast = $false; $ModRep = $false; $ModOpt = $false }

# Diagnose: Profil und Prüfungen
$profKey  = ([string]$DiagProfil).ToLowerInvariant()
$Kurztest = $profKey -like 'funktion*'
$Quick    = $Kurztest -or $profKey -like 'schnell*'
$script:DiagKeys = @((Get-ModuleContract 'Diagnose').Schritte | Where-Object { $_.Typ -eq 'Pruefung' } | ForEach-Object { $_.Key })
$optSel = $(if ($DiagOptionen) { @(Split-List $DiagOptionen) }
            elseif ($Kurztest) { @('Ereignisse', 'Netzwerk', 'RamTest') }
            elseif ($Quick)    { @('Ereignisse', 'Updatesuche', 'Netzwerk', 'RamTest') }
            else               { $script:DiagKeys })
$script:Opt = @{}
foreach ($k in $script:DiagKeys) { $script:Opt[$k] = [bool]($ModDiag -and -not $AnalyzeLastRun -and ($optSel -contains $k)) }
if ($AnalyzeLastRun) { $script:Opt['Ereignisse'] = $true }
if ($Quick) {
    if (-not $PSBoundParameters.ContainsKey('RamTestPercent'))   { $RamTestPercent   = 25 }
    if (-not $PSBoundParameters.ContainsKey('RamTestPasses'))    { $RamTestPasses    = 1 }
}
if ($Kurztest) {
    if (-not $PSBoundParameters.ContainsKey('RamTestPercent'))   { $RamTestPercent   = 5 }
    if (-not $PSBoundParameters.ContainsKey('EventDays'))        { $EventDays        = 3 }
}
$Since = $StartTime.AddDays(-$EventDays)

# Benchmark: Auswahl
$script:BenchSel = @{}
$benchList = @(Split-List $BenchTests)
foreach ($k in @((Get-ModuleContract 'Benchmark').Schritte | ForEach-Object { $_.Key })) { $script:BenchSel[$k] = [bool]($ModBench -and ($benchList -contains $k)) }
$script:BenchDiskSel = @(Split-List $BenchLaufwerke | ForEach-Object { $_ -as [int] } | Where-Object { $null -ne $_ })

# Lasttest: Komponenten und Dauer
$script:LastPlan = [ordered]@{ CPU = $LastCpuMinuten; RAM = $LastRamMinuten; GPU = $LastGpuMinuten; Disk = $LastDiskMinuten }
if ($ModLast -and -not (@($script:LastPlan.Values | Where-Object { $_ -gt 0 }).Count)) { $script:LastPlan.CPU = 15; $script:LastPlan.RAM = 15 }

# Wartung / Reparatur: Auswahl in fester, sinnvoller Reihenfolge (Reihenfolge, Titel und Risikostufe aus dem Modulvertrag)
$script:RepOrder  = @((Get-ModuleContract 'Reparatur').Schritte | ForEach-Object { $_.Key })
$script:RepTitles = [ordered]@{}
$script:RepRisk   = @{}
foreach ($s in (Get-ModuleContract 'Reparatur').Schritte) { $script:RepTitles[$s.Key] = $s.Titel; $script:RepRisk[$s.Key] = $s.Risiko }
$repList = @(Split-List $(if ($Wartung) { $Wartung } else { $Reparaturen }))
$script:RepSel = @($script:RepOrder | Where-Object { $repList -contains $_ })
if ($ModRep -and -not $script:RepSel.Count) { $ModRep = $false }

# Optimierung (ab v2.8): Einträge aus dem Katalog in Katalogreihenfolge
$script:OptSelIds = @(); $script:OptUnknown = @()
if ($ModOpt) {
    $optRes = Resolve-OptSelection $Optimierungen
    $script:OptSelIds = @($optRes.Ids); $script:OptUnknown = @($optRes.Unbekannt)
    foreach ($u in $optRes.Unbekannt) { Write-Warning ('Unbekannter Eintrag der Optimierung wird übergangen: {0}' -f $u) }
    if (-not $script:OptSelIds.Count) { $ModOpt = $false }
}

# Höchste Risikostufe dieses Laufs (steht im Bericht); Benchmark und Lasttest verändern nichts, der PawnIO-Treiber ist ein Eingriff
function Get-RunRisk {
    $lv = @('Lesen')
    if ($ModDiag -and -not $AnalyzeLastRun) {
        if ($ScheduleWindowsMemTest) { $lv += (Get-ModuleStep 'Diagnose' 'Speicherdiagnose').Risiko }
        if ($InstallSmartmontools -and -not $Kurztest) { $lv += (Get-ModuleStep 'Diagnose' 'SmartmontoolsHolen').Risiko }
    }
    if ($ModRep) { $lv += @($script:RepSel | ForEach-Object { $script:RepRisk[$_] }) }
    if ($ModOpt) { $lv += @($script:OptSelIds | ForEach-Object { (Get-OptEntry $_).Risiko }) }
    # PawnIO zählt nur, wenn der Treiber in diesem Lauf tatsächlich installiert wurde
    if ($script:PawnIoInstalledRun) { $lv += (Get-ModuleStep 'Sensoren' 'Treiber').Risiko }
    if ($script:GpuPrefChanged) { $lv += (Get-ModuleStep 'Benchmark' 'GpuWahl').Risiko }
    return (Get-MaxRisk $lv)
}

# Abschnitte abschalten, z. B. wenn der letzte Lauf dabei abgestürzt ist
function Disable-Step([string]$Key) {
    $p = $Key -split ':', 2
    switch ($p[0]) {
        'Opt'   { $script:Opt[$p[1]] = $false }
        'Bench' { $script:BenchSel[$p[1]] = $false }
        'Last'  { foreach ($k in @($script:LastPlan.Keys)) { $script:LastPlan[$k] = 0 } }
        'Rep'   { $script:RepSel = @($script:RepSel | Where-Object { $_ -ne $p[1] }) }
        'Opt8'  { $script:OptSelIds = @($script:OptSelIds | Where-Object { (Get-OptEntry $_).Kat -ne $p[1] }) }
    }
}
# Zahl der Schritte, die dieser Lauf ausführen soll (Prüfungen, Messungen, Lasttest, Reparaturen)
function Get-EnabledStepCount {
    $n = 0
    if ($ModDiag) { $n += @($script:Opt.Keys | Where-Object { $script:Opt[$_] }).Count; if (-not $n) { $n = 1 } }
    if ($ModBench) { $n += @($script:BenchSel.Keys | Where-Object { $script:BenchSel[$_] }).Count }
    if ($ModLast -and @($script:LastPlan.Values | Where-Object { $_ -gt 0 }).Count) { $n++ }
    if ($ModRep) { $n += @($script:RepSel).Count }
    if ($ModOpt) { $n += @($script:OptSelIds | ForEach-Object { (Get-OptEntry $_).Kat } | Select-Object -Unique).Count }
    return $n
}
$script:SkippedByCrash = ''
function Test-StepEnabled([string]$Key) {
    $p = $Key -split ':', 2
    switch ($p[0]) {
        'Opt'   { return [bool]$script:Opt[$p[1]] }
        'Bench' { return [bool]$script:BenchSel[$p[1]] }
        'Last'  { return [bool](@($script:LastPlan.Values | Where-Object { $_ -gt 0 }).Count) }
        'Rep'   { return ($script:RepSel -contains $p[1]) }
        'Opt8'  { return [bool]@($script:OptSelIds | Where-Object { (Get-OptEntry $_).Kat -eq $p[1] }).Count }
    }
    return $false
}

if (-not $ImportOrdner -and -not $Vergleich -and -not $Rueckgaengig -and -not $SensorLive -and -not $SensorWerkzeugeHolen -and -not $SensorAufraeumen -and -not $OptimierungZustand -and -not $OptWerkzeugeHolen -and -not $SoftwareInstallieren -and -not $Dashboard -and -not $DashboardExport -and -not $DashboardSysteme) {
    # Berichte landen ausschließlich im Datenordner neben dem Programm (z. B. auf dem USB-Stick)
    if (-not $OutputDir) {
        $base = $(if ($script:DataDir) { Join-Path $script:DataDir 'Berichte' } else { Join-Path $env:TEMP 'LeosMinibench-Berichte' })
        $OutputDir = Join-Path $base ('{0}_{1}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmm'))
        if (Test-Path -LiteralPath $OutputDir) { $OutputDir += (Get-Date -Format '_ss') }
    }
    New-Item -ItemType Directory -Path $OutputDir -Force -ErrorAction Stop | Out-Null
    $script:WriteStart = Get-VolumeWriteCounter $OutputDir
    # Ab v2.6 im lokalen TEMP (Stick schonen); ohne beschreibbares TEMP wie bisher im Berichtsordner
    $script:WorkDir = New-RunWorkDir $OutputDir
    $RawDir = $(if ($script:WorkDir) { Join-Path $script:WorkDir 'Anhang' } else { Join-Path $OutputDir 'Anhang' })
    New-Item -ItemType Directory -Path $RawDir -Force | Out-Null
    try { $script:GuiLog = New-Object IO.StreamWriter((Join-Path $RawDir 'Konsole.log'), $false, (New-Object Text.UTF8Encoding($true))); $script:GuiLog.AutoFlush = $true } catch { }
    # @@ORDNER|Berichtsordner|Arbeitsordner (ab v2.65): Endet der Lauf ohne Bericht oder wird er abgebrochen, legt die
    # Oberfläche ihr Protokoll und die Rohdaten aus dem Arbeitsordner in den Berichtsordner (sonst bleibt er leer)
    Send-GuiEvent 'ORDNER' $OutputDir $(if ($script:WorkDir) { $script:WorkDir } else { '' })
}

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

# Konsolenprogramme schreiben in der OEM-Codepage (850), unabhängig von der Konsole des Arbeitsprozesses
try   { $script:OemEnc = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) } catch { $script:OemEnc = [Text.Encoding]::Default }


$script:Report      = New-Object System.Text.StringBuilder
$script:Findings    = [System.Collections.Generic.List[object]]::new()
$script:Timings     = [System.Collections.Generic.List[object]]::new()
$script:TestResults = [System.Collections.Generic.List[object]]::new()
$script:Facts       = [ordered]@{}
function Add-TestResult([string]$Name, [string]$Status, [string]$Detail = '') {
    $script:TestResults.Add([pscustomobject]@{ Test = $Name; Ergebnis = $Status; Details = $Detail })
    Send-GuiEvent 'TEST' $Name $Status $Detail
}
$script:BenchResults  = [System.Collections.Generic.List[object]]::new()
$script:BenchNew      = New-Object System.Collections.ArrayList
$script:BenchHistory  = @()
$script:LoadSeries    = @()
# ab v2.7: Sensoren während des Benchmarks (Messpunkte und Kennzahlen je Abschnitt)
$script:BenchSeries     = @()
$script:BenchSensorRows = @()
$script:LoadSummary   = ''
$script:LoadParts     = [System.Collections.Generic.List[object]]::new()
$script:LoadThrottle  = $null
$script:LoadAbort     = $null
$script:LoadLimits    = $null
$script:PawnIoInstalledRun = $false
$script:BatteryInfo   = @()
$script:BenchRefRows  = @()
$script:BenchStartLoad = 0
$script:GpuPrefChanged = $false
$script:BenchGpuMeasured = ''
$script:IntegrityInfo = $null
$script:Stability     = $null
$script:SectionErrors = [System.Collections.Generic.List[object]]::new()
$script:RepairLog     = [System.Collections.Generic.List[object]]::new()
$script:RestartNeeded = [System.Collections.Generic.List[string]]::new()
$script:CmpSystems    = @()
$script:CmpRows       = @()
$script:DbSaved       = ''
$script:InstallInfo   = $null
$script:RamProfileActive = $false
$script:UserNames     = @()
$script:DiskNames     = $null
try { $script:FindKeys = New-Object 'System.Collections.Generic.HashSet[string]' } catch { $script:FindKeys = $null }

# Werte, die in der KI-Datei unkenntlich gemacht werden (Seriennummern, Benutzernamen, MAC-Adressen usw.)
$script:Private = New-Object 'System.Collections.Generic.Dictionary[string,string]'
function Add-Private([string]$Value, [string]$Kind) {
    if (-not $Value) { return }
    $v = $Value.Trim()
    if ($v.Length -lt 4 -or $v -match '^(0+|To be filled.*|Default string|System Serial Number|None|N/A|Not Specified|Unknown|\s*)$') { return }
    if ($script:Private.ContainsKey($v)) { return }
    $n = @($script:Private.Values | Where-Object { $_ -like "<$Kind-*" }).Count + 1
    $script:Private[$v] = '<{0}-{1}>' -f $Kind, $n
}

function Get-ModeLabel {
    if ($AnalyzeLastRun) { return 'Nur Absturzanalyse' }
    $p = @()
    if ($ModDiag) { $p += ('Diagnose ({0})' -f $(if ($Kurztest) { 'Funktionstest' } elseif ($DiagOptionen -and $profKey -like 'benutzer*') { 'benutzerdefiniert' } elseif ($Quick) { 'schnell' } else { 'vollständig' })) }
    if ($ModBench) { $p += ('Benchmark ({0}{1})' -f ((@($script:BenchSel.Keys | Where-Object { $script:BenchSel[$_] } | Sort-Object) -join ', ')), $(if ($BenchmarkKurz) { ', kurz' } else { '' })) }
    if ($ModLast) { $p += ('Lasttest ({0})' -f ((@($script:LastPlan.Keys | Where-Object { $script:LastPlan[$_] -gt 0 } | ForEach-Object { '{0} {1} Min.' -f $_, $script:LastPlan[$_] }) -join ', '))) }
    if ($ModRep) { $p += ('Reparatur ({0})' -f ($script:RepSel -join ', ')) }
    if ($ModOpt) { $p += ('Optimierung ({0} Einträge)' -f $script:OptSelIds.Count) }
    $t = ($p -join ' + ')
    if ($SchnellerModus -and $ModDiag) { $t += ', schneller Modus' }
    return $t
}

$script:StepNo = 0
function Get-PlannedSteps {
    if ($AnalyzeLastRun) { return 3 }
    $n = 0
    if ($ModDiag) {
        $n += 16
        foreach ($k in 'Integritaet', 'Netzwerk', 'RamTest') { if ($script:Opt[$k]) { $n++ } }
        if ($script:Opt['Defender'] -and $script:DefenderActive -ne $false) { $n++ }
        $smartPossible = $script:Smartctl -and ($null -eq $script:SmartDevices -or @($script:SmartDevices).Count -gt 0)
        if ($script:Opt['SmartLang'] -and $smartPossible) { $n += 2 }
        if ($script:Opt['Ereignisse']) { $n += 2 }
    }
    if (($ModBench -or $ModLast) -and -not $ModDiag) { $n++ }
    if ($ModBench) { $n += @($script:BenchSel.Keys | Where-Object { $script:BenchSel[$_] }).Count + 1 }
    if ($ModLast) { $n++ }
    if ($ModRep) { $n += $script:RepSel.Count; if (-not $OhneWiederherstellungspunkt) { $n++ } }
    if ($ModOpt) { $n += @($script:OptSelIds | ForEach-Object { (Get-OptEntry $_).Kat } | Select-Object -Unique).Count + 2; if (-not $OptOhneWiederherstellungspunkt) { $n++ } }
    return $n + 2
}

function Show-Overall([string]$Status) {
    $total = [math]::Max((Get-PlannedSteps), $script:StepNo)
    Send-GuiEvent 'STEP' $script:StepNo $total $Status
}

function Show-Sub([string]$Activity, [string]$Status = ' ', [int]$Percent = -1) {
    if (-not $Status) { $Status = ' ' }
    # schneller Modus: fertige Hintergrundprüfungen abholen und wartende starten (höchstens alle 500 ms)
    if ($script:BgJobs -and $script:BgJobs.Count) { try { Update-BgJobs } catch { } }
    Write-Heartbeat ('{0} | {1}' -f $Activity, $Status.Trim())
    Send-GuiEvent 'SUB' $Percent $Activity $Status
}

function Hide-Sub { Send-GuiEvent 'SUB' '-9' '' '' }

function Wait-JobWithProgress($Job, [string]$Activity, [int]$ExpectedSec = 0, [int]$TimeoutSec = 3600) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($Job.State -in 'NotStarted', 'Running') {
        if (Test-SkipRequested) {
            Stop-Job $Job -ErrorAction SilentlyContinue
            throw (New-Object System.OperationCanceledException 'Vom Benutzer übersprungen')
        }
        $st = 'läuft seit {0:hh\:mm\:ss}' -f $sw.Elapsed
        if ($ExpectedSec -gt 0) { Show-Sub $Activity ($st + ('   (üblich: ca. {0} Min.)' -f [math]::Ceiling($ExpectedSec / 60))) ([int]([math]::Min(99.0, $sw.Elapsed.TotalSeconds / $ExpectedSec * 100.0))) }
        else { Show-Sub $Activity $st }
        if ($sw.Elapsed.TotalSeconds -ge $TimeoutSec) { Stop-Job $Job -ErrorAction SilentlyContinue; break }
        Start-Sleep -Milliseconds 500
    }
    Hide-Sub
    return ($Job.State -eq 'Completed')
}

$FullLanguage       = $ExecutionContext.SessionState.LanguageMode -eq 'FullLanguage'
$ProgressPreference = 'SilentlyContinue'

function Get-Median($Values) {
    $v = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
    if (-not $v.Count) { return $null }
    if ($v.Count % 2) { return $v[[int][math]::Floor($v.Count / 2)] }
    return ($v[$v.Count / 2 - 1] + $v[$v.Count / 2]) / 2
}

# CPU-Messpunkt: Takt wie im Task-Manager (Nenntakt x % Prozessorleistung / 100), Last, Frequenzgrenze, ACPI-Temperatur.
# Bevorzugt über PDH (DiagPdh, Mittel seit dem letzten Aufruf wie im Task-Manager), sonst über die WMI-Leistungsdaten.
function Get-CpuSample {
    $tz = @(Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue)
    $temp = $null
    if ($tz.Count) {
        $vals = $tz | ForEach-Object { if ($_.HighPrecisionTemperature) { $_.HighPrecisionTemperature / 10 - 273.15 } elseif ($_.Temperature) { $_.Temperature - 273.15 } } | Where-Object { $_ -gt 0 -and $_ -lt 130 }
        if ($vals) { $temp = [math]::Round(($vals | Measure-Object -Maximum).Maximum, 1) }
    }
    $p = $null
    if ('DiagPdh' -as [type]) { try { $p = [DiagPdh]::Sample() } catch { $p = $null } }
    if ($p -and -not [double]::IsNaN($p[0]) -and $p[0] -gt 0) {
        $last = $(if (-not [double]::IsNaN($p[3])) { [int][math]::Round($p[3]) } else { 0 })
        $maxPerf = $(if (-not [double]::IsNaN($p[5])) { $p[5] } else { $p[1] })
        return [pscustomobject]@{
            Last = $last; Leistung = [int][math]::Round($p[1]); MaxLeistung = [int][math]::Round($maxPerf)
            MaxFreq = $(if (-not [double]::IsNaN($p[4])) { [int][math]::Round($p[4]) } else { 0 }); MHz = [int]$p[0]
            MaxMHz = [int]($p[2] * $maxPerf / 100); Temp = $temp; Quelle = 'PDH'
        }
    }
    $all  = @(Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction SilentlyContinue)
    $pi   = $all | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
    $core = @($all | Where-Object { $_.Name -notmatch '_Total' })
    $maxPerf = 0
    if ($core.Count) { $maxPerf = [int](($core | Measure-Object PercentProcessorPerformance -Maximum).Maximum) }
    $freq = 0; if ($pi) { $freq = [double]$pi.ProcessorFrequency }
    [pscustomobject]@{
        Last = [int]$pi.PercentProcessorTime; Leistung = [int]$pi.PercentProcessorPerformance; MaxLeistung = $maxPerf
        MaxFreq = [int]$pi.PercentofMaximumFrequency; MHz = [int]($freq * [int]$pi.PercentProcessorPerformance / 100)
        MaxMHz = [int]($freq * $maxPerf / 100); Temp = $temp; Quelle = 'WMI'
    }
}

function Wait-TaskProgress($Task, [string]$Activity, [string]$Status, [int]$ExpectedMs, [switch]$Sample) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $samples = New-Object System.Collections.ArrayList
    while (-not $Task.IsCompleted) {
        if (Test-SkipRequested) {
            throw (New-Object System.OperationCanceledException 'Vom Benutzer übersprungen')
        }
        Show-Sub $Activity $Status ([int][math]::Min(99.0, [double]$sw.ElapsedMilliseconds * 100.0 / [math]::Max(1.0, [double]$ExpectedMs)))
        $cs = $null
        if ($Sample -and $sw.ElapsedMilliseconds -gt 800) { $cs = Get-CpuSample; [void]$samples.Add($cs) }
        # ab v2.7: Sensoren des Benchmarks in der Wartepause (nur wenn Start-BenchSensors lief, höchstens alle 2 s)
        if ($script:BenchSens -and $script:BenchSens.On -and $sw.ElapsedMilliseconds -gt 800) { Add-BenchSensorSample $cs }
        Start-Sleep -Milliseconds 300
    }
    Hide-Sub
    return , $samples
}

function Get-PcieLink([string]$InstanceId) {
    if (-not $InstanceId) { return $null }
    try {
        $id = $InstanceId
        for ($i = 0; $i -lt 5 -and $id -and $id -notlike 'PCI\*'; $i++) {
            $id = [string](Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop).Data
        }
        if (-not $id -or $id -notlike 'PCI\*') { return $null }
        $p = @{}
        Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_PciDevice_CurrentLinkSpeed', 'DEVPKEY_PciDevice_MaxLinkSpeed', 'DEVPKEY_PciDevice_CurrentLinkWidth', 'DEVPKEY_PciDevice_MaxLinkWidth' -ErrorAction Stop |
            ForEach-Object { $p[$_.KeyName] = $_.Data }
        $o = [pscustomobject]@{
            Id = $id
            GenNow = [int]$p['DEVPKEY_PciDevice_CurrentLinkSpeed']; GenMax = [int]$p['DEVPKEY_PciDevice_MaxLinkSpeed']
            WidthNow = [int]$p['DEVPKEY_PciDevice_CurrentLinkWidth']; WidthMax = [int]$p['DEVPKEY_PciDevice_MaxLinkWidth']
        }
        if ($o.GenNow -lt 1 -or $o.GenNow -gt 7 -or $o.WidthNow -lt 1) { return $null }
        return $o
    } catch { return $null }
}

function Format-Pcie($Link, [switch]$Max) {
    if (-not $Link) { return '' }
    if ($Max) { return ('PCIe {0}.0 x{1}' -f $Link.GenMax, $Link.WidthMax) }
    return ('PCIe {0}.0 x{1}' -f $Link.GenNow, $Link.WidthNow)
}

function Write-BenchError([string]$Part, $Err) {
    $msg = $(if ($Err.Exception) { $Err.Exception.Message } else { [string]$Err })
    $line = $(if ($Err.InvocationInfo) { $Err.InvocationInfo.ScriptLineNumber } else { '?' })
    Add-Line ('  {0}: Messung fehlgeschlagen (Zeile {1}): {2}' -f $Part, $line, $msg)
    Add-Finding INFO 'Leistung' ('Benchmark {0} konnte nicht ausgeführt werden: {1}' -f $Part, $msg)
    Write-Checkpoint 'FEHLER' ('Benchmark {0}: {1} (Zeile {2})' -f $Part, $msg, $line)
}

function Add-BenchResult {
    param([string]$Komponente, [string]$Messung, [double]$Wert, [string]$Einheit, [string]$Anzeige, $Index = $null,
          [string]$Status = 'OK', [string]$Hinweis = '', [string]$Key = '', [switch]$LowerBetter,
          [string]$Gruppe = '', [string]$RefKey = '', [switch]$NoGui, [switch]$PassThru)
    if (-not $Gruppe) { $Gruppe = $(if ($Komponente -eq 'Datenträger') { 'Laufwerke' } else { $Komponente }) }
    $cmp = ''
    if ($Key) {
        $prev = @($script:BenchHistory | ForEach-Object { if ([bool]$_.Kurz -eq [bool]$BenchmarkKurz) { $_.Werte } } |
                  Where-Object { $_.Key -eq $Key } | ForEach-Object { [double]$_.Wert } | Select-Object -Last 5)
        if ($prev.Count) {
            $med = Get-Median $prev
            if ($med -gt 0) {
                $d = ($Wert - $med) / $med * 100
                if ($LowerBetter) { $d = -$d }
                $cmp = $(if ($prev.Count -eq 1) { '{0:+0;-0;0} % zum letzten Lauf' -f $d } else { '{0:+0;-0;0} % zu {1} Läufen' -f $d, $prev.Count })
                if ($d -le -15) {
                    # Lag beim Start schon Grundlast an, ist die Abweichung wahrscheinlich daher: nur Hinweis
                    if ($script:BenchStartLoad -gt 15) {
                        Add-Finding INFO 'Leistung' ('{0} {1}: {2:N0} % schlechter als bei früheren Läufen auf diesem PC ({3} statt Median {4:N1} {5}), vermutlich wegen {6} % Grundlast beim Start. Messung ohne laufende Programme wiederholen.' -f $Komponente, $Messung, [math]::Abs($d), $Anzeige, $med, $Einheit, $script:BenchStartLoad)
                        if ($Status -eq 'OK') { $Status = 'Info' }
                    } else {
                        Add-Finding WARNUNG 'Leistung' ('{0} {1}: {2:N0} % schlechter als bei früheren Läufen auf diesem PC ({3} statt Median {4:N1} {5}).' -f $Komponente, $Messung, [math]::Abs($d), $Anzeige, $med, $Einheit)
                        if ($Status -eq 'OK' -or $Status -eq 'Info') { $Status = 'Warnung' }
                    }
                }
            }
        }
        [void]$script:BenchNew.Add([pscustomobject]@{ Key = $Key; Wert = [math]::Round($Wert, 2) })
    }
    $refPct = Get-RefPct $RefKey $Wert -LowerBetter:$LowerBetter
    $refTxt = $(if ($null -ne $refPct) { '{0} %' -f $refPct } else { '' })
    $o = [pscustomobject][ordered]@{ Gruppe = $Gruppe; Komponente = $Komponente; Messung = $Messung; Wert = $Wert; Einheit = $Einheit; Anzeige = $Anzeige; Index = $Index
        Status = $Status; Referenz = $refTxt; RefPct = $refPct; RefKey = $RefKey; Vergleich = $cmp; Hinweis = $Hinweis }
    $script:BenchResults.Add($o)
    # WinSAT-Werte zeichnet die Oberfläche auf der Skala 1,0 bis 9,9 (Kennung W)
    $guiIdx = $(if ($Gruppe -eq 'WinSAT' -and $Wert -gt 0) { 'W' + $Wert.ToString('0.0', $script:Inv) } elseif ($null -ne $Index) { $Index } else { '' })
    if (-not $NoGui) { Send-GuiEvent 'BENCH' $Status $Komponente $Messung $Anzeige $guiIdx $cmp $Hinweis $refTxt $Gruppe }
    if ($PassThru) { return $o }
}


