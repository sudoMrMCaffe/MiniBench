# =====================================================================================
#                                     OPTIMIERUNG (ab v2.8)
# =====================================================================================
# Reihenfolge: Vorbereitung (Benutzer, Bedingungen, Kennzahlen vorher), auf Wunsch alte Wiederherstellungspunkte löschen,
# Wiederherstellungspunkt, dann die Kategorien in Katalogreihenfolge (Bereinigung und Grafiktreiber zuletzt), zum Schluss
# Kennzahlen nachher und Zusammenfassung.

# Schritt des Modulvertrags, zu dem ein Eintrag gehört (Absicherung und Rückgängig)
function Get-OptStepKey($Entry) {
    if ($Entry.Kat -eq 'Grafik') { return 'Grafiktreiber' }
    if ($Entry.Risiko -eq 'Aendern') { return 'Einstellungen' }
    if ($Entry.Kat -eq 'Bereinigung') { return 'Bereinigung' }
    return 'Entfernen'
}

function Add-OptLines($Results) {
    $Results | Select-Object @{ n = 'Eintrag'; e = { $_.Titel } }, Ergebnis, @{ n = 'Änderungen'; e = { $_.Aenderungen } }, @{ n = 'Stufe'; e = { Get-RiskLabel $_.Risiko } }, Details | Out-Report
}

