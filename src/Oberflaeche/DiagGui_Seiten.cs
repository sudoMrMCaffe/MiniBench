// Seiten der grafischen Oberfläche: Versionen und Änderungen (Teilklasse DiagGui)
public partial class DiagGui
{
    Control BuildVersionPage()
    {
        FlowLayoutPanel f = Page("Versionen", "Was sich von Version zu Version geändert hat, neueste zuerst. Ausführlich in den Änderungsdateien im Ordner Doku des Projekts (Änderungen_vX.Y.txt).", -1);
        RichTextBox rt = new RichTextBox(); rt.ReadOnly = true; rt.BorderStyle = BorderStyle.FixedSingle; rt.BackColor = UI.Panel; rt.ForeColor = UI.Text;
        rt.Width = 880; rt.Height = 560; rt.DetectUrls = false; rt.ScrollBars = RichTextBoxScrollBars.Vertical; rt.Font = new Font("Segoe UI", 9.75f);
        Font fh = new Font("Segoe UI Semibold", 11f), fd = new Font("Segoe UI", 9f), fb = new Font("Segoe UI", 9.75f);
        foreach (Versionshistorie.Eintrag e in Versionshistorie.Liste)
        {
            rt.SelectionFont = fh; rt.SelectionColor = UI.Text;
            rt.AppendText("Version " + e.Version + (e.Version == this.version ? "  (diese Version)" : "") + "\r\n");
            rt.SelectionFont = fd; rt.SelectionColor = UI.Muted;
            rt.AppendText(e.Datum + "   ·   " + e.Titel + "\r\n");
            rt.SelectionFont = fb; rt.SelectionColor = UI.Text;
            rt.AppendText(e.Text + "\r\n\r\n");
        }
        rt.SelectionStart = 0; rt.ScrollToCaret();
        f.Controls.Add(rt);
        return f;
    }

    Control BuildChangePage()
    {
        FlowLayoutPanel f = Page("Änderungen", "Alles, was Leos Minibench an einem PC verändert hat, mit Vorher-Wert. Einträge der Stufe Ändern lassen sich auf dem PC, auf dem sie entstanden sind, zurücknehmen. Eingriffe stehen mit dem Weg zurück als Hinweis in der Liste.", -1);
        Label lp = Lbl("Protokoll: " + (changeDir.Length > 0 ? changeDir : "(nicht verfügbar)"), 9f, false, UI.Muted); lp.Margin = new Padding(3, 0, 3, 8); f.Controls.Add(lp);
        lvChg = new ListView(); lvChg.View = View.Details; lvChg.FullRowSelect = true; lvChg.CheckBoxes = true; lvChg.Width = 880; lvChg.Height = 360; lvChg.BorderStyle = BorderStyle.FixedSingle; lvChg.HideSelection = false; lvChg.ShowItemToolTips = true;
        string[] cols = new string[] { "Zeit", "Computer", "Maßnahme", "Ziel", "Vorher", "Nachher", "Status" };
        int[] w = new int[] { 112, 100, 170, 190, 90, 110, 96 };
        for (int i = 0; i < cols.Length; i++) lvChg.Columns.Add(cols[i], w[i]);
        lvChg.ItemCheck += delegate(object sender, ItemCheckEventArgs e)
        {
            ChangeEntry c = lvChg.Items[e.Index].Tag as ChangeEntry;
            if (c != null && !c.Undoable && e.NewValue == CheckState.Checked) e.NewValue = CheckState.Unchecked;
        };
        lvChg.ItemChecked += delegate(object sender, ItemCheckedEventArgs e)
        {
            ChangeEntry c = e.Item.Tag as ChangeEntry;
            if (e.Item.Checked && c != null && !c.Undoable) { e.Item.Checked = false; return; }
            UpdateChangeButtons();
        };
        f.Controls.Add(lvChg);
        Label hint = Lbl("Anhaken lassen sich nur aktive Einträge dieses PCs. Graue Einträge sind Hinweise, bereits zurückgenommen oder stammen von einem anderen PC.", 8.75f, false, UI.Muted); hint.Margin = new Padding(3, 4, 3, 0); f.Controls.Add(hint);
        FlowLayoutPanel b = Row(); b.Margin = new Padding(0, 10, 0, 0);
        btnUndo = UI.Primary("Rückgängig machen"); btnUndo.Margin = new Padding(0); btnUndo.Padding = new Padding(14, 3, 14, 3); btnUndo.Font = new Font("Segoe UI Semibold", 9.75f);
        btnUndo.Click += delegate { UndoSelected(); };
        Button rel = UI.Secondary("Aktualisieren"); rel.Click += delegate { ReloadDb(); };
        Button open = UI.Secondary("Protokollordner"); open.Click += delegate { if (changeDir.Length > 0 && Directory.Exists(changeDir)) OpenShell(changeDir); else if (dataDir.Length > 0) OpenShell(dataDir); };
        b.Controls.Add(btnUndo); b.Controls.Add(rel); b.Controls.Add(open); f.Controls.Add(b);
        FillChangeList();
        return f;
    }

