# Sensoren: Zugriff auf LibreHardwareMonitor über Reflexion (mit nachgebauter Bibliothek), Zeitlimits und verspätete
# Abfragen, Leitwerte, Plausibilität, Abbruchschwelle, Drosselnachweis, Ersatzwerte ohne LibreHardwareMonitor
# (Grafiktreiber, Energiezähler), ARM64-Erkennung, zwischengespeicherte CIM-Abfragen, Werkzeuge mit festen Prüfsummen
# und der Lebenszyklus des PawnIO-Treibers (mit Attrappen).
#
# Kern\Sensoren.cs wird je Testlauf höchstens einmal übersetzt (Get-KernUebersetzung wie in Messung.Tests.ps1,
# gemeinsames Ergebnis in einer globalen Variablen): Windows im Kindprozess (Windows PowerShell 5.1, C# 5), sonst mit
# mcs -langversion:5. Die Bibliothek liegt in einem Ordner je Testprozess unter TEMP\LeosMinibench-Tests-Kern.
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')

    # Arbeitsordner dieses Testprozesses für übersetzte Bibliotheken (gleiche Fassung wie in Messung.Tests.ps1)
    function Get-KernOrdner {
        if ($global:MinibenchKernOrdner -and (Test-Path -LiteralPath $global:MinibenchKernOrdner)) { return $global:MinibenchKernOrdner }
        $base = Join-Path ([IO.Path]::GetTempPath()) 'LeosMinibench-Tests-Kern'
        foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)) {
            $p = 0
            if ($d.Name -match '^(\d+)_') { $p = [int]$Matches[1] }
            if ($p -eq $PID) { continue }
            if ($p -gt 0 -and (Get-Process -Id $p -ErrorAction SilentlyContinue)) { continue }
            Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        $dir = Join-Path $base ('{0}_{1}' -f $PID, [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $global:MinibenchKernOrdner = $dir
        return $dir
    }

    # Eine C#-Datei aus src als Bibliothek übersetzen, je Testlauf einmal (gleiche Fassung wie in Messung.Tests.ps1)
    function Get-KernUebersetzung([string]$Datei) {
        if (-not $global:MinibenchKernUebersetzung) { $global:MinibenchKernUebersetzung = @{} }
        if ($global:MinibenchKernUebersetzung.ContainsKey($Datei)) { return $global:MinibenchKernUebersetzung[$Datei] }
        $src = Join-Path $global:MinibenchSrcRoot $Datei
        $dll = Join-Path (Get-KernOrdner) ([IO.Path]::GetFileNameWithoutExtension($Datei) + '.dll')
        $winforms = ([IO.File]::ReadAllText($src, [Text.Encoding]::UTF8) -match 'using System\.Windows\.Forms;')
        $res = [pscustomobject]@{ Datei = $Datei; Ok = $false; Dll = $dll; Compiler = ''; Meldung = '' }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        if (Test-IstWindows) {
            $res.Compiler = 'Add-Type (.NET Framework, C# 5, Kindprozess)'
            $refs = $(if ($winforms) { 'Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $p.ReferencedAssemblies = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location); ' } else { '' })
            $code = ('$p = @{{ TypeDefinition = [IO.File]::ReadAllText(''{0}'', [Text.Encoding]::UTF8); OutputAssembly = ''{1}''; OutputType = ''Library''; IgnoreWarnings = $true; ErrorAction = ''Stop'' }}; ' -f $src.Replace("'", "''"), $dll.Replace("'", "''")) +
                $refs + 'try { Add-Type @p; exit 0 } catch { Write-Output $_.Exception.Message; exit 1 }'
            $msg = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $code
            $res.Ok = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $dll)); $res.Meldung = (@($msg) -join ' ')
        } elseif (Get-Command mcs -ErrorAction SilentlyContinue) {
            $res.Compiler = 'mcs -langversion:5'
            $r = @(); if ($winforms) { $r = @('-r:System.Windows.Forms.dll', '-r:System.Drawing.dll') }
            $msg = & mcs -langversion:5 -target:library -nowarn:414,169,649,0219,1635 @r ('-out:' + $dll) $src 2>&1
            $res.Ok = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $dll)); $res.Meldung = (@($msg | Where-Object { "$_" -match 'error' }) -join ' ')
        } else {
            $res.Meldung = 'kein C#-5-Compiler verfügbar (Windows PowerShell oder mcs)'
        }
        Write-Host ('    {0} übersetzt in {1:N1} s ({2}): {3}' -f $Datei, $sw.Elapsed.TotalSeconds, $res.Compiler, $(if ($res.Ok) { 'fehlerfrei' } else { 'FEHLER' }))
        $global:MinibenchKernUebersetzung[$Datei] = $res
        return $res
    }

    # DiagSensors, DiagPdh und DiagGpuKmt
    $script:SensorenCs = Get-KernUebersetzung 'Kern/Sensoren.cs'
    if ($script:SensorenCs.Ok -and -not ('DiagSensors' -as [type])) { Add-Type -Path $script:SensorenCs.Dll }

    Import-MinibenchTestModule -Parts 'Kern\Werkzeuge.ps1', 'Kern\Sensoren.ps1' -Functions 'Get-SafeName', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent', 'Get-CimCached' -Setup @'
$script:CimCache = @{}
$script:TestFindings = New-Object System.Collections.Generic.List[object]
function Add-Finding { param([string]$Level, [string]$Area, [string]$Text) $script:TestFindings.Add([pscustomobject]@{ Stufe = $Level; Bereich = $Area; Befund = $Text }) }
function Write-Checkpoint { param([string]$Kind, [string]$Text) }
function Add-ChangeRecord { param([string]$Modul, [string]$Schritt, [string]$Titel, [string]$Risiko, [string]$Art, [string]$Ziel, [string]$Vorher = '', [string]$Nachher = '', $Daten = $null, [string]$Gegenbefehl = '', [switch]$NurHinweis)
    $script:TestChanges += [pscustomobject]@{ Titel = $Titel; Risiko = $Risiko; NurHinweis = [bool]$NurHinweis } }
function Invoke-External { param([string]$File, [string]$Arguments = '', [int]$TimeoutSec = 600, $Encoding = $null, [string]$Progress = '', [int]$ExpectedSec = 0) [pscustomobject]@{ ExitCode = 0; Output = ''; Error = ''; TimedOut = $false } }
function Get-CpuSample { [pscustomobject]@{ Last = 5; Leistung = 100; MaxLeistung = 100; MaxFreq = 100; MHz = 3600; MaxMHz = 3600; Temp = $null } }
$script:TestChanges = @()
'@
    function New-DataDir {
        $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $d 'Tools') -Force | Out-Null
        Set-ModuleVar 'DataDir' $d
        Set-ModuleVar 'TestChanges' @()
        Set-ModuleVar 'PawnIoByUs' $false
        Set-ModuleVar 'PawnIoInstalledRun' $false
        Set-ModuleVar 'Sens' $null
        & (Get-Module MinibenchTest) { $script:ToolIssues.Clear(); $script:SensorNotes.Clear() }
        return $d
    }
    function New-Rd([string]$Gruppe, [string]$Art, [string]$Name, $Wert, [string]$Geraet = 'Gerät', [string]$Quelle = 'LHM', $TjMax = $null) {
        MinibenchTest\New-SensorReading ('{0}/{1}/{2}/{3}' -f $Quelle, $Gruppe, $Art, $Name) $Quelle $Gruppe $Geraet $Art $Name '' $Wert '' $TjMax
    }
    # Verlauf für den Drosselnachweis: n Punkte im Abstand von 3 s, Werte als Skriptblock je Index
    function New-Series([int]$N, [scriptblock]$Mhz, [scriptblock]$Temp = { $null }, [scriptblock]$Watt = { $null }, [string]$Quelle = 'LHM', [scriptblock]$Win = $null) {
        @(for ($i = 0; $i -lt $N; $i++) {
            $c = & $Mhz $i
            [pscustomobject]@{ T = 12 + 3 * $i; MHz = $(if ($Win) { & $Win $i } else { $c }); CpuMHz = $c; CpuTemp = (& $Temp $i); CpuTempQ = $Quelle; CpuW = (& $Watt $i); MaxFreq = 100; Cpu = $true; Last = 100 }
        })
    }
}

