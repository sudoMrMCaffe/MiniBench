# Fehler aus dem Praxistest vom 01.10.2026 (v2.3) als Testfälle für v2.4. Testdaten unter tests\Daten:
#   Akku\       Auszüge aus powercfg /batteryreport zweier Notebooks (HTML) und eine XML-Probe
#   WinSAT\     winsat dwm -xml von TORRENT (Radeon) und zwei Notebooks mit Prozessorgrafik (UTF-16)
#   Datenbank\  Einträge der Vergleichsdatenbank vom 30.09.2026

Describe 'Sensoren: Grenzwerte, Plausibilität, dGPU und iGPU' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Parts 'Kern\Werkzeuge.ps1', 'Kern\Sensoren.ps1' -Functions 'Get-SafeName', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent'
        function New-Rd([string]$Gruppe, [string]$Art, [string]$Name, $Wert, [string]$Geraet = 'Gerät', [string]$Quelle = 'LHM') {
            MinibenchTest\New-SensorReading ('{0}/{1}/{2}/{3}' -f $Quelle, $Geraet, $Art, $Name) $Quelle $Gruppe $Geraet $Art $Name '' $Wert ''
        }
        function Get-Classified($Rd, $Limits = $null) { $l = New-Object System.Collections.Generic.List[object]; foreach ($r in $Rd) { $l.Add($r) }; MinibenchTest\Set-SensorClassification $l $Limits; return $l.ToArray() }
    }

    It 'Warn- und Abschalttemperatur der NVMe sind Grenzwerte, keine Messung (Praxistest: 94 °C als Temperatur)' {
        $rd = Get-Classified @((New-Rd 'Datenträger' 'Temperatur' 'Temperature' 41 'Samsung SSD 980'), (New-Rd 'Datenträger' 'Temperatur' 'Warning Temperature' 84 'Samsung SSD 980'),
            (New-Rd 'Datenträger' 'Temperatur' 'Critical Temperature' 94 'Samsung SSD 980'), (New-Rd 'RAM' 'Temperatur' 'Thermal Sensor High Limit' 85 'DIMM #1'), (New-Rd 'CPU' 'Temperatur' 'Core #1 Distance to TjMax' 40 'Intel Core i5'))
        ($rd | Where-Object Name -eq 'Warning Temperature').Art | Should -Be 'Grenzwert'
        ($rd | Where-Object Name -eq 'Critical Temperature').Art | Should -Be 'Grenzwert'
        ($rd | Where-Object Name -eq 'Thermal Sensor High Limit').Art | Should -Be 'Grenzwert'
        ($rd | Where-Object Name -match 'Distance').Art | Should -Be 'Abstand'
        ($rd | Where-Object Name -eq 'Temperature').Art | Should -Be 'Temperatur'
        (MinibenchTest\Get-SensorLead $rd).DiskTemp | Should -Be 41
    }
    It 'nur Grenzwerte: keine Datenträgertemperatur' {
        $rd = Get-Classified @((New-Rd 'Datenträger' 'Temperatur' 'Warning Temperature' 84 'NVMe'), (New-Rd 'Datenträger' 'Temperatur' 'Critical Temperature' 94 'NVMe'))
        (MinibenchTest\Get-SensorLead $rd).DiskTemp | Should -BeNullOrEmpty
    }
    It '590 W an einer Prozessorgrafik ist unplausibel und zählt nicht (Praxistest ULB-PC10039)' {
        $rd = Get-Classified @((New-Rd 'GPU' 'Leistung' 'GPU Power' 590 'Intel(R) Iris(R) Xe Graphics'), (New-Rd 'GPU' 'Temperatur' 'GPU Core' 52 'Intel(R) Iris(R) Xe Graphics'))
        $w = $rd | Where-Object Name -eq 'GPU Power'
        $w.Status | Should -Be 'unplausibel'; [double]::IsNaN($w.Wert) | Should -BeTrue; $w.Roh | Should -Be 590
        $w.Hinweis | Should -Match '80 W'
        $l = MinibenchTest\Get-SensorLead $rd
        $l.GpuW | Should -BeNullOrEmpty; $l.GpuTemp | Should -Be 52
    }
    It 'NVIDIA: Grenze aus dem Power-Limit laut nvidia-smi' {
        $lim = MinibenchTest\ConvertFrom-NvidiaSmiLimits "NVIDIA GeForce RTX 3060, 170.00, 170.00, 170.00`r`nNVIDIA GeForce MX550, [N/A], 25.00, 30.00"
        $lim['NVIDIA GeForce RTX 3060'] | Should -Be 170; $lim['NVIDIA GeForce MX550'] | Should -Be 30
        $rd = Get-Classified @((New-Rd 'GPU' 'Leistung' 'GPU Package' 168 'NVIDIA GeForce RTX 3060'), (New-Rd 'GPU' 'Leistung' 'GPU Package' 45 'NVIDIA GeForce MX550')) $lim
        ($rd | Where-Object Geraet -match '3060').Status | Should -Be ''
        ($rd | Where-Object Geraet -match 'MX550').Status | Should -Be 'unplausibel'
    }
    It 'feste Obergrenzen ohne nvidia-smi' {
        $rd = Get-Classified @((New-Rd 'GPU' 'Leistung' 'GPU Package' 230 'AMD Radeon RX 7800 XT'), (New-Rd 'GPU' 'Leistung' 'GPU Package' 750 'AMD Radeon RX 6800'),
            (New-Rd 'GPU' 'Leistung' 'GPU Package' 260 'NVIDIA GeForce RTX 4070 Laptop GPU'), (New-Rd 'CPU' 'Leistung' 'CPU Package' 620 'AMD Ryzen 9'), (New-Rd 'CPU' 'Temperatur' 'CPU Package' 255 'AMD Ryzen 9'))
        @($rd | Where-Object Status -eq 'unplausibel' | ForEach-Object { $_.Geraet + '|' + $_.Art }) | Should -Be @('AMD Radeon RX 6800|Leistung', 'NVIDIA GeForce RTX 4070 Laptop GPU|Leistung', 'AMD Ryzen 9|Leistung', 'AMD Ryzen 9|Temperatur')
    }
    It 'Art der Grafikeinheit <Name> = <Art>' -ForEach @(
        @{ Name = 'Intel(R) UHD Graphics 770'; Art = 'iGPU' }, @{ Name = 'Intel(R) Iris(R) Xe Graphics'; Art = 'iGPU' }, @{ Name = 'Intel(R) Arc(TM) A770 Graphics'; Art = 'dGPU' }
        @{ Name = 'AMD Radeon(TM) Graphics'; Art = 'iGPU' }, @{ Name = 'AMD Radeon 780M'; Art = 'iGPU' }, @{ Name = 'AMD Radeon RX 6800'; Art = 'dGPU' }
        @{ Name = 'NVIDIA GeForce RTX 3060'; Art = 'dGPU' }, @{ Name = 'Microsoft Basic Display Adapter'; Art = 'virtuell' }, @{ Name = 'Parsec Virtual Display Adapter'; Art = 'virtuell' }
    ) { MinibenchTest\Get-GpuKind $Name | Should -Be $Art }
    It 'Hybridgrafik: Grafikkarte als Leitwert, Prozessorgrafik getrennt' {
        $rd = Get-Classified @((New-Rd 'GPU' 'Temperatur' 'GPU Core' 48 'Intel(R) UHD Graphics 770'), (New-Rd 'GPU' 'Takt' 'GPU Core' 1450 'Intel(R) UHD Graphics 770'), (New-Rd 'GPU' 'Leistung' 'GPU Power' 9.5 'Intel(R) UHD Graphics 770'),
            (New-Rd 'GPU' 'Temperatur' 'GPU Core' 63 'NVIDIA GeForce RTX 3060'), (New-Rd 'GPU' 'Leistung' 'GPU Package' 151 'NVIDIA GeForce RTX 3060'), (New-Rd 'GPU' 'Auslastung' 'GPU Core' 99 'NVIDIA GeForce RTX 3060'),
            (New-Rd 'GPU' 'Leistung' 'GPU Package' 0 'Parsec Virtual Display Adapter'))
        $l = MinibenchTest\Get-SensorLead $rd
        $l.GpuName | Should -Be 'NVIDIA GeForce RTX 3060'; $l.GpuTemp | Should -Be 63; $l.GpuW | Should -Be 151
        $l.IGpuName | Should -Be 'Intel(R) UHD Graphics 770'; $l.IGpuTemp | Should -Be 48; $l.IGpuMHz | Should -Be 1450; $l.IGpuW | Should -Be 9.5
    }
    It 'nur Prozessorgrafik: sie ist der Leitwert' {
        $l = MinibenchTest\Get-SensorLead (Get-Classified @((New-Rd 'GPU' 'Temperatur' 'GPU Core' 55 'Intel(R) Iris(R) Xe Graphics')))
        $l.GpuName | Should -Match 'Iris'; $l.GpuTemp | Should -Be 55; $l.IGpuName | Should -Be ''
    }
    It 'Takt wie Task-Manager vor Sensortakt, höchster Kerntakt getrennt' {
        $rd = Get-Classified @((New-Rd 'CPU' 'Takt' 'Takt wie Task-Manager' 4123 'Windows-Leistungszähler' 'Windows'), (New-Rd 'CPU' 'Takt' 'P-Core #1' 4400), (New-Rd 'CPU' 'Takt' 'P-Core #2' 4700), (New-Rd 'CPU' 'Takt' 'E-Core #1' 3300), (New-Rd 'CPU' 'Takt' 'Bus Speed' 100))
        $l = MinibenchTest\Get-SensorLead $rd
        $l.CpuMHz | Should -Be 4123; $l.CpuMHzQ | Should -Be 'Windows'; $l.CpuMHzMax | Should -Be 4700
    }
    It 'ohne Windows-Zähler: Mittel der Kerntakte' {
        $l = MinibenchTest\Get-SensorLead (Get-Classified @((New-Rd 'CPU' 'Takt' 'Core #1' 4000), (New-Rd 'CPU' 'Takt' 'Core #2' 4400)))
        $l.CpuMHz | Should -Be 4200; $l.CpuMHzQ | Should -Be 'LHM'; $l.CpuMHzMax | Should -Be 4400
    }
    It 'Sortierung: Gruppe, Grafikkarte vor Prozessorgrafik, Art, Zahlen numerisch' {
        $rd = @((New-Rd 'GPU' 'Temperatur' 'GPU Core' 40 'Intel(R) UHD Graphics 770'), (New-Rd 'Datenträger' 'Temperatur' 'Temperature' 40 'NVMe'), (New-Rd 'CPU' 'Takt' 'Core #10' 1), (New-Rd 'CPU' 'Takt' 'Core #2' 1),
            (New-Rd 'CPU' 'Temperatur' 'CPU Package' 1), (New-Rd 'GPU' 'Temperatur' 'GPU Core' 60 'NVIDIA GeForce RTX 3060'), (New-Rd 'Datenträger' 'Grenzwert' 'Warning Temperature' 84 'NVMe'))
        @(MinibenchTest\Sort-SensorReadings $rd | ForEach-Object { $_.Name + '@' + $_.Geraet }) | Should -Be @('CPU Package@Gerät', 'Core #2@Gerät', 'Core #10@Gerät', 'GPU Core@NVIDIA GeForce RTX 3060', 'GPU Core@Intel(R) UHD Graphics 770', 'Temperature@NVMe', 'Warning Temperature@NVMe')
    }
}

