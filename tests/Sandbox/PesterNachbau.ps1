# Nachbau der Pester-5-Befehle für die Sandbox ohne Zugriff auf die PowerShell Gallery (PowerShell 7 unter Linux).
# Nur für Claude-Sitzungen; unter Windows laufen die Tests mit echtem Pester über Testen.cmd.
# Aufruf: pwsh -NoProfile -File tests/Sandbox_Testen.ps1 [-Files Datei1.Tests.ps1,Datei2.Tests.ps1]
# Stand 03.10.2026 (v2.7): ergibt mit 2.67 dieselben Zahlen wie in Änderungen_v2.67 (519 bestanden, 4 übersprungen).

$global:__PS = [pscustomobject]@{ Passed = 0; Failed = 0; Skipped = 0; Fails = New-Object System.Collections.ArrayList; Stack = New-Object System.Collections.ArrayList; Calls = New-Object System.Collections.ArrayList; Mocks = @{}; ItStart = 0; Path = New-Object System.Collections.ArrayList; Quiet = $true }

function global:New-ShimFrame([string]$Name) {
    [pscustomobject]@{ Name = $Name; BeforeAll = New-Object System.Collections.ArrayList; AfterAll = New-Object System.Collections.ArrayList; BeforeEach = New-Object System.Collections.ArrayList; AfterEach = New-Object System.Collections.ArrayList; Items = New-Object System.Collections.ArrayList; MockIds = New-Object System.Collections.ArrayList }
}

function global:Expand-ShimName([string]$Name, $Data) {
    if ($Data -is [System.Collections.IDictionary]) { foreach ($k in $Data.Keys) { $Name = $Name.Replace('<' + $k + '>', [string]$Data[$k]) } }
    return $Name
}

function global:BeforeDiscovery([scriptblock]$Block) { . $Block }
function global:BeforeAll([scriptblock]$Block) { [void]$global:__PS.Stack[-1].BeforeAll.Add($Block) }
function global:AfterAll([scriptblock]$Block) { [void]$global:__PS.Stack[-1].AfterAll.Add($Block) }
function global:BeforeEach([scriptblock]$Block) { [void]$global:__PS.Stack[-1].BeforeEach.Add($Block) }
function global:AfterEach([scriptblock]$Block) { [void]$global:__PS.Stack[-1].AfterEach.Add($Block) }

function global:Describe {
    param([Parameter(Position = 0)][string]$Name, [Parameter(Position = 1)][scriptblock]$Fixture, $ForEach = $null, [switch]$Skip, [string[]]$Tag)
    $cases = New-Object System.Collections.ArrayList
    if ($PSBoundParameters.ContainsKey('ForEach')) { foreach ($c in @($ForEach)) { [void]$cases.Add($c) } } else { [void]$cases.Add($null) }
    foreach ($c in $cases) { [void]$global:__PS.Stack[-1].Items.Add([pscustomobject]@{ Kind = 'Block'; Name = (Expand-ShimName $Name $c); Body = $Fixture; Data = $c; Skip = [bool]$Skip }) }
}
Set-Alias -Name Context -Value Describe -Scope Global

function global:It {
    param([Parameter(Position = 0)][string]$Name, [Parameter(Position = 1)][scriptblock]$Test, $ForEach = $null, $TestCases = $null, [switch]$Skip, [string[]]$Tag)
    if ($PSBoundParameters.ContainsKey('TestCases')) { $ForEach = $TestCases }
    $cases = New-Object System.Collections.ArrayList
    if ($null -ne $ForEach) { foreach ($c in @($ForEach)) { [void]$cases.Add($c) } } else { [void]$cases.Add($null) }
    foreach ($c in $cases) { [void]$global:__PS.Stack[-1].Items.Add([pscustomobject]@{ Kind = 'It'; Name = (Expand-ShimName $Name $c); Body = $Test; Data = $c; Skip = [bool]$Skip }) }
}

function global:Set-ItResult { param([switch]$Skipped, [switch]$Inconclusive, [switch]$Pending, [string]$Because) throw ([System.Exception]::new('__SHIM_SKIP__ ' + $Because)) }

