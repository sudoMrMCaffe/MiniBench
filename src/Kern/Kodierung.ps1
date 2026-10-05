#region ---------- Kodierung prüfen ----------
# Fehlt der Datei das UTF-8-Kennzeichen (BOM), liest Windows PowerShell 5.1 sie als ANSI und die Umlaute
# werden zerstört. Das Skript erkennt das, legt eine korrekt kodierte Kopie an und startet sich daraus neu.
if ('ä' -ne [string][char]0xE4 -and $PSCommandPath) {
    $bytes = [IO.File]::ReadAllBytes($PSCommandPath)
    try   { $txt = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes) }
    catch { $txt = [Text.Encoding]::Default.GetString($bytes) }
    $fixed = Join-Path $env:TEMP ('LeosMinibench_utf8_{0}.ps1' -f $PID)
    [IO.File]::WriteAllText($fixed, $txt.TrimStart([char]0xFEFF), (New-Object Text.UTF8Encoding($true)))
    $pass = @()
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [System.Management.Automation.SwitchParameter]) { if ($kv.Value.IsPresent) { $pass += ('-' + $kv.Key) } }
        else { $pass += ('-' + $kv.Key); $pass += [string]$kv.Value }
    }
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $fixed @pass
    $rc = $LASTEXITCODE
    Remove-Item $fixed -Force -ErrorAction SilentlyContinue
    exit $rc
}
#endregion

