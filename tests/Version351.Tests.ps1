# Version 3.51: Dashboard-Berichtsverlinkung, Referenz-Deduplizierung & persistente Netzlaufwerke
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $global:V351Src = $global:MinibenchSrcRoot

    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Aenderungen.ps1', 'Kern\Modulvertrag.ps1', 'Kern\Datenordner.ps1', 'Bericht\Stil.ps1', 'Bericht\Bausteine_Dashboard.ps1' `
        -Functions 'Get-SafeName', 'Invoke-External', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent'

    # Quelltexte einlesen
    $global:V351Gui       = [IO.File]::ReadAllText((Join-Path $global:V351Src 'Oberflaeche/DiagGui.cs'), [System.Text.Encoding]::UTF8)
    $global:V351Seiten    = [IO.File]::ReadAllText((Join-Path $global:V351Src 'Oberflaeche/DiagGui_Seiten.cs'), [System.Text.Encoding]::UTF8)
    $global:V351Vergleich = [IO.File]::ReadAllText((Join-Path $global:V351Src 'Oberflaeche/DiagGui_Vergleich.cs'), [System.Text.Encoding]::UTF8)
    $global:V351Ctrl      = [IO.File]::ReadAllText((Join-Path $global:V351Src 'Oberflaeche/DiagGui_Steuerelemente.cs'), [System.Text.Encoding]::UTF8)
    $global:V351Ver       = [IO.File]::ReadAllText((Join-Path $global:V351Src 'Oberflaeche/Versionen.cs'), [System.Text.Encoding]::UTF8)
    $global:V351Datenord  = [IO.File]::ReadAllText((Join-Path $global:V351Src 'Kern/Datenordner.ps1'), [System.Text.Encoding]::UTF8)
    $global:V351Dash      = [IO.File]::ReadAllText((Join-Path $global:V351Src 'Bericht/Bausteine_Dashboard.ps1'), [System.Text.Encoding]::UTF8)
    $global:V351Cmd       = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'), [System.Text.Encoding]::UTF8)
}

Describe 'Version 3.51 Deklaration und Dokumentation' {
    It 'Version.ps1 definiert Version 3.51' {
        $vPs1 = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Version.ps1'), [System.Text.Encoding]::UTF8)
        $vPs1 | Should -Match '\$ScriptVersion\s*=\s*''3\.51'''
    }

    It 'Versionen.cs enthÃ¤lt den Eintrag fÃ¼r 3.51 an oberster Stelle' {
        $firstVer = [regex]::Match($global:V351Ver, 'new Eintrag\("([^"]+)"').Groups[1].Value
        $firstVer | Should -Be '3.51'
    }

    It 'Doku/Versionshistorie.txt enthÃ¤lt den Eintrag fÃ¼r 3.51 an oberster Stelle' {
        $vh = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Doku/Versionshistorie.txt'), [System.Text.Encoding]::UTF8)
        $vh | Should -Match 'VERSION 3\.51\s+\(\d{2}\.\d{2}\.\d{4}\)'
    }

    It 'CHANGELOG.md dokumentiert v3.51' {
        $cl = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'CHANGELOG.md'), [System.Text.Encoding]::UTF8)
        $cl | Should -Match '## v3\.51\s+\(\d{2}\.\d{2}\.\d{4}\)'
    }

    It 'Bauen.cmd enthÃ¤lt Commit-Nachricht fÃ¼r v3.51' {
        $global:V351Cmd | Should -Match '\$ver -eq ''3\.51'''
    }

    It 'Doku/Ã„nderungen_v3.51.txt und Doku/Testmatrix_v3.51.csv existieren mit UTF-8 BOM' {
        $aePath = Join-Path $global:MinibenchRepoRoot ('Doku/' + [char]0x00C4 + 'nderungen_v3.51.txt')
        Test-Path -LiteralPath $aePath | Should -BeTrue
        $tmPath = Join-Path $global:MinibenchRepoRoot 'Doku/Testmatrix_v3.51.csv'
        Test-Path -LiteralPath $tmPath | Should -BeTrue

        $aeBytes = [IO.File]::ReadAllBytes($aePath)
        ($aeBytes[0] -eq 0xEF -and $aeBytes[1] -eq 0xBB -and $aeBytes[2] -eq 0xBF) | Should -BeTrue

        $tmBytes = [IO.File]::ReadAllBytes($tmPath)
        ($tmBytes[0] -eq 0xEF -and $tmBytes[1] -eq 0xBB -and $tmBytes[2] -eq 0xBF) | Should -BeTrue
    }
}

