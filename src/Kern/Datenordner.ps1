#region ---------- Datenordner neben exe bzw. Skript (Berichte, Vergleichsdatenbank, Tools, Laufzeitdaten) ----------
function Test-WritableDir([string]$Dir) {
    if (-not $Dir) { return $false }
    try {
        New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop | Out-Null
        $probe = Join-Path $Dir ('.schreibtest_{0}.tmp' -f $PID)
        [IO.File]::WriteAllText($probe, 'x'); Remove-Item $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}
# Ab v3.54 liegt der Datenordner immer lokal (neben dem Programm, also auf dem Stick). Ein Netzlaufwerk (NAS) ist nur noch
# ein Spiegel der Nutzerdaten, abgeglichen per Aktualisieren (Kern\Ablage.ps1). Der Start greift nie auf das NAS zu:
# vorher konnte ein nicht erreichbares NAS den Start um Minuten verzögern oder ganz anhalten (net use, SMB-Zeitlimits).
function Resolve-DataDir([string]$AppDir = '') {
    # Kandidaten (USB-Stick neben dem Programm, Übergabepfad -DatenDir) mit automatischem Fallback
    $cands = @()
    if ($AppDir) { $cands += (Join-Path $AppDir 'Minibench-Daten'); $cands += $AppDir }
    if ($DatenDir) { $cands += $DatenDir.TrimEnd('\') }
    if ($env:LEOSMINIBENCH_EXE) {
        try {
            $exeDir = Split-Path $env:LEOSMINIBENCH_EXE -Parent
            if ($exeDir) { $cands += (Join-Path $exeDir 'Minibench-Daten') }
        } catch { }
    }
    if ($PSScriptRoot -and $PSScriptRoot -notlike "$env:TEMP*" -and $PSScriptRoot -notlike "*\tests*") { $cands += (Join-Path $PSScriptRoot 'Minibench-Daten') }
    foreach ($c in $cands) {
        # frühere Versionen: Ordner PC-Diagnose-Daten daneben übernehmen
        $old = Join-Path (Split-Path $c -Parent) 'PC-Diagnose-Daten'
        if (-not (Test-Path -LiteralPath $c) -and (Test-Path -LiteralPath $old)) { try { Rename-Item -LiteralPath $old -NewName (Split-Path $c -Leaf) -ErrorAction Stop } catch { } }
        if (Test-WritableDir $c) { return $c }
    }
    # Notlösung bei schreibgeschütztem Speicherort (z. B. gesperrter USB-Stick): Dokumente des Benutzers
    $doc = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Leos Minibench'
    if (Test-WritableDir $doc) { $script:DataDirFallback = $true; return $doc }
    return ''
}

function Test-IsNetworkPath([string]$Path) {
    if (-not $Path) { return $false }
    if ($Path.StartsWith('\\')) { return $true }
    try {
        $root = [System.IO.Path]::GetPathRoot($Path)
        if ($root) {
            $di = New-Object System.IO.DriveInfo($root)
            return ($di.DriveType -eq [System.IO.DriveType]::Network)
        }
    } catch { }
    return $false
}

$script:DataDirFallback = $false
$script:DataDir      = Resolve-DataDir
# Cache, Tools und Laufzeit liegen im selben (lokalen) Datenordner; LocalDataDir bleibt als Name für ältere Stellen erhalten
$script:LocalDataDir = $script:DataDir
$script:ReportDir    = $(if ($script:DataDir) { Join-Path $script:DataDir 'Berichte' } else { Join-Path $env:TEMP 'LeosMinibench-Berichte' })
$script:DbDir        = $(if ($script:DataDir) { Join-Path $script:DataDir 'Datenbank' } else { '' })
$script:ToolsDir     = $(if ($script:LocalDataDir) { Join-Path $script:LocalDataDir 'Tools' } else { Join-Path ([System.IO.Path]::GetTempPath()) 'LeosMinibench\Tools' })
$script:CacheDir     = $(if ($script:LocalDataDir) { Join-Path $script:LocalDataDir 'Cache' } else { Join-Path ([System.IO.Path]::GetTempPath()) 'LeosMinibench\Cache' })
$script:CpDir        = $(if ($script:LocalDataDir) { Join-Path (Join-Path $script:LocalDataDir 'Laufzeit') $env:COMPUTERNAME } else { Join-Path $env:TEMP ('LeosMinibench_' + $env:COMPUTERNAME) })

function Initialize-DbDir {
    if (-not $script:DbDir) { return }
    $isNew = -not (Test-Path -LiteralPath $script:DbDir)
    if ($isNew) {
        try { New-Item -ItemType Directory -Path $script:DbDir -Force -ErrorAction Stop | Out-Null } catch { return }
    }
    $existing = @(Get-ChildItem -LiteralPath $script:DbDir -Filter '*.json' -File -ErrorAction SilentlyContinue)
    if ($existing.Count -eq 0) {
        if ($script:EmbeddedReferences) {
            foreach ($k in $script:EmbeddedReferences.Keys) {
                try {
                    $target = Join-Path $script:DbDir $k
                    [IO.File]::WriteAllText($target, $script:EmbeddedReferences[$k], (New-Object Text.UTF8Encoding($false)))
                } catch { }
            }
        }
        $existing = @(Get-ChildItem -LiteralPath $script:DbDir -Filter '*.json' -File -ErrorAction SilentlyContinue)
        if ($existing.Count -eq 0) {
            $refDirs = @(
                (Join-Path $PSScriptRoot 'Daten\Referenzen'),
                (Join-Path $PSScriptRoot 'src\Daten\Referenzen'),
                (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Daten\Referenzen')
            )
            foreach ($rd in $refDirs) {
                if (Test-Path -LiteralPath $rd) {
                    $refFiles = @(Get-ChildItem -LiteralPath $rd -Filter '*.json' -File -ErrorAction SilentlyContinue)
                    if ($refFiles.Count -gt 0) {
                        foreach ($rf in $refFiles) {
                            try { Copy-Item -LiteralPath $rf.FullName -Destination (Join-Path $script:DbDir $rf.Name) -Force -ErrorAction SilentlyContinue } catch { }
                        }
                        break
                    }
                }
            }
        }
    }
}
if ($script:DbDir) { Initialize-DbDir }

# C#-Code einmal kompilieren und als DLL im Datenordner zwischenspeichern (spart bei jedem Start einige Sekunden).
# Ab v2.6: Liegt die DLL zum Hash schon vor, wird sie ohne Schreibprobe direkt geladen (kein Schreibzugriff auf den Stick).
$script:CacheInfo = New-Object System.Collections.Generic.List[string]
function Add-CachedType([string]$Name, [string]$Code, [string[]]$References = @()) {
    $refList = [System.Collections.Generic.List[string]]::new()
    if ($References) {
        foreach ($r in $References) { if ($r -and -not $refList.Contains($r)) { $refList.Add($r) } }
    }
    if ($PSVersionTable.PSEdition -ne 'Desktop') {
        # PowerShell 7+ (.NET Core / Roslyn): Wird ReferencedAssemblies verwendet, zieht Roslyn nicht
        # automatisch den Standard-Referenzsatz heran. Alle Referenz- und Windows-Desktop-Bibliotheken ergänzen.
        $refDir = Join-Path $PSHOME 'ref'
        if (Test-Path -LiteralPath $refDir) {
            foreach ($f in (Get-ChildItem -LiteralPath $refDir -Filter '*.dll' -ErrorAction SilentlyContinue)) {
                if (-not $refList.Contains($f.FullName)) { $refList.Add($f.FullName) }
            }
        }
        $desktopDlls = @(
            'System.Windows.Forms.dll',
            'System.Windows.Forms.Primitives.dll',
            'System.Drawing.dll',
            'System.Drawing.Primitives.dll',
            'System.Drawing.Common.dll',
            'System.Private.Windows.Core.dll',
            'System.Private.Windows.GdiPlus.dll'
        )
        foreach ($dllName in $desktopDlls) {
            $fullPath = Join-Path $PSHOME $dllName
            if ((Test-Path -LiteralPath $fullPath) -and -not $refList.Contains($fullPath)) {
                $refList.Add($fullPath)
            }
        }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Code + ($refList -join ';') + $PSVersionTable.CLRVersion)) | Select-Object -First 6 | ForEach-Object { $_.ToString('x2') })
    # IgnoreWarnings: Windows PowerShell 5.1 wertet Compilerwarnungen sonst als Fehler (eine Warnung genügt, und alle Routinen fehlen)
    $p = @{ TypeDefinition = $Code; ErrorAction = 'Stop'; IgnoreWarnings = $true }
    if ($refList.Count) { $p.ReferencedAssemblies = $refList.ToArray() }
    if ($script:CacheDir) {
        $dll = Join-Path $script:CacheDir ('{0}-{1}.dll' -f $Name, $hash)
        if (Test-Path -LiteralPath $dll) {
            try { Add-Type -Path $dll -ErrorAction Stop; $script:CacheInfo.Add(('{0} aus dem Cache' -f $Name)); return } catch { }
        }
        if (Test-WritableDir $script:CacheDir) {
            Get-ChildItem -LiteralPath $script:CacheDir -Filter ('{0}-*.dll' -f $Name) -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            try { Add-Type @p -OutputAssembly $dll -OutputType Library } catch { Remove-Item $dll -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $dll) { try { Add-Type -Path $dll -ErrorAction Stop; $script:CacheInfo.Add(('{0} übersetzt und zwischengespeichert' -f $Name)); return } catch { } }
        }
    }
    Add-Type @p
    $script:CacheInfo.Add(('{0} übersetzt (ohne Cache)' -f $Name))
}

# ---------- Lokaler Arbeitsordner (ab v2.6) ----------
# Rohdaten, Konsolenprotokoll und Werkzeugausgaben sammeln sich während des Laufs im lokalen TEMP
# (%TEMP%\LeosMinibench\Lauf_<PID>) und gehen am Laufende gebündelt als Anhang.zip in den Berichtsordner.
# Ziel.txt nennt den Berichtsordner: Bricht ein Lauf ab, sichert der nächste Start die Rohdaten dorthin.
function New-RunWorkDir([string]$Target) {
    try {
        $d = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'LeosMinibench') ('Lauf_{0}' -f $PID)
        New-Item -ItemType Directory -Path (Join-Path $d 'Anhang') -Force -ErrorAction Stop | Out-Null
        [IO.File]::WriteAllText((Join-Path $d 'Ziel.txt'), [string]$Target, (New-Object Text.UTF8Encoding($false)))
        return $d
    } catch { return '' }
}

# Arbeitsordner abgebrochener Läufe (Prozess läuft nicht mehr): Rohdaten als Anhang_unterbrochen.zip in den
# Berichtsordner des abgebrochenen Laufs, danach löschen. Fehlt dieser Ordner (z. B. Stick nach dem Absturz unter
# anderem Laufwerksbuchstaben), geht das ZIP in den Berichtsordner dieses Laufs ($Fallback). Gelöscht wird nur, was
# gesichert ist oder keine Rohdaten enthält. Rückgabe: Texte für die Rückstandskontrolle.
function Restore-StaleWorkDirs([string]$Fallback = '') {
    $out = New-Object System.Collections.Generic.List[string]
    $base = Join-Path ([IO.Path]::GetTempPath()) 'LeosMinibench'
    if (-not (Test-Path -LiteralPath $base)) { return $out.ToArray() }
    foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory -Filter 'Lauf_*' -ErrorAction SilentlyContinue)) {
        $id = 0
        if (-not [int]::TryParse($d.Name.Substring(5), [ref]$id) -or $id -eq $PID) { continue }
        $alive = $false
        try { $pr = Get-Process -Id $id -ErrorAction Stop; $alive = ($pr.ProcessName -match 'powershell|pwsh') } catch { }
        if ($alive) { continue }
        $msg = ''; $safe = $true
        try {
            $zf = Join-Path $d.FullName 'Ziel.txt'
            $tgt = $(if (Test-Path -LiteralPath $zf) { ([IO.File]::ReadAllText($zf)).Trim() } else { '' })
            $raw = Join-Path $d.FullName 'Anhang'
            if ((Test-Path -LiteralPath $raw) -and @(Get-ChildItem -LiteralPath $raw -Force -ErrorAction SilentlyContinue).Count) {
                $safe = $false
                $dest = $(if ($tgt -and (Test-Path -LiteralPath $tgt)) { $tgt } elseif ($Fallback -and (Test-Path -LiteralPath $Fallback)) { $Fallback } else { '' })
                if ($dest) {
                    $zip = Join-Path $dest $(if ($dest -eq $tgt) { 'Anhang_unterbrochen.zip' } else { 'Anhang_unterbrochen_{0}.zip' -f $id })
                    if (Test-Path -LiteralPath $zip) { $safe = $true }
                    else {
                        Compress-Archive -Path (Join-Path $raw '*') -DestinationPath $zip -Force -ErrorAction Stop
                        $safe = (Test-Path -LiteralPath $zip)
                        $msg = ('Rohdaten eines abgebrochenen Laufs gesichert nach {0}{1}' -f $zip, $(if ($dest -ne $tgt) { ' (ursprünglicher Berichtsordner {0} nicht erreichbar)' -f $tgt } else { '' }))
                    }
                } else { $msg = 'kein Berichtsordner erreichbar' }
            }
        } catch { $safe = $false; $msg = ('Sichern fehlgeschlagen: {0}' -f $_.Exception.Message) }
        if (-not $safe) { $out.Add(('Arbeitsordner eines abgebrochenen Laufs behalten, weil seine Rohdaten nicht gesichert sind (nicht entfernbar ohne Datenverlust): {0} ({1})' -f $d.FullName, $msg)); continue }
        try { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop; $out.Add(('Arbeitsordner eines abgebrochenen Laufs entfernt: {0}{1}' -f $d.FullName, $(if ($msg) { ' (' + $msg + ')' } else { '' }))) }
        catch { $out.Add(('Arbeitsordner eines abgebrochenen Laufs nicht entfernbar: {0} ({1})' -f $d.FullName, $_.Exception.Message)) }
    }
    return $out.ToArray()
}

