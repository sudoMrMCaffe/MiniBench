#region ---------- Schneller Modus: unabhängige Prüfungen parallel (ab v2.6, Roadmap v2.5) ----------
# Was parallel laufen darf, steht im Modulvertrag (Parallel = $true, Nach = Schritte, die vorher fertig sein müssen,
# Exklusiv = $true für Messungen). Im schnellen Modus starten diese Schritte als Hintergrundaufgaben in einem
# Runspace-Pool; die Abschnitte des Berichts bleiben in derselben Reihenfolge und holen dort nur das Ergebnis ab.
# Vor jeder exklusiven Messung (RAM-Test, Netzwerktest, Benchmark, Lasttest) warten alle Hintergrundaufgaben.
# Hintergrundaufgaben sind in sich geschlossene Skriptblöcke: Sie rufen keine Funktionen dieses Skripts auf.
$script:FastMode   = [bool]$SchnellerModus
$script:BgJobs     = [ordered]@{}
$script:BgPool     = $null
$script:BgDone     = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$script:BgLastTick = [datetime]::MinValue
$script:BgAbandoned = 0   # abgebrochene Aufgaben, deren Runspace noch belegt sein kann

# Abhängigkeiten aus dem Modulvertrag: Key -> @{ Parallel; Exklusiv; Nach }
function Get-StepSchedule([string]$Module) {
    $res = @{}
    $c = Get-ModuleContract $Module
    if (-not $c) { return $res }
    foreach ($s in $c.Schritte) {
        $res[[string]$s.Key] = [pscustomobject]@{ Key = [string]$s.Key; Parallel = [bool]$s.Parallel; Exklusiv = [bool]$s.Exklusiv; Nach = @($s.Nach | Where-Object { $_ }) }
    }
    return $res
}

# Reihenfolge für den Start: ein Schritt startet erst, wenn alle Schritte unter Nach fertig sind (Kreise meldet Test-ModuleContract)
function Test-StepReady($Job) {
    foreach ($n in @($Job.Nach)) { if (-not $script:BgDone.Contains([string]$n)) { return $false } }
    return $true
}

function Initialize-BgPool {
    if ($script:BgPool) { return $true }
    try {
        $iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $script:BgPool = [runspacefactory]::CreateRunspacePool(1, 3, $iss, $Host)
        $script:BgPool.ApartmentState = 'STA'
        $script:BgPool.Open()
        return $true
    } catch { $script:BgPool = $null; Write-Checkpoint 'INFO' ('Schneller Modus nicht verfügbar: {0}' -f $_.Exception.Message); return $false }
}

# Aufgabe anmelden; sie startet, sobald ihre Abhängigkeiten fertig sind (Update-BgJobs)
function Register-BgJob {
    param([string]$Key, [string]$Title, [scriptblock]$Script, [object[]]$Arguments = @(), [string[]]$Nach = @(), [scriptblock]$OnStart = $null, [scriptblock]$OnDone = $null)
    if (-not $script:FastMode) { return $false }
    if (-not (Initialize-BgPool)) { return $false }
    $script:BgJobs[$Key] = [pscustomobject]@{ Key = $Key; Titel = $Title; Script = $Script; Args = @($Arguments); Nach = @($Nach | Where-Object { $_ }); OnStart = $OnStart; OnDone = $OnDone
        Status = 'wartet'; PS = $null; Handle = $null; Start = $null; Ende = $null; Ergebnis = @(); Fehler = '' }
    Send-GuiEvent 'PAR' $Key $Title 'wartet' ''
    Update-BgJobs -Force
    return $true
}