Describe 'Akkubericht' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Functions 'Get-XmlLocal', 'ConvertTo-NullableNumber', 'ConvertFrom-IsoDuration', 'New-BatteryInfo', 'ConvertFrom-BatteryReportXml', 'ConvertFrom-BatteryReportHtml', 'Get-BatteryFinding', 'Format-Duration'
        $script:AkkuDir = Join-Path $global:MinibenchTestData 'Akku'
    }
    It 'HTML mit Tausenderpunkt, Zyklen und Verlauf (ULB-PC10039)' {
        $b = @(MinibenchTest\ConvertFrom-BatteryReportHtml ([IO.File]::ReadAllText((Join-Path $script:AkkuDir 'Notebook_ULB-PC10039.html'))))
        $b.Count | Should -Be 1
        $b[0].Name | Should -Be 'DELL YXP8T3A'; $b[0].DesignmWh | Should -Be 70624; $b[0].VollmWh | Should -Be 66867
        $b[0].VerschleissProzent | Should -Be 5.3; $b[0].Zyklen | Should -Be 32
        $b[0].Verlauf.Count | Should -BeGreaterThan 2; $b[0].Verlauf[0].Zeitraum | Should -Be '2026-08-04 bis 2026-08-11'
        MinibenchTest\Format-Duration $b[0].LaufzeitVoll | Should -Be '6:18 h'
    }
    It 'HTML ohne Zyklenzahl (DESKTOP-2KDA9KP): Zyklen bleiben leer' {
        $b = @(MinibenchTest\ConvertFrom-BatteryReportHtml ([IO.File]::ReadAllText((Join-Path $script:AkkuDir 'Notebook_DESKTOP-2KDA9KP.html'))))
        $b[0].DesignmWh | Should -Be 62016; $b[0].VollmWh | Should -Be 56559; $b[0].VerschleissProzent | Should -Be 8.8
        $b[0].Zyklen | Should -BeNullOrEmpty
        MinibenchTest\Format-Duration $b[0].LaufzeitDesign | Should -Be '6:55 h'
    }
    It 'XML-Fassung mit Namensraum, Laufzeitschätzung und Verlauf' {
        $b = @(MinibenchTest\ConvertFrom-BatteryReportXml ([IO.File]::ReadAllText((Join-Path $script:AkkuDir 'Probe_batteryreport.xml'))))
        $b[0].Name | Should -Be 'PROBE 4C 50WH'; $b[0].Chemie | Should -Be 'LION'; $b[0].Zyklen | Should -Be 612
        $b[0].VerschleissProzent | Should -Be 53
        $b[0].Verlauf.Count | Should -Be 3; $b[0].Verlauf[2].Zeitraum | Should -Be '2026-09-01 bis 2026-10-01'
        MinibenchTest\Format-Duration $b[0].LaufzeitVoll | Should -Be '2:10 h'; MinibenchTest\Format-Duration $b[0].LaufzeitDesign | Should -Be '4:37 h'
    }
    It 'Befund ab 30 % INFO, ab 50 % WARNUNG' {
        MinibenchTest\Get-BatteryFinding (MinibenchTest\New-BatteryInfo 'A' '' '' 50000 35100 100) | Should -BeNullOrEmpty
        (MinibenchTest\Get-BatteryFinding (MinibenchTest\New-BatteryInfo 'A' '' '' 50000 35000 100)).Stufe | Should -Be 'INFO'
        (MinibenchTest\Get-BatteryFinding (MinibenchTest\New-BatteryInfo 'A' '' '' 50000 25000 100)).Stufe | Should -Be 'WARNUNG'
        MinibenchTest\Get-BatteryFinding (MinibenchTest\New-BatteryInfo 'A' '' '' $null 25000 100) | Should -BeNullOrEmpty
    }
    It 'leere oder fremde Eingaben ergeben keinen Akku' {
        @(MinibenchTest\ConvertFrom-BatteryReportXml '').Count | Should -Be 0
        @(MinibenchTest\ConvertFrom-BatteryReportXml '<kein xml').Count | Should -Be 0
        @(MinibenchTest\ConvertFrom-BatteryReportHtml '<html><body>No batteries</body></html>').Count | Should -Be 0
    }
}

