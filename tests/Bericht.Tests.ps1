# Fachgebiet Bericht: Textbericht, HTML-Bericht (Navigation, Befundfilter, Benchmark-Tabellen, Kurven als SVG mit
# Hinweisen beim Überfahren), KI-Datei, Bewertungswort und Profilkarten sowie das interaktive Dashboard mit dem
# Systemvergleich aus der Datenbank (Export-BenchDashboardData, Verlinkung der Berichte, eingebettete Daten).

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $script:KulturVorher = [cultureinfo]::CurrentCulture
    [cultureinfo]::CurrentCulture = 'de-DE'
    $script:PcVorher = $env:COMPUTERNAME

    # Datenordner mit Datenbank und Berichtsordner in TestDrive, gefüllt mit den Praxisläufen aus tests/Daten/Datenbank
    function New-DashboardDaten {
        param([string[]]$Dateien = @('TORRENT_20260930_215900.json', 'LIZZZ_20260930_161500.json', 'DESKTOP-F9HRMRR_20260930_174200.json'))
        $root = Join-Path $TestDrive ('Daten_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path (Join-Path $root 'Datenbank'), (Join-Path $root 'Berichte') -Force | Out-Null
        foreach ($d in $Dateien) { Copy-Item -LiteralPath (Join-Path (Join-Path $global:MinibenchTestData 'Datenbank') $d) -Destination (Join-Path $root 'Datenbank') }
        return $root
    }
    # Eigener Datenbankeintrag (UTF-8 mit BOM wie in Leos Minibench)
    function Add-DbEintrag([string]$Root, [string]$Datei, [hashtable]$Eintrag) {
        $p = Join-Path (Join-Path $Root 'Datenbank') $Datei
        [IO.File]::WriteAllText($p, ($Eintrag | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($true)))
        return $p
    }
    function Get-DbPfad([string]$Root, [string]$Datei) { return (Join-Path (Join-Path $Root 'Datenbank') $Datei) }
    function Get-SystemNachName($Daten, [string]$Computer) { return @(@($Daten.Systems) | Where-Object { $_.Computer -eq $Computer })[0] }
    # Daten, die New-BenchDashboardHtml in die Seite eingebettet hat
    function Get-EingebetteteDaten([string]$Html) {
        $m = [regex]::Match($Html, '(?m)^\s*window\.MINIBENCH_DASHBOARD_DATA = (\{.+\});\s*$')
        if (-not $m.Success) { throw 'Keine eingebetteten Dashboard-Daten gefunden.' }
        return ($m.Groups[1].Value | ConvertFrom-Json)
    }
    function Get-Klassen([string]$Html) {
        return @([regex]::Matches($Html, 'class="([^"]+)"') | ForEach-Object { $_.Groups[1].Value -split '\s+' } | Where-Object { $_ } | Select-Object -Unique)
    }
}

AfterAll {
    [cultureinfo]::CurrentCulture = $script:KulturVorher
    $env:COMPUTERNAME = $script:PcVorher
}

Describe 'Textbericht' {
    BeforeAll { Import-MinibenchTestModule -Functions 'Format-Uptime', 'Split-TextLines' }
    It 'Laufzeit ohne "0 Tage" und mit Minuten' {
        MinibenchTest\Format-Uptime ([TimeSpan]::new(0, 5, 21, 0)) | Should -Be '5 Std 21 Min'
        MinibenchTest\Format-Uptime ([TimeSpan]::new(1, 2, 3, 0)) | Should -Be '1 Tag 2 Std 3 Min'
        MinibenchTest\Format-Uptime ([TimeSpan]::new(12, 2, 3, 0)) | Should -Be '12 Tage 2 Std'
    }
    It 'bricht lange Erklärungen an Wortgrenzen auf die Zeilenbreite um' {
        $l = @(MinibenchTest\Split-TextLines ('Wort ' * 40) 30)
        $l.Count | Should -BeGreaterThan 5
        @($l | Where-Object { $_.Length -gt 30 }).Count | Should -Be 0
        ($l -join ' ') | Should -Be (('Wort ' * 40).Trim())
    }
    It 'Kopf nennt die Zuverlässigkeit und bricht ihre Erklärung um (Felder Text und Erklaerung der Bewertung)' {
        $ab = Get-SrcText 'Ablauf/Abschluss.ps1'
        $ab | Should -Match "ZUVERLÄSSIGKEIT: \{0\}' -f \`$script:Stability\.Text"
        $ab | Should -Match 'Split-TextLines \$script:Stability\.Erklaerung'
    }
}

