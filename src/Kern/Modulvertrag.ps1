#region ---------- Modulvertrag ----------
# Jedes Modul beschreibt sich in src\Module\<Name>\Vertrag.psd1. Bauen.cmd bindet die Verträge hier ein.
#
#   Vertrag          Version des Vertragsformats (derzeit 1)
#   Name             Modulname, zugleich Wert für -Module
#   Seite            Titel und Kurzbeschreibung in der Navigation der Oberfläche
#   Admin            braucht Administratorrechte
#   Risiko           höchste Risikostufe, die das Modul erreichen kann (Lesen, Aendern, Eingriff, Zerstoerend)
#   Neustart         nie, moeglich oder immer (höchster Bedarf unter den Schritten)
#   Parameter        Skriptparameter, die zum Modul gehören
#   Datenbankfelder  Felder, die das Modul in den Datenbankeintrag schreibt
#   Schritte         Key, Typ, Titel, Risiko, Neustart, Rueckgaengig (keins, Protokoll, Wiederherstellungspunkt, Hinweis)
#                    Maßnahmen der Reparatur zusätzlich: Text, Minuten, Vorauswahl, Ueblich (für die Seite Reparatur)
#                    ab v2.6 (schneller Modus): Parallel ($true = darf im Hintergrund neben anderen Prüfungen laufen, nur Lesen),
#                    Nach (Keys, die vorher fertig sein müssen), Exklusiv ($true = Messung, nie neben Hintergrundaufgaben)
#
# Die @@-Zeilen zwischen Arbeitsprozess und Oberfläche bleiben das Protokoll; der Vertrag beschreibt nur, was ein Modul ist.
$script:ModuleContracts = @(
#>> EINBINDEN Module\Diagnose\Vertrag.psd1
#>> EINBINDEN Module\Benchmark\Vertrag.psd1
#>> EINBINDEN Module\Lasttest\Vertrag.psd1
#>> EINBINDEN Module\Wartung\Vertrag.psd1
#>> EINBINDEN Module\Optimierung\Vertrag.psd1
#>> EINBINDEN Module\Sensoren\Vertrag.psd1
)
$script:ContractCoreDbFields = @('Format', 'Name', 'Computer', 'Geraet', 'Datum', 'Version', 'Quelle', 'Module', 'Ordner', 'Schreibzugriffe', 'Ablauf')
$script:RestartOrder = @('nie', 'moeglich', 'immer')
$script:UndoKinds = @('keins', 'Protokoll', 'Wiederherstellungspunkt', 'Hinweis')

function Get-ModuleContract([string]$Name) {
    if ($Name -eq 'Reparatur') {
        foreach ($c in $script:ModuleContracts) { if ($c.Name -eq 'Wartung' -or $c.Name -eq 'Reparatur') { return $c } }
    }
    foreach ($c in $script:ModuleContracts) { if ($c.Name -eq $Name) { return $c } }
    return $null
}

function Get-ModuleStep([string]$Module, [string]$Key) {
    $c = Get-ModuleContract $Module
    if (-not $c) { return $null }
    foreach ($s in $c.Schritte) { if ($s.Key -eq $Key) { return $s } }
    return $null
}

