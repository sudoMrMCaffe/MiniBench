# Version 3.52: Netzlaufwerk-Härtung, Dashboard-Link-Fix, optimierte Datenpflege, aufgeräumte Optionen und Historie 1.0–1.8
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $global:V352Src = $global:MinibenchSrcRoot

    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Aenderungen.ps1', 'Kern\Modulvertrag.ps1', 'Kern\Datenordner.ps1', 'Kern\Werkzeuge.ps1', 'Kern\Datenpflege.ps1', 'Bericht\Stil.ps1', 'Bericht\Bausteine_Dashboard.ps1' `
        -Functions 'Get-SafeName', 'Invoke-External', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent'

    # Quelltexte einlesen
    $global:V352Gui       = [IO.File]::ReadAllText((Join-Path $global:V352Src 'Oberflaeche/DiagGui.cs'), [System.Text.Encoding]::UTF8)
    $global:V352Seiten    = [IO.File]::ReadAllText((Join-Path $global:V352Src 'Oberflaeche/DiagGui_Seiten.cs'), [System.Text.Encoding]::UTF8)
    $global:V352Vergleich = [IO.File]::ReadAllText((Join-Path $global:V352Src 'Oberflaeche/DiagGui_Vergleich.cs'), [System.Text.Encoding]::UTF8)
    $global:V352Ctrl      = [IO.File]::ReadAllText((Join-Path $global:V352Src 'Oberflaeche/DiagGui_Steuerelemente.cs'), [System.Text.Encoding]::UTF8)
    $global:V352Ver       = [IO.File]::ReadAllText((Join-Path $global:V352Src 'Oberflaeche/Versionen.cs'), [System.Text.Encoding]::UTF8)
    $global:V352Datenord  = [IO.File]::ReadAllText((Join-Path $global:V352Src 'Kern/Datenordner.ps1'), [System.Text.Encoding]::UTF8)
    $global:V352Werkz     = [IO.File]::ReadAllText((Join-Path $global:V352Src 'Kern/Werkzeuge.ps1'), [System.Text.Encoding]::UTF8)
    $global:V352Pflege    = [IO.File]::ReadAllText((Join-Path $global:V352Src 'Kern/Datenpflege.ps1'), [System.Text.Encoding]::UTF8)
    $global:V352Dash      = [IO.File]::ReadAllText((Join-Path $global:V352Src 'Bericht/Bausteine_Dashboard.ps1'), [System.Text.Encoding]::UTF8)
    $global:V352Cmd       = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'), [System.Text.Encoding]::UTF8)
}

Describe 'Version 3.52 Deklaration und Dokumentation' {
    It 'Version.ps1 definiert Version 3.52' {
        $vPs1 = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Version.ps1'), [System.Text.Encoding]::UTF8)
        $vPs1 | Should -Match '\$ScriptVersion\s*=\s*''3\.52'''
    }

    It 'Versionen.cs enthält den Eintrag für 3.52 an oberster Stelle' {
        $firstVer = [regex]::Match($global:V352Ver, 'new Eintrag\("([^"]+)"').Groups[1].Value
        $firstVer | Should -Be '3.52'
    }

    It 'Doku/Versionshistorie.txt enthält den Eintrag für 3.52 an oberster Stelle' {
        $vh = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Doku/Versionshistorie.txt'), [System.Text.Encoding]::UTF8)
        $vh | Should -Match 'VERSION 3\.52\s+\(\d{2}\.\d{2}\.\d{4}\)'
    }

    It 'CHANGELOG.md dokumentiert v3.52' {
        $cl = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'CHANGELOG.md'), [System.Text.Encoding]::UTF8)
        $cl | Should -Match '## v3\.52\s+\(\d{2}\.\d{2}\.\d{4}\)'
    }

    It 'Bauen.cmd enthält Commit-Nachricht für v3.52' {
        $global:V352Cmd | Should -Match '\$ver -eq ''3\.52'''
    }

    It 'Doku/Änderungen_v3.52.txt und Doku/Testmatrix_v3.52.csv existieren mit UTF-8 BOM' {
        $aePath = Join-Path $global:MinibenchRepoRoot ('Doku/' + [char]0x00C4 + 'nderungen_v3.52.txt')
        Test-Path -LiteralPath $aePath | Should -BeTrue
        $tmPath = Join-Path $global:MinibenchRepoRoot 'Doku/Testmatrix_v3.52.csv'
        Test-Path -LiteralPath $tmPath | Should -BeTrue

        $aeBytes = [IO.File]::ReadAllBytes($aePath)
        ($aeBytes[0] -eq 0xEF -and $aeBytes[1] -eq 0xBB -and $aeBytes[2] -eq 0xBF) | Should -BeTrue

        $tmBytes = [IO.File]::ReadAllBytes($tmPath)
        ($tmBytes[0] -eq 0xEF -and $tmBytes[1] -eq 0xBB -and $tmBytes[2] -eq 0xBF) | Should -BeTrue
    }
}

