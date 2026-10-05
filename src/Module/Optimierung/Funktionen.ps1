#region ---------- Modul Optimierung: Katalog, Zustand, Ausführung (ab v2.8) ----------
# Integriert das Windows Optimisation Pack (Marvin700) nativ: Jede Einstellung ist ein Katalogeintrag mit Kategorie,
# Risikostufe und Herkunft (Pack, Sophia-Konfiguration oder ooshutup.cfg). Sophia Script und O&O ShutUp10++ laufen
# nicht mehr; was sie taten, steht als einzelne Registry-, Dienst-, Aufgaben- oder Funktionsänderung im Katalog.
#
# Ändern     jede Änderung mit Vorher-Wert im Änderungsprotokoll, Seite Änderungen nimmt sie zurück
# Eingriff   Apps, Zusatzfeatures, Bereinigung, DDU: im Protokoll mit Weg zurück, abgesichert durch den Wiederherstellungspunkt
#
# Benutzereinstellungen (HKCU) gelten dem angemeldeten Benutzer. Läuft Leos Minibench unter einem anderen Konto
# (Ausführen als Administrator mit eigenem Admin-Konto), landen sie über HKEY_USERS\<SID> trotzdem beim richtigen Benutzer.
$script:OptKatalog = (
#>> EINBINDEN Module\Optimierung\Katalog.psd1
)
$script:OptNip = @'
#>> EINBINDEN Module\Optimierung\NvidiaProfil.nip
'@
$script:OptEnv = $null
$script:OptLog = [System.Collections.Generic.List[object]]::new()
$script:OptMetricsBefore = $null
$script:OptMetricsAfter = $null
$script:OptRestart = [System.Collections.Generic.List[string]]::new()
# DDU aus dem Windows Optimisation Pack (config\DDU.zip, Zweig main), Prüfsumme der Fassung im Projektordner
$script:OptDduZip = @{ Url = 'https://github.com/Marvin700/Windows_Optimisation_Pack/raw/main/config/DDU.zip'; SHA256 = '8840108385c0cc68306014d32b3768ee5d316515ffa9b466b5b5a1f41f10d9c2'
    Quelle = 'github.com/Marvin700/Windows_Optimisation_Pack, config/DDU.zip (Display Driver Uninstaller von Wagnardsoft)'; Lizenz = 'Freeware (Wagnardsoft), Weitergabe mit dem Optimisation Pack' }
$script:OptNpiZip = @{ Url = 'https://github.com/Orbmu2k/nvidiaProfileInspector/releases/latest/download/nvidiaProfileInspector.zip'
    Quelle = 'github.com/Orbmu2k/nvidiaProfileInspector, neueste Version'; Lizenz = 'MIT' }
$script:OptDduDir = 'LeosMinibench-DDU'
$script:OptTaskFolder = '\Leos Minibench\'

function Get-OptCatalog { return $script:OptKatalog }
function Get-OptEntries { return @($script:OptKatalog.Eintraege) }
function Get-OptCategories { return @($script:OptKatalog.Kategorien) }
function Get-OptEntry([string]$Id) { foreach ($e in $script:OptKatalog.Eintraege) { if ($e.Id -eq $Id) { return $e } }; return $null }
function Get-OptCategoryTitle([string]$Key) { foreach ($k in $script:OptKatalog.Kategorien) { if ($k.Key -eq $Key) { return $k.Titel } }; return $Key }

# Auswahl aus -Optimierungen in Katalogreihenfolge; Unbekanntes wird gemeldet
function Resolve-OptSelection([string]$Text) {
    $want = @(([string]$Text) -split '[,;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $ids = @(Get-OptEntries | ForEach-Object { $_.Id })
    return [pscustomobject]@{ Ids = @($ids | Where-Object { $want -contains $_ }); Unbekannt = @($want | Where-Object { $ids -notcontains $_ }) }
}

# Vorlage (M, S, E) als Liste von Ids; auf Domänen-PCs ohne die Einträge, die Verwaltung und Richtlinien berühren
function Get-OptPreset([string]$Letter, [bool]$Domain = $false) {
    return @(Get-OptEntries | Where-Object { ([string]$_.Vorlagen).Contains($Letter) -and -not ($Domain -and $_.Verwaltet) } | ForEach-Object { $_.Id })
}

# ---------- Umgebung: Benutzer, Windows-Version, Gehäuse, Grafik ----------
# Angemeldeter Benutzer = Besitzer von explorer.exe in der Sitzung dieses Prozesses, sonst der eigene Benutzer
function Get-OptTargetUser {
    $sid = ''; $name = ''
    try { $me = [Security.Principal.WindowsIdentity]::GetCurrent(); $sid = $me.User.Value; $name = $me.Name } catch { $name = [string]$env:USERNAME }
    $res = [pscustomobject]@{ Sid = $sid; Name = $name; Profil = [string]$env:USERPROFILE; Eigen = $true; Quelle = 'eigenes Konto' }
    try {
        $sess = (Get-Process -Id $PID).SessionId
        foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | Where-Object { $_.SessionId -eq $sess })) {
            $o = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction Stop
            if ($o.ReturnValue -ne 0 -or -not $o.Sid) { continue }
            $own = $null; try { $own = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop } catch { }
            $prof = ''
            try { $prof = [string](Get-ItemProperty -LiteralPath ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $o.Sid) -ErrorAction Stop).ProfileImagePath } catch { }
            $res = [pscustomobject]@{ Sid = [string]$o.Sid; Name = $(if ($own -and $own.User) { '{0}\{1}' -f $own.Domain, $own.User } else { [string]$o.Sid })
                Profil = $(if ($prof) { [Environment]::ExpandEnvironmentVariables($prof) } else { [string]$env:USERPROFILE }); Eigen = ([string]$o.Sid -eq $sid); Quelle = 'angemeldet (Explorer)' }
            break
        }
    } catch { }
    return $res
}

function Get-OptEnvironment([switch]$Neu) {
    if ($script:OptEnv -and -not $Neu) { return $script:OptEnv }
    $build = 0; try { $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).CurrentBuildNumber } catch { }
    if (-not $build) { try { $build = [int](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).BuildNumber } catch { } }
    $laptop = $false
    try { foreach ($c in @((Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes)) { if ([int]$c -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32) { $laptop = $true } } } catch { }
    try { if (@(Get-CimInstance Win32_Battery -ErrorAction Stop).Count) { $laptop = $true } } catch { }
    $gpus = @(); try { $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { [string]$_.Name }) } catch { }
    $domain = $false; try { $domain = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { }
    $user = Get-OptTargetUser
    $pending = $false
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { try { if (Test-Path -LiteralPath $k) { $pending = $true } } catch { } }
    $wt = $false; try { $wt = Test-Path -LiteralPath (Join-Path $user.Profil 'AppData\Local\Microsoft\WindowsApps\wt.exe') } catch { }
    $script:OptEnv = [pscustomobject]@{ Build = $build; Win11 = ($build -ge 22000); Desktop = (-not $laptop); Nvidia = [bool](@($gpus | Where-Object { $_ -match 'NVIDIA' }).Count)
        Terminal = $wt; Domain = $domain; User = $user; Neustart = $pending; Grafik = $gpus }
    return $script:OptEnv
}

# Leer = Bedingung erfüllt, sonst Grund
function Test-OptCondition($Entry, $Env) {
    switch ([string]$Entry.Bedingung) {
        'Win10'    { if ($Env.Win11) { return 'nur für Windows 10' } }
        'Win11'    { if (-not $Env.Win11) { return 'nur für Windows 11' } }
        'Desktop'  { if (-not $Env.Desktop) { return 'nur für Desktop-PCs (Notebook oder Akku erkannt)' } }
        'Nvidia'   { if (-not $Env.Nvidia) { return 'keine NVIDIA-Grafik vorhanden' } }
        'Terminal' { if (-not $Env.Terminal) { return 'Windows Terminal ist nicht installiert' } }
    }
    return ''
}

