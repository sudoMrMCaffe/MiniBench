# Version 2.67: Lasttest auf ULB-PC10039 am 03.10.2026 mit 2.66 weiter ungleichmäßig (33 Unterbrechungen über 50 ms in
# 34 s, je eine pro Speicherbereinigung). CPU- und RAM-Last laufen jetzt in einem eigenen Prozess ohne Speicher-
# bereinigung, die Lastschleifen enthalten keine Aufrufe mehr.

Describe 'Lastschleifen ohne Aufrufe' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        $script:Cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Testroutinen.cs'))
        # Text einer Methode bis zur nächsten Methode der Klasse
        function Get-Method([string]$Head) {
            $i = $script:Cs.IndexOf($Head); $i | Should -BeGreaterThan 0
            $j = $script:Cs.IndexOf('[MethodImpl', $i + 10); if ($j -lt 0) { $j = $i + 3000 }
            $k = $script:Cs.IndexOf('public static ulong Work(', $i + 10); if ($k -gt 0 -and $k -lt $j) { $j = $k }
            return $script:Cs.Substring($i, $j - $i)
        }
    }
    It 'CPU-Rechenschleife ohne Math.Sin und ohne BitConverter' {
        $m = Get-Method 'public static void WorkPart('
        $m | Should -Not -Match 'Math\.Sin'
        $m | Should -Not -Match 'BitConverter'
        $m | Should -Match 'bits\.D = xx;'
    }
    It 'RAM-Muster ohne Aufruf je Wert' {
        (Get-Method 'static void FillSlice(') | Should -Not -Match 'Expected\('
        (Get-Method 'static void VerifySlice(') | Should -Not -Match 'Expected\('
        $script:Cs | Should -Not -Match 'static ulong Expected\('
    }
    It 'Sinus als Polynom: höchstens 0,001 Abweichung über den ganzen Wertebereich der Rechnung' {
        if (-not ('DiagLoadHost' -as [type])) { Add-Type -TypeDefinition $script:Cs }
        # Polynom aus WorkPart nachgerechnet
        $max = 0.0
        foreach ($x in @(-1.0, -0.3, 0.0, 0.5, 1.5, 3.1, 3.2, 6.2, 6.3, 10.0, 100.7, 1224.9)) {
            $r = $x - 6.283185307179586 * [double][long][math]::Truncate($x * 0.15915494309189535)
            if ($r -gt [math]::PI) { $r -= 2 * [math]::PI } elseif ($r -lt -[math]::PI) { $r += 2 * [math]::PI }
            $r2 = $r * $r
            $s = $r * (1.0 - $r2 * (1.0 / 6.0 - $r2 * (1.0 / 120.0 - $r2 * (1.0 / 5040.0 - $r2 * (1.0 / 362880.0 - $r2 * (1.0 / 39916800.0))))))
            $max = [math]::Max($max, [math]::Abs($s - [math]::Sin($x)))
        }
        $max | Should -BeLessThan 0.001
    }
    It 'Rechendurchlauf bleibt deterministisch' {
        if (-not ('DiagLoadHost' -as [type])) { Add-Type -TypeDefinition $script:Cs }
        [DiagCpu]::Work(5) | Should -Be ([DiagCpu]::Work(5))
        [DiagCpu]::Work(5) | Should -Not -Be ([DiagCpu]::Work(6))
    }
}

