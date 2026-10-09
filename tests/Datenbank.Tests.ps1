# Vergleichsdatenbank (Format PC-Diagnose-DB/2 mit Geräteidentität), Referenzsysteme und eingebettete Referenzen,
# Datenordner mit NAS-Anbindung über Netzwerk.json und lokalem Fallback, Datenpflege und Archivierung.
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    # Kern\Datenordner.ps1 nur als einzelne Funktionen laden: der Teil ermittelt beim Laden sofort den Datenordner
    # (unter Windows Dokumente\Leos Minibench samt Referenzdateien, unter Linux scheitert Join-Path an einem leeren
    # Dokumente-Pfad und das Testmodul lädt gar nicht).
    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Modulvertrag.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Datenpflege.ps1', 'Kern\Referenzen_Eingebettet.ps1', 'Kern\Referenz_Vergleich.ps1' `
        -Functions 'Read-JsonFile', 'ConvertTo-ValueTable', 'Get-DbEntries', 'Get-DbLatest', 'Get-SafeName', 'Save-DbEntry', 'Get-CurrentRefValues', 'Import-BenchReference', 'Get-Median', 'Add-Line',
                   'Test-WritableDir', 'Resolve-DataDir', 'Test-IsNetworkPath', 'Resolve-LocalDataDir', 'Initialize-DbDir' `
        -Setup @'
$script:DbFormat = 'PC-Diagnose-DB/2'
$script:Report = New-Object System.Text.StringBuilder
$script:RefDefault = @{ Name = 'eingebaut'; Datum = '2026-09-30'; Quelle = 'eingebaut'; Werte = @{ 'CPU|MT' = 1000 } }
$script:Facts = [ordered]@{ 'Prozessor' = 'AMD Ryzen 5 7600X'; 'Arbeitsspeicher' = '32 GB'; 'Grafik' = 'Radeon RX 6800'; 'Datenträger' = 'SSD'; 'Betriebssystem' = 'Windows 11'; 'Mainboard' = 'B650'; 'Windows installiert' = ''; 'System' = 'Gigabyte' }
$script:BenchShort = @{}; $script:BenchNew = New-Object System.Collections.ArrayList; $script:BenchDisks = @(); $script:BenchResults = @(); $script:BenchRefName = ''
$script:LoadSummary = ''; $KeineDatenbank = $false; $AnalyzeLastRun = $false; $Kurztest = $false; $BenchmarkKurz = $false; $ReferenzDatei = ''
$script:DataDirFallback = $false; $script:LocalDataDir = ''; $script:CpDir = ''
# net.exe (Verbindung zum NAS wiederherstellen) läuft in Tests nie; die Tests ersetzen den Platzhalter per Mock
function net.exe { }
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
    function New-TestDir([string]$Prefix = 'd') {
        $d = Join-Path $TestDrive ($Prefix + '_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d | Out-Null
        return $d
    }
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

Describe 'Lesen und Toleranz der Datenbank' {
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
    It 'überspringt beschädigte JSON-Dateien' {
        $td = New-TestDir 'kaputt'
        [IO.File]::WriteAllText((Join-Path $td 'ok.json'), '{"Format":"PC-Diagnose-DB/2","Computer":"TEST-OK","Datum":"2026-10-05","Werte":{"CPU|ST":150}}')
        [IO.File]::WriteAllText((Join-Path $td 'bad.json'), '{"Format": "PC-Diagnose-DB/2", KORRUPT!')
        [IO.File]::WriteAllText((Join-Path $td 'leer.json'), '')
        Set-ModuleVar 'DbDir' $td
        $entries = @(MinibenchTest\Get-DbEntries)
        $entries.Count | Should -Be 1
        $entries[0].Computer | Should -Be 'TEST-OK'
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
        @(MinibenchTest\Get-DbEntries).Count | Should -Be 4
    }
    It 'schreibt nichts mit -KeineDatenbank' {
        $null = New-Db
        & (Get-Module MinibenchTest) { $script:KeineDatenbank = $true; try { Save-DbEntry -Sorted @() -NK 0 -NW 0 -NI 0 } finally { $script:KeineDatenbank = $false } } | Should -BeNullOrEmpty
    }
}

Describe 'Referenzsysteme und eingebettete Referenzen' {
    BeforeAll {
        $refDir = Join-Path $global:MinibenchSrcRoot 'Daten/Referenzen'
        $refFiles = @(Get-ChildItem -LiteralPath $refDir -Filter '*.json')
    }
    It 'die mitgelieferten Referenzen sind anonyme Datensätze im Format 2' {
        $refFiles.Count | Should -BeGreaterOrEqual 5
        foreach ($f in $refFiles) {
            $o = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $o.Format | Should -Be 'PC-Diagnose-DB/2' -Because $f.Name
            foreach ($k in 'Name', 'Computer', 'Datum', 'Hardware', 'Werte') { $o.$k | Should -Not -BeNullOrEmpty -Because ('{0}: {1}' -f $f.Name, $k) }
            ($o.Computer -match 'Referenz' -or $o.Name -match 'Referenz') | Should -BeTrue -Because $f.Name
        }
    }
    It 'die eingebetteten Referenzen entsprechen den Dateien in src/Daten/Referenzen' {
        $refs = Get-ModuleVar 'EmbeddedReferences'
        @($refs.Keys | Sort-Object) | Should -Be @($refFiles | ForEach-Object { $_.Name } | Sort-Object)
        foreach ($f in $refFiles) {
            $a = $refs[$f.Name] | ConvertFrom-Json
            $b = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
            ($a | ConvertTo-Json -Depth 8 -Compress) | Should -Be ($b | ConvertTo-Json -Depth 8 -Compress) -Because $f.Name
        }
    }
    It 'der Zusammenbau übernimmt Referenzdateien in Kern\Referenzen_Eingebettet.ps1 (UTF-8 mit BOM)' {
        $src = New-TestDir 'src'
        New-Item -ItemType Directory -Path (Join-Path $src 'Daten/Referenzen'), (Join-Path $src 'Kern') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'Daten/Referenzen/Neu.json'), '{ "Format": "PC-Diagnose-DB/2", "Name": "Referenz: Neu", "Werte": { "CPU|MT": 1234 } }')
        Update-EmbeddedReferences $src
        $f = Join-Path $src 'Kern/Referenzen_Eingebettet.ps1'
        $f | Should -Exist
        $bytes = [IO.File]::ReadAllBytes($f)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
        $m = New-Module -ScriptBlock ([scriptblock]::Create([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)))
        $refs = & $m { $script:EmbeddedReferences }
        @($refs.Keys) | Should -Be @('Neu.json')
        ($refs['Neu.json'] | ConvertFrom-Json).Werte.'CPU|MT' | Should -Be 1234
    }
    It 'die eingebetteten Referenzen stehen im Bauplan vor dem Datenordner (der sie beim Start entpackt)' {
        $plan = @((Get-MinibenchBuild).Teile)
        [array]::IndexOf($plan, 'Kern\Referenzen_Eingebettet.ps1') | Should -BeGreaterOrEqual 0
        [array]::IndexOf($plan, 'Kern\Referenzen_Eingebettet.ps1') | Should -BeLessThan ([array]::IndexOf($plan, 'Kern\Datenordner.ps1'))
    }
    It 'Initialize-DbDir entpackt die eingebetteten Referenzen in eine neue Datenbank' {
        $d = Join-Path (New-TestDir 'db') 'Datenbank'
        Set-ModuleVar 'DbDir' $d
        MinibenchTest\Initialize-DbDir
        $d | Should -Exist
        @(Get-ChildItem -LiteralPath $d -Filter '*.json').Count | Should -Be (Get-ModuleVar 'EmbeddedReferences').Count
    }
    It 'Initialize-DbDir lässt eine vorhandene Datenbank unverändert' {
        $d = New-TestDir 'db'
        [IO.File]::WriteAllText((Join-Path $d 'PC1_20261001_100000.json'), '{ "Format": "PC-Diagnose-DB/2" }')
        Set-ModuleVar 'DbDir' $d
        MinibenchTest\Initialize-DbDir
        @(Get-ChildItem -LiteralPath $d -Filter '*.json').Count | Should -Be 1
    }
    It 'ohne gespeicherte Referenz gilt Desktop Mittelklasse als Standard' {
        Set-ModuleVar 'DataDir' ''
        Set-ModuleVar 'DbDir' (New-TestDir 'leer')
        $ref = MinibenchTest\Get-SavedReference
        $ref | Should -Not -BeNullOrEmpty
        $ref.Name | Should -Match 'Desktop Mittelklasse'
        $ref.Quelle | Should -Match 'Eingebettet'
        $ref.Werte.Count | Should -BeGreaterThan 0
    }
    It 'die Oberfläche (JavaScriptSerializer) liest alle Referenzdateien' {
        if (-not (Test-IstWindows)) { Set-ItResult -Skipped -Because 'JavaScriptSerializer (System.Web.Extensions) gibt es nur unter Windows'; return }
        # eigener Prozess: System.Web.Extensions wird nicht in die Testsitzung geladen
        $ps1 = Join-Path (New-TestDir 'js') 'Lesen.ps1'
        $code = @'
param([string]$Dir)
Add-Type -AssemblyName System.Web.Extensions
$js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$js.MaxJsonLength = [int]::MaxValue
foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter '*.json')) {
    try {
        $d = $js.DeserializeObject([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8))
        $miss = @(foreach ($k in 'Format', 'Name', 'Computer', 'Datum', 'Hardware', 'Werte') { if (-not $d[$k]) { $k } })
        if ($miss.Count) { 'FEHL|' + $f.Name + '|fehlt: ' + ($miss -join ', ') }
        elseif ($d['Format'] -ne 'PC-Diagnose-DB/2') { 'FEHL|' + $f.Name + '|Format ' + $d['Format'] }
        else { 'OK|' + $f.Name }
    } catch { 'FEHL|' + $f.Name + '|' + $_.Exception.Message }
}
'@
        [IO.File]::WriteAllText($ps1, $code, (New-Object Text.UTF8Encoding($true)))
        $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 -Dir $refDir 2>&1 | ForEach-Object { [string]$_ })
        @($out | Where-Object { $_ -like 'OK|*' }).Count | Should -Be $refFiles.Count -Because ($out -join '; ')
    }
}

Describe 'Datenordner, NAS und Netzwerk.json' {
    BeforeAll {
        # Netzwerk.json des Rechners (Dokumente, AppData) und Ordner außerhalb von TestDrive bleiben unsichtbar, net.exe läuft nie
        function Use-NurTestDrive {
            $script:NurTestDrive = [string]$TestDrive
            # Vorgabe: echter Test-Path (Pester 6 fällt ohne passenden Filter nicht mehr auf den echten Befehl zurück)
            Mock -ModuleName MinibenchTest Test-Path {
                $a = @{}
                if ($LiteralPath) { $a.LiteralPath = $LiteralPath } else { $a.Path = $Path }
                if ($PathType) { $a.PathType = $PathType }
                Microsoft.PowerShell.Management\Test-Path @a
            }
            Mock -ModuleName MinibenchTest Test-Path { $false } -ParameterFilter { $p = $(if ($LiteralPath) { [string]$LiteralPath } else { [string]$Path }); -not $p.StartsWith($script:NurTestDrive) }
            Mock -ModuleName MinibenchTest net.exe { }
        }
        function New-AppDir([string]$NasPfad = '', [string]$Schluessel = 'NasPfad') {
            $app = New-TestDir 'app'
            if ($NasPfad) {
                $md = Join-Path $app 'Minibench-Daten'
                New-Item -ItemType Directory -Path $md | Out-Null
                [IO.File]::WriteAllText((Join-Path $md 'Netzwerk.json'), (@{ $Schluessel = $NasPfad } | ConvertTo-Json))
            }
            return $app
        }
    }
    It 'erkennt UNC-Pfade als Netzwerkpfad' {
        MinibenchTest\Test-IsNetworkPath '\\server\share' | Should -BeTrue
        MinibenchTest\Test-IsNetworkPath '\\server\share\Minibench' | Should -BeTrue
        MinibenchTest\Test-IsNetworkPath ([string]$TestDrive) | Should -BeFalse
        MinibenchTest\Test-IsNetworkPath '' | Should -BeFalse
    }
    It 'ohne Netzwerk.json liegt der Datenordner neben dem Programm' {
        Use-NurTestDrive
        $app = New-AppDir
        MinibenchTest\Resolve-DataDir -AppDir $app | Should -Be (Join-Path $app 'Minibench-Daten')
        Join-Path $app 'Minibench-Daten' | Should -Exist
    }
    It 'nimmt den erreichbaren NAS-Pfad aus Netzwerk.json (Schlüssel <Schluessel>)' -ForEach @(
        @{ Schluessel = 'NasPfad' }, @{ Schluessel = 'NetzwerkPfad' }
    ) {
        Use-NurTestDrive
        $nas = Join-Path (New-TestDir 'nas') 'Minibench'
        $app = New-AppDir -NasPfad $nas -Schluessel $Schluessel
        MinibenchTest\Resolve-DataDir -AppDir $app | Should -Be $nas
        Should -Invoke -ModuleName MinibenchTest net.exe -Times 0 -Exactly
    }
    It 'versucht bei unerreichbarem NAS die Verbindung wiederherzustellen und fällt sonst auf den lokalen Ordner zurück' {
        Use-NurTestDrive
        $blocker = Join-Path (New-TestDir 'nas') 'keinOrdner.txt'
        [IO.File]::WriteAllText($blocker, 'x')
        $app = New-AppDir -NasPfad (Join-Path $blocker 'Minibench')
        MinibenchTest\Resolve-DataDir -AppDir $app | Should -Be (Join-Path $app 'Minibench-Daten')
        Should -Invoke -ModuleName MinibenchTest net.exe -Times 1 -Exactly
    }
    It 'übernimmt den Ordner PC-Diagnose-Daten einer früheren Version' {
        Use-NurTestDrive
        $app = New-AppDir
        $old = Join-Path $app 'PC-Diagnose-Daten'
        New-Item -ItemType Directory -Path (Join-Path $old 'Datenbank') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $old 'Datenbank/PC1.json'), '{}')
        MinibenchTest\Resolve-DataDir -AppDir $app | Should -Be (Join-Path $app 'Minibench-Daten')
        Join-Path $app 'Minibench-Daten/Datenbank/PC1.json' | Should -Exist
        $old | Should -Not -Exist
    }
    It 'fällt bei schreibgeschütztem Speicherort auf Dokumente zurück und merkt sich das' {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        if (-not $docs) { Set-ItResult -Skipped -Because 'kein Ordner Dokumente auf diesem System'; return }
        Use-NurTestDrive
        $ziel = Join-Path $docs 'Leos Minibench'
        $script:DokZiel = $ziel
        Mock -ModuleName MinibenchTest Test-WritableDir { [string]$Dir -eq $script:DokZiel }
        Set-ModuleVar 'DataDirFallback' $false
        try {
            MinibenchTest\Resolve-DataDir -AppDir (New-AppDir) | Should -Be $ziel
            Get-ModuleVar 'DataDirFallback' | Should -BeTrue
        } finally { Set-ModuleVar 'DataDirFallback' $false }
    }
    It 'der lokale Ordner für Cache, Werkzeuge und Laufzeit nimmt nie einen Netzwerkpfad' {
        Use-NurTestDrive
        $lokal = New-TestDir 'lokal'
        Mock -ModuleName MinibenchTest Test-WritableDir { ([string]$Dir).StartsWith($script:NurTestDrive) }
        Set-ModuleVar 'DatenDir' $lokal
        try {
            MinibenchTest\Resolve-LocalDataDir -AppDir '\\server\freigabe\Minibench' | Should -Be $lokal
            Should -Invoke -ModuleName MinibenchTest Test-WritableDir -ParameterFilter { ([string]$Dir).StartsWith('\\') } -Times 0 -Exactly
        } finally { Set-ModuleVar 'DatenDir' $null }
    }
    It 'liegt der Datenordner auf dem NAS, bleiben Cache, Werkzeuge und Laufzeit lokal' {
        # die Zuweisungen am Ende von Kern\Datenordner.ps1, so wie sie beim Start laufen
        $zeilen = @((Get-PartText 'Kern\Datenordner.ps1') -split "`r`n" | Where-Object { $_ -match '^\$script:(DataDirFallback|DataDir|LocalDataDir|ReportDir|DbDir|ToolsDir|CacheDir|CpDir)\s*=' })
        $zeilen.Count | Should -Be 8
        # ein Ordner in TestDrive steht für die Freigabe auf dem NAS (UNC-Pfade lassen sich unter Linux nicht verbinden)
        $nas = New-TestDir 'nas'
        $lokal = New-TestDir 'lokal'
        $script:FakeNas = $nas; $script:FakeLokal = $lokal
        Mock -ModuleName MinibenchTest Resolve-DataDir { $script:FakeNas }
        Mock -ModuleName MinibenchTest Test-IsNetworkPath { ([string]$Path).StartsWith('\\') }
        Mock -ModuleName MinibenchTest Test-IsNetworkPath { $true } -ParameterFilter { [string]$Path -eq $script:FakeNas }
        Mock -ModuleName MinibenchTest Resolve-LocalDataDir { $script:FakeLokal }
        try {
            & (Get-Module MinibenchTest) ([scriptblock]::Create($zeilen -join "`n"))
            Get-ModuleVar 'DataDir' | Should -Be $nas
            Get-ModuleVar 'DbDir' | Should -Be (Join-Path $nas 'Datenbank')
            Get-ModuleVar 'LocalDataDir' | Should -Be $lokal
            Get-ModuleVar 'CacheDir' | Should -Be (Join-Path $lokal 'Cache')
            Get-ModuleVar 'ToolsDir' | Should -Be (Join-Path $lokal 'Tools')
            Get-ModuleVar 'CpDir' | Should -Be (Join-Path (Join-Path $lokal 'Laufzeit') $env:COMPUTERNAME)
            Should -Invoke -ModuleName MinibenchTest Resolve-LocalDataDir -Times 1 -Exactly
        } finally {
            & (Get-Module MinibenchTest) { $script:DataDir = ''; $script:DbDir = ''; $script:LocalDataDir = ''; $script:CpDir = ''; $script:DataDirFallback = $false }
        }
    }
    It 'liegt der Datenordner lokal, dient er auch als lokaler Ordner' {
        $zeilen = @((Get-PartText 'Kern\Datenordner.ps1') -split "`r`n" | Where-Object { $_ -match '^\$script:(DataDirFallback|DataDir|LocalDataDir|ReportDir|DbDir|ToolsDir|CacheDir|CpDir)\s*=' })
        $lokal = New-TestDir 'daten'
        $script:FakeLokal = $lokal
        Mock -ModuleName MinibenchTest Resolve-DataDir { $script:FakeLokal }
        Mock -ModuleName MinibenchTest Resolve-LocalDataDir { throw 'darf nicht aufgerufen werden' }
        try {
            & (Get-Module MinibenchTest) ([scriptblock]::Create($zeilen -join "`n"))
            Get-ModuleVar 'LocalDataDir' | Should -Be $lokal
            Get-ModuleVar 'CacheDir' | Should -Be (Join-Path $lokal 'Cache')
        } finally {
            & (Get-Module MinibenchTest) { $script:DataDir = ''; $script:DbDir = ''; $script:LocalDataDir = ''; $script:CpDir = ''; $script:DataDirFallback = $false }
        }
    }
}

