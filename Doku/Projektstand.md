# Leos Minibench: Projektstand

Gemeinsamer Stand für alle Agenten (Claude, Antigravity). Wird am Ende jeder Version aktualisiert (siehe AGENTS.md).

## Stand: Version 3.53 (09.10.2026)
Letzter gepushter Release vor 3.53: Commit a42c280 (Release v3.52). 3.53 entsteht als Commit "Release v3.53: ..." beim
nächsten erfolgreichen Bauen.cmd.

Inhalt von 3.53 (Einzelheiten in Doku\Änderungen_v3.53.txt):
1. Testsuite nach Fachgebieten statt nach Versionen; die Oberfläche wird je Testlauf einmal übersetzt und mit einem
   Selbsttest geprüft (tests\Daten\Oberflaeche\GuiSelbsttest.cs).
2. Softwarepakete der Seite Tools: winget im Arbeitsprozess (Hilfsmodus -SoftwareInstallieren, Kern\Softwarepakete.ps1)
   mit Frist, gelesener Ausgabe, Eintrag im Änderungsprotokoll und Rückgängig.
3. Grafikauswahl im Lasttest: Abgleich in beide Richtungen (DiagGui.CopySelection).
4. Minidumps mit Kerneladressen werden gelesen; Bauen.cmd committet nur nach bestandenen Tests.
5. Erster Lauf unter Windows (Pester 6.2): 10 Fehlschläge, alle in den Tests (PS 5.1 .Count, Pester 6 ohne Rückfall
   auf den echten Befehl); behoben, der Sandbox-Nachbau verhält sich jetzt wie Pester 6.

Testlauf Sandbox (pwsh 7.4, Pester-Nachbau, mcs/mono): 783 bestanden, 0 fehlgeschlagen, 11 übersprungen.
Übersprungen: 6 bekannte Fehler (unten, mit -Skip), 2 nur unter Windows, Aktueller Build (Inconclusive), 2 in Lauf.
Unter Windows sind ohne -Gesamtlauf rund 100 Tests in Lauf.Tests.ps1 übersprungen; das ist so gewollt.

## Offene Befunde (Reihenfolge = Dringlichkeit)
1. Datenpflege.ps1 (~Z.250) löscht alle Dateien direkt in Laufzeit\ älter als 2 Stunden, darunter PawnIO_<PC>.txt und
   Start.log. Nach einem Absturz bleibt der PawnIO-Treiber dann auf dem fremden PC. Test mit -Skip in Datenbank.Tests.ps1.
2. Datenpflege sucht laufend.json in <Datenordner>\Laufzeit, CpDir liegt seit 3.52 lokal: Mit NAS werden laufende Läufe
   als unvollständig archiviert (Test mit -Skip). Netzwerk.json hat Vorrang vor -DatenDir; Bauen.cmd räumt dann das NAS auf.
3. Tools-Seite (DiagGui_Seiten.cs, FindToolPath, StartAdminProcess): startet die erste beliebige exe im Tools- oder
   Installationsordner mit runas, ohne SHA-256 aus Tools.json (Vorgabe 5).
4. NAS-Dialog (DiagGui_Seiten.cs): Netzwerk.json an bis zu 5 Orten, /persistent:yes voreingestellt, Kennwort in der
   Befehlszeile von net.exe, net use im UI-Thread, kein Trennen, kein Protokolleintrag (Vorgaben 3 und 4).
5. Dashboard (Bericht\Bausteine_Dashboard.ps1): kein HTML-Escaping (innerHTML), JSON ungeschützt in <script>,
   synthetische Lasttestkurve ohne CSV (~Z.377-412), falscher Ersatz-Ordnername für Berichtslinks (Datum_PC statt
   PC_Datum_Zeit), $FilePath statt $sourceFile (~Z.430), Dashboard-Kopie im Laufordner mit kaputten Links, Version fest
   "v3.31", Rückfall auf Get-Location. Drei Tests mit -Skip in Bericht.Tests.ps1.
6. Datenpflege.ps1 Z.236: Get-ChildItem -Include ohne -Recurse findet unter PS 5.1 nichts (Test mit -Skip).
7. Oberfläche: Schriften in eigenen Steuerelementen doppelt DPI-skaliert (UI.SF auf Punktgrößen), Legende der
   Risikostufen auf der Optimierungsseite fehlt (lg nicht eingefügt), clbCompare und btnCompare tot.
8. Kleinere: Datenordner.ps1 Z.77/129 Join-Path mit leerem Dokumente-Pfad außerhalb try; Datenpflege-Text
   "1 verwaiste Eintrag"; Grundgeruest.ps1 Z.121 ohne -DashboardSysteme; Emojis, Anglizismen und Werbesprache in
   Oberfläche, README und älteren Änderungsdateien.
9. Repo: Aktueller Build und Archiv mit exe-Dateien im Repo (besser GitHub Releases); keine .gitattributes.

## Fallstricke
1. Pester 6.2 auf ULB-PC10039 (Profil auf dem Netzlaufwerk \\ulb.ad.hhu.de\Home\...). Attrappen mit -ParameterFilter
   brauchen eine Vorgabe-Attrappe ohne Filter.
2. Windows PowerShell 5.1: einzelnes Objekt ohne .Count, daher $x = @(...). Die Sandbox (pwsh 7) bemerkt das nicht.
3. winget-Quelle auf ULB-PC10039 defekt (0x8A15000F): Softwarepakete melden dort "Zustand nicht feststellbar";
   Abhilfe winget source reset --force als Administrator.
4. Get-MinibenchBuild schreibt src\Kern\Referenzen_Eingebettet.ps1 neu, wenn sich die Referenzprofile ändern; unter
   Linux nur wegen der Zeilenenden (dann nicht übernehmen).

## Testgeräte
TORRENT: Ryzen 5 7600X, Radeon RX 6800, B650 Gaming X AX, PawnIO 2.2.0.0, 5 Laufwerke (3 NVMe, 2 SATA).
ULB-PC10039: Dell Precision 5480, i9-13900H, Iris Xe und RTX 3000 Ada Laptop (Hybridgrafik), Domänen-PC, BitLocker,
WD SN820 4 TB, unter CPU-Last bis 100 °C (Firmware-Drosselung).
DESKTOP-2KDA9KP: Dell Latitude 5300, i5-8365U, UHD 620. DESKTOP-F9HRMRR: Ryzen 5 5600, RX 570, B450, RAM mit 2133 MT/s.
