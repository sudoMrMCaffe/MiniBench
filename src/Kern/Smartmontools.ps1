#region ---------- Vorbereitung: smartmontools ----------
$script:SmartLicense = 'GPL-2.0-or-later'
$script:SmartSource  = 'smartmontools.org, per winget (smartmontools.smartmontools)'
$script:ToolNotes    = New-Object System.Collections.Generic.List[string]

function Find-Smartctl {
    # auf diesem PC installiert (PATH oder Programme): gehört zum PC, nicht zum Stick
    $tools = Get-ToolsDir
    $c = Get-Command smartctl.exe -ErrorAction SilentlyContinue
    if ($c -and -not ($tools -and $c.Source -like ($tools + '*'))) { return $c.Source }
    foreach ($p in @("$env:ProgramFiles\smartmontools\bin\smartctl.exe", "${env:ProgramFiles(x86)}\smartmontools\bin\smartctl.exe")) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    # portabel aus Minibench-Daten\Tools: nur mit passendem Eintrag im Werkzeug-Manifest
    $leg = Register-LegacyTool 'smartctl' @('smartmontools\bin\smartctl.exe', 'smartctl.exe') $script:SmartLicense $script:SmartSource
    if ($leg) { $script:ToolNotes.Add(('smartctl.exe aus Version 2.1 wurde ins Werkzeug-Manifest aufgenommen (SHA-256 {0}…). Ab jetzt läuft nur diese Datei.' -f $leg.SHA256.Substring(0, 12))) }
    $v = Get-VerifiedTool 'smartctl'
    if ($v) { return $v }
    # smartctl.exe neben dem Skript (frühere Ablage) wird nicht mehr ausgeführt
    if ($PSScriptRoot) {
        foreach ($p in @((Join-Path $PSScriptRoot 'smartctl.exe'), (Join-Path $PSScriptRoot 'Tools\smartctl.exe'))) {
            if (Test-Path -LiteralPath $p) { $script:ToolNotes.Add(('{0} liegt außerhalb von Minibench-Daten\Tools und wird nicht ausgeführt. Über "smartmontools holen" neu aufnehmen lassen.' -f $p)); break }
        }
    }
    return $null
}
#endregion