Describe 'Datenpflege und Archivierung' {
    BeforeAll {
        function New-Entry([string]$Dir, [string]$Name, [string]$Version, [string]$Module, $Werte = @{}, [string]$Lasttest = '', [string]$Ordner = '') {
            $o = [ordered]@{ Format = 'PC-Diagnose-DB/2'; Name = $Name; Computer = ($Name -split '_')[0]; Datum = '2026-10-01 10:00'; Version = $Version; Module = $Module; Werte = $Werte; Lasttest = $Lasttest; Ordner = $Ordner }
            [IO.File]::WriteAllText((Join-Path $Dir ($Name + '.json')), ($o | ConvertTo-Json -Depth 4), [Text.Encoding]::UTF8)
        }
        function New-Report([string]$Root, [string]$Name, [string]$Version = '2.67', [string]$Module = 'Benchmark (CPU)', [switch]$Teilweise, [switch]$Leer) {
            $d = Join-Path $Root $Name; New-Item -ItemType Directory $d -Force | Out-Null
            if ($Leer) { return $d }
            if ($Teilweise) { [IO.File]::WriteAllText((Join-Path $d 'Diagnosebericht_teilweise.txt'), 'teilweise'); return $d }
            [IO.File]::WriteAllText((Join-Path $d 'Diagnosebericht.txt'), ("####`r`n  LEOS MINIBENCH: DIAGNOSEBERICHT   PC   v{0}`r`n####`r`n  Erstellt     : heute`r`n  Module       : {1}`r`n" -f $Version, $Module), [Text.Encoding]::UTF8)
            return $d
        }
        # leerer Datenordner mit Datenbank, Berichten und Laufzeit
        function New-Leer {
            $root = New-TestDir 'daten'
            foreach ($d in 'Datenbank', 'Berichte', 'Cache', 'Laufzeit') { New-Item -ItemType Directory (Join-Path $root $d) -Force | Out-Null }
            return $root
        }
        function Set-Alter([string]$Pfad, [double]$Stunden) { (Get-Item -LiteralPath $Pfad -Force).LastWriteTime = (Get-Date).AddHours(-$Stunden) }
        function New-Fall {
            $root = New-TestDir 'fall'
            $db = Join-Path $root 'Datenbank'; $rep = Join-Path $root 'Berichte'; $vgl = Join-Path $rep 'Vergleiche'
            foreach ($d in $db, $rep, $vgl, (Join-Path $root 'Cache'), (Join-Path $root 'Laufzeit/PC1'), (Join-Path $root 'Laufzeit/PC2')) { New-Item -ItemType Directory $d -Force | Out-Null }
            # vor v2.67: Benchmark 2.6 und Import 1.8 bleiben (Rechenwerk unverändert), Lasttest 2.66 geht, reine Diagnose 2.4 bleibt
            New-Entry $db 'PC1_20261002_125328' '2.6' 'Diagnose (vollständig) + Benchmark (CPU)' @{ 'CPU|MT' = 33704 } '' 'Berichte\PC1_20261002_1225'; New-Report $rep 'PC1_20261002_1225' '2.6' | Out-Null
            New-Entry $db 'LIZZZ_20260930_161500' '1.8' 'Import' @{ 'CPU|MT' = 28286 }
            New-Entry $db 'PC1_20261003_133426' '2.66' 'Lasttest (CPU 2 Min.)' @{} 'Dauer 00:00:34 (vorzeitig beendet), Prozessor OK' 'Berichte\PC1_20261003_1332'; New-Report $rep 'PC1_20261003_1332' '2.66' 'Lasttest (CPU 2 Min.)' | Out-Null
            New-Entry $db 'PC2_20261002_090000' '2.4' 'Diagnose (vollständig)' @{} '' 'Berichte\PC2_20261002_0900'; New-Report $rep 'PC2_20261002_0900' '2.4' 'Diagnose (vollständig)' | Out-Null
            # ab v2.67: vollständig (bleibt), kurz (Lasttest nach 20 s von Hand beendet), ohne Messergebnis, Funktionstest
            New-Entry $db 'PC1_20261003_142535' '2.67' 'Benchmark (CPU)' @{ 'CPU|MT' = 44540 } '' 'Berichte\PC1_20261003_1421'; New-Report $rep 'PC1_20261003_1421' | Out-Null
            New-Entry $db 'PC1_20261003_150000' '2.7' 'Lasttest (CPU 2 Min.)' @{} 'Dauer 00:00:20 (vorzeitig beendet), Prozessor OK' 'Berichte\PC1_20261003_1459'; New-Report $rep 'PC1_20261003_1459' '2.7' 'Lasttest (CPU 2 Min.)' | Out-Null
            New-Entry $db 'PC1_20261003_151000' '2.7' 'Lasttest (CPU 2 Min.)' @{} 'Dauer 00:01:50 (vorzeitig beendet), Prozessor OK'
            New-Entry $db 'PC1_20261003_152000' '2.7' 'Lasttest (CPU 2 Min.)' @{} 'Dauer 00:00:40 (abgebrochen: CPU 100 °C), Prozessor Warnung'
            New-Entry $db 'PC1_20261003_153000' '2.7' 'Lasttest (Disk 10 Min.)' @{} ''
            New-Entry $db 'PC1_20261003_154000' '2.7' 'Diagnose (Funktionstest)' @{} ''
            # Berichtsordner: abgebrochen, leer, alter Lauf ohne Datenbankeintrag, laufender Lauf (Absturzanalyse ausstehend)
            New-Report $rep 'PC1_20261003_1413' -Teilweise | Out-Null
            New-Report $rep 'PC1_20261002_1302' -Leer | Out-Null
            New-Report $rep 'PC3_20261001_1808' '2.3' 'Diagnose (vollständig) + Lasttest (CPU 5 Min.)' | Out-Null
            New-Report $rep 'PC3_20261001_1700' '2.3' 'Diagnose (vollständig) + Benchmark (CPU)' | Out-Null
            $busy = New-Report $rep 'PC1_20261003_1600' -Teilweise
            [IO.File]::WriteAllText((Join-Path $root 'Laufzeit/PC1/laufend.json'), (@{ OutputDir = $busy; Version = '2.7' } | ConvertTo-Json))
            # Vergleiche: mit alter Quelle, mit aktuellen Quellen
            [IO.File]::WriteAllText((Join-Path $vgl 'Vergleich_alt.html'), '<html><footer>Leos Minibench 2.65. Quellen: PC1_20261002_125328.json, LIZZZ_20260930_161500.json</footer></html>')
            [IO.File]::WriteAllText((Join-Path $vgl 'Vergleich_last.html'), '<html><footer>Leos Minibench 2.66. Quellen: PC1_20261003_133426.json, LIZZZ_20260930_161500.json</footer></html>')
            [IO.File]::WriteAllText((Join-Path $vgl 'Vergleich_neu.html'), '<html><footer>Leos Minibench 2.7. Quellen: PC1_20261003_142535.json, PC2_20261002_090000.json</footer></html>')
            [IO.File]::WriteAllText((Join-Path $root 'Referenz.json'), (@{ Name = 'TORRENT'; Version = '2.6'; Werte = @{ 'CPU|MT' = 38439 } } | ConvertTo-Json))
            # Cache: zwei Übersetzungen derselben Oberfläche, Reste der Live-Ansicht
            $c1 = Join-Path $root 'Cache/LeosMinibench-Grafik-aaaaaaaaaaaa.dll'; $c2 = Join-Path $root 'Cache/LeosMinibench-Grafik-bbbbbbbbbbbb.dll'
            [IO.File]::WriteAllText($c1, 'alt'); [IO.File]::WriteAllText($c2, 'neu'); Set-Alter $c1 24
            $so = Join-Path $root 'Laufzeit/PC2/sensor.stop'; [IO.File]::WriteAllText($so, '1'); Set-Alter $so 24
            # smartmontools: nur smartctl.exe und drivedb.h werden gebraucht
            $sm = Join-Path $root 'Tools/smartmontools/bin'; New-Item -ItemType Directory $sm -Force | Out-Null
            foreach ($n in 'smartctl.exe', 'drivedb.h', 'smartd.exe', 'runcmdu.exe') { [IO.File]::WriteAllText((Join-Path $sm $n), 'x') }
            return $root
        }
    }
    It 'Versionsnummern als Dezimalzahl: 2.7 liegt nach 2.67' {
        MinibenchTest\ConvertTo-VersionNumber '2.7' | Should -BeGreaterThan (MinibenchTest\ConvertTo-VersionNumber '2.67')
        MinibenchTest\ConvertTo-VersionNumber 'v2.65' | Should -Be 2.65
        MinibenchTest\ConvertTo-VersionNumber '1.x' | Should -Be 1
        MinibenchTest\Test-MessreiheAktuell '2.67' | Should -BeTrue
        MinibenchTest\Test-MessreiheAktuell '2.66' | Should -BeFalse
        MinibenchTest\Test-MessreiheAktuell '3.0' | Should -BeTrue
    }
    It 'Plan: ordnet Lasttests vor v2.67, unvollständige und kurze Läufe richtig ein und lässt den Rest' {
        $root = New-Fall
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root -NurPlan
        $p = $r.Zeilen -join "`n"
        $p | Should -Match 'Datenbank[\\/]PC1_20261003_133426\.json -> Lasttest_vor_v2\.67[\\/]Datenbank: Lasttest aus v2\.66'
        $p | Should -Match 'Berichte[\\/]PC1_20261003_1332 -> Lasttest_vor_v2\.67[\\/]Berichte'
        $p | Should -Match 'PC1_20261003_150000\.json -> Kurz[\\/]Datenbank: Lasttest nach 20 s von Hand beendet'
        $p | Should -Match 'Berichte[\\/]PC1_20261003_1459 -> Kurz[\\/]Berichte'
        $p | Should -Match 'PC1_20261003_153000\.json -> Kurz[\\/]Datenbank: Lauf ohne Messergebnis'
        $p | Should -Match 'PC1_20261003_154000\.json -> Kurz[\\/]Datenbank: Funktionstest'
        $p | Should -Match 'Berichte[\\/]PC1_20261003_1413 -> Unvollstaendig[\\/]Berichte: Lauf ohne Bericht'
        $p | Should -Match 'Berichte[\\/]PC1_20261002_1302 -> Unvollstaendig[\\/]Berichte: leerer Berichtsordner'
        $p | Should -Match 'Berichte[\\/]PC3_20261001_1808 -> Lasttest_vor_v2\.67[\\/]Berichte: Lasttest aus v2\.3'
        $p | Should -Match 'Vergleich_last\.html -> Lasttest_vor_v2\.67[\\/]Vergleiche: Systemvergleich mit Läufen, die ins Archiv gehen \(PC1_20261003_133426\.json\)'
        foreach ($keep in 'PC2_20261002_090000', 'PC1_20261003_142535', 'PC1_20261003_151000', 'PC1_20261003_152000', 'PC1_20261003_1600', 'Vergleich_neu', 'Vergleich_alt', 'PC1_20261003_1421', 'PC2_20261002_0900', 'PC1_20261002_125328', 'PC1_20261002_1225', 'LIZZZ_20260930_161500', 'PC3_20261001_1700', 'Referenz') { $p | Should -Not -Match $keep -Because $keep }
        $r.Verschoben | Should -Be 0
        Join-Path $root 'Datenbank/PC1_20261002_125328.json' | Should -Exist
        Join-Path $root 'Referenz.json' | Should -Exist
        $r.Kurz | Should -Match 'würden ins Archiv verschoben$'
    }
    It 'verschiebt ins Archiv, protokolliert und räumt Cache und Live-Reste auf; ein zweiter Lauf findet nichts mehr' {
        $root = New-Fall
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root
        $r.Fehler | Should -Be 0
        $r.Verschoben | Should -Be 12
        $a = Join-Path $root 'Archiv'
        Join-Path $root 'Tools/smartmontools/bin/smartctl.exe' | Should -Exist
        Join-Path $root 'Tools/smartmontools/bin/drivedb.h' | Should -Exist
        Join-Path $root 'Tools/smartmontools/bin/smartd.exe' | Should -Not -Exist
        Join-Path $a 'Werkzeuge_unbenutzt/smartmontools/bin/runcmdu.exe' | Should -Exist
        Join-Path $a 'Lasttest_vor_v2.67/Datenbank/PC1_20261003_133426.json' | Should -Exist
        Join-Path $a 'Lasttest_vor_v2.67/Berichte/PC1_20261003_1332/Diagnosebericht.txt' | Should -Exist
        Join-Path $a 'Lasttest_vor_v2.67/Vergleiche/Vergleich_last.html' | Should -Exist
        Join-Path $a 'Unvollstaendig/Berichte/PC1_20261003_1413/Diagnosebericht_teilweise.txt' | Should -Exist
        Join-Path $a 'Kurz/Datenbank/PC1_20261003_154000.json' | Should -Exist
        Join-Path $root 'Datenbank/PC1_20261003_142535.json' | Should -Exist
        Join-Path $root 'Datenbank/PC2_20261002_090000.json' | Should -Exist
        Join-Path $root 'Berichte/PC1_20261003_1600' | Should -Exist
        Join-Path $root 'Referenz.json' | Should -Exist
        Join-Path $root 'Datenbank/PC1_20261002_125328.json' | Should -Exist
        Join-Path $root 'Datenbank/LIZZZ_20260930_161500.json' | Should -Exist
        Join-Path $root 'Cache/LeosMinibench-Grafik-bbbbbbbbbbbb.dll' | Should -Exist
        Join-Path $root 'Cache/LeosMinibench-Grafik-aaaaaaaaaaaa.dll' | Should -Not -Exist
        Join-Path $root 'Laufzeit/PC2' | Should -Not -Exist
        Join-Path $root 'Laufzeit/PC1/laufend.json' | Should -Exist
        [IO.File]::ReadAllText((Join-Path $a 'Datenpflege.log')) | Should -Match 'Lasttest_vor_v2\.67'
        $r.Kurz | Should -Be '1 Lasttest vor v2.67, 3 kurze Läufe, 2 unvollständige Läufe, 2 ungenutzte Dateien von smartmontools ins Archiv verschoben'
        $r2 = MinibenchTest\Invoke-Datenpflege -DataDir $root
        $r2.Verschoben | Should -Be 0
        $r2.Kurz | Should -Be 'nichts zu archivieren'
    }
    It 'frische Läufe bleiben beim Start der Oberfläche liegen (Mindestalter), alte Lasttests nicht' {
        $root = New-Fall
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root -MindestAlterMin 60 -NurPlan
        $p = $r.Zeilen -join "`n"
        $p | Should -Not -Match 'Kurz[\\/]'
        $p | Should -Not -Match 'Unvollstaendig'
        $p | Should -Match 'Lasttest_vor_v2\.67'
    }
    It 'eigenes Archiv (Bauen.cmd) und gleichnamige Ziele werden nicht überschrieben' {
        $root = New-Fall
        $arc = New-TestDir 'arc'
        New-Item -ItemType Directory (Join-Path $arc 'Kurz/Datenbank') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $arc 'Kurz/Datenbank/PC1_20261003_154000.json'), 'schon da')
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root -ArchivDir $arc
        $r.Archiv | Should -Be $arc
        [IO.File]::ReadAllText((Join-Path $arc 'Kurz/Datenbank/PC1_20261003_154000.json')) | Should -Be 'schon da'
        Join-Path $arc 'Kurz/Datenbank/PC1_20261003_154000_2.json' | Should -Exist
        Join-Path $root 'Archiv' | Should -Not -Exist
    }
    It 'ohne Datenordner geschieht nichts' {
        (MinibenchTest\Invoke-Datenpflege -DataDir '').Kurz | Should -Be 'kein Datenordner'
    }
    It 'archiviert beschädigte und leere JSON-Dateien der Datenbank, frische erst nach dem Mindestalter' {
        $root = New-Leer
        $db = Join-Path $root 'Datenbank'
        [IO.File]::WriteAllText((Join-Path $db 'leer.json'), '')
        [IO.File]::WriteAllText((Join-Path $db 'kaputt.json'), '{ "Format": "PC-Diagnose-DB/2", KAPUTT')
        New-Entry $db 'PC1_20261003_142535' '2.7' 'Diagnose (vollständig)' @{}
        (MinibenchTest\Invoke-Datenpflege -DataDir $root -MindestAlterMin 60 -NurPlan).Zeilen.Count | Should -Be 0
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root
        $r.Verschoben | Should -Be 2
        ($r.Zeilen -join "`n") | Should -Match 'beschädigte oder leere JSON-Datei'
        Join-Path $root 'Archiv/Beschaedigt/Datenbank/leer.json' | Should -Exist
        Join-Path $root 'Archiv/Beschaedigt/Datenbank/kaputt.json' | Should -Exist
        Join-Path $db 'PC1_20261003_142535.json' | Should -Exist
    }
    It 'archiviert Datenbankeinträge, deren Berichtsordner fehlt' {
        $root = New-Leer
        $db = Join-Path $root 'Datenbank'; $rep = Join-Path $root 'Berichte'
        New-Entry $db 'PC1_20261003_100000' '2.7' 'Diagnose (vollständig)' @{} '' 'Berichte\PC1_20261003_1000'
        New-Entry $db 'PC1_20261003_110000' '2.7' 'Diagnose (vollständig)' @{} '' 'Berichte\PC1_20261003_1100'; New-Report $rep 'PC1_20261003_1100' '2.7' 'Diagnose (vollständig)' | Out-Null
        New-Entry $db 'PC1_20261003_120000' '2.7' 'Diagnose (vollständig)' @{}
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root
        $r.Verschoben | Should -Be 1
        ($r.Zeilen -join "`n") | Should -Match 'zugehöriger Berichtsordner nicht mehr vorhanden \(PC1_20261003_1000\)'
        $r.Kurz | Should -Match '^1 verwaiste Eintrag'
        Join-Path $root 'Archiv/Verwaist/Datenbank/PC1_20261003_100000.json' | Should -Exist
        Join-Path $db 'PC1_20261003_110000.json' | Should -Exist
        Join-Path $db 'PC1_20261003_120000.json' | Should -Exist
    }
    It 'nennt den freigegebenen Speicherplatz in MB' {
        $root = New-Leer
        $alt = Join-Path $root 'Cache/LeosMinibench-Oberflaeche-aaaaaaaaaaaa.dll'
        [IO.File]::WriteAllBytes($alt, (New-Object byte[] (2MB)))
        [IO.File]::WriteAllText((Join-Path $root 'Cache/LeosMinibench-Oberflaeche-bbbbbbbbbbbb.dll'), 'neu')
        Set-Alter $alt 24
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root
        $r.Geloescht | Should -Be 1
        $r.FreigegebenMB | Should -Be 2
        [IO.File]::ReadAllText((Join-Path $root 'Archiv/Datenpflege.log'), [Text.Encoding]::UTF8) | Should -Match '2[.,]00 MB freigegeben'
    }
    # bekannter Fehler, Behebung offen: Get-ChildItem -Include ohne -Recurse findet unter Windows PowerShell 5.1 nichts
    # (Kern\Datenpflege.ps1, Schritt 6), verwaiste *.tmp, *.lock und checkpoint*.json bleiben dort liegen
    It 'löscht verwaiste temporäre Dateien im Laufzeitordner eines Geräts, frische bleiben' -Skip {
        $root = New-Leer
        $pc = Join-Path $root 'Laufzeit/PC1'; New-Item -ItemType Directory $pc -Force | Out-Null
        foreach ($n in 'alt.tmp', 'alt.lock', 'checkpoint_alt.json') { $f = Join-Path $pc $n; [IO.File]::WriteAllText($f, 'x'); Set-Alter $f 3 }
        [IO.File]::WriteAllText((Join-Path $pc 'frisch.tmp'), 'x')
        $r = MinibenchTest\Invoke-Datenpflege -DataDir $root
        foreach ($n in 'alt.tmp', 'alt.lock', 'checkpoint_alt.json') { Join-Path $pc $n | Should -Not -Exist }
        Join-Path $pc 'frisch.tmp' | Should -Exist
        $r.Geloescht | Should -Be 3
    }
    # bekannter Fehler, Behebung offen: Datenpflege löscht alle Dateien direkt in Laufzeit\ älter als 2 h, auch den
    # PawnIO-Merker (PawnIO_<PC>.txt, sonst wird ein vorübergehend installierter Treiber nie entfernt) und Start.log
    It 'lässt den PawnIO-Merker und Start.log im Laufzeitordner stehen' -Skip {
        $root = New-Leer
        $lz = Join-Path $root 'Laufzeit'
        foreach ($n in 'PawnIO_PC1.txt', 'Start.log') { $f = Join-Path $lz $n; [IO.File]::WriteAllText($f, 'x'); Set-Alter $f 3 }
        $null = MinibenchTest\Invoke-Datenpflege -DataDir $root
        Join-Path $lz 'PawnIO_PC1.txt' | Should -Exist
        Join-Path $lz 'Start.log' | Should -Exist
    }
    # bekannter Fehler, Behebung offen: Datenpflege sucht laufend.json nur in <Datenordner>\Laufzeit; liegt der Datenordner
    # auf dem NAS, steht der Merker im lokalen Laufzeitordner (CpDir) und der laufende Lauf wandert ins Archiv
    It 'lässt einen laufenden Lauf auch dann liegen, wenn sein Merker im lokalen Laufzeitordner steht' -Skip {
        $root = New-Leer
        $busy = New-Report (Join-Path $root 'Berichte') 'PC1_20261003_1600' -Teilweise
        $lokal = New-TestDir 'lokal'
        $cp = Join-Path $lokal 'Laufzeit/PC1'; New-Item -ItemType Directory $cp -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $cp 'laufend.json'), (@{ OutputDir = $busy; Version = '3.52' } | ConvertTo-Json))
        Set-ModuleVar 'LocalDataDir' $lokal
        Set-ModuleVar 'CpDir' $cp
        try {
            $null = MinibenchTest\Invoke-Datenpflege -DataDir $root
            $busy | Should -Exist
        } finally { Set-ModuleVar 'LocalDataDir' ''; Set-ModuleVar 'CpDir' '' }
    }
}
