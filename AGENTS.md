# Leos Minibench: Arbeitsrahmen für jede neue Version
 
Dieser Rahmen gilt für jeden Chat, der an Leos Minibench weiterarbeitet. Erst lesen, dann ändern.
 
## Ordner und Aufbau
Projektordner auf ULB-PC10039: C:\Users\wad32muj\Agentenraum\PC DiagnoseBench
src                 Quelltext. Reihenfolge der Teile in src\Bauplan.txt. Kern in src\Kern, Berichte in src\Bericht,
                    Module je Ordner src\Module\<Name> mit Vertrag.psd1 (Modulvertrag) und Ablauf.ps1,
                    Oberfläche in src\Oberflaeche\DiagGui.cs (C#), Versionshistorie in src\Oberflaeche\Versionen.cs,
                    Sensoren in src\Kern\Sensoren.ps1 und Sensoren.cs, Datenpflege in src\Kern\Datenpflege.ps1.
Bauen.cmd           fügt src zu Aktueller Build\LeosMinibench.ps1 zusammen, baut .exe, schreibt Stand.txt,
                    passt README.md automatisch an die aktuelle Version und Testanzahl an, verschiebt
                    ab 2.7 den vorigen Build nach Archiv\v<alte Version> und räumt Aktueller Build\Minibench-Daten auf
                    (Datenpflege nach Archiv\Minibench-Daten).
Aktueller Build     nie von Hand ändern, entsteht bei jedem Bau neu. Inhalt kommt auf den USB-Stick (exe, ps1, cmd, Stand).
tests               Pester-5-Tests (*.Tests.ps1), Testdaten unter tests\Daten, Start über Testen.cmd.
                    In der Sandbox: pwsh -NoProfile -File tests/Sandbox_Testen.ps1 [-Files A.Tests.ps1,B.Tests.ps1]
                    (Nachbau der Pester-Befehle in tests\Sandbox\PesterNachbau.ps1; die PowerShell Gallery ist dort nicht
                    erreichbar). Mit 2.67 ergab der Nachbau dieselben Zahlen wie der frühere Lauf (519/0/4).
Doku                Änderungen_vX.Y.txt, Testmatrix_vX.Y.csv, Versionshistorie.txt, Beispiele, Läufe_vX.Y.
Archiv\vX.Y         Sicherung jeder abgelösten Version (ab 2.7 legt Bauen.cmd sie an).
Minibench-Daten     Datenordner neben der exe: Berichte, Datenbank (JSON, Format PC-Diagnose-DB/2), Tools mit
                    Manifest Tools.json (SHA-256), Cache, Laufzeit, Änderungsprotokoll, ab 2.7 Archiv (Datenpflege).
 
## Feste Vorgaben
1. Windows PowerShell 5.1 und C# 5 (Add-Type, mcs -langversion:5 zum Prüfen). Keine Installation nötig, läuft vom Stick.
2. Oberfläche und Arbeitsprozess sprechen über @@-Zeilen (Ereigniskanal). Neue Ereignisse dokumentieren.
3. Jede Systemänderung bekommt eine Risikostufe (Lesen, Ändern, Eingriff, Zerstörend) und einen Eintrag im
   Änderungsprotokoll mit Gegenbefehl, damit die Seite Änderungen sie rückgängig machen kann.
4. Keine Reste auf fremden PCs: Rückstandskontrolle am Laufende. Ab v2.4 kann der Nutzer Hilfswerkzeuge je Gerät behalten.
5. Fremdwerkzeuge nur portabel, frei weitergebbar und mit fester Prüfsumme im Manifest.
6. Texte in Oberfläche und Bericht auf Deutsch, sachlich, ohne Spiegelstriche als Aufzählung.
7. Messungen (Benchmark, Lasttest) laufen nie parallel zu anderer Last.
8. Ab 2.7: Jedes neue Bedienelement bekommt einen Hinweis beim Überfahren (Tip(...) in DiagGui.cs).
9. Ab 2.7: Macht eine Änderung Lasttestergebnisse unvergleichbar, $script:MessreiheAb in Kern\Datenpflege.ps1 anheben.
   Betrifft eine Änderung Benchmarkwerte, vorher mit Leonardo klären, ob ältere Läufe ins Archiv sollen (2.7: nein,
   das Rechenwerk des Benchmarks ist seit 2.6 unverändert).
10. Neue Textdateien als UTF-8 mit BOM und CRLF anlegen (Windows PowerShell 5.1 liest Dateien ohne BOM als ANSI).
## Vorgehen in jedem Chat
1. Zuerst lesen: dieses Dokument, claude/PC-Diagnose_v2.0_Stand.md, Doku\Änderungen der letzten Version und die
   betroffenen Teile in src. Erst danach ändern.
2. Bei zwei sinnvollen Lösungswegen kurz nachfragen, sonst begründet entscheiden.
3. Für jede neue Auswertung Pester-Tests ergänzen. Tests in der Sandbox mit tests/Sandbox_Testen.ps1 laufen lassen,
   C# mit mcs -langversion:5 prüfen (der Test in Version27.Tests.ps1 übersetzt die Oberfläche), Oberfläche wenn nötig
   unter mono/Xvfb starten und Bildschirmfotos ansehen.
4. Vor der Übergabe Codeprüfung auf Fehler, gefundene Fehler im Abschnitt "Gefunden und behoben" der Änderungsdatei nennen.
## Abschluss jeder Version
1. Version in src\Kern\Version.ps1 erhöhen.
2. Eintrag oben in src\Oberflaeche\Versionen.cs und Doku\Versionshistorie.txt neu erzeugen (ein Test verlangt beides).
3. CHANGELOG.md um die wesentlichen Änderungen der Version ergänzen.
4. Die vorige Version sichert Bauen.cmd selbst nach Archiv\vX.Y; README.md wird von Bauen.cmd automatisch auf die gebaute Version und Testanzahl aktualisiert.
5. Doku\Änderungen_vX.Y.txt im Stil der bisherigen Dateien (Abschnitte, Grenzen, Umstieg, Quellen).
6. Doku\Testmatrix_vX.Y.csv mit Prüfpunkten für echte Hardware (Intel, AMD, Notebook, PC mit dGPU und iGPU).
7. Geänderte Dateien in den Ordner zurückschreiben, Bauen.cmd ausführen lassen (oder den Nutzer darum bitten).
8. claude/PC-Diagnose_v2.0_Stand.md im Projekt aktualisieren.
9. Roadmap-Dokument aktualisieren: https://claude.ai/code/artifact/557250c0-e59a-42d3-8cbd-b345d03eca7a
 (Tabelle "Rückmeldungen aus dem Praxistest": Status der erledigten Punkte auf Erledigt, Roadmap-Stand).
