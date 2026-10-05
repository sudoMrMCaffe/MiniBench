# Modulvertrag Diagnose (Vertrag 1). Felder sind in src\Kern\Modulvertrag.ps1 beschrieben.
@{
    Vertrag         = 1
    Name            = 'Diagnose'
    Seite           = @{ Titel = 'Diagnose'; Kurz = 'Inventar, Prüfungen, Ereignisse' }
    Admin           = $true
    Risiko          = 'Eingriff'
    Neustart        = 'immer'
    Parameter       = @('DiagProfil', 'DiagOptionen', 'AnalyzeLastRun', 'InstallSmartmontools', 'ScheduleWindowsMemTest', 'EventDays', 'RamTestPercent', 'RamTestPasses', 'SmartTimeoutMinutes', 'SchnellerModus')
    Datenbankfelder = @('System', 'Hardware', 'Befunde', 'Akku')
    # Ab v2.6 (schneller Modus): Parallel = darf als Hintergrundaufgabe neben anderen Prüfungen laufen, Nach = Schritte, die
    # vorher fertig sein müssen, Exklusiv = Messung, vor der alle Hintergrundaufgaben abgeschlossen sein müssen
    Schritte        = @(
        @{ Key = 'Ereignisse';     Typ = 'Pruefung'; Titel = 'Ereignisprotokolle und Absturzanalyse';  Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'Updatesuche';    Typ = 'Pruefung'; Titel = 'Suche nach ausstehenden Updates';         Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Parallel = $true }
        @{ Key = 'Integritaet';    Typ = 'Pruefung'; Titel = 'Dateisystem und Systemdateien (nur prüfen)'; Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins' }
        @{ Key = 'Defender';       Typ = 'Pruefung'; Titel = 'Defender Schnellscan';                    Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Parallel = $true }
        @{ Key = 'SmartLang';      Typ = 'Pruefung'; Titel = 'SMART-Langtest';                          Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Parallel = $true }
        @{ Key = 'Netzwerk';       Typ = 'Pruefung'; Titel = 'Netzwerktest';                            Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        @{ Key = 'RamTest';        Typ = 'Pruefung'; Titel = 'RAM-Mustertest';                          Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        # CPU-Stabilität (CpuTest) ab v2.7 entfernt: das Modul Lasttest prüft die CPU gründlicher (eigener Prozess, Drosselnachweis)
        # die Energieanalyse soll den Virenscan nicht mitmessen
        @{ Key = 'Energieanalyse'; Typ = 'Pruefung'; Titel = 'Energieanalyse und DxDiag';               Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Parallel = $true; Nach = @('Defender') }
        # Zusatzoptionen der Seite Diagnose
        @{ Key = 'Speicherdiagnose';   Typ = 'Option'; Titel = 'Windows-Speicherdiagnose beim nächsten Neustart'; Risiko = 'Lesen';    Neustart = 'immer'; Rueckgaengig = 'keins'; Schalter = 'ScheduleWindowsMemTest' }
        @{ Key = 'SmartmontoolsHolen'; Typ = 'Option'; Titel = 'smartmontools per winget holen (danach entfernen oder auf Wunsch behalten)'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Schalter = 'InstallSmartmontools' }
    )
}
