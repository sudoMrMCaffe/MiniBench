# =====================================================================================
#                 SYSTEMÜBERSICHT (nur Benchmark oder Lasttest ohne Diagnose)
# =====================================================================================
if (($ModBench -or $ModLast) -and -not $ModDiag) {
    Invoke-Section 'Systemübersicht' {
        $cs   = Get-CimCached Win32_ComputerSystem
        $os   = Get-CimInstance Win32_OperatingSystem
        $bios = Get-CimCached Win32_BIOS
        $bb   = Get-CimCached Win32_BaseBoard
        $enc  = Get-CimCached Win32_SystemEnclosure
        $cv   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $cpus = @(Get-CimCached Win32_Processor)
        $mods = @(Get-CimCached Win32_PhysicalMemory)
        $pd   = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object { [int]$_.DeviceId })
        $gMain = Get-MainGpu
        $ii   = Get-WindowsInstallInfo; $script:InstallInfo = $ii
        $script:IsLaptop = [bool]($enc.ChassisTypes | Where-Object { $_ -in 8, 9, 10, 14, 30, 31, 32 })
        $script:LogicalCpus = ($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum
        $typeMap = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
        $total = ($mods | Measure-Object Capacity -Sum).Sum
        $typ0 = $(if ($mods.Count -and $typeMap.ContainsKey([int]$mods[0].SMBIOSMemoryType)) { $typeMap[[int]$mods[0].SMBIOSMemoryType] } else { '' })
        $spd0 = $(if ($mods.Count) { $(if ($mods[0].ConfiguredClockSpeed) { $mods[0].ConfiguredClockSpeed } else { $mods[0].Speed }) } else { 0 })

        $script:Facts['Computer']       = $env:COMPUTERNAME
        $script:Facts['System']         = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
        $script:Facts['Mainboard']      = ('{0} {1}' -f $bb.Manufacturer, $bb.Product).Trim()
        $script:Facts['Betriebssystem'] = ('{0} {1} (Build {2}.{3})' -f $os.Caption, $cv.DisplayVersion, $os.BuildNumber, $cv.UBR)
        if ($ii.Erstinstallation) { $script:Facts['Windows installiert'] = ('{0:dd.MM.yyyy} (vor {1}){2}' -f $ii.Erstinstallation, (Format-Age $ii.AlterTage -Dativ), $(if ($ii.Upgrades.Count) { ', seitdem {0} Funktionsupdate(s), zuletzt {1:dd.MM.yyyy}' -f $ii.Upgrades.Count, $ii.AktuellSeit } else { ', seitdem kein Funktionsupdate' })) }
        $script:Facts['BIOS/UEFI']      = ('{0} vom {1:dd.MM.yyyy}' -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
        $script:Facts['Prozessor']      = (($cpus | ForEach-Object { '{0} ({1} Kerne, {2} Threads)' -f $_.Name.Trim(), $_.NumberOfCores, $_.NumberOfLogicalProcessors }) -join '; ')
        if ($mods.Count) { $script:Facts['Arbeitsspeicher'] = ('{0} ({1}x {2} {3}, {4} MT/s)' -f (Format-Size $total), $mods.Count, (Format-Size $mods[0].Capacity), $typ0, $spd0) }
        $script:Facts['Grafik']         = $(try { Get-GpuFactText } catch { $(if ($gMain) { [string]$gMain.Name } else { '' }) })
        $script:Facts['Datenträger']    = (($pd | ForEach-Object { '{0} ({1}, {2})' -f $_.FriendlyName, (Format-Size $_.Size), $_.BusType }) -join "`n")
        $script:BenchShort.CPU = Get-ShortCpuName $cpus[0].Name
        if ($mods.Count) { $script:BenchShort.RAM = ('{0} GB {1}-{2}' -f [math]::Round($total / 1GB), $(if ($typ0) { $typ0 } else { 'RAM' }), $spd0) }
        if ($gMain) { $script:BenchShort.GPU = Get-ShortGpuName $gMain.Name }
        $script:DiskNames = @{}
        foreach ($d in $pd) { $script:DiskNames[[int]$d.DeviceId] = ('{0} ({1})' -f ([string]$d.FriendlyName).Trim(), $d.BusType); Add-Private ([string]$d.SerialNumber) 'SERIENNR' }
        Add-Private $bios.SerialNumber 'SERIENNR'; Add-Private $bb.SerialNumber 'SERIENNR'
        foreach ($m in $mods) { Add-Private ([string]$m.SerialNumber) 'SERIENNR' }
        $script:UserNames = @(@([string]$cs.UserName, [string]$env:USERNAME) | ForEach-Object { ($_ -split '\\')[-1] } | Where-Object { $_ })
        if ($cs.PartOfDomain -and $cs.Domain) { Add-Private ([string]$cs.Domain) 'DOMÄNE' }
        [pscustomobject]$script:Facts | Out-Report -List
        Test-RamProfile $mods $typ0
        $up = (Get-Date) - $os.LastBootUpTime
        if ($up.TotalDays -gt 14) { Add-Finding INFO 'System' ('Seit {0} Tagen kein Neustart. Für aussagekräftige Messwerte vorher neu starten.' -f [int]$up.TotalDays) }
    }
}


# =====================================================================================
#                                    BENCHMARK
# =====================================================================================
$script:BenchInit = $false
function Initialize-Bench {
    if ($script:BenchInit) { return }
    $script:BenchInit = $true
    $script:BenchMs = $(if ($BenchmarkKurz) { 2000 } else { 5000 })
    # PS 5.1 gibt ein JSON-Array als EIN Objekt aus, daher erst zuweisen, dann in ein Array wandeln
    # frühere Läufe dieses Geräts aus der Vergleichsdatenbank (gleiche Messdauer) für den Verlauf, auch nach Umbenennung oder Neuinstallation
    $devId = (Get-DeviceIdentity).Id
    $script:BenchHistory = @(Get-DbEntries | Where-Object { (Test-SameDevice $_ $devId $env:COMPUTERNAME) -and $_.Messwerte.Count } | Sort-Object Datum | ForEach-Object {
        $mw = $_.Messwerte
        [pscustomobject]@{ Kurz = ($_.Messdauer -eq 'kurz'); Werte = @($mw.Keys | ForEach-Object { [pscustomobject]@{ Key = $_; Wert = $mw[$_] } }) }
    })
    Import-BenchReference
    # Vergleichssysteme aus der Datenbank laden
    $script:CmpSystems = @()
    foreach ($f in @(([string]$VergleichDateien) -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })) {
        $j = Read-JsonFile $f
        if ($j -and $j.Werte) { $script:CmpSystems += [pscustomobject]@{ Path = $f; Name = [string]$j.Name; Computer = [string]$j.Computer; Datum = [string]$j.Datum; Werte = (ConvertTo-ValueTable $j.Werte) } }
        else { Add-Line ('  Vergleichssystem nicht lesbar: {0}' -f $f) }
    }
    Add-Line '  Index 100 = typischer Wert für diese Hardwareklasse. Vergleich = Median der letzten Läufe auf diesem PC.'
    if ($ReferenzSpeichern -and -not (Test-HasReference)) { Add-Line '  Dieser Lauf wird als Referenz gespeichert: Ab dem nächsten Lauf ist dieser PC 100 %, in diesem Bericht entfallen die Prozentwerte.' }
    if ($ReferenzSpeichern -and (Test-HasReference)) { Add-Line ('  Dieser Lauf ersetzt am Ende die Referenz {0}; die Prozentwerte in diesem Bericht beziehen sich noch auf sie.' -f $script:Ref.Name) }
    if (Test-HasReference) { Add-Line ('  Referenz 100 % = {0}{1}. Laufwerke werden mit der gleichen Klasse der Referenz verglichen.' -f $script:Ref.Name, $(if ($script:Ref.Datum) { ', gespeichert am ' + $(try { [datetime]::ParseExact([string]$script:Ref.Datum, 'yyyy-MM-dd', $script:Inv).ToString('dd.MM.yyyy') } catch { $script:Ref.Datum }) } else { '' })) }
    else { Add-Line '  Keine Referenz festgelegt, Prozentwerte entfallen. Zur Referenz wird ein PC mit dem Haken "Dieses System als Referenz festlegen".' }
    if ($script:CmpSystems.Count) { Add-Line ('  Eingeblendete Vergleichssysteme: {0}' -f (($script:CmpSystems | ForEach-Object { '{0} ({1})' -f $_.Computer, $_.Datum }) -join ', ')) }
    Add-Line '  Für aussagekräftige Werte andere Programme schließen und den PC am Netzteil betreiben.'
    $idle = Get-CpuSample
    $script:BenchStartLoad = [int]$idle.Last
    if ($idle.Last -gt 15) { Add-Finding INFO 'Leistung' ('Beim Benchmark-Start lag bereits {0} % CPU-Last an, die Werte können niedriger ausfallen.' -f $idle.Last) }
    # ab v2.7: Sensoren laufen in den Wartepausen der Messungen mit (Temperatur, Takt, Leistung je Abschnitt im Bericht).
    # Sensoren sind Beiwerk: Fehler dürfen den Benchmark nie verhindern.
    try { [void](Start-BenchSensors) } catch { }
}

