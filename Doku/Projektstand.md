# Leos Minibench: Projektstand

Gemeinsamer Stand für alle Agenten (Claude, Antigravity). Wird am Ende jeder Version aktualisiert (siehe AGENTS.md).

## Stand: Version 3.64 (14.10.2026)
Letzter Release-Commit: dd792f1 (Release v3.64: Überarbeitete Oberfläche: klare Navigation, eindeutiger Startknopf,
Etiketten für Risikostufen und einheitliches Raster). Erstellt von Claude in der Sandbox auf Grundlage von 8e14f3c
(origin/main), übergeben als Git-Bundle; Push über Antigravity.

Inhalt von 3.64 (Einzelheiten in Doku\Änderungen_v3.64.txt):
1. Gestaltungsregeln in der Klasse UI (Abstände, Seitenrand 24 px, Gruppenbreite 780 px, Schriftstufen), neue Steuerelemente
   Badge, GroupHeader und PrimaryButton, Zweizeilen-Optionen (Opt2), UI.OnAccent für Kontrast auf Akzentflächen.
2. Seitenleiste in Ablauf und Werkzeuge, Schalter "beim Start ausführen" im Seitenkopf, flache Kopfzeile mit Symbolknöpfen,
   Seite Systemänderungen, Fußleiste mit Ablauf und Gesamtdauer, Startknopf mit Beschriftung nach Auswahl.
3. Zusammenfassung vor dem Start (StartUebersicht) nur bei Eingriffen, Neustarts, abgewähltem Wiederherstellungspunkt oder
   verwalteten Einträgen auf Domänen-PCs; ersetzt die Rückfragen von Wartung und Optimierung.
4. Diagnose ohne Funktionstest und Nur Absturzanalyse (Skriptparameter bleiben), Lasttest als Tabelle, Wartung und
   Optimierung mit Etiketten, Tools mit einer Bildlaufleiste und Werkzeugkarten mit Zustand.

Testlauf Sandbox (pwsh 7.4, Pester-Nachbau, mono): 804 bestanden, 13 fehlgeschlagen, 3 übersprungen ohne Lauf.Tests.ps1.
Die 13 Fehler bestehen schon auf 8e14f3c (Bericht 11 und Datenbank 1: Get-CimInstance im Nachbau nicht verfügbar;
Sensoren 1: Test-OnBattery unter Linux). Lauf.Tests.ps1 (Gesamtläufe) läuft in der Sandbox nicht. Windows-Lauf steht aus.

## Offene Befunde
1. Oberfläche 3.64 unter Windows prüfen: Segoe Fluent Icons, Segmentschalter der Diagnose, Etiketten, Skalierung 100, 125 und
   150 %, beide Farbschemata; Bildschirmfotos nach Doku\Screenshots. In der Sandbox nur mit mono und Ersatzschriften gesehen.
2. Testen.cmd unter Windows laufen lassen (Bericht.Tests.ps1 und Datenbank.Tests.ps1 scheitern im Sandbox-Nachbau schon auf
   8e14f3c an einer Attrappe für Get-CimInstance; prüfen, ob das unter Pester 6.2 auch so ist).

## Fallstricke
1. Pester 6.2 auf ULB-PC10039: Attrappen mit -ParameterFilter brauchen eine Vorgabe-Attrappe ohne Filter.
2. Windows PowerShell 5.1: Einzelnes Objekt ohne .Count, daher Ergebnisse von Listenfunktionen immer mit $x = @(...) einsammeln.
3. Dialoge und Formulare: Jeder Dialog muss UI.ThemeDialog aufrufen, um Darstellungsprobleme im dunklen Farbschema zu vermeiden.
4. Zahlenformate in Tests: Trennzeichen kulturabhängig ([.,]) prüfen.
5. BOM-Prüfung: Textdateien (außer .cmd) immer mit UTF-8 BOM speichern, da Windows PowerShell 5.1 sonst ANSI annimmt.
6. Oberfläche ab 3.64: Seiten ohne Dock bekommen ihre Position in BuildSetup (Seitenrand); neue Seiten nicht mit Location 0,0
   anlegen. Primärknöpfe immer über UI.Primary (Typ PrimaryButton), Schriftfarbe UI.OnAccent, nie Color.White.

## Testgeräte
TORRENT: Ryzen 5 7600X, Radeon RX 6800, B650 Gaming X AX, PawnIO 2.2.0.0, 5 Laufwerke (3 NVMe, 2 SATA).
ULB-PC10039: Dell Precision 5480, i9-13900H, Iris Xe und RTX 3000 Ada Laptop (Hybridgrafik), Domänen-PC, BitLocker,
WD SN820 4 TB, unter CPU-Last bis 100 °C (Firmware-Drosselung).
DESKTOP-2KDA9KP: Dell Latitude 5300, i5-8365U, UHD 620.
DESKTOP-F9HRMRR: Ryzen 5 5600, RX 570, B450, RAM mit 2133 MT/s.