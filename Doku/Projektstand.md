# Leos Minibench: Projektstand

Gemeinsamer Stand für alle Agenten (Claude, Antigravity). Wird am Ende jeder Version aktualisiert (siehe AGENTS.md).

## Stand: Version 3.63 (13.10.2026)
Letzter Release-Commit auf GitHub: e88577a (Release v3.63: Geschätzter Gesamtsystemverbrauch, Effizienz-Metriken (Punkte pro Watt) und interaktiver Stromkostenrechner).


Inhalt von 3.63 (Einzelheiten in Doku\Änderungen_v3.63.txt):
1. Geschätzter Gesamtsystemverbrauch: Mathematisches Modell für Desktop (DC intern und AC an der Steckdose bei 88 % Wirkungsgrad)
   und Notebooks (Display/Plattform 7 W, LPDDR/SSD 3 W, VRM 5 %, 90 % Wirkungsgrad; reale DischargeRate bei Akkubetrieb).
2. Effizienz-Metriken (Punkte pro Watt): Ausweisung von CPU-Effizienz (CPU|MT / CpuW), GPU-Effizienz (GPU / GpuW) und Gesamtsystem-
   Effizienz (Overall / System-Watt) im HTML-Bericht und im interaktiven Multi-System Dashboard.
3. Interaktiver Stromkostenrechner: Dynamischer Rechner im HTML-Bericht für jährliche Stromkosten mit einstellbaren Nutzungszeiten
   für Alltag und Volllast sowie editierbarem Kilowattstundenpreis.
4. Dashboard-Integration: Neue Diagrammansicht "Leistung (W)" für Multi-System Zeitreihenvergleiche, Profilkarten mit Verbrauchs-
   Plaketten und neue Kategorie in der Vergleichsmatrix.
5. Robuste Absicherung & Non-Interactive Tests: Saubere Anzeige von "n/v (kein Leistungssensor)" bei sensorlosen Systemen; Testen.cmd
   beendet Testläufe ohne Tastendruck.

Testlauf Windows (Windows PowerShell 5.1, Pester 6.2.0): 805 bestanden, 0 fehlgeschlagen, 99 übersprungen
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