# Version 2.9: Phasen 0 und 1 der Roadmap.
# Phase 0: ARM64-Erkennung und Warnung, High-DPI-Manifest (PerMonitorV2), src-Bereinigung,
#          Modularisierung von DiagGui.cs in Teilklassen.
# Phase 1: Neugewichtung im Gesamtbild (CPU 2x, GPU 2x, GPU-Rendertest FPS 3x),
#          Preset "Leos Empfehlung", Modul Wartung (22 Schritte, Bereinigung übernommen),
#          Vergleichsseite: editierbarer Anzeigename und sortierbare Tabellenspalten.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $global:V29Src = $global:MinibenchSrcRoot
    $global:V29Gui = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Oberflaeche/DiagGui.cs'))
    $global:V29Ver = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Oberflaeche/Versionen.cs'))
    $global:V29Kat = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Module/Optimierung/Katalog.psd1'))
    $global:V29Cmd = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'))
}

Describe 'Phase 0: High-DPI und Anwendungsmanifest' {
    It 'Bauen.cmd enthält Per-Monitor V2 DPI-Awareness im Manifest' {
        $global:V29Cmd | Should -Match '<dpiAwareness[^>]*>PerMonitorV2,\s*PerMonitor</dpiAwareness>'
        $global:V29Cmd | Should -Match '<dpiAware[^>]*>true/pm</dpiAware>'
    }
}

Describe 'Phase 0: ARM64-Erkennung und Warnhinweis' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Sensoren.ps1' -Functions 'Test-IsArm64'
    }
    It 'Test-IsArm64 prüft Umgebungsvariablen und Systemdaten' {
        { MinibenchTest\Test-IsArm64 } | Should -Not -Throw
    }
    It 'Sensoren.ps1 setzt LhmGrund = ARM64 und enthält den Warnhinweis' {
        $sens = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Kern/Sensoren.ps1'))
        $sens | Should -Match '\$s\.LhmGrund = ''ARM64'''
        $sens | Should -Match 'ARM64-Architektur erkannt: Tiefgehende Kern- und Mainboard-Sensoren erfordern x86/x64-Treiber und stehen nur eingeschränkt zur Verfügung'
    }
    It 'Diagnose meldet ARM64 als Befund' {
        $diag = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Module/Diagnose/Ablauf.ps1'))
        $diag | Should -Match 'Add-Finding INFO ''Sensoren'' ''ARM64-Architektur erkannt: Tiefgehende Kern- und Mainboard-Sensoren erfordern x86/x64-Treiber und stehen nur eingeschränkt zur Verfügung\.'''
    }
}