if ($ModOpt) {
    if (-not $script:ChangeLog) { Start-ChangeLog }
    $script:OptSel = @($script:OptSelIds | ForEach-Object { Get-OptEntry $_ } | Where-Object { $_ })

    Invoke-Section 'Optimierung: Vorbereitung' {
        $envO = Get-OptEnvironment -Neu
        Add-Line ('  Gewählt: {0} Einträge aus {1} Kategorien (Katalog: {2} Einträge).' -f $script:OptSel.Count, @($script:OptSel | ForEach-Object { $_.Kat } | Select-Object -Unique).Count, @(Get-OptEntries).Count)
        if (@($script:OptUnknown).Count) { Add-Line ('  Unbekannt und übergangen (anderer Katalogstand?): {0}' -f (@($script:OptUnknown) -join ', ')) }
        Add-Line ('  Benutzereinstellungen (HKCU) gelten für: {0}{1}' -f $envO.User.Name, $(if (-not $envO.User.Eigen) { ' (angemeldeter Benutzer; Leos Minibench läuft unter einem anderen Konto)' } else { '' }))
        Add-Line ('  Windows-Build {0}, {1}, {2}{3}' -f $envO.Build, $(if ($envO.Desktop) { 'Desktop-PC' } else { 'Notebook' }), $(if ($envO.Domain) { 'Mitglied einer Domäne' } else { 'keine Domäne' }), $(if ($envO.Nvidia) { ', NVIDIA-Grafik' } else { '' }))
        if ($envO.Domain -and @($script:OptSel | Where-Object { $_.Verwaltet }).Count) {
            Add-Finding INFO 'Optimierung' ('Dieser PC ist Mitglied einer Domäne. {0} gewählte Einträge berühren Richtlinien oder zentral verwaltete Einstellungen; Gruppenrichtlinien können sie beim nächsten Abgleich überschreiben.' -f @($script:OptSel | Where-Object { $_.Verwaltet }).Count)
        }
        if ($envO.Neustart) {
            Add-Line '  Ein Neustart steht aus (Updates). Windows-Funktionen, Zusatzfeatures und Apps lassen sich dann oft nicht ändern.'
            Add-Finding INFO 'Optimierung' 'Vor der Optimierung stand ein Neustart aus. Fehlgeschlagene Einträge nach dem Neustart erneut ausführen.'
        }
        $mitF = [bool]@($script:OptSel | Where-Object { @($_.Aktionen | Where-Object { $_.Art -in 'Feature', 'Capability' }).Count }).Count
        $mitA = [bool]@($script:OptSel | Where-Object { @($_.Aktionen | Where-Object { $_.Art -eq 'App' }).Count }).Count
        Show-Sub 'Kennzahlen vor der Optimierung' 'Dienste, Prozesse, Aufgaben' -1
        $script:OptMetricsBefore = Get-OptMetrics -MitFunktionen:$mitF -MitApps:$mitA
        $script:OptMetricOpts = @{ MitFunktionen = $mitF; MitApps = $mitA }
        Hide-Sub
        Add-Line ('  Kennzahlen vorher: {0}' -f (($script:OptMetricsBefore.Keys | ForEach-Object { '{0} {1}' -f $_, $script:OptMetricsBefore[$_] }) -join ', '))
    }

    if ($script:OptSelIds -contains 'Wiederherstellungspunkte') {
        Invoke-Section 'Optimierung: Alte Wiederherstellungspunkte löschen' {
            $r = Invoke-OptEntry (Get-OptEntry 'Wiederherstellungspunkte')
            $script:OptLog.Add($r)
            Add-Line ('  Ergebnis: {0}{1}' -f $r.Ergebnis, $(if ($r.Details) { ', ' + $r.Details } else { '' }))
            # ein Wiederherstellungspunkt der Reparatur in diesem Lauf ist damit auch weg: gleich einen neuen anlegen
            if ($r.Ergebnis -in 'angewendet', 'teilweise' -and $script:RestorePointNo) { Add-Line ('  Der Wiederherstellungspunkt dieses Laufs ({0}) wurde mit gelöscht, es wird ein neuer angelegt.' -f $script:RestorePointNo); $script:RestorePointNo = $null }
        }
    }
    if (-not $OptOhneWiederherstellungspunkt -and -not $script:RestorePointNo) {
        Invoke-Section 'Optimierung: Wiederherstellungspunkt anlegen' {
            Show-Sub 'Wiederherstellungspunkt' 'wird angelegt' -1
            $rp = New-RestorePointLogged 'Optimierung' ('Leos Minibench vor Optimierung {0:dd.MM.yyyy HH:mm}' -f (Get-Date))
            Hide-Sub
            if ($rp.Ok) { $script:RestorePointNo = $rp.Nummer; Add-Line ('  Wiederherstellungspunkt {0}' -f $rp.Text); Add-TestResult 'Optimierung: Wiederherstellungspunkt' 'OK' $rp.Text }
            else {
                Add-Line ('  Wiederherstellungspunkt konnte nicht angelegt werden: {0}' -f $rp.Text)
                Add-TestResult 'Optimierung: Wiederherstellungspunkt' 'Warnung' $rp.Text
                Add-Finding WARNUNG 'Optimierung' ('Vor der Optimierung konnte kein Wiederherstellungspunkt angelegt werden ({0}). Eingriffe wie entfernte Apps lassen sich dann nur von Hand zurückholen; Computerschutz für {1} prüfen.' -f $rp.Text, $env:SystemDrive)
            }
        }
    } elseif ($OptOhneWiederherstellungspunkt -and @($script:OptSel | Where-Object { $_.Risiko -eq 'Eingriff' }).Count) {
        Add-Finding INFO 'Optimierung' 'Die Auswahl enthält Eingriffe ohne automatisches Rückgängig, ein Wiederherstellungspunkt wurde aber bewusst nicht angelegt.'
    }

    foreach ($kat in (Get-OptCategories)) {
        $items = @($script:OptSel | Where-Object { $_.Kat -eq $kat.Key -and $_.Id -ne 'Wiederherstellungspunkte' })
        if (-not $items.Count) { continue }
        $script:OptCurKat = $kat; $script:OptCurItems = $items
        Invoke-Section ('Optimierung: ' + $kat.Titel) {
            $k = $script:OptCurKat
            $res = @()
            $i = 0
            foreach ($e in $script:OptCurItems) {
                $i++
                Show-Sub ('Optimierung: {0}' -f $k.Titel) ('{0} ({1} von {2})' -f $e.Titel, $i, $script:OptCurItems.Count) ([int](($i - 1) * 100 / $script:OptCurItems.Count))
                Write-Checkpoint 'INFO' ('Optimierung {0}' -f $e.Id)
                $r = Invoke-OptEntry $e
                $script:OptLog.Add($r); $res += $r
                Send-GuiEvent 'OPTE' $r.Id $r.Ergebnis $r.Aenderungen $r.Details
            }
            Hide-Sub
            Add-OptLines $res
            $err = @($res | Where-Object { $_.Ergebnis -in 'Fehler', 'teilweise' })
            $chg = @($res | Where-Object { $_.Ergebnis -eq 'angewendet' }).Count
            $same = @($res | Where-Object { $_.Ergebnis -eq 'bereits so' }).Count
            Add-TestResult ('Optimierung: {0}' -f $k.Titel) $(if (@($res | Where-Object { $_.Ergebnis -eq 'Fehler' }).Count) { 'Fehler' } elseif ($err.Count) { 'Warnung' } else { 'OK' }) `
                ('{0} angewendet, {1} bereits so, {2} übersprungen{3}' -f $chg, $same, @($res | Where-Object { $_.Ergebnis -in 'übersprungen', 'nicht vorhanden' }).Count, $(if ($err.Count) { ', {0} mit Fehlern' -f $err.Count } else { '' }))
            foreach ($x in $err) { Add-Finding WARNUNG 'Optimierung' ('{0}: {1}' -f $x.Titel, $x.Details) }
        }
    }

    Invoke-Section 'Optimierung: Ergebnis' {
        Show-Sub 'Kennzahlen nach der Optimierung' 'Dienste, Prozesse, Aufgaben' -1
        $o = $script:OptMetricOpts; if (-not $o) { $o = @{} }
        $script:OptMetricsAfter = Get-OptMetrics @o
        Hide-Sub
        $rows = @(Get-OptMetricRows $script:OptMetricsBefore $script:OptMetricsAfter)
        if ($rows.Count) {
            Add-Sub 'Kennzahlen vorher und nachher (direkt nach der Optimierung, ohne Neustart)'
            $rows | Out-Report
        }
        $log = @($script:OptLog)
        $n = @($log | Where-Object { $_.Ergebnis -in 'angewendet', 'teilweise' }).Count
        $chg = 0; foreach ($x in $log) { $chg += [int]$x.Aenderungen }
        $ein = @($log | Where-Object { $_.Risiko -eq 'Eingriff' -and $_.Ergebnis -in 'angewendet', 'teilweise' }).Count
        Add-Sub 'Zusammenfassung'
        Add-Line ('  {0} von {1} Einträgen angewendet, {2} Einzeländerungen, davon {3} Eingriffe ohne automatisches Rückgängig.' -f $n, $log.Count, $chg, $ein)
        Add-Line ('  Bereits wie gewünscht: {0}, übersprungen (Bedingung oder nicht vorhanden): {1}, mit Fehlern: {2}.' -f @($log | Where-Object { $_.Ergebnis -eq 'bereits so' }).Count, @($log | Where-Object { $_.Ergebnis -in 'übersprungen', 'nicht vorhanden' }).Count, @($log | Where-Object { $_.Ergebnis -in 'Fehler', 'teilweise' }).Count)
        Add-Line '  Änderungen der Stufe Ändern nimmt die Seite Änderungen einzeln zurück; Eingriffe stehen dort mit dem Weg zurück.'
        Add-Line '  Einstellungen von Explorer, Taskleiste und Maus gelten nach dem nächsten Ab- und Anmelden.'
        if ($n) { Add-Finding INFO 'Optimierung' ('{0} Einstellungen angewendet ({1} Einzeländerungen). Rückgängig auf der Seite Änderungen; einige gelten erst nach Abmelden oder Neustart.' -f $n, $chg) }
        $rs = @($script:OptRestart | Select-Object -Unique)
        if ($rs.Count) { foreach ($t in $rs) { $script:RestartNeeded.Add(('Optimierung: {0}' -f $t)) }; Add-Line ('  Neustart nötig für: {0}' -f ($rs -join ', ')) }
        if (@($log | Where-Object { $_.Id -eq 'Ddu' -and $_.Ergebnis -eq 'angewendet' }).Count) { Add-Finding WARNUNG 'Optimierung' 'DDU ist vorbereitet: Beim nächsten Neustart startet Windows im abgesicherten Modus und entfernt alle Grafiktreiber. Danach den aktuellen Grafiktreiber installieren.' }
    }
}
