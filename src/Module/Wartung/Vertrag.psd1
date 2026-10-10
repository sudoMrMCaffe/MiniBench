# Modulvertrag Wartung (Vertrag 1). Felder sind in src\Kern\Modulvertrag.ps1 beschrieben.
# Reihenfolge der Schritte = Ausführungsreihenfolge. Text, Minuten, Vorauswahl und Ueblich steuern die Seite Wartung.
@{
    Vertrag         = 1
    Name            = 'Wartung'
    Seite           = @{ Titel = 'Wartung'; Kurz = 'SFC, DISM, Bereinigung und Systempflege' }
    Admin           = $true
    Risiko          = 'Eingriff'
    Neustart        = 'immer'
    Parameter       = @('Wartung', 'Reparaturen', 'OhneWiederherstellungspunkt')
    Datenbankfelder = @()
    Schritte        = @(
        @{ Key = 'DismRestore'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Rueckgaengig = 'Wiederherstellungspunkt'; Minuten = 20; Vorauswahl = $true; Ueblich = $false; Gruppe = 'Systemdateien und Komponentenspeicher'
           Titel = 'Komponentenspeicher prüfen und reparieren (DISM)'
           Text  = 'Komponentenspeicher prüfen und reparieren (DISM ScanHealth, bei Bedarf RestoreHealth)' }
        @{ Key = 'Sfc'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Rueckgaengig = 'Wiederherstellungspunkt'; Minuten = 12; Vorauswahl = $true; Ueblich = $false; Gruppe = 'Systemdateien und Komponentenspeicher'
           Titel = 'Systemdateien reparieren (sfc /scannow)'
           Text  = 'Systemdateien reparieren (sfc /scannow, nach DISM)' }
        @{ Key = 'Komponentenbereinigung'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 15; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Systemdateien und Komponentenspeicher'
           Titel = 'Komponentenspeicher bereinigen (DISM)'
           Text  = 'Komponentenspeicher bereinigen (DISM StartComponentCleanup, gibt Platz frei)' }
        @{ Key = 'Dateisystem'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Rueckgaengig = 'keins'; Minuten = 5; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Systemdateien und Komponentenspeicher'
           Titel = 'Dateisystemfehler beheben'
           Text  = 'Dateisystemfehler beheben (Onlinescan, SpotFix, Systemlaufwerk beim Neustart)' }
        @{ Key = 'WindowsUpdate'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'immer'; Rueckgaengig = 'Hinweis'; Minuten = 2; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Windows Update, Netzwerk und Zeit'
           Titel = 'Windows Update zurücksetzen'
           Text  = 'Windows Update zurücksetzen (Dienste, SoftwareDistribution, catroot2)' }
        @{ Key = 'Netzwerk'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'immer'; Rueckgaengig = 'Wiederherstellungspunkt'; Minuten = 1; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Windows Update, Netzwerk und Zeit'
           Titel = 'Netzwerk zurücksetzen'
           Text  = 'Netzwerk zurücksetzen (DNS-Cache, Winsock, TCP/IP), Neustart nötig' }
        @{ Key = 'Temp'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 3; Vorauswahl = $false; Ueblich = $true; Gruppe = 'Bereinigung und Speicherplatz'
           Titel = 'Temporäre Dateien löschen'
           Text  = 'Temporäre Dateien löschen (älter als 2 Tage, Übermittlungsoptimierung, Fehlerberichte)' }
        @{ Key = 'WMI'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'Wiederherstellungspunkt'; Minuten = 2; Vorauswahl = $false; Ueblich = $true; Gruppe = 'Dienste, Geräte und Energie'
           Titel = 'WMI-Repository prüfen'
           Text  = 'WMI-Repository prüfen und bei Bedarf reparieren' }
        @{ Key = 'Zeit'; Typ = 'Massnahme'; Risiko = 'Aendern'; Neustart = 'nie'; Rueckgaengig = 'Protokoll'; Minuten = 1; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Windows Update, Netzwerk und Zeit'
           Titel = 'Zeit synchronisieren'
           Text  = 'Windows-Zeit neu synchronisieren' }
        @{ Key = 'Druck'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 1; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Dienste, Geräte und Energie'
           Titel = 'Druckwarteschlange leeren'
           Text  = 'Druckwarteschlange leeren und Druckspooler neu starten' }
        @{ Key = 'Geraete'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'Wiederherstellungspunkt'; Minuten = 1; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Dienste, Geräte und Energie'
           Titel = 'Geräte neu erkennen'
           Text  = 'Geräte neu erkennen lassen (pnputil /scan-devices)' }
        @{ Key = 'Schnellstart'; Typ = 'Massnahme'; Risiko = 'Aendern'; Neustart = 'nie'; Rueckgaengig = 'Protokoll'; Minuten = 1; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Dienste, Geräte und Energie'
           Titel = 'Schnellstart deaktivieren'
           Text  = 'Schnellstart deaktivieren (hilft bei Abstürzen nach dem Einschalten)' }
        @{ Key = 'Energieplaene'; Typ = 'Massnahme'; Risiko = 'Aendern'; Neustart = 'nie'; Rueckgaengig = 'Protokoll'; Minuten = 1; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Dienste, Geräte und Energie'
           Titel = 'Energiesparpläne zurücksetzen'
           Text  = 'Energiesparpläne auf Standard zurücksetzen (eigene Pläne werden vorher gesichert)' }
        @{ Key = 'Datentraegerbereinigung'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 10; Vorauswahl = $false; Ueblich = $true; Gruppe = 'Bereinigung und Speicherplatz'
           Titel = 'Datenträgerbereinigung mit allen Kategorien'
           Text  = 'Datenträgerbereinigung (cleanmgr mit allen Kategorien außer Downloads)' }
        @{ Key = 'Leistungszaehler'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 1; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Dienste, Geräte und Energie'
           Titel = 'Leistungszähler neu aufbauen'
           Text  = 'Leistungszähler aus der Sicherung neu aufbauen (lodctr /r)' }
        @{ Key = 'Leerlaufaufgaben'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 1; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Dienste, Geräte und Energie'
           Titel = 'Leerlaufaufgaben jetzt ausführen'
           Text  = 'Aufgeschobene Windows-Wartungsaufgaben starten (ProcessIdleTasks)' }
        @{ Key = 'ShaderCache'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 1; Vorauswahl = $false; Ueblich = $true; Gruppe = 'Bereinigung und Speicherplatz'
           Titel = 'Shader-Caches der Grafiktreiber leeren'
           Text  = 'DirectX-, OpenGL-, Intel- und AMD-Shader-Caches leeren' }
        @{ Key = 'UpdateDownloads'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 1; Vorauswahl = $false; Ueblich = $true; Gruppe = 'Bereinigung und Speicherplatz'
           Titel = 'Heruntergeladene Updates löschen'
           Text  = 'SoftwareDistribution-Download-Ordner leeren (installierte Updates bleiben erhalten)' }
        @{ Key = 'Absturzabbilder'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 1; Vorauswahl = $false; Ueblich = $true; Gruppe = 'Bereinigung und Speicherplatz'
           Titel = 'Absturzabbilder und Installationsreste löschen'
           Text  = 'CrashDumps, MSOCache, RetailDemo und Treiberreste leeren' }
        @{ Key = 'Prefetch'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 1; Vorauswahl = $false; Ueblich = $true; Gruppe = 'Bereinigung und Speicherplatz'
           Titel = 'Prefetch-Daten löschen'
           Text  = 'Prefetch-Ordner leeren (Windows baut die Daten danach neu auf)' }
        @{ Key = 'PaketCache'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 1; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Bereinigung und Speicherplatz'
           Titel = 'Paket-Cache von Installationsprogrammen löschen'
           Text  = 'Paket-Cache von Installationsprogrammen leeren (Package Cache)' }
        @{ Key = 'Wiederherstellungspunkte'; Typ = 'Massnahme'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'; Minuten = 1; Vorauswahl = $false; Ueblich = $false; Gruppe = 'Bereinigung und Speicherplatz'
           Titel = 'Alte Wiederherstellungspunkte löschen'
           Text  = 'Alte Schattenkopien auf dem Systemlaufwerk löschen' }
    )
}
