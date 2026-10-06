# Changelog - Leos Minibench

Alle wesentlichen Änderungen an Leos Minibench werden in diesem Dokument festgehalten.

## v3.2 (06.10.2026)

* **Fluent 2 / Wintoys-Look & Design-Modernisierung:**
  * Modernes Windows 11 Fluent 2-Farbschema: Hintergrund `#F9F9FB`, weiße Karten mit feinem 1px-Rahmen (`#E5E7EB`), Windows 11-Akzentfarben (`#0067C0`, Hover `#005A9E`, Active `#004F8A`, Auswahl `#EBF3FB`) und weiche Pastell-Badges.
  * Neues `ToggleSwitch`-Steuerelement: Pillenförmige Spur (`UI.S(20)` Höhe, `UI.S(38)` Breite), runder Schieber mit dezentem Schatten, Windows-Akzentfüllung im aktiven Zustand, barrierefreie Tastaturbedienung mit Leertaste und Tooltip-Unterstützung.
  * Neue `FluentCard`-Komponente: Kartenansicht für Optionen im Wintoys-Stil mit Segoe-Symbol, Titel, Untertitel und eingebetteten Toggle-Schaltern oder Aktionsschaltflächen (Umschaltung per Klick auf die Karte).
  * Gestochen scharfe Segoe-Icons: Einbindung von `Segoe Fluent Icons` (mit Fallback auf `Segoe MDL2 Assets`) für Navigation und Hardware-Kategorien.
  * Modernisierte Navigation (`NavItem`): Windows 11-Sidebar-Stil mit 6 px Eckenrundung, aktivem 3 px-Akzentbalken, sanftem Auswahlhintergrund und Segoe-Icons.
* **Windows 11 DWM-Integration & Notebook-Sicherheit:**
  * Echte Windows 11-Fensterabrundung über DWM P/Invoke (`DWMWA_WINDOW_CORNER_PREFERENCE = 33`, `DWMWCP_ROUND = 2`).
  * Saubere DPI-Initialisierung über `SetProcessDpiAwarenessContext(-4)` (PerMonitorV2) und `SetProcessDpiAwareness(2)` ohne das veraltete `SetProcessDPIAware()`.
  * Dynamische Fensterberechnung anhand des sichtbaren Arbeitsbereichs (`WorkingArea * 0.94` Breite, `WorkingArea * 0.88` Höhe) und `MinimumSize` von `860x540` px gegen Überlauf auf 1080p-Notebooks bei 150 % Skalierung.
* **Zentraler DPI-Helper & Tabellen-OwnerDraw:**
  * Zentraler DPI-Helper in `UI` mit `UI.DpiScale`, `UI.S(px)` und `UI.SF(px)`.
  * Vollständig responsive Seiten Versionen, Änderungen und Vergleichsdatenbank mit `DockStyle.Fill` und automatischer Restbreiten-Ausfüllung der ListViews.
  * Tabellen-OwnerDraw in der Laufansicht mit skalierter Zeilenhöhe (`34 px`), zentrierten Badge-Pillen und verbreiterten Messwertbereichen (`48 px`) für WinSAT- und Index-Balken (`8 px` Höhe).

## v3.1 (05.10.2026)

* **Vergleichsseite & Deserialisierung:** Fehlerbehebung beim Laden von Systemen in der Benutzeroberfläche; strukturierte Fehlerbehandlung und Logging im JSON-Parser (`DbEntry.Load`).
* **Eingebettete Referenzdaten:** Fünf anonyme Referenzprofile (Desktop High-End bis Notebook Standard) direkt im Skript eingebettet; automatisches Entpacken bei leerem Datenbankordner für sofortige Systemvergleiche ab dem Erststart.
* **Prozessor-Benchmark (CPU-Regression behoben):** Verbindlicher Start über Windows PowerShell 5.1; Beseitigung von RyuJIT-Laufzeitverlangsamungen und Sensor-Abfragekollisionen unter Last.
* **Grafik-Benchmark (Robustheit bei niedrigen Bildraten):** Fehlerbehebung beim Rendertest auf Einsteiger- und Mobil-GPUs (z. B. Intel UHD Graphics 620 auf Dell-Notebooks); kein Verwerfen von Messwerten bei aktiver Vorschau; Fallback-Erkennung und erweiterte Direct3D 11 Feature-Levels (11_1, 9_3) für Hybrid-Grafiksysteme.