Describe 'Vollständige Versionshistorie 1.0 bis 1.8' {
    It 'Versionen.cs enthält alle Einzelversionen von 1.0 bis 1.8' {
        1..8 | ForEach-Object {
            $expected = "1.$_"
            $global:V352Ver | Should -Match ('new Eintrag\("' + [regex]::Escape($expected) + '"')
        }
        $global:V352Ver | Should -Not -Match 'new Eintrag\("1\.0 bis 1\.8"'
    }

    It 'Doku/Versionshistorie.txt dokumentiert alle Einzelversionen von 1.0 bis 1.8' {
        $vh = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Doku/Versionshistorie.txt'), [System.Text.Encoding]::UTF8)
        1..8 | ForEach-Object {
            $expected = "VERSION 1.$_"
            $vh | Should -Match ([regex]::Escape($expected))
        }
        $vh | Should -Not -Match 'VERSION 1\.0 bis 1\.8'
    }

    It 'CHANGELOG.md dokumentiert alle Einzelversionen von 1.0 bis 1.8' {
        $cl = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'CHANGELOG.md'), [System.Text.Encoding]::UTF8)
        1..8 | ForEach-Object {
            $expected = "## v1.$_"
            $cl | Should -Match ([regex]::Escape($expected))
        }
        $cl | Should -Not -Match '## v1\.0 - v1\.8'
    }
}

Describe 'Netzlaufwerk-Härtung: Lokale Bindung für Binaries & Cache' {
    It 'Datenordner.ps1 definiert Test-IsNetworkPath und Resolve-LocalDataDir' {
        $global:V352Datenord | Should -Match 'function Test-IsNetworkPath'
        $global:V352Datenord | Should -Match 'function Resolve-LocalDataDir'
    }

    It 'Test-IsNetworkPath erkennt UNC- und Netzlaufwerkspfade' {
        Test-IsNetworkPath '\\server\share' | Should -BeTrue
        Test-IsNetworkPath 'C:\Local\Path' | Should -BeFalse
    }

    It 'Resolve-DataDir hält CacheDir, ToolsDir und CpDir lokal auch bei Netzwerkkonfiguration' {
        $global:V352Datenord | Should -Match '\$script:LocalDataDir\s*='
        $global:V352Datenord | Should -Match '\$script:CacheDir\s*=\s*\$\(if\s*\(\$script:LocalDataDir\)\s*\{\s*Join-Path\s+\$script:LocalDataDir\s+''Cache'''
        $global:V352Datenord | Should -Match '\$script:ToolsDir\s*=\s*\$\(if\s*\(\$script:LocalDataDir\)\s*\{\s*Join-Path\s+\$script:LocalDataDir\s+''Tools'''
        $global:V352Datenord | Should -Match '\$script:CpDir\s*=\s*\$\(if\s*\(\$script:LocalDataDir\)\s*\{\s*Join-Path'
    }

    It 'Werkzeuge.ps1 Get-FileSha256 normalisiert Pfade und fängt Fehler ab' {
        $global:V352Werkz | Should -Match '\[System\.IO\.Path\]::GetFullPath\(\$Path\)'
        $global:V352Werkz | Should -Match '\[IO\.File\]::OpenRead\(\$norm\)'
    }
}

