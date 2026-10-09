#region ---------- Softwarepakete über winget (Seite Tools, ab v3.53) ----------
# Die Seite Tools bietet ausgewählte Programme zur Installation über winget an. Die Installation läuft im Arbeitsprozess
# (Hilfsmodus -SoftwareInstallieren), nicht in der Oberfläche:
#   * jedes Paket hat eine feste Frist; die Ausgabe von winget wird vollständig gelesen (kein Hänger bei vollem Puffer)
#   * schon vorhandene Programme werden nicht angefasst und nicht protokolliert (Rückgängig entfernt nur, was Minibench installiert hat)
#   * jede Installation landet als Eingriff im Änderungsprotokoll, mit winget uninstall als Gegenbefehl (Seite Änderungen)
# Ereignisse: @@PAKET|Nr|Anzahl|Id|Status|Text je Schritt (Status: läuft, installiert, bereits installiert, fehlgeschlagen,
# Zeitüberschreitung, ungültig), am Ende @@RESULT|installiert|bereits|fehlgeschlagen.

$script:WingetFristSek       = 1200   # je Paket; große Pakete (Office, Steam) brauchen auf langsamen Leitungen lange
$script:WingetFristListeSek  = 120
$script:WingetFristEntfSek   = 900

# Paketkennung prüfen (nur Zeichen, die winget-Ids haben; schützt die Befehlszeile)
function Test-WingetId([string]$Id) { return ([string]$Id -match '^[A-Za-z0-9][A-Za-z0-9\.\+_\-]{1,99}$') }