Describe 'Phase 0: Modularisierung der C#-Oberfläche' {
    It 'Teilklassen existieren und sind in Oberflaeche.ps1 eingebunden' {
        $parts = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs')
        $of = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Oberflaeche/Oberflaeche.ps1'))
        foreach ($p in $parts) {
            Test-Path (Join-Path $global:V29Src ('Oberflaeche/' + $p)) | Should -BeTrue -Because $p
            $of | Should -Match ('#>> EINBINDEN Oberflaeche\\' + [regex]::Escape($p)) -Because $p
        }
    }
    It 'Oberfläche lässt sich als Gesamtheit fehlerfrei kompilieren' {
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGui29_' + [guid]::NewGuid().ToString('N') + '.dll')
        try {
            if ($env:OS -eq 'Windows_NT') {
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

Describe 'Phase 0: Vollständigkeit der Quelltextdateien' {
    It 'jede ps1- und cs-Datei in src ist im Bauplan oder in Einbindungsanweisungen gelistet' {
        $bp = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Bauplan.txt'))
        $all = Get-ChildItem $global:V29Src -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.cs', '.psd1' }
        $known = @(
            'src\00_Kopf.ps1', 'src\Bauplan.txt', 'src\Zusammenbau.ps1',
            'src\Kern\Grafiktest.cs', 'src\Kern\Sensoren.cs', 'src\Kern\Testroutinen.cs',
            'src\Oberflaeche\DiagGui.cs', 'src\Oberflaeche\DiagGui_Steuerelemente.cs',
            'src\Oberflaeche\DiagGui_Modelle.cs', 'src\Oberflaeche\DiagGui_Vergleich.cs',
            'src\Oberflaeche\DiagGui_Seiten.cs', 'src\Oberflaeche\Start.cs', 'src\Oberflaeche\Versionen.cs'
        )
        foreach ($f in $all) {
            $rel = $f.FullName.Substring($global:V29Src.Length + 1)
            $isModuleContract = $rel -match '^Module\\[^\\]+\\Vertrag\.psd1$'
            $isKatalog = $rel -match 'Katalog\.psd1$'
            $inBauplan = $bp -match [regex]::Escape($rel)
            $inKnown = $known -contains ('src\' + $rel)
            ($inBauplan -or $isModuleContract -or $isKatalog -or $inKnown) | Should -BeTrue -Because $rel
        }
    }
}

Describe 'Phase 1: Neugewichtung im Gesamtbild' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Kodierung.ps1', 'Kern\Version.ps1', 'Kern\Modulvertrag.ps1', 'Kern\Referenz_Vergleich.ps1' `
            -Functions 'Get-GeoMean', 'Get-BenchOverall', 'Get-BenchGroup'
    }
    It 'Get-GeoMean unterstützt Gewichtungen' {
        $u = MinibenchTest\Get-GeoMean @(100, 100, 100)
        $u | Should -Be 100
        $w = MinibenchTest\Get-GeoMean @(100, 400) @(2.0, 1.0)
        $w | Should -Be 159
    }
    It 'Referenz_Vergleich gewichtet GPU-Rendertest dreifach' {
        $rv = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Kern/Referenz_Vergleich.ps1'))
        $rv | Should -Match 'REND\|RPKT.+3\.0.+1\.0'
    }
    It 'Get-BenchOverall gewichtet CPU und GPU doppelt (2x) gegenüber RAM und Laufwerken (1x)' {
        $rv = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Kern/Referenz_Vergleich.ps1'))
        $rv | Should -Match '\$weights\s*=\s*@\{\s*''CPU''\s*=\s*2\.0;\s*''GPU''\s*=\s*2\.0;\s*''RAM''\s*=\s*1\.0;\s*''Laufwerke''\s*=\s*1\.0\s*\}'
    }
}

Describe 'Phase 1: Preset Leos Empfehlung' {
    It 'ist als Voreinstellung definiert und aktiv' {
        $global:V29Gui | Should -Match '"Leos Empfehlung"'
        $global:V29Gui | Should -Match 'ApplyOptPreset\("S"\)'
        $global:V29Gui | Should -Match 'string name = key == "M" \? "Minimal" : key == "S" \? "Leos Empfehlung"'
    }
    It 'DiagGui.cs enthält defaultLeoEmpfehlung und GetLeoEmpfehlungIds' {
        $global:V29Gui | Should -Match 'defaultLeoEmpfehlung\s*=\s*new string\[\]'
        $global:V29Gui | Should -Match 'GetLeoEmpfehlungIds\(\)'
        $global:V29Gui | Should -Match 'key == "S" \? GetLeoEmpfehlungIds\(\) : null'
    }
}

Describe 'Hotfix 2.9: Rendertest FPS-Skalierung' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Kodierung.ps1', 'Kern\Berichtshilfen.ps1', 'Kern\Referenz_Vergleich.ps1' `
            -Functions 'New-MultiLineSvg', 'New-LineSvg', 'Get-ChartScale', 'ConvertTo-HtmlText'
    }
    It 'New-MultiLineSvg mit Einheit Bilder/s beginnt bei Y = 0' {
        $pts = @(
            [pscustomobject]@{ T = 0; V = 39.5 },
            [pscustomobject]@{ T = 1; V = 41.2 },
            [pscustomobject]@{ T = 2; V = 40.8 }
        )
        $svg = MinibenchTest\New-MultiLineSvg @(@{ Name = 'GPU'; Cls = 's2'; Points = $pts }) 'Bilder/s'
        $svg | Should -Match '>0</text>'
    }
    It 'New-LineSvg mit Einheit Bilder/s beginnt bei Y = 0' {
        $pts = @(
            [pscustomobject]@{ T = 0; V = 39.5 },
            [pscustomobject]@{ T = 1; V = 41.2 }
        )
        $svg = MinibenchTest\New-LineSvg $pts 'Bilder/s'
        $svg | Should -Match '>0</text>'
    }
    It 'SensorChart in DiagGui_Steuerelemente setzt Nulllinie für Bilder/s' {
        $ctrl = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Oberflaeche/DiagGui_Steuerelemente.cs'))
        $ctrl | Should -Match 'if \(unit == "Bilder/s"\) lo = 0;'
    }
}

Describe 'Phase 1: Modul Wartung und Katalogbereinigung' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Aenderungen.ps1', 'Kern\Modulvertrag.ps1', 'Module\Optimierung\Funktionen.ps1' `
            -Functions 'Get-OptCatalog', 'Get-OptEntries', 'Get-OptCategories', 'Get-OptEntry'
    }
    It 'Modulvertrag Wartung enthält 22 Schritte' {
        $v = Import-PowerShellDataFile (Join-Path $global:V29Src 'Module/Wartung/Vertrag.psd1')
        $v.Name | Should -Be 'Wartung'
        @($v.Schritte).Count | Should -Be 22
    }
    It 'Wartung Ablauf.ps1 enthält alle 22 Schlüssel' {
        $ablauf = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Module/Wartung/Ablauf.ps1'))
        $v = Import-PowerShellDataFile (Join-Path $global:V29Src 'Module/Wartung/Vertrag.psd1')
        foreach ($s in $v.Schritte) {
            $ablauf | Should -Match ("'" + $s.Key + "'") -Because $s.Key
        }
    }
    It 'Katalog der Optimierung enthält keine Kategorie Bereinigung mehr' {
        $e = @(MinibenchTest\Get-OptEntries)
        $kats = @($e | ForEach-Object { $_.Kat })
        $kats | Should -Not -Contain 'Bereinigung'
        $e.Count | Should -Be 151
    }
    It 'Kommandozeile unterstützt Wartung und Reparaturen' {
        $kopf = [IO.File]::ReadAllText((Join-Path $global:V29Src '00_Kopf.ps1'))
        $kopf | Should -Match '\[string\]\$Wartung'
        $kopf | Should -Match '\[string\]\$Reparaturen'
        $gg = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Kern/Grundgeruest.ps1'))
        $gg | Should -Match '\$Wartung \}\s*else\s*\{\s*\$Reparaturen'
    }
}

