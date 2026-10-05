#region ---------- Änderungsprotokoll mit Rückgängig ----------
# Jede Änderung der Stufe Ändern speichert vor dem Schreiben den Vorher-Wert und das Wissen, wie sie umzukehren ist.
# Ablage je Lauf: Minibench-Daten\Änderungen\<PC>\<Datum>.json, gesicherte Dateien (z. B. Energiepläne) im gleichnamigen Ordner.
# Die Datei wird nach jedem Eintrag sofort geschrieben, damit sie auch einen Absturz mitten im Lauf übersteht.
# Eingriffe ohne automatisches Rückgängig erscheinen ebenfalls, mit dem Weg zurück als Hinweis (z. B. Wiederherstellungspunkt).
#
# Status eines Eintrags: aktiv (rückgängig machbar), rückgängig, übersprungen (Wert inzwischen anders), fehlgeschlagen, nur Hinweis
$script:ChangeFormat = 'Minibench-Aenderungen/1'
$script:ChangeFile   = ''
$script:ChangeLog    = $null
$script:ChangeCount  = 0

function Get-ChangeRoot { if ($script:DataDir) { return (Join-Path $script:DataDir 'Änderungen') } else { return '' } }

function Save-ChangeFile([string]$Path, $Log) {
    $dir = Split-Path $Path -Parent
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    $tmp = $Path + '.tmp'
    [IO.File]::WriteAllText($tmp, ($Log | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::Copy($tmp, $Path, $true)
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

function Read-ChangeFile([string]$Path) {
    try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    if (-not $j -or [string]$j.Format -ne $script:ChangeFormat) { return $null }
    return $j
}

# Lauf beginnen: Die Datei entsteht erst mit dem ersten Eintrag, Läufe ohne Änderungen hinterlassen nichts
function Start-ChangeLog {
    $root = Get-ChangeRoot
    if (-not $root) { $script:ChangeFile = ''; return }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:ChangeFile = Join-Path (Join-Path $root (Get-SafeName $env:COMPUTERNAME)) ($stamp + '.json')
    $dev = Get-DeviceIdentity
    $script:ChangeLog = [ordered]@{
        Format = $script:ChangeFormat; Computer = $env:COMPUTERNAME; GeraetId = $dev.Id; Version = $ScriptVersion
        Lauf = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture); Bericht = [string]$OutputDir; Eintraege = @()
    }
    $script:ChangeCount = 0
}

# Ordner für Sicherungsdateien dieses Laufs (gleicher Name wie die Protokolldatei ohne .json)
function Get-ChangeFilesDir { if ($script:ChangeFile) { return ($script:ChangeFile -replace '\.json$', '') } else { return '' } }

function Add-ChangeRecord {
    param(
        [string]$Modul, [string]$Schritt, [string]$Titel, [string]$Risiko, [string]$Art, [string]$Ziel,
        [string]$Vorher = '', [string]$Nachher = '', $Daten = $null, [string]$Gegenbefehl = '', [switch]$NurHinweis
    )
    if (-not $script:ChangeLog) { Start-ChangeLog }
    if (-not $script:ChangeFile) { return $null }
    $script:ChangeCount++
    $r = [ordered]@{
        Id = $script:ChangeCount; Zeit = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
        Modul = $Modul; Schritt = $Schritt; Titel = $Titel; Risiko = $Risiko; Art = $Art; Ziel = $Ziel; Vorher = $Vorher; Nachher = $Nachher
        Daten = $Daten; Gegenbefehl = $Gegenbefehl; Status = $(if ($NurHinweis) { 'nur Hinweis' } else { 'aktiv' }); Ergebnis = ''
    }
    $script:ChangeLog.Eintraege = @(@($script:ChangeLog.Eintraege) + [pscustomobject]$r)
    try { Save-ChangeFile $script:ChangeFile $script:ChangeLog } catch { Write-Warning ('Änderungsprotokoll konnte nicht geschrieben werden: {0}' -f $_.Exception.Message) }
    return [pscustomobject]$r
}

# ---------- Zugriffe auf das System (einzeln, damit Tests sie ersetzen können) ----------
# Name '(default)' meint den Standardwert eines Schlüssels (ab v2.8, Kontextmenüs des Moduls Optimierung)
function Get-RegValueState([string]$Path, [string]$Name) {
    $none = [pscustomobject]@{ Vorhanden = $false; Wert = $null; Typ = '' }
    try { $k = Get-Item -LiteralPath $Path -ErrorAction Stop } catch { return $none }
    $n = $(if ($Name -eq '(default)') { '' } else { $Name })
    if (@($k.GetValueNames()) -notcontains $n) { return $none }
    return [pscustomobject]@{ Vorhanden = $true; Wert = $k.GetValue($n, $null, 'DoNotExpandEnvironmentNames'); Typ = [string]$k.GetValueKind($n) }
}

# Wert in den Registry-Typ wandeln. Felder mit Komma zurückgeben, sonst zerlegt PowerShell sie in Einzelwerte.
function ConvertTo-RegValue($Value, [string]$Type) {
    switch ($Type) {
        'DWord'       { return [int]$Value }
        'QWord'       { return [long]$Value }
        'Binary'      { return , ([byte[]]@($Value)) }
        'MultiString' { return , ([string[]]@($Value)) }
        default       { return [string]$Value }
    }
}

function Set-RegValueState([string]$Path, [string]$Name, $Value, [string]$Type) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    Set-ItemProperty -LiteralPath $Path -Name $Name -Value (ConvertTo-RegValue $Value $Type) -Type $Type -ErrorAction Stop
}

function Remove-RegValue([string]$Path, [string]$Name) { Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop }

function Get-ServiceStartType([string]$Name) { $s = Get-Service -Name $Name -ErrorAction Stop; return [string]$s.StartType }
function Set-ServiceStartType([string]$Name, [string]$StartType) { Set-Service -Name $Name -StartupType $StartType -ErrorAction Stop }

function Invoke-PowerCfg([string]$Arguments) { return (Invoke-External -File 'powercfg.exe' -Arguments $Arguments -TimeoutSec 60) }

# Energiepläne aus powercfg /list: GUID, Name, aktiv
function Get-PowerSchemes {
    $r = Invoke-PowerCfg '/list'
    return @(ConvertFrom-PowerCfgList $r.Output)
}
function ConvertFrom-PowerCfgList([string]$Text) {
    foreach ($ln in @($Text -split "`r?`n")) {
        if ($ln -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\(([^)]*)\)\s*(\*)?') {
            [pscustomobject]@{ Guid = $Matches[1].ToLowerInvariant(); Name = $Matches[2].Trim(); Aktiv = [bool]$Matches[3] }
        }
    }
}

