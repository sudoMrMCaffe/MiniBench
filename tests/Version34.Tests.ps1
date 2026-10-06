# Version 3.4: Modul Tools (Portable Werkzeuge & System-Shortcuts), Leos Empfehlung & interaktiver Hauptbericht
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $global:V34Src = $global:MinibenchSrcRoot
    $global:V34KatRaw = [IO.File]::ReadAllText((Join-Path $global:V34Src 'Module/Optimierung/Katalog.psd1'), [System.Text.Encoding]::UTF8)

    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Aenderungen.ps1', 'Kern\Modulvertrag.ps1', 'Module\Optimierung\Funktionen.ps1', 'Bericht\Stil.ps1', 'Bericht\HtmlBericht.ps1' `
        -Functions 'Get-SafeName', 'Invoke-External', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent'

    # Quelltexte einlesen
    $global:V34Gui    = [IO.File]::ReadAllText((Join-Path $global:V34Src 'Oberflaeche/DiagGui.cs'), [System.Text.Encoding]::UTF8)
    $global:V34Seiten = [IO.File]::ReadAllText((Join-Path $global:V34Src 'Oberflaeche/DiagGui_Seiten.cs'), [System.Text.Encoding]::UTF8)
    $global:V34Ctrl   = [IO.File]::ReadAllText((Join-Path $global:V34Src 'Oberflaeche/DiagGui_Steuerelemente.cs'), [System.Text.Encoding]::UTF8)
    $global:V34Ver    = [IO.File]::ReadAllText((Join-Path $global:V34Src 'Oberflaeche/Versionen.cs'), [System.Text.Encoding]::UTF8)
    $global:V34Html   = [IO.File]::ReadAllText((Join-Path $global:V34Src 'Bericht/HtmlBericht.ps1'), [System.Text.Encoding]::UTF8)
    $global:V34Stil   = [IO.File]::ReadAllText((Join-Path $global:V34Src 'Bericht/Stil.ps1'), [System.Text.Encoding]::UTF8)
    $global:V34Cmd    = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'), [System.Text.Encoding]::UTF8)
}

Describe 'Version 3.4 Deklaration und Dokumentation' {
    It 'Version.ps1 definiert Version 3.4 oder höher' {
        $vPs1 = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Version.ps1'), [System.Text.Encoding]::UTF8)
        $vPs1 | Should -Match '\$ScriptVersion\s*=\s*''3\.[45]'''
    }

    It 'Versionen.cs enthält den Eintrag für 3.4' {
        $global:V34Ver | Should -Match 'new Eintrag\("3\.4"'
    }

    It 'Doku/Versionshistorie.txt enthält den Eintrag für 3.4 an oberster Stelle' {
        $vh = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Doku/Versionshistorie.txt'), [System.Text.Encoding]::UTF8)
        $vh | Should -Match 'VERSION 3\.4\s+\(\d{2}\.\d{2}\.\d{4}\)\s+MODUL TOOLS'
    }

    It 'CHANGELOG.md dokumentiert v3.4' {
        $cl = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'CHANGELOG.md'), [System.Text.Encoding]::UTF8)
        $cl | Should -Match '## v3\.4\s+\(\d{2}\.\d{2}\.\d{4}\)'
    }

    It 'Bauen.cmd enthält Commit-Nachricht für v3.4' {
        $global:V34Cmd | Should -Match '\$ver -eq ''3\.4'''
    }

    It 'Doku/Änderungen_v3.4.txt und Doku/Testmatrix_v3.4.csv existieren mit UTF-8 BOM' {
        $aePath = Join-Path $global:MinibenchRepoRoot ('Doku/' + [char]0x00C4 + 'nderungen_v3.4.txt')
        Test-Path -LiteralPath $aePath | Should -BeTrue
        $tmPath = Join-Path $global:MinibenchRepoRoot 'Doku/Testmatrix_v3.4.csv'
        Test-Path -LiteralPath $tmPath | Should -BeTrue

        $aeBytes = [IO.File]::ReadAllBytes($aePath)
        ($aeBytes[0] -eq 0xEF -and $aeBytes[1] -eq 0xBB -and $aeBytes[2] -eq 0xBF) | Should -BeTrue

        $tmBytes = [IO.File]::ReadAllBytes($tmPath)
        ($tmBytes[0] -eq 0xEF -and $tmBytes[1] -eq 0xBB -and $tmBytes[2] -eq 0xBF) | Should -BeTrue
    }
}

