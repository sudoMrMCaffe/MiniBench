# Ablaufsteuerung eines Laufs: Abschnitte (Invoke-Section) und Überspringen per skip.flag, schneller Modus
# (Hintergrundaufgaben aus Kern\Parallel.ps1), lokaler Arbeitsordner, gedrosselte Checkpoints und Zwischenstände,
# abgebrochene Läufe und die Rückstandskontrolle am Laufende.
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Parts 'Kern\Parallel.ps1' `
        -Functions 'Invoke-Section', 'Test-SkipRequested', 'Send-StepSkipped', 'Add-Line', 'New-RunWorkDir', 'Restore-StaleWorkDirs', 'Get-WriteDelta',
                   'Write-Checkpoint', 'Flush-Checkpoint', 'Write-Durable', 'Save-Partial', 'Get-BugcheckName', 'Test-MemoryBugcheck', 'Test-TempEntryStale', 'Invoke-ResidueCheck' `
        -Setup @'
$script:Report = New-Object System.Text.StringBuilder
$script:Findings = New-Object System.Collections.Generic.List[object]
$script:Tests = New-Object System.Collections.Generic.List[object]
$script:Timings = New-Object System.Collections.Generic.List[object]
$script:SectionErrors = New-Object System.Collections.Generic.List[object]
$script:Events = New-Object System.Collections.Generic.List[string]
$script:StepNo = 0
$script:CpDir = ''
$script:CpStream = $null
$script:CpBuffer = New-Object System.Text.StringBuilder
$script:CpLastFlush = [datetime]::MinValue
$script:CpWrites = 0
$script:PartialLast = [datetime]::MinValue
$script:PartialWrites = 0
$script:CpCurrent = 'Test'
$script:OptDduDir = 'LeosMinibench-DDU'
$script:StaleWorkNotes = @()
function Send-GuiEvent { param([string]$Kind, [Parameter(ValueFromRemainingArguments = $true)][object[]]$Parts) $script:Events.Add(($Kind + '|' + (@($Parts) -join '|'))) }
function Add-Finding { param([string]$Level, [string]$Area, [string]$Text) $script:Findings.Add([pscustomobject]@{ Stufe = $Level; Bereich = $Area; Befund = $Text }) }
function Add-TestResult { param([string]$Name, [string]$Status, [string]$Detail = '') $script:Tests.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail }) }
function Add-Section { param([string]$Title, [string]$Prefix = '') }
function Get-PlannedSteps { 10 }
function Show-Overall { param([string]$Status) }
function Show-Sub { param($Activity, $Status, $Percent) }
function Hide-Sub { }
function Write-Step { param([string]$Text) }
function Write-Warning { param([Parameter(Position = 0)][string]$Message) }
function Get-PawnIoMarker { '' }
function Test-OptDduPending { $false }
function Test-OptMaintenanceTasksPresent { $false }
function Test-KeptTool { param([string]$Name) $false }
'@
    # Zustand eines Laufs zurücksetzen (Ereignisse, Tests, Befunde, Bericht, Laufzeitordner)
    function Reset-Lauf {
        & (Get-Module MinibenchTest) {
            $script:Events.Clear(); $script:Tests.Clear(); $script:Findings.Clear(); $script:SectionErrors.Clear(); $script:Timings.Clear()
            [void]$script:Report.Clear(); $script:StepNo = 0; $script:CpDir = ''
        }
    }
    # Laufzeitordner (CpDir) in TestDrive, auf Wunsch mit skip.flag
    function New-CpDir([switch]$MitFlag) {
        $d = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d | Out-Null
        if ($MitFlag) { [IO.File]::WriteAllText((Join-Path $d 'skip.flag'), '1') }
        Set-ModuleVar 'CpDir' $d
        return $d
    }
    # Umgebungsvariablen nur für die Dauer eines Blocks setzen (z. B. TEMP auf einen Ordner in TestDrive)
    function Invoke-MitUmgebung([hashtable]$Werte, [scriptblock]$Block) {
        $alt = @{}
        foreach ($k in $Werte.Keys) { $alt[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, [string]$Werte[$k]) }
        try { & $Block } finally { foreach ($k in $alt.Keys) { [Environment]::SetEnvironmentVariable($k, $alt[$k]) } }
    }
    # eigenes TEMP in TestDrive: der gemeinsame Ordner %TEMP%\LeosMinibench des Rechners bleibt unberührt
    function New-TempRoot {
        $t = Join-Path $TestDrive ('tmp_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $t | Out-Null
        return $t
    }
    function Get-TempEnv([string]$Temp) { return @{ TMP = $Temp; TEMP = $Temp; TMPDIR = $Temp } }
}

