// Versionshistorie (ab v2.7): Seite Versionen der Oberfläche und Doku\Versionshistorie.txt.
// Jede neue Version bekommt hier oben einen Eintrag (ein Test prüft, dass es einen für $ScriptVersion gibt).
// Einzelheiten stehen in Doku\Änderungen_vX.Y.txt. Für 1.0 bis 2.1 gibt es keine Änderungsdateien mehr; die Einträge
// nennen nur, was im Quelltext und in den Änderungen zu 2.2 belegt ist.
public static class Versionshistorie
{
    public class Eintrag
    {
        public string Version, Datum, Titel, Text;
        public Eintrag(string version, string datum, string titel, string text) { Version = version; Datum = datum; Titel = titel; Text = text; }
    }

    public static readonly Eintrag[] Liste = new Eintrag[] {
        new Eintrag("3.31", "06.10.2026", "Multi-System-Vergleich im Dashboard (N >= 2), nativer WinForms Dark Mode & Build-Synchronisation",
            "Multi-System-Vergleich im Dashboard: Beliebige Anzahl von Systemen (N >= 2) mit dynamischer Auswahl, direkter Hardware-Gegenüberstellung, vollständiger Benchmark-Matrix aller Metriken (inkl. Bestwert-Hervorhebung), synoptischem Befundvergleich und mehrfarbigem Canvas-Chartvergleich für Takt und Temperatur. " +
            "Paralleler Betriebsmodus in der Oberfläche: Klassischer statischer Vergleichsbericht und interaktives Multi-System-Dashboard stehen in Toolbar und Kontextmenü gleichberechtigt zur Verfügung. " +
            "Nativer GUI Dark Mode: Vollständig integriertes dynamisches Theme-System (Hell/Dunkel) für die WinForms-Oberfläche mit schnellem Umschalter in der Titelleiste, DWM Immersive Dark Mode für die Titelleiste und dauerhafter Speicherung in Einstellungen.json (Fallback: Windows-Systemdesign). " +
            "Build- und Git-Synchronisation: Bauen.cmd synchronisiert und committet Quelltexte und Dokumentation nach erfolgreichem Bau und bestandenen Tests automatisch lokal in Git."),
        new Eintrag("3.3", "06.10.2026", "Interaktives Benchmark- & Diagnose-Dashboard, Lasttest-Telemetrie-Visualisierung, Fluent 2-Design und Dark Mode",
            "Eigenständiges HTML5-Dashboard: Vollständig offline-fähiges, interaktives Analyse- und Vergleichs-Dashboard mit Export-Funktion (Export-BenchDashboardData, New-BenchDashboardHtml) und Direktaufruf aus der Vergleichsseite sowie per CLI (-Dashboard). " +
            "Dual-Axis Telemetrie-Visualisierung: Interaktiver HTML5-Canvas-Chart für Takt (GHz/MHz) und Temperatur (°C) über den Lasttestverlauf mit TjMax-Referenzlinie, dynamischen Drosselungs-Markierungen (Thermal/Power Throttling) und Cursor-Tooltips. " +
            "Fluent 2 / Wintoys-UI & Theming: Kachel- und Kartendesign im Windows 11 Fluent 2-Look, interaktiver Dark/Light-Mode Switch mit Zustandsspeicherung in localStorage. " +
            "Umfassende Vergleichsmetriken: Live-Gegenüberstellung gegen alle fünf eingebetteten Referenzprofile mit Gaming-, Büro- und Workstation-Scores sowie Differenz-Pillen für CPU, RAM, GPU und Datenträger."),
        new Eintrag("3.2", "06.10.2026", "Fluent 2 / Wintoys-Look, Windows 11 DWM-Rundungen, Segoe-Icons und responsive Notebook-Skalierung",
            "Fluent 2-Designsystem: Modernes helles Farbschema (#F9F9FB Hintergrund, weiße Karten mit feinem 1px-Rahmen #E5E7EB, Windows 11-Akzentblau #0067C0 und pastellfarbene Status-Badges). " +
            "Moderne Steuerelemente: Eigener ToggleSwitch im Windows 11-Pillendesign mit animiertem Schieber und barrierefreiem Fokus; FluentCard-Komponente für modulare Optionen mit Segoe-Icons und integrierten Schaltern. " +
            "Modul-Navigation: Neugestaltetes NavItem im Windows 11-Sidebar-Stil mit 6 px Eckenrundung, aktivem 3 px-Akzentbalken und gestochen scharfen Segoe-Symbolen (Segoe Fluent Icons / MDL2 Assets). " +
            "DWM-Integration: Echte Windows 11-Fensterabrundung über DWMWA_WINDOW_CORNER_PREFERENCE (DWMWCP_ROUND), PerMonitorV2 DPI-Awareness ohne veraltetes SetProcessDPIAware. " +
            "Zentraler DPI-Helper & Notebook-Sicherheit: Vollständige Skalierung über UI.S(...) und UI.SF(...), dynamische Fenstergröße anhand des Arbeitsbereichs (WorkingArea) gegen Überlauf auf 1080p-Notebooks mit 150 % Skalierung."),
        new Eintrag("3.1", "05.10.2026", "Bugfix-Release: Vergleichsseite, eingebettete Referenzdaten, CPU-Benchmark und Grafiktest auf Einsteiger-GPUs",
            "Vergleichsseite: Fehlerbehebung beim Einlesen der Systemdatenbank und Logging im JSON-Parser (DbEntry.Load), sodass Systeme zuverlässig angezeigt werden. " +
            "Eingebettete Referenzdaten: Fünf anonyme Referenzprofile (Desktop High-End bis Notebook Standard) direkt im Skript eingebettet und bei leerer Datenbank automatisch entpackt. " +
            "Prozessor-Benchmark: Behebung der CPU-Leistungsregression durch verbindliche Ausführung unter Windows PowerShell 5.1 ohne JIT- und Sensor-Overhead. " +
            "Grafik-Benchmark: Robuste Bildzeit- und Perzentil-Erfassung bei niedrigen Bildraten (Intel UHD Graphics auf Notebooks), Ausfallschutz für Hybrid-Grafik und zusätzliche Feature-Level."),
        new Eintrag("3.0", "05.10.2026", "Dual-Runtime (PowerShell 7 / 5.1), sicheres Schritt-Überspringen, Frametime-Latenzen (0,1 % Low & Mikroruckler), eingebettete Referenzen und Tabellenoptik",
            "Dual-Runtime-Unterstützung: Automatische Bevorzugung von PowerShell 7 (pwsh.exe) für maximale Geschwindigkeit mit nahtlosem Fallback auf Windows PowerShell 5.1. " +
            "Sicheres Überspringen langwieriger Einzelschritte mit dynamischer Freigabe (SKIP_ALLOWED) und sauberem Abbruch von Hintergrundjobs ohne Skriptfehler. " +
            "Erweiterte Frametime-Analyse im Rendertest: Erfassung von 0,1 %-Low FPS und Mikroruckler-Anteil (Frames über 50 ms) in Messwerten, Kurven und Berichten. " +
            "Fünf eingebettete Referenzprofile (Desktop High-End bis Notebook Standard) direkt im Build für sofortige Vergleiche ohne externe Dateien, Standard-Referenz Desktop Mittelklasse. " +
            "Bereinigte Benchmark-Darstellung im HTML-Bericht mit bewährter Detailtabellen-Optik unter Beibehaltung des Gesamtleistungs-Banners und der Profilkarten."),
        new Eintrag("2.95", "05.10.2026", "Anonyme Vergleichsdaten, Gesamtleistungs-Banner, UserBenchmark-Profile, Minidump Crash Inspector, Schritt überspringen",
            "Feste Einbindung von fünf anonymisierten, bereinigten Referenzsystemen von Desktop High-End bis Notebook Standard für sofortige Vergleichbarkeit ab dem ersten Start. " +
            "Gesamtleistungs-Banner im Bericht-Header mit prozentualer Gesamtbewertung zur Referenz. " +
            "Benchmark-Darstellung im UserBenchmark-Stil: Drei gewichtete Nutzungsprofile (Gaming, Büro/Desktop, Workstation), prominente Komponenten-Köpfe und modernes Spalten-Layout für Messgrößen. " +
            "Modul Wartung mit angepasster Standardauswahl für risikoarme Bereinigungen und Schnellwahlschaltern über der Aufgabenliste. " +
            "Neue Schaltfläche Diesen Schritt überspringen in der Laufansicht mit Ereignis @@SCHRITT_UEBERSPRINGEN. " +
            "Minidump Crash Inspector mit nativer Binäranalyse von Windows-Absturzabbildern (.dmp), Bugcheck-Erkennung und Handlungsempfehlungen. " +
            "Grafiktreiber-Gesundheitscheck auf Microsoft Basic Display Adapter, veraltete Treiber (ab 18 Monate) und Treiberabstürze (Event 4101). " +
            "Durchlaufzeit-Optimierung durch Zwischenspeicherung statischer WMI- und CIM-Systemabfragen."),
        new Eintrag("2.9", "05.10.2026", "Phasen 0 und 1: ARM64, High-DPI, Modularisierung, Wartung, Gesamtbild und Vergleichsseite",
            "Hardware-Erkennung mit ARM64-Erkennung und Warnhinweis für ARM64-Systeme im Bericht. " +
            "High-DPI-Optimierung mit Per-Monitor V2 DPI-Awareness im Anwendungsmanifest für gestochen scharfe Anzeige bei 150 % bis 225 % Skalierung. " +
            "Modularisierung der C#-Oberfläche in übersichtliche Teilklassen (Steuerelemente, Modelle, Vergleich, Seiten). " +
            "Modul Reparatur in Wartung umbenannt mit 22 Wartungsschritten, Bereinigung aus Optimierung überführt und Redundanzen im Katalog bereinigt. " +
            "Neues Voreinstellungs-Preset Leos Empfehlung als Standard aktiv. " +
            "Neugewichtung im Gesamtbild: Prozessor und Grafik erhalten doppeltes Gewicht, der GPU-Rendertest (FPS) dreifaches Gewicht gegenüber Durchsatzwerten. " +
            "Vergleichsseite: System-Anzeigename editierbar und Vergleichsdatenbank nach Spalten sortierbar."),
        new Eintrag("2.8", "03.10.2026", "Modul Optimierung, Sensoren ohne LibreHardwareMonitor",
            "Neues Modul Optimierung: alle Einstellungen des Windows Optimisation Pack, seiner Sophia-Konfiguration und der O&O-Auswahl als 163 einzelne Einträge in 14 Kategorien, mit Vorlagen Minimal, Standard und Erweitert, Zustandsprüfung, Wiederherstellungspunkt und Rückgängig je Einstellung. Sophia Script und O&O ShutUp10++ laufen nicht mehr; DDU und NVIDIA Profile Inspector sind optionale Werkzeuge mit Prüfsumme. " +
            "Ohne LibreHardwareMonitor liefern Grafiktreiber und Windows GPU-Temperatur, Takt, Lüfter, Auslastung und, wo vorhanden, die CPU-Leistung; Bericht und Oberfläche nennen den wahren Grund fehlender Werte und bieten das Holen an. " +
            "Kurven ohne überlappende Beschriftungen, Unterbrechungen im Benchmark ohne WinSAT, kürzere WLAN- und Zuverlässigkeitstexte, Laufzeit mit Minuten, NVMe-Klasse ohne lesbare Anbindung geschätzt."),
        new Eintrag("2.7", "03.10.2026", "Bedienung, Sensoren im Benchmark, Datenpflege",
            "Jedes Bedienelement erklärt sich beim Überfahren mit der Maus. Der Benchmark zeichnet während aller Messungen Temperatur, Takt und Leistung auf; der Bericht zeigt sie je Abschnitt (Prozessor, Arbeitsspeicher, Grafik, Datenträger, WinSAT) mit Kurven wie nach dem Lasttest, die Laufansicht zeigt die Kurven live. " +
            "Der CPU-Stabilitätstest der Diagnose entfällt, das Modul Lasttest prüft die CPU gründlicher. Neue Seite Versionen mit dieser Historie. " +
            "Die Datenpflege verschiebt Lasttests vor v2.67, abgebrochene Läufe ohne Bericht und kurze Läufe ins Archiv, beim Start von selbst und über Aufräumen auf der Seite Vergleichsdatenbank. Bauen.cmd legt den vorigen Build unter Archiv\\v<Version> ab."),
        new Eintrag("2.67", "03.10.2026", "Gleichmäßige CPU-Last im eigenen Prozess",
            "CPU- und RAM-Last laufen in einem eigenen PowerShell-Prozess ohne Speicherbereinigung; die Lastschleifen kommen ohne Aufrufe aus (Sinus als Polynom). Ursache der ungleichmäßigen Last war Math.Sin in der Rechenschleife: Die Speicherbereinigung konnte die Threads nicht anhalten. " +
            "Lasttestergebnisse älterer Versionen (Rechendurchläufe, Unterbrechungen) sind damit nicht vergleichbar; das Rechenwerk des Benchmarks blieb gleich."),
        new Eintrag("2.66", "03.10.2026", "Unterbrechungen messen, Sensoren robuster",
            "Messung von Unterbrechungen über 50 ms mit den Speicherbereinigungen je Generation in Lasttest, CPU-Test und Benchmark. Sensoren überstehen verspätete Abfragen (letzte Werte bis 10 s, Ausfall erst nach 30 s), Datenträger werden in einem eigenen Thread gelesen. KI-Auftrag mit Klickpfad und fertigen PowerShell-Befehlen. Keine Rückfrage mehr vor dem Grafik-Lasttest."),
        new Eintrag("2.65", "02.10.2026", "Praxistest auf ULB-PC und TORRENT",
            "GPU-Sensorwerte wieder vollständig, RAM-Test neben der CPU-Last mit niedriger Priorität, flüssige Vorschau des Rendertests, Warnung bei einer Bildratengrenze, Auswahl der Grafikeinheit, Lasttest ab 2 Minuten. Datenträger- und Grafiklast abgesichert, Referenz nur noch über den Haken, Zuverlässigkeit vorn im Bericht, Voreinstellungen zum Weitergeben, kürzere Texte."),
        new Eintrag("2.6", "02.10.2026", "Rendertest, schneller Modus, schneller Start",
            "Fasst die geplanten Versionen 2.5 und 2.6 zusammen (eine 2.5 gibt es nicht). Lasttest läuft eigenständig und liefert immer ein Ergebnis. Eigener Rendertest mit Direct3D 11 auf jeder Grafikeinheit. Schneller Modus mit parallelen Prüfungen. Startfenster sofort, Skript und Arbeitsordner im lokalen TEMP, deutlich weniger Schreibzugriffe auf den Stick (Anhang.zip). Programmsymbol blaues L."),
        new Eintrag("2.4", "02.10.2026", "Praxistest vom 01.10.2026",
            "Kein leerer Bericht bei einzelnen Modulen, CPU-Takt wie im Task-Manager (PDH), Grenzwerte und unplausible Sensorwerte erkannt, Grafikkarte und Prozessorgrafik getrennt, WinSAT bei Hybridgrafik auf der Grafikkarte, KI-Datei mit Gewichtungsregeln, Akkubericht, Standby-Sperre während des Laufs, SMART-Langtest höchstens 120 Minuten, Hilfswerkzeuge je Gerät behalten."),
        new Eintrag("2.3", "01.10.2026", "Sensoren",
            "LibreHardwareMonitor portabel mit festen Prüfsummen, Treiber PawnIO nur nach Rückfrage und nur vorübergehend, Ersatzquellen (Windows, ACPI, nvidia-smi). Seite Sensoren live, Lasttest mit Kurven, Drosselnachweis und Abbruchschwelle, Sensoren als Momentaufnahme in der Diagnose."),
        new Eintrag("2.2", "01.10.2026", "Neues Fundament",
            "Quelltext in Teilen (src) mit Bauen.cmd, Modulvertrag je Modul, Risikostufen (Lesen, Ändern, Eingriff, Zerstörend), Änderungsprotokoll mit Rückgängig, Werkzeug-Manifest mit SHA-256, Datenbankformat 2 mit Geräteidentität, Pester-Tests und Testmatrix. Bedienung, Berichte und Ablage blieben wie in 2.1."),
        new Eintrag("2.0 bis 2.1", "bis 01.10.2026", "Leos Minibench",
            "Neuer Name Leos Minibench, Start als LeosMinibench.exe vom Stick, Datenordner Minibench-Daten neben der exe (ein Ordner PC-Diagnose-Daten wird übernommen). Oberfläche mit den Modulen Diagnose, Benchmark, Lasttest und Reparatur, Vergleichsdatenbank (Format 1), HTML- und Textbericht, KI-Datei. smartctl lag im Tools-Ordner noch ohne Manifest. Stand 2.1 ist die Grundlage, die 2.2 in Teile zerlegt hat."),
        new Eintrag("1.0 bis 1.8", "bis 30.09.2026", "PC-Diagnose",
            "Diagnose- und Benchmark-Skript unter dem Namen PC-Diagnose, Ausgabe in Ordnern PC-Diagnose_<PC> mit Diagnosebericht und Benchmark.csv. Aus Läufen mit 1.8 vom 30.09.2026 stammen die ersten Einträge der Vergleichsdatenbank (TORRENT, AlexPC, LizPC); die Werte von TORRENT dienten bis 2.6 als eingebaute Referenz. Einzelne Stände 1.0 bis 1.7 sind nicht mehr dokumentiert.")
    };
}
