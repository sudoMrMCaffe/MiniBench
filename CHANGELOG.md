# Changelog - Leos Minibench

Alle wesentlichen Änderungen an Leos Minibench werden in diesem Dokument festgehalten.

## v3.54 (09.10.2026)

* **Datenordner immer auf dem Stick:** `Resolve-DataDir` liest `Netzwerk.json` nicht mehr und ruft kein `net use`. Der Start ist ohne NAS so schnell wie mit; Tools, Cache und Laufzeit liegen immer im Datenordner auf dem Stick (vorher wurden Tools auf dem NAS gesucht, Sensoren fehlten).
* **Netzlaufwerk als Spiegel (`Kern\Ablage.ps1`):** Abgleich nur über Aktualisieren (Hilfsmodus `-Abgleich`), in beide Richtungen gegen den Stand des letzten Abgleichs (`Minibench-Daten\Abgleich\Stand.json`). Neuere Fassung gilt, ältere nach `Archiv\Abgleich\<Zeit>\Konflikte`; Löschungen werden als Verschiebung ins Archiv übertragen, Änderung schlägt Löschung. Schutz vor Massenlöschung (hält an; `-AbgleichLoeschen` bestätigt, `-AbgleichNeu` führt ohne Entfernen zusammen), Abbruch ohne Änderung bei Lesefehlern, Sperre `Abgleich.lock`, Toleranz für Zeitverschiebung auf FAT-Sticks.
* **Netzlaufwerk einrichten:** `Netzwerk.json` nur im Datenordner auf dem Stick, Kennwort nie gespeichert, Verbindung über `WNetAddConnection2` ohne `/persistent`, beim Beenden getrennt. Pfade mit nur einem führenden `\` werden abgelehnt (Ursache des Ordners `TRUENAS` auf dem Stick).
* **Vergleichsdatenbank:** Entfernen verschiebt Eintrag und Berichtsordner nach `Archiv\Entfernt\<Zeit>` (`-Entfernen`); Name ändern benennt Datenbankdatei und Berichtsordner um und führt Verweise in den Änderungsprotokollen nach (`-Umbenennen`).
* **Datenpflege:** PawnIO-Merker und `Start.log` bleiben stehen; `-Include` ohne `-Recurse` ersetzt (fand unter PS 5.1 nichts).
* **Tests:** neue Datei `Ablage.Tests.ps1`, Datenordner-Tests in `Datenbank.Tests.ps1` neu gefasst, drei Fälle im Selbsttest der Oberfläche.

## v3.53 (09.10.2026)

* **Softwarepakete (Seite Tools) über das Änderungsprotokoll:** winget läuft im Arbeitsprozess (`-SoftwareInstallieren`) mit Frist je Paket (20 Minuten) und vollständig gelesener Ausgabe. Vorher konnte die Installation unbegrenzt hängen, weil die umgeleitete Ausgabe nie gelesen wurde. Jede Installation ist ein Eingriff im Änderungsprotokoll mit Gegenbefehl `winget uninstall`; die Seite Änderungen nimmt sie zurück. Schon vorhandene Programme werden weder angefasst noch protokolliert. Vor dem Start fragt die Oberfläche nach.
* **Grafikauswahl im Lasttest:** Die Wahl auf der Seite Lasttest sprang auf den Wert des Benchmarks zurück (vertauschte Zuweisung). Beide Seiten gleichen Auflösung, Anzeige und Grafikeinheit jetzt über `CopySelection` in beide Richtungen ab.
* **Absturzabbilder:** Parameter ab 0x8000000000000000 (Kerneladressen) brachen das Lesen eines Minidumps ab.
* **Testsuite nach Fachgebieten:** Die Dateien `Version26.Tests.ps1` bis `Version352.Tests.ps1` und `Dashboard.Tests.ps1` sind aufgelöst. Neu: `Ablauf`, `Bericht`, `Messung`, `Optimierung`, `Release`; erweitert: `Oberflaeche`, `Sensoren`, `Datenbank`, `Aufbau`, `Auswertung`, `Modulvertrag`, `Werkzeuge`, `Aenderungen`. Die Oberfläche wird je Testlauf einmal übersetzt und mit einem Selbsttest geprüft. `Testen.cmd -Datei Oberflaeche,Release` startet einzelne Dateien.
* **Bauen.cmd:** Commit-Nachricht aus `Versionen.cs`, Commit nur nach bestandenen Tests, Ergebnis von `git commit` wird geprüft, keine BOM mehr am Dateianfang.

## v3.52 (07.10.2026)

* **Sensorwerkzeuge, Binaries & Cache strikt lokal gebunden (NAS-Härtung):**
  * **Trennung von Daten und Code:** Berichte ($script:ReportDir) und Datenbanken ($script:DbDir) dürfen auf konfigurierte Netzlaufwerke/NAS-Pfade zeigen. Ausführbare Dateien, Treiber und temporäre Caches ($script:LocalDataDir, $script:CacheDir, $script:ToolsDir, $script:CpDir) werden strikt lokal (auf dem USB-Stick bzw. im lokalen %TEMP% / %LOCALAPPDATA%) isoliert.
  * **Behebung von Pfadformat- & CAS-Fehlern:** Löst Ausnahmen ("Das angegebene Pfadformat wird nicht unterstützt.") und .NET Code Access Security-Blockaden beim Zugriff auf externe Werkzeuge (LibreHardwareMonitor, PawnIO, smartctl, Add-CachedType).
  * **Härtung von Get-FileSha256:** Vollständige Pfadnormalisierung via [System.IO.Path]::GetFullPath und robuste Fehlerabfangung bei Datei-Hashprüfungen.
* **Fix: Verlinkung im Dashboard auf Diagnoseberichte:**
  * **Relative Pfadauflösung:** Verlinkungen aus Dashboard.html auf Diagnosebericht.html werden relativ zu Dashboard.html aufgelöst (<Lauf-Ordner>/Diagnosebericht.html) mit standardkonformen Vorwärtsslashes (/), wodurch ERR_FILE_NOT_FOUND und doppelte Berichte/-Präfixe behoben werden.
* **Optimierte Datenpflege & Bereinigung alter/verwaister Einträge:**
  * **Archivierung verwaister DB-Einträge:** Datenbankeinträge ohne zugehörigen Berichtsordner oder mit beschädigter/leerer (0 Byte) JSON-Datei werden sauber nach Archiv\Verwaist\Datenbank bzw. Archiv\Beschaedigt\Datenbank verschoben.
  * **Gründliche Laufzeit-Bereinigung:** Verwaiste Locks (*.lock), abgebrochene Checkpoints (checkpoint*.json), temporäre Dateien (*.tmp) und Signaldaten im Verzeichnis Laufzeit/ werden rückstandslos bereinigt.
  * **Detaillierte Statusmeldung & Protokoll:** Berechnung und Anzeige des freigegebenen Speicherplatzes in Megabyte in der Benutzeroberfläche und im Protokoll Archiv\Datenpflege.log.
* **Oberflächen-Bereinigung & optimiertes Layout:**
  * **Redundante Benchmark-Checkliste entfernt:** Die veraltete Kontrollkästchen-Liste ("Bereits geprüfte Systeme einblenden") auf der Benchmark-Startseite wurde entfernt; Vergleichsaufgaben werden vollständig durch das moderne Dashboard und die Vergleichsdatenbank abgedeckt.
  * **Kategorisierte Optionen in Fluent-Karten:** Diagnose-Optionen auf der Startseite in zwei übersichtliche Karten gegliedert ("Zusatzwerkzeuge & Speicherdiagnose" und "Prüfzeiträume & Schwellenwerte").
  * **Vergrößerte Startfenstergröße:** Auf 1320x860 erweitert, um störende Scrollbalken beim ersten Starten der Anwendung vollständig zu vermeiden.
* **Vollständige Versionshistorie (1.0 bis 1.8):**
  * Lückenlose Dokumentation aller 9 Ur-Versionen von 1.0 bis 1.8 mit konkreten Changelogs und Neuerungen nachgepflegt.

## v3.51 (07.10.2026)

* **Dashboard-Berichtsverlinkung & Schnellzugriff:**
  * **Interaktive Berichtsaufrufe:** Im Multi-System-Dashboard (`Dashboard.html`) führen Klicks auf beliebige Systemnamen in Spezifikationstabelle, Profil-Cards, Benchmark-Matrix und Befundübersicht direkt zum zugehörigen Diagnosebericht (`Diagnosebericht.html`).
  * **Berichts-Buttons & Spalte:** Tabellenköpfe und eine dedizierte Diagnosebericht-Zeile bieten direkte `📄 Bericht`-Links zur schnellen Detailanalyse.
  * **Neuer 'Bericht öffnen'-Button in der Benutzeroberfläche:** Auf der Vergleichsseite (`BuildDbPage`) steht neben dem Dashboard-Button nun ein direkter Button "Bericht öffnen" zur Verfügung, der den vollständigen HTML-Bericht des ausgewählten Systems mit einem Klick im Browser öffnet.
* **Referenzsystem-Deduplizierung:**
  * **Keine doppelten Einträge:** Referenzprofile (`Desktop_HighEnd`, `Notebook_Mittelklasse`, etc.) werden beim Multi-System-Export (`Export-BenchDashboardData`) aus der Datenbankliste herausgefiltert und erscheinen im Dashboard ausschließlich einmalig in der dedizierten Sektion "Referenzprofile (Eingebettet)" mit Stern-Symbol (`⭐`).
  * **Robuste Eindeutigkeit im JavaScript:** Clientseitiges deduplizierendes System-Mapping verhindert doppelte Rendering-Einträge in Dropdowns und Kacheln.
* **Persistente Netzlaufwerk- & NAS-Verbindung:**
  * **Redundante Speicherung:** Die Netzwerkkonfiguration (`Netzwerk.json`) wird redundant an allen lokalen Speicherorten (neben der Minibench-Executable, im Datenordner, im Benutzer-Dokumentenverzeichnis und in AppData) gesichert.
  * **Automatischer Reconnect:** Beim Start von Minibench stellt `Resolve-DataDir` nicht verbundene oder abgelaufene UNC-Freigaben automatisch im Hintergrund über `net use /persistent:yes` wieder her, sodass Berichte und Datenbanken ohne manuelles erneutes Verbinden sofort bereitstehen.
  * **Dynamische Pfadaktualisierung:** Die Benutzeroberfläche aktualisiert die Pfadanzeige nach dem Wechsel des Datenordners live ohne Neustart.

## v3.5 (06.10.2026)

* **Fehlerbehebung & Optimierungs-Presets:**
  * **Entkopplung der Taskleisten-Gruppierung:** `TaskleisteGruppieren` in `Katalog.psd1` bereinigt; steuert nun ausschließlich die reine Gruppierung (`TaskbarGlomLevel`) ohne ungewollte Nebeneffekte.
  * **Eigenständiger Eintrag 'Taskleiste: Task beenden per Rechtsklick':** `TaskbarEndTask` als eigenständiger Eintrag mit Vorlagen `MSE` in Kategorie `Explorer, Taskleiste und Start` definiert; setzt `TaskbarEndTask` = 1 in `TaskbarDeveloperSettings` und `Advanced` (Gegenbefehl: 0).
  * **Schlankes Minimal-Preset als Standardvorauswahl:** Preset **Minimal** (`M`) auf ein kompaktes Basispaket gestrafft (Minimaltelemetrie, Fehlerberichte, Werbe-ID, Speicheroptimierung, TaskbarEndTask). `BuildOptPage()` wählt nun beim Start standardmäßig `ApplyOptPreset("M")` vor. "Leos Empfehlung" (`S`) bleibt das umfassende Standardpaket.
* **Erweitertes responsives Fensterlayout:**
  * **Größere Startabmessungen:** Responsiv vergrößert auf `Math.Min(UI.S(1220), (int)(WorkingArea.Width * 0.95))` Breite und `Math.Min(UI.S(740), (int)(WorkingArea.Height * 0.92))` Höhe (`MinimumSize`: `880x560`). Bietet sofort mehr Raum für Tabellen, Kacheln und Vergleiche, ohne auf 1080p-Notebooks mit Skalierung überzulaufen.
* **Modul 'Tools': Softwarepakete installieren (winget):**
  * **Integrierter Software-Paket-Manager:** Neuer Abschnitt auf der Tools-Seite zur einfachen 1-Klick-Installation populärer Standardsoftware via Windows Package Manager (`winget.exe`).
  * **Paketauswahl:** Web-Browser (Google Chrome, Mozilla Firefox, Opera), Gaming & Chat (Steam, Discord) und Produktivität (Notepad++, ONLYOFFICE Desktop Editors, 7-Zip, VLC Media Player).
  * **Hintergrundprüfung & asynchroner Installer:** Prüft beim Start im Hintergrund auf Vorhandensein von `winget.exe` (mit klarer Hinweismeldung und deaktiviertem Button, falls nicht vorhanden). Ausführung läuft asynchron mit Live-Fortschritt im UI-Status.
* **NAS- & Netzlaufwerk-Integration:**
  * **Konfigurierbare Netzlaufwerke:** Unterstützung für `Minibench-Daten\Netzwerk.json` (`NasPfad` / `NetzwerkPfad`) in `Resolve-DataDir`.
  * **Robuster lokaler Fallback:** Automatische Prüfung auf Schreibrechte (`Test-WritableDir`). Ist das NAS nicht erreichbar oder schreibgeschützt, fällt Minibench automatisch und ohne Fehlerdialog auf den lokalen Datenordner zurück.
  * **1-Klick-Einbindung im UI:** Neuer Dialog "Netzlaufwerk / NAS verbinden" auf der Tools- und Datenbankseite mit Eingabe für UNC-Pfade, optionalen Anmeldedaten (`net use`), Verbindungstest und direktem Live-Umschalten des Datenverzeichnisses.
* **Interaktive Berichtsdiagramme & Befunde-Bereinigung:**
  * **Hoverbare Sensor-Diagramme:** Sensor-Charts (Temperatur, Takt, Leistung, Auslastung) im Hauptbericht (`Diagnosebericht.html`) mit derselben interaktiven Hover-Tooltip-Logik wie im Dashboard: Beim Bewegen der Maus über Kurven oder Messpunkte werden Zeitstempel, °C, GHz und Watt an genau diesem Punkt angezeigt (100 % inline ohne externe Bibliotheken).
  * **Bereinigte Befunde-Ansicht:** Entfernung des Text-Suchfelds zugunsten aufgeräumter, praktischer Filter-Badges (Alle, Kritisch, Warnung, Info) und klarer Trefferzählung.

## v3.4 (06.10.2026)

* **Neues Modul 'Tools' in der Benutzeroberfläche:**
  * **Navigationspunkt 'Tools':** Neuer Menüpunkt in der linken Navigation direkt unter 'Optimierung' und vor 'Sensoren' mit modernem Fluent-Design (`UI.IcoTools`).
  * **Portable Werkzeuge:** Integrierte Erkennung und Starter für Revo Uninstaller Portable (`Minibench-Daten\Tools\RevoUninstaller\*.exe`), MiniTool Partition Wizard (`Minibench-Daten\Tools\PartitionWizard\*.exe`) und WizTree Portable (`Minibench-Daten\Tools\WizTree\*.exe`) inklusive Prüfung auf lokale Systeminstallationen, 'Starten (Admin)'-Schaltflächen und Schnell-Links zum Herunterladen bzw. Ordner öffnen.
  * **System-Shortcuts & Schnellstarter:**
    * 'Ins BIOS/UEFI neu starten': Führt nach Bestätigung `shutdown.exe /r /fw /t 0` aus; prüft vorab über native Win32 `GetFirmwareType` und Registry auf UEFI-Unterstützung.
    * Schnellzugriff auf native Windows-Konsolen: Datenträgerverwaltung (`diskmgmt.msc`), Geräte-Manager (`devmgmt.msc`) und Zuverlässigkeitsverlauf (`perfmon /rel`).
  * **Volle Dark-Mode- und Tooltip-Unterstützung:** Nahtlose optische Integration im Hell- und Dunkelmodus (`UI.IsDark`) sowie konsequente Tooltips (`Tip(...)`) auf allen Steuerelementen.
* **Optimierungen: 'Leos Empfehlung' erweitert:**
  * **Task beenden per Rechtsklick (`TaskbarEndTask`):** Neue Optimierung in der Kategorie `Bedienung` für Windows 11 in den Vorlagen M, S (Leos Empfehlung) und E. Ermöglicht das sofortige Beenden hängender Programme direkt über das Kontextmenü der Taskleiste (`HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings` und `HKCU:\...\Advanced`, DWord 1). Vollständig dokumentiert und rückgängig machbar.
  * **UEFI-Neustart Desktop-Shortcut (`UefiNeustart`):** Desktop-Kontextmenüeintrag für den direkten Neustart in die Firmware in den Vorlagen S und E mit Protokollierung und Wiederherstellungsoption.
* **Interaktiver Hauptbericht (Diagnosebericht.html) & Designangleichung:**
  * **Abschnitt-Navigation:** Schnelle Reiter-Leiste am Kopf des Berichts zur gezielten Ansicht von Systemübersicht, Benchmark, Befunden, Hardware oder Sensoren.
  * **Live-Suche & Stufen-Filter für Befunde:** Sofortiges Durchsuchen von Befunden nach Text und Filtern nach Schweregraden (Kritisch, Warnung, Info) mit dynamischer Trefferzählung.
  * **Interaktive Sensor-Chart Tooltips:** Pure Vanilla JavaScript Hover-Tooltips für Messpunkte in Takt-, Temperatur-, Rendertest- und Durchsatz-Diagrammen ohne externe Bibliotheken.
  * **Designangleichung & kräftige Farbwelt:** Synchronisierung der CSS-Farbpaletten von `Dashboard.html` und `Diagnosebericht.html` auf Basis von `Stil.ps1` mit satten Badges, klaren Kontrasten und gestochen scharfer Typografie.
  * **Direktverlinkung zum Vergleichsdashboard:** Neue Schaltfläche in der Bericht-Navigation und im Benchmark-Vergleichsbereich verlinkt direkt auf das interaktive `Dashboard.html` mit dem aktuellen PC als vorausgewähltem Basissystem (`?system=...`).
* **Hotfix & Detailkorrekturen:**
  * **Optimierungsauswahl 'Leos Empfehlung':** `TaskbarEndTask` und `UefiNeustart` in `defaultLeoEmpfehlung` aufgenommen und Auswahllogik in der GUI abgesichert, sodass die Option bei Wahl des Presets zuverlässig markiert wird.
  * **Symbol für Modul 'Tools':** Eigenes Segoe MDL2-Symbol `\uE71D` (AllApps, 4 Kacheln) implementiert und an die linke Navigation übergeben (eindeutige Unterscheidung von der Wartungsseite `\uE90F`).
  * **System-Vorauswahl im Dashboard:** `Dashboard.html` wertet URL-Parameter `?system=` bzw. Hash-Fragmente aus und schaltet das Basissystem automatisch auf den angegebenen PC um.

## v3.32 (06.10.2026)

* **Dark-Mode-Feinschliff für die WinForms-Oberfläche:**
  * **Native dunkle Win32-Scrollbars:** Aktivierung des Windows-eigenen Fluent-Dunkelmodus für Scrollbars über `SetPreferredAppMode(2)` (ForceDark) und `SetWindowTheme(hWnd, "DarkMode_Explorer", null)`. Beseitigt grell-weiße Scrollbalken in Inhaltsbereichen (`content`), Navigationsleisten (`left`), `ListView`-Listen und `CheckedListBox`-Steuerelementen ohne Fremdbibliotheken oder Eingriffe ins Gesamtsystem.
  * **Eigene `DarkComboBox`-Komponente:** Ersatz der standardmäßigen WinForms-ComboBoxen durch eine vollständig darkmode-fähige Dropdown-Komponente mit sauber abgedunkeltem Hintergrund (`UI.Panel`), dezentem Rahmen (`UI.Line`), hochauflösend gezeichnetem Pfeilsymbol und owner-drawn Auswahlelementen im Fluent-Design.
  * **Dunkle Tabellenköpfe (`SysHeader32`):** ListView-Spaltenköpfe werden über `EnableDarkListView` im Dark Mode sauber abgedunkelt gezeichnet (`#1C1E20` mit dezentem Segmenttrenner und Beschriftung in Segoe UI Semibold), wodurch weiße Kopfzeilen in allen Tabellen entfallen.
  * **Optimierte Textkontraste & Deaktivierte Steuerelemente:** Deaktivierte Schaltflächen (wie "Entfernen") und Optionen nutzen ein eigens gezeichnetes Farbschema (`#8C919B` auf dezentem Panel-Hintergrund) anstelle des unleserlichen Windows-GDI-Schattendrucks ("schwarzer/grauer Text auf dunklem Grund"). Diagnose-Optionen schalten bei Klick im Vorgaben-Modus barrierefrei auf benutzerdefinierte Auswahl um.
