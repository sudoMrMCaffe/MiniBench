# Leos Minibench: Projektstand

Gemeinsamer Stand für alle Agenten (Claude, Antigravity). Wird am Ende jeder Version aktualisiert (siehe AGENTS.md).

## Stand: Version 3.6 (10.10.2026)
Letzter gepushter Release: Commit 25ee019 (Release v3.54). Version 3.6 entsteht als Commit "Release v3.6: ..." beim
nächsten erfolgreichen Bauen.cmd.

Inhalt von 3.6 (Einzelheiten in Doku\Änderungen_v3.6.txt):
1. Feste Median-Referenzen für Geräteklassen Notebook und Desktop (Referenz_Notebook.json, Referenz_Desktop.json),
   kontrolliert aktualisierbar auf Knopfdruck oder über -MedianAktualisieren.
2. Wartungsmaßnahmen gegliedert: 23 Maßnahmen in 4 fachliche Gruppen gegliedert mit Klappfunktion, Auswahlanzeige
   und synchronisierten Schaltflächen ("Übliche Auswahl", "Keine").
3. Diagnose-Prüfungen standardmäßig eingeklappt mit dynamischer Statuszusammenfassung; automatisches Aufklappen bei
   Profil "Benutzerdefiniert".
4. Dunkles Farbschema konsistent: UI.ThemeDialog formatiert Formulare und Kind-Elemente (Labels, CheckBoxen,
   RadioButtons, Eingabefelder) ohne schwarze Schrift auf dunklem Grund.
5. Hardware-Spezifikationen: Reale Kerne und logische Threads in Datenbankeinträgen erfasst; Get-CpuAnzeigename
   befreit Prozessornamen von Hersteller- und Taktballast ("Ryzen 5 7600X (6 Kerne, 12 Threads)").
6. Dashboard und Telemetrie: Multi-System-Sensorverlauf vor Befunden platziert mit CPU/GPU-Reitern, Tooltips mit
   Takt/Watt/iGPU, synthetische Kurven und redundanter Basis-Detailmodus restlos entfernt, Profilkarten nach Score sortiert.
7. Sensor- und Praxistesthärtung aus Feldtests: Hintergrundlastprüfung vor Messungen (> 15 % verwirft Leerlauf-Etikett
   mit 90/80 °C Schwellen), Akkuverschleiß-Historie geschützt, Optimus-Hybridgrafik sauber zugeordnet, unplausible
   Sensorwerte (< 5 °C, doppelte Leerlaufspannungen > 1.5 V) gefiltert, Akkubetrieb beim Benchmark markiert.

Testlauf Windows (Windows PowerShell 5.1, Pester 6.2.0): 789 bestanden, 0 fehlgeschlagen, 100 übersprungen
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