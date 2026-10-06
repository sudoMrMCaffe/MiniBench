// Grafische Oberflaeche: Steuerelemente
public static class UI
{
    public static readonly Color Bg = Color.FromArgb(249, 249, 251);
    public static readonly Color Panel = Color.White;
    public static readonly Color Text = Color.FromArgb(28, 29, 31);
    public static readonly Color Muted = Color.FromArgb(95, 99, 104);
    public static readonly Color Line = Color.FromArgb(229, 231, 235);
    public static readonly Color Accent = Color.FromArgb(0, 103, 192);
    public static readonly Color AccentHover = Color.FromArgb(0, 90, 158);
    public static readonly Color AccentActive = Color.FromArgb(0, 79, 138);
    public static readonly Color AccentDark = Color.FromArgb(0, 79, 138);
    public static readonly Color AccentSoft = Color.FromArgb(235, 243, 251);
    public static readonly Color Header = Color.FromArgb(22, 30, 46);
    public static readonly Color Crit = Color.FromArgb(196, 43, 28), CritBg = Color.FromArgb(253, 231, 233);
    public static readonly Color Warn = Color.FromArgb(157, 93, 0), WarnBg = Color.FromArgb(255, 244, 206);
    public static readonly Color Info = Color.FromArgb(0, 103, 192), InfoBg = Color.FromArgb(235, 243, 251);
    public static readonly Color Ok = Color.FromArgb(16, 124, 65), OkBg = Color.FromArgb(223, 246, 221);
    public static readonly Color Skip = Color.FromArgb(95, 99, 104), SkipBg = Color.FromArgb(243, 244, 246);

    public static float DpiScale = 1.0f;

    static UI()
    {
        DpiScale = 1.0f;
        try
        {
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
            {
                if (g.DpiX > 0) DpiScale = g.DpiX / 96.0f;
            }
        }
        catch { DpiScale = 1.0f; }
        if (DpiScale <= 0.1f) DpiScale = 1.0f;
    }

    public static int S(int px)
    {
        return (int)Math.Round(px * DpiScale);
    }

    public static float SF(float px)
    {
        return px * DpiScale;
    }

    public static string SymbolFontFamily = ResolveSymbolFontFamily();
    static string ResolveSymbolFontFamily()
    {
        try
        {
            using (Font f = new Font("Segoe Fluent Icons", 9f))
            {
                if (f.Name == "Segoe Fluent Icons") return "Segoe Fluent Icons";
            }
        }
        catch { }
        try
        {
            using (Font f = new Font("Segoe MDL2 Assets", 9f))
            {
                if (f.Name == "Segoe MDL2 Assets") return "Segoe MDL2 Assets";
            }
        }
        catch { }
        return "Segoe UI Symbol";
    }

    public static Font SymbolFont(float size)
    {
        return new Font(SymbolFontFamily, size);
    }

    public const string IcoCpu = "\uE7F8";
    public const string IcoRam = "\uE7F4";
    public const string IcoGpu = "\uE790";
    public const string IcoDisk = "\uEDA2";
    public const string IcoDiag = "\uE9D9";
    public const string IcoWartung = "\uE90F";
    public const string IcoOpt = "\uE713";
    public const string IcoSens = "\uE950";
    public const string IcoDb = "\uE81E";
    public const string IcoChg = "\uE81C";
    public const string IcoFlame = "\uECAD";

    public static GraphicsPath Round(RectangleF r, float rad)
    {
        GraphicsPath p = new GraphicsPath();
        float d = Math.Max(1f, Math.Min(rad * 2, Math.Min(r.Width, r.Height)));
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    public static GraphicsPath Round(Rectangle r, float rad)
    {
        return Round(new RectangleF(r.X, r.Y, r.Width, r.Height), rad);
    }

    public static void Level(string lvl, out Color fg, out Color bg)
    {
        string l = (lvl ?? "").ToUpperInvariant();
        if (l == "KRITISCH" || l == "FEHLER") { fg = Crit; bg = CritBg; }
        else if (l == "WARNUNG") { fg = Warn; bg = WarnBg; }
        else if (l == "OK" || l == "REPARIERT") { fg = Ok; bg = OkBg; }
        else if (l == "INFO") { fg = Info; bg = InfoBg; }
        else { fg = Skip; bg = SkipBg; }
    }

    public static Button Primary(string text)
    {
        Button b = new Button(); b.Text = text; b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderSize = 0;
        b.BackColor = Accent; b.ForeColor = Color.White; b.FlatAppearance.MouseOverBackColor = AccentHover; b.FlatAppearance.MouseDownBackColor = AccentActive;
        b.Font = new Font("Segoe UI Semibold", 10.5f); b.AutoSize = true; b.Padding = new Padding(S(18), S(6), S(18), S(6)); b.Cursor = Cursors.Hand; b.UseVisualStyleBackColor = false;
        return b;
    }

    public static Button Secondary(string text)
    {
        Button b = new Button(); b.Text = text; b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderColor = Line;
        b.BackColor = Panel; b.ForeColor = Text; b.FlatAppearance.MouseOverBackColor = Color.FromArgb(243, 244, 246); b.FlatAppearance.MouseDownBackColor = Color.FromArgb(235, 237, 240);
        b.Font = new Font("Segoe UI", 9.75f); b.AutoSize = true; b.Padding = new Padding(S(10), S(3), S(10), S(3)); b.Margin = new Padding(S(8), 0, 0, 0); b.Cursor = Cursors.Hand; b.UseVisualStyleBackColor = false;
        return b;
    }

    public static Button SkipStepButton()
    {
        return Secondary("Diesen Schritt überspringen");
    }
}

// Moderner Windows 11 Toggle-Switch (Wintoys-Look)
public class ToggleSwitch : Control
{
    bool isChecked;
    bool hover;
    public event EventHandler CheckedChanged;