Describe 'Systemdateien: DISM und SFC gemeinsam einordnen' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Functions 'Get-IntegrityAssessment'
    }
    It '<Fall>' -ForEach @(
        @{ Fall = 'sauber'; A = @{ DismState = 'Healthy'; SfcClean = $true }; Kat = 'keine Verletzungen'; Stufe = '' }
        @{ Fall = 'Abweichungen bei intaktem Speicher (Praxistest)'; A = @{ DismState = 'Healthy'; SfcViolations = $true; Corrupt = 3; Files = @('a.dll', 'b.dll') }; Kat = 'Abweichungen, Speicher intakt'; Stufe = 'INFO' }
        @{ Fall = 'reparierbar'; A = @{ DismState = 'Repairable'; SfcViolations = $true }; Kat = 'reparierbar'; Stufe = 'WARNUNG' }
        @{ Fall = 'Speicher nicht reparierbar'; A = @{ DismState = 'NonRepairable' }; Kat = 'nicht reparierbar'; Stufe = 'KRITISCH' }
        @{ Fall = 'SFC nicht reparierbar'; A = @{ DismState = 'Healthy'; CannotRepair = 2 }; Kat = 'nicht reparierbar'; Stufe = 'WARNUNG' }
        @{ Fall = 'Verletzungen ohne DISM'; A = @{ SfcViolations = $true }; Kat = 'Verletzungen, Speicher nicht geprüft'; Stufe = 'WARNUNG' }
    ) {
        $r = MinibenchTest\Get-IntegrityAssessment @A
        $r.Kategorie | Should -Be $Kat; $r.Stufe | Should -Be $Stufe
        if ($Stufe) { $r.Befund | Should -Not -BeNullOrEmpty } else { $r.Befund | Should -BeNullOrEmpty }
    }
    It 'nennt die betroffenen Dateien' {
        (MinibenchTest\Get-IntegrityAssessment -DismState 'Healthy' -SfcViolations $true -Files @('Microsoft.Windows.Shell.dll')).Befund | Should -Match 'Microsoft\.Windows\.Shell\.dll'
    }
}