    static string ShortTime(string d)
    {
        DateTime t;
        if (DateTime.TryParseExact(d, "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out t)) return t.ToString("dd.MM.yy HH:mm");
        return d;
    }

    void FillChangeList()
    {
        if (lvChg == null) return;
        lvChg.BeginUpdate(); lvChg.Items.Clear();
        int open = 0;
        foreach (ChangeEntry c in changes)
        {
            ListViewItem it = new ListViewItem(new string[] { ShortTime(c.Zeit), c.Computer, c.Titel, c.Ziel, c.Vorher, c.Nachher, c.Status });
            it.Tag = c;
            it.ToolTipText = ContractStep.RiskLabel(c.Risiko) + " · " + c.Art + (c.Gegenbefehl.Length > 0 ? "\r\nZurück: " + c.Gegenbefehl : "") + (c.Ergebnis.Length > 0 ? "\r\n" + c.Ergebnis : "");
            if (!c.Undoable) it.ForeColor = UI.Muted; else open++;
            lvChg.Items.Add(it);
        }
        lvChg.EndUpdate();
        if (navChg != null) { navChg.Desc = open == 1 ? "1 Änderung rückgängig machbar" : open > 1 ? open + " Änderungen rückgängig machbar" : changes.Count + (changes.Count == 1 ? " Eintrag" : " Einträge") + " im Protokoll"; navChg.Invalidate(); }
        UpdateChangeButtons();
    }

    List<ChangeEntry> CheckedChanges()
    {
        List<ChangeEntry> l = new List<ChangeEntry>();
        if (lvChg != null) foreach (ListViewItem it in lvChg.CheckedItems) { ChangeEntry c = it.Tag as ChangeEntry; if (c != null && c.Undoable) l.Add(c); }
        return l;
    }

    void UpdateChangeButtons()
    {
        if (btnUndo == null) return;
        int n = CheckedChanges().Count;
        btnUndo.Enabled = n > 0;
        btnUndo.Text = n > 1 ? n + " Änderungen rückgängig machen" : "Rückgängig machen";
    }

    void UndoSelected()
    {
        List<ChangeEntry> sel = CheckedChanges();
        if (sel.Count == 0) return;
        StringBuilder sb = new StringBuilder(); List<string> spec = new List<string>();
        foreach (ChangeEntry c in sel) { sb.AppendLine("·  " + c.Titel + ": " + c.Ziel + " wieder " + c.Vorher); spec.Add(c.FilePath + "*" + c.Id); }
        if (MessageBox.Show(this, "Diese Änderungen zurücknehmen?\r\n\r\n" + sb.ToString(), "Rückgängig machen", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        Cursor = Cursors.WaitCursor;
        List<string> lines = new List<string>();
        try { RunHelper("-Rueckgaengig \"" + String.Join(";", spec.ToArray()) + "\"", out lines); }
        catch (Exception ex) { lines.Add("Rückgängig fehlgeschlagen: " + ex.Message); }
        Cursor = Cursors.Default;
        ReloadDb();
        MessageBox.Show(this, lines.Count > 0 ? String.Join("\r\n", lines.ToArray()) : "Keine Rückmeldung vom Arbeitsprozess.", "Rückgängig", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }
}
