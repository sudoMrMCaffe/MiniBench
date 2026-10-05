# Führt alle Pester-Tests in diesem Ordner aus. Rückgabe: 0 = alles bestanden, 99 = Pester 5 fehlt, sonst Zahl der Fehlschläge.
# Aufruf über Testen.cmd oder Bauen.cmd. -Kurz zeigt nur Fehlschläge und die Summe.
# -Zusammenfassung <Datei> schreibt das Ergebnis in eine Zeile (für Stand.txt im Aktuellen Build).
# -Gesamtlauf führt unter Windows auch die Gesamtläufe aus (Lauf.Tests.ps1, einige Minuten, Attrappen statt Systemänderungen).
param([switch]$Kurz, [string]$Zusammenfassung = '', [switch]$Gesamtlauf)
if ($Gesamtlauf) { $env:MINIBENCH_GESAMTLAUF = '1' }
$pester = Get-Module Pester -ListAvailable | Where-Object { $_.Version -ge [version]'5.0' } | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    Write-Host ''
    Write-Host '  Pester 5 ist nicht installiert (Windows bringt nur Pester 3.4 mit). Einmalig in PowerShell ausführen:' -ForegroundColor Yellow
    Write-Host '    Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck' -ForegroundColor Yellow
    exit 99
}
Import-Module $pester.Path -Force
$cfg = New-PesterConfiguration
$cfg.Run.Path = $PSScriptRoot
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = $(if ($Kurz) { 'Normal' } else { 'Detailed' })
$res = Invoke-Pester -Configuration $cfg
$line = '{0} bestanden, {1} fehlgeschlagen, {2} übersprungen (Pester {3}, PowerShell {4})' -f $res.PassedCount, $res.FailedCount, $res.SkippedCount, $pester.Version, $PSVersionTable.PSVersion
if ($Zusammenfassung) { [IO.File]::WriteAllText($Zusammenfassung, $line) }
Write-Host ''
Write-Host ('  Tests: {0} bestanden, {1} fehlgeschlagen, {2} übersprungen (Pester {3})' -f $res.PassedCount, $res.FailedCount, $res.SkippedCount, $pester.Version) -ForegroundColor $(if ($res.FailedCount) { 'Red' } else { 'Green' })
exit [math]::Min(98, [int]$res.FailedCount)