Describe 'WinSAT: gemessene Grafikeinheit' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Parts 'Kern\Werkzeuge.ps1', 'Kern\Sensoren.ps1' -Functions 'ConvertFrom-WinsatDriverVersion', 'Read-WinsatDwmXml', 'Resolve-WinsatAdapter', 'Get-SafeName', 'Send-GuiEvent'
        $script:WsDir = Join-Path $global:MinibenchTestData 'WinSAT'
        function New-Ad([string]$Name, [string]$Treiber, [bool]$Desktop = $true) { [pscustomobject]@{ Name = $Name; Art = (MinibenchTest\Get-GpuKind $Name); Desktop = $Desktop; Treiber = $Treiber } }
    }
    It 'Treiberversion <Zahl> = <Version>' -ForEach @(
        @{ Zahl = '9007199261367216'; Version = '32.0.101.7088' }, @{ Zahl = '9007200633951114'; Version = '32.0.21045.5002' }, @{ Zahl = '8725724284651607'; Version = '31.0.101.2135' }, @{ Zahl = 'x'; Version = '' }
    ) { MinibenchTest\ConvertFrom-WinsatDriverVersion $Zahl | Should -Be $Version }
    It 'liest die UTF-16-Datei von WinSAT (<Datei>)' -ForEach @(
        @{ Datei = 'ULB-PC10039_iGPU.xml'; Vmb = 38163; Treiber = '32.0.101.7088'; Ded = 134217728 }
        @{ Datei = 'TORRENT_dGPU.xml'; Vmb = 293117; Treiber = '32.0.21045.5002'; Ded = 17130815488 }
    ) {
        $r = MinibenchTest\Read-WinsatDwmXml (Join-Path $script:WsDir $Datei)
        $r.Vmb | Should -Be $Vmb; $r.Treiber | Should -Be $Treiber; $r.Dediziert | Should -Be $Ded; $r.Fps | Should -BeGreaterThan 0
    }
    It 'Hybridgrafik: WinSAT hat die Prozessorgrafik gemessen (Zuordnung über die Treiberversion)' {
        $r = MinibenchTest\Read-WinsatDwmXml (Join-Path $script:WsDir 'ULB-PC10039_iGPU.xml')
        $a = MinibenchTest\Resolve-WinsatAdapter $r @((New-Ad 'NVIDIA RTX 3000 Ada Generation Laptop GPU' '32.0.15.8115' $false), (New-Ad 'Intel(R) Iris(R) Xe Graphics' '32.0.101.7088'))
        $a.Art | Should -Be 'iGPU'
    }
    It 'ohne passende Treiberversion entscheidet der eigene Grafikspeicher' {
        $r = MinibenchTest\Read-WinsatDwmXml (Join-Path $script:WsDir 'TORRENT_dGPU.xml')
        $a = MinibenchTest\Resolve-WinsatAdapter $r @((New-Ad 'AMD Radeon(TM) Graphics' '1.0' $false), (New-Ad 'AMD Radeon RX 6800' '2.0'))
        $a.Name | Should -Be 'AMD Radeon RX 6800'
    }
}

