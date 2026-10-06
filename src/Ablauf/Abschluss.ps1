# =====================================================================================
#                                    ABSCHLUSS
# =====================================================================================

if ($ScheduleWindowsMemTest -and $ModDiag -and -not $AnalyzeLastRun) {
    Add-Section 'Windows-Speicherdiagnose'
    Add-Line '  mdsched.exe wird gestartet. Nach dem Neustart testet Windows den RAM vor dem Systemstart.'
    Add-Line '  Das Ergebnis erscheint nach der Anmeldung als Hinweis und im System-Protokoll (Quelle MemoryDiagnostics-Results).'
}


# Schneller Modus: Hintergrundprüfungen abschließen (sollten längst fertig sein)
if ($script:BgJobs.Count) { Wait-BgAll 'der Abschluss'; Stop-BgJobs }
# Rendertest: kein Grafikgerät darf offen bleiben
if ($GpuTypesLoaded) { try { [DiagGpu]::StopAll() } catch { } }

# Sensoren schließen: entfernt einen vorübergehend installierten PawnIO-Treiber, bevor die Rückstandskontrolle prüft
Close-SensorSession
foreach ($t in @($script:SensorNotes | Select-Object -Unique)) { Add-Finding INFO 'Sensoren' $t }

# Werkzeug-Manifest: abgewiesene oder neu aufgenommene Dateien
foreach ($t in @($script:ToolIssues | Select-Object -Unique)) { Add-Finding WARNUNG 'Werkzeuge' $t }
foreach ($t in @($script:ToolNotes | Select-Object -Unique)) { Add-Finding INFO 'Werkzeuge' $t }