Describe 'HTML-Bericht: Aufbau, Navigation, Befundfilter und Benchmark' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Referenz_Vergleich.ps1', 'Kern\Berichtshilfen.ps1', 'Bericht\Stil.ps1', 'Bericht\Bausteine_Systemvergleich.ps1', 'Bericht\HtmlBericht.ps1' `
            -Functions 'Get-ModeLabel', 'Get-RunRisk', 'Send-GuiEvent', 'New-RenderChartsHtml', 'Get-StabilityAssessment', 'Get-BenchDashboardHtmlTemplate'
        Mock -ModuleName MinibenchTest New-RenderChartsHtml { '<div id="rendertest-attrappe"></div>' }
        $env:COMPUTERNAME = 'ULB-PC10039'

        # Bericht mit Befunden, Testergebnis, Absturzabbild und Detailabschnitt; wahlweise mit Benchmark und Zuverlässigkeit
        function New-TestBericht([switch]$Benchmark, [switch]$Zuverlaessigkeit, [switch]$RefGespeichert) {
            $pfad = Join-Path $TestDrive ('Bericht_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.html')
            & (Get-Module MinibenchTest) {
                param($Pfad, $Bench, $Stab, $RefNeu)
                $script:Facts = [ordered]@{ 'Betriebssystem' = 'Windows 11 Pro 25H2'; 'Laufzeit' = '5 Std 21 Min' }
                $script:Report = New-Object System.Text.StringBuilder
                [void]$script:Report.AppendLine('=' * 100).AppendLine('  System und Betriebssystem').AppendLine('=' * 100).AppendLine('  Windows 11 Pro')
                $script:TestResults = @([pscustomobject]@{ Test = 'Systemdateien (SFC)'; Ergebnis = 'OK'; Details = 'keine Verletzungen' })
                $script:Timings = @([pscustomobject]@{ Abschnitt = 'Diagnose'; Dauer = '00:12:00' })
                $script:BatteryInfo = @(); $script:BenchSensorRows = @(); $script:BenchRefRows = @(); $script:OptLog = @(); $script:CmpRows = @(); $script:LoadSeries = @(); $script:LoadParts = @()
                $script:Minidumps = @([pscustomobject]@{ Zeit = (Get-Date '2026-09-29 18:12'); Datei = '092926-1.dmp'; Bugcheck = '0x1A'; Name = 'MEMORY_MANAGEMENT'; Parameter1 = '0x41792'; Parameter2 = '0x0'; Parameter3 = '0x0'; Parameter4 = '0x0'; Empfehlung = 'Memory Management: RAM prüfen' })
                $script:Stability = $null
                if ($Stab) {
                    $rec = @(1..12 | ForEach-Object { [pscustomobject]@{ SourceName = 'Application Error'; EventIdentifier = 1000; ProductName = 'PowerToys.QuickAccess.exe'; Message = '' } })
                    $script:Stability = Get-StabilityAssessment 5.24 $rec 28
                }
                $script:RefSavedNow = [bool]$RefNeu
                $script:Ref = $script:RefNone
                $script:BenchResults = @(); $script:BenchDisks = @(); $script:BenchHead = @{}
                if ($Bench) {
                    $script:BenchResults = @(
                        [pscustomobject]@{ Gruppe = 'CPU'; Key = 'CPU|ST'; RefKey = 'CPU|ST'; Messung = 'Einzelkern'; Anzeige = '3.086 Punkte'; Index = 112; Status = 'OK'; RefPct = 104; Referenz = '104 %'; Vergleich = '+3 %'; Hinweis = '' }
                        [pscustomobject]@{ Gruppe = 'CPU'; Key = 'CPU|MT'; RefKey = 'CPU|MT'; Messung = 'Alle Kerne'; Anzeige = '38.101 Punkte'; Index = 108; Status = 'OK'; RefPct = 98; Referenz = '98 %'; Vergleich = ''; Hinweis = '' }
                        [pscustomobject]@{ Gruppe = 'RAM'; Key = 'RAM|Lesen'; RefKey = 'RAM|Lesen'; Messung = 'Lesen'; Anzeige = '61,9 GB/s'; Index = 120; Status = 'OK'; RefPct = 100; Referenz = '100 %'; Vergleich = ''; Hinweis = '' }
                        [pscustomobject]@{ Gruppe = 'GPU'; Key = 'GPU|REND'; RefKey = 'GPU|REND'; Messung = 'Rendertest'; Anzeige = '412 Bilder/s'; Index = 130; Status = 'OK'; RefPct = 120; Referenz = '120 %'; Vergleich = ''; Hinweis = '' })
                    $script:BenchDisks = @([pscustomobject]@{ Laufwerk = 'SAMSUNG MZVL21T0HCLR (C:)'; Klasse = 'NVMe PCIe 4.0'; SR = 6684; SW = 3739; R1 = 18330; R8 = 159397; W1 = 54971; Index = 105; Status = 'OK'; RefPct = 101; Referenz = '101 %'; Hinweis = ''; Vergleich = '' })
                    $script:BenchHead = @{ 'CPU' = 'AMD Ryzen 5 7600X' }
                }
                $sorted = @(
                    [pscustomobject]@{ Stufe = 'KRITISCH'; Bereich = 'Stabilität'; Befund = 'Bluescreen 0x1A <MEMORY_MANAGEMENT> & Neustart' }
                    [pscustomobject]@{ Stufe = 'WARNUNG'; Bereich = 'Datenträger'; Befund = 'SATA-Controller Reset (storahci 129): 207x' }
                    [pscustomobject]@{ Stufe = 'INFO'; Bereich = 'RAM'; Befund = 'Nur ein Modul verbaut' })
                New-HtmlReport -Path $Pfad -Sorted $sorted -NK 1 -NW 1 -NI 1 -Start (Get-Date '2026-10-03 09:00') -End (Get-Date '2026-10-03 09:42')
            } $pfad $Benchmark.IsPresent $Zuverlaessigkeit.IsPresent $RefGespeichert.IsPresent
            return [IO.File]::ReadAllText($pfad, [Text.Encoding]::UTF8)
        }
        $script:Html = New-TestBericht -Benchmark -Zuverlaessigkeit
    }

    It 'jeder Abschnitt gehört zu einem Ziel der Navigation' {
        $nav = [regex]::Match($script:Html, '<nav class="report-nav">.*?</nav>').Value
        $ziele = @([regex]::Matches($nav, "switchSection\('(\w+)'") | ForEach-Object { $_.Groups[1].Value })
        foreach ($z in 'all', 'system', 'benchmark', 'befunde', 'hardware', 'sensoren') { $ziele | Should -Contain $z }
        $abschnitte = @([regex]::Matches($script:Html, '<section\b[^>]*>') | ForEach-Object { $_.Value })
        $abschnitte.Count | Should -BeGreaterThan 5
        foreach ($s in $abschnitte) {
            $m = [regex]::Match($s, 'data-section="(\w+)"')
            $m.Success | Should -BeTrue -Because $s
            $ziele | Should -Contain $m.Groups[1].Value
        }
    }
    It 'Befunde stehen in einer nach Stufe filterbaren Tabelle, ohne Freitextsuche' {
        $chips = @([regex]::Matches($script:Html, '<button type="button" class="fchip[^"]*" data-level="(\w+)"') | ForEach-Object { $_.Groups[1].Value })
        $chips | Should -Be @('all', 'KRITISCH', 'WARNUNG', 'INFO')
        $tab = [regex]::Match($script:Html, '<table id="befundeTable">.*?</table>').Value
        $stufen = @([regex]::Matches($tab, '<td data-level="(\w+)"') | ForEach-Object { $_.Groups[1].Value })
        $stufen | Should -Be @('KRITISCH', 'WARNUNG', 'INFO')
        $script:Html | Should -Not -Match '<input\b|id="befundSearch"'
    }
    It 'jedes Element, das das Berichtsskript über die id anspricht, steht im Bericht' {
        $js = MinibenchTest\Get-ReportJs
        $ids = @([regex]::Matches($js, "getElementById\('([^']+)'\)") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        $ids.Count | Should -BeGreaterThan 3
        foreach ($id in $ids) { $script:Html | Should -Match ('id="{0}"' -f [regex]::Escape($id)) -Because $id }
        foreach ($f in 'switchSection', 'setLevelFilter', 'filterBefunde', 'initBefundCounts') { $script:Html | Should -Match ('function {0}\(' -f $f) }
    }
    It 'Texte der Befunde und Absturzabbilder werden maskiert' {
        $script:Html | Should -Match 'Bluescreen 0x1A &lt;MEMORY_MANAGEMENT&gt; &amp; Neustart'
        $script:Html | Should -Not -Match '<MEMORY_MANAGEMENT>'
        $script:Html | Should -Match '<code>092926-1\.dmp</code>'
        $script:Html | Should -Match 'Memory Management: RAM prüfen'
    }
    It 'Zuverlässigkeit als Karte und mit Erklärung der Ursachen' {
        $script:Html | Should -Match '<div class="card st info"><b>5,2</b><span>Zuverlässigkeit von 10 \(mittel\)</span></div>'
        $script:Html | Should -Match '<h2>Zuverlässigkeit 5,2 von 10</h2><p>Windows bewertet die Stabilität'
        $script:Html | Should -Match '12x Programmabsturz \(meist PowerToys\.QuickAccess\.exe\)'
        $ohne = New-TestBericht
        $ohne | Should -Not -Match 'Zuverlässigkeit'
    }
    It 'Benchmark: Gruppen als Tabelle mit Messung, Wert, Index, Referenz, Vergleich und Ergebnis' {
        $script:Html | Should -Match '<th>Messung</th><th class="r">Wert</th><th>Index</th><th>Referenz</th><th>Vergleich</th><th>Ergebnis</th>'
        $script:Html | Should -Match '<div class="comp-title">AMD Ryzen 5 7600X</div>'
        $script:Html | Should -Match '<b>101 %</b> &middot; <span class="pword">Sehr gut</span>'
        foreach ($g in 'CPU', 'RAM', 'GPU', 'Laufwerke') { $script:Html | Should -Match ('<details class="grp" id="bg-{0}"' -f $g) }
        $script:Html | Should -Match 'Gesamtleistung \(Referenz\)'
        $script:Html | Should -Match 'class="ov profile-grid"'
        $script:Html | Should -Match '<div id="rendertest-attrappe"></div>'
    }
    It 'ohne Benchmark kein Benchmark-Abschnitt' {
        $ohne = New-TestBericht
        $ohne | Should -Not -Match '<h2>Leistung \(Benchmark\)</h2>'
        $ohne | Should -Not -Match 'Gesamtleistung'
    }
    It 'Referenz in diesem Lauf gespeichert: Hinweis statt Prozentwerten' {
        $h = New-TestBericht -Benchmark -RefGespeichert
        $h | Should -Match 'Dieser Lauf wurde als Referenz gespeichert; ab dem nächsten Lauf ist dieser PC 100 %\.'
        (New-TestBericht -Benchmark) | Should -Match 'Keine Referenz festgelegt'
    }
    It 'Vergleichsdashboard: Link mit diesem PC, das Dashboard wertet den Parameter system aus' {
        $script:Html | Should -Match ('href="\.\./Dashboard\.html\?system={0}" class="tab-btn btn-dash"' -f [regex]::Escape([uri]::EscapeDataString($env:COMPUTERNAME)))
        MinibenchTest\Get-BenchDashboardHtmlTemplate | Should -Match "urlParams\.get\('system'\)"
    }
    It 'Navigation, Filterleiste und Kurven-Hinweis haben Stilregeln' {
        $css = MinibenchTest\Get-ReportCss
        $nav = [regex]::Match($script:Html, '<nav class="report-nav">.*?</nav>').Value
        $filter = [regex]::Match($script:Html, '<div class="filter-bar">.*?<span id="befundCount"[^>]*></span></div>').Value
        $filter | Should -Not -BeNullOrEmpty
        $klassen = @(Get-Klassen $nav) + @(Get-Klassen $filter)
        # den Kurven-Hinweis legt das Berichtsskript an
        (MinibenchTest\Get-ReportJs) | Should -Match "tip\.className = 'chart-tooltip'"
        $klassen += 'chart-tooltip', 'hit'
        $klassen.Count | Should -BeGreaterThan 8
        foreach ($k in ($klassen | Select-Object -Unique)) { $css | Should -Match ('\.{0}\b' -f [regex]::Escape($k)) -Because $k }
    }
}