# Daten eines -ForEach-Falls als Variablen setzen und Block im aktuellen Bereich ausführen
function global:Invoke-ShimWithData($Data, [scriptblock]$Block) {
    if ($Data -is [System.Collections.IDictionary]) { foreach ($k in $Data.Keys) { Set-Variable -Name $k -Value $Data[$k] } }
    $_ = $Data
    . $Block
}

function global:Invoke-ShimFrame($Item, [object[]]$Inherited) {
    $frame = New-ShimFrame $Item.Name
    [void]$global:__PS.Path.Add($Item.Name)
    [void]$global:__PS.Stack.Add($frame)
    try {
        # Rumpf ausführen (Entdeckung: registriert BeforeAll, It, Describe ...)
        if ($Item.Data -is [System.Collections.IDictionary]) { foreach ($k in $Item.Data.Keys) { Set-Variable -Name $k -Value $Item.Data[$k] } }
        try { . $Item.Body } catch { Add-ShimFail ('Entdeckung: ' + $_.Exception.Message); return }
        if ($Item.Skip) { Skip-ShimAll $frame; return }
        $setupOk = $true
        foreach ($b in $frame.BeforeAll) { try { . $b } catch { $setupOk = $false; Add-ShimFail ('BeforeAll: ' + $_.Exception.Message + ' @ ' + $_.InvocationInfo.PositionMessage) } }
        $eachB = @($Inherited[0]) + @($frame.BeforeEach) | Where-Object { $_ }
        $eachA = @($frame.AfterEach) + @($Inherited[1]) | Where-Object { $_ }
        foreach ($it in $frame.Items) {
            if ($it.Kind -eq 'Block') { Invoke-ShimFrame $it @(, @($eachB), @($eachA)); continue }
            if ($it.Skip -or -not $setupOk) { if ($setupOk) { $global:__PS.Skipped++ } else { Add-ShimFail ('(BeforeAll fehlgeschlagen) ' + $it.Name) }; continue }
            $global:__PS.ItStart = $global:__PS.Calls.Count
            $mockMark = $global:__PS.Stack.Count
            [void]$global:__PS.Stack.Add((New-ShimFrame ('It:' + $it.Name)))
            $res = & {
                param($__it, $__eb, $__ea)
                try {
                    if ($__it.Data -is [System.Collections.IDictionary]) { foreach ($__k in $__it.Data.Keys) { Set-Variable -Name $__k -Value $__it.Data[$__k] } }
                    $_ = $__it.Data
                    foreach ($__b in $__eb) { . $__b }
                    try { $null = & { . $__it.Body } } finally { foreach ($__a in $__ea) { try { . $__a } catch { } } }
                    'ok'
                } catch {
                    if ($_.Exception.Message -like '__SHIM_SKIP__*') { 'skip' } else { 'fail|' + $_.Exception.Message + ' @ ' + ($_.InvocationInfo.PositionMessage -split "`n")[0] }
                }
            } $it $eachB $eachA
            $res = @($res)[-1]
            Remove-ShimMocks $global:__PS.Stack[-1]
            $global:__PS.Stack.RemoveAt($global:__PS.Stack.Count - 1)
            if ($res -eq 'ok') { $global:__PS.Passed++ }
            elseif ($res -eq 'skip') { $global:__PS.Skipped++ }
            else { $global:__PS.Path.Add($it.Name) | Out-Null; Add-ShimFail ([string]$res).Substring(5); $global:__PS.Path.RemoveAt($global:__PS.Path.Count - 1) }
        }
        foreach ($b in $frame.AfterAll) { try { . $b } catch { Add-ShimFail ('AfterAll: ' + $_.Exception.Message) } }
    } finally {
        Remove-ShimMocks $frame
        $global:__PS.Stack.RemoveAt($global:__PS.Stack.Count - 1)
        $global:__PS.Path.RemoveAt($global:__PS.Path.Count - 1)
    }
}

function global:Skip-ShimAll($Frame) {
    foreach ($it in $Frame.Items) { if ($it.Kind -eq 'It') { $global:__PS.Skipped++ } }
    foreach ($it in $Frame.Items) {
        if ($it.Kind -ne 'Block') { continue }
        $f = New-ShimFrame $it.Name; [void]$global:__PS.Stack.Add($f)
        try { if ($it.Data -is [System.Collections.IDictionary]) { foreach ($k in $it.Data.Keys) { Set-Variable -Name $k -Value $it.Data[$k] } }; . $it.Body } catch { }
        $global:__PS.Stack.RemoveAt($global:__PS.Stack.Count - 1)
        Skip-ShimAll $f
    }
}

