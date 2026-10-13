# Leos Minibench: Projektstand

Gemeinsamer Stand für alle Agenten (Claude, Antigravity). Wird am Ende jeder Version aktualisiert (siehe AGENTS.md).

## Stand: Version 3.61 (13.10.2026)
Letzter Release-Commit: Commit 995e514 (Release v3.6). Version 3.61 entsteht als Commit "Release v3.61: ..." beim
nächsten erfolgreichen Bauen.cmd.

Inhalt von 3.61 (Einzelheiten in Doku\Änderungen_v3.61.txt):
1. All-in-One-Austauschformat (.minibench): Selbsttragendes ZIP-Archiv bündelt Datenbank.json, Berichte (HTML, TXT),
   Anhang.zip und Telemetrie. Automatisches Erstellen am Laufende und Export-Funktion in der Vergleichsdatenbank.
   KI-Kurzfassung restlos entfernt.
2. Erweiterter Import & Doppelklick-Verlinkung: Importiert Ordner, .minibench, .zip und .json Dateien. Kopiert Berichtsordner
   nach Minibench-Daten\Berichte und verknüpft das Feld Ordner; Doppelklick öffnet den Bericht sofort im Browser.
3. Referenzprofile mit Lasttest-Telemetrie: Strukturierte Lasttest-Werte in allen Profilen; neues GTX-1070-System von
   Matthias PC hinzugefügt; Dashboard und HTML-Bericht zeigen Lasttest-Deltas; -MedianAktualisieren pflegt Lasttest-Mediane ein.
4. Unterbrechungsfreier Start: Popups AskDriver und AskSensorTools vor dem Start restlos entfernt; PawnIO-Sensormessung
   standardmäßig aktiv mit lautlosem Nachladen fehlender Werkzeuge; manuelle Steuerung auf Seite Sensoren live erhalten.

Testlauf Windows (Windows PowerShell 5.1, Pester 6.2.0): 795 bestanden, 0 fehlgeschlagen, 99 übersprungen
(in Lauf.Tests.ps1; gewollt ohne -Gesamtlauf). Alle Fachgebiets-Tests erfolgreich.

## Offene Befunde
Keine offenen Befunde. Die früheren Punkte aus Version 3.54 (synthetische Kurve im Dashboard, doppelte Kopie,
script-Maskierung) sind vollständig behoben.

## Fallstricke
1. Pester 6.2 auf ULB-PC10039: Attrappen mit -ParameterFilter brauchen eine Vorgabe-Attrappe ohne Filter.
2. Windows PowerShell 5.1: Einzelnes Objekt ohne .Count, daher Ergebnisse von Listenfunktionen immer mit $x = @(...) einsammeln.
3. Dialoge und Formulare: Jeder Dialog muss UI.ThemeDialog aufrufen, um Darstellungsprobleme im dunklen Farbschema zu vermeiden.
4. Zahlenformate in Tests: Trennzeichen kulturabhängig ([.,]) prüfen.

## Testgeräte
TORRENT: Ryzen 5 7600X, Radeon RX 6800, B650 Gaming X AX, PawnIO 2.2.0.0, 5 Laufwerke (3 NVMe, 2 SATA).
ULB-PC10039: Dell Precision 5480, i9-13900H, Iris Xe und RTX 3000 Ada Laptop (Hybridgrafik), Domänen-PC, BitLocker,
WD SN820 4 TB, unter CPU-Last bis 100 °C (Firmware-Drosselung).
DESKTOP-2KDA9KP: Dell Latitude 5300, i5-8365U, UHD 620.
DESKTOP-F9HRMRR: Ryzen 5 5600, RX 570, B450, RAM mit 2133 MT/s.