    public ToggleSwitch()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
        TabStop = true;
        Cursor = Cursors.Hand;
        Size = new Size(UI.S(44), UI.S(24));
        BackColor = Color.Transparent;
    }

    public bool Checked
    {
        get { return isChecked; }
        set
        {
            if (isChecked != value)
            {
                isChecked = value;
                Invalidate();
                if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty);
            }
        }
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
    protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
        {
            Focus();
            Checked = !Checked;
        }
        base.OnMouseClick(e);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Space)
        {
            Checked = !Checked;
            e.Handled = true;
        }
        base.OnKeyDown(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        int trackW = UI.S(38);
        int trackH = UI.S(20);
        int trackX = (Width - trackW) / 2;
        int trackY = (Height - trackH) / 2;
        RectangleF trackRect = new RectangleF(trackX, trackY, trackW, trackH);
        float rad = trackH / 2f;

        int knobD = UI.S(14);
        int knobY = trackY + (trackH - knobD) / 2;
        int knobX = isChecked ? (trackX + trackW - knobD - UI.S(3)) : (trackX + UI.S(3));

        using (GraphicsPath trackPath = UI.Round(trackRect, rad))
        {
            if (isChecked)
            {
                Color fillColor = hover ? UI.AccentHover : UI.Accent;
                using (SolidBrush b = new SolidBrush(fillColor)) g.FillPath(b, trackPath);
                using (Pen p = new Pen(fillColor, 1f)) g.DrawPath(p, trackPath);
            }
            else
            {
                Color borderColor = hover ? Color.FromArgb(118, 118, 118) : Color.FromArgb(209, 213, 219);
                using (SolidBrush b = new SolidBrush(Color.White)) g.FillPath(b, trackPath);
                using (Pen p = new Pen(borderColor, UI.SF(1.5f))) g.DrawPath(p, trackPath);
            }
        }

        // Subtiler Schatten des Knopfs
        RectangleF shadowRect = new RectangleF(knobX, knobY + UI.SF(0.5f), knobD, knobD);
        using (SolidBrush sb = new SolidBrush(Color.FromArgb(30, 0, 0, 0)))
        {
            g.FillEllipse(sb, shadowRect);
        }

        // Weißer Schieber-Knopf
        RectangleF knobRect = new RectangleF(knobX, knobY, knobD, knobD);
        using (SolidBrush kb = new SolidBrush(Color.White))
        {
            g.FillEllipse(kb, knobRect);
        }
        if (!isChecked)
        {
            using (Pen kp = new Pen(Color.FromArgb(118, 118, 118), 1f))
            {
                g.DrawEllipse(kp, knobRect);
            }
        }

        // Barrierefreies Fokus-Rechteck
        if (Focused)
        {
            Rectangle fRect = new Rectangle(trackX - UI.S(2), trackY - UI.S(2), trackW + UI.S(4), trackH + UI.S(4));
            using (Pen fp = new Pen(UI.Accent, 1f))
            {
                fp.DashStyle = DashStyle.Dot;
                g.DrawRectangle(fp, fRect);
            }
        }
    }
}

// Moderne Fluent-Kartenansicht (Wintoys-Look)
public class FluentCard : Control
{
    string title = "";
    string desc = "";
    string icon = "";
    bool hover;
    ToggleSwitch toggle;
    Button actionButton;
    public event EventHandler CheckedChanged;

