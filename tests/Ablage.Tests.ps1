# Netzlaufwerk als Spiegel der Nutzerdaten (Kern\Ablage.ps1, ab v3.54): Netzwerk.json, Abgleich auf Knopfdruck in beide
# Richtungen mit Archiv für Konflikte und Löschungen, Entfernen und Umbenennen von Läufen der Vergleichsdatenbank.
# Ein Ordner in TestDrive steht für die Freigabe auf dem NAS (UNC-Pfade lassen sich in der Sandbox nicht verbinden);
# Test-NasPfad wird dafür ersetzt, Test-NasErreichbar läuft echt.
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Parts 'Kern\Ablage.ps1' -Functions 'Test-IsNetworkPath' -Setup @'
function Send-GuiEvent { param([string]$Kind, [Parameter(ValueFromRemainingArguments = $true)][object[]]$Parts) }
'@
    function New-TestDir([string]$Prefix = 'd') {
        $d = Join-Path $TestDrive ($Prefix + '_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d | Out-Null
        return $d
    }
    # Rel mit \ wie im Programm; Zeit als Minuten relativ zu jetzt
    function Get-Pfad([string]$Root, [string]$Rel) { return (Join-Path $Root ($Rel -replace '\\', [IO.Path]::DirectorySeparatorChar)) }
    function Set-Datei([string]$Root, [string]$Rel, [string]$Text, [double]$Minuten = -60) {
        $f = Get-Pfad $Root $Rel
        New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force | Out-Null
        [IO.File]::WriteAllText($f, $Text)
        [IO.File]::SetLastWriteTimeUtc($f, [DateTime]::UtcNow.AddMinutes($Minuten))
        return $f
    }
    function Get-Inhalt([string]$Root, [string]$Rel) { $f = Get-Pfad $Root $Rel; if (Test-Path -LiteralPath $f) { return [IO.File]::ReadAllText($f) } else { return $null } }
    function Get-Archiv([string]$Root, [string]$Art, [string]$Rel) {
        $a = Join-Path (Join-Path $Root 'Archiv') 'Abgleich'
        if (-not (Test-Path -LiteralPath $a)) { return @() }
        return @(Get-ChildItem -LiteralPath $a -Directory | ForEach-Object { Get-Pfad (Join-Path $_.FullName $Art) $Rel } | Where-Object { Test-Path -LiteralPath $_ })
    }
    function Invoke-TestAbgleich([string]$Lokal, [string]$Nas) { return (MinibenchTest\Invoke-Abgleich -DataDir $Lokal -NasPfad $Nas -TimeoutMs 5000) }
    # zwei Seiten, einmal abgeglichen
    function New-Paar {
        $l = New-TestDir 'stick'; $n = New-TestDir 'nas'
        Set-Datei $l 'Datenbank\PC1_20261003_142535.json' '{"Name":"PC1"}' -120 | Out-Null
        Set-Datei $l 'Berichte\PC1_20261003_1421\Diagnosebericht.txt' 'Bericht PC1' -120 | Out-Null
        Set-Datei $n 'Datenbank\PC2_20261004_100000.json' '{"Name":"PC2"}' -90 | Out-Null
        $r = Invoke-TestAbgleich $l $n
        if (-not $r.Ok) { throw ('erster Abgleich fehlgeschlagen: ' + $r.Kurz) }
        return [pscustomobject]@{ L = $l; N = $n }
    }
    # Wörterbuch Rel -> @{S;T} für Get-AbgleichPlan; Werte als @(Größe, Sekunden)
    function New-Bestand([hashtable]$H) {
        $d = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($k in $H.Keys) { $d[$k] = [pscustomobject]@{ S = [int64]$H[$k][0]; T = [int64]([double]$H[$k][1] * 1e7) } }
        return $d
    }
    function New-Stand([hashtable]$H) {
        $d = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($k in $H.Keys) {
            $d[$k] = [pscustomobject]@{ L = [pscustomobject]@{ S = [int64]$H[$k][0]; T = [int64]([double]$H[$k][1] * 1e7) }; N = [pscustomobject]@{ S = [int64]$H[$k][2]; T = [int64]([double]$H[$k][3] * 1e7) } }
        }
        return $d
    }
}

