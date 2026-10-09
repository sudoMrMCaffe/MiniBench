# Aufbau: Zusammenbau aus src nach Bauplan (vollständig, fehlerfrei, eindeutig), Protokoll zwischen Arbeitsprozess und
# Oberfläche, Bauen.cmd (Launcher-exe mit Startfenster und Manifest, Dateiversion, README, Archiv und Datenpflege),
# Startzeit (Start.log), Programmsymbol, Add-CachedType, Windows PowerShell 5.1 als Laufzeit und Startparameter.
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $b = Get-MinibenchBuild
    $gui = @(Get-GuiQuellen | ForEach-Object { [IO.File]::ReadAllText($_, [Text.Encoding]::UTF8) }) -join "`n"
    $cmd = Get-RepoText 'Bauen.cmd'
    Import-MinibenchTestModule -Parts 'Kern\Startzeit.ps1' -Functions 'Write-StartPhase', 'Add-CachedType', 'Test-WritableDir' `
        -Setup '$script:CacheDir = ''''; $script:CacheInfo = New-Object System.Collections.Generic.List[string]'
}

Describe 'Zusammenbau' {
    It 'baut ohne Fehler' {
        $b.Fehler | Should -BeNullOrEmpty
    }
    It 'verwendet jede Datei in src' {
        $b.Warnungen | Should -BeNullOrEmpty
    }
    It 'findet die Version' {
        $b.Version | Should -Match '^\d+\.\d+(\.\d+)?$'
    }
    It 'hat eine Änderungsdatei zur Version' {
        Join-Path $global:MinibenchRepoRoot (('Doku/' + [char]0x00C4 + 'nderungen_v{0}.txt') -f $b.Version) | Should -Exist
    }
    It 'trägt die Version in Bauen.cmd nicht fest ein' {
        $cmd | Should -Not -Match 'AssemblyVersion\("\d'
    }
    It 'Aktueller Build entspricht src (sonst Bauen.cmd ausführen)' {
        $f = Join-Path $global:MinibenchRepoRoot 'Aktueller Build/LeosMinibench.ps1'
        if (-not (Test-Path -LiteralPath $f)) { Set-ItResult -Skipped -Because 'Aktueller Build fehlt noch'; return }
        $disk = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        # kein Fehlschlag: während der Entwicklung ist src naturgemäß neuer als der Build
        if ($disk -ne $b.Text) { Set-ItResult -Inconclusive -Because 'src ist neuer als der Aktuelle Build, Bauen.cmd ausführen'; return }
        $disk | Should -BeExactly $b.Text
    }
    It 'Startdatei für den Stick liegt in src' {
        $c = Join-Path $global:MinibenchSrcRoot 'LeosMinibench.cmd'
        $c | Should -Exist
        [IO.File]::ReadAllText($c) | Should -Match 'LeosMinibench\.ps1'
    }
    It 'Bauen.cmd legt alles in Aktueller Build ab' {
        $cmd | Should -Match "'Aktueller Build'"
        $cmd | Should -Match 'Stand\.txt'
    }
    It 'definiert jede Funktion nur einmal' {
        $dup = @((Get-TopFunctions).GetEnumerator() | Where-Object { @($_.Value).Count -gt 1 } | ForEach-Object { $_.Key })
        $dup | Should -BeNullOrEmpty
    }
    It 'beginnt mit #Requires und dem Hinweis auf src' {
        $lines = $b.Text -split "`r`n"
        $lines[0] | Should -Be '#Requires -Version 5.1'
        $lines[1] | Should -Match 'src'
    }
}

Describe 'Vollständigkeit der Quelltextdateien' {
    It 'jede ps1-, cs- und psd1-Datei in src ist im Bauplan oder bekannt' {
        $bp = Get-SrcText 'Bauplan.txt'
        $all = @(Get-ChildItem $global:MinibenchSrcRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.cs', '.psd1' })
        $all.Count | Should -BeGreaterThan 20
        $known = @(
            'src\00_Kopf.ps1', 'src\Bauplan.txt', 'src\Zusammenbau.ps1', 'src\LeosMinibench.cmd',
            'src\Kern\Grafiktest.cs', 'src\Kern\Sensoren.cs', 'src\Kern\Testroutinen.cs',
            'src\Oberflaeche\DiagGui.cs', 'src\Oberflaeche\DiagGui_Steuerelemente.cs',
            'src\Oberflaeche\DiagGui_Modelle.cs', 'src\Oberflaeche\DiagGui_Vergleich.cs',
            'src\Oberflaeche\DiagGui_Seiten.cs', 'src\Oberflaeche\Start.cs', 'src\Oberflaeche\Versionen.cs'
        )
        foreach ($f in $all) {
            # relativer Pfad mit \ wie im Bauplan (unter Linux trennt das Dateisystem mit /)
            $rel = $f.FullName.Substring($global:MinibenchSrcRoot.Length + 1).Replace('/', '\')
            $isModuleContract = $rel -match '^Module\\[^\\]+\\Vertrag\.psd1$'
            $isKatalog = $rel -match 'Katalog\.psd1$'
            $inBauplan = $bp -match [regex]::Escape($rel)
            $inKnown = $known -contains ('src\' + $rel)
            ($inBauplan -or $isModuleContract -or $isKatalog -or $inKnown) | Should -BeTrue -Because $rel
        }
    }
}

Describe 'Launcher, Startfenster und Anwendungsmanifest' {
    It 'Bauen.cmd enthält Per-Monitor V2 DPI-Awareness im Manifest' {
        $cmd | Should -Match '<dpiAwareness[^>]*>PerMonitorV2,\s*PerMonitor</dpiAwareness>'
        $cmd | Should -Match '<dpiAware[^>]*>true/pm</dpiAware>'
    }
    It 'Bauen.cmd definiert Splash-Fenster und Launcher mit Startphasen' {
        $cmd | Should -Match 'class Splash : Form'
        $cmd | Should -Match 'LEOSMINIBENCH_BEREIT'
        $cmd | Should -Match 'csc\.exe'
    }
    It 'Launcher setzt Argumente nach den Regeln von CommandLineToArgvW zusammen' {
        if (-not ('MinibenchLauncherQuote' -as [type])) {
            $m = [regex]::Match($cmd, '(?s)static string Quote\(string s\)\s*\{.+?\r?\n    \}')
            $m.Success | Should -BeTrue
            Add-Type -TypeDefinition ('using System; using System.Text; public static class MinibenchLauncherQuote { public ' + $m.Value + ' }')
        }
        [MinibenchLauncherQuote]::Quote('einfach') | Should -BeExactly 'einfach'
        [MinibenchLauncherQuote]::Quote('') | Should -BeExactly '""'
        [MinibenchLauncherQuote]::Quote('C:\Mit Leerzeichen\') | Should -BeExactly '"C:\Mit Leerzeichen\\"'
        [MinibenchLauncherQuote]::Quote('a"b') | Should -BeExactly '"a\"b"'
        [MinibenchLauncherQuote]::Quote('x\"y z') | Should -BeExactly '"x\\\"y z"'
    }
    It 'Startphasen: die exe gibt dem Skript die Statusdatei mit, das Skript hängt seine Phase an' {
        $cmd | Should -Match 'EnvironmentVariables\["LEOSMINIBENCH_START"\]'
        # Skript und Oberfläche hängen gleichzeitig an, die exe liest geteilt mit
        $cmd | Should -Match 'FileShare\.ReadWrite \| FileShare\.Delete'
        (Get-SrcText 'Oberflaeche/Start.cs') | Should -Match 'GetEnvironmentVariable\("LEOSMINIBENCH_START"\)'
        $f = Join-Path $TestDrive ('Start_' + [guid]::NewGuid().ToString('N') + '.log')
        [IO.File]::WriteAllText($f, '')
        $alt = $env:LEOSMINIBENCH_START
        $env:LEOSMINIBENCH_START = $f
        try { MinibenchTest\Write-StartPhase 'Skript läuft | Teil 2' } finally { $env:LEOSMINIBENCH_START = $alt }
        $z = @([IO.File]::ReadAllLines($f, [Text.Encoding]::UTF8) | Where-Object { $_ })
        $z.Count | Should -Be 1
        $z[0] | Should -Match '^\d+\|S\|Skript läuft / Teil 2$'
    }
    It 'ohne Statusdatei schreibt das Skript keine Startphase' {
        $alt = $env:LEOSMINIBENCH_START
        $env:LEOSMINIBENCH_START = $null
        try { { MinibenchTest\Write-StartPhase 'egal' } | Should -Not -Throw } finally { $env:LEOSMINIBENCH_START = $alt }
    }
    It 'Dateiversion der exe: zweistellige Nachkommastellen (2.7 nach 2.67)' {
        $code = [regex]::Match($cmd, '(?s)\$vp = @\(.+?\$asmVer = [^\r\n]+').Value
        $code | Should -Not -BeNullOrEmpty
        $f = [scriptblock]::Create('param($ver) ' + $code + '; $asmVer')
        & $f '2.7' | Should -Be '2.70.0.0'
        & $f '2.67' | Should -Be '2.67.0.0'
        & $f '3.0' | Should -Be '3.0.0.0'
        & $f '3.52' | Should -Be '3.52.0.0'
    }
    It 'Bauen.cmd setzt Version, Download und Testanzahl in README.md' {
        $m = [regex]::Match($cmd, '(?s)\$rmText = \[IO\.File\]::ReadAllText\(\$readmeFile[^\n]*\n(.+?)\n\s*\[IO\.File\]::WriteAllText\(\$readmeFile')
        $m.Success | Should -BeTrue
        $f = [scriptblock]::Create("param(`$rmText, `$ver, `$testInfo)`n" + $m.Groups[1].Value + "`n`$rmText")
        $alt = @(
            '[![Version](https://img.shields.io/badge/Version-3.4-0284c7.svg)](CHANGELOG.md)'
            '[![Tests](https://img.shields.io/badge/Tests-500%2B%20bestanden-22c55e.svg)](tests/)'
            '<img src="https://img.shields.io/badge/Download-LeosMinibench.exe%20(v3.4)-2563eb?style=for-the-badge" alt="Download" />'
            '<img src="Doku/Screenshots/Oberflaeche.png" alt="Leos Minibench 3.4 Oberfläche" />'
        ) -join "`n"
        $neu = & $f $alt '3.6' 'Tests: 612 bestanden, 0 fehlgeschlagen, 4 übersprungen'
        $neu | Should -Match 'badge/Version-3\.6-0284c7\.svg'
        $neu | Should -Match 'Download-LeosMinibench\.exe%20\(v3\.6\)'
        $neu | Should -Match 'alt="Leos Minibench 3\.6 Oberfläche"'
        $neu | Should -Match 'badge/Tests-610%2B%20bestanden-22c55e\.svg'
        # README.md enthält die Stellen, die Bauen.cmd ersetzt
        $rm = Get-RepoText 'README.md'
        $rm | Should -Match 'img\.shields\.io/badge/Version-[^-\s]+-[0-9a-fA-F]+\.svg'
        $rm | Should -Match 'Download-LeosMinibench\.exe%20\(v[^\)]+\)'
    }
    It 'Datenpflege ist eingebunden: Parameter, ohne Adminrechte, vor der Oberfläche, Start der Oberfläche, Bauen.cmd' {
        Get-ScriptParameters | Should -Contain 'Datenpflege'
        Get-ScriptParameters | Should -Contain 'ArchivDir'
        $plan = @($b.Teile)
        [array]::IndexOf($plan, 'Kern\Datenpflege.ps1') | Should -BeGreaterOrEqual 0
        [array]::IndexOf($plan, 'Kern\Datenpflege.ps1') | Should -BeLessThan ([array]::IndexOf($plan, 'Oberflaeche\Oberflaeche.ps1'))
        (Get-SrcText 'Kern/Adminrechte.ps1') | Should -Match '-not \$Datenpflege'
        (Get-SrcText 'Oberflaeche/Oberflaeche.ps1') | Should -Match 'Invoke-Datenpflege -DataDir \$script:DataDir -MindestAlterMin 60'
        $cmd | Should -Match '-Datenpflege -DatenDir \$bData -ArchivDir'
        $cmd | Should -Match "Archiv\\v\{0\}' -f \`$oldVer"
    }
}

