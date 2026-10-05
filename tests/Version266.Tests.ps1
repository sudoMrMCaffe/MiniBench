# Version 2.66: Rückmeldungen vom 03.10.2026 (ungleichmäßige Last auf mehreren PCs, unzuverlässige Sensoren auf dem
# Ryzen 5 5600, KI-Auftrag mit Weg in der Oberfläche und fertigen PowerShell-Befehlen, keine Rückfrage vor dem Grafiktest).

Describe 'Gleichmäßige Last: Lastschleifen sind für die Speicherbereinigung schnell anhaltbar' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        if (-not ('DiagPause' -as [type])) {
            $cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Testroutinen.cs'))
            Add-Type -TypeDefinition $cs
        }
        $script:Cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Testroutinen.cs'))
    }
    It 'CPU-Rechendurchlauf in Abschnitten zu höchstens 10.000 Schritten, eigene Methode ohne Einbetten' {
        $script:Cs | Should -Match '\[MethodImpl\(MethodImplOptions\.NoInlining\)\]\s+public static void WorkPart'
        [DiagCpu]::WorkChunk | Should -BeLessOrEqual 10000
        [DiagCpu]::WorkSteps | Should -Be 1500000
    }
    It 'Abschnitte ergeben dasselbe Ergebnis wie ein Durchlauf am Stück (Referenzwerte bleiben gültig)' {
        foreach ($seed in 1, 7, 16) {
            $x = [double]($seed % 1000) + 1.5
            $h = ([uint64]$seed) -bxor [uint64]::Parse('CBF29CE484222325', 'AllowHexSpecifier')
            [DiagCpu]::WorkPart([ref]$x, [ref]$h, 1, 1500000)
            [DiagCpu]::Work([uint64]$seed) | Should -Be $h
        }
    }
    It 'RAM-Mustertest in Abschnitten zu 2 MB statt ganzer 256-MB-Blöcke' {
        $script:Cs | Should -Match 'const int Slice = 1 << 18;'
        $script:Cs | Should -Match '\[MethodImpl\(MethodImplOptions\.NoInlining\)\]\s+static void FillSlice'
        $script:Cs | Should -Match '\[MethodImpl\(MethodImplOptions\.NoInlining\)\]\s+static void VerifySlice'
        $script:Cs | Should -Not -Match 'for \(int i = 0; i < b\.Length; i\+\+\) b\[i\] = Expected'
    }
    It 'RAM-Mustertest findet in Abschnitten weiter keine Fehler und zählt den ganzen Block' {
        [DiagRam]::Stop = $false
        $txt = [DiagRam]::Run(256MB, 1)
        [DiagRam]::Errors | Should -Be 0
        [DiagRam]::BytesTested | Should -Be 256MB
        $txt | Should -Match 'Fehler\s+: 0'
    }
}

Describe 'Unterbrechungen der Last messen' {
    BeforeAll {
        $script:Kultur = [cultureinfo]::CurrentCulture; [cultureinfo]::CurrentCulture = 'de-DE'
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Functions 'Get-PauseAssessment'
        if (-not ('DiagPause' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Testroutinen.cs'))) }
    }
    AfterAll { [cultureinfo]::CurrentCulture = $script:Kultur }
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
    It 'Lasttest und Benchmark messen und berichten die Unterbrechungen' {
        $l = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Lasttest/Ablauf.ps1'))
        $l | Should -Match 'Start-PauseWatch'
        $l | Should -Match 'Stop-PauseWatch'
        $l | Should -Match "Unterbrechungen \{0\}: \{1\}"
        # ab v2.7 gibt es den CPU-Stabilitätstest der Diagnose nicht mehr
        $d = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Diagnose/Ablauf.ps1'))
        $d | Should -Not -Match "Start-LoadJob 'cpu'"
        $b = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Benchmark/Ablauf.ps1'))
        $b | Should -Match 'Unterbrechungen während der Messungen'
    }
}

Describe 'Sensoren: verspätete Abfragen und Datenträger (Ryzen 5 5600)' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        $script:Cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Sensoren.cs'))
        $script:Ps = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Sensoren.ps1'))
    }
    It 'Lesethread mit höchster Priorität, alte Werte höchstens 10 s, Ausfall erst nach 30 s' {
        $script:Cs | Should -Match 't\.Name = "LHM Read"; t\.Priority = System\.Threading\.ThreadPriority\.Highest'
        $script:Cs | Should -Match 'public static int HangAfterMs = 30000, StaleMaxMs = 10000;'
    }
    It 'Datenträger in eigenem Thread, Momentaufnahme wartet bis 15 Sekunden' {
        $script:Cs | Should -Match 't\.Name = "LHM Datenträger"'
        $script:Ps | Should -Match '\[DiagSensors\]::StorageWaitMs = \$\(if \(\$MitDatentraeger\) \{ 15000 \} else \{ 0 \}\)'
    }
    It 'verzögerte Abfragen stehen im Bericht' {
        $script:Ps | Should -Match 'function Get-SensorDelayText'
        # ab v2.7 über die gemeinsame Auswertung für Lasttest und Benchmark (Get-SensorSeriesLines)
        [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Lasttest/Ablauf.ps1')) | Should -Match 'Get-SensorSeriesLines'
        $script:Ps | Should -Match '(?s)function Get-SensorSeriesLines.+?Get-SensorDelayText'
    }
}

Describe 'KI-Auftrag: Weg in der Oberfläche und fertige PowerShell-Befehle' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Parts 'Kern\Modulvertrag.ps1' -Functions 'Get-KiPrompt'
        $script:P = MinibenchTest\Get-KiPrompt
    }
    It 'verlangt je Schritt den Klickpfad und einen fertigen Befehlsblock mit Prüfung und Rückweg' {
        $script:P | Should -Match 'In der Oberfläche: der genaue Klickpfad'
        $script:P | Should -Match 'Sofort per PowerShell: ein fertiger Befehlsblock'
        $script:P | Should -Match 'keine Platzhalter'
        $script:P | Should -Match 'Befehl zum Rückgängigmachen'
        $script:P | Should -Match 'Zum Schluss von C alle PowerShell-Befehle noch einmal in einem einzigen Block'
        $script:P | Should -Not -Match '(?m)^F\. '
    }
    It 'nennt die Reparaturen von Leos Minibench aus dem Modulvertrag' {
        $script:P | Should -Match 'Reparaturen in Leos Minibench \(Seite Reparatur'
        $script:P | Should -Match 'Schnellstart deaktivieren'
        $script:P | Should -Match 'Systemdateien reparieren \(sfc /scannow\)'
    }
    It 'erklärt die Unterbrechungsmessung' { $script:P | Should -Match 'Unterbrechungen der Last' }
    It 'ohne Spiegelstriche als Aufzählung' { @($script:P -split "`r?`n" | Where-Object { $_ -match '^\s*- ' }).Count | Should -Be 0 }
}

Describe 'Oberfläche: Grafik-Lasttest ohne Rückfrage' {
    BeforeAll { . (Join-Path $PSScriptRoot 'Hilfen.ps1') }
    It 'keine Warnung vor dem Start' {
        $g = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui.cs'))
        $g | Should -Not -Match 'Der Grafik-Lasttest belastet'
        $g | Should -Not -Match '"Grafik-Lasttest", MessageBoxButtons'
    }
}
