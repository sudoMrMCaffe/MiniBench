using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

// GPU-Rendertest (ab v2.6): eigener Direct3D-11-Renderer ohne Fremdprogramm.
// Direct3D 11 statt OpenGL, weil sich nur so jede Grafikeinheit gezielt ansprechen lässt: Der Test erzeugt das Gerät
// auf dem gewählten DXGI-Adapter (Grafikkarte oder Prozessorgrafik, auch bei Hybridgrafik), rendert in eine Textur
// außerhalb des Bildschirms (kein VSync, keine Bildwiederholrate als Grenze) und zeigt in einem Vorschaufenster
// rund 30-mal je Sekunde das aktuelle Bild (ab v2.65, vorher zweimal je Sekunde). Alle Aufrufe laufen über die COM-Funktionstabellen (vtable), es
// werden keine Zusatzbibliotheken gebraucht. Shader übersetzt d3dcompiler_47.dll (Bestandteil von Windows 10/11).

public class GpuAdapter
{
    public int Index;
    public string Name = "";
    public int VendorId, DeviceId;
    public long DedicatedMB, SharedMB;
    public long Luid;
    public bool Software;
    public string Vendor { get { return DiagGpu.VendorName(VendorId); } }
    public override string ToString() { return Index + ": " + Name + (Software ? " (Software)" : ""); }
}

public class GpuRun
{
    // Einstellungen
    public int AdapterIndex;
    public string AdapterName = "";
    public int Width = 1280, Height = 720;
    public int WarmupMs = 5000;
    public int MeasureMs = 20000;        // 0 = bis Stop (Lasttest)
    public int Preview = 1;              // 0 ohne Anzeige, 1 Fenster, 2 Vollbild
    public int CheckEveryMs = 0;         // Bildprüfung gegen das Referenzbild, 0 = nur am Anfang und am Ende
    public int Steps = 72;               // Schritte je Pixel (fest für vergleichbare Werte)
    public string Title = "";
    public bool KeepImage;               // Referenzbild als Bitmap behalten (Image)
    public int PreviewHz = 30;           // Bilder je Sekunde im Vorschaufenster (ab v2.65)
    public bool ProbeLimit;              // Gegenprobe auf eine Bildratengrenze vor der Messung (ab v2.65)
    public int ProbeMs = 1500;           // Dauer je Probe (volle und geviertelte Rechenlast)

    // Live
    public volatile bool Stop;
    public volatile bool Done;
    public volatile bool Measuring;
    public volatile string Phase = "wird vorbereitet";
    public double LiveFps;
    public long Frames;
    public double ElapsedSec;
    public volatile bool ProbeDone;
    public double ProbeFpsFull, ProbeFpsLight;

    // Ergebnis
    public bool Ok;
    public string Error = "";
    public string FeatureLevel = "";
    public bool DeviceRemoved;
    public string RemovedReason = "";
    public bool EscPressed;
    public double Seconds;
    public long MeasuredFrames;
    public double AvgFps, Low1Fps, MinFps, MaxFps, MedianMs, P99Ms, MaxMs, Score;
    public string RefHash = "";
    public int ImageChecks, ImageErrors;
    public double[] FpsPerSecond = new double[0];
    public float[] FrameMs = new float[0];
    public DateTime Started, Ended;
    public Bitmap Image;

    internal readonly object Sync = new object();
    internal List<double> fpsList = new List<double>();
    internal List<float> frameList = new List<float>();
    // Bildzeiten zusätzlich als Histogramm (logarithmische Klassen, 0,1 % Auflösung): die Liste ist begrenzt, das
    // Histogramm nicht, damit auch ein Lasttest über Stunden korrekte Perzentile liefert
    internal long[] hist = new long[DiagGpu.HistBins];
    internal long histCount;
    internal double histMax;
    internal int skipStats;              // Bildzeiten nach Vorschau oder Bildprüfung nicht werten (Messpause, kein GPU-Wert)

    // Bilder/s je volle Sekunde seit Messbeginn (für den Verlauf im Lasttest)
    public double[] FpsSoFar() { lock (Sync) return fpsList.ToArray(); }
}

public static class DiagGpu
{
    // ------------------------------------------------------------ Szene
    // Fell-Torus mit Volumennebel: pro Pixel bis zu Steps Raymarching-Schritte mit je zwei fbm-Rauschfunktionen
    // (vier Oktaven 3D-Rauschen). Reine Rechenlast im Pixelshader, gleich auf allen PCs, Zeit steuert nur die Drehung.
    // Ausgabe in der Reihenfolge B, G, R, A, damit die Bytes direkt als 32-Bit-Bitmap (BGRA) lesbar sind.
    public const string Hlsl = @"
cbuffer Szene : register(b0) { float4 g; float4 h; };
struct VO { float4 pos : SV_Position; };
VO VS(uint id : SV_VertexID)
{
    VO o;
    float2 uv = float2((id << 1) & 2, id & 2);
    o.pos = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
    return o;
}
float hash3(float3 p)
{
    p = frac(p * 0.3183099 + 0.1);
    p *= 17.0;
    return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise3(float3 x)
{
    float3 i = floor(x);
    float3 f = frac(x);
    f = f * f * (3.0 - 2.0 * f);
    float a = lerp(lerp(hash3(i), hash3(i + float3(1, 0, 0)), f.x), lerp(hash3(i + float3(0, 1, 0)), hash3(i + float3(1, 1, 0)), f.x), f.y);
    float b = lerp(lerp(hash3(i + float3(0, 0, 1)), hash3(i + float3(1, 0, 1)), f.x), lerp(hash3(i + float3(0, 1, 1)), hash3(i + float3(1, 1, 1)), f.x), f.y);
    return lerp(a, b, f.z);
}
float fbm(float3 p)
{
    float s = 0.0;
    float w = 0.5;
    [loop] for (int o = 0; o < 4; o++) { s += w * noise3(p); p = p * 2.03 + float3(1.7, 9.2, 3.1); w *= 0.5; }
    return s;
}
float at2(float y, float x)
{
    float ax = abs(x), ay = abs(y);
    float a = min(ax, ay) / max(max(ax, ay), 1e-6);
    float s = a * a;
    float r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
    if (ay > ax) r = 1.57079637 - r;
    if (x < 0) r = 3.14159274 - r;
    if (y < 0) r = -r;
    return r;
}
float sdTorus(float3 p) { float2 q = float2(length(p.xz) - 1.0, p.y); return length(q) - 0.42; }
float3 rot(float3 p, float a, float b)
{
    float ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b);
    p = float3(p.x, p.y * ca - p.z * sa, p.y * sa + p.z * ca);
    return float3(p.x * cb - p.z * sb, p.y, p.x * sb + p.z * cb);
}
float4 PS(VO i) : SV_Target
{
    float t = g.x;
    float2 uv = (i.pos.xy - 0.5 * g.yz) / g.z;
    uv.y = -uv.y;
    float3 ro = float3(0.0, 0.0, -3.4);
    float3 rd = normalize(float3(uv, 1.55));
    float a = t * 0.53, b = t * 0.31;
    ro = rot(ro, a, b);
    rd = rot(rd, a, b);
    float3 bg = lerp(float3(0.03, 0.05, 0.12), float3(0.10, 0.18, 0.35), saturate(uv.y + 0.6));
    float3 acc = float3(0, 0, 0);
    float alpha = 0.0;
    float d = 0.4;
    int steps = (int)h.x;
    [loop] for (int s = 0; s < steps; s++)
    {
        float3 p = ro + rd * d;
        float dist = sdTorus(p);
        float fog = fbm(p * 1.6 + float3(0.0, t * 0.25, 0.0));
        float fa = 0.012 * fog * (1.0 - alpha);
        acc += float3(0.12, 0.20, 0.42) * fog * fa;
        alpha += fa;
        if (dist < 0.3)
        {
            float shell = saturate(1.0 - (dist + 0.04) / 0.34);
            float2 q2 = float2(length(p.xz) - 1.0, p.y);
            float3 tp = float3(at2(p.z, p.x) * 9.0, at2(q2.y, q2.x) * 5.0, length(q2) * 1.2);
            float n = fbm(tp * float3(3.0, 3.0, 1.0) + float3(0.0, 0.0, t * 0.15));
            float fur = smoothstep(0.40, 0.75, n) * shell;
            float sa = fur * 0.24 * (1.0 - alpha);
            float3 nrm = normalize(p - float3(normalize(float2(p.x, p.z)).x, 0.0, normalize(float2(p.x, p.z)).y));
            float lit = 0.35 + 0.65 * saturate(dot(nrm, normalize(float3(0.5, 0.8, -0.4))));
            acc += lerp(float3(0.95, 0.40, 0.06), float3(1.0, 0.93, 0.66), n) * (0.30 + 0.70 * shell) * lit * sa;
            alpha += sa;
            d += 0.022;
        }
        else
        {
            d += max(dist - 0.26, 0.03);
        }
        if (alpha > 0.985 || d > 7.0) break;
    }
    float3 col = acc + bg * (1.0 - alpha);
    col = pow(saturate(col), 0.85);
    return float4(col.b, col.g, col.r, 1.0);
}
";