Describe 'Modul Tools in der Benutzeroberfläche' {
    It 'DiagGui.cs deklariert navTools und ordnet es zwischen Optimierung und Sensoren ein' {
        $global:V34Gui | Should -Match 'navTools'
        $global:V34Gui | Should -Match 'navTools = ModNav\("Tools",\s*"Tools",\s*"Portable Werkzeuge und Schnellstarter",\s*UI\.IcoTools\);'
        $global:V34Gui | Should -Match 'navTools\.HasCheck = false;'
        
        $idxOpt   = $global:V34Gui.IndexOf('navOpt = ModNav')
        $idxTools = $global:V34Gui.IndexOf('navTools = ModNav')
        $idxSens  = $global:V34Gui.IndexOf('navSens = ModNav')
        ($idxOpt -lt $idxTools -and $idxTools -lt $idxSens) | Should -BeTrue
    }

    It 'DiagGui.cs registriert BuildToolsPage in den Seiten' {
        $global:V34Gui | Should -Match 'pages\.Add\(BuildToolsPage\(\)\);'
    }

    It 'DiagGui_Steuerelemente.cs definiert Icon UI.IcoTools und SecondaryButton in FluentCard' {
        $global:V34Ctrl | Should -Match 'public const string IcoTools\s*=\s*"\\uE71D";'
        $global:V34Ctrl | Should -Match 'public Button SecondaryButton'
    }

    It 'DiagGui_Seiten.cs implementiert BuildToolsPage, IsUefiFirmware, StartAdminProcess und FindToolPath' {
        $global:V34Seiten | Should -Match 'Control BuildToolsPage\(\)'
        $global:V34Seiten | Should -Match 'bool IsUefiFirmware\(\)'
        $global:V34Seiten | Should -Match 'void StartAdminProcess\(string (file|path),\s*string args\)'
        $global:V34Seiten | Should -Match 'string FindToolPath\('
    }

    It 'DiagGui_Seiten.cs unterstützt Revo Uninstaller, Partition Wizard und WizTree' {
        $global:V34Seiten | Should -Match 'RevoUninstaller'
        $global:V34Seiten | Should -Match 'PartitionWizard'
        $global:V34Seiten | Should -Match 'WizTree'
    }

    It 'DiagGui_Seiten.cs unterstützt UEFI-Neustart und native Windows-Konsolen' {
        $global:V34Seiten | Should -Match 'shutdown\.exe'
        $global:V34Seiten | Should -Match '/r /fw /t 0'
        $global:V34Seiten | Should -Match 'diskmgmt\.msc'
        $global:V34Seiten | Should -Match 'devmgmt\.msc'
        $global:V34Seiten | Should -Match 'perfmon /rel'
    }

    It 'Alle Steuerelemente der Tools-Seite besitzen Tooltips' {
        $global:V34Seiten | Should -Match 'Tip\(bUefi,'
        $global:V34Seiten | Should -Match 'Tip\(bDisk,'
        $global:V34Seiten | Should -Match 'Tip\(bDev,'
        $global:V34Seiten | Should -Match 'Tip\(bRel,'
    }
}

