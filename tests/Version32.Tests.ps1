# Version 3.2: Fluent 2 / Wintoys-Look, DWM-Rundungen, Segoe-Icons, ToggleSwitch, FluentCard, High-DPI und responsive Notebook-Skalierung

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $global:V32Src = $global:MinibenchSrcRoot
    $global:V32Gui = [IO.File]::ReadAllText((Join-Path $global:V32Src 'Oberflaeche/DiagGui.cs'))
    $global:V32Controls = [IO.File]::ReadAllText((Join-Path $global:V32Src 'Oberflaeche/DiagGui_Steuerelemente.cs'))
    $global:V32Pages = [IO.File]::ReadAllText((Join-Path $global:V32Src 'Oberflaeche/DiagGui_Seiten.cs'))
    $global:V32Db = [IO.File]::ReadAllText((Join-Path $global:V32Src 'Oberflaeche/DiagGui_Vergleich.cs'))
    $global:V32Ver = [IO.File]::ReadAllText((Join-Path $global:V32Src 'Oberflaeche/Versionen.cs'))
    $global:V32Hist = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Doku/Versionshistorie.txt'))
}

Describe 'Version 3.2: Zentraler DPI-Helper & Windows 11 DWM-Integration' {
    It 'UI-Klasse enthält DpiScale, S(int) und SF(float)' {
        $global:V32Controls | Should -Match 'public\s+static\s+float\s+DpiScale'
        $global:V32Controls | Should -Match 'public\s+static\s+int\s+S\s*\(\s*int\s+px\s*\)'
        $global:V32Controls | Should -Match 'public\s+static\s+float\s+SF\s*\(\s*float\s+px\s*\)'
    }

    It 'UI.S und UI.SF berechnen Werte proportional zu DpiScale' {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $src = @($files | ForEach-Object { [IO.File]::ReadAllText($_) }) -join [Environment]::NewLine
        $refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
        Add-Type -TypeDefinition $src -ReferencedAssemblies $refs -IgnoreWarnings

        [UI]::DpiScale = [float]1.0
        [UI]::S(100) | Should -Be 100
        [UI]::SF(50.0) | Should -Be 50.0

        [UI]::DpiScale = [float]1.5
        [UI]::S(100) | Should -Be 150
        [UI]::S(74) | Should -Be 111
        [UI]::SF(10.0) | Should -Be 15.0

        [UI]::DpiScale = [float]2.0
        [UI]::S(100) | Should -Be 200
        [UI]::SF(10.0) | Should -Be 20.0

        [UI]::DpiScale = [float]1.0
    }

    It 'DiagGui nutzt DWMWA_WINDOW_CORNER_PREFERENCE für echte Windows 11-Fensterabrundung' {
        $global:V32Gui | Should -Match 'DWMWA_WINDOW_CORNER_PREFERENCE\s*=\s*33'
        $global:V32Gui | Should -Match 'DWMWCP_ROUND\s*=\s*2'
        $global:V32Gui | Should -Match 'DwmSetWindowAttribute'
    }

    It 'EnableDpi() nutzt SetProcessDpiAwarenessContext mit Fallback und ohne altes SetProcessDPIAware' {
        $global:V32Gui | Should -Match 'SetProcessDpiAwarenessContext'
        $global:V32Gui | Should -Match 'SetProcessDpiAwareness'
        $global:V32Gui | Should -Not -Match 'SetProcessDPIAware\\(\\)'
    }

    It 'Form berechnet Startgröße anhand des sichtbaren Arbeitsbereichs (Höhe 0.88)' {
        $global:V32Gui | Should -Match 'Screen\.FromPoint\(Cursor\.Position\)\.WorkingArea'
        $global:V32Gui | Should -Match 'Math\.Min\(UI\.S\(1120\)'
        $global:V32Gui | Should -Match 'Math\.Min\(UI\.S\(680\),\s*\(int\)\(workArea\.Height\s*\*\s*0\.88\)\)'
        $global:V32Gui | Should -Match 'MinimumSize\s*=\s*new\s+Size\(UI\.S\(860\),\s*UI\.S\(540\)\)'
    }
}

