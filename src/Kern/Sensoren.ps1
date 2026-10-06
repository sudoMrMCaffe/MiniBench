#region ---------- Sensoren: LibreHardwareMonitor, PawnIO und Ersatzquellen ----------
# Temperatur, Takt, Lüfter, Spannung und Leistung kommen bevorzugt aus LibreHardwareMonitorLib (portabel unter
# Minibench-Daten\Tools\LibreHardwareMonitor). Ab 0.9.5 liest die Bibliothek CPU-Werte und Mainboard-Chips nur über den
# Treiber PawnIO. Der Treiber wird nie ungefragt installiert: nur mit -SensorTreiber (Rückfrage in der Oberfläche),
# nur wenn er fehlt, und am Ende des Laufs wieder entfernt. Eine Markierungsdatei sorgt dafür, dass er auch nach
# einem Absturz beim nächsten Start entfernt wird. War PawnIO schon installiert, bleibt es unangetastet.
# Ohne Bibliothek oder Treiber gibt es Ersatzwerte: Windows-Leistungszähler (Takt), ACPI-Thermalzonen, nvidia-smi,
# Zuverlässigkeitszähler der Datenträger und Akkustatus aus WMI.
#
# Geladen wird nur, was zu den hier festgehaltenen SHA-256-Werten passt (Herkunft: offizielle GitHub-Releases).
# Eine neue Version von LibreHardwareMonitor braucht neue Einträge in $script:LhmPins.
$script:LhmVersion = '0.9.6'
$script:LhmSubDir  = 'LibreHardwareMonitor'
$script:LhmZip     = @{ Url = 'https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.6/LibreHardwareMonitor.zip'; SHA256 = '086d9f1b5a99e643edc2cfaaac16051685b551e4c5ac0b32a57c58c0e529c001' }
$script:LhmSource  = 'github.com/LibreHardwareMonitor/LibreHardwareMonitor, Release v0.9.6 (LibreHardwareMonitor.zip)'
$script:LhmPins = [ordered]@{
    'LibreHardwareMonitorLib.dll'                = @{ SHA256 = '6ebc194316536ba61af5be24508ad9fcbb2ecc685e716c12e787c79530f66bf0'; Lizenz = 'MPL-2.0' }
    'BlackSharp.Core.dll'                        = @{ SHA256 = 'cafb93afcc8d8a367e21f619673d05c06887d8964867fed1371f02ded1cd3e23'; Lizenz = 'siehe THIRD-PARTY-NOTICES von LibreHardwareMonitor' }
    'DiskInfoToolkit.dll'                        = @{ SHA256 = '1acbf51b3c10c51c986cf43021680d34a2e38d9a5ba652bcfa9a1b5f7fc09800'; Lizenz = 'siehe THIRD-PARTY-NOTICES von LibreHardwareMonitor' }
    'HidSharp.dll'                               = @{ SHA256 = 'd86690efde30ea9179f669320f39148853793b743a98b531afeaf30598e22f54'; Lizenz = 'Apache-2.0' }
    'RAMSPDToolkit-NDD.dll'                      = @{ SHA256 = 'b6882354c7c8ec186617e421507743dbfae09c5c1fc24cef76a1d0c0c26651de'; Lizenz = 'siehe THIRD-PARTY-NOTICES von LibreHardwareMonitor' }
    'System.Buffers.dll'                         = @{ SHA256 = '2d78d770c9cb997199154ae8c018b9f1d1efbc86729f7264dde6dbad2a12cac3'; Lizenz = 'MIT' }
    'System.Memory.dll'                          = @{ SHA256 = 'd5e8e4866f9cfa66f7765660f84b210198893e55335487afe5ebda342c0e913d'; Lizenz = 'MIT' }
    'System.Numerics.Vectors.dll'                = @{ SHA256 = '20c2fa81b8c70d651099d762954f285fd4f942e63b2d7217c145dab8d4b2f4c9'; Lizenz = 'MIT' }
    'System.Runtime.CompilerServices.Unsafe.dll' = @{ SHA256 = '08cbd7278b66f1e68425a82d4b97181a4130d93e3dd91831407aba7212ccdacf'; Lizenz = 'MIT' }
}
$script:PawnIoPin = @{
    Version = '2.2.0'; Ordner = 'PawnIO'; Datei = 'PawnIO_setup.exe'; Lizenz = 'GPL-2.0 (Treiber), Installer laut Hersteller unverändert weitergebbar'
    Url = 'https://github.com/namazso/PawnIO.Setup/releases/download/2.2.0/PawnIO_setup.exe'; SHA256 = '1f519a22e47187f70a1379a48ca604981c4fcf694f4e65b734aaa74a9fba3032'
    Quelle = 'github.com/namazso/PawnIO.Setup, Release 2.2.0'
}
$script:Sens = $null
$script:PawnIoByUs = $false
$script:PawnIoKeptRemoval = $false
$script:SensorNotes = New-Object System.Collections.Generic.List[string]
$script:SensorSnapshot = $null
$script:SensorDb = [ordered]@{}

if ($FullLanguage -and -not $ImportOrdner -and -not $Vergleich -and -not $Rueckgaengig -and -not $SensorWerkzeugeHolen -and -not $SensorAufraeumen -and -not $OptimierungZustand -and -not $OptWerkzeugeHolen -and -not $Dashboard -and -not $DashboardExport -and -not ('DiagSensors' -as [type])) {
    $sensCode = @'
#>> EINBINDEN Kern\Sensoren.cs
'@
    try { Add-CachedType 'LeosMinibench-Sensoren' $sensCode }
    catch { Write-Warning ('Sensorroutinen konnten nicht geladen werden: {0}' -f $_.Exception.Message) }
}
$SensorTypesLoaded = [bool]('DiagSensors' -as [type])

function Get-LhmToolName([string]$File) { return ('LibreHardwareMonitor:{0}' -f $File) }

# ---------- Werkzeuge: prüfen, aufnehmen, holen ----------
# Liegen passende Dateien schon im Tools-Ordner (von Hand kopiert), werden sie mit Prüfsummenvergleich ins Manifest aufgenommen.
# Dateien mit anderer Prüfsumme werden nicht aufgenommen und nicht geladen.
function Register-PinnedSensorTools([string]$ToolsDir = (Get-ToolsDir)) {
    if (-not $ToolsDir -or -not (Test-Path -LiteralPath $ToolsDir)) { return }
    $m = Read-ToolManifest $ToolsDir
    if ($m.Ungueltig) { return }
    $known = @{}; foreach ($e in $m.Werkzeuge) { $known[$e.Name] = $e }
    $items = @(foreach ($f in $script:LhmPins.Keys) { [pscustomobject]@{ Name = (Get-LhmToolName $f); Rel = (Join-Path $script:LhmSubDir $f); SHA256 = $script:LhmPins[$f].SHA256; Lizenz = $script:LhmPins[$f].Lizenz; Quelle = $script:LhmSource } })
    $items += [pscustomobject]@{ Name = 'PawnIO-Setup'; Rel = (Join-Path $script:PawnIoPin.Ordner $script:PawnIoPin.Datei); SHA256 = $script:PawnIoPin.SHA256; Lizenz = $script:PawnIoPin.Lizenz; Quelle = $script:PawnIoPin.Quelle }
    foreach ($it in $items) {
        if ($known.ContainsKey($it.Name)) { continue }
        $p = Join-Path $ToolsDir $it.Rel
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $h = Get-FileSha256 $p
        if ($h -ne $it.SHA256) { $script:ToolIssues.Add(('{0}: {1} hat nicht die bekannte Prüfsumme (SHA-256 {2}…) und wird nicht geladen. Nur LibreHardwareMonitor {3} und PawnIO {4} aus den offiziellen Releases sind freigegeben.' -f $it.Name, $it.Rel, $h.Substring(0, 12), $script:LhmVersion, $script:PawnIoPin.Version)); continue }
        Unblock-SensorFile $p
        [void](Register-Tool -Name $it.Name -Path $p -Lizenz $it.Lizenz -Quelle $it.Quelle -Herkunft 'im Tools-Ordner vorgefunden, Prüfsumme entspricht dem offiziellen Release' -ToolsDir $ToolsDir)
    }
}

# Internet-Markierung (Zone.Identifier) entfernen, nachdem die Prüfsumme bestätigt ist; sonst verweigert .NET das Laden
function Unblock-SensorFile([string]$Path) {
    if (Get-Command Unblock-File -ErrorAction SilentlyContinue) { try { Unblock-File -LiteralPath $Path -ErrorAction Stop } catch { } }
}

# Pfad einer freigegebenen Datei: im Manifest, Hash passt zum Manifest und zum festgehaltenen Wert
function Get-PinnedTool([string]$Name, [string]$PinSha, [string]$ToolsDir = (Get-ToolsDir)) {
    $p = Get-VerifiedTool $Name $ToolsDir
    if (-not $p) { return $null }
    $e = @((Read-ToolManifest $ToolsDir).Werkzeuge | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
    if (-not $e -or $e.SHA256 -ne $PinSha) { $script:ToolIssues.Add(('{0}: Eintrag im Werkzeug-Manifest weicht vom freigegebenen Release ab und wird nicht geladen.' -f $Name)); return $null }
    return $p
}

function Get-SensorToolState([string]$ToolsDir = (Get-ToolsDir)) {
    $st = [pscustomobject]@{ LhmDll = ''; LhmBereit = $false; Fehlend = @(); PawnIoSetup = ''; Version = $script:LhmVersion }
    if (-not $ToolsDir) { $st.Fehlend = @('Datenordner'); return $st }
    Register-PinnedSensorTools $ToolsDir
    $miss = New-Object System.Collections.Generic.List[string]
    foreach ($f in $script:LhmPins.Keys) {
        $p = Get-PinnedTool (Get-LhmToolName $f) $script:LhmPins[$f].SHA256 $ToolsDir
        if (-not $p) { $miss.Add($f) } elseif ($f -eq 'LibreHardwareMonitorLib.dll') { $st.LhmDll = $p }
    }
    $st.Fehlend = $miss.ToArray()
    $st.LhmBereit = ($miss.Count -eq 0 -and [bool]$st.LhmDll)
    $ps = Get-PinnedTool 'PawnIO-Setup' $script:PawnIoPin.SHA256 $ToolsDir
    if ($ps) { $st.PawnIoSetup = $ps }
    return $st
}

# Herunterladen (eigene Funktion, damit Tests sie ersetzen können)
function Save-WebFile([string]$Url, [string]$Path) {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
}

# LibreHardwareMonitorLib und PawnIO-Setup aus den offiziellen Releases holen, prüfen und ins Manifest aufnehmen.
# Alles landet im Datenordner (Stick), auf dem PC bleibt nichts.
function Install-SensorTools([string]$ToolsDir = (Get-ToolsDir)) {
    $log = New-Object System.Collections.Generic.List[string]
    $ok = $true
    if (-not $ToolsDir) { return [pscustomobject]@{ Ok = $false; Meldungen = @('Kein Datenordner verfügbar.') } }
    $work = Join-Path (Join-Path $script:DataDir 'Laufzeit') ('Download-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        New-Item -ItemType Directory -Path $work -Force -ErrorAction Stop | Out-Null
        $dest = Join-Path $ToolsDir $script:LhmSubDir
        New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop | Out-Null
        $zip = Join-Path $work 'LibreHardwareMonitor.zip'
        Save-WebFile $script:LhmZip.Url $zip
        $h = Get-FileSha256 $zip
        if ($h -ne $script:LhmZip.SHA256) { throw ('LibreHardwareMonitor.zip hat eine unerwartete Prüfsumme ({0}…), nichts übernommen.' -f $h.Substring(0, 12)) }
        $ex = Join-Path $work 'lhm'
        Expand-Archive -LiteralPath $zip -DestinationPath $ex -Force -ErrorAction Stop
        foreach ($f in $script:LhmPins.Keys) {
            $src = Join-Path $ex $f
            if (-not (Test-Path -LiteralPath $src)) { throw ('{0} fehlt im Release-Archiv.' -f $f) }
            if ((Get-FileSha256 $src) -ne $script:LhmPins[$f].SHA256) { throw ('{0} im Archiv hat eine unerwartete Prüfsumme.' -f $f) }
            Copy-Item -LiteralPath $src -Destination (Join-Path $dest $f) -Force -ErrorAction Stop
            Unblock-SensorFile (Join-Path $dest $f)
            if (-not (Register-Tool -Name (Get-LhmToolName $f) -Path (Join-Path $dest $f) -Lizenz $script:LhmPins[$f].Lizenz -Quelle $script:LhmSource -Herkunft ('von GitHub geholt auf {0}, Prüfsumme bestätigt' -f $env:COMPUTERNAME) -ToolsDir $ToolsDir)) { throw 'Eintrag ins Werkzeug-Manifest fehlgeschlagen.' }
        }
        $log.Add(('LibreHardwareMonitorLib {0} mit {1} Begleitdateien übernommen ({2}).' -f $script:LhmVersion, ($script:LhmPins.Count - 1), $dest))
        $lic = @('LibreHardwareMonitorLib und Begleitbibliotheken aus ' + $script:LhmSource,
            'Lizenz LibreHardwareMonitor: Mozilla Public License 2.0, Quelltext: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor',
            'Lizenzen der Begleitbibliotheken: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/blob/v0.9.6/THIRD-PARTY-NOTICES.txt',
            '', 'PawnIO ' + $script:PawnIoPin.Version + ' aus ' + $script:PawnIoPin.Quelle + ': ' + $script:PawnIoPin.Lizenz)
        [IO.File]::WriteAllLines((Join-Path $dest 'Lizenzen.txt'), [string[]]$lic, (New-Object Text.UTF8Encoding($false)))
    } catch { $ok = $false; $log.Add(('LibreHardwareMonitor: {0}' -f $_.Exception.Message)) }
    try {
        $pdest = Join-Path (Join-Path $ToolsDir $script:PawnIoPin.Ordner) $script:PawnIoPin.Datei
        New-Item -ItemType Directory -Path (Split-Path $pdest -Parent) -Force -ErrorAction Stop | Out-Null
        $tmp = Join-Path $work 'PawnIO_setup.exe'
        Save-WebFile $script:PawnIoPin.Url $tmp
        $h = Get-FileSha256 $tmp
        if ($h -ne $script:PawnIoPin.SHA256) { throw ('PawnIO_setup.exe hat eine unerwartete Prüfsumme ({0}…), nicht übernommen.' -f $h.Substring(0, 12)) }
        Copy-Item -LiteralPath $tmp -Destination $pdest -Force -ErrorAction Stop
        Unblock-SensorFile $pdest
        if (-not (Register-Tool -Name 'PawnIO-Setup' -Path $pdest -Lizenz $script:PawnIoPin.Lizenz -Quelle $script:PawnIoPin.Quelle -Herkunft ('von GitHub geholt auf {0}, Prüfsumme bestätigt' -f $env:COMPUTERNAME) -ToolsDir $ToolsDir)) { throw 'Eintrag ins Werkzeug-Manifest fehlgeschlagen.' }
        $log.Add(('PawnIO-Setup {0} übernommen. Installiert wird der Treiber nur nach Rückfrage und nur für die Dauer eines Laufs.' -f $script:PawnIoPin.Version))
    } catch { $ok = $false; $log.Add(('PawnIO: {0}' -f $_.Exception.Message)) }
    finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ Ok = $ok; Meldungen = $log.ToArray() }
}

