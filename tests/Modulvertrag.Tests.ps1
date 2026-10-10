# Modulverträge: vollständig, widerspruchsfrei und mit Skript und Oberfläche abgestimmt; schneller Modus (parallele und
# exklusive Schritte) und die Diagnose ohne CPU-Stabilitätstest (CPU-Last nur im Lasttest).
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Modulvertrag.ps1'
    $contracts = Get-ModuleVar 'ModuleContracts'
    $params = Get-ScriptParameters
    $gui = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui.cs'))
    function Get-CsArray([string]$Name) {
        if ($gui -notmatch ('(?s)string\[\] {0} = new string\[\] \{{(.*?)\}};' -f $Name)) { throw "$Name nicht gefunden" }
        @([regex]::Matches($Matches[1], '"((?:[^"\\]|\\.)*)"') | ForEach-Object { $_.Groups[1].Value })
    }
    function ConvertTo-Sorted($o) {
        if ($o -is [System.Collections.IDictionary]) { $r = [ordered]@{}; foreach ($k in @($o.Keys | Sort-Object)) { $r[$k] = ConvertTo-Sorted $o[$k] }; return $r }
        if ($o -is [array]) { return , @($o | ForEach-Object { ConvertTo-Sorted $_ }) }
        return $o
    }
    function ConvertTo-SortedJson($o) { (ConvertTo-Sorted $o) | ConvertTo-Json -Depth 8 -Compress }
    # Allgemeine Parameter, die zu keinem Modul gehören
    $general = @('Module', 'KiOhneAnonymisierung', 'DatenDir', 'OutputDir', 'ImportOrdner', 'Vergleich', 'Rueckgaengig', 'EventMode', 'WerkzeugeBehalten', 'GpuAufloesung', 'GpuAnzeige', 'GpuAuswahl', 'StartAuswertung', 'Datenpflege', 'ArchivDir', 'Dashboard', 'DashboardExport', 'DashboardSysteme', 'SoftwareInstallieren', 'Abgleich', 'AbgleichLoeschen', 'AbgleichNeu', 'Entfernen', 'Umbenennen', 'NeuerName', 'MedianAktualisieren')
}

Describe 'Verträge im Skript' {
    It 'enthält die sechs Module in fester Reihenfolge' {
        @($contracts | ForEach-Object { $_.Name }) | Should -Be @('Diagnose', 'Benchmark', 'Lasttest', 'Wartung', 'Optimierung', 'Sensoren')
    }
    It 'entspricht den Dateien Vertrag.psd1' {
        foreach ($c in $contracts) {
            $f = Join-Path $global:MinibenchSrcRoot ('Module/{0}/Vertrag.psd1' -f $c.Name)
            $d = Import-PowerShellDataFile -LiteralPath $f
            (ConvertTo-SortedJson $d) | Should -BeExactly (ConvertTo-SortedJson $c)
        }
    }
    It 'Vertrag <Name> ist gültig' -ForEach @(
        @{ Name = 'Diagnose' }, @{ Name = 'Benchmark' }, @{ Name = 'Lasttest' }, @{ Name = 'Wartung' }, @{ Name = 'Optimierung' }, @{ Name = 'Sensoren' }
    ) {
        $c = MinibenchTest\Get-ModuleContract $Name
        MinibenchTest\Test-ModuleContract $c $params | Should -BeNullOrEmpty
    }
    It 'ordnet jeden Skriptparameter genau einem Modul oder den allgemeinen zu' {
        $owned = @($contracts | ForEach-Object { $_.Parameter }) + $general
        foreach ($p in $params) { @($owned | Where-Object { $_ -eq $p }).Count | Should -Be 1 -Because "Parameter $p" }
    }
    It 'hat für jedes Modul eine eigene Ablaufdatei' {
        foreach ($c in $contracts) { Join-Path $global:MinibenchSrcRoot ('Module/{0}/Ablauf.ps1' -f $c.Name) | Should -Exist }
    }
    It 'schreibt nur Datenbankfelder, die Kern oder Verträge kennen' {
        $fn = (Get-TopFunctions)['Save-DbEntry']
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($fn, [ref]$null, [ref]$null)
        $ht = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.AssignmentStatementAst] -and $a.Left.Extent.Text -eq '$o' }, $true)
        $keys = @($ht.Right.Expression.Child.KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text })
        if (-not $keys.Count) { $keys = @($ht.Find({ param($a) $a -is [System.Management.Automation.Language.HashtableAst] }, $true).KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text }) }
        $known = @(Get-ModuleVar 'ContractCoreDbFields') + @($contracts | ForEach-Object { $_.Datenbankfelder })
        $keys.Count | Should -BeGreaterThan 5
        foreach ($k in $keys) { $known | Should -Contain $k -Because "Feld $k in Save-DbEntry" }
    }
}