Describe 'Phase 1: Vergleichsseite (Systemname editierbar & Spaltensortierung)' {
    It 'DiagGui_Vergleich.cs enthält RenameSelectedEntry und PromptInput' {
        $vg = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Oberflaeche/DiagGui_Vergleich.cs'))
        $vg | Should -Match 'void RenameSelectedEntry\(\)'
        $vg | Should -Match 'string PromptInput\('
        $vg | Should -Match 'Tip\(btnRename,'
    }
    It 'DiagGui_Vergleich.cs enthält DbItemComparer und OnDbColumnClick' {
        $vg = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Oberflaeche/DiagGui_Vergleich.cs'))
        $vg | Should -Match 'class DbItemComparer\s*:\s*System\.Collections\.IComparer'
        $vg | Should -Match 'void OnDbColumnClick\(object sender, ColumnClickEventArgs e\)'
        $vg | Should -Match 'lvDb\.ColumnClick \+= OnDbColumnClick'
    }
    It 'DbEntry enthält DisplayName und OverallScore' {
        $md = [IO.File]::ReadAllText((Join-Path $global:V29Src 'Oberflaeche/DiagGui_Modelle.cs'))
        $md | Should -Match 'public string DisplayName'
        $md | Should -Match 'public double OverallScore'
    }
}