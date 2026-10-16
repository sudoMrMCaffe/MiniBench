// Selbsttest der Oberfläche (ab v3.53). Wird von tests/Hilfen.ps1 zusammen mit den Dateien aus src/Oberflaeche zu einer
// eigenen exe übersetzt (keine using-Zeilen: es gelten die von DiagGui.cs am Anfang derselben Übersetzungseinheit).
// Ausgabe je Fall eine Zeile: OK|Name oder FEHL|Name|Grund. Argument 1: Projektordner (für Testdaten aus src).
public static class GuiSelbsttest
{
    static System.Collections.Generic.List<string> outLines = new System.Collections.Generic.List<string>();
    static string root = "";

    [System.STAThread]
    public static int Main(string[] args)
    {
        root = args.Length > 0 ? args[0] : "";
        System.Threading.Thread.CurrentThread.CurrentCulture = new System.Globalization.CultureInfo("de-DE");
        Fall("UI.Skalierung", UiSkalierung);
        Fall("UI.Farbschema", UiFarbschema);
        Fall("ToggleSwitch", ToggleSchalter);
        Fall("FluentCard", FluentKarte);
        Fall("Hinweise.Umbruch", HinweisUmbruch);
        Fall("Grafikauswahl.Abgleich", GrafikAbgleich);
        Fall("Softwarepakete.Auswahl", SoftwareAuswahl);
        Fall("Softwarepakete.Ereignisse", SoftwareEreignisse);
        Fall("Datenbank.Referenzen", DatenbankReferenzen);
        Fall("Aenderungen.Softwarepaket", AenderungSoftwarepaket);
        Fall("Netzlaufwerk.Pfad", NasPfad);
        Fall("Netzlaufwerk.Konfiguration", NasKonfiguration);
        Fall("Netzlaufwerk.Ergebnis", NasErgebnis);
        Fall("Wartung.Vertragszeile", WartungVertragszeile);
        Fall("Dialog.Farbschema", DialogFarbschema);
        Fall("Oberflaeche.Kontrast", Kontrast);
        Fall("Startknopf.Beschriftung", StartknopfBeschriftung);
        Fall("Zeitangabe.Minuten", Zeitangabe);
        Fall("Lasttest.Gesamtdauer", LasttestGesamtdauer);
        Fall("Lasttest.Deaktivierung", LasttestDeaktivierung);
        Fall("Startuebersicht", Startuebersicht);
        Fall("Wartung.Detailtext", WartungDetailtext);
        Fall("Voreinstellung.Altwerte", VoreinstellungAltwerte);
        Fall("Laufwerk.Kurzname", LaufwerkKurzname);
        Fall("Ablage.Kurzform", AblageKurzform);
        Fall("Etikett.Risikostufe", EtikettRisikostufe);
        Fall("Aufklappgruppe", Aufklappgruppe);
        Fall("Diagnose.Profile", DiagnoseProfile);
        Fall("Etikett.Schreibweise", EtikettSchreibweise);
        Fall("Karte", KarteRahmen);
        Fall("StartseitenElemente", StartseitenElemente);
        foreach (string l in outLines) System.Console.WriteLine(l);
        return 0;
    }

    delegate void Pruefung();
    static void Fall(string name, Pruefung p)
    {
        try { p(); outLines.Add("OK|" + name); }
        catch (System.Exception ex) { outLines.Add("FEHL|" + name + "|" + ex.Message.Replace("\r", " ").Replace("\n", " ")); }
    }
    static void Ist(bool bedingung, string text) { if (!bedingung) throw new System.Exception(text); }

    static void UiSkalierung()
    {
        float alt = UI.DpiScale;
        try
        {
            UI.DpiScale = 1.0f; Ist(UI.S(100) == 100 && UI.SF(50f) == 50f, "100 %");
            UI.DpiScale = 1.5f; Ist(UI.S(100) == 150 && UI.S(74) == 111 && UI.SF(10f) == 15f, "150 %");
            UI.DpiScale = 2.0f; Ist(UI.S(100) == 200 && UI.SF(10f) == 20f, "200 %");
        }
        finally { UI.DpiScale = alt; }
    }

    static void UiFarbschema()
    {
        UI.SetTheme(false);
        Ist(!UI.IsDark && UI.Bg.GetBrightness() > 0.8f && UI.Text.GetBrightness() < 0.3f, "hell: heller Grund, dunkle Schrift");
        UI.SetTheme(true);
        Ist(UI.IsDark && UI.Bg.GetBrightness() < 0.3f && UI.Text.GetBrightness() > 0.8f, "dunkel: dunkler Grund, helle Schrift");
        UI.SetTheme(false);
    }