# ---------- PawnIO: nur vorübergehend und nur, wenn er fehlte ----------
function Get-PawnIoMarker {
    if (-not $script:DataDir) { return '' }
    return (Join-Path (Join-Path $script:DataDir 'Laufzeit') ('PawnIO_{0}.txt' -f (Get-SafeName $env:COMPUTERNAME)))
}

# Registrierung lesen wie LibreHardwareMonitor (Uninstall\PawnIO, 64-Bit-Ansicht als Ersatz)
function Get-PawnIoRegistry {
    foreach ($view in 'Default', 'Registry64') {
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::$view)
            $k = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO')
            if ($k) {
                $r = [pscustomobject]@{ Version = [string]$k.GetValue('DisplayVersion'); Ort = [string]$k.GetValue('InstallLocation'); Deinstallation = [string]$k.GetValue('QuietUninstallString') }
                $k.Close(); $base.Close(); return $r
            }
            $base.Close()
        } catch { }
    }
    return $null
}

function Get-PawnIoState {
    $r = Get-PawnIoRegistry
    return [pscustomobject]@{ Installiert = [bool]($r -and $r.Version); Version = $(if ($r) { $r.Version } else { '' }); Ort = $(if ($r) { $r.Ort } else { '' }); Deinstallation = $(if ($r) { $r.Deinstallation } else { '' }) }
}

function Install-PawnIoTemporary {
    $st = Get-PawnIoState
    if ($st.Installiert) { return [pscustomobject]@{ Ok = $true; Text = ('PawnIO {0} war bereits installiert und bleibt unverändert' -f $st.Version) } }
    $setup = (Get-SensorToolState).PawnIoSetup
    if (-not $setup) { return [pscustomobject]@{ Ok = $false; Text = 'PawnIO-Setup fehlt im Tools-Ordner (Seite Sensoren: Sensorwerkzeuge holen)' } }
    $marker = Get-PawnIoMarker
    # Markierung zuerst: Stürzt der Lauf ab, entfernt der nächste Start den Treiber
    # ohne Markierung kein Treiber: Sie ist der einzige Weg zurück nach einem Absturz
    if (-not $marker) { return [pscustomobject]@{ Ok = $false; Text = 'PawnIO nicht installiert: kein Datenordner für die Markierung' } }
    try { New-Item -ItemType Directory -Path (Split-Path $marker -Parent) -Force -ErrorAction Stop | Out-Null; [IO.File]::WriteAllText($marker, ('PawnIO {0} installiert von Leos Minibench {1} am {2:yyyy-MM-dd HH:mm:ss}' -f $script:PawnIoPin.Version, $ScriptVersion, (Get-Date))) }
    catch { return [pscustomobject]@{ Ok = $false; Text = ('PawnIO nicht installiert: Markierung ließ sich nicht schreiben ({0})' -f $_.Exception.Message) } }
    $r = Invoke-External -File $setup -Arguments '-install -silent' -TimeoutSec 180 -Progress 'PawnIO-Treiber wird vorübergehend installiert'
    $st = Get-PawnIoState
    if (-not $st.Installiert) {
        if ($marker) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
        return [pscustomobject]@{ Ok = $false; Text = ('Installation von PawnIO fehlgeschlagen (Rückgabecode {0})' -f $r.ExitCode) }
    }
    $script:PawnIoByUs = $true
    $script:PawnIoInstalledRun = $true
    [void](Add-ChangeRecord -Modul 'Sensoren' -Schritt 'Treiber' -Titel 'PawnIO-Treiber vorübergehend installiert' -Risiko 'Eingriff' -Art 'Treiber' -Ziel ('PawnIO {0}' -f $st.Version) `
        -Vorher 'nicht installiert' -Nachher 'installiert' -Gegenbefehl ('"{0}" -uninstall -silent (läuft am Ende des Laufs automatisch)' -f $setup) -NurHinweis)
    $t = 'PawnIO {0} vorübergehend installiert' -f $st.Version
    if ($r.ExitCode -eq 3010) { $t += ' (Setup meldet: Neustart erforderlich, CPU-Werte erst danach)' }
    return [pscustomobject]@{ Ok = $true; Text = $t }
}

# Entfernt PawnIO, wenn dieses Werkzeug ihn installiert hat (in diesem Lauf oder laut Markierung in einem abgebrochenen)
function Uninstall-PawnIo {
    $marker = Get-PawnIoMarker
    $hasMarker = [bool]($marker -and (Test-Path -LiteralPath $marker))
    if (-not $script:PawnIoByUs -and -not $hasMarker) { return $null }
    $st = Get-PawnIoState
    if (-not $st.Installiert) {
        if ($hasMarker) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
        $script:PawnIoByUs = $false
        return [pscustomobject]@{ Ok = $true; Text = 'PawnIO war nicht mehr installiert' }
    }
    $file = ''
    $un = $(if ($st.Ort) { [IO.Path]::Combine($st.Ort, 'uninstall.exe') } else { '' })
    if ($un -and (Test-Path -LiteralPath $un)) { $file = $un }
    else { $file = (Get-SensorToolState).PawnIoSetup }
    if (-not $file) { return [pscustomobject]@{ Ok = $false; Text = 'PawnIO konnte nicht entfernt werden: weder uninstall.exe noch PawnIO-Setup gefunden' } }
    $r = Invoke-External -File $file -Arguments '-uninstall -silent' -TimeoutSec 180 -Progress 'PawnIO-Treiber wird entfernt'
    $st = Get-PawnIoState
    if ($st.Installiert) { return [pscustomobject]@{ Ok = $false; Text = ('PawnIO ist noch installiert (Rückgabecode {0}). Von Hand entfernen: "{1}" -uninstall' -f $r.ExitCode, $file) } }
    if ($hasMarker) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
    $script:PawnIoByUs = $false
    [void](Add-ChangeRecord -Modul 'Sensoren' -Schritt 'Treiber' -Titel 'PawnIO-Treiber wieder entfernt' -Risiko 'Eingriff' -Art 'Treiber' -Ziel 'PawnIO' -Vorher 'installiert' -Nachher 'nicht installiert' -NurHinweis)
    $t = 'PawnIO wieder entfernt'
    if ($r.ExitCode -eq 3010) { $t += ' (Setup meldet: Neustart erforderlich, bis dahin ist der Treiber noch geladen)' }
    return [pscustomobject]@{ Ok = $true; Text = $t }
}

# Beim Start: Treiberreste eines abgebrochenen Laufs entfernen
function Remove-PawnIoLeftover {
    $marker = Get-PawnIoMarker
    if (-not $marker -or -not (Test-Path -LiteralPath $marker)) { return }
    if ((Get-ToolKeep) -eq 'behalten') { $k = Save-PawnIoKept; if ($k) { $script:SensorNotes.Add(('Ein früherer Lauf wurde mit installiertem PawnIO-Treiber abgebrochen: {0}.' -f $k.Text)) }; return }
    $u = Uninstall-PawnIo
    if ($u) { $script:SensorNotes.Add(('Ein früherer Lauf wurde mit installiertem PawnIO-Treiber abgebrochen: {0}.' -f $u.Text)) }
}

# ---------- Sitzung ----------
function Find-NvidiaSmi {
    foreach ($p in @("$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe", "$env:windir\System32\nvidia-smi.exe")) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    return ''
}

function Test-IsArm64 {
    try {
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { return $true }
        $p = Get-CimCached Win32_Processor | Select-Object -First 1
        if ($p) {
            if ($p.Architecture -in 12, 5) { return $true }
            if ($p.Name -match 'Snapdragon|ARM|Qualcomm') { return $true }
        }
        $os = Get-CimCached Win32_OperatingSystem | Select-Object -First 1
        if ($os -and $os.OSArchitecture -match 'ARM') { return $true }
    } catch { }
    return $false
}

function Open-SensorSession([switch]$Treiber, [switch]$OhneDatentraeger) {
    if ($script:Sens) { return $script:Sens }
    $s = [pscustomobject]@{ Lhm = $false; LhmVersion = ''; LhmFehler = ''; LhmGrund = ''; LhmLief = $false; Treiber = 'nicht verwendet'; TreiberOk = $false; NvSmi = (Find-NvidiaSmi); Quellen = @(); Hinweise = New-Object System.Collections.Generic.List[string]; Geoeffnet = Get-Date; StorageCache = @(); StorageZeit = [datetime]::MinValue; GpuLimits = @{}; StorageTimeout = $false; LhmVerzoegert = $false }
    $script:Sens = $s
    Remove-PawnIoLeftover
    $tools = Get-SensorToolState
    if (Test-IsArm64) {
        $s.LhmGrund = 'ARM64'
        $s.Hinweise.Add('ARM64-Architektur erkannt: Tiefgehende Kern- und Mainboard-Sensoren erfordern x86/x64-Treiber und stehen nur eingeschränkt zur Verfügung')
    }
    elseif (-not $SensorTypesLoaded) { $s.LhmGrund = 'CLM'; $s.Hinweise.Add('Sensorroutinen nicht verfügbar (Constrained Language Mode): nur Ersatzwerte') }
    elseif ($PSVersionTable.PSEdition -eq 'Core') { $s.LhmGrund = 'Core'; $s.Hinweise.Add('LibreHardwareMonitorLib ist für .NET Framework gebaut und läuft nur unter Windows PowerShell 5.1 (LeosMinibench.exe oder .cmd): nur Ersatzwerte') }
    elseif (-not $tools.LhmBereit) {
        if (@($tools.Fehlend).Count -eq $script:LhmPins.Count) { $s.LhmGrund = 'fehlt'; $s.Hinweise.Add('LibreHardwareMonitor fehlt im Tools-Ordner (Seite Sensoren: Sensorwerkzeuge holen): nur Ersatzwerte') }
        else { $s.LhmGrund = 'unvollstaendig'; $s.Hinweise.Add(('LibreHardwareMonitor unvollständig oder nicht freigegeben ({0}): nur Ersatzwerte' -f ($tools.Fehlend -join ', '))) }
    } else {
        $pw = Get-PawnIoState
        if ($pw.Installiert -and (Test-ToolRemoveKept) -and (Test-KeptPawnIo $pw)) {
            # früher auf Wunsch behalten, jetzt soll er gehen: am Laufende wie einen eigenen Treiber entfernen
            $script:PawnIoByUs = $true
            $s.Treiber = ('PawnIO {0} (von Leos Minibench behalten, wird am Ende entfernt)' -f $pw.Version); $s.TreiberOk = $true
        }
        elseif ($pw.Installiert) { $s.Treiber = ('PawnIO {0} ({1})' -f $pw.Version, $(if (Test-KeptTool 'PawnIO') { 'auf Wunsch behalten' } else { 'bereits vorhanden' })); $s.TreiberOk = $true }
        elseif ($Treiber) {
            $r = Install-PawnIoTemporary
            $s.Treiber = $r.Text; $s.TreiberOk = $r.Ok
            if (-not $r.Ok) { $s.Hinweise.Add($r.Text) }
        } else { $s.Treiber = 'ohne PawnIO (CPU-Temperatur, CPU-Takt, CPU-Leistung und Mainboard-Lüfter fehlen)' }
        if ([DiagSensors]::OpenTimed($tools.LhmDll, $true, $true, $true, $true, (-not $OhneDatentraeger), $true, $false, 30000)) {
            $s.Lhm = $true; $s.LhmLief = $true; $s.LhmVersion = [DiagSensors]::LibVersion
        } else { $s.LhmGrund = 'Startfehler'; $s.LhmFehler = [DiagSensors]::LastError; $s.Hinweise.Add(('LibreHardwareMonitor ließ sich nicht starten: {0}' -f [DiagSensors]::LastError)) }
    }
    # Power-Limit der NVIDIA-Karten als Plausibilitätsgrenze für die GPU-Leistung
    if ($s.NvSmi) { try { $s.GpuLimits = Get-NvidiaPowerLimits $s.NvSmi } catch { } }
    $q = @()
    if ($s.Lhm) { $q += ('LibreHardwareMonitor {0}' -f $script:LhmVersion) }
    if ($s.NvSmi) { $q += 'nvidia-smi' }
    $q += 'Windows-Leistungszähler'
    if (-not $s.Lhm -and ('DiagGpuKmt' -as [type])) { $q += 'Windows-Grafiktreiber' }
    $q += 'ACPI'
    $s.Quellen = $q
    return $s
}

# Behalten statt entfernen (Wahl je Gerät): Markierung weg, Eintrag in Geraete.json und Hinweis im Änderungsprotokoll
function Save-PawnIoKept {
    $marker = Get-PawnIoMarker
    $hasMarker = [bool]($marker -and (Test-Path -LiteralPath $marker))
    if (-not $script:PawnIoByUs -and -not $hasMarker) { return $null }
    $st = Get-PawnIoState
    if (-not $st.Installiert) { if ($hasMarker) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }; $script:PawnIoByUs = $false; return $null }
    if ($hasMarker) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
    $script:PawnIoByUs = $false
    [void](Set-KeptTool 'PawnIO' $true)
    $ver = [string]$st.Version; $id = ''; try { $id = (Get-DeviceIdentity).Id } catch { }
    [void](Update-DeviceSetting $id ({ param($e) $e.PawnIoVersion = $ver }.GetNewClosure()))
    $setup = (Get-SensorToolState).PawnIoSetup
    [void](Add-ChangeRecord -Modul 'Sensoren' -Schritt 'Treiber' -Titel 'PawnIO-Treiber bleibt auf Wunsch installiert' -Risiko 'Eingriff' -Art 'Treiber' -Ziel ('PawnIO {0}' -f $st.Version) `
        -Vorher 'nicht installiert' -Nachher 'installiert (behalten)' -Gegenbefehl $(if ($setup) { '"{0}" -uninstall -silent, oder in Leos Minibench "Hilfswerkzeuge: wieder entfernen" wählen' -f $setup } else { 'PawnIO über Apps und Features deinstallieren' }) -NurHinweis)
    return [pscustomobject]@{ Ok = $true; Text = ('PawnIO {0} bleibt auf Wunsch auf diesem PC installiert' -f $st.Version) }
}

