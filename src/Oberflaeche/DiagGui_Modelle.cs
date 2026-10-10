// Datenmodelle der grafischen Oberfläche

// Ein System aus der Vergleichsdatenbank (eine JSON-Datei je Lauf)
public class DbEntry
{
    public string Path = "", Name = "", Computer = "", Datum = "", Cpu = "", Gpu = "", Ram = "", Disk = "", Befunde = "", Module = "", Quelle = "", Ordner = "";
    public int Kerne = 0, Threads = 0;
    public Dictionary<string, double> Werte = new Dictionary<string, double>();
    public bool HasBench { get { return Werte.Count > 0; } }
    public double Get(string k) { double v; return Werte.TryGetValue(k, out v) ? v : 0; }
    public string DisplayName { get { return !String.IsNullOrEmpty(Name) ? Name : Computer; } }

    public static string CleanCpuName(string name)
    {
        if (String.IsNullOrEmpty(name)) return "";
        string s = System.Text.RegularExpressions.Regex.Replace(name, @"\s+", " ").Trim();
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\((R|TM|tm)\)", "");
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\s*@\s*[\d.]+\s*[GM]Hz.*$", "");
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\s*-\s*Qualcomm\s+Oryon\s+CPU.*$", "");
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\s*Qualcomm\s+Oryon\s+CPU.*$", "");
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\s*(-?\s*\d+-Core)?\s*(Processor|Prozessor).*$", "");
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\s*\d+-Core.*$", "");
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\s+CPU$", "");
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\b(Intel|AMD)\b\s*", "");
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\s+-\s+", " ").Trim();
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\s+", " ").Trim();
        return s;
    }

    public string CpuDisplay
    {
        get
        {
            string c = CleanCpuName(Cpu);
            if (c.Length == 0) return "";
            if (Kerne > 0 && Threads > 0) return c + " (" + Kerne + " Kerne, " + Threads + " Threads)";
            return c;
        }
    }

    public string Label { get { return DisplayName + "  ·  " + Datum + (CpuDisplay.Length > 0 ? "  ·  " + CpuDisplay : ""); } }

    public double OverallScore
    {
        get
        {
            double cpu = Get("CPU|MT");
            double ram = Get("RAM|Lesen");
            double gpu = Get("GPU|REND");
            if (gpu <= 0) gpu = Get("GPU|VMB") * 1.5;
            if (cpu <= 0 && ram <= 0 && gpu <= 0) return 0;
            double wSum = 0; double logSum = 0;
            if (cpu > 0) { logSum += 2.0 * Math.Log(cpu); wSum += 2.0; }
            if (gpu > 0) { logSum += 2.0 * Math.Log(gpu * 100.0); wSum += 2.0; }
            if (ram > 0) { logSum += 1.0 * Math.Log(ram * 500.0); wSum += 1.0; }
            return wSum > 0 ? Math.Round(Math.Exp(logSum / wSum), 0) : 0;
        }
    }

    static string S(Dictionary<string, object> d, string k)
    {
        object o; if (d == null || !d.TryGetValue(k, out o) || o == null) return "";
        return Convert.ToString(o, CultureInfo.InvariantCulture);
    }

    static int I(Dictionary<string, object> d, string k)
    {
        object o; if (d == null || !d.TryGetValue(k, out o) || o == null) return 0;
        int v; if (int.TryParse(Convert.ToString(o, CultureInfo.InvariantCulture), out v)) return v;
        return 0;
    }

