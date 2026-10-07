# Version 2.7: Hinweise beim Überfahren, Sensoren im Benchmark-Bericht, Versionshistorie, CPU-Stabilitätstest der
# Diagnose entfernt, Datenpflege (Lasttests vor v2.67, unvollständige und kurze Läufe ins Archiv), Bauen.cmd archiviert.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $global:V27Gui = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui.cs'))
    $global:V27Ver = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/Versionen.cs'))
    $global:V27Contract = Import-PowerShellDataFile (Join-Path $global:MinibenchSrcRoot 'Module/Diagnose/Vertrag.psd1')
}

Describe 'CPU-Stabilitätstest nur noch im Lasttest' {
    It 'Diagnose-Vertrag, Kopf und Ablauf kennen CpuTest und CpuStressSeconds nicht mehr' {
        @($global:V27Contract.Schritte | Where-Object { $_.Key -eq 'CpuTest' }).Count | Should -Be 0
        $global:V27Contract.Parameter | Should -Not -Contain 'CpuStressSeconds'
        Get-ScriptParameters | Should -Not -Contain 'CpuStressSeconds'
        (Get-MinibenchBuild).Text | Should -Not -Match '\$script:Opt\[.CpuTest.\]'
        (Get-MinibenchBuild).Text | Should -Not -Match 'CpuStressSeconds'
    }
    It 'die Oberfläche zeigt genau die Prüfungen des Vertrags, in derselben Reihenfolge' {
        $keys = @($global:V27Contract.Schritte | Where-Object { $_.Typ -eq 'Pruefung' } | ForEach-Object { $_.Key })
        $null = $global:V27Gui -match 'string\[\] diagKeys = new string\[\] \{ ([^}]+) \};'
        $gui = @($Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"') })
        ($gui -join ',') | Should -Be ($keys -join ',')
    }
    It 'Texte, Profile und Zeitschätzung haben je Prüfung genau einen Wert' {
        $n = 8
        $null = $global:V27Gui -match '(?s)string\[\] diagText = new string\[\] \{(.+?)\};'
        ([regex]::Matches($Matches[1], '"[^"]+"')).Count | Should -Be $n
        foreach ($p in 'voll', 'schnell', 'test', 'none') {
            $null = $global:V27Gui -match ('bool\[\] {0} = new bool\[\] \{{ ([^}}]+) \}};' -f $p)
            @($Matches[1] -split ',').Count | Should -Be $n -Because $p
        }
        $null = $global:V27Gui -match 'int\[\] add = new int\[\] \{ ([^}]+) \};'
        @($Matches[1] -split ',').Count | Should -Be $n
        $global:V27Gui | Should -Match 'diagChk\[7\]\.Checked \? 2 : 0'
        $global:V27Gui | Should -Not -Match 'diagChk\[8\]'
    }
}

Describe 'Oberfläche übersetzbar (C# 5)' {
    It 'DiagGui.cs, Start.cs und Versionen.cs lassen sich übersetzen' {
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGui_' + [guid]::NewGuid().ToString('N') + '.dll')
        try {
            if ($env:OS -eq 'Windows_NT') {
                # in einem Kindprozess, damit keine Typen in dieser Sitzung hängen bleiben
                $code = 'Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions; $src = @(' + (($files | ForEach-Object { "[IO.File]::ReadAllText('{0}')" -f $_ }) -join ', ') + ') -join [Environment]::NewLine; ' +
                    '$refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location); ' +
                    ('try {{ Add-Type -TypeDefinition $src -ReferencedAssemblies $refs -OutputAssembly ''{0}'' -OutputType Library -IgnoreWarnings -ErrorAction Stop; exit 0 }} catch {{ Write-Output $_.Exception.Message; exit 1 }}' -f $out)
                $msg = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $code
                $LASTEXITCODE | Should -Be 0 -Because ($msg -join ' ')
            } elseif (Get-Command mcs -ErrorAction SilentlyContinue) {
                $msg = & mcs -langversion:5 -target:library -nowarn:414,169,649,0219,1635 -r:System.Windows.Forms.dll -r:System.Drawing.dll -r:System.Web.Extensions.dll ('-out:' + $out) @files 2>&1
                $LASTEXITCODE | Should -Be 0 -Because ($msg -join ' ')
            } else { Set-ItResult -Skipped -Because 'kein C#-Compiler verfügbar' }
        } finally { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Hinweise beim Überfahren' {
    It 'jede Prüfung der Diagnose und jede Messung des Benchmarks hat einen Hinweis' {
        foreach ($k in @($global:V27Contract.Schritte | Where-Object { $_.Typ -eq 'Pruefung' } | ForEach-Object { $_.Key })) { $global:V27Gui | Should -Match ('\{{ "{0}", "[^"]{{40,}}" \}}' -f $k) -Because $k }
        foreach ($k in 'CPU', 'RAM', 'GPU', 'Disk', 'WinSAT') { $global:V27Gui | Should -Match ('\{{ "{0}", "[^"]{{40,}}" \}}' -f $k) -Because $k }
    }
    It 'Hinweise werden für Einrichtung und Laufansicht gesetzt' {
        $global:V27Gui | Should -Match '(?s)ApplySetupTips\(\);\s+return p;'
        $global:V27Gui | Should -Match '(?s)ApplyRunTips\(\);\s+return p;'
        foreach ($c in 'rbVoll', 'chkFast', 'chkInstall', 'chkMem', 'cmbBenchDur', 'cmbRef', 'chkRefSave', 'chkLCpu', 'chkLGpu', 'cmbLAbortCpu', 'chkRestorePoint', 'cmbDriver', 'cmbKeep', 'btnDbClean', 'chkAnon', 'btnStart', 'btnStopWait', 'btnCancel', 'btnCopy', 'tabs') {
            $global:V27Gui | Should -Match ('Tip\({0}, "' -f $c) -Because $c
        }
    }
    It 'Hinweise ohne Spiegelstrich-Aufzählung' {
        foreach ($m in [regex]::Matches($global:V27Gui, 'Tip\([^,]+, "([^"]+)"')) { $m.Groups[1].Value | Should -Not -Match '(^|\\n)\s*[-–] ' }
    }
    It 'Umbruch nach rund 90 Zeichen, vorhandene Umbrüche bleiben' {
        $code = [regex]::Match($global:V27Gui, '(?s)public static string WrapTip\(string s\)\s*\{.+?\n    \}').Value
        if (-not ('TipProbe' -as [type])) { Add-Type -TypeDefinition ("using System; using System.Text; public static class TipProbe { " + $code + " }") }
        $w = [TipProbe]::WrapTip(('wort ' * 60).Trim() + "`r`nzweiter Absatz")
        foreach ($l in ($w -split "`r`n")) { $l.Length | Should -BeLessOrEqual 90 }
        $w | Should -Match "`r`nzweiter Absatz$"
        [TipProbe]::WrapTip('') | Should -Be ''
    }
}

Describe 'Versionshistorie' {
    It 'nennt die aktuelle Version als ersten Eintrag' {
        $v = (Get-MinibenchBuild).Version
        $first = [regex]::Match($global:V27Ver, 'new Eintrag\("([^"]+)"').Groups[1].Value
        $first | Should -Be $v
    }
    It 'reicht von 1.0 bis heute, jede Version mit Änderungsdatei hat einen Eintrag' {
        $vs = @([regex]::Matches($global:V27Ver, 'new Eintrag\("([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        $vs | Should -Contain '1.0'
        $vs | Should -Contain '1.8'
        $vs | Should -Contain '2.0 bis 2.1'
        foreach ($f in @(Get-ChildItem (Join-Path $global:MinibenchRepoRoot 'Doku') -Filter 'Änderungen_v*.txt')) {
            $x = $f.BaseName -replace '^Änderungen_v', ''
            $vs | Should -Contain $x -Because $f.Name
        }
    }
    It 'Doku\Versionshistorie.txt enthält jede Version' {
        $t = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Doku/Versionshistorie.txt'))
        foreach ($m in [regex]::Matches($global:V27Ver, 'new Eintrag\("([^"]+)"')) { $t | Should -Match ([regex]::Escape('VERSION ' + $m.Groups[1].Value)) }
    }
    It 'die Seite Versionen ist eingebunden' {
        $global:V27Gui | Should -Match 'versionPage = pages\.Count; pages\.Add\(BuildVersionPage\(\)\)'
        $global:V27Gui | Should -Match 'lnkVer\.Text = "Versionshistorie"'
        [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/Oberflaeche.ps1')) | Should -Match '#>> EINBINDEN Oberflaeche\\Versionen\.cs'
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
function Get-SensorReadings { param([switch]$MitDatentraeger, $CpuSample = $null)
    $t = 60 + 4 * $script:TestSamples
    @((New-SensorReading 'c' 'LHM' 'CPU' 'Test-CPU' 'Temperatur' 'CPU Package' '°C' $t '' 100), (New-SensorReading 'w' 'LHM' 'CPU' 'Test-CPU' 'Leistung' 'CPU Package' 'W' (20 + $script:TestSamples)),
      (New-SensorReading 'g' 'LHM' 'GPU' 'NVIDIA GeForce RTX 3060' 'Temperatur' 'GPU Core' '°C' (50 + $script:TestSamples)), (New-SensorReading 'x' 'Windows' 'CPU' 'Windows-Leistungszähler' 'Takt' 'CPU gesamt' 'MHz' $CpuSample.MHz 'Cpu')) }
'@
        $RawDir = Join-Path $TestDrive 'raw'; New-Item -ItemType Directory $RawDir -Force | Out-Null
        Set-ModuleVar 'RawDir' $RawDir
        [Threading.Thread]::CurrentThread.CurrentCulture = 'de-DE'
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
        @($b.Samples | Where-Object Teil -eq 'Prozessor').Count | Should -Be 2
        @($b.Samples | Where-Object Teil -eq 'Grafik').Count | Should -Be 1
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
    It 'gemeinsame Zeilen für Lasttest und Benchmark (Werte wie bisher im Lasttest)' {
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
    It 'Lasttest nutzt die gemeinsame Auswertung, Benchmark zeichnet in allen Wartepausen auf' {
        $l = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Lasttest/Ablauf.ps1'))
        $l | Should -Match 'Get-SensorSeriesStats \$loadS'
        $l | Should -Match 'Get-SensorSeriesLines \$sst'
        $b = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Benchmark/Ablauf.ps1'))
        foreach ($p in 'Prozessor', 'Arbeitsspeicher', 'Grafik', 'Datenträger', 'WinSAT') { $b | Should -Match ("Set-BenchSensorPart '{0}'" -f $p) }
        $b | Should -Match 'Start-BenchSensors'
        $b | Should -Match '(?s)Stop-PauseWatch.*Stop-BenchSensors.*Write-BenchSensorReport'
        foreach ($f in 'Kern/Grundgeruest.ps1', 'Kern/Grafiktest.ps1', 'Kern/Berichtshilfen.ps1') { [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot $f)) | Should -Match 'Add-BenchSensorSample' -Because $f }
        [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Bericht/HtmlBericht.ps1')) | Should -Match 'Sensoren während des Benchmarks'
        [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Bericht/KI-Datei.ps1')) | Should -Match 'SENSOREN WÄHREND DES BENCHMARKS'
    }
    It 'der Benchmark fragt vor dem Start nach dem PawnIO-Treiber wie Diagnose und Lasttest' {
        $global:V27Gui | Should -Match 'nav\[1\]\.Checked \|\| nav\[2\]\.Checked\) \{ int d = AskDriver\(\)'
    }
}

Describe 'HTML-Kurven für Benchmark und Lasttest' {
    It 'HTML: Kurven der Benchmark-Sensoren mit Marken je Abschnitt (gleiche Funktion wie im Lasttest)' {
        Import-MinibenchTestModule -Functions 'New-LoadChartsHtml', 'New-MultiLineSvg', 'Get-ChartScale', 'Get-ChartMarkLayout', 'ConvertTo-HtmlText'
        $s = @(for ($i = 0; $i -lt 12; $i++) { [pscustomobject]@{ T = 2 * $i; MHz = 3000 + 50 * $i; CpuMHz = 4000 + 20 * $i; CpuTemp = 60 + 3 * $i; CpuTempQ = 'LHM'; CpuW = 20 + $i; Temp = $null; GpuTemp = $null; GpuMHz = $null; GpuW = $null; IGpuTemp = $null; IGpuMHz = $null; IGpuW = $null; Fan = $null; DiskTemp = $null; GpuLoad = $null; IGpuLoad = $null; Fps = $null; Fps2 = $null; Cpu = $false } })
        $h = MinibenchTest\New-LoadChartsHtml -Series $s -Throttle $null -Abort $null -Limits ([pscustomobject]@{ Cpu = 0; Gpu = 0; TjMax = 100 }) -Marken @(@{ T = 10; Label = 'Arbeitsspeicher' }) -GpuLoad @()
        $h | Should -Match '<h3>Temperatur \(°C\)</h3>'
        $h | Should -Match '<h3>Takt \(MHz\)</h3>'
        $h | Should -Match '<h3>Leistung \(W\)</h3>'
        $h | Should -Match 'Arbeitsspeicher'
        $h | Should -Match 'TjMax 100 °C'
        $h | Should -Not -Match 'Drosselnachweis'
        $h | Should -Not -Match 'Abbruchschwelle'
    }
    It 'Lasttest: Marken für Abbruch und Ende der CPU-Last bleiben' {
        $s = @(for ($i = 0; $i -lt 12; $i++) { [pscustomobject]@{ T = 3 * $i; MHz = 3000; CpuMHz = 4000 + 20 * $i; CpuTemp = 60 + 3 * $i; CpuTempQ = 'LHM'; CpuW = 20 + $i; Temp = $null; GpuTemp = $null; GpuMHz = $null; GpuW = $null; IGpuTemp = $null; IGpuMHz = $null; IGpuW = $null; Fan = $null; DiskTemp = $null; GpuLoad = $null; IGpuLoad = $null; Fps = $null; Fps2 = $null; Cpu = ($i -lt 8) } })
        $h = MinibenchTest\New-LoadChartsHtml -Series $s -Throttle $null -Abort $null -Limits $null -GpuLoad @()
        $h | Should -Match 'CPU-Last Ende'
        $h2 = MinibenchTest\New-LoadChartsHtml -Series $s -Throttle $null -Abort ([pscustomobject]@{ T = 15; Grund = 'x' }) -Limits $null -GpuLoad @()
        $h2 | Should -Match '>Abbruch<'
    }
}

Describe 'Datenpflege' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Datenpflege.ps1' -Functions 'Send-GuiEvent'
        function New-Entry([string]$Dir, [string]$Name, [string]$Version, [string]$Module, $Werte = @{}, [string]$Lasttest = '', [string]$Ordner = '') {
            $o = [ordered]@{ Format = 'PC-Diagnose-DB/2'; Name = $Name; Computer = ($Name -split '_')[0]; Datum = '2026-10-01 10:00'; Version = $Version; Module = $Module; Werte = $Werte; Lasttest = $Lasttest; Ordner = $Ordner }
            [IO.File]::WriteAllText((Join-Path $Dir ($Name + '.json')), ($o | ConvertTo-Json -Depth 4), [Text.Encoding]::UTF8)
        }
        function New-Report([string]$Root, [string]$Name, [string]$Version = '2.67', [string]$Module = 'Benchmark (CPU)', [switch]$Teilweise, [switch]$Leer) {
            $d = Join-Path $Root $Name; New-Item -ItemType Directory $d -Force | Out-Null
            if ($Leer) { return $d }
            if ($Teilweise) { [IO.File]::WriteAllText((Join-Path $d 'Diagnosebericht_teilweise.txt'), 'teilweise'); return $d }
            [IO.File]::WriteAllText((Join-Path $d 'Diagnosebericht.txt'), ("####`r`n  LEOS MINIBENCH: DIAGNOSEBERICHT   PC   v{0}`r`n####`r`n  Erstellt     : heute`r`n  Module       : {1}`r`n" -f $Version, $Module), [Text.Encoding]::UTF8)
            return $d
        }
        function New-Fall {
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $db = Join-Path $root 'Datenbank'; $rep = Join-Path $root 'Berichte'; $vgl = Join-Path $rep 'Vergleiche'
            foreach ($d in $db, $rep, $vgl, (Join-Path $root 'Cache'), (Join-Path $root 'Laufzeit/PC1'), (Join-Path $root 'Laufzeit/PC2')) { New-Item -ItemType Directory $d -Force | Out-Null }
            # vor v2.67: Benchmark 2.6 und Import 1.8 bleiben (Rechenwerk unverändert), Lasttest 2.66 geht, reine Diagnose 2.4 bleibt
            New-Entry $db 'PC1_20261002_125328' '2.6' 'Diagnose (vollständig) + Benchmark (CPU)' @{ 'CPU|MT' = 33704 } '' 'Berichte\PC1_20261002_1225'; New-Report $rep 'PC1_20261002_1225' '2.6' | Out-Null
            New-Entry $db 'LIZZZ_20260930_161500' '1.8' 'Import' @{ 'CPU|MT' = 28286 }
            New-Entry $db 'PC1_20261003_133426' '2.66' 'Lasttest (CPU 2 Min.)' @{} 'Dauer 00:00:34 (vorzeitig beendet), Prozessor OK' 'Berichte\PC1_20261003_1332'; New-Report $rep 'PC1_20261003_1332' '2.66' 'Lasttest (CPU 2 Min.)' | Out-Null
            New-Entry $db 'PC2_20261002_090000' '2.4' 'Diagnose (vollständig)' @{} '' 'Berichte\PC2_20261002_0900'; New-Report $rep 'PC2_20261002_0900' '2.4' 'Diagnose (vollständig)' | Out-Null
            # ab v2.67: vollständig (bleibt), kurz (Lasttest nach 20 s von Hand beendet), ohne Messergebnis, Funktionstest
            New-Entry $db 'PC1_20261003_142535' '2.67' 'Benchmark (CPU)' @{ 'CPU|MT' = 44540 } '' 'Berichte\PC1_20261003_1421'; New-Report $rep 'PC1_20261003_1421' | Out-Null
            New-Entry $db 'PC1_20261003_150000' '2.7' 'Lasttest (CPU 2 Min.)' @{} 'Dauer 00:00:20 (vorzeitig beendet), Prozessor OK' 'Berichte\PC1_20261003_1459'; New-Report $rep 'PC1_20261003_1459' '2.7' 'Lasttest (CPU 2 Min.)' | Out-Null
            New-Entry $db 'PC1_20261003_151000' '2.7' 'Lasttest (CPU 2 Min.)' @{} 'Dauer 00:01:50 (vorzeitig beendet), Prozessor OK'
            New-Entry $db 'PC1_20261003_152000' '2.7' 'Lasttest (CPU 2 Min.)' @{} 'Dauer 00:00:40 (abgebrochen: CPU 100 °C), Prozessor Warnung'
            New-Entry $db 'PC1_20261003_153000' '2.7' 'Lasttest (Disk 10 Min.)' @{} ''
            New-Entry $db 'PC1_20261003_154000' '2.7' 'Diagnose (Funktionstest)' @{} ''
            # Berichtsordner: abgebrochen, leer, alter Lauf ohne Datenbankeintrag, laufender Lauf (Absturzanalyse ausstehend)
            New-Report $rep 'PC1_20261003_1413' -Teilweise | Out-Null
            New-Report $rep 'PC1_20261002_1302' -Leer | Out-Null
            New-Report $rep 'PC3_20261001_1808' '2.3' 'Diagnose (vollständig) + Lasttest (CPU 5 Min.)' | Out-Null
            New-Report $rep 'PC3_20261001_1700' '2.3' 'Diagnose (vollständig) + Benchmark (CPU)' | Out-Null
            $busy = New-Report $rep 'PC1_20261003_1600' -Teilweise
            [IO.File]::WriteAllText((Join-Path $root 'Laufzeit/PC1/laufend.json'), (@{ OutputDir = $busy; Version = '2.7' } | ConvertTo-Json))
            # Vergleiche: mit alter Quelle, mit aktuellen Quellen
            [IO.File]::WriteAllText((Join-Path $vgl 'Vergleich_alt.html'), '<html><footer>Leos Minibench 2.65. Quellen: PC1_20261002_125328.json, LIZZZ_20260930_161500.json</footer></html>')
            [IO.File]::WriteAllText((Join-Path $vgl 'Vergleich_last.html'), '<html><footer>Leos Minibench 2.66. Quellen: PC1_20261003_133426.json, LIZZZ_20260930_161500.json</footer></html>')
            [IO.File]::WriteAllText((Join-Path $vgl 'Vergleich_neu.html'), '<html><footer>Leos Minibench 2.7. Quellen: PC1_20261003_142535.json, PC2_20261002_090000.json</footer></html>')
            [IO.File]::WriteAllText((Join-Path $root 'Referenz.json'), (@{ Name = 'TORRENT'; Version = '2.6'; Werte = @{ 'CPU|MT' = 38439 } } | ConvertTo-Json))
            # Cache: zwei Übersetzungen derselben Oberfläche, Reste der Live-Ansicht
            $c1 = Join-Path $root 'Cache/LeosMinibench-Grafik-aaaaaaaaaaaa.dll'; $c2 = Join-Path $root 'Cache/LeosMinibench-Grafik-bbbbbbbbbbbb.dll'
            [IO.File]::WriteAllText($c1, 'alt'); [IO.File]::WriteAllText($c2, 'neu'); (Get-Item $c1).LastWriteTime = (Get-Date).AddDays(-1)
            $so = Join-Path $root 'Laufzeit/PC2/sensor.stop'; [IO.File]::WriteAllText($so, '1'); (Get-Item $so).LastWriteTime = (Get-Date).AddDays(-1)
            # smartmontools: nur smartctl.exe und drivedb.h werden gebraucht
            $sm = Join-Path $root 'Tools/smartmontools/bin'; New-Item -ItemType Directory $sm -Force | Out-Null
            foreach ($n in 'smartctl.exe', 'drivedb.h', 'smartd.exe', 'runcmdu.exe') { [IO.File]::WriteAllText((Join-Path $sm $n), 'x') }
            return $root
        }
    }
    It 'Versionsnummern als Dezimalzahl: 2.7 liegt nach 2.67' {
        MinibenchTest\ConvertTo-VersionNumber '2.7' | Should -BeGreaterThan (MinibenchTest\ConvertTo-VersionNumber '2.67')
        MinibenchTest\ConvertTo-VersionNumber 'v2.65' | Should -Be 2.65
        MinibenchTest\ConvertTo-VersionNumber '1.x' | Should -Be 1
        MinibenchTest\Test-MessreiheAktuell '2.67' | Should -BeTrue
        MinibenchTest\Test-MessreiheAktuell '2.66' | Should -BeFalse
        MinibenchTest\Test-MessreiheAktuell '3.0' | Should -BeTrue
    }
    It 'Plan: ordnet Lasttests vor v2.67, unvollständige und kurze Läufe richtig ein und lässt den Rest' {
        $root = New-Fall
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root -NurPlan
        $p = $r.Zeilen -join "`n"
        $p | Should -Match 'Datenbank[\\/]PC1_20261003_133426\.json -> Lasttest_vor_v2\.67[\\/]Datenbank: Lasttest aus v2\.66'
        $p | Should -Match 'Berichte[\\/]PC1_20261003_1332 -> Lasttest_vor_v2\.67[\\/]Berichte'
        $p | Should -Match 'PC1_20261003_150000\.json -> Kurz[\\/]Datenbank: Lasttest nach 20 s von Hand beendet'
        $p | Should -Match 'Berichte[\\/]PC1_20261003_1459 -> Kurz[\\/]Berichte'
        $p | Should -Match 'PC1_20261003_153000\.json -> Kurz[\\/]Datenbank: Lauf ohne Messergebnis'
        $p | Should -Match 'PC1_20261003_154000\.json -> Kurz[\\/]Datenbank: Funktionstest'
        $p | Should -Match 'Berichte[\\/]PC1_20261003_1413 -> Unvollstaendig[\\/]Berichte: Lauf ohne Bericht'
        $p | Should -Match 'Berichte[\\/]PC1_20261002_1302 -> Unvollstaendig[\\/]Berichte: leerer Berichtsordner'
        $p | Should -Match 'Berichte[\\/]PC3_20261001_1808 -> Lasttest_vor_v2\.67[\\/]Berichte: Lasttest aus v2\.3'
        $p | Should -Match 'Vergleich_last\.html -> Lasttest_vor_v2\.67[\\/]Vergleiche: Systemvergleich mit Läufen, die ins Archiv gehen \(PC1_20261003_133426\.json\)'
        foreach ($keep in 'PC2_20261002_090000', 'PC1_20261003_142535', 'PC1_20261003_151000', 'PC1_20261003_152000', 'PC1_20261003_1600', 'Vergleich_neu', 'Vergleich_alt', 'PC1_20261003_1421', 'PC2_20261002_0900', 'PC1_20261002_125328', 'PC1_20261002_1225', 'LIZZZ_20260930_161500', 'PC3_20261001_1700', 'Referenz') { $p | Should -Not -Match $keep -Because $keep }
        $r.Verschoben | Should -Be 0
        Join-Path $root 'Datenbank/PC1_20261002_125328.json' | Should -Exist
        Join-Path $root 'Referenz.json' | Should -Exist
        $r.Kurz | Should -Match 'würden ins Archiv verschoben$'
    }
    It 'verschiebt ins Archiv, protokolliert und räumt Cache und Live-Reste auf; ein zweiter Lauf findet nichts mehr' {
        $root = New-Fall
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root
        $r.Fehler | Should -Be 0
        $r.Verschoben | Should -Be 12
        $a = Join-Path $root 'Archiv'
        Join-Path $root 'Tools/smartmontools/bin/smartctl.exe' | Should -Exist
        Join-Path $root 'Tools/smartmontools/bin/drivedb.h' | Should -Exist
        Join-Path $root 'Tools/smartmontools/bin/smartd.exe' | Should -Not -Exist
        Join-Path $a 'Werkzeuge_unbenutzt/smartmontools/bin/runcmdu.exe' | Should -Exist
        $a = Join-Path $root 'Archiv'
        Join-Path $a 'Lasttest_vor_v2.67/Datenbank/PC1_20261003_133426.json' | Should -Exist
        Join-Path $a 'Lasttest_vor_v2.67/Berichte/PC1_20261003_1332/Diagnosebericht.txt' | Should -Exist
        Join-Path $a 'Lasttest_vor_v2.67/Vergleiche/Vergleich_last.html' | Should -Exist
        Join-Path $a 'Unvollstaendig/Berichte/PC1_20261003_1413/Diagnosebericht_teilweise.txt' | Should -Exist
        Join-Path $a 'Kurz/Datenbank/PC1_20261003_154000.json' | Should -Exist
        Join-Path $root 'Datenbank/PC1_20261003_142535.json' | Should -Exist
        Join-Path $root 'Datenbank/PC2_20261002_090000.json' | Should -Exist
        Join-Path $root 'Berichte/PC1_20261003_1600' | Should -Exist
        Join-Path $root 'Referenz.json' | Should -Exist
        Join-Path $root 'Datenbank/PC1_20261002_125328.json' | Should -Exist
        Join-Path $root 'Datenbank/LIZZZ_20260930_161500.json' | Should -Exist
        Join-Path $root 'Cache/LeosMinibench-Grafik-bbbbbbbbbbbb.dll' | Should -Exist
        Join-Path $root 'Cache/LeosMinibench-Grafik-aaaaaaaaaaaa.dll' | Should -Not -Exist
        Join-Path $root 'Laufzeit/PC2' | Should -Not -Exist
        Join-Path $root 'Laufzeit/PC1/laufend.json' | Should -Exist
        [IO.File]::ReadAllText((Join-Path $a 'Datenpflege.log')) | Should -Match 'Lasttest_vor_v2\.67'
        $r.Kurz | Should -Be '1 Lasttest vor v2.67, 3 kurze Läufe, 2 unvollständige Läufe, 2 ungenutzte Dateien von smartmontools ins Archiv verschoben'
        $r2 = MinibenchTest\Invoke-Datenpflege -DataDir $root
        $r2.Verschoben | Should -Be 0
        $r2.Kurz | Should -Be 'nichts zu archivieren'
    }
    It 'frische Läufe bleiben beim Start der Oberfläche liegen (Mindestalter), alte Lasttests nicht' {
        $root = New-Fall
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root -MindestAlterMin 60 -NurPlan
        $p = $r.Zeilen -join "`n"
        $p | Should -Not -Match 'Kurz[\\/]'
        $p | Should -Not -Match 'Unvollstaendig'
        $p | Should -Match 'Lasttest_vor_v2\.67'
    }
    It 'eigenes Archiv (Bauen.cmd) und gleichnamige Ziele werden nicht überschrieben' {
        $root = New-Fall
        $arc = Join-Path $TestDrive ('arc' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory (Join-Path $arc 'Kurz/Datenbank') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $arc 'Kurz/Datenbank/PC1_20261003_154000.json'), 'schon da')
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root -ArchivDir $arc
        $r.Archiv | Should -Be $arc
        [IO.File]::ReadAllText((Join-Path $arc 'Kurz/Datenbank/PC1_20261003_154000.json')) | Should -Be 'schon da'
        Join-Path $arc 'Kurz/Datenbank/PC1_20261003_154000_2.json' | Should -Exist
        Join-Path $root 'Archiv' | Should -Not -Exist
    }
    It 'ohne Datenordner geschieht nichts' {
        (MinibenchTest\Invoke-Datenpflege -DataDir '').Kurz | Should -Be 'kein Datenordner'
    }
    It 'ist eingebunden: Parameter, ohne Adminrechte, vor der Oberfläche, Start der Oberfläche, Import, Verlauf, Bauen.cmd' {
        Get-ScriptParameters | Should -Contain 'Datenpflege'
        Get-ScriptParameters | Should -Contain 'ArchivDir'
        $plan = (Get-MinibenchBuild).Teile
        [array]::IndexOf(@($plan), 'Kern\Datenpflege.ps1') | Should -BeLessThan ([array]::IndexOf(@($plan), 'Oberflaeche\Oberflaeche.ps1'))
        [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Adminrechte.ps1')) | Should -Match '-not \$Datenpflege'
        [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/Oberflaeche.ps1')) | Should -Match 'Invoke-Datenpflege -DataDir \$script:DataDir -MindestAlterMin 60'
        $b = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'))
        $b | Should -Match '-Datenpflege -DatenDir \$bData -ArchivDir'
        $b | Should -Match "Archiv\\v\{0\}' -f \`$oldVer"
        $b | Should -Not -Match 'Copy-Item -LiteralPath \$notes'
    }
    It 'Dateiversion der exe: zweistellige Nachkommastellen (2.7 nach 2.67)' {
        $b = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'))
        $code = [regex]::Match($b, '(?s)    \$vp = @\(.+?\$asmVer = .+?\r?\n').Value
        $code | Should -Not -BeNullOrEmpty
        $f = [scriptblock]::Create('param($ver) ' + $code + '; $asmVer')
        & $f '2.7' | Should -Be '2.70.0.0'
        & $f '2.67' | Should -Be '2.67.0.0'
        & $f '3.0' | Should -Be '3.0.0.0'
    }
}
