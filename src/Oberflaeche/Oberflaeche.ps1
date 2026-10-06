#region ---------- Grafische Oberfläche ----------
if (-not $EventMode -and -not $ImportOrdner -and -not $Vergleich -and -not $Rueckgaengig -and -not $SensorLive -and -not $SensorWerkzeugeHolen -and -not $SensorAufraeumen -and -not $OptimierungZustand -and -not $OptWerkzeugeHolen -and -not $Dashboard -and -not $DashboardExport -and -not $DashboardSysteme) {
    Write-StartPhase 'Datenordner gefunden'
    # Hardwareabfragen für die Oberfläche (Datenträgerliste, Geräteidentität) laufen parallel zum Laden der Oberfläche
    $hwPs = $null; $hwHandle = $null
    try {
        $hwPs = [powershell]::Create()
        [void]$hwPs.AddScript({
            $res = [ordered]@{ Disks = @(); Uuid = ''; Bv = ''; Bp = ''; Bs = ''; Bios = ''; Gpus = @(); Domain = $false }
            try {
                $res.Disks = @(foreach ($pd in @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object { [int]$_.DeviceId })) {
                    $num = [int]$pd.DeviceId
                    $letters = @(Get-Partition -DiskNumber $num -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object { '{0}:' -f $_.DriveLetter } | Sort-Object) -join ', '
                    [pscustomobject]@{ Num = $num; Name = ([string]$pd.FriendlyName).Trim(); Bus = [string]$pd.BusType; Medium = [string]$pd.MediaType; Size = [double]$pd.Size; Letters = $letters }
                })
            } catch { }
            try { $res.Uuid = [string](Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID } catch { }
            try { $bb = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1; $res.Bv = [string]$bb.Manufacturer; $res.Bp = [string]$bb.Product; $res.Bs = [string]$bb.SerialNumber } catch { }
            try { $res.Bios = [string](Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber } catch { }
            # Grafikeinheiten für die Auswahl im Benchmark und im Lasttest (ab v2.65)
            try { $res.Gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { ([string]$_.Name).Trim() } | Where-Object { $_ }) } catch { }
            # Domänenmitgliedschaft für die Vorlagen der Optimierung (ab v2.8)
            try { $res.Domain = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { }
            [pscustomobject]$res
        })
        $hwHandle = $hwPs.BeginInvoke()
    } catch { $hwPs = $null }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        [void][Windows.Forms.MessageBox]::Show('PowerShell läuft hier im Constrained Language Mode (AppLocker oder WDAC). Die Oberfläche und die Testroutinen von Leos Minibench sind so nicht verfügbar.', 'Leos Minibench', 'OK', 'Warning')
        exit 1
    }
    $guiCode = @'
#>> EINBINDEN Oberflaeche\DiagGui.cs
#>> EINBINDEN Oberflaeche\DiagGui_Steuerelemente.cs
#>> EINBINDEN Oberflaeche\DiagGui_Modelle.cs
#>> EINBINDEN Oberflaeche\DiagGui_Vergleich.cs
#>> EINBINDEN Oberflaeche\DiagGui_Seiten.cs
#>> EINBINDEN Oberflaeche\Start.cs
#>> EINBINDEN Oberflaeche\Versionen.cs
'@
    try {
        if (-not ('DiagGui' -as [type])) {
            Write-StartPhase 'Oberfläche wird geladen'
            Add-Type -AssemblyName System.Web.Extensions
            $refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
            Add-CachedType 'LeosMinibench-Oberflaeche' $guiCode $refs
            Write-StartPhase ('Oberfläche geladen ({0})' -f $(if ($script:CacheInfo.Count) { $script:CacheInfo[$script:CacheInfo.Count - 1] } else { 'ohne Cache' }))
        }
        # Datenträger für die Auswahl im Benchmark und im Lasttest: Nummer|Name|Bus|Medium|Größe|Buchstaben|USB
        $diskList = [System.Collections.Generic.List[string]]::new()
        $hw = $null
        if ($hwPs) { try { if ($hwHandle.AsyncWaitHandle.WaitOne(20000)) { $hw = @($hwPs.EndInvoke($hwHandle)) | Select-Object -First 1 } } catch { }; try { $hwPs.Dispose() } catch { } }
        foreach ($d in @($(if ($hw) { $hw.Disks }))) {
            $sz = [double]$d.Size
            $szT = $(if ($sz -ge 1e12) { '{0:N1} TB' -f ($sz / 1e12) } elseif ($sz -ge 1e9) { '{0:N0} GB' -f ($sz / 1e9) } else { '{0:N0} MB' -f ($sz / 1e6) })
            $diskList.Add(('{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $d.Num, (([string]$d.Name) -replace '\|', '/'), $d.Bus, $d.Medium, $szT, $d.Letters, $(if ([string]$d.Bus -eq 'USB') { '1' } else { '0' })))
        }
        # Datenpflege (ab v2.7): Lasttests vor v2.67, unvollständige und kurze Läufe ins Archiv; frische Läufe (unter 60 Min.) bleiben
        try {
            $dp = Invoke-Datenpflege -DataDir $script:DataDir -MindestAlterMin 60
            if ($dp.Verschoben -or $dp.Fehler) { [DiagGui]::DatenpflegeInfo = ('Datenpflege beim Start: {0}. Protokoll: {1}' -f $dp.Kurz, (Join-Path $dp.Archiv 'Datenpflege.log')) }
            Write-StartPhase ('Datenpflege: {0}' -f $dp.Kurz)
        } catch { }
        if ($hw -and -not $script:DeviceIdentity) { try { $script:DeviceIdentity = ConvertTo-DeviceId -Uuid $hw.Uuid -BoardVendor $hw.Bv -BoardProduct $hw.Bp -BoardSerial $hw.Bs -BiosSerial $hw.Bios -ComputerName $env:COMPUTERNAME } catch { } }
        Write-StartPhase 'Datenträger und Geräteidentität gelesen'
        if ($script:DataDirFallback) { [void][Windows.Forms.MessageBox]::Show(('Der Ordner neben dem Programm ist nicht beschreibbar (USB-Stick schreibgeschützt?). Ersatzweise wird verwendet:' + "`r`n" + $script:DataDir), 'Leos Minibench', 'OK', 'Warning') }
        elseif (-not $script:DataDir) { [void][Windows.Forms.MessageBox]::Show('Es wurde kein beschreibbarer Ordner für Berichte gefunden.', 'Leos Minibench', 'OK', 'Error'); exit 1 }
        New-Item -ItemType Directory -Path $script:CpDir -Force | Out-Null
        $devId = ''; try { $devId = [string](Get-DeviceIdentity).Id } catch { }
        try { [DiagGui]::GpuNames = [string[]]@($(if ($hw) { $hw.Gpus })) } catch { }
        try { [DiagGui]::OptKatalog = [string[]](Get-OptGuiLines); [DiagGui]::DomainPc = [bool]($hw -and $hw.Domain) } catch { }
        Write-StartPhase 'Fenster wird aufgebaut'
        [DiagGui]::Run((Get-Process -Id $PID).Path, $PSCommandPath, $script:CpDir, $script:DataDir, $ScriptVersion, $diskList.ToArray(), [string[]](Get-ContractGuiLines), $devId)
        exit 0
    } catch {
        [void][Windows.Forms.MessageBox]::Show(('Die Oberfläche konnte nicht gestartet werden:' + "`r`n`r`n" + $_.Exception.Message), 'Leos Minibench', 'OK', 'Error')
        exit 1
    }
}
#endregion


