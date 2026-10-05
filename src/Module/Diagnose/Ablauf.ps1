# =====================================================================================
#                                     DIAGNOSE
# =====================================================================================
if ($ModDiag -and -not $AnalyzeLastRun) {

# Schneller Modus: erste Hintergrundprüfungen anmelden (weitere nach den Abschnitten Sicherheit und SMART-Daten)
Start-DiagnoseParallel 'Start'

Invoke-Section 'System und Betriebssystem' {
    $cs   = Get-CimCached Win32_ComputerSystem
    $os   = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimCached Win32_BIOS
    $bb   = Get-CimCached Win32_BaseBoard
    $enc  = Get-CimCached Win32_SystemEnclosure
    $cv   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $ii   = Get-WindowsInstallInfo; $script:InstallInfo = $ii
    $up   = (Get-Date) - $os.LastBootUpTime
    $fw   = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -ErrorAction SilentlyContinue).PEFirmwareType
    if (-not $fw) { if ($env:firmware_type -eq 'UEFI') { $fw = 2 } elseif ($env:firmware_type -eq 'Legacy') { $fw = 1 } }
    if (-not $fw) { try { [void](Confirm-SecureBootUEFI -ErrorAction Stop); $fw = 2 } catch [System.PlatformNotSupportedException] { $fw = 1 } catch { } }
    $chassisMap = @{ 3 = 'Desktop'; 4 = 'Low Profile Desktop'; 6 = 'Mini Tower'; 7 = 'Tower'; 8 = 'Portable'; 9 = 'Laptop'; 10 = 'Notebook'; 13 = 'All-in-One'; 14 = 'Sub-Notebook'; 30 = 'Tablet'; 31 = 'Convertible'; 32 = 'Detachable'; 35 = 'Mini PC' }
    $chassis = ($enc.ChassisTypes | ForEach-Object { if ($chassisMap.ContainsKey([int]$_)) { $chassisMap[[int]$_] } else { "Typ $_" } }) -join ', '
    $script:IsLaptop = [bool]($enc.ChassisTypes | Where-Object { $_ -in 8, 9, 10, 14, 30, 31, 32 })

    [pscustomobject][ordered]@{
        'Computername'       = $env:COMPUTERNAME
        'Domäne/Arbeitsgr.'  = $cs.Domain
        'Angemeldet'         = $cs.UserName
        'Hersteller'         = $cs.Manufacturer
        'Modell'             = $cs.Model
        'SKU'                = $cs.SystemSKUNumber
        'Seriennummer'       = $bios.SerialNumber
        'Gehäuse'            = $chassis
        'Mainboard'          = ('{0} {1} {2}' -f $bb.Manufacturer, $bb.Product, $bb.Version).Trim()
        'BIOS/UEFI'          = ('{0} {1} vom {2:dd.MM.yyyy}' -f $bios.Manufacturer, $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
        'Firmwaremodus'      = $(switch ($fw) { 1 { 'Legacy BIOS' } 2 { 'UEFI' } default { 'unbekannt' } })
        'Betriebssystem'     = ('{0} {1}' -f $os.Caption, $cv.DisplayVersion)
        'Build'              = ('{0}.{1}' -f $os.BuildNumber, $cv.UBR)
        'Architektur'        = $os.OSArchitecture
        'Sprache'            = (Get-Culture).Name
        'Erstinstallation'   = $(if ($ii.Erstinstallation) { '{0:dd.MM.yyyy} (vor {1})' -f $ii.Erstinstallation, (Format-Age $ii.AlterTage -Dativ) } else { 'unbekannt' })
        'Stand seit'         = $(if ($ii.AktuellSeit) { '{0:dd.MM.yyyy HH:mm}{1}' -f $ii.AktuellSeit, $(if ($ii.Upgrades.Count) { ' (letztes Funktionsupdate)' } else { ' (Installation)' }) })
        'Letzter Start'      = $os.LastBootUpTime
        'Laufzeit'           = (Format-Uptime $up)
        'Zeitzone'           = (Get-TimeZone).DisplayName
        'Hypervisor aktiv'   = $cs.HypervisorPresent
        'PowerShell'         = $PSVersionTable.PSVersion.ToString()
    } | Out-Report -List
    $script:Facts['Computer']       = $env:COMPUTERNAME
    $script:Facts['System']         = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
    $script:Facts['Betriebssystem'] = ('{0} {1} (Build {2}.{3})' -f $os.Caption, $cv.DisplayVersion, $os.BuildNumber, $cv.UBR)
    $script:Facts['BIOS/UEFI']      = ('{0} vom {1:dd.MM.yyyy}' -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
    $script:Facts['Laufzeit']       = ('{0} seit dem letzten Start' -f (Format-Uptime $up))
    $script:Facts['Mainboard']      = ('{0} {1}' -f $bb.Manufacturer, $bb.Product).Trim()
    if ($ii.Erstinstallation) {
        $script:Facts['Windows installiert'] = ('{0:dd.MM.yyyy} (vor {1}){2}' -f $ii.Erstinstallation, (Format-Age $ii.AlterTage -Dativ), $(if ($ii.Upgrades.Count) { ', seitdem {0} Funktionsupdate(s), zuletzt {1:dd.MM.yyyy}' -f $ii.Upgrades.Count, $ii.AktuellSeit } else { ', seitdem kein Funktionsupdate' }))
    }
    Add-Private $bios.SerialNumber 'SERIENNR'; Add-Private $bb.SerialNumber 'SERIENNR'; Add-Private $enc.SerialNumber 'SERIENNR'
    $script:UserNames = @(@([string]$cs.UserName, [string]$env:USERNAME) | ForEach-Object { ($_ -split '\\')[-1] } | Where-Object { $_ })
    if ($cs.PartOfDomain -and $cs.Domain) { Add-Private ([string]$cs.Domain) 'DOMÄNE' }

    if ($up.TotalDays -gt 14) { Add-Finding INFO 'System' ('Seit {0} Tagen kein Neustart. Ein Neustart vor der Fehlersuche ist sinnvoll.' -f [int]$up.TotalDays) }
    if ($fw -eq 1) { Add-Finding WARNUNG 'Firmware' 'System startet im Legacy-BIOS-Modus, Windows 11 erwartet UEFI.' }
    if ($bios.ReleaseDate -and $bios.ReleaseDate -lt (Get-Date).AddYears(-3)) { Add-Finding INFO 'Firmware' ('BIOS/UEFI ist älter als 3 Jahre ({0:dd.MM.yyyy}). Update beim Hersteller prüfen.' -f $bios.ReleaseDate) }

    Add-Sub 'Windows-Installation'
    if ($ii.Erstinstallation) {
        Add-Line ('  Erstinstallation      : {0:dd.MM.yyyy HH:mm} (vor {1})' -f $ii.Erstinstallation, (Format-Age $ii.AlterTage -Dativ))
        Add-Line ('  Aktueller Stand seit  : {0:dd.MM.yyyy HH:mm}{1}' -f $ii.AktuellSeit, $(if ($ii.Upgrades.Count) { ' (Funktionsupdate oder Inplace-Upgrade)' } else { ' (seit der Installation kein Funktionsupdate)' }))
        if ($ii.WindowsOld) { Add-Line ('  Windows.old vorhanden : angelegt am {0:dd.MM.yyyy}' -f $ii.WindowsOld) }
        if ($ii.Upgrades.Count) {
            Add-Line '  Frühere Stände (Registrierung HKLM\SYSTEM\Setup\Source OS):'
            $ii.Upgrades | Select-Object @{n = 'Installiert'; e = { $_.Installiert.ToString('dd.MM.yyyy') } }, @{n = 'Ersetzt am'; e = { if ($_.Ersetzt) { $_.Ersetzt.ToString('dd.MM.yyyy') } } }, Produkt, Version, Build | Out-Report
        }
        if ($ii.AlterTage -lt 3) { Add-Finding INFO 'System' ('Windows wurde vor {0} frisch installiert. Treiber und Updates sind eventuell noch unvollständig.' -f (Format-Age $ii.AlterTage -Dativ)) }
        elseif ($ii.AlterTage -gt 5 * 365.25) { Add-Finding INFO 'System' ('Die Windows-Installation ist {0} alt (Erstinstallation {1:dd.MM.yyyy}, seitdem {2} Funktionsupdates). Bei hartnäckigen Problemen ist eine Neuinstallation eine Option.' -f (Format-Age $ii.AlterTage), $ii.Erstinstallation, $ii.Upgrades.Count) }
    } else { Add-Line '  Installationsdatum nicht ermittelbar.' }

    Add-Sub 'Aktivierung'
    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" -ErrorAction Stop
        foreach ($l in @($lic)) { Add-Private ([string]$l.PartialProductKey) 'SCHLÜSSEL' }
        $licMap = @{ 0 = 'Nicht lizenziert'; 1 = 'Lizenziert'; 2 = 'OOB-Toleranz'; 3 = 'OOT-Toleranz'; 4 = 'Nicht-Original-Toleranz'; 5 = 'Benachrichtigung'; 6 = 'Erweiterte Toleranz' }
        $lic | Select-Object Name, @{n = 'Status'; e = { $licMap[[int]$_.LicenseStatus] } }, @{n = 'Kanal'; e = { $_.ProductKeyChannel } }, @{n = 'Schlüssel (Ende)'; e = { $_.PartialProductKey } } | Out-Report
        # Ab 2.4 kein Befund mehr (nicht aktiviert, GVLK ohne Domäne): der Status steht nur im Inventar
        $act = @($lic | Where-Object LicenseStatus -eq 1)
        $script:Facts['Aktivierung'] = $(if ($act.Count) { 'aktiviert ({0})' -f (@($act | ForEach-Object { [string]$_.ProductKeyChannel } | Where-Object { $_ } | Select-Object -Unique) -join ', ') } elseif (@($lic).Count) { 'nicht aktiviert ({0})' -f $licMap[[int]@($lic)[0].LicenseStatus] } else { 'kein Produktschlüssel gefunden' })
    } catch { Add-Line '  Aktivierungsstatus nicht abrufbar.' }

    Add-Sub 'Neustart ausstehend'
    $pend = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pend += 'Komponentenwartung (CBS)' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pend += 'Windows Update' }
    $pfr = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($pend.Count) { Add-Line ('  Ja: {0}' -f ($pend -join ', ')); Add-Finding WARNUNG 'System' ('Neustart ausstehend ({0}).' -f ($pend -join ', ')) }
    else { Add-Line '  Kein Neustart durch Updates ausstehend.' }
    if ($pfr) { Add-Line ('  Ausstehende Dateiumbenennungen: {0} Einträge' -f @($pfr).Count) }

    if (-not $Kurztest) { try { Get-ComputerInfo | Out-File (Join-Path $RawDir 'ComputerInfo.txt') -Width 300 -Encoding UTF8 } catch { } }
}

Invoke-Section 'Sicherheit, TPM, Secure Boot, BitLocker' {
    $sec = [ordered]@{}
    try   { $sec['Secure Boot'] = $(if (Confirm-SecureBootUEFI -ErrorAction Stop) { 'aktiv' } else { 'AUS' }) }
    catch { $sec['Secure Boot'] = 'nicht unterstützt / Legacy' }
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        $tpmW = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue
        $sec['TPM vorhanden']   = $tpm.TpmPresent
        $sec['TPM bereit']      = $tpm.TpmReady
        $sec['TPM Version']     = $(if ($tpmW) { ($tpmW.SpecVersion -split ',')[0] } else { '' })
        $sec['TPM Hersteller']  = ((('{0} {1}' -f $tpm.ManufacturerIdTxt, $tpm.ManufacturerVersion) -replace '[\x00-\x1F]', ' ' -replace '\s{2,}', ' ').Trim())
        if (-not $tpm.TpmReady) { Add-Finding WARNUNG 'Sicherheit' 'TPM ist nicht bereit oder nicht vorhanden.' }
    } catch { $sec['TPM'] = 'nicht abrufbar' }
    $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue).EnableLUA
    $sec['UAC aktiv'] = ($uac -eq 1)
    $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    if ($dg) {
        $sec['VBS Status']          = @{ 0 = 'aus'; 1 = 'konfiguriert, nicht aktiv'; 2 = 'aktiv' }[[int]$dg.VirtualizationBasedSecurityStatus]
        $sec['Credential Guard']    = ($dg.SecurityServicesRunning -contains 1)
        $sec['Speicherintegrität']  = ($dg.SecurityServicesRunning -contains 2)
    }
    [pscustomobject]$sec | Out-Report -List
    $script:Facts['Sicherheit'] = ('Secure Boot {0}, TPM {1}' -f $sec['Secure Boot'], $(if ($sec['TPM bereit']) { 'bereit (' + $sec['TPM Version'] + ')' } else { 'nicht bereit' }))
    if ($sec['Secure Boot'] -ne 'aktiv') { Add-Finding WARNUNG 'Sicherheit' ('Secure Boot: {0}.' -f $sec['Secure Boot']) }
    if ($uac -ne 1) { Add-Finding WARNUNG 'Sicherheit' 'Benutzerkontensteuerung (UAC) ist deaktiviert.' }

    Add-Sub 'BitLocker'
    try {
        Get-BitLockerVolume -ErrorAction Stop | Select-Object MountPoint, VolumeType, VolumeStatus, ProtectionStatus, EncryptionMethod,
            @{n = 'Verschl. %'; e = { $_.EncryptionPercentage } }, @{n = 'Schutzarten'; e = { ($_.KeyProtector.KeyProtectorType -join ', ') } } | Out-Report
    } catch { Add-Line '  BitLocker-Status nicht abrufbar.' }

    Add-Sub 'Virenschutz'
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $mp | Select-Object AMRunningMode, AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, IsTamperProtected,
            AntivirusSignatureVersion, AntivirusSignatureLastUpdated, AntivirusSignatureAge, QuickScanEndTime, FullScanEndTime | Out-Report -List
        $script:DefenderActive = ($mp.AMRunningMode -eq 'Normal' -or ($null -eq $mp.AMRunningMode -and $mp.RealTimeProtectionEnabled))
        if ($script:DefenderActive -and -not $mp.RealTimeProtectionEnabled) { Add-Finding WARNUNG 'Sicherheit' 'Defender Echtzeitschutz ist aus.' }
        if ($script:DefenderActive -and $mp.AntivirusSignatureAge -gt 7) { Add-Finding WARNUNG 'Sicherheit' ('Defender-Signaturen sind {0} Tage alt.' -f $mp.AntivirusSignatureAge) }
        $thr = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt $Since })
        if ($thr.Count) {
            Add-Line ('  Erkennungen der letzten {0} Tage: {1}' -f $EventDays, $thr.Count)
            Add-Finding WARNUNG 'Sicherheit' ('{0} Bedrohungserkennungen in den letzten {1} Tagen.' -f $thr.Count, $EventDays)
        }
    } catch { Add-Line '  Microsoft Defender Status nicht abrufbar.'; $script:DefenderActive = $false }
    $av = Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
    if ($av) {
        Add-Line '  Registrierte Virenschutzprodukte:'
        $av | ForEach-Object {
            $hex = '{0:X6}' -f [int]$_.productState
            [pscustomobject]@{ Produkt = $_.displayName; Aktiv = ($hex.Substring(2, 2) -in '10', '11'); Aktuell = ($hex.Substring(4, 2) -eq '00'); Zustand = $hex }
        } | Out-Report
    }

    Add-Sub 'Firewall'
    Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction | Out-Report
    Get-NetFirewallProfile -ErrorAction SilentlyContinue | Where-Object { -not $_.Enabled } | ForEach-Object { Add-Finding WARNUNG 'Sicherheit' ('Firewallprofil {0} ist deaktiviert.' -f $_.Name) }

    Add-Sub 'SMBv1 und lokale Administratoren'
    if ($Kurztest) { Add-Line '  SMBv1: im Kurztest übersprungen.' }
    else {
        try {
            $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
            Add-Line ('  SMBv1: {0}' -f $smb1.State)
            if ($smb1.State -eq 'Enabled') { Add-Finding WARNUNG 'Sicherheit' 'Das veraltete Protokoll SMBv1 ist aktiviert.' }
        } catch { Add-Line '  SMBv1-Status nicht abrufbar.' }
    }
    try { Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | Select-Object Name, ObjectClass, PrincipalSource | Out-Report }
    catch { Add-Line '  Mitglieder der Administratorengruppe nicht abrufbar.' }
}

