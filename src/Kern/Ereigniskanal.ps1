#region ---------- Ereigniskanal zur grafischen Oberfläche ----------
# Zeilen @@Art|Feld|Feld... auf der Standardausgabe. Ab v2.65 neu: @@ORDNER|Berichtsordner|Arbeitsordner gleich nach
# dem Anlegen des Berichtsordners (die Oberfläche sichert damit Protokolle, wenn ein Lauf ohne Bericht endet).
$script:GuiOut = $null
$script:GuiLog = $null
function Send-GuiEvent {
    param([string]$Kind, [Parameter(ValueFromRemainingArguments = $true)][object[]]$Parts)
    if (-not $script:GuiOut) { return }
    $clean = @($Parts | ForEach-Object { (([string]$_) -replace '[\r\n]+', ' ') -replace '\|', '¦' })
    try { $script:GuiOut.WriteLine('@@' + $Kind + '|' + ($clean -join '|')) } catch { }
}
if ($EventMode) {
    try {
        $script:GuiOut = New-Object IO.StreamWriter([Console]::OpenStandardOutput(), (New-Object Text.UTF8Encoding($false)))
        $script:GuiOut.AutoFlush = $true
    } catch { }
    # Ausgaben als Ereignisse an die Oberfläche senden und mitprotokollieren
    function Write-Host {
        param([Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object, $ForegroundColor, $BackgroundColor, [switch]$NoNewline, $Separator)
        $t = (@($Object) | ForEach-Object { [string]$_ }) -join ' '
        Send-GuiEvent 'LOG' ([string]$ForegroundColor) $t
        if ($script:GuiLog) { try { $script:GuiLog.WriteLine($t) } catch { } }
    }
    function Write-Warning { param([Parameter(Position = 0)][string]$Message) Write-Host ('WARNUNG: ' + $Message) -ForegroundColor Yellow }
}
#endregion

#region ---------- Startphasen (ab v2.6, Roadmap v2.5) ----------
# LeosMinibench.exe nennt in LEOSMINIBENCH_START eine Statusdatei im lokalen TEMP. Jede Phase hängt dort eine Zeile an
# (Zeitstempel|Quelle|Text); das Startfenster der exe zeigt die letzte, die Oberfläche schreibt am Ende Start.log.
# Nur die Oberfläche selbst meldet Phasen, nie ein Arbeitsprozess (-EventMode).
function Write-StartPhase([string]$Text) {
    if ($EventMode -or -not $env:LEOSMINIBENCH_START) { return }
    try { [IO.File]::AppendAllText($env:LEOSMINIBENCH_START, ('{0}|S|{1}' -f [DateTime]::Now.Ticks, ($Text -replace '\|', '/')) + "`r`n", [Text.Encoding]::UTF8) } catch { }
}
Write-StartPhase 'PowerShell bereit, Skript läuft'
#endregion

