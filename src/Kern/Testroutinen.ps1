#region ---------- C#-Testroutinen (RAM, CPU, Energiesparen) ----------
if ($FullLanguage -and -not $ImportOrdner -and -not $Vergleich -and -not $Rueckgaengig -and -not $SensorLive -and -not $SensorWerkzeugeHolen -and -not $SensorAufraeumen -and -not $OptimierungZustand -and -not $OptWerkzeugeHolen -and -not $SoftwareInstallieren -and -not $Dashboard -and -not $DashboardExport -and -not ('DiagDiskStress' -as [type])) {
    $csCode = @'
#>> EINBINDEN Kern\Testroutinen.cs
'@
    try { Add-CachedType 'LeosMinibench-Tests' $csCode }
    catch { Write-Warning ('C#-Testroutinen konnten nicht geladen werden: {0}' -f $_.Exception.Message) }
}
$TypesLoaded = [bool]('DiagDiskStress' -as [type])

# GPU-Rendertest (Direct3D 11) getrennt übersetzen: scheitert er, bleiben die übrigen Testroutinen verfügbar
if ($FullLanguage -and $TypesLoaded -and -not ('DiagGpu' -as [type])) {
    $gpuCode = @'
#>> EINBINDEN Kern\Grafiktest.cs
'@
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
        Add-CachedType 'LeosMinibench-Grafik' $gpuCode @([Windows.Forms.Form].Assembly.Location, [Drawing.Bitmap].Assembly.Location)
    } catch { Write-Warning ('GPU-Rendertest konnte nicht geladen werden: {0}' -f $_.Exception.Message) }
}
$GpuTypesLoaded = [bool]('DiagGpu' -as [type])

# Standby während eines Laufs verhindern (Bildschirm darf ausgehen). Zurückgesetzt wird am Ende (Abschluss), bei
# Abbruch über die Oberfläche beendet Windows die Sperre mit dem Prozess, ebenso nach einem Absturz.
$script:StandbyText = 'nicht gesetzt (C#-Routinen nicht verfügbar)'
function Start-StandbyLock {
    if (-not $TypesLoaded) { return }
    try { [void][DiagPower]::Begin('Leos Minibench: Diagnose, Benchmark oder Lasttest läuft'); $script:StandbyText = [DiagPower]::State } catch { $script:StandbyText = 'nicht gesetzt: ' + $_.Exception.Message }
}
function Stop-StandbyLock([switch]$Quiet) {
    if (-not $TypesLoaded) { return }
    $was = $false; try { $was = [bool][DiagPower]::Active; [DiagPower]::End() } catch { }
    if ($was -and -not $Quiet) { Write-Host '  Standby-Sperre aufgehoben, Windows darf wieder in den Standby wechseln.' }
}
# kurz aussetzen, damit Messungen wie powercfg /energy die eigene Sperre nicht mitzählen
function Suspend-StandbyLock { Stop-StandbyLock -Quiet }
function Resume-StandbyLock { if ($TypesLoaded) { try { [void][DiagPower]::Begin('Leos Minibench: Diagnose, Benchmark oder Lasttest läuft') } catch { } } }
Start-StandbyLock

# Unterbrechungen der Last messen (ab v2.66, DiagPause): belegt im Bericht, ob CPU-, RAM- und Grafiklast gleichmäßig liefen
function Start-PauseWatch { if ($TypesLoaded -and ('DiagPause' -as [type])) { try { [DiagPause]::Start() } catch { } } }
function Stop-PauseWatch([double]$Seconds = 0, [switch]$Raw) {
    if (-not ($TypesLoaded -and ('DiagPause' -as [type]))) { return $null }
    # -Raw (ab v2.8): Rohwerte von DiagPause.Stop für eine eigene Auswertung (Benchmark je Abschnitt)
    if ($Raw) { try { return , [DiagPause]::Stop() } catch { return $null } }
    try { return (Get-PauseAssessment ([DiagPause]::Stop()) $Seconds) } catch { return $null }
}

