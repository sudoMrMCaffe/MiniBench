#region ---------- SMART-Hilfsfunktionen ----------
function Get-SmartTestState($Device) {
    $res = [pscustomobject]@{ Running = $false; Percent = $null; Minutes = $null }
    $r = Invoke-External -File $script:Smartctl -Arguments ('-c -l selftest -j -d {0} {1}' -f $Device.type, $Device.name) -TimeoutSec 60
    try { $j = $r.Output | ConvertFrom-Json } catch { return $res }
    if ($j.device.protocol -eq 'NVMe') {
        $op = $j.nvme_self_test_log.current_self_test_operation.value
        if ($op -and [int]$op -ne 0) { $res.Running = $true; $res.Percent = $j.nvme_self_test_log.current_self_test_completion_percent }
        if ($j.nvme_controller_capabilities -and $j.nvme_controller_capabilities.self_test_extended_minutes) { $res.Minutes = $j.nvme_controller_capabilities.self_test_extended_minutes }
    } else {
        $st = $j.ata_smart_data.self_test.status
        if ($st -and [int]$st.value -ge 240 -and [int]$st.value -le 255) { $res.Running = $true; $res.Percent = 100 - [int]$st.remaining_percent }
        $res.Minutes = $j.ata_smart_data.self_test.polling_minutes.extended
    }
    return $res
}