# Werte vergleichbar und lesbar machen (Zahlen, Text, Listen)
function Get-ValueText($Value) {
    if ($null -eq $Value) { return '(nicht vorhanden)' }
    if ($Value -is [array] -or $Value -is [System.Collections.IList]) { return ((@($Value) | ForEach-Object { [string]$_ }) -join ',') }
    return [string]$Value
}

# ---------- Protokollierte Änderungen ----------
# Registry-Wert setzen. Rückgabe: Eintrag des Protokolls, $null wenn der Wert schon stimmte. Fehler beim Schreiben werfen.
function Set-RegistryValueLogged {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord', [string]$Modul, [string]$Schritt, [string]$Titel)
    $before = Get-RegValueState $Path $Name
    if ($before.Vorhanden -and $before.Typ -eq $Type -and (Get-ValueText $before.Wert) -eq (Get-ValueText (ConvertTo-RegValue $Value $Type))) { return $null }
    Set-RegValueState $Path $Name $Value $Type
    $daten = [ordered]@{ Pfad = $Path; Name = $Name; VorherVorhanden = [bool]$before.Vorhanden; VorherWert = $before.Wert; VorherTyp = $before.Typ; NachherWert = (ConvertTo-RegValue $Value $Type); NachherTyp = $Type }
    $gegen = $(if ($before.Vorhanden) { 'Set-ItemProperty -LiteralPath ''{0}'' -Name {1} -Value {2} -Type {3}' -f $Path, $Name, (Get-ValueText $before.Wert), $before.Typ } else { 'Remove-ItemProperty -LiteralPath ''{0}'' -Name {1}' -f $Path, $Name })
    return (Add-ChangeRecord -Modul $Modul -Schritt $Schritt -Titel $Titel -Risiko 'Aendern' -Art 'Registry' -Ziel ('{0}\{1}' -f $Path, $Name) `
        -Vorher (Get-ValueText $before.Wert) -Nachher (Get-ValueText $Value) -Daten $daten -Gegenbefehl $gegen)
}

function Set-ServiceStartTypeLogged {
    param([string]$Name, [string]$StartType, [string]$Modul, [string]$Schritt, [string]$Titel)
    $before = Get-ServiceStartType $Name
    if ($before -eq $StartType) { return $null }
    Set-ServiceStartType $Name $StartType
    return (Add-ChangeRecord -Modul $Modul -Schritt $Schritt -Titel $Titel -Risiko 'Aendern' -Art 'Dienststart' -Ziel ('Dienst {0}, Starttyp' -f $Name) `
        -Vorher $before -Nachher $StartType -Daten ([ordered]@{ Dienst = $Name; Vorher = $before; Nachher = $StartType }) -Gegenbefehl ('Set-Service {0} -StartupType {1}' -f $Name, $before))
}