    public FluentCard(string title, string desc, string icon = "")
    {
        this.title = title ?? "";
        this.desc = desc ?? "";
        this.icon = icon ?? "";
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        Cursor = Cursors.Hand;
        BackColor = UI.Panel;
        Size = new Size(UI.S(400), UI.S(64));
        Margin = new Padding(0, 0, 0, UI.S(8));

        toggle = new ToggleSwitch();
        toggle.Location = new Point(Width - toggle.Width - UI.S(16), (Height - toggle.Height) / 2);
        toggle.CheckedChanged += delegate
        {
            if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty);
            Invalidate();
        };
        Controls.Add(toggle);
    }

    public string Title { get { return title; } set { title = value ?? ""; Invalidate(); } }
    public string Description { get { return desc; } set { desc = value ?? ""; Invalidate(); } }
    public string Icon { get { return icon; } set { icon = value ?? ""; Invalidate(); } }
    public ToggleSwitch Toggle { get { return toggle; } }

    public Button ActionButton
    {
        get { return actionButton; }
        set
        {
            if (actionButton != null) Controls.Remove(actionButton);
            actionButton = value;
            if (actionButton != null)
            {
                if (toggle != null) toggle.Visible = false;
                Controls.Add(actionButton);
                LayoutControls();
            }
            else if (toggle != null)
            {
                toggle.Visible = true;
                LayoutControls();
            }
            Invalidate();
        }
    }

    public bool Checked
    {
        get { return toggle != null && toggle.Checked; }
        set { if (toggle != null) toggle.Checked = value; }
    }

    void LayoutControls()
    {
        if (actionButton != null)
        {
            actionButton.Location = new Point(Width - actionButton.Width - UI.S(16), (Height - actionButton.Height) / 2);
        }
        else if (toggle != null)
        {
            toggle.Location = new Point(Width - toggle.Width - UI.S(16), (Height - toggle.Height) / 2);
        }
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        LayoutControls();
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
        {
            Focus();
            if (actionButton == null && toggle != null && toggle.Visible)
            {
                toggle.Checked = !toggle.Checked;
            }
        }
        base.OnMouseClick(e);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Space && actionButton == null && toggle != null && toggle.Visible)
        {
            toggle.Checked = !toggle.Checked;
            e.Handled = true;
        }
        base.OnKeyDown(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        RectangleF r = new RectangleF(1, 1, Width - 3, Height - 3);
        Color bg = hover ? Color.FromArgb(250, 251, 253) : UI.Panel;
        Color border = hover ? Color.FromArgb(209, 213, 219) : UI.Line;

        using (GraphicsPath p = UI.Round(r, UI.SF(8)))
        {
            using (SolidBrush b = new SolidBrush(bg)) g.FillPath(b, p);
            using (Pen pen = new Pen(border, 1f)) g.DrawPath(pen, p);
        }

        int curX = UI.S(16);
        if (!String.IsNullOrEmpty(icon))
        {
            int icoSize = UI.S(28);
            using (Font ifont = UI.SymbolFont(UI.SF(14)))
            {
                Rectangle icoRect = new Rectangle(curX, (Height - icoSize) / 2, icoSize, icoSize);
                TextRenderer.DrawText(g, icon, ifont, icoRect, UI.Accent, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoClipping);
            }
            curX += icoSize + UI.S(10);
        }

        int rightBound = (actionButton != null && actionButton.Visible ? actionButton.Left : (toggle != null && toggle.Visible ? toggle.Left : Width)) - UI.S(12);
        int textW = Math.Max(UI.S(50), rightBound - curX);

        using (Font ft = new Font("Segoe UI Semibold", UI.SF(10f)))
        {
            Size tsz = TextRenderer.MeasureText(g, title, ft);
            int titleH = Math.Max(tsz.Height, UI.S(18));
            int startY = String.IsNullOrEmpty(desc) ? (Height - titleH) / 2 : UI.S(12);
            TextRenderer.DrawText(g, title, ft, new Rectangle(curX, startY, textW, titleH), UI.Text, TextFormatFlags.Left | TextFormatFlags.EndEllipsis);

            if (!String.IsNullOrEmpty(desc))
            {
                using (Font fd = new Font("Segoe UI", UI.SF(8.5f)))
                {
                    int descY = startY + titleH + UI.S(2);
                    TextRenderer.DrawText(g, desc, fd, new Rectangle(curX, descY, textW, Height - descY - UI.S(4)), UI.Muted, TextFormatFlags.Left | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis);
                }
            }
        }
    }
}

