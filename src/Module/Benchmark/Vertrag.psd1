# Modulvertrag Benchmark (Vertrag 1). Felder sind in src\Kern\Modulvertrag.ps1 beschrieben.
@{
    Vertrag         = 1
    Name            = 'Benchmark'
    Seite           = @{ Titel = 'Benchmark'; Kurz = 'Wählbare Messungen mit Vergleich' }
    Admin           = $true
    Risiko          = 'Lesen'
    Neustart        = 'nie'
    Parameter       = @('BenchTests', 'BenchLaufwerke', 'BenchmarkKurz', 'ReferenzSpeichern', 'ReferenzDatei', 'VergleichDateien', 'KeineDatenbank')
    Datenbankfelder = @('Werte', 'Messwerte', 'Messdauer', 'Laufwerke', 'Rendertest')
    Schritte        = @(
        @{ Key = 'CPU';    Typ = 'Messung'; Titel = 'Prozessor';             Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        @{ Key = 'RAM';    Typ = 'Messung'; Titel = 'Arbeitsspeicher';       Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        # ab v2.6 mit Rendertest (Direct3D 11) je Grafikeinheit, nacheinander
        @{ Key = 'GPU';    Typ = 'Messung'; Titel = 'Grafik';                Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        # Testdatei LeosMinibench-Benchmark.tmp wird nach der Messung gelöscht, die Rückstandskontrolle prüft das
        @{ Key = 'Disk';   Typ = 'Messung'; Titel = 'Laufwerke';             Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
    )
}