Start-DiagnoseParallel 'Defender'

Invoke-Section 'Prozessor' {
    $cpus = Get-CimCached Win32_Processor
    $cpus | ForEach-Object {
        [pscustomobject][ordered]@{
            'Name'                 = $_.Name.Trim()
            'Sockel'               = $_.SocketDesignation
            'Kerne / Threads'      = ('{0} / {1}' -f $_.NumberOfCores, $_.NumberOfLogicalProcessors)
            'Max. Takt (MHz)'      = $_.MaxClockSpeed
            'Akt. Takt (MHz)'      = $_.CurrentClockSpeed
            'L2 / L3 Cache'        = ('{0} KB / {1} KB' -f $_.L2CacheSize, $_.L3CacheSize)
            'Auslastung %'         = $_.LoadPercentage
            'Virtualisierung (FW)' = $_.VirtualizationFirmwareEnabled
            'Status'               = $_.Status
        }
    } | Out-Report -List
    if ($cpus | Where-Object { $_.VirtualizationFirmwareEnabled -eq $false }) { Add-Finding INFO 'CPU' 'Virtualisierung ist in der Firmware deaktiviert (für WSL, Hyper-V, Sandbox nötig).' }
    if (Test-IsArm64) {
        $script:Facts['Architektur'] = 'ARM64'
        Add-Finding INFO 'Sensoren' 'ARM64-Architektur erkannt: Tiefgehende Kern- und Mainboard-Sensoren erfordern x86/x64-Treiber und stehen nur eingeschränkt zur Verfügung.'
    }
    $script:LogicalCpus = ($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    $script:BenchShort.CPU = Get-ShortCpuName @($cpus)[0].Name
    $script:Facts['Prozessor'] = (($cpus | ForEach-Object { '{0} ({1} Kerne, {2} Threads)' -f $_.Name.Trim(), $_.NumberOfCores, $_.NumberOfLogicalProcessors }) -join '; ')
}

Invoke-Section 'Arbeitsspeicher' {
    $typeMap = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $ffMap   = @{ 8 = 'DIMM'; 12 = 'SO-DIMM'; 0 = 'unbekannt' }
    $mods = @(Get-CimCached Win32_PhysicalMemory)
    $arr  = Get-CimInstance Win32_PhysicalMemoryArray | Where-Object Use -eq 3 | Select-Object -First 1
    $os   = Get-CimInstance Win32_OperatingSystem
    $mods | ForEach-Object {
        [pscustomobject][ordered]@{
            'Steckplatz'    = ('{0} {1}' -f $_.BankLabel, $_.DeviceLocator).Trim()
            'Größe'         = Format-Size $_.Capacity
            'Typ'           = $(if ($typeMap.ContainsKey([int]$_.SMBIOSMemoryType)) { $typeMap[[int]$_.SMBIOSMemoryType] } else { $_.SMBIOSMemoryType })
            'Bauform'       = $ffMap[[int]$_.FormFactor]
            'Nenntakt'      = $_.Speed
            'Betriebstakt'  = $_.ConfiguredClockSpeed
            'Hersteller'    = $_.Manufacturer
            'Teilenummer'   = ($_.PartNumber -as [string]).Trim()
            'Seriennummer'  = $_.SerialNumber
        }
    } | Out-Report
    $total = ($mods | Measure-Object Capacity -Sum).Sum
    if ($mods.Count) {
        $m0 = $mods[0]
        $typ0 = $(if ($typeMap.ContainsKey([int]$m0.SMBIOSMemoryType)) { $typeMap[[int]$m0.SMBIOSMemoryType] } else { '' })
        $script:Facts['Arbeitsspeicher'] = ('{0} ({1}x {2} {3}, {4} MT/s)' -f (Format-Size $total), $mods.Count, (Format-Size $m0.Capacity), $typ0, $m0.ConfiguredClockSpeed)
    }
    Add-Line
    Add-Line ('  Installiert: {0} in {1} von {2} Steckplätzen, maximal unterstützt: {3}' -f (Format-Size $total), $mods.Count, $arr.MemoryDevices, (Format-Size ([double]$arr.MaxCapacityEx * 1KB)))
    $usedPct = 100 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize * 100)
    Add-Line ('  Nutzbar: {0}, frei: {1}, belegt: {2:N0} %' -f (Format-Size ($os.TotalVisibleMemorySize * 1KB)), (Format-Size ($os.FreePhysicalMemory * 1KB)), $usedPct)
    Add-Line ('  Zugesichert (Commit): {0} von {1}' -f (Format-Size (($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) * 1KB)), (Format-Size ($os.TotalVirtualMemorySize * 1KB)))
    Get-CimInstance Win32_PageFileUsage | ForEach-Object { Add-Line ('  Auslagerungsdatei {0}: {1} MB, aktuell {2} MB, Spitze {3} MB' -f $_.Name, $_.AllocatedBaseSize, $_.CurrentUsage, $_.PeakUsage) }

    if ($usedPct -gt 90) { Add-Finding WARNUNG 'RAM' ('Arbeitsspeicher zu {0:N0} % belegt.' -f $usedPct) }
    if (@($mods.Speed | Select-Object -Unique).Count -gt 1) { Add-Finding WARNUNG 'RAM' 'Module mit unterschiedlichen Nenntakten verbaut.' }
    if (@($mods.PartNumber | Select-Object -Unique).Count -gt 1) { Add-Finding INFO 'RAM' 'Gemischte RAM-Module (unterschiedliche Teilenummern).' }
    if ($mods | Where-Object { $_.ConfiguredClockSpeed -and $_.Speed -and $_.ConfiguredClockSpeed -lt $_.Speed }) { Add-Finding INFO 'RAM' 'RAM läuft unter Nenntakt (XMP/EXPO-Profil evtl. nicht aktiv oder vom Board begrenzt).' }
    if ($mods.Count -eq 1 -and $arr.MemoryDevices -ge 2) { Add-Finding INFO 'RAM' 'Nur ein Modul verbaut, vermutlich Single-Channel-Betrieb (geringere Speicherbandbreite).' }
    if ($total -lt 8GB) { Add-Finding WARNUNG 'RAM' ('Nur {0} RAM verbaut, für Windows 11 knapp.' -f (Format-Size $total)) }
    foreach ($m in $mods) { Add-Private ([string]$m.SerialNumber) 'SERIENNR' }
    if ($mods.Count) {
        $script:BenchShort.RAM = ('{0} GB {1}-{2}' -f [math]::Round($total / 1GB), $(if ($typ0) { $typ0 } else { 'RAM' }), $(if ($m0.ConfiguredClockSpeed) { $m0.ConfiguredClockSpeed } else { $m0.Speed }))
        Test-RamProfile $mods $typ0
    }
}

Invoke-Section 'Grafik und Monitore' {
    $vram = @{}
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        try { if ($p.DriverDesc -and $p.'HardwareInformation.qwMemorySize') { $vram[$p.DriverDesc] = [long]$p.'HardwareInformation.qwMemorySize' } } catch { }
    }
    Get-CimCached Win32_VideoController | ForEach-Object {
        [pscustomobject][ordered]@{
            'Name'          = $_.Name
            'Art'           = $(switch (Get-GpuKind ([string]$_.Name)) { 'dGPU' { 'dedizierte Grafikkarte' } 'iGPU' { 'Prozessorgrafik (integriert)' } 'virtuell' { 'virtueller Adapter' } default { 'unbekannt' } }) + $(if ($_.CurrentHorizontalResolution) { ', gibt den Desktop aus' } else { '' })
            'VRAM'          = $(if ($vram.ContainsKey($_.Name)) { Format-Size $vram[$_.Name] } else { Format-Size $_.AdapterRAM })
            'Treiber'       = $_.DriverVersion
            'Treiberdatum'  = $(if ($_.DriverDate) { $_.DriverDate.ToString('dd.MM.yyyy') })
            'Auflösung'     = $(if ($_.CurrentHorizontalResolution) { '{0}x{1} @ {2} Hz' -f $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution, $_.CurrentRefreshRate })
            'Status'        = $_.Status
        }
    } | Out-Report -List
    Get-CimCached Win32_VideoController | Where-Object { $_.DriverDate -and $_.DriverDate -lt (Get-Date).AddYears(-2) -and $_.Name -notmatch 'Virtual|Remote|Indirect|Parsec|spacedesk' } | ForEach-Object {
        Add-Finding INFO 'Grafik' ('Grafiktreiber für {0} ist älter als 2 Jahre ({1:dd.MM.yyyy}).' -f $_.Name, $_.DriverDate)
    }
    Get-CimCached Win32_VideoController | Where-Object { $_.Name -match 'Basic Display|Standard-VGA|Microsoft Basic' } | ForEach-Object {
        Add-Finding WARNUNG 'Grafik' 'Nur der Microsoft-Standardtreiber ist aktiv, der Herstellertreiber fehlt.'
    }
    $script:Facts['Grafik'] = Get-GpuFactText
    $gMain = Get-MainGpu; if ($gMain) { $script:BenchShort.GPU = Get-ShortGpuName $gMain.Name }
    Add-Sub 'Monitore'
    $dec = { param($a) if ($a) { -join ($a | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) } }
    Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue | ForEach-Object {
        $sn = (& $dec $_.SerialNumberID); Add-Private $sn 'SERIENNR'
        [pscustomobject]@{ Hersteller = (& $dec $_.ManufacturerName); Modell = (& $dec $_.UserFriendlyName); Seriennummer = $sn; Baujahr = $_.YearOfManufacture; Aktiv = $_.Active }
    } | Out-Report
}