# ab v2.65 ohne eingebaute Referenzwerte: Referenz ist nur, was mit "Dieses System als Referenz festlegen" gespeichert wurde
Describe 'Referenz nur über den Haken gespeichert' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Functions 'Read-JsonFile', 'ConvertTo-ValueTable', 'Get-SavedReference', 'Save-BenchReference', 'Get-CurrentRefValues', 'Import-BenchReference', 'Test-HasReference' -Setup @'
$script:RefNone = @{ Name = ''; Datum = ''; Quelle = ''; Werte = @{}; Herkunft = @{} }
$script:Ref = $script:RefNone
$script:BenchRefName = 'TORRENT (Ryzen 5 7600X)'
$script:BenchResults = @()
$ReferenzDatei = ''
function Get-DeviceIdentity { [pscustomobject]@{ Id = 'GERAET-A' } }
function Add-Line { param($t) }
'@
        function Set-Results($list) { Set-ModuleVar 'BenchResults' @($list | ForEach-Object { [pscustomobject]@{ RefKey = $_[0]; Wert = $_[1] } }) }
    }
    BeforeEach {
        $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $d | Out-Null
        Set-ModuleVar 'DataDir' $d
        $script:Dir = $d
    }
    It 'ohne gespeicherte Referenz gibt es keine (keine eingebauten Werte)' {
        MinibenchTest\Import-BenchReference
        MinibenchTest\Test-HasReference | Should -BeFalse
        (Get-ModuleVar 'Ref').Werte.Count | Should -Be 0
    }
    It 'gespeicherte Referenz wird geladen, mit Herkunft je Messgröße' {
        Set-Results @(@('CPU|ST', 3086), @('RAM|Latenz', 81.4))
        @(MinibenchTest\Save-BenchReference).Count | Should -Be 1
        MinibenchTest\Import-BenchReference
        MinibenchTest\Test-HasReference | Should -BeTrue
        $r = Get-ModuleVar 'Ref'
        $r.Werte['CPU|ST'] | Should -Be 3086
        $r.Name | Should -Be 'TORRENT (Ryzen 5 7600X)'
        $r.Herkunft['CPU|ST'] | Should -Match '^Lauf vom \d\d\.\d\d\.\d{4}'
    }
    It 'derselbe PC ergänzt seine Referenz, ungemessene Werte bleiben' {
        Set-Results @(@('CPU|ST', 3000), @('RAM|Lesen', 60))
        [void](MinibenchTest\Save-BenchReference)
        Set-Results @(,@('CPU|ST', 3100))
        [void](MinibenchTest\Save-BenchReference)
        $r = MinibenchTest\Get-SavedReference
        $r.Werte['CPU|ST'] | Should -Be 3100; $r.Werte['RAM|Lesen'] | Should -Be 60
    }
    It 'ein anderer PC ersetzt die Referenz ganz' {
        Set-Results @(@('CPU|ST', 3000), @('RAM|Lesen', 60))
        [void](MinibenchTest\Save-BenchReference)
        & (Get-Module MinibenchTest) { function script:Get-DeviceIdentity { [pscustomobject]@{ Id = 'GERAET-B' } } }
        $env:COMPUTERNAME_ALT = $env:COMPUTERNAME; $env:COMPUTERNAME = 'ANDERER'
        try { Set-Results @(,@('CPU|ST', 2000)); [void](MinibenchTest\Save-BenchReference) } finally { $env:COMPUTERNAME = $env:COMPUTERNAME_ALT; & (Get-Module MinibenchTest) { function script:Get-DeviceIdentity { [pscustomobject]@{ Id = 'GERAET-A' } } } }
        $r = MinibenchTest\Get-SavedReference
        $r.Werte['CPU|ST'] | Should -Be 2000; $r.Werte.ContainsKey('RAM|Lesen') | Should -BeFalse
    }
    It 'Quelltext enthält keine eingebauten Referenzwerte mehr' {
        $t = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Referenz_Vergleich.ps1'))
        $t | Should -Not -Match 'RefDefault'
        $t | Should -Not -Match "'CPU\|ST' = 3086"
    }
}

