# Änderungsprotokoll und Rückgängig. Registry, Dienste und powercfg werden durch Attrappen ersetzt.
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Aenderungen.ps1' -Functions 'Get-SafeName', 'Invoke-External', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent'
    function New-Run {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-ModuleVar 'DataDir' $dir
        Set-ModuleVar 'ChangeLog' $null
        Set-ModuleVar 'DeviceIdentity' ([pscustomobject]@{ Id = 'G-aaaaaaaaaaaaaaaaaaaa'; Guete = 'hoch'; Quellen = @() })
        MinibenchTest\Start-ChangeLog
        return $dir
    }
    Mock -ModuleName MinibenchTest Write-Host { }
    function Get-RunFile { Get-ModuleVar 'ChangeFile' }
    function Read-Run { Get-Content -LiteralPath (Get-RunFile) -Raw -Encoding UTF8 | ConvertFrom-Json }
}

Describe 'Registry-Änderung' {
    BeforeEach {
        $null = New-Run
        $script:reg = @{ Vorhanden = $true; Wert = 1; Typ = 'DWord' }
        Mock -ModuleName MinibenchTest Get-RegValueState { [pscustomobject]$script:reg }
        Mock -ModuleName MinibenchTest Set-RegValueState { $script:reg = @{ Vorhanden = $true; Wert = $Value; Typ = $Type } }
        Mock -ModuleName MinibenchTest Remove-RegValue { $script:reg = @{ Vorhanden = $false; Wert = $null; Typ = '' } }
    }
    It 'protokolliert Vorher- und Nachher-Wert, bevor geschrieben wird' {
        $r = MinibenchTest\Set-RegistryValueLogged -Path 'HKLM:\SYSTEM\Test' -Name 'HiberbootEnabled' -Value 0 -Type 'DWord' -Modul 'Reparatur' -Schritt 'Schnellstart' -Titel 'Schnellstart deaktivieren'
        $r.Vorher | Should -Be '1'
        $r.Nachher | Should -Be '0'
        $r.Status | Should -Be 'aktiv'
        Should -Invoke -ModuleName MinibenchTest Set-RegValueState -Times 1
        $j = Read-Run
        $j.Format | Should -Be 'Minibench-Aenderungen/1'
        $j.GeraetId | Should -Be 'G-aaaaaaaaaaaaaaaaaaaa'
        @($j.Eintraege).Count | Should -Be 1
        (Get-RunFile) | Should -Match ([regex]::Escape([IO.Path]::Combine('Änderungen', (MinibenchTest\Get-SafeName $env:COMPUTERNAME))))
    }
    It 'schreibt nichts, wenn der Wert schon stimmt' {
        $script:reg = @{ Vorhanden = $true; Wert = 0; Typ = 'DWord' }
        MinibenchTest\Set-RegistryValueLogged -Path 'HKLM:\SYSTEM\Test' -Name 'HiberbootEnabled' -Value 0 -Modul 'R' -Schritt 'S' -Titel 'T' | Should -BeNullOrEmpty
        Should -Invoke -ModuleName MinibenchTest Set-RegValueState -Times 0
        Get-RunFile | Should -Not -Exist
    }
    It 'nimmt die Änderung zurück und vermerkt das' {
        [void](MinibenchTest\Set-RegistryValueLogged -Path 'HKLM:\SYSTEM\Test' -Name 'HiberbootEnabled' -Value 0 -Modul 'R' -Schritt 'S' -Titel 'T')
        $u = MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile))
        $u.Rueckgaengig | Should -Be 1
        $script:reg.Wert | Should -Be 1
        $script:reg.Typ | Should -Be 'DWord'
        (Read-Run).Eintraege[0].Status | Should -Be 'rückgängig'
        # ein zweites Mal passiert nichts
        $u2 = MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile))
        $u2.Rueckgaengig | Should -Be 0
        Should -Invoke -ModuleName MinibenchTest Set-RegValueState -Times 2
    }
    It 'überspringt, wenn der Wert inzwischen anders ist' {
        [void](MinibenchTest\Set-RegistryValueLogged -Path 'HKLM:\SYSTEM\Test' -Name 'HiberbootEnabled' -Value 0 -Modul 'R' -Schritt 'S' -Titel 'T')
        $script:reg = @{ Vorhanden = $true; Wert = 5; Typ = 'DWord' }
        $u = MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile))
        $u.Probleme | Should -Be 1
        $script:reg.Wert | Should -Be 5
        (Read-Run).Eintraege[0].Status | Should -Be 'übersprungen'
    }
    It 'entfernt einen Wert, der vorher nicht da war' {
        $script:reg = @{ Vorhanden = $false; Wert = $null; Typ = '' }
        [void](MinibenchTest\Set-RegistryValueLogged -Path 'HKLM:\SOFTWARE\Test' -Name 'Neu' -Value 'abc' -Type 'String' -Modul 'R' -Schritt 'S' -Titel 'T')
        [void](MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile)))
        Should -Invoke -ModuleName MinibenchTest Remove-RegValue -Times 1
        $script:reg.Vorhanden | Should -BeFalse
    }
    It 'stellt Binärwerte nach dem Weg über JSON korrekt wieder her' {
        $script:reg = @{ Vorhanden = $true; Wert = [byte[]](1, 2, 255); Typ = 'Binary' }
        [void](MinibenchTest\Set-RegistryValueLogged -Path 'HKLM:\SOFTWARE\Test' -Name 'Bin' -Value ([byte[]](9, 9)) -Type 'Binary' -Modul 'R' -Schritt 'S' -Titel 'T')
        [void](MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile)))
        ($script:reg.Wert -join ',') | Should -Be '1,2,255'
        $script:reg.Typ | Should -Be 'Binary'
        # Set-RegValueState wandelt vor dem Schreiben in den Registry-Typ um
        (MinibenchTest\ConvertTo-RegValue $script:reg.Wert 'Binary').GetType().Name | Should -Be 'Byte[]'
        (MinibenchTest\ConvertTo-RegValue ([long]0) 'DWord').GetType().Name | Should -Be 'Int32'
        (MinibenchTest\ConvertTo-RegValue @('a', 'b') 'MultiString').GetType().Name | Should -Be 'String[]'
    }
}