# Schreibzugriffe auf das Laufwerk eines Pfads (Windows-Leistungszähler, Rohwerte = Summe seit dem Systemstart).
# Gezählt wird alles, was auf dieses Laufwerk schreibt; auf einem USB-Stick ist das praktisch nur Leos Minibench.
function Get-VolumeWriteCounter([string]$Path) {
    try {
        $root = [IO.Path]::GetPathRoot($Path)
        if ($root -notmatch '^([A-Za-z]):') { return $null }
        $name = $Matches[1].ToUpperInvariant() + ':'
        $c = Get-CimInstance Win32_PerfRawData_PerfDisk_LogicalDisk -Filter ("Name='{0}'" -f $name) -ErrorAction Stop | Select-Object -First 1
        if (-not $c) { return $null }
        $art = ''; try { $art = [string](New-Object IO.DriveInfo($root)).DriveType } catch { }
        return [pscustomobject]@{ Laufwerk = $name; Vorgaenge = [double]$c.DiskWritesPersec; Bytes = [double]$c.DiskWriteBytesPersec; Art = $art; Zeit = (Get-Date) }
    } catch { return $null }
}

# Unterschied zweier Zählerstände (32-Bit-Zähler der Vorgänge laufen bei 2^32 über)
function Get-WriteDelta($Before, $After) {
    if (-not $Before -or -not $After -or $Before.Laufwerk -ne $After.Laufwerk) { return $null }
    $ops = [double]$After.Vorgaenge - [double]$Before.Vorgaenge; if ($ops -lt 0) { $ops += 4294967296 }
    $by = [double]$After.Bytes - [double]$Before.Bytes; if ($by -lt 0) { $by = 0 }
    $art = switch ([string]$After.Art) { 'Removable' { 'Wechseldatenträger (USB-Stick)' } 'Fixed' { 'fest eingebautes Laufwerk' } 'Network' { 'Netzlaufwerk' } default { [string]$After.Art } }
    return [pscustomobject]@{ Laufwerk = $After.Laufwerk; Art = $art; Vorgaenge = [long]$ops; MB = [math]::Round($by / 1MB, 1); Sekunden = [math]::Round(($After.Zeit - $Before.Zeit).TotalSeconds) }
}
#endregion


