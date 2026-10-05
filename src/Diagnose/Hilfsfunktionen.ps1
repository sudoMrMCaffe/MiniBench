# XMP/EXPO-Prüfung: Nenntakt laut Teilenummer gegen den Betriebstakt
function Test-RamProfile($Mods, [string]$TypeName) {
    $mods = @($Mods)
    if (-not $mods.Count) { return }
    $rated = @($mods | ForEach-Object { Get-RamRatedSpeed ([string]$_.PartNumber) } | Where-Object { $_ })
    $cfg = [int](($mods | Where-Object { $_.ConfiguredClockSpeed } | Measure-Object ConfiguredClockSpeed -Minimum).Minimum)
    if ($rated.Count -ne $mods.Count -or $cfg -le 0) { return }
    $rMin = [int](($rated | Measure-Object -Minimum).Minimum)
    $parts = (@($mods | ForEach-Object { ([string]$_.PartNumber).Trim() }) | Select-Object -Unique) -join ', '
    if ($rMin -gt $cfg * 1.05) {
        $gain = ($rMin / $cfg - 1) * 100
        Add-Line ('  Nenntakt laut Teilenummer: {0} MT/s, Betriebstakt: {1} MT/s. Das XMP/EXPO-Profil ist vermutlich nicht aktiv.' -f $rMin, $cfg)
        Add-Finding $(if ($gain -ge 20) { 'WARNUNG' } else { 'INFO' }) 'RAM' ('Die RAM-Module ({0}) sind für {1}-{2} ausgelegt, laufen aber nur mit {3} MT/s. Im BIOS das XMP-, EXPO- oder DOCP-Profil aktivieren (rund {4:N0} % mehr Speichertakt) und danach die Stabilität mit RAM- und Lasttest prüfen.' -f $parts, $(if ($TypeName) { $TypeName } else { 'RAM' }), $rMin, $cfg, $gain)
    } elseif ($rMin -le $cfg + 50) {
        Add-Line ('  Nenntakt laut Teilenummer: {0} MT/s, das Speicherprofil (XMP/EXPO) ist aktiv.' -f $rMin)
        $script:RamProfileActive = $true
    }
}

function Get-ShortCpuName([string]$Name) { ((($Name -as [string]) -replace '\s+', ' ').Trim() -replace '\s*(\d+-Core|Processor|CPU @.*$)', '' -replace '\((R|TM)\)', '').Trim() }
function Get-ShortGpuName([string]$Name) { (([string]$Name) -replace '^(AMD|NVIDIA|Intel\(R\))\s*', '').Trim() }
# Grafikeinheiten mit Art (dGPU, iGPU) und ob sie den Desktop ausgibt (aktive Auflösung); virtuelle Adapter fehlen
function Get-GpuAdapters {
    @(Get-CimCached Win32_VideoController | Where-Object { $_ -and (Get-GpuKind ([string]$_.Name)) -ne 'virtuell' } | ForEach-Object {
        $k = Get-GpuKind ([string]$_.Name)
        [pscustomobject]@{ Name = ([string]$_.Name).Trim(); Art = $k; Desktop = [bool]$_.CurrentHorizontalResolution; Treiber = [string]$_.DriverVersion; Adapter = $_
            Bezeichnung = $(switch ($k) { 'dGPU' { 'Grafikkarte' } 'iGPU' { 'Prozessorgrafik' } default { 'Grafik' } }) }
    })
}
# Leitkarte: dedizierte Grafikkarte vor Prozessorgrafik
function Get-MainGpu {
    $all = @(Get-GpuAdapters)
    $d = @($all | Where-Object { $_.Art -eq 'dGPU' })
    $m = @(@($d) + @($all)) | Select-Object -First 1
    if ($m) { return $m.Adapter }
    return $null
}
# Inventarzeile: alle Grafikeinheiten mit Art, die den Desktop ausgebende markiert
function Get-GpuFactText {
    $all = @(Get-GpuAdapters | Sort-Object { if ($_.Art -eq 'dGPU') { 0 } else { 1 } })
    if ($all.Count -le 1) { return (@($all | ForEach-Object { $_.Name }) -join '') }
    return ((@($all | ForEach-Object { '{0} ({1}{2})' -f $_.Name, $_.Bezeichnung, $(if ($_.Desktop) { ', Desktop' } else { '' }) })) -join '; ')
}