Invoke-Section 'Datenträger und Volumes' {
    $pd = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    $pd | Sort-Object DeviceId | Select-Object DeviceId, FriendlyName, SerialNumber, MediaType, BusType, @{n = 'Größe'; e = { Format-Size $_.Size } },
        FirmwareVersion, HealthStatus, OperationalStatus | Out-Report
    $script:Facts['Datenträger'] = (($pd | Sort-Object DeviceId | ForEach-Object { '{0} ({1}, {2}, {3})' -f $_.FriendlyName, (Format-Size $_.Size), $_.BusType, $_.HealthStatus }) -join "`n")
    $script:DiskNames = @{}
    foreach ($d in $pd) { $script:DiskNames[[int]$d.DeviceId] = ('{0} ({1})' -f ([string]$d.FriendlyName).Trim(), $d.BusType); Add-Private ([string]$d.SerialNumber) 'SERIENNR' }
    foreach ($d in $pd) {
        if ($d.HealthStatus -ne 'Healthy') { Add-Finding KRITISCH 'Datenträger' ('{0}: Windows meldet Zustand "{1}" / {2}.' -f $d.FriendlyName, $d.HealthStatus, ($d.OperationalStatus -join ', ')) }
    }

    Add-Sub 'Zuverlässigkeitszähler (Windows Storage)'
    $rel = foreach ($d in $pd) {
        $c = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($c) {
            [pscustomobject][ordered]@{
                'Laufwerk'       = $d.FriendlyName
                'Temp °C'        = $c.Temperature
                'Temp max °C'    = $c.TemperatureMax
                'Verschleiß %'   = $c.Wear
                'Betriebsstd.'   = $c.PowerOnHours
                'Lesefehler'     = $(if ($null -ne $c.ReadErrorsTotal) { '{0} / {1} unkorr.' -f $c.ReadErrorsTotal, $c.ReadErrorsUncorrected } else { 'n/v' })
                'Schreibfehler'  = $(if ($null -ne $c.WriteErrorsTotal) { '{0} / {1} unkorr.' -f $c.WriteErrorsTotal, $c.WriteErrorsUncorrected } else { 'n/v' })
                'Start/Stopp'    = $c.StartStopCycleCount
                'Latenz max ms'  = ('{0} / {1}' -f $c.ReadLatencyMax, $c.WriteLatencyMax)
            }
            if ($c.Wear -ge 90) { Add-Finding KRITISCH 'Datenträger' ('{0}: Verschleiß {1} %.' -f $d.FriendlyName, $c.Wear) }
            elseif ($c.Wear -ge 70) { Add-Finding WARNUNG 'Datenträger' ('{0}: Verschleiß {1} %.' -f $d.FriendlyName, $c.Wear) }
            if ($c.Temperature -ge 65) { Add-Finding WARNUNG 'Datenträger' ('{0}: Temperatur {1} °C.' -f $d.FriendlyName, $c.Temperature) }
            if (($c.ReadErrorsUncorrected + $c.WriteErrorsUncorrected) -gt 0) { Add-Finding KRITISCH 'Datenträger' ('{0}: {1} unkorrigierbare Lese-/Schreibfehler.' -f $d.FriendlyName, ($c.ReadErrorsUncorrected + $c.WriteErrorsUncorrected)) }
        }
    }
    $rel | Out-Report

    Add-Sub 'Ausfallvorhersage (SMART über Windows)'
    Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PredictFailure) { Add-Finding KRITISCH 'Datenträger' ('SMART sagt Ausfall voraus: {0}' -f $_.InstanceName) }
        [pscustomobject]@{ Instanz = $_.InstanceName; 'Ausfall vorhergesagt' = $_.PredictFailure; Grund = $_.Reason }
    } | Out-Report

    Add-Sub 'Partitionsschema'
    Get-Disk -ErrorAction SilentlyContinue | Sort-Object Number | Select-Object Number, FriendlyName, PartitionStyle, @{n = 'Größe'; e = { Format-Size $_.Size } },
        IsBoot, IsSystem, IsOffline, IsReadOnly, NumberOfPartitions | Out-Report

    Add-Sub 'Volumes'
    $vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.Size -gt 0 }
    $vols | Sort-Object DriveLetter | ForEach-Object {
        $pct = [math]::Round($_.SizeRemaining / $_.Size * 100, 1)
        if ($_.DriveType -eq 'Fixed') {
            if ($pct -lt 5)      { Add-Finding KRITISCH 'Speicherplatz' ('Laufwerk {0}: nur {1} % frei ({2}).' -f $_.DriveLetter, $pct, (Format-Size $_.SizeRemaining)) }
            elseif ($pct -lt 12) { Add-Finding WARNUNG  'Speicherplatz' ('Laufwerk {0}: nur {1} % frei ({2}).' -f $_.DriveLetter, $pct, (Format-Size $_.SizeRemaining)) }
            if ($_.HealthStatus -ne 'Healthy') { Add-Finding WARNUNG 'Dateisystem' ('Volume {0}: Zustand {1}.' -f $_.DriveLetter, $_.HealthStatus) }
        }
        [pscustomobject][ordered]@{ LW = $_.DriveLetter; Bezeichnung = $_.FileSystemLabel; Dateisystem = $_.FileSystem; Typ = $_.DriveType
            'Größe' = Format-Size $_.Size; Frei = Format-Size $_.SizeRemaining; 'Frei %' = $pct; Zustand = $_.HealthStatus }
    } | Out-Report

    Add-Sub 'TRIM und Dirty-Bit'
    $trim = Invoke-External -File 'fsutil.exe' -Arguments 'behavior query DisableDeleteNotify'
    Add-Line ('  ' + ($trim.Output.Trim() -replace "`r?`n", "`r`n  "))
    foreach ($v in ($vols | Where-Object { $_.FileSystem -eq 'NTFS' -and $_.DriveType -eq 'Fixed' })) {
        $dirty = Invoke-External -File 'fsutil.exe' -Arguments ('dirty query {0}:' -f $v.DriveLetter)
        Add-Line ('  ' + $dirty.Output.Trim())
        if ($dirty.Output -match 'NOT Dirty|nicht fehlerhaft|ist nicht') { } elseif ($dirty.Output -match 'Dirty|fehlerhaft') { Add-Finding WARNUNG 'Dateisystem' ('Volume {0}: Dirty-Bit gesetzt, chkdsk beim nächsten Start nötig.' -f $v.DriveLetter) }
    }

    Add-Sub 'Temporäre Dateien'
    foreach ($p in @($env:TEMP, "$env:windir\Temp", "$env:windir\SoftwareDistribution\Download")) {
        if ($p -and (Test-Path $p)) {
            $s = (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            Add-Line ('  {0,-60} {1}' -f $p, (Format-Size $s))
        }
    }
    if (Test-Path "$env:SystemDrive\Windows.old") { Add-Line '  Windows.old ist vorhanden (kann per Datenträgerbereinigung entfernt werden).' }
}

Invoke-Section 'SMART-Daten (smartmontools)' {
    $script:SmartDevices = @()
    if (-not $script:Smartctl) {
        Add-Line '  smartctl nicht gefunden. Nur die Windows-Werte oben sind verfügbar, ein SMART-Langtest ist so nicht möglich.'
        if ($script:SmartInstallMsg) { Add-Line ('  Automatische Installation fehlgeschlagen: {0}' -f $script:SmartInstallMsg) }
        Add-Line '  Abhilfe: winget install smartmontools.smartmontools, https://www.smartmontools.org oder smartctl.exe in den Datenordner unter Tools legen.'
        Add-Finding INFO 'SMART' ('smartmontools fehlt, daher kein SMART-Langtest und keine Detailattribute{0}. Option "smartmontools installieren" nutzen oder smartctl.exe in den Datenordner unter Tools legen.' -f $(if ($script:SmartInstallMsg) { ' (Installation fehlgeschlagen: ' + $script:SmartInstallMsg + ')' } else { '' }))
        return
    }
    $ver = Invoke-External -File $script:Smartctl -Arguments '--version'
    Add-Line ('  ' + (($ver.Output -split "`r?`n")[0]) + ('   ({0})' -f $script:Smartctl))
    $scan = Invoke-External -File $script:Smartctl -Arguments '--scan-open -j' -TimeoutSec 120
    try { $devs = @(($scan.Output | ConvertFrom-Json).devices | Where-Object { -not $_.open_error }) } catch { $devs = @() }
    if (-not $devs.Count) { Add-Line '  Keine SMART-fähigen Laufwerke gefunden (RAID-Controller oder USB-Gehäuse ohne SAT-Durchreichung?).'; return }

    $di = 0
    $skipped = [System.Collections.Generic.List[string]]::new()
    $usable = [System.Collections.Generic.List[object]]::new()
    $summary = foreach ($d in $devs) {
        $di++
        Show-Sub 'SMART-Daten auslesen' ('Laufwerk {0} von {1}: {2}' -f $di, $devs.Count, $d.name) ([int](($di - 1) / $devs.Count * 100))
        $jr = Invoke-External -File $script:Smartctl -Arguments ('-a -j -d {0} {1}' -f $d.type, $d.name) -TimeoutSec 180
        try { $j = $jr.Output | ConvertFrom-Json } catch { $j = $null }
        $model = $(if ($j.model_name) { [string]$j.model_name } elseif ($j.scsi_product) { ('{0} {1}' -f $j.scsi_vendor, $j.scsi_product).Trim() } else { [string]$d.info_name })
        # Kartenleser ohne Medium und Geräte ohne Kapazität liefern keine sinnvollen Werte
        if (-not $j -or -not ([double]$j.user_capacity.bytes -gt 0)) { $skipped.Add(('{0} ({1})' -f $model, $d.name)); continue }
        $safe = ($d.name -replace '[\\/:]', '_').Trim('_')
        $txt = Invoke-External -File $script:Smartctl -Arguments ('-x -d {0} {1}' -f $d.type, $d.name) -TimeoutSec 180
        $txt.Output | Out-File (Join-Path $RawDir ('smartctl_{0}_vorher.txt' -f $safe)) -Encoding UTF8
        Add-Private ([string]$j.serial_number) 'SERIENNR'
        # Langtest nur für ATA- und NVMe-Laufwerke mit aktivem SMART
        if ($j.device.protocol -in 'ATA', 'NVMe' -and $j.smart_support.enabled -ne $false) { $usable.Add($d) }
        Test-SmartJson -Json $j -Label ('{0} [{1}]' -f $model, $d.name)
    }
    Hide-Sub
    $script:SmartDevices = @($usable)
    $summary | Out-Report
    if ($skipped.Count) { Add-Line ('  Ohne Medium oder ohne Kapazität übersprungen: {0}' -f ($skipped -join ', ')) }
    Add-Line '  Vollständige SMART-Ausgaben je Laufwerk (smartctl -x) liegen im Anhang.'
}

Start-DiagnoseParallel 'SMART'

Invoke-Section 'Akku' {
    $bat = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if (-not $bat.Count) { Add-Line '  Kein Akku vorhanden.'; return }
    $static = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue)
    $full   = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue)
    $cyc    = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue)
    $stat   = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue)
    # Akkubericht von Windows: XML zum Auswerten (Zahlen ohne Tausendertrennzeichen), HTML für den Anhang
    $xmlPath = Join-Path $RawDir 'Akkubericht.xml'; $htmlPath = Join-Path $RawDir 'Akkubericht.html'
    [void](Invoke-External -File 'powercfg.exe' -Arguments ('/batteryreport /xml /output "{0}" /duration 28' -f $xmlPath) -TimeoutSec 120)
    [void](Invoke-External -File 'powercfg.exe' -Arguments ('/batteryreport /output "{0}" /duration 28' -f $htmlPath) -TimeoutSec 120)
    $rep = @(); $repSrc = ''
    if (Test-Path -LiteralPath $xmlPath) { try { $rep = @(ConvertFrom-BatteryReportXml ([IO.File]::ReadAllText($xmlPath))); $repSrc = 'powercfg /batteryreport (XML)' } catch { } }
    if (-not $rep.Count -and (Test-Path -LiteralPath $htmlPath)) { try { $rep = @(ConvertFrom-BatteryReportHtml ([IO.File]::ReadAllText($htmlPath))); $repSrc = 'powercfg /batteryreport (HTML)' } catch { } }
    $script:BatteryInfo = @()
    for ($i = 0; $i -lt $bat.Count; $i++) {
        $r = $(if ($rep.Count -gt $i) { $rep[$i] } else { $null })
        $design = $(if ($r -and $r.DesignmWh) { $r.DesignmWh } elseif ($static.Count -gt $i -and $static[$i].DesignedCapacity) { [double]$static[$i].DesignedCapacity } else { $null })
        $fullC  = $(if ($r -and $r.VollmWh) { $r.VollmWh } elseif ($full.Count -gt $i -and $full[$i].FullChargedCapacity) { [double]$full[$i].FullChargedCapacity } else { $null })
        $cycles = $(if ($r -and $null -ne $r.Zyklen) { $r.Zyklen } elseif ($cyc.Count -gt $i -and $cyc[$i].CycleCount) { [double]$cyc[$i].CycleCount } else { $null })
        $info = New-BatteryInfo $(if ($r -and $r.Name) { $r.Name } else { $bat[$i].Name }) $(if ($r) { $r.Hersteller } elseif ($static.Count -gt $i) { $static[$i].ManufactureName }) $(if ($r) { $r.Chemie }) $design $fullC $cycles
        if ($r) { $info.LaufzeitVoll = $r.LaufzeitVoll; $info.LaufzeitDesign = $r.LaufzeitDesign; $info.Verlauf = @($r.Verlauf) }
        $info | Add-Member -NotePropertyName Ladestand -NotePropertyValue $bat[$i].EstimatedChargeRemaining -Force
        $info | Add-Member -NotePropertyName Netzteil -NotePropertyValue $(if ($stat.Count -gt $i) { [bool]$stat[$i].PowerOnline } else { $null }) -Force
        $info | Add-Member -NotePropertyName Quelle -NotePropertyValue $(if ($r) { $repSrc } else { 'WMI' }) -Force
        $script:BatteryInfo += $info
        [pscustomobject][ordered]@{
            'Akku'                      = $info.Name
            'Hersteller, Chemie'        = (@($info.Hersteller, $info.Chemie) | Where-Object { $_ }) -join ', '
            'Ladestand'                 = $(if ($null -ne $info.Ladestand) { '{0} %{1}' -f $info.Ladestand, $(if ($info.Netzteil) { ', am Netzteil' } elseif ($info.Netzteil -eq $false) { ', im Akkubetrieb' }) })
            'Designkapazität'           = $(if ($info.DesignmWh) { '{0:N0} mWh' -f $info.DesignmWh })
            'Volle Ladekapazität'       = $(if ($info.VollmWh) { '{0:N0} mWh' -f $info.VollmWh })
            'Verschleiß'                = $(if ($null -ne $info.VerschleissProzent) { '{0:N1} %' -f $info.VerschleissProzent } else { 'nicht ermittelbar' })
            'Ladezyklen'                = $(if ($null -ne $info.Zyklen) { '{0:N0}' -f $info.Zyklen } else { 'nicht gemeldet' })
            'Laufzeit (volle Ladung)'   = $(if ($info.LaufzeitVoll) { (Format-Duration $info.LaufzeitVoll) + ' geschätzt' } else { 'keine Schätzung' })
            'Laufzeit (Neuzustand)'     = $(if ($info.LaufzeitDesign) { (Format-Duration $info.LaufzeitDesign) + ' geschätzt' } else { '' })
            'Quelle'                    = $info.Quelle
        } | Out-Report -List
        $hist = @($info.Verlauf | Where-Object { $_.VollmWh })
        if ($hist.Count) {
            Add-Sub ('Kapazitätsverlauf {0}' -f $info.Name)
            $step = [math]::Max(1, [int][math]::Ceiling($hist.Count / 12))
            $pick = @(for ($k = 0; $k -lt $hist.Count; $k += $step) { $hist[$k] }) + @(if (($hist.Count - 1) % $step) { $hist[$hist.Count - 1] })
            $pick | ForEach-Object { [pscustomobject][ordered]@{ Zeitraum = $_.Zeitraum; 'Volle Ladung mWh' = '{0:N0}' -f $_.VollmWh; 'Design mWh' = $(if ($_.DesignmWh) { '{0:N0}' -f $_.DesignmWh }); 'Verschleiß %' = $(if ($_.DesignmWh) { '{0:N1}' -f [math]::Max(0.0, (1 - $_.VollmWh / $_.DesignmWh) * 100) }) } } | Out-Report
        }
        $f = Get-BatteryFinding $info
        if ($f) { Add-Finding $f.Stufe 'Akku' $f.Text }
    }
    if ($script:BatteryInfo.Count) { $b0 = $script:BatteryInfo[0]; $script:Facts['Akku'] = ('{0}: {1}{2}' -f $b0.Name, $(if ($null -ne $b0.VerschleissProzent) { '{0:N0} % Verschleiß' -f $b0.VerschleissProzent } else { 'Verschleiß nicht ermittelbar' }), $(if ($null -ne $b0.Zyklen) { ', {0:N0} Zyklen' -f $b0.Zyklen } else { '' })) }
    Add-Line '  Ausführlicher Akkubericht: Akkubericht.html im Anhang'
}

