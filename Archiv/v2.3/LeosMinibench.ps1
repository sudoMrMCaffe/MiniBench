#Requires -Version 5.1
# Diese Datei erzeugt Bauen.cmd aus dem Ordner src. Änderungen bitte in src vornehmen, nicht hier.
<#
.SYNOPSIS
    Leos Minibench: Diagnose, Benchmark, Lasttest, Reparatur und Sensoren für Windows 10 und 11 mit grafischer Oberfläche.

.DESCRIPTION
    Gedacht für den Betrieb von einem USB-Stick. Alles, was das Werkzeug schreibt, landet im Ordner
    "Minibench-Daten" neben LeosMinibench.exe bzw. LeosMinibench.ps1:

      Minibench-Daten\Berichte\<PC>_<Datum>   Bericht (HTML, TXT), KI-Dateien, Anhang.zip
      Minibench-Daten\Berichte\Vergleiche     Systemvergleiche aus der Datenbank
      Minibench-Daten\Datenbank                ein JSON-Eintrag je Lauf (Vergleichsdatenbank)
      Minibench-Daten\Tools                    portable Werkzeuge (smartctl, LibreHardwareMonitor, PawnIO) mit Manifest Tools.json (SHA-256)
      Minibench-Daten\Änderungen\<PC>          Änderungsprotokoll je Lauf mit Vorher-Werten, Grundlage für Rückgängig
      Minibench-Daten\Laufzeit\<PC>            Checkpoints für die Absturzanalyse, während eines Laufs
      Minibench-Daten\Cache                    kompilierte Oberfläche und Testroutinen (schnellerer Start)

    Auf dem geprüften PC bleiben keine Dateien des Werkzeugs zurück. Am Ende jedes Laufs prüft eine
    Rückstandskontrolle die bekannten Orte und räumt Reste auf (auch solche älterer Versionen).

    Module: Diagnose (Inventar, Prüfungen, Ereignisprotokolle), Benchmark (CPU, RAM, Grafik, Laufwerke, WinSAT),
    Lasttest (CPU, RAM, Grafik, Datenträger mit eigener Dauer, Temperaturkurven, Drosselnachweis, Abbruchschwelle),
    Reparatur (SFC, DISM und weitere), Sensoren live (Temperatur, Takt, Lüfter, Spannung, Leistung).
    Die Seite Vergleichsdatenbank vergleicht bereits geprüfte Systeme ohne neuen Benchmark.
    Die Seite Änderungen zeigt, was das Werkzeug an einem PC verändert hat, und nimmt Änderungen zurück.

    Aufbau: Jedes Modul beschreibt sich in einem Modulvertrag (src\Module\<Name>\Vertrag.psd1) mit Risikostufe je Schritt:
    Lesen, Ändern (protokolliert, rückgängig machbar), Eingriff (Wiederherstellungspunkt), Zerstörend (Bestätigung per Seriennummer).

    Alle Parameter verwendet die Oberfläche intern für den Arbeitsprozess (-EventMode).

.EXAMPLE
    LeosMinibench.exe oder LeosMinibench.cmd starten.
#>
[CmdletBinding()]
param(
    [string]$Module = '',
    # Diagnose
    [string]$DiagProfil = 'Voll',
    [string]$DiagOptionen = '',
    [switch]$AnalyzeLastRun,
    [switch]$InstallSmartmontools,
    [switch]$ScheduleWindowsMemTest,
    [ValidateRange(1, 365)]  [int]$EventDays = 14,
    [ValidateRange(5, 90)]   [int]$RamTestPercent = 60,
    [ValidateRange(1, 50)]   [int]$RamTestPasses = 3,
    [ValidateRange(10, 7200)][int]$CpuStressSeconds = 180,
    [ValidateRange(5, 1440)] [int]$SmartTimeoutMinutes = 360,
    # Benchmark
    [string]$BenchTests = 'CPU,RAM,GPU,Disk',
    [string]$BenchLaufwerke = '',
    [switch]$BenchmarkKurz,
    [switch]$ReferenzSpeichern,
    [string]$ReferenzDatei,
    [string]$VergleichDateien = '',
    [switch]$KeineDatenbank,
    # Lasttest
    [ValidateRange(0, 480)] [int]$LastCpuMinuten = 0,
    [ValidateRange(0, 480)] [int]$LastRamMinuten = 0,
    [ValidateRange(0, 480)] [int]$LastGpuMinuten = 0,
    [ValidateRange(0, 480)] [int]$LastDiskMinuten = 0,
    [ValidateRange(5, 90)]  [int]$LastRamProzent = 40,
    [string]$LastDiskLaufwerk = '',
    # Abbruchschwelle in °C: auto (TjMax, sonst 100), aus oder Zahl
    [string]$LastAbbruchCpu = 'auto',
    [string]$LastAbbruchGpu = '90',
    # Sensoren (Live-Ansicht, PawnIO-Treiber nur nach Rückfrage, Werkzeuge holen)
    [switch]$SensorLive,
    [switch]$SensorTreiber,
    [switch]$SensorWerkzeugeHolen,
    [switch]$SensorAufraeumen,
    [ValidateRange(500, 10000)] [int]$SensorIntervall = 1000,
    # Reparatur
    [string]$Reparaturen = '',
    [switch]$OhneWiederherstellungspunkt,
    # Allgemein
    [switch]$KiOhneAnonymisierung,
    [string]$DatenDir,
    [string]$OutputDir,
    [string]$ImportOrdner,
    [string]$Vergleich,
    [string]$Rueckgaengig,
    [switch]$EventMode
)

# Unbehandelte Fehler protokollieren statt kommentarlos abzubrechen
trap {
    $msg = $_.Exception.Message
    $ln = $(if ($_.InvocationInfo) { $_.InvocationInfo.ScriptLineNumber } else { '?' })
    try { Write-Host ('ABBRUCH durch Fehler: {0} (Zeile {1})' -f $msg, $ln) -ForegroundColor Red } catch { }
    try { if ($OutputDir -and (Test-Path $OutputDir)) { ($_ | Out-String) | Out-File (Join-Path $OutputDir 'Fehler.txt') -Append -Encoding UTF8 } } catch { }
    try { if ($script:CpStream) { Write-Checkpoint 'ABBRUCH' ('Skriptfehler: {0} (Zeile {1})' -f $msg, $ln); Close-Checkpoint -RemoveFlag } } catch { }
    if (-not $EventMode) {
        try { Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show(('Leos Minibench wurde wegen eines Fehlers beendet:' + "`r`n`r`n" + $msg + "`r`n(Zeile " + $ln + ')'), 'Leos Minibench', 'OK', 'Error') } catch { }
    }
    break
}

#region ---------- Ereigniskanal zur grafischen Oberfläche ----------
$script:GuiOut = $null
$script:GuiLog = $null
function Send-GuiEvent {
    param([string]$Kind, [Parameter(ValueFromRemainingArguments = $true)][object[]]$Parts)
    if (-not $script:GuiOut) { return }
    $clean = @($Parts | ForEach-Object { (([string]$_) -replace '[\r\n]+', ' ') -replace '\|', '¦' })
    try { $script:GuiOut.WriteLine('@@' + $Kind + '|' + ($clean -join '|')) } catch { }
}
if ($EventMode) {
    try {
        $script:GuiOut = New-Object IO.StreamWriter([Console]::OpenStandardOutput(), (New-Object Text.UTF8Encoding($false)))
        $script:GuiOut.AutoFlush = $true
    } catch { }
    # Ausgaben als Ereignisse an die Oberfläche senden und mitprotokollieren
    function Write-Host {
        param([Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object, $ForegroundColor, $BackgroundColor, [switch]$NoNewline, $Separator)
        $t = (@($Object) | ForEach-Object { [string]$_ }) -join ' '
        Send-GuiEvent 'LOG' ([string]$ForegroundColor) $t
        if ($script:GuiLog) { try { $script:GuiLog.WriteLine($t) } catch { } }
    }
    function Write-Warning { param([Parameter(Position = 0)][string]$Message) Write-Host ('WARNUNG: ' + $Message) -ForegroundColor Yellow }
}
#endregion

#region ---------- Kodierung prüfen ----------
# Fehlt der Datei das UTF-8-Kennzeichen (BOM), liest Windows PowerShell 5.1 sie als ANSI und die Umlaute
# werden zerstört. Das Skript erkennt das, legt eine korrekt kodierte Kopie an und startet sich daraus neu.
if ('ä' -ne [string][char]0xE4 -and $PSCommandPath) {
    $bytes = [IO.File]::ReadAllBytes($PSCommandPath)
    try   { $txt = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes) }
    catch { $txt = [Text.Encoding]::Default.GetString($bytes) }
    $fixed = Join-Path $env:TEMP ('LeosMinibench_utf8_{0}.ps1' -f $PID)
    [IO.File]::WriteAllText($fixed, $txt.TrimStart([char]0xFEFF), (New-Object Text.UTF8Encoding($true)))
    $pass = @()
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [System.Management.Automation.SwitchParameter]) { if ($kv.Value.IsPresent) { $pass += ('-' + $kv.Key) } }
        else { $pass += ('-' + $kv.Key); $pass += [string]$kv.Value }
    }
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $fixed @pass
    $rc = $LASTEXITCODE
    Remove-Item $fixed -Force -ErrorAction SilentlyContinue
    exit $rc
}
#endregion

#region ---------- Administratorrechte ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# Vergleich und Import lesen nur die Datenbank und brauchen keine Administratorrechte
if (-not $isAdmin -and -not $Vergleich -and -not $ImportOrdner) {
    if (-not $PSCommandPath) { return }
    # Netzlaufwerke sind im Administratorkontext nicht verbunden: Skript und Datenordner als UNC-Pfad weitergeben
    function ConvertTo-Unc([string]$Path) {
        if ($Path -match '^[A-Za-z]:') {
            try { $drv = Get-PSDrive -Name $Path.Substring(0, 1) -ErrorAction Stop; if ($drv.DisplayRoot -like '\\*') { return $drv.DisplayRoot.TrimEnd('\') + $Path.Substring(2) } } catch { }
        }
        return $Path
    }
    if (-not $DatenDir -and $PSScriptRoot) { $DatenDir = Join-Path $PSScriptRoot 'Minibench-Daten' }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f (ConvertTo-Unc $PSCommandPath)))
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Key -eq 'DatenDir') { continue }
        if ($kv.Value -is [System.Management.Automation.SwitchParameter]) { if ($kv.Value.IsPresent) { $argList += ('-{0}' -f $kv.Key) } }
        else { $argList += ('-{0}' -f $kv.Key); $argList += ('"{0}"' -f $kv.Value) }
    }
    if ($DatenDir) { $argList += '-DatenDir'; $argList += ('"{0}"' -f (ConvertTo-Unc $DatenDir).TrimEnd('\')) }
    try { Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList -ErrorAction Stop }
    catch {
        try { Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show(('Start mit Administratorrechten nicht möglich: ' + $_.Exception.Message), 'Leos Minibench', 'OK', 'Warning') } catch { }
    }
    return
}
#endregion

$ScriptVersion = '2.3'
$AppName       = 'Leos Minibench'

#region ---------- Datenordner neben exe bzw. Skript (Berichte, Vergleichsdatenbank, Tools, Laufzeitdaten) ----------
function Test-WritableDir([string]$Dir) {
    if (-not $Dir) { return $false }
    try {
        New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop | Out-Null
        $probe = Join-Path $Dir ('.schreibtest_{0}.tmp' -f $PID)
        [IO.File]::WriteAllText($probe, 'x'); Remove-Item $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}
function Resolve-DataDir {
    $cands = @()
    if ($DatenDir) { $cands += $DatenDir.TrimEnd('\') }
    if ($PSScriptRoot -and $PSScriptRoot -notlike "$env:TEMP*") { $cands += (Join-Path $PSScriptRoot 'Minibench-Daten') }
    foreach ($c in $cands) {
        # frühere Versionen: Ordner PC-Diagnose-Daten daneben übernehmen
        $old = Join-Path (Split-Path $c -Parent) 'PC-Diagnose-Daten'
        if (-not (Test-Path -LiteralPath $c) -and (Test-Path -LiteralPath $old)) { try { Rename-Item -LiteralPath $old -NewName (Split-Path $c -Leaf) -ErrorAction Stop } catch { } }
        if (Test-WritableDir $c) { return $c }
    }
    # Notlösung bei schreibgeschütztem Speicherort (z. B. gesperrter USB-Stick): Dokumente des Benutzers
    $doc = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Leos Minibench'
    if (Test-WritableDir $doc) { $script:DataDirFallback = $true; return $doc }
    return ''
}
$script:DataDirFallback = $false
$script:DataDir  = Resolve-DataDir
$script:DbDir    = $(if ($script:DataDir) { Join-Path $script:DataDir 'Datenbank' } else { '' })
$script:CacheDir = $(if ($script:DataDir) { Join-Path $script:DataDir 'Cache' } else { '' })
$script:CpDir    = $(if ($script:DataDir) { Join-Path (Join-Path $script:DataDir 'Laufzeit') $env:COMPUTERNAME } else { Join-Path $env:TEMP ('LeosMinibench_' + $env:COMPUTERNAME) })

# C#-Code einmal kompilieren und als DLL im Datenordner zwischenspeichern (spart bei jedem Start einige Sekunden)
function Add-CachedType([string]$Name, [string]$Code, [string[]]$References = @()) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Code + ($References -join ';') + $PSVersionTable.CLRVersion)) | Select-Object -First 6 | ForEach-Object { $_.ToString('x2') })
    $p = @{ TypeDefinition = $Code; ErrorAction = 'Stop' }
    if ($References.Count) { $p.ReferencedAssemblies = $References }
    if ($script:CacheDir -and (Test-WritableDir $script:CacheDir)) {
        $dll = Join-Path $script:CacheDir ('{0}-{1}.dll' -f $Name, $hash)
        if (-not (Test-Path -LiteralPath $dll)) {
            Get-ChildItem -LiteralPath $script:CacheDir -Filter ('{0}-*.dll' -f $Name) -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            try { Add-Type @p -OutputAssembly $dll -OutputType Library } catch { Remove-Item $dll -Force -ErrorAction SilentlyContinue }
        }
        if (Test-Path -LiteralPath $dll) { try { Add-Type -Path $dll -ErrorAction Stop; return } catch { } }
    }
    Add-Type @p
}
#endregion


#region ---------- Risikostufen ----------
# Jeder Schritt eines Moduls hat eine Risikostufe. Sie bestimmt, welche Absicherung vor der Ausführung nötig ist:
#   Lesen        verändert nichts am System
#   Aendern      verändert Einstellungen; jede Änderung landet mit Vorher-Wert im Änderungsprotokoll und lässt sich rückgängig machen
#   Eingriff     verändert das System dauerhaft ohne automatisches Rückgängig; Wiederherstellungspunkt vorab, oft Neustart
#   Zerstoerend  vernichtet Daten; nur nach eigener Bestätigung mit der Seriennummer des Ziels
$script:RiskOrder  = @('Lesen', 'Aendern', 'Eingriff', 'Zerstoerend')
$script:RiskLabels = @{ Lesen = 'Lesen'; Aendern = 'Ändern'; Eingriff = 'Eingriff'; Zerstoerend = 'Zerstörend' }

function Get-RiskRank([string]$Level) {
    $i = [array]::IndexOf($script:RiskOrder, [string]$Level)
    if ($i -lt 0) { throw ('Unbekannte Risikostufe: {0}' -f $Level) }
    return $i
}

function Get-RiskLabel([string]$Level) {
    if ($script:RiskLabels.ContainsKey([string]$Level)) { return $script:RiskLabels[[string]$Level] }
    return [string]$Level
}

# Höchste Stufe aus einer Liste; leere Liste ergibt Lesen
function Get-MaxRisk($Levels) {
    $max = 0
    foreach ($l in @($Levels)) { if ($l) { $r = Get-RiskRank $l; if ($r -gt $max) { $max = $r } } }
    return $script:RiskOrder[$max]
}

# Seriennummern vergleichen, ohne dass Leerzeichen, Bindestriche oder Groß- und Kleinschreibung stören
function ConvertTo-SerialKey([string]$Serial) { return (([string]$Serial) -replace '[\s\-_.]', '').ToUpperInvariant() }

# Freigabe für zerstörende Schritte: Die eingegebene Seriennummer muss vollständig zum Ziel passen.
# Platzhalter wie "Default string" oder leere Seriennummern werden nie akzeptiert, weil sie das Ziel nicht eindeutig benennen.
function Test-DestructiveConfirmation {
    param([string]$ExpectedSerial, [string]$GivenSerial)
    $exp = ConvertTo-SerialKey $ExpectedSerial
    $giv = ConvertTo-SerialKey $GivenSerial
    if ($exp.Length -lt 4 -or $exp -match '^(0+|F+|DEFAULTSTRING|TOBEFILLEDBYOEM|SYSTEMSERIALNUMBER|NONE|NA|UNKNOWN)$') { return $false }
    return ($exp -ceq $giv)
}

# Prüft vor einem Schritt, ob die Absicherung seiner Stufe vorhanden ist. Rückgabe: leer = darf laufen, sonst Begründung.
function Get-RiskBlocker {
    # Eingriff ohne Wiederherstellungspunkt bleibt erlaubt (Schalter -OhneWiederherstellungspunkt), der Bericht vermerkt es.
    param([string]$Level, [string]$ExpectedSerial = '', [string]$GivenSerial = '', [bool]$SystemDisk = $false)
    if ((Get-RiskRank $Level) -eq 3) {
        if ($SystemDisk) { return 'Das Systemlaufwerk des laufenden Windows ist für zerstörende Schritte gesperrt.' }
        if (-not (Test-DestructiveConfirmation $ExpectedSerial $GivenSerial)) { return 'Die eingegebene Seriennummer passt nicht zum gewählten Ziel.' }
    }
    return ''
}
#endregion
#region ---------- Modulvertrag ----------
# Jedes Modul beschreibt sich in src\Module\<Name>\Vertrag.psd1. Bauen.cmd bindet die Verträge hier ein.
#
#   Vertrag          Version des Vertragsformats (derzeit 1)
#   Name             Modulname, zugleich Wert für -Module
#   Seite            Titel und Kurzbeschreibung in der Navigation der Oberfläche
#   Admin            braucht Administratorrechte
#   Risiko           höchste Risikostufe, die das Modul erreichen kann (Lesen, Aendern, Eingriff, Zerstoerend)
#   Neustart         nie, moeglich oder immer (höchster Bedarf unter den Schritten)
#   Parameter        Skriptparameter, die zum Modul gehören
#   Datenbankfelder  Felder, die das Modul in den Datenbankeintrag schreibt
#   Schritte         Key, Typ, Titel, Risiko, Neustart, Rueckgaengig (keins, Protokoll, Wiederherstellungspunkt, Hinweis)
#                    Maßnahmen der Reparatur zusätzlich: Text, Minuten, Vorauswahl, Ueblich (für die Seite Reparatur)
#
# Die @@-Zeilen zwischen Arbeitsprozess und Oberfläche bleiben das Protokoll; der Vertrag beschreibt nur, was ein Modul ist.
$script:ModuleContracts = @(
# Modulvertrag Diagnose (Vertrag 1). Felder sind in src\Kern\Modulvertrag.ps1 beschrieben.
@{
    Vertrag         = 1
    Name            = 'Diagnose'
    Seite           = @{ Titel = 'Diagnose'; Kurz = 'Inventar, Prüfungen, Ereignisse' }
    Admin           = $true
    Risiko          = 'Eingriff'
    Neustart        = 'immer'
    Parameter       = @('DiagProfil', 'DiagOptionen', 'AnalyzeLastRun', 'InstallSmartmontools', 'ScheduleWindowsMemTest', 'EventDays', 'RamTestPercent', 'RamTestPasses', 'CpuStressSeconds', 'SmartTimeoutMinutes')
    Datenbankfelder = @('System', 'Hardware', 'Befunde')
    Schritte        = @(
        @{ Key = 'Ereignisse';     Typ = 'Pruefung'; Titel = 'Ereignisprotokolle und Absturzanalyse';  Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'Updatesuche';    Typ = 'Pruefung'; Titel = 'Suche nach ausstehenden Updates';         Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'Integritaet';    Typ = 'Pruefung'; Titel = 'Dateisystem und Systemdateien (nur prüfen)'; Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'Defender';       Typ = 'Pruefung'; Titel = 'Defender Schnellscan';                    Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'SmartLang';      Typ = 'Pruefung'; Titel = 'SMART-Langtest';                          Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'Netzwerk';       Typ = 'Pruefung'; Titel = 'Netzwerktest';                            Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'RamTest';        Typ = 'Pruefung'; Titel = 'RAM-Mustertest';                          Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'CpuTest';        Typ = 'Pruefung'; Titel = 'CPU-Stabilität';                          Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'Energieanalyse'; Typ = 'Pruefung'; Titel = 'Energieanalyse und DxDiag';               Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        # Zusatzoptionen der Seite Diagnose
        @{ Key = 'Speicherdiagnose';   Typ = 'Option'; Titel = 'Windows-Speicherdiagnose beim nächsten Neustart'; Risiko = 'Lesen';    Neustart = 'immer'; Rueckgaengig = 'keins'; Schalter = 'ScheduleWindowsMemTest' }
        @{ Key = 'SmartmontoolsHolen'; Typ = 'Option'; Titel = 'smartmontools per winget holen und wieder entfernen'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Schalter = 'InstallSmartmontools' }
    )
}
# Modulvertrag Benchmark (Vertrag 1). Felder sind in src\Kern\Modulvertrag.ps1 beschrieben.
@{
    Vertrag         = 1
    Name            = 'Benchmark'
    Seite           = @{ Titel = 'Benchmark'; Kurz = 'Wählbare Messungen mit Vergleich' }
    Admin           = $true
    Risiko          = 'Lesen'
    Neustart        = 'nie'
    Parameter       = @('BenchTests', 'BenchLaufwerke', 'BenchmarkKurz', 'ReferenzSpeichern', 'ReferenzDatei', 'VergleichDateien', 'KeineDatenbank')
    Datenbankfelder = @('Werte', 'Messwerte', 'Messdauer', 'Laufwerke')
    Schritte        = @(
        @{ Key = 'CPU';    Typ = 'Messung'; Titel = 'Prozessor';             Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'RAM';    Typ = 'Messung'; Titel = 'Arbeitsspeicher';       Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'GPU';    Typ = 'Messung'; Titel = 'Grafik';                Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        # Testdatei LeosMinibench-Benchmark.tmp wird nach der Messung gelöscht, die Rückstandskontrolle prüft das
        @{ Key = 'Disk';   Typ = 'Messung'; Titel = 'Laufwerke';             Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        # WinSAT schreibt nur in den eigenen Datenspeicher von Windows
        @{ Key = 'WinSAT'; Typ = 'Messung'; Titel = 'WinSAT-Bewertung';      Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
    )
}
# Modulvertrag Lasttest (Vertrag 1). Felder sind in src\Kern\Modulvertrag.ps1 beschrieben.
@{
    Vertrag         = 1
    Name            = 'Lasttest'
    Seite           = @{ Titel = 'Lasttest'; Kurz = 'Komponenten und Dauer wählbar' }
    Admin           = $true
    Risiko          = 'Lesen'
    Neustart        = 'nie'
    Parameter       = @('LastCpuMinuten', 'LastRamMinuten', 'LastGpuMinuten', 'LastDiskMinuten', 'LastRamProzent', 'LastDiskLaufwerk', 'LastAbbruchCpu', 'LastAbbruchGpu')
    Datenbankfelder = @('Lasttest')
    Schritte        = @(
        @{ Key = 'CPU';  Typ = 'Last'; Titel = 'CPU';         Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'RAM';  Typ = 'Last'; Titel = 'RAM';         Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'GPU';  Typ = 'Last'; Titel = 'Grafik';      Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        # Testdatei LeosMinibench-Lasttest.tmp wird am Ende gelöscht, die Rückstandskontrolle prüft das
        @{ Key = 'Disk'; Typ = 'Last'; Titel = 'Datenträger'; Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
    )
}
# Modulvertrag Reparatur (Vertrag 1). Felder sind in src\Kern\Modulvertrag.ps1 beschrieben.
# Reihenfolge der Schritte = Ausführungsreihenfolge. Text, Minuten, Vorauswahl und Ueblich steuern die Seite Reparatur.
@{
    Vertrag         = 1
    Name            = 'Reparatur'
    Seite           = @{ Titel = 'Reparatur'; Kurz = 'SFC, DISM und weitere Fixes' }
    Admin           = $true
    Risiko          = 'Eingriff'
    Neustart        = 'immer'
    Parameter       = @('Reparaturen', 'OhneWiederherstellungspunkt')
    Datenbankfelder = @()
    Schritte        = @(
        @{ Key = 'DismRestore'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Rueckgaengig = 'Wiederherstellungspunkt'; Minuten = 20; Vorauswahl = $true; Ueblich = $true
           Titel = 'Komponentenspeicher prüfen und reparieren (DISM)'
           Text  = 'Komponentenspeicher prüfen und reparieren (DISM ScanHealth, bei Bedarf RestoreHealth)' }
        @{ Key = 'Sfc'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Rueckgaengig = 'Wiederherstellungspunkt'; Minuten = 12; Vorauswahl = $true; Ueblich = $true
           Titel = 'Systemdateien reparieren (sfc /scannow)'
           Text  = 'Systemdateien reparieren (sfc /scannow, nach DISM)' }
        @{ Key = 'Komponentenbereinigung'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 15; Vorauswahl = $false; Ueblich = $false
           Titel = 'Komponentenspeicher bereinigen (DISM)'
           Text  = 'Komponentenspeicher bereinigen (DISM StartComponentCleanup, gibt Platz frei)' }
        @{ Key = 'Dateisystem'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Rueckgaengig = 'keins'; Minuten = 5; Vorauswahl = $false; Ueblich = $true
           Titel = 'Dateisystemfehler beheben'
           Text  = 'Dateisystemfehler beheben (Onlinescan, SpotFix, Systemlaufwerk beim Neustart)' }
        @{ Key = 'WindowsUpdate'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'immer'; Rueckgaengig = 'Hinweis'; Minuten = 2; Vorauswahl = $false; Ueblich = $false
           Titel = 'Windows Update zurücksetzen'
           Text  = 'Windows Update zurücksetzen (Dienste, SoftwareDistribution, catroot2)' }
        @{ Key = 'Netzwerk'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'immer'; Rueckgaengig = 'Wiederherstellungspunkt'; Minuten = 1; Vorauswahl = $false; Ueblich = $false
           Titel = 'Netzwerk zurücksetzen'
           Text  = 'Netzwerk zurücksetzen (DNS-Cache, Winsock, TCP/IP), Neustart nötig' }
        @{ Key = 'Temp'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 3; Vorauswahl = $false; Ueblich = $true
           Titel = 'Temporäre Dateien löschen'
           Text  = 'Temporäre Dateien löschen (älter als 2 Tage, Übermittlungsoptimierung, Fehlerberichte)' }
        @{ Key = 'WMI'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'Wiederherstellungspunkt'; Minuten = 2; Vorauswahl = $false; Ueblich = $true
           Titel = 'WMI-Repository prüfen'
           Text  = 'WMI-Repository prüfen und bei Bedarf reparieren' }
        @{ Key = 'Zeit'; Typ = 'Massnahme'; Risiko = 'Aendern'; Neustart = 'nie'; Rueckgaengig = 'Protokoll'; Minuten = 1; Vorauswahl = $false; Ueblich = $false
           Titel = 'Zeit synchronisieren'
           Text  = 'Windows-Zeit neu synchronisieren' }
        @{ Key = 'Druck'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 1; Vorauswahl = $false; Ueblich = $false
           Titel = 'Druckwarteschlange leeren'
           Text  = 'Druckwarteschlange leeren und Druckspooler neu starten' }
        @{ Key = 'Geraete'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'Wiederherstellungspunkt'; Minuten = 1; Vorauswahl = $false; Ueblich = $false
           Titel = 'Geräte neu erkennen'
           Text  = 'Geräte neu erkennen lassen (pnputil /scan-devices)' }
        @{ Key = 'Schnellstart'; Typ = 'Massnahme'; Risiko = 'Aendern'; Neustart = 'nie'; Rueckgaengig = 'Protokoll'; Minuten = 1; Vorauswahl = $false; Ueblich = $false
           Titel = 'Schnellstart deaktivieren'
           Text  = 'Schnellstart deaktivieren (hilft bei Abstürzen nach dem Einschalten)' }
        @{ Key = 'Energieplaene'; Typ = 'Massnahme'; Risiko = 'Aendern'; Neustart = 'nie'; Rueckgaengig = 'Protokoll'; Minuten = 1; Vorauswahl = $false; Ueblich = $false
           Titel = 'Energiesparpläne zurücksetzen'
           Text  = 'Energiesparpläne auf Standard zurücksetzen (eigene Pläne werden vorher gesichert)' }
    )
}
# Modulvertrag Sensoren (Vertrag 1). Felder sind in src\Kern\Modulvertrag.ps1 beschrieben.
# Die Seite Sensoren zeigt Werte live; Diagnose (Momentaufnahme) und Lasttest (Kurven) nutzen dieselben Quellen.
@{
    Vertrag         = 1
    Name            = 'Sensoren'
    Seite           = @{ Titel = 'Sensoren live'; Kurz = 'Temperatur, Takt, Lüfter, Leistung' }
    Admin           = $true
    Risiko          = 'Eingriff'
    Neustart        = 'nie'
    Parameter       = @('SensorLive', 'SensorTreiber', 'SensorWerkzeugeHolen', 'SensorAufraeumen', 'SensorIntervall')
    Datenbankfelder = @('Sensoren')
    Schritte        = @(
        @{ Key = 'Live';      Typ = 'Anzeige';  Titel = 'Live-Ansicht';                    Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        # schreibt nur in Minibench-Daten\Tools auf dem Stick, nichts auf den PC
        @{ Key = 'Werkzeuge'; Typ = 'Werkzeug'; Titel = 'Sensorwerkzeuge holen';           Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        # Kerneltreiber nur nach Rückfrage, nur wenn er fehlt; wird am Ende des Laufs entfernt (nach Absturz beim nächsten Start)
        @{ Key = 'Treiber';   Typ = 'Treiber';  Titel = 'PawnIO-Treiber vorübergehend';    Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'Hinweis'; Schalter = 'SensorTreiber' }
    )
}
)
$script:ContractCoreDbFields = @('Format', 'Name', 'Computer', 'Geraet', 'Datum', 'Version', 'Quelle', 'Module', 'Ordner')
$script:RestartOrder = @('nie', 'moeglich', 'immer')
$script:UndoKinds = @('keins', 'Protokoll', 'Wiederherstellungspunkt', 'Hinweis')

function Get-ModuleContract([string]$Name) {
    foreach ($c in $script:ModuleContracts) { if ($c.Name -eq $Name) { return $c } }
    return $null
}

function Get-ModuleStep([string]$Module, [string]$Key) {
    $c = Get-ModuleContract $Module
    if (-not $c) { return $null }
    foreach ($s in $c.Schritte) { if ($s.Key -eq $Key) { return $s } }
    return $null
}

# Prüft einen Vertrag auf Vollständigkeit und Widersprüche. Rückgabe: Liste der Fehler (leer = in Ordnung).
function Test-ModuleContract($Contract, [string[]]$KnownParameters = @()) {
    $err = New-Object System.Collections.Generic.List[string]
    $n = $(if ($Contract -and $Contract.Name) { [string]$Contract.Name } else { '(ohne Namen)' })
    if (-not ($Contract -is [hashtable])) { $err.Add(('{0}: Vertrag ist keine Hashtable.' -f $n)); return $err.ToArray() }
    foreach ($f in 'Vertrag', 'Name', 'Seite', 'Admin', 'Risiko', 'Neustart', 'Parameter', 'Datenbankfelder', 'Schritte') {
        if (-not $Contract.ContainsKey($f)) { $err.Add(('{0}: Feld {1} fehlt.' -f $n, $f)) }
    }
    if ($err.Count) { return $err.ToArray() }
    if ($Contract.Vertrag -ne 1) { $err.Add(('{0}: Vertragsversion {1} wird nicht unterstützt.' -f $n, $Contract.Vertrag)) }
    if ($Contract.Name -notmatch '^[A-Za-z]+$') { $err.Add(('{0}: Name darf nur Buchstaben enthalten.' -f $n)) }
    if (-not $Contract.Seite.Titel -or -not $Contract.Seite.Kurz) { $err.Add(('{0}: Seite braucht Titel und Kurz.' -f $n)) }
    if (-not ($Contract.Admin -is [bool])) { $err.Add(('{0}: Admin muss $true oder $false sein.' -f $n)) }
    if ($script:RiskOrder -notcontains $Contract.Risiko) { $err.Add(('{0}: unbekannte Risikostufe {1}.' -f $n, $Contract.Risiko)) }
    if ($script:RestartOrder -notcontains $Contract.Neustart) { $err.Add(('{0}: Neustart muss nie, moeglich oder immer sein.' -f $n)) }
    foreach ($p in @($Contract.Parameter)) { if ($KnownParameters.Count -and $KnownParameters -notcontains $p) { $err.Add(('{0}: Parameter {1} gibt es im Skript nicht.' -f $n, $p)) } }
    foreach ($d in @($Contract.Datenbankfelder)) { if ($script:ContractCoreDbFields -contains $d) { $err.Add(('{0}: Datenbankfeld {1} gehört zum Kern.' -f $n, $d)) } }
    $steps = @($Contract.Schritte)
    if (-not $steps.Count) { $err.Add(('{0}: keine Schritte.' -f $n)) }
    $keys = @{}
    $maxR = 0; $maxN = 0
    foreach ($s in $steps) {
        $k = [string]$s.Key
        if (-not $k) { $err.Add(('{0}: Schritt ohne Key.' -f $n)); continue }
        if ($keys.ContainsKey($k)) { $err.Add(('{0}: Schritt {1} doppelt.' -f $n, $k)) }
        $keys[$k] = $true
        foreach ($f in 'Typ', 'Titel', 'Risiko', 'Neustart', 'Rueckgaengig') { if (-not $s.ContainsKey($f) -or -not [string]$s[$f]) { $err.Add(('{0}/{1}: Feld {2} fehlt.' -f $n, $k, $f)) } }
        if ($script:RiskOrder -notcontains $s.Risiko) { $err.Add(('{0}/{1}: unbekannte Risikostufe {2}.' -f $n, $k, $s.Risiko)); continue }
        if ($script:RestartOrder -notcontains $s.Neustart) { $err.Add(('{0}/{1}: Neustart muss nie, moeglich oder immer sein.' -f $n, $k)); continue }
        if ($script:UndoKinds -notcontains $s.Rueckgaengig) { $err.Add(('{0}/{1}: Rueckgaengig muss keins, Protokoll, Wiederherstellungspunkt oder Hinweis sein.' -f $n, $k)); continue }
        $r = Get-RiskRank $s.Risiko
        if ($r -gt $maxR) { $maxR = $r }
        $nr = [array]::IndexOf($script:RestartOrder, [string]$s.Neustart); if ($nr -gt $maxN) { $maxN = $nr }
        # Die Stufe legt fest, wie ein Schritt rückgängig zu machen ist
        switch ($s.Risiko) {
            'Lesen'       { if ($s.Rueckgaengig -ne 'keins') { $err.Add(('{0}/{1}: Lesen verändert nichts, Rueckgaengig muss keins sein.' -f $n, $k)) } }
            'Aendern'     { if ($s.Rueckgaengig -ne 'Protokoll') { $err.Add(('{0}/{1}: Ändern verlangt Rueckgaengig = Protokoll.' -f $n, $k)) } }
            'Eingriff'    { if ($s.Rueckgaengig -eq 'Protokoll') { $err.Add(('{0}/{1}: ein Eingriff ist nicht über das Protokoll umkehrbar, sonst wäre er Ändern.' -f $n, $k)) } }
            'Zerstoerend' { if ($s.Rueckgaengig -ne 'keins') { $err.Add(('{0}/{1}: Zerstörendes ist nicht umkehrbar, Rueckgaengig muss keins sein.' -f $n, $k)) } }
        }
        if ($s.Typ -eq 'Massnahme') {
            foreach ($f in 'Text', 'Minuten', 'Vorauswahl', 'Ueblich') { if (-not $s.ContainsKey($f)) { $err.Add(('{0}/{1}: Maßnahme braucht {2}.' -f $n, $k, $f)) } }
            if ($s.ContainsKey('Text') -and ([string]$s.Text).Contains('|')) { $err.Add(('{0}/{1}: Text darf kein | enthalten.' -f $n, $k)) }
        }
        if ($s.ContainsKey('Schalter') -and $KnownParameters.Count -and $KnownParameters -notcontains $s.Schalter) { $err.Add(('{0}/{1}: Schalter {2} gibt es im Skript nicht.' -f $n, $k, $s.Schalter)) }
    }
    if ($script:RiskOrder[$maxR] -ne $Contract.Risiko) { $err.Add(('{0}: Risiko {1} passt nicht zur höchsten Stufe der Schritte ({2}).' -f $n, $Contract.Risiko, $script:RiskOrder[$maxR])) }
    if ($script:RestartOrder[$maxN] -ne $Contract.Neustart) { $err.Add(('{0}: Neustart {1} passt nicht zu den Schritten ({2}).' -f $n, $Contract.Neustart, $script:RestartOrder[$maxN])) }
    return $err.ToArray()
}

# -Module "Diagnose,Benchmark" in bekannte Modulnamen übersetzen; Unbekanntes wird gemeldet und ignoriert
function Resolve-ModuleList([string]$Text) {
    $known = @{}
    foreach ($c in $script:ModuleContracts) { $known[$c.Name.ToLowerInvariant()] = $c.Name }
    $res = New-Object System.Collections.Generic.List[string]
    $unknown = New-Object System.Collections.Generic.List[string]
    foreach ($m in @(([string]$Text) -split '[,;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $k = $m.ToLowerInvariant()
        if ($known.ContainsKey($k)) { if (-not $res.Contains($known[$k])) { $res.Add($known[$k]) } } else { $unknown.Add($m) }
    }
    return [pscustomobject]@{ Module = $res.ToArray(); Unbekannt = $unknown.ToArray() }
}

# Kurzfassung der Verträge für die Oberfläche, eine Zeile je Eintrag:
#   M|Name|Titel|Kurz|Admin|Risiko|Neustart
#   S|Modul|Key|Typ|Risiko|Neustart|Rueckgaengig|Minuten|Vorauswahl|Ueblich|Text
function Get-ContractGuiLines {
    $l = New-Object System.Collections.Generic.List[string]
    $clean = { param($v) (([string]$v) -replace '[\r\n|]+', ' ').Trim() }
    foreach ($c in $script:ModuleContracts) {
        $l.Add(('M|{0}|{1}|{2}|{3}|{4}|{5}' -f $c.Name, (& $clean $c.Seite.Titel), (& $clean $c.Seite.Kurz), $(if ($c.Admin) { '1' } else { '0' }), $c.Risiko, $c.Neustart))
        foreach ($s in $c.Schritte) {
            $txt = $(if ($s.Text) { $s.Text } else { $s.Titel })
            $l.Add(('S|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}' -f $c.Name, $s.Key, $s.Typ, $s.Risiko, $s.Neustart, $s.Rueckgaengig, [int]$s.Minuten, $(if ($s.Vorauswahl) { '1' } else { '0' }), $(if ($s.Ueblich) { '1' } else { '0' }), (& $clean $txt)))
        }
    }
    return $l.ToArray()
}
#endregion
#region ---------- Geräteidentität ----------
# Eine Kennung je Gerät, die eine Neuinstallation von Windows und eine Umbenennung des PCs übersteht.
# Grundlage sind Mainboard und Firmware (SMBIOS): System-UUID, Hersteller, Modell und Seriennummer des Mainboards,
# Seriennummer im BIOS. In der Datenbank steht nur ein SHA-256-Hash, keine Seriennummer.
# Ein Tausch des Mainboards ergibt eine neue Kennung; das ist gewollt, denn danach ist es messtechnisch ein anderes Gerät.

# Werte, die Hersteller statt einer echten Kennung eintragen
function Test-PlaceholderId([string]$Value) {
    $v = ([string]$Value).Trim()
    if ($v.Length -lt 4) { return $true }
    if ($v -match '^(?i)(to be filled by o\.?e\.?m\.?|default string|system serial number|system product name|base board serial number|chassis serial number|not specified|not applicable|none|n/?a|unknown|invalid|o\.?e\.?m\.?|123456789|0123456789|x+|0+|f+)$') { return $true }
    # UUIDs ohne Aussagekraft: nur Nullen oder nur F, und die verbreitete Platzhalter-UUID vieler Boards
    $u = $v -replace '[{}\-\s]', ''
    if ($u -match '^(0+|F+)$' -or $u -eq '03000200040005000006000700080009') { return $true }
    return $false
}

function Get-Sha256Hex([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') })) }
    finally { $sha.Dispose() }
}

# Kennung aus den Rohwerten bilden. Güte: hoch (UUID und Seriennummer), mittel (eines von beiden), niedrig (nur Modell und Computername)
function ConvertTo-DeviceId {
    param([string]$Uuid, [string]$BoardVendor, [string]$BoardProduct, [string]$BoardSerial, [string]$BiosSerial, [string]$ComputerName)
    $norm = { param($s) (([string]$s) -replace '\s+', ' ').Trim().ToUpperInvariant() }
    $parts = New-Object System.Collections.Generic.List[string]
    $quellen = New-Object System.Collections.Generic.List[string]
    $strong = 0
    if (-not (Test-PlaceholderId $Uuid)) { $parts.Add('UUID=' + (& $norm ($Uuid -replace '[{}]', ''))); $quellen.Add('System-UUID'); $strong++ }
    $serial = $(if (-not (Test-PlaceholderId $BoardSerial)) { $BoardSerial; $quellen.Add('Seriennummer Mainboard') } elseif (-not (Test-PlaceholderId $BiosSerial)) { $BiosSerial; $quellen.Add('Seriennummer BIOS') } else { '' })
    if ($serial) { $parts.Add('SN=' + (& $norm $serial)); $strong++ }
    $model = ('{0} {1}' -f (& $norm $BoardVendor), (& $norm $BoardProduct)).Trim()
    if ($model -and -not (Test-PlaceholderId $model)) { $parts.Add('BOARD=' + $model); $quellen.Add('Mainboard-Modell') }
    if (-not $strong) {
        # Ohne eindeutige Firmwarewerte bleibt nur der Computername; die Kennung ist dann nicht besser als der Name
        $parts.Add('PC=' + (& $norm $ComputerName)); $quellen.Add('Computername')
    }
    $guete = $(if ($strong -ge 2) { 'hoch' } elseif ($strong -eq 1) { 'mittel' } else { 'niedrig' })
    return [pscustomobject]@{ Id = ('G-' + (Get-Sha256Hex ($parts -join ';')).Substring(0, 20)); Guete = $guete; Quellen = $quellen.ToArray() }
}

# Kennung dieses PCs (einmal je Lauf ermittelt)
$script:DeviceIdentity = $null
function Get-DeviceIdentity {
    if ($script:DeviceIdentity) { return $script:DeviceIdentity }
    $uuid = ''; $bv = ''; $bp = ''; $bs = ''; $bios = ''
    try { $uuid = [string](Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID } catch { }
    try { $bb = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1; $bv = [string]$bb.Manufacturer; $bp = [string]$bb.Product; $bs = [string]$bb.SerialNumber } catch { }
    try { $bios = [string](Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber } catch { }
    $script:DeviceIdentity = ConvertTo-DeviceId -Uuid $uuid -BoardVendor $bv -BoardProduct $bp -BoardSerial $bs -BiosSerial $bios -ComputerName $env:COMPUTERNAME
    return $script:DeviceIdentity
}

# Geräteschlüssel für alle Einträge setzen: Einträge mit Kennung behalten sie. Ältere Einträge ohne Kennung (Format 1,
# Importe) übernehmen die Kennung, wenn genau ein Gerät mit Kennung diesen Computernamen trägt, sonst gilt der Name.
function Set-DbDeviceKeys($Entries) {
    $byName = @{}
    foreach ($e in @($Entries)) {
        if ([string]$e.GeraetId) {
            $n = ([string]$e.Computer).ToUpperInvariant()
            if (-not $byName.ContainsKey($n)) { $byName[$n] = New-Object 'System.Collections.Generic.HashSet[string]' }
            [void]$byName[$n].Add([string]$e.GeraetId)
        }
    }
    foreach ($e in @($Entries)) {
        $n = ([string]$e.Computer).ToUpperInvariant()
        $key = $(if ([string]$e.GeraetId) { [string]$e.GeraetId } elseif ($byName.ContainsKey($n) -and $byName[$n].Count -eq 1) { @($byName[$n])[0] } else { 'PC:' + $n })
        $e | Add-Member -NotePropertyName GeraetKey -NotePropertyValue $key -Force
    }
}

# Gehört ein Datenbankeintrag zu diesem Gerät? Über die Kennung, bei älteren Einträgen ohne Zuordnung über den Computernamen.
function Test-SameDevice($Entry, [string]$DeviceId, [string]$ComputerName) {
    $key = [string]$Entry.GeraetKey
    if (-not $key) { $key = $(if ([string]$Entry.GeraetId) { [string]$Entry.GeraetId } else { 'PC:' + ([string]$Entry.Computer).ToUpperInvariant() }) }
    if ($key.StartsWith('G-')) { return ($DeviceId -and $key -eq $DeviceId) }
    return ([string]$Entry.Computer -eq $ComputerName)
}
#endregion
#region ---------- Änderungsprotokoll mit Rückgängig ----------
# Jede Änderung der Stufe Ändern speichert vor dem Schreiben den Vorher-Wert und das Wissen, wie sie umzukehren ist.
# Ablage je Lauf: Minibench-Daten\Änderungen\<PC>\<Datum>.json, gesicherte Dateien (z. B. Energiepläne) im gleichnamigen Ordner.
# Die Datei wird nach jedem Eintrag sofort geschrieben, damit sie auch einen Absturz mitten im Lauf übersteht.
# Eingriffe ohne automatisches Rückgängig erscheinen ebenfalls, mit dem Weg zurück als Hinweis (z. B. Wiederherstellungspunkt).
#
# Status eines Eintrags: aktiv (rückgängig machbar), rückgängig, übersprungen (Wert inzwischen anders), fehlgeschlagen, nur Hinweis
$script:ChangeFormat = 'Minibench-Aenderungen/1'
$script:ChangeFile   = ''
$script:ChangeLog    = $null
$script:ChangeCount  = 0

function Get-ChangeRoot { if ($script:DataDir) { return (Join-Path $script:DataDir 'Änderungen') } else { return '' } }

function Save-ChangeFile([string]$Path, $Log) {
    $dir = Split-Path $Path -Parent
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    $tmp = $Path + '.tmp'
    [IO.File]::WriteAllText($tmp, ($Log | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::Copy($tmp, $Path, $true)
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

function Read-ChangeFile([string]$Path) {
    try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    if (-not $j -or [string]$j.Format -ne $script:ChangeFormat) { return $null }
    return $j
}

# Lauf beginnen: Die Datei entsteht erst mit dem ersten Eintrag, Läufe ohne Änderungen hinterlassen nichts
function Start-ChangeLog {
    $root = Get-ChangeRoot
    if (-not $root) { $script:ChangeFile = ''; return }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:ChangeFile = Join-Path (Join-Path $root (Get-SafeName $env:COMPUTERNAME)) ($stamp + '.json')
    $dev = Get-DeviceIdentity
    $script:ChangeLog = [ordered]@{
        Format = $script:ChangeFormat; Computer = $env:COMPUTERNAME; GeraetId = $dev.Id; Version = $ScriptVersion
        Lauf = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture); Bericht = [string]$OutputDir; Eintraege = @()
    }
    $script:ChangeCount = 0
}

# Ordner für Sicherungsdateien dieses Laufs (gleicher Name wie die Protokolldatei ohne .json)
function Get-ChangeFilesDir { if ($script:ChangeFile) { return ($script:ChangeFile -replace '\.json$', '') } else { return '' } }

function Add-ChangeRecord {
    param(
        [string]$Modul, [string]$Schritt, [string]$Titel, [string]$Risiko, [string]$Art, [string]$Ziel,
        [string]$Vorher = '', [string]$Nachher = '', $Daten = $null, [string]$Gegenbefehl = '', [switch]$NurHinweis
    )
    if (-not $script:ChangeLog) { Start-ChangeLog }
    if (-not $script:ChangeFile) { return $null }
    $script:ChangeCount++
    $r = [ordered]@{
        Id = $script:ChangeCount; Zeit = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
        Modul = $Modul; Schritt = $Schritt; Titel = $Titel; Risiko = $Risiko; Art = $Art; Ziel = $Ziel; Vorher = $Vorher; Nachher = $Nachher
        Daten = $Daten; Gegenbefehl = $Gegenbefehl; Status = $(if ($NurHinweis) { 'nur Hinweis' } else { 'aktiv' }); Ergebnis = ''
    }
    $script:ChangeLog.Eintraege = @(@($script:ChangeLog.Eintraege) + [pscustomobject]$r)
    try { Save-ChangeFile $script:ChangeFile $script:ChangeLog } catch { Write-Warning ('Änderungsprotokoll konnte nicht geschrieben werden: {0}' -f $_.Exception.Message) }
    return [pscustomobject]$r
}

# ---------- Zugriffe auf das System (einzeln, damit Tests sie ersetzen können) ----------
function Get-RegValueState([string]$Path, [string]$Name) {
    $none = [pscustomobject]@{ Vorhanden = $false; Wert = $null; Typ = '' }
    try { $k = Get-Item -LiteralPath $Path -ErrorAction Stop } catch { return $none }
    if (@($k.GetValueNames()) -notcontains $Name) { return $none }
    return [pscustomobject]@{ Vorhanden = $true; Wert = $k.GetValue($Name, $null, 'DoNotExpandEnvironmentNames'); Typ = [string]$k.GetValueKind($Name) }
}

# Wert in den Registry-Typ wandeln. Felder mit Komma zurückgeben, sonst zerlegt PowerShell sie in Einzelwerte.
function ConvertTo-RegValue($Value, [string]$Type) {
    switch ($Type) {
        'DWord'       { return [int]$Value }
        'QWord'       { return [long]$Value }
        'Binary'      { return , ([byte[]]@($Value)) }
        'MultiString' { return , ([string[]]@($Value)) }
        default       { return [string]$Value }
    }
}

function Set-RegValueState([string]$Path, [string]$Name, $Value, [string]$Type) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    Set-ItemProperty -LiteralPath $Path -Name $Name -Value (ConvertTo-RegValue $Value $Type) -Type $Type -ErrorAction Stop
}

function Remove-RegValue([string]$Path, [string]$Name) { Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop }

function Get-ServiceStartType([string]$Name) { $s = Get-Service -Name $Name -ErrorAction Stop; return [string]$s.StartType }
function Set-ServiceStartType([string]$Name, [string]$StartType) { Set-Service -Name $Name -StartupType $StartType -ErrorAction Stop }

function Invoke-PowerCfg([string]$Arguments) { return (Invoke-External -File 'powercfg.exe' -Arguments $Arguments -TimeoutSec 60) }

# Energiepläne aus powercfg /list: GUID, Name, aktiv
function Get-PowerSchemes {
    $r = Invoke-PowerCfg '/list'
    return @(ConvertFrom-PowerCfgList $r.Output)
}
function ConvertFrom-PowerCfgList([string]$Text) {
    foreach ($ln in @($Text -split "`r?`n")) {
        if ($ln -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\(([^)]*)\)\s*(\*)?') {
            [pscustomobject]@{ Guid = $Matches[1].ToLowerInvariant(); Name = $Matches[2].Trim(); Aktiv = [bool]$Matches[3] }
        }
    }
}

# Werte vergleichbar und lesbar machen (Zahlen, Text, Listen)
function Get-ValueText($Value) {
    if ($null -eq $Value) { return '(nicht vorhanden)' }
    if ($Value -is [array] -or $Value -is [System.Collections.IList]) { return ((@($Value) | ForEach-Object { [string]$_ }) -join ',') }
    return [string]$Value
}

# ---------- Protokollierte Änderungen ----------
# Registry-Wert setzen. Rückgabe: Eintrag des Protokolls, $null wenn der Wert schon stimmte. Fehler beim Schreiben werfen.
function Set-RegistryValueLogged {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord', [string]$Modul, [string]$Schritt, [string]$Titel)
    $before = Get-RegValueState $Path $Name
    if ($before.Vorhanden -and $before.Typ -eq $Type -and (Get-ValueText $before.Wert) -eq (Get-ValueText (ConvertTo-RegValue $Value $Type))) { return $null }
    Set-RegValueState $Path $Name $Value $Type
    $daten = [ordered]@{ Pfad = $Path; Name = $Name; VorherVorhanden = [bool]$before.Vorhanden; VorherWert = $before.Wert; VorherTyp = $before.Typ; NachherWert = (ConvertTo-RegValue $Value $Type); NachherTyp = $Type }
    $gegen = $(if ($before.Vorhanden) { 'Set-ItemProperty -LiteralPath ''{0}'' -Name {1} -Value {2} -Type {3}' -f $Path, $Name, (Get-ValueText $before.Wert), $before.Typ } else { 'Remove-ItemProperty -LiteralPath ''{0}'' -Name {1}' -f $Path, $Name })
    return (Add-ChangeRecord -Modul $Modul -Schritt $Schritt -Titel $Titel -Risiko 'Aendern' -Art 'Registry' -Ziel ('{0}\{1}' -f $Path, $Name) `
        -Vorher (Get-ValueText $before.Wert) -Nachher (Get-ValueText $Value) -Daten $daten -Gegenbefehl $gegen)
}

function Set-ServiceStartTypeLogged {
    param([string]$Name, [string]$StartType, [string]$Modul, [string]$Schritt, [string]$Titel)
    $before = Get-ServiceStartType $Name
    if ($before -eq $StartType) { return $null }
    Set-ServiceStartType $Name $StartType
    return (Add-ChangeRecord -Modul $Modul -Schritt $Schritt -Titel $Titel -Risiko 'Aendern' -Art 'Dienststart' -Ziel ('Dienst {0}, Starttyp' -f $Name) `
        -Vorher $before -Nachher $StartType -Daten ([ordered]@{ Dienst = $Name; Vorher = $before; Nachher = $StartType }) -Gegenbefehl ('Set-Service {0} -StartupType {1}' -f $Name, $before))
}

# Alle Energiepläne sichern, bevor sie zurückgesetzt werden. Rückgängig stellt fehlende eigene Pläne und den aktiven Plan wieder her.
function Backup-PowerSchemesLogged {
    param([string]$Modul, [string]$Schritt, [string]$Titel)
    if (-not $script:ChangeLog) { Start-ChangeLog }
    $dir = Get-ChangeFilesDir
    if (-not $dir) { throw 'Kein Datenordner für die Sicherung der Energiepläne.' }
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    $schemes = @(Get-PowerSchemes)
    if (-not $schemes.Count) { throw 'powercfg /list lieferte keine Energiepläne.' }
    $saved = @()
    foreach ($s in $schemes) {
        $f = Join-Path $dir ('Energieplan_{0}.pow' -f $s.Guid)
        $r = Invoke-PowerCfg ('/export "{0}" {1}' -f $f, $s.Guid)
        if ($r.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $f)) { throw ('Energieplan {0} ließ sich nicht sichern (powercfg {1}).' -f $s.Name, $r.ExitCode) }
        $saved += [ordered]@{ Guid = $s.Guid; Name = $s.Name; Datei = (Split-Path $f -Leaf) }
    }
    $active = @($schemes | Where-Object Aktiv | Select-Object -First 1)
    $activeGuid = $(if ($active.Count) { $active[0].Guid } else { '' })
    $activeName = $(if ($active.Count) { $active[0].Name } else { '' })
    return (Add-ChangeRecord -Modul $Modul -Schritt $Schritt -Titel $Titel -Risiko 'Aendern' -Art 'Energieplaene' -Ziel 'Energiesparpläne' `
        -Vorher ('{0} Pläne, aktiv: {1}' -f $saved.Count, $activeName) -Nachher 'Windows-Standardpläne' `
        -Daten ([ordered]@{ AktivVorher = $activeGuid; Sicherungen = $saved }) -Gegenbefehl ('powercfg /import <Datei> <GUID>, danach powercfg /setactive {0}' -f $activeGuid))
}

# ---------- Rückgängig ----------
# Einen Eintrag umkehren. Rückgabe: Status und Text. Ändert den Eintrag nicht selbst (das macht Invoke-ChangeUndo).
function Undo-ChangeRecord($Record, [string]$FilesDir) {
    $d = $Record.Daten
    switch ([string]$Record.Art) {
        'Registry' {
            $now = Get-RegValueState $d.Pfad $d.Name
            if (-not $now.Vorhanden -or (Get-ValueText $now.Wert) -ne (Get-ValueText $d.NachherWert)) {
                return [pscustomobject]@{ Status = 'übersprungen'; Text = ('Wert ist inzwischen {0}, nicht {1}; nichts verändert.' -f (Get-ValueText $now.Wert), (Get-ValueText $d.NachherWert)) }
            }
            if ($d.VorherVorhanden) { Set-RegValueState $d.Pfad $d.Name $d.VorherWert $d.VorherTyp; return [pscustomobject]@{ Status = 'rückgängig'; Text = ('{0} wieder auf {1}' -f $d.Name, (Get-ValueText $d.VorherWert)) } }
            Remove-RegValue $d.Pfad $d.Name
            return [pscustomobject]@{ Status = 'rückgängig'; Text = ('{0} entfernt (war vorher nicht vorhanden)' -f $d.Name) }
        }
        'Dienststart' {
            $now = Get-ServiceStartType $d.Dienst
            if ($now -ne [string]$d.Nachher) { return [pscustomobject]@{ Status = 'übersprungen'; Text = ('Starttyp ist inzwischen {0}, nicht {1}; nichts verändert.' -f $now, $d.Nachher) } }
            Set-ServiceStartType $d.Dienst ([string]$d.Vorher)
            return [pscustomobject]@{ Status = 'rückgängig'; Text = ('Starttyp von {0} wieder {1}' -f $d.Dienst, $d.Vorher) }
        }
        'Energieplaene' {
            $present = @(Get-PowerSchemes | ForEach-Object { $_.Guid })
            $msgs = @(); $bad = 0
            foreach ($s in @($d.Sicherungen)) {
                if ($present -contains [string]$s.Guid) { continue }
                $f = Join-Path $FilesDir ([string]$s.Datei)
                if (-not (Test-Path -LiteralPath $f)) { $msgs += ('Sicherung von {0} fehlt' -f $s.Name); $bad++; continue }
                $r = Invoke-PowerCfg ('/import "{0}" {1}' -f $f, $s.Guid)
                if ($r.ExitCode -eq 0) { $msgs += ('{0} wiederhergestellt' -f $s.Name) } else { $msgs += ('{0} nicht importierbar (Code {1})' -f $s.Name, $r.ExitCode); $bad++ }
            }
            if ($d.AktivVorher) {
                $r = Invoke-PowerCfg ('/setactive {0}' -f $d.AktivVorher)
                if ($r.ExitCode -eq 0) { $msgs += 'vorher aktiver Plan wieder aktiv' } else { $msgs += ('aktiver Plan nicht setzbar (Code {0})' -f $r.ExitCode); $bad++ }
            }
            $msgs += 'Einstellungen der Windows-Standardpläne bleiben auf Standard'
            return [pscustomobject]@{ Status = $(if ($bad) { 'fehlgeschlagen' } else { 'rückgängig' }); Text = ($msgs -join '; ') }
        }
    }
    return [pscustomobject]@{ Status = [string]$Record.Status; Text = ('Für {0} gibt es kein automatisches Rückgängig: {1}' -f $Record.Art, $Record.Gegenbefehl) }
}

# Alle Einträge aller Läufe, neueste zuerst (für die Oberfläche und Tests)
function Get-ChangeEntries([string]$Root = (Get-ChangeRoot)) {
    $list = New-Object System.Collections.Generic.List[object]
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
        $j = Read-ChangeFile $f.FullName
        if (-not $j) { continue }
        foreach ($e in @($j.Eintraege)) {
            $list.Add([pscustomobject]@{ Datei = $f.FullName; Computer = [string]$j.Computer; GeraetId = [string]$j.GeraetId; Lauf = [string]$j.Lauf
                Id = [int]$e.Id; Zeit = [string]$e.Zeit; Modul = [string]$e.Modul; Titel = [string]$e.Titel; Risiko = [string]$e.Risiko; Art = [string]$e.Art
                Ziel = [string]$e.Ziel; Vorher = [string]$e.Vorher; Nachher = [string]$e.Nachher; Status = [string]$e.Status; Ergebnis = [string]$e.Ergebnis })
        }
    }
    return @($list | Sort-Object Zeit, Id -Descending)
}

# Rückgängig für eine Auswahl: "Datei*Id;Datei*Id". Nur auf dem Gerät, auf dem die Änderung gemacht wurde.
function Invoke-ChangeUndo([string]$Spec) {
    $byFile = [ordered]@{}
    foreach ($part in @(([string]$Spec) -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })) {
        $p = $part -split '\*', 2
        if ($p.Count -ne 2 -or -not ($p[1] -as [int])) { Write-Host ('Ungültige Auswahl: {0}' -f $part); continue }
        if (-not $byFile.Contains($p[0])) { $byFile[$p[0]] = New-Object System.Collections.Generic.List[int] }
        $byFile[$p[0]].Add([int]$p[1])
    }
    $dev = Get-DeviceIdentity
    $done = 0; $fail = 0
    foreach ($file in $byFile.Keys) {
        $root = Get-ChangeRoot
        if (-not $root -or -not ([IO.Path]::GetFullPath($file)).StartsWith([IO.Path]::GetFullPath($root), [StringComparison]::OrdinalIgnoreCase)) { Write-Host ('{0} liegt nicht im Änderungsprotokoll des Datenordners.' -f $file); $fail++; continue }
        $j = Read-ChangeFile $file
        if (-not $j) { Write-Host ('{0} ist kein lesbares Änderungsprotokoll.' -f $file); $fail++; continue }
        $same = $(if ([string]$j.GeraetId) { [string]$j.GeraetId -eq $dev.Id } else { [string]$j.Computer -eq $env:COMPUTERNAME })
        if (-not $same) { Write-Host ('{0}: Die Änderungen stammen von {1}, nicht von diesem Gerät. Rückgängig nur dort möglich.' -f (Split-Path $file -Leaf), $j.Computer); $fail++; continue }
        $filesDir = $file -replace '\.json$', ''
        # neueste zuerst, damit aufeinander aufbauende Änderungen in umgekehrter Reihenfolge zurückgenommen werden
        foreach ($e in @($j.Eintraege | Where-Object { $byFile[$file] -contains [int]$_.Id } | Sort-Object { [int]$_.Id } -Descending)) {
            if ([string]$e.Status -ne 'aktiv') { Write-Host ('{0}: Status {1}, nichts zu tun.' -f $e.Titel, $e.Status); continue }
            try { $res = Undo-ChangeRecord $e $filesDir } catch { $res = [pscustomobject]@{ Status = 'fehlgeschlagen'; Text = $_.Exception.Message } }
            $e.Status = $res.Status
            $e.Ergebnis = ('{0}: {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture), $res.Text)
            Write-Host ('{0} ({1}): {2}, {3}' -f $e.Titel, $e.Ziel, $res.Status, $res.Text)
            if ($res.Status -eq 'rückgängig') { $done++ } else { $fail++ }
        }
        try { Save-ChangeFile $file $j } catch { Write-Host ('Protokoll {0} konnte nicht aktualisiert werden: {1}' -f $file, $_.Exception.Message); $fail++ }
    }
    return [pscustomobject]@{ Rueckgaengig = $done; Probleme = $fail }
}
#endregion
#region ---------- Portable Werkzeuge mit Manifest ----------
# Externe Programme auf dem Stick liegen unter Minibench-Daten\Tools. Tools.json hält je Werkzeug Datei, Version,
# SHA-256, Lizenz und Quelle fest. Ausgeführt wird eine Datei nur, wenn ihr Hash zum Manifest passt; eine veränderte
# oder ausgetauschte Datei bleibt liegen und erscheint als Befund.
# Grenze: Wer Datei und Manifest gemeinsam austauscht, wird so nicht erkannt. Das Manifest schützt vor beschädigten,
# versehentlich ersetzten oder fremd untergeschobenen Einzeldateien, nicht vor gezielter Manipulation des ganzen Sticks.
$script:ToolManifestFormat = 'Minibench-Tools/1'
$script:ToolIssues = New-Object System.Collections.Generic.List[string]

function Get-ToolsDir { if ($script:DataDir) { return (Join-Path $script:DataDir 'Tools') } else { return '' } }

function Get-FileSha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $fs = [IO.File]::OpenRead($Path)
    try { return (-join ($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') })) }
    finally { $fs.Dispose(); $sha.Dispose() }
}

function Read-ToolManifest([string]$ToolsDir = (Get-ToolsDir)) {
    $m = [ordered]@{ Format = $script:ToolManifestFormat; Werkzeuge = @() }
    if (-not $ToolsDir) { return $m }
    $f = Join-Path $ToolsDir 'Tools.json'
    if (-not (Test-Path -LiteralPath $f)) { return $m }
    try {
        $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.Werkzeuge = @($j.Werkzeuge | Where-Object { $_ } | ForEach-Object {
            [ordered]@{ Name = [string]$_.Name; Datei = [string]$_.Datei; Version = [string]$_.Version; SHA256 = ([string]$_.SHA256).ToLowerInvariant()
                        Lizenz = [string]$_.Lizenz; Quelle = [string]$_.Quelle; Aufgenommen = [string]$_.Aufgenommen; Herkunft = [string]$_.Herkunft }
        })
    } catch { $script:ToolIssues.Add(('Tools.json ist nicht lesbar ({0}); portable Werkzeuge werden nicht ausgeführt.' -f $_.Exception.Message)); $m.Ungueltig = $true }
    return $m
}

function Save-ToolManifest($Manifest, [string]$ToolsDir = (Get-ToolsDir)) {
    if (-not $ToolsDir) { return $false }
    try {
        New-Item -ItemType Directory -Path $ToolsDir -Force -ErrorAction Stop | Out-Null
        $o = [ordered]@{ Format = $script:ToolManifestFormat; Hinweis = 'Ausgeführt wird nur, was zu SHA256 passt. Datei ist relativ zu diesem Ordner.'; Werkzeuge = @($Manifest.Werkzeuge) }
        [IO.File]::WriteAllText((Join-Path $ToolsDir 'Tools.json'), ($o | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
        return $true
    } catch { return $false }
}

# Datei ins Manifest aufnehmen (nach dem Holen aus vertrauenswürdiger Quelle) oder ihren Eintrag erneuern
function Register-Tool {
    param([string]$Name, [string]$Path, [string]$Lizenz = '', [string]$Quelle = '', [string]$Herkunft = '', [string]$ToolsDir = (Get-ToolsDir))
    if (-not $ToolsDir -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $full = (Resolve-Path -LiteralPath $Path).Path
    $root = (Resolve-Path -LiteralPath $ToolsDir).Path.TrimEnd('\', '/')
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw ('{0} liegt nicht im Tools-Ordner.' -f $full) }
    $ver = ''
    try { $vi = (Get-Item -LiteralPath $full).VersionInfo; $ver = $(if ($vi.ProductVersion) { [string]$vi.ProductVersion } else { [string]$vi.FileVersion }) } catch { }
    $e = [ordered]@{ Name = $Name; Datei = $full.Substring($root.Length + 1); Version = $ver.Trim(); SHA256 = (Get-FileSha256 $full)
                     Lizenz = $Lizenz; Quelle = $Quelle; Aufgenommen = (Get-Date).ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture); Herkunft = $Herkunft }
    $m = Read-ToolManifest $ToolsDir
    if ($m.Ungueltig) { return $null }
    $m.Werkzeuge = @(@($m.Werkzeuge | Where-Object { $_.Name -ne $Name }) + $e)
    if (Save-ToolManifest $m $ToolsDir) { return $e }
    return $null
}

# Pfad eines Werkzeugs, wenn Datei vorhanden und Hash passend; sonst $null und ein Eintrag in $script:ToolIssues
function Get-VerifiedTool([string]$Name, [string]$ToolsDir = (Get-ToolsDir)) {
    if (-not $ToolsDir) { return $null }
    $m = Read-ToolManifest $ToolsDir
    if ($m.Ungueltig) { return $null }
    $e = @($m.Werkzeuge | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
    if (-not $e) { return $null }
    $p = Join-Path $ToolsDir $e.Datei
    if (-not (Test-Path -LiteralPath $p)) { $script:ToolIssues.Add(('{0}: {1} fehlt im Tools-Ordner.' -f $Name, $e.Datei)); return $null }
    $h = Get-FileSha256 $p
    if ($h -ne $e.SHA256) {
        $script:ToolIssues.Add(('{0}: {1} passt nicht zum Manifest (SHA-256 {2}… statt {3}…) und wird nicht ausgeführt. Datei neu holen oder bewusst neu aufnehmen.' -f $Name, $e.Datei, $h.Substring(0, 12), ([string]$e.SHA256).Substring(0, [math]::Min(12, ([string]$e.SHA256).Length))))
        return $null
    }
    return $p
}

# Übergang von 2.1: dort ohne Manifest abgelegte Werkzeuge einmalig aufnehmen (Hash beim ersten Start festgehalten)
function Register-LegacyTool([string]$Name, [string[]]$RelPaths, [string]$Lizenz, [string]$Quelle, [string]$ToolsDir = (Get-ToolsDir)) {
    if (-not $ToolsDir) { return $null }
    $m = Read-ToolManifest $ToolsDir
    if ($m.Ungueltig -or @($m.Werkzeuge | Where-Object { $_.Name -eq $Name }).Count) { return $null }
    foreach ($r in $RelPaths) {
        $p = Join-Path $ToolsDir $r
        if (Test-Path -LiteralPath $p) { return (Register-Tool -Name $Name -Path $p -Lizenz $Lizenz -Quelle $Quelle -Herkunft 'aus Version 2.1 ohne Manifest übernommen' -ToolsDir $ToolsDir) }
    }
    return $null
}
#endregion
#region ---------- Grafische Oberfläche ----------
if (-not $EventMode -and -not $ImportOrdner -and -not $Vergleich -and -not $Rueckgaengig -and -not $SensorLive -and -not $SensorWerkzeugeHolen -and -not $SensorAufraeumen) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        [void][Windows.Forms.MessageBox]::Show('PowerShell läuft hier im Constrained Language Mode (AppLocker oder WDAC). Die Oberfläche und die Testroutinen von Leos Minibench sind so nicht verfügbar.', 'Leos Minibench', 'OK', 'Warning')
        exit 1
    }
    $guiCode = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

static class UI
{
    public static readonly Color Bg = Color.FromArgb(243, 245, 248);
    public static readonly Color Panel = Color.White;
    public static readonly Color Text = Color.FromArgb(28, 35, 48);
    public static readonly Color Muted = Color.FromArgb(98, 108, 124);
    public static readonly Color Line = Color.FromArgb(221, 226, 233);
    public static readonly Color Accent = Color.FromArgb(37, 99, 235);
    public static readonly Color AccentDark = Color.FromArgb(29, 78, 196);
    public static readonly Color AccentSoft = Color.FromArgb(232, 240, 254);
    public static readonly Color Header = Color.FromArgb(22, 30, 46);
    public static readonly Color Crit = Color.FromArgb(185, 35, 28), CritBg = Color.FromArgb(253, 234, 232);
    public static readonly Color Warn = Color.FromArgb(160, 92, 0), WarnBg = Color.FromArgb(254, 243, 214);
    public static readonly Color Info = Color.FromArgb(31, 91, 196), InfoBg = Color.FromArgb(231, 239, 255);
    public static readonly Color Ok = Color.FromArgb(17, 120, 66), OkBg = Color.FromArgb(225, 245, 233);
    public static readonly Color Skip = Color.FromArgb(105, 112, 125), SkipBg = Color.FromArgb(236, 238, 242);

    public static GraphicsPath Round(RectangleF r, float rad)
    {
        GraphicsPath p = new GraphicsPath();
        float d = Math.Max(1f, Math.Min(rad * 2, Math.Min(r.Width, r.Height)));
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    public static void Level(string lvl, out Color fg, out Color bg)
    {
        string l = (lvl ?? "").ToUpperInvariant();
        if (l == "KRITISCH" || l == "FEHLER") { fg = Crit; bg = CritBg; }
        else if (l == "WARNUNG") { fg = Warn; bg = WarnBg; }
        else if (l == "OK" || l == "REPARIERT") { fg = Ok; bg = OkBg; }
        else if (l == "INFO") { fg = Info; bg = InfoBg; }
        else { fg = Skip; bg = SkipBg; }
    }

    public static Button Primary(string text)
    {
        Button b = new Button(); b.Text = text; b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderSize = 0;
        b.BackColor = Accent; b.ForeColor = Color.White; b.FlatAppearance.MouseOverBackColor = AccentDark; b.FlatAppearance.MouseDownBackColor = AccentDark;
        b.Font = new Font("Segoe UI Semibold", 10.5f); b.AutoSize = true; b.Padding = new Padding(18, 6, 18, 6); b.Cursor = Cursors.Hand; b.UseVisualStyleBackColor = false;
        return b;
    }

    public static Button Secondary(string text)
    {
        Button b = new Button(); b.Text = text; b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderColor = Color.FromArgb(200, 207, 218);
        b.BackColor = Panel; b.ForeColor = Text; b.FlatAppearance.MouseOverBackColor = Color.FromArgb(240, 243, 248);
        b.Font = new Font("Segoe UI", 9.75f); b.AutoSize = true; b.Padding = new Padding(10, 3, 10, 3); b.Margin = new Padding(8, 0, 0, 0); b.Cursor = Cursors.Hand; b.UseVisualStyleBackColor = false;
        return b;
    }
}

class FlatBar : Control
{
    int val; bool marquee; int pos; Timer anim;
    public Color Fill = UI.Accent;
    public FlatBar()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        anim = new Timer(); anim.Interval = 25; anim.Tick += delegate { pos = (pos + 8) % Math.Max(1, Width + 160); Invalidate(); };
    }
    public int Value { get { return val; } set { int v = Math.Max(0, Math.Min(100, value)); if (v != val) { val = v; Invalidate(); } } }
    public bool Marquee
    {
        get { return marquee; }
        set { if (marquee == value) return; marquee = value; if (value) anim.Start(); else anim.Stop(); Invalidate(); }
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
        RectangleF r = new RectangleF(0, 0, Width - 1, Height - 1);
        float rad = Height / 2f;
        using (GraphicsPath track = UI.Round(r, rad)) using (SolidBrush tb = new SolidBrush(Color.FromArgb(226, 231, 238))) g.FillPath(tb, track);
        using (GraphicsPath clip = UI.Round(r, rad))
        {
            g.SetClip(clip);
            using (SolidBrush fb = new SolidBrush(Fill))
            {
                if (marquee) g.FillRectangle(fb, pos - 160, 0, 160, Height);
                else if (val > 0) g.FillRectangle(fb, 0, 0, (Width - 1) * val / 100f, Height);
            }
            g.ResetClip();
        }
    }
}

// Eintrag der Modulnavigation: Kästchen links schaltet das Modul ein oder aus, ein Klick daneben zeigt seine Einstellungen
class NavItem : Control
{
    bool sel, hover, chk;
    public string Title, Desc;
    public bool HasCheck = true;
    public event EventHandler Picked;
    public event EventHandler CheckedChanged;
    public NavItem(string title, string desc)
    {
        Title = title; Desc = desc;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        Cursor = Cursors.Hand; Size = new Size(226, 70); Margin = new Padding(0, 0, 0, 8); BackColor = UI.Bg;
    }
    public bool Selected { get { return sel; } set { sel = value; Invalidate(); } }
    public bool Checked
    {
        get { return chk; }
        set { if (chk == value) return; chk = value; Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); }
    }
    Rectangle Box { get { return new Rectangle(14, 14, 20, 20); } }
    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseClick(MouseEventArgs e)
    {
        Focus();
        Rectangle hit = Box; hit.Inflate(8, 8);
        if (HasCheck && hit.Contains(e.Location)) Checked = !Checked;
        if (Picked != null) Picked(this, e);
        base.OnMouseClick(e);
    }
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Space && HasCheck) Checked = !Checked;
        if (e.KeyCode == Keys.Enter && Picked != null) Picked(this, e);
        base.OnKeyDown(e);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        RectangleF r = new RectangleF(1, 1, Width - 3, Height - 3);
        Color fill = sel ? UI.AccentSoft : (hover ? Color.FromArgb(250, 251, 253) : UI.Panel);
        using (GraphicsPath p = UI.Round(r, 10))
        {
            using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
            using (Pen pen = new Pen(sel ? UI.Accent : (hover ? Color.FromArgb(180, 190, 205) : UI.Line), sel ? 2f : 1f)) g.DrawPath(pen, p);
        }
        int x = 14;
        if (HasCheck)
        {
            Rectangle bx = Box;
            using (GraphicsPath bp = UI.Round(bx, 5))
            {
                using (SolidBrush bb = new SolidBrush(chk ? UI.Accent : UI.Panel)) g.FillPath(bb, bp);
                using (Pen bpen = new Pen(chk ? UI.Accent : Color.FromArgb(160, 170, 185), 1.5f)) g.DrawPath(bpen, bp);
            }
            if (chk) using (Pen ck = new Pen(Color.White, 2.4f)) { ck.StartCap = LineCap.Round; ck.EndCap = LineCap.Round; g.DrawLines(ck, new Point[] { new Point(bx.X + 5, bx.Y + 10), new Point(bx.X + 9, bx.Y + 14), new Point(bx.X + 15, bx.Y + 6) }); }
            x = 44;
        }
        using (Font ft = new Font("Segoe UI Semibold", 10.5f)) TextRenderer.DrawText(g, Title, ft, new Rectangle(x, 12, Width - x - 10, 22), UI.Text, TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
        using (Font fs = new Font("Segoe UI", 8.5f)) TextRenderer.DrawText(g, Desc, fs, new Rectangle(x, 34, Width - x - 10, Height - 38), UI.Muted, TextFormatFlags.Left | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis);
    }
}

class StatCard : Control
{
    public string Caption; public Color Accent; int count;
    public StatCard(string caption, Color accent)
    {
        Caption = caption; Accent = accent;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Size = new Size(170, 70); Margin = new Padding(0, 0, 12, 0); BackColor = UI.Bg;
    }
    public int Count { get { return count; } set { count = value; Invalidate(); } }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
        RectangleF r = new RectangleF(0.5f, 0.5f, Width - 2, Height - 2);
        using (GraphicsPath p = UI.Round(r, 10))
        {
            using (SolidBrush b = new SolidBrush(UI.Panel)) g.FillPath(b, p);
            using (Pen pen = new Pen(UI.Line)) g.DrawPath(pen, p);
            g.SetClip(p);
            using (SolidBrush a = new SolidBrush(Accent)) g.FillRectangle(a, 0, 0, 5, Height);
            g.ResetClip();
        }
        using (Font fn = new Font("Segoe UI Semibold", 20f)) TextRenderer.DrawText(g, count.ToString(), fn, new Point(16, 6), count > 0 ? Accent : UI.Muted);
        using (Font fc = new Font("Segoe UI", 9f)) TextRenderer.DrawText(g, Caption, fc, new Point(18, 44), UI.Muted);
    }
}

class TabStrip : Control
{
    public List<string> Items = new List<string>();
    int selected;
    public event EventHandler SelectedChanged;
    public TabStrip()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Height = 38; Cursor = Cursors.Hand; BackColor = UI.Bg;
    }
    public int Selected { get { return selected; } set { selected = value; Invalidate(); if (SelectedChanged != null) SelectedChanged(this, EventArgs.Empty); } }
    public void SetText(int i, string t) { Items[i] = t; Invalidate(); }
    Rectangle ItemRect(Graphics g, int i, Font f)
    {
        int x = 0;
        for (int k = 0; k <= i; k++)
        {
            int w = TextRenderer.MeasureText(g, Items[k], f).Width + 28;
            if (k == i) return new Rectangle(x, 0, w, Height);
            x += w + 4;
        }
        return Rectangle.Empty;
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        using (Pen line = new Pen(UI.Line)) g.DrawLine(line, 0, Height - 1, Width, Height - 1);
        for (int i = 0; i < Items.Count; i++)
        {
            using (Font f = new Font(i == selected ? "Segoe UI Semibold" : "Segoe UI", 10f))
            {
                Rectangle r = ItemRect(g, i, f);
                TextRenderer.DrawText(g, Items[i], f, r, i == selected ? UI.Accent : UI.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                if (i == selected) using (SolidBrush b = new SolidBrush(UI.Accent)) g.FillRectangle(b, r.X + 6, Height - 3, r.Width - 12, 3);
            }
        }
    }
    protected override void OnMouseClick(MouseEventArgs e)
    {
        using (Graphics g = CreateGraphics())
            for (int i = 0; i < Items.Count; i++)
                using (Font f = new Font(i == selected ? "Segoe UI Semibold" : "Segoe UI", 10f))
                    if (ItemRect(g, i, f).Contains(e.Location)) { Selected = i; break; }
        base.OnMouseClick(e);
    }
}

// Ein System aus der Vergleichsdatenbank (eine JSON-Datei je Lauf)
// Kurven der Leitwerte (SENSLEAD): drei Felder übereinander für Temperatur, Takt und Leistung, je CPU und GPU.
// WindowSec > 0 zeigt nur die letzten Sekunden (Live-Seite), 0 den ganzen Verlauf (Lasttest).
class SensorChart : Control
{
    // Spalten: 0 Zeit, 1 CPU °C, 2 CPU MHz, 3 CPU W, 4 GPU °C, 5 GPU MHz, 6 GPU W, 7 Lüfter, 8 CPU-Last
    List<double[]> rows = new List<double[]>();
    public int WindowSec = 600;
    public double CpuLimit = double.NaN, GpuLimit = double.NaN, TjMax = double.NaN;
    public string Empty = "Noch keine Messwerte.";
    static readonly Color CpuColor = Color.FromArgb(37, 99, 235), GpuColor = Color.FromArgb(194, 65, 12);
    public SensorChart()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        BackColor = UI.Panel;
    }
    public int Count { get { return rows.Count; } }
    public void Clear() { rows.Clear(); CpuLimit = double.NaN; GpuLimit = double.NaN; TjMax = double.NaN; Invalidate(); }
    static double D(string s)
    {
        double v; return double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : double.NaN;
    }
    // p wie @@SENSLEAD|t|cpuT|cpuMHz|cpuW|gpuT|gpuMHz|gpuW|fan|cpuLoad (p[0] = "SENSLEAD")
    public double[] Add(string[] p)
    {
        double[] r = new double[9];
        for (int i = 0; i < 9; i++) r[i] = (i + 1 < p.Length) ? D(p[i + 1]) : double.NaN;
        if (double.IsNaN(r[0])) return r;
        rows.Add(r);
        if (rows.Count > 30000) rows.RemoveRange(0, rows.Count - 30000);
        Invalidate();
        return r;
    }
    public void SetLimits(string[] p)
    {
        CpuLimit = p.Length > 1 ? D(p[1]) : double.NaN; GpuLimit = p.Length > 2 ? D(p[2]) : double.NaN; TjMax = p.Length > 3 ? D(p[3]) : double.NaN;
        Invalidate();
    }
    public double[] Last { get { return rows.Count > 0 ? rows[rows.Count - 1] : null; } }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(BackColor);
        using (Pen bp = new Pen(UI.Line)) g.DrawRectangle(bp, 0, 0, Width - 1, Height - 1);
        if (rows.Count < 1) { using (Font f = new Font("Segoe UI", 9.75f)) TextRenderer.DrawText(g, Empty, f, ClientRectangle, UI.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak); return; }
        double tMax = rows[rows.Count - 1][0];
        double tMin = WindowSec > 0 ? Math.Max(0, tMax - WindowSec) : rows[0][0];
        if (tMax - tMin < 10) tMax = tMin + 10;
        int h = (Height - 8) / 3;
        DrawPanel(g, new Rectangle(0, 4, Width, h), "Temperatur", "°C", 1, 4, tMin, tMax, true);
        DrawPanel(g, new Rectangle(0, 4 + h, Width, h), "Takt", "MHz", 2, 5, tMin, tMax, false);
        DrawPanel(g, new Rectangle(0, 4 + 2 * h, Width, h), "Leistung", "W", 3, 6, tMin, tMax, false);
    }

    void DrawPanel(Graphics g, Rectangle r, string title, string unit, int ci, int gi, double tMin, double tMax, bool limits)
    {
        Rectangle plot = new Rectangle(r.X + 58, r.Y + 22, r.Width - 58 - 14, r.Height - 22 - 18);
        if (plot.Width < 40 || plot.Height < 20) return;
        double lo = double.MaxValue, hi = double.MinValue; bool any = false;
        foreach (double[] row in rows)
        {
            if (row[0] < tMin) continue;
            foreach (int k in new int[] { ci, gi }) if (!double.IsNaN(row[k])) { lo = Math.Min(lo, row[k]); hi = Math.Max(hi, row[k]); any = true; }
        }
        if (limits)
        {
            foreach (double v in new double[] { CpuLimit, GpuLimit, TjMax }) if (!double.IsNaN(v) && v > 0 && any) { hi = Math.Max(hi, v); }
        }
        using (Font ft = new Font("Segoe UI Semibold", 9f)) TextRenderer.DrawText(g, title + " (" + unit + ")", ft, new Point(r.X + 8, r.Y + 2), UI.Text);
        double[] last = rows[rows.Count - 1];
        string lc = Fmt(last[ci], unit), lg = Fmt(last[gi], unit);
        using (Font fl = new Font("Segoe UI", 8.75f))
        {
            int x = r.X + 160;
            if (lc.Length > 0) { using (SolidBrush b = new SolidBrush(CpuColor)) g.FillRectangle(b, x, r.Y + 7, 10, 10); TextRenderer.DrawText(g, "CPU " + lc, fl, new Point(x + 14, r.Y + 3), UI.Text); x += 120; }
            if (lg.Length > 0) { using (SolidBrush b = new SolidBrush(GpuColor)) g.FillRectangle(b, x, r.Y + 7, 10, 10); TextRenderer.DrawText(g, "GPU " + lg, fl, new Point(x + 14, r.Y + 3), UI.Text); x += 120; }
            if (limits && !double.IsNaN(CpuLimit) && CpuLimit > 0) TextRenderer.DrawText(g, "Abbruch CPU " + CpuLimit.ToString("0") + " °C" + (!double.IsNaN(GpuLimit) && GpuLimit > 0 ? ", GPU " + GpuLimit.ToString("0") + " °C" : ""), fl, new Point(x + 4, r.Y + 3), UI.Crit);
        }
        if (!any) { using (Font f = new Font("Segoe UI", 8.75f)) TextRenderer.DrawText(g, "kein Wert verfügbar", f, plot, UI.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter); return; }
        double span = hi - lo; if (span < 1) span = 1;
        double step = NiceStep(span / 3);
        double y0 = Math.Floor(lo / step) * step, y1 = Math.Ceiling(hi / step) * step; if (y1 <= y0) y1 = y0 + step;
        using (Pen grid = new Pen(Color.FromArgb(236, 239, 243)))
        using (Font fa = new Font("Segoe UI", 7.75f))
        {
            for (double v = y0; v <= y1 + step / 1000; v += step)
            {
                float y = (float)(plot.Bottom - (v - y0) / (y1 - y0) * plot.Height);
                g.DrawLine(grid, plot.Left, y, plot.Right, y);
                TextRenderer.DrawText(g, v.ToString("0"), fa, new Rectangle(r.X, (int)y - 8, 52, 16), UI.Muted, TextFormatFlags.Right | TextFormatFlags.VerticalCenter);
            }
            double ts = 10; foreach (double c in new double[] { 10, 30, 60, 120, 300, 600, 900, 1800, 3600 }) { ts = c; if ((tMax - tMin) / c <= 8) break; }
            for (double t = Math.Ceiling(tMin / ts) * ts; t <= tMax; t += ts)
            {
                float x = (float)(plot.Left + (t - tMin) / (tMax - tMin) * plot.Width);
                g.DrawLine(grid, x, plot.Top, x, plot.Bottom);
                string lab = ts >= 60 ? ((int)(t / 60)).ToString() + " min" : ((int)t).ToString() + " s";
                TextRenderer.DrawText(g, lab, fa, new Rectangle((int)x - 30, plot.Bottom + 1, 60, 16), UI.Muted, TextFormatFlags.HorizontalCenter);
            }
        }
        if (limits)
        {
            DrawLimit(g, plot, CpuLimit, y0, y1, UI.Crit, DashStyle.Dash);
            DrawLimit(g, plot, GpuLimit, y0, y1, Color.FromArgb(194, 65, 12), DashStyle.Dash);
            if (!double.IsNaN(TjMax) && TjMax != CpuLimit) DrawLimit(g, plot, TjMax, y0, y1, UI.Warn, DashStyle.Dot);
        }
        DrawSeries(g, plot, ci, tMin, tMax, y0, y1, CpuColor);
        DrawSeries(g, plot, gi, tMin, tMax, y0, y1, GpuColor);
    }

    static void DrawLimit(Graphics g, Rectangle plot, double v, double y0, double y1, Color c, DashStyle ds)
    {
        if (double.IsNaN(v) || v <= 0 || v < y0 || v > y1) return;
        float y = (float)(plot.Bottom - (v - y0) / (y1 - y0) * plot.Height);
        using (Pen p = new Pen(c, 1.5f)) { p.DashStyle = ds; g.DrawLine(p, plot.Left, y, plot.Right, y); }
    }

    void DrawSeries(Graphics g, Rectangle plot, int k, double tMin, double tMax, double y0, double y1, Color c)
    {
        List<PointF> pts = new List<PointF>();
        using (Pen p = new Pen(c, 2f))
        {
            p.LineJoin = LineJoin.Round;
            foreach (double[] row in rows)
            {
                if (row[0] < tMin) continue;
                if (double.IsNaN(row[k])) { if (pts.Count > 1) g.DrawLines(p, pts.ToArray()); pts.Clear(); continue; }
                pts.Add(new PointF((float)(plot.Left + (row[0] - tMin) / (tMax - tMin) * plot.Width), (float)(plot.Bottom - (row[k] - y0) / (y1 - y0) * plot.Height)));
            }
            if (pts.Count > 1) g.DrawLines(p, pts.ToArray());
            else if (pts.Count == 1) using (SolidBrush b = new SolidBrush(c)) g.FillEllipse(b, pts[0].X - 2, pts[0].Y - 2, 4, 4);
        }
    }

    static double NiceStep(double raw)
    {
        if (raw <= 0) return 1;
        double mag = Math.Pow(10, Math.Floor(Math.Log10(raw)));
        foreach (double f in new double[] { 1, 2, 2.5, 5, 10 }) if (f * mag >= raw) return f * mag;
        return 10 * mag;
    }

    public static string Fmt(double v, string unit)
    {
        if (double.IsNaN(v)) return "";
        return v.ToString(unit == "W" ? "0.0" : "0", CultureInfo.GetCultureInfo("de-DE")) + " " + unit;
    }
}

public class DbEntry
{
    public string Path = "", Name = "", Computer = "", Datum = "", Cpu = "", Gpu = "", Ram = "", Disk = "", Befunde = "", Module = "", Quelle = "", Ordner = "";
    public Dictionary<string, double> Werte = new Dictionary<string, double>();
    public bool HasBench { get { return Werte.Count > 0; } }
    public double Get(string k) { double v; return Werte.TryGetValue(k, out v) ? v : 0; }
    public string Label { get { return Computer + "  ·  " + Datum + (Cpu.Length > 0 ? "  ·  " + Cpu : ""); } }

    static string S(Dictionary<string, object> d, string k)
    {
        object o; if (d == null || !d.TryGetValue(k, out o) || o == null) return "";
        return Convert.ToString(o, CultureInfo.InvariantCulture);
    }

    public static List<DbEntry> Load(string dir)
    {
        List<DbEntry> list = new List<DbEntry>();
        if (String.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return list;
        System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
        js.MaxJsonLength = int.MaxValue;
        foreach (string f in Directory.GetFiles(dir, "*.json"))
        {
            try
            {
                Dictionary<string, object> d = js.DeserializeObject(File.ReadAllText(f, Encoding.UTF8)) as Dictionary<string, object>;
                if (d == null) continue;
                DbEntry e = new DbEntry(); e.Path = f;
                e.Name = S(d, "Name"); e.Computer = S(d, "Computer"); e.Datum = S(d, "Datum"); e.Module = S(d, "Module"); e.Quelle = S(d, "Quelle"); e.Ordner = S(d, "Ordner");
                object hw; if (d.TryGetValue("Hardware", out hw))
                {
                    Dictionary<string, object> h = hw as Dictionary<string, object>;
                    e.Cpu = S(h, "CPU"); e.Gpu = S(h, "GPU"); e.Ram = S(h, "RAM"); e.Disk = S(h, "Datentraeger");
                }
                object w; if (d.TryGetValue("Werte", out w))
                {
                    Dictionary<string, object> wd = w as Dictionary<string, object>;
                    if (wd != null) foreach (KeyValuePair<string, object> kv in wd) { try { e.Werte[kv.Key] = Convert.ToDouble(kv.Value, CultureInfo.InvariantCulture); } catch { } }
                }
                object b; if (d.TryGetValue("Befunde", out b))
                {
                    Dictionary<string, object> bd = b as Dictionary<string, object>;
                    if (bd != null) e.Befunde = String.Format("{0} / {1} / {2}", S(bd, "Kritisch"), S(bd, "Warnungen"), S(bd, "Hinweise"));
                }
                if (e.Computer.Length == 0) e.Computer = System.IO.Path.GetFileNameWithoutExtension(f);
                list.Add(e);
            }
            catch { }
        }
        list.Sort(delegate(DbEntry a, DbEntry c) { int r = String.Compare(a.Computer, c.Computer, StringComparison.OrdinalIgnoreCase); return r != 0 ? r : String.Compare(c.Datum, a.Datum, StringComparison.Ordinal); });
        return list;
    }
}

// Eintrag des Änderungsprotokolls (Minibench-Daten\Änderungen\<PC>\<Lauf>.json)
public class ChangeEntry
{
    public string FilePath = "", Computer = "", GeraetId = "", Zeit = "", Modul = "", Titel = "", Risiko = "", Art = "", Ziel = "", Vorher = "", Nachher = "", Status = "", Ergebnis = "", Gegenbefehl = "";
    public int Id;
    public bool Undoable { get { return Status == "aktiv" && String.Equals(Computer, Environment.MachineName, StringComparison.OrdinalIgnoreCase); } }

    static string S(Dictionary<string, object> d, string k)
    {
        object o; if (d == null || !d.TryGetValue(k, out o) || o == null) return "";
        return Convert.ToString(o, CultureInfo.InvariantCulture);
    }

    public static List<ChangeEntry> Load(string root)
    {
        List<ChangeEntry> list = new List<ChangeEntry>();
        if (String.IsNullOrEmpty(root) || !Directory.Exists(root)) return list;
        System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
        js.MaxJsonLength = int.MaxValue;
        foreach (string f in Directory.GetFiles(root, "*.json", SearchOption.AllDirectories))
        {
            try
            {
                Dictionary<string, object> d = js.DeserializeObject(File.ReadAllText(f, Encoding.UTF8)) as Dictionary<string, object>;
                if (d == null || S(d, "Format") != "Minibench-Aenderungen/1") continue;
                object eo; if (!d.TryGetValue("Eintraege", out eo)) continue;
                System.Collections.IEnumerable arr = eo as System.Collections.IEnumerable;
                if (arr == null || eo is string) continue;
                foreach (object x in arr)
                {
                    Dictionary<string, object> e = x as Dictionary<string, object>;
                    if (e == null) continue;
                    ChangeEntry c = new ChangeEntry(); c.FilePath = f; c.Computer = S(d, "Computer"); c.GeraetId = S(d, "GeraetId");
                    int id; int.TryParse(S(e, "Id"), out id); c.Id = id;
                    c.Zeit = S(e, "Zeit"); c.Modul = S(e, "Modul"); c.Titel = S(e, "Titel"); c.Risiko = S(e, "Risiko"); c.Art = S(e, "Art"); c.Ziel = S(e, "Ziel");
                    c.Vorher = S(e, "Vorher"); c.Nachher = S(e, "Nachher"); c.Status = S(e, "Status"); c.Ergebnis = S(e, "Ergebnis"); c.Gegenbefehl = S(e, "Gegenbefehl");
                    list.Add(c);
                }
            }
            catch { }
        }
        list.Sort(delegate(ChangeEntry a, ChangeEntry b) { int r = String.Compare(b.Zeit, a.Zeit, StringComparison.Ordinal); return r != 0 ? r : b.Id.CompareTo(a.Id); });
        return list;
    }
}

// Kurzfassung der Modulverträge aus dem Skript (Get-ContractGuiLines)
public class ContractStep
{
    public string Module = "", Key = "", Typ = "", Risiko = "", Neustart = "", Rueckgaengig = "", Text = "";
    public int Minuten; public bool Vorauswahl, Ueblich;
    public static string RiskLabel(string r)
    {
        switch (r) { case "Aendern": return "Ändern"; case "Zerstoerend": return "Zerstörend"; default: return r; }
    }
}

public class DiagGui : Form
{
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern bool FlashWindow(IntPtr h, bool invert);

    string psExe, script, cpDir, dataDir, dbDir, version;
    string[] disks;   // Nummer|Name|Bus|Medium|Größe|Buchstaben|USB
    Process proc;
    ConcurrentQueue<string> queue = new ConcurrentQueue<string>();
    Timer timer;
    volatile bool exited, outEof;
    DateTime exitSeen;
    bool running, done, gotDone, cancelled;
    string htmlPath = "", outDir = "", kiPath = "", kurzPath = "";
    int nK, nW, nI, cntK, cntW, cntI, testsOk, benchWarn, benchCount;
    Dictionary<string, ListViewItem> benchHeads = new Dictionary<string, ListViewItem>();
    List<DbEntry> db = new List<DbEntry>();

    Panel setupView, runView, content;
    List<NavItem> nav = new List<NavItem>();
    List<Control> pages = new List<Control>();
    int curPage;

    // Diagnose
    RadioButton rbSchnell, rbVoll, rbCustom, rbTest, rbCrash;
    string[] diagKeys = new string[] { "Ereignisse", "Updatesuche", "Integritaet", "Defender", "SmartLang", "Netzwerk", "RamTest", "CpuTest", "Energieanalyse" };
    string[] diagText = new string[] {
        "Ereignisprotokolle, Bluescreens, Absturzabbilder, Zuverlässigkeit",
        "Nach ausstehenden Windows-Updates suchen (bis 3 Minuten)",
        "Dateisystem-Onlinescan, DISM ScanHealth, sfc /verifyonly (nur prüfen)",
        "Microsoft Defender Schnellscan",
        "SMART-Langtest aller Laufwerke (SSD meist < 15 Min., HDD Stunden)",
        "Netzwerktest: Ping, DNS, HTTPS, Download",
        "RAM-Mustertest unter Windows",
        "CPU-Stabilitätstest mit Takt- und Temperaturüberwachung",
        "Energieeffizienzanalyse (60 s) und DxDiag-Bericht" };
    CheckBox[] diagChk;
    CheckBox chkInstall, chkMem;
    ComboBox cmbDays;
    // Benchmark
    string[] benchKeys = new string[] { "CPU", "RAM", "GPU", "Disk", "WinSAT" };
    string[] benchText = new string[] {
        "Prozessor: Einzel- und Mehrkern, AES-256, SHA-256, Kompression",
        "Arbeitsspeicher: Lesen, Schreiben, Kopieren, Latenz",
        "Grafik: Speicherdurchsatz, Desktop-Komposition, PCIe-Anbindung",
        "Laufwerke: sequentiell und 4K (Auswahl unten)",
        "WinSAT-Leistungsbewertung von Windows (2 bis 5 Minuten)" };
    CheckBox[] benchChk;
    CheckedListBox clbDisks, clbCompare;
    List<string> diskNums = new List<string>();
    ComboBox cmbBenchDur, cmbRef;
    CheckBox chkDbSave, chkRefSave;
    List<DbEntry> refItems = new List<DbEntry>(), cmpItems = new List<DbEntry>();
    // Lasttest
    CheckBox chkLCpu, chkLRam, chkLGpu, chkLDisk;
    ComboBox cmbLCpu, cmbLRam, cmbLGpu, cmbLDisk, cmbLRamPct, cmbLDiskDrive, cmbLAbortCpu, cmbLAbortGpu;
    // Sensoren (Live-Seite)
    NavItem navSens, navDb, navChg;
    Process liveProc;
    ConcurrentQueue<string> liveQueue = new ConcurrentQueue<string>();
    Timer liveTimer;
    volatile bool liveExited, liveEof;
    DateTime liveExitSeen;
    bool liveRunning, liveStopping;
    DateTime liveStopAt;
    Button btnLive, btnSensTools, btnSensSave;
    ComboBox cmbDriver;
    Label lblSensTools, lblSensInfo;
    SensorChart chartLive, chartRun;
    ListView lvSens;
    Dictionary<int, ListViewItem> sensItems = new Dictionary<int, ListViewItem>();
    Dictionary<int, double[]> sensMinMax = new Dictionary<int, double[]>();
    Dictionary<int, string> sensUnit = new Dictionary<int, string>();
    List<string> sensNames = new List<string>();
    List<string> sensRows = new List<string>();
    Dictionary<string, ListViewGroup> sensGroups = new Dictionary<string, ListViewGroup>();
    Label lblRunSens;
    // Reparatur
    string[] repKeys = new string[] { "DismRestore", "Sfc", "Komponentenbereinigung", "Dateisystem", "WindowsUpdate", "Netzwerk", "Temp", "WMI", "Zeit", "Druck", "Geraete", "Schnellstart", "Energieplaene" };
    string[] repText = new string[] {
        "Komponentenspeicher prüfen und reparieren (DISM ScanHealth, bei Bedarf RestoreHealth)",
        "Systemdateien reparieren (sfc /scannow, nach DISM)",
        "Komponentenspeicher bereinigen (DISM StartComponentCleanup, gibt Platz frei)",
        "Dateisystemfehler beheben (Onlinescan, SpotFix, Systemlaufwerk beim Neustart)",
        "Windows Update zurücksetzen (Dienste, SoftwareDistribution, catroot2)",
        "Netzwerk zurücksetzen (DNS-Cache, Winsock, TCP/IP), Neustart nötig",
        "Temporäre Dateien löschen (älter als 2 Tage, Übermittlungsoptimierung, Fehlerberichte)",
        "WMI-Repository prüfen und bei Bedarf reparieren",
        "Windows-Zeit neu synchronisieren",
        "Druckwarteschlange leeren und Druckspooler neu starten",
        "Geräte neu erkennen lassen (pnputil /scan-devices)",
        "Schnellstart deaktivieren (hilft bei Abstürzen nach dem Einschalten)",
        "Energiesparpläne auf Standard zurücksetzen (eigene Pläne werden vorher gesichert)" };
    int[] repMinutes = new int[] { 20, 12, 15, 5, 2, 1, 3, 2, 1, 1, 1, 1, 1 };
    CheckBox[] repChk;
    CheckBox chkRestorePoint;
    // Datenbank
    ListView lvDb;
    Label lblDbPath;
    // Modulverträge und Änderungsprotokoll
    Dictionary<string, string[]> modInfo = new Dictionary<string, string[]>();   // Name -> Titel, Kurz, Admin, Risiko, Neustart
    List<ContractStep> steps = new List<ContractStep>();
    string[] repRisk = new string[0];
    bool[] repDefault = new bool[0], repUsual = new bool[0];
    string changeDir = "";
    List<ChangeEntry> changes = new List<ChangeEntry>();
    ListView lvChg;
    Button btnUndo;
    // Fuß
    Label lblSel;
    CheckBox chkAnon;
    Button btnStart;

    // Ablauf
    Button btnStopWait, btnCancel, btnHtml, btnFolder, btnNew, btnKi, btnCopy;
    Label lblStep, lblCounter, lblSub, lblResult;
    FlatBar barAll, barSub;
    StatCard cardK, cardW, cardI, cardT;
    TabStrip tabs;
    ListView lvFind, lvTests, lvBench;
    TextBox txtLog;

    public static void Run(string psExe, string script, string cpDir, string dataDir, string version, string[] disks, string[] contract)
    {
        IntPtr con = IntPtr.Zero; bool wasVisible = false;
        try { SetProcessDPIAware(); } catch { }
        try { Application.EnableVisualStyles(); } catch { }
        try { Application.SetCompatibleTextRenderingDefault(false); } catch { }
        try { con = GetConsoleWindow(); if (con != IntPtr.Zero) { wasVisible = IsWindowVisible(con); ShowWindow(con, 0); } } catch { }
        try { Application.Run(new DiagGui(psExe, script, cpDir, dataDir, version, disks, contract)); }
        finally { if (con != IntPtr.Zero && wasVisible) ShowWindow(con, 5); }
    }

    static Label Lbl(string text, float size, bool bold, Color color)
    {
        Label l = new Label(); l.Text = text; l.AutoSize = true; l.ForeColor = color; l.BackColor = Color.Transparent;
        l.Font = new Font(bold ? "Segoe UI Semibold" : "Segoe UI", size); return l;
    }

    static string OsName()
    {
        try
        {
            using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
            {
                string pn = Convert.ToString(k.GetValue("ProductName")); string dv = Convert.ToString(k.GetValue("DisplayVersion"));
                int build = 0; int.TryParse(Convert.ToString(k.GetValue("CurrentBuildNumber")), out build);
                if (build >= 22000) pn = pn.Replace("Windows 10", "Windows 11");
                return (pn + " " + dv).Trim();
            }
        }
        catch { return "Windows"; }
    }

    public DiagGui(string psExe, string script, string cpDir, string dataDir, string version, string[] disks, string[] contract)
    {
        this.psExe = psExe; this.script = script; this.cpDir = cpDir; this.dataDir = dataDir ?? ""; this.version = version ?? "";
        this.disks = disks ?? new string[0];
        dbDir = this.dataDir.Length > 0 ? Path.Combine(this.dataDir, "Datenbank") : "";
        changeDir = this.dataDir.Length > 0 ? Path.Combine(this.dataDir, "Änderungen") : "";
        ReadContract(contract ?? new string[0]);
        Text = "Leos Minibench " + this.version;
        AutoScaleDimensions = new SizeF(96f, 96f); AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Segoe UI", 9.75f);
        BackColor = UI.Bg; ForeColor = UI.Text;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(1180, 800); MinimumSize = new Size(980, 680);
        try { Icon = Icon.ExtractAssociatedIcon(psExe); } catch { }

        Panel head = new Panel(); head.Dock = DockStyle.Top; head.Height = 78; head.BackColor = UI.Header;
        Label t1 = Lbl("Leos Minibench", 18f, true, Color.White); t1.Location = new Point(22, 10);
        Label t2 = Lbl(Environment.MachineName + "   ·   " + OsName() + "   ·   Version " + this.version, 9.75f, false, Color.FromArgb(170, 182, 200)); t2.Location = new Point(25, 48);
        head.Controls.Add(t1); head.Controls.Add(t2);

        Panel body = new Panel(); body.Dock = DockStyle.Fill; body.Padding = new Padding(20, 16, 20, 14); body.BackColor = UI.Bg;
        LoadDb();
        setupView = BuildSetup(); runView = BuildRun();
        setupView.Dock = DockStyle.Fill; runView.Dock = DockStyle.Fill; runView.Visible = false;
        body.Controls.Add(runView); body.Controls.Add(setupView);
        Controls.Add(body); Controls.Add(head);

        FormClosing += OnClosing;
        timer = new Timer(); timer.Interval = 150; timer.Tick += delegate { OnTick(); };
    }

    void LoadDb()
    {
        try { db = DbEntry.Load(dbDir); } catch { db = new List<DbEntry>(); }
        try { changes = ChangeEntry.Load(changeDir); } catch { changes = new List<ChangeEntry>(); }
    }

    // Modulverträge übernehmen: Navigation und Seite Reparatur richten sich danach (ohne Vertrag gelten die festen Listen)
    void ReadContract(string[] lines)
    {
        foreach (string l in lines)
        {
            string[] x = l.Split('|');
            if (x.Length >= 7 && x[0] == "M") modInfo[x[1]] = new string[] { x[2], x[3], x[4], x[5], x[6] };
            else if (x.Length >= 11 && x[0] == "S")
            {
                ContractStep c = new ContractStep(); c.Module = x[1]; c.Key = x[2]; c.Typ = x[3]; c.Risiko = x[4]; c.Neustart = x[5]; c.Rueckgaengig = x[6];
                int m; int.TryParse(x[7], out m); c.Minuten = m; c.Vorauswahl = x[8] == "1"; c.Ueblich = x[9] == "1"; c.Text = x[10];
                steps.Add(c);
            }
        }
        List<ContractStep> rep = steps.FindAll(delegate(ContractStep c) { return c.Module == "Reparatur" && c.Typ == "Massnahme"; });
        if (rep.Count > 0)
        {
            repKeys = new string[rep.Count]; repText = new string[rep.Count]; repMinutes = new int[rep.Count];
            repRisk = new string[rep.Count]; repDefault = new bool[rep.Count]; repUsual = new bool[rep.Count];
            for (int i = 0; i < rep.Count; i++)
            {
                repKeys[i] = rep[i].Key; repText[i] = rep[i].Text; repMinutes[i] = rep[i].Minuten;
                repRisk[i] = rep[i].Risiko; repDefault[i] = rep[i].Vorauswahl; repUsual[i] = rep[i].Ueblich;
            }
        }
        else
        {
            repRisk = new string[repKeys.Length]; repDefault = new bool[repKeys.Length]; repUsual = new bool[repKeys.Length];
            for (int i = 0; i < repKeys.Length; i++) { repRisk[i] = ""; repDefault[i] = i < 2; repUsual[i] = i < 2 || repKeys[i] == "Dateisystem" || repKeys[i] == "Temp" || repKeys[i] == "WMI"; }
        }
    }

    NavItem ModNav(string name, string title, string desc)
    {
        string[] mi; if (modInfo.TryGetValue(name, out mi)) { title = mi[0]; desc = mi[1]; }
        return new NavItem(title, desc);
    }

    // ------------------------------------------------------------ Einrichtung
    Panel BuildSetup()
    {
        Panel p = new Panel(); p.BackColor = UI.Bg;

        FlowLayoutPanel left = new FlowLayoutPanel(); left.Dock = DockStyle.Left; left.Width = 246; left.FlowDirection = FlowDirection.TopDown; left.WrapContents = false;
        left.BackColor = UI.Bg; left.Padding = new Padding(0, 0, 14, 0); left.AutoScroll = true;
        Label lm = Lbl("Module", 12f, true, UI.Text); lm.Margin = new Padding(2, 0, 0, 10); left.Controls.Add(lm);
        nav.Add(ModNav("Diagnose", "Diagnose", "Inventar, Prüfungen, Ereignisse"));
        nav.Add(ModNav("Benchmark", "Benchmark", "Wählbare Messungen mit Vergleich"));
        nav.Add(ModNav("Lasttest", "Lasttest", "Komponenten und Dauer wählbar"));
        nav.Add(ModNav("Reparatur", "Reparatur", "SFC, DISM und weitere Fixes"));
        navSens = ModNav("Sensoren", "Sensoren live", "Temperatur, Takt, Lüfter, Leistung"); navSens.HasCheck = false; nav.Add(navSens);
        navDb = new NavItem("Vergleichsdatenbank", db.Count + " gespeicherte Systeme"); navDb.HasCheck = false; nav.Add(navDb);
        navChg = new NavItem("Änderungen", "Protokoll und Rückgängig"); navChg.HasCheck = false; nav.Add(navChg);
        for (int i = 0; i < nav.Count; i++)
        {
            int idx = i;
            nav[i].Picked += delegate { ShowPage(idx); };
            nav[i].CheckedChanged += delegate { UpdateSummary(); };
            left.Controls.Add(nav[i]);
        }
        nav[0].Checked = true;

        content = new Panel(); content.Dock = DockStyle.Fill; content.BackColor = UI.Panel; content.Padding = new Padding(22, 16, 16, 16); content.AutoScroll = true;
        Panel contentHost = new Panel(); contentHost.Dock = DockStyle.Fill; contentHost.BackColor = UI.Line; contentHost.Padding = new Padding(1);
        contentHost.Controls.Add(content);

        pages.Add(BuildDiagPage()); pages.Add(BuildBenchPage()); pages.Add(BuildLoadPage()); pages.Add(BuildRepairPage()); pages.Add(BuildSensorPage()); pages.Add(BuildDbPage()); pages.Add(BuildChangePage());
        foreach (Control c in pages) { c.Visible = false; content.Controls.Add(c); }

        TableLayoutPanel foot = new TableLayoutPanel(); foot.Dock = DockStyle.Bottom; foot.Height = 66; foot.ColumnCount = 2; foot.BackColor = UI.Bg; foot.Padding = new Padding(0, 12, 0, 0);
        foot.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); foot.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        FlowLayoutPanel fl = new FlowLayoutPanel(); fl.FlowDirection = FlowDirection.TopDown; fl.WrapContents = false; fl.AutoSize = true; fl.BackColor = UI.Bg; fl.Dock = DockStyle.Fill;
        lblSel = Lbl("", 10f, true, UI.Text); lblSel.Margin = new Padding(0, 0, 0, 2);
        FlowLayoutPanel fo = new FlowLayoutPanel(); fo.AutoSize = true; fo.WrapContents = false; fo.BackColor = UI.Bg; fo.Margin = new Padding(0);
        chkAnon = Chk("Persönliche Daten in der KI-Datei unkenntlich machen", true); chkAnon.Margin = new Padding(0, 2, 22, 0);
        Label ld = Lbl("Ablage: " + (this.dataDir.Length > 0 ? this.dataDir : "(kein Datenordner)"), 9f, false, UI.Muted); ld.Margin = new Padding(0, 4, 0, 0);
        fo.Controls.Add(chkAnon); fo.Controls.Add(ld);
        fl.Controls.Add(lblSel); fl.Controls.Add(fo);
        btnStart = UI.Primary("Start"); btnStart.Anchor = AnchorStyles.Right; btnStart.Margin = new Padding(12, 6, 0, 0);
        btnStart.Click += delegate { StartRun(); };
        foot.Controls.Add(fl, 0, 0); foot.Controls.Add(btnStart, 1, 0);

        p.Controls.Add(contentHost); p.Controls.Add(left); p.Controls.Add(foot);
        ShowPage(0);
        UpdateSummary();
        return p;
    }

    void ShowPage(int i)
    {
        curPage = i;
        for (int k = 0; k < nav.Count; k++) nav[k].Selected = (k == i);
        for (int k = 0; k < pages.Count; k++) pages[k].Visible = (k == i);
        content.AutoScrollPosition = new Point(0, 0);
    }

    static CheckBox Chk(string text, bool on)
    {
        CheckBox c = new CheckBox(); c.Text = text; c.AutoSize = true; c.Checked = on; c.ForeColor = UI.Text; c.Margin = new Padding(0, 3, 0, 3);
        return c;
    }

    static ComboBox Combo(int width, string[] items, int sel)
    {
        ComboBox c = new ComboBox(); c.DropDownStyle = ComboBoxStyle.DropDownList; c.Width = width; c.Margin = new Padding(0, 1, 16, 1);
        foreach (string s in items) c.Items.Add(s);
        if (items.Length > 0) c.SelectedIndex = Math.Min(sel, items.Length - 1);
        return c;
    }

    FlowLayoutPanel Page(string title, string hint, int idx)
    {
        FlowLayoutPanel f = new FlowLayoutPanel(); f.FlowDirection = FlowDirection.TopDown; f.WrapContents = false; f.AutoSize = true; f.BackColor = UI.Panel; f.Location = new Point(0, 0);
        f.Controls.Add(Lbl(title, 14f, true, UI.Text));
        Label h = Lbl(hint, 9.75f, false, UI.Muted); h.MaximumSize = new Size(820, 0); h.Margin = new Padding(3, 2, 3, 10); f.Controls.Add(h);
        if (idx >= 0)
        {
            CheckBox on = Chk("Dieses Modul beim Start ausführen", nav[idx].Checked);
            on.Font = new Font("Segoe UI Semibold", 9.75f); on.Margin = new Padding(0, 0, 0, 10);
            on.CheckedChanged += delegate { nav[idx].Checked = on.Checked; };
            nav[idx].CheckedChanged += delegate { if (on.Checked != nav[idx].Checked) on.Checked = nav[idx].Checked; };
            f.Controls.Add(on);
        }
        return f;
    }

    static Label Section(string text)
    {
        Label l = Lbl(text, 10.5f, true, UI.Text); l.Margin = new Padding(0, 12, 0, 4); return l;
    }

    static FlowLayoutPanel Row()
    {
        FlowLayoutPanel r = new FlowLayoutPanel(); r.AutoSize = true; r.WrapContents = false; r.BackColor = UI.Panel; r.Margin = new Padding(0, 2, 0, 2);
        return r;
    }

    static Label RowLabel(string text, int width)
    {
        Label l = Lbl(text, 9.75f, false, UI.Text); l.AutoSize = false; l.Width = width; l.Height = 24; l.TextAlign = ContentAlignment.MiddleLeft; l.Margin = new Padding(0, 1, 6, 1);
        return l;
    }

    Control BuildDiagPage()
    {
        FlowLayoutPanel f = Page("Diagnose", "Liest Hardware, Treiber, Sicherheit und Ereignisprotokolle aus, führt die gewählten Prüfungen durch und bewertet alles in einem Bericht. Prüfungen verändern nichts am System.", 0);
        if (File.Exists(Path.Combine(cpDir, "laufend.json")))
        {
            Label warn = Lbl("  Der letzte Lauf wurde nicht beendet (Absturz?). Die Absturzanalyse läuft beim nächsten Start automatisch zuerst.  ", 9.75f, true, UI.Crit);
            warn.BackColor = UI.CritBg; warn.Padding = new Padding(6); warn.Margin = new Padding(0, 0, 0, 8);
            f.Controls.Add(warn);
        }
        f.Controls.Add(Section("Umfang"));
        rbSchnell = new RadioButton(); rbVoll = new RadioButton(); rbCustom = new RadioButton(); rbTest = new RadioButton(); rbCrash = new RadioButton();
        RadioButton[] rbs = new RadioButton[] { rbVoll, rbSchnell, rbCustom, rbTest, rbCrash };
        string[] rt = new string[] {
            "Vollständig  (30 bis 60 Minuten, zuzüglich SMART-Langtest)",
            "Schnell  (5 bis 10 Minuten: Inventar, Ereignisse, Netzwerk, kurze RAM- und CPU-Tests)",
            "Benutzerdefiniert  (Prüfungen unten frei wählen)",
            "Funktionstest  (1 bis 2 Minuten, prüft nur das Skript)",
            "Nur Absturzanalyse  (letzter unterbrochener Lauf und Ereignisprotokolle)" };
        for (int i = 0; i < rbs.Length; i++) { rbs[i].Text = rt[i]; rbs[i].AutoSize = true; rbs[i].ForeColor = UI.Text; rbs[i].Margin = new Padding(0, 2, 0, 2); rbs[i].CheckedChanged += delegate { ApplyDiagProfile(); }; f.Controls.Add(rbs[i]); }
        f.Controls.Add(Section("Prüfungen"));
        diagChk = new CheckBox[diagKeys.Length];
        for (int i = 0; i < diagKeys.Length; i++) { diagChk[i] = Chk(diagText[i], true); diagChk[i].CheckedChanged += delegate { UpdateSummary(); }; f.Controls.Add(diagChk[i]); }
        f.Controls.Add(Section("Optionen"));
        chkInstall = Chk("smartmontools bei Bedarf installieren (winget) oder aus dem Datenordner verwenden", true); f.Controls.Add(chkInstall);
        chkMem = Chk("Windows-Speicherdiagnose beim nächsten Neustart einplanen", false); f.Controls.Add(chkMem);
        FlowLayoutPanel r = Row(); r.Controls.Add(RowLabel("Ereignisse der letzten", 150));
        cmbDays = Combo(110, new string[] { "3 Tage", "7 Tage", "14 Tage", "30 Tage", "60 Tage" }, 2); r.Controls.Add(cmbDays); f.Controls.Add(r);
        rbVoll.Checked = true;
        return f;
    }

    void ApplyDiagProfile()
    {
        if (diagChk == null) return;
        bool custom = rbCustom.Checked, crash = rbCrash.Checked;
        // Ereignisse, Updatesuche, Integritaet, Defender, SmartLang, Netzwerk, RamTest, CpuTest, Energieanalyse
        bool[] voll = new bool[] { true, true, true, true, true, true, true, true, true };
        bool[] schnell = new bool[] { true, true, false, false, false, true, true, true, false };
        bool[] test = new bool[] { true, false, false, false, false, true, true, true, false };
        bool[] none = new bool[] { true, false, false, false, false, false, false, false, false };
        bool[] pick = rbVoll.Checked ? voll : rbSchnell.Checked ? schnell : rbTest.Checked ? test : crash ? none : null;
        for (int i = 0; i < diagChk.Length; i++)
        {
            if (pick != null) diagChk[i].Checked = pick[i];
            diagChk[i].Enabled = custom;
        }
        chkInstall.Enabled = !crash && !rbTest.Checked;
        chkMem.Enabled = !crash && !rbTest.Checked;
        cmbDays.Enabled = !rbTest.Checked;
        UpdateSummary();
    }

    Control BuildBenchPage()
    {
        FlowLayoutPanel f = Page("Benchmark", "Misst die Leistung der gewählten Komponenten und vergleicht sie mit einer Referenz, mit früheren Läufen auf diesem PC und optional mit bereits geprüften Systemen.", 1);
        f.Controls.Add(Section("Messungen"));
        benchChk = new CheckBox[benchKeys.Length];
        for (int i = 0; i < benchKeys.Length; i++) { benchChk[i] = Chk(benchText[i], i < 4); benchChk[i].CheckedChanged += delegate { clbDisks.Enabled = benchChk[3].Checked; UpdateSummary(); }; f.Controls.Add(benchChk[i]); }
        f.Controls.Add(Section("Laufwerke"));
        clbDisks = new CheckedListBox(); clbDisks.CheckOnClick = true; clbDisks.Width = 640; clbDisks.BorderStyle = BorderStyle.FixedSingle; clbDisks.IntegralHeight = false;
        foreach (string d in disks)
        {
            string[] x = d.Split('|');
            if (x.Length < 7) continue;
            string letters = x[5].Length > 0 ? x[5] : "kein Laufwerksbuchstabe";
            clbDisks.Items.Add(String.Format("Datenträger {0}:  {1}   ({2}, {3}, {4}, {5})", x[0], x[1], x[2], x[3], x[4], letters), x[6] != "1" && x[5].Length > 0);
            diskNums.Add(x[0]);
        }
        clbDisks.Height = Math.Max(48, Math.Min(8, clbDisks.Items.Count) * 21 + 6);
        clbDisks.ItemCheck += delegate { BeginInvoke(new MethodInvoker(UpdateSummary)); };
        f.Controls.Add(clbDisks);
        Label dh = Lbl("Gemessen wird mit einer Testdatei auf dem Volume mit dem meisten freien Platz. USB-Datenträger sind standardmäßig abgewählt.", 8.75f, false, UI.Muted); dh.Margin = new Padding(3, 3, 3, 0); dh.MaximumSize = new Size(820, 0); f.Controls.Add(dh);

        f.Controls.Add(Section("Messdauer und Referenz"));
        FlowLayoutPanel r1 = Row(); r1.Controls.Add(RowLabel("Messdauer", 150));
        cmbBenchDur = Combo(260, new string[] { "Normal (stabile Werte)", "Kurz (etwa halbe Dauer)" }, 0); cmbBenchDur.SelectedIndexChanged += delegate { UpdateSummary(); }; r1.Controls.Add(cmbBenchDur); f.Controls.Add(r1);
        FlowLayoutPanel r2 = Row(); r2.Controls.Add(RowLabel("Referenz (100 %)", 150));
        cmbRef = Combo(520, new string[0], 0); r2.Controls.Add(cmbRef); f.Controls.Add(r2);
        f.Controls.Add(Section("Bereits geprüfte Systeme einblenden"));
        clbCompare = new CheckedListBox(); clbCompare.CheckOnClick = true; clbCompare.Width = 640; clbCompare.BorderStyle = BorderStyle.FixedSingle; clbCompare.IntegralHeight = false;
        f.Controls.Add(clbCompare);
        Label ch = Lbl("Die gewählten Systeme erscheinen im Bericht, in der KI-Datei und im Reiter Leistung als zusätzliche Vergleichswerte.", 8.75f, false, UI.Muted); ch.Margin = new Padding(3, 3, 3, 0); ch.MaximumSize = new Size(820, 0); f.Controls.Add(ch);
        f.Controls.Add(Section("Speichern"));
        chkDbSave = Chk("Ergebnis in der Vergleichsdatenbank speichern", dbDir.Length > 0); chkDbSave.Enabled = dbDir.Length > 0; f.Controls.Add(chkDbSave);
        chkRefSave = Chk("Dieses System als Standardreferenz (100 %) festlegen", false); f.Controls.Add(chkRefSave);
        FillRefLists();
        return f;
    }

    void FillRefLists()
    {
        if (cmbRef == null) return;
        string prevRef = cmbRef.SelectedIndex > 1 && cmbRef.SelectedIndex - 2 < refItems.Count ? refItems[cmbRef.SelectedIndex - 2].Path : "";
        HashSet<string> prevCmp = new HashSet<string>();
        for (int i = 0; i < clbCompare.Items.Count; i++) if (clbCompare.GetItemChecked(i) && i < cmpItems.Count) prevCmp.Add(cmpItems[i].Path);
        cmbRef.Items.Clear(); refItems.Clear(); clbCompare.Items.Clear(); cmpItems.Clear();
        cmbRef.Items.Add("Standard (gespeicherte Referenz, sonst eingebaute Referenz TORRENT)");
        cmbRef.Items.Add("Median aller Systeme in der Vergleichsdatenbank");
        int sel = 0;
        foreach (DbEntry e in db)
        {
            if (!e.HasBench) continue;
            refItems.Add(e); cmbRef.Items.Add(e.Label);
            if (e.Path == prevRef) sel = cmbRef.Items.Count - 1;
            cmpItems.Add(e); clbCompare.Items.Add(e.Label, prevCmp.Contains(e.Path));
        }
        cmbRef.SelectedIndex = sel;
        if (clbCompare.Items.Count == 0) { clbCompare.Items.Add("(noch keine Systeme mit Benchmark in der Datenbank)"); clbCompare.Enabled = false; }
        else clbCompare.Enabled = true;
        clbCompare.Height = Math.Max(48, Math.Min(8, clbCompare.Items.Count) * 21 + 6);
    }

    Control BuildLoadPage()
    {
        FlowLayoutPanel f = Page("Lasttest", "Belastet die gewählten Komponenten gleichzeitig, jede mit eigener Dauer. Überwacht werden Temperatur, Takt, Leistung und Lüfter als Kurven, dazu Rechen- und Bitfehler, Datenfehler und WHEA-Hardwarefehler. Am Ende steht ein Drosselnachweis. Mit \"Test beenden\" lässt sich jederzeit abbrechen.", 2);
        string[] mins = new string[] { "5 Minuten", "10 Minuten", "15 Minuten", "30 Minuten", "60 Minuten", "120 Minuten", "240 Minuten" };
        f.Controls.Add(Section("Komponenten und Dauer"));
        FlowLayoutPanel r1 = Row(); chkLCpu = Chk("Prozessor (alle Threads, Ergebnisprüfung)", true); chkLCpu.Width = 330; chkLCpu.AutoSize = false; r1.Controls.Add(chkLCpu);
        cmbLCpu = Combo(120, mins, 2); r1.Controls.Add(cmbLCpu); f.Controls.Add(r1);
        FlowLayoutPanel r2 = Row(); chkLRam = Chk("Arbeitsspeicher (Mustertest, Bitfehler)", true); chkLRam.Width = 330; chkLRam.AutoSize = false; r2.Controls.Add(chkLRam);
        cmbLRam = Combo(120, mins, 2); r2.Controls.Add(cmbLRam);
        r2.Controls.Add(RowLabel("Anteil am freien RAM", 140)); cmbLRamPct = Combo(80, new string[] { "25 %", "40 %", "60 %", "75 %" }, 1); r2.Controls.Add(cmbLRamPct); f.Controls.Add(r2);
        FlowLayoutPanel r3 = Row(); chkLGpu = Chk("Grafik (WinSAT-DWM-Schleife, leichte Last)", false); chkLGpu.Width = 330; chkLGpu.AutoSize = false; r3.Controls.Add(chkLGpu);
        cmbLGpu = Combo(120, mins, 2); r3.Controls.Add(cmbLGpu); f.Controls.Add(r3);
        FlowLayoutPanel r4 = Row(); chkLDisk = Chk("Datenträger (Schreiben, Lesen, Datenprüfung)", false); chkLDisk.Width = 330; chkLDisk.AutoSize = false; r4.Controls.Add(chkLDisk);
        cmbLDisk = Combo(120, mins, 1); r4.Controls.Add(cmbLDisk);
        r4.Controls.Add(RowLabel("Laufwerk", 70));
        List<string> letters = new List<string>();
        foreach (string d in disks)
        {
            string[] x = d.Split('|'); if (x.Length < 7 || x[5].Length == 0) continue;
            foreach (string l in x[5].Split(',')) { string t = l.Trim(); if (t.Length > 0) letters.Add(t + "   " + x[1]); }
        }
        if (letters.Count == 0) letters.Add("C:");
        letters.Sort();
        cmbLDiskDrive = Combo(260, letters.ToArray(), 0); r4.Controls.Add(cmbLDiskDrive); f.Controls.Add(r4);
        foreach (CheckBox c in new CheckBox[] { chkLCpu, chkLRam, chkLGpu, chkLDisk }) c.CheckedChanged += delegate { UpdateLoadEnabled(); UpdateSummary(); };
        foreach (ComboBox c in new ComboBox[] { cmbLCpu, cmbLRam, cmbLGpu, cmbLDisk }) c.SelectedIndexChanged += delegate { UpdateSummary(); };
        f.Controls.Add(Section("Abbruchschwelle"));
        FlowLayoutPanel r5 = Row(); r5.Controls.Add(RowLabel("CPU-Temperatur", 140));
        cmbLAbortCpu = Combo(260, new string[] { "automatisch (TjMax, sonst 100 °C)", "85 °C", "90 °C", "95 °C", "100 °C", "aus" }, 0); r5.Controls.Add(cmbLAbortCpu);
        r5.Controls.Add(RowLabel("GPU-Temperatur", 120)); cmbLAbortGpu = Combo(100, new string[] { "85 °C", "90 °C", "95 °C", "aus" }, 1); r5.Controls.Add(cmbLAbortGpu); f.Controls.Add(r5);
        Label ha = Lbl("Liegt die Temperatur drei Messpunkte in Folge (rund 10 Sekunden) auf oder über der Schwelle, endet der Test mit einem Befund. Kurven, Drosselnachweis und Abbruch nutzen die Sensoren (Seite Sensoren live). Echte CPU-Temperaturen gibt es mit LibreHardwareMonitor und dem PawnIO-Treiber, der nur nach Rückfrage installiert und nach dem Lauf entfernt wird.", 8.75f, false, UI.Muted);
        ha.MaximumSize = new Size(820, 0); ha.Margin = new Padding(3, 4, 3, 0); f.Controls.Add(ha);
        Label h = Lbl("Hinweise: Die Grafiklast über WinSAT ist gering, für echte GPU-Dauerlast eignen sich OCCT oder FurMark. Der Datenträgertest schreibt eine Testdatei (bis 4 GB) und löscht sie danach wieder. Am Notebook das Netzteil anschließen.", 8.75f, false, UI.Muted);
        h.MaximumSize = new Size(820, 0); h.Margin = new Padding(3, 12, 3, 0); f.Controls.Add(h);
        UpdateLoadEnabled();
        return f;
    }

    void UpdateLoadEnabled()
    {
        cmbLCpu.Enabled = chkLCpu.Checked; cmbLRam.Enabled = chkLRam.Checked; cmbLRamPct.Enabled = chkLRam.Checked;
        cmbLGpu.Enabled = chkLGpu.Checked; cmbLDisk.Enabled = chkLDisk.Checked; cmbLDiskDrive.Enabled = chkLDisk.Checked;
    }

    Control BuildRepairPage()
    {
        FlowLayoutPanel f = Page("Reparatur", "Führt die gewählten Standardreparaturen nacheinander aus. Vorher wird auf Wunsch ein Wiederherstellungspunkt angelegt. Einige Reparaturen werden erst nach einem Neustart wirksam.", 3);
        f.Controls.Add(Section("Absicherung"));
        chkRestorePoint = Chk("Vorher einen Systemwiederherstellungspunkt anlegen", true); f.Controls.Add(chkRestorePoint);
        f.Controls.Add(Section("Reparaturen"));
        repChk = new CheckBox[repKeys.Length];
        for (int i = 0; i < repKeys.Length; i++)
        {
            string t = repText[i] + (repRisk[i].Length > 0 ? "   ·  " + ContractStep.RiskLabel(repRisk[i]) : "");
            repChk[i] = Chk(t, repDefault[i]); repChk[i].CheckedChanged += delegate { UpdateSummary(); }; f.Controls.Add(repChk[i]);
        }
        Label lg = Lbl("Ändern: wird mit Vorher-Wert protokolliert und lässt sich auf der Seite Änderungen zurücknehmen.  Eingriff: nicht automatisch umkehrbar, Absicherung über den Wiederherstellungspunkt.", 8.75f, false, UI.Muted);
        lg.MaximumSize = new Size(820, 0); lg.Margin = new Padding(3, 8, 3, 0); f.Controls.Add(lg);
        FlowLayoutPanel b = Row(); b.Margin = new Padding(0, 10, 0, 0);
        Button all = UI.Secondary("Übliche Auswahl"); all.Margin = new Padding(0);
        all.Click += delegate { for (int i = 0; i < repChk.Length; i++) repChk[i].Checked = repUsual[i]; };
        Button none = UI.Secondary("Keine");
        none.Click += delegate { foreach (CheckBox c in repChk) c.Checked = false; };
        b.Controls.Add(all); b.Controls.Add(none); f.Controls.Add(b);
        return f;
    }

    Control BuildDbPage()
    {
        FlowLayoutPanel f = Page("Vergleichsdatenbank", "Jeder Lauf wird als System gespeichert. Hier lassen sich bereits geprüfte Systeme ohne neuen Benchmark vergleichen: mindestens zwei Systeme anhaken und \"Vergleichen\" klicken. Ältere Ausgabeordner lassen sich importieren.", -1);
        lblDbPath = Lbl("Datenbank: " + (dbDir.Length > 0 ? dbDir : "(nicht verfügbar)"), 9f, false, UI.Muted); lblDbPath.Margin = new Padding(3, 0, 3, 8); f.Controls.Add(lblDbPath);
        lvDb = new ListView(); lvDb.View = View.Details; lvDb.FullRowSelect = true; lvDb.CheckBoxes = true; lvDb.Width = 880; lvDb.Height = 360; lvDb.BorderStyle = BorderStyle.FixedSingle; lvDb.HideSelection = false; lvDb.ShowItemToolTips = true;
        string[] cols = new string[] { "Computer", "Datum", "Prozessor", "Grafik", "Arbeitsspeicher", "CPU Mehrkern", "RAM Lesen", "GPU", "Befunde K/W/I" };
        int[] w = new int[] { 128, 100, 128, 122, 112, 82, 70, 66, 62 };
        for (int i = 0; i < cols.Length; i++) lvDb.Columns.Add(cols[i], w[i]);
        lvDb.DoubleClick += delegate { if (lvDb.SelectedItems.Count > 0) OpenEntry((DbEntry)lvDb.SelectedItems[0].Tag); };
        lvDb.ItemChecked += delegate { UpdateDbButtons(); };
        f.Controls.Add(lvDb);
        Label hint = Lbl("Doppelklick öffnet den Bericht des Laufs. Graue Einträge enthalten keine Benchmark-Werte.", 8.75f, false, UI.Muted); hint.Margin = new Padding(3, 4, 3, 0); f.Controls.Add(hint);
        FlowLayoutPanel b = Row(); b.Margin = new Padding(0, 10, 0, 0);
        btnCompare = UI.Primary("Vergleichen"); btnCompare.Margin = new Padding(0); btnCompare.Padding = new Padding(14, 3, 14, 3); btnCompare.Font = new Font("Segoe UI Semibold", 9.75f);
        btnCompare.Click += delegate { CompareSelected(); };
        Button imp = UI.Secondary("Importieren ...");
        imp.Click += delegate { ImportFolder(); };
        btnDelete = UI.Secondary("Entfernen"); btnDelete.Click += delegate { DeleteSelected(); };
        Button rel = UI.Secondary("Aktualisieren"); rel.Click += delegate { ReloadDb(); };
        Button open = UI.Secondary("Datenordner"); open.Click += delegate { if (dataDir.Length > 0) OpenShell(dataDir); };
        b.Controls.Add(btnCompare); b.Controls.Add(imp); b.Controls.Add(btnDelete); b.Controls.Add(rel); b.Controls.Add(open); f.Controls.Add(b);
        FillDbList();
        return f;
    }

    // ------------------------------------------------------------ Seite Sensoren (live)
    string ToolsDir { get { return dataDir.Length > 0 ? Path.Combine(dataDir, "Tools") : ""; } }
    bool LhmPresent { get { return ToolsDir.Length > 0 && File.Exists(Path.Combine(ToolsDir, "LibreHardwareMonitor", "LibreHardwareMonitorLib.dll")); } }
    bool PawnSetupPresent { get { return ToolsDir.Length > 0 && File.Exists(Path.Combine(ToolsDir, "PawnIO", "PawnIO_setup.exe")); } }

    // Version des installierten PawnIO (wie LibreHardwareMonitor: Uninstall\PawnIO, sonst 64-Bit-Ansicht), leer = nicht installiert
    static string PawnIoVersion()
    {
        foreach (Microsoft.Win32.RegistryView v in new Microsoft.Win32.RegistryView[] { Microsoft.Win32.RegistryView.Default, Microsoft.Win32.RegistryView.Registry64 })
        {
            try
            {
                using (Microsoft.Win32.RegistryKey b = Microsoft.Win32.RegistryKey.OpenBaseKey(Microsoft.Win32.RegistryHive.LocalMachine, v))
                using (Microsoft.Win32.RegistryKey k = b.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO"))
                    if (k != null) { string s = Convert.ToString(k.GetValue("DisplayVersion")); if (s.Length > 0) return s; }
            }
            catch { }
        }
        return "";
    }

    // 1 = Treiber vorübergehend installieren, 0 = ohne, -1 = Start abbrechen
    int AskDriver()
    {
        if (!LhmPresent || !PawnSetupPresent || PawnIoVersion().Length > 0) return 0;
        int pol = cmbDriver == null ? 0 : cmbDriver.SelectedIndex;
        if (pol == 1) return 1;
        if (pol == 2) return 0;
        DialogResult r = MessageBox.Show(this,
            "Für CPU-Temperatur, CPU-Takt, CPU-Leistung und die Lüfter am Mainboard braucht LibreHardwareMonitor den Treiber PawnIO.\r\n\r\n" +
            "Soll PawnIO für diesen Lauf vorübergehend installiert werden? Er wird am Ende wieder entfernt, nach einem Absturz beim nächsten Start. Die Installation erscheint als Hinweis auf der Seite Änderungen.\r\n\r\n" +
            "Ja: mit Treiber   ·   Nein: ohne Treiber (GPU, Datenträger und Ersatzwerte)",
            "PawnIO-Treiber", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
        if (r == DialogResult.Cancel) return -1;
        return r == DialogResult.Yes ? 1 : 0;
    }

    void UpdateSensTools()
    {
        if (lblSensTools == null) return;
        string pv = PawnIoVersion();
        string t;
        if (!LhmPresent) t = "LibreHardwareMonitor fehlt im Tools-Ordner. Ohne die Bibliothek zeigt die Seite nur Ersatzwerte (Windows-Takt, ACPI, nvidia-smi, Datenträger, Akku).";
        else t = "LibreHardwareMonitor liegt im Tools-Ordner (geladen wird nur mit passender Prüfsumme).";
        t += pv.Length > 0 ? "  PawnIO " + pv + " ist auf diesem PC installiert und bleibt unverändert." : (PawnSetupPresent ? "  PawnIO ist nicht installiert; das Setup liegt bereit." : "  PawnIO-Setup fehlt.");
        lblSensTools.Text = t;
        lblSensTools.ForeColor = LhmPresent ? UI.Muted : UI.Warn;
        btnSensTools.Text = LhmPresent && PawnSetupPresent ? "Sensorwerkzeuge erneut holen" : "Sensorwerkzeuge holen";
    }

    Control BuildSensorPage()
    {
        FlowLayoutPanel f = Page("Sensoren live", "Zeigt Temperatur, Takt, Lüfter, Spannung und Leistung laufend an, mit Kurven der letzten zehn Minuten. Quelle ist LibreHardwareMonitor (portabel im Tools-Ordner); CPU-Werte und Mainboard-Lüfter brauchen den Treiber PawnIO, der nur nach Rückfrage installiert und beim Beenden wieder entfernt wird.", -1);
        lblSensTools = Lbl("", 9f, false, UI.Muted); lblSensTools.MaximumSize = new Size(880, 0); lblSensTools.Margin = new Padding(3, 0, 3, 8); f.Controls.Add(lblSensTools);
        FlowLayoutPanel b = Row(); b.Margin = new Padding(0, 0, 0, 8);
        btnLive = UI.Primary("Live-Ansicht starten"); btnLive.Margin = new Padding(0); btnLive.Padding = new Padding(14, 3, 14, 3); btnLive.Font = new Font("Segoe UI Semibold", 9.75f);
        btnLive.Click += delegate { if (liveRunning) StopLive(); else StartLive(); };
        btnSensTools = UI.Secondary("Sensorwerkzeuge holen"); btnSensTools.Click += delegate { FetchSensorTools(); };
        btnSensSave = UI.Secondary("Aufzeichnung speichern"); btnSensSave.Enabled = false; btnSensSave.Click += delegate { SaveSensorCsv(); };
        b.Controls.Add(btnLive); b.Controls.Add(btnSensTools); b.Controls.Add(btnSensSave);
        f.Controls.Add(b);
        FlowLayoutPanel bd = Row(); bd.Margin = new Padding(0, 0, 0, 8);
        bd.Controls.Add(RowLabel("PawnIO-Treiber", 120));
        cmbDriver = Combo(230, new string[] { "bei Bedarf nachfragen", "vorübergehend verwenden", "nicht verwenden" }, 0); bd.Controls.Add(cmbDriver);
        Label ld = Lbl("gilt für Live-Ansicht, Diagnose und Lasttest; ein vorhandener PawnIO bleibt immer unverändert", 8.75f, false, UI.Muted); ld.Margin = new Padding(0, 5, 0, 0); bd.Controls.Add(ld);
        f.Controls.Add(bd);
        lblSensInfo = Lbl("Live-Ansicht nicht gestartet.", 9f, false, UI.Muted); lblSensInfo.MaximumSize = new Size(880, 0); lblSensInfo.Margin = new Padding(3, 0, 3, 6); f.Controls.Add(lblSensInfo);
        chartLive = new SensorChart(); chartLive.Width = 880; chartLive.Height = 330; chartLive.WindowSec = 600; chartLive.Margin = new Padding(0, 0, 0, 8);
        chartLive.Empty = "Noch keine Messwerte. \"Live-Ansicht starten\" öffnet die Sensoren.";
        f.Controls.Add(chartLive);
        lvSens = new ListView(); lvSens.View = View.Details; lvSens.FullRowSelect = true; lvSens.Width = 880; lvSens.Height = 380; lvSens.BorderStyle = BorderStyle.FixedSingle; lvSens.HideSelection = false; lvSens.ShowGroups = true;
        string[] cols = new string[] { "Sensor", "Art", "Aktuell", "Min", "Max", "Quelle" };
        int[] w = new int[] { 260, 120, 110, 110, 110, 140 };
        for (int i = 0; i < cols.Length; i++) lvSens.Columns.Add(cols[i], w[i], i >= 2 && i <= 4 ? HorizontalAlignment.Right : HorizontalAlignment.Left);
        f.Controls.Add(lvSens);
        Label hint = Lbl("Aufzeichnung speichern legt alle Werte seit dem Start als CSV unter Berichte\\Sensoren im Datenordner ab. Während eines Laufs (Diagnose, Lasttest) ist die Live-Ansicht beendet; der Lasttest zeigt seine Kurven im Reiter Sensoren.", 8.75f, false, UI.Muted);
        hint.MaximumSize = new Size(880, 0); hint.Margin = new Padding(3, 4, 3, 0); f.Controls.Add(hint);
        liveTimer = new Timer(); liveTimer.Interval = 250; liveTimer.Tick += delegate { OnLiveTick(); };
        UpdateSensTools();
        return f;
    }

    void FetchSensorTools()
    {
        if (liveRunning) { MessageBox.Show(this, "Bitte zuerst die Live-Ansicht beenden.", "Leos Minibench"); return; }
        if (MessageBox.Show(this, "LibreHardwareMonitor " + "0.9.6 und PawnIO-Setup 2.2.0 aus den offiziellen GitHub-Releases holen?\r\n\r\nDie Dateien werden mit festen SHA-256-Werten geprüft und nur im Tools-Ordner des Datenordners abgelegt. Auf diesem PC wird nichts installiert.", "Sensorwerkzeuge holen", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        List<string> lines; string res = RunHelperPumped("-SensorWerkzeugeHolen", out lines, 900);
        UpdateSensTools();
        MessageBox.Show(this, lines.Count > 0 ? String.Join("\r\n", lines.ToArray()) : "Keine Rückmeldung vom Arbeitsprozess.", "Sensorwerkzeuge", MessageBoxButtons.OK, res == "1" ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
    }

    void StartLive()
    {
        if (running) return;
        int d = AskDriver(); if (d < 0) return;
        try { Directory.CreateDirectory(cpDir); File.Delete(Path.Combine(cpDir, "sensor.stop")); } catch { }
        string args = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -EventMode -SensorLive" + (dataDir.Length > 0 ? " -DatenDir " + Q(dataDir) : "") + (d == 1 ? " -SensorTreiber" : "");
        ProcessStartInfo psi = new ProcessStartInfo(psExe, args);
        psi.UseShellExecute = false; psi.CreateNoWindow = true; psi.RedirectStandardOutput = true; psi.RedirectStandardError = true; psi.RedirectStandardInput = true;
        psi.StandardOutputEncoding = new UTF8Encoding(false); psi.StandardErrorEncoding = OemEncoding();
        liveProc = new Process(); liveProc.StartInfo = psi; liveProc.EnableRaisingEvents = true;
        liveProc.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) liveQueue.Enqueue(e.Data); else liveEof = true; };
        liveProc.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null && e.Data.Trim().Length > 0) liveQueue.Enqueue("@@SENSINFO|" + e.Data.Trim()); };
        liveProc.Exited += delegate { liveExited = true; };
        sensItems.Clear(); sensMinMax.Clear(); sensUnit.Clear(); sensNames.Clear(); sensRows.Clear(); sensGroups.Clear();
        lvSens.Items.Clear(); lvSens.Groups.Clear(); chartLive.Clear();
        string dummy; while (liveQueue.TryDequeue(out dummy)) { }
        liveExited = false; liveEof = false; liveStopping = false; liveExitSeen = DateTime.MinValue;
        try { liveProc.Start(); liveProc.BeginOutputReadLine(); liveProc.BeginErrorReadLine(); try { liveProc.StandardInput.Close(); } catch { } }
        catch (Exception ex) { MessageBox.Show(this, "PowerShell konnte nicht gestartet werden: " + ex.Message, "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Error); return; }
        liveRunning = true;
        btnLive.Text = "Live-Ansicht beenden"; btnSensTools.Enabled = false; btnSensSave.Enabled = false;
        lblSensInfo.Text = d == 1 ? "Wird gestartet, PawnIO wird vorübergehend installiert ..." : "Wird gestartet ...";
        liveTimer.Start();
    }

    void StopLive()
    {
        if (!liveRunning || liveStopping) return;
        liveStopping = true; liveStopAt = DateTime.Now;
        try { Directory.CreateDirectory(cpDir); File.WriteAllText(Path.Combine(cpDir, "sensor.stop"), "1"); } catch { }
        btnLive.Enabled = false; btnLive.Text = "Wird beendet ...";
        lblSensInfo.Text = "Wird beendet, ein vorübergehend installierter Treiber wird entfernt ...";
    }

    // Für Start eines Laufs und Schließen des Fensters: sauber beenden (Treiber entfernen), höchstens 60 Sekunden warten
    bool StopLiveAndWait()
    {
        if (!liveRunning) return true;
        StopLive();
        Cursor = Cursors.WaitCursor; Enabled = false;
        // Installation und Entfernung von PawnIO dürfen je bis zu 3 Minuten dauern
        DateTime until = DateTime.Now.AddSeconds(240);
        while (!liveExited && DateTime.Now < until) { Application.DoEvents(); System.Threading.Thread.Sleep(100); }
        bool killed = !liveExited;
        if (killed) KillProc(liveProc);
        DateTime eofUntil = DateTime.Now.AddSeconds(5);
        while (!liveEof && DateTime.Now < eofUntil) { Application.DoEvents(); System.Threading.Thread.Sleep(50); }
        liveExited = true;
        Enabled = true; Cursor = Cursors.Default;
        OnLiveTick();
        if (killed) CleanupDriver();
        return true;
    }

    void OnLiveTick()
    {
        string line; int n = 0;
        if (!liveQueue.IsEmpty)
        {
            lvSens.BeginUpdate();
            try { while (n < 2000 && liveQueue.TryDequeue(out line)) { n++; HandleLiveLine(line); } }
            finally { lvSens.EndUpdate(); }
        }
        bool killed = false;
        if (liveStopping && !liveExited && (DateTime.Now - liveStopAt).TotalSeconds > 240) { KillProc(liveProc); killed = true; }
        if (liveExited && liveExitSeen == DateTime.MinValue) liveExitSeen = DateTime.Now;
        if (liveExited && (liveEof || (DateTime.Now - liveExitSeen).TotalSeconds > 5) && liveQueue.IsEmpty && liveRunning)
        {
            liveRunning = false; liveStopping = false; liveTimer.Stop();
            btnLive.Enabled = true; btnLive.Text = "Live-Ansicht starten"; btnSensTools.Enabled = true; btnSensSave.Enabled = sensRows.Count > 0;
            if (killed || PawnMarkerExists) CleanupDriver();
            UpdateSensTools();
            ReloadDb();
        }
    }

    // Markierung eines vorübergehend installierten PawnIO (wie Get-PawnIoMarker im Skript)
    string PawnMarker
    {
        get
        {
            if (dataDir.Length == 0) return "";
            string pc = Environment.GetEnvironmentVariable("COMPUTERNAME"); if (String.IsNullOrEmpty(pc)) pc = Environment.MachineName;
            string n = System.Text.RegularExpressions.Regex.Replace(pc, "[\\/:*?\"<>|\\s]+", "_").Trim('_');
            return Path.Combine(Path.Combine(dataDir, "Laufzeit"), "PawnIO_" + n + ".txt");
        }
    }
    bool PawnMarkerExists { get { string m = PawnMarker; return m.Length > 0 && File.Exists(m); } }

    // Treiberrest eines abgebrochenen Arbeitsprozesses sofort entfernen statt erst beim nächsten Start
    void CleanupDriver()
    {
        if (!PawnMarkerExists) return;
        List<string> lines;
        string ok = RunHelperPumped("-SensorAufraeumen", out lines, 300);
        string t = lines.Count > 0 ? String.Join(" ", lines.ToArray()) : "PawnIO-Treiber: keine Rückmeldung";
        if (lblSensInfo != null) lblSensInfo.Text = t;
        if (running || done) { lblCounter.Text = ok == "1" ? "PawnIO-Treiber wieder entfernt" : "PawnIO-Treiber noch installiert"; }
        if (ok != "1") MessageBox.Show(this, "Der vorübergehend installierte PawnIO-Treiber konnte nicht entfernt werden:\r\n\r\n" + t + "\r\n\r\nDer nächste Start von Leos Minibench versucht es erneut.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }

    // Wie RunHelper, aber ohne die Oberfläche einzufrieren (Downloads, Treiber entfernen)
    string RunHelperPumped(string args, out List<string> lines, int timeoutSec)
    {
        List<string> got = new List<string>();
        string result = "";
        ProcessStartInfo psi = new ProcessStartInfo(psExe, "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -EventMode " + args + (dataDir.Length > 0 ? " -DatenDir \"" + dataDir.TrimEnd('\\') + "\"" : ""));
        psi.UseShellExecute = false; psi.CreateNoWindow = true; psi.RedirectStandardOutput = true; psi.StandardOutputEncoding = new UTF8Encoding(false);
        bool eof = false;
        Cursor = Cursors.WaitCursor; bool was = Enabled; Enabled = false;
        try
        {
            using (Process p = new Process())
            {
                p.StartInfo = psi;
                p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data == null) { eof = true; return; } lock (got) got.Add(e.Data); };
                p.Start(); p.BeginOutputReadLine();
                DateTime until = DateTime.Now.AddSeconds(timeoutSec);
                while (!p.HasExited && DateTime.Now < until) { Application.DoEvents(); System.Threading.Thread.Sleep(50); }
                if (!p.HasExited) { KillProc(p); lock (got) got.Add("@@LOG||Abgebrochen nach " + timeoutSec + " Sekunden."); }
                DateTime eu = DateTime.Now.AddSeconds(5);
                while (!eof && DateTime.Now < eu) { Application.DoEvents(); System.Threading.Thread.Sleep(20); }
            }
        }
        catch (Exception ex) { lock (got) got.Add("@@LOG||" + ex.Message); }
        finally { Enabled = was; Cursor = Cursors.Default; }
        lines = new List<string>();
        lock (got)
            foreach (string l in got)
            {
                if (l.StartsWith("@@LOG|")) { string[] x = l.Split(new char[] { '|' }, 3); if (x.Length == 3 && x[2].Trim().Length > 0) lines.Add(x[2].Trim()); }
                else if (l.StartsWith("@@RESULT|")) result = l.Substring(9);
            }
        return result;
    }

    static void KillProc(Process p)
    {
        try
        {
            if (p != null && !p.HasExited)
            {
                ProcessStartInfo k = new ProcessStartInfo("taskkill.exe", "/T /F /PID " + p.Id); k.CreateNoWindow = true; k.UseShellExecute = false;
                Process kp = Process.Start(k); kp.WaitForExit(8000);
            }
        }
        catch { }
    }

    static double ParseD(string s) { double v; return double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : double.NaN; }

    static string FmtSens(double v, string unit)
    {
        if (double.IsNaN(v)) return "";
        string f = unit == "V" ? "0.000" : (unit == "W" || unit == "A") ? "0.0" : "0";
        return v.ToString(f, CultureInfo.GetCultureInfo("de-DE")) + " " + unit;
    }

    void HandleLiveLine(string line)
    {
        if (!line.StartsWith("@@")) return;
        string[] p = line.Substring(2).Split('|');
        switch (p[0])
        {
            case "SENSDEF":
                {
                    // SENSDEF|idx|Gruppe|Geraet|Art|Name|Einheit|Quelle
                    int idx = ToInt(p, 1);
                    string grp = Get(p, 2) + "  ·  " + Get(p, 3);
                    ListViewGroup lg;
                    if (!sensGroups.TryGetValue(grp, out lg)) { lg = new ListViewGroup(grp, grp); sensGroups[grp] = lg; lvSens.Groups.Add(lg); }
                    ListViewItem it = new ListViewItem(new string[] { Get(p, 5), Get(p, 4), "", "", "", Get(p, 7) }, lg);
                    sensItems[idx] = it; sensUnit[idx] = Get(p, 6); sensMinMax[idx] = new double[] { double.MaxValue, double.MinValue };
                    while (sensNames.Count <= idx) sensNames.Add("");
                    sensNames[idx] = (Get(p, 2) + " " + Get(p, 3) + " " + Get(p, 5) + " (" + Get(p, 6) + ")").Replace(";", ",");
                    lvSens.Items.Add(it);
                    break;
                }
            case "SENSVAL":
                {
                    // SENSVAL|Sekunde|idx:wert;idx:wert
                    if (sensRows.Count < 50000) sensRows.Add(Get(p, 1) + "|" + Get(p, 2));
                    foreach (string kv in Get(p, 2).Split(';'))
                    {
                        int c = kv.IndexOf(':'); if (c <= 0) continue;
                        int idx; if (!int.TryParse(kv.Substring(0, c), out idx)) continue;
                        double v = ParseD(kv.Substring(c + 1));
                        ListViewItem it; if (!sensItems.TryGetValue(idx, out it) || double.IsNaN(v)) continue;
                        double[] mm = sensMinMax[idx]; mm[0] = Math.Min(mm[0], v); mm[1] = Math.Max(mm[1], v);
                        string u = sensUnit[idx];
                        string a = FmtSens(v, u); if (it.SubItems[2].Text != a) it.SubItems[2].Text = a;
                        string mi = FmtSens(mm[0], u); if (it.SubItems[3].Text != mi) it.SubItems[3].Text = mi;
                        string ma = FmtSens(mm[1], u); if (it.SubItems[4].Text != ma) it.SubItems[4].Text = ma;
                    }
                    break;
                }
            case "SENSLEAD": chartLive.Add(p); break;
            case "SENSINFO": lblSensInfo.Text = Get(p, 1); break;
            case "SENSEND": lblSensInfo.Text = "Beendet. " + Get(p, 1); break;
            case "LOG": { string t = p.Length > 2 ? String.Join("|", p, 2, p.Length - 2).Trim() : ""; if (t.Length > 0) lblSensInfo.Text = t; break; }
        }
    }

    void SaveSensorCsv()
    {
        if (sensRows.Count == 0 || dataDir.Length == 0) return;
        try
        {
            string dir = Path.Combine(Path.Combine(dataDir, "Berichte"), "Sensoren");
            Directory.CreateDirectory(dir);
            string file = Path.Combine(dir, Environment.MachineName + "_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".csv");
            StringBuilder sb = new StringBuilder();
            sb.Append("Sekunde"); foreach (string n in sensNames) sb.Append(';').Append(n); sb.AppendLine();
            foreach (string r in sensRows)
            {
                string[] x = r.Split(new char[] { '|' }, 2);
                string[] cells = new string[sensNames.Count];
                foreach (string kv in (x.Length > 1 ? x[1] : "").Split(';'))
                {
                    int c = kv.IndexOf(':'); int idx;
                    if (c > 0 && int.TryParse(kv.Substring(0, c), out idx) && idx < cells.Length) cells[idx] = kv.Substring(c + 1).Replace('.', ',');
                }
                sb.Append(x[0]); foreach (string c in cells) sb.Append(';').Append(c ?? ""); sb.AppendLine();
            }
            File.WriteAllText(file, sb.ToString(), new UTF8Encoding(true));
            OpenSelect(file);
        }
        catch (Exception ex) { MessageBox.Show(this, "Speichern fehlgeschlagen: " + ex.Message, "Leos Minibench"); }
    }

    // ------------------------------------------------------------ Seite Änderungen
    Control BuildChangePage()
    {
        FlowLayoutPanel f = Page("Änderungen", "Alles, was Leos Minibench an einem PC verändert hat, mit Vorher-Wert. Einträge der Stufe Ändern lassen sich auf dem PC, auf dem sie entstanden sind, zurücknehmen. Eingriffe stehen mit dem Weg zurück als Hinweis in der Liste.", -1);
        Label lp = Lbl("Protokoll: " + (changeDir.Length > 0 ? changeDir : "(nicht verfügbar)"), 9f, false, UI.Muted); lp.Margin = new Padding(3, 0, 3, 8); f.Controls.Add(lp);
        lvChg = new ListView(); lvChg.View = View.Details; lvChg.FullRowSelect = true; lvChg.CheckBoxes = true; lvChg.Width = 880; lvChg.Height = 360; lvChg.BorderStyle = BorderStyle.FixedSingle; lvChg.HideSelection = false; lvChg.ShowItemToolTips = true;
        string[] cols = new string[] { "Zeit", "Computer", "Maßnahme", "Ziel", "Vorher", "Nachher", "Status" };
        int[] w = new int[] { 112, 100, 170, 190, 90, 110, 96 };
        for (int i = 0; i < cols.Length; i++) lvChg.Columns.Add(cols[i], w[i]);
        lvChg.ItemCheck += delegate(object sender, ItemCheckEventArgs e)
        {
            ChangeEntry c = lvChg.Items[e.Index].Tag as ChangeEntry;
            if (c != null && !c.Undoable && e.NewValue == CheckState.Checked) e.NewValue = CheckState.Unchecked;
        };
        lvChg.ItemChecked += delegate(object sender, ItemCheckedEventArgs e)
        {
            ChangeEntry c = e.Item.Tag as ChangeEntry;
            if (e.Item.Checked && c != null && !c.Undoable) { e.Item.Checked = false; return; }
            UpdateChangeButtons();
        };
        f.Controls.Add(lvChg);
        Label hint = Lbl("Anhaken lassen sich nur aktive Einträge dieses PCs. Graue Einträge sind Hinweise, bereits zurückgenommen oder stammen von einem anderen PC.", 8.75f, false, UI.Muted); hint.Margin = new Padding(3, 4, 3, 0); f.Controls.Add(hint);
        FlowLayoutPanel b = Row(); b.Margin = new Padding(0, 10, 0, 0);
        btnUndo = UI.Primary("Rückgängig machen"); btnUndo.Margin = new Padding(0); btnUndo.Padding = new Padding(14, 3, 14, 3); btnUndo.Font = new Font("Segoe UI Semibold", 9.75f);
        btnUndo.Click += delegate { UndoSelected(); };
        Button rel = UI.Secondary("Aktualisieren"); rel.Click += delegate { ReloadDb(); };
        Button open = UI.Secondary("Protokollordner"); open.Click += delegate { if (changeDir.Length > 0 && Directory.Exists(changeDir)) OpenShell(changeDir); else if (dataDir.Length > 0) OpenShell(dataDir); };
        b.Controls.Add(btnUndo); b.Controls.Add(rel); b.Controls.Add(open); f.Controls.Add(b);
        FillChangeList();
        return f;
    }

    static string ShortTime(string d)
    {
        DateTime t;
        if (DateTime.TryParseExact(d, "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out t)) return t.ToString("dd.MM.yy HH:mm");
        return d;
    }

    void FillChangeList()
    {
        if (lvChg == null) return;
        lvChg.BeginUpdate(); lvChg.Items.Clear();
        int open = 0;
        foreach (ChangeEntry c in changes)
        {
            ListViewItem it = new ListViewItem(new string[] { ShortTime(c.Zeit), c.Computer, c.Titel, c.Ziel, c.Vorher, c.Nachher, c.Status });
            it.Tag = c;
            it.ToolTipText = ContractStep.RiskLabel(c.Risiko) + " · " + c.Art + (c.Gegenbefehl.Length > 0 ? "\r\nZurück: " + c.Gegenbefehl : "") + (c.Ergebnis.Length > 0 ? "\r\n" + c.Ergebnis : "");
            if (!c.Undoable) it.ForeColor = UI.Muted; else open++;
            lvChg.Items.Add(it);
        }
        lvChg.EndUpdate();
        if (navChg != null) { navChg.Desc = open == 1 ? "1 Änderung rückgängig machbar" : open > 1 ? open + " Änderungen rückgängig machbar" : changes.Count + (changes.Count == 1 ? " Eintrag" : " Einträge") + " im Protokoll"; navChg.Invalidate(); }
        UpdateChangeButtons();
    }

    List<ChangeEntry> CheckedChanges()
    {
        List<ChangeEntry> l = new List<ChangeEntry>();
        if (lvChg != null) foreach (ListViewItem it in lvChg.CheckedItems) { ChangeEntry c = it.Tag as ChangeEntry; if (c != null && c.Undoable) l.Add(c); }
        return l;
    }

    void UpdateChangeButtons()
    {
        if (btnUndo == null) return;
        int n = CheckedChanges().Count;
        btnUndo.Enabled = n > 0;
        btnUndo.Text = n > 1 ? n + " Änderungen rückgängig machen" : "Rückgängig machen";
    }

    void UndoSelected()
    {
        List<ChangeEntry> sel = CheckedChanges();
        if (sel.Count == 0) return;
        StringBuilder sb = new StringBuilder(); List<string> spec = new List<string>();
        foreach (ChangeEntry c in sel) { sb.AppendLine("·  " + c.Titel + ": " + c.Ziel + " wieder " + c.Vorher); spec.Add(c.FilePath + "*" + c.Id); }
        if (MessageBox.Show(this, "Diese Änderungen zurücknehmen?\r\n\r\n" + sb.ToString(), "Rückgängig machen", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        Cursor = Cursors.WaitCursor;
        List<string> lines = new List<string>();
        try { RunHelper("-Rueckgaengig \"" + String.Join(";", spec.ToArray()) + "\"", out lines); }
        catch (Exception ex) { lines.Add("Rückgängig fehlgeschlagen: " + ex.Message); }
        Cursor = Cursors.Default;
        ReloadDb();
        MessageBox.Show(this, lines.Count > 0 ? String.Join("\r\n", lines.ToArray()) : "Keine Rückmeldung vom Arbeitsprozess.", "Rückgängig", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    Button btnCompare, btnDelete;
    Font wsBold;

    static string ShortDate(string d)
    {
        DateTime t;
        if (DateTime.TryParseExact(d, "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out t)) return t.ToString("dd.MM.yy HH:mm");
        return d;
    }

    static string Num(double v, string fmt) { return v > 0 ? v.ToString(fmt, CultureInfo.GetCultureInfo("de-DE")) : ""; }

    void FillDbList()
    {
        if (lvDb == null) return;
        lvDb.BeginUpdate(); lvDb.Items.Clear();
        foreach (DbEntry e in db)
        {
            ListViewItem it = new ListViewItem(new string[] { e.Computer, ShortDate(e.Datum), e.Cpu, e.Gpu, e.Ram, Num(e.Get("CPU|MT"), "N0"), Num(e.Get("RAM|Lesen"), "N1") + (e.Get("RAM|Lesen") > 0 ? " GB/s" : ""), Num(e.Get("GPU|VMB"), "N0") + (e.Get("GPU|VMB") > 0 ? " GB/s" : ""), e.Befunde });
            it.Tag = e; it.ToolTipText = e.Name + (e.Disk.Length > 0 ? "\r\n" + e.Disk : "") + (e.HasBench ? "" : "\r\n(ohne Benchmark-Werte)");
            if (!e.HasBench) it.ForeColor = UI.Muted;
            lvDb.Items.Add(it);
        }
        lvDb.EndUpdate();
        if (navDb != null) { navDb.Desc = db.Count + " Systeme, vergleichen und verwalten"; navDb.Invalidate(); }
        UpdateDbButtons();
    }

    List<DbEntry> CheckedEntries()
    {
        List<DbEntry> l = new List<DbEntry>();
        if (lvDb != null) foreach (ListViewItem it in lvDb.CheckedItems) l.Add((DbEntry)it.Tag);
        return l;
    }

    void UpdateDbButtons()
    {
        if (btnCompare == null) return;
        int n = CheckedEntries().Count;
        btnCompare.Enabled = n >= 2; btnDelete.Enabled = n >= 1;
        btnCompare.Text = n >= 2 ? n + " Systeme vergleichen" : "Vergleichen";
    }

    void OpenEntry(DbEntry e)
    {
        if (e == null) return;
        if (e.Ordner.Length > 0)
        {
            string dir = System.IO.Path.IsPathRooted(e.Ordner) ? e.Ordner : System.IO.Path.Combine(dataDir, e.Ordner);
            string html = System.IO.Path.Combine(dir, "Diagnosebericht.html");
            if (File.Exists(html)) { OpenShell(html); return; }
            if (Directory.Exists(dir)) { OpenShell(dir); return; }
        }
        OpenSelect(e.Path);
    }

    string RunHelper(string args, out List<string> lines)
    {
        lines = new List<string>();
        ProcessStartInfo psi = new ProcessStartInfo(psExe, "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -EventMode " + args + " -DatenDir \"" + dataDir.TrimEnd('\\') + "\"");
        psi.UseShellExecute = false; psi.CreateNoWindow = true; psi.RedirectStandardOutput = true; psi.StandardOutputEncoding = new UTF8Encoding(false);
        string result = "";
        using (Process p = Process.Start(psi))
        {
            string all = p.StandardOutput.ReadToEnd(); p.WaitForExit(120000);
            foreach (string line in all.Split('\n'))
            {
                string l = line.TrimEnd('\r');
                if (l.StartsWith("@@LOG|")) { string[] x = l.Split(new char[] { '|' }, 3); if (x.Length == 3 && x[2].Trim().Length > 0) lines.Add(x[2].Trim()); }
                else if (l.StartsWith("@@RESULT|")) result = l.Substring(9);
            }
        }
        return result;
    }

    void CompareSelected()
    {
        List<DbEntry> sel = CheckedEntries();
        if (sel.Count < 2) return;
        List<string> paths = new List<string>(); foreach (DbEntry e in sel) paths.Add(e.Path);
        Cursor = Cursors.WaitCursor;
        string html = ""; List<string> lines = new List<string>();
        try { html = RunHelper("-Vergleich \"" + String.Join(";", paths.ToArray()) + "\"", out lines); }
        catch (Exception ex) { lines.Add(ex.Message); }
        Cursor = Cursors.Default;
        if (html.Length > 0 && File.Exists(html)) OpenShell(html);
        else MessageBox.Show(this, "Der Vergleich konnte nicht erstellt werden.\r\n\r\n" + String.Join("\r\n", lines.ToArray()), "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }

    void DeleteSelected()
    {
        List<DbEntry> sel = CheckedEntries();
        if (sel.Count == 0) return;
        StringBuilder sb = new StringBuilder();
        foreach (DbEntry e in sel) sb.AppendLine("·  " + e.Computer + "  " + e.Datum);
        if (MessageBox.Show(this, "Diese Einträge aus der Vergleichsdatenbank entfernen? Die Berichtsordner bleiben erhalten.\r\n\r\n" + sb.ToString(), "Leos Minibench", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        foreach (DbEntry e in sel) { try { File.Delete(e.Path); } catch { } }
        ReloadDb();
    }

    void ReloadDb() { LoadDb(); FillDbList(); FillRefLists(); FillChangeList(); UpdateSensTools(); }

    void ImportFolder()
    {
        if (dbDir.Length == 0) { MessageBox.Show(this, "Kein Datenordner verfügbar.", "Leos Minibench"); return; }
        using (FolderBrowserDialog fb = new FolderBrowserDialog())
        {
            fb.Description = "Ausgabeordner eines früheren Laufs (oder einen Ordner mit mehreren davon) wählen";
            if (fb.ShowDialog(this) != DialogResult.OK) return;
            Cursor = Cursors.WaitCursor;
            List<string> lines = new List<string>();
            try { RunHelper("-ImportOrdner \"" + fb.SelectedPath.TrimEnd('\\') + "\"", out lines); }
            catch (Exception ex) { lines.Add("Import fehlgeschlagen: " + ex.Message); }
            Cursor = Cursors.Default;
            ReloadDb();
            MessageBox.Show(this, lines.Count > 0 ? String.Join("\r\n", lines.ToArray()) : "Nichts importiert.", "Import", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }

    int Minutes(ComboBox c) { int v; return int.TryParse(Convert.ToString(c.SelectedItem).Split(' ')[0], out v) ? v : 15; }

    List<string> SelectedModules()
    {
        List<string> m = new List<string>();
        string[] names = new string[] { "Diagnose", "Benchmark", "Lasttest", "Reparatur" };
        for (int i = 0; i < 4; i++) if (nav[i].Checked) m.Add(names[i]);
        return m;
    }

    int EstimateMinutes()
    {
        int t = 0;
        if (nav[0].Checked)
        {
            if (rbCrash.Checked) t += 1;
            else if (rbTest.Checked) t += 2;
            else
            {
                t += 3;
                int[] add = new int[] { 1, 2, 12, 3, 10, 1, 2, 3, 2 };
                for (int i = 0; i < diagChk.Length; i++) if (diagChk[i].Checked) t += add[i];
            }
        }
        if (nav[1].Checked)
        {
            bool kurz = cmbBenchDur.SelectedIndex == 1;
            if (benchChk[0].Checked) t += kurz ? 1 : 2;
            if (benchChk[1].Checked) t += 1;
            if (benchChk[2].Checked) t += 1;
            if (benchChk[3].Checked) t += clbDisks.CheckedItems.Count * (kurz ? 1 : 1);
            if (benchChk[4].Checked) t += 4;
        }
        if (nav[2].Checked)
        {
            int m = 0;
            if (chkLCpu.Checked) m = Math.Max(m, Minutes(cmbLCpu)); if (chkLRam.Checked) m = Math.Max(m, Minutes(cmbLRam));
            if (chkLGpu.Checked) m = Math.Max(m, Minutes(cmbLGpu)); if (chkLDisk.Checked) m = Math.Max(m, Minutes(cmbLDisk) + 1);
            t += m + 1;
        }
        if (nav[3].Checked) for (int i = 0; i < repChk.Length; i++) if (repChk[i].Checked) t += repMinutes[i];
        return t;
    }

    void UpdateSummary()
    {
        if (lblSel == null || diagChk == null || benchChk == null || repChk == null || chkLCpu == null) return;
        List<string> m = SelectedModules();
        if (m.Count == 0) { lblSel.Text = "Kein Modul ausgewählt"; lblSel.ForeColor = UI.Crit; btnStart.Enabled = false; return; }
        int min = EstimateMinutes();
        lblSel.ForeColor = UI.Text;
        lblSel.Text = String.Join(" + ", m.ToArray()) + "   ·   geschätzt ca. " + Math.Max(1, min) + " Minuten" + (nav[0].Checked && diagChk[4].Checked && !rbCrash.Checked ? " zuzüglich SMART-Langtest" : "");
        btnStart.Enabled = true;
    }

    static string Q(string s) { return "\"" + (s ?? "").TrimEnd('\\') + "\""; }

    void StartRun()
    {
        List<string> mods = SelectedModules();
        if (mods.Count == 0) return;
        // Live-Ansicht und Lauf greifen auf dieselben Sensoren und denselben Treiber zu
        if (liveRunning && !StopLiveAndWait()) return;
        bool drv = false;
        if ((nav[0].Checked && !rbCrash.Checked) || nav[2].Checked) { int d = AskDriver(); if (d < 0) return; drv = d == 1; }
        StringBuilder a = new StringBuilder();
        a.Append("-NoProfile -ExecutionPolicy Bypass -File \"").Append(script).Append("\" -EventMode");
        a.Append(" -Module ").Append(String.Join(",", mods.ToArray()));
        if (dataDir.Length > 0) a.Append(" -DatenDir ").Append(Q(dataDir));
        if (!chkAnon.Checked) a.Append(" -KiOhneAnonymisierung");

        if (nav[0].Checked)
        {
            if (rbCrash.Checked) a.Append(" -AnalyzeLastRun");
            else
            {
                string prof = rbVoll.Checked ? "Voll" : rbSchnell.Checked ? "Schnell" : rbTest.Checked ? "Funktionstest" : "Benutzerdefiniert";
                a.Append(" -DiagProfil ").Append(prof);
                List<string> o = new List<string>();
                for (int i = 0; i < diagChk.Length; i++) if (diagChk[i].Checked) o.Add(diagKeys[i]);
                a.Append(" -DiagOptionen ").Append(o.Count > 0 ? String.Join(",", o.ToArray()) : "Keine");
                if (chkInstall.Enabled && chkInstall.Checked) a.Append(" -InstallSmartmontools");
                if (chkMem.Enabled && chkMem.Checked) a.Append(" -ScheduleWindowsMemTest");
            }
            if (cmbDays.Enabled) a.Append(" -EventDays ").Append(Convert.ToString(cmbDays.SelectedItem).Split(' ')[0]);
        }
        if (nav[1].Checked)
        {
            List<string> b = new List<string>();
            for (int i = 0; i < benchChk.Length; i++) if (benchChk[i].Checked) b.Add(benchKeys[i]);
            if (b.Count == 0) { MessageBox.Show(this, "Im Benchmark ist keine Messung ausgewählt.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information); ShowPage(1); return; }
            a.Append(" -BenchTests ").Append(String.Join(",", b.ToArray()));
            if (benchChk[3].Checked)
            {
                List<string> dn = new List<string>();
                for (int i = 0; i < clbDisks.Items.Count && i < diskNums.Count; i++) if (clbDisks.GetItemChecked(i)) dn.Add(diskNums[i]);
                if (dn.Count == 0) { MessageBox.Show(this, "Für den Laufwerks-Benchmark ist kein Laufwerk ausgewählt.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information); ShowPage(1); return; }
                a.Append(" -BenchLaufwerke ").Append(String.Join(",", dn.ToArray()));
            }
            if (cmbBenchDur.SelectedIndex == 1) a.Append(" -BenchmarkKurz");
            if (cmbRef.SelectedIndex == 1) a.Append(" -ReferenzDatei *median");
            else if (cmbRef.SelectedIndex > 1 && cmbRef.SelectedIndex - 2 < refItems.Count) a.Append(" -ReferenzDatei ").Append(Q(refItems[cmbRef.SelectedIndex - 2].Path));
            List<string> cmp = new List<string>();
            if (clbCompare.Enabled) for (int i = 0; i < clbCompare.Items.Count && i < cmpItems.Count; i++) if (clbCompare.GetItemChecked(i)) cmp.Add(cmpItems[i].Path);
            if (cmp.Count > 0) a.Append(" -VergleichDateien ").Append(Q(String.Join(";", cmp.ToArray())));
            if (!chkDbSave.Checked) a.Append(" -KeineDatenbank");
            if (chkRefSave.Checked) a.Append(" -ReferenzSpeichern");
        }
        if (nav[2].Checked)
        {
            if (!chkLCpu.Checked && !chkLRam.Checked && !chkLGpu.Checked && !chkLDisk.Checked) { MessageBox.Show(this, "Im Lasttest ist keine Komponente ausgewählt.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information); ShowPage(2); return; }
            if (chkLCpu.Checked) a.Append(" -LastCpuMinuten ").Append(Minutes(cmbLCpu));
            if (chkLRam.Checked) a.Append(" -LastRamMinuten ").Append(Minutes(cmbLRam)).Append(" -LastRamProzent ").Append(Convert.ToString(cmbLRamPct.SelectedItem).Split(' ')[0]);
            if (chkLGpu.Checked) a.Append(" -LastGpuMinuten ").Append(Minutes(cmbLGpu));
            if (chkLDisk.Checked) a.Append(" -LastDiskMinuten ").Append(Minutes(cmbLDisk)).Append(" -LastDiskLaufwerk ").Append(Convert.ToString(cmbLDiskDrive.SelectedItem).Substring(0, 1));
            a.Append(" -LastAbbruchCpu ").Append(AbortArg(cmbLAbortCpu)).Append(" -LastAbbruchGpu ").Append(AbortArg(cmbLAbortGpu));
        }
        if (nav[3].Checked)
        {
            List<string> r = new List<string>(); StringBuilder names = new StringBuilder();
            for (int i = 0; i < repChk.Length; i++) if (repChk[i].Checked) { r.Add(repKeys[i]); names.AppendLine("·  " + repText[i] + (repRisk[i].Length > 0 ? "  [" + ContractStep.RiskLabel(repRisk[i]) + "]" : "")); }
            if (r.Count == 0) { MessageBox.Show(this, "Im Reparaturmodul ist nichts ausgewählt.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information); ShowPage(3); return; }
            if (MessageBox.Show(this, "Folgende Reparaturen werden ausgeführt:\r\n\r\n" + names.ToString() + (chkRestorePoint.Checked ? "\r\nVorher wird ein Wiederherstellungspunkt angelegt." : "\r\nEs wird KEIN Wiederherstellungspunkt angelegt.") + "\r\n\r\nFortfahren?",
                "Reparatur bestätigen", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            a.Append(" -Reparaturen ").Append(String.Join(",", r.ToArray()));
            if (!chkRestorePoint.Checked) a.Append(" -OhneWiederherstellungspunkt");
        }
        if (drv) a.Append(" -SensorTreiber");
        Launch(a.ToString(), String.Join(" + ", mods.ToArray()));
    }

    // "automatisch ..." = auto, "aus" = aus, sonst die Zahl vor dem Gradzeichen
    static string AbortArg(ComboBox c)
    {
        string s = Convert.ToString(c.SelectedItem);
        if (s.StartsWith("automatisch")) return "auto";
        if (s == "aus") return "aus";
        return s.Split(' ')[0];
    }

    // ------------------------------------------------------------ Ablauf
    Panel BuildRun()
    {
        Panel p = new Panel(); p.BackColor = UI.Bg;
        TableLayoutPanel t = new TableLayoutPanel(); t.Dock = DockStyle.Fill; t.ColumnCount = 1; t.BackColor = UI.Bg;
        t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        t.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
        t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        t.RowStyles.Add(new RowStyle(SizeType.Absolute, 16));
        t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        t.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        t.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        TableLayoutPanel stepRow = new TableLayoutPanel(); stepRow.Dock = DockStyle.Fill; stepRow.AutoSize = true; stepRow.ColumnCount = 2; stepRow.BackColor = UI.Bg;
        stepRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); stepRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        lblStep = Lbl("Wird gestartet ...", 13f, true, UI.Text); lblStep.AutoEllipsis = true;
        lblCounter = Lbl("", 10f, false, UI.Muted); lblCounter.Anchor = AnchorStyles.Right; lblCounter.Margin = new Padding(3, 6, 0, 3);
        stepRow.Controls.Add(lblStep, 0, 0); stepRow.Controls.Add(lblCounter, 1, 0);
        t.Controls.Add(stepRow, 0, 0);
        barAll = new FlatBar(); barAll.Dock = DockStyle.Fill; barAll.Margin = new Padding(3, 4, 3, 6); t.Controls.Add(barAll, 0, 1);
        lblSub = Lbl(" ", 9.5f, false, UI.Muted); lblSub.AutoEllipsis = true; lblSub.Margin = new Padding(3, 4, 3, 2); t.Controls.Add(lblSub, 0, 2);
        barSub = new FlatBar(); barSub.Dock = DockStyle.Fill; barSub.Fill = Color.FromArgb(96, 140, 245); barSub.Margin = new Padding(3, 3, 3, 5); t.Controls.Add(barSub, 0, 3);

        FlowLayoutPanel cards = new FlowLayoutPanel(); cards.AutoSize = true; cards.BackColor = UI.Bg; cards.Margin = new Padding(0, 14, 0, 10);
        cardK = new StatCard("kritisch", UI.Crit); cardW = new StatCard("Warnungen", UI.Warn); cardI = new StatCard("Hinweise", UI.Info); cardT = new StatCard("Tests bestanden", UI.Ok);
        cards.Controls.Add(cardK); cards.Controls.Add(cardW); cards.Controls.Add(cardI); cards.Controls.Add(cardT);
        t.Controls.Add(cards, 0, 4);

        tabs = new TabStrip(); tabs.Dock = DockStyle.Fill; tabs.Items.Add("Befunde"); tabs.Items.Add("Tests"); tabs.Items.Add("Leistung"); tabs.Items.Add("Sensoren"); tabs.Items.Add("Protokoll");
        t.Controls.Add(tabs, 0, 5);

        Panel host = new Panel(); host.Dock = DockStyle.Fill; host.BackColor = UI.Panel; host.Padding = new Padding(1); host.Margin = new Padding(0, 0, 0, 10);
        lvFind = MakeList(new string[] { "Stufe", "Bereich", "Befund" }, new int[] { 110, 140, 700 });
        lvTests = MakeList(new string[] { "Ergebnis", "Test", "Details" }, new int[] { 110, 320, 520 });
        lvBench = MakeList(new string[] { "Ergebnis", "Messung", "Wert", "Index", "Referenz", "Vergleich" }, new int[] { 110, 330, 160, 190, 95, 220 });
        lvBench.Tag = "bench";
        txtLog = new TextBox(); txtLog.Multiline = true; txtLog.ReadOnly = true; txtLog.ScrollBars = ScrollBars.Vertical; txtLog.WordWrap = true;
        txtLog.Dock = DockStyle.Fill; txtLog.Font = new Font("Consolas", 9.75f); txtLog.BorderStyle = BorderStyle.None;
        txtLog.BackColor = Color.FromArgb(18, 24, 34); txtLog.ForeColor = Color.FromArgb(214, 222, 235);
        Panel sensHost = new Panel(); sensHost.Dock = DockStyle.Fill; sensHost.BackColor = UI.Panel; sensHost.Padding = new Padding(10, 6, 10, 6);
        chartRun = new SensorChart(); chartRun.Dock = DockStyle.Fill; chartRun.WindowSec = 0;
        chartRun.Empty = "Kurven erscheinen hier während des Lasttests (Temperatur, Takt, Leistung von CPU und GPU).";
        lblRunSens = Lbl(" ", 9f, false, UI.Muted); lblRunSens.Dock = DockStyle.Top; lblRunSens.AutoSize = false; lblRunSens.Height = 22;
        sensHost.Controls.Add(chartRun); sensHost.Controls.Add(lblRunSens);
        host.Controls.Add(lvFind); host.Controls.Add(lvTests); host.Controls.Add(lvBench); host.Controls.Add(sensHost); host.Controls.Add(txtLog);
        lvTests.Visible = false; lvBench.Visible = false; sensHost.Visible = false; txtLog.Visible = false;
        tabs.SelectedChanged += delegate {
            lvFind.Visible = tabs.Selected == 0; lvTests.Visible = tabs.Selected == 1; lvBench.Visible = tabs.Selected == 2; sensHost.Visible = tabs.Selected == 3; txtLog.Visible = tabs.Selected == 4;
            host.BackColor = tabs.Selected == 4 ? txtLog.BackColor : UI.Panel;
        };
        t.Controls.Add(host, 0, 6);

        TableLayoutPanel foot = new TableLayoutPanel(); foot.Dock = DockStyle.Fill; foot.AutoSize = true; foot.ColumnCount = 2; foot.BackColor = UI.Bg;
        foot.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); foot.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        lblResult = Lbl("", 11f, true, UI.Text); lblResult.Anchor = AnchorStyles.Left; lblResult.AutoEllipsis = true;
        FlowLayoutPanel btns = new FlowLayoutPanel(); btns.AutoSize = true; btns.WrapContents = false; btns.BackColor = UI.Bg;
        btnStopWait = UI.Secondary("Test beenden"); btnCancel = UI.Secondary("Abbrechen");
        btnFolder = UI.Secondary("Ordner öffnen"); btnNew = UI.Secondary("Neuer Lauf"); btnKi = UI.Secondary("KI-Datei zeigen"); btnCopy = UI.Secondary("KI-Kurzfassung kopieren"); btnHtml = UI.Primary("Bericht öffnen");
        btnHtml.Margin = new Padding(8, 0, 0, 0); btnHtml.Padding = new Padding(14, 3, 14, 3); btnHtml.Font = new Font("Segoe UI Semibold", 9.75f);
        btns.Controls.Add(btnStopWait); btns.Controls.Add(btnCancel); btns.Controls.Add(btnNew); btns.Controls.Add(btnFolder); btns.Controls.Add(btnKi); btns.Controls.Add(btnCopy); btns.Controls.Add(btnHtml);
        foot.Controls.Add(lblResult, 0, 0); foot.Controls.Add(btns, 1, 0);
        t.Controls.Add(foot, 0, 7);

        btnStopWait.Click += delegate {
            try { Directory.CreateDirectory(cpDir); File.WriteAllText(Path.Combine(cpDir, "stop.flag"), "1"); btnStopWait.Enabled = false; }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, "Leos Minibench"); }
        };
        btnCancel.Click += delegate { AskCancel(); };
        btnHtml.Click += delegate { OpenShell(htmlPath); };
        btnFolder.Click += delegate { OpenShell(outDir); };
        btnKi.Click += delegate { OpenSelect(kiPath); };
        // nur auf ausdrücklichen Klick in die Zwischenablage, damit nach dem Lauf nichts im Zwischenablageverlauf des PCs liegt
        btnCopy.Click += delegate {
            try { Clipboard.SetText(File.ReadAllText(kurzPath, Encoding.UTF8)); btnCopy.Text = "Kopiert"; }
            catch (Exception ex) { MessageBox.Show(this, "Kopieren fehlgeschlagen: " + ex.Message, "Leos Minibench"); }
        };
        btnNew.Click += delegate { ReloadDb(); runView.Visible = false; setupView.Visible = true; };
        p.Controls.Add(t);
        return p;
    }

    ListView MakeList(string[] cols, int[] widths)
    {
        ListView lv = new ListView(); lv.View = View.Details; lv.FullRowSelect = true; lv.Dock = DockStyle.Fill; lv.HideSelection = false;
        lv.HeaderStyle = ColumnHeaderStyle.Nonclickable; lv.ShowItemToolTips = true; lv.BorderStyle = BorderStyle.None; lv.OwnerDraw = true;
        lv.Font = new Font("Segoe UI", 9.75f); lv.BackColor = UI.Panel; lv.ForeColor = UI.Text;
        ImageList rowHeight = new ImageList(); rowHeight.ImageSize = new Size(1, 32); lv.SmallImageList = rowHeight;
        for (int i = 0; i < cols.Length; i++) lv.Columns.Add(cols[i], widths[i]);
        lv.DrawColumnHeader += delegate(object s, DrawListViewColumnHeaderEventArgs e) {
            using (SolidBrush b = new SolidBrush(Color.FromArgb(248, 249, 251))) e.Graphics.FillRectangle(b, e.Bounds);
            using (Pen pen = new Pen(UI.Line)) e.Graphics.DrawLine(pen, e.Bounds.Left, e.Bounds.Bottom - 1, e.Bounds.Right, e.Bounds.Bottom - 1);
            using (Font f = new Font("Segoe UI Semibold", 8.5f))
                TextRenderer.DrawText(e.Graphics, e.Header.Text.ToUpperInvariant(), f, new Rectangle(e.Bounds.X + 10, e.Bounds.Y, e.Bounds.Width - 12, e.Bounds.Height), UI.Muted, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        };
        lv.DrawItem += delegate(object s, DrawListViewItemEventArgs e) { };
        lv.DrawSubItem += delegate(object s, DrawListViewSubItemEventArgs e) {
            Graphics g = e.Graphics;
            bool hdr = "hdr".Equals(e.Item.Tag);
            if (hdr && (e.ColumnIndex == 2 || e.ColumnIndex == 3)) return;
            Rectangle rb = e.Bounds;
            if (hdr && e.ColumnIndex == 1) { for (int ci = 2; ci <= 3 && ci < lv.Columns.Count; ci++) rb.Width += lv.Columns[ci].Width; }
            Color back = e.Item.Selected ? UI.AccentSoft : (hdr ? Color.FromArgb(243, 245, 249) : UI.Panel);
            using (SolidBrush b = new SolidBrush(back)) g.FillRectangle(b, rb);
            using (Pen pen = new Pen(Color.FromArgb(236, 239, 243))) g.DrawLine(pen, rb.Left, rb.Bottom - 1, rb.Right, rb.Bottom - 1);
            string txt = e.SubItem.Text;
            if (hdr && e.ColumnIndex == 1)
            {
                int w = rb.Width;
                using (Font fb = new Font("Segoe UI Semibold", 10f))
                {
                    Size sz = TextRenderer.MeasureText(g, txt, fb);
                    TextRenderer.DrawText(g, txt, fb, new Rectangle(e.Bounds.X + 10, e.Bounds.Y, sz.Width + 4, e.Bounds.Height), UI.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                    string sub = e.Item.SubItems.Count > 2 ? e.Item.SubItems[2].Text : "";
                    if (sub.Length > 0)
                        TextRenderer.DrawText(g, sub, lv.Font, new Rectangle(e.Bounds.X + 18 + sz.Width, e.Bounds.Y, w - sz.Width - 26, e.Bounds.Height), UI.Muted,
                            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
                }
            }
            else if (hdr && e.ColumnIndex == 4 && txt.Length > 0)
            {
                using (Font fb = new Font("Segoe UI Semibold", 9.75f))
                    TextRenderer.DrawText(g, txt, fb, new Rectangle(e.Bounds.X + 10, e.Bounds.Y, e.Bounds.Width - 14, e.Bounds.Height), UI.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            }
            else if (e.ColumnIndex == 0 && txt.Length == 0) { }
            else if (e.ColumnIndex == 0)
            {
                Color fg, bg; UI.Level(txt, out fg, out bg);
                using (Font f = new Font("Segoe UI Semibold", 8.25f))
                {
                    Size sz = TextRenderer.MeasureText(g, txt.ToUpperInvariant(), f);
                    RectangleF pill = new RectangleF(e.Bounds.X + 8, e.Bounds.Y + (e.Bounds.Height - 20) / 2f, sz.Width + 12, 20);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    using (GraphicsPath gp = UI.Round(pill, 10)) using (SolidBrush pb = new SolidBrush(bg)) g.FillPath(pb, gp);
                    g.SmoothingMode = SmoothingMode.None;
                    TextRenderer.DrawText(g, txt.ToUpperInvariant(), f, Rectangle.Round(pill), fg, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                }
            }
            else if ("bench".Equals(lv.Tag) && e.ColumnIndex == 3)
            {
                int iv; double wv;
                if (txt.StartsWith("W") && double.TryParse(txt.Substring(1), NumberStyles.Float, CultureInfo.InvariantCulture, out wv))
                {
                    // WinSAT: Skala 1,0 bis 9,9, Farbe nach Bewertung
                    Color fc = wv >= 7 ? UI.Ok : wv >= 5 ? UI.Info : wv >= 3.5 ? UI.Warn : UI.Crit;
                    int bw = Math.Max(40, e.Bounds.Width - 60);
                    RectangleF tr = new RectangleF(e.Bounds.X + 10, e.Bounds.Y + e.Bounds.Height / 2f - 5, bw, 10);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    using (GraphicsPath gp = UI.Round(tr, 5)) using (SolidBrush b0 = new SolidBrush(UI.SkipBg)) g.FillPath(b0, gp);
                    float fw = Math.Max(6f, (float)(bw * (Math.Min(9.9, Math.Max(1.0, wv)) - 1.0) / 8.9));
                    using (GraphicsPath gf = UI.Round(new RectangleF(tr.X, tr.Y, fw, tr.Height), 5)) using (SolidBrush b1 = new SolidBrush(fc)) g.FillPath(b1, gf);
                    g.SmoothingMode = SmoothingMode.None;
                    TextRenderer.DrawText(g, wv.ToString("0.0", CultureInfo.GetCultureInfo("de-DE")), (wsBold ?? (wsBold = new Font(lv.Font, FontStyle.Bold))), new Rectangle((int)tr.Right + 6, e.Bounds.Y, 44, e.Bounds.Height), UI.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
                }
                else if (int.TryParse(txt, out iv))
                {
                    Color fg, bg; UI.Level(e.Item.SubItems[0].Text, out fg, out bg);
                    int bw = Math.Max(40, e.Bounds.Width - 60);
                    RectangleF tr = new RectangleF(e.Bounds.X + 10, e.Bounds.Y + e.Bounds.Height / 2f - 4, bw, 8);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    using (GraphicsPath gp = UI.Round(tr, 4)) using (SolidBrush b0 = new SolidBrush(UI.SkipBg)) g.FillPath(b0, gp);
                    float fw = Math.Max(4f, bw * Math.Min(150, Math.Max(0, iv)) / 150f);
                    using (GraphicsPath gf = UI.Round(new RectangleF(tr.X, tr.Y, fw, tr.Height), 4)) using (SolidBrush b1 = new SolidBrush(fg)) g.FillPath(b1, gf);
                    using (Pen pm = new Pen(UI.Muted, 2f)) g.DrawLine(pm, tr.X + bw * 100f / 150f, tr.Y - 3, tr.X + bw * 100f / 150f, tr.Bottom + 3);
                    g.SmoothingMode = SmoothingMode.None;
                    TextRenderer.DrawText(g, txt, lv.Font, new Rectangle((int)tr.Right + 6, e.Bounds.Y, 44, e.Bounds.Height), UI.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
                }
                else if (txt.Length > 0)
                    TextRenderer.DrawText(g, txt, lv.Font, new Rectangle(e.Bounds.X + 10, e.Bounds.Y, e.Bounds.Width - 14, e.Bounds.Height), UI.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            }
            else
            {
                TextRenderer.DrawText(g, txt, lv.Font, new Rectangle(e.Bounds.X + 10, e.Bounds.Y, e.Bounds.Width - 14, e.Bounds.Height), UI.Text,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            }
        };
        lv.Resize += delegate {
            int w = lv.ClientSize.Width; for (int i = 0; i < lv.Columns.Count - 1; i++) w -= lv.Columns[i].Width;
            if (w > 150) lv.Columns[lv.Columns.Count - 1].Width = w - 2;
        };
        lv.DoubleClick += delegate {
            if (lv.SelectedItems.Count == 0) return;
            ListViewItem it = lv.SelectedItems[0];
            StringBuilder mb = new StringBuilder();
            for (int i = 0; i < it.SubItems.Count; i++) if (it.SubItems[i].Text.Length > 0) mb.AppendLine(lv.Columns[i].Text + ":  " + it.SubItems[i].Text);
            if (!String.IsNullOrEmpty(it.ToolTipText)) { mb.AppendLine(); mb.AppendLine(it.ToolTipText); }
            MessageBox.Show(this, mb.ToString(), "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information);
        };
        return lv;
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        BringToFront2();
        BeginInvoke(new MethodInvoker(BringToFront2));
    }

    void BringToFront2()
    {
        try
        {
            if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
            ShowWindow(Handle, 9);
            IntPtr fg = GetForegroundWindow();
            uint fgT = GetWindowThreadProcessId(fg, IntPtr.Zero); uint me = GetCurrentThreadId();
            bool att = fgT != 0 && fgT != me && AttachThreadInput(me, fgT, true);
            BringWindowToTop(Handle); SetForegroundWindow(Handle);
            if (att) AttachThreadInput(me, fgT, false);
            TopMost = true; TopMost = false; Activate();
        }
        catch { }
    }

    static Encoding OemEncoding()
    {
        try { return Encoding.GetEncoding(CultureInfo.CurrentCulture.TextInfo.OEMCodePage); } catch { return Encoding.Default; }
    }

    void Launch(string args, string title)
    {
        ProcessStartInfo psi = new ProcessStartInfo(psExe, args);
        psi.UseShellExecute = false; psi.CreateNoWindow = true;
        psi.RedirectStandardOutput = true; psi.RedirectStandardError = true; psi.RedirectStandardInput = true;
        psi.StandardOutputEncoding = new UTF8Encoding(false);
        psi.StandardErrorEncoding = OemEncoding();
        proc = new Process(); proc.StartInfo = psi; proc.EnableRaisingEvents = true;
        proc.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) queue.Enqueue(e.Data); else outEof = true; };
        proc.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null && e.Data.Trim().Length > 0) queue.Enqueue("@@LOG|Red|" + e.Data); };
        proc.Exited += delegate { exited = true; };

        lvFind.Items.Clear(); lvTests.Items.Clear(); lvBench.Items.Clear(); txtLog.Clear();
        cntK = 0; cntW = 0; cntI = 0; testsOk = 0; benchWarn = 0; benchCount = 0; benchHeads.Clear(); outEof = false; exitSeen = DateTime.MinValue; cardK.Count = 0; cardW.Count = 0; cardI.Count = 0; cardT.Count = 0;
        exited = false; done = false; gotDone = false; cancelled = false; htmlPath = ""; outDir = ""; kiPath = ""; kurzPath = "";
        lblResult.Text = ""; lblStep.ForeColor = UI.Text; lblStep.Text = "Wird gestartet ..."; lblCounter.Text = title;
        barAll.Value = 0; barAll.Marquee = false; barSub.Value = 0; barSub.Marquee = true; barAll.Fill = UI.Accent;
        tabs.SetText(0, "Befunde"); tabs.SetText(1, "Tests"); tabs.SetText(2, "Leistung"); tabs.SetText(3, "Sensoren"); tabs.Selected = 0;
        chartRun.Clear(); lblRunSens.Text = " ";
        try
        {
            proc.Start();
            proc.BeginOutputReadLine(); proc.BeginErrorReadLine();
            try { proc.StandardInput.Close(); } catch { }
        }
        catch (Exception ex) { MessageBox.Show(this, "PowerShell konnte nicht gestartet werden: " + ex.Message, "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Error); return; }
        running = true;
        setupView.Visible = false; runView.Visible = true;
        btnCancel.Visible = true; btnCancel.Enabled = true;
        btnStopWait.Visible = false; btnStopWait.Enabled = true;
        btnHtml.Visible = false; btnFolder.Visible = false; btnNew.Visible = false; btnKi.Visible = false; btnCopy.Visible = false; btnCopy.Text = "KI-Kurzfassung kopieren";
        timer.Start();
    }

    static string Get(string[] p, int i) { return (i < p.Length) ? p[i] : ""; }
    static int ToInt(string[] p, int i) { int v; return int.TryParse(Get(p, i), NumberStyles.Integer, CultureInfo.InvariantCulture, out v) ? v : 0; }

    void OnTick()
    {
        string line; int n = 0;
        StringBuilder log = new StringBuilder();
        lvFind.BeginUpdate(); lvTests.BeginUpdate();
        try { while (n < 800 && queue.TryDequeue(out line)) { n++; HandleLine(line, log); } }
        finally { lvFind.EndUpdate(); lvTests.EndUpdate(); }
        if (log.Length > 0)
        {
            if (txtLog.TextLength > 1500000) txtLog.Text = txtLog.Text.Substring(txtLog.TextLength - 500000);
            txtLog.AppendText(log.ToString());
        }
        if (exited && exitSeen == DateTime.MinValue) exitSeen = DateTime.Now;
        bool eof = outEof;
        if (exited && !done && (eof || (DateTime.Now - exitSeen).TotalSeconds > 5) && queue.IsEmpty) Finish();
    }

    void HandleLine(string line, StringBuilder log)
    {
        if (!line.StartsWith("@@")) { log.AppendLine(line); return; }
        string[] p = line.Substring(2).Split('|');
        switch (p[0])
        {
            case "STEP":
                int s = ToInt(p, 1), t = ToInt(p, 2);
                lblStep.Text = Get(p, 3);
                lblCounter.Text = String.Format("Schritt {0} von {1}", s, t);
                if (t > 0) barAll.Value = (s - 1) * 100 / t;
                log.AppendLine(); log.AppendLine(">> " + Get(p, 3));
                break;
            case "SUB":
                int pc = ToInt(p, 1);
                if (pc == -9) { lblSub.Text = " "; barSub.Marquee = false; barSub.Value = 0; }
                else
                {
                    string st = Get(p, 3).Trim();
                    lblSub.Text = Get(p, 2).Trim() + (st.Length > 0 ? "   ·   " + st : "");
                    if (pc < 0) barSub.Marquee = true; else { barSub.Marquee = false; barSub.Value = pc; }
                }
                break;
            case "FIND": AddFinding(Get(p, 1), Get(p, 2), Get(p, 3)); break;
            case "TEST": AddTest(Get(p, 1), Get(p, 2), Get(p, 3)); break;
            case "LOG": log.AppendLine(p.Length > 2 ? String.Join("|", p, 2, p.Length - 2) : ""); break;
            case "BENCH": AddBench(p); break;
            case "BGRP": UpdateBenchGroup(p); break;
            case "STOP": btnStopWait.Visible = Get(p, 1) == "1"; btnStopWait.Enabled = true; break;
            case "SENSLIM": chartRun.SetLimits(p); break;
            case "SENSLEAD":
                {
                    bool firstLead = chartRun.Count == 0;
                    double[] r = chartRun.Add(p);
                    List<string> parts = new List<string>();
                    if (!double.IsNaN(r[1])) parts.Add("CPU " + SensorChart.Fmt(r[1], "°C"));
                    if (!double.IsNaN(r[3])) parts.Add(SensorChart.Fmt(r[3], "W"));
                    if (!double.IsNaN(r[2])) parts.Add(SensorChart.Fmt(r[2], "MHz"));
                    if (!double.IsNaN(r[4])) parts.Add("GPU " + SensorChart.Fmt(r[4], "°C"));
                    if (!double.IsNaN(r[7])) parts.Add("Lüfter " + SensorChart.Fmt(r[7], "U/min"));
                    lblRunSens.Text = parts.Count > 0 ? "Aktuell: " + String.Join("   ·   ", parts.ToArray()) : "Aktuell: keine Sensorwerte";
                    if (firstLead) tabs.SetText(3, "Sensoren (live)");
                    break;
                }
            case "DONE":
                htmlPath = Get(p, 2); outDir = Get(p, 3); nK = ToInt(p, 4); nW = ToInt(p, 5); nI = ToInt(p, 6); kurzPath = Get(p, 7); kiPath = Get(p, 8); gotDone = true;
                break;
            default: log.AppendLine(line); break;
        }
    }

    void AddFinding(string level, string area, string text)
    {
        ListViewItem it = new ListViewItem(new string[] { level, area, text });
        it.ToolTipText = text;
        int pos = lvFind.Items.Count;
        if (level == "KRITISCH") { pos = cntK; cntK++; cardK.Count = cntK; }
        else if (level == "WARNUNG") { pos = cntK + cntW; cntW++; cardW.Count = cntW; }
        else { cntI++; cardI.Count = cntI; }
        lvFind.Items.Insert(pos, it);
        tabs.SetText(0, String.Format("Befunde ({0})", lvFind.Items.Count));
    }

    static string GroupName(string g)
    {
        if (g == "CPU") return "Prozessor"; if (g == "RAM") return "Arbeitsspeicher"; if (g == "GPU") return "Grafik";
        if (g == "Vergleich") return "Vergleich mit anderen Systemen"; if (g == "WinSAT") return "WinSAT"; return g;
    }

    ListViewItem BenchHead(string g)
    {
        ListViewItem h;
        if (benchHeads.TryGetValue(g, out h)) return h;
        h = new ListViewItem(new string[] { "", GroupName(g), "", "", "", "" }); h.Tag = "hdr";
        benchHeads[g] = h; lvBench.Items.Add(h);
        return h;
    }

    void AddBench(string[] p)
    {
        // BENCH|Status|Komponente|Messung|Anzeige|Index|Vergleich|Hinweis|Referenz|Gruppe
        string g = Get(p, 9); if (g.Length == 0) g = Get(p, 2) == "Datenträger" ? "Laufwerke" : Get(p, 2);
        ListViewItem h = BenchHead(g);
        ListViewItem it = new ListViewItem(new string[] { Get(p, 1), Get(p, 3), Get(p, 4), Get(p, 5), Get(p, 8), Get(p, 6) });
        it.ToolTipText = Get(p, 7);
        int pos = h.Index + 1;
        while (pos < lvBench.Items.Count && !"hdr".Equals(lvBench.Items[pos].Tag)) pos++;
        lvBench.Items.Insert(pos, it);
        if (g != "Vergleich")
        {
            benchCount++;
            if (Get(p, 1).Equals("Warnung", StringComparison.OrdinalIgnoreCase)) benchWarn++;
        }
        tabs.SetText(2, benchWarn > 0 ? String.Format("Leistung ({0} auffällig)", benchWarn) : String.Format("Leistung ({0})", benchCount));
    }

    void UpdateBenchGroup(string[] p)
    {
        ListViewItem h = BenchHead(Get(p, 1));
        h.SubItems[0].Text = Get(p, 3);
        h.SubItems[1].Text = Get(p, 2);
        h.SubItems[2].Text = Get(p, 4);
        h.SubItems[4].Text = Get(p, 5);
        h.ToolTipText = Get(p, 4);
        lvBench.Invalidate();
    }

    void AddTest(string name, string status, string detail)
    {
        ListViewItem it = new ListViewItem(new string[] { status, name, detail });
        it.ToolTipText = detail;
        lvTests.Items.Add(it);
        if (status.Equals("OK", StringComparison.OrdinalIgnoreCase) || status.Equals("Repariert", StringComparison.OrdinalIgnoreCase)) { testsOk++; cardT.Count = testsOk; }
        tabs.SetText(1, String.Format("Tests ({0})", lvTests.Items.Count));
    }

    void Finish()
    {
        done = true; running = false; timer.Stop();
        barSub.Marquee = false; barSub.Value = 0; lblSub.Text = " ";
        btnCancel.Visible = false; btnStopWait.Visible = false; btnNew.Visible = true;
        if (chartRun.Count > 0) tabs.SetText(3, "Sensoren");
        int code = -1; try { code = proc.ExitCode; } catch { }
        if (gotDone)
        {
            barAll.Value = 100; barAll.Fill = nK > 0 ? UI.Crit : (nW > 0 ? Color.FromArgb(214, 140, 20) : UI.Ok); barAll.Invalidate();
            lblStep.Text = "Abgeschlossen";
            lblCounter.Text = "Bericht und KI-Dateien liegen im Datenordner";
            lblResult.Text = nK > 0 ? "Kritische Befunde gefunden" : (nW > 0 ? "Warnungen vorhanden" : "Keine Auffälligkeiten");
            lblResult.ForeColor = nK > 0 ? UI.Crit : (nW > 0 ? UI.Warn : UI.Ok);
            btnHtml.Visible = File.Exists(htmlPath); btnFolder.Visible = Directory.Exists(outDir); btnKi.Visible = File.Exists(kiPath); btnCopy.Visible = File.Exists(kurzPath);
            if (btnHtml.Visible) OpenShell(htmlPath);
        }
        else
        {
            lblStep.Text = cancelled ? "Abgebrochen" : "Ohne Bericht beendet (Code " + code + ")";
            lblStep.ForeColor = UI.Crit; lblCounter.Text = "";
            CleanupDriver();
            if (!cancelled) tabs.Selected = 4;
        }
        try { if (!ContainsFocus) FlashWindow(Handle, true); } catch { }
    }

    void AskCancel()
    {
        if (!running) return;
        if (MessageBox.Show(this, "Lauf wirklich abbrechen?", "Leos Minibench", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        cancelled = true;
        KillTree();
    }

    void KillTree()
    {
        try
        {
            if (proc != null && !proc.HasExited)
            {
                ProcessStartInfo k = new ProcessStartInfo("taskkill.exe", "/T /F /PID " + proc.Id);
                k.CreateNoWindow = true; k.UseShellExecute = false;
                Process kp = Process.Start(k); kp.WaitForExit(8000);
            }
        }
        catch { }
    }

    void OnClosing(object sender, FormClosingEventArgs e)
    {
        // Live-Ansicht sauber beenden, damit ein vorübergehend installierter Treiber entfernt wird
        if (liveRunning) StopLiveAndWait();
        if (!running) return;
        if (MessageBox.Show(this, "Der Lauf ist noch aktiv. Abbrechen und schließen?", "Leos Minibench", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) { e.Cancel = true; return; }
        cancelled = true; KillTree();
        try { if (proc != null) proc.WaitForExit(10000); } catch { }
        CleanupDriver();
    }

    static void OpenShell(string path)
    {
        if (String.IsNullOrEmpty(path)) return;
        try { Process.Start("explorer.exe", "\"" + path + "\""); } catch { }
    }

    static void OpenSelect(string path)
    {
        if (String.IsNullOrEmpty(path)) return;
        try { Process.Start("explorer.exe", "/select,\"" + path + "\""); } catch { }
    }
}
'@
    # Datenträger für die Auswahl im Benchmark und im Lasttest: Nummer|Name|Bus|Medium|Größe|Buchstaben|USB
    $diskList = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($pd in @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object { [int]$_.DeviceId })) {
            $num = [int]$pd.DeviceId
            $letters = @(Get-Partition -DiskNumber $num -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object { '{0}:' -f $_.DriveLetter } | Sort-Object) -join ', '
            $sz = [double]$pd.Size
            $szT = $(if ($sz -ge 1e12) { '{0:N1} TB' -f ($sz / 1e12) } elseif ($sz -ge 1e9) { '{0:N0} GB' -f ($sz / 1e9) } else { '{0:N0} MB' -f ($sz / 1e6) })
            $diskList.Add(('{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $num, (([string]$pd.FriendlyName).Trim() -replace '\|', '/'), $pd.BusType, $pd.MediaType, $szT, $letters, $(if ([string]$pd.BusType -eq 'USB') { '1' } else { '0' })))
        }
    } catch { }
    try {
        if (-not ('DiagGui' -as [type])) {
            Add-Type -AssemblyName System.Web.Extensions
            $refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
            Add-CachedType 'LeosMinibench-Oberflaeche' $guiCode $refs
        }
        if ($script:DataDirFallback) { [void][Windows.Forms.MessageBox]::Show(('Der Ordner neben dem Programm ist nicht beschreibbar (USB-Stick schreibgeschützt?). Ersatzweise wird verwendet:' + "`r`n" + $script:DataDir), 'Leos Minibench', 'OK', 'Warning') }
        elseif (-not $script:DataDir) { [void][Windows.Forms.MessageBox]::Show('Es wurde kein beschreibbarer Ordner für Berichte gefunden.', 'Leos Minibench', 'OK', 'Error'); exit 1 }
        New-Item -ItemType Directory -Path $script:CpDir -Force | Out-Null
        [DiagGui]::Run((Get-Process -Id $PID).Path, $PSCommandPath, $script:CpDir, $script:DataDir, $ScriptVersion, $diskList.ToArray(), [string[]](Get-ContractGuiLines))
        exit 0
    } catch {
        [void][Windows.Forms.MessageBox]::Show(('Die Oberfläche konnte nicht gestartet werden:' + "`r`n`r`n" + $_.Exception.Message), 'Leos Minibench', 'OK', 'Error')
        exit 1
    }
}
#endregion


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
$ModRep   = $modList -contains 'reparatur'
# Modul Sensoren = Live-Ansicht (Sondermodus ohne Bericht)
if ($modList -contains 'sensoren') { $SensorLive = $true }
if ($AnalyzeLastRun) { $ModDiag = $true; $ModBench = $false; $ModLast = $false; $ModRep = $false }

# Diagnose: Profil und Prüfungen
$profKey  = ([string]$DiagProfil).ToLowerInvariant()
$Kurztest = $profKey -like 'funktion*'
$Quick    = $Kurztest -or $profKey -like 'schnell*'
$script:DiagKeys = @((Get-ModuleContract 'Diagnose').Schritte | Where-Object { $_.Typ -eq 'Pruefung' } | ForEach-Object { $_.Key })
$optSel = $(if ($DiagOptionen) { @(Split-List $DiagOptionen) }
            elseif ($Kurztest) { @('Ereignisse', 'Netzwerk', 'RamTest', 'CpuTest') }
            elseif ($Quick)    { @('Ereignisse', 'Updatesuche', 'Netzwerk', 'RamTest', 'CpuTest') }
            else               { $script:DiagKeys })
$script:Opt = @{}
foreach ($k in $script:DiagKeys) { $script:Opt[$k] = [bool]($ModDiag -and -not $AnalyzeLastRun -and ($optSel -contains $k)) }
if ($AnalyzeLastRun) { $script:Opt['Ereignisse'] = $true }
if ($Quick) {
    if (-not $PSBoundParameters.ContainsKey('RamTestPercent'))   { $RamTestPercent   = 25 }
    if (-not $PSBoundParameters.ContainsKey('RamTestPasses'))    { $RamTestPasses    = 1 }
    if (-not $PSBoundParameters.ContainsKey('CpuStressSeconds')) { $CpuStressSeconds = 30 }
}
if ($Kurztest) {
    if (-not $PSBoundParameters.ContainsKey('RamTestPercent'))   { $RamTestPercent   = 5 }
    if (-not $PSBoundParameters.ContainsKey('CpuStressSeconds')) { $CpuStressSeconds = 10 }
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

# Reparatur: Auswahl in fester, sinnvoller Reihenfolge (Reihenfolge, Titel und Risikostufe aus dem Modulvertrag)
$script:RepOrder  = @((Get-ModuleContract 'Reparatur').Schritte | ForEach-Object { $_.Key })
$script:RepTitles = [ordered]@{}
$script:RepRisk   = @{}
foreach ($s in (Get-ModuleContract 'Reparatur').Schritte) { $script:RepTitles[$s.Key] = $s.Titel; $script:RepRisk[$s.Key] = $s.Risiko }
$repList = @(Split-List $Reparaturen)
$script:RepSel = @($script:RepOrder | Where-Object { $repList -contains $_ })
if ($ModRep -and -not $script:RepSel.Count) { $ModRep = $false }

# Höchste Risikostufe dieses Laufs (steht im Bericht); Benchmark und Lasttest verändern nichts, der PawnIO-Treiber ist ein Eingriff
function Get-RunRisk {
    $lv = @('Lesen')
    if ($ModDiag -and -not $AnalyzeLastRun) {
        if ($ScheduleWindowsMemTest) { $lv += (Get-ModuleStep 'Diagnose' 'Speicherdiagnose').Risiko }
        if ($InstallSmartmontools -and -not $Kurztest) { $lv += (Get-ModuleStep 'Diagnose' 'SmartmontoolsHolen').Risiko }
    }
    if ($ModRep) { $lv += @($script:RepSel | ForEach-Object { $script:RepRisk[$_] }) }
    # PawnIO zählt nur, wenn der Treiber in diesem Lauf tatsächlich installiert wurde
    if ($script:PawnIoInstalledRun) { $lv += (Get-ModuleStep 'Sensoren' 'Treiber').Risiko }
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
    }
}
function Test-StepEnabled([string]$Key) {
    $p = $Key -split ':', 2
    switch ($p[0]) {
        'Opt'   { return [bool]$script:Opt[$p[1]] }
        'Bench' { return [bool]$script:BenchSel[$p[1]] }
        'Last'  { return [bool](@($script:LastPlan.Values | Where-Object { $_ -gt 0 }).Count) }
        'Rep'   { return ($script:RepSel -contains $p[1]) }
    }
    return $false
}

if (-not $ImportOrdner -and -not $Vergleich -and -not $Rueckgaengig -and -not $SensorLive -and -not $SensorWerkzeugeHolen -and -not $SensorAufraeumen) {
    # Berichte landen ausschließlich im Datenordner neben dem Programm (z. B. auf dem USB-Stick)
    if (-not $OutputDir) {
        $base = $(if ($script:DataDir) { Join-Path $script:DataDir 'Berichte' } else { Join-Path $env:TEMP 'LeosMinibench-Berichte' })
        $OutputDir = Join-Path $base ('{0}_{1}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmm'))
        if (Test-Path -LiteralPath $OutputDir) { $OutputDir += (Get-Date -Format '_ss') }
    }
    New-Item -ItemType Directory -Path $OutputDir -Force -ErrorAction Stop | Out-Null
    $RawDir = Join-Path $OutputDir 'Anhang'
    New-Item -ItemType Directory -Path $RawDir -Force | Out-Null
    try { $script:GuiLog = New-Object IO.StreamWriter((Join-Path $RawDir 'Konsole.log'), $false, (New-Object Text.UTF8Encoding($true))); $script:GuiLog.AutoFlush = $true } catch { }
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
$script:LoadSummary   = ''
$script:LoadParts     = [System.Collections.Generic.List[object]]::new()
$script:LoadThrottle  = $null
$script:LoadAbort     = $null
$script:LoadLimits    = $null
$script:PawnIoInstalledRun = $false
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
    return ($p -join ' + ')
}

$script:StepNo = 0
function Get-PlannedSteps {
    if ($AnalyzeLastRun) { return 3 }
    $n = 0
    if ($ModDiag) {
        $n += 16
        foreach ($k in 'Integritaet', 'Netzwerk', 'RamTest', 'CpuTest') { if ($script:Opt[$k]) { $n++ } }
        if ($script:Opt['Defender'] -and $script:DefenderActive -ne $false) { $n++ }
        $smartPossible = $script:Smartctl -and ($null -eq $script:SmartDevices -or @($script:SmartDevices).Count -gt 0)
        if ($script:Opt['SmartLang'] -and $smartPossible) { $n += 2 }
        if ($script:Opt['Ereignisse']) { $n += 2 }
    }
    if (($ModBench -or $ModLast) -and -not $ModDiag) { $n++ }
    if ($ModBench) { $n += @($script:BenchSel.Keys | Where-Object { $script:BenchSel[$_] }).Count + 1 }
    if ($ModLast) { $n++ }
    if ($ModRep) { $n += $script:RepSel.Count; if (-not $OhneWiederherstellungspunkt) { $n++ } }
    return $n + 2
}

function Show-Overall([string]$Status) {
    $total = [math]::Max((Get-PlannedSteps), $script:StepNo)
    Send-GuiEvent 'STEP' $script:StepNo $total $Status
}

function Show-Sub([string]$Activity, [string]$Status = ' ', [int]$Percent = -1) {
    if (-not $Status) { $Status = ' ' }
    Write-Heartbeat ('{0} | {1}' -f $Activity, $Status.Trim())
    Send-GuiEvent 'SUB' $Percent $Activity $Status
}

function Hide-Sub { Send-GuiEvent 'SUB' '-9' '' '' }

function Wait-JobWithProgress($Job, [string]$Activity, [int]$ExpectedSec = 0, [int]$TimeoutSec = 3600) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($Job.State -in 'NotStarted', 'Running') {
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

function Get-CpuSample {
    $all  = @(Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction SilentlyContinue)
    $pi   = $all | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
    $core = @($all | Where-Object { $_.Name -notmatch '_Total' })
    $maxPerf = 0
    if ($core.Count) { $maxPerf = [int](($core | Measure-Object PercentProcessorPerformance -Maximum).Maximum) }
    $tz = @(Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue)
    $temp = $null
    if ($tz.Count) {
        $vals = $tz | ForEach-Object { if ($_.HighPrecisionTemperature) { $_.HighPrecisionTemperature / 10 - 273.15 } elseif ($_.Temperature) { $_.Temperature - 273.15 } } | Where-Object { $_ -gt 0 -and $_ -lt 130 }
        if ($vals) { $temp = [math]::Round(($vals | Measure-Object -Maximum).Maximum, 1) }
    }
    $freq = 0; if ($pi) { $freq = [double]$pi.ProcessorFrequency }
    [pscustomobject]@{
        Last = [int]$pi.PercentProcessorTime; Leistung = [int]$pi.PercentProcessorPerformance; MaxLeistung = $maxPerf
        MaxFreq = [int]$pi.PercentofMaximumFrequency; MHz = [int]($freq * [int]$pi.PercentProcessorPerformance / 100)
        MaxMHz = [int]($freq * $maxPerf / 100); Temp = $temp
    }
}

function Wait-TaskProgress($Task, [string]$Activity, [string]$Status, [int]$ExpectedMs, [switch]$Sample) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $samples = New-Object System.Collections.ArrayList
    while (-not $Task.IsCompleted) {
        Show-Sub $Activity $Status ([int][math]::Min(99.0, [double]$sw.ElapsedMilliseconds * 100.0 / [math]::Max(1.0, [double]$ExpectedMs)))
        if ($Sample -and $sw.ElapsedMilliseconds -gt 800) { [void]$samples.Add((Get-CpuSample)) }
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
                    Add-Finding WARNUNG 'Leistung' ('{0} {1}: {2:N0} % schlechter als bei früheren Läufen auf diesem PC ({3} statt Median {4:N1} {5}).' -f $Komponente, $Messung, [math]::Abs($d), $Anzeige, $med, $Einheit)
                    if ($Status -eq 'OK' -or $Status -eq 'Info') { $Status = 'Warnung' }
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


# ---------- Referenzwerte (Baseline) ----------
# Standard: Messwerte des Hauptsystems TORRENT vom 30.09.2026 (Benchmark v1.8, volle Messdauer).
# Laufwerke werden nach Klasse verglichen. Andere Referenzen: Vergleichsdatenbank, -ReferenzDatei, -ReferenzSpeichern.
$script:RefDefault = @{
    Name = 'TORRENT (Ryzen 5 7600X, 32 GB DDR5-6000, Radeon RX 6800)'; Datum = '2026-09-30'; Quelle = 'eingebaut'
    Werte = @{
        'CPU|ST' = 3086; 'CPU|MT' = 38101; 'CPU|AES' = 1432; 'CPU|SHA' = 2568; 'CPU|DEFL' = 295
        'RAM|Lesen' = 61.9; 'RAM|Schreiben' = 31.2; 'RAM|Kopieren' = 37.6; 'RAM|Latenz' = 82.4
        'GPU|VMB' = 290.2; 'GPU|DWM' = 17094
        'DISK|SATA-SSD|SR' = 554; 'DISK|SATA-SSD|SW' = 520; 'DISK|SATA-SSD|R1' = 10880; 'DISK|SATA-SSD|R8' = 73720; 'DISK|SATA-SSD|W1' = 29938
        'DISK|NVMe4|SR' = 6684; 'DISK|NVMe4|SW' = 3739; 'DISK|NVMe4|R1' = 18330; 'DISK|NVMe4|R8' = 159397; 'DISK|NVMe4|W1' = 54971
        'DISK|NVMe3|SR' = 3120; 'DISK|NVMe3|SW' = 3028; 'DISK|NVMe3|R1' = 14312; 'DISK|NVMe3|R8' = 114676; 'DISK|NVMe3|W1' = 62292
    }
}
$script:Ref = $script:RefDefault
$script:BenchDisks = [System.Collections.Generic.List[object]]::new()
$script:BenchGroupOrder = @('CPU', 'RAM', 'GPU', 'Laufwerke', 'WinSAT')
$script:BenchGroupNames = @{ 'CPU' = 'Prozessor'; 'RAM' = 'Arbeitsspeicher'; 'GPU' = 'Grafik'; 'Laufwerke' = 'Laufwerke'; 'WinSAT' = 'WinSAT-Bewertung' }
$script:BenchHead = @{}
$script:WinsatTotal = 0.0
$script:BenchShort = @{}
$script:BenchRefSummary = ''
$script:BenchRefName = ''

# Messgrößen für Referenz, Vergleich und Datenbank
$script:MetricDefs = @(
    @{ K = 'CPU|ST';        N = 'Prozessor Einzelkern';    U = 'Punkte';   F = 'N0' }
    @{ K = 'CPU|MT';        N = 'Prozessor Mehrkern';      U = 'Punkte';   F = 'N0' }
    @{ K = 'CPU|AES';       N = 'AES-256 verschlüsseln';   U = 'MB/s';     F = 'N0' }
    @{ K = 'CPU|SHA';       N = 'SHA-256 Prüfsumme';       U = 'MB/s';     F = 'N0' }
    @{ K = 'CPU|DEFL';      N = 'Kompression (Deflate)';   U = 'MB/s';     F = 'N0' }
    @{ K = 'RAM|Lesen';     N = 'RAM Lesen';               U = 'GB/s';     F = 'N1' }
    @{ K = 'RAM|Schreiben'; N = 'RAM Schreiben';           U = 'GB/s';     F = 'N1' }
    @{ K = 'RAM|Kopieren';  N = 'RAM Kopieren';            U = 'GB/s';     F = 'N1' }
    @{ K = 'RAM|Latenz';    N = 'RAM Latenz';              U = 'ns';       F = 'N0'; L = $true }
    @{ K = 'GPU|VMB';       N = 'Grafikspeicher-Durchsatz'; U = 'GB/s';    F = 'N1' }
    @{ K = 'GPU|DWM';       N = 'Desktop-Komposition';     U = 'Bilder/s'; F = 'N0' }
)
$script:DiskClassNames = [ordered]@{ 'NVMe5' = 'NVMe PCIe 5.0'; 'NVMe4' = 'NVMe PCIe 4.0'; 'NVMe3' = 'NVMe PCIe 3.0'; 'SATA-SSD' = 'SATA-SSD'; 'HDD' = 'Festplatte' }

function Read-JsonFile([string]$Path) {
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function ConvertTo-ValueTable($Obj) {
    $w = @{}
    if ($Obj) { foreach ($p in $Obj.PSObject.Properties) { try { $w[$p.Name] = [double]$p.Value } catch { } } }
    return $w
}

# Alle Systeme der Vergleichsdatenbank (Format 1 und 2; Format 2 trägt die Geräteidentität)
function Get-DbEntries {
    $list = [System.Collections.Generic.List[object]]::new()
    if (-not $script:DbDir -or -not (Test-Path $script:DbDir)) { return @() }
    foreach ($f in Get-ChildItem -LiteralPath $script:DbDir -Filter '*.json' -File -ErrorAction SilentlyContinue) {
        $j = Read-JsonFile $f.FullName
        if (-not $j) { continue }
        $list.Add([pscustomobject]@{
            Path = $f.FullName; Name = [string]$j.Name; Computer = [string]$j.Computer; Datum = [string]$j.Datum
            Werte = (ConvertTo-ValueTable $j.Werte); Messwerte = (ConvertTo-ValueTable $j.Messwerte); Messdauer = [string]$j.Messdauer
            Hardware = $j.Hardware; Befunde = $j.Befunde; Laufwerke = @($j.Laufwerke); Ordner = [string]$j.Ordner
            Format = [string]$j.Format; GeraetId = $(if ($j.Geraet) { [string]$j.Geraet.Id } else { '' })
        })
    }
    Set-DbDeviceKeys $list
    return $list.ToArray()
}

# Je Gerät nur der neueste Eintrag mit Messwerten; -ExcludeCurrent lässt das Gerät dieses Laufs weg
function Get-DbLatest($Entries, [switch]$ExcludeCurrent) {
    $dev = $(if ($ExcludeCurrent) { (Get-DeviceIdentity).Id } else { '' })
    @($Entries | Where-Object { $_.Werte.Count -and $_.Computer -and -not ($ExcludeCurrent -and (Test-SameDevice $_ $dev $env:COMPUTERNAME)) } | Group-Object GeraetKey |
        ForEach-Object { $_.Group | Sort-Object Datum -Descending | Select-Object -First 1 })
}

function Import-BenchReference {
    $script:Ref = $script:RefDefault
    if ($ReferenzDatei -eq '*median') {
        $entries = @(Get-DbLatest (Get-DbEntries) -ExcludeCurrent)
        if ($entries.Count) {
            $w = @{}
            $keys = @($entries | ForEach-Object { $_.Werte.Keys } | Select-Object -Unique)
            foreach ($k in $keys) { $m = Get-Median @($entries | ForEach-Object { $_.Werte[$k] } | Where-Object { $_ -gt 0 }); if ($m) { $w[$k] = [math]::Round($m, 1) } }
            $script:Ref = @{ Name = ('Median von {0} Systemen der Vergleichsdatenbank' -f $entries.Count); Datum = (Get-Date).ToString('yyyy-MM-dd', $script:Inv); Werte = $w; Quelle = 'Vergleichsdatenbank' }
            return
        }
        Add-Line '  Die Vergleichsdatenbank enthält noch keine anderen Systeme, daher gilt die Standardreferenz.'
    }
    $cands = @()
    if ($ReferenzDatei -and $ReferenzDatei -ne '*median') { $cands += $ReferenzDatei }
    if ($script:DataDir) { $cands += (Join-Path $script:DataDir 'Referenz.json'), (Join-Path $script:DataDir 'PC-Diagnose-Referenz.json') }
    foreach ($f in $cands) {
        if (-not $f -or -not (Test-Path -LiteralPath $f)) { continue }
        $j = Read-JsonFile $f
        if (-not $j) { continue }
        $w = ConvertTo-ValueTable $j.Werte
        if ($w.Count) { $script:Ref = @{ Name = [string]$j.Name; Datum = [string]$j.Datum; Werte = $w; Quelle = $f }; return }
    }
}

function Get-RefPct([string]$RefKey, [double]$Wert, [switch]$LowerBetter) {
    if (-not $RefKey -or -not $script:Ref -or -not $script:Ref.Werte.ContainsKey($RefKey)) { return $null }
    $r = [double]$script:Ref.Werte[$RefKey]
    if ($r -le 0 -or $Wert -le 0) { return $null }
    if ($LowerBetter) { return [int][math]::Round($r / $Wert * 100.0) }
    return [int][math]::Round($Wert / $r * 100.0)
}

function Get-StatusRank([string]$s) { switch ($s) { 'Fehler' { 3 } 'Warnung' { 2 } 'Info' { 1 } default { 0 } } }

function Get-GeoMean($Values) {
    $v = @($Values | Where-Object { $null -ne $_ -and [double]$_ -gt 0 } | ForEach-Object { [double]$_ })
    if (-not $v.Count) { return $null }
    $s = 0.0; foreach ($x in $v) { $s += [math]::Log($x) }
    return [int][math]::Round([math]::Exp($s / $v.Count))
}

# Zusammenfassung einer Benchmark-Gruppe: schlechtester Status, Referenz-% (geometrisches Mittel), Kopfzeile
function Get-BenchGroup([string]$Gruppe) {
    $items = @($script:BenchResults | Where-Object { $_.Gruppe -eq $Gruppe })
    $disks = @()
    if ($Gruppe -eq 'Laufwerke') { $disks = @($script:BenchDisks) }
    $all = @($items) + @($disks)
    $st = 'OK'; foreach ($i in $all) { if ((Get-StatusRank $i.Status) -gt (Get-StatusRank $st)) { $st = $i.Status } }
    $ref = $(if ($Gruppe -eq 'Laufwerke') { Get-GeoMean ($disks | ForEach-Object { $_.RefPct }) } else { Get-GeoMean ($items | ForEach-Object { $_.RefPct }) })
    $head = [string]$script:BenchHead[$Gruppe]
    return [pscustomobject]@{ Gruppe = $Gruppe; Name = [string]$script:BenchGroupNames[$Gruppe]; Status = $st; RefPct = $ref
        Referenz = $(if ($null -ne $ref) { '{0} %' -f $ref } else { '' }); Kopf = $head; Anzahl = $all.Count; Items = $items; Disks = $disks }
}

function Send-BenchGroup([string]$Gruppe) {
    $g = Get-BenchGroup $Gruppe
    if ($g.Anzahl) { Send-GuiEvent 'BGRP' $Gruppe $g.Name $g.Status $g.Kopf $g.Referenz }
}

# Messwerte dieses Laufs als Referenzwerte (Laufwerke als Mittelwert je Klasse)
function Get-CurrentRefValues {
    $w = @{}
    foreach ($b in $script:BenchResults) { if ($b.RefKey -and $b.Wert -gt 0 -and $b.RefKey -notlike 'DISK|*') { $w[$b.RefKey] = [math]::Round([double]$b.Wert, 1) } }
    $byKey = @{}
    foreach ($b in $script:BenchResults) { if ($b.RefKey -like 'DISK|*' -and $b.Wert -gt 0) { if (-not $byKey.ContainsKey($b.RefKey)) { $byKey[$b.RefKey] = New-Object System.Collections.ArrayList }; [void]$byKey[$b.RefKey].Add([double]$b.Wert) } }
    foreach ($k in $byKey.Keys) { $w[$k] = [math]::Round((($byKey[$k] | Measure-Object -Average).Average), 0) }
    return $w
}

function Save-BenchReference {
    $o = [ordered]@{ Name = $(if ($script:BenchRefName) { $script:BenchRefName } else { [Environment]::MachineName }); Datum = (Get-Date).ToString('yyyy-MM-dd', $script:Inv); Version = $ScriptVersion; Werte = (Get-CurrentRefValues) }
    $json = $o | ConvertTo-Json -Depth 4
    $saved = @()
    $targets = @()
    if ($script:DataDir) { $targets += (Join-Path $script:DataDir 'Referenz.json') }
    foreach ($f in $targets) {
        try { [IO.File]::WriteAllText($f, $json, (New-Object Text.UTF8Encoding($false))); $saved += $f } catch { }
    }
    return $saved
}

# Vergleich mit Systemen aus der Datenbank: eine Zeile je Messgröße
function Get-CompareRows {
    $cur = Get-CurrentRefValues
    $sys = @($script:CmpSystems)
    $latest = @(Get-DbLatest (Get-DbEntries) -ExcludeCurrent)
    $defs = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $script:MetricDefs) { $defs.Add($d) }
    foreach ($cls in $script:DiskClassNames.Keys) {
        $has = $cur.ContainsKey("DISK|$cls|SR") -or @($sys | Where-Object { $_.Werte.ContainsKey("DISK|$cls|SR") }).Count
        if (-not $has) { continue }
        $cn = $script:DiskClassNames[$cls]
        $defs.Add(@{ K = "DISK|$cls|SR"; N = "$cn seq. lesen"; U = 'MB/s'; F = 'N0' })
        $defs.Add(@{ K = "DISK|$cls|SW"; N = "$cn seq. schreiben"; U = 'MB/s'; F = 'N0' })
        $defs.Add(@{ K = "DISK|$cls|R1"; N = "$cn 4K zufällig QD1"; U = 'IOPS'; F = 'N0' })
    }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $defs) {
        $mine = $(if ($cur.ContainsKey($d.K)) { [double]$cur[$d.K] } else { $null })
        $vals = @($sys | ForEach-Object { if ($_.Werte.ContainsKey($d.K)) { [double]$_.Werte[$d.K] } else { $null } })
        if ($null -eq $mine -or -not @($vals | Where-Object { $null -ne $_ }).Count) { continue }
        $rank = ''
        if ($null -ne $mine) {
            $pool = @($latest | ForEach-Object { if ($_.Werte.ContainsKey($d.K)) { [double]$_.Werte[$d.K] } } | Where-Object { $_ -gt 0 })
            if ($pool.Count) {
                $better = @($pool | Where-Object { if ($d.L) { $_ -lt $mine } else { $_ -gt $mine } }).Count
                $rank = 'Platz {0} von {1}' -f ($better + 1), ($pool.Count + 1)
            }
        }
        $rows.Add([pscustomobject]@{ Key = $d.K; Messung = $d.N; Einheit = $d.U; Format = $d.F; LowerBetter = [bool]$d.L; Dieses = $mine; Werte = $vals; Rang = $rank })
    }
    return $rows.ToArray()
}

function Format-Metric($Value, [string]$Fmt, [string]$Unit) {
    if ($null -eq $Value -or [double]$Value -le 0) { return '' }
    return ('{0:' + $Fmt + '} {1}') -f [double]$Value, $Unit
}

function Get-RelText($Mine, $Other, [bool]$LowerBetter) {
    if ($null -eq $Mine -or $null -eq $Other -or [double]$Mine -le 0 -or [double]$Other -le 0) { return '' }
    # positiv = das andere System ist besser
    $d = $(if ($LowerBetter) { ([double]$Mine / [double]$Other - 1) * 100 } else { ([double]$Other / [double]$Mine - 1) * 100 })
    return '{0:+0;-0;0} %' -f $d
}

function New-LineSvg($Points, [string]$Unit) {
    $inv = $script:Inv
    $pts = @($Points | Where-Object { $null -ne $_.V -and $_.V -gt 0 })
    if ($pts.Count -lt 2) { return '' }
    $W = 960; $H = 260; $ml = 70; $mr = 20; $mt = 14; $mb = 38
    $xmax = [double](($pts | Measure-Object T -Maximum).Maximum); if ($xmax -le 0) { $xmax = 1 }
    $vmin = [double](($pts | Measure-Object V -Minimum).Minimum); $vmax = [double](($pts | Measure-Object V -Maximum).Maximum)
    $raw = ($vmax - $vmin) / 4; if ($raw -le 0) { $raw = [math]::Max(1.0, $vmax * 0.05) }
    $mag = [math]::Pow(10, [math]::Floor([math]::Log10($raw)))
    $nice = $mag; foreach ($f in 1, 2, 2.5, 5, 10) { if ($f * $mag -ge $raw) { $nice = $f * $mag; break } }
    $y0 = [math]::Floor($vmin / $nice) * $nice; $y1 = [math]::Ceiling($vmax / $nice) * $nice; if ($y1 -le $y0) { $y1 = $y0 + $nice }
    $pw = $W - $ml - $mr; $ph = $H - $mt - $mb
    $fx = { param($t) $ml + $t / $xmax * $pw }
    $fy = { param($v) $mt + ($y1 - $v) / ($y1 - $y0) * $ph }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append([string]::Format($inv, '<svg class="chart" viewBox="0 0 {0} {1}" role="img" preserveAspectRatio="xMidYMid meet">', $W, $H))
    for ($v = $y0; $v -le $y1 + $nice / 1000; $v += $nice) {
        $y = & $fy $v
        [void]$sb.Append([string]::Format($inv, '<line class="grid" x1="{0}" x2="{1}" y1="{2:0.#}" y2="{2:0.#}"/>', $ml, $W - $mr, $y))
        [void]$sb.Append([string]::Format($inv, '<text x="{0}" y="{1:0.#}" text-anchor="end" dominant-baseline="middle">{2}</text>', $ml - 8, $y, ('{0:N0}' -f $v)))
    }
    $tickS = 15
    foreach ($c in 15, 30, 60, 120, 300, 600, 900, 1800, 3600) { $tickS = $c; if ($xmax / $c -le 8) { break } }
    for ($t = 0; $t -le $xmax + 0.1; $t += $tickS) {
        $x = & $fx $t
        $lab = $(if ($tickS -ge 60) { '{0} min' -f [int]($t / 60) } else { '{0} s' -f [int]$t })
        [void]$sb.Append([string]::Format($inv, '<line class="tick" x1="{0:0.#}" x2="{0:0.#}" y1="{1}" y2="{2}"/><text x="{0:0.#}" y="{3}" text-anchor="middle">{4}</text>', $x, $mt + $ph, $mt + $ph + 5, $H - 12, $lab))
    }
    $poly = ($pts | ForEach-Object { [string]::Format($inv, '{0:0.#},{1:0.#}', (& $fx $_.T), (& $fy $_.V)) }) -join ' '
    [void]$sb.Append(('<polyline class="line" points="{0}"/>' -f $poly))
    $stepPts = [math]::Max(1, [int][math]::Ceiling($pts.Count / 300))
    for ($i = 0; $i -lt $pts.Count; $i += $stepPts) {
        $p = $pts[$i]
        $tl = '{0}:{1:00} min  ·  {2:N0} {3}' -f [int][math]::Floor($p.T / 60), [int]($p.T % 60), $p.V, $Unit
        [void]$sb.Append([string]::Format($inv, '<circle class="hit" cx="{0:0.#}" cy="{1:0.#}" r="6"><title>{2}</title></circle>', (& $fx $p.T), (& $fy $p.V), $tl))
    }
    [void]$sb.Append('</svg>')
    return $sb.ToString()
}

# Mehrere Kurven in einem Diagramm (Lasttest): Serien @{ Name; Cls = 's1'..'s4'; Points = T/V }, Bezugslinien @{ V; Label; Cls = 'lim'|'tj' },
# Markierungen @{ T; Label } als senkrechte Linien (Lastende, Abbruch, Beginn der Drosselung). Leer, wenn keine Serie zwei Punkte hat.
function New-MultiLineSvg {
    param($Series, [string]$Unit, $RefLines = @(), $Marks = @(), [string]$Fmt = 'N0')
    $inv = $script:Inv
    $ser = @($Series | ForEach-Object { $s = $_; $p = @($s.Points | Where-Object { $null -ne $_.V -and -not [double]::IsNaN([double]$_.V) }); if ($p.Count -ge 2) { [pscustomobject]@{ Name = $s.Name; Cls = $s.Cls; Points = $p } } })
    if (-not $ser.Count) { return '' }
    $W = 960; $H = 250; $ml = 70; $mr = 20; $mt = 14; $mb = 38
    $allP = @($ser | ForEach-Object { $_.Points })
    $xmax = [double](($allP | Measure-Object T -Maximum).Maximum); if ($xmax -le 0) { $xmax = 1 }
    $vals = @($allP | ForEach-Object { [double]$_.V }) + @($RefLines | ForEach-Object { [double]$_.V })
    $vmin = [double](($vals | Measure-Object -Minimum).Minimum); $vmax = [double](($vals | Measure-Object -Maximum).Maximum)
    $raw = ($vmax - $vmin) / 4; if ($raw -le 0) { $raw = [math]::Max(1.0, $vmax * 0.05) }
    $mag = [math]::Pow(10, [math]::Floor([math]::Log10($raw)))
    $nice = $mag; foreach ($f in 1, 2, 2.5, 5, 10) { if ($f * $mag -ge $raw) { $nice = $f * $mag; break } }
    $y0 = [math]::Floor($vmin / $nice) * $nice; $y1 = [math]::Ceiling($vmax / $nice) * $nice; if ($y1 -le $y0) { $y1 = $y0 + $nice }
    $pw = $W - $ml - $mr; $ph = $H - $mt - $mb
    $fx = { param($t) $ml + $t / $xmax * $pw }
    $fy = { param($v) $mt + ($y1 - $v) / ($y1 - $y0) * $ph }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<p class="lgd">')
    foreach ($s in $ser) {
        $lastV = [double]$s.Points[$s.Points.Count - 1].V; $maxV = [double](($s.Points | Measure-Object V -Maximum).Maximum)
        [void]$sb.Append(('<span><i class="sw {0}"></i>{1} <small>max {2} {3}</small></span>' -f $s.Cls, (ConvertTo-HtmlText $s.Name), $maxV.ToString($Fmt, [Globalization.CultureInfo]::CurrentCulture), (ConvertTo-HtmlText $Unit)))
    }
    foreach ($r in $RefLines) { [void]$sb.Append(('<span><i class="sw {0}"></i>{1}</span>' -f $r.Cls, (ConvertTo-HtmlText $r.Label))) }
    [void]$sb.Append('</p>')
    [void]$sb.Append([string]::Format($inv, '<svg class="chart ml" viewBox="0 0 {0} {1}" role="img" preserveAspectRatio="xMidYMid meet">', $W, $H))
    for ($v = $y0; $v -le $y1 + $nice / 1000; $v += $nice) {
        $y = & $fy $v
        [void]$sb.Append([string]::Format($inv, '<line class="grid" x1="{0}" x2="{1}" y1="{2:0.#}" y2="{2:0.#}"/>', $ml, $W - $mr, $y))
        [void]$sb.Append([string]::Format($inv, '<text x="{0}" y="{1:0.#}" text-anchor="end" dominant-baseline="middle">{2}</text>', $ml - 8, $y, ('{0:N0}' -f $v)))
    }
    $tickS = 15
    foreach ($c in 15, 30, 60, 120, 300, 600, 900, 1800, 3600) { $tickS = $c; if ($xmax / $c -le 8) { break } }
    for ($t = 0; $t -le $xmax + 0.1; $t += $tickS) {
        $x = & $fx $t
        $lab = $(if ($tickS -ge 60) { '{0} min' -f [int]($t / 60) } else { '{0} s' -f [int]$t })
        [void]$sb.Append([string]::Format($inv, '<line class="tick" x1="{0:0.#}" x2="{0:0.#}" y1="{1}" y2="{2}"/><text x="{0:0.#}" y="{3}" text-anchor="middle">{4}</text>', $x, $mt + $ph, $mt + $ph + 5, $H - 12, $lab))
    }
    foreach ($m in $Marks) {
        if ($null -eq $m.T -or $m.T -lt 0 -or $m.T -gt $xmax) { continue }
        $x = & $fx ([double]$m.T)
        [void]$sb.Append([string]::Format($inv, '<line class="mark" x1="{0:0.#}" x2="{0:0.#}" y1="{1}" y2="{2}"/><text class="mk" x="{3:0.#}" y="{4}">{5}</text>', $x, $mt, $mt + $ph, $x + 4, $mt + 11, (ConvertTo-HtmlText $m.Label)))
    }
    foreach ($r in $RefLines) {
        $y = & $fy ([double]$r.V)
        [void]$sb.Append([string]::Format($inv, '<line class="{3}" x1="{0}" x2="{1}" y1="{2:0.#}" y2="{2:0.#}"><title>{4}</title></line>', $ml, $W - $mr, $y, $r.Cls, (ConvertTo-HtmlText $r.Label)))
    }
    foreach ($s in $ser) {
        $poly = ($s.Points | ForEach-Object { [string]::Format($inv, '{0:0.#},{1:0.#}', (& $fx $_.T), (& $fy ([double]$_.V))) }) -join ' '
        [void]$sb.Append(('<polyline class="line {0}" points="{1}"/>' -f $s.Cls, $poly))
        $stepPts = [math]::Max(1, [int][math]::Ceiling($s.Points.Count / 200))
        for ($i = 0; $i -lt $s.Points.Count; $i += $stepPts) {
            $p = $s.Points[$i]
            $tl = '{0}:{1:00} min  ·  {2}: {3} {4}' -f [int][math]::Floor($p.T / 60), [int]($p.T % 60), $s.Name, ([double]$p.V).ToString($Fmt, [Globalization.CultureInfo]::CurrentCulture), $Unit
            [void]$sb.Append([string]::Format($inv, '<circle class="hit {3}" cx="{0:0.#}" cy="{1:0.#}" r="6"><title>{2}</title></circle>', (& $fx $p.T), (& $fy ([double]$p.V)), (ConvertTo-HtmlText $tl), $s.Cls))
        }
    }
    [void]$sb.Append('</svg>')
    return $sb.ToString()
}

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
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { & $Body }
    catch {
        Add-Line ('  FEHLER in diesem Abschnitt: {0}' -f $_.Exception.Message)
        Write-Warning ('{0}: {1}' -f $Title, $_.Exception.Message)
        Write-Checkpoint 'FEHLER' ('{0}: {1}' -f $Title, $_.Exception.Message)
    }
    $sw.Stop()
    $script:Timings.Add([pscustomobject]@{ Abschnitt = $Title; Dauer = ('{0:hh\:mm\:ss}' -f $sw.Elapsed) })
    Write-Checkpoint 'OK' ('{0} ({1:hh\:mm\:ss})' -f $Title, $sw.Elapsed)
    Save-Partial
}

# Statische WMI-Klassen (Hardware) nur einmal je Lauf abfragen
$script:CimCache = @{}
function Get-CimCached([string]$Class) {
    if (-not $script:CimCache.ContainsKey($Class)) { $script:CimCache[$Class] = @(Get-CimInstance $Class -ErrorAction SilentlyContinue) }
    return $script:CimCache[$Class]
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

function Get-ReportCss {
    return @'
:root{--bg:#f5f6f8;--panel:#fff;--text:#1c2330;--muted:#5f6878;--line:#e2e5ea;--code:#f1f3f6;
--crit:#b42318;--crit-bg:#fdeceb;--warn:#9a5b00;--warn-bg:#fdf2d8;--info:#1f5bc4;--info-bg:#e7efff;--ok:#11703f;--ok-bg:#e2f5e9;--skip:#667085;--skip-bg:#eceef2}
@media (prefers-color-scheme:dark){:root{--bg:#111419;--panel:#1a1f27;--text:#e5e8ee;--muted:#98a1b0;--line:#2b323d;--code:#141820;
--crit:#ff8f86;--crit-bg:#3b1d1c;--warn:#f3c26e;--warn-bg:#3a2d12;--info:#94b6ff;--info-bg:#1b2944;--ok:#7cd6a0;--ok-bg:#14321f;--skip:#a3abb8;--skip-bg:#252b35}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 "Segoe UI",system-ui,-apple-system,sans-serif}
main{max-width:1200px;margin:0 auto;padding:28px 20px 60px}
header{display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap;margin-bottom:22px}
h1{margin:0;font-size:27px;font-weight:650}
h1 span{color:var(--muted);font-weight:400}
.meta{margin:4px 0 0;color:var(--muted);font-size:13.5px}
.verdict{padding:9px 18px;border-radius:999px;font-weight:650;font-size:15px}
.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-bottom:20px}
.card{background:var(--panel);border:1px solid var(--line);border-left:6px solid var(--line);border-radius:12px;padding:14px 18px}
.card b{display:block;font-size:32px;line-height:1.15;font-variant-numeric:tabular-nums}
.card span{color:var(--muted)}
.box{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:18px 22px;margin-bottom:18px;overflow-x:auto}
.box h2{font-size:17px;margin:0 0 12px;font-weight:650}
dl{display:grid;grid-template-columns:190px 1fr;gap:7px 18px;margin:0}
dt{color:var(--muted)} dd{margin:0}
table{width:100%;border-collapse:collapse;font-size:14px}
th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
tr:last-child td{border-bottom:0}
th{color:var(--muted);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.05em}
.badge{display:inline-block;padding:2px 10px;border-radius:999px;font-size:12px;font-weight:650;white-space:nowrap;text-transform:uppercase}
.crit{background:var(--crit-bg);color:var(--crit)} .warn{background:var(--warn-bg);color:var(--warn)}
.info{background:var(--info-bg);color:var(--info)} .ok{background:var(--ok-bg);color:var(--ok)} .skip{background:var(--skip-bg);color:var(--skip)}
.card.crit,.card.warn,.card.info{background:var(--panel)}
.card.crit{border-left-color:var(--crit)} .card.crit b{color:var(--crit)}
.card.warn{border-left-color:var(--warn)} .card.warn b{color:var(--warn)}
.card.info{border-left-color:var(--info)} .card.info b{color:var(--info)}
.empty{color:var(--muted);margin:0}
.bar{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:8px}
.bar h2{margin:0}
button{font:inherit;font-size:13px;padding:5px 12px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--text);cursor:pointer}
details{border-top:1px solid var(--line)} details:first-of-type{border-top:0}
summary{cursor:pointer;padding:10px 2px;font-weight:600}
pre{margin:0 0 14px;padding:14px;background:var(--code);border-radius:8px;overflow:auto;font:12.5px/1.45 Consolas,"Cascadia Mono",monospace;white-space:pre}
footer{color:var(--muted);font-size:12.5px;margin-top:26px}
.note{color:var(--muted);font-size:13px;margin:-4px 0 12px}
.box h3{font-size:14px;font-weight:600;margin:14px 0 6px}
td.num{white-space:nowrap;font-variant-numeric:tabular-nums}
td.idx{white-space:nowrap}
.ib{position:relative;display:inline-block;width:130px;height:8px;border-radius:4px;background:var(--skip-bg);vertical-align:middle;margin-right:8px}
.ibf{position:absolute;left:0;top:0;bottom:0;border-radius:4px}
.ibf.ok{background:var(--ok)} .ibf.warn{background:var(--warn)} .ibf.crit{background:var(--crit)} .ibf.info{background:var(--info)} .ibf.skip{background:var(--skip)}
.ibm{position:absolute;left:66.7%;top:-3px;bottom:-3px;width:2px;background:var(--muted)}
.ib.s{width:64px}
details.grp{border:1px solid var(--line);border-radius:10px;margin:10px 0 0;padding:0 14px}
details.grp:first-of-type{border-top:1px solid var(--line)}
details.grp>summary{display:flex;align-items:center;gap:14px;flex-wrap:wrap;list-style:none;padding:12px 0}
details.grp>summary::-webkit-details-marker{display:none}
details.grp>summary::before{content:"";width:7px;height:7px;border-right:2px solid var(--muted);border-bottom:2px solid var(--muted);transform:rotate(-45deg);transition:transform .15s;margin:0 2px 0 2px}
details.grp[open]>summary::before{transform:rotate(45deg)}
details.grp[open]>summary{border-bottom:1px solid var(--line)}
details.grp table{margin:6px 0 10px}
.gname{font-weight:650;min-width:135px}
.gsub{flex:1;color:var(--muted);font-weight:400;font-size:14px;min-width:200px}
.gref{color:var(--muted);font-weight:400;font-size:13.5px;white-space:nowrap}
.gref b{color:var(--text);font-variant-numeric:tabular-nums}
th.r,td.r{text-align:right}
td.muted{color:var(--muted)}
td small{color:var(--muted);font-size:12px}
small.hint{display:block;color:var(--muted);font-size:12.5px;line-height:1.35;margin-top:1px}
table.disks td,table.disks th{padding:8px 8px}
table.disks th{white-space:nowrap}
.note.tight{margin:0 0 12px}
.tw{overflow-x:auto}
td.nw{white-space:nowrap}
th small{font-weight:400;text-transform:none;letter-spacing:0}
.chart{width:100%;height:auto;display:block}
.chart text{fill:var(--muted);font-size:12px;font-family:inherit}
.chart .grid{stroke:var(--line);stroke-width:1}
.chart .tick{stroke:var(--line)}
.chart .line{fill:none;stroke:var(--info);stroke-width:2;stroke-linejoin:round;stroke-linecap:round}
.chart .hit{fill:transparent}
.chart .hit:hover{fill:var(--info)}
.chart .line.s1{stroke:var(--info)} .chart .line.s2{stroke:#c2410c} .chart .line.s3{stroke:#0f766e} .chart .line.s4{stroke:#7c3aed}
.chart .hit.s2:hover{fill:#c2410c} .chart .hit.s3:hover{fill:#0f766e} .chart .hit.s4:hover{fill:#7c3aed}
.chart line.lim{stroke:var(--crit);stroke-width:1.5;stroke-dasharray:6 4} .chart line.tj{stroke:var(--warn);stroke-width:1.5;stroke-dasharray:2 4}
.chart line.mark{stroke:var(--muted);stroke-width:1;stroke-dasharray:3 3} .chart text.mk{font-size:11px}
.lgd{display:flex;flex-wrap:wrap;gap:4px 18px;margin:0 0 4px;font-size:13px} .lgd small{color:var(--muted)}
i.sw.s1{background:var(--info)} i.sw.s2{background:#c2410c} i.sw.s3{background:#0f766e} i.sw.s4{background:#7c3aed}
i.sw.lim{background:transparent;border-top:2px dashed var(--crit);border-radius:0;height:0;width:16px;vertical-align:3px}
i.sw.tj{background:transparent;border-top:2px dotted var(--warn);border-radius:0;height:0;width:16px;vertical-align:3px}
.thr{border:1px solid var(--line);border-left:6px solid var(--line);border-radius:10px;padding:10px 14px;margin:8px 0 14px}
.thr.warn{border-left-color:var(--warn);background:var(--panel);color:var(--text)} .thr.info{border-left-color:var(--info);background:var(--panel);color:var(--text)} .thr.ok{border-left-color:var(--ok);background:var(--panel);color:var(--text)}
.thr ul{margin:6px 0 0;padding-left:18px;color:var(--muted);font-size:13.5px}
@media (prefers-color-scheme:dark){.chart .line.s2{stroke:#fb923c} .chart .line.s3{stroke:#2dd4bf} .chart .line.s4{stroke:#c4b5fd} i.sw.s2{background:#fb923c} i.sw.s3{background:#2dd4bf} i.sw.s4{background:#c4b5fd}}
small.okt{color:var(--ok)} small.warnt{color:var(--warn)}
.ov{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin:2px 0 14px}
a.tile{display:block;text-decoration:none;color:inherit;background:var(--panel);border:1px solid var(--line);border-top:4px solid var(--line);border-radius:10px;padding:11px 14px 12px}
a.tile:hover{border-color:var(--muted)}
a.tile.tok{border-top-color:var(--ok)} a.tile.twarn{border-top-color:var(--warn)} a.tile.tcrit{border-top-color:var(--crit)} a.tile.tinfo{border-top-color:var(--info)}
.tile h4{display:flex;justify-content:space-between;align-items:center;gap:8px;margin:0;font-size:12.5px;color:var(--muted);font-weight:600;text-transform:uppercase;letter-spacing:.04em}
.tile h4 .dot{width:9px;height:9px;border-radius:50%;flex:none}
.dot.ok{background:var(--ok)} .dot.warn{background:var(--warn)} .dot.crit{background:var(--crit)} .dot.info{background:var(--info)}
.tile .big{font-size:27px;font-weight:650;font-variant-numeric:tabular-nums;line-height:1.2;margin:6px 0 8px}
.tile .big small{font-size:13px;color:var(--muted);font-weight:400}
.tile p{margin:8px 0 0;font-size:12.5px;color:var(--muted);line-height:1.35}
.rb{position:relative;display:block;height:9px;border-radius:5px;background:var(--skip-bg)}
.rb.s{display:inline-block;width:80px;height:7px;vertical-align:middle;margin-right:8px}
.rbf{position:absolute;left:0;top:0;bottom:0;border-radius:5px}
.rbf.ok{background:var(--ok)} .rbf.warn{background:var(--warn)} .rbf.crit{background:var(--crit)} .rbf.info{background:var(--info)} .rbf.skip{background:var(--skip)}
.rbm{position:absolute;left:66.7%;top:-3px;bottom:-3px;width:2px;background:var(--text);opacity:.45}
.dl{color:var(--muted);font-size:12px;margin-left:6px;white-space:nowrap} .dl.okt{color:var(--ok)} .dl.warnt{color:var(--warn)}
td .dl{margin-left:0}
.chart.ws{max-width:860px}
.chart.ws rect.bg{fill:var(--skip-bg)}
.chart.ws rect.b-ok{fill:var(--ok)} .chart.ws rect.b-info{fill:var(--info)} .chart.ws rect.b-warn{fill:var(--warn)} .chart.ws rect.b-crit{fill:var(--crit)}
.chart.ws text.l{fill:var(--text);font-size:13.5px}
.chart.ws text.v{fill:var(--text);font-size:14px;font-weight:650}
.chart.ws tspan.d{fill:var(--muted);font-weight:400;font-size:12px}
.chart.ws line.tot{stroke:var(--text);stroke-width:1.5;stroke-dasharray:5 4;opacity:.6}
.chart.ws text.tl{fill:var(--text);font-size:12px;font-weight:600}
:root{--s0:#2f6fde;--s1:#e07a1f;--s2:#1f9d8a;--s3:#9b4dca;--s4:#d14b4b;--s5:#6b7a8f}
@media (prefers-color-scheme:dark){:root{--s0:#6e9cf5;--s1:#f0a057;--s2:#4cc7b3;--s3:#c08ae6;--s4:#ef7f7f;--s5:#9aa7b8}}
.c0{background:var(--s0)} .c1{background:var(--s1)} .c2{background:var(--s2)} .c3{background:var(--s3)} .c4{background:var(--s4)} .c5{background:var(--s5)}
i.sw{display:inline-block;width:11px;height:11px;border-radius:3px;margin-right:7px;vertical-align:-1px;flex:none}
.mrow{display:grid;grid-template-columns:240px 1fr;gap:6px 20px;padding:11px 0;border-top:1px solid var(--line)}
.box h2+.mrow,.box .note+.mrow,.mgh+.mrow{border-top:0}
.mlab{font-weight:600;font-size:14px;line-height:1.35}
.mlab small{display:block;color:var(--muted);font-weight:400;font-size:12px;margin-top:2px}
.mb{display:grid;grid-template-columns:minmax(90px,170px) 1fr minmax(120px,190px);align-items:center;gap:10px;font-size:13px;margin:3px 0}
.mn{display:flex;align-items:center;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mt{height:13px;border-radius:7px;background:var(--skip-bg);position:relative;overflow:hidden}
.mf{position:absolute;left:0;top:0;bottom:0;border-radius:7px}
.mv{font-variant-numeric:tabular-nums;white-space:nowrap}
.mv.na{color:var(--muted);font-style:italic}
.mb.best .mv{font-weight:650}
.mgh{font-size:13px;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;font-weight:600;margin:16px 0 2px}
.mgh:first-of-type{margin-top:4px}
.syscards{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px;margin-bottom:18px}
.sys{background:var(--panel);border:1px solid var(--line);border-top:5px solid var(--line);border-radius:12px;padding:14px 18px}
.sys.k0{border-top-color:var(--s0)} .sys.k1{border-top-color:var(--s1)} .sys.k2{border-top-color:var(--s2)} .sys.k3{border-top-color:var(--s3)} .sys.k4{border-top-color:var(--s4)} .sys.k5{border-top-color:var(--s5)}
.sys h3{margin:0;font-size:18px;display:flex;align-items:center}
.sys .meta{margin:0 0 10px}
.sys dl{grid-template-columns:110px 1fr;font-size:13.5px;gap:4px 12px}
.bfc{margin:12px 0 0}
.mini{display:inline-block;position:relative;width:60px;height:6px;border-radius:3px;background:var(--skip-bg);overflow:hidden;vertical-align:middle;margin-right:8px}
.mini .mf{border-radius:3px}
@media (max-width:700px){.mrow{grid-template-columns:1fr}.mb{grid-template-columns:90px 1fr 120px}}
@media (max-width:700px){.cards{grid-template-columns:1fr}dl{grid-template-columns:1fr}dt{margin-top:6px}}
@media print{body{background:#fff}button{display:none}.box{break-inside:avoid}}
'@
}

#region ---------- Grafische Bausteine für die Berichte ----------
$script:GroupOfKey = @{ 'CPU' = 'Prozessor'; 'RAM' = 'Arbeitsspeicher'; 'GPU' = 'Grafik'; 'DISK' = 'Laufwerke'; 'LW' = 'Laufwerke'; 'WINSAT' = 'WinSAT-Bewertung' }

# Balken 0 bis 150 % mit Markierung bei 100 %
function Get-RefBar($Pct, [string]$Cls = 'info', [switch]$Small) {
    if ($null -eq $Pct -or "$Pct" -eq '') { return '' }
    $w = [math]::Round([math]::Min(150.0, [math]::Max(0.0, [double]$Pct)) / 150.0 * 100.0, 1)
    return [string]::Format($script:Inv, '<span class="rb{0}" title="{1} % der Referenz"><span class="rbf {2}" style="width:{3}%"></span><span class="rbm"></span></span>', $(if ($Small) { ' s' } else { '' }), $Pct, $Cls, $w)
}

# Abweichung farbig: positiv = besser
function Get-DeltaHtml([string]$Text) {
    if (-not $Text) { return '' }
    $m = [regex]::Match($Text, '^([+-]?\d+)')
    $c = ''
    if ($m.Success) { $d = [int]$m.Groups[1].Value; $c = $(if ($d -le -10) { 'warnt' } elseif ($d -ge 3) { 'okt' } else { '' }) }
    return ('<span class="dl {0}">{1}</span>' -f $c, (ConvertTo-HtmlText $Text))
}

# Kacheln über dem Benchmark: eine je Gruppe mit Referenzbalken
function New-BenchOverview {
    $bcls = @{ OK = 'ok'; Info = 'info'; Warnung = 'warn'; Fehler = 'crit' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<div class="ov">')
    foreach ($gk in $script:BenchGroupOrder) {
        $g = Get-BenchGroup $gk
        if (-not $g.Anzahl) { continue }
        $c = $bcls[$g.Status]; if (-not $c) { $c = 'info' }
        $kopf = $g.Kopf
        if ($gk -eq 'WinSAT' -and $script:WinsatTotal -gt 0) {
            $big = '{0:N1}<small> von 9,9</small>' -f $script:WinsatTotal
            $kopf = 'Gesamtwert = niedrigster Teilwert'
            $bar = [string]::Format($script:Inv, '<span class="rb"><span class="rbf {0}" style="width:{1:0.#}%"></span></span>', (Get-WinsatClass $script:WinsatTotal), ($script:WinsatTotal / 9.9 * 100))
        } elseif ($null -ne $g.RefPct) {
            $big = '{0}<small> % der Referenz</small>' -f $g.RefPct
            $bar = Get-RefBar $g.RefPct $c
        } else {
            $big = ConvertTo-HtmlText $g.Status
            $bar = ''
        }
        [void]$sb.Append(('<a class="tile t{0}" href="#bg-{1}" onclick="document.getElementById(''bg-{1}'').open=true"><h4>{2}<i class="dot {0}" title="{3}"></i></h4><div class="big">{4}</div>{5}<p>{6}</p></a>' -f
            $c, $gk, (ConvertTo-HtmlText $g.Name), (ConvertTo-HtmlText $g.Status), $big, $bar, (ConvertTo-HtmlText $kopf)))
    }
    [void]$sb.Append('</div>')
    return $sb.ToString()
}

function Get-WinsatClass([double]$v) { if ($v -ge 7) { 'ok' } elseif ($v -ge 5) { 'info' } elseif ($v -ge 3.5) { 'warn' } else { 'crit' } }

# WinSAT-Teilwerte als Balkendiagramm (Skala 1,0 bis 9,9, gestrichelte Linie = Gesamtwert)
function New-WinsatSvg($Items, [double]$Total) {
    $inv = $script:Inv
    $items = @($Items | Where-Object { [double]$_.Wert -gt 0 })
    if (-not $items.Count) { return '' }
    $W = 860; $rowH = 38; $ml = 175; $mr = 150; $mt = 26; $mb = 30
    $H = $mt + $items.Count * $rowH + $mb
    $pw = $W - $ml - $mr
    $fx = { param($v) $ml + ([math]::Max(1.0, [double]$v) - 1.0) / 8.9 * $pw }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append([string]::Format($inv, '<svg class="chart ws" viewBox="0 0 {0} {1}" role="img" aria-label="WinSAT-Teilwerte">', $W, $H))
    foreach ($t in 1, 2, 3, 4, 5, 6, 7, 8, 9, 9.9) {
        $x = & $fx $t
        [void]$sb.Append([string]::Format($inv, '<line class="grid" x1="{0:0.#}" x2="{0:0.#}" y1="{1}" y2="{2}"/><text x="{0:0.#}" y="{3}" text-anchor="middle">{4}</text>', $x, $mt - 6, $H - $mb, $H - 10, ('{0:0.#}' -f $t)))
    }
    $y = $mt
    foreach ($i in $items) {
        $v = [double]$i.Wert
        $cls = Get-WinsatClass $v
        [void]$sb.Append([string]::Format($inv, '<text class="l" x="{0}" y="{1:0.#}" text-anchor="end" dominant-baseline="middle">{2}</text>', $ml - 12, $y + $rowH / 2, (ConvertTo-HtmlText $i.Messung)))
        [void]$sb.Append([string]::Format($inv, '<rect class="bg" x="{0}" y="{1:0.#}" width="{2:0.#}" height="20" rx="5"/>', $ml, $y + ($rowH - 20) / 2, $pw))
        [void]$sb.Append([string]::Format($inv, '<rect class="b-{0}" x="{1}" y="{2:0.#}" width="{3:0.#}" height="20" rx="5"><title>{4}: {5:N1} von 9,9</title></rect>', $cls, $ml, $y + ($rowH - 20) / 2, [math]::Max(6.0, (& $fx $v) - $ml), (ConvertTo-HtmlText $i.Messung), $v))
        $cmp = $(if ($i.Vergleich) { '  ' + $i.Vergleich -replace ' zum letzten Lauf', ' zuletzt' -replace ' zu (\d+) Läufen', ' zu $1 Läufen' } else { '' })
        [void]$sb.Append([string]::Format($inv, '<text class="v" x="{0:0.#}" y="{1:0.#}" dominant-baseline="middle">{2}<tspan class="d">{3}</tspan></text>', $ml + $pw + 10, $y + $rowH / 2, ('{0:N1}' -f $v), (ConvertTo-HtmlText $cmp)))
        $y += $rowH
    }
    if ($Total -gt 0) {
        $x = & $fx $Total
        [void]$sb.Append([string]::Format($inv, '<line class="tot" x1="{0:0.#}" x2="{0:0.#}" y1="{1}" y2="{2}"/><text class="tl" x="{0:0.#}" y="{3}" text-anchor="middle">Gesamt {4}</text>', $x, $mt - 4, $H - $mb, $mt - 10, ('{0:N1}' -f $Total)))
    }
    [void]$sb.Append('</svg>')
    return $sb.ToString()
}

# Eine Messgröße für mehrere Systeme als Balkengruppe.
# Mode Base: Abstand zum ersten System (positiv = besser), Best: Abstand zum Bestwert, Abs: feste Skala bis AbsMax
function New-MetricBarsHtml {
    param([string]$Label, [string]$Unit, [string]$Fmt, [bool]$LowerBetter, [object[]]$Values, [string[]]$Names, [string]$Mode = 'Best', [double]$AbsMax = 0, [string]$Extra = '', [string]$Hint = '')
    $valid = @($Values | Where-Object { $null -ne $_ -and [double]$_ -gt 0 } | ForEach-Object { [double]$_ })
    if (-not $valid.Count) { return '' }
    $max = ($valid | Measure-Object -Maximum).Maximum; $min = ($valid | Measure-Object -Minimum).Minimum
    $best = $(if ($LowerBetter) { $min } else { $max })
    $sub = @($(if ($Unit) { $Unit }), $(if ($LowerBetter) { 'niedriger ist besser' } else { 'höher ist besser' }), $Extra) | Where-Object { $_ }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(('<div class="mrow"><div class="mlab">{0}<small>{1}</small>{2}</div><div class="mbars">' -f (ConvertTo-HtmlText $Label), (ConvertTo-HtmlText ($sub -join ' · ')), $(if ($Hint) { '<small class="hint">' + (ConvertTo-HtmlText $Hint) + '</small>' } else { '' })))
    for ($i = 0; $i -lt $Names.Count; $i++) {
        $v = $(if ($i -lt $Values.Count -and $null -ne $Values[$i] -and [double]$Values[$i] -gt 0) { [double]$Values[$i] } else { $null })
        if ($null -eq $v) {
            [void]$sb.Append(('<div class="mb"><span class="mn"><i class="sw c{0}"></i>{1}</span><span class="mt"></span><span class="mv na">nicht gemessen</span></div>' -f ($i % 6), (ConvertTo-HtmlText $Names[$i])))
            continue
        }
        $w = $(if ($Mode -eq 'Abs' -and $AbsMax -gt 0) { $v / $AbsMax } elseif ($LowerBetter) { $min / $v } else { $v / $max }) * 100
        $d = ''
        if ($Mode -eq 'Base') {
            if ($i -gt 0) { $rel = Get-RelText $Values[0] $v $LowerBetter; if ($rel) { $d = Get-DeltaHtml $rel } }
        } elseif ($valid.Count -gt 1) {
            if ($v -eq $best) { $d = '<span class="dl okt">Bestwert</span>' }
            else { $p = $(if ($LowerBetter) { ($best / $v - 1) * 100 } else { ($v / $best - 1) * 100 }); $d = '<span class="dl">{0:+0;-0;0} %</span>' -f $p }
        }
        [void]$sb.Append([string]::Format($script:Inv, '<div class="mb{0}"><span class="mn" title="{1}"><i class="sw c{2}"></i>{1}</span><span class="mt"><span class="mf c{2}" style="width:{3:0.#}%"></span></span><span class="mv">{4}{5}</span></div>',
            $(if ($valid.Count -gt 1 -and $v -eq $best) { ' best' } else { '' }), (ConvertTo-HtmlText $Names[$i]), ($i % 6), [math]::Max(1.5, [math]::Min(100.0, $w)), (ConvertTo-HtmlText (Format-Metric $v $Fmt $Unit)), $d))
    }
    [void]$sb.Append('</div></div>')
    return $sb.ToString()
}

function Get-Short([string]$s, [int]$n) { if (-not $s) { return '' }; if ($s.Length -le $n) { return $s }; return $s.Substring(0, $n - 1).TrimEnd() + '…' }

# Systemvergleich aus der Datenbank, ohne neuen Benchmark
function New-CompareReport([string[]]$Paths) {
    $sys = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $Paths) {
        $j = Read-JsonFile $p
        if (-not $j) { Write-Host ('Nicht lesbar: {0}' -f $p); continue }
        $lw = @($j.Laufwerke | Where-Object { $_ -and [double]$_.SR -gt 0 })
        $sys.Add([pscustomobject]@{ Path = $p; Computer = [string]$j.Computer; Datum = [string]$j.Datum; Name = [string]$j.Name; Hw = $j.Hardware; System = [string]$j.System
            Werte = (ConvertTo-ValueTable $j.Werte); Messwerte = (ConvertTo-ValueTable $j.Messwerte); Messdauer = [string]$j.Messdauer; Version = [string]$j.Version; Quelle = [string]$j.Quelle
            Befunde = $j.Befunde; Laufwerke = $lw; Label = '' })
    }
    if ($sys.Count -lt 2) { Write-Host 'Für einen Vergleich werden mindestens zwei lesbare Systeme benötigt.'; return '' }
    foreach ($s in $sys) {
        $s.Label = $(if (@($sys | Where-Object { $_.Computer -eq $s.Computer }).Count -gt 1) { '{0} {1}' -f $s.Computer, ($s.Datum -replace '^\d{4}-(\d\d)-(\d\d).*$', '$2.$1.') } else { $s.Computer })
        if (-not $s.Label) { $s.Label = Get-Short $s.Name 22 }
    }
    $names = [string[]]@($sys | ForEach-Object { $_.Label })
    $ref = $script:RefDefault.Werte
    # schnellstes Laufwerk je System (nach sequentiellem Lesen)
    foreach ($s in $sys) {
        $f = $s.Laufwerke | Sort-Object { [double]$_.SR } -Descending | Select-Object -First 1
        if ($f) { foreach ($k in 'SR', 'SW', 'R1', 'R8', 'W1') { $s.Werte['LW|' + $k] = [double]$f.$k }; $s | Add-Member -NotePropertyName Fastest -NotePropertyValue ([string]$f.Laufwerk) -Force }
        else {
            foreach ($k in 'SR', 'SW', 'R1', 'R8', 'W1') { $m = @($s.Werte.Keys | Where-Object { $_ -like "DISK|*|$k" } | ForEach-Object { $s.Werte[$_] } | Measure-Object -Maximum).Maximum; if ($m) { $s.Werte['LW|' + $k] = [double]$m } }
            $s | Add-Member -NotePropertyName Fastest -NotePropertyValue '' -Force
        }
    }
    $lwDefs = @(
        @{ K = 'LW|SR'; N = 'Sequentiell lesen'; U = 'MB/s'; F = 'N0'; R = 'DISK|NVMe4|SR' }
        @{ K = 'LW|SW'; N = 'Sequentiell schreiben'; U = 'MB/s'; F = 'N0'; R = 'DISK|NVMe4|SW' }
        @{ K = 'LW|R1'; N = '4K zufällig lesen QD1'; U = 'IOPS'; F = 'N0'; R = 'DISK|NVMe4|R1' }
        @{ K = 'LW|R8'; N = '4K zufällig lesen, 8 Threads'; U = 'IOPS'; F = 'N0'; R = 'DISK|NVMe4|R8' }
        @{ K = 'LW|W1'; N = '4K zufällig schreiben'; U = 'IOPS'; F = 'N0'; R = 'DISK|NVMe4|W1' }
    )
    # Gesamtbild: geometrisches Mittel je Gruppe in % der Standardreferenz, nur über Messgrößen, die alle Systeme haben
    $groups = [ordered]@{ 'Prozessor' = @($script:MetricDefs | Where-Object { $_.K -like 'CPU|*' }); 'Arbeitsspeicher' = @($script:MetricDefs | Where-Object { $_.K -like 'RAM|*' })
        'Grafik' = @($script:MetricDefs | Where-Object { $_.K -like 'GPU|*' }); 'Laufwerke' = @($lwDefs | Where-Object { $_.K -in 'LW|SR', 'LW|SW', 'LW|R1' }) }
    $ovRows = [System.Collections.Generic.List[object]]::new()
    foreach ($gn in $groups.Keys) {
        $defs = @($groups[$gn])
        $common = @($defs | Where-Object { $d = $_; @($sys | Where-Object { $_.Werte[$d.K] -gt 0 }).Count -eq $sys.Count })
        $use = $(if ($common.Count) { $common } else { $defs })
        $vals = @(foreach ($s in $sys) {
            $r = @(foreach ($d in $use) {
                $rk = $(if ($d.R) { $d.R } else { $d.K }); $v = [double]$s.Werte[$d.K]; $rv = [double]$ref[$rk]
                if ($v -gt 0 -and $rv -gt 0) { if ($d.L) { $rv / $v * 100 } else { $v / $rv * 100 } }
            })
            Get-GeoMean $r
        })
        if (@($vals | Where-Object { $_ }).Count) { $ovRows.Add([pscustomobject]@{ N = $gn; V = $vals; Basis = (@($use | ForEach-Object { $_.N }) -join ', ') }) }
    }
    $gesamt = @(for ($i = 0; $i -lt $sys.Count; $i++) { $x = @($ovRows | ForEach-Object { $_.V[$i] } | Where-Object { $_ }); if ($x.Count -eq $ovRows.Count) { Get-GeoMean $x } else { $null } })

    $sb = New-Object System.Text.StringBuilder
    $title = 'Systemvergleich ' + (($sys | ForEach-Object { $_.Label }) -join ', ')
    [void]$sb.Append(('<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{0}</title><style>{1}</style></head><body><main>' -f (ConvertTo-HtmlText $title), (Get-ReportCss)))
    [void]$sb.Append(('<header><div><h1>Leos Minibench <span>Systemvergleich</span></h1><p class="meta">{0} Systeme aus der Vergleichsdatenbank &middot; erstellt am {1:dd.MM.yyyy HH:mm} Uhr &middot; Version {2}</p></div></header>' -f $sys.Count, (Get-Date), $ScriptVersion))

    # Systemkarten
    [void]$sb.Append('<section class="syscards">')
    for ($i = 0; $i -lt $sys.Count; $i++) {
        $s = $sys[$i]; $hw = $s.Hw
        $bf = $s.Befunde
        $dat = $s.Datum; try { $dat = [datetime]::ParseExact($s.Datum, 'yyyy-MM-dd HH:mm', $script:Inv).ToString('dd.MM.yyyy HH:mm') } catch { }
        [void]$sb.Append(('<div class="sys k{0}"><h3><i class="sw c{0}"></i>{1}</h3><p class="meta">{2}{3}</p><dl>' -f ($i % 6), (ConvertTo-HtmlText $s.Label), (ConvertTo-HtmlText $dat), $(if ($s.Messdauer -and $s.Messdauer -ne 'normal') { ' &middot; Messdauer ' + (ConvertTo-HtmlText $s.Messdauer) } else { '' })))
        foreach ($kv in @(@('Prozessor', $hw.CPU), @('RAM', $hw.RAM), @('Grafik', $hw.GPU), @('System', $s.System), @('Windows', ($hw.Betriebssystem -replace '^Microsoft\s+', '')), @('Installiert', $hw.WindowsInstalliert), @('Schnellstes LW', $s.Fastest))) {
            if ($kv[1]) { [void]$sb.Append(('<dt>{0}</dt><dd>{1}</dd>' -f $kv[0], (ConvertTo-HtmlText (Get-Short ([string]$kv[1]) 70)))) }
        }
        [void]$sb.Append('</dl>')
        if ($bf) { [void]$sb.Append(('<p class="bfc"><span class="badge crit">{0} kritisch</span> <span class="badge warn">{1} {2}</span> <span class="badge info">{3} {4}</span></p>' -f [int]$bf.Kritisch, [int]$bf.Warnungen, $(if ([int]$bf.Warnungen -eq 1) { 'Warnung' } else { 'Warnungen' }), [int]$bf.Hinweise, $(if ([int]$bf.Hinweise -eq 1) { 'Hinweis' } else { 'Hinweise' }))) }
        [void]$sb.Append('</div>')
    }
    [void]$sb.Append('</section>')

    $notes = @()
    if (@($sys | ForEach-Object { $_.Messdauer } | Select-Object -Unique).Count -gt 1) { $notes += 'Die Messdauer unterscheidet sich (kurz, normal oder unbekannt bei Importen). Kurze Messungen fallen meist einige Prozent niedriger aus.' }
    if (@($sys | Where-Object { $_.Quelle -like 'Import*' }).Count) { $notes += 'Importierte Läufe älterer Versionen enthalten nicht alle Messgrößen.' }
    if ($notes.Count) { [void]$sb.Append(('<p class="note">{0}</p>' -f (ConvertTo-HtmlText ($notes -join ' ')))) }

    if ($ovRows.Count) {
        [void]$sb.Append('<section class="box"><h2>Gesamtbild</h2>')
        [void]$sb.Append(('<p class="note">Geometrisches Mittel je Bereich in Prozent der Standardreferenz ({0}). Gezählt werden nur Messgrößen, die alle Systeme haben. Laufwerke: jeweils das schnellste Laufwerk im Vergleich zu NVMe PCIe 4.0.</p>' -f (ConvertTo-HtmlText $script:RefDefault.Name)))
        foreach ($r in $ovRows) { [void]$sb.Append((New-MetricBarsHtml -Label $r.N -Unit '%' -Fmt 'N0' -LowerBetter $false -Values $r.V -Names $names -Mode 'Best' -Hint $r.Basis)) }
        if (@($gesamt | Where-Object { $_ }).Count) { [void]$sb.Append((New-MetricBarsHtml -Label 'Gesamt' -Unit '%' -Fmt 'N0' -LowerBetter $false -Values $gesamt -Names $names -Mode 'Best' -Hint 'Mittel der Bereiche')) }
        [void]$sb.Append('</section>')
    }

    # Einzelwerte je Bereich
    $sections = [ordered]@{
        'Prozessor' = @($script:MetricDefs | Where-Object { $_.K -like 'CPU|*' })
        'Arbeitsspeicher' = @($script:MetricDefs | Where-Object { $_.K -like 'RAM|*' })
        'Grafik' = @($script:MetricDefs | Where-Object { $_.K -like 'GPU|*' })
        'Laufwerke (jeweils das schnellste)' = $lwDefs
    }
    foreach ($sn in $sections.Keys) {
        $part = New-Object System.Text.StringBuilder
        foreach ($d in $sections[$sn]) {
            $vals = @(foreach ($s in $sys) { $(if ($s.Werte[$d.K] -gt 0) { [double]$s.Werte[$d.K] } else { $null }) })
            [void]$part.Append((New-MetricBarsHtml -Label $d.N -Unit $d.U -Fmt $d.F -LowerBetter ([bool]$d.L) -Values $vals -Names $names -Mode 'Best'))
        }
        if ($part.Length) { [void]$sb.Append(('<section class="box"><h2>{0}</h2>{1}</section>' -f (ConvertTo-HtmlText $sn), $part.ToString())) }
    }

    # WinSAT, falls vorhanden
    $wsDefs = @(@('WINSAT|CPU', 'Prozessor'), @('WINSAT|RAM', 'Arbeitsspeicher'), @('WINSAT|DISK', 'Systemlaufwerk'), @('WINSAT|GFX', 'Grafik (Desktop)'))
    $wsPart = New-Object System.Text.StringBuilder
    foreach ($w in $wsDefs) {
        $vals = @(foreach ($s in $sys) { $(if ($s.Messwerte[$w[0]] -gt 0) { [double]$s.Messwerte[$w[0]] } else { $null }) })
        [void]$wsPart.Append((New-MetricBarsHtml -Label $w[1] -Unit 'von 9,9' -Fmt 'N1' -LowerBetter $false -Values $vals -Names $names -Mode 'Abs' -AbsMax 9.9))
    }
    if ($wsPart.Length) { [void]$sb.Append(('<section class="box"><h2>WinSAT-Bewertung</h2>{0}</section>' -f $wsPart.ToString())) }

    # alle gemessenen Laufwerke
    if (@($sys | Where-Object { $_.Laufwerke.Count }).Count) {
        [void]$sb.Append('<section class="box"><h2>Alle gemessenen Laufwerke</h2><div class="tw"><table class="disks"><thead><tr><th>System</th><th>Laufwerk</th><th>Klasse</th><th class="r">Lesen<br><small>MB/s</small></th><th class="r">Schreiben<br><small>MB/s</small></th><th class="r">4K QD1<br><small>IOPS</small></th><th class="r">4K 8 Thr.<br><small>IOPS</small></th><th class="r">4K schr.<br><small>IOPS</small></th></tr></thead><tbody>')
        $maxSR = [double](@($sys | ForEach-Object { $_.Laufwerke } | ForEach-Object { [double]$_.SR }) | Measure-Object -Maximum).Maximum
        for ($i = 0; $i -lt $sys.Count; $i++) {
            foreach ($d in $sys[$i].Laufwerke) {
                $n = { param($v) if ([double]$v -gt 0) { '{0:N0}' -f [double]$v } else { '' } }
                $bw = $(if ($maxSR -gt 0) { [math]::Max(2.0, [double]$d.SR / $maxSR * 100) } else { 0 })
                [void]$sb.Append([string]::Format($script:Inv, '<tr><td class="nw"><i class="sw c{0}"></i>{1}</td><td>{2}</td><td class="muted">{3}</td><td class="num r"><span class="mini"><span class="mf c{0}" style="width:{4:0.#}%"></span></span>{5}</td><td class="num r">{6}</td><td class="num r">{7}</td><td class="num r">{8}</td><td class="num r">{9}</td></tr>',
                    ($i % 6), (ConvertTo-HtmlText $sys[$i].Label), (ConvertTo-HtmlText $d.Laufwerk), (ConvertTo-HtmlText $d.Klasse), $bw, (& $n $d.SR), (& $n $d.SW), (& $n $d.R1), (& $n $d.R8), (& $n $d.W1)))
            }
        }
        [void]$sb.Append('</tbody></table></div></section>')
    }

    # Befunde je System
    $cls = @{ KRITISCH = 'crit'; WARNUNG = 'warn'; INFO = 'info' }
    [void]$sb.Append('<section class="box"><h2>Befunde der Läufe</h2>')
    for ($i = 0; $i -lt $sys.Count; $i++) {
        $s = $sys[$i]; $list = @($s.Befunde.Liste | Where-Object { $_ })
        [void]$sb.Append(('<details><summary><i class="sw c{0}"></i>{1} <span class="gref">{2} Einträge</span></summary>' -f ($i % 6), (ConvertTo-HtmlText $s.Label), $list.Count))
        if ($list.Count) {
            [void]$sb.Append('<table><tbody>')
            foreach ($l in $list) {
                $m = [regex]::Match([string]$l, '^\[(\w+)\]\s*([^:]+):\s*(.*)$')
                if ($m.Success) { $c = $cls[$m.Groups[1].Value.ToUpper()]; if (-not $c) { $c = 'info' }; [void]$sb.Append(('<tr><td><span class="badge {0}">{1}</span></td><td class="nw">{2}</td><td>{3}</td></tr>' -f $c, (ConvertTo-HtmlText $m.Groups[1].Value), (ConvertTo-HtmlText $m.Groups[2].Value), (ConvertTo-HtmlText $m.Groups[3].Value))) }
                else { [void]$sb.Append(('<tr><td colspan="3">{0}</td></tr>' -f (ConvertTo-HtmlText $l))) }
            }
            [void]$sb.Append('</tbody></table>')
        } else { [void]$sb.Append('<p class="empty">Keine Befunde gespeichert.</p>') }
        [void]$sb.Append('</details>')
    }
    [void]$sb.Append('</section>')
    [void]$sb.Append(('<footer>Leos Minibench {0}. Quellen: {1}</footer></main></body></html>' -f $ScriptVersion, (ConvertTo-HtmlText ((@($sys | ForEach-Object { Split-Path $_.Path -Leaf })) -join ', '))))

    $dir = $(if ($script:DataDir) { Join-Path $script:DataDir 'Berichte\Vergleiche' } else { Join-Path $env:TEMP 'LeosMinibench-Vergleiche' })
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    $file = Join-Path $dir ('Vergleich_{0}_{1}.html' -f (Get-SafeName ((@($sys | ForEach-Object { $_.Computer } | Select-Object -Unique) | Select-Object -First 4) -join '-')), (Get-Date -Format 'yyyyMMdd_HHmmss'))
    [IO.File]::WriteAllText($file, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))
    Write-Host ('Vergleich gespeichert: {0}' -f $file)
    return $file
}
#endregion

# Lasttest im HTML-Bericht: Drosselnachweis und Kurven für Temperatur, Takt, Leistung und Lüfter
function New-LoadChartsHtml {
    $S = @($script:LoadSeries)
    $sb = New-Object System.Text.StringBuilder
    $pts = { param($prop) @($S | Where-Object { $null -ne $_.$prop -and "$($_.$prop)" -ne '' } | ForEach-Object { [pscustomobject]@{ T = $_.T; V = [double]$_.$prop } }) }
    $th = $script:LoadThrottle
    if ($th) {
        $c = switch ($th.Status) { 'keine' { 'ok' } 'thermisch' { 'warn' } 'nicht bewertbar' { 'info' } default { $(if ($th.Stufe -eq 'WARNUNG') { 'warn' } else { 'info' }) } }
        $lab = switch ($th.Status) { 'keine' { 'Keine Drosselung' } 'thermisch' { 'Thermische Drosselung' } 'Leistungsgrenze' { 'Leistungsgrenze' } 'Firmware' { 'Begrenzung durch Firmware' } 'unklar' { 'Taktabfall ohne klaren Grund' } default { 'Nicht bewertbar' } }
        [void]$sb.Append(('<div class="thr {0}"><b>Drosselnachweis: {1}</b><br>{2}<ul>' -f $c, $lab, (ConvertTo-HtmlText $th.Befund)))
        foreach ($b in $th.Belege) { [void]$sb.Append(('<li>{0}</li>' -f (ConvertTo-HtmlText $b))) }
        [void]$sb.Append('</ul></div>')
    }
    $marks = @()
    $cpuEnd = @($S | Where-Object { $_.Cpu } | Select-Object -Last 1)
    if ($script:LoadAbort) { $marks += @{ T = $script:LoadAbort.T; Label = 'Abbruch' } }
    elseif ($cpuEnd.Count -and @($S | Where-Object { -not $_.Cpu -and $_.T -gt $cpuEnd[0].T }).Count) { $marks += @{ T = $cpuEnd[0].T; Label = 'CPU-Last Ende' } }
    if ($th -and $th.Beginn -and $th.Status -ne 'keine') { $marks += @{ T = $th.Beginn; Label = 'Takt sinkt' } }
    # Temperatur: Sensorwerte, sonst ACPI-Thermalzone (nur wenn veränderlich)
    $ser = @()
    $cpuSens = @($S | Where-Object { $null -ne $_.CpuTemp -and $_.CpuTempQ -ne 'ACPI' })
    if ($cpuSens.Count -ge 2) { $ser += @{ Name = 'CPU'; Cls = 's1'; Points = @($cpuSens | ForEach-Object { [pscustomobject]@{ T = $_.T; V = [double]$_.CpuTemp } }) } }
    elseif (@($S | Where-Object { $_.Temp } | ForEach-Object { $_.Temp } | Select-Object -Unique).Count -gt 1) { $ser += @{ Name = 'ACPI-Thermalzone (keine Kerntemperatur)'; Cls = 's1'; Points = (& $pts 'Temp') } }
    $ser += @{ Name = 'GPU'; Cls = 's2'; Points = (& $pts 'GpuTemp') }
    $ser += @{ Name = 'Datenträger'; Cls = 's3'; Points = (& $pts 'DiskTemp') }
    $refs = @()
    if ($script:LoadLimits -and $script:LoadLimits.Cpu -gt 0 -and $cpuSens.Count) { $refs += @{ V = $script:LoadLimits.Cpu; Label = ('Abbruchschwelle CPU {0:N0} °C' -f $script:LoadLimits.Cpu); Cls = 'lim' } }
    if ($script:LoadLimits -and $script:LoadLimits.TjMax -and $cpuSens.Count -and $script:LoadLimits.TjMax -ne $script:LoadLimits.Cpu) { $refs += @{ V = $script:LoadLimits.TjMax; Label = ('TjMax {0:N0} °C' -f $script:LoadLimits.TjMax); Cls = 'tj' } }
    $svg = New-MultiLineSvg $ser '°C' $refs $marks
    if ($svg) { [void]$sb.Append('<h3>Temperatur (°C)</h3>' + $svg) }
    $ser = @()
    if (@($S | ForEach-Object { $_.MHz } | Select-Object -Unique).Count -gt 1) { $ser += @{ Name = 'CPU effektiv (Windows)'; Cls = 's1'; Points = (& $pts 'MHz') } }
    $ser += @{ Name = 'CPU (Sensoren)'; Cls = 's4'; Points = (& $pts 'CpuMHz') }
    $ser += @{ Name = 'GPU'; Cls = 's2'; Points = (& $pts 'GpuMHz') }
    $svg = New-MultiLineSvg $ser 'MHz' @() $marks
    if ($svg) { [void]$sb.Append('<h3>Takt (MHz)</h3>' + $svg) }
    $svg = New-MultiLineSvg @(@{ Name = 'CPU-Paket'; Cls = 's1'; Points = (& $pts 'CpuW') }, @{ Name = 'GPU'; Cls = 's2'; Points = (& $pts 'GpuW') }) 'W' @() $marks
    if ($svg) { [void]$sb.Append('<h3>Leistung (W)</h3>' + $svg) }
    $svg = New-MultiLineSvg @(@{ Name = 'Lüfter'; Cls = 's3'; Points = (& $pts 'Fan') }) 'U/min' @() $marks
    if ($svg) { [void]$sb.Append('<h3>Lüfter (U/min)</h3>' + $svg) }
    if ($S.Count -and -not $cpuSens.Count) { [void]$sb.Append('<p class="note tight">Ohne LibreHardwareMonitor mit PawnIO-Treiber gibt es keine echte CPU-Temperatur und keine CPU-Leistung. Die Seite Sensoren holt die Werkzeuge; den Treiber installiert Leos Minibench nur nach Rückfrage und entfernt ihn nach dem Lauf.</p>') }
    return $sb.ToString()
}

function New-HtmlReport {
    param([string]$Path, $Sorted, [int]$NK, [int]$NW, [int]$NI, [datetime]$Start, [datetime]$End)
    $cls = @{ KRITISCH = 'crit'; WARNUNG = 'warn'; INFO = 'info'; OK = 'ok'; FEHLER = 'crit'; 'ÜBERSPRUNGEN' = 'skip'; REPARIERT = 'ok'; NEUSTART = 'info' }
    if ($NK) { $vc = 'crit'; $vt = 'Kritische Befunde' } elseif ($NW) { $vc = 'warn'; $vt = 'Warnungen vorhanden' } else { $vc = 'ok'; $vt = 'Keine Auffälligkeiten' }
    $modus = Get-ModeLabel
    $kiLeaf = $(if ($kiFile) { Split-Path $kiFile -Leaf } else { 'KI-Analyse.txt' })
    $css = Get-ReportCss
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
    [void]$sb.Append(('<title>Leos Minibench {0}</title><style>{1}</style></head><body><main>' -f (ConvertTo-HtmlText $env:COMPUTERNAME), $css))
    [void]$sb.Append(('<header><div><h1>Leos Minibench <span>{0}</span></h1><p class="meta">{1:dd.MM.yyyy HH:mm} bis {2:HH:mm} Uhr &middot; Dauer {3:hh\:mm\:ss} &middot; Modus {4} &middot; Risikostufe {8} &middot; Version {5}</p></div><div class="verdict {6}">{7}</div></header>' -f `
        (ConvertTo-HtmlText $env:COMPUTERNAME), $Start, $End, ($End - $Start), (ConvertTo-HtmlText $modus), $ScriptVersion, $vc, $vt, (Get-RiskLabel (Get-RunRisk))))
    [void]$sb.Append(('<section class="cards"><div class="card crit"><b>{0}</b><span>kritisch</span></div><div class="card warn"><b>{1}</b><span>Warnungen</span></div><div class="card info"><b>{2}</b><span>Hinweise</span></div></section>' -f $NK, $NW, $NI))

    if ($script:Facts.Count) {
        [void]$sb.Append('<section class="box"><h2>System</h2><dl>')
        foreach ($k in $script:Facts.Keys) { [void]$sb.Append(('<dt>{0}</dt><dd>{1}</dd>' -f (ConvertTo-HtmlText $k), ((ConvertTo-HtmlText ([string]$script:Facts[$k])) -replace "`r?`n", '<br>'))) }
        [void]$sb.Append('</dl></section>')
    }

    [void]$sb.Append('<section class="box"><h2>Befunde</h2>')
    if ($Sorted.Count) {
        [void]$sb.Append('<table><thead><tr><th>Stufe</th><th>Bereich</th><th>Befund</th></tr></thead><tbody>')
        foreach ($f in $Sorted) { [void]$sb.Append(('<tr><td><span class="badge {0}">{1}</span></td><td>{2}</td><td>{3}</td></tr>' -f $cls[$f.Stufe], $f.Stufe, (ConvertTo-HtmlText $f.Bereich), (ConvertTo-HtmlText $f.Befund))) }
        [void]$sb.Append('</tbody></table>')
    } else { [void]$sb.Append('<p class="empty">Keine Auffälligkeiten gefunden.</p>') }
    [void]$sb.Append('</section>')

    if ($script:TestResults.Count) {
        [void]$sb.Append('<section class="box"><h2>Tests</h2><table><thead><tr><th>Test</th><th>Ergebnis</th><th>Details</th></tr></thead><tbody>')
        foreach ($t in $script:TestResults) {
            $c = $cls[[string]$t.Ergebnis]; if (-not $c) { $c = 'info' }
            [void]$sb.Append(('<tr><td>{0}</td><td><span class="badge {1}">{2}</span></td><td>{3}</td></tr>' -f (ConvertTo-HtmlText $t.Test), $c, (ConvertTo-HtmlText $t.Ergebnis), (ConvertTo-HtmlText $t.Details)))
        }
        [void]$sb.Append('</tbody></table></section>')
    }

    if ($script:BenchResults.Count -or $script:BenchDisks.Count) {
        $bcls = @{ OK = 'ok'; Info = 'info'; Warnung = 'warn'; Fehler = 'crit' }
        $idxHtml = {
            param($Index, [string]$Status, [switch]$Small)
            if ($null -eq $Index -or "$Index" -eq '') { return '' }
            $c = $bcls[$Status]; if (-not $c) { $c = 'info' }
            $w = [math]::Round([math]::Min(150.0, [math]::Max(0.0, [double]$Index)) / 150.0 * 100.0, 1)
            return [string]::Format($script:Inv, '<span class="ib{3}" title="Index {2}, 100 = typisch"><span class="ibf {0}" style="width:{1}%"></span><span class="ibm"></span></span><b>{2}</b>', $c, $w, $Index, $(if ($Small) { ' s' } else { '' }))
        }
        $refDat = ''; try { if ($script:Ref.Datum) { $refDat = ' vom ' + [datetime]::ParseExact([string]$script:Ref.Datum, 'yyyy-MM-dd', $script:Inv).ToString('dd.MM.yyyy') } } catch { $refDat = ' vom ' + $script:Ref.Datum }
        $refNote = $(if ($script:Ref) { ' Referenz 100 % = {0}{1}, Laufwerke im Vergleich zur gleichen Klasse.' -f $script:Ref.Name, $refDat } else { '' })
        [void]$sb.Append('<section class="box"><div class="bar"><h2>Leistung (Benchmark)</h2><button onclick="var d=this.closest(''section'').querySelectorAll(''details''),o=!d[0].open;for(var i=0;i<d.length;i++)d[i].open=o">Alle auf- oder zuklappen</button></div>')
        [void]$sb.Append((New-BenchOverview))
        [void]$sb.Append(('<p class="note">Kacheln: Ergebnis je Bereich in Prozent der Referenz (Strich = 100 %).{0} Index 100 in den Tabellen entspricht dem typischen Wert der Hardwareklasse. Vergleich bezieht sich auf frühere Läufe auf diesem PC, grün besser, orange mindestens 10 % schlechter.</p>' -f (ConvertTo-HtmlText $refNote)))
        foreach ($gk in $script:BenchGroupOrder) {
            $g = Get-BenchGroup $gk
            if (-not $g.Anzahl) { continue }
            $gc = $bcls[$g.Status]; if (-not $gc) { $gc = 'info' }
            $open = $(if ((Get-StatusRank $g.Status) -ge 2 -or $gk -eq 'WinSAT') { ' open' } else { '' })
            [void]$sb.Append(('<details class="grp" id="bg-{6}"{0}><summary><span class="gname">{1}</span><span class="gsub">{2}</span>{3}<span class="badge {4}">{5}</span></summary>' -f $open,
                (ConvertTo-HtmlText $g.Name), (ConvertTo-HtmlText $g.Kopf), $(if ($g.Referenz) { '<span class="gref" title="im Vergleich zur Referenz">Referenz <b>' + $g.Referenz + '</b></span>' } else { '' }), $gc, (ConvertTo-HtmlText $g.Status), $gk))
            if ($gk -eq 'WinSAT') {
                [void]$sb.Append((New-WinsatSvg $g.Items $script:WinsatTotal))
                [void]$sb.Append('<p class="note tight">Windows-Leistungsbewertung auf einer Skala von 1,0 bis 9,9. Die gestrichelte Linie zeigt den Gesamtwert, er entspricht dem niedrigsten Teilwert. Die Spielegrafik-Bewertung ist seit Windows 10 fest auf 9,9 gesetzt und fehlt deshalb.</p>')
            } elseif ($gk -eq 'Laufwerke') {
                [void]$sb.Append('<div class="tw"><table class="disks"><thead><tr><th>Laufwerk</th><th>Klasse</th><th class="r">Lesen<br><small>MB/s</small></th><th class="r">Schreiben<br><small>MB/s</small></th><th class="r">4K QD1<br><small>IOPS</small></th><th class="r">4K 8 Thr.<br><small>IOPS</small></th><th class="r">4K schr.<br><small>IOPS</small></th><th>Index</th><th>Referenz</th><th>Ergebnis</th></tr></thead><tbody>')
                foreach ($d in $g.Disks) {
                    $c = $bcls[$d.Status]; if (-not $c) { $c = 'info' }
                    $n = { param($v) if ([double]$v -gt 0) { '{0:N0}' -f [double]$v } else { '' } }
                    [void]$sb.Append(('<tr title="{0}"><td>{1}</td><td class="muted">{2}</td><td class="num r">{3}</td><td class="num r">{4}</td><td class="num r">{5}</td><td class="num r">{6}</td><td class="num r">{7}</td><td class="idx">{8}</td><td class="num nw">{9}</td><td><span class="badge {10}">{11}</span></td></tr>' -f
                        (ConvertTo-HtmlText (($d.Hinweis, $d.Vergleich | Where-Object { $_ }) -join '; ')), (ConvertTo-HtmlText $d.Laufwerk), (ConvertTo-HtmlText $d.Klasse),
                        (& $n $d.SR), (& $n $d.SW), (& $n $d.R1), (& $n $d.R8), (& $n $d.W1), (& $idxHtml $d.Index $d.Status -Small), ((Get-RefBar $d.RefPct 'info' -Small) + (ConvertTo-HtmlText $d.Referenz)), $c, (ConvertTo-HtmlText $d.Status)))
                }
                [void]$sb.Append('</tbody></table></div><p class="note tight">Lesen und Schreiben sequentiell mit 1 MiB-Blöcken, 4K-Werte in Zugriffen pro Sekunde, jeweils ohne Windows-Cache. Details beim Überfahren einer Zeile.</p>')
            } else {
                [void]$sb.Append('<div class="tw"><table><thead><tr><th>Messung</th><th class="r">Wert</th><th>Index</th><th>Referenz</th><th>Vergleich</th><th>Ergebnis</th></tr></thead><tbody>')
                foreach ($b in $g.Items) {
                    $c = $bcls[[string]$b.Status]; if (-not $c) { $c = 'info' }
                    [void]$sb.Append(('<tr><td>{0}{1}</td><td class="num r">{2}</td><td class="idx">{3}</td><td class="num nw">{4}</td><td class="nw">{5}</td><td><span class="badge {6}">{7}</span></td></tr>' -f
                        (ConvertTo-HtmlText $b.Messung), $(if ($b.Hinweis) { '<small class="hint">' + (ConvertTo-HtmlText $b.Hinweis) + '</small>' } else { '' }), (ConvertTo-HtmlText $b.Anzeige),
                        (& $idxHtml $b.Index $b.Status), ((Get-RefBar $b.RefPct 'info' -Small) + (ConvertTo-HtmlText $b.Referenz)), (Get-DeltaHtml $b.Vergleich), $c, (ConvertTo-HtmlText $b.Status)))
                }
                [void]$sb.Append('</tbody></table></div>')
            }
            [void]$sb.Append('</details>')
        }
        [void]$sb.Append('</section>')
    }
    if ($script:CmpRows.Count) {
        $cn = [string[]](@('Dieser PC') + @($script:CmpSystems | ForEach-Object { $_.Computer }))
        [void]$sb.Append('<section class="box"><h2>Vergleich mit bereits geprüften Systemen</h2><p class="note">')
        for ($k = 0; $k -lt $cn.Count; $k++) { [void]$sb.Append(('<i class="sw c{0}"></i>{1}{2}&nbsp;&nbsp; ' -f $k, (ConvertTo-HtmlText $cn[$k]), $(if ($k) { ' (' + (ConvertTo-HtmlText $script:CmpSystems[$k - 1].Datum) + ')' } else { '' }))) }
        [void]$sb.Append('<br>Längerer Balken = besser. Prozent: Abstand des anderen Systems zu diesem PC, grün = das andere System ist besser. Platz: Rang dieses PCs unter allen Systemen der Datenbank.</p>')
        $lastG = ''
        foreach ($r in $script:CmpRows) {
            $gname = $script:GroupOfKey[($r.Key -split '\|')[0]]
            if ($gname -ne $lastG) { [void]$sb.Append(('<div class="mgh">{0}</div>' -f (ConvertTo-HtmlText $gname))); $lastG = $gname }
            [void]$sb.Append((New-MetricBarsHtml -Label $r.Messung -Unit $r.Einheit -Fmt $r.Format -LowerBetter $r.LowerBetter -Values (@($r.Dieses) + @($r.Werte)) -Names $cn -Mode 'Base' -Extra $r.Rang))
        }
        [void]$sb.Append('</section>')
    }
    if ($script:LoadSeries.Count -ge 2 -or $script:LoadParts.Count) {
        [void]$sb.Append('<section class="box"><h2>Lasttest</h2>')
        [void]$sb.Append(('<p class="note">{0}</p>' -f (ConvertTo-HtmlText $script:LoadSummary)))
        if ($script:LoadParts.Count) {
            [void]$sb.Append('<table><thead><tr><th>Komponente</th><th>Dauer</th><th>Ergebnis</th><th>Details</th></tr></thead><tbody>')
            foreach ($p in $script:LoadParts) { $c = $cls[[string]$p.Ergebnis]; if (-not $c) { $c = 'info' }; [void]$sb.Append(('<tr><td>{0}</td><td class="nw">{1}</td><td><span class="badge {2}">{3}</span></td><td>{4}</td></tr>' -f (ConvertTo-HtmlText $p.Komponente), $p.Dauer, $c, (ConvertTo-HtmlText $p.Ergebnis), (ConvertTo-HtmlText $p.Details))) }
            [void]$sb.Append('</tbody></table>')
        }
        [void]$sb.Append((New-LoadChartsHtml))
        if (@($script:LoadSeries | Where-Object { $_.DiskMBs -gt 0 }).Count -gt 1) {
            $svg3 = New-LineSvg ($script:LoadSeries | Where-Object { $null -ne $_.DiskMBs } | ForEach-Object { [pscustomobject]@{ T = $_.T; V = $_.DiskMBs } }) 'MB/s'
            if ($svg3) { [void]$sb.Append('<h3>Datenträger-Durchsatz (MB/s)</h3>' + $svg3) }
        }
        [void]$sb.Append('</section>')
    }

    $text = $script:Report.ToString()
    $ms = [regex]::Matches($text, '(?m)^={100}\r?\n  (.+?)\r?\n={100}\r?$')
    if ($ms.Count) {
        [void]$sb.Append('<section class="box"><div class="bar"><h2>Details</h2><button onclick="var d=this.closest(''section'').querySelectorAll(''details''),o=!d[0].open;for(var i=0;i<d.length;i++)d[i].open=o">Alle auf- oder zuklappen</button></div>')
        for ($i = 0; $i -lt $ms.Count; $i++) {
            $bs = $ms[$i].Index + $ms[$i].Length
            $be = $(if ($i + 1 -lt $ms.Count) { $ms[$i + 1].Index } else { $text.Length })
            $body = $text.Substring($bs, $be - $bs).Trim("`r", "`n")
            [void]$sb.Append(('<details><summary>{0}</summary><pre>{1}</pre></details>' -f (ConvertTo-HtmlText $ms[$i].Groups[1].Value.Trim()), (ConvertTo-HtmlText $body)))
        }
        [void]$sb.Append('</section>')
    }

    if ($script:Timings.Count) {
        [void]$sb.Append('<section class="box"><h2>Zeitbedarf</h2><table><thead><tr><th>Abschnitt</th><th>Dauer</th></tr></thead><tbody>')
        foreach ($t in $script:Timings) { [void]$sb.Append(('<tr><td>{0}</td><td>{1}</td></tr>' -f (ConvertTo-HtmlText $t.Abschnitt), $t.Dauer)) }
        [void]$sb.Append('</tbody></table></section>')
    }
    [void]$sb.Append(('<footer>Ausgabeordner: {0} &middot; Protokolle und Rohdaten liegen in Anhang.zip. Für eine erweiterte Auswertung die Datei {1} in ein KI-Modell hochladen: Sie enthält Auftrag, Bericht und Rohdaten.{2}</footer></main></body></html>' -f (ConvertTo-HtmlText $OutputDir), (ConvertTo-HtmlText $kiLeaf), $(if ($script:DbSaved) { ' &middot; Datenbankeintrag: ' + (ConvertTo-HtmlText $script:DbSaved) } else { '' })))
    [IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))
}

# ---------- Checkpoints: Protokoll, das auch einen harten Absturz übersteht ----------
$script:CpLog     = Join-Path $script:CpDir 'checkpoint.log'
$script:CpFlag    = Join-Path $script:CpDir 'laufend.json'
$script:CpStream  = $null
$script:CpLastHb  = [datetime]::MinValue
$script:CpCurrent = ''

function Write-Durable([string]$Path, [string]$Text) {
    $enc = New-Object Text.UTF8Encoding($true)
    $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read, 65536, [IO.FileOptions]::WriteThrough)
    try { $pre = $enc.GetPreamble(); $fs.Write($pre, 0, $pre.Length); $b = $enc.GetBytes($Text); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
    finally { $fs.Close() }
}

function Write-Checkpoint([string]$Kind, [string]$Text) {
    if (-not $script:CpStream) { return }
    $line = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:yyyy-MM-dd HH:mm:ss} | {1,-7} | {2}', (Get-Date), $Kind, $Text)
    $b = [Text.Encoding]::UTF8.GetBytes($line + "`r`n")
    try { $script:CpStream.Write($b, 0, $b.Length); $script:CpStream.Flush($true) } catch { }
}

function Write-Heartbeat([string]$Text) {
    if (-not $script:CpStream) { return }
    $now = Get-Date
    if (($now - $script:CpLastHb).TotalSeconds -lt 5) { return }
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
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        Write-Checkpoint 'SYSTEM' ('Letzter Systemstart {0}, RAM frei {1:N1} GB' -f $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture), ($os.FreePhysicalMemory / 1MB))
    } catch { $script:CpStream = $null }
}

function Close-Checkpoint([switch]$RemoveFlag) {
    try { if ($script:CpStream) { $script:CpStream.Close() } } catch { }
    $script:CpStream = $null
    if ($RemoveFlag) { Remove-Item $script:CpFlag -Force -ErrorAction SilentlyContinue }
}

function Save-Partial {
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
    if ($m.ContainsKey([int]$Code)) { return $m[[int]$Code] }
    return '(Stoppcode im Internet nachschlagen)'
}

function Test-MemoryBugcheck([int64]$Code) { return ([int]$Code -in 0x0A, 0x19, 0x1A, 0x4E, 0x50, 0x109, 0x12B, 0x139) }


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
        '^Lasttest'                       { return 'Last:alle' }
        'Benchmark: Prozessor'            { return 'Bench:CPU' }
        'Benchmark: Arbeitsspeicher'      { return 'Bench:RAM' }
        'Benchmark: Grafik'               { return 'Bench:GPU' }
        'Benchmark: Datentr'              { return 'Bench:Disk' }
        'Benchmark: WinSAT'               { return 'Bench:WinSAT' }
        'Arbeitsspeicher \(Mustertest\)'  { return 'Opt:RamTest' }
        'CPU-Stabilit'                    { return 'Opt:CpuTest' }
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
    $boot = $(if ($bootEv) { $bootEv.TimeCreated } else { (Get-CimInstance Win32_OperatingSystem).LastBootUpTime })
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
            Disable-Step $sk
            Add-Line ('  Beim aktuellen Lauf übersprungen: {0}' -f $stepName)
            Add-Finding INFO 'Absturz' ('Der Abschnitt "{0}" wird in diesem Lauf ausgelassen, weil der letzte Lauf dabei abgestürzt ist.' -f $stepName)
        }
    }
}

#endregion

#region ---------- C#-Testroutinen (RAM, CPU, Energiesparen) ----------
if ($FullLanguage -and -not $ImportOrdner -and -not $Vergleich -and -not $Rueckgaengig -and -not $SensorLive -and -not $SensorWerkzeugeHolen -and -not $SensorAufraeumen -and -not ('DiagDiskStress' -as [type])) {
    $csCode = @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using Microsoft.Win32.SafeHandles;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public static class DiagPower {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
}

public static class DiagSys {
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMSTAT {
        public uint dwLength; public uint dwMemoryLoad;
        public ulong ullTotalPhys; public ulong ullAvailPhys; public ulong ullTotalPageFile; public ulong ullAvailPageFile;
        public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GlobalMemoryStatusEx(ref MEMSTAT m);
    public static uint MemoryLoad() {
        MEMSTAT m = new MEMSTAT();
        m.dwLength = (uint)Marshal.SizeOf(typeof(MEMSTAT));
        if (!GlobalMemoryStatusEx(ref m)) return 0;
        return m.dwMemoryLoad;
    }
}

public static class DiagRam {
    public static volatile int Percent;
    public static volatile string Phase = "";
    public static volatile bool Stop;
    public static long Errors;
    public static long BytesTested;

    public static Task<string> RunAsync(long targetBytes, int passes) {
        return Task.Factory.StartNew<string>(delegate() { return Run(targetBytes, passes); }, TaskCreationOptions.LongRunning);
    }

    static ulong Next(ref ulong s) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }

    static ulong Expected(int t, ulong addr, ref ulong s) {
        switch (t) {
            case 0: return 0UL;
            case 1: return 0xFFFFFFFFFFFFFFFFUL;
            case 2: return 0xAAAAAAAAAAAAAAAAUL;
            case 3: return 0x5555555555555555UL;
            case 4: return addr;
            case 5: return ~addr;
            default: return Next(ref s);
        }
    }

    public static string Run(long targetBytes, int passes) {
        Percent = 0; Errors = 0; BytesTested = 0; Phase = "Speicher wird reserviert";
        const int blockElems = 32 * 1024 * 1024;
        long blockBytes = (long)blockElems * 8L;
        List<ulong[]> blocks = new List<ulong[]>();
        List<string> details = new List<string>();
        DateTime start = DateTime.Now;
        try {
            while (BytesTested + blockBytes <= targetBytes) {
                blocks.Add(new ulong[blockElems]);
                BytesTested += blockBytes;
            }
        } catch (OutOfMemoryException) { }
        if (blocks.Count == 0) return "Es konnte kein Speicherblock reserviert werden.";
        string[] names = new string[] { "Nullen", "Einsen", "Schachbrett 0xAA", "Schachbrett 0x55", "Adresse in Adresse", "Adresse invertiert", "Zufallsmuster" };
        int total = passes * names.Length; int done = 0;
        for (int p = 1; p <= passes && !Stop; p++) {
            for (int t = 0; t < names.Length && !Stop; t++) {
                Phase = "Durchlauf " + p + "/" + passes + ": " + names[t];
                int test = t; int pass = p; string phase = Phase;
                Parallel.For(0, blocks.Count, delegate(int bi) {
                    if (Stop) return;
                    ulong[] b = blocks[bi];
                    ulong baseAddr = (ulong)bi * (ulong)blockElems;
                    ulong seed = (((ulong)pass * 0x9E3779B97F4A7C15UL) ^ ((ulong)(bi + 1) * 0xBF58476D1CE4E5B9UL)) | 1UL;
                    ulong s = seed;
                    for (int i = 0; i < b.Length; i++) b[i] = Expected(test, baseAddr + (ulong)i, ref s);
                    s = seed;
                    for (int i = 0; i < b.Length; i++) {
                        ulong e = Expected(test, baseAddr + (ulong)i, ref s);
                        ulong v = b[i];
                        if (v != e) {
                            long n = Interlocked.Increment(ref Errors);
                            if (n <= 25) {
                                lock (details) {
                                    details.Add(String.Format("{0}, Block {1}, Index {2}: erwartet 0x{3:X16}, gelesen 0x{4:X16}", phase, bi, i, e, v));
                                }
                            }
                        }
                    }
                });
                done++; Percent = done * 100 / total;
            }
        }
        TimeSpan dur = DateTime.Now - start;
        int blockCount = blocks.Count;
        blocks.Clear(); blocks = null;
        GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
        StringBuilder sb = new StringBuilder();
        sb.AppendLine(String.Format("Getesteter Speicher : {0:N0} MB ({1} Blöcke à 256 MB)", BytesTested / 1048576L, blockCount));
        sb.AppendLine(String.Format("Umfang             : {0} Durchläufe x {1} Muster, jeweils schreiben und prüfen", passes, names.Length));
        sb.AppendLine(String.Format("Dauer              : {0:hh\\:mm\\:ss}", dur));
        sb.AppendLine(String.Format("Fehler             : {0}", Interlocked.Read(ref Errors)));
        foreach (string d in details) sb.AppendLine("  " + d);
        Phase = "fertig";
        return sb.ToString();
    }
}

public static class DiagCpu {
    public static volatile bool Stop;
    public static long Iterations;
    public static long Errors;
    static ulong[] reference;

    public static ulong Work(ulong seed) {
        double x = (double)(seed % 1000UL) + 1.5;
        ulong h = seed ^ 0xCBF29CE484222325UL;
        for (int i = 1; i <= 1500000; i++) {
            x = Math.Sqrt(Math.Abs(x * 1.0000001 + i)) * 1.0001 + Math.Sin(x);
            h ^= (ulong)BitConverter.DoubleToInt64Bits(x);
            h *= 0x100000001B3UL;
            h = (h << 7) | (h >> 57);
        }
        return h;
    }

    public static Task RunAsync(int seconds, int threads) {
        Iterations = 0; Errors = 0;
        reference = new ulong[16];
        for (int i = 0; i < 16; i++) reference[i] = Work((ulong)(i + 1));
        DateTime end = DateTime.UtcNow.AddSeconds(seconds);
        Task[] tasks = new Task[threads];
        for (int t = 0; t < threads; t++) {
            int tid = t;
            tasks[t] = Task.Factory.StartNew(delegate() {
                Thread.CurrentThread.Priority = ThreadPriority.BelowNormal;
                int k = tid % 16;
                while (!Stop && DateTime.UtcNow < end) {
                    if (Work((ulong)(k + 1)) != reference[k]) Interlocked.Increment(ref Errors);
                    Interlocked.Increment(ref Iterations);
                    k = (k + 1) % 16;
                }
            }, TaskCreationOptions.LongRunning);
        }
        return Task.Factory.ContinueWhenAll(tasks, delegate(Task[] ts) { });
    }
}

public static class DiagBench {
    public static volatile string Phase = "";
    public static volatile int Percent;

    static ulong Kernel(ulong s) {
        double x = (double)(s % 97UL) + 1.25; ulong h = s | 1UL;
        for (int i = 0; i < 20000; i++) {
            h ^= h << 13; h ^= h >> 7; h ^= h << 17;
            h = h * 0x9E3779B97F4A7C15UL + (ulong)i;
            x = x * 0.9999997 + Math.Sqrt(x + (double)(h & 1023UL));
            if ((h & 7UL) == 3UL) x = x * 0.5 + 1.0;
        }
        return h ^ (ulong)BitConverter.DoubleToInt64Bits(x);
    }

    public static ulong Sink;

    public static Task<double> CpuAsync(int threads, int millis) { return Task.Factory.StartNew<double>(delegate() { return CpuUnitsPerSec(threads, millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> MemReadAsync(int threads, long bytes, int millis) { return Task.Factory.StartNew<double>(delegate() { return MemReadGBs(threads, bytes, millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> MemWriteAsync(int threads, long bytes, int millis) { return Task.Factory.StartNew<double>(delegate() { return MemWriteGBs(threads, bytes, millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> AesAsync(int millis) { return Task.Factory.StartNew<double>(delegate() { return AesMBs(millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> ShaAsync(int millis) { return Task.Factory.StartNew<double>(delegate() { return ShaMBs(millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> DeflateAsync(int threads, int millis) { return Task.Factory.StartNew<double>(delegate() { return DeflateMBs(threads, millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> MemCopyAsync(int threads, long bytes, int millis) { return Task.Factory.StartNew<double>(delegate() { return MemCopyGBs(threads, bytes, millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> LatencyAsync(long bytes, int millis) { return Task.Factory.StartNew<double>(delegate() { return MemLatencyNs(bytes, millis); }, TaskCreationOptions.LongRunning); }

    // Rechenwerk: Einheiten pro Sekunde über alle Threads
    public static double CpuUnitsPerSec(int threads, int millis) {
        long total = 0;
        Thread[] ts = new Thread[threads];
        Stopwatch wall = Stopwatch.StartNew();
        for (int t = 0; t < threads; t++) {
            int tid = t;
            ts[t] = new Thread(delegate() {
                Stopwatch sw = Stopwatch.StartNew(); long n = 0; ulong acc = 0; ulong seed = (ulong)(tid * 7919 + 1);
                while (sw.ElapsedMilliseconds < millis) { acc ^= Kernel(seed + (ulong)n); n++; }
                Interlocked.Add(ref total, n); Sink ^= acc;
            });
            ts[t].IsBackground = true; ts[t].Start();
        }
        foreach (Thread th in ts) th.Join();
        wall.Stop();
        return total / wall.Elapsed.TotalSeconds;
    }

    // Speicherbandbreite Lesen in GB/s (10^9)
    public static double MemReadGBs(int threads, long bytes, int millis) {
        int per = (int)Math.Min(int.MaxValue / 8, bytes / 8 / threads);
        per -= per % 8;
        ulong[][] arr = new ulong[threads][];
        for (int t = 0; t < threads; t++) { arr[t] = new ulong[per]; for (int i = 0; i < per; i += 512) arr[t][i] = (ulong)i; }
        long totalBytes = 0;
        Thread[] ts = new Thread[threads];
        using (Barrier bar = new Barrier(threads + 1)) {
            for (int t = 0; t < threads; t++) {
                int tid = t;
                ts[t] = new Thread(delegate() {
                    ulong[] a = arr[tid]; ulong s0 = 0, s1 = 0, s2 = 0, s3 = 0; long passes = 0;
                    bar.SignalAndWait();
                    Stopwatch sw = Stopwatch.StartNew();
                    while (sw.ElapsedMilliseconds < millis) {
                        for (int i = 0; i < a.Length - 3; i += 4) { s0 += a[i]; s1 += a[i + 1]; s2 += a[i + 2]; s3 += a[i + 3]; }
                        passes++;
                    }
                    Interlocked.Add(ref totalBytes, passes * (long)a.Length * 8L);
                    Sink ^= s0 ^ s1 ^ s2 ^ s3;
                });
                ts[t].IsBackground = true; ts[t].Start();
            }
            bar.SignalAndWait();
            Stopwatch wall = Stopwatch.StartNew();
            foreach (Thread th in ts) th.Join();
            wall.Stop();
            return totalBytes / wall.Elapsed.TotalSeconds / 1e9;
        }
    }

    // Speicherbandbreite Schreiben in GB/s
    public static double MemWriteGBs(int threads, long bytes, int millis) {
        int per = (int)Math.Min(int.MaxValue / 8, bytes / 8 / threads);
        ulong[][] arr = new ulong[threads][];
        for (int t = 0; t < threads; t++) { arr[t] = new ulong[per]; for (int i = 0; i < per; i += 512) arr[t][i] = 1UL; }
        long totalBytes = 0;
        Thread[] ts = new Thread[threads];
        using (Barrier bar = new Barrier(threads + 1)) {
            for (int t = 0; t < threads; t++) {
                int tid = t;
                ts[t] = new Thread(delegate() {
                    ulong[] a = arr[tid]; long passes = 0; ulong v = 1;
                    bar.SignalAndWait();
                    Stopwatch sw = Stopwatch.StartNew();
                    while (sw.ElapsedMilliseconds < millis) { for (int i = 0; i < a.Length; i++) a[i] = v; v++; passes++; }
                    Interlocked.Add(ref totalBytes, passes * (long)a.Length * 8L);
                });
                ts[t].IsBackground = true; ts[t].Start();
            }
            bar.SignalAndWait();
            Stopwatch wall = Stopwatch.StartNew();
            foreach (Thread th in ts) th.Join();
            wall.Stop();
            return totalBytes / wall.Elapsed.TotalSeconds / 1e9;
        }
    }

    // AES-256-CBC verschlüsseln, ein Thread (nutzt AES-NI über die Windows-Kryptografie)
    // Kryptografie-Klassen per Reflexion laden, damit weder System.Core referenziert noch veraltete Typen genutzt werden
    static object CreateCrypto(string[] typeNames) {
        foreach (string n in typeNames) {
            try {
                Type t = Type.GetType(n, false);
                if (t == null) continue;
                System.Reflection.MethodInfo mi = t.GetMethod("Create", Type.EmptyTypes);
                object o = (mi != null && mi.IsStatic && t.IsAbstract) ? mi.Invoke(null, null) : Activator.CreateInstance(t);
                if (o != null) return o;
            } catch { }
        }
        return null;
    }

    public static double AesMBs(int millis) {
        SymmetricAlgorithm aes = CreateCrypto(new string[] {
            "System.Security.Cryptography.Aes, System.Core, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089",
            "System.Security.Cryptography.Aes, System.Security.Cryptography",
            "System.Security.Cryptography.Aes, System.Security.Cryptography.Algorithms" }) as SymmetricAlgorithm;
        if (aes == null) return 0;
        byte[] data = new byte[1 << 20]; new Random(1).NextBytes(data); byte[] outb = new byte[data.Length];
        using (aes) {
            aes.KeySize = 256; aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.None; aes.GenerateKey(); aes.GenerateIV();
            using (ICryptoTransform enc = aes.CreateEncryptor()) {
                long bytes = 0; Stopwatch sw = Stopwatch.StartNew();
                while (sw.ElapsedMilliseconds < millis) { enc.TransformBlock(data, 0, data.Length, outb, 0); bytes += data.Length; }
                sw.Stop(); return bytes / sw.Elapsed.TotalSeconds / 1e6;
            }
        }
    }

    // SHA-256 hashen, ein Thread (SHA256Cng nutzt SHA-Befehlssatzerweiterungen, falls vorhanden)
    public static double ShaMBs(int millis) {
        byte[] data = new byte[1 << 20]; new Random(2).NextBytes(data);
        HashAlgorithm h = CreateCrypto(new string[] {
            "System.Security.Cryptography.SHA256Cng, System.Core, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089",
            "System.Security.Cryptography.SHA256, System.Security.Cryptography",
            "System.Security.Cryptography.SHA256, System.Security.Cryptography.Algorithms" }) as HashAlgorithm;
        if (h == null) h = SHA256.Create();
        using (h) {
            long bytes = 0; Stopwatch sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < millis) { h.TransformBlock(data, 0, data.Length, null, 0); bytes += data.Length; }
            h.TransformFinalBlock(data, 0, 0);
            sw.Stop(); return bytes / sw.Elapsed.TotalSeconds / 1e6;
        }
    }

    static byte[] TextData(int size, int seed) {
        string[] words = { "Diagnose", "Speicher", "Prozessor", "Laufwerk", "Grafik", "Bericht", "Leistung", "Windows", "Netzwerk", "Treiber", "und", "der", "die", "das", "mit", "0123456789" };
        Random r = new Random(seed); StringBuilder sb = new StringBuilder(size + 32);
        while (sb.Length < size) { sb.Append(words[r.Next(words.Length)]); sb.Append(r.Next(10) == 0 ? '\n' : ' '); if (r.Next(8) == 0) sb.Append(r.Next(100000)); }
        byte[] b = Encoding.UTF8.GetBytes(sb.ToString()); Array.Resize(ref b, size); return b;
    }

    // Deflate-Kompression auf allen Threads, Durchsatz der Eingangsdaten
    public static double DeflateMBs(int threads, int millis) {
        byte[] data = TextData(4 << 20, 3);
        long total = 0;
        Thread[] ts = new Thread[threads];
        Stopwatch wall = Stopwatch.StartNew();
        for (int t = 0; t < threads; t++) {
            ts[t] = new Thread(delegate() {
                long n = 0; Stopwatch sw = Stopwatch.StartNew();
                while (sw.ElapsedMilliseconds < millis) {
                    using (MemoryStream ms = new MemoryStream(data.Length / 2))
                    using (DeflateStream ds = new DeflateStream(ms, CompressionLevel.Optimal, true)) { ds.Write(data, 0, data.Length); }
                    n += data.Length;
                }
                Interlocked.Add(ref total, n);
            });
            ts[t].IsBackground = true; ts[t].Start();
        }
        foreach (Thread th in ts) th.Join();
        wall.Stop();
        return total / wall.Elapsed.TotalSeconds / 1e6;
    }

    // Speicher kopieren (memcpy) auf allen Threads, GB/s kopierte Daten
    public static double MemCopyGBs(int threads, long bytes, int millis) {
        int per = (int)Math.Min(int.MaxValue / 2, bytes / 2 / threads);
        byte[][] src = new byte[threads][]; byte[][] dst = new byte[threads][];
        for (int t = 0; t < threads; t++) { src[t] = new byte[per]; dst[t] = new byte[per]; for (int i = 0; i < per; i += 4096) { src[t][i] = 1; dst[t][i] = 1; } }
        long totalBytes = 0;
        Thread[] ts = new Thread[threads];
        using (Barrier bar = new Barrier(threads + 1)) {
            for (int t = 0; t < threads; t++) {
                int tid = t;
                ts[t] = new Thread(delegate() {
                    long passes = 0; bar.SignalAndWait(); Stopwatch sw = Stopwatch.StartNew();
                    while (sw.ElapsedMilliseconds < millis) { Buffer.BlockCopy(src[tid], 0, dst[tid], 0, per); passes++; }
                    Interlocked.Add(ref totalBytes, passes * (long)per);
                });
                ts[t].IsBackground = true; ts[t].Start();
            }
            bar.SignalAndWait();
            Stopwatch wall = Stopwatch.StartNew();
            foreach (Thread th in ts) th.Join();
            wall.Stop();
            return totalBytes / wall.Elapsed.TotalSeconds / 1e9;
        }
    }

    // Speicherlatenz in ns (zufällige Zeigerverfolgung über Cachezeilen)
    public static double MemLatencyNs(long bytes, int millis) {
        int nodes = (int)Math.Min(int.MaxValue / 8, bytes / 64);
        int[] next = new int[nodes * 16];
        int[] perm = new int[nodes];
        for (int i = 0; i < nodes; i++) perm[i] = i;
        Random rnd = new Random(12345);
        for (int i = nodes - 1; i > 0; i--) { int j = rnd.Next(i); int tmp = perm[i]; perm[i] = perm[j]; perm[j] = tmp; }
        for (int i = 0; i < nodes; i++) next[perm[i] * 16] = perm[(i + 1) % nodes] * 16;
        int p = 0; long steps = 0;
        Stopwatch sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < millis) { for (int k = 0; k < 100000; k++) p = next[p]; steps += 100000; }
        sw.Stop();
        Sink ^= (ulong)p;
        return sw.Elapsed.TotalMilliseconds * 1e6 / steps;
    }
}

public class DiskResult {
    public double SeqReadMBs, SeqWriteMBs, Rnd4kQ1Iops, Rnd4kT8Iops, Rnd4kWriteQ1Iops;
    public long TestBytes;
    public string Error = "";
}

public static class DiagDisk {
    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000, SHARE_RW = 3;
    const uint CREATE_ALWAYS = 2, OPEN_EXISTING = 3, NO_BUFFERING = 0x20000000, ATTR_TEMPORARY = 0x100;
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool WriteFile(SafeFileHandle h, IntPtr buf, uint n, out uint done, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadFile(SafeFileHandle h, IntPtr buf, uint n, out uint done, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetFilePointerEx(SafeFileHandle h, long dist, out long np, uint method);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool FlushFileBuffers(SafeFileHandle h);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr VirtualAlloc(IntPtr a, UIntPtr size, uint type, uint prot);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool VirtualFree(IntPtr a, UIntPtr size, uint type);

    public static volatile string Phase = "";
    public static volatile int Percent;

    static SafeFileHandle Open(string path, bool write, bool create)
    {
        SafeFileHandle h = CreateFileW(path, write ? (GENERIC_READ | GENERIC_WRITE) : GENERIC_READ, SHARE_RW, IntPtr.Zero,
            create ? CREATE_ALWAYS : OPEN_EXISTING, NO_BUFFERING | ATTR_TEMPORARY, IntPtr.Zero);
        if (h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
        return h;
    }
    static IntPtr Alloc(int bytes, bool random)
    {
        IntPtr p = VirtualAlloc(IntPtr.Zero, (UIntPtr)(uint)bytes, 0x3000, 0x04);
        if (p == IntPtr.Zero) throw new OutOfMemoryException();
        if (random) { byte[] b = new byte[bytes]; new Random(4711).NextBytes(b); Marshal.Copy(b, 0, p, bytes); }
        return p;
    }
    static void Free(IntPtr p) { if (p != IntPtr.Zero) VirtualFree(p, UIntPtr.Zero, 0x8000); }
    static void Seek(SafeFileHandle h, long pos) { long np; if (!SetFilePointerEx(h, pos, out np, 0)) throw new Win32Exception(Marshal.GetLastWin32Error()); }

    public static Task<DiskResult> RunAsync(string path, long sizeBytes, int phaseMillis)
    {
        return Task.Factory.StartNew<DiskResult>(delegate() { return Run(path, sizeBytes, phaseMillis); }, TaskCreationOptions.LongRunning);
    }

    public static DiskResult Run(string path, long sizeBytes, int phaseMillis)
    {
        DiskResult r = new DiskResult();
        const int block = 16 * 1024 * 1024;
        const int rblock = 8 * 1024 * 1024;
        sizeBytes -= sizeBytes % block;
        if (sizeBytes < 4L * block) sizeBytes = 4L * block;
        IntPtr buf = IntPtr.Zero;
        SafeFileHandle writer = null;
        try
        {
            buf = Alloc(block, true);
            // 1) Sequentiell schreiben (Handle bleibt offen, damit kein Virenscan beim Schließen dazwischenfunkt)
            Phase = "Sequentiell schreiben"; Percent = 0;
            writer = Open(path, true, true);
            long written = 0; uint done;
            Stopwatch sw = Stopwatch.StartNew();
            while (written < sizeBytes && sw.ElapsedMilliseconds < phaseMillis * 2)
            {
                if (!WriteFile(writer, buf, (uint)block, out done, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
                written += done; Percent = (int)(written * 25 / sizeBytes);
            }
            FlushFileBuffers(writer); sw.Stop();
            r.SeqWriteMBs = written / sw.Elapsed.TotalSeconds / 1e6;
            r.TestBytes = written;
            long chunks = written / rblock;
            long blocks4k = written / 4096;

            // 2) Sequentiell lesen, 4 Threads im Wechsel (entspricht grob Warteschlangentiefe 4)
            Phase = "Sequentiell lesen"; Percent = 25;
            r.SeqReadMBs = RunThreads(4, phaseMillis, delegate(int tid, Stopwatch w, ref long ops) {
                SafeFileHandle h = Open(path, false, false); IntPtr b = Alloc(rblock, false);
                try { long c = tid; uint d; while (w.ElapsedMilliseconds < phaseMillis) { Seek(h, (c % chunks) * rblock); if (!ReadFile(h, b, (uint)rblock, out d, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error()); ops += d; c += 4; } }
                finally { Free(b); h.Dispose(); }
            }) / 1e6;

            // 3) Zufällig 4K lesen, ein Thread, eine Anfrage (QD1)
            Phase = "Zufällig 4K lesen (QD1)"; Percent = 40;
            r.Rnd4kQ1Iops = RunThreads(1, phaseMillis, delegate(int tid, Stopwatch w, ref long ops) { Random4k(path, blocks4k, 17, w, phaseMillis, ref ops); });

            // 4) Zufällig 4K lesen, 8 Threads
            Phase = "Zufällig 4K lesen (8 Threads)"; Percent = 60;
            r.Rnd4kT8Iops = RunThreads(8, phaseMillis, delegate(int tid, Stopwatch w, ref long ops) { Random4k(path, blocks4k, 100 + tid, w, phaseMillis, ref ops); });

            // 5) Zufällig 4K schreiben, ein Thread (QD1)
            Phase = "Zufällig 4K schreiben (QD1)"; Percent = 80;
            r.Rnd4kWriteQ1Iops = RunThreads(1, phaseMillis, delegate(int tid, Stopwatch w, ref long ops) {
                SafeFileHandle h = Open(path, true, false); IntPtr b = Alloc(4096, true);
                try {
                    Random rnd = new Random(77); uint d;
                    while (w.ElapsedMilliseconds < phaseMillis) {
                        long blk = (long)(rnd.NextDouble() * (blocks4k - 1));
                        Seek(h, blk * 4096);
                        if (!WriteFile(h, b, 4096, out d, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
                        ops++;
                    }
                    FlushFileBuffers(h);
                }
                finally { Free(b); h.Dispose(); }
            });
            Percent = 100; Phase = "fertig";
        }
        catch (Exception ex) { r.Error = ex.Message; }
        finally
        {
            Free(buf);
            if (writer != null) writer.Dispose();
            try { File.Delete(path); } catch { }
        }
        return r;
    }

    delegate void Worker(int tid, Stopwatch w, ref long ops);

    static double RunThreads(int threads, int millis, Worker work)
    {
        long total = 0; string err = null;
        System.Threading.Thread[] ts = new System.Threading.Thread[threads];
        Stopwatch wall = Stopwatch.StartNew();
        for (int t = 0; t < threads; t++)
        {
            int tid = t;
            ts[t] = new System.Threading.Thread(delegate() {
                long ops = 0;
                try { work(tid, wall, ref ops); } catch (Exception ex) { err = ex.Message; }
                Interlocked.Add(ref total, ops);
            });
            ts[t].IsBackground = true; ts[t].Start();
        }
        foreach (System.Threading.Thread th in ts) th.Join();
        wall.Stop();
        if (err != null) throw new IOException(err);
        return total / wall.Elapsed.TotalSeconds;
    }

    static void Random4k(string path, long blocks4k, int seed, Stopwatch w, int millis, ref long ops)
    {
        SafeFileHandle h = Open(path, false, false); IntPtr b = Alloc(4096, false);
        try
        {
            Random rnd = new Random(seed); uint d;
            while (w.ElapsedMilliseconds < millis)
            {
                long blk = (long)(rnd.NextDouble() * (blocks4k - 1));
                Seek(h, blk * 4096);
                if (!ReadFile(h, b, 4096, out d, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
                ops++;
            }
        }
        finally { Free(b); h.Dispose(); }
    }
}

// Dauerlast für einen Datenträger: Testdatei mit Prüfmustern beschreiben, danach zufällig lesen, prüfen und neu schreiben
public static class DiagDiskStress
{
    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000, SHARE_RW = 3;
    const uint CREATE_ALWAYS = 2, NO_BUFFERING = 0x20000000, WRITE_THROUGH = 0x80000000, ATTR_TEMPORARY = 0x100;
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool WriteFile(SafeFileHandle h, IntPtr buf, uint n, out uint done, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadFile(SafeFileHandle h, IntPtr buf, uint n, out uint done, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetFilePointerEx(SafeFileHandle h, long dist, out long np, uint method);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool FlushFileBuffers(SafeFileHandle h);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr VirtualAlloc(IntPtr a, UIntPtr size, uint type, uint prot);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool VirtualFree(IntPtr a, UIntPtr size, uint type);

    public static volatile bool Stop;
    public static volatile string Phase = "";
    public static long Ops, Errors, IoErrors, BytesRead, BytesWritten;
    public static string LastError = "";

    public static Task<string> RunAsync(string path, long sizeBytes, int seconds)
    {
        return Task.Factory.StartNew<string>(delegate() { return Run(path, sizeBytes, seconds); }, TaskCreationOptions.LongRunning);
    }

    static void Fill(long[] buf, long block, long gen)
    {
        ulong s = (((ulong)(block + 1) * 0x9E3779B97F4A7C15UL) ^ ((ulong)(gen + 1) * 0xBF58476D1CE4E5B9UL)) | 1UL;
        for (int i = 0; i < buf.Length; i++) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; buf[i] = (long)s; }
    }

    static void Seek(SafeFileHandle h, long pos) { long np; if (!SetFilePointerEx(h, pos, out np, 0)) throw new Win32Exception(Marshal.GetLastWin32Error()); }

    static void WriteBlock(SafeFileHandle h, long b, IntPtr buf, int size)
    {
        uint done; Seek(h, b * size);
        if (!WriteFile(h, buf, (uint)size, out done, IntPtr.Zero) || done != (uint)size) throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    static void ReadBlock(SafeFileHandle h, long b, IntPtr buf, int size)
    {
        uint done; Seek(h, b * size);
        if (!ReadFile(h, buf, (uint)size, out done, IntPtr.Zero) || done != (uint)size) throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    public static string Run(string path, long sizeBytes, int seconds)
    {
        Ops = 0; Errors = 0; IoErrors = 0; BytesRead = 0; BytesWritten = 0; LastError = ""; Phase = "Vorbereitung";
        const int block = 1 << 20; int elems = block / 8;
        long blocks = Math.Max(16, sizeBytes / block);
        long[] gen = new long[blocks];
        long[] exp = new long[elems], got = new long[elems];
        List<string> details = new List<string>();
        StringBuilder sb = new StringBuilder();
        DateTime start = DateTime.UtcNow;
        IntPtr buf = VirtualAlloc(IntPtr.Zero, (UIntPtr)(uint)block, 0x3000, 0x04);
        if (buf == IntPtr.Zero) return "Speicher für den Datenträgertest konnte nicht reserviert werden.";
        SafeFileHandle h = null;
        long written0 = 0;
        try
        {
            h = CreateFileW(path, GENERIC_READ | GENERIC_WRITE, SHARE_RW, IntPtr.Zero, CREATE_ALWAYS, NO_BUFFERING | WRITE_THROUGH | ATTR_TEMPORARY, IntPtr.Zero);
            if (h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            Phase = "Testdatei wird mit Prüfmustern beschrieben";
            for (long b = 0; b < blocks && !Stop; b++)
            {
                Fill(exp, b, 0); Marshal.Copy(exp, 0, buf, elems);
                WriteBlock(h, b, buf, block); BytesWritten += block; Ops++; written0 = b + 1;
                if ((DateTime.UtcNow - start).TotalSeconds > seconds * 0.5) break;
            }
            blocks = Math.Max(1, written0);
            FlushFileBuffers(h);
            Phase = "Zufällig lesen, prüfen und neu schreiben";
            Random rnd = new Random(4242);
            while (!Stop && (DateTime.UtcNow - start).TotalSeconds < seconds)
            {
                long b = (long)(rnd.NextDouble() * blocks); if (b >= blocks) b = blocks - 1;
                try
                {
                    if (rnd.Next(4) == 0)
                    {
                        gen[b]++; Fill(exp, b, gen[b]); Marshal.Copy(exp, 0, buf, elems);
                        WriteBlock(h, b, buf, block); BytesWritten += block;
                    }
                    else
                    {
                        ReadBlock(h, b, buf, block); BytesRead += block;
                        Marshal.Copy(buf, got, 0, elems); Fill(exp, b, gen[b]);
                        for (int i = 0; i < elems; i++)
                            if (got[i] != exp[i]) { Errors++; if (details.Count < 10) details.Add(String.Format("Block {0} (Offset {1:N0} MB), Wort {2}: erwartet 0x{3:X16}, gelesen 0x{4:X16}", b, b, i, exp[i], got[i])); break; }
                    }
                    Ops++;
                }
                catch (Exception ex) { IoErrors++; LastError = ex.Message; if (IoErrors >= 20) throw; }
            }
            if (!Stop)
            {
                Phase = "Abschlussprüfung aller Blöcke";
                for (long b = 0; b < blocks && !Stop; b++)
                {
                    try
                    {
                        ReadBlock(h, b, buf, block); BytesRead += block;
                        Marshal.Copy(buf, got, 0, elems); Fill(exp, b, gen[b]);
                        for (int i = 0; i < elems; i++)
                            if (got[i] != exp[i]) { Errors++; if (details.Count < 10) details.Add(String.Format("Abschlussprüfung Block {0}, Wort {1}: erwartet 0x{2:X16}, gelesen 0x{3:X16}", b, i, exp[i], got[i])); break; }
                        Ops++;
                    }
                    catch (Exception ex) { IoErrors++; LastError = ex.Message; if (IoErrors >= 20) throw; }
                }
            }
        }
        catch (Exception ex) { LastError = ex.Message; sb.AppendLine("Abbruch: " + ex.Message); }
        finally
        {
            VirtualFree(buf, UIntPtr.Zero, 0x8000);
            if (h != null) h.Dispose();
            try { File.Delete(path); } catch { }
        }
        double sec = Math.Max(0.001, (DateTime.UtcNow - start).TotalSeconds);
        sb.Insert(0, String.Format("Testdatei          : {0:N0} MB\r\nDauer              : {1:N0} s\r\nGelesen            : {2:N0} MB ({3:N0} MB/s)\r\nGeschrieben        : {4:N0} MB ({5:N0} MB/s)\r\nDatenfehler        : {6}\r\nE/A-Fehler         : {7}{8}\r\n",
            blocks, sec, BytesRead / 1048576.0, BytesRead / 1048576.0 / sec, BytesWritten / 1048576.0, BytesWritten / 1048576.0 / sec, Errors, IoErrors, LastError.Length > 0 ? " (zuletzt: " + LastError + ")" : ""));
        foreach (string d in details) sb.AppendLine("  " + d);
        Phase = "fertig";
        return sb.ToString();
    }
}
'@
    try { Add-CachedType 'LeosMinibench-Tests' $csCode }
    catch { Write-Warning ('C#-Testroutinen konnten nicht geladen werden: {0}' -f $_.Exception.Message) }
}
$TypesLoaded = [bool]('DiagDiskStress' -as [type])

# Energiesparmodus/Standby während der Diagnose verhindern
if ($TypesLoaded) { [void][DiagPower]::SetThreadExecutionState([uint32]2147483649) }
#endregion

#region ---------- SMART-Hilfsfunktionen ----------
function Get-SmartTestState($Device) {
    $res = [pscustomobject]@{ Running = $false; Percent = $null; Minutes = $null }
    $r = Invoke-External -File $script:Smartctl -Arguments ('-c -l selftest -j -d {0} {1}' -f $Device.type, $Device.name) -TimeoutSec 60
    try { $j = $r.Output | ConvertFrom-Json } catch { return $res }
    if ($j.device.protocol -eq 'NVMe') {
        $op = $j.nvme_self_test_log.current_self_test_operation.value
        if ($op -and [int]$op -ne 0) { $res.Running = $true; $res.Percent = $j.nvme_self_test_log.current_self_test_completion_percent }
        if ($j.nvme_controller_capabilities -and $j.nvme_controller_capabilities.self_test_extended_minutes) { $res.Minutes = $j.nvme_controller_capabilities.self_test_extended_minutes }
    } else {
        $st = $j.ata_smart_data.self_test.status
        if ($st -and [int]$st.value -ge 240 -and [int]$st.value -le 255) { $res.Running = $true; $res.Percent = 100 - [int]$st.remaining_percent }
        $res.Minutes = $j.ata_smart_data.self_test.polling_minutes.extended
    }
    return $res
}

function Test-SmartJson {
    param($Json, [string]$Label)
    $j = $Json
    $isNvme = ($j.device.protocol -eq 'NVMe')
    $crit = New-Object System.Collections.ArrayList
    $passed = $j.smart_status.passed
    if ($passed -eq $false) { Add-Finding KRITISCH 'SMART' ('{0}: SMART-Gesamtstatus FAILED.' -f $Label); [void]$crit.Add('SMART FAILED') }
    $temp = $j.temperature.current
    $life = $null; $written = $null
    if ($isNvme) {
        $n = $j.nvme_smart_health_information_log
        if ($n) {
            $life = 100 - [int]$n.percentage_used
            $written = [double]$n.data_units_written * 512000
            if ($n.critical_warning -ne 0) { Add-Finding KRITISCH 'SMART' ('{0}: NVMe Critical Warning = {1}.' -f $Label, $n.critical_warning); [void]$crit.Add('CriticalWarning') }
            if ($n.media_errors -gt 0) { Add-Finding KRITISCH 'SMART' ('{0}: {1} Medienfehler (Media Errors).' -f $Label, $n.media_errors); [void]$crit.Add("MediaErr $($n.media_errors)") }
            if ($n.available_spare -lt $n.available_spare_threshold) { Add-Finding KRITISCH 'SMART' ('{0}: Reserveblöcke unter Schwelle ({1} %).' -f $Label, $n.available_spare); [void]$crit.Add('Spare') }
            if ($n.percentage_used -ge 90) { Add-Finding KRITISCH 'SMART' ('{0}: Lebensdauer zu {1} % verbraucht.' -f $Label, $n.percentage_used) }
            elseif ($n.percentage_used -ge 70) { Add-Finding WARNUNG 'SMART' ('{0}: Lebensdauer zu {1} % verbraucht.' -f $Label, $n.percentage_used) }
            if ($n.unsafe_shutdowns -gt 200) { Add-Finding INFO 'SMART' ('{0}: {1} unsaubere Abschaltungen.' -f $Label, $n.unsafe_shutdowns) }
            if ($temp -ge 75) { Add-Finding WARNUNG 'SMART' ('{0}: Temperatur {1} °C.' -f $Label, $temp) }
        }
    } else {
        $attrs = $j.ata_smart_attributes.table
        foreach ($a in $attrs) {
            $raw = [double]$a.raw.value
            if ($a.when_failed -eq 'now') { Add-Finding KRITISCH 'SMART' ('{0}: Attribut {1} {2} unter Schwellwert.' -f $Label, $a.id, $a.name); [void]$crit.Add("$($a.id) FAIL") }
            elseif ($a.when_failed -eq 'past') { Add-Finding WARNUNG 'SMART' ('{0}: Attribut {1} {2} war früher unter Schwellwert.' -f $Label, $a.id, $a.name) }
            switch ([int]$a.id) {
                5   { if ($raw -gt 0) { Add-Finding WARNUNG  'SMART' ('{0}: {1} reallokierte Sektoren.' -f $Label, $raw); [void]$crit.Add("Realloc $raw") } }
                187 { if ($raw -gt 0) { Add-Finding WARNUNG  'SMART' ('{0}: {1} gemeldete unkorrigierbare Fehler.' -f $Label, $raw); [void]$crit.Add("Uncorr $raw") } }
                196 { if ($raw -gt 0) { Add-Finding WARNUNG  'SMART' ('{0}: {1} Reallokierungsereignisse.' -f $Label, $raw) } }
                197 { if ($raw -gt 0) { Add-Finding KRITISCH 'SMART' ('{0}: {1} schwebende Sektoren (Pending).' -f $Label, $raw); [void]$crit.Add("Pending $raw") } }
                198 { if ($raw -gt 0) { Add-Finding KRITISCH 'SMART' ('{0}: {1} Offline-unkorrigierbare Sektoren.' -f $Label, $raw); [void]$crit.Add("OfflUnc $raw") } }
                199 { if ($raw -gt 0) { Add-Finding INFO     'SMART' ('{0}: {1} CRC-Übertragungsfehler (Kabel/Anschluss prüfen).' -f $Label, $raw) } }
                { $_ -in 177, 202, 231, 233 } { if ($null -eq $life -and $a.value -le 100) { $life = [int]$a.value } }
                { $_ -in 241, 246 } { if ($null -eq $written) { $written = $raw * 512 } }
            }
        }
        if ($written -and $written -lt 1GB -and $j.power_on_time.hours -gt 100) { $written = $written / 512 * 1GB }   # manche Hersteller zählen in GiB
        $pcy = [double]$j.power_cycle_count; $poh = [double]$j.power_on_time.hours
        if ($pcy -gt 20000 -and $poh -gt 0 -and ($pcy / $poh) -gt 2) { Add-Finding INFO 'SMART' ('{0}: ungewöhnlich viele Einschaltzyklen ({1:N0} bei {2:N0} Betriebsstunden), meist durch Energiesparfunktionen der SATA-Verbindung.' -f $Label, $pcy, $poh) }
        if ($null -ne $life -and $life -le 10) { Add-Finding KRITISCH 'SMART' ('{0}: Restlebensdauer {1} %.' -f $Label, $life) }
        elseif ($null -ne $life -and $life -le 30) { Add-Finding WARNUNG 'SMART' ('{0}: Restlebensdauer {1} %.' -f $Label, $life) }
        if ($temp -ge 55) { Add-Finding WARNUNG 'SMART' ('{0}: Temperatur {1} °C.' -f $Label, $temp) }
        $errCount = $j.ata_smart_error_log.summary.count
        if ($errCount -gt 0) { Add-Finding INFO 'SMART' ('{0}: {1} Einträge im ATA-Fehlerprotokoll.' -f $Label, $errCount) }
    }
    [pscustomobject][ordered]@{
        'Laufwerk'      = $Label
        'Protokoll'     = $j.device.protocol
        'Seriennummer'  = $j.serial_number
        'Firmware'      = $j.firmware_version
        'Größe'         = Format-Size $j.user_capacity.bytes
        'SMART'         = $(if ($passed -eq $true) { 'OK' } elseif ($passed -eq $false) { 'FAILED' } else { '?' })
        'Temp °C'       = $temp
        'Betriebsstd.'  = $j.power_on_time.hours
        'Einschaltz.'   = $j.power_cycle_count
        'Restleben %'   = $life
        'Geschrieben'   = $(if ($written) { Format-SizeDec $written })
        'Auffällig'     = ($crit -join ', ')
    }
}

#endregion


#region ---------- Neue Auswertungen: Installationsalter, RAM-Profil, Abschaltungen, Datenträgerzuordnung ----------
function Format-Age([double]$Days, [switch]$Dativ) {
    # Dativ für "vor ...", sonst Nominativ für "... alt"
    $n = $(if ($Dativ) { 'n' } else { '' })
    if ($Days -lt 1) { return 'weniger als 1 Tag' }
    if ($Days -lt 2) { return '1 Tag' }
    if ($Days -lt 61) { return ('{0:N0} Tage{1}' -f [math]::Floor($Days), $n) }
    if ($Days -lt 730) { return ('{0:N0} Monate{1}' -f [math]::Floor($Days / 30.44), $n) }
    $y = [math]::Floor($Days / 365.25); $m = [math]::Floor(($Days - $y * 365.25) / 30.44)
    if ($m -ge 1) { return ('{0} Jahre{2} {1} Monat{3}' -f $y, $m, $n, $(if ($m -eq 1) { $(if ($Dativ) { '' } else { '' }) } else { 'e' + $n })) }
    return ('{0} Jahre{1}' -f $y, $n)
}

# Windows-Installationsverlauf: InstallDate wird bei jedem Funktionsupdate (Inplace-Upgrade) neu gesetzt.
# Die Schlüssel "Source OS (Updated on ...)" enthalten die Daten der vorherigen Installationen.
function Get-WindowsInstallInfo {
    $fromUnix = { param($v) try { if ($v -and [int64]$v -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$v).LocalDateTime } } catch { } }
    $en = [Globalization.CultureInfo]::GetCultureInfo('en-US')
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $cur = & $fromUnix $cv.InstallDate
    if (-not $cur) { try { $cur = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).InstallDate } catch { } }
    $hist = @(Get-ChildItem 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'Source OS*' } | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        $inst = & $fromUnix $p.InstallDate
        $upd = $null
        if ($_.PSChildName -match 'Updated on (.+)\)') { $t = [datetime]::MinValue; if ([datetime]::TryParse($Matches[1], $en, [Globalization.DateTimeStyles]::None, [ref]$t)) { $upd = $t } }
        if ($inst) {
            [pscustomobject]@{ Installiert = $inst; Ersetzt = $upd; Version = $(if ($p.DisplayVersion) { $p.DisplayVersion } else { $p.ReleaseId })
                Build = ('{0}.{1}' -f $p.CurrentBuild, $p.UBR).Trim('.'); Produkt = $p.ProductName }
        }
    } | Sort-Object Installiert)
    $first = $cur
    foreach ($h in $hist) { if (-not $first -or $h.Installiert -lt $first) { $first = $h.Installiert } }
    $winOld = Get-Item "$env:SystemDrive\Windows.old" -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Erstinstallation = $first
        AktuellSeit      = $cur
        Upgrades         = $hist
        AlterTage        = $(if ($first) { ((Get-Date) - $first).TotalDays } else { $null })
        WindowsOld       = $(if ($winOld) { $winOld.CreationTime } else { $null })
    }
}

# Nenntakt aus der Teilenummer bekannter Hersteller (XMP/EXPO-Kits), Rückgabe in MT/s
function Get-RamRatedSpeed([string]$Part) {
    $p = ([string]$Part).Trim().ToUpperInvariant()
    if (-not $p) { return $null }
    switch -Regex ($p) {
        '^F[345]-(\d{4})'                 { return [int]$Matches[1] }          # G.Skill F4-3200C16-8GVKB, F5-6000J3038F16G
        '^CM[A-Z0-9]*X[345]M\d[A-Z](\d{4})' { return [int]$Matches[1] }        # Corsair CMK16GX4M2B3200C16, CMH32GX5M2B6000C30
        '^KHX(\d{4})C'                    { return [int]$Matches[1] }          # Kingston HyperX KHX3200C16D4/16GX
        '^KF[345](\d{2})C'                { return [int]$Matches[1] * 100 }    # Kingston Fury KF432C16BB/16, KF560C36BBE
        '^BLS?\d+G(\d{2})C'               { return [int]$Matches[1] * 100 }    # Crucial Ballistix BL8G32C16U4B
        '^CP\d+G(\d{2})C'                 { return [int]$Matches[1] * 100 }    # Crucial Pro CP16G56C46U5
        '^TF\w*?(\d{4})HC\d'              { return [int]$Matches[1] }          # TeamGroup T-Force TF3D416G3200HC16F
        '^PV\w*?\d+G(\d{3,4})C'           { $v = [int]$Matches[1]; if ($v -lt 1000) { $v *= 10 }; return $v }   # Patriot PVS416G320C6
        '^AX[45]U(\d{4})'                 { return [int]$Matches[1] }          # ADATA XPG AX4U320016G16A
    }
    return $null
}

# Kernel-Power 41 einordnen: Bluescreen, Ein/Aus-Taste, Standby, Herunterfahren oder Betrieb
function Get-PowerLossInfo($Events) {
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($ev in @($Events | Select-Object -First 15)) {
        $d = @{}
        try { foreach ($n in ([xml]$ev.ToXml()).Event.EventData.Data) { $d[[string]$n.Name] = [string]$n.'#text' } } catch { }
        $bug = 0L; [void][int64]::TryParse([string]$d['BugcheckCode'], [ref]$bug)
        $sleep = 0; [void][int]::TryParse([string]$d['SleepInProgress'], [ref]$sleep)
        $btn = 0L; [void][int64]::TryParse([string]$d['PowerButtonTimestamp'], [ref]$btn)
        $bootT = $ev.TimeCreated.AddMinutes(-1)
        try {
            $b = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 12; StartTime = $ev.TimeCreated.AddMinutes(-15); EndTime = $ev.TimeCreated } -MaxEvents 1 -ErrorAction Stop
            if ($b) { $bootT = $b.TimeCreated }
        } catch { }
        $prev = $null
        try { $prev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; EndTime = $bootT.AddSeconds(-2) } -MaxEvents 1 -ErrorAction Stop } catch { }
        $pid2 = $(if ($prev) { '{0} {1}' -f $prev.ProviderName, $prev.Id } else { '' })
        $kat = 'Betrieb'
        if ($bug -ne 0) { $kat = 'Bluescreen' }
        elseif ($btn -ne 0 -or [string]$d['LongPowerButtonPressDetected'] -eq 'true') { $kat = 'Taste' }
        elseif ($sleep -ne 0 -or ($prev -and $prev.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $prev.Id -in 42, 506)) { $kat = 'Standby' }
        elseif ($prev -and (($prev.ProviderName -eq 'Microsoft-Windows-Kernel-General' -and $prev.Id -eq 13) -or ($prev.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $prev.Id -eq 109) -or ($prev.ProviderName -eq 'User32' -and $prev.Id -eq 1074) -or ($prev.ProviderName -eq 'EventLog' -and $prev.Id -eq 6006))) { $kat = 'Herunterfahren' }
        $text = switch ($kat) {
            'Bluescreen'     { 'Bluescreen 0x{0:X} {1}' -f $bug, (Get-BugcheckName $bug) }
            'Taste'          { 'Ein/Aus-Taste lang gedrückt (erzwungenes Ausschalten, PC hing vermutlich)' }
            'Standby'        { 'Strom im Energiesparmodus verloren oder Aufwachen fehlgeschlagen' }
            'Herunterfahren' { 'beim oder nach dem Herunterfahren abgeschaltet (z. B. Steckdosenleiste bei aktivem Schnellstart)' }
            default          { 'Absturz oder Stromverlust im laufenden Betrieb' }
        }
        $out.Add([pscustomobject]@{ Neustart = $ev.TimeCreated; 'Letzte Aktivität' = $(if ($prev) { $prev.TimeCreated }); 'Letztes Ereignis' = $pid2; Kategorie = $kat; Einordnung = $text })
    }
    return $out.ToArray()
}

# Datenträgernummern in Ereignistexten den aktuellen Laufwerken zuordnen
function Get-DiskRefText($Events) {
    if (-not $script:DiskNames) {
        $script:DiskNames = @{}
        try { Get-PhysicalDisk -ErrorAction Stop | ForEach-Object { $script:DiskNames[[int]$_.DeviceId] = ('{0} ({1})' -f ([string]$_.FriendlyName).Trim(), $_.BusType) } } catch { }
    }
    $nums = @{}
    foreach ($e in $Events) {
        $m = [string]$e.Message
        foreach ($rx in 'Harddisk(\d+)', 'Datenträger "(\d+)"', '[Dd]isk (\d+)\b') { foreach ($mm in [regex]::Matches($m, $rx)) { $nums[[int]$mm.Groups[1].Value] = $true } }
    }
    if (-not $nums.Count) { return '' }
    $parts = foreach ($n in ($nums.Keys | Sort-Object)) {
        if ($script:DiskNames.ContainsKey($n)) { 'Datenträger {0} = {1}' -f $n, $script:DiskNames[$n] }
        else { 'Datenträger {0} ist derzeit nicht vorhanden (ausgefallen, abgezogen oder USB)' -f $n }
    }
    return (' Betroffen (Nummer zum Zeitpunkt des Ereignisses): {0}.' -f ($parts -join '; '))
}
#endregion

#region ---------- Datenschutz für die KI-Datei ----------
function Protect-Text([string]$Text) {
    if (-not $Text) { return $Text }
    $t = $Text
    $generic = @('USER', 'ADMIN', 'ADMINISTRATOR', 'BENUTZER', 'OWNER', 'BESITZER', 'PC', 'GAST', 'GUEST', 'SYSTEM')
    foreach ($u in @($script:UserNames | Where-Object { $_ } | Select-Object -Unique)) {
        $e = [regex]::Escape($u)
        $t = [regex]::Replace($t, '(?i)(\\Users\\|\\Benutzer\\)' + $e + '(?=\\|\b)', '$1<BENUTZER>')
        $t = [regex]::Replace($t, '(?i)(\\)' + $e + '(?![A-Za-z0-9])', '$1<BENUTZER>')
        if ($u.Length -ge 5 -and $generic -notcontains $u.ToUpperInvariant()) { $t = [regex]::Replace($t, '(?i)(?<![A-Za-z0-9])' + $e + '(?![A-Za-z0-9])', '<BENUTZER>') }
    }
    foreach ($kv in @($script:Private.GetEnumerator() | Sort-Object { $_.Key.Length } -Descending)) {
        $e = [regex]::Escape($kv.Key)
        $rx = $(if ($kv.Key -match '^\w' -and $kv.Key -match '\w$') { '(?i)(?<![A-Za-z0-9])' + $e + '(?![A-Za-z0-9])' } else { '(?i)' + $e })
        $t = [regex]::Replace($t, $rx, $kv.Value.Replace('$', '$$'))
    }
    if ($env:COMPUTERNAME) { $t = [regex]::Replace($t, '(?i)(?<![A-Za-z0-9])' + [regex]::Escape($env:COMPUTERNAME) + '(?![A-Za-z0-9])', '<PC>') }
    $t = [regex]::Replace($t, '\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b', '<MAC>')
    $t = [regex]::Replace($t, 'S-1-5-21-\d+-\d+-\d+(-\d+)?', '<SID>')
    $t = [regex]::Replace($t, '[\w.+-]+@[\w-]+\.[\w.-]+', '<E-MAIL>')
    return $t
}

function Add-PrivateFromRaw {
    foreach ($f in @(Get-ChildItem $RawDir -Filter 'smartctl_*.txt' -ErrorAction SilentlyContinue)) {
        $c = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($m in [regex]::Matches([string]$c, '(?im)^(Serial [Nn]umber|LU WWN Device Id|IEEE EUI-64|Logical Unit id):\s*(.+?)\s*$')) { Add-Private $m.Groups[2].Value 'SERIENNR' }
    }
}
#endregion

#region ---------- KI-Analysedatei ----------
function ConvertFrom-HtmlToText([string]$Html) {
    if (-not $Html) { return '' }
    $h = [regex]::Replace($Html, '(?is)<(script|style)[^>]*>.*?</\1>', '')
    $h = [regex]::Replace($h, '(?i)<br\s*/?>|</(p|tr|h\d|div|li|table|thead|tbody)>', "`n")
    $h = [regex]::Replace($h, '(?i)</t[dh]>', ' | ')
    $h = [regex]::Replace($h, '<[^>]+>', '')
    $h = [System.Net.WebUtility]::HtmlDecode($h)
    $lines = $h -split "`n" | ForEach-Object { (($_ -replace '\s+', ' ').Trim()).Trim('|').Trim() } | Where-Object { $_ }
    return ($lines -join "`r`n")
}

function Get-KiPrompt {
@'
AUFTRAG AN DIE KI (bitte zuerst lesen)

Du bist ein erfahrener Windows- und PC-Hardware-Techniker. Diese Datei enthält Bericht und Rohdaten eines Laufs des Werkzeugs Leos Minibench auf einem Windows-PC. Werte alles gründlich aus, finde die Ursachen von Problemen und zeige, wie sie sich beheben lassen.

Vorgehen
1. Lies zuerst ÜBERBLICK, BEFUNDE und TESTERGEBNISSE, danach Details und Rohdaten.
2. Prüfe die automatische Bewertung kritisch: bestätige, relativiere oder widerlege jeden wichtigen Befund anhand der Rohdaten.
3. Suche Zusammenhänge, zum Beispiel zwischen Bluescreen-Codes und RAM-Takt oder XMP/EXPO, zwischen Datenträgerereignissen und SMART-Werten, zwischen Abstürzen, Lasttest und Temperaturen.
4. Suche nach Auffälligkeiten, die das Werkzeug nicht als Befund markiert hat.
5. Belege jede Aussage mit der konkreten Stelle (Abschnitt, Messwert, Ereignis-ID, Zeitpunkt). Kennzeichne Vermutungen ausdrücklich.

Antwortformat (auf Deutsch, sachlich und knapp)
A. Kurzfazit: Zustand des PCs in höchstens fünf Sätzen mit Ampel (grün, gelb, rot).
B. Probleme nach Dringlichkeit als Tabelle: Problem, Beleg aus den Daten, wahrscheinliche Ursache, Sicherheit der Einschätzung (hoch, mittel, niedrig).
C. Lösungsschritte, nummeriert vom einfachsten und risikoärmsten zum aufwendigsten. Je Schritt: was genau zu tun ist (Klickpfad oder Befehl für PowerShell als Administrator), Risiko, ob ein Neustart nötig ist und woran man den Erfolg erkennt. Vor Schritten mit Datenverlustrisiko auf eine Sicherung hinweisen.
D. Leistung: Einordnung der Benchmark-Werte gegenüber Referenz, Vergleichssystemen und Hardwareklasse, Engpässe, ob sich eine Aufrüstung lohnt und welche.
E. Offene Punkte: welche Angaben fehlen und welche zusätzlichen Tests oder Daten (mit Befehl) die Diagnose absichern würden. Fragen an den Nutzer ans Ende stellen.

Hinweise zu den Daten
1. Persönliche Angaben (Seriennummern, Benutzer- und Computernamen, MAC-Adressen) sind gegebenenfalls durch Platzhalter in spitzen Klammern ersetzt, zum Beispiel <SERIENNR-2>. Gleiche Platzhalter bedeuten gleiche Werte.
2. Die Temperatur stammt aus der ACPI-Thermalzone und ist keine Kerntemperatur. Bleibt sie unter Last konstant, ist sie ohne Aussagekraft.
3. Der Grafik-Benchmark nutzt WinSAT DWM (Speicherdurchsatz, Desktop-Komposition) und ist kein Spiele-Benchmark.
4. Der RAM-Test unter Windows erreicht nicht jeden Speicherbereich. Ein fehlerfreier Lauf schließt RAM-Fehler nicht aus.
5. Kernel-Power 41 ohne Bluescreen-Code heißt nur, dass Windows nicht sauber beendet wurde. Der Bericht ordnet jedes Ereignis anhand des letzten Ereignisses vor dem Neustart ein (Betrieb, Standby, Herunterfahren, Ein/Aus-Taste).
6. Datenträgernummern in Ereignissen gelten für den Zeitpunkt des Ereignisses und können sich seitdem geändert haben.
7. Index 100 entspricht dem typischen Wert der Hardwareklasse. Referenz 100 % ist das angegebene Referenzsystem.
8. Win32_OperatingSystem.InstallDate zeigt das letzte Funktionsupdate. Das Datum der Erstinstallation steht im Abschnitt System und Betriebssystem.
'@
}

function New-KiExport {
    param([string]$Path, $Sorted, [int]$NK, [int]$NW, [int]$NI, [datetime]$Start, [datetime]$End, [switch]$Compact, [int]$RawBudget = 260000)
    $sb = New-Object System.Text.StringBuilder
    $line = '#' * 100
    $add = { param([string]$t) [void]$sb.AppendLine($t) }
    $head = { param([string]$t) [void]$sb.AppendLine(''); [void]$sb.AppendLine($line); [void]$sb.AppendLine('#  ' + $t); [void]$sb.AppendLine($line) }
    & $add $line
    & $add ('#  LEOS MINIBENCH {0}: DATEN FÜR DIE KI-AUSWERTUNG{1}' -f $ScriptVersion, $(if ($Compact) { ' (KURZFASSUNG OHNE ROHDATEN)' } else { '' }))
    & $add $line
    & $add ''
    & $add (Get-KiPrompt)

    & $head 'ÜBERBLICK'
    & $add ('Erstellt              : {0:dd.MM.yyyy HH:mm} bis {1:HH:mm} Uhr (Dauer {2:hh\:mm\:ss})' -f $Start, $End, ($End - $Start))
    & $add ('Module                : {0}' -f (Get-ModeLabel))
    & $add ('Ergebnis              : {0} kritisch, {1} Warnungen, {2} Hinweise' -f $NK, $NW, $NI)
    foreach ($k in $script:Facts.Keys) { & $add (('{0,-22}: {1}' -f $k, ([string]$script:Facts[$k] -replace "`r?`n", '; '))) }

    & $head 'BEFUNDE (automatische Bewertung)'
    if ($Sorted.Count) { foreach ($f in $Sorted) { & $add ('[{0}] {1}: {2}' -f $f.Stufe, $f.Bereich, $f.Befund) } } else { & $add 'Keine Auffälligkeiten gefunden.' }

    if ($script:TestResults.Count) {
        & $head 'TESTERGEBNISSE'
        foreach ($t in $script:TestResults) { & $add ('{0} | {1} | {2}' -f $t.Test, $t.Ergebnis, $t.Details) }
    }

    if ($script:BenchResults.Count -or $script:BenchDisks.Count) {
        & $head 'BENCHMARK'
        & $add ('Referenz 100 % = {0}' -f $script:Ref.Name)
        if ($script:BenchRefSummary) { & $add $script:BenchRefSummary }
        & $add 'Gruppe;Messung;Wert;Einheit;Index;Status;Referenz;Vergleich frühere Läufe;Hinweis'
        foreach ($b in $script:BenchResults) { & $add (('{0};{1};{2};{3};{4};{5};{6};{7};{8}' -f $b.Gruppe, $b.Messung, ([double]$b.Wert).ToString($script:Inv), $b.Einheit, $b.Index, $b.Status, $b.Referenz, $b.Vergleich, $b.Hinweis)) }
        if ($script:BenchDisks.Count) {
            & $add ''
            & $add 'Laufwerk;Klasse;Lesen MB/s;Schreiben MB/s;4K QD1 IOPS;4K 8 Threads IOPS;4K schreiben IOPS;Index;Referenz;Status;Hinweis'
            foreach ($d in $script:BenchDisks) { & $add (('{0};{1};{2:0};{3:0};{4:0};{5:0};{6:0};{7};{8};{9};{10}' -f $d.Laufwerk, $d.Klasse, [double]$d.SR, [double]$d.SW, [double]$d.R1, [double]$d.R8, [double]$d.W1, $d.Index, $d.Referenz, $d.Status, $d.Hinweis)) }
        }
    }

    if ($script:CmpRows.Count) {
        & $head 'VERGLEICH MIT BEREITS GEPRÜFTEN SYSTEMEN'
        $i = 0
        foreach ($s in $script:CmpSystems) { $i++; & $add ('System {0}: {1} (Messung vom {2})' -f $i, $s.Name, $s.Datum) }
        & $add ('Messung;Dieser PC;' + ((1..$script:CmpSystems.Count | ForEach-Object { "System $_" }) -join ';') + ';Rang in der Datenbank')
        foreach ($r in $script:CmpRows) {
            $cells = for ($k = 0; $k -lt $script:CmpSystems.Count; $k++) { $v = $r.Werte[$k]; if ($null -ne $v) { $rel = Get-RelText $r.Dieses $v $r.LowerBetter; (Format-Metric $v $r.Format $r.Einheit) + $(if ($rel) { ' (' + $rel + ')' } else { '' }) } else { '' } }
            & $add (('{0};{1};{2};{3}' -f $r.Messung, (Format-Metric $r.Dieses $r.Format $r.Einheit), ($cells -join ';'), $r.Rang))
        }
        & $add 'Prozent in Klammern: Abstand des anderen Systems zu diesem PC, positiv bedeutet besser.'
    }

    if ($script:LoadParts.Count -or $script:LoadSeries.Count) {
        & $head 'LASTTEST'
        if ($script:LoadSummary) { & $add $script:LoadSummary }
        foreach ($p in $script:LoadParts) { & $add ('{0} | {1} | {2} | {3}' -f $p.Komponente, $p.Dauer, $p.Ergebnis, $p.Details) }
        if ($script:LoadAbort) { & $add ('Abbruch nach {0} s: {1}' -f $script:LoadAbort.T, $script:LoadAbort.Grund) }
        if ($script:LoadThrottle) {
            & $add ('Drosselnachweis: {0} ({1})' -f $script:LoadThrottle.Status, $script:LoadThrottle.Befund)
            foreach ($b in $script:LoadThrottle.Belege) { & $add ('  ' + $b) }
        }
        if ($script:LoadSeries.Count) {
            & $add ''
            & $add 'Verlauf (Sekunde;effektiver Takt Windows MHz;CPU-Last %;Frequenzgrenze %;Thermalzone °C;CPU °C;Quelle CPU-Temperatur;CPU-Takt Sensoren MHz;CPU-Paket W;GPU °C;GPU MHz;GPU W;Lüfter U/min;Datenträger °C;Datenträger MB/s;CPU-Last aktiv)'
            $step = [math]::Max(1, [int][math]::Ceiling($script:LoadSeries.Count / 80))
            for ($i = 0; $i -lt $script:LoadSeries.Count; $i += $step) { $s = $script:LoadSeries[$i]; & $add ('{0};{1};{2};{3};{4};{5};{6};{7};{8};{9};{10};{11};{12};{13};{14};{15}' -f $s.T, $s.MHz, $s.Last, $s.MaxFreq, $s.Temp, $s.CpuTemp, $s.CpuTempQ, $s.CpuMHz, $s.CpuW, $s.GpuTemp, $s.GpuMHz, $s.GpuW, $s.Fan, $s.DiskTemp, $s.DiskMBs, $(if ($s.Cpu) { 1 } else { 0 })) }
        }
    }

    if ($script:SensorSnapshot) {
        & $head 'SENSOREN (MOMENTAUFNAHME IM LEERLAUF)'
        & $add (Get-SensorSourceText)
        & $add 'Gruppe;Gerät;Art;Sensor;Wert;Einheit;Quelle'
        foreach ($r in @($script:SensorSnapshot | Where-Object { -not [double]::IsNaN([double]$_.Wert) })) { & $add ('{0};{1};{2};{3};{4};{5};{6}' -f $r.Gruppe, $r.Geraet, $r.Art, $r.Name, ([double]$r.Wert).ToString('0.###', $script:Inv), $r.Einheit, $r.Quelle) }
    }

    if ($script:RepairLog.Count) {
        & $head 'REPARATUREN'
        foreach ($r in $script:RepairLog) { & $add ('{0} | {1} | {2}{3}' -f $r.Reparatur, $r.Ergebnis, $r.Details, $(if ($r.Stufe) { ' | Stufe ' + $r.Stufe } else { '' })) }
        if ($script:RestartNeeded.Count) { & $add ('Neustart erforderlich für: {0}' -f (($script:RestartNeeded | Select-Object -Unique) -join ', ')) }
    }

    if (-not $Compact) {
        & $head 'VOLLSTÄNDIGER BERICHT (alle Abschnitte)'
        & $add $script:Report.ToString()

        & $head 'ROHDATEN AUS DEM ANHANG'
        $files = @()
        if ($RawDir -and (Test-Path $RawDir)) { $files = @(Get-ChildItem $RawDir -File -ErrorAction SilentlyContinue) }
        $prio = @{ 'Checkpoint.log' = 1; 'Checkpoint_unterbrochener_Lauf.log' = 2; 'Diagnosebericht_unterbrochener_Lauf.txt' = 3; 'Konsole.log' = 4; 'Benchmark.csv' = 5; 'Lasttest-Verlauf.csv' = 6; 'winsat.txt' = 8; 'Treiber.csv' = 9; 'Energiebericht.html' = 10; 'Akkubericht.html' = 11; 'dxdiag.txt' = 12; 'Software.csv' = 13; 'ComputerInfo.txt' = 14 }
        $files = @($files | Where-Object { $_.Name -notlike '*.xml' } | Sort-Object { if ($prio.ContainsKey($_.Name)) { $prio[$_.Name] } elseif ($_.Name -like 'smartctl_*') { 7 } else { 20 } }, Name)
        $used = 0
        foreach ($f in $files) {
            $raw = ''
            try { $raw = [IO.File]::ReadAllText($f.FullName) } catch { continue }
            $raw = $raw.TrimStart([char]0xFEFF)
            $max = 30000
            switch -Wildcard ($f.Name) {
                'Energiebericht.html' {
                    # nur Fehler und Warnungen der Analyse, die Informationsereignisse sind meist ohne Belang
                    $a = $raw.IndexOf('Analyseergebnisse'); if ($a -lt 0) { $a = $raw.IndexOf('Analysis Results') }
                    $mI = [regex]::Match($raw, '<h4>\s*(Informationen|Information)\s*</h4>')
                    if ($a -gt 0 -and $mI.Success -and $mI.Index -gt $a) { $raw = $raw.Substring($a, $mI.Index - $a) }
                    $raw = ConvertFrom-HtmlToText $raw; $max = 15000
                }
                '*.html'         { $raw = ConvertFrom-HtmlToText $raw; $max = 15000 }
                'Checkpoint*'    { $ls = @($raw -split "`r?`n"); $raw = ((@($ls | Where-Object { $_ -notmatch '\|\s*PULS\s*\|' }) + '(Pulsmeldungen, letzte 15:)' + @($ls | Where-Object { $_ -match '\|\s*PULS\s*\|' } | Select-Object -Last 15)) -join "`r`n") }
                'dxdiag.txt'     { $max = 18000 }
                'Software.csv'   { $max = 15000 }
                'ComputerInfo.txt' { $max = 12000 }
            }
            $left = $RawBudget - $used
            if ($left -le 2000) { & $add ''; & $add ('--- {0}: ausgelassen (Größenbegrenzung der KI-Datei)' -f $f.Name); continue }
            $max = [math]::Min($max, $left)
            $note = ''
            if ($raw.Length -gt $max) { $note = (' [gekürzt auf {0:N0} von {1:N0} Zeichen]' -f $max, $raw.Length); $raw = $raw.Substring(0, $max) }
            $used += $raw.Length
            & $add ''
            & $add (('--- DATEI: {0}{1} ' -f $f.Name, $note).PadRight(100, '-'))
            & $add $raw.TrimEnd()
        }
        $err = Join-Path $OutputDir 'Fehler.txt'
        if (Test-Path $err) { & $add ''; & $add '--- DATEI: Fehler.txt (Skriptfehler) ---'; & $add ((Get-Content $err -Raw) -replace '^\s+', '') }
    }

    & $head 'ENDE DER DATEN'
    & $add 'Bitte jetzt gemäß AUFTRAG AN DIE KI am Anfang dieser Datei antworten.'
    $text = $sb.ToString()
    if (-not $KiOhneAnonymisierung) { $text = Protect-Text $text }
    if ($Path) { [IO.File]::WriteAllText($Path, $text, (New-Object Text.UTF8Encoding($true))) }
    return $text
}
#endregion

#region ---------- Vergleichsdatenbank ----------
# Format 2 (ab 2.2): zusätzlich Geraet = Kennung (SHA-256 aus Mainboard und Firmware), Güte und Quellen der Kennung.
# Format 1 bleibt lesbar; solche Einträge werden über den Computernamen einem Gerät zugeordnet.
$script:DbFormat = 'PC-Diagnose-DB/2'
function Get-SafeName([string]$s) { (($s -replace '[\\/:*?"<>|\s]+', '_').Trim('_')) }

function Save-DbEntry {
    param($Sorted, [int]$NK, [int]$NW, [int]$NI)
    if (-not $script:DbDir -or $KeineDatenbank -or $AnalyzeLastRun) { return '' }
    $w = Get-CurrentRefValues
    if ($Kurztest -and -not $w.Count) { return '' }
    try { New-Item -ItemType Directory -Path $script:DbDir -Force -ErrorAction Stop | Out-Null } catch { return '' }
    $hw = [ordered]@{
        CPU = $(if ($script:BenchShort.CPU) { $script:BenchShort.CPU } else { [string]$script:Facts['Prozessor'] })
        RAM = $(if ($script:BenchShort.RAM) { $script:BenchShort.RAM } else { [string]$script:Facts['Arbeitsspeicher'] })
        GPU = $(if ($script:BenchShort.GPU) { $script:BenchShort.GPU } else { [string]$script:Facts['Grafik'] })
        Datentraeger = ([string]$script:Facts['Datenträger'] -replace "`r?`n", '; ')
        Betriebssystem = [string]$script:Facts['Betriebssystem']
        Mainboard = [string]$script:Facts['Mainboard']
        WindowsInstalliert = [string]$script:Facts['Windows installiert']
    }
    $dev = Get-DeviceIdentity
    $o = [ordered]@{
        Format    = $script:DbFormat
        Name      = $(if ($script:BenchRefName) { $script:BenchRefName } else { '{0} ({1})' -f $env:COMPUTERNAME, ((@($hw.CPU, $hw.RAM, $hw.GPU) | Where-Object { $_ }) -join ', ') })
        Computer  = $env:COMPUTERNAME
        Geraet    = [ordered]@{ Id = $dev.Id; Guete = $dev.Guete; Quellen = @($dev.Quellen) }
        Datum     = (Get-Date).ToString('yyyy-MM-dd HH:mm', $script:Inv)
        Version   = $ScriptVersion
        Quelle    = 'Lauf'
        Module    = (Get-ModeLabel)
        Messdauer = $(if ($BenchmarkKurz) { 'kurz' } else { 'normal' })
        System    = [string]$script:Facts['System']
        Hardware  = $hw
        Werte     = $w
        Messwerte = $(if ($script:BenchNew.Count) { $mw = [ordered]@{}; foreach ($b in $script:BenchNew) { $mw[$b.Key] = $b.Wert }; $mw } else { [ordered]@{} })
        Ordner    = $(if ($script:DataDir -and $OutputDir -like ($script:DataDir + '*')) { $OutputDir.Substring($script:DataDir.Length).TrimStart('\') } else { $OutputDir })
        Laufwerke = @($script:BenchDisks | Where-Object { $_.SR -gt 0 } | ForEach-Object { [ordered]@{ Laufwerk = $_.Laufwerk; Klasse = $_.Klasse; SR = [math]::Round($_.SR); SW = [math]::Round($_.SW); R1 = [math]::Round($_.R1); R8 = [math]::Round($_.R8); W1 = [math]::Round($_.W1) } })
        Befunde   = [ordered]@{ Kritisch = $NK; Warnungen = $NW; Hinweise = $NI; Liste = @($Sorted | ForEach-Object { '[{0}] {1}: {2}' -f $_.Stufe, $_.Bereich, $_.Befund }) }
        Lasttest  = $script:LoadSummary
        Sensoren  = $(if ($script:SensorDb.Count) { $script:SensorDb } else { [ordered]@{} })
    }
    $file = Join-Path $script:DbDir ('{0}_{1}.json' -f (Get-SafeName $env:COMPUTERNAME), (Get-Date -Format 'yyyyMMdd_HHmmss'))
    try { [IO.File]::WriteAllText($file, ($o | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false))); return $file } catch { return '' }
}

# Ältere Ausgabeordner (Version 1.x) in die Datenbank übernehmen
function Import-LegacyRun([string]$Folder) {
    $name = Split-Path $Folder -Leaf
    $tmp = $null; $csvPath = $null
    try {
        $zip = Join-Path $Folder 'Anhang.zip'
        foreach ($c in @((Join-Path $Folder 'Benchmark.csv'), (Join-Path (Join-Path $Folder 'Anhang') 'Benchmark.csv'))) { if (Test-Path -LiteralPath $c) { $csvPath = $c; break } }
        if (-not $csvPath -and (Test-Path -LiteralPath $zip)) {
            $tmp = Join-Path $(if ($script:DataDir) { Join-Path $script:DataDir 'Laufzeit' } else { $env:TEMP }) ('Import-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force -ErrorAction Stop
            $c = Join-Path $tmp 'Benchmark.csv'; if (Test-Path $c) { $csvPath = $c }
        }
        $txtPath = Join-Path $Folder 'Diagnosebericht.txt'; $htmlPath = Join-Path $Folder 'Diagnosebericht.html'
        $txt = $(if (Test-Path -LiteralPath $txtPath) { [IO.File]::ReadAllText($txtPath) } else { '' })
        $html = $(if (Test-Path -LiteralPath $htmlPath) { [IO.File]::ReadAllText($htmlPath) } else { '' })
        if (-not $csvPath -and -not $txt) { return ('{0}: keine Berichtsdaten gefunden.' -f $name) }

        $facts = @{}
        foreach ($m in [regex]::Matches($html, '(?s)<dt>(.*?)</dt><dd>(.*?)</dd>')) { $facts[[Net.WebUtility]::HtmlDecode($m.Groups[1].Value)] = ([Net.WebUtility]::HtmlDecode(($m.Groups[2].Value -replace '<br>', '; '))) }
        $rows = @(); if ($csvPath) { $rows = @(Import-Csv -LiteralPath $csvPath -Delimiter ';' -Encoding UTF8) }
        $computer = $(if ($rows.Count -and $rows[0].Computer) { $rows[0].Computer } elseif ($facts['Computer']) { $facts['Computer'] } elseif ($txt -match 'DIAGNOSEBERICHT\s+(\S+)') { $Matches[1] } else { $name })
        $datum = $(if ($rows.Count -and $rows[0].Datum) { $rows[0].Datum } elseif ($txt -match 'Erstellt\s*:\s*(\d{2})\.(\d{2})\.(\d{4}) (\d{2}:\d{2})') { '{0}-{1}-{2} {3}' -f $Matches[3], $Matches[2], $Matches[1], $Matches[4] } else { '' })
        $ver = $(if ($txt -match 'DIAGNOSEBERICHT\s+\S+\s+v([\d.]+)') { $Matches[1] } else { '1.x' })

        $map = @{ 'CPU|Einzelkern' = 'CPU|ST'; 'CPU|Mehrkern' = 'CPU|MT'; 'CPU|AES-256 verschlüsseln' = 'CPU|AES'; 'CPU|SHA-256 Prüfsumme' = 'CPU|SHA'; 'CPU|Kompression (Deflate)' = 'CPU|DEFL'
                  'RAM|Lesen' = 'RAM|Lesen'; 'RAM|Schreiben' = 'RAM|Schreiben'; 'RAM|Kopieren' = 'RAM|Kopieren'; 'RAM|Latenz' = 'RAM|Latenz'
                  'GPU|Grafikspeicher-Durchsatz' = 'GPU|VMB'; 'GPU|Desktop-Komposition' = 'GPU|DWM' }
        $w = @{}; $dsk = [ordered]@{}; $byCls = @{}
        foreach ($r in $rows) {
            $val = 0.0; if (-not [double]::TryParse([string]$r.Wert, [Globalization.NumberStyles]::Float, $script:Inv, [ref]$val) -or $val -le 0) { continue }
            $mk = '{0}|{1}' -f $r.Gruppe, $r.Messung
            if ($map.ContainsKey($mk)) { $w[$map[$mk]] = [math]::Round($val, 1); continue }
            if ($r.Gruppe -eq 'Laufwerke' -and $r.Messung -match '^(.+?) (seq\. lesen|seq\. schreiben|4K zufällig QD1|4K zufällig 8 Threads|4K zufällig schreiben QD1)$') {
                $lbl = $Matches[1]; $kind = @{ 'seq. lesen' = 'SR'; 'seq. schreiben' = 'SW'; '4K zufällig QD1' = 'R1'; '4K zufällig 8 Threads' = 'R8'; '4K zufällig schreiben QD1' = 'W1' }[$Matches[2]]
                if (-not $dsk.Contains($lbl)) { $dsk[$lbl] = [ordered]@{ Laufwerk = $lbl; Klasse = ''; SR = 0; SW = 0; R1 = 0; R8 = 0; W1 = 0 } }
                $dsk[$lbl][$kind] = [math]::Round($val)
                if ($kind -eq 'SR' -and $r.Hinweis -match 'typisch für (.+?):') { $dsk[$lbl].Klasse = $Matches[1] } elseif ($kind -eq 'SR' -and -not $dsk[$lbl].Klasse) { $dsk[$lbl].Klasse = [string]$r.Hinweis }
            }
        }
        foreach ($d in $dsk.Values) {
            $cls = ''
            if ($d.Klasse -match 'NVMe PCIe (\d)\.0 x(\d+)') { if ([int]$Matches[1] -ge 3 -and [int]$Matches[2] -ge 4) { $cls = 'NVMe' + $Matches[1] } }
            elseif ($d.Klasse -match 'SATA-SSD') { $cls = 'SATA-SSD' } elseif ($d.Klasse -match 'Festplatte') { $cls = 'HDD' }
            if (-not $cls) { continue }
            foreach ($k in 'SR', 'SW', 'R1', 'R8', 'W1') { if ($d[$k] -gt 0) { $key = "DISK|$cls|$k"; if (-not $byCls.ContainsKey($key)) { $byCls[$key] = New-Object System.Collections.ArrayList }; [void]$byCls[$key].Add([double]$d[$k]) } }
        }
        foreach ($k in $byCls.Keys) { $w[$k] = [math]::Round((($byCls[$k] | Measure-Object -Average).Average), 0) }

        # Kurzbezeichnungen aus den Kopfzeilen der Benchmark-Gruppen
        $short = @{}
        foreach ($g in @(@('PROZESSOR', 'CPU'), @('ARBEITSSPEICHER', 'RAM'), @('GRAFIK', 'GPU'))) {
            if ($txt -match ('(?m)^  {0}\s+\[[^\]]*\].*\r?\n  (.+?)(?: · |\r?$)' -f $g[0])) { $short[$g[1]] = ($Matches[1] -replace ', \d+ Kan.le$', '').Trim() }
        }
        $nk = 0; $nw = 0; $ni = 0
        if ($txt -match 'ERGEBNIS:\s*(\d+) kritisch, (\d+) Warnungen, (\d+) Hinweise') { $nk = [int]$Matches[1]; $nw = [int]$Matches[2]; $ni = [int]$Matches[3] }
        $list = @([regex]::Matches($txt, '(?m)^  \[(KRITISCH|WARNUNG|INFO)\s*\]\s+(\S+)\s+(.+?)\s*$') | ForEach-Object { '[{0}] {1}: {2}' -f $_.Groups[1].Value, $_.Groups[2].Value, $_.Groups[3].Value })

        foreach ($e in (Get-DbEntries)) { if ($e.Computer -eq $computer -and $e.Datum -eq $datum) { return ('{0}: {1} vom {2} ist bereits in der Datenbank.' -f $name, $computer, $datum) } }
        $hw = [ordered]@{
            CPU = $(if ($short.CPU) { $short.CPU } else { [string]$facts['Prozessor'] }); RAM = $(if ($short.RAM) { $short.RAM } else { [string]$facts['Arbeitsspeicher'] })
            GPU = $(if ($short.GPU) { $short.GPU } else { [string]$facts['Grafik'] }); Datentraeger = [string]$facts['Datenträger']; Betriebssystem = [string]$facts['Betriebssystem']; Mainboard = ''; WindowsInstalliert = ''
        }
        $cpuS = ($hw.CPU -replace '^(AMD|Intel\(R\))\s*', '' -replace '\((R|TM)\)', '').Trim()
        $gpuS = ($hw.GPU -replace '^(AMD|NVIDIA|Intel\(R\))\s*', '').Trim()
        $o = [ordered]@{
            Format = $script:DbFormat; Name = ('{0} ({1})' -f $computer, ((@($cpuS, $hw.RAM, $gpuS) | Where-Object { $_ }) -join ', ')); Computer = $computer
            Geraet = [ordered]@{ Id = ''; Guete = 'unbekannt'; Quellen = @() }; Datum = $datum; Version = $ver
            Quelle = ('Import aus ' + $name); Module = 'Import'; Messdauer = 'unbekannt'; System = [string]$facts['System']; Hardware = $hw; Werte = $w
            Laufwerke = @($dsk.Values); Befunde = [ordered]@{ Kritisch = $nk; Warnungen = $nw; Hinweise = $ni; Liste = $list }; Lasttest = ''
        }
        New-Item -ItemType Directory -Path $script:DbDir -Force | Out-Null
        $stamp = $(if ($datum -match '^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})') { '{0}{1}{2}_{3}{4}00' -f $Matches[1], $Matches[2], $Matches[3], $Matches[4], $Matches[5] } else { Get-Date -Format 'yyyyMMdd_HHmmss' })
        $file = Join-Path $script:DbDir ('{0}_{1}.json' -f (Get-SafeName $computer), $stamp)
        [IO.File]::WriteAllText($file, ($o | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
        return ('{0}: {1} vom {2} importiert ({3} Messwerte, {4} Laufwerke).' -f $name, $computer, $datum, $w.Count, $dsk.Count)
    } catch {
        return ('{0}: Import fehlgeschlagen: {1}' -f $name, $_.Exception.Message)
    } finally {
        if ($tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Import-LegacyFolder([string]$Root) {
    if (-not $script:DbDir) { Write-Host 'Kein beschreibbarer Datenordner vorhanden.'; return }
    $isRun = { param($d) (Test-Path -LiteralPath (Join-Path $d 'Diagnosebericht.txt')) -or (Test-Path -LiteralPath (Join-Path $d 'Anhang.zip')) -or (Test-Path -LiteralPath (Join-Path $d 'Benchmark.csv')) }
    $dirs = @()
    if (& $isRun $Root) { $dirs = @($Root) } else { $dirs = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Where-Object { & $isRun $_.FullName } | ForEach-Object { $_.FullName }) }
    if (-not $dirs.Count) { Write-Host ('In {0} wurde kein Ausgabeordner von Leos Minibench oder PC-Diagnose gefunden.' -f $Root); return }
    foreach ($d in $dirs) { Write-Host (Import-LegacyRun $d) }
}
#endregion

# XMP/EXPO-Prüfung: Nenntakt laut Teilenummer gegen den Betriebstakt
function Test-RamProfile($Mods, [string]$TypeName) {
    $mods = @($Mods)
    if (-not $mods.Count) { return }
    $rated = @($mods | ForEach-Object { Get-RamRatedSpeed ([string]$_.PartNumber) } | Where-Object { $_ })
    $cfg = [int](($mods | Where-Object { $_.ConfiguredClockSpeed } | Measure-Object ConfiguredClockSpeed -Minimum).Minimum)
    if ($rated.Count -ne $mods.Count -or $cfg -le 0) { return }
    $rMin = [int](($rated | Measure-Object -Minimum).Minimum)
    $parts = (@($mods | ForEach-Object { ([string]$_.PartNumber).Trim() }) | Select-Object -Unique) -join ', '
    if ($rMin -gt $cfg * 1.05) {
        $gain = ($rMin / $cfg - 1) * 100
        Add-Line ('  Nenntakt laut Teilenummer: {0} MT/s, Betriebstakt: {1} MT/s. Das XMP/EXPO-Profil ist vermutlich nicht aktiv.' -f $rMin, $cfg)
        Add-Finding $(if ($gain -ge 20) { 'WARNUNG' } else { 'INFO' }) 'RAM' ('Die RAM-Module ({0}) sind für {1}-{2} ausgelegt, laufen aber nur mit {3} MT/s. Im BIOS das XMP-, EXPO- oder DOCP-Profil aktivieren (rund {4:N0} % mehr Speichertakt) und danach die Stabilität mit RAM- und Lasttest prüfen.' -f $parts, $(if ($TypeName) { $TypeName } else { 'RAM' }), $rMin, $cfg, $gain)
    } elseif ($rMin -le $cfg + 50) {
        Add-Line ('  Nenntakt laut Teilenummer: {0} MT/s, das Speicherprofil (XMP/EXPO) ist aktiv.' -f $rMin)
        $script:RamProfileActive = $true
    }
}

function Get-ShortCpuName([string]$Name) { ((($Name -as [string]) -replace '\s+', ' ').Trim() -replace '\s*(\d+-Core|Processor|CPU @.*$)', '' -replace '\((R|TM)\)', '').Trim() }
function Get-ShortGpuName([string]$Name) { (([string]$Name) -replace '^(AMD|NVIDIA|Intel\(R\))\s*', '').Trim() }
function Get-MainGpu {
    $gl = @(Get-CimCached Win32_VideoController | Where-Object { $_.Name -notmatch 'Virtual|Remote|Indirect|Parsec|spacedesk|Basic Display|Basic Render' })
    $gd = @($gl | Where-Object { [string]$_.Name -match 'NVIDIA|GeForce|Quadro|Radeon\s*(RX|Pro|VII)|FirePro|Intel.*Arc' })
    return (@($gd) + @($gl) | Select-Object -First 1)
}


# Einträge der Systemdateiprüfung aus CBS.log ab einem Zeitpunkt (Prüf- und Reparaturmodus)
function Get-CbsEntries([datetime]$Since) {
    $res = [pscustomobject]@{ Cannot = @(); Corrupt = @(); Files = @() }
    $cbs = "$env:windir\Logs\CBS\CBS.log"
    if (-not (Test-Path $cbs)) { return $res }
    $lines = @(Select-String -Path $cbs -Pattern '\[SR\]|Hashes for file member|do not match|corrupt' -ErrorAction SilentlyContinue | ForEach-Object {
        $t = [datetime]::MinValue
        if ($_.Line.Length -ge 19 -and [datetime]::TryParseExact($_.Line.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$t) -and $t -ge $Since.AddMinutes(-1)) { $_.Line }
    })
    $res.Cannot  = @($lines | Where-Object { $_ -match 'Cannot repair' })
    $res.Corrupt = @($lines | Where-Object { $_ -match 'corrupt|Repaired|Repairing|do not match|Hashes for file member|Cannot verify' -and $_ -notmatch 'Repairing 0 components|\b0 corrupt|Verify complete|Beginning Verify' })
    # Dateiname in Anführungszeichen vollständig übernehmen (auch mit mehreren Punkten wie Microsoft.Windows.Shell.dll)
    $res.Files   = @(($res.Cannot + $res.Corrupt) | ForEach-Object { foreach ($m in [regex]::Matches($_, "\[l:\d+(?:\{\d+\})?\](?:['""]([^'""]+?\.[A-Za-z0-9]{2,8})['""]|([^\s'""\]]+\.[A-Za-z0-9]{2,8})\b)")) { if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value } } } | Select-Object -Unique)
    return $res
}


#region ---------- Vorbereitung: smartmontools ----------
$script:SmartLicense = 'GPL-2.0-or-later'
$script:SmartSource  = 'smartmontools.org, per winget (smartmontools.smartmontools)'
$script:ToolNotes    = New-Object System.Collections.Generic.List[string]

function Find-Smartctl {
    # auf diesem PC installiert (PATH oder Programme): gehört zum PC, nicht zum Stick
    $tools = Get-ToolsDir
    $c = Get-Command smartctl.exe -ErrorAction SilentlyContinue
    if ($c -and -not ($tools -and $c.Source -like ($tools + '*'))) { return $c.Source }
    foreach ($p in @("$env:ProgramFiles\smartmontools\bin\smartctl.exe", "${env:ProgramFiles(x86)}\smartmontools\bin\smartctl.exe")) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    # portabel aus Minibench-Daten\Tools: nur mit passendem Eintrag im Werkzeug-Manifest
    $leg = Register-LegacyTool 'smartctl' @('smartmontools\bin\smartctl.exe', 'smartctl.exe') $script:SmartLicense $script:SmartSource
    if ($leg) { $script:ToolNotes.Add(('smartctl.exe aus Version 2.1 wurde ins Werkzeug-Manifest aufgenommen (SHA-256 {0}…). Ab jetzt läuft nur diese Datei.' -f $leg.SHA256.Substring(0, 12))) }
    $v = Get-VerifiedTool 'smartctl'
    if ($v) { return $v }
    # smartctl.exe neben dem Skript (frühere Ablage) wird nicht mehr ausgeführt
    if ($PSScriptRoot) {
        foreach ($p in @((Join-Path $PSScriptRoot 'smartctl.exe'), (Join-Path $PSScriptRoot 'Tools\smartctl.exe'))) {
            if (Test-Path -LiteralPath $p) { $script:ToolNotes.Add(('{0} liegt außerhalb von Minibench-Daten\Tools und wird nicht ausgeführt. Über "smartmontools holen" neu aufnehmen lassen.' -f $p)); break }
        }
    }
    return $null
}
#endregion

#region ---------- Sensoren: LibreHardwareMonitor, PawnIO und Ersatzquellen ----------
# Temperatur, Takt, Lüfter, Spannung und Leistung kommen bevorzugt aus LibreHardwareMonitorLib (portabel unter
# Minibench-Daten\Tools\LibreHardwareMonitor). Ab 0.9.5 liest die Bibliothek CPU-Werte und Mainboard-Chips nur über den
# Treiber PawnIO. Der Treiber wird nie ungefragt installiert: nur mit -SensorTreiber (Rückfrage in der Oberfläche),
# nur wenn er fehlt, und am Ende des Laufs wieder entfernt. Eine Markierungsdatei sorgt dafür, dass er auch nach
# einem Absturz beim nächsten Start entfernt wird. War PawnIO schon installiert, bleibt es unangetastet.
# Ohne Bibliothek oder Treiber gibt es Ersatzwerte: Windows-Leistungszähler (Takt), ACPI-Thermalzonen, nvidia-smi,
# Zuverlässigkeitszähler der Datenträger und Akkustatus aus WMI.
#
# Geladen wird nur, was zu den hier festgehaltenen SHA-256-Werten passt (Herkunft: offizielle GitHub-Releases).
# Eine neue Version von LibreHardwareMonitor braucht neue Einträge in $script:LhmPins.
$script:LhmVersion = '0.9.6'
$script:LhmSubDir  = 'LibreHardwareMonitor'
$script:LhmZip     = @{ Url = 'https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.6/LibreHardwareMonitor.zip'; SHA256 = '086d9f1b5a99e643edc2cfaaac16051685b551e4c5ac0b32a57c58c0e529c001' }
$script:LhmSource  = 'github.com/LibreHardwareMonitor/LibreHardwareMonitor, Release v0.9.6 (LibreHardwareMonitor.zip)'
$script:LhmPins = [ordered]@{
    'LibreHardwareMonitorLib.dll'                = @{ SHA256 = '6ebc194316536ba61af5be24508ad9fcbb2ecc685e716c12e787c79530f66bf0'; Lizenz = 'MPL-2.0' }
    'BlackSharp.Core.dll'                        = @{ SHA256 = 'cafb93afcc8d8a367e21f619673d05c06887d8964867fed1371f02ded1cd3e23'; Lizenz = 'siehe THIRD-PARTY-NOTICES von LibreHardwareMonitor' }
    'DiskInfoToolkit.dll'                        = @{ SHA256 = '1acbf51b3c10c51c986cf43021680d34a2e38d9a5ba652bcfa9a1b5f7fc09800'; Lizenz = 'siehe THIRD-PARTY-NOTICES von LibreHardwareMonitor' }
    'HidSharp.dll'                               = @{ SHA256 = 'd86690efde30ea9179f669320f39148853793b743a98b531afeaf30598e22f54'; Lizenz = 'Apache-2.0' }
    'RAMSPDToolkit-NDD.dll'                      = @{ SHA256 = 'b6882354c7c8ec186617e421507743dbfae09c5c1fc24cef76a1d0c0c26651de'; Lizenz = 'siehe THIRD-PARTY-NOTICES von LibreHardwareMonitor' }
    'System.Buffers.dll'                         = @{ SHA256 = '2d78d770c9cb997199154ae8c018b9f1d1efbc86729f7264dde6dbad2a12cac3'; Lizenz = 'MIT' }
    'System.Memory.dll'                          = @{ SHA256 = 'd5e8e4866f9cfa66f7765660f84b210198893e55335487afe5ebda342c0e913d'; Lizenz = 'MIT' }
    'System.Numerics.Vectors.dll'                = @{ SHA256 = '20c2fa81b8c70d651099d762954f285fd4f942e63b2d7217c145dab8d4b2f4c9'; Lizenz = 'MIT' }
    'System.Runtime.CompilerServices.Unsafe.dll' = @{ SHA256 = '08cbd7278b66f1e68425a82d4b97181a4130d93e3dd91831407aba7212ccdacf'; Lizenz = 'MIT' }
}
$script:PawnIoPin = @{
    Version = '2.2.0'; Ordner = 'PawnIO'; Datei = 'PawnIO_setup.exe'; Lizenz = 'GPL-2.0 (Treiber), Installer laut Hersteller unverändert weitergebbar'
    Url = 'https://github.com/namazso/PawnIO.Setup/releases/download/2.2.0/PawnIO_setup.exe'; SHA256 = '1f519a22e47187f70a1379a48ca604981c4fcf694f4e65b734aaa74a9fba3032'
    Quelle = 'github.com/namazso/PawnIO.Setup, Release 2.2.0'
}
$script:Sens = $null
$script:PawnIoByUs = $false
$script:SensorNotes = New-Object System.Collections.Generic.List[string]
$script:SensorSnapshot = $null
$script:SensorDb = [ordered]@{}

if ($FullLanguage -and -not $ImportOrdner -and -not $Vergleich -and -not $Rueckgaengig -and -not $SensorWerkzeugeHolen -and -not $SensorAufraeumen -and -not ('DiagSensors' -as [type])) {
    $sensCode = @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;

// Ein Messwert eines Sensors. Key ist über die Laufzeit stabil (bei LibreHardwareMonitor der Identifier).
public class SensorReading
{
    public string Key = "", Quelle = "", Gruppe = "", Geraet = "", Art = "", Name = "", Einheit = "";
    public double Wert = double.NaN;
    public double TjMax = double.NaN;
    public override string ToString() { return Gruppe + " | " + Geraet + " | " + Art + " | " + Name + " = " + Wert.ToString("0.###", CultureInfo.InvariantCulture) + " " + Einheit; }
}

// Zugriff auf LibreHardwareMonitorLib.dll ausschließlich über Reflexion: Das Skript lässt sich ohne die Bibliothek
// übersetzen, und geladen wird sie erst, wenn das Werkzeug-Manifest ihre Prüfsummen bestätigt hat.
public static class DiagSensors
{
    static Assembly lhm;
    static object computer;
    static string lhmDir = "";
    static PropertyInfo pHwList, pHwName, pHwType, pHwSensors, pHwSub, pSName, pSType, pSValue, pSId, pSParams, pParName, pParValue;
    static MethodInfo mUpdate;
    static bool resolverAdded;

    public static string LastError = "";
    public static string LibVersion = "";
    public static bool IsOpen { get { return computer != null; } }
    public static int UpdateErrors;

    static Assembly Resolve(object sender, ResolveEventArgs e)
    {
        // Abhängigkeiten der Bibliothek aus ihrem eigenen Ordner laden, unabhängig von der verlangten Version
        // (ersetzt die bindingRedirects aus LibreHardwareMonitor.exe.config)
        try
        {
            if (lhmDir.Length == 0) return null;
            string n = new AssemblyName(e.Name).Name;
            foreach (Assembly a in AppDomain.CurrentDomain.GetAssemblies())
            {
                try { if (a.GetName().Name == n && !a.IsDynamic && a.Location.StartsWith(lhmDir, StringComparison.OrdinalIgnoreCase)) return a; } catch { }
            }
            string p = Path.Combine(lhmDir, n + ".dll");
            if (File.Exists(p)) return Assembly.UnsafeLoadFrom(p);
        }
        catch { }
        return null;
    }

    static PropertyInfo Prop(Type t, string name)
    {
        PropertyInfo p = t.GetProperty(name);
        if (p == null) throw new MissingMemberException(t.FullName, name);
        return p;
    }

    // Bibliothek laden und Computer öffnen. Rückgabe false mit LastError, wenn etwas fehlt oder scheitert.
    public static bool Open(string dllPath, bool cpu, bool gpu, bool board, bool memory, bool storage, bool battery, bool controller)
    {
        LastError = "";
        if (computer != null) return true;
        try
        {
            lhmDir = Path.GetDirectoryName(Path.GetFullPath(dllPath));
            if (!resolverAdded) { AppDomain.CurrentDomain.AssemblyResolve += Resolve; resolverAdded = true; }
            // UnsafeLoadFrom: Dateien aus einem heruntergeladenen Archiv tragen die Internet-Zone; geprüft sind sie über SHA-256
            lhm = Assembly.UnsafeLoadFrom(dllPath);
            LibVersion = lhm.GetName().Version.ToString();
            Type tc = lhm.GetType("LibreHardwareMonitor.Hardware.Computer", true);
            Type th = lhm.GetType("LibreHardwareMonitor.Hardware.IHardware", true);
            Type ts = lhm.GetType("LibreHardwareMonitor.Hardware.ISensor", true);
            Type tp = lhm.GetType("LibreHardwareMonitor.Hardware.IParameter", true);
            pHwList = Prop(tc, "Hardware");
            pHwName = Prop(th, "Name"); pHwType = Prop(th, "HardwareType"); pHwSensors = Prop(th, "Sensors"); pHwSub = Prop(th, "SubHardware");
            mUpdate = th.GetMethod("Update");
            if (mUpdate == null) throw new MissingMethodException(th.FullName, "Update");
            pSName = Prop(ts, "Name"); pSType = Prop(ts, "SensorType"); pSValue = Prop(ts, "Value"); pSId = Prop(ts, "Identifier"); pSParams = Prop(ts, "Parameters");
            pParName = Prop(tp, "Name"); pParValue = Prop(tp, "Value");
            object c = Activator.CreateInstance(tc);
            Set(tc, c, "IsCpuEnabled", cpu); Set(tc, c, "IsGpuEnabled", gpu); Set(tc, c, "IsMotherboardEnabled", board);
            Set(tc, c, "IsMemoryEnabled", memory); Set(tc, c, "IsStorageEnabled", storage); Set(tc, c, "IsBatteryEnabled", battery);
            Set(tc, c, "IsControllerEnabled", controller); Set(tc, c, "IsNetworkEnabled", false); Set(tc, c, "IsPsuEnabled", controller);
            tc.GetMethod("Open", Type.EmptyTypes).Invoke(c, null);
            computer = c;
            return true;
        }
        catch (Exception ex)
        {
            Exception x = ex; while (x is TargetInvocationException && x.InnerException != null) x = x.InnerException;
            LastError = x.GetType().Name + ": " + x.Message;
            computer = null;
            return false;
        }
    }

    static void Set(Type t, object o, string name, bool v)
    {
        PropertyInfo p = t.GetProperty(name);
        if (p != null && p.CanWrite) p.SetValue(o, v, null);
    }

    public static void Close()
    {
        if (computer == null) return;
        try { computer.GetType().GetMethod("Close", Type.EmptyTypes).Invoke(computer, null); } catch { }
        computer = null;
    }

    // Ob PawnIO in der laufenden Bibliothek geladen werden konnte (nur Auskunft, kein Einfluss auf das Lesen)
    public static string PawnIoState()
    {
        try
        {
            Type t = lhm == null ? null : lhm.GetType("LibreHardwareMonitor.PawnIo.PawnIo");
            if (t == null) return "";
            PropertyInfo inst = t.GetProperty("IsInstalled", BindingFlags.Public | BindingFlags.Static);
            PropertyInfo ver = t.GetProperty("Version", BindingFlags.Public | BindingFlags.Static);
            bool ok = inst != null && (bool)inst.GetValue(null, null);
            object v = ver == null ? null : ver.GetValue(null, null);
            return ok ? "installiert " + Convert.ToString(v, CultureInfo.InvariantCulture) : "nicht installiert";
        }
        catch { return ""; }
    }

    public static string Group(string hwType)
    {
        switch (hwType)
        {
            case "Cpu": return "CPU";
            case "GpuNvidia": case "GpuAmd": case "GpuIntel": return "GPU";
            case "Motherboard": case "SuperIO": case "EmbeddedController": return "Mainboard";
            case "Memory": return "RAM";
            case "Storage": return "Datenträger";
            case "Battery": return "Akku";
            case "Cooler": return "Kühlung";
            case "Psu": case "PowerMonitor": return "Netzteil";
            default: return "";
        }
    }

    public static string Kind(string sensorType, out string unit)
    {
        switch (sensorType)
        {
            case "Temperature": unit = "°C"; return "Temperatur";
            case "Clock": unit = "MHz"; return "Takt";
            case "Fan": unit = "U/min"; return "Lüfter";
            case "Voltage": unit = "V"; return "Spannung";
            case "Power": unit = "W"; return "Leistung";
            case "Load": unit = "%"; return "Auslastung";
            case "Control": unit = "%"; return "Lüftersteuerung";
            case "Current": unit = "A"; return "Strom";
            case "Level": unit = "%"; return "Füllstand";
            default: unit = ""; return "";
        }
    }

    // Alle Hardware aktualisieren und die Werte der unterstützten Sensorarten liefern
    public static SensorReading[] Read()
    {
        List<SensorReading> res = new List<SensorReading>();
        if (computer == null) return res.ToArray();
        IEnumerable list = null;
        try { list = pHwList.GetValue(computer, null) as IEnumerable; } catch (Exception ex) { LastError = ex.Message; }
        if (list == null) return res.ToArray();
        foreach (object hw in list) ReadHardware(hw, null, res, 0);
        return res.ToArray();
    }

    static void ReadHardware(object hw, string parentName, List<SensorReading> res, int depth)
    {
        if (hw == null || depth > 3) return;
        string type = "", name = "";
        try { mUpdate.Invoke(hw, null); } catch { UpdateErrors++; }
        try { type = Convert.ToString(pHwType.GetValue(hw, null)); name = Convert.ToString(pHwName.GetValue(hw, null)); } catch { return; }
        string grp = Group(type);
        // Unterhardware (z. B. SuperIO-Chip am Mainboard) gehört zur Gruppe des übergeordneten Geräts, sofern sie selbst keine hat
        if (grp.Length == 0 && parentName != null) grp = "Mainboard";
        if (grp.Length > 0)
        {
            IEnumerable sensors = null;
            try { sensors = pHwSensors.GetValue(hw, null) as IEnumerable; } catch { }
            if (sensors != null)
                foreach (object s in sensors)
                {
                    try
                    {
                        string unit; string kind = Kind(Convert.ToString(pSType.GetValue(s, null)), out unit);
                        if (kind.Length == 0) continue;
                        object v = pSValue.GetValue(s, null);
                        SensorReading r = new SensorReading();
                        r.Key = Convert.ToString(pSId.GetValue(s, null));
                        r.Quelle = "LHM"; r.Gruppe = grp; r.Geraet = parentName != null ? parentName + " / " + name : name;
                        r.Art = kind; r.Name = Convert.ToString(pSName.GetValue(s, null)); r.Einheit = unit;
                        r.Wert = v == null ? double.NaN : Convert.ToDouble(v, CultureInfo.InvariantCulture);
                        if (kind == "Temperatur")
                        {
                            IEnumerable ps = pSParams.GetValue(s, null) as IEnumerable;
                            if (ps != null) foreach (object p in ps)
                                {
                                    string pn = Convert.ToString(pParName.GetValue(p, null));
                                    if (pn.StartsWith("TjMax", StringComparison.OrdinalIgnoreCase)) r.TjMax = Convert.ToDouble(pParValue.GetValue(p, null), CultureInfo.InvariantCulture);
                                }
                        }
                        res.Add(r);
                    }
                    catch { UpdateErrors++; }
                }
        }
        IEnumerable sub = null;
        try { sub = pHwSub.GetValue(hw, null) as IEnumerable; } catch { }
        if (sub != null) foreach (object h in sub) ReadHardware(h, name, res, depth + 1);
    }
}
'@
    try { Add-CachedType 'LeosMinibench-Sensoren' $sensCode }
    catch { Write-Warning ('Sensorroutinen konnten nicht geladen werden: {0}' -f $_.Exception.Message) }
}
$SensorTypesLoaded = [bool]('DiagSensors' -as [type])

function Get-LhmToolName([string]$File) { return ('LibreHardwareMonitor:{0}' -f $File) }

# ---------- Werkzeuge: prüfen, aufnehmen, holen ----------
# Liegen passende Dateien schon im Tools-Ordner (von Hand kopiert), werden sie mit Prüfsummenvergleich ins Manifest aufgenommen.
# Dateien mit anderer Prüfsumme werden nicht aufgenommen und nicht geladen.
function Register-PinnedSensorTools([string]$ToolsDir = (Get-ToolsDir)) {
    if (-not $ToolsDir -or -not (Test-Path -LiteralPath $ToolsDir)) { return }
    $m = Read-ToolManifest $ToolsDir
    if ($m.Ungueltig) { return }
    $known = @{}; foreach ($e in $m.Werkzeuge) { $known[$e.Name] = $e }
    $items = @(foreach ($f in $script:LhmPins.Keys) { [pscustomobject]@{ Name = (Get-LhmToolName $f); Rel = (Join-Path $script:LhmSubDir $f); SHA256 = $script:LhmPins[$f].SHA256; Lizenz = $script:LhmPins[$f].Lizenz; Quelle = $script:LhmSource } })
    $items += [pscustomobject]@{ Name = 'PawnIO-Setup'; Rel = (Join-Path $script:PawnIoPin.Ordner $script:PawnIoPin.Datei); SHA256 = $script:PawnIoPin.SHA256; Lizenz = $script:PawnIoPin.Lizenz; Quelle = $script:PawnIoPin.Quelle }
    foreach ($it in $items) {
        if ($known.ContainsKey($it.Name)) { continue }
        $p = Join-Path $ToolsDir $it.Rel
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $h = Get-FileSha256 $p
        if ($h -ne $it.SHA256) { $script:ToolIssues.Add(('{0}: {1} hat nicht die bekannte Prüfsumme (SHA-256 {2}…) und wird nicht geladen. Nur LibreHardwareMonitor {3} und PawnIO {4} aus den offiziellen Releases sind freigegeben.' -f $it.Name, $it.Rel, $h.Substring(0, 12), $script:LhmVersion, $script:PawnIoPin.Version)); continue }
        Unblock-SensorFile $p
        [void](Register-Tool -Name $it.Name -Path $p -Lizenz $it.Lizenz -Quelle $it.Quelle -Herkunft 'im Tools-Ordner vorgefunden, Prüfsumme entspricht dem offiziellen Release' -ToolsDir $ToolsDir)
    }
}

# Internet-Markierung (Zone.Identifier) entfernen, nachdem die Prüfsumme bestätigt ist; sonst verweigert .NET das Laden
function Unblock-SensorFile([string]$Path) {
    if (Get-Command Unblock-File -ErrorAction SilentlyContinue) { try { Unblock-File -LiteralPath $Path -ErrorAction Stop } catch { } }
}

# Pfad einer freigegebenen Datei: im Manifest, Hash passt zum Manifest und zum festgehaltenen Wert
function Get-PinnedTool([string]$Name, [string]$PinSha, [string]$ToolsDir = (Get-ToolsDir)) {
    $p = Get-VerifiedTool $Name $ToolsDir
    if (-not $p) { return $null }
    $e = @((Read-ToolManifest $ToolsDir).Werkzeuge | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
    if (-not $e -or $e.SHA256 -ne $PinSha) { $script:ToolIssues.Add(('{0}: Eintrag im Werkzeug-Manifest weicht vom freigegebenen Release ab und wird nicht geladen.' -f $Name)); return $null }
    return $p
}

function Get-SensorToolState([string]$ToolsDir = (Get-ToolsDir)) {
    $st = [pscustomobject]@{ LhmDll = ''; LhmBereit = $false; Fehlend = @(); PawnIoSetup = ''; Version = $script:LhmVersion }
    if (-not $ToolsDir) { $st.Fehlend = @('Datenordner'); return $st }
    Register-PinnedSensorTools $ToolsDir
    $miss = New-Object System.Collections.Generic.List[string]
    foreach ($f in $script:LhmPins.Keys) {
        $p = Get-PinnedTool (Get-LhmToolName $f) $script:LhmPins[$f].SHA256 $ToolsDir
        if (-not $p) { $miss.Add($f) } elseif ($f -eq 'LibreHardwareMonitorLib.dll') { $st.LhmDll = $p }
    }
    $st.Fehlend = $miss.ToArray()
    $st.LhmBereit = ($miss.Count -eq 0 -and [bool]$st.LhmDll)
    $ps = Get-PinnedTool 'PawnIO-Setup' $script:PawnIoPin.SHA256 $ToolsDir
    if ($ps) { $st.PawnIoSetup = $ps }
    return $st
}

# Herunterladen (eigene Funktion, damit Tests sie ersetzen können)
function Save-WebFile([string]$Url, [string]$Path) {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
}

# LibreHardwareMonitorLib und PawnIO-Setup aus den offiziellen Releases holen, prüfen und ins Manifest aufnehmen.
# Alles landet im Datenordner (Stick), auf dem PC bleibt nichts.
function Install-SensorTools([string]$ToolsDir = (Get-ToolsDir)) {
    $log = New-Object System.Collections.Generic.List[string]
    $ok = $true
    if (-not $ToolsDir) { return [pscustomobject]@{ Ok = $false; Meldungen = @('Kein Datenordner verfügbar.') } }
    $work = Join-Path (Join-Path $script:DataDir 'Laufzeit') ('Download-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        New-Item -ItemType Directory -Path $work -Force -ErrorAction Stop | Out-Null
        $dest = Join-Path $ToolsDir $script:LhmSubDir
        New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop | Out-Null
        $zip = Join-Path $work 'LibreHardwareMonitor.zip'
        Save-WebFile $script:LhmZip.Url $zip
        $h = Get-FileSha256 $zip
        if ($h -ne $script:LhmZip.SHA256) { throw ('LibreHardwareMonitor.zip hat eine unerwartete Prüfsumme ({0}…), nichts übernommen.' -f $h.Substring(0, 12)) }
        $ex = Join-Path $work 'lhm'
        Expand-Archive -LiteralPath $zip -DestinationPath $ex -Force -ErrorAction Stop
        foreach ($f in $script:LhmPins.Keys) {
            $src = Join-Path $ex $f
            if (-not (Test-Path -LiteralPath $src)) { throw ('{0} fehlt im Release-Archiv.' -f $f) }
            if ((Get-FileSha256 $src) -ne $script:LhmPins[$f].SHA256) { throw ('{0} im Archiv hat eine unerwartete Prüfsumme.' -f $f) }
            Copy-Item -LiteralPath $src -Destination (Join-Path $dest $f) -Force -ErrorAction Stop
            Unblock-SensorFile (Join-Path $dest $f)
            if (-not (Register-Tool -Name (Get-LhmToolName $f) -Path (Join-Path $dest $f) -Lizenz $script:LhmPins[$f].Lizenz -Quelle $script:LhmSource -Herkunft ('von GitHub geholt auf {0}, Prüfsumme bestätigt' -f $env:COMPUTERNAME) -ToolsDir $ToolsDir)) { throw 'Eintrag ins Werkzeug-Manifest fehlgeschlagen.' }
        }
        $log.Add(('LibreHardwareMonitorLib {0} mit {1} Begleitdateien übernommen ({2}).' -f $script:LhmVersion, ($script:LhmPins.Count - 1), $dest))
        $lic = @('LibreHardwareMonitorLib und Begleitbibliotheken aus ' + $script:LhmSource,
            'Lizenz LibreHardwareMonitor: Mozilla Public License 2.0, Quelltext: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor',
            'Lizenzen der Begleitbibliotheken: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/blob/v0.9.6/THIRD-PARTY-NOTICES.txt',
            '', 'PawnIO ' + $script:PawnIoPin.Version + ' aus ' + $script:PawnIoPin.Quelle + ': ' + $script:PawnIoPin.Lizenz)
        [IO.File]::WriteAllLines((Join-Path $dest 'Lizenzen.txt'), [string[]]$lic, (New-Object Text.UTF8Encoding($false)))
    } catch { $ok = $false; $log.Add(('LibreHardwareMonitor: {0}' -f $_.Exception.Message)) }
    try {
        $pdest = Join-Path (Join-Path $ToolsDir $script:PawnIoPin.Ordner) $script:PawnIoPin.Datei
        New-Item -ItemType Directory -Path (Split-Path $pdest -Parent) -Force -ErrorAction Stop | Out-Null
        $tmp = Join-Path $work 'PawnIO_setup.exe'
        Save-WebFile $script:PawnIoPin.Url $tmp
        $h = Get-FileSha256 $tmp
        if ($h -ne $script:PawnIoPin.SHA256) { throw ('PawnIO_setup.exe hat eine unerwartete Prüfsumme ({0}…), nicht übernommen.' -f $h.Substring(0, 12)) }
        Copy-Item -LiteralPath $tmp -Destination $pdest -Force -ErrorAction Stop
        Unblock-SensorFile $pdest
        if (-not (Register-Tool -Name 'PawnIO-Setup' -Path $pdest -Lizenz $script:PawnIoPin.Lizenz -Quelle $script:PawnIoPin.Quelle -Herkunft ('von GitHub geholt auf {0}, Prüfsumme bestätigt' -f $env:COMPUTERNAME) -ToolsDir $ToolsDir)) { throw 'Eintrag ins Werkzeug-Manifest fehlgeschlagen.' }
        $log.Add(('PawnIO-Setup {0} übernommen. Installiert wird der Treiber nur nach Rückfrage und nur für die Dauer eines Laufs.' -f $script:PawnIoPin.Version))
    } catch { $ok = $false; $log.Add(('PawnIO: {0}' -f $_.Exception.Message)) }
    finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ Ok = $ok; Meldungen = $log.ToArray() }
}

# ---------- PawnIO: nur vorübergehend und nur, wenn er fehlte ----------
function Get-PawnIoMarker {
    if (-not $script:DataDir) { return '' }
    return (Join-Path (Join-Path $script:DataDir 'Laufzeit') ('PawnIO_{0}.txt' -f (Get-SafeName $env:COMPUTERNAME)))
}

# Registrierung lesen wie LibreHardwareMonitor (Uninstall\PawnIO, 64-Bit-Ansicht als Ersatz)
function Get-PawnIoRegistry {
    foreach ($view in 'Default', 'Registry64') {
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::$view)
            $k = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO')
            if ($k) {
                $r = [pscustomobject]@{ Version = [string]$k.GetValue('DisplayVersion'); Ort = [string]$k.GetValue('InstallLocation'); Deinstallation = [string]$k.GetValue('QuietUninstallString') }
                $k.Close(); $base.Close(); return $r
            }
            $base.Close()
        } catch { }
    }
    return $null
}

function Get-PawnIoState {
    $r = Get-PawnIoRegistry
    return [pscustomobject]@{ Installiert = [bool]($r -and $r.Version); Version = $(if ($r) { $r.Version } else { '' }); Ort = $(if ($r) { $r.Ort } else { '' }); Deinstallation = $(if ($r) { $r.Deinstallation } else { '' }) }
}

function Install-PawnIoTemporary {
    $st = Get-PawnIoState
    if ($st.Installiert) { return [pscustomobject]@{ Ok = $true; Text = ('PawnIO {0} war bereits installiert und bleibt unverändert' -f $st.Version) } }
    $setup = (Get-SensorToolState).PawnIoSetup
    if (-not $setup) { return [pscustomobject]@{ Ok = $false; Text = 'PawnIO-Setup fehlt im Tools-Ordner (Seite Sensoren: Sensorwerkzeuge holen)' } }
    $marker = Get-PawnIoMarker
    # Markierung zuerst: Stürzt der Lauf ab, entfernt der nächste Start den Treiber
    # ohne Markierung kein Treiber: Sie ist der einzige Weg zurück nach einem Absturz
    if (-not $marker) { return [pscustomobject]@{ Ok = $false; Text = 'PawnIO nicht installiert: kein Datenordner für die Markierung' } }
    try { New-Item -ItemType Directory -Path (Split-Path $marker -Parent) -Force -ErrorAction Stop | Out-Null; [IO.File]::WriteAllText($marker, ('PawnIO {0} installiert von Leos Minibench {1} am {2:yyyy-MM-dd HH:mm:ss}' -f $script:PawnIoPin.Version, $ScriptVersion, (Get-Date))) }
    catch { return [pscustomobject]@{ Ok = $false; Text = ('PawnIO nicht installiert: Markierung ließ sich nicht schreiben ({0})' -f $_.Exception.Message) } }
    $r = Invoke-External -File $setup -Arguments '-install -silent' -TimeoutSec 180 -Progress 'PawnIO-Treiber wird vorübergehend installiert'
    $st = Get-PawnIoState
    if (-not $st.Installiert) {
        if ($marker) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
        return [pscustomobject]@{ Ok = $false; Text = ('Installation von PawnIO fehlgeschlagen (Rückgabecode {0})' -f $r.ExitCode) }
    }
    $script:PawnIoByUs = $true
    $script:PawnIoInstalledRun = $true
    [void](Add-ChangeRecord -Modul 'Sensoren' -Schritt 'Treiber' -Titel 'PawnIO-Treiber vorübergehend installiert' -Risiko 'Eingriff' -Art 'Treiber' -Ziel ('PawnIO {0}' -f $st.Version) `
        -Vorher 'nicht installiert' -Nachher 'installiert' -Gegenbefehl ('"{0}" -uninstall -silent (läuft am Ende des Laufs automatisch)' -f $setup) -NurHinweis)
    $t = 'PawnIO {0} vorübergehend installiert' -f $st.Version
    if ($r.ExitCode -eq 3010) { $t += ' (Setup meldet: Neustart erforderlich, CPU-Werte erst danach)' }
    return [pscustomobject]@{ Ok = $true; Text = $t }
}

# Entfernt PawnIO, wenn dieses Werkzeug ihn installiert hat (in diesem Lauf oder laut Markierung in einem abgebrochenen)
function Uninstall-PawnIo {
    $marker = Get-PawnIoMarker
    $hasMarker = [bool]($marker -and (Test-Path -LiteralPath $marker))
    if (-not $script:PawnIoByUs -and -not $hasMarker) { return $null }
    $st = Get-PawnIoState
    if (-not $st.Installiert) {
        if ($hasMarker) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
        $script:PawnIoByUs = $false
        return [pscustomobject]@{ Ok = $true; Text = 'PawnIO war nicht mehr installiert' }
    }
    $file = ''
    $un = $(if ($st.Ort) { [IO.Path]::Combine($st.Ort, 'uninstall.exe') } else { '' })
    if ($un -and (Test-Path -LiteralPath $un)) { $file = $un }
    else { $file = (Get-SensorToolState).PawnIoSetup }
    if (-not $file) { return [pscustomobject]@{ Ok = $false; Text = 'PawnIO konnte nicht entfernt werden: weder uninstall.exe noch PawnIO-Setup gefunden' } }
    $r = Invoke-External -File $file -Arguments '-uninstall -silent' -TimeoutSec 180 -Progress 'PawnIO-Treiber wird entfernt'
    $st = Get-PawnIoState
    if ($st.Installiert) { return [pscustomobject]@{ Ok = $false; Text = ('PawnIO ist noch installiert (Rückgabecode {0}). Von Hand entfernen: "{1}" -uninstall' -f $r.ExitCode, $file) } }
    if ($hasMarker) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
    $script:PawnIoByUs = $false
    [void](Add-ChangeRecord -Modul 'Sensoren' -Schritt 'Treiber' -Titel 'PawnIO-Treiber wieder entfernt' -Risiko 'Eingriff' -Art 'Treiber' -Ziel 'PawnIO' -Vorher 'installiert' -Nachher 'nicht installiert' -NurHinweis)
    $t = 'PawnIO wieder entfernt'
    if ($r.ExitCode -eq 3010) { $t += ' (Setup meldet: Neustart erforderlich, bis dahin ist der Treiber noch geladen)' }
    return [pscustomobject]@{ Ok = $true; Text = $t }
}

# Beim Start: Treiberreste eines abgebrochenen Laufs entfernen
function Remove-PawnIoLeftover {
    $marker = Get-PawnIoMarker
    if (-not $marker -or -not (Test-Path -LiteralPath $marker)) { return }
    $u = Uninstall-PawnIo
    if ($u) { $script:SensorNotes.Add(('Ein früherer Lauf wurde mit installiertem PawnIO-Treiber abgebrochen: {0}.' -f $u.Text)) }
}

# ---------- Sitzung ----------
function Find-NvidiaSmi {
    foreach ($p in @("$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe", "$env:windir\System32\nvidia-smi.exe")) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    return ''
}

function Open-SensorSession([switch]$Treiber, [switch]$OhneDatentraeger) {
    if ($script:Sens) { return $script:Sens }
    $s = [pscustomobject]@{ Lhm = $false; LhmVersion = ''; LhmFehler = ''; Treiber = 'nicht verwendet'; TreiberOk = $false; NvSmi = (Find-NvidiaSmi); Quellen = @(); Hinweise = New-Object System.Collections.Generic.List[string]; Geoeffnet = Get-Date; StorageCache = @(); StorageZeit = [datetime]::MinValue }
    $script:Sens = $s
    Remove-PawnIoLeftover
    $tools = Get-SensorToolState
    if (-not $SensorTypesLoaded) { $s.Hinweise.Add('Sensorroutinen nicht verfügbar (Constrained Language Mode): nur Ersatzwerte') }
    elseif ($PSVersionTable.PSEdition -eq 'Core') { $s.Hinweise.Add('LibreHardwareMonitorLib ist für .NET Framework gebaut und läuft nur unter Windows PowerShell 5.1 (LeosMinibench.exe oder .cmd): nur Ersatzwerte') }
    elseif (-not $tools.LhmBereit) {
        if (@($tools.Fehlend).Count -eq $script:LhmPins.Count) { $s.Hinweise.Add('LibreHardwareMonitor fehlt im Tools-Ordner (Seite Sensoren: Sensorwerkzeuge holen): nur Ersatzwerte') }
        else { $s.Hinweise.Add(('LibreHardwareMonitor unvollständig oder nicht freigegeben ({0}): nur Ersatzwerte' -f ($tools.Fehlend -join ', '))) }
    } else {
        $pw = Get-PawnIoState
        if ($pw.Installiert) { $s.Treiber = ('PawnIO {0} (bereits vorhanden)' -f $pw.Version); $s.TreiberOk = $true }
        elseif ($Treiber) {
            $r = Install-PawnIoTemporary
            $s.Treiber = $r.Text; $s.TreiberOk = $r.Ok
            if (-not $r.Ok) { $s.Hinweise.Add($r.Text) }
        } else { $s.Treiber = 'ohne PawnIO (CPU-Temperatur, CPU-Takt, CPU-Leistung und Mainboard-Lüfter fehlen)' }
        if ([DiagSensors]::Open($tools.LhmDll, $true, $true, $true, $true, (-not $OhneDatentraeger), $true, $false)) {
            $s.Lhm = $true; $s.LhmVersion = [DiagSensors]::LibVersion
        } else { $s.LhmFehler = [DiagSensors]::LastError; $s.Hinweise.Add(('LibreHardwareMonitor ließ sich nicht starten: {0}' -f [DiagSensors]::LastError)) }
    }
    $q = @()
    if ($s.Lhm) { $q += ('LibreHardwareMonitor {0}' -f $script:LhmVersion) }
    if ($s.NvSmi) { $q += 'nvidia-smi' }
    $q += 'Windows-Leistungszähler'; $q += 'ACPI'
    $s.Quellen = $q
    return $s
}

function Close-SensorSession {
    if (-not $script:Sens) { $u = Uninstall-PawnIo; if ($u) { $script:SensorNotes.Add($u.Text) }; return }
    if ($SensorTypesLoaded) { try { [DiagSensors]::Close() } catch { } }
    $u = Uninstall-PawnIo
    if ($u) {
        $script:Sens.Treiber = $script:Sens.Treiber + '; ' + $u.Text
        if (-not $u.Ok) { $script:ToolIssues.Add($u.Text) }
    }
    $script:Sens.Lhm = $false
}

function Get-SensorSourceText {
    $s = $script:Sens
    if (-not $s) { return 'Sensoren nicht geöffnet' }
    $t = 'Quellen: ' + ($s.Quellen -join ', ')
    if ($s.Lhm) { $t += '; Treiber: ' + $s.Treiber }
    if ($s.Hinweise.Count) { $t += '; ' + (($s.Hinweise | Select-Object -Unique) -join '; ') }
    return $t
}

# ---------- Messwerte ----------
function New-SensorReading([string]$Key, [string]$Quelle, [string]$Gruppe, [string]$Geraet, [string]$Art, [string]$Name, [string]$Einheit, $Wert, [string]$Typ = '', $TjMax = $null) {
    $w = [double]::NaN
    if ($null -ne $Wert -and "$Wert" -ne '') { try { $w = [double]$Wert } catch { } }
    $tj = [double]::NaN
    if ($null -ne $TjMax -and "$TjMax" -ne '') { try { $tj = [double]$TjMax } catch { } }
    [pscustomobject]@{ Key = $Key; Quelle = $Quelle; Gruppe = $Gruppe; Geraet = $Geraet; Art = $Art; Name = $Name; Einheit = $Einheit; Wert = $w; Typ = $Typ; TjMax = $tj }
}

# nvidia-smi --format=csv,noheader,nounits: index, name, temperature.gpu, clocks.gr, clocks.mem, power.draw, fan.speed, utilization.gpu
function ConvertFrom-NvidiaSmi([string]$Text) {
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($l in @($Text -split "`r?`n" | Where-Object { $_.Trim() })) {
        $c = @($l -split ',' | ForEach-Object { $_.Trim() })
        if ($c.Count -lt 8) { continue }
        $num = { param($v) if ($v -match '^-?\d+(\.\d+)?$') { [double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture) } else { $null } }
        $dev = $c[1]; $i = $c[0]
        $res.Add((New-SensorReading ('nvsmi/{0}/temp' -f $i) 'nvidia-smi' 'GPU' $dev 'Temperatur' 'GPU Core' '°C' (& $num $c[2]) 'GpuNvidia'))
        $res.Add((New-SensorReading ('nvsmi/{0}/clock' -f $i) 'nvidia-smi' 'GPU' $dev 'Takt' 'GPU Core' 'MHz' (& $num $c[3]) 'GpuNvidia'))
        $res.Add((New-SensorReading ('nvsmi/{0}/memclock' -f $i) 'nvidia-smi' 'GPU' $dev 'Takt' 'GPU Memory' 'MHz' (& $num $c[4]) 'GpuNvidia'))
        $res.Add((New-SensorReading ('nvsmi/{0}/power' -f $i) 'nvidia-smi' 'GPU' $dev 'Leistung' 'GPU Package' 'W' (& $num $c[5]) 'GpuNvidia'))
        $res.Add((New-SensorReading ('nvsmi/{0}/fan' -f $i) 'nvidia-smi' 'GPU' $dev 'Lüftersteuerung' 'GPU Fan' '%' (& $num $c[6]) 'GpuNvidia'))
        $res.Add((New-SensorReading ('nvsmi/{0}/load' -f $i) 'nvidia-smi' 'GPU' $dev 'Auslastung' 'GPU Core' '%' (& $num $c[7]) 'GpuNvidia'))
    }
    return $res.ToArray()
}

function Invoke-NvidiaSmi([string]$Path) {
    $r = Invoke-External -File $Path -Arguments '--query-gpu=index,name,temperature.gpu,clocks.gr,clocks.mem,power.draw,fan.speed,utilization.gpu --format=csv,noheader,nounits' -TimeoutSec 5 -Encoding ([Text.Encoding]::UTF8)
    if ($r.ExitCode -ne 0) { return '' }
    return $r.Output
}

function Get-AcpiReadings {
    $res = @()
    foreach ($z in @(Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue)) {
        $v = $null
        if ($z.HighPrecisionTemperature) { $v = $z.HighPrecisionTemperature / 10 - 273.15 } elseif ($z.Temperature) { $v = $z.Temperature - 273.15 }
        if ($null -eq $v -or $v -le 0 -or $v -ge 130) { continue }
        $n = ([string]$z.Name) -replace '^\\_TZ\.', ''
        $res += New-SensorReading ('acpi/{0}' -f $n) 'ACPI' 'Mainboard' 'ACPI-Thermalzone' 'Temperatur' $n '°C' ([math]::Round($v, 1)) 'Acpi'
    }
    return $res
}

function Get-StorageTempReadings {
    $res = @()
    try {
        foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop)) {
            $c = $null; try { $c = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
            if ($c -and $c.Temperature -gt 0) { $res += New-SensorReading ('win/disk/{0}/temp' -f $d.DeviceId) 'Windows' 'Datenträger' ([string]$d.FriendlyName).Trim() 'Temperatur' 'Temperatur' '°C' $c.Temperature 'Storage' }
        }
    } catch { }
    return $res
}

function Get-BatteryReadings {
    $res = @()
    try {
        foreach ($b in @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop)) {
            $n = 'Akku'
            if ($b.Voltage) { $res += New-SensorReading 'wmi/akku/spannung' 'WMI' 'Akku' $n 'Spannung' 'Spannung' 'V' ([math]::Round($b.Voltage / 1000.0, 3)) 'Battery' }
            if ($b.DischargeRate) { $res += New-SensorReading 'wmi/akku/entladen' 'WMI' 'Akku' $n 'Leistung' 'Entladeleistung' 'W' ([math]::Round($b.DischargeRate / 1000.0, 2)) 'Battery' }
            if ($b.ChargeRate) { $res += New-SensorReading 'wmi/akku/laden' 'WMI' 'Akku' $n 'Leistung' 'Ladeleistung' 'W' ([math]::Round($b.ChargeRate / 1000.0, 2)) 'Battery' }
        }
    } catch { }
    return $res
}

function ConvertFrom-CpuSampleReadings($Sample) {
    if (-not $Sample) { return @() }
    $res = @()
    if ($Sample.MHz -gt 0) { $res += New-SensorReading 'win/cpu/takt' 'Windows' 'CPU' 'Windows-Leistungszähler' 'Takt' 'Effektiver Takt' 'MHz' $Sample.MHz 'Cpu' }
    $res += New-SensorReading 'win/cpu/last' 'Windows' 'CPU' 'Windows-Leistungszähler' 'Auslastung' 'CPU gesamt' '%' $Sample.Last 'Cpu'
    if ($Sample.MaxFreq -gt 0) { $res += New-SensorReading 'win/cpu/grenze' 'Windows' 'CPU' 'Windows-Leistungszähler' 'Auslastung' 'Frequenzgrenze (% vom Maximum)' '%' $Sample.MaxFreq 'Cpu' }
    return $res
}

# Alle Werte: LibreHardwareMonitor zuerst, Ersatzquellen für das, was dort fehlt
function Get-SensorReadings([switch]$MitDatentraeger, $CpuSample = $null) {
    $s = $script:Sens
    $all = New-Object System.Collections.Generic.List[object]
    if ($s -and $s.Lhm) {
        try { foreach ($r in [DiagSensors]::Read()) { $all.Add((New-SensorReading $r.Key 'LHM' $r.Gruppe $r.Geraet $r.Art $r.Name $r.Einheit $(if ([double]::IsNaN($r.Wert)) { $null } else { $r.Wert }) '' $(if ([double]::IsNaN($r.TjMax)) { $null } else { $r.TjMax }))) } } catch { }
    }
    $has = { param($g, $a) @($all | Where-Object { $_.Gruppe -eq $g -and $_.Art -eq $a -and -not [double]::IsNaN($_.Wert) }).Count -gt 0 }
    if (-not $CpuSample) { $CpuSample = Get-CpuSample }
    foreach ($r in (ConvertFrom-CpuSampleReadings $CpuSample)) { $all.Add($r) }
    foreach ($r in (Get-AcpiReadings)) { $all.Add($r) }
    if ($s -and $s.NvSmi -and -not (& $has 'GPU' 'Temperatur')) { foreach ($r in (ConvertFrom-NvidiaSmi (Invoke-NvidiaSmi $s.NvSmi))) { $all.Add($r) } }
    if (-not (& $has 'Akku' 'Spannung')) { foreach ($r in (Get-BatteryReadings)) { $all.Add($r) } }
    if (-not (& $has 'Datenträger' 'Temperatur')) {
        # Zuverlässigkeitszähler sind langsam: höchstens alle 30 Sekunden neu lesen
        if ($s -and ($MitDatentraeger -or ((Get-Date) - $s.StorageZeit).TotalSeconds -ge 30)) { $s.StorageCache = @(Get-StorageTempReadings); $s.StorageZeit = Get-Date }
        if ($s) { foreach ($r in $s.StorageCache) { $all.Add($r) } } elseif ($MitDatentraeger) { foreach ($r in (Get-StorageTempReadings)) { $all.Add($r) } }
    }
    return , $all.ToArray()
}

# Leitwerte für Kurven, Drosselnachweis und Abbruchschwelle
function Get-SensorLead($Readings) {
    $R = @($Readings | Where-Object { $_ -and -not [double]::IsNaN([double]$_.Wert) })
    $pick = {
        param($Group, $Art, [string[]]$Names, [string]$Exclude = '', [string]$Quelle = '')
        $c = @($R | Where-Object { $_.Gruppe -eq $Group -and $_.Art -eq $Art -and (-not $Quelle -or $_.Quelle -eq $Quelle) -and (-not $Exclude -or $_.Name -notmatch $Exclude) })
        foreach ($n in $Names) { $m = @($c | Where-Object { $_.Name -eq $n }); if ($m.Count) { return $m[0] } }
        return $null
    }
    $lead = [ordered]@{ CpuTemp = $null; CpuTempQ = ''; TjMax = $null; CpuMHz = $null; CpuW = $null; CpuLoad = $null; GpuTemp = $null; GpuMHz = $null; GpuW = $null; GpuLoad = $null; Fan = $null; GpuFan = $null; DiskTemp = $null }
    # CPU-Temperatur: Package bzw. Tctl/Tdie, sonst höchster CPU-Wert, sonst ACPI-Thermalzone
    $t = & $pick 'CPU' 'Temperatur' @('CPU Package', 'Core (Tctl/Tdie)', 'Core (Tdie)', 'CCDs Max (Tdie)', 'Core (Tctl)', 'Core Max') 'Distance'
    if (-not $t) { $t = @($R | Where-Object { $_.Gruppe -eq 'CPU' -and $_.Art -eq 'Temperatur' -and $_.Name -notmatch 'Distance' } | Sort-Object Wert -Descending) | Select-Object -First 1 }
    if ($t) { $lead.CpuTemp = [math]::Round($t.Wert, 1); $lead.CpuTempQ = $t.Quelle }
    else {
        $a = @($R | Where-Object { $_.Quelle -eq 'ACPI' } | Sort-Object Wert -Descending) | Select-Object -First 1
        if ($a) { $lead.CpuTemp = [math]::Round($a.Wert, 1); $lead.CpuTempQ = 'ACPI' }
    }
    $tj = @($R | Where-Object { $_.Gruppe -eq 'CPU' -and -not [double]::IsNaN([double]$_.TjMax) -and $_.TjMax -gt 50 } | ForEach-Object { $_.TjMax } | Sort-Object -Descending) | Select-Object -First 1
    if ($tj) { $lead.TjMax = [double]$tj }
    # CPU-Takt der Sensoren: effektiver Mittelwert (AMD) oder Mittel der Kerntakte
    $ce = & $pick 'CPU' 'Takt' @('Cores (Average Effective)', 'Cores (Average)')
    if ($ce) { $lead.CpuMHz = [math]::Round($ce.Wert) }
    else {
        $cores = @($R | Where-Object { $_.Gruppe -eq 'CPU' -and $_.Art -eq 'Takt' -and $_.Quelle -eq 'LHM' -and $_.Name -match 'Core #\d+$' -and $_.Wert -gt 0 })
        if ($cores.Count) { $lead.CpuMHz = [math]::Round(($cores | Measure-Object Wert -Average).Average) }
    }
    $p = & $pick 'CPU' 'Leistung' @('CPU Package', 'Package')
    if ($p) { $lead.CpuW = [math]::Round($p.Wert, 1) }
    $l = & $pick 'CPU' 'Auslastung' @('CPU Total', 'CPU gesamt')
    if ($l) { $lead.CpuLoad = [math]::Round($l.Wert) }
    # GPU: dedizierte Karte vor integrierter Grafik (Intel), sonst die mit der höchsten Leistung
    $gpus = @($R | Where-Object { $_.Gruppe -eq 'GPU' } | ForEach-Object { $_.Geraet } | Select-Object -Unique)
    $dev = $null
    if ($gpus.Count -gt 1) {
        $ded = @($gpus | Where-Object { $_ -notmatch 'Intel' })
        if ($ded.Count) { $gpus = $ded }
        $dev = @($gpus | Sort-Object { $g = $_; -[double](@($R | Where-Object { $_.Geraet -eq $g -and $_.Art -eq 'Leistung' } | Measure-Object Wert -Maximum).Maximum) }) | Select-Object -First 1
    } elseif ($gpus.Count) { $dev = $gpus[0] }
    if ($dev) {
        $G = @($R | Where-Object { $_.Gruppe -eq 'GPU' -and $_.Geraet -eq $dev })
        $gp = { param($Art, [string[]]$Names) foreach ($n in $Names) { $m = @($G | Where-Object { $_.Art -eq $Art -and $_.Name -eq $n }); if ($m.Count) { return $m[0] } }; return $null }
        $x = & $gp 'Temperatur' @('GPU Core', 'GPU Temperature'); if (-not $x) { $x = @($G | Where-Object { $_.Art -eq 'Temperatur' -and $_.Name -notmatch 'Hot Spot|Memory|Junction' }) | Select-Object -First 1 }
        if ($x) { $lead.GpuTemp = [math]::Round($x.Wert, 1) }
        $x = & $gp 'Takt' @('GPU Core'); if ($x) { $lead.GpuMHz = [math]::Round($x.Wert) }
        $x = & $gp 'Leistung' @('GPU Package', 'GPU Power', 'GPU Total', 'GPU Core'); if (-not $x) { $x = @($G | Where-Object { $_.Art -eq 'Leistung' } | Sort-Object Wert -Descending) | Select-Object -First 1 }
        if ($x) { $lead.GpuW = [math]::Round($x.Wert, 1) }
        $x = & $gp 'Auslastung' @('GPU Core'); if ($x) { $lead.GpuLoad = [math]::Round($x.Wert) }
        $x = @($G | Where-Object { $_.Art -eq 'Lüfter' } | Sort-Object Wert -Descending) | Select-Object -First 1; if ($x) { $lead.GpuFan = [math]::Round($x.Wert) }
    }
    # Lüfter: CPU-Lüfter, sonst schnellster Mainboard-Lüfter
    $fans = @($R | Where-Object { $_.Gruppe -eq 'Mainboard' -and $_.Art -eq 'Lüfter' })
    $f = @($fans | Where-Object { $_.Name -match 'CPU' } | Sort-Object Wert -Descending) | Select-Object -First 1
    if (-not $f) { $f = @($fans | Sort-Object Wert -Descending) | Select-Object -First 1 }
    if ($f) { $lead.Fan = [math]::Round($f.Wert) }
    $d = @($R | Where-Object { $_.Gruppe -eq 'Datenträger' -and $_.Art -eq 'Temperatur' } | Sort-Object Wert -Descending) | Select-Object -First 1
    if ($d) { $lead.DiskTemp = [math]::Round($d.Wert, 1) }
    return [pscustomobject]$lead
}

# Zahl für die Oberfläche (Punkt als Dezimaltrennzeichen, leer bei fehlendem Wert)
function Format-SensorValue($v) {
    if ($null -eq $v) { return '' }
    $d = [double]$v
    if ([double]::IsNaN($d)) { return '' }
    return $d.ToString('0.###', $script:Inv)
}

function Send-SensorLead($T, $Lead) {
    Send-GuiEvent 'SENSLEAD' ([int]$T) (Format-SensorValue $Lead.CpuTemp) (Format-SensorValue $Lead.CpuMHz) (Format-SensorValue $Lead.CpuW) (Format-SensorValue $Lead.GpuTemp) (Format-SensorValue $Lead.GpuMHz) (Format-SensorValue $Lead.GpuW) (Format-SensorValue $Lead.Fan) (Format-SensorValue $Lead.CpuLoad)
}

# ---------- Auswertung ----------
# Schwelle aus der Einstellung: 'aus' oder 0 = keine, 'auto' = TjMax (sonst 100 °C), Zahl = fest
function Get-AbortLimit([string]$Setting, $TjMax = $null, [double]$AutoFallback = 100) {
    $s = ([string]$Setting).Trim().ToLowerInvariant()
    if (-not $s -or $s -eq 'aus' -or $s -eq '0') { return 0 }
    if ($s -eq 'auto') { if ($TjMax -and [double]$TjMax -gt 50) { return [double]$TjMax } else { return $AutoFallback } }
    $v = 0.0
    if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -ge 40 -and $v -le 125) { return $v }
    return 0
}

# Abbruch, wenn die Temperatur in den letzten -Hold Messpunkten durchgehend auf oder über der Schwelle lag.
# -CpuHold gilt für die CPU (0 = wie -Hold): Bei automatischer Schwelle (TjMax) erst nach rund einer Minute, weil viele
# Notebooks unter Volllast planmäßig an TjMax laufen und der Drosselnachweis genug Messpunkte braucht.
# ACPI-Werte zählen nur, wenn sie sich während des Tests bewegt haben (sonst Festwert der Firmware).
function Test-LoadAbort($Samples, [double]$CpuLimit, [double]$GpuLimit, [int]$Hold = 3, [int]$CpuHold = 0) {
    $s = @($Samples)
    $none = [pscustomobject]@{ Abbruch = $false; Grund = ''; Art = ''; Wert = $null }
    if ($Hold -lt 1) { return $none }
    $ch = $(if ($CpuHold -gt 0) { $CpuHold } else { $Hold })
    if ($CpuLimit -gt 0 -and $s.Count -ge $ch) {
        $last = @($s | Select-Object -Last $ch)
        $acpiMoved = @($s | Where-Object { $_.CpuTempQ -eq 'ACPI' -and $null -ne $_.CpuTemp } | ForEach-Object { $_.CpuTemp } | Select-Object -Unique).Count -gt 1
        $ok = @($last | Where-Object { $null -ne $_.CpuTemp -and [double]$_.CpuTemp -ge $CpuLimit -and ($_.CpuTempQ -ne 'ACPI' -or $acpiMoved) }).Count -eq $ch
        if ($ok) { $m = ($last | Measure-Object CpuTemp -Maximum).Maximum; return [pscustomobject]@{ Abbruch = $true; Art = 'CPU'; Wert = $m; Grund = ('CPU-Temperatur {0:N0} °C erreichte die Abbruchschwelle von {1:N0} °C' -f $m, $CpuLimit) } }
    }
    if ($GpuLimit -gt 0 -and $s.Count -ge $Hold) {
        $last = @($s | Select-Object -Last $Hold)
        $ok = @($last | Where-Object { $null -ne $_.GpuTemp -and [double]$_.GpuTemp -ge $GpuLimit }).Count -eq $Hold
        if ($ok) { $m = ($last | Measure-Object GpuTemp -Maximum).Maximum; return [pscustomobject]@{ Abbruch = $true; Art = 'GPU'; Wert = $m; Grund = ('GPU-Temperatur {0:N0} °C erreichte die Abbruchschwelle von {1:N0} °C' -f $m, $GpuLimit) } }
    }
    return $none
}

# Drosselnachweis aus dem Verlauf unter CPU-Last. Belegt wird mit Zahlen, nicht vermutet:
#   thermisch        Takt fällt, während die Temperatur an der Grenze liegt (TjMax bzw. 95 °C, wenn TjMax unbekannt)
#   Leistungsgrenze  Takt fällt mit der Paketleistung, die Temperatur bleibt mit Abstand unter der Grenze (PL1/PL2, PPT)
#   Firmware         Windows meldet eine Frequenzgrenze unter 100 % oder Ereignis 37 (Kernel-Processor-Power) ohne Temperaturbeleg
#   unklar           Takt fällt ohne erkennbaren Grund (Energieplan, Strombegrenzung, Spannungswandler)
# Rückgabe: Status (keine, thermisch, Leistungsgrenze, Firmware, unklar, nicht bewertbar), Kennzahlen, Belege und Befund.
function Get-ThrottleAnalysis {
    param($Samples, $TjMax = $null, [int]$FirmwareEvents = 0, [int]$WarmupSec = 10)
    $res = [ordered]@{ Status = 'nicht bewertbar'; Stufe = ''; Befund = ''; TaktQuelle = ''; TaktStart = $null; TaktEnde = $null; Abfall = $null
        TempMax = $null; TempQuelle = ''; Grenze = $null; GrenzeQuelle = ''; AnteilAnGrenze = $null; LeistungStart = $null; LeistungEnde = $null; FrequenzgrenzeMin = $null; Beginn = $null; Belege = @() }
    $s = @($Samples | Where-Object { $_.Cpu -and $_.T -ge $WarmupSec })
    if ($s.Count -lt 8) { $res.Befund = 'zu wenige Messpunkte unter CPU-Last'; return [pscustomobject]$res }
    # Taktquelle: Windows-Leistungszähler, wenn er sich bewegt, sonst Sensortakt
    $winVar = @($s | ForEach-Object { $_.MHz } | Where-Object { $_ -gt 0 } | Select-Object -Unique).Count -gt 1
    $sensOk = @($s | Where-Object { $_.CpuMHz -gt 0 }).Count -ge [math]::Ceiling($s.Count * 0.8)
    $clk = $(if ($winVar) { 'MHz' } elseif ($sensOk) { 'CpuMHz' } else { '' })
    $res.TaktQuelle = $(if ($clk -eq 'MHz') { 'Windows-Leistungszähler' } elseif ($clk) { 'Sensoren (LibreHardwareMonitor)' } else { '' })
    if (-not $clk) { $res.Befund = 'kein veränderlicher Taktwert verfügbar'; return [pscustomobject]$res }
    $n = $s.Count
    # Anfangsfenster: erste 15 %, höchstens 20 Messpunkte (rund 1 Minute), damit eine frühe Drosselung bei langen Tests
    # nicht im Anfangswert verschwindet; Endfenster: letztes Viertel
    $qs = [math]::Min(20, [math]::Max(3, [int][math]::Ceiling($n * 0.15))); $qe = [math]::Max(3, [int][math]::Ceiling($n * 0.25))
    $first = @($s | Select-Object -First $qs); $lastW = @($s | Select-Object -Last $qe)
    $avg = { param($set, $prop) $v = @($set | ForEach-Object { $_.$prop } | Where-Object { $null -ne $_ -and [double]$_ -gt 0 }); if ($v.Count) { [double](($v | Measure-Object -Average).Average) } else { $null } }
    $c0 = & $avg $first $clk; $c1 = & $avg $lastW $clk
    if (-not $c0 -or -not $c1) { $res.Befund = 'Taktwerte unvollständig'; return [pscustomobject]$res }
    $drop = ($c0 - $c1) / $c0 * 100
    $res.TaktStart = [math]::Round($c0); $res.TaktEnde = [math]::Round($c1); $res.Abfall = [math]::Round($drop, 1)
    # Temperatur: echte Sensorwerte; ACPI nur, wenn veränderlich
    $tv = @($s | Where-Object { $null -ne $_.CpuTemp })
    $acpiOnly = $tv.Count -and -not @($tv | Where-Object { $_.CpuTempQ -ne 'ACPI' }).Count
    if ($acpiOnly -and @($tv | ForEach-Object { $_.CpuTemp } | Select-Object -Unique).Count -le 1) { $tv = @() }
    $hasTemp = $tv.Count -ge [math]::Ceiling($n * 0.5)
    if ($hasTemp) { $res.TempMax = [math]::Round([double](($tv | Measure-Object CpuTemp -Maximum).Maximum), 1); $res.TempQuelle = $(if ($acpiOnly) { 'ACPI-Thermalzone' } else { 'Sensoren' }) }
    $lim = $(if ($TjMax -and [double]$TjMax -gt 50) { [double]$TjMax } else { 95.0 })
    $res.Grenze = $lim; $res.GrenzeQuelle = $(if ($TjMax -and [double]$TjMax -gt 50) { 'TjMax laut CPU' } else { 'Annahme 95 °C (TjMax unbekannt)' })
    $near = $lim - 5
    $hot = @(); $atLimShare = 0.0
    if ($hasTemp) {
        $hot = @($tv | Where-Object { [double]$_.CpuTemp -ge $near })
        $atLimShare = $hot.Count / [double]$tv.Count
        $res.AnteilAnGrenze = [math]::Round($atLimShare * 100)
    }
    $p0 = & $avg $first 'CpuW'; $p1 = & $avg $lastW 'CpuW'
    if ($p0) { $res.LeistungStart = [math]::Round($p0, 1) }; if ($p1) { $res.LeistungEnde = [math]::Round($p1, 1) }
    $fl = @($s | Where-Object { $_.MaxFreq -gt 0 } | ForEach-Object { [int]$_.MaxFreq })
    if ($fl.Count) { $res.FrequenzgrenzeMin = ($fl | Measure-Object -Minimum).Minimum }
    # Beginn: erster Messpunkt, ab dem der Takt dauerhaft mehr als 5 % unter dem Anfangswert liegt
    # ein Durchlauf von hinten mit laufender Summe; Messpunkte ohne Taktwert zählen nicht
    $sufSum = New-Object 'double[]' ($n + 1); $sufCnt = New-Object 'int[]' ($n + 1)
    for ($i = $n - 1; $i -ge 0; $i--) {
        $v = $s[$i].$clk; $ok = ($null -ne $v -and [double]$v -gt 0)
        $sufSum[$i] = $sufSum[$i + 1] + $(if ($ok) { [double]$v } else { 0 }); $sufCnt[$i] = $sufCnt[$i + 1] + $(if ($ok) { 1 } else { 0 })
    }
    for ($i = 0; $i -lt $n; $i++) {
        $v = $s[$i].$clk
        if ($null -eq $v -or [double]$v -le 0 -or -not $sufCnt[$i]) { continue }
        if ([double]$v -le $c0 * 0.95 -and ($sufSum[$i] / $sufCnt[$i]) -le $c0 * 0.95) { $res.Beginn = [int]$s[$i].T; break }
    }
    $bel = New-Object System.Collections.Generic.List[string]
    $bel.Add(('Takt ({0}): Ø {1:N0} MHz zu Beginn, Ø {2:N0} MHz im letzten Viertel ({3:+0.0;-0.0;0} %)' -f $res.TaktQuelle, $c0, $c1, -$drop))
    if ($hasTemp) { $bel.Add(('Temperatur ({0}): max {1:N0} °C, Grenze {2:N0} °C ({3}), {4} % der Messpunkte ab {5:N0} °C' -f $res.TempQuelle, $res.TempMax, $lim, $res.GrenzeQuelle, $res.AnteilAnGrenze, $near)) }
    else { $bel.Add('Temperatur: keine echte CPU-Temperatur verfügbar (ohne PawnIO-Treiber liefert LibreHardwareMonitor keine CPU-Werte)') }
    if ($p0 -and $p1) { $bel.Add(('Paketleistung: Ø {0:N0} W zu Beginn, Ø {1:N0} W am Ende' -f $p0, $p1)) }
    if ($null -ne $res.FrequenzgrenzeMin -and $res.FrequenzgrenzeMin -lt 100) { $bel.Add(('Windows meldet eine Frequenzgrenze bis hinab auf {0} % des Maximums' -f $res.FrequenzgrenzeMin)) }
    if ($FirmwareEvents -gt 0) { $bel.Add(('{0} Ereignisse 37 (Kernel-Processor-Power): Firmware hat den Takt begrenzt' -f $FirmwareEvents)) }
    $res.Belege = $bel.ToArray()

    $fwLimit = ($FirmwareEvents -gt 0) -or ($null -ne $res.FrequenzgrenzeMin -and $res.FrequenzgrenzeMin -lt 95)
    $powerDrop = ($p0 -and $p1 -and $p0 -gt 0 -and (($p0 - $p1) / $p0) -ge 0.12)
    $thermal = $hasTemp -and $atLimShare -ge 0.2
    if ($drop -lt 5 -and -not ($thermal -and $drop -ge 3)) {
        $res.Status = 'keine'
        $res.Befund = $(if ($hasTemp) { 'keine Drosselung: Takt stabil (Abfall {0:N1} %), Temperatur max {1:N0} °C' -f $drop, $res.TempMax } else { 'keine Drosselung: Takt stabil (Abfall {0:N1} %)' -f $drop })
        return [pscustomobject]$res
    }
    if ($thermal) {
        $res.Status = 'thermisch'; $res.Stufe = 'WARNUNG'
        $res.Befund = ('Thermische Drosselung belegt: Der CPU-Takt fällt unter Dauerlast um {0:N0} % (Ø {1:N0} auf {2:N0} MHz), während die CPU-Temperatur {3} % der Zeit an der Grenze liegt (max {4:N0} °C, Grenze {5:N0} °C). Kühler, Lüfter, Wärmeleitpaste und Staub prüfen.' -f $drop, $c0, $c1, $res.AnteilAnGrenze, $res.TempMax, $lim)
    } elseif ($powerDrop -and (-not $hasTemp -or $res.TempMax -lt $near)) {
        $res.Status = 'Leistungsgrenze'; $res.Stufe = 'INFO'
        $res.Befund = ('Leistungsgrenze statt Hitze: Der CPU-Takt fällt um {0:N0} %, zugleich sinkt die Paketleistung von {1:N0} auf {2:N0} W{3}. Typisch für das Ende des Kurzzeit-Boosts (PL2 auf PL1 bzw. PPT); kein Kühlungsproblem.' -f $drop, $p0, $p1, $(if ($hasTemp) { ', die Temperatur bleibt bei max {0:N0} °C' -f $res.TempMax } else { '' }))
    } elseif ($fwLimit) {
        $res.Status = 'Firmware'; $res.Stufe = $(if ($drop -ge 10) { 'WARNUNG' } else { 'INFO' })
        $res.Befund = ('Der CPU-Takt fällt um {0:N0} %, Windows meldet eine Begrenzung durch die Firmware{1}. Ursache kann Temperatur, Leistungs- oder Stromgrenze sein{2}.' -f $drop, $(if ($null -ne $res.FrequenzgrenzeMin -and $res.FrequenzgrenzeMin -lt 100) { ' (Frequenzgrenze bis {0} %)' -f $res.FrequenzgrenzeMin } else { '' }), $(if (-not $hasTemp) { '; für die Unterscheidung CPU-Temperaturen mit PawnIO-Treiber messen' } else { '' }))
    } else {
        $res.Status = 'unklar'; $res.Stufe = $(if ($drop -ge 10) { 'WARNUNG' } else { 'INFO' })
        $res.Befund = ('Der CPU-Takt fällt unter Dauerlast um {0:N0} % (Ø {1:N0} auf {2:N0} MHz){3}. Energieplan, Stromgrenzen und Spannungswandler prüfen{4}.' -f $drop, $c0, $c1, $(if ($hasTemp) { ' ohne Temperaturbeleg (max {0:N0} °C)' -f $res.TempMax } else { '' }), $(if (-not $hasTemp) { '; ohne CPU-Temperatur ist thermische Drosselung nicht auszuschließen' } else { '' }))
    }
    return [pscustomobject]$res
}

# Momentaufnahme für die Diagnose: Werte im Leerlauf mit Plausibilitätsprüfung
function Get-SensorSnapshotFindings($Readings, $Lead) {
    $f = New-Object System.Collections.Generic.List[object]
    $add = { param($lvl, $txt) $f.Add([pscustomobject]@{ Stufe = $lvl; Text = $txt }) }
    if ($null -ne $Lead.CpuTemp -and $Lead.CpuTempQ -ne 'ACPI') {
        if ($Lead.CpuTemp -ge 80) { & $add 'WARNUNG' ('CPU-Temperatur im Leerlauf {0:N0} °C: Kühlung prüfen (Lüfter, Staub, Wärmeleitpaste) oder Hintergrundlast suchen.' -f $Lead.CpuTemp) }
        elseif ($Lead.CpuTemp -ge 70) { & $add 'INFO' ('CPU-Temperatur im Leerlauf {0:N0} °C, etwas hoch.' -f $Lead.CpuTemp) }
    }
    if ($null -ne $Lead.GpuTemp -and $Lead.GpuTemp -ge 80) { & $add 'WARNUNG' ('GPU-Temperatur im Leerlauf {0:N0} °C: Grafikkartenlüfter und Gehäusebelüftung prüfen.' -f $Lead.GpuTemp) }
    $cpuFan = @($Readings | Where-Object { $_.Gruppe -eq 'Mainboard' -and $_.Art -eq 'Lüfter' -and $_.Name -match 'CPU' -and -not [double]::IsNaN([double]$_.Wert) })
    if ($cpuFan.Count -and -not @($cpuFan | Where-Object { $_.Wert -gt 0 }).Count -and $null -ne $Lead.CpuTemp -and $Lead.CpuTemp -ge 60) {
        & $add 'WARNUNG' ('Der CPU-Lüfteranschluss meldet 0 U/min bei {0:N0} °C: Lüfter angeschlossen und dreht er?' -f $Lead.CpuTemp)
    }
    return $f.ToArray()
}
#endregion
# =====================================================================================
#                          SENSOREN: Werkzeuge holen und Live-Ansicht
# =====================================================================================
# Beide Modi startet die Oberfläche als eigenen Arbeitsprozess (-EventMode). Es entsteht kein Berichtsordner.

# Sensorwerkzeuge aus den offiziellen Releases holen (Seite Sensoren, Schaltfläche "Sensorwerkzeuge holen")
if ($SensorWerkzeugeHolen) {
    $r = Install-SensorTools
    foreach ($m in $r.Meldungen) { Write-Host $m }
    foreach ($t in @($script:ToolIssues | Select-Object -Unique)) { Write-Host ('WARNUNG: ' + $t) }
    Send-GuiEvent 'RESULT' $(if ($r.Ok) { '1' } else { '0' })
    exit $(if ($r.Ok) { 0 } else { 1 })
}

# Treiberrest entfernen (die Oberfläche ruft das nach einem abgebrochenen Lauf und beim Schließen auf, wenn die
# Markierung Laufzeit\PawnIO_<PC>.txt noch da ist)
if ($SensorAufraeumen) {
    Remove-PawnIoLeftover
    $msg = @($script:SensorNotes | Select-Object -Unique)
    foreach ($m in $msg) { Write-Host $m }
    if (-not $msg.Count) { Write-Host 'Kein Treiberrest von Leos Minibench gefunden.' }
    $marker = Get-PawnIoMarker
    Send-GuiEvent 'RESULT' $(if ($marker -and (Test-Path -LiteralPath $marker)) { '0' } else { '1' })
    exit 0
}

# Live-Ansicht: sendet je Intervall alle Werte (@@SENSDEF einmal je Sensor, @@SENSVAL und @@SENSLEAD je Messung).
# Ende über stop.flag im Laufzeitordner (Schaltfläche "Beenden"), wenn die Oberfläche nicht mehr läuft, oder nach 12 Stunden.
# Den PawnIO-Treiber entfernt der Abschluss auch bei Abbruch über die Oberfläche; nach einem Absturz der nächste Start.
if ($SensorLive) {
    New-Item -ItemType Directory -Path $script:CpDir -Force -ErrorAction SilentlyContinue | Out-Null
    $stopFile = Join-Path $script:CpDir 'sensor.stop'
    Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
    $parentId = 0
    try { $parentId = [int](Get-CimInstance Win32_Process -Filter ('ProcessId = {0}' -f $PID) -ErrorAction Stop).ParentProcessId } catch { }
    Send-GuiEvent 'SENSINFO' 'Sensoren werden geöffnet ...'
    $sess = Open-SensorSession -Treiber:$SensorTreiber
    Send-GuiEvent 'SENSINFO' (Get-SensorSourceText)
    foreach ($n in $script:SensorNotes) { Write-Host $n }
    $idx = @{}
    $t0 = Get-Date
    $first = $true
    try {
        while ($true) {
            $tick = [Diagnostics.Stopwatch]::StartNew()
            $rd = Get-SensorReadings -MitDatentraeger:$first
            $first = $false
            $vals = New-Object System.Collections.Generic.List[string]
            foreach ($r in $rd) {
                if (-not $idx.ContainsKey($r.Key)) {
                    $idx[$r.Key] = $idx.Count
                    Send-GuiEvent 'SENSDEF' $idx[$r.Key] $r.Gruppe $r.Geraet $r.Art $r.Name $r.Einheit $r.Quelle
                }
                $v = Format-SensorValue $r.Wert
                if ($v) { $vals.Add(('{0}:{1}' -f $idx[$r.Key], $v)) }
            }
            $el = [int]((Get-Date) - $t0).TotalSeconds
            Send-GuiEvent 'SENSVAL' $el ($vals -join ';')
            Send-SensorLead $el (Get-SensorLead $rd)
            if ($el -ge 43200) { Write-Host 'Live-Ansicht nach 12 Stunden beendet.'; break }
            $stop = $false
            while ($tick.ElapsedMilliseconds -lt $SensorIntervall) {
                Start-Sleep -Milliseconds 100
                if (Test-Path -LiteralPath $stopFile) { $stop = $true; break }
            }
            if ($stop) { break }
            if ($parentId -and -not (Get-Process -Id $parentId -ErrorAction SilentlyContinue)) { break }
        }
    } finally {
        Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
        Send-GuiEvent 'SENSINFO' 'Sensoren werden geschlossen ...'
        Close-SensorSession
        Send-GuiEvent 'SENSEND' ([string]$script:Sens.Treiber)
        # leeren Laufzeitordner nicht auf dem Stick zurücklassen
        if (-not @(Get-ChildItem -LiteralPath $script:CpDir -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $script:CpDir -Force -ErrorAction SilentlyContinue }
        $rtDir = Split-Path $script:CpDir -Parent
        if ($rtDir -and (Split-Path $rtDir -Leaf) -eq 'Laufzeit' -and -not @(Get-ChildItem -LiteralPath $rtDir -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $rtDir -Force -ErrorAction SilentlyContinue }
    }
    exit 0
}
# Import älterer Ausgabeordner in die Vergleichsdatenbank (wird von der Oberfläche aufgerufen)
if ($ImportOrdner) {
    Import-LegacyFolder $ImportOrdner
    exit 0
}

# Vergleich bereits geprüfter Systeme ohne neuen Benchmark (wird von der Oberfläche aufgerufen)
if ($Vergleich) {
    $vf = ''
    try { $vf = New-CompareReport @(([string]$Vergleich) -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }) }
    catch { Write-Host ('Vergleich fehlgeschlagen: {0}' -f $_.Exception.Message) }
    if (-not $vf) { exit 1 }
    Send-GuiEvent 'RESULT' $vf
    if (-not $EventMode) { Invoke-Item -LiteralPath $vf }
    exit 0
}

# Änderungen aus dem Änderungsprotokoll zurücknehmen (Seite Änderungen der Oberfläche): -Rueckgaengig "Datei*Id;Datei*Id"
if ($Rueckgaengig) {
    $u = Invoke-ChangeUndo $Rueckgaengig
    Write-Host ('{0} Änderungen zurückgenommen, {1} nicht möglich oder übersprungen.' -f $u.Rueckgaengig, $u.Probleme)
    Send-GuiEvent 'RESULT' $u.Rueckgaengig $u.Probleme
    exit $(if ($u.Probleme) { 1 } else { 0 })
}

Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ('  LEOS MINIBENCH v{0}   {1}   {2}' -f $ScriptVersion, $env:COMPUTERNAME, (Get-Date -Format 'dd.MM.yyyy HH:mm')) -ForegroundColor Cyan
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ('  Module         : {0}' -f (Get-ModeLabel))
Write-Host ('  Ausgabeordner  : {0}' -f $OutputDir)
Write-Host ('  Datenordner    : {0}' -f $(if ($script:DataDir) { $script:DataDir } else { 'nicht verfügbar (kein beschreibbarer Ordner)' }))
Write-Host  '  Der PC bleibt benutzbar, wird aber zeitweise stark ausgelastet. Bitte nicht in den Standby schicken.'
if (-not $FullLanguage) { Write-Host '  Hinweis        : PowerShell läuft im Constrained Language Mode, Tests mit C#-Routinen entfallen.' -ForegroundColor Yellow }
Write-Host ''

Invoke-CrashAnalysis
# PawnIO-Treiber eines abgebrochenen Laufs entfernen (Markierung im Laufzeitordner)
Remove-PawnIoLeftover
Open-Checkpoint
Remove-Item (Join-Path $script:CpDir 'stop.flag') -Force -ErrorAction SilentlyContinue

$script:Smartctl = Find-Smartctl
$script:SmartInstallMsg = ''
$script:SmartLeftInstalled = $false
if (-not $script:Smartctl -and $ModDiag -and -not $AnalyzeLastRun -and -not $Kurztest -and $InstallSmartmontools) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        $wp = Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($wp) { $winget = [pscustomobject]@{ Source = $wp.FullName } }
    }
    if ($winget) {
        Write-Step 'Installiere smartmontools über winget ...'
        $r = Invoke-External -File $winget.Source -Arguments 'install --id smartmontools.smartmontools -e --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity' -TimeoutSec 600 -Progress 'smartmontools wird installiert' -ExpectedSec 90 -Encoding ([Text.Encoding]::UTF8)
        $installed = Find-Smartctl
        if ($installed -and $script:DataDir) {
            # Programmdateien in den Datenordner übernehmen und die Installation wieder entfernen, damit nichts auf dem PC bleibt
            try {
                $tools = Join-Path $script:DataDir 'Tools\smartmontools\bin'
                New-Item -ItemType Directory -Path $tools -Force -ErrorAction Stop | Out-Null
                Copy-Item -Path (Join-Path (Split-Path $installed -Parent) '*') -Destination $tools -Recurse -Force -ErrorAction Stop
                # Die übernommene Datei ins Werkzeug-Manifest eintragen; ab dann läuft nur diese Fassung
                if (-not (Register-Tool -Name 'smartctl' -Path (Join-Path $tools 'smartctl.exe') -Lizenz $script:SmartLicense -Quelle $script:SmartSource -Herkunft ('per winget geholt auf {0}' -f $env:COMPUTERNAME))) { throw 'Eintrag ins Werkzeug-Manifest (Tools.json) fehlgeschlagen' }
                $u = Invoke-External -File $winget.Source -Arguments 'uninstall --id smartmontools.smartmontools -e --silent --accept-source-agreements --disable-interactivity' -TimeoutSec 300 -Progress 'smartmontools wird wieder deinstalliert' -ExpectedSec 30 -Encoding ([Text.Encoding]::UTF8)
                $script:SmartInstallMsg = $(if ($u.ExitCode -eq 0) { 'per winget geholt, in den Datenordner übernommen und wieder deinstalliert' } else { 'per winget geholt und in den Datenordner übernommen, Deinstallation meldete Code ' + $u.ExitCode })
                $script:SmartLeftInstalled = ($u.ExitCode -ne 0)
                $installed = Find-Smartctl
            } catch { $script:SmartLeftInstalled = $true; $script:SmartInstallMsg = 'per winget installiert, Übernahme in den Datenordner fehlgeschlagen: ' + $_.Exception.Message }
        }
        $script:Smartctl = $installed
        if (-not $script:Smartctl) {
            $tail = (@(($r.Output + "`n" + $r.Error) -split "`r?`n" | ForEach-Object { ($_ -replace '[^\w\s\.,:;()\-/%]', '').Trim() } | Where-Object { $_.Length -gt 3 }) | Select-Object -Last 3) -join ' '
            $script:SmartInstallMsg = ('winget-Rückgabecode {0}{1}' -f $r.ExitCode, $(if ($tail) { ': ' + $tail } else { '' }))
            Write-Warning ('Installation von smartmontools fehlgeschlagen ({0}).' -f $script:SmartInstallMsg)
        }
    } else {
        $script:SmartInstallMsg = 'winget ist auf diesem PC nicht verfügbar'
    }
}


# =====================================================================================
#                                     DIAGNOSE
# =====================================================================================
if ($ModDiag -and -not $AnalyzeLastRun) {

Invoke-Section 'System und Betriebssystem' {
    $cs   = Get-CimCached Win32_ComputerSystem
    $os   = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimCached Win32_BIOS
    $bb   = Get-CimCached Win32_BaseBoard
    $enc  = Get-CimCached Win32_SystemEnclosure
    $cv   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $ii   = Get-WindowsInstallInfo; $script:InstallInfo = $ii
    $up   = (Get-Date) - $os.LastBootUpTime
    $fw   = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -ErrorAction SilentlyContinue).PEFirmwareType
    if (-not $fw) { if ($env:firmware_type -eq 'UEFI') { $fw = 2 } elseif ($env:firmware_type -eq 'Legacy') { $fw = 1 } }
    if (-not $fw) { try { [void](Confirm-SecureBootUEFI -ErrorAction Stop); $fw = 2 } catch [System.PlatformNotSupportedException] { $fw = 1 } catch { } }
    $chassisMap = @{ 3 = 'Desktop'; 4 = 'Low Profile Desktop'; 6 = 'Mini Tower'; 7 = 'Tower'; 8 = 'Portable'; 9 = 'Laptop'; 10 = 'Notebook'; 13 = 'All-in-One'; 14 = 'Sub-Notebook'; 30 = 'Tablet'; 31 = 'Convertible'; 32 = 'Detachable'; 35 = 'Mini PC' }
    $chassis = ($enc.ChassisTypes | ForEach-Object { if ($chassisMap.ContainsKey([int]$_)) { $chassisMap[[int]$_] } else { "Typ $_" } }) -join ', '
    $script:IsLaptop = [bool]($enc.ChassisTypes | Where-Object { $_ -in 8, 9, 10, 14, 30, 31, 32 })

    [pscustomobject][ordered]@{
        'Computername'       = $env:COMPUTERNAME
        'Domäne/Arbeitsgr.'  = $cs.Domain
        'Angemeldet'         = $cs.UserName
        'Hersteller'         = $cs.Manufacturer
        'Modell'             = $cs.Model
        'SKU'                = $cs.SystemSKUNumber
        'Seriennummer'       = $bios.SerialNumber
        'Gehäuse'            = $chassis
        'Mainboard'          = ('{0} {1} {2}' -f $bb.Manufacturer, $bb.Product, $bb.Version).Trim()
        'BIOS/UEFI'          = ('{0} {1} vom {2:dd.MM.yyyy}' -f $bios.Manufacturer, $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
        'Firmwaremodus'      = $(switch ($fw) { 1 { 'Legacy BIOS' } 2 { 'UEFI' } default { 'unbekannt' } })
        'Betriebssystem'     = ('{0} {1}' -f $os.Caption, $cv.DisplayVersion)
        'Build'              = ('{0}.{1}' -f $os.BuildNumber, $cv.UBR)
        'Architektur'        = $os.OSArchitecture
        'Sprache'            = (Get-Culture).Name
        'Erstinstallation'   = $(if ($ii.Erstinstallation) { '{0:dd.MM.yyyy} (vor {1})' -f $ii.Erstinstallation, (Format-Age $ii.AlterTage -Dativ) } else { 'unbekannt' })
        'Stand seit'         = $(if ($ii.AktuellSeit) { '{0:dd.MM.yyyy HH:mm}{1}' -f $ii.AktuellSeit, $(if ($ii.Upgrades.Count) { ' (letztes Funktionsupdate)' } else { ' (Installation)' }) })
        'Letzter Start'      = $os.LastBootUpTime
        'Laufzeit'           = ('{0} Tage {1} Std {2} Min' -f $up.Days, $up.Hours, $up.Minutes)
        'Zeitzone'           = (Get-TimeZone).DisplayName
        'Hypervisor aktiv'   = $cs.HypervisorPresent
        'PowerShell'         = $PSVersionTable.PSVersion.ToString()
    } | Out-Report -List
    $script:Facts['Computer']       = $env:COMPUTERNAME
    $script:Facts['System']         = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
    $script:Facts['Betriebssystem'] = ('{0} {1} (Build {2}.{3})' -f $os.Caption, $cv.DisplayVersion, $os.BuildNumber, $cv.UBR)
    $script:Facts['BIOS/UEFI']      = ('{0} vom {1:dd.MM.yyyy}' -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
    $script:Facts['Laufzeit']       = ('{0} Tage {1} Std seit dem letzten Start' -f $up.Days, $up.Hours)
    $script:Facts['Mainboard']      = ('{0} {1}' -f $bb.Manufacturer, $bb.Product).Trim()
    if ($ii.Erstinstallation) {
        $script:Facts['Windows installiert'] = ('{0:dd.MM.yyyy} (vor {1}){2}' -f $ii.Erstinstallation, (Format-Age $ii.AlterTage -Dativ), $(if ($ii.Upgrades.Count) { ', seitdem {0} Funktionsupdate(s), zuletzt {1:dd.MM.yyyy}' -f $ii.Upgrades.Count, $ii.AktuellSeit } else { ', seitdem kein Funktionsupdate' }))
    }
    Add-Private $bios.SerialNumber 'SERIENNR'; Add-Private $bb.SerialNumber 'SERIENNR'; Add-Private $enc.SerialNumber 'SERIENNR'
    $script:UserNames = @(@([string]$cs.UserName, [string]$env:USERNAME) | ForEach-Object { ($_ -split '\\')[-1] } | Where-Object { $_ })
    if ($cs.PartOfDomain -and $cs.Domain) { Add-Private ([string]$cs.Domain) 'DOMÄNE' }

    if ($up.TotalDays -gt 14) { Add-Finding INFO 'System' ('Seit {0} Tagen kein Neustart. Ein Neustart vor der Fehlersuche ist sinnvoll.' -f [int]$up.TotalDays) }
    if ($fw -eq 1) { Add-Finding WARNUNG 'Firmware' 'System startet im Legacy-BIOS-Modus, Windows 11 erwartet UEFI.' }
    if ($bios.ReleaseDate -and $bios.ReleaseDate -lt (Get-Date).AddYears(-3)) { Add-Finding INFO 'Firmware' ('BIOS/UEFI ist älter als 3 Jahre ({0:dd.MM.yyyy}). Update beim Hersteller prüfen.' -f $bios.ReleaseDate) }

    Add-Sub 'Windows-Installation'
    if ($ii.Erstinstallation) {
        Add-Line ('  Erstinstallation      : {0:dd.MM.yyyy HH:mm} (vor {1})' -f $ii.Erstinstallation, (Format-Age $ii.AlterTage -Dativ))
        Add-Line ('  Aktueller Stand seit  : {0:dd.MM.yyyy HH:mm}{1}' -f $ii.AktuellSeit, $(if ($ii.Upgrades.Count) { ' (Funktionsupdate oder Inplace-Upgrade)' } else { ' (seit der Installation kein Funktionsupdate)' }))
        if ($ii.WindowsOld) { Add-Line ('  Windows.old vorhanden : angelegt am {0:dd.MM.yyyy}' -f $ii.WindowsOld) }
        if ($ii.Upgrades.Count) {
            Add-Line '  Frühere Stände (Registrierung HKLM\SYSTEM\Setup\Source OS):'
            $ii.Upgrades | Select-Object @{n = 'Installiert'; e = { $_.Installiert.ToString('dd.MM.yyyy') } }, @{n = 'Ersetzt am'; e = { if ($_.Ersetzt) { $_.Ersetzt.ToString('dd.MM.yyyy') } } }, Produkt, Version, Build | Out-Report
        }
        if ($ii.AlterTage -lt 3) { Add-Finding INFO 'System' ('Windows wurde vor {0} frisch installiert. Treiber und Updates sind eventuell noch unvollständig.' -f (Format-Age $ii.AlterTage -Dativ)) }
        elseif ($ii.AlterTage -gt 5 * 365.25) { Add-Finding INFO 'System' ('Die Windows-Installation ist {0} alt (Erstinstallation {1:dd.MM.yyyy}, seitdem {2} Funktionsupdates). Bei hartnäckigen Problemen ist eine Neuinstallation eine Option.' -f (Format-Age $ii.AlterTage), $ii.Erstinstallation, $ii.Upgrades.Count) }
    } else { Add-Line '  Installationsdatum nicht ermittelbar.' }

    Add-Sub 'Aktivierung'
    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" -ErrorAction Stop
        foreach ($l in @($lic)) { Add-Private ([string]$l.PartialProductKey) 'SCHLÜSSEL' }
        $licMap = @{ 0 = 'Nicht lizenziert'; 1 = 'Lizenziert'; 2 = 'OOB-Toleranz'; 3 = 'OOT-Toleranz'; 4 = 'Nicht-Original-Toleranz'; 5 = 'Benachrichtigung'; 6 = 'Erweiterte Toleranz' }
        $lic | Select-Object Name, @{n = 'Status'; e = { $licMap[[int]$_.LicenseStatus] } }, @{n = 'Kanal'; e = { $_.ProductKeyChannel } }, @{n = 'Schlüssel (Ende)'; e = { $_.PartialProductKey } } | Out-Report
        if (-not ($lic | Where-Object LicenseStatus -eq 1)) { Add-Finding WARNUNG 'Lizenz' 'Windows ist nicht aktiviert.' }
        if (($lic | Where-Object { $_.ProductKeyChannel -match 'GVLK' }) -and -not $cs.PartOfDomain) {
            Add-Finding WARNUNG 'Lizenz' 'Windows ist per KMS-Volumenlizenz (GVLK) aktiviert, obwohl der PC in keiner Domäne ist. Das deutet auf eine inoffizielle Aktivierung hin, Lizenz prüfen.'
        }
    } catch { Add-Line '  Aktivierungsstatus nicht abrufbar.' }

    Add-Sub 'Neustart ausstehend'
    $pend = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pend += 'Komponentenwartung (CBS)' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pend += 'Windows Update' }
    $pfr = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($pend.Count) { Add-Line ('  Ja: {0}' -f ($pend -join ', ')); Add-Finding WARNUNG 'System' ('Neustart ausstehend ({0}).' -f ($pend -join ', ')) }
    else { Add-Line '  Kein Neustart durch Updates ausstehend.' }
    if ($pfr) { Add-Line ('  Ausstehende Dateiumbenennungen: {0} Einträge' -f @($pfr).Count) }

    if (-not $Kurztest) { try { Get-ComputerInfo | Out-File (Join-Path $RawDir 'ComputerInfo.txt') -Width 300 -Encoding UTF8 } catch { } }
}

Invoke-Section 'Sicherheit, TPM, Secure Boot, BitLocker' {
    $sec = [ordered]@{}
    try   { $sec['Secure Boot'] = $(if (Confirm-SecureBootUEFI -ErrorAction Stop) { 'aktiv' } else { 'AUS' }) }
    catch { $sec['Secure Boot'] = 'nicht unterstützt / Legacy' }
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        $tpmW = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue
        $sec['TPM vorhanden']   = $tpm.TpmPresent
        $sec['TPM bereit']      = $tpm.TpmReady
        $sec['TPM Version']     = $(if ($tpmW) { ($tpmW.SpecVersion -split ',')[0] } else { '' })
        $sec['TPM Hersteller']  = ('{0} {1}' -f $tpm.ManufacturerIdTxt, $tpm.ManufacturerVersion)
        if (-not $tpm.TpmReady) { Add-Finding WARNUNG 'Sicherheit' 'TPM ist nicht bereit oder nicht vorhanden.' }
    } catch { $sec['TPM'] = 'nicht abrufbar' }
    $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue).EnableLUA
    $sec['UAC aktiv'] = ($uac -eq 1)
    $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    if ($dg) {
        $sec['VBS Status']          = @{ 0 = 'aus'; 1 = 'konfiguriert, nicht aktiv'; 2 = 'aktiv' }[[int]$dg.VirtualizationBasedSecurityStatus]
        $sec['Credential Guard']    = ($dg.SecurityServicesRunning -contains 1)
        $sec['Speicherintegrität']  = ($dg.SecurityServicesRunning -contains 2)
    }
    [pscustomobject]$sec | Out-Report -List
    $script:Facts['Sicherheit'] = ('Secure Boot {0}, TPM {1}' -f $sec['Secure Boot'], $(if ($sec['TPM bereit']) { 'bereit (' + $sec['TPM Version'] + ')' } else { 'nicht bereit' }))
    if ($sec['Secure Boot'] -ne 'aktiv') { Add-Finding WARNUNG 'Sicherheit' ('Secure Boot: {0}.' -f $sec['Secure Boot']) }
    if ($uac -ne 1) { Add-Finding WARNUNG 'Sicherheit' 'Benutzerkontensteuerung (UAC) ist deaktiviert.' }

    Add-Sub 'BitLocker'
    try {
        Get-BitLockerVolume -ErrorAction Stop | Select-Object MountPoint, VolumeType, VolumeStatus, ProtectionStatus, EncryptionMethod,
            @{n = 'Verschl. %'; e = { $_.EncryptionPercentage } }, @{n = 'Schutzarten'; e = { ($_.KeyProtector.KeyProtectorType -join ', ') } } | Out-Report
    } catch { Add-Line '  BitLocker-Status nicht abrufbar.' }

    Add-Sub 'Virenschutz'
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $mp | Select-Object AMRunningMode, AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, IsTamperProtected,
            AntivirusSignatureVersion, AntivirusSignatureLastUpdated, AntivirusSignatureAge, QuickScanEndTime, FullScanEndTime | Out-Report -List
        $script:DefenderActive = ($mp.AMRunningMode -eq 'Normal' -or ($null -eq $mp.AMRunningMode -and $mp.RealTimeProtectionEnabled))
        if ($script:DefenderActive -and -not $mp.RealTimeProtectionEnabled) { Add-Finding WARNUNG 'Sicherheit' 'Defender Echtzeitschutz ist aus.' }
        if ($script:DefenderActive -and $mp.AntivirusSignatureAge -gt 7) { Add-Finding WARNUNG 'Sicherheit' ('Defender-Signaturen sind {0} Tage alt.' -f $mp.AntivirusSignatureAge) }
        $thr = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt $Since })
        if ($thr.Count) {
            Add-Line ('  Erkennungen der letzten {0} Tage: {1}' -f $EventDays, $thr.Count)
            Add-Finding WARNUNG 'Sicherheit' ('{0} Bedrohungserkennungen in den letzten {1} Tagen.' -f $thr.Count, $EventDays)
        }
    } catch { Add-Line '  Microsoft Defender Status nicht abrufbar.'; $script:DefenderActive = $false }
    $av = Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
    if ($av) {
        Add-Line '  Registrierte Virenschutzprodukte:'
        $av | ForEach-Object {
            $hex = '{0:X6}' -f [int]$_.productState
            [pscustomobject]@{ Produkt = $_.displayName; Aktiv = ($hex.Substring(2, 2) -in '10', '11'); Aktuell = ($hex.Substring(4, 2) -eq '00'); Zustand = $hex }
        } | Out-Report
    }

    Add-Sub 'Firewall'
    Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction | Out-Report
    Get-NetFirewallProfile -ErrorAction SilentlyContinue | Where-Object { -not $_.Enabled } | ForEach-Object { Add-Finding WARNUNG 'Sicherheit' ('Firewallprofil {0} ist deaktiviert.' -f $_.Name) }

    Add-Sub 'SMBv1 und lokale Administratoren'
    if ($Kurztest) { Add-Line '  SMBv1: im Kurztest übersprungen.' }
    else {
        try {
            $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
            Add-Line ('  SMBv1: {0}' -f $smb1.State)
            if ($smb1.State -eq 'Enabled') { Add-Finding WARNUNG 'Sicherheit' 'Das veraltete Protokoll SMBv1 ist aktiviert.' }
        } catch { Add-Line '  SMBv1-Status nicht abrufbar.' }
    }
    try { Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | Select-Object Name, ObjectClass, PrincipalSource | Out-Report }
    catch { Add-Line '  Mitglieder der Administratorengruppe nicht abrufbar.' }
}

Invoke-Section 'Prozessor' {
    $cpus = Get-CimCached Win32_Processor
    $cpus | ForEach-Object {
        [pscustomobject][ordered]@{
            'Name'                 = $_.Name.Trim()
            'Sockel'               = $_.SocketDesignation
            'Kerne / Threads'      = ('{0} / {1}' -f $_.NumberOfCores, $_.NumberOfLogicalProcessors)
            'Max. Takt (MHz)'      = $_.MaxClockSpeed
            'Akt. Takt (MHz)'      = $_.CurrentClockSpeed
            'L2 / L3 Cache'        = ('{0} KB / {1} KB' -f $_.L2CacheSize, $_.L3CacheSize)
            'Auslastung %'         = $_.LoadPercentage
            'Virtualisierung (FW)' = $_.VirtualizationFirmwareEnabled
            'Status'               = $_.Status
        }
    } | Out-Report -List
    if ($cpus | Where-Object { $_.VirtualizationFirmwareEnabled -eq $false }) { Add-Finding INFO 'CPU' 'Virtualisierung ist in der Firmware deaktiviert (für WSL, Hyper-V, Sandbox nötig).' }
    $script:LogicalCpus = ($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    $script:BenchShort.CPU = Get-ShortCpuName @($cpus)[0].Name
    $script:Facts['Prozessor'] = (($cpus | ForEach-Object { '{0} ({1} Kerne, {2} Threads)' -f $_.Name.Trim(), $_.NumberOfCores, $_.NumberOfLogicalProcessors }) -join '; ')
}

Invoke-Section 'Arbeitsspeicher' {
    $typeMap = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $ffMap   = @{ 8 = 'DIMM'; 12 = 'SO-DIMM'; 0 = 'unbekannt' }
    $mods = @(Get-CimCached Win32_PhysicalMemory)
    $arr  = Get-CimInstance Win32_PhysicalMemoryArray | Where-Object Use -eq 3 | Select-Object -First 1
    $os   = Get-CimInstance Win32_OperatingSystem
    $mods | ForEach-Object {
        [pscustomobject][ordered]@{
            'Steckplatz'    = ('{0} {1}' -f $_.BankLabel, $_.DeviceLocator).Trim()
            'Größe'         = Format-Size $_.Capacity
            'Typ'           = $(if ($typeMap.ContainsKey([int]$_.SMBIOSMemoryType)) { $typeMap[[int]$_.SMBIOSMemoryType] } else { $_.SMBIOSMemoryType })
            'Bauform'       = $ffMap[[int]$_.FormFactor]
            'Nenntakt'      = $_.Speed
            'Betriebstakt'  = $_.ConfiguredClockSpeed
            'Hersteller'    = $_.Manufacturer
            'Teilenummer'   = ($_.PartNumber -as [string]).Trim()
            'Seriennummer'  = $_.SerialNumber
        }
    } | Out-Report
    $total = ($mods | Measure-Object Capacity -Sum).Sum
    if ($mods.Count) {
        $m0 = $mods[0]
        $typ0 = $(if ($typeMap.ContainsKey([int]$m0.SMBIOSMemoryType)) { $typeMap[[int]$m0.SMBIOSMemoryType] } else { '' })
        $script:Facts['Arbeitsspeicher'] = ('{0} ({1}x {2} {3}, {4} MT/s)' -f (Format-Size $total), $mods.Count, (Format-Size $m0.Capacity), $typ0, $m0.ConfiguredClockSpeed)
    }
    Add-Line
    Add-Line ('  Installiert: {0} in {1} von {2} Steckplätzen, maximal unterstützt: {3}' -f (Format-Size $total), $mods.Count, $arr.MemoryDevices, (Format-Size ([double]$arr.MaxCapacityEx * 1KB)))
    $usedPct = 100 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize * 100)
    Add-Line ('  Nutzbar: {0}, frei: {1}, belegt: {2:N0} %' -f (Format-Size ($os.TotalVisibleMemorySize * 1KB)), (Format-Size ($os.FreePhysicalMemory * 1KB)), $usedPct)
    Add-Line ('  Zugesichert (Commit): {0} von {1}' -f (Format-Size (($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) * 1KB)), (Format-Size ($os.TotalVirtualMemorySize * 1KB)))
    Get-CimInstance Win32_PageFileUsage | ForEach-Object { Add-Line ('  Auslagerungsdatei {0}: {1} MB, aktuell {2} MB, Spitze {3} MB' -f $_.Name, $_.AllocatedBaseSize, $_.CurrentUsage, $_.PeakUsage) }

    if ($usedPct -gt 90) { Add-Finding WARNUNG 'RAM' ('Arbeitsspeicher zu {0:N0} % belegt.' -f $usedPct) }
    if (@($mods.Speed | Select-Object -Unique).Count -gt 1) { Add-Finding WARNUNG 'RAM' 'Module mit unterschiedlichen Nenntakten verbaut.' }
    if (@($mods.PartNumber | Select-Object -Unique).Count -gt 1) { Add-Finding INFO 'RAM' 'Gemischte RAM-Module (unterschiedliche Teilenummern).' }
    if ($mods | Where-Object { $_.ConfiguredClockSpeed -and $_.Speed -and $_.ConfiguredClockSpeed -lt $_.Speed }) { Add-Finding INFO 'RAM' 'RAM läuft unter Nenntakt (XMP/EXPO-Profil evtl. nicht aktiv oder vom Board begrenzt).' }
    if ($mods.Count -eq 1 -and $arr.MemoryDevices -ge 2) { Add-Finding INFO 'RAM' 'Nur ein Modul verbaut, vermutlich Single-Channel-Betrieb (geringere Speicherbandbreite).' }
    if ($total -lt 8GB) { Add-Finding WARNUNG 'RAM' ('Nur {0} RAM verbaut, für Windows 11 knapp.' -f (Format-Size $total)) }
    foreach ($m in $mods) { Add-Private ([string]$m.SerialNumber) 'SERIENNR' }
    if ($mods.Count) {
        $script:BenchShort.RAM = ('{0} GB {1}-{2}' -f [math]::Round($total / 1GB), $(if ($typ0) { $typ0 } else { 'RAM' }), $(if ($m0.ConfiguredClockSpeed) { $m0.ConfiguredClockSpeed } else { $m0.Speed }))
        Test-RamProfile $mods $typ0
    }
}

Invoke-Section 'Grafik und Monitore' {
    $vram = @{}
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        try { if ($p.DriverDesc -and $p.'HardwareInformation.qwMemorySize') { $vram[$p.DriverDesc] = [long]$p.'HardwareInformation.qwMemorySize' } } catch { }
    }
    Get-CimCached Win32_VideoController | ForEach-Object {
        [pscustomobject][ordered]@{
            'Name'          = $_.Name
            'VRAM'          = $(if ($vram.ContainsKey($_.Name)) { Format-Size $vram[$_.Name] } else { Format-Size $_.AdapterRAM })
            'Treiber'       = $_.DriverVersion
            'Treiberdatum'  = $(if ($_.DriverDate) { $_.DriverDate.ToString('dd.MM.yyyy') })
            'Auflösung'     = $(if ($_.CurrentHorizontalResolution) { '{0}x{1} @ {2} Hz' -f $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution, $_.CurrentRefreshRate })
            'Status'        = $_.Status
        }
    } | Out-Report -List
    Get-CimCached Win32_VideoController | Where-Object { $_.DriverDate -and $_.DriverDate -lt (Get-Date).AddYears(-2) -and $_.Name -notmatch 'Virtual|Remote|Indirect|Parsec|spacedesk' } | ForEach-Object {
        Add-Finding INFO 'Grafik' ('Grafiktreiber für {0} ist älter als 2 Jahre ({1:dd.MM.yyyy}).' -f $_.Name, $_.DriverDate)
    }
    Get-CimCached Win32_VideoController | Where-Object { $_.Name -match 'Basic Display|Standard-VGA|Microsoft Basic' } | ForEach-Object {
        Add-Finding WARNUNG 'Grafik' 'Nur der Microsoft-Standardtreiber ist aktiv, der Herstellertreiber fehlt.'
    }
    $script:Facts['Grafik'] = ((Get-CimCached Win32_VideoController | Where-Object { $_.Name -notmatch 'Virtual|Remote|Indirect|Parsec|spacedesk' } | ForEach-Object { $_.Name }) -join '; ')
    $gMain = Get-MainGpu; if ($gMain) { $script:BenchShort.GPU = Get-ShortGpuName $gMain.Name }
    Add-Sub 'Monitore'
    $dec = { param($a) if ($a) { -join ($a | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) } }
    Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue | ForEach-Object {
        $sn = (& $dec $_.SerialNumberID); Add-Private $sn 'SERIENNR'
        [pscustomobject]@{ Hersteller = (& $dec $_.ManufacturerName); Modell = (& $dec $_.UserFriendlyName); Seriennummer = $sn; Baujahr = $_.YearOfManufacture; Aktiv = $_.Active }
    } | Out-Report
}

Invoke-Section 'Datenträger und Volumes' {
    $pd = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    $pd | Sort-Object DeviceId | Select-Object DeviceId, FriendlyName, SerialNumber, MediaType, BusType, @{n = 'Größe'; e = { Format-Size $_.Size } },
        FirmwareVersion, HealthStatus, OperationalStatus | Out-Report
    $script:Facts['Datenträger'] = (($pd | Sort-Object DeviceId | ForEach-Object { '{0} ({1}, {2}, {3})' -f $_.FriendlyName, (Format-Size $_.Size), $_.BusType, $_.HealthStatus }) -join "`n")
    $script:DiskNames = @{}
    foreach ($d in $pd) { $script:DiskNames[[int]$d.DeviceId] = ('{0} ({1})' -f ([string]$d.FriendlyName).Trim(), $d.BusType); Add-Private ([string]$d.SerialNumber) 'SERIENNR' }
    foreach ($d in $pd) {
        if ($d.HealthStatus -ne 'Healthy') { Add-Finding KRITISCH 'Datenträger' ('{0}: Windows meldet Zustand "{1}" / {2}.' -f $d.FriendlyName, $d.HealthStatus, ($d.OperationalStatus -join ', ')) }
    }

    Add-Sub 'Zuverlässigkeitszähler (Windows Storage)'
    $rel = foreach ($d in $pd) {
        $c = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($c) {
            [pscustomobject][ordered]@{
                'Laufwerk'       = $d.FriendlyName
                'Temp °C'        = $c.Temperature
                'Temp max °C'    = $c.TemperatureMax
                'Verschleiß %'   = $c.Wear
                'Betriebsstd.'   = $c.PowerOnHours
                'Lesefehler'     = $(if ($null -ne $c.ReadErrorsTotal) { '{0} / {1} unkorr.' -f $c.ReadErrorsTotal, $c.ReadErrorsUncorrected } else { 'n/v' })
                'Schreibfehler'  = $(if ($null -ne $c.WriteErrorsTotal) { '{0} / {1} unkorr.' -f $c.WriteErrorsTotal, $c.WriteErrorsUncorrected } else { 'n/v' })
                'Start/Stopp'    = $c.StartStopCycleCount
                'Latenz max ms'  = ('{0} / {1}' -f $c.ReadLatencyMax, $c.WriteLatencyMax)
            }
            if ($c.Wear -ge 90) { Add-Finding KRITISCH 'Datenträger' ('{0}: Verschleiß {1} %.' -f $d.FriendlyName, $c.Wear) }
            elseif ($c.Wear -ge 70) { Add-Finding WARNUNG 'Datenträger' ('{0}: Verschleiß {1} %.' -f $d.FriendlyName, $c.Wear) }
            if ($c.Temperature -ge 65) { Add-Finding WARNUNG 'Datenträger' ('{0}: Temperatur {1} °C.' -f $d.FriendlyName, $c.Temperature) }
            if (($c.ReadErrorsUncorrected + $c.WriteErrorsUncorrected) -gt 0) { Add-Finding KRITISCH 'Datenträger' ('{0}: {1} unkorrigierbare Lese-/Schreibfehler.' -f $d.FriendlyName, ($c.ReadErrorsUncorrected + $c.WriteErrorsUncorrected)) }
        }
    }
    $rel | Out-Report

    Add-Sub 'Ausfallvorhersage (SMART über Windows)'
    Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PredictFailure) { Add-Finding KRITISCH 'Datenträger' ('SMART sagt Ausfall voraus: {0}' -f $_.InstanceName) }
        [pscustomobject]@{ Instanz = $_.InstanceName; 'Ausfall vorhergesagt' = $_.PredictFailure; Grund = $_.Reason }
    } | Out-Report

    Add-Sub 'Partitionsschema'
    Get-Disk -ErrorAction SilentlyContinue | Sort-Object Number | Select-Object Number, FriendlyName, PartitionStyle, @{n = 'Größe'; e = { Format-Size $_.Size } },
        IsBoot, IsSystem, IsOffline, IsReadOnly, NumberOfPartitions | Out-Report

    Add-Sub 'Volumes'
    $vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.Size -gt 0 }
    $vols | Sort-Object DriveLetter | ForEach-Object {
        $pct = [math]::Round($_.SizeRemaining / $_.Size * 100, 1)
        if ($_.DriveType -eq 'Fixed') {
            if ($pct -lt 5)      { Add-Finding KRITISCH 'Speicherplatz' ('Laufwerk {0}: nur {1} % frei ({2}).' -f $_.DriveLetter, $pct, (Format-Size $_.SizeRemaining)) }
            elseif ($pct -lt 12) { Add-Finding WARNUNG  'Speicherplatz' ('Laufwerk {0}: nur {1} % frei ({2}).' -f $_.DriveLetter, $pct, (Format-Size $_.SizeRemaining)) }
            if ($_.HealthStatus -ne 'Healthy') { Add-Finding WARNUNG 'Dateisystem' ('Volume {0}: Zustand {1}.' -f $_.DriveLetter, $_.HealthStatus) }
        }
        [pscustomobject][ordered]@{ LW = $_.DriveLetter; Bezeichnung = $_.FileSystemLabel; Dateisystem = $_.FileSystem; Typ = $_.DriveType
            'Größe' = Format-Size $_.Size; Frei = Format-Size $_.SizeRemaining; 'Frei %' = $pct; Zustand = $_.HealthStatus }
    } | Out-Report

    Add-Sub 'TRIM und Dirty-Bit'
    $trim = Invoke-External -File 'fsutil.exe' -Arguments 'behavior query DisableDeleteNotify'
    Add-Line ('  ' + ($trim.Output.Trim() -replace "`r?`n", "`r`n  "))
    foreach ($v in ($vols | Where-Object { $_.FileSystem -eq 'NTFS' -and $_.DriveType -eq 'Fixed' })) {
        $dirty = Invoke-External -File 'fsutil.exe' -Arguments ('dirty query {0}:' -f $v.DriveLetter)
        Add-Line ('  ' + $dirty.Output.Trim())
        if ($dirty.Output -match 'NOT Dirty|nicht fehlerhaft|ist nicht') { } elseif ($dirty.Output -match 'Dirty|fehlerhaft') { Add-Finding WARNUNG 'Dateisystem' ('Volume {0}: Dirty-Bit gesetzt, chkdsk beim nächsten Start nötig.' -f $v.DriveLetter) }
    }

    Add-Sub 'Temporäre Dateien'
    foreach ($p in @($env:TEMP, "$env:windir\Temp", "$env:windir\SoftwareDistribution\Download")) {
        if ($p -and (Test-Path $p)) {
            $s = (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            Add-Line ('  {0,-60} {1}' -f $p, (Format-Size $s))
        }
    }
    if (Test-Path "$env:SystemDrive\Windows.old") { Add-Line '  Windows.old ist vorhanden (kann per Datenträgerbereinigung entfernt werden).' }
}

Invoke-Section 'SMART-Daten (smartmontools)' {
    $script:SmartDevices = @()
    if (-not $script:Smartctl) {
        Add-Line '  smartctl nicht gefunden. Nur die Windows-Werte oben sind verfügbar, ein SMART-Langtest ist so nicht möglich.'
        if ($script:SmartInstallMsg) { Add-Line ('  Automatische Installation fehlgeschlagen: {0}' -f $script:SmartInstallMsg) }
        Add-Line '  Abhilfe: winget install smartmontools.smartmontools, https://www.smartmontools.org oder smartctl.exe in den Datenordner unter Tools legen.'
        Add-Finding INFO 'SMART' ('smartmontools fehlt, daher kein SMART-Langtest und keine Detailattribute{0}. Option "smartmontools installieren" nutzen oder smartctl.exe in den Datenordner unter Tools legen.' -f $(if ($script:SmartInstallMsg) { ' (Installation fehlgeschlagen: ' + $script:SmartInstallMsg + ')' } else { '' }))
        return
    }
    $ver = Invoke-External -File $script:Smartctl -Arguments '--version'
    Add-Line ('  ' + (($ver.Output -split "`r?`n")[0]) + ('   ({0})' -f $script:Smartctl))
    $scan = Invoke-External -File $script:Smartctl -Arguments '--scan-open -j' -TimeoutSec 120
    try { $devs = @(($scan.Output | ConvertFrom-Json).devices | Where-Object { -not $_.open_error }) } catch { $devs = @() }
    if (-not $devs.Count) { Add-Line '  Keine SMART-fähigen Laufwerke gefunden (RAID-Controller oder USB-Gehäuse ohne SAT-Durchreichung?).'; return }

    $di = 0
    $skipped = [System.Collections.Generic.List[string]]::new()
    $usable = [System.Collections.Generic.List[object]]::new()
    $summary = foreach ($d in $devs) {
        $di++
        Show-Sub 'SMART-Daten auslesen' ('Laufwerk {0} von {1}: {2}' -f $di, $devs.Count, $d.name) ([int](($di - 1) / $devs.Count * 100))
        $jr = Invoke-External -File $script:Smartctl -Arguments ('-a -j -d {0} {1}' -f $d.type, $d.name) -TimeoutSec 180
        try { $j = $jr.Output | ConvertFrom-Json } catch { $j = $null }
        $model = $(if ($j.model_name) { [string]$j.model_name } elseif ($j.scsi_product) { ('{0} {1}' -f $j.scsi_vendor, $j.scsi_product).Trim() } else { [string]$d.info_name })
        # Kartenleser ohne Medium und Geräte ohne Kapazität liefern keine sinnvollen Werte
        if (-not $j -or -not ([double]$j.user_capacity.bytes -gt 0)) { $skipped.Add(('{0} ({1})' -f $model, $d.name)); continue }
        $safe = ($d.name -replace '[\\/:]', '_').Trim('_')
        $txt = Invoke-External -File $script:Smartctl -Arguments ('-x -d {0} {1}' -f $d.type, $d.name) -TimeoutSec 180
        $txt.Output | Out-File (Join-Path $RawDir ('smartctl_{0}_vorher.txt' -f $safe)) -Encoding UTF8
        Add-Private ([string]$j.serial_number) 'SERIENNR'
        # Langtest nur für ATA- und NVMe-Laufwerke mit aktivem SMART
        if ($j.device.protocol -in 'ATA', 'NVMe' -and $j.smart_support.enabled -ne $false) { $usable.Add($d) }
        Test-SmartJson -Json $j -Label ('{0} [{1}]' -f $model, $d.name)
    }
    Hide-Sub
    $script:SmartDevices = @($usable)
    $summary | Out-Report
    if ($skipped.Count) { Add-Line ('  Ohne Medium oder ohne Kapazität übersprungen: {0}' -f ($skipped -join ', ')) }
    Add-Line '  Vollständige SMART-Ausgaben je Laufwerk (smartctl -x) liegen im Anhang.'
}

Invoke-Section 'Akku' {
    $bat = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if (-not $bat.Count) { Add-Line '  Kein Akku vorhanden.'; return }
    $static = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue)
    $full   = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue)
    $cyc    = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue)
    $stat   = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue)
    for ($i = 0; $i -lt $bat.Count; $i++) {
        $design = $(if ($static.Count -gt $i) { $static[$i].DesignedCapacity })
        $fullC  = $(if ($full.Count -gt $i) { $full[$i].FullChargedCapacity })
        $health = $(if ($design -and $fullC) { [math]::Round($fullC / $design * 100, 1) })
        [pscustomobject][ordered]@{
            'Akku'                = $bat[$i].Name
            'Ladestand %'         = $bat[$i].EstimatedChargeRemaining
            'Netzteil'            = $(if ($stat.Count -gt $i) { $stat[$i].PowerOnline })
            'Designkapazität mWh' = $design
            'Volle Ladung mWh'    = $fullC
            'Gesundheit %'        = $health
            'Ladezyklen'          = $(if ($cyc.Count -gt $i) { $cyc[$i].CycleCount })
            'Hersteller'          = $(if ($static.Count -gt $i) { $static[$i].ManufactureName })
        } | Out-Report -List
        if ($health -and $health -lt 50) { Add-Finding KRITISCH 'Akku' ('Akkukapazität nur noch {0} % der Designkapazität.' -f $health) }
        elseif ($health -and $health -lt 70) { Add-Finding WARNUNG 'Akku' ('Akkukapazität nur noch {0} % der Designkapazität.' -f $health) }
    }
    $r = Invoke-External -File 'powercfg.exe' -Arguments ('/batteryreport /output "{0}" /duration 28' -f (Join-Path $RawDir 'Akkubericht.html')) -TimeoutSec 120
    Add-Line '  Ausführlicher Akkubericht: Akkubericht.html im Anhang'
}

Invoke-Section 'Sensoren (Momentaufnahme)' {
    Show-Sub 'Sensoren' 'werden geöffnet' -1
    [void](Open-SensorSession -Treiber:$SensorTreiber)
    # zwei Lesungen: Leistungs- und Taktsensoren brauchen einen Vergleichswert
    $rd = Get-SensorReadings -MitDatentraeger
    Start-Sleep -Milliseconds 1000
    $rd = Get-SensorReadings
    Hide-Sub
    $lead = Get-SensorLead $rd
    $script:SensorSnapshot = $rd
    Add-Line ('  {0}' -f (Get-SensorSourceText))
    $show = @($rd | Where-Object { -not [double]::IsNaN([double]$_.Wert) -and $_.Art -in 'Temperatur', 'Takt', 'Lüfter', 'Spannung', 'Leistung', 'Lüftersteuerung', 'Strom' -and $_.Name -notmatch 'Distance to TjMax' })
    if ($show.Count) {
        $show | Sort-Object Gruppe, Geraet, Art, Name | ForEach-Object {
            [pscustomobject][ordered]@{ Gruppe = $_.Gruppe; Gerät = $_.Geraet; Art = $_.Art; Sensor = $_.Name; Wert = ('{0} {1}' -f $(if ($_.Einheit -eq 'V') { $_.Wert.ToString('0.000', $script:Inv) } elseif ($_.Einheit -eq 'W') { $_.Wert.ToString('0.0', $script:Inv) } else { [math]::Round($_.Wert).ToString($script:Inv) }), $_.Einheit); Quelle = $_.Quelle }
        } | Out-Report
    } else { Add-Line '  Keine Sensorwerte verfügbar.' }
    Add-Line ('  Leitwerte: CPU {0}, GPU {1}, CPU-Paketleistung {2}, Lüfter {3}, Datenträger max {4}' -f $(if ($null -ne $lead.CpuTemp) { '{0:N0} °C ({1})' -f $lead.CpuTemp, $lead.CpuTempQ } else { 'n/v' }), $(if ($null -ne $lead.GpuTemp) { '{0:N0} °C' -f $lead.GpuTemp } else { 'n/v' }), $(if ($null -ne $lead.CpuW) { '{0:N1} W' -f $lead.CpuW } else { 'n/v' }), $(if ($null -ne $lead.Fan) { '{0:N0} U/min' -f $lead.Fan } else { 'n/v' }), $(if ($null -ne $lead.DiskTemp) { '{0:N0} °C' -f $lead.DiskTemp } else { 'n/v' }))
    if ($lead.CpuTempQ -eq 'ACPI') { Add-Line '  Hinweis: Die ACPI-Thermalzone ist oft ein Mainboard- oder Festwert, keine Kerntemperatur. Echte CPU-Werte liefert LibreHardwareMonitor mit PawnIO-Treiber.' }
    foreach ($f in (Get-SensorSnapshotFindings $rd $lead)) { Add-Finding $f.Stufe 'Sensoren' $f.Text }
    $script:SensorDb['Leerlauf'] = [ordered]@{ CpuTemp = $lead.CpuTemp; CpuTempQuelle = $lead.CpuTempQ; TjMax = $lead.TjMax; CpuW = $lead.CpuW; GpuTemp = $lead.GpuTemp; Luefter = $lead.Fan; DatentraegerTempMax = $lead.DiskTemp; Quelle = (Get-SensorSourceText) }
    if ($null -ne $lead.CpuTemp -and $lead.CpuTempQ -ne 'ACPI') { $script:Facts['CPU-Temperatur (Leerlauf)'] = ('{0:N0} °C{1}' -f $lead.CpuTemp, $(if ($lead.TjMax) { ', TjMax {0:N0} °C' -f $lead.TjMax } else { '' })) }
    Add-TestResult 'Sensoren' $(if ($show.Count) { 'OK' } else { 'Info' }) ('{0} Werte, {1}' -f $show.Count, ($script:Sens.Quellen -join ', '))
}

Invoke-Section 'Netzwerkkonfiguration' {
    Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Status, Name | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress, DriverVersion,
        @{n = 'Treiberdatum'; e = { $_.DriverDate } } | Out-Report
    Add-Sub 'IP-Konfiguration aktiver Adapter'
    Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.NetAdapter.Status -eq 'Up' } | ForEach-Object {
        [pscustomobject][ordered]@{
            Adapter  = $_.InterfaceAlias
            IPv4     = ($_.IPv4Address.IPAddress -join ', ')
            Gateway  = ($_.IPv4DefaultGateway.NextHop -join ', ')
            DNS      = (($_.DNSServer | Where-Object AddressFamily -eq 2).ServerAddresses -join ', ')
            IPv6     = ($_.IPv6Address.IPAddress -join ', ')
            Netzwerk = $_.NetProfile.Name
            Profil   = $_.NetProfile.NetworkCategory
        }
    } | Out-Report -List
    Add-Sub 'Adapterstatistik'
    Get-NetAdapterStatistics -ErrorAction SilentlyContinue | ForEach-Object {
        $errs = $_.ReceivedPacketErrors + $_.OutboundPacketErrors
        if ($errs -gt 100) { Add-Finding INFO 'Netzwerk' ('{0}: {1} Paketfehler seit Adapterstart.' -f $_.Name, $errs) }
        [pscustomobject]@{ Adapter = $_.Name; Empfangen = Format-Size $_.ReceivedBytes; Gesendet = Format-Size $_.SentBytes
            'Fehler Rx/Tx' = ('{0} / {1}' -f $_.ReceivedPacketErrors, $_.OutboundPacketErrors); 'Verworfen Rx/Tx' = ('{0} / {1}' -f $_.ReceivedDiscardedPackets, $_.OutboundDiscardedPackets) }
    } | Out-Report
    if ((Get-Service WlanSvc -ErrorAction SilentlyContinue).Status -eq 'Running') {
        Add-Sub 'WLAN'
        $w = Invoke-External -File 'netsh.exe' -Arguments 'wlan show interfaces'
        Add-Line (($w.Output -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { '  ' + $_.Trim() }) -join "`r`n")
    }
    Add-Sub 'Proxy (WinHTTP)'
    $px = Invoke-External -File 'netsh.exe' -Arguments 'winhttp show proxy'
    Add-Line (($px.Output -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { '  ' + $_.Trim() }) -join "`r`n")
}

Invoke-Section 'Geräte und Treiber' {
    $codes = @{ 1 = 'nicht korrekt konfiguriert'; 3 = 'Treiber beschädigt'; 10 = 'Start fehlgeschlagen'; 12 = 'Ressourcenkonflikt'; 14 = 'Neustart nötig'; 18 = 'Treiber neu installieren'
        19 = 'Registrierung fehlerhaft'; 21 = 'wird entfernt'; 22 = 'deaktiviert'; 24 = 'nicht vorhanden/fehlerhaft'; 28 = 'kein Treiber installiert'; 31 = 'Treiber lädt nicht'
        32 = 'Dienst deaktiviert'; 37 = 'Treiberinitialisierung fehlgeschlagen'; 39 = 'Treiber beschädigt/fehlt'; 41 = 'Hardware nicht gefunden'; 43 = 'Gerät meldet Fehler'; 45 = 'nicht angeschlossen'; 52 = 'Signatur ungültig' }
    $bad = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -ne 45 })
    if ($bad.Count) {
        $bad | ForEach-Object {
            $c = [int]$_.ConfigManagerErrorCode
            $lvl = $(if ($c -eq 22) { 'INFO' } else { 'WARNUNG' })
            Add-Finding $lvl 'Geräte' ('{0}: Code {1} ({2}).' -f $_.Name, $c, $codes[$c])
            [pscustomobject]@{ 'Gerät' = $_.Name; Klasse = $_.PNPClass; Code = $c; Bedeutung = $codes[$c]; ID = $_.DeviceID }
        } | Out-Report
    } else { Add-Line '  Alle Geräte ohne Fehlercode.' }

    Add-Sub 'Treiber wichtiger Geräteklassen'
    $drv = $(if ($Kurztest) { @() } else { @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue) })
    if ($Kurztest) { Add-Line '  Treiberliste im Kurztest übersprungen.' }
    $drvList = @($drv | Where-Object { $_.DeviceClass -in 'DISPLAY', 'NET', 'SCSIADAPTER', 'HDC', 'MEDIA', 'BLUETOOTH', 'USB', 'SYSTEM' -and $_.Manufacturer -notmatch '^\(Standard|^Standard |^Microsoft$' -and $_.DeviceName } |
        Sort-Object DeviceClass, DeviceName -Unique | Select-Object DeviceClass, DeviceName, DriverVersion, @{n = 'Datum'; e = { if ($_.DriverDate) { $_.DriverDate.ToString('dd.MM.yyyy') } } }, Manufacturer)
    if ($drvList.Count) {
        try { $drvList | Export-Csv -Path (Join-Path $RawDir 'Treiber.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8 } catch { }
        $drvList | Where-Object { $_.DeviceClass -in 'DISPLAY', 'NET', 'SCSIADAPTER', 'HDC' } | Out-Report
        Add-Line ('  Gesamtliste mit {0} Treibern: Treiber.csv im Anhang' -f $drvList.Count)
    }
    Add-Sub 'Unsignierte Treiber'
    $uns = @($drv | Where-Object { $_.IsSigned -eq $false -and $_.DeviceName })
    if ($uns.Count) {
        $uns | Select-Object DeviceName, DriverVersion, InfName, Manufacturer | Out-Report
        Add-Finding INFO 'Treiber' ('{0} unsignierte Treiber gefunden.' -f $uns.Count)
    } else { Add-Line '  Keine.' }
}

Invoke-Section 'Updates' {
    try {
        $au = (New-Object -ComObject Microsoft.Update.AutoUpdate).Results
        Add-Line ('  Letzte erfolgreiche Suche       : {0}' -f $au.LastSearchSuccessDate)
        Add-Line ('  Letzte erfolgreiche Installation: {0}' -f $au.LastInstallationSuccessDate)
        if ($au.LastInstallationSuccessDate -and ([datetime]$au.LastInstallationSuccessDate) -lt (Get-Date).AddDays(-45)) {
            Add-Finding WARNUNG 'Updates' ('Letzte erfolgreiche Updateinstallation am {0:dd.MM.yyyy}.' -f [datetime]$au.LastInstallationSuccessDate)
        }
    } catch { Add-Line '  Windows-Update-Status nicht abrufbar.' }

    Add-Sub 'Zuletzt installierte Updates'
    Get-HotFix -ErrorAction SilentlyContinue | Sort-Object { $_.InstalledOn -as [datetime] } -Descending | Select-Object -First 15 HotFixID, Description, InstalledOn, InstalledBy | Out-Report

    Add-Sub 'Ausstehende Updates (Suche, max. 3 Minuten)'
    if (-not $script:Opt['Updatesuche']) { Add-Line '  Nicht ausgewählt.' }
    else {
        $job = Start-Job -ScriptBlock {
            $s = New-Object -ComObject Microsoft.Update.Session
            $r = $s.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0")
            foreach ($u in $r.Updates) { [pscustomobject]@{ Titel = $u.Title; KB = ($u.KBArticleIDs -join ','); Pflicht = $u.IsMandatory; Neustart = $u.RebootRequired } }
        }
        if (Wait-JobWithProgress $job 'Suche nach ausstehenden Updates' 60 180) {
            $pu = @(Receive-Job $job -ErrorAction SilentlyContinue)
            if ($pu.Count) {
                $pu | Select-Object Titel, KB, Pflicht | Out-Report
                Add-Finding INFO 'Updates' ('{0} Updates stehen zur Installation bereit.' -f $pu.Count)
            } else { Add-Line '  Keine ausstehenden Updates gefunden (bzw. zentral verwaltet).' }
        } else { Add-Line '  Updatesuche nach 3 Minuten abgebrochen oder fehlgeschlagen.' ; Stop-Job $job -ErrorAction SilentlyContinue }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Section 'Autostart, Dienste, Prozesse' {
    Add-Sub 'Autostart-Einträge'
    Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Select-Object Name, Command, Location, User | Out-Report
    Add-Sub 'Geplante Aufgaben (nicht von Microsoft)'
    Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object {
        $i = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        [pscustomobject]@{ Aufgabe = ($_.TaskPath + $_.TaskName); Status = $_.State; 'Letzter Lauf' = $i.LastRunTime; Ergebnis = ('0x{0:X}' -f [int64]$i.LastTaskResult) }
    } | Out-Report
    Add-Sub 'Automatische Dienste, die mit Fehler beendet wurden'
    $svc = @(Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" -ErrorAction SilentlyContinue | Where-Object { $_.ExitCode -ne 0 })
    if ($svc.Count) {
        $svc | Select-Object Name, DisplayName, State, ExitCode | Out-Report
        Add-Finding INFO 'Dienste' ('{0} automatische Dienste laufen nicht und haben einen Fehlercode.' -f $svc.Count)
    } else { Add-Line '  Keine.' }
    Add-Sub 'Top 15 Prozesse nach Arbeitsspeicher'
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 Name, Id, @{n = 'RAM'; e = { Format-Size $_.WorkingSet64 } }, @{n = 'CPU s'; e = { [math]::Round($_.CPU, 0) } }, Handles | Out-Report
    Add-Sub 'Top 10 Prozesse nach CPU-Zeit'
    Get-Process | Where-Object CPU | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, @{n = 'CPU s'; e = { [math]::Round($_.CPU, 0) } }, @{n = 'RAM'; e = { Format-Size $_.WorkingSet64 } } | Out-Report
}

Invoke-Section 'Installierte Software' {
    $paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $sw = @(Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 -and -not $_.ParentKeyName } |
        Select-Object @{n = 'Name'; e = { $_.DisplayName.Trim() } }, @{n = 'Version'; e = { $_.DisplayVersion } }, @{n = 'Hersteller'; e = { $_.Publisher } }, @{n = 'Installiert'; e = { $_.InstallDate } } |
        Sort-Object Name -Unique)
    Add-Line ('  {0} Programme, vollständige Liste: Software.csv im Anhang' -f $sw.Count)
    try { $sw | Export-Csv -Path (Join-Path $RawDir 'Software.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8 } catch { }
    $recent = @($sw | Where-Object { $_.Installiert -match '^\d{8}$' -and $_.Installiert -ge (Get-Date).AddDays(-30).ToString('yyyyMMdd') })
    if ($recent.Count) { Add-Line '  In den letzten 30 Tagen installiert:'; $recent | Sort-Object Installiert -Descending | Out-Report }
}

if ($script:Opt['Integritaet']) {
    Invoke-Section 'Test: Dateisystem und Systemdateien' {
        Add-Sub 'Dateisystem-Onlinescan (chkdsk /scan)'
        $volRes = New-Object System.Collections.ArrayList
        foreach ($v in (Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem -in 'NTFS', 'ReFS' -and $_.DriveType -eq 'Fixed' })) {
            Write-Step ('Scanne Volume {0}: ...' -f $v.DriveLetter)
            try {
                if ((Get-Command Repair-Volume).Parameters.ContainsKey('AsJob')) {
                    $rj = Repair-Volume -DriveLetter $v.DriveLetter -Scan -AsJob -ErrorAction Stop
                    [void](Wait-JobWithProgress $rj ('Dateisystem-Scan Laufwerk {0}:' -f $v.DriveLetter) 120 3600)
                    $res = Receive-Job $rj -ErrorAction Stop
                    Remove-Job $rj -Force -ErrorAction SilentlyContinue
                } else {
                    Show-Sub ('Dateisystem-Scan Laufwerk {0}:' -f $v.DriveLetter) 'läuft'
                    $res = Repair-Volume -DriveLetter $v.DriveLetter -Scan -ErrorAction Stop
                    Hide-Sub
                }
                Add-Line ('  {0}: {1}' -f $v.DriveLetter, $res)
                [void]$volRes.Add(('{0}: {1}' -f $v.DriveLetter, $(if ("$res" -eq 'NoErrorsFound') { 'ok' } else { "$res" })))
                if ("$res" -ne 'NoErrorsFound') { Add-Finding WARNUNG 'Dateisystem' ('Volume {0}: Onlinescan meldet {1}. Abhilfe: Reparaturmodul "Dateisystemfehler beheben".' -f $v.DriveLetter, $res) }
            } catch { Add-Line ('  {0}: Scan fehlgeschlagen: {1}' -f $v.DriveLetter, $_.Exception.Message) }
        }
        $fat = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -like 'FAT*' })
        if ($fat.Count) { Add-Line ('  Nicht geprüft (FAT/FAT32, kein Onlinescan möglich): {0}' -f (($fat | ForEach-Object { '{0}:' -f $_.DriveLetter }) -join ', ')) }
        Add-TestResult 'Dateisystem-Scan (chkdsk)' $(if (@($volRes | Where-Object { $_ -notmatch ': ok$' }).Count) { 'Warnung' } else { 'OK' }) ($volRes -join ', ')

        Add-Sub 'Komponentenspeicher (DISM ScanHealth)'
        Write-Step 'DISM ScanHealth läuft (5 bis 20 Minuten) ...'
        $job = Start-Job -ScriptBlock { Repair-WindowsImage -Online -ScanHealth -NoRestart -ErrorAction Stop | Select-Object ImageHealthState }
        [void](Wait-JobWithProgress $job 'DISM ScanHealth' 600 3600)
        $dismState = ''
        try { $dr = Receive-Job $job -ErrorAction Stop; $dismState = [string]@($dr)[0].ImageHealthState } catch { Add-Line ('  DISM fehlgeschlagen: {0}' -f $_.Exception.Message) }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        if ($dismState) {
            Add-Line ('  Zustand: {0}' -f $dismState)
            Add-TestResult 'Komponentenspeicher (DISM)' $(if ($dismState -eq 'Healthy') { 'OK' } else { 'Warnung' }) $dismState
            if ($dismState -eq 'Repairable') { Add-Finding WARNUNG 'Systemdateien' 'Komponentenspeicher beschädigt, aber reparierbar. Abhilfe: Reparaturmodul (DISM RestoreHealth, danach sfc /scannow).' }
            elseif ($dismState -ne 'Healthy') { Add-Finding KRITISCH 'Systemdateien' ('Komponentenspeicher: {0}. Abhilfe: Inplace-Upgrade mit dem Windows-Installationsmedium.' -f $dismState) }
        }

        Add-Sub 'Systemdateiprüfung (sfc /verifyonly)'
        Write-Step 'sfc /verifyonly läuft (5 bis 15 Minuten) ...'
        $sfcStart = Get-Date
        $sfc = Invoke-External -File "$env:windir\System32\sfc.exe" -Arguments '/verifyonly' -TimeoutSec 3600 -Encoding ([Text.Encoding]::Unicode) -Progress 'Systemdateiprüfung sfc /verifyonly' -ExpectedSec 600
        $sfcLines = ($sfc.Output -split "[`r`n]+") | Where-Object { $_.Trim() -and $_ -notmatch '\d+\s*%' }
        Add-Line (($sfcLines | ForEach-Object { '  ' + $_.Trim() }) -join "`r`n")
        Add-Line ('  Rückgabecode: {0}' -f $sfc.ExitCode)
        $cbs = Get-CbsEntries $sfcStart
        Add-Line ('  CBS.log: {0} nicht reparierbare, {1} beschädigte oder abweichende Einträge' -f $cbs.Cannot.Count, $cbs.Corrupt.Count)
        if ($cbs.Files.Count) { Add-Line ('  Betroffene Dateien: {0}' -f (($cbs.Files | Select-Object -First 20) -join ', ')) }
        (@($cbs.Cannot) + @($cbs.Corrupt)) | Select-Object -First 15 | ForEach-Object { Add-Line ('    ' + $_) }
        $sfcClean = $sfc.Output -match 'keine Integritätsverletzungen|did not find any integrity violations'
        $sfcViol  = (-not $sfcClean) -and ($sfc.Output -match 'Integritätsverletzungen|integrity violations|beschädigte Dateien|corrupt files')
        $files = $(if ($cbs.Files.Count) { ' Betroffen: ' + (($cbs.Files | Select-Object -First 8) -join ', ') + '.' } else { '' })
        if ($sfcViol -or $cbs.Corrupt.Count) {
            $healthyHint = $(if ($dismState -eq 'Healthy') { ' Da der Komponentenspeicher intakt ist, behebt sfc /scannow das in der Regel sofort.' } else { '' })
            Add-Finding WARNUNG 'Systemdateien' ('SFC hat Integritätsverletzungen gefunden.{0}{1} Abhilfe: Reparaturmodul (DISM RestoreHealth, danach sfc /scannow).' -f $files, $healthyHint)
        }
        $sfcStatus = $(if ($cbs.Cannot.Count) { 'Fehler' } elseif ($sfcClean) { 'OK' } elseif ($cbs.Corrupt.Count -or $sfcViol) { 'Warnung' } else { 'Info' })
        Add-TestResult 'Systemdateien (sfc /verifyonly)' $sfcStatus $(if ($sfcClean) { 'keine Integritätsverletzungen' } elseif ($sfcViol -or $cbs.Corrupt.Count) { 'Integritätsverletzungen gefunden' + $files } else { 'Ergebnis siehe Details' })
    }
}

if ($script:Opt['Defender'] -and $script:DefenderActive) {
    Invoke-Section 'Test: Microsoft Defender Schnellscan' {
        Write-Step 'Defender Schnellscan läuft ...'
        $t0 = Get-Date
        try {
            Show-Sub 'Defender' 'Signaturen werden aktualisiert'
            Update-MpSignature -ErrorAction SilentlyContinue
            if ((Get-Command Start-MpScan).Parameters.ContainsKey('AsJob')) {
                $mj = Start-MpScan -ScanType QuickScan -AsJob -ErrorAction Stop
                [void](Wait-JobWithProgress $mj 'Defender Schnellscan' 300 3600)
                Receive-Job $mj -ErrorAction SilentlyContinue | Out-Null
                Remove-Job $mj -Force -ErrorAction SilentlyContinue
            } else {
                Show-Sub 'Defender Schnellscan' 'läuft, Dauer meist 2 bis 10 Minuten'
                Start-MpScan -ScanType QuickScan -ErrorAction Stop
                Hide-Sub
            }
            $new = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -ge $t0 })
            Add-Line ('  Scan beendet nach {0:mm\:ss}, neue Erkennungen: {1}' -f ((Get-Date) - $t0), $new.Count)
            Add-TestResult 'Defender Schnellscan' $(if ($new.Count) { 'Fehler' } else { 'OK' }) ('{0} neue Erkennungen' -f $new.Count)
            if ($new.Count) {
                $new | Select-Object InitialDetectionTime, ThreatID, ActionSuccess, @{n = 'Ressourcen'; e = { $_.Resources -join '; ' } } | Out-Report
                Add-Finding KRITISCH 'Sicherheit' ('Defender-Schnellscan hat {0} Bedrohungen gefunden.' -f $new.Count)
            }
        } catch { Add-Line ('  Scan nicht möglich: {0}' -f $_.Exception.Message); Add-TestResult 'Defender Schnellscan' 'Info' 'nicht möglich' }
    }
}

# ---------- SMART-Langtest starten (läuft in der Laufwerksfirmware weiter) ----------
$script:SmartTests = @()
if ($script:Opt['SmartLang'] -and $script:Smartctl -and @($script:SmartDevices).Count) {
    Invoke-Section 'Test: SMART-Langtest wird gestartet' {
        foreach ($d in $script:SmartDevices) {
            Show-Sub 'SMART-Langtest starten' $d.name
            $st0 = Get-SmartTestState $d
            $r = $null
            if (-not $st0.Running) {
                $r = Invoke-External -File $script:Smartctl -Arguments ('-t long -d {0} {1}' -f $d.type, $d.name) -TimeoutSec 60
                for ($try = 0; $try -lt 3 -and -not $st0.Running; $try++) { Start-Sleep -Seconds 5; $st0 = Get-SmartTestState $d }
            }
            $begun = [bool]($r -and $r.Output -match 'has begun|Testing has begun|started')
            $status = $(if ($st0.Running -or $begun) { 'läuft' } else { 'nicht gestartet' })
            $info = [pscustomobject]@{ Device = $d; Name = $d.name; Protokoll = $d.protocol; Status = $status; Fortschritt = $(if ($st0.Percent) { $st0.Percent } else { 0 }); Start = (Get-Date); Ende = $null; Minuten = $st0.Minutes; Grund = '' }
            $script:SmartTests += $info
            if ($status -eq 'läuft') {
                Add-Line ('  {0}: Langtest läuft{1}' -f $d.name, $(if ($st0.Minutes) { ', vom Hersteller geschätzt ca. {0} Minuten' -f $st0.Minutes } else { '' }))
            } else {
                $msg = ''
                if ($r) { $msg = (($r.Output + "`n" + $r.Error) -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch '^smartctl |^Copyright|^===' } | Select-Object -Last 3) -join ' ' }
                if (-not $msg) { $msg = 'smartctl hat keinen Grund gemeldet' }
                $info.Grund = $msg.Trim()
                Add-Line ('  {0}: Langtest konnte nicht gestartet werden: {1}' -f $d.name, $info.Grund)
                Add-Finding INFO 'SMART' ('{0}: SMART-Langtest ließ sich nicht starten ({1}).' -f $d.name, $info.Grund)
            }
        }
        Add-Line '  Der Test läuft im Hintergrund in der Laufwerksfirmware weiter, während die übrigen Tests laufen.'
    }
}

if ($script:Opt['Netzwerk']) {
    Invoke-Section 'Test: Netzwerk' {
        function Test-PingTarget([string]$Target, [int]$Count = 10) {
            $p = New-Object System.Net.NetworkInformation.Ping
            $ok = 0; $times = New-Object System.Collections.ArrayList
            for ($i = 0; $i -lt $Count; $i++) {
                try { $rp = $p.Send($Target, 1500); if ($rp.Status -eq 'Success') { $ok++; [void]$times.Add([int]$rp.RoundtripTime) } } catch { }
                Start-Sleep -Milliseconds 200
            }
            $m = $times | Measure-Object -Minimum -Maximum -Average
            [pscustomobject][ordered]@{ Ziel = $Target; Gesendet = $Count; Empfangen = $ok; 'Verlust %' = [math]::Round(($Count - $ok) / $Count * 100, 0)
                'Min ms' = $m.Minimum; 'Mittel ms' = $(if ($m.Average -ne $null) { [math]::Round($m.Average, 1) }); 'Max ms' = $m.Maximum }
        }
        $netProblems = New-Object System.Collections.ArrayList
        $mbit = $null
        $gw = (Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1).IPv4DefaultGateway.NextHop
        $targets = @(); if ($gw) { $targets += $gw }; $targets += '1.1.1.1', 'www.microsoft.com'
        Write-Step 'Ping-Tests ...'
        $ti = 0
        $pings = foreach ($t in $targets) { $ti++; Show-Sub 'Ping-Test' ('{0} ({1} von {2})' -f $t, $ti, $targets.Count) ([int](($ti - 1) / $targets.Count * 100)); Test-PingTarget $t $(if ($Kurztest) { 3 } else { 10 }) }
        Hide-Sub
        $pings | Out-Report
        foreach ($pp in $pings) {
            if ($pp.'Verlust %' -gt 0 -and $pp.'Verlust %' -lt 100) { Add-Finding WARNUNG 'Netzwerk' ('{0}: {1} % Paketverlust.' -f $pp.Ziel, $pp.'Verlust %'); [void]$netProblems.Add(('Paketverlust {0}' -f $pp.Ziel)) }
            elseif ($pp.'Verlust %' -eq 100) { Add-Finding INFO 'Netzwerk' ('{0} antwortet nicht auf Ping (evtl. per Firewall gesperrt).' -f $pp.Ziel) }
        }

        Add-Sub 'DNS und HTTPS'
        foreach ($h in 'www.microsoft.com', 'www.google.com', 'www.wikipedia.org') {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try { $a = Resolve-DnsName $h -Type A -DnsOnly -ErrorAction Stop | Where-Object Type -eq 'A' | Select-Object -First 1; $sw.Stop(); Add-Line ('  DNS {0,-20} -> {1,-16} {2} ms' -f $h, $a.IPAddress, $sw.ElapsedMilliseconds) }
            catch { Add-Line ('  DNS {0,-20} FEHLGESCHLAGEN: {1}' -f $h, $_.Exception.Message); Add-Finding WARNUNG 'Netzwerk' ('DNS-Auflösung von {0} fehlgeschlagen.' -f $h); [void]$netProblems.Add(('DNS {0}' -f $h)) }
        }
        try {
            $wc = New-Object Net.WebClient
            $wc.Proxy = [Net.WebRequest]::GetSystemWebProxy(); $wc.Proxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials
            $txt = $wc.DownloadString('http://www.msftconnecttest.com/connecttest.txt')
            Add-Line ('  Internet-Konnektivitätstest (NCSI): {0}' -f $(if ($txt -eq 'Microsoft Connect Test') { 'OK' } else { 'unerwartete Antwort (Captive Portal?)' }))
            if ($Kurztest) { Add-Line '  Downloadtest im Kurztest übersprungen.' }
            else {
                Write-Step 'Downloadtest (25 MB) ...'
                Show-Sub 'Downloadtest' '25 MB werden geladen'
                $sw = [Diagnostics.Stopwatch]::StartNew()
                $data = $wc.DownloadData('https://speed.cloudflare.com/__down?bytes=25000000')
                $sw.Stop()
                $mbit = [math]::Round(($data.Length * 8 / 1e6) / $sw.Elapsed.TotalSeconds, 1)
                Add-Line ('  Download: {0} in {1:N1} s = ca. {2} Mbit/s' -f (Format-Size $data.Length), $sw.Elapsed.TotalSeconds, $mbit)
                Hide-Sub
            }
        } catch { Add-Line ('  HTTP(S)-Test fehlgeschlagen: {0}' -f $_.Exception.Message); Add-Finding WARNUNG 'Netzwerk' 'HTTP(S)-Zugriff ins Internet fehlgeschlagen (Proxy/Firewall?).'; [void]$netProblems.Add('HTTP(S)') }
        $pingAvg = ($pings | Where-Object { $_.'Mittel ms' -ne $null } | Select-Object -Last 1).'Mittel ms'
        $netDet = ('Ping {0} ms, Download {1}' -f $pingAvg, $(if ($mbit) { "$mbit Mbit/s" } else { 'n/v' }))
        if ($netProblems.Count) { $netDet += ', Probleme: ' + ($netProblems -join ', ') }
        Add-TestResult 'Netzwerk' $(if ($netProblems.Count) { 'Warnung' } else { 'OK' }) $netDet
    }
}

if ($script:Opt['RamTest']) {
    Invoke-Section 'Test: Arbeitsspeicher (Mustertest)' {
        if (-not $TypesLoaded) { Add-Line '  Übersprungen: C#-Testroutinen nicht verfügbar (Constrained Language Mode / AppLocker).'; return }
        $os = Get-CimInstance Win32_OperatingSystem
        $free = [long]$os.FreePhysicalMemory * 1KB
        $target = [long]($free * $RamTestPercent / 100)
        if (-not [Environment]::Is64BitProcess) { $target = [math]::Min($target, 1.2GB) }
        Add-Line ('  Freier RAM: {0}, davon getestet werden {1} % ({2}).' -f (Format-Size $free), $RamTestPercent, (Format-Size $target))
        Add-Line '  Hinweis: Ein Test unter Windows erreicht nicht jeden physischen Speicherbereich. Für eine vollständige Prüfung die Windows-Speicherdiagnose oder MemTest86 nutzen.'
        $task = [DiagRam]::RunAsync($target, $RamTestPasses)
        while (-not $task.IsCompleted) {
            Show-Sub ('RAM-Mustertest   {0} %' -f [DiagRam]::Percent) ('{0}   Fehler bisher: {1}' -f [DiagRam]::Phase, [DiagRam]::Errors) ([DiagRam]::Percent)
            Start-Sleep -Milliseconds 500
        }
        Hide-Sub
        Add-Line (($task.Result -split "`r?`n" | Where-Object { $_ } | ForEach-Object { '  ' + $_ }) -join "`r`n")
        Add-TestResult 'RAM-Mustertest' $(if ([DiagRam]::Errors -gt 0) { 'Fehler' } else { 'OK' }) ('{0} getestet, {1} Durchläufe, {2} Fehler' -f (Format-Size ([DiagRam]::BytesTested)), $RamTestPasses, [DiagRam]::Errors)
        if ([DiagRam]::Errors -gt 0) { Add-Finding KRITISCH 'RAM' ('RAM-Mustertest: {0} Bitfehler gefunden. Module einzeln testen (MemTest86), XMP/EXPO deaktivieren.' -f [DiagRam]::Errors) }
    }
}

Invoke-Section 'Windows-Speicherdiagnose (frühere Ergebnisse)' {
    $md = Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } 5
    if ($md.Count) {
        $md | Select-Object TimeCreated, Id, LevelDisplayName, @{n = 'Ergebnis'; e = { Get-ShortText $_.Message 180 } } | Out-Report
        if ($md | Where-Object { $_.Id -in 1102, 1202 -or $_.Level -le 2 }) { Add-Finding KRITISCH 'RAM' 'Die Windows-Speicherdiagnose hat früher Hardwarefehler gemeldet.' }
    } else { Add-Line '  Bisher kein Lauf der Windows-Speicherdiagnose protokolliert.' }
}

if ($script:Opt['CpuTest']) {
    Invoke-Section 'Test: CPU-Stabilität und Drosselung' {
        if (-not $TypesLoaded) { Add-Line '  Übersprungen: C#-Testroutinen nicht verfügbar.'; return }
        $threads = [Environment]::ProcessorCount
        $idle = Get-CpuSample
        Add-Line ('  Leerlauf: Last {0} %, effektiver Takt ca. {1} MHz, Temperatur (ACPI) {2}' -f $idle.Last, $idle.MHz, $(if ($idle.Temp) { '{0} °C' -f $idle.Temp } else { 'nicht verfügbar' }))
        Write-Step ('CPU-Last auf {0} Threads für {1} Sekunden ...' -f $threads, $CpuStressSeconds)
        $task = [DiagCpu]::RunAsync($CpuStressSeconds, $threads)
        $t0 = Get-Date
        $samples = New-Object System.Collections.ArrayList
        while (-not $task.IsCompleted) {
            Start-Sleep -Seconds 3
            $s = Get-CpuSample
            if ($script:Sens) { $ld = Get-SensorLead (Get-SensorReadings -CpuSample $s); if ($null -ne $ld.CpuTemp -and $ld.CpuTempQ -ne 'ACPI') { $s | Add-Member -NotePropertyName SensTemp -NotePropertyValue $ld.CpuTemp -Force }; if ($null -ne $ld.CpuW) { $s | Add-Member -NotePropertyName SensW -NotePropertyValue $ld.CpuW -Force } }
            [void]$samples.Add($s)
            $el = ((Get-Date) - $t0).TotalSeconds
            $cp = [int]([math]::Min(100.0, $el / $CpuStressSeconds * 100.0))
            Show-Sub ('CPU-Stabilitätstest   {0} %   noch ca. {1} s' -f $cp, [int][math]::Max(0.0, $CpuStressSeconds - $el)) ('Last {0} %   Takt {1} MHz   Temp {2}   Rechenfehler {3}' -f $s.Last, $s.MHz, $(if ($s.Temp) { "$($s.Temp) °C" } else { 'n/v' }), [DiagCpu]::Errors) $cp
        }
        Hide-Sub
        $load = $samples | Where-Object Last -ge 80
        if (-not $load) { $load = $samples }
        $mhz  = $load | Measure-Object MHz -Minimum -Maximum -Average
        $perf = $load | Measure-Object Leistung -Minimum -Average
        $tmp  = $load | Where-Object Temp | Measure-Object Temp -Maximum
        $lim  = $load | Measure-Object MaxFreq -Minimum
        Add-Line ('  Dauer: {0} s, Threads: {1}, Rechendurchläufe: {2:N0}, Rechenfehler: {3}' -f $CpuStressSeconds, $threads, [DiagCpu]::Iterations, [DiagCpu]::Errors)
        Add-Line ('  Effektiver Takt unter Last: min {0:N0} / Ø {1:N0} / max {2:N0} MHz' -f $mhz.Minimum, $mhz.Average, $mhz.Maximum)
        Add-Line ('  Prozessorleistung (% vom Basistakt): min {0} / Ø {1:N0}' -f $perf.Minimum, $perf.Average)
        Add-Line ('  Frequenzgrenze (% vom Maximum): min {0}' -f $lim.Minimum)
        Add-TestResult 'CPU-Stabilität' $(if ([DiagCpu]::Errors -gt 0) { 'Fehler' } elseif ($perf.Average -and $perf.Average -lt 75) { 'Warnung' } else { 'OK' }) ('{0} s auf {1} Threads, Ø {2:N0} MHz, {3} Rechenfehler' -f $CpuStressSeconds, $threads, $mhz.Average, [DiagCpu]::Errors)
        $sensT = @($samples | Where-Object { $null -ne $_.SensTemp })
        if ($sensT.Count) {
            $stm = ($sensT | Measure-Object SensTemp -Maximum).Maximum
            $swm = @($samples | Where-Object { $null -ne $_.SensW })
            Add-Line ('  CPU-Temperatur (Sensoren): max {0:N0} °C{1}' -f $stm, $(if ($swm.Count) { ', Paketleistung max {0:N0} W' -f ($swm | Measure-Object SensW -Maximum).Maximum } else { '' }))
            if ($stm -ge 95) { Add-Finding WARNUNG 'CPU' ('CPU-Temperatur erreichte {0:N0} °C unter Last. Kühlung, Lüfter und Wärmeleitpaste prüfen.' -f $stm) }
        }
        $tempVals = @($samples | Where-Object Temp | ForEach-Object { $_.Temp } | Select-Object -Unique)
        $tempStatic = ($tempVals.Count -le 1)
        if ($sensT.Count) { }
        elseif (-not $tmp.Count) { Add-Line '  Temperatur: nicht auslesbar. Für Kerntemperaturen HWiNFO oder Ryzen Master/Intel XTU nutzen.' }
        elseif ($tempStatic) { Add-Line ('  Temperatur: ACPI-Wert bleibt unter Last konstant bei {0} °C, das ist keine echte CPU-Temperatur. Für Kerntemperaturen HWiNFO oder Ryzen Master/Intel XTU nutzen.' -f $tmp.Maximum) }
        else { Add-Line ('  Temperatur (ACPI-Thermalzone, nicht zwingend Kerntemperatur): max {0} °C' -f $tmp.Maximum) }
        if ([DiagCpu]::Errors -gt 0) { Add-Finding KRITISCH 'CPU' ('{0} Rechenfehler unter Last. Hinweis auf Instabilität (Übertaktung, Undervolting, Kühlung, Netzteil).' -f [DiagCpu]::Errors) }
        if ($perf.Average -and $perf.Average -lt 75) { Add-Finding WARNUNG 'CPU' ('CPU läuft unter Last im Schnitt nur mit {0:N0} % des Basistakts (thermische Drosselung, Energiesparplan oder Netzteil).' -f $perf.Average) }
        if ($lim.Minimum -and $lim.Minimum -lt 85) { Add-Finding INFO 'CPU' ('Frequenzgrenze fiel auf {0} % (Energie- oder Temperaturlimit aktiv).' -f $lim.Minimum) }
        if (-not $sensT.Count -and $tmp.Count -and -not $tempStatic -and $tmp.Maximum -ge 95) { Add-Finding WARNUNG 'CPU' ('Thermalzone erreichte {0} °C unter Last. Kühlung/Lüfter/Wärmeleitpaste prüfen.' -f $tmp.Maximum) }
    }
}

Invoke-Section 'Energie' {
    $as = Invoke-External -File 'powercfg.exe' -Arguments '/getactivescheme'
    Add-Line ('  ' + $as.Output.Trim())
    Add-Sub 'Verfügbare Standbymodi'
    $a = Invoke-External -File 'powercfg.exe' -Arguments '/a'
    Add-Line (($a.Output -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { '  ' + $_.TrimEnd() }) -join "`r`n")
    Add-Sub 'Aktive Energieanforderungen (verhindern Standby)'
    $rq = Invoke-External -File 'powercfg.exe' -Arguments '/requests'
    Add-Line (($rq.Output -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { '  ' + $_.TrimEnd() }) -join "`r`n")
    if ($script:Opt['Energieanalyse']) {
        Add-Sub 'Energieeffizienzanalyse (60 Sekunden)'
        Write-Step 'powercfg /energy läuft 60 Sekunden ...'
        if ($TypesLoaded) { [void][DiagPower]::SetThreadExecutionState([uint32]2147483648) }   # eigene Standby-Sperre nicht mitmessen
        $en = Invoke-External -File 'powercfg.exe' -Arguments ('/energy /output "{0}" /duration 60' -f (Join-Path $RawDir 'Energiebericht.html')) -TimeoutSec 180 -Progress 'Energieanalyse (powercfg /energy)' -ExpectedSec 65
        if ($TypesLoaded) { [void][DiagPower]::SetThreadExecutionState([uint32]2147483649) }
        Add-Line (($en.Output -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch 'Energiebericht\.html|energy-report' } | ForEach-Object { '  ' + $_.Trim() }) -join "`r`n")
        Add-Line '  Details: Energiebericht.html im Anhang'
        $enSum = (($en.Output -split "`r?`n") | Where-Object { $_ -match '^\s*\d+\s' } | ForEach-Object { $_.Trim() }) -join ', '
        Add-TestResult 'Energieanalyse' 'Info' $(if ($enSum) { $enSum + ' (Details im Anhang)' } else { 'Details im Anhang' })
        Write-Step 'DxDiag-Bericht wird erstellt ...'
        [void](Invoke-External -File "$env:windir\System32\dxdiag.exe" -Arguments ('/t "{0}"' -f (Join-Path $RawDir 'dxdiag.txt')) -TimeoutSec 240 -Progress 'DxDiag-Bericht' -ExpectedSec 45)
    }
}

# ---------- Auf SMART-Langtest warten ----------
if ($script:SmartTests | Where-Object Status -eq 'läuft') {
    Invoke-Section 'Test: SMART-Langtest Ergebnis' {
        $deadline = ($script:SmartTests | Sort-Object Start | Select-Object -First 1).Start.AddMinutes($SmartTimeoutMinutes)
        Write-Step ('Warte auf den SMART-Langtest (maximal bis {0:HH:mm} Uhr). Die Schaltfläche "Test beenden" beendet das Warten, der Bericht wird trotzdem erstellt.' -f $deadline)
        $skipWait = $false
        $stopFile = Join-Path $script:CpDir 'stop.flag'
        Remove-Item $stopFile -Force -ErrorAction SilentlyContinue
        Send-GuiEvent 'STOP' '1'
        while ((Get-Date) -lt $deadline) {
            $running = @($script:SmartTests | Where-Object Status -eq 'läuft')
            if (-not $running.Count) { break }
            foreach ($t in $running) {
                $st = Get-SmartTestState $t.Device
                if ($st.Running) { $t.Fortschritt = $st.Percent } else { $t.Status = 'beendet'; $t.Ende = Get-Date; $t.Fortschritt = 100 }
            }
            $still = @($script:SmartTests | Where-Object Status -eq 'läuft')
            if (-not $still.Count) { break }
            $avg = ($still | Measure-Object Fortschritt -Average).Average
            $txt = ($still | ForEach-Object { '{0}: {1} %' -f $_.Name, $_.Fortschritt }) -join '   '
            $left = $deadline - (Get-Date)
            for ($w = 0; $w -lt 30; $w++) {
                Show-Sub ('SMART-Langtest   {0} %' -f [int]$avg) ('{0}   Zeitlimit in {1:hh\:mm\:ss}' -f $txt, ($left - [TimeSpan]::FromSeconds($w))) ([math]::Max(0, [math]::Min(100, [int]$avg)))
                Start-Sleep -Seconds 1
                if (Test-Path $stopFile) { Remove-Item $stopFile -Force -ErrorAction SilentlyContinue; $skipWait = $true; break }
            }
            if ($skipWait) { Write-Step 'Warten auf SMART-Langtest vom Benutzer beendet.'; break }
        }
        Hide-Sub
        Send-GuiEvent 'STOP' '0'
        $waitReason = $(if ($skipWait) { 'Warten vom Benutzer beendet' } else { 'Zeitlimit erreicht' })
        $waited = ((Get-Date) - ($script:SmartTests | Sort-Object Start | Select-Object -First 1).Start).TotalMinutes

        foreach ($t in $script:SmartTests) {
            $d = $t.Device
            Add-Sub ('{0} ({1})' -f $d.name, $d.protocol)
            if ($t.Status -eq 'nicht gestartet') { Add-Line ('  Langtest nicht gestartet: {0}' -f $t.Grund); Add-TestResult ('SMART-Langtest {0}' -f $d.name) 'Info' ('nicht gestartet: ' + $t.Grund); continue }
            if ($t.Status -eq 'läuft') {
                Add-Line ('  {0} nach {1:N0} Minuten. Der Test läuft im Laufwerk weiter ({2} %). Ergebnis später mit: smartctl -l selftest {3}' -f $waitReason, $waited, $t.Fortschritt, $d.name)
                Add-Finding INFO 'SMART' ('{0}: Langtest nach {1:N0} Minuten bei {2} % ({3}), Ergebnis später prüfen.' -f $d.name, $waited, $t.Fortschritt, $waitReason)
                Add-TestResult ('SMART-Langtest {0}' -f $d.name) 'Info' ('nach {0:N0} min bei {1} %, läuft im Laufwerk weiter' -f $waited, $t.Fortschritt)
                continue
            }
            Add-Line ('  Dauer: {0:hh\:mm\:ss}' -f ($t.Ende - $t.Start))
            $jr = Invoke-External -File $script:Smartctl -Arguments ('-a -l selftest -j -d {0} {1}' -f $d.type, $d.name) -TimeoutSec 120
            try { $j = $jr.Output | ConvertFrom-Json } catch { $j = $null }
            if ($j) {
                if ($j.device.protocol -eq 'NVMe') {
                    $last = $j.nvme_self_test_log.table | Select-Object -First 1
                    if (-not $last) { Add-Line '  Kein Eintrag im Selbsttestprotokoll, der Test wurde vermutlich nicht ausgeführt.'; Add-TestResult ('SMART-Langtest {0}' -f $d.name) 'Info' 'kein Eintrag im Selbsttestprotokoll' }
                    if ($last) {
                        Add-Line ('  Letzter Selbsttest: {0} -> {1} (bei {2} Betriebsstunden)' -f $last.self_test_code.string, $last.self_test_result.string, $last.power_on_hours)
                        $v = [int]$last.self_test_result.value
                        Add-TestResult ('SMART-Langtest {0} [{1}]' -f $j.model_name, $d.name) $(if ($v -eq 0) { 'OK' } elseif ($v -in 5, 6, 7) { 'Fehler' } else { 'Warnung' }) $last.self_test_result.string
                        if ($v -in 5, 6, 7) { Add-Finding KRITISCH 'SMART' ('{0}: SMART-Langtest FEHLGESCHLAGEN ({1}).' -f $d.name, $last.self_test_result.string) }
                        elseif ($v -ne 0) { Add-Finding WARNUNG 'SMART' ('{0}: SMART-Langtest abgebrochen ({1}).' -f $d.name, $last.self_test_result.string) }
                    }
                } else {
                    $last = $j.ata_smart_self_test_log.standard.table | Select-Object -First 1
                    if (-not $last) { Add-Line '  Kein Eintrag im Selbsttestprotokoll, der Test wurde vermutlich nicht ausgeführt.'; Add-TestResult ('SMART-Langtest {0}' -f $d.name) 'Info' 'kein Eintrag im Selbsttestprotokoll' }
                    if ($last) {
                        Add-Line ('  Letzter Selbsttest: {0} -> {1} (bei {2} Betriebsstunden{3})' -f $last.type.string, $last.status.string, $last.lifetime_hours, $(if ($last.lba) { ', erster Fehler-LBA ' + $last.lba } else { '' }))
                        Add-TestResult ('SMART-Langtest {0} [{1}]' -f $j.model_name, $d.name) $(if ($last.status.passed) { 'OK' } elseif ($last.status.string -match 'fail|fatal|damage') { 'Fehler' } else { 'Warnung' }) $last.status.string
                        if ($last.status.passed -eq $false) {
                            if ($last.status.string -match 'fail|fatal|damage') { Add-Finding KRITISCH 'SMART' ('{0}: SMART-Langtest FEHLGESCHLAGEN ({1}).' -f $d.name, $last.status.string) }
                            else { Add-Finding WARNUNG 'SMART' ('{0}: SMART-Langtest nicht erfolgreich ({1}).' -f $d.name, $last.status.string) }
                        }
                    }
                }
                $label = '{0} [{1}]' -f $j.model_name, $d.name
                Test-SmartJson -Json $j -Label $label | Out-Report -List
            }
            $safe = ($d.name -replace '[\\/:]', '_').Trim('_')
            (Invoke-External -File $script:Smartctl -Arguments ('-x -d {0} {1}' -f $d.type, $d.name) -TimeoutSec 180).Output | Out-File (Join-Path $RawDir ('smartctl_{0}_nachher.txt' -f $safe)) -Encoding UTF8
        }
    }
}

}   # Ende: Diagnose


# ---------- Ereignisprotokolle (Diagnose und Absturzanalyse) ----------
$script:PowerLoss = $null
if ($script:Opt['Ereignisse']) {
$script:EventDetails = @()
Invoke-Section ('Ereignisprotokolle (letzte {0} Tage)' -f $EventDays) {
    $checks = @(
        @{ N = 'Bluescreens (BugCheck 1001)';                  P = @('Microsoft-Windows-WER-SystemErrorReporting'); Id = @(1001); L = 'KRITISCH'; A = 'Stabilität' }
        @{ N = 'Unerwartetes Abschalten (Kernel-Power 41)';    P = @('Microsoft-Windows-Kernel-Power'); Id = @(41); L = 'WARNUNG'; A = 'Stabilität' }
        @{ N = 'Unerwartetes Herunterfahren (EventLog 6008)';  P = @('EventLog'); Id = @(6008); L = 'INFO'; A = 'Stabilität' }
        @{ N = 'WHEA Hardwarefehler (schwer)';                 P = @('Microsoft-Windows-WHEA-Logger'); Lv = @(1, 2); L = 'KRITISCH'; A = 'Hardware' }
        @{ N = 'WHEA korrigierte Hardwarefehler';              P = @('Microsoft-Windows-WHEA-Logger'); Lv = @(3); L = 'WARNUNG'; A = 'Hardware' }
        @{ N = 'Datenträger: fehlerhafter Block (disk 7)';     P = @('disk'); Id = @(7); L = 'KRITISCH'; A = 'Datenträger' }
        @{ N = 'Datenträger: Controllerfehler (disk 11)';      P = @('disk'); Id = @(11); L = 'WARNUNG'; A = 'Datenträger' }
        @{ N = 'Datenträger: Auslagerungsfehler (disk 51)';    P = @('disk'); Id = @(51); L = 'WARNUNG'; A = 'Datenträger' }
        @{ N = 'Datenträger: E/A wiederholt (disk 153)';       P = @('disk'); Id = @(153); L = 'WARNUNG'; A = 'Datenträger' }
        @{ N = 'SATA-Controller Reset (storahci 129)';         P = @('storahci', 'iaStorAC', 'iaStorA', 'iaStorAVC'); Id = @(129); L = 'WARNUNG'; A = 'Datenträger' }
        @{ N = 'NVMe Controllerfehler/Reset (stornvme)';       P = @('stornvme'); Lv = @(1, 2, 3); L = 'WARNUNG'; A = 'Datenträger' }
        @{ N = 'NTFS Dateisystembeschädigung (55)';            P = @('Ntfs', 'Microsoft-Windows-Ntfs'); Id = @(55); L = 'WARNUNG'; A = 'Dateisystem' }
        @{ N = 'NTFS Volume braucht Reparatur (98)';           P = @('Ntfs', 'Microsoft-Windows-Ntfs'); Id = @(98); Lv = @(1, 2, 3); L = 'WARNUNG'; A = 'Dateisystem' }
        @{ N = 'Grafiktreiber reagierte nicht (Display 4101)'; P = @('Display'); Id = @(4101); L = 'WARNUNG'; A = 'Grafik' }
        @{ N = 'NVIDIA/AMD Treiberfehler';                     P = @('nvlddmkm', 'amdkmdag', 'amdwddmg'); Lv = @(1, 2); L = 'WARNUNG'; A = 'Grafik' }
        @{ N = 'Dienstabstürze (SCM 7031/7034)';               P = @('Service Control Manager'); Id = @(7031, 7034); L = 'INFO'; A = 'Dienste' }
        @{ N = 'Windows-Update Installationsfehler (20)';      P = @('Microsoft-Windows-WindowsUpdateClient'); Id = @(20); L = 'WARNUNG'; A = 'Updates' }
        @{ N = 'Zeitsynchronisation fehlgeschlagen';           P = @('Microsoft-Windows-Time-Service'); Lv = @(2); L = 'INFO'; A = 'System' }
    )
    $ci = 0
    $overview = foreach ($c in $checks) {
        $ci++
        Show-Sub 'Ereignisprotokolle auswerten' $c.N ([int](($ci - 1) / $checks.Count * 100))
        $ev = @()
        foreach ($prov in $c.P) {
            $f = @{ LogName = 'System'; ProviderName = $prov; StartTime = $Since }
            if ($c.Id) { $f.Id = $c.Id }
            if ($c.Lv) { $f.Level = $c.Lv }
            $ev += Get-Ev $f 500
        }
        $ev = @($ev | Sort-Object RecordId -Unique | Sort-Object TimeCreated -Descending)
        $lvl = $c.L; $note = ''
        if ($c.N -like 'Windows-Update*' -and $ev.Count -and @($ev | Where-Object { $_.Message -match '\b9[A-Z0-9]{11}-' }).Count -eq $ev.Count) {
            $lvl = 'INFO'; $note = ' Nur Store-Apps betroffen, meist harmlos (0x80073D02: App war beim Update geöffnet).'
        }
        if ($ev.Count -and $c.N -like 'Bluescreens*') {
            $codes = @($ev | ForEach-Object { if ($_.Message -match '0x([0-9a-fA-F]{8})') { [Convert]::ToInt64($Matches[1], 16) } } | Group-Object | Sort-Object Count -Descending)
            if ($codes.Count) {
                $note = ' Stoppcodes: ' + (($codes | ForEach-Object { '0x{0:X} {1} ({2}x)' -f [int64]$_.Name, (Get-BugcheckName ([int64]$_.Name)), $_.Count }) -join '; ') + '.'
                if (@($codes | Where-Object { Test-MemoryBugcheck ([int64]$_.Name) }).Count) {
                    $note += ' Der Code deutet auf Arbeitsspeicher oder Treiber hin: RAM mit MemTest86 prüfen' + $(if ($script:RamProfileActive) { ', das XMP/EXPO-Profil testweise deaktivieren' } else { '' }) + ' und Treiber aktualisieren.'
                }
            }
        }
        if ($ev.Count -and $c.N -like 'Unerwartetes Abschalten*') {
            $script:PowerLoss = @(Get-PowerLossInfo $ev)
            $grp = @($script:PowerLoss | Group-Object Kategorie)
            $cnt = @{}; foreach ($g in $grp) { $cnt[$g.Name] = $g.Count }
            $names = @{ Betrieb = 'im laufenden Betrieb'; Standby = 'im Energiesparmodus'; Herunterfahren = 'beim oder nach dem Herunterfahren'; Taste = 'per Ein/Aus-Taste erzwungen'; Bluescreen = 'durch Bluescreen' }
            $note = ' Einordnung der letzten {0}: {1}.' -f $script:PowerLoss.Count, (($grp | ForEach-Object { '{0}x {1}' -f $_.Count, $names[$_.Name] }) -join ', ')
            $lvl = $(if ($cnt['Betrieb'] -or $cnt['Standby'] -ge 2) { 'WARNUNG' } else { 'INFO' })
            if ($cnt['Betrieb']) { $note += ' Abschaltungen im Betrieb deuten auf Netzteil, Überhitzung, instabile Übertaktung oder RAM-Einstellungen hin.' }
            if ($cnt['Herunterfahren'] -or $cnt['Standby']) {
                $hb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
                if ($hb -ne 0) { $note += ' Schnellstart ist aktiv: Wird der Strom nach dem Herunterfahren getrennt, protokolliert Windows das als unerwartetes Abschalten. Abhilfe: Reparaturmodul "Schnellstart deaktivieren".' }
            }
        }
        if ($ev.Count -and $c.A -in 'Datenträger', 'Dateisystem') { $note += (Get-DiskRefText $ev) }
        if ($ev.Count) {
            Add-Finding $lvl $c.A ('{0}: {1}x, zuletzt {2:dd.MM.yyyy HH:mm}.{3}' -f $c.N, $ev.Count, $ev[0].TimeCreated, $note)
            $script:EventDetails += , @{ Name = $c.N; Events = ($ev | Select-Object -First 5) }
        }
        [pscustomobject]@{ 'Prüfung' = $c.N; Anzahl = $ev.Count; Zuletzt = $(if ($ev.Count) { $ev[0].TimeCreated }) }
    }
    Show-Sub 'Ereignisprotokolle auswerten' 'Häufigste Fehler und Abstürze' 95
    $overview | Out-Report
    foreach ($d in $script:EventDetails) {
        Add-Sub $d.Name
        $d.Events | Select-Object TimeCreated, Id, ProviderName, @{n = 'Meldung'; e = { Get-ShortText $_.Message 200 } } | Out-Report
        if ($d.Name -like 'Unerwartetes Abschalten*' -and $script:PowerLoss) {
            Add-Line '  Einordnung anhand des letzten Ereignisses vor dem Neustart:'
            $script:PowerLoss | Select-Object @{n = 'Neustart'; e = { $_.Neustart.ToString('dd.MM.yyyy HH:mm') } }, @{n = 'Letzte Aktivität'; e = { if ($_.'Letzte Aktivität') { $_.'Letzte Aktivität'.ToString('dd.MM.yyyy HH:mm') } } }, 'Letztes Ereignis', Einordnung | Out-Report
        }
    }

    Add-Sub 'Häufigste Fehler im System-Protokoll'
    $sysErr = Get-Ev @{ LogName = 'System'; Level = 1, 2; StartTime = $Since } 5000
    Add-Line ('  {0} Fehler/kritische Ereignisse' -f $sysErr.Count)
    $sysErr | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 25 | ForEach-Object {
        $f = $_.Group[0]
        [pscustomobject]@{ Anzahl = $_.Count; Quelle = $f.ProviderName; ID = $f.Id; Zuletzt = $f.TimeCreated; Meldung = (Get-ShortText $f.Message 130) }
    } | Out-Report

    Add-Sub 'Häufigste Fehler im Anwendungs-Protokoll'
    $appErr = Get-Ev @{ LogName = 'Application'; Level = 1, 2; StartTime = $Since } 5000
    Add-Line ('  {0} Fehler/kritische Ereignisse' -f $appErr.Count)
    $appErr | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object {
        $f = $_.Group[0]
        [pscustomobject]@{ Anzahl = $_.Count; Quelle = $f.ProviderName; ID = $f.Id; Zuletzt = $f.TimeCreated; Meldung = (Get-ShortText $f.Message 130) }
    } | Out-Report

    Add-Sub 'Programmabstürze (Application Error 1000)'
    $crash = Get-Ev @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $Since } 3000
    $crash | Group-Object { $_.Properties[0].Value } | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object {
        [pscustomobject]@{ Anzahl = $_.Count; Programm = $_.Name; 'Fehlermodul (zuletzt)' = $_.Group[0].Properties[3].Value; Ausnahmecode = $_.Group[0].Properties[6].Value; Zuletzt = $_.Group[0].TimeCreated }
    } | Out-Report
    if ($crash.Count -gt 25) { Add-Finding INFO 'Stabilität' ('{0} Programmabstürze in {1} Tagen.' -f $crash.Count, $EventDays) }
    Add-Sub 'Programme reagieren nicht (Application Hang 1002)'
    Get-Ev @{ LogName = 'Application'; ProviderName = 'Application Hang'; Id = 1002; StartTime = $Since } 2000 | Group-Object { $_.Properties[0].Value } |
        Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { [pscustomobject]@{ Anzahl = $_.Count; Programm = $_.Name; Zuletzt = $_.Group[0].TimeCreated } } | Out-Report
}

Invoke-Section 'Absturzabbilder und Zuverlässigkeit' {
    Add-Sub 'Minidumps / Kernel-Dumps'
    $dumps = @()
    $dumps += Get-ChildItem "$env:windir\Minidump\*.dmp" -ErrorAction SilentlyContinue
    $dumps += Get-ChildItem "$env:windir\MEMORY.DMP" -ErrorAction SilentlyContinue
    $dumps += Get-ChildItem "$env:windir\LiveKernelReports" -Recurse -Filter *.dmp -ErrorAction SilentlyContinue
    if ($dumps.Count) {
        $dumps | Sort-Object LastWriteTime -Descending | Select-Object -First 20 FullName, LastWriteTime, @{n = 'Größe'; e = { Format-Size $_.Length } } | Out-Report
        $recent = @($dumps | Where-Object { $_.LastWriteTime -gt $Since -and $_.FullName -match 'Minidump|MEMORY.DMP' })
        if ($recent.Count) { Add-Finding WARNUNG 'Stabilität' ('{0} Absturzabbilder in den letzten {1} Tagen (Analyse z. B. mit WinDbg oder BlueScreenView).' -f $recent.Count, $EventDays) }
        $lkr = @($dumps | Where-Object { $_.LastWriteTime -gt $Since -and $_.FullName -match 'LiveKernelReports' })
        if ($lkr.Count) { Add-Finding INFO 'Stabilität' ('{0} Live-Kernel-Reports (oft Grafiktreiber- oder USB-Hänger).' -f $lkr.Count) }
        $big = @($dumps | Where-Object { $_.Length -gt 1GB })
        if ($big.Count) { Add-Finding INFO 'Speicherplatz' ('{0} große Absturzabbilder belegen {1} (z. B. {2}), löschbar wenn nicht mehr zur Analyse nötig.' -f $big.Count, (Format-Size (($big | Measure-Object Length -Sum).Sum)), $big[0].FullName) }
    } else { Add-Line '  Keine Absturzabbilder vorhanden.' }

    Add-Sub 'Einstellungen für Absturzabbilder'
    $cc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction SilentlyContinue
    if ($cc) {
        $cdMap = @{ 0 = 'keins'; 1 = 'vollständig'; 2 = 'Kernelspeicher'; 3 = 'klein (Minidump)'; 7 = 'automatisch' }
        Add-Line ('  Abbildtyp: {0}, automatischer Neustart: {1}' -f $cdMap[[int]$cc.CrashDumpEnabled], $(if ($cc.AutoReboot -eq 1) { 'ja' } else { 'nein' }))
        if ([int]$cc.CrashDumpEnabled -eq 0) { Add-Finding WARNUNG 'Stabilität' 'Absturzabbilder sind deaktiviert, nach einem Bluescreen fehlt die Ursache (Systemeigenschaften, Erweitert, Starten und Wiederherstellen).' }
    }

    Add-Sub 'Zuverlässigkeitsindex'
    $rsm = Get-CimInstance Win32_ReliabilityStabilityMetrics -ErrorAction SilentlyContinue | Sort-Object TimeGenerated -Descending | Select-Object -First 1
    if ($rsm) {
        Add-Line ('  Stabilitätsindex: {0:N2} von 10 (Stand {1})' -f $rsm.SystemStabilityIndex, $rsm.TimeGenerated)
        if ($rsm.SystemStabilityIndex -lt 5) { Add-Finding WARNUNG 'Stabilität' ('Zuverlässigkeitsindex nur {0:N1} von 10.' -f $rsm.SystemStabilityIndex) }
    } else { Add-Line '  Nicht verfügbar (Aufgabe RacTask evtl. deaktiviert).' }
    $dmtf = [Management.ManagementDateTimeConverter]::ToDmtfDateTime($Since)
    $rr = $(if ($Kurztest) { @() } else { @(Get-CimInstance Win32_ReliabilityRecords -Filter ("TimeGenerated > '{0}'" -f $dmtf) -ErrorAction SilentlyContinue) })
    if ($rr.Count) {
        Add-Line ('  {0} Zuverlässigkeitsereignisse, gruppiert:' -f $rr.Count)
        $rr | Group-Object SourceName, ProductName | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object {
            [pscustomobject]@{ Anzahl = $_.Count; Quelle = $_.Group[0].SourceName; Produkt = $_.Group[0].ProductName; Zuletzt = ($_.Group | Sort-Object TimeGenerated -Descending | Select-Object -First 1).TimeGenerated }
        } | Out-Report
    }
}

}


# =====================================================================================
#                 SYSTEMÜBERSICHT (nur Benchmark oder Lasttest ohne Diagnose)
# =====================================================================================
if (($ModBench -or $ModLast) -and -not $ModDiag) {
    Invoke-Section 'Systemübersicht' {
        $cs   = Get-CimCached Win32_ComputerSystem
        $os   = Get-CimInstance Win32_OperatingSystem
        $bios = Get-CimCached Win32_BIOS
        $bb   = Get-CimCached Win32_BaseBoard
        $enc  = Get-CimCached Win32_SystemEnclosure
        $cv   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $cpus = @(Get-CimCached Win32_Processor)
        $mods = @(Get-CimCached Win32_PhysicalMemory)
        $pd   = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object { [int]$_.DeviceId })
        $gMain = Get-MainGpu
        $ii   = Get-WindowsInstallInfo; $script:InstallInfo = $ii
        $script:IsLaptop = [bool]($enc.ChassisTypes | Where-Object { $_ -in 8, 9, 10, 14, 30, 31, 32 })
        $script:LogicalCpus = ($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum
        $typeMap = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
        $total = ($mods | Measure-Object Capacity -Sum).Sum
        $typ0 = $(if ($mods.Count -and $typeMap.ContainsKey([int]$mods[0].SMBIOSMemoryType)) { $typeMap[[int]$mods[0].SMBIOSMemoryType] } else { '' })
        $spd0 = $(if ($mods.Count) { $(if ($mods[0].ConfiguredClockSpeed) { $mods[0].ConfiguredClockSpeed } else { $mods[0].Speed }) } else { 0 })

        $script:Facts['Computer']       = $env:COMPUTERNAME
        $script:Facts['System']         = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
        $script:Facts['Mainboard']      = ('{0} {1}' -f $bb.Manufacturer, $bb.Product).Trim()
        $script:Facts['Betriebssystem'] = ('{0} {1} (Build {2}.{3})' -f $os.Caption, $cv.DisplayVersion, $os.BuildNumber, $cv.UBR)
        if ($ii.Erstinstallation) { $script:Facts['Windows installiert'] = ('{0:dd.MM.yyyy} (vor {1}){2}' -f $ii.Erstinstallation, (Format-Age $ii.AlterTage -Dativ), $(if ($ii.Upgrades.Count) { ', seitdem {0} Funktionsupdate(s), zuletzt {1:dd.MM.yyyy}' -f $ii.Upgrades.Count, $ii.AktuellSeit } else { ', seitdem kein Funktionsupdate' })) }
        $script:Facts['BIOS/UEFI']      = ('{0} vom {1:dd.MM.yyyy}' -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
        $script:Facts['Prozessor']      = (($cpus | ForEach-Object { '{0} ({1} Kerne, {2} Threads)' -f $_.Name.Trim(), $_.NumberOfCores, $_.NumberOfLogicalProcessors }) -join '; ')
        if ($mods.Count) { $script:Facts['Arbeitsspeicher'] = ('{0} ({1}x {2} {3}, {4} MT/s)' -f (Format-Size $total), $mods.Count, (Format-Size $mods[0].Capacity), $typ0, $spd0) }
        $script:Facts['Grafik']         = $(if ($gMain) { [string]$gMain.Name } else { '' })
        $script:Facts['Datenträger']    = (($pd | ForEach-Object { '{0} ({1}, {2})' -f $_.FriendlyName, (Format-Size $_.Size), $_.BusType }) -join "`n")
        $script:BenchShort.CPU = Get-ShortCpuName $cpus[0].Name
        if ($mods.Count) { $script:BenchShort.RAM = ('{0} GB {1}-{2}' -f [math]::Round($total / 1GB), $(if ($typ0) { $typ0 } else { 'RAM' }), $spd0) }
        if ($gMain) { $script:BenchShort.GPU = Get-ShortGpuName $gMain.Name }
        $script:DiskNames = @{}
        foreach ($d in $pd) { $script:DiskNames[[int]$d.DeviceId] = ('{0} ({1})' -f ([string]$d.FriendlyName).Trim(), $d.BusType); Add-Private ([string]$d.SerialNumber) 'SERIENNR' }
        Add-Private $bios.SerialNumber 'SERIENNR'; Add-Private $bb.SerialNumber 'SERIENNR'
        foreach ($m in $mods) { Add-Private ([string]$m.SerialNumber) 'SERIENNR' }
        $script:UserNames = @(@([string]$cs.UserName, [string]$env:USERNAME) | ForEach-Object { ($_ -split '\\')[-1] } | Where-Object { $_ })
        if ($cs.PartOfDomain -and $cs.Domain) { Add-Private ([string]$cs.Domain) 'DOMÄNE' }
        [pscustomobject]$script:Facts | Out-Report -List
        Test-RamProfile $mods $typ0
        $up = (Get-Date) - $os.LastBootUpTime
        if ($up.TotalDays -gt 14) { Add-Finding INFO 'System' ('Seit {0} Tagen kein Neustart. Für aussagekräftige Messwerte vorher neu starten.' -f [int]$up.TotalDays) }
    }
}


# =====================================================================================
#                                    BENCHMARK
# =====================================================================================
$script:BenchInit = $false
function Initialize-Bench {
    if ($script:BenchInit) { return }
    $script:BenchInit = $true
    $script:BenchMs = $(if ($BenchmarkKurz) { 2000 } else { 5000 })
    # PS 5.1 gibt ein JSON-Array als EIN Objekt aus, daher erst zuweisen, dann in ein Array wandeln
    # frühere Läufe dieses Geräts aus der Vergleichsdatenbank (gleiche Messdauer) für den Verlauf, auch nach Umbenennung oder Neuinstallation
    $devId = (Get-DeviceIdentity).Id
    $script:BenchHistory = @(Get-DbEntries | Where-Object { (Test-SameDevice $_ $devId $env:COMPUTERNAME) -and $_.Messwerte.Count } | Sort-Object Datum | ForEach-Object {
        $mw = $_.Messwerte
        [pscustomobject]@{ Kurz = ($_.Messdauer -eq 'kurz'); Werte = @($mw.Keys | ForEach-Object { [pscustomobject]@{ Key = $_; Wert = $mw[$_] } }) }
    })
    Import-BenchReference
    # Vergleichssysteme aus der Datenbank laden
    $script:CmpSystems = @()
    foreach ($f in @(([string]$VergleichDateien) -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })) {
        $j = Read-JsonFile $f
        if ($j -and $j.Werte) { $script:CmpSystems += [pscustomobject]@{ Path = $f; Name = [string]$j.Name; Computer = [string]$j.Computer; Datum = [string]$j.Datum; Werte = (ConvertTo-ValueTable $j.Werte) } }
        else { Add-Line ('  Vergleichssystem nicht lesbar: {0}' -f $f) }
    }
    Add-Line '  Index 100 = typischer Wert für diese Hardwareklasse. Vergleich = Median der letzten Läufe auf diesem PC.'
    Add-Line ('  Referenz 100 % = {0}{1}. Laufwerke werden mit der gleichen Klasse der Referenz verglichen.' -f $script:Ref.Name, $(if ($script:Ref.Quelle -ne 'eingebaut') { ', Quelle: ' + $script:Ref.Quelle } else { '' }))
    if ($script:CmpSystems.Count) { Add-Line ('  Eingeblendete Vergleichssysteme: {0}' -f (($script:CmpSystems | ForEach-Object { '{0} ({1})' -f $_.Computer, $_.Datum }) -join ', ')) }
    Add-Line '  Für aussagekräftige Werte andere Programme schließen und den PC am Netzteil betreiben.'
    $idle = Get-CpuSample
    if ($idle.Last -gt 15) { Add-Finding INFO 'Leistung' ('Beim Benchmark-Start lag bereits {0} % CPU-Last an, die Werte können niedriger ausfallen.' -f $idle.Last) }
}

# Vergleich mit den gewählten Systemen: Bericht, Oberfläche (Reiter Leistung) und KI-Datei
function Add-BenchComparison {
    if (-not $script:CmpSystems.Count) { return }
    $script:CmpRows = @(Get-CompareRows)
    if (-not $script:CmpRows.Count) { return }
    Add-Sub 'Vergleich mit bereits geprüften Systemen'
    $i = 0
    foreach ($s in $script:CmpSystems) { $i++; Add-Line ('  System {0}: {1}, Messung vom {2}' -f $i, $s.Name, $s.Datum) }
    $tab = foreach ($r in $script:CmpRows) {
        $o = [ordered]@{ Messung = $r.Messung; 'Dieser PC' = (Format-Metric $r.Dieses $r.Format $r.Einheit) }
        for ($k = 0; $k -lt $script:CmpSystems.Count; $k++) {
            $v = $r.Werte[$k]
            $rel = Get-RelText $r.Dieses $v $r.LowerBetter
            $o[('System {0}' -f ($k + 1))] = $(if ($null -ne $v) { (Format-Metric $v $r.Format $r.Einheit) + $(if ($rel) { ' (' + $rel + ')' } else { '' }) } else { '' })
        }
        $o['Rang'] = $r.Rang
        [pscustomobject]$o
    }
    $tab | Out-Report
    Add-Line '  Prozent in Klammern: Abstand des anderen Systems zu diesem PC, positiv bedeutet besser. Rang unter allen Systemen der Datenbank.'
    Send-GuiEvent 'BGRP' 'Vergleich' 'Vergleich mit anderen Systemen' '' (($script:CmpSystems | ForEach-Object { $_.Computer }) -join ', ') ''
    foreach ($r in $script:CmpRows) {
        $parts = for ($k = 0; $k -lt $script:CmpSystems.Count; $k++) { $v = $r.Werte[$k]; if ($null -ne $v) { $rel = Get-RelText $r.Dieses $v $r.LowerBetter; '{0}: {1}{2}' -f $script:CmpSystems[$k].Computer, (Format-Metric $v $r.Format $r.Einheit), $(if ($rel) { ' (' + $rel + ')' } else { '' }) } }
        Send-GuiEvent 'BENCH' '' 'Vergleich' $r.Messung (Format-Metric $r.Dieses $r.Format $r.Einheit) '' ($parts -join '  ·  ') ((@($parts) + @($r.Rang) | Where-Object { $_ }) -join '; ') $r.Rang 'Vergleich'
    }
}

function Test-BenchTypes {
    if ($TypesLoaded) { return $true }
    Add-Line '  Übersprungen: C#-Routinen nicht verfügbar (Constrained Language Mode).'
    Add-TestResult 'Benchmark' 'Übersprungen' 'Constrained Language Mode'
    return $false
}

if ($ModBench) {

if ($script:BenchSel['CPU']) {
    Invoke-Section 'Benchmark: Prozessor' {
        Initialize-Bench
        if (-not (Test-BenchTypes)) { return }
        $inv = $script:Inv; $ms = $script:BenchMs; $threads = [Environment]::ProcessorCount
        # ---------------- Prozessor ----------------
        try {
            $cpuAll = @(Get-CimCached Win32_Processor)
            $cpuName = (($cpuAll[0].Name -as [string]) -replace '\s+', ' ').Trim()
            $cores = [int](($cpuAll | Measure-Object NumberOfCores -Sum).Sum)
            $baseMHz = [int]$cpuAll[0].MaxClockSpeed
            Write-Step 'Benchmark Prozessor ...'
            $tST = [DiagBench]::CpuAsync(1, $ms)
            $sST = Wait-TaskProgress $tST 'Benchmark Prozessor' 'Einzelkern' $ms -Sample
            $st = [double]$tST.Result
            Start-Sleep -Milliseconds 500
            $tMT = [DiagBench]::CpuAsync($threads, $ms)
            $sMT = Wait-TaskProgress $tMT 'Benchmark Prozessor' ('Mehrkern, {0} Threads' -f $threads) $ms -Sample
            $mt = [double]$tMT.Result
            $ptsST = [math]::Round($st / 3); $ptsMT = [math]::Round($mt / 3)
            $scal = $(if ($st -gt 0) { $mt / $st } else { 0 })
            $hybrid = $cpuName -match 'Core\(TM\) Ultra|Core\(TM\) i[3579]-1[2-4]\d{3}|Core\(TM\) [3579] '
            $smt = [math]::Max(0, $threads - $cores)
            # Die Rechenlast profitiert stark von SMT/Hyper-Threading (gemessen: 6 Kerne/12 Threads skalieren ca. 12x)
            $expScal = $(if ($hybrid) { $cores * 0.8 + $smt * 0.9 } else { $cores + $smt * 0.9 })
            if ($expScal -lt 1) { $expScal = 1 }
            $scalIdx = [int][math]::Round($scal / $expScal * 100)
            $stPerf = Get-Median ($sST | ForEach-Object { $_.MaxLeistung } | Where-Object { $_ -gt 0 })
            $mtPerf = Get-Median ($sMT | ForEach-Object { $_.Leistung } | Where-Object { $_ -gt 0 })
            $keyCpu = 'CPU|' + $cpuName
            Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Einzelkern' -Wert $ptsST -Einheit 'Punkte' -Anzeige ('{0:N0} Punkte' -f $ptsST) -Key ($keyCpu + '|ST') -RefKey 'CPU|ST' -Hinweis 'eigene Rechenlast aus Ganzzahl- und Gleitkommaoperationen, ein Thread'
            if ($stPerf) {
                $stStat = $(if ($stPerf -lt 85) { 'Warnung' } else { 'OK' })
                Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Takt Einzelkern' -Wert ($baseMHz * $stPerf / 100) -Einheit 'MHz' -Anzeige ('{0:N0} MHz' -f ($baseMHz * $stPerf / 100)) -Index ([int]$stPerf) -Status $stStat -Hinweis ('{0} % vom Basistakt {1} MHz' -f $stPerf, $baseMHz)
                if ($stStat -eq 'Warnung') { Add-Finding WARNUNG 'Leistung' ('Unter Einzelkernlast läuft die CPU nur mit {0} % des Basistakts (Energiesparplan, Drosselung oder BIOS-Einstellung).' -f $stPerf) }
            }
            Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Mehrkern' -Wert $ptsMT -Einheit 'Punkte' -Anzeige ('{0:N0} Punkte' -f $ptsMT) -Key ($keyCpu + '|MT') -RefKey 'CPU|MT' -Hinweis ('{0} Threads' -f $threads)
            $mtStat = $(if ($scalIdx -lt 55) { 'Warnung' } elseif ($scalIdx -lt 75) { 'Info' } else { 'OK' })
            Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Mehrkern-Skalierung' -Wert ([math]::Round($scal, 2)) -Einheit 'x' -Anzeige ('{0:N1}x' -f $scal) -Index $scalIdx -Status $mtStat -Hinweis ('erwartet ca. {0:N1}x bei {1} Kernen und {2} Threads' -f $expScal, $cores, $threads)
            if ($mtStat -eq 'Warnung') { Add-Finding WARNUNG 'Leistung' ('Die CPU skaliert schlecht über alle Kerne ({0:N1}x statt ca. {1:N1}x): Power-Limit, Drosselung, Energiesparplan oder Hintergrundlast.' -f $scal, $expScal) }
            if ($mtPerf) {
                $mtcStat = $(if ($mtPerf -lt 80) { 'Warnung' } else { 'OK' })
                Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Takt Mehrkern' -Wert ($baseMHz * $mtPerf / 100) -Einheit 'MHz' -Anzeige ('{0:N0} MHz' -f ($baseMHz * $mtPerf / 100)) -Index ([int]$mtPerf) -Status $mtcStat -Hinweis ('{0} % vom Basistakt' -f $mtPerf)
                if ($mtcStat -eq 'Warnung') { Add-Finding WARNUNG 'Leistung' ('Unter Last auf allen Kernen hält die CPU nur {0} % des Basistakts (Kühlung, Power-Limit oder Netzteil).' -f $mtPerf) }
            }
            # Praxisnahe Teillasten: Verschlüsselung, Prüfsummen, Kompression
            $tA = [DiagBench]::AesAsync($ms); [void](Wait-TaskProgress $tA 'Benchmark Prozessor' 'AES-256 verschlüsseln' $ms); $aes = [double]$tA.Result
            if ($aes -gt 0) {
                $aesStat = $(if ($aes -lt 300) { 'Info' } else { 'OK' })
                Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'AES-256 verschlüsseln' -Wert ([math]::Round($aes)) -Einheit 'MB/s' -Anzeige ('{0:N0} MB/s' -f $aes) -Status $aesStat -Key ($keyCpu + '|AES') -RefKey 'CPU|AES' -Hinweis 'AES-256-CBC, ein Thread, Windows-Kryptografie'
                if ($aesStat -eq 'Info') { Add-Finding INFO 'Leistung' ('AES-Verschlüsselung erreicht nur {0:N0} MB/s. Vermutlich wird AES-NI nicht genutzt (im BIOS deaktiviert oder virtuelle Maschine), BitLocker und VPN werden dadurch langsamer.' -f $aes) }
            }
            $tS = [DiagBench]::ShaAsync($ms); [void](Wait-TaskProgress $tS 'Benchmark Prozessor' 'SHA-256 Prüfsumme' $ms); $sha = [double]$tS.Result
            if ($sha -gt 0) { Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'SHA-256 Prüfsumme' -Wert ([math]::Round($sha)) -Einheit 'MB/s' -Anzeige ('{0:N0} MB/s' -f $sha) -Key ($keyCpu + '|SHA') -RefKey 'CPU|SHA' -Hinweis $(if ($sha -ge 1500) { 'ein Thread, SHA-Befehlssatz aktiv' } else { 'ein Thread' }) }
            $tD = [DiagBench]::DeflateAsync($threads, $ms); [void](Wait-TaskProgress $tD 'Benchmark Prozessor' ('Kompression, {0} Threads' -f $threads) ($ms + 1500)); $defl = [double]$tD.Result
            if ($defl -gt 0) { Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Kompression (Deflate)' -Wert ([math]::Round($defl)) -Einheit 'MB/s' -Anzeige ('{0:N0} MB/s' -f $defl) -Key ($keyCpu + '|DEFL') -RefKey 'CPU|DEFL' -Hinweis ('ZIP-Kompression von Textdaten auf {0} Threads, Durchsatz der Eingangsdaten' -f $threads) }
            $script:BenchHead['CPU'] = '{0} · Einzelkern {1:N0} · Mehrkern {2:N0} Punkte' -f ($cpuName -replace '\s*(\d+-Core|Processor|CPU @.*$)', '' -replace '\((R|TM)\)', ''), $ptsST, $ptsMT
            $script:BenchShort.CPU = Get-ShortCpuName $cpuName
        } catch { Write-BenchError 'Prozessor' $_ }
        Send-BenchGroup 'CPU'
    }
}

if ($script:BenchSel['RAM']) {
    Invoke-Section 'Benchmark: Arbeitsspeicher' {
        Initialize-Bench
        if (-not (Test-BenchTypes)) { return }
        $inv = $script:Inv; $ms = $script:BenchMs; $threads = [Environment]::ProcessorCount
        # ---------------- Arbeitsspeicher ----------------
        try {
            $os = Get-CimInstance Win32_OperatingSystem
            $freeB = [double]$os.FreePhysicalMemory * 1KB
            $memBytes = [long][math]::Min([double]1GB, [double]$freeB * 0.3)
            if ($memBytes -lt 128MB) { Add-Line '  RAM-Benchmark übersprungen: zu wenig freier Speicher.' }
            else {
                Write-Step 'Benchmark Arbeitsspeicher ...'
                $tR = [DiagBench]::MemReadAsync($threads, $memBytes, $ms); [void](Wait-TaskProgress $tR 'Benchmark Arbeitsspeicher' 'Lesen' ($ms + 2000)); $rd = [double]$tR.Result
                $tW = [DiagBench]::MemWriteAsync($threads, $memBytes, $ms); [void](Wait-TaskProgress $tW 'Benchmark Arbeitsspeicher' 'Schreiben' ($ms + 2000)); $wr = [double]$tW.Result
                $tC = [DiagBench]::MemCopyAsync($threads, $memBytes, $ms); [void](Wait-TaskProgress $tC 'Benchmark Arbeitsspeicher' 'Kopieren' ($ms + 2000)); $cp = [double]$tC.Result
                $tL = [DiagBench]::LatencyAsync([long][math]::Min([long]256MB, [long]$memBytes), [int][math]::Min(3000, [int]$ms)); [void](Wait-TaskProgress $tL 'Benchmark Arbeitsspeicher' 'Latenz' 4000); $lat = [double]$tL.Result
                $mods = @(Get-CimCached Win32_PhysicalMemory)
                $speed = [int](($mods | Where-Object { $_.ConfiguredClockSpeed } | Measure-Object ConfiguredClockSpeed -Minimum).Minimum)
                if (-not $speed) { $speed = [int](($mods | Measure-Object Speed -Minimum).Minimum) }
                $mtype = $(if ($mods.Count) { [int]$mods[0].SMBIOSMemoryType } else { 0 })
                $tname = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }[$mtype]
                $chan = @($mods | ForEach-Object {
                    $l = '{0} {1}' -f $_.BankLabel, $_.DeviceLocator
                    if ($l -match '(Controller\s*\d+)?\W*CHANNEL\s*([A-H])') { ('{0}{1}' -f $Matches[1], $Matches[2]).ToUpper() } elseif ($l -match 'DIMM_?([A-H])\d') { $Matches[1].ToUpper() }
                } | Select-Object -Unique).Count
                if (-not $chan) { $chan = [math]::Min(2, $mods.Count) }
                $lp = $mtype -in 27, 28, 29, 30, 35
                $theo = $chan * $speed * 8 / 1000
                $eff = $(if ($theo -gt 0) { $rd / $theo } else { 0 })
                $memIdx = $(if ($lp -or $theo -le 0) { $null } else { [int][math]::Round($eff / 0.65 * 100) })
                $memStat = $(if ($null -eq $memIdx) { 'Info' } elseif ($memIdx -lt 50) { 'Warnung' } elseif ($memIdx -lt 70) { 'Info' } else { 'OK' })
                $totalGB = [math]::Round((($mods | Measure-Object Capacity -Sum).Sum) / 1GB)
                $keyRam = 'RAM|{0}GB|{1}' -f $totalGB, $speed
                $hint = $(if ($null -ne $memIdx) { '{0:N0} % von theoretisch {1:N1} GB/s ({2} Kanäle, {3} MT/s)' -f ($eff * 100), $theo, $chan, $speed } else { 'LPDDR bzw. unbekannte Kanalzahl, kein Index' })
                Add-BenchResult -Gruppe 'RAM' -Komponente 'RAM' -Messung 'Lesen' -Wert ([math]::Round($rd, 1)) -Einheit 'GB/s' -Anzeige ('{0:N1} GB/s' -f $rd) -Index $memIdx -Status $memStat -Key ($keyRam + '|Lesen') -RefKey 'RAM|Lesen' -Hinweis $hint
                Add-BenchResult -Gruppe 'RAM' -Komponente 'RAM' -Messung 'Schreiben' -Wert ([math]::Round($wr, 1)) -Einheit 'GB/s' -Anzeige ('{0:N1} GB/s' -f $wr) -Key ($keyRam + '|Schreiben') -RefKey 'RAM|Schreiben'
                if ($cp -gt 0) { Add-BenchResult -Gruppe 'RAM' -Komponente 'RAM' -Messung 'Kopieren' -Wert ([math]::Round($cp, 1)) -Einheit 'GB/s' -Anzeige ('{0:N1} GB/s' -f $cp) -Key ($keyRam + '|Kopieren') -RefKey 'RAM|Kopieren' -Hinweis 'kopierte Datenmenge pro Sekunde (liest und schreibt gleichzeitig)' }
                $latStat = $(if ($lat -gt 250) { 'Warnung' } elseif ($lat -gt 150) { 'Info' } else { 'OK' })
                Add-BenchResult -Gruppe 'RAM' -Komponente 'RAM' -Messung 'Latenz' -Wert ([math]::Round($lat, 1)) -Einheit 'ns' -Anzeige ('{0:N0} ns' -f $lat) -Status $latStat -Key ($keyRam + '|Latenz') -RefKey 'RAM|Latenz' -LowerBetter -Hinweis 'zufällige Zugriffe über 256 MB, inklusive TLB-Fehlgriffe'
                if ($memStat -eq 'Warnung') { Add-Finding WARNUNG 'Leistung' ('Die Speicherbandbreite erreicht nur {0:N0} % des theoretischen Werts: Single-Channel-Betrieb, falsche Steckplätze, niedriger Takt oder Hintergrundlast prüfen.' -f ($eff * 100)) }
                $ramDesc = ('{0} GB {1}-{2}' -f $totalGB, $(if ($tname) { $tname } else { 'RAM' }), $speed)
                $script:BenchHead['RAM'] = '{0}, {1} Kanäle · Lesen {2:N1} GB/s · Latenz {3:N0} ns' -f $ramDesc, $chan, $rd, $lat
                $script:BenchShort.RAM = $ramDesc
            }
        } catch { Write-BenchError 'Arbeitsspeicher' $_ }
        Send-BenchGroup 'RAM'
    }
}

if ($script:BenchSel['GPU']) {
    Invoke-Section 'Benchmark: Grafik' {
        Initialize-Bench
        if (-not (Test-BenchTypes)) { return }
        $inv = $script:Inv; $ms = $script:BenchMs; $threads = [Environment]::ProcessorCount
        # ---------------- Grafik ----------------
        try {
            $isDisc = { param($g) [string]$g.Name -match 'NVIDIA|GeForce|Quadro|Radeon\s*(RX|Pro|VII)|FirePro|Intel.*Arc' }
            $gpus = @(Get-CimCached Win32_VideoController | Where-Object { $_.Name -notmatch 'Virtual|Remote|Indirect|Parsec|spacedesk|Basic Display|Basic Render' })
            $disc = @($gpus | Where-Object { & $isDisc $_ })
            if ($disc.Count -and -not $script:IsLaptop) {
                $discOn = @($disc | Where-Object { $_.CurrentHorizontalResolution })
                $igpOn  = @($gpus | Where-Object { -not (& $isDisc $_) -and $_.CurrentHorizontalResolution })
                if (-not $discOn.Count -and $igpOn.Count) { Add-Finding WARNUNG 'Leistung' ('Der Monitor hängt an der Prozessorgrafik ({0}) statt an der Grafikkarte {1}. Kabel an die Grafikkarte umstecken.' -f $igpOn[0].Name, $disc[0].Name) }
            }
            $gMain = $(if ($disc.Count) { $disc[0] } elseif ($gpus.Count) { $gpus[0] } else { $null })
            $gpuName = $(if ($gMain) { [string]$gMain.Name } else { 'Grafik' })
            $wx = Join-Path $RawDir 'winsat-dwm.xml'
            Write-Step 'Benchmark Grafik (WinSAT DWM) ...'
            $wr2 = Invoke-External -File "$env:windir\System32\winsat.exe" -Arguments ('dwm -xml "{0}"' -f $wx) -TimeoutSec 300 -Progress 'Benchmark Grafik (WinSAT DWM)' -ExpectedSec 30
            $vmb = $null; $dfps = $null
            if (Test-Path $wx) {
                try {
                    [xml]$x = Get-Content $wx -Raw
                    $n1 = $x.SelectSingleNode('//VideoMemBandwidth'); if ($n1) { $vmb = [double]::Parse($n1.InnerText.Trim(), $inv) }
                    $n2 = $x.SelectSingleNode('//DWMFps'); if ($n2) { $dfps = [double]::Parse($n2.InnerText.Trim(), $inv) }
                } catch { }
            }
            if ($vmb) {
                Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung 'Grafikspeicher-Durchsatz' -Wert ([math]::Round($vmb / 1000, 1)) -Einheit 'GB/s' -Anzeige ('{0:N1} GB/s' -f ($vmb / 1000)) -Key ('GPU|' + $gpuName + '|VMB') -RefKey 'GPU|VMB' -Hinweis ('{0}, gemessen mit WinSAT DWM (kein Spiele-Benchmark)' -f $gpuName)
                if ($dfps) { Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung 'Desktop-Komposition' -Wert ([math]::Round($dfps)) -Einheit 'Bilder/s' -Anzeige ('{0:N0} Bilder/s' -f $dfps) -Key ('GPU|' + $gpuName + '|DWM') -RefKey 'GPU|DWM' }
            } else {
                Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung 'Grafikspeicher-Durchsatz' -Wert 0 -Einheit 'GB/s' -Anzeige 'nicht messbar' -Status 'Info' -Hinweis ('WinSAT DWM lieferte kein Ergebnis (Rückgabecode {0}, z. B. per Remotedesktop)' -f $wr2.ExitCode)
            }
            # Anbindung direkt nach der Last lesen, im Leerlauf senken Grafikkarten die PCIe-Generation oft ab
            $glink = $null
            foreach ($g in $gpus) {
                $link = Get-PcieLink $g.PNPDeviceID
                if (-not $link) { continue }
                if ($g -eq $gMain) { $glink = $link }
                Add-Line ('  {0}: angebunden mit {1}, möglich {2}' -f $g.Name, (Format-Pcie $link), (Format-Pcie $link -Max))
                if ((& $isDisc $g) -and $link.WidthMax -gt 0 -and $link.WidthNow -lt $link.WidthMax) {
                    Add-Finding WARNUNG 'Leistung' ('{0} ist nur mit x{1} statt x{2} angebunden: falscher Steckplatz, Riser-Kabel oder Kontaktproblem.' -f $g.Name, $link.WidthNow, $link.WidthMax)
                }
            }
            if ($glink) {
                $lStat = $(if ((& $isDisc $gMain) -and $glink.WidthMax -gt 0 -and $glink.WidthNow -lt $glink.WidthMax) { 'Warnung' } elseif ($glink.GenMax -gt 0 -and $glink.GenNow -lt $glink.GenMax) { 'Info' } else { 'OK' })
                $lHint = $(if ($lStat -eq 'Info') { 'möglich {0}. Im Leerlauf schalten viele Grafikkarten die PCIe-Generation zum Stromsparen herunter.' -f (Format-Pcie $glink -Max) } else { 'möglich ' + (Format-Pcie $glink -Max) })
                Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung 'Anbindung' -Wert ($glink.GenNow * 100 + $glink.WidthNow) -Einheit '' -Anzeige (Format-Pcie $glink) -Status $lStat -Hinweis $lHint
            }
            $vramB = 0
            if ($gMain) {
                Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue | ForEach-Object {
                    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    try { if ($p.DriverDesc -eq $gpuName -and $p.'HardwareInformation.qwMemorySize') { $vramB = [math]::Max([double]$vramB, [double]$p.'HardwareInformation.qwMemorySize') } } catch { }
                }
                if (-not $vramB -and $gMain.AdapterRAM) { $vramB = [double][uint32]$gMain.AdapterRAM }
            }
            if ($vramB -gt 0) {
                $vGB = [math]::Round($vramB / 1GB, 1)
                $vStat = $(if ((& $isDisc $gMain) -and $vGB -lt 4) { 'Info' } else { 'OK' })
                Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung 'Grafikspeicher' -Wert $vGB -Einheit 'GB' -Anzeige ('{0:N0} GB' -f $vGB) -Status $vStat -Hinweis $(if (& $isDisc $gMain) { 'eigener Grafikspeicher der Karte' } else { 'dem Grafikchip zugewiesener Speicher' })
            }
            $script:BenchHead['GPU'] = (@($gpuName, $(if ($vmb) { '{0:N1} GB/s' -f ($vmb / 1000) }), $(if ($glink) { Format-Pcie $glink })) | Where-Object { $_ }) -join ' · '
            $script:BenchShort.GPU = Get-ShortGpuName $gpuName
        } catch { Write-BenchError 'Grafik' $_ }
        Send-BenchGroup 'GPU'
    }
}

if ($script:BenchSel['Disk']) {
    Invoke-Section 'Benchmark: Datenträger' {
        Initialize-Bench
        if (-not (Test-BenchTypes)) { return }
        $inv = $script:Inv; $ms = $script:BenchMs; $threads = [Environment]::ProcessorCount
        # ---------------- Datenträger ----------------
        try {
            $sizeB = $(if ($BenchmarkKurz) { 256MB } else { 1GB }); $phase = $(if ($BenchmarkKurz) { 2500 } else { 6000 })
            Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter | ForEach-Object {
                foreach ($n in 'LeosMinibench-Benchmark.tmp', 'PC-Diagnose-Benchmark.tmp') { $f = '{0}:\{1}' -f $_.DriveLetter, $n; if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
            }
            $dd = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
            foreach ($pd in @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object { [int]$_.DeviceId })) {
                $num = [int]$pd.DeviceId
                $name = ([string]$pd.FriendlyName).Trim()
                $isUsb = [string]$pd.BusType -eq 'USB'
                if ($script:BenchDiskSel.Count) { if ($script:BenchDiskSel -notcontains $num) { continue } }
                elseif ($isUsb) { Add-Line ('  {0}: USB-Datenträger, nicht ausgewählt.' -f $name); continue }
                $vol = Get-Partition -DiskNumber $num -ErrorAction SilentlyContinue | Where-Object DriveLetter |
                    ForEach-Object { Get-Volume -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue } |
                    Where-Object { $_.FileSystem -in 'NTFS', 'ReFS', 'exFAT' -and $_.SizeRemaining -gt ($sizeB * 3 + 1GB) } |
                    Sort-Object SizeRemaining -Descending | Select-Object -First 1
                if (-not $vol) { Add-Line ('  {0}: kein Laufwerksbuchstabe mit genug freiem Platz ({1} nötig), übersprungen.' -f $name, (Format-Size ($sizeB * 3 + 1GB))); continue }
                $bus = [string]$pd.BusType; $media = [string]$pd.MediaType
                $link = $null
                $w = $dd | Where-Object { $_.Index -eq $num } | Select-Object -First 1
                if ($w -and $bus -in 'NVMe', 'RAID') { $link = Get-PcieLink $w.PNPDeviceID }
                # NVMe hinter Intel VMD/RST meldet BusType RAID
                if ($bus -eq 'RAID' -and $media -eq 'SSD' -and ($link -or ($w -and "$($w.PNPDeviceID) $($w.Model)" -match 'NVME'))) { $bus = 'NVMe' }
                $path = '{0}:\LeosMinibench-Benchmark.tmp' -f $vol.DriveLetter
                $label = '{0} ({1}:)' -f $name, $vol.DriveLetter
                try {
                Write-Step ('Benchmark Datenträger {0} (Laufwerk {1}:) ...' -f $name, $vol.DriveLetter)
                Write-Checkpoint 'INFO' ('Datenträger-Benchmark {0} auf {1}' -f $name, $path)
                $task = [DiagDisk]::RunAsync($path, [long]$sizeB, $phase)
                while (-not $task.IsCompleted) { Show-Sub ('Benchmark {0} ({1}:)' -f $name, $vol.DriveLetter) ([DiagDisk]::Phase) ([DiagDisk]::Percent); Start-Sleep -Milliseconds 400 }
                Hide-Sub
                $res = $task.Result
                if ($res.Error) {
                    Add-Line ('  {0}: Messung fehlgeschlagen: {1}' -f $label, $res.Error)
                    $dErr = [pscustomobject][ordered]@{ Laufwerk = $label; Klasse = ('Fehler: ' + $res.Error); SR = 0; SW = 0; R1 = 0; R8 = 0; W1 = 0; Index = $null; RefPct = $null; Referenz = ''; Status = 'Info'; Vergleich = ''; Hinweis = $res.Error }
                    $script:BenchDisks.Add($dErr)
                    Send-GuiEvent 'BENCH' 'Info' 'Datenträger' $label 'Fehler' '' '' $res.Error '' 'Laufwerke'
                    continue
                }
                $typSeq = $null; $typRnd = $null; $refCls = ''
                if ($bus -eq 'NVMe') {
                    $gen = $(if ($link) { $link.GenNow } else { 0 }); $wid = $(if ($link) { $link.WidthNow } else { 4 })
                    $baseSeq = @{ 1 = 800; 2 = 1500; 3 = 3000; 4 = 5500; 5 = 10000; 6 = 14000 }
                    $typSeq = $(if ($baseSeq.ContainsKey($gen)) { $baseSeq[$gen] * [math]::Min(1.0, [double]$wid / 4.0) } else { 2500 })
                    $typRnd = 14000
                    $cls = $(if ($link) { 'NVMe ' + (Format-Pcie $link) } else { 'NVMe' })
                    if ($gen -ge 3 -and $wid -ge 4) { $refCls = 'NVMe' + $gen }
                } elseif ($media -eq 'SSD' -and $bus -in 'SATA', 'SAS', 'RAID', 'ATA') { $typSeq = 530; $typRnd = 9000; $cls = 'SATA-SSD'; $refCls = 'SATA-SSD' }
                elseif ($media -eq 'HDD') { $typSeq = 180; $typRnd = 120; $cls = 'Festplatte'; $refCls = 'HDD' }
                else { $cls = ('{0} {1}' -f $bus, $media).Trim() }
                $iSeq = $(if ($typSeq) { [int][math]::Round($res.SeqReadMBs / $typSeq * 100) } else { $null })
                $iRnd = $(if ($typRnd) { [int][math]::Round($res.Rnd4kQ1Iops / $typRnd * 100) } else { $null })
                $sStat = $(if ($null -eq $iSeq) { 'Info' } elseif ($iSeq -lt 40) { 'Warnung' } elseif ($iSeq -lt 65) { 'Info' } else { 'OK' })
                $rStat = $(if ($null -eq $iRnd) { 'Info' } elseif ($iRnd -lt 30) { 'Info' } else { 'OK' })
                $keyD = 'DISK|' + ([string]$pd.SerialNumber).Trim() + '|' + $name
                $rk = $(if ($refCls) { 'DISK|' + $refCls + '|' } else { '' })
                $m = @(
                    (Add-BenchResult -PassThru -NoGui -Gruppe 'Laufwerke' -Komponente 'Datenträger' -Messung ($label + ' seq. lesen') -Wert ([math]::Round($res.SeqReadMBs)) -Einheit 'MB/s' -Anzeige ('{0:N0} MB/s' -f $res.SeqReadMBs) -Index $iSeq -Status $sStat -Key ($keyD + '|SR') -RefKey $(if ($rk) { $rk + 'SR' }) -Hinweis $(if ($typSeq) { 'typisch für {0}: ca. {1:N0} MB/s' -f $cls, $typSeq } else { $cls })),
                    (Add-BenchResult -PassThru -NoGui -Gruppe 'Laufwerke' -Komponente 'Datenträger' -Messung ($label + ' seq. schreiben') -Wert ([math]::Round($res.SeqWriteMBs)) -Einheit 'MB/s' -Anzeige ('{0:N0} MB/s' -f $res.SeqWriteMBs) -Key ($keyD + '|SW') -RefKey $(if ($rk) { $rk + 'SW' }) -Hinweis ('{0} geschrieben, ohne Windows-Cache' -f (Format-Size $res.TestBytes))),
                    (Add-BenchResult -PassThru -NoGui -Gruppe 'Laufwerke' -Komponente 'Datenträger' -Messung ($label + ' 4K zufällig QD1') -Wert ([math]::Round($res.Rnd4kQ1Iops)) -Einheit 'IOPS' -Anzeige ('{0:N0} IOPS' -f $res.Rnd4kQ1Iops) -Index $iRnd -Status $rStat -Key ($keyD + '|R1') -RefKey $(if ($rk) { $rk + 'R1' }) -Hinweis $(if ($typRnd) { 'typisch für {0}: ca. {1:N0} IOPS' -f $cls, $typRnd } else { '' })),
                    (Add-BenchResult -PassThru -NoGui -Gruppe 'Laufwerke' -Komponente 'Datenträger' -Messung ($label + ' 4K zufällig 8 Threads') -Wert ([math]::Round($res.Rnd4kT8Iops)) -Einheit 'IOPS' -Anzeige ('{0:N0} IOPS' -f $res.Rnd4kT8Iops) -Key ($keyD + '|R8') -RefKey $(if ($rk) { $rk + 'R8' }))
                )
                if ($res.Rnd4kWriteQ1Iops -gt 0) {
                    $m += (Add-BenchResult -PassThru -NoGui -Gruppe 'Laufwerke' -Komponente 'Datenträger' -Messung ($label + ' 4K zufällig schreiben QD1') -Wert ([math]::Round($res.Rnd4kWriteQ1Iops)) -Einheit 'IOPS' -Anzeige ('{0:N0} IOPS' -f $res.Rnd4kWriteQ1Iops) -Key ($keyD + '|W1') -RefKey $(if ($rk) { $rk + 'W1' }))
                }
                $dStat = 'OK'; foreach ($mx in $m) { if ((Get-StatusRank $mx.Status) -gt (Get-StatusRank $dStat)) { $dStat = $mx.Status } }
                $dRef = Get-GeoMean ($m | ForEach-Object { $_.RefPct })
                $dCmp = (@($m | Where-Object { $_.Vergleich } | ForEach-Object { $_.Vergleich }) | Select-Object -First 1)
                $dHint = (@($cls) + @($m | Where-Object { $_.Status -ne 'OK' -or $_.Vergleich -match '^-' } | ForEach-Object { ('{0}: {1} {2}' -f ($_.Messung -replace [regex]::Escape($label + ' '), ''), $_.Anzeige, $_.Vergleich).Trim() })) -join '; '
                $disk = [pscustomobject][ordered]@{ Laufwerk = $label; Klasse = $cls; SR = $res.SeqReadMBs; SW = $res.SeqWriteMBs; R1 = $res.Rnd4kQ1Iops; R8 = $res.Rnd4kT8Iops; W1 = $res.Rnd4kWriteQ1Iops
                    Index = $iSeq; RefPct = $dRef; Referenz = $(if ($null -ne $dRef) { '{0} %' -f $dRef } else { '' }); Status = $dStat; Vergleich = $(if ($dCmp) { $dCmp } else { '' }); Hinweis = $dHint }
                $script:BenchDisks.Add($disk)
                Send-GuiEvent 'BENCH' $dStat 'Datenträger' ('{0} · {1}' -f $label, $cls) ('{0:N0} / {1:N0} MB/s' -f $res.SeqReadMBs, $res.SeqWriteMBs) $(if ($null -ne $iSeq) { $iSeq } else { '' }) $disk.Vergleich `
                    ('Lesen {0:N0} MB/s, Schreiben {1:N0} MB/s, 4K QD1 {2:N0} IOPS, 4K 8 Threads {3:N0} IOPS, 4K schreiben {4:N0} IOPS. {5}' -f $res.SeqReadMBs, $res.SeqWriteMBs, $res.Rnd4kQ1Iops, $res.Rnd4kT8Iops, $res.Rnd4kWriteQ1Iops, $dHint) $disk.Referenz 'Laufwerke'
                if ($sStat -eq 'Warnung') { Add-Finding WARNUNG 'Leistung' ('{0} liest sequentiell nur {1:N0} MB/s, typisch für {2} sind ca. {3:N0} MB/s. Anbindung, Treiber, Füllstand, Temperatur oder Zustand der SSD prüfen.' -f $label, $res.SeqReadMBs, $cls, $typSeq) }
                if ($link -and $link.WidthMax -gt 0 -and $link.WidthNow -lt $link.WidthMax) { Add-Finding WARNUNG 'Leistung' ('{0} ist nur mit x{1} statt x{2} angebunden.' -f $name, $link.WidthNow, $link.WidthMax) }
                if ($link -and $link.GenMax -gt 0 -and $link.GenNow -lt $link.GenMax) { Add-Finding INFO 'Leistung' ('{0} läuft mit PCIe {1}.0, unterstützt aber PCIe {2}.0 (Steckplatz oder Mainboard begrenzt).' -f $name, $link.GenNow, $link.GenMax) }
                } catch { Write-BenchError ('Datenträger ' + $name) $_; Remove-Item $path -Force -ErrorAction SilentlyContinue }
            }
            $okDisks = @($script:BenchDisks | Where-Object { $_.SR -gt 0 })
            if ($okDisks.Count) {
                $fast = $okDisks | Sort-Object SR -Descending | Select-Object -First 1
                $script:BenchHead['Laufwerke'] = '{0} {1} · schnellstes {2:N0} MB/s lesen ({3})' -f $okDisks.Count, $(if ($okDisks.Count -eq 1) { 'Laufwerk' } else { 'Laufwerke' }), $fast.SR, $fast.Klasse
            }
        } catch { Write-BenchError 'Datenträger' $_ }
        Send-BenchGroup 'Laufwerke'
    }
}

if ($script:BenchSel['WinSAT']) {
    Invoke-Section 'Benchmark: WinSAT-Leistungsbewertung' {
        Initialize-Bench
        Write-Step 'winsat formal läuft (ca. 2 bis 5 Minuten) ...'
        $t0 = Get-Date
        $r = Invoke-External -File "$env:windir\System32\winsat.exe" -Arguments 'formal -restart clean' -TimeoutSec 1200 -Progress 'WinSAT Leistungsbewertung' -ExpectedSec 240
        $r.Output | Out-File (Join-Path $RawDir 'winsat.txt') -Encoding UTF8
        if ($r.ExitCode -ne 0) { Add-Line ('  WinSAT Rückgabecode {0} (auf Akku, per Remotedesktop oder in VMs oft nicht möglich).' -f $r.ExitCode) }
        $xmlFile = Get-ChildItem "$env:windir\Performance\WinSAT\DataStore\*Formal.Assessment*.xml" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $fresh = [bool]($xmlFile -and $xmlFile.LastWriteTime -ge $t0.AddMinutes(-1))
        $ws = Get-CimInstance Win32_WinSAT -ErrorAction SilentlyContinue
        if ($ws -and $fresh) {
            $ws | Select-Object @{n = 'CPU'; e = { $_.CPUScore } }, @{n = 'RAM'; e = { $_.MemoryScore } }, @{n = 'Datenträger'; e = { $_.DiskScore } },
                @{n = 'Grafik'; e = { $_.GraphicsScore } }, @{n = 'Spielegrafik'; e = { $_.D3DScore } }, @{n = 'Gesamt'; e = { $_.WinSPRLevel } } | Out-Report
            Add-Line '  Hinweis: Die Spielegrafik-Bewertung ist seit Windows 10 fest auf 9,9 gesetzt und ohne Aussagekraft.'
            foreach ($p in @(@('CPU', 'Prozessor', $ws.CPUScore), @('RAM', 'Arbeitsspeicher', $ws.MemoryScore), @('DISK', 'Systemlaufwerk', $ws.DiskScore), @('GFX', 'Grafik (Desktop)', $ws.GraphicsScore))) {
                $sv = [double]$p[2]
                if ($sv -gt 0) { Add-BenchResult -Gruppe 'WinSAT' -Komponente 'WinSAT' -Messung $p[1] -Wert $sv -Einheit 'von 9,9' -Anzeige ('{0:N1} von 9,9' -f $sv) -Index ([int][math]::Round($sv / 9.9 * 100)) -Status $(if ($sv -lt 4) { 'Info' } else { 'OK' }) -Key ('WINSAT|' + $p[0]) }
            }
            $script:WinsatTotal = [double]$ws.WinSPRLevel
            $script:BenchHead['WinSAT'] = 'Gesamt {0:N1} (niedrigster Teilwert)' -f [double]$ws.WinSPRLevel
            Send-BenchGroup 'WinSAT'
            Add-TestResult 'Leistungsbewertung (WinSAT)' 'OK' ('CPU {0}, RAM {1}, Datenträger {2}, Grafik {3}' -f $ws.CPUScore, $ws.MemoryScore, $ws.DiskScore, $ws.GraphicsScore)
        } else { Add-TestResult 'Leistungsbewertung (WinSAT)' 'Info' ('keine neue Bewertung (Rückgabecode {0})' -f $r.ExitCode) }
        if ($xmlFile -and $fresh) {
            try {
                [xml]$x = Get-Content $xmlFile.FullName -Raw
                Add-Sub 'Messwerte'
                $x.SelectNodes('//Metrics//*[not(*)]') | ForEach-Object {
                    $u = $_.GetAttribute('units')
                    [pscustomobject]@{ Bereich = $_.ParentNode.Name; Messung = $_.Name; Wert = $_.InnerText; Einheit = $u }
                } | Where-Object { $_.Wert -and $_.Bereich -ne 'GamingMetrics' } | Sort-Object Bereich, Messung, Wert -Unique | Select-Object -First 50 | Out-Report
            } catch { }
        }
    }
}


Invoke-Section 'Benchmark: Auswertung und Vergleich' {
    $inv = $script:Inv
        # ---------------- Zusammenfassung, Verlauf, Referenz, CSV ----------------
        Initialize-Bench
        if (-not $script:BenchResults.Count -and -not $script:BenchDisks.Count) { Add-Line '  Keine Messwerte vorhanden.'; Add-TestResult 'Benchmark' 'Info' 'keine Messwerte'; return }
        Add-Sub 'Ergebnisse'
        $sumParts = @()
        foreach ($gk in $script:BenchGroupOrder) {
            $g = Get-BenchGroup $gk
            if (-not $g.Anzahl) { continue }
            if ($null -ne $g.RefPct) { $sumParts += ('{0} {1} %' -f $gk, $g.RefPct) }
            Add-Line
            Add-Line ('  {0}   [{1}]{2}' -f $g.Name.ToUpper(), $g.Status, $(if ($g.Referenz) { '   Referenz ' + $g.Referenz } else { '' }))
            if ($g.Kopf) { Add-Line ('  ' + $g.Kopf) }
            if ($gk -eq 'Laufwerke') {
                $fz = { param($v) if ([double]$v -gt 0) { '{0:N0}' -f [double]$v } else { '' } }
                $g.Disks | Select-Object Status, Laufwerk, Klasse, @{n = 'Lesen'; e = { & $fz $_.SR } }, @{n = 'Schreiben'; e = { & $fz $_.SW } }, @{n = '4K QD1'; e = { & $fz $_.R1 } },
                    @{n = '4K 8T'; e = { & $fz $_.R8 } }, @{n = '4K Schr.'; e = { & $fz $_.W1 } }, Index, Referenz, Vergleich | Out-Report
                Add-Line '  Lesen und Schreiben in MB/s, 4K-Werte in IOPS.'
            } else {
                $g.Items | Select-Object Status, Messung, @{n = 'Wert'; e = { $_.Anzeige } }, Index, Referenz, Vergleich, Hinweis | Out-Report
            }
        }
        $script:BenchRefSummary = $(if ($sumParts.Count) { 'Im Vergleich zur Referenz {0}: {1}' -f $script:Ref.Name, ($sumParts -join ', ') } else { '' })
        if ($script:BenchRefSummary) { Add-Line; Add-Line ('  ' + $script:BenchRefSummary) }
        $refParts = @(@((($script:BenchShort.CPU -as [string]) -replace '^(AMD|Intel)\s*', ''), $script:BenchShort.RAM, $script:BenchShort.GPU) | Where-Object { $_ })
        $script:BenchRefName = ('{0} ({1})' -f [Environment]::MachineName, ($refParts -join ', '))
        Add-BenchComparison
        if ($ReferenzSpeichern) {
            if ($BenchmarkKurz) { Add-Line '  Hinweis: Referenz aus einem Kurzlauf gespeichert, Werte mit voller Messdauer sind stabiler.' }
            $saved = @(Save-BenchReference)
            if ($saved.Count) { Add-Line ('  Referenz gespeichert: {0}' -f ($saved -join ', ')); Add-Finding INFO 'Leistung' ('Die Messwerte dieses PCs sind als Standardreferenz gespeichert ({0}). Andere PCs, die mit demselben Datenordner arbeiten, vergleichen sich ab jetzt damit.' -f $saved[-1]) }
        }
        try {
            $script:BenchResults | Select-Object @{n = 'Computer'; e = { $env:COMPUTERNAME } }, @{n = 'Modell'; e = { $script:Facts['System'] } }, @{n = 'Datum'; e = { (Get-Date).ToString('yyyy-MM-dd HH:mm', $inv) } },
                Gruppe, Komponente, Messung, @{n = 'Wert'; e = { $_.Wert.ToString($inv) } }, Einheit, Index, Status, Referenz, Vergleich, Hinweis |
                Export-Csv -Path (Join-Path $RawDir 'Benchmark.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
            Add-Line '  Rohwerte für den Vergleich mehrerer PCs: Benchmark.csv im Anhang'
        } catch { }
        $bw = @($script:BenchResults | Where-Object Status -eq 'Warnung').Count
        $grps = @($script:BenchGroupOrder | Where-Object { (Get-BenchGroup $_).Anzahl })
        $want = @(@{ CPU = 'CPU'; RAM = 'RAM'; GPU = 'GPU'; Disk = 'Laufwerke'; WinSAT = 'WinSAT' }.GetEnumerator() | Where-Object { $script:BenchSel[$_.Key] } | ForEach-Object { $_.Value })
        $missing = @($want | Where-Object { $grps -notcontains $_ })
        Add-TestResult 'Benchmark' $(if ($bw) { 'Warnung' } elseif ($missing.Count) { 'Info' } else { 'OK' }) ('{0} Messwerte für {1}, {2} auffällig{3}{4}' -f $script:BenchResults.Count, ($grps -join ', '), $bw,
            $(if ($missing.Count) { ', ohne Ergebnis: ' + ($missing -join ', ') } else { '' }), $(if ($sumParts.Count) { '. Referenz: ' + ($sumParts -join ', ') } else { '' }))
}
}   # Ende: if ($ModBench)


# =====================================================================================
#                                     LASTTEST
# =====================================================================================
# Ab 2.3 mit Sensoren: Temperatur-, Takt-, Leistungs- und Lüfterkurven, Drosselnachweis und Abbruchschwelle.
if ($ModLast -and (Test-StepEnabled 'Last:alle')) {
    $ltNames = @{ CPU = 'CPU'; RAM = 'RAM'; GPU = 'Grafik'; Disk = 'Datenträger' }
    $ltTitle = (@($script:LastPlan.Keys | Where-Object { $script:LastPlan[$_] -gt 0 } | ForEach-Object { '{0} {1} Min.' -f $ltNames[$_], $script:LastPlan[$_] }) -join ', ')
    Invoke-Section ('Lasttest ({0})' -f $ltTitle) {
        if (-not $TypesLoaded) { Add-Line '  Übersprungen: C#-Routinen nicht verfügbar (Constrained Language Mode).'; Add-TestResult 'Lasttest' 'Übersprungen' 'Constrained Language Mode'; return }
        $plan = $script:LastPlan
        $threads = [Environment]::ProcessorCount

        # Sensoren öffnen und Leerlaufwerte messen, bevor die Last beginnt
        Show-Sub 'Lasttest' 'Sensoren werden geöffnet' -1
        [void](Open-SensorSession -Treiber:$SensorTreiber)
        $idleSamples = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt 3; $i++) { [void]$idleSamples.Add((Get-SensorLead (Get-SensorReadings -MitDatentraeger:($i -eq 0)))); Start-Sleep -Milliseconds 700 }
        $idle = $idleSamples[$idleSamples.Count - 1]
        $tjMax = @($idleSamples | Where-Object { $_.TjMax } | ForEach-Object { $_.TjMax }) | Select-Object -First 1
        $cpuLimit = Get-AbortLimit $LastAbbruchCpu $tjMax 100
        $gpuLimit = Get-AbortLimit $LastAbbruchGpu $null 90
        # automatisch: an TjMax erst nach rund einer Minute (20 Messpunkte), feste Schwellen nach rund 10 Sekunden
        $cpuHold = $(if (([string]$LastAbbruchCpu).Trim().ToLowerInvariant() -eq 'auto') { 20 } else { 3 })
        $script:LoadLimits = [pscustomobject]@{ Cpu = $cpuLimit; Gpu = $gpuLimit; TjMax = $tjMax }
        Send-GuiEvent 'SENSLIM' (Format-SensorValue $cpuLimit) (Format-SensorValue $gpuLimit) (Format-SensorValue $tjMax)
        Add-Line ('  Sensoren: {0}' -f (Get-SensorSourceText))
        Add-Line ('  Leerlauf vor der Last: CPU {0}, GPU {1}, Paketleistung {2}' -f $(if ($null -ne $idle.CpuTemp) { '{0:N0} °C ({1})' -f $idle.CpuTemp, $idle.CpuTempQ } else { 'Temperatur nicht verfügbar' }), $(if ($null -ne $idle.GpuTemp) { '{0:N0} °C' -f $idle.GpuTemp } else { 'nicht verfügbar' }), $(if ($null -ne $idle.CpuW) { '{0:N0} W' -f $idle.CpuW } else { 'nicht verfügbar' }))
        Add-Line ('  Abbruchschwelle: CPU {0}, GPU {1} (Abbruch, wenn die Temperatur {2} Messpunkte in Folge auf oder über der Schwelle liegt, GPU 3)' -f $(if ($cpuLimit) { '{0:N0} °C{1}' -f $cpuLimit, $(if ($LastAbbruchCpu -eq 'auto') { $(if ($tjMax) { ' (TjMax)' } else { ' (automatisch, TjMax unbekannt)' }) } else { '' }) } else { 'aus' }), $(if ($gpuLimit) { '{0:N0} °C' -f $gpuLimit } else { 'aus' }), $cpuHold)
        if ($cpuLimit -and $idle.CpuTempQ -eq 'ACPI') { Add-Line '  Hinweis: Als CPU-Temperatur steht nur die ACPI-Thermalzone zur Verfügung; sie zählt für den Abbruch erst, wenn sie sich unter Last bewegt.' }
        elseif ($cpuLimit -and $null -eq $idle.CpuTemp) { Add-Line '  Hinweis: Keine CPU-Temperatur verfügbar, die CPU-Abbruchschwelle kann nicht greifen.' }

        $t0 = Get-Date
        $end = @{}
        foreach ($k in @($plan.Keys)) { if ($plan[$k] -gt 0) { $end[$k] = $t0.AddMinutes($plan[$k]) } }
        $tEnd = @($end.Values | Sort-Object -Descending)[0]
        $stopFile = Join-Path $script:CpDir 'stop.flag'
        Remove-Item $stopFile -Force -ErrorAction SilentlyContinue
        [DiagCpu]::Stop = $false; [DiagRam]::Stop = $false; [DiagDiskStress]::Stop = $false
        $cpuTask = $null; $ramTask = $null; $diskTask = $null; $gpuProc = $null; $gpuRuns = 0
        $useGpu = $end.ContainsKey('GPU')
        $diskPath = $null; $diskLetter = ''

        Add-Line '  Belastet werden gleichzeitig, jeweils mit eigener Dauer:'
        if ($end.ContainsKey('CPU')) {
            $cpuTask = [DiagCpu]::RunAsync([int]($plan.CPU * 60) + 60, $threads)
            Add-Line ('    Prozessor      : {0} Min., {1} Threads mit Ergebnisprüfung' -f $plan.CPU, $threads)
        }
        if ($end.ContainsKey('RAM')) {
            $os = Get-CimInstance Win32_OperatingSystem
            $ramTarget = [long]([double]$os.FreePhysicalMemory * 1KB * $LastRamProzent / 100)
            if (-not [Environment]::Is64BitProcess) { $ramTarget = [math]::Min($ramTarget, 1.2GB) }
            $ramTask = [DiagRam]::RunAsync($ramTarget, 100000)
            Add-Line ('    Arbeitsspeicher: {0} Min., Mustertest über {1} ({2} % des freien RAM)' -f $plan.RAM, (Format-Size $ramTarget), $LastRamProzent)
        }
        if ($end.ContainsKey('GPU')) { Add-Line ('    Grafik         : {0} Min., WinSAT-DWM-Schleife (leichte Last, für Volllast OCCT oder FurMark nutzen)' -f $plan.GPU) }
        if ($end.ContainsKey('Disk')) {
            $diskLetter = $(if ($LastDiskLaufwerk) { $LastDiskLaufwerk.Substring(0, 1).ToUpperInvariant() } else { $env:SystemDrive.Substring(0, 1) })
            $vol = Get-Volume -DriveLetter $diskLetter -ErrorAction SilentlyContinue
            if (-not $vol -or $vol.SizeRemaining -lt 2GB) {
                Add-Line ('    Datenträger    : Laufwerk {0}: hat zu wenig freien Platz oder fehlt, Datenträgerlast entfällt.' -f $diskLetter)
                $end.Remove('Disk')
            } else {
                $sizeB = [long][math]::Max(256MB, [math]::Min(4GB, [double]$vol.SizeRemaining * 0.1))
                $diskPath = '{0}:\LeosMinibench-Lasttest.tmp' -f $diskLetter
                $diskTask = [DiagDiskStress]::RunAsync($diskPath, $sizeB, [int]($plan.Disk * 60))
                Add-Line ('    Datenträger    : {0} Min., Laufwerk {1}: mit {2} Testdatei, Schreiben, Lesen und Datenprüfung' -f $plan.Disk, $diskLetter, (Format-Size $sizeB))
                Write-Checkpoint 'INFO' ('Lasttest Datenträger auf {0}' -f $diskPath)
            }
        }
        Send-GuiEvent 'STOP' '1'
        Write-Step ('Lasttest läuft bis ca. {0:HH:mm} Uhr. Die Schaltfläche "Test beenden" beendet ihn vorzeitig.' -f $tEnd)

        $samples = New-Object System.Collections.ArrayList
        $done = @{}; $stopped = $false; $abort = $null
        $lastBytes = 0L; $lastT = Get-Date
        while ($true) {
            $now = Get-Date
            if ($cpuTask -and -not $done.ContainsKey('CPU') -and ($now -ge $end.CPU -or $stopped)) { [DiagCpu]::Stop = $true; $done.CPU = $now }
            if ($ramTask -and -not $done.ContainsKey('RAM') -and ($now -ge $end.RAM -or $stopped)) { [DiagRam]::Stop = $true; $done.RAM = $now }
            if ($end.ContainsKey('GPU') -and -not $done.ContainsKey('GPU') -and ($now -ge $end.GPU -or $stopped -or -not $useGpu)) {
                $done.GPU = $now; $useGpu = $false
                if ($gpuProc -and -not $gpuProc.HasExited) { try { $gpuProc.Kill() } catch { } }
            }
            if ($diskTask -and -not $done.ContainsKey('Disk')) {
                if ($stopped) { [DiagDiskStress]::Stop = $true }
                if ($diskTask.IsCompleted) { $done.Disk = $now }
            }
            if ($useGpu -and $gpuProc -and $gpuProc.HasExited) {
                try { if (($gpuProc.ExitTime - $gpuProc.StartTime).TotalSeconds -lt 5) { $useGpu = $false; Add-Line '  WinSAT DWM beendet sich sofort (z. B. Remotedesktop), die Grafiklast wird abgeschaltet.' } } catch { }
            }
            if ($useGpu -and (-not $gpuProc -or $gpuProc.HasExited)) {
                try { $gpuProc = Start-Process -FilePath "$env:windir\System32\winsat.exe" -ArgumentList 'dwm' -WindowStyle Hidden -PassThru -ErrorAction Stop; $gpuRuns++ } catch { $useGpu = $false }
            }
            $pending = @($end.Keys | Where-Object { -not $done.ContainsKey($_) })
            if (-not $pending.Count) { break }

            $s = Get-CpuSample
            $lead = Get-SensorLead (Get-SensorReadings -CpuSample $s)
            $el = ($now - $t0).TotalSeconds
            $bytes = [DiagDiskStress]::BytesRead + [DiagDiskStress]::BytesWritten
            $dMBs = $(if ($diskTask -and -not $done.ContainsKey('Disk')) { [math]::Round(($bytes - $lastBytes) / 1MB / [math]::Max(0.5, ($now - $lastT).TotalSeconds)) } else { $null })
            $lastBytes = $bytes; $lastT = $now
            [void]$samples.Add([pscustomobject]@{ T = [int]$el; MHz = $s.MHz; Last = $s.Last; Leistung = $s.Leistung; MaxFreq = $s.MaxFreq; Temp = $s.Temp
                CpuTemp = $lead.CpuTemp; CpuTempQ = $lead.CpuTempQ; CpuMHz = $lead.CpuMHz; CpuW = $lead.CpuW; GpuTemp = $lead.GpuTemp; GpuMHz = $lead.GpuMHz; GpuW = $lead.GpuW
                Fan = $lead.Fan; DiskTemp = $lead.DiskTemp; DiskMBs = $dMBs; Cpu = [bool]($cpuTask -and -not $done.ContainsKey('CPU')) })
            Send-SensorLead $el $lead
            # Abbruchschwelle: drei Messpunkte in Folge (rund 10 Sekunden) an oder über der Grenze
            if (-not $abort -and -not $stopped) {
                $recent = $samples.GetRange([math]::Max(0, $samples.Count - 25), [math]::Min(25, $samples.Count))
                $ab = Test-LoadAbort $recent $cpuLimit $gpuLimit 3 $cpuHold
                if ($ab.Abbruch) {
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
            $st = @('CPU {0} %   Takt {1} MHz   Temp {2}' -f $s.Last, $s.MHz, $tTxt)
            if ($null -ne $lead.CpuW) { $st += ('{0:N0} W' -f $lead.CpuW) }
            if ($null -ne $lead.GpuTemp) { $st += ('GPU {0:N0} °C' -f $lead.GpuTemp) }
            if ($cpuTask) { $st += ('Rechenfehler {0}' -f [DiagCpu]::Errors) }
            if ($ramTask) { $st += ('RAM-Fehler {0}' -f [DiagRam]::Errors) }
            if ($diskTask) { $st += ('Datenträger {0} MB/s, Fehler {1}' -f $(if ($null -ne $dMBs) { $dMBs } else { 0 }), ([DiagDiskStress]::Errors + [DiagDiskStress]::IoErrors)) }
            Show-Sub ('Lasttest   {0} %   noch {1:hh\:mm\:ss}   aktiv: {2}' -f $pc, $left, (($pending | ForEach-Object { $ltNames[$_] }) -join ', ')) ($st -join '   ') $pc
            for ($w = 0; $w -lt 5 -and -not $stopped; $w++) {
                Start-Sleep -Milliseconds 500
                if (Test-Path $stopFile) { Remove-Item $stopFile -Force -ErrorAction SilentlyContinue; $stopped = $true; Write-Step 'Lasttest wird vorzeitig beendet ...' }
            }
        }
        [DiagCpu]::Stop = $true; [DiagRam]::Stop = $true; [DiagDiskStress]::Stop = $true
        Send-GuiEvent 'STOP' '0'
        Show-Sub 'Lasttest' 'wird beendet' -1
        try { if ($cpuTask) { [void]$cpuTask.Wait(30000) } } catch { }
        try { if ($ramTask) { [void]$ramTask.Wait(120000) } } catch { }
        try { if ($diskTask) { [void]$diskTask.Wait(120000) } } catch { }
        if ($gpuProc -and -not $gpuProc.HasExited) { try { $gpuProc.Kill() } catch { } }
        if ($diskPath) { Remove-Item $diskPath -Force -ErrorAction SilentlyContinue }
        $real = (Get-Date) - $t0
        # Abkühlung: 30 Sekunden nachmessen, wie schnell die Temperatur fällt
        $coolStart = Get-Date
        if ($samples.Count -and $null -ne $samples[$samples.Count - 1].CpuTemp) {
            while (((Get-Date) - $coolStart).TotalSeconds -lt 30) {
                Show-Sub 'Lasttest' ('Abkühlung wird gemessen ({0:N0} s)' -f (30 - ((Get-Date) - $coolStart).TotalSeconds)) -1
                $s = Get-CpuSample; $lead = Get-SensorLead (Get-SensorReadings -CpuSample $s)
                $el = ((Get-Date) - $t0).TotalSeconds
                [void]$samples.Add([pscustomobject]@{ T = [int]$el; MHz = $s.MHz; Last = $s.Last; Leistung = $s.Leistung; MaxFreq = $s.MaxFreq; Temp = $s.Temp
                    CpuTemp = $lead.CpuTemp; CpuTempQ = $lead.CpuTempQ; CpuMHz = $lead.CpuMHz; CpuW = $lead.CpuW; GpuTemp = $lead.GpuTemp; GpuMHz = $lead.GpuMHz; GpuW = $lead.GpuW
                    Fan = $lead.Fan; DiskTemp = $lead.DiskTemp; DiskMBs = $null; Cpu = $false; Abkuehlung = $true })
                Send-SensorLead $el $lead
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

        $mhzAll = $loadS | Measure-Object MHz -Minimum -Maximum -Average
        $tv = @($loadS | Where-Object { $_.Temp } | ForEach-Object { $_.Temp } | Select-Object -Unique)
        $tStatic = $tv.Count -le 1
        $tMax = $(if ($tv.Count) { ($tv | Measure-Object -Maximum).Maximum } else { $null })
        $cpuT = @($loadS | Where-Object { $null -ne $_.CpuTemp -and $_.CpuTempQ -ne 'ACPI' })
        $cpuTMax = $(if ($cpuT.Count) { ($cpuT | Measure-Object CpuTemp -Maximum).Maximum } else { $null })
        $gpuT = @($loadS | Where-Object { $null -ne $_.GpuTemp })
        $gpuTMax = $(if ($gpuT.Count) { ($gpuT | Measure-Object GpuTemp -Maximum).Maximum } else { $null })
        $cpuWMax = $(if (@($loadS | Where-Object { $null -ne $_.CpuW }).Count) { ($loadS | Where-Object { $null -ne $_.CpuW } | Measure-Object CpuW -Maximum).Maximum } else { $null })
        $gpuWMax = $(if (@($loadS | Where-Object { $null -ne $_.GpuW }).Count) { ($loadS | Where-Object { $null -ne $_.GpuW } | Measure-Object GpuW -Maximum).Maximum } else { $null })
        $fanMax = $(if (@($loadS | Where-Object { $null -ne $_.Fan }).Count) { ($loadS | Where-Object { $null -ne $_.Fan } | Measure-Object Fan -Maximum).Maximum } else { $null })
        $diskTMax = $(if (@($loadS | Where-Object { $null -ne $_.DiskTemp }).Count) { ($loadS | Where-Object { $null -ne $_.DiskTemp } | Measure-Object DiskTemp -Maximum).Maximum } else { $null })
        Add-Line ('  Effektiver Takt (Windows): min {0:N0} / Ø {1:N0} / max {2:N0} MHz' -f $mhzAll.Minimum, $mhzAll.Average, $mhzAll.Maximum)
        if ($null -ne $cpuTMax) { Add-Line ('  CPU-Temperatur (Sensoren): Leerlauf {0:N0} °C, max {1:N0} °C{2}' -f $idle.CpuTemp, $cpuTMax, $(if ($tjMax) { ', TjMax {0:N0} °C' -f $tjMax } else { '' })) }
        else { Add-Line ('  Temperatur: {0}' -f $(if (-not $tv.Count) { 'nicht auslesbar' } elseif ($tStatic) { 'nur statischer ACPI-Wert verfügbar' } else { 'max {0} °C (ACPI-Thermalzone)' -f $tMax })) }
        if ($null -ne $cpuWMax) { Add-Line ('  CPU-Paketleistung: max {0:N0} W' -f $cpuWMax) }
        if ($null -ne $gpuTMax) { Add-Line ('  GPU: Temperatur max {0:N0} °C{1}' -f $gpuTMax, $(if ($null -ne $gpuWMax) { ', Leistung max {0:N0} W' -f $gpuWMax } else { '' })) }
        if ($null -ne $fanMax) { Add-Line ('  Lüfter: max {0:N0} U/min' -f $fanMax) }
        if ($null -ne $diskTMax) { Add-Line ('  Datenträger: Temperatur max {0:N0} °C' -f $diskTMax) }
        $cool = @($samples | Where-Object { $_.Abkuehlung -and $null -ne $_.CpuTemp })
        if ($cool.Count -and $null -ne $cpuTMax) { Add-Line ('  Abkühlung: {0} s nach Lastende {1:N0} °C, {2:N0} K unter dem Höchstwert' -f ($cool[$cool.Count - 1].T - $loadS[$loadS.Count - 1].T), $cool[$cool.Count - 1].CpuTemp, ($cpuTMax - $cool[$cool.Count - 1].CpuTemp)) }
        if (@($loadS | ForEach-Object { $_.MHz } | Select-Object -Unique).Count -le 1 -and $loadS.Count -gt 3) { Add-Line '  Hinweis: Der Taktwert von Windows blieb über alle Messpunkte gleich (Festwert des Leistungszählers); bewertet wird der Sensortakt, falls vorhanden.' }

        if ($cpuTask) {
            $cpuErr = [DiagCpu]::Errors
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
            if ($th.Stufe -and ($cpuMin -ge 2 -or $th.Status -eq 'thermisch')) {
                Add-Finding $th.Stufe 'Lasttest' $th.Befund
                if ($th.Stufe -eq 'WARNUNG' -and $st -eq 'OK') { $st = 'Warnung' }
            } elseif ($th.Status -eq 'nicht bewertbar' -and $cpuMin -ge 3) { Add-Finding INFO 'Lasttest' ('Drosselnachweis nicht möglich: {0}.' -f $th.Befund) }
            if ($perfMin -and $perfMin -lt 70) { Add-Finding WARNUNG 'Lasttest' ('Der CPU-Takt fiel unter Dauerlast zeitweise auf {0} % des Basistakts.' -f $perfMin); if ($st -eq 'OK') { $st = 'Warnung' } }
            if ($null -ne $cpuTMax -and $cpuTMax -ge 95 -and $th.Status -ne 'thermisch') { Add-Finding INFO 'Lasttest' ('Die CPU erreichte unter Dauerlast {0:N0} °C.' -f $cpuTMax) }
            elseif ($null -eq $cpuTMax -and $tMax -and -not $tStatic -and $tMax -ge 95) { Add-Finding WARNUNG 'Lasttest' ('Die Thermalzone erreichte {0} °C unter Dauerlast.' -f $tMax); if ($st -eq 'OK') { $st = 'Warnung' } }
            $det = ('{0} Threads, {1:N0} Rechendurchläufe, {2} Rechenfehler, Ø {3:N0} MHz, Taktverlauf {4:+0.0;-0.0;0} %{5}{6}, Drosselung: {7}' -f $threads, [DiagCpu]::Iterations, $cpuErr, $mhz.Average, $(if ($null -ne $th.Abfall) { -$th.Abfall } else { 0 }),
                $(if ($null -ne $cpuTMax) { ', max {0:N0} °C' -f $cpuTMax } else { '' }), $(if ($null -ne $cpuWMax) { ', max {0:N0} W' -f $cpuWMax } else { '' }), $th.Status)
            Add-Line ('  Prozessor      : {0}, {1}' -f (& $dur 'CPU'), $det)
            $script:LoadParts.Add([pscustomobject]@{ Komponente = 'Prozessor'; Dauer = (& $dur 'CPU'); Ergebnis = $st; Details = $det }); & $setStatus $st
        }
        if ($ramTask) {
            $ramErr = [DiagRam]::Errors
            $st = $(if ($ramErr -gt 0) { 'Fehler' } else { 'OK' })
            if ($ramErr -gt 0) { Add-Finding KRITISCH 'Lasttest' ('{0} Bitfehler im RAM unter Dauerlast: EXPO/XMP deaktivieren und die Module einzeln prüfen (MemTest86).' -f $ramErr) }
            $det = ('{0} geprüft, {1} Bitfehler' -f (Format-Size ([DiagRam]::BytesTested)), $ramErr)
            Add-Line ('  Arbeitsspeicher: {0}, {1}' -f (& $dur 'RAM'), $det)
            try { $rr = $ramTask.Result; ($rr -split "`r?`n" | Where-Object { $_ -match 'erwartet' } | Select-Object -First 10) | ForEach-Object { Add-Line ('    ' + $_.Trim()) } } catch { }
            $script:LoadParts.Add([pscustomobject]@{ Komponente = 'Arbeitsspeicher'; Dauer = (& $dur 'RAM'); Ergebnis = $st; Details = $det }); & $setStatus $st
        }
        if ($end.ContainsKey('GPU')) {
            $det = ('{0} WinSAT-DWM-Durchläufe{1}' -f $gpuRuns, $(if ($null -ne $gpuTMax) { ', GPU max {0:N0} °C' -f $gpuTMax } else { '' }))
            Add-Line ('  Grafik         : {0}, {1}' -f (& $dur 'GPU'), $det)
            $script:LoadParts.Add([pscustomobject]@{ Komponente = 'Grafik'; Dauer = (& $dur 'GPU'); Ergebnis = $(if ($gpuRuns) { 'OK' } else { 'Info' }); Details = $det })
        }
        if ($diskTask) {
            $res = ''; try { $res = [string]$diskTask.Result } catch { $res = $_.Exception.Message }
            $dErr = [DiagDiskStress]::Errors; $ioErr = [DiagDiskStress]::IoErrors
            $dEv = @(foreach ($pv in 'disk', 'storahci', 'stornvme') { Get-Ev @{ LogName = 'System'; ProviderName = $pv; Level = 1, 2, 3; StartTime = $t0 } 200 })
            $st = 'OK'
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
        try { $samples | Select-Object T, MHz, Last, Leistung, MaxFreq, Temp, CpuTemp, CpuTempQ, CpuMHz, CpuW, GpuTemp, GpuMHz, GpuW, Fan, DiskTemp, DiskMBs, Cpu | Export-Csv -Path (Join-Path $RawDir 'Lasttest-Verlauf.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8 } catch { }
        $script:LoadSummary = ('Dauer {0:hh\:mm\:ss}{1}, {2}, {3} WHEA-Ereignisse{4}' -f $real, $stopTxt, (($script:LoadParts | ForEach-Object { '{0} {1}' -f $_.Komponente, $_.Ergebnis }) -join ', '), $whea.Count,
            $(if ($null -ne $cpuTMax) { ', CPU max {0:N0} °C' -f $cpuTMax } else { '' }) + $(if ($script:LoadThrottle) { ', Drosselung: ' + $script:LoadThrottle.Status } else { '' }))
        $script:SensorDb['Last'] = [ordered]@{
            CpuTempLeerlauf = $idle.CpuTemp; CpuTempMax = $cpuTMax; TjMax = $tjMax; CpuWMax = $cpuWMax; GpuTempMax = $gpuTMax; GpuWMax = $gpuWMax; LuefterMax = $fanMax; DatentraegerTempMax = $diskTMax
            Drosselung = $(if ($script:LoadThrottle) { $script:LoadThrottle.Status } else { '' }); TaktAbfall = $(if ($script:LoadThrottle) { $script:LoadThrottle.Abfall } else { $null })
            Abbruch = $(if ($abort) { $abort.Grund } else { '' }); Quelle = (Get-SensorSourceText)
        }
        foreach ($p in $script:LoadParts) { Add-TestResult ('Lasttest {0} ({1})' -f $p.Komponente, $p.Dauer) $p.Ergebnis $p.Details }
    }
}
# =====================================================================================
#                                     REPARATUR
# =====================================================================================
function Add-RepairResult([string]$Key, [string]$Status, [string]$Detail, [switch]$Restart) {
    $t = $(if ($script:RepTitles.Contains($Key)) { $script:RepTitles[$Key] } else { $Key })
    $script:RepairLog.Add([pscustomobject]@{ Reparatur = $t; Ergebnis = $Status; Details = $Detail; Stufe = $(if ($script:RepRisk.ContainsKey($Key)) { Get-RiskLabel $script:RepRisk[$Key] } else { '' }) })
    Add-TestResult ('Reparatur: ' + $t) $Status $Detail
    if ($Restart) { $script:RestartNeeded.Add($t) }
    Add-Line ('  Ergebnis: {0}{1}' -f $Status, $(if ($Detail) { ', ' + $Detail } else { '' }))
}

function Get-OutLines($Result, [int]$Max = 12) {
    @(($Result.Output + "`n" + $Result.Error) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^\[?=*\s*[\d.,]+\s*%\s*=*\]?$|\d+\s*%\s*$' } | Select-Object -Last $Max)
}

# Dateien löschen, die älter als die angegebene Anzahl Tage sind; Rückgabe: freigegebene Bytes
function Remove-OldFiles([string]$Path, [int]$Days) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    $limit = (Get-Date).AddDays(-$Days); $freed = 0.0
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $limit })) {
        try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $len } catch { }
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
        try { if (-not @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction Stop).Count -and $d.LastWriteTime -lt $limit) { Remove-Item -LiteralPath $d.FullName -Force -ErrorAction Stop } } catch { }
    }
    return $freed
}

function Invoke-DismJob([string]$Mode, [int]$ExpectedSec) {
    $job = Start-Job -ScriptBlock { param($m) $p = @{ Online = $true; NoRestart = $true; ErrorAction = 'Stop' }; $p[$m] = $true; Repair-WindowsImage @p | Select-Object ImageHealthState, RestartNeeded } -ArgumentList $Mode
    [void](Wait-JobWithProgress $job ('DISM ' + $Mode) $ExpectedSec 7200)
    $r = $null; $err = ''
    try { $r = Receive-Job $job -ErrorAction Stop } catch { $err = $_.Exception.Message }
    if (-not $err -and $job.ChildJobs[0].Error.Count) { $err = [string]$job.ChildJobs[0].Error[0] }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ State = $(if ($r) { [string]@($r)[0].ImageHealthState } else { '' }); Restart = $(if ($r) { [bool]@($r)[0].RestartNeeded } else { $false }); Error = $err }
}

if ($ModRep) {
    # Änderungsprotokoll dieses Laufs (Datei entsteht erst mit der ersten Änderung)
    Start-ChangeLog
    $script:RestorePointNo = ''
    $maxRep = Get-MaxRisk @($script:RepSel | ForEach-Object { $script:RepRisk[$_] })
    if ($OhneWiederherstellungspunkt -and (Get-RiskRank $maxRep) -ge (Get-RiskRank 'Eingriff')) {
        Add-Finding INFO 'Reparatur' 'Die Reparaturen enthalten Eingriffe ohne automatisches Rückgängig, ein Wiederherstellungspunkt wurde aber bewusst nicht angelegt.'
    }
    if (-not $OhneWiederherstellungspunkt) {
        Invoke-Section 'Reparatur: Wiederherstellungspunkt anlegen' {
            $rk = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
            $old = $null; try { $old = (Get-ItemProperty $rk -Name SystemRestorePointCreationFrequency -ErrorAction Stop).SystemRestorePointCreationFrequency } catch { }
            try {
                Show-Sub 'Wiederherstellungspunkt' 'wird angelegt' -1
                try { Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop } catch { }
                if (-not (Test-Path $rk)) { New-Item -Path $rk -Force | Out-Null }
                Set-ItemProperty -Path $rk -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Checkpoint-Computer -Description ('Leos Minibench vor Reparatur {0:dd.MM.yyyy HH:mm}' -f (Get-Date)) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                $rp = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber -Descending | Select-Object -First 1
                $txt = $(if ($rp) { 'angelegt: {0} (Nr. {1})' -f $rp.Description, $rp.SequenceNumber } else { 'angelegt' })
                if ($rp) { $script:RestorePointNo = [string]$rp.SequenceNumber }
                Add-Line ('  Wiederherstellungspunkt {0}' -f $txt)
                # Weg zurück für alle Eingriffe dieses Laufs; erscheint auf der Seite Änderungen als Hinweis
                [void](Add-ChangeRecord -Modul 'Reparatur' -Schritt 'Wiederherstellungspunkt' -Titel 'Wiederherstellungspunkt vor den Reparaturen' -Risiko 'Lesen' -Art 'Wiederherstellungspunkt' `
                    -Ziel 'Computerschutz' -Nachher $txt -Daten ([ordered]@{ Nummer = $script:RestorePointNo }) -Gegenbefehl ('rstrui.exe starten und Punkt Nr. {0} wählen; macht die Eingriffe dieses Laufs rückgängig' -f $script:RestorePointNo) -NurHinweis)
                $script:RepairLog.Add([pscustomobject]@{ Reparatur = 'Wiederherstellungspunkt'; Ergebnis = 'OK'; Details = $txt })
                Add-TestResult 'Reparatur: Wiederherstellungspunkt' 'OK' $txt
            } catch {
                Add-Line ('  Wiederherstellungspunkt konnte nicht angelegt werden: {0}' -f $_.Exception.Message)
                $script:RepairLog.Add([pscustomobject]@{ Reparatur = 'Wiederherstellungspunkt'; Ergebnis = 'Warnung'; Details = $_.Exception.Message })
                Add-TestResult 'Reparatur: Wiederherstellungspunkt' 'Warnung' $_.Exception.Message
                Add-Finding WARNUNG 'Reparatur' ('Vor den Reparaturen konnte kein Wiederherstellungspunkt angelegt werden ({0}). Computerschutz für Laufwerk {1} prüfen.' -f $_.Exception.Message, $env:SystemDrive)
            } finally {
                if ($null -ne $old) { Set-ItemProperty -Path $rk -Name SystemRestorePointCreationFrequency -Value $old -Type DWord -ErrorAction SilentlyContinue }
                else { Remove-ItemProperty -Path $rk -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
                Hide-Sub
            }
        }
    }

    foreach ($repKey in @($script:RepOrder | Where-Object { $script:RepSel -contains $_ })) {
        if (-not (Test-StepEnabled ('Rep:' + $repKey))) { continue }
        $script:CurRep = $repKey
        Invoke-Section ('Reparatur: ' + $script:RepTitles[$repKey]) {
            $k = $script:CurRep
            $st = Get-ModuleStep 'Reparatur' $k
            Add-Line ('  Risikostufe: {0}{1}' -f (Get-RiskLabel $st.Risiko), $(switch ($st.Rueckgaengig) { 'Protokoll' { ', rückgängig über die Seite Änderungen' } 'Wiederherstellungspunkt' { ', zurück nur über den Wiederherstellungspunkt' } 'Hinweis' { ', Weg zurück steht im Änderungsprotokoll' } default { ', nicht umkehrbar' } }))
            switch ($k) {
                'DismRestore' {
                    Write-Step 'DISM ScanHealth läuft (5 bis 20 Minuten) ...'
                    $scan = Invoke-DismJob 'ScanHealth' 600
                    if ($scan.Error) { Add-Line ('  ScanHealth fehlgeschlagen: {0}' -f $scan.Error); Add-RepairResult $k 'Fehler' ('ScanHealth fehlgeschlagen: ' + $scan.Error); break }
                    Add-Line ('  Zustand vor der Reparatur: {0}' -f $scan.State)
                    if ($scan.State -eq 'Healthy') { Add-RepairResult $k 'OK' 'Komponentenspeicher intakt, keine Reparatur nötig'; break }
                    if ($scan.State -eq 'NonRepairable') {
                        Add-RepairResult $k 'Fehler' 'Komponentenspeicher nicht reparierbar'
                        Add-Finding KRITISCH 'Systemdateien' 'Der Komponentenspeicher ist nicht reparierbar. Abhilfe: Inplace-Upgrade mit dem Windows-Installationsmedium (setup.exe, Dateien und Apps behalten).'
                        break
                    }
                    Write-Step 'DISM RestoreHealth läuft (10 bis 30 Minuten, lädt Dateien über Windows Update) ...'
                    $rh = Invoke-DismJob 'RestoreHealth' 1200
                    if ($rh.Error) {
                        Add-Line ('  RestoreHealth fehlgeschlagen: {0}' -f $rh.Error)
                        $hint = $(if ($rh.Error -match '0x800f081f|0x800f0906|0x800f0907|Quelldateien|source files') { ' Die Reparaturquelle fehlt: Windows-ISO einbinden und DISM /Online /Cleanup-Image /RestoreHealth /Source:WIM:X:\sources\install.wim:1 /LimitAccess ausführen.' } else { '' })
                        Add-RepairResult $k 'Fehler' ('RestoreHealth fehlgeschlagen: ' + $rh.Error)
                        Add-Finding KRITISCH 'Systemdateien' ('DISM RestoreHealth konnte den Komponentenspeicher nicht reparieren ({0}).{1}' -f $rh.Error, $hint)
                        break
                    }
                    Add-Line ('  Zustand nach der Reparatur: {0}' -f $rh.State)
                    if ($rh.State -eq 'Healthy') { Add-RepairResult $k 'Repariert' 'Komponentenspeicher repariert' -Restart:$rh.Restart; Add-Finding INFO 'Systemdateien' 'Der Komponentenspeicher war beschädigt und wurde mit DISM repariert.' }
                    else { Add-RepairResult $k 'Fehler' ('Zustand nach RestoreHealth: ' + $rh.State); Add-Finding KRITISCH 'Systemdateien' ('Komponentenspeicher nach der Reparatur weiterhin {0}. Abhilfe: Inplace-Upgrade mit dem Windows-Installationsmedium.' -f $rh.State) }
                }
                'Sfc' {
                    Write-Step 'sfc /scannow läuft (5 bis 20 Minuten) ...'
                    $t0 = Get-Date
                    $sfc = Invoke-External -File "$env:windir\System32\sfc.exe" -Arguments '/scannow' -TimeoutSec 5400 -Encoding ([Text.Encoding]::Unicode) -Progress 'Systemdateien reparieren (sfc /scannow)' -ExpectedSec 900
                    (Get-OutLines $sfc) | ForEach-Object { Add-Line ('  ' + $_) }
                    $cbs = Get-CbsEntries $t0
                    if ($cbs.Cannot.Count) { Add-Line ('  CBS.log: {0} nicht reparierbare Dateien, z. B. {1}' -f $cbs.Cannot.Count, (($cbs.Files | Select-Object -First 5) -join ', ')) }
                    $o = $sfc.Output
                    if ($o -match 'keine Integritätsverletzungen|did not find any integrity violations') { Add-RepairResult $k 'OK' 'keine Integritätsverletzungen' }
                    elseif ($cbs.Cannot.Count -or $o -match 'konnte einige|nicht reparieren|unable to fix') {
                        Add-RepairResult $k 'Fehler' ('{0} Dateien nicht reparierbar' -f [math]::Max(1, $cbs.Cannot.Count))
                        Add-Finding KRITISCH 'Systemdateien' 'SFC konnte nicht alle beschädigten Dateien reparieren. Zuerst DISM RestoreHealth ausführen, danach sfc /scannow wiederholen. Hilft das nicht: Inplace-Upgrade mit dem Windows-Installationsmedium.'
                    }
                    elseif ($o -match 'erfolgreich repariert|successfully repaired') { Add-RepairResult $k 'Repariert' 'beschädigte Dateien repariert' -Restart; Add-Finding INFO 'Systemdateien' 'SFC hat beschädigte Systemdateien gefunden und repariert. Ein Neustart schließt die Reparatur ab.' }
                    elseif ($sfc.TimedOut) { Add-RepairResult $k 'Warnung' 'Zeitlimit überschritten' }
                    else { Add-RepairResult $k 'Info' ('Rückgabecode {0}, Ausgabe siehe Bericht' -f $sfc.ExitCode) }
                }
                'Komponentenbereinigung' {
                    $sysVol = Get-Volume -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction SilentlyContinue
                    $before = [double]$sysVol.SizeRemaining
                    Write-Step 'DISM StartComponentCleanup läuft (5 bis 30 Minuten) ...'
                    $r = Invoke-External -File "$env:windir\System32\dism.exe" -Arguments '/Online /Cleanup-Image /StartComponentCleanup /NoRestart' -TimeoutSec 5400 -Progress 'Komponentenspeicher bereinigen' -ExpectedSec 900
                    (Get-OutLines $r 4) | ForEach-Object { Add-Line ('  ' + $_) }
                    $after = [double](Get-Volume -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction SilentlyContinue).SizeRemaining
                    $gain = $after - $before
                    if ($r.ExitCode -eq 0) { Add-RepairResult $k 'OK' ('abgeschlossen, Speicherplatz auf {0} {1}' -f $env:SystemDrive, $(if ($gain -gt 50MB) { 'um ' + (Format-Size $gain) + ' vergrößert' } else { 'kaum verändert' })) }
                    else { Add-RepairResult $k 'Warnung' ('DISM-Rückgabecode {0}' -f $r.ExitCode) }
                }
                'Dateisystem' {
                    $res = New-Object System.Collections.ArrayList; $restart = $false; $fixed = $false; $bad = $false
                    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -in 'NTFS', 'ReFS' } | Sort-Object DriveLetter)) {
                        $dl = [string]$v.DriveLetter
                        Show-Sub ('Dateisystem Laufwerk {0}:' -f $dl) 'Onlinescan' -1
                        try { $scan = "$(Repair-Volume -DriveLetter $dl -Scan -ErrorAction Stop)" } catch { [void]$res.Add(('{0}: Scan fehlgeschlagen ({1})' -f $dl, $_.Exception.Message)); $bad = $true; continue }
                        if ($scan -eq 'NoErrorsFound') { [void]$res.Add(('{0}: ok' -f $dl)); continue }
                        if (('{0}:' -f $dl) -eq $env:SystemDrive) {
                            $r = Invoke-External -File 'fsutil.exe' -Arguments ('dirty set {0}:' -f $dl)
                            [void]$res.Add(('{0}: {1}, Reparatur (chkdsk) beim nächsten Neustart eingeplant' -f $dl, $scan)); $restart = $true
                        } else {
                            Show-Sub ('Dateisystem Laufwerk {0}:' -f $dl) 'SpotFix' -1
                            try { $fx = "$(Repair-Volume -DriveLetter $dl -SpotFix -ErrorAction Stop)"; [void]$res.Add(('{0}: {1}, SpotFix: {2}' -f $dl, $scan, $fx)); $fixed = $true }
                            catch { [void]$res.Add(('{0}: {1}, SpotFix fehlgeschlagen ({2})' -f $dl, $scan, $_.Exception.Message)); $bad = $true }
                        }
                    }
                    Hide-Sub
                    $res | ForEach-Object { Add-Line ('  ' + $_) }
                    $st = $(if ($bad) { 'Warnung' } elseif ($restart) { 'Neustart' } elseif ($fixed) { 'Repariert' } else { 'OK' })
                    Add-RepairResult $k $st ($res -join '; ') -Restart:$restart
                }
                'WindowsUpdate' {
                    $svcs = 'wuauserv', 'bits', 'cryptsvc', 'msiserver'
                    $was = @{}
                    foreach ($s in $svcs) { $sv = Get-Service $s -ErrorAction SilentlyContinue; if ($sv) { $was[$s] = [string]$sv.Status; Stop-Service $s -Force -ErrorAction SilentlyContinue } }
                    $sw = [Diagnostics.Stopwatch]::StartNew()
                    while ($sw.Elapsed.TotalSeconds -lt 40 -and @($svcs | Where-Object { (Get-Service $_ -ErrorAction SilentlyContinue).Status -eq 'Running' }).Count) { Show-Sub 'Windows Update zurücksetzen' 'Dienste werden beendet' -1; Start-Sleep -Milliseconds 500 }
                    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'; $msgs = @(); $err = $false
                    foreach ($d in @("$env:windir\SoftwareDistribution", "$env:windir\System32\catroot2")) {
                        if (-not (Test-Path $d)) { continue }
                        $new = '{0}.bak_{1}' -f (Split-Path $d -Leaf), $ts
                        try { Rename-Item -LiteralPath $d -NewName $new -ErrorAction Stop; $msgs += ('{0} umbenannt in {1}' -f (Split-Path $d -Leaf), $new) }
                        catch { $msgs += ('{0} nicht umbenennbar: {1}' -f (Split-Path $d -Leaf), $_.Exception.Message); $err = $true }
                    }
                    foreach ($s in 'cryptsvc', 'bits', 'wuauserv') { Start-Service $s -ErrorAction SilentlyContinue }
                    foreach ($s in $was.Keys) { if ($was[$s] -eq 'Running') { Start-Service $s -ErrorAction SilentlyContinue } }
                    Hide-Sub
                    $old = @(Get-ChildItem $env:windir -Directory -Filter 'SoftwareDistribution.bak_*' -ErrorAction SilentlyContinue) + @(Get-ChildItem "$env:windir\System32" -Directory -Filter 'catroot2.bak_*' -ErrorAction SilentlyContinue)
                    $msgs | ForEach-Object { Add-Line ('  ' + $_) }
                    if ($old.Count -gt 2) { Add-Line ('  Hinweis: {0} Sicherungsordner früherer Zurücksetzungen liegen in {1} und können gelöscht werden, wenn Updates wieder funktionieren.' -f $old.Count, $env:windir) }
                    $ren = @($msgs | Where-Object { $_ -match ' umbenannt in ' })
                    if ($ren.Count) {
                        [void](Add-ChangeRecord -Modul 'Reparatur' -Schritt $k -Titel $script:RepTitles[$k] -Risiko 'Eingriff' -Art 'Ordner' -Ziel ('{0}\SoftwareDistribution, catroot2' -f $env:windir) `
                            -Vorher 'Originalordner' -Nachher ($ren -join '; ') -Gegenbefehl 'Dienste wuauserv, bits, cryptsvc beenden, die neuen Ordner löschen und die Ordner .bak_<Datum> zurückbenennen' -NurHinweis)
                    }
                    Add-RepairResult $k $(if ($err) { 'Warnung' } else { 'Repariert' }) (($msgs -join '; ') + '; Dienste neu gestartet') -Restart
                }
                'Netzwerk' {
                    $out = @(); $bad = 0
                    foreach ($c in @(@('ipconfig.exe', '/flushdns'), @('netsh.exe', 'winsock reset'), @('netsh.exe', 'int ip reset'), @('netsh.exe', 'int ipv6 reset'))) {
                        Show-Sub 'Netzwerk zurücksetzen' ('{0} {1}' -f $c[0], $c[1]) -1
                        $r = Invoke-External -File $c[0] -Arguments $c[1] -TimeoutSec 120
                        $out += ('{0} {1}: Rückgabecode {2}' -f $c[0], $c[1], $r.ExitCode)
                        if ($r.ExitCode -ne 0) { $bad++ }
                    }
                    Hide-Sub
                    $out | ForEach-Object { Add-Line ('  ' + $_) }
                    Add-RepairResult $k $(if ($bad) { 'Warnung' } else { 'Neustart' }) ('DNS-Cache geleert, Winsock und TCP/IP zurückgesetzt' + $(if ($bad) { (', {0} Befehle mit Fehler' -f $bad) } else { '' })) -Restart
                }
                'Temp' {
                    $total = 0.0; $lines = @()
                    $targets = @($env:TEMP, "$env:windir\Temp", "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue")
                    $targets += @(Get-ChildItem "$env:SystemDrive\Users" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'AppData\Local\Temp' } | Where-Object { Test-Path -LiteralPath $_ })
                    foreach ($t in @($targets | Where-Object { $_ } | Select-Object -Unique)) {
                        Show-Sub 'Temporäre Dateien löschen' $t -1
                        $f = Remove-OldFiles $t 2
                        $total += $f
                        if ($f -gt 1MB) { $lines += ('{0}: {1}' -f $t, (Format-Size $f)) }
                    }
                    try {
                        if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
                            $doB = $null; try { $doB = (Get-DeliveryOptimizationStatus -ErrorAction Stop | Measure-Object FileSize -Sum).Sum } catch { }
                            Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
                            $lines += ('Übermittlungsoptimierung: Cache geleert{0}' -f $(if ($doB) { ' (' + (Format-Size $doB) + ')' } else { '' }))
                        }
                    } catch { }
                    Hide-Sub
                    $lines | ForEach-Object { Add-Line ('  ' + $_) }
                    Add-RepairResult $k 'OK' ('{0} freigegeben (Dateien älter als 2 Tage, gesperrte Dateien bleiben erhalten)' -f (Format-Size $total))
                }
                'WMI' {
                    $v = Invoke-External -File "$env:windir\System32\wbem\winmgmt.exe" -Arguments '/verifyrepository' -TimeoutSec 600 -Progress 'WMI-Repository prüfen'
                    $txt = ($v.Output + ' ' + $v.Error).Trim()
                    Add-Line ('  Prüfung: {0}' -f $txt)
                    if ($txt -match 'inkonsistent|nicht konsistent|inconsistent|not consistent') {
                        $s = Invoke-External -File "$env:windir\System32\wbem\winmgmt.exe" -Arguments '/salvagerepository' -TimeoutSec 900 -Progress 'WMI-Repository reparieren'
                        $v2 = Invoke-External -File "$env:windir\System32\wbem\winmgmt.exe" -Arguments '/verifyrepository' -TimeoutSec 600
                        Add-Line ('  Reparatur: {0}' -f ($s.Output + ' ' + $s.Error).Trim()); Add-Line ('  Erneute Prüfung: {0}' -f ($v2.Output).Trim())
                        if (($v2.Output) -match 'inkonsistent|nicht konsistent|inconsistent|not consistent') { Add-RepairResult $k 'Fehler' 'Repository weiterhin inkonsistent'; Add-Finding WARNUNG 'System' 'Das WMI-Repository ist beschädigt und ließ sich nicht reparieren (winmgmt /resetrepository als letzter Schritt).' }
                        else { Add-RepairResult $k 'Repariert' 'Repository war inkonsistent und wurde repariert' }
                    } elseif ($v.ExitCode -eq 0) { Add-RepairResult $k 'OK' 'Repository konsistent' }
                    else { Add-RepairResult $k 'Info' ('Rückgabecode {0}' -f $v.ExitCode) }
                }
                'Zeit' {
                    $svc = Get-Service w32time -ErrorAction SilentlyContinue
                    if ($svc -and $svc.StartType -eq 'Disabled') {
                        try { $c = Set-ServiceStartTypeLogged -Name 'w32time' -StartType 'Manual' -Modul 'Reparatur' -Schritt $k -Titel $script:RepTitles[$k]; if ($c) { Add-Line '  Dienst w32time war deaktiviert und steht jetzt auf Manuell (im Änderungsprotokoll).' } }
                        catch { Add-Line ('  Starttyp von w32time nicht änderbar: {0}' -f $_.Exception.Message) }
                    }
                    Start-Service w32time -ErrorAction SilentlyContinue
                    $r = Invoke-External -File 'w32tm.exe' -Arguments '/resync /force' -TimeoutSec 120 -Progress 'Zeit synchronisieren'
                    if ($r.ExitCode -ne 0) {
                        [void](Invoke-External -File 'w32tm.exe' -Arguments '/config /update' -TimeoutSec 60)
                        Restart-Service w32time -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2
                        $r = Invoke-External -File 'w32tm.exe' -Arguments '/resync /force' -TimeoutSec 120
                    }
                    (Get-OutLines $r 3) | ForEach-Object { Add-Line ('  ' + $_) }
                    Add-RepairResult $k $(if ($r.ExitCode -eq 0) { 'OK' } else { 'Warnung' }) $(if ($r.ExitCode -eq 0) { 'Zeit synchronisiert' } else { 'Synchronisierung fehlgeschlagen, Rückgabecode ' + $r.ExitCode })
                }
                'Druck' {
                    Stop-Service Spooler -Force -ErrorAction SilentlyContinue
                    $spool = "$env:windir\System32\spool\PRINTERS"
                    $files = @(Get-ChildItem $spool -File -Force -ErrorAction SilentlyContinue)
                    $n = 0; foreach ($f in $files) { try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $n++ } catch { } }
                    Start-Service Spooler -ErrorAction SilentlyContinue
                    $ok = (Get-Service Spooler -ErrorAction SilentlyContinue).Status -eq 'Running'
                    Add-RepairResult $k $(if (-not $ok) { 'Warnung' } elseif ($n) { 'Repariert' } else { 'OK' }) ('{0} hängende Druckaufträge entfernt, Druckspooler {1}' -f $n, $(if ($ok) { 'läuft' } else { 'startet nicht' }))
                }
                'Geraete' {
                    $bad0 = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -notin 22, 45 }).Count
                    $r = Invoke-External -File 'pnputil.exe' -Arguments '/scan-devices' -TimeoutSec 300 -Progress 'Geräte neu erkennen'
                    Start-Sleep -Seconds 3
                    $bad1 = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -notin 22, 45 }).Count
                    Add-RepairResult $k $(if ($r.ExitCode -ne 0) { 'Info' } elseif ($bad1 -lt $bad0) { 'Repariert' } else { 'OK' }) ('Geräte mit Fehlercode vorher {0}, nachher {1}' -f $bad0, $bad1)
                }
                'Schnellstart' {
                    $pk = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
                    $old = (Get-ItemProperty $pk -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
                    if ($old -eq 0) { Add-RepairResult $k 'OK' 'Schnellstart war bereits deaktiviert' }
                    else {
                        try { [void](Set-RegistryValueLogged -Path $pk -Name 'HiberbootEnabled' -Value 0 -Type 'DWord' -Modul 'Reparatur' -Schritt $k -Titel $script:RepTitles[$k]); Add-RepairResult $k 'Repariert' 'Schnellstart deaktiviert, Windows fährt ab jetzt vollständig herunter (rückgängig über die Seite Änderungen)' }
                        catch { Add-RepairResult $k 'Fehler' $_.Exception.Message }
                    }
                }
                'Energieplaene' {
                    # Erst alle Pläne sichern; ohne Sicherung wird nichts zurückgesetzt
                    try { $bk = Backup-PowerSchemesLogged -Modul 'Reparatur' -Schritt $k -Titel $script:RepTitles[$k]; Add-Line ('  Gesichert: {0}' -f $bk.Vorher) }
                    catch { Add-RepairResult $k 'Fehler' ('Sicherung der Energiepläne fehlgeschlagen, nichts zurückgesetzt: ' + $_.Exception.Message); break }
                    $r = Invoke-External -File 'powercfg.exe' -Arguments '-restoredefaultschemes' -TimeoutSec 60
                    $a = Invoke-External -File 'powercfg.exe' -Arguments '/getactivescheme'
                    Add-RepairResult $k $(if ($r.ExitCode -eq 0) { 'OK' } else { 'Warnung' }) ('Standardpläne wiederhergestellt, aktiv: {0}' -f ((($a.Output -split '\(')[-1]) -replace '\)', '').Trim())
                }
            }
        }
    }
    if ($script:RestartNeeded.Count) { Add-Finding INFO 'Reparatur' ('Neustart erforderlich, damit diese Reparaturen wirksam werden: {0}.' -f (($script:RestartNeeded | Select-Object -Unique) -join ', ')) }
    if ($script:ChangeCount) {
        Add-Sub 'Änderungsprotokoll'
        Add-Line ('  {0} Einträge in {1}' -f $script:ChangeCount, $script:ChangeFile)
        foreach ($c in @($script:ChangeLog.Eintraege)) { Add-Line ('  {0,2}. {1}: {2} | vorher {3} | nachher {4} | {5}' -f $c.Id, $c.Titel, $c.Ziel, $c.Vorher, $c.Nachher, $(if ($c.Status -eq 'aktiv') { 'rückgängig über die Seite Änderungen' } else { $c.Gegenbefehl })) }
    }
}


# =====================================================================================
#                                    ABSCHLUSS
# =====================================================================================

if ($ScheduleWindowsMemTest -and $ModDiag -and -not $AnalyzeLastRun) {
    Add-Section 'Windows-Speicherdiagnose'
    Add-Line '  mdsched.exe wird gestartet. Nach dem Neustart testet Windows den RAM vor dem Systemstart.'
    Add-Line '  Das Ergebnis erscheint nach der Anmeldung als Hinweis und im System-Protokoll (Quelle MemoryDiagnostics-Results).'
}

if ($TypesLoaded) { [void][DiagPower]::SetThreadExecutionState([uint32]2147483648) }

# Sensoren schließen: entfernt einen vorübergehend installierten PawnIO-Treiber, bevor die Rückstandskontrolle prüft
Close-SensorSession
foreach ($t in @($script:SensorNotes | Select-Object -Unique)) { Add-Finding INFO 'Sensoren' $t }

# Werkzeug-Manifest: abgewiesene oder neu aufgenommene Dateien
foreach ($t in @($script:ToolIssues | Select-Object -Unique)) { Add-Finding WARNUNG 'Werkzeuge' $t }
foreach ($t in @($script:ToolNotes | Select-Object -Unique)) { Add-Finding INFO 'Werkzeuge' $t }

# ---------- Rückstandskontrolle: auf dem geprüften PC sollen keine Dateien des Werkzeugs bleiben ----------
function Invoke-ResidueCheck {
    $removed = New-Object System.Collections.ArrayList
    $left = New-Object System.Collections.ArrayList
    $del = {
        param([string]$Path, [string]$What)
        if (-not (Test-Path -LiteralPath $Path)) { return }
        try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop; [void]$removed.Add(('{0}: {1}' -f $What, $Path)) }
        catch { [void]$left.Add(('{0}: {1} ({2})' -f $What, $Path, $_.Exception.Message)) }
    }
    # Testdateien von Benchmark und Lasttest auf allen Laufwerken (z. B. nach einem Absturz)
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })) {
        foreach ($n in 'LeosMinibench-Benchmark.tmp', 'LeosMinibench-Lasttest.tmp', 'PC-Diagnose-Benchmark.tmp', 'PC-Diagnose-Lasttest.tmp') { & $del ('{0}:\{1}' -f $v.DriveLetter, $n) 'Testdatei' }
    }
    # temporäre Dateien dieses Werkzeugs und Ordner früherer Versionen (PC-Diagnose)
    $mine = @($PSCommandPath, $script:DataDir) | Where-Object { $_ }
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    $profiles = @(if (Test-Path -LiteralPath $usersRoot) { Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } })
    $tempRoots = @($env:TEMP, "$env:windir\Temp") + @($profiles | ForEach-Object { Join-Path $_ 'AppData\Local\Temp' })
    foreach ($t in @($tempRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
        foreach ($i in @(Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'LeosMinibench*' -or $_.Name -like 'PC-Diagnose*' })) {
            if (@($mine | Where-Object { $_ -like ($i.FullName + '*') }).Count) { continue }   # eigene, noch laufende Skriptdatei
            & $del $i.FullName 'Temporäre Datei'
        }
    }
    foreach ($d in "$env:ProgramData\PC-Diagnose", "$env:PUBLIC\PC-Diagnose") { & $del $d 'Ordner einer früheren Version' }
    # Berichtsordner früherer Versionen auf Desktops: in den Datenordner verschieben statt zu löschen
    if ($script:DataDir -and -not $script:DataDirFallback) {
        $desks = @("$env:PUBLIC\Desktop") + @($profiles | ForEach-Object { Join-Path $_ 'Desktop' }) + @([Environment]::GetFolderPath('Desktop'))
        foreach ($dk in @($desks | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
            foreach ($o in @(Get-ChildItem -LiteralPath $dk -Directory -Filter 'PC-Diagnose_*' -ErrorAction SilentlyContinue)) {
                $dest = Join-Path (Join-Path $script:DataDir 'Berichte\Altbestand') $o.Name
                try { New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null; Move-Item -LiteralPath $o.FullName -Destination $dest -Force -ErrorAction Stop; [void]$removed.Add(('Bericht einer früheren Version vom Desktop in den Datenordner verschoben: {0}' -f $o.Name)) }
                catch { [void]$left.Add(('Bericht einer früheren Version auf dem Desktop: {0} ({1})' -f $o.FullName, $_.Exception.Message)) }
            }
            foreach ($f in @(Get-ChildItem -LiteralPath $dk -File -Filter 'PC-Diagnose*.exe' -ErrorAction SilentlyContinue)) { [void]$left.Add(('Programmdatei einer früheren Version auf dem Desktop (nicht gelöscht): {0}' -f $f.FullName)) }
        }
    }
    # PawnIO: nur entfernen, was dieses Werkzeug installiert hat; ein vorher vorhandener Treiber bleibt
    $pwm = Get-PawnIoMarker
    if ($pwm -and (Test-Path -LiteralPath $pwm)) { $u = Uninstall-PawnIo; if ($u -and $u.Ok) { [void]$removed.Add(('Treiber: {0}' -f $u.Text)) } elseif ($u) { [void]$left.Add(('Treiber: {0}' -f $u.Text)) } }
    elseif ($script:Sens -and $script:Sens.Treiber -match 'wieder entfernt') { [void]$removed.Add('Treiber: PawnIO wieder entfernt') }
    elseif ($script:Sens -and $script:Sens.Treiber -match 'noch installiert') { [void]$left.Add(('Treiber: {0}' -f $script:Sens.Treiber)) }
    if ($script:SmartLeftInstalled) { [void]$left.Add('smartmontools ist noch installiert (Deinstallation fehlgeschlagen): winget uninstall smartmontools.smartmontools') }

    if ($removed.Count) { Add-Line '  Entfernt oder verschoben:'; $removed | ForEach-Object { Add-Line ('    ' + $_) } }
    if ($left.Count) { Add-Line '  Verblieben:'; $left | ForEach-Object { Add-Line ('    ' + $_) }; Add-Finding INFO 'System' ('Auf dem PC sind noch Dateien des Werkzeugs vorhanden: {0}' -f ($left -join '; ')) }
    if (-not $removed.Count -and -not $left.Count) { Add-Line '  Keine Dateien des Werkzeugs auf diesem PC gefunden.' }
    Add-Line ('  Alle Berichte und Daten liegen im Datenordner: {0}' -f $script:DataDir)
    Add-Line '  Nicht entfernbar und nicht entfernt werden Spuren, die Windows selbst anlegt: Ereignisprotokolle, Prefetch-Einträge,'
    Add-Line '  CBS- und DISM-Protokolle (bei Integritätsprüfung und Reparatur) sowie der WinSAT-Datenspeicher (bei WinSAT).'
    Add-TestResult 'Rückstandskontrolle' $(if ($left.Count) { 'Info' } else { 'OK' }) $(if ($left.Count) { '{0} Reste verblieben' -f $left.Count } elseif ($removed.Count) { '{0} Reste entfernt oder verschoben' -f $removed.Count } else { 'keine Reste gefunden' })
}
Invoke-Section 'Rückstandskontrolle' { Invoke-ResidueCheck }

$script:StepNo = [math]::Max((Get-PlannedSteps), $script:StepNo + 1)
Show-Overall 'Bericht, KI-Datei und Datenbankeintrag werden erstellt'
Hide-Sub
$EndTime = Get-Date
$order = @{ KRITISCH = 0; WARNUNG = 1; INFO = 2 }
$sorted = @($script:Findings | Sort-Object Stufe, Bereich, Befund -Unique | Sort-Object @{ e = { $order[$_.Stufe] } }, Bereich)
$nK = @($sorted | Where-Object Stufe -eq 'KRITISCH').Count
$nW = @($sorted | Where-Object Stufe -eq 'WARNUNG').Count
$nI = @($sorted | Where-Object Stufe -eq 'INFO').Count

if ($ModDiag -and -not $AnalyzeLastRun) {
    $skipList = @(@('Dateisystem und Systemdateien', 'Integritaet'), @('Defender Schnellscan', 'Defender'), @('SMART-Langtest', 'SmartLang'), @('Netzwerk', 'Netzwerk'), @('RAM-Mustertest', 'RamTest'), @('CPU-Stabilität', 'CpuTest'), @('Energieanalyse', 'Energieanalyse'))
    foreach ($sk in $skipList) { if (-not $script:Opt[$sk[1]]) { Add-TestResult $sk[0] 'Übersprungen' 'nicht ausgewählt' } }
}

# Datenbankeintrag vor dem Bericht, damit der Pfad im Bericht steht
$script:DbSaved = Save-DbEntry -Sorted $sorted -NK $nK -NW $nW -NI $nI
if ($script:DbSaved) { Add-Sub 'Vergleichsdatenbank'; Add-Line ('  Eintrag gespeichert: {0}' -f $script:DbSaved) }

$head = New-Object System.Text.StringBuilder
[void]$head.AppendLine('#' * 100)
[void]$head.AppendLine(('  LEOS MINIBENCH: DIAGNOSEBERICHT   {0}   v{1}' -f $env:COMPUTERNAME, $ScriptVersion))
[void]$head.AppendLine('#' * 100)
[void]$head.AppendLine(('  Erstellt     : {0:dd.MM.yyyy HH:mm} bis {1:HH:mm} Uhr (Dauer {2:hh\:mm\:ss})' -f $StartTime, $EndTime, ($EndTime - $StartTime)))
[void]$head.AppendLine(('  Module       : {0}' -f (Get-ModeLabel)))
[void]$head.AppendLine(('  Risikostufe  : {0}' -f (Get-RiskLabel (Get-RunRisk))))
if ($ModDiag -and -not $AnalyzeLastRun) {
    [void]$head.AppendLine(('  Prüfungen    : {0}' -f ((@($script:DiagKeys | ForEach-Object { '{0} {1}' -f $_, $(if ($script:Opt[$_]) { 'ja' } else { 'nein' }) })) -join ', ')))
}
[void]$head.AppendLine(('  Ausgabe      : {0}' -f $OutputDir))
if ($script:DataDir) { [void]$head.AppendLine(('  Datenordner  : {0}' -f $script:DataDir)) }
[void]$head.AppendLine()
[void]$head.AppendLine(('  ERGEBNIS: {0} kritisch, {1} Warnungen, {2} Hinweise' -f $nK, $nW, $nI))
[void]$head.AppendLine('  ' + ('-' * 98))
if ($sorted.Count) {
    foreach ($f in $sorted) { [void]$head.AppendLine(('  [{0,-8}] {1,-14} {2}' -f $f.Stufe, $f.Bereich, $f.Befund)) }
} else { [void]$head.AppendLine('  Keine Auffälligkeiten gefunden.') }
[void]$head.AppendLine()
[void]$head.AppendLine('  Zeitbedarf der Abschnitte:')
foreach ($t in $script:Timings) { [void]$head.AppendLine(('    {0,-55} {1}' -f $t.Abschnitt, $t.Dauer)) }

$full = $head.ToString() + $script:Report.ToString()
$reportFile = Join-Path $OutputDir 'Diagnosebericht.txt'
[IO.File]::WriteAllText($reportFile, $full, (New-Object Text.UTF8Encoding($true)))
Write-Checkpoint 'ENDE' 'Lauf regulär abgeschlossen'
Close-Checkpoint -RemoveFlag
try { Copy-Item $script:CpLog (Join-Path $RawDir 'Checkpoint.log') -Force } catch { }
Remove-Item (Join-Path $OutputDir 'Diagnosebericht_teilweise.txt') -Force -ErrorAction SilentlyContinue

$kiName = $(if ($KiOhneAnonymisierung) { 'KI-Analyse_{0}_{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmm') } else { 'KI-Analyse_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmm') })
$kiFile = Join-Path $OutputDir $kiName
$htmlFile = Join-Path $OutputDir 'Diagnosebericht.html'
try { New-HtmlReport -Path $htmlFile -Sorted $sorted -NK $nK -NW $nW -NI $nI -Start $StartTime -End $EndTime }
catch { Write-Warning ('HTML-Bericht konnte nicht erstellt werden: {0}' -f $_.Exception.Message); $htmlFile = '' }

if ($script:GuiLog) { try { $script:GuiLog.Close(); $script:GuiLog = $null } catch { } }

# KI-Dateien: vollständige Fassung mit Rohdaten zum Hochladen, Kurzfassung ohne Rohdaten zum Einfügen in ein Chatfenster
$kurzFile = Join-Path $OutputDir 'KI-Kurzfassung.txt'
try {
    Add-PrivateFromRaw
    [void](New-KiExport -Path $kiFile -Sorted $sorted -NK $nK -NW $nW -NI $nI -Start $StartTime -End $EndTime)
    [void](New-KiExport -Path $kurzFile -Sorted $sorted -NK $nK -NW $nW -NI $nI -Start $StartTime -End $EndTime -Compact)
} catch { Write-Warning ('KI-Datei konnte nicht erstellt werden: {0}' -f $_.Exception.Message); $kiFile = ''; $kurzFile = '' }

# Alles außer den Berichten in Anhang.zip packen
$zipFile = Join-Path $OutputDir 'Anhang.zip'
try {
    if (@(Get-ChildItem $RawDir -Force -ErrorAction SilentlyContinue).Count) {
        Compress-Archive -Path (Join-Path $RawDir '*') -DestinationPath $zipFile -Force -ErrorAction Stop
        Remove-Item $RawDir -Recurse -Force -ErrorAction SilentlyContinue
    } else { Remove-Item $RawDir -Force -ErrorAction SilentlyContinue; $zipFile = '' }
} catch { $zipFile = '' }

Write-Host ''
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ('  FERTIG nach {0:hh\:mm\:ss}' -f ($EndTime - $StartTime)) -ForegroundColor Cyan
Write-Host ('  {0} kritisch, {1} Warnungen, {2} Hinweise' -f $nK, $nW, $nI) -ForegroundColor $(if ($nK) { 'Red' } elseif ($nW) { 'Yellow' } else { 'Green' })
Write-Host ('  Ordner      : {0}' -f $OutputDir)
if ($htmlFile) { Write-Host '  Bericht     : Diagnosebericht.html (und .txt)' } else { Write-Host '  Bericht     : Diagnosebericht.txt' }
if ($kiFile) { Write-Host ('  KI-Datei    : {0} ({1:N0} KB, zum Hochladen) und KI-Kurzfassung.txt (zum Einfügen)' -f (Split-Path $kiFile -Leaf), ((Get-Item $kiFile).Length / 1KB)) }
if ($zipFile) { Write-Host '  Anhang      : Anhang.zip (Protokolle und Rohdaten)' }
if ($script:DbSaved) { Write-Host ('  Datenbank   : {0}' -f $script:DbSaved) }
if ($script:RestartNeeded.Count) { Write-Host ('  NEUSTART erforderlich für: {0}' -f (($script:RestartNeeded | Select-Object -Unique) -join ', ')) -ForegroundColor Yellow }
Write-Host ('=' * 80) -ForegroundColor Cyan

if ($ScheduleWindowsMemTest -and $ModDiag -and -not $AnalyzeLastRun) { Start-Process "$env:windir\System32\mdsched.exe" }
Remove-Item -LiteralPath $script:CpDir -Recurse -Force -ErrorAction SilentlyContinue
$rtDir = Split-Path $script:CpDir -Parent
if ($rtDir -and (Split-Path $rtDir -Leaf) -eq 'Laufzeit' -and -not @(Get-ChildItem -LiteralPath $rtDir -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $rtDir -Force -ErrorAction SilentlyContinue }
Send-GuiEvent 'DONE' $reportFile $htmlFile $OutputDir $nK $nW $nI $kurzFile $kiFile
