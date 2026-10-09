# Fachgebiet Auswertung: Diagnose-Auswertungen mit Fällen aus echten Läufen (AlexPC, LizPC, TORRENT, ULB-PC10039):
# RAM-Nenntakt, Bluescreens und Abschaltungen, Systemdateien, Kennzahlen, Datenschutz, Zuverlässigkeitsindex,
# Absturzabbilder (Minidump), Grafiktreiber-Gesundheitscheck und Korrekturen aus den Praxistests.
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Functions 'Get-RamRatedSpeed', 'Get-BugcheckName', 'Test-MemoryBugcheck', 'Get-PowerLossInfo', 'Get-GeoMean', 'Get-Median', 'Get-RefPct',
        'Format-Size', 'Format-SizeDec', 'ConvertTo-HtmlText', 'Get-ShortCpuName', 'Get-ShortGpuName', 'Protect-Text', 'Add-Private', 'Get-CbsEntries', 'Get-StatusRank', 'Get-ShortText', 'Split-List' `
        -Setup @'
$script:Private = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$script:UserNames = @()
$script:Ref = @{ Name = 'TORRENT'; Werte = @{ 'CPU|MT' = 38101; 'RAM|Latenz' = 82.4 } }
'@
    # Kernel-Power 41 als Ereignisobjekt mit ToXml(), wie Get-WinEvent es liefert
    function New-Kp41([datetime]$Time, [hashtable]$Data) {
        $xml = '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData>' + (($Data.GetEnumerator() | ForEach-Object { '<Data Name="{0}">{1}</Data>' -f $_.Key, $_.Value }) -join '') + '</EventData></Event>'
        $o = [pscustomobject]@{ TimeCreated = $Time; Id = 41; ProviderName = 'Microsoft-Windows-Kernel-Power' }
        $o | Add-Member -MemberType ScriptMethod -Name ToXml -Value ([scriptblock]::Create("'$xml'"))
        return $o
    }
}

Describe 'RAM-Nenntakt aus der Teilenummer' {
    It '<Teil> ergibt <MTs> MT/s' -ForEach @(
        @{ Teil = 'F4-3200C16-8GVKB'; MTs = 3200 }          # AlexPC: läuft mit 2133, XMP aus
        @{ Teil = 'F5-6000J3038F16G'; MTs = 6000 }
        @{ Teil = 'CMK16GX4M2B3200C16'; MTs = 3200 }
        @{ Teil = 'CMH32GX5M2B6000C30'; MTs = 6000 }
        @{ Teil = 'KF432C16BB/16'; MTs = 3200 }
        @{ Teil = 'BL8G32C16U4B'; MTs = 3200 }
        @{ Teil = 'CP16G56C46U5'; MTs = 5600 }
        @{ Teil = 'TF3D416G3200HC16F'; MTs = 3200 }
        @{ Teil = 'PVS416G320C6'; MTs = 3200 }
        @{ Teil = 'AX4U320016G16A'; MTs = 3200 }
        @{ Teil = ' f4-3600c18-16gtzr '; MTs = 3600 }
    ) { MinibenchTest\Get-RamRatedSpeed $Teil | Should -Be $MTs }
    It 'kennt OEM-Module nicht (kein Fehlalarm)' -ForEach @(@{ Teil = 'M378A1K43CB2-CTD' }, @{ Teil = 'HMA81GS6CJR8N-VK' }, @{ Teil = '' }) {
        MinibenchTest\Get-RamRatedSpeed $Teil | Should -BeNullOrEmpty
    }
}

Describe 'Bluescreens und Abschaltungen' {
    It 'LizPC: 0x1A heißt MEMORY_MANAGEMENT und zählt als Speicherfehler' {
        MinibenchTest\Get-BugcheckName 0x1A | Should -Match 'MEMORY_MANAGEMENT'
        MinibenchTest\Test-MemoryBugcheck 0x1A | Should -BeTrue
    }
    It 'Grafiktreiber-Absturz ist kein Speicherfehler' { MinibenchTest\Test-MemoryBugcheck 0x116 | Should -BeFalse }
    It 'unbekannte Codes führen nicht zum Fehler' { { MinibenchTest\Get-BugcheckName 0x12345 } | Should -Not -Throw }
    Context 'Kernel-Power 41 einordnen' {
        BeforeEach { Mock -ModuleName MinibenchTest Get-WinEvent { throw 'keine Ereignisse' } }
        It 'LizPC: mit Bugcheck-Code ist es ein Bluescreen' {
            $ev = New-Kp41 (Get-Date '2026-09-29 18:12') @{ BugcheckCode = '26'; SleepInProgress = '0'; PowerButtonTimestamp = '0' }
            $r = @(MinibenchTest\Get-PowerLossInfo @($ev))
            $r[0].Kategorie | Should -Be 'Bluescreen'
            $r[0].Einordnung | Should -Match '0x1A'
        }
        It 'AlexPC: letztes Ereignis vor dem Neustart war ein Herunterfahren' {
            $ev = New-Kp41 (Get-Date '2026-09-28 08:01') @{ BugcheckCode = '0'; SleepInProgress = '0'; PowerButtonTimestamp = '0' }
            Mock -ModuleName MinibenchTest Get-WinEvent { }   # Vorgabe (Pester 6 ruft ohne passenden Filter nicht den echten Befehl)
            Mock -ModuleName MinibenchTest Get-WinEvent { [pscustomobject]@{ TimeCreated = (Get-Date '2026-09-27 22:40'); ProviderName = 'User32'; Id = 1074 } } -ParameterFilter { -not $FilterHashtable.ProviderName }
            $r = @(MinibenchTest\Get-PowerLossInfo @($ev))
            $r[0].Kategorie | Should -Be 'Herunterfahren'
            $r[0].'Letztes Ereignis' | Should -Be 'User32 1074'
        }
        It 'lange gedrückte Ein/Aus-Taste' {
            $ev = New-Kp41 (Get-Date '2026-09-28 08:01') @{ BugcheckCode = '0'; LongPowerButtonPressDetected = 'true' }
            (MinibenchTest\Get-PowerLossInfo @($ev))[0].Kategorie | Should -Be 'Taste'
        }
        It 'Stromverlust im Standby' {
            $ev = New-Kp41 (Get-Date '2026-09-28 08:01') @{ BugcheckCode = '0'; SleepInProgress = '4' }
            (MinibenchTest\Get-PowerLossInfo @($ev))[0].Kategorie | Should -Be 'Standby'
        }
        It 'ohne Hinweise: Absturz oder Stromverlust im Betrieb' {
            $ev = New-Kp41 (Get-Date '2026-09-28 08:01') @{ BugcheckCode = '0' }
            (MinibenchTest\Get-PowerLossInfo @($ev))[0].Kategorie | Should -Be 'Betrieb'
        }
    }
}

Describe 'Systemdateiprüfung (CBS.log)' {
    BeforeAll {
        $win = Join-Path $TestDrive 'Windows'
        New-Item -ItemType Directory (Join-Path $win 'Logs/CBS') -Force | Out-Null
        @(
            '2026-09-30 09:00:01, Info                  CSI    00000010 [SR] Cannot repair member file [l:12]"alt.dll" of Alt, Version = 10.0 (vor dem Lauf)'
            '2026-09-30 14:02:11, Info                  CSI    00000123 [SR] Verify complete'
            '2026-09-30 14:02:12, Info                  CSI    00000124 [SR] Repairing 0 components'
            '2026-09-30 14:03:40, Info                  CSI    00000150 [SR] Cannot repair member file [l:23]"Microsoft.Windows.Shell.dll" of Microsoft-Windows-Shell, Version = 10.0.26100.1'
            '2026-09-30 14:03:41, Info                  CSI    00000151 Hashes for file member [l:9]"twinui.dll" do not match.'
            '2026-09-30 14:03:42, Info                  CSI    00000152 [SR] Cannot repair member file [l:23]"Microsoft.Windows.Shell.dll" of Microsoft-Windows-Shell, Version = 10.0.26100.1'
        ) | Set-Content (Join-Path $win 'Logs/CBS/CBS.log')
        $oldWin = $env:windir; $env:windir = $win
    }
    AfterAll { $env:windir = $oldWin }
    It 'zählt nur Einträge ab Beginn der Prüfung' {
        $r = MinibenchTest\Get-CbsEntries (Get-Date '2026-09-30 14:02:00')
        @($r.Cannot).Count | Should -Be 2
        $r.Files | Should -Contain 'Microsoft.Windows.Shell.dll'
        $r.Files | Should -Contain 'twinui.dll'
        $r.Files | Should -Not -Contain 'alt.dll'
    }
    It 'wertet "Verify complete" und "Repairing 0 components" nicht als Beschädigung' {
        $r = MinibenchTest\Get-CbsEntries (Get-Date '2026-09-30 14:02:00')
        @($r.Corrupt | Where-Object { $_ -match 'Verify complete|Repairing 0' }).Count | Should -Be 0
    }
}

Describe 'Kennzahlen' {
    It 'geometrisches Mittel' { MinibenchTest\Get-GeoMean @(50, 200) | Should -Be 100 }
    It 'geometrisches Mittel ignoriert leere und negative Werte' { MinibenchTest\Get-GeoMean @(100, $null, 0, -5) | Should -Be 100 }
    It 'Median gerade und ungerade' {
        MinibenchTest\Get-Median @(3, 1, 2) | Should -Be 2
        MinibenchTest\Get-Median @(4, 1, 2, 3) | Should -Be 2.5
        MinibenchTest\Get-Median @() | Should -BeNullOrEmpty
    }
    It 'Referenzprozent, auch für "kleiner ist besser"' {
        MinibenchTest\Get-RefPct 'CPU|MT' 19050.5 | Should -Be 50
        MinibenchTest\Get-RefPct 'RAM|Latenz' 164.8 -LowerBetter | Should -Be 50
        MinibenchTest\Get-RefPct 'GIBT|ES|NICHT' 1 | Should -BeNullOrEmpty
    }
    It 'Statusrang' { (MinibenchTest\Get-StatusRank 'Fehler') -gt (MinibenchTest\Get-StatusRank 'Warnung') | Should -BeTrue }
}

Describe 'Texte und Datenschutz' {
    It 'HTML wird maskiert' { MinibenchTest\ConvertTo-HtmlText '<b>"A&B"</b>' | Should -Be '&lt;b&gt;&quot;A&amp;B&quot;&lt;/b&gt;' }
    It 'kurze Prozessornamen' {
        MinibenchTest\Get-ShortCpuName 'AMD Ryzen 5 7600X 6-Core Processor' | Should -Be 'AMD Ryzen 5 7600X'
        MinibenchTest\Get-ShortCpuName 'Intel(R) Core(TM) i5-8500 CPU @ 3.00GHz' | Should -Be 'Intel Core i5-8500'
    }
    It 'kurze Grafiknamen' { MinibenchTest\Get-ShortGpuName 'AMD Radeon RX 6800' | Should -Be 'Radeon RX 6800' }
    It 'Listen aus Komma oder Semikolon' { MinibenchTest\Split-List 'CPU, RAM;;GPU ' | Should -Be @('CPU', 'RAM', 'GPU') }
    It 'KI-Datei: Seriennummern, PC-Name, MAC, SID und E-Mail werden unkenntlich' {
        $env:COMPUTERNAME = 'LIZZZ'
        try {
            MinibenchTest\Add-Private 'S4EWNX0R123456' 'SERIENNR'
            $t = MinibenchTest\Protect-Text 'LIZZZ: Datenträger S4EWNX0R123456, MAC 00-1A-2B-3C-4D-5E, S-1-5-21-111-222-333-1001, leo@example.org'
            $t | Should -Not -Match 'LIZZZ|S4EWNX0R123456|00-1A-2B|S-1-5-21-111|leo@example'
            $t | Should -Match '<PC>'
            $t | Should -Match '<SERIENNR-1>'
        } finally { $env:COMPUTERNAME = 'TESTPC' }
    }
    It 'Platzhalter-Seriennummern werden nicht als privat geführt' {
        MinibenchTest\Add-Private 'Default string' 'SERIENNR'
        (Get-ModuleVar 'Private').ContainsKey('Default string') | Should -BeFalse
    }
    It 'Größen' {
        MinibenchTest\Format-Size 0 | Should -Match 'KB'
        MinibenchTest\Format-Size (1.5GB) | Should -Match '^1[,.]5 GB$'
    }
}

Describe 'Zuverlässigkeit (Zuverlässigkeitsverlauf von Windows)' {
    BeforeAll {
        $script:KulturVorher = [cultureinfo]::CurrentCulture
        [cultureinfo]::CurrentCulture = 'de-DE'
        Import-MinibenchTestModule -Functions 'Get-StabilityAssessment', 'Get-ShortText'
        function New-Rel([string]$Src, [int]$Id, [string]$Prod, [string]$Msg = '') { [pscustomobject]@{ SourceName = $Src; EventIdentifier = $Id; ProductName = $Prod; Message = $Msg } }
    }
    AfterAll { [cultureinfo]::CurrentCulture = $script:KulturVorher }
    It 'ULB-PC10039 (5,24): mittel, mit Erklärung und den Ursachen' {
        $rec = @(1..7 | ForEach-Object { New-Rel 'Application Error' 1000 'PowerToys.QuickAccess.exe' }) + @(1..5 | ForEach-Object { New-Rel 'Application Error' 1000 'PowerToys.Settings.exe' }) +
            @((New-Rel 'EventLog' 6008 'Windows'), (New-Rel 'Microsoft-Windows-WindowsUpdateClient' 20 '9WZDNCRFJBMP-MICROSOFT.WINDOWSSTORE'), (New-Rel 'Microsoft-Windows-WindowsUpdateClient' 19 'KB2267602'), (New-Rel 'MsiInstaller' 1033 'Microsoft Edge'))
        $s = MinibenchTest\Get-StabilityAssessment 5.24 $rec 28
        $s.Stufe | Should -Be 'mittel'; $s.Klasse | Should -Be 'info'; $s.Text | Should -Be '5,2 von 10 (mittel)'; $s.Index | Should -Be 5.2
        $s.Erklaerung | Should -Match 'bewertet die Stabilität täglich von 1 bis 10'
        $s.Erklaerung | Should -Match 'Ursachen der letzten 28 Tage'
        $s.Erklaerung | Should -Match '12x Programmabsturz \(meist PowerToys\.QuickAccess\.exe\)'
        $s.Erklaerung | Should -Match '1x Windows-Fehler'
        $s.Erklaerung | Should -Match '1x Update fehlgeschlagen'
        $s.Erklaerung | Should -Not -Match 'Installation fehlgeschlagen'
        @($s.Ursachen).Count | Should -Be 3
    }
    It 'TORRENT (10): gut, ohne Erklärung, erfolgreiche Installationen zählen nicht' {
        $s = MinibenchTest\Get-StabilityAssessment 10 @((New-Rel 'MsiInstaller' 1033 'Microsoft GameInput'))
        $s.Stufe | Should -Be 'gut'; $s.Klasse | Should -Be 'ok'; $s.Erklaerung | Should -BeNullOrEmpty; @($s.Ursachen).Count | Should -Be 0
    }
    It 'niedriger Wert ohne Fehler in den letzten Tagen: Hinweis auf ältere Fehler' {
        $s = MinibenchTest\Get-StabilityAssessment 3.1 @() 28
        $s.Stufe | Should -Be 'niedrig'; $s.Klasse | Should -Be 'warn'
        $s.Erklaerung | Should -Match 'erholt sich von älteren Fehlern'
    }
    It 'Index <Index>: Stufe <Stufe>, Erklärung <Erkl>' -ForEach @(
        @{ Index = 8; Stufe = 'gut'; Erkl = $false }, @{ Index = 7.99; Stufe = 'mittel'; Erkl = $false }, @{ Index = 6.99; Stufe = 'mittel'; Erkl = $true }
        @{ Index = 5; Stufe = 'mittel'; Erkl = $true }, @{ Index = 4.99; Stufe = 'niedrig'; Erkl = $true }, @{ Index = 'kein Wert'; Stufe = $null; Erkl = $null }
    ) {
        $s = MinibenchTest\Get-StabilityAssessment $Index @()
        if ($null -eq $Stufe) { $s | Should -BeNullOrEmpty; return }
        $s.Stufe | Should -Be $Stufe
        [bool]$s.Erklaerung | Should -Be $Erkl
    }
    It 'Hänger, Bluescreen-Bericht und fehlgeschlagene Installation werden eigens gezählt' {
        $rec = @((New-Rel 'Application Hang' 1002 'explorer.exe'), (New-Rel 'Windows Error Reporting' 1001 'Windows' 'BlueScreen'), (New-Rel 'MsiInstaller' 11708 'Treiberpaket'))
        $s = MinibenchTest\Get-StabilityAssessment 4 $rec 14
        $s.Erklaerung | Should -Match 'Ursachen der letzten 14 Tage: 1x Windows-Fehler \(Absturz oder unerwartetes Ausschalten\), 1x Programm reagierte nicht \(meist explorer\.exe\), 1x Installation fehlgeschlagen \(meist Treiberpaket\)\.'
    }
    It 'kein Index, keine Bewertung' { MinibenchTest\Get-StabilityAssessment $null @() | Should -BeNullOrEmpty }
}

Describe 'Korrekturen aus dem Praxistest 03.10.2026' {
    BeforeAll { Import-MinibenchTestModule -Functions 'Repair-Utf8AsOem', 'Get-NvmeGenFromSpeed', 'Get-BenchPauseMeasured', 'Get-PauseAssessment' }
    It 'netsh-Ausgabe in UTF-8, gelesen als OEM 850, wird lesbar' {
        Set-ModuleVar 'OemEnc' ([Text.Encoding]::GetEncoding(850))
        $bad = [Text.Encoding]::GetEncoding(850).GetString([Text.Encoding]::UTF8.GetBytes('benötigen „Standort“'))
        MinibenchTest\Repair-Utf8AsOem $bad | Should -Be 'benötigen „Standort“'
        MinibenchTest\Repair-Utf8AsOem 'Größe' | Should -Be 'Größe'
    }
    It 'PCIe-Generation einer NVMe-SSD aus dem Lesewert, wenn die Anbindung fehlt' {
        MinibenchTest\Get-NvmeGenFromSpeed 6689 | Should -Be 4
        MinibenchTest\Get-NvmeGenFromSpeed 3420 | Should -Be 3
        MinibenchTest\Get-NvmeGenFromSpeed 12000 | Should -Be 5
        MinibenchTest\Get-NvmeGenFromSpeed 0 | Should -Be 0
    }
    It 'Unterbrechungen während WinSAT zählen nicht' {
        $t0 = Get-Date
        $parts = @(
            [pscustomobject]@{ Teil = 'Prozessor'; Beginn = $t0; Ende = $t0.AddSeconds(30); Von = [double[]](0, 0, 0, 0, 0, 0); Bis = [double[]](2, 80, 150, 1, 0, 0) },
            [pscustomobject]@{ Teil = 'WinSAT'; Beginn = $t0.AddSeconds(30); Ende = $t0.AddSeconds(120); Von = [double[]](2, 0, 150, 1, 0, 0); Bis = [double[]](400, 900, 27000, 9, 1, 1) })
        $m = MinibenchTest\Get-BenchPauseMeasured $parts ([double[]](400, 900, 27000, 9, 1, 1))
        $m.Werte[0] | Should -Be 2
        $m.Werte[1] | Should -Be 80
        $m.Werte[2] | Should -Be 150
        $m.Sekunden | Should -Be 30
        (MinibenchTest\Get-PauseAssessment $m.Werte $m.Sekunden).Auffaellig | Should -BeFalse
    }
}

Describe 'Absturzabbilder (Minidump)' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Checkpoints_Absturzanalyse.ps1'
        # Minidump (MDMP) mit Ausnahme-Datenstrom wie unter C:\Windows\Minidump
        function New-Mdmp([string]$Pfad, [uint32]$Code, [uint64[]]$Param, [uint32]$Unix = 1700000000) {
            $ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter($ms)
            $bw.Write([uint32]0x504D444D); $bw.Write([uint32]0xA793); $bw.Write([uint32]1); $bw.Write([uint32]32); $bw.Write([uint32]0); $bw.Write($Unix); $bw.Write([uint64]0)
            $bw.Write([uint32]6); $bw.Write([uint32]160); $bw.Write([uint32]44)
            $bw.Write([uint32]1000); $bw.Write([uint32]0); $bw.Write($Code); $bw.Write([uint32]0); $bw.Write([uint64]0); $bw.Write([uint64]0); $bw.Write([uint32]$Param.Count); $bw.Write([uint32]0)
            foreach ($p in $Param) { $bw.Write([uint64]$p) }
            $bw.Flush(); [IO.File]::WriteAllBytes($Pfad, $ms.ToArray()); $bw.Close()
        }
        # Vollständiges Speicherabbild (PAGE/DU64) wie C:\Windows\MEMORY.DMP
        function New-Du64([string]$Pfad, [uint32]$Code, [uint64[]]$Param) {
            $b = New-Object byte[] 0x2000
            $ms = New-Object IO.MemoryStream(, $b); $bw = New-Object IO.BinaryWriter($ms)
            $bw.Write([uint32]0x45474150); $bw.Write([uint32]0x34365544)
            $ms.Position = 0x38; $bw.Write($Code)
            $ms.Position = 0x40; foreach ($p in $Param) { $bw.Write([uint64]$p) }
            $bw.Flush(); [IO.File]::WriteAllBytes($Pfad, $b); $bw.Close()
        }
    }
    It 'Empfehlung für Stoppcode <Code>' -ForEach @(
        @{ Code = 0x133; Text = 'DPC Watchdog' }, @{ Code = 0x3B; Text = 'System Service' }, @{ Code = 0x116; Text = 'Video TDR' }, @{ Code = 0xD1; Text = 'Driver IRQL' }
        @{ Code = 0x1A; Text = 'Memory Management' }, @{ Code = 0x124; Text = 'WHEA Uncorrectable' }, @{ Code = 0x12345; Text = 'Stoppcode analysieren' }
    ) { MinibenchTest\Get-BugcheckRecommendation $Code | Should -Match $Text }
    It 'liest Stoppcode, Parameter und Zeitpunkt aus einem Minidump' {
        $f = Join-Path $TestDrive '100326-1.dmp'
        New-Mdmp $f 0x133 @(0x1, 0x1E00, 0x0, 0x0)
        $r = MinibenchTest\Read-MinidumpFile $f
        $r.BugcheckCode | Should -Be '0x133'
        $r.BugcheckInt | Should -Be 0x133
        $r.Name | Should -Match 'DPC_WATCHDOG'
        $r.Empfehlung | Should -Match 'DPC Watchdog'
        $r.Parameter1 | Should -Be '0x1'
        $r.Parameter2 | Should -Be '0x1E00'
        $r.Datei | Should -Be '100326-1.dmp'
        $r.Datum | Should -Be ((New-Object DateTime(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).AddSeconds(1700000000).ToLocalTime())
    }
    It 'liest Stoppcode und Parameter aus einem vollständigen Speicherabbild (DU64)' {
        $f = Join-Path $TestDrive 'MEMORY.DMP'
        New-Du64 $f 0x1A @(0x41792, 0x1E00, 0x0, 0x0)
        $r = MinibenchTest\Read-MinidumpFile $f
        $r.BugcheckCode | Should -Be '0x1A'
        $r.Name | Should -Match 'MEMORY_MANAGEMENT'
        $r.Empfehlung | Should -Match 'Memory Management'
        $r.Parameter1 | Should -Be '0x41792'
        $r.Parameter2 | Should -Be '0x1E00'
    }
    It 'Kerneladressen als Parameter (ab 0x8000000000000000) brechen das Lesen nicht ab (<Format>)' -ForEach @(@{ Format = 'MDMP' }, @{ Format = 'DU64' }) {
        # typischer Parameter eines Bluescreens: Adresse im Kernel, z. B. 0xFFFFF80312345678
        $adr = [Convert]::ToUInt64('FFFFF80312345678', 16)
        $f = Join-Path $TestDrive ('kernel_' + $Format + '.dmp')
        if ($Format -eq 'MDMP') { New-Mdmp $f 0x3B @([uint64]3221225477, $adr, 0, 0) } else { New-Du64 $f 0x3B @([uint64]3221225477, $adr, 0, 0) }
        $r = MinibenchTest\Read-MinidumpFile $f
        $r | Should -Not -BeNullOrEmpty
        $r.BugcheckCode | Should -Be '0x3B'
        $r.Parameter1 | Should -Be '0xC0000005'
        $r.Parameter2 | Should -Be '0xFFFFF80312345678'
    }
    It 'kaputte, zu kurze und fehlende Dateien ergeben nichts' {
        $kurz = Join-Path $TestDrive 'kurz.dmp'; [IO.File]::WriteAllBytes($kurz, [byte[]](1, 2, 3))
        $fremd = Join-Path $TestDrive 'fremd.dmp'; [IO.File]::WriteAllBytes($fremd, (New-Object byte[] 256))
        MinibenchTest\Read-MinidumpFile $kurz | Should -BeNullOrEmpty
        MinibenchTest\Read-MinidumpFile $fremd | Should -BeNullOrEmpty
        MinibenchTest\Read-MinidumpFile (Join-Path $TestDrive 'gibt-es-nicht.dmp') | Should -BeNullOrEmpty
    }
    It 'Ordner: nur gültige Abbilder, das neueste zuerst' {
        $dir = Join-Path $TestDrive 'Minidump'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        New-Mdmp (Join-Path $dir 'alt.dmp') 0x116 @(0x0) 1700000000
        New-Mdmp (Join-Path $dir 'neu.dmp') 0x3B @([uint64]3221225477) 1750000000
        [IO.File]::WriteAllBytes((Join-Path $dir 'kaputt.dmp'), [byte[]](0, 0, 0, 0))
        Set-Content -LiteralPath (Join-Path $dir 'notiz.txt') -Value 'kein Abbild'
        $r = @(MinibenchTest\Read-Minidumps $dir)
        $r.Count | Should -Be 2
        @($r | ForEach-Object { $_.BugcheckCode }) | Should -Be @('0x3B', '0x116')
    }
}

Describe 'Grafiktreiber-Gesundheitscheck' {
    BeforeAll {
        Import-MinibenchTestModule -Functions 'Add-Finding', 'Send-GuiEvent', 'Get-GpuKind', 'Format-Size', 'Get-CimCached', 'Get-TdrEvents', 'Get-Ev', 'Out-Report', 'Add-Sub', 'Add-Line', 'Get-MainGpu', 'Get-GpuFactText', 'Get-ShortGpuName', 'Add-Private' `
            -Setup '$script:Facts = [ordered]@{}; $script:BenchShort = @{}; $script:CimCache = @{}; $script:Report = New-Object System.Text.StringBuilder; $script:FindKeys = $null'
        # Abschnitt "Grafik und Monitore" der Diagnose, so wie er im zusammengebauten Skript steht
        $cmd = (Get-MinibenchAst).Find({ param($a) $a -is [System.Management.Automation.Language.CommandAst] -and $a.GetCommandName() -eq 'Invoke-Section' -and $a.CommandElements.Count -ge 3 -and $a.CommandElements[1].Extent.Text -eq "'Grafik und Monitore'" }, $true)
        $sbe = @($cmd.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] })[0]
        $script:Abschnitt = [scriptblock]::Create($sbe.ScriptBlock.EndBlock.Extent.Text)
        Mock -ModuleName MinibenchTest Get-CimCached { $global:MinibenchTestGpus }
        Mock -ModuleName MinibenchTest Get-TdrEvents { $global:MinibenchTestTdr }
        Mock -ModuleName MinibenchTest Get-CimInstance { }
        Mock -ModuleName MinibenchTest Get-ChildItem { }   # der Abschnitt liest nur die Grafikklasse der Registry
        Mock -ModuleName MinibenchTest Get-MainGpu { }
        Mock -ModuleName MinibenchTest Get-GpuFactText { 'Testgrafik' }
        Mock -ModuleName MinibenchTest Write-Host { }
        function New-Gpu([string]$Name, [datetime]$Datum) { [pscustomobject]@{ Name = $Name; DriverDate = $Datum; DriverVersion = '31.0.1'; AdapterRAM = 4GB; CurrentHorizontalResolution = 1920; CurrentVerticalResolution = 1080; CurrentRefreshRate = 60; Status = 'OK' } }
        function Invoke-GrafikAbschnitt($Gpus, [int]$Tdr = 0) {
            $global:MinibenchTestGpus = @($Gpus)
            $global:MinibenchTestTdr = @(1..$Tdr | Where-Object { $Tdr } | ForEach-Object { [pscustomobject]@{ Id = 4101; ProviderName = 'Display' } })
            Set-ModuleVar 'Findings' (New-Object System.Collections.Generic.List[object])
            & (Get-Module MinibenchTest) $script:Abschnitt
            return @(Get-ModuleVar 'Findings' | Where-Object { $_.Bereich -eq 'Grafik' })
        }
    }
    AfterAll { Remove-Variable -Scope Global -Name MinibenchTestGpus, MinibenchTestTdr -ErrorAction SilentlyContinue }
    It 'nur der Microsoft Basic Display Adapter: Warnung, Herstellertreiber fehlt' {
        $f = @(Invoke-GrafikAbschnitt @(New-Gpu 'Microsoft Basic Display Adapter' (Get-Date).AddYears(-8)))
        $f.Count | Should -Be 1
        $f[0].Stufe | Should -Be 'WARNUNG'
        $f[0].Befund | Should -Match 'Nur der Microsoft Basic Display Adapter ist aktiv'
    }
    It 'Treiber älter als 18 Monate: Hinweis nur für diese Karte, nicht für den Basisadapter' {
        $f = @(Invoke-GrafikAbschnitt @((New-Gpu 'Radeon RX 570 Series' (Get-Date).AddMonths(-19)), (New-Gpu 'Intel(R) UHD Graphics 630' (Get-Date).AddMonths(-17)), (New-Gpu 'Microsoft Basic Display Adapter' (Get-Date).AddYears(-8))))
        $f.Count | Should -Be 1
        $f[0].Stufe | Should -Be 'INFO'
        $f[0].Befund | Should -Match '^Grafiktreiber für Radeon RX 570 Series ist älter als 18 Monate'
    }
    It 'Treiberabstürze (Ereignis 4101) der letzten 30 Tage: Warnung mit Anzahl und DDU' {
        $f = @(Invoke-GrafikAbschnitt @(New-Gpu 'NVIDIA GeForce RTX 3060' (Get-Date).AddMonths(-2)) 3)
        $f.Count | Should -Be 1
        $f[0].Stufe | Should -Be 'WARNUNG'
        $f[0].Befund | Should -Match 'Ereignis 4101 .* 3x auf'
        $f[0].Befund | Should -Match 'DDU'
        Should -Invoke -ModuleName MinibenchTest Get-TdrEvents -Times 1 -Exactly -ParameterFilter { [math]::Abs(((Get-Date) - $Since).TotalDays - 30) -lt 1 }
    }
    It 'aktueller Herstellertreiber ohne Abstürze: kein Befund, Grafik steht im Inventar' {
        $f = @(Invoke-GrafikAbschnitt @(New-Gpu 'AMD Radeon RX 6800' (Get-Date).AddMonths(-3)))
        $f.Count | Should -Be 0
        (Get-ModuleVar 'Facts')['Grafik'] | Should -Be 'Testgrafik'
        (Get-ModuleVar 'Report').ToString() | Should -Match 'AMD Radeon RX 6800'
    }
}
