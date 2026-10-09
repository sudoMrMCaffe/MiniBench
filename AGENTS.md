# Leos Minibench: Arbeitsrahmen für jede neue Version

Gilt für jeden Agenten, der an Leos Minibench arbeitet (Claude, Antigravity). Erst lesen, dann ändern.
Den aktuellen Stand, offene Befunde und Fallstricke beschreibt Doku\Projektstand.md. Wer eine Version abschließt,
aktualisiert diese Datei, damit der nächste Agent dort weitermachen kann.

## Ordner und Aufbau
Projektordner auf ULB-PC10039: C:\Users\wad32muj\Agentenraum\PC DiagnoseBench
src                 Quelltext. Reihenfolge der Teile in src\Bauplan.txt. Kern in src\Kern, Berichte in src\Bericht,
                    Module je Ordner src\Module\<Name> mit Vertrag.psd1 (Modulvertrag) und Ablauf.ps1,
                    Oberfläche in src\Oberflaeche\DiagGui*.cs (C#, Teile in der Reihenfolge aus Oberflaeche.ps1),
                    Versionshistorie in src\Oberflaeche\Versionen.cs, Sensoren in src\Kern\Sensoren.ps1 und .cs,
                    Datenpflege in src\Kern\Datenpflege.ps1, Softwarepakete (winget) in src\Kern\Softwarepakete.ps1.
Bauen.cmd           fügt src zu Aktueller Build\LeosMinibench.ps1 zusammen, führt die Tests aus, baut die .exe, schreibt
                    Stand.txt, passt README.md an (Version, Testanzahl), verschiebt den vorigen Build nach
                    Archiv\v<alte Version>, räumt Aktueller Build\Minibench-Daten auf und committet nach bestandenen
                    Tests lokal (Nachricht aus Versionen.cs). Bauen.cmd ohnetests baut ohne Tests und ohne Commit.
Aktueller Build     nie von Hand ändern, entsteht bei jedem Bau neu. Inhalt kommt auf den USB-Stick.
tests               Pester-Tests nach Fachgebieten (keine Dateien je Version): Ablauf, Aenderungen, Aufbau, Auswertung,
                    Bericht, Datenbank, Lauf (Gesamtläufe, nur mit -Gesamtlauf), Messung, Modulvertrag, Oberflaeche,
                    Optimierung, Praxistest, Release, Risiko, Sensoren, Werkzeuge. Testdaten unter tests\Daten.
                    Start: Testen.cmd, einzelne Dateien: Testen.cmd -Datei Oberflaeche,Release.
                    Auf ULB-PC10039 läuft Pester 6.2 (Benutzerprofil); die Tests müssen mit Pester 5 und 6 laufen.
                    Die Oberfläche wird je Testlauf einmal übersetzt (Get-GuiUebersetzung in tests\Hilfen.ps1) und mit
                    tests\Daten\Oberflaeche\GuiSelbsttest.cs geprüft; neue Verhaltensprüfungen der Oberfläche dort.
                    Linux-Sandbox (Claude): pwsh -NoProfile -File tests/Sandbox_Testen.ps1 [-Files A.Tests.ps1,...] mit
                    dem Pester-Nachbau tests\Sandbox\PesterNachbau.ps1 (verhält sich bei Mock wie Pester 6), mcs/mono.
Doku                Änderungen_vX.Y.txt, Versionshistorie.txt, Projektstand.md, Beispiele, Screenshots.
Archiv\vX.Y         Sicherung jeder abgelösten Version (legt Bauen.cmd an).
Minibench-Daten     Datenordner neben der exe: Berichte, Datenbank (JSON, PC-Diagnose-DB/2), Tools mit Manifest
                    Tools.json (SHA-256), Cache, Laufzeit, Änderungen (Änderungsprotokoll), Archiv. Berichte und Datenbank
                    können auf ein NAS (Netzwerk.json); Cache, Tools und Laufzeit bleiben lokal.

## Feste Vorgaben
1. Windows PowerShell 5.1 und C# 5 (Add-Type, mcs -langversion:5 zum Prüfen). Keine Installation nötig, läuft vom Stick.
2. Oberfläche und Arbeitsprozess sprechen über @@-Zeilen (Ereigniskanal). Neue Ereignisse dokumentieren und in der
   Oberfläche auswerten (Aufbau.Tests.ps1 prüft, dass jede gesendete Art ausgewertet wird).
3. Jede Systemänderung bekommt eine Risikostufe (Lesen, Ändern, Eingriff, Zerstörend) und einen Eintrag im
   Änderungsprotokoll mit Gegenbefehl, damit die Seite Änderungen sie rückgängig machen kann. Das gilt auch für
   Installationen (winget), Netzlaufwerke und Werkzeugstarts aus der Oberfläche.
4. Keine Reste auf fremden PCs: Rückstandskontrolle am Laufende. Der Nutzer kann Hilfswerkzeuge je Gerät behalten.
5. Fremdwerkzeuge nur portabel, frei weitergebbar und mit fester Prüfsumme im Manifest.
6. Texte in Oberfläche und Bericht auf Deutsch, sachlich, ohne Spiegelstriche als Aufzählung, ohne Werbesprache und
   ohne Emojis.
7. Messungen (Benchmark, Lasttest) laufen nie parallel zu anderer Last.
8. Jedes neue Bedienelement bekommt einen Hinweis beim Überfahren (Tip(...)); Oberflaeche.Tests.ps1 prüft das.
9. Macht eine Änderung Lasttestergebnisse unvergleichbar, $script:MessreiheAb in Kern\Datenpflege.ps1 anheben.
   Betrifft eine Änderung Benchmarkwerte, vorher mit Leonardo klären, ob ältere Läufe ins Archiv sollen.
10. Neue Textdateien als UTF-8 mit BOM und CRLF anlegen (Windows PowerShell 5.1 liest Dateien ohne BOM als ANSI).
    Ausnahme: .cmd-Dateien ohne BOM (cmd.exe liest die BOM als Zeichen der ersten Zeile).
11. Berichte und Dashboard zeigen nur gemessene Werte; fehlen Messwerte, steht das da. Nichts synthetisieren.
12. Werte aus Datenbank, WMI oder Dateinamen in HTML und JavaScript immer maskieren.
13. Neuer Startparameter, der einen Hilfsmodus der Oberfläche startet: in den Sondermodus-Bedingungen von
    Oberflaeche.ps1, Grundgeruest.ps1, Testroutinen.ps1 und Sensoren.ps1 ausschließen und einem Modulvertrag oder der
    Liste $general in Modulvertrag.Tests.ps1 zuordnen.

## Regeln für Tests
1. Nach Fachgebiet, nicht nach Version. Verhaltenstests (Funktion im Testmodul aufrufen, Ergebnis prüfen) vor Regex auf
   den Quelltext; Regex nur für echte Verträge (Parameter, Ereignisse, Projektregeln).
2. Bekannte, noch offene Fehler als Test mit -Skip und Kommentar "bekannter Fehler, Behebung offen" festhalten; mit der
   Behebung das -Skip entfernen.
3. Pester 6: Jede Attrappe mit -ParameterFilter braucht in derselben Datei eine Vorgabe-Attrappe ohne Filter für denselben
   Befehl. Ohne passende Attrappe ruft Pester 6 nicht den echten Befehl, sondern bricht ab (Aufbau.Tests.ps1 prüft das).
4. PS 5.1: Ein einzelnes [pscustomobject] hat kein .Count. Ergebnisse von Funktionen, die Listen liefern, immer mit @()
   einsammeln: $f = @(Funktion ...). Nie return ,$x verwenden.
5. PS 5.1: Group-, Where-, Sort-Object mit Eigenschaftsnamen finden keine Hashtable-Schlüssel (Skriptblöcke nutzen);
   Get-ChildItem -Include wirkt ohne -Recurse oder Platzhalter nicht. Dateien immer mit Encoding UTF8 lesen.
6. Das Testmodul nie mit dem ganzen Teil Kern\Datenordner.ps1 laden (der Teil ruft beim Laden Resolve-DataDir auf),
   sondern einzelne Funktionen. Externe Programme (winget, net.exe, nvidia-smi, powershell.exe) mocken.
7. Temporäre Ordner je Prozess anlegen (PID im Namen), nie fest; C#-Teile je Testlauf höchstens einmal übersetzen,
   unter Windows im Kindprozess. Windows-Befehle, die es unter Linux nicht gibt, per Mock ersetzen; nur wenn ein Test
   zwingend Windows braucht: Set-ItResult -Skipped mit Test-IstWindows.

## Git
Repository: https://github.com/sudoMrMCaffe/MiniBench (Zweig main). Bauen.cmd committet nach bestandenen Tests lokal,
gepusht wird von Hand (git push). Jede Version ein Commit "Release vX.Y: <Titel aus Versionen.cs>". Vor der Arbeit
git log seit dem in Doku\Projektstand.md genannten Commit lesen.

## Vorgehen in jedem Chat
1. Zuerst lesen: dieses Dokument, Doku\Projektstand.md, Doku\Änderungen der letzten Version, git log und die
   betroffenen Teile in src. Erst danach ändern.
2. Bei zwei sinnvollen Lösungswegen kurz nachfragen, sonst begründet entscheiden.
3. Für jede neue Funktion Pester-Tests ergänzen und mit Testen.cmd (Windows) bzw. der Sandbox laufen lassen.
   "Alle Tests bestanden" nur schreiben, wenn ein Lauf das belegt, mit Zahlen.
4. Vor der Übergabe Codeprüfung auf Fehler, gefundene Fehler im Abschnitt "Gefunden und behoben" der Änderungsdatei nennen.

## Abschluss jeder Version
1. Version in src\Kern\Version.ps1 erhöhen.
2. Eintrag oben in src\Oberflaeche\Versionen.cs, Doku\Versionshistorie.txt und CHANGELOG.md (Release.Tests.ps1 prüft alle drei).
3. Doku\Änderungen_vX.Y.txt im Stil der bisherigen Dateien (Abschnitte, Gefunden und behoben, Grenzen, Umstieg, Quellen).
   Keine Testmatrix.
4. Doku\Projektstand.md aktualisieren (Stand, offene Befunde, Fallstricke, letzter Commit).
5. Bauen.cmd ausführen (oder Leonardo darum bitten), danach git push.
