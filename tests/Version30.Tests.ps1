# Version 3.0: Dual-Runtime (pwsh/powershell), sicheres Schritt-Überspringen,
#               Frametime-Latenzen (0,1 %-Low & Mikroruckler), eingebettete Referenzen
#               und Wiederherstellung der tabellarischen Detailoptik.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $global:V30Src = $global:MinibenchSrcRoot
    $global:V30Gui = [IO.File]::ReadAllText((Join-Path $global:V30Src 'Oberflaeche/DiagGui.cs'))
    $global:V30Ver = [IO.File]::ReadAllText((Join-Path $global:V30Src 'Oberflaeche/Versionen.cs'))
    $global:V30Hist = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Doku/Versionshistorie.txt'))
    $global:V30Cmd = [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'))
    $global:V30RunCmd = [IO.File]::ReadAllText((Join-Path $global:V30Src 'LeosMinibench.cmd'))
}

Describe 'Version 3.0: Fehlerbehebung und sicheres Überspringen' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Berichtshilfen.ps1', 'Kern\Ereigniskanal.ps1' -Functions 'Invoke-Section', 'Send-StepSkipped', 'Test-SkipRequested' -Setup '
            $script:Report = New-Object System.Text.StringBuilder
            $script:Timings = New-Object System.Collections.Generic.List[object]
            $script:Tests = New-Object System.Collections.Generic.List[object]
            $script:Findings = New-Object System.Collections.Generic.List[object]
            $script:EventsSent = New-Object System.Collections.Generic.List[object]
            function Send-GuiEvent($type, $p1, $p2) { $script:EventsSent.Add("$type|$p1|$p2") }
            function Add-TestResult($name, $status, $detail) {
                $script:Tests.Add([pscustomobject]@{ Name = $name; Status = $status; Detail = $detail })
            }
            function Get-PlannedSteps { 10 }
            function Show-Overall($t) { }
            function Hide-Sub { }
            function Write-Checkpoint($a, $b) { }
            function Save-Partial { }
        '
    }

    It 'Invoke-Section besitzt den Schalter Skippable' {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput((Get-PartText 'Kern\Berichtshilfen.ps1'), [ref]$null, [ref]$null)
        $fn = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Invoke-Section' }, $true)
        $fn | Should -Not -BeNullOrEmpty
        $fn.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Skippable' } | Should -Not -BeNullOrEmpty
    }

    It 'Invoke-Section meldet SKIP_ALLOWED 1 bei überspringbaren Abschnitten' {
        Set-ModuleVar 'EventsSent' (New-Object System.Collections.Generic.List[object])
        MinibenchTest\Invoke-Section -Title 'Langwieriger Schritt' -Skippable { }
        $events = Get-ModuleVar 'EventsSent'
        $events | Should -Contain 'SKIP_ALLOWED|1|'
        $events | Should -Contain 'SKIP_ALLOWED|0|'
    }

    It 'Invoke-Section meldet SKIP_ALLOWED 0 bei nicht überspringbaren Abschnitten' {
        Set-ModuleVar 'EventsSent' (New-Object System.Collections.Generic.List[object])
        MinibenchTest\Invoke-Section -Title 'Kritische Systemerkennung' { }
        $events = Get-ModuleVar 'EventsSent'
        $events | Should -Contain 'SKIP_ALLOWED|0|'
        $events | Should -Not -Contain 'SKIP_ALLOWED|1|'
    }

    It 'Invoke-Section fängt Überspringen über Add-TestResult ohne CommandNotFoundException ab' {
        $td = Join-Path ([IO.Path]::GetTempPath()) ('mbtest_skip_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $td -Force | Out-Null
        $flag = Join-Path $td 'skip.flag'
        [IO.File]::WriteAllText($flag, '1')
        try {
            Set-ModuleVar 'CpDir' $td
            Set-ModuleVar 'Tests' (New-Object System.Collections.Generic.List[object])
            { MinibenchTest\Invoke-Section -Title 'Updates' -Skippable { throw 'Darf nicht laufen' } } | Should -Not -Throw
            $tests = @(Get-ModuleVar 'Tests')
            $tests.Count | Should -BeGreaterOrEqual 1
            $tests[0].Status | Should -Match 'BERSPRUNGEN'
        }
        finally {
            Remove-Item $td -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-Section ignoriert skip.flag bei nicht überspringbaren Schritten' {
        $td = Join-Path ([IO.Path]::GetTempPath()) ('mbtest_noskip_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $td -Force | Out-Null
        $flag = Join-Path $td 'skip.flag'
        [IO.File]::WriteAllText($flag, '1')
        try {
            Set-ModuleVar 'CpDir' $td
            $script:CritRan = $false
            MinibenchTest\Invoke-Section -Title 'Hardware-Erkennung' { $script:CritRan = $true }
            $script:CritRan | Should -BeTrue
        }
        finally {
            Remove-Item $td -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'DiagGui.cs verarbeitet SKIP_ALLOWED und steuert btnSkipStep' {
        $global:V30Gui | Should -Match 'case "SKIP_ALLOWED":\s*btnSkipStep\.Enabled\s*='
        $global:V30Gui | Should -Match 'btnSkipStep\.Enabled\s*=\s*false'
    }

    It 'Parallel.ps1 prüft Test-SkipRequested in Wait-BgJob und ruft Stop-BgJob auf' {
        $par = [IO.File]::ReadAllText((Join-Path $global:V30Src 'Kern/Parallel.ps1'))
        $par | Should -Match 'Test-SkipRequested'
        $par | Should -Match 'Stop-BgJob\s+\$j\s+''Vom Benutzer'
    }
}

Describe 'Version 3.0: Eingebettete Referenzen und Standard-Referenz' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Referenzen_Eingebettet.ps1', 'Kern\Datenordner.ps1', 'Kern\Referenz_Vergleich.ps1' -Functions 'Initialize-DbDir', 'Get-SavedReference', 'Read-JsonFile', 'ConvertTo-ValueTable'
    }

    It 'src/Kern/Referenzen_Eingebettet.ps1 enthält 5 gültige Referenzdatensätze' {
        $refs = Get-ModuleVar 'EmbeddedReferences'
        $refs | Should -Not -BeNullOrEmpty
        $refs.Count | Should -Be 5
        $refs.ContainsKey('Desktop_HighEnd.json') | Should -BeTrue
        $refs.ContainsKey('Workstation_Mobil.json') | Should -BeTrue
        $refs.ContainsKey('Desktop_Mittelklasse.json') | Should -BeTrue
        $refs.ContainsKey('MiniPC_APU.json') | Should -BeTrue
        $refs.ContainsKey('Notebook_Standard.json') | Should -BeTrue

        foreach ($k in $refs.Keys) {
            $obj = $refs[$k] | ConvertFrom-Json
            $obj.Format | Should -Be 'PC-Diagnose-DB/2'
            $obj.Werte | Should -Not -BeNullOrEmpty
        }
    }

    It 'Initialize-DbDir entpackt eingebettete Referenzen in leeres Verzeichnis' {
        $td = Join-Path ([IO.Path]::GetTempPath()) ('mbtest_db_' + [guid]::NewGuid().ToString('N'))
        try {
            Set-ModuleVar 'DbDir' $td
            MinibenchTest\Initialize-DbDir
            Test-Path $td | Should -BeTrue
            $files = @(Get-ChildItem -LiteralPath $td -Filter '*.json')
            $files.Count | Should -Be 5
        }
        finally {
            Remove-Item $td -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-SavedReference liefert Desktop_Mittelklasse als Standard wenn keine Referenz.json existiert' {
        $ref = MinibenchTest\Get-SavedReference
        $ref | Should -Not -BeNullOrEmpty
        $ref.Name | Should -Match 'Desktop Mittelklasse'
        $ref.Werte.Count | Should -BeGreaterThan 0
    }

    It 'HtmlBericht.ps1 enthält Tabellenoptik mit Messung, Wert, Index, Referenz, Vergleich, Ergebnis' {
        $html = [IO.File]::ReadAllText((Join-Path $global:V30Src 'Bericht/HtmlBericht.ps1'))
        $html | Should -Match '<th>Messung</th><th class="r">Wert</th><th>Index</th><th>Referenz</th><th>Vergleich</th><th>Ergebnis</th>'
        $html | Should -Match 'New-ProfileCards'
        $html | Should -Match 'New-BenchOverview'
        $html | Should -Match 'New-RenderChartsHtml'
    }
}

Describe 'Version 3.0: Frametime-Latenzen (0,1 %-Low und Mikroruckler)' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Grafiktest.ps1', 'Kern\Referenz_Vergleich.ps1' -Functions 'ConvertTo-RenderResult', 'Test-LowerBetterKey'
    }

    It 'Grafiktest.cs Stats() berechnet 0,1 %-Low und Mikroruckler korrekt' {
        $gCode = [IO.File]::ReadAllText((Join-Path $global:V30Src 'Kern/Grafiktest.cs'))
        $gCode | Should -Match 'r\[6\]\s*='
        $gCode | Should -Match 'r\[7\]\s*='
        $gCode | Should -Match 'stutterCount'

        $testCode = 'using System; public static class GpuStatsTest30 { public static double[] Calc(float[] times, double seconds) { double[] r = new double[8]; float[] s = (float[])times.Clone(); Array.Sort(s); int n = s.Length; r[0] = n / seconds; int idx999 = Math.Min(n - 1, Math.Max(0, (int)Math.Ceiling(n * 0.999) - 1)); double p999 = s[idx999]; r[6] = p999 > 0 ? 1000.0 / p999 : 0; int stutter = 0; for (int i = 0; i < n; i++) { if (s[i] > 50.0f) stutter++; } r[7] = (double)stutter / n * 100.0; return r; } }'
        Add-Type -TypeDefinition $testCode -Language CSharp
        # 1000 Frames: 998x 10ms, 1x 20ms, 1x 100ms
        $frames = New-Object float[] 1000
        for ($i = 0; $i -lt 998; $i++) { $frames[$i] = 10.0 }
        $frames[998] = 20.0
        $frames[999] = 100.0
        $res = [GpuStatsTest30]::Calc($frames, 10.1)

        # 0.1% low = 1000 / 20ms = 50 FPS
        [math]::Round($res[6], 1) | Should -Be 50.0
        # Stutter % = 1 / 1000 = 0.1%
        [math]::Round($res[7], 2) | Should -Be 0.10
    }

    It 'MetricDefs enthält GPU|REND01 und GPU|STUTTER als LowerBetter' {
        $mDefs = Get-ModuleVar 'MetricDefs'
        ($mDefs | Where-Object { $_.K -eq 'GPU|REND01' }) | Should -Not -BeNullOrEmpty
        ($mDefs | Where-Object { $_.K -eq 'GPU|STUTTER' }) | Should -Not -BeNullOrEmpty

        MinibenchTest\Test-LowerBetterKey 'GPU|STUTTER' | Should -BeTrue
        MinibenchTest\Test-LowerBetterKey 'GPU|REND01'  | Should -BeFalse
    }

    It 'ConvertTo-RenderResult übernimmt Low01 und Mikroruckler' {
        $mockRun = [pscustomobject]@{
            Ok = $true; Seconds = 5.0; MeasuredFrames = 500; Fps = 100.0; Low1Fps = 80.0; Low01Fps = 60.0; StutterPct = 0.5
            MedianMs = 10.0; P99Ms = 12.5; MaxMs = 60.0; Score = 9200.0; AdapterName = 'TestGPU'; RenderResolution = '1280x720'
            Error = ''; DeviceRemoved = $false; RemovedReason = ''; ImageChecks = 1; ImageErrors = 0; StepCount = 10
        }
        $r = MinibenchTest\ConvertTo-RenderResult $mockRun
        $r.Low01 | Should -Be 60.0
        $r.Mikroruckler | Should -Be 0.5
    }
}

Describe 'Version 3.0/3.1: Windows PowerShell 5.1 Runtime (keine CPU-Regression)' {
    It 'Bauen.cmd startet powershell.exe (Windows PowerShell 5.1)' {
        $global:V30Cmd | Should -Match 'WindowsPowerShell\\v1\.0\\powershell\.exe'
    }

    It 'src/LeosMinibench.cmd startet powershell.exe direkt' {
        $global:V30RunCmd | Should -Match 'start "" powershell\.exe'
    }
}

Describe 'Version 3.0: Fehlertoleranz und Edge-Cases' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Werkzeuge.ps1', 'Kern\Datenordner.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Referenz_Vergleich.ps1' -Functions 'Get-VerifiedTool', 'Get-DbEntries', 'Resolve-DataDir', 'Test-WritableDir', 'Read-JsonFile', 'ConvertTo-ValueTable'
    }

    It 'Get-VerifiedTool fängt fehlende Hilfstools ohne Ausnahme ab' {
        $td = Join-Path ([IO.Path]::GetTempPath()) ('mbtest_tools_' + [guid]::NewGuid().ToString('N'))
        try {
            $res = MinibenchTest\Get-VerifiedTool 'NichtVorhandenesTool' -ToolsDir $td
            $res | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item $td -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-DbEntries überspringt defekte JSON-Dateien tolerant' {
        $td = Join-Path ([IO.Path]::GetTempPath()) ('mbtest_corruptdb_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $td -Force | Out-Null
        try {
            # 1 gesunde Datei
            $validJson = '{"Format":"PC-Diagnose-DB/2","Computer":"TEST-OK","Datum":"2026-10-05","Werte":{"CPU|ST":150}}'
            [IO.File]::WriteAllText((Join-Path $td 'ok.json'), $validJson)
            # 1 defekte Datei
            [IO.File]::WriteAllText((Join-Path $td 'bad.json'), '{"Format": "PC-Diagnose-DB/2", KORRUPT!')

            Set-ModuleVar 'DbDir' $td
            $entries = @(MinibenchTest\Get-DbEntries)
            $entries.Count | Should -Be 1
            $entries[0].Computer | Should -Be 'TEST-OK'
        }
        finally {
            Remove-Item $td -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Resolve-DataDir fällt bei schreibgeschütztem Pfad auf Dokumente zurück' {
        $doc = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Leos Minibench'
        $src = [IO.File]::ReadAllText((Join-Path $global:V30Src 'Kern/Datenordner.ps1'))
        $src | Should -Match 'MyDocuments'
        $src | Should -Match '\$script:DataDirFallback\s*=\s*\$true'
    }
}

Describe 'Version 3.0: Gesamtzusammenbau und C#-Kompilierung' {
    It 'Versionsnummer ist 3.0 oder 3.1 in Version.ps1, Versionen.cs und Versionshistorie.txt' {
        $vPs1 = [IO.File]::ReadAllText((Join-Path $global:V30Src 'Kern/Version.ps1'))
        $vPs1 | Should -Match '\$ScriptVersion\s*=\s*''(3\.0|3\.1|3\.1\.1|3\.2|3\.3|3\.31|3\.32|3\.4|3\.5|3\.51)'''
        $global:V30Ver | Should -Match 'new Eintrag\("(3\.0|3\.1|3\.1\.1|3\.2|3\.3|3\.31|3\.32|3\.4|3\.5|3\.51)"'
        $global:V30Hist | Should -Match 'VERSION (3\.0|3\.1|3\.1\.1|3\.2|3\.3|3\.31|3\.32|3\.4|3\.5|3\.51)'
    }

    It 'Änderungsdatei und Testmatrix für Version existieren' {
        $b = Get-MinibenchBuild
        $b.Version | Should -Match '^(3\.0|3\.1|3\.1\.1|3\.2|3\.3|3\.31|3\.32|3\.4|3\.5|3\.51)$'
        $aePath = Join-Path $global:MinibenchRepoRoot ('Doku/' + [char]0x00C4 + ('nderungen_v{0}.txt' -f $b.Version))
        Test-Path -LiteralPath $aePath | Should -BeTrue
        Join-Path $global:MinibenchRepoRoot ('Doku/Testmatrix_v{0}.csv' -f $b.Version) | Should -Exist
    }

    It 'Oberfläche lässt sich als Gesamtheit fehlerfrei kompilieren' {
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGui30_' + [guid]::NewGuid().ToString('N') + '.dll')
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
        $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGpu30_' + [guid]::NewGuid().ToString('N') + '.dll')
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
}