# Ist der installierte PawnIO noch der, den Leos Minibench auf Wunsch behalten hat? Gleiche Version wie beim Behalten.
# Fehlt der Treiber inzwischen, wird der Eintrag gelöscht; so entfernt ein späterer Lauf nie einen PawnIO, den ein
# anderes Programm (z. B. FanControl) mitgebracht hat.
function Test-KeptPawnIo($State = $null) {
    if (-not (Test-KeptTool 'PawnIO')) { return $false }
    if (-not $State) { $State = Get-PawnIoState }
    if (-not $State.Installiert) { [void](Set-KeptTool 'PawnIO' $false); return $false }
    $id = ''; try { $id = (Get-DeviceIdentity).Id } catch { }
    $v = [string](Get-DeviceSetting $id).PawnIoVersion
    return [bool]($v -and $v -eq [string]$State.Version)
}

function Close-SensorSession {
    $keep = ((Get-ToolKeep) -eq 'behalten')
    if ($script:Sens) {
        if ($SensorTypesLoaded) { try { [DiagSensors]::Close() } catch { } }
        if ($SensorTypesLoaded -and ('DiagPdh' -as [type])) { try { [DiagPdh]::Close() } catch { } }
    }
    # einen früher behaltenen Treiber entfernen, wenn "entfernen" ausdrücklich gewählt ist (auch ohne Sensorsitzung)
    if (-not $keep -and -not $script:PawnIoByUs -and (Test-ToolRemoveKept) -and (Test-KeptPawnIo)) { $script:PawnIoByUs = $true; $script:PawnIoKeptRemoval = $true }
    $u = $(if ($keep) { Save-PawnIoKept } else { Uninstall-PawnIo })
    if ($u -and $u.Ok -and -not $keep -and (Test-KeptTool 'PawnIO')) { [void](Set-KeptTool 'PawnIO' $false) }
    if ($u -and $script:PawnIoKeptRemoval) { $script:PawnIoKeptRemoval = $u }
    if (-not $script:Sens) { if ($u) { $script:SensorNotes.Add($u.Text) }; return }
    if ($u) {
        $script:Sens.Treiber = $script:Sens.Treiber + '; ' + $u.Text
        if (-not $u.Ok) { $script:ToolIssues.Add($u.Text) }
    }
    $script:Sens.Lhm = $false
}

# Warum fehlen CPU-Temperatur und CPU-Leistung? (ab v2.8) Bis 2.7 hieß es immer "ohne PawnIO-Treiber", auch wenn
# LibreHardwareMonitor gar nicht im Tools-Ordner lag (Praxistest 03.10.: neuer Datenordner ohne Tools auf TORRENT).
function Get-SensorGapText {
    if (Test-IsArm64) { return 'ARM64-Architektur erkannt: Tiefgehende Kern- und Mainboard-Sensoren erfordern x86/x64-Treiber und stehen nur eingeschränkt zur Verfügung' }
    $s = $script:Sens
    if (-not $s) { return 'Sensoren nicht geöffnet' }
    switch ([string]$s.LhmGrund) {
        'ARM64'          { return 'ARM64-Architektur erkannt: Tiefgehende Kern- und Mainboard-Sensoren erfordern x86/x64-Treiber und stehen nur eingeschränkt zur Verfügung' }
        'fehlt'          { return ('LibreHardwareMonitor fehlt im Tools-Ordner des Datenordners ({0}); die Seite Sensoren holt es mit "Sensorwerkzeuge holen", vor Benchmark und Lasttest fragt Leos Minibench danach' -f (Get-ToolsDir)) }
        'unvollstaendig' { return 'LibreHardwareMonitor im Tools-Ordner ist unvollständig oder hat abweichende Prüfsummen; "Sensorwerkzeuge erneut holen"' }
        'Core'           { return 'LibreHardwareMonitor läuft nur unter Windows PowerShell 5.1 (LeosMinibench.exe)' }
        'CLM'            { return 'PowerShell läuft im Constrained Language Mode, Sensorroutinen sind gesperrt' }
        'Startfehler'    { return ('LibreHardwareMonitor ließ sich nicht starten ({0})' -f $s.LhmFehler) }
    }
    if (($s.Lhm -or $s.LhmLief) -and -not $s.TreiberOk) { return ('LibreHardwareMonitor läuft, aber ohne PawnIO-Treiber ({0}); ohne ihn gibt es keine CPU-Werte' -f $s.Treiber) }
    if ($s.Lhm -or $s.LhmLief) { return 'LibreHardwareMonitor und PawnIO laufen, liefern für diese CPU aber keine Temperatur' }
    return 'LibreHardwareMonitor war nicht geöffnet'
}

# Einmal je Lauf als Befund, wenn Benchmark oder Lasttest ohne LibreHardwareMonitor messen (ab v2.8)
$script:SensorGapReported = $false
function Add-SensorGapFinding([string]$Wo) {
    if ($script:SensorGapReported) { return }
    if (Test-IsArm64) {
        $script:SensorGapReported = $true
        Add-Finding INFO 'Sensoren' 'ARM64-Architektur erkannt: Tiefgehende Kern- und Mainboard-Sensoren erfordern x86/x64-Treiber und stehen nur eingeschränkt zur Verfügung.'
        return
    }
    $s = $script:Sens
    if (-not $s -or $s.Lhm -or -not $s.LhmGrund) { return }
    $script:SensorGapReported = $true
    Add-Finding INFO 'Sensoren' ('{0} lief ohne LibreHardwareMonitor: keine CPU-Temperatur; CPU-Leistung und GPU-Werte nur, soweit Windows, der Grafiktreiber oder nvidia-smi sie melden (GPU-Leistung bei AMD und Intel fehlt dann). Grund: {1}.' -f $Wo, (Get-SensorGapText))
}

function Get-SensorSourceText {
    $s = $script:Sens
    if (-not $s) { return 'Sensoren nicht geöffnet' }
    $t = 'Quellen: ' + ($s.Quellen -join ', ')
    if ($s.Lhm) { $t += '; Treiber: ' + $s.Treiber }
    if ($s.Hinweise.Count) { $t += '; ' + (($s.Hinweise | Select-Object -Unique) -join '; ') }
    $d = Get-SensorDelayText
    if ($d) { $t += '; ' + $d }
    return $t
}

# Verzögerte Abfragen von LibreHardwareMonitor (ab v2.66): Anzahl und längste Dauer, leer ohne Verzögerung
function Get-SensorDelayText {
    if (-not $script:Sens -or -not $script:Sens.LhmVersion -or -not ('DiagSensors' -as [type])) { return '' }
    $n = 0; $mx = 0.0
    try { $n = [int][DiagSensors]::SlowReads; $mx = [double][DiagSensors]::MaxReadMs } catch { return '' }
    if ($n -le 0) { return '' }
    return ('LibreHardwareMonitor antwortete {0}x verzögert (längste Abfrage {1:N1} s), bis dahin galten die letzten Werte' -f $n, ($mx / 1000.0))
}

# ---------- Messwerte ----------
function New-SensorReading([string]$Key, [string]$Quelle, [string]$Gruppe, [string]$Geraet, [string]$Art, [string]$Name, [string]$Einheit, $Wert, [string]$Typ = '', $TjMax = $null) {
    $w = [double]::NaN
    if ($null -ne $Wert -and "$Wert" -ne '') { try { $w = [double]$Wert } catch { } }
    $tj = [double]::NaN
    if ($null -ne $TjMax -and "$TjMax" -ne '') { try { $tj = [double]$TjMax } catch { } }
    [pscustomobject]@{ Key = $Key; Quelle = $Quelle; Gruppe = $Gruppe; Geraet = $Geraet; Art = $Art; Name = $Name; Einheit = $Einheit; Wert = $w; Typ = $Typ; TjMax = $tj; Status = ''; Hinweis = ''; Roh = $w }
}

# Art der Grafikeinheit aus dem Namen: dGPU (eigene Karte), iGPU (im Prozessor), virtuell oder unbekannt.
# AMD-Prozessorgrafik heißt "Radeon(TM) Graphics", "Radeon 780M" oder "Radeon RX Vega 11 Graphics", Intel-Karten "Arc A770".
function Get-GpuKind([string]$Name) {
    $n = ([string]$Name).Trim()
    if (-not $n) { return 'unbekannt' }
    if ($n -match 'Virtual|Remote|Indirect|Parsec|spacedesk|Basic Display|Basic Render|Standard-VGA|Hyper-V|VMware|VirtualBox|Citrix|DisplayLink') { return 'virtuell' }
    if ($n -match 'NVIDIA|GeForce|Quadro|Tesla|\bRTX\b|\bGTX\b') { return 'dGPU' }
    if ($n -match 'Intel') { if ($n -match 'Arc(\(TM\))?\s+(Pro\s+)?[AB]\d{2,3}') { return 'dGPU' }; return 'iGPU' }
    if ($n -match 'AMD|ATI|Radeon|FirePro') {
        if ($n -match 'Graphics\s*$' -or $n -match '\b\d{3}M\b') { return 'iGPU' }
        return 'dGPU'
    }
    return 'unbekannt'
}
function Test-LaptopGpu([string]$Name) { return ([string]$Name -match 'Laptop|Mobile|Max-Q|\b\d{4}M\b|\bMX\s?\d{3}') }

# Grenzwerte laut Hersteller sind keine Messwerte: Warn- und Abschalttemperatur von NVMe-SSDs (Warning/Critical
# Temperature), Grenzen der RAM-Temperatursensoren (Thermal Sensor ... Limit), Schwellen wie Available Spare Threshold.
# Sie bekommen die Art Grenzwert und zählen nie für Leitwerte, Kurven oder Befunde. "Distance to TjMax" ist ein Abstand.
$script:SensorLimitPattern = '(?i)\b(Warning|Critical)\b.*\bTemp|\bTemp\w*\s+(Limit|Threshold)|\bLimit\b|\bThreshold\b|Sensor Resolution'
function Get-SensorArt([string]$Art, [string]$Name) {
    if ($Name -match 'Distance to TjMax') { return 'Abstand' }
    if ($Art -in 'Temperatur', 'Füllstand', 'Leistung', 'Takt', 'Spannung', 'Strom' -and $Name -match $script:SensorLimitPattern) { return 'Grenzwert' }
    return $Art
}

