# Leos Minibench: Projektstand

Gemeinsamer Stand für alle Agenten (Claude, Antigravity). Wird am Ende jeder Version aktualisiert (siehe AGENTS.md).

## Stand: Version 3.54 (09.10.2026)
Letzter gepushter Release: Commit a42c280 (Release v3.52). 3.53 und 3.54 entstehen als Commits "Release vX.Y: ..." beim
nächsten erfolgreichen Bauen.cmd (Arbeitszweig von Claude: claude/v3.54, auf claude/v3.53 aufbauend).

Inhalt von 3.54 (Einzelheiten in Doku\Änderungen_v3.54.txt):
1. Datenordner immer auf dem Stick: Resolve-DataDir liest Netzwerk.json nicht mehr, kein net use beim Start. Tools,
   Cache, Laufzeit, Datenbank und Berichte liegen alle in Minibench-Daten; LocalDataDir = DataDir.
2. Netzlaufwerk als Spiegel (Kern\Ablage.ps1): Abgleich in beide Richtungen nur über Aktualisieren (Hilfsmodus
   -Abgleich, nach Anhalten -AbgleichLoeschen oder -AbgleichNeu), Stand in Minibench-Daten\Abgleich\Stand.json,
   Konflikte und Löschungen ins Archiv\Abgleich, Schutz vor Massenlöschung, Sperre Abgleich.lock auf dem NAS.
   Oberfläche: Klasse NasAblage (DiagGui_Modelle.cs), Dialog ShowConnectNasDialog, RefreshAndSync (DiagGui_Vergleich.cs).
3. Vergleichsdatenbank: Entfernen (-Entfernen "Pfad|Pfad") verschiebt Eintrag und Berichtsordner nach Archiv\Entfernt,
   Name ändern (-Umbenennen -NeuerName) benennt Datei und Berichtsordner um.
4. Datenpflege: PawnIO-Merker bleibt, -Include ersetzt (frühere Befunde 1 und 6).

Testlauf Sandbox (pwsh 7.4, Pester-Nachbau, mcs/mono): 857 bestanden, 0 fehlgeschlagen, 8 übersprungen
(3 bekannte Fehler im Dashboard mit -Skip, 2 nur unter Windows, Aktueller Build, 2 in Lauf).
Unter Windows ist 3.54 noch nicht gelaufen. Ohne -Gesamtlauf sind rund 100 Tests in Lauf.Tests.ps1 übersprungen; gewollt.

## Offene Befunde (Reihenfolge = Dringlichkeit)
1. Tools-Seite (DiagGui_Seiten.cs, FindToolPath, StartAdminProcess): startet die erste beliebige exe im Tools- oder
   Installationsordner mit runas, ohne SHA-256 aus Tools.json (Vorgabe 5).
2. Dashboard (Bericht\Bausteine_Dashboard.ps1): kein HTML-Escaping (innerHTML), JSON ungeschützt in <script>,
   synthetische Lasttestkurve ohne CSV (~Z.377-412), falscher Ersatz-Ordnername für Berichtslinks (Datum_PC statt
   PC_Datum_Zeit), $FilePath statt $sourceFile (~Z.430), Dashboard-Kopie im Laufordner mit kaputten Links, Version fest
   "v3.31", Rückfall auf Get-Location. Drei Tests mit -Skip in Bericht.Tests.ps1.
3. Oberfläche: Schriften in eigenen Steuerelementen doppelt DPI-skaliert (UI.SF auf Punktgrößen), Legende der
   Risikostufen auf der Optimierungsseite fehlt (lg nicht eingefügt), clbCompare und btnCompare tot.
4. Abgleich (Grenzen, bewusst offen): Konflikte entscheidet die Dateizeit (falsche Uhr eines PCs); Pfade über 260
   Zeichen brechen den Abgleich ohne Änderung ab; leere Ordner werden nicht abgeglichen. Die Verbindung mit Kennwort
   (WNetAddConnection2) steht nicht im Änderungsprotokoll; sie ist nicht dauerhaft und wird beim Beenden getrennt.
5. Kleinere: Datenordner.ps1 Join-Path mit leerem Dokumente-Pfad außerhalb try; Datenpflege-Text "1 verwaiste Eintrag";
   Emojis, Anglizismen und Werbesprache in Oberfläche, README und älteren Änderungsdateien.
6. Repo: Aktueller Build und Archiv mit exe-Dateien im Repo (besser GitHub Releases); keine .gitattributes.

## Fallstricke
1. Pester 6.2 auf ULB-PC10039 (Profil auf dem Netzlaufwerk \\ulb.ad.hhu.de\Home\...). Attrappen mit -ParameterFilter
   brauchen eine Vorgabe-Attrappe ohne Filter.
2. Windows PowerShell 5.1: einzelnes Objekt ohne .Count, daher $x = @(...). Die Sandbox (pwsh 7) bemerkt das nicht.
3. winget-Quelle auf ULB-PC10039 defekt (0x8A15000F): Softwarepakete melden dort "Zustand nicht feststellbar";
   Abhilfe winget source reset --force als Administrator.
4. Netzlaufwerk: Netzwerk.json nur in Minibench-Daten auf dem Stick. Nie wieder einen Datenordner auf das NAS legen
   oder beim Start auf das NAS zugreifen; alles, was das NAS betrifft, läuft über Kern\Ablage.ps1 auf Knopfdruck.
   Tests für den Abgleich nehmen einen Ordner in TestDrive als NAS und ersetzen Test-NasPfad (Ablage.Tests.ps1).
5. Get-MinibenchBuild schreibt src\Kern\Referenzen_Eingebettet.ps1 neu, wenn sich die Referenzprofile ändern; unter
   Linux nur wegen der Zeilenenden (dann nicht übernehmen).

## Testgeräte
TORRENT: Ryzen 5 7600X, Radeon RX 6800, B650 Gaming X AX, PawnIO 2.2.0.0, 5 Laufwerke (3 NVMe, 2 SATA).
ULB-PC10039: Dell Precision 5480, i9-13900H, Iris Xe und RTX 3000 Ada Laptop (Hybridgrafik), Domänen-PC, BitLocker,
WD SN820 4 TB, unter CPU-Last bis 100 °C (Firmware-Drosselung).
DESKTOP-2KDA9KP: Dell Latitude 5300, i5-8365U, UHD 620. DESKTOP-F9HRMRR: Ryzen 5 5600, RX 570, B450, RAM mit 2133 MT/s.
