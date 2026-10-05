# Version 2.8: Modul Optimierung (Windows Optimisation Pack nativ), Sensor-Ersatzwerte ohne LibreHardwareMonitor,
# Beschriftungen der Kurven ohne Überschneidung, Berichtskorrekturen aus dem Praxistest vom 03.10.2026.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $global:V28Src = $global:MinibenchSrcRoot
    $global:V28Gui = [IO.File]::ReadAllText((Join-Path $global:V28Src 'Oberflaeche/DiagGui.cs'))
    $global:V28Kat = [IO.File]::ReadAllText((Join-Path $global:V28Src 'Module/Optimierung/Katalog.psd1'))
    function Import-Opt {
        Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Aenderungen.ps1', 'Kern\Modulvertrag.ps1', 'Module\Optimierung\Funktionen.ps1' `
            -Functions 'Get-SafeName', 'Invoke-External', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent'
        Mock -ModuleName MinibenchTest Write-Host { }
    }
    function New-OptRun {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-ModuleVar 'DataDir' $dir
        Set-ModuleVar 'ChangeLog' $null
        Set-ModuleVar 'DeviceIdentity' ([pscustomobject]@{ Id = 'G-bbbbbbbbbbbbbbbbbbbb'; Guete = 'hoch'; Quellen = @() })
        MinibenchTest\Start-ChangeLog
    }
    $global:V28Env = [pscustomobject]@{ Build = 26200; Win11 = $true; Desktop = $true; Nvidia = $false; Terminal = $false; Domain = $false; Neustart = $false; Grafik = @()
        User = [pscustomobject]@{ Sid = 'S-1-5-21-1-2-3-1001'; Name = 'PC\anna'; Profil = 'C:\Users\anna'; Eigen = $true; Quelle = 'test' } }
}