# Plausibilitätsgrenze für Leistungswerte: NVIDIA-Karten nach dem höchsten einstellbaren Power-Limit laut nvidia-smi
# (power.max_limit, 5 % Messtoleranz), sonst feste Obergrenzen (Notebook-GPU 200 W, Desktop-GPU 700 W,
# Prozessorgrafik 80 W), CPU 500 W. Beispiel aus dem Praxistest: 590 W an einer Iris-Xe-Prozessorgrafik.
function Get-PowerLimit($Reading, $GpuLimits = $null) {
    if ($Reading.Gruppe -eq 'GPU') {
        $pl = $null
        $dev = [string]$Reading.Geraet
        if ($GpuLimits -and $dev) { foreach ($k in @($GpuLimits.Keys)) { if ($k -and ($dev.IndexOf([string]$k, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or ([string]$k).IndexOf($dev, [StringComparison]::OrdinalIgnoreCase) -ge 0)) { $pl = [double]$GpuLimits[$k]; break } } }
        if ($pl -and $pl -gt 5) { return [pscustomobject]@{ W = [math]::Round($pl * 1.05, 1); Quelle = ('Power-Limit {0:N0} W laut nvidia-smi' -f $pl) } }
        $kind = Get-GpuKind $Reading.Geraet
        if ($kind -eq 'iGPU') { return [pscustomobject]@{ W = 80; Quelle = 'Obergrenze für Prozessorgrafik' } }
        if (Test-LaptopGpu $Reading.Geraet) { return [pscustomobject]@{ W = 200; Quelle = 'Obergrenze für Notebook-Grafik' } }
        return [pscustomobject]@{ W = 700; Quelle = 'Obergrenze für Grafikkarten' }
    }
    if ($Reading.Gruppe -eq 'CPU') { return [pscustomobject]@{ W = 500; Quelle = 'Obergrenze für Prozessoren' } }
    if ($Reading.Gruppe -eq 'Akku') { return [pscustomobject]@{ W = 300; Quelle = 'Obergrenze für Akkus' } }
    return [pscustomobject]@{ W = 2000; Quelle = 'allgemeine Obergrenze' }
}

# Grund, warum ein Wert nicht stimmen kann (leer = plausibel). Unplausible Werte werden nicht angezeigt und nicht ausgewertet.
function Get-SensorImplausibility($Reading, $GpuLimits = $null) {
    $v = [double]$Reading.Wert
    if ([double]::IsNaN($v)) { return '' }
    switch ($Reading.Art) {
        'Temperatur' {
            if ($v -le -30 -or $v -ge 150) { return ('{0:N0} °C liegt außerhalb des möglichen Bereichs' -f $v) }
            if ($Reading.Gruppe -in 'Datenträger', 'RAM', 'Akku' -and $v -ge 120) { return ('{0:N0} °C ist für {1} nicht möglich' -f $v, $Reading.Gruppe) }
        }
        'Leistung' {
            $lim = Get-PowerLimit $Reading $GpuLimits
            if ($v -lt -5) { return ('{0:N1} W ist negativ' -f $v) }
            if ($v -gt $lim.W) { return ('{0:N0} W über der Plausibilitätsgrenze von {1:N0} W ({2})' -f $v, $lim.W, $lim.Quelle) }
        }
        'Takt' {
            $max = $(if ($Reading.Name -match 'Memory|Speicher') { 40000 } elseif ($Reading.Gruppe -eq 'GPU') { 5000 } else { 9000 })
            if ($v -lt 0 -or $v -gt $max) { return ('{0:N0} MHz über der Obergrenze von {1:N0} MHz' -f $v, $max) }
        }
        'Lüfter' { if ($v -lt 0 -or $v -gt 12000) { return ('{0:N0} U/min ist kein möglicher Lüfterwert' -f $v) } }
        'Spannung' {
            if ($v -lt -1 -or $v -gt 60) { return ('{0:N2} V liegt außerhalb des möglichen Bereichs' -f $v) }
            if ($Reading.Gruppe -in 'CPU', 'GPU' -and $v -gt 3) { return ('{0:N2} V ist als Kern- oder Chipspannung nicht möglich' -f $v) }
        }
        { $_ -in 'Auslastung', 'Lüftersteuerung' } { if ($v -lt 0 -or $v -gt 105) { return ('{0:N0} % liegt außerhalb von 0 bis 100 %' -f $v) } }
        'Strom' { if ($v -lt -500 -or $v -gt 500) { return ('{0:N0} A liegt außerhalb des möglichen Bereichs' -f $v) } }
    }
    return ''
}

# Einordnen und prüfen: Grenzwerte bekommen ihre eigene Art, unplausible Werte Status "unplausibel" (Rohwert in Roh, Wert NaN)
function Set-SensorClassification($Readings, $GpuLimits = $null) {
    if ($null -eq $Readings) { return }
    # foreach direkt über die Liste: @($Readings) auf eine List[object] löst in PowerShell 7.4 "Argument types do not match" aus
    foreach ($r in $Readings) {
        if (-not $r) { continue }
        $r.Art = Get-SensorArt $r.Art $r.Name
        if ($r.Art -in 'Grenzwert', 'Abstand') { continue }
        $why = Get-SensorImplausibility $r $GpuLimits
        if ($why) { $r.Status = 'unplausibel'; $r.Hinweis = $why; $r.Roh = $r.Wert; $r.Wert = [double]::NaN }
    }
}

# Reihenfolge für Anzeige und Bericht: Gruppe, Gerät, Art, Sensorname (Zahlen im Namen numerisch)
$script:SensorGroupOrder = @{ 'CPU' = 1; 'GPU' = 2; 'RAM' = 3; 'Mainboard' = 4; 'Datenträger' = 5; 'Akku' = 6; 'Netzteil' = 7; 'Kühlung' = 8 }
$script:SensorArtOrder = @{ 'Temperatur' = 1; 'Takt' = 2; 'Leistung' = 3; 'Spannung' = 4; 'Strom' = 5; 'Lüfter' = 6; 'Lüftersteuerung' = 7; 'Auslastung' = 8; 'Füllstand' = 9; 'Abstand' = 10; 'Grenzwert' = 11 }
function Sort-SensorReadings($Readings) {
    $nat = { param($s) [regex]::Replace([string]$s, '\d+', { param($m) $m.Value.PadLeft(6, '0') }) }
    return @($Readings | Sort-Object @{ e = { $g = $script:SensorGroupOrder[[string]$_.Gruppe]; if ($g) { $g } else { 50 } } }, @{ e = { $(if ((Get-GpuKind $_.Geraet) -eq 'iGPU') { 1 } else { 0 }) } }, Geraet,
        @{ e = { $a = $script:SensorArtOrder[[string]$_.Art]; if ($a) { $a } else { 50 } } }, @{ e = { & $nat $_.Name } })
}

# nvidia-smi --format=csv,noheader,nounits: index, name, temperature.gpu, clocks.gr, clocks.mem, power.draw, fan.speed, utilization.gpu
function ConvertFrom-NvidiaSmi([string]$Text) {
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($l in @($Text -split "`r?`n" | Where-Object { $_.Trim() })) {
        $c = @($l -split ',' | ForEach-Object { $_.Trim() })
        if ($c.Count -lt 8) { continue }
        $num = { param($v) if ($v -match '^-?\d+(\.\d+)?$') { [double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture) } else { $null } }
        $dev = $c[1]; $i = $c[0]
        $res.Add((New-SensorReading ('nvsmi/{0}/temp' -f $i) 'nvidia-smi' 'GPU' $dev 'Temperatur' 'GPU Core' '°C' (& $num $c[2]) 'GpuNvidia'))
        $res.Add((New-SensorReading ('nvsmi/{0}/clock' -f $i) 'nvidia-smi' 'GPU' $dev 'Takt' 'GPU Core' 'MHz' (& $num $c[3]) 'GpuNvidia'))
        $res.Add((New-SensorReading ('nvsmi/{0}/memclock' -f $i) 'nvidia-smi' 'GPU' $dev 'Takt' 'GPU Memory' 'MHz' (& $num $c[4]) 'GpuNvidia'))
        $res.Add((New-SensorReading ('nvsmi/{0}/power' -f $i) 'nvidia-smi' 'GPU' $dev 'Leistung' 'GPU Package' 'W' (& $num $c[5]) 'GpuNvidia'))
        $res.Add((New-SensorReading ('nvsmi/{0}/fan' -f $i) 'nvidia-smi' 'GPU' $dev 'Lüftersteuerung' 'GPU Fan' '%' (& $num $c[6]) 'GpuNvidia'))
        $res.Add((New-SensorReading ('nvsmi/{0}/load' -f $i) 'nvidia-smi' 'GPU' $dev 'Auslastung' 'GPU Core' '%' (& $num $c[7]) 'GpuNvidia'))
    }
    return $res.ToArray()
}

# Ersatzwerte vom Grafiktreiber über Windows (ab v2.8, Typ DiagGpuKmt): nur Werte, die keine andere Quelle für dieses Gerät
# liefert. Liefert LibreHardwareMonitor oder nvidia-smi schon Werte für eine Karte, bleibt sie unberührt.
#   $Adapters  Objekte mit Name, TempC, CoreMhz, MemMhz, FanRpm, Load (NaN = fehlt)
#   $Existing  bisherige Messwerte (Gruppe GPU)
function ConvertFrom-KmtAdapters($Adapters, $Existing) {
    $res = New-Object System.Collections.Generic.List[object]
    $taken = @{}
    foreach ($e in @($Existing)) { if ($e -and $e.Gruppe -eq 'GPU' -and -not [double]::IsNaN([double]$e.Wert)) { $taken[('{0}|{1}' -f $e.Geraet, $e.Art)] = $true } }
    $seen = @{}
    foreach ($a in @($Adapters)) {
        if (-not $a -or -not $a.Name) { continue }
        $dev = [string]$a.Name
        if ($seen[$dev]) { continue }; $seen[$dev] = $true
        $kind = Get-GpuKind $dev
        if ($kind -eq 'virtuell') { continue }
        $key = 'kmt/' + ($dev -replace '[^A-Za-z0-9]+', '_')
        $add = {
            param($Suffix, $Art, $Name, $Unit, $Value, $Min, $Max)
            if ($null -eq $Value) { return }
            $v = [double]$Value
            if ([double]::IsNaN($v) -or $v -lt $Min -or $v -gt $Max) { return }
            if ($taken[('{0}|{1}' -f $dev, $Art)]) { return }
            $res.Add((New-SensorReading ('{0}/{1}' -f $key, $Suffix) 'Windows' 'GPU' $dev $Art $Name $Unit $v 'GpuWindows'))
        }
        & $add 'temp' 'Temperatur' 'GPU Core' '°C' $a.TempC 1 150
        & $add 'load' 'Auslastung' 'D3D 3D' '%' $a.Load 0 100
        & $add 'fan' 'Lüfter' 'GPU Fan' 'U/min' $a.FanRpm 1 20000
        # Takt: Kern und Speicher getrennt prüfen (Art Takt ist für beide gleich, daher Name statt Art)
        if (-not @($Existing | Where-Object { $_ -and $_.Geraet -eq $dev -and $_.Art -eq 'Takt' -and $_.Name -eq 'GPU Core' -and -not [double]::IsNaN([double]$_.Wert) }).Count) {
            $v = [double]$a.CoreMhz; if (-not [double]::IsNaN($v) -and $v -ge 100 -and $v -le 4000) { $res.Add((New-SensorReading ('{0}/clock' -f $key) 'Windows' 'GPU' $dev 'Takt' 'GPU Core' 'MHz' $v 'GpuWindows')) }
        }
        if (-not @($Existing | Where-Object { $_ -and $_.Geraet -eq $dev -and $_.Art -eq 'Takt' -and $_.Name -eq 'GPU Memory' -and -not [double]::IsNaN([double]$_.Wert) }).Count) {
            $v = [double]$a.MemMhz; if (-not [double]::IsNaN($v) -and $v -ge 100 -and $v -le 30000) { $res.Add((New-SensorReading ('{0}/memclock' -f $key) 'Windows' 'GPU' $dev 'Takt' 'GPU Memory' 'MHz' $v 'GpuWindows')) }
        }
    }
    return $res.ToArray()
}

function Get-WindowsGpuAdapters {
    if (-not ('DiagGpuKmt' -as [type])) { return @() }
    try { return @([DiagGpuKmt]::Read()) } catch { return @() }
}

# CPU-Paketleistung aus dem Energiezähler von Windows (RAPL), nur ohne Wert von LibreHardwareMonitor
function Get-WindowsCpuPowerReading {
    if (-not ('DiagGpuKmt' -as [type])) { return $null }
    try { $w = [DiagGpuKmt]::CpuPackageWatts() } catch { return $null }
    if ([double]::IsNaN($w) -or $w -le 0 -or $w -ge 1000) { return $null }
    return (New-SensorReading 'win/cpu/power' 'Windows' 'CPU' 'CPU' 'Leistung' 'CPU Package' 'W' $w 'CpuWindows')
}

function Invoke-NvidiaSmi([string]$Path) {
    $r = Invoke-External -File $Path -Arguments '--query-gpu=index,name,temperature.gpu,clocks.gr,clocks.mem,power.draw,fan.speed,utilization.gpu --format=csv,noheader,nounits' -TimeoutSec 5 -Encoding ([Text.Encoding]::UTF8)
    if ($r.ExitCode -ne 0) { return '' }
    return $r.Output
}

# Power-Limit je NVIDIA-Karte (Name -> Watt) für die Plausibilitätsgrenze; einmal je Sitzung
function ConvertFrom-NvidiaSmiLimits([string]$Text) {
    $res = @{}
    foreach ($l in @($Text -split "`r?`n" | Where-Object { $_.Trim() })) {
        $c = @($l -split ',' | ForEach-Object { $_.Trim() })
        if ($c.Count -lt 2) { continue }
        $w = $null
        foreach ($v in @($c[1..($c.Count - 1)])) { if ($v -match '^\d+(\.\d+)?$') { $x = [double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture); if ($null -eq $w -or $x -gt $w) { $w = $x } } }
        if ($c[0] -and $w) { $res[$c[0]] = $w }
    }
    return $res
}
function Get-NvidiaPowerLimits([string]$Path) {
    if (-not $Path) { return @{} }
    $r = Invoke-External -File $Path -Arguments '--query-gpu=name,power.limit,enforced.power.limit,power.max_limit --format=csv,noheader,nounits' -TimeoutSec 5 -Encoding ([Text.Encoding]::UTF8)
    if ($r.ExitCode -ne 0) { return @{} }
    return (ConvertFrom-NvidiaSmiLimits $r.Output)
}

function Get-AcpiReadings {
    $res = @()
    foreach ($z in @(Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue)) {
        $v = $null
        if ($z.HighPrecisionTemperature) { $v = $z.HighPrecisionTemperature / 10 - 273.15 } elseif ($z.Temperature) { $v = $z.Temperature - 273.15 }
        if ($null -eq $v -or $v -le 0 -or $v -ge 130) { continue }
        $n = ([string]$z.Name) -replace '^\\_TZ\.', ''
        $res += New-SensorReading ('acpi/{0}' -f $n) 'ACPI' 'Mainboard' 'ACPI-Thermalzone' 'Temperatur' $n '°C' ([math]::Round($v, 1)) 'Acpi'
    }
    return $res
}

# Temperaturen der Zuverlässigkeitszähler (Windows Storage, WMI). Ab v2.65 in einem eigenen Runspace mit Zeitlimit:
# Der Speicheranbieter von WMI kann bei auffälligen Datenträgern (USB mit Controllerfehlern) minutenlang hängen und
# hielt dann den ganzen Lauf an. Nach einer Zeitüberschreitung fragt die Sitzung nicht mehr nach.
function Get-StorageTempRaw {
    $res = @()
    try {
        foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop)) {
            $c = $null; try { $c = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
            if ($c -and $c.Temperature -gt 0) { $res += [pscustomobject]@{ Id = [string]$d.DeviceId; Name = ([string]$d.FriendlyName).Trim(); Temp = [double]$c.Temperature } }
        }
    } catch { }
    return $res
}

function Get-StorageTempReadings([int]$TimeoutSec = 15) {
    $s = $script:Sens
    if ($s -and $s.StorageTimeout) { return @() }
    $raw = @()
    $ps = $null
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript(${function:Get-StorageTempRaw}.ToString())
        $h = $ps.BeginInvoke()
        if ($h.AsyncWaitHandle.WaitOne([math]::Max(1, $TimeoutSec) * 1000)) { $raw = @($ps.EndInvoke($h)) }
        else {
            try { [void]$ps.BeginStop($null, $null) } catch { }
            $ps = $null   # nicht freigeben: Dispose würde auf den hängenden Aufruf warten
            if ($s) { $s.StorageTimeout = $true; $s.Hinweise.Add(('Temperaturen der Zuverlässigkeitszähler antworten nicht innerhalb von {0} Sekunden und werden in diesem Lauf nicht mehr abgefragt' -f $TimeoutSec)) }
            try { Write-Checkpoint 'INFO' 'Sensoren: Zuverlässigkeitszähler (Get-StorageReliabilityCounter) antworten nicht, abgeschaltet' } catch { }
        }
    } catch { $raw = @() }
    finally { if ($ps) { try { $ps.Dispose() } catch { } } }
    $res = @()
    foreach ($d in $raw) { if ($d -and $d.Temp -gt 0) { $res += New-SensorReading ('win/disk/{0}/temp' -f $d.Id) 'Windows' 'Datenträger' ([string]$d.Name) 'Temperatur' 'Temperatur' '°C' $d.Temp 'Storage' } }
    return $res
}

function Get-BatteryReadings {
    $res = @()
    try {
        foreach ($b in @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop)) {
            $n = 'Akku'
            if ($b.Voltage) { $res += New-SensorReading 'wmi/akku/spannung' 'WMI' 'Akku' $n 'Spannung' 'Spannung' 'V' ([math]::Round($b.Voltage / 1000.0, 3)) 'Battery' }
            if ($b.DischargeRate) { $res += New-SensorReading 'wmi/akku/entladen' 'WMI' 'Akku' $n 'Leistung' 'Entladeleistung' 'W' ([math]::Round($b.DischargeRate / 1000.0, 2)) 'Battery' }
            if ($b.ChargeRate) { $res += New-SensorReading 'wmi/akku/laden' 'WMI' 'Akku' $n 'Leistung' 'Ladeleistung' 'W' ([math]::Round($b.ChargeRate / 1000.0, 2)) 'Battery' }
        }
    } catch { }
    return $res
}