# CPU- oder RAM-Last starten (ab v2.67 in einem eigenen PowerShell-Prozess, siehe DiagLoadHost in Testroutinen.cs).
# Startet der nicht, läuft die Last wie bis v2.66 im Arbeitsprozess (LoadJob.Note sagt warum).
# MINIBENCH_LAST_INTERN=1 erzwingt die Last im Arbeitsprozess (Vergleich, Fehlersuche).
function Start-LoadJob([string]$Mode, [int]$Seconds, [int]$Threads, [long]$RamBytes = 0, [int]$RamMax = 0, [switch]$Low) {
    $hostExe = ''; $dll = ''; $why = ''
    if ($env:MINIBENCH_LAST_INTERN) { $why = 'MINIBENCH_LAST_INTERN gesetzt' }
    else {
        $exe = $(if ($PSVersionTable.PSEdition -eq 'Core') { if ([IO.Path]::DirectorySeparatorChar -eq '\') { 'pwsh.exe' } else { 'pwsh' } } else { 'powershell.exe' })
        $p = Join-Path $PSHOME $exe
        if (Test-Path -LiteralPath $p) { $hostExe = $p } else { $why = ('{0} nicht gefunden' -f $p) }
        try { $dll = [DiagLoadHost].Assembly.Location } catch { $dll = '' }
        if (-not $dll -and -not $why) { $why = 'Bibliothek nicht als Datei zwischengespeichert (Datenordner schreibgeschützt?)' }
    }
    # eigener Ordner je Last (PID und Zeitstempel): ein gerade beendeter Lastprozess kann seine Dateien noch halten
    $dir = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'LeosMinibench') ('Last_{0}_{1}_{2}' -f $PID, $Mode, [DateTime]::UtcNow.Ticks)
    $j = [LoadJob]::Start($Mode, $hostExe, $dll, $dir, $Seconds, $Threads, $RamBytes, $RamMax, [bool]$Low)
    if (-not $j.External -and -not $j.Note -and $why) { $j.Note = ('Last im Arbeitsprozess: {0}' -f $why) }
    Write-Checkpoint 'INFO' ('Last {0}: {1}{2}' -f $Mode, $(if ($j.External) { 'eigener Prozess' } else { 'im Arbeitsprozess' }), $(if ($j.Note) { ' (' + $j.Note + ')' } else { '' }))
    return $j
}

# Zeile zu den Unterbrechungen einer Last für den Bericht; $Job = LoadJob (im eigenen Prozess gemessen) oder $null
function Get-LoadJobPauseText($Job, [double]$Seconds) {
    if (-not $Job) { return $null }
    if ($Job.External -and $Job.Pause) { return (Get-PauseAssessment $Job.Pause $Seconds) }
    return $null
}

# Bewertung: [0] Zahl ab 50 ms, [1] längste in ms, [2] Summe in ms, [3..5] GC-Läufe Gen 0, 1, 2.
# Stufe INFO ab einer Unterbrechung von 250 ms oder zusammen mehr als 2 % der Dauer.
function Get-PauseAssessment($P, [double]$Seconds = 0) {
    if ($null -eq $P -or @($P).Count -lt 6) { return $null }
    $n = [int]$P[0]; $mx = [double]$P[1]; $sum = [double]$P[2]
    $gc = ('Speicherbereinigungen Gen 0/1/2: {0}/{1}/{2}' -f [int]$P[3], [int]$P[4], [int]$P[5])
    $share = $(if ($Seconds -gt 0) { $sum / 1000.0 / $Seconds * 100.0 } else { 0.0 })
    $txt = $(if ($n -eq 0) { 'keine über 50 ms ({0})' -f $gc }
        else { '{0} über 50 ms, längste {1:N0} ms, zusammen {2:N1} s ({3})' -f $n, $mx, ($sum / 1000.0), $gc })
    [pscustomobject]@{ Anzahl = $n; MaxMs = $mx; SummeMs = $sum; Gc0 = [int]$P[3]; Gc1 = [int]$P[4]; Gc2 = [int]$P[5]; AnteilProzent = [math]::Round($share, 1)
        Text = $txt; Auffaellig = ($mx -ge 250 -or $share -gt 2) }
}
#endregion