Describe 'Prüfung der Verträge erkennt Fehler' {
    BeforeEach {
        $base = @{
            Vertrag = 1; Name = 'Probe'; Seite = @{ Titel = 'Probe'; Kurz = 'Test' }; Admin = $true; Risiko = 'Aendern'; Neustart = 'nie'
            Parameter = @(); Datenbankfelder = @()
            Schritte = @(@{ Key = 'A'; Typ = 'Massnahme'; Titel = 'A'; Text = 'A'; Minuten = 1; Vorauswahl = $false; Ueblich = $false; Risiko = 'Aendern'; Neustart = 'nie'; Rueckgaengig = 'Protokoll' })
        }
    }
    It 'akzeptiert einen korrekten Vertrag' { MinibenchTest\Test-ModuleContract $base | Should -BeNullOrEmpty }
    It 'Ändern ohne Protokoll' { $base.Schritte[0].Rueckgaengig = 'keins'; (MinibenchTest\Test-ModuleContract $base) -join ' ' | Should -Match 'Protokoll' }
    It 'Eingriff mit Protokoll' { $base.Schritte[0].Risiko = 'Eingriff'; $base.Risiko = 'Eingriff'; (MinibenchTest\Test-ModuleContract $base) -join ' ' | Should -Match 'Eingriff' }
    It 'Modulrisiko passt nicht zu den Schritten' { $base.Risiko = 'Lesen'; (MinibenchTest\Test-ModuleContract $base) -join ' ' | Should -Match 'höchsten Stufe' }
    It 'unbekannte Risikostufe' { $base.Schritte[0].Risiko = 'Gefaehrlich'; (MinibenchTest\Test-ModuleContract $base) -join ' ' | Should -Match 'unbekannte Risikostufe' }
    It 'doppelter Schritt' { $base.Schritte = @($base.Schritte[0], $base.Schritte[0].Clone()); (MinibenchTest\Test-ModuleContract $base) -join ' ' | Should -Match 'doppelt' }
    It 'unbekannter Parameter' { $base.Parameter = @('GibtEsNicht'); (MinibenchTest\Test-ModuleContract $base @('Module')) -join ' ' | Should -Match 'GibtEsNicht' }
    It 'Kernfeld als Moduldatenbankfeld' { $base.Datenbankfelder = @('Computer'); (MinibenchTest\Test-ModuleContract $base) -join ' ' | Should -Match 'Kern' }
    It 'fehlendes Feld' { $base.Remove('Seite'); (MinibenchTest\Test-ModuleContract $base) -join ' ' | Should -Match 'Seite' }
    It 'Text mit senkrechtem Strich' { $base.Schritte[0].Text = 'A|B'; (MinibenchTest\Test-ModuleContract $base) -join ' ' | Should -Match '\|' }
}

