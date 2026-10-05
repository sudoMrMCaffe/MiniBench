using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

// Ein Messwert eines Sensors. Key ist über die Laufzeit stabil (bei LibreHardwareMonitor der Identifier).
public class SensorReading
{
    public string Key = "", Quelle = "", Gruppe = "", Geraet = "", Art = "", Name = "", Einheit = "";
    public double Wert = double.NaN;
    public double TjMax = double.NaN;
    public override string ToString() { return Gruppe + " | " + Geraet + " | " + Art + " | " + Name + " = " + Wert.ToString("0.###", CultureInfo.InvariantCulture) + " " + Einheit; }
}

// Zugriff auf LibreHardwareMonitorLib.dll ausschließlich über Reflexion: Das Skript lässt sich ohne die Bibliothek
// übersetzen, und geladen wird sie erst, wenn das Werkzeug-Manifest ihre Prüfsummen bestätigt hat.
public static class DiagSensors
{
    static Assembly lhm;
    static object computer;
    static string lhmDir = "";
    static PropertyInfo pHwList, pHwName, pHwType, pHwSensors, pHwSub, pSName, pSType, pSValue, pSId, pSParams, pParName, pParValue;
    static MethodInfo mUpdate;
    static bool resolverAdded;

    public static string LastError = "";
    public static string LibVersion = "";
    public static bool IsOpen { get { return computer != null; } }
    public static int UpdateErrors;

    static Assembly Resolve(object sender, ResolveEventArgs e)
    {
        // Abhängigkeiten der Bibliothek aus ihrem eigenen Ordner laden, unabhängig von der verlangten Version
        // (ersetzt die bindingRedirects aus LibreHardwareMonitor.exe.config)
        try
        {
            if (lhmDir.Length == 0) return null;
            string n = new AssemblyName(e.Name).Name;
            foreach (Assembly a in AppDomain.CurrentDomain.GetAssemblies())
            {
                try { if (a.GetName().Name == n && !a.IsDynamic && a.Location.StartsWith(lhmDir, StringComparison.OrdinalIgnoreCase)) return a; } catch { }
            }
            string p = Path.Combine(lhmDir, n + ".dll");
            if (File.Exists(p)) return Assembly.UnsafeLoadFrom(p);
        }
        catch { }
        return null;
    }

    static PropertyInfo Prop(Type t, string name)
    {
        PropertyInfo p = t.GetProperty(name);
        if (p == null) throw new MissingMemberException(t.FullName, name);
        return p;
    }

    // Bibliothek laden und Computer öffnen. Rückgabe false mit LastError, wenn etwas fehlt oder scheitert.
    public static bool Open(string dllPath, bool cpu, bool gpu, bool board, bool memory, bool storage, bool battery, bool controller)
    {
        LastError = "";
        if (computer != null) return true;
        try
        {
            lhmDir = Path.GetDirectoryName(Path.GetFullPath(dllPath));
            if (!resolverAdded) { AppDomain.CurrentDomain.AssemblyResolve += Resolve; resolverAdded = true; }
            // UnsafeLoadFrom: Dateien aus einem heruntergeladenen Archiv tragen die Internet-Zone; geprüft sind sie über SHA-256
            lhm = Assembly.UnsafeLoadFrom(dllPath);
            LibVersion = lhm.GetName().Version.ToString();
            Type tc = lhm.GetType("LibreHardwareMonitor.Hardware.Computer", true);
            Type th = lhm.GetType("LibreHardwareMonitor.Hardware.IHardware", true);
            Type ts = lhm.GetType("LibreHardwareMonitor.Hardware.ISensor", true);
            Type tp = lhm.GetType("LibreHardwareMonitor.Hardware.IParameter", true);
            pHwList = Prop(tc, "Hardware");
            pHwName = Prop(th, "Name"); pHwType = Prop(th, "HardwareType"); pHwSensors = Prop(th, "Sensors"); pHwSub = Prop(th, "SubHardware");
            mUpdate = th.GetMethod("Update");
            if (mUpdate == null) throw new MissingMethodException(th.FullName, "Update");
            pSName = Prop(ts, "Name"); pSType = Prop(ts, "SensorType"); pSValue = Prop(ts, "Value"); pSId = Prop(ts, "Identifier"); pSParams = Prop(ts, "Parameters");
            pParName = Prop(tp, "Name"); pParValue = Prop(tp, "Value");
            object c = Activator.CreateInstance(tc);
            Set(tc, c, "IsCpuEnabled", cpu); Set(tc, c, "IsGpuEnabled", gpu); Set(tc, c, "IsMotherboardEnabled", board);
            Set(tc, c, "IsMemoryEnabled", memory); Set(tc, c, "IsStorageEnabled", storage); Set(tc, c, "IsBatteryEnabled", battery);
            Set(tc, c, "IsControllerEnabled", controller); Set(tc, c, "IsNetworkEnabled", false); Set(tc, c, "IsPsuEnabled", controller);
            tc.GetMethod("Open", Type.EmptyTypes).Invoke(c, null);
            computer = c;
            return true;
        }
        catch (Exception ex)
        {
            Exception x = ex; while (x is TargetInvocationException && x.InnerException != null) x = x.InnerException;
            LastError = x.GetType().Name + ": " + x.Message;
            computer = null;
            return false;
        }
    }