class FlatBar : Control
{
    int val; bool marquee; int pos; Timer anim;
    public Color Fill = UI.Accent;
    public FlatBar()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        anim = new Timer(); anim.Interval = 25; anim.Tick += delegate { pos = (pos + UI.S(8)) % Math.Max(1, Width + UI.S(160)); Invalidate(); };
    }
    public int Value { get { return val; } set { int v = Math.Max(0, Math.Min(100, value)); if (v != val) { val = v; Invalidate(); } } }
    public bool Marquee
    {
        get { return marquee; }
        set { if (marquee == value) return; marquee = value; if (value) anim.Start(); else anim.Stop(); Invalidate(); }
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
        RectangleF r = new RectangleF(0, 0, Width - 1, Height - 1);
        float rad = Height / 2f;
        using (GraphicsPath track = UI.Round(r, rad)) using (SolidBrush tb = new SolidBrush(Color.FromArgb(226, 231, 238))) g.FillPath(tb, track);
        using (GraphicsPath clip = UI.Round(r, rad))
        {
            g.SetClip(clip);
            using (SolidBrush fb = new SolidBrush(Fill))
            {
                if (marquee) g.FillRectangle(fb, pos - UI.S(160), 0, UI.S(160), Height);
                else if (val > 0) g.FillRectangle(fb, 0, 0, (Width - 1) * val / 100f, Height);
            }
            g.ResetClip();
        }
    }
}

// Eintrag der Modulnavigation: moderner Windows 11-Sidebar-Stil
class NavItem : Control
{
    bool sel, hover, chk;
    public string Title, Desc, Icon;
    public bool HasCheck = true;
    public event EventHandler Picked;
    public event EventHandler CheckedChanged;
    public NavItem(string title, string desc) : this(title, desc, "") { }
    public NavItem(string title, string desc, string icon)
    {
        Title = title; Desc = desc; Icon = icon ?? "";
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        Cursor = Cursors.Hand; Size = new Size(UI.S(226), UI.S(66)); Margin = new Padding(0, 0, 0, UI.S(6)); BackColor = UI.Bg;
    }
    public bool Selected { get { return sel; } set { sel = value; Invalidate(); } }
    public bool Checked
    {
        get { return chk; }
        set { if (chk == value) return; chk = value; Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); }
    }
    Rectangle Box { get { return new Rectangle(UI.S(14), (Height - UI.S(20)) / 2, UI.S(20), UI.S(20)); } }
    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseClick(MouseEventArgs e)
    {
        Focus();
        Rectangle hit = Box; hit.Inflate(UI.S(8), UI.S(8));
        if (HasCheck && hit.Contains(e.Location)) Checked = !Checked;
        if (Picked != null) Picked(this, e);
        base.OnMouseClick(e);
    }
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Space && HasCheck) Checked = !Checked;
        if (e.KeyCode == Keys.Enter && Picked != null) Picked(this, e);
        base.OnKeyDown(e);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        RectangleF r = new RectangleF(1, 1, Width - 3, Height - 3);
        Color fill = sel ? UI.AccentSoft : (hover ? Color.FromArgb(240, 243, 248) : UI.Panel);
        using (GraphicsPath p = UI.Round(r, UI.SF(6)))
        {
            using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
            using (Pen pen = new Pen(sel ? UI.Accent : (hover ? Color.FromArgb(209, 213, 219) : UI.Line), sel ? UI.SF(1.5f) : UI.SF(1f))) g.DrawPath(pen, p);
        }

        // Bei Auswahl: Links ein 3 px breiter, abgerundeter blauer Akzentbalken
        if (sel)
        {
            int barH = Height - UI.S(20);
            RectangleF barR = new RectangleF(UI.S(3), (Height - barH) / 2f, UI.S(3), barH);
            using (GraphicsPath bp = UI.Round(barR, UI.SF(1.5f)))
            using (SolidBrush bb = new SolidBrush(UI.Accent))
                g.FillPath(bb, bp);
        }

        int x = UI.S(14);
        if (HasCheck)
        {
            Rectangle bx = Box;
            using (GraphicsPath bp = UI.Round(bx, UI.SF(5)))
            {
                using (SolidBrush bb = new SolidBrush(chk ? UI.Accent : UI.Panel)) g.FillPath(bb, bp);
                using (Pen bpen = new Pen(chk ? UI.Accent : Color.FromArgb(160, 170, 185), UI.SF(1.5f))) g.DrawPath(bpen, bp);
            }
            if (chk) using (Pen ck = new Pen(Color.White, UI.SF(2.4f))) { ck.StartCap = LineCap.Round; ck.EndCap = LineCap.Round; g.DrawLines(ck, new Point[] { new Point(bx.X + UI.S(5), bx.Y + UI.S(10)), new Point(bx.X + UI.S(9), bx.Y + UI.S(14)), new Point(bx.X + UI.S(15), bx.Y + UI.S(6)) }); }
            x = bx.Right + UI.S(10);
        }

        if (!String.IsNullOrEmpty(Icon))
        {
            int icoSize = UI.S(24);
            int icoY = (Height - icoSize) / 2;
            using (Font ifont = UI.SymbolFont(UI.SF(13)))
            {
                Rectangle icoR = new Rectangle(x, icoY, icoSize, icoSize);
                TextRenderer.DrawText(g, Icon, ifont, icoR, sel ? UI.Accent : UI.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoClipping);
            }
            x += icoSize + UI.S(8);
        }

        using (Font ft = new Font("Segoe UI Semibold", UI.SF(10f)))
        {
            Size tsz = TextRenderer.MeasureText(g, Title, ft);
            int th = Math.Max(tsz.Height, UI.S(18));
            int startY = String.IsNullOrEmpty(Desc) ? (Height - th) / 2 : UI.S(12);
            TextRenderer.DrawText(g, Title, ft, new Rectangle(x, startY, Width - x - UI.S(8), th), sel ? UI.AccentDark : UI.Text, TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
            if (!String.IsNullOrEmpty(Desc))
            {
                using (Font fs = new Font("Segoe UI", UI.SF(8.5f)))
                {
                    int dy = startY + th + UI.S(2);
                    TextRenderer.DrawText(g, Desc, fs, new Rectangle(x, dy, Width - x - UI.S(8), Height - dy - UI.S(4)), UI.Muted, TextFormatFlags.Left | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis);
                }
            }
        }
    }
}

