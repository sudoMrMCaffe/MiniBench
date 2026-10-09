# Modul Optimierung (Windows Optimisation Pack nativ): Katalog, Vorlagen (Minimal, Leos Empfehlung, Erweitert),
# angemeldeter Benutzer und Pfade, Einträge ausführen und über das Änderungsprotokoll zurücknehmen, Bericht.
# Dazu das Modul Wartung (Modulvertrag und Ablauf).
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Aenderungen.ps1', 'Kern\Modulvertrag.ps1', 'Module\Optimierung\Funktionen.ps1' `
        -Functions 'Get-SafeName', 'Invoke-External', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent', 'Get-OptStepKey', 'Get-SkipSwitch', 'ConvertTo-HtmlText'
    Mock -ModuleName MinibenchTest Write-Host { }
    $katalogText = Get-SrcText 'Module/Optimierung/Katalog.psd1'
    function New-OptRun {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-ModuleVar 'DataDir' $dir
        Set-ModuleVar 'ChangeLog' $null
        Set-ModuleVar 'DeviceIdentity' ([pscustomobject]@{ Id = 'G-bbbbbbbbbbbbbbbbbbbb'; Guete = 'hoch'; Quellen = @() })
        MinibenchTest\Start-ChangeLog
    }
    $optEnv = [pscustomobject]@{ Build = 26200; Win11 = $true; Desktop = $true; Nvidia = $false; Terminal = $false; Domain = $false; Neustart = $false; Grafik = @()
        User = [pscustomobject]@{ Sid = 'S-1-5-21-1-2-3-1001'; Name = 'PC\anna'; Profil = 'C:\Users\anna'; Eigen = $true; Quelle = 'test' } }
}

