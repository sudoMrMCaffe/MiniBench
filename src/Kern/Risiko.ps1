#region ---------- Risikostufen ----------
# Jeder Schritt eines Moduls hat eine Risikostufe. Sie bestimmt, welche Absicherung vor der Ausführung nötig ist:
#   Lesen        verändert nichts am System
#   Aendern      verändert Einstellungen; jede Änderung landet mit Vorher-Wert im Änderungsprotokoll und lässt sich rückgängig machen
#   Eingriff     verändert das System dauerhaft ohne automatisches Rückgängig; Wiederherstellungspunkt vorab, oft Neustart
#   Zerstoerend  vernichtet Daten; nur nach eigener Bestätigung mit der Seriennummer des Ziels
$script:RiskOrder  = @('Lesen', 'Aendern', 'Eingriff', 'Zerstoerend')
$script:RiskLabels = @{ Lesen = 'Lesen'; Aendern = 'Ändern'; Eingriff = 'Eingriff'; Zerstoerend = 'Zerstörend' }

function Get-RiskRank([string]$Level) {
    $i = [array]::IndexOf($script:RiskOrder, [string]$Level)
    if ($i -lt 0) { throw ('Unbekannte Risikostufe: {0}' -f $Level) }
    return $i
}

function Get-RiskLabel([string]$Level) {
    if ($script:RiskLabels.ContainsKey([string]$Level)) { return $script:RiskLabels[[string]$Level] }
    return [string]$Level
}

# Höchste Stufe aus einer Liste; leere Liste ergibt Lesen
function Get-MaxRisk($Levels) {
    $max = 0
    foreach ($l in @($Levels)) { if ($l) { $r = Get-RiskRank $l; if ($r -gt $max) { $max = $r } } }
    return $script:RiskOrder[$max]
}

# Seriennummern vergleichen, ohne dass Leerzeichen, Bindestriche oder Groß- und Kleinschreibung stören
function ConvertTo-SerialKey([string]$Serial) { return (([string]$Serial) -replace '[\s\-_.]', '').ToUpperInvariant() }

# Freigabe für zerstörende Schritte: Die eingegebene Seriennummer muss vollständig zum Ziel passen.
# Platzhalter wie "Default string" oder leere Seriennummern werden nie akzeptiert, weil sie das Ziel nicht eindeutig benennen.
function Test-DestructiveConfirmation {
    param([string]$ExpectedSerial, [string]$GivenSerial)
    $exp = ConvertTo-SerialKey $ExpectedSerial
    $giv = ConvertTo-SerialKey $GivenSerial
    if ($exp.Length -lt 4 -or $exp -match '^(0+|F+|DEFAULTSTRING|TOBEFILLEDBYOEM|SYSTEMSERIALNUMBER|NONE|NA|UNKNOWN)$') { return $false }
    return ($exp -ceq $giv)
}

# Prüft vor einem Schritt, ob die Absicherung seiner Stufe vorhanden ist. Rückgabe: leer = darf laufen, sonst Begründung.
function Get-RiskBlocker {
    # Eingriff ohne Wiederherstellungspunkt bleibt erlaubt (Schalter -OhneWiederherstellungspunkt), der Bericht vermerkt es.
    param([string]$Level, [string]$ExpectedSerial = '', [string]$GivenSerial = '', [bool]$SystemDisk = $false)
    if ((Get-RiskRank $Level) -eq 3) {
        if ($SystemDisk) { return 'Das Systemlaufwerk des laufenden Windows ist für zerstörende Schritte gesperrt.' }
        if (-not (Test-DestructiveConfirmation $ExpectedSerial $GivenSerial)) { return 'Die eingegebene Seriennummer passt nicht zum gewählten Ziel.' }
    }
    return ''
}
#endregion