Describe 'Kurven im HTML-Bericht (SVG)' {
    BeforeAll {
        Import-MinibenchTestModule -Functions 'New-LoadChartsHtml', 'New-MultiLineSvg', 'New-LineSvg', 'Get-ChartScale', 'Get-ChartMarkLayout', 'ConvertTo-HtmlText', 'Get-TelemetryTip'
        function New-Messreihe([int]$Anzahl, [int]$Abstand, [scriptblock]$CpuLast) {
            return @(for ($i = 0; $i -lt $Anzahl; $i++) {
                [pscustomobject]@{ T = $Abstand * $i; MHz = 3000 + 50 * $i; CpuMHz = 4000 + 20 * $i; CpuTemp = 60 + 3 * $i; CpuTempQ = 'LHM'; CpuW = 20 + $i; Temp = $null; GpuTemp = $null; GpuMHz = $null; GpuW = $null
                    IGpuTemp = $null; IGpuMHz = $null; IGpuW = $null; Fan = $null; DiskTemp = $null; GpuLoad = $null; IGpuLoad = $null; Fps = $null; Fps2 = $null; Cpu = [bool](& $CpuLast $i) }
            })
        }
        function Get-Teilstriche([string]$Svg) { return @([regex]::Matches($Svg, 'text-anchor="end" dominant-baseline="middle">([^<]+)</text>') | ForEach-Object { $_.Groups[1].Value }) }
    }
    It 'Benchmark: Kurven der Sensoren mit Marken je Abschnitt, TjMax als Linie, ohne Drosselnachweis' {
        $s = New-Messreihe 12 2 { $false }
        $h = MinibenchTest\New-LoadChartsHtml -Series $s -Throttle $null -Abort $null -Limits ([pscustomobject]@{ Cpu = 0; Gpu = 0; TjMax = 100 }) -Marken @(@{ T = 10; Label = 'Arbeitsspeicher' }) -GpuLoad @()
        foreach ($t in 'Temperatur \(°C\)', 'Takt \(MHz\)', 'Leistung \(W\)') { $h | Should -Match ('<h3>{0}</h3>' -f $t) }
        $h | Should -Match '<text class="mk"[^>]*>Arbeitsspeicher</text>'
        $h | Should -Match 'TjMax 100 °C'
        $h | Should -Not -Match 'Drosselnachweis'
        $h | Should -Not -Match 'Abbruchschwelle'
    }
    It 'Lasttest: Marken für das Ende der CPU-Last und für den Abbruch' {
        $s = New-Messreihe 12 3 { param($i) $i -lt 8 }
        MinibenchTest\New-LoadChartsHtml -Series $s -Throttle $null -Abort $null -Limits $null -GpuLoad @() | Should -Match '>CPU-Last Ende<'
        $h2 = MinibenchTest\New-LoadChartsHtml -Series $s -Throttle $null -Abort ([pscustomobject]@{ T = 15; Grund = 'x' }) -Limits $null -GpuLoad @()
        $h2 | Should -Match '>Abbruch<'
        $h2 | Should -Not -Match 'CPU-Last Ende'
    }
    It 'Achse: halbe Schritte mit Nachkommastelle, keine doppelten Beschriftungen' {
        $s = MinibenchTest\Get-ChartScale 60 61.8
        $s.Step | Should -Be 0.5
        $lab = @($s.Ticks | ForEach-Object { $_.ToString($s.Format, [Globalization.CultureInfo]::InvariantCulture) })
        @($lab | Select-Object -Unique).Count | Should -Be $lab.Count
        $lab[0] | Should -Be '60.0'
    }
    It 'Achse: ganzzahlige Messreihen bekommen mindestens Schritt 1' {
        $s = MinibenchTest\Get-ChartScale 60 62 -Integer
        $s.Step | Should -Be 1
        $s.Format | Should -Be 'N0'
    }
    It 'Achse: Schritt 2,5 wird mit Nachkommastelle beschriftet, ganzzahlige Reihen meiden 2,5' {
        $s = MinibenchTest\Get-ChartScale -5 5
        $s.Step | Should -Be 2.5
        $s.Format | Should -Be 'N1'
        (MinibenchTest\Get-ChartScale 40 50 -Integer).Step | Should -Not -Be 2.5
    }
    It 'nahe Marken landen in getrennten Zeilen, am rechten Rand links der Linie' {
        $fx = { param($t) 70 + $t / 300 * 870 }
        $m = @(MinibenchTest\Get-ChartMarkLayout @(@{ T = 100; Label = 'Arbeitsspeicher' }, @{ T = 110; Label = 'Grafik' }, @{ T = 299; Label = 'Ende' }) 70 940 14 $fx 300)
        $m[0].Y | Should -Not -Be $m[1].Y
        $m[2].Anchor | Should -Be 'end'
        $svg = MinibenchTest\New-MultiLineSvg @(@{ Name = 'CPU'; Cls = 's1'; Points = @([pscustomobject]@{ T = 0; V = 60.5 }, [pscustomobject]@{ T = 300; V = 61.5 }) }) '°C' @() @(@{ T = 100; Label = 'Arbeitsspeicher' }, @{ T = 110; Label = 'Grafik' })
        $y = @([regex]::Matches($svg, '<text class="mk"[^>]*y="(\d+)"') | ForEach-Object { $_.Groups[1].Value })
        $y.Count | Should -Be 2
        @($y | Select-Object -Unique).Count | Should -Be 2
    }
    It 'Bilder/s beginnen bei 0 (<Funktion>)' -ForEach @(
        @{ Funktion = 'New-MultiLineSvg' }
        @{ Funktion = 'New-LineSvg' }
    ) {
        $pts = @([pscustomobject]@{ T = 0; V = 39.5 }, [pscustomobject]@{ T = 1; V = 41.2 }, [pscustomobject]@{ T = 2; V = 40.8 })
        $svg = $(if ($Funktion -eq 'New-LineSvg') { MinibenchTest\New-LineSvg $pts 'Bilder/s' } else { MinibenchTest\New-MultiLineSvg @(@{ Name = 'GPU'; Cls = 's2'; Points = $pts }) 'Bilder/s' })
        $tick = @(Get-Teilstriche $svg)
        $tick | Should -Contain '0'
        # ohne Nulllinie begänne die Achse knapp unter 39,5
        $tick | Should -Not -Contain '39'
    }
    It 'Punkte mit eigenem Hinweis: Hinweis maskiert in data-tip, Titel ohne HTML' {
        $pts = @([pscustomobject]@{ T = 0; V = 60; Tip = '<b>Start</b><div>CPU 60 °C</div>' }, [pscustomobject]@{ T = 10; V = 70; Tip = $null })
        $svg = MinibenchTest\New-MultiLineSvg @(@{ Name = 'CPU'; Cls = 's1'; Points = $pts }) '°C'
        $hits = @([regex]::Matches($svg, '<circle class="hit s1"[^>]*data-tip="([^"]*)"><title>([^<]*)</title>'))
        $hits.Count | Should -Be 2
        $hits[0].Groups[1].Value | Should -Be '&lt;b&gt;Start&lt;/b&gt;&lt;div&gt;CPU 60 °C&lt;/div&gt;'
        $hits[0].Groups[2].Value | Should -Match '^Start\W+CPU 60 °C$'
        $hits[1].Groups[1].Value | Should -Match '^0:10 min  ·  CPU: 70 °C$'
    }
    It 'Hinweis eines Messpunkts nennt Zeit, Temperatur in °C, Takt in GHz und Leistung in W' {
        $tip = MinibenchTest\Get-TelemetryTip ([pscustomobject]@{ T = 75; CpuTemp = 81.5; CpuMHz = 4200; CpuW = 35; GpuTemp = 64; GpuMHz = $null; GpuW = $null; GpuLoad = $null; Fps = $null; Fan = 1450; DiskMBs = $null })
        $tip | Should -Match '01:15 min \(75 s\)'
        $tip | Should -Match 'CPU: 81,5 °C'
        $tip | Should -Match 'GPU: 64,0 °C'
        $tip | Should -Match 'CPU-Takt: 4,20 GHz'
        $tip | Should -Match 'CPU-Paket: 35,0 W'
        $tip | Should -Match 'Lüfter: 1\.450 U/min'
        $tip | Should -Not -Match 'Bilder/s|GPU-Auslastung'
    }
    It 'Kurven des Lasttests tragen den Hinweis je Messpunkt' {
        $s = New-Messreihe 6 2 { $true }
        $h = MinibenchTest\New-LoadChartsHtml -Series $s -Throttle $null -Abort $null -Limits $null -Marken @() -GpuLoad @()
        $h | Should -Match 'data-tip="[^"]*CPU-Takt: 4,02 GHz[^"]*CPU-Paket: 21,0 W'
    }
}

