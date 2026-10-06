// Seiten der grafischen Oberfläche: Versionen und Änderungen (Teilklasse DiagGui)
public partial class DiagGui
{
    Control BuildVersionPage()
    {
        Panel f = new Panel(); f.Dock = DockStyle.Fill; f.BackColor = UI.Panel;
        FlowLayoutPanel top = Page("Versionen", "Was sich von Version zu Version geändert hat, neueste zuerst. Ausführlich in den Änderungsdateien im Ordner Doku des Projekts (Änderungen_vX.Y.txt).", -1);
        top.Dock = DockStyle.Top;
        top.AutoSize = true;
        top.Padding = new Padding(0, 0, 0, UI.S(10));
        RichTextBox rt = new RichTextBox(); rt.ReadOnly = true; rt.BorderStyle = BorderStyle.FixedSingle; rt.BackColor = UI.Panel; rt.ForeColor = UI.Text;
        rt.Dock = DockStyle.Fill; rt.DetectUrls = false; rt.ScrollBars = RichTextBoxScrollBars.Vertical; rt.Font = new Font("Segoe UI", 9.75f);
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
        f.Controls.Add(top);
        top.SendToBack();
        return f;
    }

    Control BuildChangePage()
    {
        Panel f = new Panel(); f.Dock = DockStyle.Fill; f.BackColor = UI.Panel;
        FlowLayoutPanel top = Page("Änderungen", "Alles, was Leos Minibench an einem PC verändert hat, mit Vorher-Wert. Einträge der Stufe Ändern lassen sich auf dem PC, auf dem sie entstanden sind, zurücknehmen. Eingriffe stehen mit dem Weg zurück als Hinweis in der Liste.", -1);
        top.Dock = DockStyle.Top;
        top.AutoSize = true;
        Label lp = Lbl("Protokoll: " + (changeDir.Length > 0 ? changeDir : "(nicht verfügbar)"), 9f, false, UI.Muted); lp.Margin = new Padding(UI.S(4), 0, UI.S(4), UI.S(8)); top.Controls.Add(lp);

        FlowLayoutPanel bottom = new FlowLayoutPanel(); bottom.FlowDirection = FlowDirection.TopDown; bottom.WrapContents = false; bottom.AutoSize = true; bottom.BackColor = UI.Panel; bottom.Dock = DockStyle.Bottom;
        Label hint = Lbl("Anhaken lassen sich nur aktive Einträge dieses PCs. Graue Einträge sind Hinweise, bereits zurückgenommen oder stammen von einem anderen PC.", 8.75f, false, UI.Muted); hint.Margin = new Padding(UI.S(4), UI.S(4), UI.S(4), 0); bottom.Controls.Add(hint);
        FlowLayoutPanel b = Row(); b.Margin = new Padding(UI.S(4), UI.S(10), 0, 0);
        btnUndo = UI.Primary("Rückgängig machen"); btnUndo.Margin = new Padding(0); btnUndo.Padding = new Padding(UI.S(14), UI.S(3), UI.S(14), UI.S(3)); btnUndo.Font = new Font("Segoe UI Semibold", 9.75f);
        btnUndo.Click += delegate { UndoSelected(); };
        Button rel = UI.Secondary("Aktualisieren"); rel.Margin = new Padding(UI.S(8), 0, 0, 0); rel.Click += delegate { ReloadDb(); };
        Button open = UI.Secondary("Protokollordner"); open.Margin = new Padding(UI.S(8), 0, 0, 0); open.Click += delegate { if (changeDir.Length > 0 && Directory.Exists(changeDir)) OpenShell(changeDir); else if (dataDir.Length > 0) OpenShell(dataDir); };
        Tip(rel, "Liest das Änderungsprotokoll neu ein.");
        Tip(open, "Öffnet den Protokollordner.");
        b.Controls.Add(btnUndo); b.Controls.Add(rel); b.Controls.Add(open); bottom.Controls.Add(b);

        lvChg = new ListView(); lvChg.View = View.Details; lvChg.FullRowSelect = true; lvChg.CheckBoxes = true; lvChg.Dock = DockStyle.Fill; lvChg.BorderStyle = BorderStyle.FixedSingle; lvChg.HideSelection = false; lvChg.ShowItemToolTips = true;
        EnableDarkListView(lvChg);
        string[] cols = new string[] { "Zeit", "Computer", "Maßnahme", "Ziel", "Vorher", "Nachher", "Status" };
        int[] w = new int[] { UI.S(112), UI.S(100), UI.S(170), UI.S(190), UI.S(90), UI.S(110), UI.S(96) };
        for (int i = 0; i < cols.Length; i++) lvChg.Columns.Add(cols[i], w[i]);
        lvChg.Resize += delegate {
            int rem = lvChg.ClientSize.Width;
            for (int i = 0; i < lvChg.Columns.Count - 1; i++) rem -= lvChg.Columns[i].Width;
            if (rem > UI.S(60)) lvChg.Columns[lvChg.Columns.Count - 1].Width = rem - 2;
        };
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
        f.Controls.Add(bottom);
        f.Controls.Add(top);
        top.SendToBack();
        bottom.SendToBack();

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

    Control BuildToolsPage()
    {
        Panel f = new Panel(); f.Dock = DockStyle.Fill; f.BackColor = UI.Panel;
        FlowLayoutPanel top = Page("Tools", "Portable Werkzeuge und praktische Windows-Schnellstarter für Partitionierung, gründliche Deinstallation, Speicherplatzanalyse und Firmware-Zugriff.", -1);
        top.Dock = DockStyle.Top; top.AutoSize = true; top.WrapContents = false;
        top.Padding = new Padding(0, 0, 0, UI.S(10));

        FlowLayoutPanel body = new FlowLayoutPanel();
        body.Dock = DockStyle.Fill; body.AutoScroll = true;
        body.FlowDirection = FlowDirection.TopDown; body.WrapContents = false;
        body.BackColor = UI.Panel;
        body.Padding = new Padding(UI.S(4), 0, UI.S(16), UI.S(20));

        FlowLayoutPanel topBar = Row(); topBar.Margin = new Padding(UI.S(4), 0, 0, UI.S(10));
        Button btnRefreshTools = UI.Secondary("Neu scannen");
        btnRefreshTools.Margin = new Padding(0);
        Tip(btnRefreshTools, "Prüft erneut auf vorhandene portable Werkzeuge und Systeminstallationen.");
        Button btnOpenToolsDir = UI.Secondary("Tools-Ordner");
        btnOpenToolsDir.Margin = new Padding(UI.S(8), 0, 0, 0);
        Tip(btnOpenToolsDir, "Öffnet den Ordner Minibench-Daten\\Tools im Windows Explorer.");
        btnOpenToolsDir.Click += delegate {
            string td = Path.Combine(dataDir, "Tools");
            try { Directory.CreateDirectory(td); } catch { }
            OpenShell(td);
        };
        Button btnConnectNas = UI.Secondary("Netzlaufwerk verbinden ...");
        btnConnectNas.Margin = new Padding(UI.S(8), 0, 0, 0);
        Tip(btnConnectNas, "Verbindet ein Netzlaufwerk oder NAS für Berichte und Datenbank mit lokalem Fallback.");
        btnConnectNas.Click += delegate { ShowConnectNasDialog(); };
        topBar.Controls.Add(btnRefreshTools);
        topBar.Controls.Add(btnOpenToolsDir);
        topBar.Controls.Add(btnConnectNas);
        body.Controls.Add(topBar);

        FlowLayoutPanel pnlCards = new FlowLayoutPanel();
        pnlCards.AutoSize = true; pnlCards.FlowDirection = FlowDirection.TopDown; pnlCards.WrapContents = false;
        pnlCards.BackColor = UI.Panel; pnlCards.Margin = new Padding(0);

        Action populateCards = delegate {
            pnlCards.SuspendLayout();
            pnlCards.Controls.Clear();

            // 1. Portable Werkzeuge
            pnlCards.Controls.Add(Section("Portable Werkzeuge"));
            Label lToolsDesc = Lbl("Werden portable Versionen im Ordner Minibench-Daten\\Tools abgelegt, nutzt Leos Minibench diese direkt ohne Installation. Alternativ wird eine vorhandene Systeminstallation gestartet.", 9f, false, UI.Muted);
            lToolsDesc.MaximumSize = new Size(UI.S(740), 0);
            lToolsDesc.Margin = new Padding(UI.S(4), 0, 0, UI.S(8));
            pnlCards.Controls.Add(lToolsDesc);

            int cardW = UI.S(720); int cardH = UI.S(68);

            // Revo Uninstaller
            FluentCard cRevo = new FluentCard("Revo Uninstaller", "Gründliche Deinstallation von Programmen inklusive Registry- und Dateiresten.", UI.IcoTools);
            cRevo.Width = cardW; cRevo.Height = cardH;
            string[] revoDirect = new string[] {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"VS Revo Group\Revo Uninstaller\RevoUnin.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"VS Revo Group\Revo Uninstaller\RevoUnin.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"VS Revo Group\Revo Uninstaller Pro\RevoUninPro.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"VS Revo Group\Revo Uninstaller Pro\RevoUninPro.exe")
            };
            string revoPath = FindToolPath("RevoUninstaller", new string[] { "RevoUPort.exe", "RevoUnin.exe", "RevoUninPro.exe", "RevoUninstaller_Portable.exe" }, new string[] { "Revo Uninstaller" }, revoDirect);
            if (!String.IsNullOrEmpty(revoPath))
            {
                cRevo.Description = "Bereit: " + (revoPath.IndexOf("Minibench-Daten", StringComparison.OrdinalIgnoreCase) >= 0 ? "Portabel (" + Path.GetFileName(revoPath) + ")" : "Systeminstallation (" + Path.GetFileName(revoPath) + ")");
                Button bStart = UI.Primary("Starten (Admin)");
                Tip(bStart, "Startet Revo Uninstaller mit Administratorrechten (" + revoPath + ").");
                string rp = revoPath; bStart.Click += delegate { StartAdminProcess(rp, ""); };
                cRevo.ActionButton = bStart;
                Button bFolder = UI.Secondary("Ordner");
                Tip(bFolder, "Öffnet den Speicherort von Revo Uninstaller.");
                bFolder.Click += delegate { OpenSelect(rp); };
                cRevo.SecondaryButton = bFolder;
            }
            else
            {
                cRevo.Description = "Nicht gefunden (erwartet in Minibench-Daten\\Tools\\RevoUninstaller oder auf dem System).";
                Button bDl = UI.Secondary("Herunterladen");
                Tip(bDl, "Öffnet die Downloadseite von Revo Uninstaller im Standardbrowser.");
                bDl.Click += delegate { OpenShell("https://www.revouninstaller.com/revo-uninstaller-free-download/"); };
                cRevo.ActionButton = bDl;
                Button bDir = UI.Secondary("Ordner öffnen");
                Tip(bDir, "Erstellt und öffnet den Ordner Minibench-Daten\\Tools\\RevoUninstaller.");
                bDir.Click += delegate { string d = Path.Combine(dataDir, "Tools\\RevoUninstaller"); try { Directory.CreateDirectory(d); } catch { } OpenShell(d); };
                cRevo.SecondaryButton = bDir;
            }
            Tip(cRevo, "Revo Uninstaller: Software restlos entfernen.");
            pnlCards.Controls.Add(cRevo);

            // MiniTool Partition Wizard
            FluentCard cPart = new FluentCard("MiniTool Partition Wizard", "Laufwerke partitionieren, Dateisysteme konvertieren und Datenträger verwalten.", UI.IcoDisk);
            cPart.Width = cardW; cPart.Height = cardH;
            string[] partDirect = new string[] {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"MiniTool Partition Wizard 12\partitionwizard.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"MiniTool Partition Wizard 12\partitionwizard.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"MiniTool Partition Wizard\partitionwizard.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"MiniTool Partition Wizard\partitionwizard.exe")
            };
            string partPath = FindToolPath("PartitionWizard", new string[] { "partitionwizard.exe", "PartitionWizard.exe", "MiniToolPartitionWizard.exe" }, new string[] { "Partition Wizard", "MiniTool Partition Wizard" }, partDirect);
            if (!String.IsNullOrEmpty(partPath))
            {
                cPart.Description = "Bereit: " + (partPath.IndexOf("Minibench-Daten", StringComparison.OrdinalIgnoreCase) >= 0 ? "Portabel (" + Path.GetFileName(partPath) + ")" : "Systeminstallation (" + Path.GetFileName(partPath) + ")");
                Button bStart = UI.Primary("Starten (Admin)");
                Tip(bStart, "Startet MiniTool Partition Wizard mit Administratorrechten (" + partPath + ").");
                string pp = partPath; bStart.Click += delegate { StartAdminProcess(pp, ""); };
                cPart.ActionButton = bStart;
                Button bFolder = UI.Secondary("Ordner");
                Tip(bFolder, "Öffnet den Speicherort von MiniTool Partition Wizard.");
                bFolder.Click += delegate { OpenSelect(pp); };
                cPart.SecondaryButton = bFolder;
            }
            else
            {
                cPart.Description = "Nicht gefunden (erwartet in Minibench-Daten\\Tools\\PartitionWizard oder auf dem System).";
                Button bDl = UI.Secondary("Herunterladen");
                Tip(bDl, "Öffnet die Downloadseite von MiniTool Partition Wizard im Standardbrowser.");
                bDl.Click += delegate { OpenShell("https://www.partitionwizard.com/free-partition-manager.html"); };
                cPart.ActionButton = bDl;
                Button bDir = UI.Secondary("Ordner öffnen");
                Tip(bDir, "Erstellt und öffnet den Ordner Minibench-Daten\\Tools\\PartitionWizard.");
                bDir.Click += delegate { string d = Path.Combine(dataDir, "Tools\\PartitionWizard"); try { Directory.CreateDirectory(d); } catch { } OpenShell(d); };
                cPart.SecondaryButton = bDir;
            }
            Tip(cPart, "MiniTool Partition Wizard: Leistungsfähige Datenträger- und Partitionsverwaltung.");
            pnlCards.Controls.Add(cPart);

            // WizTree
            FluentCard cWiz = new FluentCard("WizTree Portable", "Ultraschneller Festplatten-Speicherplatzanalysator (MFT-Direktleser).", UI.IcoDisk);
            cWiz.Width = cardW; cWiz.Height = cardH;
            string[] wizDirect = new string[] {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"WizTree\WizTree64.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"WizTree\WizTree.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"WizTree\WizTree.exe")
            };
            string wizPath = FindToolPath("WizTree", new string[] { "WizTree64.exe", "WizTree.exe" }, new string[] { "WizTree" }, wizDirect);
            if (!String.IsNullOrEmpty(wizPath))
            {
                cWiz.Description = "Bereit: " + (wizPath.IndexOf("Minibench-Daten", StringComparison.OrdinalIgnoreCase) >= 0 ? "Portabel (" + Path.GetFileName(wizPath) + ")" : "Systeminstallation (" + Path.GetFileName(wizPath) + ")");
                Button bStart = UI.Primary("Starten (Admin)");
                Tip(bStart, "Startet WizTree mit Administratorrechten (" + wizPath + ").");
                string wp = wizPath; bStart.Click += delegate { StartAdminProcess(wp, ""); };
                cWiz.ActionButton = bStart;
                Button bFolder = UI.Secondary("Ordner");
                Tip(bFolder, "Öffnet den Speicherort von WizTree.");
                bFolder.Click += delegate { OpenSelect(wp); };
                cWiz.SecondaryButton = bFolder;
            }
            else
            {
                cWiz.Description = "Nicht gefunden (erwartet in Minibench-Daten\\Tools\\WizTree oder auf dem System).";
                Button bDl = UI.Secondary("Herunterladen");
                Tip(bDl, "Öffnet die Downloadseite von WizTree im Standardbrowser.");
                bDl.Click += delegate { OpenShell("https://diskanalyzer.com/download"); };
                cWiz.ActionButton = bDl;
                Button bDir = UI.Secondary("Ordner öffnen");
                Tip(bDir, "Erstellt und öffnet den Ordner Minibench-Daten\\Tools\\WizTree.");
                bDir.Click += delegate { string d = Path.Combine(dataDir, "Tools\\WizTree"); try { Directory.CreateDirectory(d); } catch { } OpenShell(d); };
                cWiz.SecondaryButton = bDir;
            }
            Tip(cWiz, "WizTree: Speicherfresser blitzschnell aufspüren.");
            pnlCards.Controls.Add(cWiz);

            // 2. Softwarepakete installieren (winget)
            pnlCards.Controls.Add(Section("Softwarepakete installieren (winget)"));
            Label lWingetDesc = Lbl("Auswahl populärer Basisprogramme zur automatischen und stillen Installation via Windows-Paket-Manager (winget).", 9f, false, UI.Muted);
            lWingetDesc.MaximumSize = new Size(UI.S(740), 0);
            lWingetDesc.Margin = new Padding(UI.S(4), 0, 0, UI.S(8));
            pnlCards.Controls.Add(lWingetDesc);

            Panel pnlWgBox = new Panel();
            pnlWgBox.Width = cardW;
            pnlWgBox.BackColor = UI.Panel;
            pnlWgBox.BorderStyle = BorderStyle.FixedSingle;
            pnlWgBox.Padding = new Padding(UI.S(12));
            pnlWgBox.AutoSize = true;
            pnlWgBox.Margin = new Padding(UI.S(4), 0, 0, UI.S(12));

            FlowLayoutPanel pnlWgInner = new FlowLayoutPanel();
            pnlWgInner.Dock = DockStyle.Fill;
            pnlWgInner.AutoSize = true;
            pnlWgInner.FlowDirection = FlowDirection.TopDown;
            pnlWgInner.WrapContents = false;

            string wingetPath;
            bool hasWinget = IsWingetAvailable(out wingetPath);

            // Web-Browser
            Label lCatBrowser = Lbl("Web-Browser", 9.5f, true, UI.Text);
            lCatBrowser.Margin = new Padding(0, 0, 0, UI.S(4));
            pnlWgInner.Controls.Add(lCatBrowser);

            FlowLayoutPanel rowBrowser = Row();
            rowBrowser.Margin = new Padding(0, 0, 0, UI.S(8));
            CheckBox chkChrome = Chk("Google Chrome (Google.Chrome)", false);
            Tip(chkChrome, "Google Chrome Webbrowser via winget (Google.Chrome)");
            CheckBox chkFirefox = Chk("Mozilla Firefox (Mozilla.Firefox)", false);
            Tip(chkFirefox, "Mozilla Firefox Webbrowser via winget (Mozilla.Firefox)");
            CheckBox chkOpera = Chk("Opera (Opera.Opera)", false);
            Tip(chkOpera, "Opera Webbrowser via winget (Opera.Opera)");
            rowBrowser.Controls.Add(chkChrome);
            rowBrowser.Controls.Add(chkFirefox);
            rowBrowser.Controls.Add(chkOpera);
            pnlWgInner.Controls.Add(rowBrowser);

            // Gaming & Chat
            Label lCatGaming = Lbl("Gaming & Chat", 9.5f, true, UI.Text);
            lCatGaming.Margin = new Padding(0, UI.S(4), 0, UI.S(4));
            pnlWgInner.Controls.Add(lCatGaming);

            FlowLayoutPanel rowGaming = Row();
            rowGaming.Margin = new Padding(0, 0, 0, UI.S(8));
            CheckBox chkSteam = Chk("Steam (Valve.Steam)", false);
            Tip(chkSteam, "Steam Gaming-Plattform via winget (Valve.Steam)");
            CheckBox chkDiscord = Chk("Discord (Discord.Discord)", false);
            Tip(chkDiscord, "Discord Chat- und Sprach-Client via winget (Discord.Discord)");
            rowGaming.Controls.Add(chkSteam);
            rowGaming.Controls.Add(chkDiscord);
            pnlWgInner.Controls.Add(rowGaming);

            // Produktivität & Tools
            Label lCatProd = Lbl("Produktivität & Tools", 9.5f, true, UI.Text);
            lCatProd.Margin = new Padding(0, UI.S(4), 0, UI.S(4));
            pnlWgInner.Controls.Add(lCatProd);

            FlowLayoutPanel rowProd = Row();
            rowProd.Margin = new Padding(0, 0, 0, UI.S(10));
            CheckBox chkNpp = Chk("Notepad++ (Notepad++.Notepad++)", false);
            Tip(chkNpp, "Notepad++ Quelltext-Editor via winget (Notepad++.Notepad++)");
            CheckBox chkOnlyOffice = Chk("ONLYOFFICE Desktop Editors (ONLYOFFICE.DesktopEditors)", false);
            Tip(chkOnlyOffice, "ONLYOFFICE Office-Suite via winget (ONLYOFFICE.DesktopEditors)");
            CheckBox chk7zip = Chk("7-Zip (7zip.7zip)", false);
            Tip(chk7zip, "7-Zip Packprogramm via winget (7zip.7zip)");
            CheckBox chkVlc = Chk("VLC Media Player (VideoLAN.VLC)", false);
            Tip(chkVlc, "VLC Media Player via winget (VideoLAN.VLC)");
            rowProd.Controls.Add(chkNpp);
            rowProd.Controls.Add(chkOnlyOffice);
            rowProd.Controls.Add(chk7zip);
            rowProd.Controls.Add(chkVlc);
            pnlWgInner.Controls.Add(rowProd);

            // Aktionen & Status
            FlowLayoutPanel rowWgActions = Row();
            rowWgActions.Margin = new Padding(0, UI.S(4), 0, 0);

            LinkLabel lnkWgAll = new LinkLabel(); lnkWgAll.Text = "alle"; lnkWgAll.AutoSize = true;
            lnkWgAll.Margin = new Padding(0, UI.S(6), UI.S(8), 0); lnkWgAll.LinkColor = UI.Accent;
            Tip(lnkWgAll, "Alle Softwarepakete auswählen.");
            LinkLabel lnkWgNone = new LinkLabel(); lnkWgNone.Text = "keine"; lnkWgNone.AutoSize = true;
            lnkWgNone.Margin = new Padding(0, UI.S(6), UI.S(16), 0); lnkWgNone.LinkColor = UI.Accent;
            Tip(lnkWgNone, "Alle Softwarepakete abwählen.");

            CheckBox[] allWgBoxes = new CheckBox[] { chkChrome, chkFirefox, chkOpera, chkSteam, chkDiscord, chkNpp, chkOnlyOffice, chk7zip, chkVlc };
            string[] allWgIds = new string[] { "Google.Chrome", "Mozilla.Firefox", "Opera.Opera", "Valve.Steam", "Discord.Discord", "Notepad++.Notepad++", "ONLYOFFICE.DesktopEditors", "7zip.7zip", "VideoLAN.VLC" };
            string[] allWgNames = new string[] { "Google Chrome", "Mozilla Firefox", "Opera", "Steam", "Discord", "Notepad++", "ONLYOFFICE Desktop Editors", "7-Zip", "VLC Media Player" };

            lnkWgAll.LinkClicked += delegate { foreach (CheckBox cb in allWgBoxes) cb.Checked = true; };
            lnkWgNone.LinkClicked += delegate { foreach (CheckBox cb in allWgBoxes) cb.Checked = false; };

            Button btnInstallWg = UI.Primary("Ausgewählte Programme installieren");
            btnInstallWg.Margin = new Padding(0);
            Label lblWgStatus = Lbl("", 9f, false, UI.Muted);
            lblWgStatus.Margin = new Padding(UI.S(12), UI.S(6), 0, 0);

            if (!hasWinget)
            {
                btnInstallWg.Enabled = false;
                lblWgStatus.Text = "winget ist auf diesem System nicht installiert.";
                lblWgStatus.ForeColor = UI.Warn;
                Tip(btnInstallWg, "winget ist auf diesem System nicht installiert.");
            }
            else
            {
                Tip(btnInstallWg, "Führt 'winget install' für alle markierten Programme still im Hintergrund aus.");
                btnInstallWg.Click += delegate {
                    List<int> selIndices = new List<int>();
                    for (int i = 0; i < allWgBoxes.Length; i++) {
                        if (allWgBoxes[i].Checked) selIndices.Add(i);
                    }
                    if (selIndices.Count == 0) {
                        MessageBox.Show(this, "Bitte wählen Sie mindestens ein Programm zur Installation aus.", "Softwarepakete installieren", MessageBoxButtons.OK, MessageBoxIcon.Information);
                        return;
                    }
                    InstallWingetPackagesAsync(wingetPath, selIndices, allWgIds, allWgNames, lblWgStatus, btnInstallWg, allWgBoxes, lnkWgAll, lnkWgNone);
                };
            }

            rowWgActions.Controls.Add(lnkWgAll);
            rowWgActions.Controls.Add(lnkWgNone);
            rowWgActions.Controls.Add(btnInstallWg);
            rowWgActions.Controls.Add(lblWgStatus);

            pnlWgInner.Controls.Add(rowWgActions);
            pnlWgBox.Controls.Add(pnlWgInner);
            pnlCards.Controls.Add(pnlWgBox);

            // 3. Schnellstarter & Shortcuts
            pnlCards.Controls.Add(Section("Schnellstarter & System-Shortcuts"));
            Label lShortDesc = Lbl("Direkter Aufruf nativer Windows-Verwaltungskonsolen und Neustart in die Firmware.", 9f, false, UI.Muted);
            lShortDesc.MaximumSize = new Size(UI.S(740), 0);
            lShortDesc.Margin = new Padding(UI.S(4), 0, 0, UI.S(8));
            pnlCards.Controls.Add(lShortDesc);

            // BIOS/UEFI Neustart
            FluentCard cUefi = new FluentCard("Ins BIOS/UEFI neu starten", "Startet den Computer sofort neu und öffnet automatisch das UEFI/BIOS-Setup (shutdown /r /fw /t 0).", "\uE777");
            cUefi.Width = cardW; cUefi.Height = cardH;
            Button bUefi = UI.Secondary("Neu starten");
            Tip(bUefi, "Prüft auf UEFI-Unterstützung und führt nach Bestätigung 'shutdown.exe /r /fw /t 0' aus.");
            bUefi.Click += delegate {
                if (!IsUefiFirmware())
                {
                    MessageBox.Show(this, "Dieser Computer verwendet ein klassisches BIOS oder meldet keine Unterstützung für den direkten Neustart in die UEFI-Firmware.", "BIOS/UEFI-Neustart", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                if (MessageBox.Show(this, "Möchten Sie den Computer jetzt sofort neu starten und direkt die UEFI/BIOS-Firmware-Einstellungen öffnen?\r\n\r\nBitte sichern Sie vorher alle geöffneten Dokumente und Arbeiten!", "Ins BIOS/UEFI neu starten", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                {
                    StartAdminProcess("shutdown.exe", "/r /fw /t 0");
                }
            };
            cUefi.ActionButton = bUefi;
            Tip(cUefi, "Startet das System neu und leitet direkt in das UEFI-Setup weiter.");
            pnlCards.Controls.Add(cUefi);

            // Datenträgerverwaltung
            FluentCard cDisk = new FluentCard("Datenträgerverwaltung", "Windows-Konsole zur Partitionierung und Volume-Verwaltung (diskmgmt.msc).", UI.IcoDisk);
            cDisk.Width = cardW; cDisk.Height = cardH;
            Button bDisk = UI.Secondary("Öffnen");
            Tip(bDisk, "Öffnet die Windows-Datenträgerverwaltung (diskmgmt.msc).");
            bDisk.Click += delegate { StartAdminProcess("diskmgmt.msc", ""); };
            cDisk.ActionButton = bDisk;
            Tip(cDisk, "Datenträgerverwaltung: Partitionen anlegen, verkleinern und Buchstaben zuweisen.");
            pnlCards.Controls.Add(cDisk);

            // Geräte-Manager
            FluentCard cDev = new FluentCard("Geräte-Manager", "Windows-Geräte-Manager zur Überprüfung von Hardware, Treibern und Ressourcen (devmgmt.msc).", UI.IcoCpu);
            cDev.Width = cardW; cDev.Height = cardH;
            Button bDev = UI.Secondary("Öffnen");
            Tip(bDev, "Öffnet den Windows-Geräte-Manager (devmgmt.msc).");
            bDev.Click += delegate { StartAdminProcess("devmgmt.msc", ""); };
            cDev.ActionButton = bDev;
            Tip(cDev, "Geräte-Manager: Hardwarekomponenten und Treiberstatus untersuchen.");
            pnlCards.Controls.Add(cDev);

            // Zuverlässigkeitsverlauf
            FluentCard cRel = new FluentCard("Zuverlässigkeitsverlauf", "Windows-Zuverlässigkeitsüberwachung für Abstürze, Warnungen und Fehler (perfmon /rel).", UI.IcoDiag);
            cRel.Width = cardW; cRel.Height = cardH;
            Button bRel = UI.Secondary("Öffnen");
            Tip(bRel, "Öffnet die Windows-Zuverlässigkeitsüberwachung (perfmon.exe /rel).");
            bRel.Click += delegate { StartAdminProcess("perfmon.exe", "/rel"); };
            cRel.ActionButton = bRel;
            Tip(cRel, "Zuverlässigkeitsverlauf: Stabilitätsindex und Ereignisse im Zeitverlauf einsehen.");
            pnlCards.Controls.Add(cRel);

            pnlCards.ResumeLayout(true);
        };

        btnRefreshTools.Click += delegate { populateCards(); };
        populateCards();

        body.Controls.Add(pnlCards);
        f.Controls.Add(body);
        f.Controls.Add(top);
        top.SendToBack();
        return f;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetFirmwareType(out int firmwareType);

    public static bool IsUefiFirmware()
    {
        try
        {
            int fw = 0;
            if (GetFirmwareType(out fw))
            {
                if (fw == 2) return true;
                if (fw == 1) return false;
            }
        }
        catch { }
        try
        {
            using (Microsoft.Win32.RegistryKey rk = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\SecureBoot\State"))
            {
                if (rk != null) return true;
            }
        }
        catch { }
        try
        {
            using (Microsoft.Win32.RegistryKey rk = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control"))
            {
                if (rk != null)
                {
                    object v = rk.GetValue("PEFirmwareType");
                    if (v != null && Convert.ToInt32(v) == 2) return true;
                }
            }
        }
        catch { }
        return false;
    }

    static void StartAdminProcess(string path, string args)
    {
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = path;
            if (!String.IsNullOrEmpty(args)) psi.Arguments = args;
            psi.UseShellExecute = true;
            psi.Verb = "runas";
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Das Programm konnte nicht gestartet werden:\r\n\r\n" + ex.Message, "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    public string FindToolPath(string subDir, string[] exeNames, string[] registryNames, string[] directPaths)
    {
        // 1. Portable im Minibench-Daten Ordner suchen
        if (!String.IsNullOrEmpty(dataDir))
        {
            string tdir = Path.Combine(dataDir, "Tools\\" + subDir);
            if (Directory.Exists(tdir))
            {
                if (exeNames != null)
                {
                    foreach (string en in exeNames)
                    {
                        string p = Path.Combine(tdir, en);
                        if (File.Exists(p)) return p;
                    }
                }
                try
                {
                    string[] files = Directory.GetFiles(tdir, "*.exe");
                    if (files.Length > 0) return files[0];
                }
                catch { }
            }
        }

        // 2. Bekannte Installationspfade direkt prüfen
        if (directPaths != null)
        {
            foreach (string dp in directPaths)
            {
                try { if (File.Exists(dp)) return dp; } catch { }
            }
        }

        // 3. Registry Uninstall-Schlüssel durchsuchen
        if (registryNames != null && registryNames.Length > 0)
        {
            string[] ukeys = new string[] {
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
            };
            Microsoft.Win32.RegistryKey[] roots = new Microsoft.Win32.RegistryKey[] {
                Microsoft.Win32.Registry.LocalMachine,
                Microsoft.Win32.Registry.CurrentUser
            };
            foreach (Microsoft.Win32.RegistryKey root in roots)
            {
                foreach (string uk in ukeys)
                {
                    try
                    {
                        using (Microsoft.Win32.RegistryKey key = root.OpenSubKey(uk))
                        {
                            if (key == null) continue;
                            foreach (string subName in key.GetSubKeyNames())
                            {
                                try
                                {
                                    using (Microsoft.Win32.RegistryKey sub = key.OpenSubKey(subName))
                                    {
                                        if (sub == null) continue;
                                        string disp = Convert.ToString(sub.GetValue("DisplayName"));
                                        if (String.IsNullOrEmpty(disp)) continue;
                                        foreach (string rn in registryNames)
                                        {
                                            if (disp.IndexOf(rn, StringComparison.OrdinalIgnoreCase) >= 0)
                                            {
                                                string icon = Convert.ToString(sub.GetValue("DisplayIcon"));
                                                if (!String.IsNullOrEmpty(icon))
                                                {
                                                    string clean = icon.Trim('"', ' ');
                                                    if (clean.IndexOf(',') > 0) clean = clean.Substring(0, clean.IndexOf(',')).Trim();
                                                    if (File.Exists(clean) && clean.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) return clean;
                                                }
                                                string loc = Convert.ToString(sub.GetValue("InstallLocation"));
                                                if (!String.IsNullOrEmpty(loc))
                                                {
                                                    string cleanLoc = loc.Trim('"', ' ');
                                                    if (Directory.Exists(cleanLoc))
                                                    {
                                                        if (exeNames != null)
                                                        {
                                                            foreach (string en in exeNames)
                                                            {
                                                                string p = Path.Combine(cleanLoc, en);
                                                                if (File.Exists(p)) return p;
                                                            }
                                                        }
                                                        string[] ef = Directory.GetFiles(cleanLoc, "*.exe");
                                                        if (ef.Length > 0) return ef[0];
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                catch { }
                            }
                        }
                    }
                    catch { }
                }
            }
        }
        return null;
    }

    public void InstallWingetPackagesAsync(string exeToRun, List<int> selIndices, string[] allWgIds, string[] allWgNames, Label lblWgStatus, Button btnInstallWg, CheckBox[] allWgBoxes, LinkLabel lnkWgAll, LinkLabel lnkWgNone)
    {
        btnInstallWg.Enabled = false;
        foreach (CheckBox cb in allWgBoxes) cb.Enabled = false;
        lnkWgAll.Enabled = false; lnkWgNone.Enabled = false;

        System.Threading.Thread t = new System.Threading.Thread(delegate() {
            int okCount = 0;
            int failCount = 0;
            int total = selIndices.Count;
            for (int s = 0; s < total; s++) {
                int idx = selIndices[s];
                string pkgId = allWgIds[idx];
                string pkgName = allWgNames[idx];
                string statusTxt = String.Format("Installiere ({0} von {1}): {2} ...", s + 1, total, pkgName);
                try {
                    this.BeginInvoke(new MethodInvoker(delegate {
                        lblWgStatus.Text = statusTxt;
                        lblWgStatus.ForeColor = UI.Accent;
                    }));
                } catch { }

                try {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = exeToRun;
                    psi.Arguments = "install --id " + pkgId + " -e --silent --accept-package-agreements --accept-source-agreements";
                    psi.UseShellExecute = false;
                    psi.CreateNoWindow = true;
                    psi.RedirectStandardOutput = true;
                    psi.RedirectStandardError = true;
                    using (Process proc = Process.Start(psi)) {
                        proc.WaitForExit();
                        if (proc.ExitCode == 0) okCount++; else failCount++;
                    }
                } catch { failCount++; }
            }

            try {
                this.BeginInvoke(new MethodInvoker(delegate {
                    btnInstallWg.Enabled = true;
                    foreach (CheckBox cb in allWgBoxes) cb.Enabled = true;
                    lnkWgAll.Enabled = true; lnkWgNone.Enabled = true;
                    if (failCount == 0) {
                        lblWgStatus.Text = String.Format("Installation abgeschlossen: {0} Programme erfolgreich installiert.", okCount);
                        lblWgStatus.ForeColor = UI.Ok;
                    } else {
                        lblWgStatus.Text = String.Format("Abgeschlossen: {0} erfolgreich, {1} fehlgeschlagen.", okCount, failCount);
                        lblWgStatus.ForeColor = UI.Warn;
                    }
                }));
            } catch { }
        });
        t.IsBackground = true;
        t.Start();
    }

    public static bool IsWingetAvailable(out string wingetPath)
    {
        wingetPath = "winget.exe";
        try
        {
            string appDataWinget = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\WindowsApps\winget.exe");
            if (File.Exists(appDataWinget)) { wingetPath = appDataWinget; return true; }
            ProcessStartInfo psi = new ProcessStartInfo("where.exe", "winget");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            using (Process p = Process.Start(psi))
            {
                string o = p.StandardOutput.ReadToEnd();
                p.WaitForExit();
                if (p.ExitCode == 0 && !String.IsNullOrEmpty(o))
                {
                    string first = o.Split(new char[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)[0].Trim();
                    if (File.Exists(first)) { wingetPath = first; return true; }
                    return true;
                }
            }
        }
        catch { }
        return false;
    }

    public static bool TestWritableDir(string dir)
    {
        if (String.IsNullOrEmpty(dir)) return false;
        try
        {
            Directory.CreateDirectory(dir);
            string testFile = Path.Combine(dir, ".schreibtest_" + Process.GetCurrentProcess().Id + ".tmp");
            File.WriteAllText(testFile, "x", Encoding.UTF8);
            File.Delete(testFile);
            return true;
        }
        catch { return false; }
    }

    public void SwitchDataDir(string newDir)
    {
        if (String.IsNullOrEmpty(newDir)) return;
        this.dataDir = newDir.TrimEnd('\\');
        this.dbDir = Path.Combine(this.dataDir, "Datenbank");
        this.changeDir = Path.Combine(this.dataDir, "Änderungen");
        try { Directory.CreateDirectory(this.dataDir); } catch { }
        try { Directory.CreateDirectory(this.dbDir); } catch { }
        try { Directory.CreateDirectory(this.changeDir); } catch { }
        try { ReloadDb(); } catch { }
    }

    public void ShowConnectNasDialog()
    {
        using (Form dlg = new Form())
        {
            dlg.Text = "Netzlaufwerk für Berichte & Datenbank verbinden";
            dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
            dlg.MaximizeBox = false; dlg.MinimizeBox = false; dlg.ShowInTaskbar = false;
            dlg.StartPosition = FormStartPosition.CenterParent;
            dlg.Font = new Font("Segoe UI", 9.5f);
            dlg.BackColor = UI.Bg; dlg.ForeColor = UI.Text;
            dlg.ClientSize = new Size(UI.S(520), UI.S(380));

            FlowLayoutPanel p = new FlowLayoutPanel();
            p.Dock = DockStyle.Fill;
            p.FlowDirection = FlowDirection.TopDown;
            p.WrapContents = false;
            p.Padding = new Padding(UI.S(16));

            Label lInfo = Lbl("Verbindet ein Netzlaufwerk oder NAS für Berichte und Vergleichsdatenbank. Ist das Netzlaufwerk offline oder nicht beschreibbar, schaltet Minibench automatisch auf den lokalen Datenordner zurück.", 9f, false, UI.Muted);
            lInfo.MaximumSize = new Size(UI.S(480), 0);
            lInfo.Margin = new Padding(0, 0, 0, UI.S(12));
            p.Controls.Add(lInfo);

            Label lPath = Lbl("Netzwerkpfad (UNC-Pfad oder Netzlaufwerk):", 9.5f, true, UI.Text);
            lPath.Margin = new Padding(0, 0, 0, UI.S(4));
            p.Controls.Add(lPath);

            TextBox tbPath = new TextBox();
            tbPath.Width = UI.S(480);
            string initialPath = (dataDir != null && dataDir.StartsWith(@"\\")) ? dataDir : "";
            if (String.IsNullOrEmpty(initialPath)) {
                List<string> probeDirs = new List<string>();
                string eEnv = Environment.GetEnvironmentVariable("LEOSMINIBENCH_EXE");
                if (!String.IsNullOrEmpty(eEnv)) { try { string ed = Path.GetDirectoryName(eEnv); if (!String.IsNullOrEmpty(ed)) probeDirs.Add(Path.Combine(ed, "Minibench-Daten")); } catch { } }
                probeDirs.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Leos Minibench"));
                probeDirs.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "LeosMinibench"));
                probeDirs.Add(Path.Combine(Directory.GetCurrentDirectory(), "Minibench-Daten"));
                if (!String.IsNullOrEmpty(dataDir) && !dataDir.StartsWith(@"\\")) probeDirs.Add(dataDir);
                foreach (string pd in probeDirs) {
                    try {
                        string cfg = Path.Combine(pd, "Netzwerk.json");
                        if (File.Exists(cfg)) {
                            string txt = File.ReadAllText(cfg, Encoding.UTF8);
                            System.Text.RegularExpressions.Match m = System.Text.RegularExpressions.Regex.Match(txt, @"""NasPfad""\s*:\s*""([^""]+)""");
                            if (m.Success && !String.IsNullOrEmpty(m.Groups[1].Value)) { initialPath = m.Groups[1].Value.Replace(@"\\", @"\"); break; }
                        }
                    } catch { }
                }
            }
            if (String.IsNullOrEmpty(initialPath)) initialPath = @"\\NAS\Freigabe\Minibench-Daten";
            tbPath.Text = initialPath;
            tbPath.Margin = new Padding(0, 0, 0, UI.S(10));
            p.Controls.Add(tbPath);

            Label lUser = Lbl("Benutzername (optional für 'net use'):", 9f, false, UI.Text);
            lUser.Margin = new Padding(0, 0, 0, UI.S(2));
            p.Controls.Add(lUser);

            TextBox tbUser = new TextBox();
            tbUser.Width = UI.S(480);
            tbUser.Margin = new Padding(0, 0, 0, UI.S(8));
            p.Controls.Add(tbUser);

            Label lPass = Lbl("Kennwort (optional):", 9f, false, UI.Text);
            lPass.Margin = new Padding(0, 0, 0, UI.S(2));
            p.Controls.Add(lPass);

            TextBox tbPass = new TextBox();
            tbPass.Width = UI.S(480);
            tbPass.UseSystemPasswordChar = true;
            tbPass.Margin = new Padding(0, 0, 0, UI.S(10));
            p.Controls.Add(tbPass);

            CheckBox chkSave = Chk("In Minibench-Daten\\Netzwerk.json dauerhaft festlegen", true);
            chkSave.Margin = new Padding(0, 0, 0, UI.S(4));
            Tip(chkSave, "Speichert den NAS-Pfad in der lokalen Konfigurationsdatei Netzwerk.json für zukünftige Starts.");
            p.Controls.Add(chkSave);

            CheckBox chkNetUse = Chk("Verbindung jetzt herstellen ('net use')", true);
            chkNetUse.Margin = new Padding(0, 0, 0, UI.S(14));
            Tip(chkNetUse, "Führt im Hintergrund 'net use' aus, um Netzwerkauthentifizierung herzustellen.");
            p.Controls.Add(chkNetUse);

            FlowLayoutPanel rowButtons = Row();
            Button btnOk = UI.Primary("Verbinden & Umschalten");
            btnOk.Margin = new Padding(0);
            Tip(btnOk, "Testet Schreibrechte und schaltet den aktiven Speicherort auf das Netzlaufwerk um.");

            Button btnCancel = UI.Secondary("Abbrechen");
            btnCancel.Margin = new Padding(UI.S(8), 0, 0, 0);
            btnCancel.Click += delegate { dlg.Close(); };
            Tip(btnCancel, "Schließt den Dialog ohne Änderungen.");

            btnOk.Click += delegate {
                string unc = tbPath.Text.Trim();
                if (String.IsNullOrEmpty(unc)) {
                    MessageBox.Show(dlg, "Bitte geben Sie einen Netzwerkpfad ein.", "Netzlaufwerk verbinden", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                // net use optional ausführen
                if (chkNetUse.Checked || !String.IsNullOrEmpty(tbUser.Text)) {
                    try {
                        ProcessStartInfo psi = new ProcessStartInfo();
                        psi.FileName = "net.exe";
                        StringBuilder args = new StringBuilder("use \"").Append(unc).Append("\"");
                        if (!String.IsNullOrEmpty(tbPass.Text)) args.Append(" \"").Append(tbPass.Text).Append("\"");
                        if (!String.IsNullOrEmpty(tbUser.Text)) args.Append(" /user:\"").Append(tbUser.Text).Append("\"");
                        args.Append(chkSave.Checked ? " /persistent:yes" : " /persistent:no");
                        psi.Arguments = args.ToString();
                        psi.UseShellExecute = false;
                        psi.CreateNoWindow = true;
                        using (Process pNet = Process.Start(psi)) {
                            pNet.WaitForExit(8000);
                        }
                    } catch { }
                }

                // Schreibprobe durchführen
                if (!TestWritableDir(unc)) {
                    MessageBox.Show(dlg, "Auf das Netzlaufwerk '" + unc + "' konnte nicht schreibend zugegriffen werden.\r\n\r\nBitte Zugriffsrechte, Freigabeeinstellungen und Netzwerkverbindung prüfen. Der bisherige Ablageort bleibt aktiv.", "Verbindung fehlgeschlagen", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                // Dauerhaft speichern wenn gewünscht
                if (chkSave.Checked) {
                    List<string> cfgDirs = new List<string>();
                    string exeEnv = Environment.GetEnvironmentVariable("LEOSMINIBENCH_EXE");
                    if (!String.IsNullOrEmpty(exeEnv)) {
                        try { string ed = Path.GetDirectoryName(exeEnv); if (!String.IsNullOrEmpty(ed) && Directory.Exists(ed)) cfgDirs.Add(Path.Combine(ed, "Minibench-Daten")); } catch { }
                    }
                    if (!String.IsNullOrEmpty(dataDir) && !dataDir.StartsWith(@"\\")) cfgDirs.Add(dataDir);
                    cfgDirs.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Leos Minibench"));
                    cfgDirs.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "LeosMinibench"));
                    cfgDirs.Add(Path.Combine(Directory.GetCurrentDirectory(), "Minibench-Daten"));

                    string json = "{\r\n  \"NasPfad\": \"" + unc.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"\r\n}\r\n";
                    foreach (string cd in cfgDirs) {
                        try {
                            if (!Directory.Exists(cd)) Directory.CreateDirectory(cd);
                            string cfgPath = Path.Combine(cd, "Netzwerk.json");
                            File.WriteAllText(cfgPath, json, new UTF8Encoding(true));
                        } catch { }
                    }
                }

                // Live umschalten
                SwitchDataDir(unc);
                MessageBox.Show(dlg, "Netzlaufwerk erfolgreich verbunden!\r\n\r\nAktiver Ablageort für Berichte und Datenbank:\r\n" + unc, "Netzlaufwerk verbunden", MessageBoxButtons.OK, MessageBoxIcon.Information);
                dlg.DialogResult = DialogResult.OK;
                dlg.Close();
            };

            rowButtons.Controls.Add(btnOk);
            rowButtons.Controls.Add(btnCancel);
            p.Controls.Add(rowButtons);

            dlg.Controls.Add(p);
            dlg.AcceptButton = btnOk;
            dlg.CancelButton = btnCancel;
            dlg.ShowDialog(this);
        }
    }
}
