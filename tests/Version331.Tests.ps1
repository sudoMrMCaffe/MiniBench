# Version 3.31: Multi-System-Vergleich im interaktiven Dashboard (N >= 2),
# Hardware-Spezifikationen, Benchmark-Matrix, nativer WinForms Dark Mode und Build-Sync.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Version.ps1', 'Bericht\Bausteine_Dashboard.ps1'
    $global:V331Gui = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui.cs'))
    $global:V331Ctrl = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui_Steuerelemente.cs'))
    $global:V331Verg = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui_Vergleich.cs'))
    $global:V331Ver = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Oberflaeche/Versionen.cs'))
    $global:V331Cmd = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'))
}

Describe 'Version 3.31 Deklaration' {
    It 'Version.ps1 definiert Version 3.31' {
        $vPs1 = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Version.ps1'))
        $vPs1 | Should -Match '\$ScriptVersion\s*=\s*''3\.31'''
    }

    It 'Versionen.cs enthält den Eintrag für 3.31' {
        $global:V331Ver | Should -Match 'new Eintrag\("3\.31",'
    }

    It 'Doku/Versionshistorie.txt enthält den Eintrag für 3.31' {
        $vh = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Doku/Versionshistorie.txt'))
        $vh | Should -Match 'VERSION 3\.31'
    }
}