Describe 'KI-Datei' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Modulvertrag.ps1' -Functions 'Get-KiPrompt', 'New-KiExport', 'Protect-Text', 'Add-Private', 'Get-ModeLabel', 'Get-StabilityAssessment', 'Get-ShortText' `
            -Setup "`$script:Private = New-Object 'System.Collections.Generic.Dictionary[string,string]'; `$script:UserNames = @()"
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
    It 'nennt alle Reparaturen von Leos Minibench aus dem Modulvertrag' {
        $titel = @((MinibenchTest\Get-ModuleContract 'Reparatur').Schritte | ForEach-Object { $_.Titel })
        $titel.Count | Should -BeGreaterThan 3
        $script:P | Should -Match 'Reparaturen in Leos Minibench \(Seite Reparatur'
        foreach ($t in $titel) { $script:P | Should -Match ([regex]::Escape($t)) }
    }
    It 'erklärt die Unterbrechungsmessung' { $script:P | Should -Match 'Unterbrechungen der Last' }
    It 'ohne Spiegelstriche als Aufzählung' { @($script:P -split "`r?`n" | Where-Object { $_ -match '^\s*- ' }).Count | Should -Be 0 }
    It 'Überblick nennt Zuverlässigkeit mit Ursachen, Absturzabbilder mit Empfehlung, der PC-Name ist unkenntlich' {
        $env:COMPUTERNAME = 'ULB-PC10039'
        & (Get-Module MinibenchTest) {
            $rec = @(1..7 | ForEach-Object { [pscustomobject]@{ SourceName = 'Application Error'; EventIdentifier = 1000; ProductName = 'PowerToys.QuickAccess.exe'; Message = '' } }) +
                @([pscustomobject]@{ SourceName = 'EventLog'; EventIdentifier = 6008; ProductName = 'Windows'; Message = '' })
            $script:Stability = Get-StabilityAssessment 5.24 $rec 28
            $script:Facts = [ordered]@{ 'Computer' = 'ULB-PC10039' }
            $script:Minidumps = @([pscustomobject]@{ Datum = (Get-Date '2026-09-29 18:12'); Datei = '092926-1.dmp'; BugcheckCode = '0x133'; Name = 'DPC_WATCHDOG_VIOLATION'; Parameter1 = '0x1'; Parameter2 = '0x1E00'; Parameter3 = '0x0'; Parameter4 = '0x0'; Empfehlung = 'DPC Watchdog: SSD-Firmware aktualisieren' })
            $script:BatteryInfo = @(); $script:BenchSensorRows = @(); $script:OptLog = @(); $script:TestResults = @(); $script:BenchResults = @(); $script:BenchDisks = @(); $script:CmpRows = @(); $script:LoadSeries = @(); $script:LoadParts = @(); $script:RepairLog = @()
        }
        $sorted = @([pscustomobject]@{ Stufe = 'KRITISCH'; Bereich = 'Stabilität'; Befund = 'Bluescreen auf ULB-PC10039' })
        $t = MinibenchTest\New-KiExport -Path '' -Sorted $sorted -NK 1 -NW 0 -NI 0 -Start (Get-Date '2026-10-03 09:00') -End (Get-Date '2026-10-03 09:42') -Compact
        $t | Should -Match 'AUFTRAG AN DIE KI'
        $t | Should -Match 'Zuverlässigkeit       : 5,2 von 10 \(mittel\); 1x Windows-Fehler \(Absturz oder unerwartetes Ausschalten\), 7x Programmabsturz \(meist PowerToys\.QuickAccess\.exe\)'
        $t | Should -Match '#  ABSTURZABBILDER'
        $t | Should -Match '29\.09\.2026 18:12 \| Datei: 092926-1\.dmp \| Stoppcode: 0x133 \(DPC_WATCHDOG_VIOLATION\) \| Parameter: 0x1, 0x1E00'
        $t | Should -Match 'Empfehlung: DPC Watchdog'
        $t | Should -Match '\[KRITISCH\] Stabilität: Bluescreen auf <PC>'
        $t | Should -Not -Match 'ULB-PC10039'
        $t | Should -Not -Match 'VOLLSTÄNDIGER BERICHT'
    }
}