# Alle Energiepläne sichern, bevor sie zurückgesetzt werden. Rückgängig stellt fehlende eigene Pläne und den aktiven Plan wieder her.
function Backup-PowerSchemesLogged {
    param([string]$Modul, [string]$Schritt, [string]$Titel)
    if (-not $script:ChangeLog) { Start-ChangeLog }
    $dir = Get-ChangeFilesDir
    if (-not $dir) { throw 'Kein Datenordner für die Sicherung der Energiepläne.' }
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    $schemes = @(Get-PowerSchemes)
    if (-not $schemes.Count) { throw 'powercfg /list lieferte keine Energiepläne.' }
    $saved = @()
    foreach ($s in $schemes) {
        $f = Join-Path $dir ('Energieplan_{0}.pow' -f $s.Guid)
        $r = Invoke-PowerCfg ('/export "{0}" {1}' -f $f, $s.Guid)
        if ($r.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $f)) { throw ('Energieplan {0} ließ sich nicht sichern (powercfg {1}).' -f $s.Name, $r.ExitCode) }
        $saved += [ordered]@{ Guid = $s.Guid; Name = $s.Name; Datei = (Split-Path $f -Leaf) }
    }
    $active = @($schemes | Where-Object Aktiv | Select-Object -First 1)
    $activeGuid = $(if ($active.Count) { $active[0].Guid } else { '' })
    $activeName = $(if ($active.Count) { $active[0].Name } else { '' })
    return (Add-ChangeRecord -Modul $Modul -Schritt $Schritt -Titel $Titel -Risiko 'Aendern' -Art 'Energieplaene' -Ziel 'Energiesparpläne' `
        -Vorher ('{0} Pläne, aktiv: {1}' -f $saved.Count, $activeName) -Nachher 'Windows-Standardpläne' `
        -Daten ([ordered]@{ AktivVorher = $activeGuid; Sicherungen = $saved }) -Gegenbefehl ('powercfg /import <Datei> <GUID>, danach powercfg /setactive {0}' -f $activeGuid))
}