* **Konsolidierung des Systemvergleichs:**
  * **Vollständige Dashboard-Ablösung:** Das interaktive Multi-System-Dashboard deckt nun alle Funktionen des älteren Vergleichssystems ab (Hardwaredaten im Direktvergleich, lückenlose Benchmark-Matrix mit Bestwert-Hervorhebung, Befunde-Gegenüberstellung und Multi-Kurven-Telemetrie).
  * **Bereinigung redundanter Pfade:** Die statische Vergleichsfunktion wurde aus der Benutzeroberfläche und der Befehlszeile nahtlos auf das interaktive Dashboard konsolidiert.
  * **Aktualisierte Vergleichsdatenbank:** Die Vergleichsseite bietet nun eine fokussierte, einheitliche primäre Aktionsschaltfläche ("Im Dashboard vergleichen") mit dynamischer Systemanzahlanzeige sowie ein angepasstes Kontextmenü.

## v3.31 (06.10.2026)

* **Multi-System-Vergleich im interaktiven Dashboard (N >= 2):**
  * Umstellung der starren 2-System-Auswahl auf flexible Multi-System-Selektion: Ein beliebiges Basissystem plus beliebig viele Vergleichssysteme über interaktive System-Chips mit Schaltflächen zur Schnellauswahl.
  * Vollständige Hardware-Spezifikationen im Direktvergleich: Übersichtstabelle aller gewählten Systeme nebeneinander (Rechnername, CPU, RAM, GPU, Datenträger, Betriebssystem, Mainboard, Installationsdatum) äquivalent zum klassischen Vergleichsbericht.
  * Vollständige Benchmark-Matrix: Synoptische Gegenüberstellung sämtlicher vorliegender Messwerte (CPU Single/Multi/AES/SHA/Deflate, RAM Lesen/Schreiben/Kopieren/Latenz, GPU FPS/1%-Low/0,1%-Low/Mikroruckler, Datenträger sequentiell und 4K) mit automatischer Bestwert-Hervorhebung (`👑 Bestwert`).
  * Synoptischer Befund-Vergleich: Gegenüberstellung aller Diagnose-Befunde (Kritisch, Warnungen, Hinweise) aufgeschlüsselt nach den verglichenen Systemen.
  * Interaktiver Canvas-Chart für mehrere Systeme: Umschaltbare Takt- und Temperaturkurven (Temperatur-Modus, Takt-Modus, Einzel-Detailansicht) mit Farbcodierung je System und simultanem Multi-System-Tooltip beim Überfahren mit der Maus.
