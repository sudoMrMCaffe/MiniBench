# Datenbankformat 2 mit Geräteidentität; Format 1 (echte Einträge der Läufe vom 30.09.2026) bleibt lesbar
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Modulvertrag.ps1', 'Kern\Geraeteidentitaet.ps1' `
        -Functions 'Read-JsonFile', 'ConvertTo-ValueTable', 'Get-DbEntries', 'Get-DbLatest', 'Get-SafeName', 'Save-DbEntry', 'Get-CurrentRefValues', 'Import-BenchReference', 'Get-Median', 'Add-Line' `
        -Setup @'
$script:DbFormat = 'PC-Diagnose-DB/2'
$script:Report = New-Object System.Text.StringBuilder
$script:RefDefault = @{ Name = 'eingebaut'; Datum = '2026-09-30'; Quelle = 'eingebaut'; Werte = @{ 'CPU|MT' = 1000 } }
$script:Facts = [ordered]@{ 'Prozessor' = 'AMD Ryzen 5 7600X'; 'Arbeitsspeicher' = '32 GB'; 'Grafik' = 'Radeon RX 6800'; 'Datenträger' = 'SSD'; 'Betriebssystem' = 'Windows 11'; 'Mainboard' = 'B650'; 'Windows installiert' = ''; 'System' = 'Gigabyte' }
$script:BenchShort = @{}; $script:BenchNew = New-Object System.Collections.ArrayList; $script:BenchDisks = @(); $script:BenchResults = @(); $script:BenchRefName = ''
$script:LoadSummary = ''; $KeineDatenbank = $false; $AnalyzeLastRun = $false; $Kurztest = $false; $BenchmarkKurz = $false; $ReferenzDatei = ''
function Get-ModeLabel { 'Diagnose (vollständig)' }
'@
    $real = Join-Path $global:MinibenchTestData 'Datenbank'
    function New-Db {
        $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $d | Out-Null
        Copy-Item (Join-Path $real '*.json') $d
        Set-ModuleVar 'DbDir' $d
        return $d
    }
    function Set-Device([string]$Id) { Set-ModuleVar 'DeviceIdentity' ([pscustomobject]@{ Id = $Id; Guete = 'hoch'; Quellen = @('System-UUID', 'Seriennummer Mainboard') }) }
}

Describe 'Geräteidentität' {
    BeforeAll {
        $a = @{ Uuid = '4C4C4544-0042-3510-8051-B4C04F4E3732'; BoardVendor = 'Gigabyte Technology Co., Ltd.'; BoardProduct = 'B650 GAMING X AX'; BoardSerial = 'SN123456789'; BiosSerial = 'Default string'; ComputerName = 'TORRENT' }
    }
    It 'ist stabil und hat das Format G- plus 20 Hexziffern' {
        $x = MinibenchTest\ConvertTo-DeviceId @a
        $y = MinibenchTest\ConvertTo-DeviceId @a
        $x.Id | Should -Be $y.Id
        $x.Id | Should -Match '^G-[0-9a-f]{20}$'
        $x.Guete | Should -Be 'hoch'
    }
    It 'bleibt nach Umbenennung des PCs gleich' {
        $b = $a.Clone(); $b.ComputerName = 'NEUER-NAME'
        (MinibenchTest\ConvertTo-DeviceId @b).Id | Should -Be (MinibenchTest\ConvertTo-DeviceId @a).Id
    }
    It 'ignoriert Schreibweise und Leerzeichen' {
        $b = $a.Clone(); $b.Uuid = '{' + $a.Uuid.ToLower() + '}'; $b.BoardProduct = ' b650  gaming x ax '
        (MinibenchTest\ConvertTo-DeviceId @b).Id | Should -Be (MinibenchTest\ConvertTo-DeviceId @a).Id
    }
    It 'ändert sich mit einem anderen Mainboard' {
        $b = $a.Clone(); $b.BoardSerial = 'SN000000001'
        (MinibenchTest\ConvertTo-DeviceId @b).Id | Should -Not -Be (MinibenchTest\ConvertTo-DeviceId @a).Id
    }
    It 'enthält keine Seriennummer im Klartext' {
        $x = MinibenchTest\ConvertTo-DeviceId @a
        ($x | ConvertTo-Json) | Should -Not -Match 'SN123456789|4C4C4544'
    }
    It 'verwirft Platzhalter (<Wert>)' -ForEach @(
        @{ Wert = 'To be filled by O.E.M.' }, @{ Wert = 'Default string' }, @{ Wert = '00000000-0000-0000-0000-000000000000' },
        @{ Wert = 'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF' }, @{ Wert = '03000200-0400-0500-0006-000700080009' }, @{ Wert = 'System Serial Number' }, @{ Wert = '' }
    ) { MinibenchTest\Test-PlaceholderId $Wert | Should -BeTrue }
    It 'nimmt echte Werte an' { MinibenchTest\Test-PlaceholderId 'PF2ABCDE' | Should -BeFalse }
    It 'fällt ohne Firmwarekennung auf den Computernamen zurück (Güte niedrig)' {
        $x = MinibenchTest\ConvertTo-DeviceId -Uuid '' -BoardVendor 'To be filled by O.E.M.' -BoardProduct 'To be filled by O.E.M.' -BoardSerial 'Default string' -BiosSerial '' -ComputerName 'LIZZZ'
        $x.Guete | Should -Be 'niedrig'
        $x.Quellen | Should -Contain 'Computername'
    }
    It 'nutzt die BIOS-Seriennummer, wenn das Mainboard keine hat (Güte mittel)' {
        $x = MinibenchTest\ConvertTo-DeviceId -Uuid '' -BoardVendor 'LENOVO' -BoardProduct '20XW' -BoardSerial '' -BiosSerial 'PF2ABCDE' -ComputerName 'NB1'
        $x.Guete | Should -Be 'mittel'
        $x.Quellen | Should -Contain 'Seriennummer BIOS'
    }
}

Describe 'Lesen der Datenbank' {
    It 'liest die drei echten Einträge im Format 1' {
        $null = New-Db
        $e = @(MinibenchTest\Get-DbEntries)
        $e.Count | Should -Be 3
        @($e | Where-Object Format -eq 'PC-Diagnose-DB/1').Count | Should -Be 3
        ($e | Where-Object Computer -eq 'TORRENT').Werte['CPU|MT'] | Should -Be 38101
    }
    It 'ordnet alte Einträge über den Namen dem Gerät mit Kennung zu' {
        $d = New-Db
        $o = Get-Content (Join-Path $d 'TORRENT_20260930_215900.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $o.Format = 'PC-Diagnose-DB/2'; $o.Datum = '2026-10-05 10:00'
        $o | Add-Member Geraet ([pscustomobject]@{ Id = 'G-11111111111111111111'; Guete = 'hoch'; Quellen = @() })
        $o | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $d 'TORRENT_20261005_100000.json') -Encoding UTF8
        $e = @(MinibenchTest\Get-DbEntries)
        @($e | Where-Object Computer -eq 'TORRENT' | ForEach-Object GeraetKey | Select-Object -Unique) | Should -Be @('G-11111111111111111111')
        @($e | Where-Object Computer -eq 'LIZZZ').GeraetKey | Should -Be 'PC:LIZZZ'
    }
    It 'findet frühere Läufe eines umbenannten Geräts' {
        $entry = [pscustomobject]@{ Computer = 'ALTER-NAME'; GeraetId = 'G-22222222222222222222'; GeraetKey = 'G-22222222222222222222' }
        MinibenchTest\Test-SameDevice $entry 'G-22222222222222222222' 'NEUER-NAME' | Should -BeTrue
        MinibenchTest\Test-SameDevice $entry 'G-33333333333333333333' 'ALTER-NAME' | Should -BeFalse
    }
    It 'ordnet Einträge ohne Kennung über den Namen zu' {
        $entry = [pscustomobject]@{ Computer = 'LIZZZ'; GeraetId = ''; GeraetKey = 'PC:LIZZZ' }
        MinibenchTest\Test-SameDevice $entry 'G-33333333333333333333' 'LIZZZ' | Should -BeTrue
    }
    It 'neuester Eintrag je Gerät, ohne das aktuelle Gerät' {
        $null = New-Db
        $env:COMPUTERNAME = 'TORRENT'; Set-Device 'G-99999999999999999999'
        try {
            $l = @(MinibenchTest\Get-DbLatest (MinibenchTest\Get-DbEntries) -ExcludeCurrent)
            @($l | ForEach-Object Computer) | Should -Not -Contain 'TORRENT'
            $l.Count | Should -Be 2
        } finally { $env:COMPUTERNAME = 'TESTPC' }
    }
    It 'Median-Referenz lässt das eigene Gerät weg' {
        $null = New-Db
        $env:COMPUTERNAME = 'TORRENT'; Set-Device 'G-99999999999999999999'
        try {
            & (Get-Module MinibenchTest) { $script:ReferenzDatei = '*median'; Import-BenchReference }
            $ref = Get-ModuleVar 'Ref'
            $ref.Name | Should -Match 'Median von 2 Systemen'
        } finally { $env:COMPUTERNAME = 'TESTPC'; & (Get-Module MinibenchTest) { $script:ReferenzDatei = '' } }
    }
}

Describe 'Schreiben im Format 2' {
    It 'schreibt Format, Geräteidentität und Kernfelder' {
        $d = New-Db
        Set-Device 'G-44444444444444444444'
        $f = & (Get-Module MinibenchTest) { Save-DbEntry -Sorted @() -NK 0 -NW 1 -NI 2 }
        $f | Should -Exist
        $j = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $j.Format | Should -Be 'PC-Diagnose-DB/2'
        $j.Geraet.Id | Should -Be 'G-44444444444444444444'
        $j.Geraet.Guete | Should -Be 'hoch'
        $j.Befunde.Warnungen | Should -Be 1
        # der neue Eintrag ist gemeinsam mit den alten lesbar
        @(MinibenchTest\Get-DbEntries).Count | Should -Be 4
    }
    It 'schreibt nichts mit -KeineDatenbank' {
        $null = New-Db
        & (Get-Module MinibenchTest) { $script:KeineDatenbank = $true; try { Save-DbEntry -Sorted @() -NK 0 -NW 0 -NI 0 } finally { $script:KeineDatenbank = $false } } | Should -BeNullOrEmpty
    }
}