function Test-SmartJson {
    param($Json, [string]$Label)
    $j = $Json
    $isNvme = ($j.device.protocol -eq 'NVMe')
    $crit = New-Object System.Collections.ArrayList
    $passed = $j.smart_status.passed
    if ($passed -eq $false) { Add-Finding KRITISCH 'SMART' ('{0}: SMART-Gesamtstatus FAILED.' -f $Label); [void]$crit.Add('SMART FAILED') }
    $temp = $j.temperature.current
    $life = $null; $written = $null
    if ($isNvme) {
        $n = $j.nvme_smart_health_information_log
        if ($n) {
            $life = 100 - [int]$n.percentage_used
            $written = [double]$n.data_units_written * 512000
            if ($n.critical_warning -ne 0) { Add-Finding KRITISCH 'SMART' ('{0}: NVMe Critical Warning = {1}.' -f $Label, $n.critical_warning); [void]$crit.Add('CriticalWarning') }
            if ($n.media_errors -gt 0) { Add-Finding KRITISCH 'SMART' ('{0}: {1} Medienfehler (Media Errors).' -f $Label, $n.media_errors); [void]$crit.Add("MediaErr $($n.media_errors)") }
            if ($n.available_spare -lt $n.available_spare_threshold) { Add-Finding KRITISCH 'SMART' ('{0}: Reserveblöcke unter Schwelle ({1} %).' -f $Label, $n.available_spare); [void]$crit.Add('Spare') }
            if ($n.percentage_used -ge 90) { Add-Finding KRITISCH 'SMART' ('{0}: Lebensdauer zu {1} % verbraucht.' -f $Label, $n.percentage_used) }
            elseif ($n.percentage_used -ge 70) { Add-Finding WARNUNG 'SMART' ('{0}: Lebensdauer zu {1} % verbraucht.' -f $Label, $n.percentage_used) }
            if ($n.unsafe_shutdowns -gt 200) { Add-Finding INFO 'SMART' ('{0}: {1} unsaubere Abschaltungen.' -f $Label, $n.unsafe_shutdowns) }
            if ($temp -ge 75) { Add-Finding WARNUNG 'SMART' ('{0}: Temperatur {1} °C.' -f $Label, $temp) }
        }
    } else {
        $attrs = $j.ata_smart_attributes.table
        foreach ($a in $attrs) {
            $raw = [double]$a.raw.value
            if ($a.when_failed -eq 'now') { Add-Finding KRITISCH 'SMART' ('{0}: Attribut {1} {2} unter Schwellwert.' -f $Label, $a.id, $a.name); [void]$crit.Add("$($a.id) FAIL") }
            elseif ($a.when_failed -eq 'past') { Add-Finding WARNUNG 'SMART' ('{0}: Attribut {1} {2} war früher unter Schwellwert.' -f $Label, $a.id, $a.name) }
            switch ([int]$a.id) {
                5   { if ($raw -gt 0) { Add-Finding WARNUNG  'SMART' ('{0}: {1} reallokierte Sektoren.' -f $Label, $raw); [void]$crit.Add("Realloc $raw") } }
                187 { if ($raw -gt 0) { Add-Finding WARNUNG  'SMART' ('{0}: {1} gemeldete unkorrigierbare Fehler.' -f $Label, $raw); [void]$crit.Add("Uncorr $raw") } }
                196 { if ($raw -gt 0) { Add-Finding WARNUNG  'SMART' ('{0}: {1} Reallokierungsereignisse.' -f $Label, $raw) } }
                197 { if ($raw -gt 0) { Add-Finding KRITISCH 'SMART' ('{0}: {1} schwebende Sektoren (Pending).' -f $Label, $raw); [void]$crit.Add("Pending $raw") } }
                198 { if ($raw -gt 0) { Add-Finding KRITISCH 'SMART' ('{0}: {1} Offline-unkorrigierbare Sektoren.' -f $Label, $raw); [void]$crit.Add("OfflUnc $raw") } }
                199 { if ($raw -gt 0) { Add-Finding INFO     'SMART' ('{0}: {1} CRC-Übertragungsfehler (Kabel/Anschluss prüfen).' -f $Label, $raw) } }
                { $_ -in 177, 202, 231, 233 } { if ($null -eq $life -and $a.value -le 100) { $life = [int]$a.value } }
                { $_ -in 241, 246 } { if ($null -eq $written) { $written = $raw * 512 } }
            }
        }
        if ($written -and $written -lt 1GB -and $j.power_on_time.hours -gt 100) { $written = $written / 512 * 1GB }   # manche Hersteller zählen in GiB
        $pcy = [double]$j.power_cycle_count; $poh = [double]$j.power_on_time.hours
        if ($pcy -gt 20000 -and $poh -gt 0 -and ($pcy / $poh) -gt 2) { Add-Finding INFO 'SMART' ('{0}: ungewöhnlich viele Einschaltzyklen ({1:N0} bei {2:N0} Betriebsstunden), meist durch Energiesparfunktionen der SATA-Verbindung.' -f $Label, $pcy, $poh) }
        if ($null -ne $life -and $life -le 10) { Add-Finding KRITISCH 'SMART' ('{0}: Restlebensdauer {1} %.' -f $Label, $life) }
        elseif ($null -ne $life -and $life -le 30) { Add-Finding WARNUNG 'SMART' ('{0}: Restlebensdauer {1} %.' -f $Label, $life) }
        if ($temp -ge 55) { Add-Finding WARNUNG 'SMART' ('{0}: Temperatur {1} °C.' -f $Label, $temp) }
        $errCount = $j.ata_smart_error_log.summary.count
        if ($errCount -gt 0) { Add-Finding INFO 'SMART' ('{0}: {1} Einträge im ATA-Fehlerprotokoll.' -f $Label, $errCount) }
    }
    [pscustomobject][ordered]@{
        'Laufwerk'      = $Label
        'Protokoll'     = $j.device.protocol
        'Seriennummer'  = $j.serial_number
        'Firmware'      = $j.firmware_version
        'Größe'         = Format-Size $j.user_capacity.bytes
        'SMART'         = $(if ($passed -eq $true) { 'OK' } elseif ($passed -eq $false) { 'FAILED' } else { '?' })
        'Temp °C'       = $temp
        'Betriebsstd.'  = $j.power_on_time.hours
        'Einschaltz.'   = $j.power_cycle_count
        'Restleben %'   = $life
        'Geschrieben'   = $(if ($written) { Format-SizeDec $written })
        'Auffällig'     = ($crit -join ', ')
    }
}

#endregion


#region ---------- Neue Auswertungen: Installationsalter, RAM-Profil, Abschaltungen, Datenträgerzuordnung ----------
function Format-Age([double]$Days, [switch]$Dativ) {
    # Dativ für "vor ...", sonst Nominativ für "... alt"
    $n = $(if ($Dativ) { 'n' } else { '' })
    if ($Days -lt 1) { return 'weniger als 1 Tag' }
    if ($Days -lt 2) { return '1 Tag' }
    if ($Days -lt 61) { return ('{0:N0} Tage{1}' -f [math]::Floor($Days), $n) }
    if ($Days -lt 730) { return ('{0:N0} Monate{1}' -f [math]::Floor($Days / 30.44), $n) }
    $y = [math]::Floor($Days / 365.25); $m = [math]::Floor(($Days - $y * 365.25) / 30.44)
    if ($m -ge 1) { return ('{0} Jahre{2} {1} Monat{3}' -f $y, $m, $n, $(if ($m -eq 1) { $(if ($Dativ) { '' } else { '' }) } else { 'e' + $n })) }
    return ('{0} Jahre{1}' -f $y, $n)
}

