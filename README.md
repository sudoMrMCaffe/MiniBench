<div align="center">

<img src="src/Oberflaeche/Symbol.png" alt="Minibench Symbol" width="96" />

# Minibench

**Portable Diagnose-, Benchmark-, Stresstest-, Reparatur- und Optimierungs-Suite für Windows 10 & 11.**

> 💡 **Hinweis:** *Minibench* ist mein erstes **Vibe Coding**-Projekt – von der Konzeption über die native PowerShell 5.1- & C# 5-Architektur bis hin zum modernen Fluent 2-Look vollständig im interaktiven Pair-Programming mit KI entwickelt.

[![Version](https://img.shields.io/badge/Version-3.54-0284c7.svg)](CHANGELOG.md)
[![Changelog](https://img.shields.io/badge/Changelog-MD-6366f1.svg)](CHANGELOG.md)
[![Plattform](https://img.shields.io/badge/Windows-10%20%7C%2011%20(x64)-0078d4.svg)]()
[![Laufzeit](https://img.shields.io/badge/PowerShell-5.1%20%7C%20C%23%205-1e293b.svg)]()
[![Tests](https://img.shields.io/badge/Tests-760%2B%20bestanden-22c55e.svg)](tests/)
[![Vibe Coding](https://img.shields.io/badge/Built%20With-Vibe%20Coding-7c3aed.svg)]()
[![Portabel](https://img.shields.io/badge/USB-Zero--Footprint-f59e0b.svg)]()

<br/>

<a href="https://github.com/sudoMrMCaffe/MiniBench/raw/main/Aktueller%20Build/LeosMinibench.exe">
  <img src="https://img.shields.io/badge/%E2%AC%87%EF%B8%8F%20Download-LeosMinibench.exe%20(v3.54)-2563eb?style=for-the-badge&logo=windows&logoColor=white" alt="Download LeosMinibench.exe" />
</a>

<br/><br/>

<img src="Doku/Screenshots/Oberflaeche.png" alt="Leos Minibench 3.54 Oberfläche" width="850" />

<br/><br/>

<p align="center">
  <img src="Doku/Screenshots/Dashboard.png" alt="Interaktives Multi-System Dashboard" width="415" />
  &nbsp;
  <img src="Doku/Screenshots/Diagnosebericht.png" alt="Interaktiver Diagnosebericht mit Sensor-Charts" width="415" />
</p>

</div>

---

## 🚀 Schnellstart


1. **[LeosMinibench.exe herunterladen](https://github.com/sudoMrMCaffe/MiniBench/raw/main/Aktueller%20Build/LeosMinibench.exe)** (oder auf den USB-Stick kopieren).
2. Per Doppelklick als **Administrator** starten (UAC bestätigen).
3. Gewünschte Module wählen und **Start** klicken. Alle Berichte landen sauber unter `Minibench-Daten\Berichte\`.

---

## Kernmerkmale

* **100 % Portabel (Zero-Footprint):** Startet direkt vom USB-Stick ohne Installation. Hinterlässt keine Dateien auf dem geprüften PC; eine automatische Rückstandskontrolle räumt temporäre Reste am Ende ab.
* **Autarke Single-File-EXE:** Baut per `csc.exe` in eine eigenständige `LeosMinibench.exe` mit integriertem Startfenster und UAC-Rechteerhöhung (Fallback über `.cmd` oder `.ps1`).
* **Sicher & Reversibel:** Jede Systemänderung wird protokolliert und kann selektiv zurückgenommen werden. Automatischer Systemwiederherstellungspunkt vor tiefen Eingriffen.
* **KI-Diagnosedatei:** Erzeugt neben HTML-/TXT-Berichten eine anonymisierte `KI-Datei.txt` mit System-Prompt für Ursachen- und Reparaturanalysen in LLMs (Gemini, Claude, ChatGPT).
* **Interaktives HTML5-Dashboard:** 100 % offline-fähiges Fluent 2-Dashboard für flexible Multi-System-Vergleiche ($N \ge 2$) mit Hardware-Gegenüberstellung, vollständiger Benchmark-Matrix (Bestwert-Hervorhebung) und 2-Achsen Canvas-Telemetriekurven (Temperatur & Taktung) samt Drosselungsanzeige.
* **Nativer GUI Dark Mode:** Modernes Dark/Light-Theme für das WinForms-Hauptprogramm mit DWM Immersive Dark Mode in der Titelleiste, flüssigem Umschalter und optimierten Kontrasten.

---

## Module

* **Diagnose:** Vollständiges Hardware- & OS-Inventar, SMART-Werte, Akku-Verschleiß, Ereignisprotokolle, Absturzanalyse und Drosselnachweis.
* **Benchmark:** CPU (Single/Multi, Krypto, Deflate), RAM (Bandbreite & Latenz), Datenträger (NVMe/SSD/USB), Direct3D 11 GPU-Rendertest (FPS, Frametimes, Punkte) und WinSAT.
* **Lasttest:** Isolierte CPU- und RAM-Last ohne GC-Einfluss, GPU-Rendertest, thermischer Drosselnachweis und konfigurierbare Abbruchschwellen (°C).
* **Wartung & Reparatur:** SFC, DISM, Netzwerk-Reset, Windows Update Reset, Bereinigung von Caches/Komponentenspeicher und DDU-Treiberbereinigung.
* **Optimierung:** 163 native Windows-Einstellungen in 14 Kategorien, inklusive Preset *Leos Empfehlung* und Einzel-Rollback.
* **Sensoren Live & Vergleich:** Echtzeit-Monitoring von Temperatur, Takt, Lüfter und Leistung; historische Vergleichsdatenbank mit aufgeräumter Toolbar und editierbaren Systemnamen; interaktives Multi-System-Dashboard für Systemvergleiche und Lasttest-Telemetrie.

---

## Beispielberichte

Das Werkzeug erzeugt nach jedem Lauf detaillierte, interaktive HTML-Berichte mit SVG-Diagrammen:

* 📊 **[Beispiel-Dashboard (HTML)](Doku/Beispiele/Beispiel_Dashboard.html)** – Interaktives Benchmark- & Diagnose-Dashboard mit Systemvergleich gegen 5 Referenzprofile, Dual-Axis Lasttest-Telemetrie und Fluent 2 Dark/Light Mode.
* 📈 **[Beispiel-Systemvergleich (HTML)](Doku/Beispiele/Beispiel_Systemvergleich.html)** – Interaktiver Gegenüberstellungsbericht mehrerer Rechner aus der Datenbank.

---

## Für Entwickler

* **Tests ausführen:** `Testen.cmd` (über 635 Pester-Tests für Modulverträge, Risikostufen, Dashboard-Logik und AST-Syntax).
* **Programm bauen:** `Bauen.cmd` (Syntaxprüfung, Testlauf, EXE-Kompilierung und automatische Archivierung nach `Aktueller Build/`).
* **Vorgaben:** Quellcode-Änderungen nur in `src/`, UTF-8 mit BOM + CRLF, Modulverträge in `Vertrag.psd1` einhalten (Details in [AGENTS.md](AGENTS.md)).