    // Öffnen und Lesen mit Zeitlimit (ab v2.6): Im Praxistest blieb das Öffnen direkt nach der Installation von PawnIO
    // hängen und der Lasttest kam nie in Gang. Antwortet die Bibliothek nicht, gilt sie für diesen Lauf als ausgefallen
    // (Hung): keine weiteren Aufrufe, der Lauf arbeitet mit den Ersatzquellen weiter. Der hängende Aufruf bleibt in einem
    // Hintergrundthread und endet mit dem Prozess.
    public static volatile bool Hung;
    public static bool OpenTimed(string dllPath, bool cpu, bool gpu, bool board, bool memory, bool storage, bool battery, bool controller, int timeoutMs)
    {
        if (Hung) { LastError = "LibreHardwareMonitor hat in diesem Lauf schon einmal nicht geantwortet"; return false; }
        bool ok = false; string err = "";
        System.Threading.Thread t = new System.Threading.Thread(delegate()
        {
            try { ok = Open(dllPath, cpu, gpu, board, memory, storage, battery, controller); err = LastError; }
            catch (Exception ex) { ok = false; err = ex.GetType().Name + ": " + ex.Message; }
        });
        t.IsBackground = true; t.Name = "LHM Open"; t.Priority = System.Threading.ThreadPriority.Highest;
        t.Start();
        if (!t.Join(Math.Max(1000, timeoutMs)))
        {
            Hung = true;
            LastError = "LibreHardwareMonitor antwortet nicht (Öffnen dauerte länger als " + (Math.Max(1000, timeoutMs) / 1000) + " s)";
            return false;
        }
        LastError = err;
        return ok;
    }

    // Lesen mit Zeitlimit, ab v2.66 nachsichtig: Bis v2.65 galt die Bibliothek nach einer einzigen Abfrage über 5 s für
    // den ganzen Lauf als ausgefallen (Praxistest Ryzen 5 5600: nach 95 s CPU-Test keine Temperatur und keine GPU-Werte
    // mehr, auch nicht im Lasttest). Jetzt läuft eine verspätete Abfrage im Hintergrund weiter; bis sie fertig ist, liefert
    // ReadTimed die letzten Werte (höchstens StaleMaxMs = 10 s alt, LastStale = true; danach keine, damit die Abbruchschwelle
    // nicht mit alten Temperaturen arbeitet) und startet keine zweite Abfrage. Erst wenn eine Abfrage länger als
    // HangAfterMs = 30 s hängt, gilt die Bibliothek als ausgefallen. Der Lesethread läuft mit höchster
    // Priorität, damit die Lastthreads ihn nicht verdrängen.
    public static int HangAfterMs = 30000, StaleMaxMs = 10000;
    public static volatile bool LastStale;
    public static int SlowReads;
    public static double MaxReadMs;
    // Zähler für einen neuen Abschnitt (Lasttest) zurücksetzen
    public static void ResetStats() { SlowReads = 0; MaxReadMs = 0; }
    static readonly object readGate = new object();
    static System.Threading.Thread readThread;
    static SensorReading[] readResult;
    static DateTime readStarted, readDoneAt, lastGoodAt = DateTime.MinValue;
    static SensorReading[] lastGood = new SensorReading[0];
    static bool slowCounted;

