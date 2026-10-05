# Version 2.65: Rückmeldungen aus den Läufen vom 02.10.2026 auf ULB-PC10039 und TORRENT (Lasttest ohne GPU-Werte,
# ungleichmäßige Bilder/s, Bildratengrenze, Auswahl der Grafikeinheit, Referenz nur über den Haken, Zuverlässigkeit,
# Voreinstellungen, einfachere Texte).

Describe 'Lasttest: Sensorwerte kommen vollständig an (Praxistest: alle Leitwerte leer)' {
    BeforeAll {
        $script:Kultur = [cultureinfo]::CurrentCulture; [cultureinfo]::CurrentCulture = 'de-DE'
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Parts 'Kern\Werkzeuge.ps1', 'Kern\Sensoren.ps1' -Functions 'Get-SafeName', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent', 'Write-Checkpoint'
        function New-Rd([string]$Gruppe, [string]$Art, [string]$Name, $Wert, [string]$Geraet = 'Gerät', [string]$Quelle = 'LHM') {
            MinibenchTest\New-SensorReading ('{0}/{1}/{2}/{3}' -f $Quelle, $Geraet, $Art, $Name) $Quelle $Gruppe $Geraet $Art $Name '' $Wert ''
        }
        # so wie Get-SensorReadings zurückgibt: ein Array, mit Komma vor dem Auspacken geschützt
        function Get-Fake { $l = New-Object System.Collections.Generic.List[object]
            $l.Add((New-Rd 'CPU' 'Temperatur' 'CPU Package' 71 '13th Gen Intel Core i9-13900H'))
            $l.Add((New-Rd 'GPU' 'Temperatur' 'GPU Core' 66 'NVIDIA RTX 3000 Ada Generation Laptop GPU'))
            $l.Add((New-Rd 'GPU' 'Takt' 'GPU Core' 1755 'NVIDIA RTX 3000 Ada Generation Laptop GPU'))
            $l.Add((New-Rd 'GPU' 'Leistung' 'GPU Package' 48.5 'NVIDIA RTX 3000 Ada Generation Laptop GPU'))
            $l.Add((New-Rd 'GPU' 'Leistung' 'GPU Power' 590 'Intel(R) Iris(R) Xe Graphics'))
            $l.Add((New-Rd 'GPU' 'Takt' 'GPU Core' 1300 'Intel(R) Iris(R) Xe Graphics'))
            MinibenchTest\Set-SensorClassification $l $null
            return , [object[]]$l.ToArray() }
    }
    It 'doppelt verpackte Liste ergibt dieselben Leitwerte wie die flache' {
        $flat = Get-Fake
        $nested = @(Get-Fake)
        $nested.Count | Should -Be 1
        $a = MinibenchTest\Get-SensorLead $flat
        $b = MinibenchTest\Get-SensorLead $nested
        $b.GpuTemp | Should -Be 66; $b.GpuMHz | Should -Be 1755; $b.GpuW | Should -Be 48.5
        $b.CpuTemp | Should -Be 71
        $b.IGpuMHz | Should -Be 1300
        $b.GpuTemp | Should -Be $a.GpuTemp
    }
    It 'unplausible Werte werden je Sensor gezählt, nicht als ein Sammelobjekt' {
        $seen = @{}
        MinibenchTest\Register-BadReadings @(Get-Fake) $seen
        $seen.Count | Should -Be 1
        $e = @($seen.Values)[0]
        $e.Geraet | Should -Be 'Intel(R) Iris(R) Xe Graphics'; $e.Name | Should -Be 'GPU Power'; $e.Max | Should -Be 590
    }
    It 'flache Liste bleibt flach, null wird übergangen' {
        @(MinibenchTest\ConvertTo-FlatReadings @($null, (New-Rd 'CPU' 'Takt' 'Core #1' 4000))).Count | Should -Be 1
        @(MinibenchTest\ConvertTo-FlatReadings $null).Count | Should -Be 0
    }
    AfterAll { [cultureinfo]::CurrentCulture = $script:Kultur }
    It 'Lasttest packt die Messwerte nicht mehr mit @() ein' {
        $t = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Lasttest/Ablauf.ps1'))
        $t | Should -Not -Match '@\(Get-SensorReadings'
        $t | Should -Match 'ConvertTo-FlatReadings \(Get-SensorReadings'
    }
    It 'Takt der Windows-Leistungszähler heißt schlicht CPU gesamt, der Leitwert findet ihn weiter' {
        $s = [pscustomobject]@{ MHz = 2450; Last = 30; MaxFreq = 100 }
        $rd = @(MinibenchTest\ConvertFrom-CpuSampleReadings $s)
        @($rd | Where-Object { $_.Art -eq 'Takt' })[0].Name | Should -Be 'CPU gesamt'
        (MinibenchTest\Get-SensorLead $rd).CpuMHz | Should -Be 2450
    }
    It 'GPU-Zeile für den Bericht mit Takt, Temperatur und Leistung' {
        $m = [pscustomobject]@{ Average = 1712.4; Maximum = 1800 }
        MinibenchTest\Get-GpuLoadLine 'NVIDIA RTX 3000' $m 74 ([double]51.2) | Should -Be 'NVIDIA RTX 3000: Takt Ø 1.712 / max 1.800 MHz, Temperatur max 74 °C, Leistung max 51,2 W'
        MinibenchTest\Get-GpuLoadLine 'X' $null $null $null | Should -BeNullOrEmpty
    }
    It 'Zuverlässigkeitszähler mit Zeitlimit: ein hängender Aufruf hält den Lauf nicht an' {
        & (Get-Module MinibenchTest) {
            function script:Get-StorageTempRaw { Start-Sleep -Seconds 20; @() }
            $script:Sens = [pscustomobject]@{ StorageTimeout = $false; Hinweise = New-Object System.Collections.Generic.List[string] }
        }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        @(MinibenchTest\Get-StorageTempReadings 1).Count | Should -Be 0
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 8
        (Get-ModuleVar 'Sens').StorageTimeout | Should -BeTrue
        $sw.Restart()
        @(MinibenchTest\Get-StorageTempReadings 1).Count | Should -Be 0
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 1
    }
}

