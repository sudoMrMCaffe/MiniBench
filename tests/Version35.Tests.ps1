# Version 3.5: Taskleisten-Bugfix, Minimal-Preset, winget-Softwarepakete, NAS-Netzlaufwerke & Hover-Charts
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $global:V35Src = $global:MinibenchSrcRoot
    $global:V35KatRaw = [IO.File]::ReadAllText((Join-Path $global:V35Src 'Module/Optimierung/Katalog.psd1'), [System.Text.Encoding]::UTF8)

    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Aenderungen.ps1', 'Kern\Modulvertrag.ps1', 'Module\Optimierung\Funktionen.ps1', 'Kern\Datenordner.ps1', 'Bericht\Stil.ps1', 'Bericht\HtmlBericht.ps1' `
        -Functions 'Get-SafeName', 'Invoke-External', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent'

    # Quelltexte einlesen
    $global:V35Gui       = [IO.File]::ReadAllText((Join-Path $global:V35Src 'Oberflaeche/DiagGui.cs'), [System.Text.Encoding]::UTF8)
    $global:V35Seiten    = [IO.File]::ReadAllText((Join-Path $global:V35Src 'Oberflaeche/DiagGui_Seiten.cs'), [System.Text.Encoding]::UTF8)
    $global:V35Vergleich = [IO.File]::ReadAllText((Join-Path $global:V35Src 'Oberflaeche/DiagGui_Vergleich.cs'), [System.Text.Encoding]::UTF8)
    $global:V35Ctrl      = [IO.File]::ReadAllText((Join-Path $global:V35Src 'Oberflaeche/DiagGui_Steuerelemente.cs'), [System.Text.Encoding]::UTF8)
    $global:V35Ver       = [IO.File]::ReadAllText((Join-Path $global:V35Src 'Oberflaeche/Versionen.cs'), [System.Text.Encoding]::UTF8)
    $global:V35Html      = [IO.File]::ReadAllText((Join-Path $global:V35Src 'Bericht/HtmlBericht.ps1'), [System.Text.Encoding]::UTF8)
    $global:V35Stil      = [IO.File]::ReadAllText((Join-Path $global:V35Src 'Bericht/Stil.ps1'), [System.Text.Encoding]::UTF8)
    $global:V35Datenord  = [IO.File]::ReadAllText((Join-Path $global:V35Src 'Kern/Datenordner.ps1'), [System.Text.Encoding]::UTF8)
    $global:V35Cmd       = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'), [System.Text.Encoding]::UTF8)
}

Describe 'Version 3.5 Deklaration und Dokumentation' {
    It 'Version.ps1 definiert Version 3.5 oder höher' {
        $vPs1 = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Version.ps1'), [System.Text.Encoding]::UTF8)
        $vPs1 | Should -Match '\$ScriptVersion\s*=\s*''3\.5(1|2)?'''
    }

    It 'Versionen.cs enthält den Eintrag für 3.5 oder höher an oberster Stelle' {
        $firstVer = [regex]::Match($global:V35Ver, 'new Eintrag\("([^"]+)"').Groups[1].Value
        $firstVer | Should -Match '^3\.5(1|2)?$'
    }

    It 'Doku/Versionshistorie.txt enthält den Eintrag für 3.5 an oberster Stelle' {
        $vh = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Doku/Versionshistorie.txt'), [System.Text.Encoding]::UTF8)
        $vh | Should -Match 'VERSION 3\.5\s+\(\d{2}\.\d{2}\.\d{4}\)'
    }

    It 'CHANGELOG.md dokumentiert v3.5' {
        $cl = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'CHANGELOG.md'), [System.Text.Encoding]::UTF8)
        $cl | Should -Match '## v3\.5\s+\(\d{2}\.\d{2}\.\d{4}\)'
    }

    It 'Bauen.cmd enthält Commit-Nachricht für v3.5' {
        $global:V35Cmd | Should -Match '\$ver -eq ''3\.5'''
    }

    It 'Doku/Änderungen_v3.5.txt und Doku/Testmatrix_v3.5.csv existieren mit UTF-8 BOM' {
        $aePath = Join-Path $global:MinibenchRepoRoot ('Doku/' + [char]0x00C4 + 'nderungen_v3.5.txt')
        Test-Path -LiteralPath $aePath | Should -BeTrue
        $tmPath = Join-Path $global:MinibenchRepoRoot 'Doku/Testmatrix_v3.5.csv'
        Test-Path -LiteralPath $tmPath | Should -BeTrue

        $aeBytes = [IO.File]::ReadAllBytes($aePath)
        ($aeBytes[0] -eq 0xEF -and $aeBytes[1] -eq 0xBB -and $aeBytes[2] -eq 0xBF) | Should -BeTrue

        $tmBytes = [IO.File]::ReadAllBytes($tmPath)
        ($tmBytes[0] -eq 0xEF -and $tmBytes[1] -eq 0xBB -and $tmBytes[2] -eq 0xBF) | Should -BeTrue
    }
}