Describe 'Abschnitte und Überspringen' {
    BeforeEach { Reset-Lauf }
    It 'meldet der Oberfläche, ob <Titel> übersprungen werden darf (<Erwartet>)' -ForEach @(
        @{ Titel = 'Langwieriger Schritt'; Schalter = $true; Erwartet = '1' }
        @{ Titel = 'Updates'; Schalter = $false; Erwartet = '1' }
        @{ Titel = 'Kritische Systemerkennung'; Schalter = $false; Erwartet = '0' }
    ) {
        MinibenchTest\Invoke-Section -Title $Titel -Skippable:$Schalter { }
        $ev = @(Get-ModuleVar 'Events' | Where-Object { $_ -like 'SKIP_ALLOWED|*' })
        $ev[0] | Should -Be ('SKIP_ALLOWED|' + $Erwartet)
        # am Ende jedes Abschnitts wird der Knopf wieder gesperrt
        $ev[-1] | Should -Be 'SKIP_ALLOWED|0'
    }
    It 'skip.flag wird erkannt und dabei gelöscht' {
        $cp = New-CpDir
        MinibenchTest\Test-SkipRequested | Should -BeFalse
        [IO.File]::WriteAllText((Join-Path $cp 'skip.flag'), '1')
        MinibenchTest\Test-SkipRequested | Should -BeTrue
        Join-Path $cp 'skip.flag' | Should -Not -Exist
        MinibenchTest\Test-SkipRequested | Should -BeFalse
    }
    It 'ohne Laufzeitordner gibt es kein Überspringen' {
        Set-ModuleVar 'CpDir' ''
        MinibenchTest\Test-SkipRequested | Should -BeFalse
    }
    It 'überspringt einen überspringbaren Abschnitt bei skip.flag, ohne seinen Inhalt auszuführen' {
        $null = New-CpDir -MitFlag
        $script:inhaltLief = $false
        { MinibenchTest\Invoke-Section -Title 'Updates' -Skippable { $script:inhaltLief = $true; throw 'darf nicht laufen' } } | Should -Not -Throw
        $script:inhaltLief | Should -BeFalse
        $t = @(Get-ModuleVar 'Tests')
        $t.Count | Should -Be 1
        $t[0].Status | Should -Match 'BERSPRUNGEN'
        @(Get-ModuleVar 'Events') | Should -Contain 'SCHRITT_UEBERSPRINGEN|Updates'
        @(Get-ModuleVar 'Findings' | Where-Object { $_.Stufe -eq 'INFO' -and $_.Befund -match 'Benutzeranforderung' }).Count | Should -Be 1
        @(Get-ModuleVar 'SectionErrors').Count | Should -Be 0
    }
    It 'ignoriert skip.flag bei nicht überspringbaren Abschnitten und lässt die Anforderung stehen' {
        $cp = New-CpDir -MitFlag
        $script:inhaltLief = $false
        MinibenchTest\Invoke-Section -Title 'Hardware-Erkennung' { $script:inhaltLief = $true }
        $script:inhaltLief | Should -BeTrue
        Join-Path $cp 'skip.flag' | Should -Exist
        @(Get-ModuleVar 'Tests').Count | Should -Be 0
    }
    It 'ein Abbruch im Inhalt eines überspringbaren Abschnitts zählt als übersprungen, nicht als Skriptfehler' {
        MinibenchTest\Invoke-Section -Title 'Benchmark: Grafik' { throw (New-Object System.OperationCanceledException) }
        @(Get-ModuleVar 'SectionErrors').Count | Should -Be 0
        @(Get-ModuleVar 'Tests')[0].Status | Should -Match 'BERSPRUNGEN'
        @(Get-ModuleVar 'Findings' | Where-Object { $_.Stufe -eq 'WARNUNG' }).Count | Should -Be 0
    }
    It 'ein Skriptfehler in einem Abschnitt wird gesammelt und bricht den Lauf nicht ab' {
        { MinibenchTest\Invoke-Section -Title 'Ereignisprotokolle' { throw 'kaputt' } } | Should -Not -Throw
        $e = @(Get-ModuleVar 'SectionErrors')
        $e.Count | Should -Be 1
        $e[0].Meldung | Should -Be 'kaputt'
        @(Get-ModuleVar 'Timings').Count | Should -Be 1
    }
}