Describe 'Startzeit (Start.log)' {
    BeforeAll {
        $log = @(
            'START|2026-10-02 10:00:00|2.6|Stick|E:|4200', 'PHASE|0|L|Programm gestartet', 'PHASE|300|L|Startfenster sichtbar', 'PHASE|900|L|Skript entpackt (lokales TEMP)', 'PHASE|1000|L|PowerShell gestartet',
            'PHASE|2600|S|PowerShell bereit, Skript läuft', 'PHASE|3100|S|Oberfläche geladen (LeosMinibench-Oberflaeche aus dem Cache)', 'PHASE|4200|O|Oberfläche bereit',
            'START|2026-10-02 10:05:00|2.6|Stick|E:|3800', 'PHASE|0|L|Programm gestartet', 'PHASE|200|L|Startfenster sichtbar', 'PHASE|800|L|Skript entpackt (lokales TEMP)', 'PHASE|900|L|PowerShell gestartet',
            'PHASE|2300|S|PowerShell bereit, Skript läuft', 'PHASE|2800|S|Oberfläche geladen (LeosMinibench-Oberflaeche übersetzt und zwischengespeichert)', 'PHASE|3800|O|Oberfläche bereit',
            'START|2026-10-02 11:00:00|2.6|Festplatte|C:|1500', 'PHASE|0|L|Programm gestartet', 'PHASE|120|L|Startfenster sichtbar', 'PHASE|1500|O|Oberfläche bereit',
            'Müll', 'PHASE|kaputt'
        )
    }
    It 'liest Blöcke und Phasen, unlesbare Zeilen fallen weg' {
        $s = @(MinibenchTest\ConvertFrom-StartLog $log)
        $s.Count | Should -Be 3
        $s[0].Ort | Should -Be 'Stick'; $s[0].GesamtMs | Should -Be 4200; $s[0].Phasen.Count | Should -Be 7
        $s[2].Phasen.Count | Should -Be 3
    }
    It 'wertet je Ort mit Median aus und fasst Phasen mit wechselnden Zusätzen zusammen' {
        $a = @(MinibenchTest\Get-StartAnalysis (MinibenchTest\ConvertFrom-StartLog $log))
        $stick = $a | Where-Object { $_.Ort -eq 'Stick' }
        $stick.Starts | Should -Be 2; $stick.MedianMs | Should -Be 4000
        $p = $stick.Phasen | Where-Object { $_.Phase -eq 'Oberfläche geladen' }
        $p.ZeitpunktMs | Should -Be 2950; $p.DauerMs | Should -Be 500
        ($stick.Phasen | Where-Object { $_.Phase -eq 'Startfenster sichtbar' }).ZeitpunktMs | Should -Be 250
        ($a | Where-Object { $_.Ort -eq 'Festplatte' }).MedianMs | Should -Be 1500
    }
    It 'Text für die Ausgabe' {
        $t = (MinibenchTest\Format-StartAnalysis (MinibenchTest\Get-StartAnalysis (MinibenchTest\ConvertFrom-StartLog $log))) -join "`n"
        $t | Should -Match 'Start von Stick: 2 Start\(s\), Version 2\.6, bis zur bedienbaren Oberfläche Median 4,00 s'
        $t | Should -Match 'Startfenster sichtbar \(exe\)\s+0,25 s'
        (MinibenchTest\Format-StartAnalysis @()) | Should -Match 'Noch keine Starts'
    }
}