Describe 'Dashboard: Relative Berichtsverlinkung ohne ERR_FILE_NOT_FOUND' {
    It 'Bausteine_Dashboard.ps1 erzeugt saubere relative Pfade ohne doppeltes Berichte-Präfix' {
        $global:V352Dash | Should -Match '\$reportUrl\s*=\s*\$reportUrl\s*-replace\s*''\^Berichte/'',\s*'''''
        $global:V352Dash | Should -Match '\$reportUrl\s*=\s*\$reportUrl\s*-replace\s*''\\\\'',\s*''/'''
    }
}

Describe 'Datenpflege: Bereinigung verwaister & beschädigter Einträge' {
    It 'Datenpflege.ps1 archiviert beschädigte 0-Byte-JSON-Dateien' {
        $global:V352Pflege | Should -Match 'Beschaedigt'
        $global:V352Pflege | Should -Match 'beschädigte oder leere JSON-Datei'
    }

    It 'Datenpflege.ps1 archiviert verwaiste DB-Einträge ohne Berichtsordner' {
        $global:V352Pflege | Should -Match 'Verwaist'
        $global:V352Pflege | Should -Match 'zugehöriger Berichtsordner nicht mehr vorhanden'
    }

    It 'Datenpflege.ps1 bereinigt temporäre Reste im Laufzeitordner' {
        $global:V352Pflege | Should -Match '\*\.tmp'
        $global:V352Pflege | Should -Match '\*\.lock'
    }

    It 'Datenpflege.ps1 erfasst freigegebenen Speicherplatz in MB' {
        $global:V352Pflege | Should -Match 'FreigegebenMB'
    }
}

Describe 'Oberfläche: Aufgeräumte Optionen, keine redundante Checkliste & Fenstergröße' {
    It 'BuildBenchPage bindet clbCompare nicht mehr in die sichtbaren Controls ein' {
        $global:V352Gui | Should -Not -Match 'f\.Controls\.Add\(clbCompare\)'
        $global:V352Gui | Should -Not -Match 'Bereits geprüfte Systeme einblenden'
    }

    It 'BuildDiagPage verwendet OptionCard für kategorisierte Optionen' {
        $global:V352Gui | Should -Match 'OptionCard\("Zusatzwerkzeuge & Speicherdiagnose"'
        $global:V352Gui | Should -Match 'OptionCard\("Prüfzeiträume & Schwellenwerte"'
    }

    It 'Startfenstergröße ist auf 1320x860 vergrößert' {
        $global:V352Gui | Should -Match 'Math\.Min\(UI\.S\(1320\),\s*\(int\)\(workArea\.Width\s*\*\s*0\.96\)\)'
        $global:V352Gui | Should -Match 'Math\.Min\(UI\.S\(860\),\s*\(int\)\(workArea\.Height\s*\*\s*0\.95\)\)'
    }
}

Describe 'Vollständige C# 5-Kompilierung der Oberfläche' {
    It 'alle C#-Quelldateien in src/Oberflaeche lassen sich fehlerfrei übersetzen' {
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:V352Src 'Oberflaeche') $_ }
        $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGui_' + [guid]::NewGuid().ToString('N') + '.dll')
        try {
            $code = 'Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions; $src = @(' + (($files | ForEach-Object { "[IO.File]::ReadAllText('{0}')" -f $_ }) -join ', ') + ') -join [Environment]::NewLine; ' +
                '$refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location); ' +
                ('try {{ Add-Type -TypeDefinition $src -ReferencedAssemblies $refs -OutputAssembly ''{0}'' -OutputType Library -IgnoreWarnings -ErrorAction Stop; exit 0 }} catch {{ Write-Output $_.Exception.Message; exit 1 }}' -f $out)
            $msg = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $code
            $LASTEXITCODE | Should -Be 0 -Because ($msg -join ' ')
        } finally {
            Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
        }
    }
}