Describe 'Grafik: Auswahl der Einheiten, Bildratengrenze, Bilder/s im Verlauf' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Parts 'Kern\Grafiktest.ps1' -Functions 'Get-GpuKind', 'Get-StatusRank'
        $script:Ads = @(
            [pscustomobject]@{ Index = 1; Name = 'NVIDIA RTX 3000 Ada Generation Laptop GPU'; Art = 'dGPU'; Bezeichnung = 'Grafikkarte' }
            [pscustomobject]@{ Index = 0; Name = 'Intel(R) Iris(R) Xe Graphics'; Art = 'iGPU'; Bezeichnung = 'Prozessorgrafik' }
        )
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
    It 'Renderer: Gegenprobe, Vorschau mit 30 Bildern je Sekunde ohne neue Speicherblöcke, GetData ohne Flush' {
        $cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Grafiktest.cs'))
        $cs | Should -Match 'public int PreviewHz = 30;'
        $cs | Should -Match 'r\.ProbeFpsLight = probe\(Math\.Max\(4, r\.Steps / 4\)'
        $cs | Should -Match 'D3D11_ASYNC_GETDATA_DONOTFLUSH = 1'
        $cs | Should -Match 'StretchDIBits\(hdc'
        $cs | Should -Match 'buf = form\.TakeSpare\('
        # Vorschau-Kopien kosten keine Messpause mehr: skipStats nur nach der Bildprüfung
        ([regex]::Matches($cs, 'r\.skipStats = 3')).Count | Should -Be 1
    }
    It 'RAM-Test im gemeinsamen Lasttest unter normaler Priorität und mit begrenzten Threads' {
        $cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Testroutinen.cs'))
        $cs | Should -Match 'po\.MaxDegreeOfParallelism = MaxThreads'
        $cs | Should -Match 'ThreadPriority\.BelowNormal'
        $t = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Lasttest/Ablauf.ps1'))
        $t | Should -Match "Start-LoadJob 'ram' .* -Low"
        $t | Should -Match '\[DiagRam\]::MaxThreads = 0; \[DiagRam\]::LowPriority = \$false'
        $t | Should -Not -Match 'Get-Volume -DriveLetter'
    }
}

