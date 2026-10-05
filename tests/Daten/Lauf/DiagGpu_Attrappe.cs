// Attrappe des GPU-Rendertests für die Gesamtläufe unter PowerShell 7 (ohne Direct3D).
// GpuAdapter und GpuRun stammen aus src\Kern\Grafiktest.cs (Lauf.Hilfen.ps1 setzt sie hier ein), DiagGpu ist nachgebaut.
// Steuerung über Umgebungsvariablen:
//   MINIBENCH_TEST_GPU         Namen der Grafikeinheiten, durch ; getrennt (leer = keine Hardware, "-" = Standard)
//   MINIBENCH_TEST_GPU_FEHLER  reset = Treiber-Reset auf der ersten Einheit, bild = Bildfehler, haengt = antwortet nie
using System;
using System.Collections.Generic;
using System.Threading;

//>> KLASSEN

public static class DiagGpu
{
    public static string LastError = "";
    public const int HistBins = 16;
    public static int Starts;
    static readonly List<GpuRun> active = new List<GpuRun>();

    public static string VendorName(int v)
    {
        switch (v) { case 0x10DE: return "NVIDIA"; case 0x1002: return "AMD"; case 0x8086: return "Intel"; default: return ""; }
    }

    static string[] Names()
    {
        string e = Environment.GetEnvironmentVariable("MINIBENCH_TEST_GPU");
        if (e == null || e == "-") return new string[] { "NVIDIA GeForce RTX 3060", "Intel(R) UHD Graphics 730" };
        if (e.Trim().Length == 0) return new string[0];
        return e.Split(';');
    }

    public static GpuAdapter[] Adapters()
    {
        List<GpuAdapter> l = new List<GpuAdapter>();
        string[] n = Names();
        for (int i = 0; i < n.Length; i++)
        {
            GpuAdapter a = new GpuAdapter();
            a.Index = i; a.Name = n[i].Trim(); a.Luid = 1000 + i;
            a.VendorId = a.Name.Contains("NVIDIA") ? 0x10DE : a.Name.Contains("Intel") ? 0x8086 : a.Name.Contains("AMD") || a.Name.Contains("Radeon") ? 0x1002 : 0;
            a.DedicatedMB = a.VendorId == 0x10DE ? 8192 : 128;
            l.Add(a);
        }
        GpuAdapter w = new GpuAdapter(); w.Index = n.Length; w.Name = "Microsoft Basic Render Driver"; w.VendorId = 0x1414; w.DeviceId = 0x8C; w.Software = true; w.Luid = 99;
        l.Add(w);
        return l.ToArray();
    }

    public static double[] Stats(float[] frameMs, double seconds, int width, int height)
    {
        double[] r = new double[6];
        if (frameMs == null || frameMs.Length == 0 || seconds <= 0) return r;
        float[] s = (float[])frameMs.Clone(); Array.Sort(s);
        int n = s.Length; r[0] = n / seconds;
        int worst = Math.Max(1, n / 100); double sum = 0; for (int i = n - worst; i < n; i++) sum += s[i];
        r[1] = 1000.0 / (sum / worst); r[2] = s[n / 2]; r[3] = s[Math.Min(n - 1, (int)Math.Ceiling(n * 0.99) - 1)]; r[4] = s[n - 1]; r[5] = r[0] * width * height / 10000.0;
        return r;
    }

    public static GpuRun Start(int adapterIndex, int width, int height, int warmupMs, int measureMs, int preview, int checkEveryMs)
    {
        GpuRun r = new GpuRun(); r.AdapterIndex = adapterIndex; r.Width = width; r.Height = height; r.WarmupMs = warmupMs; r.MeasureMs = measureMs; r.Preview = preview; r.CheckEveryMs = checkEveryMs;
        return Start(r);
    }

    public static GpuRun Start(GpuRun r)
    {
        Starts++;
        lock (active) active.Add(r);
        Thread t = new Thread(delegate() { Body(r); }); t.IsBackground = true; t.Start();
        return r;
    }

    public static void StopAll() { lock (active) foreach (GpuRun r in active) r.Stop = true; }
    public static bool AnyRunning() { lock (active) foreach (GpuRun r in active) if (!r.Done) return true; return false; }