Describe 'Schutz beim Rückgängig' {
    BeforeEach {
        $null = New-Run
        $script:reg = @{ Vorhanden = $true; Wert = 1; Typ = 'DWord' }
        Mock -ModuleName MinibenchTest Get-RegValueState { [pscustomobject]$script:reg }
        Mock -ModuleName MinibenchTest Set-RegValueState { $script:reg = @{ Vorhanden = $true; Wert = $Value; Typ = $Type } }
        [void](MinibenchTest\Set-RegistryValueLogged -Path 'HKLM:\SYSTEM\Test' -Name 'X' -Value 0 -Modul 'R' -Schritt 'S' -Titel 'T')
    }
    It 'verweigert Rückgängig auf einem anderen Gerät' {
        Set-ModuleVar 'DeviceIdentity' ([pscustomobject]@{ Id = 'G-bbbbbbbbbbbbbbbbbbbb'; Guete = 'hoch'; Quellen = @() })
        $u = MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile))
        $u.Rueckgaengig | Should -Be 0
        $u.Probleme | Should -Be 1
        $script:reg.Wert | Should -Be 0
    }
    It 'verweigert Dateien außerhalb des Protokollordners' {
        $fremd = Join-Path $TestDrive 'fremd.json'
        Copy-Item (Get-RunFile) $fremd
        (MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f $fremd)).Probleme | Should -Be 1
        $script:reg.Wert | Should -Be 0
    }
    It 'ignoriert unsinnige Auswahl' {
        (MinibenchTest\Invoke-ChangeUndo ('{0}*abc;;nur-text' -f (Get-RunFile))).Rueckgaengig | Should -Be 0
    }
}