# Eine Änderung dieses Laufs sofort zurücknehmen (vorübergehende Einstellung für eine Messung). Rückgabe: Status und Text.
function Undo-ChangeNow($Record) {
    if (-not $Record -or -not $script:ChangeLog) { return $null }
    $e = @($script:ChangeLog.Eintraege | Where-Object { [int]$_.Id -eq [int]$Record.Id }) | Select-Object -First 1
    if (-not $e) { return $null }
    try { $res = Undo-ChangeRecord $e (Get-ChangeFilesDir) } catch { $res = [pscustomobject]@{ Status = 'fehlgeschlagen'; Text = $_.Exception.Message } }
    $e.Status = $res.Status
    $e.Ergebnis = ('{0}: {1} (direkt nach der Messung)' -f (Get-Date).ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture), $res.Text)
    try { Save-ChangeFile $script:ChangeFile $script:ChangeLog } catch { }
    return $res
}

# ---------- Rückgängig ----------
# Einen Eintrag umkehren. Rückgabe: Status und Text. Ändert den Eintrag nicht selbst (das macht Invoke-ChangeUndo).
function Undo-ChangeRecord($Record, [string]$FilesDir) {
    $d = $Record.Daten
    switch ([string]$Record.Art) {
        'Registry' {
            $now = Get-RegValueState $d.Pfad $d.Name
            if (-not $now.Vorhanden -or (Get-ValueText $now.Wert) -ne (Get-ValueText $d.NachherWert)) {
                return [pscustomobject]@{ Status = 'übersprungen'; Text = ('Wert ist inzwischen {0}, nicht {1}; nichts verändert.' -f (Get-ValueText $now.Wert), (Get-ValueText $d.NachherWert)) }
            }
            if ($d.VorherVorhanden) { Set-RegValueState $d.Pfad $d.Name $d.VorherWert $d.VorherTyp; return [pscustomobject]@{ Status = 'rückgängig'; Text = ('{0} wieder auf {1}' -f $d.Name, (Get-ValueText $d.VorherWert)) } }
            Remove-RegValue $d.Pfad $d.Name
            return [pscustomobject]@{ Status = 'rückgängig'; Text = ('{0} entfernt (war vorher nicht vorhanden)' -f $d.Name) }
        }
        'Dienststart' {
            $now = Get-ServiceStartType $d.Dienst
            if ($now -ne [string]$d.Nachher) { return [pscustomobject]@{ Status = 'übersprungen'; Text = ('Starttyp ist inzwischen {0}, nicht {1}; nichts verändert.' -f $now, $d.Nachher) } }
            Set-ServiceStartType $d.Dienst ([string]$d.Vorher)
            return [pscustomobject]@{ Status = 'rückgängig'; Text = ('Starttyp von {0} wieder {1}' -f $d.Dienst, $d.Vorher) }
        }
        'Energieplaene' {
            $present = @(Get-PowerSchemes | ForEach-Object { $_.Guid })
            $msgs = @(); $bad = 0
            foreach ($s in @($d.Sicherungen)) {
                if ($present -contains [string]$s.Guid) { continue }
                $f = Join-Path $FilesDir ([string]$s.Datei)
                if (-not (Test-Path -LiteralPath $f)) { $msgs += ('Sicherung von {0} fehlt' -f $s.Name); $bad++; continue }
                $r = Invoke-PowerCfg ('/import "{0}" {1}' -f $f, $s.Guid)
                if ($r.ExitCode -eq 0) { $msgs += ('{0} wiederhergestellt' -f $s.Name) } else { $msgs += ('{0} nicht importierbar (Code {1})' -f $s.Name, $r.ExitCode); $bad++ }
            }
            if ($d.AktivVorher) {
                $r = Invoke-PowerCfg ('/setactive {0}' -f $d.AktivVorher)
                if ($r.ExitCode -eq 0) { $msgs += 'vorher aktiver Plan wieder aktiv' } else { $msgs += ('aktiver Plan nicht setzbar (Code {0})' -f $r.ExitCode); $bad++ }
            }
            $msgs += 'Einstellungen der Windows-Standardpläne bleiben auf Standard'
            return [pscustomobject]@{ Status = $(if ($bad) { 'fehlgeschlagen' } else { 'rückgängig' }); Text = ($msgs -join '; ') }
        }
    }
    # ab v2.8: Arten des Moduls Optimierung (geplante Aufgaben, Windows-Funktionen, Laufwerke, Energie, Defender, DNS ...)
    if (Get-Command Undo-OptChange -ErrorAction SilentlyContinue) { $r = Undo-OptChange $Record; if ($r) { return $r } }
    return [pscustomobject]@{ Status = [string]$Record.Status; Text = ('Für {0} gibt es kein automatisches Rückgängig: {1}' -f $Record.Art, $Record.Gegenbefehl) }
}