Describe 'Katalog der Optimierung' {
    It 'ist eingeschränkte Sprache (nur Daten, keine Befehle)' {
        $sb = [scriptblock]::Create($katalogText)
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
    It 'enthält keine Kategorie Bereinigung mehr (Bereinigungen gehören zum Modul Wartung)' {
        @(MinibenchTest\Get-OptCategories | ForEach-Object { $_.Key }) | Should -Not -Contain 'Bereinigung'
        @(MinibenchTest\Get-OptEntries | ForEach-Object { $_.Kat }) | Should -Not -Contain 'Bereinigung'
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
        $keys = @((MinibenchTest\Get-ModuleContract 'Optimierung').Schritte | ForEach-Object { $_.Key })
        foreach ($x in @(MinibenchTest\Get-OptEntries)) { $keys | Should -Contain (MinibenchTest\Get-OptStepKey $x) -Because $x.Id }
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

Describe 'Vorlagen der Optimierung' {
    It 'bauen aufeinander auf (Minimal in Leos Empfehlung in Erweitert)' {
        $m = @(MinibenchTest\Get-OptPreset 'M'); $s = @(MinibenchTest\Get-OptPreset 'S'); $x = @(MinibenchTest\Get-OptPreset 'E')
        $m.Count | Should -BeGreaterThan 0
        $m.Count | Should -BeLessThan $s.Count
        @($m | Where-Object { $s -notcontains $_ }).Count | Should -Be 0
        @($s | Where-Object { $x -notcontains $_ }).Count | Should -Be 0
        # DDU und das Löschen der Wiederherstellungspunkte nur von Hand
        $x | Should -Not -Contain 'Ddu'
        $x | Should -Not -Contain 'Wiederherstellungspunkte'
    }
    It 'Minimal enthält genau die fünf Grundeinstellungen' {
        @(MinibenchTest\Get-OptPreset 'M' | Sort-Object) | Should -Be @('Fehlerberichte', 'Speicheroptimierung', 'TaskbarEndTask', 'TelemetrieMinimal', 'WerbeId')
    }
    It 'Leos Empfehlung enthält Task beenden per Rechtsklick und den UEFI-Neustart' {
        $s = @(MinibenchTest\Get-OptPreset 'S')
        $s | Should -Contain 'TaskbarEndTask'
        $s | Should -Contain 'UefiNeustart'
    }
    It 'auf Domänen-PCs bleiben Einträge, die Richtlinien berühren, außen vor' {
        $verwaltet = @(MinibenchTest\Get-OptEntries | Where-Object { $_.Verwaltet -and ([string]$_.Vorlagen).Contains('S') } | ForEach-Object { $_.Id })
        $verwaltet.Count | Should -BeGreaterThan 0
        $dom = @(MinibenchTest\Get-OptPreset 'S' $true)
        foreach ($id in $verwaltet) { $dom | Should -Not -Contain $id }
        @(MinibenchTest\Get-OptPreset 'S' $false) | Should -Contain $verwaltet[0]
    }
    It 'Task beenden per Rechtsklick ist ein eigener Eintrag für Windows 11 mit Gegenbefehl' {
        $e = MinibenchTest\Get-OptEntry 'TaskbarEndTask'
        $e | Should -Not -BeNullOrEmpty
        $e.Kat | Should -Be 'Bedienung'
        $e.Vorlagen | Should -Be 'MSE'
        $e.Bedingung | Should -Be 'Win11'
        @($e.Aktionen).Count | Should -Be 2
        @($e.Aktionen | Where-Object { $_.Art -eq 'Reg' -and $_.Name -eq 'TaskbarEndTask' -and $_.Wert -eq 1 }).Count | Should -Be 2
        @($e.Gegenbefehl | Where-Object { $_ -match 'TaskbarEndTask' }).Count | Should -BeGreaterThan 0
    }
    It 'Taskleiste gruppieren setzt nur TaskbarGlomLevel' {
        $e = MinibenchTest\Get-OptEntry 'TaskleisteGruppieren'
        $e | Should -Not -BeNullOrEmpty
        @($e.Aktionen | Where-Object { $_.Name -eq 'TaskbarGlomLevel' }).Count | Should -Be 1
        @($e.Aktionen | Where-Object { $_.Name -eq 'TaskbarEndTask' }).Count | Should -Be 0
    }
    It 'UEFI-Neustart legt einen eigenen Kontextmenü-Schlüssel an (rücknehmbar)' {
        $e = MinibenchTest\Get-OptEntry 'UefiNeustart'
        $e | Should -Not -BeNullOrEmpty
        $e.Kat | Should -Be 'Bedienung'
        [string]$e.Vorlagen | Should -Match 'S'
        [string]$e.Vorlagen | Should -Match 'E'
        @($e.Aktionen)[0].Art | Should -Be 'RegKey'
    }
}

Describe 'Benutzer und Pfade der Optimierung' {
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
        (MinibenchTest\Get-OptEntryState $e $optEnv).Zustand | Should -Be 'offen'
        $r = MinibenchTest\Invoke-OptEntry $e $optEnv
        $r.Ergebnis | Should -Be 'angewendet'
        $r.Aenderungen | Should -Be 2
        (MinibenchTest\Invoke-OptEntry $e $optEnv).Ergebnis | Should -Be 'bereits so'
        (MinibenchTest\Get-OptEntryState $e $optEnv).Zustand | Should -Be 'aktiv'
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
        (MinibenchTest\Invoke-OptEntry $e $optEnv).Ergebnis | Should -Be 'übersprungen'
        Should -Invoke -ModuleName MinibenchTest Set-RegValueState -Times 0
    }
    It 'Dienst, den es nicht gibt: nicht vorhanden statt Fehler' {
        Mock -ModuleName MinibenchTest Get-ServiceStartType { throw 'nicht vorhanden' }
        $e = [pscustomobject]@{ Id = 'T3'; Titel = 'Dienst'; Kat = 'Hintergrund'; Risiko = 'Aendern'; Neustart = 'nie'; Bedingung = ''; Aktionen = @(@{ Art = 'Dienst'; Name = 'GibtsNicht'; Start = 'Disabled' }) }
        (MinibenchTest\Invoke-OptEntry $e $optEnv).Ergebnis | Should -Be 'nicht vorhanden'
    }
    It 'Dienst: Starttyp mit Vorher-Wert, Dienst wird beendet' {
        $script:svc = 'Automatic'
        Mock -ModuleName MinibenchTest Get-ServiceStartType { $script:svc }
        Mock -ModuleName MinibenchTest Set-ServiceStartType { $script:svc = $StartType }
        Mock -ModuleName MinibenchTest Stop-OptService { $true }
        $e = [pscustomobject]@{ Id = 'T4'; Titel = 'Dienst'; Kat = 'Hintergrund'; Risiko = 'Aendern'; Neustart = 'nie'; Bedingung = ''; Aktionen = @(@{ Art = 'Dienst'; Name = 'DiagTrack'; Start = 'Disabled' }) }
        (MinibenchTest\Invoke-OptEntry $e $optEnv).Ergebnis | Should -Be 'angewendet'
        $script:svc | Should -Be 'Disabled'
        Should -Invoke -ModuleName MinibenchTest Stop-OptService -Times 1
    }
    It 'Aufgabe: deaktiviert und über das Protokoll wieder aktiv' {
        $script:task = 'Ready'
        Mock -ModuleName MinibenchTest Get-OptTasks { @([pscustomobject]@{ Pfad = '\Microsoft\Windows\Test\'; Name = 'Sammler'; Zustand = $script:task }) }
        Mock -ModuleName MinibenchTest Disable-OptTask { $script:task = 'Disabled' }
        Mock -ModuleName MinibenchTest Enable-OptTask { $script:task = 'Ready' }
        $e = [pscustomobject]@{ Id = 'T5'; Titel = 'Aufgabe'; Kat = 'Datenschutz'; Risiko = 'Aendern'; Neustart = 'nie'; Bedingung = ''; Aktionen = @(@{ Art = 'Aufgabe'; Pfad = '\Microsoft\Windows\Test\'; Name = 'Sammler' }) }
        (MinibenchTest\Invoke-OptEntry $e $optEnv).Ergebnis | Should -Be 'angewendet'
        $script:task | Should -Be 'Disabled'
        $u = MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-ModuleVar 'ChangeFile'))
        $u.Rueckgaengig | Should -Be 1
        $script:task | Should -Be 'Ready'
    }
    It 'App: Eingriff, Fehler beim Entfernen landet im Ergebnis' {
        Mock -ModuleName MinibenchTest Get-OptApps { @([pscustomobject]@{ Name = 'Microsoft.BingNews'; Paket = 'Microsoft.BingNews_1.0_x64'; Version = '1.0' }) }
        Mock -ModuleName MinibenchTest Remove-OptApp { throw 'Zugriff verweigert' }
        $e = [pscustomobject]@{ Id = 'T6'; Titel = 'News'; Kat = 'Apps'; Risiko = 'Eingriff'; Neustart = 'nie'; Bedingung = ''; Aktionen = @(@{ Art = 'App'; Muster = 'Microsoft.BingNews' }) }
        $r = MinibenchTest\Invoke-OptEntry $e $optEnv
        $r.Ergebnis | Should -Be 'Fehler'
        $r.Details | Should -Match 'Zugriff verweigert'
    }
    It 'Windows-Funktion: Neustart wird vermerkt' {
        Mock -ModuleName MinibenchTest Get-OptFeatureState { 'Enabled' }
        Mock -ModuleName MinibenchTest Set-OptFeature { $true }
        $e = [pscustomobject]@{ Id = 'T7'; Titel = 'Funktion'; Kat = 'Funktionen'; Risiko = 'Aendern'; Neustart = 'moeglich'; Bedingung = ''; Aktionen = @(@{ Art = 'Feature'; Name = 'WorkFolders-Client' }) }
        $r = MinibenchTest\Invoke-OptEntry $e $optEnv
        $r.Neustart | Should -BeTrue
        @(Get-ModuleVar 'OptRestart') | Should -Contain 'Funktion'
    }
    It 'Rückgängig kennt neue Arten und lässt fremde unberührt' {
        MinibenchTest\Undo-OptChange ([pscustomobject]@{ Art = 'Unbekannt'; Daten = @{} }) | Should -BeNullOrEmpty
        Mock -ModuleName MinibenchTest Test-OptRegKey { $false }
        (MinibenchTest\Undo-OptChange ([pscustomobject]@{ Art = 'RegSchluessel'; Daten = [pscustomobject]@{ Pfad = 'HKCU:\X' } })).Status | Should -Be 'übersprungen'
    }
}

Describe 'Optimierung im Ablauf und im Bericht' {
    It 'Bericht: Zusammenfassung und je Kategorie eine Tabelle, Kategorien mit Fehlern aufgeklappt' {
        $log = [System.Collections.Generic.List[object]]::new()
        $log.Add([pscustomobject]@{ Titel = 'Werbe-ID aus'; Kat = 'Datenschutz'; Ergebnis = 'angewendet'; Aenderungen = 2; Risiko = 'Aendern'; Details = '' })
        $log.Add([pscustomobject]@{ Titel = 'Feedback <aus>'; Kat = 'Datenschutz'; Ergebnis = 'Fehler'; Aenderungen = 0; Risiko = 'Aendern'; Details = 'Zugriff verweigert' })
        Set-ModuleVar 'OptLog' $log
        Set-ModuleVar 'OptMetricsBefore' $null
        Set-ModuleVar 'OptMetricsAfter' $null
        $h = MinibenchTest\New-OptHtml
        $h | Should -Match '1 von 2 Einträgen angewendet, 2 Einzeländerungen'
        $h | Should -Match '<details open><summary><b>Datenschutz und Telemetrie</b>'
        $h | Should -Match 'badge crit">Fehler'
        $h | Should -Match 'Feedback &lt;aus&gt;'
        $h | Should -Not -Match 'Kennzahlen vorher und nachher'
        (Get-PartText 'Bericht\HtmlBericht.ps1') | Should -Match 'New-OptHtml'
    }
    It 'Absturz in einer Kategorie der Optimierung schaltet beim nächsten Lauf genau diese Kategorie ab' {
        $k = @(MinibenchTest\Get-OptCategories) | Where-Object { $_.Key -eq 'Sicherheit' }
        MinibenchTest\Get-SkipSwitch ('Optimierung: ' + $k.Titel) | Should -Be 'Opt8:Sicherheit'
        MinibenchTest\Get-SkipSwitch 'Optimierung: Ergebnis' | Should -BeNullOrEmpty
        MinibenchTest\Get-SkipSwitch 'Defender' | Should -Be 'Opt:Defender'
    }
    It 'Befehle der Wartungsaufgaben sind gültiges PowerShell' {
        $t = @(MinibenchTest\Get-OptMaintenanceTasks)
        $t.Count | Should -BeGreaterThan 0
        foreach ($x in $t) {
            $errs = $null; $tok = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($x.Befehl, [ref]$tok, [ref]$errs)
            @($errs).Count | Should -Be 0 -Because $x.Name
        }
    }
    It 'Wiederherstellungspunkt: nach dem Löschen alter Punkte wird ein neuer angelegt' {
        $a = Get-PartText 'Module\Optimierung\Ablauf.ps1'
        $del = $a.IndexOf("Invoke-Section 'Optimierung: Alte Wiederherstellungspunkte löschen'")
        $new = $a.IndexOf("Invoke-Section 'Optimierung: Wiederherstellungspunkt anlegen'")
        $del | Should -BeGreaterThan 0
        $new | Should -BeGreaterThan $del
        # der Punkt dieses Laufs ist mit gelöscht: die Nummer wird verworfen, damit danach ein neuer entsteht
        $a.Substring($del, $new - $del) | Should -Match '\$script:RestorePointNo = \$null'
    }
    It 'startet weder Sophia Script noch O&O ShutUp10++' {
        $b = (Get-MinibenchBuild).Text
        $b | Should -Not -Match 'Sophia\.ps1'
        $b | Should -Not -Match 'OOSU10\.exe'
    }
}

Describe 'Modul Wartung' {
    BeforeAll {
        $wartung = MinibenchTest\Get-ModuleContract 'Wartung'
    }
    It 'der Ablauf behandelt jeden Schritt des Vertrags' {
        $ablauf = Get-SrcText 'Module/Wartung/Ablauf.ps1'
        @($wartung.Schritte).Count | Should -BeGreaterThan 0
        foreach ($s in $wartung.Schritte) { $ablauf | Should -Match ("'" + [regex]::Escape($s.Key) + "'") -Because $s.Key }
    }
    It 'die übliche Auswahl enthält nur risikoarme Bereinigungen' {
        $ueblich = @($wartung.Schritte | Where-Object { $_.Ueblich } | ForEach-Object { $_.Key })
        foreach ($k in 'Datentraegerbereinigung', 'Temp', 'ShaderCache', 'UpdateDownloads', 'Absturzabbilder', 'Prefetch', 'WMI') { $ueblich | Should -Contain $k }
        foreach ($k in 'DismRestore', 'Sfc', 'Dateisystem') { $ueblich | Should -Not -Contain $k }
    }
}