Describe 'Fehlerbehebung Taskleiste & Optimierungs-Presets' {
    It 'Katalogeintrag TaskleisteGruppieren enthält TaskbarGlomLevel und KEIN TaskbarEndTask' {
        $entry = Get-OptEntry 'TaskleisteGruppieren'
        $entry | Should -Not -BeNullOrEmpty
        $entry.Aktionen | Should -Not -BeNullOrEmpty
        @($entry.Aktionen | Where-Object { $_.Name -eq 'TaskbarGlomLevel' }).Count | Should -Be 1
        @($entry.Aktionen | Where-Object { $_.Name -eq 'TaskbarEndTask' }).Count | Should -Be 0
    }

    It 'TaskbarEndTask ist als eigenständiger Eintrag mit Vorlagen MSE definiert' {
        $entry = Get-OptEntry 'TaskbarEndTask'
        $entry | Should -Not -BeNullOrEmpty
        $entry.Titel | Should -Be 'Taskleiste: Task beenden per Rechtsklick'
        $entry.Kat | Should -Be 'Bedienung'
        $entry.Vorlagen | Should -Be 'MSE'
        $entry.Bedingung | Should -Be 'Win11'
        $entry.Aktionen.Count | Should -Be 2
        @($entry.Aktionen | Where-Object { $_.Name -eq 'TaskbarEndTask' -and $_.Wert -eq 1 }).Count | Should -Be 2
        @($entry.Gegenbefehl | Where-Object { $_ -match 'TaskbarEndTask' }).Count | Should -BeGreaterThan 0
    }

    It 'Preset Minimal (M) ist gestrafft und enthält weniger Einträge als Leos Empfehlung (S)' {
        $presetM = Get-OptPreset 'M'
        $presetS = Get-OptPreset 'S'
        $presetM.Count | Should -BeLessThan $presetS.Count
        $presetM.Count | Should -Be 5
        $presetM | Should -Contain 'TelemetrieMinimal'
        $presetM | Should -Contain 'Fehlerberichte'
        $presetM | Should -Contain 'WerbeId'
        $presetM | Should -Contain 'Speicheroptimierung'
        $presetM | Should -Contain 'TaskbarEndTask'
    }

    It 'DiagGui.cs wählt bei Start das Preset Minimal (M) vor' {
        $global:V35Gui | Should -Match 'ApplyOptPreset\("M"\)'
        $global:V35Gui | Should -Match 'defaultMinimal'
    }
}

Describe 'Responsives Fensterlayout' {
    It 'Startfenstergröße nutzt responsive 1220x740 Formeln mit 880x560 Minimum' {
        $global:V35Gui | Should -Match 'Math\.Min\(UI\.S\((1220|1320)\),\s*\(int\)\((workArea|Screen\.FromPoint\(Cursor\.Position\)\.WorkingArea)\.Width\s*\*\s*0\.(95|96)\)\)'
        $global:V35Gui | Should -Match 'Math\.Min\(UI\.S\((740|860)\),\s*\(int\)\((workArea|Screen\.FromPoint\(Cursor\.Position\)\.WorkingArea)\.Height\s*\*\s*0\.(92|95)\)\)'
        $global:V35Gui | Should -Match 'MinimumSize\s*=\s*new\s+Size\(UI\.S\(880\),\s*UI\.S\(560\)\)'
    }
}