# Fertige Aufgaben abholen und wartende starten. Wird bei jedem Abschnitt und bei jeder Fortschrittsmeldung aufgerufen (billig).
function Update-BgJobs([switch]$Force) {
    if (-not $script:BgJobs.Count) { return }
    $now = Get-Date
    if (-not $Force -and ($now - $script:BgLastTick).TotalMilliseconds -lt 500) { return }
    $script:BgLastTick = $now
    foreach ($j in @($script:BgJobs.Values)) {
        if ($j.Status -eq 'läuft' -and $j.Handle -and $j.Handle.IsCompleted) {
            try {
                $out = $j.PS.EndInvoke($j.Handle)
                $j.Ergebnis = @($out | Where-Object { $null -ne $_ })
                if ($j.PS.Streams.Error.Count) { $j.Fehler = ($j.PS.Streams.Error | Select-Object -First 3 | ForEach-Object { $_.ToString() }) -join '; ' }
            } catch { $j.Fehler = $(if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }) }
            try { $j.PS.Dispose() } catch { }
            $j.PS = $null; $j.Handle = $null
            $j.Ende = Get-Date
            $j.Status = $(if ($j.Fehler -and -not @($j.Ergebnis | Where-Object { $null -ne $_ }).Count) { 'Fehler' } else { 'fertig' })
            [void]$script:BgDone.Add($j.Key)
            if ($j.OnDone) { try { & $j.OnDone $j } catch { } }
            $dur = '{0:mm\:ss}' -f ($j.Ende - $j.Start)
            Send-GuiEvent 'PAR' $j.Key $j.Titel $j.Status $dur
            Write-Checkpoint 'PARALL' ('{0}: {1} nach {2}{3}' -f $j.Titel, $j.Status, $dur, $(if ($j.Fehler) { ' (' + $j.Fehler + ')' } else { '' }))
        }
    }
    foreach ($j in @($script:BgJobs.Values)) {
        if ($j.Status -ne 'wartet' -or -not (Test-StepReady $j)) { continue }
        try {
            if ($j.OnStart) { try { & $j.OnStart $j } catch { } }
            $ps = [powershell]::Create()
            $ps.RunspacePool = $script:BgPool
            [void]$ps.AddScript($j.Script.ToString())
            foreach ($a in $j.Args) { [void]$ps.AddArgument($a) }
            $j.PS = $ps; $j.Start = Get-Date; $j.Handle = $ps.BeginInvoke(); $j.Status = 'läuft'
            Send-GuiEvent 'PAR' $j.Key $j.Titel 'läuft' ''
            Write-Checkpoint 'PARALL' ('{0}: gestartet' -f $j.Titel)
        } catch { $j.Status = 'Fehler'; $j.Fehler = $_.Exception.Message; [void]$script:BgDone.Add($j.Key) }
    }
}

# Ist zu einem Schritt eine Hintergrundaufgabe angemeldet?
function Test-BgJob([string]$Key) { return [bool]($script:BgJobs.Contains($Key)) }

# Auf eine Aufgabe warten (mit Fortschritt) und sie zurückgeben. Nach Ablauf der Frist wird sie abgebrochen.
function Wait-BgJob([string]$Key, [string]$Activity = '', [int]$TimeoutSec = 3600) {
    if (-not $script:BgJobs.Contains($Key)) { return $null }
    $j = $script:BgJobs[$Key]
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($j.Status -in 'wartet', 'läuft') {
        Update-BgJobs -Force
        if ($j.Status -notin 'wartet', 'läuft') { break }
        if ($Activity) { Show-Sub $Activity ('läuft im Hintergrund seit {0:mm\:ss}' -f $(if ($j.Start) { (Get-Date) - $j.Start } else { [TimeSpan]::Zero })) }
        if ($sw.Elapsed.TotalSeconds -ge $TimeoutSec) { Stop-BgJob $j ('nach {0} Minuten abgebrochen' -f [math]::Max(1, [int]($TimeoutSec / 60))); break }
        Start-Sleep -Milliseconds 400
    }
    if ($Activity) { Hide-Sub }
    return $j
}

# Aufgabe abbrechen, ohne zu warten: PowerShell.Stop() und Dispose() blockieren, solange ein COM- oder .NET-Aufruf
# läuft (z. B. eine hängende Updatesuche). BeginStop stößt das Ende nur an, das Objekt wird aufgegeben.
function Stop-BgJob($Job, [string]$Reason) {
    $j = $Job
    if ($j.Status -notin 'wartet', 'läuft') { return }
    $wasRunning = ($j.Status -eq 'läuft')
    if ($j.PS) { try { [void]$j.PS.BeginStop($null, $null) } catch { }; $script:BgAbandoned++ }
    $j.PS = $null; $j.Handle = $null; $j.Status = 'abgebrochen'; $j.Fehler = $Reason; $j.Ende = Get-Date
    [void]$script:BgDone.Add($j.Key)
    # OnDone auch hier: z. B. hebt die Energieanalyse die ausgesetzte Standby-Sperre wieder auf
    if ($wasRunning -and $j.OnDone) { try { & $j.OnDone $j } catch { } }
    Send-GuiEvent 'PAR' $j.Key $j.Titel 'abgebrochen' ''
    Write-Checkpoint 'PARALL' ('{0}: abgebrochen ({1})' -f $j.Titel, $Reason)
}