Describe 'Last im eigenen Prozess (LoadJob, DiagLoadHost)' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        # als Datei übersetzen, wie Add-CachedType im Datenordner: der Lastprozess lädt dieselbe Bibliothek
        $base = Join-Path ([IO.Path]::GetTempPath()) 'LeosMinibench-Tests-Last'
        Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $script:Dir = Join-Path $base ([guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
        $script:Dll = Join-Path $script:Dir 'Last.dll'
        $exe = $(if ($PSVersionTable.PSEdition -eq 'Core') { if ([IO.Path]::DirectorySeparatorChar -eq '\') { 'pwsh.exe' } else { 'pwsh' } } else { 'powershell.exe' })
        $script:Host1 = Join-Path $PSHOME $exe
        # Bibliothek in einem eigenen Prozess übersetzen: Sind die Typen hier schon geladen, lehnt Add-Type eine zweite
        # Übersetzung ab. Der Lastprozess lädt diese Datei.
        $src = (Join-Path $global:MinibenchSrcRoot 'Kern/Testroutinen.cs').Replace("'", "''")
        $cmd = "Add-Type -TypeDefinition ([IO.File]::ReadAllText('$src')) -OutputAssembly '$($script:Dll.Replace("'", "''"))' -OutputType Library"
        & $script:Host1 -NoProfile -NonInteractive -EncodedCommand ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))) | Out-Null
        if (-not ('LoadJob' -as [type])) { Add-Type -Path $script:Dll }
    }
    It 'CPU-Last läuft im eigenen Prozess, meldet Durchläufe und endet auf Stopp' {
        $j = [LoadJob]::Start('cpu', $script:Host1, $script:Dll, (Join-Path $script:Dir 'cpu'), 60, 2, 0, 0, $false)
        $j.External | Should -BeTrue
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 500; $j.Refresh(); if ($j.Count -ge 20) { break } }
        $j.Count | Should -BeGreaterOrEqual 20
        $j.Errors | Should -Be 0
        $j.Stop()
        $j.Wait(15000) | Should -BeTrue
        $j.Done | Should -BeTrue
        $j.ExitCode | Should -Be 0
        $j.Note | Should -BeNullOrEmpty
        # im Lastprozess keine Speicherbereinigung und keine Unterbrechung
        $j.Pause.Count | Should -Be 6
        $j.Pause[0] | Should -Be 0
        $j.Pause[3] | Should -Be 0
    }
    It 'RAM-Last im eigenen Prozess mit Ergebnistext' {
        $j = [LoadJob]::Start('ram', $script:Host1, $script:Dll, (Join-Path $script:Dir 'ram'), 60, 2, 256MB, 2, $true)
        $j.External | Should -BeTrue
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 500; $j.Refresh(); if ($j.Count -ge 256MB) { break } }
        $j.Count | Should -Be 256MB
        $j.Stop()
        $j.Wait(30000) | Should -BeTrue
        $j.Result | Should -Match 'Fehler\s+: 0'
    }
    It 'Endet der Arbeitsprozess-Ersatz ohne Status, läuft die Last im Arbeitsprozess weiter' {
        $j = [LoadJob]::Start('cpu', (Join-Path $script:Dir 'fehlt.exe'), $script:Dll, (Join-Path $script:Dir 'cpu2'), 2, 1, 0, 0, $false)
        $j.External | Should -BeFalse
        $j.Note | Should -Match 'eigener Lastprozess nicht möglich'
        $j.Wait(30000) | Should -BeTrue
        $j.Count | Should -BeGreaterThan 0
    }
    It 'Endet der Lastprozess vor der ersten Meldung (kaputte Bibliothek), übernimmt der Arbeitsprozess' {
        $bad = Join-Path $script:Dir 'kaputt.dll'
        [IO.File]::WriteAllText($bad, 'keine Bibliothek')
        $j = [LoadJob]::Start('cpu', $script:Host1, $bad, (Join-Path $script:Dir 'cpu3'), 2, 1, 0, 0, $false)
        $j.External | Should -BeTrue
        $j.Wait(60000) | Should -BeTrue
        $j.External | Should -BeFalse
        # Fehlertext von Add-Type je nach Sprache von Windows (Bad IL format, Assemblymanifest erwartet): nur Rahmen prüfen
        $j.Note | Should -Match 'Lastprozess endete ohne Ergebnis \(Exitcode 2, .*kaputt\.dll.*\), Last läuft im Arbeitsprozess'
        $j.Count | Should -BeGreaterThan 0
    }
    It 'nach Stop startet ein gescheiterter Lastprozess keine Last im Arbeitsprozess nach' {
        $bad = Join-Path $script:Dir 'kaputt2.dll'
        [IO.File]::WriteAllText($bad, 'keine Bibliothek')
        $j = [LoadJob]::Start('cpu', $script:Host1, $bad, (Join-Path $script:Dir 'cpu5'), 30, 1, 0, 0, $false)
        $j.Stop()
        $j.Wait(60000) | Should -BeTrue
        $j.External | Should -BeTrue
        $j.Count | Should -Be 0
        $j.Note | Should -Match 'Lastprozess endete ohne Ergebnis'
        $j.Cleanup()
        Test-Path -LiteralPath (Join-Path $script:Dir 'cpu5') | Should -BeFalse
    }
    It 'Statuszeile mit Prüfsumme: abgeschnittene oder veränderte Zeilen werden verworfen' {
        $ok = 'L1;5;0;100;0;0;0;0;0;0;0;0;105;'
        $v = [DiagLoadHost]::ParseStatus($ok)
        $v[2] | Should -Be 100
        [DiagLoadHost]::ParseStatus('L1;5;0;100;0;0;0;0;0;0;0;0;106;') | Should -BeNullOrEmpty
        [DiagLoadHost]::ParseStatus('L1;5;0;10') | Should -BeNullOrEmpty
        [DiagLoadHost]::ParseStatus('') | Should -BeNullOrEmpty
    }
    It 'Lasttest startet die Last über Start-LoadJob und räumt den Lastprozess auf' {
        $l = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Lasttest/Ablauf.ps1'))
        $l | Should -Match "\`$cpuTask = Start-LoadJob 'cpu'"
        $l | Should -Match "\`$ramTask = Start-LoadJob 'ram'"
        $l | Should -Match 'if \(-not \$lj\.Wait\(5000\)\) \{ \$lj\.Kill\(\) \}'
        $l | Should -Not -Match '\[DiagCpu\]::RunAsync'
        $l | Should -Match '\$lj\.Cleanup\(\)'
        # ab v2.7 ohne CPU-Test in der Diagnose: dort darf keine Last mehr starten
        $d = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Module/Diagnose/Ablauf.ps1'))
        $d | Should -Not -Match 'Start-LoadJob'
        $d | Should -Not -Match '\[DiagCpu\]::RunAsync'
    }
}

Describe 'Rückstandskontrolle: Ordner der Lastprozesse' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Functions 'Test-TempEntryStale'
    }
    It 'Ordner eines beendeten Laufs ist veraltet, der eigene nicht' {
        MinibenchTest\Test-TempEntryStale 'Last_999999_cpu_638950000000000000' | Should -BeTrue
        MinibenchTest\Test-TempEntryStale ('Last_{0}_ram_638950000000000000' -f $PID) | Should -BeFalse
        MinibenchTest\Test-TempEntryStale 'Lauf_999999' | Should -BeFalse
    }
}
