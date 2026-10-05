# =====================================================================================
#                          SENSOREN: Werkzeuge holen und Live-Ansicht
# =====================================================================================
# Beide Modi startet die Oberfläche als eigenen Arbeitsprozess (-EventMode). Es entsteht kein Berichtsordner.

# Sensorwerkzeuge aus den offiziellen Releases holen (Seite Sensoren, Schaltfläche "Sensorwerkzeuge holen")
if ($SensorWerkzeugeHolen) {
    $r = Install-SensorTools
    foreach ($m in $r.Meldungen) { Write-Host $m }
    foreach ($t in @($script:ToolIssues | Select-Object -Unique)) { Write-Host ('WARNUNG: ' + $t) }
    Send-GuiEvent 'RESULT' $(if ($r.Ok) { '1' } else { '0' })
    exit $(if ($r.Ok) { 0 } else { 1 })
}

# Treiberrest entfernen (die Oberfläche ruft das nach einem abgebrochenen Lauf und beim Schließen auf, wenn die
# Markierung Laufzeit\PawnIO_<PC>.txt noch da ist)
if ($SensorAufraeumen) {
    Remove-PawnIoLeftover
    $msg = @($script:SensorNotes | Select-Object -Unique)
    foreach ($m in $msg) { Write-Host $m }
    if (-not $msg.Count) { Write-Host 'Kein Treiberrest von Leos Minibench gefunden.' }
    $marker = Get-PawnIoMarker
    Send-GuiEvent 'RESULT' $(if ($marker -and (Test-Path -LiteralPath $marker)) { '0' } else { '1' })
    exit 0
}

# Live-Ansicht: sendet je Intervall alle Werte (@@SENSDEF einmal je Sensor, @@SENSVAL und @@SENSLEAD je Messung,
# @@SENSBAD für verworfene unplausible Werte). Grenzwerte laut Hersteller kommen mit der Art Grenzwert.
# Ende über stop.flag im Laufzeitordner (Schaltfläche "Beenden"), wenn die Oberfläche nicht mehr läuft, oder nach 12 Stunden.
# Den PawnIO-Treiber entfernt der Abschluss auch bei Abbruch über die Oberfläche; nach einem Absturz der nächste Start.
if ($SensorLive) {
    New-Item -ItemType Directory -Path $script:CpDir -Force -ErrorAction SilentlyContinue | Out-Null
    $stopFile = Join-Path $script:CpDir 'sensor.stop'
    Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
    $parentId = 0
    try { $parentId = [int](Get-CimInstance Win32_Process -Filter ('ProcessId = {0}' -f $PID) -ErrorAction Stop).ParentProcessId } catch { }
    Send-GuiEvent 'SENSINFO' 'Sensoren werden geöffnet ...'
    $sess = Open-SensorSession -Treiber:$SensorTreiber
    Send-GuiEvent 'SENSINFO' (Get-SensorSourceText)
    foreach ($n in $script:SensorNotes) { Write-Host $n }
    $idx = @{}
    $t0 = Get-Date
    $first = $true
    try {
        while ($true) {
            $tick = [Diagnostics.Stopwatch]::StartNew()
            $rd = Get-SensorReadings -MitDatentraeger:$first
            $first = $false
            $vals = New-Object System.Collections.Generic.List[string]
            foreach ($r in $rd) {
                if (-not $idx.ContainsKey($r.Key)) {
                    $idx[$r.Key] = $idx.Count
                    Send-GuiEvent 'SENSDEF' $idx[$r.Key] $r.Gruppe $r.Geraet $r.Art $r.Name $r.Einheit $r.Quelle
                }
                $v = Format-SensorValue $r.Wert
                if ($v) { $vals.Add(('{0}:{1}' -f $idx[$r.Key], $v)) }
                # unplausible Werte nicht anzeigen, sondern als solche kennzeichnen (@@SENSBAD|idx|Rohwert|Grund)
                elseif ($r.Status -eq 'unplausibel') { Send-GuiEvent 'SENSBAD' $idx[$r.Key] (Format-SensorValue $r.Roh) $r.Hinweis }
            }
            $el = [int]((Get-Date) - $t0).TotalSeconds
            Send-GuiEvent 'SENSVAL' $el ($vals -join ';')
            Send-SensorLead $el (Get-SensorLead $rd)
            if ($el -ge 43200) { Write-Host 'Live-Ansicht nach 12 Stunden beendet.'; break }
            $stop = $false
            while ($tick.ElapsedMilliseconds -lt $SensorIntervall) {
                Start-Sleep -Milliseconds 100
                if (Test-Path -LiteralPath $stopFile) { $stop = $true; break }
            }
            if ($stop) { break }
            if ($parentId -and -not (Get-Process -Id $parentId -ErrorAction SilentlyContinue)) { break }
        }
    } finally {
        Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
        Send-GuiEvent 'SENSINFO' 'Sensoren werden geschlossen ...'
        Close-SensorSession
        Send-GuiEvent 'SENSEND' ([string]$script:Sens.Treiber)
        # leeren Laufzeitordner nicht auf dem Stick zurücklassen
        if (-not @(Get-ChildItem -LiteralPath $script:CpDir -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $script:CpDir -Force -ErrorAction SilentlyContinue }
        $rtDir = Split-Path $script:CpDir -Parent
        if ($rtDir -and (Split-Path $rtDir -Leaf) -eq 'Laufzeit' -and -not @(Get-ChildItem -LiteralPath $rtDir -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $rtDir -Force -ErrorAction SilentlyContinue }
    }
    exit 0
}