Describe 'Version 3.2: Fluent 2-Farbpalette & Segoe-Icons' {
    It 'UI-Farbpalette entspricht den Fluent 2-Vorgaben' {
        $global:V32Controls | Should -Match 'Color\.FromArgb\(249,\s*249,\s*251\)'
        $global:V32Controls | Should -Match 'Color\.FromArgb\(229,\s*231,\s*235\)'
        $global:V32Controls | Should -Match 'Color\.FromArgb\(0,\s*103,\s*192\)'
        $global:V32Controls | Should -Match 'Color\.FromArgb\(235,\s*243,\s*251\)'
        $global:V32Controls | Should -Match 'Color\.FromArgb\(28,\s*29,\s*31\)'
        $global:V32Controls | Should -Match 'Color\.FromArgb\(95,\s*99,\s*104\)'
    }

    It 'UI enthält Segoe Fluent Icons Fallback und Symbol-Konstanten' {
        $global:V32Controls | Should -Match 'Segoe Fluent Icons'
        $global:V32Controls | Should -Match 'Segoe MDL2 Assets'
        $global:V32Controls | Should -Match 'IcoCpu\s*=\s*"\\uE7F8"'
        $global:V32Controls | Should -Match 'IcoRam\s*=\s*"\\uE7F4"'
        $global:V32Controls | Should -Match 'IcoGpu\s*=\s*"\\uE790"'
        $global:V32Controls | Should -Match 'IcoDisk\s*=\s*"\\uEDA2"'
        $global:V32Controls | Should -Match 'IcoDiag\s*=\s*"\\uE9D9"'
        $global:V32Controls | Should -Match 'IcoWartung\s*=\s*"\\uE90F"'
        $global:V32Controls | Should -Match 'IcoDb\s*=\s*"\\uE81E"'
        $global:V32Controls | Should -Match 'IcoChg\s*=\s*"\\uE81C"'
    }
}

Describe 'Version 3.2: Moderne Steuerelemente (Wintoys-Look)' {
    It 'ToggleSwitch-Steuerelement existiert und steuert Checked / CheckedChanged' {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $src = @($files | ForEach-Object { [IO.File]::ReadAllText($_) }) -join [Environment]::NewLine
        $refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
        Add-Type -TypeDefinition $src -ReferencedAssemblies $refs -IgnoreWarnings

        $ts = New-Object ToggleSwitch
        $ts.Checked | Should -BeFalse
        $state = @{ fired = $false }
        $ts.add_CheckedChanged({ $state.fired = $true })
        $ts.Checked = $true
        $ts.Checked | Should -BeTrue
        $state.fired | Should -BeTrue
    }

    It 'FluentCard existiert und bettet ToggleSwitch ein' {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $src = @($files | ForEach-Object { [IO.File]::ReadAllText($_) }) -join [Environment]::NewLine
        $refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
        Add-Type -TypeDefinition $src -ReferencedAssemblies $refs -IgnoreWarnings

        $card = New-Object FluentCard('Testkarte', 'Beschreibung', [UI]::IcoDiag)
        $card.Title | Should -Be 'Testkarte'
        $card.Description | Should -Be 'Beschreibung'
        $card.Checked | Should -BeFalse
        $cardState = @{ fired = $false }
        $card.add_CheckedChanged({ $cardState.fired = $true })
        $card.Checked = $true
        $card.Checked | Should -BeTrue
        $cardState.fired | Should -BeTrue
    }

    It 'NavItem besitzt Segoe-Icon und Windows 11-Sidebar-Stil' {
        $global:V32Controls | Should -Match 'UI\.SF\(6\)'
        $global:V32Controls | Should -Match 'UI\.SF\(1\.5f\)'
        $global:V32Controls | Should -Match 'UI\.SymbolFont'
    }

    It 'StatCard und TabStrip sind im Fluent-Design umgesetzt' {
        $global:V32Controls | Should -Match 'UI\.SF\(8\)'
        $global:V32Controls | Should -Match 'barH\s*=\s*UI\.S\(2\)'
    }
}