function ConvertFrom-CpuSampleReadings($Sample) {
    if (-not $Sample) { return @() }
    $res = @()
    if ($Sample.MHz -gt 0) { $res += New-SensorReading 'win/cpu/takt' 'Windows' 'CPU' 'Windows-Leistungszähler' 'Takt' 'CPU gesamt' 'MHz' $Sample.MHz 'Cpu' }
    $res += New-SensorReading 'win/cpu/last' 'Windows' 'CPU' 'Windows-Leistungszähler' 'Auslastung' 'CPU gesamt' '%' $Sample.Last 'Cpu'
    if ($Sample.MaxFreq -gt 0) { $res += New-SensorReading 'win/cpu/grenze' 'Windows' 'CPU' 'Windows-Leistungszähler' 'Auslastung' 'Frequenzgrenze (% vom Maximum)' '%' $Sample.MaxFreq 'Cpu' }
    return $res
}

# Alle Werte: LibreHardwareMonitor zuerst, Ersatzquellen für das, was dort fehlt. Grenzwerte und unplausible Werte
# sind gekennzeichnet (Art Grenzwert bzw. Status unplausibel), sortiert nach Gruppe, Gerät und Art.
function Get-SensorReadings([switch]$MitDatentraeger, $CpuSample = $null) {
    $s = $script:Sens
    $all = New-Object System.Collections.Generic.List[object]
    if ($s -and $s.Lhm) {
        # Datenträger: für die Momentaufnahme bis 15 s auf die erste Aktualisierung warten, sonst nur die letzten Werte
        try { [DiagSensors]::StorageWaitMs = $(if ($MitDatentraeger) { 15000 } else { 0 }) } catch { }
        try { foreach ($r in [DiagSensors]::ReadTimed(5000)) { $all.Add((New-SensorReading $r.Key 'LHM' $r.Gruppe $r.Geraet $r.Art $r.Name $r.Einheit $(if ([double]::IsNaN($r.Wert)) { $null } else { $r.Wert }) '' $(if ([double]::IsNaN($r.TjMax)) { $null } else { $r.TjMax }))) } } catch { }
        try { [DiagSensors]::StorageWaitMs = 0 } catch { }
        if ([DiagSensors]::Hung) { $s.Lhm = $false; $s.LhmFehler = [DiagSensors]::LastError; $s.Hinweise.Add(('{0}; weiter mit Windows-Werten' -f [DiagSensors]::LastError)); Write-Checkpoint 'INFO' ('Sensoren: {0}' -f [DiagSensors]::LastError) }
        elseif ([DiagSensors]::LastStale -and -not $s.LhmVerzoegert) {
            # einmal vermerken: eine Abfrage dauert länger, die letzten Werte gelten weiter (ab v2.66 kein Ausfall mehr)
            $s.LhmVerzoegert = $true
            Write-Checkpoint 'INFO' ('Sensoren: {0}, letzte Werte gelten weiter' -f [DiagSensors]::LastError)
        }
    }
    $has = { param($g, $a) @($all | Where-Object { $_.Gruppe -eq $g -and $_.Art -eq $a -and -not [double]::IsNaN($_.Wert) }).Count -gt 0 }
    if (-not $CpuSample) { $CpuSample = Get-CpuSample }
    foreach ($r in (ConvertFrom-CpuSampleReadings $CpuSample)) { $all.Add($r) }
    foreach ($r in (Get-AcpiReadings)) { $all.Add($r) }
    if ($s -and $s.NvSmi -and -not (& $has 'GPU' 'Temperatur')) { foreach ($r in (ConvertFrom-NvidiaSmi (Invoke-NvidiaSmi $s.NvSmi))) { $all.Add($r) } }
    # ohne LibreHardwareMonitor: Grafiktreiber-Werte über Windows und CPU-Leistung aus dem Energiezähler (ab v2.8)
    if (-not ($s -and $s.Lhm)) {
        $gpuNow = @($all | Where-Object { $_.Gruppe -eq 'GPU' })
        foreach ($r in (ConvertFrom-KmtAdapters (Get-WindowsGpuAdapters) $gpuNow)) { $all.Add($r) }
        if (-not (& $has 'CPU' 'Leistung')) { $cw = Get-WindowsCpuPowerReading; if ($cw) { $all.Add($cw) } }
    }
    if (-not (& $has 'Akku' 'Spannung')) { foreach ($r in (Get-BatteryReadings)) { $all.Add($r) } }
    $diskReal = @($all | Where-Object { $_.Gruppe -eq 'Datenträger' -and $_.Art -eq 'Temperatur' -and $_.Name -notmatch $script:SensorLimitPattern -and -not [double]::IsNaN($_.Wert) }).Count
    if (-not $diskReal) {
        # Zuverlässigkeitszähler sind langsam: höchstens alle 30 Sekunden neu lesen
        if ($s -and ($MitDatentraeger -or ((Get-Date) - $s.StorageZeit).TotalSeconds -ge 30)) { $s.StorageCache = @(Get-StorageTempReadings); $s.StorageZeit = Get-Date }
        if ($s) { foreach ($r in $s.StorageCache) { $all.Add(($r | Select-Object *)) } } elseif ($MitDatentraeger) { foreach ($r in (Get-StorageTempReadings)) { $all.Add($r) } }
    }
    Set-SensorClassification $all $(if ($s) { $s.GpuLimits } else { $null })
    return , [object[]](Sort-SensorReadings $all)
}

# Messwerte als flache Liste: Ein Array im Array (z. B. @() um eine Funktion, die ihr Ergebnis mit Komma zurückgibt)
# wird aufgelöst. Bis v2.6 kamen die Werte im Lasttest so verpackt an, alle Leitwerte fehlten.
function ConvertTo-FlatReadings($Readings) {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($r in @($Readings)) {
        if ($null -eq $r) { continue }
        if ($r -is [System.Collections.IEnumerable] -and $r -isnot [string] -and $r -isnot [System.Collections.IDictionary]) { foreach ($x in $r) { if ($null -ne $x) { $out.Add($x) } } }
        else { $out.Add($r) }
    }
    # ohne Komma: der Aufrufer bekommt die Elemente, @() um den Aufruf ergibt kein Array im Array
    return $out.ToArray()
}

# Leitwerte für Kurven, Drosselnachweis und Abbruchschwelle.
#   CpuMHz     Takt laut Windows (Nenntakt x % Prozessorleistung, wie im Task-Manager), sonst Mittel der Kerntakte
#   CpuMHzMax  höchster Kerntakt laut LibreHardwareMonitor
#   Gpu*       dedizierte Grafikkarte (Leitwert), IGpu* zusätzlich die Prozessorgrafik
# Unplausible Werte (Status) und Grenzwerte (Art) zählen nie.
function Get-SensorLead($Readings) {
    $Readings = ConvertTo-FlatReadings $Readings
    $R = @($Readings | Where-Object { $_ -and -not [double]::IsNaN([double]$_.Wert) -and $_.Art -notin 'Grenzwert', 'Abstand' -and $_.Status -ne 'unplausibel' -and $_.Name -notmatch $script:SensorLimitPattern })
    $pick = {
        param($Group, $Art, [string[]]$Names, [string]$Exclude = '', [string]$Quelle = '')
        $c = @($R | Where-Object { $_.Gruppe -eq $Group -and $_.Art -eq $Art -and (-not $Quelle -or $_.Quelle -eq $Quelle) -and (-not $Exclude -or $_.Name -notmatch $Exclude) })
        foreach ($n in $Names) { $m = @($c | Where-Object { $_.Name -eq $n }); if ($m.Count) { return $m[0] } }
        return $null
    }
    $lead = [ordered]@{ CpuTemp = $null; CpuTempQ = ''; TjMax = $null; CpuMHz = $null; CpuMHzQ = ''; CpuMHzMax = $null; CpuW = $null; CpuLoad = $null
        GpuName = ''; GpuTemp = $null; GpuMHz = $null; GpuW = $null; GpuLoad = $null; GpuFan = $null
        IGpuName = ''; IGpuTemp = $null; IGpuMHz = $null; IGpuW = $null; IGpuLoad = $null; Fan = $null; DiskTemp = $null }
    # CPU-Temperatur: Package bzw. Tctl/Tdie, sonst höchster CPU-Wert, sonst ACPI-Thermalzone
    $t = & $pick 'CPU' 'Temperatur' @('CPU Package', 'Core (Tctl/Tdie)', 'Core (Tdie)', 'CCDs Max (Tdie)', 'Core (Tctl)', 'Core Max') 'Distance'
    if (-not $t) { $t = @($R | Where-Object { $_.Gruppe -eq 'CPU' -and $_.Art -eq 'Temperatur' -and $_.Name -notmatch 'Distance' } | Sort-Object Wert -Descending) | Select-Object -First 1 }
    if ($t) { $lead.CpuTemp = [math]::Round($t.Wert, 1); $lead.CpuTempQ = $t.Quelle }
    else {
        $a = @($R | Where-Object { $_.Quelle -eq 'ACPI' } | Sort-Object Wert -Descending) | Select-Object -First 1
        if ($a) { $lead.CpuTemp = [math]::Round($a.Wert, 1); $lead.CpuTempQ = 'ACPI' }
    }
    $tj = @($Readings | Where-Object { $_ -and $_.Gruppe -eq 'CPU' -and -not [double]::IsNaN([double]$_.TjMax) -and $_.TjMax -gt 50 } | ForEach-Object { $_.TjMax } | Sort-Object -Descending) | Select-Object -First 1
    if ($tj) { $lead.TjMax = [double]$tj }
    # CPU-Takt: wie im Task-Manager, sonst effektiver Mittelwert (AMD) oder Mittel der Kerntakte
    $win = & $pick 'CPU' 'Takt' @('CPU gesamt', 'Takt wie Task-Manager', 'Effektiver Takt') '' 'Windows'
    $cores = @($R | Where-Object { $_.Gruppe -eq 'CPU' -and $_.Art -eq 'Takt' -and $_.Quelle -eq 'LHM' -and $_.Name -match '^(P-|E-)?Core #\d+$' -and $_.Wert -gt 0 })
    if ($win) { $lead.CpuMHz = [math]::Round($win.Wert); $lead.CpuMHzQ = 'Windows' }
    else {
        $ce = & $pick 'CPU' 'Takt' @('Cores (Average Effective)', 'Cores (Average)')
        if ($ce) { $lead.CpuMHz = [math]::Round($ce.Wert); $lead.CpuMHzQ = 'LHM' }
        elseif ($cores.Count) { $lead.CpuMHz = [math]::Round(($cores | Measure-Object Wert -Average).Average); $lead.CpuMHzQ = 'LHM' }
    }
    if ($cores.Count) { $lead.CpuMHzMax = [math]::Round(($cores | Measure-Object Wert -Maximum).Maximum) }
    $p = & $pick 'CPU' 'Leistung' @('CPU Package', 'Package')
    if ($p) { $lead.CpuW = [math]::Round($p.Wert, 1) }
    $l = & $pick 'CPU' 'Auslastung' @('CPU Total', 'CPU gesamt')
    if ($l) { $lead.CpuLoad = [math]::Round($l.Wert) }
    # GPU: dedizierte Karte als Leitwert (bei mehreren die am stärksten ausgelastete), Prozessorgrafik zusätzlich.
    # Ohne dedizierte Karte ist die Prozessorgrafik der Leitwert.
    $devs = @($R | Where-Object { $_.Gruppe -eq 'GPU' } | ForEach-Object { $_.Geraet } | Select-Object -Unique | Sort-Object)
    $dg = @($devs | Where-Object { (Get-GpuKind $_) -notin 'iGPU', 'virtuell' })
    $ig = @($devs | Where-Object { (Get-GpuKind $_) -eq 'iGPU' })
    $loadOf = { param($d) $x = @($R | Where-Object { $_.Geraet -eq $d -and $_.Art -eq 'Auslastung' -and $_.Name -in 'GPU Core', 'D3D 3D' } | Measure-Object Wert -Maximum); if ($x.Count) { [double]$x[0].Maximum } else { 0.0 } }
    $main = $(if ($dg.Count -gt 1) { @($dg | Sort-Object { - (& $loadOf $_) }, { $_ }) | Select-Object -First 1 } elseif ($dg.Count) { $dg[0] } elseif ($ig.Count) { $ig[0] } else { $null })
    $second = $(if ($dg.Count -and $ig.Count) { $ig[0] } else { $null })
    $gpuVals = {
        param($dev)
        $G = @($R | Where-Object { $_.Gruppe -eq 'GPU' -and $_.Geraet -eq $dev })
        $gp = { param($Art, [string[]]$Names) foreach ($n in $Names) { $m = @($G | Where-Object { $_.Art -eq $Art -and $_.Name -eq $n }); if ($m.Count) { return $m[0] } }; return $null }
        $o = [ordered]@{ Temp = $null; MHz = $null; W = $null; Load = $null; Fan = $null }
        $x = & $gp 'Temperatur' @('GPU Core', 'GPU Temperature'); if (-not $x) { $x = @($G | Where-Object { $_.Art -eq 'Temperatur' -and $_.Name -notmatch 'Hot Spot|Memory|Junction' }) | Select-Object -First 1 }
        if ($x) { $o.Temp = [math]::Round($x.Wert, 1) }
        $x = & $gp 'Takt' @('GPU Core'); if ($x) { $o.MHz = [math]::Round($x.Wert) }
        $x = & $gp 'Leistung' @('GPU Package', 'GPU Power', 'GPU Total', 'GPU Board Power', 'GPU Core')
        if (-not $x) { $x = @($G | Where-Object { $_.Art -eq 'Leistung' -and $_.Name -match 'GPU' }) | Select-Object -First 1 }
        if ($x) { $o.W = [math]::Round($x.Wert, 1) }
        $x = & $gp 'Auslastung' @('GPU Core', 'D3D 3D'); if ($x) { $o.Load = [math]::Round($x.Wert) }
        $x = @($G | Where-Object { $_.Art -eq 'Lüfter' } | Sort-Object Wert -Descending) | Select-Object -First 1; if ($x) { $o.Fan = [math]::Round($x.Wert) }
        return [pscustomobject]$o
    }
    if ($main) { $v = & $gpuVals $main; $lead.GpuName = [string]$main; $lead.GpuTemp = $v.Temp; $lead.GpuMHz = $v.MHz; $lead.GpuW = $v.W; $lead.GpuLoad = $v.Load; $lead.GpuFan = $v.Fan }
    if ($second) { $v = & $gpuVals $second; $lead.IGpuName = [string]$second; $lead.IGpuTemp = $v.Temp; $lead.IGpuMHz = $v.MHz; $lead.IGpuW = $v.W; $lead.IGpuLoad = $v.Load }
    # Lüfter: CPU-Lüfter, sonst schnellster Mainboard-Lüfter
    $fans = @($R | Where-Object { $_.Gruppe -eq 'Mainboard' -and $_.Art -eq 'Lüfter' })
    $f = @($fans | Where-Object { $_.Name -match 'CPU' } | Sort-Object Wert -Descending) | Select-Object -First 1
    if (-not $f) { $f = @($fans | Sort-Object Wert -Descending) | Select-Object -First 1 }
    if ($f) { $lead.Fan = [math]::Round($f.Wert) }
    # Datenträger: höchste gemessene Temperatur (Grenzwerte laut Hersteller zählen nicht)
    $d = @($R | Where-Object { $_.Gruppe -eq 'Datenträger' -and $_.Art -eq 'Temperatur' } | Sort-Object Wert -Descending) | Select-Object -First 1
    if ($d) { $lead.DiskTemp = [math]::Round($d.Wert, 1) }
    return [pscustomobject]$lead
}

