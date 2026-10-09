#region ---------- Ablage: Netzlaufwerk als Spiegel, Entfernen und Umbenennen von Läufen (ab v3.54) ----------
# Arbeitsort ist immer der Datenordner auf dem Stick (Kern\Datenordner.ps1). Ein Netzlaufwerk (NAS) ist ein Spiegel der
# Nutzerdaten: Berichte, Datenbank, Änderungen sowie Voreinstellungen.json und Referenz.json. Abgeglichen wird nur auf
# Knopfdruck (Aktualisieren auf der Seite Vergleichsdatenbank, Hilfsmodus -Abgleich), in beide Richtungen:
#   * Grundlage ist der Stand des letzten Abgleichs (Minibench-Daten\Abgleich\Stand.json, Größe und Zeit je Datei und Seite)
#   * neu oder geändert auf einer Seite: auf die andere kopieren
#   * auf einer Seite gelöscht (seit dem letzten Abgleich): auf der anderen ins Archiv verschieben
#   * auf beiden Seiten geändert: die neuere Fassung gilt, die ältere kommt ins Archiv (Archiv\Abgleich\<Zeit>\Konflikte)
#   * Änderung schlägt Löschung: wurde eine Datei auf einer Seite gelöscht und auf der anderen geändert, bleibt sie
# Nie abgeglichen werden Tools, Cache, Laufzeit, Archiv, Netzwerk.json, Einstellungen.json, Geraete.json und Berichte\Dashboard.html.
# Der Ordner eines laufenden Laufs (laufend.json) bleibt außen vor. Das NAS wird mit Zeitlimit geprüft, nie beim Start.
# Schutz vor Massenlöschung: Fehlt auf einer Seite ein ganzer Ordner oder ein großer Teil der zuletzt abgeglichenen Dateien
# (Freigabe nicht eingehängt, Ordner verschoben), hält der Abgleich an und ändert nichts, bis er ausdrücklich bestätigt wird.
# Lässt sich eine Seite nicht vollständig lesen, wird ebenfalls nichts geändert. Abgleich.lock auf dem NAS verhindert zwei
# gleichzeitige Abgleiche.
# Netzwerk.json liegt nur im Datenordner auf dem Stick: {"NasPfad": "\\\\server\\freigabe\\Ordner", "Benutzer": "..."};
# ein Kennwort wird nie gespeichert.

$script:AbgleichOrdner   = @('Berichte', 'Datenbank', 'Änderungen')
$script:AbgleichDateien  = @('Voreinstellungen.json', 'Referenz.json')
$script:AbgleichToleranz = 2.0          # Sekunden; FAT-Sticks speichern Zeiten auf 2 s genau
$script:AbgleichFormat   = 'Minibench-Abgleich/1'
$script:AbgleichSperreMin = 30          # Abgleich.lock älter als das gilt als verwaist

# Rel-Pfade stehen immer mit \ (Stand.json, Vergleiche); für Dateizugriffe in das Trennzeichen des Systems wandeln
function Join-AbgleichPfad([string]$Root, [string]$Rel) { return (Join-Path $Root ($Rel -replace '\\', [IO.Path]::DirectorySeparatorChar)) }

# ohne ' und & (Windows PowerShell 5.1 schreibt sie in JSON als ' und &), [ ] (Platzhalter) und ;
function Get-AblageName([string]$s) { return (([string]$s -replace '[\\/:*?"<>|;''&\[\]\s]+', '_').Trim('_', '.')) }

