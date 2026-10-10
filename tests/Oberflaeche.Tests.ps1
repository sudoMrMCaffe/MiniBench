# Oberfläche (src/Oberflaeche, WinForms in C# 5): Übersetzung, Selbsttest der Steuerelemente und Hilfen, Verträge mit dem
# Arbeitsprozess und Projektregeln (Hinweise beim Überfahren).
#
# Die Oberfläche wird je Testsitzung genau einmal übersetzt (Get-GuiUebersetzung in Hilfen.ps1), zusammen mit
# tests/Daten/Oberflaeche/GuiSelbsttest.cs. Der Selbsttest läuft als eigene exe; in dieser Sitzung werden keine Typen geladen.
# Neue Verhaltensprüfungen der Oberfläche gehören in GuiSelbsttest.cs und hier in die Liste der Fälle.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $script:Gui = @(Get-GuiQuellen | ForEach-Object { [IO.File]::ReadAllText($_, [Text.Encoding]::UTF8) }) -join "`n"
}

Describe 'Übersetzung (C# 5)' {
    It 'jede cs-Datei in src/Oberflaeche ist in Oberflaeche.ps1 eingebunden' {
        $dateien = @(Get-ChildItem (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') -Filter '*.cs' | ForEach-Object { $_.Name } | Sort-Object)
        $eingebunden = @(Get-GuiQuellen | ForEach-Object { [IO.Path]::GetFileName($_) } | Sort-Object)
        ($eingebunden -join ',') | Should -Be ($dateien -join ',')
        [IO.Path]::GetFileName(@(Get-GuiQuellen)[0]) | Should -Be 'DiagGui.cs' -Because 'DiagGui.cs trägt die using-Zeilen für alle Teile'
    }
    It 'die Oberfläche lässt sich als Ganzes übersetzen' {
        $u = Get-GuiUebersetzung
        if (-not $u.Ok -and $u.Meldung -eq 'kein C#-Compiler verfügbar') { Set-ItResult -Skipped -Because $u.Meldung; return }
        $u.Ok | Should -BeTrue -Because $u.Meldung
    }
}

Describe 'Selbsttest der Oberfläche' {
    It '<Fall>' -ForEach @(
        @{ Fall = 'UI.Skalierung' }
        @{ Fall = 'UI.Farbschema' }
        @{ Fall = 'ToggleSwitch' }
        @{ Fall = 'FluentCard' }
        @{ Fall = 'Hinweise.Umbruch' }
        @{ Fall = 'Grafikauswahl.Abgleich' }
        @{ Fall = 'Softwarepakete.Auswahl' }
        @{ Fall = 'Softwarepakete.Ereignisse' }
        @{ Fall = 'Datenbank.Referenzen' }
        @{ Fall = 'Aenderungen.Softwarepaket' }
        @{ Fall = 'Netzlaufwerk.Pfad' }
        @{ Fall = 'Netzlaufwerk.Konfiguration' }
        @{ Fall = 'Netzlaufwerk.Ergebnis' }
        @{ Fall = 'Wartung.Vertragszeile' }
        @{ Fall = 'Dialog.Farbschema' }
    ) {
        Assert-GuiSelbsttest $Fall
    }
    It 'jeder Fall des Selbsttests wird hier geprüft' {
        $u = Get-GuiUebersetzung
        if (-not $u.Ok) { Set-ItResult -Skipped -Because 'Oberfläche nicht übersetzt'; return }
        $m = Get-GuiSelbsttest
        if ($null -eq $m) { Set-ItResult -Skipped -Because 'Selbsttest braucht Windows oder eine Anzeige'; return }
        $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Oberflaeche.Tests.ps1'), [Text.Encoding]::UTF8)
        $hier = @([regex]::Matches($text, "@\{ Fall = '([^']+)' \}") | ForEach-Object { $_.Groups[1].Value })
        $m.Count | Should -BeGreaterThan 0
        foreach ($k in $m.Keys) { $hier | Should -Contain $k }
    }
}

Describe 'Verträge zwischen Oberfläche und Arbeitsprozess' {
    It 'jeder Parameter, den die Oberfläche an LeosMinibench.ps1 übergibt, gibt es im Skript' {
        $params = Get-ScriptParameters
        $fremd = @('NoProfile', 'ExecutionPolicy', 'File', 'Command')   # Parameter von powershell.exe selbst
        # Versionen.cs ist Historientext, keine Befehlszeile
        $code = @(Get-GuiQuellen | Where-Object { [IO.Path]::GetFileName($_) -ne 'Versionen.cs' } | ForEach-Object { [IO.File]::ReadAllText($_, [Text.Encoding]::UTF8) }) -join "`n"
        $benutzt = @(foreach ($lit in [regex]::Matches($code, '"(?:[^"\\\r\n]|\\.)*"')) {
                foreach ($m in [regex]::Matches($lit.Value, '(?<=[\s"])-([A-Z][A-Za-z]+)\b')) { $m.Groups[1].Value }
            }) | Sort-Object -Unique
        $benutzt.Count | Should -BeGreaterThan 20
        foreach ($p in $benutzt) { if ($fremd -notcontains $p) { $params | Should -Contain $p -Because ('die Oberfläche übergibt -' + $p) } }
    }
    It 'Rendertest-Einstellungen werden zwischen Benchmark und Lasttest in beide Richtungen abgeglichen' {
        # das Verhalten von CopySelection prüft der Selbsttest (Grafikauswahl.Abgleich); hier die Verdrahtung beider Seiten
        $script:Gui | Should -Match 'ComboBox\[\] GpuCombosBench\(\) \{ return new ComboBox\[\] \{ cmbGpuRes, cmbGpuShow, cmbGpuSel \}; \}'
        $script:Gui | Should -Match 'ComboBox\[\] GpuCombosLast\(\) \{ return new ComboBox\[\] \{ cmbLGpuRes, cmbLGpuShow, cmbLGpuSel \}; \}'
        $script:Gui | Should -Match 'sync1 = delegate \{[^\r\n]*CopySelection\(GpuCombosBench\(\), GpuCombosLast\(\)\)'
        $script:Gui | Should -Match 'sync2 = delegate \{[^\r\n]*CopySelection\(GpuCombosLast\(\), GpuCombosBench\(\)\)'
        $script:Gui | Should -Match 'cmbLGpuRes\.SelectedIndexChanged \+= sync2; cmbLGpuShow\.SelectedIndexChanged \+= sync2; cmbLGpuSel\.SelectedIndexChanged \+= sync2;'
    }
    It 'Softwarepakete installiert der Arbeitsprozess, die Oberfläche startet winget nicht selbst' {
        $script:Gui | Should -Match '-SoftwareInstallieren'
        $script:Gui | Should -Not -Match 'install --id'
        $script:Gui | Should -Match '"@@PAKET\|"'
    }
    It 'jede gespeicherte Voreinstellung wird beim Laden wieder angewendet' {
        $put = @([regex]::Matches($script:Gui, 'Put(?:C|Cb)\(d, "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        $get = @([regex]::Matches($script:Gui, 'Get(?:C|Cb)\(d, "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        $put.Count | Should -BeGreaterThan 15
        foreach ($k in $put) { $get | Should -Contain $k }
    }
    It 'jede Methode mit new Form() ruft UI.ThemeDialog auf' {
        $csDateien = Get-ChildItem -Path (Join-Path $PSScriptRoot '..\src\Oberflaeche') -Filter '*.cs'
        $methodenMitForm = 0
        foreach ($datei in $csDateien) {
            $text = [IO.File]::ReadAllText($datei.FullName, [Text.Encoding]::UTF8)
            $mMatches = [regex]::Matches($text, '(?m)^\s*(?:public|private|internal|protected|static|\s)*\b[\w<>\[\]]+\s+(\w+)\s*\([^)]*\)\s*\{')
            foreach ($m in $mMatches) {
                $idx = $m.Index + $m.Length
                $depth = 1
                while ($depth -gt 0 -and $idx -lt $text.Length) {
                    if ($text[$idx] -eq '{') { $depth++ }
                    elseif ($text[$idx] -eq '}') { $depth-- }
                    $idx++
                }
                $body = $text.Substring($m.Index, $idx - $m.Index)
                if ($body -match 'new Form\(') {
                    $methodenMitForm++
                    $body | Should -Match 'UI\.ThemeDialog\(' -Because "$($m.Groups[1].Value) in $($datei.Name) erzeugt eine Form und muss UI.ThemeDialog aufrufen"
                }
            }
        }
        $methodenMitForm | Should -BeGreaterOrEqual 5
    }
}

Describe 'Projektregeln der Oberfläche' {
    It 'jedes Bedienelement hat einen Hinweis beim Überfahren (Tip)' {
        # Felder der Oberfläche mit Bedienelementen. Abgedeckt ist ein Feld durch Tip(feld, ...), Tip(feld[...], ...) oder
        # eine foreach-Liste direkt vor Tip(...). Ausnahmen: Teile eigener Steuerelemente (die Karte trägt den Hinweis),
        # das Protokollfeld und die nicht angezeigte Vergleichsliste.
        $ausnahmen = @('actionButton', 'secondaryButton', 'toggle', 'txtLog', 'clbCompare')
        $types = 'CheckBox|ComboBox|Button|LinkLabel|TextBox|RadioButton|ToggleSwitch|FluentCard|NumericUpDown|TrackBar|CheckedListBox|DarkComboBox'
        $felder = @([regex]::Matches($script:Gui, "(?m)^    (?:public |private |internal |static |readonly )*(?:$types)(?:\[\])?\s+([\w\s,]+);") |
            ForEach-Object { $_.Groups[1].Value -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\w+$' } | Sort-Object -Unique)
        $felder.Count | Should -BeGreaterThan 50
        $mitTip = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($m in [regex]::Matches($script:Gui, 'Tip\(\s*(\w+)\s*[,\[]')) { [void]$mitTip.Add($m.Groups[1].Value) }
        foreach ($m in [regex]::Matches($script:Gui, 'foreach \(\w+ (\w+) in new \w+\[\] \{([^}]+)\}\)\s*Tip\(\s*(\w+)\s*,')) {
            if ($m.Groups[1].Value -eq $m.Groups[3].Value) { foreach ($n in $m.Groups[2].Value -split ',') { [void]$mitTip.Add($n.Trim()) } }
        }
        $ohne = @($felder | Where-Object { $ausnahmen -notcontains $_ -and -not $mitTip.Contains($_) })
        ($ohne -join ', ') | Should -BeNullOrEmpty
    }
    It 'Hinweise ohne Spiegelstrich-Aufzählung' {
        foreach ($m in [regex]::Matches($script:Gui, 'Tip\([^,]+, "([^"]+)"')) { $m.Groups[1].Value | Should -Not -Match '(^|\\n)\s*[-–] ' }
    }
}
