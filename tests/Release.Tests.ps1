# Release-Metadaten: Die Version in src/Kern/Version.ps1 steht überall oben (Versionen.cs, Doku/Versionshistorie.txt,
# CHANGELOG.md), zu jeder Version gibt es eine Änderungsdatei, und Bauen.cmd committet ohne fest eingetragene Versionen.
# Ersetzt die früheren Versionsprüfungen je Release (VersionXX.Tests.ps1).

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    $script:Ver = Get-MinibenchVersion
    $script:VersionenCs = Get-SrcText 'Oberflaeche/Versionen.cs'
    $script:Historie = Get-RepoText 'Doku/Versionshistorie.txt'
    $script:Changelog = Get-RepoText 'CHANGELOG.md'
    $script:Bauen = Get-RepoText 'Bauen.cmd'
    $script:Eintraege = @([regex]::Matches($script:VersionenCs, 'new Eintrag\("([^"]+)", "([^"]*)", "([^"]+)"') | ForEach-Object {
            [pscustomobject]@{ Version = $_.Groups[1].Value; Datum = $_.Groups[2].Value; Titel = $_.Groups[3].Value } })
}

Describe 'Aktuelle Version überall gleich' {
    It 'Version.ps1 nennt eine gültige Versionsnummer' {
        $script:Ver | Should -Match '^\d+\.\d+$'
        Get-SrcText 'Kern/Version.ps1' | Should -Match ('\$ScriptVersion\s*=\s*''' + [regex]::Escape($script:Ver) + '''')
    }
    It 'Versionen.cs führt die aktuelle Version als ersten Eintrag, mit Datum und Titel' {
        $script:Eintraege[0].Version | Should -Be $script:Ver
        $script:Eintraege[0].Datum | Should -Match '^\d{2}\.\d{2}\.\d{4}$'
        $script:Eintraege[0].Titel.Length | Should -BeGreaterThan 10
    }
    It 'Doku/Versionshistorie.txt führt die aktuelle Version als ersten Eintrag' {
        [regex]::Match($script:Historie, '(?m)^VERSION\s+([0-9.]+)\s+\(').Groups[1].Value | Should -Be $script:Ver
    }
    It 'CHANGELOG.md führt die aktuelle Version als ersten Eintrag' {
        [regex]::Match($script:Changelog, '(?m)^##\s+v([0-9.]+)\s+\(').Groups[1].Value | Should -Be $script:Ver
    }
    It 'Doku/Änderungen_v<Version>.txt existiert als UTF-8 mit BOM' {
        $p = Join-Path $global:MinibenchRepoRoot (('Doku/' + [char]0x00C4 + 'nderungen_v{0}.txt') -f $script:Ver)
        Test-Path -LiteralPath $p | Should -BeTrue
        $b = [IO.File]::ReadAllBytes($p)
        $b.Length | Should -BeGreaterThan 100
        ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) | Should -BeTrue
    }
}

Describe 'Versionshistorie vollständig' {
    It 'jede Version mit Änderungsdatei hat einen Eintrag in Versionen.cs' {
        $vs = @($script:Eintraege | ForEach-Object { $_.Version })
        foreach ($f in @(Get-ChildItem (Join-Path $global:MinibenchRepoRoot 'Doku') -Filter '*nderungen_v*.txt')) {
            $vs | Should -Contain ($f.BaseName -replace '^.nderungen_v', '') -Because $f.Name
        }
    }
    It 'reicht als Einzelversionen bis 1.0 zurück' {
        $vs = @($script:Eintraege | ForEach-Object { $_.Version })
        foreach ($n in 0..8) { $vs | Should -Contain ('1.{0}' -f $n) }
        $vs | Should -Not -Contain '1.0 bis 1.8'
    }
    It 'Doku/Versionshistorie.txt und CHANGELOG.md enthalten jede Version aus Versionen.cs genau einmal' {
        foreach ($e in $script:Eintraege) {
            ([regex]::Matches($script:Historie, ('(?m)^VERSION {0}\s' -f [regex]::Escape($e.Version)))).Count | Should -Be 1 -Because ('Versionshistorie.txt, ' + $e.Version)
            if ($e.Version -match '^\d+\.\d+$') {
                ([regex]::Matches($script:Changelog, ('(?m)^## v{0}\s' -f [regex]::Escape($e.Version)))).Count | Should -Be 1 -Because ('CHANGELOG.md, ' + $e.Version)
            }
        }
    }
    It 'Einträge stehen absteigend nach Version' {
        $zahlen = @($script:Eintraege | Where-Object { $_.Version -match '^\d+\.\d+$' } | ForEach-Object { [double]::Parse($_.Version, [Globalization.CultureInfo]::InvariantCulture) })
        for ($i = 1; $i -lt $zahlen.Count; $i++) { $zahlen[$i] | Should -BeLessThan $zahlen[$i - 1] }
    }
}

Describe 'Bauen.cmd und Git' {
    It 'nennt keine Versionsnummer fest (Commit-Nachricht kommt aus Versionen.cs)' {
        $script:Bauen | Should -Not -Match '\$ver -eq ''\d'
        $script:Bauen | Should -Match 'new Eintrag\\\("\{0\}"'
        $script:Bauen | Should -Match "'Release v\{0\}: \{1\}'"
    }
    It 'committet nur nach bestandenen Tests und prüft das Ergebnis von git commit' {
        $script:Bauen | Should -Match '\$testsOk = \$false'
        $script:Bauen | Should -Match 'else \{ \$testsOk = \$true;'
        $script:Bauen | Should -Match '-and -not \$testsOk\)'
        $script:Bauen | Should -Match '(?s)git\.exe -C \$Here commit -m \$commitMsg 2>&1\s+if \(\$LASTEXITCODE -eq 0\)'
    }
    It 'beginnt ohne BOM (cmd.exe liest die BOM als Zeichen der ersten Zeile)' {
        $b = [IO.File]::ReadAllBytes((Join-Path $global:MinibenchRepoRoot 'Bauen.cmd'))
        ($b[0] -eq 0xEF -and $b[1] -eq 0xBB) | Should -BeFalse
        [char]$b[0] | Should -Be '<'
    }
}