Invoke-Section 'Sensoren (Momentaufnahme)' {
    Show-Sub 'Sensoren' 'werden geöffnet' -1
    [void](Open-SensorSession -Treiber:$SensorTreiber)
    # zwei Lesungen: Leistungs- und Taktsensoren brauchen einen Vergleichswert
    $rd = Get-SensorReadings -MitDatentraeger
    Start-Sleep -Milliseconds 1000
    $rd = Get-SensorReadings
    Hide-Sub
    $lead = Get-SensorLead $rd
    $script:SensorSnapshot = $rd
    Add-Line ('  {0}' -f (Get-SensorSourceText))
    $fmtV = { param($v, $u) $(if ($u -eq 'V') { ([double]$v).ToString('0.000', $script:Inv) } elseif ($u -eq 'W') { ([double]$v).ToString('0.0', $script:Inv) } else { [math]::Round([double]$v).ToString($script:Inv) }) + ' ' + $u }
    $show = @($rd | Where-Object { (-not [double]::IsNaN([double]$_.Wert) -or $_.Status -eq 'unplausibel') -and $_.Art -in 'Temperatur', 'Takt', 'Lüfter', 'Spannung', 'Leistung', 'Lüftersteuerung', 'Strom' })
    if ($show.Count) {
        $show | ForEach-Object {
            [pscustomobject][ordered]@{ Gruppe = $_.Gruppe; Gerät = $_.Geraet; Art = $_.Art; Sensor = $_.Name; Wert = $(if ($_.Status -eq 'unplausibel') { 'unplausibel (' + (& $fmtV $_.Roh $_.Einheit) + ')' } else { & $fmtV $_.Wert $_.Einheit }); Quelle = $_.Quelle }
        } | Out-Report
    } else { Add-Line '  Keine Sensorwerte verfügbar.' }
    $limits = @($rd | Where-Object { $_.Art -eq 'Grenzwert' -and -not [double]::IsNaN([double]$_.Wert) })
    if ($limits.Count) {
        Add-Sub 'Grenzwerte laut Hersteller (keine Messwerte)'
        $limits | ForEach-Object { [pscustomobject][ordered]@{ Gruppe = $_.Gruppe; Gerät = $_.Geraet; Grenzwert = $_.Name; Wert = (& $fmtV $_.Wert $_.Einheit) } } | Out-Report
        Add-Line '  Warn- und Abschalttemperaturen sind Vorgaben des Herstellers, keine gemessenen Temperaturen.'
    }
    $bad = @($rd | Where-Object { $_.Status -eq 'unplausibel' })
    foreach ($b in $bad) { Add-Line ('  Verworfen: {0} {1}: {2}' -f $b.Geraet, $b.Name, $b.Hinweis) }
    Add-Line ('  Leitwerte: CPU {0}, Takt {1}{2}, CPU-Paketleistung {3}, GPU {4}{5}, Lüfter {6}, Datenträger max {7}' -f $(if ($null -ne $lead.CpuTemp) { '{0:N0} °C ({1})' -f $lead.CpuTemp, $lead.CpuTempQ } else { 'n/v' }),
        $(if ($null -ne $lead.CpuMHz) { '{0:N0} MHz' -f $lead.CpuMHz } else { 'n/v' }), $(if ($null -ne $lead.CpuMHzMax) { ', höchster Kerntakt {0:N0} MHz' -f $lead.CpuMHzMax } else { '' }),
        $(if ($null -ne $lead.CpuW) { '{0:N1} W' -f $lead.CpuW } else { 'n/v' }), $(if ($null -ne $lead.GpuTemp) { '{0:N0} °C' -f $lead.GpuTemp } else { 'n/v' }),
        $(if ($lead.IGpuName) { ', Prozessorgrafik {0}' -f $(if ($null -ne $lead.IGpuTemp) { '{0:N0} °C' -f $lead.IGpuTemp } else { 'ohne Temperatur' }) } else { '' }),
        $(if ($null -ne $lead.Fan) { '{0:N0} U/min' -f $lead.Fan } else { 'n/v' }), $(if ($null -ne $lead.DiskTemp) { '{0:N0} °C' -f $lead.DiskTemp } else { 'n/v' }))
    if ($lead.CpuTempQ -eq 'ACPI') { Add-Line '  Hinweis: Die ACPI-Thermalzone ist oft ein Mainboard- oder Festwert, keine Kerntemperatur. Echte CPU-Werte liefert LibreHardwareMonitor mit PawnIO-Treiber.' }
    foreach ($f in (Get-SensorSnapshotFindings $rd $lead)) { Add-Finding $f.Stufe 'Sensoren' $f.Text }
    $script:SensorDb['Leerlauf'] = [ordered]@{ CpuTemp = $lead.CpuTemp; CpuTempQuelle = $lead.CpuTempQ; TjMax = $lead.TjMax; CpuMHz = $lead.CpuMHz; CpuMHzMax = $lead.CpuMHzMax; CpuW = $lead.CpuW
        Gpu = [string]$lead.GpuName; GpuTemp = $lead.GpuTemp; IGpu = [string]$lead.IGpuName; IGpuTemp = $lead.IGpuTemp; Luefter = $lead.Fan; DatentraegerTempMax = $lead.DiskTemp; Quelle = (Get-SensorSourceText) }
    if ($null -ne $lead.CpuTemp -and $lead.CpuTempQ -ne 'ACPI') { $script:Facts['CPU-Temperatur (Leerlauf)'] = ('{0:N0} °C{1}' -f $lead.CpuTemp, $(if ($lead.TjMax) { ', TjMax {0:N0} °C' -f $lead.TjMax } else { '' })) }
    Add-TestResult 'Sensoren' $(if ($show.Count) { 'OK' } else { 'Info' }) ('{0} Werte, {1}{2}' -f $show.Count, ($script:Sens.Quellen -join ', '), $(if ($bad.Count) { ', {0} unplausible Werte verworfen' -f $bad.Count } else { '' }))
}

Invoke-Section 'Netzwerkkonfiguration' {
    Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Status, Name | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress, DriverVersion,
        @{n = 'Treiberdatum'; e = { $_.DriverDate } } | Out-Report
    Add-Sub 'IP-Konfiguration aktiver Adapter'
    Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.NetAdapter.Status -eq 'Up' } | ForEach-Object {
        [pscustomobject][ordered]@{
            Adapter  = $_.InterfaceAlias
            IPv4     = ($_.IPv4Address.IPAddress -join ', ')
            Gateway  = ($_.IPv4DefaultGateway.NextHop -join ', ')
            DNS      = (($_.DNSServer | Where-Object AddressFamily -eq 2).ServerAddresses -join ', ')
            IPv6     = ($_.IPv6Address.IPAddress -join ', ')
            Netzwerk = $_.NetProfile.Name
            Profil   = $_.NetProfile.NetworkCategory
        }
    } | Out-Report -List
    Add-Sub 'Adapterstatistik'
    Get-NetAdapterStatistics -ErrorAction SilentlyContinue | ForEach-Object {
        $errs = $_.ReceivedPacketErrors + $_.OutboundPacketErrors
        if ($errs -gt 100) { Add-Finding INFO 'Netzwerk' ('{0}: {1} Paketfehler seit Adapterstart.' -f $_.Name, $errs) }
        [pscustomobject]@{ Adapter = $_.Name; Empfangen = Format-Size $_.ReceivedBytes; Gesendet = Format-Size $_.SentBytes
            'Fehler Rx/Tx' = ('{0} / {1}' -f $_.ReceivedPacketErrors, $_.OutboundPacketErrors); 'Verworfen Rx/Tx' = ('{0} / {1}' -f $_.ReceivedDiscardedPackets, $_.OutboundDiscardedPackets) }
    } | Out-Report
    if ((Get-Service WlanSvc -ErrorAction SilentlyContinue).Status -eq 'Running') {
        Add-Sub 'WLAN'
        $w = Invoke-External -File 'netsh.exe' -Arguments 'wlan show interfaces'
        $wt = Repair-Utf8AsOem ([string]$w.Output)
        if ($wt -match 'privacy-location|WlanQueryInterface') {
            # ab v2.8: Windows 11 gibt WLAN-Details ohne Standortfreigabe nicht heraus; statt der langen netsh-Anleitung eine Zeile
            Add-Line '  WLAN-Details (SSID, Signal, Funkstandard) gesperrt: Windows gibt sie ohne Standortberechtigung nicht heraus (Einstellungen, Datenschutz und Sicherheit, Standort).'
        } else { Add-Line (($wt -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { '  ' + $_.Trim() }) -join "`r`n") }
    }
    Add-Sub 'Proxy (WinHTTP)'
    $px = Invoke-External -File 'netsh.exe' -Arguments 'winhttp show proxy'
    Add-Line (($px.Output -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { '  ' + $_.Trim() }) -join "`r`n")
}