Describe 'Zuverlässigkeit prominent und erklärt' {
    BeforeAll {
        $script:Kultur = [cultureinfo]::CurrentCulture; [cultureinfo]::CurrentCulture = 'de-DE'
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Functions 'Get-StabilityAssessment', 'Get-ShortText', 'Split-TextLines'
        function New-Rel([string]$Src, [int]$Id, [string]$Prod) { [pscustomobject]@{ SourceName = $Src; EventIdentifier = $Id; ProductName = $Prod; Message = '' } }
    }
    It 'ULB-PC10039 (5,24): mittel, mit Erklärung und den Ursachen' {
        $rec = @(1..7 | ForEach-Object { New-Rel 'Application Error' 1000 'PowerToys.QuickAccess.exe' }) + @(1..5 | ForEach-Object { New-Rel 'Application Error' 1000 'PowerToys.Settings.exe' }) +
            @((New-Rel 'EventLog' 6008 'Windows'), (New-Rel 'Microsoft-Windows-WindowsUpdateClient' 20 '9WZDNCRFJBMP-MICROSOFT.WINDOWSSTORE'), (New-Rel 'Microsoft-Windows-WindowsUpdateClient' 19 'KB2267602'), (New-Rel 'MsiInstaller' 1033 'Microsoft Edge'))
        $s = MinibenchTest\Get-StabilityAssessment 5.24 $rec 28
        $s.Stufe | Should -Be 'mittel'; $s.Klasse | Should -Be 'info'; $s.Text | Should -Be '5,2 von 10 (mittel)'
        $s.Erklaerung | Should -Match 'bewertet die Stabilität täglich von 1 bis 10'
        $s.Erklaerung | Should -Match '12x Programmabsturz \(meist PowerToys\.QuickAccess\.exe\)'
        $s.Erklaerung | Should -Match '1x Windows-Fehler'
        $s.Erklaerung | Should -Match '1x Update fehlgeschlagen'
        $s.Erklaerung | Should -Not -Match 'Installation fehlgeschlagen'
    }
    It 'TORRENT (10): gut, ohne Erklärung' {
        $s = MinibenchTest\Get-StabilityAssessment 10 @((New-Rel 'MsiInstaller' 1033 'Microsoft GameInput'))
        $s.Stufe | Should -Be 'gut'; $s.Erklaerung | Should -BeNullOrEmpty; $s.Ursachen.Count | Should -Be 0
    }
    It 'niedriger Wert ohne Fehler in den letzten Tagen: Hinweis auf ältere Fehler' {
        $s = MinibenchTest\Get-StabilityAssessment 3.1 @() 28
        $s.Stufe | Should -Be 'niedrig'; $s.Klasse | Should -Be 'warn'
        $s.Erklaerung | Should -Match 'erholt sich von älteren Fehlern'
    }
    AfterAll { [cultureinfo]::CurrentCulture = $script:Kultur }
    It 'kein Index, keine Bewertung' { MinibenchTest\Get-StabilityAssessment $null @() | Should -BeNullOrEmpty }
    It 'Umbruch für den Textbericht' {
        $l = @(MinibenchTest\Split-TextLines ('Wort ' * 40) 30)
        $l.Count | Should -BeGreaterThan 5
        @($l | Where-Object { $_.Length -gt 30 }).Count | Should -Be 0
    }
    It 'steht im Kopf des Textberichts, als Karte im HTML-Bericht und in der KI-Datei' {
        $ab = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Ablauf/Abschluss.ps1'))
        $ab | Should -Match "ZUVERLÄSSIGKEIT: \{0\}"
        $ht = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Bericht/HtmlBericht.ps1'))
        $ht | Should -Match 'Zuverlässigkeit von 10'
        $ki = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Bericht/KI-Datei.ps1'))
        $ki | Should -Match "Zuverlässigkeit       : "
    }
}