* **Paralleler Betriebsmodus in der Oberfläche:**
  * Gleichberechtigte Koexistenz beider Vergleichswege in der Toolbar und im Kontextmenü der Vergleichsseite:
    * *Vergleichen (Klassisch)* erzeugt den bewährten statischen `Vergleichsbericht.html`.
    * *Interaktives Dashboard* übergibt alle angehakten Systeme an `Show-BenchDashboard` und öffnet das interaktive Dashboard mit vorausgewählten Systemen.
* **Nativer Dark Mode für die MiniBench-App (DiagGui.cs):**
  * Dynamisches Farbsystem in `DiagGui_Steuerelemente.cs` (`UI.IsDark`, `UI.SetTheme(bool dark)`): Saubere Umschaltung zwischen hellem Modus (`#F9F9FB`, `#FFFFFF`, `#1C1D1F`, `#5F6368`, `#E5E7EB`, `#161E2E`) und augenschonendem dunklem Modus (`#18191A`, `#242526`, `#F5F6F7`, `#9CA3AF`, `#3A3B3C`, `#121314`) inklusive angepasster Statusfarben und Steuerflächen.
  * Titelleisten-Umschalter: Diskreter Theme-Schalter (☀️/🌙) in der Kopfzeile neben der Versionshistorie mit Mouseover-Tooltip (`Tip`).
  * Windows DWM Immersive Dark Mode: Dynamische Umschaltung der Windows-Fensterleiste via `DwmSetWindowAttribute` (`DWMWA_USE_IMMERSIVE_DARK_MODE`).
  * Einstellungs-Persistierung: Speicherung der gewählten Theme-Präferenz in `Minibench-Daten/Einstellungen.json` mit automatischem Fallback auf das Windows-Systemdesign (`AppsUseLightTheme`).
  * Flackerfreie Neuzeichnung durch rekursive Steuerelement-Aktualisierung und Doppelpufferung.