class StatCard : Control
{
    public string Caption; public Color Accent; int count;
    public StatCard(string caption, Color accent)
    {
        Caption = caption; Accent = accent;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Size = new Size(UI.S(170), UI.S(72)); Margin = new Padding(0, 0, UI.S(12), 0); BackColor = UI.Bg;
    }
    public int Count { get { return count; } set { count = value; Invalidate(); } }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
        RectangleF r = new RectangleF(0.5f, 0.5f, Width - 2, Height - 2);
        using (GraphicsPath p = UI.Round(r, UI.SF(8)))
        {
            using (SolidBrush b = new SolidBrush(UI.Panel)) g.FillPath(b, p);
            using (Pen pen = new Pen(UI.Line)) g.DrawPath(pen, p);
            g.SetClip(p);
            using (SolidBrush a = new SolidBrush(Accent)) g.FillRectangle(a, 0, 0, UI.S(5), Height);
            g.ResetClip();
        }
        using (Font fn = new Font("Segoe UI Semibold", UI.SF(19f)))
        {
            Size numSz = TextRenderer.MeasureText(g, count.ToString(), fn);
            int numY = UI.S(6);
            TextRenderer.DrawText(g, count.ToString(), fn, new Point(UI.S(16), numY), count > 0 ? Accent : UI.Muted);
            using (Font fc = new Font("Segoe UI", UI.SF(8.5f)))
            {
                int capY = numY + numSz.Height - UI.S(2);
                TextRenderer.DrawText(g, Caption, fc, new Rectangle(UI.S(16), capY, Width - UI.S(20), Height - capY), UI.Muted, TextFormatFlags.Left | TextFormatFlags.WordBreak);
            }
        }
    }
}

class TabStrip : Control
{
    public List<string> Items = new List<string>();
    int selected;
    public event EventHandler SelectedChanged;
    public TabStrip()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Height = UI.S(38); Cursor = Cursors.Hand; BackColor = UI.Bg;
    }
    public int Selected { get { return selected; } set { selected = value; Invalidate(); if (SelectedChanged != null) SelectedChanged(this, EventArgs.Empty); } }
    public void SetText(int i, string t) { if (Items[i] == t) return; Items[i] = t; Invalidate(); }
    Rectangle ItemRect(Graphics g, int i, Font f)
    {
        int x = 0;
        int pad = UI.S(28);
        for (int k = 0; k <= i; k++)
        {
            int w = TextRenderer.MeasureText(g, Items[k], f).Width + pad;
            if (k == i) return new Rectangle(x, 0, w, Height);
            x += w + UI.S(4);
        }
        return Rectangle.Empty;
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        using (Pen line = new Pen(UI.Line)) g.DrawLine(line, 0, Height - 1, Width, Height - 1);
        int barH = UI.S(2);
        int barPad = UI.S(8);
        for (int i = 0; i < Items.Count; i++)
        {
            using (Font f = new Font(i == selected ? "Segoe UI Semibold" : "Segoe UI", UI.SF(9.5f)))
            {
                Rectangle r = ItemRect(g, i, f);
                TextRenderer.DrawText(g, Items[i], f, r, i == selected ? UI.Accent : UI.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                if (i == selected) using (SolidBrush b = new SolidBrush(UI.Accent)) g.FillRectangle(b, r.X + barPad, Height - barH, r.Width - (barPad * 2), barH);
            }
        }
    }
    protected override void OnMouseClick(MouseEventArgs e)
    {
        using (Graphics g = CreateGraphics())
            for (int i = 0; i < Items.Count; i++)
                using (Font f = new Font(i == selected ? "Segoe UI Semibold" : "Segoe UI", UI.SF(9.5f)))
                    if (ItemRect(g, i, f).Contains(e.Location)) { Selected = i; break; }
        base.OnMouseClick(e);
    }
}