    public static SensorReading[] ReadTimed(int timeoutMs)
    {
        lock (readGate)
        {
            LastStale = false;
            if (Hung || computer == null) return new SensorReading[0];
            bool fresh = false;
            for (int attempt = 0; attempt < 2; attempt++)
            {
                fresh = readThread == null;
                if (fresh)
                {
                    readResult = null; readStarted = DateTime.UtcNow; readDoneAt = DateTime.MinValue; slowCounted = false;
                    System.Threading.Thread t = new System.Threading.Thread(delegate() { SensorReading[] r; try { r = Read(); } catch { r = new SensorReading[0]; } readResult = r; readDoneAt = DateTime.UtcNow; });
                    t.IsBackground = true; t.Name = "LHM Read"; t.Priority = System.Threading.ThreadPriority.Highest;
                    try { t.Start(); } catch (Exception ex) { LastError = "LibreHardwareMonitor: Lesethread startet nicht (" + ex.Message + ")"; return new SensorReading[0]; }
                    readThread = t;
                }
                // eine schon verspätete Abfrage nur kurz abwarten, damit die Abfrageschleife nicht jedes Mal steht;
                // wartet die Abfrage auf die Datenträger (Momentaufnahme), zählt diese Zeit zum Zeitlimit dazu
                int wait = fresh ? Math.Max(500, timeoutMs) + Math.Max(0, StorageWaitMs) : Math.Min(250, Math.Max(500, timeoutMs));
                if (!readThread.Join(wait)) break;
                DateTime done = readDoneAt == DateTime.MinValue ? DateTime.UtcNow : readDoneAt;
                double ms = (done - readStarted).TotalMilliseconds;
                if (ms > MaxReadMs) MaxReadMs = ms;
                SensorReading[] res = readResult ?? new SensorReading[0];
                readThread = null;
                // eine verspätete Abfrage, die schon länger fertig ist, ist zu alt: neu lesen
                if (!fresh && (DateTime.UtcNow - done).TotalMilliseconds > StaleMaxMs) continue;
                lastGood = res; lastGoodAt = done;
                return res;
            }
            if (readThread == null) return lastGood;
            double pending = (DateTime.UtcNow - readStarted).TotalMilliseconds;
            if (pending > MaxReadMs) MaxReadMs = pending;
            if (!slowCounted) { SlowReads++; slowCounted = true; }
            if (pending >= HangAfterMs)
            {
                Hung = true;
                LastError = "LibreHardwareMonitor antwortet nicht (eine Abfrage hängt seit " + (pending / 1000.0).ToString("0", CultureInfo.InvariantCulture) + " s)";
                return new SensorReading[0];
            }
            LastStale = true;
            LastError = "LibreHardwareMonitor antwortet verzögert (Abfrage läuft seit " + (pending / 1000.0).ToString("0.#", CultureInfo.InvariantCulture) + " s)";
            if ((DateTime.UtcNow - lastGoodAt).TotalMilliseconds <= StaleMaxMs) return lastGood;
            return new SensorReading[0];
        }
    }

    static void Set(Type t, object o, string name, bool v)
    {
        PropertyInfo p = t.GetProperty(name);
        if (p != null && p.CanWrite) p.SetValue(o, v, null);
    }

    public static void Close()
    {
        if (computer == null) return;
        System.Threading.Thread r = readThread, d = storageThread;
        // Zustand der Abfragen vergessen; ein hängender Thread läuft im Hintergrund aus und endet mit dem Prozess
        readThread = null; storageThread = null; storageDone = false; storageAt = DateTime.MinValue; lastGood = new SensorReading[0]; lastGoodAt = DateTime.MinValue;
        if (Hung) { computer = null; return; }   // hängende Bibliothek nicht noch einmal aufrufen
        // laufende Abfragen kurz abwarten; hängen sie, nicht schließen (Close würde mit ihnen hängen)
        if ((r != null && r.IsAlive && !r.Join(10000)) || (d != null && d.IsAlive && !d.Join(20000))) { computer = null; return; }
        try { computer.GetType().GetMethod("Close", Type.EmptyTypes).Invoke(computer, null); } catch { }
        computer = null;
    }

    // Ob PawnIO in der laufenden Bibliothek geladen werden konnte (nur Auskunft, kein Einfluss auf das Lesen)
    public static string PawnIoState()
    {
        try
        {
            Type t = lhm == null ? null : lhm.GetType("LibreHardwareMonitor.PawnIo.PawnIo");
            if (t == null) return "";
            PropertyInfo inst = t.GetProperty("IsInstalled", BindingFlags.Public | BindingFlags.Static);
            PropertyInfo ver = t.GetProperty("Version", BindingFlags.Public | BindingFlags.Static);
            bool ok = inst != null && (bool)inst.GetValue(null, null);
            object v = ver == null ? null : ver.GetValue(null, null);
            return ok ? "installiert " + Convert.ToString(v, CultureInfo.InvariantCulture) : "nicht installiert";
        }
        catch { return ""; }
    }

    public static string Group(string hwType)
    {
        switch (hwType)
        {
            case "Cpu": return "CPU";
            case "GpuNvidia": case "GpuAmd": case "GpuIntel": return "GPU";
            case "Motherboard": case "SuperIO": case "EmbeddedController": return "Mainboard";
            case "Memory": return "RAM";
            case "Storage": return "Datenträger";
            case "Battery": return "Akku";
            case "Cooler": return "Kühlung";
            case "Psu": case "PowerMonitor": return "Netzteil";
            default: return "";
        }
    }

    public static string Kind(string sensorType, out string unit)
    {
        switch (sensorType)
        {
            case "Temperature": unit = "°C"; return "Temperatur";
            case "Clock": unit = "MHz"; return "Takt";
            case "Fan": unit = "U/min"; return "Lüfter";
            case "Voltage": unit = "V"; return "Spannung";
            case "Power": unit = "W"; return "Leistung";
            case "Load": unit = "%"; return "Auslastung";
            case "Control": unit = "%"; return "Lüftersteuerung";
            case "Current": unit = "A"; return "Strom";
            case "Level": unit = "%"; return "Füllstand";
            default: unit = ""; return "";
        }
    }