* **Build-Prozess & Git-Automatisierung:**
  * Erweiterung von `Bauen.cmd`: Nach erfolgreichem Bau und bestandenen Tests wird das Git-Repository geprüft, Quell- und Dokumentationsdateien gestaged und ein lokaler Release-Commit formatiert erzeugt.

## v3.3 (06.10.2026)

* **Interaktives Benchmark- & Diagnose-Dashboard:**
  * Vollständig offline-fähiges HTML5-Dashboard (`Dashboard.html`) mit reinem Vanilla-JS und modularem CSS ohne externe CDN-Abhängigkeiten.
  * Neue PowerShell-Integrationsfunktionen in `src/Bericht/Bausteine_Dashboard.ps1`: `Export-BenchDashboardData` (aggregiert Datenbankläufe, Systemmetadaten, Benchmark-Keys, Disk-Werte und Telemetrie), `Get-BenchDashboardHtmlTemplate`, `New-BenchDashboardHtml` und `Export-BenchDashboardHtml`.
  * Integration in GUI und CLI: Schaltfläche *Dashboard* mit Tooltip auf der Vergleichsseite in `DiagGui_Vergleich.cs` sowie CLI-Parameter `-Dashboard` und `-DashboardExport <Pfad>`.
* **Dual-Axis Telemetrie-Visualisierung (Pure Canvas):**
  * Hochpräziser interaktiver 2-Achsen-Canvas-Chart für Takt (GHz/MHz) und CPU-Temperatur (°C) über den Lasttest-Zeitverlauf.
  * Automatische Extraktion und Dekomprimierung von `Lasttest-Verlauf.csv` aus den Berichts-Anhängen (`Anhang.zip`).
  * Visuelle Warnbalken und Markierungen bei thermischer oder leistungsbezogener Prozessordrosselung (Thermal / Power Throttling) sowie TjMax-Referenzlinie.
  * Flüssige Hover-Fadenkreuze und Tooltip-Karten an der Cursor-Position mit exakten Sensor- und Taktratenwerten.