Invoke-Section 'Geräte und Treiber' {
    $codes = @{ 1 = 'nicht korrekt konfiguriert'; 3 = 'Treiber beschädigt'; 10 = 'Start fehlgeschlagen'; 12 = 'Ressourcenkonflikt'; 14 = 'Neustart nötig'; 18 = 'Treiber neu installieren'
        19 = 'Registrierung fehlerhaft'; 21 = 'wird entfernt'; 22 = 'deaktiviert'; 24 = 'nicht vorhanden/fehlerhaft'; 28 = 'kein Treiber installiert'; 31 = 'Treiber lädt nicht'
        32 = 'Dienst deaktiviert'; 37 = 'Treiberinitialisierung fehlgeschlagen'; 39 = 'Treiber beschädigt/fehlt'; 41 = 'Hardware nicht gefunden'; 43 = 'Gerät meldet Fehler'; 45 = 'nicht angeschlossen'; 52 = 'Signatur ungültig' }
    $bad = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -ne 45 })
    if ($bad.Count) {
        $bad | ForEach-Object {
            $c = [int]$_.ConfigManagerErrorCode
            $lvl = $(if ($c -eq 22) { 'INFO' } else { 'WARNUNG' })
            Add-Finding $lvl 'Geräte' ('{0}: Code {1} ({2}).' -f $_.Name, $c, $codes[$c])
            [pscustomobject]@{ 'Gerät' = $_.Name; Klasse = $_.PNPClass; Code = $c; Bedeutung = $codes[$c]; ID = $_.DeviceID }
        } | Out-Report
    } else { Add-Line '  Alle Geräte ohne Fehlercode.' }

    Add-Sub 'Treiber wichtiger Geräteklassen'
    $drv = $(if ($Kurztest) { @() } else { @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue) })
    if ($Kurztest) { Add-Line '  Treiberliste im Kurztest übersprungen.' }
    $drvList = @($drv | Where-Object { $_.DeviceClass -in 'DISPLAY', 'NET', 'SCSIADAPTER', 'HDC', 'MEDIA', 'BLUETOOTH', 'USB', 'SYSTEM' -and $_.Manufacturer -notmatch '^\(Standard|^Standard |^Microsoft$' -and $_.DeviceName } |
        Sort-Object DeviceClass, DeviceName -Unique | Select-Object DeviceClass, DeviceName, DriverVersion, @{n = 'Datum'; e = { if ($_.DriverDate) { $_.DriverDate.ToString('dd.MM.yyyy') } } }, Manufacturer)
    if ($drvList.Count) {
        try { $drvList | Export-Csv -Path (Join-Path $RawDir 'Treiber.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8 } catch { }
        $drvList | Where-Object { $_.DeviceClass -in 'DISPLAY', 'NET', 'SCSIADAPTER', 'HDC' } | Out-Report
        Add-Line ('  Gesamtliste mit {0} Treibern: Treiber.csv im Anhang' -f $drvList.Count)
    }
    Add-Sub 'Unsignierte Treiber'
    $uns = @($drv | Where-Object { $_.IsSigned -eq $false -and $_.DeviceName })
    if ($uns.Count) {
        $uns | Select-Object DeviceName, DriverVersion, InfName, Manufacturer | Out-Report
        Add-Finding INFO 'Treiber' ('{0} unsignierte Treiber gefunden.' -f $uns.Count)
    } else { Add-Line '  Keine.' }
}

Invoke-Section 'Updates' {
    try {
        $au = (New-Object -ComObject Microsoft.Update.AutoUpdate).Results
        Add-Line ('  Letzte erfolgreiche Suche       : {0}' -f $au.LastSearchSuccessDate)
        Add-Line ('  Letzte erfolgreiche Installation: {0}' -f $au.LastInstallationSuccessDate)
        if ($au.LastInstallationSuccessDate -and ([datetime]$au.LastInstallationSuccessDate) -lt (Get-Date).AddDays(-45)) {
            Add-Finding WARNUNG 'Updates' ('Letzte erfolgreiche Updateinstallation am {0:dd.MM.yyyy}.' -f [datetime]$au.LastInstallationSuccessDate)
        }
    } catch { Add-Line '  Windows-Update-Status nicht abrufbar.' }

    Add-Sub 'Zuletzt installierte Updates'
    Get-HotFix -ErrorAction SilentlyContinue | Sort-Object { $_.InstalledOn -as [datetime] } -Descending | Select-Object -First 15 HotFixID, Description, InstalledOn, InstalledBy | Out-Report

    Add-Sub 'Ausstehende Updates (Suche, max. 3 Minuten)'
    if (-not $script:Opt['Updatesuche']) { Add-Line '  Nicht ausgewählt.' }
    elseif (Test-BgJob 'Updatesuche') {
        $bj = Wait-BgJob 'Updatesuche' 'Suche nach ausstehenden Updates' 180
        if ($bj.Status -eq 'fertig') {
            $pu = @($bj.Ergebnis | Where-Object { $_ })
            if ($pu.Count) {
                $pu | Select-Object Titel, KB, Pflicht | Out-Report
                Add-Finding INFO 'Updates' ('{0} Updates stehen zur Installation bereit.' -f $pu.Count)
            } else { Add-Line '  Keine ausstehenden Updates gefunden (bzw. zentral verwaltet).' }
        } else { Add-Line ('  Updatesuche abgebrochen oder fehlgeschlagen{0}.' -f $(if ($bj.Fehler) { ': ' + $bj.Fehler } else { '' })) }
        Add-Line (Get-BgNote $bj)
    }
    else {
        $job = Start-Job -ScriptBlock {
            $s = New-Object -ComObject Microsoft.Update.Session
            $r = $s.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0")
            foreach ($u in $r.Updates) { [pscustomobject]@{ Titel = $u.Title; KB = ($u.KBArticleIDs -join ','); Pflicht = $u.IsMandatory; Neustart = $u.RebootRequired } }
        }
        if (Wait-JobWithProgress $job 'Suche nach ausstehenden Updates' 60 180) {
            $pu = @(Receive-Job $job -ErrorAction SilentlyContinue)
            if ($pu.Count) {
                $pu | Select-Object Titel, KB, Pflicht | Out-Report
                Add-Finding INFO 'Updates' ('{0} Updates stehen zur Installation bereit.' -f $pu.Count)
            } else { Add-Line '  Keine ausstehenden Updates gefunden (bzw. zentral verwaltet).' }
        } else { Add-Line '  Updatesuche nach 3 Minuten abgebrochen oder fehlgeschlagen.' ; Stop-Job $job -ErrorAction SilentlyContinue }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Section 'Autostart, Dienste, Prozesse' {
    Add-Sub 'Autostart-Einträge'
    Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Select-Object Name, Command, Location, User | Out-Report
    Add-Sub 'Geplante Aufgaben (nicht von Microsoft)'
    Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object {
        $i = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        [pscustomobject]@{ Aufgabe = ($_.TaskPath + $_.TaskName); Status = $_.State; 'Letzter Lauf' = $i.LastRunTime; Ergebnis = ('0x{0:X}' -f [int64]$i.LastTaskResult) }
    } | Out-Report
    Add-Sub 'Automatische Dienste, die mit Fehler beendet wurden'
    $svc = @(Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" -ErrorAction SilentlyContinue | Where-Object { $_.ExitCode -ne 0 })
    if ($svc.Count) {
        $svc | Select-Object Name, DisplayName, State, ExitCode | Out-Report
        Add-Finding INFO 'Dienste' ('{0} automatische Dienste laufen nicht und haben einen Fehlercode.' -f $svc.Count)
    } else { Add-Line '  Keine.' }
    Add-Sub 'Top 15 Prozesse nach Arbeitsspeicher'
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 Name, Id, @{n = 'RAM'; e = { Format-Size $_.WorkingSet64 } }, @{n = 'CPU s'; e = { [math]::Round($_.CPU, 0) } }, Handles | Out-Report
    Add-Sub 'Top 10 Prozesse nach CPU-Zeit'
    Get-Process | Where-Object CPU | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, @{n = 'CPU s'; e = { [math]::Round($_.CPU, 0) } }, @{n = 'RAM'; e = { Format-Size $_.WorkingSet64 } } | Out-Report
}

Invoke-Section 'Installierte Software' {
    $paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $sw = @(Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 -and -not $_.ParentKeyName } |
        Select-Object @{n = 'Name'; e = { $_.DisplayName.Trim() } }, @{n = 'Version'; e = { $_.DisplayVersion } }, @{n = 'Hersteller'; e = { $_.Publisher } }, @{n = 'Installiert'; e = { $_.InstallDate } } |
        Sort-Object Name -Unique)
    Add-Line ('  {0} Programme, vollständige Liste: Software.csv im Anhang' -f $sw.Count)
    try { $sw | Export-Csv -Path (Join-Path $RawDir 'Software.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8 } catch { }
    $recent = @($sw | Where-Object { $_.Installiert -match '^\d{8}$' -and $_.Installiert -ge (Get-Date).AddDays(-30).ToString('yyyyMMdd') })
    if ($recent.Count) { Add-Line '  In den letzten 30 Tagen installiert:'; $recent | Sort-Object Installiert -Descending | Out-Report }
}

if ($script:Opt['Integritaet']) {
    Invoke-Section 'Test: Dateisystem und Systemdateien' {
        Add-Sub 'Dateisystem-Onlinescan (chkdsk /scan)'
        $volRes = New-Object System.Collections.ArrayList
        foreach ($v in (Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem -in 'NTFS', 'ReFS' -and $_.DriveType -eq 'Fixed' })) {
            Write-Step ('Scanne Volume {0}: ...' -f $v.DriveLetter)
            try {
                if ((Get-Command Repair-Volume).Parameters.ContainsKey('AsJob')) {
                    $rj = Repair-Volume -DriveLetter $v.DriveLetter -Scan -AsJob -ErrorAction Stop
                    [void](Wait-JobWithProgress $rj ('Dateisystem-Scan Laufwerk {0}:' -f $v.DriveLetter) 120 3600)
                    $res = Receive-Job $rj -ErrorAction Stop
                    Remove-Job $rj -Force -ErrorAction SilentlyContinue
                } else {
                    Show-Sub ('Dateisystem-Scan Laufwerk {0}:' -f $v.DriveLetter) 'läuft'
                    $res = Repair-Volume -DriveLetter $v.DriveLetter -Scan -ErrorAction Stop
                    Hide-Sub
                }
                Add-Line ('  {0}: {1}' -f $v.DriveLetter, $res)
                [void]$volRes.Add(('{0}: {1}' -f $v.DriveLetter, $(if ("$res" -eq 'NoErrorsFound') { 'ok' } else { "$res" })))
                if ("$res" -ne 'NoErrorsFound') { Add-Finding WARNUNG 'Dateisystem' ('Volume {0}: Onlinescan meldet {1}. Abhilfe: Reparaturmodul "Dateisystemfehler beheben".' -f $v.DriveLetter, $res) }
            } catch { Add-Line ('  {0}: Scan fehlgeschlagen: {1}' -f $v.DriveLetter, $_.Exception.Message) }
        }
        $fat = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -like 'FAT*' })
        if ($fat.Count) { Add-Line ('  Nicht geprüft (FAT/FAT32, kein Onlinescan möglich): {0}' -f (($fat | ForEach-Object { '{0}:' -f $_.DriveLetter }) -join ', ')) }
        Add-TestResult 'Dateisystem-Scan (chkdsk)' $(if (@($volRes | Where-Object { $_ -notmatch ': ok$' }).Count) { 'Warnung' } else { 'OK' }) ($volRes -join ', ')

        Add-Sub 'Komponentenspeicher (DISM ScanHealth)'
        Write-Step 'DISM ScanHealth läuft (5 bis 20 Minuten) ...'
        $job = Start-Job -ScriptBlock { Repair-WindowsImage -Online -ScanHealth -NoRestart -ErrorAction Stop | Select-Object ImageHealthState }
        [void](Wait-JobWithProgress $job 'DISM ScanHealth' 600 3600)
        $dismState = ''
        try { $dr = Receive-Job $job -ErrorAction Stop; $dismState = [string]@($dr)[0].ImageHealthState } catch { Add-Line ('  DISM fehlgeschlagen: {0}' -f $_.Exception.Message) }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        if ($dismState) {
            Add-Line ('  Zustand: {0}' -f $dismState)
            Add-TestResult 'Komponentenspeicher (DISM)' $(if ($dismState -eq 'Healthy') { 'OK' } else { 'Warnung' }) $dismState
        }

        Add-Sub 'Systemdateiprüfung (sfc /verifyonly)'
        Write-Step 'sfc /verifyonly läuft (5 bis 15 Minuten) ...'
        $sfcStart = Get-Date
        # SFC-Fehler dürfen den DISM-Befund nicht verschlucken: die Einordnung läuft auch, wenn SFC oder CBS.log scheitern
        $sfcClean = $false; $sfcViol = $false; $cbs = [pscustomobject]@{ Cannot = @(); Corrupt = @(); Files = @() }; $files = ''
        try {
            $sfc = Invoke-External -File "$env:windir\System32\sfc.exe" -Arguments '/verifyonly' -TimeoutSec 3600 -Encoding ([Text.Encoding]::Unicode) -Progress 'Systemdateiprüfung sfc /verifyonly' -ExpectedSec 600
            $sfcLines = ($sfc.Output -split "[`r`n]+") | Where-Object { $_.Trim() -and $_ -notmatch '\d+\s*%' }
            Add-Line (($sfcLines | ForEach-Object { '  ' + $_.Trim() }) -join "`r`n")
            Add-Line ('  Rückgabecode: {0}' -f $sfc.ExitCode)
            $cbs = Get-CbsEntries $sfcStart
            Add-Line ('  CBS.log: {0} nicht reparierbare, {1} beschädigte oder abweichende Einträge' -f $cbs.Cannot.Count, $cbs.Corrupt.Count)
            if ($cbs.Files.Count) { Add-Line ('  Betroffene Dateien: {0}' -f (($cbs.Files | Select-Object -First 20) -join ', ')) }
            (@($cbs.Cannot) + @($cbs.Corrupt)) | Select-Object -First 15 | ForEach-Object { Add-Line ('    ' + $_) }
            $sfcClean = $sfc.Output -match 'keine Integritätsverletzungen|did not find any integrity violations'
            $sfcViol  = (-not $sfcClean) -and ($sfc.Output -match 'Integritätsverletzungen|integrity violations|beschädigte Dateien|corrupt files')
            $files = $(if ($cbs.Files.Count) { ' Betroffen: ' + (($cbs.Files | Select-Object -First 8) -join ', ') + '.' } else { '' })
        } catch { Add-Line ('  sfc /verifyonly fehlgeschlagen: {0}' -f $_.Exception.Message) }
        # Einordnung von DISM und SFC zusammen: ein Befund statt zweier, Hash-Abweichungen bei intaktem DISM nur als Hinweis
        $ia = Get-IntegrityAssessment -DismState $dismState -SfcClean ([bool]$sfcClean) -SfcViolations ([bool]$sfcViol) -CannotRepair $cbs.Cannot.Count -Corrupt $cbs.Corrupt.Count -Files @($cbs.Files)
        $script:IntegrityInfo = $ia
        Add-Line ('  Einordnung: {0}' -f $ia.Einordnung)
        if ($ia.Stufe) { Add-Finding $ia.Stufe 'Systemdateien' $ia.Befund }
        $sfcStatus = $(if ($cbs.Cannot.Count) { 'Fehler' } elseif ($sfcClean) { 'OK' } elseif ($ia.Stufe -eq 'INFO') { 'Info' } elseif ($cbs.Corrupt.Count -or $sfcViol) { 'Warnung' } else { 'Info' })
        Add-TestResult 'Systemdateien (sfc /verifyonly)' $sfcStatus $(if ($sfcClean) { 'keine Integritätsverletzungen' } elseif ($sfcViol -or $cbs.Corrupt.Count) { 'Integritätsverletzungen gefunden' + $files } else { 'Ergebnis siehe Details' })
    }
}

if ($script:Opt['Defender'] -and $script:DefenderActive) {
    Invoke-Section 'Test: Microsoft Defender Schnellscan' {
        $t0 = Get-Date
        $bj = $null
        if (Test-BgJob 'Defender') {
            $bj = Wait-BgJob 'Defender' 'Defender Schnellscan' 3600
            if ($bj.Start) { $t0 = $bj.Start }
        } else { Write-Step 'Defender Schnellscan läuft ...' }
        try {
            if ($bj) {
                # Scan lief im Hintergrund (schneller Modus): nur das Ergebnis abholen
                if ($bj.Status -ne 'fertig') { throw $(if ($bj.Fehler) { $bj.Fehler } else { 'Hintergrundprüfung ' + $bj.Status }) }
            }
            elseif ((Get-Command Start-MpScan).Parameters.ContainsKey('AsJob')) {
                Show-Sub 'Defender' 'Signaturen werden aktualisiert'; Update-MpSignature -ErrorAction SilentlyContinue
                $mj = Start-MpScan -ScanType QuickScan -AsJob -ErrorAction Stop
                [void](Wait-JobWithProgress $mj 'Defender Schnellscan' 300 3600)
                Receive-Job $mj -ErrorAction SilentlyContinue | Out-Null
                Remove-Job $mj -Force -ErrorAction SilentlyContinue
            } else {
                Show-Sub 'Defender' 'Signaturen werden aktualisiert'; Update-MpSignature -ErrorAction SilentlyContinue
                Show-Sub 'Defender Schnellscan' 'läuft, Dauer meist 2 bis 10 Minuten'
                Start-MpScan -ScanType QuickScan -ErrorAction Stop
                Hide-Sub
            }
            $new = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -ge $t0 })
            Add-Line ('  Scan beendet nach {0:mm\:ss}, neue Erkennungen: {1}' -f $(if ($bj -and $bj.Ende) { $bj.Ende - $t0 } else { (Get-Date) - $t0 }), $new.Count)
            if ($bj) { Add-Line (Get-BgNote $bj) }
            Add-TestResult 'Defender Schnellscan' $(if ($new.Count) { 'Fehler' } else { 'OK' }) ('{0} neue Erkennungen' -f $new.Count)
            if ($new.Count) {
                $new | Select-Object InitialDetectionTime, ThreatID, ActionSuccess, @{n = 'Ressourcen'; e = { $_.Resources -join '; ' } } | Out-Report
                Add-Finding KRITISCH 'Sicherheit' ('Defender-Schnellscan hat {0} Bedrohungen gefunden.' -f $new.Count)
            }
        } catch { Add-Line ('  Scan nicht möglich: {0}' -f $_.Exception.Message); Add-TestResult 'Defender Schnellscan' 'Info' 'nicht möglich' }
    }
}

