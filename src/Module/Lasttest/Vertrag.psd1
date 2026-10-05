# Modulvertrag Lasttest (Vertrag 1). Felder sind in src\Kern\Modulvertrag.ps1 beschrieben.
@{
    Vertrag         = 1
    Name            = 'Lasttest'
    Seite           = @{ Titel = 'Lasttest'; Kurz = 'Komponenten und Dauer wählbar' }
    Admin           = $true
    Risiko          = 'Lesen'
    Neustart        = 'nie'
    Parameter       = @('LastCpuMinuten', 'LastRamMinuten', 'LastGpuMinuten', 'LastDiskMinuten', 'LastRamProzent', 'LastDiskLaufwerk', 'LastAbbruchCpu', 'LastAbbruchGpu')
    Datenbankfelder = @('Lasttest')
    Schritte        = @(
        @{ Key = 'CPU';  Typ = 'Last'; Titel = 'CPU';         Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        @{ Key = 'RAM';  Typ = 'Last'; Titel = 'RAM';         Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        # ab v2.6 Rendertest (Direct3D 11) auf allen Grafikeinheiten gleichzeitig
        @{ Key = 'GPU';  Typ = 'Last'; Titel = 'Grafik';      Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
        # Testdatei LeosMinibench-Lasttest.tmp wird am Ende gelöscht, die Rückstandskontrolle prüft das
        @{ Key = 'Disk'; Typ = 'Last'; Titel = 'Datenträger'; Risiko = 'Lesen'; Neustart = 'nie'; Rueckgaengig = 'keins'; Exklusiv = $true }
    )
}