Describe 'Modul Tools: winget Softwarepakete' {
    It 'DiagGui_Seiten.cs enthält Abschnitt Softwarepakete installieren (winget)' {
        $global:V35Seiten | Should -Match 'Softwarepakete installieren \(winget\)'
        $global:V35Seiten | Should -Match 'Google\.Chrome'
        $global:V35Seiten | Should -Match 'Mozilla\.Firefox'
        $global:V35Seiten | Should -Match 'Valve\.Steam'
        $global:V35Seiten | Should -Match 'Discord\.Discord'
        $global:V35Seiten | Should -Match 'Notepad\+\+\.Notepad\+\+'
        $global:V35Seiten | Should -Match 'ONLYOFFICE\.DesktopEditors'
        $global:V35Seiten | Should -Match '7zip\.7zip'
        $global:V35Seiten | Should -Match 'VideoLAN\.VLC'
    }

    It 'DiagGui_Seiten.cs implementiert IsWingetAvailable und asynchrone Installation' {
        $global:V35Seiten | Should -Match 'IsWingetAvailable'
        $global:V35Seiten | Should -Match 'InstallWingetPackagesAsync'
        $global:V35Seiten | Should -Match 'winget ist auf diesem System nicht installiert'
    }
}

Describe 'NAS-Netzlaufwerke & Lokaler Fallback' {
    It 'Resolve-DataDir prüft Netzwerk.json und fällt bei Nichterreichbarkeit auf lokalen Ordner zurück' {
        $global:V35Datenord | Should -Match 'Netzwerk\.json'
        $global:V35Datenord | Should -Match 'NasPfad|NetzwerkPfad'
        $global:V35Datenord | Should -Match 'Test-WritableDir'
    }

    It 'Resolve-DataDir liefert lokalen Pfad wenn NAS-Pfad ungültig oder unerreichbar ist' {
        $fakeNetzwerkJson = Join-Path ([IO.Path]::GetTempPath()) ('Netzwerk_' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            $cfg = @{ NasPfad = '\\NichtExistierenderServer\Freigabe\Minibench' } | ConvertTo-Json
            [IO.File]::WriteAllText($fakeNetzwerkJson, $cfg, [System.Text.Encoding]::UTF8)

            $res = Resolve-DataDir -AppDir (Join-Path ([IO.Path]::GetTempPath()) 'MiniBenchTest')
            $res | Should -Not -BeNullOrEmpty
            # Muss ein lokaler Pfad sein, nicht das ungültige NAS
            $res | Should -Not -Match '^\\\\NichtExistierenderServer'
        } finally {
            if (Test-Path -LiteralPath $fakeNetzwerkJson) { Remove-Item -LiteralPath $fakeNetzwerkJson -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'DiagGui bietet Netzlaufwerk-Verbindungsdialog und Live-Umschaltung' {
        $global:V35Seiten | Should -Match 'ShowConnectNasDialog'
        $global:V35Seiten | Should -Match 'SwitchDataDir'
        $global:V35Seiten | Should -Match 'btnConnectNas'
        $global:V35Vergleich | Should -Match 'ShowConnectNasDialog'
    }
}

Describe 'Bericht-Anpassung: Hoverbare Diagramme & Befunde-Bereinigung' {
    It 'HtmlBericht.ps1 enthält keine Freitext-Suchleiste für Befunde' {
        $global:V35Html | Should -Not -Match 'id="befundSearch"'
        $global:V35Html | Should -Match 'id="befundeTable"'
        $global:V35Html | Should -Match 'class="fchip'
    }

    It 'HtmlBericht.ps1 generiert reichhaltige Telemetrie-Tooltips (Zeit, °C, GHz, W)' {
        $global:V35Html | Should -Match 'Get-TelemetryTip'
        $global:V35Html | Should -Match 'CPU-Takt'
        $global:V35Html | Should -Match 'CPU-Paket'
    }

    It 'Referenz_Vergleich.ps1 unterstützt p.Tip für interaktive Hover-Punkte' {
        $rv = [IO.File]::ReadAllText((Join-Path $global:V35Src 'Kern/Referenz_Vergleich.ps1'), [System.Text.Encoding]::UTF8)
        $rv | Should -Match '\$p\.Tip'
        $rv | Should -Match 'data-tip='
    }

    It 'Stil.ps1 formatiert chart-tooltip für mehrzeilige Inhalte' {
        $global:V35Stil | Should -Match '\.chart-tooltip'
        $global:V35Stil | Should -Match 'min-width:\s*140px'
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
            if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
        }
    }
}