    public static List<DbEntry> Load(string dir)
    {
        List<DbEntry> list = new List<DbEntry>();
        if (String.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return list;
        System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
        js.MaxJsonLength = int.MaxValue;
        foreach (string f in Directory.GetFiles(dir, "*.json"))
        {
            try
            {
                Dictionary<string, object> d = js.DeserializeObject(File.ReadAllText(f, Encoding.UTF8)) as Dictionary<string, object>;
                if (d == null) continue;
                DbEntry e = new DbEntry(); e.Path = f;
                e.Name = S(d, "Name"); e.Computer = S(d, "Computer"); e.Datum = S(d, "Datum"); e.Module = S(d, "Module"); e.Quelle = S(d, "Quelle"); e.Ordner = S(d, "Ordner");
                object hw; if (d.TryGetValue("Hardware", out hw))
                {
                    Dictionary<string, object> h = hw as Dictionary<string, object>;
                    e.Cpu = S(h, "CPU"); e.Kerne = I(h, "Kerne"); e.Threads = I(h, "Threads"); e.Gpu = S(h, "GPU"); e.Ram = S(h, "RAM"); e.Disk = S(h, "Datentraeger");
                }
                object w; if (d.TryGetValue("Werte", out w))
                {
                    Dictionary<string, object> wd = w as Dictionary<string, object>;
                    if (wd != null) foreach (KeyValuePair<string, object> kv in wd) { try { e.Werte[kv.Key] = Convert.ToDouble(kv.Value, CultureInfo.InvariantCulture); } catch { } }
                }
                object b; if (d.TryGetValue("Befunde", out b))
                {
                    Dictionary<string, object> bd = b as Dictionary<string, object>;
                    if (bd != null) e.Befunde = String.Format("{0} / {1} / {2}", S(bd, "Kritisch"), S(bd, "Warnungen"), S(bd, "Hinweise"));
                }
                if (e.Computer.Length == 0) e.Computer = System.IO.Path.GetFileNameWithoutExtension(f);
                list.Add(e);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("DbEntry.Load Fehler in " + f + ": " + ex.Message);
            }
        }
        list.Sort(delegate(DbEntry a, DbEntry c) { int r = String.Compare(a.DisplayName, c.DisplayName, StringComparison.OrdinalIgnoreCase); return r != 0 ? r : String.Compare(c.Datum, a.Datum, StringComparison.Ordinal); });
        return list;
    }
}

// Eintrag des Änderungsprotokolls (Minibench-Daten\Änderungen\<PC>\<Lauf>.json)
public class ChangeEntry
{
    public string FilePath = "", Computer = "", GeraetId = "", Zeit = "", Modul = "", Titel = "", Risiko = "", Art = "", Ziel = "", Vorher = "", Nachher = "", Status = "", Ergebnis = "", Gegenbefehl = "";
    public int Id;
    public bool Undoable { get { return Status == "aktiv" && String.Equals(Computer, Environment.MachineName, StringComparison.OrdinalIgnoreCase); } }

    static string S(Dictionary<string, object> d, string k)
    {
        object o; if (d == null || !d.TryGetValue(k, out o) || o == null) return "";
        return Convert.ToString(o, CultureInfo.InvariantCulture);
    }

