# Leos Minibench: Projektstand

Gemeinsamer Stand für alle Agenten (Claude, Antigravity). Wird am Ende jeder Version aktualisiert (siehe AGENTS.md).

## Stand: Version 3.62 (13.10.2026)
Letzter Release-Commit auf GitHub: f758044 (Update instructions in README). Lokaler Commit 88b5cf0 (Release v3.61).
Version 3.62 entsteht als Release-Commit durch Bauen.cmd und wird direkt automatisch nach GitHub gepusht.

Inhalt von 3.62 (Einzelheiten in Doku\Änderungen_v3.62.txt):
1. Bedarfsorientierter Lauf-Export (.minibench): Austauschdatei entsteht nur bei Bedarf. Neue Schaltfläche "Lauf exportieren …"
   direkt in der Ergebnisansicht am Laufende (neben "Ordner öffnen") sowie weiterhin in der Vergleichsdatenbank.
2. Keine Diagnosebericht.txt bei vorhandenem HTML: Wurde Diagnosebericht.html erfolgreich erzeugt, entfällt die redundante
   reine Textfassung. Bei Fehlern bleibt sie als automatischer Fallback erhalten.
3. Kerne und Threads in allen Referenzen: Alle mitgelieferten Profile (Desktop High-End, Desktop Mittelklasse, Mini-PC APU,
   Notebook Standard, Workstation Mobil) besitzen nun reale Kerne und logische Threads; Referenzen_Eingebettet.ps1 aktualisiert.
4. Kompakter Lasttest: Standardauswahl der Testdauer auf 2 Minuten verkürzt (vorher 15 Minuten) für schnellere Prüfläufe.
5. Automatischer GitHub-Push & Release-Workflow: Bauen.cmd committet und pusht bei bestandenen Tests vollautomatisch nach
   GitHub und aktualisiert die README.md. AGENTS.md entsprechend angepasst.

Testlauf Windows (Windows PowerShell 5.1, Pester 6.2.0): 796 bestanden, 0 fehlgeschlagen, 99 übersprungen
(in Lauf.Tests.ps1; gewollt ohne -Gesamtlauf). Alle Fachgebiets-Tests erfolgreich.

## Offene Befunde
Keine offenen Befunde.

## Fallstricke
1. Pester 6.2 auf ULB-PC10039: Attrappen mit -ParameterFilter brauchen eine Vorgabe-Attrappe ohne Filter.
2. Windows PowerShell 5.1: Einzelnes Objekt ohne .Count, daher Ergebnisse von Listenfunktionen immer mit $x = @(...) einsammeln.
3. Dialoge und Formulare: Jeder Dialog muss UI.ThemeDialog aufrufen, um Darstellungsprobleme im dunklen Farbschema zu vermeiden.
4. Zahlenformate in Tests: Trennzeichen kulturabhängig ([.,]) prüfen.
5. BOM-Prüfung: Textdateien (außer .cmd) immer mit UTF-8 BOM speichern, da Windows PowerShell 5.1 sonst ANSI annimmt.

## Testgeräte
TORRENT: Ryzen 5 7600X, Radeon RX 6800, B650 Gaming X AX, PawnIO 2.2.0.0, 5 Laufwerke (3 NVMe, 2 SATA).
ULB-PC10039: Dell Precision 5480, i9-13900H, Iris Xe und RTX 3000 Ada Laptop (Hybridgrafik), Domänen-PC, BitLocker,
WD SN820 4 TB, unter CPU-Last bis 100 °C (Firmware-Drosselung).
DESKTOP-2KDA9KP: Dell Latitude 5300, i5-8365U, UHD 620.
DESKTOP-F9HRMRR: Ryzen 5 5600, RX 570, B450, RAM mit 2133 MT/s.