// Datenmodelle der grafischen Oberfläche

// Ein System aus der Vergleichsdatenbank (eine JSON-Datei je Lauf)
public class DbEntry
{
    public string Path = "", Name = "", Computer = "", Datum = "", Cpu = "", Gpu = "", Ram = "", Disk = "", Befunde = "", Module = "", Quelle = "", Ordner = "";
    public Dictionary<string, double> Werte = new Dictionary<string, double>();
    public bool HasBench { get { return Werte.Count > 0; } }
    public double Get(string k) { double v; return Werte.TryGetValue(k, out v) ? v : 0; }
    public string DisplayName { get { return !String.IsNullOrEmpty(Name) ? Name : Computer; } }
    public string Label { get { return DisplayName + "  ·  " + Datum + (Cpu.Length > 0 ? "  ·  " + Cpu : ""); } }

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
                    e.Cpu = S(h, "CPU"); e.Gpu = S(h, "GPU"); e.Ram = S(h, "RAM"); e.Disk = S(h, "Datentraeger");
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
    public string Module = "", Key = "", Typ = "", Risiko = "", Neustart = "", Rueckgaengig = "", Text = "";
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