# Vor exklusiven Messungen: alle Hintergrundaufgaben abwarten
function Wait-BgAll([string]$Reason = '') {
    if (-not $script:BgJobs.Count) { return }
    $open = @($script:BgJobs.Values | Where-Object { $_.Status -in 'wartet', 'läuft' })
    if (-not $open.Count) { return }
    Write-Step ('Warte auf {0} Hintergrundprüfung(en), damit {1} ohne Nebenlast läuft ...' -f $open.Count, $(if ($Reason) { $Reason } else { 'die Messung' }))
    foreach ($j in $open) { [void](Wait-BgJob $j.Key ('Hintergrund: ' + $j.Titel) 3600) }
}

# Zeile für den Bericht: lief parallel, wie lange
function Get-BgNote($Job) {
    if (-not $Job) { return '' }
    $d = $(if ($Job.Start -and $Job.Ende) { '{0:mm\:ss}' -f ($Job.Ende - $Job.Start) } else { '?' })
    return ('  Schneller Modus: lief im Hintergrund parallel zu anderen Prüfungen (Dauer {0}{1}).' -f $d, $(if ($Job.Fehler) { ', Meldung: ' + $Job.Fehler } else { '' }))
}

function Stop-BgJobs {
    Update-BgJobs -Force
    foreach ($j in @($script:BgJobs.Values)) { Stop-BgJob $j 'beim Laufende abgebrochen' }
    # Pool nur schließen, wenn nichts mehr läuft; sonst blockiert Close(). Aufgegebene Aufgaben endet das Prozessende.
    if (-not $script:BgAbandoned) { try { if ($script:BgPool) { $script:BgPool.Close(); $script:BgPool.Dispose() } } catch { } }
    $script:BgPool = $null
}

# Schritt eines Abschnitts aus dem Titel (für Abhängigkeiten auf Abschnitte im Vordergrund und die Sperre vor Messungen)
function Get-SectionStepKey([string]$Title) {
    switch -Regex ($Title) {
        '^Test: Dateisystem und Systemdateien' { return 'Integritaet' }
        '^Test: Microsoft Defender' { return 'Defender' }
        '^Test: SMART-Langtest wird gestartet' { return 'SmartLang' }
        '^Test: Netzwerk' { return 'Netzwerk' }
        '^Test: Arbeitsspeicher' { return 'RamTest' }
        '^Energie$' { return 'Energieanalyse' }
        '^Ereignisprotokolle' { return 'Ereignisse' }
        '^Updates$' { return 'Updatesuche' }
        '^(Benchmark|Lasttest)' { return 'Messung' }
        default { return '' }
    }
}

# Haken für Invoke-Section: vor exklusiven Schritten warten, danach den Schritt als fertig markieren
function Enter-SectionSchedule([string]$Title) {
    if (-not $script:BgJobs.Count) { return }
    Update-BgJobs -Force
    $k = Get-SectionStepKey $Title
    if (-not $k) { return }
    $excl = ($k -eq 'Messung')
    if (-not $excl) { $sch = Get-StepSchedule 'Diagnose'; if ($sch.ContainsKey($k) -and $sch[$k].Exklusiv) { $excl = $true } }
    if ($excl) { Wait-BgAll ('"' + $Title + '"') }
}
function Exit-SectionSchedule([string]$Title) {
    $k = Get-SectionStepKey $Title
    if ($k -and $k -ne 'Messung' -and -not (Test-BgJob $k)) { [void]$script:BgDone.Add($k) }
    if ($script:BgJobs.Count) { Update-BgJobs -Force }
}

# Abhängigkeiten, die in diesem Lauf nicht vorkommen (nicht gewählt, Defender inaktiv), gelten als erfüllt
function Get-ActiveDeps([string[]]$Nach) {
    return @(@($Nach) | Where-Object { $_ -and $script:Opt[$_] -and ($_ -ne 'Defender' -or $script:DefenderActive) -and ($_ -ne 'SmartLang' -or ($script:Smartctl -and @($script:SmartDevices).Count)) })
}