# ---------- Rückstandskontrolle: auf dem geprüften PC sollen keine Dateien des Werkzeugs bleiben ----------
# Eintrag im gemeinsamen TEMP-Ordner (Lauf_<PID>, Start_<PID>.log, LeosMinibench_<PID>.ps1): veraltet, wenn der Prozess
# nicht mehr läuft. Der eigene Prozess und unbekannte Namen gelten als nicht veraltet. Arbeitsordner (Lauf_) räumt
# Restore-StaleWorkDirs beim Start auf, damit ihre Rohdaten vorher gesichert werden.
function Test-TempEntryStale([string]$Name) {
    if ($Name -notmatch '^(Lauf|Start|LeosMinibench|Last)_(\d+)(_\w+|\.\w+)?$') { return $false }
    if ($Matches[1] -eq 'Lauf') { return $false }
    $id = [int]$Matches[2]
    if ($id -eq $PID) { return $false }
    try { $pr = Get-Process -Id $id -ErrorAction Stop; return -not ($pr.ProcessName -match 'LeosMinibench|powershell|pwsh') } catch { return $true }
}
function Invoke-ResidueCheck {
    $removed = New-Object System.Collections.ArrayList
    $left = New-Object System.Collections.ArrayList
    $del = {
        param([string]$Path, [string]$What)
        if (-not (Test-Path -LiteralPath $Path)) { return }
        try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop; [void]$removed.Add(('{0}: {1}' -f $What, $Path)) }
        catch { [void]$left.Add(('{0}: {1} ({2})' -f $What, $Path, $_.Exception.Message)) }
    }
    # Testdateien von Benchmark und Lasttest auf allen Laufwerken (z. B. nach einem Absturz)
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })) {
        foreach ($n in 'LeosMinibench-Benchmark.tmp', 'LeosMinibench-Lasttest.tmp', 'PC-Diagnose-Benchmark.tmp', 'PC-Diagnose-Lasttest.tmp') { & $del ('{0}:\{1}' -f $v.DriveLetter, $n) 'Testdatei' }
    }
    # temporäre Dateien dieses Werkzeugs und Ordner früherer Versionen (PC-Diagnose)
    $mine = @($PSCommandPath, $script:DataDir) | Where-Object { $_ }
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    $profiles = @(if (Test-Path -LiteralPath $usersRoot) { Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } })
    $tempRoots = @($env:TEMP, "$env:windir\Temp") + @($profiles | ForEach-Object { Join-Path $_ 'AppData\Local\Temp' })
    foreach ($t in @($tempRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
        foreach ($i in @(Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'LeosMinibench*' -or $_.Name -like 'PC-Diagnose*' })) {
            if (@($mine | Where-Object { $_ -like ($i.FullName + '*') }).Count) { continue }   # eigene, noch laufende Skriptdatei
            # ab v2.8: DDU wartet auf den nächsten Neustart (RunOnce); der Ordner löscht sich danach selbst
            if ($i.Name -eq $script:OptDduDir -and (Test-OptDduPending)) { $script:OptDduKept = $i.FullName; continue }
            # gemeinsamer Ordner %TEMP%\LeosMinibench: nie als Ganzes löschen (Arbeitsordner, Skript und Statusdatei laufender
            # Prozesse liegen darin, der Pfad kann als 8.3-Kurzname abweichen). Einträge nur entfernen, wenn ihr Prozess beendet ist.
            if ($i.PSIsContainer -and $i.Name -eq 'LeosMinibench') {
                foreach ($e in @(Get-ChildItem -LiteralPath $i.FullName -Force -ErrorAction SilentlyContinue)) {
                    if (-not (Test-TempEntryStale $e.Name)) { continue }
                    & $del $e.FullName 'Temporäre Datei'
                }
                if (-not @(Get-ChildItem -LiteralPath $i.FullName -Force -ErrorAction SilentlyContinue).Count) { & $del $i.FullName 'Temporärer Ordner' }
                continue
            }
            & $del $i.FullName 'Temporäre Datei'
        }
    }
    foreach ($d in "$env:ProgramData\PC-Diagnose", "$env:PUBLIC\PC-Diagnose") { & $del $d 'Ordner einer früheren Version' }
    # Berichtsordner früherer Versionen auf Desktops: in den Datenordner verschieben statt zu löschen
    if ($script:DataDir -and -not $script:DataDirFallback) {
        $desks = @("$env:PUBLIC\Desktop") + @($profiles | ForEach-Object { Join-Path $_ 'Desktop' }) + @([Environment]::GetFolderPath('Desktop'))
        foreach ($dk in @($desks | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
            foreach ($o in @(Get-ChildItem -LiteralPath $dk -Directory -Filter 'PC-Diagnose_*' -ErrorAction SilentlyContinue)) {
                $dest = Join-Path (Join-Path $script:DataDir 'Berichte\Altbestand') $o.Name
                try { New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null; Move-Item -LiteralPath $o.FullName -Destination $dest -Force -ErrorAction Stop; [void]$removed.Add(('Bericht einer früheren Version vom Desktop in den Datenordner verschoben: {0}' -f $o.Name)) }
                catch { [void]$left.Add(('Bericht einer früheren Version auf dem Desktop: {0} ({1})' -f $o.FullName, $_.Exception.Message)) }
            }
            foreach ($f in @(Get-ChildItem -LiteralPath $dk -File -Filter 'PC-Diagnose*.exe' -ErrorAction SilentlyContinue)) { [void]$left.Add(('Programmdatei einer früheren Version auf dem Desktop (nicht gelöscht): {0}' -f $f.FullName)) }
        }
    }
    # PawnIO: nur entfernen, was dieses Werkzeug installiert hat; ein vorher vorhandener Treiber bleibt
    $pwm = Get-PawnIoMarker
    $kept = New-Object System.Collections.ArrayList
    if ($pwm -and (Test-Path -LiteralPath $pwm)) {
        if ((Get-ToolKeep) -eq 'behalten') { $k = Save-PawnIoKept; if ($k) { [void]$kept.Add(('Treiber: {0}' -f $k.Text)) } }
        else { $u = Uninstall-PawnIo; if ($u -and $u.Ok) { [void]$removed.Add(('Treiber: {0}' -f $u.Text)) } elseif ($u) { [void]$left.Add(('Treiber: {0}' -f $u.Text)) } }
    }
    elseif ($script:PawnIoKeptRemoval -and $script:PawnIoKeptRemoval -isnot [bool]) {
        $u = $script:PawnIoKeptRemoval
        if ($u.Ok) { [void]$removed.Add(('Treiber: früher behaltener PawnIO entfernt ({0})' -f $u.Text)) } else { [void]$left.Add(('Treiber: {0}' -f $u.Text)) }
    }
    elseif ($script:Sens -and $script:Sens.Treiber -match 'wieder entfernt') { [void]$removed.Add('Treiber: PawnIO wieder entfernt') }
    elseif ($script:Sens -and $script:Sens.Treiber -match 'noch installiert') { [void]$left.Add(('Treiber: {0}' -f $script:Sens.Treiber)) }
    # ab v2.8: bewusst angelegt im Modul Optimierung
    if ($script:OptDduKept) { [void]$kept.Add(('DDU für den nächsten Neustart: {0} (löscht sich nach dem Lauf von DDU selbst)' -f $script:OptDduKept)) }
    if (Test-OptMaintenanceTasksPresent) { [void]$kept.Add(('Geplante Aufgaben {0} (Modul Optimierung, regelmäßige Bereinigung; entfernen über die Seite Änderungen)' -f $script:OptTaskFolder)) }
    # auf Wunsch behalten (Wahl je Gerät in Geraete.json): kein Rückstand, aber im Bericht genannt
    if (Test-KeptTool 'PawnIO') { if (-not @($kept | Where-Object { $_ -match 'PawnIO' }).Count) { [void]$kept.Add('Treiber: PawnIO (auf Wunsch behalten)') } }
    if (Test-KeptTool 'smartmontools') { [void]$kept.Add('smartmontools (per winget installiert, auf Wunsch behalten)') }
    if ($script:SmartLeftInstalled) { [void]$left.Add('smartmontools ist noch installiert (Deinstallation fehlgeschlagen): winget uninstall smartmontools.smartmontools') }
    foreach ($t in @($script:StaleWorkNotes)) { if ($t -match 'nicht entfernbar') { [void]$left.Add($t) } else { [void]$removed.Add($t) } }

    if ($removed.Count) { Add-Line '  Entfernt oder verschoben:'; $removed | ForEach-Object { Add-Line ('    ' + $_) } }
    if ($kept.Count) { Add-Line '  Auf Wunsch auf diesem PC behalten (Einstellung Hilfswerkzeuge):'; $kept | ForEach-Object { Add-Line ('    ' + $_) } }
    if ($left.Count) { Add-Line '  Verblieben:'; $left | ForEach-Object { Add-Line ('    ' + $_) }; Add-Finding INFO 'System' ('Auf dem PC sind noch Dateien des Werkzeugs vorhanden: {0}' -f ($left -join '; ')) }
    if (-not $removed.Count -and -not $left.Count -and -not $kept.Count) { Add-Line '  Keine Dateien des Werkzeugs auf diesem PC gefunden.' }
    Add-Line ('  Alle Berichte und Daten liegen im Datenordner: {0}' -f $script:DataDir)
    if ($script:WorkDir) { Add-Line ('  Lokaler Arbeitsordner dieses Laufs: {0}. Er wird gelöscht, sobald Bericht und Anhang im Datenordner liegen; ein Rest fällt beim nächsten Start auf.' -f $script:WorkDir) }
    Add-Line '  Nicht entfernbar und nicht entfernt werden Spuren, die Windows selbst anlegt: Ereignisprotokolle, Prefetch-Einträge,'
    Add-Line '  CBS- und DISM-Protokolle (bei Integritätsprüfung und Reparatur) sowie der WinSAT-Datenspeicher (bei WinSAT).'
    $keptTxt = $(if ($kept.Count) { ', {0} Hilfswerkzeug(e) auf Wunsch behalten' -f $kept.Count } else { '' })
    Add-TestResult 'Rückstandskontrolle' $(if ($left.Count) { 'Info' } else { 'OK' }) ($(if ($left.Count) { '{0} Reste verblieben' -f $left.Count } elseif ($removed.Count) { '{0} Reste entfernt oder verschoben' -f $removed.Count } else { 'keine Reste gefunden' }) + $keptTxt)
}
Invoke-Section 'Rückstandskontrolle' { Invoke-ResidueCheck }