Describe 'Schneller Modus: Ablaufsteuerung' {
    It 'Abschnittstitel <T> gehört zum Schritt <K>' -ForEach @(
        @{ T = 'Test: Arbeitsspeicher (Mustertest)'; K = 'RamTest' }, @{ T = 'Energie'; K = 'Energieanalyse' }
        @{ T = 'Benchmark: Grafik'; K = 'Messung' }, @{ T = 'Lasttest (CPU 5 Min.)'; K = 'Messung' }, @{ T = 'Prozessor'; K = '' }, @{ T = 'Updates'; K = 'Updatesuche' }
    ) {
        MinibenchTest\Get-SectionStepKey $T | Should -Be $K
    }
    It 'Abhängigkeiten, die in diesem Lauf nicht vorkommen, gelten als erfüllt' {
        & (Get-Module MinibenchTest) { $script:Opt = @{ Defender = $true; Energieanalyse = $true }; $script:DefenderActive = $false }
        @(MinibenchTest\Get-ActiveDeps @('Defender')).Count | Should -Be 0
        & (Get-Module MinibenchTest) { $script:DefenderActive = $true }
        @(MinibenchTest\Get-ActiveDeps @('Defender')) | Should -Be @('Defender')
    }
    It 'Hintergrundaufgaben laufen parallel, Abhängigkeiten warten, die Sperre wartet auf alle' {
        & (Get-Module MinibenchTest) {
            $script:FastMode = $true; $script:BgJobs = [ordered]@{}; $script:BgDone.Clear()
            [void](Register-BgJob -Key 'A' -Title 'Aufgabe A' -Script { Start-Sleep -Milliseconds 600; 'a' })
            [void](Register-BgJob -Key 'B' -Title 'Aufgabe B' -Nach @('A') -Script { 'b' })
            [void](Register-BgJob -Key 'C' -Title 'Aufgabe C' -Script { param($x) $x * 2 } -Arguments @(21))
        }
        $jobs = Get-ModuleVar 'BgJobs'
        $jobs['A'].Status | Should -Be 'läuft'
        $jobs['B'].Status | Should -Be 'wartet'
        & (Get-Module MinibenchTest) { Wait-BgAll 'den Test' }
        $jobs['A'].Status | Should -Be 'fertig'; $jobs['B'].Status | Should -Be 'fertig'; $jobs['C'].Status | Should -Be 'fertig'
        $jobs['C'].Ergebnis | Should -Be 42
        $jobs['B'].Start | Should -BeGreaterOrEqual $jobs['A'].Ende
        & (Get-Module MinibenchTest) { Stop-BgJobs; $script:FastMode = $false; $script:BgJobs = [ordered]@{} }
    }
    It 'Fehler einer Hintergrundaufgabe brechen nichts ab' {
        & (Get-Module MinibenchTest) {
            $script:FastMode = $true; $script:BgJobs = [ordered]@{}; $script:BgDone.Clear()
            [void](Register-BgJob -Key 'X' -Title 'kaputt' -Script { throw 'geht nicht' })
            $script:XJob = Wait-BgJob 'X' '' 30
            Stop-BgJobs; $script:FastMode = $false; $script:BgJobs = [ordered]@{}
        }
        $j = Get-ModuleVar 'XJob'
        $j.Status | Should -Be 'Fehler'; $j.Fehler | Should -Match 'geht nicht'
        MinibenchTest\Get-BgNote $j | Should -Match 'Meldung: .*geht nicht'
    }
    It 'ohne schnellen Modus wird nichts angemeldet' {
        & (Get-Module MinibenchTest) { $script:FastMode = $false; $script:BgJobs = [ordered]@{}; $script:Reg = Register-BgJob -Key 'Y' -Title 'y' -Script { 1 } }
        Get-ModuleVar 'Reg' | Should -BeFalse
        (Get-ModuleVar 'BgJobs').Count | Should -Be 0
    }
    It 'Warten auf eine Aufgabe endet bei skip.flag sofort, ohne die Aufgabe abzuwarten, und ruft OnDone auf' {
        # Stop-BgJob stößt das Ende nur an (BeginStop), sonst blockiert eine hängende Aufgabe den ganzen Lauf
        $cp = New-CpDir
        & (Get-Module MinibenchTest) {
            $script:FastMode = $true; $script:BgJobs = [ordered]@{}; $script:BgDone.Clear(); $script:OnDoneLief = $false
            [void](Register-BgJob -Key 'Lang' -Title 'lange Aufgabe' -Script { Start-Sleep -Seconds 20; 'fertig' } -OnDone { $script:OnDoneLief = $true })
        }
        [IO.File]::WriteAllText((Join-Path $cp 'skip.flag'), '1')
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & (Get-Module MinibenchTest) { $script:LangJob = Wait-BgJob 'Lang' '' 60 }
        $sw.Stop()
        try {
            $j = Get-ModuleVar 'LangJob'
            $j.Status | Should -Be 'abgebrochen'
            $j.Fehler | Should -Match 'übersprungen'
            Get-ModuleVar 'OnDoneLief' | Should -BeTrue
            $sw.Elapsed.TotalSeconds | Should -BeLessThan 10
            Join-Path $cp 'skip.flag' | Should -Not -Exist
        } finally {
            & (Get-Module MinibenchTest) { Stop-BgJobs; $script:FastMode = $false; $script:BgJobs = [ordered]@{}; $script:CpDir = '' }
        }
    }
}