# Vergleich mit den gewählten Systemen: Bericht, Oberfläche (Reiter Leistung) und KI-Datei
function Add-BenchComparison {
    if (-not $script:CmpSystems.Count) { return }
    $script:CmpRows = @(Get-CompareRows)
    if (-not $script:CmpRows.Count) { return }
    Add-Sub 'Vergleich mit bereits geprüften Systemen'
    $i = 0
    foreach ($s in $script:CmpSystems) { $i++; Add-Line ('  System {0}: {1}, Messung vom {2}' -f $i, $s.Name, $s.Datum) }
    $tab = foreach ($r in $script:CmpRows) {
        $o = [ordered]@{ Messung = $r.Messung; 'Dieser PC' = (Format-Metric $r.Dieses $r.Format $r.Einheit) }
        for ($k = 0; $k -lt $script:CmpSystems.Count; $k++) {
            $v = $r.Werte[$k]
            $rel = Get-RelText $r.Dieses $v $r.LowerBetter
            $o[('System {0}' -f ($k + 1))] = $(if ($null -ne $v) { (Format-Metric $v $r.Format $r.Einheit) + $(if ($rel) { ' (' + $rel + ')' } else { '' }) } else { '' })
        }
        $o['Reihenfolge (niedrig nach hoch)'] = (Get-CompareOrderText $r)
        $o['Rang'] = $r.Rang
        [pscustomobject]$o
    }
    $tab | Out-Report
    Add-Line '  Prozent in Klammern: Abstand des anderen Systems zu diesem PC, positiv bedeutet besser. Reihenfolge immer vom niedrigsten zum höchsten Wert. Rang unter allen Systemen der Datenbank.'
    Send-GuiEvent 'BGRP' 'Vergleich' 'Vergleich mit anderen Systemen' '' (($script:CmpSystems | ForEach-Object { $_.Computer }) -join ', ') ''
    foreach ($r in $script:CmpRows) {
        # aufsteigend sortiert, dieser PC eingereiht und hervorgehoben
        $parts = Get-CompareOrderText $r -Gui
        Send-GuiEvent 'BENCH' '' 'Vergleich' $r.Messung (Format-Metric $r.Dieses $r.Format $r.Einheit) '' $parts ((@($parts) + @($r.Rang) | Where-Object { $_ }) -join '; ') $r.Rang 'Vergleich'
    }
}

function Test-BenchTypes {
    if ($TypesLoaded) { return $true }
    Add-Line '  Übersprungen: C#-Routinen nicht verfügbar (Constrained Language Mode).'
    Add-TestResult 'Benchmark' 'Übersprungen' 'Constrained Language Mode'
    return $false
}

