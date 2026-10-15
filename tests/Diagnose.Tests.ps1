# Fachgebiet Diagnose: Startzeit-Analyse, schnell behebbare Konfigurationsfehler (v3.7)

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
}

Describe 'Startzeit-Analyse (Get-SystemBootPerformance)' {
    BeforeAll {
        Import-MinibenchTestModule -Functions 'Get-SystemBootPerformance'
    }

    It 'liest Event 100 und BIOS-POST-Zeit korrekt aus' {
        $xmlData = '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData><Data Name="BootDuration">18500</Data><Data Name="MainPathBootTime">11200</Data><Data Name="BootPostBootTime">7300</Data></EventData></Event>'
        $mockEvent = [pscustomobject]@{
            Id = 100
            TimeCreated = (Get-Date)
        }
        Add-Member -InputObject $mockEvent -MemberType ScriptMethod -Name ToXml -Value ([scriptblock]::Create("return '$xmlData'")) -Force

        Mock -ModuleName MinibenchTest Get-WinEvent { @($mockEvent) }
        Mock -ModuleName MinibenchTest Get-ItemProperty { [pscustomobject]@{ FwPOSTTime = 4500 } }

        $bp = MinibenchTest\Get-SystemBootPerformance
        $bp.Verfuegbar | Should -BeTrue
        $bp.KernelSekunden | Should -Be 11.2
        $bp.DesktopSekunden | Should -Be 7.3
        $bp.OsBootSekunden | Should -Be 18.5
        $bp.BiosSekunden | Should -Be 4.5
        $bp.SystemGesamtSekunden | Should -Be 23.0
    }

    It 'erkennt Autostart-Verzögerer ab 1,0 Sekunde' {
        $xml100 = '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData><Data Name="BootDuration">20000</Data><Data Name="MainPathBootTime">10000</Data><Data Name="BootPostBootTime">10000</Data></EventData></Event>'
        $ev100 = [pscustomobject]@{ Id = 100; TimeCreated = (Get-Date) }
        Add-Member -InputObject $ev100 -MemberType ScriptMethod -Name ToXml -Value ([scriptblock]::Create("return '$xml100'")) -Force

        $xml101 = '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData><Data Name="ImageName">C:\Tools\SlowApp.exe</Data><Data Name="TotalTime">2400</Data></EventData></Event>'
        $ev101 = [pscustomobject]@{ Id = 101; TimeCreated = (Get-Date) }
        Add-Member -InputObject $ev101 -MemberType ScriptMethod -Name ToXml -Value ([scriptblock]::Create("return '$xml101'")) -Force

        Mock -ModuleName MinibenchTest Get-WinEvent {
            if ($FilterHashtable.Id -eq 100) { return @($ev100) }
            return @($ev101)
        }
        Mock -ModuleName MinibenchTest Get-ItemProperty { $null }

        $bp = MinibenchTest\Get-SystemBootPerformance
        $bp.Verfuegbar | Should -BeTrue
        @($bp.Verzoegerer).Count | Should -Be 1
        $bp.Verzoegerer[0].Name | Should -Be 'SlowApp.exe'
        $bp.Verzoegerer[0].DauerSekunden | Should -Be 2.4
    }

    It 'gibt sauberen Fallback aus, wenn Protokoll fehlt oder leer ist' {
        Mock -ModuleName MinibenchTest Get-WinEvent { throw 'No events found' }
        Mock -ModuleName MinibenchTest Get-ItemProperty { $null }

        $bp = MinibenchTest\Get-SystemBootPerformance
        $bp.Verfuegbar | Should -BeFalse
        $bp.StatusText | Should -Be 'Nicht verfügbar (Diagnostics-Performance-Protokoll deaktiviert)'
    }
}

Describe 'Hersteller-Links für BIOS-Updates (Get-BiosVendorSupportUrl)' {
    BeforeAll {
        Import-MinibenchTestModule -Functions 'Get-BiosVendorSupportUrl'
    }

    It 'löst bekannte Hersteller auf direkte Supportseiten auf' {
        MinibenchTest\Get-BiosVendorSupportUrl 'ASUSTeK COMPUTER INC.' | Should -Be 'https://www.asus.com/support/'
        MinibenchTest\Get-BiosVendorSupportUrl 'Gigabyte Technology Co., Ltd.' | Should -Be 'https://www.gigabyte.com/Support'
        MinibenchTest\Get-BiosVendorSupportUrl 'Micro-Star International Co., Ltd.' | Should -Be 'https://de.msi.com/support'
        MinibenchTest\Get-BiosVendorSupportUrl 'ASRock' | Should -Be 'https://www.asrock.com/support/'
        MinibenchTest\Get-BiosVendorSupportUrl 'Dell Inc.' | Should -Be 'https://www.dell.com/support/home/'
        MinibenchTest\Get-BiosVendorSupportUrl 'HP' | Should -Be 'https://support.hp.com/'
        MinibenchTest\Get-BiosVendorSupportUrl 'Lenovo' | Should -Be 'https://pcsupport.lenovo.com/'
    }

    It 'erzeugt Suchlink für unbekannte Hersteller' {
        $url = MinibenchTest\Get-BiosVendorSupportUrl 'Supermicro'
        $url | Should -Match '^https://www\.google\.com/search\?q=Supermicro'
    }
}