Describe 'Vergleich aufsteigend sortiert' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Functions 'Get-CompareOrderText', 'Format-Metric', 'Get-RelText', 'New-MetricBarsHtml', 'ConvertTo-HtmlText', 'Get-DeltaHtml'
    }
    It 'Reihenfolge von niedrig nach hoch mit dem eigenen PC an seiner Stelle' {
        Set-ModuleVar 'CmpSystems' @([pscustomobject]@{ Computer = 'TORRENT' }, [pscustomobject]@{ Computer = 'LIZZZ' })
        $row = [pscustomobject]@{ Dieses = 57.4; Werte = @(61.8, 21.3); Format = 'N1'; Einheit = 'GB/s'; LowerBetter = $false }
        $t = MinibenchTest\Get-CompareOrderText $row
        $t | Should -Match '^LIZZZ .* < Dieser PC .* < TORRENT '
    }
    It 'Balken aufsteigend, eigenes System markiert, nicht gemessene am Ende' {
        $h = MinibenchTest\New-MetricBarsHtml -Label 'Einzelkern' -Unit 'Punkte' -Fmt 'N0' -LowerBetter $false -Values @(900, $null, 3086, 1500) -Names @('Dieser PC', 'OHNE', 'TORRENT', 'LIZZZ') -Own 0
        $names = @([regex]::Matches($h, '<i class="sw c\d"></i>([^<]+)</span>') | ForEach-Object { $_.Groups[1].Value })
        $names | Should -Be @('Dieser PC', 'LIZZZ', 'TORRENT', 'OHNE')
        $h | Should -Match 'class="mb[^"]* own"'
        $h | Should -Match 'aufsteigend sortiert'
    }
}

Describe 'KI-Datei: Grenzwerte in smartctl-Ausgaben markiert' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Functions 'Add-SmartLimitMarks'
    }
    It 'markiert Schwellen und Zeitzähler, lässt die Messung unverändert, behält CRLF' {
        $in = "Temperature:                        41 Celsius`r`nWarning  Comp. Temperature Time:    12`r`nCritical Comp. Temperature Time:    0`r`nWarning  Comp. Temp. Threshold:     84 Celsius`r`nCritical Comp. Temp. Threshold:     94 Celsius`r`n"
        $out = MinibenchTest\Add-SmartLimitMarks $in
        $l = $out -split "`r`n"
        $l[0] | Should -Be 'Temperature:                        41 Celsius'
        $l[1] | Should -Match '\[Minuten oberhalb des Grenzwerts, keine Temperatur\]$'
        $l[3] | Should -Match '84 Celsius   \[Grenzwert laut Hersteller, keine Messung\]$'
        $l[4] | Should -Match '94 Celsius   \[Grenzwert laut Hersteller'
        ([regex]::Matches($out, "`r`n")).Count | Should -Be 5
    }
}

Describe 'Kein leerer Bericht: Absturzanalyse und Modulergebnis' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Functions 'Get-EnabledStepCount', 'Test-ModuleResults' -Setup @'
$script:Rec = New-Object System.Collections.ArrayList
function Add-Finding { param($Level, $Area, $Text) [void]$script:Rec.Add("FIND|$Level|$Area|$Text") }
function Add-TestResult { param($Name, $Status, $Detail) [void]$script:Rec.Add("TEST|$Name|$Status|$Detail") }
function Add-Section { param($Title) [void]$script:Rec.Add("SEC|$Title") }
function Add-Line { param($Text) }
function Test-StepEnabled { param($Key) $true }
$ModDiag = $false; $ModBench = $false; $ModLast = $true; $ModRep = $false; $AnalyzeLastRun = $false
$script:Opt = @{}; $script:BenchSel = @{}; $script:LastPlan = @{ CPU = 1 }; $script:RepSel = @()
$script:BenchResults = @(); $script:BenchDisks = @(); $script:LoadParts = @(); $script:RepairLog = @(); $script:Facts = [ordered]@{}; $script:TestResults = @()
$script:SectionErrors = New-Object System.Collections.ArrayList; $script:SkippedByCrash = ''
'@
    }
    It 'nur Lasttest ist ein einziger Schritt (Absturzanalyse überspringt dann nichts)' {
        MinibenchTest\Get-EnabledStepCount | Should -Be 1
    }
    It 'Lasttest ohne Ergebnis: Befund, Testergebnis und Abschnitt mit dem Grund' {
        & (Get-Module MinibenchTest) { [void]$script:SectionErrors.Add([pscustomobject]@{ Abschnitt = 'Lasttest (CPU 1 Min.)'; Meldung = 'Sensorfehler'; Zeile = 1 }) }
        MinibenchTest\Test-ModuleResults
        $rec = @(Get-ModuleVar 'Rec')
        $rec | Where-Object { $_ -like 'FIND|WARNUNG|Ablauf|*Lasttest*Sensorfehler*' } | Should -Not -BeNullOrEmpty
        $rec | Should -Contain 'TEST|Lasttest|Fehler|Abschnitt abgebrochen: Sensorfehler'
        $rec | Should -Contain 'SEC|Lasttest: kein Ergebnis'
    }
    It 'mit Ergebnis kein Eintrag' {
        Set-ModuleVar 'Rec' (New-Object System.Collections.ArrayList); Set-ModuleVar 'LoadParts' @('CPU')
        MinibenchTest\Test-ModuleResults
        @(Get-ModuleVar 'Rec').Count | Should -Be 0
    }
}