# WinSAT speichert die Treiberversion des gemessenen Adapters als 64-Bit-Zahl (4 x 16 Bit): 9007199261367216 = 32.0.101.7088
function ConvertFrom-WinsatDriverVersion([string]$Text) {
    $v = [uint64]0
    if (-not [uint64]::TryParse(([string]$Text).Trim(), [ref]$v) -or $v -eq 0) { return '' }
    return ('{0}.{1}.{2}.{3}' -f ($v -shr 48), (($v -shr 32) -band 0xFFFF), (($v -shr 16) -band 0xFFFF), ($v -band 0xFFFF))
}

# Ergebnis von winsat dwm -xml: Durchsatz, Bilder/s und Angaben zum gemessenen Adapter
function Read-WinsatDwmXml([string]$Path) {
    $o = [pscustomobject]@{ Vmb = $null; Fps = $null; Treiber = ''; Dediziert = $null; Geteilt = $null }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $o }
    try {
        [xml]$x = Get-Content -LiteralPath $Path -Raw
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $n = $x.SelectSingleNode('//VideoMemBandwidth'); if ($n) { $o.Vmb = [double]::Parse($n.InnerText.Trim(), $inv) }
        $n = $x.SelectSingleNode('//DWMFps'); if ($n) { $o.Fps = [double]::Parse($n.InnerText.Trim(), $inv) }
        $n = $x.SelectSingleNode('//DriverVersion'); if ($n) { $o.Treiber = ConvertFrom-WinsatDriverVersion $n.InnerText }
        $n = $x.SelectSingleNode('//DedicatedVideoMemory'); if ($n) { $o.Dediziert = [double]::Parse($n.InnerText.Trim(), $inv) }
        $n = $x.SelectSingleNode('//SharedSystemMemory'); if ($n) { $o.Geteilt = [double]::Parse($n.InnerText.Trim(), $inv) }
    } catch { }
    return $o
}

# Welche Grafikeinheit hat WinSAT gemessen? Zuerst über die Treiberversion, sonst über den eigenen Grafikspeicher
# (unter 1 GB = Prozessorgrafik), zuletzt die Einheit, die den Desktop ausgibt.
function Resolve-WinsatAdapter($Result, $Adapters) {
    $all = @($Adapters)
    if (-not $all.Count) { return $null }
    if ($all.Count -eq 1) { return $all[0] }
    if ($Result.Treiber) { $m = @($all | Where-Object { $_.Treiber -eq $Result.Treiber }); if ($m.Count -eq 1) { return $m[0] } }
    if ($null -ne $Result.Dediziert) {
        $want = $(if ($Result.Dediziert -lt 1GB) { 'iGPU' } else { 'dGPU' })
        $m = @($all | Where-Object { $_.Art -eq $want }); if ($m.Count -ge 1) { return $m[0] }
    }
    $m = @($all | Where-Object { $_.Desktop }); if ($m.Count) { return $m[0] }
    return $all[0]
}


# Einträge der Systemdateiprüfung aus CBS.log ab einem Zeitpunkt (Prüf- und Reparaturmodus)
function Get-CbsEntries([datetime]$Since) {
    $res = [pscustomobject]@{ Cannot = @(); Corrupt = @(); Files = @() }
    $cbs = "$env:windir\Logs\CBS\CBS.log"
    if (-not (Test-Path $cbs)) { return $res }
    $lines = @(Select-String -Path $cbs -Pattern '\[SR\]|Hashes for file member|do not match|corrupt' -ErrorAction SilentlyContinue | ForEach-Object {
        $t = [datetime]::MinValue
        if ($_.Line.Length -ge 19 -and [datetime]::TryParseExact($_.Line.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$t) -and $t -ge $Since.AddMinutes(-1)) { $_.Line }
    })
    $res.Cannot  = @($lines | Where-Object { $_ -match 'Cannot repair' })
    $res.Corrupt = @($lines | Where-Object { $_ -match 'corrupt|Repaired|Repairing|do not match|Hashes for file member|Cannot verify' -and $_ -notmatch 'Repairing 0 components|\b0 corrupt|Verify complete|Beginning Verify' })
    # Dateiname in Anführungszeichen vollständig übernehmen (auch mit mehreren Punkten wie Microsoft.Windows.Shell.dll)
    $res.Files   = @(($res.Cannot + $res.Corrupt) | ForEach-Object { foreach ($m in [regex]::Matches($_, "\[l:\d+(?:\{\d+\})?\](?:['""]([^'""]+?\.[A-Za-z0-9]{2,8})['""]|([^\s'""\]]+\.[A-Za-z0-9]{2,8})\b)")) { if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value } } } | Select-Object -Unique)
    return $res
}

