# Startzeit von außen messen (Roadmap 2.5): Leos Minibench mehrmals starten und je Start festhalten, wann das erste
# Fenster der exe (Startfenster) und wann die Oberfläche erscheint, dazu die Schreibzugriffe auf das Laufwerk der exe.
# Für den Vergleich vorher und nachher einmal mit der exe von 2.4 und einmal mit der von 2.6 aufrufen, jeweils vom Stick.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File Startzeit_messen.ps1 -Exe E:\LeosMinibench.exe -Anzahl 5
#
# Ergebnis: Tabelle in der Konsole und Startzeit_<Version>_<Zeit>.csv neben diesem Skript. Mit -Auswertung ruft das Skript
# danach LeosMinibench.exe -StartAuswertung auf (ab 2.6), das die Phasen aus Minibench-Daten\Laufzeit\Start.log
# zusammenfasst. Zwischen den Starts wartet es, bis alle Prozesse beendet sind; die Oberfläche wird über "Fenster
# schließen" beendet, nicht hart.
param(
    [Parameter(Mandatory = $true)] [string]$Exe,
    [int]$Anzahl = 5,
    [int]$PauseSekunden = 5,
    [int]$FristSekunden = 180,
    [switch]$Auswertung
)
$ErrorActionPreference = 'Stop'
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$ver = (Get-Item -LiteralPath $Exe).VersionInfo.FileVersion
$drive = ([IO.Path]::GetPathRoot($Exe)).Substring(0, 2).ToUpperInvariant()
$art = [string](New-Object IO.DriveInfo($drive)).DriveType

function Get-Writes([string]$Drive) {
    try {
        $c = Get-CimInstance Win32_PerfRawData_PerfDisk_LogicalDisk -Filter ("Name='{0}'" -f $Drive) | Select-Object -First 1
        if ($c) { return [pscustomobject]@{ Ops = [double]$c.DiskWritesPersec; Bytes = [double]$c.DiskWriteBytesPersec } }
    } catch { }
    return $null
}

# Prozesse von Leos Minibench: die exe und ihre PowerShell-Kinder (Oberfläche, Worker)
function Get-MinibenchProcs([int]$RootId) {
    $all = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='LeosMinibench.exe'")
    $ids = New-Object System.Collections.Generic.HashSet[int]; [void]$ids.Add($RootId)
    do { $n = $ids.Count; foreach ($p in $all) { if ($ids.Contains([int]$p.ParentProcessId)) { [void]$ids.Add([int]$p.ProcessId) } } } while ($ids.Count -ne $n)
    return @($ids | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
}

$rows = @()
for ($i = 1; $i -le $Anzahl; $i++) {
    Write-Host ('Start {0} von {1} ...' -f $i, $Anzahl)
    $w0 = Get-Writes $drive
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $Exe -PassThru
    $splash = $null; $gui = $null; $guiProc = $null
    while ($sw.Elapsed.TotalSeconds -lt $FristSekunden) {
        if ($null -eq $splash) { try { $p.Refresh(); if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $splash = $sw.Elapsed.TotalMilliseconds } } catch { } }
        foreach ($c in @(Get-MinibenchProcs $p.Id | Where-Object { $_.ProcessName -eq 'powershell' })) {
            if ($c.MainWindowHandle -ne [IntPtr]::Zero -and $c.MainWindowTitle -like 'Leos Minibench*') { $gui = $sw.Elapsed.TotalMilliseconds; $guiProc = $c; break }
        }
        if ($null -ne $gui -or $p.HasExited) { break }
        Start-Sleep -Milliseconds 25
    }
    $w1 = Get-Writes $drive
    $rows += [pscustomobject]@{
        Start = $i; Version = $ver; Laufwerk = $drive; Art = $art
        Startfenster_ms = $(if ($null -ne $splash) { [math]::Round($splash) } else { $null })
        Oberflaeche_ms = $(if ($null -ne $gui) { [math]::Round($gui) } else { $null })
        Schreibvorgaenge = $(if ($w0 -and $w1) { $w1.Ops - $w0.Ops } else { $null })
        Geschrieben_KB = $(if ($w0 -and $w1) { [math]::Round(($w1.Bytes - $w0.Bytes) / 1KB) } else { $null })
    }
    # Oberfläche schließen wie ein Benutzer, dann warten, bis alles beendet ist
    if ($guiProc) { [void]$guiProc.CloseMainWindow() }
    $t = [Diagnostics.Stopwatch]::StartNew()
    while (@(Get-MinibenchProcs $p.Id).Count -and $t.Elapsed.TotalSeconds -lt 60) { Start-Sleep -Milliseconds 200 }
    foreach ($x in @(Get-MinibenchProcs $p.Id)) { try { $x.Kill() } catch { } }
    Start-Sleep -Seconds $PauseSekunden
}

$rows | Format-Table -AutoSize
$med = {
    param($v) $v = @($v | Where-Object { $null -ne $_ } | Sort-Object); if (-not $v.Count) { return 'n/v' }
    if ($v.Count % 2) { $v[[int][math]::Floor($v.Count / 2)] } else { ($v[$v.Count / 2 - 1] + $v[$v.Count / 2]) / 2 }
}
Write-Host ('Version {0} von {1} ({2}): Median Startfenster {3} ms, Oberfläche {4} ms, Schreibvorgänge je Start {5}' -f $ver, $drive, $art,
    (& $med $rows.Startfenster_ms), (& $med $rows.Oberflaeche_ms), (& $med $rows.Schreibvorgaenge))
$csv = Join-Path $PSScriptRoot ('Startzeit_{0}_{1:yyyyMMdd_HHmmss}.csv' -f $ver, (Get-Date))
$rows | Export-Csv -LiteralPath $csv -Delimiter ';' -NoTypeInformation -Encoding UTF8
Write-Host ('Gespeichert: {0}' -f $csv)
if ($Auswertung) { Start-Process -FilePath $Exe -ArgumentList '-StartAuswertung' -Wait; Write-Host 'Startauswertung.txt liegt in Minibench-Daten\Laufzeit.' }