    // Datenträger getrennt (ab v2.66): Die SMART-Abfrage einer Festplatte im Ruhezustand wartet, bis sie angelaufen ist
    // (mehrere Sekunden). Datenträger werden deshalb höchstens alle StorageIntervalMs in einem eigenen Thread
    // aktualisiert; Read() liefert deren letzte Werte und wartet nur StorageWaitMs darauf (Momentaufnahme: 15 s, sonst 0).
    public static int StorageIntervalMs = 30000;
    public static int StorageWaitMs = 0;
    static System.Threading.Thread storageThread;
    static DateTime storageAt = DateTime.MinValue;
    static bool storageDone;

    static void UpdateStorage(List<object> disks)
    {
        if (disks.Count == 0) return;
        System.Threading.Thread t = storageThread;
        if ((t == null || !t.IsAlive) && (DateTime.UtcNow - storageAt).TotalMilliseconds >= StorageIntervalMs)
        {
            storageAt = DateTime.UtcNow;
            object[] list = disks.ToArray();
            t = new System.Threading.Thread(delegate()
            {
                foreach (object hw in list) { try { mUpdate.Invoke(hw, null); } catch { UpdateErrors++; } }
                storageDone = true;
            });
            t.IsBackground = true; t.Name = "LHM Datenträger";
            storageThread = t;
            t.Start();
        }
        if (StorageWaitMs > 0 && t != null && t.IsAlive) t.Join(StorageWaitMs);
    }

    // Alle Hardware aktualisieren und die Werte der unterstützten Sensorarten liefern
    public static SensorReading[] Read()
    {
        List<SensorReading> res = new List<SensorReading>();
        if (computer == null) return res.ToArray();
        IEnumerable list = null;
        try { list = pHwList.GetValue(computer, null) as IEnumerable; } catch (Exception ex) { LastError = ex.Message; }
        if (list == null) return res.ToArray();
        List<object> disks = new List<object>(), rest = new List<object>();
        foreach (object hw in list)
        {
            string type = "";
            try { type = Convert.ToString(pHwType.GetValue(hw, null)); } catch { }
            if (type == "Storage") disks.Add(hw); else rest.Add(hw);
        }
        UpdateStorage(disks);
        foreach (object hw in rest) ReadHardware(hw, null, res, 0, true);
        // Datenträgerwerte erst nach der ersten fertigen Aktualisierung (vorher stünden nur leere Werte da)
        if (storageDone) foreach (object hw in disks) ReadHardware(hw, null, res, 0, false);
        return res.ToArray();
    }

    static void ReadHardware(object hw, string parentName, List<SensorReading> res, int depth, bool update)
    {
        if (hw == null || depth > 3) return;
        string type = "", name = "";
        if (update) { try { mUpdate.Invoke(hw, null); } catch { UpdateErrors++; } }
        try { type = Convert.ToString(pHwType.GetValue(hw, null)); name = Convert.ToString(pHwName.GetValue(hw, null)); } catch { return; }
        string grp = Group(type);
        // Unterhardware (z. B. SuperIO-Chip am Mainboard) gehört zur Gruppe des übergeordneten Geräts, sofern sie selbst keine hat
        if (grp.Length == 0 && parentName != null) grp = "Mainboard";
        if (grp.Length > 0)
        {
            IEnumerable sensors = null;
            try { sensors = pHwSensors.GetValue(hw, null) as IEnumerable; } catch { }
            if (sensors != null)
                foreach (object s in sensors)
                {
                    try
                    {
                        string unit; string kind = Kind(Convert.ToString(pSType.GetValue(s, null)), out unit);
                        if (kind.Length == 0) continue;
                        object v = pSValue.GetValue(s, null);
                        SensorReading r = new SensorReading();
                        r.Key = Convert.ToString(pSId.GetValue(s, null));
                        r.Quelle = "LHM"; r.Gruppe = grp; r.Geraet = parentName != null ? parentName + " / " + name : name;
                        r.Art = kind; r.Name = Convert.ToString(pSName.GetValue(s, null)); r.Einheit = unit;
                        r.Wert = v == null ? double.NaN : Convert.ToDouble(v, CultureInfo.InvariantCulture);
                        if (kind == "Temperatur")
                        {
                            IEnumerable ps = pSParams.GetValue(s, null) as IEnumerable;
                            if (ps != null) foreach (object p in ps)
                                {
                                    string pn = Convert.ToString(pParName.GetValue(p, null));
                                    if (pn.StartsWith("TjMax", StringComparison.OrdinalIgnoreCase)) r.TjMax = Convert.ToDouble(pParValue.GetValue(p, null), CultureInfo.InvariantCulture);
                                }
                        }
                        res.Add(r);
                    }
                    catch { UpdateErrors++; }
                }
        }
        IEnumerable sub = null;
        try { sub = pHwSub.GetValue(hw, null) as IEnumerable; } catch { }
        if (sub != null) foreach (object h in sub) ReadHardware(h, name, res, depth + 1, update);
    }
}

