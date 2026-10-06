# Version 3.32: Dark-Mode-Feinschliff (Scrollbars, ComboBox, Header & Kontraste)
# und Konsolidierung des Systemvergleichs.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Version.ps1', 'Bericht\Bausteine_Dashboard.ps1'
    $global:V332Gui = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui.cs'))
    $global:V332Ctrl = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui_Steuerelemente.cs'))
    $global:V332Verg = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui_Vergleich.cs'))
    $global:V332Seiten = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui_Seiten.cs'))
    $global:V332Ver = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/Versionen.cs'))
    $global:V332Start = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Ablauf/Start.ps1'))
    $global:V332Cmd = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'))
}

Describe 'Version 3.32 Deklaration und Dokumentation' {
    It 'Version.ps1 definiert Version 3.32 oder höher' {
        $vPs1 = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Version.ps1'))
        $vPs1 | Should -Match '\$ScriptVersion\s*=\s*''3\.(32|4|5)'''
    }

    It 'Versionen.cs enthält den Eintrag für 3.32 oder höher an oberster Stelle' {
        $firstVer = [regex]::Match($global:V332Ver, 'new Eintrag\("([^"]+)"').Groups[1].Value
        $firstVer | Should -Match '3\.(32|4|5)'
    }

    It 'Doku/Versionshistorie.txt enthÃ¤lt den Eintrag fÃ¼r 3.32' {
        $vh = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Doku/Versionshistorie.txt'))
        $vh | Should -Match 'VERSION 3\.32'
    }

    It 'Doku/Ã„nderungen_v3.32.txt und Doku/Testmatrix_v3.32.csv existieren mit UTF-8 BOM' {
        $aePath = Join-Path $global:MinibenchRepoRoot ('Doku/' + [char]0x00C4 + 'nderungen_v3.32.txt')
        Test-Path -LiteralPath $aePath | Should -BeTrue
        $tmPath = Join-Path $global:MinibenchRepoRoot 'Doku/Testmatrix_v3.32.csv'
        Test-Path -LiteralPath $tmPath | Should -BeTrue

        $aeBytes = [IO.File]::ReadAllBytes($aePath)
        ($aeBytes[0] -eq 0xEF -and $aeBytes[1] -eq 0xBB -and $aeBytes[2] -eq 0xBF) | Should -BeTrue

        $tmBytes = [IO.File]::ReadAllBytes($tmPath)
        ($tmBytes[0] -eq 0xEF -and $tmBytes[1] -eq 0xBB -and $tmBytes[2] -eq 0xBF) | Should -BeTrue
    }
}

Describe 'WinForms Dark Mode Feinschliff' {
    It 'DiagGui_Steuerelemente.cs definiert DarkComboBox mit OwnerDraw und Theming' {
        $global:V332Ctrl | Should -Match 'public class DarkComboBox\s*:\s*ComboBox'
        $global:V332Ctrl | Should -Match 'DrawMode\s*=\s*DrawMode\.OwnerDrawFixed'
        $global:V332Ctrl | Should -Match 'protected override void OnPaint'
        $global:V332Ctrl | Should -Match 'protected override void OnDrawItem'
        $global:V332Ctrl | Should -Match 'UI\.Panel'
        $global:V332Ctrl | Should -Match 'UI\.Line'
    }

    It 'DiagGui_Steuerelemente.cs UI.Secondary zeichnet deaktivierte SchaltflÃ¤chen mit kontrastreichem Text' {
        $global:V332Ctrl | Should -Match 'b\.Paint\s*\+='
        $global:V332Ctrl | Should -Match '!b\.Enabled'
        $global:V332Ctrl | Should -Match 'Color\.FromArgb\(140,\s*145,\s*155\)'
    }

    It 'DiagGui.cs definiert EnableDarkListView fÃ¼r TabellenkÃ¶pfe' {
        $global:V332Gui | Should -Match 'void EnableDarkListView\(ListView lv\)'
        $global:V332Gui | Should -Match 'lv\.OwnerDraw\s*=\s*true'
        $global:V332Gui | Should -Match 'DrawColumnHeader\s*\+='
    }

    It 'DiagGui.cs bindet SetPreferredAppMode und SetWindowTheme fÃ¼r native dunkle Win32-Scrollbars ein' {
        $global:V332Gui | Should -Match 'SetPreferredAppMode'
        $global:V332Gui | Should -Match 'SetWindowTheme'
        $global:V332Gui | Should -Match 'DarkMode_Explorer'
        $global:V332Gui | Should -Match 'ApplyNativeControlThemes'
    }

    It 'Alle Tabellen (lvDb, lvSens, lvChg) nutzen EnableDarkListView' {
        $global:V332Verg | Should -Match 'EnableDarkListView\(lvDb\)'
        $global:V332Gui | Should -Match 'EnableDarkListView\(lvSens\)'
        $global:V332Seiten | Should -Match 'EnableDarkListView\(lvChg\)'
    }

    It 'CheckedListBoxes (clbDisks, clbCompare) initialisieren mit UI.Panel und UI.Text' {
        $global:V332Gui | Should -Match 'clbDisks\.BackColor\s*=\s*UI\.Panel'
        $global:V332Gui | Should -Match 'clbCompare\.BackColor\s*=\s*UI\.Panel'
    }
}

Describe 'Konsolidierung des Systemvergleichs' {
    It 'DiagGui_Vergleich.cs bietet Interaktives Dashboard als primÃ¤re Vergleichsaktion' {
        $global:V332Verg | Should -Match 'btnDashboard\s*=\s*UI\.Primary\("(Interaktives )?Dashboard"\)'
        $global:V332Verg | Should -Match 'OpenDashboard\(\)'
        $global:V332Verg | Should -Match 'Tip\(btnDashboard,'
    }

    It 'DiagGui_Vergleich.cs leitet CompareSelected auf OpenDashboard weiter' {
        $global:V332Verg | Should -Match 'void CompareSelected\(\)\s*\{\s*OpenDashboard\(\);'
    }

    It 'DiagGui_Vergleich.cs KontextmenÃ¼ enthÃ¤lt Im Dashboard vergleichen' {
        $global:V332Verg | Should -Match 'MenuItem\("Im Dashboard vergleichen"'
    }

    It 'Start.ps1 leitet Befehlszeilen-Parameter -Vergleich an Export-BenchDashboardHtml weiter' {
        $global:V332Start | Should -Match 'Export-BenchDashboardHtml\s*-SystemPaths'
    }
}

Describe 'VollstÃ¤ndige C# 5-Kompilierung der OberflÃ¤che' {
    It 'alle C#-Quelldateien in src/Oberflaeche lassen sich fehlerfrei Ã¼bersetzen' {
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGui_' + [guid]::NewGuid().ToString('N') + '.dll')
        try {
            $code = 'Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions; ' +
                '$srcFiles = @(' + (($files | ForEach-Object { "[IO.File]::ReadAllText('{0}')" -f $_ }) -join ', ') + '); ' +
                '$src = [string]::Join([Environment]::NewLine, $srcFiles); ' +
                '$refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location); ' +
                ('try {{ Add-Type -TypeDefinition $src -ReferencedAssemblies $refs -OutputAssembly ''{0}'' -OutputType Library -IgnoreWarnings -ErrorAction Stop; exit 0 }} catch {{ Write-Output $_.Exception.Message; exit 1 }}' -f $out)
            $msg = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $code
            $LASTEXITCODE | Should -Be 0 -Because ($msg -join ' ')
        } finally {
            if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
        }
    }
}