# ---------- SMART-Langtest starten (läuft in der Laufwerksfirmware weiter) ----------
$script:SmartTests = @()
if ($script:Opt['SmartLang'] -and $script:Smartctl -and @($script:SmartDevices).Count) {
    Invoke-Section 'Test: SMART-Langtest wird gestartet' {
        # Schneller Modus: Die Tests wurden schon im Hintergrund gestartet (früherer Start, kürzere Wartezeit am Ende)
        $bj = $null; $early = @{}
        if (Test-BgJob 'SmartLang') { $bj = Wait-BgJob 'SmartLang' 'SMART-Langtest starten' 300; foreach ($e in @($bj.Ergebnis | Where-Object { $_ })) { $early[[string]$e.Name] = $e } }
        foreach ($d in $script:SmartDevices) {
            Show-Sub 'SMART-Langtest starten' $d.name
            $st0 = Get-SmartTestState $d
            $r = $null
            if ($early.ContainsKey([string]$d.name)) {
                $e = $early[[string]$d.name]
                $r = [pscustomobject]@{ Output = [string]$e.Output; Error = [string]$e.Error; ExitCode = $e.ExitCode }
                for ($try = 0; $try -lt 3 -and -not $st0.Running; $try++) { Start-Sleep -Seconds 5; $st0 = Get-SmartTestState $d }
            }
            elseif (-not $st0.Running) {
                $r = Invoke-External -File $script:Smartctl -Arguments ('-t long -d {0} {1}' -f $d.type, $d.name) -TimeoutSec 60
                for ($try = 0; $try -lt 3 -and -not $st0.Running; $try++) { Start-Sleep -Seconds 5; $st0 = Get-SmartTestState $d }
            }
            $begun = [bool]($r -and $r.Output -match 'has begun|Testing has begun|started')
            $status = $(if ($st0.Running -or $begun) { 'läuft' } else { 'nicht gestartet' })
            $info = [pscustomobject]@{ Device = $d; Name = $d.name; Protokoll = $d.protocol; Status = $status; Fortschritt = $(if ($st0.Percent) { $st0.Percent } else { 0 }); Start = $(if ($early.ContainsKey([string]$d.name)) { $early[[string]$d.name].Start } else { Get-Date }); Ende = $null; Minuten = $st0.Minutes; Grund = '' }
            $script:SmartTests += $info
            if ($status -eq 'läuft') {
                Add-Line ('  {0}: Langtest läuft{1}' -f $d.name, $(if ($st0.Minutes) { ', vom Hersteller geschätzt ca. {0} Minuten' -f $st0.Minutes } else { '' }))
            } else {
                $msg = ''
                if ($r) { $msg = (($r.Output + "`n" + $r.Error) -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch '^smartctl |^Copyright|^===' } | Select-Object -Last 3) -join ' ' }
                if (-not $msg) { $msg = 'smartctl hat keinen Grund gemeldet' }
                $info.Grund = $msg.Trim()
                Add-Line ('  {0}: Langtest konnte nicht gestartet werden: {1}' -f $d.name, $info.Grund)
                Add-Finding INFO 'SMART' ('{0}: SMART-Langtest ließ sich nicht starten ({1}).' -f $d.name, $info.Grund)
            }
        }
        Add-Line '  Der Test läuft im Hintergrund in der Laufwerksfirmware weiter, während die übrigen Tests laufen.'
        if ($bj) { Add-Line (Get-BgNote $bj) }
    }
}

if ($script:Opt['Netzwerk']) {
    Invoke-Section 'Test: Netzwerk' {
        function Test-PingTarget([string]$Target, [int]$Count = 10) {
            $p = New-Object System.Net.NetworkInformation.Ping
            $ok = 0; $times = New-Object System.Collections.ArrayList
            for ($i = 0; $i -lt $Count; $i++) {
                try { $rp = $p.Send($Target, 1500); if ($rp.Status -eq 'Success') { $ok++; [void]$times.Add([int]$rp.RoundtripTime) } } catch { }
                Start-Sleep -Milliseconds 200
            }
            $m = $times | Measure-Object -Minimum -Maximum -Average
            [pscustomobject][ordered]@{ Ziel = $Target; Gesendet = $Count; Empfangen = $ok; 'Verlust %' = [math]::Round(($Count - $ok) / $Count * 100, 0)
                'Min ms' = $m.Minimum; 'Mittel ms' = $(if ($m.Average -ne $null) { [math]::Round($m.Average, 1) }); 'Max ms' = $m.Maximum }
        }
        $netProblems = New-Object System.Collections.ArrayList
        $mbit = $null
        $gw = (Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1).IPv4DefaultGateway.NextHop
        $targets = @(); if ($gw) { $targets += $gw }; $targets += '1.1.1.1', 'www.microsoft.com'
        Write-Step 'Ping-Tests ...'
        $ti = 0
        $pings = foreach ($t in $targets) { $ti++; Show-Sub 'Ping-Test' ('{0} ({1} von {2})' -f $t, $ti, $targets.Count) ([int](($ti - 1) / $targets.Count * 100)); Test-PingTarget $t $(if ($Kurztest) { 3 } else { 10 }) }
        Hide-Sub
        $pings | Out-Report
        foreach ($pp in $pings) {
            if ($pp.'Verlust %' -gt 0 -and $pp.'Verlust %' -lt 100) { Add-Finding WARNUNG 'Netzwerk' ('{0}: {1} % Paketverlust.' -f $pp.Ziel, $pp.'Verlust %'); [void]$netProblems.Add(('Paketverlust {0}' -f $pp.Ziel)) }
            elseif ($pp.'Verlust %' -eq 100) { Add-Finding INFO 'Netzwerk' ('{0} antwortet nicht auf Ping (evtl. per Firewall gesperrt).' -f $pp.Ziel) }
        }

        Add-Sub 'DNS und HTTPS'
        foreach ($h in 'www.microsoft.com', 'www.google.com', 'www.wikipedia.org') {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try { $a = Resolve-DnsName $h -Type A -DnsOnly -ErrorAction Stop | Where-Object Type -eq 'A' | Select-Object -First 1; $sw.Stop(); Add-Line ('  DNS {0,-20} -> {1,-16} {2} ms' -f $h, $a.IPAddress, $sw.ElapsedMilliseconds) }
            catch { Add-Line ('  DNS {0,-20} FEHLGESCHLAGEN: {1}' -f $h, $_.Exception.Message); Add-Finding WARNUNG 'Netzwerk' ('DNS-Auflösung von {0} fehlgeschlagen.' -f $h); [void]$netProblems.Add(('DNS {0}' -f $h)) }
        }
        try {
            $wc = New-Object Net.WebClient
            $wc.Proxy = [Net.WebRequest]::GetSystemWebProxy(); $wc.Proxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials
            $txt = $wc.DownloadString('http://www.msftconnecttest.com/connecttest.txt')
            Add-Line ('  Internet-Konnektivitätstest (NCSI): {0}' -f $(if ($txt -eq 'Microsoft Connect Test') { 'OK' } else { 'unerwartete Antwort (Captive Portal?)' }))
            if ($Kurztest) { Add-Line '  Downloadtest im Kurztest übersprungen.' }
            else {
                Write-Step 'Downloadtest (25 MB) ...'
                Show-Sub 'Downloadtest' '25 MB werden geladen'
                $sw = [Diagnostics.Stopwatch]::StartNew()
                $data = $wc.DownloadData('https://speed.cloudflare.com/__down?bytes=25000000')
                $sw.Stop()
                $mbit = [math]::Round(($data.Length * 8 / 1e6) / $sw.Elapsed.TotalSeconds, 1)
                Add-Line ('  Download: {0} in {1:N1} s = ca. {2} Mbit/s' -f (Format-Size $data.Length), $sw.Elapsed.TotalSeconds, $mbit)
                Hide-Sub
            }
        } catch { Add-Line ('  HTTP(S)-Test fehlgeschlagen: {0}' -f $_.Exception.Message); Add-Finding WARNUNG 'Netzwerk' 'HTTP(S)-Zugriff ins Internet fehlgeschlagen (Proxy/Firewall?).'; [void]$netProblems.Add('HTTP(S)') }
        $pingAvg = ($pings | Where-Object { $_.'Mittel ms' -ne $null } | Select-Object -Last 1).'Mittel ms'
        $netDet = ('Ping {0} ms, Download {1}' -f $pingAvg, $(if ($mbit) { "$mbit Mbit/s" } else { 'n/v' }))
        if ($netProblems.Count) { $netDet += ', Probleme: ' + ($netProblems -join ', ') }
        Add-TestResult 'Netzwerk' $(if ($netProblems.Count) { 'Warnung' } else { 'OK' }) $netDet
    }
}

if ($script:Opt['RamTest']) {
    Invoke-Section 'Test: Arbeitsspeicher (Mustertest)' {
        if (-not $TypesLoaded) { Add-Line '  Übersprungen: C#-Testroutinen nicht verfügbar (Constrained Language Mode / AppLocker).'; return }
        $os = Get-CimInstance Win32_OperatingSystem
        $free = [long]$os.FreePhysicalMemory * 1KB
        $target = [long]($free * $RamTestPercent / 100)
        if (-not [Environment]::Is64BitProcess) { $target = [math]::Min($target, 1.2GB) }
        Add-Line ('  Freier RAM: {0}, davon getestet werden {1} % ({2}).' -f (Format-Size $free), $RamTestPercent, (Format-Size $target))
        Add-Line '  Hinweis: Ein Test unter Windows erreicht nicht jeden physischen Speicherbereich. Für eine vollständige Prüfung die Windows-Speicherdiagnose oder MemTest86 nutzen.'
        $task = [DiagRam]::RunAsync($target, $RamTestPasses)
        while (-not $task.IsCompleted) {
            Show-Sub ('RAM-Mustertest   {0} %' -f [DiagRam]::Percent) ('{0}   Fehler bisher: {1}' -f [DiagRam]::Phase, [DiagRam]::Errors) ([DiagRam]::Percent)
            Start-Sleep -Milliseconds 500
        }
        Hide-Sub
        Add-Line (($task.Result -split "`r?`n" | Where-Object { $_ } | ForEach-Object { '  ' + $_ }) -join "`r`n")
        Add-TestResult 'RAM-Mustertest' $(if ([DiagRam]::Errors -gt 0) { 'Fehler' } else { 'OK' }) ('{0} getestet, {1} Durchläufe, {2} Fehler' -f (Format-Size ([DiagRam]::BytesTested)), $RamTestPasses, [DiagRam]::Errors)
        if ([DiagRam]::Errors -gt 0) { Add-Finding KRITISCH 'RAM' ('RAM-Mustertest: {0} Bitfehler gefunden. Module einzeln testen (MemTest86), XMP/EXPO deaktivieren.' -f [DiagRam]::Errors) }
    }
}

Invoke-Section 'Windows-Speicherdiagnose (frühere Ergebnisse)' {
    $md = Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } 5
    if ($md.Count) {
        $md | Select-Object TimeCreated, Id, LevelDisplayName, @{n = 'Ergebnis'; e = { Get-ShortText $_.Message 180 } } | Out-Report
        if ($md | Where-Object { $_.Id -in 1102, 1202 -or $_.Level -le 2 }) { Add-Finding KRITISCH 'RAM' 'Die Windows-Speicherdiagnose hat früher Hardwarefehler gemeldet.' }
    } else { Add-Line '  Bisher kein Lauf der Windows-Speicherdiagnose protokolliert.' }
}

# CPU-Stabilität und Drosselung: ab v2.7 nur noch im Modul Lasttest (CPU), dort mit eigenem Lastprozess, Sensorkurven
# und Drosselnachweis. Der kurze Test der Diagnose maß dasselbe mit weniger Aussagekraft.

