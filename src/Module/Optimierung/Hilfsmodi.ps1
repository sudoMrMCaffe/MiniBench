# =====================================================================================
#        OPTIMIERUNG UND TOOLS: Hilfsmodi der Oberfläche (ab v2.8, Softwarepakete ab v3.53, kein Bericht)
# =====================================================================================
# Zustand aller Einträge: @@OPTZ|Id|Zustand|Text je Eintrag, @@RESULT|Anzahl
if ($OptimierungZustand) {
    $envO = Get-OptEnvironment
    $script:OptCache = [ordered]@{}
    Write-Host ('Benutzereinstellungen gelten für: {0}' -f $envO.User.Name)
    $n = 0
    foreach ($e in (Get-OptEntries)) {
        $s = $null
        try { $s = Get-OptEntryState $e $envO } catch { $s = [pscustomobject]@{ Id = $e.Id; Zustand = 'nicht prüfbar'; Text = $_.Exception.Message } }
        Send-GuiEvent 'OPTZ' $s.Id $s.Zustand $s.Text
        $n++
    }
    Send-GuiEvent 'RESULT' $n
    exit 0
}
# Seite Tools (ab v3.53): Softwarepakete über winget, je Paket @@PAKET, am Ende @@RESULT|installiert|bereits|fehlgeschlagen
if ($SoftwareInstallieren) {
    $r = Invoke-SoftwarePakete $SoftwareInstallieren
    Send-GuiEvent 'RESULT' $r.Installiert $r.Bereits $r.Fehler
    exit $(if ($r.Fehler) { 1 } else { 0 })
}
if ($OptWerkzeugeHolen) {
    $r = Install-OptTools
    foreach ($m in $r.Meldungen) { Write-Host $m }
    foreach ($t in @($script:ToolIssues | Select-Object -Unique)) { Write-Host ('WARNUNG: ' + $t) }
    Send-GuiEvent 'RESULT' $(if ($r.Ok) { '1' } else { '0' })
    exit $(if ($r.Ok) { 0 } else { 1 })
}
