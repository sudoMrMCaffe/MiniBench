# Version 3.1: Bugfixes (Vergleichsseite, Referenzdaten, CPU-Regression, GPU-Fehler)

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $global:V31Src = $global:MinibenchSrcRoot
    $global:V31Gui = [IO.File]::ReadAllText((Join-Path $global:V31Src 'Oberflaeche/DiagGui.cs'))
    $global:V31Ver = [IO.File]::ReadAllText((Join-Path $global:V31Src 'Oberflaeche/Versionen.cs'))
    $global:V31Hist = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Doku/Versionshistorie.txt'))
    $global:V31Cmd = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'))
    $global:V31RunCmd = [IO.File]::ReadAllText((Join-Path $global:V31Src 'LeosMinibench.cmd'))
    $global:V31Modelle = [IO.File]::ReadAllText((Join-Path $global:V31Src 'Oberflaeche/DiagGui_Modelle.cs'))
    $global:V31GpuCs = [IO.File]::ReadAllText((Join-Path $global:V31Src 'Kern/Grafiktest.cs'))
    $global:V31GpuPs1 = [IO.File]::ReadAllText((Join-Path $global:V31Src 'Kern/Grafiktest.ps1'))
}

Describe 'Version 3.1: Referenzdaten und JSON-Parsing (BUG 1 & BUG 2)' {
    It 'JavaScriptSerializer deserialisiert alle Referenz-JSON-Dateien fehlerfrei' {
        Add-Type -AssemblyName System.Web.Extensions
        $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $js.MaxJsonLength = [int]::MaxValue

        $refDir = Join-Path $global:V31Src 'Daten/Referenzen'
        Test-Path -LiteralPath $refDir | Should -BeTrue
        $files = @(Get-ChildItem -LiteralPath $refDir -Filter '*.json')
        $files.Count | Should -BeGreaterOrEqual 5

        foreach ($f in $files) {
            $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
            $dict = $js.DeserializeObject($text)
            $dict | Should -Not -BeNullOrEmpty -Because $f.Name
            $dict['Format'] | Should -Be 'PC-Diagnose-DB/2' -Because $f.Name
            $dict['Name'] | Should -Not -BeNullOrEmpty -Because $f.Name
            $dict['Computer'] | Should -Not -BeNullOrEmpty -Because $f.Name
            $dict['Datum'] | Should -Not -BeNullOrEmpty -Because $f.Name
            $dict['Hardware'] | Should -Not -BeNullOrEmpty -Because $f.Name
            $dict['Werte'] | Should -Not -BeNullOrEmpty -Because $f.Name
        }
    }

    It 'DbEntry.Load liest alle Referenz-JSON-Dateien ein' {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $src = @($files | ForEach-Object { [IO.File]::ReadAllText($_) }) -join [Environment]::NewLine
        $refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
        Add-Type -TypeDefinition $src -ReferencedAssemblies $refs -IgnoreWarnings

        $refDir = Join-Path $global:V31Src 'Daten/Referenzen'
        $entries = [DbEntry]::Load($refDir)
        $entries.Count | Should -BeGreaterOrEqual 5
        foreach ($e in $entries) {
            $e.Name | Should -Not -BeNullOrEmpty
            $e.Computer | Should -Not -BeNullOrEmpty
            $e.Cpu | Should -Not -BeNullOrEmpty
            $e.Werte.Count | Should -BeGreaterThan 0
        }
    }

    It 'DbEntry.Load protokolliert Fehler im catch-Block' {
        $global:V31Modelle | Should -Match 'catch\s*\(\s*Exception\s+\w+\s*\)'
        $global:V31Modelle | Should -Match 'System\.Diagnostics\.Debug\.WriteLine'
    }
}