Describe 'Katalog der Optimierung' {
    BeforeAll { Import-Opt }
    It 'ist eingeschränkte Sprache (nur Daten, keine Befehle)' {
        $sb = [scriptblock]::Create($global:V28Kat)
        { $sb.CheckRestrictedLanguage([string[]]@(), [string[]]@('true', 'false', 'null'), $false) } | Should -Not -Throw
    }
    It 'hat eindeutige Ids, bekannte Kategorien, Stufen, Vorlagen und Bedingungen' {
        $e = @(MinibenchTest\Get-OptEntries)
        $e.Count | Should -BeGreaterThan 150
        # Katalogeinträge sind Hashtables: Group-Object und Where-Object mit Eigenschaftsnamen finden deren Schlüssel unter
        # Windows PowerShell 5.1 nicht (alle Einträge landeten in einer Gruppe), daher überall Skriptblöcke
        $ids = @($e | ForEach-Object { [string]$_.Id })
        @($ids | Where-Object { -not $_ }).Count | Should -Be 0
        @($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
        $kats = @(MinibenchTest\Get-OptCategories | ForEach-Object { $_.Key })
        foreach ($x in $e) {
            $kats | Should -Contain $x.Kat -Because $x.Id
            (@('Aendern', 'Eingriff') -contains $x.Risiko) | Should -BeTrue -Because $x.Id
            [string]$x.Vorlagen | Should -Match '^M?S?E?$' -Because $x.Id
            (@('', 'Win10', 'Win11', 'Desktop', 'Nvidia', 'Terminal') -contains [string]$x.Bedingung) | Should -BeTrue -Because $x.Id
            (@('nie', 'moeglich', 'immer') -contains [string]$x.Neustart) | Should -BeTrue -Because $x.Id
            $x.Titel | Should -Not -BeNullOrEmpty
            $x.Text | Should -Not -BeNullOrEmpty
            $x.Quelle | Should -Not -BeNullOrEmpty
            @($x.Aktionen).Count | Should -BeGreaterThan 0 -Because $x.Id
        }
        foreach ($k in $kats) { @($e | Where-Object { $_.Kat -eq $k }).Count | Should -BeGreaterThan 0 -Because $k }
    }
    It 'Vorlagen bauen aufeinander auf (Minimal in Standard in Erweitert)' {
        $m = @(MinibenchTest\Get-OptPreset 'M'); $s = @(MinibenchTest\Get-OptPreset 'S'); $x = @(MinibenchTest\Get-OptPreset 'E')
        $m.Count | Should -BeGreaterThan 0
        @($m | Where-Object { $s -notcontains $_ }).Count | Should -Be 0
        @($s | Where-Object { $x -notcontains $_ }).Count | Should -Be 0
        # DDU und das Löschen der Wiederherstellungspunkte nur von Hand
        $x | Should -Not -Contain 'Ddu'
        $x | Should -Not -Contain 'Wiederherstellungspunkte'
    }
    It 'Stufe Ändern nur mit Aktionen, die sich einzeln zurücknehmen lassen' {
        $undo = 'Defender', 'DnsOverHttps', 'Energieplan', 'Indizierung', 'Laufwerksname', 'NetzwerkEnergie', 'Ruhezustand', 'Speicherreserve', 'Wartungsaufgaben'
        # Zählung schützt vor einer leeren Schleife (Filter, der unter PS 5.1 nichts findet)
        @(MinibenchTest\Get-OptEntries | Where-Object { $_.Risiko -eq 'Aendern' }).Count | Should -BeGreaterThan 100
        foreach ($x in @(MinibenchTest\Get-OptEntries | Where-Object { $_.Risiko -eq 'Aendern' })) {
            foreach ($a in @($x.Aktionen)) {
                (@('Reg', 'RegKey', 'Dienst', 'Aufgabe', 'Feature', 'Sonder') -contains $a.Art) | Should -BeTrue -Because $x.Id
                if ($a.Art -eq 'Sonder') { ($undo -contains $a.Name) | Should -BeTrue -Because $x.Id }
            }
        }
        foreach ($x in @(MinibenchTest\Get-OptEntries | Where-Object { @($_.Aktionen | Where-Object { $_.Art -in 'App', 'Capability' }).Count })) { $x.Risiko | Should -Be 'Eingriff' -Because $x.Id }
    }
    It 'Registry-Aktionen sind vollständig' {
        @(MinibenchTest\Get-OptEntries | ForEach-Object { $_.Aktionen } | Where-Object { $_.Art -eq 'Reg' }).Count | Should -BeGreaterThan 100
        foreach ($x in @(MinibenchTest\Get-OptEntries)) {
            foreach ($a in @($x.Aktionen | Where-Object { $_.Art -eq 'Reg' })) {
                $a.Pfad | Should -Match '^(HKLM:|HKCU:|Registry::HKEY_USERS)\\' -Because $x.Id
                $a.Name | Should -Not -BeNullOrEmpty -Because $x.Id
                (@('DWord', 'QWord', 'String', 'ExpandString', 'Binary', 'MultiString') -contains $a.Typ) | Should -BeTrue -Because ('{0} {1}' -f $x.Id, $a.Name)
            }
        }
    }
    It 'jeder Eintrag gehört zu einem Schritt des Modulvertrags' {
        Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Modulvertrag.ps1', 'Module\Optimierung\Funktionen.ps1' -Functions 'Get-OptStepKey'
        $c = MinibenchTest\Get-ModuleContract 'Optimierung'
        $keys = @($c.Schritte | ForEach-Object { $_.Key })
        foreach ($x in @(MinibenchTest\Get-OptEntries)) { $keys | Should -Contain (MinibenchTest\Get-OptStepKey $x) -Because $x.Id }
        Import-Opt
    }
    It 'Zeilen für die Oberfläche haben feste Spaltenzahl und keine Zeilenumbrüche' {
        $l = @(MinibenchTest\Get-OptGuiLines)
        @($l | Where-Object { $_ -like 'K|*' }).Count | Should -Be @(MinibenchTest\Get-OptCategories).Count
        foreach ($z in @($l | Where-Object { $_ -like 'E|*' })) {
            @($z -split '\|').Count | Should -Be 11 -Because $z.Substring(0, 30)
            $z | Should -Not -Match '[\r\n]'
        }
    }
    It 'Auswahl meldet Unbekanntes und hält die Katalogreihenfolge' {
        $r = MinibenchTest\Resolve-OptSelection 'Feedback; WerbeId,gibtsnicht'
        $r.Unbekannt | Should -Be @('gibtsnicht')
        $all = @(MinibenchTest\Get-OptEntries | ForEach-Object { $_.Id })
        $all.IndexOf($r.Ids[0]) | Should -BeLessThan $all.IndexOf($r.Ids[1])
    }
}

Describe 'Benutzer und Pfade der Optimierung' {
    BeforeAll { Import-Opt }
    It 'lenkt HKCU auf den angemeldeten Benutzer, wenn Leos Minibench unter einem anderen Konto läuft' {
        $u = [pscustomobject]@{ Sid = 'S-1-5-21-9'; Eigen = $false }
        MinibenchTest\Resolve-OptRegPath 'HKCU:\Software\Test' $u | Should -Be 'Registry::HKEY_USERS\S-1-5-21-9\Software\Test'
        MinibenchTest\Resolve-OptRegPath 'HKCU:\Software\Test' ([pscustomobject]@{ Sid = 'S-1-5-21-9'; Eigen = $true }) | Should -Be 'HKCU:\Software\Test'
        MinibenchTest\Resolve-OptRegPath 'HKLM:\SOFTWARE\X\{SID}' $u | Should -Be 'HKLM:\SOFTWARE\X\S-1-5-21-9'
    }
    It 'setzt Profilpfade des angemeldeten Benutzers ein' {
        $p = MinibenchTest\Expand-OptPath '%TEMP%\x' ([pscustomobject]@{ Profil = (Join-Path $TestDrive 'anna') })
        $p | Should -Match 'anna'
        $p | Should -Match 'Temp'
        MinibenchTest\Expand-OptPath '%localappdata%' ([pscustomobject]@{ Profil = (Join-Path $TestDrive 'a$b') }) | Should -Match ([regex]::Escape('a$b'))
    }
    It 'prüft Bedingungen' {
        $e10 = [pscustomobject]@{ Win11 = $false; Desktop = $false; Nvidia = $false; Terminal = $false }
        MinibenchTest\Test-OptCondition ([pscustomobject]@{ Bedingung = 'Win11' }) $e10 | Should -Match 'Windows 11'
        MinibenchTest\Test-OptCondition ([pscustomobject]@{ Bedingung = 'Desktop' }) $e10 | Should -Match 'Desktop'
        MinibenchTest\Test-OptCondition ([pscustomobject]@{ Bedingung = '' }) $e10 | Should -BeNullOrEmpty
    }
}

Describe 'Einträge ausführen und zurücknehmen' {
    BeforeAll { Import-Opt }
    BeforeEach {
        New-OptRun
        $script:reg = @{}
        Mock -ModuleName MinibenchTest Get-RegValueState { $k = $Path + '|' + $Name; if ($script:reg.ContainsKey($k)) { [pscustomobject]$script:reg[$k] } else { [pscustomobject]@{ Vorhanden = $false; Wert = $null; Typ = '' } } }
        Mock -ModuleName MinibenchTest Set-RegValueState { $script:reg[$Path + '|' + $Name] = @{ Vorhanden = $true; Wert = $Value; Typ = $Type } }
        Mock -ModuleName MinibenchTest Remove-RegValue { $script:reg.Remove($Path + '|' + $Name) }
        Set-ModuleVar 'OptRestart' ([System.Collections.Generic.List[string]]::new())
    }
    It 'Registry: angewendet, beim zweiten Mal bereits so, im Protokoll mit Vorher-Wert' {
        $e = [pscustomobject]@{ Id = 'T1'; Titel = 'Test'; Kat = 'Datenschutz'; Risiko = 'Aendern'; Neustart = 'nie'; Bedingung = ''
            Aktionen = @(@{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Test'; Name = 'A'; Wert = 0; Typ = 'DWord' }, @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Test'; Name = 'B'; Wert = 1; Typ = 'DWord' }) }
        (MinibenchTest\Get-OptEntryState $e $global:V28Env).Zustand | Should -Be 'offen'
        $r = MinibenchTest\Invoke-OptEntry $e $global:V28Env
        $r.Ergebnis | Should -Be 'angewendet'
        $r.Aenderungen | Should -Be 2
        (MinibenchTest\Invoke-OptEntry $e $global:V28Env).Ergebnis | Should -Be 'bereits so'
        (MinibenchTest\Get-OptEntryState $e $global:V28Env).Zustand | Should -Be 'aktiv'
        $j = Get-Content -LiteralPath (Get-ModuleVar 'ChangeFile') -Raw -Encoding UTF8 | ConvertFrom-Json
        @($j.Eintraege).Count | Should -Be 2
        $j.Eintraege[0].Modul | Should -Be 'Optimierung'
        $j.Eintraege[0].Schritt | Should -Be 'T1'
        $f = Get-ModuleVar 'ChangeFile'
        $u = MinibenchTest\Invoke-ChangeUndo ('{0}*1;{0}*2' -f $f)
        $u.Rueckgaengig | Should -Be 2
        $script:reg.Count | Should -Be 0
    }
    It 'Bedingung nicht erfüllt: übersprungen, nichts geschrieben' {
        $e = [pscustomobject]@{ Id = 'T2'; Titel = 'Nur Win10'; Kat = 'Bedienung'; Risiko = 'Aendern'; Neustart = 'nie'; Bedingung = 'Win10'; Aktionen = @(@{ Art = 'Reg'; Pfad = 'HKLM:\X'; Name = 'A'; Wert = 1; Typ = 'DWord' }) }
        (MinibenchTest\Invoke-OptEntry $e $global:V28Env).Ergebnis | Should -Be 'übersprungen'
        Should -Invoke -ModuleName MinibenchTest Set-RegValueState -Times 0
    }
    It 'Dienst, den es nicht gibt: nicht vorhanden statt Fehler' {
        Mock -ModuleName MinibenchTest Get-ServiceStartType { throw 'nicht vorhanden' }
        $e = [pscustomobject]@{ Id = 'T3'; Titel = 'Dienst'; Kat = 'Hintergrund'; Risiko = 'Aendern'; Neustart = 'nie'; Bedingung = ''; Aktionen = @(@{ Art = 'Dienst'; Name = 'GibtsNicht'; Start = 'Disabled' }) }
        (MinibenchTest\Invoke-OptEntry $e $global:V28Env).Ergebnis | Should -Be 'nicht vorhanden'
    }
    It 'Dienst: Starttyp mit Vorher-Wert, Dienst wird beendet' {
        $script:svc = 'Automatic'
        Mock -ModuleName MinibenchTest Get-ServiceStartType { $script:svc }
        Mock -ModuleName MinibenchTest Set-ServiceStartType { $script:svc = $StartType }
        Mock -ModuleName MinibenchTest Stop-OptService { $true }
        $e = [pscustomobject]@{ Id = 'T4'; Titel = 'Dienst'; Kat = 'Hintergrund'; Risiko = 'Aendern'; Neustart = 'nie'; Bedingung = ''; Aktionen = @(@{ Art = 'Dienst'; Name = 'DiagTrack'; Start = 'Disabled' }) }
        (MinibenchTest\Invoke-OptEntry $e $global:V28Env).Ergebnis | Should -Be 'angewendet'
        $script:svc | Should -Be 'Disabled'
        Should -Invoke -ModuleName MinibenchTest Stop-OptService -Times 1
    }
    It 'Aufgabe: deaktiviert und über das Protokoll wieder aktiv' {
        $script:task = 'Ready'
        Mock -ModuleName MinibenchTest Get-OptTasks { @([pscustomobject]@{ Pfad = '\Microsoft\Windows\Test\'; Name = 'Sammler'; Zustand = $script:task }) }
        Mock -ModuleName MinibenchTest Disable-OptTask { $script:task = 'Disabled' }
        Mock -ModuleName MinibenchTest Enable-OptTask { $script:task = 'Ready' }
        $e = [pscustomobject]@{ Id = 'T5'; Titel = 'Aufgabe'; Kat = 'Datenschutz'; Risiko = 'Aendern'; Neustart = 'nie'; Bedingung = ''; Aktionen = @(@{ Art = 'Aufgabe'; Pfad = '\Microsoft\Windows\Test\'; Name = 'Sammler' }) }
        (MinibenchTest\Invoke-OptEntry $e $global:V28Env).Ergebnis | Should -Be 'angewendet'
        $script:task | Should -Be 'Disabled'
        $u = MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-ModuleVar 'ChangeFile'))
        $u.Rueckgaengig | Should -Be 1
        $script:task | Should -Be 'Ready'
    }
    It 'App: Eingriff, Fehler beim Entfernen landet im Ergebnis' {
        Mock -ModuleName MinibenchTest Get-OptApps { @([pscustomobject]@{ Name = 'Microsoft.BingNews'; Paket = 'Microsoft.BingNews_1.0_x64'; Version = '1.0' }) }
        Mock -ModuleName MinibenchTest Remove-OptApp { throw 'Zugriff verweigert' }
        $e = [pscustomobject]@{ Id = 'T6'; Titel = 'News'; Kat = 'Apps'; Risiko = 'Eingriff'; Neustart = 'nie'; Bedingung = ''; Aktionen = @(@{ Art = 'App'; Muster = 'Microsoft.BingNews' }) }
        $r = MinibenchTest\Invoke-OptEntry $e $global:V28Env
        $r.Ergebnis | Should -Be 'Fehler'
        $r.Details | Should -Match 'Zugriff verweigert'
    }
    It 'Windows-Funktion: Neustart wird vermerkt' {
        Mock -ModuleName MinibenchTest Get-OptFeatureState { 'Enabled' }
        Mock -ModuleName MinibenchTest Set-OptFeature { $true }
        $e = [pscustomobject]@{ Id = 'T7'; Titel = 'Funktion'; Kat = 'Funktionen'; Risiko = 'Aendern'; Neustart = 'moeglich'; Bedingung = ''; Aktionen = @(@{ Art = 'Feature'; Name = 'WorkFolders-Client' }) }
        $r = MinibenchTest\Invoke-OptEntry $e $global:V28Env
        $r.Neustart | Should -BeTrue
        @(Get-ModuleVar 'OptRestart') | Should -Contain 'Funktion'
    }
    It 'Rückgängig kennt neue Arten und lässt fremde unberührt' {
        MinibenchTest\Undo-OptChange ([pscustomobject]@{ Art = 'Unbekannt'; Daten = @{} }) | Should -BeNullOrEmpty
        Mock -ModuleName MinibenchTest Test-OptRegKey { $false }
        (MinibenchTest\Undo-OptChange ([pscustomobject]@{ Art = 'RegSchluessel'; Daten = [pscustomobject]@{ Pfad = 'HKCU:\X' } })).Status | Should -Be 'übersprungen'
    }
}

Describe 'Optimierung im Ablauf, Bericht und in der Oberfläche' {
    It 'Bauplan, Vertrag, Kopf und Bericht kennen das Modul' {
        $b = (Get-MinibenchBuild).Text
        $b | Should -Match 'function Invoke-OptEntry'
        $b | Should -Match 'Invoke-Section .Optimierung: Ergebnis'
        $b | Should -Match 'New-OptHtml'
        $b | Should -Match 'OPTIMIERUNG \(Windows Optimisation Pack, nativ\)'
        Get-ScriptParameters | Should -Contain 'Optimierungen'
        Get-ScriptParameters | Should -Contain 'OptimierungZustand'
    }
    It 'die Oberfläche hat die Seite, Vorlagen und verarbeitet @@OPTE und @@OPTZ' {
        $global:V28Gui | Should -Match 'BuildOptPage'
        $global:V28Gui | Should -Match 'case "OPTE": UpdateOptResult\(p\)'
        $global:V28Gui | Should -Match '@@OPTZ\|'
        $global:V28Gui | Should -Match 'Opt\.Auswahl'
    }
    It 'Sophia Script und O&O ShutUp10++ werden nicht mehr gestartet' {
        $b = (Get-MinibenchBuild).Text
        $b | Should -Not -Match 'Sophia\.ps1'
        $b | Should -Not -Match 'OOSU10\.exe'
    }
}

Describe 'Sensoren ohne LibreHardwareMonitor' {
    BeforeAll { Import-MinibenchTestModule -Parts 'Kern\Werkzeuge.ps1', 'Kern\Sensoren.ps1' -Functions 'Get-SafeName' }
    It 'Windows-Grafiktreiber liefert Temperatur, Takt, Lüfter und Auslastung je Karte' {
        $a = @([pscustomobject]@{ Name = 'AMD Radeon RX 6800'; TempC = 55.5; CoreMhz = 2105; MemMhz = 1000; FanRpm = [double]::NaN; Load = 97.3 })
        $r = @(MinibenchTest\ConvertFrom-KmtAdapters $a @())
        @($r | Where-Object { $_.Art -eq 'Temperatur' }).Wert | Should -Be 55.5
        @($r | Where-Object { $_.Name -eq 'GPU Core' -and $_.Art -eq 'Takt' }).Wert | Should -Be 2105
        @($r | Where-Object { $_.Name -eq 'GPU Memory' }).Wert | Should -Be 1000
        @($r | Where-Object { $_.Art -eq 'Lüfter' }).Count | Should -Be 0
        @($r | ForEach-Object { $_.Quelle } | Select-Object -Unique) | Should -Be @('Windows')
        $lead = MinibenchTest\Get-SensorLead $r
        $lead.GpuTemp | Should -Be 55.5
        $lead.GpuLoad | Should -Be 97
    }
    It 'überschreibt keine Werte anderer Quellen, verwirft unplausible und virtuelle Adapter' {
        $ex = @(MinibenchTest\New-SensorReading 'nvsmi/0/temp' 'nvidia-smi' 'GPU' 'NVIDIA GeForce RTX 3060' 'Temperatur' 'GPU Core' '°C' 61 'GpuNvidia')
        $a = @([pscustomobject]@{ Name = 'NVIDIA GeForce RTX 3060'; TempC = 60; CoreMhz = 99999; MemMhz = [double]::NaN; FanRpm = 1500; Load = 40 },
               [pscustomobject]@{ Name = 'Microsoft Remote Display Adapter'; TempC = 40; CoreMhz = 1000; MemMhz = 1000; FanRpm = 1000; Load = 1 })
        $r = @(MinibenchTest\ConvertFrom-KmtAdapters $a $ex)
        @($r | Where-Object { $_.Art -eq 'Temperatur' }).Count | Should -Be 0
        @($r | Where-Object { $_.Art -eq 'Takt' }).Count | Should -Be 0
        @($r | Where-Object { $_.Geraet -match 'Remote' }).Count | Should -Be 0
        @($r | Where-Object { $_.Art -eq 'Lüfter' }).Wert | Should -Be 1500
    }
    It 'nennt den Grund, warum Werte fehlen, statt PawnIO zu vermuten' {
        Set-ModuleVar 'Sens' ([pscustomobject]@{ Lhm = $false; LhmLief = $false; LhmGrund = 'fehlt'; LhmFehler = ''; TreiberOk = $false; Treiber = 'nicht verwendet' })
        MinibenchTest\Get-SensorGapText | Should -Match 'LibreHardwareMonitor fehlt im Tools-Ordner'
        MinibenchTest\Get-SensorGapText | Should -Not -Match 'PawnIO'
        Set-ModuleVar 'Sens' ([pscustomobject]@{ Lhm = $true; LhmLief = $true; LhmGrund = ''; LhmFehler = ''; TreiberOk = $false; Treiber = 'ohne PawnIO' })
        MinibenchTest\Get-SensorGapText | Should -Match 'ohne PawnIO-Treiber'
    }
    It 'Ersatzquellen werden nur ohne LibreHardwareMonitor abgefragt' {
        $f = (Get-TopFunctions)['Get-SensorReadings']
        $f | Should -Match "if \(-not \(\`$s -and \`$s\.Lhm\)\) \{"
        $f | Should -Match 'ConvertFrom-KmtAdapters \(Get-WindowsGpuAdapters\)'
        $f | Should -Match 'Get-WindowsCpuPowerReading'
    }
    It 'C#-Teil mit DiagGpuKmt lässt sich mit C# 5 übersetzen' {
        $cs = Join-Path $global:V28Src 'Kern/Sensoren.cs'
        [IO.File]::ReadAllText($cs) | Should -Match 'public static class DiagGpuKmt'
        if ($env:OS -ne 'Windows_NT' -and (Get-Command mcs -ErrorAction SilentlyContinue)) {
            $out = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchSens_' + [guid]::NewGuid().ToString('N') + '.dll')
            try { $msg = & mcs -langversion:5 -target:library ('-out:' + $out) $cs 2>&1; $LASTEXITCODE | Should -Be 0 -Because ($msg -join ' ') }
            finally { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Kurven ohne Überschneidung' {
    BeforeAll {
        Import-MinibenchTestModule -Functions 'Get-ChartScale', 'Get-ChartMarkLayout', 'New-MultiLineSvg', 'ConvertTo-HtmlText'
    }
    It 'beschriftet halbe Schritte mit Nachkommastelle, keine doppelten Werte' {
        $s = MinibenchTest\Get-ChartScale 60 61.8
        $s.Step | Should -Be 0.5
        $lab = @($s.Ticks | ForEach-Object { $_.ToString($s.Format, [Globalization.CultureInfo]::InvariantCulture) })
        @($lab | Select-Object -Unique).Count | Should -Be $lab.Count
        $lab[0] | Should -Be '60.0'
    }
    It 'ganzzahlige Messreihen bekommen mindestens Schritt 1' {
        $s = MinibenchTest\Get-ChartScale 60 62 -Integer
        $s.Step | Should -Be 1
        $s.Format | Should -Be 'N0'
    }
    It 'nahe Marken landen in getrennten Zeilen, am rechten Rand links der Linie' {
        $fx = { param($t) 70 + $t / 300 * 870 }
        $m = @(MinibenchTest\Get-ChartMarkLayout @(@{ T = 100; Label = 'Arbeitsspeicher' }, @{ T = 110; Label = 'Grafik' }, @{ T = 299; Label = 'Ende' }) 70 940 14 $fx 300)
        $m[0].Y | Should -Not -Be $m[1].Y
        $m[2].Anchor | Should -Be 'end'
        $svg = MinibenchTest\New-MultiLineSvg @(@{ Name = 'CPU'; Cls = 's1'; Points = @([pscustomobject]@{ T = 0; V = 60.5 }, [pscustomobject]@{ T = 300; V = 61.5 }) }) '°C' @() @(@{ T = 100; Label = 'Arbeitsspeicher' }, @{ T = 110; Label = 'Grafik' })
        ([regex]::Matches($svg, '<text class="mk"[^>]*y="(\d+)"')).Count | Should -Be 2
        @([regex]::Matches($svg, '<text class="mk"[^>]*y="(\d+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique).Count | Should -Be 2
    }
}

Describe 'Berichtskorrekturen aus dem Praxistest 03.10.2026' {
    BeforeAll { Import-MinibenchTestModule -Functions 'Format-Uptime', 'Repair-Utf8AsOem', 'Get-NvmeGenFromSpeed', 'Get-BenchPauseMeasured', 'Get-PauseAssessment' }
    It 'Laufzeit ohne "0 Tage" und mit Minuten' {
        MinibenchTest\Format-Uptime ([TimeSpan]::new(0, 5, 21, 0)) | Should -Be '5 Std 21 Min'
        MinibenchTest\Format-Uptime ([TimeSpan]::new(1, 2, 3, 0)) | Should -Be '1 Tag 2 Std 3 Min'
        MinibenchTest\Format-Uptime ([TimeSpan]::new(12, 2, 3, 0)) | Should -Be '12 Tage 2 Std'
    }
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
    It 'Referenz, TPM, Zuverlässigkeit, Benchmark-Abschnitte und winget im Skript' {
        $b = (Get-MinibenchBuild).Text
        $b | Should -Match 'Dieser Lauf wird als Referenz gespeichert'
        $b | Should -Match '\$script:RefSavedNow = \$true'
        $b | Should -Match "TPM Hersteller'\]\s+= \(\(\('\{0\} \{1\}' -f .+-replace '\[\\x00-\\x1F\]'"
        $b | Should -Not -Match "Add-Finding INFO 'Stabilität' \('Zuverlässigkeit \{0:N1\} von 10\. \{1\}' -f \`$rsm\.SystemStabilityIndex, \`$script:Stability\.Erklaerung\)"
        $b | Should -Match "Add-BenchHeadLine 'RAM'"
        $b | Should -Match "Add-BenchHeadLine 'Laufwerke'"
        $b | Should -Match 'winget source reset --force'
        $b | Should -Match 'WLAN-Details \(SSID, Signal, Funkstandard\) gesperrt'
    }
}

Describe 'Befunde aus dem Code-Review v2.8' {
    It 'Absturz in einer Kategorie der Optimierung schaltet beim nächsten Lauf genau diese Kategorie ab' {
        Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Modulvertrag.ps1', 'Module\Optimierung\Funktionen.ps1' -Functions 'Get-SkipSwitch'
        $k = @(MinibenchTest\Get-OptCategories) | Where-Object { $_.Key -eq 'Sicherheit' }
        MinibenchTest\Get-SkipSwitch ('Optimierung: ' + $k.Titel) | Should -Be 'Opt8:Sicherheit'
        MinibenchTest\Get-SkipSwitch 'Optimierung: Ergebnis' | Should -BeNullOrEmpty
        MinibenchTest\Get-SkipSwitch 'Defender' | Should -Be 'Opt:Defender'
    }
    It 'Befehle der Wartungsaufgaben sind gültiges PowerShell' {
        Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Modulvertrag.ps1', 'Module\Optimierung\Funktionen.ps1'
        foreach ($t in @(MinibenchTest\Get-OptMaintenanceTasks)) {
            $errs = $null; $tok = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($t.Befehl, [ref]$tok, [ref]$errs)
            @($errs).Count | Should -Be 0 -Because $t.Name
        }
    }
    It 'Achsenschritt 2,5 wird mit Nachkommastelle beschriftet, ganzzahlige Reihen meiden 2,5' {
        Import-MinibenchTestModule -Functions 'Get-ChartScale'
        $s = MinibenchTest\Get-ChartScale -5 5
        $s.Step | Should -Be 2.5
        $s.Format | Should -Be 'N1'
        (MinibenchTest\Get-ChartScale 40 50 -Integer).Step | Should -Not -Be 2.5
    }
    It 'Wiederherstellungspunkt: nach dem Löschen alter Punkte wird ein neuer angelegt' {
        $b = (Get-MinibenchBuild).Text
        $b | Should -Match 'wurde mit gelöscht, es wird ein neuer angelegt.+\$script:RestorePointNo = \$null'
    }
    It 'Energiezähler meldet Milliwatt' {
        [IO.File]::ReadAllText((Join-Path $global:V28Src 'Kern/Sensoren.cs')) | Should -Match 'double w = kv\.Value / 1000\.0;'
    }
}