* **Fluent 2 / Wintoys-UI & Systemvergleich:**
  * Designkonforme Umsetzung im Fluent 2-Design: Karten mit dezentem 1px-Rahmen (`#E5E7EB`), sanften Rundungen (8–10 px) und Windows 11-Akzentblau (`#0067C0`).
  * Responsiver Theme-Switch (Dark Mode `#202020` / Light Mode `#F9F9FB`) mit `localStorage`-Persistierung.
  * Interaktive Systemauswahl: Beliebiges Zielsystem aus der lokalen Datenbank gegen alle 5 integrierten Referenzsysteme (Desktop High-End, Desktop Mittelklasse, Mini-PC, Notebook Standard, Workstation Mobil).
  * Prominente Score-Kacheln für Gaming, Büro/Desktop und Workstation sowie Komponenten-Pillen mit farblicher Trendbewertung (Grün bei Zuwachs, Rot bei Abfall).
* **UI-Bereinigung & Barrierefreiheit (Navigation & Vergleichsseite):**
  * Aufgeräumte Vergleichsdatenbank: Wartungs- und Importwerkzeuge in eine obere Werkzeugleiste (`topTools`) direkt unter dem Datenbankpfad verlegt.
  * Fokussierte Haupt-Aktionsleiste am unteren Fensterrand mit 4 Kernaktionen (*Vergleichen*, *Dashboard*, *Name ändern ...*, *Entfernen*) sowie nativem Rechtsklick-Kontextmenü für alle Zeilenaktionen.
  * Navigationsleiste ohne Untertitel-Clipping: Kurzbeschreibungen von den NavItem-Buttons entfernt, um Textabschneiden bei hohen Display-Skalierungen (150 % / 200 %) zu verhindern; Standard-Fluent-Höhe von `UI.S(40)` mit zentrierten Segoe-Icons und Checkboxen; vollständige Modulbeschreibungen weiterhin als Hover-Tooltips verfügbar.
  * Fehlerbehebung Systemvergleich im Dashboard: Beseitigung einer Namenskollision bei `$idleSens` in `Export-BenchDashboardData`, strikte Typisierung von System-IDs und defensiver String-ID-Abgleich im Frontend-JavaScript.

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