# Zahl für die Oberfläche (Punkt als Dezimaltrennzeichen, leer bei fehlendem Wert)
function Format-SensorValue($v) {
    if ($null -eq $v) { return '' }
    $d = [double]$v
    if ([double]::IsNaN($d)) { return '' }
    return $d.ToString('0.###', $script:Inv)
}

# @@SENSLEAD|t|CPU °C|CPU MHz (Task-Manager)|CPU W|GPU °C|GPU MHz|GPU W|Lüfter|CPU-Last|höchster Kerntakt|iGPU °C|iGPU MHz|iGPU W|Bilder/s GPU|Bilder/s iGPU
# (die beiden Bilder/s-Felder ab v2.6, nur während der Grafiklast des Lasttests)
function Send-SensorLead($T, $Lead, $Fps = $null, $Fps2 = $null) {
    Send-GuiEvent 'SENSLEAD' ([int]$T) (Format-SensorValue $Lead.CpuTemp) (Format-SensorValue $Lead.CpuMHz) (Format-SensorValue $Lead.CpuW) (Format-SensorValue $Lead.GpuTemp) (Format-SensorValue $Lead.GpuMHz) (Format-SensorValue $Lead.GpuW) (Format-SensorValue $Lead.Fan) (Format-SensorValue $Lead.CpuLoad) (Format-SensorValue $Lead.CpuMHzMax) (Format-SensorValue $Lead.IGpuTemp) (Format-SensorValue $Lead.IGpuMHz) (Format-SensorValue $Lead.IGpuW) (Format-SensorValue $Fps) (Format-SensorValue $Fps2)
}

# Unplausible Werte je Sensor zählen (Anzahl, höchster Rohwert). Ab v2.6 ohne Zuweisung an $tabelle[$k].Eigenschaft:
# Diese Schreibweise brach im Praxistest unter Windows PowerShell 5.1 den CPU-Lasttest ab ("Die Eigenschaft Anzahl wurde
# für dieses Objekt nicht gefunden"). Der Eintrag wird jetzt in einer eigenen Variablen geführt.
function Register-BadReadings($Readings, [hashtable]$Seen) {
    if ($null -eq $Seen) { return }
    $Readings = ConvertTo-FlatReadings $Readings
    foreach ($b in @($Readings | Where-Object { $_ -and $_.Status -eq 'unplausibel' })) {
        $k = ([string]$b.Geraet) + '|' + ([string]$b.Name)
        $e = $null
        if ($Seen.ContainsKey($k)) { $e = $Seen[$k] }
        if ($null -eq $e) {
            $e = [pscustomobject]@{ Geraet = [string]$b.Geraet; Name = [string]$b.Name; Art = [string]$b.Art; Hinweis = [string]$b.Hinweis; Anzahl = 0; Max = [double]::NaN }
            $Seen[$k] = $e
        }
        $e.Anzahl = [int]$e.Anzahl + 1
        $raw = [double]::NaN; try { $raw = [double]$b.Roh } catch { }
        if (-not [double]::IsNaN($raw) -and ([double]::IsNaN([double]$e.Max) -or $raw -gt [double]$e.Max)) { $e.Max = $raw }
    }
}

# Zeile für den Bericht: Takt, Temperatur und Leistung einer Grafikeinheit unter Last (leer ohne Werte)
function Get-GpuLoadLine([string]$Name, $Mhz, $TempMax, $WattMax) {
    $p = @()
    if ($Mhz -and $Mhz.Average) { $p += ('Takt Ø {0:N0} / max {1:N0} MHz' -f $Mhz.Average, $Mhz.Maximum) }
    if ($null -ne $TempMax) { $p += ('Temperatur max {0:N0} °C' -f $TempMax) }
    if ($null -ne $WattMax) { $p += ('Leistung max {0:N1} W' -f $WattMax) }
    if (-not $p.Count) { return '' }
    return ('{0}: {1}' -f $(if ($Name) { $Name } else { 'Grafik' }), ($p -join ', '))
}

# ---------- Auswertung ----------
# Messpunkt des Lasttests aus CPU-Messpunkt (Windows) und Leitwerten (Sensoren).
# MHz = Takt wie im Task-Manager, CpuMHz = höchster Kerntakt laut LibreHardwareMonitor.
function New-LoadSample([double]$T, $Sample, $Lead, $DiskMBs = $null, [bool]$Cpu = $false, $Fps = $null, $Fps2 = $null) {
    [pscustomobject]@{ T = [int]$T; MHz = $Sample.MHz; Last = $Sample.Last; Leistung = $Sample.Leistung; MaxFreq = $Sample.MaxFreq; Temp = $Sample.Temp
        CpuTemp = $Lead.CpuTemp; CpuTempQ = $Lead.CpuTempQ; CpuMHz = $Lead.CpuMHzMax; CpuW = $Lead.CpuW; GpuTemp = $Lead.GpuTemp; GpuMHz = $Lead.GpuMHz; GpuW = $Lead.GpuW; GpuLoad = $Lead.GpuLoad
        IGpuTemp = $Lead.IGpuTemp; IGpuMHz = $Lead.IGpuMHz; IGpuW = $Lead.IGpuW; IGpuLoad = $Lead.IGpuLoad
        Fps = $Fps; Fps2 = $Fps2
        Fan = $Lead.Fan; DiskTemp = $Lead.DiskTemp; DiskMBs = $DiskMBs; Cpu = $Cpu; Abkuehlung = $false }
}

# Schwelle aus der Einstellung: 'aus' oder 0 = keine, 'auto' = TjMax (sonst 100 °C), Zahl = fest
function Get-AbortLimit([string]$Setting, $TjMax = $null, [double]$AutoFallback = 100) {
    $s = ([string]$Setting).Trim().ToLowerInvariant()
    if (-not $s -or $s -eq 'aus' -or $s -eq '0') { return 0 }
    if ($s -eq 'auto') { if ($TjMax -and [double]$TjMax -gt 50) { return [double]$TjMax } else { return $AutoFallback } }
    $v = 0.0
    if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -ge 40 -and $v -le 125) { return $v }
    return 0
}

# Abbruch, wenn die Temperatur in den letzten -Hold Messpunkten durchgehend auf oder über der Schwelle lag.
# -CpuHold gilt für die CPU (0 = wie -Hold): Bei automatischer Schwelle (TjMax) erst nach rund einer Minute, weil viele
# Notebooks unter Volllast planmäßig an TjMax laufen und der Drosselnachweis genug Messpunkte braucht.
# ACPI-Werte zählen nur, wenn sie sich während des Tests bewegt haben (sonst Festwert der Firmware).
function Test-LoadAbort($Samples, [double]$CpuLimit, [double]$GpuLimit, [int]$Hold = 3, [int]$CpuHold = 0) {
    $s = @($Samples)
    $none = [pscustomobject]@{ Abbruch = $false; Grund = ''; Art = ''; Wert = $null }
    if ($Hold -lt 1) { return $none }
    $ch = $(if ($CpuHold -gt 0) { $CpuHold } else { $Hold })
    if ($CpuLimit -gt 0 -and $s.Count -ge $ch) {
        $last = @($s | Select-Object -Last $ch)
        $acpiMoved = @($s | Where-Object { $_.CpuTempQ -eq 'ACPI' -and $null -ne $_.CpuTemp } | ForEach-Object { $_.CpuTemp } | Select-Object -Unique).Count -gt 1
        $ok = @($last | Where-Object { $null -ne $_.CpuTemp -and [double]$_.CpuTemp -ge $CpuLimit -and ($_.CpuTempQ -ne 'ACPI' -or $acpiMoved) }).Count -eq $ch
        if ($ok) { $m = ($last | Measure-Object CpuTemp -Maximum).Maximum; return [pscustomobject]@{ Abbruch = $true; Art = 'CPU'; Wert = $m; Grund = ('CPU-Temperatur {0:N0} °C erreichte die Abbruchschwelle von {1:N0} °C' -f $m, $CpuLimit) } }
    }
    if ($GpuLimit -gt 0 -and $s.Count -ge $Hold) {
        $last = @($s | Select-Object -Last $Hold)
        $ok = @($last | Where-Object { $null -ne $_.GpuTemp -and [double]$_.GpuTemp -ge $GpuLimit }).Count -eq $Hold
        if ($ok) { $m = ($last | Measure-Object GpuTemp -Maximum).Maximum; return [pscustomobject]@{ Abbruch = $true; Art = 'GPU'; Wert = $m; Grund = ('GPU-Temperatur {0:N0} °C erreichte die Abbruchschwelle von {1:N0} °C' -f $m, $GpuLimit) } }
    }
    return $none
}