Describe 'Lokaler Arbeitsordner und abgebrochene Läufe' {
    It 'legt den Arbeitsordner im lokalen TEMP an und vermerkt den Berichtsordner in Ziel.txt' {
        $tmp = New-TempRoot
        $d = Invoke-MitUmgebung (Get-TempEnv $tmp) { MinibenchTest\New-RunWorkDir 'X:\Berichte\PC_1' }
        $d | Should -Match 'LeosMinibench[\\/]Lauf_\d+$'
        Join-Path $tmp ('LeosMinibench/Lauf_{0}/Anhang' -f $PID) | Should -Exist
        [IO.File]::ReadAllText((Join-Path $d 'Ziel.txt')) | Should -Be 'X:\Berichte\PC_1'
    }
    It 'sichert die Rohdaten eines abgebrochenen Laufs in seinen Berichtsordner und entfernt den Arbeitsordner' {
        $tmp = New-TempRoot
        $dead = Join-Path $tmp 'LeosMinibench/Lauf_999999'
        $tgt = Join-Path $TestDrive ('Bericht_alt_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $dead 'Anhang'), $tgt -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dead 'Ziel.txt'), $tgt)
        [IO.File]::WriteAllText((Join-Path $dead 'Anhang/Konsole.log'), 'abgebrochen')
        $n = @(Invoke-MitUmgebung (Get-TempEnv $tmp) { MinibenchTest\Restore-StaleWorkDirs })
        ($n -join ' ') | Should -Match 'Arbeitsordner eines abgebrochenen Laufs entfernt'
        $dead | Should -Not -Exist
        Join-Path $tgt 'Anhang_unterbrochen.zip' | Should -Exist
    }
    It 'fehlt der Berichtsordner des abgebrochenen Laufs, gehen die Rohdaten in den aktuellen Berichtsordner' {
        $tmp = New-TempRoot
        $dead = Join-Path $tmp 'LeosMinibench/Lauf_999998'
        $now = Join-Path $TestDrive ('Bericht_neu_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $dead 'Anhang'), $now -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dead 'Ziel.txt'), (Join-Path $TestDrive 'gibt_es_nicht'))
        [IO.File]::WriteAllText((Join-Path $dead 'Anhang/Konsole.log'), 'abgebrochen')
        $n = @(Invoke-MitUmgebung (Get-TempEnv $tmp) { MinibenchTest\Restore-StaleWorkDirs $now })
        ($n -join ' ') | Should -Match 'nicht erreichbar'
        $dead | Should -Not -Exist
        Join-Path $now 'Anhang_unterbrochen_999998.zip' | Should -Exist
    }
    It 'ohne erreichbaren Berichtsordner bleibt der Arbeitsordner mit seinen Rohdaten erhalten' {
        $tmp = New-TempRoot
        $dead = Join-Path $tmp 'LeosMinibench/Lauf_999997'
        New-Item -ItemType Directory -Path (Join-Path $dead 'Anhang') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dead 'Ziel.txt'), (Join-Path $TestDrive 'gibt_es_nicht'))
        [IO.File]::WriteAllText((Join-Path $dead 'Anhang/Konsole.log'), 'abgebrochen')
        $n = @(Invoke-MitUmgebung (Get-TempEnv $tmp) { MinibenchTest\Restore-StaleWorkDirs '' })
        ($n -join ' ') | Should -Match 'behalten.*nicht entfernbar'
        Join-Path $dead 'Anhang/Konsole.log' | Should -Exist
    }
    It 'der Arbeitsordner des eigenen Prozesses bleibt unangetastet' {
        $tmp = New-TempRoot
        $own = Join-Path $tmp ('LeosMinibench/Lauf_{0}' -f $PID)
        New-Item -ItemType Directory -Path (Join-Path $own 'Anhang') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $own 'Anhang/Konsole.log'), 'läuft')
        @(Invoke-MitUmgebung (Get-TempEnv $tmp) { MinibenchTest\Restore-StaleWorkDirs }).Count | Should -Be 0
        Join-Path $own 'Anhang/Konsole.log' | Should -Exist
    }
    It 'Stoppcodes ab 0x80000000 führen nicht zum Abbruch der Absturzanalyse' {
        { MinibenchTest\Get-BugcheckName ([int64]0xDEADDEAD) } | Should -Not -Throw
        MinibenchTest\Get-BugcheckName ([int64]0xC000021A) | Should -Match 'nachschlagen'
        MinibenchTest\Test-MemoryBugcheck ([int64]0xDEADDEAD) | Should -BeFalse
    }
}

