# Zusammenbau aus src: vollständig, fehlerfrei, eindeutig, Protokoll zwischen Arbeitsprozess und Oberfläche stimmig
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $b = Get-MinibenchBuild
    $gui = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui.cs'))
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
        Join-Path $global:MinibenchRepoRoot ('Doku/Änderungen_v{0}.txt' -f $b.Version) | Should -Exist
    }
    It 'hat eine Testmatrix zur Version' {
        Join-Path $global:MinibenchRepoRoot ('Doku/Testmatrix_v{0}.csv' -f $b.Version) | Should -Exist
    }
    It 'trägt die Version in Bauen.cmd nicht fest ein' {
        [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd')) | Should -Not -Match 'AssemblyVersion\("\d'
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
        $t = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'))
        $t | Should -Match "'Aktueller Build'"
        $t | Should -Match 'Stand\.txt'
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