Describe 'Version 3.1: Eingebettete Referenzen im Build (BUG 2)' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Referenzen_Eingebettet.ps1', 'Kern\Datenordner.ps1' -Functions 'Initialize-DbDir'
    }

    It 'Referenzen_Eingebettet.ps1 ist im Bauplan eingebunden' {
        $plan = [IO.File]::ReadAllText((Join-Path $global:V31Src 'Bauplan.txt'))
        $plan | Should -Match 'Kern[/\\]Referenzen_Eingebettet\.ps1'
    }

    It 'Zusammenbau.ps1 enthält Update-EmbeddedReferences' {
        $zb = [IO.File]::ReadAllText((Join-Path $global:V31Src 'Zusammenbau.ps1'))
        $zb | Should -Match 'function Update-EmbeddedReferences'
        $zb | Should -Match 'Update-EmbeddedReferences\s+\$SrcDir'
    }

    It 'Initialize-DbDir entpackt eingebettete Referenzen in leeren Ordner' {
        $td = Join-Path ([IO.Path]::GetTempPath()) ('mbtest_embed_' + [guid]::NewGuid().ToString('N'))
        try {
            Set-ModuleVar 'DbDir' $td
            MinibenchTest\Initialize-DbDir
            Test-Path -LiteralPath $td | Should -BeTrue
            $files = @(Get-ChildItem -LiteralPath $td -Filter '*.json')
            $files.Count | Should -Be 5
        }
        finally {
            Remove-Item $td -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Version 3.1: Beseitigung der CPU-Regression (BUG 3)' {
    It 'Bauen.cmd startet strikt powershell.exe (Windows PowerShell 5.1)' {
        $global:V31Cmd | Should -Match 'WindowsPowerShell\\v1\.0\\powershell\.exe'
        $global:V31Cmd | Should -Not -Match 'PowerShell\\7\\pwsh\.exe'
    }

    It 'src/LeosMinibench.cmd startet powershell.exe direkt ohne pwsh-Suche' {
        $global:V31RunCmd | Should -Match 'start "" powershell\.exe'
        $global:V31RunCmd | Should -Not -Match 'where\.exe\s+pwsh\.exe'
    }
}

Describe 'Version 3.1: Grafik-Benchmark Robustheit bei niedrigen Bildraten (BUG 4)' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Grafiktest.ps1' -Functions 'ConvertTo-RenderResult'
    }

    It 'Grafiktest.cs überspringt Statistik bei niedriger Bildrate nicht' {
        $global:V31GpuCs | Should -Match 'lastMs\s*<\s*20\.0'
        $global:V31GpuCs | Should -Not -Match 'r\.skipStats\s*=\s*Math\.Max\(r\.skipStats,\s*1\);'
    }

    It 'Grafiktest.cs Summarize() hat Fallback bei MeasuredFrames > 0' {
        $global:V31GpuCs | Should -Match 'if\s*\(st\[1\]\s*<=\s*0\s*&&\s*r\.AvgFps\s*>\s*0\)\s*st\[1\]\s*=\s*r\.AvgFps;'
    }

    It 'Grafiktest.cs Adapters() bricht nicht bei einzelnem Adapterfehler ab' {
        $global:V31GpuCs | Should -Match 'if\s*\(hr\s*==\s*DXGI_ERROR_NOT_FOUND\)\s*break;\s*if\s*\(hr\s*<\s*0\)\s*continue;'
    }

    It 'Grafiktest.cs unterstützt Feature-Level 11_1 und 9_3 mit Adapter-Fallback' {
        $global:V31GpuCs | Should -Match '0xB100'
        $global:V31GpuCs | Should -Match '0x9300'
        $global:V31GpuCs | Should -Match 'D3D11CreateDevice\(IntPtr\.Zero'
    }

    It 'ConvertTo-RenderResult hat defensive Fallbacks für Low1, Median und MaxMs' {
        $mockLowFps = [pscustomobject]@{
            Ok = $true; Seconds = 10.0; MeasuredFrames = 50; AvgFps = 5.0; Low1Fps = 0.0; Low01Fps = 0.0; StutterPct = 100.0
            MedianMs = 0.0; P99Ms = 0.0; MaxMs = 0.0; Score = 460.0; AdapterName = 'Intel(R) UHD Graphics 620'; Width = 1280; Height = 720
            Error = ''; DeviceRemoved = $false; RemovedReason = ''; ImageChecks = 1; ImageErrors = 0; FeatureLevel = '11_0'
            FpsPerSecond = @(5.0); FrameMs = @(); EscPressed = $false; RefHash = 'hash'
        }
        $r = MinibenchTest\ConvertTo-RenderResult $mockLowFps ([pscustomobject]@{ Name = 'Intel(R) UHD Graphics 620'; Art = 'iGPU'; Bezeichnung = ''; Index = 0 })
        $r.Fps | Should -Be 5.0
        $r.Low1 | Should -Be 5.0
        $r.Low01 | Should -Be 5.0
        $r.MedianMs | Should -Be 200.0
        $r.P99Ms | Should -Be 200.0
        $r.MaxMs | Should -Be 200.0
    }
}

