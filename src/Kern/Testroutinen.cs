using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using Microsoft.Win32.SafeHandles;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

// Standby-Sperre für die Dauer eines Laufs. Der Bildschirm darf ausgehen.
// SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED) verhindert den Leerlauf-Standby; auf Geräten mit
// Modern Standby hält zusätzlich eine Energieanforderung (PowerRequestSystemRequired und ExecutionRequired) den
// Arbeitsprozess am Laufen, wenn der Bildschirm abschaltet. Beides gilt nur, solange der Prozess lebt: Nach einem
// Absturz oder Abbruch gibt Windows die Sperre selbst wieder frei.
public static class DiagPower {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct REASON_CONTEXT { public uint Version; public uint Flags; [MarshalAs(UnmanagedType.LPWStr)] public string SimpleReasonString; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr PowerCreateRequest(ref REASON_CONTEXT context);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool PowerSetRequest(IntPtr h, int type);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool PowerClearRequest(IntPtr h, int type);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);

    const uint ES_CONTINUOUS = 0x80000000, ES_SYSTEM_REQUIRED = 0x00000001;
    const int SystemRequired = 1, ExecutionRequired = 3;
    static IntPtr request = IntPtr.Zero;
    static bool exec;
    public static bool Active;
    public static string State = "";

    public static bool Begin(string reason) {
        bool ok = SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED) != 0;
        string extra = "";
        try {
            if (request == IntPtr.Zero) {
                REASON_CONTEXT c = new REASON_CONTEXT(); c.Version = 0; c.Flags = 1; c.SimpleReasonString = reason;
                IntPtr h = PowerCreateRequest(ref c);
                if (h != IntPtr.Zero && h != new IntPtr(-1)) {
                    request = h;
                    if (PowerSetRequest(h, SystemRequired)) ok = true;
                    exec = PowerSetRequest(h, ExecutionRequired);
                    extra = exec ? ", Ausführungsanforderung für Modern Standby" : "";
                }
            }
        } catch { }
        Active = ok;
        State = ok ? "aktiv (Systemanforderung" + extra + ")" : "nicht gesetzt";
        return ok;
    }

    public static void End() {
        try {
            if (request != IntPtr.Zero) {
                PowerClearRequest(request, SystemRequired);
                if (exec) PowerClearRequest(request, ExecutionRequired);
                CloseHandle(request);
                request = IntPtr.Zero; exec = false;
            }
        } catch { }
        SetThreadExecutionState(ES_CONTINUOUS);
        Active = false;
    }
}

public static class DiagSys {
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMSTAT {
        public uint dwLength; public uint dwMemoryLoad;
        public ulong ullTotalPhys; public ulong ullAvailPhys; public ulong ullTotalPageFile; public ulong ullAvailPageFile;
        public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GlobalMemoryStatusEx(ref MEMSTAT m);
    public static uint MemoryLoad() {
        MEMSTAT m = new MEMSTAT();
        m.dwLength = (uint)Marshal.SizeOf(typeof(MEMSTAT));
        if (!GlobalMemoryStatusEx(ref m)) return 0;
        return m.dwMemoryLoad;
    }
}

public static class DiagRam {
    public static volatile int Percent;
    public static volatile string Phase = "";
    public static volatile bool Stop;
    public static long Errors;
    public static long BytesTested;
    // ab v2.65: höchstens so viele Threads (0 = alle) und eine Stufe unter normal, damit der RAM-Test im gemeinsamen
    // Lasttest dem Grafiktreiber und der CPU-Last nicht die Rechenzeit nimmt (Praxistest 02.10.: Bilder/s schwankten stark)
    public static int MaxThreads;
    public static bool LowPriority;

    public static Task<string> RunAsync(long targetBytes, int passes) {
        return Task.Factory.StartNew<string>(delegate() { return Run(targetBytes, passes); }, TaskCreationOptions.LongRunning);
    }

    const int Slice = 1 << 18;

