// Vergleichsdatenbank und Systemvergleich (Teilklasse DiagGui)
public partial class DiagGui
{
    class DbItemComparer : System.Collections.IComparer
    {
        int col;
        bool asc;
        public DbItemComparer(int column, bool ascending) { col = column; asc = ascending; }
        public int Column { get { return col; } }
        public bool Ascending { get { return asc; } }

        public int Compare(object x, object y)
        {
            ListViewItem itemX = x as ListViewItem;
            ListViewItem itemY = y as ListViewItem;
            if (itemX == null || itemY == null) return 0;
            DbEntry dx = itemX.Tag as DbEntry;
            DbEntry dy = itemY.Tag as DbEntry;
            if (dx == null || dy == null) return 0;

            int res = 0;
            switch (col)
            {
                case 0:
                    res = String.Compare(dx.DisplayName, dy.DisplayName, StringComparison.CurrentCultureIgnoreCase);
                    break;
                case 1:
                    res = String.Compare(dx.Datum, dy.Datum, StringComparison.Ordinal);
                    break;
                case 2:
                    res = dx.OverallScore.CompareTo(dy.OverallScore);
                    break;
                case 3:
                    res = String.Compare(dx.Cpu, dy.Cpu, StringComparison.CurrentCultureIgnoreCase);
                    break;
                case 4:
                    res = String.Compare(dx.Gpu, dy.Gpu, StringComparison.CurrentCultureIgnoreCase);
                    break;
                case 5:
                    res = String.Compare(dx.Ram, dy.Ram, StringComparison.CurrentCultureIgnoreCase);
                    break;
                case 6:
                    res = dx.Get("CPU|MT").CompareTo(dy.Get("CPU|MT"));
                    break;
                case 7:
                    res = dx.Get("RAM|Lesen").CompareTo(dy.Get("RAM|Lesen"));
                    break;
                case 8:
                    double gx = dx.Get("GPU|REND") > 0 ? dx.Get("GPU|REND") : dx.Get("GPU|VMB");
                    double gy = dy.Get("GPU|REND") > 0 ? dy.Get("GPU|REND") : dy.Get("GPU|VMB");
                    res = gx.CompareTo(gy);
                    break;
                case 9:
                    res = String.Compare(dx.Befunde, dy.Befunde, StringComparison.OrdinalIgnoreCase);
                    break;
                default:
                    string tx = itemX.SubItems.Count > col ? itemX.SubItems[col].Text : "";
                    string ty = itemY.SubItems.Count > col ? itemY.SubItems[col].Text : "";
                    res = String.Compare(tx, ty, StringComparison.CurrentCultureIgnoreCase);
                    break;
            }
            return asc ? res : -res;
        }
    }

    int dbSortCol = -1;
    bool dbSortAsc = true;
    Button btnRename;
    Button btnCompare, btnDashboard, btnDelete;

    void OnDbColumnClick(object sender, ColumnClickEventArgs e)
    {
        if (e.Column == dbSortCol)
        {
            dbSortAsc = !dbSortAsc;
        }
        else
        {
            dbSortCol = e.Column;
            dbSortAsc = (e.Column == 0 || e.Column == 3 || e.Column == 4 || e.Column == 5);
        }
        lvDb.ListViewItemSorter = new DbItemComparer(dbSortCol, dbSortAsc);
        lvDb.Sort();
    }

