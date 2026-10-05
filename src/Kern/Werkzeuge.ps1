#region ---------- Portable Werkzeuge mit Manifest ----------
# Externe Programme auf dem Stick liegen unter Minibench-Daten\Tools. Tools.json hält je Werkzeug Datei, Version,
# SHA-256, Lizenz und Quelle fest. Ausgeführt wird eine Datei nur, wenn ihr Hash zum Manifest passt; eine veränderte
# oder ausgetauschte Datei bleibt liegen und erscheint als Befund.
# Grenze: Wer Datei und Manifest gemeinsam austauscht, wird so nicht erkannt. Das Manifest schützt vor beschädigten,
# versehentlich ersetzten oder fremd untergeschobenen Einzeldateien, nicht vor gezielter Manipulation des ganzen Sticks.
$script:ToolManifestFormat = 'Minibench-Tools/1'
$script:ToolIssues = New-Object System.Collections.Generic.List[string]

function Get-ToolsDir { if ($script:DataDir) { return (Join-Path $script:DataDir 'Tools') } else { return '' } }

function Get-FileSha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $fs = [IO.File]::OpenRead($Path)
    try { return (-join ($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') })) }
    finally { $fs.Dispose(); $sha.Dispose() }
}

function Read-ToolManifest([string]$ToolsDir = (Get-ToolsDir)) {
    $m = [ordered]@{ Format = $script:ToolManifestFormat; Werkzeuge = @() }
    if (-not $ToolsDir) { return $m }
    $f = Join-Path $ToolsDir 'Tools.json'
    if (-not (Test-Path -LiteralPath $f)) { return $m }
    try {
        $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.Werkzeuge = @($j.Werkzeuge | Where-Object { $_ } | ForEach-Object {
            [ordered]@{ Name = [string]$_.Name; Datei = [string]$_.Datei; Version = [string]$_.Version; SHA256 = ([string]$_.SHA256).ToLowerInvariant()
                        Lizenz = [string]$_.Lizenz; Quelle = [string]$_.Quelle; Aufgenommen = [string]$_.Aufgenommen; Herkunft = [string]$_.Herkunft }
        })
    } catch { $script:ToolIssues.Add(('Tools.json ist nicht lesbar ({0}); portable Werkzeuge werden nicht ausgeführt.' -f $_.Exception.Message)); $m.Ungueltig = $true }
    return $m
}

function Save-ToolManifest($Manifest, [string]$ToolsDir = (Get-ToolsDir)) {
    if (-not $ToolsDir) { return $false }
    try {
        New-Item -ItemType Directory -Path $ToolsDir -Force -ErrorAction Stop | Out-Null
        $o = [ordered]@{ Format = $script:ToolManifestFormat; Hinweis = 'Ausgeführt wird nur, was zu SHA256 passt. Datei ist relativ zu diesem Ordner.'; Werkzeuge = @($Manifest.Werkzeuge) }
        [IO.File]::WriteAllText((Join-Path $ToolsDir 'Tools.json'), ($o | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
        return $true
    } catch { return $false }
}

# Datei ins Manifest aufnehmen (nach dem Holen aus vertrauenswürdiger Quelle) oder ihren Eintrag erneuern
function Register-Tool {
    param([string]$Name, [string]$Path, [string]$Lizenz = '', [string]$Quelle = '', [string]$Herkunft = '', [string]$ToolsDir = (Get-ToolsDir))
    if (-not $ToolsDir -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $full = (Resolve-Path -LiteralPath $Path).Path
    $root = (Resolve-Path -LiteralPath $ToolsDir).Path.TrimEnd('\', '/')
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw ('{0} liegt nicht im Tools-Ordner.' -f $full) }
    $ver = ''
    try { $vi = (Get-Item -LiteralPath $full).VersionInfo; $ver = $(if ($vi.ProductVersion) { [string]$vi.ProductVersion } else { [string]$vi.FileVersion }) } catch { }
    $e = [ordered]@{ Name = $Name; Datei = $full.Substring($root.Length + 1); Version = $ver.Trim(); SHA256 = (Get-FileSha256 $full)
                     Lizenz = $Lizenz; Quelle = $Quelle; Aufgenommen = (Get-Date).ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture); Herkunft = $Herkunft }
    $m = Read-ToolManifest $ToolsDir
    if ($m.Ungueltig) { return $null }
    $m.Werkzeuge = @(@($m.Werkzeuge | Where-Object { $_.Name -ne $Name }) + $e)
    if (Save-ToolManifest $m $ToolsDir) { return $e }
    return $null
}

# Pfad eines Werkzeugs, wenn Datei vorhanden und Hash passend; sonst $null und ein Eintrag in $script:ToolIssues
function Get-VerifiedTool([string]$Name, [string]$ToolsDir = (Get-ToolsDir)) {
    if (-not $ToolsDir) { return $null }
    $m = Read-ToolManifest $ToolsDir
    if ($m.Ungueltig) { return $null }
    $e = @($m.Werkzeuge | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
    if (-not $e) { return $null }
    $p = Join-Path $ToolsDir $e.Datei
    if (-not (Test-Path -LiteralPath $p)) { $script:ToolIssues.Add(('{0}: {1} fehlt im Tools-Ordner.' -f $Name, $e.Datei)); return $null }
    $h = Get-FileSha256 $p
    if ($h -ne $e.SHA256) {
        $script:ToolIssues.Add(('{0}: {1} passt nicht zum Manifest (SHA-256 {2}… statt {3}…) und wird nicht ausgeführt. Datei neu holen oder bewusst neu aufnehmen.' -f $Name, $e.Datei, $h.Substring(0, 12), ([string]$e.SHA256).Substring(0, [math]::Min(12, ([string]$e.SHA256).Length))))
        return $null
    }
    return $p
}

# Übergang von 2.1: dort ohne Manifest abgelegte Werkzeuge einmalig aufnehmen (Hash beim ersten Start festgehalten)
function Register-LegacyTool([string]$Name, [string[]]$RelPaths, [string]$Lizenz, [string]$Quelle, [string]$ToolsDir = (Get-ToolsDir)) {
    if (-not $ToolsDir) { return $null }
    $m = Read-ToolManifest $ToolsDir
    if ($m.Ungueltig -or @($m.Werkzeuge | Where-Object { $_.Name -eq $Name }).Count) { return $null }
    foreach ($r in $RelPaths) {
        $p = Join-Path $ToolsDir $r
        if (Test-Path -LiteralPath $p) { return (Register-Tool -Name $Name -Path $p -Lizenz $Lizenz -Quelle $Quelle -Herkunft 'aus Version 2.1 ohne Manifest übernommen' -ToolsDir $ToolsDir) }
    }
    return $null
}
#endregion

#region ---------- Hilfswerkzeuge je Gerät behalten (ab 2.4) ----------
# Auf eigenen PCs können PawnIO und eine per winget installierte smartmontools-Fassung bleiben, statt nach jedem Lauf
# entfernt zu werden. Die Wahl gilt je Gerätekennung und steht im Datenordner in Geraete.json:
#   { Format = 'Minibench-Geraete/1'; Geraete = { <Kennung> = { Name; Werkzeuge = fragen|entfernen|behalten; Behalten = [...]; Geaendert } } }
# Werkzeuge = Voreinstellung (die Oberfläche schreibt sie), Behalten = was Leos Minibench auf dem Gerät gelassen hat
# (schreibt der Arbeitsprozess). Ohne Datei und ohne -WerkzeugeBehalten wird wie bisher alles entfernt.
$script:DeviceSettingsFormat = 'Minibench-Geraete/1'
$script:ToolKeep = $null
$script:ToolKeepExplicit = $false
function Get-DeviceSettingsPath { if ($script:DataDir) { return (Join-Path $script:DataDir 'Geraete.json') } else { return '' } }

function Read-DeviceSettings([string]$Path = (Get-DeviceSettingsPath)) {
    $res = @{}
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $res }
    try { $j = [IO.File]::ReadAllText($Path) | ConvertFrom-Json } catch { return $res }
    if (-not $j -or [string]$j.Format -ne $script:DeviceSettingsFormat -or -not $j.Geraete) { return $res }
    foreach ($p in $j.Geraete.PSObject.Properties) {
        $v = $p.Value
        $res[$p.Name] = [ordered]@{ Name = [string]$v.Name; Werkzeuge = [string]$v.Werkzeuge; Treiber = [string]$v.Treiber; PawnIoVersion = [string]$v.PawnIoVersion; Behalten = @($v.Behalten | Where-Object { $_ } | ForEach-Object { [string]$_ }); Geaendert = [string]$v.Geaendert }
    }
    return $res
}

function Save-DeviceSettings($All, [string]$Path = (Get-DeviceSettingsPath)) {
    if (-not $Path) { return $false }
    $o = [ordered]@{ Format = $script:DeviceSettingsFormat; Geraete = [ordered]@{} }
    foreach ($k in @($All.Keys | Sort-Object)) { $o.Geraete[$k] = $All[$k] }
    try { [IO.File]::WriteAllText($Path, ($o | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false))); return $true } catch { return $false }
}

function Get-DeviceSetting([string]$Id) {
    $all = Read-DeviceSettings
    if ($Id -and $all.ContainsKey($Id)) { return $all[$Id] }
    return [ordered]@{ Name = $env:COMPUTERNAME; Werkzeuge = 'fragen'; Treiber = 'fragen'; PawnIoVersion = ''; Behalten = @(); Geaendert = '' }
}

function Update-DeviceSetting([string]$Id, [scriptblock]$Change) {
    if (-not $Id) { return $false }
    $all = Read-DeviceSettings
    $e = $(if ($all.ContainsKey($Id)) { $all[$Id] } else { [ordered]@{ Name = $env:COMPUTERNAME; Werkzeuge = 'fragen'; Treiber = 'fragen'; PawnIoVersion = ''; Behalten = @(); Geaendert = '' } })
    & $Change $e
    $e.Name = $env:COMPUTERNAME
    $e.Geaendert = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
    $all[$Id] = $e
    return (Save-DeviceSettings $all)
}

# Wirksame Wahl dieses Laufs: Parameter -WerkzeugeBehalten, sonst gespeicherte Voreinstellung, sonst entfernen
function Get-ToolKeep {
    if ($script:ToolKeep) { return $script:ToolKeep }
    $k = ([string]$WerkzeugeBehalten).ToLowerInvariant()
    $script:ToolKeepExplicit = $true
    if ($k -notin 'behalten', 'entfernen') {
        $id = ''; try { $id = (Get-DeviceIdentity).Id } catch { }
        $pref = [string](Get-DeviceSetting $id).Werkzeuge
        $script:ToolKeepExplicit = ($pref -in 'behalten', 'entfernen')
        $k = $(if ($pref -eq 'behalten') { 'behalten' } else { 'entfernen' })
    }
    $script:ToolKeep = $k
    return $k
}

# Früher behaltene Werkzeuge werden nur entfernt, wenn "entfernen" ausdrücklich gewählt ist (Parameter oder Einstellung).
# Bei "jedes Mal fragen" ohne Antwort bleibt ein behaltenes Werkzeug, neu installierte werden entfernt.
function Test-ToolRemoveKept { return ((Get-ToolKeep) -eq 'entfernen' -and [bool]$script:ToolKeepExplicit) }

function Test-KeptTool([string]$Name) {
    $id = ''; try { $id = (Get-DeviceIdentity).Id } catch { }
    return (@((Get-DeviceSetting $id).Behalten) -contains $Name)
}
function Set-KeptTool([string]$Name, [bool]$Kept) {
    $id = ''; try { $id = (Get-DeviceIdentity).Id } catch { }
    $n = $Name; $kp = $Kept
    return (Update-DeviceSetting $id ({ param($e) $l = @($e.Behalten | Where-Object { $_ -and $_ -ne $n }); if ($kp) { $l += $n }; $e.Behalten = @($l) }.GetNewClosure()))
}
#endregion
