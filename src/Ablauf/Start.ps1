# Import älterer Ausgabeordner in die Vergleichsdatenbank (wird von der Oberfläche aufgerufen)
if ($ImportOrdner) {
    Import-LegacyFolder $ImportOrdner
    exit 0
}

# Vergleich bereits geprüfter Systeme ohne neuen Benchmark (wird von der Oberfläche aufgerufen)
if ($Vergleich) {
    $vf = ''
    try { $vf = New-CompareReport @(([string]$Vergleich) -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }) }
    catch { Write-Host ('Vergleich fehlgeschlagen: {0}' -f $_.Exception.Message) }
    if (-not $vf) { exit 1 }
    Send-GuiEvent 'RESULT' $vf
    if (-not $EventMode) { Invoke-Item -LiteralPath $vf }
    exit 0
}

# Interaktives Dashboard generieren oder öffnen (wird von der Oberfläche oder über die Befehlszeile aufgerufen)
if ($Dashboard -or $DashboardExport -or $DashboardSysteme) {
    $df = ''
    try {
        $outPath = $(if ($DashboardExport) { $DashboardExport } else { '' })
        $sysPaths = @()
        if ($DashboardSysteme) {
            $sysPaths = @($DashboardSysteme -split ';' | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
        }
        $df = Export-BenchDashboardHtml -OutputPath $outPath -SystemPaths $sysPaths
    } catch {
        Write-Host ('Dashboard-Erstellung fehlgeschlagen: {0}' -f $_.Exception.Message)
    }
    if (-not $df -or -not (Test-Path -LiteralPath $df)) { exit 1 }
    Send-GuiEvent 'RESULT' $df
    if (-not $EventMode -and -not $DashboardExport) { Invoke-Item -LiteralPath $df }
    exit 0
}

# Änderungen aus dem Änderungsprotokoll zurücknehmen (Seite Änderungen der Oberfläche): -Rueckgaengig "Datei*Id;Datei*Id"
if ($Rueckgaengig) {
    $u = Invoke-ChangeUndo $Rueckgaengig
    Write-Host ('{0} Änderungen zurückgenommen, {1} nicht möglich oder übersprungen.' -f $u.Rueckgaengig, $u.Probleme)
    Send-GuiEvent 'RESULT' $u.Rueckgaengig $u.Probleme
    exit $(if ($u.Probleme) { 1 } else { 0 })
}

Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ('  LEOS MINIBENCH v{0}   {1}   {2}' -f $ScriptVersion, $env:COMPUTERNAME, (Get-Date -Format 'dd.MM.yyyy HH:mm')) -ForegroundColor Cyan
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ('  Module         : {0}' -f (Get-ModeLabel))
Write-Host ('  Ausgabeordner  : {0}' -f $OutputDir)
Write-Host ('  Datenordner    : {0}' -f $(if ($script:DataDir) { $script:DataDir } else { 'nicht verfügbar (kein beschreibbarer Ordner)' }))
Write-Host  '  Der PC bleibt benutzbar, wird aber zeitweise stark ausgelastet. Bitte nicht in den Standby schicken.'
if (-not $FullLanguage) { Write-Host '  Hinweis        : PowerShell läuft im Constrained Language Mode, Tests mit C#-Routinen entfallen.' -ForegroundColor Yellow }
Write-Host ''

# Absturzanalyse darf den Start nie verhindern (sonst bliebe laufend.json liegen und jeder Start bräche hier ab)
try { Invoke-CrashAnalysis } catch { Write-Warning ('Absturzanalyse des letzten Laufs nicht möglich: {0}' -f $_.Exception.Message); Add-Finding INFO 'Absturzanalyse' ('Die Auswertung des letzten unterbrochenen Laufs schlug fehl: {0}' -f $_.Exception.Message); Remove-Item -LiteralPath $script:CpFlag -Force -ErrorAction SilentlyContinue }
# Hilfswerkzeuge: Wahl dieses Laufs (Parameter oder je Gerät gespeichert)
Write-Host ('  Hilfswerkzeuge : {0}' -f $(if ((Get-ToolKeep) -eq 'behalten') { 'auf diesem PC behalten' } else { 'nach dem Lauf entfernen' }))
# früher behaltene smartmontools entfernen, wenn sie jetzt nicht mehr bleiben sollen
if ((Test-ToolRemoveKept) -and (Test-KeptTool 'smartmontools')) {
    $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wg) {
        $u = Invoke-External -File $wg.Source -Arguments 'uninstall --id smartmontools.smartmontools -e --silent --accept-source-agreements --disable-interactivity' -TimeoutSec 300 -Progress 'smartmontools wird deinstalliert (nicht mehr behalten)' -ExpectedSec 30 -Encoding ([Text.Encoding]::UTF8)
        if ($u.ExitCode -eq 0) { [void](Set-KeptTool 'smartmontools' $false); $script:ToolNotes.Add('Früher behaltene smartmontools wurden deinstalliert (Einstellung Hilfswerkzeuge: entfernen).') }
    }
}
# PawnIO-Treiber eines abgebrochenen Laufs entfernen (Markierung im Laufzeitordner)
Remove-PawnIoLeftover
# vorübergehende Einstellungen eines abgebrochenen Laufs zurücknehmen (GPU-Wahl für winsat.exe)
try {
    $tmpUndo = Restore-TemporaryChanges
    if ($tmpUndo -and $tmpUndo.Rueckgaengig) { $script:ToolNotes.Add(('Ein früherer Lauf wurde während einer vorübergehenden Einstellung abgebrochen; {0} Änderung(en) zurückgenommen (Seite Änderungen).' -f $tmpUndo.Rueckgaengig)) }
} catch { Write-Warning ('Vorübergehende Änderungen früherer Läufe nicht prüfbar: {0}' -f $_.Exception.Message) }
Open-Checkpoint
Remove-Item (Join-Path $script:CpDir 'stop.flag') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $script:CpDir 'skip.flag') -Force -ErrorAction SilentlyContinue
# Arbeitsordner abgebrochener Läufe im lokalen TEMP: Rohdaten sichern, Ordner entfernen (steht in der Rückstandskontrolle)
$script:StaleWorkNotes = @(); try { $script:StaleWorkNotes = @(Restore-StaleWorkDirs $OutputDir) } catch { }
if ($script:FastMode) { Write-Host '  Schneller Modus: unabhängige Prüfungen laufen parallel, Messungen bleiben exklusiv.' }

