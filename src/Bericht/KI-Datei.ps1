#region ---------- Datenschutz für die KI-Datei ----------
function Protect-Text([string]$Text) {
    if (-not $Text) { return $Text }
    $t = $Text
    $generic = @('USER', 'ADMIN', 'ADMINISTRATOR', 'BENUTZER', 'OWNER', 'BESITZER', 'PC', 'GAST', 'GUEST', 'SYSTEM')
    foreach ($u in @($script:UserNames | Where-Object { $_ } | Select-Object -Unique)) {
        $e = [regex]::Escape($u)
        $t = [regex]::Replace($t, '(?i)(\\Users\\|\\Benutzer\\)' + $e + '(?=\\|\b)', '$1<BENUTZER>')
        $t = [regex]::Replace($t, '(?i)(\\)' + $e + '(?![A-Za-z0-9])', '$1<BENUTZER>')
        if ($u.Length -ge 5 -and $generic -notcontains $u.ToUpperInvariant()) { $t = [regex]::Replace($t, '(?i)(?<![A-Za-z0-9])' + $e + '(?![A-Za-z0-9])', '<BENUTZER>') }
    }
    foreach ($kv in @($script:Private.GetEnumerator() | Sort-Object { $_.Key.Length } -Descending)) {
        $e = [regex]::Escape($kv.Key)
        $rx = $(if ($kv.Key -match '^\w' -and $kv.Key -match '\w$') { '(?i)(?<![A-Za-z0-9])' + $e + '(?![A-Za-z0-9])' } else { '(?i)' + $e })
        $t = [regex]::Replace($t, $rx, $kv.Value.Replace('$', '$$'))
    }
    if ($env:COMPUTERNAME) { $t = [regex]::Replace($t, '(?i)(?<![A-Za-z0-9])' + [regex]::Escape($env:COMPUTERNAME) + '(?![A-Za-z0-9])', '<PC>') }
    $t = [regex]::Replace($t, '\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b', '<MAC>')
    $t = [regex]::Replace($t, 'S-1-5-21-\d+-\d+-\d+(-\d+)?', '<SID>')
    $t = [regex]::Replace($t, '[\w.+-]+@[\w-]+\.[\w.-]+', '<E-MAIL>')
    return $t
}

function Add-PrivateFromRaw {
    foreach ($f in @(Get-ChildItem $RawDir -Filter 'smartctl_*.txt' -ErrorAction SilentlyContinue)) {
        $c = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($m in [regex]::Matches([string]$c, '(?im)^(Serial [Nn]umber|LU WWN Device Id|IEEE EUI-64|Logical Unit id):\s*(.+?)\s*$')) { Add-Private $m.Groups[2].Value 'SERIENNR' }
    }
}
#endregion

#region ---------- KI-Analysedatei ----------
function ConvertFrom-HtmlToText([string]$Html) {
    if (-not $Html) { return '' }
    $h = [regex]::Replace($Html, '(?is)<(script|style)[^>]*>.*?</\1>', '')
    $h = [regex]::Replace($h, '(?i)<br\s*/?>|</(p|tr|h\d|div|li|table|thead|tbody)>', "`n")
    $h = [regex]::Replace($h, '(?i)</t[dh]>', ' | ')
    $h = [regex]::Replace($h, '<[^>]+>', '')
    $h = [System.Net.WebUtility]::HtmlDecode($h)
    $lines = $h -split "`n" | ForEach-Object { (($_ -replace '\s+', ' ').Trim()).Trim('|').Trim() } | Where-Object { $_ }
    return ($lines -join "`r`n")
}

# In smartctl-Ausgaben Grenzwerte als solche markieren, damit sie nicht als gemessene Temperatur gelesen werden
function Add-SmartLimitMarks([string]$Text) {
    if (-not $Text) { return $Text }
    $t = [regex]::Replace($Text, '(?m)^([^\r\n]*Comp\. Temperature Time[^\r\n]*?)[ \t]*(\r?)$', '$1   [Minuten oberhalb des Grenzwerts, keine Temperatur]$2')
    $rx = '(?m)^((?![^\r\n]*\[Minuten)[^\r\n]*(Temp\. Threshold|Temperature Threshold|Specified Max Operating Temperature|Min/Max recommended Temperature|Min/Max Temperature Limit)[^\r\n]*?)[ \t]*(\r?)$'
    return [regex]::Replace($t, $rx, '$1   [Grenzwert laut Hersteller, keine Messung]$3')
}

