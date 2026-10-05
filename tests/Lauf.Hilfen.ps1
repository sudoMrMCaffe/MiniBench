# Gesamtlauf des Arbeitsprozesses unter PowerShell 7 (auch Linux) mit Attrappen für Windows-Befehle.
#
# Das Skript wird wie von Bauen.cmd zusammengebaut. Drei Teile werden für den Test ersetzt:
#   Kern\Adminrechte.ps1   immer Administrator
#   Kern\Testroutinen.ps1  echte C#-Routinen ohne Windows-Aufrufe (Standby-Sperre und Speicherlast als Attrappe)
#   nach 00_Kopf.ps1       Vorspann mit Zeitraffer (Start-Sleep kostet keine Zeit, Get-Date läuft entsprechend vor)
#                          und Attrappen für CIM, Datenträger, Ereignisprotokoll und PnP
# Der Lauf startet als eigener Prozess mit -EventMode, also genau so, wie die Oberfläche ihn startet.

. (Join-Path $PSScriptRoot 'Hilfen.ps1')

$global:MinibenchLaufVorspann = @'
#region ---------- TESTVORSPANN (nur im Testlauf) ----------
$global:__Warp = [TimeSpan]::Zero
function Start-Sleep { param([Parameter(Position = 0)][double]$Seconds = 0, [int]$Milliseconds = 0) $global:__Warp = $global:__Warp + [TimeSpan]::FromMilliseconds($Seconds * 1000 + $Milliseconds + 5) }
function Get-Date {
    param([Parameter(Position = 0)]$Date, [string]$Format, [string]$UFormat, [int]$Year, [int]$Month, [int]$Day, [int]$Hour, [int]$Minute, [int]$Second)
    $p = @{}
    foreach ($k in 'Year', 'Month', 'Day', 'Hour', 'Minute', 'Second') { if ($PSBoundParameters.ContainsKey($k)) { $p[$k] = $PSBoundParameters[$k] } }
    if ($null -ne $Date) { $d = Microsoft.PowerShell.Utility\Get-Date -Date $Date @p } else { $d = (Microsoft.PowerShell.Utility\Get-Date @p) + $global:__Warp }
    if ($Format) { return $d.ToString($Format) }
    return $d
}
$global:__Cim = @{
    'Win32_ComputerSystem' = @([pscustomobject]@{ Manufacturer = 'Testhersteller'; Model = 'Testmodell 1'; UserName = 'TEST\tester'; PartOfDomain = $false; Domain = 'WORKGROUP'; TotalPhysicalMemory = 17179869184; PCSystemType = 1 })
    'Win32_OperatingSystem' = @([pscustomobject]@{ Caption = 'Microsoft Windows 11 Pro'; BuildNumber = '26200'; Version = '10.0.26200'; LastBootUpTime = (Microsoft.PowerShell.Utility\Get-Date).AddHours(-2); InstallDate = (Microsoft.PowerShell.Utility\Get-Date).AddDays(-200); FreePhysicalMemory = 8388608; TotalVisibleMemorySize = 16777216; OSArchitecture = '64-Bit' })
    'Win32_BIOS' = @([pscustomobject]@{ SMBIOSBIOSVersion = '1.0'; ReleaseDate = (Microsoft.PowerShell.Utility\Get-Date).AddYears(-1); SerialNumber = 'BIOS123456' })
    'Win32_BaseBoard' = @([pscustomobject]@{ Manufacturer = 'Testboard'; Product = 'TB-1'; SerialNumber = 'BB12345678' })
    'Win32_SystemEnclosure' = @([pscustomobject]@{ ChassisTypes = @(3) })
    'Win32_Processor' = @([pscustomobject]@{ Name = 'Intel(R) Core(TM) i5-12400 CPU'; NumberOfCores = 6; NumberOfLogicalProcessors = 12; MaxClockSpeed = 2500; CurrentClockSpeed = 2500; Manufacturer = 'GenuineIntel'; VirtualizationFirmwareEnabled = $true; L2CacheSize = 7680; L3CacheSize = 18432 })
    'Win32_PhysicalMemory' = @([pscustomobject]@{ Capacity = 8589934592; SMBIOSMemoryType = 26; Speed = 3200; ConfiguredClockSpeed = 3200; PartNumber = 'TESTRAM'; Manufacturer = 'Test'; SerialNumber = 'RAM1234567'; DeviceLocator = 'DIMM1' }, [pscustomobject]@{ Capacity = 8589934592; SMBIOSMemoryType = 26; Speed = 3200; ConfiguredClockSpeed = 3200; PartNumber = 'TESTRAM'; Manufacturer = 'Test'; SerialNumber = 'RAM7654321'; DeviceLocator = 'DIMM2' })
    'Win32_VideoController' = @([pscustomobject]@{ Name = 'NVIDIA GeForce RTX 3060'; AdapterRAM = 4293918720; DriverVersion = '31.0.15.1'; DriverDate = (Microsoft.PowerShell.Utility\Get-Date).AddMonths(-3); CurrentHorizontalResolution = 1920; CurrentVerticalResolution = 1080; CurrentRefreshRate = 60; Status = 'OK'; PNPDeviceID = 'PCI\VEN_10DE&DEV_2504'; VideoProcessor = 'GA106' }, [pscustomobject]@{ Name = 'Intel(R) UHD Graphics 730'; AdapterRAM = 1073741824; DriverVersion = '31.0.101.1'; DriverDate = (Microsoft.PowerShell.Utility\Get-Date).AddMonths(-5); CurrentHorizontalResolution = $null; CurrentVerticalResolution = $null; CurrentRefreshRate = $null; Status = 'OK'; PNPDeviceID = 'PCI\VEN_8086&DEV_4692'; VideoProcessor = 'Intel UHD' })
    'Win32_PerfFormattedData_Counters_ProcessorInformation' = @([pscustomobject]@{ Name = '_Total'; PercentProcessorTime = 100; PercentProcessorPerformance = 160; PercentofMaximumFrequency = 100; ProcessorFrequency = 2500 }, [pscustomobject]@{ Name = '0,0'; PercentProcessorTime = 100; PercentProcessorPerformance = 170; PercentofMaximumFrequency = 100; ProcessorFrequency = 2500 })
}
function Get-CimInstance {
    [CmdletBinding()] param([Parameter(Position = 0)][string]$ClassName, [string]$Namespace, [string]$Filter, [string]$Query, [string[]]$Property)
    if ($Query -and $Query -match 'from\s+(\w+)') { $ClassName = $Matches[1] }
    if ($global:__Cim.ContainsKey($ClassName)) { return $global:__Cim[$ClassName] }
    if ($ClassName -eq 'Win32_Process') { return [pscustomobject]@{ ParentProcessId = 0 } }
    return @()
}
function Get-CimClass { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) return $null }
function Get-PhysicalDisk { [CmdletBinding()] param($DeviceNumber, [Parameter(ValueFromRemainingArguments = $true)]$Rest) @([pscustomobject]@{ DeviceId = '0'; FriendlyName = 'TEST NVMe 1TB'; BusType = 'NVMe'; MediaType = 'SSD'; Size = 1000204886016; SerialNumber = 'DISK12345678'; HealthStatus = 'Healthy'; OperationalStatus = 'OK'; SpindleSpeed = 0 }) }
function Get-Disk { [CmdletBinding()] param($Number, [Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
function Get-Partition { [CmdletBinding()] param($DiskNumber, $DriveLetter, [Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
function Get-Volume { [CmdletBinding()] param($DriveLetter, [Parameter(ValueFromRemainingArguments = $true)]$Rest) if ($env:MINIBENCH_TEST_VOLUME -and $DriveLetter) { return [pscustomobject]@{ DriveLetter = [string]$DriveLetter; SizeRemaining = [uint64]3GB; Size = [uint64]1TB; FileSystem = 'NTFS'; DriveType = 'Fixed'; HealthStatus = 'Healthy' } }; @() }
function Get-StorageReliabilityCounter { [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)]$InputObject, [Parameter(ValueFromRemainingArguments = $true)]$Rest) $null }
function Get-WinEvent { [CmdletBinding()] param($FilterHashtable, $LogName, $MaxEvents, $Oldest, [Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
function Get-PnpDevice { [CmdletBinding()] param($Class, $Status, $PresentOnly, [Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
function Get-PnpDeviceProperty { [CmdletBinding()] param($InstanceId, $KeyName, [Parameter(ValueFromRemainingArguments = $true)]$Rest) throw 'nicht verfügbar' }
function Get-Service { [CmdletBinding()] param([Parameter(Position = 0)]$Name, [Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
function Get-ComputerRestorePoint { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
function Get-MpComputerStatus { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) throw 'nicht verfügbar' }
function Get-NetAdapter { [CmdletBinding()] param($Physical, [Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
function Get-NetIPConfiguration { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
function Get-BitLockerVolume { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
function Get-Tpm { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) throw 'nicht verfügbar' }
function Confirm-SecureBootUEFI { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) throw 'nicht verfügbar' }
function Get-ScheduledTask { [CmdletBinding()] param($TaskName, $TaskPath, [Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
function Checkpoint-Computer { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
function Enable-ComputerRestore { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
function Get-NetFirewallProfile { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) @([pscustomobject]@{ Name = 'Domain'; Enabled = $true }, [pscustomobject]@{ Name = 'Private'; Enabled = $true }, [pscustomobject]@{ Name = 'Public'; Enabled = $true }) }
function Get-NetAdapterStatistics { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
function Get-HotFix { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
# System.Management gibt es unter Linux nicht: DMTF-Zeitstempel selbst bilden
function ConvertTo-TestDmtf($d) { return ([datetime]$d).ToString('yyyyMMddHHmmss.ffffff') + '+000' }
#endregion
'@

$global:MinibenchLaufTestroutinen = @(
    '#region ---------- C#-Testroutinen (TESTFASSUNG ohne Windows-Aufrufe) ----------'
    'if (-not (''DiagDiskStress'' -as [type])) {'
    '    $csCode = @' + "'"
    '#>> TESTCODE'
    "'" + '@'
    '    # als Datei übersetzen wie Add-CachedType: der Lastprozess (ab v2.67) lädt dieselbe Bibliothek'
    '    $__dll = Join-Path $PSScriptRoot ''Typen.dll'''
    '    try { Add-Type -TypeDefinition $csCode -OutputAssembly $__dll -OutputType Library -ErrorAction Stop; Add-Type -Path $__dll -ErrorAction Stop }'
    '    catch { Add-Type -TypeDefinition $csCode -ErrorAction Stop }'
    '}'
    '$TypesLoaded = [bool](''DiagDiskStress'' -as [type])'
    '#>> STANDBY'
    '#endregion'
) -join "`r`n"

function New-MinibenchLaufSkript([string]$Ziel) {
    $b = Get-MinibenchBuild
    $lines = $b.Text -split "`r`n"
    $out = New-Object System.Collections.Generic.List[string]
    $cs = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Testroutinen.cs'))
    # Windows-Aufrufe der Testroutinen durch Attrappen ersetzen (SetThreadExecutionState zählt nur mit)
    $cs = $cs -replace '(?s)public static class DiagPower \{.*?\n\}', (Get-Content -Raw (Join-Path $PSScriptRoot 'Daten/Lauf/DiagPower_Attrappe.cs') -Encoding UTF8)
    $cs = $cs -replace 'if \(!GlobalMemoryStatusEx\(ref m\)\) return 0;', 'if (m.dwLength > 0) return 40;'
    # GPU-Rendertest: Klassen GpuAdapter und GpuRun aus Grafiktest.cs, DiagGpu als Attrappe (ohne Direct3D und WinForms)
    $gt = [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot 'Kern/Grafiktest.cs'))
    $cls = $gt.Substring($gt.IndexOf('public class GpuAdapter'), $gt.IndexOf('public static class DiagGpu') - $gt.IndexOf('public class GpuAdapter'))
    $cls = $cls -replace 'public Bitmap Image;', 'public object Image;'
    $gpuFake = (Get-Content -Raw (Join-Path $PSScriptRoot 'Daten/Lauf/DiagGpu_Attrappe.cs') -Encoding UTF8).Replace('//>> KLASSEN', $cls)
    $cs = $cs + "`r`n" + ($gpuFake -replace '(?m)^using [^;]+;\s*$', '')
    $tr = $global:MinibenchLaufTestroutinen.Replace('#>> TESTCODE', $cs)
    $origTr = Get-PartText 'Kern\Testroutinen.ps1'
    $trLines = @($origTr -split "`r`n")
    $from = -1; for ($k = 0; $k -lt $trLines.Count; $k++) { if ($trLines[$k] -match '^\$TypesLoaded\s*=') { $from = $k + 1 } }
    $standby = @(if ($from -gt 0) { $trLines[$from..($trLines.Count - 1)] | Where-Object { $_ -notmatch '^#endregion' } }) -join "`r`n"
    $tr = $tr.Replace('#>> STANDBY', $standby)
    $prev = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $d = $(if ($i -lt $b.Herkunft.Count) { $b.Herkunft[$i].Datei } else { '' })
        $isTr = ($d -eq 'Kern\Testroutinen.ps1' -or $d -eq 'Kern\Testroutinen.cs' -or $d -eq 'Kern\Grafiktest.cs')
        if ($d -eq 'Kern\Adminrechte.ps1') { if ($prev -ne $d) { $out.Add('$isAdmin = $true') }; $prev = $d; continue }
        if ($isTr) { if ($prev -ne 'TR') { foreach ($l in ($tr -split "`r?`n")) { $out.Add($l) } }; $prev = 'TR'; continue }
        if ($prev -eq '00_Kopf.ps1' -and $d -ne '00_Kopf.ps1') { foreach ($l in ($global:MinibenchLaufVorspann -split "`r?`n")) { $out.Add($l) } }
        $out.Add(($lines[$i] -replace '\[(System\.)?Management\.ManagementDateTimeConverter\]::ToDmtfDateTime\(', 'ConvertTo-TestDmtf(')); $prev = $d
    }
    [IO.File]::WriteAllText($Ziel, ($out -join "`r`n"), (New-Object Text.UTF8Encoding($true)))
}

# Startet einen Lauf und liefert Ereignisse, Rückgabecode und Bericht
function Invoke-MinibenchLauf {
    param([string[]]$Argumente, [string]$Name = 'Lauf', [int]$TimeoutSec = 300, [hashtable]$Umgebung = @{})
    $root = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchLauf_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $skript = Join-Path $root 'LeosMinibench.ps1'
    New-MinibenchLaufSkript $skript
    $daten = Join-Path $root 'Minibench-Daten'
    New-Item -ItemType Directory -Path $daten -Force | Out-Null
    $envSet = @{ COMPUTERNAME = 'TESTPC'; windir = (Join-Path $root 'Windows'); SystemDrive = $root; ProgramFiles = (Join-Path $root 'Programme'); ProgramData = (Join-Path $root 'ProgramData'); PUBLIC = (Join-Path $root 'Public'); TEMP = (Join-Path $root 'Temp'); USERNAME = 'tester' }
    foreach ($k in $envSet.Keys) { if ($k -notin 'COMPUTERNAME', 'USERNAME') { New-Item -ItemType Directory -Path $envSet[$k] -Force -ErrorAction SilentlyContinue | Out-Null } }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Process -Id $PID).Path
    $psi.Arguments = ('-NoProfile -NonInteractive -File "{0}" -EventMode -DatenDir "{1}" {2}' -f $skript, $daten, ($Argumente -join ' '))
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    foreach ($k in $envSet.Keys) { $psi.Environment[$k] = $envSet[$k] }
    foreach ($k in $Umgebung.Keys) { $psi.Environment[$k] = [string]$Umgebung[$k] }
    # Testdateien (z. B. des Datenträgertests) landen im Testordner, nicht im Arbeitsordner von Pester
    $psi.WorkingDirectory = $root
    $p = [Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill($true) } catch { }; throw ('Lauf {0} hat nach {1} s nicht geendet.' -f $Name, $TimeoutSec) }
    $out = $outTask.Result -split "`r?`n"
    $events = @($out | Where-Object { $_ -like '@@*' })
    $done = @($events | Where-Object { $_ -like '@@DONE|*' }) | Select-Object -First 1
    $bericht = ''; $html = ''; $ordner = ''
    if ($done) {
        $parts = $done.Substring(2).Split('|')
        if ($parts.Count -gt 1 -and (Test-Path -LiteralPath $parts[1])) { $bericht = [IO.File]::ReadAllText($parts[1]) }
        if ($parts.Count -gt 2 -and $parts[2] -and (Test-Path -LiteralPath $parts[2])) { $html = [IO.File]::ReadAllText($parts[2]) }
        if ($parts.Count -gt 3) { $ordner = $parts[3] }
    }
    [pscustomobject]@{
        Name = $Name; ExitCode = $p.ExitCode; Ereignisse = $events; Ausgabe = $out; Fehlerausgabe = $errTask.Result
        Bericht = $bericht; Html = $html; Ordner = $ordner; Daten = $daten; Wurzel = $root
        Log = @($events | Where-Object { $_ -like '@@LOG|*' } | ForEach-Object { $_.Substring(6) })
    }
}
