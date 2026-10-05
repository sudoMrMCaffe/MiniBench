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