# Kein Bericht ohne Inhalt: Jedes gewählte Modul muss ein Ergebnis liefern, sonst steht der Grund als Befund und Test im Bericht
function Test-ModuleResults {
    $why = {
        param([string]$Pattern)
        $e = @($script:SectionErrors | Where-Object { $_.Abschnitt -match $Pattern })
        if ($e.Count) { return ('Abschnitt abgebrochen: {0}' -f $e[0].Meldung) }
        if ($script:SkippedByCrash -and $script:SkippedByCrash -match $Pattern) { return 'nach einem Absturz im letzten Lauf übersprungen' }
        return 'kein Schritt ausgeführt'
    }
    $miss = @()
    if ($ModBench -and -not $script:BenchResults.Count -and -not $script:BenchDisks.Count) { $miss += [pscustomobject]@{ Modul = 'Benchmark'; Grund = (& $why '^Benchmark') } }
    if ($ModLast -and -not $script:LoadParts.Count) { $miss += [pscustomobject]@{ Modul = 'Lasttest'; Grund = (& $why '^Lasttest') } }
    if ($ModRep -and -not $script:RepairLog.Count) { $miss += [pscustomobject]@{ Modul = 'Reparatur'; Grund = (& $why '^Reparatur') } }
    if ($ModOpt -and -not @($script:OptLog).Count) { $miss += [pscustomobject]@{ Modul = 'Optimierung'; Grund = (& $why '^Optimierung') } }
    if ($ModDiag -and -not $AnalyzeLastRun -and -not $script:Facts.Count -and -not @($script:TestResults | Where-Object { $_.Test -ne 'Rückstandskontrolle' }).Count) { $miss += [pscustomobject]@{ Modul = 'Diagnose'; Grund = (& $why '.') } }
    foreach ($m in $miss) {
        Add-Finding WARNUNG 'Ablauf' ('Das Modul {0} hat kein Ergebnis geliefert ({1}). Lauf wiederholen; bleibt es so, Checkpoint.log und KI-Datei prüfen.' -f $m.Modul, $m.Grund)
        Add-TestResult $m.Modul 'Fehler' $m.Grund
        Add-Section ('{0}: kein Ergebnis' -f $m.Modul)
        Add-Line ('  {0}' -f $m.Grund)
    }
}
Test-ModuleResults
# Schreibzugriffe auf den Datenträger des Datenordners (ab v2.6): Leistungszähler von Windows, ohne die Berichtsdateien am Ende
$script:WriteInfo = $null
try { $script:WriteInfo = Get-WriteDelta $script:WriteStart (Get-VolumeWriteCounter $OutputDir) } catch { }
Add-Sub 'Schreibzugriffe auf den Datenträger des Datenordners'
if ($script:WriteInfo) {
    Add-Line ('  {0} ({1}): {2:N0} Schreibvorgänge, {3:N1} MB in {4:N0} Sekunden (laut Windows, ohne die Berichtsdateien am Ende des Laufs)' -f $script:WriteInfo.Laufwerk, $script:WriteInfo.Art, $script:WriteInfo.Vorgaenge, $script:WriteInfo.MB, $script:WriteInfo.Sekunden)
    $script:Facts['Schreibzugriffe Datenordner'] = ('{0:N0} Vorgänge, {1:N1} MB auf {2} ({3})' -f $script:WriteInfo.Vorgaenge, $script:WriteInfo.MB, $script:WriteInfo.Laufwerk, $script:WriteInfo.Art)
} else { Add-Line '  Nicht messbar (Leistungszähler für das Laufwerk nicht verfügbar).' }
Add-Line ('  Eigene Schreibvorgänge: {0} Checkpoint-Blöcke, {1} Zwischenstände; Rohdaten im lokalen Arbeitsordner{2}.' -f $script:CpWrites, $script:PartialWrites, $(if ($script:WorkDir) { '' } else { ' nicht verfügbar, daher direkt im Berichtsordner' }))