    public static void Summarize(GpuRun r)
    {
        float[] fm; double[] fp;
        lock (r.Sync) { fm = r.frameList.ToArray(); fp = r.fpsList.ToArray(); r.histCount = fm.Length; r.histMax = 0; r.skipStats = 0; }
        r.FrameMs = fm; r.FpsPerSecond = fp;
        double sec = r.Seconds > 0 ? r.Seconds : r.ElapsedSec;
        if (fm.Length > 0 && sec > 0)
        {
            double[] st = Stats(fm, sec, r.Width, r.Height);
            r.AvgFps = r.MeasuredFrames / sec; r.Low1Fps = st[1]; r.MedianMs = st[2]; r.P99Ms = st[3]; r.MaxMs = st[4]; r.Score = r.AvgFps * r.Width * r.Height / 10000.0;
            double mn = double.MaxValue, mx = 0; foreach (double v in fp) { mn = Math.Min(mn, v); mx = Math.Max(mx, v); }
            r.MinFps = fp.Length > 0 ? mn : r.AvgFps; r.MaxFps = fp.Length > 0 ? mx : r.AvgFps;
        }
    }

    static void Body(GpuRun r)
    {
        string fehler = Environment.GetEnvironmentVariable("MINIBENCH_TEST_GPU_FEHLER") ?? "";
        string[] n = Names();
        r.Started = DateTime.Now;
        try
        {
            if (r.AdapterIndex < 0 || r.AdapterIndex >= n.Length) { r.Error = "EnumAdapters1 fehlgeschlagen"; return; }
            r.AdapterName = n[r.AdapterIndex].Trim();
            r.FeatureLevel = "11_0";
            double fps = r.AdapterName.Contains("NVIDIA") ? 240.0 : 45.0;
            r.RefHash = "attrappe0000000" + r.AdapterIndex;
            // Gegenprobe Bildratengrenze (ab v2.65): MINIBENCH_TEST_GPU_GRENZE=1 simuliert eine Grenze im Treiber
            if (r.ProbeLimit)
            {
                bool cap = Environment.GetEnvironmentVariable("MINIBENCH_TEST_GPU_GRENZE") == "1";
                r.ProbeFpsFull = cap ? 238.0 : fps; r.ProbeFpsLight = cap ? 239.0 : fps * 3.2; r.ProbeDone = true;
            }
            r.Phase = "Aufwärmen";
            if (fehler == "haengt") { while (!r.Stop) Thread.Sleep(20); r.Error = "vor Beginn der Messung beendet"; return; }
            Thread.Sleep(Math.Min(200, r.WarmupMs / 50));
            r.Measuring = true; r.Phase = "Messung";
            Random rnd = new Random(7 + r.AdapterIndex);
            double simSec = 0;
            int steps = 0;
            while (true)
            {
                if (r.Stop) break;
                if (r.MeasureMs > 0 && simSec * 1000 >= r.MeasureMs) break;
                // je Schritt eine simulierte Sekunde
                double f = fps * (1.0 - 0.02 * rnd.NextDouble()) * (r.MeasureMs == 0 ? 1.0 - Math.Min(0.25, steps * 0.002) : 1.0);
                int frames = (int)f;
                lock (r.Sync)
                {
                    for (int k = 0; k < frames; k++) r.frameList.Add((float)(1000.0 / f * (k % 97 == 0 ? 2.5 : 1.0)));
                    r.fpsList.Add(f);
                }
                r.MeasuredFrames += frames; r.Frames += frames; r.LiveFps = f; simSec += 1; steps++; r.ElapsedSec = simSec;
                if (fehler == "reset" && r.AdapterIndex == 0 && simSec >= 2) { r.DeviceRemoved = true; r.RemovedReason = "0x887A0006 DXGI_ERROR_DEVICE_HUNG"; r.Error = "GetData 0x887A0005 DXGI_ERROR_DEVICE_REMOVED"; break; }
                if (r.CheckEveryMs > 0 && steps % Math.Max(1, r.CheckEveryMs / 1000) == 0) { r.ImageChecks++; if (fehler == "bild") r.ImageErrors++; }
                Thread.Sleep(r.MeasureMs > 0 ? 2 : 30);
            }
            r.ImageChecks++;
            if (fehler == "bild") r.ImageErrors++;
            r.Seconds = Math.Max(0.001, simSec);
            r.Ok = r.MeasuredFrames > 0 && !r.DeviceRemoved;
        }
        finally
        {
            Summarize(r);
            r.Ended = DateTime.Now; r.Phase = "beendet"; r.Measuring = false; r.Done = true;
            lock (active) active.Remove(r);
        }
    }
}