    static void ToggleSchalter()
    {
        using (ToggleSwitch t = new ToggleSwitch())
        {
            int n = 0; t.CheckedChanged += delegate { n++; };
            Ist(!t.Checked, "Vorgabe aus");
            t.Checked = true; Ist(t.Checked && n == 1, "Einschalten meldet CheckedChanged");
            t.Checked = true; Ist(n == 1, "gleicher Wert meldet nichts");
        }
    }

    static void FluentKarte()
    {
        using (FluentCard c = new FluentCard("Testkarte", "Beschreibung", UI.IcoDiag))
        {
            int n = 0; c.CheckedChanged += delegate { n++; };
            Ist(c.Title == "Testkarte" && c.Description == "Beschreibung" && !c.Checked, "Titel, Text, Vorgabe aus");
            c.Checked = true; Ist(c.Checked && n == 1, "Haken meldet CheckedChanged");
        }
    }

    static void HinweisUmbruch()
    {
        string lang = "";
        for (int i = 0; i < 60; i++) lang += (i > 0 ? " " : "") + "wort";
        string w = DiagGui.WrapTip(lang + "\r\nzweiter Absatz");
        foreach (string l in w.Split(new string[] { "\r\n" }, System.StringSplitOptions.None)) Ist(l.Length <= 90, "Zeile über 90 Zeichen: " + l.Length);
        Ist(w.EndsWith("\r\nzweiter Absatz"), "vorhandener Umbruch bleibt");
        Ist(DiagGui.WrapTip("") == "" && DiagGui.WrapTip(null) == "", "leer bleibt leer");
    }

    static ComboBox Box(int n, int sel)
    {
        ComboBox c = new ComboBox();
        for (int i = 0; i < n; i++) c.Items.Add("Eintrag " + i);
        c.SelectedIndex = sel;
        return c;
    }

    // Benchmark und Lasttest halten Auflösung, Anzeige und Grafikeinheit gleich, in beide Richtungen (Fehler bis 3.52:
    // die Wahl auf der Seite Lasttest sprang auf den Wert des Benchmarks zurück)
    static void GrafikAbgleich()
    {
        ComboBox[] bench = new ComboBox[] { Box(2, 0), Box(3, 0), Box(3, 0) };
        ComboBox[] last = new ComboBox[] { Box(2, 0), Box(3, 0), Box(3, 0) };
        last[2].SelectedIndex = 2;
        DiagGui.CopySelection(last, bench);
        Ist(bench[2].SelectedIndex == 2, "Lasttest -> Benchmark: Grafikeinheit übernommen");
        Ist(last[2].SelectedIndex == 2, "Lasttest behält seine Wahl");
        bench[0].SelectedIndex = 1;
        DiagGui.CopySelection(bench, last);
        Ist(last[0].SelectedIndex == 1 && last[2].SelectedIndex == 2, "Benchmark -> Lasttest: Auflösung übernommen, Grafikeinheit gleich");
        // fehlende Liste (keine Grafikauswahl) und Index außerhalb der Zielliste bleiben ohne Wirkung
        ComboBox[] kurz = new ComboBox[] { Box(2, 1), null, Box(1, 0) };
        DiagGui.CopySelection(last, kurz);
        Ist(kurz[0].SelectedIndex == 1, "erste Liste übernommen");
        Ist(kurz[2].SelectedIndex == 0, "ungültiger Index wird nicht übernommen");
        DiagGui.CopySelection(null, bench); DiagGui.CopySelection(bench, null);
    }

    static void SoftwareAuswahl()
    {
        string[] ids = new string[] { "Google.Chrome", "7zip.7zip", "VideoLAN.VLC" };
        string[] names = new string[] { "Google Chrome", "7-Zip; \"x\"=y", "VLC" };
        string spec = DiagGui.WingetSpec(new System.Collections.Generic.List<int>(new int[] { 0, 1, 7 }), ids, names);
        Ist(spec == "Google.Chrome=Google Chrome;7zip.7zip=7-Zip, 'x'-y", "Spezifikation: " + spec);
        // je Paket list (120 s) + install (1200 s) + list (120 s) im Arbeitsprozess
        Ist(DiagGui.WingetTimeoutSec(3) >= 3 * (120 + 1200 + 120) + 60, "Frist der Oberfläche liegt über den Fristen des Arbeitsprozesses");
    }