# Drosselnachweis aus dem Verlauf unter CPU-Last. Belegt wird mit Zahlen, nicht vermutet:
#   thermisch        Takt fällt, während die Temperatur an der Grenze liegt (TjMax bzw. 95 °C, wenn TjMax unbekannt)
#   Leistungsgrenze  Takt fällt mit der Paketleistung, die Temperatur bleibt mit Abstand unter der Grenze (PL1/PL2, PPT)
#   Firmware         Windows meldet eine Frequenzgrenze unter 100 % oder Ereignis 37 (Kernel-Processor-Power) ohne Temperaturbeleg
#   unklar           Takt fällt ohne erkennbaren Grund (Energieplan, Strombegrenzung, Spannungswandler)
# Rückgabe: Status (keine, thermisch, Leistungsgrenze, Firmware, unklar, nicht bewertbar), Kennzahlen, Belege und Befund.
function Get-ThrottleAnalysis {
    param($Samples, $TjMax = $null, [int]$FirmwareEvents = 0, [int]$WarmupSec = 10)
    $res = [ordered]@{ Status = 'nicht bewertbar'; Stufe = ''; Befund = ''; TaktQuelle = ''; TaktStart = $null; TaktEnde = $null; Abfall = $null
        TempMax = $null; TempQuelle = ''; Grenze = $null; GrenzeQuelle = ''; AnteilAnGrenze = $null; LeistungStart = $null; LeistungEnde = $null; FrequenzgrenzeMin = $null; Beginn = $null; Belege = @() }
    $s = @($Samples | Where-Object { $_.Cpu -and $_.T -ge $WarmupSec })
    if ($s.Count -lt 8) { $res.Befund = 'zu wenige Messpunkte unter CPU-Last'; return [pscustomobject]$res }
    # Taktquelle: Windows-Leistungszähler, wenn er sich bewegt, sonst Sensortakt
    $winVar = @($s | ForEach-Object { $_.MHz } | Where-Object { $_ -gt 0 } | Select-Object -Unique).Count -gt 1
    $sensOk = @($s | Where-Object { $_.CpuMHz -gt 0 }).Count -ge [math]::Ceiling($s.Count * 0.8)
    $clk = $(if ($winVar) { 'MHz' } elseif ($sensOk) { 'CpuMHz' } else { '' })
    $res.TaktQuelle = $(if ($clk -eq 'MHz') { 'Windows' } elseif ($clk) { 'höchster Kerntakt laut LibreHardwareMonitor' } else { '' })
    if (-not $clk) { $res.Befund = 'kein veränderlicher Taktwert verfügbar'; return [pscustomobject]$res }
    $n = $s.Count
    # Anfangsfenster: erste 15 %, höchstens 20 Messpunkte (rund 1 Minute), damit eine frühe Drosselung bei langen Tests
    # nicht im Anfangswert verschwindet; Endfenster: letztes Viertel
    $qs = [math]::Min(20, [math]::Max(3, [int][math]::Ceiling($n * 0.15))); $qe = [math]::Max(3, [int][math]::Ceiling($n * 0.25))
    $first = @($s | Select-Object -First $qs); $lastW = @($s | Select-Object -Last $qe)
    $avg = { param($set, $prop) $v = @($set | ForEach-Object { $_.$prop } | Where-Object { $null -ne $_ -and [double]$_ -gt 0 }); if ($v.Count) { [double](($v | Measure-Object -Average).Average) } else { $null } }
    $c0 = & $avg $first $clk; $c1 = & $avg $lastW $clk
    if (-not $c0 -or -not $c1) { $res.Befund = 'Taktwerte unvollständig'; return [pscustomobject]$res }
    $drop = ($c0 - $c1) / $c0 * 100
    $res.TaktStart = [math]::Round($c0); $res.TaktEnde = [math]::Round($c1); $res.Abfall = [math]::Round($drop, 1)
    # Temperatur: echte Sensorwerte; ACPI nur, wenn veränderlich
    $tv = @($s | Where-Object { $null -ne $_.CpuTemp })
    $acpiOnly = $tv.Count -and -not @($tv | Where-Object { $_.CpuTempQ -ne 'ACPI' }).Count
    if ($acpiOnly -and @($tv | ForEach-Object { $_.CpuTemp } | Select-Object -Unique).Count -le 1) { $tv = @() }
    $hasTemp = $tv.Count -ge [math]::Ceiling($n * 0.5)
    if ($hasTemp) { $res.TempMax = [math]::Round([double](($tv | Measure-Object CpuTemp -Maximum).Maximum), 1); $res.TempQuelle = $(if ($acpiOnly) { 'ACPI-Thermalzone' } else { 'Sensoren' }) }
    $lim = $(if ($TjMax -and [double]$TjMax -gt 50) { [double]$TjMax } else { 95.0 })
    $res.Grenze = $lim; $res.GrenzeQuelle = $(if ($TjMax -and [double]$TjMax -gt 50) { 'TjMax laut CPU' } else { 'Annahme 95 °C (TjMax unbekannt)' })
    $near = $lim - 5
    $hot = @(); $atLimShare = 0.0
    if ($hasTemp) {
        $hot = @($tv | Where-Object { [double]$_.CpuTemp -ge $near })
        $atLimShare = $hot.Count / [double]$tv.Count
        $res.AnteilAnGrenze = [math]::Round($atLimShare * 100)
    }
    $p0 = & $avg $first 'CpuW'; $p1 = & $avg $lastW 'CpuW'
    if ($p0) { $res.LeistungStart = [math]::Round($p0, 1) }; if ($p1) { $res.LeistungEnde = [math]::Round($p1, 1) }
    $fl = @($s | Where-Object { $_.MaxFreq -gt 0 } | ForEach-Object { [int]$_.MaxFreq })
    if ($fl.Count) { $res.FrequenzgrenzeMin = ($fl | Measure-Object -Minimum).Minimum }
    # Beginn: erster Messpunkt, ab dem der Takt dauerhaft mehr als 5 % unter dem Anfangswert liegt
    # ein Durchlauf von hinten mit laufender Summe; Messpunkte ohne Taktwert zählen nicht
    $sufSum = New-Object 'double[]' ($n + 1); $sufCnt = New-Object 'int[]' ($n + 1)
    for ($i = $n - 1; $i -ge 0; $i--) {
        $v = $s[$i].$clk; $ok = ($null -ne $v -and [double]$v -gt 0)
        $sufSum[$i] = $sufSum[$i + 1] + $(if ($ok) { [double]$v } else { 0 }); $sufCnt[$i] = $sufCnt[$i + 1] + $(if ($ok) { 1 } else { 0 })
    }
    for ($i = 0; $i -lt $n; $i++) {
        $v = $s[$i].$clk
        if ($null -eq $v -or [double]$v -le 0 -or -not $sufCnt[$i]) { continue }
        if ([double]$v -le $c0 * 0.95 -and ($sufSum[$i] / $sufCnt[$i]) -le $c0 * 0.95) { $res.Beginn = [int]$s[$i].T; break }
    }
    $bel = New-Object System.Collections.Generic.List[string]
    $bel.Add(('Takt ({0}): Ø {1:N0} MHz zu Beginn, Ø {2:N0} MHz im letzten Viertel ({3:+0.0;-0.0;0} %)' -f $res.TaktQuelle, $c0, $c1, -$drop))
    if ($hasTemp) { $bel.Add(('Temperatur ({0}): max {1:N0} °C, Grenze {2:N0} °C ({3}), {4} % der Messpunkte ab {5:N0} °C' -f $res.TempQuelle, $res.TempMax, $lim, $res.GrenzeQuelle, $res.AnteilAnGrenze, $near)) }
    else { $bel.Add(('Temperatur: keine echte CPU-Temperatur verfügbar ({0})' -f (Get-SensorGapText))) }
    if ($p0 -and $p1) { $bel.Add(('Paketleistung: Ø {0:N0} W zu Beginn, Ø {1:N0} W am Ende' -f $p0, $p1)) }
    if ($null -ne $res.FrequenzgrenzeMin -and $res.FrequenzgrenzeMin -lt 100) { $bel.Add(('Windows meldet eine Frequenzgrenze bis hinab auf {0} % des Maximums' -f $res.FrequenzgrenzeMin)) }
    if ($FirmwareEvents -gt 0) { $bel.Add(('{0} Ereignisse 37 (Kernel-Processor-Power): Firmware hat den Takt begrenzt' -f $FirmwareEvents)) }
    $res.Belege = $bel.ToArray()

    $fwLimit = ($FirmwareEvents -gt 0) -or ($null -ne $res.FrequenzgrenzeMin -and $res.FrequenzgrenzeMin -lt 95)
    $powerDrop = ($p0 -and $p1 -and $p0 -gt 0 -and (($p0 - $p1) / $p0) -ge 0.12)
    $thermal = $hasTemp -and $atLimShare -ge 0.2
    if ($drop -lt 5 -and -not ($thermal -and $drop -ge 3)) {
        $res.Status = 'keine'
        $res.Befund = $(if ($hasTemp) { 'keine Drosselung: Takt stabil (Abfall {0:N1} %), Temperatur max {1:N0} °C' -f $drop, $res.TempMax } else { 'keine Drosselung: Takt stabil (Abfall {0:N1} %)' -f $drop })
        return [pscustomobject]$res
    }
    if ($thermal) {
        $res.Status = 'thermisch'; $res.Stufe = 'WARNUNG'
        $res.Befund = ('Thermische Drosselung belegt: Der CPU-Takt fällt unter Dauerlast um {0:N0} % (Ø {1:N0} auf {2:N0} MHz), während die CPU-Temperatur {3} % der Zeit an der Grenze liegt (max {4:N0} °C, Grenze {5:N0} °C). Kühler, Lüfter, Wärmeleitpaste und Staub prüfen.' -f $drop, $c0, $c1, $res.AnteilAnGrenze, $res.TempMax, $lim)
    } elseif ($powerDrop -and (-not $hasTemp -or $res.TempMax -lt $near)) {
        $res.Status = 'Leistungsgrenze'; $res.Stufe = 'INFO'
        $res.Befund = ('Leistungsgrenze statt Hitze: Der CPU-Takt fällt um {0:N0} %, zugleich sinkt die Paketleistung von {1:N0} auf {2:N0} W{3}. Typisch für das Ende des Kurzzeit-Boosts (PL2 auf PL1 bzw. PPT); kein Kühlungsproblem.' -f $drop, $p0, $p1, $(if ($hasTemp) { ', die Temperatur bleibt bei max {0:N0} °C' -f $res.TempMax } else { '' }))
    } elseif ($fwLimit) {
        $res.Status = 'Firmware'; $res.Stufe = $(if ($drop -ge 10) { 'WARNUNG' } else { 'INFO' })
        $res.Befund = ('Der CPU-Takt fällt um {0:N0} %, Windows meldet eine Begrenzung durch die Firmware{1}. Ursache kann Temperatur, Leistungs- oder Stromgrenze sein{2}.' -f $drop, $(if ($null -ne $res.FrequenzgrenzeMin -and $res.FrequenzgrenzeMin -lt 100) { ' (Frequenzgrenze bis {0} %)' -f $res.FrequenzgrenzeMin } else { '' }), $(if (-not $hasTemp) { '; für die Unterscheidung CPU-Temperaturen mit PawnIO-Treiber messen' } else { '' }))
    } else {
        $res.Status = 'unklar'; $res.Stufe = $(if ($drop -ge 10) { 'WARNUNG' } else { 'INFO' })
        $res.Befund = ('Der CPU-Takt fällt unter Dauerlast um {0:N0} % (Ø {1:N0} auf {2:N0} MHz){3}. Energieplan, Stromgrenzen und Spannungswandler prüfen{4}.' -f $drop, $c0, $c1, $(if ($hasTemp) { ' ohne Temperaturbeleg (max {0:N0} °C)' -f $res.TempMax } else { '' }), $(if (-not $hasTemp) { '; ohne CPU-Temperatur ist thermische Drosselung nicht auszuschließen' } else { '' }))
    }
    return [pscustomobject]$res
}

# ---------- Auswertung einer Messreihe (Lasttest und ab v2.7 Benchmark) ----------
# Kennzahlen aus Messpunkten (New-LoadSample): Windows-Takt, höchster Kerntakt, Temperaturen, Leistung, Lüfter.
# Gemeinsam für Lasttest und Benchmark, damit beide Berichte dieselben Zeilen und Zahlen zeigen.
function Get-SensorSeriesStats($Samples) {
    $S = @($Samples | Where-Object { $null -ne $_ })
    $max = { param($prop) $v = @($S | Where-Object { $null -ne $_.$prop }); if ($v.Count) { ($v | Measure-Object $prop -Maximum).Maximum } else { $null } }
    $tv = @($S | Where-Object { $_.Temp } | ForEach-Object { $_.Temp } | Select-Object -Unique)
    $cpuT = @($S | Where-Object { $null -ne $_.CpuTemp -and $_.CpuTempQ -ne 'ACPI' })
    [pscustomobject]@{
        Anzahl   = $S.Count
        Mhz      = $(if ($S.Count) { $S | Measure-Object MHz -Minimum -Maximum -Average } else { $null })
        Kern     = @($S | Where-Object { $null -ne $_.CpuMHz -and $_.CpuMHz -gt 0 } | Measure-Object CpuMHz -Minimum -Maximum -Average)
        Acpi     = $tv
        AcpiFest = ($tv.Count -le 1)
        AcpiMax  = $(if ($tv.Count) { ($tv | Measure-Object -Maximum).Maximum } else { $null })
        CpuTMax  = $(if ($cpuT.Count) { ($cpuT | Measure-Object CpuTemp -Maximum).Maximum } else { $null })
        CpuWMax  = (& $max 'CpuW')
        GpuTMax  = (& $max 'GpuTemp'); GpuWMax = (& $max 'GpuW')
        GpuMhz   = @($S | Where-Object { $null -ne $_.GpuMHz -and $_.GpuMHz -gt 0 } | Measure-Object GpuMHz -Average -Maximum)
        IGpuTMax = (& $max 'IGpuTemp'); IGpuWMax = (& $max 'IGpuW')
        IGpuMhz  = @($S | Where-Object { $null -ne $_.IGpuMHz -and $_.IGpuMHz -gt 0 } | Measure-Object IGpuMHz -Average -Maximum)
        FanMax   = (& $max 'Fan'); DiskTMax = (& $max 'DiskTemp')
    }
}

# Berichtszeilen zu einer Messreihe (wie im Lasttest seit v2.3). -GpuErwartet: Hinweis, wenn die Grafik belastet wurde,
# aber keine GPU-Sensorwerte kamen. -Bad: unplausible Werte (Register-BadReadings).
function Get-SensorSeriesLines($Stats, $Idle, $TjMax = $null, [hashtable]$Bad = @{}, [string]$GpuName = '', [string]$IGpuName = '', [switch]$GpuErwartet) {
    $L = New-Object System.Collections.Generic.List[string]
    $st = $Stats
    if ($st.Mhz) { $L.Add(('  CPU-Takt: min {0:N0} / Ø {1:N0} / max {2:N0} MHz' -f $st.Mhz.Minimum, $st.Mhz.Average, $st.Mhz.Maximum)) }
    if ($st.Kern.Count -and $st.Kern[0].Count) { $L.Add(('  Höchster Kerntakt (LibreHardwareMonitor): min {0:N0} / Ø {1:N0} / max {2:N0} MHz' -f $st.Kern[0].Minimum, $st.Kern[0].Average, $st.Kern[0].Maximum)) }
    if ($null -ne $st.CpuTMax) { $L.Add(('  CPU-Temperatur (Sensoren): Leerlauf {0:N0} °C, max {1:N0} °C{2}' -f $(if ($Idle) { $Idle.CpuTemp } else { $null }), $st.CpuTMax, $(if ($TjMax) { ', TjMax {0:N0} °C' -f $TjMax } else { '' }))) }
    else { $L.Add(('  Temperatur: {0}' -f $(if (-not $st.Acpi.Count) { 'nicht auslesbar' } elseif ($st.AcpiFest) { 'nur statischer ACPI-Wert verfügbar' } else { 'max {0} °C (ACPI-Thermalzone)' -f $st.AcpiMax }))) }
    if ($null -ne $st.CpuWMax) { $L.Add(('  CPU-Paketleistung: max {0:N0} W' -f $st.CpuWMax)) }
    $gpuLine = Get-GpuLoadLine $GpuName $(if ($st.GpuMhz.Count) { $st.GpuMhz[0] } else { $null }) $st.GpuTMax $st.GpuWMax
    if ($gpuLine) { $L.Add(('  GPU {0}' -f $gpuLine)) }
    $igLine = Get-GpuLoadLine $IGpuName $(if ($st.IGpuMhz.Count) { $st.IGpuMhz[0] } else { $null }) $st.IGpuTMax $st.IGpuWMax
    if ($igLine) { $L.Add(('  Prozessorgrafik {0}' -f $igLine)) }
    if ($GpuErwartet -and -not $gpuLine -and -not $igLine) { $L.Add('  GPU: keine Sensorwerte (Takt, Temperatur, Leistung) verfügbar.') }
    if ($Bad -and $Bad.Count) {
        $L.Add('  Verworfene Sensorwerte (unplausibel, nicht angezeigt und nicht ausgewertet):')
        foreach ($b in @($Bad.Values)) { $L.Add(('    {0} {1}: {2}x, höchster Rohwert {3:N0}; {4}' -f $b.Geraet, $b.Name, $b.Anzahl, $b.Max, $b.Hinweis)) }
    }
    $sDelay = Get-SensorDelayText
    if ($sDelay) { $L.Add(('  Sensoren: {0}.' -f $sDelay)) }
    if ($null -ne $st.FanMax) { $L.Add(('  Lüfter: max {0:N0} U/min' -f $st.FanMax)) }
    if ($null -ne $st.DiskTMax) { $L.Add(('  Datenträger: Temperatur max {0:N0} °C' -f $st.DiskTMax)) }
    return $L.ToArray()
}

# ---------- Sensoren während des Benchmarks (ab v2.7) ----------
# Die Messungen des Benchmarks dauern nur Sekunden. Die Sensoren werden deshalb in den Wartepausen gelesen, in denen der
# Arbeitsprozess ohnehin auf eine Messung wartet (Wait-TaskProgress, Datenträger, Rendertest, WinSAT): höchstens alle
# 2 Sekunden ein Messpunkt, kein zusätzlicher Thread. Während der Laufwerksmessung fragt LibreHardwareMonitor die
# Datenträger nicht ab (SMART-Abfragen würden die 4K-Werte stören); deren letzte Werte gelten weiter.
$script:BenchSens = $null
function Start-BenchSensors {
    if ($script:BenchSens) { return $script:BenchSens }
    $b = [pscustomobject]@{ On = $false; T0 = (Get-Date); Samples = (New-Object System.Collections.ArrayList); Teil = ''; Teile = (New-Object System.Collections.ArrayList)
        Zuletzt = [datetime]::MinValue; IntervallMs = 2000; Idle = $null; TjMax = $null; Bad = @{}; StorageMs = $null; Fehler = '' }
    $script:BenchSens = $b
    Show-Sub 'Benchmark' 'Sensoren werden geöffnet (höchstens 30 Sekunden)' -1
    try { [void](Open-SensorSession -Treiber:$SensorTreiber) } catch { $b.Fehler = $_.Exception.Message }
    try { [DiagSensors]::ResetStats() } catch { }
    $s = $null; try { $s = Get-CpuSample } catch { }
    $b.Idle = Read-BenchSensorLead $s
    if ($b.Idle -and $b.Idle.TjMax) { $b.TjMax = [double]$b.Idle.TjMax }
    $b.T0 = Get-Date
    $b.On = $true
    Hide-Sub
    return $b
}