function Get-KiPrompt {
    $rep = ''
    try { $c = Get-ModuleContract 'Reparatur'; if ($c) { $rep = (@($c.Schritte | ForEach-Object { $_.Titel }) -join ', ') } } catch { }
    $text = @'
AUFTRAG AN DIE KI (bitte zuerst lesen)

Du bist ein erfahrener Windows- und PC-Hardware-Techniker. Diese Datei enthält Bericht und Rohdaten eines Laufs des Werkzeugs Leos Minibench auf einem Windows-PC. Werte alles gründlich aus, finde die Ursachen von Problemen und zeige, wie sie sich beheben lassen.

Vorgehen
1. Lies zuerst ÜBERBLICK, BEFUNDE und TESTERGEBNISSE, danach Details und Rohdaten.
2. Prüfe die automatische Bewertung kritisch: bestätige, relativiere oder widerlege jeden wichtigen Befund anhand der Rohdaten.
3. Suche Zusammenhänge, zum Beispiel zwischen Bluescreen-Codes und RAM-Takt oder XMP/EXPO, zwischen Datenträgerereignissen und SMART-Werten, zwischen Abstürzen, Lasttest und Temperaturen.
4. Suche nach Auffälligkeiten, die das Werkzeug nicht als Befund markiert hat.
5. Belege jede Aussage mit der konkreten Stelle (Abschnitt, Messwert, Ereignis-ID, Zeitpunkt). Kennzeichne Vermutungen ausdrücklich.

Antwortformat (auf Deutsch, sachlich und knapp)
A. Kurzfazit: Zustand des PCs in höchstens fünf Sätzen mit Ampel (grün, gelb, rot).
B. Probleme nach Dringlichkeit als Tabelle: Problem, Beleg aus den Daten, wahrscheinliche Ursache, Sicherheit der Einschätzung (hoch, mittel, niedrig).
C. Lösung je Problem aus B, nummeriert vom einfachsten und risikoärmsten zum aufwendigsten. Je Schritt immer beide Wege:
   1. In der Oberfläche: der genaue Klickpfad (Windows-Einstellungen, Systemsteuerung, Geräte-Manager, Datenträgerverwaltung, BIOS/UEFI mit dem üblichen Menünamen) oder die passende Reparatur in Leos Minibench (Seite Reparatur, Liste unten).
   2. Sofort per PowerShell: ein fertiger Befehlsblock zum Kopieren in PowerShell als Administrator, der die Änderung direkt umsetzt. Werte aus den Daten einsetzen (Laufwerksbuchstaben, Gerätenamen, Dienstnamen, Energieplan-GUIDs), keine Platzhalter, die erst ersetzt werden müssen; anonymisierte Angaben in spitzen Klammern nie in Befehle übernehmen. Danach eine Zeile, die den Erfolg prüft, und der Befehl zum Rückgängigmachen.
   Geht ein Schritt nicht per Befehl (BIOS-Einstellung, Hardwaretausch, Treiber von der Herstellerseite), das ausdrücklich sagen und nur den Weg in der Oberfläche nennen. Dazu je Schritt: Risiko, ob ein Neustart nötig ist und woran man den Erfolg erkennt. Vor Schritten mit Datenverlustrisiko auf eine Sicherung hinweisen.
   Zum Schluss von C alle PowerShell-Befehle noch einmal in einem einzigen Block, in der empfohlenen Reihenfolge, mit Kommentarzeilen je Schritt. Befehle mit Datenverlust- oder Startrisiko darin nur auskommentiert und mit Warnung.
D. Leistung: Einordnung der Benchmark-Werte gegenüber Referenz, Vergleichssystemen und Hardwareklasse, Engpässe, ob sich eine Aufrüstung lohnt und welche.
E. Offene Punkte: welche Angaben fehlen und welche zusätzlichen Tests oder Daten (mit Befehl) die Diagnose absichern würden. Fragen an den Nutzer ans Ende stellen.

Regeln zur Gewichtung (verbindlich)
1. Grenzwerte sind keine Messwerte. Warning und Critical (Composite) Temperature, Temp. Threshold, Thermal Sensor ... Limit und ähnliche Angaben sind Vorgaben des Herstellers. Sie stehen gesondert unter GRENZWERTE oder sind in den Rohdaten mit [Grenzwert laut Hersteller] markiert. Nie als gemessene Temperatur werten und nie als Überhitzung deuten.
2. Systemdateien: Die Einordnung von DISM und SFC steht vorab im Abschnitt SYSTEMDATEIEN. Einzelne Hash-Abweichungen bei intaktem Komponentenspeicher (DISM Healthy) sind meist folgenlos und kein Grund für Neuinstallation, Inplace-Upgrade oder dringende Maßnahmen. Dringend ist nur ein beschädigter Komponentenspeicher (Repairable, NonRepairable) oder ein Zusammenhang mit tatsächlichen Beschwerden.
3. Reihenfolge der Dringlichkeit: Datenverlust (SMART, Datenträgerfehler, Controller-Resets) vor Stabilität (Bluescreens, WHEA, Rechen- oder Bitfehler, Kernel-Power 41 im Betrieb) vor Leistung (Drosselung, Benchmark) vor Komfort und Kosmetik.
4. INFO-Befunde nur mit zusätzlichem Beleg aus den Rohdaten zu einem Problem aufwerten. Werte mit dem Vermerk unplausibel sind verworfene Sensorfehler, keine Messwerte.
5. Lizenz und Aktivierung nicht bewerten; der Status steht nur zur Information im Inventar.
6. Die ACPI-Thermalzone ist keine CPU-Temperatur. Bleibt sie konstant (zum Beispiel 16,9 °C), ist sie ohne Aussagekraft.

Hinweise zu den Daten
1. Persönliche Angaben (Seriennummern, Benutzer- und Computernamen, MAC-Adressen) sind gegebenenfalls durch Platzhalter in spitzen Klammern ersetzt, zum Beispiel <SERIENNR-2>. Gleiche Platzhalter bedeuten gleiche Werte.
2. CPU-Temperatur, CPU-Leistung und Lüfter kommen von LibreHardwareMonitor (Quelle LHM), sofern verfügbar. Werte mit Quelle ACPI stammen aus der Thermalzone des Mainboards und sind keine Kerntemperatur.
2a. CPU-Takt: Takt laut Windows = Nenntakt x Prozessorleistung (wie im Task-Manager). Der höchste Kerntakt laut LibreHardwareMonitor steht getrennt daneben.
3. Grafik: WinSAT DWM (Speicherdurchsatz, Desktop-Komposition) misst nur die Einheit, die den Desktop ausgibt. Der eigene Rendertest (Direct3D 11, ab v2.6) misst jede Grafikeinheit einzeln mit fester Szene ohne VSync: Ø Bilder/s, 1-%-Low (langsamste 1 % der Bildzeiten) und Punktzahl (Bilder/s x Pixel / 10 000). Bilder/s sind nur bei gleicher Auflösung vergleichbar, die Punktzahl auch über Auflösungen. Im Lasttest läuft derselbe Test als Dauerlast auf den gewählten Grafikeinheiten gleichzeitig. Vor jeder Messung prüft eine Gegenprobe mit einem Viertel der Rechenlast, ob eine Bildratengrenze (Treiber) oder der Prozessor bremst; ein solcher Befund macht die Bilder/s unvergleichbar.
3a. Ein Treiber-Reset (TDR, Ereignis 4101 Display oder DXGI_ERROR_DEVICE_REMOVED/HUNG) und Bildfehler (Prüfbild weicht vom Referenzbild ab) unter Last sind ernste Stabilitätszeichen der Grafik (Treiber, Übertaktung, Temperatur, Netzteil, Defekt). Ein Abfall der Bilder/s über die Dauer des Lasttests deutet auf Drosselung.
3b. Sensoren während des Benchmarks (ab v2.7) zeigen je Abschnitt Höchstwerte unter kurzer Last. Liegt die CPU dabei an TjMax, können die Prozessorwerte durch Drosselung niedriger sein; einen Drosselnachweis liefert nur der Lasttest. Lasttestergebnisse (Rechendurchläufe, Unterbrechungen) sind erst ab v2.67 untereinander vergleichbar; das Rechenwerk des Benchmarks ist seit 2.6 unverändert.
3b. "Unterbrechungen der Last" (ab v2.66) misst, wie oft das Messprogramm selbst kurz stand (Speicherbereinigung von .NET, Treiber, Systemlatenz). Einbrüche der Bilder/s oder der CPU-Auslastung zur selben Zeit sind dann kein Hardwarefehler.
4. Der RAM-Test unter Windows erreicht nicht jeden Speicherbereich. Ein fehlerfreier Lauf schließt RAM-Fehler nicht aus.
5. Kernel-Power 41 ohne Bluescreen-Code heißt nur, dass Windows nicht sauber beendet wurde. Der Bericht ordnet jedes Ereignis anhand des letzten Ereignisses vor dem Neustart ein (Betrieb, Standby, Herunterfahren, Ein/Aus-Taste).
6. Datenträgernummern in Ereignissen gelten für den Zeitpunkt des Ereignisses und können sich seitdem geändert haben.
7. Index 100 entspricht dem typischen Wert der Hardwareklasse. Referenz 100 % ist das angegebene Referenzsystem.
8. Win32_OperatingSystem.InstallDate zeigt das letzte Funktionsupdate. Das Datum der Erstinstallation steht im Abschnitt System und Betriebssystem.
9. Auf Geräten mit Grafikkarte und Prozessorgrafik nennt der Benchmark je Wert die gemessene Grafikeinheit. Werte der Prozessorgrafik sagen nichts über die Grafikkarte.
10. Akku: Verschleiß = 1 minus volle Ladekapazität durch Designkapazität. Ab 30 % spürbar kürzere Laufzeit, ab 50 % Austausch sinnvoll.
'@
    if ($rep) { $text += "`r`n11. Reparaturen in Leos Minibench (Seite Reparatur, mit Wiederherstellungspunkt und Protokoll): $rep." }
    return $text
}

