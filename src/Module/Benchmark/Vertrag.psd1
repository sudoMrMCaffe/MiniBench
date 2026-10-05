# Modulvertrag Benchmark (Vertrag 1). Felder sind in src\Kern\Modulvertrag.ps1 beschrieben.
@{
    Vertrag         = 1
    Name            = 'Benchmark'
    Seite           = @{ Titel = 'Benchmark'; Kurz = 'Wählbare Messungen mit Vergleich' }
    Admin           = $true
    Risiko          = 'Aendern'
    Neustart        = 'nie'
    Parameter       = @('BenchTests', 'BenchLaufwerke', 'BenchmarkKurz', 'ReferenzSpeichern', 'ReferenzDatei', 'VergleichDateien', 'KeineDatenbank', 'BenchGpuWahl')
    Datenbankfelder = @('Werte', 'Messwerte', 'Messdauer', 'Laufwerke', 'Rendertest')
    Schritte        = @(
        @{ Key = 'CPU';    Typ = 'Messung'; Titel = 'Prozessor';             Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        @{ Key = 'RAM';    Typ = 'Messung'; Titel = 'Arbeitsspeicher';       Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        # ab v2.6 mit Rendertest (Direct3D 11) je Grafikeinheit, nacheinander
        @{ Key = 'GPU';    Typ = 'Messung'; Titel = 'Grafik';                Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        # Testdatei LeosMinibench-Benchmark.tmp wird nach der Messung gelöscht, die Rückstandskontrolle prüft das
        @{ Key = 'Disk';   Typ = 'Messung'; Titel = 'Laufwerke';             Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        # WinSAT schreibt nur in den eigenen Datenspeicher von Windows
        @{ Key = 'WinSAT'; Typ = 'Messung'; Titel = 'WinSAT-Bewertung';      Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        # Hybridgrafik: GPU-Wahl für winsat.exe (HKCU\Software\Microsoft\DirectX\UserGpuPreferences) für eine zweite Messung,
        # protokolliert und direkt danach zurückgesetzt
        @{ Key = 'GpuWahl'; Typ = 'Option'; Titel = 'Grafikkarte zusätzlich messen (Hybridgrafik)'; Risiko = 'Aendern'; Neustart = 'nie'; Rueckgaengig = 'Protokoll'; Schalter = 'BenchGpuWahl' }
    )
}
