#region ---------- Administratorrechte ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# Vergleich, Import, Dashboard, Datenpflege sowie Abgleich, Entfernen, Umbenennen und MedianAktualisieren
# arbeiten nur im Datenordner und brauchen keine Administratorrechte
if (-not $isAdmin -and -not $Vergleich -and -not $ImportOrdner -and -not $Datenpflege -and -not $Dashboard -and -not $DashboardExport -and -not $DashboardSysteme -and -not $Abgleich -and -not $Entfernen -and -not $Umbenennen -and -not $MedianAktualisieren) {
    if (-not $PSCommandPath) { return }
    # Netzlaufwerke sind im Administratorkontext nicht verbunden: Skript und Datenordner als UNC-Pfad weitergeben
    function ConvertTo-Unc([string]$Path) {
        if ($Path -match '^[A-Za-z]:') {
            try { $drv = Get-PSDrive -Name $Path.Substring(0, 1) -ErrorAction Stop; if ($drv.DisplayRoot -like '\\*') { return $drv.DisplayRoot.TrimEnd('\') + $Path.Substring(2) } } catch { }
        }
        return $Path
    }
    if (-not $DatenDir -and $PSScriptRoot) { $DatenDir = Join-Path $PSScriptRoot 'Minibench-Daten' }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f (ConvertTo-Unc $PSCommandPath)))
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Key -eq 'DatenDir') { continue }
        if ($kv.Value -is [System.Management.Automation.SwitchParameter]) { if ($kv.Value.IsPresent) { $argList += ('-{0}' -f $kv.Key) } }
        else { $argList += ('-{0}' -f $kv.Key); $argList += ('"{0}"' -f $kv.Value) }
    }
    if ($DatenDir) { $argList += '-DatenDir'; $argList += ('"{0}"' -f (ConvertTo-Unc $DatenDir).TrimEnd('\')) }
    try { Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList -ErrorAction Stop }
    catch {
        try { Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show(('Start mit Administratorrechten nicht möglich: ' + $_.Exception.Message), 'Leos Minibench', 'OK', 'Warning') } catch { }
    }
    return
}
#endregion