// Prozessortakt wie im Task-Manager: Leistungszähler "Processor Information(_Total)", gelesen über PDH mit
// englischen Zählernamen (PdhAddEnglishCounter), damit es auf deutschem und englischem Windows gleich funktioniert.
// Takt = Processor Frequency (Nenntakt) x % Processor Performance / 100. Ratenzähler brauchen zwei Abfragen;
// Sample() hält zwischen zwei Abfragen mindestens 250 ms Abstand (auch direkt nach Open) und liefert das Mittel seit dem letzten Aufruf.
public static class DiagPdh
{
    [StructLayout(LayoutKind.Explicit)]
    struct FmtValue { [FieldOffset(0)] public uint CStatus; [FieldOffset(8)] public double Value; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct FmtItem { public IntPtr Name; public FmtValue Value; }

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern uint PdhOpenQuery(string source, IntPtr user, out IntPtr query);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern uint PdhAddEnglishCounter(IntPtr query, string path, IntPtr user, out IntPtr counter);
    [DllImport("pdh.dll")] static extern uint PdhCollectQueryData(IntPtr query);
    [DllImport("pdh.dll")] static extern uint PdhGetFormattedCounterValue(IntPtr counter, uint format, IntPtr type, out FmtValue value);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern uint PdhGetFormattedCounterArray(IntPtr counter, uint format, ref uint size, out uint count, IntPtr items);
    [DllImport("pdh.dll")] static extern uint PdhCloseQuery(IntPtr query);

    const uint FMT_DOUBLE = 0x00000200, FMT_NOCAP100 = 0x00008000, MORE_DATA = 0x800007D2;
    static IntPtr q = IntPtr.Zero, cPerf, cFreq, cTime, cMax, cPerfAll;
    static DateTime last = DateTime.MinValue;
    static object gate = new object();
    public static string LastError = "";
    public static bool Available { get { return q != IntPtr.Zero; } }

    public static bool Open()
    {
        lock (gate)
        {
            if (q != IntPtr.Zero) return true;
            try
            {
                IntPtr h;
                if (PdhOpenQuery(null, IntPtr.Zero, out h) != 0) { LastError = "PdhOpenQuery"; return false; }
                uint e = 0;
                e |= PdhAddEnglishCounter(h, @"\Processor Information(_Total)\% Processor Performance", IntPtr.Zero, out cPerf);
                e |= PdhAddEnglishCounter(h, @"\Processor Information(_Total)\Processor Frequency", IntPtr.Zero, out cFreq);
                if (e != 0) { PdhCloseQuery(h); LastError = "Zähler Processor Information fehlen"; return false; }
                if (PdhAddEnglishCounter(h, @"\Processor Information(_Total)\% Processor Time", IntPtr.Zero, out cTime) != 0) cTime = IntPtr.Zero;
                if (PdhAddEnglishCounter(h, @"\Processor Information(_Total)\% of Maximum Frequency", IntPtr.Zero, out cMax) != 0) cMax = IntPtr.Zero;
                if (PdhAddEnglishCounter(h, @"\Processor Information(*)\% Processor Performance", IntPtr.Zero, out cPerfAll) != 0) cPerfAll = IntPtr.Zero;
                PdhCollectQueryData(h);
                q = h; last = DateTime.UtcNow;
                return true;
            }
            catch (Exception ex) { LastError = ex.GetType().Name + ": " + ex.Message; q = IntPtr.Zero; return false; }
        }
    }

    static double Get(IntPtr c)
    {
        if (c == IntPtr.Zero) return double.NaN;
        FmtValue v;
        if (PdhGetFormattedCounterValue(c, FMT_DOUBLE | FMT_NOCAP100, IntPtr.Zero, out v) != 0 || (v.CStatus != 0 && v.CStatus != 1)) return double.NaN;
        return v.Value;
    }

