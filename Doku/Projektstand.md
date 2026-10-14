# Leos Minibench: Projektstand

Gemeinsamer Stand für alle Agenten (Claude, Antigravity). Wird am Ende jeder Version aktualisiert (siehe AGENTS.md).

## Stand: Version 3.66 (14.10.2026)
Release-Commit "Release v3.66: Dark Mode beim Programmstart, Dashboard-Telemetrie und GPU-Effizienz in FPS/Watt".
Getestet und gebaut unter Windows mit Windows PowerShell 5.1 und Pester 6.2.0.

Inhalt von 3.66 (Einzelheiten in Doku\Änderungen_v3.66.txt):
1. Dark Mode beim Start: SetPreferredAppMode vor Control-Erzeugung, OnShown und ShowPage wenden DarkMode_Explorer rekursiv auf alle Win32-Scrollbars an.
2. Sensor-Status-Badge in der Kopfzeile: Dezentes Badge für aktiven Modus (LHM + PawnIO aktiv oder Windows-Fallback), gekoppelt an Treiberwahl.
3. Dashboard-Telemetrie für Neu-Läufe: Export-BenchDashboardHtml nach Anhang.zip-Erzeugung; extractCsvSeries liest auch .minibench und Fallback-Dateien.
4. Canvas-Diagramm: Zwei getrennte Y-Achsen (links: °C in Blau/Orange, rechts: Watt in Grün/Gelb); zentrierte Infokarte mit Peak-Werten bei Systemen ohne Zeitreihe.
5. GPU-Effizienz: Strikt in FPS/Watt aus Render-FPS (GPU|REND) geteilt durch Maximalleistung (GpuWMax); Beschriftung im Bericht auf FPS/W korrigiert.
6. HTML-Bericht: Sticky-Navigation mit dezentem Schatten und flüssiger Nach-oben-Knopf unten rechts ab 300 px Scrolltiefe.
7. Bildschirmfoto: Doku\Screenshots\Oberflaeche neu.png als Standard-Vorschaubild Oberflaeche.png übernommen.

Testlauf Windows (Windows PowerShell 5.1, Pester 6.2.0): 821 bestanden, 0 fehlgeschlagen, 99 übersprungen
(in Lauf.Tests.ps1; gewollt ohne -Gesamtlauf). Alle Fachgebiets-Tests fehlerfrei.

## Vorher: Version 3.65
Inhalt von 3.65 (Einzelheiten in Doku\Änderungen_v3.65.txt):
1. Einheitliche Karten (CardPanel) für Optionen der Diagnose, Tabellen des Lasttests, Paketauswahl der Tools und Listen der Laufansicht.
2. Wartung im Aufbau der Optimierung (CategoryBlock) mit Gruppenbeschreibung, "alle" und "keine", Etiketten rechts und "Alle aufklappen".
3. Angeglichene Laufansicht mit Kartenrahmen, Etiketten in normaler Schreibweise und themenangepasstem Protokollfeld.
4. Korrekturen nach Windows-Test: Zeitangabe mit Parallelausführung, Diagnose (parallel) in Fußleiste, Optimierungsknöpfe zweizeilig,
   Netzlaufwerk-Karte ohne Textabschnitt, größeres Schildsymbol.
5. Diagnosebericht: KPI-Kopfzeile (.cards) auf minmax(120px, 1fr) mit kompakten Abständen und Schriftgröße angepasst, sodass alle
   sieben Kennzahlen (inklusive Zuverlässigkeit) einzeilig nebeneinander stehen und nicht mehr in eine zweite Zeile umbrechen.

## Vorher: Version 3.64
Inhalt von 3.64 (Einzelheiten in Doku\Änderungen_v3.64.txt):
1. Gestaltungsregeln in der Klasse UI (Abstände, Seitenrand 24 px, Gruppenbreite 780 px, Schriftstufen), neue Steuerelemente
   Badge, GroupHeader und PrimaryButton, Zweizeilen-Optionen (Opt2), UI.OnAccent für Kontrast auf Akzentflächen.
2. Seitenleiste in Ablauf und Werkzeuge, Schalter "beim Start ausführen" im Seitenkopf, flache Kopfzeile mit Symbolknöpfen,
   Seite Systemänderungen, Fußleiste mit Ablauf und Gesamtdauer, Startknopf mit Beschriftung nach Auswahl.
3. Zusammenfassung vor dem Start (StartUebersicht) nur bei Eingriffen, Neustarts, abgewähltem Wiederherstellungspunkt oder
   verwalteten Einträgen auf Domänen-PCs; ersetzt die Rückfragen von Wartung und Optimierung.
4. Diagnose ohne Funktionstest und Nur Absturzanalyse (Skriptparameter bleiben), Lasttest als Tabelle, Wartung und
   Optimierung mit Etiketten, Tools mit einer Bildlaufleiste und Werkzeugkarten mit Zustand.

## Offene Befunde
Keine offenen Befunde.
Die Windows-Prüfung auf ULB-PC10039 ist abgeschlossen; aktualisierte Bildschirmfotos liegen in Doku\Screenshots\ vor.
Die KPI-Kopfzeile im Diagnosebericht ist einzeilig ohne Zeilenumbruch.

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