    string PromptInput(string prompt, string title, string defaultValue)
    {
        Form dlg = new Form();
        dlg.Text = title;
        dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
        dlg.MaximizeBox = false; dlg.MinimizeBox = false;
        dlg.StartPosition = FormStartPosition.CenterParent;
        dlg.ClientSize = new Size(UI.S(440), UI.S(145));
        dlg.BackColor = UI.Bg; dlg.Font = new Font("Segoe UI", 9f);

        Label lbl = new Label();
        lbl.Text = prompt;
        lbl.Location = new Point(UI.S(16), UI.S(14));
        lbl.Size = new Size(UI.S(408), UI.S(30));

        TextBox tb = new TextBox();
        tb.Text = defaultValue ?? "";
        tb.Location = new Point(UI.S(16), UI.S(48));
        tb.Size = new Size(UI.S(408), UI.S(24));
        tb.BackColor = UI.Panel;
        tb.ForeColor = UI.Text;
        tb.BorderStyle = BorderStyle.FixedSingle;

        Button btnOk = UI.Primary("Speichern");
        btnOk.Location = new Point(UI.S(226), UI.S(92));
        btnOk.Size = new Size(UI.S(95), UI.S(32));
        btnOk.DialogResult = DialogResult.OK;

        Button btnCancel = UI.Secondary("Abbrechen");
        btnCancel.Location = new Point(UI.S(328), UI.S(92));
        btnCancel.Size = new Size(UI.S(96), UI.S(32));
        btnCancel.DialogResult = DialogResult.Cancel;

        dlg.Controls.Add(lbl); dlg.Controls.Add(tb); dlg.Controls.Add(btnOk); dlg.Controls.Add(btnCancel);
        dlg.AcceptButton = btnOk; dlg.CancelButton = btnCancel;

        return dlg.ShowDialog(this) == DialogResult.OK ? tb.Text : null;
    }