# Standby-Sperre im Bericht vermerken
Add-Sub 'Standby während des Laufs'
Add-Line ('  Standby-Sperre: {0}. Der Bildschirm durfte ausgehen; am Laufende wieder aufgehoben.' -f $script:StandbyText)
$script:Facts['Standby-Sperre'] = ('{0}, Bildschirm durfte ausgehen' -f $script:StandbyText)

$script:StepNo = [math]::Max((Get-PlannedSteps), $script:StepNo + 1)
Show-Overall 'Bericht, KI-Datei und Datenbankeintrag werden erstellt'
Hide-Sub
$EndTime = Get-Date
$order = @{ KRITISCH = 0; WARNUNG = 1; INFO = 2 }
$sorted = @($script:Findings | Sort-Object Stufe, Bereich, Befund -Unique | Sort-Object @{ e = { $order[$_.Stufe] } }, Bereich)
$nK = @($sorted | Where-Object Stufe -eq 'KRITISCH').Count
$nW = @($sorted | Where-Object Stufe -eq 'WARNUNG').Count
$nI = @($sorted | Where-Object Stufe -eq 'INFO').Count

if ($ModDiag -and -not $AnalyzeLastRun) {
    $skipList = @(@('Dateisystem und Systemdateien', 'Integritaet'), @('Defender Schnellscan', 'Defender'), @('SMART-Langtest', 'SmartLang'), @('Netzwerk', 'Netzwerk'), @('RAM-Mustertest', 'RamTest'), @('Energieanalyse', 'Energieanalyse'))
    foreach ($sk in $skipList) { if (-not $script:Opt[$sk[1]]) { Add-TestResult $sk[0] 'Übersprungen' 'nicht ausgewählt' } }
}

