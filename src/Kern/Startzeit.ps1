#region ---------- Startzeit auswerten (ab v2.6, Roadmap v2.5) ----------
# Minibench-Daten\Laufzeit\Start.log: ein Block je Start der Oberfläche (geschrieben von StartLog in Start.cs)
#   START|2026-10-02 10:15:03|2.6|Stick|E:|3420
#   PHASE|0|L|Programm gestartet
#   PHASE|180|L|Startfenster sichtbar ...
# Quelle L = LeosMinibench.exe, S = Skript, O = Oberfläche (C#). ms zählen ab dem Start des exe-Prozesses.
function ConvertFrom-StartLog([string[]]$Lines) {
    $res = New-Object System.Collections.Generic.List[object]
    $cur = $null
    foreach ($l in @($Lines)) {
        $x = ([string]$l).Trim() -split '\|'
        if ($x[0] -eq 'START' -and $x.Count -ge 6) {
            $ms = 0; [void][int]::TryParse($x[5], [ref]$ms)
            $cur = [pscustomobject]@{ Zeit = $x[1]; Version = $x[2]; Ort = $x[3]; Laufwerk = $x[4]; GesamtMs = $ms; Phasen = (New-Object System.Collections.Generic.List[object]) }
            $res.Add($cur)
        }
        elseif ($x[0] -eq 'PHASE' -and $x.Count -ge 4 -and $cur) {
            $ms = 0; [void][int]::TryParse($x[1], [ref]$ms)
            $cur.Phasen.Add([pscustomobject]@{ Ms = $ms; Quelle = $x[2]; Text = (($x[3..($x.Count - 1)]) -join '|') })
        }
    }
    return $res.ToArray()
}

# eigener Median: dieser Teil läuft vor dem Grundgerüst (Sondermodus -StartAuswertung)
function Get-StartMedian($Values) {
    $v = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
    if (-not $v.Count) { return $null }
    if ($v.Count % 2) { return $v[[int][math]::Floor($v.Count / 2)] }
    return ($v[$v.Count / 2 - 1] + $v[$v.Count / 2]) / 2
}

# Phasenname ohne wechselnde Zusätze (Cache-Hinweis, Ort des Entpackens), damit gleiche Phasen zusammenfallen
function Get-StartPhaseKey([string]$Text) { return (([string]$Text) -replace '\s*\(.*\)\s*$', '').Trim() }

# Auswertung je Ort (Stick, Festplatte): Zahl der Starts, Median bis zur bedienbaren Oberfläche, je Phase der Median
# des Zeitpunkts und der Dauer seit der vorigen Phase. Rückgabe: Objekte für Tabellen und Tests.
function Get-StartAnalysis($Starts) {
    $out = @()
    foreach ($g in @($Starts | Group-Object Ort)) {
        $runs = @($g.Group)
        $phases = [ordered]@{}
        foreach ($r in $runs) {
            $prev = 0
            foreach ($p in $r.Phasen) {
                $k = Get-StartPhaseKey $p.Text
                if (-not $phases.Contains($k)) { $phases[$k] = [pscustomobject]@{ Phase = $k; Quelle = $p.Quelle; Zeitpunkte = (New-Object System.Collections.Generic.List[double]); Dauern = (New-Object System.Collections.Generic.List[double]) } }
                $phases[$k].Zeitpunkte.Add([double]$p.Ms); $phases[$k].Dauern.Add([double]($p.Ms - $prev)); $prev = $p.Ms
            }
        }
        $tot = @($runs | ForEach-Object { [double]$_.GesamtMs })
        $out += [pscustomobject]@{
            Ort = $g.Name; Starts = $runs.Count; MedianMs = (Get-StartMedian $tot); MinMs = (($tot | Measure-Object -Minimum).Minimum); MaxMs = (($tot | Measure-Object -Maximum).Maximum)
            Versionen = (@($runs | ForEach-Object { $_.Version } | Select-Object -Unique) -join ', ')
            Phasen = @($phases.Values | ForEach-Object { [pscustomobject]@{ Phase = $_.Phase; Quelle = $_.Quelle; ZeitpunktMs = (Get-StartMedian $_.Zeitpunkte); DauerMs = (Get-StartMedian $_.Dauern) } })
        }
    }
    return $out
}

function Format-StartAnalysis($Analysis) {
    $l = New-Object System.Collections.Generic.List[string]
    $inv = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
    foreach ($a in @($Analysis)) {
        $l.Add(('Start von {0}: {1} Start(s), Version {2}, bis zur bedienbaren Oberfläche Median {3} s (min {4} s, max {5} s)' -f $a.Ort, $a.Starts, $a.Versionen, ([double]$a.MedianMs / 1000).ToString('0.00', $inv), ([double]$a.MinMs / 1000).ToString('0.00', $inv), ([double]$a.MaxMs / 1000).ToString('0.00', $inv)))
        $l.Add(('  {0,-48} {1,10} {2,10}' -f 'Phase', 'ab Start', 'Dauer'))
        foreach ($p in $a.Phasen) {
            $l.Add(('  {0,-48} {1,10} {2,10}' -f ('{0} ({1})' -f $p.Phase, $(switch ($p.Quelle) { 'L' { 'exe' } 'S' { 'Skript' } 'O' { 'Oberfläche' } default { $p.Quelle } })), ('{0} s' -f ([double]$p.ZeitpunktMs / 1000).ToString('0.00', $inv)), ('{0} s' -f ([double]$p.DauerMs / 1000).ToString('0.00', $inv))))
        }
        $l.Add('')
    }
    if (-not $l.Count) { $l.Add('Noch keine Starts protokolliert (Start.log entsteht beim Start über LeosMinibench.exe ab Version 2.6).') }
    return $l.ToArray()
}

# Sondermodus -StartAuswertung: Auswertung von Start.log ausgeben und als Startauswertung.txt ablegen
if ($StartAuswertung) {
    $sl = $(if ($script:DataDir) { Join-Path (Join-Path $script:DataDir 'Laufzeit') 'Start.log' } else { '' })
    $lines = @(if ($sl -and (Test-Path -LiteralPath $sl)) { Get-Content -LiteralPath $sl -Encoding UTF8 })
    $txt = Format-StartAnalysis (Get-StartAnalysis (ConvertFrom-StartLog $lines))
    foreach ($t in $txt) { Write-Host $t }
    if ($sl) { try { [IO.File]::WriteAllLines((Join-Path (Split-Path $sl -Parent) 'Startauswertung.txt'), $txt, (New-Object Text.UTF8Encoding($true))) } catch { } }
    exit 0
}
#endregion