Describe 'XMP/EXPO-Erkennung (Test-RamProfile)' {
    BeforeAll {
        Import-MinibenchTestModule -Functions 'Test-RamProfile', 'Get-RamRatedSpeed', 'Add-Finding', 'Send-GuiEvent', 'Add-Line' `
            -Setup '$script:Findings = New-Object System.Collections.Generic.List[object]; $script:FindKeys = $null; $script:RamProfileActive = $false; $script:Report = New-Object System.Text.StringBuilder'
    }

    It 'warnt bei inaktivem Profil anhand von Teilenummer' {
        Set-ModuleVar 'Findings' (New-Object System.Collections.Generic.List[object])
        $mods = @(
            [pscustomobject]@{ PartNumber = 'F4-3200C16-8GVKB'; ConfiguredClockSpeed = 2133; Speed = 2133 },
            [pscustomobject]@{ PartNumber = 'F4-3200C16-8GVKB'; ConfiguredClockSpeed = 2133; Speed = 2133 }
        )
        MinibenchTest\Test-RamProfile $mods 'DDR4'
        $f = @(Get-ModuleVar 'Findings' | Where-Object { $_.Bereich -eq 'RAM' })
        $f.Count | Should -Be 1
        $f[0].Stufe | Should -Be 'WARNUNG'
        $f[0].Befund | Should -Match 'XMP/EXPO/DOCP inaktiv'
    }

    It 'erkennt aktives Profil, wenn Takt dem Nenntakt entspricht' {
        Set-ModuleVar 'Findings' (New-Object System.Collections.Generic.List[object])
        $mods = @(
            [pscustomobject]@{ PartNumber = 'F4-3200C16-8GVKB'; ConfiguredClockSpeed = 3200; Speed = 3200 }
        )
        MinibenchTest\Test-RamProfile $mods 'DDR4'
        $f = @(Get-ModuleVar 'Findings' | Where-Object { $_.Bereich -eq 'RAM' })
        $f.Count | Should -Be 0
        (Get-ModuleVar 'RamProfileActive') | Should -BeTrue
    }

    It 'warnt auch bei inaktivem Profil über Speed-Eigenschaft ohne Teilenummer' {
        Set-ModuleVar 'Findings' (New-Object System.Collections.Generic.List[object])
        $mods = @(
            [pscustomobject]@{ PartNumber = 'OEM-GENERIC'; ConfiguredClockSpeed = 2400; Speed = 3200 }
        )
        MinibenchTest\Test-RamProfile $mods 'DDR4'
        $f = @(Get-ModuleVar 'Findings' | Where-Object { $_.Bereich -eq 'RAM' })
        $f.Count | Should -Be 1
        $f[0].Stufe | Should -Be 'WARNUNG'
        $f[0].Befund | Should -Match 'XMP/EXPO/DOCP inaktiv'
    }
}

Describe 'Bildschirm- und Grafikanschluss-Diagnose (Get-DisplayDiagnostics)' {
    BeforeAll {
        Import-MinibenchTestModule -Functions 'Get-DisplayDiagnostics' `
            -Setup '$script:IsLaptop = $false'
    }

    It 'liefert strukturierte Diagnoseergebnisse' {
        $res = MinibenchTest\Get-DisplayDiagnostics
        $res.PSObject.Properties['WrongPortDetected'] | Should -Not -BeNullOrEmpty
        $res.PSObject.Properties['HzBremseDetected'] | Should -Not -BeNullOrEmpty
    }
}

Describe 'LAN-Verhandlungsrate' {
    It 'warnt bei Gigabit-Adapter, der auf 100 Mbit/s synchronisiert' {
        $netAdapters = @(
            [pscustomobject]@{
                Name                 = 'Ethernet'
                InterfaceDescription = 'Intel(R) Ethernet Connection I219-V'
                Status               = 'Up'
                LinkSpeed            = '100 Mbps'
                DuplexMode           = 'Full'
                FullDuplex           = $true
            }
        )
        $findings = New-Object System.Collections.Generic.List[object]
        foreach ($na in $netAdapters) {
            if ($na.Status -ne 'Up') { continue }
            $desc = [string]$na.InterfaceDescription
            if ($desc -match 'Wireless|Wi-Fi|Bluetooth|Virtual|TAP|Hyper-V|VPN|Loopback|Tailscale|ZeroTier') { continue }
            $isGbeCapable = ($desc -match 'Gigabit|GbE|2\.5G|2500|5G|10G|I211|I219|I225|I226|RTL8111|RTL8125|Killer E')
            $is100M = ($na.LinkSpeed -match '100 M(bps|bit/s)?$')
            $isHalf = ($na.DuplexMode -eq 'Half' -or ($null -ne $na.FullDuplex -and -not $na.FullDuplex))
            if ($isGbeCapable -and ($is100M -or $isHalf)) {
                $findings.Add([pscustomobject]@{ Stufe = 'WARNUNG'; Bereich = 'Netzwerk'; Befund = 'LAN-Verhandlungsrate gebremst' })
            }
        }
        $findings.Count | Should -Be 1
        $findings[0].Stufe | Should -Be 'WARNUNG'
    }
}
