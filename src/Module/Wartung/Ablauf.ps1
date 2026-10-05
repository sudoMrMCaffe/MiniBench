# =====================================================================================
#                                     REPARATUR
# =====================================================================================
function Add-RepairResult([string]$Key, [string]$Status, [string]$Detail, [switch]$Restart) {
    $t = $(if ($script:RepTitles.Contains($Key)) { $script:RepTitles[$Key] } else { $Key })
    $script:RepairLog.Add([pscustomobject]@{ Reparatur = $t; Ergebnis = $Status; Details = $Detail; Stufe = $(if ($script:RepRisk.ContainsKey($Key)) { Get-RiskLabel $script:RepRisk[$Key] } else { '' }) })
    Add-TestResult ('Reparatur: ' + $t) $Status $Detail
    if ($Restart) { $script:RestartNeeded.Add($t) }
    Add-Line ('  Ergebnis: {0}{1}' -f $Status, $(if ($Detail) { ', ' + $Detail } else { '' }))
}

function Get-OutLines($Result, [int]$Max = 12) {
    @(($Result.Output + "`n" + $Result.Error) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^\[?=*\s*[\d.,]+\s*%\s*=*\]?$|\d+\s*%\s*$' } | Select-Object -Last $Max)
}

# Dateien löschen, die älter als die angegebene Anzahl Tage sind; Rückgabe: freigegebene Bytes
function Remove-OldFiles([string]$Path, [int]$Days) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    $limit = (Get-Date).AddDays(-$Days); $freed = 0.0
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $limit })) {
        try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $len } catch { }
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
        try { if (-not @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction Stop).Count -and $d.LastWriteTime -lt $limit) { Remove-Item -LiteralPath $d.FullName -Force -ErrorAction Stop } } catch { }
    }
    return $freed
}

function Clear-Folder([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0.0 }
    $freed = 0.0
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue)) {
        try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $len } catch { }
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
        try { if (-not @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction Stop).Count) { Remove-Item -LiteralPath $d.FullName -Force -ErrorAction Stop } } catch { }
    }
    return $freed
}

function Invoke-DismJob([string]$Mode, [int]$ExpectedSec) {
    $job = Start-Job -ScriptBlock { param($m) $p = @{ Online = $true; NoRestart = $true; ErrorAction = 'Stop' }; $p[$m] = $true; Repair-WindowsImage @p | Select-Object ImageHealthState, RestartNeeded } -ArgumentList $Mode
    [void](Wait-JobWithProgress $job ('DISM ' + $Mode) $ExpectedSec 7200)
    $r = $null; $err = ''
    try { $r = Receive-Job $job -ErrorAction Stop } catch { $err = $_.Exception.Message }
    if (-not $err -and $job.ChildJobs[0].Error.Count) { $err = [string]$job.ChildJobs[0].Error[0] }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ State = $(if ($r) { [string]@($r)[0].ImageHealthState } else { '' }); Restart = $(if ($r) { [bool]@($r)[0].RestartNeeded } else { $false }); Error = $err }
}