Describe 'Dashboard: Berichtsverlinkung & Direkter Aufruf' {
    It 'Export-BenchDashboardData erzeugt ReportUrl fÃ¼r Systeme' {
        $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchV351_' + [guid]::NewGuid().ToString('N'))
        $dbDir = Join-Path $tempDir 'Datenbank'
        $repDir = Join-Path $tempDir 'Berichte'
        New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
        New-Item -ItemType Directory -Path $repDir -Force | Out-Null
        try {
            $sysData = @{
                Format = 'PC-Diagnose-DB/2'; Name = 'Test System Alpha'; Computer = 'ALPHA-PC'; Datum = '2026-10-01 12:00';
                Hardware = @{ CPU = 'Intel Core i7-13700K'; RAM = '32 GB'; GPU = 'RTX 4070'; OS = 'Windows 11 Pro' };
                Scores = @{ Overall = 90; Gaming = 92; Desktop = 88; Workstation = 91 };
                BerichtPfad = 'Berichte\2026-10-01_1200_ALPHA-PC\Diagnosebericht.html'
            } | ConvertTo-Json
            [IO.File]::WriteAllText((Join-Path $dbDir 'System1.json'), $sysData, [System.Text.Encoding]::UTF8)

            $data = Export-BenchDashboardData -AppDir $tempDir
            $data | Should -Not -BeNullOrEmpty
            $data.Systems.Count | Should -Be 1
            $data.Systems[0].ReportUrl | Should -Not -BeNullOrEmpty
            $data.Systems[0].ReportUrl | Should -Match 'Diagnosebericht\.html'
        } finally {
            if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'Get-BenchDashboardHtmlTemplate enthält Verlinkungen auf ReportUrl und Bericht-Badges' {
        $html = Get-BenchDashboardHtmlTemplate
        $html | Should -Match 's\.ReportUrl'
        $html | Should -Match 'Diagnosebericht'
        $html | Should -Match 'report-badge-btn'
    }

    It 'DiagGui_Vergleich.cs enthält den Button btnOpenReport (Bericht öffnen)' {
        $global:V351Vergleich | Should -Match 'btnOpenReport'
        $global:V351Vergleich | Should -Match 'btnOpenReport\s*=\s*UI\.Secondary\("Bericht'
        $global:V351Vergleich | Should -Match 'Diagnosebericht\.html'
    }

    It 'btnOpenReport wird bei genau 1 gewähltem System aktiviert' {
        $global:V351Vergleich | Should -Match 'btnOpenReport\.Enabled\s*='
    }
}

Describe 'Dashboard: Referenzsystem-Deduplizierung' {
    It 'Export-BenchDashboardData schlieÃŸt Referenzsysteme aus der allgemeinen Systems-Liste aus' {
        $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchV351Ref_' + [guid]::NewGuid().ToString('N'))
        $dbDir = Join-Path $tempDir 'Datenbank'
        New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
        try {
            # Echte Messung
            $realSys = @{
                Format = 'PC-Diagnose-DB/2'; Name = 'Mein Hauptrechner'; Computer = 'MEIN-PC'; Datum = '2026-10-05 10:00';
                Hardware = @{ CPU = 'AMD Ryzen 7 7800X3D'; RAM = '32 GB'; GPU = 'RX 7900 XT'; OS = 'Windows 11' }
            } | ConvertTo-Json
            [IO.File]::WriteAllText((Join-Path $dbDir 'MeinPC.json'), $realSys, [System.Text.Encoding]::UTF8)

            # In die Datenbank kopiertes Referenzprofil
            $refSys = @{
                Format = 'PC-Diagnose-DB/2'; Id = 'Desktop_HighEnd'; Name = 'High-End Gaming PC'; Typ = 'Referenz';
                Hardware = @{ CPU = 'Intel Core i9-14900K'; RAM = '64 GB'; GPU = 'RTX 4090'; OS = 'Windows 11' }
            } | ConvertTo-Json
            [IO.File]::WriteAllText((Join-Path $dbDir 'Ref_HighEnd.json'), $refSys, [System.Text.Encoding]::UTF8)

            $data = Export-BenchDashboardData -AppDir $tempDir
            $data.Systems.Count | Should -Be 1
            $data.Systems[0].DisplayName | Should -Be 'Mein Hauptrechner'
            # Referenz taucht in References auf, nicht in Systems
            $data.References.Count | Should -BeGreaterThan 0
            @($data.Systems | Where-Object { $_.Id -eq 'Desktop_HighEnd' -or $_.Typ -eq 'Referenz' }).Count | Should -Be 0
        } finally {
            if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'Get-BenchDashboardHtmlTemplate dedupliziert Systeme clientseitig' {
        $html = Get-BenchDashboardHtmlTemplate
        $html | Should -Match 'seen\.has\('
    }
}

Describe 'Persistente NAS- & Netzlaufwerk-Verbindung' {
    It 'Resolve-DataDir prÃ¼ft redundante Speicherorte fÃ¼r Netzwerk.json' {
        $global:V351Datenord | Should -Match 'LEOSMINIBENCH_EXE'
        $global:V351Datenord | Should -Match 'MyDocuments'
        $global:V351Datenord | Should -Match 'ApplicationData'
    }

    It 'Resolve-DataDir fÃ¼hrt net use aus wenn Share getrennt war' {
        $global:V351Datenord | Should -Match 'net\.exe\s+use\s+\$nas\s+/persistent:yes'
    }

    It 'DiagGui_Seiten.cs sichert Netzwerk.json redundant an allen Speicherorten' {
        $global:V351Seiten | Should -Match 'LEOSMINIBENCH_EXE'
        $global:V351Seiten | Should -Match 'MyDocuments'
        $global:V351Seiten | Should -Match 'ApplicationData'
        $global:V351Seiten | Should -Match 'Netzwerk\.json'
    }

    It 'DiagGui.cs aktualisiert lblDbPath nach Ordnerwechsel' {
        $global:V351Gui | Should -Match 'lblDbPath\.Text'
    }
}

Describe 'VollstÃ¤ndige C# 5-Kompilierung der OberflÃ¤che' {
    It 'alle C#-Quelldateien in src/Oberflaeche lassen sich fehlerfrei Ã¼bersetzen' {
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGui351_' + [guid]::NewGuid().ToString('N') + '.dll')
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