function global:Add-ShimFail([string]$Msg) {
    $global:__PS.Failed++
    [void]$global:__PS.Fails.Add((($global:__PS.Path -join ' > ') + "`n      " + $Msg))
}

# ---------- Mock ----------
function global:Mock {
    param([string]$ModuleName, [Parameter(Position = 0)][string]$CommandName, [Parameter(Position = 1)][scriptblock]$MockWith = {}, [scriptblock]$ParameterFilter = { $true }, [switch]$Verifiable, [string[]]$RemoveParameterType)
    $mod = $(if ($ModuleName) { Get-Module $ModuleName } else { $null })
    $old = $null
    $key = ($ModuleName + '|' + $CommandName)
    # Modul neu geladen (Import-MinibenchTestModule in einer späteren Testdatei): die Attrappe fehlt dort, neu anlegen
    if ($global:__PS.Mocks.ContainsKey($key) -and $mod) {
        $cur = & $mod { param($n) Get-Command -Name $n -ErrorAction SilentlyContinue | Select-Object -First 1 } $CommandName
        if (-not $cur -or -not ($cur.CommandType -eq 'Function' -and [string]$cur.Definition -match '__ShimDispatch')) {
            $old = $global:__PS.Mocks[$key]
            $global:__PS.Mocks.Remove($key)
        }
    }
    if (-not $global:__PS.Mocks.ContainsKey($key)) {
        $orig = $(if ($mod) { & $mod { param($n) Get-Command -Name $n -ErrorAction SilentlyContinue | Select-Object -First 1 } $CommandName } else { Get-Command -Name $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1 })
        $paramBlock = ''; $binding = '[CmdletBinding()]'
        if ($orig -and $orig.CommandType -in 'Function', 'Cmdlet', 'Filter') {
            try { $md = [System.Management.Automation.CommandMetadata]::new($orig); $paramBlock = [System.Management.Automation.ProxyCommand]::GetParamBlock($md); $binding = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($md) } catch { $paramBlock = '' }
            if (-not $orig.CmdletBinding -and $orig.CommandType -eq 'Function') { $binding = '' }
        }
        $origSb = $(if ($orig -and $orig.CommandType -eq 'Function') { $orig.ScriptBlock } else { $null })
        $entry = [pscustomobject]@{ Key = $key; Name = $CommandName; Module = $ModuleName; Orig = $orig; OrigSb = $origSb; List = New-Object System.Collections.ArrayList }
        if ($old) { foreach ($x in $old.List) { [void]$entry.List.Add($x) } }
        $global:__PS.Mocks[$key] = $entry
        if ($binding) {
            $code = "function script:$CommandName { $binding param($paramBlock) & `$global:__ShimDispatch '$key' `$PSBoundParameters @() }"
        } else {
            $code = "function script:$CommandName { param($paramBlock) & `$global:__ShimDispatch '$key' `$PSBoundParameters `$args }"
        }
        if ($mod) { & $mod ([scriptblock]::Create($code)) } else { . ([scriptblock]::Create($code.Replace('function script:', 'function global:'))) }
    }
    $id = [guid]::NewGuid().ToString()
    [void]$global:__PS.Mocks[$key].List.Add([pscustomobject]@{ Id = $id; Body = $MockWith; Filter = $ParameterFilter })
    [void]$global:__PS.Stack[-1].MockIds.Add(@($key, $id))
}

function global:Remove-ShimMocks($Frame) {
    foreach ($m in $Frame.MockIds) {
        $e = $global:__PS.Mocks[$m[0]]
        if (-not $e) { continue }
        for ($i = $e.List.Count - 1; $i -ge 0; $i--) { if ($e.List[$i].Id -eq $m[1]) { $e.List.RemoveAt($i) } }
    }
}

function global:Test-ShimFilter($Params, [scriptblock]$Filter) {
    $r = & { param($__p, $__f) foreach ($__k in $__p.Keys) { Set-Variable -Name $__k -Value $__p[$__k] }; & $__f } $Params $Filter
    return [bool](@($r)[-1])
}