// Kurven der Leitwerte (SENSLEAD): drei Felder übereinander für Temperatur, Takt und Leistung, je CPU, GPU und Prozessorgrafik.
// WindowSec > 0 zeigt nur die letzten Sekunden (Live-Seite), 0 den ganzen Verlauf (Lasttest).
// Neuzeichnen gebündelt: Add() merkt nur vor, Flush() (Zeitgeber der Oberfläche) zeichnet höchstens einmal je Takt.
class SensorChart : Control
{
    // Spalten: 0 Zeit, 1 CPU °C, 2 CPU MHz (Task-Manager), 3 CPU W, 4 GPU °C, 5 GPU MHz, 6 GPU W, 7 Lüfter, 8 CPU-Last,
    //          9 höchster Kerntakt, 10 iGPU °C, 11 iGPU MHz, 12 iGPU W, 13 Bilder/s GPU, 14 Bilder/s iGPU (Rendertest, ab v2.6)
    const int Cols = 15;
    bool hasFps;
    List<double[]> rows = new List<double[]>();
    bool dirty;
    public int WindowSec = 600;
    public double CpuLimit = double.NaN, GpuLimit = double.NaN, TjMax = double.NaN;
    public string Empty = "Noch keine Messwerte.";
    static readonly Color CpuColor = Color.FromArgb(37, 99, 235), CoreColor = Color.FromArgb(125, 160, 245), GpuColor = Color.FromArgb(194, 65, 12), IGpuColor = Color.FromArgb(202, 138, 4);
    struct Series { public int Col; public Color Color; public string Label; public bool Dash; public Series(int c, Color k, string l, bool d) { Col = c; Color = k; Label = l; Dash = d; } }
    public SensorChart()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        BackColor = UI.Panel;
    }
    public int Count { get { return rows.Count; } }
    public void Clear() { rows.Clear(); tOffset = 0; hasFps = false; CpuLimit = double.NaN; GpuLimit = double.NaN; TjMax = double.NaN; dirty = false; Invalidate(); }
    static double D(string s)
    {
        double v; return double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : double.NaN;
    }
    // p wie @@SENSLEAD|t|cpuT|cpuMHz|cpuW|gpuT|gpuMHz|gpuW|fan|cpuLoad|coreMax|igpuT|igpuMHz|igpuW (p[0] = "SENSLEAD")
    // Zeitversatz (ab v2.7): Benchmark und Lasttest zählen ihre Sekunden je ab 0. Springt die Zeit zurück, läuft die
    // Kurve hinter dem letzten Punkt weiter, statt sich zu überlagern.
    double tOffset;
    public double[] Add(string[] p)
    {
        double[] r = new double[Cols];
        for (int i = 0; i < Cols; i++) r[i] = (i + 1 < p.Length) ? D(p[i + 1]) : double.NaN;
        if (double.IsNaN(r[0])) return r;
        if (rows.Count > 0)
        {
            double lastT = rows[rows.Count - 1][0];
            if (r[0] + tOffset < lastT - 0.5) tOffset = lastT + 2 - r[0];
        }
        r[0] += tOffset;
        if (!double.IsNaN(r[13]) || !double.IsNaN(r[14])) hasFps = true;
        rows.Add(r);
        if (rows.Count > 30000) rows.RemoveRange(0, rows.Count - 30000);
        dirty = true;
        return r;
    }
    // vom Zeitgeber der Oberfläche aufgerufen: neu zeichnen, wenn seit dem letzten Mal Werte dazukamen
    public void Flush() { if (dirty) { dirty = false; Invalidate(); } }
    public void SetLimits(string[] p)
    {
        CpuLimit = p.Length > 1 ? D(p[1]) : double.NaN; GpuLimit = p.Length > 2 ? D(p[2]) : double.NaN; TjMax = p.Length > 3 ? D(p[3]) : double.NaN;
        Invalidate();
    }
    public double[] Last { get { return rows.Count > 0 ? rows[rows.Count - 1] : null; } }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(BackColor);
        using (Pen bp = new Pen(UI.Line)) g.DrawRectangle(bp, 0, 0, Width - 1, Height - 1);
        if (rows.Count < 1) { using (Font f = new Font("Segoe UI", 9.75f)) TextRenderer.DrawText(g, Empty, f, ClientRectangle, UI.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak); return; }
        double tMax = rows[rows.Count - 1][0];
        double tMin = WindowSec > 0 ? Math.Max(0, tMax - WindowSec) : rows[0][0];
        if (tMax - tMin < 10) tMax = tMin + 10;
        int n = hasFps ? 4 : 3;
        int h = (Height - 8) / n;
        DrawPanel(g, new Rectangle(0, 4, Width, h), "Temperatur", "°C", new Series[] { new Series(1, CpuColor, "CPU", false), new Series(4, GpuColor, "GPU", false), new Series(10, IGpuColor, "iGPU", true) }, tMin, tMax, true);
        DrawPanel(g, new Rectangle(0, 4 + h, Width, h), "Takt", "MHz", new Series[] { new Series(2, CpuColor, "CPU", false), new Series(9, CoreColor, "höchster Kern", true), new Series(5, GpuColor, "GPU", false), new Series(11, IGpuColor, "iGPU", true) }, tMin, tMax, false);
        DrawPanel(g, new Rectangle(0, 4 + 2 * h, Width, h), "Leistung", "W", new Series[] { new Series(3, CpuColor, "CPU", false), new Series(6, GpuColor, "GPU", false), new Series(12, IGpuColor, "iGPU", true) }, tMin, tMax, false);
        if (hasFps) DrawPanel(g, new Rectangle(0, 4 + 3 * h, Width, h), "Rendertest", "Bilder/s", new Series[] { new Series(13, GpuColor, "GPU", false), new Series(14, IGpuColor, "iGPU", true) }, tMin, tMax, false);
    }

    void DrawPanel(Graphics g, Rectangle r, string title, string unit, Series[] ser, double tMin, double tMax, bool limits)
    {
        Rectangle plot = new Rectangle(r.X + 58, r.Y + 22, r.Width - 58 - 14, r.Height - 22 - 18);
        if (plot.Width < 40 || plot.Height < 20) return;
        double lo = double.MaxValue, hi = double.MinValue; bool any = false;
        foreach (double[] row in rows)
        {
            if (row[0] < tMin) continue;
            foreach (Series sr in ser) { double v = row[sr.Col]; if (!double.IsNaN(v)) { lo = Math.Min(lo, v); hi = Math.Max(hi, v); any = true; } }
        }
        if (limits)
        {
            foreach (double v in new double[] { CpuLimit, GpuLimit, TjMax }) if (!double.IsNaN(v) && v > 0 && any) { hi = Math.Max(hi, v); }
        }
        if (unit == "Bilder/s") lo = 0;
        if (unit == "%") { lo = 0; if (hi < 100) hi = 100; }
        using (Font ft = new Font("Segoe UI Semibold", 9f)) TextRenderer.DrawText(g, title + " (" + unit + ")", ft, new Point(r.X + 8, r.Y + 2), UI.Text);
        double[] last = rows[rows.Count - 1];
        using (Font fl = new Font("Segoe UI", 8.75f))
        {
            int x = r.X + 140;
            foreach (Series sr in ser)
            {
                string lv = Fmt(last[sr.Col], unit);
                if (lv.Length == 0) continue;
                string txt = sr.Label + " " + lv;
                using (SolidBrush b = new SolidBrush(sr.Color)) g.FillRectangle(b, x, r.Y + 7, 10, 10);
                TextRenderer.DrawText(g, txt, fl, new Point(x + 14, r.Y + 3), UI.Text);
                x += 22 + TextRenderer.MeasureText(txt, fl).Width;
            }
            if (limits && !double.IsNaN(CpuLimit) && CpuLimit > 0) TextRenderer.DrawText(g, "Abbruch CPU " + CpuLimit.ToString("0") + " °C" + (!double.IsNaN(GpuLimit) && GpuLimit > 0 ? ", GPU " + GpuLimit.ToString("0") + " °C" : ""), fl, new Point(x + 4, r.Y + 3), UI.Crit);
        }
        if (!any) { using (Font f = new Font("Segoe UI", 8.75f)) TextRenderer.DrawText(g, "kein Wert verfügbar", f, plot, UI.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter); return; }
        double span = hi - lo; if (span < 1) span = 1;
        double step = NiceStep(span / 3);
        double y0 = Math.Floor(lo / step) * step, y1 = Math.Ceiling(hi / step) * step; if (y1 <= y0) y1 = y0 + step;
        using (Pen grid = new Pen(Color.FromArgb(236, 239, 243)))
        using (Font fa = new Font("Segoe UI", 7.75f))
        {
            for (double v = y0; v <= y1 + step / 1000; v += step)
            {
                float y = (float)(plot.Bottom - (v - y0) / (y1 - y0) * plot.Height);
                g.DrawLine(grid, plot.Left, y, plot.Right, y);
                TextRenderer.DrawText(g, v.ToString("0"), fa, new Rectangle(r.X, (int)y - 8, 52, 16), UI.Muted, TextFormatFlags.Right | TextFormatFlags.VerticalCenter);
            }
            double ts = 10; foreach (double c in new double[] { 10, 30, 60, 120, 300, 600, 900, 1800, 3600 }) { ts = c; if ((tMax - tMin) / c <= 8) break; }
            for (double t = Math.Ceiling(tMin / ts) * ts; t <= tMax; t += ts)
            {
                float x = (float)(plot.Left + (t - tMin) / (tMax - tMin) * plot.Width);
                g.DrawLine(grid, x, plot.Top, x, plot.Bottom);
                string lab = ts >= 60 ? ((int)(t / 60)).ToString() + " min" : ((int)t).ToString() + " s";
                TextRenderer.DrawText(g, lab, fa, new Rectangle((int)x - 30, plot.Bottom + 1, 60, 16), UI.Muted, TextFormatFlags.HorizontalCenter);
            }
        }
        if (limits)
        {
            DrawLimit(g, plot, CpuLimit, y0, y1, UI.Crit, DashStyle.Dash);
            DrawLimit(g, plot, GpuLimit, y0, y1, Color.FromArgb(194, 65, 12), DashStyle.Dash);
            if (!double.IsNaN(TjMax) && TjMax != CpuLimit) DrawLimit(g, plot, TjMax, y0, y1, UI.Warn, DashStyle.Dot);
        }
        for (int i = ser.Length - 1; i >= 0; i--) DrawSeries(g, plot, ser[i].Col, tMin, tMax, y0, y1, ser[i].Color, ser[i].Dash);
    }

    static void DrawLimit(Graphics g, Rectangle plot, double v, double y0, double y1, Color c, DashStyle ds)
    {
        if (double.IsNaN(v) || v <= 0 || v < y0 || v > y1) return;
        float y = (float)(plot.Bottom - (v - y0) / (y1 - y0) * plot.Height);
        using (Pen p = new Pen(c, 1.5f)) { p.DashStyle = ds; g.DrawLine(p, plot.Left, y, plot.Right, y); }
    }

    void DrawSeries(Graphics g, Rectangle plot, int k, double tMin, double tMax, double y0, double y1, Color c, bool dash)
    {
        List<PointF> pts = new List<PointF>();
        using (Pen p = new Pen(c, dash ? 1.6f : 2f))
        {
            p.LineJoin = LineJoin.Round;
            if (dash) p.DashStyle = DashStyle.Dash;
            foreach (double[] row in rows)
            {
                if (row[0] < tMin) continue;
                if (double.IsNaN(row[k])) { if (pts.Count > 1) g.DrawLines(p, pts.ToArray()); pts.Clear(); continue; }
                pts.Add(new PointF((float)(plot.Left + (row[0] - tMin) / (tMax - tMin) * plot.Width), (float)(plot.Bottom - (row[k] - y0) / (y1 - y0) * plot.Height)));
            }
            if (pts.Count > 1) g.DrawLines(p, pts.ToArray());
            else if (pts.Count == 1) using (SolidBrush b = new SolidBrush(c)) g.FillEllipse(b, pts[0].X - 2, pts[0].Y - 2, 4, 4);
        }
    }

    static double NiceStep(double raw)
    {
        if (raw <= 0) return 1;
        double mag = Math.Pow(10, Math.Floor(Math.Log10(raw)));
        foreach (double f in new double[] { 1, 2, 2.5, 5, 10 }) if (f * mag >= raw) return f * mag;
        return 10 * mag;
    }

    public static string Fmt(double v, string unit)
    {
        if (double.IsNaN(v)) return "";
        return v.ToString(unit == "W" ? "0.0" : "0", CultureInfo.GetCultureInfo("de-DE")) + " " + unit;
    }
}