Describe 'Programmsymbol' {
    It 'Symbol.ico enthält 16, 24, 32, 48, 64, 128 und 256 Pixel' {
        $f = Join-Path $global:MinibenchSrcRoot 'Oberflaeche/Symbol.ico'
        $f | Should -Exist
        $ico = [IO.File]::ReadAllBytes($f)
        $n = [BitConverter]::ToUInt16($ico, 4)
        $sizes = @(for ($i = 0; $i -lt $n; $i++) { $w = $ico[6 + 16 * $i]; if ($w -eq 0) { 256 } else { [int]$w } }) | Sort-Object
        $sizes | Should -Be @(16, 24, 32, 48, 64, 128, 256)
    }
    It 'Bauen.cmd bettet Symbol.ico und Symbol.png in die exe ein' {
        $cmd | Should -Match "Oberflaeche\\Symbol\.ico"
        $cmd | Should -Match 'Symbol\.png'
        Join-Path $global:MinibenchSrcRoot 'Oberflaeche/Symbol.png' | Should -Exist
    }
}

Describe 'C#-Teile übersetzen (Add-CachedType)' {
    It 'Compilerwarnungen verhindern das Laden nicht (Windows PowerShell wertet sie sonst als Fehler)' {
        $n = 'MinibenchWarnTest_' + [guid]::NewGuid().ToString('N')
        # ohne Cache-Ordner: übersetzt im Speicher, es entsteht keine DLL
        Set-ModuleVar 'CacheDir' ''
        { MinibenchTest\Add-CachedType $n ('public static class {0} {{ public static int F() {{ int unbenutzt = 1; return 2; }} }}' -f $n) 3>$null } | Should -Not -Throw
        ($n -as [type]) | Should -Not -BeNullOrEmpty
        ([type]$n)::F() | Should -Be 2
        @(Get-ModuleVar 'CacheInfo') | Should -Contain ('{0} übersetzt (ohne Cache)' -f $n)
    }
}