## v1.8 (30.09.2026)

* **Gruppierter Benchmark und Referenz:**
  * Der Benchmark ist in vier ausklappbare Blöcke gegliedert, im Bericht und in der Oberfläche. Laufwerke stehen kompakt in einer Zeile pro Laufwerk. Neue Messungen:
  * CPU: AES-256, SHA-256, Kompression
  * RAM: Kopieren
  * GPU: PCIe-Anbindung, Grafikspeicher
  * Laufwerke: 4K schreiben

## v1.7 (29.09.2026)

* **Benchmark-Korrektur und schlankere Ausgabe:**
  * Fehler behoben, durch den nur die CPU gemessen wurde. Jeder Teil des Benchmarks läuft jetzt abgesichert für sich. Die Ausgabe ist entschlackt: Im Ordner liegen nur noch der HTML- und der Textbericht, alles andere steckt in Anhang.zip.

## v1.6 (28.09.2026)

* **Benchmark und Lasttest:**
  * Benchmark für CPU (Einzel- und Mehrkern, Takt), RAM (Lesen, Schreiben, Latenz), GPU (WinSAT) und Laufwerke (sequentiell und 4K, ohne Windows-Cache). Jeder Wert bekommt einen Index für seine Hardwareklasse und wird mit früheren Läufen verglichen. PCIe-Anbindung von Grafikkarte und NVMe wird geprüft. Lasttest mit wählbarer Dauer, Takt- und Temperaturkurve, Drosselungserkennung und Abbruchknopf.

