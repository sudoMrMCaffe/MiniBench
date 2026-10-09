# Gemeinsame Hilfen für die Pester-Tests (Pester 5, Windows PowerShell 5.1 oder PowerShell 7)
#
# Die Tests prüfen den Quelltext in src. Dafür wird das Skript im Speicher zusammengebaut und das Gewünschte in ein
# Testmodul geladen: ganze Kernteile ohne Seiteneffekte (Risiko, Modulvertrag, ...) und einzelne Funktionen aus den übrigen.
# So läuft nichts vom eigentlichen Ablauf (Oberfläche, Adminrechte, Berichtsordner).

$global:MinibenchRepoRoot = Split-Path $PSScriptRoot -Parent
$global:MinibenchSrcRoot  = Join-Path $global:MinibenchRepoRoot 'src'
$global:MinibenchTestData = Join-Path $PSScriptRoot 'Daten'
. (Join-Path $global:MinibenchSrcRoot 'Zusammenbau.ps1')

function Get-MinibenchBuild {
    if (-not $global:MinibenchTestBuild) { $global:MinibenchTestBuild = Invoke-MinibenchBuild -SrcDir $global:MinibenchSrcRoot }
    return $global:MinibenchTestBuild
}

function Get-MinibenchAst {
    if (-not $global:MinibenchTestAst) {
        $t = $null; $e = $null
        $global:MinibenchTestAst = [System.Management.Automation.Language.Parser]::ParseInput((Get-MinibenchBuild).Text, [ref]$t, [ref]$e)
    }
    return $global:MinibenchTestAst
}

# Text eines Quelltextteils, wie er im zusammengebauten Skript steht (eingebundene Dateien eingesetzt)
function Get-PartText([string]$Part) {
    $b = Get-MinibenchBuild
    $lines = $b.Text -split "`r`n"
    $first = -1; $last = -1
    for ($i = 0; $i -lt $b.Herkunft.Count; $i++) { if ($b.Herkunft[$i].Datei -eq $Part) { if ($first -lt 0) { $first = $i }; $last = $i } }
    if ($first -lt 0) { throw ('Teil {0} kommt im Bauplan nicht vor.' -f $Part) }
    return (($lines[$first..$last]) -join "`r`n")
}

# Alle Funktionen, die nicht in einer anderen Funktion stehen, als Name -> Quelltext
function Get-TopFunctions {
    $res = [ordered]@{}
    foreach ($f in (Get-MinibenchAst).FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        $p = $f.Parent; $nested = $false
        while ($p) { if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $nested = $true; break }; $p = $p.Parent }
        if ($nested) { continue }
        if ($res.Contains($f.Name)) { $res[$f.Name] = @($res[$f.Name]) + $f.Extent.Text } else { $res[$f.Name] = $f.Extent.Text }
    }
    return $res
}