# Windows-Installationsverlauf: InstallDate wird bei jedem Funktionsupdate (Inplace-Upgrade) neu gesetzt.
# Die Schlüssel "Source OS (Updated on ...)" enthalten die Daten der vorherigen Installationen.
function Get-WindowsInstallInfo {
    $fromUnix = { param($v) try { if ($v -and [int64]$v -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$v).LocalDateTime } } catch { } }
    $en = [Globalization.CultureInfo]::GetCultureInfo('en-US')
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $cur = & $fromUnix $cv.InstallDate
    if (-not $cur) { try { $cur = (Get-CimCached Win32_OperatingSystem | Select-Object -First 1).InstallDate } catch { } }
    $hist = @(Get-ChildItem 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'Source OS*' } | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        $inst = & $fromUnix $p.InstallDate
        $upd = $null
        if ($_.PSChildName -match 'Updated on (.+)\)') { $t = [datetime]::MinValue; if ([datetime]::TryParse($Matches[1], $en, [Globalization.DateTimeStyles]::None, [ref]$t)) { $upd = $t } }
        if ($inst) {
            [pscustomobject]@{ Installiert = $inst; Ersetzt = $upd; Version = $(if ($p.DisplayVersion) { $p.DisplayVersion } else { $p.ReleaseId })
                Build = ('{0}.{1}' -f $p.CurrentBuild, $p.UBR).Trim('.'); Produkt = $p.ProductName }
        }
    } | Sort-Object Installiert)
    $first = $cur
    foreach ($h in $hist) { if (-not $first -or $h.Installiert -lt $first) { $first = $h.Installiert } }
    $winOld = Get-Item "$env:SystemDrive\Windows.old" -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Erstinstallation = $first
        AktuellSeit      = $cur
        Upgrades         = $hist
        AlterTage        = $(if ($first) { ((Get-Date) - $first).TotalDays } else { $null })
        WindowsOld       = $(if ($winOld) { $winOld.CreationTime } else { $null })
    }
}

# Nenntakt aus der Teilenummer bekannter Hersteller (XMP/EXPO-Kits), Rückgabe in MT/s
function Get-RamRatedSpeed([string]$Part) {
    $p = ([string]$Part).Trim().ToUpperInvariant()
    if (-not $p) { return $null }
    switch -Regex ($p) {
        '^F[345]-(\d{4})'                 { return [int]$Matches[1] }          # G.Skill F4-3200C16-8GVKB, F5-6000J3038F16G
        '^CM[A-Z0-9]*X[345]M\d[A-Z](\d{4})' { return [int]$Matches[1] }        # Corsair CMK16GX4M2B3200C16, CMH32GX5M2B6000C30
        '^KHX(\d{4})C'                    { return [int]$Matches[1] }          # Kingston HyperX KHX3200C16D4/16GX
        '^KF[345](\d{2})C'                { return [int]$Matches[1] * 100 }    # Kingston Fury KF432C16BB/16, KF560C36BBE
        '^BLS?\d+G(\d{2})C'               { return [int]$Matches[1] * 100 }    # Crucial Ballistix BL8G32C16U4B
        '^CP\d+G(\d{2})C'                 { return [int]$Matches[1] * 100 }    # Crucial Pro CP16G56C46U5
        '^TF\w*?(\d{4})HC\d'              { return [int]$Matches[1] }          # TeamGroup T-Force TF3D416G3200HC16F
        '^PV\w*?\d+G(\d{3,4})C'           { $v = [int]$Matches[1]; if ($v -lt 1000) { $v *= 10 }; return $v }   # Patriot PVS416G320C6
        '^AX[45]U(\d{4})'                 { return [int]$Matches[1] }          # ADATA XPG AX4U320016G16A
    }
    return $null
}