$script:Smartctl = Find-Smartctl
$script:SmartInstallMsg = ''
$script:SmartLeftInstalled = $false
if (-not $script:Smartctl -and $ModDiag -and -not $AnalyzeLastRun -and -not $Kurztest -and $InstallSmartmontools) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        $wp = Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($wp) { $winget = [pscustomobject]@{ Source = $wp.FullName } }
    }
    if ($winget) {
        Write-Step 'Installiere smartmontools über winget ...'
        $r = Invoke-External -File $winget.Source -Arguments 'install --id smartmontools.smartmontools -e --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity' -TimeoutSec 600 -Progress 'smartmontools wird installiert' -ExpectedSec 90 -Encoding ([Text.Encoding]::UTF8)
        $installed = Find-Smartctl
        if ($installed -and $script:DataDir) {
            # Programmdateien in den Datenordner übernehmen und die Installation wieder entfernen, damit nichts auf dem PC bleibt
            try {
                $tools = Join-Path $script:DataDir 'Tools\smartmontools\bin'
                New-Item -ItemType Directory -Path $tools -Force -ErrorAction Stop | Out-Null
                Copy-Item -Path (Join-Path (Split-Path $installed -Parent) '*') -Destination $tools -Recurse -Force -ErrorAction Stop
                # Die übernommene Datei ins Werkzeug-Manifest eintragen; ab dann läuft nur diese Fassung
                if (-not (Register-Tool -Name 'smartctl' -Path (Join-Path $tools 'smartctl.exe') -Lizenz $script:SmartLicense -Quelle $script:SmartSource -Herkunft ('per winget geholt auf {0}' -f $env:COMPUTERNAME))) { throw 'Eintrag ins Werkzeug-Manifest (Tools.json) fehlgeschlagen' }
                if ((Get-ToolKeep) -eq 'behalten') {
                    # auf Wunsch auf diesem PC behalten (Einstellung Hilfswerkzeuge, je Gerät gemerkt)
                    [void](Set-KeptTool 'smartmontools' $true)
                    [void](Add-ChangeRecord -Modul 'Diagnose' -Schritt 'SmartmontoolsHolen' -Titel 'smartmontools bleibt auf Wunsch installiert' -Risiko 'Eingriff' -Art 'Programm' -Ziel 'smartmontools (winget)' -Vorher 'nicht installiert' -Nachher 'installiert (behalten)' -Gegenbefehl 'winget uninstall --id smartmontools.smartmontools -e' -NurHinweis)
                    $script:SmartInstallMsg = 'per winget geholt, in den Datenordner übernommen und auf Wunsch auf diesem PC behalten'
                } else {
                    $u = Invoke-External -File $winget.Source -Arguments 'uninstall --id smartmontools.smartmontools -e --silent --accept-source-agreements --disable-interactivity' -TimeoutSec 300 -Progress 'smartmontools wird wieder deinstalliert' -ExpectedSec 30 -Encoding ([Text.Encoding]::UTF8)
                    $script:SmartInstallMsg = $(if ($u.ExitCode -eq 0) { 'per winget geholt, in den Datenordner übernommen und wieder deinstalliert' } else { 'per winget geholt und in den Datenordner übernommen, Deinstallation meldete Code ' + $u.ExitCode })
                    $script:SmartLeftInstalled = ($u.ExitCode -ne 0)
                }
                $installed = Find-Smartctl
            } catch { $script:SmartLeftInstalled = $true; $script:SmartInstallMsg = 'per winget installiert, Übernahme in den Datenordner fehlgeschlagen: ' + $_.Exception.Message }
        }
        $script:Smartctl = $installed
        if (-not $script:Smartctl) {
            $tail = (@(($r.Output + "`n" + $r.Error) -split "`r?`n" | ForEach-Object { ($_ -replace '[^\w\s\.,:;()\-/%]', '').Trim() } | Where-Object { $_.Length -gt 3 }) | Select-Object -Last 3) -join ' '
            $hex = '0x{0:X8}' -f ([int64]$r.ExitCode -band 0xFFFFFFFFL)
            if (($r.Output + ' ' + $r.Error) -match 'source reset|Quelle\(n\)|source\(s\)' -or $hex -eq '0x8A15000F') {
                # ab v2.8: kaputte Paketquelle von winget kurz benennen statt der abgeschnittenen winget-Meldung
                $script:SmartInstallMsg = ('winget kann seine Paketquelle nicht öffnen ({0}); Abhilfe: in einer Eingabeaufforderung als Administrator "winget source reset --force", danach erneut' -f $hex)
            } else { $script:SmartInstallMsg = ('winget-Rückgabecode {0} ({1}){2}' -f $r.ExitCode, $hex, $(if ($tail) { ': ' + $tail } else { '' })) }
            Write-Warning ('Installation von smartmontools fehlgeschlagen ({0}).' -f $script:SmartInstallMsg)
        }
    } else {
        $script:SmartInstallMsg = 'winget ist auf diesem PC nicht verfügbar'
    }
}


