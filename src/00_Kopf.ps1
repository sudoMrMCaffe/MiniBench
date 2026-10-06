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
    Reparatur (SFC, DISM und weitere), Optimierung (ab v2.8: Windows Optimisation Pack nativ, in Kategorien wählbar),
    Sensoren live (Temperatur, Takt, Lüfter, Spannung, Leistung).
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
    [ValidateRange(5, 1440)] [int]$SmartTimeoutMinutes = 120,
    # Schneller Modus: unabhängige Prüfungen parallel (Messungen bleiben exklusiv)
    [switch]$SchnellerModus,
    # Benchmark
    [string]$BenchTests = 'CPU,RAM,GPU,Disk',
    [string]$BenchLaufwerke = '',
    [switch]$BenchmarkKurz,
    [switch]$ReferenzSpeichern,
    [string]$ReferenzDatei,
    [string]$VergleichDateien = '',
    [switch]$KeineDatenbank,
    # Hybridgrafik: zweite WinSAT-Messung mit vorübergehend bevorzugter Grafikkarte
    [switch]$BenchGpuWahl,
    # GPU-Rendertest (Benchmark und Lasttest): Auflösung und Anzeige (Fenster, Vollbild, Aus)
    [ValidateSet('1280x720', '1920x1080')] [string]$GpuAufloesung = '1280x720',
    [ValidateSet('Fenster', 'Vollbild', 'Aus')] [string]$GpuAnzeige = 'Fenster',
    # ab v2.65: welche Grafikeinheiten Benchmark und Lasttest belasten (Alle, Grafikkarte, Prozessorgrafik oder ein Name)
    [string]$GpuAuswahl = 'Alle',
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
    # Wartung (früher Reparatur)
    [string]$Wartung = '',
    [string]$Reparaturen = '',
    [switch]$OhneWiederherstellungspunkt,
    # Optimierung (ab v2.8): Katalog-Ids, Wiederherstellungspunkt, Zustand prüfen und Werkzeuge holen (Hilfsmodi der Oberfläche)
    [string]$Optimierungen = '',
    [switch]$OptOhneWiederherstellungspunkt,
    [switch]$OptimierungZustand,
    [switch]$OptWerkzeugeHolen,
    # Allgemein
    [switch]$KiOhneAnonymisierung,
    # Hilfswerkzeuge (PawnIO, smartmontools per winget) nach dem Lauf: entfernen oder auf diesem PC behalten; leer = gespeicherte Wahl
    [ValidateSet('', 'entfernen', 'behalten')] [string]$WerkzeugeBehalten = '',
    [string]$DatenDir,
    [string]$OutputDir,
    [string]$ImportOrdner,
    [string]$Vergleich,
    [string]$Rueckgaengig,
    [switch]$Dashboard,
    [string]$DashboardExport,
    # Auswertung von Minibench-Daten\Laufzeit\Start.log ausgeben (Startzeit je Phase, Stick und Festplatte getrennt)
    [switch]$StartAuswertung,
    # Datenpflege (ab v2.7): Lasttests vor v2.67 (nicht vergleichbar), unvollständige und kurze Läufe ins Archiv
    # verschieben; ohne -ArchivDir nach Minibench-Daten\Archiv. Läuft beim Start der Oberfläche von selbst mit.
    [switch]$Datenpflege,
    [string]$ArchivDir,
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