Describe 'Dienst-Starttyp' {
    BeforeEach {
        $null = New-Run
        $script:svc = 'Disabled'
        Mock -ModuleName MinibenchTest Get-ServiceStartType { $script:svc }
        Mock -ModuleName MinibenchTest Set-ServiceStartType { $script:svc = $StartType }
    }
    It 'protokolliert und nimmt zurück' {
        $r = MinibenchTest\Set-ServiceStartTypeLogged -Name 'w32time' -StartType 'Manual' -Modul 'Reparatur' -Schritt 'Zeit' -Titel 'Zeit synchronisieren'
        $r.Vorher | Should -Be 'Disabled'
        $script:svc | Should -Be 'Manual'
        [void](MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile)))
        $script:svc | Should -Be 'Disabled'
    }
    It 'tut nichts, wenn der Starttyp schon stimmt' {
        $script:svc = 'Manual'
        MinibenchTest\Set-ServiceStartTypeLogged -Name 'w32time' -StartType 'Manual' -Modul 'R' -Schritt 'S' -Titel 'T' | Should -BeNullOrEmpty
        Should -Invoke -ModuleName MinibenchTest Set-ServiceStartType -Times 0
    }
}

Describe 'Energiepläne' {
    BeforeEach {
        $null = New-Run
        # Ausgangslage: Ausbalanciert, Höchstleistung und ein eigener Plan (aktiv)
        $script:plans = [ordered]@{ '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Ausbalanciert'; '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'Höchstleistung'; '11111111-2222-3333-4444-555555555555' = 'Werkstatt' }
        $script:active = '11111111-2222-3333-4444-555555555555'
        Mock -ModuleName MinibenchTest Invoke-PowerCfg {
            $a = $Arguments
            if ($a -eq '/list') {
                $t = "Bestehende Energieschemas (* Aktiv)`r`n-----------------------------------`r`n"
                foreach ($g in $script:plans.Keys) { $t += ('GUID des Energieschemas: {0}  ({1}){2}' -f $g, $script:plans[$g], $(if ($g -eq $script:active) { ' *' } else { '' })) + "`r`n" }
                return [pscustomobject]@{ ExitCode = 0; Output = $t; Error = '' }
            }
            if ($a -match '^/export "(.+)" (\S+)$') { Set-Content -LiteralPath $Matches[1] -Value $Matches[2]; return [pscustomobject]@{ ExitCode = 0; Output = ''; Error = '' } }
            if ($a -match '^/import "(.+)" (\S+)$') { $script:plans[$Matches[2]] = 'importiert'; return [pscustomobject]@{ ExitCode = 0; Output = ''; Error = '' } }
            if ($a -match '^/setactive (\S+)$') { if ($script:plans.Contains($Matches[1])) { $script:active = $Matches[1]; return [pscustomobject]@{ ExitCode = 0 } } else { return [pscustomobject]@{ ExitCode = 1 } } }
            return [pscustomobject]@{ ExitCode = 1; Output = ''; Error = 'unbekannt' }
        }
    }
    It 'sichert alle Pläne in den Ordner des Laufs' {
        $r = MinibenchTest\Backup-PowerSchemesLogged -Modul 'Reparatur' -Schritt 'Energieplaene' -Titel 'Energiesparpläne zurücksetzen'
        $r.Vorher | Should -Match '3 Pläne, aktiv: Werkstatt'
        @(Get-ChildItem (MinibenchTest\Get-ChangeFilesDir) -Filter '*.pow').Count | Should -Be 3
    }
    It 'stellt nach dem Zurücksetzen den eigenen Plan und den aktiven Plan wieder her' {
        [void](MinibenchTest\Backup-PowerSchemesLogged -Modul 'Reparatur' -Schritt 'Energieplaene' -Titel 'Energiesparpläne zurücksetzen')
        # powercfg -restoredefaultschemes: eigener Plan weg, Ausbalanciert aktiv
        $script:plans.Remove('11111111-2222-3333-4444-555555555555'); $script:active = '381b4222-f694-41f0-9685-ff5bb260df2e'
        $u = MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile))
        $u.Rueckgaengig | Should -Be 1
        $script:plans.Contains('11111111-2222-3333-4444-555555555555') | Should -BeTrue
        $script:active | Should -Be '11111111-2222-3333-4444-555555555555'
        Should -Invoke -ModuleName MinibenchTest Invoke-PowerCfg -ParameterFilter { $Arguments -like '/import*' } -Times 1
    }
    It 'bricht ab, wenn powercfg keine Pläne liefert' {
        $script:plans = [ordered]@{}
        { MinibenchTest\Backup-PowerSchemesLogged -Modul 'R' -Schritt 'S' -Titel 'T' } | Should -Throw '*keine Energiepläne*'
    }
}

