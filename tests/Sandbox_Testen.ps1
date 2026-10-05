# Testlauf in der Sandbox mit dem Nachbau der Pester-Befehle (siehe Sandbox/PesterNachbau.ps1). Liegt in tests, damit
# $PSScriptRoot in den Testdateien auf diesen Ordner zeigt.
param([string]$Files = "")
. (Join-Path $PSScriptRoot 'Sandbox/PesterNachbau.ps1')
$dir = $PSScriptRoot
$list = $(if ($Files) { ($Files -split ",") | ForEach-Object { Join-Path $dir $_ } } else { Get-ChildItem $dir -Filter '*.Tests.ps1' | Sort-Object Name | ForEach-Object FullName })
foreach ($f in $list) {
    $p0 = $global:__PS.Passed; $f0 = $global:__PS.Failed; $s0 = $global:__PS.Skipped; $t = [Diagnostics.Stopwatch]::StartNew()
    Invoke-ShimFile $f
    Write-Host ('{0,-28} {1,4} ok {2,3} fehl {3,3} übersp. {4,6:N1} s' -f [IO.Path]::GetFileName($f), ($global:__PS.Passed - $p0), ($global:__PS.Failed - $f0), ($global:__PS.Skipped - $s0), $t.Elapsed.TotalSeconds)
}
foreach ($x in $global:__PS.Fails) { Write-Host ('FEHL: ' + $x) -ForegroundColor Red }
Write-Host ('SUMME: {0} bestanden, {1} fehlgeschlagen, {2} übersprungen' -f $global:__PS.Passed, $global:__PS.Failed, $global:__PS.Skipped)