Describe 'Multi-System-Export in Export-BenchDashboardData' {
    It 'aggregiert mehrere Systeme und liefert Hardware, Befunde und Benchmark-Metriken' {
        $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchV331_' + [guid]::NewGuid().ToString('N'))
        $dbDir = Join-Path $tempDir 'Datenbank'
        New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
        try {
            $sys1 = @{
                Format = 'PC-Diagnose-DB/2'; Name = 'System Alpha'; Computer = 'ALPHA-PC'; Datum = '2026-10-01 10:00';
                Hardware = @{ CPU = 'Intel Core i9-13900K'; RAM = '64 GB DDR5'; GPU = 'NVIDIA GeForce RTX 4090'; OS = 'Windows 11 Pro'; Mainboard = 'ASUS ROG MAXIMUS' };
                Scores = @{ Overall = 95; Gaming = 98; Desktop = 92; Workstation = 96 };
                Befunde = '0/1/2';
                BefundeDetails = @(@{ Stufe = 'Warnung'; Bereich = 'Kühlung'; Text = 'Lüfterdrehzahl erhöht' });
                Benchmark = @{ 'CPU|ST' = 2200; 'CPU|MT' = 38000; 'RAM|Lesen' = 95.5; 'GPU|REND' = 180; 'GPU|REND1' = 145 }
            } | ConvertTo-Json -Depth 5
            $sys2 = @{
                Format = 'PC-Diagnose-DB/2'; Name = 'System Beta'; Computer = 'BETA-PC'; Datum = '2026-10-02 11:00';
                Hardware = @{ CPU = 'AMD Ryzen 9 7950X'; RAM = '32 GB DDR5'; GPU = 'AMD Radeon RX 7900 XTX'; OS = 'Windows 11 Pro'; Mainboard = 'MSI MEG X670E' };
                Scores = @{ Overall = 92; Gaming = 94; Desktop = 90; Workstation = 93 };
                Befunde = '1/0/1';
                BefundeDetails = @(@{ Stufe = 'Kritisch'; Bereich = 'Datenträger'; Text = 'SMART-Sektorfehler gemeldet' });
                Benchmark = @{ 'CPU|ST' = 2100; 'CPU|MT' = 39000; 'RAM|Lesen' = 88.0; 'GPU|REND' = 170; 'GPU|REND1' = 135 }
            } | ConvertTo-Json -Depth 5
            $sys3 = @{
                Format = 'PC-Diagnose-DB/2'; Name = 'System Gamma'; Computer = 'GAMMA-PC'; Datum = '2026-10-03 12:00';
                Hardware = @{ CPU = 'Intel Core i7-12700K'; RAM = '32 GB DDR4'; GPU = 'NVIDIA GeForce RTX 3070'; OS = 'Windows 10 Pro'; Mainboard = 'GIGABYTE Z690' };
                Scores = @{ Overall = 75; Gaming = 76; Desktop = 78; Workstation = 72 };
                Befunde = '0/0/0';
                Benchmark = @{ 'CPU|ST' = 1750; 'CPU|MT' = 22000; 'RAM|Lesen' = 48.0; 'GPU|REND' = 105; 'GPU|REND1' = 85 }
            } | ConvertTo-Json -Depth 5

            $f1 = Join-Path $dbDir 'Sys1.json'
            $f2 = Join-Path $dbDir 'Sys2.json'
            $f3 = Join-Path $dbDir 'Sys3.json'
            [IO.File]::WriteAllText($f1, $sys1, [Text.Encoding]::UTF8)
            [IO.File]::WriteAllText($f2, $sys2, [Text.Encoding]::UTF8)
            [IO.File]::WriteAllText($f3, $sys3, [Text.Encoding]::UTF8)

            $data = MinibenchTest\Export-BenchDashboardData -DatenOrdner $tempDir -SystemPaths @($f1, $f2, $f3)
            $data.Systems.Count | Should -BeGreaterOrEqual 3
            $data.PreselectedIds.Count | Should -BeGreaterOrEqual 3

            $json = $data | ConvertTo-Json -Depth 8
            $json | Should -Match 'ALPHA-PC'
            $json | Should -Match 'BETA-PC'
            $json | Should -Match 'GAMMA-PC'
            $json | Should -Match 'SMART-Sektorfehler'

            $html = MinibenchTest\Export-BenchDashboardHtml -DatenOrdner $tempDir -SystemPaths @($f1, $f2)
            $html | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $html | Should -Be $true
            $content = [IO.File]::ReadAllText($html)
            $content | Should -Match 'Hardware-Spezifikationen im Direktvergleich'
            $content | Should -Match 'Vollständige Benchmark-Matrix'
            $content | Should -Match 'Befunde-Vergleich'
            $content | Should -Match '👑 Bestwert'
        } finally {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Nativer WinForms Dark Mode Farbsystem' {
    It 'UI.SetTheme schaltet konsistent zwischen Hell- und Dunkelmodus um' {
        $file = Join-Path $global:MinibenchSrcRoot 'Oberflaeche/DiagGui_Steuerelemente.cs'
        $subScript = @"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
`$usings = "using System; using System.Collections.Generic; using System.Drawing; using System.Drawing.Drawing2D; using System.Globalization; using System.Windows.Forms;"
`$fileContent = [System.IO.File]::ReadAllText('$($file.Replace("'", "''"))')
`$src = `$usings + [Environment]::NewLine + `$fileContent
`$refs = @([System.Windows.Forms.Form].Assembly.Location, [System.Drawing.Color].Assembly.Location)
Add-Type -TypeDefinition `$src -ReferencedAssemblies `$refs -IgnoreWarnings -ErrorAction Stop
[UI]::SetTheme(`$false)
Write-Output ("{0},{1},{2}" -f [UI]::Bg.R, [UI]::Bg.G, [UI]::Bg.B)
Write-Output ("{0},{1},{2}" -f [UI]::Text.R, [UI]::Text.G, [UI]::Text.B)
[UI]::SetTheme(`$true)
Write-Output ("{0},{1},{2}" -f [UI]::Bg.R, [UI]::Bg.G, [UI]::Bg.B)
Write-Output ("{0},{1},{2}" -f [UI]::Text.R, [UI]::Text.G, [UI]::Text.B)
"@
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($subScript)
        $enc = [System.Convert]::ToBase64String($bytes)
        $res = & powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc
        $LASTEXITCODE | Should -Be 0
        $res[0] | Should -Be '249,249,251'
        $res[1] | Should -Be '28,29,31'
        $res[2] | Should -Be '24,25,26'
        $res[3] | Should -Be '245,246,247'
    }

    It 'DiagGui.cs enthält Theme-Schalter und DWM Immersive Dark Mode Attribut' {
        $global:V331Gui | Should -Match 'btnThemeToggle'
        $global:V331Gui | Should -Match 'DwmSetWindowAttribute\(Handle,\s*20'
        $global:V331Gui | Should -Match 'ApplyTitleBarTheme'
        $global:V331Gui | Should -Match 'Einstellungen\.json'
        $global:V331Gui | Should -Match 'AppsUseLightTheme'
    }

    It 'DiagGui_Vergleich.cs bietet Vergleichen (Klassisch) und Interaktives Dashboard parallel' {
        $global:V331Verg | Should -Match 'Vergleichen \(Klassisch\)'
        $global:V331Verg | Should -Match 'Interaktives Dashboard'
        $global:V331Verg | Should -Match 'OpenDashboard\(\)'
        $global:V331Verg | Should -Match '-DashboardSysteme'
    }
}

Describe 'Vollständige C# 5-Kompilierung der Oberfläche' {
    It 'alle C#-Quelldateien in src/Oberflaeche lassen sich fehlerfrei übersetzen' {
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
            Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Git-Synchronisation in Bauen.cmd' {
    It 'Bauen.cmd enthält automatische Git-Aktualisierung und Release-Commit' {
        $global:V331Cmd | Should -Match 'git\.exe'
        $global:V331Cmd | Should -Match 'git\.exe -C \$Here add'
        $global:V331Cmd | Should -Match 'Release v\{0\}: Multi-System Dashboard, nativer GUI Dark Mode & Build-Sync'
        $global:V331Cmd | Should -Match 'Bereit zur Übertragung mit "git push"'
    }
}