function Read-BenchSensorLead($CpuSample) {
    $rd = @()
    try { $rd = ConvertTo-FlatReadings (Get-SensorReadings -CpuSample $CpuSample) } catch { try { $rd = @(ConvertFrom-CpuSampleReadings $CpuSample) } catch { $rd = @() } }
    if ($script:BenchSens) { try { Register-BadReadings $rd $script:BenchSens.Bad } catch { } }
    try { return (Get-SensorLead $rd) } catch { return (Get-SensorLead @()) }
}

# Neuer Abschnitt (Prozessor, Arbeitsspeicher, Grafik, Datenträger, WinSAT): beendet den vorigen, nächster Messpunkt sofort
function Set-BenchSensorPart([string]$Teil) {
    $b = $script:BenchSens
    if (-not $b -or -not $b.On) { return }
    $t = [int]((Get-Date) - $b.T0).TotalSeconds
    if ($b.Teile.Count -and $null -eq $b.Teile[$b.Teile.Count - 1].Ende) { $b.Teile[$b.Teile.Count - 1].Ende = $t }
    $b.Teil = $Teil
    [void]$b.Teile.Add([pscustomobject]@{ Teil = $Teil; Beginn = $t; Ende = $null })
    if ($Teil -eq 'Datenträger') { try { if ($null -eq $b.StorageMs) { $b.StorageMs = [DiagSensors]::StorageIntervalMs }; [DiagSensors]::StorageIntervalMs = 86400000 } catch { } }
    elseif ($null -ne $b.StorageMs) { try { [DiagSensors]::StorageIntervalMs = $b.StorageMs } catch { }; $b.StorageMs = $null }
    $b.Zuletzt = [datetime]::MinValue
}

# Messpunkt in einer Wartepause (höchstens alle IntervallMs). -CpuSample: schon gelesener CPU-Messpunkt (spart eine Abfrage)
function Add-BenchSensorSample($CpuSample = $null) {
    $b = $script:BenchSens
    if (-not $b -or -not $b.On) { return }
    $now = Get-Date
    if (($now - $b.Zuletzt).TotalMilliseconds -lt $b.IntervallMs) { return }
    $b.Zuletzt = $now
    try {
        if (-not $CpuSample) { $CpuSample = Get-CpuSample }
        $lead = Read-BenchSensorLead $CpuSample
        $el = ($now - $b.T0).TotalSeconds
        $x = New-LoadSample $el $CpuSample $lead
        $x | Add-Member -NotePropertyName Teil -NotePropertyValue $b.Teil -Force
        [void]$b.Samples.Add($x)
        if (-not $b.TjMax -and $lead.TjMax) { $b.TjMax = [double]$lead.TjMax }
        try { Send-SensorLead $el $lead } catch { }
    } catch { }
}

function Stop-BenchSensors {
    $b = $script:BenchSens
    if (-not $b) { return }
    if ($b.On -and $b.Teile.Count -and $null -eq $b.Teile[$b.Teile.Count - 1].Ende) { $b.Teile[$b.Teile.Count - 1].Ende = [int]((Get-Date) - $b.T0).TotalSeconds }
    if ($null -ne $b.StorageMs) { try { [DiagSensors]::StorageIntervalMs = $b.StorageMs } catch { }; $b.StorageMs = $null }
    $b.On = $false
}

# Kennzahlen je Abschnitt des Benchmarks: eine Zeile je Teil mit den Werten, die dort gemessen wurden
function Get-BenchSensorRows($Samples, $Teile) {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($t in @($Teile)) {
        $S = @($Samples | Where-Object { $_.Teil -eq $t.Teil })
        if (-not $S.Count) { continue }
        $st = Get-SensorSeriesStats $S
        $dur = $(if ($null -ne $t.Ende) { [int]$t.Ende - [int]$t.Beginn } else { $null })
        $rows.Add([pscustomobject][ordered]@{
            Teil = $t.Teil; Dauer = $(if ($null -ne $dur) { '{0}:{1:00}' -f [int][math]::Floor($dur / 60), [int]($dur % 60) } else { '' }); Messpunkte = $S.Count
            CpuMhzAvg = $(if ($st.Mhz) { [math]::Round($st.Mhz.Average) } else { $null }); CpuMhzMax = $(if ($st.Mhz) { [math]::Round($st.Mhz.Maximum) } else { $null })
            KernMax = $(if ($st.Kern.Count -and $st.Kern[0].Count) { [math]::Round($st.Kern[0].Maximum) } else { $null })
            CpuTMax = $st.CpuTMax; CpuWMax = $st.CpuWMax; GpuTMax = $st.GpuTMax; GpuMhzAvg = $(if ($st.GpuMhz.Count -and $st.GpuMhz[0].Count) { [math]::Round($st.GpuMhz[0].Average) } else { $null }); GpuWMax = $st.GpuWMax
            IGpuTMax = $st.IGpuTMax; IGpuWMax = $st.IGpuWMax; FanMax = $st.FanMax; DiskTMax = $st.DiskTMax
        })
    }
    return $rows.ToArray()
}

# Tabelle je Abschnitt für den Textbericht; Spalten ohne einen einzigen Wert entfallen
function Format-BenchSensorTable($Rows) {
    $fmt = { param($v, $u) if ($null -eq $v -or "$v" -eq '') { '' } else { ('{0:N0} {1}' -f [double]$v, $u) } }
    $cols = @(
        @('Abschnitt', 'Teil', ''), @('Dauer', 'Dauer', ''), @('CPU-Takt Ø', 'CpuMhzAvg', 'MHz'), @('höchster Kern', 'KernMax', 'MHz'), @('CPU max', 'CpuTMax', '°C'), @('CPU-Paket max', 'CpuWMax', 'W'),
        @('GPU max', 'GpuTMax', '°C'), @('GPU-Takt Ø', 'GpuMhzAvg', 'MHz'), @('GPU-Leistung max', 'GpuWMax', 'W'), @('Prozessorgrafik max', 'IGpuTMax', '°C'), @('Lüfter max', 'FanMax', 'U/min'), @('Datenträger max', 'DiskTMax', '°C'))
    $use = @($cols | Where-Object { $c = $_; -not $c[2] -or @($Rows | Where-Object { $null -ne $_.($c[1]) -and "$($_.($c[1]))" -ne '' }).Count })
    foreach ($r in @($Rows)) {
        $o = [ordered]@{}
        foreach ($c in $use) { $o[$c[0]] = $(if ($c[2]) { & $fmt $r.($c[1]) $c[2] } else { [string]$r.($c[1]) }) }
        [pscustomobject]$o
    }
}

# Bericht, Befunde, Datenbank und CSV zu den Sensoren des Benchmarks (Abschnitt Auswertung und Vergleich)
function Write-BenchSensorReport {
    $b = $script:BenchSens
    if (-not $b) { return }
    $S = @($b.Samples)
    Add-Sub 'Sensoren während des Benchmarks'
    Add-Line ('  Sensoren: {0}' -f (Get-SensorSourceText))
    Add-SensorGapFinding 'Der Benchmark'
    if ($b.Fehler) { Add-Line ('  Sensoren ließen sich nicht öffnen: {0}. Gezeigt werden die Windows-Werte.' -f $b.Fehler) }
    $idle = $b.Idle
    if ($idle) { Add-Line ('  Leerlauf vor dem Benchmark: CPU {0}, GPU {1}, Paketleistung {2}' -f $(if ($null -ne $idle.CpuTemp) { '{0:N0} °C ({1})' -f $idle.CpuTemp, $idle.CpuTempQ } else { 'Temperatur nicht verfügbar' }), $(if ($null -ne $idle.GpuTemp) { '{0:N0} °C' -f $idle.GpuTemp } else { 'nicht verfügbar' }), $(if ($null -ne $idle.CpuW) { '{0:N0} W' -f $idle.CpuW } else { 'nicht verfügbar' })) }
    if (-not $S.Count) { Add-Line '  Keine Messpunkte (die Messungen waren kürzer als der Abstand der Sensorabfragen).'; return }
    Add-Line ('  {0} Messpunkte in den Wartepausen der Messungen, höchstens alle {1} s.' -f $S.Count, ($b.IntervallMs / 1000))
    $rows = @(Get-BenchSensorRows $S $b.Teile)
    $script:BenchSensorRows = $rows
    Format-BenchSensorTable $rows | Out-Report
    Add-Line '  Gesamt über alle Messungen:'
    $st = Get-SensorSeriesStats $S
    $gName = $(if ($idle -and $idle.GpuName) { $idle.GpuName } else { '' }); $igName = $(if ($idle -and $idle.IGpuName) { $idle.IGpuName } else { '' })
    foreach ($ln in @(Get-SensorSeriesLines $st $idle $b.TjMax $b.Bad $gName $igName)) { Add-Line ('  ' + $ln) }
    # Befunde: Grenztemperaturen während kurzer Messungen verfälschen die Werte (Drosselung)
    $tj = $(if ($b.TjMax) { [double]$b.TjMax } else { 100.0 })
    if ($null -ne $st.CpuTMax -and $st.CpuTMax -ge [math]::Min(95.0, $tj - 3)) {
        $wo = @($rows | Where-Object { $null -ne $_.CpuTMax -and $_.CpuTMax -ge [math]::Min(95.0, $tj - 3) } | ForEach-Object { $_.Teil })
        Add-Finding INFO 'Benchmark' ('Die CPU erreichte während des Benchmarks {0:N0} °C{1} ({2}). Die Prozessorwerte können durch Drosselung niedriger ausfallen; Kühlung prüfen und den Lasttest CPU für den Drosselnachweis nutzen.' -f $st.CpuTMax, $(if ($b.TjMax) { ' bei TjMax {0:N0} °C' -f $b.TjMax } else { '' }), ($wo -join ', '))
    }
    if ($null -ne $st.GpuTMax -and $st.GpuTMax -ge 90) { Add-Finding INFO 'Benchmark' ('Die Grafikkarte erreichte während des Benchmarks {0:N0} °C. Die Grafikwerte können durch Drosselung niedriger ausfallen.' -f $st.GpuTMax) }
    if ($null -ne $st.DiskTMax -and $st.DiskTMax -ge 70) { Add-Finding INFO 'Benchmark' ('Ein Datenträger erreichte während des Benchmarks {0:N0} °C (NVMe drosseln ab etwa 70 °C).' -f $st.DiskTMax) }
    $script:BenchSeries = $S
    $script:SensorDb['Benchmark'] = [ordered]@{
        CpuTempLeerlauf = $(if ($idle) { $idle.CpuTemp } else { $null }); CpuTempMax = $st.CpuTMax; TjMax = $b.TjMax; CpuWMax = $st.CpuWMax
        CpuMHzMax = $(if ($st.Kern.Count -and $st.Kern[0].Count) { [math]::Round($st.Kern[0].Maximum) } else { $null })
        Gpu = $gName; GpuTempMax = $st.GpuTMax; GpuWMax = $st.GpuWMax; IGpu = $igName; IGpuTempMax = $st.IGpuTMax; IGpuWMax = $st.IGpuWMax
        LuefterMax = $st.FanMax; DatentraegerTempMax = $st.DiskTMax; Messpunkte = $S.Count; Quelle = (Get-SensorSourceText)
        Abschnitte = @($rows | ForEach-Object { [ordered]@{ Teil = $_.Teil; CpuTempMax = $_.CpuTMax; CpuWMax = $_.CpuWMax; CpuMHzAvg = $_.CpuMhzAvg; GpuTempMax = $_.GpuTMax; GpuWMax = $_.GpuWMax } })
    }
    try { $S | Select-Object T, Teil, MHz, Last, Leistung, MaxFreq, Temp, CpuTemp, CpuTempQ, @{n = 'CpuMHzMax'; e = { $_.CpuMHz } }, CpuW, GpuTemp, GpuMHz, GpuW, GpuLoad, IGpuTemp, IGpuMHz, IGpuW, IGpuLoad, Fan, DiskTemp | Export-Csv -Path (Join-Path $RawDir 'Benchmark-Sensoren.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8 } catch { }
}

# Momentaufnahme für die Diagnose: Werte im Leerlauf mit Plausibilitätsprüfung
function Get-SensorSnapshotFindings($Readings, $Lead) {
    $f = New-Object System.Collections.Generic.List[object]
    $add = { param($lvl, $txt) $f.Add([pscustomobject]@{ Stufe = $lvl; Text = $txt }) }
    if (Test-IsArm64) {
        & $add 'INFO' 'ARM64-Architektur erkannt: Tiefgehende Kern- und Mainboard-Sensoren erfordern x86/x64-Treiber und stehen nur eingeschränkt zur Verfügung.'
    }
    if ($null -ne $Lead.CpuTemp -and $Lead.CpuTempQ -ne 'ACPI') {
        if ($Lead.CpuTemp -ge 80) { & $add 'WARNUNG' ('CPU-Temperatur im Leerlauf {0:N0} °C: Kühlung prüfen (Lüfter, Staub, Wärmeleitpaste) oder Hintergrundlast suchen.' -f $Lead.CpuTemp) }
        elseif ($Lead.CpuTemp -ge 70) { & $add 'INFO' ('CPU-Temperatur im Leerlauf {0:N0} °C, etwas hoch.' -f $Lead.CpuTemp) }
    }
    if ($null -ne $Lead.GpuTemp -and $Lead.GpuTemp -ge 80) { & $add 'WARNUNG' ('GPU-Temperatur im Leerlauf {0:N0} °C: Grafikkartenlüfter und Gehäusebelüftung prüfen.' -f $Lead.GpuTemp) }
    $cpuFan = @($Readings | Where-Object { $_.Gruppe -eq 'Mainboard' -and $_.Art -eq 'Lüfter' -and $_.Name -match 'CPU' -and -not [double]::IsNaN([double]$_.Wert) })
    if ($cpuFan.Count -and -not @($cpuFan | Where-Object { $_.Wert -gt 0 }).Count -and $null -ne $Lead.CpuTemp -and $Lead.CpuTemp -ge 60) {
        & $add 'WARNUNG' ('Der CPU-Lüfteranschluss meldet 0 U/min bei {0:N0} °C: Lüfter angeschlossen und dreht er?' -f $Lead.CpuTemp)
    }
    return $f.ToArray()
}
#endregion