Describe 'Version 3.2: Responsives Seiten-Layout & Tabellen' {
    It 'Versionen, Änderungen und Vergleich nutzen DockStyle.Fill' {
        $global:V32Pages | Should -Match 'rt\.Dock\s*=\s*DockStyle\.Fill'
        $global:V32Pages | Should -Match 'lvChg\.Dock\s*=\s*DockStyle\.Fill'
        $global:V32Db | Should -Match 'lvDb\.Dock\s*=\s*DockStyle\.Fill'
    }

    It 'Laufansicht verwendet skalierte Zeilenhöhe UI.S(34) und Balkenhöhe UI.S(8)' {
        $global:V32Gui | Should -Match 'rowHeight\.ImageSize\s*=\s*new\s+Size\(1,\s*UI\.S\(34\)\)'
        $global:V32Gui | Should -Match 'barH\s*=\s*UI\.S\(8\)'
        $global:V32Gui | Should -Match 'textW\s*=\s*UI\.S\(48\)'
    }
}

Describe 'Version 3.2: C# 5-Kompatibilität' {
    It 'Keine C# 6 Ausdruckskörper (=>) in den Oberflächen-Dateien' {
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        foreach ($f in $files) {
            $lines = [System.IO.File]::ReadAllLines($f)
            for ($i = 0; $i -lt $lines.Length; $i++) {
                $line = $lines[$i].Trim()
                if ($line.StartsWith('//') -or $line.StartsWith('*')) { continue }
                $line | Should -Not -Match '\)\s*=>' -Because ('C# 6 expression body in {0}:{1}' -f [IO.Path]::GetFileName($f), ($i + 1))
            }
        }
    }

    It 'Oberfläche lässt sich als Gesamtheit fehlerfrei kompilieren' {
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGui32_' + [guid]::NewGuid().ToString('N') + '.dll')
        try {
            if ($env:OS -eq 'Windows_NT') {
                $code = 'Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions; $src = @(' + (($files | ForEach-Object { "[IO.File]::ReadAllText('{0}')" -f $_ }) -join ', ') + ') -join [Environment]::NewLine; ' +
                    '$refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location); ' +
                    ('try {{ Add-Type -TypeDefinition $src -ReferencedAssemblies $refs -OutputAssembly ''{0}'' -OutputType Library -IgnoreWarnings -ErrorAction Stop; exit 0 }} catch {{ Write-Output $_.Exception.Message; exit 1 }}' -f $out)
                $msg = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $code
                $LASTEXITCODE | Should -Be 0 -Because ($msg -join ' ')
            }
        }
        finally {
            Remove-Item $out -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Version 3.2: Release und Dokumentation' {
    It 'Versionsnummer ist 3.2 in Version.ps1, Versionen.cs und Versionshistorie.txt' {
        $vPs1 = [IO.File]::ReadAllText((Join-Path $global:V32Src 'Kern/Version.ps1'))
        $vPs1 | Should -Match '\$ScriptVersion\s*=\s*''3\.2'''
        $firstVer = [regex]::Match($global:V32Ver, 'new Eintrag\("([^"]+)"').Groups[1].Value
        $firstVer | Should -Be '3.2'
        $global:V32Hist | Should -Match 'VERSION 3\.2'
    }

    It 'Änderungsdatei und Testmatrix für Version 3.2 existieren' {
        $b = Get-MinibenchBuild
        $b.Version | Should -Be '3.2'
        $aePath = Join-Path $global:MinibenchRepoRoot ('Doku/' + [char]0x00C4 + 'nderungen_v3.2.txt')
        Test-Path -LiteralPath $aePath | Should -BeTrue
        Join-Path $global:MinibenchRepoRoot ('Doku/Testmatrix_v{0}.csv' -f $b.Version) | Should -Exist
    }

    It 'CHANGELOG.md enthält v3.2' {
        $cl = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'CHANGELOG.md'))
        $cl | Should -Match '## v3\.2'
    }
}
