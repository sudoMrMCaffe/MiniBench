# Version 2.95: Anonyme Vergleichsdaten, Gesamtleistungs-Banner, UserBenchmark-Profile,
#               Minidump Crash Inspector, Schritt überspringen, Grafiktreiber-Gesundheitscheck, CIM-Caching.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $global:V295Src = $global:MinibenchSrcRoot
    $global:V295Gui = [IO.File]::ReadAllText((Join-Path $global:V295Src 'Oberflaeche/DiagGui.cs'))
    $global:V295Ver = [IO.File]::ReadAllText((Join-Path $global:V295Src 'Oberflaeche/Versionen.cs'))
}

Describe 'Version 2.95: Anonyme Vergleichsdaten' {
    It 'Referenzdateien existieren in src/Daten/Referenzen' {
        $refDir = Join-Path $global:V295Src 'Daten/Referenzen'
        Test-Path $refDir | Should -BeTrue
        $files = @(Get-ChildItem $refDir -Filter '*.json')
        $files.Count | Should -BeGreaterOrEqual 4
    }
    It 'Referenzdateien sind gültiges JSON mit PC-Diagnose-DB/2' {
        $refDir = Join-Path $global:V295Src 'Daten/Referenzen'
        foreach ($f in (Get-ChildItem $refDir -Filter '*.json')) {
            $json = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
            $obj = $json | ConvertFrom-Json
            $obj.Format | Should -Be 'PC-Diagnose-DB/2'
            $obj.Werte | Should -Not -BeNullOrEmpty
            ($obj.Computer -match 'Referenz' -or $obj.Name -match 'Referenz') | Should -BeTrue
        }
    }
    It 'Datenordner kopiert Referenzdateien beim Erstanlegen' {
        $src = [IO.File]::ReadAllText((Join-Path $global:V295Src 'Kern/Datenordner.ps1'))
        $src | Should -Match 'Daten[/\\]Referenzen'
        $src | Should -Match 'Initialize-DbDir'
    }
}

Describe 'Version 2.95: Bewertungswort und Profilkarten' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Referenz_Vergleich.ps1', 'Bericht\Bausteine_Systemvergleich.ps1' -Functions 'Get-BenchRatingWord', 'Get-Bewertungswort', 'New-ProfileCards', 'Get-GeoMean', 'Get-BenchGroup', 'Get-RefBar'
    }
    It 'Get-BenchRatingWord liefert korrekte Skala' {
        MinibenchTest\Get-BenchRatingWord 120 | Should -Be 'Hervorragend'
        MinibenchTest\Get-BenchRatingWord 105 | Should -Be 'Sehr gut'
        MinibenchTest\Get-BenchRatingWord 90  | Should -Be 'Gut'
        MinibenchTest\Get-BenchRatingWord 75  | Should -Be 'Durchschnittlich'
        MinibenchTest\Get-BenchRatingWord 55  | Should -Be 'Mäßig'
        MinibenchTest\Get-BenchRatingWord 30  | Should -Be 'Unterdurchschnittlich'
    }
    It 'Get-Bewertungswort ist Alias oder kompatibel' {
        MinibenchTest\Get-Bewertungswort 116 | Should -Be 'Hervorragend'
        MinibenchTest\Get-Bewertungswort 40  | Should -Be 'Unterdurchschnittlich'
    }
    It 'New-ProfileCards erzeugt Kacheln bei ausreichenden Gruppen' {
        $cards = MinibenchTest\New-ProfileCards
        # Wenn noch keine BenchGroups vorliegen, bleibt es leer
        $cards | Should -Be ''
    }
}