# Prüft einen Vertrag auf Vollständigkeit und Widersprüche. Rückgabe: Liste der Fehler (leer = in Ordnung).
function Test-ModuleContract($Contract, [string[]]$KnownParameters = @()) {
    $err = New-Object System.Collections.Generic.List[string]
    $n = $(if ($Contract -and $Contract.Name) { [string]$Contract.Name } else { '(ohne Namen)' })
    if (-not ($Contract -is [hashtable])) { $err.Add(('{0}: Vertrag ist keine Hashtable.' -f $n)); return $err.ToArray() }
    foreach ($f in 'Vertrag', 'Name', 'Seite', 'Admin', 'Risiko', 'Neustart', 'Parameter', 'Datenbankfelder', 'Schritte') {
        if (-not $Contract.ContainsKey($f)) { $err.Add(('{0}: Feld {1} fehlt.' -f $n, $f)) }
    }
    if ($err.Count) { return $err.ToArray() }
    if ($Contract.Vertrag -ne 1) { $err.Add(('{0}: Vertragsversion {1} wird nicht unterstützt.' -f $n, $Contract.Vertrag)) }
    if ($Contract.Name -notmatch '^[A-Za-z]+$') { $err.Add(('{0}: Name darf nur Buchstaben enthalten.' -f $n)) }
    if (-not $Contract.Seite.Titel -or -not $Contract.Seite.Kurz) { $err.Add(('{0}: Seite braucht Titel und Kurz.' -f $n)) }
    if (-not ($Contract.Admin -is [bool])) { $err.Add(('{0}: Admin muss $true oder $false sein.' -f $n)) }
    if ($script:RiskOrder -notcontains $Contract.Risiko) { $err.Add(('{0}: unbekannte Risikostufe {1}.' -f $n, $Contract.Risiko)) }
    if ($script:RestartOrder -notcontains $Contract.Neustart) { $err.Add(('{0}: Neustart muss nie, moeglich oder immer sein.' -f $n)) }
    foreach ($p in @($Contract.Parameter)) { if ($KnownParameters.Count -and $KnownParameters -notcontains $p) { $err.Add(('{0}: Parameter {1} gibt es im Skript nicht.' -f $n, $p)) } }
    foreach ($d in @($Contract.Datenbankfelder)) { if ($script:ContractCoreDbFields -contains $d) { $err.Add(('{0}: Datenbankfeld {1} gehört zum Kern.' -f $n, $d)) } }
    $steps = @($Contract.Schritte)
    if (-not $steps.Count) { $err.Add(('{0}: keine Schritte.' -f $n)) }
    $keys = @{}
    $maxR = 0; $maxN = 0
    foreach ($s in $steps) {
        $k = [string]$s.Key
        if (-not $k) { $err.Add(('{0}: Schritt ohne Key.' -f $n)); continue }
        if ($keys.ContainsKey($k)) { $err.Add(('{0}: Schritt {1} doppelt.' -f $n, $k)) }
        $keys[$k] = $true
        foreach ($f in 'Typ', 'Titel', 'Risiko', 'Neustart', 'Rueckgaengig') { if (-not $s.ContainsKey($f) -or -not [string]$s[$f]) { $err.Add(('{0}/{1}: Feld {2} fehlt.' -f $n, $k, $f)) } }
        if ($script:RiskOrder -notcontains $s.Risiko) { $err.Add(('{0}/{1}: unbekannte Risikostufe {2}.' -f $n, $k, $s.Risiko)); continue }
        if ($script:RestartOrder -notcontains $s.Neustart) { $err.Add(('{0}/{1}: Neustart muss nie, moeglich oder immer sein.' -f $n, $k)); continue }
        if ($script:UndoKinds -notcontains $s.Rueckgaengig) { $err.Add(('{0}/{1}: Rueckgaengig muss keins, Protokoll, Wiederherstellungspunkt oder Hinweis sein.' -f $n, $k)); continue }
        $r = Get-RiskRank $s.Risiko
        if ($r -gt $maxR) { $maxR = $r }
        $nr = [array]::IndexOf($script:RestartOrder, [string]$s.Neustart); if ($nr -gt $maxN) { $maxN = $nr }
        # Die Stufe legt fest, wie ein Schritt rückgängig zu machen ist
        switch ($s.Risiko) {
            'Lesen'       { if ($s.Rueckgaengig -ne 'keins') { $err.Add(('{0}/{1}: Lesen verändert nichts, Rueckgaengig muss keins sein.' -f $n, $k)) } }
            'Aendern'     { if ($s.Rueckgaengig -ne 'Protokoll') { $err.Add(('{0}/{1}: Ändern verlangt Rueckgaengig = Protokoll.' -f $n, $k)) } }
            'Eingriff'    { if ($s.Rueckgaengig -eq 'Protokoll') { $err.Add(('{0}/{1}: ein Eingriff ist nicht über das Protokoll umkehrbar, sonst wäre er Ändern.' -f $n, $k)) } }
            'Zerstoerend' { if ($s.Rueckgaengig -ne 'keins') { $err.Add(('{0}/{1}: Zerstörendes ist nicht umkehrbar, Rueckgaengig muss keins sein.' -f $n, $k)) } }
        }
        if ($s.Typ -eq 'Massnahme') {
            foreach ($f in 'Text', 'Minuten', 'Vorauswahl', 'Ueblich') { if (-not $s.ContainsKey($f)) { $err.Add(('{0}/{1}: Maßnahme braucht {2}.' -f $n, $k, $f)) } }
            if ($s.ContainsKey('Text') -and ([string]$s.Text).Contains('|')) { $err.Add(('{0}/{1}: Text darf kein | enthalten.' -f $n, $k)) }
        }
        if ($s.ContainsKey('Schalter') -and $KnownParameters.Count -and $KnownParameters -notcontains $s.Schalter) { $err.Add(('{0}/{1}: Schalter {2} gibt es im Skript nicht.' -f $n, $k, $s.Schalter)) }
        if ($s.ContainsKey('Parallel') -and -not ($s.Parallel -is [bool])) { $err.Add(('{0}/{1}: Parallel muss $true oder $false sein.' -f $n, $k)) }
        if ($s.ContainsKey('Exklusiv') -and -not ($s.Exklusiv -is [bool])) { $err.Add(('{0}/{1}: Exklusiv muss $true oder $false sein.' -f $n, $k)) }
        if ($s.Parallel -and $s.Exklusiv) { $err.Add(('{0}/{1}: ein Schritt kann nicht zugleich parallel und exklusiv sein.' -f $n, $k)) }
        if ($s.Parallel -and $s.Risiko -ne 'Lesen') { $err.Add(('{0}/{1}: parallel laufen dürfen nur lesende Schritte.' -f $n, $k)) }
    }
    # Abhängigkeiten: nur bekannte Schritte, keine Kreise
    foreach ($s in $steps) {
        foreach ($d in @($s.Nach | Where-Object { $_ })) { if (-not $keys.ContainsKey([string]$d)) { $err.Add(('{0}/{1}: Nach nennt den unbekannten Schritt {2}.' -f $n, $s.Key, $d)) } }
    }
    $dep = @{}; foreach ($s in $steps) { if ($s.Key) { $dep[[string]$s.Key] = @($s.Nach | Where-Object { $_ } | ForEach-Object { [string]$_ }) } }
    foreach ($start in @($dep.Keys)) {
        $seen = @{}; $todo = New-Object System.Collections.Generic.Queue[string]; foreach ($d in $dep[$start]) { $todo.Enqueue($d) }
        while ($todo.Count) {
            $x = $todo.Dequeue()
            if ($x -eq $start) { $err.Add(('{0}/{1}: Abhängigkeiten bilden einen Kreis.' -f $n, $start)); break }
            if ($seen.ContainsKey($x) -or -not $dep.ContainsKey($x)) { continue }
            $seen[$x] = $true; foreach ($d in $dep[$x]) { $todo.Enqueue($d) }
        }
    }
    if ($script:RiskOrder[$maxR] -ne $Contract.Risiko) { $err.Add(('{0}: Risiko {1} passt nicht zur höchsten Stufe der Schritte ({2}).' -f $n, $Contract.Risiko, $script:RiskOrder[$maxR])) }
    if ($script:RestartOrder[$maxN] -ne $Contract.Neustart) { $err.Add(('{0}: Neustart {1} passt nicht zu den Schritten ({2}).' -f $n, $Contract.Neustart, $script:RestartOrder[$maxN])) }
    return $err.ToArray()
}

