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
        foreach (DbEntry e in l) Ist(e.Name.Length > 0 && e.Computer.Length > 0 && e.Cpu.Length > 0 && e.Werte.Count > 0, "Profil vollständig: " + e.Path);
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
}