Describe 'Werkzeuge je Gerät behalten (Geraete.json)' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Parts 'Kern\Werkzeuge.ps1' -Setup @'
function Get-DeviceIdentity { [pscustomobject]@{ Id = 'GERAET-1' } }
$WerkzeugeBehalten = ''
'@
        function Reset-Keep([string]$Param = '') {
            $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $d | Out-Null
            Set-ModuleVar 'DataDir' $d; Set-ModuleVar 'ToolKeep' $null; Set-ModuleVar 'ToolKeepExplicit' $false; Set-ModuleVar 'WerkzeugeBehalten' $Param
            return $d
        }
    }
    It 'ohne Datei und ohne Parameter: entfernen, früher Behaltenes bleibt aber' {
        Reset-Keep | Out-Null
        MinibenchTest\Get-ToolKeep | Should -Be 'entfernen'
        MinibenchTest\Test-ToolRemoveKept | Should -BeFalse
    }
    It 'Parameter behalten: Werkzeug wird gemerkt und in Geraete.json geschrieben' {
        $d = Reset-Keep 'behalten'
        MinibenchTest\Get-ToolKeep | Should -Be 'behalten'
        MinibenchTest\Set-KeptTool 'PawnIO' $true | Should -BeTrue
        MinibenchTest\Test-KeptTool 'PawnIO' | Should -BeTrue
        $j = Get-Content -Raw (Join-Path $d 'Geraete.json') -Encoding UTF8 | ConvertFrom-Json
        $j.Format | Should -Be 'Minibench-Geraete/1'; @($j.Geraete.'GERAET-1'.Behalten) | Should -Be @('PawnIO')
    }
    It 'gespeicherte Einstellung der Oberfläche gilt, entfernen räumt Behaltenes ab' {
        $d = Reset-Keep
        $json = '{"Format":"Minibench-Geraete/1","Geraete":{"GERAET-1":{"Name":"PC","Werkzeuge":"entfernen","Treiber":"verwenden","Behalten":["smartmontools"],"Geaendert":""}}}'
        [IO.File]::WriteAllText((Join-Path $d 'Geraete.json'), $json)
        MinibenchTest\Get-ToolKeep | Should -Be 'entfernen'
        MinibenchTest\Test-ToolRemoveKept | Should -BeTrue
        MinibenchTest\Test-KeptTool 'smartmontools' | Should -BeTrue
        MinibenchTest\Set-KeptTool 'smartmontools' $false | Should -BeTrue
        $j = Get-Content -Raw (Join-Path $d 'Geraete.json') -Encoding UTF8 | ConvertFrom-Json
        @($j.Geraete.'GERAET-1'.Behalten).Count | Should -Be 0; $j.Geraete.'GERAET-1'.Treiber | Should -Be 'verwenden'
    }
    It 'eine fremde oder kaputte Datei wird ignoriert' {
        $d = Reset-Keep
        [IO.File]::WriteAllText((Join-Path $d 'Geraete.json'), '{kaputt')
        MinibenchTest\Get-ToolKeep | Should -Be 'entfernen'
        MinibenchTest\Test-KeptTool 'PawnIO' | Should -BeFalse
    }
}

