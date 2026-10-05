# Version 2.6 (mit den Punkten der Roadmap v2.5): Korrekturen aus dem Praxistest vom 02.10.2026, GPU-Rendertest,
# schneller Modus, Startzeit, lokaler Arbeitsordner und gedrosselte Schreibzugriffe auf den Stick.
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Parts 'Kern\Grafiktest.ps1', 'Kern\Startzeit.ps1', 'Kern\Parallel.ps1' `
        -Functions 'Get-GpuKind', 'Test-LaptopGpu', 'Register-BadReadings', 'ConvertTo-FlatReadings', 'Get-DiskStressBytes', 'Get-Median', 'Get-StatusRank', 'New-RunWorkDir', 'Restore-StaleWorkDirs', 'Get-WriteDelta',
                   'Write-Checkpoint', 'Flush-Checkpoint', 'Write-Durable', 'Save-Partial', 'Get-BugcheckName', 'Test-MemoryBugcheck', 'Test-TempEntryStale', 'Get-ModuleContract', 'Test-ModuleContract', 'Get-RiskRank', 'Send-GuiEvent', 'New-SensorReading' -Setup @'
$script:Findings = New-Object System.Collections.Generic.List[object]
function Add-Finding { param([string]$Level, [string]$Area, [string]$Text) $script:Findings.Add([pscustomobject]@{ Stufe = $Level; Bereich = $Area; Befund = $Text }) }
function Write-Step { param([string]$Text) }
function Show-Sub { param($a, $b, $c) }
function Hide-Sub { }
$script:EvList = @()
function Get-Ev { param([hashtable]$Filter, [int]$Max = 1000) @($script:EvList) }
$script:RiskOrder = @('Lesen', 'Aendern', 'Eingriff', 'Zerstoerend')
$script:RestartOrder = @('nie', 'moeglich', 'immer')
$script:UndoKinds = @('keins', 'Protokoll', 'Wiederherstellungspunkt', 'Hinweis')
$script:ContractCoreDbFields = @('Format', 'Name', 'Computer', 'Geraet', 'Datum', 'Version', 'Quelle', 'Module', 'Ordner', 'Schreibzugriffe', 'Ablauf')
$script:CpStream = $null
$script:CpBuffer = New-Object System.Text.StringBuilder
$script:CpLastFlush = [datetime]::MinValue
$script:CpWrites = 0
$script:PartialLast = [datetime]::MinValue
$script:PartialWrites = 0
$script:Report = New-Object System.Text.StringBuilder
$script:CpCurrent = 'Test'
'@
    $global:V26Contracts = @{}
    foreach ($n in 'Diagnose', 'Benchmark', 'Lasttest') { $global:V26Contracts[$n] = Import-PowerShellDataFile -LiteralPath (Join-Path $global:MinibenchSrcRoot ('Module/{0}/Vertrag.psd1' -f $n)) }
}

Describe 'Praxistest 02.10.2026: Lasttest Datenträger (Testdatei)' {
    It 'Größe der Testdatei für <Frei> freie Bytes ist <Erwartet>' -ForEach @(
        @{ Frei = 500GB; Erwartet = 4GB }
        @{ Frei = 3GB; Erwartet = [long](3GB * 0.1) }
        @{ Frei = 1GB; Erwartet = 256MB }
        @{ Frei = 4TB; Erwartet = 4GB }
    ) {
        MinibenchTest\Get-DiskStressBytes $Frei | Should -Be $Erwartet
    }
    It 'Lasttest nutzt die Funktion statt [math]::Max(256MB, ...) mit gemischten Typen' {
        $t = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Lasttest/Ablauf.ps1'))
        $t | Should -Match 'Get-DiskStressBytes'
        $t | Should -Not -Match '\[math\]::Max\(256MB'
    }
}

Describe 'Praxistest 02.10.2026: unplausible Sensorwerte zählen (CPU-Lasttest brach ab)' {
    BeforeEach { $script:seen = @{} }
    It 'zählt je Sensor und behält den höchsten Rohwert' {
        $r1 = MinibenchTest\New-SensorReading 'k1' 'LHM' 'GPU' 'Intel(R) Iris(R) Xe Graphics' 'Leistung' 'GPU Package' 'W' 590
        $r1.Status = 'unplausibel'; $r1.Roh = 590; $r1.Wert = [double]::NaN
        $r2 = MinibenchTest\New-SensorReading 'k1' 'LHM' 'GPU' 'Intel(R) Iris(R) Xe Graphics' 'Leistung' 'GPU Package' 'W' 610
        $r2.Status = 'unplausibel'; $r2.Roh = 610; $r2.Wert = [double]::NaN
        $ok = MinibenchTest\New-SensorReading 'k2' 'LHM' 'CPU' 'CPU' 'Temperatur' 'CPU Package' '°C' 55
        MinibenchTest\Register-BadReadings @($r1, $ok) $script:seen
        MinibenchTest\Register-BadReadings @($r2) $script:seen
        $script:seen.Count | Should -Be 1
        $e = @($script:seen.Values)[0]
        $e.Anzahl | Should -Be 2; $e.Max | Should -Be 610; $e.Geraet | Should -Be 'Intel(R) Iris(R) Xe Graphics'
    }
    It 'übersteht Einträge ohne Gerät, ohne Namen und ohne Rohwert' {
        $r = [pscustomobject]@{ Geraet = $null; Name = $null; Art = 'Leistung'; Hinweis = ''; Status = 'unplausibel'; Roh = $null }
        { MinibenchTest\Register-BadReadings @($r, $r, $null) $script:seen } | Should -Not -Throw
        @($script:seen.Values)[0].Anzahl | Should -Be 2
    }
    It 'Lasttest führt die Zählung in einer Skriptvariablen und ohne Zuweisung an $tabelle[$k].Anzahl' {
        $t = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Lasttest/Ablauf.ps1'))
        $t | Should -Match 'Register-BadReadings \$rd \$script:LoadBadSeen'
        $t | Should -Not -Match '\]\.Anzahl\+\+'
    }
}

Describe 'Praxistest 02.10.2026: Sensoren hängen beim Öffnen' {
    It 'Öffnen und Lesen haben ein Zeitlimit' {
        $cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Sensoren.cs'))
        $cs | Should -Match 'public static bool OpenTimed\('
        $cs | Should -Match 'public static SensorReading\[\] ReadTimed\('
        $ps = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Sensoren.ps1'))
        $ps | Should -Match '\[DiagSensors\]::OpenTimed\('
        $ps | Should -Match '\[DiagSensors\]::ReadTimed\('
        $ps | Should -Not -Match '\[DiagSensors\]::Open\(\$tools'
    }
}

Describe 'Rendertest: Einstellungen' {
    It 'Auflösung <Text> ergibt <B>x<H>' -ForEach @(
        @{ Text = '1280x720'; B = 1280; H = 720 }, @{ Text = '1920x1080'; B = 1920; H = 1080 }, @{ Text = ' 1920 x 1080 '; B = 1920; H = 1080 }
        @{ Text = 'unsinn'; B = 1280; H = 720 }, @{ Text = '10x10'; B = 1280; H = 720 }, @{ Text = ''; B = 1280; H = 720 }
    ) {
        $r = MinibenchTest\Get-RenderSize $Text
        $r[0] | Should -Be $B; $r[1] | Should -Be $H
    }
    It 'Anzeige <Text> ergibt Modus <M>' -ForEach @(
        @{ Text = 'Fenster'; M = 1 }, @{ Text = 'Vollbild'; M = 2 }, @{ Text = 'Aus'; M = 0 }, @{ Text = 'ohne'; M = 0 }, @{ Text = ''; M = 1 }
    ) {
        MinibenchTest\Get-RenderPreviewMode $Text | Should -Be $M
    }
}

Describe 'Rendertest: Grafikeinheiten' {
    BeforeAll {
        function New-Ad($i, $n, $v, $luid, [bool]$sw = $false) { [pscustomobject]@{ Index = $i; Name = $n; VendorId = $v; Vendor = $(switch ($v) { 0x10DE { 'NVIDIA' } 0x8086 { 'Intel' } 0x1002 { 'AMD' } 0x1414 { 'Microsoft' } default { '' } }); DedicatedMB = 4096; Luid = $luid; Software = $sw } }
    }
    It 'Notebook mit Hybridgrafik: Grafikkarte zuerst, beide werden getestet, WARP entfällt' {
        $raw = @((New-Ad 0 'Intel(R) Iris(R) Xe Graphics' 0x8086 11), (New-Ad 1 'NVIDIA RTX 3000 Ada Generation Laptop GPU' 0x10DE 12), (New-Ad 2 'Microsoft Basic Render Driver' 0x1414 13 $true))
        $a = @(MinibenchTest\Get-RenderAdapters $raw)
        $a.Count | Should -Be 2
        $a[0].Name | Should -Be 'NVIDIA RTX 3000 Ada Generation Laptop GPU'; $a[0].Art | Should -Be 'dGPU'; $a[0].Bezeichnung | Should -Be 'Grafikkarte'; $a[0].Index | Should -Be 1
        $a[1].Art | Should -Be 'iGPU'; $a[1].Bezeichnung | Should -Be 'Prozessorgrafik'
    }
    It 'doppelte Adapter (gleiche LUID) und virtuelle Adapter zählen nicht' {
        $raw = @((New-Ad 0 'AMD Radeon RX 6800' 0x1002 5), (New-Ad 1 'AMD Radeon RX 6800' 0x1002 5), (New-Ad 2 'Microsoft Remote Display Adapter' 0 6))
        $a = @(MinibenchTest\Get-RenderAdapters $raw)
        $a.Count | Should -Be 1; $a[0].Art | Should -Be 'dGPU'
    }
    It 'ohne Hardware (Remotedesktop): leer' {
        @(MinibenchTest\Get-RenderAdapters @((New-Ad 0 'Microsoft Basic Render Driver' 0x1414 1 $true))).Count | Should -Be 0
    }
}

Describe 'Rendertest: Kennzahlen' {
    BeforeAll {
        # Kennzahlen aus Grafiktest.cs (ohne Direct3D und WinForms übersetzbar)
        if (-not ('GpuStatsTest' -as [type])) {
            $cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Grafiktest.cs'))
            $m = [regex]::Match($cs, '(?s)    public static double\[\] Stats\(.*?\n    }\r?\n')
            $f = [regex]::Match($cs, '(?s)    public static ulong Fnv\(.*?\n    }\r?\n')
            Add-Type -TypeDefinition ('using System; public static class GpuStatsTest {' + $m.Value + $f.Value + '}')
        }
    }
    It 'Ø Bilder/s, 1-%-Low, Median, 99 %, längste Bildzeit und Punktzahl' {
        # 1000 Bilder: 990 x 10 ms, 10 x 50 ms (Ruckler) in 10,4 s
        $f = [float[]](@(1..990 | ForEach-Object { 10.0 }) + @(1..10 | ForEach-Object { 50.0 }))
        $r = [GpuStatsTest]::Stats($f, 10.4, 1280, 720)
        [math]::Round($r[0], 2) | Should -Be ([math]::Round(1000 / 10.4, 2))
        $r[1] | Should -Be 20          # langsamste 1 % = 10 Bilder mit 50 ms
        $r[2] | Should -Be 10
        $r[3] | Should -Be 10          # 99. Perzentil (990. von 1000)
        $r[4] | Should -Be 50
        [math]::Round($r[5]) | Should -Be ([math]::Round(1000 / 10.4 * 1280 * 720 / 10000))
    }
    It 'leere Messung ergibt Nullen' {
        @([GpuStatsTest]::Stats([float[]]@(), 0, 1280, 720)) | Should -Be @(0, 0, 0, 0, 0, 0, 0, 0)
    }
    It 'Prüfsumme des Referenzbilds unterscheidet sich schon bei einem Byte' {
        $a = [byte[]](1..100); $b = [byte[]](1..100); $b[50] = 0
        [GpuStatsTest]::Fnv($a, 100, 14695981039346656037) | Should -Not -Be ([GpuStatsTest]::Fnv($b, 100, 14695981039346656037))
        [GpuStatsTest]::Fnv($a, 100, 14695981039346656037) | Should -Be ([GpuStatsTest]::Fnv($a, 100, 14695981039346656037))
    }
    It 'Bildzeiten werden für Diagramme verdichtet, Ruckler bleiben sichtbar' {
        $f = @(1..10000 | ForEach-Object { 4.0 }); $f[5000] = 120.0
        $p = @(MinibenchTest\Get-FrameTimePoints $f 400)
        $p.Count | Should -BeLessOrEqual 400
        ($p | Measure-Object V -Maximum).Maximum | Should -Be 120
        [math]::Round($p[$p.Count - 1].T) | Should -Be 40
    }
    It 'Abfall der Bilder/s über den Lasttest: <Erwartet>' -ForEach @(
        @{ Werte = @(1..300 | ForEach-Object { 100 }); Erwartet = 0 }
        @{ Werte = @(@(1..150 | ForEach-Object { 100 }) + @(1..150 | ForEach-Object { 80 })); Erwartet = 20 }
        @{ Werte = @(1..30 | ForEach-Object { 100 }); Erwartet = $null }
    ) {
        MinibenchTest\Get-FpsDrop $Werte | Should -Be $Erwartet
    }
}

Describe 'Rendertest: Befunde' {
    BeforeEach { & (Get-Module MinibenchTest) { $script:Findings.Clear() } }
    BeforeAll {
        function New-Res([bool]$Ok = $true, [bool]$Reset = $false, [int]$Bild = 0, [string]$Fehler = '') {
            [pscustomobject]@{ Name = 'NVIDIA GeForce RTX 3060'; Bezeichnung = 'Grafikkarte'; Ok = $Ok; Treiberreset = $Reset; ResetGrund = $(if ($Reset) { '0x887A0006 DXGI_ERROR_DEVICE_HUNG' } else { '' }); Bildfehler = $Bild; Bildpruefungen = 4; Fehler = $Fehler }
        }
    }
    It 'fehlerfreier Lauf: OK ohne Befund' {
        MinibenchTest\Add-RenderFindings (New-Res) 'Rendertests' @() | Should -Be 'OK'
        (Get-ModuleVar 'Findings').Count | Should -Be 0
    }
    It 'Treiber-Reset: Warnung und Status Fehler' {
        MinibenchTest\Add-RenderFindings (New-Res -Ok $false -Reset $true -Fehler 'GetData') 'Lasttests' @() | Should -Be 'Fehler'
        @(Get-ModuleVar 'Findings')[0].Befund | Should -Match 'Treiber-Reset \(TDR\) während des Lasttests auf NVIDIA GeForce RTX 3060 \(Grafikkarte\): Direct3D meldet 0x887A0006'
    }
    It 'Ereignis 4101 ohne Fehler im Renderer zählt ebenfalls als Treiber-Reset' {
        $ev = [pscustomobject]@{ Id = 4101; Message = 'Der Anzeigetreiber nvlddmkm reagiert nicht mehr und wurde wiederhergestellt.' }
        MinibenchTest\Add-RenderFindings (New-Res) 'Rendertests' @($ev) | Should -Be 'Fehler'
        @(Get-ModuleVar 'Findings')[0].Befund | Should -Match '1x Ereignis 4101'
    }
    It 'Bildfehler: Warnung' {
        MinibenchTest\Add-RenderFindings (New-Res -Bild 2) 'Lasttests' @() | Should -Be 'Fehler'
        @(Get-ModuleVar 'Findings')[0].Befund | Should -Match '2 von 4 Prüfbildern'
    }
    It 'nicht möglich (ohne Reset): Hinweis, kein Fehler' {
        MinibenchTest\Add-RenderFindings (New-Res -Ok $false -Fehler 'D3D11CreateDevice fehlgeschlagen') 'Rendertests' @() | Should -Be 'Info'
        @(Get-ModuleVar 'Findings')[0].Stufe | Should -Be 'INFO'
    }
    It 'Ereignisse 4101 werden der Grafikeinheit nach Treibername zugeordnet' {
        $ev = @([pscustomobject]@{ Message = 'Der Anzeigetreiber nvlddmkm reagiert nicht mehr' }, [pscustomobject]@{ Message = 'Der Anzeigetreiber igfx reagiert nicht mehr' }, [pscustomobject]@{ Message = 'Der Anzeigetreiber unbekannt reagiert nicht mehr' })
        $nv = [pscustomobject]@{ Name = 'NVIDIA RTX 3000 Ada'; Hersteller = 'NVIDIA' }
        $in = [pscustomobject]@{ Name = 'Intel(R) Iris(R) Xe Graphics'; Hersteller = 'Intel' }
        @(MinibenchTest\Select-TdrEvents $ev $nv $true).Count | Should -Be 2
        @(MinibenchTest\Select-TdrEvents $ev $in $false).Count | Should -Be 1
    }
}

Describe 'Rendertest im Quelltext' {
    It 'Benchmark misst jede Grafikeinheit und Lasttest belastet alle gleichzeitig' {
        $b = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Benchmark/Ablauf.ps1'))
        $b | Should -Match 'Invoke-RenderBenchmark \$rAds'
        $l = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Lasttest/Ablauf.ps1'))
        $l | Should -Match 'foreach \(\$ad in \$gAds\)'
        $l | Should -Not -Match 'winsat\.exe'
    }
    It 'Vtable-Plätze stimmen mit d3d11.h überein' {
        $cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Grafiktest.cs'))
        foreach ($kv in @(@('V_Dev_CreateTexture2D', 5), @('V_Dev_CreateRenderTargetView', 9), @('V_Dev_CreatePixelShader', 15), @('V_Dev_CreateQuery', 24), @('V_Dev_GetDeviceRemovedReason', 39),
                          @('V_Ctx_Draw', 13), @('V_Ctx_Map', 14), @('V_Ctx_GetData', 29), @('V_Ctx_OMSetRenderTargets', 33), @('V_Ctx_RSSetViewports', 44), @('V_Ctx_CopyResource', 47), @('V_Ctx_Flush', 111))) {
            $cs | Should -Match ('{0} = {1}\b' -f $kv[0], $kv[1])
        }
    }
    It 'Metrik-Definitionen für Datenbank und Vergleich' {
        $t = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Referenz_Vergleich.ps1'))
        foreach ($k in 'GPU|REND', 'GPU|REND1', 'GPU|RPKT') { $t | Should -Match ([regex]::Escape("K = '$k'")) }
    }
}

Describe 'Schneller Modus: Modulvertrag' {
    It 'Diagnose: Updatesuche, Defender, SMART-Start und Energieanalyse parallel, Messungen exklusiv' {
        $s = @{}; foreach ($x in $global:V26Contracts['Diagnose'].Schritte) { $s[$x.Key] = $x }
        foreach ($k in 'Updatesuche', 'Defender', 'SmartLang', 'Energieanalyse') { $s[$k].Parallel | Should -BeTrue -Because $k }
        foreach ($k in 'RamTest', 'Netzwerk') { $s[$k].Exklusiv | Should -BeTrue -Because $k }
        # ab v2.7 ohne CPU-Stabilitätstest (Modul Lasttest)
        $s.ContainsKey('CpuTest') | Should -BeFalse
        $s['Energieanalyse'].Nach | Should -Contain 'Defender'
    }
    It 'Benchmark und Lasttest: alle Schritte exklusiv' {
        foreach ($n in 'Benchmark', 'Lasttest') { foreach ($x in $global:V26Contracts[$n].Schritte) { if ($x.Typ -ne 'Option') { $x.Exklusiv | Should -BeTrue -Because ('{0}/{1}' -f $n, $x.Key) } } }
    }
    It 'Prüfung meldet <Fall>' -ForEach @(
        @{ Fall = 'unbekannte Abhängigkeit'; Steps = @(@{ Key = 'A'; Typ = 'Pruefung'; Titel = 'A'; Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Parallel = $true; Nach = @('X') }); Muster = 'unbekannten Schritt X' }
        @{ Fall = 'Kreis'; Steps = @(@{ Key = 'A'; Typ = 'Pruefung'; Titel = 'A'; Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Nach = @('B') }, @{ Key = 'B'; Typ = 'Pruefung'; Titel = 'B'; Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Nach = @('A') }); Muster = 'Kreis' }
        @{ Fall = 'parallel und exklusiv'; Steps = @(@{ Key = 'A'; Typ = 'Pruefung'; Titel = 'A'; Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Parallel = $true; Exklusiv = $true }); Muster = 'zugleich parallel und exklusiv' }
        @{ Fall = 'parallel mit Änderung'; Steps = @(@{ Key = 'A'; Typ = 'Pruefung'; Titel = 'A'; Risiko = 'Aendern'; Neustart = 'nie'; Rueckgaengig = 'Protokoll'; Parallel = $true }); Muster = 'nur lesende Schritte' }
    ) {
        $c = @{ Vertrag = 1; Name = 'Probe'; Seite = @{ Titel = 'P'; Kurz = 'p' }; Admin = $true; Risiko = $(if (@($Steps | Where-Object { $_.Risiko -eq 'Aendern' }).Count) { 'Aendern' } else { 'Lesen' }); Neustart = 'nie'; Parameter = @(); Datenbankfelder = @(); Schritte = $Steps }
        (@(MinibenchTest\Test-ModuleContract $c) -join ' ') | Should -Match $Muster
    }
    It 'die echten Verträge sind gültig' {
        foreach ($n in 'Diagnose', 'Benchmark', 'Lasttest') { @(MinibenchTest\Test-ModuleContract $global:V26Contracts[$n]) | Should -BeNullOrEmpty -Because $n }
    }
}

Describe 'Schneller Modus: Ablaufsteuerung' {
    It 'Abschnittstitel werden Schritten zugeordnet' -ForEach @(
        @{ T = 'Test: Arbeitsspeicher (Mustertest)'; K = 'RamTest' }, @{ T = 'Energie'; K = 'Energieanalyse' }
        @{ T = 'Benchmark: Grafik'; K = 'Messung' }, @{ T = 'Lasttest (CPU 5 Min.)'; K = 'Messung' }, @{ T = 'Prozessor'; K = '' }, @{ T = 'Updates'; K = 'Updatesuche' }
    ) {
        MinibenchTest\Get-SectionStepKey $T | Should -Be $K
    }
    It 'Abhängigkeiten, die in diesem Lauf nicht vorkommen, gelten als erfüllt' {
        & (Get-Module MinibenchTest) { $script:Opt = @{ Defender = $true; Energieanalyse = $true }; $script:DefenderActive = $false }
        @(MinibenchTest\Get-ActiveDeps @('Defender')).Count | Should -Be 0
        & (Get-Module MinibenchTest) { $script:DefenderActive = $true }
        @(MinibenchTest\Get-ActiveDeps @('Defender')) | Should -Be @('Defender')
    }
    It 'Hintergrundaufgaben laufen parallel, Abhängigkeiten warten, die Sperre wartet auf alle' {
        & (Get-Module MinibenchTest) {
            $script:FastMode = $true; $script:BgJobs = [ordered]@{}; $script:BgDone.Clear()
            [void](Register-BgJob -Key 'A' -Title 'Aufgabe A' -Script { Start-Sleep -Milliseconds 600; 'a' })
            [void](Register-BgJob -Key 'B' -Title 'Aufgabe B' -Nach @('A') -Script { 'b' })
            [void](Register-BgJob -Key 'C' -Title 'Aufgabe C' -Script { param($x) $x * 2 } -Arguments @(21))
        }
        $jobs = Get-ModuleVar 'BgJobs'
        $jobs['A'].Status | Should -Be 'läuft'
        $jobs['B'].Status | Should -Be 'wartet'
        & (Get-Module MinibenchTest) { Wait-BgAll 'den Test' }
        $jobs['A'].Status | Should -Be 'fertig'; $jobs['B'].Status | Should -Be 'fertig'; $jobs['C'].Status | Should -Be 'fertig'
        $jobs['C'].Ergebnis | Should -Be 42
        $jobs['B'].Start | Should -BeGreaterOrEqual $jobs['A'].Ende
        & (Get-Module MinibenchTest) { Stop-BgJobs; $script:FastMode = $false; $script:BgJobs = [ordered]@{} }
    }
    It 'Fehler einer Hintergrundaufgabe brechen nichts ab' {
        & (Get-Module MinibenchTest) {
            $script:FastMode = $true; $script:BgJobs = [ordered]@{}; $script:BgDone.Clear()
            [void](Register-BgJob -Key 'X' -Title 'kaputt' -Script { throw 'geht nicht' })
            $script:XJob = Wait-BgJob 'X' '' 30
            Stop-BgJobs; $script:FastMode = $false; $script:BgJobs = [ordered]@{}
        }
        $j = Get-ModuleVar 'XJob'
        $j.Status | Should -Be 'Fehler'; $j.Fehler | Should -Match 'geht nicht'
        MinibenchTest\Get-BgNote $j | Should -Match 'Meldung: .*geht nicht'
    }
    It 'ohne schnellen Modus wird nichts angemeldet' {
        & (Get-Module MinibenchTest) { $script:FastMode = $false; $script:BgJobs = [ordered]@{}; $script:Reg = Register-BgJob -Key 'Y' -Title 'y' -Script { 1 } }
        Get-ModuleVar 'Reg' | Should -BeFalse
        (Get-ModuleVar 'BgJobs').Count | Should -Be 0
    }
}

Describe 'Startzeit (Start.log)' {
    BeforeAll {
        $script:log = @(
            'START|2026-10-02 10:00:00|2.6|Stick|E:|4200', 'PHASE|0|L|Programm gestartet', 'PHASE|300|L|Startfenster sichtbar', 'PHASE|900|L|Skript entpackt (lokales TEMP)', 'PHASE|1000|L|PowerShell gestartet',
            'PHASE|2600|S|PowerShell bereit, Skript läuft', 'PHASE|3100|S|Oberfläche geladen (LeosMinibench-Oberflaeche aus dem Cache)', 'PHASE|4200|O|Oberfläche bereit',
            'START|2026-10-02 10:05:00|2.6|Stick|E:|3800', 'PHASE|0|L|Programm gestartet', 'PHASE|200|L|Startfenster sichtbar', 'PHASE|800|L|Skript entpackt (lokales TEMP)', 'PHASE|900|L|PowerShell gestartet',
            'PHASE|2300|S|PowerShell bereit, Skript läuft', 'PHASE|2800|S|Oberfläche geladen (LeosMinibench-Oberflaeche übersetzt und zwischengespeichert)', 'PHASE|3800|O|Oberfläche bereit',
            'START|2026-10-02 11:00:00|2.6|Festplatte|C:|1500', 'PHASE|0|L|Programm gestartet', 'PHASE|120|L|Startfenster sichtbar', 'PHASE|1500|O|Oberfläche bereit',
            'Müll', 'PHASE|kaputt'
        )
    }
    It 'liest Blöcke und Phasen' {
        $s = @(MinibenchTest\ConvertFrom-StartLog $script:log)
        $s.Count | Should -Be 3
        $s[0].Ort | Should -Be 'Stick'; $s[0].GesamtMs | Should -Be 4200; $s[0].Phasen.Count | Should -Be 7
        $s[2].Phasen.Count | Should -Be 3
    }
    It 'wertet je Ort mit Median aus und fasst Phasen mit wechselnden Zusätzen zusammen' {
        $a = @(MinibenchTest\Get-StartAnalysis (MinibenchTest\ConvertFrom-StartLog $script:log))
        $stick = $a | Where-Object Ort -eq 'Stick'
        $stick.Starts | Should -Be 2; $stick.MedianMs | Should -Be 4000
        $p = $stick.Phasen | Where-Object Phase -eq 'Oberfläche geladen'
        $p.ZeitpunktMs | Should -Be 2950; $p.DauerMs | Should -Be 500
        ($stick.Phasen | Where-Object Phase -eq 'Startfenster sichtbar').ZeitpunktMs | Should -Be 250
        ($a | Where-Object Ort -eq 'Festplatte').MedianMs | Should -Be 1500
    }
    It 'Text für die Ausgabe' {
        $t = (MinibenchTest\Format-StartAnalysis (MinibenchTest\Get-StartAnalysis (MinibenchTest\ConvertFrom-StartLog $script:log))) -join "`n"
        $t | Should -Match 'Start von Stick: 2 Start\(s\), Version 2\.6, bis zur bedienbaren Oberfläche Median 4,00 s'
        $t | Should -Match 'Startfenster sichtbar \(exe\)\s+0,25 s'
        (MinibenchTest\Format-StartAnalysis @()) | Should -Match 'Noch keine Starts'
    }
    It 'Startfenster der exe und Startprotokoll der Oberfläche sind eingebaut' {
        $b = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'))
        $b | Should -Match 'class Splash : Form'
        $b | Should -Match 'LEOSMINIBENCH_BEREIT'
        $b | Should -Match 'Path.GetTempPath\(\), "LeosMinibench"'
        $g = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui.cs'))
        $g | Should -Match 'StartLog.SignalReady\(\)'
        $g | Should -Match 'AppSymbol.SetAppId\(\)'
        Join-Path $global:MinibenchSrcRoot 'Oberflaeche/Symbol.ico' | Should -Exist
    }
    It 'Symbol enthält 16, 24, 32, 48, 64, 128 und 256 Pixel' {
        $b = [IO.File]::ReadAllBytes((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/Symbol.ico'))
        $n = [BitConverter]::ToUInt16($b, 4)
        $sizes = @(for ($i = 0; $i -lt $n; $i++) { $w = $b[6 + 16 * $i]; if ($w -eq 0) { 256 } else { [int]$w } }) | Sort-Object
        $sizes | Should -Be @(16, 24, 32, 48, 64, 128, 256)
    }
}

Describe 'Stick schonen: lokaler Arbeitsordner, gedrosselte Schreibzugriffe' {
    It 'Arbeitsordner im lokalen TEMP mit Ziel.txt' {
        $d = MinibenchTest\New-RunWorkDir 'X:\Berichte\PC_1'
        try {
            $d | Should -Match 'LeosMinibench[\\/]Lauf_\d+$'
            Join-Path $d 'Anhang' | Should -Exist
            [IO.File]::ReadAllText((Join-Path $d 'Ziel.txt')) | Should -Be 'X:\Berichte\PC_1'
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'Arbeitsordner eines abgebrochenen Laufs: Rohdaten gesichert, Ordner entfernt' {
        $base = Join-Path ([IO.Path]::GetTempPath()) 'LeosMinibench'
        $dead = Join-Path $base 'Lauf_999999'
        $tgt = Join-Path $TestDrive 'Bericht_alt'
        New-Item -ItemType Directory -Path (Join-Path $dead 'Anhang'), $tgt -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dead 'Ziel.txt'), $tgt)
        [IO.File]::WriteAllText((Join-Path $dead 'Anhang/Konsole.log'), 'abgebrochen')
        $n = @(MinibenchTest\Restore-StaleWorkDirs)
        ($n -join ' ') | Should -Match 'Arbeitsordner eines abgebrochenen Laufs entfernt'
        $dead | Should -Not -Exist
        Join-Path $tgt 'Anhang_unterbrochen.zip' | Should -Exist
    }
    It 'Unterschied der Schreibzähler (mit Überlauf des 32-Bit-Zählers)' {
        $t = Get-Date
        $a = [pscustomobject]@{ Laufwerk = 'E:'; Vorgaenge = 4294967000; Bytes = 1000; Art = 'Removable'; Zeit = $t }
        $b = [pscustomobject]@{ Laufwerk = 'E:'; Vorgaenge = 704; Bytes = 1000 + 10MB; Art = 'Removable'; Zeit = $t.AddSeconds(90) }
        $d = MinibenchTest\Get-WriteDelta $a $b
        $d.Vorgaenge | Should -Be 1000; $d.MB | Should -Be 10; $d.Sekunden | Should -Be 90; $d.Art | Should -Match 'USB-Stick'
        MinibenchTest\Get-WriteDelta $a $null | Should -BeNullOrEmpty
    }
    It 'Checkpoints: Pulse gesammelt, Schrittwechsel sofort geschrieben' {
        $f = Join-Path $TestDrive 'cp.log'
        # Lesen mit FileShare.ReadWrite: unter Windows hält der Checkpoint-Strom die Datei zum Schreiben offen
        $readShared = { param($p) $fs = New-Object IO.FileStream($p, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite); try { (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd() } finally { $fs.Dispose() } }
        & (Get-Module MinibenchTest) { param($p) $script:CpStream = New-Object IO.FileStream($p, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite); $script:CpWrites = 0; $script:CpLastFlush = Get-Date } $f
        try {
            MinibenchTest\Write-Checkpoint 'START' 'Abschnitt'
            MinibenchTest\Write-Checkpoint 'PULS' 'Wert 1'
            MinibenchTest\Write-Checkpoint 'PULS' 'Wert 2'
            $t1 = & $readShared $f
            $t1 | Should -Match 'START'; $t1 | Should -Not -Match 'Wert 1'
            MinibenchTest\Write-Checkpoint 'OK' 'Abschnitt'
            $t2 = & $readShared $f
            $t2 | Should -Match 'Wert 1'; $t2 | Should -Match 'Wert 2'; $t2 | Should -Match '\| OK '
            Get-ModuleVar 'CpWrites' | Should -Be 2
        } finally {
            # Strom immer schließen, sonst kann Pester TestDrive nicht löschen
            & (Get-Module MinibenchTest) { if ($script:CpStream) { $script:CpStream.Close(); $script:CpStream = $null } }
        }
    }
    It 'Zwischenstand höchstens einmal je Minute, mit -Force sofort' {
        $o = Join-Path $TestDrive 'out'; New-Item -ItemType Directory -Path $o -Force | Out-Null
        & (Get-Module MinibenchTest) { param($p) $script:OutputDir = $p; Set-Variable -Name OutputDir -Value $p -Scope Script; $script:PartialLast = [datetime]::MinValue; $script:PartialWrites = 0 } $o
        MinibenchTest\Save-Partial; MinibenchTest\Save-Partial; MinibenchTest\Save-Partial
        Get-ModuleVar 'PartialWrites' | Should -Be 1
        MinibenchTest\Save-Partial -Force
        Get-ModuleVar 'PartialWrites' | Should -Be 2
        Join-Path $o 'Diagnosebericht_teilweise.txt' | Should -Exist
    }
}

Describe 'Codeprüfung 2.6: gefunden und behoben' {
    BeforeAll {
        if (-not ('GpuHistTest' -as [type])) {
            $cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Grafiktest.cs'))
            $m = [regex]::Match($cs, '(?s)    public static double\[\] Stats\(.*?\n    }\r?\n')
            $h = [regex]::Match($cs, '(?s)    // Histogramm der Bildzeiten: Klasse k.*?    public static double\[\] StatsHist\(.*?\n    }\r?\n')
            Add-Type -TypeDefinition ('using System; public static class GpuHistTest {' + $m.Value + $h.Value + '}')
        }
    }
    It 'Histogramm liefert dieselben Kennzahlen wie die Liste (auf 0,2 % genau)' {
        $rnd = New-Object Random 5
        $f = [float[]](1..20000 | ForEach-Object { 4.0 + $rnd.NextDouble() * 2.0 + $(if ($_ % 250 -eq 0) { 30.0 } else { 0.0 }) })
        $hist = New-Object 'long[]' ([GpuHistTest]::HistBins); $max = 0.0
        foreach ($v in $f) { $hist[[GpuHistTest]::HistBin($v)]++; if ($v -gt $max) { $max = $v } }
        $a = [GpuHistTest]::Stats($f, 100.0, 1280, 720); $b = [GpuHistTest]::StatsHist($hist, $max, 100.0, 1280, 720)
        $b[0] | Should -Be $a[0]
        for ($i = 1; $i -le 4; $i++) { [math]::Abs($b[$i] - $a[$i]) / $a[$i] | Should -BeLessThan 0.002 -Because "Kennzahl $i" }
    }
    It 'Histogramm deckt 0,01 ms bis 60 s ab, Ausreißer landen in der letzten Klasse' {
        [GpuHistTest]::HistBin(0.0) | Should -Be 0
        [GpuHistTest]::HistBin(1e9) | Should -Be ([GpuHistTest]::HistBins - 1)
        [GpuHistTest]::HistMid([GpuHistTest]::HistBins - 1) | Should -BeGreaterThan 60000
    }
    It 'Ø Bilder/s zählt alle gemessenen Bilder, nicht nur die gespeicherten Bildzeiten' {
        $cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Grafiktest.cs'))
        $cs | Should -Match 'r\.AvgFps = r\.MeasuredFrames / sec'
        $cs | Should -Match 'hc > fm\.Length \? StatsHist'
    }
    It 'Vorschau übergibt Rohdaten, das Bild entsteht im Fensterthread' {
        $cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Grafiktest.cs'))
        # ab v2.65 mit wiederverwendeten Puffern (TakeSpare/Publish) statt neuer Speicherblöcke je Vorschaubild
        $cs | Should -Match 'form\.Publish\(buf, r\.Width, r\.Height\)'
        $cs | Should -Match 'TakeLatest\(\)'
        $cs | Should -Match 'r\.skipStats = 3'
        $cs | Should -Not -Match 'new IntPtr\([^)]*ToInt64\(\)'
    }
    It 'Stoppcodes ab 0x80000000 führen nicht zum Abbruch' {
        { MinibenchTest\Get-BugcheckName ([int64]0xDEADDEAD) } | Should -Not -Throw
        MinibenchTest\Get-BugcheckName ([int64]0xC000021A) | Should -Match 'nachschlagen'
        MinibenchTest\Get-BugcheckName 0x116 | Should -Match 'VIDEO_TDR_FAILURE'
        MinibenchTest\Test-MemoryBugcheck ([int64]0xDEADDEAD) | Should -BeFalse
        MinibenchTest\Test-MemoryBugcheck 0x1A | Should -BeTrue
    }
    It 'gemeinsamer TEMP-Ordner: nur Einträge beendeter Prozesse gelten als Rest' {
        MinibenchTest\Test-TempEntryStale ('Start_{0}.log' -f $PID) | Should -BeFalse
        MinibenchTest\Test-TempEntryStale 'Start_999999.log' | Should -BeTrue
        MinibenchTest\Test-TempEntryStale 'LeosMinibench_999999.ps1' | Should -BeTrue
        MinibenchTest\Test-TempEntryStale 'Lauf_999999' | Should -BeFalse   # sichert Restore-StaleWorkDirs beim Start
        MinibenchTest\Test-TempEntryStale 'fremd.txt' | Should -BeFalse
    }
    It 'Rückstandskontrolle löscht den Ordner LeosMinibench im TEMP nie als Ganzes' {
        $src = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Ablauf/Abschluss.ps1'))
        $src | Should -Match "\`$i\.PSIsContainer -and \`$i\.Name -eq 'LeosMinibench'"
    }
    It 'abgebrochener Lauf, Berichtsordner fehlt: Rohdaten in den aktuellen Berichtsordner' {
        $base = Join-Path ([IO.Path]::GetTempPath()) 'LeosMinibench'
        $dead = Join-Path $base 'Lauf_999998'
        $now = Join-Path $TestDrive 'Bericht_neu'
        New-Item -ItemType Directory -Path (Join-Path $dead 'Anhang'), $now -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dead 'Ziel.txt'), (Join-Path $TestDrive 'gibt_es_nicht'))
        [IO.File]::WriteAllText((Join-Path $dead 'Anhang/Konsole.log'), 'abgebrochen')
        $n = @(MinibenchTest\Restore-StaleWorkDirs $now)
        ($n -join ' ') | Should -Match 'nicht erreichbar'
        $dead | Should -Not -Exist
        Join-Path $now 'Anhang_unterbrochen_999998.zip' | Should -Exist
    }
    It 'abgebrochener Lauf ohne erreichbaren Berichtsordner: Ordner bleibt, Rohdaten gehen nicht verloren' {
        $base = Join-Path ([IO.Path]::GetTempPath()) 'LeosMinibench'
        $dead = Join-Path $base 'Lauf_999997'
        try {
            New-Item -ItemType Directory -Path (Join-Path $dead 'Anhang') -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $dead 'Ziel.txt'), (Join-Path $TestDrive 'gibt_es_nicht'))
            [IO.File]::WriteAllText((Join-Path $dead 'Anhang/Konsole.log'), 'abgebrochen')
            $n = @(MinibenchTest\Restore-StaleWorkDirs '')
            ($n -join ' ') | Should -Match 'behalten.*nicht entfernbar'
            Join-Path $dead 'Anhang/Konsole.log' | Should -Exist
        } finally { Remove-Item -LiteralPath $dead -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'Lasttest: try/finally beendet alle Lasten, hängender Datenträgertest hat eine Frist' {
        $src = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Lasttest/Ablauf.ps1'))
        $src | Should -Match '(?s)finally \{\s*\[DiagCpu\]::Stop = \$true; \[DiagRam\]::Stop = \$true; \[DiagDiskStress\]::Stop = \$true'
        $src | Should -Match '\(\$now - \$diskStopAt\)\.TotalSeconds -ge 120'
        $src | Should -Match 'if \(\$stopped\) \{ Start-Sleep -Milliseconds 500 \}'
    }
    It 'schneller Modus: Abbruch mit BeginStop, OnDone auch beim Abbruch' {
        $src = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Parallel.ps1'))
        $src | Should -Match 'BeginStop\(\$null, \$null\)'
        $src | Should -Not -Match '\.PS\.Stop\(\)'
        $src | Should -Match 'wasRunning -and \$j\.OnDone'
    }
    It 'Launcher: Argumente nach CommandLineToArgvW, Statusdatei geteilt lesbar' {
        $src = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot '../Bauen.cmd'))
        $src | Should -Match "b\.Append\('\\\\', bs \* 2\);"
        $src | Should -Match 'FileShare\.ReadWrite \| FileShare\.Delete'
    }
    It 'Add-CachedType ignoriert Compilerwarnungen (Windows PowerShell wertet sie sonst als Fehler)' {
        $src = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Datenordner.ps1'))
        $src | Should -Match 'IgnoreWarnings = \$true'
    }
}