## v1.5 (27.09.2026)

* **Kurztest und neues Design:**
  * Kurztest-Modus, der alles Langwierige überspringt. Die Oberfläche ist komplett überarbeitet, mit Kacheln, Statuskarten und Reitern, und öffnet sich im Vordergrund. Die exe fordert Administratorrechte selbst an. Dazu Korrekturen aus dem Code-Review.

## v1.4 (26.09.2026)

* **Oberfläche und HTML-Bericht:**
  * Optionale grafische Oberfläche mit Live-Befunden, Testergebnissen und Protokoll. Grafischer Endbericht als HTML mit Hell- und Dunkelmodus. Ein Build-Skript kompiliert die exe direkt auf dem Desktop, ganz ohne Download.

## v1.3 (25.09.2026)

* **Absturzsicherheit und Korrekturen:**
  * Checkpoints werden direkt auf die Platte geschrieben, damit sie auch einen Absturz überstehen. Nach einem abgebrochenen Lauf startet eine Absturzanalyse: Bluescreen-Stoppcode, Kernel-Power 41, WHEA-Fehler und der Schritt, in dem der PC ausfiel. Neue Option Absturzanalyse (-AnalyzeLastRun). Behoben wurden die Fehler aus dem ersten Praxislauf: Auswertung von SFC, Fehlalarme bei NTFS und Store-Apps, SMART-Meldung, Firmwaretyp und Konsolenkodierung.