# -Module "Diagnose,Benchmark" in bekannte Modulnamen übersetzen; Unbekanntes wird gemeldet und ignoriert
function Resolve-ModuleList([string]$Text) {
    $known = @{}
    foreach ($c in $script:ModuleContracts) { $known[$c.Name.ToLowerInvariant()] = $c.Name }
    if ($known.ContainsKey('wartung') -and -not $known.ContainsKey('reparatur')) { $known['reparatur'] = $known['wartung'] }
    $res = New-Object System.Collections.Generic.List[string]
    $unknown = New-Object System.Collections.Generic.List[string]
    foreach ($m in @(([string]$Text) -split '[,;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $k = $m.ToLowerInvariant()
        if ($known.ContainsKey($k)) { if (-not $res.Contains($known[$k])) { $res.Add($known[$k]) } } else { $unknown.Add($m) }
    }
    return [pscustomobject]@{ Module = $res.ToArray(); Unbekannt = $unknown.ToArray() }
}

# Kurzfassung der Verträge für die Oberfläche, eine Zeile je Eintrag:
#   M|Name|Titel|Kurz|Admin|Risiko|Neustart
#   S|Modul|Key|Typ|Risiko|Neustart|Rueckgaengig|Minuten|Vorauswahl|Ueblich|Text
function Get-ContractGuiLines {
    $l = New-Object System.Collections.Generic.List[string]
    $clean = { param($v) (([string]$v) -replace '[\r\n|]+', ' ').Trim() }
    foreach ($c in $script:ModuleContracts) {
        $l.Add(('M|{0}|{1}|{2}|{3}|{4}|{5}' -f $c.Name, (& $clean $c.Seite.Titel), (& $clean $c.Seite.Kurz), $(if ($c.Admin) { '1' } else { '0' }), $c.Risiko, $c.Neustart))
        foreach ($s in $c.Schritte) {
            $txt = $(if ($s.Text) { $s.Text } else { $s.Titel })
            $l.Add(('S|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}' -f $c.Name, $s.Key, $s.Typ, $s.Risiko, $s.Neustart, $s.Rueckgaengig, [int]$s.Minuten, $(if ($s.Vorauswahl) { '1' } else { '0' }), $(if ($s.Ueblich) { '1' } else { '0' }), (& $clean $txt)))
        }
    }
    return $l.ToArray()
}
#endregion