Describe 'Schneller Modus im Modulvertrag' {
    It 'Diagnose: Updatesuche, Defender, SMART-Start und Energieanalyse parallel, Messungen exklusiv, Energieanalyse nach Defender' {
        $s = @{}; foreach ($x in (MinibenchTest\Get-ModuleContract 'Diagnose').Schritte) { $s[$x.Key] = $x }
        foreach ($k in 'Updatesuche', 'Defender', 'SmartLang', 'Energieanalyse') { $s[$k].Parallel | Should -BeTrue -Because $k }
        foreach ($k in 'RamTest', 'Netzwerk') { $s[$k].Exklusiv | Should -BeTrue -Because $k }
        $s['Energieanalyse'].Nach | Should -Contain 'Defender'
    }
    It 'Benchmark und Lasttest: jeder Schritt außer Optionen exklusiv (Messungen nie parallel zu anderer Last)' {
        foreach ($n in 'Benchmark', 'Lasttest') {
            foreach ($x in (MinibenchTest\Get-ModuleContract $n).Schritte) { if ($x.Typ -ne 'Option') { $x.Exklusiv | Should -BeTrue -Because ('{0}/{1}' -f $n, $x.Key) } }
        }
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
}

Describe 'Diagnose ohne CPU-Stabilitätstest (CPU-Last nur im Lasttest)' {
    It 'Vertrag, Skriptparameter und Skript kennen CpuTest und CpuStressSeconds nicht' {
        $d = MinibenchTest\Get-ModuleContract 'Diagnose'
        @($d.Schritte | Where-Object { $_.Key -eq 'CpuTest' }).Count | Should -Be 0
        $d.Parameter | Should -Not -Contain 'CpuStressSeconds'
        $params | Should -Not -Contain 'CpuStressSeconds'
        (Get-MinibenchBuild).Text | Should -Not -Match '\$script:Opt\[.CpuTest.\]'
        (Get-MinibenchBuild).Text | Should -Not -Match 'CpuStressSeconds'
    }
    It 'der Lasttest hat die CPU-Last als exklusiven Schritt' {
        $c = @((MinibenchTest\Get-ModuleContract 'Lasttest').Schritte | Where-Object { $_.Key -eq 'CPU' })
        $c.Count | Should -Be 1
        $c[0].Exklusiv | Should -BeTrue
    }
    It 'der Ablauf der Diagnose startet keine CPU-Last' {
        $t = Get-SrcText 'Module/Diagnose/Ablauf.ps1'
        $t | Should -Not -Match 'Start-LoadJob'
        $t | Should -Not -Match '\[DiagCpu\]::RunAsync'
    }
}

Describe 'Modulauswahl' {
    It 'übersetzt Namen unabhängig von Groß- und Kleinschreibung und meldet Unbekanntes' {
        $r = MinibenchTest\Resolve-ModuleList 'diagnose, REPARATUR;Foo;Diagnose'
        $r.Module | Should -Be @('Diagnose', 'Wartung')
        $r.Unbekannt | Should -Be @('Foo')
    }
    It 'leere Auswahl ergibt nichts' { (MinibenchTest\Resolve-ModuleList '').Module | Should -BeNullOrEmpty }
}

Describe 'Sensoren im Vertrag' {
    It 'der PawnIO-Treiber ist ein Eingriff mit Hinweis und eigenem Schalter' {
        $t = MinibenchTest\Get-ModuleStep 'Sensoren' 'Treiber'
        $t.Risiko | Should -Be 'Eingriff'; $t.Rueckgaengig | Should -Be 'Hinweis'; $t.Schalter | Should -Be 'SensorTreiber'
    }
    It 'Live-Ansicht und Werkzeuge holen verändern nichts am PC' {
        foreach ($k in 'Live', 'Werkzeuge') { (MinibenchTest\Get-ModuleStep 'Sensoren' $k).Risiko | Should -Be 'Lesen' }
    }
    It 'Lasttest kennt die Abbruchschwellen' {
        (MinibenchTest\Get-ModuleContract 'Lasttest').Parameter | Should -Contain 'LastAbbruchCpu'
        (MinibenchTest\Get-ModuleContract 'Lasttest').Parameter | Should -Contain 'LastAbbruchGpu'
    }
}

Describe 'Abgleich mit der Oberfläche' {
    It 'Navigation hat die Seite Sensoren live aus dem Vertrag' {
        $gui | Should -Match 'ModNav\("Sensoren"'
        $gui | Should -Match 'pages.Add\(BuildSensorPage\(\)\)'
    }
    It 'Abbruchschwellen der Seite Lasttest versteht das Skript' {
        $g = [regex]::Match($gui, 'cmbLAbortGpu = Combo\(\d+, new string\[\] \{([^}]*)\}').Groups[1].Value
        $c = [regex]::Match($gui, 'cmbLAbortCpu = Combo\(\d+, new string\[\] \{([^}]*)\}').Groups[1].Value
        $c | Should -Match 'automatisch'; $g | Should -Match 'aus'
        foreach ($o in @([regex]::Matches($c + ',' + $g, '"(\d+) °C"') | ForEach-Object { $_.Groups[1].Value })) { [int]$o | Should -BeGreaterOrEqual 40; [int]$o | Should -BeLessOrEqual 125 }
    }
    It 'Prüfungen der Seite Diagnose = Prüfungen im Vertrag' {
        Get-CsArray 'diagKeys' | Should -Be @((MinibenchTest\Get-ModuleContract 'Diagnose').Schritte | Where-Object { $_.Typ -eq 'Pruefung' } | ForEach-Object { $_.Key })
    }
    It 'Texte, Voreinstellungen und Zeitschätzung der Seite Diagnose haben je Prüfung genau einen Wert' {
        $n = @((MinibenchTest\Get-ModuleContract 'Diagnose').Schritte | Where-Object { $_.Typ -eq 'Pruefung' }).Count
        @(Get-CsArray 'diagText').Count | Should -Be $n
        foreach ($p in 'voll', 'schnell', 'test', 'none') {
            ($gui -match ('bool\[\] {0} = new bool\[\] \{{([^}}]+)\}};' -f $p)) | Should -BeTrue -Because $p
            @($Matches[1] -split ',').Count | Should -Be $n -Because $p
        }
        ($gui -match 'int\[\] add = new int\[\] \{([^}]+)\};') | Should -BeTrue
        @($Matches[1] -split ',').Count | Should -Be $n
    }
    It 'feste Plätze der Seite Diagnose zeigen auf die passenden Prüfungen des Vertrags' {
        $keys = @(Get-CsArray 'diagKeys')
        $steps = @{}; foreach ($x in (MinibenchTest\Get-ModuleContract 'Diagnose').Schritte) { $steps[$x.Key] = $x }
        $idx = @([regex]::Matches($gui, 'diagChk\[(\d+)\]') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
        $idx.Count | Should -BeGreaterThan 0
        foreach ($i in $idx) { $i | Should -BeLessThan $keys.Count }
        # schneller Modus: die Zeitschätzung zieht nur parallel laufende Prüfungen ab
        $fast = @($gui -split "`r?`n" | Where-Object { $_ -match 'chkFast\.Checked' -and $_ -match 'diagChk\[\d+\]' })
        $fast.Count | Should -BeGreaterThan 0
        foreach ($i in @([regex]::Matches(($fast -join ' '), 'diagChk\[(\d+)\]') | ForEach-Object { [int]$_.Groups[1].Value })) { $steps[$keys[$i]].Parallel | Should -BeTrue -Because $keys[$i] }
        # SMART-Höchstdauer nur mit dem SMART-Langtest
        ($gui -match 'diagChk\[(\d+)\]\.Checked\) a\.Append\(" -SmartTimeoutMinutes "\)') | Should -BeTrue
        $keys[[int]$Matches[1]] | Should -Be 'SmartLang'
    }
    It 'Messungen der Seite Benchmark = Schritte im Vertrag' {
        Get-CsArray 'benchKeys' | Should -Be @((MinibenchTest\Get-ModuleContract 'Benchmark').Schritte | Where-Object { $_.Typ -eq 'Messung' } | ForEach-Object { $_.Key })
    }
    It 'Optionen mit Schalter werden von der Oberfläche übergeben' {
        foreach ($s in @(foreach ($m in 'Diagnose', 'Benchmark', 'Lasttest', 'Wartung', 'Optimierung', 'Sensoren') { (MinibenchTest\Get-ModuleContract $m).Schritte | Where-Object { $_.Typ -eq 'Option' -and $_.Schalter } })) {
            $gui | Should -Match ([regex]::Escape('" -' + $s.Schalter)) -Because $s.Key
        }
    }
    It 'Oberfläche übergibt SMART-Höchstdauer und Werkzeug-Einstellung' {
        $gui | Should -Match '-SmartTimeoutMinutes '
        $gui | Should -Match '-WerkzeugeBehalten '
        $gui | Should -Match '"Minibench-Geraete/1"'
    }
    It 'Ersatzliste der Seite Wartung = Maßnahmen im Vertrag (Reihenfolge und Texte)' {
        $rep = (MinibenchTest\Get-ModuleContract 'Wartung').Schritte
        Get-CsArray 'repKeys' | Should -Be @($rep | ForEach-Object { $_.Key })
        Get-CsArray 'repText' | Should -Be @($rep | ForEach-Object { $_.Text })
    }
    It 'Kurzfassung für die Oberfläche hat feste Spaltenzahl' {
        foreach ($l in (MinibenchTest\Get-ContractGuiLines)) {
            $n = ($l -split '\|').Count
            if ($l.StartsWith('M|')) { $n | Should -Be 7 } else { $n | Should -Be 12 }
        }
    }
    It 'jede Maßnahme der Wartung hat eine Gruppe aus der Liste' {
        $validGroups = @(
            'Systemdateien und Komponentenspeicher',
            'Bereinigung und Speicherplatz',
            'Windows Update, Netzwerk und Zeit',
            'Dienste, Geräte und Energie'
        )
        $rep = (MinibenchTest\Get-ModuleContract 'Wartung').Schritte
        foreach ($s in $rep) {
            $validGroups | Should -Contain $s.Gruppe -Because "Schritt $($s.Key) hat Gruppe $($s.Gruppe)"
        }
    }
    It 'Reparaturreihenfolge im Skript kommt aus dem Vertrag' {
        (Get-PartText 'Kern\Grundgeruest.ps1') | Should -Match "RepOrder\s+=\s+@\(\(Get-ModuleContract 'Reparatur'\)"
    }
}