function Find-Winget {
    $c = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    if ($env:LOCALAPPDATA) {
        $p = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return ''
}

# winget aufrufen; Rückgabe wie Invoke-External (ExitCode, Output, Error, TimedOut)
function Invoke-Winget([string]$Exe, [string]$Arguments, [int]$TimeoutSec) {
    return (Invoke-External -File $Exe -Arguments $Arguments -TimeoutSec $TimeoutSec -Encoding ([Text.Encoding]::UTF8) -OhneUeberspringen)
}

function Format-WingetCode($Code) { return ('0x{0:X8}' -f ([int64]$Code -band 0xFFFFFFFFL)) }

# Rückgabecodes von winget (https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md)
$script:WingetNichtGefunden     = '0x8A150014'   # NO_APPLICATIONS_FOUND (list: nicht installiert)
$script:WingetSchonInstalliert  = @('0x8A150061', '0x8A15002B')   # PACKAGE_ALREADY_INSTALLED, UPDATE_NOT_APPLICABLE
$script:WingetNeustartFertig    = '0x8A150109'   # INSTALL_REBOOT_REQUIRED_TO_FINISH (installiert, Neustart schließt ab)

# Ist das Paket installiert? $true: list nennt die Id; $false: nur bei "nichts gefunden" (0x8A150014);
# $null: nicht feststellbar (Frist, defekte Quelle, unbekannter Fehler). Nur ein eindeutiges $false erlaubt eine
# Installation mit Eintrag im Änderungsprotokoll, sonst könnte Rückgängig ein Programm entfernen, das schon da war.
function Test-WingetPaketInstalliert([string]$Exe, [string]$Id) {
    $r = Invoke-Winget $Exe ('list --id {0} -e --accept-source-agreements --disable-interactivity' -f $Id) $script:WingetFristListeSek
    if ($r.TimedOut) { return $null }
    if ([int64]$r.ExitCode -eq 0 -and ([string]$r.Output) -match [regex]::Escape($Id)) { return $true }
    if ((Format-WingetCode $r.ExitCode) -eq $script:WingetNichtGefunden) { return $false }
    return $null
}

function Get-WingetFehlerText($r) {
    $tail = (@((([string]$r.Output) + "`n" + ([string]$r.Error)) -split "`r?`n" | ForEach-Object { ($_ -replace '[^\w\s\.,:;()\-/%]', '').Trim() } | Where-Object { $_.Length -gt 3 }) | Select-Object -Last 2) -join ' '
    return ('winget meldet {0}{1}' -f (Format-WingetCode $r.ExitCode), $(if ($tail) { ' (' + $tail + ')' } else { '' }))
}

# Ein Paket installieren. Rückgabe: Id, Status, Text
function Install-SoftwarePaket([string]$Exe, [string]$Id, [string]$Name = '') {
    if (-not $Name) { $Name = $Id }
    $vorher = Test-WingetPaketInstalliert $Exe $Id
    if ($vorher -eq $true) { return [pscustomobject]@{ Id = $Id; Status = 'bereits installiert'; Text = ('{0} ist schon installiert; nichts geändert.' -f $Name) } }
    if ($null -eq $vorher) { return [pscustomobject]@{ Id = $Id; Status = 'fehlgeschlagen'; Text = ('{0}: winget kann nicht feststellen, ob das Programm schon installiert ist; nichts installiert.' -f $Name) } }
    # --no-upgrade: ein Programm, das winget nicht zuordnen konnte, wird nicht still aktualisiert
    $r = Invoke-Winget $Exe ('install --id {0} -e --silent --no-upgrade --accept-package-agreements --accept-source-agreements --disable-interactivity' -f $Id) $script:WingetFristSek
    if ($r.TimedOut) {
        return [pscustomobject]@{ Id = $Id; Status = 'Zeitüberschreitung'; Text = ('{0}: keine Rückmeldung von winget nach {1} Minuten, abgebrochen. Ob das Programm installiert ist, zeigt die Systemsteuerung.' -f $Name, [int]($script:WingetFristSek / 60)) }
    }
    $code = Format-WingetCode $r.ExitCode
    if ($script:WingetSchonInstalliert -contains $code) { return [pscustomobject]@{ Id = $Id; Status = 'bereits installiert'; Text = ('{0} ist schon installiert ({1}); nichts geändert.' -f $Name, $code) } }
    $neustart = ($code -eq $script:WingetNeustartFertig)
    $nachher = Test-WingetPaketInstalliert $Exe $Id
    if ([int64]$r.ExitCode -eq 0 -or $neustart -or $nachher -eq $true) {
        [void](Add-ChangeRecord -Modul 'Tools' -Schritt 'Softwarepaket' -Titel ('{0} installiert (winget)' -f $Name) -Risiko 'Eingriff' -Art 'Softwarepaket' `
            -Ziel $Id -Vorher 'nicht installiert' -Nachher $(if ($neustart) { 'installiert, Neustart nötig' } else { 'installiert' }) -Daten ([ordered]@{ PaketId = $Id; Name = $Name }) -Gegenbefehl ('winget uninstall --id {0} -e' -f $Id))
        return [pscustomobject]@{ Id = $Id; Status = 'installiert'; Text = ('{0} installiert{1}; rückgängig über die Seite Änderungen.' -f $Name, $(if ($neustart) { ', ein Neustart schließt die Installation ab' } else { '' })) }
    }
    return [pscustomobject]@{ Id = $Id; Status = 'fehlgeschlagen'; Text = ('{0}: {1}' -f $Name, (Get-WingetFehlerText $r)) }
}

# Hilfsmodus der Oberfläche: -SoftwareInstallieren "Id=Name;Id=Name" (Name optional)
function Invoke-SoftwarePakete([string]$Spec) {
    $liste = @(([string]$Spec) -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
        $p = $_ -split '=', 2
        [pscustomobject]@{ Id = $p[0].Trim(); Name = $(if ($p.Count -eq 2 -and $p[1].Trim()) { $p[1].Trim() } else { $p[0].Trim() }) }
    })
    $sum = [ordered]@{ Installiert = 0; Bereits = 0; Fehler = 0; Ergebnisse = @() }
    $exe = Find-Winget
    $n = $liste.Count; $i = 0
    foreach ($e in $liste) {
        $i++
        if (-not (Test-WingetId $e.Id)) { $r = [pscustomobject]@{ Id = $e.Id; Status = 'ungültig'; Text = ('Ungültige Paketkennung: {0}' -f $e.Id) } }
        elseif (-not $exe) { $r = [pscustomobject]@{ Id = $e.Id; Status = 'fehlgeschlagen'; Text = 'winget ist auf diesem PC nicht verfügbar.' } }
        else {
            Send-GuiEvent 'PAKET' $i $n $e.Id 'läuft' ('Installiere ({0} von {1}): {2} ...' -f $i, $n, $e.Name)
            try { $r = Install-SoftwarePaket $exe $e.Id $e.Name } catch { $r = [pscustomobject]@{ Id = $e.Id; Status = 'fehlgeschlagen'; Text = ('{0}: {1}' -f $e.Name, $_.Exception.Message) } }
        }
        switch ($r.Status) { 'installiert' { $sum.Installiert++ } 'bereits installiert' { $sum.Bereits++ } default { $sum.Fehler++ } }
        $sum.Ergebnisse += $r
        Send-GuiEvent 'PAKET' $i $n $r.Id $r.Status $r.Text
        Write-Host $r.Text
    }
    return [pscustomobject]$sum
}

# Rückgängig (Seite Änderungen): nur deinstallieren, was noch installiert ist. Ist das nicht feststellbar oder scheitert
# winget, bleibt der Eintrag aktiv (Status aktiv), damit ein späterer Versuch möglich ist.
function Undo-SoftwarePaket($Record) {
    $id = [string]$Record.Daten.PaketId
    if (-not $id) { $id = [string]$Record.Ziel }
    if (-not (Test-WingetId $id)) { return [pscustomobject]@{ Status = 'fehlgeschlagen'; Text = ('Ungültige Paketkennung im Protokoll: {0}' -f $id) } }
    $exe = Find-Winget
    if (-not $exe) { return [pscustomobject]@{ Status = 'aktiv'; Text = 'winget ist auf diesem PC nicht verfügbar; später erneut versuchen oder von Hand deinstallieren.' } }
    $da = Test-WingetPaketInstalliert $exe $id
    if ($da -eq $false) { return [pscustomobject]@{ Status = 'übersprungen'; Text = ('{0} ist nicht mehr installiert; nichts verändert.' -f $id) } }
    if ($null -eq $da) { return [pscustomobject]@{ Status = 'aktiv'; Text = ('{0}: winget kann den Zustand nicht feststellen; nichts verändert, später erneut versuchen.' -f $id) } }
    $r = Invoke-Winget $exe ('uninstall --id {0} -e --silent --accept-source-agreements --disable-interactivity' -f $id) $script:WingetFristEntfSek
    if ($r.TimedOut) { return [pscustomobject]@{ Status = 'aktiv'; Text = ('{0}: Deinstallation nach {1} Minuten abgebrochen; später erneut versuchen.' -f $id, [int]($script:WingetFristEntfSek / 60)) } }
    if ([int64]$r.ExitCode -eq 0 -or (Format-WingetCode $r.ExitCode) -eq $script:WingetNeustartFertig) { return [pscustomobject]@{ Status = 'rückgängig'; Text = ('{0} deinstalliert' -f $id) } }
    return [pscustomobject]@{ Status = 'aktiv'; Text = ('{0}: Deinstallation fehlgeschlagen, {1}; später erneut versuchen.' -f $id, (Get-WingetFehlerText $r)) }
}
#endregion