    static void SoftwareEreignisse()
    {
        string st, tx;
        Ist(DiagGui.ParseWingetEvent("@@PAKET|1|2|Google.Chrome|installiert|Google Chrome installiert¦ok", out st, out tx), "Paketereignis erkannt");
        Ist(st == "installiert" && tx == "Google Chrome installiert|ok", "Status und Text: " + st + " / " + tx);
        Ist(!DiagGui.ParseWingetEvent("@@RESULT|1|0|0", out st, out tx), "anderes Ereignis wird nicht gelesen");
        Ist(!DiagGui.ParseWingetEvent("@@PAKET|1|2", out st, out tx), "unvollständige Zeile wird nicht gelesen");
    }

    static void DatenbankReferenzen()
    {
        string dir = System.IO.Path.Combine(System.IO.Path.Combine(System.IO.Path.Combine(root, "src"), "Daten"), "Referenzen");
        System.Collections.Generic.List<DbEntry> l = DbEntry.Load(dir);
        Ist(l.Count >= 5, "mindestens 5 Referenzprofile, gelesen: " + l.Count);
        foreach (DbEntry e in l)
        {
            Ist(e.Name.Length > 0 && e.Computer.Length > 0 && e.Cpu.Length > 0 && e.Werte.Count > 0, "Profil vollständig: " + e.Path);
            Ist(e.Kerne > 0 && e.Threads > 0, "Kerne und Threads vorhanden: " + e.Path);
        }
    }