## v3.0 (05.10.2026)

* **Sicheres Schritt-Überspringen:** Gezieltes Überspringen langwieriger Einzelschritte (`-Skippable`) mit dynamischer Freigabe (`@@SKIP_ALLOWED`) und geordnetem Hintergrund-Job-Abbruch.
* **Frametime-Latenzen:** Erfassung von 0,1 %-Low FPS und Mikroruckler-Anteil (Frames über 50 ms) in Messwerten, Kurventabellen und HTML-Bericht.
* **Benchmark-Detailtabellen:** Bereinigte Darstellung im HTML-Bericht mit bewährter tabellarischer Struktur (Messung, Wert, Index, Referenz, Vergleich, Ergebnis) bei Beibehaltung des Gesamtleistungs-Banners und der Profilkarten.
* **Referenzprofile:** Fünf bereinigte Referenzsysteme als Standardauswahl; Desktop Mittelklasse dient als Standard-Vergleich.

## v2.95 (05.10.2026)

* **Anonyme Vergleichsdaten fest eingebaut:** Fünf bereinigte Referenzsysteme von Desktop High-End bis Notebook Standard werden bei der Ersteinrichtung automatisch in die lokale Vergleichsdatenbank kopiert.
* **Gesamtleistungs-Banner:** Prominente Leistungskarte im Header des HTML-Berichts mit Gesamtprozentwert relativ zum Referenzsystem.
* **Benchmark-Darstellung im UserBenchmark-Stil:**
  * Drei Nutzungsprofile (Gaming, Büro/Desktop, Workstation) mit gewichteten geometrischen Mittelwerten und Bewertungswörtern.
  * Prominente Komponenten-Köpfe in den Benchmark-Details mit genauer Hardwarebezeichnung, Prozentwert und Referenzbalken.
  * Modernes Spalten-Layout für Messgrößen von Prozessor, Arbeitsspeicher und Grafikkarte.
* **Wartung & Bedienung:**
  * Standardauswahl im Modul Wartung auf risikoarme Bereinigungen vorkonfiguriert.
  * Schnellwahlschalter „Übliche Auswahl“ und „Alle abwählen“ direkt über die Maßnahmenliste versetzt und mit Tooltips versehen.
  * Neue Schaltfläche „Diesen Schritt überspringen“ während des Durchlaufs mit Ereignis `@@SCHRITT_UEBERSPRINGEN`.
* **Minidump Crash Inspector:** Binäre Erkennung und Analyse von Windows-Absturzabbildern (`.dmp`) inklusive Bugcheck-Mapping und Reparaturempfehlungen in Diagnose, Bericht und KI-Datei.
* **Grafiktreiber-Gesundheitscheck:** Überprüfung auf Microsoft Basic Display Adapter, Alter des Treibers (> 18 Monate) und Treiberabstürze (Event ID 4101) mit DDU-Empfehlung.
* **Durchlaufzeit-Optimierung:** Konsequente Nutzung von Zwischenspeichern (`Get-CimCached`) für unveränderliche WMI- und CIM-Systemabfragen.

## v2.9 (05.10.2026)

* **ARM64 & High-DPI:** Hardware-Erkennung mit ARM64-Unterstützung und Warnhinweisen; Per-Monitor V2 DPI-Awareness im Anwendungsmanifest.
* **Modularisierung:** Aufteilung der C#-Oberfläche in spezialisierte Teilklassen für Steuerelemente, Modelle, Vergleich und Seiten.
* **Wartungsmodul:** Reparaturmodul in Wartung umbenannt mit 22 eigenständigen Wartungsschritten und Bereinigung der Redundanzen im Optimierungskatalog.
* **Preset Leos Empfehlung:** Neues Standard-Preset für Windows-Optimierungen.
* **Neugewichtung:** Doppelte Gewichtung von CPU und GPU sowie dreifache Gewichtung der gemessenen Renderleistung im Gesamtergebnis.
* **Vergleichsseite:** Editierbare Systembezeichnungen und interaktive Spaltensortierung in der Vergleichsdatenbank.