if ($ModBench) {

# PCIe-Generation einer NVMe-SSD aus dem sequentiellen Lesen (ab v2.8), 0 ohne Messwert. Grenzen knapp über dem, was die
# kleinere Generation mit x4 praktisch schafft (3.0 bis ca. 3.500, 4.0 bis ca. 7.400 MB/s).
function Get-NvmeGenFromSpeed([double]$ReadMBs) {
    if ($ReadMBs -le 0) { return 0 }
    if ($ReadMBs -gt 7600) { return 5 }
    if ($ReadMBs -gt 3700) { return 4 }
    return 3
}

# Kurzergebnis am Ende eines Messabschnitts (ab v2.8): Bis v2.7 blieben Arbeitsspeicher und Datenträger im Textbericht leer,
# weil die Tabellen erst in der Auswertung stehen.
function Add-BenchHeadLine([string]$Gruppe) {
    $h = $script:BenchHead[$Gruppe]
    if ($h) { Add-Line ('  Ergebnis: {0}. Einzelwerte unter Auswertung und Vergleich.' -f $h) }
    elseif (-not (Get-BenchGroup $Gruppe).Anzahl) { Add-Line '  Keine Messwerte (siehe Hinweise oben).' }
}

# Unterbrechungen je Abschnitt (ab v2.8): WinSAT läuft als eigener Prozess, Unterbrechungen von Leos Minibench in dieser
# Zeit verfälschen keine Messung und zählen nicht mehr mit. Bis v2.7 kamen so auf TORRENT 28 s zusammen.
$script:BenchPauseParts = New-Object System.Collections.Generic.List[object]
function Set-BenchPausePart([string]$Teil) {
    if (-not ($TypesLoaded -and ('DiagPause' -as [type]))) { return }
    try { if (-not [DiagPause]::Running) { return }; $snap = [DiagPause]::SnapshotPart() } catch { return }
    $now = Get-Date
    if ($script:BenchPauseParts.Count) { $l = $script:BenchPauseParts[$script:BenchPauseParts.Count - 1]; if ($null -eq $l.Ende) { $l.Ende = $now; $l.Bis = $snap } }
    if ($Teil) { $script:BenchPauseParts.Add([pscustomobject]@{ Teil = $Teil; Beginn = $now; Ende = $null; Von = $snap; Bis = $null }) }
}

# Zusammenfassung der Abschnitte ohne WinSAT: Werte wie DiagPause ([0] Anzahl, [1] längste, [2] Summe, GC aus $Gesamt), Dauer in s
function Get-BenchPauseMeasured($Parts, $Gesamt) {
    $n = 0.0; $mx = 0.0; $sum = 0.0; $sec = 0.0
    foreach ($p in @($Parts | Where-Object { $_ -and $_.Teil -ne 'WinSAT' -and $_.Von -and $_.Bis })) {
        $n += [double]$p.Bis[0] - [double]$p.Von[0]; $sum += [double]$p.Bis[2] - [double]$p.Von[2]
        if ([double]$p.Bis[1] -gt $mx) { $mx = [double]$p.Bis[1] }
        $sec += ($p.Ende - $p.Beginn).TotalSeconds
    }
    $gc = $(if ($Gesamt -and @($Gesamt).Count -ge 6) { @($Gesamt[3], $Gesamt[4], $Gesamt[5]) } else { @(0, 0, 0) })
    return [pscustomobject]@{ Werte = [double[]]@($n, $mx, $sum, $gc[0], $gc[1], $gc[2]); Sekunden = $sec }
}

# Unterbrechungen während der Messungen (ab v2.66): Auswertung im Abschnitt Auswertung und Vergleich
$script:BenchT0 = Get-Date; $script:BenchPause = $null
Start-PauseWatch

if ($script:BenchSel['CPU']) {
    Invoke-Section 'Benchmark: Prozessor' {
        Initialize-Bench
        Set-BenchSensorPart 'Prozessor'
        Set-BenchPausePart 'Prozessor'
        if (-not (Test-BenchTypes)) { return }
        $inv = $script:Inv; $ms = $script:BenchMs; $threads = [Environment]::ProcessorCount
        # ---------------- Prozessor ----------------
        try {
            $cpuAll = @(Get-CimCached Win32_Processor)
            $cpuName = (($cpuAll[0].Name -as [string]) -replace '\s+', ' ').Trim()
            $cores = [int](($cpuAll | Measure-Object NumberOfCores -Sum).Sum)
            $baseMHz = [int]$cpuAll[0].MaxClockSpeed
            Write-Step 'Benchmark Prozessor ...'
            $tST = [DiagBench]::CpuAsync(1, $ms)
            $sST = Wait-TaskProgress $tST 'Benchmark Prozessor' 'Einzelkern' $ms -Sample
            $st = [double]$tST.Result
            Start-Sleep -Milliseconds 500
            $tMT = [DiagBench]::CpuAsync($threads, $ms)
            $sMT = Wait-TaskProgress $tMT 'Benchmark Prozessor' ('Mehrkern, {0} Threads' -f $threads) $ms -Sample
            $mt = [double]$tMT.Result
            $ptsST = [math]::Round($st / 3); $ptsMT = [math]::Round($mt / 3)
            $scal = $(if ($st -gt 0) { $mt / $st } else { 0 })
            $hybrid = $cpuName -match 'Core\(TM\) Ultra|Core\(TM\) i[3579]-1[2-4]\d{3}|Core\(TM\) [3579] '
            $smt = [math]::Max(0, $threads - $cores)
            # Die Rechenlast profitiert stark von SMT/Hyper-Threading (gemessen: 6 Kerne/12 Threads skalieren ca. 12x)
            $expScal = $(if ($hybrid) { $cores * 0.8 + $smt * 0.9 } else { $cores + $smt * 0.9 })
            if ($expScal -lt 1) { $expScal = 1 }
            $scalIdx = [int][math]::Round($scal / $expScal * 100)
            $stPerf = Get-Median ($sST | ForEach-Object { $_.MaxLeistung } | Where-Object { $_ -gt 0 })
            $mtPerf = Get-Median ($sMT | ForEach-Object { $_.Leistung } | Where-Object { $_ -gt 0 })
            $keyCpu = 'CPU|' + $cpuName
            Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Einzelkern' -Wert $ptsST -Einheit 'Punkte' -Anzeige ('{0:N0} Punkte' -f $ptsST) -Key ($keyCpu + '|ST') -RefKey 'CPU|ST' -Hinweis 'eigene Rechenlast aus Ganzzahl- und Gleitkommaoperationen, ein Thread'
            if ($stPerf) {
                $stStat = $(if ($stPerf -lt 85) { 'Warnung' } else { 'OK' })
                Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Takt Einzelkern' -Wert ($baseMHz * $stPerf / 100) -Einheit 'MHz' -Anzeige ('{0:N0} MHz' -f ($baseMHz * $stPerf / 100)) -Index ([int]$stPerf) -Status $stStat -Hinweis ('{0} % vom Basistakt {1} MHz' -f $stPerf, $baseMHz)
                if ($stStat -eq 'Warnung') { Add-Finding WARNUNG 'Leistung' ('Unter Einzelkernlast läuft die CPU nur mit {0} % des Basistakts (Energiesparplan, Drosselung oder BIOS-Einstellung).' -f $stPerf) }
            }
            Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Mehrkern' -Wert $ptsMT -Einheit 'Punkte' -Anzeige ('{0:N0} Punkte' -f $ptsMT) -Key ($keyCpu + '|MT') -RefKey 'CPU|MT' -Hinweis ('{0} Threads' -f $threads)
            $mtStat = $(if ($scalIdx -lt 55) { 'Warnung' } elseif ($scalIdx -lt 75) { 'Info' } else { 'OK' })
            Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Mehrkern-Skalierung' -Wert ([math]::Round($scal, 2)) -Einheit 'x' -Anzeige ('{0:N1}x' -f $scal) -Index $scalIdx -Status $mtStat -Hinweis ('erwartet ca. {0:N1}x bei {1} Kernen und {2} Threads' -f $expScal, $cores, $threads)
            if ($mtStat -eq 'Warnung') { Add-Finding WARNUNG 'Leistung' ('Die CPU skaliert schlecht über alle Kerne ({0:N1}x statt ca. {1:N1}x): Power-Limit, Drosselung, Energiesparplan oder Hintergrundlast.' -f $scal, $expScal) }
            if ($mtPerf) {
                $mtcStat = $(if ($mtPerf -lt 80) { 'Warnung' } else { 'OK' })
                Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Takt Mehrkern' -Wert ($baseMHz * $mtPerf / 100) -Einheit 'MHz' -Anzeige ('{0:N0} MHz' -f ($baseMHz * $mtPerf / 100)) -Index ([int]$mtPerf) -Status $mtcStat -Hinweis ('{0} % vom Basistakt' -f $mtPerf)
                if ($mtcStat -eq 'Warnung') { Add-Finding WARNUNG 'Leistung' ('Unter Last auf allen Kernen hält die CPU nur {0} % des Basistakts (Kühlung, Power-Limit oder Netzteil).' -f $mtPerf) }
            }
            # Praxisnahe Teillasten: Verschlüsselung, Prüfsummen, Kompression
            $tA = [DiagBench]::AesAsync($ms); [void](Wait-TaskProgress $tA 'Benchmark Prozessor' 'AES-256 verschlüsseln' $ms); $aes = [double]$tA.Result
            if ($aes -gt 0) {
                $aesStat = $(if ($aes -lt 300) { 'Info' } else { 'OK' })
                Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'AES-256 verschlüsseln' -Wert ([math]::Round($aes)) -Einheit 'MB/s' -Anzeige ('{0:N0} MB/s' -f $aes) -Status $aesStat -Key ($keyCpu + '|AES') -RefKey 'CPU|AES' -Hinweis 'AES-256-CBC, ein Thread, Windows-Kryptografie'
                if ($aesStat -eq 'Info') { Add-Finding INFO 'Leistung' ('AES-Verschlüsselung erreicht nur {0:N0} MB/s. Vermutlich wird AES-NI nicht genutzt (im BIOS deaktiviert oder virtuelle Maschine), BitLocker und VPN werden dadurch langsamer.' -f $aes) }
            }
            $tS = [DiagBench]::ShaAsync($ms); [void](Wait-TaskProgress $tS 'Benchmark Prozessor' 'SHA-256 Prüfsumme' $ms); $sha = [double]$tS.Result
            if ($sha -gt 0) { Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'SHA-256 Prüfsumme' -Wert ([math]::Round($sha)) -Einheit 'MB/s' -Anzeige ('{0:N0} MB/s' -f $sha) -Key ($keyCpu + '|SHA') -RefKey 'CPU|SHA' -Hinweis $(if ($sha -ge 1500) { 'ein Thread, SHA-Befehlssatz aktiv' } else { 'ein Thread' }) }
            $tD = [DiagBench]::DeflateAsync($threads, $ms); [void](Wait-TaskProgress $tD 'Benchmark Prozessor' ('Kompression, {0} Threads' -f $threads) ($ms + 1500)); $defl = [double]$tD.Result
            if ($defl -gt 0) { Add-BenchResult -Gruppe 'CPU' -Komponente 'CPU' -Messung 'Kompression (Deflate)' -Wert ([math]::Round($defl)) -Einheit 'MB/s' -Anzeige ('{0:N0} MB/s' -f $defl) -Key ($keyCpu + '|DEFL') -RefKey 'CPU|DEFL' -Hinweis ('ZIP-Kompression von Textdaten auf {0} Threads, Durchsatz der Eingangsdaten' -f $threads) }
            $script:BenchHead['CPU'] = '{0} · Einzelkern {1:N0} · Mehrkern {2:N0} Punkte' -f ($cpuName -replace '\s*(\d+-Core|Processor|CPU @.*$)', '' -replace '\((R|TM)\)', ''), $ptsST, $ptsMT
            $script:BenchShort.CPU = Get-ShortCpuName $cpuName
        } catch { Write-BenchError 'Prozessor' $_ }
        Send-BenchGroup 'CPU'
        Add-BenchHeadLine 'CPU'
    }
}

if ($script:BenchSel['RAM']) {
    Invoke-Section 'Benchmark: Arbeitsspeicher' {
        Initialize-Bench
        Set-BenchSensorPart 'Arbeitsspeicher'
        Set-BenchPausePart 'Arbeitsspeicher'
        if (-not (Test-BenchTypes)) { return }
        $inv = $script:Inv; $ms = $script:BenchMs; $threads = [Environment]::ProcessorCount
        # ---------------- Arbeitsspeicher ----------------
        try {
            $os = Get-CimInstance Win32_OperatingSystem
            $freeB = [double]$os.FreePhysicalMemory * 1KB
            $memBytes = [long][math]::Min([double]1GB, [double]$freeB * 0.3)
            if ($memBytes -lt 128MB) { Add-Line '  RAM-Benchmark übersprungen: zu wenig freier Speicher.' }
            else {
                Write-Step 'Benchmark Arbeitsspeicher ...'
                $tR = [DiagBench]::MemReadAsync($threads, $memBytes, $ms); [void](Wait-TaskProgress $tR 'Benchmark Arbeitsspeicher' 'Lesen' ($ms + 2000)); $rd = [double]$tR.Result
                $tW = [DiagBench]::MemWriteAsync($threads, $memBytes, $ms); [void](Wait-TaskProgress $tW 'Benchmark Arbeitsspeicher' 'Schreiben' ($ms + 2000)); $wr = [double]$tW.Result
                $tC = [DiagBench]::MemCopyAsync($threads, $memBytes, $ms); [void](Wait-TaskProgress $tC 'Benchmark Arbeitsspeicher' 'Kopieren' ($ms + 2000)); $cp = [double]$tC.Result
                $tL = [DiagBench]::LatencyAsync([long][math]::Min([long]256MB, [long]$memBytes), [int][math]::Min(3000, [int]$ms)); [void](Wait-TaskProgress $tL 'Benchmark Arbeitsspeicher' 'Latenz' 4000); $lat = [double]$tL.Result
                $mods = @(Get-CimCached Win32_PhysicalMemory)
                $speed = [int](($mods | Where-Object { $_.ConfiguredClockSpeed } | Measure-Object ConfiguredClockSpeed -Minimum).Minimum)
                if (-not $speed) { $speed = [int](($mods | Measure-Object Speed -Minimum).Minimum) }
                $mtype = $(if ($mods.Count) { [int]$mods[0].SMBIOSMemoryType } else { 0 })
                $tname = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }[$mtype]
                $chan = @($mods | ForEach-Object {
                    $l = '{0} {1}' -f $_.BankLabel, $_.DeviceLocator
                    if ($l -match '(Controller\s*\d+)?\W*CHANNEL\s*([A-H])') { ('{0}{1}' -f $Matches[1], $Matches[2]).ToUpper() } elseif ($l -match 'DIMM_?([A-H])\d') { $Matches[1].ToUpper() }
                } | Select-Object -Unique).Count
                if (-not $chan) { $chan = [math]::Min(2, $mods.Count) }
                $lp = $mtype -in 27, 28, 29, 30, 35
                $theo = $chan * $speed * 8 / 1000
                $eff = $(if ($theo -gt 0) { $rd / $theo } else { 0 })
                $memIdx = $(if ($lp -or $theo -le 0) { $null } else { [int][math]::Round($eff / 0.65 * 100) })
                $memStat = $(if ($null -eq $memIdx) { 'Info' } elseif ($memIdx -lt 50) { 'Warnung' } elseif ($memIdx -lt 70) { 'Info' } else { 'OK' })
                $totalGB = [math]::Round((($mods | Measure-Object Capacity -Sum).Sum) / 1GB)
                $keyRam = 'RAM|{0}GB|{1}' -f $totalGB, $speed
                $hint = $(if ($null -ne $memIdx) { '{0:N0} % von theoretisch {1:N1} GB/s ({2} Kanäle, {3} MT/s)' -f ($eff * 100), $theo, $chan, $speed } else { 'LPDDR bzw. unbekannte Kanalzahl, kein Index' })
                Add-BenchResult -Gruppe 'RAM' -Komponente 'RAM' -Messung 'Lesen' -Wert ([math]::Round($rd, 1)) -Einheit 'GB/s' -Anzeige ('{0:N1} GB/s' -f $rd) -Index $memIdx -Status $memStat -Key ($keyRam + '|Lesen') -RefKey 'RAM|Lesen' -Hinweis $hint
                Add-BenchResult -Gruppe 'RAM' -Komponente 'RAM' -Messung 'Schreiben' -Wert ([math]::Round($wr, 1)) -Einheit 'GB/s' -Anzeige ('{0:N1} GB/s' -f $wr) -Key ($keyRam + '|Schreiben') -RefKey 'RAM|Schreiben'
                if ($cp -gt 0) { Add-BenchResult -Gruppe 'RAM' -Komponente 'RAM' -Messung 'Kopieren' -Wert ([math]::Round($cp, 1)) -Einheit 'GB/s' -Anzeige ('{0:N1} GB/s' -f $cp) -Key ($keyRam + '|Kopieren') -RefKey 'RAM|Kopieren' -Hinweis 'kopierte Datenmenge pro Sekunde (liest und schreibt gleichzeitig)' }
                $latStat = $(if ($lat -gt 250) { 'Warnung' } elseif ($lat -gt 150) { 'Info' } else { 'OK' })
                Add-BenchResult -Gruppe 'RAM' -Komponente 'RAM' -Messung 'Latenz' -Wert ([math]::Round($lat, 1)) -Einheit 'ns' -Anzeige ('{0:N0} ns' -f $lat) -Status $latStat -Key ($keyRam + '|Latenz') -RefKey 'RAM|Latenz' -LowerBetter -Hinweis 'zufällige Zugriffe über 256 MB, inklusive TLB-Fehlgriffe'
                if ($memStat -eq 'Warnung') { Add-Finding WARNUNG 'Leistung' ('Die Speicherbandbreite erreicht nur {0:N0} % des theoretischen Werts: Single-Channel-Betrieb, falsche Steckplätze, niedriger Takt oder Hintergrundlast prüfen.' -f ($eff * 100)) }
                $ramDesc = ('{0} GB {1}-{2}' -f $totalGB, $(if ($tname) { $tname } else { 'RAM' }), $speed)
                $script:BenchHead['RAM'] = '{0}, {1} Kanäle · Lesen {2:N1} GB/s · Latenz {3:N0} ns' -f $ramDesc, $chan, $rd, $lat
                $script:BenchShort.RAM = $ramDesc
            }
        } catch { Write-BenchError 'Arbeitsspeicher' $_ }
        Send-BenchGroup 'RAM'
        Add-BenchHeadLine 'RAM'
    }
}