# HKCU auf den angemeldeten Benutzer lenken, {SID} ersetzen
function Resolve-OptRegPath([string]$Path, $User) {
    $p = $Path
    if ($User -and $User.Sid) { $p = $p.Replace('{SID}', $User.Sid) }
    if ($p -like 'HKCU:\*' -and $User -and -not $User.Eigen -and $User.Sid) { $p = 'Registry::HKEY_USERS\' + $User.Sid + '\' + $p.Substring(6) }
    return $p
}

# %TEMP%, %LOCALAPPDATA%, %USERPROFILE% des angemeldeten Benutzers, %WINDIR%, %SYSTEMDRIVE%, %PROGRAMDATA%
function Expand-OptPath([string]$Path, $User) {
    $prof = $(if ($User -and $User.Profil) { $User.Profil } else { [string]$env:USERPROFILE })
    $map = [ordered]@{ '%TEMP%' = (Join-Path $prof 'AppData\Local\Temp'); '%LOCALAPPDATA%' = (Join-Path $prof 'AppData\Local'); '%USERPROFILE%' = $prof
        '%WINDIR%' = [string]$env:windir; '%SYSTEMDRIVE%' = [string]$env:SystemDrive; '%PROGRAMDATA%' = [string]$env:ProgramData }
    $r = $Path
    foreach ($k in $map.Keys) { $r = $r -ireplace [regex]::Escape($k), ($map[$k] -replace '\$', '$$$$') }
    return $r
}

# ---------- Systemzugriffe (einzeln, damit Tests sie ersetzen können) ----------
function Get-OptTasks([string]$Name, [string]$Pfad = '') {
    $p = @{ ErrorAction = 'SilentlyContinue' }
    if ($Pfad) { $p.TaskPath = $Pfad }
    if ($Name -and $Name -ne '*') { $p.TaskName = $Name }
    return @(Get-ScheduledTask @p | ForEach-Object { [pscustomobject]@{ Pfad = [string]$_.TaskPath; Name = [string]$_.TaskName; Zustand = [string]$_.State } })
}
function Disable-OptTask([string]$Pfad, [string]$Name) { [void](Disable-ScheduledTask -TaskPath $Pfad -TaskName $Name -ErrorAction Stop) }
function Enable-OptTask([string]$Pfad, [string]$Name) { [void](Enable-ScheduledTask -TaskPath $Pfad -TaskName $Name -ErrorAction Stop) }
# Im Prüfmodus (Zustand für die Oberfläche) einmal alle Funktionen, Zusatzfeatures und Apps lesen statt je Eintrag
$script:OptCache = $null
function Get-OptFeatureState([string]$Name) {
    if ($script:OptCache) {
        if (-not $script:OptCache.Contains('F')) { $h = @{}; try { foreach ($f in @(Get-WindowsOptionalFeature -Online -ErrorAction Stop)) { $h[[string]$f.FeatureName] = [string]$f.State } } catch { }; $script:OptCache['F'] = $h }
        if ($script:OptCache['F'].ContainsKey($Name)) { return $script:OptCache['F'][$Name] }
        return ''
    }
    try { $f = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop; if ($f) { return [string]$f.State } } catch { }
    return ''
}
function Set-OptFeature([string]$Name, [bool]$Enable) {
    if ($Enable) { $r = Enable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -All -ErrorAction Stop }
    else { $r = Disable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -ErrorAction Stop }
    return [bool]($r -and $r.RestartNeeded)
}
function Get-OptCapabilities([string]$Muster) {
    if ($script:OptCache) {
        if (-not $script:OptCache.Contains('C')) { $script:OptCache['C'] = @(Get-WindowsCapability -Online -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Zustand = [string]$_.State } }) }
        return @($script:OptCache['C'] | Where-Object { $_.Name -like $Muster })
    }
    return @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -like $Muster } | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Zustand = [string]$_.State } })
}
function Remove-OptCapability([string]$Name) { $r = Remove-WindowsCapability -Online -Name $Name -ErrorAction Stop; return [bool]($r -and $r.RestartNeeded) }
function Get-OptApps([string]$Muster) {
    if ($script:OptCache) {
        if (-not $script:OptCache.Contains('A')) { $script:OptCache['A'] = @(Get-AppxPackage -AllUsers -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Paket = [string]$_.PackageFullName; Version = [string]$_.Version } }) }
        return @($script:OptCache['A'] | Where-Object { $_.Name -like $Muster })
    }
    return @(Get-AppxPackage -AllUsers -Name $Muster -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Paket = [string]$_.PackageFullName; Version = [string]$_.Version } })
}
function Remove-OptApp([string]$Paket) { Remove-AppxPackage -Package $Paket -AllUsers -ErrorAction Stop }
function Stop-OptService([string]$Name) { try { Stop-Service -Name $Name -Force -ErrorAction Stop; return $true } catch { return $false } }
function Test-OptRegKey([string]$Path) { return [bool](Test-Path -LiteralPath $Path) }
function New-OptRegKey([string]$Path) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
function Remove-OptRegKey([string]$Path) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }
function Get-OptVolumes { return @(Get-CimInstance Win32_Volume -Filter 'DriveType=3' -ErrorAction Stop | Where-Object { $_.DriveLetter }) }
function Set-OptVolumeProperty([string]$Letter, [hashtable]$Property) {
    $v = @(Get-CimInstance Win32_Volume -Filter ("DriveLetter='{0}'" -f $Letter) -ErrorAction Stop) | Select-Object -First 1
    if (-not $v) { throw ('Laufwerk {0} nicht gefunden.' -f $Letter) }
    Set-CimInstance -InputObject $v -Property $Property -ErrorAction Stop
}
function Get-OptHibernate { $s = Get-RegValueState 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'; return [bool]($s.Vorhanden -and [int]$s.Wert -ne 0) }
function Set-OptHibernate([bool]$On) { $r = Invoke-PowerCfg $(if ($On) { '/hibernate on' } else { '/hibernate off' }); if ($r.ExitCode -ne 0) { throw ('powercfg /hibernate meldet {0}: {1}' -f $r.ExitCode, ($r.Output + $r.Error).Trim()) } }
function Get-OptAdapterPower { return @(Get-NetAdapter -Physical -ErrorAction Stop | Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Zustand = [string]$_.AllowComputerToTurnOffDevice } }) }
function Set-OptAdapterPower([string]$Name, [string]$Zustand) { Set-NetAdapterPowerManagement -Name $Name -AllowComputerToTurnOffDevice $Zustand -NoRestart -ErrorAction Stop }
function Get-OptDefender {
    $st = $null; try { $st = Get-MpComputerStatus -ErrorAction Stop } catch { }
    if (-not $st -or -not $st.AntivirusEnabled -or [string]$st.AMRunningMode -notin 'Normal', '') { return $null }
    return (Get-MpPreference -ErrorAction Stop)
}
function Set-OptDefender([string]$Name, $Wert) { $p = @{ ErrorAction = 'Stop' }; $p[$Name] = $Wert; Set-MpPreference @p }
function Get-OptDnsInterfaces {
    $res = @()
    foreach ($a in @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })) {
        $cur = @(); try { $cur = @((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses) } catch { }
        $static = ''
        try { $static = [string](Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\' + $a.InterfaceGuid) -ErrorAction Stop).NameServer } catch { }
        $res += [pscustomobject]@{ Index = [int]$a.ifIndex; Name = [string]$a.Name; Aktuell = @($cur); Statisch = @(($static -split '[,\s]+') | Where-Object { $_ }) }
    }
    return $res
}
function Set-OptDnsServers([int]$Index, [string[]]$Server) {
    if ($Server -and $Server.Count) { Set-DnsClientServerAddress -InterfaceIndex $Index -ServerAddresses $Server -ErrorAction Stop }
    else { Set-DnsClientServerAddress -InterfaceIndex $Index -ResetServerAddresses -ErrorAction Stop }
}
function Get-OptReservedStorage { try { return [string](Get-WindowsReservedStorageState -ErrorAction Stop).ReservedStorageState } catch { return '' } }
function Set-OptReservedStorage([string]$State) { Set-WindowsReservedStorageState -State $State -ErrorAction Stop | Out-Null }
function Get-OptActiveScheme { $s = @(Get-PowerSchemes | Where-Object Aktiv | Select-Object -First 1); if ($s.Count) { return $s[0].Guid } else { return '' } }
function Set-OptActiveScheme([string]$Guid) { $r = Invoke-PowerCfg ('/setactive {0}' -f $Guid); if ($r.ExitCode -ne 0) { throw ('powercfg /setactive meldet {0}' -f $r.ExitCode) } }
function Get-OptFolderSize([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0.0 }
    $s = 0.0; foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue)) { $s += [double]$f.Length }
    return $s
}
function Get-OptFreeBytes { try { return [double](New-Object IO.DriveInfo(([string]$env:SystemDrive).TrimEnd('\') + '\')).AvailableFreeSpace } catch { return 0.0 } }

# ---------- Beschreibung einer Aktion (Hinweis in der Oberfläche, Bericht) ----------
function Format-OptAction($A) {
    switch ([string]$A.Art) {
        'Reg'     { return ('Registry {0}\{1} = {2}' -f ($A.Pfad -replace '^Registry::', '' -replace ':\\', '\'), $A.Name, $(if ($A.Typ -eq 'Binary') { '(Binärwert, {0} Bytes)' -f @($A.Wert).Count } else { '{0} ({1})' -f $A.Wert, $A.Typ })) }
        'RegKey'  { return ('Registry-Schlüssel {0} neu, mit {1} Werten' -f ($A.Pfad -replace ':\\', '\'), @($A.Werte).Count) }
        'Dienst'  { return ('Dienst {0}: Starttyp {1}, wird beendet' -f $A.Name, $(switch ($A.Start) { 'Disabled' { 'deaktiviert' } 'Manual' { 'manuell' } default { $A.Start } })) }
        'Aufgabe' { return ('Geplante Aufgabe {0}{1} deaktivieren' -f $(if ($A.Pfad) { $A.Pfad } else { '' }), $(if ($A.Name -eq '*') { '(alle)' } else { $A.Name })) }
        'Feature' { return ('Windows-Funktion {0} abschalten' -f $A.Name) }
        'Capability' { return ('Zusatzfeature {0} entfernen' -f $A.Muster) }
        'App'     { return ('App {0} für alle Benutzer entfernen' -f $A.Muster) }
        'Sonder'  {
            switch ([string]$A.Name) {
                'Cache' { return ('Inhalt löschen: {0}' -f (($A.Werte -split '\|') -join ', ')) }
                'Laufwerksname' { return ('Bezeichnung des Systemlaufwerks: {0}' -f $A.Werte) }
                'Indizierung' { return 'Win32_Volume IndexingEnabled = false für alle festen Laufwerke' }
                'Ruhezustand' { return 'powercfg /hibernate off' }
                'Energieplan' { return ('powercfg /setactive {0}' -f $A.Werte) }
                'NetzwerkEnergie' { return 'Set-NetAdapterPowerManagement -AllowComputerToTurnOffDevice Disabled (physische Adapter)' }
                'Defender' { return ('Set-MpPreference {0}' -f (($A.Werte -split ';') -join ', ')) }
                'DnsOverHttps' { return ('DNS-Server {0} für aktive Adapter, EnableAutoDoh = 2' -f $A.Werte) }
                'Speicherreserve' { return 'Set-WindowsReservedStorageState Disabled' }
                'Wartungsaufgaben' { return ('drei geplante Aufgaben unter {0}' -f $script:OptTaskFolder) }
                'OneDriveEntfernen' { return 'OneDriveSetup.exe /uninstall' }
                'DnsCache' { return 'ipconfig /flushdns, Clear-BCCache' }
                'Leistungszaehler' { return 'lodctr /r' }
                'Komponentenspeicher' { return 'DISM /AnalyzeComponentStore, /StartComponentCleanup, /SPSuperseded' }
                'Datentraegerbereinigung' { return 'cleanmgr /sagerun mit allen Kategorien außer Downloads' }
                'Leerlaufaufgaben' { return 'rundll32 advapi32.dll,ProcessIdleTasks' }
                'Wiederherstellungspunkte' { return 'vssadmin delete shadows /for=<Systemlaufwerk> /all' }
                'Ddu' { return 'bcdedit safeboot minimal, RunOnce: DDU -silent -cleanallgpus ... -restart' }
                'NvidiaProfil' { return 'nvidiaProfileInspector.exe <Profil> -silent' }
            }
            return [string]$A.Name
        }
    }
    return [string]$A.Art
}

# Kurzfassung des Katalogs für die Oberfläche, eine Zeile je Eintrag (| kommt in Texten nicht vor):
#   K|Key|Titel|Text
#   E|Id|Kat|Risiko|Neustart|Vorlagen|Verwaltet|Bedingung|Minuten|Titel|Hinweistext
function Get-OptGuiLines {
    $l = New-Object System.Collections.Generic.List[string]
    $clean = { param($v) (([string]$v) -replace '[\r\n|]+', ' ').Trim() }
    foreach ($k in (Get-OptCategories)) { $l.Add(('K|{0}|{1}|{2}' -f $k.Key, (& $clean $k.Titel), (& $clean $k.Text))) }
    foreach ($e in (Get-OptEntries)) {
        $tip = New-Object System.Text.StringBuilder
        [void]$tip.Append($e.Text)
        if ($e.Hinweis) { [void]$tip.Append(' ¶Hinweis: ').Append($e.Hinweis) }
        [void]$tip.Append(' ¶Änderungen:')
        $acts = @($e.Aktionen)
        for ($i = 0; $i -lt $acts.Count -and $i -lt 8; $i++) { [void]$tip.Append(' ¶· ').Append((Format-OptAction $acts[$i])) }
        if ($acts.Count -gt 8) { [void]$tip.Append((' ¶· und {0} weitere' -f ($acts.Count - 8))) }
        [void]$tip.Append(' ¶Herkunft: ').Append($e.Quelle)
        $l.Add(('E|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}' -f $e.Id, $e.Kat, $e.Risiko, $e.Neustart, $e.Vorlagen, $(if ($e.Verwaltet) { '1' } else { '0' }), $e.Bedingung, [int]$e.Minuten, (& $clean $e.Titel), (& $clean $tip.ToString())))
    }
    return $l.ToArray()
}

# ---------- Ausführen und Prüfen ----------
# Ergebnis einer Aktion: Status geaendert, bereits, fehlt (nicht vorhanden), offen (nur prüfen), unklar (nicht prüfbar), Fehler
function New-OptResult([string]$Status, [string]$Text = '', [int]$Changes = 0, [bool]$Restart = $false) {
    return [pscustomobject]@{ Status = $Status; Text = $Text; Aenderungen = $Changes; Neustart = $Restart }
}

function Test-OptRegValue($State, $Wert, [string]$Typ) {
    if (-not $State.Vorhanden) { return $false }
    if ($Typ -and $State.Typ -and $State.Typ -ne $Typ) { return $false }
    return ((Get-ValueText $State.Wert) -eq (Get-ValueText (ConvertTo-RegValue $Wert $Typ)))
}

function Invoke-OptAction($Entry, $A, $Env, [switch]$Pruefen) {
    $mod = 'Optimierung'; $step = [string]$Entry.Id; $ttl = [string]$Entry.Titel
    switch ([string]$A.Art) {
        'Reg' {
            $p = Resolve-OptRegPath $A.Pfad $Env.User
            $before = Get-RegValueState $p $A.Name
            if (Test-OptRegValue $before $A.Wert $A.Typ) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' ('{0} ist {1}' -f $A.Name, (Get-ValueText $before.Wert))) }
            $r = Set-RegistryValueLogged -Path $p -Name $A.Name -Value $A.Wert -Type $A.Typ -Modul $mod -Schritt $step -Titel $ttl
            if (-not $r) { return (New-OptResult 'bereits') }
            return (New-OptResult 'geaendert' '' 1)
        }
        'RegKey' {
            $p = Resolve-OptRegPath $A.Pfad $Env.User
            $exists = Test-OptRegKey $p
            $diff = 0
            foreach ($w in @($A.Werte)) {
                $kp = $(if ($w.Unterschluessel) { Join-Path $p $w.Unterschluessel } else { $p })
                if (-not (Test-OptRegValue (Get-RegValueState $kp $w.Name) $w.Wert $w.Typ)) { $diff++ }
            }
            if (-not $diff) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen') }
            if ($exists) {
                # Schlüssel gab es schon: nur die abweichenden Werte einzeln (mit Vorher-Wert) setzen
                $n = 0
                foreach ($w in @($A.Werte)) {
                    $kp = $(if ($w.Unterschluessel) { Join-Path $p $w.Unterschluessel } else { $p })
                    if (Set-RegistryValueLogged -Path $kp -Name $w.Name -Value $w.Wert -Type $w.Typ -Modul $mod -Schritt $step -Titel $ttl) { $n++ }
                }
                return (New-OptResult 'geaendert' '' $n)
            }
            New-OptRegKey $p
            foreach ($w in @($A.Werte)) {
                $kp = $(if ($w.Unterschluessel) { Join-Path $p $w.Unterschluessel } else { $p })
                if (-not (Test-OptRegKey $kp)) { New-OptRegKey $kp }
                Set-RegValueState $kp $w.Name $w.Wert $w.Typ
            }
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'RegSchluessel' -Ziel ($p -replace '^Registry::', '') -Vorher '(nicht vorhanden)' -Nachher ('{0} Werte' -f @($A.Werte).Count) `
                -Daten ([ordered]@{ Pfad = $p }) -Gegenbefehl ('Remove-Item -LiteralPath ''{0}'' -Recurse' -f $p))
            return (New-OptResult 'geaendert' '' 1)
        }
        'Dienst' {
            $st = ''
            try { $st = Get-ServiceStartType $A.Name } catch { return (New-OptResult 'fehlt' ('Dienst {0} gibt es hier nicht' -f $A.Name)) }
            if ($st -eq [string]$A.Start) {
                if (-not $Pruefen -and $A.Start -eq 'Disabled') { [void](Stop-OptService $A.Name) }
                return (New-OptResult 'bereits')
            }
            if ($Pruefen) { return (New-OptResult 'offen' ('{0}: {1}' -f $A.Name, $st)) }
            try { [void](Set-ServiceStartTypeLogged -Name $A.Name -StartType $A.Start -Modul $mod -Schritt $step -Titel $ttl) }
            catch {
                # Benutzerdienst-Vorlagen und geschützte Dienste: Starttyp direkt in der Registry (ebenfalls mit Vorher-Wert)
                $code = @{ Automatic = 2; Manual = 3; Disabled = 4 }[[string]$A.Start]
                try { [void](Set-RegistryValueLogged -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $A.Name) -Name 'Start' -Value $code -Type 'DWord' -Modul $mod -Schritt $step -Titel $ttl) }
                catch { return (New-OptResult 'Fehler' ('Dienst {0}: {1}' -f $A.Name, $_.Exception.Message)) }
            }
            if ($A.Start -eq 'Disabled') { [void](Stop-OptService $A.Name) }
            return (New-OptResult 'geaendert' '' 1)
        }
        'Aufgabe' {
            $tasks = @(Get-OptTasks -Name $A.Name -Pfad $A.Pfad)
            if (-not $tasks.Count) { return (New-OptResult 'fehlt' ('Aufgabe {0} gibt es hier nicht' -f $A.Name)) }
            $on = @($tasks | Where-Object { $_.Zustand -ne 'Disabled' })
            if (-not $on.Count) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' ('{0} aktiv' -f (($on | ForEach-Object { $_.Name }) -join ', '))) }
            $n = 0; $err = @()
            foreach ($t in $on) {
                try {
                    Disable-OptTask $t.Pfad $t.Name
                    [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'Aufgabe' -Ziel ('Aufgabe {0}{1}' -f $t.Pfad, $t.Name) -Vorher $t.Zustand -Nachher 'Disabled' `
                        -Daten ([ordered]@{ Pfad = $t.Pfad; Name = $t.Name; Vorher = $t.Zustand }) -Gegenbefehl ('Enable-ScheduledTask -TaskPath ''{0}'' -TaskName ''{1}''' -f $t.Pfad, $t.Name))
                    $n++
                } catch { $err += ('{0}: {1}' -f $t.Name, $_.Exception.Message) }
            }
            if ($err.Count -and -not $n) { return (New-OptResult 'Fehler' ($err -join '; ')) }
            return (New-OptResult 'geaendert' ($err -join '; ') $n)
        }
        'Feature' {
            $st = Get-OptFeatureState $A.Name
            if (-not $st) { return (New-OptResult 'fehlt' ('Funktion {0} gibt es hier nicht' -f $A.Name)) }
            if ($st -ne 'Enabled') { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' ('{0} aktiv' -f $A.Name)) }
            Show-Sub ('Windows-Funktion {0} wird abgeschaltet' -f $A.Name) 'DISM' -1
            try { $rs = Set-OptFeature $A.Name $false } catch { Hide-Sub; return (New-OptResult 'Fehler' ('{0}: {1}' -f $A.Name, $_.Exception.Message)) }
            Hide-Sub
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'Feature' -Ziel ('Windows-Funktion {0}' -f $A.Name) -Vorher 'Enabled' -Nachher 'Disabled' `
                -Daten ([ordered]@{ Name = $A.Name; Vorher = 'Enabled' }) -Gegenbefehl ('Enable-WindowsOptionalFeature -Online -FeatureName {0} -NoRestart' -f $A.Name))
            return (New-OptResult 'geaendert' '' 1 $rs)
        }
        'Capability' {
            $caps = @(); try { $caps = @(Get-OptCapabilities $A.Muster) } catch { return (New-OptResult 'Fehler' $_.Exception.Message) }
            $inst = @($caps | Where-Object { $_.Zustand -eq 'Installed' })
            if (-not $caps.Count) { return (New-OptResult 'fehlt' ('kein Zusatzfeature {0}' -f $A.Muster)) }
            if (-not $inst.Count) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' (($inst | ForEach-Object { $_.Name }) -join ', ')) }
            $n = 0; $rs = $false; $err = @()
            foreach ($c in $inst) {
                Show-Sub ('Zusatzfeature {0} wird entfernt' -f $c.Name) 'DISM' -1
                try {
                    if (Remove-OptCapability $c.Name) { $rs = $true }
                    [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Eingriff' -Art 'Zusatzfeature' -Ziel $c.Name -Vorher 'Installed' -Nachher 'entfernt' `
                        -Daten ([ordered]@{ Name = $c.Name }) -Gegenbefehl ('Add-WindowsCapability -Online -Name {0} (lädt über Windows Update)' -f $c.Name) -NurHinweis)
                    $n++
                } catch { $err += ('{0}: {1}' -f $c.Name, $_.Exception.Message) }
                Hide-Sub
            }
            if ($err.Count -and -not $n) { return (New-OptResult 'Fehler' ($err -join '; ')) }
            return (New-OptResult 'geaendert' ($err -join '; ') $n $rs)
        }
        'App' {
            $apps = @(); try { $apps = @(Get-OptApps $A.Muster) } catch { return (New-OptResult 'Fehler' $_.Exception.Message) }
            if (-not $apps.Count) { return (New-OptResult 'bereits' ('{0} nicht installiert' -f $A.Muster)) }
            if ($Pruefen) { return (New-OptResult 'offen' ('{0} installiert' -f $A.Muster)) }
            $n = 0; $err = @()
            foreach ($ap in @($apps | Sort-Object Paket -Unique)) {
                try {
                    Remove-OptApp $ap.Paket
                    [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Eingriff' -Art 'App' -Ziel $ap.Name -Vorher ('installiert ({0})' -f $ap.Version) -Nachher 'entfernt' `
                        -Daten ([ordered]@{ Name = $ap.Name; Paket = $ap.Paket }) -Gegenbefehl ('Im Microsoft Store neu installieren ({0})' -f $ap.Name) -NurHinweis)
                    $n++
                } catch { $err += ('{0}: {1}' -f $ap.Name, $_.Exception.Message) }
            }
            if ($err.Count -and -not $n) { return (New-OptResult 'Fehler' ($err -join '; ')) }
            return (New-OptResult 'geaendert' ($err -join '; ') $n)
        }
        'Sonder' { return (Invoke-OptSpecial $Entry $A $Env -Pruefen:$Pruefen) }
    }
    return (New-OptResult 'Fehler' ('Unbekannte Aktion {0}' -f $A.Art))
}

function Invoke-OptSpecial($Entry, $A, $Env, [switch]$Pruefen) {
    $mod = 'Optimierung'; $step = [string]$Entry.Id; $ttl = [string]$Entry.Titel
    switch ([string]$A.Name) {
        'Laufwerksname' {
            $d = ([string]$env:SystemDrive).TrimEnd('\')
            $v = @(Get-OptVolumes | Where-Object { [string]$_.DriveLetter -eq $d }) | Select-Object -First 1
            if (-not $v) { return (New-OptResult 'fehlt' 'Systemlaufwerk nicht gefunden') }
            $old = [string]$v.Label
            if ($old -eq [string]$A.Werte) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' ('heißt {0}' -f $(if ($old) { $old } else { '(ohne Namen)' }))) }
            Set-OptVolumeProperty $d @{ Label = [string]$A.Werte }
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'Laufwerksname' -Ziel ('Laufwerk {0}' -f $d) -Vorher $old -Nachher $A.Werte `
                -Daten ([ordered]@{ Laufwerk = $d; Vorher = $old; Nachher = [string]$A.Werte }) -Gegenbefehl ('label {0} {1}' -f $d, $old))
            return (New-OptResult 'geaendert' '' 1)
        }
        'Indizierung' {
            $on = @(Get-OptVolumes | Where-Object { $_.IndexingEnabled })
            if (-not $on.Count) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' ('an auf {0}' -f (($on | ForEach-Object { $_.DriveLetter }) -join ', '))) }
            $n = 0; $err = @()
            foreach ($v in $on) {
                try {
                    Set-OptVolumeProperty ([string]$v.DriveLetter) @{ IndexingEnabled = $false }
                    [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'Indizierung' -Ziel ('Laufwerk {0}' -f $v.DriveLetter) -Vorher 'an' -Nachher 'aus' `
                        -Daten ([ordered]@{ Laufwerk = [string]$v.DriveLetter; Vorher = $true }) -Gegenbefehl ('Eigenschaften von {0}: "Zulassen, dass für Dateien ... Inhalte indiziert werden"' -f $v.DriveLetter))
                    $n++
                } catch { $err += ('{0}: {1}' -f $v.DriveLetter, $_.Exception.Message) }
            }
            if ($err.Count -and -not $n) { return (New-OptResult 'Fehler' ($err -join '; ')) }
            return (New-OptResult 'geaendert' ($err -join '; ') $n)
        }
        'Ruhezustand' {
            if (-not (Get-OptHibernate)) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' 'Ruhezustand an') }
            Set-OptHibernate $false
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'Ruhezustand' -Ziel 'Ruhezustand (hiberfil.sys)' -Vorher 'an' -Nachher 'aus' `
                -Daten ([ordered]@{ Vorher = $true }) -Gegenbefehl 'powercfg /hibernate on')
            return (New-OptResult 'geaendert' '' 1)
        }
        'Energieplan' {
            $cur = Get-OptActiveScheme
            if ($cur -eq [string]$A.Werte) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' ('aktiv: {0}' -f $cur)) }
            Set-OptActiveScheme ([string]$A.Werte)
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'Energieplan' -Ziel 'aktiver Energiesparplan' -Vorher $cur -Nachher $A.Werte `
                -Daten ([ordered]@{ AktivVorher = $cur; Nachher = [string]$A.Werte }) -Gegenbefehl ('powercfg /setactive {0}' -f $cur))
            return (New-OptResult 'geaendert' '' 1)
        }
        'NetzwerkEnergie' {
            $ad = @(); try { $ad = @(Get-OptAdapterPower) } catch { return (New-OptResult 'Fehler' $_.Exception.Message) }
            $on = @($ad | Where-Object { $_.Zustand -eq 'Enabled' })
            if (-not $ad.Count) { return (New-OptResult 'fehlt' 'keine physischen Netzwerkadapter mit Energieverwaltung') }
            if (-not $on.Count) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' (($on | ForEach-Object { $_.Name }) -join ', ')) }
            $n = 0; $err = @()
            foreach ($a in $on) {
                try {
                    Set-OptAdapterPower $a.Name 'Disabled'
                    [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'NetzwerkEnergie' -Ziel ('Netzwerkadapter {0}' -f $a.Name) -Vorher 'Enabled' -Nachher 'Disabled' `
                        -Daten ([ordered]@{ Adapter = $a.Name; Vorher = 'Enabled' }) -Gegenbefehl ('Set-NetAdapterPowerManagement -Name ''{0}'' -AllowComputerToTurnOffDevice Enabled' -f $a.Name))
                    $n++
                } catch { $err += ('{0}: {1}' -f $a.Name, $_.Exception.Message) }
            }
            if ($err.Count -and -not $n) { return (New-OptResult 'Fehler' ($err -join '; ')) }
            return (New-OptResult 'geaendert' ($err -join '; ') $n)
        }
        'Defender' {
            $pref = $null; try { $pref = Get-OptDefender } catch { }
            if (-not $pref) { return (New-OptResult 'fehlt' 'Microsoft Defender ist nicht der aktive Virenschutz') }
            $want = [ordered]@{}
            foreach ($p in @(([string]$A.Werte) -split ';' | Where-Object { $_ })) { $kv = $p -split '=', 2; $want[$kv[0]] = [int]$kv[1] }
            $diff = @($want.Keys | Where-Object { [int]$pref.$_ -ne $want[$_] })
            if (-not $diff.Count) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' (($diff | ForEach-Object { '{0} = {1}' -f $_, $pref.$_ }) -join ', ')) }
            $n = 0; $err = @()
            foreach ($k in $diff) {
                $old = [int]$pref.$k
                try {
                    Set-OptDefender $k $want[$k]
                    [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'Defender' -Ziel ('Defender {0}' -f $k) -Vorher $old -Nachher $want[$k] `
                        -Daten ([ordered]@{ Name = $k; Vorher = $old; Nachher = $want[$k] }) -Gegenbefehl ('Set-MpPreference -{0} {1}' -f $k, $old))
                    $n++
                } catch { $err += ('{0}: {1}' -f $k, $_.Exception.Message) }
            }
            if ($err.Count -and -not $n) { return (New-OptResult 'Fehler' ($err -join '; ')) }
            return (New-OptResult 'geaendert' ($err -join '; ') $n)
        }
        'DnsOverHttps' {
            $srv = @(([string]$A.Werte) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $ifs = @(); try { $ifs = @(Get-OptDnsInterfaces) } catch { return (New-OptResult 'Fehler' $_.Exception.Message) }
            if (-not $ifs.Count) { return (New-OptResult 'fehlt' 'kein aktiver physischer Netzwerkadapter') }
            $todo = @($ifs | Where-Object { (@($_.Aktuell) -join ',') -ne ($srv -join ',') })
            $doh = Get-RegValueState 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'EnableAutoDoh'
            $dohOk = Test-OptRegValue $doh 2 'DWord'
            if (-not $todo.Count -and $dohOk) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' (($ifs | ForEach-Object { '{0}: {1}' -f $_.Name, (@($_.Aktuell) -join ', ') }) -join '; ')) }
            $n = 0; $err = @()
            foreach ($i in $todo) {
                try { Set-OptDnsServers $i.Index $srv } catch { $err += ('{0}: {1}' -f $i.Name, $_.Exception.Message); continue }
                [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'DnsServer' -Ziel ('DNS-Server {0}' -f $i.Name) -Vorher $(if (@($i.Statisch).Count) { @($i.Statisch) -join ', ' } else { 'automatisch (DHCP)' }) -Nachher ($srv -join ', ') `
                    -Daten ([ordered]@{ Index = $i.Index; Adapter = $i.Name; Statisch = @($i.Statisch); Nachher = $srv }) -Gegenbefehl $(if (@($i.Statisch).Count) { 'Set-DnsClientServerAddress -InterfaceIndex {0} -ServerAddresses {1}' -f $i.Index, (@($i.Statisch) -join ',') } else { 'Set-DnsClientServerAddress -InterfaceIndex {0} -ResetServerAddresses' -f $i.Index }))
                $n++
            }
            if (Set-RegistryValueLogged -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name 'EnableAutoDoh' -Value 2 -Type 'DWord' -Modul $mod -Schritt $step -Titel $ttl) { $n++ }
            if ($err.Count -and -not $n) { return (New-OptResult 'Fehler' ($err -join '; ')) }
            return (New-OptResult 'geaendert' ($err -join '; ') $n)
        }
        'Speicherreserve' {
            $st = Get-OptReservedStorage
            if (-not $st) { return (New-OptResult 'fehlt' 'reservierter Speicher nicht abfragbar') }
            if ($st -eq 'Disabled') { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' $st) }
            try { Set-OptReservedStorage 'Disabled' } catch { return (New-OptResult 'Fehler' ('nicht möglich, solange Updates installiert werden ({0})' -f $_.Exception.Message)) }
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'Speicherreserve' -Ziel 'Reservierter Speicher' -Vorher $st -Nachher 'Disabled' `
                -Daten ([ordered]@{ Vorher = $st }) -Gegenbefehl 'Set-WindowsReservedStorageState -State Enabled')
            return (New-OptResult 'geaendert' '' 1)
        }
        'Wartungsaufgaben' {
            $plan = @(Get-OptMaintenanceTasks)
            $have = @(Get-OptTasks -Name '*' -Pfad $script:OptTaskFolder | ForEach-Object { $_.Name })
            $miss = @($plan | Where-Object { $have -notcontains $_.Name })
            if (-not $miss.Count) { return (New-OptResult 'bereits') }
            if ($Pruefen) { return (New-OptResult 'offen' (($miss | ForEach-Object { $_.Name }) -join ', ')) }
            $n = 0; $err = @()
            foreach ($t in $miss) {
                try {
                    Register-OptMaintenanceTask $t
                    [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Aendern' -Art 'AufgabeNeu' -Ziel ('Aufgabe {0}{1}' -f $script:OptTaskFolder, $t.Name) -Vorher '(nicht vorhanden)' -Nachher $t.Plan `
                        -Daten ([ordered]@{ Pfad = $script:OptTaskFolder; Name = $t.Name }) -Gegenbefehl ('Unregister-ScheduledTask -TaskPath ''{0}'' -TaskName ''{1}'' -Confirm:$false' -f $script:OptTaskFolder, $t.Name))
                    $n++
                } catch { $err += ('{0}: {1}' -f $t.Name, $_.Exception.Message) }
            }
            if ($err.Count -and -not $n) { return (New-OptResult 'Fehler' ($err -join '; ')) }
            return (New-OptResult 'geaendert' ($err -join '; ') $n)
        }
        'OneDriveEntfernen' { return (Invoke-OptOneDrive $Entry $Env -Pruefen:$Pruefen) }
        'Cache' {
            $paths = @(([string]$A.Werte) -split '\|' | ForEach-Object { Expand-OptPath $_ $Env.User } | Where-Object { $_ })
            $size = 0.0; foreach ($p in $paths) { $size += Get-OptFolderSize $p }
            if ($Pruefen) { return (New-OptResult 'unklar' ('{0:N0} MB belegt' -f ($size / 1MB))) }
            $freed = 0.0
            foreach ($p in $paths) { $freed += Clear-OptFolder $p }
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Eingriff' -Art 'Bereinigung' -Ziel ($paths -join '; ') -Vorher ('{0:N0} MB' -f ($size / 1MB)) -Nachher ('{0:N0} MB gelöscht' -f ($freed / 1MB)) `
                -Daten ([ordered]@{ Pfade = $paths; Geloescht = $freed }) -Gegenbefehl 'nicht umkehrbar (temporäre Daten)' -NurHinweis)
            return (New-OptResult 'geaendert' ('{0:N0} MB gelöscht' -f ($freed / 1MB)) 1)
        }
        'DnsCache' {
            if ($Pruefen) { return (New-OptResult 'unklar') }
            $r = Invoke-External -File 'ipconfig.exe' -Arguments '/flushdns' -TimeoutSec 60
            try { Clear-BCCache -Force -ErrorAction Stop } catch { }
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Eingriff' -Art 'Bereinigung' -Ziel 'DNS-Cache und BranchCache' -Nachher 'geleert' -Gegenbefehl 'nicht nötig, füllt sich von selbst' -NurHinweis)
            return (New-OptResult $(if ($r.ExitCode -eq 0) { 'geaendert' } else { 'Fehler' }) $(if ($r.ExitCode -ne 0) { 'ipconfig /flushdns meldet ' + $r.ExitCode } else { '' }) 1)
        }
        'Leistungszaehler' {
            if ($Pruefen) { return (New-OptResult 'unklar') }
            $r = Invoke-External -File 'lodctr.exe' -Arguments '/r' -TimeoutSec 300 -Progress 'Leistungszähler werden neu aufgebaut' -ExpectedSec 30
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Eingriff' -Art 'Leistungszaehler' -Ziel 'Leistungsindikatoren' -Nachher $(if ($r.ExitCode -eq 0) { 'neu aufgebaut' } else { 'Fehler ' + $r.ExitCode }) -Gegenbefehl 'nicht umkehrbar, erneut lodctr /r' -NurHinweis)
            return (New-OptResult $(if ($r.ExitCode -eq 0) { 'geaendert' } else { 'Fehler' }) ($r.Output + ' ' + $r.Error).Trim() 1)
        }
        'Komponentenspeicher' {
            if ($Pruefen) { return (New-OptResult 'unklar') }
            $free0 = Get-OptFreeBytes; $msg = @(); $bad = 0
            foreach ($arg in '/Online /Cleanup-Image /AnalyzeComponentStore /NoRestart', '/Online /Cleanup-Image /StartComponentCleanup /NoRestart', '/Online /Cleanup-Image /SPSuperseded /NoRestart') {
                $r = Invoke-External -File 'dism.exe' -Arguments $arg -TimeoutSec 5400 -Progress ('DISM {0}' -f ($arg -split ' ')[2]) -ExpectedSec 600
                if ($r.ExitCode -ne 0 -and $r.ExitCode -ne 3010) { $bad++; $msg += ('{0}: Code {1}' -f ($arg -split ' ')[2], $r.ExitCode) }
                if ($arg -like '*Analyze*' -and $r.Output -match '(?im)(Empfohlene Komponentenspeicherbereinigung|Component Store Cleanup Recommended)\s*:\s*(\S+)') { $msg += ('Bereinigung empfohlen: {0}' -f $Matches[2]) }
            }
            $freed = [math]::Max(0.0, (Get-OptFreeBytes) - $free0)
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Eingriff' -Art 'Bereinigung' -Ziel 'Komponentenspeicher (WinSxS)' -Nachher ('{0:N0} MB frei geworden' -f ($freed / 1MB)) -Gegenbefehl 'nicht umkehrbar' -NurHinweis)
            return (New-OptResult $(if ($bad -eq 3) { 'Fehler' } else { 'geaendert' }) ((@($msg) + ('{0:N0} MB frei geworden' -f ($freed / 1MB))) -join '; ') 1)
        }
        'Datentraegerbereinigung' {
            if ($Pruefen) { return (New-OptResult 'unklar') }
            $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
            $keys = @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'DownloadsFolder' })
            foreach ($k in $keys) { try { New-ItemProperty -LiteralPath $k.PSPath -Name 'StateFlags4711' -Value 2 -PropertyType DWord -Force -ErrorAction Stop | Out-Null } catch { } }
            $free0 = Get-OptFreeBytes
            $r = Invoke-External -File (Join-Path $env:windir 'System32\cleanmgr.exe') -Arguments '/sagerun:4711' -TimeoutSec 3600 -Progress 'Datenträgerbereinigung läuft' -ExpectedSec 600
            foreach ($k in $keys) { try { Remove-ItemProperty -LiteralPath $k.PSPath -Name 'StateFlags4711' -ErrorAction Stop } catch { } }
            $freed = [math]::Max(0.0, (Get-OptFreeBytes) - $free0)
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Eingriff' -Art 'Bereinigung' -Ziel ('Datenträgerbereinigung, {0} Kategorien' -f $keys.Count) -Nachher ('{0:N0} MB frei geworden' -f ($freed / 1MB)) -Gegenbefehl 'nicht umkehrbar' -NurHinweis)
            return (New-OptResult $(if ($r.TimedOut) { 'Fehler' } else { 'geaendert' }) ('{0:N0} MB frei geworden{1}' -f ($freed / 1MB), $(if ($r.TimedOut) { ', nach einer Stunde abgebrochen' } else { '' })) 1)
        }
        'Leerlaufaufgaben' {
            if ($Pruefen) { return (New-OptResult 'unklar') }
            Start-Process -FilePath (Join-Path $env:windir 'System32\rundll32.exe') -ArgumentList 'advapi32.dll,ProcessIdleTasks' -WindowStyle Hidden -ErrorAction Stop
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Eingriff' -Art 'Wartung' -Ziel 'Leerlaufaufgaben' -Nachher 'gestartet' -Gegenbefehl 'nicht nötig' -NurHinweis)
            return (New-OptResult 'geaendert' 'läuft im Hintergrund weiter (bis zu einer Stunde)' 1)
        }
        'Wiederherstellungspunkte' {
            if ($Pruefen) { return (New-OptResult 'unklar') }
            $d = ([string]$env:SystemDrive).TrimEnd('\')
            $r = Invoke-External -File 'vssadmin.exe' -Arguments ('delete shadows /for={0} /all /quiet' -f $d) -TimeoutSec 600
            $ok = ($r.ExitCode -eq 0 -or ($r.Output + $r.Error) -match 'No items found|Keine Elemente')
            [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Eingriff' -Art 'Wiederherstellungspunkte' -Ziel ('Schattenkopien auf {0}' -f $d) -Nachher $(if ($ok) { 'gelöscht' } else { 'Fehler ' + $r.ExitCode }) -Gegenbefehl 'nicht umkehrbar' -NurHinweis)
            return (New-OptResult $(if ($ok) { 'geaendert' } else { 'Fehler' }) ($r.Output + ' ' + $r.Error).Trim() 1)
        }
        'Ddu' { return (Invoke-OptDdu $Entry $Env -Pruefen:$Pruefen) }
        'NvidiaProfil' { return (Invoke-OptNvidiaProfile $Entry $Env -Pruefen:$Pruefen) }
    }
    return (New-OptResult 'Fehler' ('Unbekannter Ablauf {0}' -f $A.Name))
}

# Ordnerinhalt löschen, Rückgabe: freigegebene Bytes. Eigene Arbeitsordner (LeosMinibench*) bleiben unberührt.
function Clear-OptFolder([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0.0 }
    $freed = 0.0
    foreach ($i in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
        if ($i.Name -like 'LeosMinibench*') { continue }
        $sz = $(if ($i.PSIsContainer) { Get-OptFolderSize $i.FullName } else { [double]$i.Length })
        try { Remove-Item -LiteralPath $i.FullName -Recurse -Force -ErrorAction Stop; $freed += $sz }
        catch { if ($i.PSIsContainer) { $freed += [math]::Max(0.0, $sz - (Get-OptFolderSize $i.FullName)) } }
    }
    return $freed
}

# Wartungsaufgaben (Sophia CleanupTask, SoftwareDistributionTask, TempTask) ohne Skriptdateien: PowerShell-Befehl als
# -EncodedCommand in der Aufgabe selbst, Ausführung als SYSTEM
function Get-OptMaintenanceTasks {
    $clean = 'Get-ChildItem ''HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'' | Where-Object { $_.PSChildName -ne ''DownloadsFolder'' } | ForEach-Object { New-ItemProperty -LiteralPath $_.PSPath -Name StateFlags1337 -Value 2 -PropertyType DWord -Force | Out-Null }; Start-Process -FilePath "$env:windir\System32\cleanmgr.exe" -ArgumentList ''/sagerun:1337'' -Wait; Get-ChildItem ''HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'' | ForEach-Object { Remove-ItemProperty -LiteralPath $_.PSPath -Name StateFlags1337 -ErrorAction SilentlyContinue }'
    $sd = '$lim = (Get-Date).AddDays(-7); Get-ChildItem "$env:windir\SoftwareDistribution\Download" -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $lim } | Remove-Item -Force -ErrorAction SilentlyContinue'
    $tmp = '$lim = (Get-Date).AddDays(-1); $d = @("$env:windir\Temp"); Get-ChildItem ''HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'' | ForEach-Object { $p = [Environment]::ExpandEnvironmentVariables([string](Get-ItemProperty -LiteralPath $_.PSPath).ProfileImagePath); if ($p -and (Test-Path (Join-Path $p ''AppData\Local\Temp''))) { $d += (Join-Path $p ''AppData\Local\Temp'') } }; foreach ($x in $d) { Get-ChildItem -LiteralPath $x -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $lim } | Remove-Item -Force -ErrorAction SilentlyContinue }'
    return @(
        [pscustomobject]@{ Name = 'Datenträgerbereinigung'; Tage = 30; Plan = 'alle 30 Tage'; Befehl = $clean }
        [pscustomobject]@{ Name = 'Update-Downloads aufräumen'; Tage = 90; Plan = 'alle 90 Tage'; Befehl = $sd }
        [pscustomobject]@{ Name = 'Temporäre Dateien aufräumen'; Tage = 60; Plan = 'alle 60 Tage'; Befehl = $tmp }
    )
}
function Register-OptMaintenanceTask($Task) {
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Task.Befehl))
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand ' + $enc)
    $trg = New-ScheduledTaskTrigger -Daily -DaysInterval $Task.Tage -At '10:00'
    $pri = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    Register-ScheduledTask -TaskPath $script:OptTaskFolder -TaskName $Task.Name -Action $act -Trigger $trg -Principal $pri -Settings $set -Description ('Leos Minibench {0}, Modul Optimierung ({1})' -f $ScriptVersion, $Task.Plan) -Force -ErrorAction Stop | Out-Null
}

# OneDrive deinstallieren: Installation für alle Benutzer (Programme) mit /allusers, sonst je Benutzer nur im eigenen Konto
function Invoke-OptOneDrive($Entry, $Env, [switch]$Pruefen) {
    $machine = @("$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe", "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe") | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $userExe = Join-Path $Env.User.Profil 'AppData\Local\Microsoft\OneDrive\OneDrive.exe'
    $perUser = Test-Path -LiteralPath $userExe
    if (-not @($machine).Count -and -not $perUser) { return (New-OptResult 'bereits' 'OneDrive ist nicht installiert') }
    if ($Pruefen) { return (New-OptResult 'offen' 'OneDrive installiert') }
    $setup = @("$env:windir\System32\OneDriveSetup.exe", "$env:windir\SysWOW64\OneDriveSetup.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $setup) { $setup = @(Get-ChildItem -LiteralPath (Split-Path $userExe -Parent) -Recurse -Filter 'OneDriveSetup.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { $_.FullName }) | Select-Object -First 1 }
    if (-not $setup) { return (New-OptResult 'Fehler' 'OneDriveSetup.exe nicht gefunden') }
    if (-not @($machine).Count -and -not $Env.User.Eigen) { return (New-OptResult 'Fehler' ('OneDrive ist je Benutzer installiert und läuft hier unter einem anderen Konto; bitte als {0} deinstallieren (Apps und Features).' -f $Env.User.Name)) }
    Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $r = Invoke-External -File $setup -Arguments $(if (@($machine).Count) { '/uninstall /allusers' } else { '/uninstall' }) -TimeoutSec 600 -Progress 'OneDrive wird deinstalliert' -ExpectedSec 60
    [void](Add-ChangeRecord -Modul 'Optimierung' -Schritt $Entry.Id -Titel $Entry.Titel -Risiko 'Eingriff' -Art 'App' -Ziel 'Microsoft OneDrive' -Vorher 'installiert' -Nachher $(if ($r.ExitCode -eq 0) { 'deinstalliert' } else { 'Fehler ' + $r.ExitCode }) `
        -Gegenbefehl 'OneDrive von microsoft.com/onedrive neu installieren' -NurHinweis)
    return (New-OptResult $(if ($r.ExitCode -eq 0) { 'geaendert' } else { 'Fehler' }) $(if ($r.ExitCode -ne 0) { 'OneDriveSetup meldet ' + $r.ExitCode } else { 'Ordner OneDrive mit den Dateien bleibt' }) 1)
}

# ---------- Werkzeuge: DDU und NVIDIA Profile Inspector ----------
function Get-OptDduExe {
    $t = Get-ToolsDir
    if (-not $t) { return $null }
    $p = Get-VerifiedTool 'DDU' $t
    if ($p) { return $p }
    # DDU.zip von Hand in den Tools-Ordner gelegt: Prüfsumme wie beim Holen, dann auspacken und aufnehmen
    foreach ($z in @((Join-Path $t 'DDU.zip'), (Join-Path $t 'DDU\DDU.zip'))) { if (Test-Path -LiteralPath $z) { $r = Install-OptDduFromZip $z; if ($r.Ok) { return (Get-VerifiedTool 'DDU' $t) } } }
    return $null
}
function Install-OptDduFromZip([string]$Zip) {
    $t = Get-ToolsDir
    $h = Get-FileSha256 $Zip
    if ($h -ne $script:OptDduZip.SHA256) { return [pscustomobject]@{ Ok = $false; Text = ('DDU.zip hat eine unerwartete Prüfsumme ({0}…), nicht übernommen. Freigegeben ist die Fassung aus dem Windows Optimisation Pack.' -f $h.Substring(0, 12)) } }
    $dest = Join-Path $t 'DDU'
    New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop | Out-Null
    $tmp = Join-Path $dest ('_entpacken_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    try {
        Expand-Archive -LiteralPath $Zip -DestinationPath $tmp -Force -ErrorAction Stop
        $src = Join-Path $tmp 'DDU'
        if (-not (Test-Path -LiteralPath $src)) { $src = $tmp }
        Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force -ErrorAction Stop
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    $exe = Join-Path $dest 'DisplayDriverUninstaller.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return [pscustomobject]@{ Ok = $false; Text = 'DisplayDriverUninstaller.exe fehlt im Archiv.' } }
    Get-ChildItem -LiteralPath $dest -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { if (Get-Command Unblock-File -ErrorAction SilentlyContinue) { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } }
    [void](Register-Tool -Name 'DDU' -Path $exe -Lizenz $script:OptDduZip.Lizenz -Quelle $script:OptDduZip.Quelle -Herkunft ('DDU.zip mit bestätigter Prüfsumme auf {0} ausgepackt' -f $env:COMPUTERNAME) -ToolsDir $t)
    return [pscustomobject]@{ Ok = $true; Text = ('Display Driver Uninstaller übernommen ({0}).' -f $dest) }
}
function Get-OptNpiExe {
    $t = Get-ToolsDir
    if (-not $t) { return $null }
    $p = Get-VerifiedTool 'NvidiaProfileInspector' $t
    if ($p) { return $p }
    $exe = Join-Path $t 'NvidiaProfileInspector\nvidiaProfileInspector.exe'
    $m = Read-ToolManifest $t
    if ((Test-Path -LiteralPath $exe) -and -not @($m.Werkzeuge | Where-Object { $_.Name -eq 'NvidiaProfileInspector' }).Count) {
        [void](Register-Tool -Name 'NvidiaProfileInspector' -Path $exe -Lizenz $script:OptNpiZip.Lizenz -Quelle $script:OptNpiZip.Quelle -Herkunft 'im Tools-Ordner vorgefunden, Prüfsumme beim ersten Fund festgehalten' -ToolsDir $t)
        return (Get-VerifiedTool 'NvidiaProfileInspector' $t)
    }
    return $null
}
function Install-OptTools {
    $log = New-Object System.Collections.Generic.List[string]; $ok = $true
    $t = Get-ToolsDir
    if (-not $t) { return [pscustomobject]@{ Ok = $false; Meldungen = @('Kein Datenordner verfügbar.') } }
    $work = Join-Path (Join-Path $script:DataDir 'Laufzeit') ('Download-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        New-Item -ItemType Directory -Path $work -Force -ErrorAction Stop | Out-Null
        if (Get-VerifiedTool 'DDU' $t) { $log.Add('Display Driver Uninstaller liegt bereits im Tools-Ordner.') }
        else {
            try { $z = Join-Path $work 'DDU.zip'; Save-WebFile $script:OptDduZip.Url $z; $r = Install-OptDduFromZip $z; $log.Add($r.Text); if (-not $r.Ok) { $ok = $false } }
            catch { $ok = $false; $log.Add(('DDU: {0}' -f $_.Exception.Message)) }
        }
        if (Get-OptNpiExe) { $log.Add('NVIDIA Profile Inspector liegt bereits im Tools-Ordner.') }
        else {
            try {
                $z = Join-Path $work 'npi.zip'; Save-WebFile $script:OptNpiZip.Url $z
                $dest = Join-Path $t 'NvidiaProfileInspector'
                New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop | Out-Null
                Expand-Archive -LiteralPath $z -DestinationPath $dest -Force -ErrorAction Stop
                $exe = @(Get-ChildItem -LiteralPath $dest -Recurse -Filter 'nvidiaProfileInspector.exe' -ErrorAction SilentlyContinue | Select-Object -First 1)
                if (-not $exe.Count) { throw 'nvidiaProfileInspector.exe fehlt im Archiv.' }
                if ($exe[0].DirectoryName -ne $dest) { Copy-Item -Path (Join-Path $exe[0].DirectoryName '*') -Destination $dest -Recurse -Force }
                Get-ChildItem -LiteralPath $dest -Recurse -File | ForEach-Object { if (Get-Command Unblock-File -ErrorAction SilentlyContinue) { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } }
                [void](Register-Tool -Name 'NvidiaProfileInspector' -Path (Join-Path $dest 'nvidiaProfileInspector.exe') -Lizenz $script:OptNpiZip.Lizenz -Quelle $script:OptNpiZip.Quelle -Herkunft ('von GitHub geholt auf {0}, Prüfsumme beim Holen festgehalten' -f $env:COMPUTERNAME) -ToolsDir $t)
                $log.Add(('NVIDIA Profile Inspector übernommen ({0}).' -f $dest))
            } catch { $ok = $false; $log.Add(('NVIDIA Profile Inspector: {0}' -f $_.Exception.Message)) }
        }
    } finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ Ok = $ok; Meldungen = $log.ToArray() }
}

# DDU wie im Pack: Windows Update einen Tag pausieren, abgesicherter Start, DDU per RunOnce, danach normal starten.
# DDU liegt dafür lokal unter %SystemRoot%\Temp (im abgesicherten Modus ist der Stick oft nicht da); ein weiterer
# RunOnce-Eintrag löscht den Ordner bei der ersten normalen Anmeldung danach.
function Invoke-OptDdu($Entry, $Env, [switch]$Pruefen) {
    if ($Pruefen) { return (New-OptResult 'unklar' $(if (Get-OptDduExe) { 'DDU bereit' } else { 'DDU fehlt im Tools-Ordner' })) }
    if ($Env.Neustart) { return (New-OptResult 'Fehler' 'Ein Neustart steht aus (Updates). Erst neu starten, dann DDU vorbereiten.') }
    $exe = Get-OptDduExe
    if (-not $exe) { return (New-OptResult 'Fehler' 'Display Driver Uninstaller fehlt im Tools-Ordner (Seite Optimierung: Werkzeuge holen).') }
    $mod = 'Optimierung'; $step = $Entry.Id; $ttl = $Entry.Titel
    $local = Join-Path (Join-Path $env:windir 'Temp') $script:OptDduDir
    Remove-Item -LiteralPath $local -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $local -Force -ErrorAction Stop | Out-Null
    Copy-Item -Path (Join-Path (Split-Path $exe -Parent) '*') -Destination $local -Recurse -Force -ErrorAction Stop
    $pause = (Get-Date).AddDays(1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', $script:Inv)
    [void](Set-RegistryValueLogged -Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -Name 'PauseUpdatesExpiryTime' -Value $pause -Type 'String' -Modul $mod -Schritt $step -Titel ($ttl + ': Windows Update einen Tag pausiert'))
    $r = Invoke-External -File 'bcdedit.exe' -Arguments '/set {current} safeboot minimal' -TimeoutSec 60
    if ($r.ExitCode -ne 0) { Remove-Item -LiteralPath $local -Recurse -Force -ErrorAction SilentlyContinue; return (New-OptResult 'Fehler' ('bcdedit meldet {0}: {1}' -f $r.ExitCode, ($r.Output + $r.Error).Trim())) }
    $ro = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    $ddu = '"{0}" -silent -removemonitors -removephysx -removegfe -removenvbroadcast -cleanallgpus -removenvcp -removeintelcp -removeamdcp -removeamddirs -restart' -f (Join-Path $local 'DisplayDriverUninstaller.exe')
    $vals = [ordered]@{
        '*!LeosMinibench1_NormalStart' = 'cmd.exe /c "bcdedit /deletevalue {current} safeboot"'
        '*LeosMinibench2_Hinweis'      = 'cmd.exe /c start "" powershell.exe -NoExit -Command "Write-Host ''Leos Minibench: DDU entfernt die Grafiktreiber. Bitte warten (bis 10 Minuten), der PC startet danach neu.''"'
        '*LeosMinibench3_DDU'          = $ddu
        'LeosMinibench4_Aufraeumen'    = ('cmd.exe /c rd /s /q "{0}"' -f $local)
    }
    foreach ($k in $vals.Keys) { Set-RegValueState $ro $k $vals[$k] 'String' }
    [void](Add-ChangeRecord -Modul $mod -Schritt $step -Titel $ttl -Risiko 'Eingriff' -Art 'Grafiktreiber' -Ziel 'Startkonfiguration und RunOnce' -Vorher 'normaler Start' -Nachher 'nächster Start abgesichert, DDU entfernt alle Grafiktreiber' `
        -Daten ([ordered]@{ Ordner = $local; RunOnce = @($vals.Keys) }) -Gegenbefehl ('Vor dem Neustart zurück: bcdedit /deletevalue {current} safeboot, die RunOnce-Einträge LeosMinibench* löschen und {0} entfernen' -f $local) -NurHinweis)
    $script:OptRestart.Add('DDU (abgesicherter Start)')
    return (New-OptResult 'geaendert' 'Beim nächsten Neustart startet Windows im abgesicherten Modus, DDU entfernt die Grafiktreiber und startet neu. Danach den aktuellen Treiber installieren.' 1 $true)
}

# Wartet ein vorbereiteter DDU-Lauf auf den nächsten Start? (RunOnce-Einträge von Invoke-OptDdu)
function Test-OptDduPending {
    try { $k = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -ErrorAction Stop; return [bool]@($k.GetValueNames() | Where-Object { $_ -like '*LeosMinibench*' }).Count } catch { return $false }
}
function Test-OptMaintenanceTasksPresent {
    try { return [bool]@(Get-ScheduledTask -TaskPath $script:OptTaskFolder -ErrorAction Stop).Count } catch { return $false }
}

function Invoke-OptNvidiaProfile($Entry, $Env, [switch]$Pruefen) {
    $exe = Get-OptNpiExe
    if ($Pruefen) { return (New-OptResult 'unklar' $(if ($exe) { 'NVIDIA Profile Inspector bereit' } else { 'NVIDIA Profile Inspector fehlt im Tools-Ordner' })) }
    if (-not $exe) { return (New-OptResult 'Fehler' 'nvidiaProfileInspector.exe fehlt im Tools-Ordner (Seite Optimierung: Werkzeuge holen).') }
    $dir = $(if ($RawDir -and (Test-Path -LiteralPath $RawDir)) { $RawDir } else { [IO.Path]::GetTempPath() })
    $nip = Join-Path $dir 'LeosMinibench-NvidiaProfil.nip'
    [IO.File]::WriteAllText($nip, $script:OptNip, (New-Object Text.UTF8Encoding($true)))
    try { $r = Invoke-External -File $exe -Arguments ('"{0}" -silent' -f $nip) -TimeoutSec 180 -Progress 'NVIDIA-Profil wird gesetzt' -ExpectedSec 10 }
    finally { Remove-Item -LiteralPath $nip -Force -ErrorAction SilentlyContinue }
    [void](Add-ChangeRecord -Modul 'Optimierung' -Schritt $Entry.Id -Titel $Entry.Titel -Risiko 'Eingriff' -Art 'Grafiktreiber' -Ziel 'NVIDIA-Basisprofil' -Nachher $(if ($r.ExitCode -eq 0) { 'Profil des Optimisation Pack gesetzt' } else { 'Fehler ' + $r.ExitCode }) `
        -Gegenbefehl 'NVIDIA-Systemsteuerung, 3D-Einstellungen verwalten, Wiederherstellen' -NurHinweis)
    return (New-OptResult $(if ($r.ExitCode -eq 0) { 'geaendert' } else { 'Fehler' }) $(if ($r.ExitCode -ne 0) { 'Profile Inspector meldet ' + $r.ExitCode } else { '' }) 1)
}

# ---------- Ein Eintrag: ausführen oder prüfen ----------
# Zustand: aktiv (alles wie gewünscht), teilweise, offen, nicht zutreffend, nicht prüfbar (Bereinigung, Werkzeuge)
function Get-OptEntryState($Entry, $Env = (Get-OptEnvironment)) {
    $why = Test-OptCondition $Entry $Env
    if ($why) { return [pscustomobject]@{ Id = $Entry.Id; Zustand = 'nicht zutreffend'; Text = $why } }
    $st = @(); $txt = @()
    foreach ($a in @($Entry.Aktionen)) {
        try { $r = Invoke-OptAction $Entry $a $Env -Pruefen } catch { $r = New-OptResult 'unklar' $_.Exception.Message }
        $st += $r.Status; if ($r.Text) { $txt += $r.Text }
    }
    $z = $(if (@($st | Where-Object { $_ -eq 'unklar' }).Count) { 'nicht prüfbar' }
           elseif (-not @($st | Where-Object { $_ -eq 'offen' }).Count) { $(if (@($st | Where-Object { $_ -eq 'bereits' }).Count) { 'aktiv' } else { 'nicht zutreffend' }) }
           elseif (@($st | Where-Object { $_ -eq 'bereits' }).Count) { 'teilweise' } else { 'offen' })
    return [pscustomobject]@{ Id = $Entry.Id; Zustand = $z; Text = (($txt | Select-Object -Unique) -join '; ') }
}

function Invoke-OptEntry($Entry, $Env = (Get-OptEnvironment)) {
    $why = Test-OptCondition $Entry $Env
    if ($why) { return [pscustomobject]@{ Id = $Entry.Id; Titel = $Entry.Titel; Kat = $Entry.Kat; Risiko = $Entry.Risiko; Ergebnis = 'übersprungen'; Aenderungen = 0; Details = $why; Neustart = $false } }
    $n = 0; $err = @(); $info = @(); $st = @(); $rs = $false
    foreach ($a in @($Entry.Aktionen)) {
        try { $r = Invoke-OptAction $Entry $a $Env } catch { $r = New-OptResult 'Fehler' $_.Exception.Message }
        $st += $r.Status; $n += [int]$r.Aenderungen; if ($r.Neustart) { $rs = $true }
        if ($r.Status -eq 'Fehler') { $err += $r.Text } elseif ($r.Text -and $r.Status -ne 'fehlt') { $info += $r.Text }
    }
    $erg = $(if ($err.Count -and -not $n) { 'Fehler' } elseif ($err.Count) { 'teilweise' } elseif ($n) { 'angewendet' }
             elseif (@($st | Where-Object { $_ -eq 'bereits' }).Count) { 'bereits so' } else { 'nicht vorhanden' })
    if ($rs -or ($n -and $Entry.Neustart -eq 'immer')) { $rs = $true; $script:OptRestart.Add([string]$Entry.Titel) }
    $det = @($err) + @($info | Select-Object -Unique)
    return [pscustomobject]@{ Id = $Entry.Id; Titel = $Entry.Titel; Kat = $Entry.Kat; Risiko = $Entry.Risiko; Ergebnis = $erg; Aenderungen = $n; Details = ($det -join '; '); Neustart = $rs }
}

# ---------- Kennzahlen vor und nach der Optimierung ----------
function Get-OptMetrics([switch]$MitFunktionen, [switch]$MitApps) {
    $m = [ordered]@{}
    try { $svc = @(Get-Service -ErrorAction Stop); $m['Laufende Dienste'] = @($svc | Where-Object { [string]$_.Status -eq 'Running' }).Count; $m['Dienste mit automatischem Start'] = @($svc | Where-Object { [string]$_.StartType -eq 'Automatic' }).Count } catch { }
    try { $m['Laufende Prozesse'] = @(Get-Process -ErrorAction Stop).Count } catch { }
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; $m['Belegter Arbeitsspeicher (MB)'] = [int](([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) / 1024) } catch { }
    try { $m['Aktive geplante Aufgaben'] = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { [string]$_.State -ne 'Disabled' }).Count } catch { }
    $run = 0; foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run') { try { $run += @((Get-Item -LiteralPath $k -ErrorAction Stop).GetValueNames() | Where-Object { $_ }).Count } catch { } }
    $m['Autostart-Einträge (Run)'] = $run
    if ($MitFunktionen) { try { $m['Aktive Windows-Funktionen'] = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object { [string]$_.State -eq 'Enabled' }).Count } catch { } }
    if ($MitApps) { try { $m['Installierte Store-Apps'] = @(Get-AppxPackage -AllUsers -ErrorAction Stop).Count } catch { } }
    $free = Get-OptFreeBytes; if ($free -gt 0) { $m['Freier Speicher Systemlaufwerk (GB)'] = [math]::Round($free / 1GB, 1) }
    return $m
}

# Kennzahlen gegenüberstellen: Kennzahl, Vorher, Nachher, Differenz
function Get-OptMetricRows($Before, $After) {
    $rows = @()
    if (-not $Before -or -not $After) { return $rows }
    foreach ($k in $Before.Keys) {
        if (-not $After.Contains($k)) { continue }
        $b = [double]$Before[$k]; $a = [double]$After[$k]; $d = $a - $b
        $fmt = $(if ($k -match 'GB') { 'N1' } else { 'N0' })
        $rows += [pscustomobject][ordered]@{ Kennzahl = $k; Vorher = $b.ToString($fmt); Nachher = $a.ToString($fmt); Differenz = $(if ($d -eq 0) { '0' } else { ('{0}{1}' -f $(if ($d -gt 0) { '+' } else { '' }), $d.ToString($fmt)) }) }
    }
    return $rows
}

# ---------- HTML-Bericht ----------
function New-OptHtml {
    $cls = @{ 'angewendet' = 'ok'; 'bereits so' = 'skip'; 'übersprungen' = 'skip'; 'nicht vorhanden' = 'skip'; 'teilweise' = 'warn'; 'Fehler' = 'crit' }
    $log = @($script:OptLog)
    $sb = New-Object System.Text.StringBuilder
    $n = @($log | Where-Object { $_.Ergebnis -in 'angewendet', 'teilweise' }).Count
    $chg = 0; foreach ($x in $log) { $chg += [int]$x.Aenderungen }
    [void]$sb.Append('<section class="box"><div class="bar"><h2>Optimierung</h2><button onclick="var d=this.closest(''section'').querySelectorAll(''details''),o=!d[0].open;for(var i=0;i<d.length;i++)d[i].open=o">Alle auf- oder zuklappen</button></div>')
    [void]$sb.Append(('<p class="note">{0} von {1} Einträgen angewendet, {2} Einzeländerungen. Stufe Ändern: auf der Seite Änderungen einzeln rücknehmbar. Eingriff: zurück über den Wiederherstellungspunkt oder den genannten Weg.</p>' -f $n, $log.Count, $chg))
    $rows = @(Get-OptMetricRows $script:OptMetricsBefore $script:OptMetricsAfter)
    if ($rows.Count) {
        [void]$sb.Append('<h3>Kennzahlen vorher und nachher</h3><table><thead><tr><th>Kennzahl</th><th class="r">Vorher</th><th class="r">Nachher</th><th class="r">Differenz</th></tr></thead><tbody>')
        foreach ($r in $rows) { [void]$sb.Append(('<tr><td>{0}</td><td class="r">{1}</td><td class="r">{2}</td><td class="r">{3}</td></tr>' -f (ConvertTo-HtmlText $r.Kennzahl), $r.Vorher, $r.Nachher, $r.Differenz)) }
        [void]$sb.Append('</tbody></table><p class="note tight">Direkt nach der Optimierung gemessen, ohne Neustart.</p>')
    }
    foreach ($k in (Get-OptCategories)) {
        $items = @($log | Where-Object { $_.Kat -eq $k.Key })
        if (-not $items.Count) { continue }
        $ok = @($items | Where-Object { $_.Ergebnis -eq 'angewendet' }).Count
        $bad = @($items | Where-Object { $_.Ergebnis -in 'Fehler', 'teilweise' }).Count
        [void]$sb.Append(('<details{0}><summary><b>{1}</b> &middot; {2} von {3} angewendet{4}</summary>' -f $(if ($bad) { ' open' } else { '' }), (ConvertTo-HtmlText $k.Titel), $ok, $items.Count, $(if ($bad) { (' &middot; <span class="badge warn">{0} mit Fehlern</span>' -f $bad) } else { '' })))
        [void]$sb.Append('<table><thead><tr><th>Eintrag</th><th>Ergebnis</th><th class="r">Änderungen</th><th>Stufe</th><th>Details</th></tr></thead><tbody>')
        foreach ($r in $items) {
            $c = $cls[[string]$r.Ergebnis]; if (-not $c) { $c = 'info' }
            [void]$sb.Append(('<tr><td>{0}</td><td><span class="badge {1}">{2}</span></td><td class="r">{3}</td><td>{4}</td><td>{5}</td></tr>' -f (ConvertTo-HtmlText $r.Titel), $c, (ConvertTo-HtmlText $r.Ergebnis), $r.Aenderungen, (Get-RiskLabel $r.Risiko), (ConvertTo-HtmlText $r.Details)))
        }
        [void]$sb.Append('</tbody></table></details>')
    }
    [void]$sb.Append('</section>')
    return $sb.ToString()
}

# ---------- Rückgängig für die neuen Arten (aufgerufen von Undo-ChangeRecord) ----------
function Undo-OptChange($Record) {
    $d = $Record.Daten
    switch ([string]$Record.Art) {
        'Aufgabe' {
            $t = @(Get-OptTasks -Name $d.Name -Pfad $d.Pfad) | Select-Object -First 1
            if (-not $t) { return [pscustomobject]@{ Status = 'übersprungen'; Text = 'Aufgabe gibt es nicht mehr' } }
            if ($t.Zustand -ne 'Disabled') { return [pscustomobject]@{ Status = 'übersprungen'; Text = ('Aufgabe ist inzwischen {0}' -f $t.Zustand) } }
            Enable-OptTask $d.Pfad $d.Name
            return [pscustomobject]@{ Status = 'rückgängig'; Text = ('Aufgabe {0} wieder aktiv' -f $d.Name) }
        }
        'Feature' {
            if ((Get-OptFeatureState $d.Name) -eq 'Enabled') { return [pscustomobject]@{ Status = 'übersprungen'; Text = 'Funktion ist bereits wieder aktiv' } }
            $rs = Set-OptFeature $d.Name $true
            return [pscustomobject]@{ Status = 'rückgängig'; Text = ('Windows-Funktion {0} wieder aktiv{1}' -f $d.Name, $(if ($rs) { ', Neustart nötig' } else { '' })) }
        }
        'RegSchluessel' {
            if (-not (Test-OptRegKey $d.Pfad)) { return [pscustomobject]@{ Status = 'übersprungen'; Text = 'Schlüssel gibt es nicht mehr' } }
            Remove-OptRegKey $d.Pfad
            return [pscustomobject]@{ Status = 'rückgängig'; Text = 'Schlüssel entfernt (war vorher nicht vorhanden)' }
        }
        'Laufwerksname' {
            $v = @(Get-OptVolumes | Where-Object { [string]$_.DriveLetter -eq [string]$d.Laufwerk }) | Select-Object -First 1
            if ($v -and [string]$v.Label -ne [string]$d.Nachher) { return [pscustomobject]@{ Status = 'übersprungen'; Text = ('Laufwerk heißt inzwischen {0}' -f $v.Label) } }
            Set-OptVolumeProperty ([string]$d.Laufwerk) @{ Label = [string]$d.Vorher }
            return [pscustomobject]@{ Status = 'rückgängig'; Text = ('Laufwerk {0} heißt wieder {1}' -f $d.Laufwerk, $(if ($d.Vorher) { $d.Vorher } else { '(ohne Namen)' })) }
        }
        'Indizierung' {
            Set-OptVolumeProperty ([string]$d.Laufwerk) @{ IndexingEnabled = $true }
            return [pscustomobject]@{ Status = 'rückgängig'; Text = ('Indizierung auf {0} wieder an' -f $d.Laufwerk) }
        }
        'Ruhezustand' { Set-OptHibernate $true; return [pscustomobject]@{ Status = 'rückgängig'; Text = 'Ruhezustand wieder an' } }
        'Energieplan' {
            $cur = Get-OptActiveScheme
            if ($cur -ne [string]$d.Nachher) { return [pscustomobject]@{ Status = 'übersprungen'; Text = ('aktiver Plan ist inzwischen {0}' -f $cur) } }
            Set-OptActiveScheme ([string]$d.AktivVorher)
            return [pscustomobject]@{ Status = 'rückgängig'; Text = ('Energiesparplan {0} wieder aktiv' -f $d.AktivVorher) }
        }
        'NetzwerkEnergie' { Set-OptAdapterPower ([string]$d.Adapter) ([string]$d.Vorher); return [pscustomobject]@{ Status = 'rückgängig'; Text = ('{0}: Energiesparen wieder erlaubt' -f $d.Adapter) } }
        'Defender' { Set-OptDefender ([string]$d.Name) ([int]$d.Vorher); return [pscustomobject]@{ Status = 'rückgängig'; Text = ('{0} wieder {1}' -f $d.Name, $d.Vorher) } }
        'DnsServer' { Set-OptDnsServers ([int]$d.Index) ([string[]]@($d.Statisch)); return [pscustomobject]@{ Status = 'rückgängig'; Text = ('{0}: DNS wieder {1}' -f $d.Adapter, $(if (@($d.Statisch).Count) { @($d.Statisch) -join ', ' } else { 'automatisch' })) } }
        'Speicherreserve' { Set-OptReservedStorage ([string]$d.Vorher); return [pscustomobject]@{ Status = 'rückgängig'; Text = ('Reservierter Speicher wieder {0}' -f $d.Vorher) } }
        'AufgabeNeu' {
            if (-not @(Get-OptTasks -Name $d.Name -Pfad $d.Pfad).Count) { return [pscustomobject]@{ Status = 'übersprungen'; Text = 'Aufgabe gibt es nicht mehr' } }
            Unregister-ScheduledTask -TaskPath $d.Pfad -TaskName $d.Name -Confirm:$false -ErrorAction Stop
            return [pscustomobject]@{ Status = 'rückgängig'; Text = ('Aufgabe {0} entfernt' -f $d.Name) }
        }
    }
    return $null
}

#endregion