# DISM und SFC gemeinsam einordnen. Rückgabe: Kategorie (fuer KI-Datei und Bericht), Stufe und Befund (leer = kein Befund).
#   keine Verletzungen            sfc sauber, DISM intakt oder nicht geprüft
#   Abweichungen, Speicher intakt einzelne Hash-Abweichungen bei intaktem DISM: meist folgenlos, INFO
#   reparierbar                   DISM Repairable: ein WARNUNG-Befund für beides
#   nicht reparierbar             DISM NonRepairable oder nicht reparierbare SFC-Einträge
function Get-IntegrityAssessment {
    param([string]$DismState = '', [bool]$SfcClean = $false, [bool]$SfcViolations = $false, [int]$CannotRepair = 0, [int]$Corrupt = 0, [string[]]$Files = @())
    $f = @($Files | Where-Object { $_ })
    $fileTxt = $(if ($f.Count) { ' Betroffen: {0}{1}.' -f (($f | Select-Object -First 8) -join ', '), $(if ($f.Count -gt 8) { ' und {0} weitere' -f ($f.Count - 8) } else { '' }) } else { '' })
    $sfcBad = $SfcViolations -or $Corrupt -gt 0
    $o = [ordered]@{ Kategorie = 'keine Verletzungen'; Einordnung = ''; Stufe = ''; Befund = ''; Dism = $(if ($DismState) { $DismState } else { 'nicht geprüft' }); Sfc = $(if ($SfcClean) { 'keine Integritätsverletzungen' } elseif ($sfcBad) { 'Integritätsverletzungen' } else { 'ohne klares Ergebnis' }); Dateien = $f.Count }
    if ($DismState -and $DismState -notin 'Healthy', 'Repairable') {
        $o.Kategorie = 'nicht reparierbar'; $o.Stufe = 'KRITISCH'
        $o.Befund = ('Komponentenspeicher: {0}, DISM kann ihn nicht reparieren.{1} Abhilfe: Inplace-Upgrade mit dem Windows-Installationsmedium (Dateien und Programme bleiben erhalten).' -f $DismState, $fileTxt)
    } elseif ($DismState -eq 'Repairable') {
        $o.Kategorie = 'reparierbar'; $o.Stufe = 'WARNUNG'
        $o.Befund = ('Komponentenspeicher beschädigt, aber reparierbar{0}.{1} Abhilfe: Reparaturmodul (DISM RestoreHealth, danach sfc /scannow).' -f $(if ($sfcBad) { '; sfc meldet deshalb auch Integritätsverletzungen' } else { '' }), $fileTxt)
    } elseif ($CannotRepair -gt 0) {
        $o.Kategorie = 'nicht reparierbar'; $o.Stufe = 'WARNUNG'
        $o.Befund = ('sfc meldet {0} nicht reparierbare Einträge.{1} Abhilfe: Reparaturmodul (DISM RestoreHealth, danach sfc /scannow); hilft das nicht, Inplace-Upgrade.' -f $CannotRepair, $fileTxt)
    } elseif ($sfcBad -and $DismState -eq 'Healthy') {
        $o.Kategorie = 'Abweichungen, Speicher intakt'; $o.Stufe = 'INFO'
        $o.Befund = ('sfc /verifyonly meldet Abweichungen, der Komponentenspeicher ist intakt.{0} Einzelne Hash-Abweichungen sind dann meist folgenlos (häufig nach Updates); sfc /scannow behebt sie aus dem intakten Speicher, nötig ist das nur bei Beschwerden.' -f $fileTxt)
    } elseif ($sfcBad) {
        $o.Kategorie = 'Verletzungen, Speicher nicht geprüft'; $o.Stufe = 'WARNUNG'
        $o.Befund = ('SFC hat Integritätsverletzungen gefunden, der Komponentenspeicher wurde nicht geprüft.{0} Abhilfe: Reparaturmodul (DISM RestoreHealth, danach sfc /scannow).' -f $fileTxt)
    }
    $o.Einordnung = ('{0} (DISM: {1}, SFC: {2})' -f $o.Kategorie, $o.Dism, $o.Sfc)
    return [pscustomobject]$o
}