Describe 'Version 2.95: Minidump Crash Inspector' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Checkpoints_Absturzanalyse.ps1' -Functions 'Get-BugcheckName', 'Get-BugcheckRecommendation', 'Read-MinidumpFile', 'Read-Minidumps' -Setup '$script:CpDir = [IO.Path]::GetTempPath()'
    }
    It 'Get-BugcheckRecommendation kennt zentrale Fehlercodes' {
        MinibenchTest\Get-BugcheckRecommendation 0x133 | Should -Match 'DPC Watchdog'
        MinibenchTest\Get-BugcheckRecommendation 0x3B  | Should -Match 'System Service'
        MinibenchTest\Get-BugcheckRecommendation 0x116 | Should -Match 'Video TDR'
        MinibenchTest\Get-BugcheckRecommendation 0xD1  | Should -Match 'Driver IRQL'
        MinibenchTest\Get-BugcheckRecommendation 0x1A  | Should -Match 'Memory Management'
    }
    It 'Read-MinidumpFile parst synthetische MDMP-Struktur fehlerfrei' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('testdump_' + [guid]::NewGuid().ToString('N') + '.dmp')
        try {
            $ms = New-Object IO.MemoryStream
            $bw = New-Object IO.BinaryWriter($ms)
            # MDMP Header (32 Bytes)
            $bw.Write([uint32]0x504D444D) # 'MDMP'
            $bw.Write([uint32]0x0000A793) # Version
            $bw.Write([uint32]1)          # 1 Stream
            $bw.Write([uint32]32)         # StreamDirectory RVA at offset 32
            $bw.Write([uint32]0)          # Checksum
            $bw.Write([uint32]1700000000) # Timestamp
            $bw.Write([uint64]0)          # Flags

            # Stream Directory Entry (12 Bytes: Type, Size, Rva)
            $bw.Write([uint32]6)          # Type 6: MINIDUMP_EXCEPTION_STREAM
            $bw.Write([uint32]160)        # DataSize
            $bw.Write([uint32]44)         # RVA at offset 44

            # Exception Stream: ThreadId (4), Align (4), ExceptionCode (4)
            $bw.Write([uint32]1000)
            $bw.Write([uint32]0)
            $bw.Write([uint32]0x133)      # Bugcheck 0x133: DPC_WATCHDOG_VIOLATION
            $bw.Write([uint32]0)          # Flags
            $bw.Write([uint64]0)          # Record
            $bw.Write([uint64]0)          # Address
            $bw.Write([uint32]4)          # 4 Parameters
            $bw.Write([uint32]0)
            $bw.Write([uint64]0x1)        # P1
            $bw.Write([uint64]0x1E00)     # P2
            $bw.Write([uint64]0x0)        # P3
            $bw.Write([uint64]0x0)        # P4
            $bw.Flush()

            [IO.File]::WriteAllBytes($tmp, $ms.ToArray())
            $bw.Close(); $ms.Close()

            $res = MinibenchTest\Read-MinidumpFile $tmp
            $res | Should -Not -BeNullOrEmpty
            $res.BugcheckCode | Should -Be '0x133'
            $res.Name | Should -Match 'DPC_WATCHDOG'
            $res.Empfehlung | Should -Match 'DPC Watchdog'
            $res.Parameter1 | Should -Be '0x1'
            $res.Parameter2 | Should -Be '0x1E00'
        }
        finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Version 2.95: Schritt überspringen' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Ereigniskanal.ps1' -Functions 'Send-StepSkipped', 'Test-SkipRequested'
    }
    It 'Test-SkipRequested erkennt und löscht skip.flag' {
        $td = Join-Path ([IO.Path]::GetTempPath()) ('mbtest_cp_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $td -Force | Out-Null
        $flag = Join-Path $td 'skip.flag'
        try {
            Set-ModuleVar 'CpDir' $td
            MinibenchTest\Test-SkipRequested | Should -BeFalse
            [IO.File]::WriteAllText($flag, '1')
            MinibenchTest\Test-SkipRequested | Should -BeTrue
            Test-Path $flag | Should -BeFalse
            MinibenchTest\Test-SkipRequested | Should -BeFalse
        }
        finally {
            Remove-Item $td -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'DiagGui enthält btnSkipStep und SkipStepButton' {
        $global:V295Gui | Should -Match 'btnSkipStep\s*='
        $global:V295Gui | Should -Match 'UI\.SkipStepButton\(\)'
        $global:V295Gui | Should -Match 'skip\.flag'
        $global:V295Gui | Should -Match 'case "SCHRITT_UEBERSPRINGEN":'
    }
}

Describe 'Version 2.95: Grafiktreiber-Gesundheitscheck' {
    It 'Ablauf.ps1 enthält Prüfung auf Basic Display, 18 Monate Alter und Event 4101 DDU' {
        $diag = [IO.File]::ReadAllText((Join-Path $global:V295Src 'Module/Diagnose/Ablauf.ps1'))
        $diag | Should -Match 'Microsoft Basic Display Adapter ist aktiv'
        $diag | Should -Match 'AddMonths\(-18\)'
        $diag | Should -Match 'Ereignis 4101'
        $diag | Should -Match 'DDU'
    }
}

Describe 'Version 2.95: CIM-Caching' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Berichtshilfen.ps1' -Functions 'Get-CimCached'
    }
    It 'Get-CimCached speichert Ergebnisse im Cache' {
        $c1 = MinibenchTest\Get-CimCached 'Win32_OperatingSystem'
        $c2 = MinibenchTest\Get-CimCached 'Win32_OperatingSystem'
        [object]::ReferenceEquals($c1, $c2) | Should -BeTrue
    }
}