Describe 'Stick schonen: gedrosselte Schreibzugriffe' {
    It 'Unterschied der Schreibzähler (mit Überlauf des 32-Bit-Zählers)' {
        $t = Get-Date
        $a = [pscustomobject]@{ Laufwerk = 'E:'; Vorgaenge = 4294967000; Bytes = 1000; Art = 'Removable'; Zeit = $t }
        $b = [pscustomobject]@{ Laufwerk = 'E:'; Vorgaenge = 704; Bytes = 1000 + 10MB; Art = 'Removable'; Zeit = $t.AddSeconds(90) }
        $d = MinibenchTest\Get-WriteDelta $a $b
        $d.Vorgaenge | Should -Be 1000; $d.MB | Should -Be 10; $d.Sekunden | Should -Be 90; $d.Art | Should -Match 'USB-Stick'
        MinibenchTest\Get-WriteDelta $a $null | Should -BeNullOrEmpty
        $c = [pscustomobject]@{ Laufwerk = 'F:'; Vorgaenge = 1; Bytes = 1; Art = 'Fixed'; Zeit = $t }
        MinibenchTest\Get-WriteDelta $a $c | Should -BeNullOrEmpty
    }
    It 'Checkpoints: Pulse werden gesammelt, Schrittwechsel sofort geschrieben' {
        $f = Join-Path $TestDrive ('cp_' + [guid]::NewGuid().ToString('N') + '.log')
        # Lesen mit FileShare.ReadWrite: unter Windows hält der Checkpoint-Strom die Datei zum Schreiben offen
        $readShared = { param($p) $fs = New-Object IO.FileStream($p, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite); try { (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd() } finally { $fs.Dispose() } }
        & (Get-Module MinibenchTest) { param($p) $script:CpStream = New-Object IO.FileStream($p, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite); $script:CpWrites = 0; $script:CpLastFlush = Get-Date; [void]$script:CpBuffer.Clear() } $f
        try {
            MinibenchTest\Write-Checkpoint 'START' 'Abschnitt'
            MinibenchTest\Write-Checkpoint 'PULS' 'Wert 1'
            MinibenchTest\Write-Checkpoint 'PULS' 'Wert 2'
            $t1 = & $readShared $f
            $t1 | Should -Match 'START'; $t1 | Should -Not -Match 'Wert 1'
            MinibenchTest\Write-Checkpoint 'OK' 'Abschnitt'
            $t2 = & $readShared $f
            $t2 | Should -Match 'Wert 1'; $t2 | Should -Match 'Wert 2'; $t2 | Should -Match '\| OK '
            Get-ModuleVar 'CpWrites' | Should -Be 2
        } finally {
            # Strom immer schließen, sonst kann Pester TestDrive nicht löschen
            & (Get-Module MinibenchTest) { if ($script:CpStream) { $script:CpStream.Close(); $script:CpStream = $null } }
        }
    }
    It 'Zwischenstand höchstens einmal je Minute, mit -Force sofort' {
        $o = Join-Path $TestDrive ('out_' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $o -Force | Out-Null
        & (Get-Module MinibenchTest) { param($p) $script:OutputDir = $p; $script:PartialLast = [datetime]::MinValue; $script:PartialWrites = 0 } $o
        try {
            MinibenchTest\Save-Partial; MinibenchTest\Save-Partial; MinibenchTest\Save-Partial
            Get-ModuleVar 'PartialWrites' | Should -Be 1
            MinibenchTest\Save-Partial -Force
            Get-ModuleVar 'PartialWrites' | Should -Be 2
            Join-Path $o 'Diagnosebericht_teilweise.txt' | Should -Exist
        } finally { Set-ModuleVar 'OutputDir' '' }
    }
}

Describe 'Rückstandskontrolle' {
    It 'Eintrag <Name> im gemeinsamen TEMP-Ordner gilt als Rest: <Erwartet>' -ForEach @(
        @{ Name = 'Start_999999.log'; Erwartet = $true }
        @{ Name = 'LeosMinibench_999999.ps1'; Erwartet = $true }
        @{ Name = 'Last_999999_cpu_638950000000000000'; Erwartet = $true }
        # Arbeitsordner sichert Restore-StaleWorkDirs beim Start, die Rückstandskontrolle lässt sie stehen
        @{ Name = 'Lauf_999999'; Erwartet = $false }
        @{ Name = 'fremd.txt'; Erwartet = $false }
    ) {
        MinibenchTest\Test-TempEntryStale $Name | Should -Be $Erwartet
    }
    It 'Einträge des eigenen Prozesses gelten nie als Rest' {
        MinibenchTest\Test-TempEntryStale ('Start_{0}.log' -f $PID) | Should -BeFalse
        MinibenchTest\Test-TempEntryStale ('Last_{0}_ram_638950000000000000' -f $PID) | Should -BeFalse
    }
    It 'räumt Reste beendeter Läufe auf, löscht den gemeinsamen Ordner LeosMinibench im TEMP aber nie als Ganzes' {
        Reset-Lauf
        $root = Join-Path $TestDrive ('pc_' + [guid]::NewGuid().ToString('N'))
        $tmp = Join-Path $root 'Temp'
        $lm = Join-Path $tmp 'LeosMinibench'
        New-Item -ItemType Directory -Path (Join-Path $lm 'Lauf_999999') -Force | Out-Null
        foreach ($n in 'Start_999999.log', ('Start_{0}.log' -f $PID), 'fremd.txt') { [IO.File]::WriteAllText((Join-Path $lm $n), 'x') }
        [IO.File]::WriteAllText((Join-Path $tmp 'LeosMinibench_999999.ps1'), 'x')
        Mock -ModuleName MinibenchTest Get-Volume { }
        Set-ModuleVar 'DataDir' ''
        # alle Orte, die die Rückstandskontrolle durchsucht, liegen in TestDrive
        $envs = @{ TEMP = $tmp; windir = (Join-Path $root 'Windows'); SystemDrive = $root; ProgramData = (Join-Path $root 'ProgramData'); PUBLIC = (Join-Path $root 'Public') }
        Invoke-MitUmgebung $envs { MinibenchTest\Invoke-ResidueCheck }
        $lm | Should -Exist
        Join-Path $lm 'Start_999999.log' | Should -Not -Exist
        Join-Path $lm ('Start_{0}.log' -f $PID) | Should -Exist
        Join-Path $lm 'fremd.txt' | Should -Exist
        Join-Path $lm 'Lauf_999999' | Should -Exist
        Join-Path $tmp 'LeosMinibench_999999.ps1' | Should -Not -Exist
        $t = @(Get-ModuleVar 'Tests' | Where-Object { $_.Name -eq 'Rückstandskontrolle' })
        $t.Count | Should -Be 1
        $t[0].Status | Should -Be 'OK'
        $t[0].Detail | Should -Match '2 Reste entfernt'
    }
}