Describe 'Version 3.1: Release und Dokumentation' {
    It 'Versionsnummer ist 3.1 in Version.ps1, Versionen.cs und Versionshistorie.txt' {
        $vPs1 = [IO.File]::ReadAllText((Join-Path $global:V31Src 'Kern/Version.ps1'))
        $vPs1 | Should -Match '\$ScriptVersion\s*=\s*''(3\.1(\.1)?|3\.2|3\.3|3\.31)'''
        $firstVer = [regex]::Match($global:V31Ver, 'new Eintrag\("([^"]+)"').Groups[1].Value
        $firstVer | Should -Match '^(3\.1(\.1)?|3\.2|3\.3|3\.31)$'
        $global:V31Hist | Should -Match 'VERSION (3\.1|3\.2|3\.3|3\.31)'
    }

    It 'Änderungsdatei und Testmatrix für Version 3.1 existieren' {
        $b = Get-MinibenchBuild
        $b.Version | Should -Match '^(3\.1(\.1)?|3\.2|3\.3|3\.31)$'
        $aePath = Join-Path $global:MinibenchRepoRoot ('Doku/' + [char]0x00C4 + ('nderungen_v{0}.txt' -f $b.Version))
        Test-Path -LiteralPath $aePath | Should -BeTrue
        Join-Path $global:MinibenchRepoRoot ('Doku/Testmatrix_v{0}.csv' -f $b.Version) | Should -Exist
    }

    It 'Oberfläche lässt sich als Gesamtheit fehlerfrei kompilieren' {
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGui31_' + [guid]::NewGuid().ToString('N') + '.dll')
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

    It 'Grafiktest.cs lässt sich fehlerfrei kompilieren' {
        $file = Join-Path (Join-Path $global:MinibenchSrcRoot 'Kern') 'Grafiktest.cs'
        $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGpu31_' + [guid]::NewGuid().ToString('N') + '.dll')
        try {
            if ($env:OS -eq 'Windows_NT') {
                $code = 'Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $src = [IO.File]::ReadAllText(''' + $file + '''); ' +
                    '$refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location); ' +
                    ('try {{ Add-Type -TypeDefinition $src -ReferencedAssemblies $refs -OutputAssembly ''{0}'' -OutputType Library -IgnoreWarnings -ErrorAction Stop; exit 0 }} catch {{ Write-Output $_.Exception.Message; exit 1 }}' -f $out)
                $msg = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $code
                $LASTEXITCODE | Should -Be 0 -Because ($msg -join ' ')
            }
        }
        finally {
            Remove-Item $out -Force -ErrorAction SilentlyContinue
        }
    }

    It 'README.md und CHANGELOG.md sind auf Version 3.1 aktualisiert' {
        $rm = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'README.md'))
        $rm | Should -Match 'https://img\.shields\.io/badge/Version-3\.[123](\.1)?-'
        $rm | Should -Match 'Download-LeosMinibench\.exe%20\(v3\.[123](\.1)?\)'
        $cl = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'CHANGELOG.md'))
        $cl | Should -Match '## v3\.[123]'
    }

    It 'Bauen.cmd aktualisiert README.md automatisch' {
        $global:V31Cmd | Should -Match 'README\.md'
        $global:V31Cmd | Should -Match 'badge/Version-'
        $global:V31Cmd | Should -Match 'Download-LeosMinibench'
    }
}

