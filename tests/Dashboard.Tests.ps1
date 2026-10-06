# Tests für das Benchmark- & Diagnose-Dashboard (v3.3)

BeforeAll {
    . (Join-Path $PSScriptRoot 'Hilfen.ps1')
    . (Join-Path $global:MinibenchSrcRoot 'Bericht/Bausteine_Dashboard.ps1')
    $global:V33Src = $global:MinibenchSrcRoot
    $global:V33Gui = [IO.File]::ReadAllText((Join-Path $global:V33Src 'Oberflaeche/DiagGui_Vergleich.cs'), [System.Text.Encoding]::UTF8)
    $global:V33Start = [IO.File]::ReadAllText((Join-Path $global:V33Src 'Ablauf/Start.ps1'), [System.Text.Encoding]::UTF8)
    $global:V33Kopf = [IO.File]::ReadAllText((Join-Path $global:V33Src '00_Kopf.ps1'), [System.Text.Encoding]::UTF8)
    $global:V33Bauplan = [IO.File]::ReadAllText((Join-Path $global:V33Src 'Bauplan.txt'), [System.Text.Encoding]::UTF8)
}

Describe 'Dashboard: Datenintegration & Export-BenchDashboardData' {
    It 'Export-BenchDashboardData aggregiert Referenzen und Systemdaten' {
        $data = Export-BenchDashboardData -IncludeReferences
        $data | Should -Not -BeNullOrEmpty
        $data.Version | Should -Be '3.3'
        $data.References | Should -Not -BeNullOrEmpty
        $data.References.Count | Should -BeGreaterOrEqual 5
    }

    It 'Referenzen enthalten die 5 standardmäßigen Systemprofile' {
        $data = Export-BenchDashboardData -IncludeReferences
        $refNames = @($data.References | ForEach-Object { $_.DisplayName })
        @($refNames | Where-Object { $_ -like '*Desktop High-End*' }).Count | Should -BeGreaterThan 0
        @($refNames | Where-Object { $_ -like '*Desktop Mittelklasse*' }).Count | Should -BeGreaterThan 0
        @($refNames | Where-Object { $_ -like '*Mini*PC*' }).Count | Should -BeGreaterThan 0
        @($refNames | Where-Object { $_ -like '*Notebook Standard*' }).Count | Should -BeGreaterThan 0
        @($refNames | Where-Object { $_ -like '*Workstation Mobil*' }).Count | Should -BeGreaterThan 0
    }

    It 'Systemdaten enthalten alle geforderten Metadaten und Hardware-Felder' {
        $data = Export-BenchDashboardData -IncludeReferences
        $first = $data.References[0]
        $first.Id | Should -Not -BeNullOrEmpty
        $first.Computer | Should -Not -BeNullOrEmpty
        $first.DisplayName | Should -Not -BeNullOrEmpty
        $first.IsReference | Should -BeTrue
        $first.Hardware | Should -Not -BeNullOrEmpty
        $first.Hardware.CPU | Should -Not -BeNullOrEmpty
        $first.Hardware.RAM | Should -Not -BeNullOrEmpty
    }

    It 'Reale Benchmark-Keys (CPU, RAM, GPU, Disks) sind vorhanden und konsistent' {
        $data = Export-BenchDashboardData -IncludeReferences
        $highEnd = @($data.References | Where-Object { $_.DisplayName -like '*High-End*' })[0]
        $m = $highEnd.Metrics
        $m | Should -Not -BeNullOrEmpty
        $m.CPU_ST | Should -BeGreaterThan 0
        $m.CPU_MT | Should -BeGreaterThan 0
        $m.RAM_Lesen | Should -BeGreaterThan 0
        $m.RAM_Kopieren | Should -BeGreaterThan 0
        $m.RAM_Latenz | Should -BeGreaterThan 0
        $m.GPU_REND | Should -BeGreaterThan 0
        $m.GPU_REND1 | Should -BeGreaterThan 0
        $m.FastestDisk | Should -Not -BeNullOrEmpty
        $m.FastestDisk.SR | Should -BeGreaterThan 0
    }

    It 'Scores (Overall, Gaming, Desktop, Workstation) werden berechnet' {
        $data = Export-BenchDashboardData -IncludeReferences
        $ref = $data.References[0]
        $ref.Scores | Should -Not -BeNullOrEmpty
        $ref.Scores.Overall | Should -BeGreaterThan 0
        $ref.Scores.Gaming | Should -BeGreaterThan 0
        $ref.Scores.Desktop | Should -BeGreaterThan 0
        $ref.Scores.Workstation | Should -BeGreaterThan 0
    }

    It 'Lasttest-Telemetrie und Zeitreihenpunkte sind extrahiert' {
        $data = Export-BenchDashboardData -IncludeReferences
        $ref = $data.References[0]
        $t = $ref.Telemetry
        $t | Should -Not -BeNullOrEmpty
        $t.Drosselung | Should -Not -BeNullOrEmpty
        $t.Series | Should -Not -BeNullOrEmpty
        $t.Series.Count | Should -BeGreaterThan 5
        $t.Series[0].T | Should -Be 0
    }

    It 'Export-BenchDashboardData unterstützt -AsJson und -OutputPath' {
        $tmpJson = Join-Path ([IO.Path]::GetTempPath()) ('mb_dash_' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            $jsonStr = Export-BenchDashboardData -IncludeReferences -AsJson -OutputPath $tmpJson
            $jsonStr | Should -Match '"Version":\s*"3\.3"'
            Test-Path -LiteralPath $tmpJson | Should -BeTrue
            $readBack = [IO.File]::ReadAllText($tmpJson, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $readBack.Version | Should -Be '3.3'
        } finally {
            Remove-Item -LiteralPath $tmpJson -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Dashboard: HTML-Generierung, Theming & 100 % Offline-Fähigkeit' {
    It 'New-BenchDashboardHtml generiert vollständige, valide HTML5-Datei' {
        $tmpHtml = Join-Path ([IO.Path]::GetTempPath()) ('mb_dash_' + [guid]::NewGuid().ToString('N') + '.html')
        try {
            $res = New-BenchDashboardHtml -OutputPath $tmpHtml
            Test-Path -LiteralPath $tmpHtml | Should -BeTrue
            $content = [IO.File]::ReadAllText($tmpHtml, [Text.Encoding]::UTF8)
            $content | Should -Match '<!DOCTYPE html>'
            $content | Should -Match '<html lang="de"'
            $content | Should -Match 'Leos Minibench'
            $content | Should -Match 'window\.MINIBENCH_DASHBOARD_DATA = \{'
            $content | Should -Match '<canvas id="telemetryCanvas">'
        } finally {
            Remove-Item -LiteralPath $tmpHtml -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Dashboard enthält keine externen CDN-Abhängigkeiten (100 % offline)' {
        $tmpHtml = Join-Path ([IO.Path]::GetTempPath()) ('mb_dash_cdn_' + [guid]::NewGuid().ToString('N') + '.html')
        try {
            New-BenchDashboardHtml -OutputPath $tmpHtml
            $content = [IO.File]::ReadAllText($tmpHtml, [Text.Encoding]::UTF8)
            $content | Should -Not -Match 'https?://[^"\''\s]*cdn'
            $content | Should -Not -Match 'https?://fonts\.googleapis\.com'
            $content | Should -Not -Match 'https?://cdn\.jsdelivr\.net'
            $content | Should -Not -Match 'https?://cdnjs\.cloudflare\.com'
        } finally {
            Remove-Item -LiteralPath $tmpHtml -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Dashboard enthält Fluent 2-Designelemente, ToggleSwitch und Dark-Mode Theming' {
        $tmpHtml = Join-Path ([IO.Path]::GetTempPath()) ('mb_dash_theme_' + [guid]::NewGuid().ToString('N') + '.html')
        try {
            New-BenchDashboardHtml -OutputPath $tmpHtml
            $content = [IO.File]::ReadAllText($tmpHtml, [Text.Encoding]::UTF8)
            $content | Should -Match 'data-theme="dark"'
            $content | Should -Match '--accent:\s*#0067C0'
            $content | Should -Match '--bg:\s*#F9F9FB'
            $content | Should -Match '--bg:\s*#202020'
            $content | Should -Match 'localStorage\.setItem\(''minibench_theme'''
            $content | Should -Match 'class="toggle-switch"'
        } finally {
            Remove-Item -LiteralPath $tmpHtml -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Dashboard: Integration in Bauplan, Ablauf und Oberfläche' {
    It 'Bausteine_Dashboard.ps1 ist im Bauplan eingebunden' {
        $global:V33Bauplan | Should -Match 'Bericht\\Bausteine_Dashboard\.ps1'
    }

    It '00_Kopf.ps1 deklariert die Parameter Dashboard und DashboardExport' {
        $global:V33Kopf | Should -Match '\[switch\]\$Dashboard'
        $global:V33Kopf | Should -Match '\[string\]\$DashboardExport'
    }

    It 'Ablauf/Start.ps1 führt Dashboard-Erstellung aus' {
        $global:V33Start | Should -Match 'Export-BenchDashboardHtml'
    }

    It 'DiagGui_Vergleich.cs enthält Schaltfläche Dashboard und Methode OpenDashboard' {
        $global:V33Gui | Should -Match 'UI\.Secondary\("Dashboard"\)'
        $global:V33Gui | Should -Match 'void OpenDashboard\(\)'
        $global:V33Gui | Should -Match 'Tip\(btnDashboard,'
    }
}