    // Schreiben und Prüfen ab v2.67 ohne Aufruf in der Schleife (Muster direkt ausgeschrieben, siehe DiagCpu.WorkPart):
    // voll unterbrechbar für die Speicherbereinigung. Ein Fehlerfund ruft Report auf; der Zweig ist selten und nicht in
    // jedem Durchgang, die Schleife bleibt voll unterbrechbar.
    [MethodImpl(MethodImplOptions.NoInlining)]
    static void FillSlice(ulong[] b, int test, ulong baseAddr, int from, int to, ref ulong s) {
        ulong st = s;
        switch (test) {
            case 0: for (int i = from; i < to; i++) b[i] = 0UL; break;
            case 1: for (int i = from; i < to; i++) b[i] = 0xFFFFFFFFFFFFFFFFUL; break;
            case 2: for (int i = from; i < to; i++) b[i] = 0xAAAAAAAAAAAAAAAAUL; break;
            case 3: for (int i = from; i < to; i++) b[i] = 0x5555555555555555UL; break;
            case 4: for (int i = from; i < to; i++) b[i] = baseAddr + (ulong)i; break;
            case 5: for (int i = from; i < to; i++) b[i] = ~(baseAddr + (ulong)i); break;
            default: for (int i = from; i < to; i++) { st ^= st << 13; st ^= st >> 7; st ^= st << 17; b[i] = st; } break;
        }
        s = st;
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void VerifySlice(ulong[] b, int test, ulong baseAddr, int from, int to, ref ulong s, int bi, string phase, List<string> details) {
        ulong st = s;
        for (int i = from; i < to; i++) {
            ulong e;
            switch (test) {
                case 0: e = 0UL; break;
                case 1: e = 0xFFFFFFFFFFFFFFFFUL; break;
                case 2: e = 0xAAAAAAAAAAAAAAAAUL; break;
                case 3: e = 0x5555555555555555UL; break;
                case 4: e = baseAddr + (ulong)i; break;
                case 5: e = ~(baseAddr + (ulong)i); break;
                default: st ^= st << 13; st ^= st >> 7; st ^= st << 17; e = st; break;
            }
            if (b[i] != e) Report(phase, bi, i, e, b[i], details);
        }
        s = st;
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void Report(string phase, int bi, int i, ulong e, ulong v, List<string> details) {
        long n = Interlocked.Increment(ref Errors);
        if (n <= 25) {
            lock (details) {
                details.Add(String.Format("{0}, Block {1}, Index {2}: erwartet 0x{3:X16}, gelesen 0x{4:X16}", phase, bi, i, e, v));
            }
        }
    }

    public static string Run(long targetBytes, int passes) {
        Percent = 0; Errors = 0; BytesTested = 0; Phase = "Speicher wird reserviert";
        const int blockElems = 32 * 1024 * 1024;
        long blockBytes = (long)blockElems * 8L;
        List<ulong[]> blocks = new List<ulong[]>();
        List<string> details = new List<string>();
        DateTime start = DateTime.Now;
        try {
            while (BytesTested + blockBytes <= targetBytes) {
                blocks.Add(new ulong[blockElems]);
                BytesTested += blockBytes;
            }
        } catch (OutOfMemoryException) { }
        if (blocks.Count == 0) return "Es konnte kein Speicherblock reserviert werden.";
        string[] names = new string[] { "Nullen", "Einsen", "Schachbrett 0xAA", "Schachbrett 0x55", "Adresse in Adresse", "Adresse invertiert", "Zufallsmuster" };
        int total = passes * names.Length; int done = 0;
        for (int p = 1; p <= passes && !Stop; p++) {
            for (int t = 0; t < names.Length && !Stop; t++) {
                Phase = "Durchlauf " + p + "/" + passes + ": " + names[t];
                int test = t; int pass = p; string phase = Phase;
                ParallelOptions po = new ParallelOptions();
                if (MaxThreads > 0) po.MaxDegreeOfParallelism = MaxThreads;
                bool low = LowPriority;
                Parallel.For(0, blocks.Count, po, delegate(int bi) {
                    if (Stop) return;
                    ThreadPriority prio = Thread.CurrentThread.Priority;
                    if (low) { try { Thread.CurrentThread.Priority = ThreadPriority.BelowNormal; } catch { } }
                    try {
                    ulong[] b = blocks[bi];
                    ulong baseAddr = (ulong)bi * (ulong)blockElems;
                    ulong seed = (((ulong)pass * 0x9E3779B97F4A7C15UL) ^ ((ulong)(bi + 1) * 0xBF58476D1CE4E5B9UL)) | 1UL;
                    // ab v2.66 in Abschnitten zu 256K Werten (2 MB), damit die Speicherbereinigung nicht auf den ganzen
                    // 256-MB-Block warten muss (siehe DiagCpu.WorkPart)
                    ulong s = seed;
                    for (int i = 0; i < b.Length && !Stop; i += Slice) FillSlice(b, test, baseAddr, i, Math.Min(b.Length, i + Slice), ref s);
                    s = seed;
                    for (int i = 0; i < b.Length && !Stop; i += Slice) VerifySlice(b, test, baseAddr, i, Math.Min(b.Length, i + Slice), ref s, bi, phase, details);
                    } finally { if (low) { try { Thread.CurrentThread.Priority = prio; } catch { } } }
                });
                done++; Percent = done * 100 / total;
            }
        }
        TimeSpan dur = DateTime.Now - start;
        int blockCount = blocks.Count;
        blocks.Clear(); blocks = null;
        GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
        StringBuilder sb = new StringBuilder();
        sb.AppendLine(String.Format("Getesteter Speicher : {0:N0} MB ({1} Blöcke à 256 MB)", BytesTested / 1048576L, blockCount));
        sb.AppendLine(String.Format("Umfang             : {0} Durchläufe x {1} Muster, jeweils schreiben und prüfen", passes, names.Length));
        sb.AppendLine(String.Format("Dauer              : {0:hh\\:mm\\:ss}", dur));
        sb.AppendLine(String.Format("Fehler             : {0}", Interlocked.Read(ref Errors)));
        foreach (string d in details) sb.AppendLine("  " + d);
        Phase = "fertig";
        return sb.ToString();
    }
}

public static class DiagCpu {
    public static volatile bool Stop;
    public static long Iterations;
    public static long Errors;
    static ulong[] reference;

    // Ein Rechendurchlauf: 1,5 Mio. Schritte, Ergebnis wird gegen den Referenzwert geprüft.
    // Speicherbereinigung (GC): Sie hält alle Threads eines Prozesses an. Eine Schleife, die in jedem Durchgang eine
    // Funktion aufruft, ist dafür nur an bestimmten Stellen anhaltbar; steckt der Thread gerade in einer Funktion des
    // Laufzeitkerns (bis v2.66 Math.Sin), versucht .NET es im Windows-Zeittakt (15,6 ms) erneut. Mit 20 Threads kostete
    // jede GC so im Mittel 220 ms (ULB-PC10039, 03.10.2026: 33 GC-Läufe, 33 Unterbrechungen, zusammen 7,3 s in 34 s).
    // Ab v2.67: Die Schleife enthält keinen einzigen Aufruf mehr (Sinus als Polynom, Bitmuster über eine Union,
    // Math.Sqrt und Math.Abs übersetzt der JIT direkt in Prozessorbefehle). Solche Schleifen übersetzt der JIT als
    // "voll unterbrechbar": Die GC hält sie an jeder Stelle sofort an. Zusätzlich läuft die Last im Lasttest und im
    // CPU-Test in einem eigenen Prozess ohne Speicheranforderungen (DiagLoadHost), dort gibt es gar keine GC.
    public const int WorkSteps = 1500000, WorkChunk = 5000;

    [StructLayout(LayoutKind.Explicit)]
    struct Bits { [FieldOffset(0)] public double D; [FieldOffset(0)] public ulong U; }

    [MethodImpl(MethodImplOptions.NoInlining)]
    public static void WorkPart(ref double x, ref ulong h, int from, int to) {
        double xx = x; ulong hh = h; Bits bits = new Bits();
        const double TwoPi = 6.283185307179586, Pi = 3.141592653589793, InvTwoPi = 0.15915494309189535;
        for (int i = from; i <= to; i++) {
            // Sinus ohne Aufruf: auf -Pi bis Pi zurückführen, dann Taylorpolynom bis zur 11. Potenz (Fehler unter 0,001)
            // (int) statt (long): auch der 32-Bit-JIT wandelt das ohne Hilfsaufruf um (|xx| bleibt unter 2.000)
            double r = xx - TwoPi * (double)(int)(xx * InvTwoPi);
            if (r > Pi) r -= TwoPi; else if (r < -Pi) r += TwoPi;
            double r2 = r * r;
            double s = r * (1.0 - r2 * (1.0 / 6.0 - r2 * (1.0 / 120.0 - r2 * (1.0 / 5040.0 - r2 * (1.0 / 362880.0 - r2 * (1.0 / 39916800.0))))));
            xx = Math.Sqrt(Math.Abs(xx * 1.0000001 + i)) * 1.0001 + s;
            bits.D = xx;
            hh ^= bits.U;
            hh *= 0x100000001B3UL;
            hh = (hh << 7) | (hh >> 57);
        }
        x = xx; h = hh;
    }

    public static ulong Work(ulong seed) {
        double x = (double)(seed % 1000UL) + 1.5;
        ulong h = seed ^ 0xCBF29CE484222325UL;
        for (int i = 1; i <= WorkSteps; i += WorkChunk) WorkPart(ref x, ref h, i, Math.Min(WorkSteps, i + WorkChunk - 1));
        return h;
    }

    public static Task RunAsync(int seconds, int threads) {
        Iterations = 0; Errors = 0;
        reference = new ulong[16];
        for (int i = 0; i < 16; i++) reference[i] = Work((ulong)(i + 1));
        DateTime end = DateTime.UtcNow.AddSeconds(seconds);
        Task[] tasks = new Task[threads];
        for (int t = 0; t < threads; t++) {
            int tid = t;
            tasks[t] = Task.Factory.StartNew(delegate() {
                Thread.CurrentThread.Priority = ThreadPriority.BelowNormal;
                int k = tid % 16;
                while (!Stop && DateTime.UtcNow < end) {
                    if (Work((ulong)(k + 1)) != reference[k]) Interlocked.Increment(ref Errors);
                    Interlocked.Increment(ref Iterations);
                    k = (k + 1) % 16;
                }
            }, TaskCreationOptions.LongRunning);
        }
        return Task.Factory.ContinueWhenAll(tasks, delegate(Task[] ts) { });
    }
}

// Unterbrechungen messen (ab v2.66): ein Thread mit höchster Priorität schläft je 2 ms und misst, wie viel später er
// tatsächlich wieder läuft (gezählt ab 50 ms). Hält die Speicherbereinigung (GC) alle Threads des Prozesses an, steht auch er, und die Lücke
// zeigt die Dauer. So belegt der Bericht, ob die Last gleichmäßig lief, und zählt die GC-Läufe je Generation.
public static class DiagPause {
    static Thread th;
    static volatile int gen;             // jede Messung hat ihre eigene Nummer: ein alter Thread endet sicher
    static readonly object gate = new object();
    static long count, sumMs; static double maxMs, partMax; static int g0, g1, g2;
    public static int ThresholdMs = 50;   // über dem doppelten Windows-Zeitgebertakt (15,6 ms), damit Schlafgenauigkeit nicht zählt
    public static int LatencyBefore = -1;

    // Start setzt die Zähler immer neu; läuft noch eine Messung (Stop fehlte), endet sie.
    public static void Start() {
        lock (gate) {
            count = 0; sumMs = 0; maxMs = 0; partMax = 0;
            g0 = GC.CollectionCount(0); g1 = GC.CollectionCount(1); g2 = GC.CollectionCount(2);
            // während der Last keine blockierende Gen-2-Bereinigung (außer bei Speichermangel); den Ausgangswert nur
            // beim ersten Start merken, damit ein zweiter Start ohne Stop ihn nicht überschreibt
            try {
                if (LatencyBefore < 0) LatencyBefore = (int)System.Runtime.GCSettings.LatencyMode;
                System.Runtime.GCSettings.LatencyMode = System.Runtime.GCLatencyMode.SustainedLowLatency;
            } catch { }
            int my = ++gen;
            Thread t = new Thread(delegate() {
                Stopwatch sw = Stopwatch.StartNew(); double last = 0;
                while (gen == my) {
                    Thread.Sleep(2);
                    double now = sw.Elapsed.TotalMilliseconds, gap = now - last - 2.0; last = now;
                    if (gap >= ThresholdMs && gen == my) { lock (gate) { count++; sumMs += (long)gap; if (gap > maxMs) maxMs = gap; if (gap > partMax) partMax = gap; } }
                }
            });
            t.IsBackground = true; t.Name = "Unterbrechungsmessung"; t.Priority = ThreadPriority.Highest;
            t.Start();
            th = t;
        }
    }

    public static bool Running { get { lock (gate) { return th != null; } } }

    // [0] Zahl der Unterbrechungen ab ThresholdMs, [1] längste in ms, [2] Summe in ms, [3..5] GC-Läufe Gen 0, 1, 2 seit Start
    public static double[] Snapshot() {
        lock (gate) {
            return new double[] { count, maxMs, sumMs, GC.CollectionCount(0) - g0, GC.CollectionCount(1) - g1, GC.CollectionCount(2) - g2 };
        }
    }

    // Wie Snapshot, aber [1] = längste Unterbrechung seit dem letzten Aufruf (ab v2.8, Unterbrechungen je Benchmark-Abschnitt)
    public static double[] SnapshotPart() {
        lock (gate) {
            double[] r = new double[] { count, partMax, sumMs, GC.CollectionCount(0) - g0, GC.CollectionCount(1) - g1, GC.CollectionCount(2) - g2 };
            partMax = 0;
            return r;
        }
    }

    // Rückgabe null, wenn keine Messung lief
    public static double[] Stop() {
        double[] r = null;
        Thread t;
        lock (gate) {
            t = th; th = null;
            if (t != null) r = new double[] { count, maxMs, sumMs, GC.CollectionCount(0) - g0, GC.CollectionCount(1) - g1, GC.CollectionCount(2) - g2 };
            gen++;
        }
        if (t != null) { try { t.Join(500); } catch { } }
        if (LatencyBefore >= 0) { try { System.Runtime.GCSettings.LatencyMode = (System.Runtime.GCLatencyMode)LatencyBefore; } catch { } LatencyBefore = -1; }
        return r;
    }
}

// Last in einem eigenen Prozess (ab v2.67). Der Arbeitsprozess (PowerShell) fordert bei jeder Abfrage viel Speicher an
// und löst dadurch laufend Speicherbereinigungen aus, die alle seine Threads anhalten. Die CPU- und RAM-Last laufen
// deshalb in einem zweiten PowerShell-Prozess, der nur diese Bibliothek lädt und danach keinen Speicher mehr anfordert.
// Verständigung über Dateien in einem eigenen Ordner:
//   status.txt    eine Zeile, alle 250 ms neu geschrieben (ohne Speicheranforderung):
//                 L1;Folgenummer;fertig;Zähler;Fehler;Prozent;Unterbrechungen;längste;Summe;GC0;GC1;GC2;Prüfsumme
//                 Zähler = Rechendurchläufe (cpu) bzw. geprüfte Bytes (ram)
//   stop          vom Arbeitsprozess angelegt: Last beenden
//   ergebnis.txt  Ergebnistext des RAM-Tests (am Ende)
//   fehler.txt    Ausnahme im Lastprozess
// Endet der Arbeitsprozess, beendet sich der Lastprozess selbst (Prüfung alle 250 ms).
public static class DiagLoadHost {
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    const uint SYNCHRONIZE = 0x00100000;

    public static int Run(string mode, string dir, int seconds, int threads, long ramBytes, int ramMaxThreads, int lowPriority, int parentPid) {
        string statusPath = Path.Combine(dir, "status.txt"), stopPath = Path.Combine(dir, "stop");
        try {
            IntPtr parent = IntPtr.Zero;
            bool parentGone = false;
            // Arbeitsprozess schon beendet (OpenProcess liefert nichts): sofort aufhören; ohne kernel32 (Testumgebung) nur Zeitlimit
            try { if (parentPid > 0) { parent = OpenProcess(SYNCHRONIZE, false, parentPid); parentGone = parent == IntPtr.Zero; } } catch { parent = IntPtr.Zero; }
            if (parentGone) return 3;
            DiagPause.Start();
            Task task; Task<string> ramTask = null;
            bool ram = mode == "ram";
            if (ram) {
                DiagRam.Stop = false; DiagRam.LowPriority = lowPriority != 0; DiagRam.MaxThreads = ramMaxThreads;
                ramTask = DiagRam.RunAsync(ramBytes, 100000); task = ramTask;
            } else {
                DiagCpu.Stop = false;
                task = DiagCpu.RunAsync(seconds, threads);
            }
            DateTime limit = DateTime.UtcNow.AddSeconds(Math.Max(60, seconds) + 120);
            byte[] buf = new byte[160]; long seq = 0;
            using (FileStream fs = new FileStream(statusPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete)) {
                while (!task.Wait(250)) {
                    double[] p = DiagPause.Snapshot();
                    WriteStatus(fs, buf, ++seq, false, ram, p);
                    bool stop = File.Exists(stopPath) || DateTime.UtcNow > limit;
                    if (!stop && parent != IntPtr.Zero) { try { stop = WaitForSingleObject(parent, 0) == 0; } catch { } }
                    if (stop) { if (ram) DiagRam.Stop = true; else DiagCpu.Stop = true; }
                }
                double[] fin = DiagPause.Stop() ?? DiagPause.Snapshot();
                if (ramTask != null) { try { File.WriteAllText(Path.Combine(dir, "ergebnis.txt"), ramTask.Result, new UTF8Encoding(false)); } catch { } }
                WriteStatus(fs, buf, ++seq, true, ram, fin);
            }
            return 0;
        } catch (Exception ex) {
            try { File.WriteAllText(Path.Combine(dir, "fehler.txt"), ex.ToString(), new UTF8Encoding(false)); } catch { }
            return 1;
        }
    }

    static void Put(byte[] b, ref int p, long v, ref long sum) {
        sum = (sum + (v < 0 ? -v : v)) % 1000000007L;
        if (v < 0) { b[p++] = (byte)'-'; v = -v; }
        int start = p;
        do { b[p++] = (byte)('0' + (int)(v % 10)); v /= 10; } while (v > 0);
        for (int i = start, j = p - 1; i < j; i++, j--) { byte t = b[i]; b[i] = b[j]; b[j] = t; }
        b[p++] = (byte)';';
    }

    static void WriteStatus(FileStream fs, byte[] b, long seq, bool done, bool ram, double[] p) {
        int pos = 0; long sum = 0;
        b[pos++] = (byte)'L'; b[pos++] = (byte)'1'; b[pos++] = (byte)';';
        Put(b, ref pos, seq, ref sum);
        Put(b, ref pos, done ? 1 : 0, ref sum);
        Put(b, ref pos, ram ? Interlocked.Read(ref DiagRam.BytesTested) : Interlocked.Read(ref DiagCpu.Iterations), ref sum);
        Put(b, ref pos, ram ? Interlocked.Read(ref DiagRam.Errors) : Interlocked.Read(ref DiagCpu.Errors), ref sum);
        Put(b, ref pos, ram ? DiagRam.Percent : 0, ref sum);
        for (int k = 0; k < 6; k++) Put(b, ref pos, p != null && p.Length > k ? (long)p[k] : 0, ref sum);
        long chk = sum;
        Put(b, ref pos, chk, ref sum);
        while (pos < b.Length - 1) b[pos++] = (byte)' ';
        b[pos++] = (byte)'\n';
        fs.Position = 0;
        fs.Write(b, 0, pos);
        fs.Flush();
    }

    // Statuszeile lesen. Rückgabe null, wenn sie fehlt oder unvollständig ist (Prüfsumme).
    // Felder: [0] Folgenummer, [1] fertig, [2] Zähler, [3] Fehler, [4] Prozent, [5..10] Unterbrechungen und GC
    public static long[] ParseStatus(string line) {
        if (line == null) return null;
        string[] f = line.Trim().Split(';');
        if (f.Length < 14 || f[0] != "L1") return null;
        long[] v = new long[11]; long sum = 0;
        for (int i = 0; i < 11; i++) {
            long x;
            if (!long.TryParse(f[i + 1], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out x)) return null;
            v[i] = x; sum = (sum + (x < 0 ? -x : x)) % 1000000007L;
        }
        long chk;
        if (!long.TryParse(f[12], NumberStyles.None, CultureInfo.InvariantCulture, out chk) || chk != sum) return null;
        return v;
    }
}

// Eine CPU- oder RAM-Last aus Sicht des Arbeitsprozesses: im eigenen Prozess (External) oder, wenn der nicht startet,
// wie bis v2.66 im Arbeitsprozess. Refresh() holt den Stand, Stop() beendet, Wait() wartet auf das Ende.
public class LoadJob {
    public string Mode = "", Dir = "", Note = "";
    public bool External, Done;
    public long Count, Errors;
    public int Percent;
    public double[] Pause;          // Unterbrechungen im Lastprozess (wie DiagPause.Stop), nur bei External
    public string Result = "";
    public int ExitCode = -1;
    Process proc; Task task; Task<string> ramTask;
    readonly StringBuilder errText = new StringBuilder();
    DateTime startedAt; bool seen, stopRequested;
    int seconds, threads, ramMax, low; long ramBytes;
    public int StartTimeoutMs = 30000;

    public static LoadJob Start(string mode, string host, string dll, string dir, int seconds, int threads, long ramBytes, int ramMaxThreads, bool lowPriority) {
        LoadJob j = new LoadJob();
        j.Mode = mode == "ram" ? "ram" : "cpu"; j.Dir = dir ?? ""; j.seconds = seconds; j.threads = threads; j.ramBytes = ramBytes; j.ramMax = ramMaxThreads; j.low = lowPriority ? 1 : 0;
        j.startedAt = DateTime.UtcNow;
        if (!String.IsNullOrEmpty(host) && !String.IsNullOrEmpty(dll) && File.Exists(dll) && j.Dir.Length > 0) {
            try {
                Directory.CreateDirectory(j.Dir);
                foreach (string n in new string[] { "status.txt", "stop", "ergebnis.txt", "fehler.txt" }) { try { File.Delete(Path.Combine(j.Dir, n)); } catch { } }
                // kleines Startskript statt -EncodedCommand (Virenscanner und Regeln zur Angriffsflächenreduzierung
                // werten kodierte Befehle als verdächtig); gestartet wie der Arbeitsprozess selbst mit -File
                string ps1 = Path.Combine(j.Dir, "Lastprozess.ps1");
                File.WriteAllText(ps1,
                    "param([string]$Dll, [string]$Mode, [string]$Dir, [int]$Seconds, [int]$Threads, [long]$RamBytes, [int]$RamMax, [int]$Low, [int]$ParentPid)\r\n" +
                    "# Leos Minibench: CPU- oder RAM-Last in einem eigenen Prozess, endet von selbst\r\n" +
                    "$ErrorActionPreference = 'Stop'\r\n" +
                    "try { Add-Type -Path $Dll } catch { [IO.File]::WriteAllText((Join-Path $Dir 'fehler.txt'), $_.Exception.Message); exit 2 }\r\n" +
                    "exit [DiagLoadHost]::Run($Mode, $Dir, $Seconds, $Threads, $RamBytes, $RamMax, $Low, $ParentPid)\r\n", Encoding.ASCII);
                string args = String.Format(CultureInfo.InvariantCulture,
                    "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{0}\" -Dll \"{1}\" -Mode {2} -Dir \"{3}\" -Seconds {4} -Threads {5} -RamBytes {6} -RamMax {7} -Low {8} -ParentPid {9}",
                    ps1, dll, j.Mode, j.Dir.TrimEnd('\\', '/'), seconds, threads, ramBytes, ramMaxThreads, j.low, Process.GetCurrentProcess().Id);
                ProcessStartInfo psi = new ProcessStartInfo(host, args);
                psi.UseShellExecute = false; psi.CreateNoWindow = true;
                // Ausgaben des Lastprozesses abfangen: Die Standardausgabe des Arbeitsprozesses ist der Ereigniskanal zur
                // Oberfläche, dorthin darf nichts durchgereicht werden. Fehlertext für die Meldung behalten (gekürzt).
                psi.RedirectStandardOutput = true; psi.RedirectStandardError = true;
                Process pr = new Process(); pr.StartInfo = psi;
                LoadJob jj = j;
                DataReceivedEventHandler h = delegate(object sender, DataReceivedEventArgs e) {
                    if (e.Data == null) return;
                    lock (jj.errText) { if (jj.errText.Length < 2000) jj.errText.AppendLine(e.Data); }
                };
                pr.OutputDataReceived += h; pr.ErrorDataReceived += h;
                if (pr.Start()) { pr.BeginOutputReadLine(); pr.BeginErrorReadLine(); j.proc = pr; j.External = true; }
            } catch (Exception ex) { j.Note = "eigener Lastprozess nicht möglich (" + ex.Message + ")"; j.External = false; }
        }
        if (!j.External) j.StartInternal();
        return j;
    }

    void StartInternal() {
        External = false;
        if (Mode == "ram") {
            DiagRam.Stop = false; DiagRam.LowPriority = low != 0; DiagRam.MaxThreads = ramMax;
            ramTask = DiagRam.RunAsync(ramBytes, 100000); task = ramTask;
        } else {
            DiagCpu.Stop = false;
            task = DiagCpu.RunAsync(seconds, threads);
        }
    }

    void FallBack(string why) {
        try { if (proc != null && !proc.HasExited) proc.Kill(); } catch { }
        Note = why + ", Last läuft im Arbeitsprozess";
        StartInternal();
    }

    string ReadText(string name) {
        try {
            using (FileStream fs = new FileStream(Path.Combine(Dir, name), FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (StreamReader r = new StreamReader(fs, Encoding.UTF8)) return r.ReadToEnd();
        } catch { return null; }
    }

    public void Refresh() {
        if (Done) return;
        if (!External) {
            if (Mode == "ram") { Count = Interlocked.Read(ref DiagRam.BytesTested); Errors = Interlocked.Read(ref DiagRam.Errors); Percent = DiagRam.Percent; }
            else { Count = Interlocked.Read(ref DiagCpu.Iterations); Errors = Interlocked.Read(ref DiagCpu.Errors); }
            if (task != null && task.IsCompleted) {
                Done = true;
                if (ramTask != null) { try { Result = ramTask.Result ?? ""; } catch (Exception ex) { Result = ex.Message; } }
            }
            return;
        }
        long[] v = DiagLoadHost.ParseStatus(ReadText("status.txt"));
        if (v != null) {
            seen = true;
            Count = v[2]; Errors = v[3]; Percent = (int)v[4];
            if (v[1] == 1) {
                Pause = new double[] { v[5], v[6], v[7], v[8], v[9], v[10] };
                Result = ReadText("ergebnis.txt") ?? "";
                Done = true;
                try { if (proc.WaitForExit(2000)) ExitCode = proc.ExitCode; } catch { }
                return;
            }
        }
        bool exited = false;
        try { exited = proc.HasExited; } catch { exited = true; }
        if (exited) {
            try { ExitCode = proc.ExitCode; } catch { }
            // nach dem Ende noch einmal lesen: die letzte Zeile kann zwischen Lesen und Prozessende geschrieben worden sein
            long[] w = DiagLoadHost.ParseStatus(ReadText("status.txt"));
            if (w != null) {
                seen = true; Count = w[2]; Errors = w[3]; Percent = (int)w[4];
                if (w[1] == 1) { Pause = new double[] { w[5], w[6], w[7], w[8], w[9], w[10] }; Result = ReadText("ergebnis.txt") ?? ""; Done = true; return; }
            }
            string err = ReadText("fehler.txt");
            if (String.IsNullOrEmpty(err)) { lock (errText) err = Clean(errText.ToString()); }
            string why = "Lastprozess endete ohne Ergebnis (Exitcode " + ExitCode + (String.IsNullOrEmpty(err) ? "" : ", " + FirstLine(err)) + ")";
            // nach Stop() keine Last mehr im Arbeitsprozess nachstarten
            if (!seen && !stopRequested) FallBack(why);
            else { Note = why; Done = true; }
        } else if (!seen && (DateTime.UtcNow - startedAt).TotalMilliseconds > StartTimeoutMs) {
            string why = "Lastprozess meldete sich nicht innerhalb von " + (StartTimeoutMs / 1000) + " s";
            if (stopRequested) { Kill(); Note = why; Done = true; }
            else FallBack(why);
        }
    }

    // PowerShell schreibt Fehler eines Kindprozesses als CLIXML; nur den Text behalten
    static string Clean(string s) {
        if (String.IsNullOrEmpty(s)) return "";
        int a = s.IndexOf("<S S=\"Error\">");
        if (a >= 0) { int b = s.IndexOf("</S>", a); s = s.Substring(a + 13, (b > a ? b : s.Length) - a - 13); }
        s = System.Text.RegularExpressions.Regex.Replace(s, "_x001B_\\[[0-9;]*m|\u001B\\[[0-9;]*m|_x000[AD]_", " ");
        s = System.Text.RegularExpressions.Regex.Replace(s.Replace("#< CLIXML", ""), "\\s+", " ").Trim();
        return s.Length > 300 ? s.Substring(0, 300) : s;
    }

    static string FirstLine(string s) { s = s.Trim(); int n = s.IndexOfAny(new char[] { '\r', '\n' }); return n > 0 ? s.Substring(0, n) : s; }

    public void Stop() {
        stopRequested = true;
        if (External) { try { File.WriteAllText(Path.Combine(Dir, "stop"), "1"); } catch { } }
        else if (Mode == "ram") DiagRam.Stop = true; else DiagCpu.Stop = true;
    }

    // Wartet bis zum Ende; ein Lastprozess, der dann noch läuft, wird beendet
    public bool Wait(int ms) {
        Stopwatch sw = Stopwatch.StartNew();
        while (true) {
            Refresh();
            if (Done) return true;
            if (sw.ElapsedMilliseconds >= ms) break;
            Thread.Sleep(100);
        }
        Kill();
        return false;
    }

    public void Kill() {
        if (!External) { if (Mode == "ram") DiagRam.Stop = true; else DiagCpu.Stop = true; return; }
        try { if (proc != null && !proc.HasExited) { proc.Kill(); Note = (Note.Length > 0 ? Note + "; " : "") + "Lastprozess beendet"; } } catch { }
    }

    public bool Running { get { Refresh(); return !Done; } }

    // Ordner des Lastprozesses entfernen (nach dem Ende; Rückstandskontrolle)
    public void Cleanup() {
        if (Dir.Length == 0 || !Directory.Exists(Dir)) return;
        try { if (proc != null && !proc.HasExited) proc.WaitForExit(3000); } catch { }
        for (int i = 0; i < 5; i++) {
            try { Directory.Delete(Dir, true); return; } catch { Thread.Sleep(200); }
        }
    }
}

public static class DiagBench {
    public static volatile string Phase = "";
    public static volatile int Percent;

    static ulong Kernel(ulong s) {
        double x = (double)(s % 97UL) + 1.25; ulong h = s | 1UL;
        for (int i = 0; i < 20000; i++) {
            h ^= h << 13; h ^= h >> 7; h ^= h << 17;
            h = h * 0x9E3779B97F4A7C15UL + (ulong)i;
            x = x * 0.9999997 + Math.Sqrt(x + (double)(h & 1023UL));
            if ((h & 7UL) == 3UL) x = x * 0.5 + 1.0;
        }
        return h ^ (ulong)BitConverter.DoubleToInt64Bits(x);
    }

    public static ulong Sink;

    public static Task<double> CpuAsync(int threads, int millis) { return Task.Factory.StartNew<double>(delegate() { return CpuUnitsPerSec(threads, millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> MemReadAsync(int threads, long bytes, int millis) { return Task.Factory.StartNew<double>(delegate() { return MemReadGBs(threads, bytes, millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> MemWriteAsync(int threads, long bytes, int millis) { return Task.Factory.StartNew<double>(delegate() { return MemWriteGBs(threads, bytes, millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> AesAsync(int millis) { return Task.Factory.StartNew<double>(delegate() { return AesMBs(millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> ShaAsync(int millis) { return Task.Factory.StartNew<double>(delegate() { return ShaMBs(millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> DeflateAsync(int threads, int millis) { return Task.Factory.StartNew<double>(delegate() { return DeflateMBs(threads, millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> MemCopyAsync(int threads, long bytes, int millis) { return Task.Factory.StartNew<double>(delegate() { return MemCopyGBs(threads, bytes, millis); }, TaskCreationOptions.LongRunning); }
    public static Task<double> LatencyAsync(long bytes, int millis) { return Task.Factory.StartNew<double>(delegate() { return MemLatencyNs(bytes, millis); }, TaskCreationOptions.LongRunning); }

    // Rechenwerk: Einheiten pro Sekunde über alle Threads
    public static double CpuUnitsPerSec(int threads, int millis) {
        long total = 0;
        Thread[] ts = new Thread[threads];
        Stopwatch wall = Stopwatch.StartNew();
        for (int t = 0; t < threads; t++) {
            int tid = t;
            ts[t] = new Thread(delegate() {
                Stopwatch sw = Stopwatch.StartNew(); long n = 0; ulong acc = 0; ulong seed = (ulong)(tid * 7919 + 1);
                while (sw.ElapsedMilliseconds < millis) { acc ^= Kernel(seed + (ulong)n); n++; }
                Interlocked.Add(ref total, n); Sink ^= acc;
            });
            ts[t].IsBackground = true; ts[t].Start();
        }
        foreach (Thread th in ts) th.Join();
        wall.Stop();
        return total / wall.Elapsed.TotalSeconds;
    }

    // Speicherbandbreite Lesen in GB/s (10^9)
    public static double MemReadGBs(int threads, long bytes, int millis) {
        int per = (int)Math.Min(int.MaxValue / 8, bytes / 8 / threads);
        per -= per % 8;
        ulong[][] arr = new ulong[threads][];
        for (int t = 0; t < threads; t++) { arr[t] = new ulong[per]; for (int i = 0; i < per; i += 512) arr[t][i] = (ulong)i; }
        long totalBytes = 0;
        Thread[] ts = new Thread[threads];
        using (Barrier bar = new Barrier(threads + 1)) {
            for (int t = 0; t < threads; t++) {
                int tid = t;
                ts[t] = new Thread(delegate() {
                    ulong[] a = arr[tid]; ulong s0 = 0, s1 = 0, s2 = 0, s3 = 0; long passes = 0;
                    bar.SignalAndWait();
                    Stopwatch sw = Stopwatch.StartNew();
                    while (sw.ElapsedMilliseconds < millis) {
                        for (int i = 0; i < a.Length - 3; i += 4) { s0 += a[i]; s1 += a[i + 1]; s2 += a[i + 2]; s3 += a[i + 3]; }
                        passes++;
                    }
                    Interlocked.Add(ref totalBytes, passes * (long)a.Length * 8L);
                    Sink ^= s0 ^ s1 ^ s2 ^ s3;
                });
                ts[t].IsBackground = true; ts[t].Start();
            }
            bar.SignalAndWait();
            Stopwatch wall = Stopwatch.StartNew();
            foreach (Thread th in ts) th.Join();
            wall.Stop();
            return totalBytes / wall.Elapsed.TotalSeconds / 1e9;
        }
    }

    // Speicherbandbreite Schreiben in GB/s
    public static double MemWriteGBs(int threads, long bytes, int millis) {
        int per = (int)Math.Min(int.MaxValue / 8, bytes / 8 / threads);
        ulong[][] arr = new ulong[threads][];
        for (int t = 0; t < threads; t++) { arr[t] = new ulong[per]; for (int i = 0; i < per; i += 512) arr[t][i] = 1UL; }
        long totalBytes = 0;
        Thread[] ts = new Thread[threads];
        using (Barrier bar = new Barrier(threads + 1)) {
            for (int t = 0; t < threads; t++) {
                int tid = t;
                ts[t] = new Thread(delegate() {
                    ulong[] a = arr[tid]; long passes = 0; ulong v = 1;
                    bar.SignalAndWait();
                    Stopwatch sw = Stopwatch.StartNew();
                    while (sw.ElapsedMilliseconds < millis) { for (int i = 0; i < a.Length; i++) a[i] = v; v++; passes++; }
                    Interlocked.Add(ref totalBytes, passes * (long)a.Length * 8L);
                });
                ts[t].IsBackground = true; ts[t].Start();
            }
            bar.SignalAndWait();
            Stopwatch wall = Stopwatch.StartNew();
            foreach (Thread th in ts) th.Join();
            wall.Stop();
            return totalBytes / wall.Elapsed.TotalSeconds / 1e9;
        }
    }

    // AES-256-CBC verschlüsseln, ein Thread (nutzt AES-NI über die Windows-Kryptografie)
    // Kryptografie-Klassen per Reflexion laden, damit weder System.Core referenziert noch veraltete Typen genutzt werden
    static object CreateCrypto(string[] typeNames) {
        foreach (string n in typeNames) {
            try {
                Type t = Type.GetType(n, false);
                if (t == null) continue;
                System.Reflection.MethodInfo mi = t.GetMethod("Create", Type.EmptyTypes);
                object o = (mi != null && mi.IsStatic && t.IsAbstract) ? mi.Invoke(null, null) : Activator.CreateInstance(t);
                if (o != null) return o;
            } catch { }
        }
        return null;
    }

    public static double AesMBs(int millis) {
        SymmetricAlgorithm aes = CreateCrypto(new string[] {
            "System.Security.Cryptography.Aes, System.Core, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089",
            "System.Security.Cryptography.Aes, System.Security.Cryptography",
            "System.Security.Cryptography.Aes, System.Security.Cryptography.Algorithms" }) as SymmetricAlgorithm;
        if (aes == null) return 0;
        byte[] data = new byte[1 << 20]; new Random(1).NextBytes(data); byte[] outb = new byte[data.Length];
        using (aes) {
            aes.KeySize = 256; aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.None; aes.GenerateKey(); aes.GenerateIV();
            using (ICryptoTransform enc = aes.CreateEncryptor()) {
                long bytes = 0; Stopwatch sw = Stopwatch.StartNew();
                while (sw.ElapsedMilliseconds < millis) { enc.TransformBlock(data, 0, data.Length, outb, 0); bytes += data.Length; }
                sw.Stop(); return bytes / sw.Elapsed.TotalSeconds / 1e6;
            }
        }
    }

    // SHA-256 hashen, ein Thread (SHA256Cng nutzt SHA-Befehlssatzerweiterungen, falls vorhanden)
    public static double ShaMBs(int millis) {
        byte[] data = new byte[1 << 20]; new Random(2).NextBytes(data);
        HashAlgorithm h = CreateCrypto(new string[] {
            "System.Security.Cryptography.SHA256Cng, System.Core, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089",
            "System.Security.Cryptography.SHA256, System.Security.Cryptography",
            "System.Security.Cryptography.SHA256, System.Security.Cryptography.Algorithms" }) as HashAlgorithm;
        if (h == null) h = SHA256.Create();
        using (h) {
            long bytes = 0; Stopwatch sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < millis) { h.TransformBlock(data, 0, data.Length, null, 0); bytes += data.Length; }
            h.TransformFinalBlock(data, 0, 0);
            sw.Stop(); return bytes / sw.Elapsed.TotalSeconds / 1e6;
        }
    }

    static byte[] TextData(int size, int seed) {
        string[] words = { "Diagnose", "Speicher", "Prozessor", "Laufwerk", "Grafik", "Bericht", "Leistung", "Windows", "Netzwerk", "Treiber", "und", "der", "die", "das", "mit", "0123456789" };
        Random r = new Random(seed); StringBuilder sb = new StringBuilder(size + 32);
        while (sb.Length < size) { sb.Append(words[r.Next(words.Length)]); sb.Append(r.Next(10) == 0 ? '\n' : ' '); if (r.Next(8) == 0) sb.Append(r.Next(100000)); }
        byte[] b = Encoding.UTF8.GetBytes(sb.ToString()); Array.Resize(ref b, size); return b;
    }

    // Deflate-Kompression auf allen Threads, Durchsatz der Eingangsdaten
    public static double DeflateMBs(int threads, int millis) {
        byte[] data = TextData(4 << 20, 3);
        long total = 0;
        Thread[] ts = new Thread[threads];
        Stopwatch wall = Stopwatch.StartNew();
        for (int t = 0; t < threads; t++) {
            ts[t] = new Thread(delegate() {
                long n = 0; Stopwatch sw = Stopwatch.StartNew();
                while (sw.ElapsedMilliseconds < millis) {
                    using (MemoryStream ms = new MemoryStream(data.Length / 2))
                    using (DeflateStream ds = new DeflateStream(ms, CompressionLevel.Optimal, true)) { ds.Write(data, 0, data.Length); }
                    n += data.Length;
                }
                Interlocked.Add(ref total, n);
            });
            ts[t].IsBackground = true; ts[t].Start();
        }
        foreach (Thread th in ts) th.Join();
        wall.Stop();
        return total / wall.Elapsed.TotalSeconds / 1e6;
    }

    // Speicher kopieren (memcpy) auf allen Threads, GB/s kopierte Daten
    public static double MemCopyGBs(int threads, long bytes, int millis) {
        int per = (int)Math.Min(int.MaxValue / 2, bytes / 2 / threads);
        byte[][] src = new byte[threads][]; byte[][] dst = new byte[threads][];
        for (int t = 0; t < threads; t++) { src[t] = new byte[per]; dst[t] = new byte[per]; for (int i = 0; i < per; i += 4096) { src[t][i] = 1; dst[t][i] = 1; } }
        long totalBytes = 0;
        Thread[] ts = new Thread[threads];
        using (Barrier bar = new Barrier(threads + 1)) {
            for (int t = 0; t < threads; t++) {
                int tid = t;
                ts[t] = new Thread(delegate() {
                    long passes = 0; bar.SignalAndWait(); Stopwatch sw = Stopwatch.StartNew();
                    // in Stücken zu 1 MB: ein Kopieraufruf ist für die Speicherbereinigung nicht anhaltbar (siehe DiagCpu.WorkPart)
                    byte[] s = src[tid], d = dst[tid];
                    while (sw.ElapsedMilliseconds < millis) { for (int o = 0; o < per; o += 1 << 20) Buffer.BlockCopy(s, o, d, o, Math.Min(1 << 20, per - o)); passes++; }
                    Interlocked.Add(ref totalBytes, passes * (long)per);
                });
                ts[t].IsBackground = true; ts[t].Start();
            }
            bar.SignalAndWait();
            Stopwatch wall = Stopwatch.StartNew();
            foreach (Thread th in ts) th.Join();
            wall.Stop();
            return totalBytes / wall.Elapsed.TotalSeconds / 1e9;
        }
    }

    // Speicherlatenz in ns (zufällige Zeigerverfolgung über Cachezeilen)
    public static double MemLatencyNs(long bytes, int millis) {
        int nodes = (int)Math.Min(int.MaxValue / 8, bytes / 64);
        int[] next = new int[nodes * 16];
        int[] perm = new int[nodes];
        for (int i = 0; i < nodes; i++) perm[i] = i;
        Random rnd = new Random(12345);
        for (int i = nodes - 1; i > 0; i--) { int j = rnd.Next(i); int tmp = perm[i]; perm[i] = perm[j]; perm[j] = tmp; }
        for (int i = 0; i < nodes; i++) next[perm[i] * 16] = perm[(i + 1) % nodes] * 16;
        int p = 0; long steps = 0;
        Stopwatch sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < millis) { for (int k = 0; k < 100000; k++) p = next[p]; steps += 100000; }
        sw.Stop();
        Sink ^= (ulong)p;
        return sw.Elapsed.TotalMilliseconds * 1e6 / steps;
    }
}

public class DiskResult {
    public double SeqReadMBs, SeqWriteMBs, Rnd4kQ1Iops, Rnd4kT8Iops, Rnd4kWriteQ1Iops;
    public long TestBytes;
    public string Error = "";
}

public static class DiagDisk {
    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000, SHARE_RW = 3;
    const uint CREATE_ALWAYS = 2, OPEN_EXISTING = 3, NO_BUFFERING = 0x20000000, ATTR_TEMPORARY = 0x100;
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool WriteFile(SafeFileHandle h, IntPtr buf, uint n, out uint done, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadFile(SafeFileHandle h, IntPtr buf, uint n, out uint done, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetFilePointerEx(SafeFileHandle h, long dist, out long np, uint method);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool FlushFileBuffers(SafeFileHandle h);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr VirtualAlloc(IntPtr a, UIntPtr size, uint type, uint prot);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool VirtualFree(IntPtr a, UIntPtr size, uint type);

    public static volatile string Phase = "";
    public static volatile int Percent;

    static SafeFileHandle Open(string path, bool write, bool create)
    {
        SafeFileHandle h = CreateFileW(path, write ? (GENERIC_READ | GENERIC_WRITE) : GENERIC_READ, SHARE_RW, IntPtr.Zero,
            create ? CREATE_ALWAYS : OPEN_EXISTING, NO_BUFFERING | ATTR_TEMPORARY, IntPtr.Zero);
        if (h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
        return h;
    }
    static IntPtr Alloc(int bytes, bool random)
    {
        IntPtr p = VirtualAlloc(IntPtr.Zero, (UIntPtr)(uint)bytes, 0x3000, 0x04);
        if (p == IntPtr.Zero) throw new OutOfMemoryException();
        if (random) { byte[] b = new byte[bytes]; new Random(4711).NextBytes(b); Marshal.Copy(b, 0, p, bytes); }
        return p;
    }
    static void Free(IntPtr p) { if (p != IntPtr.Zero) VirtualFree(p, UIntPtr.Zero, 0x8000); }
    static void Seek(SafeFileHandle h, long pos) { long np; if (!SetFilePointerEx(h, pos, out np, 0)) throw new Win32Exception(Marshal.GetLastWin32Error()); }

    public static Task<DiskResult> RunAsync(string path, long sizeBytes, int phaseMillis)
    {
        return Task.Factory.StartNew<DiskResult>(delegate() { return Run(path, sizeBytes, phaseMillis); }, TaskCreationOptions.LongRunning);
    }

    public static DiskResult Run(string path, long sizeBytes, int phaseMillis)
    {
        DiskResult r = new DiskResult();
        const int block = 16 * 1024 * 1024;
        const int rblock = 8 * 1024 * 1024;
        sizeBytes -= sizeBytes % block;
        if (sizeBytes < 4L * block) sizeBytes = 4L * block;
        IntPtr buf = IntPtr.Zero;
        SafeFileHandle writer = null;
        try
        {
            buf = Alloc(block, true);
            // 1) Sequentiell schreiben (Handle bleibt offen, damit kein Virenscan beim Schließen dazwischenfunkt)
            Phase = "Sequentiell schreiben"; Percent = 0;
            writer = Open(path, true, true);
            long written = 0; uint done;
            Stopwatch sw = Stopwatch.StartNew();
            while (written < sizeBytes && sw.ElapsedMilliseconds < phaseMillis * 2)
            {
                if (!WriteFile(writer, buf, (uint)block, out done, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
                written += done; Percent = (int)(written * 25 / sizeBytes);
            }
            FlushFileBuffers(writer); sw.Stop();
            r.SeqWriteMBs = written / sw.Elapsed.TotalSeconds / 1e6;
            r.TestBytes = written;
            long chunks = written / rblock;
            long blocks4k = written / 4096;

            // 2) Sequentiell lesen, 4 Threads im Wechsel (entspricht grob Warteschlangentiefe 4)
            Phase = "Sequentiell lesen"; Percent = 25;
            r.SeqReadMBs = RunThreads(4, phaseMillis, delegate(int tid, Stopwatch w, ref long ops) {
                SafeFileHandle h = Open(path, false, false); IntPtr b = Alloc(rblock, false);
                try { long c = tid; uint d; while (w.ElapsedMilliseconds < phaseMillis) { Seek(h, (c % chunks) * rblock); if (!ReadFile(h, b, (uint)rblock, out d, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error()); ops += d; c += 4; } }
                finally { Free(b); h.Dispose(); }
            }) / 1e6;

            // 3) Zufällig 4K lesen, ein Thread, eine Anfrage (QD1)
            Phase = "Zufällig 4K lesen (QD1)"; Percent = 40;
            r.Rnd4kQ1Iops = RunThreads(1, phaseMillis, delegate(int tid, Stopwatch w, ref long ops) { Random4k(path, blocks4k, 17, w, phaseMillis, ref ops); });

            // 4) Zufällig 4K lesen, 8 Threads
            Phase = "Zufällig 4K lesen (8 Threads)"; Percent = 60;
            r.Rnd4kT8Iops = RunThreads(8, phaseMillis, delegate(int tid, Stopwatch w, ref long ops) { Random4k(path, blocks4k, 100 + tid, w, phaseMillis, ref ops); });

            // 5) Zufällig 4K schreiben, ein Thread (QD1)
            Phase = "Zufällig 4K schreiben (QD1)"; Percent = 80;
            r.Rnd4kWriteQ1Iops = RunThreads(1, phaseMillis, delegate(int tid, Stopwatch w, ref long ops) {
                SafeFileHandle h = Open(path, true, false); IntPtr b = Alloc(4096, true);
                try {
                    Random rnd = new Random(77); uint d;
                    while (w.ElapsedMilliseconds < phaseMillis) {
                        long blk = (long)(rnd.NextDouble() * (blocks4k - 1));
                        Seek(h, blk * 4096);
                        if (!WriteFile(h, b, 4096, out d, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
                        ops++;
                    }
                    FlushFileBuffers(h);
                }
                finally { Free(b); h.Dispose(); }
            });
            Percent = 100; Phase = "fertig";
        }
        catch (Exception ex) { r.Error = ex.Message; }
        finally
        {
            Free(buf);
            if (writer != null) writer.Dispose();
            try { File.Delete(path); } catch { }
        }
        return r;
    }

    delegate void Worker(int tid, Stopwatch w, ref long ops);

    static double RunThreads(int threads, int millis, Worker work)
    {
        long total = 0; string err = null;
        System.Threading.Thread[] ts = new System.Threading.Thread[threads];
        Stopwatch wall = Stopwatch.StartNew();
        for (int t = 0; t < threads; t++)
        {
            int tid = t;
            ts[t] = new System.Threading.Thread(delegate() {
                long ops = 0;
                try { work(tid, wall, ref ops); } catch (Exception ex) { err = ex.Message; }
                Interlocked.Add(ref total, ops);
            });
            ts[t].IsBackground = true; ts[t].Start();
        }
        foreach (System.Threading.Thread th in ts) th.Join();
        wall.Stop();
        if (err != null) throw new IOException(err);
        return total / wall.Elapsed.TotalSeconds;
    }

    static void Random4k(string path, long blocks4k, int seed, Stopwatch w, int millis, ref long ops)
    {
        SafeFileHandle h = Open(path, false, false); IntPtr b = Alloc(4096, false);
        try
        {
            Random rnd = new Random(seed); uint d;
            while (w.ElapsedMilliseconds < millis)
            {
                long blk = (long)(rnd.NextDouble() * (blocks4k - 1));
                Seek(h, blk * 4096);
                if (!ReadFile(h, b, 4096, out d, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
                ops++;
            }
        }
        finally { Free(b); h.Dispose(); }
    }
}

// Dauerlast für einen Datenträger: Testdatei mit Prüfmustern beschreiben, danach zufällig lesen, prüfen und neu schreiben
public static class DiagDiskStress
{
    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000, SHARE_RW = 3;
    const uint CREATE_ALWAYS = 2, NO_BUFFERING = 0x20000000, WRITE_THROUGH = 0x80000000, ATTR_TEMPORARY = 0x100;
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool WriteFile(SafeFileHandle h, IntPtr buf, uint n, out uint done, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadFile(SafeFileHandle h, IntPtr buf, uint n, out uint done, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetFilePointerEx(SafeFileHandle h, long dist, out long np, uint method);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool FlushFileBuffers(SafeFileHandle h);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr VirtualAlloc(IntPtr a, UIntPtr size, uint type, uint prot);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool VirtualFree(IntPtr a, UIntPtr size, uint type);

    public static volatile bool Stop;
    public static volatile string Phase = "";
    public static long Ops, Errors, IoErrors, BytesRead, BytesWritten;
    public static string LastError = "";

    public static Task<string> RunAsync(string path, long sizeBytes, int seconds)
    {
        return Task.Factory.StartNew<string>(delegate() { return Run(path, sizeBytes, seconds); }, TaskCreationOptions.LongRunning);
    }

    static void Fill(long[] buf, long block, long gen)
    {
        ulong s = (((ulong)(block + 1) * 0x9E3779B97F4A7C15UL) ^ ((ulong)(gen + 1) * 0xBF58476D1CE4E5B9UL)) | 1UL;
        for (int i = 0; i < buf.Length; i++) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; buf[i] = (long)s; }
    }

    static void Seek(SafeFileHandle h, long pos) { long np; if (!SetFilePointerEx(h, pos, out np, 0)) throw new Win32Exception(Marshal.GetLastWin32Error()); }

    static void WriteBlock(SafeFileHandle h, long b, IntPtr buf, int size)
    {
        uint done; Seek(h, b * size);
        if (!WriteFile(h, buf, (uint)size, out done, IntPtr.Zero) || done != (uint)size) throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    static void ReadBlock(SafeFileHandle h, long b, IntPtr buf, int size)
    {
        uint done; Seek(h, b * size);
        if (!ReadFile(h, buf, (uint)size, out done, IntPtr.Zero) || done != (uint)size) throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    public static string Run(string path, long sizeBytes, int seconds)
    {
        Ops = 0; Errors = 0; IoErrors = 0; BytesRead = 0; BytesWritten = 0; LastError = ""; Phase = "Vorbereitung";
        const int block = 1 << 20; int elems = block / 8;
        long blocks = Math.Max(16, sizeBytes / block);
        long[] gen = new long[blocks];
        long[] exp = new long[elems], got = new long[elems];
        List<string> details = new List<string>();
        StringBuilder sb = new StringBuilder();
        DateTime start = DateTime.UtcNow;
        IntPtr buf = VirtualAlloc(IntPtr.Zero, (UIntPtr)(uint)block, 0x3000, 0x04);
        if (buf == IntPtr.Zero) return "Speicher für den Datenträgertest konnte nicht reserviert werden.";
        SafeFileHandle h = null;
        long written0 = 0;
        try
        {
            h = CreateFileW(path, GENERIC_READ | GENERIC_WRITE, SHARE_RW, IntPtr.Zero, CREATE_ALWAYS, NO_BUFFERING | WRITE_THROUGH | ATTR_TEMPORARY, IntPtr.Zero);
            if (h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            Phase = "Testdatei wird mit Prüfmustern beschrieben";
            for (long b = 0; b < blocks && !Stop; b++)
            {
                Fill(exp, b, 0); Marshal.Copy(exp, 0, buf, elems);
                WriteBlock(h, b, buf, block); BytesWritten += block; Ops++; written0 = b + 1;
                if ((DateTime.UtcNow - start).TotalSeconds > seconds * 0.5) break;
            }
            blocks = Math.Max(1, written0);
            FlushFileBuffers(h);
            Phase = "Zufällig lesen, prüfen und neu schreiben";
            Random rnd = new Random(4242);
            while (!Stop && (DateTime.UtcNow - start).TotalSeconds < seconds)
            {
                long b = (long)(rnd.NextDouble() * blocks); if (b >= blocks) b = blocks - 1;
                try
                {
                    if (rnd.Next(4) == 0)
                    {
                        gen[b]++; Fill(exp, b, gen[b]); Marshal.Copy(exp, 0, buf, elems);
                        WriteBlock(h, b, buf, block); BytesWritten += block;
                    }
                    else
                    {
                        ReadBlock(h, b, buf, block); BytesRead += block;
                        Marshal.Copy(buf, got, 0, elems); Fill(exp, b, gen[b]);
                        for (int i = 0; i < elems; i++)
                            if (got[i] != exp[i]) { Errors++; if (details.Count < 10) details.Add(String.Format("Block {0} (Offset {1:N0} MB), Wort {2}: erwartet 0x{3:X16}, gelesen 0x{4:X16}", b, b, i, exp[i], got[i])); break; }
                    }
                    Ops++;
                }
                catch (Exception ex) { IoErrors++; LastError = ex.Message; if (IoErrors >= 20) throw; }
            }
            if (!Stop)
            {
                Phase = "Abschlussprüfung aller Blöcke";
                for (long b = 0; b < blocks && !Stop; b++)
                {
                    try
                    {
                        ReadBlock(h, b, buf, block); BytesRead += block;
                        Marshal.Copy(buf, got, 0, elems); Fill(exp, b, gen[b]);
                        for (int i = 0; i < elems; i++)
                            if (got[i] != exp[i]) { Errors++; if (details.Count < 10) details.Add(String.Format("Abschlussprüfung Block {0}, Wort {1}: erwartet 0x{2:X16}, gelesen 0x{3:X16}", b, i, exp[i], got[i])); break; }
                        Ops++;
                    }
                    catch (Exception ex) { IoErrors++; LastError = ex.Message; if (IoErrors >= 20) throw; }
                }
            }
        }
        catch (Exception ex) { LastError = ex.Message; sb.AppendLine("Abbruch: " + ex.Message); }
        finally
        {
            VirtualFree(buf, UIntPtr.Zero, 0x8000);
            if (h != null) h.Dispose();
            try { File.Delete(path); } catch { }
        }
        double sec = Math.Max(0.001, (DateTime.UtcNow - start).TotalSeconds);
        sb.Insert(0, String.Format("Testdatei          : {0:N0} MB\r\nDauer              : {1:N0} s\r\nGelesen            : {2:N0} MB ({3:N0} MB/s)\r\nGeschrieben        : {4:N0} MB ({5:N0} MB/s)\r\nDatenfehler        : {6}\r\nE/A-Fehler         : {7}{8}\r\n",
            blocks, sec, BytesRead / 1048576.0, BytesRead / 1048576.0 / sec, BytesWritten / 1048576.0, BytesWritten / 1048576.0 / sec, Errors, IoErrors, LastError.Length > 0 ? " (zuletzt: " + LastError + ")" : ""));
        foreach (string d in details) sb.AppendLine("  " + d);
        Phase = "fertig";
        return sb.ToString();
    }
}
