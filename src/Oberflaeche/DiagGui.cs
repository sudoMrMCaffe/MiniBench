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
    List<NavItem> nav = new List<NavItem>();
    List<Control> pages = new List<Control>();
    int curPage;
#pragma warning restore 414

    // Diagnose
    RadioButton rbSchnell, rbVoll, rbCustom, rbTest, rbCrash;
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
    Label lblPar;
    Dictionary<string, string[]> parJobs = new Dictionary<string, string[]>();
    List<string> parOrder = new List<string>();
    // Benchmark
    string[] benchKeys = new string[] { "CPU", "RAM", "GPU", "Disk", "WinSAT" };
    string[] benchText = new string[] {
        "Prozessor: Einzel- und Mehrkern, AES-256, SHA-256, Kompression",
        "Arbeitsspeicher: Lesen, Schreiben, Kopieren, Latenz",
        "Grafik: Rendertest je Grafikeinheit (Bilder/s, 1-%-Low, Punktzahl), Speicherdurchsatz, Desktop-Komposition, PCIe",
        "Laufwerke: sequentiell und 4K (Auswahl unten)",
        "WinSAT-Leistungsbewertung von Windows (2 bis 5 Minuten)" };
    CheckBox[] benchChk;
    CheckedListBox clbDisks, clbCompare;
    List<string> diskNums = new List<string>();
    ComboBox cmbBenchDur, cmbRef;
    CheckBox chkDbSave, chkRefSave;
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
    string[] repRisk = new string[0];
    bool[] repDefault = new bool[0], repUsual = new bool[0];
    string changeDir = "";
    List<ChangeEntry> changes = new List<ChangeEntry>();
    ListView lvChg;
    Button btnUndo;
    // Fuß
    Label lblSel;
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
    Button btnStopWait, btnSkipStep, btnCancel, btnHtml, btnFolder, btnNew, btnKi, btnCopy;
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
        UI.SetTheme(isDark);
        Font = new Font("Segoe UI", 9.75f);
        BackColor = UI.Bg; ForeColor = UI.Text;
        StartPosition = FormStartPosition.CenterScreen;
        Rectangle workArea = Screen.FromPoint(Cursor.Position).WorkingArea;
        int startW = Math.Min(UI.S(1320), (int)(workArea.Width * 0.96));
        int startH = Math.Min(UI.S(860), (int)(workArea.Height * 0.95));
        ClientSize = new Size(startW, startH);
        MinimumSize = new Size(UI.S(880), UI.S(560));
        try { Icon ic = AppSymbol.Get(); if (ic != null) Icon = ic; else Icon = Icon.ExtractAssociatedIcon(psExe); } catch { }
        try { int round = DWMWCP_ROUND; DwmSetWindowAttribute(Handle, DWMWA_WINDOW_CORNER_PREFERENCE, ref round, sizeof(int)); } catch { }

        head = new Panel(); head.Dock = DockStyle.Top; head.Height = UI.S(74); head.BackColor = UI.Header;
        Label t1 = Lbl("Leos Minibench", 18f, true, Color.White); t1.Location = new Point(UI.S(76), UI.S(10));
        Label t2 = Lbl(Environment.MachineName + "   ·   " + OsName() + "   ·   Version " + this.version, 9.75f, false, Color.FromArgb(170, 182, 200)); t2.Location = new Point(UI.S(78), UI.S(44));
        PictureBox logo = new PictureBox(); logo.Size = new Size(UI.S(48), UI.S(48)); logo.Location = new Point(UI.S(18), UI.S(13)); logo.SizeMode = PictureBoxSizeMode.Zoom; logo.BackColor = Color.Transparent;
        try { logo.Image = AppSymbol.Image(UI.S(48)); } catch { }
        head.Controls.Add(logo); head.Controls.Add(t1); head.Controls.Add(t2);
        // ab v2.7: Versionshistorie oben rechts
        FlowLayoutPanel hr = new FlowLayoutPanel(); hr.Dock = DockStyle.Right; hr.Width = UI.S(320); hr.FlowDirection = FlowDirection.RightToLeft; hr.BackColor = Color.Transparent; hr.Padding = new Padding(0, UI.S(24), UI.S(20), 0);
        LinkLabel lnkVer = new LinkLabel(); lnkVer.Text = "Versionshistorie"; lnkVer.AutoSize = true; lnkVer.Font = new Font("Segoe UI", 9.75f);
        lnkVer.LinkColor = Color.FromArgb(147, 197, 253); lnkVer.ActiveLinkColor = Color.White; lnkVer.VisitedLinkColor = Color.FromArgb(147, 197, 253); lnkVer.BackColor = Color.Transparent;
        lnkVer.LinkClicked += delegate { if (setupView != null && setupView.Visible && versionPage >= 0) ShowPage(versionPage); };
        Tip(lnkVer, "Was sich von Version 1.0 bis " + this.version + " geändert hat.");
        hr.Controls.Add(lnkVer);

        // ab v3.31: Theme-Umschalter (Dark Mode)
        btnThemeToggle = new Button();
        btnThemeToggle.Text = UI.IsDark ? "☀️ Hell" : "🌙 Dunkel";
        btnThemeToggle.FlatStyle = FlatStyle.Flat;
        btnThemeToggle.FlatAppearance.BorderSize = 0;
        btnThemeToggle.BackColor = UI.IsDark ? Color.FromArgb(38, 44, 54) : Color.FromArgb(40, 52, 72);
        btnThemeToggle.ForeColor = Color.White;
        btnThemeToggle.Font = new Font("Segoe UI", 8.75f);
        btnThemeToggle.AutoSize = true;
        btnThemeToggle.Margin = new Padding(0, 0, UI.S(16), 0);
        btnThemeToggle.Padding = new Padding(UI.S(8), UI.S(2), UI.S(8), UI.S(2));
        btnThemeToggle.Cursor = Cursors.Hand;
        btnThemeToggle.Click += delegate { ToggleTheme(); };
        Tip(btnThemeToggle, "Wechselt zwischen hellem und dunklem Erscheinungsbild (Dark Mode).");
        hr.Controls.Add(btnThemeToggle);

        head.Controls.Add(hr);

        body = new Panel(); body.Dock = DockStyle.Fill; body.Padding = new Padding(UI.S(20), UI.S(16), UI.S(20), UI.S(14)); body.BackColor = UI.Bg;
        LoadDb();
        setupView = BuildSetup(); runView = BuildRun();
        FillPresets(true);
        setupView.Dock = DockStyle.Fill; runView.Dock = DockStyle.Fill; runView.Visible = false;
        body.Controls.Add(runView); body.Controls.Add(setupView);
        Controls.Add(body); Controls.Add(head);

        FormClosing += OnClosing;
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
            btnThemeToggle.Text = dark ? "☀️ Hell" : "🌙 Dunkel";
            btnThemeToggle.BackColor = dark ? Color.FromArgb(38, 44, 54) : Color.FromArgb(40, 52, 72);
            Tip(btnThemeToggle, dark ? "Zu hellem Design wechseln." : "Zu dunklem Design wechseln (Dark Mode).");
        }

        SuspendLayout();
        try
        {
            BackColor = UI.Bg;
            ForeColor = UI.Text;
            ApplyThemeRecursive(this);
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
        else if (c is ToggleSwitch)
        {
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
        else if (c is CheckBox || c is RadioButton)
        {
            c.ForeColor = UI.Text;
        }
        else if (c is Button)
        {
            Button btn = (Button)c;
            if (btn == btnThemeToggle)
            {
                btn.BackColor = UI.IsDark ? Color.FromArgb(38, 44, 54) : Color.FromArgb(40, 52, 72);
                btn.ForeColor = Color.White;
            }
            else if (btn == btnHtml || btn == btnStart || (btnUndo != null && btn == btnUndo) || (btnDashboard != null && btn == btnDashboard) || (btn.Font.Name.Contains("Semibold") && btn.ForeColor == Color.White && btn.BackColor != UI.Panel))
            {
                btn.BackColor = UI.Accent;
                btn.ForeColor = Color.White;
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
            if (lbl.Parent != head && lbl.ForeColor != Color.White)
            {
                Color fc = lbl.ForeColor;
                if (fc == Color.FromArgb(28, 29, 31) || fc == Color.FromArgb(245, 246, 247) || fc == Color.Black)
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
        if (lblDbPath != null) lblDbPath.Text = "Datenbank: " + (dbDir.Length > 0 ? dbDir : "(nicht verfügbar)");
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
                steps.Add(c);
            }
        }
        List<ContractStep> rep = steps.FindAll(delegate(ContractStep c) { return (c.Module == "Reparatur" || c.Module == "Wartung") && c.Typ == "Massnahme"; });
        if (rep.Count > 0)
        {
            repKeys = new string[rep.Count]; repText = new string[rep.Count]; repMinutes = new int[rep.Count];
            repRisk = new string[rep.Count]; repDefault = new bool[rep.Count]; repUsual = new bool[rep.Count];
            for (int i = 0; i < rep.Count; i++)
            {
                repKeys[i] = rep[i].Key; repText[i] = rep[i].Text; repMinutes[i] = rep[i].Minuten;
                repRisk[i] = rep[i].Risiko; repDefault[i] = rep[i].Vorauswahl; repUsual[i] = rep[i].Ueblich;
            }
        }
        else
        {
            repRisk = new string[repKeys.Length]; repDefault = new bool[repKeys.Length]; repUsual = new bool[repKeys.Length];
            for (int i = 0; i < repKeys.Length; i++) { repRisk[i] = ""; repDefault[i] = i < 2; repUsual[i] = i < 2 || repKeys[i] == "Dateisystem" || repKeys[i] == "Temp" || repKeys[i] == "WMI"; }
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
        Label lm = Lbl("Module", 12f, true, UI.Text); lm.Margin = new Padding(UI.S(2), 0, 0, UI.S(10)); left.Controls.Add(lm);
        nav.Add(ModNav("Diagnose", "Diagnose", "Inventar, Prüfungen, Ereignisse", UI.IcoDiag));
        nav.Add(ModNav("Benchmark", "Benchmark", "Wählbare Messungen mit Vergleich", UI.IcoCpu));
        nav.Add(ModNav("Lasttest", "Lasttest", "Komponenten und Dauer wählbar", UI.IcoFlame));
        nav.Add(ModNav("Wartung", "Wartung", "SFC, DISM, Bereinigung und Systempflege", UI.IcoWartung));
        nav.Add(ModNav("Optimierung", "Optimierung", "Windows Optimisation Pack, gruppiert", UI.IcoOpt));
        navTools = ModNav("Tools", "Tools", "Portable Werkzeuge und Schnellstarter", UI.IcoTools); navTools.HasCheck = false; nav.Add(navTools);
        navSens = ModNav("Sensoren", "Sensoren live", "Temperatur, Takt, Lüfter, Leistung", UI.IcoSens); navSens.HasCheck = false; nav.Add(navSens);
        navDb = new NavItem("Vergleichsdatenbank", db.Count + " gespeicherte Systeme", UI.IcoDb); navDb.HasCheck = false; Tip(navDb, "Vergleichsdatenbank aller gespeicherten Systeme verwalten und vergleichen."); nav.Add(navDb);
        navChg = new NavItem("Änderungen", "Protokoll und Rückgängig", UI.IcoChg); navChg.HasCheck = false; Tip(navChg, "Änderungsprotokoll und Rückgängigmachung von Systemeinstellungen."); nav.Add(navChg);
        for (int i = 0; i < nav.Count; i++)
        {
            int idx = i;
            nav[i].Picked += delegate { ShowPage(idx); };
            nav[i].CheckedChanged += delegate { UpdateSummary(); };
            left.Controls.Add(nav[i]);
        }
        nav[0].Checked = true;
        // ab v2.8 acht Einträge: bei kleinem Fenster mit senkrechter Bildlaufleiste schmaler statt waagerecht zu scrollen
        left.Layout += delegate { int w = left.ClientSize.Width - left.Padding.Horizontal - 2; if (w > UI.S(150)) foreach (NavItem n in nav) if (n.Width != w) n.Width = w; };

        content = new Panel(); content.Dock = DockStyle.Fill; content.BackColor = UI.Panel; content.Padding = new Padding(UI.S(32), UI.S(22), UI.S(28), UI.S(20)); content.AutoScroll = true;
        contentHost = new Panel(); contentHost.Dock = DockStyle.Fill; contentHost.BackColor = UI.Line; contentHost.Padding = new Padding(1);
        contentHost.Controls.Add(content);

        pages.Add(BuildDiagPage()); pages.Add(BuildBenchPage()); pages.Add(BuildLoadPage()); pages.Add(BuildRepairPage()); pages.Add(BuildOptPage()); pages.Add(BuildToolsPage()); pages.Add(BuildSensorPage()); pages.Add(BuildDbPage()); pages.Add(BuildChangePage()); versionPage = pages.Count; pages.Add(BuildVersionPage());
        foreach (Control c in pages) { c.Visible = false; content.Controls.Add(c); }

        TableLayoutPanel foot = new TableLayoutPanel(); foot.Dock = DockStyle.Bottom; foot.Height = UI.S(72); foot.ColumnCount = 2; foot.BackColor = UI.Bg; foot.Padding = new Padding(0, UI.S(8), 0, 0);
        foot.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); foot.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        FlowLayoutPanel fl = new FlowLayoutPanel(); fl.FlowDirection = FlowDirection.TopDown; fl.WrapContents = false; fl.AutoSize = true; fl.BackColor = UI.Bg; fl.Dock = DockStyle.Fill;
        lblSel = Lbl("", 9.5f, true, UI.Text); lblSel.Margin = new Padding(0, 0, 0, UI.S(2)); lblSel.AutoEllipsis = true;
        FlowLayoutPanel fo = new FlowLayoutPanel(); fo.AutoSize = true; fo.WrapContents = false; fo.BackColor = UI.Bg; fo.Margin = new Padding(0);
        chkAnon = Chk("Persönliche Daten in der KI-Datei unkenntlich machen", true); chkAnon.Margin = new Padding(0, UI.S(2), UI.S(16), 0);
        Label ld = Lbl("Ablage: " + (this.dataDir.Length > 0 ? this.dataDir : "(kein Datenordner)"), 9f, false, UI.Muted); ld.Margin = new Padding(0, UI.S(4), 0, 0); ld.AutoEllipsis = true;
        fo.Controls.Add(chkAnon); fo.Controls.Add(ld);
        fl.Controls.Add(lblSel); fl.Controls.Add(fo);
        btnStart = UI.Primary("Start"); btnStart.Margin = new Padding(UI.S(12), 0, 0, 0);
        btnStart.Click += delegate { StartRun(); };
        // Voreinstellungen (ab v2.65): gespeicherte Auswahl laden, speichern, löschen
        FlowLayoutPanel fr = new FlowLayoutPanel(); fr.AutoSize = true; fr.WrapContents = false; fr.BackColor = UI.Bg; fr.Anchor = AnchorStyles.Right; fr.Margin = new Padding(0, UI.S(4), 0, 0);
        Label lp = Lbl("Voreinstellung", 9f, false, UI.Muted); lp.Margin = new Padding(0, UI.S(6), UI.S(6), 0); fr.Controls.Add(lp);
        cmbPreset = Combo(170, new string[0], 0); cmbPreset.Margin = new Padding(0, UI.S(2), UI.S(6), 0); fr.Controls.Add(cmbPreset);
        btnPresetSave = UI.Secondary("Speichern ..."); btnPresetSave.Margin = new Padding(0, 0, UI.S(4), 0); fr.Controls.Add(btnPresetSave);
        btnPresetDel = UI.Secondary("Löschen"); btnPresetDel.Margin = new Padding(0, 0, 0, 0); fr.Controls.Add(btnPresetDel);
        fr.Controls.Add(btnStart);
        cmbPreset.SelectedIndexChanged += delegate { if (!presetFilling) PresetPicked(); };
        btnPresetSave.Click += delegate { SavePresetDialog(); };
        btnPresetDel.Click += delegate { DeletePreset(); };
        foot.Controls.Add(fl, 0, 0); foot.Controls.Add(fr, 1, 0);
        foot.Resize += delegate
        {
            int avail = foot.ClientSize.Width - fr.Width - UI.S(20);
            if (avail > UI.S(80))
            {
                lblSel.MaximumSize = new Size(avail, UI.S(22));
                int availAblage = avail - chkAnon.Width - UI.S(16);
                ld.MaximumSize = new Size(Math.Max(UI.S(80), availAblage), UI.S(20));
            }
        };

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
        { "Updatesuche", "Fragt Windows Update nach ausstehenden Updates (bis 3 Minuten). Es wird nichts heruntergeladen oder installiert. Läuft im schnellen Modus nebenher." },
        { "Integritaet", "Prüft das Dateisystem (Onlinescan), den Komponentenspeicher (DISM ScanHealth) und die Systemdateien (sfc /verifyonly). Nur prüfen, nichts reparieren: Reparaturen bietet das Modul Reparatur. Dauer etwa 10 bis 20 Minuten." },
        { "Defender", "Startet einen Schnellscan von Microsoft Defender und meldet Funde. Entfällt, wenn ein anderer Virenschutz aktiv ist. Läuft im schnellen Modus nebenher." },
        { "SmartLang", "Startet in jedem Laufwerk den erweiterten SMART-Selbsttest (smartctl). SSDs brauchen meist unter 15 Minuten, Festplatten Stunden. Wie lange auf das Ergebnis gewartet wird, steht unten unter SMART-Langtest; der Test läuft im Laufwerk danach weiter." },
        { "Netzwerk", "Prüft Ping zum Router und ins Internet, Namensauflösung (DNS), eine HTTPS-Verbindung und die Download-Geschwindigkeit. Etwa 1 Minute, braucht die Leitung kurz für sich." },
        { "RamTest", "Schreibt Bitmuster in einen Teil des freien Arbeitsspeichers und liest sie zurück (Vollständig: 60 % in 3 Durchläufen, Schnell: 25 % in einem). Findet grobe RAM-Fehler; den ganzen Speicher prüft nur die Windows-Speicherdiagnose oder MemTest86." },
        { "Energieanalyse", "Energieeffizienzanalyse von Windows (powercfg /energy, 60 Sekunden) und DxDiag mit Grafik- und Treiberangaben. Beide Berichte liegen danach in Anhang.zip." } };
    static readonly Dictionary<string, string> benchTips = new Dictionary<string, string> {
        { "CPU", "Einzelkern und Mehrkern mit eigener Rechenlast (Punkte), AES-256 und SHA-256 über die Windows-Kryptografie (ein Thread) und ZIP-Kompression auf allen Threads. Dazu der Takt unter Einzel- und Mehrkernlast. Je Messung 5 Sekunden, im Kurzlauf 2." },
        { "RAM", "Lesen, Schreiben und Kopieren auf allen Threads über bis zu 1 GB sowie die Latenz zufälliger Zugriffe über 256 MB. Bewertet wird gegen den theoretischen Wert aus Takt und Kanalzahl." },
        { "GPU", "WinSAT DWM (Grafikspeicher-Durchsatz, Desktop-Komposition) und der eigene Rendertest mit Direct3D 11 auf jeder gewählten Grafikeinheit (Bilder/s, 1-%-Low, Punktzahl), dazu PCIe-Anbindung und Grafikspeicher." },
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
            "Änderungen: was Leos Minibench an einem PC verändert hat, mit Vorher-Wert und Rückgängig." };
        for (int i = 0; i < nav.Count && i < navTips.Length; i++) Tip(nav[i], navTips[i]);
        // Diagnose
        Tip(rbVoll, "Alle Prüfungen der Liste. 30 bis 60 Minuten, mit SMART-Langtest länger.");
        Tip(rbSchnell, "Inventar, Ereignisse, Updatesuche, Netzwerk und ein kurzer RAM-Test (25 % des freien RAM, ein Durchlauf). 5 bis 10 Minuten.");
        Tip(rbCustom, "Die Prüfungen unten frei wählen.");
        Tip(rbTest, "Prüft in 1 bis 2 Minuten nur, ob das Programm auf diesem PC läuft (Ereignisse der letzten 3 Tage, kleiner RAM-Test). Für die Fehlersuche am Programm, keine Diagnose. Solche Läufe räumt die Datenpflege ins Archiv.");
        Tip(rbCrash, "Wertet nur den letzten unterbrochenen Lauf und die Ereignisprotokolle aus: Woran ist der PC zuletzt abgestürzt? Ohne weitere Prüfungen.");
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
        Tip(cmbBenchDur, "Normal: 5 Sekunden je Messung, stabile Werte. Kurz: 2 Sekunden, etwa halbe Dauer; Kurzläufe werden nur mit Kurzläufen verglichen.");
        Tip(cmbRef, "Bezug für die Prozentwerte (100 %): die gespeicherte Referenz (Referenz.json, gesetzt mit dem Haken unten), der Median aller Systeme der Datenbank oder ein einzelner gespeicherter Lauf.");
        Tip(chkDbSave, "Legt die Werte dieses Laufs als Eintrag in Minibench-Daten\\Datenbank ab (Verlauf auf diesem PC, Vergleiche, Rang).");
        Tip(chkRefSave, "Speichert die Werte dieses Laufs als Referenz.json im Datenordner. Alle PCs, die mit diesem Datenordner messen, werden dann in Prozent dieses Systems angegeben.");
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
                t.Append("\r\nRisikostufe: ").Append(ContractStep.RiskLabel(cs.Risiko)).Append(cs.Risiko == "Aendern" ? " (protokolliert, auf der Seite Änderungen rücknehmbar)" : cs.Risiko == "Eingriff" ? " (nicht automatisch umkehrbar, Absicherung über den Wiederherstellungspunkt)" : "");
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
        Tip(cmbDriver, "PawnIO ist der Treiber, den LibreHardwareMonitor für CPU-Temperatur, CPU-Takt, CPU-Leistung und Mainboard-Lüfter braucht. Bei Bedarf nachfragen: Rückfrage vor jedem Lauf. Ein bereits installierter PawnIO bleibt immer unverändert.");
        Tip(cmbKeep, "Was nach dem Lauf mit PawnIO und smartmontools geschieht, die Leos Minibench installiert hat: entfernen (keine Reste) oder auf diesem PC behalten. Gespeichert je Gerät.");
        // Vergleichsdatenbank, Änderungen, Fuß
        Tip(btnCompare, "Vergleicht die angehakten Systeme in einem HTML-Bericht (mindestens zwei).");
        Tip(btnDelete, "Entfernt die angehakten Einträge aus der Datenbank. Die Berichtsordner bleiben erhalten.");
        Tip(btnDbClean, "Datenpflege: verschiebt Lasttests vor v2.67 (andere Last, nicht vergleichbar), abgebrochene Läufe ohne Bericht und kurze Läufe (Funktionstest, Lasttest nach wenigen Sekunden beendet, Lauf ohne Messwert) sowie ungenutzte Teile von smartmontools nach Minibench-Daten\\Archiv. Gelöscht werden nur ältere Übersetzungen im Cache und Reste der Live-Ansicht; das Protokoll steht in Archiv\\Datenpflege.log.");
        Tip(btnUndo, "Nimmt die angehakten Änderungen zurück (nur Stufe Ändern und nur auf dem PC, auf dem sie entstanden sind).");
        Tip(chkAnon, "Ersetzt in der KI-Datei Benutzernamen, Seriennummern, Domäne und ähnliche persönliche Angaben durch Platzhalter, bevor sie an ein KI-Modell geht.");
        Tip(btnStart, "Startet die angehakten Module in fester Reihenfolge: Diagnose, Benchmark, Lasttest, Wartung, Optimierung.");
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
        Tip(btnNew, "Zurück zur Auswahl für einen neuen Lauf.");
        Tip(btnKi, "Zeigt die KI-Datei im Explorer. Sie enthält Auftrag, Bericht und Rohdaten und lässt sich in ein KI-Modell hochladen.");
        Tip(btnCopy, "Kopiert die KI-Kurzfassung in die Zwischenablage, zum Einfügen in einen KI-Chat.");
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
        for (int k = 0; k < pages.Count; k++) pages[k].Visible = (k == i);
        content.AutoScrollPosition = new Point(0, 0);
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

    FlowLayoutPanel Page(string title, string hint, int idx)
    {
        FlowLayoutPanel f = new FlowLayoutPanel(); f.FlowDirection = FlowDirection.TopDown; f.WrapContents = false; f.AutoSize = true; f.BackColor = UI.Panel; f.Location = new Point(0, 0);
        f.Controls.Add(Lbl(title, 14.5f, true, UI.Text));
        Label h = Lbl(hint, 9.5f, false, UI.Muted); h.MaximumSize = new Size(UI.S(820), 0); h.Margin = new Padding(0, UI.S(3), 0, UI.S(10)); f.Controls.Add(h);
        if (idx >= 0)
        {
            CheckBox on = Chk("Dieses Modul beim Start ausführen", nav[idx].Checked);
            on.Font = new Font("Segoe UI Semibold", 9.75f); on.Margin = new Padding(UI.S(4), 0, 0, UI.S(10));
            on.CheckedChanged += delegate { nav[idx].Checked = on.Checked; };
            nav[idx].CheckedChanged += delegate { if (on.Checked != nav[idx].Checked) on.Checked = nav[idx].Checked; };
            f.Controls.Add(on);
        }
        return f;
    }

    static Label Section(string text)
    {
        Label l = Lbl(text, 10.5f, true, UI.Text); l.Margin = new Padding(0, UI.S(14), 0, UI.S(6)); return l;
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

    static Panel OptionCard(string categoryTitle, string icon, Control[] controls)
    {
        Panel card = new Panel();
        card.BackColor = UI.Panel;
        card.Padding = new Padding(UI.S(14), UI.S(10), UI.S(14), UI.S(10));
        card.Margin = new Padding(UI.S(4), UI.S(4), 0, UI.S(8));
        card.Width = UI.S(840);
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

        Label header = Lbl((icon != null && icon.Length > 0 ? icon + "  " : "") + categoryTitle, 9.75f, true, UI.Text);
        header.Margin = new Padding(0, 0, 0, UI.S(6));
        inner.Controls.Add(header);

        if (controls != null)
        {
            foreach (Control c in controls)
            {
                if (c != null) inner.Controls.Add(c);
            }
        }

        card.Controls.Add(inner);
        card.Paint += delegate(object sender, PaintEventArgs e)
        {
            Rectangle r = card.ClientRectangle; r.Width--; r.Height--;
            using (Pen pen = new Pen(UI.Line, 1f))
            {
                e.Graphics.DrawRectangle(pen, r);
            }
        };
        return card;
    }

    Control BuildDiagPage()
    {
        FlowLayoutPanel f = Page("Diagnose", "Liest Hardware, Treiber, Sicherheit und Ereignisprotokolle aus, führt die gewählten Prüfungen durch und bewertet alles in einem Bericht. Prüfungen verändern nichts am System.", 0);
        if (File.Exists(Path.Combine(cpDir, "laufend.json")))
        {
            Label warn = Lbl("  Der letzte Lauf wurde nicht beendet (Absturz?). Die Absturzanalyse läuft beim nächsten Start automatisch zuerst.  ", 9.75f, true, UI.Crit);
            warn.BackColor = UI.CritBg; warn.Padding = new Padding(UI.S(6)); warn.Margin = new Padding(0, 0, 0, UI.S(8));
            f.Controls.Add(warn);
        }
        f.Controls.Add(Section("Umfang"));
        rbSchnell = new RadioButton(); rbVoll = new RadioButton(); rbCustom = new RadioButton(); rbTest = new RadioButton(); rbCrash = new RadioButton();
        RadioButton[] rbs = new RadioButton[] { rbVoll, rbSchnell, rbCustom, rbTest, rbCrash };
        string[] rt = new string[] {
            "Vollständig (30 bis 60 Minuten, zuzüglich SMART-Langtest)",
            "Schnell (5 bis 10 Minuten: Inventar, Ereignisse, Netzwerk, kurzer RAM-Test)",
            "Benutzerdefiniert (Prüfungen unten frei wählen)",
            "Funktionstest (1 bis 2 Minuten, prüft nur das Skript)",
            "Nur Absturzanalyse (letzter unterbrochener Lauf und Ereignisprotokolle)" };
        for (int i = 0; i < rbs.Length; i++) {
            rbs[i].Text = rt[i]; rbs[i].AutoSize = true; rbs[i].ForeColor = UI.Text;
            rbs[i].Font = new Font("Segoe UI", 9.5f);
            rbs[i].Margin = new Padding(UI.S(4), UI.S(3), 0, UI.S(3));
            rbs[i].CheckedChanged += delegate { ApplyDiagProfile(); };
            f.Controls.Add(rbs[i]);
        }
        chkFast = Chk("Schneller Modus (lesende Prüfungen laufen parallel)", false);
        chkFast.Margin = new Padding(UI.S(4), UI.S(8), 0, UI.S(2));
        chkFast.Font = new Font("Segoe UI Semibold", 9.5f);
        chkFast.CheckedChanged += delegate { UpdateSummary(); }; f.Controls.Add(chkFast);
        Label fastHint = Lbl("Updatesuche, Defender-Schnellscan, Energieanalyse und SMART-Langtest laufen nebenher. Messungen bleiben exklusiv, damit die Werte vergleichbar sind.", 8.5f, false, UI.Muted);
        fastHint.MaximumSize = new Size(UI.S(820), 0); fastHint.Margin = new Padding(UI.S(24), 0, 0, UI.S(4)); f.Controls.Add(fastHint);
        f.Controls.Add(Section("Prüfungen"));
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
            f.Controls.Add(diagChk[i]);
        }
        Label cpuHint = Lbl("Die CPU-Stabilität prüft ab v2.7 das Modul Lasttest (Prozessor, ab 2 Minuten): eigener Lastprozess, Rechenfehler, Takt- und Temperaturverlauf und Drosselnachweis.", 8.5f, false, UI.Muted);
        cpuHint.MaximumSize = new Size(UI.S(820), 0); cpuHint.Margin = new Padding(UI.S(24), UI.S(2), 0, UI.S(4)); f.Controls.Add(cpuHint);
        f.Controls.Add(Section("Optionen"));
        chkInstall = Chk("smartmontools bei Bedarf installieren (winget) oder aus dem Datenordner verwenden", true);
        chkMem = Chk("Windows-Speicherdiagnose beim nächsten Neustart einplanen", false);
        f.Controls.Add(OptionCard("Zusatzwerkzeuge & Speicherdiagnose", UI.IcoTools, new Control[] { chkInstall, chkMem }));

        FlowLayoutPanel r = Row(); r.Controls.Add(RowLabel("Ereignisse der letzten", 150));
        cmbDays = Combo(110, new string[] { "3 Tage", "7 Tage", "14 Tage", "30 Tage", "60 Tage" }, 2); r.Controls.Add(cmbDays);
        FlowLayoutPanel rs = Row(); rs.Controls.Add(RowLabel("SMART-Langtest", 150));
        string[] sm = new string[smartMinutes.Length]; for (int i = 0; i < sm.Length; i++) sm[i] = "höchstens " + smartMinutes[i] + " Min. warten";
        cmbSmartMax = Combo(220, sm, 3); cmbSmartMax.SelectedIndexChanged += delegate { UpdateSummary(); }; rs.Controls.Add(cmbSmartMax);
        Label lsm = Lbl("danach wird der Bericht ohne Ergebnis des Langtests erstellt; der Test läuft im Laufwerk weiter", 8.75f, false, UI.Muted); lsm.Margin = new Padding(0, UI.S(5), 0, 0); rs.Controls.Add(lsm);
        f.Controls.Add(OptionCard("Prüfzeiträume & Schwellenwerte", UI.IcoDiag, new Control[] { r, rs }));
        rbVoll.Checked = true;
        return f;
    }

    void ApplyDiagProfile()
    {
        if (diagChk == null) return;
        bool custom = rbCustom.Checked, crash = rbCrash.Checked;
        // Ereignisse, Updatesuche, Integritaet, Defender, SmartLang, Netzwerk, RamTest, Energieanalyse
        // (CPU-Stabilität ab v2.7 nur noch im Modul Lasttest)
        bool[] voll = new bool[] { true, true, true, true, true, true, true, true };
        bool[] schnell = new bool[] { true, true, false, false, false, true, true, false };
        bool[] test = new bool[] { true, false, false, false, false, true, true, false };
        bool[] none = new bool[] { true, false, false, false, false, false, false, false };
        bool[] pick = rbVoll.Checked ? voll : rbSchnell.Checked ? schnell : rbTest.Checked ? test : crash ? none : null;
        for (int i = 0; i < diagChk.Length; i++)
        {
            if (pick != null) diagChk[i].Checked = pick[i];
            diagChk[i].AutoCheck = custom;
            diagChk[i].ForeColor = custom ? UI.Text : (UI.IsDark ? Color.FromArgb(195, 200, 210) : Color.FromArgb(80, 85, 95));
        }
        chkInstall.Enabled = !crash && !rbTest.Checked;
        chkInstall.ForeColor = chkInstall.Enabled ? UI.Text : (UI.IsDark ? Color.FromArgb(140, 145, 155) : Color.FromArgb(160, 163, 168));
        chkMem.Enabled = !crash && !rbTest.Checked;
        chkMem.ForeColor = chkMem.Enabled ? UI.Text : (UI.IsDark ? Color.FromArgb(140, 145, 155) : Color.FromArgb(160, 163, 168));
        if (chkFast != null) {
            chkFast.Enabled = !crash && !rbTest.Checked;
            chkFast.ForeColor = chkFast.Enabled ? UI.Text : (UI.IsDark ? Color.FromArgb(140, 145, 155) : Color.FromArgb(160, 163, 168));
        }
        cmbDays.Enabled = !rbTest.Checked;
        if (cmbSmartMax != null) cmbSmartMax.Enabled = !crash && !rbTest.Checked;
        UpdateSummary();
    }

    Control BuildBenchPage()
    {
        FlowLayoutPanel f = Page("Benchmark", "Misst die Leistung der gewählten Komponenten und vergleicht sie mit einer Referenz, mit früheren Läufen auf diesem PC und optional mit bereits geprüften Systemen. Temperatur, Takt und Leistung während der Messungen stehen im Bericht unter Sensoren während des Benchmarks.", 1);
        f.Controls.Add(Section("Messungen"));
        benchChk = new CheckBox[benchKeys.Length];
        for (int i = 0; i < benchKeys.Length; i++) { benchChk[i] = Chk(benchText[i], i < 4); benchChk[i].CheckedChanged += delegate { clbDisks.Enabled = benchChk[3].Checked; UpdateSummary(); }; f.Controls.Add(benchChk[i]); }
        f.Controls.Add(Section("Laufwerke"));
        clbDisks = new CheckedListBox(); clbDisks.CheckOnClick = true; clbDisks.Width = UI.S(640); clbDisks.BorderStyle = BorderStyle.FixedSingle; clbDisks.IntegralHeight = false; clbDisks.Margin = new Padding(UI.S(4), UI.S(4), 0, UI.S(4)); clbDisks.BackColor = UI.Panel; clbDisks.ForeColor = UI.Text;
        foreach (string d in disks)
        {
            string[] x = d.Split('|');
            if (x.Length < 7) continue;
            string letters = x[5].Length > 0 ? x[5] : "kein Laufwerksbuchstabe";
            clbDisks.Items.Add(String.Format("Datenträger {0}:  {1}   ({2}, {3}, {4}, {5})", x[0], x[1], x[2], x[3], x[4], letters), x[6] != "1" && x[5].Length > 0);
            diskNums.Add(x[0]);
        }
        clbDisks.Height = Math.Max(UI.S(48), Math.Min(8, clbDisks.Items.Count) * UI.S(21) + UI.S(6));
        clbDisks.ItemCheck += delegate { BeginInvoke(new System.Windows.Forms.MethodInvoker(UpdateSummary)); };
        f.Controls.Add(clbDisks);
        Label dh = Lbl("Gemessen wird mit einer Testdatei auf dem Volume mit dem meisten freien Platz. USB-Datenträger sind abgewählt.", 8.75f, false, UI.Muted); dh.Margin = new Padding(UI.S(4), UI.S(3), 0, 0); dh.MaximumSize = new Size(UI.S(820), 0); f.Controls.Add(dh);
        f.Controls.Add(Section("Rendertest (Grafik)"));
        FlowLayoutPanel rg0 = Row(); rg0.Controls.Add(RowLabel("Grafikeinheit", 150));
        cmbGpuSel = Combo(420, GpuChoiceTexts(), 0); rg0.Controls.Add(cmbGpuSel); f.Controls.Add(rg0);
        FlowLayoutPanel rg = Row(); rg.Controls.Add(RowLabel("Auflösung", 150));
        cmbGpuRes = Combo(140, new string[] { "1280x720", "1920x1080" }, 0); rg.Controls.Add(cmbGpuRes);
        rg.Controls.Add(RowLabel("Anzeige", 70)); cmbGpuShow = Combo(170, new string[] { "Fenster", "Vollbild", "ohne Anzeige" }, 0); rg.Controls.Add(cmbGpuShow);
        f.Controls.Add(rg);
        Label gh = Lbl("Eigener Rendertest mit Direct3D 11, je Grafikeinheit 6 s Aufwärmen und 20 s Messung ohne VSync. Ergebnis: Ø Bilder/s, 1-%-Low und Punktzahl. Vorher prüft eine kurze Gegenprobe, ob eine Bildratengrenze im Treiber bremst. Esc im Fenster beendet den Test.", 8.75f, false, UI.Muted);
        gh.Margin = new Padding(UI.S(4), UI.S(3), 0, 0); gh.MaximumSize = new Size(UI.S(820), 0); f.Controls.Add(gh);
        chkGpuWahl = Chk("Bei Hybridgrafik WinSAT zusätzlich auf der Grafikkarte messen (kurze Umstellung, steht im Änderungsprotokoll)", false);
        chkGpuWahl.MaximumSize = new Size(UI.S(840), 0); chkGpuWahl.Margin = new Padding(UI.S(4), UI.S(8), 0, UI.S(3)); f.Controls.Add(chkGpuWahl);

        f.Controls.Add(Section("Messdauer und Referenz"));
        FlowLayoutPanel r1 = Row(); r1.Controls.Add(RowLabel("Messdauer", 150));
        cmbBenchDur = Combo(260, new string[] { "Normal (stabile Werte)", "Kurz (etwa halbe Dauer)" }, 0); cmbBenchDur.SelectedIndexChanged += delegate { UpdateSummary(); }; r1.Controls.Add(cmbBenchDur); f.Controls.Add(r1);
        FlowLayoutPanel r2 = Row(); r2.Controls.Add(RowLabel("Referenz (100 %)", 150));
        cmbRef = Combo(520, new string[0], 0); r2.Controls.Add(cmbRef); f.Controls.Add(r2);
        clbCompare = new CheckedListBox(); clbCompare.BackColor = UI.Panel; clbCompare.ForeColor = UI.Text;
        f.Controls.Add(Section("Speichern"));
        chkDbSave = Chk("Ergebnis in der Vergleichsdatenbank speichern", dbDir.Length > 0); chkDbSave.Enabled = dbDir.Length > 0; f.Controls.Add(chkDbSave);
        chkRefSave = Chk("Dieses System als Referenz (100 %) festlegen", false); f.Controls.Add(chkRefSave);
        FillRefLists();
        return f;
    }

    void FillRefLists()
    {
        if (cmbRef == null) return;
        string prevRef = cmbRef.SelectedIndex > 1 && cmbRef.SelectedIndex - 2 < refItems.Count ? refItems[cmbRef.SelectedIndex - 2].Path : "";
        HashSet<string> prevCmp = new HashSet<string>();
        for (int i = 0; i < clbCompare.Items.Count; i++) if (clbCompare.GetItemChecked(i) && i < cmpItems.Count) prevCmp.Add(cmpItems[i].Path);
        cmbRef.Items.Clear(); refItems.Clear(); clbCompare.Items.Clear(); cmpItems.Clear();
        cmbRef.Items.Add(SavedRefText());
        cmbRef.Items.Add("Median aller Systeme in der Vergleichsdatenbank");
        int sel = 0;
        foreach (DbEntry e in db)
        {
            if (!e.HasBench) continue;
            refItems.Add(e); cmbRef.Items.Add(e.Label);
            if (e.Path == prevRef) sel = cmbRef.Items.Count - 1;
            cmpItems.Add(e); clbCompare.Items.Add(e.Label, prevCmp.Contains(e.Path));
        }
        cmbRef.SelectedIndex = sel;
        if (clbCompare.Items.Count == 0) { clbCompare.Items.Add("(noch keine Systeme mit Benchmark in der Datenbank)"); clbCompare.Enabled = false; }
        else clbCompare.Enabled = true;
        clbCompare.Height = Math.Max(UI.S(48), Math.Min(8, clbCompare.Items.Count) * UI.S(21) + UI.S(6));
    }

    Control BuildLoadPage()
    {
        FlowLayoutPanel f = Page("Lasttest", "Belastet die gewählten Komponenten gleichzeitig, jede mit eigener Dauer, und zeichnet Temperatur, Takt, Leistung und Lüfter auf. Gemeldet werden Rechen-, Bit- und Datenfehler, WHEA-Fehler und Drosselung. \"Test beenden\" bricht jederzeit ab.", 2);
        string[] mins = new string[] { "2 Minuten", "5 Minuten", "10 Minuten", "15 Minuten", "30 Minuten", "60 Minuten", "120 Minuten", "240 Minuten" };
        f.Controls.Add(Section("Komponenten und Dauer"));
        FlowLayoutPanel r1 = Row(); chkLCpu = Chk("Prozessor (alle Threads, Ergebnisprüfung)", true); chkLCpu.Width = UI.S(350); chkLCpu.AutoSize = false; r1.Controls.Add(chkLCpu);
        cmbLCpu = Combo(120, mins, 3); r1.Controls.Add(cmbLCpu); f.Controls.Add(r1);
        FlowLayoutPanel r2 = Row(); chkLRam = Chk("Arbeitsspeicher (Mustertest, Bitfehler)", true); chkLRam.Width = UI.S(350); chkLRam.AutoSize = false; r2.Controls.Add(chkLRam);
        cmbLRam = Combo(120, mins, 3); r2.Controls.Add(cmbLRam);
        r2.Controls.Add(RowLabel("Anteil am freien RAM", 140)); cmbLRamPct = Combo(80, new string[] { "25 %", "40 %", "60 %", "75 %" }, 1); r2.Controls.Add(cmbLRamPct); f.Controls.Add(r2);
        FlowLayoutPanel r3 = Row(); chkLGpu = Chk("Grafik (Rendertest)", false); chkLGpu.Width = UI.S(350); chkLGpu.AutoSize = false; r3.Controls.Add(chkLGpu);
        cmbLGpu = Combo(120, mins, 3); r3.Controls.Add(cmbLGpu);
        cmbLGpuRes = Combo(110, new string[] { "1280x720", "1920x1080" }, 0); r3.Controls.Add(cmbLGpuRes);
        cmbLGpuShow = Combo(140, new string[] { "Fenster", "Vollbild", "ohne Anzeige" }, 0); r3.Controls.Add(cmbLGpuShow);
        f.Controls.Add(r3);
        FlowLayoutPanel r3b = Row(); Label lsel = RowLabel("Grafikeinheit", 332); lsel.Margin = new Padding(UI.S(22), UI.S(1), UI.S(6), UI.S(1)); r3b.Controls.Add(lsel);
        cmbLGpuSel = Combo(420, GpuChoiceTexts(), 0); r3b.Controls.Add(cmbLGpuSel); f.Controls.Add(r3b);
        // Einstellungen des Rendertests auf beiden Seiten gleich halten: Benchmark -> Lasttest und Lasttest -> Benchmark
        // (ab 3.53 über CopySelection; vorher setzte sync2 die Grafikeinheit des Lasttests auf den Wert des Benchmarks zurück)
        EventHandler sync1 = delegate { if (syncGpu || cmbGpuRes == null) return; syncGpu = true; try { CopySelection(GpuCombosBench(), GpuCombosLast()); } finally { syncGpu = false; } };
        EventHandler sync2 = delegate { if (syncGpu || cmbGpuRes == null) return; syncGpu = true; try { CopySelection(GpuCombosLast(), GpuCombosBench()); } finally { syncGpu = false; } };
        if (cmbGpuRes != null) { cmbGpuRes.SelectedIndexChanged += sync1; cmbGpuShow.SelectedIndexChanged += sync1; }
        if (cmbGpuSel != null) cmbGpuSel.SelectedIndexChanged += sync1;
        cmbLGpuRes.SelectedIndexChanged += sync2; cmbLGpuShow.SelectedIndexChanged += sync2; cmbLGpuSel.SelectedIndexChanged += sync2;
        FlowLayoutPanel r4 = Row(); chkLDisk = Chk("Datenträger (Schreiben, Lesen, Datenprüfung)", false); chkLDisk.Width = UI.S(350); chkLDisk.AutoSize = false; r4.Controls.Add(chkLDisk);
        cmbLDisk = Combo(120, mins, 2); r4.Controls.Add(cmbLDisk);
        r4.Controls.Add(RowLabel("Laufwerk", 70));
        List<string> letters = new List<string>();
        foreach (string d in disks)
        {
            string[] x = d.Split('|'); if (x.Length < 7 || x[5].Length == 0) continue;
            foreach (string l in x[5].Split(',')) { string t = l.Trim(); if (t.Length > 0) letters.Add(t + "   " + x[1]); }
        }
        if (letters.Count == 0) letters.Add("C:");
        letters.Sort();
        cmbLDiskDrive = Combo(260, letters.ToArray(), 0); r4.Controls.Add(cmbLDiskDrive); f.Controls.Add(r4);
        foreach (CheckBox c in new CheckBox[] { chkLCpu, chkLRam, chkLGpu, chkLDisk }) c.CheckedChanged += delegate { UpdateLoadEnabled(); UpdateSummary(); };
        foreach (ComboBox c in new ComboBox[] { cmbLCpu, cmbLRam, cmbLGpu, cmbLDisk }) c.SelectedIndexChanged += delegate { UpdateSummary(); };
        f.Controls.Add(Section("Abbruchschwelle"));
        FlowLayoutPanel r5 = Row(); r5.Controls.Add(RowLabel("CPU-Temperatur", 140));
        cmbLAbortCpu = Combo(260, new string[] { "automatisch (TjMax, sonst 100 °C)", "85 °C", "90 °C", "95 °C", "100 °C", "aus" }, 0); r5.Controls.Add(cmbLAbortCpu);
        r5.Controls.Add(RowLabel("GPU-Temperatur", 120)); cmbLAbortGpu = Combo(100, new string[] { "85 °C", "90 °C", "95 °C", "aus" }, 1); r5.Controls.Add(cmbLAbortGpu); f.Controls.Add(r5);
        Label ha = Lbl("Liegt die Temperatur rund 10 Sekunden auf oder über der Schwelle, endet der Test mit einem Befund. Echte CPU-Temperaturen gibt es mit LibreHardwareMonitor und dem Treiber PawnIO (nur nach Rückfrage, wird nach dem Lauf entfernt).", 8.75f, false, UI.Muted);
        ha.MaximumSize = new Size(UI.S(820), 0); ha.Margin = new Padding(UI.S(4), UI.S(4), 0, 0); f.Controls.Add(ha);
        Label h = Lbl("Grafiklast: eigener Rendertest mit Direct3D 11 (Volllast ähnlich FurMark) auf den gewählten Grafikeinheiten gleichzeitig, mit Bilder/s-Verlauf, Bildprüfung alle 30 Sekunden und Erkennung von Treiber-Resets. Der Datenträgertest schreibt eine Testdatei (bis 4 GB) und löscht sie danach. Am Notebook das Netzteil anschließen.", 8.75f, false, UI.Muted);
        h.MaximumSize = new Size(UI.S(820), 0); h.Margin = new Padding(UI.S(4), UI.S(12), 0, 0); f.Controls.Add(h);
        UpdateLoadEnabled();
        return f;
    }

    void UpdateLoadEnabled()
    {
        cmbLCpu.Enabled = chkLCpu.Checked; cmbLRam.Enabled = chkLRam.Checked; cmbLRamPct.Enabled = chkLRam.Checked;
        cmbLGpu.Enabled = chkLGpu.Checked; cmbLDisk.Enabled = chkLDisk.Checked; cmbLDiskDrive.Enabled = chkLDisk.Checked;
        if (cmbLGpuRes != null) { cmbLGpuRes.Enabled = chkLGpu.Checked; cmbLGpuShow.Enabled = chkLGpu.Checked; }
        if (cmbLGpuSel != null) cmbLGpuSel.Enabled = chkLGpu.Checked;
    }

    Control BuildRepairPage()
    {
        FlowLayoutPanel f = Page("Wartung", "Führt die gewählten Wartungs- und Reparaturaufgaben nacheinander aus. Vorher wird auf Wunsch ein Wiederherstellungspunkt angelegt. Einige Aufgaben werden erst nach einem Neustart wirksam.", 3);
        f.Controls.Add(Section("Absicherung"));
        chkRestorePoint = Chk("Vorher einen Systemwiederherstellungspunkt anlegen", true); f.Controls.Add(chkRestorePoint);
        f.Controls.Add(Section("Reparaturen"));
        FlowLayoutPanel b = Row(); b.Margin = new Padding(UI.S(4), UI.S(4), 0, UI.S(8));
        Button all = UI.Secondary("Übliche Auswahl"); all.Margin = new Padding(0);
        Tip(all, "Wählt alle risikoarmen Routine-Wartungsaufgaben wie Bereinigungen und Cache-Leerungen aus.");
        all.Click += delegate { for (int i = 0; i < repChk.Length; i++) repChk[i].Checked = repUsual[i]; };
        Button none = UI.Secondary("Keine");
        Tip(none, "Hebt die Auswahl aller Wartungs- und Reparaturaufgaben auf.");
        none.Click += delegate { foreach (CheckBox c in repChk) c.Checked = false; };
        b.Controls.Add(all); b.Controls.Add(none); f.Controls.Add(b);
        repChk = new CheckBox[repKeys.Length];
        for (int i = 0; i < repKeys.Length; i++)
        {
            string t = repText[i] + (repRisk[i].Length > 0 ? "   ·  " + ContractStep.RiskLabel(repRisk[i]) : "");
            repChk[i] = Chk(t, repDefault[i]); repChk[i].CheckedChanged += delegate { UpdateSummary(); }; f.Controls.Add(repChk[i]);
        }
        Label lg = Lbl("Ändern: wird mit Vorher-Wert protokolliert und lässt sich auf der Seite Änderungen zurücknehmen.  Eingriff: nicht automatisch umkehrbar, Absicherung über den Wiederherstellungspunkt.", 8.75f, false, UI.Muted);
        lg.MaximumSize = new Size(UI.S(820), 0); lg.Margin = new Padding(UI.S(4), UI.S(8), 0, 0); f.Controls.Add(lg);
        return f;
    }

    // ------------------------------------------------------------ Seite Optimierung (ab v2.8)
    // Katalog aus dem Skript (Get-OptGuiLines): Kategorien zum Auf- und Zuklappen, je Eintrag ein Haken mit Risikostufe.
    List<OptItem> optItems = new List<OptItem>();
    List<string[]> optCats = new List<string[]>();
    Dictionary<string, Label> optCatCount = new Dictionary<string, Label>();
    Dictionary<string, FlowLayoutPanel> optCatBody = new Dictionary<string, FlowLayoutPanel>();
    Dictionary<string, LinkLabel> optCatToggle = new Dictionary<string, LinkLabel>();
    CheckBox chkOptRestore;
    Label lblOptInfo, lblOptState;
    Button btnOptCheck, btnOptTools, btnOptAll;
    List<Button> optPresetButtons = new List<Button>();
    static readonly string[] optPresetTips = new string[] {
        "Minimal wie im Optimisation Pack: Datenschutz-Einstellungen (O&O-Auswahl), Dienste und Aufgaben, Indizierung aus, Caches leeren.",
        "Leos Empfehlung: Wie die Voreinstellung beim Start ausgewählt (empfohlene Optimierungen für Datenschutz, Apps, Dienste und System).",
        "Erweitert wie im Optimisation Pack: Leos Empfehlung plus Windows-Funktionen, Zusatzfeatures, vorinstallierte Apps und Darstellung.",
        "Nichts gewählt." };

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

    string OptBoxText(OptItem it)
    {
        StringBuilder t = new StringBuilder(it.Titel);
        if (it.Risiko == "Eingriff") t.Append("   ·  Eingriff");
        if (it.Neustart == "immer") t.Append("   ·  Neustart");
        if (it.Verwaltet && DomainPc) t.Append("   ·  verwaltet");
        if (it.Zustand.Length > 0) t.Append("   ·  " + (it.Zustand == "aktiv" ? "bereits aktiv" : it.Zustand));
        return t.ToString();
    }

    string OptTipText(OptItem it)
    {
        StringBuilder t = new StringBuilder(it.Tip.Replace(" ¶", "\r\n"));
        t.Append("\r\nRisikostufe: ").Append(ContractStep.RiskLabel(it.Risiko)).Append(it.Risiko == "Aendern" ? " (protokolliert, auf der Seite Änderungen einzeln rücknehmbar)" : " (nicht automatisch umkehrbar, Absicherung über den Wiederherstellungspunkt)");
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
        FlowLayoutPanel f = Page("Optimierung", "Die Einstellungen des Windows Optimisation Pack mit seiner Sophia- und O&O-Auswahl, nativ umgesetzt und nach Kategorien gruppiert. Ändern steht mit Vorher-Wert im Änderungsprotokoll und lässt sich auf der Seite Änderungen einzeln zurücknehmen; Eingriffe sichert der Wiederherstellungspunkt ab.", 4);
        f.Controls.Add(Section("Absicherung"));
        chkOptRestore = Chk("Vorher einen Systemwiederherstellungspunkt anlegen", true); f.Controls.Add(chkOptRestore);
        f.Controls.Add(Section("Vorlagen und Zustand"));
        FlowLayoutPanel b = Row(); b.Margin = new Padding(UI.S(4), UI.S(2), 0, UI.S(4));
        string[] pn = new string[] { "Minimal", "Leos Empfehlung", "Erweitert", "Keine" };
        for (int i = 0; i < pn.Length; i++)
        {
            string key = i == 0 ? "M" : i == 1 ? "S" : i == 2 ? "E" : "";
            Button pb = UI.Secondary(pn[i]); pb.Margin = new Padding(i == 0 ? 0 : UI.S(8), 0, 0, 0);
            pb.Click += delegate { ApplyOptPreset(key); };
            optPresetButtons.Add(pb); b.Controls.Add(pb);
        }
        btnOptCheck = UI.Secondary("Zustand prüfen"); btnOptCheck.Margin = new Padding(UI.S(16), 0, 0, 0); btnOptCheck.Click += delegate { CheckOptState(); }; b.Controls.Add(btnOptCheck);
        btnOptTools = UI.Secondary("Werkzeuge holen ..."); btnOptTools.Margin = new Padding(UI.S(8), 0, 0, 0); btnOptTools.Click += delegate { FetchOptTools(); }; b.Controls.Add(btnOptTools);
        btnOptAll = UI.Secondary("Alle aufklappen"); btnOptAll.Margin = new Padding(UI.S(8), 0, 0, 0); btnOptAll.Click += delegate { ToggleOptAll(); }; b.Controls.Add(btnOptAll);
        f.Controls.Add(b);
        lblOptInfo = Lbl("", 9f, false, UI.Muted); lblOptInfo.MaximumSize = new Size(UI.S(820), 0); lblOptInfo.Margin = new Padding(UI.S(4), UI.S(4), UI.S(4), 0); f.Controls.Add(lblOptInfo);
        lblOptState = Lbl("", 9f, false, UI.Muted); lblOptState.MaximumSize = new Size(UI.S(820), 0); lblOptState.Margin = new Padding(UI.S(4), UI.S(2), UI.S(4), UI.S(4)); f.Controls.Add(lblOptState);
        if (optItems.Count == 0) { lblOptInfo.Text = "Der Katalog der Optimierung fehlt (Skript ohne Modul Optimierung)."; return f; }
        foreach (string[] k in optCats)
        {
            string key = k[0];
            List<OptItem> items = optItems.FindAll(delegate(OptItem it) { return it.Kat == key; });
            if (items.Count == 0) continue;
            FlowLayoutPanel h = Row(); h.Margin = new Padding(UI.S(4), UI.S(10), 0, 0);
            LinkLabel tg = new LinkLabel(); tg.Text = "▸ " + k[1]; tg.AutoSize = true; tg.Font = new Font("Segoe UI Semibold", 10f); tg.LinkColor = UI.Text; tg.ActiveLinkColor = UI.Accent; tg.LinkBehavior = LinkBehavior.HoverUnderline; tg.Margin = new Padding(0, UI.S(2), UI.S(10), 0);
            Label cnt = Lbl("", 9f, false, UI.Muted); cnt.Margin = new Padding(0, UI.S(4), UI.S(12), 0);
            LinkLabel all = new LinkLabel(); all.Text = "alle"; all.AutoSize = true; all.Margin = new Padding(0, UI.S(4), UI.S(8), 0); all.LinkColor = UI.Accent;
            LinkLabel none = new LinkLabel(); none.Text = "keine"; none.AutoSize = true; none.Margin = new Padding(0, UI.S(4), 0, 0); none.LinkColor = UI.Accent;
            h.Controls.Add(tg); h.Controls.Add(cnt); h.Controls.Add(all); h.Controls.Add(none);
            f.Controls.Add(h);
            Label desc = Lbl(k[2], 8.75f, false, UI.Muted); desc.MaximumSize = new Size(UI.S(820), 0); desc.Margin = new Padding(UI.S(20), 0, UI.S(4), UI.S(2)); f.Controls.Add(desc);
            FlowLayoutPanel body = new FlowLayoutPanel(); body.FlowDirection = FlowDirection.TopDown; body.WrapContents = false; body.AutoSize = true; body.BackColor = UI.Panel; body.Margin = new Padding(UI.S(16), 0, 0, UI.S(4)); body.Visible = false;
            foreach (OptItem it in items)
            {
                it.Box = Chk(OptBoxText(it), false); it.Box.Margin = new Padding(UI.S(4), UI.S(2), 0, UI.S(2)); it.Box.UseMnemonic = false;
                it.Box.CheckedChanged += delegate { UpdateOptCounts(); };
                body.Controls.Add(it.Box);
            }
            f.Controls.Add(body);
            optCatCount[key] = cnt; optCatBody[key] = body; optCatToggle[key] = tg;
            tg.LinkClicked += delegate { body.Visible = !body.Visible; tg.Text = (body.Visible ? "▾ " : "▸ ") + k[1]; };
            all.LinkClicked += delegate { foreach (OptItem it in items) it.Box.Checked = true; };
            none.LinkClicked += delegate { foreach (OptItem it in items) it.Box.Checked = false; };
            Tip(tg, k[2] + "\r\nKlicken zeigt oder verbirgt die Einträge.");
            Tip(all, "Alle Einträge dieser Kategorie wählen."); Tip(none, "Keinen Eintrag dieser Kategorie wählen.");
        }
        Label lg = Lbl("Ändern: mit Vorher-Wert protokolliert, auf der Seite Änderungen einzeln rücknehmbar.  Eingriff: nicht automatisch umkehrbar (Apps, Zusatzfeatures, Bereinigung, DDU).  verwaltet: berührt Gruppenrichtlinien, auf Domänen-PCs nicht in den Vorlagen.  Benutzereinstellungen gelten für den angemeldeten Benutzer.", 8.75f, false, UI.Muted);
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
                + (DomainPc ? "  Dieser PC ist Mitglied einer Domäne" + (skip > 0 ? "; " + skip + " verwaltete Einträge sind nicht gewählt" : "") + ". Gruppenrichtlinien können Einstellungen wieder überschreiben." : "");
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
        foreach (KeyValuePair<string, Label> kv in optCatCount)
        {
            int a = 0, n = 0;
            foreach (OptItem it in optItems) if (it.Kat == kv.Key) { a++; if (it.Box.Checked) n++; }
            SetText(kv.Value, n + " von " + a + " gewählt");
            kv.Value.ForeColor = n > 0 ? UI.Text : UI.Muted;
        }
        UpdateSummary();
    }

    void ToggleOptAll()
    {
        bool open = false;
        foreach (FlowLayoutPanel p in optCatBody.Values) if (!p.Visible) { open = true; break; }
        foreach (KeyValuePair<string, FlowLayoutPanel> kv in optCatBody)
        {
            kv.Value.Visible = open;
            string t = optCatToggle[kv.Key].Text.Substring(2);
            optCatToggle[kv.Key].Text = (open ? "▾ " : "▸ ") + t;
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

    // Argumente für den Arbeitsprozess nach Rückfrage; null = nicht starten
    string OptStartArgs()
    {
        List<string> ids = SelectedOptIds();
        if (ids.Count == 0) { MessageBox.Show(this, "In der Optimierung ist kein Eintrag ausgewählt.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information); ShowPage(4); return null; }
        int aend = 0; List<string> ein = new List<string>(); List<string> ver = new List<string>(); bool rs = false;
        Dictionary<string, int> perCat = new Dictionary<string, int>();
        foreach (OptItem it in optItems)
        {
            if (!it.Box.Checked) continue;
            if (it.Risiko == "Eingriff") ein.Add(it.Titel); else aend++;
            if (it.Verwaltet && DomainPc) ver.Add(it.Titel);
            if (it.Neustart == "immer") rs = true;
            int c; perCat.TryGetValue(it.Kat, out c); perCat[it.Kat] = c + 1;
        }
        StringBuilder m = new StringBuilder();
        m.AppendLine(ids.Count + " Einträge der Optimierung werden angewendet:");
        foreach (string[] k in optCats) { int c; if (perCat.TryGetValue(k[0], out c)) m.AppendLine("·  " + k[1] + ": " + c); }
        m.AppendLine();
        m.AppendLine(aend + " Einstellungen der Stufe Ändern (einzeln rücknehmbar).");
        if (ein.Count > 0)
        {
            m.AppendLine(ein.Count + " Eingriffe ohne automatisches Rückgängig:");
            for (int i = 0; i < ein.Count && i < 12; i++) m.AppendLine("·  " + ein[i]);
            if (ein.Count > 12) m.AppendLine("·  und " + (ein.Count - 12) + " weitere");
        }
        if (ver.Count > 0) m.AppendLine("\r\nDomänen-PC: " + ver.Count + " gewählte Einträge berühren Gruppenrichtlinien und können beim nächsten Abgleich überschrieben werden.");
        if (rs) m.AppendLine("\r\nEinige Einträge werden erst nach einem Neustart wirksam.");
        m.AppendLine(chkOptRestore.Checked ? "\r\nVorher wird ein Wiederherstellungspunkt angelegt." : "\r\nEs wird KEIN Wiederherstellungspunkt angelegt.");
        m.AppendLine("\r\nFortfahren?");
        if (MessageBox.Show(this, m.ToString(), "Optimierung bestätigen", MessageBoxButtons.YesNo, ein.Count > 0 ? MessageBoxIcon.Warning : MessageBoxIcon.Question) != DialogResult.Yes) return null;
        return " -Optimierungen " + String.Join(",", ids.ToArray()) + (chkOptRestore.Checked ? "" : " -OptOhneWiederherstellungspunkt");
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

    // 1 = Treiber installieren, 0 = ohne, -1 = Start abbrechen. Fragt bei Bedarf zugleich, ob die Hilfswerkzeuge bleiben.
    // ab v2.8: fehlt LibreHardwareMonitor im Datenordner (z. B. neuer Ordner ohne Tools), vor dem Lauf anbieten, es zu holen.
    // Im Praxistest vom 03.10. liefen Benchmark und Lasttest auf TORRENT so ohne CPU-Temperatur, Leistung und AMD-GPU-Werte.
    bool lhmAsked = false;
    int AskSensorTools()
    {
        if (LhmPresent || lhmAsked || ToolsDir.Length == 0) return 0;
        lhmAsked = true;
        DialogResult r = MessageBox.Show(this, "LibreHardwareMonitor fehlt im Tools-Ordner dieses Datenordners:\r\n" + ToolsDir + "\r\n\r\n"
            + "Ohne die Bibliothek gibt es bei Diagnose, Benchmark und Lasttest keine CPU-Temperatur und keine CPU-Leistung; GPU-Werte nur über nvidia-smi oder den Windows-Grafiktreiber.\r\n\r\n"
            + "Jetzt LibreHardwareMonitor 0.9.6 und das PawnIO-Setup aus den offiziellen Releases holen (geprüft mit festen SHA-256-Werten, auf dem PC wird nichts installiert)?\r\n\r\n"
            + "Ja: holen und danach starten\r\nNein: ohne Sensorwerkzeuge starten\r\nAbbrechen: nicht starten", "Sensorwerkzeuge fehlen", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning);
        if (r == DialogResult.Cancel) return -1;
        if (r != DialogResult.Yes) return 0;
        List<string> lines; string res = RunHelperPumped("-SensorWerkzeugeHolen", out lines, 900);
        UpdateSensTools();
        if (res != "1") MessageBox.Show(this, (lines.Count > 0 ? String.Join("\r\n", lines.ToArray()) : "Keine Rückmeldung vom Arbeitsprozess.") + "\r\n\r\nDer Lauf startet ohne Sensorwerkzeuge.", "Sensorwerkzeuge", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        return 0;
    }

    int AskDriver()
    {
        runKeep = "";
        if (AskSensorTools() < 0) return -1;
        if (!LhmPresent || !PawnSetupPresent || PawnIoVersion().Length > 0) return 0;
        int pol = cmbDriver == null ? 0 : cmbDriver.SelectedIndex;
        if (pol == 1) return 1;
        if (pol == 2) return 0;
        bool askKeep = cmbKeep == null || cmbKeep.SelectedIndex == 0;
        using (Form d = new Form())
        {
            d.Text = "PawnIO-Treiber"; d.FormBorderStyle = FormBorderStyle.FixedDialog; d.MaximizeBox = false; d.MinimizeBox = false; d.ShowInTaskbar = false;
            d.StartPosition = FormStartPosition.CenterParent; d.Font = new Font("Segoe UI", 9.5f); d.BackColor = UI.Bg; d.AutoSize = true; d.AutoSizeMode = AutoSizeMode.GrowAndShrink; d.Padding = new Padding(UI.S(16));
            FlowLayoutPanel f = new FlowLayoutPanel(); f.FlowDirection = FlowDirection.TopDown; f.AutoSize = true; f.WrapContents = false; f.Dock = DockStyle.Fill;
            Label t = new Label(); t.AutoSize = true; t.MaximumSize = new Size(UI.S(520), 0); t.Margin = new Padding(0, 0, 0, UI.S(10));
            t.Text = "Für CPU-Temperatur, CPU-Takt, CPU-Leistung und die Lüfter am Mainboard braucht LibreHardwareMonitor den Treiber PawnIO. Die Installation erscheint auf der Seite Änderungen.";
            f.Controls.Add(t);
            RadioButton rbMit = new RadioButton(); rbMit.Text = "mit Treiber messen"; rbMit.AutoSize = true; rbMit.Checked = true; rbMit.Margin = new Padding(UI.S(4), UI.S(3), 0, UI.S(3));
            RadioButton rbOhne = new RadioButton(); rbOhne.Text = "ohne Treiber (GPU, Datenträger und Ersatzwerte)"; rbOhne.AutoSize = true; rbOhne.Margin = new Padding(UI.S(4), UI.S(3), 0, UI.S(3));
            f.Controls.Add(rbMit); f.Controls.Add(rbOhne);
            CheckBox cKeep = new CheckBox(); cKeep.AutoSize = true; cKeep.Margin = new Padding(UI.S(4), UI.S(10), 0, UI.S(3)); cKeep.MaximumSize = new Size(UI.S(520), 0);
            cKeep.Text = "PawnIO und smartmontools nach dem Lauf auf diesem PC behalten (sonst am Ende wieder entfernt, nach einem Absturz beim nächsten Start)";
            cKeep.Checked = cmbKeep != null && cmbKeep.SelectedIndex == 2; cKeep.Enabled = askKeep;
            CheckBox cMerk = new CheckBox(); cMerk.AutoSize = true; cMerk.Margin = new Padding(UI.S(4), UI.S(3), 0, UI.S(3)); cMerk.Text = "Wahl für diesen PC merken (änderbar auf der Seite Sensoren)";
            f.Controls.Add(cKeep); f.Controls.Add(cMerk);
            FlowLayoutPanel b = new FlowLayoutPanel(); b.AutoSize = true; b.Margin = new Padding(0, UI.S(12), 0, 0);
            Button ok = UI.Primary("Starten"); ok.DialogResult = DialogResult.OK; ok.Margin = new Padding(0, 0, UI.S(8), 0); Button ab = UI.Secondary("Abbrechen"); ab.DialogResult = DialogResult.Cancel;
            b.Controls.Add(ok); b.Controls.Add(ab); f.Controls.Add(b);
            d.Controls.Add(f); d.AcceptButton = ok; d.CancelButton = ab;
            if (d.ShowDialog(this) != DialogResult.OK) return -1;
            int drv = rbMit.Checked ? 1 : 0;
            if (askKeep) runKeep = cKeep.Checked ? "behalten" : "entfernen";
            if (cMerk.Checked)
            {
                if (cmbDriver != null) cmbDriver.SelectedIndex = drv == 1 ? 1 : 2;
                if (askKeep && cmbKeep != null) cmbKeep.SelectedIndex = cKeep.Checked ? 2 : 1;
                SaveDeviceTools();
            }
            return drv;
        }
    }

    // Einstellung für Hilfswerkzeuge je Gerät, gemeinsam mit dem Arbeitsprozess in Geraete.json (Format Minibench-Geraete/1)
    string DeviceFile { get { return dataDir.Length > 0 ? Path.Combine(dataDir, "Geraete.json") : ""; } }
    static readonly string[] keepValues = new string[] { "fragen", "entfernen", "behalten" };
    static readonly string[] driverValues = new string[] { "fragen", "verwenden", "nein" };

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
        object w; if (cmbKeep != null && ed.TryGetValue("Werkzeuge", out w)) { int i = Array.IndexOf(keepValues, Convert.ToString(w)); if (i >= 0) cmbKeep.SelectedIndex = i; }
        object t; if (cmbDriver != null && ed.TryGetValue("Treiber", out t)) { int i = Array.IndexOf(driverValues, Convert.ToString(t)); if (i >= 0) cmbDriver.SelectedIndex = i; }
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
            if (cmbKeep != null) ed["Werkzeuge"] = keepValues[Math.Max(0, cmbKeep.SelectedIndex)];
            if (cmbDriver != null) ed["Treiber"] = driverValues[Math.Max(0, cmbDriver.SelectedIndex)];
            if (!ed.ContainsKey("Behalten")) ed["Behalten"] = new object[0];
            ed["Geaendert"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
            Directory.CreateDirectory(dataDir);
            System.Web.Script.Serialization.JavaScriptSerializer js = new System.Web.Script.Serialization.JavaScriptSerializer();
            File.WriteAllText(DeviceFile, js.Serialize(d), new UTF8Encoding(false));
        }
        catch { }
    }

    // Argument für den Arbeitsprozess: Wahl im Startdialog, sonst feste Einstellung, bei "jedes Mal fragen" ohne Dialog entfernen
    string KeepArg()
    {
        string k = runKeep;
        if (k.Length == 0 && cmbKeep != null && cmbKeep.SelectedIndex > 0) k = keepValues[cmbKeep.SelectedIndex];
        return k.Length > 0 ? " -WerkzeugeBehalten " + k : "";
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
    }

    Control BuildSensorPage()
    {
        FlowLayoutPanel f = Page("Sensoren live", "Zeigt Temperatur, Takt, Lüfter, Spannung und Leistung laufend an (Kurven der letzten zehn Minuten). CPU-Werte und Mainboard-Lüfter brauchen den Treiber PawnIO; er wird nur nach Rückfrage installiert und beim Beenden entfernt.", -1);
        lblSensTools = Lbl("", 9f, false, UI.Muted); lblSensTools.MaximumSize = new Size(UI.S(880), 0); lblSensTools.Margin = new Padding(UI.S(4), 0, UI.S(4), UI.S(8)); f.Controls.Add(lblSensTools);
        FlowLayoutPanel b = Row(); b.Margin = new Padding(UI.S(4), 0, 0, UI.S(8));
        btnLive = UI.Primary("Live-Ansicht starten"); btnLive.Margin = new Padding(0); btnLive.Padding = new Padding(UI.S(14), UI.S(3), UI.S(14), UI.S(3)); btnLive.Font = new Font("Segoe UI Semibold", 9.75f);
        btnLive.Click += delegate { if (liveRunning) StopLive(); else StartLive(); };
        btnSensTools = UI.Secondary("Sensorwerkzeuge holen"); btnSensTools.Margin = new Padding(UI.S(8), 0, 0, 0); btnSensTools.Click += delegate { FetchSensorTools(); };
        btnSensSave = UI.Secondary("Aufzeichnung speichern"); btnSensSave.Margin = new Padding(UI.S(8), 0, 0, 0); btnSensSave.Enabled = false; btnSensSave.Click += delegate { SaveSensorCsv(); };
        b.Controls.Add(btnLive); b.Controls.Add(btnSensTools); b.Controls.Add(btnSensSave);
        f.Controls.Add(b);
        FlowLayoutPanel bd = Row(); bd.Margin = new Padding(UI.S(4), 0, 0, UI.S(8));
        bd.Controls.Add(RowLabel("PawnIO-Treiber", 120));
        cmbDriver = Combo(230, new string[] { "bei Bedarf nachfragen", "vorübergehend verwenden", "nicht verwenden" }, 0); bd.Controls.Add(cmbDriver);
        Label ld = Lbl("gilt für Live-Ansicht, Diagnose, Benchmark und Lasttest; ein vorhandener PawnIO bleibt immer unverändert", 8.75f, false, UI.Muted); ld.Margin = new Padding(0, UI.S(5), 0, 0); bd.Controls.Add(ld);
        f.Controls.Add(bd);
        FlowLayoutPanel bk = Row(); bk.Margin = new Padding(UI.S(4), 0, 0, UI.S(8));
        bk.Controls.Add(RowLabel("Hilfswerkzeuge", 120));
        cmbKeep = Combo(230, new string[] { "jedes Mal fragen", "nach dem Lauf entfernen", "auf diesem PC behalten" }, 0); bk.Controls.Add(cmbKeep);
        Label lk = Lbl("PawnIO und smartmontools, die Leos Minibench installiert hat; gespeichert je Gerät in Geraete.json", 8.75f, false, UI.Muted); lk.Margin = new Padding(0, UI.S(5), 0, 0); bk.Controls.Add(lk);
        f.Controls.Add(bk);
        LoadDeviceTools();
        cmbKeep.SelectedIndexChanged += delegate { SaveDeviceTools(); };
        cmbDriver.SelectedIndexChanged += delegate { SaveDeviceTools(); };
        lblSensInfo = Lbl("Live-Ansicht nicht gestartet.", 9f, false, UI.Muted); lblSensInfo.MaximumSize = new Size(UI.S(880), 0); lblSensInfo.Margin = new Padding(UI.S(4), 0, UI.S(4), UI.S(6)); f.Controls.Add(lblSensInfo);
        chartLive = new SensorChart(); chartLive.Width = UI.S(880); chartLive.Height = UI.S(330); chartLive.WindowSec = 600; chartLive.Margin = new Padding(UI.S(4), 0, 0, UI.S(8));
        chartLive.Empty = "Noch keine Messwerte. \"Live-Ansicht starten\" öffnet die Sensoren.";
        f.Controls.Add(chartLive);
        lvSens = new ListView(); lvSens.View = View.Details; lvSens.FullRowSelect = true; lvSens.Width = UI.S(880); lvSens.Height = UI.S(380); lvSens.BorderStyle = BorderStyle.FixedSingle; lvSens.HideSelection = false; lvSens.ShowGroups = true; lvSens.ShowItemToolTips = true; lvSens.Margin = new Padding(UI.S(4), 0, 0, UI.S(4));
        EnableDarkListView(lvSens);
        string[] cols = new string[] { "Sensor", "Art", "Aktuell", "Min", "Max", "Quelle" };
        int[] w = new int[] { UI.S(260), UI.S(120), UI.S(110), UI.S(110), UI.S(110), UI.S(140) };
        for (int i = 0; i < cols.Length; i++) lvSens.Columns.Add(cols[i], w[i], i >= 2 && i <= 4 ? HorizontalAlignment.Right : HorizontalAlignment.Left);
        f.Controls.Add(lvSens);
        Label hint = Lbl("\"Aufzeichnung speichern\" legt alle Werte als CSV unter Berichte\\Sensoren ab. Während eines Laufs ist die Live-Ansicht aus; der Lasttest zeigt seine Kurven im Reiter Sensoren.", 8.75f, false, UI.Muted);
        hint.MaximumSize = new Size(UI.S(880), 0); hint.Margin = new Padding(UI.S(4), UI.S(4), UI.S(4), 0); f.Controls.Add(hint);
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
        int d = AskDriver(); if (d < 0) return;
        try { Directory.CreateDirectory(cpDir); File.Delete(Path.Combine(cpDir, "sensor.stop")); } catch { }
        string args = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -EventMode -SensorLive" + (dataDir.Length > 0 ? " -DatenDir " + Q(dataDir) : "") + (d == 1 ? " -SensorTreiber" : "") + KeepArg();
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
        lblSensInfo.Text = d == 1 ? "Wird gestartet, PawnIO wird vorübergehend installiert ..." : "Wird gestartet ...";
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
    string RunHelperPumped(string args, out List<string> lines, int timeoutSec)
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
                p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data == null) { eof = true; return; } lock (got) got.Add(e.Data); };
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

    int Minutes(ComboBox c) { int v; return int.TryParse(Convert.ToString(c.SelectedItem).Split(' ')[0], out v) ? v : 15; }

    List<string> SelectedModules()
    {
        List<string> m = new List<string>();
        string[] names = new string[] { "Diagnose", "Benchmark", "Lasttest", "Wartung", "Optimierung" };
        for (int i = 0; i < names.Length; i++) if (nav[i].Checked) m.Add(names[i]);
        return m;
    }

    int EstimateMinutes()
    {
        int t = 0;
        if (nav[0].Checked)
        {
            if (rbCrash.Checked) t += 1;
            else if (rbTest.Checked) t += 2;
            else
            {
                t += 3;
                int[] add = new int[] { 1, 2, 12, 3, 10, 1, 2, 2 };
                for (int i = 0; i < diagChk.Length; i++) if (diagChk[i].Checked) t += add[i];
                // schneller Modus: Updatesuche, Defender und Energieanalyse laufen neben den übrigen Prüfungen
                if (chkFast != null && chkFast.Checked && chkFast.Enabled) { int par = (diagChk[1].Checked ? 2 : 0) + (diagChk[3].Checked ? 3 : 0) + (diagChk[7].Checked ? 2 : 0); t -= Math.Min(par, Math.Max(0, t - 3)); }
            }
        }
        if (nav[1].Checked)
        {
            bool kurz = cmbBenchDur.SelectedIndex == 1;
            if (benchChk[0].Checked) t += kurz ? 1 : 2;
            if (benchChk[1].Checked) t += 1;
            if (benchChk[2].Checked) t += 2;
            if (benchChk[3].Checked) t += clbDisks.CheckedItems.Count * (kurz ? 1 : 1);
            if (benchChk[4].Checked) t += 4;
        }
        if (nav[2].Checked)
        {
            int m = 0;
            if (chkLCpu.Checked) m = Math.Max(m, Minutes(cmbLCpu)); if (chkLRam.Checked) m = Math.Max(m, Minutes(cmbLRam));
            if (chkLGpu.Checked) m = Math.Max(m, Minutes(cmbLGpu)); if (chkLDisk.Checked) m = Math.Max(m, Minutes(cmbLDisk) + 1);
            t += m + 1;
        }
        if (nav[3].Checked) for (int i = 0; i < repChk.Length; i++) if (repChk[i].Checked) t += repMinutes[i];
        if (nav[4].Checked) { int n = 0; foreach (OptItem it in optItems) if (it.Box.Checked) { n++; t += it.Minuten; } t += 1 + n / 40; }
        return t;
    }

    void UpdateSummary()
    {
        if (lblSel == null || diagChk == null || benchChk == null || repChk == null || chkLCpu == null || chkOptRestore == null) return;
        List<string> m = SelectedModules();
        if (m.Count == 0) { lblSel.Text = "Kein Modul ausgewählt"; lblSel.ForeColor = UI.Crit; btnStart.Enabled = false; return; }
        int min = EstimateMinutes();
        lblSel.ForeColor = UI.Text;
        lblSel.Text = String.Join(" + ", m.ToArray()) + (nav[0].Checked && chkFast != null && chkFast.Checked && chkFast.Enabled ? " (schneller Modus)" : "") + "   ·   geschätzt ca. " + Math.Max(1, min) + " Minuten" + (nav[0].Checked && diagChk[4].Checked && !rbCrash.Checked ? " zuzüglich SMART-Langtest (höchstens " + SmartMax() + " Min.)" : "");
        btnStart.Enabled = true;
    }

    static string Q(string s) { return "\"" + (s ?? "").TrimEnd('\\') + "\""; }

    void StartRun()
    {
        List<string> mods = SelectedModules();
        if (mods.Count == 0) return;
        // Live-Ansicht und Lauf greifen auf dieselben Sensoren und denselben Treiber zu
        if (liveRunning && !StopLiveAndWait()) return;
        bool drv = false; runKeep = "";
        if ((nav[0].Checked && !rbCrash.Checked) || nav[1].Checked || nav[2].Checked) { int d = AskDriver(); if (d < 0) return; drv = d == 1; }
        StringBuilder a = new StringBuilder();
        a.Append("-NoProfile -ExecutionPolicy Bypass -File \"").Append(script).Append("\" -EventMode");
        a.Append(" -Module ").Append(String.Join(",", mods.ToArray()));
        if (dataDir.Length > 0) a.Append(" -DatenDir ").Append(Q(dataDir));
        if (!chkAnon.Checked) a.Append(" -KiOhneAnonymisierung");

        if (nav[0].Checked)
        {
            if (rbCrash.Checked) a.Append(" -AnalyzeLastRun");
            else
            {
                string prof = rbVoll.Checked ? "Voll" : rbSchnell.Checked ? "Schnell" : rbTest.Checked ? "Funktionstest" : "Benutzerdefiniert";
                a.Append(" -DiagProfil ").Append(prof);
                List<string> o = new List<string>();
                for (int i = 0; i < diagChk.Length; i++) if (diagChk[i].Checked) o.Add(diagKeys[i]);
                a.Append(" -DiagOptionen ").Append(o.Count > 0 ? String.Join(",", o.ToArray()) : "Keine");
                if (chkInstall.Enabled && chkInstall.Checked) a.Append(" -InstallSmartmontools");
                if (chkMem.Enabled && chkMem.Checked) a.Append(" -ScheduleWindowsMemTest");
            }
            if (cmbDays.Enabled) a.Append(" -EventDays ").Append(Convert.ToString(cmbDays.SelectedItem).Split(' ')[0]);
            if (!rbCrash.Checked && diagChk[4].Checked) a.Append(" -SmartTimeoutMinutes ").Append(SmartMax());
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
            if (cmbBenchDur.SelectedIndex == 1) a.Append(" -BenchmarkKurz");
            if (benchChk[2].Checked && chkGpuWahl != null && chkGpuWahl.Checked) a.Append(" -BenchGpuWahl");
            if (cmbRef.SelectedIndex == 1) a.Append(" -ReferenzDatei *median");
            else if (cmbRef.SelectedIndex > 1 && cmbRef.SelectedIndex - 2 < refItems.Count) a.Append(" -ReferenzDatei ").Append(Q(refItems[cmbRef.SelectedIndex - 2].Path));
            List<string> cmp = new List<string>();
            if (clbCompare.Enabled) for (int i = 0; i < clbCompare.Items.Count && i < cmpItems.Count; i++) if (clbCompare.GetItemChecked(i)) cmp.Add(cmpItems[i].Path);
            if (cmp.Count > 0) a.Append(" -VergleichDateien ").Append(Q(String.Join(";", cmp.ToArray())));
            if (!chkDbSave.Checked) a.Append(" -KeineDatenbank");
            if (chkRefSave.Checked) a.Append(" -ReferenzSpeichern");
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
            List<string> r = new List<string>(); StringBuilder names = new StringBuilder();
            for (int i = 0; i < repChk.Length; i++) if (repChk[i].Checked) { r.Add(repKeys[i]); names.AppendLine("·  " + repText[i] + (repRisk[i].Length > 0 ? "  [" + ContractStep.RiskLabel(repRisk[i]) + "]" : "")); }
            if (r.Count == 0) { MessageBox.Show(this, "Im Wartungsmodul ist nichts ausgewählt.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Information); ShowPage(3); return; }
            if (MessageBox.Show(this, "Folgende Reparaturen werden ausgeführt:\r\n\r\n" + names.ToString() + (chkRestorePoint.Checked ? "\r\nVorher wird ein Wiederherstellungspunkt angelegt." : "\r\nEs wird KEIN Wiederherstellungspunkt angelegt.") + "\r\n\r\nFortfahren?",
                "Wartung bestätigen", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            a.Append(" -Wartung ").Append(String.Join(",", r.ToArray()));
            if (!chkRestorePoint.Checked) a.Append(" -OhneWiederherstellungspunkt");
        }
        if (nav[4].Checked)
        {
            string optArgs = OptStartArgs(); if (optArgs == null) return;
            a.Append(optArgs);
        }
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
        Launch(a.ToString(), String.Join(" + ", mods.ToArray()));
    }

    // "automatisch ..." = auto, "aus" = aus, sonst die Zahl vor dem Gradzeichen
    static string AbortArg(ComboBox c)
    {
        string s = Convert.ToString(c.SelectedItem);
        if (s.StartsWith("automatisch")) return "auto";
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
        return "Gespeicherte Referenz (noch keine festgelegt, Haken unten setzen)";
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
    static readonly string[] diagProfiles = new string[] { "Voll", "Schnell", "Benutzerdefiniert", "Funktionstest", "Absturzanalyse" };

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
            f.StartPosition = FormStartPosition.CenterParent; f.Font = new Font("Segoe UI", 9.5f); f.BackColor = UI.Bg; f.AutoSize = true; f.AutoSizeMode = AutoSizeMode.GrowAndShrink; f.Padding = new Padding(16);
            FlowLayoutPanel p = new FlowLayoutPanel(); p.FlowDirection = FlowDirection.TopDown; p.AutoSize = true; p.WrapContents = false; p.Dock = DockStyle.Fill;
            Label l = new Label(); l.AutoSize = true; l.MaximumSize = new Size(460, 0); l.Margin = new Padding(0, 0, 0, 8);
            l.Text = "Speichert die Auswahl aller Seiten (Module, Prüfungen, Messungen, Lasttest, Reparaturen, Sensortreiber) im Datenordner. Laufwerke und Vergleichssysteme bleiben je PC frei.";
            p.Controls.Add(l);
            TextBox tb = new TextBox(); tb.Width = 320; tb.Text = presetActive.Length > 0 ? presetActive : "Standardprüfung"; p.Controls.Add(tb);
            CheckBox cs = new CheckBox(); cs.AutoSize = true; cs.Margin = new Padding(3, 10, 3, 3); cs.Text = "Beim Start automatisch laden (dann genügt ein Klick auf Start)"; cs.Checked = start.Length == 0 || start == tb.Text; p.Controls.Add(cs);
            FlowLayoutPanel b = new FlowLayoutPanel(); b.AutoSize = true; b.Margin = new Padding(0, 12, 0, 0);
            Button ok = UI.Primary("Speichern"); ok.DialogResult = DialogResult.OK; Button ab = UI.Secondary("Abbrechen"); ab.DialogResult = DialogResult.Cancel;
            b.Controls.Add(ok); b.Controls.Add(ab); p.Controls.Add(b);
            f.Controls.Add(p); f.AcceptButton = ok; f.CancelButton = ab;
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
    static string GetS(Dictionary<string, object> d, string k) { object o; return d != null && d.TryGetValue(k, out o) && o != null ? Convert.ToString(o) : null; }
    static void GetC(Dictionary<string, object> d, string k, CheckBox c) { bool v; if (c != null && GetB(d, k, out v)) c.Checked = v; }
    static void GetCb(Dictionary<string, object> d, string k, ComboBox c)
    {
        string v = GetS(d, k); if (c == null || v == null) return;
        int i = c.Items.IndexOf(v);
        if (i < 0) for (int j = 0; j < c.Items.Count; j++) if (Convert.ToString(c.Items[j]).StartsWith(v, StringComparison.OrdinalIgnoreCase)) { i = j; break; }
        if (i >= 0) c.SelectedIndex = i;
    }

    // Alle Einstellungen der Seiten als Schlüssel und Wert (Texte der Auswahllisten, damit Änderungen der Reihenfolge nicht stören)
    public Dictionary<string, object> CaptureSettings()
    {
        Dictionary<string, object> d = new Dictionary<string, object>();
        string[] mods = new string[] { "Diagnose", "Benchmark", "Lasttest", "Reparatur", "Optimierung" };
        for (int i = 0; i < mods.Length && i < nav.Count; i++) d["Modul." + mods[i]] = nav[i].Checked;
        RadioButton[] rbs = new RadioButton[] { rbVoll, rbSchnell, rbCustom, rbTest, rbCrash };
        for (int i = 0; i < rbs.Length; i++) if (rbs[i] != null && rbs[i].Checked) d["Diag.Profil"] = diagProfiles[i];
        for (int i = 0; i < diagKeys.Length && diagChk != null; i++) d["Diag." + diagKeys[i]] = diagChk[i].Checked;
        PutC(d, "Diag.SchnellerModus", chkFast); PutC(d, "Diag.Smartmontools", chkInstall); PutC(d, "Diag.Speicherdiagnose", chkMem);
        PutCb(d, "Diag.Tage", cmbDays); PutCb(d, "Diag.SmartMax", cmbSmartMax);
        for (int i = 0; i < benchKeys.Length && benchChk != null; i++) d["Bench." + benchKeys[i]] = benchChk[i].Checked;
        PutC(d, "Bench.GpuWahl", chkGpuWahl); PutCb(d, "Bench.Dauer", cmbBenchDur); PutC(d, "Bench.Datenbank", chkDbSave);
        if (cmbRef != null) d["Bench.Referenz"] = cmbRef.SelectedIndex == 1 ? "Median" : (cmbRef.SelectedIndex > 1 && cmbRef.SelectedIndex - 2 < refItems.Count ? "Datei:" + refItems[cmbRef.SelectedIndex - 2].Path : "Gespeichert");
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
        RadioButton[] rbs = new RadioButton[] { rbVoll, rbSchnell, rbCustom, rbTest, rbCrash };
        if (prof != null) { int i = Array.IndexOf(diagProfiles, prof); if (i >= 0 && rbs[i] != null) rbs[i].Checked = true; }
        for (int i = 0; i < diagKeys.Length && diagChk != null; i++) GetC(d, "Diag." + diagKeys[i], diagChk[i]);
        GetC(d, "Diag.SchnellerModus", chkFast); GetC(d, "Diag.Smartmontools", chkInstall); GetC(d, "Diag.Speicherdiagnose", chkMem);
        GetCb(d, "Diag.Tage", cmbDays); GetCb(d, "Diag.SmartMax", cmbSmartMax);
        for (int i = 0; i < benchKeys.Length && benchChk != null; i++) GetC(d, "Bench." + benchKeys[i], benchChk[i]);
        GetC(d, "Bench.GpuWahl", chkGpuWahl); GetCb(d, "Bench.Dauer", cmbBenchDur);
        if (chkDbSave != null && chkDbSave.Enabled) GetC(d, "Bench.Datenbank", chkDbSave);
        if (cmbRef != null)
        {
            string r = GetS(d, "Bench.Referenz");
            int ri = r == null ? -1 : r == "Median" ? 1 : 0;
            if (r != null && r.StartsWith("Datei:")) { int k = refItems.FindIndex(delegate(DbEntry x) { return String.Equals(x.Path, r.Substring(6), StringComparison.OrdinalIgnoreCase); }); ri = k >= 0 ? k + 2 : 0; }
            if (ri >= 0 && ri < cmbRef.Items.Count) cmbRef.SelectedIndex = ri;
        }
        if (chkRefSave != null) chkRefSave.Checked = false;
        GetCb(d, "Gpu.Aufloesung", cmbGpuRes); GetCb(d, "Gpu.Anzeige", cmbGpuShow);
        string gs = GetS(d, "Gpu.Auswahl"); if (gs != null) SetGpuChoice(gs);
        GetC(d, "Last.CPU", chkLCpu); GetCb(d, "Last.CPUDauer", cmbLCpu);
        GetC(d, "Last.RAM", chkLRam); GetCb(d, "Last.RAMDauer", cmbLRam); GetCb(d, "Last.RAMAnteil", cmbLRamPct);
        GetC(d, "Last.GPU", chkLGpu); GetCb(d, "Last.GPUDauer", cmbLGpu);
        GetC(d, "Last.Disk", chkLDisk); GetCb(d, "Last.DiskDauer", cmbLDisk); GetCb(d, "Last.Laufwerk", cmbLDiskDrive);
        GetCb(d, "Last.AbbruchCpu", cmbLAbortCpu); GetCb(d, "Last.AbbruchGpu", cmbLAbortGpu);
        for (int i = 0; i < repKeys.Length && repChk != null; i++) GetC(d, "Rep." + repKeys[i], repChk[i]);
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
        lblStep = Lbl("Wird gestartet ...", 13f, true, UI.Text); lblStep.AutoEllipsis = true;
        lblCounter = Lbl("", 10f, false, UI.Muted); lblCounter.Anchor = AnchorStyles.Right; lblCounter.Margin = new Padding(UI.S(3), UI.S(6), 0, UI.S(3));
        stepRow.Controls.Add(lblStep, 0, 0); stepRow.Controls.Add(lblCounter, 1, 0);
        t.Controls.Add(stepRow, 0, 0);
        barAll = new FlatBar(); barAll.Dock = DockStyle.Fill; barAll.Margin = new Padding(UI.S(3), UI.S(4), UI.S(3), UI.S(6)); t.Controls.Add(barAll, 0, 1);
        lblSub = Lbl(" ", 9.5f, false, UI.Muted); lblSub.AutoEllipsis = true; lblSub.Margin = new Padding(UI.S(3), UI.S(4), UI.S(3), UI.S(2)); t.Controls.Add(lblSub, 0, 2);
        barSub = new FlatBar(); barSub.Dock = DockStyle.Fill; barSub.Fill = Color.FromArgb(96, 140, 245); barSub.Margin = new Padding(UI.S(3), UI.S(3), UI.S(3), UI.S(5)); t.Controls.Add(barSub, 0, 3);
        lblPar = Lbl(" ", 9f, false, UI.Muted); lblPar.AutoEllipsis = true; lblPar.Margin = new Padding(UI.S(3), 0, UI.S(3), 0); lblPar.Visible = false; t.Controls.Add(lblPar, 0, 4);

        FlowLayoutPanel cards = new FlowLayoutPanel(); cards.AutoSize = true; cards.BackColor = UI.Bg; cards.Margin = new Padding(0, UI.S(14), 0, UI.S(10));
        cardK = new StatCard("kritisch", UI.Crit); cardW = new StatCard("Warnungen", UI.Warn); cardI = new StatCard("Hinweise", UI.Info); cardT = new StatCard("Tests bestanden", UI.Ok);
        cards.Controls.Add(cardK); cards.Controls.Add(cardW); cards.Controls.Add(cardI); cards.Controls.Add(cardT);
        t.Controls.Add(cards, 0, 5);

        tabs = new TabStrip(); tabs.Dock = DockStyle.Fill; tabs.Items.Add("Befunde"); tabs.Items.Add("Tests"); tabs.Items.Add("Leistung"); tabs.Items.Add("Sensoren"); tabs.Items.Add("Protokoll");
        t.Controls.Add(tabs, 0, 6);

        Panel host = new Panel(); host.Dock = DockStyle.Fill; host.BackColor = UI.Panel; host.Padding = new Padding(1); host.Margin = new Padding(0, 0, 0, UI.S(10));
        lvFind = MakeList(new string[] { "Stufe", "Bereich", "Befund" }, new int[] { UI.S(110), UI.S(140), UI.S(700) });
        lvTests = MakeList(new string[] { "Ergebnis", "Test", "Details" }, new int[] { UI.S(110), UI.S(320), UI.S(520) });
        lvBench = MakeList(new string[] { "Ergebnis", "Messung", "Wert", "Index", "Referenz", "Vergleich" }, new int[] { UI.S(110), UI.S(330), UI.S(160), UI.S(190), UI.S(95), UI.S(220) });
        lvBench.Tag = "bench";
        txtLog = new TextBox(); txtLog.Multiline = true; txtLog.ReadOnly = true; txtLog.ScrollBars = ScrollBars.Vertical; txtLog.WordWrap = true;
        txtLog.Dock = DockStyle.Fill; txtLog.Font = new Font("Consolas", 9.75f); txtLog.BorderStyle = BorderStyle.None;
        txtLog.BackColor = Color.FromArgb(18, 24, 34); txtLog.ForeColor = Color.FromArgb(214, 222, 235);
        Panel sensHost = new Panel(); sensHost.Dock = DockStyle.Fill; sensHost.BackColor = UI.Panel; sensHost.Padding = new Padding(10, 6, 10, 6);
        chartRun = new SensorChart(); chartRun.Dock = DockStyle.Fill; chartRun.WindowSec = 0;
        chartRun.Empty = "Kurven erscheinen hier während des Benchmarks und des Lasttests (Temperatur, Takt, Leistung von CPU und GPU).";
        lblRunSens = Lbl(" ", 9f, false, UI.Muted); lblRunSens.Dock = DockStyle.Top; lblRunSens.AutoSize = false; lblRunSens.Height = 22;
        sensHost.Controls.Add(chartRun); sensHost.Controls.Add(lblRunSens);
        host.Controls.Add(lvFind); host.Controls.Add(lvTests); host.Controls.Add(lvBench); host.Controls.Add(sensHost); host.Controls.Add(txtLog);
        lvTests.Visible = false; lvBench.Visible = false; sensHost.Visible = false; txtLog.Visible = false;
        tabs.SelectedChanged += delegate {
            lvFind.Visible = tabs.Selected == 0; lvTests.Visible = tabs.Selected == 1; lvBench.Visible = tabs.Selected == 2; sensHost.Visible = tabs.Selected == 3; txtLog.Visible = tabs.Selected == 4;
            host.BackColor = tabs.Selected == 4 ? txtLog.BackColor : UI.Panel;
        };
        t.Controls.Add(host, 0, 7);

        TableLayoutPanel foot = new TableLayoutPanel(); foot.Dock = DockStyle.Fill; foot.AutoSize = true; foot.ColumnCount = 2; foot.BackColor = UI.Bg;
        foot.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); foot.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        lblResult = Lbl("", 11f, true, UI.Text); lblResult.Anchor = AnchorStyles.Left; lblResult.AutoEllipsis = true;
        FlowLayoutPanel btns = new FlowLayoutPanel(); btns.AutoSize = true; btns.WrapContents = false; btns.BackColor = UI.Bg;
        btnStopWait = UI.Secondary("Test beenden"); btnSkipStep = UI.SkipStepButton(); btnCancel = UI.Secondary("Abbrechen");
        btnFolder = UI.Secondary("Ordner öffnen"); btnNew = UI.Secondary("Neuer Lauf"); btnKi = UI.Secondary("KI-Datei zeigen"); btnCopy = UI.Secondary("KI-Kurzfassung kopieren"); btnHtml = UI.Primary("Bericht öffnen");
        btnHtml.Margin = new Padding(8, 0, 0, 0); btnHtml.Padding = new Padding(14, 3, 14, 3); btnHtml.Font = new Font("Segoe UI Semibold", 9.75f);
        btns.Controls.Add(btnStopWait); btns.Controls.Add(btnSkipStep); btns.Controls.Add(btnCancel); btns.Controls.Add(btnNew); btns.Controls.Add(btnFolder); btns.Controls.Add(btnKi); btns.Controls.Add(btnCopy); btns.Controls.Add(btnHtml);
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
        // nur auf ausdrücklichen Klick in die Zwischenablage, damit nach dem Lauf nichts im Zwischenablageverlauf des PCs liegt
        btnCopy.Click += delegate {
            try { Clipboard.SetText(File.ReadAllText(kurzPath, Encoding.UTF8)); btnCopy.Text = "Kopiert"; }
            catch (Exception ex) { MessageBox.Show(this, "Kopieren fehlgeschlagen: " + ex.Message, "Leos Minibench"); }
        };
        btnNew.Click += delegate { ReloadDb(); runView.Visible = false; setupView.Visible = true; };
        p.Controls.Add(t);
        ApplyRunTips();
        return p;
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
                Color fg, bg; UI.Level(txt, out fg, out bg);
                using (Font f = new Font("Segoe UI Semibold", 8.25f))
                {
                    Size sz = TextRenderer.MeasureText(g, txt.ToUpperInvariant(), f);
                    int pillH = UI.S(20);
                    int pillW = sz.Width + UI.S(12);
                    RectangleF pill = new RectangleF(e.Bounds.X + UI.S(8), e.Bounds.Y + (e.Bounds.Height - pillH) / 2f, pillW, pillH);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    using (GraphicsPath gp = UI.Round(pill, UI.SF(10))) using (SolidBrush pb = new SolidBrush(bg)) g.FillPath(pb, gp);
                    g.SmoothingMode = SmoothingMode.None;
                    TextRenderer.DrawText(g, txt.ToUpperInvariant(), f, Rectangle.Round(pill), fg, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
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
        BringToFront2();
        BeginInvoke(new System.Windows.Forms.MethodInvoker(BringToFront2));
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
        btnHtml.Visible = false; btnFolder.Visible = false; btnNew.Visible = false; btnKi.Visible = false; btnCopy.Visible = false; btnCopy.Text = "KI-Kurzfassung kopieren";
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
            btnHtml.Visible = File.Exists(htmlPath); btnFolder.Visible = Directory.Exists(outDir); btnKi.Visible = File.Exists(kiPath); btnCopy.Visible = File.Exists(kurzPath);
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
        if (!running) return;
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
