using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using Thread = System.Threading.Thread;
using System.Windows.Forms;

// Steuerelemente in DiagGui_Steuerelemente.cs, Modelle in DiagGui_Modelle.cs,
// Vergleichsseite in DiagGui_Vergleich.cs, Versions- und Änderungsseite in DiagGui_Seiten.cs.
public partial class DiagGui : Form
{
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", SetLastError = true)] static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
    [DllImport("shcore.dll", SetLastError = true)] static extern int SetProcessDpiAwareness(int awareness);
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
    const int DWMWCP_ROUND = 2;
    [DllImport("uxtheme.dll", EntryPoint = "#135", SetLastError = true)] static extern int SetPreferredAppMode(int appMode);
    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr hWnd, string pszSubAppName, string pszSubIdList);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern bool FlashWindow(IntPtr h, bool invert);

    string psExe, script, cpDir, dataDir, dbDir, version;
    string[] disks;   // Nummer|Name|Bus|Medium|Größe|Buchstaben|USB
    Process proc;
    ConcurrentQueue<string> queue = new ConcurrentQueue<string>();
    Timer timer;
    volatile bool exited, outEof;
    DateTime exitSeen;
    bool running, done, gotDone, cancelled;
    string htmlPath = "", outDir = "", kiPath = "", kurzPath = "";
#pragma warning disable 414
    int nK, nW, nI, cntK, cntW, cntI, testsOk, benchWarn, benchCount;
    Dictionary<string, ListViewItem> benchHeads = new Dictionary<string, ListViewItem>();
    List<DbEntry> db = new List<DbEntry>();
    Font wsBold;

    Panel setupView, runView, content, head, body, contentHost;
    FlowLayoutPanel left;
    Button btnThemeToggle;
    Badge badgeSensStatus;
    List<NavItem> nav = new List<NavItem>();
    List<Control> pages = new List<Control>();
    int curPage;