Invoke-Section 'Energie' {
    $as = Invoke-External -File 'powercfg.exe' -Arguments '/getactivescheme'
    Add-Line ('  ' + $as.Output.Trim())
    Add-Sub 'Verfügbare Standbymodi'
    $a = Invoke-External -File 'powercfg.exe' -Arguments '/a'
    Add-Line (($a.Output -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { '  ' + $_.TrimEnd() }) -join "`r`n")
    Add-Sub 'Aktive Energieanforderungen (verhindern Standby)'
    $rq = Invoke-External -File 'powercfg.exe' -Arguments '/requests'
    Add-Line (($rq.Output -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { '  ' + $_.TrimEnd() }) -join "`r`n")
    if ($script:Opt['Energieanalyse']) {
        Add-Sub 'Energieeffizienzanalyse (60 Sekunden)'
        $bj = $null
        if (Test-BgJob 'Energieanalyse') {
            $bj = Wait-BgJob 'Energieanalyse' 'Energieanalyse und DxDiag' 600
            $er = @($bj.Ergebnis | Where-Object { $_ }) | Select-Object -First 1
            $en = $(if ($er) { [pscustomobject]@{ Output = [string]$er.Output; Error = [string]$er.Error; ExitCode = $er.ExitCode } } else { [pscustomobject]@{ Output = ('Energieanalyse im Hintergrund fehlgeschlagen: {0}' -f $bj.Fehler); Error = ''; ExitCode = -1 } })
        } else {
            Write-Step 'powercfg /energy läuft 60 Sekunden ...'
            Suspend-StandbyLock   # eigene Standby-Sperre nicht mitmessen
            $en = Invoke-External -File 'powercfg.exe' -Arguments ('/energy /output "{0}" /duration 60' -f (Join-Path $RawDir 'Energiebericht.html')) -TimeoutSec 180 -Progress 'Energieanalyse (powercfg /energy)' -ExpectedSec 65
            Resume-StandbyLock
        }
        Add-Line (($en.Output -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch 'Energiebericht\.html|energy-report' } | ForEach-Object { '  ' + $_.Trim() }) -join "`r`n")
        Add-Line '  Details: Energiebericht.html im Anhang'
        $enSum = (($en.Output -split "`r?`n") | Where-Object { $_ -match '^\s*\d+\s' } | ForEach-Object { $_.Trim() }) -join ', '
        Add-TestResult 'Energieanalyse' 'Info' $(if ($enSum) { $enSum + ' (Details im Anhang)' } else { 'Details im Anhang' })
        if ($bj) { Add-Line (Get-BgNote $bj); Add-Line '  Hinweis: Im Energiebericht ist die Last der parallel laufenden Prüfungen mit erfasst.' }
        else {
            Write-Step 'DxDiag-Bericht wird erstellt ...'
            [void](Invoke-External -File "$env:windir\System32\dxdiag.exe" -Arguments ('/t "{0}"' -f (Join-Path $RawDir 'dxdiag.txt')) -TimeoutSec 240 -Progress 'DxDiag-Bericht' -ExpectedSec 45)
        }
    }
}

# ---------- Auf SMART-Langtest warten ----------
if ($script:SmartTests | Where-Object Status -eq 'läuft') {
    Invoke-Section 'Test: SMART-Langtest Ergebnis' {
        $deadline = ($script:SmartTests | Sort-Object Start | Select-Object -First 1).Start.AddMinutes($SmartTimeoutMinutes)
        Write-Step ('Warte auf den SMART-Langtest (maximal bis {0:HH:mm} Uhr). Die Schaltfläche "Test beenden" beendet das Warten, der Bericht wird trotzdem erstellt.' -f $deadline)
        $skipWait = $false
        $stopFile = Join-Path $script:CpDir 'stop.flag'
        Remove-Item $stopFile -Force -ErrorAction SilentlyContinue
        Send-GuiEvent 'STOP' '1'
        while ((Get-Date) -lt $deadline) {
            $running = @($script:SmartTests | Where-Object Status -eq 'läuft')
            if (-not $running.Count) { break }
            foreach ($t in $running) {
                $st = Get-SmartTestState $t.Device
                if ($st.Running) { $t.Fortschritt = $st.Percent } else { $t.Status = 'beendet'; $t.Ende = Get-Date; $t.Fortschritt = 100 }
            }
            $still = @($script:SmartTests | Where-Object Status -eq 'läuft')
            if (-not $still.Count) { break }
            $avg = ($still | Measure-Object Fortschritt -Average).Average
            $txt = ($still | ForEach-Object { '{0}: {1} %' -f $_.Name, $_.Fortschritt }) -join '   '
            $left = $deadline - (Get-Date)
            for ($w = 0; $w -lt 30; $w++) {
                Show-Sub ('SMART-Langtest   {0} %' -f [int]$avg) ('{0}   Zeitlimit in {1:hh\:mm\:ss}' -f $txt, ($left - [TimeSpan]::FromSeconds($w))) ([math]::Max(0, [math]::Min(100, [int]$avg)))
                Start-Sleep -Seconds 1
                if (Test-Path $stopFile) { Remove-Item $stopFile -Force -ErrorAction SilentlyContinue; $skipWait = $true; break }
            }
            if ($skipWait) { Write-Step 'Warten auf SMART-Langtest vom Benutzer beendet.'; break }
        }
        Hide-Sub
        Send-GuiEvent 'STOP' '0'
        $waitReason = $(if ($skipWait) { 'Warten vom Benutzer beendet' } else { 'Zeitlimit erreicht' })
        $waited = ((Get-Date) - ($script:SmartTests | Sort-Object Start | Select-Object -First 1).Start).TotalMinutes

        foreach ($t in $script:SmartTests) {
            $d = $t.Device
            Add-Sub ('{0} ({1})' -f $d.name, $d.protocol)
            if ($t.Status -eq 'nicht gestartet') { Add-Line ('  Langtest nicht gestartet: {0}' -f $t.Grund); Add-TestResult ('SMART-Langtest {0}' -f $d.name) 'Info' ('nicht gestartet: ' + $t.Grund); continue }
            if ($t.Status -eq 'läuft') {
                Add-Line ('  {0} nach {1:N0} Minuten. Der Test läuft im Laufwerk weiter ({2} %). Ergebnis später mit: smartctl -l selftest {3}' -f $waitReason, $waited, $t.Fortschritt, $d.name)
                Add-Finding INFO 'SMART' ('{0}: Langtest nach {1:N0} Minuten bei {2} % ({3}), Ergebnis später prüfen.' -f $d.name, $waited, $t.Fortschritt, $waitReason)
                Add-TestResult ('SMART-Langtest {0}' -f $d.name) 'Info' ('nach {0:N0} min bei {1} %, läuft im Laufwerk weiter' -f $waited, $t.Fortschritt)
                continue
            }
            Add-Line ('  Dauer: {0:hh\:mm\:ss}' -f ($t.Ende - $t.Start))
            $jr = Invoke-External -File $script:Smartctl -Arguments ('-a -l selftest -j -d {0} {1}' -f $d.type, $d.name) -TimeoutSec 120
            try { $j = $jr.Output | ConvertFrom-Json } catch { $j = $null }
            if ($j) {
                if ($j.device.protocol -eq 'NVMe') {
                    $last = $j.nvme_self_test_log.table | Select-Object -First 1
                    if (-not $last) { Add-Line '  Kein Eintrag im Selbsttestprotokoll, der Test wurde vermutlich nicht ausgeführt.'; Add-TestResult ('SMART-Langtest {0}' -f $d.name) 'Info' 'kein Eintrag im Selbsttestprotokoll' }
                    if ($last) {
                        Add-Line ('  Letzter Selbsttest: {0} -> {1} (bei {2} Betriebsstunden)' -f $last.self_test_code.string, $last.self_test_result.string, $last.power_on_hours)
                        $v = [int]$last.self_test_result.value
                        Add-TestResult ('SMART-Langtest {0} [{1}]' -f $j.model_name, $d.name) $(if ($v -eq 0) { 'OK' } elseif ($v -in 5, 6, 7) { 'Fehler' } else { 'Warnung' }) $last.self_test_result.string
                        if ($v -in 5, 6, 7) { Add-Finding KRITISCH 'SMART' ('{0}: SMART-Langtest FEHLGESCHLAGEN ({1}).' -f $d.name, $last.self_test_result.string) }
                        elseif ($v -ne 0) { Add-Finding WARNUNG 'SMART' ('{0}: SMART-Langtest abgebrochen ({1}).' -f $d.name, $last.self_test_result.string) }
                    }
                } else {
                    $last = $j.ata_smart_self_test_log.standard.table | Select-Object -First 1
                    if (-not $last) { Add-Line '  Kein Eintrag im Selbsttestprotokoll, der Test wurde vermutlich nicht ausgeführt.'; Add-TestResult ('SMART-Langtest {0}' -f $d.name) 'Info' 'kein Eintrag im Selbsttestprotokoll' }
                    if ($last) {
                        Add-Line ('  Letzter Selbsttest: {0} -> {1} (bei {2} Betriebsstunden{3})' -f $last.type.string, $last.status.string, $last.lifetime_hours, $(if ($last.lba) { ', erster Fehler-LBA ' + $last.lba } else { '' }))
                        Add-TestResult ('SMART-Langtest {0} [{1}]' -f $j.model_name, $d.name) $(if ($last.status.passed) { 'OK' } elseif ($last.status.string -match 'fail|fatal|damage') { 'Fehler' } else { 'Warnung' }) $last.status.string
                        if ($last.status.passed -eq $false) {
                            if ($last.status.string -match 'fail|fatal|damage') { Add-Finding KRITISCH 'SMART' ('{0}: SMART-Langtest FEHLGESCHLAGEN ({1}).' -f $d.name, $last.status.string) }
                            else { Add-Finding WARNUNG 'SMART' ('{0}: SMART-Langtest nicht erfolgreich ({1}).' -f $d.name, $last.status.string) }
                        }
                    }
                }
                $label = '{0} [{1}]' -f $j.model_name, $d.name
                Test-SmartJson -Json $j -Label $label | Out-Report -List
            }
            $safe = ($d.name -replace '[\\/:]', '_').Trim('_')
            (Invoke-External -File $script:Smartctl -Arguments ('-x -d {0} {1}' -f $d.type, $d.name) -TimeoutSec 180).Output | Out-File (Join-Path $RawDir ('smartctl_{0}_nachher.txt' -f $safe)) -Encoding UTF8
        }
    }
}

}   # Ende: Diagnose


