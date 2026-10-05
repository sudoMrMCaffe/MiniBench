# Eingebettete Referenzprofile für Leos Minibench (v3.0)
$script:EmbeddedReferences = @{
    'Desktop_HighEnd.json' = @'
{
    "Format":  "PC-Diagnose-DB/2",
    "Name":  "Referenz: Desktop High-End (Ryzen 7600X, RX 6800)",
    "Computer":  "Referenz-Desktop-HighEnd",
    "Geraet":  {
                   "Id":  "REF-REFERENZ-DESKTOP-HIGHEND",
                   "Guete":  "hoch",
                   "Quellen":  [
                                   "Referenzsystem"
                               ]
               },
    "Datum":  "2026-10-01 12:00",
    "Version":  "2.95",
    "Quelle":  "Referenz",
    "Module":  "Benchmark",
    "Messdauer":  "normal",
    "System":  "Desktop High-End (AMD B650)",
    "Hardware":  {
                     "CPU":  "AMD Ryzen 5 7600X",
                     "RAM":  "32 GB DDR5-6000",
                     "GPU":  "Radeon RX 6800",
                     "IGPU":  null,
                     "GPUGemessen":  "AMD Radeon RX 6800",
                     "Datentraeger":  "NVMe PCIe 4.0 SSD 1TB; NVMe PCIe 3.0 SSD 1TB; SATA SSD 1TB",
                     "Betriebssystem":  "Microsoft Windows 11",
                     "Mainboard":  "AMD B650 Mainboard",
                     "WindowsInstalliert":  null
                 },
    "Werte":  {
                  "DISK|NVMe4|SW":  2779,
                  "RAM|Lesen":  61.9,
                  "CPU|MT":  38883,
                  "DISK|NVMe4|R8":  119846,
                  "DISK|SATA-SSD|SW":  524,
                  "DISK|NVMe4|SR":  6551,
                  "RAM|Kopieren":  24.1,
                  "GPU|REND":  133.3,
                  "GPU|REND1":  121,
                  "DISK|SATA-SSD|R8":  73138,
                  "DISK|SATA-SSD|R1":  11337,
                  "DISK|NVMe3|R8":  109080,
                  "DISK|SATA-SSD|SR":  558,
                  "CPU|AES":  1429,
                  "DISK|NVMe3|W1":  58294,
                  "GPU|RPKT":  12285,
                  "GPU|VMB":  296.1,
                  "GPU|DWM":  17440,
                  "DISK|NVMe3|R1":  14090,
                  "DISK|NVMe3|SW":  2910,
                  "CPU|ST":  3092,
                  "DISK|NVMe4|R1":  14178,
                  "DISK|SATA-SSD|W1":  29740,
                  "DISK|NVMe3|SR":  3114,
                  "RAM|Latenz":  80.6,
                  "RAM|Schreiben":  31.3,
                  "DISK|NVMe4|W1":  52665,
                  "CPU|SHA":  2535,
                  "CPU|DEFL":  296
              },
    "Messwerte":  {
                      "CPU|AMD Ryzen 5 7600X 6-Core Processor|ST":  3092,
                      "CPU|AMD Ryzen 5 7600X 6-Core Processor|MT":  38883,
                      "CPU|AMD Ryzen 5 7600X 6-Core Processor|AES":  1429,
                      "CPU|AMD Ryzen 5 7600X 6-Core Processor|SHA":  2535,
                      "CPU|AMD Ryzen 5 7600X 6-Core Processor|DEFL":  296,
                      "RAM|32GB|6000|Lesen":  61.9,
                      "RAM|32GB|6000|Schreiben":  31.3,
                      "RAM|32GB|6000|Kopieren":  24.1,
                      "RAM|32GB|6000|Latenz":  80.6,
                      "GPU|AMD Radeon RX 6800|VMB":  296.1,
                      "GPU|AMD Radeon RX 6800|DWM":  17440,
                      "GPU|AMD Radeon RX 6800|REND|1280x720":  133.3,
                      "GPU|AMD Radeon RX 6800|REND1|1280x720":  121,
                      "GPU|AMD Radeon RX 6800|RPKT":  12285,
                      "DISK|203791800341|SanDisk SDSSDH3 1T02|SR":  554,
                      "DISK|203791800341|SanDisk SDSSDH3 1T02|SW":  514,
                      "DISK|203791800341|SanDisk SDSSDH3 1T02|R1":  10433,
                      "DISK|203791800341|SanDisk SDSSDH3 1T02|R8":  70639,
                      "DISK|203791800341|SanDisk SDSSDH3 1T02|W1":  29362,
                      "DISK|S4X6NF0MC07136F|Samsung SSD 860 EVO 1TB|SR":  563,
                      "DISK|S4X6NF0MC07136F|Samsung SSD 860 EVO 1TB|SW":  533,
                      "DISK|S4X6NF0MC07136F|Samsung SSD 860 EVO 1TB|R1":  12241,
                      "DISK|S4X6NF0MC07136F|Samsung SSD 860 EVO 1TB|R8":  75637,
                      "DISK|S4X6NF0MC07136F|Samsung SSD 860 EVO 1TB|W1":  30117,
                      "DISK|0025_38B6_31A3_2B45.|SAMSUNG MZVL21T0HCLR-00B00|SR":  6551,
                      "DISK|0025_38B6_31A3_2B45.|SAMSUNG MZVL21T0HCLR-00B00|SW":  2779,
                      "DISK|0025_38B6_31A3_2B45.|SAMSUNG MZVL21T0HCLR-00B00|R1":  14178,
                      "DISK|0025_38B6_31A3_2B45.|SAMSUNG MZVL21T0HCLR-00B00|R8":  119846,
                      "DISK|0025_38B6_31A3_2B45.|SAMSUNG MZVL21T0HCLR-00B00|W1":  52665,
                      "DISK|0000_0006_2303_2570_CAF2_5B03_FF00_024E.|Lexar SSD NM620 1TB|SR":  2805,
                      "DISK|0000_0006_2303_2570_CAF2_5B03_FF00_024E.|Lexar SSD NM620 1TB|SW":  2908,
                      "DISK|0000_0006_2303_2570_CAF2_5B03_FF00_024E.|Lexar SSD NM620 1TB|R1":  16504,
                      "DISK|0000_0006_2303_2570_CAF2_5B03_FF00_024E.|Lexar SSD NM620 1TB|R8":  124476,
                      "DISK|0000_0006_2303_2570_CAF2_5B03_FF00_024E.|Lexar SSD NM620 1TB|W1":  48673,
                      "DISK|E823_8FA6_BF53_0001_001B_444A_463E_D685.|WDS100T3X0C-00SJG0|SR":  3422,
                      "DISK|E823_8FA6_BF53_0001_001B_444A_463E_D685.|WDS100T3X0C-00SJG0|SW":  2912,
                      "DISK|E823_8FA6_BF53_0001_001B_444A_463E_D685.|WDS100T3X0C-00SJG0|R1":  11676,
                      "DISK|E823_8FA6_BF53_0001_001B_444A_463E_D685.|WDS100T3X0C-00SJG0|R8":  93685,
                      "DISK|E823_8FA6_BF53_0001_001B_444A_463E_D685.|WDS100T3X0C-00SJG0|W1":  67914,
                      "WINSAT|CPU":  9.3,
                      "WINSAT|RAM":  9.3,
                      "WINSAT|DISK":  9.35,
                      "WINSAT|GFX":  9.9
                  },
    "Ordner":  "",
    "Laufwerke":  [
                      {
                          "Laufwerk":  "SanDisk SDSSDH3 1T02",
                          "Klasse":  "SATA-SSD",
                          "SR":  554,
                          "SW":  514,
                          "R1":  10433,
                          "R8":  70639,
                          "W1":  29362
                      },
                      {
                          "Laufwerk":  "Samsung SSD 860 EVO 1TB",
                          "Klasse":  "SATA-SSD",
                          "SR":  563,
                          "SW":  533,
                          "R1":  12241,
                          "R8":  75637,
                          "W1":  30117
                      },
                      {
                          "Laufwerk":  "SAMSUNG MZVL21T0HCLR-00B00",
                          "Klasse":  "NVMe PCIe 4.0 x4",
                          "SR":  6551,
                          "SW":  2779,
                          "R1":  14178,
                          "R8":  119846,
                          "W1":  52665
                      },
                      {
                          "Laufwerk":  "Lexar SSD NM620 1TB",
                          "Klasse":  "NVMe PCIe 3.0 x4",
                          "SR":  2805,
                          "SW":  2908,
                          "R1":  16504,
                          "R8":  124476,
                          "W1":  48673
                      },
                      {
                          "Laufwerk":  "WDS100T3X0C-00SJG0",
                          "Klasse":  "NVMe PCIe 3.0 x4",
                          "SR":  3422,
                          "SW":  2912,
                          "R1":  11676,
                          "R8":  93685,
                          "W1":  67914
                      }
                  ],
    "Befunde":  {
                    "Kritisch":  0,
                    "Warnungen":  0,
                    "Hinweise":  0,
                    "Liste":  [

                              ]
                },
    "Lasttest":  null,
    "Rendertest":  [
                       {
                           "Grafik":  "AMD Radeon RX 6800",
                           "Art":  "dGPU",
                           "Aufloesung":  "1280x720",
                           "Fps":  133.3,
                           "Low1":  121,
                           "Punkte":  12285,
                           "Bildfehler":  0,
                           "Treiberreset":  false,
                           "Fehler":  ""
                       }
                   ],
    "Schreibzugriffe":  null,
    "Ablauf":  "normal",
    "Sensoren":  {

                 },
    "Optimierung":  null,
    "Akku":  null
}
'@
    'Desktop_Mittelklasse.json' = @'
{
    "Format":  "PC-Diagnose-DB/2",
    "Name":  "Referenz: Desktop Mittelklasse (Ryzen 5600, RX 570)",
    "Computer":  "Referenz-Desktop-Mittelklasse",
    "Geraet":  {
                   "Id":  "REF-REFERENZ-DESKTOP-MITTELKLASSE",
                   "Guete":  "hoch",
                   "Quellen":  [
                                   "Referenzsystem"
                               ]
               },
    "Datum":  "2026-10-01 12:00",
    "Version":  "2.95",
    "Quelle":  "Referenz",
    "Module":  "Benchmark",
    "Messdauer":  "normal",
    "System":  "Desktop Mittelklasse (AMD B450)",
    "Hardware":  {
                     "CPU":  "AMD Ryzen 5 5600",
                     "RAM":  "32 GB DDR4-2133",
                     "GPU":  "Radeon RX 570 Series",
                     "IGPU":  null,
                     "GPUGemessen":  "Radeon RX 570 Series",
                     "Datentraeger":  "NVMe PCIe 3.0 SSD 500GB; SATA SSD 1TB",
                     "Betriebssystem":  "Microsoft Windows 11",
                     "Mainboard":  "AMD B450 Mainboard",
                     "WindowsInstalliert":  null
                 },
    "Werte":  {
                  "DISK|NVMe3|R8":  108045,
                  "GPU|DWM":  4339,
                  "RAM|Latenz":  113.2,
                  "GPU|VMB":  73.7,
                  "CPU|MT":  30319,
                  "DISK|HDD|SW":  123,
                  "GPU|REND":  45.4,
                  "GPU|REND1":  42.8,
                  "DISK|HDD|W1":  1412,
                  "DISK|HDD|R8":  178,
                  "RAM|Kopieren":  11.5,
                  "RAM|Schreiben":  13.4,
                  "CPU|ST":  2731,
                  "CPU|AES":  1160,
                  "DISK|HDD|SR":  112,
                  "DISK|NVMe3|W1":  35518,
                  "CPU|SHA":  2192,
                  "GPU|RPKT":  4189,
                  "RAM|Lesen":  27.5,
                  "DISK|NVMe3|SW":  2591,
                  "DISK|NVMe3|R1":  14329,
                  "DISK|NVMe3|SR":  3095,
                  "CPU|DEFL":  244,
                  "DISK|HDD|R1":  104
              },
    "Messwerte":  {
                      "CPU|AMD Ryzen 5 5600 6-Core Processor|ST":  2731,
                      "CPU|AMD Ryzen 5 5600 6-Core Processor|MT":  30319,
                      "CPU|AMD Ryzen 5 5600 6-Core Processor|AES":  1160,
                      "CPU|AMD Ryzen 5 5600 6-Core Processor|SHA":  2192,
                      "CPU|AMD Ryzen 5 5600 6-Core Processor|DEFL":  244,
                      "RAM|32GB|2133|Lesen":  27.5,
                      "RAM|32GB|2133|Schreiben":  13.4,
                      "RAM|32GB|2133|Kopieren":  11.5,
                      "RAM|32GB|2133|Latenz":  113.2,
                      "GPU|Radeon RX 570 Series|VMB":  73.7,
                      "GPU|Radeon RX 570 Series|DWM":  4339,
                      "GPU|Radeon RX 570 Series|REND|1280x720":  45.4,
                      "GPU|Radeon RX 570 Series|REND1|1280x720":  42.8,
                      "GPU|Radeon RX 570 Series|RPKT":  4189,
                      "DISK|Z1E7D75M|ST2000DX001-1CM164|SR":  110,
                      "DISK|Z1E7D75M|ST2000DX001-1CM164|SW":  128,
                      "DISK|Z1E7D75M|ST2000DX001-1CM164|R1":  106,
                      "DISK|Z1E7D75M|ST2000DX001-1CM164|R8":  172,
                      "DISK|Z1E7D75M|ST2000DX001-1CM164|W1":  1339,
                      "DISK|ZFN03R4F|ST4000DM004-2CV104|SR":  114,
                      "DISK|ZFN03R4F|ST4000DM004-2CV104|SW":  118,
                      "DISK|ZFN03R4F|ST4000DM004-2CV104|R1":  103,
                      "DISK|ZFN03R4F|ST4000DM004-2CV104|R8":  185,
                      "DISK|ZFN03R4F|ST4000DM004-2CV104|W1":  1485,
                      "DISK|0025_38D9_31A0_34FA.|Samsung SSD 980 1TB|SR":  3095,
                      "DISK|0025_38D9_31A0_34FA.|Samsung SSD 980 1TB|SW":  2591,
                      "DISK|0025_38D9_31A0_34FA.|Samsung SSD 980 1TB|R1":  14329,
                      "DISK|0025_38D9_31A0_34FA.|Samsung SSD 980 1TB|R8":  108045,
                      "DISK|0025_38D9_31A0_34FA.|Samsung SSD 980 1TB|W1":  35518,
                      "WINSAT|CPU":  9.3,
                      "WINSAT|RAM":  9.3,
                      "WINSAT|DISK":  8.8,
                      "WINSAT|GFX":  8.7
                  },
    "Ordner":  "",
    "Laufwerke":  [
                      {
                          "Laufwerk":  "ST2000DX001-1CM164",
                          "Klasse":  "Festplatte",
                          "SR":  110,
                          "SW":  128,
                          "R1":  106,
                          "R8":  172,
                          "W1":  1339
                      },
                      {
                          "Laufwerk":  "ST4000DM004-2CV104",
                          "Klasse":  "Festplatte",
                          "SR":  114,
                          "SW":  118,
                          "R1":  103,
                          "R8":  185,
                          "W1":  1485
                      },
                      {
                          "Laufwerk":  "Samsung SSD 980 1TB",
                          "Klasse":  "NVMe PCIe 3.0 x4",
                          "SR":  3095,
                          "SW":  2591,
                          "R1":  14329,
                          "R8":  108045,
                          "W1":  35518
                      }
                  ],
    "Befunde":  {
                    "Kritisch":  0,
                    "Warnungen":  0,
                    "Hinweise":  0,
                    "Liste":  [

                              ]
                },
    "Lasttest":  null,
    "Rendertest":  [
                       {
                           "Grafik":  "Radeon RX 570 Series",
                           "Art":  "dGPU",
                           "Aufloesung":  "1280x720",
                           "Fps":  45.4,
                           "Low1":  42.8,
                           "Punkte":  4189,
                           "Bildfehler":  0,
                           "Treiberreset":  false,
                           "Fehler":  ""
                       }
                   ],
    "Schreibzugriffe":  null,
    "Ablauf":  "normal",
    "Sensoren":  {

                 },
    "Optimierung":  null,
    "Akku":  null
}
'@
    'MiniPC_APU.json' = @'
{
    "Format":  "PC-Diagnose-DB/2",
    "Name":  "Referenz: Mini-PC / APU (Ryzen 7 255H, Radeon 780M)",
    "Computer":  "Referenz-MiniPC-APU",
    "Geraet":  {
                   "Id":  "REF-REFERENZ-MINIPC-APU",
                   "Guete":  "hoch",
                   "Quellen":  [
                                   "Referenzsystem"
                               ]
               },
    "Datum":  "2026-10-01 12:00",
    "Version":  "2.95",
    "Quelle":  "Referenz",
    "Module":  "Benchmark",
    "Messdauer":  "normal",
    "System":  "Mini-PC / APU (AMD Ryzen 7)",
    "Hardware":  {
                     "CPU":  "AMD Ryzen 7 H 255 w/ Radeon 780M Graphics",
                     "RAM":  "32 GB DDR5-5600",
                     "GPU":  "Radeon 780M Graphics",
                     "IGPU":  "Radeon 780M Graphics",
                     "GPUGemessen":  "AMD Radeon 780M Graphics",
                     "Datentraeger":  "NVMe PCIe 4.0 SSD 1TB",
                     "Betriebssystem":  "Microsoft Windows 11",
                     "Mainboard":  "Mini-PC Mainboard",
                     "WindowsInstalliert":  null
                 },
    "Werte":  {
                  "GPU|DWM":  1670,
                  "RAM|Latenz":  112,
                  "GPU|VMB":  28.4,
                  "CPU|MT":  46553,
                  "DISK|NVMe4|W1":  54294,
                  "GPU|REND":  46.8,
                  "GPU|REND1":  42.3,
                  "DISK|NVMe4|R8":  34279,
                  "RAM|Kopieren":  17.4,
                  "DISK|NVMe4|SR":  4295,
                  "RAM|Schreiben":  25.4,
                  "CPU|ST":  2928,
                  "CPU|AES":  1362,
                  "CPU|SHA":  2409,
                  "GPU|RPKT":  4313,
                  "RAM|Lesen":  58.2,
                  "DISK|NVMe4|R1":  4519,
                  "CPU|DEFL":  345,
                  "DISK|NVMe4|SW":  1140
              },
    "Messwerte":  {
                      "CPU|AMD Ryzen 7 H 255 w/ Radeon 780M Graphics|ST":  2928,
                      "CPU|AMD Ryzen 7 H 255 w/ Radeon 780M Graphics|MT":  46553,
                      "CPU|AMD Ryzen 7 H 255 w/ Radeon 780M Graphics|AES":  1362,
                      "CPU|AMD Ryzen 7 H 255 w/ Radeon 780M Graphics|SHA":  2409,
                      "CPU|AMD Ryzen 7 H 255 w/ Radeon 780M Graphics|DEFL":  345,
                      "RAM|32GB|5600|Lesen":  58.2,
                      "RAM|32GB|5600|Schreiben":  25.4,
                      "RAM|32GB|5600|Kopieren":  17.4,
                      "RAM|32GB|5600|Latenz":  112,
                      "GPU|AMD Radeon 780M Graphics|VMB":  28.4,
                      "GPU|AMD Radeon 780M Graphics|DWM":  1670,
                      "GPU|AMD Radeon 780M Graphics|REND|1280x720":  46.8,
                      "GPU|AMD Radeon 780M Graphics|REND1|1280x720":  42.3,
                      "GPU|AMD Radeon 780M Graphics|RPKT":  4313,
                      "DISK|ACE4_2E00_3A0E_DF9B_2EE4_AC00_0000_0001.|PC801 NVMe SK hynix 1TB|SR":  4295,
                      "DISK|ACE4_2E00_3A0E_DF9B_2EE4_AC00_0000_0001.|PC801 NVMe SK hynix 1TB|SW":  1140,
                      "DISK|ACE4_2E00_3A0E_DF9B_2EE4_AC00_0000_0001.|PC801 NVMe SK hynix 1TB|R1":  4519,
                      "DISK|ACE4_2E00_3A0E_DF9B_2EE4_AC00_0000_0001.|PC801 NVMe SK hynix 1TB|R8":  34279,
                      "DISK|ACE4_2E00_3A0E_DF9B_2EE4_AC00_0000_0001.|PC801 NVMe SK hynix 1TB|W1":  54294,
                      "WINSAT|CPU":  9.4,
                      "WINSAT|RAM":  9.4,
                      "WINSAT|DISK":  8.45,
                      "WINSAT|GFX":  8.2
                  },
    "Ordner":  "",
    "Laufwerke":  [
                      {
                          "Laufwerk":  "PC801 NVMe SK hynix 1TB",
                          "Klasse":  "NVMe PCIe 4.0 x4",
                          "SR":  4295,
                          "SW":  1140,
                          "R1":  4519,
                          "R8":  34279,
                          "W1":  54294
                      }
                  ],
    "Befunde":  {
                    "Kritisch":  0,
                    "Warnungen":  0,
                    "Hinweise":  0,
                    "Liste":  [

                              ]
                },
    "Lasttest":  null,
    "Rendertest":  [
                       {
                           "Grafik":  "AMD Radeon 780M Graphics",
                           "Art":  "iGPU",
                           "Aufloesung":  "1280x720",
                           "Fps":  46.8,
                           "Low1":  42.3,
                           "Punkte":  4313,
                           "Bildfehler":  0,
                           "Treiberreset":  false,
                           "Fehler":  ""
                       }
                   ],
    "Schreibzugriffe":  null,
    "Ablauf":  "normal",
    "Sensoren":  {

                 },
    "Optimierung":  null,
    "Akku":  null
}
'@
    'Notebook_Standard.json' = @'
{
    "Format":  "PC-Diagnose-DB/2",
    "Name":  "Referenz: Notebook Standard (Core i5, Intel UHD)",
    "Computer":  "Referenz-Notebook-Standard",
    "Geraet":  {
                   "Id":  "REF-REFERENZ-NOTEBOOK-STANDARD",
                   "Guete":  "hoch",
                   "Quellen":  [
                                   "Referenzsystem"
                               ]
               },
    "Datum":  "2026-10-01 12:00",
    "Version":  "2.95",
    "Quelle":  "Referenz",
    "Module":  "Benchmark",
    "Messdauer":  "normal",
    "System":  "Notebook Standard (Intel Core i5)",
    "Hardware":  {
                     "CPU":  "Intel Core i5-8365U",
                     "RAM":  "24 GB DDR4-2400",
                     "GPU":  "UHD Graphics 620",
                     "IGPU":  "UHD Graphics 620",
                     "GPUGemessen":  "Intel(R) UHD Graphics 620",
                     "Datentraeger":  "NVMe PCIe 3.0 SSD 512GB",
                     "Betriebssystem":  "Microsoft Windows 11",
                     "Mainboard":  "Notebook Mainboard",
                     "WindowsInstalliert":  null
                 },
    "Werte":  {
                  "DISK|NVMe3|R8":  112473,
                  "GPU|DWM":  383,
                  "RAM|Latenz":  134.4,
                  "GPU|VMB":  6.5,
                  "CPU|MT":  14744,
                  "GPU|REND":  4.8,
                  "GPU|REND1":  4.7,
                  "DISK|NVMe3|W1":  22297,
                  "RAM|Kopieren":  9.9,
                  "RAM|Schreiben":  13.4,
                  "CPU|ST":  2133,
                  "CPU|AES":  1031,
                  "CPU|SHA":  437,
                  "GPU|RPKT":  442,
                  "RAM|Lesen":  28.3,
                  "DISK|NVMe3|SW":  2424,
                  "DISK|NVMe3|R1":  15440,
                  "DISK|NVMe3|SR":  3487,
                  "CPU|DEFL":  118
              },
    "Messwerte":  {
                      "CPU|Intel(R) Core(TM) i5-8365U CPU @ 1.60GHz|ST":  2133,
                      "CPU|Intel(R) Core(TM) i5-8365U CPU @ 1.60GHz|MT":  14744,
                      "CPU|Intel(R) Core(TM) i5-8365U CPU @ 1.60GHz|AES":  1031,
                      "CPU|Intel(R) Core(TM) i5-8365U CPU @ 1.60GHz|SHA":  437,
                      "CPU|Intel(R) Core(TM) i5-8365U CPU @ 1.60GHz|DEFL":  118,
                      "RAM|24GB|2400|Lesen":  28.3,
                      "RAM|24GB|2400|Schreiben":  13.4,
                      "RAM|24GB|2400|Kopieren":  9.9,
                      "RAM|24GB|2400|Latenz":  134.4,
                      "GPU|Intel(R) UHD Graphics 620|VMB":  6.5,
                      "GPU|Intel(R) UHD Graphics 620|DWM":  383,
                      "GPU|Intel(R) UHD Graphics 620|REND|1280x720":  4.8,
                      "GPU|Intel(R) UHD Graphics 620|REND1|1280x720":  4.7,
                      "GPU|Intel(R) UHD Graphics 620|RPKT":  442,
                      "DISK|0025_3887_11B9_A4F0.|SAMSUNG MZVLB512HBJQ-000L7|SR":  3487,
                      "DISK|0025_3887_11B9_A4F0.|SAMSUNG MZVLB512HBJQ-000L7|SW":  2424,
                      "DISK|0025_3887_11B9_A4F0.|SAMSUNG MZVLB512HBJQ-000L7|R1":  15440,
                      "DISK|0025_3887_11B9_A4F0.|SAMSUNG MZVLB512HBJQ-000L7|R8":  112473,
                      "DISK|0025_3887_11B9_A4F0.|SAMSUNG MZVLB512HBJQ-000L7|W1":  22297,
                      "WINSAT|CPU":  8.9,
                      "WINSAT|RAM":  8.9,
                      "WINSAT|DISK":  9.05,
                      "WINSAT|GFX":  6.2
                  },
    "Ordner":  "",
    "Laufwerke":  [
                      {
                          "Laufwerk":  "SAMSUNG MZVLB512HBJQ-000L7",
                          "Klasse":  "NVMe PCIe 3.0 x4",
                          "SR":  3487,
                          "SW":  2424,
                          "R1":  15440,
                          "R8":  112473,
                          "W1":  22297
                      }
                  ],
    "Befunde":  {
                    "Kritisch":  0,
                    "Warnungen":  0,
                    "Hinweise":  0,
                    "Liste":  [

                              ]
                },
    "Lasttest":  null,
    "Rendertest":  [
                       {
                           "Grafik":  "Intel(R) UHD Graphics 620",
                           "Art":  "iGPU",
                           "Aufloesung":  "1280x720",
                           "Fps":  4.8,
                           "Low1":  4.7,
                           "Punkte":  442,
                           "Bildfehler":  0,
                           "Treiberreset":  false,
                           "Fehler":  ""
                       }
                   ],
    "Schreibzugriffe":  null,
    "Ablauf":  "normal",
    "Sensoren":  {

                 },
    "Optimierung":  null,
    "Akku":  null
}
'@
    'Workstation_Mobil.json' = @'
{
    "Format":  "PC-Diagnose-DB/2",
    "Name":  "Referenz: Workstation Mobil (Core i9-13900H, RTX 3000 Ada)",
    "Computer":  "Referenz-Workstation-Mobil",
    "Geraet":  {
                   "Id":  "REF-REFERENZ-WORKSTATION-MOBIL",
                   "Guete":  "hoch",
                   "Quellen":  [
                                   "Referenzsystem"
                               ]
               },
    "Datum":  "2026-10-01 12:00",
    "Version":  "2.95",
    "Quelle":  "Referenz",
    "Module":  "Benchmark",
    "Messdauer":  "normal",
    "System":  "Workstation Mobil (Intel Core i9)",
    "Hardware":  {
                     "CPU":  "13th Gen Intel Core i9-13900H",
                     "RAM":  "64 GB LPDDR5-6000",
                     "GPU":  "RTX 3000 Ada Generation Laptop GPU",
                     "IGPU":  "Iris(R) Xe Graphics",
                     "GPUGemessen":  "NVIDIA RTX 3000 Ada Generation Laptop GPU",
                     "Datentraeger":  "NVMe PCIe 4.0 SSD 1TB",
                     "Betriebssystem":  "Microsoft Windows 11",
                     "Mainboard":  "Mobile Workstation Board",
                     "WindowsInstalliert":  null
                 },
    "Werte":  {
                  "GPU|DWM":  2850,
                  "RAM|Latenz":  113.9,
                  "GPU|VMB":  48.4,
                  "CPU|MT":  42759,
                  "GPU|REND":  90.6,
                  "GPU|REND1":  37.8,
                  "RAM|Kopieren":  28.5,
                  "RAM|Schreiben":  47.2,
                  "CPU|ST":  3464,
                  "CPU|AES":  1786,
                  "CPU|SHA":  2409,
                  "GPU|RPKT":  8354,
                  "RAM|Lesen":  67.9,
                  "CPU|DEFL":  295
              },
    "Messwerte":  {
                      "CPU|13th Gen Intel(R) Core(TM) i9-13900H|ST":  3464,
                      "CPU|13th Gen Intel(R) Core(TM) i9-13900H|MT":  42759,
                      "CPU|13th Gen Intel(R) Core(TM) i9-13900H|AES":  1786,
                      "CPU|13th Gen Intel(R) Core(TM) i9-13900H|SHA":  2409,
                      "CPU|13th Gen Intel(R) Core(TM) i9-13900H|DEFL":  295,
                      "RAM|64GB|6000|Lesen":  67.9,
                      "RAM|64GB|6000|Schreiben":  47.2,
                      "RAM|64GB|6000|Kopieren":  28.5,
                      "RAM|64GB|6000|Latenz":  113.9,
                      "GPU|Intel(R) Iris(R) Xe Graphics|VMB":  48.4,
                      "GPU|Intel(R) Iris(R) Xe Graphics|DWM":  2850,
                      "GPU|NVIDIA RTX 3000 Ada Generation Laptop GPU|REND|1280x720":  90.6,
                      "GPU|NVIDIA RTX 3000 Ada Generation Laptop GPU|REND1|1280x720":  37.8,
                      "GPU|NVIDIA RTX 3000 Ada Generation Laptop GPU|RPKT":  8354,
                      "GPU|Intel(R) Iris(R) Xe Graphics|REND|1280x720":  23,
                      "GPU|Intel(R) Iris(R) Xe Graphics|REND1|1280x720":  21.8,
                      "GPU|Intel(R) Iris(R) Xe Graphics|RPKT":  2124,
                      "DISK|E823_8FA6_BF53_0001_001B_444A_4143_AA1D.|NVMe PC SN820 NVMe WD 4096GB|SR":  6689,
                      "DISK|E823_8FA6_BF53_0001_001B_444A_4143_AA1D.|NVMe PC SN820 NVMe WD 4096GB|SW":  3974,
                      "DISK|E823_8FA6_BF53_0001_001B_444A_4143_AA1D.|NVMe PC SN820 NVMe WD 4096GB|R1":  18211,
                      "DISK|E823_8FA6_BF53_0001_001B_444A_4143_AA1D.|NVMe PC SN820 NVMe WD 4096GB|R8":  106690,
                      "DISK|E823_8FA6_BF53_0001_001B_444A_4143_AA1D.|NVMe PC SN820 NVMe WD 4096GB|W1":  46373,
                      "WINSAT|CPU":  9.4,
                      "WINSAT|RAM":  9.4,
                      "WINSAT|DISK":  9.45,
                      "WINSAT|GFX":  8.4
                  },
    "Ordner":  "",
    "Laufwerke":  [
                      {
                          "Laufwerk":  "NVMe PC SN820 NVMe WD 4096GB",
                          "Klasse":  "NVMe",
                          "SR":  6689,
                          "SW":  3974,
                          "R1":  18211,
                          "R8":  106690,
                          "W1":  46373
                      }
                  ],
    "Befunde":  {
                    "Kritisch":  0,
                    "Warnungen":  0,
                    "Hinweise":  0,
                    "Liste":  [

                              ]
                },
    "Lasttest":  null,
    "Rendertest":  [
                       {
                           "Grafik":  "NVIDIA RTX 3000 Ada Generation Laptop GPU",
                           "Art":  "dGPU",
                           "Aufloesung":  "1280x720",
                           "Fps":  90.6,
                           "Low1":  37.8,
                           "Punkte":  8354,
                           "Bildfehler":  0,
                           "Treiberreset":  false,
                           "Fehler":  ""
                       },
                       {
                           "Grafik":  "Intel(R) Iris(R) Xe Graphics",
                           "Art":  "iGPU",
                           "Aufloesung":  "1280x720",
                           "Fps":  23,
                           "Low1":  21.8,
                           "Punkte":  2124,
                           "Bildfehler":  0,
                           "Treiberreset":  false,
                           "Fehler":  ""
                       }
                   ],
    "Schreibzugriffe":  null,
    "Ablauf":  "normal",
    "Sensoren":  {

                 },
    "Optimierung":  null,
    "Akku":  null
}
'@
}