if ($ModRep) {
    # Änderungsprotokoll dieses Laufs (Datei entsteht erst mit der ersten Änderung)
    Start-ChangeLog
    $script:RestorePointNo = ''
    $maxRep = Get-MaxRisk @($script:RepSel | ForEach-Object { $script:RepRisk[$_] })
    if ($OhneWiederherstellungspunkt -and (Get-RiskRank $maxRep) -ge (Get-RiskRank 'Eingriff')) {
        Add-Finding INFO 'Reparatur' 'Die Reparaturen enthalten Eingriffe ohne automatisches Rückgängig, ein Wiederherstellungspunkt wurde aber bewusst nicht angelegt.'
    }
    if (-not $OhneWiederherstellungspunkt) {
        Invoke-Section 'Reparatur: Wiederherstellungspunkt anlegen' {
            $rk = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
            $old = $null; try { $old = (Get-ItemProperty $rk -Name SystemRestorePointCreationFrequency -ErrorAction Stop).SystemRestorePointCreationFrequency } catch { }
            try {
                Show-Sub 'Wiederherstellungspunkt' 'wird angelegt' -1
                try { Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop } catch { }
                if (-not (Test-Path $rk)) { New-Item -Path $rk -Force | Out-Null }
                Set-ItemProperty -Path $rk -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction SilentlyContinue
                Checkpoint-Computer -Description ('Leos Minibench vor Reparatur {0:dd.MM.yyyy HH:mm}' -f (Get-Date)) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                $rp = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber -Descending | Select-Object -First 1
                $txt = $(if ($rp) { 'angelegt: {0} (Nr. {1})' -f $rp.Description, $rp.SequenceNumber } else { 'angelegt' })
                if ($rp) { $script:RestorePointNo = [string]$rp.SequenceNumber }
                Add-Line ('  Wiederherstellungspunkt {0}' -f $txt)
                # Weg zurück für alle Eingriffe dieses Laufs; erscheint auf der Seite Änderungen als Hinweis
                [void](Add-ChangeRecord -Modul 'Reparatur' -Schritt 'Wiederherstellungspunkt' -Titel 'Wiederherstellungspunkt vor den Reparaturen' -Risiko 'Lesen' -Art 'Wiederherstellungspunkt' `
                    -Ziel 'Computerschutz' -Nachher $txt -Daten ([ordered]@{ Nummer = $script:RestorePointNo }) -Gegenbefehl ('rstrui.exe starten und Punkt Nr. {0} wählen; macht die Eingriffe dieses Laufs rückgängig' -f $script:RestorePointNo) -NurHinweis)
                $script:RepairLog.Add([pscustomobject]@{ Reparatur = 'Wiederherstellungspunkt'; Ergebnis = 'OK'; Details = $txt })
                Add-TestResult 'Reparatur: Wiederherstellungspunkt' 'OK' $txt
            } catch {
                Add-Line ('  Wiederherstellungspunkt konnte nicht angelegt werden: {0}' -f $_.Exception.Message)
                $script:RepairLog.Add([pscustomobject]@{ Reparatur = 'Wiederherstellungspunkt'; Ergebnis = 'Warnung'; Details = $_.Exception.Message })
                Add-TestResult 'Reparatur: Wiederherstellungspunkt' 'Warnung' $_.Exception.Message
                Add-Finding WARNUNG 'Reparatur' ('Vor den Reparaturen konnte kein Wiederherstellungspunkt angelegt werden ({0}). Computerschutz für Laufwerk {1} prüfen.' -f $_.Exception.Message, $env:SystemDrive)
            } finally {
                if ($null -ne $old) { Set-ItemProperty -Path $rk -Name SystemRestorePointCreationFrequency -Value $old -Type DWord -ErrorAction SilentlyContinue }
                else { Remove-ItemProperty -Path $rk -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
                Hide-Sub
            }
        }
    }

    foreach ($repKey in @($script:RepOrder | Where-Object { $script:RepSel -contains $_ })) {
        if (-not (Test-StepEnabled ('Rep:' + $repKey))) { continue }
        $script:CurRep = $repKey
        Invoke-Section ('Reparatur: ' + $script:RepTitles[$repKey]) {
            $k = $script:CurRep
            $st = Get-ModuleStep 'Wartung' $k; if (-not $st) { $st = Get-ModuleStep 'Reparatur' $k }
            Add-Line ('  Risikostufe: {0}{1}' -f (Get-RiskLabel $st.Risiko), $(switch ($st.Rueckgaengig) { 'Protokoll' { ', rückgängig über die Seite Änderungen' } 'Wiederherstellungspunkt' { ', zurück nur über den Wiederherstellungspunkt' } 'Hinweis' { ', Weg zurück steht im Änderungsprotokoll' } default { ', nicht umkehrbar' } }))
            switch ($k) {
                'DismRestore' {
                    Write-Step 'DISM ScanHealth läuft (5 bis 20 Minuten) ...'
                    $scan = Invoke-DismJob 'ScanHealth' 600
                    if ($scan.Error) { Add-Line ('  ScanHealth fehlgeschlagen: {0}' -f $scan.Error); Add-RepairResult $k 'Fehler' ('ScanHealth fehlgeschlagen: ' + $scan.Error); break }
                    Add-Line ('  Zustand vor der Reparatur: {0}' -f $scan.State)
                    if ($scan.State -eq 'Healthy') { Add-RepairResult $k 'OK' 'Komponentenspeicher intakt, keine Reparatur nötig'; break }
                    if ($scan.State -eq 'NonRepairable') {
                        Add-RepairResult $k 'Fehler' 'Komponentenspeicher nicht reparierbar'
                        Add-Finding KRITISCH 'Systemdateien' 'Der Komponentenspeicher ist nicht reparierbar. Abhilfe: Inplace-Upgrade mit dem Windows-Installationsmedium (setup.exe, Dateien und Apps behalten).'
                        break
                    }
                    Write-Step 'DISM RestoreHealth läuft (10 bis 30 Minuten, lädt Dateien über Windows Update) ...'
                    $rh = Invoke-DismJob 'RestoreHealth' 1200
                    if ($rh.Error) {
                        Add-Line ('  RestoreHealth fehlgeschlagen: {0}' -f $rh.Error)
                        $hint = $(if ($rh.Error -match '0x800f081f|0x800f0906|0x800f0907|Quelldateien|source files') { ' Die Reparaturquelle fehlt: Windows-ISO einbinden und DISM /Online /Cleanup-Image /RestoreHealth /Source:WIM:X:\sources\install.wim:1 /LimitAccess ausführen.' } else { '' })
                        Add-RepairResult $k 'Fehler' ('RestoreHealth fehlgeschlagen: ' + $rh.Error)
                        Add-Finding KRITISCH 'Systemdateien' ('DISM RestoreHealth konnte den Komponentenspeicher nicht reparieren ({0}).{1}' -f $rh.Error, $hint)
                        break
                    }
                    Add-Line ('  Zustand nach der Reparatur: {0}' -f $rh.State)
                    if ($rh.State -eq 'Healthy') { Add-RepairResult $k 'Repariert' 'Komponentenspeicher repariert' -Restart:$rh.Restart; Add-Finding INFO 'Systemdateien' 'Der Komponentenspeicher war beschädigt und wurde mit DISM repariert.' }
                    else { Add-RepairResult $k 'Fehler' ('Zustand nach RestoreHealth: ' + $rh.State); Add-Finding KRITISCH 'Systemdateien' ('Komponentenspeicher nach der Reparatur weiterhin {0}. Abhilfe: Inplace-Upgrade mit dem Windows-Installationsmedium.' -f $rh.State) }
                }
                'Sfc' {
                    Write-Step 'sfc /scannow läuft (5 bis 20 Minuten) ...'
                    $t0 = Get-Date
                    $sfc = Invoke-External -File "$env:windir\System32\sfc.exe" -Arguments '/scannow' -TimeoutSec 5400 -Encoding ([Text.Encoding]::Unicode) -Progress 'Systemdateien reparieren (sfc /scannow)' -ExpectedSec 900
                    (Get-OutLines $sfc) | ForEach-Object { Add-Line ('  ' + $_) }
                    $cbs = Get-CbsEntries $t0
                    if ($cbs.Cannot.Count) { Add-Line ('  CBS.log: {0} nicht reparierbare Dateien, z. B. {1}' -f $cbs.Cannot.Count, (($cbs.Files | Select-Object -First 5) -join ', ')) }
                    $o = $sfc.Output
                    if ($o -match 'keine Integritätsverletzungen|did not find any integrity violations') { Add-RepairResult $k 'OK' 'keine Integritätsverletzungen' }
                    elseif ($cbs.Cannot.Count -or $o -match 'konnte einige|nicht reparieren|unable to fix') {
                        Add-RepairResult $k 'Fehler' ('{0} Dateien nicht reparierbar' -f [math]::Max(1, $cbs.Cannot.Count))
                        Add-Finding KRITISCH 'Systemdateien' 'SFC konnte nicht alle beschädigten Dateien reparieren. Zuerst DISM RestoreHealth ausführen, danach sfc /scannow wiederholen. Hilft das nicht: Inplace-Upgrade mit dem Windows-Installationsmedium.'
                    }
                    elseif ($o -match 'erfolgreich repariert|successfully repaired') { Add-RepairResult $k 'Repariert' 'beschädigte Dateien repariert' -Restart; Add-Finding INFO 'Systemdateien' 'SFC hat beschädigte Systemdateien gefunden und repariert. Ein Neustart schließt die Reparatur ab.' }
                    elseif ($sfc.TimedOut) { Add-RepairResult $k 'Warnung' 'Zeitlimit überschritten' }
                    else { Add-RepairResult $k 'Info' ('Rückgabecode {0}, Ausgabe siehe Bericht' -f $sfc.ExitCode) }
                }
                'Komponentenbereinigung' {
                    $sysVol = Get-Volume -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction SilentlyContinue
                    $before = [double]$sysVol.SizeRemaining
                    Write-Step 'DISM StartComponentCleanup läuft (5 bis 30 Minuten) ...'
                    $r = Invoke-External -File "$env:windir\System32\dism.exe" -Arguments '/Online /Cleanup-Image /StartComponentCleanup /NoRestart' -TimeoutSec 5400 -Progress 'Komponentenspeicher bereinigen' -ExpectedSec 900
                    (Get-OutLines $r 4) | ForEach-Object { Add-Line ('  ' + $_) }
                    $after = [double](Get-Volume -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction SilentlyContinue).SizeRemaining
                    $gain = $after - $before
                    if ($r.ExitCode -eq 0) { Add-RepairResult $k 'OK' ('abgeschlossen, Speicherplatz auf {0} {1}' -f $env:SystemDrive, $(if ($gain -gt 50MB) { 'um ' + (Format-Size $gain) + ' vergrößert' } else { 'kaum verändert' })) }
                    else { Add-RepairResult $k 'Warnung' ('DISM-Rückgabecode {0}' -f $r.ExitCode) }
                }
                'Dateisystem' {
                    $res = New-Object System.Collections.ArrayList; $restart = $false; $fixed = $false; $bad = $false
                    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -in 'NTFS', 'ReFS' } | Sort-Object DriveLetter)) {
                        $dl = [string]$v.DriveLetter
                        Show-Sub ('Dateisystem Laufwerk {0}:' -f $dl) 'Onlinescan' -1
                        try { $scan = "$(Repair-Volume -DriveLetter $dl -Scan -ErrorAction Stop)" } catch { [void]$res.Add(('{0}: Scan fehlgeschlagen ({1})' -f $dl, $_.Exception.Message)); $bad = $true; continue }
                        if ($scan -eq 'NoErrorsFound') { [void]$res.Add(('{0}: ok' -f $dl)); continue }
                        if (('{0}:' -f $dl) -eq $env:SystemDrive) {
                            $r = Invoke-External -File 'fsutil.exe' -Arguments ('dirty set {0}:' -f $dl)
                            [void]$res.Add(('{0}: {1}, Reparatur (chkdsk) beim nächsten Neustart eingeplant' -f $dl, $scan)); $restart = $true
                        } else {
                            Show-Sub ('Dateisystem Laufwerk {0}:' -f $dl) 'SpotFix' -1
                            try { $fx = "$(Repair-Volume -DriveLetter $dl -SpotFix -ErrorAction Stop)"; [void]$res.Add(('{0}: {1}, SpotFix: {2}' -f $dl, $scan, $fx)); $fixed = $true }
                            catch { [void]$res.Add(('{0}: {1}, SpotFix fehlgeschlagen ({2})' -f $dl, $scan, $_.Exception.Message)); $bad = $true }
                        }
                    }
                    Hide-Sub
                    $res | ForEach-Object { Add-Line ('  ' + $_) }
                    $st = $(if ($bad) { 'Warnung' } elseif ($restart) { 'Neustart' } elseif ($fixed) { 'Repariert' } else { 'OK' })
                    Add-RepairResult $k $st ($res -join '; ') -Restart:$restart
                }
                'WindowsUpdate' {
                    $svcs = 'wuauserv', 'bits', 'cryptsvc', 'msiserver'
                    $was = @{}
                    foreach ($s in $svcs) { $sv = Get-Service $s -ErrorAction SilentlyContinue; if ($sv) { $was[$s] = [string]$sv.Status; Stop-Service $s -Force -ErrorAction SilentlyContinue } }
                    $sw = [Diagnostics.Stopwatch]::StartNew()
                    while ($sw.Elapsed.TotalSeconds -lt 40 -and @($svcs | Where-Object { (Get-Service $_ -ErrorAction SilentlyContinue).Status -eq 'Running' }).Count) { Show-Sub 'Windows Update zurücksetzen' 'Dienste werden beendet' -1; Start-Sleep -Milliseconds 500 }
                    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'; $msgs = @(); $err = $false
                    foreach ($d in @("$env:windir\SoftwareDistribution", "$env:windir\System32\catroot2")) {
                        if (-not (Test-Path $d)) { continue }
                        $new = '{0}.bak_{1}' -f (Split-Path $d -Leaf), $ts
                        try { Rename-Item -LiteralPath $d -NewName $new -ErrorAction Stop; $msgs += ('{0} umbenannt in {1}' -f (Split-Path $d -Leaf), $new) }
                        catch { $msgs += ('{0} nicht umbenennbar: {1}' -f (Split-Path $d -Leaf), $_.Exception.Message); $err = $true }
                    }
                    foreach ($s in 'cryptsvc', 'bits', 'wuauserv') { Start-Service $s -ErrorAction SilentlyContinue }
                    foreach ($s in $was.Keys) { if ($was[$s] -eq 'Running') { Start-Service $s -ErrorAction SilentlyContinue } }
                    Hide-Sub
                    $old = @(Get-ChildItem $env:windir -Directory -Filter 'SoftwareDistribution.bak_*' -ErrorAction SilentlyContinue) + @(Get-ChildItem "$env:windir\System32" -Directory -Filter 'catroot2.bak_*' -ErrorAction SilentlyContinue)
                    $msgs | ForEach-Object { Add-Line ('  ' + $_) }
                    if ($old.Count -gt 2) { Add-Line ('  Hinweis: {0} Sicherungsordner früherer Zurücksetzungen liegen in {1} und können gelöscht werden, wenn Updates wieder funktionieren.' -f $old.Count, $env:windir) }
                    $ren = @($msgs | Where-Object { $_ -match ' umbenannt in ' })
                    if ($ren.Count) {
                        [void](Add-ChangeRecord -Modul 'Reparatur' -Schritt $k -Titel $script:RepTitles[$k] -Risiko 'Eingriff' -Art 'Ordner' -Ziel ('{0}\SoftwareDistribution, catroot2' -f $env:windir) `
                            -Vorher 'Originalordner' -Nachher ($ren -join '; ') -Gegenbefehl 'Dienste wuauserv, bits, cryptsvc beenden, die neuen Ordner löschen und die Ordner .bak_<Datum> zurückbenennen' -NurHinweis)
                    }
                    Add-RepairResult $k $(if ($err) { 'Warnung' } else { 'Repariert' }) (($msgs -join '; ') + '; Dienste neu gestartet') -Restart
                }
                'Netzwerk' {
                    $out = @(); $bad = 0
                    foreach ($c in @(@('ipconfig.exe', '/flushdns'), @('netsh.exe', 'winsock reset'), @('netsh.exe', 'int ip reset'), @('netsh.exe', 'int ipv6 reset'))) {
                        Show-Sub 'Netzwerk zurücksetzen' ('{0} {1}' -f $c[0], $c[1]) -1
                        $r = Invoke-External -File $c[0] -Arguments $c[1] -TimeoutSec 120
                        $out += ('{0} {1}: Rückgabecode {2}' -f $c[0], $c[1], $r.ExitCode)
                        if ($r.ExitCode -ne 0) { $bad++ }
                    }
                    Hide-Sub
                    $out | ForEach-Object { Add-Line ('  ' + $_) }
                    Add-RepairResult $k $(if ($bad) { 'Warnung' } else { 'Neustart' }) ('DNS-Cache geleert, Winsock und TCP/IP zurückgesetzt' + $(if ($bad) { (', {0} Befehle mit Fehler' -f $bad) } else { '' })) -Restart
                }
                'Temp' {
                    $total = 0.0; $lines = @()
                    $targets = @($env:TEMP, "$env:windir\Temp", "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue")
                    $targets += @(Get-ChildItem "$env:SystemDrive\Users" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'AppData\Local\Temp' } | Where-Object { Test-Path -LiteralPath $_ })
                    foreach ($t in @($targets | Where-Object { $_ } | Select-Object -Unique)) {
                        Show-Sub 'Temporäre Dateien löschen' $t -1
                        $f = Remove-OldFiles $t 2
                        $total += $f
                        if ($f -gt 1MB) { $lines += ('{0}: {1}' -f $t, (Format-Size $f)) }
                    }
                    try {
                        if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
                            $doB = $null; try { $doB = (Get-DeliveryOptimizationStatus -ErrorAction Stop | Measure-Object FileSize -Sum).Sum } catch { }
                            Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
                            $lines += ('Übermittlungsoptimierung: Cache geleert{0}' -f $(if ($doB) { ' (' + (Format-Size $doB) + ')' } else { '' }))
                        }
                    } catch { }
                    Hide-Sub
                    $lines | ForEach-Object { Add-Line ('  ' + $_) }
                    Add-RepairResult $k 'OK' ('{0} freigegeben (Dateien älter als 2 Tage, gesperrte Dateien bleiben erhalten)' -f (Format-Size $total))
                }
                'WMI' {
                    $v = Invoke-External -File "$env:windir\System32\wbem\winmgmt.exe" -Arguments '/verifyrepository' -TimeoutSec 600 -Progress 'WMI-Repository prüfen'
                    $txt = ($v.Output + ' ' + $v.Error).Trim()
                    Add-Line ('  Prüfung: {0}' -f $txt)
                    if ($txt -match 'inkonsistent|nicht konsistent|inconsistent|not consistent') {
                        $s = Invoke-External -File "$env:windir\System32\wbem\winmgmt.exe" -Arguments '/salvagerepository' -TimeoutSec 900 -Progress 'WMI-Repository reparieren'
                        $v2 = Invoke-External -File "$env:windir\System32\wbem\winmgmt.exe" -Arguments '/verifyrepository' -TimeoutSec 600
                        Add-Line ('  Reparatur: {0}' -f ($s.Output + ' ' + $s.Error).Trim()); Add-Line ('  Erneute Prüfung: {0}' -f ($v2.Output).Trim())
                        if (($v2.Output) -match 'inkonsistent|nicht konsistent|inconsistent|not consistent') { Add-RepairResult $k 'Fehler' 'Repository weiterhin inkonsistent'; Add-Finding WARNUNG 'System' 'Das WMI-Repository ist beschädigt und ließ sich nicht reparieren (winmgmt /resetrepository als letzter Schritt).' }
                        else { Add-RepairResult $k 'Repariert' 'Repository war inkonsistent und wurde repariert' }
                    } elseif ($v.ExitCode -eq 0) { Add-RepairResult $k 'OK' 'Repository konsistent' }
                    else { Add-RepairResult $k 'Info' ('Rückgabecode {0}' -f $v.ExitCode) }
                }
                'Zeit' {
                    $svc = Get-Service w32time -ErrorAction SilentlyContinue
                    if ($svc -and $svc.StartType -eq 'Disabled') {
                        try { $c = Set-ServiceStartTypeLogged -Name 'w32time' -StartType 'Manual' -Modul 'Reparatur' -Schritt $k -Titel $script:RepTitles[$k]; if ($c) { Add-Line '  Dienst w32time war deaktiviert und steht jetzt auf Manuell (im Änderungsprotokoll).' } }
                        catch { Add-Line ('  Starttyp von w32time nicht änderbar: {0}' -f $_.Exception.Message) }
                    }
                    Start-Service w32time -ErrorAction SilentlyContinue
                    $r = Invoke-External -File 'w32tm.exe' -Arguments '/resync /force' -TimeoutSec 120 -Progress 'Zeit synchronisieren'
                    if ($r.ExitCode -ne 0) {
                        [void](Invoke-External -File 'w32tm.exe' -Arguments '/config /update' -TimeoutSec 60)
                        Restart-Service w32time -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2
                        $r = Invoke-External -File 'w32tm.exe' -Arguments '/resync /force' -TimeoutSec 120
                    }
                    (Get-OutLines $r 3) | ForEach-Object { Add-Line ('  ' + $_) }
                    Add-RepairResult $k $(if ($r.ExitCode -eq 0) { 'OK' } else { 'Warnung' }) $(if ($r.ExitCode -eq 0) { 'Zeit synchronisiert' } else { 'Synchronisierung fehlgeschlagen, Rückgabecode ' + $r.ExitCode })
                }
                'Druck' {
                    Stop-Service Spooler -Force -ErrorAction SilentlyContinue
                    $spool = "$env:windir\System32\spool\PRINTERS"
                    $files = @(Get-ChildItem $spool -File -Force -ErrorAction SilentlyContinue)
                    $n = 0; foreach ($f in $files) { try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $n++ } catch { } }
                    Start-Service Spooler -ErrorAction SilentlyContinue
                    $ok = (Get-Service Spooler -ErrorAction SilentlyContinue).Status -eq 'Running'
                    Add-RepairResult $k $(if (-not $ok) { 'Warnung' } elseif ($n) { 'Repariert' } else { 'OK' }) ('{0} hängende Druckaufträge entfernt, Druckspooler {1}' -f $n, $(if ($ok) { 'läuft' } else { 'startet nicht' }))
                }
                'Geraete' {
                    $bad0 = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -notin 22, 45 }).Count
                    $r = Invoke-External -File 'pnputil.exe' -Arguments '/scan-devices' -TimeoutSec 300 -Progress 'Geräte neu erkennen'
                    Start-Sleep -Seconds 3
                    $bad1 = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -notin 22, 45 }).Count
                    Add-RepairResult $k $(if ($r.ExitCode -ne 0) { 'Info' } elseif ($bad1 -lt $bad0) { 'Repariert' } else { 'OK' }) ('Geräte mit Fehlercode vorher {0}, nachher {1}' -f $bad0, $bad1)
                }
                'Schnellstart' {
                    $pk = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
                    $old = (Get-ItemProperty $pk -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
                    if ($old -eq 0) { Add-RepairResult $k 'OK' 'Schnellstart war bereits deaktiviert' }
                    else {
                        try { [void](Set-RegistryValueLogged -Path $pk -Name 'HiberbootEnabled' -Value 0 -Type 'DWord' -Modul 'Reparatur' -Schritt $k -Titel $script:RepTitles[$k]); Add-RepairResult $k 'Repariert' 'Schnellstart deaktiviert, Windows fährt ab jetzt vollständig herunter (rückgängig über die Seite Änderungen)' }
                        catch { Add-RepairResult $k 'Fehler' $_.Exception.Message }
                    }
                }
                'Energieplaene' {
                    # Erst alle Pläne sichern; ohne Sicherung wird nichts zurückgesetzt
                    try { $bk = Backup-PowerSchemesLogged -Modul 'Reparatur' -Schritt $k -Titel $script:RepTitles[$k]; Add-Line ('  Gesichert: {0}' -f $bk.Vorher) }
                    catch { Add-RepairResult $k 'Fehler' ('Sicherung der Energiepläne fehlgeschlagen, nichts zurückgesetzt: ' + $_.Exception.Message); break }
                    $r = Invoke-External -File 'powercfg.exe' -Arguments '-restoredefaultschemes' -TimeoutSec 60
                    $a = Invoke-External -File 'powercfg.exe' -Arguments '/getactivescheme'
                    Add-RepairResult $k $(if ($r.ExitCode -eq 0) { 'OK' } else { 'Warnung' }) ('Standardpläne wiederhergestellt, aktiv: {0}' -f ((($a.Output -split '\(')[-1]) -replace '\)', '').Trim())
                }
                'Datentraegerbereinigung' {
                    Write-Step 'Datenträgerbereinigung läuft (cleanmgr /sagerun:4711) ...'
                    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
                    $keys = @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'DownloadsFolder' })
                    foreach ($kObj in $keys) { try { New-ItemProperty -LiteralPath $kObj.PSPath -Name 'StateFlags4711' -Value 2 -PropertyType DWord -Force -ErrorAction Stop | Out-Null } catch { } }
                    $free0 = [double](Get-Volume -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction SilentlyContinue).SizeRemaining
                    $r = Invoke-External -File (Join-Path $env:windir 'System32\cleanmgr.exe') -Arguments '/sagerun:4711' -TimeoutSec 3600 -Progress 'Datenträgerbereinigung läuft' -ExpectedSec 600
                    foreach ($kObj in $keys) { try { Remove-ItemProperty -LiteralPath $kObj.PSPath -Name 'StateFlags4711' -ErrorAction Stop } catch { } }
                    $free1 = [double](Get-Volume -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction SilentlyContinue).SizeRemaining
                    $freed = [math]::Max(0.0, $free1 - $free0)
                    [void](Add-ChangeRecord -Modul 'Wartung' -Schritt $k -Titel $script:RepTitles[$k] -Risiko 'Eingriff' -Art 'Bereinigung' -Ziel ('Datenträgerbereinigung, {0} Kategorien' -f $keys.Count) -Nachher ('{0:N0} MB frei geworden' -f ($freed / 1MB)) -Gegenbefehl 'nicht umkehrbar' -NurHinweis)
                    Add-RepairResult $k $(if ($r.TimedOut) { 'Warnung' } else { 'OK' }) ('Datenträgerbereinigung abgeschlossen, {0} freigegeben' -f (Format-Size $freed))
                }
                'Leistungszaehler' {
                    Write-Step 'Leistungszähler werden neu aufgebaut (lodctr /r) ...'
                    $r = Invoke-External -File "$env:windir\System32\lodctr.exe" -Arguments '/r' -TimeoutSec 300 -Progress 'Leistungszähler werden neu aufgebaut' -ExpectedSec 30
                    (Get-OutLines $r 3) | ForEach-Object { Add-Line ('  ' + $_) }
                    [void](Add-ChangeRecord -Modul 'Wartung' -Schritt $k -Titel $script:RepTitles[$k] -Risiko 'Eingriff' -Art 'Leistungszaehler' -Ziel 'Leistungsindikatoren' -Nachher $(if ($r.ExitCode -eq 0) { 'neu aufgebaut' } else { 'Fehler ' + $r.ExitCode }) -Gegenbefehl 'nicht umkehrbar, erneut lodctr /r' -NurHinweis)
                    Add-RepairResult $k $(if ($r.ExitCode -eq 0) { 'OK' } else { 'Warnung' }) $(if ($r.ExitCode -eq 0) { 'Leistungsindikatoren erfolgreich aus der Sicherung neu aufgebaut' } else { 'lodctr /r Rückgabecode ' + $r.ExitCode })
                }
                'Leerlaufaufgaben' {
                    Write-Step 'Aufgeschobene Windows-Wartungsaufgaben starten (ProcessIdleTasks) ...'
                    Start-Process -FilePath (Join-Path $env:windir 'System32\rundll32.exe') -ArgumentList 'advapi32.dll,ProcessIdleTasks' -WindowStyle Hidden -ErrorAction Stop
                    [void](Add-ChangeRecord -Modul 'Wartung' -Schritt $k -Titel $script:RepTitles[$k] -Risiko 'Eingriff' -Art 'Wartung' -Ziel 'Leerlaufaufgaben' -Nachher 'gestartet' -Gegenbefehl 'nicht nötig' -NurHinweis)
                    Add-RepairResult $k 'OK' 'Leerlaufaufgaben gestartet (laufen im Hintergrund bis zu einer Stunde weiter)'
                }
                'ShaderCache' {
                    $targets = @(
                        "$env:LOCALAPPDATA\NVIDIA\DXCache",
                        "$env:LOCALAPPDATA\NVIDIA\GLCache",
                        "$env:USERPROFILE\AppData\LocalLow\Intel\ShaderCache",
                        "$env:LOCALAPPDATA\AMD",
                        "$env:USERPROFILE\AppData\LocalLow\AMD"
                    )
                    $total = 0.0; $lines = @()
                    foreach ($t in @($targets | Where-Object { Test-Path -LiteralPath $_ })) {
                        $f = Clear-Folder $t
                        $total += $f
                        if ($f -gt 1MB) { $lines += ('{0}: {1}' -f $t, (Format-Size $f)) }
                    }
                    $lines | ForEach-Object { Add-Line ('  ' + $_) }
                    [void](Add-ChangeRecord -Modul 'Wartung' -Schritt $k -Titel $script:RepTitles[$k] -Risiko 'Eingriff' -Art 'Bereinigung' -Ziel 'Shader-Caches der Grafiktreiber' -Nachher ('{0} gelöscht' -f (Format-Size $total)) -Gegenbefehl 'Spiele bauen Caches automatisch neu auf' -NurHinweis)
                    Add-RepairResult $k 'OK' ('{0} freigegeben (Spiele und Grafiktreiber bauen die Caches beim nächsten Start neu auf)' -f (Format-Size $total))
                }
                'UpdateDownloads' {
                    $p = "$env:windir\SoftwareDistribution\Download"
                    $freed = Clear-Folder $p
                    [void](Add-ChangeRecord -Modul 'Wartung' -Schritt $k -Titel $script:RepTitles[$k] -Risiko 'Eingriff' -Art 'Bereinigung' -Ziel $p -Nachher ('{0} gelöscht' -f (Format-Size $freed)) -Gegenbefehl 'nicht nötig' -NurHinweis)
                    Add-RepairResult $k 'OK' ('{0} freigegeben in SoftwareDistribution\Download' -f (Format-Size $freed))
                }
                'Absturzabbilder' {
                    $targets = @(
                        "$env:LOCALAPPDATA\CrashDumps",
                        "$env:SystemDrive\MSOCache",
                        "$env:ProgramData\Microsoft\Windows\RetailDemo",
                        "$env:SystemDrive\AMD"
                    )
                    $total = 0.0; $lines = @()
                    foreach ($t in @($targets | Where-Object { Test-Path -LiteralPath $_ })) {
                        $f = Clear-Folder $t
                        $total += $f
                        if ($f -gt 1MB) { $lines += ('{0}: {1}' -f $t, (Format-Size $f)) }
                    }
                    $lines | ForEach-Object { Add-Line ('  ' + $_) }
                    [void](Add-ChangeRecord -Modul 'Wartung' -Schritt $k -Titel $script:RepTitles[$k] -Risiko 'Eingriff' -Art 'Bereinigung' -Ziel 'Absturzabbilder und Installationsreste' -Nachher ('{0} gelöscht' -f (Format-Size $total)) -Gegenbefehl 'nicht umkehrbar' -NurHinweis)
                    Add-RepairResult $k 'OK' ('{0} freigegeben (CrashDumps, temporäre Installationsquellen und Treiberentpackreste)' -f (Format-Size $total))
                }
                'Prefetch' {
                    $p = "$env:windir\Prefetch"
                    $freed = Clear-Folder $p
                    [void](Add-ChangeRecord -Modul 'Wartung' -Schritt $k -Titel $script:RepTitles[$k] -Risiko 'Eingriff' -Art 'Bereinigung' -Ziel $p -Nachher ('{0} gelöscht' -f (Format-Size $freed)) -Gegenbefehl 'Windows baut Prefetch-Daten neu auf' -NurHinweis)
                    Add-RepairResult $k 'OK' ('{0} freigegeben in Windows\Prefetch' -f (Format-Size $freed))
                }
                'PaketCache' {
                    $p = "$env:ProgramData\Package Cache"
                    $freed = Clear-Folder $p
                    [void](Add-ChangeRecord -Modul 'Wartung' -Schritt $k -Titel $script:RepTitles[$k] -Risiko 'Eingriff' -Art 'Bereinigung' -Ziel $p -Nachher ('{0} gelöscht' -f (Format-Size $freed)) -Gegenbefehl 'nicht umkehrbar' -NurHinweis)
                    Add-RepairResult $k 'OK' ('{0} freigegeben in ProgramData\Package Cache' -f (Format-Size $freed))
                }
                'Wiederherstellungspunkte' {
                    $d = ([string]$env:SystemDrive).TrimEnd('\')
                    $r = Invoke-External -File "$env:windir\System32\vssadmin.exe" -Arguments ('delete shadows /for={0} /all /quiet' -f $d) -TimeoutSec 600
                    $ok = ($r.ExitCode -eq 0 -or ($r.Output + $r.Error) -match 'No items found|Keine Elemente')
                    [void](Add-ChangeRecord -Modul 'Wartung' -Schritt $k -Titel $script:RepTitles[$k] -Risiko 'Eingriff' -Art 'Wiederherstellungspunkte' -Ziel ('Schattenkopien auf {0}' -f $d) -Nachher $(if ($ok) { 'gelöscht' } else { 'Fehler ' + $r.ExitCode }) -Gegenbefehl 'nicht umkehrbar' -NurHinweis)
                    Add-RepairResult $k $(if ($ok) { 'OK' } else { 'Warnung' }) $(if ($ok) { 'Alte Schattenkopien auf dem Systemlaufwerk gelöscht' } else { 'vssadmin Fehler: ' + ($r.Output + ' ' + $r.Error).Trim() })
                }
            }
        }
    }
    if ($script:RestartNeeded.Count) { Add-Finding INFO 'Reparatur' ('Neustart erforderlich, damit diese Reparaturen wirksam werden: {0}.' -f (($script:RestartNeeded | Select-Object -Unique) -join ', ')) }
    if ($script:ChangeCount) {
        Add-Sub 'Änderungsprotokoll'
        Add-Line ('  {0} Einträge in {1}' -f $script:ChangeCount, $script:ChangeFile)
        foreach ($c in @($script:ChangeLog.Eintraege)) { Add-Line ('  {0,2}. {1}: {2} | vorher {3} | nachher {4} | {5}' -f $c.Id, $c.Titel, $c.Ziel, $c.Vorher, $c.Nachher, $(if ($c.Status -eq 'aktiv') { 'rückgängig über die Seite Änderungen' } else { $c.Gegenbefehl })) }
    }
}