## v1.2 (24.09.2026)

* **Kodierung:**
  * Das Skript repariert sich selbst, wenn die UTF-8-Kennung (BOM) beim Kopieren verloren geht. Hashtable-Schlüssel mit Umlauten stehen jetzt in Anführungszeichen.

## v1.1 (23.09.2026)

* **Starten und Fortschritt:**
  * Start-CMD mit Menü und eine exe als Starter. Die Administratorrechte holt sich die CMD selbst, und das Fenster bleibt bei Fehlern offen. Klare Fortschrittsbalken für den Gesamtlauf und den einzelnen Schritt.

## v1.0 (22.09.2026)

* **Grundversion:**
  * Diagnoseskript für Windows 11. Es erfasst die Hardware und das System: Firmware, TPM, BitLocker, CPU, RAM-Module, GPU, Datenträger, SMART, Akku, Netzwerk, Treiber, Updates, Sicherheit, Autostart und Software. Dazu kommen Tests: WinSAT, chkdsk-Onlinescan, DISM und SFC, Defender-Schnellscan, SMART-Langtest, RAM-Mustertest, CPU-Stabilitätstest, Netzwerk- und Energieanalyse sowie die Auswertung der Ereignisprotokolle. Der komplette Bericht landet in der Zwischenablage und als Textdatei auf dem Desktop.