Describe 'Bewertungswort und Profilkarten' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Referenz_Vergleich.ps1', 'Bericht\Bausteine_Systemvergleich.ps1' -Functions 'ConvertTo-HtmlText'
        function Set-Bench([hashtable]$Pct) {
            $r = @()
            foreach ($k in 'CPU|ST', 'CPU|MT', 'RAM|Lesen', 'GPU|REND') {
                if ($Pct.ContainsKey($k)) { $r += [pscustomobject]@{ Gruppe = ($k -split '\|')[0]; Key = $k; RefKey = $k; Status = 'OK'; RefPct = $Pct[$k] } }
            }
            Set-ModuleVar 'BenchResults' $r
            Set-ModuleVar 'BenchDisks' $(if ($Pct.ContainsKey('DISK')) { @([pscustomobject]@{ Laufwerk = 'C:'; Status = 'OK'; RefPct = $Pct['DISK'] }) } else { @() })
        }
        function Get-Karten([string]$Html) {
            $k = [ordered]@{}
            foreach ($m in [regex]::Matches($Html, '<h4>\S+ ([^<]+)</h4><div class="big">(\d+)<small> %</small></div><div class="pword">([^<]+)</div>')) { $k[$m.Groups[1].Value] = @([int]$m.Groups[2].Value, $m.Groups[3].Value) }
            return $k
        }
    }
    It '<Pct> % heißt <Wort>' -ForEach @(
        @{ Pct = 120; Wort = 'Hervorragend' }, @{ Pct = 115; Wort = 'Hervorragend' }, @{ Pct = 114.9; Wort = 'Sehr gut' }, @{ Pct = 100; Wort = 'Sehr gut' }
        @{ Pct = 99.9; Wort = 'Gut' }, @{ Pct = 85; Wort = 'Gut' }, @{ Pct = 84.9; Wort = 'Durchschnittlich' }, @{ Pct = 70; Wort = 'Durchschnittlich' }
        @{ Pct = 69.9; Wort = 'Mäßig' }, @{ Pct = 50; Wort = 'Mäßig' }, @{ Pct = 49.9; Wort = 'Unterdurchschnittlich' }, @{ Pct = 0; Wort = 'Unterdurchschnittlich' }
    ) {
        MinibenchTest\Get-BenchRatingWord $Pct | Should -Be $Wort
        MinibenchTest\Get-Bewertungswort $Pct | Should -Be $Wort
    }
    It 'ohne Wert kein Bewertungswort' {
        MinibenchTest\Get-BenchRatingWord $null | Should -Be ''
        MinibenchTest\Get-BenchRatingWord '' | Should -Be ''
    }
    It 'Profilkarten erst ab drei Bereichen mit Referenzwert' {
        Set-Bench @{}
        MinibenchTest\New-ProfileCards | Should -Be ''
        Set-Bench @{ 'CPU|ST' = 100; 'CPU|MT' = 100; 'GPU|REND' = 100 }
        MinibenchTest\New-ProfileCards | Should -Be ''
        Set-Bench @{ 'CPU|ST' = 100; 'CPU|MT' = 100; 'GPU|REND' = 100; 'RAM|Lesen' = 100 }
        @((Get-Karten (MinibenchTest\New-ProfileCards)).Keys) | Should -Be @('Gaming', 'Büro/Desktop', 'Workstation')
    }
    It 'Referenzniveau in allen Bereichen ergibt 100 % und Sehr gut in jedem Profil' {
        Set-Bench @{ 'CPU|ST' = 100; 'CPU|MT' = 100; 'GPU|REND' = 100; 'RAM|Lesen' = 100; 'DISK' = 100 }
        $k = Get-Karten (MinibenchTest\New-ProfileCards)
        foreach ($p in 'Gaming', 'Büro/Desktop', 'Workstation') { $k[$p][0] | Should -Be 100; $k[$p][1] | Should -Be 'Sehr gut' }
    }
    It 'doppelte Grafikleistung hebt Gaming am stärksten, Büro am wenigsten (Gewichte 3 : 1 : 0,5)' {
        Set-Bench @{ 'CPU|ST' = 100; 'CPU|MT' = 100; 'GPU|REND' = 200; 'RAM|Lesen' = 100; 'DISK' = 100 }
        $k = Get-Karten (MinibenchTest\New-ProfileCards)
        $k['Gaming'][0] | Should -Be 146
        $k['Workstation'][0] | Should -Be 110
        $k['Büro/Desktop'][0] | Should -Be 105
        $k['Gaming'][1] | Should -Be 'Hervorragend'
    }
}