if ($script:BenchSel['GPU']) {
    Invoke-Section 'Benchmark: Grafik' {
        Initialize-Bench
        Set-BenchSensorPart 'Grafik'
        Set-BenchPausePart 'Grafik'
        if (-not (Test-BenchTypes)) { return }
        $inv = $script:Inv; $ms = $script:BenchMs; $threads = [Environment]::ProcessorCount
        # ---------------- Grafik ----------------
        # Gemessen wird mit WinSAT DWM. Auf Geräten mit Grafikkarte und Prozessorgrafik misst WinSAT die Einheit, über die
        # Windows den Desktop ausgibt; welche das war, verrät die Treiberversion in winsat-dwm.xml. Hat WinSAT die
        # Prozessorgrafik gemessen, wird mit -BenchGpuWahl die Grafikkarte für winsat.exe vorübergehend als bevorzugte
        # GPU eingetragen (protokolliert, sofort zurückgesetzt) und ein zweites Mal gemessen.
        try {
            $isDisc = { param($g) (Get-GpuKind ([string]$g.Name)) -eq 'dGPU' }
            $adapters = @(Get-GpuAdapters)
            $gpus = @($adapters | ForEach-Object { $_.Adapter })
            $disc = @($gpus | Where-Object { & $isDisc $_ })
            if ($disc.Count -and -not $script:IsLaptop) {
                $discOn = @($disc | Where-Object { $_.CurrentHorizontalResolution })
                $igpOn  = @($gpus | Where-Object { -not (& $isDisc $_) -and $_.CurrentHorizontalResolution })
                if (-not $discOn.Count -and $igpOn.Count) { Add-Finding WARNUNG 'Leistung' ('Der Monitor hängt an der Prozessorgrafik ({0}) statt an der Grafikkarte {1}. Kabel an die Grafikkarte umstecken.' -f $igpOn[0].Name, $disc[0].Name) }
            }
            $gMain = $(if ($disc.Count) { $disc[0] } elseif ($gpus.Count) { $gpus[0] } else { $null })
            $gpuName = $(if ($gMain) { [string]$gMain.Name } else { 'Grafik' })
            $runDwm = {
                param([string]$File, [string]$Label)
                $wx = Join-Path $RawDir $File
                Write-Step ('Benchmark Grafik (WinSAT DWM{0}) ...' -f $Label)
                $wr = Invoke-External -File "$env:windir\System32\winsat.exe" -Arguments ('dwm -xml "{0}"' -f $wx) -TimeoutSec 300 -Progress ('Benchmark Grafik (WinSAT DWM{0})' -f $Label) -ExpectedSec 30
                $res = Read-WinsatDwmXml $wx
                $res | Add-Member -NotePropertyName ExitCode -NotePropertyValue $wr.ExitCode -Force
                $res | Add-Member -NotePropertyName Einheit -NotePropertyValue (Resolve-WinsatAdapter $res $adapters) -Force
                return $res
            }
            $meas = New-Object System.Collections.Generic.List[object]
            $m1 = & $runDwm 'winsat-dwm.xml' ''
            if ($m1.Vmb) { $meas.Add($m1) }
            $dAd = @($adapters | Where-Object { $_.Art -eq 'dGPU' }) | Select-Object -First 1
            if ($m1.Vmb -and $dAd -and $m1.Einheit -and $m1.Einheit.Art -ne 'dGPU') {
                if ($BenchGpuWahl) {
                    $prefPath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
                    $exe = "$env:windir\System32\winsat.exe"
                    $rec = $null
                    if (-not $script:ChangeLog) { Start-ChangeLog }
                    if (-not $script:ChangeFile) { Add-Line '  Grafikkarte für WinSAT nicht umgestellt: kein Datenordner für das Änderungsprotokoll.' }
                    else { try {
                        $rec = Set-RegistryValueLogged -Path $prefPath -Name $exe -Value 'GpuPreference=2;' -Type 'String' -Modul 'Benchmark' -Schritt 'GpuWahl' -Titel 'WinSAT vorübergehend auf die Grafikkarte gelegt (Hybridgrafik)'
                        $script:GpuPrefChanged = $true
                        $m2 = & $runDwm 'winsat-dwm-grafikkarte.xml' ', Grafikkarte'
                        if ($m2.Vmb -and $m2.Einheit -and $m2.Einheit.Art -eq 'dGPU') { $meas.Add($m2) }
                        else { Add-Line ('  WinSAT erreicht hier nur die Prozessorgrafik, auch mit Vorrang für {0}. Die Grafikkarte misst der Rendertest.' -f $dAd.Name) }
                    } catch { Add-Line ('  Grafikkarte für WinSAT nicht umstellbar: {0}' -f $_.Exception.Message) }
                    finally { if ($rec) { $u = Undo-ChangeNow $rec; if ($u) { Add-Line '  Grafikwahl für WinSAT wieder zurückgesetzt.' } } } }
                } else {
                    Add-Line ('  WinSAT misst nur die Einheit, die den Desktop ausgibt (hier die Prozessorgrafik {0}). Die Grafikkarte {1} misst der Rendertest.' -f $m1.Einheit.Name, $dAd.Name)
                }
            }
            if ($meas.Count) {
                # Referenz und Datenbankwert: die Grafikkarte, wenn sie gemessen wurde, sonst die gemessene Einheit
                $leadIdx = 0
                for ($k = 0; $k -lt $meas.Count; $k++) { if ($meas[$k].Einheit -and $meas[$k].Einheit.Art -eq 'dGPU') { $leadIdx = $k; break } }
                $lead = $meas[$leadIdx]
                $two = ($meas.Count -gt 1)
                for ($k = 0; $k -lt $meas.Count; $k++) {
                    $m = $meas[$k]
                    $u = $m.Einheit; $uName = $(if ($u) { $u.Name } else { $gpuName })
                    $suffix = $(if ($two -and $u) { ' ({0})' -f $u.Bezeichnung } else { '' })
                    $isLead = ($k -eq $leadIdx)
                    $hint = ('{0}{1}, gemessen mit WinSAT DWM (kein Spiele-Benchmark){2}' -f $uName, $(if ($u -and $adapters.Count -gt 1) { ', ' + $u.Bezeichnung } else { '' }), $(if ($u -and $u.Desktop -and $adapters.Count -gt 1) { ', gibt den Desktop aus' } else { '' }))
                    Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung ('Grafikspeicher-Durchsatz' + $suffix) -Wert ([math]::Round($m.Vmb / 1000, 1)) -Einheit 'GB/s' -Anzeige ('{0:N1} GB/s' -f ($m.Vmb / 1000)) -Key ('GPU|' + $uName + '|VMB') -RefKey $(if ($isLead) { 'GPU|VMB' } else { '' }) -Hinweis $hint
                    if ($m.Fps) { Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung ('Desktop-Komposition' + $suffix) -Wert ([math]::Round($m.Fps)) -Einheit 'Bilder/s' -Anzeige ('{0:N0} Bilder/s' -f $m.Fps) -Key ('GPU|' + $uName + '|DWM') -RefKey $(if ($isLead) { 'GPU|DWM' } else { '' }) }
                }
                $script:BenchGpuMeasured = $(if ($lead.Einheit) { $lead.Einheit.Name } else { $gpuName })
                $vmb = $lead.Vmb
            } else {
                $vmb = $null
                Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung 'Grafikspeicher-Durchsatz' -Wert 0 -Einheit 'GB/s' -Anzeige 'nicht messbar' -Status 'Info' -Hinweis ('WinSAT DWM lieferte kein Ergebnis (Rückgabecode {0}, z. B. per Remotedesktop)' -f $m1.ExitCode)
            }
            # ---------------- Rendertest je Grafikeinheit (ab v2.6) ----------------
            # Eigenes Direct3D-11-Gerät auf jeder Grafikeinheit, nacheinander (Messungen nie parallel). Ersetzt für die
            # Leistung der Grafikkarte die WinSAT-Messung, die bei Hybridgrafik nur die Prozessorgrafik erreicht.
            $renderFps = $null
            $rSel = Select-RenderAdapters @(Get-RenderAdapters) $GpuAuswahl
            $rAds = @($rSel.Adapter)
            if ($rSel.Hinweis) { Add-Line ('  {0}' -f $rSel.Hinweis) }
            $script:DisplayRates = @(Get-DisplayRefreshRates)
            if (-not $rAds.Count) {
                $why = Get-RenderUnavailableText
                Add-Line ('  {0}' -f $why)
                Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung 'Rendertest' -Wert 0 -Einheit 'Bilder/s' -Anzeige 'nicht messbar' -Status 'Info' -Hinweis $why
            } else {
                $rs = Get-RenderSize $GpuAufloesung
                $rWarm = $(if ($BenchmarkKurz) { 3000 } else { 6000 }); $rMeas = $(if ($BenchmarkKurz) { 10000 } else { 20000 })
                Add-Line ('  Rendertest: {0}x{1}, je Grafikeinheit {2} s Aufwärmen und {3} s Messung, ohne VSync{5}: {4}' -f $rs[0], $rs[1], ($rWarm / 1000), ($rMeas / 1000), (($rAds | ForEach-Object { '{0} ({1})' -f $_.Name, $_.Bezeichnung }) -join ', '), $(if ($rSel.Auswahl -ne 'alle Grafikeinheiten') { ', ' + $rSel.Auswahl } else { '' }))
                $rr = @(Invoke-RenderBenchmark $rAds $rs[0] $rs[1] (Get-RenderPreviewMode $GpuAnzeige) $rWarm $rMeas)
                $multi = ($rAds.Count -gt 1)
                $leadDone = $false; $ri = 0
                foreach ($res in $rr) {
                    $script:GpuRender.Add($res)
                    $adOf = @($rAds | Where-Object { $_.Index -eq $res.Index }) | Select-Object -First 1
                    $st = Add-RenderFindings $res 'Rendertests' @(Select-TdrEvents $res.Tdr $adOf ($ri -eq 0))
                    $suffix = $(if ($multi) { ' ({0})' -f $res.Bezeichnung } else { '' })
                    if ($res.Ok) {
                        $isLead = -not $leadDone; $leadDone = $true
                        if ($isLead) { $renderFps = $res.Fps; $script:BenchGpuMeasured = $res.Name }
                        $bStat = $(if ($st -eq 'Fehler') { 'Warnung' } else { 'OK' })
                        $hint = ('{0}, {1}, Direct3D-Feature-Level {2}, Ø {3:N1} Bilder/s, 1-%-Low {4:N1}, Bildzeit Median {5:N2} ms, 99 % {6:N2} ms, Bildprüfung {7}' -f $res.Name, $res.Aufloesung, $res.Ebene, $res.Fps, $res.Low1, $res.MedianMs, $res.P99Ms, $(if ($res.Bildfehler) { '{0} von {1} abweichend' -f $res.Bildfehler, $res.Bildpruefungen } else { 'bitgleich' }))
                        # Bildratengrenze (ab v2.65): Gegenprobe mit einem Viertel der Rechenlast vor der Messung
                        if ($res.Grenze -and $res.Grenze.Begrenzt) {
                            Add-Finding WARNUNG 'Grafik' ('{0} ({1}): {2}' -f $res.Name, $res.Bezeichnung, $res.Grenze.Text)
                            $bStat = 'Warnung'
                            $hint = 'Bildratengrenze: ' + $res.Grenze.Text + ' ' + $hint
                            Add-Line ('  {0} ({1}): {2}' -f $res.Name, $res.Bezeichnung, $res.Grenze.Text)
                        }
                        Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung ('Rendertest' + $suffix) -Wert $res.Fps -Einheit 'Bilder/s' -Anzeige ('{0:N0} Bilder/s' -f $res.Fps) -Key ('GPU|' + $res.Name + '|REND|' + $res.Aufloesung) -RefKey $(if ($isLead -and $res.Aufloesung -eq '1280x720') { 'GPU|REND' } else { '' }) -Hinweis $hint -Status $bStat
                        Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung ('Rendertest 1-%-Low' + $suffix) -Wert $res.Low1 -Einheit 'Bilder/s' -Anzeige ('{0:N0} Bilder/s' -f $res.Low1) -Key ('GPU|' + $res.Name + '|REND1|' + $res.Aufloesung) -RefKey $(if ($isLead -and $res.Aufloesung -eq '1280x720') { 'GPU|REND1' } else { '' }) -Hinweis 'Bilder/s aus den langsamsten 1 % der Bildzeiten (Ruckler)'
                        Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung ('Rendertest Punktzahl' + $suffix) -Wert $res.Punkte -Einheit 'Punkte' -Anzeige ('{0:N0} Punkte' -f $res.Punkte) -Key ('GPU|' + $res.Name + '|RPKT') -RefKey $(if ($isLead) { 'GPU|RPKT' } else { '' }) -Hinweis 'Ø Bilder/s x Pixel je Bild / 10 000, vergleichbar über die Auflösungen'
                        Add-Line ('  {0} ({1}): Ø {2:N1} Bilder/s, 1-%-Low {3:N1}, Punktzahl {4:N0}, {5:N0} Bilder in {6:N1} s' -f $res.Name, $res.Bezeichnung, $res.Fps, $res.Low1, $res.Punkte, $res.Bilder, $res.Sekunden)
                        try {
                            $csv = Join-Path $RawDir ('Rendertest_{0}.csv' -f (Get-SafeName $res.Name))
                            $acc = 0.0
                            $lines = New-Object System.Collections.Generic.List[string]; $lines.Add('Bild;Zeit_s;Bildzeit_ms')
                            $fmz = @($res.Bildzeiten)
                            for ($q = 0; $q -lt $fmz.Count; $q++) { $acc += [double]$fmz[$q] / 1000.0; $lines.Add(('{0};{1};{2}' -f ($q + 1), $acc.ToString('0.000', $script:Inv), ([double]$fmz[$q]).ToString('0.000', $script:Inv))) }
                            [IO.File]::WriteAllLines($csv, $lines, (New-Object Text.UTF8Encoding($true)))
                        } catch { }
                    } else {
                        Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung ('Rendertest' + $suffix) -Wert 0 -Einheit 'Bilder/s' -Anzeige 'nicht messbar' -Status $(if ($res.Treiberreset) { 'Fehler' } else { 'Info' }) -Hinweis ('{0}: {1}' -f $res.Name, $res.Fehler)
                        Add-Line ('  {0} ({1}): Rendertest nicht möglich: {2}' -f $res.Name, $res.Bezeichnung, $res.Fehler)
                    }
                    $ri++
                }
            }
            # Anbindung direkt nach der Last lesen, im Leerlauf senken Grafikkarten die PCIe-Generation oft ab
            $glink = $null
            foreach ($g in $gpus) {
                $link = Get-PcieLink $g.PNPDeviceID
                if (-not $link) { continue }
                if ($g -eq $gMain) { $glink = $link }
                Add-Line ('  {0}: angebunden mit {1}, möglich {2}' -f $g.Name, (Format-Pcie $link), (Format-Pcie $link -Max))
                if ((& $isDisc $g) -and $link.WidthMax -gt 0 -and $link.WidthNow -lt $link.WidthMax) {
                    Add-Finding WARNUNG 'Leistung' ('{0} ist nur mit x{1} statt x{2} angebunden: falscher Steckplatz, Riser-Kabel oder Kontaktproblem.' -f $g.Name, $link.WidthNow, $link.WidthMax)
                }
            }
            if ($glink) {
                $lStat = $(if ((& $isDisc $gMain) -and $glink.WidthMax -gt 0 -and $glink.WidthNow -lt $glink.WidthMax) { 'Warnung' } elseif ($glink.GenMax -gt 0 -and $glink.GenNow -lt $glink.GenMax) { 'Info' } else { 'OK' })
                $lHint = $(if ($lStat -eq 'Info') { 'möglich {0}. Im Leerlauf schalten viele Grafikkarten die PCIe-Generation zum Stromsparen herunter.' -f (Format-Pcie $glink -Max) } else { 'möglich ' + (Format-Pcie $glink -Max) })
                Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung ('Anbindung' + $(if ($adapters.Count -gt 1) { ' ' + $gpuName })) -Wert ($glink.GenNow * 100 + $glink.WidthNow) -Einheit '' -Anzeige (Format-Pcie $glink) -Status $lStat -Hinweis $lHint
            }
            $vramOf = {
                param($ad)
                $b = 0
                Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue | ForEach-Object {
                    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    try { if ($p.DriverDesc -eq $ad.Name -and $p.'HardwareInformation.qwMemorySize') { $b = [math]::Max([double]$b, [double]$p.'HardwareInformation.qwMemorySize') } } catch { }
                }
                if (-not $b -and $ad.AdapterRAM) { $b = [double][uint32]$ad.AdapterRAM }
                return $b
            }
            foreach ($ad in @($gpus | Sort-Object { if (& $isDisc $_) { 0 } else { 1 } })) {
                $vramB = & $vramOf $ad
                if ($vramB -le 0) { continue }
                $vGB = [math]::Round($vramB / 1GB, 1)
                $dsc = & $isDisc $ad
                $vStat = $(if ($dsc -and $vGB -lt 4) { 'Info' } else { 'OK' })
                Add-BenchResult -Gruppe 'GPU' -Komponente 'GPU' -Messung ('Grafikspeicher' + $(if ($gpus.Count -gt 1) { ' ' + [string]$ad.Name })) -Wert $vGB -Einheit 'GB' -Anzeige ('{0:N0} GB' -f $vGB) -Status $vStat -Hinweis $(if ($dsc) { 'eigener Grafikspeicher der Karte' } else { 'dem Grafikchip zugewiesener Speicher' })
            }
            $script:BenchHead['GPU'] = (@($(if ($script:BenchGpuMeasured -and $script:BenchGpuMeasured -ne $gpuName) { '{0} (gemessen: {1})' -f $gpuName, $script:BenchGpuMeasured } else { $gpuName }), $(if ($renderFps) { '{0:N0} Bilder/s' -f $renderFps }), $(if ($vmb) { '{0:N1} GB/s' -f ($vmb / 1000) }), $(if ($glink) { Format-Pcie $glink })) | Where-Object { $_ }) -join ' · '
            $script:BenchShort.GPU = Get-ShortGpuName $gpuName
        } catch { Write-BenchError 'Grafik' $_ }
        Send-BenchGroup 'GPU'
    }
}