    // Zeitpunkt des Referenzbilds (fester Blickwinkel): ein Bild mit diesen Werten muss auf derselben GPU immer gleich sein
    public const float RefTime = 2.5f;

    public static string LastError = "";
    static readonly List<GpuRun> active = new List<GpuRun>();

    // ------------------------------------------------------------ Win32 / DXGI / D3D11
    [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid riid, out IntPtr factory);
    [DllImport("d3d11.dll")] static extern int D3D11CreateDevice(IntPtr adapter, int driverType, IntPtr software, uint flags, int[] levels, uint numLevels, uint sdk, out IntPtr device, out int level, out IntPtr context);
    [DllImport("d3dcompiler_47.dll", CharSet = CharSet.Ansi)] static extern int D3DCompile(byte[] src, UIntPtr size, string name, IntPtr defines, IntPtr include, string entry, string target, uint flags1, uint flags2, out IntPtr code, out IntPtr errors);

    static Guid IID_IDXGIFactory1 = new Guid("770aae78-f26f-4dba-a829-253c83d1b387");

    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate uint FnRelease(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnEnumAdapters1(IntPtr self, uint index, out IntPtr adapter);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnGetDesc1(IntPtr self, IntPtr desc);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnCreateRes(IntPtr self, IntPtr desc, IntPtr init, out IntPtr res);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnCreateView(IntPtr self, IntPtr res, IntPtr desc, out IntPtr view);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnCreateShader(IntPtr self, IntPtr code, UIntPtr len, IntPtr linkage, out IntPtr shader);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnCreateQuery(IntPtr self, IntPtr desc, out IntPtr query);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnHr(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnSetShader(IntPtr self, IntPtr shader, IntPtr inst, uint n);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnSetBuffers(IntPtr self, uint slot, uint n, IntPtr arr);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnSetPtr(IntPtr self, IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnSetUInt(IntPtr self, uint v);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnDraw(IntPtr self, uint count, uint start);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnSetTargets(IntPtr self, uint n, IntPtr views, IntPtr dsv);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnSetViewports(IntPtr self, uint n, IntPtr vp);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnUpdate(IntPtr self, IntPtr res, uint sub, IntPtr box, IntPtr data, uint rowPitch, uint depthPitch);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnCopy(IntPtr self, IntPtr dst, IntPtr src);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnMap(IntPtr self, IntPtr res, uint sub, uint type, uint flags, IntPtr mapped);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnUnmap(IntPtr self, IntPtr res, uint sub);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnGetData(IntPtr self, IntPtr async, IntPtr data, uint size, uint flags);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnVoid(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate IntPtr FnBlobPtr(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate UIntPtr FnBlobSize(IntPtr self);

    // Plätze in den Funktionstabellen (Reihenfolge laut d3d11.h, dxgi.h, d3dcommon.h)
    const int V_Release = 2;
    const int V_Factory_EnumAdapters1 = 12;
    const int V_Adapter_GetDesc1 = 10;
    const int V_Dev_CreateBuffer = 3, V_Dev_CreateTexture2D = 5, V_Dev_CreateRenderTargetView = 9, V_Dev_CreateVertexShader = 12,
              V_Dev_CreatePixelShader = 15, V_Dev_CreateQuery = 24, V_Dev_GetDeviceRemovedReason = 39;
    const int V_Ctx_PSSetShader = 9, V_Ctx_VSSetShader = 11, V_Ctx_Draw = 13, V_Ctx_Map = 14, V_Ctx_Unmap = 15, V_Ctx_PSSetConstantBuffers = 16,
              V_Ctx_IASetInputLayout = 17, V_Ctx_IASetPrimitiveTopology = 24, V_Ctx_End = 28, V_Ctx_GetData = 29, V_Ctx_OMSetRenderTargets = 33,
              V_Ctx_RSSetViewports = 44, V_Ctx_CopyResource = 47, V_Ctx_UpdateSubresource = 48, V_Ctx_ClearState = 110, V_Ctx_Flush = 111;
    const int V_Blob_GetBufferPointer = 3, V_Blob_GetBufferSize = 4;

    const int DXGI_ERROR_NOT_FOUND = unchecked((int)0x887A0002);
    const int DXGI_ERROR_WAS_STILL_DRAWING = unchecked((int)0x887A000A);
    const uint D3D11_MAP_READ = 1, D3D11_MAP_FLAG_DO_NOT_WAIT = 0x100000, D3D11_ASYNC_GETDATA_DONOTFLUSH = 1;

    static T Fn<T>(IntPtr obj, int slot) where T : class
    {
        IntPtr vt = Marshal.ReadIntPtr(obj);
        IntPtr f = Marshal.ReadIntPtr(vt, slot * IntPtr.Size);
        return Marshal.GetDelegateForFunctionPointer(f, typeof(T)) as T;
    }

    static void Release(ref IntPtr p)
    {
        if (p == IntPtr.Zero) return;
        try { Fn<FnRelease>(p, V_Release)(p); } catch { }
        p = IntPtr.Zero;
    }

    static void Check(int hr, string what)
    {
        if (hr < 0) throw new GpuException(hr, what + " fehlgeschlagen (" + HrText(hr) + ")");
    }

    public static string HrText(int hr)
    {
        string n = "";
        switch ((uint)hr)
        {
            case 0x887A0005: n = "DXGI_ERROR_DEVICE_REMOVED"; break;
            case 0x887A0006: n = "DXGI_ERROR_DEVICE_HUNG"; break;
            case 0x887A0007: n = "DXGI_ERROR_DEVICE_RESET"; break;
            case 0x887A0020: n = "DXGI_ERROR_DRIVER_INTERNAL_ERROR"; break;
            case 0x887A0001: n = "DXGI_ERROR_INVALID_CALL"; break;
            case 0x887A0004: n = "DXGI_ERROR_UNSUPPORTED"; break;
            case 0x80070057: n = "E_INVALIDARG"; break;
            case 0x8007000E: n = "E_OUTOFMEMORY"; break;
            case 0x80004005: n = "E_FAIL"; break;
        }
        return "0x" + ((uint)hr).ToString("X8") + (n.Length > 0 ? " " + n : "");
    }

    public static string VendorName(int v)
    {
        switch (v)
        {
            case 0x10DE: return "NVIDIA";
            case 0x1002: case 0x1022: return "AMD";
            case 0x8086: return "Intel";
            case 0x1414: return "Microsoft";
            case 0x5143: return "Qualcomm";
            default: return v == 0 ? "" : "0x" + v.ToString("X4");
        }
    }

    // ------------------------------------------------------------ Adapter
    // Alle Grafikeinheiten laut DXGI, in der Reihenfolge von Windows (0 = Hauptadapter). Software-Adapter
    // (Microsoft Basic Render Driver, WARP) sind markiert und zählen nicht als Grafikeinheit.
    public static GpuAdapter[] Adapters()
    {
        List<GpuAdapter> res = new List<GpuAdapter>();
        IntPtr fac = IntPtr.Zero;
        LastError = "";
        try
        {
            Guid iid = IID_IDXGIFactory1;
            Check(CreateDXGIFactory1(ref iid, out fac), "CreateDXGIFactory1");
            FnEnumAdapters1 en = Fn<FnEnumAdapters1>(fac, V_Factory_EnumAdapters1);
            for (uint i = 0; i < 16; i++)
            {
                IntPtr ad;
                int hr = en(fac, i, out ad);
                if (hr == DXGI_ERROR_NOT_FOUND || hr < 0) break;
                try { res.Add(Describe(ad, (int)i)); }
                finally { Release(ref ad); }
            }
        }
        catch (DllNotFoundException ex) { LastError = "DXGI nicht verfügbar: " + ex.Message; }
        catch (EntryPointNotFoundException ex) { LastError = "DXGI nicht verfügbar: " + ex.Message; }
        catch (Exception ex) { LastError = ex.Message; }
        finally { Release(ref fac); }
        return res.ToArray();
    }

    static GpuAdapter Describe(IntPtr adapter, int index)
    {
        IntPtr d = Marshal.AllocHGlobal(512);
        try
        {
            for (int k = 0; k < 512; k += 4) Marshal.WriteInt32(d, k, 0);
            Check(Fn<FnGetDesc1>(adapter, V_Adapter_GetDesc1)(adapter, d), "IDXGIAdapter1::GetDesc1");
            GpuAdapter a = new GpuAdapter();
            a.Index = index;
            string nm = Marshal.PtrToStringUni(d, 128) ?? "";
            int z = nm.IndexOf('\0'); if (z >= 0) nm = nm.Substring(0, z);
            a.Name = nm.Trim();
            int off = 256;
            a.VendorId = Marshal.ReadInt32(d, off); a.DeviceId = Marshal.ReadInt32(d, off + 4);
            off += 16;
            int ps = IntPtr.Size;
            // SIZE_T ohne Vorzeichen lesen (in 32-Bit-PowerShell sonst negativ ab 2 GB)
            long ded = ReadSize(d, off), dsys = ReadSize(d, off + ps), shr = ReadSize(d, off + 2 * ps);
            a.DedicatedMB = ded / (1024 * 1024); a.SharedMB = shr / (1024 * 1024);
            off += 3 * ps;
            uint lo = (uint)Marshal.ReadInt32(d, off); int hi = Marshal.ReadInt32(d, off + 4);
            a.Luid = ((long)hi << 32) | lo;
            int flags = Marshal.ReadInt32(d, off + 8);
            a.Software = (flags & 2) != 0 || (a.VendorId == 0x1414 && a.DeviceId == 0x8C);
            if (dsys < 0) dsys = 0;
            return a;
        }
        finally { Marshal.FreeHGlobal(d); }
    }

    // ------------------------------------------------------------ Kennzahlen (auch für die Pester-Tests)
    // Ø Bilder/s = Bilder / Messdauer, 1-%-Low = Bilder/s aus dem Mittel der langsamsten 1 % der Bildzeiten,
    // Punktzahl = Ø Bilder/s x Pixel je Bild / 10 000 (bei 1280x720 rund 92 x Bilder/s).
    public static double[] Stats(float[] frameMs, double seconds, int width, int height)
    {
        // Rückgabe: Ø Bilder/s, 1-%-Low, Median ms, 99.-Perzentil ms, längste ms, Punktzahl
        double[] r = new double[6];
        if (frameMs == null || frameMs.Length == 0 || seconds <= 0) return r;
        float[] s = (float[])frameMs.Clone();
        Array.Sort(s);
        int n = s.Length;
        r[0] = n / seconds;
        int worst = Math.Max(1, n / 100);
        double sum = 0; for (int i = n - worst; i < n; i++) sum += s[i];
        double wAvg = sum / worst;
        r[1] = wAvg > 0 ? 1000.0 / wAvg : 0;
        r[2] = n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0;
        r[3] = s[Math.Min(n - 1, (int)Math.Ceiling(n * 0.99) - 1)];
        r[4] = s[n - 1];
        r[5] = r[0] * width * height / 10000.0;
        return r;
    }

    public static ulong Fnv(byte[] b, int len, ulong h)
    {
        for (int i = 0; i < len; i++) { h ^= b[i]; h *= 1099511628211UL; }
        return h;
    }

    public static ulong Fnv(byte[] b, int offset, int len, ulong h)
    {
        int e = offset + len;
        for (int i = offset; i < e; i++) { h ^= b[i]; h *= 1099511628211UL; }
        return h;
    }

    // Histogramm der Bildzeiten: Klasse k umfasst 0,01 ms x 1,001^k bis 0,01 ms x 1,001^(k+1), also 0,01 ms bis rund 60 s
    public const int HistBins = 15700;
    const double HistBase = 0.01;
    static readonly double HistLog = Math.Log(1.001);

    public static int HistBin(double ms)
    {
        if (!(ms > HistBase)) return 0;
        int k = (int)(Math.Log(ms / HistBase) / HistLog);
        return k < 0 ? 0 : k >= HistBins ? HistBins - 1 : k;
    }

    public static double HistMid(int k) { return HistBase * Math.Exp((k + 0.5) * HistLog); }

    // Kennzahlen aus dem Histogramm, Rückgabe wie Stats: Ø Bilder/s, 1-%-Low, Median ms, 99.-Perzentil ms, längste ms, Punktzahl
    public static double[] StatsHist(long[] hist, double maxMs, double seconds, int width, int height)
    {
        double[] r = new double[6];
        long n = 0; for (int k = 0; k < hist.Length; k++) n += hist[k];
        if (n == 0 || seconds <= 0) return r;
        r[0] = n / seconds;
        long worst = Math.Max(1, n / 100), need = worst; double sum = 0;
        for (int k = hist.Length - 1; k >= 0 && need > 0; k--)
        {
            if (hist[k] == 0) continue;
            long take = Math.Min(need, hist[k]);
            sum += take * Math.Min(HistMid(k), maxMs > 0 ? maxMs : double.MaxValue); need -= take;
        }
        double wAvg = sum / worst;
        r[1] = wAvg > 0 ? 1000.0 / wAvg : 0;
        long half = (n + 1) / 2, p99 = (long)Math.Ceiling(n * 0.99), c = 0;
        bool hasMed = false;
        for (int k = 0; k < hist.Length; k++)
        {
            if (hist[k] == 0) continue;
            c += hist[k];
            if (!hasMed && c >= half) { r[2] = HistMid(k); hasMed = true; }
            if (c >= p99) { r[3] = HistMid(k); break; }
        }
        r[4] = maxMs;
        r[5] = r[0] * width * height / 10000.0;
        return r;
    }

    // Kennzahlen eines Laufs berechnen. Läuft am Ende des Renderthreads und kann auch von außen aufgerufen werden,
    // wenn der Thread nicht mehr antwortet (Zwischenstand bis dahin).
    public static void Summarize(GpuRun r)
    {
        float[] fm; double[] fps; long[] h; long hc; double hmax;
        lock (r.Sync) { fm = r.frameList.ToArray(); fps = r.fpsList.ToArray(); h = (long[])r.hist.Clone(); hc = r.histCount; hmax = r.histMax; }
        r.FrameMs = fm; r.FpsPerSecond = fps;
        double sec = r.Seconds > 0 ? r.Seconds : r.ElapsedSec;
        if (sec <= 0 || r.MeasuredFrames <= 0) return;
        double[] st = hc > fm.Length ? StatsHist(h, hmax, sec, r.Width, r.Height) : fm.Length > 0 ? Stats(fm, sec, r.Width, r.Height) : new double[6];
        // Ø Bilder/s aus allen gemessenen Bildern (auch denen, deren Bildzeit wegen einer Messpause nicht gewertet wurde)
        r.AvgFps = r.MeasuredFrames / sec;
        r.Low1Fps = st[1]; r.MedianMs = st[2]; r.P99Ms = st[3]; r.MaxMs = st[4];
        r.Score = r.AvgFps * r.Width * r.Height / 10000.0;
        if (fps.Length > 0) { double mn = double.MaxValue, mx = 0; foreach (double v in fps) { mn = Math.Min(mn, v); mx = Math.Max(mx, v); } r.MinFps = mn; r.MaxFps = mx; }
        else { r.MinFps = r.AvgFps; r.MaxFps = r.AvgFps; }
    }

    // ------------------------------------------------------------ Ablauf
    public static GpuRun Start(int adapterIndex, int width, int height, int warmupMs, int measureMs, int preview, int checkEveryMs)
    {
        GpuRun r = new GpuRun();
        r.AdapterIndex = adapterIndex; r.Width = Math.Max(64, width); r.Height = Math.Max(64, height);
        r.WarmupMs = Math.Max(0, warmupMs); r.MeasureMs = Math.Max(0, measureMs); r.Preview = preview; r.CheckEveryMs = Math.Max(0, checkEveryMs);
        return Start(r);
    }

    public static GpuRun Start(GpuRun r)
    {
        lock (active) { active.Add(r); }
        Thread t = new Thread(delegate() { Body(r); });
        t.IsBackground = true; t.Name = "Rendertest " + r.AdapterIndex;
        // über den CPU-Lastthreads, damit die Grafikeinheit im gemeinsamen Lasttest durchgehend Arbeit bekommt
        t.Priority = ThreadPriority.AboveNormal;
        t.Start();
        return r;
    }

    public static GpuRun Run(int adapterIndex, int width, int height, int warmupMs, int measureMs, int preview, int checkEveryMs)
    {
        GpuRun r = Start(adapterIndex, width, height, warmupMs, measureMs, preview, checkEveryMs);
        while (!r.Done) Thread.Sleep(50);
        return r;
    }

    public static void StopAll()
    {
        lock (active) { foreach (GpuRun r in active) r.Stop = true; }
    }

    public static bool AnyRunning()
    {
        lock (active) { foreach (GpuRun r in active) if (!r.Done) return true; }
        return false;
    }

    class GpuException : Exception
    {
        public int Hr;
        public GpuException(int hr, string msg) : base(msg) { Hr = hr; }
    }

    static void Body(GpuRun r)
    {
        IntPtr fac = IntPtr.Zero, adapter = IntPtr.Zero, dev = IntPtr.Zero, ctx = IntPtr.Zero, tex = IntPtr.Zero, rtv = IntPtr.Zero;
        IntPtr vs = IntPtr.Zero, ps = IntPtr.Zero, cb = IntPtr.Zero;
        // Zwischenspeicher zum Auslesen: 0 bis 2 Vorschau (Ring), 3 Referenzbild und Bildprüfung
        IntPtr[] stg = new IntPtr[4]; IntPtr[] q = new IntPtr[4];
        IntPtr mem = IntPtr.Zero;
        PreviewForm form = null;
        Stopwatch sw = new Stopwatch();
        double mStart = -1;
        r.Started = DateTime.Now;
        try
        {
            r.Phase = "Grafikgerät wird geöffnet";
            Guid iid = IID_IDXGIFactory1;
            Check(CreateDXGIFactory1(ref iid, out fac), "CreateDXGIFactory1");
            Check(Fn<FnEnumAdapters1>(fac, V_Factory_EnumAdapters1)(fac, (uint)r.AdapterIndex, out adapter), "EnumAdapters1(" + r.AdapterIndex + ")");
            GpuAdapter info = Describe(adapter, r.AdapterIndex);
            r.AdapterName = info.Name;
            int level;
            int[] levels = new int[] { 0xB000, 0xA100, 0xA000 };
            Check(D3D11CreateDevice(adapter, 0, IntPtr.Zero, 0, levels, (uint)levels.Length, 7, out dev, out level, out ctx), "D3D11CreateDevice");
            r.FeatureLevel = ((level >> 12) & 0xF) + "_" + ((level >> 8) & 0xF);

            r.Phase = "Shader werden übersetzt";
            byte[] vsCode = Compile("VS", "vs_4_0");
            byte[] psCode = Compile("PS", "ps_4_0");

            // Speicher für Beschreibungen und Parameter (wird mehrfach verwendet)
            mem = Marshal.AllocHGlobal(256);
            FnCreateRes createTex = Fn<FnCreateRes>(dev, V_Dev_CreateTexture2D);
            // Renderziel: R8G8B8A8, Bild außerhalb des Bildschirms
            WriteU(mem, r.Width, r.Height, 1, 1, 28, 1, 0, 0, 0x20, 0, 0);
            Check(createTex(dev, mem, IntPtr.Zero, out tex), "CreateTexture2D (Renderziel)");
            Check(Fn<FnCreateView>(dev, V_Dev_CreateRenderTargetView)(dev, tex, IntPtr.Zero, out rtv), "CreateRenderTargetView");
            // Kopien zum Auslesen, Usage STAGING, CPU lesen
            for (int k = 0; k < stg.Length; k++) { WriteU(mem, r.Width, r.Height, 1, 1, 28, 1, 0, 3, 0, 0x20000, 0); Check(createTex(dev, mem, IntPtr.Zero, out stg[k]), "CreateTexture2D (Kopie)"); }
            // Konstanten: 32 Byte
            WriteU(mem, 32, 0, 4, 0, 0, 0);
            Check(Fn<FnCreateRes>(dev, V_Dev_CreateBuffer)(dev, mem, IntPtr.Zero, out cb), "CreateBuffer");
            WriteU(mem, 0, 0);
            FnCreateQuery cq = Fn<FnCreateQuery>(dev, V_Dev_CreateQuery);
            for (int k = 0; k < q.Length; k++) Check(cq(dev, mem, out q[k]), "CreateQuery");
            vs = CreateShader(dev, V_Dev_CreateVertexShader, vsCode, "CreateVertexShader");
            ps = CreateShader(dev, V_Dev_CreatePixelShader, psCode, "CreatePixelShader");

            // Funktionen des Kontexts einmal holen
            FnSetShader psSet = Fn<FnSetShader>(ctx, V_Ctx_PSSetShader), vsSet = Fn<FnSetShader>(ctx, V_Ctx_VSSetShader);
            FnDraw draw = Fn<FnDraw>(ctx, V_Ctx_Draw);
            FnMap map = Fn<FnMap>(ctx, V_Ctx_Map); FnUnmap unmap = Fn<FnUnmap>(ctx, V_Ctx_Unmap);
            FnSetBuffers psCb = Fn<FnSetBuffers>(ctx, V_Ctx_PSSetConstantBuffers);
            FnSetPtr setLayout = Fn<FnSetPtr>(ctx, V_Ctx_IASetInputLayout), end = Fn<FnSetPtr>(ctx, V_Ctx_End);
            FnSetUInt topo = Fn<FnSetUInt>(ctx, V_Ctx_IASetPrimitiveTopology);
            FnGetData getData = Fn<FnGetData>(ctx, V_Ctx_GetData);
            FnSetTargets omSet = Fn<FnSetTargets>(ctx, V_Ctx_OMSetRenderTargets);
            FnSetViewports rsVp = Fn<FnSetViewports>(ctx, V_Ctx_RSSetViewports);
            FnCopy copy = Fn<FnCopy>(ctx, V_Ctx_CopyResource);
            FnUpdate update = Fn<FnUpdate>(ctx, V_Ctx_UpdateSubresource);
            FnVoid flush = Fn<FnVoid>(ctx, V_Ctx_Flush);
            FnHr removed = Fn<FnHr>(dev, V_Dev_GetDeviceRemovedReason);

            // Zustand der Pipeline einmal setzen
            IntPtr arr = Marshal.AllocHGlobal(IntPtr.Size * 2);
            IntPtr vp = Marshal.AllocHGlobal(24);
            IntPtr cbData = Marshal.AllocHGlobal(32);
            IntPtr mapped = Marshal.AllocHGlobal(16 + IntPtr.Size);
            try
            {
                setLayout(ctx, IntPtr.Zero);
                topo(ctx, 4);   // TRIANGLELIST
                vsSet(ctx, vs, IntPtr.Zero, 0);
                psSet(ctx, ps, IntPtr.Zero, 0);
                Marshal.WriteIntPtr(arr, cb); psCb(ctx, 0, 1, arr);
                Marshal.WriteIntPtr(arr, rtv); omSet(ctx, 1, arr, IntPtr.Zero);
                float[] vpv = new float[] { 0f, 0f, r.Width, r.Height, 0f, 1f };
                Marshal.Copy(vpv, 0, vp, 6); rsVp(ctx, 1, vp);

                float[] par = new float[8];
                Action<float, int> setTime = delegate(float t, int steps)
                {
                    par[0] = t; par[1] = r.Width; par[2] = r.Height; par[3] = 0f;
                    par[4] = steps; par[5] = 0f; par[6] = 0f; par[7] = 0f;
                    Marshal.Copy(par, 0, cbData, 8);
                    update(ctx, cb, 0, IntPtr.Zero, cbData, 0, 0);
                };
                int rowBytes = r.Width * 4;
                byte[] refBuf = null;
                // Bild der Kopie k auslesen. Vorschau: Zeilen ohne Zwischenabstand in einen Puffer des Fensters
                // (wiederverwendet, keine neuen Speicherblöcke je Bild). Referenz und Bildprüfung: Prüfsumme.
                Func<int, bool, bool, string> readBack = delegate(int k, bool wait, bool toForm)
                {
                    uint flags = wait ? 0u : D3D11_MAP_FLAG_DO_NOT_WAIT;
                    int hr = map(ctx, stg[k], 0, D3D11_MAP_READ, flags, mapped);
                    if (hr == DXGI_ERROR_WAS_STILL_DRAWING) return null;
                    Check(hr, "Map");
                    byte[] buf; int pitch;
                    try
                    {
                        IntPtr p = Marshal.ReadIntPtr(mapped);
                        pitch = Marshal.ReadInt32(mapped, IntPtr.Size);
                        if (pitch < rowBytes) pitch = rowBytes;
                        if (toForm)
                        {
                            if (form == null) return "";
                            buf = form.TakeSpare(rowBytes * r.Height);
                            if (pitch == rowBytes) Marshal.Copy(p, buf, 0, rowBytes * r.Height);
                            else for (int y = 0; y < r.Height; y++) Marshal.Copy(IntPtr.Add(p, y * pitch), buf, y * rowBytes, rowBytes);
                        }
                        else
                        {
                            int len = pitch * (r.Height - 1) + rowBytes;
                            buf = refBuf != null && refBuf.Length >= len ? refBuf : (refBuf = new byte[len]);
                            Marshal.Copy(p, buf, 0, len);
                        }
                    }
                    finally { unmap(ctx, stg[k], 0); }
                    if (toForm) { form.Publish(buf, r.Width, r.Height); return ""; }
                    ulong h = 14695981039346656037UL;
                    for (int y = 0; y < r.Height; y++) h = Fnv(buf, y * pitch, rowBytes, h);
                    if (r.KeepImage && r.Image == null) r.Image = PreviewForm.ToBitmap(buf, pitch, r.Width, r.Height);
                    return h.ToString("x16");
                };
                int frameNo = 0;
                long removedCheck = 0;
                // Warten auf ein fertiges Bild. DONOTFLUSH: jedes Bild wurde schon mit Flush abgeschickt, das Abfragen
                // selbst löst keine weiteren Übergaben an den Treiber aus (gleichmäßigere Bildzeiten).
                Func<int, double> waitQuery = delegate(int idx)
                {
                    Stopwatch w = Stopwatch.StartNew(); int spins = 0;
                    while (true)
                    {
                        int hr = getData(ctx, q[idx], IntPtr.Zero, 0, D3D11_ASYNC_GETDATA_DONOTFLUSH);
                        if (hr == 0) return w.Elapsed.TotalMilliseconds;
                        if (hr < 0) throw new GpuException(hr, "GetData " + HrText(hr));
                        if (w.ElapsedMilliseconds > 10000) throw new GpuException(unchecked((int)0x887A0006), "Die Grafikeinheit antwortet seit 10 Sekunden nicht mehr");
                        if (++spins > 64) Thread.Sleep(0);
                    }
                };
                Func<float, string> renderReference = delegate(float t)
                {
                    setTime(t, r.Steps);
                    draw(ctx, 3, 0);
                    copy(ctx, stg[3], tex);
                    end(ctx, q[0]); flush(ctx);
                    waitQuery(0);
                    return readBack(3, true, false);
                };
                // Gegenprobe Bildratengrenze: gleiche Szene mit voller und mit einem Viertel der Rechenlast. Begrenzt nur
                // die Grafikeinheit, steigen die Bilder/s mit weniger Last deutlich; bleiben sie gleich, begrenzt etwas
                // anderes (Bildratengrenze im Treiber, Prozessor oder Treiber).
                Func<int, int, double> probe = delegate(int steps, int ms)
                {
                    int n = 0; long counted = 0; double tStart = -1, tLast = 0;
                    Stopwatch pw = Stopwatch.StartNew();
                    while (!r.Stop && pw.ElapsedMilliseconds < ms + 300)
                    {
                        setTime((float)pw.Elapsed.TotalSeconds, steps);
                        draw(ctx, 3, 0);
                        end(ctx, q[n % 4]); flush(ctx);
                        n++;
                        if (n >= 3)
                        {
                            waitQuery((n - 3) % 4);
                            double t = pw.Elapsed.TotalSeconds;
                            if (t >= 0.3) { if (tStart < 0) tStart = t; else counted++; tLast = t; }
                        }
                        if (form != null && form.Gone) { r.Stop = true; r.EscPressed = form.Esc; }
                    }
                    for (int k = Math.Max(0, n - 2); k < n; k++) waitQuery(k % 4);
                    return tStart >= 0 && tLast > tStart ? counted / (tLast - tStart) : 0;
                };

                if (r.Preview > 0)
                {
                    form = PreviewForm.Open(r);
                }

                // Referenzbild vor der Last (fester Zeitpunkt)
                r.Phase = "Referenzbild";
                r.RefHash = renderReference(RefTime) ?? "";

                if (r.ProbeLimit && !r.Stop)
                {
                    r.Phase = "Prüfung auf Bildratengrenze";
                    if (form != null) form.Info = r.AdapterName + "   ·   " + r.Phase;
                    r.ProbeFpsFull = probe(r.Steps, Math.Max(500, r.ProbeMs));
                    if (!r.Stop) r.ProbeFpsLight = probe(Math.Max(4, r.Steps / 4), Math.Max(500, r.ProbeMs));
                    r.ProbeDone = true;
                }

                r.Phase = r.WarmupMs > 0 ? "Aufwärmen" : "Messung";
                sw.Start();
                double lastDone = 0, measureStart = -1, nextPreview = 0.1, nextInfo = 0, nextCheck = r.CheckEveryMs > 0 ? r.CheckEveryMs / 1000.0 : double.MaxValue;
                double previewStep = 1.0 / Math.Max(1, Math.Min(60, r.PreviewHz));
                double secStart = 0; long secFrames = 0, liveFrames = 0; double liveStart = 0;
                // Ring der Vorschau-Kopien: pendHead = älteste ausstehende Kopie, pendCount = Zahl ausstehender Kopien
                int pendHead = 0, pendCount = 0; double[] pendAt = new double[3];
                while (true)
                {
                    double now = sw.Elapsed.TotalSeconds;
                    if (r.Stop) break;
                    bool inMeasure = now * 1000.0 >= r.WarmupMs;
                    if (inMeasure && measureStart < 0)
                    {
                        measureStart = now; mStart = now; secStart = now; secFrames = 0; r.Measuring = true; r.Phase = "Messung";
                    }
                    if (inMeasure && r.MeasureMs > 0 && (now - measureStart) * 1000.0 >= r.MeasureMs) break;

                    setTime((float)now, r.Steps);
                    draw(ctx, 3, 0);
                    end(ctx, q[frameNo % 4]);
                    flush(ctx);   // jedes Bild sofort abschicken, damit die GPU gleichmäßig arbeitet
                    frameNo++;
                    if (frameNo >= 3)
                    {
                        // zwei Bilder in Arbeit: so kommen die Bildzeiten gleichmäßig an (bei drei bündeln manche Treiber die Abfragen)
                        waitQuery((frameNo - 3) % 4);
                        double t = sw.Elapsed.TotalSeconds;
                        double ms = (t - lastDone) * 1000.0;
                        lastDone = t;
                        r.Frames++; liveFrames++;
                        if (measureStart >= 0 && t >= measureStart)
                        {
                            r.MeasuredFrames++;
                            if (r.skipStats > 0) r.skipStats--;
                            else lock (r.Sync)
                            {
                                if (r.frameList.Count < 2000000) r.frameList.Add((float)ms);
                                r.hist[HistBin(ms)]++; r.histCount++; if (ms > r.histMax) r.histMax = ms;
                            }
                            secFrames++;
                            if (t - secStart >= 1.0)
                            {
                                lock (r.Sync) r.fpsList.Add(secFrames / (t - secStart));
                                secStart = t; secFrames = 0;
                            }
                        }
                        if (t - liveStart >= 0.5) { r.LiveFps = liveFrames / (t - liveStart); liveStart = t; liveFrames = 0; r.ElapsedSec = measureStart >= 0 ? t - measureStart : 0; }
                    }
                    else lastDone = sw.Elapsed.TotalSeconds;

                    // Vorschau (ab v2.65 rund 30 Bilder je Sekunde): Kopie in einen freien Zwischenspeicher anstoßen und
                    // ältere Kopien ohne Warten abholen.
                    if (form != null)
                    {
                        if (form.Gone) { r.Stop = true; r.EscPressed = form.Esc; }
                        else
                        {
                            while (pendCount > 0)
                            {
                                int k = pendHead;
                                if (now - pendAt[k] < 0.004) break;
                                if (readBack(k, false, true) == null)
                                {
                                    // noch nicht fertig; nach 2 Sekunden aufgeben (Treiber hält die Kopie fest)
                                    if (now - pendAt[k] > 2.0) { pendHead = (k + 1) % 3; pendCount--; continue; }
                                    break;
                                }
                                pendHead = (k + 1) % 3; pendCount--;
                                // das Kopieren für die Vorschau kostet den Renderthread etwa eine Millisekunde: das nächste
                                // Bild nicht werten (zählt aber für Ø Bilder/s), sonst wären Fenster und "ohne Anzeige" ungleich
                                r.skipStats = Math.Max(r.skipStats, 1);
                            }
                            if (pendCount < 3 && now >= nextPreview)
                            {
                                int k = (pendHead + pendCount) % 3;
                                copy(ctx, stg[k], tex); pendAt[k] = now; pendCount++;
                                nextPreview = Math.Max(now, nextPreview + previewStep);
                            }
                            if (now >= nextInfo)
                            {
                                form.Info = String.Format(CultureInfo.GetCultureInfo("de-DE"), "{0}   ·   {1}x{2}   ·   {3:0} Bilder/s   ·   {4}", r.AdapterName, r.Width, r.Height, r.LiveFps, r.Phase);
                                nextInfo = now + 0.25;
                            }
                        }
                    }
                    // Bildprüfung während der Dauerlast
                    if (now >= nextCheck && !r.Stop)
                    {
                        string prev = r.Phase; r.Phase = "Bildprüfung";
                        pendCount = 0;
                        string hc = renderReference(RefTime);
                        r.ImageChecks++;
                        if (hc != r.RefHash) r.ImageErrors++;
                        r.Phase = prev;
                        nextCheck = sw.Elapsed.TotalSeconds + r.CheckEveryMs / 1000.0;
                        lastDone = sw.Elapsed.TotalSeconds; frameNo = 0; r.skipStats = 3;
                    }
                    if (++removedCheck % 256 == 0) { int rr = removed(dev); if (rr < 0) throw new GpuException(rr, "Grafikgerät entfernt"); }
                }
                // ausstehende Bilder abwarten, dann Abschlussprüfung des Referenzbilds
                for (int k = Math.Max(0, frameNo - 2); k < frameNo; k++) waitQuery(k % 4);
                double tEnd = sw.Elapsed.TotalSeconds;
                r.Seconds = measureStart >= 0 ? Math.Max(0.001, Math.Min(tEnd, measureStart + (r.MeasureMs > 0 ? r.MeasureMs / 1000.0 : tEnd)) - measureStart) : 0;
                r.Phase = "Bildprüfung";
                string hEnd = renderReference(RefTime);
                r.ImageChecks++;
                if (hEnd != r.RefHash) r.ImageErrors++;
                r.Ok = r.MeasuredFrames > 0;
                if (!r.Ok && r.Error.Length == 0) r.Error = r.Stop ? "vor Beginn der Messung beendet" : "keine Bilder gemessen";
            }
            finally
            {
                Marshal.FreeHGlobal(arr); Marshal.FreeHGlobal(vp); Marshal.FreeHGlobal(cbData); Marshal.FreeHGlobal(mapped);
            }
        }
        catch (GpuException ex)
        {
            r.Error = ex.Message;
            uint u = (uint)ex.Hr;
            if (u == 0x887A0005 || u == 0x887A0006 || u == 0x887A0007 || u == 0x887A0020)
            {
                r.DeviceRemoved = true;
                int why = 0;
                try { if (dev != IntPtr.Zero) why = Fn<FnHr>(dev, V_Dev_GetDeviceRemovedReason)(dev); } catch { }
                r.RemovedReason = HrText(why != 0 ? why : ex.Hr);
            }
        }
        catch (DllNotFoundException ex) { r.Error = "Direct3D 11 nicht verfügbar: " + ex.Message; }
        catch (EntryPointNotFoundException ex) { r.Error = "Direct3D 11 nicht verfügbar: " + ex.Message; }
        catch (Exception ex) { r.Error = ex.GetType().Name + ": " + ex.Message; }
        finally
        {
            // abgebrochen (z. B. Treiber-Reset): Kennzahlen bis zum Abbruch
            if (r.Seconds <= 0 && mStart >= 0) r.Seconds = Math.Max(0.001, sw.Elapsed.TotalSeconds - mStart);
            sw.Stop();
            if (r.ProbeLimit) r.ProbeDone = true;
            // Kennzahlen aus den Bildzeiten
            try { Summarize(r); } catch { }
            // Grafikkontext sauber freigeben
            try
            {
                if (ctx != IntPtr.Zero) { Fn<FnVoid>(ctx, V_Ctx_ClearState)(ctx); Fn<FnVoid>(ctx, V_Ctx_Flush)(ctx); }
            }
            catch { }
            for (int k = 0; k < q.Length; k++) Release(ref q[k]);
            for (int k = 0; k < stg.Length; k++) Release(ref stg[k]);
            Release(ref cb); Release(ref ps); Release(ref vs); Release(ref rtv); Release(ref tex);
            Release(ref ctx); Release(ref dev); Release(ref adapter); Release(ref fac);
            if (mem != IntPtr.Zero) Marshal.FreeHGlobal(mem);
            if (form != null) form.CloseAsync();
            r.Ended = DateTime.Now;
            r.Phase = "beendet";
            r.Measuring = false;
            r.Done = true;
            lock (active) { active.Remove(r); }
        }
    }

    static long ReadSize(IntPtr p, int off) { return IntPtr.Size == 4 ? (long)(uint)Marshal.ReadInt32(p, off) : Marshal.ReadInt64(p, off); }

    static void WriteU(IntPtr p, params int[] v)
    {
        for (int i = 0; i < v.Length; i++) Marshal.WriteInt32(p, i * 4, v[i]);
    }

    static IntPtr CreateShader(IntPtr dev, int slot, byte[] code, string what)
    {
        GCHandle h = GCHandle.Alloc(code, GCHandleType.Pinned);
        try
        {
            IntPtr s;
            Check(Fn<FnCreateShader>(dev, slot)(dev, h.AddrOfPinnedObject(), new UIntPtr((uint)code.Length), IntPtr.Zero, out s), what);
            return s;
        }
        finally { h.Free(); }
    }

    static readonly Dictionary<string, byte[]> shaderCache = new Dictionary<string, byte[]>();

    public static byte[] Compile(string entry, string target)
    {
        string key = entry + "|" + target;
        lock (shaderCache) { byte[] c; if (shaderCache.TryGetValue(key, out c)) return c; }
        byte[] src = Encoding.ASCII.GetBytes(Hlsl);
        IntPtr code, err;
        // Optimierungsstufe 3
        int hr = D3DCompile(src, new UIntPtr((uint)src.Length), "Rendertest", IntPtr.Zero, IntPtr.Zero, entry, target, 1u << 15, 0, out code, out err);
        try
        {
            if (hr < 0 || code == IntPtr.Zero)
            {
                string msg = "";
                if (err != IntPtr.Zero)
                {
                    IntPtr ep = Fn<FnBlobPtr>(err, V_Blob_GetBufferPointer)(err);
                    msg = Marshal.PtrToStringAnsi(ep) ?? "";
                }
                throw new GpuException(hr, "Shader " + entry + " ließ sich nicht übersetzen (" + HrText(hr) + "): " + msg.Trim());
            }
            IntPtr p = Fn<FnBlobPtr>(code, V_Blob_GetBufferPointer)(code);
            int n = (int)Fn<FnBlobSize>(code, V_Blob_GetBufferSize)(code).ToUInt32();
            byte[] b = new byte[n];
            Marshal.Copy(p, b, 0, n);
            lock (shaderCache) { shaderCache[key] = b; }
            return b;
        }
        finally { Release(ref code); Release(ref err); }
    }

    // ------------------------------------------------------------ Vorschaufenster
    // Eigenes Fenster in einem eigenen Thread: zeigt das zuletzt ausgelesene Bild, Esc oder Schließen beendet den Test.
    // Ab v2.65 rund 30 Bilder je Sekunde: Das Bild geht als Rohdaten (BGRA, Zeilen ohne Abstand) direkt per
    // StretchDIBits auf das Fenster, ohne Bitmap je Bild. Drei Puffer wechseln zwischen Renderthread und Fenster.
    [StructLayout(LayoutKind.Sequential)]
    struct BITMAPINFOHEADER
    {
        public int biSize, biWidth, biHeight; public short biPlanes, biBitCount; public int biCompression, biSizeImage, biXPelsPerMeter, biYPelsPerMeter, biClrUsed, biClrImportant;
    }
    [DllImport("gdi32.dll")] static extern int StretchDIBits(IntPtr hdc, int xDest, int yDest, int wDest, int hDest, int xSrc, int ySrc, int wSrc, int hSrc, byte[] bits, ref BITMAPINFOHEADER bmi, uint usage, uint rop);
    [DllImport("gdi32.dll")] static extern int SetStretchBltMode(IntPtr hdc, int mode);
    [DllImport("gdi32.dll")] static extern bool SetBrushOrgEx(IntPtr hdc, int x, int y, IntPtr old);

    // Ausgabefläche des Bildes im Fenster: Seitenverhältnis halten, unten Platz für die Infozeile (auch für die Tests)
    public static Rectangle FitImage(int clientW, int clientH, int imgW, int imgH, int footer)
    {
        int ah = Math.Max(1, clientH - footer);
        if (imgW <= 0 || imgH <= 0 || clientW <= 0) return Rectangle.Empty;
        double sc = Math.Min((double)clientW / imgW, (double)ah / imgH);
        int w = Math.Max(1, (int)(imgW * sc)), h = Math.Max(1, (int)(imgH * sc));
        return new Rectangle((clientW - w) / 2, (ah - h) / 2, w, h);
    }

    class PreviewForm : Form
    {
        readonly object fl = new object();
        public volatile bool Gone, Esc;
        public volatile string Info = "";
        readonly Font font = new Font("Segoe UI", 10f);
        System.Windows.Forms.Timer tick;
        // latest: zuletzt fertiges Bild (Renderthread), shown: angezeigtes Bild (nur Fensterthread), spare: freie Puffer
        byte[] latest, shown; int latestW, latestH, shownW, shownH;
        readonly Stack<byte[]> spare = new Stack<byte[]>();
        string lastInfo = "";

        public static PreviewForm Open(GpuRun r)
        {
            PreviewForm f = null;
            object box = new object(); bool abandoned = false;
            ManualResetEvent ready = new ManualResetEvent(false);
            Thread t = new Thread(delegate()
            {
                PreviewForm mine = null;
                try
                {
                    mine = new PreviewForm(r);
                    // kam das Fenster zu spät (Renderthread wartet nicht mehr), gar nicht erst anzeigen
                    lock (box) { if (abandoned) { mine.Dispose(); mine = null; return; } f = mine; }
                    mine.Shown += delegate { ready.Set(); };
                    mine.HandleCreated += delegate { ready.Set(); };
                    Application.Run(mine);
                }
                catch { }
                finally { if (mine != null) mine.Gone = true; try { ready.Set(); } catch { } }
            });
            t.IsBackground = true; t.SetApartmentState(ApartmentState.STA); t.Name = "Rendertest-Vorschau";
            t.Start();
            bool ok = ready.WaitOne(5000);
            lock (box)
            {
                if (!ok) abandoned = true;
                // zu spät erzeugtes Fenster schließen, der Test läuft dann ohne Vorschau
                if (!ok && f != null) { f.CloseAsync(); f = null; }
                return f;
            }
        }

        // Rohdaten (BGRA, Zeilenabstand pitch) in eine Bitmap übertragen (Referenzbild für den Bericht)
        public static Bitmap ToBitmap(byte[] buf, int pitch, int w, int h)
        {
            Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppRgb);
            BitmapData bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppRgb);
            try { for (int y = 0; y < h; y++) Marshal.Copy(buf, y * pitch, IntPtr.Add(bd.Scan0, y * bd.Stride), w * 4); }
            finally { bmp.UnlockBits(bd); }
            return bmp;
        }

        // vom Renderthread: freien Puffer holen, füllen und als neuestes Bild abgeben
        public byte[] TakeSpare(int len)
        {
            lock (fl)
            {
                while (spare.Count > 0) { byte[] b = spare.Pop(); if (b.Length == len) return b; }
            }
            return new byte[len];
        }

        public void Publish(byte[] buf, int w, int h)
        {
            lock (fl)
            {
                if (latest != null && spare.Count < 3) spare.Push(latest);
                latest = buf; latestW = w; latestH = h;
            }
        }

        PreviewForm(GpuRun r)
        {
            Text = "Leos Minibench Rendertest: " + r.AdapterName + (r.Title.Length > 0 ? " (" + r.Title + ")" : "") + "   (Esc beendet)";
            BackColor = Color.Black; ForeColor = Color.White;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
            KeyPreview = true;
            ShowInTaskbar = true;
            StartPosition = FormStartPosition.Manual;
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            if (r.Preview == 2)
            {
                FormBorderStyle = FormBorderStyle.None;
                Bounds = Screen.PrimaryScreen.Bounds;
                TopMost = true;
            }
            else
            {
                int w = Math.Min(960, wa.Width - 80), h = w * 9 / 16 + 40;
                int off = 40 * (r.AdapterIndex % 4);
                Bounds = new Rectangle(wa.Left + 60 + off, wa.Top + 60 + off, w, h);
            }
            KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) { Esc = true; Close(); } };
            FormClosed += delegate { Gone = true; };
            tick = new System.Windows.Forms.Timer(); tick.Interval = Math.Max(15, 1000 / Math.Max(1, Math.Min(60, r.PreviewHz)));
            tick.Tick += delegate { if (TakeLatest() || Info != lastInfo) Invalidate(); };
            tick.Start();
        }

        // Fensterthread: neuestes Bild übernehmen, das bisher gezeigte wird wieder frei
        bool TakeLatest()
        {
            lock (fl)
            {
                if (latest == null) return false;
                if (shown != null && spare.Count < 3) spare.Push(shown);
                shown = latest; shownW = latestW; shownH = latestH; latest = null;
                return true;
            }
        }

        public void CloseAsync()
        {
            try { if (!Gone && IsHandleCreated) BeginInvoke(new MethodInvoker(delegate { try { Close(); } catch { } })); } catch { }
        }

        protected override void OnPaintBackground(PaintEventArgs e) { }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Color.Black);
            byte[] img = shown;
            if (img != null && shownW > 0 && shownH > 0)
            {
                Rectangle dst = FitImage(ClientSize.Width, ClientSize.Height, shownW, shownH, 28);
                BITMAPINFOHEADER bi = new BITMAPINFOHEADER();
                bi.biSize = Marshal.SizeOf(typeof(BITMAPINFOHEADER)); bi.biWidth = shownW; bi.biHeight = -shownH; bi.biPlanes = 1; bi.biBitCount = 32; bi.biCompression = 0;
                IntPtr hdc = g.GetHdc();
                try
                {
                    // verkleinern mit HALFTONE (sauber), vergrößern mit COLORONCOLOR (schnell)
                    if (dst.Width < shownW) { SetStretchBltMode(hdc, 4); SetBrushOrgEx(hdc, 0, 0, IntPtr.Zero); } else SetStretchBltMode(hdc, 3);
                    StretchDIBits(hdc, dst.X, dst.Y, dst.Width, dst.Height, 0, 0, shownW, shownH, img, ref bi, 0, 0x00CC0020);
                }
                finally { g.ReleaseHdc(hdc); }
            }
            lastInfo = Info;
            TextRenderer.DrawText(g, lastInfo + "   ·   Esc beendet", font, new Rectangle(8, ClientSize.Height - 26, ClientSize.Width - 16, 24), Color.Gainsboro, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) { try { tick.Stop(); tick.Dispose(); } catch { } lock (fl) { latest = null; shown = null; spare.Clear(); } font.Dispose(); }
            base.Dispose(disposing);
        }
    }
}