#pragma warning restore 414

    // Diagnose
    RadioButton rbSchnell, rbVoll, rbCustom;
    Label lblDiagProfil;
    string[] diagKeys = new string[] { "Ereignisse", "Updatesuche", "Integritaet", "Defender", "SmartLang", "Netzwerk", "RamTest", "Energieanalyse" };
    string[] diagText = new string[] {
        "Ereignisprotokolle, Bluescreens, Absturzabbilder, Zuverlässigkeit",
        "Nach ausstehenden Windows-Updates suchen (bis 3 Minuten)",
        "Dateisystem-Onlinescan, DISM ScanHealth, sfc /verifyonly (nur prüfen)",
        "Microsoft Defender Schnellscan",
        "SMART-Langtest aller Laufwerke (SSD meist < 15 Min., HDD Stunden)",
        "Netzwerktest: Ping, DNS, HTTPS, Download",
        "RAM-Mustertest unter Windows",
        "Energieeffizienzanalyse (60 s) und DxDiag-Bericht" };
    CheckBox[] diagChk;
    CheckBox chkInstall, chkMem;
    ComboBox cmbDays, cmbSmartMax;
    static readonly int[] smartMinutes = new int[] { 30, 60, 90, 120, 180, 240, 360 };
    // Hilfswerkzeuge (PawnIO, smartmontools per winget): je Gerät entfernen, behalten oder jedes Mal fragen (Geraete.json)
    string deviceId = "";
    ComboBox cmbKeep;
    CheckBox chkGpuWahl;
    // GPU-Rendertest (ab v2.6): Auflösung und Anzeige, auf den Seiten Benchmark und Lasttest gleich eingestellt
    ComboBox cmbGpuRes, cmbGpuShow, cmbLGpuRes, cmbLGpuShow;
    bool syncGpu;
    // Auflösung, Anzeige und Grafikeinheit des Rendertests, je Seite in derselben Reihenfolge (einzelne können null sein)
    ComboBox[] GpuCombosBench() { return new ComboBox[] { cmbGpuRes, cmbGpuShow, cmbGpuSel }; }
    ComboBox[] GpuCombosLast() { return new ComboBox[] { cmbLGpuRes, cmbLGpuShow, cmbLGpuSel }; }
    // Auswahl paarweise übernehmen: nach[i] bekommt den Index von von[i]; fehlende Listen und ungültige Indizes bleiben unberührt
    public static void CopySelection(ComboBox[] von, ComboBox[] nach)
    {
        if (von == null || nach == null) return;
        for (int i = 0; i < von.Length && i < nach.Length; i++)
        {
            ComboBox a = von[i], b = nach[i];
            if (a == null || b == null || a.SelectedIndex < 0 || a.SelectedIndex >= b.Items.Count) continue;
            if (b.SelectedIndex != a.SelectedIndex) b.SelectedIndex = a.SelectedIndex;
        }
    }
    // ab v2.65: Auswahl der Grafikeinheiten (Benchmark und Lasttest gleich), Liste vom Startskript (Win32_VideoController)
    public static string[] GpuNames = new string[0];
    // ab v2.8: Katalog des Moduls Optimierung (Zeilen K|... und E|... aus Get-OptGuiLines) und Domänenmitgliedschaft
    public static string[] OptKatalog = new string[0];
    public static bool DomainPc = false;
    ComboBox cmbGpuSel, cmbLGpuSel;
    List<string> gpuSelValues = new List<string>();
    // Schneller Modus (ab v2.6): parallele Prüfungen der Diagnose
    CheckBox chkFast;
    GroupHeader diagToggle;
    FlowLayoutPanel diagBody;
    Label lblPar;
    Dictionary<string, string[]> parJobs = new Dictionary<string, string[]>();
    List<string> parOrder = new List<string>();
    // Benchmark
    string[] benchKeys = new string[] { "CPU", "RAM", "GPU", "Disk", "WinSAT" };
    string[] benchText = new string[] { "Prozessor", "Arbeitsspeicher", "Grafik", "Laufwerke", "WinSAT-Leistungsbewertung" };
    CheckBox[] benchChk;
    CheckedListBox clbDisks, clbCompare;
    List<string> diskNums = new List<string>();
    List<DbEntry> refItems = new List<DbEntry>(), cmpItems = new List<DbEntry>();
    // Lasttest
    CheckBox chkLCpu, chkLRam, chkLGpu, chkLDisk;
    ComboBox cmbLCpu, cmbLRam, cmbLGpu, cmbLDisk, cmbLRamPct, cmbLDiskDrive, cmbLAbortCpu, cmbLAbortGpu;
    // Sensoren (Live-Seite)
    NavItem navSens, navDb, navChg, navTools;
    Process liveProc;
    ConcurrentQueue<string> liveQueue = new ConcurrentQueue<string>();
    Timer liveTimer;
    volatile bool liveExited, liveEof;
    DateTime liveExitSeen;
    bool liveRunning, liveStopping;
    DateTime liveStopAt;
    Button btnLive, btnSensTools, btnSensSave;
    ComboBox cmbDriver;
    int psuWattage = 650;
    string psuRating = "80 PLUS Bronze";
    Label lblSensTools, lblSensInfo;
    SensorChart chartLive, chartRun;
    ListView lvSens;
    Dictionary<int, ListViewItem> sensItems = new Dictionary<int, ListViewItem>();
    Dictionary<int, double[]> sensMinMax = new Dictionary<int, double[]>();
    Dictionary<int, string> sensUnit = new Dictionary<int, string>();
    List<string> sensNames = new List<string>();
    List<string> sensRows = new List<string>();
    Dictionary<string, ListViewGroup> sensGroups = new Dictionary<string, ListViewGroup>();
    Label lblRunSens;
    // Reparatur
    string[] repKeys = new string[] {
        "DismRestore", "Sfc", "Komponentenbereinigung", "Dateisystem", "WindowsUpdate", "Netzwerk", "Temp", "WMI", "Zeit", "Druck",
        "Geraete", "Schnellstart", "Energieplaene", "Datentraegerbereinigung", "Leistungszaehler", "Leerlaufaufgaben", "ShaderCache", "UpdateDownloads", "Absturzabbilder", "Prefetch",
        "PaketCache", "Wiederherstellungspunkte" };
    string[] repText = new string[] {
        "Komponentenspeicher prüfen und reparieren (DISM ScanHealth, bei Bedarf RestoreHealth)",
        "Systemdateien reparieren (sfc /scannow, nach DISM)",
        "Komponentenspeicher bereinigen (DISM StartComponentCleanup, gibt Platz frei)",
        "Dateisystemfehler beheben (Onlinescan, SpotFix, Systemlaufwerk beim Neustart)",
        "Windows Update zurücksetzen (Dienste, SoftwareDistribution, catroot2)",
        "Netzwerk zurücksetzen (DNS-Cache, Winsock, TCP/IP), Neustart nötig",
        "Temporäre Dateien löschen (älter als 2 Tage, Übermittlungsoptimierung, Fehlerberichte)",
        "WMI-Repository prüfen und bei Bedarf reparieren",
        "Windows-Zeit neu synchronisieren",
        "Druckwarteschlange leeren und Druckspooler neu starten",
        "Geräte neu erkennen lassen (pnputil /scan-devices)",
        "Schnellstart deaktivieren (hilft bei Abstürzen nach dem Einschalten)",
        "Energiesparpläne auf Standard zurücksetzen (eigene Pläne werden vorher gesichert)",
        "Datenträgerbereinigung (cleanmgr mit allen Kategorien außer Downloads)",
        "Leistungszähler aus der Sicherung neu aufbauen (lodctr /r)",
        "Aufgeschobene Windows-Wartungsaufgaben starten (ProcessIdleTasks)",
        "DirectX-, OpenGL-, Intel- und AMD-Shader-Caches leeren",
        "SoftwareDistribution-Download-Ordner leeren (installierte Updates bleiben erhalten)",
        "CrashDumps, MSOCache, RetailDemo und Treiberreste leeren",
        "Prefetch-Ordner leeren (Windows baut die Daten danach neu auf)",
        "Paket-Cache von Installationsprogrammen leeren (Package Cache)",
        "Alte Schattenkopien auf dem Systemlaufwerk löschen" };
    int[] repMinutes = new int[] { 20, 12, 15, 5, 2, 1, 3, 2, 1, 1, 1, 1, 1, 10, 1, 1, 1, 1, 1, 1, 1, 1 };
    CheckBox[] repChk;
    CheckBox chkRestorePoint;
    // Datenbank
    ListView lvDb;
    Label lblDbPath;
    // Modulverträge und Änderungsprotokoll
    Dictionary<string, string[]> modInfo = new Dictionary<string, string[]>();   // Name -> Titel, Kurz, Admin, Risiko, Neustart
    List<ContractStep> steps = new List<ContractStep>();
    string[] repRisk = new string[0], repGroup = new string[0];
    bool[] repDefault = new bool[0], repUsual = new bool[0];
    string[] repRestart = new string[0];
    Dictionary<string, GroupHeader> repCatCount = new Dictionary<string, GroupHeader>();
    Dictionary<string, Control> repCatBody = new Dictionary<string, Control>();
    Dictionary<string, GroupHeader> repCatToggle = new Dictionary<string, GroupHeader>();
    string changeDir = "";
    List<ChangeEntry> changes = new List<ChangeEntry>();
    ListView lvChg;
    Button btnUndo;
    // Fuß
    Label lblSel;
    LinkLabel lnkAblage;
    Action footLayout = delegate { };
    CheckBox chkAnon;
    Button btnStart;
    // ab v2.7: Datenpflege beim Start (vom Skript gesetzt) und Schaltfläche Aufräumen auf der Seite Vergleichsdatenbank
    public static string DatenpflegeInfo = "";
    Label lblDbClean;
    Button btnDbClean;
    // ab v2.7: Seite Versionen (Verweis oben rechts im Kopf, keine eigene Schaltfläche in der Modulliste)
    int versionPage = -1;

    // Hinweise beim Überfahren mit der Maus (ab v2.7): kurze Erklärung zu jedem Bedienelement
    ToolTip tip = NewTip();
    static ToolTip NewTip()
    {
        ToolTip t = new ToolTip(); t.AutoPopDelay = 30000; t.InitialDelay = 450; t.ReshowDelay = 150; t.ShowAlways = true;
        return t;
    }
    // Text für den Hinweis umbrechen (höchstens rund 90 Zeichen je Zeile), vorhandene Zeilenumbrüche bleiben
    public static string WrapTip(string s)
    {
        if (String.IsNullOrEmpty(s)) return "";
        StringBuilder b = new StringBuilder();
        foreach (string para in s.Replace("\r\n", "\n").Split('\n'))
        {
            if (b.Length > 0) b.Append("\r\n");
            int col = 0;
            foreach (string w in para.Split(' '))
            {
                if (w.Length == 0) continue;
                if (col > 0 && col + 1 + w.Length > 90) { b.Append("\r\n"); col = 0; }
                else if (col > 0) { b.Append(' '); col++; }
                b.Append(w); col += w.Length;
            }
        }
        return b.ToString();
    }
    void Tip(Control c, string text) { if (c != null && !String.IsNullOrEmpty(text)) tip.SetToolTip(c, WrapTip(text)); }

    // Ablauf
    Button btnStopWait, btnSkipStep, btnCancel, btnHtml, btnFolder, btnNew, btnKi, btnExportRun;
    Label lblStep, lblCounter, lblSub, lblResult;
    FlatBar barAll, barSub;
    StatCard cardK, cardW, cardI, cardT;
    TabStrip tabs;
    ListView lvFind, lvTests, lvBench;
    TextBox txtLog;

    public static void Run(string psExe, string script, string cpDir, string dataDir, string version, string[] disks, string[] contract)
    {
        Run(psExe, script, cpDir, dataDir, version, disks, contract, "");
    }

    static void EnableDpi()
    {
        try { if (SetProcessDpiAwarenessContext((IntPtr)(-4))) return; } catch { }
        try { if (SetProcessDpiAwareness(2) == 0) return; } catch { }
    }

    public static void Run(string psExe, string script, string cpDir, string dataDir, string version, string[] disks, string[] contract, string deviceId)
    {
        IntPtr con = IntPtr.Zero; bool wasVisible = false;
        EnableDpi();
        try { using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) if (g.DpiX > 0) UI.DpiScale = g.DpiX / 96.0f; } catch { }
        AppSymbol.SetAppId();
        try { Application.EnableVisualStyles(); } catch { }
        try { Application.SetCompatibleTextRenderingDefault(false); } catch { }
        try { con = GetConsoleWindow(); if (con != IntPtr.Zero) { wasVisible = IsWindowVisible(con); ShowWindow(con, 0); } } catch { }
        try { DiagGui g = new DiagGui(psExe, script, cpDir, dataDir, version, disks, contract, deviceId); Application.Run(g); }
        finally { if (con != IntPtr.Zero && wasVisible) ShowWindow(con, 5); }
    }

    static Label Lbl(string text, float size, bool bold, Color color)
    {
        Label l = new Label(); l.Text = text; l.AutoSize = true; l.ForeColor = color; l.BackColor = Color.Transparent; l.UseMnemonic = false;
        l.Font = new Font(bold ? "Segoe UI Semibold" : "Segoe UI", size); return l;
    }

    // Ablage kurz: die letzten zwei Ordner des Datenordners ("LMB\Minibench-Daten"), der volle Pfad steht im Hinweis
    public static string AblageKurz(string dir)
    {
        string d = (dir ?? "").TrimEnd('\\', '/');
        if (d.Length == 0) return "Ablage: kein Datenordner";
        string[] parts = d.Split(new char[] { '\\', '/' }, StringSplitOptions.RemoveEmptyEntries);
        string kurz = parts.Length >= 2 ? parts[parts.Length - 2] + "\\" + parts[parts.Length - 1] : d;
        return "Ablage: " + (parts.Length > 2 ? "...\\" : "") + kurz;
    }

    static Label SideHead(string text)
    {
        Label l = Lbl(text.ToUpperInvariant(), 8.5f, true, UI.Muted); return l;
    }

    static string OsName()
    {
        try
        {
            using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
            {
                string pn = Convert.ToString(k.GetValue("ProductName")); string dv = Convert.ToString(k.GetValue("DisplayVersion"));
                int build = 0; int.TryParse(Convert.ToString(k.GetValue("CurrentBuildNumber")), out build);
                if (build >= 22000) pn = pn.Replace("Windows 10", "Windows 11");
                return (pn + " " + dv).Trim();
            }
        }
        catch { return "Windows"; }
    }

    public DiagGui(string psExe, string script, string cpDir, string dataDir, string version, string[] disks, string[] contract) : this(psExe, script, cpDir, dataDir, version, disks, contract, "") { }

    public DiagGui(string psExe, string script, string cpDir, string dataDir, string version, string[] disks, string[] contract, string deviceId)
    {
        using (Graphics g = CreateGraphics())
        {
            if (g.DpiX > 0) UI.DpiScale = g.DpiX / 96.0f;
        }
        this.deviceId = deviceId ?? "";
        this.psExe = psExe; this.script = script; this.cpDir = cpDir; this.dataDir = dataDir ?? ""; this.version = version ?? "";
        this.disks = disks ?? new string[0];
        dbDir = this.dataDir.Length > 0 ? Path.Combine(this.dataDir, "Datenbank") : "";
        changeDir = this.dataDir.Length > 0 ? Path.Combine(this.dataDir, "Änderungen") : "";
        ReadContract(contract ?? new string[0]);
        Text = "Leos Minibench " + this.version;
        AutoScaleDimensions = new SizeF(96f, 96f); AutoScaleMode = AutoScaleMode.Dpi;
        bool isDark = LoadThemePreference();
        LoadPsuPreference();
        UI.SetTheme(isDark);
        try { SetPreferredAppMode(isDark ? 2 : 0); } catch { }
        Font = new Font("Segoe UI", 9.75f);
        BackColor = UI.Bg; ForeColor = UI.Text;
        StartPosition = FormStartPosition.CenterScreen;
        Rectangle workArea = Screen.FromPoint(Cursor.Position).WorkingArea;
        int startW = Math.Min(UI.S(1320), (int)(workArea.Width * 0.96));
        int startH = Math.Min(UI.S(860), (int)(workArea.Height * 0.95));
        ClientSize = new Size(startW, startH);
        // ab v3.64 Mindestgröße, bei der jede Seite ohne waagerechte Bildlaufleiste auskommt: Seitenleiste 246, Ränder 90,
        // Gruppenbreite 780 und senkrechte Bildlaufleiste; höchstens 60 % der Arbeitsfläche, damit das Fenster bei hoher
        // Skalierung oder kleinem Bildschirm verkleinerbar bleibt (dann mit waagerechter Bildlaufleiste)
        MinimumSize = new Size(Math.Max(640, Math.Min(UI.S(1160), (int)(workArea.Width * 0.6))), Math.Min(UI.S(600), workArea.Height));
        try { Icon ic = AppSymbol.Get(); if (ic != null) Icon = ic; else Icon = Icon.ExtractAssociatedIcon(psExe); } catch { }
        try { int round = DWMWCP_ROUND; DwmSetWindowAttribute(Handle, DWMWA_WINDOW_CORNER_PREFERENCE, ref round, sizeof(int)); } catch { }

        // ab v3.64: flachere Kopfzeile (56 statt 74 px), Version nur noch in der Titelleiste und auf der Seite Info,
        // rechts Symbolknöpfe für Farbschema und Info statt Emoji-Text und Verweis
        head = new Panel(); head.Dock = DockStyle.Top; head.Height = UI.S(56); head.BackColor = UI.Header;
        PictureBox logo = new PictureBox(); logo.Size = new Size(UI.S(36), UI.S(36)); logo.Location = new Point(UI.S(18), UI.S(10)); logo.SizeMode = PictureBoxSizeMode.Zoom; logo.BackColor = Color.Transparent;
        try { logo.Image = AppSymbol.Image(UI.S(36)); } catch { }
        Label t1 = Lbl("Leos Minibench", 13.5f, true, Color.White); t1.Location = new Point(UI.S(64), UI.S(6));
        Label t2 = Lbl(Environment.MachineName + "   ·   " + OsName(), 8.75f, false, Color.FromArgb(170, 182, 200)); t2.Location = new Point(UI.S(65), UI.S(31));
        head.Controls.Add(logo); head.Controls.Add(t1); head.Controls.Add(t2);
        FlowLayoutPanel hr = new FlowLayoutPanel(); hr.Dock = DockStyle.Right; hr.AutoSize = true; hr.FlowDirection = FlowDirection.RightToLeft; hr.WrapContents = false; hr.BackColor = Color.Transparent; hr.Padding = new Padding(0, UI.S(12), UI.S(14), 0);
        Button btnInfo = HeadButton(UI.IcoInfo);
        btnInfo.Click += delegate { if (setupView != null && setupView.Visible && versionPage >= 0) ShowPage(versionPage); };
        Tip(btnInfo, "Info und Versionshistorie: was sich von Version 1.0 bis " + this.version + " geändert hat.");
        hr.Controls.Add(btnInfo);
        btnThemeToggle = HeadButton(UI.IsDark ? UI.IcoSonne : UI.IcoMond);
        btnThemeToggle.Click += delegate { ToggleTheme(); };
        Tip(btnThemeToggle, UI.IsDark ? "Zu hellem Farbschema wechseln." : "Zu dunklem Farbschema wechseln.");
        hr.Controls.Add(btnThemeToggle);
        badgeSensStatus = new Badge("", "ok");
        badgeSensStatus.Margin = new Padding(UI.S(6), UI.S(5), 0, 0);
        Tip(badgeSensStatus, "Aktiver Sensormodus für Hardware-Telemetrie und Systemwerte.");
        hr.Controls.Add(badgeSensStatus);
        head.Controls.Add(hr);

        body = new Panel(); body.Dock = DockStyle.Fill; body.Padding = new Padding(UI.S(20), UI.S(16), UI.S(20), UI.S(14)); body.BackColor = UI.Bg;
        LoadDb();
        setupView = BuildSetup(); runView = BuildRun();
        FillPresets(true);
        UpdateSensStatusBadge();
        setupView.Dock = DockStyle.Fill; runView.Dock = DockStyle.Fill; runView.Visible = false;
        body.Controls.Add(runView); body.Controls.Add(setupView);
        Controls.Add(body); Controls.Add(head);

        FormClosing += OnClosing;
        // selbst hergestellte Verbindungen zum Netzlaufwerk (Kennwort) nicht über das Programmende hinaus bestehen lassen
        FormClosed += delegate { NasAblage.AlleTrennen(); };
        // gegen Flackern: Doppelpufferung für Formular, Panels und Listen; Laufansicht wird höchstens alle 250 ms aktualisiert
        DoubleBuffered = true;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        EnableDoubleBuffer(this);
        timer = new Timer(); timer.Interval = 250; timer.Tick += delegate { OnTick(); };
        StartLog.Phase("Fenster aufgebaut");
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        try { int round = DWMWCP_ROUND; DwmSetWindowAttribute(Handle, DWMWA_WINDOW_CORNER_PREFERENCE, ref round, sizeof(int)); } catch { }
        ApplyTitleBarTheme(UI.IsDark);
        ApplyNativeControlThemes();
    }

    void ApplyNativeControlThemes()
    {
        string subApp = UI.IsDark ? "DarkMode_Explorer" : "Explorer";
        try { SetPreferredAppMode(UI.IsDark ? 2 : 0); } catch { }
        if (content != null && content.IsHandleCreated) try { SetWindowTheme(content.Handle, subApp, null); } catch { }
        if (left != null && left.IsHandleCreated) try { SetWindowTheme(left.Handle, subApp, null); } catch { }
        if (lvDb != null && lvDb.IsHandleCreated) try { SetWindowTheme(lvDb.Handle, subApp, null); } catch { }
        if (lvSens != null && lvSens.IsHandleCreated) try { SetWindowTheme(lvSens.Handle, subApp, null); } catch { }
        if (lvChg != null && lvChg.IsHandleCreated) try { SetWindowTheme(lvChg.Handle, subApp, null); } catch { }
        if (clbDisks != null && clbDisks.IsHandleCreated) try { SetWindowTheme(clbDisks.Handle, subApp, null); } catch { }
        if (clbCompare != null && clbCompare.IsHandleCreated) try { SetWindowTheme(clbCompare.Handle, subApp, null); } catch { }
        if (txtLog != null && txtLog.IsHandleCreated) try { SetWindowTheme(txtLog.Handle, subApp, null); } catch { }
        ApplyNativeThemeRecursive(this, subApp);
    }

    void ApplyNativeThemeRecursive(Control c, string subApp)
    {
        if (c == null) return;
        if (c.IsHandleCreated)
        {
            if (c is ScrollableControl || c is ListView || c is TextBoxBase || c is ListBox)
            {
                try { SetWindowTheme(c.Handle, subApp, null); } catch { }
            }
        }
        foreach (Control child in c.Controls)
        {
            ApplyNativeThemeRecursive(child, subApp);
        }
    }

    public void EnableDarkListView(ListView lv)
    {
        if (lv == null) return;
        lv.OwnerDraw = true;
        lv.BackColor = UI.Panel;
        lv.ForeColor = UI.Text;
        lv.DrawColumnHeader += delegate(object s, DrawListViewColumnHeaderEventArgs e) {
            Color headerBg = UI.IsDark ? Color.FromArgb(28, 30, 32) : Color.FromArgb(248, 249, 251);
            using (SolidBrush b = new SolidBrush(headerBg)) e.Graphics.FillRectangle(b, e.Bounds);
            using (Pen pen = new Pen(UI.Line)) e.Graphics.DrawLine(pen, e.Bounds.Left, e.Bounds.Bottom - 1, e.Bounds.Right, e.Bounds.Bottom - 1);
            using (Font f = new Font("Segoe UI Semibold", 8.5f))
                TextRenderer.DrawText(e.Graphics, e.Header.Text.ToUpperInvariant(), f,
                    new Rectangle(e.Bounds.X + UI.S(8), e.Bounds.Y, e.Bounds.Width - UI.S(10), e.Bounds.Height),
                    UI.Muted, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        };
        lv.DrawItem += delegate(object s, DrawListViewItemEventArgs e) { e.DrawDefault = true; };
        lv.DrawSubItem += delegate(object s, DrawListViewSubItemEventArgs e) { e.DrawDefault = true; };
        if (lv.IsHandleCreated) try { SetWindowTheme(lv.Handle, UI.IsDark ? "DarkMode_Explorer" : "Explorer", null); } catch { }
    }

    void ApplyTitleBarTheme(bool dark)
    {
        if (!IsHandleCreated || Handle == IntPtr.Zero) return;
        int darkMode = dark ? 1 : 0;
        try
        {
            int hr = DwmSetWindowAttribute(Handle, 20, ref darkMode, sizeof(int));
            if (hr != 0)
            {
                DwmSetWindowAttribute(Handle, 19, ref darkMode, sizeof(int));
            }
        }
        catch { }
    }

    static Color HeadButtonBack() { return UI.IsDark ? Color.FromArgb(32, 35, 40) : Color.FromArgb(34, 44, 62); }
    static Color HeadButtonHover() { return UI.IsDark ? Color.FromArgb(48, 52, 60) : Color.FromArgb(52, 64, 86); }

    // Symbolknopf der Kopfzeile (Farbschema, Info)
    static Button HeadButton(string glyph)
    {
        Button b = new Button(); b.Text = glyph; b.Font = UI.SymbolFont(11f); b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderSize = 0;
        b.BackColor = HeadButtonBack(); b.ForeColor = Color.White; b.FlatAppearance.MouseOverBackColor = HeadButtonHover();
        b.Size = new Size(UI.S(34), UI.S(32)); b.Margin = new Padding(UI.S(6), 0, 0, 0); b.Cursor = Cursors.Hand; b.UseVisualStyleBackColor = false;
        return b;
    }

    string SettingsFile { get { return dataDir.Length > 0 ? Path.Combine(dataDir, "Einstellungen.json") : ""; } }

    bool DetectWindowsDarkTheme()
    {
        try
        {
            using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
            {
                if (k != null)
                {
                    object val = k.GetValue("AppsUseLightTheme");
                    if (val is int) return ((int)val) == 0;
                }
            }
        }
        catch { }
        return false;
    }

    bool LoadThemePreference()
    {
        try
        {
            if (SettingsFile.Length > 0 && File.Exists(SettingsFile))
            {
                System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
                Dictionary<string, object> d = js.DeserializeObject(File.ReadAllText(SettingsFile, Encoding.UTF8)) as Dictionary<string, object>;
                if (d != null && d.ContainsKey("DarkMode"))
                {
                    return Convert.ToBoolean(d["DarkMode"]);
                }
            }
        }
        catch { }
        return DetectWindowsDarkTheme();
    }

    void SaveThemePreference(bool dark)
    {
        try
        {
            if (SettingsFile.Length == 0) return;
            Dictionary<string, object> d = null;
            System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
            if (File.Exists(SettingsFile))
            {
                try { d = js.DeserializeObject(File.ReadAllText(SettingsFile, Encoding.UTF8)) as Dictionary<string, object>; } catch { }
            }
            if (d == null) d = new Dictionary<string, object>();
            d["DarkMode"] = dark;
            File.WriteAllText(SettingsFile, js.Serialize(d), Encoding.UTF8);
        }
        catch { }
    }

    void LoadPsuPreference()
    {
        try
        {
            if (SettingsFile.Length > 0 && File.Exists(SettingsFile))
            {
                System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
                Dictionary<string, object> d = js.DeserializeObject(File.ReadAllText(SettingsFile, Encoding.UTF8)) as Dictionary<string, object>;
                if (d != null)
                {
                    if (d.ContainsKey("PsuWattage")) psuWattage = Convert.ToInt32(d["PsuWattage"]);
                    if (d.ContainsKey("PsuRating")) psuRating = Convert.ToString(d["PsuRating"]);
                }
            }
        }
        catch { }
    }

    void ToggleTheme()
    {
        SetAppTheme(!UI.IsDark);
    }

    void SetAppTheme(bool dark)
    {
        UI.SetTheme(dark);
        try { SetPreferredAppMode(dark ? 2 : 0); } catch { }
        SaveThemePreference(dark);
        ApplyTitleBarTheme(dark);
        ApplyNativeControlThemes();
        if (btnThemeToggle != null)
        {
            btnThemeToggle.Text = dark ? UI.IcoSonne : UI.IcoMond;
            Tip(btnThemeToggle, dark ? "Zu hellem Farbschema wechseln." : "Zu dunklem Farbschema wechseln.");
        }

        SuspendLayout();
        try
        {
            BackColor = UI.Bg;
            ForeColor = UI.Text;
            ApplyThemeRecursive(this);
            ApplyDiagProfile();
            // ab v3.64: Warnfelder und gedämpfte Beschriftungen tragen eigene Farben
            foreach (Label w in new Label[] { lblAkku, lblRestoreWarn }) if (w != null) { w.ForeColor = UI.Warn; w.BackColor = UI.WarnBg; }
            UpdateLoadEnabled(); ThemeLog();
            if (barAll != null && !done) barAll.Fill = UI.Accent;
            if (barSub != null) barSub.Fill = UI.AccentActive;
        }
        finally
        {
            ResumeLayout(true);
            Invalidate(true);
        }
    }

    void ApplyThemeRecursive(Control c)
    {
        if (c == null) return;

        if (c == head)
        {
            c.BackColor = UI.Header;
        }
        else if (c == contentHost)
        {
            c.BackColor = UI.Line;
        }
        else if (c == content)
        {
            c.BackColor = UI.Panel;
            if (c.IsHandleCreated) try { SetWindowTheme(c.Handle, UI.IsDark ? "DarkMode_Explorer" : "Explorer", null); } catch { }
        }
        else if (c is NavItem)
        {
            c.BackColor = UI.Bg;
            c.Invalidate();
        }
        else if (c is FluentCard)
        {
            c.BackColor = UI.Panel;
            c.Invalidate();
        }
        else if (c is ToggleSwitch || c is Badge)
        {
            c.Invalidate();
        }
        else if (c is GroupHeader)
        {
            c.BackColor = UI.Panel;
            c.Invalidate();
        }
        else if (c is FlatBar)
        {
            c.Invalidate();
        }
        else if (c is StatCard)
        {
            c.BackColor = UI.Bg;
            c.Invalidate();
        }
        else if (c is TabStrip)
        {
            c.BackColor = UI.Bg;
            c.Invalidate();
        }
        else if (c is SensorChart)
        {
            c.BackColor = UI.Panel;
            c.Invalidate();
        }
        else if (c is ListView)
        {
            c.BackColor = UI.Panel;
            c.ForeColor = UI.Text;
            if (c.IsHandleCreated) try { SetWindowTheme(c.Handle, UI.IsDark ? "DarkMode_Explorer" : "Explorer", null); } catch { }
            c.Invalidate();
        }
        else if (c is RichTextBox)
        {
            c.BackColor = UI.Panel;
            c.ForeColor = UI.Text;
        }
        else if (c is TextBox)
        {
            if (c != txtLog)
            {
                c.BackColor = UI.Panel;
                c.ForeColor = UI.Text;
            }
        }
        else if (c is DarkComboBox || c is ComboBox)
        {
            c.BackColor = UI.Panel;
            c.ForeColor = UI.Text;
            c.Invalidate();
        }
        else if (c is CheckedListBox || c is ListBox)
        {
            c.BackColor = UI.Panel;
            c.ForeColor = UI.Text;
            if (c.IsHandleCreated) try { SetWindowTheme(c.Handle, UI.IsDark ? "DarkMode_Explorer" : "Explorer", null); } catch { }
            c.Invalidate();
        }
        else if (c is RadioButton && ((RadioButton)c).Appearance == Appearance.Button)
        {
            StyleSegment((RadioButton)c);
        }
        else if (c is CheckBox || c is RadioButton)
        {
            c.ForeColor = c.Enabled ? UI.Text : UI.Muted;
        }
        else if (c is LinkLabel)
        {
            LinkLabel ll = (LinkLabel)c;
            if (ll.LinkColor == Color.FromArgb(28, 29, 31) || ll.LinkColor == Color.FromArgb(245, 246, 247) || ll.LinkColor == Color.Black || ll.LinkColor == SystemColors.ControlText)
            {
                ll.LinkColor = UI.Text;
            }
            else
            {
                ll.LinkColor = UI.Accent;
            }
            ll.ActiveLinkColor = UI.AccentHover;
            ll.ForeColor = UI.Text;
        }
        else if (c is Button)
        {
            Button btn = (Button)c;
            if (btn.Parent != null && btn.Parent.Parent == head)
            {
                btn.BackColor = HeadButtonBack();
                btn.ForeColor = Color.White;
                btn.FlatAppearance.MouseOverBackColor = HeadButtonHover();
            }
            else if (btn is PrimaryButton || btn == btnHtml || btn == btnStart || (btnUndo != null && btn == btnUndo) || (btnDashboard != null && btn == btnDashboard))
            {
                btn.BackColor = UI.Accent;
                btn.ForeColor = UI.OnAccent;
                // Symbol im Knopf (Tag = Zeichen der Symbolschrift) in der neuen Schriftfarbe neu zeichnen
                string glyph = btn.Tag as string;
                if (btn.Image != null && !String.IsNullOrEmpty(glyph)) { Image old = btn.Image; btn.Image = UI.GlyphImage(glyph, UI.OnAccent, old.Width); old.Dispose(); }
                btn.FlatAppearance.MouseOverBackColor = UI.AccentHover;
                btn.FlatAppearance.MouseDownBackColor = UI.AccentActive;
            }
            else
            {
                btn.BackColor = UI.Panel;
                btn.ForeColor = UI.Text;
                btn.FlatAppearance.BorderColor = UI.Line;
                btn.FlatAppearance.MouseOverBackColor = UI.IsDark ? Color.FromArgb(45, 48, 52) : Color.FromArgb(243, 244, 246);
                btn.FlatAppearance.MouseDownBackColor = UI.IsDark ? Color.FromArgb(55, 58, 62) : Color.FromArgb(235, 237, 240);
            }
            btn.Invalidate();
        }
        else if (c is Label)
        {
            Label lbl = (Label)c;
            if ((lbl.Tag as string) == "accent") lbl.ForeColor = UI.Accent;
            else if (lbl.Parent != head && lbl.ForeColor != Color.White)
            {
                Color fc = lbl.ForeColor;
                if (fc == Color.FromArgb(28, 29, 31) || fc == Color.FromArgb(245, 246, 247) || fc == Color.Black || fc == SystemColors.ControlText || fc.ToArgb() == Color.Black.ToArgb())
                {
                    lbl.ForeColor = UI.Text;
                }
                else if (fc == Color.FromArgb(95, 99, 104) || fc == Color.FromArgb(156, 163, 175) || fc == Color.Gray)
                {
                    lbl.ForeColor = UI.Muted;
                }
            }
        }
        else if (c is Panel)
        {
            Color bg = c.BackColor;
            if (bg == Color.FromArgb(249, 249, 251) || bg == Color.FromArgb(24, 25, 26))
            {
                c.BackColor = UI.Bg;
            }
            else if (bg == Color.White || bg == Color.FromArgb(36, 37, 38))
            {
                c.BackColor = UI.Panel;
            }
            else if (bg == Color.FromArgb(229, 231, 235) || bg == Color.FromArgb(58, 59, 60))
            {
                c.BackColor = UI.Line;
            }
            if (((Panel)c).AutoScroll && c.IsHandleCreated)
            {
                try { SetWindowTheme(c.Handle, UI.IsDark ? "DarkMode_Explorer" : "Explorer", null); } catch { }
            }
        }

        foreach (Control child in c.Controls)
        {
            ApplyThemeRecursive(child);
        }
    }

    // DoubleBuffered ist bei Panels und ListViews geschützt; per Reflexion für alle Unterelemente setzen
    static void EnableDoubleBuffer(Control c)
    {
        if (c == null) return;
        if (!(c is TextBoxBase))
        {
            try { PropertyInfo p = typeof(Control).GetProperty("DoubleBuffered", BindingFlags.NonPublic | BindingFlags.Instance); if (p != null) p.SetValue(c, true, null); } catch { }
        }
        foreach (Control k in c.Controls) EnableDoubleBuffer(k);
    }

    // Text nur setzen, wenn er sich ändert (jede Zuweisung zeichnet das Element neu)
    static void SetText(Control c, string t) { if (c != null && c.Text != t) c.Text = t; }

    void LoadDb()
    {
        try { db = DbEntry.Load(dbDir); } catch { db = new List<DbEntry>(); }
        try { changes = ChangeEntry.Load(changeDir); } catch { changes = new List<ChangeEntry>(); }
    }

    void ReloadDb()
    {
        LoadDb();
        FillDbList();
        FillRefLists();
        FillChangeList();
        UpdateSensTools();
        if (lblDbPath != null) SetText(lblDbPath, NasAblage.AblageText(dataDir));
    }

    // Modulverträge übernehmen: Navigation und Seite Reparatur richten sich danach (ohne Vertrag gelten die festen Listen)
    void ReadContract(string[] lines)
    {
        foreach (string l in lines)
        {
            string[] x = l.Split('|');
            if (x.Length >= 7 && x[0] == "M") modInfo[x[1]] = new string[] { x[2], x[3], x[4], x[5], x[6] };
            else if (x.Length >= 11 && x[0] == "S")
            {
                ContractStep c = new ContractStep(); c.Module = x[1]; c.Key = x[2]; c.Typ = x[3]; c.Risiko = x[4]; c.Neustart = x[5]; c.Rueckgaengig = x[6];
                int m; int.TryParse(x[7], out m); c.Minuten = m; c.Vorauswahl = x[8] == "1"; c.Ueblich = x[9] == "1"; c.Text = x[10];
                if (x.Length >= 12) c.Gruppe = x[11];
                steps.Add(c);
            }
        }
        List<ContractStep> rep = steps.FindAll(delegate(ContractStep c) { return (c.Module == "Reparatur" || c.Module == "Wartung") && c.Typ == "Massnahme"; });
        if (rep.Count > 0)
        {
            repKeys = new string[rep.Count]; repText = new string[rep.Count]; repMinutes = new int[rep.Count]; repRestart = new string[rep.Count];
            repRisk = new string[rep.Count]; repGroup = new string[rep.Count]; repDefault = new bool[rep.Count]; repUsual = new bool[rep.Count];
            for (int i = 0; i < rep.Count; i++)
            {
                repKeys[i] = rep[i].Key; repText[i] = rep[i].Text; repMinutes[i] = rep[i].Minuten;
                repRestart[i] = rep[i].Neustart; repRisk[i] = rep[i].Risiko; repGroup[i] = rep[i].Gruppe; repDefault[i] = rep[i].Vorauswahl; repUsual[i] = rep[i].Ueblich;
            }
        }
        else
        {
            repRestart = new string[repKeys.Length]; for (int i = 0; i < repKeys.Length; i++) repRestart[i] = "";
            repRisk = new string[repKeys.Length]; repGroup = new string[repKeys.Length]; repDefault = new bool[repKeys.Length]; repUsual = new bool[repKeys.Length];
            for (int i = 0; i < repKeys.Length; i++) { repRisk[i] = ""; repGroup[i] = ""; repDefault[i] = i < 2; repUsual[i] = i < 2 || repKeys[i] == "Dateisystem" || repKeys[i] == "Temp" || repKeys[i] == "WMI"; }
        }
    }

    NavItem ModNav(string name, string title, string desc, string icon = "")
    {
        string[] mi; if (modInfo.TryGetValue(name, out mi)) { title = mi[0]; desc = mi[1]; }
        NavItem it = new NavItem(title, desc, icon);
        if (!String.IsNullOrEmpty(desc)) Tip(it, desc);
        return it;
    }

    // ------------------------------------------------------------ Einrichtung
    Panel BuildSetup()
    {
        Panel p = new Panel(); p.BackColor = UI.Bg;

        left = new FlowLayoutPanel(); left.Dock = DockStyle.Left; left.Width = UI.S(246); left.FlowDirection = FlowDirection.TopDown; left.WrapContents = false;
        left.BackColor = UI.Bg; left.Padding = new Padding(0, 0, UI.S(14), 0); left.AutoScroll = true;
        // ab v3.64 zwei Gruppen: ausführbare Module (mit Haken) und Werkzeugseiten (ohne Haken)
        Label lm = SideHead("Ablauf"); lm.Margin = new Padding(UI.S(4), 0, 0, UI.S(6)); left.Controls.Add(lm);
        nav.Add(ModNav("Diagnose", "Diagnose", "Inventar, Prüfungen, Ereignisse", UI.IcoDiag));
        nav.Add(ModNav("Benchmark", "Benchmark", "Wählbare Messungen mit Vergleich", UI.IcoCpu));
        nav.Add(ModNav("Lasttest", "Lasttest", "Komponenten und Dauer wählbar", UI.IcoFlame));
        nav.Add(ModNav("Wartung", "Wartung", "SFC, DISM, Bereinigung und Systempflege", UI.IcoWartung));
        nav.Add(ModNav("Optimierung", "Optimierung", "Windows Optimisation Pack, gruppiert", UI.IcoOpt));
        navTools = ModNav("Tools", "Tools", "Portable Werkzeuge und Schnellstarter", UI.IcoTools); navTools.HasCheck = false; nav.Add(navTools);
        navSens = ModNav("Sensoren", "Sensoren live", "Temperatur, Takt, Lüfter, Leistung", UI.IcoSens); navSens.HasCheck = false; nav.Add(navSens);
        navDb = new NavItem("Vergleichsdatenbank", db.Count + " gespeicherte Systeme", UI.IcoDb); navDb.HasCheck = false; Tip(navDb, "Vergleichsdatenbank aller gespeicherten Systeme verwalten und vergleichen."); nav.Add(navDb);
        navChg = new NavItem("Systemänderungen", "Protokoll und Rückgängig", UI.IcoChg); navChg.HasCheck = false; Tip(navChg, "Änderungsprotokoll: was Leos Minibench an diesem PC verändert hat, mit Rückgängig."); nav.Add(navChg);
        for (int i = 0; i < nav.Count; i++)
        {
            int idx = i;
            nav[i].Picked += delegate { ShowPage(idx); };
            nav[i].CheckedChanged += delegate { UpdateSummary(); };
            if (nav[i] == navTools) { Label lw = SideHead("Werkzeuge"); lw.Margin = new Padding(UI.S(4), UI.S(UI.Abstand4), 0, UI.S(6)); left.Controls.Add(lw); }
            left.Controls.Add(nav[i]);
        }
        nav[0].Checked = true;
        // ab v2.8 acht Einträge: bei kleinem Fenster mit senkrechter Bildlaufleiste schmaler statt waagerecht zu scrollen
        left.Layout += delegate { int w = left.ClientSize.Width - left.Padding.Horizontal - 2; if (w > UI.S(150)) foreach (NavItem n in nav) if (n.Width != w) n.Width = w; };

        content = new Panel(); content.Dock = DockStyle.Fill; content.BackColor = UI.Panel; content.Padding = new Padding(UI.S(UI.Seitenrand), UI.S(UI.Seitenrand), UI.S(UI.Seitenrand), UI.S(20)); content.AutoScroll = true;
        contentHost = new Panel(); contentHost.Dock = DockStyle.Fill; contentHost.BackColor = UI.Line; contentHost.Padding = new Padding(1);
        contentHost.Controls.Add(content);

        pages.Add(BuildDiagPage()); pages.Add(BuildBenchPage()); pages.Add(BuildLoadPage()); pages.Add(BuildRepairPage()); pages.Add(BuildOptPage()); pages.Add(BuildToolsPage()); pages.Add(BuildSensorPage()); pages.Add(BuildDbPage()); pages.Add(BuildChangePage()); versionPage = pages.Count; pages.Add(BuildVersionPage());
        // ab v3.64 einheitlicher Seitenrand: Seiten ohne Dock stehen an der Position des Innenabstands (vorher bei 0,0,
        // dort wirkte der Innenabstand des Bildlaufbereichs nicht und der Titel klebte am Rahmen)
        foreach (Control c in pages) { c.Visible = false; if (c.Dock == DockStyle.None) c.Location = new Point(UI.S(UI.Seitenrand), UI.S(UI.Seitenrand)); content.Controls.Add(c); }

        // ab v3.64 Fußleiste in zwei Zeilen: oben Module in Ablaufreihenfolge mit Gesamtschätzung, darunter Voreinstellung,
        // Ablage und KI-Datei; der Startknopf steht allein rechts und sagt, was er startet
        TableLayoutPanel foot = new TableLayoutPanel(); foot.Dock = DockStyle.Bottom; foot.Height = UI.S(76); foot.ColumnCount = 2; foot.RowCount = 2; foot.BackColor = UI.Bg; foot.Padding = new Padding(0, UI.S(10), 0, 0);
        foot.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); foot.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        foot.RowStyles.Add(new RowStyle(SizeType.AutoSize)); foot.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        lblSel = Lbl("", 10f, true, UI.Text); lblSel.Margin = new Padding(0, 0, 0, UI.S(6)); lblSel.AutoEllipsis = true;
        FlowLayoutPanel fo = new FlowLayoutPanel(); fo.AutoSize = true; fo.WrapContents = false; fo.BackColor = UI.Bg; fo.Margin = new Padding(0);
        Label lp = Lbl("Voreinstellung", UI.SchriftHinweis, false, UI.Muted); lp.Margin = new Padding(0, UI.S(6), UI.S(6), 0); fo.Controls.Add(lp);
        cmbPreset = Combo(180, new string[0], 0); cmbPreset.Margin = new Padding(0, UI.S(2), UI.S(4), 0); fo.Controls.Add(cmbPreset);
        btnPresetSave = UI.Secondary("Speichern ..."); btnPresetSave.Margin = new Padding(0, 0, UI.S(4), 0); fo.Controls.Add(btnPresetSave);
        btnPresetDel = UI.Secondary("Löschen"); btnPresetDel.Margin = new Padding(0, 0, UI.S(UI.Abstand5), 0); fo.Controls.Add(btnPresetDel);
        lnkAblage = new LinkLabel(); lnkAblage.AutoSize = true; lnkAblage.Font = new Font("Segoe UI", UI.SchriftHinweis); lnkAblage.LinkColor = UI.Accent; lnkAblage.ActiveLinkColor = UI.AccentHover;
        lnkAblage.Text = AblageKurz(this.dataDir); lnkAblage.Margin = new Padding(0, UI.S(7), UI.S(UI.Abstand4), 0); lnkAblage.AutoEllipsis = true; lnkAblage.LinkBehavior = LinkBehavior.HoverUnderline;
        lnkAblage.LinkClicked += delegate { if (this.dataDir.Length > 0) { try { Directory.CreateDirectory(this.dataDir); } catch { } OpenShell(this.dataDir); } };
        fo.Controls.Add(lnkAblage);
        chkAnon = Chk("Personenbezogene Daten für die KI-Auswertung entfernen", true); chkAnon.Margin = new Padding(0, UI.S(5), 0, 0);
        fo.Controls.Add(chkAnon);
        btnStart = UI.Primary("Start"); btnStart.Margin = new Padding(UI.S(UI.Abstand5), 0, 0, 0); btnStart.MinimumSize = new Size(UI.S(150), UI.S(44)); btnStart.Anchor = AnchorStyles.Right;
        btnStart.Click += delegate { StartRun(); };
        cmbPreset.SelectedIndexChanged += delegate { if (!presetFilling) PresetPicked(); };
        btnPresetSave.Click += delegate { SavePresetDialog(); };
        btnPresetDel.Click += delegate { DeletePreset(); };
        foot.Controls.Add(lblSel, 0, 0); foot.Controls.Add(fo, 0, 1); foot.Controls.Add(btnStart, 1, 0); foot.SetRowSpan(btnStart, 2);
        footLayout = delegate
        {
            int avail = foot.ClientSize.Width - btnStart.Width - btnStart.Margin.Horizontal - UI.S(8);
            if (avail <= UI.S(80)) return;
            lblSel.MaximumSize = new Size(avail, UI.S(24));
            int rest = avail - lp.Width - lp.Margin.Horizontal - cmbPreset.Width - cmbPreset.Margin.Horizontal - btnPresetSave.Width - btnPresetSave.Margin.Horizontal - btnPresetDel.Width - btnPresetDel.Margin.Horizontal;
            int anonW = TextRenderer.MeasureText(chkAnon.Text, chkAnon.Font).Width + UI.S(24);
            // wird es eng, zuerst die Ablage kürzen, dann den Text der KI-Option
            int ablW = Math.Max(UI.S(60), Math.Min(TextRenderer.MeasureText(lnkAblage.Text, lnkAblage.Font).Width + UI.S(4), rest - anonW - lnkAblage.Margin.Horizontal));
            lnkAblage.AutoSize = false; lnkAblage.Size = new Size(ablW, UI.S(20));
            chkAnon.AutoSize = false; chkAnon.Size = new Size(Math.Max(UI.S(60), Math.Min(anonW, rest - ablW - lnkAblage.Margin.Horizontal)), UI.S(22)); chkAnon.AutoEllipsis = true;
        };
        foot.Resize += delegate { footLayout(); };
        btnStart.SizeChanged += delegate { footLayout(); };

        p.Controls.Add(contentHost); p.Controls.Add(left); p.Controls.Add(foot);
        ShowPage(0);
        UpdateSummary();
        ApplySetupTips();
        return p;
    }

    // ------------------------------------------------------------ Hinweise beim Überfahren (ab v2.7)
    // Erklärt jedes Bedienelement: was es tut, wie lange es dauert und ob es etwas am PC verändert.
    static readonly Dictionary<string, string> diagTips = new Dictionary<string, string> {
        { "Ereignisse", "Liest die Ereignisprotokolle der gewählten Tage: Bluescreens mit Erklärung des Stoppcodes, unerwartete Abschaltungen (Kernel-Power 41), Absturzabbilder, Datenträger- und Hardwarefehler sowie den Zuverlässigkeitsindex von Windows. Nur lesend, etwa 1 Minute." },
        { "Updatesuche", "Fragt Windows Update nach ausstehenden Updates (bis 3 Minuten). Es wird nichts heruntergeladen oder installiert. Läuft bei paralleler Ausführung nebenher." },
        { "Integritaet", "Prüft das Dateisystem (Onlinescan), den Komponentenspeicher (DISM ScanHealth) und die Systemdateien (sfc /verifyonly). Nur prüfen, nichts reparieren: Reparaturen bietet das Modul Reparatur. Dauer etwa 10 bis 20 Minuten." },
        { "Defender", "Startet einen Schnellscan von Microsoft Defender und meldet Funde. Entfällt, wenn ein anderer Virenschutz aktiv ist. Läuft bei paralleler Ausführung nebenher." },
        { "SmartLang", "Startet in jedem Laufwerk den erweiterten SMART-Selbsttest (smartctl). SSDs brauchen meist unter 15 Minuten, Festplatten Stunden. Wie lange auf das Ergebnis gewartet wird, steht unten unter SMART-Langtest; der Test läuft im Laufwerk danach weiter." },
        { "Netzwerk", "Prüft Ping zum Router und ins Internet, Namensauflösung (DNS), eine HTTPS-Verbindung und die Download-Geschwindigkeit. Etwa 1 Minute, braucht die Leitung kurz für sich." },
        { "RamTest", "Schreibt Bitmuster in einen Teil des freien Arbeitsspeichers und liest sie zurück (Vollständig: 60 % in 3 Durchläufen, Schnell: 25 % in einem). Findet grobe RAM-Fehler; den ganzen Speicher prüft nur die Windows-Speicherdiagnose oder MemTest86." },
        { "Energieanalyse", "Energieeffizienzanalyse von Windows (powercfg /energy, 60 Sekunden) und DxDiag mit Grafik- und Treiberangaben. Beide Berichte liegen danach in Anhang.zip." } };
    static readonly Dictionary<string, string> benchTips = new Dictionary<string, string> {
        { "CPU", "Einzelkern und Mehrkern mit eigener Rechenlast (Punkte), AES-256 und SHA-256 über die Windows-Kryptografie (ein Thread) und ZIP-Kompression auf allen Threads. Dazu der Takt unter Einzel- und Mehrkernlast. Je Messung 5 Sekunden, im Kurzlauf 2." },
        { "RAM", "Lesen, Schreiben und Kopieren auf allen Threads über bis zu 1 GB sowie die Latenz zufälliger Zugriffe über 256 MB. Bewertet wird gegen den theoretischen Wert aus Takt und Kanalzahl." },
        { "GPU", "WinSAT DWM (Grafikspeicher-Durchsatz, Desktop-Komposition) und der eigene Rendertest mit Direct3D 11 auf jeder gewählten Grafikeinheit (Bilder/s, 1-%-Low, Punktzahl), dazu PCIe-Anbindung und Grafikspeicher. Je Grafikeinheit 6 s Aufwärmen und 20 s Messung ohne VSync; vorher prüft eine kurze Gegenprobe, ob eine Bildratengrenze im Treiber bremst." },
        { "Disk", "Sequentiell Lesen und Schreiben (1-MiB-Blöcke) und 4K zufällig (QD1, 8 Threads, Schreiben), jeweils ohne Windows-Cache. Die Testdatei (1 GB, im Kurzlauf 256 MB) wird danach gelöscht. Welche Laufwerke, steht in der Liste darunter." },
        { "WinSAT", "Vollständige Leistungsbewertung von Windows (winsat formal), 2 bis 5 Minuten. Auf Akku, per Remotedesktop und in virtuellen Maschinen oft nicht möglich." } };

    void ApplySetupTips()
    {
        string[] navTips = new string[] {
            "Diagnose: Inventar, Treiber, Sicherheit, Ereignisprotokolle und die gewählten Prüfungen. Verändert nichts am System. Haken setzen, damit das Modul beim Start läuft.",
            "Benchmark: misst Prozessor, Arbeitsspeicher, Grafik, Laufwerke und WinSAT und vergleicht mit der Referenz und früheren Läufen. Ab v2.7 mit Temperatur, Takt und Leistung je Messung im Bericht.",
            "Lasttest: belastet CPU, RAM, Grafik und Datenträger gleichzeitig mit eigener Dauer, zeichnet Kurven auf und weist Drosselung nach. Hier steckt ab v2.7 auch die Prüfung der CPU-Stabilität.",
            "Wartung: Standardreparaturen wie DISM und SFC sowie Systempflege. Verändert das System; vorher auf Wunsch ein Wiederherstellungspunkt. Jede Maßnahme zeigt ihre Risikostufe.",
            "Optimierung (ab v2.8): das Windows Optimisation Pack nativ, mit Sophia- und O&O-Einstellungen, in Kategorien einzeln wählbar. Ändern ist einzeln rücknehmbar, Eingriffe sichert der Wiederherstellungspunkt ab.",
            "Tools: Portable Hilfswerkzeuge wie Revo Uninstaller, MiniTool Partition Wizard, WizTree sowie Windows-Schnellstarter.",
            "Sensoren live: Temperatur, Takt, Lüfter, Spannung und Leistung laufend anzeigen und aufzeichnen. Kein Modul für den Start.",
            "Vergleichsdatenbank: alle gespeicherten Läufe, Vergleich mehrerer Systeme ohne neuen Benchmark, Import älterer Ordner und Aufräumen.",
            "Systemänderungen: was Leos Minibench an einem PC verändert hat, mit Vorher-Wert und Rückgängig." };
        for (int i = 0; i < nav.Count && i < navTips.Length; i++) Tip(nav[i], navTips[i]);
        // Diagnose
        Tip(rbVoll, "Alle Prüfungen der Liste, ca. " + DiagMinutes(diagVoll) + " Min., mit SMART-Langtest länger.");
        Tip(rbSchnell, "Inventar, Ereignisse, Updatesuche, Netzwerk und ein kurzer RAM-Test (25 % des freien RAM, ein Durchlauf), ca. " + DiagMinutes(diagSchnell) + " Min.");
        Tip(rbCustom, "Die Prüfungen unten frei wählen.");
        Tip(chkFast, "Lesende Prüfungen ohne Messcharakter (Updatesuche, Defender, Energieanalyse, Start des SMART-Langtests) laufen nebenher. Messungen wie RAM-Test, Netzwerk, Benchmark und Lasttest warten immer, bis alles andere fertig ist.");
        for (int i = 0; diagChk != null && i < diagChk.Length && i < diagKeys.Length; i++) { string t; if (diagTips.TryGetValue(diagKeys[i], out t)) Tip(diagChk[i], t); }
        Tip(chkInstall, "smartctl liefert SMART-Werte und den Langtest. Liegt es im Tools-Ordner des Datenordners, wird es von dort verwendet, sonst per winget geholt und nach dem Lauf entfernt (oder auf Wunsch behalten). Risikostufe Eingriff.");
        Tip(chkMem, "Plant die Windows-Speicherdiagnose für den nächsten Neustart ein. Sie prüft den gesamten Arbeitsspeicher außerhalb von Windows; das Ergebnis liest der nächste Lauf aus den Ereignissen.");
        Tip(cmbDays, "Zeitraum für Ereignisprotokolle, Bluescreens und Absturzabbilder.");
        Tip(cmbSmartMax, "So lange wartet der Lauf auf das Ergebnis des SMART-Langtests. Danach entsteht der Bericht ohne Langtest; der Test läuft im Laufwerk weiter.");
        // Benchmark
        for (int i = 0; benchChk != null && i < benchChk.Length && i < benchKeys.Length; i++) { string t; if (benchTips.TryGetValue(benchKeys[i], out t)) Tip(benchChk[i], t); }
        Tip(clbDisks, "Laufwerke für den Laufwerks-Benchmark. Gemessen wird auf dem Volume mit dem meisten freien Platz; USB-Datenträger sind zunächst abgewählt.");
        Tip(cmbGpuSel, "Welche Grafikeinheiten der Rendertest belastet: alle, nur die Grafikkarte, nur die Prozessorgrafik oder eine bestimmte. Gilt für Benchmark und Lasttest.");
        Tip(cmbGpuRes, "Auflösung des Rendertests. Bilder/s sind nur bei gleicher Auflösung vergleichbar, die Punktzahl auch über Auflösungen.");
        Tip(cmbGpuShow, "Fenster: Vorschau des Rendertests. Vollbild: erste Grafikeinheit im Vollbild. Ohne Anzeige: misst unsichtbar (Esc entfällt).");
        Tip(chkGpuWahl, "Bei Notebooks mit zwei Grafikeinheiten misst WinSAT nur die Einheit, die den Desktop ausgibt. Mit diesem Haken wird WinSAT kurz auf die Grafikkarte gestellt und gleich wieder zurück (steht im Änderungsprotokoll).");
        // Lasttest
        Tip(chkLCpu, "Alle logischen Prozessoren rechnen mit Ergebnisprüfung; Rechenfehler deuten auf Instabilität (Übertaktung, Spannung, Kühlung, Netzteil). Läuft in einem eigenen Prozess ohne Unterbrechungen. Mit Sensoren gibt es Takt- und Temperaturverlauf und den Drosselnachweis. Ersetzt ab v2.7 den CPU-Stabilitätstest der Diagnose.");
        Tip(chkLRam, "Mustertest über einen Teil des freien Arbeitsspeichers mit Bitfehlerprüfung. Neben der CPU-Last läuft er mit niedriger Priorität auf einem Viertel der Threads.");
        Tip(cmbLRamPct, "Anteil des freien Arbeitsspeichers, den der RAM-Test belegt. Mehr findet mehr Fehler, lässt Windows aber weniger Luft.");
        Tip(chkLGpu, "Eigener Rendertest mit Direct3D 11 als Dauerlast auf den gewählten Grafikeinheiten gleichzeitig: Bilder/s-Verlauf, Bildprüfung alle 30 Sekunden und Erkennung von Treiber-Resets.");
        Tip(chkLDisk, "Schreibt eine Testdatei (bis 4 GB), liest sie zurück und prüft jeden Block. Meldet Datenfehler, Ein-/Ausgabefehler und Controllerereignisse. Die Datei wird danach gelöscht.");
        Tip(cmbLDiskDrive, "Laufwerk für den Datenträgertest; es braucht mindestens 2 GB freien Platz.");
        foreach (ComboBox c in new ComboBox[] { cmbLCpu, cmbLRam, cmbLGpu, cmbLDisk }) Tip(c, "Dauer dieser Komponente. Alle gewählten Komponenten starten gleichzeitig, jede endet nach ihrer eigenen Dauer.");
        Tip(cmbLGpuSel, "Welche Grafikeinheiten der Rendertest belastet (gleich eingestellt wie im Benchmark).");
        Tip(cmbLGpuRes, "Auflösung des Rendertests (gleich eingestellt wie im Benchmark).");
        Tip(cmbLGpuShow, "Fenster, Vollbild oder ohne Anzeige für den Rendertest (gleich eingestellt wie im Benchmark).");
        Tip(cmbLAbortCpu, "Liegt die CPU-Temperatur über dieser Schwelle, endet der Test mit einem Befund. Automatisch: TjMax der CPU nach rund einer Minute (viele Notebooks laufen planmäßig an TjMax), sonst 100 °C. Feste Werte greifen nach rund 10 Sekunden.");
        Tip(cmbLAbortGpu, "Liegt die GPU-Temperatur rund 10 Sekunden über dieser Schwelle, endet der Test mit einem Befund.");
        // Reparatur
        for (int i = 0; repChk != null && i < repChk.Length && i < repKeys.Length; i++)
        {
            ContractStep cs = steps.Find(delegate(ContractStep c) { return (c.Module == "Reparatur" || c.Module == "Wartung") && c.Key == repKeys[i]; });
            StringBuilder t = new StringBuilder(repText[i]);
            if (cs != null)
            {
                t.Append("\r\nRisikostufe: ").Append(ContractStep.RiskLabel(cs.Risiko)).Append(cs.Risiko == "Aendern" ? " (protokolliert, auf der Seite Systemänderungen rücknehmbar)" : cs.Risiko == "Eingriff" ? " (nicht automatisch umkehrbar, Absicherung über den Wiederherstellungspunkt)" : "");
                t.Append("\r\nNeustart: ").Append(cs.Neustart == "immer" ? "nötig" : cs.Neustart == "moeglich" ? "kann nötig sein" : "nicht nötig");
                if (cs.Minuten > 0) t.Append("\r\nDauer: etwa ").Append(cs.Minuten).Append(" Min.");
            }
            Tip(repChk[i], t.ToString());
        }
        Tip(chkRestorePoint, "Legt vor den Reparaturen einen Systemwiederherstellungspunkt an. Er ist der Weg zurück für alle Eingriffe dieses Laufs.");
        // Sensoren
        Tip(btnLive, "Öffnet die Sensoren und zeigt die Werte laufend an. Während eines Laufs ist die Live-Ansicht aus.");
        Tip(btnSensTools, "Holt LibreHardwareMonitor und das PawnIO-Setup aus den offiziellen Releases und prüft sie mit festen SHA-256-Werten. Abgelegt wird nur im Tools-Ordner, installiert wird nichts.");
        Tip(btnSensSave, "Speichert alle Werte der Live-Ansicht als CSV unter Berichte\\Sensoren.");
        Tip(cmbDriver, "PawnIO ist der Treiber, den LibreHardwareMonitor für CPU-Temperatur, CPU-Takt, CPU-Leistung und Mainboard-Lüfter braucht. Standardmäßig aktiv für alle Messungen. Ein bereits installierter PawnIO bleibt immer unverändert.");
        Tip(cmbKeep, "Was nach dem Lauf mit PawnIO und smartmontools geschieht, die Leos Minibench installiert hat: nach dem Lauf entfernen (keine Reste) oder auf diesem PC behalten. Gespeichert je Gerät in Geraete.json.");
        // Vergleichsdatenbank, Änderungen, Fuß
        Tip(btnCompare, "Vergleicht die angehakten Systeme in einem HTML-Bericht (mindestens zwei).");
        Tip(btnDelete, "Entfernt die angehakten Einträge aus der Datenbank. Die Berichtsordner bleiben erhalten.");
        Tip(btnDbClean, "Datenpflege: verschiebt Lasttests vor v2.67 (andere Last, nicht vergleichbar), abgebrochene Läufe ohne Bericht und kurze Läufe (Funktionstest, Lasttest nach wenigen Sekunden beendet, Lauf ohne Messwert) sowie ungenutzte Teile von smartmontools nach Minibench-Daten\\Archiv. Gelöscht werden nur ältere Übersetzungen im Cache und Reste der Live-Ansicht; das Protokoll steht in Archiv\\Datenpflege.log.");
        Tip(btnUndo, "Nimmt die angehakten Änderungen zurück (nur Stufe Ändern und nur auf dem PC, auf dem sie entstanden sind).");
        Tip(lnkAblage, "Öffnet den Datenordner mit Berichten, Datenbank, Werkzeugen und Voreinstellungen: " + (dataDir.Length > 0 ? dataDir : "kein Datenordner"));
        Tip(chkAnon, "Ersetzt in der KI-Datei Benutzernamen, Seriennummern, Domäne und ähnliche persönliche Angaben durch Platzhalter, bevor sie an ein KI-Modell geht.");
        // Optimierung
        Tip(chkOptRestore, "Legt vor der Optimierung einen Systemwiederherstellungspunkt an. Er ist der Weg zurück für Eingriffe wie entfernte Apps und Zusatzfeatures.");
        Tip(btnOptCheck, "Liest für jeden Eintrag, ob er auf diesem PC schon so eingestellt ist (aktiv, teilweise, offen). Verändert nichts, dauert bis zu einer Minute.");
        Tip(btnOptTools, "Holt Display Driver Uninstaller (aus dem Optimisation Pack, feste Prüfsumme) und NVIDIA Profile Inspector in den Tools-Ordner. Installiert wird nichts.");
        Tip(btnOptAll, "Alle Kategorien auf- oder zuklappen.");
        for (int i = 0; i < optPresetButtons.Count; i++) Tip(optPresetButtons[i], optPresetTips[i]);
        foreach (OptItem it in optItems) Tip(it.Box, OptTipText(it));
        Tip(cmbPreset, "Gespeicherte Auswahl aller Seiten laden (Voreinstellungen.json im Datenordner, weitergebbar).");
        Tip(btnPresetSave, "Aktuelle Auswahl aller Seiten unter einem Namen speichern.");
        Tip(btnPresetDel, "Gewählte Voreinstellung löschen.");
    }

    void ApplyRunTips()
    {
        Tip(btnStopWait, "Beendet den laufenden Test vorzeitig (Lasttest, SMART-Wartezeit). Der Bericht entsteht trotzdem.");
        Tip(btnSkipStep, "Überspringt den aktuellen Diagnoseschritt oder Benchmark und setzt den Lauf sofort mit dem nächsten Schritt fort.");
        Tip(btnCancel, "Bricht den ganzen Lauf ab. Es entsteht nur ein Teilbericht.");
        Tip(btnHtml, "Öffnet den Bericht im Browser.");
        Tip(btnFolder, "Öffnet den Berichtsordner dieses Laufs (Bericht, KI-Dateien, Anhang.zip).");
        Tip(btnExportRun, "Exportiert diesen Durchlauf als gepackte .minibench-Datei für den Austausch oder das Archiv.");
        Tip(btnNew, "Zurück zur Auswahl für einen neuen Lauf.");
        Tip(btnKi, "Zeigt die KI-Datei im Explorer. Sie enthält Auftrag, Bericht und Rohdaten und lässt sich in ein KI-Modell hochladen.");
        Tip(cardK, "Kritische Befunde: Datenverlust oder Instabilität möglich, bald handeln.");
        Tip(cardW, "Warnungen: sollten behoben werden.");
        Tip(cardI, "Hinweise: zur Kenntnis, meist ohne Handlungsbedarf.");
        Tip(cardT, "Bestandene Tests im Verhältnis zu allen Tests dieses Laufs.");
        Tip(tabs, "Befunde: Ergebnisse nach Dringlichkeit. Tests: jede Prüfung mit Ergebnis. Leistung: Benchmark-Werte. Sensoren: Kurven von Benchmark und Lasttest. Protokoll: Ausgabe des Laufs.");
    }

    void ShowPage(int i)
    {
        curPage = i;
        for (int k = 0; k < nav.Count; k++) nav[k].Selected = (k == i);
        content.AutoScrollPosition = new Point(0, 0);
        for (int k = 0; k < pages.Count; k++) pages[k].Visible = (k == i);
        if (i == 2) UpdateLoadExtras();
        ApplyNativeControlThemes();
    }

    static CheckBox Chk(string text, bool on)
    {
        CheckBox c = new CheckBox(); c.Text = text; c.AutoSize = true; c.Checked = on; c.ForeColor = UI.Text;
        c.Font = new Font("Segoe UI", 9.5f);
        c.Margin = new Padding(UI.S(4), UI.S(3), 0, UI.S(3));
        return c;
    }

    static ComboBox Combo(int width, string[] items, int sel)
    {
        DarkComboBox c = new DarkComboBox(); c.Width = UI.S(width); c.Margin = new Padding(0, UI.S(1), UI.S(16), UI.S(1));
        foreach (string s in items) c.Items.Add(s);
        if (items.Length > 0) c.SelectedIndex = Math.Min(sel, items.Length - 1);
        return c;
    }

    // ab v3.64: Seitenkopf mit Titel, rechts daneben der Schalter "beim Start ausführen" (gekoppelt an den Haken der
    // Seitenleiste; vorher eine zweite Checkbox im Inhalt), darunter die Einleitung
    FlowLayoutPanel Page(string title, string hint, int idx)
    {
        FlowLayoutPanel f = new FlowLayoutPanel(); f.FlowDirection = FlowDirection.TopDown; f.WrapContents = false; f.AutoSize = true; f.BackColor = UI.Panel; f.Location = new Point(0, 0);
        FlowLayoutPanel tr = new FlowLayoutPanel(); tr.AutoSize = true; tr.WrapContents = false; tr.BackColor = UI.Panel; tr.Margin = new Padding(0);
        Label lt = Lbl(title, UI.SchriftTitel, true, UI.Text); lt.Margin = new Padding(0, 0, UI.S(UI.Abstand5), 0); tr.Controls.Add(lt);
        if (idx >= 0)
        {
            ToggleSwitch on = new ToggleSwitch(); on.Checked = nav[idx].Checked; on.Margin = new Padding(0, UI.S(6), UI.S(4), 0);
            Label lo = Lbl("beim Start ausführen", UI.SchriftText, false, UI.Text); lo.Margin = new Padding(0, UI.S(8), 0, 0); lo.Cursor = Cursors.Hand;
            lo.Click += delegate { on.Checked = !on.Checked; };
            on.CheckedChanged += delegate { nav[idx].Checked = on.Checked; };
            nav[idx].CheckedChanged += delegate { if (on.Checked != nav[idx].Checked) on.Checked = nav[idx].Checked; };
            Tip(on, "Schaltet das Modul für den nächsten Start ein oder aus (gleich wie der Haken in der Seitenleiste).");
            Tip(lo, "Schaltet das Modul für den nächsten Start ein oder aus (gleich wie der Haken in der Seitenleiste).");
            tr.Controls.Add(on); tr.Controls.Add(lo);
        }
        f.Controls.Add(tr);
        Label h = Lbl(hint, UI.SchriftText, false, UI.Muted); h.MaximumSize = new Size(UI.S(UI.Gruppenbreite), 0); h.Margin = new Padding(0, UI.S(UI.Abstand1), 0, UI.S(UI.Abstand2)); f.Controls.Add(h);
        return f;
    }

    static Label Section(string text)
    {
        Label l = Lbl(text, UI.SchriftAbschnitt, true, UI.Text); l.Margin = new Padding(0, UI.S(18), 0, UI.S(UI.Abstand2)); return l;
    }

    // Hinweis unter einem Element: mindestens 9 pt, höchstens Gruppenbreite
    static Label Hint(string text, int left)
    {
        Label l = Lbl(text, UI.SchriftHinweis, false, UI.Muted); l.MaximumSize = new Size(UI.S(UI.Gruppenbreite) - UI.S(left), 0);
        l.Margin = new Padding(UI.S(left), UI.S(2), 0, UI.S(UI.Abstand1)); return l;
    }

    // Option mit zwei Zeilen: kurze Bezeichnung, darunter eine kleinere Detailzeile; Etiketten (Risikostufe, Neustart) rechts
    // daneben. Ein Klick auf die Detailzeile schaltet die Option wie ein Klick auf ihren Text.
    Control Opt2(ButtonBase c, string detail, params Badge[] badges)
    {
        FlowLayoutPanel box = new FlowLayoutPanel(); box.FlowDirection = FlowDirection.TopDown; box.WrapContents = false; box.AutoSize = true; box.BackColor = UI.Panel;
        box.Margin = new Padding(0, UI.S(2), 0, UI.S(2));
        FlowLayoutPanel top = new FlowLayoutPanel(); top.AutoSize = true; top.WrapContents = false; top.BackColor = UI.Panel; top.Margin = new Padding(0);
        c.Margin = new Padding(UI.S(4), UI.S(2), 0, 0);
        top.Controls.Add(c);
        if (badges != null) foreach (Badge b in badges) if (b != null && b.Text.Length > 0) { BadgeTip(b); top.Controls.Add(b); }
        box.Controls.Add(top);
        if (!String.IsNullOrEmpty(detail))
        {
            Label d = Lbl(detail, UI.SchriftHinweis, false, UI.Muted); d.MaximumSize = new Size(UI.S(UI.Gruppenbreite - 24), 0);
            d.Margin = new Padding(UI.S(24), 0, 0, UI.S(2)); d.Cursor = Cursors.Hand;
            d.Click += delegate { if (!c.Enabled) return; CheckBox cb = c as CheckBox; RadioButton rb = c as RadioButton; if (cb != null && cb.AutoCheck) cb.Checked = !cb.Checked; else if (rb != null) rb.Checked = true; };
            c.EnabledChanged += delegate { d.ForeColor = c.Enabled ? UI.Muted : DisabledText(); };
            box.Controls.Add(d);
        }
        return box;
    }

    static FlowLayoutPanel Row()
    {
        FlowLayoutPanel r = new FlowLayoutPanel(); r.AutoSize = true; r.WrapContents = false; r.BackColor = UI.Panel; r.Margin = new Padding(UI.S(4), UI.S(2), 0, UI.S(2));
        return r;
    }

    static Label RowLabel(string text, int width)
    {
        Label l = Lbl(text, 9.75f, false, UI.Text); l.AutoSize = false; l.Width = UI.S(width); l.Height = UI.S(24); l.TextAlign = ContentAlignment.MiddleLeft; l.Margin = new Padding(0, UI.S(1), UI.S(6), UI.S(1));
        return l;
    }

    // ab v3.64: Auswahl als Segmentschalter (RadioButton mit Knopfdarstellung), gemeinsam umschaltbar mit dem Farbschema
    static void StyleSegment(RadioButton r)
    {
        r.Appearance = Appearance.Button; r.FlatStyle = FlatStyle.Flat; r.TextAlign = ContentAlignment.MiddleCenter;
        r.FlatAppearance.BorderColor = UI.Line; r.FlatAppearance.BorderSize = 1;
        r.FlatAppearance.CheckedBackColor = UI.AccentSoft;
        r.FlatAppearance.MouseOverBackColor = UI.IsDark ? Color.FromArgb(45, 48, 52) : Color.FromArgb(243, 244, 246);
        r.BackColor = UI.Panel; r.ForeColor = r.Checked ? (UI.IsDark ? UI.Accent : UI.AccentDark) : UI.Text;
        r.Font = new Font(r.Checked ? "Segoe UI Semibold" : "Segoe UI", UI.SchriftText);
    }

    public static Color DisabledText() { return UI.IsDark ? Color.FromArgb(120, 125, 135) : Color.FromArgb(160, 163, 168); }

    // Text der Vertragszeile in Bezeichnung und Detail teilen: "Titel (Detail)" -> Titel, Detail
    public static string[] SplitDetail(string text)
    {
        string t = (text ?? "").Trim();
        // ", Neustart nötig" steht seit v3.64 als Etikett daneben
        if (t.EndsWith(", Neustart nötig")) t = t.Substring(0, t.Length - ", Neustart nötig".Length);
        int k = t.IndexOf(" (");
        if (k > 0 && t.EndsWith(")") && t.IndexOf('(', k + 2) < 0) return new string[] { t.Substring(0, k), t.Substring(k + 2, t.Length - k - 3) };
        return new string[] { t, "" };
    }

    static Badge RiskBadge(string risiko)
    {
        string r = risiko ?? "";
        if (r.Length == 0 || r == "Lesen") return null;
        Badge b = new Badge(ContractStep.RiskLabel(r), UI.RiskLevel(r)); b.Tag = "risiko"; return b;
    }

    static Badge RestartBadge(string neustart)
    {
        Badge b = neustart == "immer" ? new Badge("Neustart", "skip") : neustart == "moeglich" ? new Badge("Neustart möglich", "skip") : null;
        if (b != null) b.Tag = "neustart";
        return b;
    }

    // Hinweis eines Etiketts nach seiner Art (Risikostufe, Neustart, verwaltet, Zustand)
    void BadgeTip(Badge b)
    {
        if (b == null) return;
        string k = b.Tag as string;
        if (k == "risiko") Tip(b, b.Level == "info" ? "Ändern: wird mit Vorher-Wert protokolliert und lässt sich auf der Seite Systemänderungen zurücknehmen." : "Eingriff: nicht automatisch umkehrbar; der Weg zurück ist der Wiederherstellungspunkt.");
        else if (k == "neustart") Tip(b, b.Text == "Neustart" ? "Wird erst nach einem Neustart vollständig wirksam." : "Kann einen Neustart brauchen, je nach Zustand des PCs.");
        else if (k == "verwaltet") Tip(b, "Berührt Gruppenrichtlinien oder zentrale Verwaltung; auf Domänen-PCs nicht in den Vorlagen.");
        else if (k == "zustand") Tip(b, "Zustand auf diesem PC, ermittelt mit Zustand prüfen oder beim letzten Lauf.");
    }

    // ab v3.65: Gruppen als abgerundete Karten (CardPanel) wie die Werkzeugkarten
    static Panel OptionCard(string categoryTitle, string icon, Control[] controls)
    {
        CardPanel card = new CardPanel();
        card.Margin = new Padding(0, UI.S(4), 0, UI.S(UI.Abstand2));
        // ab v3.64: alle Gruppen einer Seite gleich breit (vorher schrumpfte jede auf ihren Inhalt)
        card.MinimumSize = new Size(UI.S(UI.Gruppenbreite), 0);
        card.AutoSize = true;
        card.AutoSizeMode = AutoSizeMode.GrowAndShrink;

        FlowLayoutPanel inner = new FlowLayoutPanel();
        inner.FlowDirection = FlowDirection.TopDown;
        inner.WrapContents = false;
        inner.AutoSize = true;
        inner.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        inner.BackColor = UI.Panel;
        inner.Margin = new Padding(0);
        inner.Dock = DockStyle.Fill;

        // Symbol in der Symbolschrift (vorher in Segoe UI gezeichnet, dort erschien es als Punkt vor dem Titel)
        FlowLayoutPanel hr = new FlowLayoutPanel(); hr.AutoSize = true; hr.WrapContents = false; hr.BackColor = UI.Panel; hr.Margin = new Padding(0, 0, 0, UI.S(6));
        if (icon != null && icon.Length > 0)
        {
            Label li = new Label(); li.AutoSize = true; li.Text = icon; li.Font = UI.SymbolFont(11f); li.ForeColor = UI.Accent; li.Tag = "accent"; li.BackColor = Color.Transparent; li.Margin = new Padding(0, UI.S(2), UI.S(6), 0);
            hr.Controls.Add(li);
        }
        Label header = Lbl(categoryTitle, UI.SchriftGruppe, true, UI.Text); header.Margin = new Padding(0);
        hr.Controls.Add(header);
        inner.Controls.Add(hr);

        if (controls != null)
        {
            foreach (Control c in controls)
            {
                if (c != null) inner.Controls.Add(c);
            }
        }

        card.Controls.Add(inner);
        return card;
    }

    // Beliebigen Inhalt (Tabelle, Liste) in eine Karte der Gruppenbreite setzen
    static CardPanel Card(Control content)
    {
        CardPanel card = new CardPanel();
        card.Margin = new Padding(0, UI.S(4), 0, UI.S(UI.Abstand2));
        card.MinimumSize = new Size(UI.S(UI.Gruppenbreite), 0);
        card.AutoSize = true; card.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        content.Margin = new Padding(0); content.Dock = DockStyle.Fill;
        card.Controls.Add(content);
        return card;
    }

    Control BuildDiagPage()
    {
        FlowLayoutPanel f = Page("Diagnose", "Liest Hardware, Treiber, Sicherheit und Ereignisprotokolle aus, führt die gewählten Prüfungen durch und bewertet alles in einem Bericht. Die Prüfungen verändern nichts am System; gekennzeichnete Optionen nehmen Änderungen vor.", 0);
        if (File.Exists(Path.Combine(cpDir, "laufend.json")))
        {
            Label warn = Lbl("  Der letzte Lauf wurde nicht beendet (Absturz?). Die Absturzanalyse läuft beim nächsten Start automatisch zuerst.  ", 9.75f, true, UI.Crit);
            warn.BackColor = UI.CritBg; warn.Padding = new Padding(UI.S(6)); warn.Margin = new Padding(0, 0, 0, UI.S(8));
            f.Controls.Add(warn);
        }
        // ab v3.64 drei Profile als Segmentschalter; Funktionstest und Nur Absturzanalyse entfallen in der Oberfläche
        // (die Absturzanalyse läuft nach einem unterbrochenen Lauf ohnehin automatisch zuerst)
        f.Controls.Add(Section("Umfang"));
        rbVoll = new RadioButton(); rbSchnell = new RadioButton(); rbCustom = new RadioButton();
        FlowLayoutPanel seg = new FlowLayoutPanel(); seg.AutoSize = true; seg.WrapContents = false; seg.BackColor = UI.Panel; seg.Margin = new Padding(UI.S(4), 0, 0, UI.S(4));
        RadioButton[] rbs = new RadioButton[] { rbVoll, rbSchnell, rbCustom };
        string[] rt = new string[] { "Vollständig", "Schnell", "Benutzerdefiniert" };
        for (int i = 0; i < rbs.Length; i++) {
            rbs[i].Text = rt[i]; rbs[i].AutoSize = false; rbs[i].Size = new Size(UI.S(160), UI.S(34)); rbs[i].Margin = new Padding(0, 0, UI.S(6), 0);
            rbs[i].Cursor = Cursors.Hand; StyleSegment(rbs[i]);
            rbs[i].CheckedChanged += delegate { ApplyDiagProfile(); };
            seg.Controls.Add(rbs[i]);
        }
        f.Controls.Add(seg);
        lblDiagProfil = Hint("", 4); f.Controls.Add(lblDiagProfil);
        chkFast = Chk("Lesende Prüfungen parallel ausführen", false);
        chkFast.CheckedChanged += delegate { UpdateSummary(); };
        Control fastBox = Opt2(chkFast, "Updatesuche, Defender-Schnellscan, Energieanalyse und SMART-Langtest laufen nebenher. Messungen bleiben exklusiv, damit die Werte vergleichbar sind.");
        fastBox.Margin = new Padding(0, UI.S(UI.Abstand2), 0, 0); f.Controls.Add(fastBox);

        diagToggle = new GroupHeader("Prüfungen"); diagToggle.Margin = new Padding(0, UI.S(UI.Abstand3), 0, 0);
        Tip(diagToggle, "Klicken zeigt oder verbirgt die einzelnen Diagnoseprüfungen. Wer eine Prüfung ändert, wechselt zum Profil Benutzerdefiniert.");
        f.Controls.Add(diagToggle);

        diagBody = new FlowLayoutPanel(); diagBody.FlowDirection = FlowDirection.TopDown;
        diagBody.WrapContents = false; diagBody.AutoSize = true; diagBody.BackColor = UI.Panel;
        diagBody.Margin = new Padding(UI.S(UI.Abstand4), UI.S(UI.Abstand1), 0, UI.S(UI.Abstand1)); diagBody.Visible = false;

        diagChk = new CheckBox[diagKeys.Length];
        for (int i = 0; i < diagKeys.Length; i++) {
            int chkIdx = i;
            diagChk[i] = Chk(diagText[i], true);
            diagChk[i].Click += delegate {
                if (!rbCustom.Checked) {
                    rbCustom.Checked = true;
                    diagChk[chkIdx].Checked = !diagChk[chkIdx].Checked;
                }
            };
            diagChk[i].CheckedChanged += delegate { UpdateSummary(); };
            diagBody.Controls.Add(diagChk[i]);
        }
        diagBody.Controls.Add(Hint("Die CPU-Stabilität prüft das Modul Lasttest (Prozessor, ab 2 Min.): eigener Lastprozess, Rechenfehler, Takt- und Temperaturverlauf und Drosselnachweis.", 4));
        f.Controls.Add(diagBody);
        diagToggle.Toggled += delegate { diagBody.Visible = diagToggle.Expanded; };

        f.Controls.Add(Section("Optionen"));
        chkInstall = Chk("smartmontools bei Bedarf installieren oder aus dem Datenordner verwenden", true);
        chkMem = Chk("Windows-Speicherdiagnose beim nächsten Neustart einplanen", false);
        f.Controls.Add(OptionCard("Zusatzwerkzeuge und Speicherdiagnose", UI.IcoTools, new Control[] {
            Opt2(chkInstall, "Liegt smartctl im Tools-Ordner, wird es von dort verwendet, sonst per winget geholt und nach dem Lauf entfernt.", RiskBadge("Eingriff")),
            Opt2(chkMem, "Prüft den gesamten Arbeitsspeicher außerhalb von Windows; das Ergebnis liest der nächste Lauf.", RestartBadge("immer")) }));

        FlowLayoutPanel r = Row(); r.Controls.Add(RowLabel("Ereignisse der letzten", 170));
        cmbDays = Combo(110, new string[] { "3 Tage", "7 Tage", "14 Tage", "30 Tage", "60 Tage" }, 2); r.Controls.Add(cmbDays);
        FlowLayoutPanel rs = Row(); rs.Controls.Add(RowLabel("SMART-Langtest", 170));
        string[] sm = new string[smartMinutes.Length]; for (int i = 0; i < sm.Length; i++) sm[i] = "höchstens " + smartMinutes[i] + " Min. warten";
        cmbSmartMax = Combo(220, sm, 3); cmbSmartMax.SelectedIndexChanged += delegate { UpdateSummary(); }; rs.Controls.Add(cmbSmartMax);
        f.Controls.Add(OptionCard("Prüfzeiträume", UI.IcoDiag, new Control[] { r, rs, Hint("Danach entsteht der Bericht ohne Ergebnis des Langtests; der Test läuft im Laufwerk weiter.", 180) }));
        rbVoll.Checked = true;
        return f;
    }

    // Ereignisse, Updatesuche, Integritaet, Defender, SmartLang, Netzwerk, RamTest, Energieanalyse
    // (CPU-Stabilität ab v2.7 nur noch im Modul Lasttest)
    static readonly bool[] diagVoll = DiagPreset(true);
    static readonly bool[] diagSchnell = DiagPreset(false);
    static bool[] DiagPreset(bool full)
    {
        bool[] voll = new bool[] { true, true, true, true, true, true, true, true };
        bool[] schnell = new bool[] { true, true, false, false, false, true, true, false };
        return full ? voll : schnell;
    }

    // Geschätzte Minuten der Diagnose ohne Wartezeit auf den SMART-Langtest (Grundlage für Profiltext und Fußleiste)
    public static int DiagMinutes(bool[] sel)
    {
        int t = 0;
        int[] add = new int[] { 1, 2, 3, 1, 2, 1, 2, 2 };
        for (int i = 0; sel != null && i < sel.Length && i < add.Length; i++) if (sel[i]) t += add[i];
        return t;
    }

    // Schätzung der Diagnose für eine Auswahl, bei paralleler Ausführung abzüglich der nebenher laufenden Prüfungen
    // (ab v3.65 auch für die Zeile unter dem Profil; vorher zeigte sie ohne Abzug eine andere Zahl als die Seitenleiste)
    int DiagEstimate(bool[] sel)
    {
        int t = DiagMinutes(sel);
        // schneller Modus: Updatesuche, Defender und Energieanalyse laufen neben den übrigen Prüfungen
        if (chkFast != null && chkFast.Checked && chkFast.Enabled) { int par = (diagChk[1].Checked ? 2 : 0) + (diagChk[3].Checked ? 1 : 0) + (diagChk[7].Checked ? 2 : 0); t -= Math.Min(par, Math.Max(0, t - 1)); }
        return t;
    }

    void UpdateDiagSummary()
    {
        if (diagToggle == null || diagChk == null) return;
        int sel = 0;
        bool[] cur = new bool[diagChk.Length];
        for (int i = 0; i < diagChk.Length; i++) { cur[i] = diagChk[i] != null && diagChk[i].Checked; if (cur[i]) sel++; }
        string pName = rbVoll != null && rbVoll.Checked ? "Vollständig" : rbSchnell != null && rbSchnell.Checked ? "Schnell" : "Benutzerdefiniert";
        diagToggle.CountText = sel + " von " + diagChk.Length + " gewählt, Profil " + pName;
        if (lblDiagProfil != null)
        {
            string smart = cur.Length > 4 && cur[4] ? ", dazu das Warten auf den SMART-Langtest (höchstens " + SmartMax() + " Min.)" : "";
            string par = chkFast != null && chkFast.Checked ? " mit paralleler Ausführung" : "";
            string t = rbVoll != null && rbVoll.Checked ? "Alle " + diagChk.Length + " Prüfungen, ca. " + DiagEstimate(cur) + " Min." + par + smart
                : rbSchnell != null && rbSchnell.Checked ? "Inventar, Ereignisse, Updatesuche, Netzwerk und kurzer RAM-Test (25 % des freien RAM), ca. " + DiagEstimate(cur) + " Min." + par
                : "Prüfungen unten frei wählen, derzeit " + sel + " gewählt, ca. " + DiagEstimate(cur) + " Min." + par + smart;
            SetText(lblDiagProfil, t);
        }
    }

    void ApplyDiagProfile()
    {
        if (diagChk == null) return;
        bool custom = rbCustom.Checked;
        if (custom && diagBody != null)
        {
            diagBody.Visible = true;
            if (diagToggle != null) diagToggle.Expanded = true;
        }
        bool[] pick = rbVoll.Checked ? diagVoll : rbSchnell.Checked ? diagSchnell : null;
        for (int i = 0; i < diagChk.Length; i++)
        {
            if (pick != null) diagChk[i].Checked = pick[i];
            diagChk[i].AutoCheck = custom;
            diagChk[i].ForeColor = custom ? UI.Text : (UI.IsDark ? Color.FromArgb(195, 200, 210) : Color.FromArgb(80, 85, 95));
        }
        foreach (RadioButton r in new RadioButton[] { rbVoll, rbSchnell, rbCustom }) if (r != null) StyleSegment(r);
        UpdateDiagSummary();
        UpdateSummary();
    }

    // ab v3.64: Messungen mit kurzer Bezeichnung und Detailzeile, Laufwerke mit Ziel und freiem Platz, Referenz-Zustand neben der Liste
    static readonly string[] benchDetail = new string[] {
        "Einzel- und Mehrkern, AES-256, SHA-256, Kompression",
        "Lesen, Schreiben, Kopieren, Latenz",
        "Rendertest je Grafikeinheit (Bilder/s, 1-%-Low, Punktzahl), Speicherdurchsatz, Desktop-Komposition, PCIe",
        "sequentiell und 4K-Zufallszugriff, Auswahl unten",
        "Leistungsbewertung von Windows, 2 bis 5 Min." };

    Control BuildBenchPage()
    {
        FlowLayoutPanel f = Page("Benchmark", "Misst die Leistung der gewählten Komponenten und vergleicht sie mit der Referenz, mit früheren Läufen auf diesem PC und mit bereits geprüften Systemen.", 1);
        f.Controls.Add(Section("Messungen"));
        benchChk = new CheckBox[benchKeys.Length];
        for (int i = 0; i < benchKeys.Length; i++)
        {
            benchChk[i] = Chk(benchText[i], i < 4);
            benchChk[i].CheckedChanged += delegate { clbDisks.Enabled = benchChk[3].Checked; UpdateSummary(); };
            f.Controls.Add(Opt2(benchChk[i], benchDetail[i]));
        }
        f.Controls.Add(Section("Laufwerke"));
        clbDisks = new CheckedListBox(); clbDisks.CheckOnClick = true; clbDisks.Width = UI.S(UI.Gruppenbreite); clbDisks.BorderStyle = BorderStyle.FixedSingle; clbDisks.IntegralHeight = false; clbDisks.Margin = new Padding(UI.S(4), UI.S(2), 0, UI.S(4)); clbDisks.BackColor = UI.Panel; clbDisks.ForeColor = UI.Text;
        foreach (string d in disks)
        {
            string[] x = d.Split('|');
            if (x.Length < 7) continue;
            clbDisks.Items.Add(DiskLine(x), x[6] != "1" && x[5].Length > 0);
            diskNums.Add(x[0]);
        }
        // Höhe nach Anzahl der Einträge (vorher mindestens 48 px, ein Laufwerk stand in einem fast leeren Feld)
        clbDisks.Height = Math.Max(1, Math.Min(8, clbDisks.Items.Count)) * UI.S(21) + UI.S(6);
        clbDisks.ItemCheck += delegate { BeginInvoke(new System.Windows.Forms.MethodInvoker(UpdateSummary)); };
        f.Controls.Add(clbDisks);
        f.Controls.Add(Hint("Je Laufwerk wird mit einer Testdatei auf dessen Volume mit dem meisten freien Platz gemessen (1 GB, im Kurzlauf 256 MB, danach gelöscht). USB-Datenträger sind zunächst abgewählt.", 4));
        f.Controls.Add(Section("Rendertest (Grafik)"));
        FlowLayoutPanel rg0 = Row(); rg0.Controls.Add(RowLabel("Grafikeinheit", 170));
        cmbGpuSel = Combo(420, GpuChoiceTexts(), 0); rg0.Controls.Add(cmbGpuSel); f.Controls.Add(rg0);
        FlowLayoutPanel rg = Row(); rg.Controls.Add(RowLabel("Auflösung", 170));
        cmbGpuRes = Combo(140, new string[] { "1280x720", "1920x1080" }, 0); rg.Controls.Add(cmbGpuRes);
        rg.Controls.Add(RowLabel("Anzeige", 70)); cmbGpuShow = Combo(170, new string[] { "Fenster", "Vollbild", "ohne Anzeige" }, 0); rg.Controls.Add(cmbGpuShow);
        f.Controls.Add(rg);
        f.Controls.Add(Hint("Ergebnis: Ø Bilder/s, 1-%-Low und Punktzahl je Grafikeinheit. Esc im Fenster beendet den Test.", 4));
        chkGpuWahl = Chk("Bei Hybridgrafik WinSAT zusätzlich auf der Grafikkarte messen", false);
        Control gw = Opt2(chkGpuWahl, "kurze Umstellung der Grafikeinheit für WinSAT, gleich danach zurück", RiskBadge("Aendern")); gw.Margin = new Padding(0, UI.S(UI.Abstand2), 0, 0); f.Controls.Add(gw);

        clbCompare = new CheckedListBox(); clbCompare.BackColor = UI.Panel; clbCompare.ForeColor = UI.Text;
        FillRefLists();
        return f;
    }

    // Laufwerkszeile: Nummer, Name, Bus, Medium, Größe und je Laufwerksbuchstabe der freie Platz; das Ziel der Messung
    // ist das Volume mit dem meisten freien Platz
    static string DiskLine(string[] x)
    {
        string head = String.Format("Datenträger {0}:  {1}   ({2}, {3}, {4})", x[0], x[1], x[2], x[3], x[4]);
        if (x[5].Length == 0) return head + "   ·   kein Laufwerksbuchstabe";
        List<string> vols = new List<string>(); string best = ""; long bestFree = -1;
        foreach (string l in x[5].Split(','))
        {
            string t = l.Trim(); if (t.Length == 0) continue;
            long free = -1;
            // USB-Datenträger nicht abfragen (ein schlafendes Laufwerk verzögerte sonst den Start)
            if (x.Length < 7 || x[6] != "1") try { DriveInfo di = new DriveInfo(t.Substring(0, 1)); if (di.IsReady) free = di.AvailableFreeSpace; } catch { }
            vols.Add(free >= 0 ? t + " " + GbText(free) + " frei" : t);
            if (free > bestFree) { bestFree = free; best = t; }
        }
        return head + "   ·   " + String.Join(", ", vols.ToArray()) + (vols.Count > 1 && best.Length > 0 ? "   ·   gemessen auf " + best : "");
    }

    static string GbText(long bytes)
    {
        double gb = bytes / 1073741824.0;
        return gb >= 1024 ? (gb / 1024).ToString("0.0", CultureInfo.GetCultureInfo("de-DE")) + " TB" : gb.ToString("0", CultureInfo.GetCultureInfo("de-DE")) + " GB";
    }

    void FillRefLists()
    {
        HashSet<string> prevCmp = new HashSet<string>();
        if (clbCompare != null)
        {
            for (int i = 0; i < clbCompare.Items.Count; i++) if (clbCompare.GetItemChecked(i) && i < cmpItems.Count) prevCmp.Add(cmpItems[i].Path);
            clbCompare.Items.Clear(); cmpItems.Clear();
        }
        foreach (DbEntry e in db)
        {
            if (!e.HasBench) continue;
            refItems.Add(e);
            if (clbCompare != null) { cmpItems.Add(e); clbCompare.Items.Add(e.Label, prevCmp.Contains(e.Path)); }
        }
        if (clbCompare != null)
        {
            if (clbCompare.Items.Count == 0) { clbCompare.Items.Add("(noch keine Systeme mit Benchmark in der Datenbank)"); clbCompare.Enabled = false; }
            else clbCompare.Enabled = true;
            clbCompare.Height = Math.Max(UI.S(48), Math.Min(8, clbCompare.Items.Count) * UI.S(21) + UI.S(6));
        }
    }

    // ab v3.64 Lasttest als Tabelle: Komponente, Dauer, Einstellungen; Hinweise stehen bei ihrem Feld statt am Seitenende
    Dictionary<CheckBox, List<Control>> loadParts = new Dictionary<CheckBox, List<Control>>();
    Label lblLoadTotal, lblAkku;
    Badge badgePawn;

    static Label CellLabel(string text, int width)
    {
        Label l = RowLabel(text, width); l.Font = new Font("Segoe UI", UI.SchriftText); return l;
    }

    Control BuildLoadPage()
    {
        FlowLayoutPanel f = Page("Lasttest", "Belastet die gewählten Komponenten gleichzeitig, jede mit eigener Dauer, und zeichnet Temperatur, Takt, Leistung und Lüfter auf. Gemeldet werden Rechen-, Bit- und Datenfehler, WHEA-Fehler und Drosselung. Während des Tests lässt er sich jederzeit beenden.", 2);
        string[] mins = new string[] { "2 Min.", "5 Min.", "10 Min.", "15 Min.", "30 Min.", "60 Min.", "120 Min.", "240 Min." };
        lblAkku = Lbl("  Akkubetrieb: Für den Lasttest das Netzteil anschließen, sonst begrenzt die Energieverwaltung Takt und Leistung.  ", UI.SchriftText, true, UI.Warn);
        lblAkku.BackColor = UI.WarnBg; lblAkku.Padding = new Padding(UI.S(6)); lblAkku.Margin = new Padding(0, UI.S(4), 0, UI.S(4)); lblAkku.Visible = false; f.Controls.Add(lblAkku);
        f.Controls.Add(Section("Komponenten und Dauer"));
        TableLayoutPanel t = LoadTable();
        t.Controls.Add(CellLabel("Komponente", 230), 0, 0); t.Controls.Add(CellLabel("Dauer", 120), 1, 0); t.Controls.Add(CellLabel("Einstellungen", 150), 2, 0);
        foreach (Control c in t.Controls) { c.ForeColor = UI.Muted; c.Font = new Font("Segoe UI Semibold", UI.SchriftHinweis); }

        chkLCpu = Chk("Prozessor", true); cmbLCpu = Combo(110, mins, 0);
        AddLoadRow(t, 1, chkLCpu, "alle Threads mit Ergebnisprüfung", cmbLCpu, null);

        chkLRam = Chk("Arbeitsspeicher", true); cmbLRam = Combo(110, mins, 0);
        cmbLRamPct = Combo(90, new string[] { "25 %", "40 %", "60 %", "75 %" }, 1);
        Label lPct = CellLabel("Anteil am freien RAM", 150);
        AddLoadRow(t, 2, chkLRam, "Mustertest mit Bitfehlerprüfung", cmbLRam, new Control[] { SettingRow(lPct, cmbLRamPct) });

        chkLGpu = Chk("Grafik", false); cmbLGpu = Combo(110, mins, 0);
        cmbLGpuSel = Combo(260, GpuChoiceTexts(), 0);
        cmbLGpuRes = Combo(120, new string[] { "1280x720", "1920x1080" }, 0);
        cmbLGpuShow = Combo(140, new string[] { "Fenster", "Vollbild", "ohne Anzeige" }, 0);
        Label lSel = CellLabel("Grafikeinheit", 100), lRes = CellLabel("Auflösung", 100), lShow = CellLabel("Anzeige", 100);
        AddLoadRow(t, 3, chkLGpu, "Rendertest mit Direct3D 11, Bildprüfung alle 30 s, Erkennung von Treiber-Resets", cmbLGpu, new Control[] { SettingRow(lSel, cmbLGpuSel), SettingRow(lRes, cmbLGpuRes), SettingRow(lShow, cmbLGpuShow) });
        // Einstellungen des Rendertests auf beiden Seiten gleich halten: Benchmark -> Lasttest und Lasttest -> Benchmark
        // (ab 3.53 über CopySelection; vorher setzte sync2 die Grafikeinheit des Lasttests auf den Wert des Benchmarks zurück)
        EventHandler sync1 = delegate { if (syncGpu || cmbGpuRes == null) return; syncGpu = true; try { CopySelection(GpuCombosBench(), GpuCombosLast()); } finally { syncGpu = false; } };
        EventHandler sync2 = delegate { if (syncGpu || cmbGpuRes == null) return; syncGpu = true; try { CopySelection(GpuCombosLast(), GpuCombosBench()); } finally { syncGpu = false; } };
        if (cmbGpuRes != null) { cmbGpuRes.SelectedIndexChanged += sync1; cmbGpuShow.SelectedIndexChanged += sync1; }
        if (cmbGpuSel != null) cmbGpuSel.SelectedIndexChanged += sync1;
        cmbLGpuRes.SelectedIndexChanged += sync2; cmbLGpuShow.SelectedIndexChanged += sync2; cmbLGpuSel.SelectedIndexChanged += sync2;

        chkLDisk = Chk("Datenträger", false); cmbLDisk = Combo(110, mins, 0);
        List<string> letters = new List<string>();
        foreach (string d in disks)
        {
            string[] x = d.Split('|'); if (x.Length < 7 || x[5].Length == 0) continue;
            foreach (string l in x[5].Split(',')) { string tl = l.Trim(); if (tl.Length > 0) letters.Add(tl + "  " + ShortDiskName(x[1]) + (x[4].Length > 0 ? " (" + x[4] + ")" : "")); }
        }
        if (letters.Count == 0) letters.Add("C:");
        letters.Sort();
        cmbLDiskDrive = Combo(260, letters.ToArray(), 0);
        Label lDrv = CellLabel("Laufwerk", 100);
        AddLoadRow(t, 4, chkLDisk, "Schreiben, Lesen und Prüfen jedes Blocks; Testdatei bis 4 GB, wird danach gelöscht", cmbLDisk, new Control[] { SettingRow(lDrv, cmbLDiskDrive) });
        f.Controls.Add(Card(t));
        lblLoadTotal = Lbl("", UI.SchriftText, true, UI.Text); lblLoadTotal.Margin = new Padding(UI.S(4), UI.S(UI.Abstand2), 0, 0); f.Controls.Add(lblLoadTotal);

        foreach (CheckBox c in new CheckBox[] { chkLCpu, chkLRam, chkLGpu, chkLDisk }) c.CheckedChanged += delegate { UpdateLoadEnabled(); UpdateSummary(); };
        foreach (ComboBox c in new ComboBox[] { cmbLCpu, cmbLRam, cmbLGpu, cmbLDisk }) c.SelectedIndexChanged += delegate { UpdateSummary(); };

        f.Controls.Add(Section("Abbruchschwelle"));
        TableLayoutPanel ta = LoadTable();
        cmbLAbortCpu = Combo(140, new string[] { "Automatisch", "85 °C", "90 °C", "95 °C", "100 °C", "aus" }, 0);
        cmbLAbortGpu = Combo(140, new string[] { "85 °C", "90 °C", "95 °C", "aus" }, 1);
        badgePawn = new Badge("PawnIO vorübergehend", "info");
        Tip(badgePawn, "Echte CPU-Temperaturen liefert LibreHardwareMonitor mit dem Treiber PawnIO. Er wird für den Lauf vorübergehend installiert und danach wieder entfernt (einstellbar auf der Seite Sensoren live).");
        ta.Controls.Add(CellLabel("CPU-Temperatur", 230), 0, 0); ta.Controls.Add(cmbLAbortCpu, 1, 0); ta.Controls.Add(badgePawn, 2, 0);
        ta.Controls.Add(CellLabel("GPU-Temperatur", 230), 0, 1); ta.Controls.Add(cmbLAbortGpu, 1, 1);
        f.Controls.Add(Card(ta));
        f.Controls.Add(Hint("Liegt die Temperatur rund 10 Sekunden auf oder über der Schwelle, endet der Test mit einem Befund. Automatisch: TjMax der CPU, sonst 100 °C.", 4));
        UpdateLoadEnabled();
        return f;
    }

    static TableLayoutPanel LoadTable()
    {
        TableLayoutPanel t = new TableLayoutPanel(); t.AutoSize = true; t.AutoSizeMode = AutoSizeMode.GrowAndShrink; t.ColumnCount = 3; t.BackColor = UI.Panel;
        t.Margin = new Padding(0, 0, 0, 0);
        t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, UI.S(240))); t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, UI.S(130))); t.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        return t;
    }

    static Control SettingRow(Label l, Control c)
    {
        FlowLayoutPanel r = new FlowLayoutPanel(); r.AutoSize = true; r.WrapContents = false; r.BackColor = UI.Panel; r.Margin = new Padding(0, 0, 0, UI.S(2));
        r.Controls.Add(l); r.Controls.Add(c); return r;
    }

    void AddLoadRow(TableLayoutPanel t, int row, CheckBox chk, string detail, ComboBox dur, Control[] settings)
    {
        Control comp = Opt2(chk, detail);
        Label d = comp.Controls.Count > 1 ? comp.Controls[1] as Label : null;
        if (d != null) d.MaximumSize = new Size(UI.S(216), 0);
        comp.Margin = new Padding(0, UI.S(4), UI.S(4), UI.S(6));
        dur.Margin = new Padding(0, UI.S(6), 0, 0);
        t.Controls.Add(comp, 0, row); t.Controls.Add(dur, 1, row);
        List<Control> parts = new List<Control>(); parts.Add(dur);
        if (settings != null && settings.Length > 0)
        {
            FlowLayoutPanel s = new FlowLayoutPanel(); s.FlowDirection = FlowDirection.TopDown; s.WrapContents = false; s.AutoSize = true; s.BackColor = UI.Panel; s.Margin = new Padding(0, UI.S(4), 0, UI.S(4));
            foreach (Control c in settings) { s.Controls.Add(c); foreach (Control k in c.Controls) parts.Add(k); }
            t.Controls.Add(s, 2, row);
        }
        loadParts[chk] = parts;
    }

    // Elemente einer abgewählten Komponente einheitlich deaktivieren: Auswahllisten aus, Beschriftungen gedämpft
    public static void SetPartEnabled(IEnumerable<Control> parts, bool on)
    {
        if (parts == null) return;
        foreach (Control c in parts)
        {
            if (c is Label) c.ForeColor = on ? UI.Text : DisabledText();
            else c.Enabled = on;
        }
    }

    void UpdateLoadEnabled()
    {
        foreach (KeyValuePair<CheckBox, List<Control>> kv in loadParts) SetPartEnabled(kv.Value, kv.Key.Checked);
        UpdateLoadTotal();
    }

    void UpdateLoadTotal()
    {
        if (lblLoadTotal == null || chkLCpu == null) return;
        int m = LoadTotalMinutes(new bool[] { chkLCpu.Checked, chkLRam.Checked, chkLGpu.Checked, chkLDisk.Checked },
            new int[] { Minutes(cmbLCpu), Minutes(cmbLRam), Minutes(cmbLGpu), Minutes(cmbLDisk) });
        SetText(lblLoadTotal, m == 0 ? "Keine Komponente gewählt" : "Gesamtdauer: " + MinText(m) + " (alle gewählten Komponenten laufen gleichzeitig)");
        lblLoadTotal.ForeColor = m == 0 ? UI.Warn : UI.Text;
    }

    // Hinweise der Seite Lasttest, die sich nach Gerät und Einstellung richten (Akkubetrieb, PawnIO)
    void UpdateLoadExtras()
    {
        try { if (lblAkku != null) lblAkku.Visible = SystemInformation.PowerStatus.PowerLineStatus == PowerLineStatus.Offline; } catch { }
        try { if (badgePawn != null) badgePawn.Text = (cmbDriver == null || cmbDriver.SelectedIndex == 0) && PawnIoVersion().Length == 0 ? "PawnIO vorübergehend" : ""; } catch { }
    }

    // Laufwerksname kurz: Busangaben und Größenangabe im Namen entfallen ("NVMe PC SN820 NVMe WD 4096GB" -> "PC SN820 WD")
    public static string ShortDiskName(string name)
    {
        string n = " " + (name ?? "") + " ";
        n = System.Text.RegularExpressions.Regex.Replace(n, @"(?i)\b(NVMe|SATA|SCSI|ATA|USB|Device|Disk)\b", " ");
        n = System.Text.RegularExpressions.Regex.Replace(n, @"(?i)\b\d+([.,]\d+)?\s?(GB|TB|G|T)\b", " ");
        n = System.Text.RegularExpressions.Regex.Replace(n, @"\s+", " ").Trim();
        return n.Length > 0 ? n : (name ?? "").Trim();
    }

    string[] repairGroupOrder = new string[] {
        "Systemdateien und Komponentenspeicher",
        "Bereinigung und Speicherplatz",
        "Windows Update, Netzwerk und Zeit",
        "Dienste, Geräte und Energie"
    };

    string GetRepairGroup(int i)
    {
        if (i >= 0 && i < repGroup.Length && !string.IsNullOrEmpty(repGroup[i])) return repGroup[i];
        if (i >= 0 && i < repKeys.Length)
        {
            string k = repKeys[i];
            if (k == "DismRestore" || k == "Sfc" || k == "Komponentenbereinigung" || k == "Dateisystem") return "Systemdateien und Komponentenspeicher";
            if (k == "Temp" || k == "Datentraegerbereinigung" || k == "UpdateDownloads" || k == "ShaderCache" || k == "Prefetch" || k == "PaketCache" || k == "Absturzabbilder" || k == "Wiederherstellungspunkte") return "Bereinigung und Speicherplatz";
            if (k == "WindowsUpdate" || k == "Netzwerk" || k == "Zeit") return "Windows Update, Netzwerk und Zeit";
            if (k == "WMI" || k == "Leistungszaehler" || k == "Leerlaufaufgaben" || k == "Druck" || k == "Geraete" || k == "Schnellstart" || k == "Energieplaene") return "Dienste, Geräte und Energie";
        }
        return "Dienste, Geräte und Energie";
    }

    // ab v3.64: Risikostufe und Neustart als Etiketten rechts in einer Spalte, Befehle in der Detailzeile, Legende oben,
    // Warnung ohne Wiederherstellungspunkt bei gewählten Eingriffen
    Label lblRestoreWarn;
    Button btnRepAll;

    Control BuildRepairPage()
    {
        FlowLayoutPanel f = Page("Wartung", "Führt die gewählten Wartungs- und Reparaturaufgaben nacheinander aus. Vorher wird auf Wunsch ein Wiederherstellungspunkt angelegt. Aufgaben mit dem Etikett Neustart werden erst danach vollständig wirksam.", 3);
        f.Controls.Add(Section("Absicherung"));
        chkRestorePoint = Chk("Vorher einen Systemwiederherstellungspunkt anlegen", true); chkRestorePoint.Margin = new Padding(UI.S(4), UI.S(2), 0, UI.S(2)); f.Controls.Add(chkRestorePoint);
        lblRestoreWarn = Lbl("", UI.SchriftText, true, UI.Warn); lblRestoreWarn.BackColor = UI.WarnBg; lblRestoreWarn.Padding = new Padding(UI.S(6)); lblRestoreWarn.Margin = new Padding(UI.S(4), UI.S(4), 0, UI.S(2));
        lblRestoreWarn.MaximumSize = new Size(UI.S(UI.Gruppenbreite), 0); lblRestoreWarn.Visible = false; f.Controls.Add(lblRestoreWarn);
        chkRestorePoint.CheckedChanged += delegate { UpdateRestoreWarn(); UpdateSummary(); };
        f.Controls.Add(Section("Reparaturen"));
        FlowLayoutPanel b = Row(); b.Margin = new Padding(UI.S(4), UI.S(2), 0, UI.S(UI.Abstand2));
        Button all = UI.Secondary("Empfohlene Auswahl"); all.Margin = new Padding(0);
        Tip(all, "Wählt in allen Gruppen die risikoarmen Routineaufgaben wie Bereinigungen und Cache-Leerungen aus.");
        all.Click += delegate {
            for (int i = 0; i < repChk.Length; i++) repChk[i].Checked = repUsual[i];
            UpdateRepairCounts();
            UpdateRepairGroupVisibility();
        };
        Button none = UI.Secondary("Auswahl aufheben");
        Tip(none, "Hebt die Auswahl in allen Gruppen auf.");
        none.Click += delegate {
            foreach (CheckBox c in repChk) c.Checked = false;
            UpdateRepairCounts();
            UpdateRepairGroupVisibility();
        };
        btnRepAll = UI.Secondary("Alle aufklappen"); btnRepAll.Margin = new Padding(UI.S(16), 0, 0, 0);
        btnRepAll.Click += delegate {
            bool open = false;
            foreach (Control c in repCatBody.Values) if (!c.Visible) { open = true; break; }
            foreach (KeyValuePair<string, Control> kv in repCatBody) { kv.Value.Visible = open; repCatToggle[kv.Key].Expanded = open; }
            btnRepAll.Text = open ? "Alle zuklappen" : "Alle aufklappen";
        };
        Tip(btnRepAll, "Alle Gruppen auf- oder zuklappen.");
        b.Controls.Add(all); b.Controls.Add(none); b.Controls.Add(btnRepAll); f.Controls.Add(b);
        // Reihenfolge wie auf der Seite Optimierung: Knöpfe, Legende, Gruppen
        f.Controls.Add(RiskLegend());

        repChk = new CheckBox[repKeys.Length];
        for (int i = 0; i < repKeys.Length; i++)
        {
            repChk[i] = Chk(SplitDetail(repText[i])[0], repDefault[i]);
            repChk[i].CheckedChanged += delegate { UpdateRepairCounts(); UpdateRestoreWarn(); UpdateSummary(); };
        }

        repCatCount.Clear(); repCatBody.Clear(); repCatToggle.Clear();
        foreach (string grp in repairGroupOrder)
        {
            List<int> indices = new List<int>();
            for (int i = 0; i < repKeys.Length; i++) if (GetRepairGroup(i) == grp) indices.Add(i);
            if (indices.Count == 0) continue;
            string gd; repairGroupText.TryGetValue(grp, out gd);
            GroupHeader tg; LinkLabel lAll, lNone;
            TableLayoutPanel body = CategoryBlock(f, grp, gd, out tg, out lAll, out lNone);
            bool hasChecked = false;
            int row = 0;
            foreach (int idx in indices)
            {
                if (repChk[idx].Checked) hasChecked = true;
                repChk[idx].Margin = new Padding(UI.S(4), UI.S(2), 0, UI.S(2));
                body.Controls.Add(repChk[idx], 0, row);
                body.Controls.Add(BadgeCell(RiskBadge(idx < repRisk.Length ? repRisk[idx] : ""), RestartBadge(idx < repRestart.Length ? repRestart[idx] : "")), 1, row);
                row++;
            }
            body.Visible = hasChecked;
            tg.Expanded = hasChecked;
            repCatCount[grp] = tg; repCatBody[grp] = body; repCatToggle[grp] = tg;
            List<int> mine = indices;
            tg.Toggled += delegate { body.Visible = tg.Expanded; };
            lAll.LinkClicked += delegate { foreach (int i in mine) repChk[i].Checked = true; UpdateRepairGroupVisibility(); };
            lNone.LinkClicked += delegate { foreach (int i in mine) repChk[i].Checked = false; };
            Tip(tg, (gd ?? grp) + "\r\nKlicken zeigt oder verbirgt die Maßnahmen dieser Gruppe.");
            Tip(lAll, "Alle Maßnahmen dieser Gruppe wählen."); Tip(lNone, "Keine Maßnahme dieser Gruppe wählen.");
        }
        UpdateRepairCounts();
        UpdateRestoreWarn();
        return f;
    }

    // ab v3.65 gemeinsamer Aufbau einer Kategorie für Wartung und Optimierung: Kopfzeile mit Zähler, rechts alle und
    // keine, darunter die Beschreibung und die Tabelle der Einträge (Haken links, Etiketten rechts)
    TableLayoutPanel CategoryBlock(FlowLayoutPanel f, string title, string desc, out GroupHeader tg, out LinkLabel all, out LinkLabel none)
    {
        FlowLayoutPanel h = new FlowLayoutPanel(); h.AutoSize = true; h.WrapContents = false; h.BackColor = UI.Panel; h.Margin = new Padding(0, UI.S(UI.Abstand2), 0, 0);
        tg = new GroupHeader(title); tg.Width = UI.S(UI.Gruppenbreite - 110); tg.Margin = new Padding(0);
        all = new LinkLabel(); all.Text = "alle"; all.AutoSize = true; all.Margin = new Padding(UI.S(12), UI.S(8), UI.S(8), 0); all.LinkColor = UI.Accent;
        none = new LinkLabel(); none.Text = "keine"; none.AutoSize = true; none.Margin = new Padding(0, UI.S(8), 0, 0); none.LinkColor = UI.Accent;
        h.Controls.Add(tg); h.Controls.Add(all); h.Controls.Add(none);
        f.Controls.Add(h);
        if (!String.IsNullOrEmpty(desc)) f.Controls.Add(Hint(desc, 30));
        TableLayoutPanel body = BadgeTable(); body.Margin = new Padding(UI.S(UI.Abstand4), 0, 0, UI.S(UI.Abstand1)); body.Visible = false;
        f.Controls.Add(body);
        return body;
    }

    static readonly Dictionary<string, string> repairGroupText = new Dictionary<string, string> {
        { "Systemdateien und Komponentenspeicher", "Windows-Systemdateien, Komponentenspeicher und Dateisystem prüfen und reparieren." },
        { "Bereinigung und Speicherplatz", "Temporäre Dateien, Caches, alte Update-Downloads und Absturzabbilder entfernen." },
        { "Windows Update, Netzwerk und Zeit", "Update-Komponenten, Netzwerkeinstellungen und Zeitsynchronisierung zurücksetzen." },
        { "Dienste, Geräte und Energie", "WMI, Leistungszähler, Druckwarteschlange, Geräteerkennung, Schnellstart und Energiepläne." } };

    // Legende der Risikostufen als Etiketten mit kurzer Erklärung (Wartung und Optimierung)
    Control RiskLegend()
    {
        FlowLayoutPanel l = new FlowLayoutPanel(); l.AutoSize = true; l.FlowDirection = FlowDirection.TopDown; l.WrapContents = false; l.BackColor = UI.Panel; l.Margin = new Padding(UI.S(4), 0, 0, UI.S(2));
        Badge ba = new Badge(ContractStep.RiskLabel("Aendern"), "info"); ba.Margin = new Padding(0, UI.S(2), UI.S(6), 0);
        Label ta = Lbl("protokolliert, auf der Seite Systemänderungen rücknehmbar", UI.SchriftHinweis, false, UI.Muted); ta.Margin = new Padding(0, UI.S(3), UI.S(UI.Abstand4), 0);
        Badge be = new Badge(ContractStep.RiskLabel("Eingriff"), "warn"); be.Margin = new Padding(0, UI.S(2), UI.S(6), 0);
        Label te = Lbl("nicht automatisch umkehrbar, abgesichert über den Wiederherstellungspunkt", UI.SchriftHinweis, false, UI.Muted); te.Margin = new Padding(0, UI.S(3), 0, 0);
        Tip(ba, "Wird mit Vorher-Wert protokolliert und lässt sich auf der Seite Systemänderungen zurücknehmen.");
        Tip(be, "Lässt sich nicht automatisch umkehren; der Weg zurück ist der Wiederherstellungspunkt.");
        foreach (Control[] pair in new Control[][] { new Control[] { ba, ta }, new Control[] { be, te } })
        {
            FlowLayoutPanel r = new FlowLayoutPanel(); r.AutoSize = true; r.WrapContents = false; r.BackColor = UI.Panel; r.Margin = new Padding(0, 0, 0, UI.S(2));
            pair[0].Width = Math.Max(pair[0].Width, UI.S(70));
            r.Controls.Add(pair[0]); r.Controls.Add(pair[1]); l.Controls.Add(r);
        }
        return l;
    }

    const int BadgeSpalte = 230;

    static TableLayoutPanel BadgeTable()
    {
        TableLayoutPanel t = new TableLayoutPanel(); t.AutoSize = true; t.AutoSizeMode = AutoSizeMode.GrowAndShrink; t.ColumnCount = 2; t.BackColor = UI.Panel;
        t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, UI.S(UI.Gruppenbreite - 16 - BadgeSpalte))); t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, UI.S(BadgeSpalte)));
        return t;
    }

    Control BadgeCell(params Badge[] badges)
    {
        // Etiketten rechtsbündig; reicht die Spalte nicht (verwaltet, Zustand), brechen sie in eine zweite Zeile um
        FlowLayoutPanel c = new FlowLayoutPanel(); c.AutoSize = true; c.WrapContents = true; c.FlowDirection = FlowDirection.RightToLeft; c.BackColor = UI.Panel; c.Dock = DockStyle.Top; c.Margin = new Padding(0, UI.S(2), 0, 0);
        c.MaximumSize = new Size(UI.S(BadgeSpalte), 0);
        foreach (Badge b in badges) if (b != null)
        {
            b.Margin = new Padding(UI.S(6), UI.S(2), 0, 0);
            BadgeTip(b);
            c.Controls.Add(b);
        }
        return c;
    }

    // Warnung: Eingriffe gewählt, aber kein Wiederherstellungspunkt; Computerschutz aus (soweit lesend feststellbar)
    void UpdateRestoreWarn()
    {
        if (lblRestoreWarn == null || repChk == null) return;
        int ein = 0;
        for (int i = 0; i < repChk.Length; i++) if (repChk[i] != null && repChk[i].Checked && i < repRisk.Length && (repRisk[i] == "Eingriff" || repRisk[i] == "Zerstoerend")) ein++;
        string t = "";
        if (ein > 0 && !chkRestorePoint.Checked) t = "Es sind " + ein + (ein == 1 ? " Eingriff" : " Eingriffe") + " gewählt, aber kein Wiederherstellungspunkt. Ohne ihn gibt es keinen Weg zurück.";
        else if (chkRestorePoint.Checked && SystemRestoreOff()) t = "Der Computerschutz scheint auf diesem PC ausgeschaltet zu sein; der Wiederherstellungspunkt kann dann nicht angelegt werden.";
        SetText(lblRestoreWarn, t);
        lblRestoreWarn.Visible = t.Length > 0;
    }

    // Computerschutz per Richtlinie oder Systemeinstellung aus (nur lesend, ohne Gewähr; unbekannt gilt als an)
    static int systemRestoreOff = -1;
    static bool SystemRestoreOff()
    {
        if (systemRestoreOff >= 0) return systemRestoreOff == 1;
        systemRestoreOff = 0;
        try
        {
            using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore"))
                if (k != null && (Convert.ToInt32(k.GetValue("DisableSR", 0)) == 1 || Convert.ToInt32(k.GetValue("DisableConfig", 0)) == 1)) systemRestoreOff = 1;
            using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"))
                if (k != null) { object v = k.GetValue("RPSessionInterval"); if (v != null && Convert.ToInt32(v) == 0) systemRestoreOff = 1; }
        }
        catch { }
        return systemRestoreOff == 1;
    }

    void UpdateRepairCounts()
    {
        foreach (string grp in repairGroupOrder)
        {
            if (!repCatCount.ContainsKey(grp)) continue;
            int sel = 0, tot = 0;
            for (int i = 0; i < repKeys.Length; i++)
            {
                if (GetRepairGroup(i) == grp)
                {
                    tot++;
                    if (repChk[i] != null && repChk[i].Checked) sel++;
                }
            }
            repCatCount[grp].CountText = sel + " von " + tot + " gewählt";
        }
    }

    void UpdateRepairGroupVisibility()
    {
        foreach (string grp in repairGroupOrder)
        {
            if (!repCatBody.ContainsKey(grp) || !repCatToggle.ContainsKey(grp)) continue;
            bool hasChecked = false;
            for (int i = 0; i < repKeys.Length; i++)
            {
                if (GetRepairGroup(i) == grp && repChk[i] != null && repChk[i].Checked) { hasChecked = true; break; }
            }
            repCatBody[grp].Visible = hasChecked;
            repCatToggle[grp].Expanded = hasChecked;
        }
    }

    // ------------------------------------------------------------ Seite Optimierung (ab v2.8)
    // Katalog aus dem Skript (Get-OptGuiLines): Kategorien zum Auf- und Zuklappen, je Eintrag ein Haken mit Risikostufe.
    List<OptItem> optItems = new List<OptItem>();
    List<string[]> optCats = new List<string[]>();
    Dictionary<string, GroupHeader> optCatCount = new Dictionary<string, GroupHeader>();
    Dictionary<string, Control> optCatBody = new Dictionary<string, Control>();
    Dictionary<string, GroupHeader> optCatToggle = new Dictionary<string, GroupHeader>();
    CheckBox chkOptRestore;
    Label lblOptInfo, lblOptState;
    Button btnOptCheck, btnOptTools, btnOptAll;
    List<Button> optPresetButtons = new List<Button>();
    static readonly string[] optPresetTips = new string[] {
        "Minimal wie im Optimisation Pack: Datenschutz-Einstellungen (O&O-Auswahl), Dienste und Aufgaben, Indizierung aus, Caches leeren.",
        "Leos Empfehlung: Wie die Voreinstellung beim Start ausgewählt (empfohlene Optimierungen für Datenschutz, Apps, Dienste und System).",
        "Erweitert wie im Optimisation Pack: Leos Empfehlung plus Windows-Funktionen, Zusatzfeatures, vorinstallierte Apps und Darstellung.",
        "Hebt die Auswahl in allen Kategorien auf." };

    static readonly string[] defaultMinimal = new string[] {
        "TelemetrieMinimal", "Fehlerberichte", "WerbeId", "Speicheroptimierung", "TaskbarEndTask"
    };
    HashSet<string> cachedMinimalIds;

    HashSet<string> GetMinimalIds()
    {
        if (cachedMinimalIds != null) return cachedMinimalIds;
        HashSet<string> set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string id in defaultMinimal) set.Add(id);
        foreach (OptItem it in optItems)
        {
            if (it.Vorlagen != null && it.Vorlagen.IndexOf("M", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                set.Add(it.Id);
            }
        }
        cachedMinimalIds = set;
        return cachedMinimalIds;
    }

    static readonly string[] defaultLeoEmpfehlung = new string[] {
        "TelemetrieMinimal", "TelemetrieDienste", "TelemetrieDiagnoseprotokolle", "Feedback", "WerbeId",
        "MassgeschneiderteErfahrung", "Sprachliste", "Handschrift", "Inventar", "Insiderseite",
        "Nachrichtensicherung", "BluetoothWerbung", "MediaPlayerDiagnose", "Standort", "TippsVorschlaege",
        "Willkommen", "EinstellungenVorschlaege", "AppsStillInstallieren", "Sperrbildschirm", "Sperrkamera",
        "ExplorerWerbung", "Smartphone", "Websuche", "Suchhighlights", "Cortana",
        "Spracherkennung", "Copilot", "Recall", "PaintKI", "AppDiagnose",
        "AppBewegung", "AppStarts", "DiensteSelten", "DiensteSync", "DiensteSmartcard",
        "DiensteEdgeUpdate", "AufgabenTelemetrie", "AufgabenKarten", "AufgabenJugendschutz", "AufgabenXbox",
        "AufgabenGesicht", "CapSchrittaufzeichnung", "CapMathe", "CapIse", "CapHandschrift",
        "AppHilfeTipps", "AppSolitaer", "AppOfficeHub", "AppFeedbackHub", "AppKarten",
        "AppClipchamp", "AppTeamsPrivat", "AppSmartphoneLink", "AppCortana", "AppCopilot",
        "AppPowerAutomate", "AppDevHome", "AppAltlasten", "AppKontakteAufgaben", "AppOutlookNeu",
        "Widgets", "JetztBesprechen", "DunklerModus", "Hintergrundqualitaet", "Laufwerksname",
        "Mausbeschleunigung", "Spieleprioritaet", "EdgeVerknuepfung", "EdgeHintergrund", "OneDriveRichtlinie",
        "OneDriveEntfernen", "DefenderMeldungen", "TaskbarEndTask", "UefiNeustart"
    };
    HashSet<string> cachedLeoIds;

    HashSet<string> GetLeoEmpfehlungIds()
    {
        if (cachedLeoIds != null) return cachedLeoIds;
        HashSet<string> set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            Dictionary<string, object> d = ReadPresetFile();
            Dictionary<string, object> e = SubDict(SubDict(d, "Eintraege"), "Leos Empfehlung");
            Dictionary<string, object> w = SubDict(e, "Werte");
            string os = w != null ? GetS(w, "Opt.Auswahl") : null;
            if (!string.IsNullOrEmpty(os))
            {
                string[] parts = os.Split(new char[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
                foreach (string p in parts) set.Add(p.Trim());
            }
        }
        catch { }
        if (set.Count == 0)
        {
            foreach (string id in defaultLeoEmpfehlung) set.Add(id);
        }
        foreach (OptItem it in optItems)
        {
            if (it.Vorlagen != null && it.Vorlagen.IndexOf("S", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                set.Add(it.Id);
            }
        }
        cachedLeoIds = set;
        return cachedLeoIds;
    }

    void ReadOptCatalog()
    {
        foreach (string l in OptKatalog ?? new string[0])
        {
            string[] x = l.Split('|');
            if (x.Length >= 4 && x[0] == "K") optCats.Add(new string[] { x[1], x[2], x[3] });
            else if (x.Length >= 11 && x[0] == "E")
            {
                OptItem it = new OptItem(); it.Id = x[1]; it.Kat = x[2]; it.Risiko = x[3]; it.Neustart = x[4]; it.Vorlagen = x[5]; it.Verwaltet = x[6] == "1"; it.Bedingung = x[7];
                int m; int.TryParse(x[8], out m); it.Minuten = m; it.Titel = x[9]; it.Tip = x[10];
                optItems.Add(it);
            }
        }
    }

    // ab v3.64 nur noch der Titel; Risikostufe, Neustart, verwaltet und Zustand stehen als Etiketten daneben
    string OptBoxText(OptItem it)
    {
        if (it.StateBadge != null)
        {
            it.StateBadge.Text = it.Zustand.Length > 0 ? (it.Zustand == "aktiv" ? "bereits aktiv" : it.Zustand) : "";
            it.StateBadge.Level = it.Zustand == "aktiv" ? "ok" : it.Zustand == "teilweise" ? "info" : it.Zustand == "fehlgeschlagen" || it.Zustand == "Fehler" ? "crit" : "skip";
        }
        return it.Titel;
    }

    string OptTipText(OptItem it)
    {
        StringBuilder t = new StringBuilder(it.Tip.Replace(" ¶", "\r\n"));
        t.Append("\r\nRisikostufe: ").Append(ContractStep.RiskLabel(it.Risiko)).Append(it.Risiko == "Aendern" ? " (protokolliert, auf der Seite Systemänderungen einzeln rücknehmbar)" : " (nicht automatisch umkehrbar, Absicherung über den Wiederherstellungspunkt)");
        t.Append("\r\nNeustart: ").Append(it.Neustart == "immer" ? "nötig" : it.Neustart == "moeglich" ? "kann nötig sein" : "nicht nötig");
        List<string> vList = new List<string>();
        if (it.Vorlagen.Contains("M")) vList.Add("Minimal");
        if (GetLeoEmpfehlungIds().Contains(it.Id)) vList.Add("Leos Empfehlung");
        if (it.Vorlagen.Contains("E")) vList.Add("Erweitert");
        if (vList.Count > 0) t.Append("\r\nVorlagen: ").Append(string.Join(", ", vList.ToArray()));
        else t.Append("\r\nIn keiner Vorlage, nur von Hand wählbar.");
        if (it.Verwaltet) t.Append("\r\nBerührt Richtlinien oder zentrale Verwaltung; auf Domänen-PCs nicht in den Vorlagen.");
        if (it.Bedingung.Length > 0) t.Append("\r\nGilt nur für: ").Append(it.Bedingung == "Win10" ? "Windows 10" : it.Bedingung == "Win11" ? "Windows 11" : it.Bedingung == "Desktop" ? "Desktop-PCs" : it.Bedingung == "Nvidia" ? "PCs mit NVIDIA-Grafik" : "PCs mit Windows Terminal");
        if (it.Zustand.Length > 0) t.Append("\r\nZustand auf diesem PC: ").Append(it.Zustand).Append(it.ZustandText.Length > 0 ? " (" + it.ZustandText + ")" : "");
        return t.ToString();
    }

    Control BuildOptPage()
    {
        ReadOptCatalog();
        FlowLayoutPanel f = Page("Optimierung", "Die Einstellungen des Windows Optimisation Pack mit seiner Sophia- und O&O-Auswahl, nativ umgesetzt und nach Kategorien gruppiert.", 4);
        f.Controls.Add(Section("Absicherung"));
        chkOptRestore = Chk("Vorher einen Systemwiederherstellungspunkt anlegen", true); f.Controls.Add(chkOptRestore);
        f.Controls.Add(Section("Vorlagen und Zustand"));
        FlowLayoutPanel b = Row(); b.Margin = new Padding(UI.S(4), UI.S(2), 0, UI.S(4));
        string[] pn = new string[] { "Minimal", "Leos Empfehlung", "Erweitert", "Auswahl aufheben" };
        for (int i = 0; i < pn.Length; i++)
        {
            string key = i == 0 ? "M" : i == 1 ? "S" : i == 2 ? "E" : "";
            Button pb = UI.Secondary(pn[i]); pb.Margin = new Padding(i == 0 ? 0 : UI.S(8), 0, 0, 0);
            pb.Click += delegate { ApplyOptPreset(key); };
            optPresetButtons.Add(pb); b.Controls.Add(pb);
        }
        f.Controls.Add(b);
        // ab v3.65 zweite Zeile für die Werkzeugknöpfe (vorher ragte die Leiste über die Gruppenbreite hinaus)
        b = Row(); b.Margin = new Padding(UI.S(4), UI.S(6), 0, UI.S(4));
        btnOptCheck = UI.Secondary("Zustand prüfen"); btnOptCheck.Margin = new Padding(0); btnOptCheck.Click += delegate { CheckOptState(); }; b.Controls.Add(btnOptCheck);
        btnOptTools = UI.Secondary("Werkzeuge holen ..."); btnOptTools.Margin = new Padding(UI.S(8), 0, 0, 0); btnOptTools.Click += delegate { FetchOptTools(); }; b.Controls.Add(btnOptTools);
        btnOptAll = UI.Secondary("Alle aufklappen"); btnOptAll.Margin = new Padding(UI.S(8), 0, 0, 0); btnOptAll.Click += delegate { ToggleOptAll(); }; b.Controls.Add(btnOptAll);
        f.Controls.Add(b);
        lblOptInfo = Lbl("", 9f, false, UI.Muted); lblOptInfo.MaximumSize = new Size(UI.S(UI.Gruppenbreite), 0); lblOptInfo.Margin = new Padding(UI.S(4), UI.S(4), UI.S(4), 0); f.Controls.Add(lblOptInfo);
        lblOptState = Lbl("", 9f, false, UI.Muted); lblOptState.MaximumSize = new Size(UI.S(UI.Gruppenbreite), 0); lblOptState.Margin = new Padding(UI.S(4), UI.S(2), UI.S(4), UI.S(4)); f.Controls.Add(lblOptState);
        if (optItems.Count == 0) { lblOptInfo.Text = "Der Katalog der Optimierung fehlt (Skript ohne Modul Optimierung)."; return f; }
        f.Controls.Add(RiskLegend());
        foreach (string[] k in optCats)
        {
            string key = k[0];
            List<OptItem> items = optItems.FindAll(delegate(OptItem it) { return it.Kat == key; });
            if (items.Count == 0) continue;
            // Kopfzeile, Beschreibung und Tabelle wie auf der Seite Wartung (CategoryBlock)
            GroupHeader tg; LinkLabel all, none;
            TableLayoutPanel body = CategoryBlock(f, k[1], k[2], out tg, out all, out none);
            int row = 0;
            foreach (OptItem it in items)
            {
                it.Box = Chk(OptBoxText(it), false); it.Box.Margin = new Padding(UI.S(4), UI.S(2), 0, UI.S(2)); it.Box.UseMnemonic = false;
                it.Box.CheckedChanged += delegate { UpdateOptCounts(); };
                it.StateBadge = new Badge("", "ok"); it.StateBadge.Tag = "zustand";
                Badge bv = it.Verwaltet && DomainPc ? new Badge("verwaltet", "warn") : null;
                if (bv != null) bv.Tag = "verwaltet";
                body.Controls.Add(it.Box, 0, row);
                body.Controls.Add(BadgeCell(it.Risiko == "Eingriff" ? RiskBadge("Eingriff") : null, it.Neustart == "immer" ? RestartBadge("immer") : null, bv, it.StateBadge), 1, row);
                row++;
            }
            optCatCount[key] = tg; optCatBody[key] = body; optCatToggle[key] = tg;
            tg.Toggled += delegate { body.Visible = tg.Expanded; };
            all.LinkClicked += delegate { foreach (OptItem it in items) it.Box.Checked = true; };
            none.LinkClicked += delegate { foreach (OptItem it in items) it.Box.Checked = false; };
            Tip(tg, k[2] + "\r\nKlicken zeigt oder verbirgt die Einträge.");
            Tip(all, "Alle Einträge dieser Kategorie wählen."); Tip(none, "Keinen Eintrag dieser Kategorie wählen.");
        }
        f.Controls.Add(Hint("verwaltet: berührt Gruppenrichtlinien, auf Domänen-PCs nicht in den Vorlagen. Benutzereinstellungen gelten für den angemeldeten Benutzer.", 4));
        // Start-Vorauswahl: ab v3.5 ApplyOptPreset("M") (Minimal), früher ApplyOptPreset("S") (Leos Empfehlung)
        ApplyOptPreset("M");
        return f;
    }

    void ApplyOptPreset(string key)
    {
        int skip = 0;
        HashSet<string> leoIds = key == "S" ? GetLeoEmpfehlungIds() : null;
        HashSet<string> minIds = key == "M" ? GetMinimalIds() : null;
        foreach (OptItem it in optItems)
        {
            bool on = false;
            if (key == "S")
            {
                on = (leoIds != null && leoIds.Contains(it.Id)) || (it.Vorlagen != null && it.Vorlagen.Contains("S"));
            }
            else if (key == "M")
            {
                on = (minIds != null && minIds.Contains(it.Id)) || (it.Vorlagen != null && it.Vorlagen.Contains("M"));
            }
            else if (key.Length > 0)
            {
                on = it.Vorlagen.Contains(key);
            }
            if (on && DomainPc && it.Verwaltet) { on = false; skip++; }
            if (it.Box != null) it.Box.Checked = on;
        }
        UpdateOptCounts();
        if (lblOptInfo != null)
        {
            string name = key == "M" ? "Minimal" : key == "S" ? "Leos Empfehlung" : key == "E" ? "Erweitert" : "";
            int n = SelectedOptIds().Count;
            lblOptInfo.Text = (name.Length > 0 ? "Vorlage " + name + ": " + n + " Einträge gewählt." : "Keine Einträge gewählt.")
                + (DomainPc ? "  Dieser PC ist Mitglied einer Domäne" + (skip == 1 ? "; 1 verwalteter Eintrag ist nicht gewählt" : skip > 1 ? "; " + skip + " verwaltete Einträge sind nicht gewählt" : "") + ". Gruppenrichtlinien können Einstellungen wieder überschreiben." : "");
            lblOptInfo.ForeColor = DomainPc ? UI.Warn : UI.Muted;
        }
    }

    List<string> SelectedOptIds()
    {
        List<string> r = new List<string>();
        foreach (OptItem it in optItems) if (it.Box != null && it.Box.Checked) r.Add(it.Id);
        return r;
    }

    void UpdateOptCounts()
    {
        foreach (KeyValuePair<string, GroupHeader> kv in optCatCount)
        {
            int a = 0, n = 0;
            foreach (OptItem it in optItems) if (it.Kat == kv.Key) { a++; if (it.Box.Checked) n++; }
            kv.Value.CountText = n + " von " + a + " gewählt";
        }
        UpdateSummary();
    }

    void ToggleOptAll()
    {
        bool open = false;
        foreach (Control p in optCatBody.Values) if (!p.Visible) { open = true; break; }
        foreach (KeyValuePair<string, Control> kv in optCatBody)
        {
            kv.Value.Visible = open;
            optCatToggle[kv.Key].Expanded = open;
        }
        btnOptAll.Text = open ? "Alle zuklappen" : "Alle aufklappen";
    }

    void CheckOptState()
    {
        if (running) return;
        List<string> lines; RunHelperPumped("-OptimierungZustand", out lines, 300);
        int a = 0, t = 0, o = 0, nz = 0, np = 0;
        string user = "";
        foreach (string l in lines)
        {
            if (!l.StartsWith("@@OPTZ|")) { if (l.StartsWith("Benutzereinstellungen")) user = l; continue; }
            string[] x = l.Split(new char[] { '|' }, 4);
            if (x.Length < 3) continue;
            OptItem it = optItems.Find(delegate(OptItem i) { return i.Id == x[1]; });
            if (it == null) continue;
            it.Zustand = x[2]; it.ZustandText = x.Length > 3 ? x[3].Replace("¦", "|") : "";
            if (it.Zustand == "aktiv") a++; else if (it.Zustand == "teilweise") t++; else if (it.Zustand == "offen") o++; else if (it.Zustand == "nicht zutreffend") nz++; else np++;
            it.Box.Text = OptBoxText(it); Tip(it.Box, OptTipText(it));
        }
        lblOptState.Text = (a + t + o + nz + np) == 0 ? "Zustand nicht lesbar: keine Rückmeldung vom Arbeitsprozess." : "Zustand auf diesem PC: " + a + " bereits aktiv, " + t + " teilweise, " + o + " offen, " + nz + " nicht zutreffend, " + np + " nicht prüfbar (Bereinigung, Werkzeuge)." + (user.Length > 0 ? "  " + user + "." : "");
        lblOptState.ForeColor = UI.Text;
    }

    // Ergebnis eines Eintrags während des Laufs (@@OPTE|Id|Ergebnis|Änderungen|Details): Häkchen zeigt den neuen Stand
    void UpdateOptResult(string[] p)
    {
        OptItem it = optItems.Find(delegate(OptItem i) { return i.Id == Get(p, 1); });
        if (it == null || it.Box == null) return;
        string erg = Get(p, 2);
        it.Zustand = (erg == "angewendet" || erg == "bereits so") ? "aktiv" : erg;
        it.ZustandText = Get(p, 4).Replace("¦", "|");
        it.Box.Text = OptBoxText(it); Tip(it.Box, OptTipText(it));
    }

    void FetchOptTools()
    {
        if (MessageBox.Show(this, "Display Driver Uninstaller (aus dem Windows Optimisation Pack, feste SHA-256-Prüfsumme) und NVIDIA Profile Inspector (neueste Version von GitHub, Prüfsumme wird beim Holen festgehalten) in den Tools-Ordner holen?\r\n\r\nAuf diesem PC wird nichts installiert.", "Werkzeuge für die Optimierung", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        List<string> lines; string res = RunHelperPumped("-OptWerkzeugeHolen", out lines, 900);
        MessageBox.Show(this, lines.Count > 0 ? String.Join("\r\n", lines.ToArray()) : "Keine Rückmeldung vom Arbeitsprozess.", "Werkzeuge für die Optimierung", MessageBoxButtons.OK, res == "1" ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
    }

    // Argumente für den Arbeitsprozess; null = nicht starten. Eingriffe und Neustarts gehen in die Zusammenfassung vor dem
    // Start (ab v3.64 statt einer eigenen Rückfrage der Optimierung)
    string OptStartArgs(List<StartPunkt> punkte, List<string> zusatz)
    {
        List<string> ids = SelectedOptIds();
        if (ids.Count == 0) { MessageBox.Show(this, "In der Optimierung ist kein Eintrag ausgewählt.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information); ShowPage(4); return null; }
        int ver = 0;
        foreach (OptItem it in optItems)
        {
            if (!it.Box.Checked) continue;
            if (it.Verwaltet && DomainPc) ver++;
            if (punkte != null) punkte.Add(new StartPunkt("Optimierung", it.Titel, it.Risiko, it.Neustart));
        }
        if (ver > 0 && zusatz != null) zusatz.Add("Domänen-PC: " + ver + " gewählte Einträge der Optimierung berühren Gruppenrichtlinien und können beim nächsten Abgleich überschrieben werden.");
        return " -Optimierungen " + String.Join(",", ids.ToArray()) + (chkOptRestore.Checked ? "" : " -OptOhneWiederherstellungspunkt");
    }

    // Dialog vor dem Start mit Ablauf, Eingriffen, Neustarts und Wiederherstellungspunkt
    bool ConfirmStart(string text, List<StartPunkt> punkte)
    {
        using (Form f = new Form())
        {
            f.Text = "Start bestätigen"; f.FormBorderStyle = FormBorderStyle.FixedDialog; f.MaximizeBox = false; f.MinimizeBox = false; f.ShowInTaskbar = false;
            f.StartPosition = FormStartPosition.CenterParent; f.Font = new Font("Segoe UI", 9.5f); f.BackColor = UI.Bg; f.AutoSize = true; f.AutoSizeMode = AutoSizeMode.GrowAndShrink; f.Padding = new Padding(UI.S(18));
            FlowLayoutPanel p = new FlowLayoutPanel(); p.FlowDirection = FlowDirection.TopDown; p.AutoSize = true; p.WrapContents = false; p.Dock = DockStyle.Fill;
            bool ein = punkte != null && punkte.Exists(delegate(StartPunkt x) { return x.IstEingriff; });
            Label h = new Label(); h.AutoSize = true; h.Font = new Font("Segoe UI Semibold", 11f); h.Margin = new Padding(0, 0, 0, UI.S(10));
            h.Text = ein ? "Dieser Lauf verändert das System" : "Bitte vor dem Start prüfen";
            p.Controls.Add(h);
            Label l = new Label(); l.AutoSize = true; l.MaximumSize = new Size(UI.S(560), 0); l.Margin = new Padding(0, 0, 0, UI.S(12)); l.Text = text; l.UseMnemonic = false;
            p.Controls.Add(l);
            FlowLayoutPanel b = new FlowLayoutPanel(); b.AutoSize = true; b.Margin = new Padding(0, UI.S(4), 0, 0);
            Button ok = UI.Primary("Starten"); ok.DialogResult = DialogResult.OK; Button ab = UI.Secondary("Abbrechen"); ab.DialogResult = DialogResult.Cancel;
            b.Controls.Add(ok); b.Controls.Add(ab); p.Controls.Add(b);
            f.Controls.Add(p); f.AcceptButton = ab; f.CancelButton = ab; f.ActiveControl = ab;
            UI.ThemeDialog(f);
            return f.ShowDialog(this) == DialogResult.OK;
        }
    }

    // ------------------------------------------------------------ Seite Sensoren (live)
    string ToolsDir { get { return dataDir.Length > 0 ? Path.Combine(dataDir, "Tools") : ""; } }
    bool LhmPresent { get { return ToolsDir.Length > 0 && File.Exists(Path.Combine(ToolsDir, "LibreHardwareMonitor", "LibreHardwareMonitorLib.dll")); } }
    bool PawnSetupPresent { get { return ToolsDir.Length > 0 && File.Exists(Path.Combine(ToolsDir, "PawnIO", "PawnIO_setup.exe")); } }

    // Version des installierten PawnIO (wie LibreHardwareMonitor: Uninstall\PawnIO, sonst 64-Bit-Ansicht), leer = nicht installiert
    static string PawnIoVersion()
    {
        foreach (Microsoft.Win32.RegistryView v in new Microsoft.Win32.RegistryView[] { Microsoft.Win32.RegistryView.Default, Microsoft.Win32.RegistryView.Registry64 })
        {
            try
            {
                using (Microsoft.Win32.RegistryKey b = Microsoft.Win32.RegistryKey.OpenBaseKey(Microsoft.Win32.RegistryHive.LocalMachine, v))
                using (Microsoft.Win32.RegistryKey k = b.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO"))
                    if (k != null) { string s = Convert.ToString(k.GetValue("DisplayVersion")); if (s.Length > 0) return s; }
            }
            catch { }
        }
        return "";
    }

    // Wahl im Startdialog für diesen Lauf ("" = Einstellung der Seite Sensoren bzw. Geraete.json)
    string runKeep = "";

    // ab v3.61: Sensorwerkzeuge bei Bedarf automatisch und lautlos im Hintergrund holen, ohne Popups vor dem Start
    bool lhmAutoFetchAttempted = false;
    void TryAutoFetchSensorTools()
    {
        if (lhmAutoFetchAttempted || ToolsDir.Length == 0) return;
        if (LhmPresent && PawnSetupPresent) return;
        lhmAutoFetchAttempted = true;
        try
        {
            List<string> lines;
            RunHelper("-SensorWerkzeugeHolen", out lines);
            UpdateSensTools();
        }
        catch { }
    }

    // Einstellung für Hilfswerkzeuge je Gerät, gemeinsam mit dem Arbeitsprozess in Geraete.json (Format Minibench-Geraete/1)
    string DeviceFile { get { return dataDir.Length > 0 ? Path.Combine(dataDir, "Geraete.json") : ""; } }
    static readonly string[] keepValues = new string[] { "entfernen", "behalten" };
    static readonly string[] driverValues = new string[] { "verwenden", "nein" };

    Dictionary<string, object> ReadDeviceFile()
    {
        try
        {
            if (DeviceFile.Length == 0 || !File.Exists(DeviceFile)) return null;
            System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
            Dictionary<string, object> d = js.DeserializeObject(File.ReadAllText(DeviceFile, Encoding.UTF8)) as Dictionary<string, object>;
            object fm; if (d == null || !d.TryGetValue("Format", out fm) || Convert.ToString(fm) != "Minibench-Geraete/1") return null;
            return d;
        }
        catch { return null; }
    }

    void LoadDeviceTools()
    {
        if (deviceId.Length == 0) return;
        Dictionary<string, object> d = ReadDeviceFile(); if (d == null) return;
        object g; if (!d.TryGetValue("Geraete", out g)) return;
        Dictionary<string, object> gd = g as Dictionary<string, object>; object e;
        if (gd == null || !gd.TryGetValue(deviceId, out e)) return;
        Dictionary<string, object> ed = e as Dictionary<string, object>; if (ed == null) return;
        object w; if (cmbKeep != null && ed.TryGetValue("Werkzeuge", out w)) {
            string ws = Convert.ToString(w);
            cmbKeep.SelectedIndex = (ws == "behalten") ? 1 : 0;
        }
        object t; if (cmbDriver != null && ed.TryGetValue("Treiber", out t)) {
            string ts = Convert.ToString(t);
            cmbDriver.SelectedIndex = (ts == "nein") ? 1 : 0;
        }
    }

    void SaveDeviceTools()
    {
        if (deviceId.Length == 0 || DeviceFile.Length == 0 || running || presetLoading) return;
        try
        {
            Dictionary<string, object> d = ReadDeviceFile() ?? new Dictionary<string, object>();
            d["Format"] = "Minibench-Geraete/1";
            object g; Dictionary<string, object> gd = d.TryGetValue("Geraete", out g) ? g as Dictionary<string, object> : null;
            if (gd == null) { gd = new Dictionary<string, object>(); d["Geraete"] = gd; }
            object e; Dictionary<string, object> ed = gd.TryGetValue(deviceId, out e) ? e as Dictionary<string, object> : null;
            if (ed == null) { ed = new Dictionary<string, object>(); ed["Behalten"] = new object[0]; gd[deviceId] = ed; }
            ed["Name"] = Environment.MachineName;
            if (cmbKeep != null) ed["Werkzeuge"] = keepValues[Math.Max(0, Math.Min(keepValues.Length - 1, cmbKeep.SelectedIndex))];
            if (cmbDriver != null) ed["Treiber"] = driverValues[Math.Max(0, Math.Min(driverValues.Length - 1, cmbDriver.SelectedIndex))];
            if (!ed.ContainsKey("Behalten")) ed["Behalten"] = new object[0];
            ed["Geaendert"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
            Directory.CreateDirectory(dataDir);
            System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
            File.WriteAllText(DeviceFile, js.Serialize(d), new UTF8Encoding(false));
        }
        catch { }
    }

    // Argument für den Arbeitsprozess: Wahl im Startdialog, sonst feste Einstellung
    string KeepArg()
    {
        string k = runKeep;
        if (k.Length == 0 && cmbKeep != null) k = keepValues[Math.Max(0, Math.Min(keepValues.Length - 1, cmbKeep.SelectedIndex))];
        return k.Length > 0 ? " -WerkzeugeBehalten " + k : "";
    }

    void UpdateSensStatusBadge(string stateOverride = null, string tooltipOverride = null)
    {
        if (badgeSensStatus == null) return;
        if (!String.IsNullOrEmpty(stateOverride))
        {
            SetSensorBadgeState(stateOverride, tooltipOverride);
            return;
        }

        string pv = PawnIoVersion();
        bool drvDisabled = (cmbDriver != null && cmbDriver.SelectedIndex == 1);
        if (drvDisabled)
        {
            SetSensorBadgeState("Inaktiv", "Inaktiv: Sensorüberwachung bzw. Sensortreiber explizit deaktiviert.");
        }
        else if (LhmPresent && (pv.Length > 0 || PawnSetupPresent))
        {
            SetSensorBadgeState("Vollstaendig", "Vollständig (Ring-0-Treiber aktiv): PawnIO / WinRing0 geladen, Live-Taktraten, Package-Power und Hotspot-Temperaturen verfügbar.");
        }
        else
        {
            SetSensorBadgeState("Eingeschraenkt", "Eingeschränkt (Standard-WMI / Leistungszähler): Basis-Takte und Standard-Temperaturen vorhanden, keine direkte VRM/Power-Telemetrie.");
        }
    }

    void SetSensorBadgeState(string state, string tooltip)
    {
        if (badgeSensStatus == null) return;
        switch (state)
        {
            case "Vollstaendig":
                badgeSensStatus.Text = "● Vollständig";
                badgeSensStatus.Level = "ok";
                Tip(badgeSensStatus, !String.IsNullOrEmpty(tooltip) ? tooltip : "Vollständig (Ring-0-Treiber aktiv): PawnIO / WinRing0 geladen, Live-Taktraten, Package-Power und Hotspot-Temperaturen verfügbar.");
                break;
            case "Eingeschraenkt":
                badgeSensStatus.Text = "● Eingeschränkt";
                badgeSensStatus.Level = "warn";
                Tip(badgeSensStatus, !String.IsNullOrEmpty(tooltip) ? tooltip : "Eingeschränkt (Standard-WMI / Leistungszähler): Basis-Takte und Standard-Temperaturen vorhanden, keine direkte VRM/Power-Telemetrie.");
                break;
            case "Inaktiv":
                badgeSensStatus.Text = "○ Inaktiv";
                badgeSensStatus.Level = "skip";
                Tip(badgeSensStatus, !String.IsNullOrEmpty(tooltip) ? tooltip : "Inaktiv: Sensorüberwachung explizit deaktiviert oder keine kompatible Hardware gefunden.");
                break;
            case "Fehler":
                badgeSensStatus.Text = "● Fehler";
                badgeSensStatus.Level = "crit";
                Tip(badgeSensStatus, !String.IsNullOrEmpty(tooltip) ? tooltip : "Fehler: Treiberabsturz oder Zugriffsverweigerung (Details im Protokoll).");
                break;
            default:
                badgeSensStatus.Text = state;
                badgeSensStatus.Level = "skip";
                Tip(badgeSensStatus, tooltip ?? "");
                break;
        }
    }

    void UpdateSensTools()
    {
        if (lblSensTools == null) return;
        string pv = PawnIoVersion();
        string t;
        if (!LhmPresent) t = "LibreHardwareMonitor fehlt im Tools-Ordner. Ohne die Bibliothek zeigt die Seite nur Ersatzwerte (Windows-Takt, ACPI, nvidia-smi, Datenträger, Akku).";
        else t = "LibreHardwareMonitor liegt im Tools-Ordner (geladen wird nur mit passender Prüfsumme).";
        t += pv.Length > 0 ? "  PawnIO " + pv + " ist auf diesem PC installiert und bleibt unverändert." : (PawnSetupPresent ? "  PawnIO ist nicht installiert; das Setup liegt bereit." : "  PawnIO-Setup fehlt.");
        lblSensTools.Text = t;
        lblSensTools.ForeColor = LhmPresent ? UI.Muted : UI.Warn;
        btnSensTools.Text = LhmPresent && PawnSetupPresent ? "Sensorwerkzeuge erneut holen" : "Sensorwerkzeuge holen";
        UpdateSensStatusBadge();
    }

    Control BuildSensorPage()
    {
        FlowLayoutPanel f = Page("Sensoren live", "Zeigt Temperatur, Takt, Lüfter, Spannung und Leistung laufend an (Kurven der letzten zehn Minuten). CPU-Werte und Mainboard-Lüfter brauchen den Treiber PawnIO; er wird beim Beenden wieder entfernt.", -1);
        lblSensTools = Lbl("", 9f, false, UI.Muted); lblSensTools.MaximumSize = new Size(UI.S(UI.Gruppenbreite), 0); lblSensTools.Margin = new Padding(UI.S(4), 0, UI.S(4), UI.S(8)); f.Controls.Add(lblSensTools);
        FlowLayoutPanel b = Row(); b.Margin = new Padding(UI.S(4), 0, 0, UI.S(8));
        btnLive = UI.Primary("Live-Ansicht starten"); btnLive.Margin = new Padding(0); btnLive.Padding = new Padding(UI.S(14), UI.S(3), UI.S(14), UI.S(3)); btnLive.Font = new Font("Segoe UI Semibold", 9.75f);
        btnLive.Click += delegate { if (liveRunning) StopLive(); else StartLive(); };
        btnSensTools = UI.Secondary("Sensorwerkzeuge holen"); btnSensTools.Margin = new Padding(UI.S(8), 0, 0, 0); btnSensTools.Click += delegate { FetchSensorTools(); };
        btnSensSave = UI.Secondary("Aufzeichnung speichern"); btnSensSave.Margin = new Padding(UI.S(8), 0, 0, 0); btnSensSave.Enabled = false; btnSensSave.Click += delegate { SaveSensorCsv(); };
        b.Controls.Add(btnLive); b.Controls.Add(btnSensTools); b.Controls.Add(btnSensSave);
        f.Controls.Add(b);
        FlowLayoutPanel bd = Row(); bd.Margin = new Padding(UI.S(4), 0, 0, UI.S(8));
        bd.Controls.Add(RowLabel("PawnIO-Treiber", 120));
        cmbDriver = Combo(230, new string[] { "vorübergehend verwenden (Standard)", "nicht verwenden" }, 0); bd.Controls.Add(cmbDriver);
        Label ld = Lbl("gilt für Live-Ansicht, Diagnose, Benchmark und Lasttest; ein vorhandener PawnIO bleibt immer unverändert", 8.75f, false, UI.Muted); ld.Margin = new Padding(0, UI.S(5), 0, 0); bd.Controls.Add(ld);
        f.Controls.Add(bd);
        FlowLayoutPanel bk = Row(); bk.Margin = new Padding(UI.S(4), 0, 0, UI.S(8));
        bk.Controls.Add(RowLabel("Hilfswerkzeuge", 120));
        cmbKeep = Combo(230, new string[] { "nach dem Lauf entfernen (Standard)", "auf diesem PC behalten" }, 0); bk.Controls.Add(cmbKeep);
        Label lk = Lbl("PawnIO und smartmontools, die Leos Minibench installiert hat; gespeichert je Gerät in Geraete.json", 8.75f, false, UI.Muted); lk.Margin = new Padding(0, UI.S(5), 0, 0); bk.Controls.Add(lk);
        f.Controls.Add(bk);
        LoadDeviceTools();
        cmbKeep.SelectedIndexChanged += delegate { SaveDeviceTools(); };
        cmbDriver.SelectedIndexChanged += delegate { SaveDeviceTools(); UpdateSensStatusBadge(); };
        lblSensInfo = Lbl("Live-Ansicht nicht gestartet.", 9f, false, UI.Muted); lblSensInfo.MaximumSize = new Size(UI.S(UI.Gruppenbreite), 0); lblSensInfo.Margin = new Padding(UI.S(4), 0, UI.S(4), UI.S(6)); f.Controls.Add(lblSensInfo);
        chartLive = new SensorChart(); chartLive.Width = UI.S(UI.Gruppenbreite); chartLive.Height = UI.S(330); chartLive.WindowSec = 600; chartLive.Margin = new Padding(UI.S(4), 0, 0, UI.S(8));
        chartLive.Empty = "Noch keine Messwerte. \"Live-Ansicht starten\" öffnet die Sensoren.";
        f.Controls.Add(chartLive);
        lvSens = new ListView(); lvSens.View = View.Details; lvSens.FullRowSelect = true; lvSens.Width = UI.S(UI.Gruppenbreite); lvSens.Height = UI.S(380); lvSens.BorderStyle = BorderStyle.FixedSingle; lvSens.HideSelection = false; lvSens.ShowGroups = true; lvSens.ShowItemToolTips = true; lvSens.Margin = new Padding(UI.S(4), 0, 0, UI.S(4));
        EnableDarkListView(lvSens);
        string[] cols = new string[] { "Sensor", "Art", "Aktuell", "Min", "Max", "Quelle" };
        int[] w = new int[] { UI.S(240), UI.S(110), UI.S(100), UI.S(100), UI.S(100), UI.S(120) };
        for (int i = 0; i < cols.Length; i++) lvSens.Columns.Add(cols[i], w[i], i >= 2 && i <= 4 ? HorizontalAlignment.Right : HorizontalAlignment.Left);
        f.Controls.Add(lvSens);
        Label hint = Lbl("\"Aufzeichnung speichern\" legt alle Werte als CSV unter Berichte\\Sensoren ab. Während eines Laufs ist die Live-Ansicht aus; der Lasttest zeigt seine Kurven im Reiter Sensoren.", 8.75f, false, UI.Muted);
        hint.MaximumSize = new Size(UI.S(UI.Gruppenbreite), 0); hint.Margin = new Padding(UI.S(4), UI.S(4), UI.S(4), 0); f.Controls.Add(hint);
        liveTimer = new Timer(); liveTimer.Interval = 250; liveTimer.Tick += delegate { OnLiveTick(); };
        UpdateSensTools();
        return f;
    }

    void FetchSensorTools()
    {
        if (liveRunning) { MessageBox.Show(this, "Bitte zuerst die Live-Ansicht beenden.", "Leos Minibench"); return; }
        if (MessageBox.Show(this, "LibreHardwareMonitor " + "0.9.6 und PawnIO-Setup 2.2.0 aus den offiziellen GitHub-Releases holen?\r\n\r\nDie Dateien werden mit festen SHA-256-Werten geprüft und nur im Tools-Ordner des Datenordners abgelegt. Auf diesem PC wird nichts installiert.", "Sensorwerkzeuge holen", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        List<string> lines; string res = RunHelperPumped("-SensorWerkzeugeHolen", out lines, 900);
        UpdateSensTools();
        MessageBox.Show(this, lines.Count > 0 ? String.Join("\r\n", lines.ToArray()) : "Keine Rückmeldung vom Arbeitsprozess.", "Sensorwerkzeuge", MessageBoxButtons.OK, res == "1" ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
    }

    void StartLive()
    {
        if (running) return;
        TryAutoFetchSensorTools();
        bool drv = cmbDriver == null || cmbDriver.SelectedIndex == 0;
        try { Directory.CreateDirectory(cpDir); File.Delete(Path.Combine(cpDir, "sensor.stop")); } catch { }
        string args = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -EventMode -SensorLive" + (dataDir.Length > 0 ? " -DatenDir " + Q(dataDir) : "") + (drv ? " -SensorTreiber" : "") + KeepArg();
        ProcessStartInfo psi = new ProcessStartInfo(psExe, args);
        psi.UseShellExecute = false; psi.CreateNoWindow = true; psi.RedirectStandardOutput = true; psi.RedirectStandardError = true; psi.RedirectStandardInput = true;
        psi.StandardOutputEncoding = new UTF8Encoding(false); psi.StandardErrorEncoding = OemEncoding();
        liveProc = new Process(); liveProc.StartInfo = psi; liveProc.EnableRaisingEvents = true;
        liveProc.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) liveQueue.Enqueue(e.Data); else liveEof = true; };
        liveProc.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null && e.Data.Trim().Length > 0) liveQueue.Enqueue("@@SENSINFO|" + e.Data.Trim()); };
        liveProc.Exited += delegate { liveExited = true; };
        sensItems.Clear(); sensMinMax.Clear(); sensUnit.Clear(); sensNames.Clear(); sensRows.Clear(); sensGroups.Clear();
        lvSens.Items.Clear(); lvSens.Groups.Clear(); chartLive.Clear();
        string dummy; while (liveQueue.TryDequeue(out dummy)) { }
        liveExited = false; liveEof = false; liveStopping = false; liveExitSeen = DateTime.MinValue;
        try { liveProc.Start(); liveProc.BeginOutputReadLine(); liveProc.BeginErrorReadLine(); try { liveProc.StandardInput.Close(); } catch { } }
        catch (Exception ex) { MessageBox.Show(this, "PowerShell konnte nicht gestartet werden: " + ex.Message, "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Error); return; }
        liveRunning = true;
        btnLive.Text = "Live-Ansicht beenden"; btnSensTools.Enabled = false; btnSensSave.Enabled = false;
        lblSensInfo.Text = drv ? "Wird gestartet, PawnIO wird vorübergehend installiert ..." : "Wird gestartet ...";
        liveTimer.Start();
    }

    void StopLive()
    {
        if (!liveRunning || liveStopping) return;
        liveStopping = true; liveStopAt = DateTime.Now;
        try { Directory.CreateDirectory(cpDir); File.WriteAllText(Path.Combine(cpDir, "sensor.stop"), "1"); } catch { }
        btnLive.Enabled = false; btnLive.Text = "Wird beendet ...";
        lblSensInfo.Text = "Wird beendet, ein vorübergehend installierter Treiber wird entfernt ...";
    }

    // Für Start eines Laufs und Schließen des Fensters: sauber beenden (Treiber entfernen), höchstens 60 Sekunden warten
    bool StopLiveAndWait()
    {
        if (!liveRunning) return true;
        StopLive();
        Cursor = Cursors.WaitCursor; Enabled = false;
        // Installation und Entfernung von PawnIO dürfen je bis zu 3 Minuten dauern
        DateTime until = DateTime.Now.AddSeconds(240);
        while (!liveExited && DateTime.Now < until) { Application.DoEvents(); System.Threading.Thread.Sleep(100); }
        bool killed = !liveExited;
        if (killed) KillProc(liveProc);
        DateTime eofUntil = DateTime.Now.AddSeconds(5);
        while (!liveEof && DateTime.Now < eofUntil) { Application.DoEvents(); System.Threading.Thread.Sleep(50); }
        liveExited = true;
        Enabled = true; Cursor = Cursors.Default;
        OnLiveTick();
        if (killed) CleanupDriver();
        return true;
    }

    void OnLiveTick()
    {
        string line; int n = 0;
        if (!liveQueue.IsEmpty)
        {
            lvSens.BeginUpdate();
            try { while (n < 2000 && liveQueue.TryDequeue(out line)) { n++; HandleLiveLine(line); } }
            finally { lvSens.EndUpdate(); }
        }
        chartLive.Flush();
        bool killed = false;
        if (liveStopping && !liveExited && (DateTime.Now - liveStopAt).TotalSeconds > 240) { KillProc(liveProc); killed = true; }
        if (liveExited && liveExitSeen == DateTime.MinValue) liveExitSeen = DateTime.Now;
        if (liveExited && (liveEof || (DateTime.Now - liveExitSeen).TotalSeconds > 5) && liveQueue.IsEmpty && liveRunning)
        {
            liveRunning = false; liveStopping = false; liveTimer.Stop();
            btnLive.Enabled = true; btnLive.Text = "Live-Ansicht starten"; btnSensTools.Enabled = true; btnSensSave.Enabled = sensRows.Count > 0;
            if (killed || PawnMarkerExists) CleanupDriver();
            UpdateSensTools();
            ReloadDb();
        }
    }

    // Markierung eines vorübergehend installierten PawnIO (wie Get-PawnIoMarker im Skript)
    string PawnMarker
    {
        get
        {
            if (dataDir.Length == 0) return "";
            string pc = Environment.GetEnvironmentVariable("COMPUTERNAME"); if (String.IsNullOrEmpty(pc)) pc = Environment.MachineName;
            string n = System.Text.RegularExpressions.Regex.Replace(pc, "[\\/:*?\"<>|\\s]+", "_").Trim('_');
            return Path.Combine(Path.Combine(dataDir, "Laufzeit"), "PawnIO_" + n + ".txt");
        }
    }
    bool PawnMarkerExists { get { string m = PawnMarker; return m.Length > 0 && File.Exists(m); } }

    // Treiberrest eines abgebrochenen Arbeitsprozesses sofort entfernen statt erst beim nächsten Start
    void CleanupDriver()
    {
        if (!PawnMarkerExists) return;
        List<string> lines;
        string ok = RunHelperPumped("-SensorAufraeumen", out lines, 300);
        string t = lines.Count > 0 ? String.Join(" ", lines.ToArray()) : "PawnIO-Treiber: keine Rückmeldung";
        if (lblSensInfo != null) lblSensInfo.Text = t;
        if (running || done) { lblCounter.Text = ok == "1" ? "PawnIO-Treiber wieder entfernt" : "PawnIO-Treiber noch installiert"; }
        if (ok != "1") MessageBox.Show(this, "Der vorübergehend installierte PawnIO-Treiber konnte nicht entfernt werden:\r\n\r\n" + t + "\r\n\r\nDer nächste Start von Leos Minibench versucht es erneut.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }

    string RunHelper(string args, out List<string> lines)
    {
        lines = new List<string>();
        ProcessStartInfo psi = new ProcessStartInfo(psExe, "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -EventMode " + args + " -DatenDir \"" + dataDir.TrimEnd('\\') + "\"");
        psi.UseShellExecute = false; psi.CreateNoWindow = true; psi.RedirectStandardOutput = true; psi.StandardOutputEncoding = new UTF8Encoding(false);
        string result = "";
        using (Process p = Process.Start(psi))
        {
            string all = p.StandardOutput.ReadToEnd(); p.WaitForExit(120000);
            foreach (string line in all.Split('\n'))
            {
                string l = line.TrimEnd('\r');
                if (l.StartsWith("@@LOG|")) { string[] x = l.Split(new char[] { '|' }, 3); if (x.Length == 3 && x[2].Trim().Length > 0) lines.Add(x[2].Trim()); }
                else if (l.StartsWith("@@RESULT|")) result = l.Substring(9);
            }
        }
        return result;
    }

    // Wie RunHelper, aber ohne die Oberfläche einzufrieren (Downloads, Treiber entfernen)
    string RunHelperPumped(string args, out List<string> lines, int timeoutSec) { return RunHelperPumped(args, out lines, timeoutSec, null); }

    // Wie RunHelper, aber ohne die Oberfläche einzufrieren; Fortschritt des Abgleichs (@@ABGLEICH|Nr|Anzahl|Datei) im Label
    string RunHelperPumped(string args, out List<string> lines, int timeoutSec, Label progress)
    {
        List<string> got = new List<string>();
        string result = "";
        ProcessStartInfo psi = new ProcessStartInfo(psExe, "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -EventMode " + args + (dataDir.Length > 0 ? " -DatenDir \"" + dataDir.TrimEnd('\\') + "\"" : ""));
        psi.UseShellExecute = false; psi.CreateNoWindow = true; psi.RedirectStandardOutput = true; psi.StandardOutputEncoding = new UTF8Encoding(false);
        bool eof = false;
        Cursor = Cursors.WaitCursor; bool was = Enabled; Enabled = false;
        try
        {
            using (Process p = new Process())
            {
                p.StartInfo = psi;
                p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) {
                    if (e.Data == null) { eof = true; return; }
                    if (progress != null && e.Data.StartsWith("@@ABGLEICH|"))
                    {
                        string[] x = e.Data.Split(new char[] { '|' }, 4);
                        if (x.Length == 4) { string t = "Abgleich: " + x[1] + " von " + x[2] + ", " + x[3].Replace("¦", "|"); try { BeginInvoke(new MethodInvoker(delegate { SetText(progress, t); })); } catch { } }
                        return;
                    }
                    lock (got) got.Add(e.Data);
                };
                p.Start(); p.BeginOutputReadLine();
                DateTime until = DateTime.Now.AddSeconds(timeoutSec);
                while (!p.HasExited && DateTime.Now < until) { Application.DoEvents(); System.Threading.Thread.Sleep(50); }
                if (!p.HasExited) { KillProc(p); lock (got) got.Add("@@LOG||Abgebrochen nach " + timeoutSec + " Sekunden."); }
                DateTime eu = DateTime.Now.AddSeconds(5);
                while (!eof && DateTime.Now < eu) { Application.DoEvents(); System.Threading.Thread.Sleep(20); }
            }
        }
        catch (Exception ex) { lock (got) got.Add("@@LOG||" + ex.Message); }
        finally { Enabled = was; Cursor = Cursors.Default; }
        lines = new List<string>();
        lock (got)
            foreach (string l in got)
            {
                if (l.StartsWith("@@LOG|")) { string[] x = l.Split(new char[] { '|' }, 3); if (x.Length == 3 && x[2].Trim().Length > 0) lines.Add(x[2].Trim()); }
                else if (l.StartsWith("@@RESULT|")) result = l.Substring(9);
                else if (l.StartsWith("@@OPTZ|")) lines.Add(l);
            }
        return result;
    }

    static void KillProc(Process p)
    {
        try
        {
            if (p != null && !p.HasExited)
            {
                ProcessStartInfo k = new ProcessStartInfo("taskkill.exe", "/T /F /PID " + p.Id); k.CreateNoWindow = true; k.UseShellExecute = false;
                Process kp = Process.Start(k); kp.WaitForExit(8000);
            }
        }
        catch { }
    }

    static double ParseD(string s) { double v; return double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : double.NaN; }

    static string FmtSens(double v, string unit)
    {
        if (double.IsNaN(v)) return "";
        string f = unit == "V" ? "0.000" : (unit == "W" || unit == "A") ? "0.0" : "0";
        return v.ToString(f, CultureInfo.GetCultureInfo("de-DE")) + " " + unit;
    }

    void HandleLiveLine(string line)
    {
        if (!line.StartsWith("@@")) return;
        string[] p = line.Substring(2).Split('|');
        switch (p[0])
        {
            case "SENSDEF":
                {
                    // SENSDEF|idx|Gruppe|Geraet|Art|Name|Einheit|Quelle
                    int idx = ToInt(p, 1);
                    string grp = Get(p, 2) + "  ·  " + Get(p, 3);
                    ListViewGroup lg;
                    if (!sensGroups.TryGetValue(grp, out lg)) { lg = new ListViewGroup(grp, grp); sensGroups[grp] = lg; lvSens.Groups.Add(lg); }
                    string art = Get(p, 4);
                    ListViewItem it = new ListViewItem(new string[] { Get(p, 5), art == "Grenzwert" ? "Grenzwert (Hersteller)" : art, "", "", "", Get(p, 7) }, lg);
                    // Grenzwerte laut Hersteller sind keine Messwerte: grau und ohne Min/Max-Bewertung
                    if (art == "Grenzwert" || art == "Abstand") { it.ForeColor = UI.Muted; it.ToolTipText = art == "Grenzwert" ? "Vorgabe des Herstellers, keine gemessene Temperatur" : "Abstand zur Höchsttemperatur TjMax"; }
                    else it.ToolTipText = "Quelle: " + Get(p, 7);
                    sensItems[idx] = it; sensUnit[idx] = Get(p, 6); sensMinMax[idx] = new double[] { double.MaxValue, double.MinValue };
                    while (sensNames.Count <= idx) sensNames.Add("");
                    sensNames[idx] = (Get(p, 2) + " " + Get(p, 3) + " " + Get(p, 5) + " (" + Get(p, 6) + ")").Replace(";", ",");
                    lvSens.Items.Add(it);
                    break;
                }
            case "SENSVAL":
                {
                    // SENSVAL|Sekunde|idx:wert;idx:wert
                    if (sensRows.Count < 50000) sensRows.Add(Get(p, 1) + "|" + Get(p, 2));
                    foreach (string kv in Get(p, 2).Split(';'))
                    {
                        int c = kv.IndexOf(':'); if (c <= 0) continue;
                        int idx; if (!int.TryParse(kv.Substring(0, c), out idx)) continue;
                        double v = ParseD(kv.Substring(c + 1));
                        ListViewItem it; if (!sensItems.TryGetValue(idx, out it) || double.IsNaN(v)) continue;
                        double[] mm = sensMinMax[idx]; mm[0] = Math.Min(mm[0], v); mm[1] = Math.Max(mm[1], v);
                        string u = sensUnit[idx];
                        string a = FmtSens(v, u); if (it.SubItems[2].Text != a) { it.SubItems[2].Text = a; if (!it.UseItemStyleForSubItems) it.SubItems[2].ForeColor = it.ForeColor; }
                        string mi = FmtSens(mm[0], u); if (it.SubItems[3].Text != mi) it.SubItems[3].Text = mi;
                        string ma = FmtSens(mm[1], u); if (it.SubItems[4].Text != ma) it.SubItems[4].Text = ma;
                    }
                    break;
                }
            case "SENSBAD":
                {
                    // SENSBAD|idx|Rohwert|Grund: unplausibler Wert, wird nicht angezeigt und zählt nicht für Min/Max
                    ListViewItem it; int idx = ToInt(p, 1);
                    if (!sensItems.TryGetValue(idx, out it)) break;
                    if (it.SubItems[2].Text != "unplausibel") { it.SubItems[2].Text = "unplausibel"; it.UseItemStyleForSubItems = false; it.SubItems[2].ForeColor = UI.Crit; }
                    string tip = "Verworfen: " + Get(p, 3) + " (Rohwert " + Get(p, 2) + ")";
                    if (it.ToolTipText != tip) it.ToolTipText = tip;
                    break;
                }
            case "SENSLEAD": chartLive.Add(p); break;
            case "SENSINFO": lblSensInfo.Text = Get(p, 1); break;
            case "SENSSTAT": UpdateSensStatusBadge(Get(p, 1), Get(p, 2)); break;
            case "SENSEND": lblSensInfo.Text = "Beendet. " + Get(p, 1); break;
            case "LOG": { string t = p.Length > 2 ? String.Join("|", p, 2, p.Length - 2).Trim() : ""; if (t.Length > 0) lblSensInfo.Text = t; break; }
        }
    }

    void SaveSensorCsv()
    {
        if (sensRows.Count == 0 || dataDir.Length == 0) return;
        try
        {
            string dir = Path.Combine(Path.Combine(dataDir, "Berichte"), "Sensoren");
            Directory.CreateDirectory(dir);
            string file = Path.Combine(dir, Environment.MachineName + "_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".csv");
            StringBuilder sb = new StringBuilder();
            sb.Append("Sekunde"); foreach (string n in sensNames) sb.Append(';').Append(n); sb.AppendLine();
            foreach (string r in sensRows)
            {
                string[] x = r.Split(new char[] { '|' }, 2);
                string[] cells = new string[sensNames.Count];
                foreach (string kv in (x.Length > 1 ? x[1] : "").Split(';'))
                {
                    int c = kv.IndexOf(':'); int idx;
                    if (c > 0 && int.TryParse(kv.Substring(0, c), out idx) && idx < cells.Length) cells[idx] = kv.Substring(c + 1).Replace('.', ',');
                }
                sb.Append(x[0]); foreach (string c in cells) sb.Append(';').Append(c ?? ""); sb.AppendLine();
            }
            File.WriteAllText(file, sb.ToString(), new UTF8Encoding(true));
            OpenSelect(file);
        }
        catch (Exception ex) { MessageBox.Show(this, "Speichern fehlgeschlagen: " + ex.Message, "Leos Minibench"); }
    }

    // ------------------------------------------------------------ Seite Änderungen
    // ------------------------------------------------------------ Seite Versionen (ab v2.7)
    int SmartMax() { return cmbSmartMax != null && cmbSmartMax.SelectedIndex >= 0 && cmbSmartMax.SelectedIndex < smartMinutes.Length ? smartMinutes[cmbSmartMax.SelectedIndex] : 120; }

    int Minutes(ComboBox c) { int v; return int.TryParse(Convert.ToString(c.SelectedItem).Split(' ')[0], out v) ? v : 2; }

    List<string> SelectedModules()
    {
        List<string> m = new List<string>();
        string[] names = new string[] { "Diagnose", "Benchmark", "Lasttest", "Wartung", "Optimierung" };
        for (int i = 0; i < names.Length; i++) if (nav[i].Checked) m.Add(names[i]);
        return m;
    }

    // Geschätzte Minuten je Modul (Index wie nav), ohne Wartezeit auf den SMART-Langtest
    int ModuleMinutes(int mod)
    {
        int t = 0;
        if (mod == 0)
        {
            bool[] cur = new bool[diagChk.Length];
            for (int i = 0; i < diagChk.Length; i++) cur[i] = diagChk[i].Checked;
            t = DiagEstimate(cur);
        }
        else if (mod == 1)
        {
            bool kurz = false;
            if (benchChk[0].Checked) t += kurz ? 1 : 2;
            if (benchChk[1].Checked) t += 1;
            if (benchChk[2].Checked) t += 2;
            if (benchChk[3].Checked) t += clbDisks.CheckedItems.Count;
            if (benchChk[4].Checked) t += 1;
        }
        else if (mod == 2)
        {
            int m = LoadTotalMinutes(new bool[] { chkLCpu.Checked, chkLRam.Checked, chkLGpu.Checked, chkLDisk.Checked },
                new int[] { Minutes(cmbLCpu), Minutes(cmbLRam), Minutes(cmbLGpu), Minutes(cmbLDisk) + 1 });
            t = m + 1;
        }
        else if (mod == 3) { for (int i = 0; i < repChk.Length; i++) if (repChk[i].Checked) t += repMinutes[i]; }
        else if (mod == 4) { int n = 0; foreach (OptItem it in optItems) if (it.Box.Checked) { n++; t += it.Minuten; } t += 1 + n / 40; }
        return t;
    }

    int EstimateMinutes()
    {
        int t = 0;
        for (int i = 0; i < 5; i++) if (nav[i].Checked) t += ModuleMinutes(i);
        return t;
    }

    // Lasttest: alle gewählten Komponenten laufen gleichzeitig, die Gesamtdauer ist die längste gewählte Dauer
    public static int LoadTotalMinutes(bool[] on, int[] minutes)
    {
        int m = 0;
        for (int i = 0; on != null && minutes != null && i < on.Length && i < minutes.Length; i++) if (on[i]) m = Math.Max(m, minutes[i]);
        return m;
    }

    // Beschriftung des Startknopfs: sagt, was er startet (vorher immer nur "Start", auch auf der Seite Tools)
    public static string StartButtonText(List<string> modules)
    {
        if (modules == null || modules.Count == 0) return "Start";
        if (modules.Count == 1) return modules[0] + " starten";
        return modules.Count + " Module starten";
    }

    // Kurzform für Minuten: "45 Min.", "1 Std. 20 Min."
    public static string MinText(int min)
    {
        min = Math.Max(1, min);
        if (min < 60) return min + " Min.";
        return (min / 60) + " Std." + (min % 60 > 0 ? " " + (min % 60) + " Min." : "");
    }

    void UpdateSummary()
    {
        UpdateDiagSummary();
        UpdateLoadTotal();
        if (lblSel == null || btnStart == null || diagChk == null || benchChk == null || repChk == null || chkLCpu == null || chkOptRestore == null) return;
        List<string> m = SelectedModules();
        for (int i = 0; i < 5 && i < nav.Count; i++) { string h = nav[i].Checked ? "ca. " + MinText(ModuleMinutes(i)) : ""; if (nav[i].Hint != h) { nav[i].Hint = h; nav[i].Invalidate(); } }
        SetText(btnStart, StartButtonText(m));
        if (m.Count == 0)
        {
            lblSel.Text = "Kein Modul ausgewählt: in der Seitenleiste mindestens ein Modul anhaken"; lblSel.ForeColor = UI.Crit; btnStart.Enabled = false;
            Tip(btnStart, "Erst ein Modul in der Seitenleiste anhaken.");
            return;
        }
        int min = EstimateMinutes();
        bool smart = nav[0].Checked && diagChk[4].Checked;
        lblSel.ForeColor = UI.Text;
        List<string> shown = new List<string>(m);
        if (nav[0].Checked && chkFast != null && chkFast.Checked && chkFast.Enabled && shown.Count > 0 && shown[0] == "Diagnose") shown[0] = "Diagnose (parallel)";
        lblSel.Text = String.Join("  →  ", shown.ToArray())
            + "   ·   ca. " + MinText(min) + (smart ? ", mit SMART-Langtest höchstens " + MinText(min + SmartMax()) : "");
        btnStart.Enabled = true;
        Tip(btnStart, "Startet " + (m.Count == 1 ? "das Modul " + m[0] : "die Module in dieser Reihenfolge: " + String.Join(", ", m.ToArray())) + ". Geschätzte Dauer ca. " + MinText(min) + (smart ? " zuzüglich Warten auf den SMART-Langtest" : "") + ".");
    }

    static string Q(string s) { return "\"" + (s ?? "").TrimEnd('\\') + "\""; }

    void StartRun()
    {
        List<string> mods = SelectedModules();
        if (mods.Count == 0) return;
        // Live-Ansicht und Lauf greifen auf dieselben Sensoren und denselben Treiber zu
        if (liveRunning && !StopLiveAndWait()) return;
        bool drv = false; runKeep = "";
        if (nav[0].Checked || nav[1].Checked || nav[2].Checked)
        {
            TryAutoFetchSensorTools();
            drv = cmbDriver == null || cmbDriver.SelectedIndex == 0;
        }
        List<StartPunkt> punkte = new List<StartPunkt>(); List<string> wp = new List<string>(), zusatz = new List<string>(); bool ohneWp = false;
        StringBuilder a = new StringBuilder();
        a.Append("-NoProfile -ExecutionPolicy Bypass -File \"").Append(script).Append("\" -EventMode");
        a.Append(" -Module ").Append(String.Join(",", mods.ToArray()));
        if (dataDir.Length > 0) a.Append(" -DatenDir ").Append(Q(dataDir));
        if (!chkAnon.Checked) a.Append(" -KiOhneAnonymisierung");

        if (nav[0].Checked)
        {
            string prof = rbVoll.Checked ? "Voll" : rbSchnell.Checked ? "Schnell" : "Benutzerdefiniert";
            a.Append(" -DiagProfil ").Append(prof);
            List<string> o = new List<string>();
            for (int i = 0; i < diagChk.Length; i++) if (diagChk[i].Checked) o.Add(diagKeys[i]);
            a.Append(" -DiagOptionen ").Append(o.Count > 0 ? String.Join(",", o.ToArray()) : "Keine");
            if (chkInstall.Enabled && chkInstall.Checked) a.Append(" -InstallSmartmontools");
            if (chkMem.Enabled && chkMem.Checked) a.Append(" -ScheduleWindowsMemTest");
            if (cmbDays.Enabled) a.Append(" -EventDays ").Append(Convert.ToString(cmbDays.SelectedItem).Split(' ')[0]);
            if (diagChk[4].Checked) a.Append(" -SmartTimeoutMinutes ").Append(SmartMax());
        }
        if (nav[1].Checked)
        {
            List<string> b = new List<string>();
            for (int i = 0; i < benchChk.Length; i++) if (benchChk[i].Checked) b.Add(benchKeys[i]);
            if (b.Count == 0) { MessageBox.Show(this, "Im Benchmark ist keine Messung ausgewählt.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information); ShowPage(1); return; }
            a.Append(" -BenchTests ").Append(String.Join(",", b.ToArray()));
            if (benchChk[3].Checked)
            {
                List<string> dn = new List<string>();
                for (int i = 0; i < clbDisks.Items.Count && i < diskNums.Count; i++) if (clbDisks.GetItemChecked(i)) dn.Add(diskNums[i]);
                if (dn.Count == 0) { MessageBox.Show(this, "Für den Laufwerks-Benchmark ist kein Laufwerk ausgewählt.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information); ShowPage(1); return; }
                a.Append(" -BenchLaufwerke ").Append(String.Join(",", dn.ToArray()));
            }
            if (benchChk[2].Checked && chkGpuWahl != null && chkGpuWahl.Checked) a.Append(" -BenchGpuWahl");
            List<string> cmp = new List<string>();
            if (clbCompare.Enabled) for (int i = 0; i < clbCompare.Items.Count && i < cmpItems.Count; i++) if (clbCompare.GetItemChecked(i)) cmp.Add(cmpItems[i].Path);
            if (cmp.Count > 0) a.Append(" -VergleichDateien ").Append(Q(String.Join(";", cmp.ToArray())));
        }
        if (nav[2].Checked)
        {
            if (!chkLCpu.Checked && !chkLRam.Checked && !chkLGpu.Checked && !chkLDisk.Checked) { MessageBox.Show(this, "Im Lasttest ist keine Komponente ausgewählt.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information); ShowPage(2); return; }
            if (chkLCpu.Checked) a.Append(" -LastCpuMinuten ").Append(Minutes(cmbLCpu));
            if (chkLRam.Checked) a.Append(" -LastRamMinuten ").Append(Minutes(cmbLRam)).Append(" -LastRamProzent ").Append(Convert.ToString(cmbLRamPct.SelectedItem).Split(' ')[0]);
            if (chkLGpu.Checked) a.Append(" -LastGpuMinuten ").Append(Minutes(cmbLGpu));
            if (chkLDisk.Checked) a.Append(" -LastDiskMinuten ").Append(Minutes(cmbLDisk)).Append(" -LastDiskLaufwerk ").Append(Convert.ToString(cmbLDiskDrive.SelectedItem).Substring(0, 1));
            a.Append(" -LastAbbruchCpu ").Append(AbortArg(cmbLAbortCpu)).Append(" -LastAbbruchGpu ").Append(AbortArg(cmbLAbortGpu));
        }
        if (nav[3].Checked)
        {
            List<string> r = new List<string>();
            for (int i = 0; i < repChk.Length; i++) if (repChk[i].Checked) { r.Add(repKeys[i]); punkte.Add(new StartPunkt("Wartung", SplitDetail(repText[i])[0], i < repRisk.Length && repRisk[i].Length > 0 ? repRisk[i] : "Eingriff", i < repRestart.Length ? repRestart[i] : "")); }
            if (r.Count == 0) { MessageBox.Show(this, "Im Wartungsmodul ist nichts ausgewählt.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information); ShowPage(3); return; }
            wp.Add("Wartung|" + (chkRestorePoint.Checked ? "1" : "0")); if (!chkRestorePoint.Checked) ohneWp = true;
            a.Append(" -Wartung ").Append(String.Join(",", r.ToArray()));
            if (!chkRestorePoint.Checked) a.Append(" -OhneWiederherstellungspunkt");
        }
        if (nav[4].Checked)
        {
            string optArgs = OptStartArgs(punkte, zusatz); if (optArgs == null) return;
            wp.Add("Optimierung|" + (chkOptRestore.Checked ? "1" : "0")); if (!chkOptRestore.Checked) ohneWp = true;
            a.Append(optArgs);
        }
        if (nav[0].Checked && chkMem.Enabled && chkMem.Checked) punkte.Add(new StartPunkt("Diagnose", "Windows-Speicherdiagnose beim nächsten Neustart", "Aendern", "immer"));
        // ab v3.64 eine Zusammenfassung vor dem Start, nur bei Eingriffen, Neustarts oder abgewähltem Wiederherstellungspunkt
        if ((StartUebersicht.Noetig(punkte, ohneWp) || zusatz.Count > 0) && !ConfirmStart(StartUebersicht.Text(mods, "ca. " + MinText(EstimateMinutes()), punkte, wp, zusatz), punkte)) return;
        if (nav[0].Checked && chkFast != null && chkFast.Enabled && chkFast.Checked) a.Append(" -SchnellerModus");
        bool gpuBench = nav[1].Checked && benchChk[2].Checked, gpuLoad = nav[2].Checked && chkLGpu.Checked;
        if (gpuBench || gpuLoad)
        {
            ComboBox res = gpuLoad ? cmbLGpuRes : cmbGpuRes, show = gpuLoad ? cmbLGpuShow : cmbGpuShow;
            a.Append(" -GpuAufloesung ").Append(Convert.ToString(res.SelectedItem));
            a.Append(" -GpuAnzeige ").Append(show.SelectedIndex == 1 ? "Vollbild" : show.SelectedIndex == 2 ? "Aus" : "Fenster");
            string gsel = GpuChoiceValue(gpuLoad ? cmbLGpuSel : cmbGpuSel);
            if (gsel != "Alle") a.Append(" -GpuAuswahl ").Append(Q(gsel));
        }
        // ab v2.66 ohne Rückfrage vor dem Grafik-Lasttest (Wunsch aus dem Praxistest); die Abbruchschwelle wirkt weiter, Esc im Vorschaufenster beendet
        if (drv) a.Append(" -SensorTreiber");
        a.Append(KeepArg());
        a.Append(" -PsuWattage ").Append(psuWattage);
        if (!string.IsNullOrEmpty(psuRating)) a.Append(" -PsuRating ").Append(Q(psuRating));
        Launch(a.ToString(), String.Join(" + ", mods.ToArray()));
    }

    // "automatisch ..." = auto, "aus" = aus, sonst die Zahl vor dem Gradzeichen
    static string AbortArg(ComboBox c)
    {
        string s = Convert.ToString(c.SelectedItem);
        if (s.StartsWith("automatisch", StringComparison.OrdinalIgnoreCase)) return "auto";
        if (s == "aus") return "aus";
        return s.Split(' ')[0];
    }

    // ------------------------------------------------------------ Protokoll eines Laufs ohne Bericht (ab v2.65)
    // Endet ein Lauf ohne Bericht (Abbruch, Fehler, Hänger), blieb der Berichtsordner bisher leer und die Rohdaten lagen
    // nur im lokalen TEMP (bei Adminrechten in dem des Admin-Kontos). Jetzt kommen Oberflächenprotokoll, Startargumente,
    // Konsole.log und Checkpoint.log des Arbeitsprozesses in den Berichtsordner.
    string runOutDir = "", runWorkDir = "", runArgs = "", lastStepText = "";
    DateTime runStarted;

    string SaveFailureLog(int code)
    {
        try
        {
            if (runOutDir.Length == 0 || !Directory.Exists(runOutDir)) return "";
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("LEOS MINIBENCH " + version + ": LAUF OHNE BERICHT");
            sb.AppendLine("Computer   : " + Environment.MachineName + ", Benutzer " + Environment.UserName);
            sb.AppendLine("Gestartet  : " + runStarted.ToString("dd.MM.yyyy HH:mm:ss", CultureInfo.InvariantCulture));
            sb.AppendLine("Beendet    : " + DateTime.Now.ToString("dd.MM.yyyy HH:mm:ss", CultureInfo.InvariantCulture) + (cancelled ? " (abgebrochen)" : ", Rückgabecode " + code));
            sb.AppendLine("Argumente  : " + runArgs);
            sb.AppendLine("Arbeitsordner: " + runWorkDir);
            sb.AppendLine("Letzter Schritt: " + lastStepText);
            sb.AppendLine();
            sb.AppendLine("--- Protokoll der Oberfläche ---");
            sb.AppendLine(txtLog.Text);
            string f = Path.Combine(runOutDir, "Protokoll_ohne_Bericht.txt");
            File.WriteAllText(f, sb.ToString(), new UTF8Encoding(true));
            if (runWorkDir.Length > 0)
            {
                foreach (string n in new string[] { "Konsole.log", "Checkpoint.log" })
                {
                    string src = Path.Combine(Path.Combine(runWorkDir, "Anhang"), n);
                    try { if (File.Exists(src)) using (FileStream i = new FileStream(src, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) using (FileStream o = File.Create(Path.Combine(runOutDir, n))) i.CopyTo(o); } catch { }
                }
            }
            return f;
        }
        catch { return ""; }
    }

    // ------------------------------------------------------------ Grafikeinheiten (ab v2.65)
    static string GpuKind(string n)
    {
        n = (n ?? "").Trim();
        if (n.Length == 0) return "";
        if (System.Text.RegularExpressions.Regex.IsMatch(n, "Virtual|Remote|Indirect|Parsec|spacedesk|Basic Display|Basic Render|Standard-VGA|Hyper-V|VMware|VirtualBox|Citrix|DisplayLink", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) return "virtuell";
        if (System.Text.RegularExpressions.Regex.IsMatch(n, "NVIDIA|GeForce|Quadro|Tesla|\\bRTX\\b|\\bGTX\\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) return "dGPU";
        if (n.IndexOf("Intel", StringComparison.OrdinalIgnoreCase) >= 0) return System.Text.RegularExpressions.Regex.IsMatch(n, "Arc(\\(TM\\))?\\s+(Pro\\s+)?[AB]\\d{2,3}", System.Text.RegularExpressions.RegexOptions.IgnoreCase) ? "dGPU" : "iGPU";
        if (System.Text.RegularExpressions.Regex.IsMatch(n, "AMD|ATI|Radeon|FirePro", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            return System.Text.RegularExpressions.Regex.IsMatch(n, "Graphics\\s*$|\\b\\d{3}M\\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase) ? "iGPU" : "dGPU";
        return "";
    }

    // Einträge der Auswahl: alle, nur Grafikkarte, nur Prozessorgrafik (wenn vorhanden), dann jede Einheit einzeln
    string[] GpuChoiceTexts()
    {
        List<string> t = new List<string>(); gpuSelValues.Clear();
        t.Add("alle Grafikeinheiten"); gpuSelValues.Add("Alle");
        List<string> names = new List<string>();
        foreach (string g in GpuNames ?? new string[0]) { string n = (g ?? "").Trim(); if (n.Length > 0 && GpuKind(n) != "virtuell" && !names.Contains(n)) names.Add(n); }
        bool dg = names.Exists(delegate(string n) { return GpuKind(n) == "dGPU"; }), ig = names.Exists(delegate(string n) { return GpuKind(n) == "iGPU"; });
        if (dg && ig) { t.Add("nur Grafikkarte"); gpuSelValues.Add("Grafikkarte"); t.Add("nur Prozessorgrafik"); gpuSelValues.Add("Prozessorgrafik"); }
        if (names.Count > 1) foreach (string n in names) { t.Add("nur " + n); gpuSelValues.Add("Name:" + n); }
        return t.ToArray();
    }

    string GpuChoiceValue(ComboBox c)
    {
        if (c == null || c.SelectedIndex < 0 || c.SelectedIndex >= gpuSelValues.Count) return "Alle";
        return gpuSelValues[c.SelectedIndex];
    }

    void SetGpuChoice(string v)
    {
        int i = gpuSelValues.IndexOf(v ?? "");
        if (i < 0 && (v ?? "").StartsWith("Name:")) i = gpuSelValues.FindIndex(delegate(string x) { return x.StartsWith("Name:") && x.Substring(5).IndexOf(v.Substring(5), StringComparison.OrdinalIgnoreCase) >= 0; });
        if (i < 0) i = 0;
        if (cmbGpuSel != null && i < cmbGpuSel.Items.Count) cmbGpuSel.SelectedIndex = i;
        if (cmbLGpuSel != null && i < cmbLGpuSel.Items.Count) cmbLGpuSel.SelectedIndex = i;
    }

    // Referenz (ab v2.65 nur noch die mit "Dieses System als Referenz festlegen" gespeicherte, keine eingebauten Werte)
    string SavedRefText()
    {
        try
        {
            string f = dataDir.Length > 0 ? Path.Combine(dataDir, "Referenz.json") : "";
            if (f.Length > 0 && !File.Exists(f)) f = Path.Combine(dataDir, "PC-Diagnose-Referenz.json");
            if (f.Length > 0 && File.Exists(f))
            {
                System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
                Dictionary<string, object> d = js.DeserializeObject(File.ReadAllText(f, Encoding.UTF8)) as Dictionary<string, object>;
                object n, dt; string name = d != null && d.TryGetValue("Name", out n) ? Convert.ToString(n) : "";
                string dat = d != null && d.TryGetValue("Datum", out dt) ? Convert.ToString(dt) : "";
                DateTime x; if (DateTime.TryParseExact(dat, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out x)) dat = x.ToString("dd.MM.yyyy");
                if (name.Length > 0) return "Gespeicherte Referenz: " + name + (dat.Length > 0 ? " vom " + dat : "");
            }
        }
        catch { }
        return "";
    }

    // ------------------------------------------------------------ Voreinstellungen (ab v2.65)
    // Auswahl der Module, Prüfungen, Messungen, Lasttest und Reparaturen als benannte Voreinstellung im Datenordner
    // (Voreinstellungen.json, Format Minibench-Voreinstellungen/1). Eine davon kann beim Start automatisch geladen werden:
    // Wer den Stick weitergibt, legt sie fest, die andere Person klickt nur noch Start.
    ComboBox cmbPreset;
    Button btnPresetSave, btnPresetDel;
    bool presetFilling, presetLoading;
    string presetActive = "";
    string PresetFile { get { return dataDir.Length > 0 ? Path.Combine(dataDir, "Voreinstellungen.json") : ""; } }
    const string PresetFormat = "Minibench-Voreinstellungen/1";
    static readonly string[] diagProfiles = new string[] { "Voll", "Schnell", "Benutzerdefiniert" };

    Dictionary<string, object> ReadPresetFile()
    {
        try
        {
            if (PresetFile.Length == 0 || !File.Exists(PresetFile)) return null;
            System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
            Dictionary<string, object> d = js.DeserializeObject(File.ReadAllText(PresetFile, Encoding.UTF8)) as Dictionary<string, object>;
            object fm; if (d == null || !d.TryGetValue("Format", out fm) || Convert.ToString(fm) != PresetFormat) return null;
            return d;
        }
        catch { return null; }
    }

    static Dictionary<string, object> SubDict(Dictionary<string, object> d, string key)
    {
        object o; if (d == null || !d.TryGetValue(key, out o)) return null;
        return o as Dictionary<string, object>;
    }

    void FillPresets(bool autoLoad)
    {
        cachedLeoIds = null;
        if (cmbPreset == null) return;
        presetFilling = true;
        try
        {
            cmbPreset.Items.Clear(); cmbPreset.Items.Add("(keine)");
            Dictionary<string, object> d = ReadPresetFile();
            Dictionary<string, object> e = SubDict(d, "Eintraege");
            object st; string start = d != null && d.TryGetValue("BeimStart", out st) ? Convert.ToString(st) : "";
            List<string> names = new List<string>();
            if (e != null) names.AddRange(e.Keys);
            names.Sort(StringComparer.CurrentCultureIgnoreCase);
            foreach (string n in names) cmbPreset.Items.Add(n == start ? n + "   (beim Start)" : n);
            int sel = 0;
            if (presetActive.Length > 0) { int i = names.IndexOf(presetActive); if (i >= 0) sel = i + 1; }
            if (autoLoad && start.Length > 0) { int i = names.IndexOf(start); if (i >= 0) { sel = i + 1; ApplyPreset(start); } }
            cmbPreset.SelectedIndex = sel;
            btnPresetDel.Enabled = sel > 0;
            btnPresetSave.Enabled = PresetFile.Length > 0;
        }
        finally { presetFilling = false; }
    }

    string PresetNameOf(int index)
    {
        if (index <= 0 || index >= cmbPreset.Items.Count) return "";
        string t = Convert.ToString(cmbPreset.Items[index]);
        int k = t.IndexOf("   (beim Start)"); return k >= 0 ? t.Substring(0, k) : t;
    }

    void PresetPicked()
    {
        btnPresetDel.Enabled = cmbPreset.SelectedIndex > 0;
        string n = PresetNameOf(cmbPreset.SelectedIndex);
        if (n.Length == 0) { presetActive = ""; UpdateSummary(); return; }
        ApplyPreset(n);
    }

    void ApplyPreset(string name)
    {
        Dictionary<string, object> e = SubDict(SubDict(ReadPresetFile(), "Eintraege"), name);
        Dictionary<string, object> w = SubDict(e, "Werte");
        if (w == null) return;
        presetLoading = true;
        try { ApplySettings(w); presetActive = name; }
        catch { }
        finally { presetLoading = false; }
        UpdateSummary();
    }

    void SavePresetDialog()
    {
        if (PresetFile.Length == 0) { MessageBox.Show(this, "Kein Datenordner verfügbar.", "Leos Minibench"); return; }
        Dictionary<string, object> d = ReadPresetFile();
        object st; string start = d != null && d.TryGetValue("BeimStart", out st) ? Convert.ToString(st) : "";
        using (Form f = new Form())
        {
            f.Text = "Voreinstellung speichern"; f.FormBorderStyle = FormBorderStyle.FixedDialog; f.MaximizeBox = false; f.MinimizeBox = false; f.ShowInTaskbar = false;
            f.StartPosition = FormStartPosition.CenterParent; f.Font = new Font("Segoe UI", 9.5f); f.BackColor = UI.Bg; f.AutoSize = true; f.AutoSizeMode = AutoSizeMode.GrowAndShrink; f.Padding = new Padding(UI.S(16));
            FlowLayoutPanel p = new FlowLayoutPanel(); p.FlowDirection = FlowDirection.TopDown; p.AutoSize = true; p.WrapContents = false; p.Dock = DockStyle.Fill;
            Label l = new Label(); l.AutoSize = true; l.MaximumSize = new Size(UI.S(460), 0); l.Margin = new Padding(0, 0, 0, UI.S(8));
            l.Text = "Speichert die Auswahl aller Seiten (Module, Prüfungen, Messungen, Lasttest, Reparaturen, Sensortreiber) im Datenordner. Laufwerke und Vergleichssysteme bleiben je PC frei.";
            p.Controls.Add(l);
            TextBox tb = new TextBox(); tb.Width = UI.S(320); tb.Text = presetActive.Length > 0 ? presetActive : "Standardprüfung"; p.Controls.Add(tb);
            CheckBox cs = new CheckBox(); cs.AutoSize = true; cs.Margin = new Padding(UI.S(3), UI.S(10), UI.S(3), UI.S(3)); cs.Text = "Beim Start automatisch laden (dann genügt ein Klick auf Start)"; cs.Checked = start.Length == 0 || start == tb.Text; p.Controls.Add(cs);
            FlowLayoutPanel b = new FlowLayoutPanel(); b.AutoSize = true; b.Margin = new Padding(0, UI.S(12), 0, 0);
            Button ok = UI.Primary("Speichern"); ok.DialogResult = DialogResult.OK; Button ab = UI.Secondary("Abbrechen"); ab.DialogResult = DialogResult.Cancel;
            b.Controls.Add(ok); b.Controls.Add(ab); p.Controls.Add(b);
            f.Controls.Add(p); f.AcceptButton = ok; f.CancelButton = ab;
            UI.ThemeDialog(f);
            if (f.ShowDialog(this) != DialogResult.OK) return;
            string name = tb.Text.Trim().Replace("   (beim Start)", "");
            if (name.Length == 0) return;
            try
            {
                if (d == null) d = new Dictionary<string, object>();
                d["Format"] = PresetFormat;
                Dictionary<string, object> e = SubDict(d, "Eintraege");
                if (e == null) { e = new Dictionary<string, object>(); d["Eintraege"] = e; }
                Dictionary<string, object> entry = new Dictionary<string, object>();
                entry["Gespeichert"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
                entry["Version"] = version; entry["Computer"] = Environment.MachineName;
                entry["Werte"] = CaptureSettings();
                e[name] = entry;
                if (cs.Checked) d["BeimStart"] = name; else if (start == name) d["BeimStart"] = "";
                Directory.CreateDirectory(dataDir);
                System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
                File.WriteAllText(PresetFile, js.Serialize(d), new UTF8Encoding(false));
                presetActive = name;
                FillPresets(false);
                UpdateSummary();
            }
            catch (Exception ex) { MessageBox.Show(this, "Voreinstellung nicht gespeichert: " + ex.Message, "Leos Minibench"); }
        }
    }

    void DeletePreset()
    {
        string n = PresetNameOf(cmbPreset.SelectedIndex);
        if (n.Length == 0) return;
        if (MessageBox.Show(this, "Voreinstellung \"" + n + "\" löschen?", "Leos Minibench", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        try
        {
            Dictionary<string, object> d = ReadPresetFile(); if (d == null) return;
            Dictionary<string, object> e = SubDict(d, "Eintraege"); if (e != null) e.Remove(n);
            object st; if (d.TryGetValue("BeimStart", out st) && Convert.ToString(st) == n) d["BeimStart"] = "";
            System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
            File.WriteAllText(PresetFile, js.Serialize(d), new UTF8Encoding(false));
            if (presetActive == n) presetActive = "";
            FillPresets(false); UpdateSummary();
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Leos Minibench"); }
    }

    static void PutC(Dictionary<string, object> d, string k, CheckBox c) { if (c != null) d[k] = c.Checked; }
    static void PutCb(Dictionary<string, object> d, string k, ComboBox c) { if (c != null && c.SelectedItem != null) d[k] = Convert.ToString(c.SelectedItem); }
    static bool GetB(Dictionary<string, object> d, string k, out bool v)
    {
        v = false; object o; if (d == null || !d.TryGetValue(k, out o) || o == null) return false;
        if (o is bool) { v = (bool)o; return true; }
        bool b; if (bool.TryParse(Convert.ToString(o), out b)) { v = b; return true; }
        return false;
    }
    // gleiche Wahl trotz geänderter Beschriftung: gleiche Zahl am Anfang oder alter Text beginnt mit dem neuen
    public static bool SameChoice(string item, string old)
    {
        if (String.IsNullOrEmpty(item) || String.IsNullOrEmpty(old)) return false;
        if (old.StartsWith(item, StringComparison.OrdinalIgnoreCase)) return true;
        string a = item.Split(' ')[0], b = old.Split(' ')[0]; int x, y;
        return int.TryParse(a, out x) && int.TryParse(b, out y) && x == y && item.Length > a.Length && old.Length > b.Length && Char.ToLowerInvariant(item[a.Length + 1]) == Char.ToLowerInvariant(old[b.Length + 1]);
    }

    static string GetS(Dictionary<string, object> d, string k) { object o; return d != null && d.TryGetValue(k, out o) && o != null ? Convert.ToString(o) : null; }
    static void GetC(Dictionary<string, object> d, string k, CheckBox c) { bool v; if (c != null && GetB(d, k, out v)) c.Checked = v; }
    static void GetCb(Dictionary<string, object> d, string k, ComboBox c)
    {
        string v = GetS(d, k); if (c == null || v == null) return;
        int i = c.Items.IndexOf(v);
        if (i < 0) for (int j = 0; j < c.Items.Count; j++) if (Convert.ToString(c.Items[j]).StartsWith(v, StringComparison.OrdinalIgnoreCase)) { i = j; break; }
        // Voreinstellungen vor v3.64: längere Texte ("2 Minuten", "automatisch (TjMax, sonst 100 °C)")
        if (i < 0) for (int j = 0; j < c.Items.Count; j++) if (SameChoice(Convert.ToString(c.Items[j]), v)) { i = j; break; }
        if (i >= 0) c.SelectedIndex = i;
    }

    // Alle Einstellungen der Seiten als Schlüssel und Wert (Texte der Auswahllisten, damit Änderungen der Reihenfolge nicht stören)
    public Dictionary<string, object> CaptureSettings()
    {
        Dictionary<string, object> d = new Dictionary<string, object>();
        string[] mods = new string[] { "Diagnose", "Benchmark", "Lasttest", "Reparatur", "Optimierung" };
        for (int i = 0; i < mods.Length && i < nav.Count; i++) d["Modul." + mods[i]] = nav[i].Checked;
        RadioButton[] rbs = new RadioButton[] { rbVoll, rbSchnell, rbCustom };
        for (int i = 0; i < rbs.Length; i++) if (rbs[i] != null && rbs[i].Checked) d["Diag.Profil"] = diagProfiles[i];
        for (int i = 0; i < diagKeys.Length && diagChk != null; i++) d["Diag." + diagKeys[i]] = diagChk[i].Checked;
        PutC(d, "Diag.SchnellerModus", chkFast); PutC(d, "Diag.Smartmontools", chkInstall); PutC(d, "Diag.Speicherdiagnose", chkMem);
        PutCb(d, "Diag.Tage", cmbDays); PutCb(d, "Diag.SmartMax", cmbSmartMax);
        for (int i = 0; i < benchKeys.Length && benchChk != null; i++) d["Bench." + benchKeys[i]] = benchChk[i].Checked;
        PutC(d, "Bench.GpuWahl", chkGpuWahl);
        PutCb(d, "Gpu.Aufloesung", cmbGpuRes); PutCb(d, "Gpu.Anzeige", cmbGpuShow); d["Gpu.Auswahl"] = GpuChoiceValue(cmbGpuSel);
        PutC(d, "Last.CPU", chkLCpu); PutCb(d, "Last.CPUDauer", cmbLCpu);
        PutC(d, "Last.RAM", chkLRam); PutCb(d, "Last.RAMDauer", cmbLRam); PutCb(d, "Last.RAMAnteil", cmbLRamPct);
        PutC(d, "Last.GPU", chkLGpu); PutCb(d, "Last.GPUDauer", cmbLGpu);
        PutC(d, "Last.Disk", chkLDisk); PutCb(d, "Last.DiskDauer", cmbLDisk);
        if (cmbLDiskDrive != null && cmbLDiskDrive.SelectedItem != null) d["Last.Laufwerk"] = Convert.ToString(cmbLDiskDrive.SelectedItem).Substring(0, Math.Min(2, Convert.ToString(cmbLDiskDrive.SelectedItem).Length));
        PutCb(d, "Last.AbbruchCpu", cmbLAbortCpu); PutCb(d, "Last.AbbruchGpu", cmbLAbortGpu);
        for (int i = 0; i < repKeys.Length && repChk != null; i++) d["Rep." + repKeys[i]] = repChk[i].Checked;
        PutC(d, "Rep.Wiederherstellungspunkt", chkRestorePoint);
        d["Opt.Auswahl"] = String.Join(",", SelectedOptIds().ToArray());
        PutC(d, "Opt.Wiederherstellungspunkt", chkOptRestore);
        PutC(d, "Allg.Anonymisieren", chkAnon);
        if (cmbDriver != null) d["Sensor.Treiber"] = driverValues[Math.Max(0, cmbDriver.SelectedIndex)];
        if (cmbKeep != null) d["Sensor.Werkzeuge"] = keepValues[Math.Max(0, cmbKeep.SelectedIndex)];
        return d;
    }

    public void ApplySettings(Dictionary<string, object> d)
    {
        string[] mods = new string[] { "Diagnose", "Benchmark", "Lasttest", "Reparatur", "Optimierung" };
        bool v;
        for (int i = 0; i < mods.Length && i < nav.Count; i++) if (GetB(d, "Modul." + mods[i], out v)) nav[i].Checked = v;
        string prof = GetS(d, "Diag.Profil");
        RadioButton[] rbs = new RadioButton[] { rbVoll, rbSchnell, rbCustom };
        // Voreinstellungen vor v3.64 mit Funktionstest oder Absturzanalyse: Profil Schnell, ohne die dort abgeschalteten
        // Prüfungen und Optionen zu übernehmen (sonst liefe etwa die Installation von smartmontools unerwartet mit)
        bool alt = false;
        if (prof != null) { int i = Array.IndexOf(diagProfiles, prof); if (i < 0) { i = 1; alt = true; } if (rbs[i] != null) rbs[i].Checked = true; }
        if (!alt)
        {
            for (int i = 0; i < diagKeys.Length && diagChk != null; i++) GetC(d, "Diag." + diagKeys[i], diagChk[i]);
            GetC(d, "Diag.Smartmontools", chkInstall); GetC(d, "Diag.Speicherdiagnose", chkMem);
        }
        GetC(d, "Diag.SchnellerModus", chkFast);
        GetCb(d, "Diag.Tage", cmbDays); GetCb(d, "Diag.SmartMax", cmbSmartMax);
        for (int i = 0; i < benchKeys.Length && benchChk != null; i++) GetC(d, "Bench." + benchKeys[i], benchChk[i]);
        GetC(d, "Bench.GpuWahl", chkGpuWahl);
        GetCb(d, "Gpu.Aufloesung", cmbGpuRes); GetCb(d, "Gpu.Anzeige", cmbGpuShow);
        string gs = GetS(d, "Gpu.Auswahl"); if (gs != null) SetGpuChoice(gs);
        GetC(d, "Last.CPU", chkLCpu); GetCb(d, "Last.CPUDauer", cmbLCpu);
        GetC(d, "Last.RAM", chkLRam); GetCb(d, "Last.RAMDauer", cmbLRam); GetCb(d, "Last.RAMAnteil", cmbLRamPct);
        GetC(d, "Last.GPU", chkLGpu); GetCb(d, "Last.GPUDauer", cmbLGpu);
        GetC(d, "Last.Disk", chkLDisk); GetCb(d, "Last.DiskDauer", cmbLDisk); GetCb(d, "Last.Laufwerk", cmbLDiskDrive);
        GetCb(d, "Last.AbbruchCpu", cmbLAbortCpu); GetCb(d, "Last.AbbruchGpu", cmbLAbortGpu);
        for (int i = 0; i < repKeys.Length && repChk != null; i++) GetC(d, "Rep." + repKeys[i], repChk[i]);
        UpdateRepairCounts(); UpdateRepairGroupVisibility();
        GetC(d, "Rep.Wiederherstellungspunkt", chkRestorePoint);
        string os = GetS(d, "Opt.Auswahl");
        if (os != null) { List<string> ids = new List<string>(os.Split(new char[] { ',' }, StringSplitOptions.RemoveEmptyEntries)); foreach (OptItem it in optItems) it.Box.Checked = ids.Contains(it.Id); UpdateOptCounts(); }
        GetC(d, "Opt.Wiederherstellungspunkt", chkOptRestore);
        GetC(d, "Allg.Anonymisieren", chkAnon);
        // Sensortreiber und Hilfswerkzeuge gelten für diesen Lauf, gespeichert je Gerät wird hier nichts
        string tr = GetS(d, "Sensor.Treiber"); if (tr != null && cmbDriver != null) { int i = Array.IndexOf(driverValues, tr); if (i >= 0) cmbDriver.SelectedIndex = i; }
        string kp = GetS(d, "Sensor.Werkzeuge"); if (kp != null && cmbKeep != null) { int i = Array.IndexOf(keepValues, kp); if (i >= 0) cmbKeep.SelectedIndex = i; }
        UpdateLoadEnabled();
    }

    // ------------------------------------------------------------ Ablauf
    Panel BuildRun()
    {
        Panel p = new Panel(); p.BackColor = UI.Bg;
        TableLayoutPanel t = new TableLayoutPanel(); t.Dock = DockStyle.Fill; t.ColumnCount = 1; t.BackColor = UI.Bg;
        t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        t.RowStyles.Add(new RowStyle(SizeType.Absolute, UI.S(22)));
        t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        t.RowStyles.Add(new RowStyle(SizeType.Absolute, UI.S(16)));
        t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        t.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        t.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        TableLayoutPanel stepRow = new TableLayoutPanel(); stepRow.Dock = DockStyle.Fill; stepRow.AutoSize = true; stepRow.ColumnCount = 2; stepRow.BackColor = UI.Bg;
        stepRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); stepRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        // ab v3.65 an die Einstellungsseiten angeglichen: Titelgröße, Karte um die Listen, Fußleiste wie beim Start
        lblStep = Lbl("Wird gestartet ...", UI.SchriftTitel, true, UI.Text); lblStep.AutoEllipsis = true;
        lblCounter = Lbl("", 10f, false, UI.Muted); lblCounter.Anchor = AnchorStyles.Right; lblCounter.Margin = new Padding(UI.S(3), UI.S(6), 0, UI.S(3));
        stepRow.Controls.Add(lblStep, 0, 0); stepRow.Controls.Add(lblCounter, 1, 0);
        t.Controls.Add(stepRow, 0, 0);
        barAll = new FlatBar(); barAll.Dock = DockStyle.Fill; barAll.Margin = new Padding(UI.S(3), UI.S(4), UI.S(3), UI.S(6)); t.Controls.Add(barAll, 0, 1);
        lblSub = Lbl(" ", 9.5f, false, UI.Muted); lblSub.AutoEllipsis = true; lblSub.Margin = new Padding(UI.S(3), UI.S(4), UI.S(3), UI.S(2)); t.Controls.Add(lblSub, 0, 2);
        barSub = new FlatBar(); barSub.Dock = DockStyle.Fill; barSub.Fill = UI.AccentActive; barSub.Margin = new Padding(UI.S(3), UI.S(3), UI.S(3), UI.S(5)); t.Controls.Add(barSub, 0, 3);
        lblPar = Lbl(" ", 9f, false, UI.Muted); lblPar.AutoEllipsis = true; lblPar.Margin = new Padding(UI.S(3), 0, UI.S(3), 0); lblPar.Visible = false; t.Controls.Add(lblPar, 0, 4);

        FlowLayoutPanel cards = new FlowLayoutPanel(); cards.AutoSize = true; cards.BackColor = UI.Bg; cards.Margin = new Padding(0, UI.S(14), 0, UI.S(10));
        cardK = new StatCard("kritisch", UI.Crit); cardW = new StatCard("Warnungen", UI.Warn); cardI = new StatCard("Hinweise", UI.Info); cardT = new StatCard("Tests bestanden", UI.Ok);
        cards.Controls.Add(cardK); cards.Controls.Add(cardW); cards.Controls.Add(cardI); cards.Controls.Add(cardT);
        t.Controls.Add(cards, 0, 5);

        tabs = new TabStrip(); tabs.Dock = DockStyle.Fill; tabs.Items.Add("Befunde"); tabs.Items.Add("Tests"); tabs.Items.Add("Leistung"); tabs.Items.Add("Sensoren"); tabs.Items.Add("Protokoll");
        t.Controls.Add(tabs, 0, 6);

        CardPanel host = new CardPanel(); host.Dock = DockStyle.Fill; host.Padding = new Padding(UI.S(6)); host.Margin = new Padding(0, UI.S(6), 0, UI.S(12));
        lvFind = MakeList(new string[] { "Stufe", "Bereich", "Befund" }, new int[] { UI.S(110), UI.S(140), UI.S(700) });
        lvTests = MakeList(new string[] { "Ergebnis", "Test", "Details" }, new int[] { UI.S(110), UI.S(320), UI.S(520) });
        lvBench = MakeList(new string[] { "Ergebnis", "Messung", "Wert", "Index", "Referenz", "Vergleich" }, new int[] { UI.S(110), UI.S(330), UI.S(160), UI.S(190), UI.S(95), UI.S(220) });
        lvBench.Tag = "bench";
        txtLog = new TextBox(); txtLog.Multiline = true; txtLog.ReadOnly = true; txtLog.ScrollBars = ScrollBars.Vertical; txtLog.WordWrap = true;
        txtLog.Dock = DockStyle.Fill; txtLog.Font = new Font("Consolas", 9.75f); txtLog.BorderStyle = BorderStyle.None;
        ThemeLog();
        Panel sensHost = new Panel(); sensHost.Dock = DockStyle.Fill; sensHost.BackColor = UI.Panel; sensHost.Padding = new Padding(10, 6, 10, 6);
        chartRun = new SensorChart(); chartRun.Dock = DockStyle.Fill; chartRun.WindowSec = 0;
        chartRun.Empty = "Kurven erscheinen hier während des Benchmarks und des Lasttests (Temperatur, Takt, Leistung von CPU und GPU).";
        lblRunSens = Lbl(" ", 9f, false, UI.Muted); lblRunSens.Dock = DockStyle.Top; lblRunSens.AutoSize = false; lblRunSens.Height = 22;
        sensHost.Controls.Add(chartRun); sensHost.Controls.Add(lblRunSens);
        host.Controls.Add(lvFind); host.Controls.Add(lvTests); host.Controls.Add(lvBench); host.Controls.Add(sensHost); host.Controls.Add(txtLog);
        lvTests.Visible = false; lvBench.Visible = false; sensHost.Visible = false; txtLog.Visible = false;
        tabs.SelectedChanged += delegate {
            lvFind.Visible = tabs.Selected == 0; lvTests.Visible = tabs.Selected == 1; lvBench.Visible = tabs.Selected == 2; sensHost.Visible = tabs.Selected == 3; txtLog.Visible = tabs.Selected == 4;
        };
        t.Controls.Add(host, 0, 7);

        TableLayoutPanel foot = new TableLayoutPanel(); foot.Dock = DockStyle.Fill; foot.AutoSize = true; foot.ColumnCount = 2; foot.BackColor = UI.Bg;
        foot.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); foot.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        lblResult = Lbl("", 10.5f, true, UI.Text); lblResult.Anchor = AnchorStyles.Left; lblResult.AutoEllipsis = true;
        FlowLayoutPanel btns = new FlowLayoutPanel(); btns.AutoSize = true; btns.WrapContents = false; btns.BackColor = UI.Bg; btns.Anchor = AnchorStyles.Right;
        btnStopWait = UI.Secondary("Test beenden"); btnSkipStep = UI.SkipStepButton(); btnCancel = UI.Secondary("Abbrechen");
        btnFolder = UI.Secondary("Ordner öffnen"); btnNew = UI.Secondary("Neuer Lauf"); btnKi = UI.Secondary("KI-Datei zeigen");
        btnExportRun = UI.Secondary("Lauf exportieren …"); btnHtml = UI.Primary("Bericht öffnen");
        btnHtml.Margin = new Padding(UI.S(UI.Abstand5), 0, 0, 0); btnHtml.MinimumSize = new Size(UI.S(150), UI.S(44));
        foreach (Button sb in new Button[] { btnStopWait, btnSkipStep, btnCancel, btnFolder, btnNew, btnKi, btnExportRun }) { sb.Margin = new Padding(UI.S(8), UI.S(6), 0, 0); sb.MinimumSize = new Size(0, UI.S(32)); }
        btns.Controls.Add(btnStopWait); btns.Controls.Add(btnSkipStep); btns.Controls.Add(btnCancel); btns.Controls.Add(btnNew); btns.Controls.Add(btnFolder); btns.Controls.Add(btnExportRun); btns.Controls.Add(btnKi); btns.Controls.Add(btnHtml);
        foot.Controls.Add(lblResult, 0, 0); foot.Controls.Add(btns, 1, 0);
        t.Controls.Add(foot, 0, 8);

        btnStopWait.Click += delegate {
            try { Directory.CreateDirectory(cpDir); File.WriteAllText(Path.Combine(cpDir, "stop.flag"), "1"); btnStopWait.Enabled = false; }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, "Leos Minibench"); }
        };
        btnSkipStep.Click += delegate {
            try { Directory.CreateDirectory(cpDir); File.WriteAllText(Path.Combine(cpDir, "skip.flag"), "1"); btnSkipStep.Enabled = false; }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, "Leos Minibench"); }
        };
        btnCancel.Click += delegate { AskCancel(); };
        btnHtml.Click += delegate { OpenShell(htmlPath); };
        btnFolder.Click += delegate { OpenShell(outDir); };
        btnKi.Click += delegate { OpenSelect(kiPath); };
        btnExportRun.Click += delegate { ExportCurrentRun(); };
        btnNew.Click += delegate { ReloadDb(); runView.Visible = false; setupView.Visible = true; };
        p.Controls.Add(t);
        ApplyRunTips();
        return p;
    }

    // Stufe als Etikett: "KRITISCH" wird "Kritisch", kurze Kürzel wie "OK" bleiben
    public static string BadgeCase(string t)
    {
        t = (t ?? "").Trim();
        if (t.Length <= 2) return t.ToUpperInvariant();
        return t.Substring(0, 1).ToUpperInvariant() + t.Substring(1).ToLowerInvariant();
    }

    // Protokollfeld: im Dunkelschema konsolenartig dunkel, im Hellschema hell (vorher in beiden Schemata dunkelblau)
    void ThemeLog()
    {
        if (txtLog == null) return;
        txtLog.BackColor = UI.IsDark ? Color.FromArgb(18, 24, 34) : Color.FromArgb(246, 247, 249);
        txtLog.ForeColor = UI.IsDark ? Color.FromArgb(214, 222, 235) : Color.FromArgb(28, 29, 31);
    }

    ListView MakeList(string[] cols, int[] widths)
    {
        ListView lv = new ListView(); lv.View = View.Details; lv.FullRowSelect = true; lv.Dock = DockStyle.Fill; lv.HideSelection = false;
        lv.HeaderStyle = ColumnHeaderStyle.Nonclickable; lv.ShowItemToolTips = true; lv.BorderStyle = BorderStyle.None; lv.OwnerDraw = true;
        lv.Font = new Font("Segoe UI", 9.75f); lv.BackColor = UI.Panel; lv.ForeColor = UI.Text;
        ImageList rowHeight = new ImageList(); rowHeight.ImageSize = new Size(1, UI.S(34)); lv.SmallImageList = rowHeight;
        for (int i = 0; i < cols.Length; i++) lv.Columns.Add(cols[i], widths[i]);
        lv.DrawColumnHeader += delegate(object s, DrawListViewColumnHeaderEventArgs e) {
            Color headerBg = UI.IsDark ? Color.FromArgb(28, 30, 32) : Color.FromArgb(248, 249, 251);
            using (SolidBrush b = new SolidBrush(headerBg)) e.Graphics.FillRectangle(b, e.Bounds);
            using (Pen pen = new Pen(UI.Line)) e.Graphics.DrawLine(pen, e.Bounds.Left, e.Bounds.Bottom - 1, e.Bounds.Right, e.Bounds.Bottom - 1);
            using (Font f = new Font("Segoe UI Semibold", 8.5f))
                TextRenderer.DrawText(e.Graphics, e.Header.Text.ToUpperInvariant(), f, new Rectangle(e.Bounds.X + UI.S(10), e.Bounds.Y, e.Bounds.Width - UI.S(12), e.Bounds.Height), UI.Muted, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        };
        lv.DrawItem += delegate(object s, DrawListViewItemEventArgs e) { };
        lv.DrawSubItem += delegate(object s, DrawListViewSubItemEventArgs e) {
            Graphics g = e.Graphics;
            bool hdr = "hdr".Equals(e.Item.Tag);
            if (hdr && (e.ColumnIndex == 2 || e.ColumnIndex == 3)) return;
            Rectangle rb = e.Bounds;
            if (hdr && e.ColumnIndex == 1) { for (int ci = 2; ci <= 3 && ci < lv.Columns.Count; ci++) rb.Width += lv.Columns[ci].Width; }
            Color back = e.Item.Selected ? UI.AccentSoft : (hdr ? (UI.IsDark ? Color.FromArgb(32, 34, 38) : Color.FromArgb(243, 245, 249)) : UI.Panel);
            using (SolidBrush b = new SolidBrush(back)) g.FillRectangle(b, rb);
            Color borderLine = UI.IsDark ? Color.FromArgb(45, 48, 52) : Color.FromArgb(236, 239, 243);
            using (Pen pen = new Pen(borderLine)) g.DrawLine(pen, rb.Left, rb.Bottom - 1, rb.Right, rb.Bottom - 1);
            string txt = e.SubItem.Text;
            if (hdr && e.ColumnIndex == 1)
            {
                int w = rb.Width;
                using (Font fb = new Font("Segoe UI Semibold", 10f))
                {
                    Size sz = TextRenderer.MeasureText(g, txt, fb);
                    TextRenderer.DrawText(g, txt, fb, new Rectangle(e.Bounds.X + UI.S(10), e.Bounds.Y, sz.Width + UI.S(4), e.Bounds.Height), UI.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                    string sub = e.Item.SubItems.Count > 2 ? e.Item.SubItems[2].Text : "";
                    if (sub.Length > 0)
                        TextRenderer.DrawText(g, sub, lv.Font, new Rectangle(e.Bounds.X + UI.S(18) + sz.Width, e.Bounds.Y, w - sz.Width - UI.S(26), e.Bounds.Height), UI.Muted,
                            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
                }
            }
            else if (hdr && e.ColumnIndex == 4 && txt.Length > 0)
            {
                using (Font fb = new Font("Segoe UI Semibold", 9.75f))
                    TextRenderer.DrawText(g, txt, fb, new Rectangle(e.Bounds.X + UI.S(10), e.Bounds.Y, e.Bounds.Width - UI.S(14), e.Bounds.Height), UI.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            }
            else if (e.ColumnIndex == 0 && txt.Length == 0) { }
            else if (e.ColumnIndex == 0)
            {
                // ab v3.65 wie die Etiketten der Einstellungsseiten: gleiche Schrift, Höhe und Schreibweise
                Color fg, bg; UI.Level(txt, out fg, out bg);
                string label = BadgeCase(txt);
                using (Font f = new Font("Segoe UI Semibold", 8.25f))
                {
                    Size sz = TextRenderer.MeasureText(g, label, f, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                    int pillH = Math.Max(UI.S(18), sz.Height + UI.S(4));
                    int pillW = sz.Width + UI.S(14);
                    RectangleF pill = new RectangleF(e.Bounds.X + UI.S(8), e.Bounds.Y + (e.Bounds.Height - pillH) / 2f, pillW, pillH);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    using (GraphicsPath gp = UI.Round(pill, (pillH - 1) / 2f)) using (SolidBrush pb = new SolidBrush(bg)) g.FillPath(pb, gp);
                    g.SmoothingMode = SmoothingMode.None;
                    TextRenderer.DrawText(g, label, f, Rectangle.Round(pill), fg, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                }
            }
            else if ("bench".Equals(lv.Tag) && e.ColumnIndex == 3)
            {
                int iv; double wv;
                int textW = UI.S(48);
                int barMargin = UI.S(10);
                int barGap = UI.S(6);
                int totalReserve = barMargin + barGap + textW;
                if (txt.StartsWith("W") && double.TryParse(txt.Substring(1), NumberStyles.Float, CultureInfo.InvariantCulture, out wv))
                {
                    // WinSAT: Skala 1,0 bis 9,9, Farbe nach Bewertung
                    Color fc = wv >= 7 ? UI.Ok : wv >= 5 ? UI.Info : wv >= 3.5 ? UI.Warn : UI.Crit;
                    int bw = Math.Max(UI.S(40), e.Bounds.Width - totalReserve);
                    int barH = UI.S(8);
                    RectangleF tr = new RectangleF(e.Bounds.X + barMargin, e.Bounds.Y + (e.Bounds.Height - barH) / 2f, bw, barH);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    using (GraphicsPath gp = UI.Round(tr, UI.SF(4))) using (SolidBrush b0 = new SolidBrush(UI.SkipBg)) g.FillPath(b0, gp);
                    float fw = Math.Max(UI.SF(6f), (float)(bw * (Math.Min(9.9, Math.Max(1.0, wv)) - 1.0) / 8.9));
                    using (GraphicsPath gf = UI.Round(new RectangleF(tr.X, tr.Y, fw, tr.Height), UI.SF(4))) using (SolidBrush b1 = new SolidBrush(fc)) g.FillPath(b1, gf);
                    g.SmoothingMode = SmoothingMode.None;
                    TextRenderer.DrawText(g, wv.ToString("0.0", CultureInfo.GetCultureInfo("de-DE")), (wsBold ?? (wsBold = new Font(lv.Font, FontStyle.Bold))), new Rectangle((int)tr.Right + barGap, e.Bounds.Y, textW, e.Bounds.Height), UI.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
                }
                else if (int.TryParse(txt, out iv))
                {
                    Color fg, bg; UI.Level(e.Item.SubItems[0].Text, out fg, out bg);
                    int bw = Math.Max(UI.S(40), e.Bounds.Width - totalReserve);
                    int barH = UI.S(8);
                    RectangleF tr = new RectangleF(e.Bounds.X + barMargin, e.Bounds.Y + (e.Bounds.Height - barH) / 2f, bw, barH);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    using (GraphicsPath gp = UI.Round(tr, UI.SF(4))) using (SolidBrush b0 = new SolidBrush(UI.SkipBg)) g.FillPath(b0, gp);
                    float fw = Math.Max(UI.SF(4f), bw * Math.Min(150, Math.Max(0, iv)) / 150f);
                    using (GraphicsPath gf = UI.Round(new RectangleF(tr.X, tr.Y, fw, tr.Height), UI.SF(4))) using (SolidBrush b1 = new SolidBrush(fg)) g.FillPath(b1, gf);
                    using (Pen pm = new Pen(UI.Muted, UI.SF(2f))) g.DrawLine(pm, tr.X + bw * 100f / 150f, tr.Y - UI.SF(3), tr.X + bw * 100f / 150f, tr.Bottom + UI.SF(3));
                    g.SmoothingMode = SmoothingMode.None;
                    TextRenderer.DrawText(g, txt, lv.Font, new Rectangle((int)tr.Right + barGap, e.Bounds.Y, textW, e.Bounds.Height), UI.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
                }
                else if (txt.Length > 0)
                    TextRenderer.DrawText(g, txt, lv.Font, new Rectangle(e.Bounds.X + UI.S(10), e.Bounds.Y, e.Bounds.Width - UI.S(14), e.Bounds.Height), UI.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            }
            else
            {
                TextRenderer.DrawText(g, txt, lv.Font, new Rectangle(e.Bounds.X + UI.S(10), e.Bounds.Y, e.Bounds.Width - UI.S(14), e.Bounds.Height), UI.Text,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            }
        };
        lv.Resize += delegate {
            int w = lv.ClientSize.Width; for (int i = 0; i < lv.Columns.Count - 1; i++) w -= lv.Columns[i].Width;
            if (w > UI.S(150)) lv.Columns[lv.Columns.Count - 1].Width = w - 2;
        };
        lv.DoubleClick += delegate {
            if (lv.SelectedItems.Count == 0) return;
            ListViewItem it = lv.SelectedItems[0];
            StringBuilder mb = new StringBuilder();
            for (int i = 0; i < it.SubItems.Count; i++) if (it.SubItems[i].Text.Length > 0) mb.AppendLine(lv.Columns[i].Text + ":  " + it.SubItems[i].Text);
            if (!String.IsNullOrEmpty(it.ToolTipText)) { mb.AppendLine(); mb.AppendLine(it.ToolTipText); }
            MessageBox.Show(this, mb.ToString(), "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information);
        };
        return lv;
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        ApplyTitleBarTheme(UI.IsDark);
        ApplyNativeControlThemes();
        BringToFront2();
        BeginInvoke(new System.Windows.Forms.MethodInvoker(BringToFront2));
        BeginInvoke(new System.Windows.Forms.MethodInvoker(delegate { ApplyNativeControlThemes(); }));
        // erst nach dem ersten Zeichnen: Startfenster der exe schließen und die Startzeit protokollieren
        BeginInvoke(new System.Windows.Forms.MethodInvoker(delegate { StartLog.Phase("Oberfläche bereit"); StartLog.SignalReady(); StartLog.Finish(dataDir, version, script); }));
    }

    void BringToFront2()
    {
        try
        {
            if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
            ShowWindow(Handle, 9);
            IntPtr fg = GetForegroundWindow();
            uint fgT = GetWindowThreadProcessId(fg, IntPtr.Zero); uint me = GetCurrentThreadId();
            bool att = fgT != 0 && fgT != me && AttachThreadInput(me, fgT, true);
            BringWindowToTop(Handle); SetForegroundWindow(Handle);
            if (att) AttachThreadInput(me, fgT, false);
            TopMost = true; TopMost = false; Activate();
        }
        catch { }
    }

    static Encoding OemEncoding()
    {
        try { return Encoding.GetEncoding(CultureInfo.CurrentCulture.TextInfo.OEMCodePage); } catch { return Encoding.Default; }
    }

    void Launch(string args, string title)
    {
        ProcessStartInfo psi = new ProcessStartInfo(psExe, args);
        psi.UseShellExecute = false; psi.CreateNoWindow = true;
        psi.RedirectStandardOutput = true; psi.RedirectStandardError = true; psi.RedirectStandardInput = true;
        psi.StandardOutputEncoding = new UTF8Encoding(false);
        psi.StandardErrorEncoding = OemEncoding();
        proc = new Process(); proc.StartInfo = psi; proc.EnableRaisingEvents = true;
        proc.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) queue.Enqueue(e.Data); else outEof = true; };
        proc.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null && e.Data.Trim().Length > 0) queue.Enqueue("@@LOG|Red|" + e.Data); };
        proc.Exited += delegate { exited = true; };

        lvFind.Items.Clear(); lvTests.Items.Clear(); lvBench.Items.Clear(); txtLog.Clear();
        cntK = 0; cntW = 0; cntI = 0; testsOk = 0; benchWarn = 0; benchCount = 0; benchHeads.Clear(); outEof = false; exitSeen = DateTime.MinValue; cardK.Count = 0; cardW.Count = 0; cardI.Count = 0; cardT.Count = 0;
        exited = false; done = false; gotDone = false; cancelled = false; htmlPath = ""; outDir = ""; kiPath = ""; kurzPath = "";
        runOutDir = ""; runWorkDir = ""; runArgs = args; runStarted = DateTime.Now;
        lblResult.Text = ""; lblStep.ForeColor = UI.Text; lblStep.Text = "Wird gestartet ..."; lblCounter.Text = title;
        barAll.Value = 0; barAll.Marquee = false; barSub.Value = 0; barSub.Marquee = true; barAll.Fill = UI.Accent;
        tabs.SetText(0, "Befunde"); tabs.SetText(1, "Tests"); tabs.SetText(2, "Leistung"); tabs.SetText(3, "Sensoren"); tabs.Selected = 0;
        chartRun.Clear(); lblRunSens.Text = " ";
        parJobs.Clear(); parOrder.Clear(); lblPar.Text = " "; lblPar.Visible = false;
        try
        {
            proc.Start();
            proc.BeginOutputReadLine(); proc.BeginErrorReadLine();
            try { proc.StandardInput.Close(); } catch { }
        }
        catch (Exception ex) { MessageBox.Show(this, "PowerShell konnte nicht gestartet werden: " + ex.Message, "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Error); return; }
        running = true;
        setupView.Visible = false; runView.Visible = true;
        btnCancel.Visible = true; btnCancel.Enabled = true;
        btnSkipStep.Visible = true; btnSkipStep.Enabled = false;
        btnStopWait.Visible = false; btnStopWait.Enabled = true;
        btnHtml.Visible = false; btnFolder.Visible = false; btnNew.Visible = false; btnKi.Visible = false; btnExportRun.Visible = false;
        timer.Start();
    }

    static string Get(string[] p, int i) { return (i < p.Length) ? p[i] : ""; }
    static int ToInt(string[] p, int i) { int v; return int.TryParse(Get(p, i), NumberStyles.Integer, CultureInfo.InvariantCulture, out v) ? v : 0; }

    void OnTick()
    {
        string line; int n = 0;
        StringBuilder log = new StringBuilder();
        // alle @@-Zeilen seit dem letzten Takt gesammelt verarbeiten: Listen und Layout nur einmal neu zeichnen
        if (!queue.IsEmpty)
        {
            runView.SuspendLayout();
            lvFind.BeginUpdate(); lvTests.BeginUpdate(); lvBench.BeginUpdate();
            try { while (n < 800 && queue.TryDequeue(out line)) { n++; HandleLine(line, log); } }
            finally { lvFind.EndUpdate(); lvTests.EndUpdate(); lvBench.EndUpdate(); runView.ResumeLayout(false); }
        }
        chartRun.Flush();
        if (log.Length > 0)
        {
            if (txtLog.TextLength > 1500000) txtLog.Text = txtLog.Text.Substring(txtLog.TextLength - 500000);
            txtLog.AppendText(log.ToString());
        }
        if (exited && exitSeen == DateTime.MinValue) exitSeen = DateTime.Now;
        bool eof = outEof;
        if (exited && !done && (eof || (DateTime.Now - exitSeen).TotalSeconds > 5) && queue.IsEmpty) Finish();
    }

    void HandleLine(string line, StringBuilder log)
    {
        if (!line.StartsWith("@@")) { log.AppendLine(line); return; }
        string[] p = line.Substring(2).Split('|');
        switch (p[0])
        {
            case "STEP":
                int s = ToInt(p, 1), t = ToInt(p, 2);
                SetText(lblStep, Get(p, 3));
                SetText(lblCounter, String.Format("Schritt {0} von {1}", s, t));
                if (t > 0) barAll.Value = (s - 1) * 100 / t;
                btnSkipStep.Enabled = false;
                log.AppendLine(); log.AppendLine(">> " + Get(p, 3));
                break;
            case "SKIP_ALLOWED":
                btnSkipStep.Enabled = Get(p, 1) == "1";
                break;
            case "SCHRITT_UEBERSPRINGEN":
                btnSkipStep.Enabled = false;
                break;
            case "SUB":
                int pc = ToInt(p, 1);
                if (pc == -9) { SetText(lblSub, " "); barSub.Marquee = false; barSub.Value = 0; }
                else
                {
                    string st = Get(p, 3).Trim();
                    SetText(lblSub, Get(p, 2).Trim() + (st.Length > 0 ? "   ·   " + st : ""));
                    if (pc < 0) barSub.Marquee = true; else { barSub.Marquee = false; barSub.Value = pc; }
                }
                break;
            case "FIND": AddFinding(Get(p, 1), Get(p, 2), Get(p, 3)); break;
            case "TEST": AddTest(Get(p, 1), Get(p, 2), Get(p, 3)); break;
            case "LOG": log.AppendLine(p.Length > 2 ? String.Join("|", p, 2, p.Length - 2) : ""); break;
            case "BENCH": AddBench(p); break;
            case "PAR": UpdatePar(p); break;
            case "BGRP": UpdateBenchGroup(p); break;
            case "OPTE": UpdateOptResult(p); break;
            case "STOP": btnStopWait.Visible = Get(p, 1) == "1"; btnStopWait.Enabled = true; break;
            case "ORDNER": runOutDir = Get(p, 1); runWorkDir = Get(p, 2); break;
            case "SENSLIM": chartRun.SetLimits(p); break;
            case "SENSSTAT": UpdateSensStatusBadge(Get(p, 1), Get(p, 2)); break;
            case "SENSLEAD":
                {
                    bool firstLead = chartRun.Count == 0;
                    double[] r = chartRun.Add(p);
                    List<string> parts = new List<string>();
                    if (!double.IsNaN(r[1])) parts.Add("CPU " + SensorChart.Fmt(r[1], "°C"));
                    if (!double.IsNaN(r[3])) parts.Add(SensorChart.Fmt(r[3], "W"));
                    if (!double.IsNaN(r[2])) parts.Add("Takt " + SensorChart.Fmt(r[2], "MHz"));
                    if (!double.IsNaN(r[9])) parts.Add("höchster Kern " + SensorChart.Fmt(r[9], "MHz"));
                    if (!double.IsNaN(r[4]) || !double.IsNaN(r[5]) || !double.IsNaN(r[6]))
                    {
                        List<string> g = new List<string>();
                        if (!double.IsNaN(r[4])) g.Add(SensorChart.Fmt(r[4], "°C"));
                        if (!double.IsNaN(r[5])) g.Add(SensorChart.Fmt(r[5], "MHz"));
                        if (!double.IsNaN(r[6])) g.Add(SensorChart.Fmt(r[6], "W"));
                        parts.Add("GPU " + String.Join(" ", g.ToArray()));
                    }
                    if (!double.IsNaN(r[10])) parts.Add("iGPU " + SensorChart.Fmt(r[10], "°C"));
                    if (!double.IsNaN(r[7])) parts.Add("Lüfter " + SensorChart.Fmt(r[7], "U/min"));
                    if (!double.IsNaN(r[13])) parts.Add(SensorChart.Fmt(r[13], "Bilder/s") + (!double.IsNaN(r[14]) ? " und " + SensorChart.Fmt(r[14], "Bilder/s") : ""));
                    SetText(lblRunSens, parts.Count > 0 ? "Aktuell: " + String.Join("   ·   ", parts.ToArray()) : "Aktuell: keine Sensorwerte");
                    if (firstLead) tabs.SetText(3, "Sensoren (live)");
                    break;
                }
            case "DONE":
                htmlPath = Get(p, 2); outDir = Get(p, 3); nK = ToInt(p, 4); nW = ToInt(p, 5); nI = ToInt(p, 6); kurzPath = Get(p, 7); kiPath = Get(p, 8); gotDone = true;
                break;
            default: log.AppendLine(line); break;
        }
    }

    // @@PAR|Key|Titel|Status|Dauer: Hintergrundprüfungen im schnellen Modus
    void UpdatePar(string[] p)
    {
        string k = Get(p, 1); if (k.Length == 0) return;
        if (!parJobs.ContainsKey(k)) parOrder.Add(k);
        parJobs[k] = new string[] { Get(p, 2), Get(p, 3), Get(p, 4) };
        List<string> parts = new List<string>();
        foreach (string x in parOrder) { string[] v = parJobs[x]; parts.Add(v[0] + " " + v[1] + (v[2].Length > 0 ? " (" + v[2] + ")" : "")); }
        SetText(lblPar, "Parallel im Hintergrund:   " + String.Join("   ·   ", parts.ToArray()));
        lblPar.Visible = true;
    }

    void AddFinding(string level, string area, string text)
    {
        ListViewItem it = new ListViewItem(new string[] { level, area, text });
        it.ToolTipText = text;
        int pos = lvFind.Items.Count;
        if (level == "KRITISCH") { pos = cntK; cntK++; cardK.Count = cntK; }
        else if (level == "WARNUNG") { pos = cntK + cntW; cntW++; cardW.Count = cntW; }
        else { cntI++; cardI.Count = cntI; }
        lvFind.Items.Insert(pos, it);
        tabs.SetText(0, String.Format("Befunde ({0})", lvFind.Items.Count));
    }

    static string GroupName(string g)
    {
        if (g == "CPU") return "Prozessor"; if (g == "RAM") return "Arbeitsspeicher"; if (g == "GPU") return "Grafik";
        if (g == "Vergleich") return "Vergleich mit anderen Systemen"; if (g == "WinSAT") return "WinSAT"; return g;
    }

    ListViewItem BenchHead(string g)
    {
        ListViewItem h;
        if (benchHeads.TryGetValue(g, out h)) return h;
        h = new ListViewItem(new string[] { "", GroupName(g), "", "", "", "" }); h.Tag = "hdr";
        benchHeads[g] = h; lvBench.Items.Add(h);
        return h;
    }

    void AddBench(string[] p)
    {
        // BENCH|Status|Komponente|Messung|Anzeige|Index|Vergleich|Hinweis|Referenz|Gruppe
        string g = Get(p, 9); if (g.Length == 0) g = Get(p, 2) == "Datenträger" ? "Laufwerke" : Get(p, 2);
        ListViewItem h = BenchHead(g);
        ListViewItem it = new ListViewItem(new string[] { Get(p, 1), Get(p, 3), Get(p, 4), Get(p, 5), Get(p, 8), Get(p, 6) });
        it.ToolTipText = Get(p, 7);
        int pos = h.Index + 1;
        while (pos < lvBench.Items.Count && !"hdr".Equals(lvBench.Items[pos].Tag)) pos++;
        lvBench.Items.Insert(pos, it);
        if (g != "Vergleich")
        {
            benchCount++;
            if (Get(p, 1).Equals("Warnung", StringComparison.OrdinalIgnoreCase)) benchWarn++;
        }
        tabs.SetText(2, benchWarn > 0 ? String.Format("Leistung ({0} auffällig)", benchWarn) : String.Format("Leistung ({0})", benchCount));
    }

    void UpdateBenchGroup(string[] p)
    {
        ListViewItem h = BenchHead(Get(p, 1));
        h.SubItems[0].Text = Get(p, 3);
        h.SubItems[1].Text = Get(p, 2);
        h.SubItems[2].Text = Get(p, 4);
        h.SubItems[4].Text = Get(p, 5);
        h.ToolTipText = Get(p, 4);
        lvBench.Invalidate();
    }

    void AddTest(string name, string status, string detail)
    {
        ListViewItem it = new ListViewItem(new string[] { status, name, detail });
        it.ToolTipText = detail;
        lvTests.Items.Add(it);
        if (status.Equals("OK", StringComparison.OrdinalIgnoreCase) || status.Equals("Repariert", StringComparison.OrdinalIgnoreCase)) { testsOk++; cardT.Count = testsOk; }
        tabs.SetText(1, String.Format("Tests ({0})", lvTests.Items.Count));
    }

    void Finish()
    {
        done = true; running = false; timer.Stop();
        barSub.Marquee = false; barSub.Value = 0; lblSub.Text = " ";
        btnCancel.Visible = false; btnStopWait.Visible = false; btnSkipStep.Visible = false; btnNew.Visible = true;
        if (chartRun.Count > 0) tabs.SetText(3, "Sensoren");
        int code = -1; try { code = proc.ExitCode; } catch { }
        if (gotDone)
        {
            barAll.Value = 100; barAll.Fill = nK > 0 ? UI.Crit : (nW > 0 ? Color.FromArgb(214, 140, 20) : UI.Ok); barAll.Invalidate();
            lblStep.Text = "Abgeschlossen";
            lblCounter.Text = "Bericht und KI-Dateien liegen im Datenordner";
            lblResult.Text = nK > 0 ? "Kritische Befunde gefunden" : (nW > 0 ? "Warnungen vorhanden" : "Keine Auffälligkeiten");
            lblResult.ForeColor = nK > 0 ? UI.Crit : (nW > 0 ? UI.Warn : UI.Ok);
            btnHtml.Visible = File.Exists(htmlPath); btnFolder.Visible = Directory.Exists(outDir); btnKi.Visible = File.Exists(kiPath);
            btnExportRun.Visible = Directory.Exists(outDir);
            if (btnHtml.Visible) OpenShell(htmlPath);
        }
        else
        {
            lastStepText = lblStep.Text + "   ·   " + lblSub.Text;
            lblStep.Text = cancelled ? "Abgebrochen" : "Ohne Bericht beendet (Code " + code + ")";
            lblStep.ForeColor = UI.Crit; lblCounter.Text = "";
            CleanupDriver();
            string saved = SaveFailureLog(code);
            if (saved.Length > 0) { lblResult.Text = "Protokoll gesichert: " + saved; lblResult.ForeColor = UI.Muted; outDir = runOutDir; btnFolder.Visible = Directory.Exists(outDir); }
            if (!cancelled) tabs.Selected = 4;
        }
        try { if (!ContainsFocus) FlashWindow(Handle, true); } catch { }
    }

    void ExportCurrentRun()
    {
        if (String.IsNullOrEmpty(outDir) || !Directory.Exists(outDir)) return;
        using (SaveFileDialog sfd = new SaveFileDialog())
        {
            sfd.Title = "Lauf als Minibench-Paket exportieren";
            sfd.Filter = "Minibench-Paket (*.minibench)|*.minibench|ZIP-Archiv (*.zip)|*.zip|Alle Dateien (*.*)|*.*";
            sfd.FilterIndex = 1;
            string dirName = Path.GetFileName(outDir);
            sfd.FileName = (String.IsNullOrEmpty(dirName) ? "Lauf" : dirName) + ".minibench";
            if (sfd.ShowDialog(this) != DialogResult.OK) return;

            Cursor = Cursors.WaitCursor;
            List<string> lines;
            string res = RunHelper("-ExportLauf " + Q(outDir) + " -ExportZiel " + Q(sfd.FileName), out lines);
            Cursor = Cursors.Default;
            MessageBox.Show(this, lines.Count > 0 ? String.Join("\r\n", lines.ToArray()) : "Export abgeschlossen.", "Lauf exportieren", MessageBoxButtons.OK, res.StartsWith("1") ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
        }
    }

    void AskCancel()
    {
        if (!running) return;
        if (MessageBox.Show(this, "Lauf wirklich abbrechen?", "Leos Minibench", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        cancelled = true;
        KillTree();
    }

    void KillTree()
    {
        try
        {
            if (proc != null && !proc.HasExited)
            {
                ProcessStartInfo k = new ProcessStartInfo("taskkill.exe", "/T /F /PID " + proc.Id);
                k.CreateNoWindow = true; k.UseShellExecute = false;
                Process kp = Process.Start(k); kp.WaitForExit(8000);
            }
        }
        catch { }
    }

    void OnClosing(object sender, FormClosingEventArgs e)
    {
        // Live-Ansicht sauber beenden, damit ein vorübergehend installierter Treiber entfernt wird
        if (liveRunning) StopLiveAndWait();
        if (!running) { CleanupDriver(); return; }
        if (MessageBox.Show(this, "Der Lauf ist noch aktiv. Abbrechen und schließen?", "Leos Minibench", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) { e.Cancel = true; return; }
        cancelled = true; KillTree();
        try { if (proc != null) proc.WaitForExit(10000); } catch { }
        CleanupDriver();
    }

    static void OpenShell(string path)
    {
        if (String.IsNullOrEmpty(path)) return;
        try { Process.Start("explorer.exe", "\"" + path + "\""); } catch { }
    }

    static void OpenSelect(string path)
    {
        if (String.IsNullOrEmpty(path)) return;
        try { Process.Start("explorer.exe", "/select,\"" + path + "\""); } catch { }
    }
}
