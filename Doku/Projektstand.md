# Leos Minibench: Projektstand

Gemeinsamer Stand für alle Agenten (Claude, Antigravity). Wird am Ende jeder Version aktualisiert (siehe AGENTS.md).

## Stand: Version 3.71 (15.10.2026)
Release-Commit "Release v3.71: Präzise Stromverbrauchsschätzung, Startzeit-Transparenz, Profilkarten und Dashboard-Korrekturen" (Commit 5664f49).
Getestet und gebaut unter Windows mit Windows PowerShell 5.1 und Pester 6.2.0.

Inhalt von 3.71 (Einzelheiten in Doku\Änderungen_v3.71.txt):
1. Präzise Stromverbrauchsschätzung (PSU-Effizienzmodell): Umstellung der DC- und AC-Berechnung auf ein physikalisches Hardware- und Netzteil-Modell mit 230V EU-Effizienzkurven (Unbekannt, 80 PLUS White bis Titanium) und linearer Stützstellen-Interpolation (5 % bis 100 % Netzteilauslastung); interaktive Konfigurationsleiste direkt im HTML-Bericht (Nennleistung in Watt und Effizienzklasse) für Desktops mit Live-Neuberechnung aller Verbrauchswerte, Auslastungsgrade und Stromkosten sowie Speicherung im Browser (localStorage); automatische Erkennung mobiler Plattformen mit OEM-Netzteil-/Akkumodell (~90 % Wirkungsgrad) ohne ATX-Netzteilwahl; detaillierte DC-Erfassung inkl. Mainboard-VRM-Verlusten, AMD-Radeon-TBP-Zuschlägen (+4 W / +15 %), DIMM-Arbeitsspeichermodulen, Datenträgertypen (NVMe/SATA/HDD) und Lüftern sowie Warnung bei Netzteil-Überlastung (> 85 % unter Volllast).
2. System-Startzeit & Nutzungsprofil-Transparenz: Standardmäßig geöffnetes Boot-Performance-Element (<details class="box grp" data-section="system" open>) im HTML-Bericht; saubere Trennung und verständliche Erläuterung der beiden Boot-Phasen aus Event 100 (MainPathBootTime: Desktop/Treiber einsatzbereit vs. BootPostBootTime: Autostart bis vollständiger Leerlauf); Nutzungsprofile (Gaming, Büro, Workstation) mit transparentem Hover-Tooltip zur genauen mathematischen Zusammensetzung und Gewichtung der Komponenten; Referenzsystem-Auswahl (Gespeicherte Referenz, Mediane, Datenbankeinträge) und Referenz-Speichern im Benchmark-Reiter der Benutzeroberfläche wiederhergestellt.
3. Berichts-Feinschliff & Layout-Optimierung: Nutzungsprofile mit farbigem Akzent-Hintergrund (var(--accent-soft)) und neutrale Komponentenkarten (CPU, GPU, RAM, Laufwerke) prominent über den Benchmark-Detailtabellen wiederhergestellt; Facts-Tabelle von redundanten Leistungsschätzungen bereinigt; Block für Gesamtsystemverbrauch und Stromkostenrechner direkt über den Benchmark-Sensoren platziert.
4. Dashboard- & Dark-Mode-Korrekturen: Horizontale und vertikale Trennlinien in Spalte 1 der Matrix-Tabelle im Dark Mode durch kontrastreiche Linienfarben (#444E5E / #363E4D) und z-index-Priorisierung repariert; Emojis (🎮, 💼, 🚀, 📊) beibehalten; Dashboard-Start bei Erstbenutzung ohne Parameterfehler stabilisiert.

## Vorher: Version 3.7
Inhalt von 3.7 (Einzelheiten in Doku\Änderungen_v3.7.txt):
1. Schnell behebbare Konfigurationsfehler: Automatische Erkennung von LAN-Verhandlungsrate gebremst (100 Mbit/s oder Halbduplex an Gigabit/2.5GbE-Adaptern), Monitorkabel an iGPU statt dGPU bei Desktops, Hz-Bremse bei Monitoren >= 75 Hz auf 60 Hz limitiert, inaktivem RAM-Speicherprofil (XMP/EXPO/DOCP) und veraltetem BIOS (> 2 Jahre) mit direkten Hersteller-Supportlinks sowie transparenter Bestätigung der Prüfung im Bericht.
2. System-Startzeit-Analyse (Boot Performance Breakdown): Aufschlüsselung der Windows-Boot-Phasen aus Event 100 (MainPathBootTime, BootPostBootTime, BootDuration) und UEFI/BIOS-POST-Zeit (FwPOSTTime) mit visueller Wasserfall-/Stack-Kaskade im HTML-Bericht (eingeklappt am Berichtsende); Auswertung von Autostart-Verzögerern (Event 101-110 ab 1,0 s) und robuster Fallback ohne Schätzwerte bei unvollständigen Ereignissen oder deaktiviertem Protokoll.
3. Harmonisierte Sensoren-Zustandsmaschine: Konsistente 4-Stufen-Statuslogik (Vollständig, Eingeschränkt, Inaktiv, Fehler) im Skript und in der Benutzeroberfläche; automatische Treiberinitialisierung bei Vorliegen von Administratorrechten ohne zusätzliche Rückfragen und garantierte Treiberentladung bei Programmbeendigung.
4. Benchmark-Vereinfachung & Dashboard: Entfernen redundanter Dropdowns und Checkboxen (Messdauer, Referenz, DB-Speicherung); Benchmark speichert immer in der Vergleichsdatenbank. Beseitigung der Scrollbars in der Vergleichsmatrix mit Wiederholung der Systemnamen am Tabellenende (tfoot), gut sichtbaren Zeilentrennlinien in der Basiskolumne und metrischen Einheiten (°C, %). Stromkostenrechner standardmäßig geöffnet, Details und Zeitbedarf standardmäßig eingeklappt. Redundante Referenz-Spalten und Profilkarten aus dem Einzelbericht entfernt (vollständig durch das interaktive Dashboard abgedeckt).
5. Modulares Dashboard: Vollständige Zerlegung des Dashboard-Quelltexts in separate semantische Bausteine (dashboard.html, dashboard.css, daten.js, matrix.js, profile.js, diagramme.js) mit robuster Einbettung im Zusammenbau-Skript und Syntaxprüfung via node --check.
Inhalt von 3.67 (Einzelheiten in Doku\Änderungen_v3.67.txt):
1. Multi-System-Sensorverlauf: Achsenbeschriftung Temperatur (°C) durch 75 px Randabstand und linksbündige Ausrichtung vollständig sichtbar; Tooltip mit kompakten Systemnamen (getShortSysName), zweizeiligem Layout und stets vorangestelltem Basissystem (auch ohne Zeitreihe).
2. Differenzierte Nutzungsprofile: Gewichtung für Gaming (70 % GPU-FPS, 20 % ST, 10 % RAM/SSD; Kerne > 8 neutral), Büro/Desktop (45 % SSD-Reaktionszeit, 35 % ST, 20 % RAM-Latenz; 0 % GPU/MT) und Workstation (45 % MT, 20 % Instruktionen, 20 % RAM-Bandbreite, 15 % Dauertransfer); redundante Stromverbrauchs-Badges im Profilgitter entfernt.
3. Hervorhebung des Basissystems: Markante Akzent-Umrandung mit Anker-Symbol im Auswahlbereich, durchgehende Hintergrundhervorhebung mit 100-%-Basis-Badge in Hardware- und Matrix-Tabelle sowie Akzent-Rahmen in den Profilkarten.
4. Hardware-Tabelle aufgeräumt: Redundante Berichtszeile entfernt; kompakte Datenträger-Zusammenfassung nach Typ und Gesamtkapazität mit vollständiger Modellliste im Hinweis beim Überfahren.
5. Kalibrierte Moduldauern: Grundzeit der Diagnose auf 0 Min. gesenkt, Zuschläge für Systemprüfungen und WinSAT auf reale SSD-Dauern kalibriert.
6. Dashboard-Feinschliff: Versionspille dynamisch an Skriptversion gekoppelt, kompakte Matrix-Tabellenzeilen und fixierte Tabellenköpfe (sticky) beim Scrollen.

## Vorher: Version 3.66
Inhalt von 3.66 (Einzelheiten in Doku\Änderungen_v3.66.txt):
1. Dark Mode beim Start: SetPreferredAppMode vor Control-Erzeugung, OnShown und ShowPage wenden DarkMode_Explorer rekursiv auf alle Win32-Scrollbars an.
2. Sensor-Status-Badge in der Kopfzeile: Dezentes Badge für aktiven Modus (LHM + PawnIO aktiv oder Windows-Fallback), gekoppelt an Treiberwahl.
3. Dashboard-Telemetrie für Neu-Läufe: Export-BenchDashboardHtml nach Anhang.zip-Erzeugung; extractCsvSeries liest auch .minibench und Fallback-Dateien.
4. Canvas-Diagramm: Zwei getrennte Y-Achsen (links: °C in Blau/Orange, rechts: Watt in Grün/Gelb); zentrierte Infokarte mit Peak-Werten bei Systemen ohne Zeitreihe.
5. GPU-Effizienz: Strikt in FPS/Watt aus Render-FPS (GPU|REND) geteilt durch Maximalleistung (GpuWMax); Beschriftung im Bericht auf FPS/W korrigiert.
6. HTML-Bericht: Sticky-Navigation mit dezentem Schatten und flüssiger Nach-oben-Knopf unten rechts ab 300 px Scrolltiefe.
7. Bildschirmfoto: Doku\Screenshots\Oberflaeche neu.png als Standard-Vorschaubild Oberflaeche.png übernommen.

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

## Letzter Commit
Release-Commit v3.71 (Commit 5664f49)