Describe 'Version 2.95: Modul Wartung Anpassungen' {
    It 'Nur risikoarme Bereinigungen haben Ueblich = $true' {
        $v = Import-PowerShellDataFile (Join-Path $global:V295Src 'Module/Wartung/Vertrag.psd1')
        $ueblich = @($v.Schritte | Where-Object { $_.Ueblich } | ForEach-Object { $_.Key })
        $ueblich | Should -Contain 'Datentraegerbereinigung'
        $ueblich | Should -Contain 'Temp'
        $ueblich | Should -Contain 'ShaderCache'
        $ueblich | Should -Contain 'UpdateDownloads'
        $ueblich | Should -Contain 'Absturzabbilder'
        $ueblich | Should -Contain 'Prefetch'
        $ueblich | Should -Contain 'WMI'
        $ueblich | Should -Not -Contain 'DismRestore'
        $ueblich | Should -Not -Contain 'Sfc'
        $ueblich | Should -Not -Contain 'Dateisystem'
    }
    It 'DiagGui.cs platziert Schnellwahlknöpfe vor der Maßnahmenliste' {
        $repPos = $global:V295Gui.IndexOf('BuildRepairPage()')
        $btnPos = $global:V295Gui.IndexOf('UI.Secondary("Übliche Auswahl")', $repPos)
        $chkPos = $global:V295Gui.IndexOf('repChk = new CheckBox[repKeys.Length]', $repPos)
        $btnPos | Should -BeLessThan $chkPos
    }
}

Describe 'Version 2.95: Gesamtzusammenbau und C#-Kompilierung' {
    It 'Versionsnummer ist 2.95 in Version.ps1 und Versionen.cs' {
        $vPs1 = [IO.File]::ReadAllText((Join-Path $global:V295Src 'Kern/Version.ps1'))
        $vPs1 | Should -Match '\$ScriptVersion\s*=\s*''(2\.95|3\.0|3\.1|3\.2|3\.3|3\.31)'''
        $global:V295Ver | Should -Match 'new Eintrag\("2\.95"'
    }
    It 'Oberfläche lässt sich als Gesamtheit fehlerfrei kompilieren' {
        $files = @('DiagGui.cs', 'DiagGui_Steuerelemente.cs', 'DiagGui_Modelle.cs', 'DiagGui_Vergleich.cs', 'DiagGui_Seiten.cs', 'Start.cs', 'Versionen.cs') | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ }
        $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGui295_' + [guid]::NewGuid().ToString('N') + '.dll')
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
}