Describe 'NAS-Pfad und Netzwerk.json' {
    BeforeEach {
        Mock -ModuleName MinibenchTest Test-IsNetworkPath { $false }
        Mock -ModuleName MinibenchTest Test-IsNetworkPath { $true } -ParameterFilter { ([string]$Path).StartsWith('I:') }
    }
    It 'Test-NasPfad: <Pfad> -> <Erwartung>' -ForEach @(
        @{ Pfad = '\\TRUENAS\Multimedia\MiniBench'; Erwartung = '' }
        @{ Pfad = '\\nas\freigabe'; Erwartung = '' }
        @{ Pfad = 'I:\MiniBench'; Erwartung = '' }
        @{ Pfad = '\TRUENAS\Multimedia\MiniBench'; Erwartung = 'nur einem' }
        @{ Pfad = 'C:\Daten'; Erwartung = 'kein Netzlaufwerk' }
        @{ Pfad = 'TRUENAS\Multimedia'; Erwartung = 'kein UNC-Pfad' }
        @{ Pfad = '   '; Erwartung = 'kein Pfad' }
    ) {
        $r = MinibenchTest\Test-NasPfad $Pfad
        if ($Erwartung) { $r | Should -Match $Erwartung } else { $r | Should -BeNullOrEmpty }
    }
    It 'ohne Netzwerk.json gibt es keine Konfiguration, beschädigte Dateien gelten als fehlend' {
        $d = New-TestDir
        MinibenchTest\Get-NasKonfig $d | Should -BeNullOrEmpty
        [IO.File]::WriteAllText((Join-Path $d 'Netzwerk.json'), '{ kaputt')
        MinibenchTest\Get-NasKonfig $d | Should -BeNullOrEmpty
    }
    It 'Save-NasKonfig und Get-NasKonfig: Pfad ohne abschließendes \, Benutzer, kein Kennwort, UTF-8 mit BOM' {
        $d = New-TestDir
        MinibenchTest\Save-NasKonfig $d '\\TRUENAS\Multimedia\MiniBench\' 'leo'
        $k = MinibenchTest\Get-NasKonfig $d
        $k.Pfad | Should -Be '\\TRUENAS\Multimedia\MiniBench'
        $k.Benutzer | Should -Be 'leo'
        $k.Fehler | Should -BeNullOrEmpty
        $b = [IO.File]::ReadAllBytes((Join-Path $d 'Netzwerk.json'))
        ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) | Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $d 'Netzwerk.json')) | Should -Not -Match '(?i)kennwort|passw'
    }
    It 'liest den Schlüssel NetzwerkPfad früherer Versionen und meldet einen Pfad mit nur einem \' {
        $d = New-TestDir
        [IO.File]::WriteAllText((Join-Path $d 'Netzwerk.json'), '{"NetzwerkPfad":"\\TRUENAS\\Multimedia\\MiniBench"}')
        $k = MinibenchTest\Get-NasKonfig $d
        $k.Pfad | Should -Be '\TRUENAS\Multimedia\MiniBench'
        $k.Fehler | Should -Match 'nur einem'
    }
    It 'Format-NasPfad: <Pfad> -> <Erwartung>' -ForEach @(
        @{ Pfad = ' \\nas\daten\ '; Erwartung = '\\nas\daten' }
        @{ Pfad = 'Z:\'; Erwartung = 'Z:\' }
        @{ Pfad = 'Z:'; Erwartung = 'Z:\' }
        @{ Pfad = 'Z:\MiniBench\'; Erwartung = 'Z:\MiniBench' }
    ) {
        MinibenchTest\Format-NasPfad $Pfad | Should -Be $Erwartung
    }
    It 'alte Kopien von Netzwerk.json mit demselben NAS-Pfad werden entfernt, nie übernommen' {
        $d = New-TestDir 'daten'
        MinibenchTest\Save-NasKonfig $d '\\nas\daten\Minibench'
        $docs = Join-Path (New-TestDir 'docs') 'Leos Minibench'
        $app = Join-Path (New-TestDir 'appdata') 'LeosMinibench'
        foreach ($o in $docs, $app) { New-Item -ItemType Directory -Path $o | Out-Null; [IO.File]::WriteAllText((Join-Path $o 'Netzwerk.json'), '{"NasPfad":"\\\\nas\\daten\\Minibench\\"}') }
        [IO.File]::WriteAllText((Join-Path $docs 'Referenz.json'), '{}')
        $z = @(MinibenchTest\Move-AlteNasKonfig $d @((Join-Path $docs 'Netzwerk.json'), (Join-Path $app 'Netzwerk.json')))
        Join-Path $docs 'Netzwerk.json' | Should -Not -Exist
        Join-Path $docs 'Referenz.json' | Should -Exist
        $app | Should -Not -Exist
        $z.Count | Should -Be 2
    }
    It 'ein Stick ohne Netzlaufwerk übernimmt keine fremde Netzwerk.json (anderer PC, anderes NAS)' {
        $d = New-TestDir 'daten'
        $fremd = Join-Path (New-TestDir 'docs') 'Netzwerk.json'
        [IO.File]::WriteAllText($fremd, '{"NasPfad":"\\\\fremdes-nas\\daten"}')
        $null = MinibenchTest\Move-AlteNasKonfig $d @($fremd)
        Join-Path $d 'Netzwerk.json' | Should -Not -Exist
        $fremd | Should -Exist
    }
    It 'eine Kopie zu einem anderen NAS bleibt stehen' {
        $d = New-TestDir 'daten'
        MinibenchTest\Save-NasKonfig $d '\\nas\neu'
        $alt = Join-Path (New-TestDir 'docs') 'Netzwerk.json'
        [IO.File]::WriteAllText($alt, '{"NasPfad":"\\\\nas\\alt"}')
        $null = MinibenchTest\Move-AlteNasKonfig $d @($alt)
        (MinibenchTest\Get-NasKonfig $d).Pfad | Should -Be '\\nas\neu'
        $alt | Should -Exist
    }
}

Describe 'Plan des Abgleichs' {
    # Werte: Größe und Zeit in Sekunden; Stand: lokal Größe, Zeit, NAS Größe, Zeit
    It '<Fall>' -ForEach @(
        @{ Fall = 'nur auf dem Stick, neu'; L = @{ a = 1, 100 }; N = @{}; B = @{}; Aktion = 'NachNas' }
        @{ Fall = 'nur auf dem NAS, neu'; L = @{}; N = @{ a = 1, 100 }; B = @{}; Aktion = 'VomNas' }
        @{ Fall = 'auf dem NAS gelöscht'; L = @{ a = 1, 100 }; N = @{}; B = @{ a = 1, 100, 1, 100 }; Aktion = 'LoeschenLokal' }
        @{ Fall = 'auf dem Stick gelöscht'; L = @{}; N = @{ a = 1, 100 }; B = @{ a = 1, 100, 1, 100 }; Aktion = 'LoeschenNas' }
        @{ Fall = 'auf dem NAS gelöscht, auf dem Stick geändert: Änderung gewinnt'; L = @{ a = 2, 200 }; N = @{}; B = @{ a = 1, 100, 1, 100 }; Aktion = 'NachNas' }
        @{ Fall = 'auf dem Stick gelöscht, auf dem NAS geändert: Änderung gewinnt'; L = @{}; N = @{ a = 2, 200 }; B = @{ a = 1, 100, 1, 100 }; Aktion = 'VomNas' }
        @{ Fall = 'gleich'; L = @{ a = 1, 100 }; N = @{ a = 1, 100 }; B = @{}; Aktion = 'Gleich' }
        @{ Fall = 'Zeit 1 s versetzt (FAT): gleich'; L = @{ a = 1, 100 }; N = @{ a = 1, 101 }; B = @{}; Aktion = 'Gleich' }
        @{ Fall = 'auf dem Stick geändert'; L = @{ a = 2, 200 }; N = @{ a = 1, 100 }; B = @{ a = 1, 100, 1, 100 }; Aktion = 'NachNas' }
        @{ Fall = 'auf dem NAS geändert'; L = @{ a = 1, 100 }; N = @{ a = 2, 200 }; B = @{ a = 1, 100, 1, 100 }; Aktion = 'VomNas' }
        @{ Fall = 'beide geändert, Stick neuer'; L = @{ a = 3, 300 }; N = @{ a = 2, 200 }; B = @{ a = 1, 100, 1, 100 }; Aktion = 'KonfliktNachNas' }
        @{ Fall = 'beide geändert, NAS neuer'; L = @{ a = 3, 300 }; N = @{ a = 2, 400 }; B = @{ a = 1, 100, 1, 100 }; Aktion = 'KonfliktVomNas' }
        @{ Fall = 'erster Abgleich, verschieden, NAS neuer'; L = @{ a = 3, 300 }; N = @{ a = 2, 400 }; B = @{}; Aktion = 'KonfliktVomNas' }
        @{ Fall = 'seit dem letzten Abgleich auf beiden Seiten unverändert'; L = @{ a = 1, 100 }; N = @{ a = 1, 500 }; B = @{ a = 1, 100, 1, 500 }; Aktion = 'Gleich' }
        @{ Fall = 'auf beiden Seiten gelöscht'; L = @{}; N = @{}; B = @{ a = 1, 100, 1, 100 }; Aktion = 'Vergessen' }
        @{ Fall = 'Stick um eine Stunde verschoben (Sommerzeit auf FAT), NAS gelöscht'; L = @{ a = 1, 3700 }; N = @{}; B = @{ a = 1, 100, 1, 100 }; Aktion = 'LoeschenLokal' }
        @{ Fall = 'beide Seiten um zwei Stunden versetzt: gleich'; L = @{ a = 1, 100 }; N = @{ a = 1, 7300 }; B = @{}; Aktion = 'Gleich' }
        @{ Fall = 'halbe Stunde versetzt ist eine Änderung'; L = @{ a = 1, 1900 }; N = @{ a = 1, 100 }; B = @{ a = 1, 100, 1, 100 }; Aktion = 'NachNas' }
    ) {
        $p = @(MinibenchTest\Get-AbgleichPlan (New-Bestand $L) (New-Bestand $N) (New-Stand $B))
        $p.Count | Should -Be 1
        $p[0].Rel | Should -Be 'a'
        $p[0].Aktion | Should -Be $Aktion
    }
}

Describe 'Abgleich mit dem Netzlaufwerk' {
    BeforeEach { Mock -ModuleName MinibenchTest Test-NasPfad { '' } }

    It 'der erste Abgleich vereinigt beide Seiten, Werkzeuge und Einstellungen bleiben auf dem Stick' {
        $l = New-TestDir 'stick'; $n = New-TestDir 'nas'
        Set-Datei $l 'Datenbank\PC1.json' 'PC1' | Out-Null
        Set-Datei $l 'Berichte\PC1_20261003_1421\Diagnosebericht.txt' 'Bericht' | Out-Null
        Set-Datei $l 'Berichte\Dashboard.html' 'Dashboard' | Out-Null
        Set-Datei $l 'Tools\LibreHardwareMonitor\LibreHardwareMonitorLib.dll' 'dll' | Out-Null
        Set-Datei $l 'Laufzeit\PC1\checkpoint.json' '{}' | Out-Null
        Set-Datei $l 'Netzwerk.json' '{}' | Out-Null
        Set-Datei $l 'Einstellungen.json' '{}' | Out-Null
        Set-Datei $n 'Datenbank\PC2.json' 'PC2' | Out-Null
        Set-Datei $n 'Voreinstellungen.json' '{"a":1}' | Out-Null
        Set-Datei $n 'Änderungen\PC2\aenderung.json' '{}' | Out-Null
        $r = Invoke-TestAbgleich $l $n
        $r.Ok | Should -BeTrue
        $r.Erreichbar | Should -BeTrue
        $r.NachNas | Should -Be 2
        $r.VomNas | Should -Be 3
        Get-Inhalt $n 'Datenbank\PC1.json' | Should -Be 'PC1'
        Get-Inhalt $n 'Berichte\PC1_20261003_1421\Diagnosebericht.txt' | Should -Be 'Bericht'
        Get-Inhalt $l 'Datenbank\PC2.json' | Should -Be 'PC2'
        Get-Inhalt $l 'Voreinstellungen.json' | Should -Be '{"a":1}'
        Get-Inhalt $l 'Änderungen\PC2\aenderung.json' | Should -Be '{}'
        foreach ($x in 'Berichte\Dashboard.html', 'Tools\LibreHardwareMonitor\LibreHardwareMonitorLib.dll', 'Laufzeit\PC1\checkpoint.json', 'Netzwerk.json', 'Einstellungen.json') {
            Get-Pfad $n $x | Should -Not -Exist
        }
        Get-Pfad $l 'Abgleich\Stand.json' | Should -Exist
        [IO.File]::ReadAllText((Get-Pfad $l 'Abgleich\Abgleich.log')) | Should -Match '2 zum Netzlaufwerk, 3 auf den Stick'
        # Kopien tragen die Zeit des Originals
        [IO.File]::GetLastWriteTimeUtc((Get-Pfad $n 'Datenbank\PC1.json')) | Should -Be ([IO.File]::GetLastWriteTimeUtc((Get-Pfad $l 'Datenbank\PC1.json')))
    }
    It 'ein zweiter Abgleich ohne Änderungen tut nichts' {
        $p = New-Paar
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.Ok | Should -BeTrue
        ($r.NachNas + $r.VomNas + $r.GeloeschtLokal + $r.GeloeschtNas + $r.Konflikte) | Should -Be 0
    }
    It 'Änderungen gehen in die jeweils andere Richtung' {
        $p = New-Paar
        Set-Datei $p.L 'Datenbank\PC1_20261003_142535.json' '{"Name":"PC1 neu"}' -5 | Out-Null
        Set-Datei $p.N 'Datenbank\PC2_20261004_100000.json' '{"Name":"PC2 neu"}' -5 | Out-Null
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.NachNas | Should -Be 1
        $r.VomNas | Should -Be 1
        $r.Konflikte | Should -Be 0
        Get-Inhalt $p.N 'Datenbank\PC1_20261003_142535.json' | Should -Be '{"Name":"PC1 neu"}'
        Get-Inhalt $p.L 'Datenbank\PC2_20261004_100000.json' | Should -Be '{"Name":"PC2 neu"}'
    }
    It 'eine Löschung auf dem Stick verschiebt die Datei auf dem NAS ins Archiv' {
        $p = New-Paar
        Remove-Item -LiteralPath (Get-Pfad $p.L 'Berichte\PC1_20261003_1421') -Recurse -Force
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.GeloeschtNas | Should -Be 1
        Get-Pfad $p.N 'Berichte\PC1_20261003_1421\Diagnosebericht.txt' | Should -Not -Exist
        Get-Pfad $p.N 'Berichte\PC1_20261003_1421' | Should -Not -Exist
        @(Get-Archiv $p.N 'Geloescht' 'Berichte\PC1_20261003_1421\Diagnosebericht.txt').Count | Should -Be 1
        # und kommt beim nächsten Abgleich nicht zurück
        $r2 = Invoke-TestAbgleich $p.L $p.N
        $r2.VomNas | Should -Be 0
        Get-Pfad $p.L 'Berichte\PC1_20261003_1421' | Should -Not -Exist
    }
    It 'eine Löschung auf dem NAS verschiebt die Datei auf dem Stick ins Archiv' {
        $p = New-Paar
        Remove-Item -LiteralPath (Get-Pfad $p.N 'Datenbank\PC2_20261004_100000.json') -Force
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.GeloeschtLokal | Should -Be 1
        Get-Pfad $p.L 'Datenbank\PC2_20261004_100000.json' | Should -Not -Exist
        @(Get-Archiv $p.L 'Geloescht' 'Datenbank\PC2_20261004_100000.json').Count | Should -Be 1
    }
    It 'Konflikt: die neuere Fassung gilt auf beiden Seiten, die ältere liegt im Archiv ihrer Seite' {
        $p = New-Paar
        Set-Datei $p.L 'Datenbank\PC1_20261003_142535.json' '{"Name":"vom Stick, neuer"}' -2 | Out-Null
        Set-Datei $p.N 'Datenbank\PC1_20261003_142535.json' '{"Name":"vom NAS"}' -10 | Out-Null
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.Konflikte | Should -Be 1
        $r.Ok | Should -BeTrue
        Get-Inhalt $p.L 'Datenbank\PC1_20261003_142535.json' | Should -Be '{"Name":"vom Stick, neuer"}'
        Get-Inhalt $p.N 'Datenbank\PC1_20261003_142535.json' | Should -Be '{"Name":"vom Stick, neuer"}'
        $a = @(Get-Archiv $p.N 'Konflikte' 'Datenbank\PC1_20261003_142535.json')
        $a.Count | Should -Be 1
        [IO.File]::ReadAllText($a[0]) | Should -Be '{"Name":"vom NAS"}'
        ($r.Zeilen -join ' ') | Should -Match 'Konflikt'
    }
    It 'Konflikt in der anderen Richtung: NAS neuer' {
        $p = New-Paar
        Set-Datei $p.L 'Datenbank\PC2_20261004_100000.json' '{"Name":"Stick"}' -10 | Out-Null
        Set-Datei $p.N 'Datenbank\PC2_20261004_100000.json' '{"Name":"NAS, neuer"}' -2 | Out-Null
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.Konflikte | Should -Be 1
        Get-Inhalt $p.L 'Datenbank\PC2_20261004_100000.json' | Should -Be '{"Name":"NAS, neuer"}'
        [IO.File]::ReadAllText(@(Get-Archiv $p.L 'Konflikte' 'Datenbank\PC2_20261004_100000.json')[0]) | Should -Be '{"Name":"Stick"}'
    }
    It 'Änderung schlägt Löschung: auf dem Stick gelöscht, auf dem NAS geändert' {
        $p = New-Paar
        Remove-Item -LiteralPath (Get-Pfad $p.L 'Datenbank\PC2_20261004_100000.json') -Force
        Set-Datei $p.N 'Datenbank\PC2_20261004_100000.json' '{"Name":"PC2 geändert"}' -1 | Out-Null
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.VomNas | Should -Be 1
        $r.GeloeschtNas | Should -Be 0
        Get-Inhalt $p.L 'Datenbank\PC2_20261004_100000.json' | Should -Be '{"Name":"PC2 geändert"}'
    }
    It 'gleicher Inhalt mit anderer Zeit ist kein Konflikt, auch nicht beim nächsten Abgleich' {
        $l = New-TestDir 'stick'; $n = New-TestDir 'nas'
        Set-Datei $l 'Datenbank\PC1.json' 'gleich' -100 | Out-Null
        Set-Datei $n 'Datenbank\PC1.json' 'gleich' -10 | Out-Null
        $r = Invoke-TestAbgleich $l $n
        $r.Konflikte | Should -Be 0
        (Join-Path (Join-Path $l 'Archiv') 'Abgleich') | Should -Not -Exist
        (Join-Path (Join-Path $n 'Archiv') 'Abgleich') | Should -Not -Exist
        $r2 = Invoke-TestAbgleich $l $n
        ($r2.NachNas + $r2.VomNas + $r2.Konflikte) | Should -Be 0
    }
    It 'der Ordner eines laufenden Laufs wird nicht abgeglichen' {
        $l = New-TestDir 'stick'; $n = New-TestDir 'nas'
        $busy = Join-Path (Join-Path $l 'Berichte') 'PC1_20261009_1200'
        Set-Datei $l 'Berichte\PC1_20261009_1200\Diagnosebericht_teilweise.txt' 'läuft' | Out-Null
        Set-Datei $l 'Laufzeit\PC1\laufend.json' (@{ OutputDir = $busy } | ConvertTo-Json) | Out-Null
        Set-Datei $l 'Datenbank\PC1.json' 'PC1' | Out-Null
        $r = Invoke-TestAbgleich $l $n
        $r.NachNas | Should -Be 1
        Get-Pfad $n 'Berichte\PC1_20261009_1200' | Should -Not -Exist
    }
    It 'ein nicht erreichbares NAS ändert nichts' {
        $l = New-TestDir 'stick'
        Set-Datei $l 'Datenbank\PC1.json' 'PC1' | Out-Null
        $n = Join-Path (Join-Path $TestDrive 'gibt-es-nicht') 'Minibench'
        $r = Invoke-TestAbgleich $l $n
        $r.Erreichbar | Should -BeFalse
        $r.Ok | Should -BeFalse
        $r.Kurz | Should -Match 'nicht erreichbar'
        $n | Should -Not -Exist
        Get-Pfad $l 'Abgleich\Stand.json' | Should -Not -Exist
        Get-Inhalt $l 'Datenbank\PC1.json' | Should -Be 'PC1'
    }
    It 'fehlt nur der Ordner auf einer erreichbaren Freigabe, wird er angelegt' {
        $l = New-TestDir 'stick'
        Set-Datei $l 'Datenbank\PC1.json' 'PC1' | Out-Null
        $n = Join-Path (New-TestDir 'freigabe') 'MiniBench'
        $r = Invoke-TestAbgleich $l $n
        $r.Ok | Should -BeTrue
        Get-Inhalt $n 'Datenbank\PC1.json' | Should -Be 'PC1'
    }
    It 'ohne Netzwerk.json und ohne Pfad gleicht nichts ab' {
        $r = MinibenchTest\Invoke-Abgleich -DataDir (New-TestDir 'stick')
        $r.Ok | Should -BeFalse
        $r.Kurz | Should -Match 'kein Netzlaufwerk'
    }
    It 'ein Fehler bei einer Datei lässt deren alten Stand stehen; der nächste Abgleich versucht es erneut' {
        $p = New-Paar
        Set-Datei $p.L 'Berichte\PC1_20261003_1421\Diagnosebericht.txt' 'Bericht neu' -1 | Out-Null
        Mock -ModuleName MinibenchTest Copy-AbgleichDatei {
            New-Item -ItemType Directory -Path (Split-Path $Ziel -Parent) -Force | Out-Null
            [IO.File]::Copy($Quelle, $Ziel, $true); [IO.File]::SetLastWriteTimeUtc($Ziel, [IO.File]::GetLastWriteTimeUtc($Quelle))
        }
        Mock -ModuleName MinibenchTest Copy-AbgleichDatei { throw 'Zugriff verweigert' } -ParameterFilter { $Ziel -like '*Diagnosebericht.txt' }
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.Ok | Should -BeFalse
        $r.Fehler | Should -Be 1
        ($r.Zeilen -join ' ') | Should -Match 'Zugriff verweigert'
        Get-Inhalt $p.N 'Berichte\PC1_20261003_1421\Diagnosebericht.txt' | Should -Be 'Bericht PC1'
        $plan = @(MinibenchTest\Get-AbgleichPlan (MinibenchTest\Get-AbgleichBestand $p.L) (MinibenchTest\Get-AbgleichBestand $p.N) (MinibenchTest\Read-AbgleichStand $p.L $p.N))
        @($plan | Where-Object { $_.Rel -eq 'Berichte\PC1_20261003_1421\Diagnosebericht.txt' })[0].Aktion | Should -Be 'NachNas'
    }
    It 'nach einem Fehler in einem Berichtsordner folgen die Datenbankeinträge erst beim nächsten Abgleich' {
        $p = New-Paar
        Set-Datei $p.L 'Berichte\PC3_20261009_1000\Diagnosebericht.txt' 'B3' | Out-Null
        Set-Datei $p.L 'Berichte\PC3_20261009_1000\Rohdaten.txt' 'R3' | Out-Null
        Set-Datei $p.L 'Datenbank\PC3_20261009_100500.json' '{"Name":"PC3","Ordner":"Berichte\\PC3_20261009_1000"}' | Out-Null
        Set-Datei $p.L 'Datenbank\PC4_20261009_110000.json' '{"Name":"PC4","Ordner":"Berichte\\PC4_20261009_1100"}' | Out-Null
        Set-Datei $p.L 'Berichte\PC4_20261009_1100\Diagnosebericht.txt' 'B4' | Out-Null
        Mock -ModuleName MinibenchTest Copy-AbgleichDatei {
            New-Item -ItemType Directory -Path (Split-Path $Ziel -Parent) -Force | Out-Null
            [IO.File]::Copy($Quelle, $Ziel, $true); [IO.File]::SetLastWriteTimeUtc($Ziel, [IO.File]::GetLastWriteTimeUtc($Quelle))
        }
        Mock -ModuleName MinibenchTest Copy-AbgleichDatei { throw 'Datenträger voll' } -ParameterFilter { $Ziel -like '*Rohdaten.txt' }
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.Fehler | Should -Be 1
        $r.NachNas | Should -Be 3
        Get-Pfad $p.N 'Datenbank\PC3_20261009_100500.json' | Should -Not -Exist
        # ein Fehler in einem anderen Berichtsordner hält fremde Einträge nicht auf
        Get-Pfad $p.N 'Datenbank\PC4_20261009_110000.json' | Should -Exist
        ($r.Zeilen -join ' ') | Should -Match 'folgen beim nächsten Abgleich'
        # der halb kopierte Ordner gilt nicht als abgeglichen: verschwindet er auf dem Stick (Datenpflege), kommt er zurück
        (MinibenchTest\Read-AbgleichStand $p.L $p.N).ContainsKey('Berichte\PC3_20261009_1000\Diagnosebericht.txt') | Should -BeFalse
        Remove-Item -LiteralPath (Get-Pfad $p.L 'Berichte\PC3_20261009_1000') -Recurse -Force
        $plan = @(MinibenchTest\Get-AbgleichPlan (MinibenchTest\Get-AbgleichBestand $p.L) (MinibenchTest\Get-AbgleichBestand $p.N) (MinibenchTest\Read-AbgleichStand $p.L $p.N))
        @($plan | Where-Object { $_.Rel -eq 'Berichte\PC3_20261009_1000\Diagnosebericht.txt' })[0].Aktion | Should -Be 'VomNas'
    }
    It 'fehlt auf dem NAS ein ganzer Ordner, hält der Abgleich an; bestätigt geht es ins Archiv' {
        $l = New-TestDir 'stick'; $n = New-TestDir 'nas'
        1..12 | ForEach-Object { Set-Datei $l ('Datenbank\PC{0}.json' -f $_) 'x' | Out-Null }
        (Invoke-TestAbgleich $l $n).NachNas | Should -Be 12
        Remove-Item -LiteralPath (Join-Path $n 'Datenbank') -Recurse -Force
        $r = Invoke-TestAbgleich $l $n
        $r.Angehalten | Should -Match 'Ordner Datenbank'
        $r.Ok | Should -BeFalse
        $r.GeloeschtLokal | Should -Be 0
        @(Get-ChildItem -LiteralPath (Join-Path $l 'Datenbank')).Count | Should -Be 12
        [IO.File]::ReadAllText((Get-Pfad $l 'Abgleich\Abgleich.log')) | Should -Match 'angehalten'
        $r2 = MinibenchTest\Invoke-Abgleich -DataDir $l -NasPfad $n -LoeschenErlaubt
        $r2.GeloeschtLokal | Should -Be 12
        @(Get-Archiv $l 'Geloescht' 'Datenbank\PC1.json').Count | Should -Be 1
    }
    It 'wurde das NAS geleert, führt -Neu beide Seiten zusammen, ohne etwas zu entfernen' {
        $l = New-TestDir 'stick'; $n = New-TestDir 'nas'
        1..12 | ForEach-Object { Set-Datei $l ('Datenbank\PC{0}.json' -f $_) 'x' | Out-Null }
        $null = Invoke-TestAbgleich $l $n
        Remove-Item -LiteralPath $n -Recurse -Force
        (Invoke-TestAbgleich $l $n).Erreichbar | Should -BeFalse
        $r = MinibenchTest\Invoke-Abgleich -DataDir $l -NasPfad $n -Neu
        $r.Ok | Should -BeTrue
        $r.NachNas | Should -Be 12
        $r.GeloeschtLokal | Should -Be 0
        @(Get-ChildItem -LiteralPath (Join-Path $l 'Datenbank')).Count | Should -Be 12
    }
    It 'gleiche Größe, um eine Stunde versetzt, aber anderer Inhalt: die neuere Fassung gilt' {
        $l = New-TestDir 'stick'; $n = New-TestDir 'nas'
        Set-Datei $l 'Voreinstellungen.json' '{"a":true }' -70 | Out-Null
        Set-Datei $n 'Voreinstellungen.json' '{"a":false}' -10 | Out-Null
        $r = Invoke-TestAbgleich $l $n
        $r.Konflikte | Should -Be 1
        Get-Inhalt $l 'Voreinstellungen.json' | Should -Be '{"a":false}'
    }
    It 'fehlt der NAS-Ordner nach einem Abgleich (Freigabe nicht eingehängt), wird er nicht neu angelegt' {
        $p = New-Paar
        Rename-Item -LiteralPath $p.N -NewName ((Split-Path $p.N -Leaf) + '_weg')
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.Erreichbar | Should -BeFalse
        $p.N | Should -Not -Exist
        Get-Inhalt $p.L 'Datenbank\PC1_20261003_142535.json' | Should -Be '{"Name":"PC1"}'
    }
    It 'lässt sich eine Seite nicht vollständig lesen, wird nichts geändert' {
        $p = New-Paar
        Remove-Item -LiteralPath (Get-Pfad $p.N 'Datenbank\PC2_20261004_100000.json')
        Mock -ModuleName MinibenchTest Get-AbgleichBestand { throw ('{0} ist nicht vollständig lesbar: Zugriff verweigert' -f $Root) }
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.Ok | Should -BeFalse
        $r.Kurz | Should -Match 'nicht vollständig lesbar.*nichts geändert'
        Get-Pfad $p.L 'Datenbank\PC2_20261004_100000.json' | Should -Exist
        Join-Path $p.N 'Abgleich.lock' | Should -Not -Exist
    }
    It 'ein laufender Abgleich eines anderen Rechners sperrt; eine alte Sperre gilt als verwaist' {
        $p = New-Paar
        Set-Datei $p.L 'Datenbank\PC9.json' 'PC9' | Out-Null
        $lock = Join-Path $p.N 'Abgleich.lock'
        [IO.File]::WriteAllText($lock, 'ANDERER-PC 2026-10-09 10:00:00')
        $r = Invoke-TestAbgleich $p.L $p.N
        $r.Kurz | Should -Match 'anderer Abgleich.*ANDERER-PC'
        [IO.File]::ReadAllText($lock) | Should -Match 'ANDERER-PC'
        Get-Pfad $p.N 'Datenbank\PC9.json' | Should -Not -Exist
        $lock | Should -Exist
        [IO.File]::SetLastWriteTimeUtc($lock, [DateTime]::UtcNow.AddHours(-2))
        $r2 = Invoke-TestAbgleich $p.L $p.N
        $r2.Ok | Should -BeTrue
        Get-Pfad $p.N 'Datenbank\PC9.json' | Should -Exist
        $lock | Should -Not -Exist
    }
    It 'leere Ordner werden nur dort entfernt, wo der Abgleich etwas verschoben hat, nie bei laufenden Läufen' {
        $d = New-TestDir 'stick'
        foreach ($x in 'Berichte\PC1_A\Rohdaten', 'Berichte\PC1_B', 'Berichte\PC1_C') { New-Item -ItemType Directory -Path (Get-Pfad $d $x) -Force | Out-Null }
        $belegt = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        [void]$belegt.Add('Berichte\PC1_B')
        MinibenchTest\Remove-AbgleichLeereOrdner $d @('Berichte\PC1_A\Rohdaten\x.csv', 'Berichte\PC1_B\y.txt') $belegt
        Get-Pfad $d 'Berichte\PC1_A' | Should -Not -Exist
        Get-Pfad $d 'Berichte\PC1_B' | Should -Exist
        Get-Pfad $d 'Berichte\PC1_C' | Should -Exist
        Get-Pfad $d 'Berichte' | Should -Exist
    }
    It 'meldet den Fortschritt an die Oberfläche (@@ABGLEICH)' {
        Mock -ModuleName MinibenchTest Send-GuiEvent { }
        $l = New-TestDir 'stick'; $n = New-TestDir 'nas'
        1..25 | ForEach-Object { Set-Datei $l ('Datenbank\PC{0}.json' -f $_) 'x' | Out-Null }
        $r = Invoke-TestAbgleich $l $n
        $r.NachNas | Should -Be 25
        Should -Invoke -ModuleName MinibenchTest Send-GuiEvent -Times 2 -Exactly -ParameterFilter { $Kind -eq 'ABGLEICH' }
    }
    It 'ein Stand zu einem anderen NAS-Pfad gilt nicht (erster Abgleich mit dem neuen Ziel)' {
        $p = New-Paar
        $stand = MinibenchTest\Read-AbgleichStand $p.L $p.N
        $stand.Count | Should -BeGreaterThan 0
        (MinibenchTest\Read-AbgleichStand $p.L (Join-Path $TestDrive 'anderes')).Count | Should -Be 0
    }
}

Describe 'Läufe entfernen und umbenennen' {
    BeforeAll {
        # Datenordner mit einem Lauf: Datenbankeintrag, Berichtsordner, Änderungsprotokoll mit Verweis auf den Bericht
        function New-Lauf([string]$Root = '', [string]$Name = 'PC1', [string]$Stamp = '20261003_142535', [string]$Ordner = 'PC1_20261003_1421') {
            if (-not $Root) { $Root = New-TestDir 'daten' }
            $db = Join-Path $Root 'Datenbank'; New-Item -ItemType Directory $db -Force | Out-Null
            $rep = Join-Path (Join-Path $Root 'Berichte') $Ordner
            New-Item -ItemType Directory $rep -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $rep 'Diagnosebericht.txt'), 'Bericht')
            $json = Join-Path $db ('{0}_{1}.json' -f $Name, $Stamp)
            [IO.File]::WriteAllText($json, ([ordered]@{ Format = 'PC-Diagnose-DB/2'; Name = $Name; Computer = 'PC1'; Ordner = 'Berichte\' + $Ordner; Werte = @{ 'CPU|MT' = 1000 } } | ConvertTo-Json -Depth 4))
            $ae = Join-Path (Join-Path $Root 'Änderungen') 'PC1'; New-Item -ItemType Directory $ae -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $ae ('Aenderungen_{0}.json' -f $Stamp)), ([ordered]@{ Bericht = $rep; Eintraege = @() } | ConvertTo-Json))
            return [pscustomobject]@{ Root = $Root; Json = $json; Ordner = $rep }
        }
    }
    It 'Entfernen verschiebt Eintrag und Berichtsordner nach Archiv\Entfernt' {
        $x = New-Lauf
        $r = MinibenchTest\Remove-DbLauf @($x.Json) $x.Root
        $r.Entfernt | Should -Be 1
        $r.Fehler | Should -Be 0
        $x.Json | Should -Not -Exist
        $x.Ordner | Should -Not -Exist
        Join-Path (Join-Path $r.Archiv 'Datenbank') (Split-Path $x.Json -Leaf) | Should -Exist
        Join-Path (Join-Path (Join-Path $r.Archiv 'Berichte') 'PC1_20261003_1421') 'Diagnosebericht.txt' | Should -Exist
        $r.Archiv.StartsWith((Join-Path (Join-Path $x.Root 'Archiv') 'Entfernt')) | Should -BeTrue
    }
    It 'Entfernen mehrerer Einträge; ein Eintrag ohne Berichtsordner geht allein ins Archiv' {
        $x = New-Lauf
        $y = New-Lauf -Root $x.Root -Name 'PC2' -Stamp '20261004_100000' -Ordner 'PC2_20261004_1000'
        Remove-Item -LiteralPath $y.Ordner -Recurse -Force
        $r = MinibenchTest\Remove-DbLauf @($x.Json, $y.Json) $x.Root
        $r.Entfernt | Should -Be 2
        $y.Json | Should -Not -Exist
    }
    It 'Entfernen lässt fremde Ordner und Dateien außerhalb der Datenbank unberührt' {
        $x = New-Lauf
        $fremd = New-TestDir 'fremd'
        [IO.File]::WriteAllText($x.Json, (@{ Name = 'PC1'; Ordner = $fremd } | ConvertTo-Json))
        $draussen = Join-Path $fremd 'irgendwas.json'; [IO.File]::WriteAllText($draussen, '{}')
        $r = MinibenchTest\Remove-DbLauf @($x.Json, $draussen) $x.Root
        $r.Entfernt | Should -Be 1
        $r.Fehler | Should -Be 1
        $fremd | Should -Exist
        $draussen | Should -Exist
    }
    It 'Entfernen überspringt einen Lauf, der noch läuft' {
        $x = New-Lauf
        $lz = Join-Path (Join-Path $x.Root 'Laufzeit') 'PC1'; New-Item -ItemType Directory $lz -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $lz 'laufend.json'), (@{ OutputDir = $x.Ordner } | ConvertTo-Json))
        $r = MinibenchTest\Remove-DbLauf @($x.Json) $x.Root
        $r.Entfernt | Should -Be 0
        $r.Fehler | Should -Be 1
        $x.Json | Should -Exist
        $x.Ordner | Should -Exist
    }
    It 'Umbenennen ändert Name, Dateiname, Berichtsordner und den Verweis im Änderungsprotokoll' {
        $x = New-Lauf
        $r = MinibenchTest\Rename-DbLauf $x.Json 'Büro PC Max' $x.Root
        $r.Ok | Should -BeTrue
        Split-Path $r.Pfad -Leaf | Should -Be 'Büro_PC_Max_20261003_142535.json'
        Split-Path $r.Ordner -Leaf | Should -Be 'Büro_PC_Max_20261003_1421'
        $x.Json | Should -Not -Exist
        $x.Ordner | Should -Not -Exist
        Join-Path $r.Ordner 'Diagnosebericht.txt' | Should -Exist
        $e = Get-Content -LiteralPath $r.Pfad -Raw -Encoding UTF8 | ConvertFrom-Json
        $e.Name | Should -Be 'Büro PC Max'
        $e.Computer | Should -Be 'PC1'
        $e.Ordner | Should -Be 'Berichte\Büro_PC_Max_20261003_1421'
        $e.Werte.'CPU|MT' | Should -Be 1000
        $ae = @(Get-ChildItem -LiteralPath (Join-Path $x.Root 'Änderungen') -Filter '*.json' -Recurse)[0].FullName
        (Get-Content -LiteralPath $ae -Raw -Encoding UTF8 | ConvertFrom-Json).Bericht | Should -Be $r.Ordner
    }
    It 'Umbenennen entfernt Zeichen, die in Dateinamen und in der Liste für -Entfernen stören' {
        $x = New-Lauf
        $r = MinibenchTest\Rename-DbLauf $x.Json 'a/b:c;d*e' $x.Root
        $r.Ok | Should -BeTrue
        Split-Path $r.Pfad -Leaf | Should -Be 'a_b_c_d_e_20261003_142535.json'
        (Get-Content -LiteralPath $r.Pfad -Raw -Encoding UTF8 | ConvertFrom-Json).Name | Should -Be 'a/b:c;d*e'
        $r2 = MinibenchTest\Rename-DbLauf $r.Pfad "Leo's PC & [Test]" $x.Root
        Split-Path $r2.Pfad -Leaf | Should -Be 'Leo_s_PC_Test_20261003_142535.json'
    }
    It 'Umbenennen auf einen vorhandenen Namen hängt _2 an und überschreibt nichts' {
        $x = New-Lauf
        $y = New-Lauf -Root $x.Root -Name 'Neu' -Stamp '20261003_142535' -Ordner 'Neu_20261003_1421'
        $r = MinibenchTest\Rename-DbLauf $x.Json 'Neu' $x.Root
        $r.Ok | Should -BeTrue
        Split-Path $r.Pfad -Leaf | Should -Be 'Neu_20261003_142535_2.json'
        Split-Path $r.Ordner -Leaf | Should -Be 'Neu_20261003_1421_2'
        $y.Json | Should -Exist
        $y.Ordner | Should -Exist
    }
    It 'Umbenennen führt Verweise mit anderem Laufwerk nach und speichert den Ordner relativ' {
        $x = New-Lauf
        $ae = @(Get-ChildItem -LiteralPath (Join-Path $x.Root 'Änderungen') -Filter '*.json' -Recurse)[0].FullName
        [IO.File]::WriteAllText($ae, (@{ Bericht = 'E:\Minibench-Daten\Berichte\PC1_20261003_1421'; Eintraege = @() } | ConvertTo-Json))
        [IO.File]::WriteAllText($x.Json, (@{ Name = 'PC1'; Computer = 'PC1'; Ordner = $x.Ordner } | ConvertTo-Json))
        $r = MinibenchTest\Rename-DbLauf $x.Json 'Neu' $x.Root
        $r.Ok | Should -BeTrue
        (Get-Content -LiteralPath $ae -Raw -Encoding UTF8 | ConvertFrom-Json).Bericht | Should -Be 'E:\Minibench-Daten\Berichte\Neu_20261003_1421'
        (Get-Content -LiteralPath $r.Pfad -Raw -Encoding UTF8 | ConvertFrom-Json).Ordner | Should -Be 'Berichte\Neu_20261003_1421'
    }
    It 'zweimal Umbenennen bei Namensgleichheit: der Zähler wächst nicht an' {
        $x = New-Lauf
        $null = New-Lauf -Root $x.Root -Name 'Neu' -Stamp '20261003_142535' -Ordner 'Neu_20261003_1421'
        $r = MinibenchTest\Rename-DbLauf $x.Json 'Neu' $x.Root
        Split-Path $r.Pfad -Leaf | Should -Be 'Neu_20261003_142535_2.json'
        $r2 = MinibenchTest\Rename-DbLauf $r.Pfad 'Anders' $x.Root
        Split-Path $r2.Pfad -Leaf | Should -Be 'Anders_20261003_142535.json'
        Split-Path $r2.Ordner -Leaf | Should -Be 'Anders_20261003_1421'
    }
    It 'Umbenennen auf denselben Namen ändert keine Dateinamen' {
        $x = New-Lauf
        $r = MinibenchTest\Rename-DbLauf $x.Json 'PC1' $x.Root
        $r.Ok | Should -BeTrue
        $r.Pfad | Should -Be $x.Json
        $r.Ordner | Should -Be $x.Ordner
    }
    It 'Umbenennen ohne Namen oder außerhalb der Datenbank wird abgelehnt' {
        $x = New-Lauf
        (MinibenchTest\Rename-DbLauf $x.Json '   ' $x.Root).Ok | Should -BeFalse
        $draussen = Join-Path (New-TestDir 'fremd') 'x.json'; [IO.File]::WriteAllText($draussen, '{}')
        (MinibenchTest\Rename-DbLauf $draussen 'Neu' $x.Root).Ok | Should -BeFalse
        $x.Json | Should -Exist
    }
}