Describe 'Liste der Energiepläne' {
    It 'liest deutsche und englische Ausgabe von powercfg /list' {
        $de = "GUID des Energieschemas: 381b4222-f694-41f0-9685-ff5bb260df2e  (Ausbalanciert) *`r`nGUID des Energieschemas: a1841308-3541-4fab-bc81-f71556f20b4a  (Energiesparmodus)"
        $en = 'Power Scheme GUID: 8C5E7FDA-E8BF-4A96-9A85-A6E23A8C635C  (High performance)'
        $p = @(MinibenchTest\ConvertFrom-PowerCfgList $de)
        $p.Count | Should -Be 2
        $p[0].Aktiv | Should -BeTrue
        $p[1].Name | Should -Be 'Energiesparmodus'
        (MinibenchTest\ConvertFrom-PowerCfgList $en).Guid | Should -Be '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    }
}

Describe 'Hinweise und Übersicht' {
    It 'Hinweise lassen sich nicht automatisch zurücknehmen' {
        $null = New-Run
        [void](MinibenchTest\Add-ChangeRecord -Modul 'Reparatur' -Schritt 'Wiederherstellungspunkt' -Titel 'Wiederherstellungspunkt' -Risiko 'Lesen' -Art 'Wiederherstellungspunkt' -Ziel 'Computerschutz' -Gegenbefehl 'rstrui.exe' -NurHinweis)
        $u = MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile))
        $u.Rueckgaengig | Should -Be 0
        (Read-Run).Eintraege[0].Status | Should -Be 'nur Hinweis'
    }
    It 'Läufe ohne Änderung hinterlassen keine Datei' {
        $dir = New-Run
        Join-Path $dir 'Änderungen' | Should -Not -Exist
    }
    It 'listet Einträge aller Läufe, neueste zuerst' {
        $dir = New-Run
        [void](MinibenchTest\Add-ChangeRecord -Modul 'R' -Schritt 'A' -Titel 'Erster' -Risiko 'Aendern' -Art 'Hinweis' -Ziel 'x' -NurHinweis)
        Start-Sleep -Milliseconds 1100
        [void](MinibenchTest\Add-ChangeRecord -Modul 'R' -Schritt 'B' -Titel 'Zweiter' -Risiko 'Aendern' -Art 'Hinweis' -Ziel 'y' -NurHinweis)
        $l = @(MinibenchTest\Get-ChangeEntries (Join-Path $dir 'Änderungen'))
        $l.Count | Should -Be 2
        $l[0].Titel | Should -Be 'Zweiter'
    }
}

Describe 'Vorübergehende Änderung eines abgebrochenen Laufs (GPU-Wahl für winsat.exe)' {
    BeforeEach {
        $null = New-Run
        $script:reg = @{ Vorhanden = $false; Wert = $null; Typ = '' }
        Mock -ModuleName MinibenchTest Get-RegValueState { [pscustomobject]$script:reg }
        Mock -ModuleName MinibenchTest Set-RegValueState { $script:reg = @{ Vorhanden = $true; Wert = $Value; Typ = $Type } }
        Mock -ModuleName MinibenchTest Remove-RegValue { $script:reg = @{ Vorhanden = $false; Wert = $null; Typ = '' } }
    }
    It 'Undo-ChangeNow nimmt sie direkt nach der Messung zurück' {
        $r = MinibenchTest\Set-RegistryValueLogged -Path 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'C:\Windows\System32\winsat.exe' -Value 'GpuPreference=2;' -Type 'String' -Modul 'Benchmark' -Schritt 'GpuWahl' -Titel 'WinSAT auf die Grafikkarte'
        (MinibenchTest\Undo-ChangeNow $r).Status | Should -Be 'rückgängig'
        $script:reg.Vorhanden | Should -BeFalse
        (Read-Run).Eintraege[0].Status | Should -Be 'rückgängig'
    }
    It 'der nächste Start nimmt eine liegen gebliebene GPU-Wahl zurück, andere aktive Änderungen bleiben' {
        [void](MinibenchTest\Set-RegistryValueLogged -Path 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'C:\Windows\System32\winsat.exe' -Value 'GpuPreference=2;' -Type 'String' -Modul 'Benchmark' -Schritt 'GpuWahl' -Titel 'WinSAT auf die Grafikkarte')
        [void](MinibenchTest\Add-ChangeRecord -Modul 'Reparatur' -Schritt 'Schnellstart' -Titel 'bleibt' -Risiko 'Aendern' -Art 'Registry' -Ziel 'x' -Daten ([ordered]@{ Pfad = 'HKLM:\X'; Name = 'Y'; VorherVorhanden = $false; NachherWert = 0 }))
        $alt = Get-RunFile
        # neuer Lauf mit eigener Protokolldatei
        Set-ModuleVar 'ChangeLog' $null; Start-Sleep -Milliseconds 1100; MinibenchTest\Start-ChangeLog
        $u = MinibenchTest\Restore-TemporaryChanges
        $u.Rueckgaengig | Should -Be 1
        $script:reg.Vorhanden | Should -BeFalse
        $j = Get-Content -LiteralPath $alt -Raw -Encoding UTF8 | ConvertFrom-Json
        @($j.Eintraege | ForEach-Object { $_.Status }) | Should -Be @('rückgängig', 'aktiv')
        MinibenchTest\Restore-TemporaryChanges | Should -BeNullOrEmpty
    }
}