Describe 'LibreHardwareMonitor über Reflexion (nachgebaute Bibliothek)' {
    BeforeAll {
        $fake = @'
using System;
using System.Collections.Generic;
namespace LibreHardwareMonitor.Hardware {
    public enum SensorType { Voltage, Current, Power, Clock, Temperature, Load, Frequency, Fan, Flow, Control, Level, Factor, Data, SmallData, Throughput }
    public enum HardwareType { Motherboard, SuperIO, Cpu, Memory, GpuNvidia, GpuAmd, GpuIntel, Storage, Network, Cooler, EmbeddedController, Psu, Battery, PowerMonitor }
    public class Identifier { string s; public Identifier(string s) { this.s = s; } public override string ToString() { return s; } }
    public interface IParameter { string Name { get; } float Value { get; } }
    public interface ISensor { string Name { get; } SensorType SensorType { get; } float? Value { get; } Identifier Identifier { get; } IReadOnlyList<IParameter> Parameters { get; } }
    public interface IHardware { string Name { get; } HardwareType HardwareType { get; } ISensor[] Sensors { get; } IHardware[] SubHardware { get; } void Update(); }
    public class P : IParameter { public string Name { get; set; } public float Value { get; set; } }
    public class S : ISensor { public string Name { get; set; } public SensorType SensorType { get; set; } public float? Value { get; set; } public Identifier Identifier { get; set; } public IReadOnlyList<IParameter> Parameters { get; set; } }
    public class H : IHardware {
        public string Name { get; set; } public HardwareType HardwareType { get; set; } public ISensor[] Sensors { get; set; } public IHardware[] SubHardware { get; set; }
        public static int Delay;
        public int OwnDelay;
        public int Updates; public bool Fail; public void Update() { Updates++; if (Delay + OwnDelay > 0) System.Threading.Thread.Sleep(Delay + OwnDelay); if (Fail) throw new InvalidOperationException("kaputt"); }
    }
    public class Computer {
        public static int Opened, Closed;
        public bool IsCpuEnabled { get; set; } public bool IsGpuEnabled { get; set; } public bool IsMotherboardEnabled { get; set; } public bool IsMemoryEnabled { get; set; }
        public bool IsStorageEnabled { get; set; } public bool IsBatteryEnabled { get; set; } public bool IsControllerEnabled { get; set; } public bool IsNetworkEnabled { get; set; } public bool IsPsuEnabled { get; set; }
        public static bool LastStorage;
        public static int StorageDelay;
        List<IHardware> hw = new List<IHardware>();
        public IList<IHardware> Hardware { get { return hw; } }
        static S Sn(string n, SensorType t, float? v, string id, float tj) {
            S s = new S(); s.Name = n; s.SensorType = t; s.Value = v; s.Identifier = new Identifier(id);
            List<IParameter> ps = new List<IParameter>(); if (tj > 0) { P p = new P(); p.Name = "TjMax [°C]"; p.Value = tj; ps.Add(p); P q = new P(); q.Name = "TSlope [°C]"; q.Value = 1; ps.Add(q); }
            s.Parameters = ps; return s;
        }
        public void Open() {
            Opened++; LastStorage = IsStorageEnabled;
            H cpu = new H(); cpu.Name = "Intel Core i7-12700"; cpu.HardwareType = HardwareType.Cpu; cpu.SubHardware = new IHardware[0];
            cpu.Sensors = new ISensor[] { Sn("CPU Package", SensorType.Temperature, 61.5f, "/intelcpu/0/temperature/13", 100), Sn("P-Core #1", SensorType.Clock, 4700, "/intelcpu/0/clock/1", 0),
                Sn("CPU Package", SensorType.Power, 88.25f, "/intelcpu/0/power/0", 0), Sn("CPU Total", SensorType.Load, 97, "/intelcpu/0/load/0", 0), Sn("Bus Speed", SensorType.Clock, null, "/intelcpu/0/clock/0", 0),
                Sn("CPU Core", SensorType.Factor, 47, "/intelcpu/0/factor/0", 0), Sn("Wert", SensorType.Data, 1, "/intelcpu/0/data/0", 0) };
            H sio = new H(); sio.Name = "Nuvoton NCT6798D"; sio.HardwareType = HardwareType.SuperIO; sio.SubHardware = new IHardware[0];
            sio.Sensors = new ISensor[] { Sn("CPU Fan", SensorType.Fan, 1180, "/lpc/nct6798d/0/fan/1", 0), Sn("+12V", SensorType.Voltage, 12.096f, "/lpc/nct6798d/0/voltage/2", 0) };
            H mb = new H(); mb.Name = "ASUS PRIME Z690-P"; mb.HardwareType = HardwareType.Motherboard; mb.Sensors = new ISensor[0]; mb.SubHardware = new IHardware[] { sio };
            H bad = new H(); bad.Name = "Defekt"; bad.HardwareType = HardwareType.GpuIntel; bad.Fail = true; bad.SubHardware = new IHardware[0];
            bad.Sensors = new ISensor[] { Sn("GPU Core", SensorType.Temperature, 40, "/gpu-intel/0/temperature/0", 0) };
            H net = new H(); net.Name = "Ethernet"; net.HardwareType = HardwareType.Network; net.SubHardware = new IHardware[0];
            net.Sensors = new ISensor[] { Sn("Upload Speed", SensorType.Throughput, 5, "/nic/0/throughput/0", 0) };
            hw.Add(cpu); hw.Add(mb); hw.Add(bad); hw.Add(net);
            if (IsStorageEnabled) {
                H ssd = new H(); ssd.Name = "Samsung SSD 980 1TB"; ssd.HardwareType = HardwareType.Storage; ssd.SubHardware = new IHardware[0]; ssd.OwnDelay = StorageDelay;
                ssd.Sensors = new ISensor[] { Sn("Composite Temperature", SensorType.Temperature, 41, "/nvme/0/temperature/0", 0) };
                hw.Add(ssd);
            }
        }
        public void Close() { Closed++; }
    }
}
namespace LibreHardwareMonitor.PawnIo { public class PawnIo { public static bool IsInstalled { get { return true; } } public static Version Version { get { return new Version(2, 2, 0, 0); } } } }
'@
        # nicht in TestDrive: Windows sperrt eine geladene DLL bis zum Prozessende, Pester könnte TestDrive nicht löschen.
        # Eigener Ordner dieses Testprozesses (Get-KernOrdner); Ordner beendeter Testläufe entfernt der nächste Lauf.
        $script:fakeDir = Join-Path (Get-KernOrdner) ('LHM_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $script:fakeDir -Force | Out-Null
        $script:fakeDll = Join-Path $script:fakeDir 'LibreHardwareMonitorLib.dll'
        Add-Type -TypeDefinition $fake -OutputAssembly $script:fakeDll -OutputType Library
        if (-not ('DiagSensors' -as [type])) { throw ('Sensoren.cs nicht geladen: ' + $script:SensorenCs.Meldung) }
    }
    It 'Grundwerte: alte Werte höchstens 10 s, Ausfall erst nach 30 s, Datenträger höchstens alle 30 s und ohne Warten' {
        [DiagSensors]::StaleMaxMs | Should -Be 10000
        [DiagSensors]::HangAfterMs | Should -Be 30000
        [DiagSensors]::StorageIntervalMs | Should -Be 30000
        [DiagSensors]::StorageWaitMs | Should -Be 0
    }
    It 'das Skript ruft die Bibliothek nur mit Zeitlimit auf' {
        $ps = Get-PartText 'Kern\Sensoren.ps1'
        $ps | Should -Match '\[DiagSensors\]::OpenTimed\('
        $ps | Should -Match '\[DiagSensors\]::ReadTimed\('
        $ps | Should -Not -Match '\[DiagSensors\]::(Open|Read)\('
    }
    It 'meldet eine fehlende Bibliothek als Fehler statt abzubrechen' {
        [DiagSensors]::Open((Join-Path $TestDrive 'fehlt/LibreHardwareMonitorLib.dll'), $true, $true, $true, $true, $true, $true, $false) | Should -BeFalse
        [DiagSensors]::LastError | Should -Not -BeNullOrEmpty
        [DiagSensors]::IsOpen | Should -BeFalse
    }
    It 'öffnet die Bibliothek und liest nur unterstützte Sensorarten' {
        [DiagSensors]::Open($script:fakeDll, $true, $true, $true, $true, $false, $true, $false) | Should -BeTrue
        [DiagSensors]::LastError | Should -BeNullOrEmpty
        [DiagSensors]::PawnIoState() | Should -Match 'installiert 2\.2'
        $r = @([DiagSensors]::Read())
        @($r | ForEach-Object { $_.Art } | Select-Object -Unique | Sort-Object) | Should -Be @('Auslastung', 'Leistung', 'Lüfter', 'Spannung', 'Takt', 'Temperatur')
        @($r | Where-Object { $_.Name -eq 'Wert' -or $_.Name -eq 'Upload Speed' }).Count | Should -Be 0
    }
    It 'gibt die Speicherauswahl an die Bibliothek weiter' {
        [LibreHardwareMonitor.Hardware.Computer]::LastStorage | Should -BeFalse
    }
    It 'ordnet Gruppen, Einheiten und Geräte zu' {
        $r = @([DiagSensors]::Read())
        $t = $r | Where-Object { $_.Key -eq '/intelcpu/0/temperature/13' }
        $t.Gruppe | Should -Be 'CPU'; $t.Einheit | Should -Be '°C'; $t.Wert | Should -Be 61.5; $t.Geraet | Should -Be 'Intel Core i7-12700'
        $t.TjMax | Should -Be 100
        $f = $r | Where-Object { $_.Name -eq 'CPU Fan' }
        $f.Gruppe | Should -Be 'Mainboard'; $f.Einheit | Should -Be 'U/min'; $f.Geraet | Should -Be 'ASUS PRIME Z690-P / Nuvoton NCT6798D'
        ($r | Where-Object { $_.Name -eq '+12V' }).Wert | Should -BeGreaterThan 12.09
    }
    It 'liefert fehlende Werte als NaN und übersteht fehlerhafte Hardware' {
        $r = @([DiagSensors]::Read())
        [double]::IsNaN(($r | Where-Object { $_.Name -eq 'Bus Speed' }).Wert) | Should -BeTrue
        ($r | Where-Object { $_.Key -eq '/gpu-intel/0/temperature/0' }).Wert | Should -Be 40
        [DiagSensors]::UpdateErrors | Should -BeGreaterThan 0
    }
    It 'schließt die Bibliothek' {
        [DiagSensors]::Close()
        [DiagSensors]::IsOpen | Should -BeFalse
        [LibreHardwareMonitor.Hardware.Computer]::Closed | Should -Be 1
        @([DiagSensors]::Read()).Count | Should -Be 0
    }
    It 'eine verspätete Abfrage liefert die letzten Werte statt die Sensoren abzuschalten (Praxistest Ryzen 5 5600)' {
        [DiagSensors]::OpenTimed($script:fakeDll, $true, $true, $true, $true, $false, $true, $false, 5000) | Should -BeTrue
        $n0 = @([DiagSensors]::ReadTimed(5000)).Count
        $n0 | Should -BeGreaterThan 0
        $slow0 = [DiagSensors]::SlowReads
        # fünf Geräte je 400 ms: eine Abfrage dauert rund 2 s
        [LibreHardwareMonitor.Hardware.H]::Delay = 400
        $sw = [Diagnostics.Stopwatch]::StartNew()
        @([DiagSensors]::ReadTimed(500)).Count | Should -Be $n0
        $sw.ElapsedMilliseconds | Should -BeLessThan 1500
        [DiagSensors]::LastStale | Should -BeTrue
        [DiagSensors]::Hung | Should -BeFalse
        [DiagSensors]::SlowReads | Should -Be ($slow0 + 1)
        # solange die Abfrage läuft: kurz warten, keine zweite Abfrage, wieder die letzten Werte
        $sw.Restart()
        @([DiagSensors]::ReadTimed(5000)).Count | Should -Be $n0
        $sw.ElapsedMilliseconds | Should -BeLessThan 800
        [DiagSensors]::SlowReads | Should -Be ($slow0 + 1)
        Start-Sleep -Milliseconds 2500
        [LibreHardwareMonitor.Hardware.H]::Delay = 0
        @([DiagSensors]::ReadTimed(5000)).Count | Should -Be $n0
        [DiagSensors]::LastStale | Should -BeFalse
        [DiagSensors]::MaxReadMs | Should -BeGreaterThan 1500
    }
    It 'verzögerte Abfragen stehen mit Anzahl und längster Dauer im Bericht' {
        Set-ModuleVar 'Sens' ([pscustomobject]@{ LhmVersion = '0.9.4' })
        try {
            MinibenchTest\Get-SensorDelayText | Should -Match '^LibreHardwareMonitor antwortete \d+x verzögert \(längste Abfrage \d'
            $l = @(MinibenchTest\Get-SensorSeriesLines (MinibenchTest\Get-SensorSeriesStats @()) $null)
            ($l -join "`n") | Should -Match '  Sensoren: LibreHardwareMonitor antwortete \d+x verzögert'
            Set-ModuleVar 'Sens' ([pscustomobject]@{ LhmVersion = '' })
            MinibenchTest\Get-SensorDelayText | Should -BeNullOrEmpty
        } finally { Set-ModuleVar 'Sens' $null }
    }
    It 'eine längst fertige verspätete Abfrage gilt als zu alt: neu lesen, Dauer bis zum Ende der Abfrage gemessen' {
        [DiagSensors]::ResetStats()
        [DiagSensors]::StaleMaxMs = 300
        [LibreHardwareMonitor.Hardware.H]::Delay = 300   # rund 1,5 s je Abfrage
        @([DiagSensors]::ReadTimed(500)) | Out-Null
        [DiagSensors]::LastStale | Should -BeTrue
        Start-Sleep -Milliseconds 3000
        [LibreHardwareMonitor.Hardware.H]::Delay = 0
        $sw = [Diagnostics.Stopwatch]::StartNew()
        @([DiagSensors]::ReadTimed(5000)).Count | Should -BeGreaterThan 0
        [DiagSensors]::LastStale | Should -BeFalse
        [DiagSensors]::MaxReadMs | Should -BeLessThan 2500
        [DiagSensors]::SlowReads | Should -Be 1
        [DiagSensors]::StaleMaxMs = 10000
    }
    It 'gilt erst als ausgefallen, wenn eine Abfrage länger als HangAfterMs hängt' {
        [DiagSensors]::HangAfterMs = 1000
        [LibreHardwareMonitor.Hardware.H]::Delay = 3000
        @([DiagSensors]::ReadTimed(500)).Count | Should -BeGreaterThan 0
        [DiagSensors]::Hung | Should -BeFalse
        Start-Sleep -Milliseconds 700
        @([DiagSensors]::ReadTimed(500)).Count | Should -Be 0
        [DiagSensors]::Hung | Should -BeTrue
        [DiagSensors]::LastError | Should -Match 'antwortet nicht'
        @([DiagSensors]::ReadTimed(500)).Count | Should -Be 0
        [DiagSensors]::OpenTimed($script:fakeDll, $true, $true, $true, $true, $false, $true, $false, 1000) | Should -BeFalse
        [LibreHardwareMonitor.Hardware.H]::Delay = 0
        [DiagSensors]::HangAfterMs = 30000
        [DiagSensors]::Close()
        [DiagSensors]::IsOpen | Should -BeFalse
        [DiagSensors]::Hung = $false
    }
    It 'liest Datenträger getrennt, eine anlaufende Festplatte hält die übrigen Werte nicht auf' {
        Start-Sleep -Milliseconds 3500   # hängende Abfrage des vorigen Tests endet im Hintergrund
        [LibreHardwareMonitor.Hardware.Computer]::StorageDelay = 1500
        [DiagSensors]::StorageIntervalMs = 0
        [DiagSensors]::OpenTimed($script:fakeDll, $true, $true, $true, $true, $true, $true, $false, 5000) | Should -BeTrue
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = @([DiagSensors]::ReadTimed(5000))
        $sw.ElapsedMilliseconds | Should -BeLessThan 1000
        @($r | Where-Object { $_.Gruppe -eq 'CPU' }).Count | Should -BeGreaterThan 0
        @($r | Where-Object { $_.Gruppe -eq 'Datenträger' }).Count | Should -Be 0
        Start-Sleep -Milliseconds 1800
        $r = @([DiagSensors]::ReadTimed(5000))
        ($r | Where-Object { $_.Gruppe -eq 'Datenträger' }).Wert | Should -Be 41
        # Momentaufnahme: auf die Datenträger warten (StorageWaitMs)
        [DiagSensors]::Close(); [DiagSensors]::StorageWaitMs = 5000
        [DiagSensors]::OpenTimed($script:fakeDll, $true, $true, $true, $true, $true, $true, $false, 5000) | Should -BeTrue
        # Wartezeit auf die Datenträger zählt nicht als verspätete Abfrage
        $slow = [DiagSensors]::SlowReads
        $r = @([DiagSensors]::ReadTimed(500))
        ($r | Where-Object { $_.Gruppe -eq 'Datenträger' }).Wert | Should -Be 41
        [DiagSensors]::LastStale | Should -BeFalse
        [DiagSensors]::SlowReads | Should -Be $slow
        [DiagSensors]::StorageWaitMs = 0; [DiagSensors]::StorageIntervalMs = 30000
        [LibreHardwareMonitor.Hardware.Computer]::StorageDelay = 0
        [DiagSensors]::Close()
    }
    It 'Momentaufnahme (-MitDatentraeger) wartet auf die erste Abfrage der Datenträger, danach wieder ohne Warten' {
        Mock -ModuleName MinibenchTest Get-AcpiReadings { @() }
        Mock -ModuleName MinibenchTest Get-BatteryReadings { @() }
        Mock -ModuleName MinibenchTest Get-StorageTempReadings { @() }
        [LibreHardwareMonitor.Hardware.Computer]::StorageDelay = 1500
        try {
            [DiagSensors]::OpenTimed($script:fakeDll, $true, $true, $true, $true, $true, $true, $false, 5000) | Should -BeTrue
            Set-ModuleVar 'Sens' ([pscustomobject]@{ Lhm = $true; LhmFehler = ''; LhmVerzoegert = $false; NvSmi = ''; Hinweise = (New-Object System.Collections.Generic.List[string]); StorageCache = @(); StorageZeit = [datetime]::MinValue; GpuLimits = @{} })
            $r = MinibenchTest\Get-SensorReadings -MitDatentraeger -CpuSample ([pscustomobject]@{ MHz = 3600; Last = 5; MaxFreq = 100 })
            @($r | Where-Object { $_.Gruppe -eq 'Datenträger' -and $_.Quelle -eq 'LHM' }).Count | Should -Be 1
            @($r | Where-Object { $_.Gruppe -eq 'Datenträger' -and $_.Quelle -eq 'LHM' })[0].Wert | Should -Be 41
            @($r | Where-Object { $_.Gruppe -eq 'CPU' -and $_.Quelle -eq 'LHM' }).Count | Should -BeGreaterThan 0
            [DiagSensors]::StorageWaitMs | Should -Be 0
            [DiagSensors]::LastStale | Should -BeFalse
        } finally {
            [LibreHardwareMonitor.Hardware.Computer]::StorageDelay = 0
            [DiagSensors]::Close()
            Set-ModuleVar 'Sens' $null
        }
    }
    It 'Gruppen und Arten decken alle Hardwaretypen ab' {
        foreach ($h in 'Cpu', 'GpuNvidia', 'GpuAmd', 'GpuIntel', 'Motherboard', 'SuperIO', 'EmbeddedController', 'Memory', 'Storage', 'Battery', 'Cooler', 'Psu') { [DiagSensors]::Group($h) | Should -Not -BeNullOrEmpty -Because $h }
        [DiagSensors]::Group('Network') | Should -BeNullOrEmpty
        $u = ''; [DiagSensors]::Kind('Throughput', [ref]$u) | Should -BeNullOrEmpty
    }
}

Describe 'Leitwerte' {
    It 'Intel mit PawnIO: Package-Temperatur, TjMax, Kerntakt und Paketleistung' {
        $rd = @(
            (New-Rd 'CPU' 'Temperatur' 'Core Max' 70 -TjMax 100), (New-Rd 'CPU' 'Temperatur' 'CPU Package' 72 -TjMax 100), (New-Rd 'CPU' 'Temperatur' 'P-Core #1 Distance to TjMax' 28),
            (New-Rd 'CPU' 'Takt' 'P-Core #1' 4700), (New-Rd 'CPU' 'Takt' 'E-Core #1' 3600), (New-Rd 'CPU' 'Takt' 'Bus Speed' 100),
            (New-Rd 'CPU' 'Leistung' 'CPU Package' 125.4), (New-Rd 'CPU' 'Leistung' 'CPU Cores' 110), (New-Rd 'CPU' 'Auslastung' 'CPU Total' 99),
            (New-Rd 'Mainboard' 'Lüfter' 'Fan #2' 900 'Board'), (New-Rd 'Mainboard' 'Lüfter' 'CPU Fan' 1500 'Board'), (New-Rd 'Datenträger' 'Temperatur' 'Temperature' 44 'NVMe'), (New-Rd 'Datenträger' 'Temperatur' 'Temperature' 51 'SATA'))
        $l = MinibenchTest\Get-SensorLead $rd
        $l.CpuTemp | Should -Be 72; $l.CpuTempQ | Should -Be 'LHM'; $l.TjMax | Should -Be 100
        $l.CpuMHz | Should -Be 4150; $l.CpuW | Should -Be 125.4; $l.CpuLoad | Should -Be 99
        $l.Fan | Should -Be 1500; $l.DiskTemp | Should -Be 51
    }
    It 'AMD: Tctl/Tdie und effektiver Mittelwert' {
        $rd = @((New-Rd 'CPU' 'Temperatur' 'Core (Tctl/Tdie)' 88.4), (New-Rd 'CPU' 'Temperatur' 'CCD1 (Tdie)' 80), (New-Rd 'CPU' 'Takt' 'Cores (Average Effective)' 4380.6), (New-Rd 'CPU' 'Takt' 'Core #1' 4500), (New-Rd 'CPU' 'Leistung' 'Package' 142.0))
        $l = MinibenchTest\Get-SensorLead $rd
        $l.CpuTemp | Should -Be 88.4; $l.CpuMHz | Should -Be 4381; $l.CpuW | Should -Be 142; $l.TjMax | Should -BeNullOrEmpty
    }
    It 'ohne Treiber: ACPI als Ersatz, NVIDIA-Werte aus nvidia-smi' {
        $rd = @((New-Rd 'Mainboard' 'Temperatur' 'THRM' 27.8 'ACPI-Thermalzone' 'ACPI'), (New-Rd 'Mainboard' 'Temperatur' 'TZ00' 45 'ACPI-Thermalzone' 'ACPI'), (New-Rd 'CPU' 'Takt' 'Effektiver Takt' 3900 'Windows' 'Windows'), (New-Rd 'CPU' 'Auslastung' 'CPU gesamt' 12 'Windows' 'Windows'))
        $rd += @(MinibenchTest\ConvertFrom-NvidiaSmi '0, NVIDIA GeForce RTX 3060, 47, 1777, 7500, 112.53, 38, 97')
        $l = MinibenchTest\Get-SensorLead $rd
        $l.CpuTemp | Should -Be 45; $l.CpuTempQ | Should -Be 'ACPI'
        $l.CpuMHz | Should -Be 3900; $l.CpuMHzQ | Should -Be 'Windows'; $l.CpuLoad | Should -Be 12
        $l.GpuTemp | Should -Be 47; $l.GpuMHz | Should -Be 1777; $l.GpuW | Should -Be 112.5; $l.GpuLoad | Should -Be 97
    }
    It 'zwei Grafikkarten: die dedizierte statt der integrierten' {
        $rd = @((New-Rd 'GPU' 'Temperatur' 'GPU Core' 41 'Intel(R) UHD Graphics 770'), (New-Rd 'GPU' 'Leistung' 'GPU Power' 4 'Intel(R) UHD Graphics 770'),
            (New-Rd 'GPU' 'Temperatur' 'GPU Hot Spot' 80 'AMD Radeon RX 7800 XT'), (New-Rd 'GPU' 'Temperatur' 'GPU Core' 66 'AMD Radeon RX 7800 XT'), (New-Rd 'GPU' 'Leistung' 'GPU Package' 230 'AMD Radeon RX 7800 XT'), (New-Rd 'GPU' 'Lüfter' 'GPU Fan' 1400 'AMD Radeon RX 7800 XT'))
        $l = MinibenchTest\Get-SensorLead $rd
        $l.GpuTemp | Should -Be 66; $l.GpuW | Should -Be 230; $l.GpuFan | Should -Be 1400
    }
    It 'leere Werte ergeben leere Leitwerte' {
        $l = MinibenchTest\Get-SensorLead @((New-Rd 'CPU' 'Temperatur' 'CPU Package' $null))
        $l.CpuTemp | Should -BeNullOrEmpty; $l.GpuTemp | Should -BeNullOrEmpty
    }
    It 'nvidia-smi: [N/A] wird zu fehlendem Wert, kaputte Zeilen werden übergangen' {
        $r = @(MinibenchTest\ConvertFrom-NvidiaSmi "0, Quadro P400, 35, 139, 405, [N/A], [N/A], 0`r`nFehlerzeile")
        $r.Count | Should -Be 6
        [double]::IsNaN(($r | Where-Object { $_.Art -eq 'Leistung' }).Wert) | Should -BeTrue
        ($r | Where-Object { $_.Art -eq 'Temperatur' }).Wert | Should -Be 35
    }
    It 'Zahlen für die Oberfläche mit Punkt und ohne NaN' {
        MinibenchTest\Format-SensorValue 12.3456 | Should -Be '12.346'
        MinibenchTest\Format-SensorValue ([double]::NaN) | Should -Be ''
        MinibenchTest\Format-SensorValue $null | Should -Be ''
    }
}

Describe 'Abbruchschwelle' {
    It 'Einstellung <S> mit TjMax <Tj> ergibt <E>' -ForEach @(
        @{ S = 'auto'; Tj = 100; E = 100 }, @{ S = 'auto'; Tj = 105; E = 105 }, @{ S = 'auto'; Tj = $null; E = 100 }, @{ S = 'aus'; Tj = 100; E = 0 },
        @{ S = '0'; Tj = $null; E = 0 }, @{ S = '90'; Tj = 100; E = 90 }, @{ S = '95.5'; Tj = $null; E = 95.5 }, @{ S = 'Quatsch'; Tj = $null; E = 0 }, @{ S = '20'; Tj = $null; E = 0 }
    ) { MinibenchTest\Get-AbortLimit $S $Tj | Should -Be $E }
    It 'bricht erst ab, wenn drei Messpunkte in Folge an der Schwelle liegen' {
        $s = @(70, 96, 97, 80, 96, 96) | ForEach-Object { [pscustomobject]@{ CpuTemp = $_; CpuTempQ = 'LHM'; GpuTemp = $null } }
        (MinibenchTest\Test-LoadAbort $s 95 0 3).Abbruch | Should -BeFalse
        $s += [pscustomobject]@{ CpuTemp = 95; CpuTempQ = 'LHM'; GpuTemp = $null }
        $a = MinibenchTest\Test-LoadAbort $s 95 0 3
        $a.Abbruch | Should -BeTrue; $a.Art | Should -Be 'CPU'; $a.Wert | Should -Be 96; $a.Grund | Should -Match '95 °C'
    }
    It 'ein ACPI-Festwert löst nie aus, eine bewegte Thermalzone schon' {
        $fix = @(1..5) | ForEach-Object { [pscustomobject]@{ CpuTemp = 100; CpuTempQ = 'ACPI'; GpuTemp = $null } }
        (MinibenchTest\Test-LoadAbort $fix 95 0 3).Abbruch | Should -BeFalse
        $mov = @(60, 80, 96, 97, 98) | ForEach-Object { [pscustomobject]@{ CpuTemp = $_; CpuTempQ = 'ACPI'; GpuTemp = $null } }
        (MinibenchTest\Test-LoadAbort $mov 95 0 3).Abbruch | Should -BeTrue
    }
    It 'GPU-Schwelle und ausgeschaltete Schwellen' {
        $s = @(88, 91, 92, 93) | ForEach-Object { [pscustomobject]@{ CpuTemp = 99; CpuTempQ = 'LHM'; GpuTemp = $_ } }
        (MinibenchTest\Test-LoadAbort $s 0 0 3).Abbruch | Should -BeFalse
        $a = MinibenchTest\Test-LoadAbort $s 0 90 3
        $a.Abbruch | Should -BeTrue; $a.Art | Should -Be 'GPU'
    }
    It 'automatische Schwelle wartet länger als feste (eigene Haltezeit für die CPU)' {
        $s = @(1..10) | ForEach-Object { [pscustomobject]@{ CpuTemp = 100; CpuTempQ = 'LHM'; GpuTemp = 50 } }
        (MinibenchTest\Test-LoadAbort $s 100 90 3 20).Abbruch | Should -BeFalse
        $s += @(1..10) | ForEach-Object { [pscustomobject]@{ CpuTemp = 100; CpuTempQ = 'LHM'; GpuTemp = 50 } }
        (MinibenchTest\Test-LoadAbort $s 100 90 3 20).Abbruch | Should -BeTrue
        $g = @(1..3) | ForEach-Object { [pscustomobject]@{ CpuTemp = 100; CpuTempQ = 'LHM'; GpuTemp = 95 } }
        (MinibenchTest\Test-LoadAbort $g 100 90 3 20).Art | Should -Be 'GPU'
    }
    It 'fehlende Werte lösen nicht aus' {
        $s = @(1..4) | ForEach-Object { [pscustomobject]@{ CpuTemp = $null; CpuTempQ = ''; GpuTemp = $null } }
        (MinibenchTest\Test-LoadAbort $s 95 90 3).Abbruch | Should -BeFalse
    }
}

Describe 'Drosselnachweis' {
    It 'stabiler Takt: keine Drosselung' {
        $s = New-Series 40 { 4500 + ($args[0] % 3) * 10 } { 78 } { 120 }
        $r = MinibenchTest\Get-ThrottleAnalysis $s 100
        $r.Status | Should -Be 'keine'; $r.Stufe | Should -BeNullOrEmpty; $r.Abfall | Should -BeLessThan 1
    }
    It 'thermisch: Takt fällt, Temperatur an TjMax' {
        $s = New-Series 40 { param($i) if ($i -lt 8) { 4700 } else { 3700 } } { param($i) if ($i -lt 6) { 85 + $i * 2 } else { 99 } } { param($i) if ($i -lt 8) { 190 } else { 150 } }
        $r = MinibenchTest\Get-ThrottleAnalysis $s 100
        $r.Status | Should -Be 'thermisch'; $r.Stufe | Should -Be 'WARNUNG'
        $r.Abfall | Should -BeGreaterThan 15; $r.TempMax | Should -Be 99; $r.Grenze | Should -Be 100
        $r.Befund | Should -Match 'Thermische Drosselung belegt'
        $r.Beginn | Should -Be 36
        @($r.Belege).Count | Should -BeGreaterOrEqual 3
    }
    It 'Leistungsgrenze: Takt fällt mit der Paketleistung, Temperatur weit unter der Grenze' {
        $s = New-Series 40 { param($i) if ($i -lt 9) { 4600 } else { 4000 } } { 76 } { param($i) if ($i -lt 9) { 181 } else { 125 } }
        $r = MinibenchTest\Get-ThrottleAnalysis $s 100
        $r.Status | Should -Be 'Leistungsgrenze'; $r.Stufe | Should -Be 'INFO'; $r.Befund | Should -Match 'PL2'
    }
    It 'ohne TjMax gilt 95 °C als Grenze (AMD)' {
        $s = New-Series 30 { param($i) if ($i -lt 6) { 4800 } else { 4300 } } { 94.6 } { 140 }
        $r = MinibenchTest\Get-ThrottleAnalysis $s $null
        $r.Status | Should -Be 'thermisch'; $r.Grenze | Should -Be 95; $r.GrenzeQuelle | Should -Match 'unbekannt'
    }
    It 'Firmware: Ereignis 37 ohne Temperatur' {
        $s = New-Series 30 { param($i) if ($i -lt 6) { 3000 } else { 2400 } } { $null } { $null } 'LHM'
        $r = MinibenchTest\Get-ThrottleAnalysis $s $null -FirmwareEvents 4
        $r.Status | Should -Be 'Firmware'; $r.Stufe | Should -Be 'WARNUNG'; ($r.Belege -join ' ') | Should -Match 'Ereignisse 37'
    }
    It 'unklar: Abfall ohne Beleg' {
        $s = New-Series 30 { param($i) if ($i -lt 6) { 3000 } else { 2600 } } { 70 } { 60 }
        $r = MinibenchTest\Get-ThrottleAnalysis $s 100
        $r.Status | Should -Be 'unklar'; $r.Stufe | Should -Be 'WARNUNG'
    }
    It 'ACPI-Festwert zählt nicht als Temperaturbeleg' {
        $s = New-Series 30 { param($i) if ($i -lt 6) { 3000 } else { 2500 } } { 100 } { $null } 'ACPI'
        $r = MinibenchTest\Get-ThrottleAnalysis $s $null
        $r.Status | Should -Be 'unklar'; $r.TempMax | Should -BeNullOrEmpty
    }
    It 'Windows-Takt als Festwert: bewertet wird der Sensortakt' {
        $s = New-Series 30 { param($i) if ($i -lt 6) { 4700 } else { 3800 } } { 99 } { $null } 'LHM' { 3600 }
        $r = MinibenchTest\Get-ThrottleAnalysis $s 100
        $r.TaktQuelle | Should -Match 'LibreHardwareMonitor'; $r.Status | Should -Be 'thermisch'
    }
    It 'fehlende Taktwerte verschieben den Beginn nicht nach vorn' {
        $s = New-Series 40 { param($i) if ($i -lt 8) { 4700 } else { 3700 } } { 99 } { 150 }
        $s[3].MHz = $null; $s[3].CpuMHz = $null; $s[4].MHz = 0
        $r = MinibenchTest\Get-ThrottleAnalysis $s 100
        $r.Beginn | Should -Be 36
    }
    It 'lange Verläufe bleiben schnell (9600 Messpunkte, 8 Stunden)' {
        $s = New-Series 9600 { param($i) if ($i -lt 400) { 4700 } else { 4300 } } { 90 } { 150 }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = MinibenchTest\Get-ThrottleAnalysis $s 100
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 30
        $r.Beginn | Should -Be (12 + 3 * 400)
    }
    It 'zu wenige Messpunkte: nicht bewertbar' {
        $r = MinibenchTest\Get-ThrottleAnalysis (New-Series 5 { 4000 }) 100
        $r.Status | Should -Be 'nicht bewertbar'
    }
    It 'Messpunkte ohne CPU-Last und in der Anlaufphase zählen nicht' {
        $s = @(New-Series 30 { 4000 } { 70 } { 100 })
        foreach ($x in $s[0..9]) { $x.Cpu = $false; $x.MHz = 900; $x.CpuMHz = 900 }
        $r = MinibenchTest\Get-ThrottleAnalysis $s 100
        $r.Status | Should -Be 'keine'; $r.TaktStart | Should -Be 4000
    }
}

Describe 'Momentaufnahme: Plausibilität' {
    It 'warnt bei heißer CPU im Leerlauf, nicht bei ACPI-Werten' {
        $l = [pscustomobject]@{ CpuTemp = 84; CpuTempQ = 'LHM'; GpuTemp = 45 }
        @(MinibenchTest\Get-SensorSnapshotFindings @() $l).Stufe | Should -Be 'WARNUNG'
        $l.CpuTempQ = 'ACPI'
        @(MinibenchTest\Get-SensorSnapshotFindings @() $l).Count | Should -Be 0
    }
    It 'stehender CPU-Lüfter bei warmer CPU' {
        $l = [pscustomobject]@{ CpuTemp = 66; CpuTempQ = 'LHM'; GpuTemp = $null }
        $rd = @((New-Rd 'Mainboard' 'Lüfter' 'CPU Fan' 0 'Board'), (New-Rd 'Mainboard' 'Lüfter' 'Chassis Fan #1' 800 'Board'))
        (@(MinibenchTest\Get-SensorSnapshotFindings $rd $l).Text -join ' ') | Should -Match '0 U/min'
        $rd[0].Wert = 900
        @(MinibenchTest\Get-SensorSnapshotFindings $rd $l).Count | Should -Be 0
    }
    It 'nennt Leerlauf nur bei geringer Last, sonst bei Last und Watt' {
        $lIdle = [pscustomobject]@{ CpuTemp = 84; CpuTempQ = 'LHM'; CpuLoad = 5; CpuW = 15; GpuTemp = $null }
        $fIdle = @(MinibenchTest\Get-SensorSnapshotFindings @() $lIdle)
        $fIdle[0].Text | Should -Match 'im Leerlauf 84 °C'

        $lLoad = [pscustomobject]@{ CpuTemp = 95; CpuTempQ = 'LHM'; CpuLoad = 35; CpuW = 28.7; GpuTemp = $null }
        $fLoad = @(MinibenchTest\Get-SensorSnapshotFindings @() $lLoad)
        $fLoad[0].Text | Should -Match '95 °C bei 35 % Last, 29 W'
    }
    It 'Temperaturen unter 5 °C werden als unplausibel verworfen' {
        $rd = New-Rd 'Datenträger' 'Temperatur' 'Temperature' 1 'NVMe Disk'
        $why = MinibenchTest\Get-SensorImplausibility $rd $null
        $why | Should -Match 'unter 5 °C ist als Komponententemperatur unplausibel'
    }
    It 'identische Spannungen über 1,5 V auf mehreren Schienen desselben Geräts im Leerlauf werden verworfen' {
        $l = New-Object System.Collections.Generic.List[object]
        $l.Add((New-Rd 'CPU' 'Spannung' 'Core Voltage' 1.55 'Ryzen 3 5300U'))
        $l.Add((New-Rd 'CPU' 'Spannung' 'SoC Voltage' 1.55 'Ryzen 3 5300U'))
        MinibenchTest\Set-SensorClassification $l $null
        $l[0].Status | Should -Be 'unplausibel'
        $l[1].Status | Should -Be 'unplausibel'
        [double]::IsNaN($l[0].Wert) | Should -BeTrue
        [double]::IsNaN($l[1].Wert) | Should -BeTrue
    }
    It 'Test-OnBattery erkennt Akkubetrieb und Netzbetrieb' {
        Mock -ModuleName MinibenchTest Get-CimInstance { [pscustomobject]@{ PowerOnline = $false } } -ParameterFilter { $ClassName -eq 'BatteryStatus' }
        Mock -ModuleName MinibenchTest Get-CimInstance { }
        MinibenchTest\Test-OnBattery | Should -BeTrue

        Mock -ModuleName MinibenchTest Get-CimInstance { [pscustomobject]@{ PowerOnline = $true } } -ParameterFilter { $ClassName -eq 'BatteryStatus' }
        Mock -ModuleName MinibenchTest Get-CimInstance { }
        MinibenchTest\Test-OnBattery | Should -BeFalse
    }
}

Describe 'Sensorwerkzeuge mit festen Prüfsummen' {
    BeforeEach {
        $d = New-DataDir
        $tools = Join-Path $d 'Tools'
        $lhm = Join-Path $tools 'LibreHardwareMonitor'; New-Item -ItemType Directory -Path $lhm -Force | Out-Null
        $pw = Join-Path $tools 'PawnIO'; New-Item -ItemType Directory -Path $pw -Force | Out-Null
        # Testdateien statt der echten Bibliothek; die Pins zeigen auf ihre Prüfsummen
        $pins = [ordered]@{}
        foreach ($n in 'LibreHardwareMonitorLib.dll', 'HidSharp.dll') { $p = Join-Path $lhm $n; [IO.File]::WriteAllText($p, 'Inhalt ' + $n); $pins[$n] = @{ SHA256 = (MinibenchTest\Get-FileSha256 $p); Lizenz = 'MPL-2.0' } }
        Set-ModuleVar 'LhmPins' $pins
        $setup = Join-Path $pw 'PawnIO_setup.exe'; [IO.File]::WriteAllText($setup, 'Setup')
        $pp = (Get-ModuleVar 'PawnIoPin').Clone(); $pp.SHA256 = (MinibenchTest\Get-FileSha256 $setup); Set-ModuleVar 'PawnIoPin' $pp
    }
    BeforeAll { $script:orig = @{ LhmPins = (Get-ModuleVar 'LhmPins'); PawnIoPin = (Get-ModuleVar 'PawnIoPin'); LhmZip = (Get-ModuleVar 'LhmZip') } }
    AfterAll { foreach ($k in $script:orig.Keys) { Set-ModuleVar $k $script:orig[$k] } }
    It 'nimmt vorgefundene Dateien mit passender Prüfsumme auf und gibt sie frei' {
        $st = MinibenchTest\Get-SensorToolState $tools
        $st.LhmBereit | Should -BeTrue
        $st.LhmDll | Should -Be (Join-Path $lhm 'LibreHardwareMonitorLib.dll')
        $st.PawnIoSetup | Should -Be $setup
        $m = Get-Content (Join-Path $tools 'Tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        @($m.Werkzeuge | Where-Object { $_.Name -like 'LibreHardwareMonitor:*' }).Count | Should -Be 2
        ($m.Werkzeuge | Where-Object { $_.Name -eq 'PawnIO-Setup' }).Herkunft | Should -Match 'Prüfsumme'
    }
    It 'weist eine Datei mit fremder Prüfsumme ab und lädt dann nichts' {
        [IO.File]::WriteAllText((Join-Path $lhm 'HidSharp.dll'), 'ausgetauscht')
        $st = MinibenchTest\Get-SensorToolState $tools
        $st.LhmBereit | Should -BeFalse
        $st.Fehlend | Should -Be @('HidSharp.dll')
        (Get-ModuleVar 'ToolIssues') -join ' ' | Should -Match 'nicht die bekannte Prüfsumme'
    }
    It 'sperrt eine nach der Aufnahme veränderte Datei' {
        [void](MinibenchTest\Get-SensorToolState $tools)
        [IO.File]::WriteAllText((Join-Path $lhm 'LibreHardwareMonitorLib.dll'), 'manipuliert')
        (MinibenchTest\Get-SensorToolState $tools).LhmBereit | Should -BeFalse
    }
    It 'sperrt einen Manifesteintrag, der vom Release abweicht' {
        [void](MinibenchTest\Get-SensorToolState $tools)
        $pins = Get-ModuleVar 'LhmPins'; $pins['HidSharp.dll'].SHA256 = ('0' * 64); Set-ModuleVar 'LhmPins' $pins
        $st = MinibenchTest\Get-SensorToolState $tools
        $st.LhmBereit | Should -BeFalse
        (Get-ModuleVar 'ToolIssues') -join ' ' | Should -Match 'weicht vom freigegebenen Release ab'
    }
    It 'ohne Dateien: nicht bereit, ohne Fehlermeldung' {
        Remove-Item (Join-Path $lhm '*') -Force; Remove-Item $setup -Force
        $st = MinibenchTest\Get-SensorToolState $tools
        $st.LhmBereit | Should -BeFalse; $st.PawnIoSetup | Should -BeNullOrEmpty
        @(Get-ModuleVar 'ToolIssues').Count | Should -Be 0
    }
    It 'holt aus dem Release-Archiv, prüft und nimmt auf' {
        $src = Join-Path $TestDrive ('rel' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $src | Out-Null
        foreach ($n in 'LibreHardwareMonitorLib.dll', 'HidSharp.dll') { Copy-Item (Join-Path $lhm $n) $src; Remove-Item (Join-Path $lhm $n) }
        [IO.File]::WriteAllText((Join-Path $src 'LibreHardwareMonitor.exe'), 'nicht gebraucht')
        $zip = Join-Path $TestDrive ('rel' + [guid]::NewGuid().ToString('N') + '.zip')
        Compress-Archive -Path (Join-Path $src '*') -DestinationPath $zip
        $z = (Get-ModuleVar 'LhmZip').Clone(); $z.SHA256 = (MinibenchTest\Get-FileSha256 $zip); Set-ModuleVar 'LhmZip' $z
        $setupCopy = Join-Path $TestDrive ('s' + [guid]::NewGuid().ToString('N')); Copy-Item $setup $setupCopy; Remove-Item $setup
        $script:TZip = $zip; $script:TSetup = $setupCopy
        Mock -ModuleName MinibenchTest Save-WebFile { if ($Url -like '*LibreHardwareMonitor.zip') { Copy-Item $script:TZip $Path } else { Copy-Item $script:TSetup $Path } }
        $r = MinibenchTest\Install-SensorTools $tools
        $r.Ok | Should -BeTrue
        (MinibenchTest\Get-SensorToolState $tools).LhmBereit | Should -BeTrue
        Test-Path (Join-Path $lhm 'LibreHardwareMonitor.exe') | Should -BeFalse
        Test-Path (Join-Path $lhm 'Lizenzen.txt') | Should -BeTrue
        Test-Path $setup | Should -BeTrue
        @(Get-ChildItem (Join-Path $d 'Laufzeit') -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
    It 'übernimmt nichts, wenn das Archiv nicht die erwartete Prüfsumme hat' {
        Remove-Item (Join-Path $lhm '*') -Force
        Mock -ModuleName MinibenchTest Save-WebFile { [IO.File]::WriteAllText($Path, 'falsches Archiv') }
        $r = MinibenchTest\Install-SensorTools $tools
        $r.Ok | Should -BeFalse
        ($r.Meldungen -join ' ') | Should -Match 'unerwartete Prüfsumme'
        @(Get-ChildItem $lhm).Count | Should -Be 0
    }
}

Describe 'PawnIO nur vorübergehend' {
    BeforeEach {
        $d = New-DataDir
        $script:Reg = $null; $script:Calls = @(); $script:UninstallFails = $false
        Mock -ModuleName MinibenchTest Get-PawnIoRegistry { $script:Reg }
        # sonst ruft die Sitzung auf einem PC mit NVIDIA-Treiber nvidia-smi über Invoke-External auf
        Mock -ModuleName MinibenchTest Find-NvidiaSmi { '' }
        Mock -ModuleName MinibenchTest Get-SensorToolState { [pscustomobject]@{ LhmDll = 'x'; LhmBereit = $true; Fehlend = @(); PawnIoSetup = 'C:\Stick\Tools\PawnIO\PawnIO_setup.exe' } }
        Mock -ModuleName MinibenchTest Invoke-External {
            $script:Calls += ('{0} {1}' -f $File, $Arguments)
            if ($Arguments -like '-install*') { $script:Reg = [pscustomobject]@{ Version = '2.2.0.0'; Ort = 'C:\Program Files\PawnIO'; Deinstallation = '' } }
            if ($Arguments -like '-uninstall*' -and -not $script:UninstallFails) { $script:Reg = $null }
            [pscustomobject]@{ ExitCode = 0; Output = ''; Error = ''; TimedOut = $false }
        }
    }
    It 'lässt einen vorhandenen Treiber unangetastet' {
        $script:Reg = [pscustomobject]@{ Version = '2.0.1.0'; Ort = 'C:\Program Files\PawnIO'; Deinstallation = '' }
        $r = MinibenchTest\Install-PawnIoTemporary
        $r.Text | Should -Match 'bereits installiert'
        MinibenchTest\Uninstall-PawnIo | Should -BeNullOrEmpty
        @($script:Calls).Count | Should -Be 0
        Get-ModuleVar 'PawnIoInstalledRun' | Should -BeFalse
    }
    It 'installiert mit Markierung und Hinweis im Änderungsprotokoll und entfernt wieder' {
        $r = MinibenchTest\Install-PawnIoTemporary
        $r.Ok | Should -BeTrue
        ($script:Calls)[0] | Should -Match 'PawnIO_setup\.exe -install -silent'
        Test-Path (MinibenchTest\Get-PawnIoMarker) | Should -BeTrue
        Get-ModuleVar 'PawnIoInstalledRun' | Should -BeTrue
        $c = @(Get-ModuleVar 'TestChanges'); $c[0].Risiko | Should -Be 'Eingriff'; $c[0].NurHinweis | Should -BeTrue
        $u = MinibenchTest\Uninstall-PawnIo
        $u.Ok | Should -BeTrue
        ($script:Calls)[1] | Should -Match '-uninstall -silent'
        Test-Path (MinibenchTest\Get-PawnIoMarker) | Should -BeFalse
        @(Get-ModuleVar 'TestChanges').Count | Should -Be 2
    }
    It 'entfernt nach einem Absturz beim nächsten Start' {
        [void](MinibenchTest\Install-PawnIoTemporary)
        Set-ModuleVar 'PawnIoByUs' $false   # neuer Prozess: nur die Markierung weiß noch davon
        MinibenchTest\Remove-PawnIoLeftover
        $script:Reg | Should -BeNullOrEmpty
        (Get-ModuleVar 'SensorNotes') -join ' ' | Should -Match 'abgebrochen'
        Test-Path (MinibenchTest\Get-PawnIoMarker) | Should -BeFalse
    }
    It 'ohne Markierung entfernt der Start nichts' {
        $script:Reg = [pscustomobject]@{ Version = '2.2.0.0'; Ort = 'C:\x'; Deinstallation = '' }
        MinibenchTest\Remove-PawnIoLeftover
        @($script:Calls).Count | Should -Be 0
    }
    It 'meldet eine gescheiterte Entfernung und behält die Markierung' {
        [void](MinibenchTest\Install-PawnIoTemporary)
        $script:UninstallFails = $true
        $u = MinibenchTest\Uninstall-PawnIo
        $u.Ok | Should -BeFalse; $u.Text | Should -Match 'noch installiert'
        Test-Path (MinibenchTest\Get-PawnIoMarker) | Should -BeTrue
    }
    It 'installiert nicht ohne geprüftes Setup' {
        Mock -ModuleName MinibenchTest Get-SensorToolState { [pscustomobject]@{ LhmDll = ''; LhmBereit = $false; Fehlend = @('x'); PawnIoSetup = '' } }
        $r = MinibenchTest\Install-PawnIoTemporary
        $r.Ok | Should -BeFalse
        @($script:Calls).Count | Should -Be 0
        Test-Path (MinibenchTest\Get-PawnIoMarker) | Should -BeFalse
    }
    It 'ohne schreibbare Markierung wird nicht installiert' {
        $m = MinibenchTest\Get-PawnIoMarker
        New-Item -ItemType Directory -Path $m -Force | Out-Null   # ein Ordner an der Stelle der Datei verhindert das Schreiben
        $r = MinibenchTest\Install-PawnIoTemporary
        $r.Ok | Should -BeFalse; $r.Text | Should -Match 'Markierung'
        @($script:Calls).Count | Should -Be 0
    }
    It 'eine gescheiterte Installation hinterlässt keine Markierung' {
        Mock -ModuleName MinibenchTest Invoke-External { [pscustomobject]@{ ExitCode = 5; Output = ''; Error = ''; TimedOut = $false } }
        $r = MinibenchTest\Install-PawnIoTemporary
        $r.Ok | Should -BeFalse; $r.Text | Should -Match 'Rückgabecode 5'
        Test-Path (MinibenchTest\Get-PawnIoMarker) | Should -BeFalse
    }
    It 'Sitzung ohne -SensorTreiber installiert nie' {
        Mock -ModuleName MinibenchTest Get-SensorToolState { [pscustomobject]@{ LhmDll = ''; LhmBereit = $false; Fehlend = @('LibreHardwareMonitorLib.dll'); PawnIoSetup = 'C:\s.exe' } }
        $s = MinibenchTest\Open-SensorSession
        $s.Lhm | Should -BeFalse
        @($script:Calls).Count | Should -Be 0
        MinibenchTest\Close-SensorSession
        @($script:Calls).Count | Should -Be 0
    }
}

Describe 'Unplausible Sensorwerte zählen' {
    BeforeEach { $script:seen = @{} }
    It 'zählt je Sensor und behält den höchsten Rohwert' {
        $r1 = MinibenchTest\New-SensorReading 'k1' 'LHM' 'GPU' 'Intel(R) Iris(R) Xe Graphics' 'Leistung' 'GPU Package' 'W' 590
        $r1.Status = 'unplausibel'; $r1.Roh = 590; $r1.Wert = [double]::NaN
        $r2 = MinibenchTest\New-SensorReading 'k1' 'LHM' 'GPU' 'Intel(R) Iris(R) Xe Graphics' 'Leistung' 'GPU Package' 'W' 610
        $r2.Status = 'unplausibel'; $r2.Roh = 610; $r2.Wert = [double]::NaN
        $ok = MinibenchTest\New-SensorReading 'k2' 'LHM' 'CPU' 'CPU' 'Temperatur' 'CPU Package' '°C' 55
        MinibenchTest\Register-BadReadings @($r1, $ok) $script:seen
        MinibenchTest\Register-BadReadings @($r2) $script:seen
        $script:seen.Count | Should -Be 1
        $e = @($script:seen.Values)[0]
        $e.Anzahl | Should -Be 2; $e.Max | Should -Be 610; $e.Geraet | Should -Be 'Intel(R) Iris(R) Xe Graphics'
    }
    It 'übersteht Einträge ohne Gerät, ohne Namen und ohne Rohwert' {
        $r = [pscustomobject]@{ Geraet = $null; Name = $null; Art = 'Leistung'; Hinweis = ''; Status = 'unplausibel'; Roh = $null }
        { MinibenchTest\Register-BadReadings @($r, $r, $null) $script:seen } | Should -Not -Throw
        @($script:seen.Values)[0].Anzahl | Should -Be 2
    }
    It 'eine unplausible GPU-Leistung der Prozessorgrafik wird erkannt und je Sensor gezählt' {
        $l = New-Object System.Collections.Generic.List[object]
        $l.Add((New-Rd 'GPU' 'Leistung' 'GPU Package' 48.5 'NVIDIA RTX 3000 Ada Generation Laptop GPU'))
        $l.Add((New-Rd 'GPU' 'Leistung' 'GPU Power' 590 'Intel(R) Iris(R) Xe Graphics'))
        MinibenchTest\Set-SensorClassification $l $null
        MinibenchTest\Register-BadReadings @(, [object[]]$l.ToArray()) $script:seen
        $script:seen.Count | Should -Be 1
        $e = @($script:seen.Values)[0]
        $e.Geraet | Should -Be 'Intel(R) Iris(R) Xe Graphics'; $e.Name | Should -Be 'GPU Power'; $e.Max | Should -Be 590
    }
}

Describe 'Messwerte für Lasttest und Bericht' {
    BeforeAll {
        $script:SensKultur = [Threading.Thread]::CurrentThread.CurrentCulture
        [Threading.Thread]::CurrentThread.CurrentCulture = 'de-DE'
        # so wie Get-SensorReadings zurückgibt: ein Array, mit Komma vor dem Auspacken geschützt
        function Get-Fake {
            $l = New-Object System.Collections.Generic.List[object]
            $l.Add((New-Rd 'CPU' 'Temperatur' 'CPU Package' 71 '13th Gen Intel Core i9-13900H'))
            $l.Add((New-Rd 'GPU' 'Temperatur' 'GPU Core' 66 'NVIDIA RTX 3000 Ada Generation Laptop GPU'))
            $l.Add((New-Rd 'GPU' 'Takt' 'GPU Core' 1755 'NVIDIA RTX 3000 Ada Generation Laptop GPU'))
            $l.Add((New-Rd 'GPU' 'Leistung' 'GPU Package' 48.5 'NVIDIA RTX 3000 Ada Generation Laptop GPU'))
            $l.Add((New-Rd 'GPU' 'Takt' 'GPU Core' 1300 'Intel(R) Iris(R) Xe Graphics'))
            MinibenchTest\Set-SensorClassification $l $null
            return , [object[]]$l.ToArray()
        }
    }
    AfterAll { [Threading.Thread]::CurrentThread.CurrentCulture = $script:SensKultur }
    It 'doppelt verpackte Liste ergibt dieselben Leitwerte wie die flache (Praxistest: alle Leitwerte leer)' {
        $flat = Get-Fake
        $nested = @(Get-Fake)
        $nested.Count | Should -Be 1
        $a = MinibenchTest\Get-SensorLead $flat
        $b = MinibenchTest\Get-SensorLead $nested
        $b.GpuTemp | Should -Be 66; $b.GpuMHz | Should -Be 1755; $b.GpuW | Should -Be 48.5
        $b.CpuTemp | Should -Be 71
        $b.IGpuMHz | Should -Be 1300
        $b.GpuTemp | Should -Be $a.GpuTemp
    }
    It 'flache Liste bleibt flach, null wird übergangen' {
        @(MinibenchTest\ConvertTo-FlatReadings @($null, (New-Rd 'CPU' 'Takt' 'Core #1' 4000))).Count | Should -Be 1
        @(MinibenchTest\ConvertTo-FlatReadings $null).Count | Should -Be 0
    }
    It 'Takt der Windows-Leistungszähler heißt CPU gesamt, der Leitwert findet ihn' {
        $rd = @(MinibenchTest\ConvertFrom-CpuSampleReadings ([pscustomobject]@{ MHz = 2450; Last = 30; MaxFreq = 100 }))
        @($rd | Where-Object { $_.Art -eq 'Takt' })[0].Name | Should -Be 'CPU gesamt'
        (MinibenchTest\Get-SensorLead $rd).CpuMHz | Should -Be 2450
    }
    It 'GPU-Zeile für den Bericht mit Takt, Temperatur und Leistung' {
        $m = [pscustomobject]@{ Average = 1712.4; Maximum = 1800 }
        MinibenchTest\Get-GpuLoadLine 'NVIDIA RTX 3000' $m 74 ([double]51.2) | Should -Be 'NVIDIA RTX 3000: Takt Ø 1.712 / max 1.800 MHz, Temperatur max 74 °C, Leistung max 51,2 W'
        MinibenchTest\Get-GpuLoadLine 'X' $null $null $null | Should -BeNullOrEmpty
    }
    It 'Zuverlässigkeitszähler mit Zeitlimit: ein hängender Aufruf hält den Lauf nicht an' {
        $mod = Get-Module MinibenchTest
        $orig = & $mod { ${function:Get-StorageTempRaw}.ToString() }
        try {
            & $mod {
                function script:Get-StorageTempRaw { Start-Sleep -Seconds 20; @() }
                $script:Sens = [pscustomobject]@{ StorageTimeout = $false; Hinweise = New-Object System.Collections.Generic.List[string] }
            }
            $sw = [Diagnostics.Stopwatch]::StartNew()
            @(MinibenchTest\Get-StorageTempReadings 1).Count | Should -Be 0
            $sw.Elapsed.TotalSeconds | Should -BeLessThan 8
            (Get-ModuleVar 'Sens').StorageTimeout | Should -BeTrue
            ((Get-ModuleVar 'Sens').Hinweise -join ' ') | Should -Match 'antworten nicht innerhalb von 1 Sekunden'
            $sw.Restart()
            @(MinibenchTest\Get-StorageTempReadings 1).Count | Should -Be 0
            $sw.Elapsed.TotalSeconds | Should -BeLessThan 1
        } finally {
            & $mod { param($t) . ([scriptblock]::Create('function script:Get-StorageTempRaw {' + $t + '}')); $script:Sens = $null } $orig
        }
    }
}

Describe 'Sensoren ohne LibreHardwareMonitor' {
    BeforeAll {
        function New-Sitzung([bool]$Lhm) {
            [pscustomobject]@{ Lhm = $Lhm; LhmFehler = ''; LhmVerzoegert = $false; NvSmi = ''; Hinweise = (New-Object System.Collections.Generic.List[string]); StorageCache = @(); StorageZeit = [datetime]::MinValue; GpuLimits = @{} }
        }
    }
    AfterEach { Set-ModuleVar 'Sens' $null }
    It 'Sensoren.cs mit DiagGpuKmt (Grafiktreiber, Energiezähler) lässt sich mit C# 5 übersetzen' {
        if (-not $script:SensorenCs.Compiler) { Set-ItResult -Skipped -Because $script:SensorenCs.Meldung; return }
        $script:SensorenCs.Ok | Should -BeTrue -Because $script:SensorenCs.Meldung
        ('DiagGpuKmt' -as [type]) | Should -Not -BeNullOrEmpty
    }
    It 'Windows-Grafiktreiber liefert Temperatur, Takt, Lüfter und Auslastung je Karte' {
        $a = @([pscustomobject]@{ Name = 'AMD Radeon RX 6800'; TempC = 55.5; CoreMhz = 2105; MemMhz = 1000; FanRpm = [double]::NaN; Load = 97.3 })
        $r = @(MinibenchTest\ConvertFrom-KmtAdapters $a @())
        @($r | Where-Object { $_.Art -eq 'Temperatur' }).Wert | Should -Be 55.5
        @($r | Where-Object { $_.Name -eq 'GPU Core' -and $_.Art -eq 'Takt' }).Wert | Should -Be 2105
        @($r | Where-Object { $_.Name -eq 'GPU Memory' }).Wert | Should -Be 1000
        @($r | Where-Object { $_.Art -eq 'Lüfter' }).Count | Should -Be 0
        @($r | ForEach-Object { $_.Quelle } | Select-Object -Unique) | Should -Be @('Windows')
        $lead = MinibenchTest\Get-SensorLead $r
        $lead.GpuTemp | Should -Be 55.5
        $lead.GpuLoad | Should -Be 97
    }
    It 'überschreibt keine Werte anderer Quellen, verwirft unplausible und virtuelle Adapter' {
        $ex = @(MinibenchTest\New-SensorReading 'nvsmi/0/temp' 'nvidia-smi' 'GPU' 'NVIDIA GeForce RTX 3060' 'Temperatur' 'GPU Core' '°C' 61 'GpuNvidia')
        $a = @([pscustomobject]@{ Name = 'NVIDIA GeForce RTX 3060'; TempC = 60; CoreMhz = 99999; MemMhz = [double]::NaN; FanRpm = 1500; Load = 40 },
               [pscustomobject]@{ Name = 'Microsoft Remote Display Adapter'; TempC = 40; CoreMhz = 1000; MemMhz = 1000; FanRpm = 1000; Load = 1 })
        $r = @(MinibenchTest\ConvertFrom-KmtAdapters $a $ex)
        @($r | Where-Object { $_.Art -eq 'Temperatur' }).Count | Should -Be 0
        @($r | Where-Object { $_.Art -eq 'Takt' }).Count | Should -Be 0
        @($r | Where-Object { $_.Geraet -match 'Remote' }).Count | Should -Be 0
        @($r | Where-Object { $_.Art -eq 'Lüfter' }).Wert | Should -Be 1500
    }
    It 'nennt den Grund, warum Werte fehlen, statt PawnIO zu vermuten' {
        Mock -ModuleName MinibenchTest Test-IsArm64 { $false }
        Set-ModuleVar 'Sens' ([pscustomobject]@{ Lhm = $false; LhmLief = $false; LhmGrund = 'fehlt'; LhmFehler = ''; TreiberOk = $false; Treiber = 'nicht verwendet' })
        MinibenchTest\Get-SensorGapText | Should -Match 'LibreHardwareMonitor fehlt im Tools-Ordner'
        MinibenchTest\Get-SensorGapText | Should -Not -Match 'PawnIO'
        Set-ModuleVar 'Sens' ([pscustomobject]@{ Lhm = $true; LhmLief = $true; LhmGrund = ''; LhmFehler = ''; TreiberOk = $false; Treiber = 'ohne PawnIO' })
        MinibenchTest\Get-SensorGapText | Should -Match 'ohne PawnIO-Treiber'
    }
    It 'Ersatzquellen (Grafiktreiber, Energiezähler) werden nur ohne LibreHardwareMonitor abgefragt' {
        Mock -ModuleName MinibenchTest Get-AcpiReadings { @() }
        Mock -ModuleName MinibenchTest Get-BatteryReadings { @() }
        Mock -ModuleName MinibenchTest Get-StorageTempReadings { @() }
        Mock -ModuleName MinibenchTest Get-WindowsGpuAdapters { @([pscustomobject]@{ Name = 'AMD Radeon RX 6800'; TempC = 55; CoreMhz = 2100; MemMhz = 1000; FanRpm = [double]::NaN; Load = 90 }) }
        Mock -ModuleName MinibenchTest Get-WindowsCpuPowerReading { MinibenchTest\New-SensorReading 'win/cpu/power' 'Windows' 'CPU' 'CPU' 'Leistung' 'CPU Package' 'W' 42 'CpuWindows' }
        $cpu = [pscustomobject]@{ MHz = 3600; Last = 5; MaxFreq = 100 }
        Set-ModuleVar 'Sens' (New-Sitzung $false)
        $r = MinibenchTest\Get-SensorReadings -CpuSample $cpu
        Should -Invoke -ModuleName MinibenchTest Get-WindowsGpuAdapters -Times 1 -Exactly
        Should -Invoke -ModuleName MinibenchTest Get-WindowsCpuPowerReading -Times 1 -Exactly
        @($r | Where-Object { $_.Gruppe -eq 'GPU' -and $_.Art -eq 'Temperatur' -and $_.Quelle -eq 'Windows' })[0].Wert | Should -Be 55
        @($r | Where-Object { $_.Gruppe -eq 'CPU' -and $_.Art -eq 'Leistung' })[0].Wert | Should -Be 42
        # mit LibreHardwareMonitor (hier ohne geöffnete Bibliothek): keine Ersatzquellen
        Set-ModuleVar 'Sens' (New-Sitzung $true)
        $r = MinibenchTest\Get-SensorReadings -CpuSample $cpu
        Should -Invoke -ModuleName MinibenchTest Get-WindowsGpuAdapters -Times 1 -Exactly
        Should -Invoke -ModuleName MinibenchTest Get-WindowsCpuPowerReading -Times 1 -Exactly
        @($r | Where-Object { $_.Gruppe -eq 'GPU' }).Count | Should -Be 0
    }
}

Describe 'ARM64-Erkennung' {
    BeforeEach {
        $script:ArchAlt = @($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432)
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'; $env:PROCESSOR_ARCHITEW6432 = $null
        $script:Cpu = [pscustomobject]@{ Name = 'Intel(R) Core(TM) i7-12700'; Architecture = 9 }
        $script:Os = [pscustomobject]@{ OSArchitecture = '64-Bit' }
        Mock -ModuleName MinibenchTest Get-CimCached { }
        Mock -ModuleName MinibenchTest Get-CimCached { $script:Cpu } -ParameterFilter { $Class -eq 'Win32_Processor' }
        Mock -ModuleName MinibenchTest Get-CimCached { $script:Os } -ParameterFilter { $Class -eq 'Win32_OperatingSystem' }
        Set-ModuleVar 'SensorGapReported' $false
        & (Get-Module MinibenchTest) { $script:TestFindings.Clear() }
    }
    AfterEach {
        $env:PROCESSOR_ARCHITECTURE = $script:ArchAlt[0]; $env:PROCESSOR_ARCHITEW6432 = $script:ArchAlt[1]
        Set-ModuleVar 'Sens' $null
        Set-ModuleVar 'SensorGapReported' $false
    }
    It 'x64-Prozessor und x64-Windows: kein ARM64' { MinibenchTest\Test-IsArm64 | Should -BeFalse }
    It 'Umgebungsvariable <V> = ARM64' -ForEach @(@{ V = 'PROCESSOR_ARCHITECTURE' }, @{ V = 'PROCESSOR_ARCHITEW6432' }) {
        Set-Item -Path ('env:' + $V) -Value 'ARM64'
        MinibenchTest\Test-IsArm64 | Should -BeTrue
    }
    It 'Prozessor <Fall>' -ForEach @(
        @{ Fall = 'mit Architektur 12 (ARM64)'; Name = 'Prozessor'; Arch = 12 }
        @{ Fall = 'mit Architektur 5 (ARM)'; Name = 'Prozessor'; Arch = 5 }
        @{ Fall = 'Snapdragon im Namen'; Name = 'Snapdragon(R) X Elite - X1E78100 - Qualcomm(R) Oryon(TM) CPU'; Arch = 9 }
    ) {
        $script:Cpu = [pscustomobject]@{ Name = $Name; Architecture = $Arch }
        MinibenchTest\Test-IsArm64 | Should -BeTrue
    }
    It 'Windows für ARM' {
        $script:Os = [pscustomobject]@{ OSArchitecture = 'ARM 64-Bit-Prozessor' }
        MinibenchTest\Test-IsArm64 | Should -BeTrue
    }
    It 'ohne Systemdaten: kein ARM64 statt Fehler' {
        # mit Filter, damit diese Attrappe vor denen aus BeforeEach greift (Pester wertet Attrappen mit Filter zuerst aus)
        Mock -ModuleName MinibenchTest Get-CimCached { throw 'WMI nicht erreichbar' } -ParameterFilter { $true }
        MinibenchTest\Test-IsArm64 | Should -BeFalse
    }
    It 'auf ARM64: Sitzung nennt ARM64 als Grund, Hinweis, Lücke und Befund statt LibreHardwareMonitor zu laden' {
        Mock -ModuleName MinibenchTest Test-IsArm64 { $true }
        Mock -ModuleName MinibenchTest Find-NvidiaSmi { '' }
        Mock -ModuleName MinibenchTest Remove-PawnIoLeftover { }
        Mock -ModuleName MinibenchTest Get-SensorToolState { [pscustomobject]@{ LhmDll = 'x'; LhmBereit = $true; Fehlend = @(); PawnIoSetup = '' } }
        Set-ModuleVar 'Sens' $null
        $s = MinibenchTest\Open-SensorSession
        $s.LhmGrund | Should -Be 'ARM64'
        $s.Lhm | Should -BeFalse
        ($s.Hinweise -join ' ') | Should -Match 'ARM64-Architektur erkannt'
        MinibenchTest\Get-SensorGapText | Should -Match '^ARM64-Architektur erkannt'
        MinibenchTest\Add-SensorGapFinding 'Lasttest'
        MinibenchTest\Add-SensorGapFinding 'Benchmark'
        @(Get-ModuleVar 'TestFindings').Count | Should -Be 1
        @(Get-ModuleVar 'TestFindings')[0].Stufe | Should -Be 'INFO'
        @(MinibenchTest\Get-SensorSnapshotFindings @() ([pscustomobject]@{ CpuTemp = $null; CpuTempQ = ''; GpuTemp = $null }))[0].Text | Should -Match 'ARM64-Architektur erkannt'
    }
    It 'die Diagnose prüft auf ARM64' {
        Get-SrcText 'Module/Diagnose/Ablauf.ps1' | Should -Match 'if \(Test-IsArm64\)'
    }
}

Describe 'CIM-Abfragen zwischenspeichern' {
    BeforeEach {
        Set-ModuleVar 'CimCache' @{}
        Mock -ModuleName MinibenchTest Get-CimInstance { [pscustomobject]@{ Caption = 'Testsystem' } }
    }
    AfterEach { Set-ModuleVar 'CimCache' @{} }
    It 'fragt jede Klasse einmal je Lauf ab und liefert danach dasselbe Ergebnis' {
        $a = MinibenchTest\Get-CimCached 'Win32_OperatingSystem'
        $b = MinibenchTest\Get-CimCached 'Win32_OperatingSystem'
        $a.Caption | Should -Be 'Testsystem'
        [object]::ReferenceEquals($a, $b) | Should -BeTrue
        Should -Invoke -ModuleName MinibenchTest Get-CimInstance -Times 1 -Exactly
    }
    It 'Klassen und Namensräume werden getrennt zwischengespeichert' {
        [void](MinibenchTest\Get-CimCached 'Win32_Processor')
        [void](MinibenchTest\Get-CimCached 'BatteryStatus' 'root\wmi')
        [void](MinibenchTest\Get-CimCached 'BatteryStatus' 'root\wmi')
        [void](MinibenchTest\Get-CimCached 'Win32_Processor')
        Should -Invoke -ModuleName MinibenchTest Get-CimInstance -Times 2 -Exactly
        @((Get-ModuleVar 'CimCache').Keys | Sort-Object) | Should -Be @('root\wmi:BatteryStatus', 'Win32_Processor')
    }
}

Describe 'Kurven im Bericht' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Werkzeuge.ps1', 'Kern\Sensoren.ps1' -Functions 'Get-SafeName', 'ConvertTo-HtmlText', 'New-MultiLineSvg', 'Get-ChartScale', 'Get-ChartMarkLayout', 'New-LoadChartsHtml'
    }
    It 'zeichnet mehrere Serien mit Legende, Schwelle und Markierung' {
        $a = @(0..20 | ForEach-Object { [pscustomobject]@{ T = $_ * 3; V = 60 + $_ } }); $b = @(0..20 | ForEach-Object { [pscustomobject]@{ T = $_ * 3; V = 50 } })
        $svg = MinibenchTest\New-MultiLineSvg @(@{ Name = 'CPU'; Cls = 's1'; Points = $a }, @{ Name = 'GPU'; Cls = 's2'; Points = $b }, @{ Name = 'leer'; Cls = 's3'; Points = @() }) '°C' @(@{ V = 95; Label = 'Abbruchschwelle'; Cls = 'lim' }) @(@{ T = 30; Label = 'Abbruch' })
        ([regex]::Matches($svg, '<polyline')).Count | Should -Be 2
        $svg | Should -Match 'class="lim"'
        $svg | Should -Match 'Abbruch'
        $svg | Should -Not -Match 'leer'
        $svg | Should -Match 'max 80'
    }
    It 'liefert nichts ohne Daten' { MinibenchTest\New-MultiLineSvg @(@{ Name = 'CPU'; Cls = 's1'; Points = @() }) '°C' | Should -BeNullOrEmpty }
    It 'Lasttest-Abschnitt mit Drosselnachweis und Kurven' {
        $series = New-Series 30 { param($i) if ($i -lt 6) { 4700 } else { 3800 } } { 99 } { 150 }
        foreach ($x in $series) { $x | Add-Member GpuTemp 60; $x | Add-Member GpuMHz 1800; $x | Add-Member GpuW 80; $x | Add-Member Fan 1400; $x | Add-Member DiskTemp 45; $x | Add-Member Temp 30 }
        Set-ModuleVar 'LoadSeries' $series
        Set-ModuleVar 'LoadThrottle' (MinibenchTest\Get-ThrottleAnalysis $series 100)
        Set-ModuleVar 'LoadLimits' ([pscustomobject]@{ Cpu = 100; Gpu = 90; TjMax = 100 })
        Set-ModuleVar 'LoadAbort' $null
        $h = MinibenchTest\New-LoadChartsHtml
        $h | Should -Match 'Drosselnachweis: Thermische Drosselung'
        foreach ($t in 'Temperatur', 'Takt', 'Leistung', 'Lüfter') { $h | Should -Match ('<h3>{0}' -f $t) }
        $h | Should -Match 'Abbruchschwelle CPU 100'
        $h | Should -Not -Match 'ohne LibreHardwareMonitor'
    }
    It 'Hinweis, wenn keine echte CPU-Temperatur vorlag' {
        $series = New-Series 12 { 3000 } { $null } { $null }
        foreach ($x in $series) { $x | Add-Member Temp 28; $x | Add-Member GpuTemp $null; $x | Add-Member GpuMHz $null; $x | Add-Member GpuW $null; $x | Add-Member Fan $null; $x | Add-Member DiskTemp $null }
        Set-ModuleVar 'LoadSeries' $series; Set-ModuleVar 'LoadThrottle' $null; Set-ModuleVar 'LoadLimits' $null
        # ab v2.8 mit dem tatsächlichen Grund (bis v2.7 hieß es immer, der PawnIO-Treiber fehle)
        Set-ModuleVar 'Sens' ([pscustomobject]@{ Lhm = $false; LhmLief = $false; LhmGrund = 'fehlt'; LhmFehler = ''; TreiberOk = $false; Treiber = 'nicht verwendet' })
        $h = MinibenchTest\New-LoadChartsHtml
        $h | Should -Match 'Keine echte CPU-Temperatur und keine CPU-Leistung: LibreHardwareMonitor fehlt'
        Set-ModuleVar 'Sens' ([pscustomobject]@{ Lhm = $true; LhmLief = $true; LhmGrund = ''; LhmFehler = ''; TreiberOk = $false; Treiber = 'ohne PawnIO' })
        MinibenchTest\New-LoadChartsHtml | Should -Match 'PawnIO-Treiber'
        Set-ModuleVar 'Sens' $null
    }
}