# Parameter des Skripts (param-Block)
function Get-ScriptParameters { @((Get-MinibenchAst).ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }

# Testmodul laden. -Parts: ganze Teile, -Functions: einzelne Funktionen aus dem übrigen Skript, -Setup: Vorbelegung
function Import-MinibenchTestModule {
    param([string[]]$Parts = @(), [string[]]$Functions = @(), [string]$Setup = '')
    Get-Module MinibenchTest | Remove-Module -Force
    $sb = New-Object System.Text.StringBuilder
    # Windows-Befehle, die es unter PowerShell 7 auf Linux nicht gibt, als Platzhalter (Tests ersetzen sie per Mock)
    foreach ($c in 'Get-WinEvent', 'Get-CimInstance', 'Get-Service', 'Set-Service', 'Get-Volume', 'Get-PhysicalDisk', 'Get-ComputerRestorePoint') {
        if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { [void]$sb.AppendLine(('function {0} {{ throw "{0} ist hier nicht verfügbar" }}' -f $c)) }
    }
    [void]$sb.AppendLine(('$ScriptVersion = ''{0}''; $AppName = ''Leos Minibench''; $script:Inv = [Globalization.CultureInfo]::InvariantCulture' -f (Get-MinibenchBuild).Version))
    [void]$sb.AppendLine('$script:DataDir = ''''; $script:DbDir = ''''; $OutputDir = ''''; $RawDir = ''''; $script:OemEnc = [Text.Encoding]::UTF8')
    foreach ($p in $Parts) { [void]$sb.AppendLine((Get-PartText $p)) }
    $all = Get-TopFunctions
    foreach ($f in $Functions) {
        if (-not $all.Contains($f)) { throw ('Funktion {0} gibt es im Skript nicht.' -f $f) }
        [void]$sb.AppendLine((@($all[$f])[0]))
    }
    if ($Setup) { [void]$sb.AppendLine($Setup) }
    [void]$sb.AppendLine('Export-ModuleMember -Function * -Variable *')
    New-Module -Name MinibenchTest -ScriptBlock ([scriptblock]::Create($sb.ToString())) | Import-Module -Force -Global -DisableNameChecking
    if (-not $env:COMPUTERNAME) { $env:COMPUTERNAME = 'TESTPC' }
}

# Variable im Testmodul setzen bzw. lesen
function Set-ModuleVar([string]$Name, $Value) { & (Get-Module MinibenchTest) { param($n, $v) Set-Variable -Scope Script -Name $n -Value $v } $Name $Value }
function Get-ModuleVar([string]$Name) { $v = & (Get-Module MinibenchTest) { param($n) Get-Variable -Scope Script -Name $n -ValueOnly } $Name; return $v }

# ---------- Gemeinsame Hilfen ab v3.53 (Umbau der Testsuite nach Fachgebieten) ----------

# Läuft der Test unter Windows? (Windows PowerShell 5.1 kennt $IsWindows nicht)
function Test-IstWindows { return ($env:OS -eq 'Windows_NT') }

# Quelltextdatei aus src als Text (UTF-8), z. B. Get-SrcText 'Oberflaeche/DiagGui.cs'
function Get-SrcText([string]$Pfad) {
    return [IO.File]::ReadAllText((Join-Path $global:MinibenchSrcRoot $Pfad), [Text.Encoding]::UTF8)
}

# Datei relativ zum Projektordner als Text (UTF-8), z. B. Get-RepoText 'Bauen.cmd'
function Get-RepoText([string]$Pfad) {
    return [IO.File]::ReadAllText((Join-Path $global:MinibenchRepoRoot $Pfad), [Text.Encoding]::UTF8)
}

# Version laut src/Kern/Version.ps1
function Get-MinibenchVersion { return (Get-MinibenchBuild).Version }

# ---------- Oberfläche: einmal übersetzen, Selbsttest im eigenen Prozess ----------
# Die Oberfläche wird je Testsitzung genau einmal übersetzt, zusammen mit tests/Daten/Oberflaeche/GuiSelbsttest.cs.
# Windows: Add-Type in einem Kindprozess (powershell.exe, .NET Framework, C# 5) mit -OutputAssembly, sonst mcs -langversion:5.
# Das Ergebnis ist eine eigene exe, die den Selbsttest ausführt; in dieser Sitzung werden keine Typen geladen.

# Dateien der Oberfläche in der Reihenfolge von Oberflaeche.ps1 (DiagGui.cs mit den using-Zeilen zuerst)
function Get-GuiQuellen {
    $ps = Get-SrcText 'Oberflaeche/Oberflaeche.ps1'
    $names = @([regex]::Matches($ps, '#>> EINBINDEN Oberflaeche\\(\S+\.cs)') | ForEach-Object { $_.Groups[1].Value })
    return @($names | ForEach-Object { Join-Path (Join-Path $global:MinibenchSrcRoot 'Oberflaeche') $_ })
}

function Get-GuiUebersetzung {
    if ($global:MinibenchGuiUebersetzung) { return $global:MinibenchGuiUebersetzung }
    # Reste abgebrochener Testläufe (älter als eine Stunde) entfernen
    Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'MinibenchGui_*' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('MinibenchGui_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $cs = Join-Path $dir 'Oberflaeche.cs'
    $exe = Join-Path $dir 'GuiSelbsttest.exe'
    $teile = @(Get-GuiQuellen | ForEach-Object { [IO.File]::ReadAllText($_, [Text.Encoding]::UTF8) })
    $teile += [IO.File]::ReadAllText((Join-Path $global:MinibenchTestData 'Oberflaeche/GuiSelbsttest.cs'), [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($cs, ($teile -join "`r`n"), (New-Object Text.UTF8Encoding($true)))
    $res = [pscustomobject]@{ Ok = $false; Meldung = ''; Exe = $exe; Ordner = $dir; Compiler = '' }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    if (Test-IstWindows) {
        $res.Compiler = 'Add-Type (.NET Framework, Kindprozess)'
        $code = 'Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Web.Extensions; ' +
            '$refs = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location); ' +
            ('$src = [IO.File]::ReadAllText(''{0}'', [Text.Encoding]::UTF8); ' -f $cs.Replace("'", "''")) +
            ('try {{ Add-Type -TypeDefinition $src -ReferencedAssemblies $refs -OutputAssembly ''{0}'' -OutputType ConsoleApplication -IgnoreWarnings -ErrorAction Stop; exit 0 }} catch {{ Write-Output $_.Exception.Message; exit 1 }}' -f $exe.Replace("'", "''"))
        $msg = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $code
        $res.Ok = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $exe)); $res.Meldung = (@($msg) -join ' ')
    } elseif (Get-Command mcs -ErrorAction SilentlyContinue) {
        $res.Compiler = 'mcs -langversion:5'
        $msg = & mcs -langversion:5 -target:exe -nowarn:414,169,649,0219,1635 -r:System.Windows.Forms.dll -r:System.Drawing.dll -r:System.Web.Extensions.dll ('-out:' + $exe) $cs 2>&1
        $res.Ok = ($LASTEXITCODE -eq 0); $res.Meldung = (@($msg | Where-Object { "$_" -match 'error' }) -join ' ')
    } else {
        $res.Meldung = 'kein C#-Compiler verfügbar'
    }
    Write-Host ('    Oberfläche übersetzt in {0:N1} s ({1}): {2}' -f $sw.Elapsed.TotalSeconds, $res.Compiler, $(if ($res.Ok) { 'fehlerfrei' } else { 'FEHLER' }))
    $global:MinibenchGuiUebersetzung = $res
    return $res
}

# Selbsttest einmal ausführen. Rückgabe: Name -> 'OK' oder Fehlertext; $null, wenn er hier nicht laufen kann.
function Get-GuiSelbsttest {
    if ($global:MinibenchGuiSelbsttest) { return $global:MinibenchGuiSelbsttest }
    $u = Get-GuiUebersetzung
    if (-not $u.Ok) { return $null }
    if (-not (Test-IstWindows) -and -not $env:DISPLAY) { return $null }
    $out = $(if (Test-IstWindows) { & $u.Exe $global:MinibenchRepoRoot 2>&1 } else { & mono $u.Exe $global:MinibenchRepoRoot 2>&1 })
    $map = [ordered]@{}
    foreach ($l in @($out)) {
        $p = ([string]$l) -split '\|', 3
        if ($p.Count -ge 2 -and $p[0] -eq 'OK') { $map[$p[1]] = 'OK' }
        elseif ($p.Count -ge 2 -and $p[0] -eq 'FEHL') { $map[$p[1]] = $(if ($p.Count -eq 3) { $p[2] } else { 'Fehler' }) }
    }
    $global:MinibenchGuiSelbsttest = $map
    return $map
}

# Prüft einen Fall des Selbsttests (im It-Block aufrufen)
function Assert-GuiSelbsttest([string]$Name) {
    $u = Get-GuiUebersetzung
    if (-not $u.Ok) { throw ('Oberfläche nicht übersetzbar: ' + $u.Meldung) }
    $m = Get-GuiSelbsttest
    if ($null -eq $m) { Set-ItResult -Skipped -Because 'Selbsttest braucht Windows oder eine Anzeige (DISPLAY)'; return }
    $m.Contains($Name) | Should -BeTrue -Because ('Selbsttest kennt den Fall ' + $Name)
    $m[$Name] | Should -Be 'OK' -Because $Name
}