Describe 'Behaltener PawnIO wird nur entfernt, wenn es noch derselbe ist' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Parts 'Kern\Werkzeuge.ps1', 'Kern\Sensoren.ps1' -Functions 'Get-SafeName', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent' -Setup @'
function Get-DeviceIdentity { [pscustomobject]@{ Id = 'GERAET-1' } }
$script:FakePawn = [pscustomobject]@{ Installiert = $true; Version = '2.2.0'; Ort = '' }
function Get-PawnIoState { $script:FakePawn }
$WerkzeugeBehalten = ''
'@
        function Set-Json([string]$Behalten, [string]$Version) {
            $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $d | Out-Null
            Set-ModuleVar 'DataDir' $d; Set-ModuleVar 'ToolKeep' $null
            [IO.File]::WriteAllText((Join-Path $d 'Geraete.json'), ('{{"Format":"Minibench-Geraete/1","Geraete":{{"GERAET-1":{{"Name":"PC","Werkzeuge":"entfernen","Treiber":"","PawnIoVersion":"{0}","Behalten":[{1}],"Geaendert":""}}}}}}' -f $Version, $Behalten))
        }
    }
    It 'gleiche Version: ja' { Set-Json '"PawnIO"' '2.2.0'; MinibenchTest\Test-KeptPawnIo | Should -BeTrue }
    It 'andere Version (anderes Programm hat PawnIO installiert): nein' { Set-Json '"PawnIO"' '2.1.0'; MinibenchTest\Test-KeptPawnIo | Should -BeFalse }
    It 'nicht als behalten vermerkt: nein' { Set-Json '' '2.2.0'; MinibenchTest\Test-KeptPawnIo | Should -BeFalse }
    It 'inzwischen deinstalliert: Eintrag wird gelöscht' {
        Set-Json '"PawnIO"' '2.2.0'
        & (Get-Module MinibenchTest) { $script:FakePawn = [pscustomobject]@{ Installiert = $false; Version = ''; Ort = '' } }
        MinibenchTest\Test-KeptPawnIo | Should -BeFalse
        MinibenchTest\Test-KeptTool 'PawnIO' | Should -BeFalse
        & (Get-Module MinibenchTest) { $script:FakePawn = [pscustomobject]@{ Installiert = $true; Version = '2.2.0'; Ort = '' } }
    }
}

Describe 'Abschnittsfehler werden für die Modulprüfung gesammelt' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        Import-MinibenchTestModule -Functions 'Invoke-Section' -Setup @'
$script:StepNo = 0; $script:Timings = New-Object System.Collections.ArrayList; $script:SectionErrors = New-Object System.Collections.Generic.List[object]
$script:Finds = New-Object System.Collections.ArrayList
function Get-PlannedSteps { 3 }
function Add-Section { param($Title, $Prefix) }
function Show-Overall { param($t) }
function Hide-Sub { }
function Save-Partial { }
function Get-CimCached { param($c) }
function Add-Line { param($Text) }
function Write-Checkpoint { param($a, $b) }
function Add-Finding { param($Level, $Area, $Text) [void]$script:Finds.Add("$Level|$Area|$Text") }
'@
        Mock -ModuleName MinibenchTest Write-Warning { }
    }
    It 'der erste Fehler landet in der leeren Liste' {
        MinibenchTest\Invoke-Section 'Lasttest (CPU 1 Min.)' { throw 'Sensorfehler' }
        $e = @(Get-ModuleVar 'SectionErrors')
        $e.Count | Should -Be 1; $e[0].Abschnitt | Should -Be 'Lasttest (CPU 1 Min.)'; $e[0].Meldung | Should -Be 'Sensorfehler'
        @(Get-ModuleVar 'Finds') | Where-Object { $_ -like 'WARNUNG|Ablauf|*Sensorfehler*' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Quelltext: Vorgaben aus dem Praxistest' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Hilfen.ps1')
        $script:Src = $global:MinibenchSrcRoot
        $script:Diag = [IO.File]::ReadAllText((Join-Path $script:Src 'Module/Diagnose/Ablauf.ps1'))
        $script:Gui = [IO.File]::ReadAllText((Join-Path $script:Src 'Oberflaeche/DiagGui.cs'))
        $script:Kopf = [IO.File]::ReadAllText((Join-Path $script:Src '00_Kopf.ps1'))
    }
    It 'keine Lizenzbefunde mehr' { $script:Diag | Should -Not -Match "Add-Finding \w+ 'Lizenz'" }
    It 'SMART-Langtest wartet standardmäßig höchstens 120 Minuten' { $script:Kopf | Should -Match '\[int\]\$SmartTimeoutMinutes = 120' }
    It 'Oberfläche bietet 120 Minuten als Vorgabe' { $script:Gui | Should -Match 'smartMinutes = new int\[\] \{ 30, 60, 90, 120,' ; $script:Gui | Should -Match 'cmbSmartMax = Combo\(220, sm, 3\)' }
    It 'GPU-Wahl in der Oberfläche nur auf Wunsch (Vorgabe aus)' { $script:Gui | Should -Match 'chkGpuWahl = Chk\("[^"]*WinSAT zusätzlich auf der Grafikkarte messen[^"]*", false\)' }
    It 'Diagrammzeichnung gepuffert (Flackern)' { $script:Gui | Should -Match 'EnableDoubleBuffer'; $script:Gui | Should -Match 'Flush\(\)' }
}