# ---------- Akkubericht (powercfg /batteryreport) ----------
# Bevorzugt die XML-Fassung (/xml, Zahlen ohne Tausendertrennzeichen), sonst die HTML-Fassung. Rückgabe je Akku:
# Name, Hersteller, Chemie, DesignmWh, VollmWh, VerschleissProzent, Zyklen, LaufzeitVoll und LaufzeitDesign (TimeSpan),
# Verlauf (Zeitraum, VollmWh, DesignmWh). Fehlende Werte bleiben $null.
function Get-XmlLocal($Node, [string]$Name) {
    if (-not $Node) { return $null }
    if ($Node.Attributes) { foreach ($a in $Node.Attributes) { if ($a.LocalName -eq $Name) { return [string]$a.Value } } }
    foreach ($c in @($Node.ChildNodes)) { if ($c.LocalName -eq $Name) { return [string]$c.InnerText } }
    return $null
}
function ConvertTo-NullableNumber($v) {
    if ($null -eq $v) { return $null }
    $t = ([string]$v).Trim()
    if (-not $t -or $t -eq '-') { return $null }
    $d = 0.0
    if ([double]::TryParse($t, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return $null
}
function ConvertFrom-IsoDuration([string]$Text) {
    if (-not $Text) { return $null }
    try { $ts = [Xml.XmlConvert]::ToTimeSpan($Text.Trim()); if ($ts.TotalSeconds -gt 0) { return $ts } } catch { }
    return $null
}
function New-BatteryInfo($Name, $Hersteller, $Chemie, $Design, $Voll, $Zyklen) {
    $wear = $null
    if ($Design -and $Voll -and [double]$Design -gt 0) { $wear = [math]::Round([math]::Max(0.0, (1 - [double]$Voll / [double]$Design) * 100), 1) }
    [pscustomobject][ordered]@{ Name = [string]$Name; Hersteller = [string]$Hersteller; Chemie = [string]$Chemie; DesignmWh = $Design; VollmWh = $Voll; VerschleissProzent = $wear
        Zyklen = $Zyklen; LaufzeitVoll = $null; LaufzeitDesign = $null; Verlauf = @() }
}

function ConvertFrom-BatteryReportXml([string]$Text) {
    if (-not $Text) { return @() }
    $x = New-Object Xml.XmlDocument
    try { $x.LoadXml($Text.TrimStart([char]0xFEFF)) } catch { return @() }
    $all = @($x.SelectNodes('//*'))
    $bats = @($all | Where-Object { $_.LocalName -eq 'Battery' -and $_.ParentNode -and $_.ParentNode.LocalName -eq 'Batteries' })
    $res = @(foreach ($b in $bats) {
        New-BatteryInfo (Get-XmlLocal $b 'Id') (Get-XmlLocal $b 'Manufacturer') (Get-XmlLocal $b 'Chemistry') (ConvertTo-NullableNumber (Get-XmlLocal $b 'DesignCapacity')) (ConvertTo-NullableNumber (Get-XmlLocal $b 'FullChargeCapacity')) (ConvertTo-NullableNumber (Get-XmlLocal $b 'CycleCount'))
    })
    if (-not $res.Count) { return @() }
    $hist = @($all | Where-Object { $_.LocalName -eq 'HistoryEntry' } | ForEach-Object {
        $st = Get-XmlLocal $_ 'LocalStartDate'; if (-not $st) { $st = Get-XmlLocal $_ 'StartDate' }
        $en = Get-XmlLocal $_ 'LocalEndDate'; if (-not $en) { $en = Get-XmlLocal $_ 'EndDate' }
        $f = ConvertTo-NullableNumber (Get-XmlLocal $_ 'FullChargeCapacity'); $d = ConvertTo-NullableNumber (Get-XmlLocal $_ 'DesignCapacity')
        if ($f) { [pscustomobject]@{ Zeitraum = ('{0}{1}' -f ([string]$st -replace 'T.*$', ''), $(if ($en) { ' bis ' + ([string]$en -replace 'T.*$', '') } else { '' })); VollmWh = $f; DesignmWh = $d; ActiveRuntime = (Get-XmlLocal $_ 'ActiveRuntime') } }
    })
    $res[0].Verlauf = @($hist)
    # Laufzeitschätzung: Abschnitt RuntimeEstimates (FullChargeCapacity bzw. DesignCapacity mit ActiveRuntime)
    $est = @($all | Where-Object { $_.LocalName -eq 'RuntimeEstimates' }) | Select-Object -First 1
    if ($est) {
        foreach ($c in @($est.ChildNodes)) {
            $ar = ConvertFrom-IsoDuration (Get-XmlLocal $c 'ActiveRuntime')
            if ($c.LocalName -eq 'FullChargeCapacity' -and $ar) { $res[0].LaufzeitVoll = $ar }
            if ($c.LocalName -eq 'DesignCapacity' -and $ar) { $res[0].LaufzeitDesign = $ar }
        }
    }
    if (-not $res[0].LaufzeitVoll -and $hist.Count) { $res[0].LaufzeitVoll = ConvertFrom-IsoDuration $hist[$hist.Count - 1].ActiveRuntime }
    return $res
}

# HTML-Fassung: Zahlen mit Tausenderpunkt oder -komma ("70.624 mWh", "70,624 mWh"), Zyklen "-" = unbekannt
function ConvertFrom-BatteryReportHtml([string]$Html) {
    if (-not $Html) { return @() }
    $cells = { param($row) @([regex]::Matches($row, '(?is)<td[^>]*>(.*?)</td>') | ForEach-Object { ([System.Net.WebUtility]::HtmlDecode(([regex]::Replace($_.Groups[1].Value, '<[^>]+>', ' '))) -replace '\s+', ' ').Trim() }) }
    $mwh = { param($t) $d = ([string]$t -replace '[^\d]', ''); if ($d) { [double]$d } else { $null } }
    $hms = { param($t) $m = [regex]::Match([string]$t, '^(\d+):(\d{2}):(\d{2})'); if ($m.Success) { New-TimeSpan -Hours ([int]$m.Groups[1].Value) -Minutes ([int]$m.Groups[2].Value) -Seconds ([int]$m.Groups[3].Value) } else { $null } }
    $i = $Html.IndexOf('Installed batteries')
    $j = $Html.IndexOf('Recent usage')
    if ($i -lt 0) { return @() }
    $blk = $Html.Substring($i, $(if ($j -gt $i) { $j - $i } else { [math]::Min(20000, $Html.Length - $i) }))
    $vals = @{}
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($row in [regex]::Matches($blk, '(?is)<tr[^>]*>(.*?)</tr>')) {
        $c = & $cells $row.Groups[1].Value
        if ($c.Count -ge 2 -and $c[0] -match '^[A-Z ]+$') {
            $k = $c[0].Trim()
            if ($k -match '^BATTERY \d+' -or ($k -eq 'NAME' -and $vals.ContainsKey('NAME'))) { if ($vals.Count) { $res.Add($vals); $vals = @{} } }
            if ($k -notmatch '^BATTERY') { $vals[$k] = $c[1] }
        }
    }
    if ($vals.Count) { $res.Add($vals) }
    $out = @(foreach ($v in $res) {
        if (-not $v.ContainsKey('DESIGN CAPACITY') -and -not $v.ContainsKey('FULL CHARGE CAPACITY')) { continue }
        $cy = $(if ($v['CYCLE COUNT'] -match '^\s*\d+\s*$') { [double]$v['CYCLE COUNT'].Trim() } else { $null })
        New-BatteryInfo $v['NAME'] $v['MANUFACTURER'] $v['CHEMISTRY'] (& $mwh $v['DESIGN CAPACITY']) (& $mwh $v['FULL CHARGE CAPACITY']) $cy
    })
    if (-not $out.Count) { return @() }
    $h = $Html.IndexOf('Battery capacity history'); $e = $Html.IndexOf('Battery life estimates')
    if ($h -gt 0) {
        $part = $Html.Substring($h, $(if ($e -gt $h) { $e - $h } else { $Html.Length - $h }))
        $out[0].Verlauf = @(foreach ($row in [regex]::Matches($part, '(?is)<tr[^>]*>(.*?)</tr>')) {
            $c = & $cells $row.Groups[1].Value
            if ($c.Count -ge 3 -and $c[0] -match '^\d{4}-\d{2}-\d{2}') { [pscustomobject]@{ Zeitraum = ($c[0] -replace '\s+-\s+', ' bis '); VollmWh = (& $mwh $c[1]); DesignmWh = (& $mwh $c[2]); ActiveRuntime = $null } }
        })
    }
    if ($e -gt 0) {
        $rows = @([regex]::Matches($Html.Substring($e), '(?is)<tr[^>]*>(.*?)</tr>') | ForEach-Object { , (& $cells $_.Groups[1].Value) } | Where-Object { $_.Count -ge 5 -and (& $hms $_[1]) })
        $since = @($rows | Where-Object { $_[0] -match 'install|Installation' }) | Select-Object -First 1
        $pickRow = $(if ($since) { $since } elseif ($rows.Count) { $rows[$rows.Count - 1] } else { $null })
        if ($pickRow) { $out[0].LaufzeitVoll = & $hms $pickRow[1]; $out[0].LaufzeitDesign = & $hms $pickRow[$pickRow.Count - 2] }
    }
    return $out
}

# Befund nach Verschleiß: ab 30 % INFO, ab 50 % WARNUNG
function Get-BatteryFinding($Info) {
    if (-not $Info -or $null -eq $Info.VerschleissProzent) { return $null }
    $w = [double]$Info.VerschleissProzent
    $txt = ('Akku {0}: {1:N0} % Verschleiß (volle Ladung {2:N0} von {3:N0} mWh Designkapazität{4}).' -f $Info.Name, $w, $Info.VollmWh, $Info.DesignmWh, $(if ($null -ne $Info.Zyklen) { ', {0:N0} Ladezyklen' -f $Info.Zyklen } else { '' }))
    if ($w -ge 50) { return [pscustomobject]@{ Stufe = 'WARNUNG'; Text = $txt + ' Die Laufzeit ist stark verkürzt, ein Austausch lohnt sich.' } }
    if ($w -ge 30) { return [pscustomobject]@{ Stufe = 'INFO'; Text = $txt + ' Die Laufzeit ist spürbar kürzer als im Neuzustand.' } }
    return $null
}

function Format-Duration($Ts) { if (-not $Ts) { return '' }; return ('{0}:{1:00} h' -f [int][math]::Floor($Ts.TotalHours), $Ts.Minutes) }

# Größe der Testdatei des Datenträger-Lasttests: 10 % des freien Platzes, mindestens 256 MB, höchstens 4 GB.
# Alles in double: [math]::Max(256MB, ...) wählte unter Windows PowerShell 5.1 die Int32-Fassung und brach mit
# "Der Wert 4294967296 kann nicht in Int32 konvertiert werden" ab (Praxistest 02.10.2026, Lasttest Datenträger).
# Zuverlässigkeitsindex von Windows (Zuverlässigkeitsverlauf, 1 bis 10) einordnen und bei niedrigem Wert kurz erklären
# (ab v2.65). Gezählt werden nur Fehler aus Win32_ReliabilityRecords, keine erfolgreichen Updates und Installationen.
function Get-StabilityAssessment($Index, $Records = @(), [int]$Days = 28) {
    if ($null -eq $Index -or "$Index" -eq '') { return $null }
    $v = 0.0; try { $v = [double]$Index } catch { return $null }
    $stufe = $(if ($v -ge 8) { 'gut' } elseif ($v -ge 5) { 'mittel' } else { 'niedrig' })
    $kat = [ordered]@{ Programm = @(); Haenger = @(); Windows = @(); Update = @(); Installation = @() }
    foreach ($r in @($Records | Where-Object { $_ })) {
        $src = [string]$r.SourceName; $id = 0; try { $id = [int]$r.EventIdentifier } catch { }
        $prod = ([string]$r.ProductName).Trim()
        switch -Regex ($src) {
            '^Application Error$' { $kat.Programm += $prod; break }
            '^Application Hang$' { $kat.Haenger += $prod; break }
            '^(EventLog|Microsoft-Windows-WER-SystemErrorReporting|Microsoft-Windows-Kernel-Power)$' { if ($id -in 6008, 1001, 41) { $kat.Windows += $prod }; break }
            '^Windows Error Reporting$' { if ($prod -match '^Windows$' -or ([string]$r.Message) -match 'BlueScreen|LiveKernelEvent') { $kat.Windows += $prod }; break }
            'WindowsUpdateClient' { if ($id -eq 20) { $kat.Update += $prod }; break }
            '^MsiInstaller$' { if ($id -in 11708, 1023, 11724) { $kat.Installation += $prod }; break }
        }
    }
    $top = { param($list) $g = @($list | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 1); if ($g.Count) { ' (meist {0})' -f (Get-ShortText $g[0].Name 60) } else { '' } }
    $u = @()
    if ($kat.Windows.Count) { $u += ('{0}x Windows-Fehler (Absturz oder unerwartetes Ausschalten)' -f $kat.Windows.Count) }
    if ($kat.Programm.Count) { $u += ('{0}x Programmabsturz{1}' -f $kat.Programm.Count, (& $top $kat.Programm)) }
    if ($kat.Haenger.Count) { $u += ('{0}x Programm reagierte nicht{1}' -f $kat.Haenger.Count, (& $top $kat.Haenger)) }
    if ($kat.Update.Count) { $u += ('{0}x Update fehlgeschlagen{1}' -f $kat.Update.Count, (& $top $kat.Update)) }
    if ($kat.Installation.Count) { $u += ('{0}x Installation fehlgeschlagen{1}' -f $kat.Installation.Count, (& $top $kat.Installation)) }
    $erkl = ''
    if ($v -lt 7) {
        $erkl = 'Windows bewertet die Stabilität täglich von 1 bis 10. Abstürze, Fehlstarts und fehlgeschlagene Updates senken den Wert, neuere stärker; ohne neue Fehler steigt er langsam wieder.'
        $erkl += $(if ($u.Count) { (' Ursachen der letzten {0} Tage: {1}.' -f $Days, ($u -join ', ')) } else { (' In den letzten {0} Tagen stehen keine Fehler im Zuverlässigkeitsverlauf; der Wert erholt sich von älteren Fehlern.' -f $Days) })
    }
    return [pscustomobject]@{ Index = [math]::Round($v, 1); Stufe = $stufe; Klasse = $(switch ($stufe) { 'gut' { 'ok' } 'mittel' { 'info' } default { 'warn' } }); Ursachen = $u; Erklaerung = $erkl
        Text = ('{0:N1} von 10 ({1})' -f $v, $stufe) }
}

# Freier Platz eines Laufwerks über .NET (ab v2.65 statt Get-Volume, das über den WMI-Speicheranbieter hängen kann)
function Get-DriveSpace([string]$Letter) {
    $l = ([string]$Letter).Trim().TrimEnd(':', '\')
    if ($l.Length -ne 1) { return $null }
    # außerhalb von Windows (Gesamtläufe der Tests) gibt es keine Laufwerksbuchstaben: dort die Attrappe von Get-Volume
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $v = @(Get-Volume -DriveLetter $l -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($v) { return [pscustomobject]@{ DriveLetter = $l.ToUpperInvariant(); SizeRemaining = [double]$v.SizeRemaining; Size = [double]$v.Size; FileSystem = [string]$v.FileSystem; DriveType = [string]$v.DriveType } }
        return $null
    }
    try {
        $d = New-Object IO.DriveInfo ($l + ':\')
        if (-not $d.IsReady) { return $null }
        return [pscustomobject]@{ DriveLetter = $l.ToUpperInvariant(); SizeRemaining = [double]$d.AvailableFreeSpace; Size = [double]$d.TotalSize; FileSystem = [string]$d.DriveFormat; DriveType = [string]$d.DriveType }
    } catch { return $null }
}

function Get-DiskStressBytes([double]$FreeBytes) {
    return [long][math]::Max([double]256MB, [math]::Min([double]4GB, [double]$FreeBytes * 0.1))
}