# Wiederherstellungspunkt anlegen und als Hinweis ins Änderungsprotokoll schreiben (ab v2.8 auch für das Modul Optimierung).
# Windows erlaubt sonst nur einen Punkt je 24 Stunden; die Häufigkeitssperre wird dafür kurz aufgehoben.
function New-RestorePointLogged([string]$Modul, [string]$Beschreibung) {
    $rk = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $old = $null; try { $old = (Get-ItemProperty $rk -Name SystemRestorePointCreationFrequency -ErrorAction Stop).SystemRestorePointCreationFrequency } catch { }
    try {
        try { Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop } catch { }
        if (-not (Test-Path $rk)) { New-Item -Path $rk -Force | Out-Null }
        Set-ItemProperty -Path $rk -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Beschreibung -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        $rp = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber -Descending | Select-Object -First 1
        $no = $(if ($rp) { [string]$rp.SequenceNumber } else { '' })
        $txt = $(if ($rp) { 'angelegt: {0} (Nr. {1})' -f $rp.Description, $rp.SequenceNumber } else { 'angelegt' })
        [void](Add-ChangeRecord -Modul $Modul -Schritt 'Wiederherstellungspunkt' -Titel ('Wiederherstellungspunkt vor dem Modul {0}' -f $Modul) -Risiko 'Lesen' -Art 'Wiederherstellungspunkt' `
            -Ziel 'Computerschutz' -Nachher $txt -Daten ([ordered]@{ Nummer = $no }) -Gegenbefehl ('rstrui.exe starten und Punkt Nr. {0} wählen; macht die Eingriffe dieses Laufs rückgängig' -f $no) -NurHinweis)
        return [pscustomobject]@{ Ok = $true; Text = $txt; Nummer = $no }
    } catch {
        return [pscustomobject]@{ Ok = $false; Text = $_.Exception.Message; Nummer = '' }
    } finally {
        if ($null -ne $old) { Set-ItemProperty -Path $rk -Name SystemRestorePointCreationFrequency -Value $old -Type DWord -ErrorAction SilentlyContinue }
        else { Remove-ItemProperty -Path $rk -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
    }
}

# Vorübergehende Änderungen, die nur für eine Messung gelten (GPU-Wahl für winsat.exe). Bricht ein Lauf dazwischen ab
# (Absturz, Abbruch in der Oberfläche), nimmt der nächste Start sie zurück.
$script:TemporarySteps = @('GpuWahl')
function Restore-TemporaryChanges {
    $root = Get-ChangeRoot
    if (-not $root) { return $null }
    $dir = Join-Path $root (Get-SafeName $env:COMPUTERNAME)
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $spec = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
        if ($script:ChangeFile -and $f.FullName -eq $script:ChangeFile) { continue }
        $j = Read-ChangeFile $f.FullName
        if (-not $j) { continue }
        foreach ($e in @($j.Eintraege)) { if ([string]$e.Status -eq 'aktiv' -and $script:TemporarySteps -contains [string]$e.Schritt) { $spec += ('{0}*{1}' -f $f.FullName, [int]$e.Id) } }
    }
    if (-not $spec.Count) { return $null }
    return (Invoke-ChangeUndo ($spec -join ';'))
}

# Alle Einträge aller Läufe, neueste zuerst (für die Oberfläche und Tests)
function Get-ChangeEntries([string]$Root = (Get-ChangeRoot)) {
    $list = New-Object System.Collections.Generic.List[object]
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
        $j = Read-ChangeFile $f.FullName
        if (-not $j) { continue }
        foreach ($e in @($j.Eintraege)) {
            $list.Add([pscustomobject]@{ Datei = $f.FullName; Computer = [string]$j.Computer; GeraetId = [string]$j.GeraetId; Lauf = [string]$j.Lauf
                Id = [int]$e.Id; Zeit = [string]$e.Zeit; Modul = [string]$e.Modul; Titel = [string]$e.Titel; Risiko = [string]$e.Risiko; Art = [string]$e.Art
                Ziel = [string]$e.Ziel; Vorher = [string]$e.Vorher; Nachher = [string]$e.Nachher; Status = [string]$e.Status; Ergebnis = [string]$e.Ergebnis })
        }
    }
    return @($list | Sort-Object Zeit, Id -Descending)
}

# Rückgängig für eine Auswahl: "Datei*Id;Datei*Id". Nur auf dem Gerät, auf dem die Änderung gemacht wurde.
function Invoke-ChangeUndo([string]$Spec) {
    $byFile = [ordered]@{}
    foreach ($part in @(([string]$Spec) -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })) {
        $p = $part -split '\*', 2
        if ($p.Count -ne 2 -or -not ($p[1] -as [int])) { Write-Host ('Ungültige Auswahl: {0}' -f $part); continue }
        if (-not $byFile.Contains($p[0])) { $byFile[$p[0]] = New-Object System.Collections.Generic.List[int] }
        $byFile[$p[0]].Add([int]$p[1])
    }
    $dev = Get-DeviceIdentity
    $done = 0; $fail = 0
    foreach ($file in $byFile.Keys) {
        $root = Get-ChangeRoot
        if (-not $root -or -not ([IO.Path]::GetFullPath($file)).StartsWith([IO.Path]::GetFullPath($root), [StringComparison]::OrdinalIgnoreCase)) { Write-Host ('{0} liegt nicht im Änderungsprotokoll des Datenordners.' -f $file); $fail++; continue }
        $j = Read-ChangeFile $file
        if (-not $j) { Write-Host ('{0} ist kein lesbares Änderungsprotokoll.' -f $file); $fail++; continue }
        $same = $(if ([string]$j.GeraetId) { [string]$j.GeraetId -eq $dev.Id } else { [string]$j.Computer -eq $env:COMPUTERNAME })
        if (-not $same) { Write-Host ('{0}: Die Änderungen stammen von {1}, nicht von diesem Gerät. Rückgängig nur dort möglich.' -f (Split-Path $file -Leaf), $j.Computer); $fail++; continue }
        $filesDir = $file -replace '\.json$', ''
        # neueste zuerst, damit aufeinander aufbauende Änderungen in umgekehrter Reihenfolge zurückgenommen werden
        foreach ($e in @($j.Eintraege | Where-Object { $byFile[$file] -contains [int]$_.Id } | Sort-Object { [int]$_.Id } -Descending)) {
            if ([string]$e.Status -ne 'aktiv') { Write-Host ('{0}: Status {1}, nichts zu tun.' -f $e.Titel, $e.Status); continue }
            try { $res = Undo-ChangeRecord $e $filesDir } catch { $res = [pscustomobject]@{ Status = 'fehlgeschlagen'; Text = $_.Exception.Message } }
            $e.Status = $res.Status
            $e.Ergebnis = ('{0}: {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture), $res.Text)
            Write-Host ('{0} ({1}): {2}, {3}' -f $e.Titel, $e.Ziel, $res.Status, $res.Text)
            if ($res.Status -eq 'rückgängig') { $done++ } else { $fail++ }
        }
        try { Save-ChangeFile $file $j } catch { Write-Host ('Protokoll {0} konnte nicht aktualisiert werden: {1}' -f $file, $_.Exception.Message); $fail++ }
    }
    return [pscustomobject]@{ Rueckgaengig = $done; Probleme = $fail }
}
#endregion
