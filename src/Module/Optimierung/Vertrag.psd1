# Modulvertrag Optimierung (Vertrag 1, ab v2.8). Felder sind in src\Kern\Modulvertrag.ps1 beschrieben.
# Die einzelnen Einstellungen stehen im Katalog (Katalog.psd1); die Schritte hier fassen sie nach Art der Absicherung zusammen.
@{
    Vertrag         = 1
    Name            = 'Optimierung'
    Seite           = @{ Titel = 'Optimierung'; Kurz = 'Windows Optimisation Pack, gruppiert' }
    Admin           = $true
    Risiko          = 'Eingriff'
    Neustart        = 'immer'
    Parameter       = @('Optimierungen', 'OptOhneWiederherstellungspunkt', 'OptimierungZustand', 'OptWerkzeugeHolen')
    Datenbankfelder = @('Optimierung')
    Schritte        = @(
        @{ Key = 'Zustand'; Typ = 'Pruefung'; Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'
           Titel = 'Zustand und Kennzahlen vorher und nachher' }
        @{ Key = 'Einstellungen'; Typ = 'Optimierung'; Risiko = 'Aendern'; Neustart = 'moeglich'; Rueckgaengig = 'Protokoll'
           Titel = 'Registry, Dienste, geplante Aufgaben, Windows-Funktionen, Energie (einzeln rückgängig)' }
        @{ Key = 'Entfernen'; Typ = 'Optimierung'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Rueckgaengig = 'Wiederherstellungspunkt'
           Titel = 'Apps, Zusatzfeatures und OneDrive entfernen' }
        @{ Key = 'Bereinigung'; Typ = 'Optimierung'; Risiko = 'Eingriff'; Neustart = 'nie'; Rueckgaengig = 'keins'
           Titel = 'Temporäre Dateien, Caches, Komponentenspeicher, Datenträgerbereinigung' }
        @{ Key = 'Grafiktreiber'; Typ = 'Optimierung'; Risiko = 'Eingriff'; Neustart = 'immer'; Rueckgaengig = 'Hinweis'
           Titel = 'Grafiktreiber mit DDU entfernen, NVIDIA-Profil setzen' }
    )
}