# ---------- Ereignisprotokolle (Diagnose und Absturzanalyse) ----------
$script:PowerLoss = $null
if ($script:Opt['Ereignisse']) {
$script:EventDetails = @()
Invoke-Section ('Ereignisprotokolle (letzte {0} Tage)' -f $EventDays) {
    $checks = @(
        @{ N = 'Bluescreens (BugCheck 1001)';                  P = @('Microsoft-Windows-WER-SystemErrorReporting'); Id = @(1001); L = 'KRITISCH'; A = 'Stabilität' }
        @{ N = 'Unerwartetes Abschalten (Kernel-Power 41)';    P = @('Microsoft-Windows-Kernel-Power'); Id = @(41); L = 'WARNUNG'; A = 'Stabilität' }
        @{ N = 'Unerwartetes Herunterfahren (EventLog 6008)';  P = @('EventLog'); Id = @(6008); L = 'INFO'; A = 'Stabilität' }
        @{ N = 'WHEA Hardwarefehler (schwer)';                 P = @('Microsoft-Windows-WHEA-Logger'); Lv = @(1, 2); L = 'KRITISCH'; A = 'Hardware' }
        @{ N = 'WHEA korrigierte Hardwarefehler';              P = @('Microsoft-Windows-WHEA-Logger'); Lv = @(3); L = 'WARNUNG'; A = 'Hardware' }
        @{ N = 'Datenträger: fehlerhafter Block (disk 7)';     P = @('disk'); Id = @(7); L = 'KRITISCH'; A = 'Datenträger' }
        @{ N = 'Datenträger: Controllerfehler (disk 11)';      P = @('disk'); Id = @(11); L = 'WARNUNG'; A = 'Datenträger' }
        @{ N = 'Datenträger: Auslagerungsfehler (disk 51)';    P = @('disk'); Id = @(51); L = 'WARNUNG'; A = 'Datenträger' }
        @{ N = 'Datenträger: E/A wiederholt (disk 153)';       P = @('disk'); Id = @(153); L = 'WARNUNG'; A = 'Datenträger' }
        @{ N = 'SATA-Controller Reset (storahci 129)';         P = @('storahci', 'iaStorAC', 'iaStorA', 'iaStorAVC'); Id = @(129); L = 'WARNUNG'; A = 'Datenträger' }
        @{ N = 'NVMe Controllerfehler/Reset (stornvme)';       P = @('stornvme'); Lv = @(1, 2, 3); L = 'WARNUNG'; A = 'Datenträger' }
        @{ N = 'NTFS Dateisystembeschädigung (55)';            P = @('Ntfs', 'Microsoft-Windows-Ntfs'); Id = @(55); L = 'WARNUNG'; A = 'Dateisystem' }
        @{ N = 'NTFS Volume braucht Reparatur (98)';           P = @('Ntfs', 'Microsoft-Windows-Ntfs'); Id = @(98); Lv = @(1, 2, 3); L = 'WARNUNG'; A = 'Dateisystem' }
        @{ N = 'Grafiktreiber reagierte nicht (Display 4101)'; P = @('Display'); Id = @(4101); L = 'WARNUNG'; A = 'Grafik' }
        @{ N = 'NVIDIA/AMD Treiberfehler';                     P = @('nvlddmkm', 'amdkmdag', 'amdwddmg'); Lv = @(1, 2); L = 'WARNUNG'; A = 'Grafik' }
        @{ N = 'Dienstabstürze (SCM 7031/7034)';               P = @('Service Control Manager'); Id = @(7031, 7034); L = 'INFO'; A = 'Dienste' }
        @{ N = 'Windows-Update Installationsfehler (20)';      P = @('Microsoft-Windows-WindowsUpdateClient'); Id = @(20); L = 'WARNUNG'; A = 'Updates' }
        @{ N = 'Zeitsynchronisation fehlgeschlagen';           P = @('Microsoft-Windows-Time-Service'); Lv = @(2); L = 'INFO'; A = 'System' }
    )
    $ci = 0
    $overview = foreach ($c in $checks) {
        $ci++
        Show-Sub 'Ereignisprotokolle auswerten' $c.N ([int](($ci - 1) / $checks.Count * 100))
        $ev = @()
        foreach ($prov in $c.P) {
            $f = @{ LogName = 'System'; ProviderName = $prov; StartTime = $Since }
            if ($c.Id) { $f.Id = $c.Id }
            if ($c.Lv) { $f.Level = $c.Lv }
            $ev += Get-Ev $f 500
        }
        $ev = @($ev | Sort-Object RecordId -Unique | Sort-Object TimeCreated -Descending)
        $lvl = $c.L; $note = ''
        if ($c.N -like 'Windows-Update*' -and $ev.Count -and @($ev | Where-Object { $_.Message -match '\b9[A-Z0-9]{11}-' }).Count -eq $ev.Count) {
            $lvl = 'INFO'; $note = ' Nur Store-Apps betroffen, meist harmlos (0x80073D02: App war beim Update geöffnet).'
        }
        if ($ev.Count -and $c.N -like 'Bluescreens*') {
            $codes = @($ev | ForEach-Object { if ($_.Message -match '0x([0-9a-fA-F]{8})') { [Convert]::ToInt64($Matches[1], 16) } } | Group-Object | Sort-Object Count -Descending)
            if ($codes.Count) {
                $note = ' Stoppcodes: ' + (($codes | ForEach-Object { '0x{0:X} {1} ({2}x)' -f [int64]$_.Name, (Get-BugcheckName ([int64]$_.Name)), $_.Count }) -join '; ') + '.'
                if (@($codes | Where-Object { Test-MemoryBugcheck ([int64]$_.Name) }).Count) {
                    $note += ' Der Code deutet auf Arbeitsspeicher oder Treiber hin: RAM mit MemTest86 prüfen' + $(if ($script:RamProfileActive) { ', das XMP/EXPO-Profil testweise deaktivieren' } else { '' }) + ' und Treiber aktualisieren.'
                }
            }
        }
        if ($ev.Count -and $c.N -like 'Unerwartetes Abschalten*') {
            $script:PowerLoss = @(Get-PowerLossInfo $ev)
            $grp = @($script:PowerLoss | Group-Object Kategorie)
            $cnt = @{}; foreach ($g in $grp) { $cnt[$g.Name] = $g.Count }
            $names = @{ Betrieb = 'im laufenden Betrieb'; Standby = 'im Energiesparmodus'; Herunterfahren = 'beim oder nach dem Herunterfahren'; Taste = 'per Ein/Aus-Taste erzwungen'; Bluescreen = 'durch Bluescreen' }
            $note = ' Einordnung der letzten {0}: {1}.' -f $script:PowerLoss.Count, (($grp | ForEach-Object { '{0}x {1}' -f $_.Count, $names[$_.Name] }) -join ', ')
            $lvl = $(if ($cnt['Betrieb'] -or $cnt['Standby'] -ge 2) { 'WARNUNG' } else { 'INFO' })
            if ($cnt['Betrieb']) { $note += ' Abschaltungen im Betrieb deuten auf Netzteil, Überhitzung, instabile Übertaktung oder RAM-Einstellungen hin.' }
            if ($cnt['Herunterfahren'] -or $cnt['Standby']) {
                $hb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
                if ($hb -ne 0) { $note += ' Schnellstart ist aktiv: Wird der Strom nach dem Herunterfahren getrennt, protokolliert Windows das als unerwartetes Abschalten. Abhilfe: Reparaturmodul "Schnellstart deaktivieren".' }
            }
        }
        if ($ev.Count -and $c.A -in 'Datenträger', 'Dateisystem') { $note += (Get-DiskRefText $ev) }
        if ($ev.Count) {
            Add-Finding $lvl $c.A ('{0}: {1}x, zuletzt {2:dd.MM.yyyy HH:mm}.{3}' -f $c.N, $ev.Count, $ev[0].TimeCreated, $note)
            $script:EventDetails += , @{ Name = $c.N; Events = ($ev | Select-Object -First 5) }
        }
        [pscustomobject]@{ 'Prüfung' = $c.N; Anzahl = $ev.Count; Zuletzt = $(if ($ev.Count) { $ev[0].TimeCreated }) }
    }
    Show-Sub 'Ereignisprotokolle auswerten' 'Häufigste Fehler und Abstürze' 95
    $overview | Out-Report
    foreach ($d in $script:EventDetails) {
        Add-Sub $d.Name
        $d.Events | Select-Object TimeCreated, Id, ProviderName, @{n = 'Meldung'; e = { Get-ShortText $_.Message 200 } } | Out-Report
        if ($d.Name -like 'Unerwartetes Abschalten*' -and $script:PowerLoss) {
            Add-Line '  Einordnung anhand des letzten Ereignisses vor dem Neustart:'
            $script:PowerLoss | Select-Object @{n = 'Neustart'; e = { $_.Neustart.ToString('dd.MM.yyyy HH:mm') } }, @{n = 'Letzte Aktivität'; e = { if ($_.'Letzte Aktivität') { $_.'Letzte Aktivität'.ToString('dd.MM.yyyy HH:mm') } } }, 'Letztes Ereignis', Einordnung | Out-Report
        }
    }

    Add-Sub 'Häufigste Fehler im System-Protokoll'
    $sysErr = Get-Ev @{ LogName = 'System'; Level = 1, 2; StartTime = $Since } 5000
    Add-Line ('  {0} Fehler/kritische Ereignisse' -f $sysErr.Count)
    $sysErr | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 25 | ForEach-Object {
        $f = $_.Group[0]
        [pscustomobject]@{ Anzahl = $_.Count; Quelle = $f.ProviderName; ID = $f.Id; Zuletzt = $f.TimeCreated; Meldung = (Get-ShortText $f.Message 130) }
    } | Out-Report

    Add-Sub 'Häufigste Fehler im Anwendungs-Protokoll'
    $appErr = Get-Ev @{ LogName = 'Application'; Level = 1, 2; StartTime = $Since } 5000
    Add-Line ('  {0} Fehler/kritische Ereignisse' -f $appErr.Count)
    $appErr | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object {
        $f = $_.Group[0]
        [pscustomobject]@{ Anzahl = $_.Count; Quelle = $f.ProviderName; ID = $f.Id; Zuletzt = $f.TimeCreated; Meldung = (Get-ShortText $f.Message 130) }
    } | Out-Report

    Add-Sub 'Programmabstürze (Application Error 1000)'
    $crash = Get-Ev @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $Since } 3000
    $crash | Group-Object { $_.Properties[0].Value } | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object {
        [pscustomobject]@{ Anzahl = $_.Count; Programm = $_.Name; 'Fehlermodul (zuletzt)' = $_.Group[0].Properties[3].Value; Ausnahmecode = $_.Group[0].Properties[6].Value; Zuletzt = $_.Group[0].TimeCreated }
    } | Out-Report
    if ($crash.Count -gt 25) { Add-Finding INFO 'Stabilität' ('{0} Programmabstürze in {1} Tagen.' -f $crash.Count, $EventDays) }
    Add-Sub 'Programme reagieren nicht (Application Hang 1002)'
    Get-Ev @{ LogName = 'Application'; ProviderName = 'Application Hang'; Id = 1002; StartTime = $Since } 2000 | Group-Object { $_.Properties[0].Value } |
        Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { [pscustomobject]@{ Anzahl = $_.Count; Programm = $_.Name; Zuletzt = $_.Group[0].TimeCreated } } | Out-Report
}

Invoke-Section 'Absturzabbilder und Zuverlässigkeit' {
    Add-Sub 'Minidumps / Kernel-Dumps'
    $dumps = @()
    $dumps += Get-ChildItem "$env:windir\Minidump\*.dmp" -ErrorAction SilentlyContinue
    $dumps += Get-ChildItem "$env:windir\MEMORY.DMP" -ErrorAction SilentlyContinue
    $dumps += Get-ChildItem "$env:windir\LiveKernelReports" -Recurse -Filter *.dmp -ErrorAction SilentlyContinue
    if ($dumps.Count) {
        $dumps | Sort-Object LastWriteTime -Descending | Select-Object -First 20 FullName, LastWriteTime, @{n = 'Größe'; e = { Format-Size $_.Length } } | Out-Report
        $recent = @($dumps | Where-Object { $_.LastWriteTime -gt $Since -and $_.FullName -match 'Minidump|MEMORY.DMP' })
        if ($recent.Count) { Add-Finding WARNUNG 'Stabilität' ('{0} Absturzabbilder in den letzten {1} Tagen (Analyse z. B. mit WinDbg oder BlueScreenView).' -f $recent.Count, $EventDays) }
        $lkr = @($dumps | Where-Object { $_.LastWriteTime -gt $Since -and $_.FullName -match 'LiveKernelReports' })
        if ($lkr.Count) { Add-Finding INFO 'Stabilität' ('{0} Live-Kernel-Reports (oft Grafiktreiber- oder USB-Hänger).' -f $lkr.Count) }
        $big = @($dumps | Where-Object { $_.Length -gt 1GB })
        if ($big.Count) { Add-Finding INFO 'Speicherplatz' ('{0} belegt {1} (z. B. {2}), löschbar, wenn es nicht mehr zur Analyse gebraucht wird.' -f $(if ($big.Count -eq 1) { 'Ein großes Absturzabbild' } else { '{0} große Absturzabbilder' -f $big.Count }), (Format-Size (($big | Measure-Object Length -Sum).Sum)), $big[0].FullName) }
    } else { Add-Line '  Keine Absturzabbilder vorhanden.' }

    Add-Sub 'Einstellungen für Absturzabbilder'
    $cc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction SilentlyContinue
    if ($cc) {
        $cdMap = @{ 0 = 'keins'; 1 = 'vollständig'; 2 = 'Kernelspeicher'; 3 = 'klein (Minidump)'; 7 = 'automatisch' }
        Add-Line ('  Abbildtyp: {0}, automatischer Neustart: {1}' -f $cdMap[[int]$cc.CrashDumpEnabled], $(if ($cc.AutoReboot -eq 1) { 'ja' } else { 'nein' }))
        if ([int]$cc.CrashDumpEnabled -eq 0) { Add-Finding WARNUNG 'Stabilität' 'Absturzabbilder sind deaktiviert, nach einem Bluescreen fehlt die Ursache (Systemeigenschaften, Erweitert, Starten und Wiederherstellen).' }
    }

    Add-Sub 'Zuverlässigkeitsindex'
    $rsm = Get-CimInstance Win32_ReliabilityStabilityMetrics -ErrorAction SilentlyContinue | Sort-Object TimeGenerated -Descending | Select-Object -First 1
    # Ereignisse für die Erklärung: der Index bewertet rund die letzten vier Wochen, auch wenn der Bericht weniger Tage zeigt
    $relSince = $(if ($EventDays -lt 28) { (Get-Date).AddDays(-28) } else { $Since })
    $dmtf = [Management.ManagementDateTimeConverter]::ToDmtfDateTime($relSince)
    $rrAll = $(if ($Kurztest) { @() } else { @(Get-CimInstance Win32_ReliabilityRecords -Filter ("TimeGenerated > '{0}'" -f $dmtf) -ErrorAction SilentlyContinue) })
    $rr = @($rrAll | Where-Object { $_.TimeGenerated -gt $Since })
    if ($rsm) {
        $script:Stability = Get-StabilityAssessment $rsm.SystemStabilityIndex $rrAll ([int][math]::Round(((Get-Date) - $relSince).TotalDays))
        Add-Line ('  Zuverlässigkeit: {0:N1} von 10, {1} (Stand {2})' -f $rsm.SystemStabilityIndex, $script:Stability.Stufe, $rsm.TimeGenerated)
        if ($script:Stability.Erklaerung) { Add-Line ('  ' + $script:Stability.Erklaerung) }
        # ab v2.8 kurz: die Erklärung steht schon im Kopf des Berichts (bis v2.7 doppelt)
        $stU = $(if (@($script:Stability.Ursachen).Count) { ' Ursachen: {0}.' -f (@($script:Stability.Ursachen) -join ', ') } else { ' Keine neuen Fehler, der Wert erholt sich von älteren.' })
        if ($rsm.SystemStabilityIndex -lt 5) { Add-Finding WARNUNG 'Stabilität' ('Zuverlässigkeit nur {0:N1} von 10.{1}' -f $rsm.SystemStabilityIndex, $stU) }
        elseif ($rsm.SystemStabilityIndex -lt 7) { Add-Finding INFO 'Stabilität' ('Zuverlässigkeit {0:N1} von 10.{1}' -f $rsm.SystemStabilityIndex, $stU) }
    } else { Add-Line '  Nicht verfügbar (Aufgabe RacTask evtl. deaktiviert).' }
    if ($rr.Count) {
        Add-Line ('  {0} Zuverlässigkeitsereignisse, gruppiert:' -f $rr.Count)
        $rr | Group-Object SourceName, ProductName | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object {
            [pscustomobject]@{ Anzahl = $_.Count; Quelle = $_.Group[0].SourceName; Produkt = $_.Group[0].ProductName; Zuletzt = ($_.Group | Sort-Object TimeGenerated -Descending | Select-Object -First 1).TimeGenerated }
        } | Out-Report
    }
}

}