    public static List<ChangeEntry> Load(string root)
    {
        List<ChangeEntry> list = new List<ChangeEntry>();
        if (String.IsNullOrEmpty(root) || !Directory.Exists(root)) return list;
        System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
        js.MaxJsonLength = int.MaxValue;
        foreach (string f in Directory.GetFiles(root, "*.json", SearchOption.AllDirectories))
        {
            try
            {
                Dictionary<string, object> d = js.DeserializeObject(File.ReadAllText(f, Encoding.UTF8)) as Dictionary<string, object>;
                if (d == null || S(d, "Format") != "Minibench-Aenderungen/1") continue;
                object eo; if (!d.TryGetValue("Eintraege", out eo)) continue;
                System.Collections.IEnumerable arr = eo as System.Collections.IEnumerable;
                if (arr == null || eo is string) continue;
                foreach (object x in arr)
                {
                    Dictionary<string, object> e = x as Dictionary<string, object>;
                    if (e == null) continue;
                    ChangeEntry c = new ChangeEntry(); c.FilePath = f; c.Computer = S(d, "Computer"); c.GeraetId = S(d, "GeraetId");
                    int id; int.TryParse(S(e, "Id"), out id); c.Id = id;
                    c.Zeit = S(e, "Zeit"); c.Modul = S(e, "Modul"); c.Titel = S(e, "Titel"); c.Risiko = S(e, "Risiko"); c.Art = S(e, "Art"); c.Ziel = S(e, "Ziel");
                    c.Vorher = S(e, "Vorher"); c.Nachher = S(e, "Nachher"); c.Status = S(e, "Status"); c.Ergebnis = S(e, "Ergebnis"); c.Gegenbefehl = S(e, "Gegenbefehl");
                    list.Add(c);
                }
            }
            catch { }
        }
        list.Sort(delegate(ChangeEntry a, ChangeEntry b) { int r = String.Compare(b.Zeit, a.Zeit, StringComparison.Ordinal); return r != 0 ? r : b.Id.CompareTo(a.Id); });
        return list;
    }
}

// Kurzfassung der Modulverträge aus dem Skript (Get-ContractGuiLines)
public class ContractStep
{
    public string Module = "", Key = "", Typ = "", Risiko = "", Neustart = "", Rueckgaengig = "", Text = "", Gruppe = "";
    public int Minuten; public bool Vorauswahl, Ueblich;
    public static string RiskLabel(string r)
    {
        switch (r) { case "Aendern": return "Ändern"; case "Zerstoerend": return "Zerstörend"; default: return r; }
    }
}

// Katalogeintrag der Optimierung (Get-OptGuiLines)
class OptItem
{
    public string Id = "", Kat = "", Risiko = "", Neustart = "", Vorlagen = "", Bedingung = "", Titel = "", Tip = "", Zustand = "", ZustandText = "";
    public bool Verwaltet; public int Minuten; public CheckBox Box;
}

// Netzlaufwerk als Spiegel der Nutzerdaten (ab v3.54). Die Oberfläche arbeitet immer im Datenordner auf dem Stick;
// Netzwerk.json dort nennt nur den NAS-Pfad (und optional den Benutzer). Abgeglichen wird über den Hilfsmodus -Abgleich
// (Kern\Ablage.ps1). Verbindungen mit Kennwort laufen über WNetAddConnection2 (nicht dauerhaft, Kennwort nicht in einer
// Befehlszeile) und werden beim Schließen des Programms wieder getrennt.
public static class NasAblage
{
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    class NETRESOURCE
    {
        public int dwScope = 0, dwType = 1, dwDisplayType = 0, dwUsage = 0;
        public string lpLocalName = null, lpRemoteName = null, lpComment = null, lpProvider = null;
    }
    [System.Runtime.InteropServices.DllImport("mpr.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern int WNetAddConnection2(NETRESOURCE res, string password, string user, int flags);
    [System.Runtime.InteropServices.DllImport("mpr.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern int WNetCancelConnection2(string name, int flags, bool force);

    static readonly List<string> verbunden = new List<string>();

    // leer, wenn gültig; sonst der Grund (gleiche Regeln wie Test-NasPfad in Kern\Ablage.ps1)
    public static string PfadFehler(string pfad)
    {
        string p = (pfad ?? "").Trim();
        if (p.Length == 0) return "kein Pfad angegeben";
        if (System.Text.RegularExpressions.Regex.IsMatch(p, @"^\\\\[^\\/:*?""<>|]+\\[^\\/:*?""<>|]+(\\.*)?$")) return "";
        if (System.Text.RegularExpressions.Regex.IsMatch(p, @"^\\[^\\]")) return p + " beginnt mit nur einem \\ und zeigte damit auf den Stick; gemeint ist \\" + p;
        if (System.Text.RegularExpressions.Regex.IsMatch(p, @"^[A-Za-z]:\\"))
        {
            try { if (new DriveInfo(p.Substring(0, 3)).DriveType == DriveType.Network) return ""; } catch { }
            return p + " ist kein Netzlaufwerk (lokales Laufwerk)";
        }
        return p + " ist kein UNC-Pfad (\\\\server\\freigabe\\Ordner)";
    }

    // \\server\freigabe aus einem UNC-Pfad (für die Verbindung), sonst leer
    public static string Freigabe(string pfad)
    {
        System.Text.RegularExpressions.Match m = System.Text.RegularExpressions.Regex.Match(pfad ?? "", @"^(\\\\[^\\]+\\[^\\]+)");
        return m.Success ? m.Groups[1].Value : "";
    }

    // ohne abschließendes \, außer beim Stamm eines Laufwerks (Z:\); wie Format-NasPfad in Kern\Ablage.ps1
    public static string Vereinheitlichen(string pfad)
    {
        string p = (pfad ?? "").Trim().TrimEnd('\\');
        if (p.Length == 2 && p[1] == ':') p += "\\";
        return p;
    }

    public static string KonfigDatei(string dataDir) { return String.IsNullOrEmpty(dataDir) ? "" : Path.Combine(dataDir, "Netzwerk.json"); }

    public static bool LeseKonfig(string dataDir, out string pfad, out string benutzer)
    {
        pfad = ""; benutzer = "";
        string f = KonfigDatei(dataDir);
        if (f.Length == 0 || !File.Exists(f)) return false;
        try
        {
            Dictionary<string, object> d = new System.Web.Script.Serialization.JavaScriptSerializer().DeserializeObject(File.ReadAllText(f, Encoding.UTF8)) as Dictionary<string, object>;
            if (d == null) return false;
            object o;
            if (d.TryGetValue("NasPfad", out o) && o != null) pfad = Convert.ToString(o);
            else if (d.TryGetValue("NetzwerkPfad", out o) && o != null) pfad = Convert.ToString(o);
            if (d.TryGetValue("Benutzer", out o) && o != null) benutzer = Convert.ToString(o);
        }
        catch { return false; }
        pfad = Vereinheitlichen(pfad);
        return pfad.Length > 0;
    }

    public static void SchreibeKonfig(string dataDir, string pfad, string benutzer)
    {
        Dictionary<string, object> d = new Dictionary<string, object>();
        d["NasPfad"] = Vereinheitlichen(pfad);
        if (!String.IsNullOrEmpty(benutzer)) d["Benutzer"] = benutzer.Trim();
        Directory.CreateDirectory(dataDir);
        File.WriteAllText(KonfigDatei(dataDir), new System.Web.Script.Serialization.JavaScriptSerializer().Serialize(d), new UTF8Encoding(true));
    }

    public static void LoescheKonfig(string dataDir)
    {
        string f = KonfigDatei(dataDir);
        if (f.Length > 0 && File.Exists(f)) File.Delete(f);
    }

    // Zeitpunkt des letzten Abgleichs aus Minibench-Daten\Abgleich\Stand.json ("yyyy-MM-dd HH:mm:ss"), sonst leer
    public static string LetzterAbgleich(string dataDir)
    {
        try
        {
            string f = Path.Combine(Path.Combine(dataDir, "Abgleich"), "Stand.json");
            if (!File.Exists(f)) return "";
            string t = File.ReadAllText(f, Encoding.UTF8);
            System.Text.RegularExpressions.Match m = System.Text.RegularExpressions.Regex.Match(t, @"""Zeit""\s*:\s*""(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})");
            return m.Success ? m.Groups[3].Value + "." + m.Groups[2].Value + "." + m.Groups[1].Value + " " + m.Groups[4].Value + ":" + m.Groups[5].Value : "";
        }
        catch { return ""; }
    }

    // Zeile für die Seite Vergleichsdatenbank
    public static string AblageText(string dataDir)
    {
        string t = "Datenordner: " + (String.IsNullOrEmpty(dataDir) ? "(nicht verfügbar)" : dataDir);
        string p, b;
        if (!String.IsNullOrEmpty(dataDir) && LeseKonfig(dataDir, out p, out b))
        {
            string z = LetzterAbgleich(dataDir);
            t += "   ·   Netzlaufwerk: " + p + (z.Length > 0 ? " (zuletzt abgeglichen " + z + ")" : " (noch nicht abgeglichen)");
        }
        return t;
    }

    // Ergebnis des Hilfsmodus -Abgleich: ok|zumNas|aufStick|gelöscht|Konflikte|Fehler|erreichbar -> kurzer Text
    public static string ErgebnisText(string res, out bool ok, out bool erreichbar)
    {
        ok = false; erreichbar = false;
        string[] x = (res ?? "").Split('|');
        if (x.Length < 7) return "Keine Rückmeldung vom Abgleich.";
        ok = x[0] == "1"; erreichbar = x[6] == "1";
        if (!erreichbar) return "Netzlaufwerk oder Ordner nicht erreichbar, nichts abgeglichen.";
        if (Angehalten(res)) return "Abgleich angehalten, nichts geändert.";
        return x[1] + " zum Netzlaufwerk, " + x[2] + " auf den Stick, " + x[3] + " gelöscht, " + x[4] + " Konflikte, " + x[5] + " Fehler";
    }

    // Schutz vor Massenlöschung hat angehalten (8. Feld des Ergebnisses)
    public static bool Angehalten(string res)
    {
        string[] x = (res ?? "").Split('|');
        return x.Length >= 8 && x[7] == "1";
    }

    // Ordner über dem NAS-Ordner: die Freigabe (\\server\freigabe) oder der Stamm des Netzlaufwerks
    static string Oberhalb(string pfad)
    {
        string f = Freigabe(pfad);
        if (f.Length > 0) return f;
        try { return Path.GetPathRoot(pfad) ?? ""; } catch { return ""; }
    }

    // Prüfung mit Zeitlimit in einem eigenen Thread (ein nicht erreichbarer Server blockiert sonst bis zu einer Minute);
    // die Oberfläche verarbeitet währenddessen Nachrichten, ist aber gesperrt (keine zweite Aktion)
    static bool MitFrist(Func<bool> pruefung, int timeoutMs)
    {
        bool ok = false;
        System.Threading.Thread t = new System.Threading.Thread(delegate() { try { ok = pruefung(); } catch { ok = false; } });
        t.IsBackground = true; t.Start();
        DateTime bis = DateTime.Now.AddMilliseconds(timeoutMs);
        while (t.IsAlive && DateTime.Now < bis) { Application.DoEvents(); t.Join(30); }
        return !t.IsAlive && ok;
    }

    // Ist der Server erreichbar (Freigabe vorhanden)? Ob der Ordner selbst fehlen darf, entscheidet der Abgleich.
    public static bool Erreichbar(string pfad, int timeoutMs)
    {
        if (PfadFehler(pfad).Length > 0) return false;
        string ober = Oberhalb(pfad);
        return MitFrist(delegate() { return Directory.Exists(pfad) || (ober.Length > 0 && Directory.Exists(ober)); }, timeoutMs);
    }

    // Beim Einrichten: Ordner vorhanden oder auf der erreichbaren Freigabe angelegt?
    public static bool OrdnerBereit(string pfad, int timeoutMs)
    {
        if (PfadFehler(pfad).Length > 0) return false;
        return MitFrist(delegate() {
            if (Directory.Exists(pfad)) return true;
            string eltern = Path.GetDirectoryName(pfad);
            if (String.IsNullOrEmpty(eltern) || !Directory.Exists(eltern)) return false;
            Directory.CreateDirectory(pfad);
            return true;
        }, timeoutMs);
    }

    // Verbindung mit Benutzer und Kennwort (nicht dauerhaft). Rückgabe: leer bei Erfolg, sonst der Fehler.
    public static string Verbinden(string pfad, string benutzer, string kennwort)
    {
        string share = Freigabe(pfad);
        if (share.Length == 0) return "Verbinden geht nur mit einem UNC-Pfad (\\\\server\\freigabe).";
        NETRESOURCE r = new NETRESOURCE(); r.lpRemoteName = share;
        int rc = WNetAddConnection2(r, String.IsNullOrEmpty(kennwort) ? null : kennwort, String.IsNullOrEmpty(benutzer) ? null : benutzer, 0);
        if (rc == 0) { lock (verbunden) if (!verbunden.Contains(share)) verbunden.Add(share); return ""; }
        if (rc == 1219) return "Zur Freigabe besteht schon eine Verbindung mit anderen Anmeldedaten (Fehler 1219).";
        if (rc == 86 || rc == 1326) return "Benutzername oder Kennwort falsch (Fehler " + rc + ").";
        return "Verbindung fehlgeschlagen (Fehler " + rc + ": " + new System.ComponentModel.Win32Exception(rc).Message + ").";
    }

    // beim Schließen: nur die selbst hergestellten Verbindungen trennen
    public static void AlleTrennen()
    {
        lock (verbunden)
        {
            foreach (string s in verbunden) { try { WNetCancelConnection2(s, 0, false); } catch { } }
            verbunden.Clear();
        }
    }
}