    // höchster Wert über alle Kerne (Instanzen außer _Total)
    static double MaxInstance(IntPtr c)
    {
        if (c == IntPtr.Zero) return double.NaN;
        uint size = 0, count;
        uint r = PdhGetFormattedCounterArray(c, FMT_DOUBLE | FMT_NOCAP100, ref size, out count, IntPtr.Zero);
        if (r != MORE_DATA || size == 0) return double.NaN;
        IntPtr buf = Marshal.AllocHGlobal((int)size);
        try
        {
            if (PdhGetFormattedCounterArray(c, FMT_DOUBLE | FMT_NOCAP100, ref size, out count, buf) != 0) return double.NaN;
            double max = double.NaN;
            int step = Marshal.SizeOf(typeof(FmtItem));
            for (int i = 0; i < count; i++)
            {
                FmtItem it = (FmtItem)Marshal.PtrToStructure(new IntPtr(buf.ToInt64() + (long)i * step), typeof(FmtItem));
                string n = Marshal.PtrToStringUni(it.Name) ?? "";
                if (n.IndexOf("_Total", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                if (it.Value.CStatus != 0 && it.Value.CStatus != 1) continue;
                if (double.IsNaN(max) || it.Value.Value > max) max = it.Value.Value;
            }
            return max;
        }
        finally { Marshal.FreeHGlobal(buf); }
    }

    // Rückgabe: [0] Takt MHz wie Task-Manager, [1] % Processor Performance, [2] Nenntakt MHz, [3] CPU-Last %, [4] % of Maximum Frequency, [5] höchster Kern-% Performance
    public static double[] Sample()
    {
        double[] r = new double[] { double.NaN, double.NaN, double.NaN, double.NaN, double.NaN, double.NaN };
        lock (gate)
        {
            if (q == IntPtr.Zero && !Open()) return r;
            try
            {
                // Ratenzähler brauchen einen Abstand zwischen zwei Abfragen: nach langer Pause neu ansetzen,
                // direkt nach Open() oder bei schnellen Folgeaufrufen mindestens 250 ms warten
                double gap = (DateTime.UtcNow - last).TotalMilliseconds;
                if (gap > 15000) { PdhCollectQueryData(q); System.Threading.Thread.Sleep(250); }
                else if (gap < 250) System.Threading.Thread.Sleep((int)Math.Max(1, 250 - gap));
                if (PdhCollectQueryData(q) != 0) return r;
                last = DateTime.UtcNow;
                double perf = Get(cPerf), freq = Get(cFreq);
                r[1] = perf; r[2] = freq; r[3] = Get(cTime); r[4] = Get(cMax); r[5] = MaxInstance(cPerfAll);
                if (!double.IsNaN(perf) && !double.IsNaN(freq) && freq > 0) r[0] = Math.Round(freq * perf / 100.0);
            }
            catch (Exception ex) { LastError = ex.GetType().Name + ": " + ex.Message; }
        }
        return r;
    }

    public static void Close()
    {
        lock (gate) { if (q != IntPtr.Zero) { try { PdhCloseQuery(q); } catch { } q = IntPtr.Zero; } }
    }
}

// Ersatzquellen ohne LibreHardwareMonitor (ab v2.8). Im Praxistest vom 03.10. lief TORRENT (Radeon RX 6800) ohne
// LibreHardwareMonitor und hatte deshalb keine GPU-Werte. Windows selbst kennt einige davon:
//   Grafikkernel (D3DKMT, WDDM 2.4+): Temperatur, Lüfter und Speichertakt der Grafikkarte wie im Task-Manager, Takt der
//     ersten Engine; nur wenn der Treiber sie meldet. Abfragen mit falscher Größe weist der Kernel ab, es wird nichts geschrieben.
//   Leistungszähler "GPU Engine": Auslastung je Grafikeinheit (höchste Engine, Summe über alle Prozesse, wie im Task-Manager).
//   Leistungszähler "Energy Meter": Paketleistung der CPU (RAPL), wo die Firmware sie meldet (vor allem Intel).
// Alles nur lesend; jede Abfrage darf scheitern, dann fehlt der Wert.
public static class DiagGpuKmt
{
    [StructLayout(LayoutKind.Sequential)] struct EnumAdapters2 { public uint NumAdapters; public IntPtr pAdapters; }
    [StructLayout(LayoutKind.Sequential)] struct QueryAdapterInfo { public uint hAdapter; public int Type; public IntPtr pData; public uint Size; }
    [StructLayout(LayoutKind.Sequential)] struct CloseAdapter { public uint hAdapter; }
    [DllImport("gdi32.dll")] static extern int D3DKMTEnumAdapters2(ref EnumAdapters2 p);
    [DllImport("gdi32.dll")] static extern int D3DKMTQueryAdapterInfo(ref QueryAdapterInfo p);
    [DllImport("gdi32.dll")] static extern int D3DKMTCloseAdapter(ref CloseAdapter p);
    const int KMT_REGISTRYINFO = 8, KMT_ADAPTERTYPE = 15, KMT_NODEPERFDATA = 61, KMT_ADAPTERPERFDATA = 62;
    const int SIZE_ADAPTERINFO = 20, SIZE_REGISTRYINFO = 2080, SIZE_ADAPTERPERF = 64, SIZE_NODEPERF = 56;

    public class Adapter
    {
        public string Name = "", Luid = "";
        public double TempC = double.NaN, FanRpm = double.NaN, MemMhz = double.NaN, CoreMhz = double.NaN, Load = double.NaN;
    }
    public static string LastError = "";
    public static bool Disabled = false;

    static void Zero(IntPtr p, int n) { for (int i = 0; i < n; i += 4) Marshal.WriteInt32(p, i, 0); }
    static int Query(uint h, int type, IntPtr buf, int size) { QueryAdapterInfo q = new QueryAdapterInfo(); q.hAdapter = h; q.Type = type; q.pData = buf; q.Size = (uint)size; return D3DKMTQueryAdapterInfo(ref q); }

    public static List<Adapter> Read()
    {
        List<Adapter> res = new List<Adapter>();
        if (Disabled) return res;
        try
        {
            EnumAdapters2 e = new EnumAdapters2();
            if (D3DKMTEnumAdapters2(ref e) != 0 || e.NumAdapters == 0 || e.NumAdapters > 64) return res;
            int n = (int)e.NumAdapters;
            IntPtr arr = Marshal.AllocHGlobal(n * 32 + 64);
            IntPtr buf = Marshal.AllocHGlobal(4096);
            try
            {
                Zero(arr, n * 32 + 64);
                e.pAdapters = arr;
                if (D3DKMTEnumAdapters2(ref e) != 0) return res;
                n = Math.Min(n, (int)e.NumAdapters);
                for (int i = 0; i < n; i++)
                {
                    IntPtr p = new IntPtr(arr.ToInt64() + (long)i * SIZE_ADAPTERINFO);
                    uint h = (uint)Marshal.ReadInt32(p);
                    uint lo = (uint)Marshal.ReadInt32(p, 4); uint hi = (uint)Marshal.ReadInt32(p, 8);
                    Adapter a = new Adapter(); a.Luid = String.Format("luid_0x{0:X8}_0x{1:X8}", hi, lo);
                    bool soft = false;
                    try
                    {
                        Zero(buf, 4096);
                        if (Query(h, KMT_ADAPTERTYPE, buf, 4) == 0) soft = (Marshal.ReadInt32(buf) & 4) != 0;
                        Zero(buf, 4096);
                        if (Query(h, KMT_REGISTRYINFO, buf, SIZE_REGISTRYINFO) == 0) a.Name = (Marshal.PtrToStringUni(buf, 260) ?? "").Split('\0')[0].Trim();
                        Zero(buf, 4096);
                        if (Query(h, KMT_ADAPTERPERFDATA, buf, SIZE_ADAPTERPERF) == 0)
                        {
                            long mem = Marshal.ReadInt64(buf, 8); uint fan = (uint)Marshal.ReadInt32(buf, 48); uint temp = (uint)Marshal.ReadInt32(buf, 56);
                            if (temp >= 10 && temp <= 1500) a.TempC = temp / 10.0;
                            if (fan > 0 && fan < 20000) a.FanRpm = fan;
                            if (mem >= 100000000L && mem <= 40000000000L) a.MemMhz = Math.Round(mem / 1e6);
                        }
                        Zero(buf, 4096);
                        if (Query(h, KMT_NODEPERFDATA, buf, SIZE_NODEPERF) == 0)
                        {
                            long f = Marshal.ReadInt64(buf, 8);
                            if (f >= 100000000L && f <= 5000000000L) a.CoreMhz = Math.Round(f / 1e6);
                        }
                    }
                    catch { }
                    try { CloseAdapter c = new CloseAdapter(); c.hAdapter = h; D3DKMTCloseAdapter(ref c); } catch { }
                    if (!soft && a.Name.Length > 0 && a.Name.IndexOf("Basic Render", StringComparison.OrdinalIgnoreCase) < 0) res.Add(a);
                }
            }
            finally { Marshal.FreeHGlobal(buf); Marshal.FreeHGlobal(arr); }
        }
        catch (Exception ex) { LastError = ex.GetType().Name + ": " + ex.Message; if (ex is DllNotFoundException || ex is EntryPointNotFoundException) Disabled = true; }
        try
        {
            Dictionary<string, double> load = EngineLoad();
            foreach (Adapter a in res) { double v; if (load.TryGetValue(a.Luid.ToLowerInvariant(), out v)) a.Load = Math.Round(Math.Min(100.0, v), 1); }
        }
        catch { }
        return res;
    }

    // ---------- Leistungszähler mit Platzhalter (GPU Engine, Energy Meter) ----------
    [StructLayout(LayoutKind.Explicit)] struct FmtValue { [FieldOffset(0)] public uint CStatus; [FieldOffset(8)] public double Value; }
    [StructLayout(LayoutKind.Sequential)] struct FmtItem { public IntPtr Name; public FmtValue Value; }
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern uint PdhOpenQuery(string source, IntPtr user, out IntPtr query);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern uint PdhAddEnglishCounter(IntPtr query, string path, IntPtr user, out IntPtr counter);
    [DllImport("pdh.dll")] static extern uint PdhCollectQueryData(IntPtr query);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern uint PdhGetFormattedCounterArray(IntPtr counter, uint format, ref uint size, out uint count, IntPtr items);
    const uint FMT_DOUBLE = 0x00000200, FMT_NOCAP100 = 0x00008000, MORE_DATA = 0x800007D2;
    static IntPtr qEng = IntPtr.Zero, cEng = IntPtr.Zero, qPow = IntPtr.Zero, cPow = IntPtr.Zero;
    static bool engFailed, powFailed;
    static readonly object gate = new object();

    static Dictionary<string, double> ReadArray(IntPtr c)
    {
        Dictionary<string, double> r = new Dictionary<string, double>();
        uint size = 0, count;
        if (PdhGetFormattedCounterArray(c, FMT_DOUBLE | FMT_NOCAP100, ref size, out count, IntPtr.Zero) != MORE_DATA || size == 0) return r;
        IntPtr buf = Marshal.AllocHGlobal((int)size);
        try
        {
            if (PdhGetFormattedCounterArray(c, FMT_DOUBLE | FMT_NOCAP100, ref size, out count, buf) != 0) return r;
            int step = Marshal.SizeOf(typeof(FmtItem));
            for (int i = 0; i < count; i++)
            {
                FmtItem it = (FmtItem)Marshal.PtrToStructure(new IntPtr(buf.ToInt64() + (long)i * step), typeof(FmtItem));
                if (it.Value.CStatus != 0 && it.Value.CStatus != 1) continue;
                string name = Marshal.PtrToStringUni(it.Name) ?? "";
                double old; r[name] = r.TryGetValue(name, out old) ? old + it.Value.Value : it.Value.Value;
            }
        }
        finally { Marshal.FreeHGlobal(buf); }
        return r;
    }

    // Auslastung je Grafikeinheit (Schlüssel luid_0x..._0x... in Kleinbuchstaben): Summe je Engine über alle Prozesse, davon die höchste
    public static Dictionary<string, double> EngineLoad()
    {
        Dictionary<string, double> res = new Dictionary<string, double>();
        lock (gate)
        {
            if (engFailed) return res;
            if (qEng == IntPtr.Zero)
            {
                IntPtr q;
                if (PdhOpenQuery(null, IntPtr.Zero, out q) != 0) { engFailed = true; return res; }
                if (PdhAddEnglishCounter(q, @"\GPU Engine(*)\Utilization Percentage", IntPtr.Zero, out cEng) != 0) { engFailed = true; return res; }
                PdhCollectQueryData(q); qEng = q;
                System.Threading.Thread.Sleep(200);
            }
            if (PdhCollectQueryData(qEng) != 0) return res;
            Dictionary<string, double> perEngine = new Dictionary<string, double>();
            foreach (KeyValuePair<string, double> kv in ReadArray(cEng))
            {
                // pid_1234_luid_0x00000000_0x0000D1F4_phys_0_eng_3_engtype_3D
                string n = kv.Key.ToLowerInvariant();
                int l = n.IndexOf("luid_"), en = n.IndexOf("_eng_");
                if (l < 0 || en < 0) continue;
                int phys = n.IndexOf("_phys_", l);
                string luid = n.Substring(l, (phys > l ? phys : en) - l);
                int et = n.IndexOf("_engtype_", en);
                string key = luid + "|" + n.Substring(en, (et > en ? et : n.Length) - en);
                double old; perEngine[key] = perEngine.TryGetValue(key, out old) ? old + kv.Value : kv.Value;
            }
            foreach (KeyValuePair<string, double> kv in perEngine)
            {
                string luid = kv.Key.Substring(0, kv.Key.IndexOf('|'));
                double old; if (!res.TryGetValue(luid, out old) || kv.Value > old) res[luid] = kv.Value;
            }
        }
        return res;
    }

    // Paketleistung der CPU in Watt aus dem Energiezähler (RAPL_Package0_PKG), NaN ohne Zähler. Der Zähler meldet Milliwatt.
    public static double CpuPackageWatts()
    {
        lock (gate)
        {
            if (powFailed) return double.NaN;
            if (qPow == IntPtr.Zero)
            {
                IntPtr q;
                if (PdhOpenQuery(null, IntPtr.Zero, out q) != 0) { powFailed = true; return double.NaN; }
                if (PdhAddEnglishCounter(q, @"\Energy Meter(*)\Power", IntPtr.Zero, out cPow) != 0) { powFailed = true; return double.NaN; }
                PdhCollectQueryData(q); qPow = q;
                System.Threading.Thread.Sleep(200);
            }
            if (PdhCollectQueryData(qPow) != 0) return double.NaN;
            foreach (KeyValuePair<string, double> kv in ReadArray(cPow))
            {
                string n = kv.Key.ToUpperInvariant();
                if (n.IndexOf("PKG", StringComparison.Ordinal) < 0 || n.IndexOf("PACKAGE0", StringComparison.Ordinal) < 0) continue;
                double w = kv.Value / 1000.0;
                if (w > 0 && w < 1000) return Math.Round(w, 1);
            }
            return double.NaN;
        }
    }
}