$global:__ShimDispatch = {
    param($Key, $Bound, $Rest)
    $e = $global:__PS.Mocks[$Key]
    $p = @{}; foreach ($k in $Bound.Keys) { $p[$k] = $Bound[$k] }
    [void]$global:__PS.Calls.Add([pscustomobject]@{ Key = $Key; Params = $p })
    for ($i = $e.List.Count - 1; $i -ge 0; $i--) {
        $m = $e.List[$i]
        if (Test-ShimFilter $p $m.Filter) {
            return (& { param($__p, $__b, $args) foreach ($__k in $__p.Keys) { Set-Variable -Name $__k -Value $__p[$__k] }; . $__b } $p $m.Body $Rest)
        }
    }
    if ($e.OrigSb) { return (& $e.OrigSb @p @Rest) }
    if ($e.Orig) { return (& $e.Orig @p @Rest) }
}

# ---------- Should ----------
function global:Should {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]$ActualValue,
        [Parameter(Position = 0)]$ExpectedValue,
        [switch]$Not, [switch]$Be, [switch]$BeExactly, [switch]$Match, [switch]$MatchExactly, [switch]$BeTrue, [switch]$BeFalse, [switch]$BeNullOrEmpty,
        [switch]$BeGreaterThan, [switch]$BeLessThan, [switch]$BeGreaterOrEqual, [switch]$BeLessOrEqual, [switch]$Exist, [switch]$Contain,
        [switch]$Throw, [switch]$Invoke, [switch]$BeLike, [switch]$BeOfType, [switch]$HaveCount,
        [string]$Because, [string]$ExpectedMessage, [string]$ModuleName, [int]$Times = 1, [switch]$Exactly, [scriptblock]$ParameterFilter = { $true }, [string]$Scope,
        [Parameter(Position = 1)]$Extra
    )
    begin { $items = New-Object System.Collections.ArrayList; $piped = $false }
    process { if ($PSCmdlet.MyInvocation.ExpectingInput) { $piped = $true; [void]$items.Add($ActualValue) } }
    end {
        $a = $(if ($piped) { if ($items.Count -eq 1) { $items[0] } elseif ($items.Count -eq 0) { $null } else { , $items.ToArray() } } else { $ActualValue })
        $fail = { param($m) throw ([System.Exception]::new($m + $(if ($Because) { ' (weil ' + $Because + ')' } else { '' }))) }
        $show = { param($v) if ($null -eq $v) { '$null' } elseif ($v -is [array]) { '@(' + (($v | ForEach-Object { [string]$_ }) -join ', ') + ')' } else { "'" + ([string]$v) + "'" } }
        if ($Invoke) {
            $name = [string]$ExpectedValue
            $key = $ModuleName + '|' + $name
            $calls = @(for ($i = $global:__PS.ItStart; $i -lt $global:__PS.Calls.Count; $i++) { $c = $global:__PS.Calls[$i]; if ($c.Key -eq $key -and (Test-ShimFilter $c.Params $ParameterFilter)) { $c } })
            $n = $calls.Count
            $ok = $(if ($Exactly -or $Times -eq 0) { $n -eq $Times } else { $n -ge $Times })
            if ($Not) { $ok = ($n -eq 0) }
            if (-not $ok) { & $fail ('{0} wurde {1}x aufgerufen, erwartet {2}{3}' -f $name, $n, $(if ($Exactly -or $Times -eq 0) { '' } else { 'mindestens ' }), $Times) }
            return
        }
        if ($Throw) {
            $threw = $false; $msg = ''
            try { & $a } catch { $threw = $true; $msg = $_.Exception.Message }
            $exp = $(if ($ExpectedMessage) { $ExpectedMessage } else { [string]$ExpectedValue })
            $ok = $threw -and (-not $exp -or $msg -like $exp)
            if ($Not) { if ($threw) { & $fail ('Erwartet keinen Fehler, aber: ' + $msg) }; return }
            if (-not $ok) { & $fail ('Erwartet Fehler {0}, erhalten: {1}' -f $exp, $(if ($threw) { $msg } else { 'kein Fehler' })) }
            return
        }
        $ok = $null; $desc = ''
        if ($Be -or $BeExactly) {
            $e = $ExpectedValue
            if ($a -is [array] -or $e -is [array]) {
                $aa = @($a); $ea = @($e)
                $ok = ($aa.Count -eq $ea.Count)
                if ($ok) { for ($i = 0; $i -lt $aa.Count; $i++) { if ($BeExactly) { if (-not ($aa[$i] -ceq $ea[$i])) { $ok = $false } } elseif (-not ($aa[$i] -eq $ea[$i])) { $ok = $false } } }
            } elseif ($null -eq $e) { $ok = ($null -eq $a) }
            elseif ($null -eq $a) { $ok = $false }
            elseif ($BeExactly) { $ok = ($e -ceq $a) } else { $ok = ($e -eq $a) }
            $desc = 'gleich ' + (& $show $e) + ', erhalten ' + (& $show $a)
        }
        elseif ($Match) { $ok = ([string]$a -match [string]$ExpectedValue); $desc = 'passend zu ' + $ExpectedValue + ', erhalten ' + (& $show $a) }
        elseif ($MatchExactly) { $ok = ([string]$a -cmatch [string]$ExpectedValue); $desc = 'passend zu ' + $ExpectedValue }
        elseif ($BeLike) { $ok = ([string]$a -like [string]$ExpectedValue); $desc = 'wie ' + $ExpectedValue + ', erhalten ' + (& $show $a) }
        elseif ($BeTrue) { $ok = [bool]$a; $desc = 'wahr, erhalten ' + (& $show $a) }
        elseif ($BeFalse) { $ok = -not [bool]$a; $desc = 'falsch, erhalten ' + (& $show $a) }
        elseif ($BeNullOrEmpty) { $ok = ($null -eq $a) -or ($a -is [string] -and $a -eq '') -or (($a -is [array] -or $a -is [System.Collections.ICollection]) -and @($a).Count -eq 0); $desc = 'leer, erhalten ' + (& $show $a) }
        elseif ($BeGreaterThan) { $ok = ($a -gt $ExpectedValue); $desc = 'größer als ' + $ExpectedValue + ', erhalten ' + (& $show $a) }
        elseif ($BeLessThan) { $ok = ($a -lt $ExpectedValue); $desc = 'kleiner als ' + $ExpectedValue + ', erhalten ' + (& $show $a) }
        elseif ($BeGreaterOrEqual) { $ok = ($a -ge $ExpectedValue); $desc = 'mindestens ' + $ExpectedValue + ', erhalten ' + (& $show $a) }
        elseif ($BeLessOrEqual) { $ok = ($a -le $ExpectedValue); $desc = 'höchstens ' + $ExpectedValue + ', erhalten ' + (& $show $a) }
        elseif ($Exist) { $ok = Test-Path -LiteralPath ([string]$a); $desc = 'vorhanden: ' + $a }
        elseif ($Contain) { $ok = (@($a) -contains $ExpectedValue); $desc = 'enthält ' + $ExpectedValue + ', erhalten ' + (& $show $a) }
        elseif ($HaveCount) { $ok = (@($a).Count -eq $ExpectedValue); $desc = 'Anzahl ' + $ExpectedValue + ', erhalten ' + @($a).Count }
        elseif ($BeOfType) { $ok = ($a -is $ExpectedValue); $desc = 'vom Typ ' + $ExpectedValue }
        else { throw 'Should: unbekannter Operator' }
        if ($Not) { $ok = -not $ok; $desc = 'NICHT ' + $desc }
        if (-not $ok) { & $fail ('Erwartet ' + $desc) }
    }
}

# ---------- Lauf ----------
function global:Invoke-ShimFile([string]$Path) {
    $root = New-ShimFrame ([IO.Path]::GetFileName($Path))
    $td = Join-Path ([IO.Path]::GetTempPath()) ('shimdrive_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $td -Force | Out-Null
    $global:TestDrive = $td
    $item = [pscustomobject]@{ Kind = 'Block'; Name = [IO.Path]::GetFileName($Path); Body = ([scriptblock]::Create(". '$Path'")); Data = $null; Skip = $false }
    Invoke-ShimFrame $item @(, @(), @())
    try { Remove-Item -LiteralPath $td -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