# Datenbankeintrag vor dem Bericht, damit der Pfad im Bericht steht
$script:DbSaved = Save-DbEntry -Sorted $sorted -NK $nK -NW $nW -NI $nI
if ($script:DbSaved) { Add-Sub 'Vergleichsdatenbank'; Add-Line ('  Eintrag gespeichert: {0}' -f $script:DbSaved) }

$head = New-Object System.Text.StringBuilder
[void]$head.AppendLine('#' * 100)
[void]$head.AppendLine(('  LEOS MINIBENCH: DIAGNOSEBERICHT   {0}   v{1}' -f $env:COMPUTERNAME, $ScriptVersion))
[void]$head.AppendLine('#' * 100)
[void]$head.AppendLine(('  Erstellt     : {0:dd.MM.yyyy HH:mm} bis {1:HH:mm} Uhr (Dauer {2:hh\:mm\:ss})' -f $StartTime, $EndTime, ($EndTime - $StartTime)))
[void]$head.AppendLine(('  Module       : {0}' -f (Get-ModeLabel)))
[void]$head.AppendLine(('  Risikostufe  : {0}' -f (Get-RiskLabel (Get-RunRisk))))
[void]$head.AppendLine(('  Standby      : Sperre {0}, Bildschirm durfte ausgehen' -f $script:StandbyText))
if ($script:FastMode) { [void]$head.AppendLine(('  Ablauf       : schneller Modus, parallel liefen {0}' -f $(if ($script:BgJobs.Count) { (@($script:BgJobs.Values | ForEach-Object { '{0} ({1})' -f $_.Titel, $(if ($_.Start -and $_.Ende) { '{0:mm\:ss}' -f ($_.Ende - $_.Start) } else { $_.Status }) })) -join ', ' } else { 'keine Prüfungen (nichts Parallelisierbares gewählt)' }))) }
if ($ModDiag -and -not $AnalyzeLastRun) {
    [void]$head.AppendLine(('  Prüfungen    : {0}' -f ((@($script:DiagKeys | ForEach-Object { '{0} {1}' -f $_, $(if ($script:Opt[$_]) { 'ja' } else { 'nein' }) })) -join ', ')))
}
[void]$head.AppendLine(('  Ausgabe      : {0}' -f $OutputDir))
if ($script:DataDir) { [void]$head.AppendLine(('  Datenordner  : {0}' -f $script:DataDir)) }
[void]$head.AppendLine()
if ($script:Stability) {
    [void]$head.AppendLine(('  ZUVERLÄSSIGKEIT: {0}' -f $script:Stability.Text))
    if ($script:Stability.Erklaerung) { foreach ($l in @(Split-TextLines $script:Stability.Erklaerung 94)) { [void]$head.AppendLine('    ' + $l) } }
    [void]$head.AppendLine()
}
[void]$head.AppendLine(('  ERGEBNIS: {0} kritisch, {1} Warnungen, {2} Hinweise' -f $nK, $nW, $nI))
[void]$head.AppendLine('  ' + ('-' * 98))
if ($sorted.Count) {
    foreach ($f in $sorted) { [void]$head.AppendLine(('  [{0,-8}] {1,-14} {2}' -f $f.Stufe, $f.Bereich, $f.Befund)) }
} else { [void]$head.AppendLine('  Keine Auffälligkeiten gefunden.') }
[void]$head.AppendLine()
[void]$head.AppendLine('  Zeitbedarf der Abschnitte:')
foreach ($t in $script:Timings) { [void]$head.AppendLine(('    {0,-55} {1}' -f $t.Abschnitt, $t.Dauer)) }