Describe 'Oberfläche: Voreinstellungen, 2 Minuten, Grafikeinheit, Protokoll ohne Bericht' {
    BeforeAll {
        $script:Gui = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui.cs'))
        $script:Grund = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Grundgeruest.ps1'))
    }
    It 'Lasttest auch 2 Minuten, Vorgaben bleiben 15 und 10 Minuten' {
        $script:Gui | Should -Match 'new string\[\] \{ "2 Minuten", "5 Minuten", "10 Minuten", "15 Minuten"'
        $script:Gui | Should -Match 'cmbLCpu = Combo\(120, mins, 3\)'
        $script:Gui | Should -Match 'cmbLDisk = Combo\(120, mins, 2\)'
    }
    It 'Grafikeinheit wählbar und als -GpuAuswahl übergeben' {
        $script:Gui | Should -Match 'cmbLGpuSel = Combo\(420, GpuChoiceTexts\(\), 0\)'
        $script:Gui | Should -Match 'a\.Append\(" -GpuAuswahl "\)'
    }
    It 'Voreinstellungen werden gespeichert und beim Start geladen' {
        $script:Gui | Should -Match 'Minibench-Voreinstellungen/1'
        $script:Gui | Should -Match 'Voreinstellungen\.json'
        $script:Gui | Should -Match 'FillPresets\(true\)'
        $script:Gui | Should -Match 'd\["BeimStart"\] = name'
        # die Referenz-Option wird nie aus einer Voreinstellung gesetzt
        $script:Gui | Should -Match 'if \(chkRefSave != null\) chkRefSave\.Checked = false;'
    }
    It 'jede gespeicherte Einstellung wird auch wieder angewendet' {
        $put = @([regex]::Matches($script:Gui, 'Put(?:C|Cb)\(d, "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        $get = @([regex]::Matches($script:Gui, 'Get(?:C|Cb)\(d, "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        $put.Count | Should -BeGreaterThan 15
        foreach ($k in $put) { $get | Should -Contain $k }
    }
    It 'Lauf ohne Bericht: Protokoll und Rohdaten in den Berichtsordner' {
        $script:Grund | Should -Match "Send-GuiEvent 'ORDNER' \`$OutputDir"
        $script:Gui | Should -Match 'case "ORDNER": runOutDir = Get\(p, 1\); runWorkDir = Get\(p, 2\);'
        $script:Gui | Should -Match 'Protokoll_ohne_Bericht\.txt'
        $script:Gui | Should -Match 'string saved = SaveFailureLog\(code\);'
    }
    It 'einfachere Texte ohne Task-Manager-Vergleich und ohne winsat.exe' {
        foreach ($f in 'Module/Lasttest/Ablauf.ps1', 'Module/Diagnose/Ablauf.ps1', 'Oberflaeche/DiagGui.cs', 'Bericht/HtmlBericht.ps1') {
            $t = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot $f))
            $t | Should -Not -Match '(?<!//.*)wie Task-Manager' -Because $f
        }
        $script:Gui | Should -Not -Match 'GPU-Wahl für winsat\.exe'
        $b = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Benchmark/Ablauf.ps1'))
        $b | Should -Not -Match "Add-Line \('  GPU-Wahl für winsat\.exe"
    }
}
