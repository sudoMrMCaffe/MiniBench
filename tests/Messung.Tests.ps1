# Messungen von Benchmark und Lasttest: GPU-Rendertest (Einstellungen, Auswahl der Grafikeinheiten, Kennzahlen und
# Frametime-Werte, Befunde, Bildratengrenze), Lastschleifen und Lastprozess (Kern\Testroutinen.cs), Messung der
# Unterbrechungen, Sensoren während des Benchmarks, Gewichtung im Gesamtbild und die Abläufe, die diese Bausteine nutzen.
#
# C#-Teile werden je Testlauf höchstens einmal übersetzt (Get-KernUebersetzung, Ergebnis in einer globalen Variablen):
# Windows: Add-Type in einem Kindprozess (Windows PowerShell 5.1, C# 5) mit -OutputAssembly, sonst mcs -langversion:5.
# Die Bibliothek liegt in einem eigenen Ordner je Prozess unter TEMP\LeosMinibench-Tests-Kern (nicht in TestDrive:
# Windows sperrt eine geladene DLL bis zum Prozessende). Ordner beendeter Testläufe werden beim nächsten Lauf entfernt,
# Ordner noch laufender Testprozesse bleiben unberührt.
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $script:MessungKultur = [Threading.Thread]::CurrentThread.CurrentCulture
    [Threading.Thread]::CurrentThread.CurrentCulture = 'de-DE'

    # Arbeitsordner dieses Testprozesses für übersetzte Bibliotheken und Lastprozesse
    function Get-KernOrdner {
        if ($global:MinibenchKernOrdner -and (Test-Path -LiteralPath $global:MinibenchKernOrdner)) { return $global:MinibenchKernOrdner }
        $base = Join-Path ([IO.Path]::GetTempPath()) 'LeosMinibench-Tests-Kern'
        foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)) {
            $p = 0
            if ($d.Name -match '^(\d+)_') { $p = [int]$Matches[1] }
            if ($p -eq $PID) { continue }
            if ($p -gt 0 -and (Get-Process -Id $p -ErrorAction SilentlyContinue)) { continue }
            Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        $dir = Join-Path $base ('{0}_{1}' -f $PID, [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $global:MinibenchKernOrdner = $dir
        return $dir
    }

    # Eine C#-Datei aus src als Bibliothek übersetzen, je Testlauf einmal. Rückgabe: Ok, Dll, Compiler, Meldung
    function Get-KernUebersetzung([string]$Datei) {
        if (-not $global:MinibenchKernUebersetzung) { $global:MinibenchKernUebersetzung = @{} }
        if ($global:MinibenchKernUebersetzung.ContainsKey($Datei)) { return $global:MinibenchKernUebersetzung[$Datei] }
        $src = Join-Path $global:MinibenchSrcRoot $Datei
        $dll = Join-Path (Get-KernOrdner) ([IO.Path]::GetFileNameWithoutExtension($Datei) + '.dll')
        $winforms = ([IO.File]::ReadAllText($src, [Text.Encoding]::UTF8) -match 'using System\.Windows\.Forms;')
        $res = [pscustomobject]@{ Datei = $Datei; Ok = $false; Dll = $dll; Compiler = ''; Meldung = '' }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        if (Test-IstWindows) {
            $res.Compiler = 'Add-Type (.NET Framework, C# 5, Kindprozess)'
            $refs = $(if ($winforms) { 'Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $p.ReferencedAssemblies = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location); ' } else { '' })
            $code = ('$p = @{{ TypeDefinition = [IO.File]::ReadAllText(''{0}'', [Text.Encoding]::UTF8); OutputAssembly = ''{1}''; OutputType = ''Library''; IgnoreWarnings = $true; ErrorAction = ''Stop'' }}; ' -f $src.Replace("'", "''"), $dll.Replace("'", "''")) +
                $refs + 'try { Add-Type @p; exit 0 } catch { Write-Output $_.Exception.Message; exit 1 }'
            $msg = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $code
            $res.Ok = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $dll)); $res.Meldung = (@($msg) -join ' ')
        } elseif (Get-Command mcs -ErrorAction SilentlyContinue) {
            $res.Compiler = 'mcs -langversion:5'
            $r = @(); if ($winforms) { $r = @('-r:System.Windows.Forms.dll', '-r:System.Drawing.dll') }
            $msg = & mcs -langversion:5 -target:library -nowarn:414,169,649,0219,1635 @r ('-out:' + $dll) $src 2>&1
            $res.Ok = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $dll)); $res.Meldung = (@($msg | Where-Object { "$_" -match 'error' }) -join ' ')
        } else {
            $res.Meldung = 'kein C#-5-Compiler verfügbar (Windows PowerShell oder mcs)'
        }
        Write-Host ('    {0} übersetzt in {1:N1} s ({2}): {3}' -f $Datei, $sw.Elapsed.TotalSeconds, $res.Compiler, $(if ($res.Ok) { 'fehlerfrei' } else { 'FEHLER' }))
        $global:MinibenchKernUebersetzung[$Datei] = $res
        return $res
    }

    # Testroutinen (DiagCpu, DiagRam, DiagPause, DiagLoadHost, LoadJob) als Datei: der Lastprozess lädt dieselbe Bibliothek
    $script:Testroutinen = Get-KernUebersetzung 'Kern/Testroutinen.cs'
    if ($script:Testroutinen.Ok -and -not ('LoadJob' -as [type])) { Add-Type -Path $script:Testroutinen.Dll }

    Import-MinibenchTestModule -Parts 'Kern\Kodierung.ps1', 'Kern\Version.ps1', 'Kern\Modulvertrag.ps1', 'Kern\Referenz_Vergleich.ps1', 'Kern\Grafiktest.ps1' `
        -Functions 'Get-GpuKind', 'Get-DiskStressBytes', 'Get-PauseAssessment', 'Start-LoadJob' -Setup @'
$script:Findings = New-Object System.Collections.Generic.List[object]
function Add-Finding { param([string]$Level, [string]$Area, [string]$Text) $script:Findings.Add([pscustomobject]@{ Stufe = $Level; Bereich = $Area; Befund = $Text }) }
function Write-Checkpoint { param([string]$Kind, [string]$Text) }
function Write-Step { param([string]$Text) }
'@
}

AfterAll {
    [Threading.Thread]::CurrentThread.CurrentCulture = $script:MessungKultur
}

Describe 'C#-Teile der Messungen übersetzen' {
    It 'Testroutinen.cs lässt sich mit C# 5 übersetzen' {
        if (-not $script:Testroutinen.Compiler) { Set-ItResult -Skipped -Because $script:Testroutinen.Meldung; return }
        $script:Testroutinen.Ok | Should -BeTrue -Because $script:Testroutinen.Meldung
    }
    It 'Grafiktest.cs lässt sich mit C# 5 übersetzen' {
        $u = Get-KernUebersetzung 'Kern/Grafiktest.cs'
        if (-not $u.Compiler) { Set-ItResult -Skipped -Because $u.Meldung; return }
        $u.Ok | Should -BeTrue -Because $u.Meldung
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

Describe 'Rendertest: Grafikeinheiten erkennen und auswählen' {
    BeforeAll {
        function New-Ad($i, $n, $v, $luid, [bool]$sw = $false) {
            [pscustomobject]@{ Index = $i; Name = $n; VendorId = $v; Vendor = $(switch ($v) { 0x10DE { 'NVIDIA' } 0x8086 { 'Intel' } 0x1002 { 'AMD' } 0x1414 { 'Microsoft' } default { '' } }); DedicatedMB = 4096; Luid = $luid; Software = $sw }
        }
        $script:Ads = @(
            [pscustomobject]@{ Index = 1; Name = 'NVIDIA RTX 3000 Ada Generation Laptop GPU'; Art = 'dGPU'; Bezeichnung = 'Grafikkarte' }
            [pscustomobject]@{ Index = 0; Name = 'Intel(R) Iris(R) Xe Graphics'; Art = 'iGPU'; Bezeichnung = 'Prozessorgrafik' }
        )
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
    It 'Auswahl <A> ergibt <N> Einheit(en), erste <Erste>' -ForEach @(
        @{ A = 'Alle'; N = 2; Erste = 'NVIDIA RTX 3000 Ada Generation Laptop GPU' }
        @{ A = ''; N = 2; Erste = 'NVIDIA RTX 3000 Ada Generation Laptop GPU' }
        @{ A = 'Grafikkarte'; N = 1; Erste = 'NVIDIA RTX 3000 Ada Generation Laptop GPU' }
        @{ A = 'Prozessorgrafik'; N = 1; Erste = 'Intel(R) Iris(R) Xe Graphics' }
        @{ A = 'Name:Intel(R) Iris(R) Xe Graphics'; N = 1; Erste = 'Intel(R) Iris(R) Xe Graphics' }
        @{ A = 'Name:RTX 3000'; N = 1; Erste = 'NVIDIA RTX 3000 Ada Generation Laptop GPU' }
    ) {
        $r = MinibenchTest\Select-RenderAdapters $script:Ads $A
        @($r.Adapter).Count | Should -Be $N
        @($r.Adapter)[0].Name | Should -Be $Erste
        $r.Hinweis | Should -BeNullOrEmpty
    }
    It 'Voreinstellung von einem anderen PC ohne passende Einheit testet alle und sagt es' {
        $r = MinibenchTest\Select-RenderAdapters @($script:Ads[1]) 'Grafikkarte'
        @($r.Adapter).Count | Should -Be 1
        $r.Hinweis | Should -Match 'passt auf diesem PC zu keiner Grafikeinheit'
    }
}

Describe 'Rendertest: Kennzahlen und Frametime-Werte' {
    BeforeAll {
        # Kennzahlen aus Grafiktest.cs ohne Direct3D und WinForms: Klasse GpuRun und der Abschnitt Kennzahlen von DiagGpu
        # (Stats, Fnv, Histogramm, Summarize) unter eigenen Namen übersetzen. Felder werden für den Test öffentlich.
        if (-not ('GrafikKennzahlenTest' -as [type])) {
            $cs = Get-SrcText 'Kern/Grafiktest.cs'
            $run = [regex]::Match($cs, '(?s)public class GpuRun\s*\{.*?\r?\n\}')
            $kz = [regex]::Match($cs, '(?s)\r?\n    // -+ Kennzahlen.*?(?=\r?\n    // -+ Ablauf)')
            if (-not $run.Success -or -not $kz.Success) { throw 'Grafiktest.cs: Klasse GpuRun oder Abschnitt Kennzahlen nicht gefunden' }
            $runText = $run.Value.Replace('public class GpuRun', 'public class GrafikLaufTest').Replace('DiagGpu.HistBins', 'GrafikKennzahlenTest.HistBins') -replace '(?m)^\s*public Bitmap Image;\s*$', '' -replace '\binternal ', 'public '
            $kzText = $kz.Value -replace '\bGpuRun\b', 'GrafikLaufTest'
            Add-Type -TypeDefinition ("using System;`r`nusing System.Collections.Generic;`r`n" + $runText + "`r`npublic static class GrafikKennzahlenTest {`r`n" + $kzText + "`r`n}")
        }
        function New-Lauf([double]$Sekunden, [long]$Bilder, [float[]]$Bildzeiten = @()) {
            $r = New-Object GrafikLaufTest
            $r.Seconds = $Sekunden; $r.MeasuredFrames = $Bilder
            foreach ($f in $Bildzeiten) { $r.frameList.Add($f) }
            return $r
        }
    }
    It 'Ø Bilder/s, 1-%-Low, Median, 99 %, längste Bildzeit und Punktzahl' {
        # 1000 Bilder: 990 x 10 ms, 10 x 50 ms (Ruckler) in 10,4 s
        $f = [float[]](@(1..990 | ForEach-Object { 10.0 }) + @(1..10 | ForEach-Object { 50.0 }))
        $r = [GrafikKennzahlenTest]::Stats($f, 10.4, 1280, 720)
        [math]::Round($r[0], 2) | Should -Be ([math]::Round(1000 / 10.4, 2))
        $r[1] | Should -Be 20          # langsamste 1 % = 10 Bilder mit 50 ms
        $r[2] | Should -Be 10
        $r[3] | Should -Be 10          # 99. Perzentil (990. von 1000)
        $r[4] | Should -Be 50
        [math]::Round($r[5]) | Should -Be ([math]::Round(1000 / 10.4 * 1280 * 720 / 10000))
    }
    It '0,1-%-Low und Anteil der Mikroruckler über 50 ms' {
        # 1000 Bilder: 998 x 10 ms, 1 x 20 ms, 1 x 100 ms
        $f = [float[]](@(1..998 | ForEach-Object { 10.0 }) + @(20.0, 100.0))
        $r = [GrafikKennzahlenTest]::Stats($f, 10.1, 1280, 720)
        [math]::Round($r[6], 1) | Should -Be 50     # 99,9. Perzentil = 20 ms
        [math]::Round($r[7], 2) | Should -Be 0.1    # 1 von 1000 Bildern über 50 ms
    }
    It 'leere Messung ergibt Nullen' {
        @([GrafikKennzahlenTest]::Stats([float[]]@(), 0, 1280, 720)) | Should -Be @(0, 0, 0, 0, 0, 0, 0, 0)
    }
    It 'Prüfsumme des Referenzbilds unterscheidet sich schon bei einem Byte' {
        $a = [byte[]](1..100); $b = [byte[]](1..100); $b[50] = 0
        [GrafikKennzahlenTest]::Fnv($a, 100, 14695981039346656037) | Should -Not -Be ([GrafikKennzahlenTest]::Fnv($b, 100, 14695981039346656037))
        [GrafikKennzahlenTest]::Fnv($a, 100, 14695981039346656037) | Should -Be ([GrafikKennzahlenTest]::Fnv($a, 100, 14695981039346656037))
        [GrafikKennzahlenTest]::Fnv($a, 0, 100, 14695981039346656037) | Should -Be ([GrafikKennzahlenTest]::Fnv($a, 100, 14695981039346656037))
    }
    It 'Histogramm liefert dieselben Kennzahlen wie die Liste (auf 0,2 % genau)' {
        $rnd = New-Object Random 5
        $f = [float[]](1..20000 | ForEach-Object { 4.0 + $rnd.NextDouble() * 2.0 + $(if ($_ % 250 -eq 0) { 30.0 } else { 0.0 }) })
        $hist = New-Object 'long[]' ([GrafikKennzahlenTest]::HistBins); $max = 0.0
        foreach ($v in $f) { $hist[[GrafikKennzahlenTest]::HistBin($v)]++; if ($v -gt $max) { $max = $v } }
        $a = [GrafikKennzahlenTest]::Stats($f, 100.0, 1280, 720); $b = [GrafikKennzahlenTest]::StatsHist($hist, $max, 100.0, 1280, 720)
        $b[0] | Should -Be $a[0]
        for ($i = 1; $i -le 4; $i++) { [math]::Abs($b[$i] - $a[$i]) / $a[$i] | Should -BeLessThan 0.002 -Because "Kennzahl $i" }
        $b[7] | Should -Be $a[7]
    }
    It 'Histogramm deckt 0,01 ms bis 60 s ab, Ausreißer landen in der letzten Klasse' {
        [GrafikKennzahlenTest]::HistBin(0.0) | Should -Be 0
        [GrafikKennzahlenTest]::HistBin(1e9) | Should -Be ([GrafikKennzahlenTest]::HistBins - 1)
        [GrafikKennzahlenTest]::HistMid([GrafikKennzahlenTest]::HistBins - 1) | Should -BeGreaterThan 60000
    }
    It 'Ø Bilder/s zählt alle gemessenen Bilder, nicht nur die gewerteten Bildzeiten' {
        # 1200 Bilder in 10 s, davon 1000 Bildzeiten gewertet (Rest in Messpausen nach Vorschau oder Bildprüfung)
        $r = New-Lauf 10 1200 ([float[]]@(1..1000 | ForEach-Object { 10.0 }))
        [GrafikKennzahlenTest]::Summarize($r)
        $r.AvgFps | Should -Be 120
        $r.Low1Fps | Should -Be 100
        $r.MedianMs | Should -Be 10
        $r.Score | Should -Be (120 * 1280 * 720 / 10000)
    }
    It 'Dauerlast: mehr Bilder als gespeicherte Bildzeiten, die Kennzahlen kommen aus dem Histogramm' {
        $r = New-Lauf 100 20000 ([float[]]@(1..10 | ForEach-Object { 50.0 }))
        $k = [GrafikKennzahlenTest]::HistBin(5.0)
        $r.hist[$k] = 20000; $r.histCount = 20000; $r.histMax = 5.0
        [GrafikKennzahlenTest]::Summarize($r)
        [math]::Abs($r.MedianMs - 5.0) | Should -BeLessThan 0.01
        $r.MaxMs | Should -Be 5
        $r.StutterPct | Should -Be 0
    }
    It 'niedrige Bildrate ohne gewertete Bildzeiten: Ersatzwerte aus Ø Bilder/s statt Nullen' {
        $r = New-Lauf 10 50
        [GrafikKennzahlenTest]::Summarize($r)
        $r.AvgFps | Should -Be 5
        $r.Low1Fps | Should -Be 5; $r.Low01Fps | Should -Be 5
        $r.MedianMs | Should -Be 200; $r.P99Ms | Should -Be 200; $r.MaxMs | Should -Be 200
        $r.MinFps | Should -Be 5; $r.MaxFps | Should -Be 5
    }
    It 'ohne gemessene Bilder bleibt alles 0' {
        $r = New-Lauf 10 0
        [GrafikKennzahlenTest]::Summarize($r)
        $r.AvgFps | Should -Be 0; $r.Low1Fps | Should -Be 0; $r.Score | Should -Be 0
    }
    It 'feste Szene für vergleichbare Werte: 72 Schritte je Pixel, 1280x720, Vorschau mit 30 Bildern je Sekunde' {
        $r = New-Object GrafikLaufTest
        $r.Steps | Should -Be 72
        $r.Width | Should -Be 1280; $r.Height | Should -Be 720
        $r.PreviewHz | Should -Be 30
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
    It 'Ergebnis übernimmt 0,1-%-Low und Mikroruckler' {
        $run = [pscustomobject]@{
            Done = $true; Ok = $true; Seconds = 5.0; MeasuredFrames = 500; AvgFps = 100.0; Low1Fps = 80.0; Low01Fps = 60.0; StutterPct = 0.5
            MedianMs = 10.0; P99Ms = 12.5; MaxMs = 60.0; Score = 9200.0; AdapterName = 'TestGPU'; Width = 1280; Height = 720
            Error = ''; DeviceRemoved = $false; RemovedReason = ''; ImageChecks = 1; ImageErrors = 0
        }
        $r = MinibenchTest\ConvertTo-RenderResult $run ([pscustomobject]@{ Name = 'TestGPU'; Art = 'dGPU'; Bezeichnung = 'Grafikkarte'; Index = 0 })
        $r.Ok | Should -BeTrue; $r.Haengt | Should -BeFalse
        $r.Low01 | Should -Be 60
        $r.Mikroruckler | Should -Be 0.5
        $r.Aufloesung | Should -Be '1280x720'
    }
    It 'Ergebnis bei niedriger Bildrate: Ersatzwerte für 1-%-Low, Median und längste Bildzeit' {
        $run = [pscustomobject]@{
            Done = $true; Ok = $true; Seconds = 10.0; MeasuredFrames = 50; AvgFps = 5.0; Low1Fps = 0.0; Low01Fps = 0.0; StutterPct = 100.0
            MedianMs = 0.0; P99Ms = 0.0; MaxMs = 0.0; Score = 460.0; AdapterName = 'Intel(R) UHD Graphics 620'; Width = 1280; Height = 720
            Error = ''; DeviceRemoved = $false; RemovedReason = ''; ImageChecks = 1; ImageErrors = 0; FeatureLevel = '11_0'
            FpsPerSecond = @(5.0); FrameMs = @(); EscPressed = $false; RefHash = 'hash'
        }
        $r = MinibenchTest\ConvertTo-RenderResult $run ([pscustomobject]@{ Name = 'Intel(R) UHD Graphics 620'; Art = 'iGPU'; Bezeichnung = ''; Index = 0 })
        $r.Fps | Should -Be 5.0
        $r.Low1 | Should -Be 5.0; $r.Low01 | Should -Be 5.0
        $r.MedianMs | Should -Be 200.0; $r.P99Ms | Should -Be 200.0; $r.MaxMs | Should -Be 200.0
    }
    It 'Metriken des Rendertests für Datenbank und Vergleich, Mikroruckler zählen als kleiner ist besser' {
        $keys = @(Get-ModuleVar 'MetricDefs' | ForEach-Object { $_.K })
        foreach ($k in 'GPU|REND', 'GPU|REND1', 'GPU|REND01', 'GPU|STUTTER', 'GPU|RPKT') { $keys | Should -Contain $k }
        MinibenchTest\Test-LowerBetterKey 'GPU|STUTTER' | Should -BeTrue
        MinibenchTest\Test-LowerBetterKey 'GPU|REND01' | Should -BeFalse
        MinibenchTest\Test-LowerBetterKey 'GPU|REND' | Should -BeFalse
    }
}

Describe 'Rendertest: Direct3D-Schnittstelle' {
    It 'Plätze in den Funktionstabellen von ID3D11Device und ID3D11DeviceContext entsprechen d3d11.h' {
        # Plätze laut d3d11.h (IUnknown 0 bis 2, ID3D11DeviceChild 3 bis 6 beim Kontext)
        $soll = @{
            V_Dev_CreateBuffer = 3; V_Dev_CreateTexture2D = 5; V_Dev_CreateRenderTargetView = 9; V_Dev_CreateInputLayout = 11; V_Dev_CreateVertexShader = 12
            V_Dev_CreatePixelShader = 15; V_Dev_CreateQuery = 24; V_Dev_GetFeatureLevel = 37; V_Dev_GetDeviceRemovedReason = 39; V_Dev_GetImmediateContext = 40
            V_Ctx_VSSetConstantBuffers = 7; V_Ctx_PSSetShader = 9; V_Ctx_VSSetShader = 11; V_Ctx_Draw = 13; V_Ctx_Map = 14; V_Ctx_Unmap = 15
            V_Ctx_PSSetConstantBuffers = 16; V_Ctx_IASetInputLayout = 17; V_Ctx_IASetVertexBuffers = 18; V_Ctx_IASetPrimitiveTopology = 24
            V_Ctx_Begin = 27; V_Ctx_End = 28; V_Ctx_GetData = 29; V_Ctx_OMSetRenderTargets = 33; V_Ctx_RSSetViewports = 44
            V_Ctx_CopyResource = 47; V_Ctx_UpdateSubresource = 48; V_Ctx_ClearState = 110; V_Ctx_Flush = 111
        }
        $ist = @([regex]::Matches((Get-SrcText 'Kern/Grafiktest.cs'), '\b(V_(?:Dev|Ctx)_\w+)\s*=\s*(\d+)'))
        $ist.Count | Should -BeGreaterThan 10
        foreach ($m in $ist) {
            $n = $m.Groups[1].Value
            $soll.ContainsKey($n) | Should -BeTrue -Because ('{0} fehlt in der Tabelle des Tests (Platz in d3d11.h nachsehen)' -f $n)
            [int]$m.Groups[2].Value | Should -Be $soll[$n] -Because $n
        }
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

Describe 'Rendertest: Bildratengrenze und Bilder/s im Verlauf' {
    It 'TORRENT: 134 Bilder/s bei voller und geviertelter Last, Monitor 144 Hz, ergibt Bildratengrenze' {
        $g = MinibenchTest\Get-FpsLimitAssessment 134.4 135.1 @(144)
        $g.Begrenzt | Should -BeTrue; $g.Grenze | Should -Be 144
        $g.Text | Should -Match 'Bildratengrenze aktiv: 134 Bilder/s'
        $g.Text | Should -Match 'Radeon Chill'
    }
    It 'Grafikkarte, die mit weniger Last schneller wird, ist nicht begrenzt' {
        (MinibenchTest\Get-FpsLimitAssessment 134.4 410 @(144)).Begrenzt | Should -BeFalse
        (MinibenchTest\Get-FpsLimitAssessment 85 260 @(60)).Begrenzt | Should -BeFalse
    }
    It 'ohne Nähe zu einer Bildwiederholrate: allgemeiner Hinweis (Treiber oder Prozessor)' {
        $g = MinibenchTest\Get-FpsLimitAssessment 22 24 @(60)
        $g.Begrenzt | Should -BeTrue; $g.Grenze | Should -BeNullOrEmpty
        $g.Text | Should -Match 'steigen mit einem Viertel der Rechenlast kaum'
    }
    It 'ohne Probe kein Urteil' {
        MinibenchTest\Get-FpsLimitAssessment 0 0 @(144) | Should -BeNullOrEmpty
        MinibenchTest\Get-FpsLimitAssessment $null 100 | Should -BeNullOrEmpty
    }
    It 'Bilder/s im Verlauf als Mittel seit dem letzten Messpunkt' {
        $t0 = Get-Date '2026-10-02 13:04:00'
        $e = [pscustomobject]@{ Run = [pscustomobject]@{ Frames = 0L; LiveFps = 95.0 }; Frames0 = 0L; T0 = $t0 }
        MinibenchTest\Get-FpsSince $e $t0.AddSeconds(0.2) | Should -BeNullOrEmpty
        $e.Run.Frames = 300
        MinibenchTest\Get-FpsSince $e $t0.AddSeconds(4) | Should -Be 95
        $e.Run.Frames = 300 + 5 * 103
        MinibenchTest\Get-FpsSince $e $t0.AddSeconds(9) | Should -Be 103
    }
}

Describe 'Lasttest: Größe der Testdatei für den Datenträger' {
    It 'Größe der Testdatei für <Frei> freie Bytes ist <Erwartet>' -ForEach @(
        @{ Frei = 500GB; Erwartet = 4GB }
        @{ Frei = 3GB; Erwartet = [long](3GB * 0.1) }
        @{ Frei = 1GB; Erwartet = 256MB }
        @{ Frei = 4TB; Erwartet = 4GB }
    ) {
        MinibenchTest\Get-DiskStressBytes $Frei | Should -Be $Erwartet
    }
}

Describe 'Lastschleifen ohne Aufrufe (für die Speicherbereinigung sofort anhaltbar)' {
    BeforeAll {
        if (-not ('DiagCpu' -as [type])) { throw ('Testroutinen nicht geladen: ' + $script:Testroutinen.Meldung) }
        # Aufgerufene Methoden einer Methode aus ihrem IL-Code (call, callvirt, newobj)
        function Get-IlAufrufe([Reflection.MethodBase]$Methode) {
            if (-not $global:MinibenchIlOpCodes) {
                $global:MinibenchIlOpCodes = @{}
                foreach ($f in [Reflection.Emit.OpCodes].GetFields([Reflection.BindingFlags]'Public, Static')) { $o = $f.GetValue($null); $global:MinibenchIlOpCodes[[int]($o.Value -band 0xFFFF)] = $o }
            }
            $il = $Methode.GetMethodBody().GetILAsByteArray()
            $out = New-Object System.Collections.Generic.List[string]
            $i = 0
            while ($i -lt $il.Length) {
                $v = [int]$il[$i]; $i++
                if ($v -eq 0xFE) { $v = 0xFE00 -bor [int]$il[$i]; $i++ }
                $op = $global:MinibenchIlOpCodes[$v]
                if (-not $op) { throw ('unbekannter IL-Befehl 0x{0:X}' -f $v) }
                $n = switch ($op.OperandType.ToString()) {
                    'InlineNone' { 0 } 'ShortInlineBrTarget' { 1 } 'ShortInlineI' { 1 } 'ShortInlineVar' { 1 } 'InlineVar' { 2 }
                    'InlineI8' { 8 } 'InlineR' { 8 } 'InlineSwitch' { 4 + 4 * [BitConverter]::ToInt32($il, $i) } default { 4 }
                }
                if ($op.FlowControl.ToString() -eq 'Call' -and $op.OperandType.ToString() -eq 'InlineMethod') {
                    $m = $Methode.Module.ResolveMethod([BitConverter]::ToInt32($il, $i))
                    $out.Add(('{0}.{1}' -f $m.DeclaringType.Name, $m.Name))
                }
                $i += $n
            }
            return @($out | Select-Object -Unique)
        }
        $script:NonPublic = [Reflection.BindingFlags]'NonPublic, Public, Static'
    }
    It 'CPU-Rechenschritt ruft nur Math.Sqrt und Math.Abs auf (kein Math.Sin, kein BitConverter)' {
        $m = [DiagCpu].GetMethod('WorkPart')
        @(Get-IlAufrufe $m | Where-Object { $_ -notin 'Math.Sqrt', 'Math.Abs' }) | Should -BeNullOrEmpty
    }
    It 'RAM-Muster schreiben und prüfen ohne Aufruf je Wert (nur die seltene Fehlermeldung)' {
        @(Get-IlAufrufe ([DiagRam].GetMethod('FillSlice', $script:NonPublic))) | Should -BeNullOrEmpty
        @(Get-IlAufrufe ([DiagRam].GetMethod('VerifySlice', $script:NonPublic))) | Should -Be @('DiagRam.Report')
    }
    It 'Lastschleifen sind eigene Methoden ohne Einbetten, in Abschnitten zu höchstens 10.000 Schritten bzw. 2 MB' {
        foreach ($m in @([DiagCpu].GetMethod('WorkPart'), [DiagRam].GetMethod('FillSlice', $script:NonPublic), [DiagRam].GetMethod('VerifySlice', $script:NonPublic))) {
            ($m.MethodImplementationFlags -band [Reflection.MethodImplAttributes]::NoInlining) | Should -Be ([Reflection.MethodImplAttributes]::NoInlining) -Because $m.Name
        }
        [DiagCpu]::WorkChunk | Should -BeLessOrEqual 10000
        [DiagCpu]::WorkSteps | Should -Be 1500000
        [DiagRam].GetField('Slice', $script:NonPublic).GetRawConstantValue() * 8 | Should -Be 2MB
    }
    It 'Sinus als Polynom: höchstens 0,001 Abweichung über den Wertebereich der Rechnung' {
        foreach ($x0 in @(-1.0, -0.3, 0.0, 0.5, 1.5, 3.1, 3.2, 6.2, 6.3, 10.0, 100.7, 1224.9)) {
            $x = [double]$x0; $h = [uint64]0
            [DiagCpu]::WorkPart([ref]$x, [ref]$h, 7, 7)
            $soll = [math]::Sqrt([math]::Abs($x0 * 1.0000001 + 7)) * 1.0001 + [math]::Sin($x0)
            [math]::Abs($x - $soll) | Should -BeLessThan 0.001 -Because "x = $x0"
        }
    }
    It 'Abschnitte ergeben dasselbe Ergebnis wie ein Durchlauf am Stück (Referenzwerte bleiben gültig)' {
        foreach ($seed in 1, 7, 16) {
            $x = [double]($seed % 1000) + 1.5
            $h = ([uint64]$seed) -bxor [uint64]::Parse('CBF29CE484222325', 'AllowHexSpecifier')
            [DiagCpu]::WorkPart([ref]$x, [ref]$h, 1, 1500000)
            [DiagCpu]::Work([uint64]$seed) | Should -Be $h
        }
    }
    It 'Rechendurchlauf bleibt deterministisch' {
        [DiagCpu]::Work(5) | Should -Be ([DiagCpu]::Work(5))
        [DiagCpu]::Work(5) | Should -Not -Be ([DiagCpu]::Work(6))
    }
    It 'RAM-Mustertest findet in Abschnitten keine Fehler und zählt den ganzen Block' {
        [DiagRam]::Stop = $false
        $txt = [DiagRam]::Run(256MB, 1)
        [DiagRam]::Errors | Should -Be 0
        [DiagRam]::BytesTested | Should -Be 256MB
        $txt | Should -Match 'Fehler\s+: 0'
    }
}

Describe 'Unterbrechungen der Last messen' {
    BeforeAll { if (-not ('DiagPause' -as [type])) { throw ('Testroutinen nicht geladen: ' + $script:Testroutinen.Meldung) } }
    It 'Messung liefert Zahl, längste, Summe und Speicherbereinigungen je Generation' {
        [DiagPause]::Start()
        $null = 1..20000 | ForEach-Object { New-Object byte[] 4096 }
        [GC]::Collect()
        Start-Sleep -Milliseconds 200
        $p = [DiagPause]::Stop()
        $p.Count | Should -Be 6
        $p[3] | Should -BeGreaterThan 0
        $p[5] | Should -BeGreaterOrEqual 1
    }
    It 'stellt den GC-Modus nach der Messung wieder her, auch nach zweimal Start' {
        $before = [System.Runtime.GCSettings]::LatencyMode
        [DiagPause]::Start()
        [DiagPause]::Start()
        [DiagPause]::Running | Should -BeTrue
        [DiagPause]::Stop() | Out-Null
        [DiagPause]::Running | Should -BeFalse
        [System.Runtime.GCSettings]::LatencyMode | Should -Be $before
    }
    It 'Stop ohne laufende Messung liefert nichts (keine alten Zähler)' {
        [DiagPause]::Stop() | Should -BeNullOrEmpty
    }
    It 'ohne Unterbrechung: kurzer Text, nicht auffällig' {
        $a = MinibenchTest\Get-PauseAssessment @(0, 0, 0, 12, 3, 0) 120
        $a.Text | Should -Be 'keine über 50 ms (Speicherbereinigungen Gen 0/1/2: 12/3/0)'
        $a.Auffaellig | Should -BeFalse
    }
    It 'eine Unterbrechung ab 250 ms ist auffällig' {
        $a = MinibenchTest\Get-PauseAssessment @(3, 310, 420, 40, 6, 1) 120
        $a.Text | Should -Be '3 über 50 ms, längste 310 ms, zusammen 0,4 s (Speicherbereinigungen Gen 0/1/2: 40/6/1)'
        $a.Auffaellig | Should -BeTrue
    }
    It 'viele kurze Unterbrechungen über 2 % der Dauer sind auffällig' {
        (MinibenchTest\Get-PauseAssessment @(80, 90, 6000, 200, 10, 0) 120).Auffaellig | Should -BeTrue
        (MinibenchTest\Get-PauseAssessment @(10, 60, 600, 50, 2, 0) 120).Auffaellig | Should -BeFalse
    }
    It 'ohne Messwerte keine Bewertung' { MinibenchTest\Get-PauseAssessment $null | Should -BeNullOrEmpty }
}

Describe 'Last im eigenen Prozess (LoadJob, DiagLoadHost)' {
    BeforeAll {
        if (-not ('LoadJob' -as [type])) { throw ('Testroutinen nicht geladen: ' + $script:Testroutinen.Meldung) }
        $script:LastDll = $script:Testroutinen.Dll
        # eigener Ordner dieses Testprozesses (Get-KernOrdner): ein paralleler Testlauf räumt ihn nicht weg
        $script:LastDir = Join-Path (Get-KernOrdner) ('Last_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $script:LastDir -Force | Out-Null
        $exe = $(if ($PSVersionTable.PSEdition -eq 'Core') { if ([IO.Path]::DirectorySeparatorChar -eq '\') { 'pwsh.exe' } else { 'pwsh' } } else { 'powershell.exe' })
        $script:LastHost = Join-Path $PSHOME $exe
        # unbrauchbare Bibliothek für die Ausweichpfade
        $script:Kaputt = Join-Path $script:LastDir 'kaputt.dll'
        [IO.File]::WriteAllText($script:Kaputt, 'keine Bibliothek')
    }
    AfterAll { Remove-Item -LiteralPath $script:LastDir -Recurse -Force -ErrorAction SilentlyContinue }
    It 'CPU-Last läuft im eigenen Prozess, meldet Durchläufe und endet auf Stopp' {
        $j = [LoadJob]::Start('cpu', $script:LastHost, $script:LastDll, (Join-Path $script:LastDir 'cpu'), 60, 2, 0, 0, $false)
        try {
            $j.External | Should -BeTrue
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 500; $j.Refresh(); if ($j.Count -ge 20) { break } }
            $j.Count | Should -BeGreaterOrEqual 20
            $j.Errors | Should -Be 0
            $j.Stop()
            $j.Wait(15000) | Should -BeTrue
            $j.Done | Should -BeTrue
            $j.ExitCode | Should -Be 0
            $j.Note | Should -BeNullOrEmpty
            # im Lastprozess keine Speicherbereinigung und keine Unterbrechung
            $j.Pause.Count | Should -Be 6
            $j.Pause[0] | Should -Be 0
            $j.Pause[3] | Should -Be 0
        } finally { $j.Stop(); $j.Kill(); $j.Cleanup() }
    }
    It 'RAM-Last im eigenen Prozess mit Ergebnistext' {
        $j = [LoadJob]::Start('ram', $script:LastHost, $script:LastDll, (Join-Path $script:LastDir 'ram'), 60, 2, 256MB, 2, $true)
        try {
            $j.External | Should -BeTrue
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 500; $j.Refresh(); if ($j.Count -ge 256MB) { break } }
            $j.Count | Should -Be 256MB
            $j.Stop()
            $j.Wait(30000) | Should -BeTrue
            $j.Result | Should -Match 'Fehler\s+: 0'
        } finally { $j.Stop(); $j.Kill(); $j.Cleanup() }
    }
    It 'startet der Lastprozess nicht, läuft die Last im Arbeitsprozess' {
        $j = [LoadJob]::Start('cpu', (Join-Path $script:LastDir 'fehlt.exe'), $script:LastDll, (Join-Path $script:LastDir 'cpu2'), 1, 1, 0, 0, $false)
        $j.External | Should -BeFalse
        $j.Note | Should -Match 'eigener Lastprozess nicht möglich'
        $j.Wait(30000) | Should -BeTrue
        $j.Count | Should -BeGreaterThan 0
    }
    It 'endet der Lastprozess vor der ersten Meldung (unbrauchbare Bibliothek), übernimmt der Arbeitsprozess' {
        Test-Path -LiteralPath $script:Kaputt | Should -BeTrue
        $j = [LoadJob]::Start('cpu', $script:LastHost, $script:Kaputt, (Join-Path $script:LastDir 'cpu3'), 1, 1, 0, 0, $false)
        $j.External | Should -BeTrue
        $j.Wait(60000) | Should -BeTrue
        $j.External | Should -BeFalse
        # Fehlertext von Add-Type je nach Sprache von Windows (Bad IL format, Assemblymanifest erwartet): nur Rahmen prüfen
        $j.Note | Should -Match 'Lastprozess endete ohne Ergebnis \(Exitcode 2, .*kaputt\.dll.*\), Last läuft im Arbeitsprozess'
        $j.Count | Should -BeGreaterThan 0
    }
    It 'nach Stop startet ein gescheiterter Lastprozess keine Last im Arbeitsprozess nach' {
        $j = [LoadJob]::Start('cpu', $script:LastHost, $script:Kaputt, (Join-Path $script:LastDir 'cpu5'), 30, 1, 0, 0, $false)
        $j.Stop()
        $j.Wait(60000) | Should -BeTrue
        $j.External | Should -BeTrue
        $j.Count | Should -Be 0
        $j.Note | Should -Match 'Lastprozess endete ohne Ergebnis'
        $j.Cleanup()
        Test-Path -LiteralPath (Join-Path $script:LastDir 'cpu5') | Should -BeFalse
    }
    It 'Statuszeile mit Prüfsumme: abgeschnittene oder veränderte Zeilen werden verworfen' {
        $v = [DiagLoadHost]::ParseStatus('L1;5;0;100;0;0;0;0;0;0;0;0;105;')
        $v[2] | Should -Be 100
        [DiagLoadHost]::ParseStatus('L1;5;0;100;0;0;0;0;0;0;0;0;106;') | Should -BeNullOrEmpty
        [DiagLoadHost]::ParseStatus('L1;5;0;10') | Should -BeNullOrEmpty
        [DiagLoadHost]::ParseStatus('') | Should -BeNullOrEmpty
    }
    It 'Start-LoadJob: MINIBENCH_LAST_INTERN erzwingt die Last im Arbeitsprozess und nennt den Grund' {
        $alt = $env:MINIBENCH_LAST_INTERN
        $env:MINIBENCH_LAST_INTERN = '1'
        try {
            $j = MinibenchTest\Start-LoadJob 'cpu' 1 1
            $j.External | Should -BeFalse
            $j.Note | Should -Match 'MINIBENCH_LAST_INTERN gesetzt'
            $j.Wait(30000) | Should -BeTrue
            $j.Count | Should -BeGreaterThan 0
            $j.Cleanup()
        } finally { $env:MINIBENCH_LAST_INTERN = $alt }
    }
}

Describe 'Gewichtung im Gesamtbild' {
    BeforeEach {
        Set-ModuleVar 'BenchHead' @{}
        Set-ModuleVar 'BenchGroupNames' @{ CPU = 'Prozessor'; RAM = 'Arbeitsspeicher'; GPU = 'Grafik'; Laufwerke = 'Laufwerke' }
        Set-ModuleVar 'BenchDisks' @()
    }
    It 'geometrisches Mittel mit Gewichten' {
        MinibenchTest\Get-GeoMean @(100, 400) @(2.0, 1.0) | Should -Be 159
        MinibenchTest\Get-GeoMean @(100, 400) @(1.0, 1.0) | Should -Be 200
    }
    It 'Grafik: der gemessene Rendertest zählt dreifach gegenüber theoretischen Werten' {
        Set-ModuleVar 'BenchResults' @(
            [pscustomobject]@{ Gruppe = 'GPU'; Key = 'GPU|REND'; RefKey = 'GPU|REND'; RefPct = 100; Status = 'OK' }
            [pscustomobject]@{ Gruppe = 'GPU'; Key = 'GPU|DWM'; RefKey = 'GPU|DWM'; RefPct = 400; Status = 'OK' })
        (MinibenchTest\Get-BenchGroup 'GPU').RefPct | Should -Be 141   # (100^3 x 400)^(1/4); ungewichtet wären es 200
    }
    It 'Gesamtbild: Prozessor und Grafik doppelt gegenüber Arbeitsspeicher und Laufwerken' {
        Set-ModuleVar 'BenchResults' @(
            [pscustomobject]@{ Gruppe = 'CPU'; Key = 'CPU|X'; RefKey = 'CPU|X'; RefPct = 100; Status = 'OK' }
            [pscustomobject]@{ Gruppe = 'RAM'; Key = 'RAM|X'; RefKey = 'RAM|X'; RefPct = 400; Status = 'OK' }
            [pscustomobject]@{ Gruppe = 'GPU'; Key = 'GPU|REND'; RefKey = 'GPU|REND'; RefPct = 100; Status = 'OK' })
        Set-ModuleVar 'BenchDisks' @([pscustomobject]@{ RefPct = 400; Status = 'OK' })
        MinibenchTest\Get-BenchOverall | Should -Be 159   # (100^4 x 400^2)^(1/6); ungewichtet wären es 200
    }
    It 'Gruppen ohne Referenzwert fallen aus dem Gesamtbild' {
        Set-ModuleVar 'BenchResults' @([pscustomobject]@{ Gruppe = 'CPU'; Key = 'CPU|X'; RefKey = 'CPU|X'; RefPct = 120; Status = 'OK' })
        MinibenchTest\Get-BenchOverall | Should -Be 120
        Set-ModuleVar 'BenchResults' @()
        MinibenchTest\Get-BenchOverall | Should -BeNullOrEmpty
    }
}

Describe 'Abläufe von Benchmark und Lasttest nutzen die geprüften Bausteine' {
    It '<Datei>: <Zweck>' -ForEach @(
        @{ Datei = 'Module/Lasttest/Ablauf.ps1'; Zweck = 'Testdatei nach freiem Platz'; Muster = 'Get-DiskStressBytes' }
        @{ Datei = 'Module/Lasttest/Ablauf.ps1'; Zweck = 'Messwerte als flache Liste'; Muster = 'ConvertTo-FlatReadings \(Get-SensorReadings' }
        @{ Datei = 'Module/Lasttest/Ablauf.ps1'; Zweck = 'unplausible Werte je Sensor gezählt'; Muster = 'Register-BadReadings \$rd \$script:LoadBadSeen' }
        @{ Datei = 'Module/Lasttest/Ablauf.ps1'; Zweck = 'CPU-Last über den Lastprozess'; Muster = "Start-LoadJob 'cpu'" }
        @{ Datei = 'Module/Lasttest/Ablauf.ps1'; Zweck = 'RAM-Last über den Lastprozess, eine Stufe unter normal'; Muster = "Start-LoadJob 'ram' .*-Low" }
        @{ Datei = 'Module/Lasttest/Ablauf.ps1'; Zweck = 'Unterbrechungen gemessen'; Muster = '(?s)Start-PauseWatch.*Stop-PauseWatch' }
        @{ Datei = 'Module/Lasttest/Ablauf.ps1'; Zweck = 'gemeinsame Sensorauswertung mit dem Benchmark'; Muster = '(?s)Get-SensorSeriesStats.*Get-SensorSeriesLines' }
        @{ Datei = 'Module/Lasttest/Ablauf.ps1'; Zweck = 'Auswahl der Grafikeinheiten'; Muster = 'Select-RenderAdapters @\(Get-RenderAdapters\) \$GpuAuswahl' }
        @{ Datei = 'Module/Lasttest/Ablauf.ps1'; Zweck = 'Befunde und Abfall der Bilder/s'; Muster = '(?s)Add-RenderFindings.*Get-FpsDrop' }
        @{ Datei = 'Module/Benchmark/Ablauf.ps1'; Zweck = 'Rendertest je ausgewählter Grafikeinheit'; Muster = '(?s)Select-RenderAdapters @\(Get-RenderAdapters\) \$GpuAuswahl.*Invoke-RenderBenchmark' }
        @{ Datei = 'Module/Benchmark/Ablauf.ps1'; Zweck = 'Unterbrechungen, Sensoren beenden, dann Sensorbericht'; Muster = '(?s)Start-PauseWatch.*Stop-PauseWatch.*Stop-BenchSensors.*Write-BenchSensorReport' }
        @{ Datei = 'Module/Benchmark/Ablauf.ps1'; Zweck = 'Sensoren je Abschnitt'; Muster = "(?s)Start-BenchSensors.*Set-BenchSensorPart 'Prozessor'.*Set-BenchSensorPart 'Arbeitsspeicher'.*Set-BenchSensorPart 'Grafik'.*Set-BenchSensorPart 'Datenträger'.*Set-BenchSensorPart 'WinSAT'" }
        @{ Datei = 'Kern/Grundgeruest.ps1'; Zweck = 'Sensor-Messpunkte in den Wartepausen'; Muster = 'Add-BenchSensorSample' }
        @{ Datei = 'Kern/Grafiktest.ps1'; Zweck = 'Sensor-Messpunkte in den Wartepausen'; Muster = 'Add-BenchSensorSample' }
        @{ Datei = 'Kern/Berichtshilfen.ps1'; Zweck = 'Sensor-Messpunkte in den Wartepausen'; Muster = 'Add-BenchSensorSample' }
    ) {
        Get-SrcText $Datei | Should -Match $Muster
    }
    It 'Lasttest beendet im finally-Block alle Lasten, räumt die Lastprozesse auf und setzt den RAM-Test zurück' {
        $t = $null; $e = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput((Get-SrcText 'Module/Lasttest/Ablauf.ps1'), [ref]$t, [ref]$e)
        $fin = @($ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.TryStatementAst] -and $a.Finally -and $a.Finally.Extent.Text -match 'DiagDiskStress' }, $true))
        $fin.Count | Should -Be 1
        $f = $fin[0].Finally.Extent.Text
        foreach ($m in '\[DiagCpu\]::Stop = \$true', '\[DiagRam\]::Stop = \$true', '\[DiagDiskStress\]::Stop = \$true', '\.Run\.Stop = \$true', '\.Kill\(\)', '\.Cleanup\(\)', '\[DiagRam\]::MaxThreads = 0', 'Stop-PauseWatch') {
            $f | Should -Match $m
        }
    }
    It 'Lasttest rechnet CPU-Last nie im Arbeitsprozess an Start-LoadJob vorbei' {
        Get-SrcText 'Module/Lasttest/Ablauf.ps1' | Should -Not -Match '\[DiagCpu\]::RunAsync'
    }
}

Describe 'Sensoren während des Benchmarks' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Werkzeuge.ps1', 'Kern\Sensoren.ps1' -Functions 'Get-SafeName', 'Write-Heartbeat', 'Send-GuiEvent', 'Write-Checkpoint' -Setup @'
$script:TestLines = New-Object System.Collections.Generic.List[string]
$script:TestFindings = New-Object System.Collections.Generic.List[object]
$script:TestSamples = 0
function Show-Sub { param($a, $b, $c) }
function Hide-Sub { }
function Add-Line { param([string]$Text = '') $script:TestLines.Add($Text) }
function Add-Sub { param([string]$Title) $script:TestLines.Add('--- ' + $Title) }
function Add-Finding { param($Stufe, $Bereich, $Befund) $script:TestFindings.Add([pscustomobject]@{ Stufe = $Stufe; Bereich = $Bereich; Befund = $Befund }) }
function Out-Report { param([Parameter(ValueFromPipeline = $true)]$InputObject) begin { $a = @() } process { $a += $InputObject } end { foreach ($l in (($a | Format-Table -AutoSize | Out-String -Width 300) -split "`r?`n")) { if ($l.Trim()) { $script:TestLines.Add($l) } } } }
function Open-SensorSession { param([switch]$Treiber, [switch]$OhneDatentraeger) $script:Sens = [pscustomobject]@{ Quellen = @('Test'); Lhm = $false; Treiber = ''; Hinweise = (New-Object System.Collections.Generic.List[string]); LhmVersion = '' }; return $script:Sens }
function Get-CpuSample { $script:TestSamples++; [pscustomobject]@{ Last = 100; Leistung = 150; MaxLeistung = 160; MaxFreq = 100; MHz = 3000 + $script:TestSamples; MaxMHz = 3900; Temp = $null } }
function Test-IsArm64 { $false }
function Get-SensorReadings { param([switch]$MitDatentraeger, $CpuSample = $null)
    $t = 60 + 4 * $script:TestSamples
    @((New-SensorReading 'c' 'LHM' 'CPU' 'Test-CPU' 'Temperatur' 'CPU Package' '°C' $t '' 100), (New-SensorReading 'w' 'LHM' 'CPU' 'Test-CPU' 'Leistung' 'CPU Package' 'W' (20 + $script:TestSamples)),
      (New-SensorReading 'g' 'LHM' 'GPU' 'NVIDIA GeForce RTX 3060' 'Temperatur' 'GPU Core' '°C' (50 + $script:TestSamples)), (New-SensorReading 'x' 'Windows' 'CPU' 'Windows-Leistungszähler' 'Takt' 'CPU gesamt' 'MHz' $CpuSample.MHz 'Cpu')) }
'@
        $raw = Join-Path $TestDrive ('raw_' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory $raw -Force | Out-Null
        Set-ModuleVar 'RawDir' $raw
    }
    BeforeEach {
        & (Get-Module MinibenchTest) { $script:BenchSens = $null; $script:TestLines.Clear(); $script:TestFindings.Clear(); $script:TestSamples = 0; $script:SensorDb = [ordered]@{}; $script:Sens = $null }
    }
    It 'zeichnet je Abschnitt Messpunkte auf und hält den Abstand ein' {
        $b = MinibenchTest\Start-BenchSensors
        $b.On | Should -BeTrue
        $b.IntervallMs = 0
        MinibenchTest\Set-BenchSensorPart 'Prozessor'
        MinibenchTest\Add-BenchSensorSample; MinibenchTest\Add-BenchSensorSample
        MinibenchTest\Set-BenchSensorPart 'Grafik'
        MinibenchTest\Add-BenchSensorSample
        $b.IntervallMs = 600000
        MinibenchTest\Add-BenchSensorSample
        MinibenchTest\Stop-BenchSensors
        $b.On | Should -BeFalse
        @($b.Samples | Where-Object { $_.Teil -eq 'Prozessor' }).Count | Should -Be 2
        @($b.Samples | Where-Object { $_.Teil -eq 'Grafik' }).Count | Should -Be 1
        $b.Teile.Count | Should -Be 2
        $b.Teile[1].Ende | Should -Not -BeNullOrEmpty
        $b.TjMax | Should -Be 100
        MinibenchTest\Add-BenchSensorSample
        $b.Samples.Count | Should -Be 3
    }
    It 'ohne Start sind die Haken in den Wartepausen wirkungslos' {
        MinibenchTest\Add-BenchSensorSample
        MinibenchTest\Set-BenchSensorPart 'Prozessor'
        (Get-ModuleVar 'BenchSens') | Should -BeNullOrEmpty
    }
    It 'Bericht: Tabelle je Abschnitt, Gesamtwerte wie im Lasttest, Befund an TjMax, Datenbank und CSV' {
        $b = MinibenchTest\Start-BenchSensors
        $b.IntervallMs = 0
        MinibenchTest\Set-BenchSensorPart 'Prozessor'
        1..5 | ForEach-Object { MinibenchTest\Add-BenchSensorSample }
        MinibenchTest\Set-BenchSensorPart 'Arbeitsspeicher'
        1..3 | ForEach-Object { MinibenchTest\Add-BenchSensorSample }
        MinibenchTest\Stop-BenchSensors
        MinibenchTest\Write-BenchSensorReport
        $t = (Get-ModuleVar 'TestLines') -join "`n"
        $t | Should -Match '--- Sensoren während des Benchmarks'
        $t | Should -Match 'Leerlauf vor dem Benchmark: CPU 64 °C'
        $t | Should -Match '8 Messpunkte'
        $t | Should -Match 'Prozessor\s+\d:\d\d\s+3\.00\d MHz'
        $t | Should -Match 'Arbeitsspeicher'
        $t | Should -Match 'Gesamt über alle Messungen:'
        $t | Should -Match 'CPU-Temperatur \(Sensoren\): Leerlauf 64 °C, max 96 °C, TjMax 100 °C'
        $t | Should -Match 'CPU-Paketleistung: max 29 W'
        $t | Should -Match 'GPU NVIDIA GeForce RTX 3060: Temperatur max 59 °C'
        $t | Should -Not -Match 'Lüfter max'
        @(Get-ModuleVar 'TestFindings' | Where-Object { $_.Bereich -eq 'Benchmark' -and $_.Befund -match '96 °C bei TjMax 100 °C \(Arbeitsspeicher\)' }).Count | Should -Be 1
        $db = (Get-ModuleVar 'SensorDb')['Benchmark']
        $db.CpuTempMax | Should -Be 96
        $db.Messpunkte | Should -Be 8
        @($db.Abschnitte).Count | Should -Be 2
        Join-Path (Get-ModuleVar 'RawDir') 'Benchmark-Sensoren.csv' | Should -Exist
        @(Get-ModuleVar 'BenchSensorRows').Count | Should -Be 2
    }
    It 'Tabelle lässt Spalten ohne Werte weg' {
        $rows = @([pscustomobject]@{ Teil = 'Prozessor'; Dauer = '0:20'; CpuMhzAvg = 3000; CpuMhzMax = 3100; KernMax = $null; CpuTMax = 80; CpuWMax = $null; GpuTMax = $null; GpuMhzAvg = $null; GpuWMax = $null; IGpuTMax = $null; IGpuWMax = $null; FanMax = $null; DiskTMax = $null })
        $o = @(MinibenchTest\Format-BenchSensorTable $rows)
        @($o[0].PSObject.Properties.Name) -join ',' | Should -Be 'Abschnitt,Dauer,CPU-Takt Ø,CPU max'
        $o[0].'CPU max' | Should -Be '80 °C'
    }
    It 'gemeinsame Zeilen für Lasttest und Benchmark' {
        $s = @(
            [pscustomobject]@{ T = 3; MHz = 1000; CpuMHz = 3100; CpuTemp = 70; CpuTempQ = 'LHM'; CpuW = 30; Temp = $null; GpuTemp = $null; GpuW = $null; GpuMHz = $null; IGpuTemp = $null; IGpuW = $null; IGpuMHz = $null; Fan = 1200; DiskTemp = 40 }
            [pscustomobject]@{ T = 6; MHz = 2000; CpuMHz = 3300; CpuTemp = 90; CpuTempQ = 'LHM'; CpuW = 45; Temp = $null; GpuTemp = $null; GpuW = $null; GpuMHz = $null; IGpuTemp = $null; IGpuW = $null; IGpuMHz = $null; Fan = 1800; DiskTemp = 42 })
        $st = MinibenchTest\Get-SensorSeriesStats $s
        $l = @(MinibenchTest\Get-SensorSeriesLines $st ([pscustomobject]@{ CpuTemp = 50 }) 100 @{} '' '' -GpuErwartet)
        $l[0] | Should -Be '  CPU-Takt: min 1.000 / Ø 1.500 / max 2.000 MHz'
        $l[1] | Should -Be '  Höchster Kerntakt (LibreHardwareMonitor): min 3.100 / Ø 3.200 / max 3.300 MHz'
        $l[2] | Should -Be '  CPU-Temperatur (Sensoren): Leerlauf 50 °C, max 90 °C, TjMax 100 °C'
        $l[3] | Should -Be '  CPU-Paketleistung: max 45 W'
        $l[4] | Should -Be '  GPU: keine Sensorwerte (Takt, Temperatur, Leistung) verfügbar.'
        $l | Should -Contain '  Lüfter: max 1.800 U/min'
        $l | Should -Contain '  Datenträger: Temperatur max 42 °C'
    }
}