## v2.8 (03.10.2026)

* **Modul Optimierung:** 163 native Einstellungen in 14 Kategorien mit Vorlagen (Minimal, Standard, Erweitert), Wiederherstellungspunkt und Rückgängig-Funktion.
* **Sensoren ohne LibreHardwareMonitor:** Fallback auf Windows- und Treiberquellen für GPU-Temperatur, Takt, Lüfter und Auslastung.
* **Berichtsverbesserungen:** Diagramme ohne überlappende Texte, WinSAT-Entkopplung von Benchmark-Unterbrechungen, NVMe-Klassenschätzung.

## v2.7 (03.10.2026)

* **Bedienung & Barrierefreiheit:** Erklärung aller Bedienelemente per Maus-Tooltip.
* **Sensoren im Benchmark:** Durchgehende Aufzeichnung von Temperatur, Takt und Leistungsaufnahme während aller Messungen.
* **Datenpflege & Archivierung:** Automatische Archivierung älterer oder unvollständiger Läufe; Quell- und Build-Archivierung in `Bauen.cmd`.
* **Versionsansicht:** Neue Informationsseite mit vollständiger Versionshistorie im Programm.

## v2.67 (03.10.2026)

* **Gleichmäßige Last im eigenen Prozess:** Auslagerung von CPU- und RAM-Last in einen separaten PowerShell-Hintergrundprozess ohne Unterbrechungen durch Speicherbereinigung.
* **Optimierte Rechenschleifen:** Sinus-Berechnung als Polynom ohne wiederholte Bibliotheksaufrufe.

## v2.66 (03.10.2026)

* **Unterbrechungsmessung:** Protokollierung von Latenzspitzen über 50 ms während Last- und Benchmarks.
* **Robustes Sensor-Polling:** Toleranz bei verspäteten Abfragen und asynchrones Auslesen von Datenträgern.
* **Erweiterter KI-Auftrag:** Bereitstellung vollständiger PowerShell-Befehle und Klickpfade in der Analyse-Datei.

## v2.65 (02.10.2026)

* **Praxistest-Anpassungen:** Vollständige GPU-Messwerte, RAM-Stresstest im Hintergrund, flüssige Rendervorschau und Warnung bei aktiver Bildratengrenze.
* **Flexibler Lasttest:** Frei wählbare Dauer ab 2 Minuten und gezielte Auswahl der Grafikeinheit.

## v2.6 (02.10.2026)

* **Direct3D 11 Rendertest:** Eigener hardwarebeschleunigter 3D-Test zur Erfassung realer Bildraten.
* **Schneller Modus:** Parallele Ausführung von Routineprüfungen zur drastischen Verkürzung der Gesamtlaufzeit.
* **Zero-Footprint & Temp-Ausführung:** Vollständiger Betrieb im temporären Verzeichnis zur Entlastung des USB-Sticks.

## v2.4 (02.10.2026)

* **Hardware-Vertiefung:** Trennung von dedizierter und integrierter Grafikkarte, exakte Taktmessung über PDH, Akkubericht mit Verschleißanalyse und Standby-Sperre.

## v2.3 (01.10.2026)

* **Sensor-Integration:** Einbindung von LibreHardwareMonitor und PawnIO-Treiber mit Sicherheitsprüfungen und Hash-Validierung.
* **Echtzeitüberwachung:** Neuer Reiter für Live-Sensordaten und Drosselnachweis unter Volllast.

## v2.2 (01.10.2026)

* **Modulare Architektur:** Quelltextaufteilung (`src/`), Modulverträge (`Vertrag.psd1`), Risikoklassifizierung aller Aktionen und Pester-Testsuite.
* **Reversibilität:** Strukturiertes Änderungsprotokoll mit Rollback-Funktion.

## v2.0 - v2.1 (01.10.2026)

* **Leos Minibench:** Einführung des Namens, Single-File-EXE für USB-Betrieb, Diagnose-, Benchmark-, Lasttest- und Reparaturmodule sowie HTML-/KI-Berichte.

## v1.0 - v1.8 (bis 30.09.2026)

* **PC-Diagnose:** Ursprüngliche Skriptsammlung zur automatisierten Hardware-Bestandsaufnahme und Benchmark-Auswertung.
