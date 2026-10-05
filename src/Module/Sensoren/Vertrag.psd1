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