    // Ein Eintrag, wie ihn Install-SoftwarePaket schreibt, erscheint auf der Seite Änderungen und ist rückgängig machbar
    static void AenderungSoftwarepaket()
    {
        string dir = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "MinibenchSelbsttest_" + System.Guid.NewGuid().ToString("N"));
        string pc = System.IO.Path.Combine(dir, "PC");
        System.IO.Directory.CreateDirectory(pc);
        try
        {
            string json = "{\"Format\":\"Minibench-Aenderungen/1\",\"Computer\":\"" + System.Environment.MachineName + "\",\"GeraetId\":\"\",\"Version\":\"3.53\",\"Lauf\":\"2026-10-09 10:00:00\",\"Bericht\":\"\",\"Eintraege\":[" +
                "{\"Id\":1,\"Zeit\":\"2026-10-09 10:01:00\",\"Modul\":\"Tools\",\"Schritt\":\"Softwarepaket\",\"Titel\":\"7-Zip installiert (winget)\",\"Risiko\":\"Eingriff\",\"Art\":\"Softwarepaket\",\"Ziel\":\"7zip.7zip\",\"Vorher\":\"nicht installiert\",\"Nachher\":\"installiert\",\"Daten\":{\"PaketId\":\"7zip.7zip\",\"Name\":\"7-Zip\"},\"Gegenbefehl\":\"winget uninstall --id 7zip.7zip -e\",\"Status\":\"aktiv\",\"Ergebnis\":\"\"}]}";
            System.IO.File.WriteAllText(System.IO.Path.Combine(pc, "20261009_100000.json"), json, new System.Text.UTF8Encoding(false));
            System.Collections.Generic.List<ChangeEntry> l = ChangeEntry.Load(dir);
            Ist(l.Count == 1, "ein Eintrag gelesen: " + l.Count);
            Ist(l[0].Art == "Softwarepaket" && l[0].Risiko == "Eingriff" && l[0].Ziel == "7zip.7zip", "Art, Risiko, Ziel");
            Ist(l[0].Undoable, "auf diesem PC rückgängig machbar");
        }
        finally { try { System.IO.Directory.Delete(dir, true); } catch { } }
    }

    // ab v3.54: Netzlaufwerk als Spiegel (NasAblage in DiagGui_Modelle.cs)
    static void NasPfad()
    {
        Ist(NasAblage.PfadFehler(@"\\TRUENAS\Multimedia\MiniBench") == "", "UNC-Pfad gültig");
        Ist(NasAblage.PfadFehler(@"\\nas\freigabe") == "", "Freigabe ohne Unterordner gültig");
        Ist(NasAblage.PfadFehler(@"\TRUENAS\Multimedia\MiniBench").Contains("nur einem"), "ein führendes \\ wird erkannt (Ordner TRUENAS auf dem Stick)");
        Ist(NasAblage.PfadFehler(@"TRUENAS\Multimedia").Length > 0, "relativer Pfad abgelehnt");
        Ist(NasAblage.PfadFehler("").Length > 0 && NasAblage.PfadFehler(null).Length > 0, "leer abgelehnt");
        Ist(NasAblage.Freigabe(@"\\TRUENAS\Multimedia\MiniBench\Daten") == @"\\TRUENAS\Multimedia", "Freigabe aus dem Pfad");
        Ist(NasAblage.Freigabe(@"I:\TRUENAS") == "", "Laufwerk hat keine Freigabe");
        Ist(!NasAblage.Erreichbar(@"\TRUENAS\Multimedia", 200), "ungültiger Pfad gilt nie als erreichbar");
        Ist(!NasAblage.OrdnerBereit(@"\TRUENAS\Multimedia", 200), "ungültiger Pfad wird nie angelegt");
        Ist(NasAblage.Vereinheitlichen(@" \\nas\daten\ ") == @"\\nas\daten" && NasAblage.Vereinheitlichen(@"Z:\") == @"Z:\" && NasAblage.Vereinheitlichen("Z:") == @"Z:\", "Pfade vereinheitlichen (Laufwerksstamm bleibt Z:\\)");
    }

    static void NasKonfiguration()
    {
        string d = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "mb_nas_" + System.Guid.NewGuid().ToString("N"));
        try
        {
            string p, b;
            Ist(!NasAblage.LeseKonfig(d, out p, out b), "ohne Netzwerk.json keine Konfiguration");
            Ist(NasAblage.AblageText(d) == "Datenordner: " + d, "ohne Netzlaufwerk nur der Datenordner");
            NasAblage.SchreibeKonfig(d, @"\\TRUENAS\Multimedia\MiniBench\", "leo");
            Ist(NasAblage.LeseKonfig(d, out p, out b) && p == @"\\TRUENAS\Multimedia\MiniBench" && b == "leo", "Pfad und Benutzer gelesen: " + p + " / " + b);
            string t = System.IO.File.ReadAllText(NasAblage.KonfigDatei(d));
            Ist(!t.ToLowerInvariant().Contains("kennwort") && !t.ToLowerInvariant().Contains("passw"), "kein Kennwort in Netzwerk.json");
            Ist(NasAblage.AblageText(d).Contains("noch nicht abgeglichen"), "noch nicht abgeglichen");
            System.IO.Directory.CreateDirectory(System.IO.Path.Combine(d, "Abgleich"));
            System.IO.File.WriteAllText(System.IO.Path.Combine(System.IO.Path.Combine(d, "Abgleich"), "Stand.json"), "{\"Format\":\"Minibench-Abgleich/1\",\"Zeit\":\"2026-10-09 14:05:33\",\"Dateien\":[]}");
            Ist(NasAblage.LetzterAbgleich(d) == "09.10.2026 14:05", "Zeit des letzten Abgleichs: " + NasAblage.LetzterAbgleich(d));
            Ist(NasAblage.AblageText(d).Contains("zuletzt abgeglichen 09.10.2026 14:05"), "Zeile nennt den letzten Abgleich");
            // Schlüssel früherer Versionen
            System.IO.File.WriteAllText(NasAblage.KonfigDatei(d), "{\"NetzwerkPfad\":\"\\\\\\\\nas\\\\daten\"}");
            Ist(NasAblage.LeseKonfig(d, out p, out b) && p == @"\\nas\daten" && b == "", "Schlüssel NetzwerkPfad: " + p);
            NasAblage.LoescheKonfig(d);
            Ist(!System.IO.File.Exists(NasAblage.KonfigDatei(d)), "Netzwerk.json gelöscht");
        }
        finally { try { System.IO.Directory.Delete(d, true); } catch { } }
    }

    static void NasErgebnis()
    {
        bool ok, erreichbar;
        string t = NasAblage.ErgebnisText("1|3|2|1|0|0|1", out ok, out erreichbar);
        Ist(ok && erreichbar && t == "3 zum Netzlaufwerk, 2 auf den Stick, 1 gelöscht, 0 Konflikte, 0 Fehler", t);
        t = NasAblage.ErgebnisText("0|0|0|0|0|0|0", out ok, out erreichbar);
        Ist(!ok && !erreichbar && t.Contains("nicht erreichbar"), t);
        t = NasAblage.ErgebnisText("0|0|0|0|0|0|1|1", out ok, out erreichbar);
        Ist(!ok && erreichbar && NasAblage.Angehalten("0|0|0|0|0|0|1|1") && t.Contains("angehalten"), "angehalten: " + t);
        Ist(!NasAblage.Angehalten("1|3|2|1|0|0|1|0") && !NasAblage.Angehalten("1|3|2|1|0|0|1"), "nicht angehalten");
        t = NasAblage.ErgebnisText("", out ok, out erreichbar);
        Ist(!ok && t.StartsWith("Keine"), t);
    }

    static void WartungVertragszeile()
    {
        string alt = "S|Wartung|Temp|Massnahme|Eingriff|nie|keins|3|0|1|Temporäre Dateien löschen";
        string neu = "S|Wartung|Temp|Massnahme|Eingriff|nie|keins|3|0|1|Temporäre Dateien löschen|Bereinigung und Speicherplatz";
        string[] xAlt = alt.Split('|');
        string[] xNeu = neu.Split('|');
        ContractStep cAlt = new ContractStep();
        cAlt.Module = xAlt[1]; cAlt.Key = xAlt[2]; cAlt.Typ = xAlt[3]; cAlt.Risiko = xAlt[4]; cAlt.Neustart = xAlt[5]; cAlt.Rueckgaengig = xAlt[6];
        int mAlt; int.TryParse(xAlt[7], out mAlt); cAlt.Minuten = mAlt; cAlt.Vorauswahl = xAlt[8] == "1"; cAlt.Ueblich = xAlt[9] == "1"; cAlt.Text = xAlt[10];
        if (xAlt.Length >= 12) cAlt.Gruppe = xAlt[11];
        Ist(cAlt.Key == "Temp" && cAlt.Gruppe == "", "alt: 11 Felder, Gruppe leer");

        ContractStep cNeu = new ContractStep();
        cNeu.Module = xNeu[1]; cNeu.Key = xNeu[2]; cNeu.Typ = xNeu[3]; cNeu.Risiko = xNeu[4]; cNeu.Neustart = xNeu[5]; cNeu.Rueckgaengig = xNeu[6];
        int mNeu; int.TryParse(xNeu[7], out mNeu); cNeu.Minuten = mNeu; cNeu.Vorauswahl = xNeu[8] == "1"; cNeu.Ueblich = xNeu[9] == "1"; cNeu.Text = xNeu[10];
        if (xNeu.Length >= 12) cNeu.Gruppe = xNeu[11];
        Ist(cNeu.Key == "Temp" && cNeu.Gruppe == "Bereinigung und Speicherplatz", "neu: 12 Felder, Gruppe gelesen");
    }

    static void DialogFarbschema()
    {
        bool altDark = UI.IsDark;
        try
        {
            UI.SetTheme(true);
            using (Form dlg = new Form())
            {
                FlowLayoutPanel p = new FlowLayoutPanel();
                Label l = new Label(); l.Text = "Beispiel";
                CheckBox cb = new CheckBox(); cb.Text = "Option";
                RadioButton rb = new RadioButton(); rb.Text = "Wahl";
                TextBox tb = new TextBox(); tb.Text = "Eingabe";
                ComboBox cmb = new ComboBox(); cmb.Items.Add("Auswahl");
                LinkLabel ll = new LinkLabel(); ll.Text = "Verweis";
                Button btn = new Button(); btn.Text = "Schaltfläche";
                p.Controls.Add(l);
                p.Controls.Add(cb);
                p.Controls.Add(rb);
                p.Controls.Add(tb);
                p.Controls.Add(cmb);
                p.Controls.Add(ll);
                p.Controls.Add(btn);
                dlg.Controls.Add(p);
                UI.ThemeDialog(dlg);

                Ist(dlg.BackColor == UI.Bg, "Dialog BackColor gesetzt");
                Ist(dlg.ForeColor != System.Drawing.Color.Black && dlg.ForeColor != System.Drawing.SystemColors.ControlText, "Dialog ForeColor nicht schwarz");

                System.Collections.Generic.Queue<System.Windows.Forms.Control> q = new System.Collections.Generic.Queue<System.Windows.Forms.Control>();
                q.Enqueue(dlg);
                while (q.Count > 0)
                {
                    System.Windows.Forms.Control c = q.Dequeue();
                    if (c != dlg)
                    {
                        Ist(c.ForeColor != System.Drawing.Color.Black &&
                            c.ForeColor != System.Drawing.SystemColors.ControlText &&
                            c.ForeColor.ToArgb() != System.Drawing.Color.Black.ToArgb(),
                            c.GetType().Name + " hat im dunklen Schema keine schwarze Schrift (ist: " + c.ForeColor + ")");
                    }
                    foreach (System.Windows.Forms.Control kind in c.Controls) q.Enqueue(kind);
                }
            }
        }
        finally
        {
            UI.SetTheme(altDark);
        }
    }

    // ab v3.64: Schrift auf Akzentflächen und gedämpfte Hinweise erreichen in beiden Farbschemata mindestens 4,5:1
    // (bis 3.63 weiße Schrift auf #4CC2FF im Dunkelschema, etwa 2:1)
    static void Kontrast()
    {
        bool alt = UI.IsDark;
        try
        {
            foreach (bool dark in new bool[] { false, true })
            {
                UI.SetTheme(dark);
                string n = dark ? "dunkel: " : "hell: ";
                Ist(UI.ContrastRatio(UI.OnAccent, UI.Accent) >= 4.5, n + "Schrift auf Primärknopf " + UI.ContrastRatio(UI.OnAccent, UI.Accent).ToString("0.0"));
                Ist(UI.ContrastRatio(UI.Muted, UI.Panel) >= 4.5, n + "Hinweis auf Seite");
                Ist(UI.ContrastRatio(UI.Text, UI.Panel) >= 7, n + "Text auf Seite");
                Color fg, bg;
                foreach (string l in new string[] { "info", "warn", "crit", "ok", "skip" }) { UI.BadgeColors(l, out fg, out bg); Ist(UI.ContrastRatio(fg, bg) >= 4.5, n + "Etikett " + l); }
                using (Button b = UI.Primary("x")) Ist(b is PrimaryButton && b.ForeColor == UI.OnAccent && b.BackColor == UI.Accent, n + "UI.Primary nutzt OnAccent");
            }
            Ist(System.Math.Abs(UI.ContrastRatio(Color.White, Color.Black) - 21) < 0.01, "Weiß auf Schwarz 21:1");
        }
        finally { UI.SetTheme(alt); }
    }

    static void StartknopfBeschriftung()
    {
        Ist(DiagGui.StartButtonText(new System.Collections.Generic.List<string>()) == "Ablauf wählen", "kein Modul");
        Ist(DiagGui.StartButtonText(null) == "Ablauf wählen", "null");
        Ist(DiagGui.StartButtonText(new System.Collections.Generic.List<string>(new string[] { "Diagnose" })) == "Diagnose starten", "ein Modul");
        Ist(DiagGui.StartButtonText(new System.Collections.Generic.List<string>(new string[] { "Diagnose", "Lasttest", "Wartung" })) == "3 Module starten", "drei Module");
    }

    static void Zeitangabe()
    {
        Ist(DiagGui.MinText(45) == "45 Min.", "45");
        Ist(DiagGui.MinText(80) == "1 Std. 20 Min.", "80");
        Ist(DiagGui.MinText(120) == "2 Std.", "120");
        Ist(DiagGui.MinText(0) == "1 Min.", "mindestens 1");
    }

    // Komponenten laufen gleichzeitig: Gesamtdauer = längste gewählte Dauer
    static void LasttestGesamtdauer()
    {
        Ist(DiagGui.LoadTotalMinutes(new bool[] { true, false, true, false }, new int[] { 2, 60, 15, 5 }) == 15, "CPU 2 und GPU 15 ergibt 15");
        Ist(DiagGui.LoadTotalMinutes(new bool[] { false, false, false, false }, new int[] { 2, 2, 2, 2 }) == 0, "nichts gewählt");
        Ist(DiagGui.LoadTotalMinutes(new bool[] { true }, new int[] { 240 }) == 240, "eine Komponente");
        Ist(DiagGui.LoadTotalMinutes(null, null) == 0, "ohne Listen");
    }

    // Alles, was zu einer abgewählten Komponente gehört, wird einheitlich deaktiviert (bis 3.63 blieb das Label hell)
    static void LasttestDeaktivierung()
    {
        using (Label l = new Label()) using (ComboBox c = new ComboBox())
        {
            Control[] teile = new Control[] { l, c };
            DiagGui.SetPartEnabled(teile, false);
            Ist(!c.Enabled && l.ForeColor == DiagGui.DisabledText(), "abgewählt: Liste aus, Beschriftung gedämpft");
            DiagGui.SetPartEnabled(teile, true);
            Ist(c.Enabled && l.ForeColor == UI.Text, "gewählt: Liste an, Beschriftung normal");
            DiagGui.SetPartEnabled(null, true);
        }
    }

    // Zusammenfassung vor dem Start nur bei Eingriffen, Neustarts oder ohne Wiederherstellungspunkt
    static void Startuebersicht()
    {
        System.Collections.Generic.List<StartPunkt> nurAendern = new System.Collections.Generic.List<StartPunkt>();
        nurAendern.Add(new StartPunkt("Wartung", "Zeit synchronisieren", "Aendern", "nie"));
        Ist(!StartUebersicht.Noetig(nurAendern, false), "nur Ändern ohne Neustart: kein Dialog");
        Ist(!StartUebersicht.Noetig(null, false), "nichts gewählt: kein Dialog");
        Ist(StartUebersicht.Noetig(nurAendern, true), "ohne Wiederherstellungspunkt: Dialog");
        System.Collections.Generic.List<StartPunkt> ein = new System.Collections.Generic.List<StartPunkt>(nurAendern);
        ein.Add(new StartPunkt("Wartung", "Systemdateien reparieren", "Eingriff", "nie"));
        Ist(StartUebersicht.Noetig(ein, false), "Eingriff: Dialog");
        System.Collections.Generic.List<StartPunkt> neu = new System.Collections.Generic.List<StartPunkt>();
        neu.Add(new StartPunkt("Optimierung", "Schnellstart aus", "Aendern", "moeglich"));
        Ist(StartUebersicht.Noetig(neu, false), "Neustart möglich: Dialog");
        string t = StartUebersicht.Text(new System.Collections.Generic.List<string>(new string[] { "Diagnose", "Wartung" }), "ca. 40 Min.", ein,
            new System.Collections.Generic.List<string>(new string[] { "Wartung|0" }), null);
        Ist(t.StartsWith("Ablauf: Diagnose  →  Wartung, ca. 40 Min."), "Ablauf und Dauer");
        Ist(t.Contains("1 Eingriff ohne automatisches Rückgängig") && t.Contains("Systemdateien reparieren (Wartung)"), "Eingriff genannt");
        Ist(t.Contains("Wartung: Es wird KEIN Wiederherstellungspunkt angelegt."), "Wiederherstellungspunkt");
        Ist(!t.Contains("Zeit synchronisieren"), "Ändern ohne Neustart steht nicht in der Liste");
        Ist(!System.Text.RegularExpressions.Regex.IsMatch(t, @"(^|\n)\s*[-–] "), "ohne Spiegelstriche");
    }

    static void WartungDetailtext()
    {
        string[] a = DiagGui.SplitDetail("Systemdateien reparieren (sfc /scannow, nach DISM)");
        Ist(a[0] == "Systemdateien reparieren" && a[1] == "sfc /scannow, nach DISM", "Titel und Befehl getrennt");
        string[] b = DiagGui.SplitDetail("Netzwerk zurücksetzen (DNS-Cache, Winsock, TCP/IP), Neustart nötig");
        Ist(b[0] == "Netzwerk zurücksetzen" && b[1] == "DNS-Cache, Winsock, TCP/IP", "Neustart steht als Etikett, nicht im Text");
        string[] c = DiagGui.SplitDetail("Windows-Zeit neu synchronisieren");
        Ist(c[0] == "Windows-Zeit neu synchronisieren" && c[1] == "", "ohne Klammer");
        string[] d = DiagGui.SplitDetail("Datenträgerbereinigung (cleanmgr mit allen Kategorien außer Downloads)");
        Ist(d[0] == "Datenträgerbereinigung" && d[1].StartsWith("cleanmgr"), "cleanmgr");
        Ist(DiagGui.SplitDetail(null)[0] == "", "null");
    }

    // Voreinstellungen vor v3.64 speichern die alten Texte der Auswahllisten
    static void VoreinstellungAltwerte()
    {
        Ist(DiagGui.SameChoice("2 Min.", "2 Minuten"), "2 Minuten");
        Ist(DiagGui.SameChoice("120 Min.", "120 Minuten"), "120 Minuten");
        Ist(DiagGui.SameChoice("Automatisch", "automatisch (TjMax, sonst 100 °C)"), "automatisch");
        Ist(!DiagGui.SameChoice("5 Min.", "2 Minuten"), "andere Zahl");
        Ist(!DiagGui.SameChoice("25 %", "25 Minuten"), "andere Einheit");
        Ist(!DiagGui.SameChoice("", "2 Minuten") && !DiagGui.SameChoice("2 Min.", null), "leer");
    }

    static void LaufwerkKurzname()
    {
        Ist(DiagGui.ShortDiskName("NVMe PC SN820 NVMe WD 4096GB") == "PC SN820 WD", DiagGui.ShortDiskName("NVMe PC SN820 NVMe WD 4096GB"));
        Ist(DiagGui.ShortDiskName("Samsung SSD 870 EVO 1TB") == "Samsung SSD 870 EVO", "Samsung");
        Ist(DiagGui.ShortDiskName("NVMe") == "NVMe", "nichts übrig: Originalname");
    }

    static void AblageKurzform()
    {
        Ist(DiagGui.AblageKurz("\\\\ulb.ad.hhu.de\\Home\\wad32muj\\Desktop\\LMB\\Minibench-Daten") == "Ablage: ...\\LMB\\Minibench-Daten", DiagGui.AblageKurz("\\\\ulb.ad.hhu.de\\Home\\wad32muj\\Desktop\\LMB\\Minibench-Daten"));
        Ist(DiagGui.AblageKurz("E:\\Minibench-Daten") == "Ablage: E:\\Minibench-Daten", "Stick");
        Ist(DiagGui.AblageKurz("") == "Ablage: kein Datenordner", "leer");
    }

    static void EtikettRisikostufe()
    {
        Ist(UI.RiskLevel("Aendern") == "info" && UI.RiskLevel("Eingriff") == "warn" && UI.RiskLevel("Zerstoerend") == "crit" && UI.RiskLevel("Lesen") == "ok", "Stufen");
        using (Badge b = new Badge("Eingriff", "warn"))
        {
            Ist(b.Visible && b.Width > b.Height && b.Level == "warn", "sichtbar und breiter als hoch");
            b.Text = ""; Ist(!b.Visible, "ohne Text unsichtbar");
            b.Text = "bereits aktiv"; Ist(b.Visible, "wieder sichtbar");
        }
    }

    static void Aufklappgruppe()
    {
        using (GroupHeader h = new GroupHeader("Prüfungen"))
        {
            int n = 0; h.Toggled += delegate { n++; };
            Ist(!h.Expanded, "Vorgabe zu");
            System.Reflection.MethodInfo flip = typeof(GroupHeader).GetMethod("Flip", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
            flip.Invoke(h, null);
            Ist(h.Expanded && n == 1, "Klick klappt auf und meldet Toggled");
            h.Expanded = false; Ist(!h.Expanded && n == 1, "Setzen von außen meldet nichts");
            h.CountText = "2 von 4 gewählt"; Ist(h.CountText == "2 von 4 gewählt", "Zähler");
        }
    }

    // Profile der Diagnose: Schätzung passt zur Fußleiste (vorher drei verschiedene Zeitangaben)
    static void DiagnoseProfile()
    {
        Ist(DiagGui.DiagMinutes(new bool[] { true, true, true, true, true, true, true, true }) == 14, "Vollständig 14 Min.");
        Ist(DiagGui.DiagMinutes(new bool[] { true, true, false, false, false, true, true, false }) == 6, "Schnell 6 Min.");
        Ist(DiagGui.DiagMinutes(null) == 0, "ohne Prüfungen Grundzeit");
    }

    // ab v3.65: Stufen in der Laufansicht wie die Etiketten der Einstellungsseiten
    static void EtikettSchreibweise()
    {
        Ist(DiagGui.BadgeCase("KRITISCH") == "Kritisch", "KRITISCH");
        Ist(DiagGui.BadgeCase("warnung") == "Warnung", "warnung");
        Ist(DiagGui.BadgeCase("OK") == "OK" && DiagGui.BadgeCase("ok") == "OK", "OK bleibt Kürzel");
        Ist(DiagGui.BadgeCase(null) == "" && DiagGui.BadgeCase("  ") == "", "leer");
    }

    // ab v3.65: Karten haben den Grund der Seite und lassen Platz für den Rahmen
    static void KarteRahmen()
    {
        using (CardPanel c = new CardPanel())
        {
            Ist(c.BackColor == UI.Panel, "Grund wie die Seite");
            Ist(c.Padding.Left >= UI.S(8) && c.Padding.Top >= UI.S(8), "Innenabstand für den Rahmen");
        }
    }

    // ab v3.72: Startseiten-Elemente (PillLabel, StartTaskCard, StartTaskRow) unterstützen transparente Hintergründe
    static void StartseitenElemente()
    {
        using (PillLabel pill = new PillLabel("Ryzen 5 5600"))
        {
            Ist(pill.Text == "Ryzen 5 5600" && pill.BackColor == Color.Transparent, "PillLabel transparent");
        }
        using (StartTaskCard card = new StartTaskCard("Test", "Beschreibung", "Fußzeile", "Badge", "ok", UI.IcoDiag, true))
        {
            Ist(card.Title == "Test" && card.Recommended, "StartTaskCard initialisiert");
            Ist(card.Width >= UI.S(200), "StartTaskCard vergrößert");
        }
        using (StartTaskRow row = new StartTaskRow("Test", "Untertitel", "Badge", "warn", UI.IcoSpeed))
        {
            Ist(row.Subtitle == "Untertitel" && row.BackColor == Color.Transparent, "StartTaskRow transparent");
        }
        using (KpiBox kpi = new KpiBox("Gesamt", "12.111"))
        {
            Ist(kpi.Title == "Gesamt" && kpi.Value == "12.111" && kpi.BackColor == Color.Transparent, "KpiBox transparent");
            Ist(kpi.Width >= UI.S(90), "KpiBox vergrößert");
        }
        Ist(UI.StartGruppenbreite >= 860, "StartGruppenbreite mindestens 860");
    }
}