$full = $head.ToString() + $script:Report.ToString()
$reportFile = Join-Path $OutputDir 'Diagnosebericht.txt'
[IO.File]::WriteAllText($reportFile, $full, (New-Object Text.UTF8Encoding($true)))
Write-Checkpoint 'ENDE' 'Lauf regulär abgeschlossen'
Close-Checkpoint -RemoveFlag
try { Copy-Item $script:CpLog (Join-Path $RawDir 'Checkpoint.log') -Force } catch { }
Remove-Item (Join-Path $OutputDir 'Diagnosebericht_teilweise.txt') -Force -ErrorAction SilentlyContinue

$kiName = $(if ($KiOhneAnonymisierung) { 'KI-Analyse_{0}_{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmm') } else { 'KI-Analyse_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmm') })
$kiFile = Join-Path $OutputDir $kiName
$htmlFile = Join-Path $OutputDir 'Diagnosebericht.html'
try { New-HtmlReport -Path $htmlFile -Sorted $sorted -NK $nK -NW $nW -NI $nI -Start $StartTime -End $EndTime }
catch { Write-Warning ('HTML-Bericht konnte nicht erstellt werden: {0}' -f $_.Exception.Message); $htmlFile = '' }

try {
    $dashPath = Export-BenchDashboardHtml -ErrorAction SilentlyContinue
    if ($dashPath -and (Test-Path -LiteralPath $dashPath)) {
        Copy-Item -LiteralPath $dashPath -Destination (Join-Path $OutputDir 'Dashboard.html') -Force -ErrorAction SilentlyContinue
    }
} catch { }

if ($script:GuiLog) { try { $script:GuiLog.Close(); $script:GuiLog = $null } catch { } }