    void RenameSelectedEntry()
    {
        DbEntry target = null;
        ListViewItem lvi = null;
        if (lvDb != null && lvDb.SelectedItems.Count == 1) { lvi = lvDb.SelectedItems[0]; target = (DbEntry)lvi.Tag; }
        else if (lvDb != null && lvDb.CheckedItems.Count == 1) { lvi = lvDb.CheckedItems[0]; target = (DbEntry)lvi.Tag; }
        if (target == null) return;

        string currentName = target.DisplayName;
        string newName = PromptInput("Anzeigename für dieses System eingeben (z. B. Vor Reinigung oder Neuer Treiber):\r\nRechnername bleibt: " + target.Computer, "Systemnamen bearbeiten", currentName);
        if (newName == null) return;
        newName = newName.Trim();
        if (newName.Length == 0 || newName == currentName) return;

        target.Name = newName;
        if (File.Exists(target.Path))
        {
            try
            {
                string text = File.ReadAllText(target.Path, Encoding.UTF8);
                string escaped = newName.Replace("\\", "\\\\").Replace("\"", "\\\"");
                if (System.Text.RegularExpressions.Regex.IsMatch(text, @"(?m)^\s*""Name""\s*:"))
                {
                    text = System.Text.RegularExpressions.Regex.Replace(text, @"(?m)^(\s*""Name""\s*:\s*)"".*?""(,?)", "$1\"" + escaped + "\"$2");
                }
                else
                {
                    int idx = text.IndexOf('{');
                    if (idx >= 0) text = text.Substring(0, idx + 1) + "\r\n  \"Name\": \"" + escaped + "\"," + text.Substring(idx + 1);
                }
                File.WriteAllText(target.Path, text, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Fehler beim Speichern des Namens: " + ex.Message, "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
        }
        if (lvi != null)
        {
            lvi.SubItems[0].Text = target.DisplayName;
            lvi.ToolTipText = target.DisplayName + (target.Disk.Length > 0 ? "\r\n" + target.Disk : "") + (target.HasBench ? "" : "\r\n(ohne Benchmark-Werte)");
        }
    }

    Control BuildDbPage()
    {
        Panel f = new Panel(); f.Dock = DockStyle.Fill; f.BackColor = UI.Panel;
        FlowLayoutPanel top = Page("Vergleichsdatenbank", "Jeder Lauf wird als System gespeichert. Hier lassen sich bereits geprüfte Systeme ohne neuen Benchmark im interaktiven Multi-System-Dashboard gegenüberstellen: Systeme anhaken und \"Im Dashboard vergleichen\" klicken. Ältere Ausgabeordner lassen sich importieren. Ein Klick auf die Spaltenköpfe sortiert die Einträge.", -1);
        top.Dock = DockStyle.Top;
        top.AutoSize = true;
        lblDbPath = Lbl("Datenbank: " + (dbDir.Length > 0 ? dbDir : "(nicht verfügbar)"), 9f, false, UI.Muted); lblDbPath.Margin = new Padding(UI.S(4), 0, UI.S(4), UI.S(4)); top.Controls.Add(lblDbPath);

        FlowLayoutPanel topTools = Row();
        topTools.Margin = new Padding(UI.S(4), 0, UI.S(4), UI.S(8));
        Button imp = UI.Secondary("Importieren ..."); imp.Margin = new Padding(0); imp.Click += delegate { ImportFolder(); };
        Tip(imp, "Übernimmt Benchmark-Werte aus Ausgabeordnern früherer Läufe in die Datenbank (auch von PC-Diagnose).");
        btnDbClean = UI.Secondary("Aufräumen ..."); btnDbClean.Margin = new Padding(UI.S(8), 0, 0, 0); btnDbClean.Click += delegate { CleanData(); }; btnDbClean.Enabled = dataDir.Length > 0;
        Tip(btnDbClean, "Räumt nicht vergleichbare oder abgebrochene Läufe auf und verschiebt sie ins Archiv.");
        Button rel = UI.Secondary("Aktualisieren"); rel.Margin = new Padding(UI.S(8), 0, 0, 0); rel.Click += delegate { ReloadDb(); };
        Tip(rel, "Liest Datenbank und Referenz neu ein.");
        Button open = UI.Secondary("Datenordner"); open.Margin = new Padding(UI.S(8), 0, 0, 0); open.Click += delegate { if (dataDir.Length > 0) OpenShell(dataDir); };
        Tip(open, "Öffnet den Datenordner (Berichte, Datenbank, Tools, Archiv).");
        Button btnNas = UI.Secondary("Netzlaufwerk / NAS ..."); btnNas.Margin = new Padding(UI.S(8), 0, 0, 0); btnNas.Click += delegate { ShowConnectNasDialog(); };
        Tip(btnNas, "Verbindet ein Netzlaufwerk oder NAS für Berichte und Vergleichsdatenbank.");
        topTools.Controls.Add(imp); topTools.Controls.Add(btnDbClean); topTools.Controls.Add(rel); topTools.Controls.Add(open); topTools.Controls.Add(btnNas);
        top.Controls.Add(topTools);

        FlowLayoutPanel bottom = new FlowLayoutPanel(); bottom.FlowDirection = FlowDirection.TopDown; bottom.WrapContents = false; bottom.AutoSize = true; bottom.BackColor = UI.Panel; bottom.Dock = DockStyle.Bottom;
        Label hint = Lbl("Doppelklick öffnet den Bericht des Laufs. Graue Einträge enthalten keine Benchmark-Werte. Klick auf Spaltenkopf sortiert die Tabelle.", 8.75f, false, UI.Muted); hint.Margin = new Padding(UI.S(4), UI.S(4), UI.S(4), 0); bottom.Controls.Add(hint);
        FlowLayoutPanel b = Row(); b.Margin = new Padding(UI.S(4), UI.S(10), 0, 0);
        // Hinweis: Der statische Bericht "Vergleichen (Klassisch)" ist ab v3.32 vollständig durch das interaktive Dashboard abgelöst
        btnDashboard = UI.Primary("Interaktives Dashboard"); btnDashboard.Margin = new Padding(0); btnDashboard.Padding = new Padding(UI.S(14), UI.S(3), UI.S(14), UI.S(3)); btnDashboard.Font = new Font("Segoe UI Semibold", 9.75f);
        btnDashboard.Click += delegate { OpenDashboard(); };
        Tip(btnDashboard, "Öffnet das interaktive Multi-System-Dashboard im Browser mit den angehakten Systemen.");
        btnRename = UI.Secondary("Name ändern ..."); btnRename.Margin = new Padding(UI.S(8), 0, 0, 0);
        btnRename.Click += delegate { RenameSelectedEntry(); };
        btnRename.Enabled = false;
        Tip(btnRename, "Bearbeitet den Anzeigenamen des ausgewählten Systems (z. B. für Notizen wie Vor Reinigung oder Neuer Treiber), ohne die Hardware-Erkennung zu verändern.");
        btnDelete = UI.Secondary("Entfernen"); btnDelete.Margin = new Padding(UI.S(8), 0, 0, 0); btnDelete.Click += delegate { DeleteSelected(); };
        Tip(btnDelete, "Löscht die ausgewählten Systeme aus der Vergleichsdatenbank.");
        b.Controls.Add(btnDashboard); b.Controls.Add(btnRename); b.Controls.Add(btnDelete); bottom.Controls.Add(b);
        lblDbClean = Lbl(DatenpflegeInfo.Length > 0 ? DatenpflegeInfo : "Lasttests vor v2.67 (nicht vergleichbar), abgebrochene und kurze Läufe verschiebt die Datenpflege beim Start nach Minibench-Daten\\Archiv.", 8.75f, false, UI.Muted);
        lblDbClean.Margin = new Padding(UI.S(4), UI.S(8), UI.S(4), 0); bottom.Controls.Add(lblDbClean);
        bottom.Resize += delegate { lblDbClean.MaximumSize = new Size(Math.Max(UI.S(200), bottom.ClientSize.Width - UI.S(10)), 0); };

        lvDb = new ListView(); lvDb.View = View.Details; lvDb.FullRowSelect = true; lvDb.CheckBoxes = true; lvDb.Dock = DockStyle.Fill; lvDb.BorderStyle = BorderStyle.FixedSingle; lvDb.HideSelection = false; lvDb.ShowItemToolTips = true;
        EnableDarkListView(lvDb);
        string[] cols = new string[] { "System", "Datum", "Gesamt", "Prozessor", "Grafik", "Arbeitsspeicher", "CPU Mehrkern", "RAM Lesen", "GPU", "Befunde K/W/I" };
        int[] w = new int[] { UI.S(135), UI.S(95), UI.S(65), UI.S(125), UI.S(115), UI.S(105), UI.S(80), UI.S(70), UI.S(70), UI.S(62) };
        for (int i = 0; i < cols.Length; i++) lvDb.Columns.Add(cols[i], w[i]);
        lvDb.Resize += delegate {
            int rem = lvDb.ClientSize.Width;
            for (int i = 0; i < lvDb.Columns.Count - 1; i++) rem -= lvDb.Columns[i].Width;
            if (rem > UI.S(60)) lvDb.Columns[lvDb.Columns.Count - 1].Width = rem - 2;
        };
        lvDb.DoubleClick += delegate { if (lvDb.SelectedItems.Count > 0) OpenEntry((DbEntry)lvDb.SelectedItems[0].Tag); };
        lvDb.ItemChecked += delegate { UpdateDbButtons(); };
        lvDb.SelectedIndexChanged += delegate { UpdateDbButtons(); };
        lvDb.ColumnClick += OnDbColumnClick;
        Tip(lvDb, "Vergleichsdatenbank aller gespeicherten Systeme. Ein Klick auf die Spaltenköpfe sortiert nach Datum, Gesamtwertung, CPU oder GPU.");

        ContextMenu cm = new ContextMenu();
        MenuItem miDashboard = new MenuItem("Im Dashboard vergleichen", delegate { OpenDashboard(); });
        MenuItem miSep1 = new MenuItem("-");
        MenuItem miRename = new MenuItem("Name ändern ...", delegate { RenameSelectedEntry(); });
        MenuItem miOpen = new MenuItem("Bericht öffnen", delegate { if (lvDb.SelectedItems.Count > 0) OpenEntry((DbEntry)lvDb.SelectedItems[0].Tag); });
        MenuItem miSep2 = new MenuItem("-");
        MenuItem miDelete = new MenuItem("Aus Datenbank entfernen", delegate { DeleteSelected(); });
        cm.MenuItems.Add(miDashboard);
        cm.MenuItems.Add(miSep1);
        cm.MenuItems.Add(miRename);
        cm.MenuItems.Add(miOpen);
        cm.MenuItems.Add(miSep2);
        cm.MenuItems.Add(miDelete);
        cm.Popup += delegate {
            int selN = lvDb.SelectedItems.Count;
            int chkN = CheckedEntries().Count;
            miDashboard.Enabled = chkN >= 1 || selN >= 1;
            miRename.Enabled = selN == 1 || (selN == 0 && chkN == 1);
            miOpen.Enabled = selN == 1;
            miDelete.Enabled = chkN >= 1 || selN >= 1;
        };
        lvDb.ContextMenu = cm;

        f.Controls.Add(lvDb);
        f.Controls.Add(bottom);
        f.Controls.Add(top);
        top.SendToBack();
        bottom.SendToBack();

        FillDbList();
        return f;
    }

    static string ShortDate(string d)
    {
        DateTime t;
        if (DateTime.TryParseExact(d, "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out t)) return t.ToString("dd.MM.yy HH:mm");
        return d;
    }

    static string Num(double v, string fmt) { return v > 0 ? v.ToString(fmt, CultureInfo.GetCultureInfo("de-DE")) : ""; }

    void FillDbList()
    {
        if (lvDb == null) return;
        lvDb.BeginUpdate(); lvDb.Items.Clear();
        foreach (DbEntry e in db)
        {
            string gesamt = e.OverallScore > 0 ? Num(e.OverallScore, "N0") : "";
            string gpu = e.Get("GPU|REND") > 0 ? Num(e.Get("GPU|REND"), "N0") + " FPS" : (e.Get("GPU|VMB") > 0 ? Num(e.Get("GPU|VMB"), "N0") + " GB/s" : "");
            ListViewItem it = new ListViewItem(new string[] { e.DisplayName, ShortDate(e.Datum), gesamt, e.Cpu, e.Gpu, e.Ram, Num(e.Get("CPU|MT"), "N0"), Num(e.Get("RAM|Lesen"), "N1") + (e.Get("RAM|Lesen") > 0 ? " GB/s" : ""), gpu, e.Befunde });
            it.Tag = e; it.ToolTipText = e.DisplayName + (e.Disk.Length > 0 ? "\r\n" + e.Disk : "") + (e.HasBench ? "" : "\r\n(ohne Benchmark-Werte)");
            if (!e.HasBench) it.ForeColor = UI.Muted;
            lvDb.Items.Add(it);
        }
        if (lvDb.ListViewItemSorter != null) lvDb.Sort();
        lvDb.EndUpdate();
        if (navDb != null) { navDb.Desc = db.Count + " Systeme, vergleichen und verwalten"; navDb.Invalidate(); }
        UpdateDbButtons();
    }

    List<DbEntry> CheckedEntries()
    {
        List<DbEntry> l = new List<DbEntry>();
        if (lvDb != null) foreach (ListViewItem it in lvDb.CheckedItems) l.Add((DbEntry)it.Tag);
        return l;
    }

    void UpdateDbButtons()
    {
        if (btnDashboard == null && btnCompare == null) return;
        int n = CheckedEntries().Count;
        if (btnDelete != null) btnDelete.Enabled = n >= 1;
        if (btnCompare != null)
        {
            btnCompare.Enabled = n >= 2;
            btnCompare.Text = n >= 2 ? n + " Systeme vergleichen (Klassisch)" : "Vergleichen (Klassisch)";
        }
        if (btnDashboard != null)
        {
            btnDashboard.Text = n >= 2 ? n + " Systeme im Dashboard vergleichen" : (n == 1 ? "1 System im Dashboard anzeigen" : "Interaktives Dashboard");
        }
        if (btnRename != null)
        {
            int selCount = (lvDb != null ? lvDb.SelectedItems.Count : 0);
            btnRename.Enabled = (selCount == 1 || (selCount == 0 && n == 1));
        }
    }

    void OpenEntry(DbEntry e)
    {
        if (e == null) return;
        if (e.Ordner.Length > 0)
        {
            string dir = System.IO.Path.IsPathRooted(e.Ordner) ? e.Ordner : System.IO.Path.Combine(dataDir, e.Ordner);
            string html = System.IO.Path.Combine(dir, "Diagnosebericht.html");
            if (File.Exists(html)) { OpenShell(html); return; }
            if (Directory.Exists(dir)) { OpenShell(dir); return; }
        }
        OpenSelect(e.Path);
    }

    // Vergleichen (Klassisch): In v3.32 vollständig durch das interaktive Multi-System-Dashboard abgelöst
    void CompareSelected()
    {
        OpenDashboard();
    }

    void OpenDashboard()
    {
        Cursor = Cursors.WaitCursor;
        List<string> lines = new List<string>(); string res = "";
        List<DbEntry> sel = CheckedEntries();
        if (sel.Count == 0 && lvDb != null && lvDb.SelectedItems.Count > 0)
        {
            foreach (ListViewItem it in lvDb.SelectedItems) sel.Add((DbEntry)it.Tag);
        }
        string args = "-Dashboard";
        if (sel.Count > 0)
        {
            List<string> paths = new List<string>();
            foreach (DbEntry e in sel) paths.Add(e.Path);
            args += " -DashboardSysteme \"" + String.Join(";", paths.ToArray()) + "\"";
        }
        try { res = RunHelper(args, out lines); }
        catch (Exception ex) { lines.Add("Dashboard-Aufruf fehlgeschlagen: " + ex.Message); }
        Cursor = Cursors.Default;
        if (res.Length > 0 && File.Exists(res)) OpenShell(res);
        else
        {
            string dashPath = System.IO.Path.Combine(dataDir, "Berichte\\Dashboard.html");
            if (File.Exists(dashPath)) OpenShell(dashPath);
            else MessageBox.Show(this, "Das Dashboard konnte nicht geöffnet werden.\r\n\r\n" + String.Join("\r\n", lines.ToArray()), "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    void DeleteSelected()
    {
        List<DbEntry> sel = CheckedEntries();
        if (sel.Count == 0) return;
        StringBuilder sb = new StringBuilder();
        foreach (DbEntry e in sel) sb.AppendLine("·  " + e.DisplayName + "  " + e.Datum);
        if (MessageBox.Show(this, "Diese Einträge aus der Vergleichsdatenbank entfernen? Die Berichtsordner bleiben erhalten.\r\n\r\n" + sb.ToString(), "Leos Minibench", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        foreach (DbEntry e in sel) { try { File.Delete(e.Path); } catch { } }
        ReloadDb();
    }

    void CleanData()
    {
        if (dataDir.Length == 0) return;
        if (MessageBox.Show(this, "Lasttests vor v2.67 (andere Last, nicht vergleichbar), abgebrochene Läufe ohne Bericht und kurze Läufe (Funktionstest, von Hand nach wenigen Sekunden beendeter Lasttest, Lauf ohne Messwert) sowie ungenutzte Teile von smartmontools nach Minibench-Daten\\Archiv verschieben?\r\n\r\nGelöscht wird nichts außer älteren Übersetzungen im Cache. Das Protokoll steht in Archiv\\Datenpflege.log.", "Daten aufräumen", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        Cursor = Cursors.WaitCursor;
        List<string> lines = new List<string>(); string res = "";
        try { res = RunHelper("-Datenpflege", out lines); }
        catch (Exception ex) { lines.Add("Datenpflege fehlgeschlagen: " + ex.Message); }
        Cursor = Cursors.Default;
        ReloadDb();
        if (res.Length > 0) SetText(lblDbClean, "Datenpflege: " + res.Split('|')[0]);
        MessageBox.Show(this, lines.Count > 0 ? String.Join("\r\n", lines.ToArray()) : "Nichts zu archivieren.", "Daten aufräumen", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    void ImportFolder()
    {
        if (dbDir.Length == 0) { MessageBox.Show(this, "Kein Datenordner verfügbar.", "Leos Minibench"); return; }
        using (FolderBrowserDialog fb = new FolderBrowserDialog())
        {
            fb.Description = "Ausgabeordner eines früheren Laufs (oder einen Ordner mit mehreren davon) wählen";
            if (fb.ShowDialog(this) != DialogResult.OK) return;
            Cursor = Cursors.WaitCursor;
            List<string> lines = new List<string>();
            try { RunHelper("-ImportOrdner \"" + fb.SelectedPath.TrimEnd('\\') + "\"", out lines); }
            catch (Exception ex) { lines.Add("Import fehlgeschlagen: " + ex.Message); }
            Cursor = Cursors.Default;
            ReloadDb();
            MessageBox.Show(this, lines.Count > 0 ? String.Join("\r\n", lines.ToArray()) : "Nichts importiert.", "Import", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }
}