function New-KiExport {
    param([string]$Path, $Sorted, [int]$NK, [int]$NW, [int]$NI, [datetime]$Start, [datetime]$End, [switch]$Compact, [int]$RawBudget = 260000)
    $sb = New-Object System.Text.StringBuilder
    $line = '#' * 100
    $add = { param([string]$t) [void]$sb.AppendLine($t) }
    $head = { param([string]$t) [void]$sb.AppendLine(''); [void]$sb.AppendLine($line); [void]$sb.AppendLine('#  ' + $t); [void]$sb.AppendLine($line) }
    & $add $line
    & $add ('#  LEOS MINIBENCH {0}: DATEN FÜR DIE KI-AUSWERTUNG{1}' -f $ScriptVersion, $(if ($Compact) { ' (KURZFASSUNG OHNE ROHDATEN)' } else { '' }))
    & $add $line
    & $add ''
    & $add (Get-KiPrompt)

    & $head 'ÜBERBLICK'
    & $add ('Erstellt              : {0:dd.MM.yyyy HH:mm} bis {1:HH:mm} Uhr (Dauer {2:hh\:mm\:ss})' -f $Start, $End, ($End - $Start))
    & $add ('Module                : {0}' -f (Get-ModeLabel))
    & $add ('Ergebnis              : {0} kritisch, {1} Warnungen, {2} Hinweise' -f $NK, $NW, $NI)
    if ($script:Stability) { & $add ('Zuverlässigkeit       : {0}{1}' -f $script:Stability.Text, $(if ($script:Stability.Ursachen.Count) { '; ' + ($script:Stability.Ursachen -join ', ') } else { '' })) }
    foreach ($k in $script:Facts.Keys) { & $add (('{0,-22}: {1}' -f $k, ([string]$script:Facts[$k] -replace "`r?`n", '; '))) }

    & $head 'BEFUNDE (automatische Bewertung)'
    if ($Sorted.Count) { foreach ($f in $Sorted) { & $add ('[{0}] {1}: {2}' -f $f.Stufe, $f.Bereich, $f.Befund) } } else { & $add 'Keine Auffälligkeiten gefunden.' }

    if ($script:TestResults.Count) {
        & $head 'TESTERGEBNISSE'
        foreach ($t in $script:TestResults) { & $add ('{0} | {1} | {2}' -f $t.Test, $t.Ergebnis, $t.Details) }
    }

    if ($script:IntegrityInfo) {
        & $head 'SYSTEMDATEIEN (Einordnung vorab, siehe Regel 2)'
        & $add ('Einordnung: {0}' -f $script:IntegrityInfo.Kategorie)
        & $add ('DISM (Komponentenspeicher): {0}' -f $script:IntegrityInfo.Dism)
        & $add ('SFC /verifyonly: {0}{1}' -f $script:IntegrityInfo.Sfc, $(if ($script:IntegrityInfo.Dateien) { ', {0} betroffene Dateien' -f $script:IntegrityInfo.Dateien } else { '' }))
        & $add ('Bedeutung: {0}' -f $(switch ($script:IntegrityInfo.Kategorie) {
            'keine Verletzungen' { 'Systemdateien in Ordnung.' }
            'Abweichungen, Speicher intakt' { 'Einzelne Hash-Abweichungen bei intaktem Komponentenspeicher: meist folgenlos; sfc /scannow behebt sie bei Bedarf. Kein Grund für Neuinstallation.' }
            'reparierbar' { 'Komponentenspeicher beschädigt, aber reparierbar: DISM /Online /Cleanup-Image /RestoreHealth, danach sfc /scannow.' }
            'nicht reparierbar' { 'Nicht reparierbar: Inplace-Upgrade mit dem Installationsmedium.' }
            default { 'Komponentenspeicher nicht geprüft, Ergebnis nur eingeschränkt belastbar.' } }))
    }

    if (@($script:BatteryInfo).Count) {
        & $head 'AKKU'
        foreach ($b in @($script:BatteryInfo)) {
            & $add ('{0}: Designkapazität {1}, volle Ladekapazität {2}, Verschleiß {3}, Ladezyklen {4}, geschätzte Laufzeit {5}{6}, Quelle {7}' -f $b.Name,
                $(if ($b.DesignmWh) { '{0:N0} mWh' -f $b.DesignmWh } else { 'n/v' }), $(if ($b.VollmWh) { '{0:N0} mWh' -f $b.VollmWh } else { 'n/v' }),
                $(if ($null -ne $b.VerschleissProzent) { '{0:N1} %' -f $b.VerschleissProzent } else { 'n/v' }), $(if ($null -ne $b.Zyklen) { '{0:N0}' -f $b.Zyklen } else { 'nicht gemeldet' }),
                $(if ($b.LaufzeitVoll) { Format-Duration $b.LaufzeitVoll } else { 'n/v' }), $(if ($b.LaufzeitDesign) { ' (im Neuzustand {0})' -f (Format-Duration $b.LaufzeitDesign) } else { '' }), $b.Quelle)
            $hist = @($b.Verlauf | Where-Object { $_.VollmWh })
            if ($hist.Count) {
                & $add 'Kapazitätsverlauf (Zeitraum;volle Ladung mWh;Design mWh)'
                $step = [math]::Max(1, [int][math]::Ceiling($hist.Count / 20))
                for ($i = 0; $i -lt $hist.Count; $i += $step) { & $add ('{0};{1:0};{2:0}' -f $hist[$i].Zeitraum, $hist[$i].VollmWh, $hist[$i].DesignmWh) }
            }
        }
    }

    if ($script:BenchResults.Count -or $script:BenchDisks.Count) {
        & $head 'BENCHMARK'
        & $add $(if ($script:RefSavedNow -and -not (Test-HasReference)) { 'Dieser Lauf wurde als Referenz gespeichert (ab dem nächsten Lauf 100 %)' }
            elseif ($script:RefSavedNow) { 'Referenz 100 % = {0}; dieser Lauf wurde als neue Referenz gespeichert (gilt ab dem nächsten Lauf)' -f $script:Ref.Name } elseif (Test-HasReference) { 'Referenz 100 % = {0}' -f $script:Ref.Name } else { 'Keine Referenz festgelegt (Prozentwerte entfallen)' })
        if ($script:BenchRefSummary) { & $add $script:BenchRefSummary }
        & $add 'Gruppe;Messung;Wert;Einheit;Index;Status;Referenz;Vergleich frühere Läufe;Hinweis'
        foreach ($b in $script:BenchResults) { & $add (('{0};{1};{2};{3};{4};{5};{6};{7};{8}' -f $b.Gruppe, $b.Messung, ([math]::Round([double]$b.Wert, 2)).ToString($script:Inv), $b.Einheit, $b.Index, $b.Status, $b.Referenz, $b.Vergleich, $b.Hinweis)) }
        if (@($script:BenchRefRows).Count) {
            & $add ''
            & $add ('Referenzwerte ({0}): Messgröße;Referenz;Herkunft' -f $script:Ref.Name)
            foreach ($r in @($script:BenchRefRows)) { & $add ('{0};{1};{2}' -f $r.'Messgröße', $r.Referenz, $r.Herkunft) }
        }
        if ($script:BenchDisks.Count) {
            & $add ''
            & $add 'Laufwerk;Klasse;Lesen MB/s;Schreiben MB/s;4K QD1 IOPS;4K 8 Threads IOPS;4K schreiben IOPS;Index;Referenz;Status;Hinweis'
            foreach ($d in $script:BenchDisks) { & $add (('{0};{1};{2:0};{3:0};{4:0};{5:0};{6:0};{7};{8};{9};{10}' -f $d.Laufwerk, $d.Klasse, [double]$d.SR, [double]$d.SW, [double]$d.R1, [double]$d.R8, [double]$d.W1, $d.Index, $d.Referenz, $d.Status, $d.Hinweis)) }
        }
    }

    if ($script:CmpRows.Count) {
        & $head 'VERGLEICH MIT BEREITS GEPRÜFTEN SYSTEMEN'
        $i = 0
        foreach ($s in $script:CmpSystems) { $i++; & $add ('System {0}: {1} (Messung vom {2})' -f $i, $s.Name, $s.Datum) }
        & $add ('Messung;Dieser PC;' + ((1..$script:CmpSystems.Count | ForEach-Object { "System $_" }) -join ';') + ';Reihenfolge niedrig nach hoch;Rang in der Datenbank')
        foreach ($r in $script:CmpRows) {
            $cells = for ($k = 0; $k -lt $script:CmpSystems.Count; $k++) { $v = $r.Werte[$k]; if ($null -ne $v) { $rel = Get-RelText $r.Dieses $v $r.LowerBetter; (Format-Metric $v $r.Format $r.Einheit) + $(if ($rel) { ' (' + $rel + ')' } else { '' }) } else { '' } }
            & $add (('{0};{1};{2};{3};{4}' -f $r.Messung, (Format-Metric $r.Dieses $r.Format $r.Einheit), ($cells -join ';'), (Get-CompareOrderText $r), $r.Rang))
        }
        & $add 'Prozent in Klammern: Abstand des anderen Systems zu diesem PC, positiv bedeutet besser.'
    }

    # ab v2.7: Sensoren während des Benchmarks, je Abschnitt (Werte unter Last kurzer Messungen, kein Drosselnachweis)
    if (@($script:BenchSensorRows).Count) {
        & $head 'SENSOREN WÄHREND DES BENCHMARKS'
        & $add (Get-SensorSourceText)
        & $add 'Abschnitt;Dauer;Messpunkte;CPU-Takt Ø MHz;CPU-Takt max MHz;höchster Kerntakt max MHz;CPU max °C;CPU-Paket max W;GPU max °C;GPU-Takt Ø MHz;GPU max W;Prozessorgrafik max °C;Prozessorgrafik max W;Lüfter max U/min;Datenträger max °C'
        foreach ($r in @($script:BenchSensorRows)) {
            $v = @($r.Teil, $r.Dauer, $r.Messpunkte, $r.CpuMhzAvg, $r.CpuMhzMax, $r.KernMax, $r.CpuTMax, $r.CpuWMax, $r.GpuTMax, $r.GpuMhzAvg, $r.GpuWMax, $r.IGpuTMax, $r.IGpuWMax, $r.FanMax, $r.DiskTMax)
            & $add (($v | ForEach-Object { if ($null -eq $_) { '' } elseif ($_ -is [double]) { ([math]::Round($_, 1)).ToString($script:Inv) } else { [string]$_ } }) -join ';')
        }
        if ($script:BenchSens -and $script:BenchSens.TjMax) { & $add ('TjMax laut CPU: {0:N0} °C' -f $script:BenchSens.TjMax) }
    }

    if ($script:LoadParts.Count -or $script:LoadSeries.Count) {
        & $head 'LASTTEST'
        if ($script:LoadSummary) { & $add $script:LoadSummary }
        foreach ($p in $script:LoadParts) { & $add ('{0} | {1} | {2} | {3}' -f $p.Komponente, $p.Dauer, $p.Ergebnis, $p.Details) }
        if ($script:LoadAbort) { & $add ('Abbruch nach {0} s: {1}' -f $script:LoadAbort.T, $script:LoadAbort.Grund) }
        if ($script:LoadThrottle) {
            & $add ('Drosselnachweis: {0} ({1})' -f $script:LoadThrottle.Status, $script:LoadThrottle.Befund)
            foreach ($b in $script:LoadThrottle.Belege) { & $add ('  ' + $b) }
        }
        if ($script:LoadSeries.Count) {
            $S = @($script:LoadSeries)
            # Thermalzone nur, wenn sie sich bewegt und keine echte CPU-Temperatur da ist; Prozessorgrafik nur, wenn vorhanden
            $tzMoves = @($S | Where-Object { $_.Temp } | ForEach-Object { $_.Temp } | Select-Object -Unique).Count -gt 1
            $realT = @($S | Where-Object { $null -ne $_.CpuTemp -and $_.CpuTempQ -ne 'ACPI' }).Count -gt 0
            $withTz = $tzMoves -and -not $realT
            $withIg = @($S | Where-Object { $null -ne $_.IGpuTemp -or $null -ne $_.IGpuW }).Count -gt 0
            $cols = @('Sekunde', 'CPU-Takt MHz', 'CPU-Last %', 'Frequenzgrenze %') + $(if ($withTz) { @('Thermalzone °C') } else { @() }) + @('CPU °C', 'Quelle CPU-Temperatur', 'höchster Kerntakt MHz', 'CPU-Paket W', 'GPU °C', 'GPU MHz', 'GPU W') + $(if ($withIg) { @('Prozessorgrafik °C', 'Prozessorgrafik W') } else { @() }) + @('Lüfter U/min', 'Datenträger °C', 'Datenträger MB/s', 'CPU-Last aktiv')
            & $add ''
            & $add ('Verlauf ({0})' -f ($cols -join ';'))
            if (-not $withTz -and @($S | Where-Object { $_.Temp }).Count) { & $add ('Thermalzone weggelassen: {0}' -f $(if ($realT) { 'echte CPU-Temperatur vorhanden' } else { 'Festwert ohne Aussagekraft' })) }
            $step = [math]::Max(1, [int][math]::Ceiling($S.Count / 80))
            for ($i = 0; $i -lt $S.Count; $i += $step) {
                $x = $S[$i]
                $v = @($x.T, $x.MHz, $x.Last, $x.MaxFreq) + $(if ($withTz) { @($x.Temp) } else { @() }) + @($x.CpuTemp, $x.CpuTempQ, $x.CpuMHz, $x.CpuW, $x.GpuTemp, $x.GpuMHz, $x.GpuW) + $(if ($withIg) { @($x.IGpuTemp, $x.IGpuW) } else { @() }) + @($x.Fan, $x.DiskTemp, $x.DiskMBs, $(if ($x.Cpu) { 1 } else { 0 }))
                & $add (($v | ForEach-Object { if ($null -eq $_) { '' } elseif ($_ -is [double]) { ([math]::Round($_, 1)).ToString($script:Inv) } else { [string]$_ } }) -join ';')
            }
        }
    }

    if ($script:SensorSnapshot) {
        & $head 'SENSOREN (MOMENTAUFNAHME IM LEERLAUF)'
        & $add (Get-SensorSourceText)
        & $add 'Messwerte: Gruppe;Gerät;Art;Sensor;Wert;Einheit;Quelle'
        foreach ($r in @($script:SensorSnapshot | Where-Object { $_.Art -notin 'Grenzwert', 'Abstand' -and (-not [double]::IsNaN([double]$_.Wert) -or $_.Status -eq 'unplausibel') })) {
            $val = $(if ($r.Status -eq 'unplausibel') { 'unplausibel, verworfen ({0})' -f $r.Hinweis } else { ([double]$r.Wert).ToString('0.###', $script:Inv) })
            & $add ('{0};{1};{2};{3};{4};{5};{6}' -f $r.Gruppe, $r.Geraet, $r.Art, $r.Name, $val, $r.Einheit, $r.Quelle)
        }
        $lim = @($script:SensorSnapshot | Where-Object { $_.Art -eq 'Grenzwert' -and -not [double]::IsNaN([double]$_.Wert) })
        if ($lim.Count) {
            & $add ''
            & $add 'GRENZWERTE LAUT HERSTELLER (keine Messwerte, siehe Regel 1): Gruppe;Gerät;Grenzwert;Wert;Einheit'
            foreach ($r in $lim) { & $add ('{0};{1};{2};{3};{4}' -f $r.Gruppe, $r.Geraet, $r.Name, ([double]$r.Wert).ToString('0.###', $script:Inv), $r.Einheit) }
        }
    }

    if ($script:RepairLog.Count) {
        & $head 'REPARATUREN'
        foreach ($r in $script:RepairLog) { & $add ('{0} | {1} | {2}{3}' -f $r.Reparatur, $r.Ergebnis, $r.Details, $(if ($r.Stufe) { ' | Stufe ' + $r.Stufe } else { '' })) }
        if ($script:RestartNeeded.Count) { & $add ('Neustart erforderlich für: {0}' -f (($script:RestartNeeded | Select-Object -Unique) -join ', ')) }
    }

    if (@($script:OptLog).Count) {
        & $head 'OPTIMIERUNG (Windows Optimisation Pack, nativ)'
        & $add 'Eintrag | Kategorie | Ergebnis | Einzeländerungen | Stufe | Details'
        foreach ($r in $script:OptLog) { & $add ('{0} | {1} | {2} | {3} | {4} | {5}' -f $r.Titel, (Get-OptCategoryTitle $r.Kat), $r.Ergebnis, $r.Aenderungen, (Get-RiskLabel $r.Risiko), $r.Details) }
        foreach ($m in @(Get-OptMetricRows $script:OptMetricsBefore $script:OptMetricsAfter)) { & $add ('Kennzahl {0}: vorher {1}, nachher {2} ({3})' -f $m.Kennzahl, $m.Vorher, $m.Nachher, $m.Differenz) }
    }

    if (-not $Compact) {
        & $head 'VOLLSTÄNDIGER BERICHT (alle Abschnitte)'
        & $add $script:Report.ToString()

        & $head 'ROHDATEN AUS DEM ANHANG'
        $files = @()
        if ($RawDir -and (Test-Path $RawDir)) { $files = @(Get-ChildItem $RawDir -File -ErrorAction SilentlyContinue) }
        $prio = @{ 'Checkpoint.log' = 1; 'Checkpoint_unterbrochener_Lauf.log' = 2; 'Diagnosebericht_unterbrochener_Lauf.txt' = 3; 'Konsole.log' = 4; 'Benchmark.csv' = 5; 'Lasttest-Verlauf.csv' = 6; 'Benchmark-Sensoren.csv' = 7; 'winsat.txt' = 8; 'Treiber.csv' = 9; 'Energiebericht.html' = 10; 'Akkubericht.html' = 11; 'dxdiag.txt' = 12; 'Software.csv' = 13; 'ComputerInfo.txt' = 14 }
        $files = @($files | Where-Object { $_.Name -notlike '*.xml' } | Sort-Object { if ($prio.ContainsKey($_.Name)) { $prio[$_.Name] } elseif ($_.Name -like 'smartctl_*') { 7 } else { 20 } }, Name)
        $used = 0
        foreach ($f in $files) {
            $raw = ''
            try { $raw = [IO.File]::ReadAllText($f.FullName) } catch { continue }
            $raw = $raw.TrimStart([char]0xFEFF)
            $max = 30000
            switch -Wildcard ($f.Name) {
                'Energiebericht.html' {
                    # nur Fehler und Warnungen der Analyse, die Informationsereignisse sind meist ohne Belang
                    $a = $raw.IndexOf('Analyseergebnisse'); if ($a -lt 0) { $a = $raw.IndexOf('Analysis Results') }
                    $mI = [regex]::Match($raw, '<h4>\s*(Informationen|Information)\s*</h4>')
                    if ($a -gt 0 -and $mI.Success -and $mI.Index -gt $a) { $raw = $raw.Substring($a, $mI.Index - $a) }
                    $raw = ConvertFrom-HtmlToText $raw; $max = 15000
                }
                '*.html'         { $raw = ConvertFrom-HtmlToText $raw; $max = 15000 }
                'smartctl_*'     { $raw = Add-SmartLimitMarks $raw }
                'Checkpoint*'    { $ls = @($raw -split "`r?`n"); $raw = ((@($ls | Where-Object { $_ -notmatch '\|\s*PULS\s*\|' }) + '(Pulsmeldungen, letzte 15:)' + @($ls | Where-Object { $_ -match '\|\s*PULS\s*\|' } | Select-Object -Last 15)) -join "`r`n") }
                'dxdiag.txt'     { $max = 18000 }
                'Software.csv'   { $max = 15000 }
                'ComputerInfo.txt' { $max = 12000 }
            }
            $left = $RawBudget - $used
            if ($left -le 2000) { & $add ''; & $add ('--- {0}: ausgelassen (Größenbegrenzung der KI-Datei)' -f $f.Name); continue }
            $max = [math]::Min($max, $left)
            $note = ''
            if ($raw.Length -gt $max) { $note = (' [gekürzt auf {0:N0} von {1:N0} Zeichen]' -f $max, $raw.Length); $raw = $raw.Substring(0, $max) }
            $used += $raw.Length
            & $add ''
            & $add (('--- DATEI: {0}{1} ' -f $f.Name, $note).PadRight(100, '-'))
            & $add $raw.TrimEnd()
        }
        $err = Join-Path $OutputDir 'Fehler.txt'
        if (Test-Path $err) { & $add ''; & $add '--- DATEI: Fehler.txt (Skriptfehler) ---'; & $add ((Get-Content $err -Raw) -replace '^\s+', '') }
    }

    & $head 'ENDE DER DATEN'
    & $add 'Bitte jetzt gemäß AUFTRAG AN DIE KI am Anfang dieser Datei antworten.'
    $text = $sb.ToString()
    if (-not $KiOhneAnonymisierung) { $text = Protect-Text $text }
    if ($Path) { [IO.File]::WriteAllText($Path, $text, (New-Object Text.UTF8Encoding($true))) }
    return $text
}
#endregion