# Hintergrundaufgaben des Moduls Diagnose anmelden, sobald ihre Voraussetzungen bekannt sind:
#   Start     zu Beginn des Moduls (Updatesuche)
#   Defender  nach dem Abschnitt Sicherheit (Defender aktiv?), dazu die Energieanalyse (wartet laut Vertrag auf Defender)
#   SMART     nach dem Abschnitt SMART-Daten (Laufwerke bekannt)
function Start-DiagnoseParallel([string]$Phase) {
    if (-not $script:FastMode -or -not $ModDiag -or $AnalyzeLastRun -or $Kurztest) { return }
    $sch = Get-StepSchedule 'Diagnose'
    $n = 0
    switch ($Phase) {
        'Start' {
            if ($script:Opt['Updatesuche'] -and $sch['Updatesuche'].Parallel) {
                $n += [int](Register-BgJob -Key 'Updatesuche' -Title 'Suche nach ausstehenden Updates' -Nach (Get-ActiveDeps $sch['Updatesuche'].Nach) -Script {
                    $s = New-Object -ComObject Microsoft.Update.Session
                    $r = $s.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0")
                    foreach ($u in $r.Updates) { [pscustomobject]@{ Titel = $u.Title; KB = ($u.KBArticleIDs -join ','); Pflicht = $u.IsMandatory; Neustart = $u.RebootRequired } }
                })
            }
        }
        'Defender' {
            if ($script:Opt['Defender'] -and $script:DefenderActive -and $sch['Defender'].Parallel) {
                $n += [int](Register-BgJob -Key 'Defender' -Title 'Defender Schnellscan' -Nach (Get-ActiveDeps $sch['Defender'].Nach) -Script {
                    $t0 = Get-Date
                    Update-MpSignature -ErrorAction SilentlyContinue
                    Start-MpScan -ScanType QuickScan -ErrorAction Stop
                    [pscustomobject]@{ Start = $t0; Ende = (Get-Date) }
                })
            }
            if ($script:Opt['Energieanalyse'] -and $sch['Energieanalyse'].Parallel) {
                $html = Join-Path $RawDir 'Energiebericht.html'; $dx = Join-Path $RawDir 'dxdiag.txt'
                # eigene Standby-Sperre während der Energieanalyse aussetzen, damit sie nicht im Energiebericht erscheint
                $n += [int](Register-BgJob -Key 'Energieanalyse' -Title 'Energieanalyse und DxDiag' -Nach (Get-ActiveDeps $sch['Energieanalyse'].Nach) -Arguments @($html, $dx, $script:OemEnc.CodePage, "$env:windir\System32\dxdiag.exe") `
                    -OnStart { Suspend-StandbyLock } -OnDone { Resume-StandbyLock } -Script {
                    param($Html, $Dx, $Oem, $DxExe)
                    $psi = New-Object Diagnostics.ProcessStartInfo 'powercfg.exe', ('/energy /output "{0}" /duration 60' -f $Html)
                    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
                    try { $psi.StandardOutputEncoding = [Text.Encoding]::GetEncoding($Oem) } catch { }
                    $p = [Diagnostics.Process]::Start($psi)
                    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
                    if (-not $p.WaitForExit(180000)) { try { $p.Kill() } catch { } }
                    $res = [pscustomobject]@{ Output = $o.Result; Error = $e.Result; ExitCode = $(try { $p.ExitCode } catch { -1 }); DxDiag = $false }
                    try {
                        $d = Start-Process -FilePath $DxExe -ArgumentList ('/t "{0}"' -f $Dx) -WindowStyle Hidden -PassThru
                        if (-not $d.WaitForExit(240000)) { try { $d.Kill() } catch { } }
                    } catch { }
                    $res.DxDiag = (Test-Path -LiteralPath $Dx)
                    $res
                })
            }
        }
        'SMART' {
            if ($script:Opt['SmartLang'] -and $script:Smartctl -and @($script:SmartDevices).Count -and $sch['SmartLang'].Parallel) {
                $devs = @($script:SmartDevices | ForEach-Object { [pscustomobject]@{ name = $_.name; type = $_.type } })
                $n += [int](Register-BgJob -Key 'SmartLang' -Title 'SMART-Langtest starten' -Nach (Get-ActiveDeps $sch['SmartLang'].Nach) -Arguments @($script:Smartctl, $devs) -Script {
                    param($Exe, $Devs)
                    foreach ($d in $Devs) {
                        $psi = New-Object Diagnostics.ProcessStartInfo $Exe, ('-t long -d {0} {1}' -f $d.type, $d.name)
                        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
                        $t = Get-Date
                        $p = [Diagnostics.Process]::Start($psi)
                        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
                        if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch { } }
                        [pscustomobject]@{ Name = $d.name; Start = $t; Output = $o.Result; Error = $e.Result; ExitCode = $(try { $p.ExitCode } catch { -1 }) }
                    }
                })
            }
        }
    }
    if ($n) {
        $names = @($script:BgJobs.Values | Where-Object { $_.Status -in 'wartet', 'läuft' } | ForEach-Object { $_.Titel }) -join ', '
        Write-Step ('Schneller Modus: im Hintergrund laufen jetzt {0}. Messungen warten darauf.' -f $names)
    }
}
#endregion
