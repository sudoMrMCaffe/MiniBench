# Auswertungsfunktionen mit Fällen aus echten Läufen (AlexPC, LizPC, TORRENT vom 30.09.2026)
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