# KI-Dateien: vollständige Fassung mit Rohdaten zum Hochladen, Kurzfassung ohne Rohdaten zum Einfügen in ein Chatfenster
$kurzFile = Join-Path $OutputDir 'KI-Kurzfassung.txt'
try {
    Add-PrivateFromRaw
    [void](New-KiExport -Path $kiFile -Sorted $sorted -NK $nK -NW $nW -NI $nI -Start $StartTime -End $EndTime)
    [void](New-KiExport -Path $kurzFile -Sorted $sorted -NK $nK -NW $nW -NI $nI -Start $StartTime -End $EndTime -Compact)
} catch { Write-Warning ('KI-Datei konnte nicht erstellt werden: {0}' -f $_.Exception.Message); $kiFile = ''; $kurzFile = '' }

# Alles außer den Berichten in Anhang.zip packen
$zipFile = Join-Path $OutputDir 'Anhang.zip'
try {
    if (@(Get-ChildItem $RawDir -Force -ErrorAction SilentlyContinue).Count) {
        Compress-Archive -Path (Join-Path $RawDir '*') -DestinationPath $zipFile -Force -ErrorAction Stop
        Remove-Item $RawDir -Recurse -Force -ErrorAction SilentlyContinue
    } else { Remove-Item $RawDir -Force -ErrorAction SilentlyContinue; $zipFile = '' }
} catch { $zipFile = '' }

Write-Host ''
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ('  FERTIG nach {0:hh\:mm\:ss}' -f ($EndTime - $StartTime)) -ForegroundColor Cyan
Write-Host ('  {0} kritisch, {1} Warnungen, {2} Hinweise' -f $nK, $nW, $nI) -ForegroundColor $(if ($nK) { 'Red' } elseif ($nW) { 'Yellow' } else { 'Green' })
Write-Host ('  Ordner      : {0}' -f $OutputDir)
if ($htmlFile) { Write-Host '  Bericht     : Diagnosebericht.html (und .txt)' } else { Write-Host '  Bericht     : Diagnosebericht.txt' }
if ($kiFile) { Write-Host ('  KI-Datei    : {0} ({1:N0} KB, zum Hochladen) und KI-Kurzfassung.txt (zum Einfügen)' -f (Split-Path $kiFile -Leaf), ((Get-Item $kiFile).Length / 1KB)) }
if ($zipFile) { Write-Host '  Anhang      : Anhang.zip (Protokolle und Rohdaten)' }
if ($script:DbSaved) { Write-Host ('  Datenbank   : {0}' -f $script:DbSaved) }
if ($script:RestartNeeded.Count) { Write-Host ('  NEUSTART erforderlich für: {0}' -f (($script:RestartNeeded | Select-Object -Unique) -join ', ')) -ForegroundColor Yellow }
Write-Host ('=' * 80) -ForegroundColor Cyan

if ($ScheduleWindowsMemTest -and $ModDiag -and -not $AnalyzeLastRun) { Start-Process "$env:windir\System32\mdsched.exe" }
Remove-Item -LiteralPath $script:CpDir -Recurse -Force -ErrorAction SilentlyContinue
# lokalen Arbeitsordner löschen und prüfen
if ($script:WorkDir -and (Test-Path -LiteralPath $script:WorkDir)) {
    Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:WorkDir) { Write-Warning ('Der lokale Arbeitsordner ließ sich nicht vollständig löschen: {0}. Der nächste Start räumt ihn auf.' -f $script:WorkDir) }
    $wb = Split-Path $script:WorkDir -Parent
    if ($wb -and -not @(Get-ChildItem -LiteralPath $wb -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $wb -Force -ErrorAction SilentlyContinue }
}
$rtDir = Split-Path $script:CpDir -Parent
if ($rtDir -and (Split-Path $rtDir -Leaf) -eq 'Laufzeit' -and -not @(Get-ChildItem -LiteralPath $rtDir -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $rtDir -Force -ErrorAction SilentlyContinue }
Stop-StandbyLock
Send-GuiEvent 'DONE' $reportFile $htmlFile $OutputDir $nK $nW $nI $kurzFile $kiFile
