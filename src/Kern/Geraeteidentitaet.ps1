#region ---------- Geräteidentität ----------
# Eine Kennung je Gerät, die eine Neuinstallation von Windows und eine Umbenennung des PCs übersteht.
# Grundlage sind Mainboard und Firmware (SMBIOS): System-UUID, Hersteller, Modell und Seriennummer des Mainboards,
# Seriennummer im BIOS. In der Datenbank steht nur ein SHA-256-Hash, keine Seriennummer.
# Ein Tausch des Mainboards ergibt eine neue Kennung; das ist gewollt, denn danach ist es messtechnisch ein anderes Gerät.

# Werte, die Hersteller statt einer echten Kennung eintragen
function Test-PlaceholderId([string]$Value) {
    $v = ([string]$Value).Trim()
    if ($v.Length -lt 4) { return $true }
    if ($v -match '^(?i)(to be filled by o\.?e\.?m\.?|default string|system serial number|system product name|base board serial number|chassis serial number|not specified|not applicable|none|n/?a|unknown|invalid|o\.?e\.?m\.?|123456789|0123456789|x+|0+|f+)$') { return $true }
    # UUIDs ohne Aussagekraft: nur Nullen oder nur F, und die verbreitete Platzhalter-UUID vieler Boards
    $u = $v -replace '[{}\-\s]', ''
    if ($u -match '^(0+|F+)$' -or $u -eq '03000200040005000006000700080009') { return $true }
    return $false
}

function Get-Sha256Hex([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') })) }
    finally { $sha.Dispose() }
}

# Kennung aus den Rohwerten bilden. Güte: hoch (UUID und Seriennummer), mittel (eines von beiden), niedrig (nur Modell und Computername)
function ConvertTo-DeviceId {
    param([string]$Uuid, [string]$BoardVendor, [string]$BoardProduct, [string]$BoardSerial, [string]$BiosSerial, [string]$ComputerName)
    $norm = { param($s) (([string]$s) -replace '\s+', ' ').Trim().ToUpperInvariant() }
    $parts = New-Object System.Collections.Generic.List[string]
    $quellen = New-Object System.Collections.Generic.List[string]
    $strong = 0
    if (-not (Test-PlaceholderId $Uuid)) { $parts.Add('UUID=' + (& $norm ($Uuid -replace '[{}]', ''))); $quellen.Add('System-UUID'); $strong++ }
    $serial = $(if (-not (Test-PlaceholderId $BoardSerial)) { $BoardSerial; $quellen.Add('Seriennummer Mainboard') } elseif (-not (Test-PlaceholderId $BiosSerial)) { $BiosSerial; $quellen.Add('Seriennummer BIOS') } else { '' })
    if ($serial) { $parts.Add('SN=' + (& $norm $serial)); $strong++ }
    $model = ('{0} {1}' -f (& $norm $BoardVendor), (& $norm $BoardProduct)).Trim()
    if ($model -and -not (Test-PlaceholderId $model)) { $parts.Add('BOARD=' + $model); $quellen.Add('Mainboard-Modell') }
    if (-not $strong) {
        # Ohne eindeutige Firmwarewerte bleibt nur der Computername; die Kennung ist dann nicht besser als der Name
        $parts.Add('PC=' + (& $norm $ComputerName)); $quellen.Add('Computername')
    }
    $guete = $(if ($strong -ge 2) { 'hoch' } elseif ($strong -eq 1) { 'mittel' } else { 'niedrig' })
    return [pscustomobject]@{ Id = ('G-' + (Get-Sha256Hex ($parts -join ';')).Substring(0, 20)); Guete = $guete; Quellen = $quellen.ToArray() }
}

# Kennung dieses PCs (einmal je Lauf ermittelt)
$script:DeviceIdentity = $null
function Get-DeviceIdentity {
    if ($script:DeviceIdentity) { return $script:DeviceIdentity }
    $uuid = ''; $bv = ''; $bp = ''; $bs = ''; $bios = ''
    try { $uuid = [string](Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID } catch { }
    try { $bb = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1; $bv = [string]$bb.Manufacturer; $bp = [string]$bb.Product; $bs = [string]$bb.SerialNumber } catch { }
    try { $bios = [string](Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber } catch { }
    $script:DeviceIdentity = ConvertTo-DeviceId -Uuid $uuid -BoardVendor $bv -BoardProduct $bp -BoardSerial $bs -BiosSerial $bios -ComputerName $env:COMPUTERNAME
    return $script:DeviceIdentity
}

# Geräteschlüssel für alle Einträge setzen: Einträge mit Kennung behalten sie. Ältere Einträge ohne Kennung (Format 1,
# Importe) übernehmen die Kennung, wenn genau ein Gerät mit Kennung diesen Computernamen trägt, sonst gilt der Name.
function Set-DbDeviceKeys($Entries) {
    $byName = @{}
    foreach ($e in @($Entries)) {
        if ([string]$e.GeraetId) {
            $n = ([string]$e.Computer).ToUpperInvariant()
            if (-not $byName.ContainsKey($n)) { $byName[$n] = New-Object 'System.Collections.Generic.HashSet[string]' }
            [void]$byName[$n].Add([string]$e.GeraetId)
        }
    }
    foreach ($e in @($Entries)) {
        $n = ([string]$e.Computer).ToUpperInvariant()
        $key = $(if ([string]$e.GeraetId) { [string]$e.GeraetId } elseif ($byName.ContainsKey($n) -and $byName[$n].Count -eq 1) { @($byName[$n])[0] } else { 'PC:' + $n })
        $e | Add-Member -NotePropertyName GeraetKey -NotePropertyValue $key -Force
    }
}

# Gehört ein Datenbankeintrag zu diesem Gerät? Über die Kennung, bei älteren Einträgen ohne Zuordnung über den Computernamen.
function Test-SameDevice($Entry, [string]$DeviceId, [string]$ComputerName) {
    $key = [string]$Entry.GeraetKey
    if (-not $key) { $key = $(if ([string]$Entry.GeraetId) { [string]$Entry.GeraetId } else { 'PC:' + ([string]$Entry.Computer).ToUpperInvariant() }) }
    if ($key.StartsWith('G-')) { return ($DeviceId -and $key -eq $DeviceId) }
    return ([string]$Entry.Computer -eq $ComputerName)
}
#endregion