# NAS-Pfad vereinheitlichen: ohne abschließendes \, außer beim Stamm eines Laufwerks (Z:\)
function Format-NasPfad([string]$Pfad) {
    $p = ([string]$Pfad).Trim().TrimEnd('\')
    if ($p -match '^[A-Za-z]:$') { $p += '\' }
    return $p
}

# ---------- Netzwerk.json ----------
# Prüft einen NAS-Pfad. Rückgabe: leer, wenn gültig, sonst der Grund. Erlaubt sind UNC-Pfade (\\server\freigabe[\...])
# und Laufwerke, die Windows als Netzlaufwerk kennt. Ein Pfad mit nur einem führenden \ (\server\...) zeigt auf das
# Laufwerk, von dem das Programm läuft, also auf den Stick; das war die Ursache des Ordners TRUENAS auf dem Stick.
function Test-NasPfad([string]$Pfad) {
    $p = ([string]$Pfad).Trim()
    if (-not $p) { return 'kein Pfad angegeben' }
    if ($p -match '^\\\\[^\\/:*?"<>|]+\\[^\\/:*?"<>|]+(\\.*)?$') { return '' }
    if ($p -match '^\\[^\\]') { return ('{0} beginnt mit nur einem \ und zeigte damit auf den Stick; gemeint ist \{0}' -f $p) }
    if ($p -match '^[A-Za-z]:\\') {
        if (Test-IsNetworkPath $p) { return '' }
        return ('{0} ist kein Netzlaufwerk (lokales Laufwerk)' -f $p)
    }
    return ('{0} ist kein UNC-Pfad (\\server\freigabe\Ordner)' -f $p)
}

function Get-NasKonfig([string]$DataDir = $script:DataDir) {
    if (-not $DataDir) { return $null }
    $f = Join-Path $DataDir 'Netzwerk.json'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    $p = $(if ($j.NasPfad) { [string]$j.NasPfad } elseif ($j.NetzwerkPfad) { [string]$j.NetzwerkPfad } else { '' })
    $p = Format-NasPfad $p
    if (-not $p) { return $null }
    return [pscustomobject]@{ Pfad = $p; Benutzer = [string]$j.Benutzer; Datei = $f; Fehler = (Test-NasPfad $p) }
}

function Save-NasKonfig([string]$DataDir, [string]$Pfad, [string]$Benutzer = '') {
    $o = [ordered]@{ NasPfad = (Format-NasPfad $Pfad) }
    if ($Benutzer) { $o.Benutzer = $Benutzer.Trim() }
    New-Item -ItemType Directory -Path $DataDir -Force -ErrorAction Stop | Out-Null
    [IO.File]::WriteAllText((Join-Path $DataDir 'Netzwerk.json'), ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($true)))
}

# Bis 3.53 schrieb der NAS-Dialog Netzwerk.json zusätzlich nach Dokumente\Leos Minibench und %APPDATA%\LeosMinibench, auch
# auf fremden PCs. Diese Kopien werden nie übernommen (sonst gliche ein Stick ohne NAS mit dem NAS eines anderen ab). Beim
# Start entfernt: nur Kopien, die auf dasselbe Netzlaufwerk zeigen wie der Stick (eigene Reste); fremde bleiben unberührt.
function Get-AlteNasKonfigDateien {
    $alt = @()
    try { $d = [Environment]::GetFolderPath('MyDocuments'); if ($d) { $alt += (Join-Path (Join-Path $d 'Leos Minibench') 'Netzwerk.json') } } catch { }
    try { $d = [Environment]::GetFolderPath('ApplicationData'); if ($d) { $alt += (Join-Path (Join-Path $d 'LeosMinibench') 'Netzwerk.json') } } catch { }
    return $alt
}
function Move-AlteNasKonfig([string]$DataDir = $script:DataDir, [string[]]$AlteDateien = $null) {
    $res = New-Object System.Collections.Generic.List[string]
    if (-not $DataDir) { return $res }
    $eigen = Get-NasKonfig $DataDir
    if (-not $eigen) { return $res }
    $eigene = Join-Path $DataDir 'Netzwerk.json'
    $alt = $(if ($null -ne $AlteDateien) { $AlteDateien } else { Get-AlteNasKonfigDateien })
    foreach ($f in $alt) {
        if (-not $f -or -not (Test-Path -LiteralPath $f)) { continue }
        if ([IO.Path]::GetFullPath($f) -eq [IO.Path]::GetFullPath($eigene)) { continue }
        $k = Get-NasKonfig (Split-Path $f -Parent)
        if (-not $k -or $k.Pfad -ine $eigen.Pfad) { continue }
        try {
            Remove-Item -LiteralPath $f -Force -ErrorAction Stop
            $res.Add(('{0} entfernt (Rest einer früheren Version)' -f $f))
            $d = Split-Path $f -Parent
            if ((Split-Path $d -Leaf) -eq 'LeosMinibench' -and -not @(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $d -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    return $res
}

# Ist der Ordner auf dem NAS erreichbar? Mit Zeitlimit in einem eigenen Runspace, weil ein nicht erreichbarer Server
# Directory.Exists bis zu einer Minute blockieren kann. Mit -Anlegen wird ein fehlender Ordner auf einer vorhandenen
# Freigabe angelegt (nur beim ersten Abgleich; danach hieße ein fehlender Ordner, dass etwas nicht stimmt).
function Test-NasErreichbar([string]$Pfad, [int]$TimeoutMs = 6000, [switch]$Anlegen) {
    if (-not $Pfad) { return $false }
    $ps = [powershell]::Create()
    try {
        [void]$ps.AddScript({
            param($p, $neu)
            if ([IO.Directory]::Exists($p)) { return $true }
            if (-not $neu) { return $false }
            $parent = [IO.Path]::GetDirectoryName($p)
            if ($parent -and [IO.Directory]::Exists($parent)) { try { [void][IO.Directory]::CreateDirectory($p); return $true } catch { return $false } }
            return $false
        }).AddArgument($Pfad).AddArgument([bool]$Anlegen)
        $h = $ps.BeginInvoke()
        if (-not $h.AsyncWaitHandle.WaitOne($TimeoutMs)) { try { [void]$ps.BeginStop($null, $null) } catch { }; return $false }
        $r = @($ps.EndInvoke($h))
        return ($r.Count -gt 0 -and [bool]$r[-1])
    } catch { return $false }
    finally { if ($h -and $h.IsCompleted) { $ps.Dispose() } }
}

# ---------- Bestand und Plan ----------
# Ordner laufender Läufe (laufend.json im Laufzeitordner) relativ zum Datenordner, z. B. Berichte\PC1_20261009_1200
function Get-AbgleichBelegt([string]$DataDir) {
    $set = New-Object System.Collections.Generic.List[string]
    $lz = Join-Path $DataDir 'Laufzeit'
    foreach ($lf in @(Get-ChildItem -LiteralPath $lz -Filter 'laufend.json' -Recurse -File -ErrorAction SilentlyContinue)) {
        try { $j = Get-Content -LiteralPath $lf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if ($j -and $j.OutputDir) { $set.Add('Berichte\' + @(([string]$j.OutputDir).TrimEnd('\', '/') -split '[\\/]')[-1]) }
    }
    return @($set)
}

function Test-AbgleichAusnahme([string]$Rel, $Belegt) {
    $leaf = Split-Path $Rel -Leaf
    if ($leaf -like '*.tmp' -or $leaf -like '~abgleich_*' -or $leaf -like '.schreibtest_*') { return $true }
    if ($Rel -ieq 'Berichte\Dashboard.html') { return $true }
    foreach ($b in $Belegt) { if ($Rel.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}

# Alle abzugleichenden Dateien einer Seite: Rel -> @{ S = Größe; T = Zeit in UTC-Ticks }. Lässt sich ein Ordner nicht
# vollständig lesen (Zugriff verweigert, Pfad zu lang, Verbindung weg), bricht die Funktion ab: Fehlende Dateien würden
# sonst als gelöscht gelten.
function Get-AbgleichBestand([string]$Root, $Belegt = @()) {
    $d = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    foreach ($o in $script:AbgleichOrdner) {
        $dir = Join-Path $Root $o
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $ev = $null
        $liste = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable ev)
        if ($ev -and @($ev).Count) { throw ('{0} ist nicht vollständig lesbar: {1}' -f $dir, @($ev)[0].Exception.Message) }
        foreach ($f in $liste) {
            $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/') -replace '/', '\'
            if (Test-AbgleichAusnahme $rel $Belegt) { continue }
            $d[$rel] = [pscustomobject]@{ S = [int64]$f.Length; T = [int64]$f.LastWriteTimeUtc.Ticks }
        }
    }
    foreach ($n in $script:AbgleichDateien) {
        $f = Join-Path $Root $n
        if (Test-Path -LiteralPath $f -PathType Leaf) { $fi = Get-Item -LiteralPath $f -Force; $d[$n] = [pscustomobject]@{ S = [int64]$fi.Length; T = [int64]$fi.LastWriteTimeUtc.Ticks } }
    }
    return $d
}

# Gleich heißt: gleiche Größe und gleiche Zeit (2 s Toleranz) oder genau um ganze Stunden versetzt (bis 14 h). FAT-Sticks
# speichern Ortszeit; nach der Umstellung auf Sommerzeit oder an einem PC in einer anderen Zeitzone erscheinen alle Dateien
# um eine oder mehrere Stunden verschoben (wie robocopy /DST).
function Test-AbgleichGleich($a, $b) {
    if ($null -eq $a -or $null -eq $b) { return $false }
    if ([int64]$a.S -ne [int64]$b.S) { return $false }
    $dt = [math]::Abs(([double]([int64]$a.T - [int64]$b.T)) / 1e7)
    if ($dt -le $script:AbgleichToleranz) { return $true }
    if ($dt -gt 14 * 3600 + $script:AbgleichToleranz) { return $false }
    return ([math]::Abs($dt - [math]::Round($dt / 3600) * 3600) -le $script:AbgleichToleranz)
}

# Stand des letzten Abgleichs: Rel -> @{ L = @{S;T}; N = @{S;T} }; leer, wenn er zu einem anderen NAS-Pfad gehört
function Read-AbgleichStand([string]$DataDir, [string]$NasPfad) {
    $d = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $f = Join-Path (Join-Path $DataDir 'Abgleich') 'Stand.json'
    if (-not (Test-Path -LiteralPath $f)) { return $d }
    try { $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $d }
    if ([string]$j.Format -ne $script:AbgleichFormat -or ([string]$j.NasPfad).TrimEnd('\') -ine $NasPfad.TrimEnd('\')) { return $d }
    foreach ($e in @($j.Dateien)) {
        if (-not $e.P) { continue }
        $d[[string]$e.P] = [pscustomobject]@{ L = [pscustomobject]@{ S = [int64]$e.LS; T = [int64]$e.LT }; N = [pscustomobject]@{ S = [int64]$e.NS; T = [int64]$e.NT } }
    }
    return $d
}

function Save-AbgleichStand([string]$DataDir, [string]$NasPfad, $Stand) {
    $dir = Join-Path $DataDir 'Abgleich'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $liste = @(foreach ($k in @($Stand.Keys | Sort-Object)) { $e = $Stand[$k]; [ordered]@{ P = $k; LS = $e.L.S; LT = $e.L.T; NS = $e.N.S; NT = $e.N.T } })
    $o = [ordered]@{ Format = $script:AbgleichFormat; NasPfad = $NasPfad; Zeit = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture); Dateien = $liste }
    $f = Join-Path $dir 'Stand.json'
    [IO.File]::WriteAllText($f + '.tmp', ($o | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::Copy($f + '.tmp', $f, $true); Remove-Item -LiteralPath ($f + '.tmp') -Force -ErrorAction SilentlyContinue
}

# Plan aus beiden Beständen und dem letzten Stand. Aktionen: NachNas, VomNas, LoeschenLokal, LoeschenNas, Gleich,
# KonfliktNachNas (lokal neuer), KonfliktVomNas (NAS neuer), Vergessen (auf beiden Seiten weg).
function Get-AbgleichPlan($Lokal, $Nas, $Stand) {
    $alle = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $Lokal.Keys) { [void]$alle.Add($k) }; foreach ($k in $Nas.Keys) { [void]$alle.Add($k) }; foreach ($k in $Stand.Keys) { [void]$alle.Add($k) }
    $plan = New-Object System.Collections.Generic.List[object]
    foreach ($rel in @($alle | Sort-Object)) {
        $l = $(if ($Lokal.ContainsKey($rel)) { $Lokal[$rel] } else { $null })
        $n = $(if ($Nas.ContainsKey($rel)) { $Nas[$rel] } else { $null })
        $b = $(if ($Stand.ContainsKey($rel)) { $Stand[$rel] } else { $null })
        $a = ''
        if ($l -and $n) {
            if (Test-AbgleichGleich $l $n) { $a = 'Gleich' }
            elseif ($b) {
                $lNeu = -not (Test-AbgleichGleich $l $b.L); $nNeu = -not (Test-AbgleichGleich $n $b.N)
                if ($lNeu -and -not $nNeu) { $a = 'NachNas' }
                elseif ($nNeu -and -not $lNeu) { $a = 'VomNas' }
                elseif (-not $lNeu -and -not $nNeu) { $a = 'Gleich' }   # seit dem letzten Abgleich unverändert (gleicher Inhalt, andere Zeit)
                else { $a = $(if ([int64]$l.T -ge [int64]$n.T) { 'KonfliktNachNas' } else { 'KonfliktVomNas' }) }
            }
            else { $a = $(if ([int64]$l.T -ge [int64]$n.T) { 'KonfliktNachNas' } else { 'KonfliktVomNas' }) }
        }
        elseif ($l) { $a = $(if ($b -and (Test-AbgleichGleich $l $b.L)) { 'LoeschenLokal' } else { 'NachNas' }) }
        elseif ($n) { $a = $(if ($b -and (Test-AbgleichGleich $n $b.N)) { 'LoeschenNas' } else { 'VomNas' }) }
        else { $a = 'Vergessen' }
        $plan.Add([pscustomobject]@{ Rel = $rel; Aktion = $a })
    }
    return $plan
}

# ---------- Ausführen ----------
function Copy-AbgleichDatei([string]$Quelle, [string]$Ziel) {
    $dir = Split-Path $Ziel -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
    $tmp = Join-Path $dir ('~abgleich_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.tmp')
    try {
        [IO.File]::Copy($Quelle, $tmp, $true)
        [IO.File]::SetLastWriteTimeUtc($tmp, [IO.File]::GetLastWriteTimeUtc($Quelle))
        if ([IO.File]::Exists($Ziel)) { [IO.File]::Delete($Ziel) }
        [IO.File]::Move($tmp, $Ziel)
    } finally { if ([IO.File]::Exists($tmp)) { try { [IO.File]::Delete($tmp) } catch { } } }
}

# Datei ins Archiv der eigenen Seite verschieben (Archiv\Abgleich\<Zeit>\<Art>\<Rel>)
function Move-AbgleichArchiv([string]$Root, [string]$Rel, [string]$Stempel, [string]$Art) {
    $quelle = Join-AbgleichPfad $Root $Rel
    if (-not (Test-Path -LiteralPath $quelle)) { return }
    $ziel = Join-AbgleichPfad (Join-Path (Join-Path (Join-Path $Root 'Archiv') 'Abgleich') (Join-Path $Stempel $Art)) $Rel
    New-Item -ItemType Directory -Path (Split-Path $ziel -Parent) -Force -ErrorAction Stop | Out-Null
    if (Test-Path -LiteralPath $ziel) { $ziel = $ziel + '.' + [guid]::NewGuid().ToString('N').Substring(0, 4) }
    Move-Item -LiteralPath $quelle -Destination $ziel -Force -ErrorAction Stop
}

function Get-AbgleichHash([string]$Pfad) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $fs = [IO.File]::Open($Pfad, 'Open', 'Read', 'ReadWrite')
    try { return [BitConverter]::ToString($sha.ComputeHash($fs)) } finally { $fs.Dispose(); $sha.Dispose() }
}
function Test-AbgleichInhaltGleich([string]$A, [string]$B) {
    try { return ((Get-AbgleichHash $A) -eq (Get-AbgleichHash $B)) } catch { return $false }
}

function Get-AbgleichMeta([string]$Pfad) {
    $fi = New-Object IO.FileInfo($Pfad)
    if (-not $fi.Exists) { return $null }
    return [pscustomobject]@{ S = [int64]$fi.Length; T = [int64]$fi.LastWriteTimeUtc.Ticks }
}

# Leere Ordner nach Löschungen entfernen: nur die Ordner, aus denen dieser Abgleich etwas verschoben hat, aufwärts bis
# unter den abgeglichenen Ordner (Berichte bleibt). Ordner laufender Läufe bleiben, auch wenn sie noch leer sind.
function Remove-AbgleichLeereOrdner([string]$Root, $Rels, $Belegt = @()) {
    foreach ($rel in @($Rels)) {
        $teile = @(([string]$rel) -split '\\')
        for ($n = $teile.Count - 1; $n -ge 2; $n--) {
            $dirRel = ($teile[0..($n - 1)] -join '\')
            $frei = $true
            foreach ($b in $Belegt) { if ($dirRel -ieq $b -or $dirRel.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase)) { $frei = $false } }
            if (-not $frei) { break }
            $dir = Join-AbgleichPfad $Root $dirRel
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
            if (@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue).Count) { break }
            Remove-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
        }
    }
}

# Schutz vor Massenlöschung. Rückgabe: leer, oder der Grund zum Anhalten.
function Test-AbgleichMassenloeschung($Plan, $Stand, $Lokal, $Nas) {
    $gruende = @()
    foreach ($seite in @(@{ Name = 'auf dem Netzlaufwerk'; Aktion = 'LoeschenLokal'; Bestand = $Nas }, @{ Name = 'auf dem Stick'; Aktion = 'LoeschenNas'; Bestand = $Lokal })) {
        # ganze Ordner, die beim letzten Abgleich Dateien hatten und jetzt leer sind oder fehlen
        foreach ($o in $script:AbgleichOrdner) {
            $vorher = @($Stand.Keys | Where-Object { $_.StartsWith($o + '\', [StringComparison]::OrdinalIgnoreCase) }).Count
            $jetzt = @($seite.Bestand.Keys | Where-Object { $_.StartsWith($o + '\', [StringComparison]::OrdinalIgnoreCase) }).Count
            if ($vorher -ge 3 -and $jetzt -eq 0) { $gruende += ('{0} fehlt der Ordner {1} (beim letzten Abgleich {2} Dateien)' -f $seite.Name, $o, $vorher) }
        }
        $del = @($Plan | Where-Object { $_.Aktion -eq $seite.Aktion }).Count
        if ($del -ge 50 -or ($del -ge 10 -and $del * 2 -ge $Stand.Count)) { $gruende += ('{0} fehlen {1} von {2} abgeglichenen Dateien' -f $seite.Name, $del, $Stand.Count) }
    }
    return ($gruende -join '; ')
}

# NAS sperren (Abgleich.lock im NAS-Ordner). Die Sperre trägt eine eigene Kennung, wird während des Abgleichs
# aufgefrischt und nur mit passender Kennung entfernt. Ihr Alter wird an der Uhr des NAS gemessen (eine frisch
# geschriebene Probedatei), nicht an der Uhr des PCs, die auf einem geprüften Rechner falsch gehen kann.
function Get-NasJetzt([string]$NasPfad) {
    $f = Join-Path $NasPfad ('.zeit_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.tmp')
    try { [IO.File]::WriteAllText($f, ''); return [IO.File]::GetLastWriteTimeUtc($f) }
    catch { return [DateTime]::UtcNow }
    finally { try { [IO.File]::Delete($f) } catch { } }
}
function Enter-AbgleichSperre([string]$NasPfad, [string]$Kennung) {
    $f = Join-Path $NasPfad 'Abgleich.lock'
    for ($v = 0; $v -lt 2; $v++) {
        try {
            $fs = [IO.File]::Open($f, 'CreateNew', 'Write', 'None')
            try { $b = [Text.Encoding]::UTF8.GetBytes(('{0} {1} {2}' -f $Kennung, $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))); $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }
            return ''
        } catch {
            if (-not (Test-Path -LiteralPath $f)) { return ('Sperre auf dem Netzlaufwerk nicht anlegbar: ' + $_.Exception.Message) }
            $alt = $null; try { $alt = (Get-Item -LiteralPath $f -Force).LastWriteTimeUtc } catch { }
            if ($alt -and ((Get-NasJetzt $NasPfad) - $alt).TotalMinutes -ge $script:AbgleichSperreMin) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue; continue }
            $wer = ''; try { $wer = ([IO.File]::ReadAllText($f) -replace '^[0-9a-f]{32}\s+', '') } catch { }
            return ('ein anderer Abgleich läuft gerade oder wurde abgebrochen ({0}); die Sperre verfällt {1} Minuten nach dem letzten Lebenszeichen' -f $wer.Trim(), $script:AbgleichSperreMin)
        }
    }
    return 'Sperre auf dem Netzlaufwerk nicht anlegbar'
}
function Update-AbgleichSperre([string]$NasPfad, [string]$Kennung) {
    $f = Join-Path $NasPfad 'Abgleich.lock'
    try { if ([IO.File]::ReadAllText($f).StartsWith($Kennung)) { [IO.File]::WriteAllText($f, ('{0} {1} {2}' -f $Kennung, $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) } } catch { }
}
function Exit-AbgleichSperre([string]$NasPfad, [string]$Kennung) {
    $f = Join-Path $NasPfad 'Abgleich.lock'
    try { if ([IO.File]::ReadAllText($f).StartsWith($Kennung)) { [IO.File]::Delete($f) } } catch { }
}

# Protokoll in Minibench-Daten\Abgleich\Abgleich.log, auch wenn der Abgleich angehalten oder nichts geändert hat
function Write-AbgleichLog([string]$DataDir, $Res) {
    try {
        $log = Join-Path (Join-Path $DataDir 'Abgleich') 'Abgleich.log'
        New-Item -ItemType Directory -Path (Split-Path $log -Parent) -Force | Out-Null
        $txt = @(('{0}  {1}  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Res.NasPfad, $Res.Kurz)) + @($Res.Zeilen | ForEach-Object { '    ' + $_ })
        [IO.File]::AppendAllText($log, (($txt -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($true)))
    } catch { }
}

# Ordner eines Datenbankeintrags (Berichte\<Name>) aus der JSON-Datei, sonst leer
function Get-AbgleichEintragOrdner([string]$Pfad) {
    try {
        $o = [string](Get-Content -LiteralPath $Pfad -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).Ordner
        if ($o) { return ('Berichte\' + @($o.TrimEnd('\', '/') -split '[\\/]')[-1]) }
    } catch { }
    return ''
}

# -LoeschenErlaubt: angehaltenen Abgleich bestätigen. -Neu: Stand des letzten Abgleichs nicht verwenden (beide Seiten
# zusammenführen wie beim ersten Abgleich, nichts löschen), z. B. wenn das NAS neu eingerichtet oder geleert wurde.
function Invoke-Abgleich([string]$DataDir = $script:DataDir, [string]$NasPfad = '', [int]$TimeoutMs = 6000, [switch]$LoeschenErlaubt, [switch]$Neu) {
    $res = Invoke-AbgleichKern -DataDir $DataDir -NasPfad $NasPfad -TimeoutMs $TimeoutMs -LoeschenErlaubt:$LoeschenErlaubt -Neu:$Neu
    if ($DataDir) { Write-AbgleichLog $DataDir $res }
    return $res
}

function Invoke-AbgleichKern([string]$DataDir, [string]$NasPfad, [int]$TimeoutMs, [switch]$LoeschenErlaubt, [switch]$Neu) {
    $res = [pscustomobject]@{ Ok = $false; Erreichbar = $false; NasPfad = $NasPfad; NachNas = 0; VomNas = 0; GeloeschtLokal = 0; GeloeschtNas = 0
        Konflikte = 0; Fehler = 0; Angehalten = ''; Zeilen = (New-Object System.Collections.Generic.List[string]); Kurz = '' }
    if (-not $DataDir) { $res.Kurz = 'kein Datenordner'; return $res }
    if (-not $NasPfad) { $k = Get-NasKonfig $DataDir; if ($k) { $NasPfad = $k.Pfad } }
    $NasPfad = Format-NasPfad $NasPfad
    $res.NasPfad = $NasPfad
    if (-not $NasPfad) { $res.Kurz = 'kein Netzlaufwerk eingerichtet'; return $res }
    $fehler = Test-NasPfad $NasPfad
    if ($fehler) { $res.Kurz = 'ungültiger NAS-Pfad: ' + $fehler; return $res }
    $stand = Read-AbgleichStand $DataDir $NasPfad
    if ($Neu) { $stand.Clear(); $res.Zeilen.Add('Neu zusammengeführt: Stand des letzten Abgleichs nicht verwendet, nichts gelöscht') }
    # den Ordner auf dem NAS nur beim ersten Abgleich anlegen; fehlt er später, ist die Freigabe vermutlich nicht eingehängt
    if (-not (Test-NasErreichbar $NasPfad $TimeoutMs -Anlegen:($stand.Count -eq 0))) {
        $res.Kurz = $(if ($stand.Count) { ('{0} ist nicht erreichbar oder der Ordner fehlt; nichts geändert' -f $NasPfad) } else { ('{0} ist nicht erreichbar; nichts geändert' -f $NasPfad) })
        return $res
    }
    $res.Erreichbar = $true
    $kennung = [guid]::NewGuid().ToString('N')
    $sperre = Enter-AbgleichSperre $NasPfad $kennung
    if ($sperre) { $res.Fehler++; $res.Kurz = $sperre + '; nichts geändert'; return $res }
    try {
        $stempel = Get-Date -Format 'yyyyMMdd_HHmmss'
        $belegt = @(Get-AbgleichBelegt $DataDir)
        try {
            $lokal = Get-AbgleichBestand $DataDir $belegt
            $nas = Get-AbgleichBestand $NasPfad $belegt
        } catch { $res.Fehler++; $res.Kurz = $_.Exception.Message + '; nichts geändert'; return $res }
        # Datenbankeinträge zuletzt: Scheitert vorher eine Datei (z. B. eines Berichtsordners), bleiben sie für den nächsten
        # Abgleich stehen. So entsteht kein Eintrag, dessen Bericht fehlt (Datenpflege hielte ihn für verwaist).
        $plan = @(@(Get-AbgleichPlan $lokal $nas $stand) | Sort-Object @{ Expression = { if ($_.Rel -like 'Datenbank\*') { 1 } else { 0 } } }, @{ Expression = { $_.Rel } })
        if (-not $LoeschenErlaubt) {
            $grund = Test-AbgleichMassenloeschung $plan $stand $lokal $nas
            if ($grund) {
                $res.Angehalten = $grund
                $res.Kurz = ('angehalten, nichts geändert: {0}' -f $grund)
                $res.Zeilen.Add('Ist das gewollt (Daten bewusst entfernt), Abgleich bestätigen; sonst Netzlaufwerk und Pfad prüfen. Entfernte Dateien kämen ins Archiv.')
                return $res
            }
        }
        $neuStand = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($k in $stand.Keys) { $neuStand[$k] = $stand[$k] }      # Ausgangspunkt: alter Stand; bearbeitete Einträge werden ersetzt
        $arbeit = @($plan | Where-Object { $_.Aktion -ne 'Gleich' -and $_.Aktion -ne 'Vergessen' })
        $kopiert = New-Object System.Collections.Generic.List[string]
        $fehlOrdner = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $geleertL = New-Object System.Collections.Generic.List[string]; $geleertN = New-Object System.Collections.Generic.List[string]
        $i = 0; $folge = 0; $dbZurueck = 0
        foreach ($p in $plan) {
            $rel = $p.Rel; $lp = Join-AbgleichPfad $DataDir $rel; $np = Join-AbgleichPfad $NasPfad $rel
            if ($p.Aktion -eq 'Vergessen') { [void]$neuStand.Remove($rel); continue }
            if ($p.Aktion -eq 'Gleich' -and $lokal.ContainsKey($rel) -and $nas.ContainsKey($rel) -and
                [math]::Abs(([double]([int64]$lokal[$rel].T - [int64]$nas[$rel].T)) / 1e7) -gt $script:AbgleichToleranz -and -not (Test-AbgleichInhaltGleich $lp $np)) {
                # nur über die Stundenregel gleich, Inhalt aber verschieden: wie ein Konflikt behandeln
                $p = [pscustomobject]@{ Rel = $rel; Aktion = $(if ([int64]$lokal[$rel].T -ge [int64]$nas[$rel].T) { 'KonfliktNachNas' } else { 'KonfliktVomNas' }) }
            }
            if ($p.Aktion -eq 'Gleich') { $neuStand[$rel] = [pscustomobject]@{ L = $lokal[$rel]; N = $nas[$rel] }; continue }
            if ($p.Aktion -like 'Konflikt*' -and [int64]$lokal[$rel].S -eq [int64]$nas[$rel].S -and (Test-AbgleichInhaltGleich $lp $np)) {
                $neuStand[$rel] = [pscustomobject]@{ L = $lokal[$rel]; N = $nas[$rel] }; continue
            }
            if ($rel -like 'Datenbank\*' -and $fehlOrdner.Count -gt 0 -and $p.Aktion -notlike 'Loeschen*') {
                $quelle = $(if ($p.Aktion -eq 'NachNas' -or $p.Aktion -eq 'KonfliktNachNas') { $lp } else { $np })
                $eo = Get-AbgleichEintragOrdner $quelle
                if ($eo -and $fehlOrdner.Contains($eo)) { $dbZurueck++; continue }
            }
            $i++
            if ($i % 20 -eq 1) { Send-GuiEvent 'ABGLEICH' $i $arbeit.Count $rel; if ($i -gt 1) { Update-AbgleichSperre $NasPfad $kennung } }
            try {
                switch ($p.Aktion) {
                    'NachNas' { Copy-AbgleichDatei $lp $np; $res.NachNas++ }
                    'VomNas' { Copy-AbgleichDatei $np $lp; $res.VomNas++ }
                    'KonfliktNachNas' { Move-AbgleichArchiv $NasPfad $rel $stempel 'Konflikte'; Copy-AbgleichDatei $lp $np; $res.Konflikte++; $res.Zeilen.Add(('Konflikt {0}: Fassung vom Stick gilt, die vom Netzlaufwerk liegt dort im Archiv' -f $rel)) }
                    'KonfliktVomNas' { Move-AbgleichArchiv $DataDir $rel $stempel 'Konflikte'; Copy-AbgleichDatei $np $lp; $res.Konflikte++; $res.Zeilen.Add(('Konflikt {0}: Fassung vom Netzlaufwerk gilt, die vom Stick liegt im Archiv' -f $rel)) }
                    'LoeschenLokal' { Move-AbgleichArchiv $DataDir $rel $stempel 'Geloescht'; $res.GeloeschtLokal++; $geleertL.Add($rel) }
                    'LoeschenNas' { Move-AbgleichArchiv $NasPfad $rel $stempel 'Geloescht'; $res.GeloeschtNas++; $geleertN.Add($rel) }
                }
                $folge = 0
                if ($p.Aktion -like 'Loeschen*') { [void]$neuStand.Remove($rel) }
                else {
                    $m1 = Get-AbgleichMeta $lp; $m2 = Get-AbgleichMeta $np
                    if ($m1 -and $m2) { $neuStand[$rel] = [pscustomobject]@{ L = $m1; N = $m2 }; $kopiert.Add($rel) }
                }
            } catch {
                $res.Fehler++; $folge++
                $res.Zeilen.Add(('Fehler bei {0}: {1}' -f $rel, $_.Exception.Message))
                $t = @($rel -split '\\'); if ($t.Count -ge 3 -and $t[0] -ieq 'Berichte') { [void]$fehlOrdner.Add($t[0] + '\' + $t[1]) }
                if ($folge -ge 10) { $res.Zeilen.Add('Abgebrochen: zehn Fehler in Folge (Netzlaufwerk getrennt?). Der nächste Abgleich setzt fort.'); break }
            }
        }
        if ($dbZurueck) { $res.Zeilen.Add(('{0} Datenbankeinträge folgen beim nächsten Abgleich (Fehler in ihrem Berichtsordner)' -f $dbZurueck)) }
        # Ordner mit Fehlern gelten als nicht abgeglichen: ihre in diesem Durchgang kopierten Dateien behalten den alten Stand.
        # Fehlt einer Seite danach ein Teil davon (Datenpflege), wird er beim nächsten Abgleich ergänzt statt gelöscht.
        foreach ($rel in $kopiert) {
            $t = @($rel -split '\\'); $o = $(if ($t.Count -ge 3) { $t[0] + '\' + $t[1] } else { '' })
            if ($o -and $fehlOrdner.Contains($o)) { if ($stand.ContainsKey($rel)) { $neuStand[$rel] = $stand[$rel] } else { [void]$neuStand.Remove($rel) } }
        }
        try { Save-AbgleichStand $DataDir $NasPfad $neuStand } catch { $res.Fehler++; $res.Zeilen.Add('Stand des Abgleichs nicht gespeichert: ' + $_.Exception.Message) }
        Remove-AbgleichLeereOrdner $DataDir $geleertL $belegt; Remove-AbgleichLeereOrdner $NasPfad $geleertN $belegt
    } finally { Exit-AbgleichSperre $NasPfad $kennung }
    $res.Ok = ($res.Fehler -eq 0)
    $res.Kurz = ('{0} zum Netzlaufwerk, {1} auf den Stick, {2} gelöscht, {3} Konflikte, {4} Fehler' -f $res.NachNas, $res.VomNas, ($res.GeloeschtLokal + $res.GeloeschtNas), $res.Konflikte, $res.Fehler)
    return $res
}

# ---------- Läufe entfernen und umbenennen (Seite Vergleichsdatenbank) ----------
# Berichtsordner eines Datenbankeintrags (nur innerhalb von Berichte im Datenordner), sonst leer
function Get-LaufOrdner($Eintrag, [string]$DataDir) {
    $ber = [IO.Path]::GetFullPath((Join-Path $DataDir 'Berichte')).TrimEnd('\', '/')
    $o = ([string]$Eintrag.Ordner).Trim()
    if (-not $o) { return '' }
    $kand = @()
    if ([IO.Path]::IsPathRooted($o)) { $kand += $o } else { $kand += (Join-Path $DataDir $o) }
    $kand += (Join-Path $ber (@($o.TrimEnd('\', '/') -split '[\\/]')[-1]))
    foreach ($k in $kand) {
        try { $full = [IO.Path]::GetFullPath($k).TrimEnd('\', '/') } catch { continue }
        if ($full.StartsWith($ber + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full -PathType Container)) { return $full }
    }
    return ''
}

function Test-ImDatenbankOrdner([string]$Pfad, [string]$DataDir) {
    try {
        $db = [IO.Path]::GetFullPath((Join-Path $DataDir 'Datenbank')).TrimEnd('\', '/')
        $f = [IO.Path]::GetFullPath($Pfad)
        return ($f.StartsWith($db + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and $f -like '*.json')
    } catch { return $false }
}

# Einträge samt Berichtsordner nach Archiv\Entfernt\<Zeit> verschieben (wiederherstellbar). Rückgabe: Anzahl und Zeilen.
function Remove-DbLauf([string[]]$Pfade, [string]$DataDir = $script:DataDir) {
    $res = [pscustomobject]@{ Entfernt = 0; Fehler = 0; Zeilen = (New-Object System.Collections.Generic.List[string]); Archiv = '' }
    $arch = Join-Path (Join-Path (Join-Path $DataDir 'Archiv') 'Entfernt') (Get-Date -Format 'yyyyMMdd_HHmmss')
    $res.Archiv = $arch
    $belegt = @(Get-AbgleichBelegt $DataDir)
    foreach ($p in @($Pfade | Where-Object { $_ })) {
        $name = Split-Path $p -Leaf
        if (-not (Test-ImDatenbankOrdner $p $DataDir) -or -not (Test-Path -LiteralPath $p)) { $res.Fehler++; $res.Zeilen.Add(('{0}: nicht in der Datenbank dieses Datenordners, übersprungen' -f $p)); continue }
        $e = $null; try { $e = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        $ordner = $(if ($e) { Get-LaufOrdner $e $DataDir } else { '' })
        if ($ordner -and $belegt -contains ('Berichte\' + (Split-Path $ordner -Leaf))) { $res.Fehler++; $res.Zeilen.Add(('{0}: der Lauf ist noch nicht abgeschlossen, übersprungen' -f $name)); continue }
        try {
            New-Item -ItemType Directory -Path (Join-Path $arch 'Datenbank') -Force -ErrorAction Stop | Out-Null
            if ($ordner) {
                New-Item -ItemType Directory -Path (Join-Path $arch 'Berichte') -Force -ErrorAction Stop | Out-Null
                Move-Item -LiteralPath $ordner -Destination (Join-Path (Join-Path $arch 'Berichte') (Split-Path $ordner -Leaf)) -ErrorAction Stop
            }
            Move-Item -LiteralPath $p -Destination (Join-Path (Join-Path $arch 'Datenbank') $name) -ErrorAction Stop
            $res.Entfernt++
            $res.Zeilen.Add(('{0}{1} ins Archiv verschoben' -f $name, $(if ($ordner) { ' und Berichtsordner ' + (Split-Path $ordner -Leaf) } else { '' })))
        } catch { $res.Fehler++; $res.Zeilen.Add(('{0}: {1}' -f $name, $_.Exception.Message)) }
    }
    return $res
}

# freier Name im Ordner: Basis, sonst Basis_2, Basis_3 ...
function Get-FreierName([string]$Dir, [string]$Basis, [string]$Endung, [string]$Eigen = '') {
    $n = $Basis + $Endung
    $i = 2
    while ((Test-Path -LiteralPath (Join-Path $Dir $n)) -and $n -ine $Eigen) { $n = '{0}_{1}{2}' -f $Basis, $i, $Endung; $i++ }
    return $n
}

# Anzeigenamen ändern und Datenbankdatei sowie Berichtsordner passend umbenennen (Name_Datum_Zeit). Der Rechnername
# (Computer) und die Geräteidentität bleiben. Änderungsprotokolle, die auf den Berichtsordner zeigen, werden nachgeführt.
function Rename-DbLauf([string]$Pfad, [string]$NeuerName, [string]$DataDir = $script:DataDir) {
    $res = [pscustomobject]@{ Ok = $false; Pfad = $Pfad; Ordner = ''; Text = '' }
    $NeuerName = ([string]$NeuerName -replace '[\r\n"]+', ' ').Trim()
    if ($NeuerName.Length -gt 80) { $NeuerName = $NeuerName.Substring(0, 80).Trim() }
    if (-not $NeuerName) { $res.Text = 'Kein Name angegeben.'; return $res }
    if (-not (Test-ImDatenbankOrdner $Pfad $DataDir) -or -not (Test-Path -LiteralPath $Pfad)) { $res.Text = 'Eintrag liegt nicht in der Datenbank dieses Datenordners.'; return $res }
    try { $e = Get-Content -LiteralPath $Pfad -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { $res.Text = 'Eintrag nicht lesbar: ' + $_.Exception.Message; return $res }
    $basis = Get-AblageName $NeuerName
    if (-not $basis) { $basis = Get-AblageName ([string]$e.Computer) }
    # Datenbankdatei: <Name>_<yyyyMMdd_HHmmss>.json
    $dbDir = Split-Path $Pfad -Parent
    $alt = [IO.Path]::GetFileNameWithoutExtension($Pfad)
    $m = [regex]::Match($alt, '^(.*?)(_\d{8}_\d{6})(?:_\d{1,2})?$')
    $neuDatei = Get-FreierName $dbDir ($basis + $(if ($m.Success) { $m.Groups[2].Value } else { '_' + $alt })) '.json' (Split-Path $Pfad -Leaf)
    $neuPfad = Join-Path $dbDir $neuDatei
    # Berichtsordner: <Name>_<yyyyMMdd_HHmm>[_ss]
    $ordner = Get-LaufOrdner $e $DataDir
    $neuOrdner = ''
    if ($ordner) {
        $leaf = Split-Path $ordner -Leaf
        $mo = [regex]::Match($leaf, '^(.*?)(_\d{8}_\d{4}(?:_\d{2})?)(?:_\d)?$')
        $neuLeaf = Get-FreierName (Split-Path $ordner -Parent) ($basis + $(if ($mo.Success) { $mo.Groups[2].Value } else { '_' + $leaf })) '' $leaf
        $neuOrdner = Join-Path (Split-Path $ordner -Parent) $neuLeaf
        if ($neuLeaf -ine $leaf) {
            try { Move-Item -LiteralPath $ordner -Destination $neuOrdner -ErrorAction Stop }
            catch { $res.Text = ('Berichtsordner {0} lässt sich nicht umbenennen (geöffnet?): {1}' -f $leaf, $_.Exception.Message); return $res }
        } else { $neuOrdner = $ordner }
    }
    try {
        $e | Add-Member -NotePropertyName Name -NotePropertyValue $NeuerName -Force
        # Ordner immer relativ zum Datenordner (ein absoluter Pfad vom Stick wäre auf dem Netzlaufwerk falsch)
        if ($neuOrdner) { $e | Add-Member -NotePropertyName Ordner -NotePropertyValue ('Berichte\' + (Split-Path $neuOrdner -Leaf)) -Force }
        [IO.File]::WriteAllText($neuPfad, ($e | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
        if ($neuPfad -ine $Pfad) { Remove-Item -LiteralPath $Pfad -Force -ErrorAction Stop }
    } catch {
        if ($ordner -and $neuOrdner -and $neuOrdner -ine $ordner) { try { Move-Item -LiteralPath $neuOrdner -Destination $ordner -ErrorAction Stop } catch { } }
        if ($neuPfad -ine $Pfad -and (Test-Path -LiteralPath $Pfad) -and (Test-Path -LiteralPath $neuPfad)) { Remove-Item -LiteralPath $neuPfad -Force -ErrorAction SilentlyContinue }
        $res.Text = 'Eintrag nicht gespeichert: ' + $_.Exception.Message; return $res
    }
    # Änderungsprotokolle: Feld Bericht zeigt auf den Ordner zur Laufzeit (anderer Laufwerksbuchstabe, früher auch das NAS).
    # Ersetzt wird nur der letzte Teil (Ordnername), der Rest des Pfads bleibt, wie er war.
    if ($ordner -and $neuOrdner -ine $ordner) {
        $altLeaf = Split-Path $ordner -Leaf; $neuLeaf = Split-Path $neuOrdner -Leaf
        $muster = '("Bericht"\s*:\s*"[^"]*?(?:\\\\|/))' + [regex]::Escape($altLeaf) + '"'
        $ersatz = '${1}' + ($neuLeaf -replace '\$', '$$$$') + '"'
        foreach ($cf in @(Get-ChildItem -LiteralPath (Join-Path $DataDir 'Änderungen') -Filter '*.json' -Recurse -File -ErrorAction SilentlyContinue)) {
            try {
                $t = [IO.File]::ReadAllText($cf.FullName, [Text.Encoding]::UTF8)
                $n = [regex]::Replace($t, $muster, $ersatz, 'IgnoreCase')
                if ($n -ne $t) { [IO.File]::WriteAllText($cf.FullName, $n, (New-Object Text.UTF8Encoding($false))) }
            } catch { }
        }
    }
    $res.Ok = $true; $res.Pfad = $neuPfad; $res.Ordner = $neuOrdner
    $res.Text = ('Name geändert in {0}; Datei {1}{2}' -f $NeuerName, $neuDatei, $(if ($neuOrdner) { ', Berichtsordner ' + (Split-Path $neuOrdner -Leaf) } else { '' }))
    return $res
}

# ---------- Start und Hilfsmodi der Oberfläche ----------
if ($script:DataDir) { try { foreach ($z in (Move-AlteNasKonfig $script:DataDir)) { Write-Verbose $z } } catch { } }

# Abgleich mit dem Netzlaufwerk: @@ABGLEICH|Nr|Anzahl|Datei während, am Ende
# @@RESULT|ok|zumNas|aufStick|gelöscht|Konflikte|Fehler|erreichbar|angehalten (1: Schutz vor Massenlöschung, Bestätigung nötig).
# -AbgleichLoeschen bestätigt einen angehaltenen Abgleich, -AbgleichNeu führt ohne den letzten Stand zusammen (nichts löschen).
if ($Abgleich) {
    $r = Invoke-Abgleich -DataDir $script:DataDir -LoeschenErlaubt:$AbgleichLoeschen -Neu:$AbgleichNeu
    Write-Host ('Abgleich mit {0}: {1}' -f $r.NasPfad, $r.Kurz)
    foreach ($z in $r.Zeilen) { Write-Host $z }
    Send-GuiEvent 'RESULT' $(if ($r.Ok) { '1' } else { '0' }) $r.NachNas $r.VomNas ($r.GeloeschtLokal + $r.GeloeschtNas) $r.Konflikte $r.Fehler $(if ($r.Erreichbar) { '1' } else { '0' }) $(if ($r.Angehalten) { '1' } else { '0' })
    exit $(if ($r.Ok) { 0 } else { 1 })
}
# Einträge entfernen: -Entfernen "Pfad|Pfad" (| kommt in Windows-Pfaden nicht vor), @@RESULT|entfernt|Fehler
if ($Entfernen) {
    $r = Remove-DbLauf @(([string]$Entfernen) -split '\|' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }) $script:DataDir
    foreach ($z in $r.Zeilen) { Write-Host $z }
    Send-GuiEvent 'RESULT' $r.Entfernt $r.Fehler
    exit $(if ($r.Fehler) { 1 } else { 0 })
}
# Eintrag umbenennen: -Umbenennen "Pfad" -NeuerName "Name", @@RESULT|1 oder 0|neuer Pfad
if ($Umbenennen) {
    $r = Rename-DbLauf ([string]$Umbenennen).Trim('"') $NeuerName $script:DataDir
    Write-Host $r.Text
    Send-GuiEvent 'RESULT' $(if ($r.Ok) { '1' } else { '0' }) $r.Pfad
    exit $(if ($r.Ok) { 0 } else { 1 })
}
#endregion
