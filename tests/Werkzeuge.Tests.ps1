# Werkzeug-Manifest: nur Dateien mit passendem SHA-256 werden ausgeführt
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Parts 'Kern\Werkzeuge.ps1'
    function New-ToolsDir {
        $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $d 'smartmontools/bin') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $d 'smartmontools/bin/smartctl.exe') -Value 'Originaldatei' -NoNewline
        & (Get-Module MinibenchTest) { $script:ToolIssues.Clear() }
        return $d
    }
}

Describe 'SHA-256' {
    It 'entspricht dem Prüfwert aus FIPS 180-2 für "abc"' {
        $f = Join-Path $TestDrive 'abc.txt'; [IO.File]::WriteAllText($f, 'abc')
        MinibenchTest\Get-FileSha256 $f | Should -Be 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    }
}

Describe 'Manifest' {
    BeforeEach { $tools = New-ToolsDir; $exe = Join-Path $tools 'smartmontools/bin/smartctl.exe' }
    It 'nimmt eine Datei auf und gibt sie danach frei' {
        $e = MinibenchTest\Register-Tool -Name 'smartctl' -Path $exe -Lizenz 'GPL-2.0-or-later' -Quelle 'winget' -ToolsDir $tools
        $e.SHA256 | Should -Be (MinibenchTest\Get-FileSha256 $exe)
        $e.Datei | Should -Be ([IO.Path]::Combine('smartmontools', 'bin', 'smartctl.exe'))
        MinibenchTest\Get-VerifiedTool 'smartctl' $tools | Should -Be (Join-Path $tools $e.Datei)
        $j = Get-Content (Join-Path $tools 'Tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $j.Format | Should -Be 'Minibench-Tools/1'
        $j.Werkzeuge[0].Lizenz | Should -Be 'GPL-2.0-or-later'
    }
    It 'sperrt eine veränderte Datei und meldet das' {
        [void](MinibenchTest\Register-Tool -Name 'smartctl' -Path $exe -ToolsDir $tools)
        Set-Content -LiteralPath $exe -Value 'ausgetauscht' -NoNewline
        MinibenchTest\Get-VerifiedTool 'smartctl' $tools | Should -BeNullOrEmpty
        (Get-ModuleVar 'ToolIssues') -join ' ' | Should -Match 'passt nicht zum Manifest'
    }
    It 'meldet eine fehlende Datei' {
        [void](MinibenchTest\Register-Tool -Name 'smartctl' -Path $exe -ToolsDir $tools)
        Remove-Item $exe
        MinibenchTest\Get-VerifiedTool 'smartctl' $tools | Should -BeNullOrEmpty
        (Get-ModuleVar 'ToolIssues') -join ' ' | Should -Match 'fehlt'
    }
    It 'gibt ohne Manifesteintrag nichts frei' {
        MinibenchTest\Get-VerifiedTool 'smartctl' $tools | Should -BeNullOrEmpty
    }
    It 'gibt bei beschädigtem Manifest nichts frei' {
        [void](MinibenchTest\Register-Tool -Name 'smartctl' -Path $exe -ToolsDir $tools)
        Set-Content (Join-Path $tools 'Tools.json') '{ kaputt'
        MinibenchTest\Get-VerifiedTool 'smartctl' $tools | Should -BeNullOrEmpty
        (Get-ModuleVar 'ToolIssues') -join ' ' | Should -Match 'nicht lesbar'
    }
    It 'nimmt nur Dateien aus dem Tools-Ordner auf' {
        $fremd = Join-Path $TestDrive 'fremd.exe'; Set-Content $fremd 'x'
        { MinibenchTest\Register-Tool -Name 'fremd' -Path $fremd -ToolsDir $tools } | Should -Throw '*nicht im Tools-Ordner*'
    }
    It 'ersetzt beim erneuten Aufnehmen den alten Eintrag' {
        [void](MinibenchTest\Register-Tool -Name 'smartctl' -Path $exe -ToolsDir $tools)
        Set-Content -LiteralPath $exe -Value 'neue Version' -NoNewline
        [void](MinibenchTest\Register-Tool -Name 'smartctl' -Path $exe -ToolsDir $tools)
        @((Get-Content (Join-Path $tools 'Tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json).Werkzeuge).Count | Should -Be 1
        MinibenchTest\Get-VerifiedTool 'smartctl' $tools | Should -Not -BeNullOrEmpty
    }
}

Describe 'Übergang von 2.1' {
    It 'übernimmt ein vorhandenes smartctl.exe einmalig und vermerkt die Herkunft' {
        $tools = New-ToolsDir
        $e = MinibenchTest\Register-LegacyTool 'smartctl' @('smartmontools/bin/smartctl.exe', 'smartctl.exe') 'GPL-2.0-or-later' 'winget' $tools
        $e.Herkunft | Should -Match '2\.1'
        MinibenchTest\Register-LegacyTool 'smartctl' @('smartmontools/bin/smartctl.exe') 'GPL' 'winget' $tools | Should -BeNullOrEmpty
    }
    It 'tut nichts, wenn kein Werkzeug da ist' {
        $tools = Join-Path $TestDrive 'leer'; New-Item -ItemType Directory $tools -Force | Out-Null
        MinibenchTest\Register-LegacyTool 'smartctl' @('smartctl.exe') 'GPL' 'winget' $tools | Should -BeNullOrEmpty
        Join-Path $tools 'Tools.json' | Should -Not -Exist
    }
}