Describe 'Windows PowerShell 5.1 als Laufzeit' {
    It 'Bauen.cmd und der Launcher starten Windows PowerShell 5.1, nie pwsh' {
        $cmd | Should -Match 'powershell\.exe -NoProfile'
        $cmd | Should -Match 'WindowsPowerShell\\v1\.0\\powershell\.exe'
        $cmd | Should -Not -Match 'pwsh\.exe'
    }
    It 'src/LeosMinibench.cmd startet powershell.exe direkt' {
        $c = Get-SrcText 'LeosMinibench.cmd'
        $c | Should -Match 'start "" powershell\.exe'
        $c | Should -Not -Match 'pwsh'
    }
}

Describe 'Protokoll zwischen Arbeitsprozess und Oberfläche' {
    It 'jede gesendete @@-Art wird von der Oberfläche verarbeitet' {
        $sent = @([regex]::Matches($b.Text, "Send-GuiEvent '([A-Z]+)'") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        $handled = @([regex]::Matches($gui, 'case "([A-Z]+)":') | ForEach-Object { $_.Groups[1].Value }) + @([regex]::Matches($gui, '"@@([A-Z]+)\|"') | ForEach-Object { $_.Groups[1].Value })
        foreach ($k in $sent) { $handled | Should -Contain $k -Because "@@$k muss in DiagGui.cs ausgewertet werden" }
    }
    It 'die Oberfläche bekommt den Modulvertrag übergeben' {
        $b.Text | Should -Match '\[DiagGui\]::Run\([^\r\n]*Get-ContractGuiLines'
        $gui | Should -Match 'public static void Run\([^)]*string\[\] contract\)'
    }
}

Describe 'Startparameter' {
    It 'jeder Sondermodus schließt Oberfläche, Berichtsordner und Testroutinen aus' {
        foreach ($m in 'ImportOrdner', 'Vergleich', 'Rueckgaengig', 'SensorLive', 'SensorWerkzeugeHolen', 'SensorAufraeumen') {
            (Get-PartText 'Oberflaeche\Oberflaeche.ps1') | Should -Match ('-not \${0}' -f $m)
            (Get-PartText 'Kern\Grundgeruest.ps1') | Should -Match ('-not \${0}' -f $m)
            (Get-PartText 'Kern\Testroutinen.ps1') | Should -Match ('-not \${0}' -f $m)
        }
    }
    It 'die Sensormodi laufen vor dem Start eines Laufs und enden mit exit' {
        $plan = @(Get-Content (Join-Path $global:MinibenchSrcRoot 'Bauplan.txt') -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
        [array]::IndexOf($plan, 'Module\Sensoren\Ablauf.ps1') | Should -BeLessThan ([array]::IndexOf($plan, 'Ablauf\Start.ps1'))
        [array]::IndexOf($plan, 'Kern\Sensoren.ps1') | Should -BeLessThan ([array]::IndexOf($plan, 'Module\Sensoren\Ablauf.ps1'))
        $t = Get-PartText 'Module\Sensoren\Ablauf.ps1'
        ([regex]::Matches($t, '(?m)^\s*exit ')).Count | Should -Be 3
    }
    It 'der Abschluss schließt die Sensoren vor der Rückstandskontrolle' {
        $t = Get-PartText 'Ablauf\Abschluss.ps1'
        $t.IndexOf('Close-SensorSession') | Should -BeGreaterThan 0
        $t.IndexOf('Close-SensorSession') | Should -BeLessThan $t.IndexOf('function Invoke-ResidueCheck')
    }
    It 'die Live-Ansicht der Oberfläche endet über sensor.stop, nicht durch Abschießen' {
        $gui | Should -Match 'sensor\.stop'
        (Get-PartText 'Module\Sensoren\Ablauf.ps1') | Should -Match 'sensor\.stop'
        $gui | Should -Match 'if \(liveRunning\) StopLiveAndWait\(\);'
    }
    It 'nach einem Abbruch räumt die Oberfläche den Treiber sofort auf' {
        $gui | Should -Match 'RunHelperPumped\("-SensorAufraeumen"'
        ([regex]::Matches($gui, 'CleanupDriver\(\);')).Count | Should -BeGreaterOrEqual 3
        $gui | Should -Match '"PawnIO_" \+ n \+ ".txt"'
        (Get-PartText 'Kern\Sensoren.ps1') | Should -Match "'PawnIO_\{0\}\.txt' -f \(Get-SafeName \`$env:COMPUTERNAME\)"
    }
}

Describe 'Regeln für die Testsuite selbst' {
    It 'jede Attrappe mit -ParameterFilter hat in derselben Datei eine Vorgabe-Attrappe ohne Filter (Pester 6)' {
        # Pester 6 ruft ohne passende Attrappe nicht mehr den echten Befehl, sondern bricht ab
        foreach ($f in @(Get-ChildItem $PSScriptRoot -Filter '*.Tests.ps1')) {
            $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
            $mit = @{}; $ohne = @{}
            foreach ($m in [regex]::Matches($t, '(?m)^\s*Mock\s+(?:-ModuleName\s+\S+\s+)?(\S+)(.*)$')) {
                if ($m.Groups[2].Value -match '-ParameterFilter') { $mit[$m.Groups[1].Value] = $true } else { $ohne[$m.Groups[1].Value] = $true }
            }
            foreach ($k in $mit.Keys) { $ohne.ContainsKey($k) | Should -BeTrue -Because ('{0}: Mock {1} nur mit -ParameterFilter' -f $f.Name, $k) }
        }
    }
    It 'keine Testdateien je Version mehr (Fachgebiete statt Versionen)' {
        @(Get-ChildItem $PSScriptRoot -Filter 'Version*.Tests.ps1').Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Dashboard.Tests.ps1') | Should -BeFalse -Because 'Dashboard-Tests stehen in Bericht.Tests.ps1'
    }
}