# Seite Tools (ab v3.53): Softwarepakete über winget im Arbeitsprozess, mit Frist, Änderungsprotokoll und Rückgängig.
# winget selbst ist eine Attrappe (Invoke-Winget); sie merkt sich, was "installiert" ist.
Describe 'Softwarepakete über winget' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Aenderungen.ps1', 'Kern\Softwarepakete.ps1' -Functions 'Get-SafeName', 'Invoke-External', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent'
        Mock -ModuleName MinibenchTest Write-Host { }
        $script:NichtGefunden = -1978335212   # 0x8A150014
    }
    BeforeEach {
        $null = New-Run
        $script:Inst = @{}
        $script:InstallErgebnis = $null
        $script:ListErgebnis = $null
        Mock -ModuleName MinibenchTest Find-Winget { 'winget.exe' }
        Mock -ModuleName MinibenchTest Invoke-Winget {
            $id = ([string]$Arguments -split ' ')[2]
            if ($Arguments -like 'list *') {
                if ($script:ListErgebnis) { return $script:ListErgebnis }
                if ($script:Inst.ContainsKey($id)) { return [pscustomobject]@{ ExitCode = 0; Output = ('Name  Id  Version`n7-Zip {0} 24.08' -f $id); Error = ''; TimedOut = $false } }
                return [pscustomobject]@{ ExitCode = $script:NichtGefunden; Output = 'Kein installiertes Paket gefunden'; Error = ''; TimedOut = $false }
            }
            if ($Arguments -like 'install *') {
                if ($script:InstallErgebnis) { return $script:InstallErgebnis }
                $script:Inst[$id] = $true; return [pscustomobject]@{ ExitCode = 0; Output = 'Erfolgreich installiert'; Error = ''; TimedOut = $false }
            }
            if ($Arguments -like 'uninstall *') { $script:Inst.Remove($id); return [pscustomobject]@{ ExitCode = 0; Output = 'Erfolgreich deinstalliert'; Error = ''; TimedOut = $false } }
            throw ('unerwarteter Aufruf: ' + $Arguments)
        }
    }
    It 'installiert, protokolliert als Eingriff mit Gegenbefehl und nimmt die Installation über Rückgängig wieder heraus' {
        $r = MinibenchTest\Invoke-SoftwarePakete '7zip.7zip=7-Zip'
        $r.Installiert | Should -Be 1
        $r.Fehler | Should -Be 0
        $script:Inst.ContainsKey('7zip.7zip') | Should -BeTrue
        $e = @((Read-Run).Eintraege)
        $e.Count | Should -Be 1
        $e[0].Art | Should -Be 'Softwarepaket'
        $e[0].Risiko | Should -Be 'Eingriff'
        $e[0].Modul | Should -Be 'Tools'
        $e[0].Gegenbefehl | Should -Be 'winget uninstall --id 7zip.7zip -e'
        $e[0].Daten.PaketId | Should -Be '7zip.7zip'
        $e[0].Status | Should -Be 'aktiv'
        $u = MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile))
        $u.Rueckgaengig | Should -Be 1
        $script:Inst.ContainsKey('7zip.7zip') | Should -BeFalse
        (Read-Run).Eintraege[0].Status | Should -Be 'rückgängig'
    }
    It 'lässt ein schon installiertes Programm unberührt und protokolliert nichts' {
        $script:Inst['Mozilla.Firefox'] = $true
        $r = MinibenchTest\Invoke-SoftwarePakete 'Mozilla.Firefox=Mozilla Firefox'
        $r.Bereits | Should -Be 1
        $r.Installiert | Should -Be 0
        Should -Invoke -ModuleName MinibenchTest Invoke-Winget -Times 0 -ParameterFilter { $Arguments -like 'install *' }
        Get-RunFile | Should -Not -Exist
    }
    It 'meldet Zeitüberschreitung und Fehlercodes und protokolliert dann nichts' {
        $script:InstallErgebnis = [pscustomobject]@{ ExitCode = -2; Output = ''; Error = ''; TimedOut = $true }
        $a = MinibenchTest\Invoke-SoftwarePakete 'Valve.Steam=Steam'
        $a.Ergebnisse[0].Status | Should -Be 'Zeitüberschreitung'
        $script:InstallErgebnis = [pscustomobject]@{ ExitCode = [int]-1978335217; Output = 'Fehler beim Öffnen der Quelle'; Error = ''; TimedOut = $false }
        $b = MinibenchTest\Invoke-SoftwarePakete 'Discord.Discord=Discord'
        $b.Ergebnisse[0].Status | Should -Be 'fehlgeschlagen'
        $b.Ergebnisse[0].Text | Should -Match '0x8A15000F'
        ($a.Fehler + $b.Fehler) | Should -Be 2
        Get-RunFile | Should -Not -Exist
    }
    It 'installiert nicht, wenn winget den Zustand nicht feststellen kann (defekte Quelle, Frist)' {
        $script:ListErgebnis = [pscustomobject]@{ ExitCode = [int]-1978335217; Output = 'Fehler beim Öffnen der Quelle'; Error = ''; TimedOut = $false }
        $a = MinibenchTest\Invoke-SoftwarePakete 'Google.Chrome=Google Chrome'
        $script:ListErgebnis = [pscustomobject]@{ ExitCode = -2; Output = ''; Error = ''; TimedOut = $true }
        $b = MinibenchTest\Invoke-SoftwarePakete 'Mozilla.Firefox=Mozilla Firefox'
        $a.Ergebnisse[0].Status | Should -Be 'fehlgeschlagen'
        $b.Ergebnisse[0].Status | Should -Be 'fehlgeschlagen'
        Should -Invoke -ModuleName MinibenchTest Invoke-Winget -Times 0 -ParameterFilter { $Arguments -like 'install *' }
        Get-RunFile | Should -Not -Exist
    }
    It 'installiert ohne Aktualisierung eines vorhandenen Programms; "schon installiert" von winget wird nicht protokolliert' {
        $script:InstallErgebnis = [pscustomobject]@{ ExitCode = [int]-1978335135; Output = 'Ein vorhandenes Paket wurde bereits installiert'; Error = ''; TimedOut = $false }   # 0x8A150061
        $r = MinibenchTest\Invoke-SoftwarePakete 'Notepad++.Notepad++=Notepad++'
        $r.Ergebnisse[0].Status | Should -Be 'bereits installiert'
        Should -Invoke -ModuleName MinibenchTest Invoke-Winget -Times 1 -ParameterFilter { $Arguments -like 'install *--no-upgrade*' }
        Get-RunFile | Should -Not -Exist
    }
    It 'Neustart nötig (0x8A150109) gilt als installiert und wird protokolliert' {
        $script:InstallErgebnis = [pscustomobject]@{ ExitCode = [int]-1978334967; Output = 'Neustart erforderlich'; Error = ''; TimedOut = $false }   # 0x8A150109
        $r = MinibenchTest\Invoke-SoftwarePakete 'ONLYOFFICE.DesktopEditors=ONLYOFFICE'
        $r.Installiert | Should -Be 1
        $r.Ergebnisse[0].Text | Should -Match 'Neustart'
        (Read-Run).Eintraege[0].Nachher | Should -Be 'installiert, Neustart nötig'
    }
    It 'Rückgängig lässt den Eintrag aktiv, wenn winget den Zustand nicht feststellen kann' {
        [void](MinibenchTest\Invoke-SoftwarePakete 'VideoLAN.VLC=VLC')
        $script:ListErgebnis = [pscustomobject]@{ ExitCode = [int]-1978335217; Output = ''; Error = ''; TimedOut = $false }
        $u = MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile))
        $u.Rueckgaengig | Should -Be 0
        (Read-Run).Eintraege[0].Status | Should -Be 'aktiv'
        $script:Inst.ContainsKey('VideoLAN.VLC') | Should -BeTrue
        Should -Invoke -ModuleName MinibenchTest Invoke-Winget -Times 0 -ParameterFilter { $Arguments -like 'uninstall *' }
    }
    It 'gibt ungültige Paketkennungen nicht an winget weiter' {
        $r = MinibenchTest\Invoke-SoftwarePakete 'x" & calc.exe=böse;;Google.Chrome=Google Chrome'
        $r.Ergebnisse[0].Status | Should -Be 'ungültig'
        $r.Ergebnisse[1].Status | Should -Be 'installiert'
        Should -Invoke -ModuleName MinibenchTest Invoke-Winget -Times 0 -ParameterFilter { $Arguments -like '*calc*' }
        MinibenchTest\Test-WingetId 'Notepad++.Notepad++' | Should -BeTrue
        MinibenchTest\Test-WingetId '-e --force' | Should -BeFalse
    }
    It 'ohne winget: jedes Paket fehlgeschlagen mit Begründung' {
        Mock -ModuleName MinibenchTest Find-Winget { '' }
        $r = MinibenchTest\Invoke-SoftwarePakete 'Google.Chrome=Google Chrome'
        $r.Fehler | Should -Be 1
        $r.Ergebnisse[0].Text | Should -Match 'nicht verfügbar'
    }
    It 'Rückgängig überspringt ein inzwischen von Hand entferntes Programm' {
        [void](MinibenchTest\Invoke-SoftwarePakete 'VideoLAN.VLC=VLC')
        $script:Inst.Remove('VideoLAN.VLC')
        $u = MinibenchTest\Invoke-ChangeUndo ('{0}*1' -f (Get-RunFile))
        $u.Rueckgaengig | Should -Be 0
        (Read-Run).Eintraege[0].Status | Should -Be 'übersprungen'
        Should -Invoke -ModuleName MinibenchTest Invoke-Winget -Times 0 -ParameterFilter { $Arguments -like 'uninstall *' }
    }
}

Describe 'Aufruf von winget' {
    BeforeAll {
        Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1', 'Kern\Geraeteidentitaet.ps1', 'Kern\Aenderungen.ps1', 'Kern\Softwarepakete.ps1' -Functions 'Get-SafeName', 'Invoke-External', 'Show-Sub', 'Hide-Sub', 'Write-Heartbeat', 'Send-GuiEvent'
    }
    It 'winget läuft mit Frist, gelesener Ausgabe und ohne Reaktion auf skip.flag eines Laufs' {
        Mock -ModuleName MinibenchTest Invoke-External { [pscustomobject]@{ ExitCode = 0; Output = ''; Error = ''; TimedOut = $false } }
        [void](& (Get-Module MinibenchTest) { Invoke-Winget 'winget.exe' 'list --id 7zip.7zip -e' 120 })
        Should -Invoke -ModuleName MinibenchTest Invoke-External -Times 1 -ParameterFilter { $TimeoutSec -eq 120 -and $OhneUeberspringen -and $File -eq 'winget.exe' }
        (Get-ModuleVar 'WingetFristSek') | Should -BeGreaterThan 0
        (Get-ModuleVar 'WingetFristSek') | Should -BeLessOrEqual 3600
    }
}