if ($script:BenchSel['Disk']) {
    Invoke-Section 'Benchmark: Datenträger' {
        Initialize-Bench
        Set-BenchSensorPart 'Datenträger'
        Set-BenchPausePart 'Datenträger'
        if (-not (Test-BenchTypes)) { return }
        $inv = $script:Inv; $ms = $script:BenchMs; $threads = [Environment]::ProcessorCount
        # ---------------- Datenträger ----------------
        try {
            $sizeB = $(if ($BenchmarkKurz) { 256MB } else { 1GB }); $phase = $(if ($BenchmarkKurz) { 2500 } else { 6000 })
            Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter | ForEach-Object {
                foreach ($n in 'LeosMinibench-Benchmark.tmp', 'PC-Diagnose-Benchmark.tmp') { $f = '{0}:\{1}' -f $_.DriveLetter, $n; if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
            }
            $dd = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
            foreach ($pd in @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object { [int]$_.DeviceId })) {
                $num = [int]$pd.DeviceId
                $name = ([string]$pd.FriendlyName).Trim()
                $isUsb = [string]$pd.BusType -eq 'USB'
                if ($script:BenchDiskSel.Count) { if ($script:BenchDiskSel -notcontains $num) { continue } }
                elseif ($isUsb) { Add-Line ('  {0}: USB-Datenträger, nicht ausgewählt.' -f $name); continue }
                $vol = Get-Partition -DiskNumber $num -ErrorAction SilentlyContinue | Where-Object DriveLetter |
                    ForEach-Object { Get-Volume -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue } |
                    Where-Object { $_.FileSystem -in 'NTFS', 'ReFS', 'exFAT' -and $_.SizeRemaining -gt ($sizeB * 3 + 1GB) } |
                    Sort-Object SizeRemaining -Descending | Select-Object -First 1
                if (-not $vol) { Add-Line ('  {0}: kein Laufwerksbuchstabe mit genug freiem Platz ({1} nötig), übersprungen.' -f $name, (Format-Size ($sizeB * 3 + 1GB))); continue }
                $bus = [string]$pd.BusType; $media = [string]$pd.MediaType
                $link = $null
                $w = $dd | Where-Object { $_.Index -eq $num } | Select-Object -First 1
                if ($w -and $bus -in 'NVMe', 'RAID') { $link = Get-PcieLink $w.PNPDeviceID }
                # NVMe hinter Intel VMD/RST meldet BusType RAID
                if ($bus -eq 'RAID' -and $media -eq 'SSD' -and ($link -or ($w -and "$($w.PNPDeviceID) $($w.Model)" -match 'NVME'))) { $bus = 'NVMe' }
                $path = '{0}:\LeosMinibench-Benchmark.tmp' -f $vol.DriveLetter
                $label = '{0} ({1}:)' -f $name, $vol.DriveLetter
                try {
                Write-Step ('Benchmark Datenträger {0} (Laufwerk {1}:) ...' -f $name, $vol.DriveLetter)
                Write-Checkpoint 'INFO' ('Datenträger-Benchmark {0} auf {1}' -f $name, $path)
                $task = [DiagDisk]::RunAsync($path, [long]$sizeB, $phase)
                while (-not $task.IsCompleted) { Show-Sub ('Benchmark {0} ({1}:)' -f $name, $vol.DriveLetter) ([DiagDisk]::Phase) ([DiagDisk]::Percent); if ($script:BenchSens -and $script:BenchSens.On) { Add-BenchSensorSample }; Start-Sleep -Milliseconds 400 }
                Hide-Sub
                $res = $task.Result
                if ($res.Error) {
                    Add-Line ('  {0}: Messung fehlgeschlagen: {1}' -f $label, $res.Error)
                    $dErr = [pscustomobject][ordered]@{ Laufwerk = $label; Klasse = ('Fehler: ' + $res.Error); SR = 0; SW = 0; R1 = 0; R8 = 0; W1 = 0; Index = $null; RefPct = $null; Referenz = ''; Status = 'Info'; Vergleich = ''; Hinweis = $res.Error }
                    $script:BenchDisks.Add($dErr)
                    Send-GuiEvent 'BENCH' 'Info' 'Datenträger' $label 'Fehler' '' '' $res.Error '' 'Laufwerke'
                    continue
                }
                $typSeq = $null; $typRnd = $null; $refCls = ''
                if ($bus -eq 'NVMe') {
                    $gen = $(if ($link) { $link.GenNow } else { 0 }); $wid = $(if ($link) { $link.WidthNow } else { 4 })
                    $baseSeq = @{ 1 = 800; 2 = 1500; 3 = 3000; 4 = 5500; 5 = 10000; 6 = 14000 }
                    # ab v2.8: ohne lesbare PCIe-Anbindung (z. B. hinter Intel VMD) die Generation aus dem gemessenen Lesen
                    # ableiten; was schneller liest, als eine Generation kann, muss mindestens die nächste sein. Bis v2.7 galt
                    # pauschal 2.500 MB/s als typisch, eine PCIe-4.0-SSD bekam so Index 268.
                    $genEst = Get-NvmeGenFromSpeed $(if ($link) { 0 } else { $res.SeqReadMBs })
                    if (-not $link -and $genEst) { $gen = $genEst }
                    $typSeq = $(if ($baseSeq.ContainsKey($gen)) { $baseSeq[$gen] * [math]::Min(1.0, [double]$wid / 4.0) } else { 2500 })
                    $typRnd = 14000
                    $cls = $(if ($link) { 'NVMe ' + (Format-Pcie $link) } elseif ($genEst) { 'NVMe PCIe {0}.0 (geschätzt)' -f $genEst } else { 'NVMe' })
                    if ($gen -ge 3 -and $wid -ge 4) { $refCls = 'NVMe' + $gen }
                } elseif ($media -eq 'SSD' -and $bus -in 'SATA', 'SAS', 'RAID', 'ATA') { $typSeq = 530; $typRnd = 9000; $cls = 'SATA-SSD'; $refCls = 'SATA-SSD' }
                elseif ($media -eq 'HDD') { $typSeq = 180; $typRnd = 120; $cls = 'Festplatte'; $refCls = 'HDD' }
                else { $cls = ('{0} {1}' -f $bus, $media).Trim() }
                $iSeq = $(if ($typSeq) { [int][math]::Round($res.SeqReadMBs / $typSeq * 100) } else { $null })
                $iRnd = $(if ($typRnd) { [int][math]::Round($res.Rnd4kQ1Iops / $typRnd * 100) } else { $null })
                $sStat = $(if ($null -eq $iSeq) { 'Info' } elseif ($iSeq -lt 40) { 'Warnung' } elseif ($iSeq -lt 65) { 'Info' } else { 'OK' })
                $rStat = $(if ($null -eq $iRnd) { 'Info' } elseif ($iRnd -lt 30) { 'Info' } else { 'OK' })
                $keyD = 'DISK|' + ([string]$pd.SerialNumber).Trim() + '|' + $name
                $rk = $(if ($refCls) { 'DISK|' + $refCls + '|' } else { '' })
                $m = @(
                    (Add-BenchResult -PassThru -NoGui -Gruppe 'Laufwerke' -Komponente 'Datenträger' -Messung ($label + ' seq. lesen') -Wert ([math]::Round($res.SeqReadMBs)) -Einheit 'MB/s' -Anzeige ('{0:N0} MB/s' -f $res.SeqReadMBs) -Index $iSeq -Status $sStat -Key ($keyD + '|SR') -RefKey $(if ($rk) { $rk + 'SR' }) -Hinweis $(if ($typSeq) { 'typisch für {0}: ca. {1:N0} MB/s' -f $cls, $typSeq } else { $cls })),
                    (Add-BenchResult -PassThru -NoGui -Gruppe 'Laufwerke' -Komponente 'Datenträger' -Messung ($label + ' seq. schreiben') -Wert ([math]::Round($res.SeqWriteMBs)) -Einheit 'MB/s' -Anzeige ('{0:N0} MB/s' -f $res.SeqWriteMBs) -Key ($keyD + '|SW') -RefKey $(if ($rk) { $rk + 'SW' }) -Hinweis ('{0} geschrieben, ohne Windows-Cache' -f (Format-Size $res.TestBytes))),
                    (Add-BenchResult -PassThru -NoGui -Gruppe 'Laufwerke' -Komponente 'Datenträger' -Messung ($label + ' 4K zufällig QD1') -Wert ([math]::Round($res.Rnd4kQ1Iops)) -Einheit 'IOPS' -Anzeige ('{0:N0} IOPS' -f $res.Rnd4kQ1Iops) -Index $iRnd -Status $rStat -Key ($keyD + '|R1') -RefKey $(if ($rk) { $rk + 'R1' }) -Hinweis $(if ($typRnd) { 'typisch für {0}: ca. {1:N0} IOPS' -f $cls, $typRnd } else { '' })),
                    (Add-BenchResult -PassThru -NoGui -Gruppe 'Laufwerke' -Komponente 'Datenträger' -Messung ($label + ' 4K zufällig 8 Threads') -Wert ([math]::Round($res.Rnd4kT8Iops)) -Einheit 'IOPS' -Anzeige ('{0:N0} IOPS' -f $res.Rnd4kT8Iops) -Key ($keyD + '|R8') -RefKey $(if ($rk) { $rk + 'R8' }))
                )
                if ($res.Rnd4kWriteQ1Iops -gt 0) {
                    $m += (Add-BenchResult -PassThru -NoGui -Gruppe 'Laufwerke' -Komponente 'Datenträger' -Messung ($label + ' 4K zufällig schreiben QD1') -Wert ([math]::Round($res.Rnd4kWriteQ1Iops)) -Einheit 'IOPS' -Anzeige ('{0:N0} IOPS' -f $res.Rnd4kWriteQ1Iops) -Key ($keyD + '|W1') -RefKey $(if ($rk) { $rk + 'W1' }))
                }
                $dStat = 'OK'; foreach ($mx in $m) { if ((Get-StatusRank $mx.Status) -gt (Get-StatusRank $dStat)) { $dStat = $mx.Status } }
                $dRef = Get-GeoMean ($m | ForEach-Object { $_.RefPct })
                $dCmp = (@($m | Where-Object { $_.Vergleich } | ForEach-Object { $_.Vergleich }) | Select-Object -First 1)
                $dHint = (@($cls) + @($m | Where-Object { $_.Status -ne 'OK' -or $_.Vergleich -match '^-' } | ForEach-Object { ('{0}: {1} {2}' -f ($_.Messung -replace [regex]::Escape($label + ' '), ''), $_.Anzeige, $_.Vergleich).Trim() })) -join '; '
                $disk = [pscustomobject][ordered]@{ Laufwerk = $label; Klasse = $cls; SR = $res.SeqReadMBs; SW = $res.SeqWriteMBs; R1 = $res.Rnd4kQ1Iops; R8 = $res.Rnd4kT8Iops; W1 = $res.Rnd4kWriteQ1Iops
                    Index = $iSeq; RefPct = $dRef; Referenz = $(if ($null -ne $dRef) { '{0} %' -f $dRef } else { '' }); Status = $dStat; Vergleich = $(if ($dCmp) { $dCmp } else { '' }); Hinweis = $dHint }
                $script:BenchDisks.Add($disk)
                Send-GuiEvent 'BENCH' $dStat 'Datenträger' ('{0} · {1}' -f $label, $cls) ('{0:N0} / {1:N0} MB/s' -f $res.SeqReadMBs, $res.SeqWriteMBs) $(if ($null -ne $iSeq) { $iSeq } else { '' }) $disk.Vergleich `
                    ('Lesen {0:N0} MB/s, Schreiben {1:N0} MB/s, 4K QD1 {2:N0} IOPS, 4K 8 Threads {3:N0} IOPS, 4K schreiben {4:N0} IOPS. {5}' -f $res.SeqReadMBs, $res.SeqWriteMBs, $res.Rnd4kQ1Iops, $res.Rnd4kT8Iops, $res.Rnd4kWriteQ1Iops, $dHint) $disk.Referenz 'Laufwerke'
                if ($sStat -eq 'Warnung') { Add-Finding WARNUNG 'Leistung' ('{0} liest sequentiell nur {1:N0} MB/s, typisch für {2} sind ca. {3:N0} MB/s. Anbindung, Treiber, Füllstand, Temperatur oder Zustand der SSD prüfen.' -f $label, $res.SeqReadMBs, $cls, $typSeq) }
                if ($link -and $link.WidthMax -gt 0 -and $link.WidthNow -lt $link.WidthMax) { Add-Finding WARNUNG 'Leistung' ('{0} ist nur mit x{1} statt x{2} angebunden.' -f $name, $link.WidthNow, $link.WidthMax) }
                if ($link -and $link.GenMax -gt 0 -and $link.GenNow -lt $link.GenMax) { Add-Finding INFO 'Leistung' ('{0} läuft mit PCIe {1}.0, unterstützt aber PCIe {2}.0 (Steckplatz oder Mainboard begrenzt).' -f $name, $link.GenNow, $link.GenMax) }
                } catch { Write-BenchError ('Datenträger ' + $name) $_; Remove-Item $path -Force -ErrorAction SilentlyContinue }
            }
            $okDisks = @($script:BenchDisks | Where-Object { $_.SR -gt 0 })
            if ($okDisks.Count) {
                $fast = $okDisks | Sort-Object SR -Descending | Select-Object -First 1
                $script:BenchHead['Laufwerke'] = '{0} {1} · schnellstes {2:N0} MB/s lesen ({3})' -f $okDisks.Count, $(if ($okDisks.Count -eq 1) { 'Laufwerk' } else { 'Laufwerke' }), $fast.SR, $fast.Klasse
            }
        } catch { Write-BenchError 'Datenträger' $_ }
        Send-BenchGroup 'Laufwerke'
        Add-BenchHeadLine 'Laufwerke'
    }
}

if ($script:BenchSel['WinSAT']) {
    Invoke-Section 'Benchmark: WinSAT-Leistungsbewertung' {
        Initialize-Bench
        Set-BenchSensorPart 'WinSAT'
        Set-BenchPausePart 'WinSAT'
        Write-Step 'winsat formal läuft (ca. 2 bis 5 Minuten) ...'
        $t0 = Get-Date
        $r = Invoke-External -File "$env:windir\System32\winsat.exe" -Arguments 'formal -restart clean' -TimeoutSec 1200 -Progress 'WinSAT Leistungsbewertung' -ExpectedSec 240
        $r.Output | Out-File (Join-Path $RawDir 'winsat.txt') -Encoding UTF8
        if ($r.ExitCode -ne 0) { Add-Line ('  WinSAT Rückgabecode {0} (auf Akku, per Remotedesktop oder in VMs oft nicht möglich).' -f $r.ExitCode) }
        $xmlFile = Get-ChildItem "$env:windir\Performance\WinSAT\DataStore\*Formal.Assessment*.xml" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $fresh = [bool]($xmlFile -and $xmlFile.LastWriteTime -ge $t0.AddMinutes(-1))
        $ws = Get-CimInstance Win32_WinSAT -ErrorAction SilentlyContinue
        if ($ws -and $fresh) {
            $ws | Select-Object @{n = 'CPU'; e = { $_.CPUScore } }, @{n = 'RAM'; e = { $_.MemoryScore } }, @{n = 'Datenträger'; e = { $_.DiskScore } },
                @{n = 'Grafik'; e = { $_.GraphicsScore } }, @{n = 'Spielegrafik'; e = { $_.D3DScore } }, @{n = 'Gesamt'; e = { $_.WinSPRLevel } } | Out-Report
            Add-Line '  Hinweis: Die Spielegrafik-Bewertung ist seit Windows 10 fest auf 9,9 gesetzt und ohne Aussagekraft.'
            foreach ($p in @(@('CPU', 'Prozessor', $ws.CPUScore), @('RAM', 'Arbeitsspeicher', $ws.MemoryScore), @('DISK', 'Systemlaufwerk', $ws.DiskScore), @('GFX', 'Grafik (Desktop)', $ws.GraphicsScore))) {
                $sv = [double]$p[2]
                if ($sv -gt 0) { Add-BenchResult -Gruppe 'WinSAT' -Komponente 'WinSAT' -Messung $p[1] -Wert $sv -Einheit 'von 9,9' -Anzeige ('{0:N1} von 9,9' -f $sv) -Index ([int][math]::Round($sv / 9.9 * 100)) -Status $(if ($sv -lt 4) { 'Info' } else { 'OK' }) -Key ('WINSAT|' + $p[0]) }
            }
            $script:WinsatTotal = [double]$ws.WinSPRLevel
            $script:BenchHead['WinSAT'] = 'Gesamt {0:N1} (niedrigster Teilwert)' -f [double]$ws.WinSPRLevel
            Send-BenchGroup 'WinSAT'
            Add-TestResult 'Leistungsbewertung (WinSAT)' 'OK' ('CPU {0}, RAM {1}, Datenträger {2}, Grafik {3}' -f $ws.CPUScore, $ws.MemoryScore, $ws.DiskScore, $ws.GraphicsScore)
        } else { Add-TestResult 'Leistungsbewertung (WinSAT)' 'Info' ('keine neue Bewertung (Rückgabecode {0})' -f $r.ExitCode) }
        if ($xmlFile -and $fresh) {
            try {
                [xml]$x = Get-Content $xmlFile.FullName -Raw
                Add-Sub 'Messwerte'
                $x.SelectNodes('//Metrics//*[not(*)]') | ForEach-Object {
                    $u = $_.GetAttribute('units')
                    [pscustomobject]@{ Bereich = $_.ParentNode.Name; Messung = $_.Name; Wert = $_.InnerText; Einheit = $u }
                } | Where-Object { $_.Wert -and $_.Bereich -ne 'GamingMetrics' } | Sort-Object Bereich, Messung, Wert -Unique | Select-Object -First 50 | Out-Report
            } catch { }
        }
    }
}


Invoke-Section 'Benchmark: Auswertung und Vergleich' {
    Set-BenchPausePart ''
    $script:BenchPause = $null
    $pg = Stop-PauseWatch -Raw
    if ($pg) {
        $pm = Get-BenchPauseMeasured $script:BenchPauseParts $pg
        $onlyWinSat = ($script:BenchPauseParts.Count -and -not @($script:BenchPauseParts | Where-Object { $_.Teil -ne 'WinSAT' }).Count)
        # nur WinSAT gemessen: keine eigene Messung, deren Werte Unterbrechungen verfälschen könnten
        $script:BenchPause = $(if ($pm.Sekunden -gt 0) { Get-PauseAssessment $pm.Werte $pm.Sekunden } elseif ($onlyWinSat) { $null } else { Get-PauseAssessment $pg ((Get-Date) - $script:BenchT0).TotalSeconds })
    }
    try { Stop-BenchSensors } catch { }
    $inv = $script:Inv
        # ---------------- Zusammenfassung, Verlauf, Referenz, CSV ----------------
        Initialize-Bench
        if (-not $script:BenchResults.Count -and -not $script:BenchDisks.Count) { Add-Line '  Keine Messwerte vorhanden.'; Add-TestResult 'Benchmark' 'Info' 'keine Messwerte'; return }
        Add-Sub 'Ergebnisse'
        if ($script:BenchPause) {
            Add-Line ('  Unterbrechungen während der Messungen: {0}{1}' -f $script:BenchPause.Text, $(if (@($script:BenchPauseParts | Where-Object { $_.Teil -eq 'WinSAT' }).Count) { '; WinSAT läuft als eigener Prozess und zählt nicht mit' } else { '' }))
            $pl = @($script:BenchPauseParts | Where-Object { $_.Von -and $_.Bis } | ForEach-Object { '{0} {1:N0} ({2:N1} s)' -f $_.Teil, ([double]$_.Bis[0] - [double]$_.Von[0]), (([double]$_.Bis[2] - [double]$_.Von[2]) / 1000.0) })
            if ($pl.Count -gt 1) { Add-Line ('  Je Abschnitt: {0}' -f ($pl -join ', ')) }
            if ($script:BenchPause.Auffaellig) { Add-Finding INFO 'Benchmark' ('Die Messungen liefen nicht ohne Unterbrechung: {0}. Einzelne Werte können dadurch etwas niedriger ausfallen.' -f $script:BenchPause.Text) }
        }
        $sumParts = @()
        foreach ($gk in $script:BenchGroupOrder) {
            $g = Get-BenchGroup $gk
            if (-not $g.Anzahl) { continue }
            if ($null -ne $g.RefPct) { $sumParts += ('{0} {1} %' -f $gk, $g.RefPct) }
            Add-Line
            Add-Line ('  {0}   [{1}]{2}' -f $g.Name.ToUpper(), $g.Status, $(if ($g.Referenz) { '   Referenz ' + $g.Referenz } else { '' }))
            if ($g.Kopf) { Add-Line ('  ' + $g.Kopf) }
            if ($gk -eq 'Laufwerke') {
                $fz = { param($v) if ([double]$v -gt 0) { '{0:N0}' -f [double]$v } else { '' } }
                $g.Disks | Select-Object Status, Laufwerk, Klasse, @{n = 'Lesen'; e = { & $fz $_.SR } }, @{n = 'Schreiben'; e = { & $fz $_.SW } }, @{n = '4K QD1'; e = { & $fz $_.R1 } },
                    @{n = '4K 8T'; e = { & $fz $_.R8 } }, @{n = '4K Schr.'; e = { & $fz $_.W1 } }, Index, Referenz, Vergleich | Out-Report
                Add-Line '  Lesen und Schreiben in MB/s, 4K-Werte in IOPS.'
            } else {
                $g.Items | Select-Object Status, Messung, @{n = 'Wert'; e = { $_.Anzeige } }, Index, Referenz, Vergleich, Hinweis | Out-Report
            }
        }
        $script:BenchRefSummary = $(if ($sumParts.Count) { 'Im Vergleich zur Referenz {0}: {1}' -f $script:Ref.Name, ($sumParts -join ', ') } else { '' })
        if ($script:BenchRefSummary) { Add-Line; Add-Line ('  ' + $script:BenchRefSummary) }
        # Herkunft der Referenzwerte (Lauf, aus dem die gespeicherte Referenz je Messgröße stammt)
        $script:BenchRefRows = @(Get-ReferenceRows)
        if ($script:BenchRefRows.Count) {
            Add-Sub ('Referenzwerte: {0}' -f $script:Ref.Name)
            $script:BenchRefRows | Select-Object Messgröße, Referenz, Herkunft | Out-Report
        }
        $refParts = @(@((($script:BenchShort.CPU -as [string]) -replace '^(AMD|Intel)\s*', ''), $script:BenchShort.RAM, $script:BenchShort.GPU) | Where-Object { $_ })
        $script:BenchRefName = ('{0} ({1})' -f [Environment]::MachineName, ($refParts -join ', '))
        Add-BenchComparison
        if ($ReferenzSpeichern) {
            if ($BenchmarkKurz) { Add-Line '  Hinweis: Referenz aus einem Kurzlauf gespeichert, Werte mit voller Messdauer sind stabiler.' }
            $saved = @(Save-BenchReference)
            if ($saved.Count) { $script:RefSavedNow = $true; Add-Line ('  Referenz gespeichert: {0}' -f ($saved -join ', ')); Add-Finding INFO 'Leistung' ('Dieser PC ist jetzt die Referenz (100 %) für alle PCs, die mit diesem Datenordner arbeiten.') }
        }
        try {
            $script:BenchResults | Select-Object @{n = 'Computer'; e = { $env:COMPUTERNAME } }, @{n = 'Modell'; e = { $script:Facts['System'] } }, @{n = 'Datum'; e = { (Get-Date).ToString('yyyy-MM-dd HH:mm', $inv) } },
                Gruppe, Komponente, Messung, @{n = 'Wert'; e = { $_.Wert.ToString($inv) } }, Einheit, Index, Status, Referenz, Vergleich, Hinweis |
                Export-Csv -Path (Join-Path $RawDir 'Benchmark.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
            Add-Line '  Rohwerte für den Vergleich mehrerer PCs: Benchmark.csv im Anhang'
        } catch { }
        $bw = @($script:BenchResults | Where-Object Status -eq 'Warnung').Count
        $grps = @($script:BenchGroupOrder | Where-Object { (Get-BenchGroup $_).Anzahl })
        $want = @(@{ CPU = 'CPU'; RAM = 'RAM'; GPU = 'GPU'; Disk = 'Laufwerke'; WinSAT = 'WinSAT' }.GetEnumerator() | Where-Object { $script:BenchSel[$_.Key] } | ForEach-Object { $_.Value })
        $missing = @($want | Where-Object { $grps -notcontains $_ })
        Add-TestResult 'Benchmark' $(if ($bw) { 'Warnung' } elseif ($missing.Count) { 'Info' } else { 'OK' }) ('{0} Messwerte für {1}, {2} auffällig{3}{4}' -f $script:BenchResults.Count, ($grps -join ', '), $bw,
            $(if ($missing.Count) { ', ohne Ergebnis: ' + ($missing -join ', ') } else { '' }), $(if ($sumParts.Count) { '. Referenz: ' + ($sumParts -join ', ') } else { '' }))
        # ab v2.7: Temperatur, Takt und Leistung während der Messungen (wie nach dem Lasttest)
        try { Write-BenchSensorReport } catch { Add-Line ('  Sensorauswertung nicht möglich: {0}' -f $_.Exception.Message) }
}
}   # Ende: if ($ModBench)


