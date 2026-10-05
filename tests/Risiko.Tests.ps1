# Risikostufen und Freigabe zerstörender Schritte
BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    Import-MinibenchTestModule -Parts 'Kern\Risiko.ps1'
}

Describe 'Rangfolge' {
    It 'ordnet Lesen < Ändern < Eingriff < Zerstörend' {
        MinibenchTest\Get-RiskRank 'Lesen' | Should -Be 0
        MinibenchTest\Get-RiskRank 'Aendern' | Should -Be 1
        MinibenchTest\Get-RiskRank 'Eingriff' | Should -Be 2
        MinibenchTest\Get-RiskRank 'Zerstoerend' | Should -Be 3
    }
    It 'lehnt unbekannte Stufen ab' { { MinibenchTest\Get-RiskRank 'Harmlos' } | Should -Throw '*Unbekannte Risikostufe*' }
    It 'höchste Stufe einer Auswahl' {
        MinibenchTest\Get-MaxRisk @('Lesen', 'Eingriff', 'Aendern') | Should -Be 'Eingriff'
        MinibenchTest\Get-MaxRisk @() | Should -Be 'Lesen'
        MinibenchTest\Get-MaxRisk @('', $null, 'Aendern') | Should -Be 'Aendern'
    }
    It 'zeigt Umlaute in der Anzeige' {
        MinibenchTest\Get-RiskLabel 'Aendern' | Should -Be 'Ändern'
        MinibenchTest\Get-RiskLabel 'Zerstoerend' | Should -Be 'Zerstörend'
    }
}

Describe 'Bestätigung per Seriennummer' {
    It 'akzeptiert die exakte Seriennummer' { MinibenchTest\Test-DestructiveConfirmation 'S4EWNX0R123456' 'S4EWNX0R123456' | Should -BeTrue }
    It 'ignoriert Leerzeichen, Bindestriche und Groß-/Kleinschreibung' { MinibenchTest\Test-DestructiveConfirmation 'WD-WX12A3456789' 'wdwx12a3456789 ' | Should -BeTrue }
    It 'lehnt Teile der Seriennummer ab' { MinibenchTest\Test-DestructiveConfirmation 'S4EWNX0R123456' '123456' | Should -BeFalse }
    It 'lehnt leere Eingaben ab' { MinibenchTest\Test-DestructiveConfirmation 'S4EWNX0R123456' '' | Should -BeFalse }
    It 'lehnt Platzhalter-Seriennummern grundsätzlich ab' -ForEach @(@{ S = 'Default string' }, @{ S = '0000000000' }, @{ S = 'To Be Filled By O.E.M.' }, @{ S = '' }) {
        MinibenchTest\Test-DestructiveConfirmation $S $S | Should -BeFalse
    }
}

Describe 'Sperren vor einem Schritt' {
    It 'Lesen, Ändern und Eingriff laufen ohne Seriennummer' {
        foreach ($l in 'Lesen', 'Aendern', 'Eingriff') { MinibenchTest\Get-RiskBlocker -Level $l | Should -BeNullOrEmpty }
    }
    It 'Zerstörend braucht die passende Seriennummer' {
        MinibenchTest\Get-RiskBlocker -Level 'Zerstoerend' -ExpectedSerial 'ABC12345' -GivenSerial 'ABC12346' | Should -Match 'passt nicht'
        MinibenchTest\Get-RiskBlocker -Level 'Zerstoerend' -ExpectedSerial 'ABC12345' -GivenSerial 'abc-12345' | Should -BeNullOrEmpty
    }
    It 'Zerstörend auf dem Systemlaufwerk ist immer gesperrt' {
        MinibenchTest\Get-RiskBlocker -Level 'Zerstoerend' -ExpectedSerial 'ABC12345' -GivenSerial 'ABC12345' -SystemDisk $true | Should -Match 'Systemlaufwerk'
    }
}