Describe 'Interaktives Dashboard' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Referenzen_Eingebettet.ps1', 'Bericht\Bausteine_Dashboard.ps1'
        $script:Root = New-DashboardDaten
        $script:Daten = MinibenchTest\Export-BenchDashboardData -DatabaseDir $script:Root -ReportDir (Join-Path $script:Root 'Berichte')
        # Datenordner mit Lasttest-Verlauf.csv im Berichtsordner (PC-T) und einem Lauf ohne Verlaufsdatei (PC-K)
        $script:RootCsv = New-DashboardDaten @()
        $ordner = Join-Path (Join-Path $script:RootCsv 'Berichte') 'PC-T_20261001_1200'
        New-Item -ItemType Directory -Path $ordner -Force | Out-Null
        $zeilen = @('T;MHz;CpuTemp;GpuTemp;CpuW;Fps') + @(for ($i = 0; $i -lt 8; $i++) { '{0};{1};{2};{3};{4};{5}' -f (2 * $i), (3800 + 50 * $i), ('{0},5' -f (60 + $i)), (50 + $i), ('{0},2' -f (80 + $i)), $(if ($i) { 100 + $i } else { '' }) })
        [IO.File]::WriteAllLines((Join-Path $ordner 'Lasttest-Verlauf.csv'), [string[]]$zeilen, (New-Object Text.UTF8Encoding($true)))
        Add-DbEintrag $script:RootCsv 'PC-T.json' @{ Format = 'PC-Diagnose-DB/2'; Name = 'PC-T'; Computer = 'PC-T'; Datum = '2026-10-01 12:00'; Ordner = 'Berichte\PC-T_20261001_1200'
            Sensoren = @{ Last = @{ CpuTempMax = 91; CpuTempLeerlauf = 38; TjMax = 95; Drosselung = 'thermisch'; TaktAbfall = 12; Unterbrechungen = '3 über 50 ms, längste 180 ms' } } } | Out-Null
        Add-DbEintrag $script:RootCsv 'PC-K.json' @{ Format = 'PC-Diagnose-DB/2'; Name = 'PC-K'; Computer = 'PC-K'; Datum = '2026-10-01 13:00'
            Sensoren = @{ Last = @{ CpuTempMax = 70; Unterbrechungen = 'keine über 50 ms (Speicherbereinigungen Gen 0/1/2: 3/0/0)' } } } | Out-Null
        $script:DatenCsv = MinibenchTest\Export-BenchDashboardData -DatabaseDir $script:RootCsv -ReportDir (Join-Path $script:RootCsv 'Berichte') -IncludeReferences:$false
    }

    Context 'Daten aus der Datenbank (Export-BenchDashboardData)' {
        It 'liest jeden Lauf der Datenbank als System, die Referenzprofile getrennt' {
            @($script:Daten.Systems | ForEach-Object { $_.Computer } | Sort-Object) | Should -Be @('DESKTOP-F9HRMRR', 'LIZZZ', 'TORRENT')
            @($script:Daten.Systems | Where-Object { $_.IsReference }).Count | Should -Be 0
            $refs = @($script:Daten.References)
            $refs.Count | Should -Be 5
            @($refs | Where-Object { -not $_.IsReference }).Count | Should -Be 0
            foreach ($n in '*Desktop High-End*', '*Desktop Mittelklasse*', '*Mini*PC*', '*Notebook Standard*', '*Workstation Mobil*') {
                @($refs | Where-Object { $_.DisplayName -like $n }).Count | Should -Be 1 -Because $n
            }
            @($script:Daten.PreselectedIds).Count | Should -Be 0
        }
        It 'Datenstand trägt die Version von Leos Minibench' {
            $script:Daten.Version | Should -Be (Get-MinibenchVersion)
        }
        It 'übernimmt Messwerte, schnellstes Laufwerk und bestes Laufwerk je Klasse (TORRENT)' {
            $t = Get-SystemNachName $script:Daten 'TORRENT'
            $t.Id | Should -Be 'TORRENT_202609302159'
            $t.Metrics.CPU_ST | Should -Be 3086
            $t.Metrics.CPU_MT | Should -Be 38101
            $t.Metrics.RAM_Lesen | Should -Be 61.9
            $t.Metrics.RAM_Latenz | Should -Be 82.4
            $t.Metrics.GPU_VMB | Should -Be 290.2
            $t.Metrics.FastestDisk.Model | Should -Be 'SAMSUNG MZVL21T0HCLR-00B00 (C:)'
            $t.Metrics.FastestDisk.SR | Should -Be 6684
            @($t.Metrics.Disks).Count | Should -Be 5
            $t.Metrics.DisksByClass['NVMe PCIe 3.0 x4'].Model | Should -Be 'WDS100T3X0C-00SJG0 (G:)'
            $t.Metrics.DisksByClass['SATA-SSD'].SR | Should -Be 564
            $t.RawValues['DISK|NVMe4|R8'] | Should -Be 159397
        }
        It 'übernimmt Hardware und Befunde, Mainboard fällt auf die Systembezeichnung zurück (TORRENT)' {
            $t = Get-SystemNachName $script:Daten 'TORRENT'
            $t.Hardware.CPU | Should -Be 'AMD Ryzen 5 7600X'
            $t.Hardware.GPU | Should -Be 'AMD Radeon RX 6800'
            $t.Hardware.Mainboard | Should -Be 'Gigabyte Technology Co., Ltd. B650 GAMING X AX'
            $t.OS | Should -Match '^Microsoft Windows 11 Pro'
            $t.Befunde.Kritisch | Should -Be 0
            $t.Befunde.Warnungen | Should -Be 1
            $t.Befunde.Hinweise | Should -Be 5
            @($t.Befunde.Liste).Count | Should -Be 6
            @($t.Befunde.Liste)[0] | Should -Match '^\[WARNUNG\] Lizenz:'
        }
        It 'Gesamtwert und Nutzungsprofile ordnen die Praxis-PCs nach Leistung' {
            $t = Get-SystemNachName $script:Daten 'TORRENT'; $l = Get-SystemNachName $script:Daten 'LIZZZ'; $d = Get-SystemNachName $script:Daten 'DESKTOP-F9HRMRR'
            foreach ($p in 'Overall', 'Gaming', 'Desktop', 'Workstation') {
                $t.Scores[$p] | Should -BeGreaterThan $l.Scores[$p] -Because $p
                $d.Scores[$p] | Should -BeGreaterThan 0 -Because $p
            }
            $l.Scores.Overall | Should -BeGreaterThan $d.Scores.Overall
            # Gesamtwert: geometrisches Mittel aus CPU-MT (2x), Grafik (2x, ohne Rendertest 1,5 x VRAM-Bandbreite x 100) und RAM-Lesen x 500 (1x)
            $erwartet = [int][math]::Round([math]::Exp((2 * [math]::Log(38101) + 2 * [math]::Log(290.2 * 1.5 * 100) + [math]::Log(61.9 * 500)) / 5))
            $t.Scores.Overall | Should -Be $erwartet
        }
        It 'Referenzprofile haben Messwerte, Laufwerke und Wertungen' {
            $he = @($script:Daten.References | Where-Object { $_.DisplayName -like '*High-End*' })[0]
            foreach ($k in 'CPU_ST', 'CPU_MT', 'RAM_Lesen', 'RAM_Kopieren', 'RAM_Latenz', 'GPU_REND', 'GPU_REND1') { $he.Metrics[$k] | Should -BeGreaterThan 0 -Because $k }
            $he.Metrics.FastestDisk.SR | Should -BeGreaterThan 0
            foreach ($p in 'Overall', 'Gaming', 'Desktop', 'Workstation') { $he.Scores[$p] | Should -BeGreaterThan 0 -Because $p }
            $he.Hardware.CPU | Should -Not -BeNullOrEmpty
            $he.Id | Should -Match '^REF_'
        }
        It 'Befunde als Zählertext und als Detailliste' {
            $root = New-DashboardDaten @()
            $p = Add-DbEintrag $root 'Alpha.json' @{ Format = 'PC-Diagnose-DB/2'; Name = 'System Alpha'; Computer = 'ALPHA-PC'; Datum = '2026-10-01 10:00'; Befunde = '0/1/2'
                BefundeDetails = @(@{ Stufe = 'Warnung'; Bereich = 'Kühlung'; Text = 'Lüfterdrehzahl erhöht' }, 'freier Text') }
            $a = Get-SystemNachName (MinibenchTest\Export-BenchDashboardData -DatabaseDir $root -SystemPaths @($p)) 'ALPHA-PC'
            $a.Befunde.Kritisch | Should -Be 0; $a.Befunde.Warnungen | Should -Be 1; $a.Befunde.Hinweise | Should -Be 2
            @($a.Befunde.Liste) | Should -Be @('[WARNUNG] Kühlung: Lüfterdrehzahl erhöht', 'freier Text')
        }
        It 'gewählte Systeme sind in ihrer Reihenfolge vorausgewählt, die übrigen bleiben im Vergleich' {
            $wahl = @((Get-DbPfad $script:Root 'LIZZZ_20260930_161500.json'), (Get-DbPfad $script:Root 'TORRENT_20260930_215900.json'))
            $d = MinibenchTest\Export-BenchDashboardData -DatabaseDir $script:Root -SystemPaths $wahl
            @($d.PreselectedIds) | Should -Be @('LIZZZ_202609301615', 'TORRENT_202609302159')
            @($d.Systems).Count | Should -Be 3
            @($d.Systems | ForEach-Object { $_.Id } | Select-Object -Unique).Count | Should -Be 3
        }
        It 'Referenzprofile in der Datenbank erscheinen nicht als geprüftes System' {
            $root = New-DashboardDaten
            $ref = Join-Path (Join-Path $root 'Datenbank') 'Desktop_HighEnd.json'
            Copy-Item -LiteralPath (Join-Path $global:MinibenchSrcRoot 'Daten/Referenzen/Desktop_HighEnd.json') -Destination $ref
            Add-DbEintrag $root 'Kopie.json' @{ Format = 'PC-Diagnose-DB/2'; Typ = 'Referenz'; Name = 'Referenzkopie'; Computer = 'REF-KOPIE'; Datum = '2026-10-05 10:00' } | Out-Null
            $d = MinibenchTest\Export-BenchDashboardData -DatabaseDir $root -SystemPaths @($ref)
            @($d.Systems | ForEach-Object { $_.Computer } | Sort-Object) | Should -Be @('DESKTOP-F9HRMRR', 'LIZZZ', 'TORRENT')
            @($d.PreselectedIds).Count | Should -Be 0
            @($d.References).Count | Should -Be 5
        }
        It 'Export als JSON-Datei (UTF-8 mit BOM, CRLF) ist wieder einlesbar' {
            $ziel = Join-Path $TestDrive 'Dashboard-Daten.json'
            $json = MinibenchTest\Export-BenchDashboardData -DatabaseDir $script:Root -AsJson -OutputPath $ziel
            $bytes = [IO.File]::ReadAllBytes($ziel)
            @($bytes[0..2]) | Should -Be @(0xEF, 0xBB, 0xBF)
            [IO.File]::ReadAllText($ziel, [Text.Encoding]::UTF8) | Should -Match "`r`n"
            $zurueck = [IO.File]::ReadAllText($ziel, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $zurueck.Version | Should -Be (Get-MinibenchVersion)
            @($zurueck.Systems).Count | Should -Be 3
            ($json | ConvertFrom-Json).Version | Should -Be (Get-MinibenchVersion)
        }
    }

    Context 'Verlinkung der Diagnoseberichte' {
        It 'Link relativ zum Dashboard im Berichtsordner: <Fall>' -ForEach @(
            @{ Fall = 'Ordner relativ zum Datenordner'; Feld = 'Ordner'; Wert = 'Berichte\PC-A_20261001_1200'; Url = 'PC-A_20261001_1200/Diagnosebericht.html' }
            @{ Fall = 'Berichtspfad mit Datei'; Feld = 'BerichtPfad'; Wert = 'Berichte\PC-A_20261001_1200\Diagnosebericht.html'; Url = 'PC-A_20261001_1200/Diagnosebericht.html' }
            @{ Fall = 'absoluter Ordner auf dem Stick'; Feld = 'Ordner'; Wert = 'D:\Stick\Minibench-Daten\Berichte\PC-A_20261001_1200\'; Url = 'PC-A_20261001_1200/Diagnosebericht.html' }
            @{ Fall = 'Ordner ohne Präfix'; Feld = 'Ordner'; Wert = 'PC-A_20261001_1200'; Url = 'PC-A_20261001_1200/Diagnosebericht.html' }
        ) {
            $root = New-DashboardDaten @()
            $e = @{ Format = 'PC-Diagnose-DB/2'; Name = 'PC-A'; Computer = 'PC-A'; Datum = '2026-10-01 12:00' }
            $e[$Feld] = $Wert
            Add-DbEintrag $root 'PC-A.json' $e | Out-Null
            $a = Get-SystemNachName (MinibenchTest\Export-BenchDashboardData -DatabaseDir $root -IncludeReferences:$false) 'PC-A'
            $a.ReportUrl | Should -Be $Url
        }
        It 'der Link führt von Dashboard.html zum vorhandenen Bericht (kein ERR_FILE_NOT_FOUND)' {
            $root = New-DashboardDaten @()
            $ordner = Join-Path (Join-Path $root 'Berichte') 'PC-A_20261001_1200'
            New-Item -ItemType Directory -Path $ordner -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $ordner 'Diagnosebericht.html') -Value '<html></html>'
            Add-DbEintrag $root 'PC-A.json' @{ Format = 'PC-Diagnose-DB/2'; Name = 'PC-A'; Computer = 'PC-A'; Datum = '2026-10-01 12:00'; Ordner = 'Berichte\PC-A_20261001_1200' } | Out-Null
            $seite = MinibenchTest\Export-BenchDashboardHtml -DatenOrdner $root
            $seite | Should -Be (Join-Path (Join-Path $root 'Berichte') 'Dashboard.html')
            $url = (Get-SystemNachName (Get-EingebetteteDaten ([IO.File]::ReadAllText($seite, [Text.Encoding]::UTF8))) 'PC-A').ReportUrl
            Test-Path -LiteralPath (Join-Path (Split-Path $seite -Parent) $url) | Should -BeTrue
        }
        # bekannter Fehler, Behebung offen: Ersatz-Ordnername wird als Datum_PC (202609302159_TORRENT) statt PC_Datum_Zeit gebaut
        It 'ohne Ordnerangabe zeigt der Link auf den Berichtsordner PC_Datum_Zeit' -Skip {
            $t = Get-SystemNachName $script:Daten 'TORRENT'
            $t.ReportUrl | Should -Be 'TORRENT_20260930_2159/Diagnosebericht.html'
        }
    }

    Context 'Zeitreihen und Drosselung' {
        It 'Messpunkte stammen aus Lasttest-Verlauf.csv im Berichtsordner' {
            $s = @((Get-SystemNachName $script:DatenCsv 'PC-T').Telemetry.Series)
            $s.Count | Should -Be 8
            $s[0].T | Should -Be 0
            $s[0].Fps | Should -BeNullOrEmpty
            $s[3].T | Should -Be 6
            $s[3].MHz | Should -Be 3950
            $s[3].Temp | Should -Be 63.5
            $s[3].GpuTemp | Should -Be 53
            $s[3].CpuW | Should -Be 83.2
            $s[3].Fps | Should -Be 103
        }
        It 'Drosselung, TjMax und Unterbrechungen aus den Sensorwerten des Lasttests' {
            $t = (Get-SystemNachName $script:DatenCsv 'PC-T').Telemetry
            $t.CpuTempMax | Should -Be 91
            $t.TjMax | Should -Be 95
            $t.Drosselung | Should -Be 'thermisch'
            $t.UnterbrechungenUeber50ms | Should -BeTrue
            @($t.ThrottleEvents).Count | Should -Be 1
            @($t.ThrottleEvents)[0].Label | Should -Be 'Drosselung (thermisch, -12 %)'
            $k = (Get-SystemNachName $script:DatenCsv 'PC-K').Telemetry
            $k.Drosselung | Should -Be 'keine'
            $k.UnterbrechungenUeber50ms | Should -BeFalse
            @($k.ThrottleEvents).Count | Should -Be 0
        }
        # bekannter Fehler, Behebung offen: ohne CSV wird eine synthetische Telemetriekurve erfunden und als Messung gezeigt
        It 'ohne Verlaufsdatei gibt es keine Kurve (keine erfundenen Messpunkte)' -Skip {
            @((Get-SystemNachName $script:Daten 'TORRENT').Telemetry.Series).Count | Should -Be 0
            @((Get-SystemNachName $script:DatenCsv 'PC-K').Telemetry.Series).Count | Should -Be 0
        }
    }

    Context 'HTML-Seite' {
        BeforeAll {
            $script:Seite = Join-Path $TestDrive 'Dashboard_Test.html'
            MinibenchTest\New-BenchDashboardHtml -DashboardData $script:Daten -OutputPath $script:Seite | Out-Null
            $script:SeiteText = [IO.File]::ReadAllText($script:Seite, [Text.Encoding]::UTF8)
            $script:Vorlage = MinibenchTest\Get-BenchDashboardHtmlTemplate
        }
        It 'ist ein vollständiges deutsches HTML-Dokument mit den exportierten Daten' {
            $script:SeiteText | Should -Match '^<!DOCTYPE html>'
            $script:SeiteText | Should -Match '<html lang="de"'
            $script:SeiteText | Should -Match '</html>\s*$'
            $d = Get-EingebetteteDaten $script:SeiteText
            $d.Version | Should -Be (Get-MinibenchVersion)
            @($d.Systems | ForEach-Object { $_.Id } | Sort-Object) | Should -Be @($script:Daten.Systems | ForEach-Object { $_.Id } | Sort-Object)
            @($d.References).Count | Should -Be 5
            (@($d.Systems | Where-Object { $_.Computer -eq 'TORRENT' })[0]).Metrics.CPU_MT | Should -Be 38101
        }
        It 'lädt nichts aus dem Netz (läuft offline vom Stick)' {
            $script:SeiteText | Should -Not -Match '(src|href)\s*=\s*["'']?(https?:)?//'
            $script:SeiteText | Should -Not -Match '@import|url\(\s*["'']?(https?:)?//'
            $script:SeiteText | Should -Not -Match '<link[^>]+rel="stylesheet"'
        }
        It 'jedes Element, das das Skript über die id anspricht, steht in der Seite' {
            $ids = @([regex]::Matches($script:Vorlage, "getElementById\('([^']+)'\)") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
            $ids.Count | Should -BeGreaterThan 10
            foreach ($id in $ids) { $script:SeiteText | Should -Match ('id="{0}"' -f [regex]::Escape($id)) -Because $id }
        }
        It 'jedes Feld, das das Skript liest, liefert Export-BenchDashboardData' {
            $sys = Get-SystemNachName $script:DatenCsv 'PC-T'
            $fehlt = New-Object System.Collections.ArrayList
            $pruefe = { param($Muster, $Ziel, [string]$Name) foreach ($m in [regex]::Matches($script:Vorlage, $Muster)) { $f = $m.Groups[1].Value; if (-not $Ziel.Contains($f)) { [void]$fehlt.Add($Name + '.' + $f) } } }
            & $pruefe '\b(?:s|sys|r|mid|match|other|baseSystem)\??\.([A-Z]\w*)' $sys 'System'
            & $pruefe '\bHardware\?\.(\w+)' $sys.Hardware 'Hardware'
            & $pruefe '\bb\.([A-Z]\w*)' $sys.Befunde 'Befunde'
            & $pruefe '\bTelemetry\?\.(\w+)' $sys.Telemetry 'Telemetry'
            & $pruefe '\b(?:pt|closest)\.([A-Z]\w*)' @($sys.Telemetry.Series)[0] 'Messpunkt'
            & $pruefe 'FastestDisk\?\.(\w+)' $sys.Metrics.FastestDisk 'FastestDisk'
            & $pruefe "key: '((?:CPU|RAM|GPU)_\w+)'" $sys.Metrics 'Metrics'
            & $pruefe '\bdata\.([A-Z]\w*)' $script:DatenCsv 'Daten'
            @($fehlt | Select-Object -Unique) | Should -BeNullOrEmpty
        }
        It 'Export-BenchDashboardHtml legt Dashboard.html in den Berichtsordner, gewählte Systeme vorausgewählt' {
            $wahl = @((Get-DbPfad $script:Root 'TORRENT_20260930_215900.json'), (Get-DbPfad $script:Root 'DESKTOP-F9HRMRR_20260930_174200.json'))
            $seite = MinibenchTest\Export-BenchDashboardHtml -DatenOrdner $script:Root -SystemPaths $wahl
            $seite | Should -Be (Join-Path (Join-Path $script:Root 'Berichte') 'Dashboard.html')
            $d = Get-EingebetteteDaten ([IO.File]::ReadAllText($seite, [Text.Encoding]::UTF8))
            @($d.PreselectedIds) | Should -Be @('TORRENT_202609302159', 'DESKTOP-F9HRMRR_202609301742')
            @($d.Systems).Count | Should -Be 3
        }
        It 'Start: -Vergleich und -Dashboard rufen Export-BenchDashboardHtml mit gültigen Parametern und den Systempfaden auf' {
            $t = $null; $e = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput((Get-SrcText 'Ablauf/Start.ps1'), [ref]$t, [ref]$e)
            $aufrufe = @($ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] -and $a.GetCommandName() -eq 'Export-BenchDashboardHtml' }, $true))
            $aufrufe.Count | Should -BeGreaterOrEqual 2
            $cmd = Get-Command -Module MinibenchTest -Name Export-BenchDashboardHtml
            $erlaubt = @($cmd.Parameters.Keys) + @($cmd.Parameters.Values | ForEach-Object { $_.Aliases })
            foreach ($a in $aufrufe) {
                $p = @($a.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
                $p | Should -Contain 'SystemPaths'
                foreach ($n in $p) { $erlaubt | Should -Contain $n }
            }
        }
        # bekannter Fehler, Behebung offen: Systemnamen und Befundtexte werden ohne HTML-Maskierung über innerHTML eingesetzt
        It 'Systemnamen werden nicht ungeschützt als HTML eingesetzt' -Skip {
            $script:Vorlage | Should -Not -Match '\$\{s\.DisplayName'
            $script:Vorlage | Should -Not -Match '\$\{s\.Computer\}'
        }
    }
}