# Kernel-Power 41 einordnen: Bluescreen, Ein/Aus-Taste, Standby, Herunterfahren oder Betrieb
function Get-PowerLossInfo($Events) {
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($ev in @($Events | Select-Object -First 15)) {
        $d = @{}
        try { foreach ($n in ([xml]$ev.ToXml()).Event.EventData.Data) { $d[[string]$n.Name] = [string]$n.'#text' } } catch { }
        $bug = 0L; [void][int64]::TryParse([string]$d['BugcheckCode'], [ref]$bug)
        $sleep = 0; [void][int]::TryParse([string]$d['SleepInProgress'], [ref]$sleep)
        $btn = 0L; [void][int64]::TryParse([string]$d['PowerButtonTimestamp'], [ref]$btn)
        $bootT = $ev.TimeCreated.AddMinutes(-1)
        try {
            $b = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 12; StartTime = $ev.TimeCreated.AddMinutes(-15); EndTime = $ev.TimeCreated } -MaxEvents 1 -ErrorAction Stop
            if ($b) { $bootT = $b.TimeCreated }
        } catch { }
        $prev = $null
        try { $prev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; EndTime = $bootT.AddSeconds(-2) } -MaxEvents 1 -ErrorAction Stop } catch { }
        $pid2 = $(if ($prev) { '{0} {1}' -f $prev.ProviderName, $prev.Id } else { '' })
        $kat = 'Betrieb'
        if ($bug -ne 0) { $kat = 'Bluescreen' }
        elseif ($btn -ne 0 -or [string]$d['LongPowerButtonPressDetected'] -eq 'true') { $kat = 'Taste' }
        elseif ($sleep -ne 0 -or ($prev -and $prev.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $prev.Id -in 42, 506)) { $kat = 'Standby' }
        elseif ($prev -and (($prev.ProviderName -eq 'Microsoft-Windows-Kernel-General' -and $prev.Id -eq 13) -or ($prev.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $prev.Id -eq 109) -or ($prev.ProviderName -eq 'User32' -and $prev.Id -eq 1074) -or ($prev.ProviderName -eq 'EventLog' -and $prev.Id -eq 6006))) { $kat = 'Herunterfahren' }
        $text = switch ($kat) {
            'Bluescreen'     { 'Bluescreen 0x{0:X} {1}' -f $bug, (Get-BugcheckName $bug) }
            'Taste'          { 'Ein/Aus-Taste lang gedrückt (erzwungenes Ausschalten, PC hing vermutlich)' }
            'Standby'        { 'Strom im Energiesparmodus verloren oder Aufwachen fehlgeschlagen' }
            'Herunterfahren' { 'beim oder nach dem Herunterfahren abgeschaltet (z. B. Steckdosenleiste bei aktivem Schnellstart)' }
            default          { 'Absturz oder Stromverlust im laufenden Betrieb' }
        }
        $out.Add([pscustomobject]@{ Neustart = $ev.TimeCreated; 'Letzte Aktivität' = $(if ($prev) { $prev.TimeCreated }); 'Letztes Ereignis' = $pid2; Kategorie = $kat; Einordnung = $text })
    }
    return $out.ToArray()
}

# Datenträgernummern in Ereignistexten den aktuellen Laufwerken zuordnen
function Get-DiskRefText($Events) {
    if (-not $script:DiskNames) {
        $script:DiskNames = @{}
        try { Get-PhysicalDisk -ErrorAction Stop | ForEach-Object { $script:DiskNames[[int]$_.DeviceId] = ('{0} ({1})' -f ([string]$_.FriendlyName).Trim(), $_.BusType) } } catch { }
    }
    $nums = @{}
    foreach ($e in $Events) {
        $m = [string]$e.Message
        foreach ($rx in 'Harddisk(\d+)', 'Datenträger "(\d+)"', '[Dd]isk (\d+)\b') { foreach ($mm in [regex]::Matches($m, $rx)) { $nums[[int]$mm.Groups[1].Value] = $true } }
    }
    if (-not $nums.Count) { return '' }
    $parts = foreach ($n in ($nums.Keys | Sort-Object)) {
        if ($script:DiskNames.ContainsKey($n)) { 'Datenträger {0} = {1}' -f $n, $script:DiskNames[$n] }
        else { 'Datenträger {0} ist derzeit nicht vorhanden (ausgefallen, abgezogen oder USB)' -f $n }
    }
    return (' Betroffen (Nummer zum Zeitpunkt des Ereignisses): {0}.' -f ($parts -join '; '))
}
#endregion