Describe 'Optimierungen: Leos Empfehlung' {
    It 'Katalog enthält TaskbarEndTask mit Kategorie Bedienung und Vorlagen MSE' {
        $entry = Get-OptEntry 'TaskbarEndTask'
        $entry | Should -Not -BeNullOrEmpty
        $entry.Kat | Should -Be 'Bedienung'
        $entry.Vorlagen | Should -Match 'S'
        $entry.Vorlagen | Should -Match 'M'
        $entry.Vorlagen | Should -Match 'E'
        $entry.Bedingung | Should -Be 'Win11'
        $entry.Aktionen | Should -Not -BeNullOrEmpty
        $entry.Aktionen[0].Art | Should -Be 'Reg'
        $entry.Aktionen[0].Wert | Should -Be 1
    }

    It 'Katalog enthält UefiNeustart mit Vorlagen SE' {
        $entry = Get-OptEntry 'UefiNeustart'
        $entry | Should -Not -BeNullOrEmpty
        $entry.Kat | Should -Be 'Bedienung'
        $entry.Vorlagen | Should -Match 'S'
        $entry.Vorlagen | Should -Match 'E'
    }

    It 'Get-OptPreset "S" enthält TaskbarEndTask und UefiNeustart' {
        $presetS = Get-OptPreset 'S'
        $presetS | Should -Contain 'TaskbarEndTask'
        $presetS | Should -Contain 'UefiNeustart'
    }

    It 'Get-OptPreset "M" enthält TaskbarEndTask' {
        $presetM = Get-OptPreset 'M'
        $presetM | Should -Contain 'TaskbarEndTask'
    }

    It 'DiagGui.cs enthält TaskbarEndTask in defaultLeoEmpfehlung und wählt Vorlage S aus' {
        $global:V34Gui | Should -Match 'defaultLeoEmpfehlung\s*=\s*new string\[\]\s*\{[^}]+"TaskbarEndTask"'
        $global:V34Gui | Should -Match 'it\.Vorlagen\.Contains\("S"\)'
    }
}

Describe 'Interaktiver Diagnosebericht & Stil' {
    It 'HtmlBericht.ps1 definiert Get-ReportJs für Offline-Interaktivität' {
        $global:V34Html | Should -Match 'function Get-ReportJs'
        $global:V34Html | Should -Match 'switchSection'
        $global:V34Html | Should -Match 'setLevelFilter'
        $global:V34Html | Should -Match 'filterBefunde'
        $global:V34Html | Should -Match 'initBefundCounts'
    }

    It 'HtmlBericht.ps1 bindet Abschnitts-Navigation und Datenabschnitte ein' {
        $global:V34Html | Should -Match '<nav class="report-nav">'
        $global:V34Html | Should -Match 'data-section="system"'
        $global:V34Html | Should -Match 'data-section="benchmark"'
        $global:V34Html | Should -Match 'data-section="befunde"'
        $global:V34Html | Should -Match 'data-section="hardware"'
        $global:V34Html | Should -Match 'data-section="sensoren"'
    }

    It 'HtmlBericht.ps1 bindet Filter-Bar und Filter-Chips für Befunde ein' {
        $global:V34Html | Should -Match 'id="befundeTable"'
        $global:V34Html | Should -Match 'class="fchip'
    }

    It 'HtmlBericht.ps1 bindet Vergleichsdashboard-Button mit PC-Vorauswahl ein' {
        $global:V34Html | Should -Match 'href="\.\./Dashboard\.html\?system='
        $global:V34Html | Should -Match 'class="tab-btn btn-dash"'
        $dash = [IO.File]::ReadAllText((Join-Path $global:V34Src 'Bericht/Bausteine_Dashboard.ps1'), [System.Text.Encoding]::UTF8)
        $dash | Should -Match 'urlParams\.get\(''system''\)'
    }

    It 'Stil.ps1 definiert Styles für den Vergleichsdashboard-Button' {
        $global:V34Stil | Should -Match '\.btn-dash'
    }

    It 'Stil.ps1 definiert Styles für Navigation, Filter-Bar und Chart-Tooltips' {
        $global:V34Stil | Should -Match '\.report-nav'
        $global:V34Stil | Should -Match '\.tab-btn'
        $global:V34Stil | Should -Match '\.filter-bar'
        $global:V34Stil | Should -Match '\.search-input'
        $global:V34Stil | Should -Match '\.chart-tooltip'
    }

    It 'Referenz_Vergleich.ps1 generiert data-tip Attribute für Diagramme' {
        $rv = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Referenz_Vergleich.ps1'), [System.Text.Encoding]::UTF8)
        $rv | Should -Match 'data-tip='
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
