// Seiten der grafischen Oberfläche: Versionen und Änderungen (Teilklasse DiagGui)
public partial class DiagGui
{
    Control BuildVersionPage()
    {
        Panel f = new Panel(); f.Dock = DockStyle.Fill; f.BackColor = UI.Panel;
        FlowLayoutPanel top = Page("Info und Versionen", "Leos Minibench " + this.version + " auf " + Environment.MachineName + ", " + OsName() + ". Darunter, was sich von Version zu Version geändert hat, neueste zuerst; ausführlich in den Änderungsdateien im Ordner Doku des Projekts (Änderungen_vX.Y.txt).", -1);
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
        FlowLayoutPanel top = Page("Systemänderungen", "Alles, was Leos Minibench an einem PC verändert hat, mit Vorher-Wert. Einträge der Stufe Ändern lassen sich auf dem PC, auf dem sie entstanden sind, zurücknehmen. Eingriffe stehen mit dem Weg zurück als Hinweis in der Liste.", -1);
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

    static string FormatRunDate(string d)
    {
        if (String.IsNullOrEmpty(d)) return "";
        DateTime t;
        if (DateTime.TryParseExact(d, new string[] { "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm" }, CultureInfo.InvariantCulture, DateTimeStyles.None, out t) ||
            DateTime.TryParse(d, CultureInfo.CurrentCulture, DateTimeStyles.None, out t))
        {
            return t.ToString("dd.MM.yyyy, HH:mm");
        }
        if (DateTime.TryParseExact(d, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out t))
        {
            return t.ToString("dd.MM.yyyy");
        }
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
        // ab 3.53 ohne Einfrieren der Oberfläche: Softwarepakete brauchen für winget uninstall bis zu 20 Minuten je Paket
        int pakete = 0; foreach (ChangeEntry c in sel) if (c.Art == "Softwarepaket") pakete++;
        List<string> lines = new List<string>();
        try { RunHelperPumped("-Rueckgaengig \"" + String.Join(";", spec.ToArray()) + "\"", out lines, 300 + pakete * WingetFristPaketSek); }
        catch (Exception ex) { lines.Add("Rückgängig fehlgeschlagen: " + ex.Message); }
        ReloadDb();
        MessageBox.Show(this, lines.Count > 0 ? String.Join("\r\n", lines.ToArray()) : "Keine Rückmeldung vom Arbeitsprozess.", "Rückgängig", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    // ab v3.64: Seite ohne eigenen Bildlaufbereich (vorher zwei Bildlaufleisten), Werkzeugkarten mit Zustandsetikett und
    // festen Knopfspalten, Netzlaufwerk als eigener Bereich, Paketauswahl ohne IDs im Text
    Control BuildToolsPage()
    {
        FlowLayoutPanel f = Page("Tools", "Portable Werkzeuge und Windows-Schnellstarter für gründliche Deinstallation, Partitionierung, Speicherplatzanalyse, Geräte und den Neustart in die Firmware.", -1);

        FlowLayoutPanel topBar = Row(); topBar.Margin = new Padding(0, UI.S(UI.Abstand1), 0, 0);
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
        topBar.Controls.Add(btnRefreshTools);
        topBar.Controls.Add(btnOpenToolsDir);
        f.Controls.Add(topBar);

        FlowLayoutPanel pnlCards = new FlowLayoutPanel();
        pnlCards.AutoSize = true; pnlCards.FlowDirection = FlowDirection.TopDown; pnlCards.WrapContents = false;
        pnlCards.BackColor = UI.Panel; pnlCards.Margin = new Padding(0);

        Action populateCards = delegate {
            pnlCards.SuspendLayout();
            pnlCards.Controls.Clear();
            int cardW = UI.S(UI.Gruppenbreite); int cardH = UI.S(68);

            // 1. Portable Werkzeuge
            pnlCards.Controls.Add(Section("Portable Werkzeuge"));
            pnlCards.Controls.Add(Hint("Liegen portable Versionen im Ordner Minibench-Daten\\Tools, nutzt Leos Minibench diese ohne Installation, sonst eine vorhandene Systeminstallation.", 0));

            pnlCards.Controls.Add(ToolCard("Revo Uninstaller", "Gründliche Deinstallation von Programmen mit Registry- und Dateiresten.", UI.IcoEntfernen,
                "RevoUninstaller", new string[] { "RevoUPort.exe", "RevoUnin.exe", "RevoUninPro.exe", "RevoUninstaller_Portable.exe" }, new string[] { "Revo Uninstaller" },
                new string[] {
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"VS Revo Group\Revo Uninstaller\RevoUnin.exe"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"VS Revo Group\Revo Uninstaller\RevoUnin.exe"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"VS Revo Group\Revo Uninstaller Pro\RevoUninPro.exe"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"VS Revo Group\Revo Uninstaller Pro\RevoUninPro.exe") },
                "https://www.revouninstaller.com/revo-uninstaller-free-download/", cardW, cardH));
            pnlCards.Controls.Add(ToolCard("MiniTool Partition Wizard", "Laufwerke partitionieren, Dateisysteme konvertieren und Datenträger verwalten.", UI.IcoDisk,
                "PartitionWizard", new string[] { "partitionwizard.exe", "PartitionWizard.exe", "MiniToolPartitionWizard.exe" }, new string[] { "Partition Wizard", "MiniTool Partition Wizard" },
                new string[] {
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"MiniTool Partition Wizard 12\partitionwizard.exe"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"MiniTool Partition Wizard 12\partitionwizard.exe"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"MiniTool Partition Wizard\partitionwizard.exe"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"MiniTool Partition Wizard\partitionwizard.exe") },
                "https://www.partitionwizard.com/free-partition-manager.html", cardW, cardH));
            pnlCards.Controls.Add(ToolCard("WizTree", "Schnelle Speicherplatzanalyse direkt aus der MFT des Laufwerks.", UI.IcoTorte,
                "WizTree", new string[] { "WizTree64.exe", "WizTree.exe" }, new string[] { "WizTree" },
                new string[] {
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"WizTree\WizTree64.exe"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"WizTree\WizTree.exe"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"WizTree\WizTree.exe") },
                "https://diskanalyzer.com/download", cardW, cardH));

            // 2. Softwarepakete installieren (winget)
            pnlCards.Controls.Add(Section("Softwarepakete installieren"));
            pnlCards.Controls.Add(Hint("Stille Installation gängiger Programme über den Windows-Paket-Manager (winget). Jede Installation steht danach auf der Seite Systemänderungen und lässt sich dort wieder entfernen.", 0));

            // ab v3.65 als abgerundete Karte wie die Werkzeugkarten (vorher eckiger Rahmen)
            CardPanel pnlWgBox = new CardPanel();
            pnlWgBox.MinimumSize = new Size(cardW, 0);
            pnlWgBox.Padding = new Padding(UI.S(16), UI.S(12), UI.S(16), UI.S(12));
            pnlWgBox.AutoSize = true;
            pnlWgBox.Margin = new Padding(0, 0, 0, UI.S(12));

            FlowLayoutPanel pnlWgInner = new FlowLayoutPanel();
            pnlWgInner.Dock = DockStyle.Fill;
            pnlWgInner.AutoSize = true;
            pnlWgInner.FlowDirection = FlowDirection.TopDown;
            pnlWgInner.WrapContents = false;

            string wingetPath;
            bool hasWinget = IsWingetAvailable(out wingetPath);

            CheckBox chkChrome = Chk("Google Chrome", false); Tip(chkChrome, "Webbrowser Google Chrome, winget-Paket Google.Chrome");
            CheckBox chkFirefox = Chk("Mozilla Firefox", false); Tip(chkFirefox, "Webbrowser Mozilla Firefox, winget-Paket Mozilla.Firefox");
            CheckBox chkOpera = Chk("Opera", false); Tip(chkOpera, "Webbrowser Opera, winget-Paket Opera.Opera");
            CheckBox chkSteam = Chk("Steam", false); Tip(chkSteam, "Spieleplattform Steam, winget-Paket Valve.Steam");
            CheckBox chkDiscord = Chk("Discord", false); Tip(chkDiscord, "Chat- und Sprachprogramm Discord, winget-Paket Discord.Discord");
            CheckBox chkNpp = Chk("Notepad++", false); Tip(chkNpp, "Texteditor Notepad++, winget-Paket Notepad++.Notepad++");
            CheckBox chkOnlyOffice = Chk("ONLYOFFICE Desktop Editors", false); Tip(chkOnlyOffice, "Office-Programme ONLYOFFICE, winget-Paket ONLYOFFICE.DesktopEditors");
            CheckBox chk7zip = Chk("7-Zip", false); Tip(chk7zip, "Packprogramm 7-Zip, winget-Paket 7zip.7zip");
            CheckBox chkVlc = Chk("VLC Media Player", false); Tip(chkVlc, "Medienwiedergabe VLC, winget-Paket VideoLAN.VLC");
            string[] cats = new string[] { "Web-Browser", "Gaming und Chat", "Produktivität und Werkzeuge" };
            CheckBox[][] rows = new CheckBox[][] { new CheckBox[] { chkChrome, chkFirefox, chkOpera }, new CheckBox[] { chkSteam, chkDiscord }, new CheckBox[] { chkNpp, chkOnlyOffice, chk7zip, chkVlc } };
            for (int ci = 0; ci < cats.Length; ci++)
            {
                Label lc = Lbl(cats[ci], UI.SchriftText, true, UI.Text); lc.Margin = new Padding(0, ci == 0 ? 0 : UI.S(4), 0, UI.S(4)); pnlWgInner.Controls.Add(lc);
                FlowLayoutPanel r = Row(); r.Margin = new Padding(0, 0, 0, UI.S(8));
                foreach (CheckBox cb in rows[ci]) { cb.Margin = new Padding(UI.S(4), UI.S(3), UI.S(12), UI.S(3)); r.Controls.Add(cb); }
                pnlWgInner.Controls.Add(r);
            }

            FlowLayoutPanel rowWgActions = Row();
            rowWgActions.Margin = new Padding(0, UI.S(4), 0, 0);
            CheckBox[] allWgBoxes = new CheckBox[] { chkChrome, chkFirefox, chkOpera, chkSteam, chkDiscord, chkNpp, chkOnlyOffice, chk7zip, chkVlc };
            string[] allWgIds = new string[] { "Google.Chrome", "Mozilla.Firefox", "Opera.Opera", "Valve.Steam", "Discord.Discord", "Notepad++.Notepad++", "ONLYOFFICE.DesktopEditors", "7zip.7zip", "VideoLAN.VLC" };
            string[] allWgNames = new string[] { "Google Chrome", "Mozilla Firefox", "Opera", "Steam", "Discord", "Notepad++", "ONLYOFFICE Desktop Editors", "7-Zip", "VLC Media Player" };

            Button btnInstallWg = UI.Primary("Ausgewählte installieren");
            btnInstallWg.Margin = new Padding(0); btnInstallWg.Font = new Font("Segoe UI Semibold", UI.SchriftText); btnInstallWg.Padding = new Padding(UI.S(14), UI.S(3), UI.S(14), UI.S(3));
            LinkLabel lnkWgAll = new LinkLabel(); lnkWgAll.Text = "alle"; lnkWgAll.AutoSize = true;
            lnkWgAll.Margin = new Padding(UI.S(16), UI.S(7), UI.S(8), 0); lnkWgAll.LinkColor = UI.Accent;
            Tip(lnkWgAll, "Alle Softwarepakete auswählen.");
            LinkLabel lnkWgNone = new LinkLabel(); lnkWgNone.Text = "keine"; lnkWgNone.AutoSize = true;
            lnkWgNone.Margin = new Padding(0, UI.S(7), UI.S(8), 0); lnkWgNone.LinkColor = UI.Accent;
            Tip(lnkWgNone, "Alle Softwarepakete abwählen.");
            Label lblWgStatus = Lbl("", UI.SchriftHinweis, false, UI.Muted);
            lblWgStatus.Margin = new Padding(UI.S(12), UI.S(7), 0, 0);
            EventHandler wgCount = delegate {
                int n = 0; foreach (CheckBox cb in allWgBoxes) if (cb.Checked) n++;
                SetText(btnInstallWg, n > 0 ? "Ausgewählte installieren (" + n + ")" : "Ausgewählte installieren");
            };
            foreach (CheckBox cb in allWgBoxes) cb.CheckedChanged += wgCount;
            lnkWgAll.LinkClicked += delegate { foreach (CheckBox cb in allWgBoxes) cb.Checked = true; };
            lnkWgNone.LinkClicked += delegate { foreach (CheckBox cb in allWgBoxes) cb.Checked = false; };

            if (!hasWinget)
            {
                btnInstallWg.Enabled = false;
                lblWgStatus.Text = "winget ist auf diesem System nicht installiert.";
                lblWgStatus.ForeColor = UI.Warn;
                Tip(btnInstallWg, "winget ist auf diesem System nicht installiert.");
            }
            else
            {
                Tip(btnInstallWg, "Installiert die markierten Programme über winget im Hintergrund. Jede Installation steht danach auf der Seite Systemänderungen und lässt sich dort wieder entfernen; schon vorhandene Programme bleiben unberührt.");
                btnInstallWg.Click += delegate {
                    List<int> selIndices = new List<int>();
                    for (int i = 0; i < allWgBoxes.Length; i++) {
                        if (allWgBoxes[i].Checked) selIndices.Add(i);
                    }
                    if (selIndices.Count == 0) {
                        MessageBox.Show(this, "Bitte mindestens ein Programm zur Installation auswählen.", "Softwarepakete installieren", MessageBoxButtons.OK, MessageBoxIcon.Information);
                        return;
                    }
                    InstallWingetPackagesAsync(selIndices, allWgIds, allWgNames, lblWgStatus, btnInstallWg, allWgBoxes, lnkWgAll, lnkWgNone);
                };
            }

            rowWgActions.Controls.Add(btnInstallWg);
            rowWgActions.Controls.Add(lnkWgAll);
            rowWgActions.Controls.Add(lnkWgNone);
            rowWgActions.Controls.Add(lblWgStatus);

            pnlWgInner.Controls.Add(rowWgActions);
            pnlWgBox.Controls.Add(pnlWgInner);
            pnlCards.Controls.Add(pnlWgBox);

            // 3. Netzlaufwerk (vorher als Knopf zwischen den Werkzeugknöpfen)
            pnlCards.Controls.Add(Section("Netzlaufwerk"));
            FluentCard cNas = new FluentCard("Netzlaufwerk als Spiegel", "Berichte und Datenbank zusätzlich auf einem Netzlaufwerk spiegeln.", UI.IcoNetz);
            cNas.Width = cardW; cNas.Height = cardH;
            Button bNas = UI.Secondary("Einrichten ..."); bNas.MinimumSize = new Size(UI.S(130), 0);
            Tip(bNas, "Richtet ein Netzlaufwerk als Spiegel der Berichte und der Datenbank ein. Werkzeuge bleiben immer auf dem Stick.");
            bNas.Click += delegate { ShowConnectNasDialog(); };
            cNas.ActionButton = bNas;
            Tip(cNas, "Netzlaufwerk als Spiegel von Berichten und Datenbank. Abgeglichen wird nur über Aktualisieren; Werkzeuge bleiben immer auf dem Stick.");
            pnlCards.Controls.Add(cNas);

            // 4. Schnellstarter
            pnlCards.Controls.Add(Section("Schnellstarter"));
            pnlCards.Controls.Add(Hint("Direkter Aufruf der Windows-Verwaltungskonsolen und Neustart in die Firmware.", 0));

            FluentCard cUefi = new FluentCard("Ins BIOS/UEFI neu starten", "Startet den Computer sofort neu und öffnet das UEFI-Setup (shutdown /r /fw /t 0).", "");
            cUefi.Width = cardW; cUefi.Height = cardH;
            Button bUefi = UI.Secondary("Neu starten"); bUefi.MinimumSize = new Size(UI.S(130), 0);
            Tip(bUefi, "Prüft auf UEFI-Unterstützung und führt nach Bestätigung 'shutdown.exe /r /fw /t 0' aus.");
            bUefi.Click += delegate {
                if (!IsUefiFirmware())
                {
                    MessageBox.Show(this, "Dieser Computer verwendet ein klassisches BIOS oder meldet keine Unterstützung für den direkten Neustart in die UEFI-Firmware.", "BIOS/UEFI-Neustart", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                if (MessageBox.Show(this, "Den Computer jetzt sofort neu starten und die UEFI/BIOS-Einstellungen öffnen?\r\n\r\nVorher alle geöffneten Dokumente und Arbeiten sichern.", "Ins BIOS/UEFI neu starten", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                {
                    StartAdminProcess("shutdown.exe", "/r /fw /t 0");
                }
            };
            cUefi.ActionButton = bUefi;
            Tip(cUefi, "Startet das System neu und leitet direkt in das UEFI-Setup weiter.");
            pnlCards.Controls.Add(cUefi);

            pnlCards.Controls.Add(LauncherCard("Datenträgerverwaltung", "Partitionen anlegen, verkleinern und Laufwerksbuchstaben zuweisen (diskmgmt.msc).", UI.IcoOrdner, "diskmgmt.msc", "", cardW, cardH));
            pnlCards.Controls.Add(LauncherCard("Geräte-Manager", "Hardware, Treiber und Ressourcen prüfen (devmgmt.msc).", UI.IcoGeraete, "devmgmt.msc", "", cardW, cardH));
            pnlCards.Controls.Add(LauncherCard("Zuverlässigkeitsverlauf", "Stabilitätsindex mit Abstürzen, Warnungen und Fehlern im Zeitverlauf (perfmon /rel).", UI.IcoDiag, "perfmon.exe", "/rel", cardW, cardH));

            pnlCards.ResumeLayout(true);
        };

        btnRefreshTools.Click += delegate { populateCards(); ApplyThemeRecursive(pnlCards); };
        populateCards();
        f.Controls.Add(pnlCards);
        return f;
    }

    // Karte eines portablen Werkzeugs: Zustand als Etikett, links "Ordner", rechts die Hauptaktion (Starten oder Herunterladen)
    FluentCard ToolCard(string title, string desc, string icon, string subDir, string[] exeNames, string[] regNames, string[] direct, string downloadUrl, int w, int h)
    {
        FluentCard c = new FluentCard(title, desc, icon); c.Width = w; c.Height = h;
        string path = FindToolPath(subDir, exeNames, regNames, direct);
        Button bMain, bFolder = UI.Secondary("Ordner");
        if (!String.IsNullOrEmpty(path))
        {
            bool portable = path.IndexOf("Minibench-Daten", StringComparison.OrdinalIgnoreCase) >= 0;
            c.StatusText = portable ? "Bereit, portabel" : "Bereit, installiert"; c.StatusLevel = "ok";
            bMain = UI.Primary("Starten");
            bMain.Image = UI.GlyphImage(UI.IcoAdmin, UI.OnAccent, UI.S(20)); bMain.Tag = UI.IcoAdmin; bMain.ImageAlign = ContentAlignment.MiddleLeft; bMain.TextImageRelation = TextImageRelation.ImageBeforeText;
            Tip(bMain, "Startet " + title + " mit Administratorrechten (" + path + ").");
            string p = path; bMain.Click += delegate { StartAdminProcess(p, ""); };
            Tip(bFolder, "Öffnet den Speicherort von " + title + ".");
            bFolder.Click += delegate { OpenSelect(p); };
        }
        else
        {
            c.StatusText = "Nicht gefunden"; c.StatusLevel = "warn";
            bMain = UI.Primary("Herunterladen");
            Tip(bMain, "Öffnet die Downloadseite von " + title + " im Standardbrowser. Die portable Version gehört in Minibench-Daten\\Tools\\" + subDir + ".");
            string u = downloadUrl; bMain.Click += delegate { OpenShell(u); };
            Tip(bFolder, "Erstellt und öffnet den Ordner Minibench-Daten\\Tools\\" + subDir + " für die portable Version.");
            string sd = subDir; bFolder.Click += delegate { string d = Path.Combine(dataDir, "Tools\\" + sd); try { Directory.CreateDirectory(d); } catch { } OpenShell(d); };
        }
        bMain.Font = new Font("Segoe UI Semibold", UI.SchriftText); bMain.Padding = new Padding(UI.S(10), UI.S(3), UI.S(10), UI.S(3));
        bMain.MinimumSize = new Size(UI.S(140), 0); bFolder.MinimumSize = new Size(UI.S(90), 0);
        c.ActionButton = bMain; c.SecondaryButton = bFolder;
        Tip(c, title + ": " + desc + (String.IsNullOrEmpty(path) ? " Erwartet in Minibench-Daten\\Tools\\" + subDir + " oder als Systeminstallation." : " Gefunden: " + path));
        return c;
    }

    // Karte eines Windows-Schnellstarters mit einem Knopf "Öffnen"
    FluentCard LauncherCard(string title, string desc, string icon, string exe, string args, int w, int h)
    {
        FluentCard c = new FluentCard(title, desc, icon); c.Width = w; c.Height = h;
        Button b = UI.Secondary("Öffnen"); b.MinimumSize = new Size(UI.S(130), 0);
        Tip(b, "Öffnet " + title + " (" + exe + (args.Length > 0 ? " " + args : "") + ").");
        string e = exe, a = args; b.Click += delegate { StartAdminProcess(e, a); };
        c.ActionButton = b;
        Tip(c, title + ": " + desc);
        return c;
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

    // Softwarepakete über winget (ab 3.53): Installation im Arbeitsprozess (-SoftwareInstallieren), dort mit Frist je Paket,
    // vollständig gelesener Ausgabe und Eintrag im Änderungsprotokoll (Risikostufe Eingriff, Gegenbefehl winget uninstall).
    // Vorher lief winget direkt aus der Oberfläche: Ausgabe umgeleitet, aber nie gelesen, WaitForExit ohne Frist (Hänger),
    // und nichts stand im Änderungsprotokoll.
    public static string WingetSpec(List<int> selIndices, string[] ids, string[] names)
    {
        List<string> parts = new List<string>();
        foreach (int i in selIndices)
        {
            if (i < 0 || i >= ids.Length) continue;
            string n = (i < names.Length ? names[i] : ids[i]).Replace(";", ",").Replace("=", "-").Replace("\"", "'");
            parts.Add(ids[i] + "=" + n);
        }
        return String.Join(";", parts.ToArray());
    }

    // Frist für den ganzen Hilfsprozess: je Paket die Fristen des Arbeitsprozesses (Kern\Softwarepakete.ps1: list 120 s vorher,
    // install 1200 s, list 120 s nachher) plus Reserve, dazu der Start von PowerShell
    public const int WingetFristPaketSek = 120 + 1200 + 120 + 60;
    public static int WingetTimeoutSec(int count) { return Math.Max(1, count) * WingetFristPaketSek + 120; }

    // @@PAKET|Nr|Anzahl|Id|Status|Text -> Status und Text; false, wenn die Zeile kein Paketereignis ist
    public static bool ParseWingetEvent(string line, out string status, out string text)
    {
        status = ""; text = "";
        if (line == null || !line.StartsWith("@@PAKET|")) return false;
        string[] x = line.Split(new char[] { '|' }, 6);
        if (x.Length < 6) return false;
        status = x[4]; text = x[5].Replace("¦", "|");
        return true;
    }

    public void InstallWingetPackagesAsync(List<int> selIndices, string[] allWgIds, string[] allWgNames, Label lblWgStatus, Button btnInstallWg, CheckBox[] allWgBoxes, LinkLabel lnkWgAll, LinkLabel lnkWgNone)
    {
        StringBuilder m = new StringBuilder();
        m.AppendLine("Diese Programme werden über winget installiert (Risikostufe Eingriff):");
        m.AppendLine();
        foreach (int i in selIndices) m.AppendLine("·  " + allWgNames[i] + " (" + allWgIds[i] + ")");
        m.AppendLine();
        m.AppendLine("Jede Installation steht danach auf der Seite Systemänderungen und lässt sich dort wieder entfernen. Schon vorhandene Programme bleiben unberührt. Je Programm gilt eine Frist von 20 Minuten.");
        if (MessageBox.Show(this, m.ToString(), "Softwarepakete installieren", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;

        btnInstallWg.Enabled = false;
        foreach (CheckBox cb in allWgBoxes) cb.Enabled = false;
        lnkWgAll.Enabled = false; lnkWgNone.Enabled = false;
        lblWgStatus.Text = "winget wird gestartet ..."; lblWgStatus.ForeColor = UI.Accent;

        string spec = WingetSpec(selIndices, allWgIds, allWgNames);
        int timeoutSec = WingetTimeoutSec(selIndices.Count);
        string args = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -EventMode -SoftwareInstallieren \"" + spec + "\"" + (dataDir.Length > 0 ? " -DatenDir \"" + dataDir.TrimEnd('\\') + "\"" : "");

        System.Threading.Thread t = new System.Threading.Thread(delegate() {
            List<string> texte = new List<string>();
            string result = "";
            bool eof = false;
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(psExe, args);
                psi.UseShellExecute = false; psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true; psi.StandardOutputEncoding = new UTF8Encoding(false);
                using (Process p = new Process())
                {
                    p.StartInfo = psi;
                    p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) {
                        string st, tx;
                        if (e.Data == null) { eof = true; return; }
                        if (e.Data.StartsWith("@@RESULT|")) { result = e.Data.Substring(9); return; }
                        if (!ParseWingetEvent(e.Data, out st, out tx)) return;
                        if (st != "läuft") lock (texte) texte.Add(tx);
                        Color c = st == "läuft" ? UI.Accent : (st == "installiert" || st == "bereits installiert") ? UI.Ok : UI.Warn;
                        try { BeginInvoke(new MethodInvoker(delegate { lblWgStatus.Text = tx; lblWgStatus.ForeColor = c; })); } catch { }
                    };
                    p.Start(); p.BeginOutputReadLine();
                    if (!p.WaitForExit(timeoutSec * 1000))
                    {
                        KillProc(p);
                        lock (texte) texte.Add("Abgebrochen: keine Rückmeldung nach " + (timeoutSec / 60) + " Minuten.");
                    }
                    // letzte Ausgabezeilen abholen, höchstens 5 s (hält ein Kindprozess die Ausgabe offen, nicht ewig warten)
                    DateTime eu = DateTime.Now.AddSeconds(5);
                    while (!eof && DateTime.Now < eu) System.Threading.Thread.Sleep(20);
                }
            }
            catch (Exception ex) { lock (texte) texte.Add("Arbeitsprozess nicht gestartet: " + ex.Message); }

            try
            {
                BeginInvoke(new MethodInvoker(delegate {
                    btnInstallWg.Enabled = true;
                    foreach (CheckBox cb in allWgBoxes) cb.Enabled = true;
                    lnkWgAll.Enabled = true; lnkWgNone.Enabled = true;
                    string[] r = result.Split('|');
                    int ok = 0, da = 0, bad = 0;
                    if (r.Length >= 3) { int.TryParse(r[0], out ok); int.TryParse(r[1], out da); int.TryParse(r[2], out bad); }
                    else bad = selIndices.Count;
                    lblWgStatus.Text = String.Format("Abgeschlossen: {0} installiert, {1} schon vorhanden, {2} fehlgeschlagen.", ok, da, bad);
                    lblWgStatus.ForeColor = bad == 0 ? UI.Ok : UI.Warn;
                    ReloadDb();
                    if (bad > 0)
                    {
                        string all; lock (texte) all = String.Join("\r\n", texte.ToArray());
                        MessageBox.Show(this, all.Length > 0 ? all : "Keine Rückmeldung vom Arbeitsprozess.", "Softwarepakete installieren", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                }));
            }
            catch { }
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

    // Netzlaufwerk einrichten (ab v3.54): nur Pfad und Benutzer in Minibench-Daten\Netzwerk.json auf dem Stick. Die Ablage
    // bleibt lokal; abgeglichen wird über Aktualisieren auf der Seite Vergleichsdatenbank. Ein Kennwort wird nicht
    // gespeichert, die Verbindung (WNetAddConnection2) ist nicht dauerhaft und endet spätestens mit dem Programm.
    public void ShowConnectNasDialog()
    {
        string altPfad, altBenutzer;
        bool hatKonfig = NasAblage.LeseKonfig(dataDir, out altPfad, out altBenutzer);
        using (Form dlg = new Form())
        {
            dlg.Text = "Netzlaufwerk für den Abgleich einrichten";
            dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
            dlg.MaximizeBox = false; dlg.MinimizeBox = false; dlg.ShowInTaskbar = false;
            dlg.StartPosition = FormStartPosition.CenterParent;
            dlg.Font = new Font("Segoe UI", 9.5f);
            dlg.BackColor = UI.Bg; dlg.ForeColor = UI.Text;
            dlg.ClientSize = new Size(UI.S(540), UI.S(400));

            FlowLayoutPanel p = new FlowLayoutPanel();
            p.Dock = DockStyle.Fill; p.FlowDirection = FlowDirection.TopDown; p.WrapContents = false; p.Padding = new Padding(UI.S(16));

            Label lInfo = Lbl("Berichte, Datenbank und Änderungsprotokolle bleiben immer auf dem Stick. Ein Netzlaufwerk ist ein Spiegel dieser Daten: \"Aktualisieren\" auf der Seite Vergleichsdatenbank gleicht beide Seiten ab. Ohne Netzlaufwerk (unterwegs) funktioniert alles wie gewohnt.", 9f, false, UI.Muted);
            lInfo.MaximumSize = new Size(UI.S(500), 0); lInfo.Margin = new Padding(0, 0, 0, UI.S(12));
            p.Controls.Add(lInfo);

            Label lPath = Lbl("Ordner auf dem Netzlaufwerk (\\\\server\\freigabe\\Ordner):", 9.5f, true, UI.Text); lPath.Margin = new Padding(0, 0, 0, UI.S(4)); p.Controls.Add(lPath);
            TextBox tbPath = new TextBox(); tbPath.Width = UI.S(500); tbPath.Margin = new Padding(0, 0, 0, UI.S(10));
            tbPath.Text = hatKonfig ? altPfad : @"\\NAS\Freigabe\Minibench";
            Tip(tbPath, "UNC-Pfad des Ordners auf dem NAS, zum Beispiel \\\\TRUENAS\\Multimedia\\MiniBench. Ein Pfad mit nur einem \\ am Anfang zeigt auf den Stick und wird abgelehnt.");
            p.Controls.Add(tbPath);

            Label lUser = Lbl("Benutzername (optional):", 9f, false, UI.Text); lUser.Margin = new Padding(0, 0, 0, UI.S(2)); p.Controls.Add(lUser);
            TextBox tbUser = new TextBox(); tbUser.Width = UI.S(500); tbUser.Margin = new Padding(0, 0, 0, UI.S(8)); tbUser.Text = altBenutzer;
            Tip(tbUser, "Nur nötig, wenn Windows die Freigabe nicht mit der eigenen Anmeldung öffnet. Wird in Netzwerk.json gespeichert, das Kennwort nicht.");
            p.Controls.Add(tbUser);

            Label lPass = Lbl("Kennwort (optional, wird nicht gespeichert):", 9f, false, UI.Text); lPass.Margin = new Padding(0, 0, 0, UI.S(2)); p.Controls.Add(lPass);
            TextBox tbPass = new TextBox(); tbPass.Width = UI.S(500); tbPass.UseSystemPasswordChar = true; tbPass.Margin = new Padding(0, 0, 0, UI.S(14));
            Tip(tbPass, "Stellt die Verbindung nur für diese Sitzung her (nicht dauerhaft). Beim Aktualisieren fragt Leos Minibench bei Bedarf erneut.");
            p.Controls.Add(tbPass);

            FlowLayoutPanel rowButtons = Row();
            Button btnOk = UI.Primary("Speichern und prüfen"); btnOk.Margin = new Padding(0);
            Tip(btnOk, "Prüft den Pfad, verbindet bei Bedarf mit Benutzer und Kennwort und speichert den Pfad in Netzwerk.json auf dem Stick.");
            Button btnRemove = UI.Secondary("Netzlaufwerk entfernen"); btnRemove.Margin = new Padding(UI.S(8), 0, 0, 0); btnRemove.Enabled = hatKonfig;
            Tip(btnRemove, "Löscht Netzwerk.json. Die Daten auf Stick und Netzlaufwerk bleiben unverändert, es wird nur nicht mehr abgeglichen.");
            Button btnCancel = UI.Secondary("Abbrechen"); btnCancel.Margin = new Padding(UI.S(8), 0, 0, 0);
            Tip(btnCancel, "Schließt den Dialog ohne Änderungen.");
            btnCancel.Click += delegate { dlg.Close(); };
            bool jetztAbgleichen = false;

            btnRemove.Click += delegate {
                if (MessageBox.Show(dlg, "Netzlaufwerk " + altPfad + " entfernen? Die Daten bleiben auf beiden Seiten erhalten, es wird nur nicht mehr abgeglichen.", "Netzlaufwerk entfernen", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                try { NasAblage.LoescheKonfig(dataDir); } catch (Exception ex) { MessageBox.Show(dlg, ex.Message, "Netzlaufwerk entfernen", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                dlg.Close();
            };

            btnOk.Click += delegate {
                string pfad = NasAblage.Vereinheitlichen(tbPath.Text);
                string fehler = NasAblage.PfadFehler(pfad);
                if (fehler.Length > 0) { MessageBox.Show(dlg, "Der Pfad ist nicht verwendbar: " + fehler, "Netzlaufwerk einrichten", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                if (dataDir.Length == 0) { MessageBox.Show(dlg, "Es gibt keinen Datenordner auf dem Stick.", "Netzlaufwerk einrichten", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                Cursor = Cursors.WaitCursor; dlg.Cursor = Cursors.WaitCursor;
                string hinweis = "";
                if (tbPass.Text.Length > 0 || tbUser.Text.Trim().Length > 0)
                {
                    string err = NasAblage.Verbinden(pfad, tbUser.Text.Trim(), tbPass.Text);
                    if (err.Length > 0) hinweis = err;
                }
                dlg.Enabled = false;
                bool ok = NasAblage.OrdnerBereit(pfad, 6000);
                dlg.Enabled = true;
                Cursor = Cursors.Default; dlg.Cursor = Cursors.Default;
                if (!ok)
                {
                    string m = "Der Ordner auf dem Netzlaufwerk ist gerade nicht erreichbar oder lässt sich nicht anlegen" + (hinweis.Length > 0 ? ": " + hinweis : ".") + "\r\n\r\nTrotzdem speichern? Abgeglichen wird dann beim nächsten Aktualisieren im Heimnetz.";
                    if (MessageBox.Show(dlg, m, "Netzlaufwerk einrichten", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
                }
                try { NasAblage.SchreibeKonfig(dataDir, pfad, tbUser.Text.Trim()); }
                catch (Exception ex) { MessageBox.Show(dlg, "Netzwerk.json lässt sich nicht schreiben: " + ex.Message, "Netzlaufwerk einrichten", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                if (ok) jetztAbgleichen = MessageBox.Show(dlg, "Netzlaufwerk gespeichert und erreichbar.\r\n\r\nJetzt abgleichen?", "Netzlaufwerk einrichten", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes;
                dlg.DialogResult = DialogResult.OK;
                dlg.Close();
            };

            rowButtons.Controls.Add(btnOk); rowButtons.Controls.Add(btnRemove); rowButtons.Controls.Add(btnCancel);
            p.Controls.Add(rowButtons);
            dlg.Controls.Add(p);
            dlg.AcceptButton = btnOk; dlg.CancelButton = btnCancel;
            UI.ThemeDialog(dlg);
            dlg.ShowDialog(this);
            if (lblDbPath != null) SetText(lblDbPath, NasAblage.AblageText(dataDir));
            if (jetztAbgleichen) RefreshAndSync();
        }
    }

    // Kennwort für das Netzlaufwerk abfragen (wird nicht gespeichert); null = abgebrochen
    string PromptPassword(string pfad, string benutzer)
    {
        using (Form dlg = new Form())
        {
            dlg.Text = "Netzlaufwerk verbinden"; dlg.FormBorderStyle = FormBorderStyle.FixedDialog; dlg.MaximizeBox = false; dlg.MinimizeBox = false;
            dlg.StartPosition = FormStartPosition.CenterParent; dlg.ClientSize = new Size(UI.S(440), UI.S(150)); dlg.BackColor = UI.Bg; dlg.Font = new Font("Segoe UI", 9f);
            Label l = new Label(); l.Text = "Kennwort für " + benutzer + " auf " + NasAblage.Freigabe(pfad) + ":"; l.Location = new Point(UI.S(16), UI.S(14)); l.Size = new Size(UI.S(408), UI.S(36));
            TextBox tb = new TextBox(); tb.UseSystemPasswordChar = true; tb.Location = new Point(UI.S(16), UI.S(54)); tb.Size = new Size(UI.S(408), UI.S(24));
            Button ok = UI.Primary("Verbinden"); ok.Location = new Point(UI.S(226), UI.S(98)); ok.Size = new Size(UI.S(95), UI.S(32)); ok.DialogResult = DialogResult.OK;
            Button ab = UI.Secondary("Abbrechen"); ab.Location = new Point(UI.S(328), UI.S(98)); ab.Size = new Size(UI.S(96), UI.S(32)); ab.DialogResult = DialogResult.Cancel;
            dlg.Controls.Add(l); dlg.Controls.Add(tb); dlg.Controls.Add(ok); dlg.Controls.Add(ab); dlg.AcceptButton = ok; dlg.CancelButton = ab;
            UI.ThemeDialog(dlg);
            return dlg.ShowDialog(this) == DialogResult.OK ? tb.Text : null;
        }
    }

    // ============================================================ Startseite (ab v3.72)
    class QuickFixItem
    {
        public string Level = "ok", Badge = "", Title = "", Desc = "", ButtonText = "", Tip = "";
        public Action Action;
    }

    Control BuildStartPage()
    {
        Panel f = new Panel(); f.Dock = DockStyle.Fill; f.BackColor = UI.Panel; f.AutoScroll = true;
        BuildStartContent(f);
        return f;
    }

    DbEntry GetCurrentPcLastRun()
    {
        DbEntry newest = null;
        DateTime newestDt = DateTime.MinValue;
        string curPc = Environment.MachineName;
        foreach (DbEntry e in db)
        {
            bool isThisPc = false;
            if (!String.IsNullOrEmpty(e.Computer) && (String.Equals(e.Computer, curPc, StringComparison.OrdinalIgnoreCase) || e.Computer.StartsWith(curPc + "_", StringComparison.OrdinalIgnoreCase)))
                isThisPc = true;
            else if (!String.IsNullOrEmpty(e.Name) && String.Equals(e.Name, curPc, StringComparison.OrdinalIgnoreCase))
                isThisPc = true;

            if (isThisPc)
            {
                DateTime dt;
                if (DateTime.TryParse(e.Datum, CultureInfo.CurrentCulture, DateTimeStyles.None, out dt) ||
                    DateTime.TryParseExact(e.Datum, "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out dt) ||
                    DateTime.TryParseExact(e.Datum, "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out dt) ||
                    DateTime.TryParseExact(e.Datum, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out dt))
                {
                    if (dt > newestDt) { newestDt = dt; newest = e; }
                }
                else if (newest == null)
                {
                    newest = e;
                }
            }
        }
        return newest;
    }

    void BuildStartContent(Panel f)
    {
        f.SuspendLayout();
        f.Controls.Clear();
        DbEntry lastRunThisPc = GetCurrentPcLastRun();
        if (lastRunThisPc == null)
        {
            BuildStartPageA(f);
        }
        else
        {
            BuildStartPageB(f, lastRunThisPc);
        }
        f.ResumeLayout(true);
    }

    void BuildStartPageA(Panel f)
    {
        FlowLayoutPanel p = new FlowLayoutPanel();
        p.FlowDirection = FlowDirection.TopDown;
        p.WrapContents = false;
        p.AutoSize = true;
        p.BackColor = UI.Panel;
        p.Margin = new Padding(0);
        p.Padding = new Padding(0);

        // 1. Kopfbereich & Steckbrief (zweispaltig, Breite Gruppenbreite)
        TableLayoutPanel headGrid = new TableLayoutPanel();
        headGrid.Width = UI.S(UI.Gruppenbreite);
        headGrid.Height = UI.S(148);
        headGrid.ColumnCount = 2;
        headGrid.RowCount = 1;
        headGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 58f));
        headGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42f));
        headGrid.Margin = new Padding(0, 0, 0, UI.S(14));

        FlowLayoutPanel leftHead = new FlowLayoutPanel();
        leftHead.Dock = DockStyle.Fill;
        leftHead.FlowDirection = FlowDirection.TopDown;
        leftHead.WrapContents = false;
        leftHead.BackColor = UI.Panel;
        leftHead.Margin = new Padding(0);

        Label lblTitle = Lbl("Willkommen bei Leos Minibench", 15.5f, true, UI.Text);
        lblTitle.Margin = new Padding(0, 0, 0, UI.S(6));
        leftHead.Controls.Add(lblTitle);

        Label lblDesc = Lbl("Prüft, misst und pflegt diesen PC. Wähle unten eine Aufgabe oder links einen oder mehrere Abläufe und starte unten rechts. Am Ende steht ein Bericht mit allen Befunden.", 9.25f, false, UI.Muted);
        lblDesc.MaximumSize = new Size(UI.S(420), 0);
        lblDesc.Margin = new Padding(0, 0, 0, UI.S(10));
        leftHead.Controls.Add(lblDesc);

        FlowLayoutPanel statusRow = new FlowLayoutPanel();
        statusRow.AutoSize = true;
        statusRow.WrapContents = false;
        statusRow.BackColor = UI.Panel;
        statusRow.Margin = new Padding(0);

        Label dot1 = Lbl("● ", 9f, true, UI.Ok); dot1.Margin = new Padding(0);
        Label txt1 = Lbl("Prüfungen lesen nur   ", 8.75f, false, UI.Muted); txt1.Margin = new Padding(0);
        Label dot2 = Lbl("● ", 9f, true, UI.Warn); dot2.Margin = new Padding(UI.S(8), 0, 0, 0);
        Label txt2 = Lbl("Änderungen sind gekennzeichnet und umkehrbar", 8.75f, false, UI.Muted); txt2.Margin = new Padding(0);
        Tip(dot1, "Diagnose und Benchmark lesen nur Systemeigenschaften und verändern keine Einstellungen.");
        Tip(txt1, "Diagnose und Benchmark lesen nur Systemeigenschaften und verändern keine Einstellungen.");
        Tip(dot2, "Wartungs- und Optimierungsmaßnahmen sind gekennzeichnet und lassen sich rückgängig machen.");
        Tip(txt2, "Wartungs- und Optimierungsmaßnahmen sind gekennzeichnet und lassen sich rückgängig machen.");
        statusRow.Controls.Add(dot1); statusRow.Controls.Add(txt1); statusRow.Controls.Add(dot2); statusRow.Controls.Add(txt2);
        leftHead.Controls.Add(statusRow);
        headGrid.Controls.Add(leftHead, 0, 0);

        Panel cardPc = new Panel();
        cardPc.Dock = DockStyle.Fill;
        cardPc.BackColor = UI.Panel;
        cardPc.Padding = new Padding(UI.S(14), UI.S(10), UI.S(14), UI.S(10));
        cardPc.Paint += delegate(object sender, PaintEventArgs pe) {
            pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath path = UI.Round(new RectangleF(0.5f, 0.5f, cardPc.Width - 1.5f, cardPc.Height - 1.5f), UI.SF(8)))
            using (Pen pen = new Pen(UI.Line)) pe.Graphics.DrawPath(pen, path);
        };

        TableLayoutPanel pcTop = new TableLayoutPanel();
        pcTop.Dock = DockStyle.Top;
        pcTop.Height = UI.S(24);
        pcTop.ColumnCount = 2;
        pcTop.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50f));
        pcTop.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50f));
        Label lblDpc = Lbl("DIESER PC", 8f, true, UI.Muted);
        lblDpc.Margin = new Padding(0);
        LinkLabel lnkInvA = new LinkLabel();
        lnkInvA.Text = "Inventar";
        lnkInvA.Font = new Font("Segoe UI", 8.5f);
        lnkInvA.LinkColor = UI.Accent;
        lnkInvA.ActiveLinkColor = UI.AccentHover;
        lnkInvA.LinkBehavior = LinkBehavior.HoverUnderline;
        lnkInvA.Anchor = AnchorStyles.Right;
        lnkInvA.AutoSize = true;
        Tip(lnkInvA, "Öffnet das detaillierte Hardware-Inventar dieses Rechners.");
        lnkInvA.LinkClicked += delegate { ShowInventoryDialog(); };
        pcTop.Controls.Add(lblDpc, 0, 0);
        pcTop.Controls.Add(lnkInvA, 1, 0);
        cardPc.Controls.Add(pcTop);

        TableLayoutPanel pcGrid = new TableLayoutPanel();
        pcGrid.Dock = DockStyle.Fill;
        pcGrid.ColumnCount = 2;
        pcGrid.RowCount = 5;
        pcGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, UI.S(75)));
        pcGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));

        string cleanCpu = DbEntry.CleanCpuName(HwCpu);
        string cpuSpec = cleanCpu.Length > 0 ? (cleanCpu + (HwCores > 0 ? " · " + HwCores + " Kerne / " + HwThreads + " Threads" : "")) : "Standard-Prozessor";
        string gpuSpec = GpuNames.Length > 0 ? GpuNames[0] : "Grafikeinheit";
        string ramSpec = HwRam.Length > 0 ? HwRam : "Arbeitsspeicher";
        string diskSpec = GetDisksSummary();
        string boardSpec = HwBoard.Length > 0 ? HwBoard : "Standard-Mainboard";

        string[][] specs = new string[][] {
            new string[] { "Prozessor", cpuSpec },
            new string[] { "Grafik", gpuSpec },
            new string[] { "Speicher", ramSpec },
            new string[] { "Laufwerke", diskSpec },
            new string[] { "Mainboard", boardSpec }
        };

        for (int i = 0; i < specs.Length; i++)
        {
            Label k = Lbl(specs[i][0], 8.25f, false, UI.Muted);
            k.Margin = new Padding(0, UI.S(1), UI.S(4), UI.S(1));
            Label v = Lbl(specs[i][1], 8.25f, false, UI.Text);
            v.Margin = new Padding(0, UI.S(1), 0, UI.S(1));
            v.AutoEllipsis = true;
            Tip(k, specs[i][0] + ": " + specs[i][1]);
            Tip(v, specs[i][0] + ": " + specs[i][1]);
            pcGrid.Controls.Add(k, 0, i);
            pcGrid.Controls.Add(v, 1, i);
        }
        cardPc.Controls.Add(pcGrid);
        pcGrid.BringToFront();
        headGrid.Controls.Add(cardPc, 1, 0);
        p.Controls.Add(headGrid);

        // 2. Aufgabenkarten
        Label lblStartHead = Lbl("Womit möchtest du anfangen?", 11.5f, true, UI.Text);
        lblStartHead.Margin = new Padding(0, UI.S(4), 0, UI.S(8));
        Tip(lblStartHead, "Wähle eine Aufgabe oder hake links Module an.");
        p.Controls.Add(lblStartHead);

        TableLayoutPanel tasksGrid = new TableLayoutPanel();
        tasksGrid.Width = UI.S(UI.Gruppenbreite);
        tasksGrid.Height = UI.S(205);
        tasksGrid.ColumnCount = 4;
        tasksGrid.RowCount = 1;
        tasksGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25f));
        tasksGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25f));
        tasksGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25f));
        tasksGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25f));
        tasksGrid.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        tasksGrid.Margin = new Padding(0, 0, 0, UI.S(16));

        StartTaskCard c1 = new StartTaskCard("PC durchchecken", "Hardware, Treiber, Leistung und Stabilität prüfen. Ergebnis ist ein ausführlicher Bericht.", "Diagnose, Bench., Last.", "Lesen", "ok", UI.IcoDiag, true);
        c1.Dock = DockStyle.Fill; c1.Margin = new Padding(0, 0, UI.S(10), 0);
        Tip(c1, "Startet Diagnose, Benchmark und Lasttest zur vollständigen Überprüfung von Hardware, Leistung und Stabilität.");
        c1.CardClicked += delegate { SelectTask("PC durchchecken"); };

        StartTaskCard c2 = new StartTaskCard("Leistung messen", "Prozessor, Speicher, Grafik und Laufwerke messen und mit anderen Systemen vergleichen.", "Benchmark · ca. 7 Min.", "Lesen", "ok", UI.IcoSpeed, false);
        c2.Dock = DockStyle.Fill; c2.Margin = new Padding(0, 0, UI.S(10), 0);
        Tip(c2, "Startet den Leistungsbenchmark für CPU, RAM, Grafikkarte und Datenträger.");
        c2.CardClicked += delegate { SelectTask("Leistung messen"); };

        StartTaskCard c3 = new StartTaskCard("Stabilität prüfen", "Volllast mit Temperatur, Takt und Fehlerprüfung. Findet Hitze- und Stabilitätsprobleme.", "Lasttest · ab 2 Min.", "Lesen", "ok", UI.IcoFlame, false);
        c3.Dock = DockStyle.Fill; c3.Margin = new Padding(0, 0, UI.S(10), 0);
        Tip(c3, "Startet den Stabilitätstest unter Volllast zur Erkennung von Überhitzung und Instabilitäten.");
        c3.CardClicked += delegate { SelectTask("Stabilität prüfen"); };

        StartTaskCard c4 = new StartTaskCard("Pflegen und beschleunigen", "Reparieren, aufräumen, Einstellungen verbessern. Jede Änderung lässt sich rückgängig machen.", "Wartung, Optimierung", "Ändert", "warn", UI.IcoWartung, false);
        c4.Dock = DockStyle.Fill; c4.Margin = new Padding(0);
        Tip(c4, "Startet Wartung und Optimierung zur Systembereinigung und Leistungsverbesserung.");
        c4.CardClicked += delegate { SelectTask("Pflegen und beschleunigen"); };

        tasksGrid.Controls.Add(c1, 0, 0);
        tasksGrid.Controls.Add(c2, 1, 0);
        tasksGrid.Controls.Add(c3, 2, 0);
        tasksGrid.Controls.Add(c4, 3, 0);
        p.Controls.Add(tasksGrid);

        // 3. Erklärbereich (zweispaltig, Breite Gruppenbreite)
        TableLayoutPanel explGrid = new TableLayoutPanel();
        explGrid.Width = UI.S(UI.Gruppenbreite);
        explGrid.Height = UI.S(154);
        explGrid.ColumnCount = 2;
        explGrid.RowCount = 1;
        explGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 58f));
        explGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42f));
        explGrid.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        explGrid.Margin = new Padding(0, 0, 0, UI.S(16));

        Panel cardSteps = new Panel();
        cardSteps.Dock = DockStyle.Fill;
        cardSteps.BackColor = UI.Panel;
        cardSteps.Padding = new Padding(UI.S(14), UI.S(12), UI.S(14), UI.S(12));
        cardSteps.Margin = new Padding(0, 0, UI.S(10), 0);
        cardSteps.Paint += delegate(object sender, PaintEventArgs pe) {
            pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath path = UI.Round(new RectangleF(0.5f, 0.5f, cardSteps.Width - 1.5f, cardSteps.Height - 1.5f), UI.SF(8)))
            using (Pen pen = new Pen(UI.Line)) pe.Graphics.DrawPath(pen, path);
        };

        Label lblStpHead = Lbl("So läuft ein Durchgang", 10.5f, true, UI.Text);
        lblStpHead.Dock = DockStyle.Top;
        lblStpHead.Height = UI.S(24);
        Tip(lblStpHead, "Drei einfache Schritte zur Durchführung.");
        cardSteps.Controls.Add(lblStpHead);

        TableLayoutPanel stepCols = new TableLayoutPanel();
        stepCols.Dock = DockStyle.Fill;
        stepCols.ColumnCount = 3;
        stepCols.RowCount = 1;
        stepCols.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.3f));
        stepCols.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.3f));
        stepCols.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.4f));

        string[][] stepData = new string[][] {
            new string[] { "1", "Ablauf wählen", "Links abhaken, mehrere lassen sich kombinieren. Die Seite daneben zeigt die Optionen." },
            new string[] { "2", "Starten", "Unten rechts. Die Fußleiste zeigt vorher die Gesamtdauer." },
            new string[] { "3", "Bericht lesen", "Öffnet sich am Ende. Befunde sind nach kritisch, Warnung und Hinweis sortiert." }
        };

        for (int i = 0; i < 3; i++)
        {
            FlowLayoutPanel sp = new FlowLayoutPanel();
            sp.Dock = DockStyle.Fill;
            sp.FlowDirection = FlowDirection.TopDown;
            sp.WrapContents = false;
            sp.BackColor = UI.Panel;
            sp.Margin = new Padding(0, 0, UI.S(6), 0);

            FlowLayoutPanel badgeRow = new FlowLayoutPanel();
            badgeRow.AutoSize = true;
            badgeRow.WrapContents = false;
            badgeRow.BackColor = UI.Panel;
            badgeRow.Margin = new Padding(0, 0, 0, UI.S(4));

            Badge bNum = new Badge(stepData[i][0], "info");
            bNum.Margin = new Padding(0, 0, UI.S(6), 0);
            Tip(bNum, "Schritt " + stepData[i][0]);
            Label stTitle = Lbl(stepData[i][1], 9f, true, UI.Text);
            Tip(stTitle, stepData[i][1]);
            badgeRow.Controls.Add(bNum);
            badgeRow.Controls.Add(stTitle);
            sp.Controls.Add(badgeRow);

            Label stDesc = Lbl(stepData[i][2], 8f, false, UI.Muted);
            stDesc.MaximumSize = new Size(UI.S(125), 0);
            Tip(stDesc, stepData[i][2]);
            sp.Controls.Add(stDesc);
            stepCols.Controls.Add(sp, i, 0);
        }
        cardSteps.Controls.Add(stepCols);
        stepCols.BringToFront();
        explGrid.Controls.Add(cardSteps, 0, 0);

        Panel cardTools = new Panel();
        cardTools.Dock = DockStyle.Fill;
        cardTools.BackColor = UI.Panel;
        cardTools.Padding = new Padding(UI.S(14), UI.S(12), UI.S(14), UI.S(12));
        cardTools.Margin = new Padding(0);
        cardTools.Paint += delegate(object sender, PaintEventArgs pe) {
            pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath path = UI.Round(new RectangleF(0.5f, 0.5f, cardTools.Width - 1.5f, cardTools.Height - 1.5f), UI.SF(8)))
            using (Pen pen = new Pen(UI.Line)) pe.Graphics.DrawPath(pen, path);
        };

        Label lblToolsHead = Lbl("Werkzeuge", 10.5f, true, UI.Text);
        lblToolsHead.Dock = DockStyle.Top;
        lblToolsHead.Height = UI.S(24);
        Tip(lblToolsHead, "Schnellzugriff auf portable Hilfswerkzeuge und Übersichten.");
        cardTools.Controls.Add(lblToolsHead);

        TableLayoutPanel toolRows = new TableLayoutPanel();
        toolRows.Dock = DockStyle.Fill;
        toolRows.RowCount = 3;
        toolRows.ColumnCount = 1;
        toolRows.RowStyles.Add(new RowStyle(SizeType.Percent, 33.3f));
        toolRows.RowStyles.Add(new RowStyle(SizeType.Percent, 33.3f));
        toolRows.RowStyles.Add(new RowStyle(SizeType.Percent, 33.4f));

        Control rowSensA = CreateToolItem(UI.IcoSens, "Sensoren live", "Temperatur, Takt, Lüfter laufend ansehen", delegate { ShowPage(7); }, "Öffnet die Live-Sensoranzeige für Temperaturen, Taktraten und Spannungen.");
        Control rowDbA = CreateToolItem(UI.IcoDb, "Vergleichsdatenbank", db.Count + " Systeme, im Dashboard vergleichen", delegate { ShowPage(8); }, "Öffnet die Vergleichsdatenbank aller gespeicherten Messungen.");
        Control rowToolsA = CreateToolItem(UI.IcoTools, "Tools", "Portable Werkzeuge, Programme, BIOS-Neustart", delegate { ShowPage(6); }, "Öffnet die Werkzeugseite mit portablen Hilfsprogrammen und Windows-Schnellstartern.");

        toolRows.Controls.Add(rowSensA, 0, 0);
        toolRows.Controls.Add(rowDbA, 0, 1);
        toolRows.Controls.Add(rowToolsA, 0, 2);
        cardTools.Controls.Add(toolRows);
        toolRows.BringToFront();
        explGrid.Controls.Add(cardTools, 1, 0);
        p.Controls.Add(explGrid);

        // 4. Abschlussleiste
        p.Controls.Add(BuildStartFooter());

        f.Controls.Add(p);
    }

    void BuildStartPageB(Panel f, DbEntry lastRun)
    {
        FlowLayoutPanel p = new FlowLayoutPanel();
        p.FlowDirection = FlowDirection.TopDown;
        p.WrapContents = false;
        p.AutoSize = true;
        p.BackColor = UI.Panel;
        p.Margin = new Padding(0);
        p.Padding = new Padding(0);

        // 1. Kopfzeile mit Badges/Pills & Inventar-Link
        TableLayoutPanel headRow = new TableLayoutPanel();
        headRow.Width = UI.S(UI.Gruppenbreite);
        headRow.Height = UI.S(32);
        headRow.ColumnCount = 2;
        headRow.RowCount = 1;
        headRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 75f));
        headRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25f));
        headRow.Margin = new Padding(0, 0, 0, UI.S(4));

        Label lblWelcome = Lbl("Willkommen zurück", 15.5f, true, UI.Text);
        lblWelcome.Margin = new Padding(0);
        Tip(lblWelcome, "Startübersicht für dieses bereits früher geprüfte System.");
        headRow.Controls.Add(lblWelcome, 0, 0);

        LinkLabel lnkInvB = new LinkLabel();
        lnkInvB.Text = "Inventar anzeigen";
        lnkInvB.Font = new Font("Segoe UI", 9f);
        lnkInvB.LinkColor = UI.Accent;
        lnkInvB.ActiveLinkColor = UI.AccentHover;
        lnkInvB.LinkBehavior = LinkBehavior.HoverUnderline;
        lnkInvB.Anchor = AnchorStyles.Right;
        lnkInvB.AutoSize = true;
        Tip(lnkInvB, "Öffnet das detaillierte Hardware-Inventar dieses Rechners.");
        lnkInvB.LinkClicked += delegate { ShowInventoryDialog(); };
        headRow.Controls.Add(lnkInvB, 1, 0);
        p.Controls.Add(headRow);

        // Pills-Reihe mit Hardwaredaten
        FlowLayoutPanel pillsRow = new FlowLayoutPanel();
        pillsRow.Width = UI.S(UI.Gruppenbreite);
        pillsRow.AutoSize = true;
        pillsRow.WrapContents = true;
        pillsRow.BackColor = UI.Panel;
        pillsRow.Margin = new Padding(0, 0, 0, UI.S(16));

        string cleanCpu = DbEntry.CleanCpuName(HwCpu);
        if (cleanCpu.Length > 0) { PillLabel pill = new PillLabel(cleanCpu); Tip(pill, "Prozessor: " + cleanCpu); pillsRow.Controls.Add(pill); }
        if (GpuNames.Length > 0 && GpuNames[0].Length > 0) { PillLabel pill = new PillLabel(GpuNames[0]); Tip(pill, "Grafikkarte: " + GpuNames[0]); pillsRow.Controls.Add(pill); }
        if (HwRam.Length > 0) { PillLabel pill = new PillLabel(HwRam); Tip(pill, "Arbeitsspeicher: " + HwRam); pillsRow.Controls.Add(pill); }
        string disksSummary = GetDisksSummary();
        if (disksSummary.Length > 0) { PillLabel pill = new PillLabel(disksSummary); Tip(pill, "Laufwerke: " + disksSummary); pillsRow.Controls.Add(pill); }
        if (HwBoard.Length > 0) { PillLabel pill = new PillLabel(HwBoard); Tip(pill, "Mainboard: " + HwBoard); pillsRow.Controls.Add(pill); }
        p.Controls.Add(pillsRow);

        // Bestimme letzten Benchmark und Lasttest DIESES PCs
        string lastBenchDate = "";
        string lastLoadDate = "";
        DateTime lastBenchDt = DateTime.MinValue;
        DateTime lastLoadDt = DateTime.MinValue;
        string curPc = Environment.MachineName;

        foreach (DbEntry e in db)
        {
            bool isThisPc = false;
            if (!String.IsNullOrEmpty(e.Computer) && (String.Equals(e.Computer, curPc, StringComparison.OrdinalIgnoreCase) || e.Computer.StartsWith(curPc + "_", StringComparison.OrdinalIgnoreCase)))
                isThisPc = true;
            else if (!String.IsNullOrEmpty(e.Name) && String.Equals(e.Name, curPc, StringComparison.OrdinalIgnoreCase))
                isThisPc = true;

            if (isThisPc)
            {
                DateTime dt;
                if (DateTime.TryParse(e.Datum, CultureInfo.CurrentCulture, DateTimeStyles.None, out dt) ||
                    DateTime.TryParseExact(e.Datum, "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out dt) ||
                    DateTime.TryParseExact(e.Datum, "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out dt) ||
                    DateTime.TryParseExact(e.Datum, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out dt))
                {
                    if (e.HasBench && dt > lastBenchDt) { lastBenchDt = dt; lastBenchDate = dt.ToString("dd.MM."); }
                    if (e.Module.IndexOf("Lasttest", StringComparison.OrdinalIgnoreCase) >= 0 && dt > lastLoadDt) { lastLoadDt = dt; lastLoadDate = dt.ToString("dd.MM."); }
                }
            }
        }

        // 2x2 Grid (Breite Gruppenbreite, Höhe 444)
        TableLayoutPanel grid2x2 = new TableLayoutPanel();
        grid2x2.Width = UI.S(UI.Gruppenbreite);
        grid2x2.Height = UI.S(444);
        grid2x2.ColumnCount = 2;
        grid2x2.RowCount = 2;
        grid2x2.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 53f));
        grid2x2.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 47f));
        grid2x2.RowStyles.Add(new RowStyle(SizeType.Absolute, UI.S(215)));
        grid2x2.RowStyles.Add(new RowStyle(SizeType.Absolute, UI.S(215)));
        grid2x2.Margin = new Padding(0, 0, 0, UI.S(14));

        // --- Kachel 1 (links oben): Letzter Lauf ---
        Panel cardLast = new Panel();
        cardLast.Dock = DockStyle.Fill;
        cardLast.BackColor = UI.Panel;
        cardLast.Margin = new Padding(0, 0, UI.S(12), UI.S(12));
        cardLast.Padding = new Padding(UI.S(14), UI.S(12), UI.S(14), UI.S(12));
        cardLast.Paint += delegate(object sender, PaintEventArgs pe) {
            pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath path = UI.Round(new RectangleF(0.5f, 0.5f, cardLast.Width - 1.5f, cardLast.Height - 1.5f), UI.SF(8)))
            using (Pen pen = new Pen(UI.Line)) pe.Graphics.DrawPath(pen, path);
        };

        TableLayoutPanel lastLayout = new TableLayoutPanel();
        lastLayout.Dock = DockStyle.Fill;
        lastLayout.ColumnCount = 1;
        lastLayout.RowCount = 3;
        lastLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, UI.S(26)));
        lastLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, UI.S(74)));
        lastLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, UI.S(38)));

        // Row 0: Kopfzeile Letzter Lauf
        TableLayoutPanel lastHead = new TableLayoutPanel();
        lastHead.Dock = DockStyle.Fill;
        lastHead.ColumnCount = 2;
        lastHead.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 40f));
        lastHead.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 60f));
        lastHead.Margin = new Padding(0);
        Label lblLTitle = Lbl("Letzter Lauf", 10.5f, true, UI.Text);
        lblLTitle.Margin = new Padding(0);
        string lastRunInfo = lastRun != null ? (FormatRunDate(lastRun.Datum) + " · " + (lastRun.Module.Length > 0 ? (lastRun.Module.IndexOf("Benchmark") >= 0 ? "Benchmark" : (lastRun.Module.IndexOf("Diagnose") >= 0 ? "Diagnose" : "Lauf")) : "Lauf")) : "keine Läufe";
        Label lblLDate = Lbl(lastRunInfo, 8.25f, false, UI.Muted);
        lblLDate.Anchor = AnchorStyles.Right;
        lblLDate.Margin = new Padding(0);
        lblLDate.AutoEllipsis = true;
        Tip(lblLTitle, "Ergebnisse des letzten auf diesem Rechner durchgeführten Laufs.");
        Tip(lblLDate, lastRunInfo);
        lastHead.Controls.Add(lblLTitle, 0, 0);
        lastHead.Controls.Add(lblLDate, 1, 0);
        lastLayout.Controls.Add(lastHead, 0, 0);

        // Row 1: KPI Grid (4 Spalten)
        TableLayoutPanel kpiGrid = new TableLayoutPanel();
        kpiGrid.Dock = DockStyle.Fill;
        kpiGrid.ColumnCount = 4;
        kpiGrid.RowCount = 1;
        kpiGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25f));
        kpiGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25f));
        kpiGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25f));
        kpiGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25f));
        kpiGrid.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        kpiGrid.Margin = new Padding(0, UI.S(4), 0, UI.S(6));

        string kpiGesamt = (lastRun != null && lastRun.OverallScore > 0) ? lastRun.OverallScore.ToString("N0", CultureInfo.CurrentCulture) : "-";
        string kpiCpu = (lastRun != null && lastRun.Get("CPU|MT") > 0) ? lastRun.Get("CPU|MT").ToString("N0", CultureInfo.CurrentCulture) : "-";
        string kpiRam = "-";
        if (lastRun != null)
        {
            double rVal = lastRun.Get("RAM|Lesen");
            if (rVal <= 0) rVal = lastRun.Get("RAM|Read");
            if (rVal > 0)
            {
                double gb = rVal > 1000.0 ? rVal / 1000.0 : rVal;
                kpiRam = gb.ToString("N1", CultureInfo.CurrentCulture) + " GB/s";
            }
        }
        string kpiGpu = "-";
        if (lastRun != null)
        {
            double gVal = lastRun.Get("GPU|REND");
            if (gVal <= 0) gVal = lastRun.Get("GPU|FPS");
            if (gVal > 0) kpiGpu = Math.Round(gVal, 0) + " FPS";
        }

        KpiBox kpi1 = new KpiBox("Gesamt", kpiGesamt); kpi1.Dock = DockStyle.Fill; Tip(kpi1, "Gesamtpunktzahl des letzten Benchmarklaufs.");
        KpiBox kpi2 = new KpiBox("CPU Mehrkern", kpiCpu); kpi2.Dock = DockStyle.Fill; Tip(kpi2, "CPU-Mehrkern-Punktzahl des letzten Laufs.");
        KpiBox kpi3 = new KpiBox("RAM Lesen", kpiRam); kpi3.Dock = DockStyle.Fill; Tip(kpi3, "Gemessener Speicherdurchsatz beim Lesen.");
        KpiBox kpi4 = new KpiBox("Grafik", kpiGpu); kpi4.Dock = DockStyle.Fill; kpi4.Margin = new Padding(0); Tip(kpi4, "Gemessene Bildrate im Grafik-Rendertest.");

        kpiGrid.Controls.Add(kpi1, 0, 0);
        kpiGrid.Controls.Add(kpi2, 1, 0);
        kpiGrid.Controls.Add(kpi3, 2, 0);
        kpiGrid.Controls.Add(kpi4, 3, 0);
        lastLayout.Controls.Add(kpiGrid, 0, 1);

        // Row 2: Aktionen & Befundstatus
        TableLayoutPanel actGrid = new TableLayoutPanel();
        actGrid.Dock = DockStyle.Fill;
        actGrid.ColumnCount = 2;
        actGrid.RowCount = 1;
        actGrid.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        actGrid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        actGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        actGrid.Margin = new Padding(0);

        FlowLayoutPanel pnlButtons = new FlowLayoutPanel();
        pnlButtons.Dock = DockStyle.Fill;
        pnlButtons.WrapContents = false;
        pnlButtons.AutoSize = true;
        pnlButtons.BackColor = UI.Panel;
        pnlButtons.Margin = new Padding(0);

        Button btnOpenRep = new PrimaryButton();
        btnOpenRep.Text = "Bericht öffnen";
        btnOpenRep.FlatStyle = FlatStyle.Flat;
        btnOpenRep.FlatAppearance.BorderSize = 0;
        btnOpenRep.BackColor = UI.Accent;
        btnOpenRep.ForeColor = UI.OnAccent;
        btnOpenRep.FlatAppearance.MouseOverBackColor = UI.AccentHover;
        btnOpenRep.FlatAppearance.MouseDownBackColor = UI.AccentActive;
        btnOpenRep.Font = new Font("Segoe UI Semibold", 8.5f);
        btnOpenRep.Padding = new Padding(UI.S(10), UI.S(3), UI.S(10), UI.S(3));
        btnOpenRep.Margin = new Padding(0, UI.S(2), UI.S(6), 0);
        btnOpenRep.AutoSize = true;
        btnOpenRep.Cursor = Cursors.Hand;
        btnOpenRep.UseVisualStyleBackColor = false;
        btnOpenRep.Enabled = (lastRun != null);
        Tip(btnOpenRep, "Öffnet den vollständigen HTML-Bericht des letzten Laufs.");
        DbEntry targetRun = lastRun;
        btnOpenRep.Click += delegate { if (targetRun != null) OpenEntry(targetRun); };
        pnlButtons.Controls.Add(btnOpenRep);

        Button btnDash = new Button();
        btnDash.Text = "Im Dashboard vergleichen";
        btnDash.FlatStyle = FlatStyle.Flat;
        btnDash.FlatAppearance.BorderColor = UI.Line;
        btnDash.BackColor = UI.Panel;
        btnDash.ForeColor = UI.Text;
        btnDash.FlatAppearance.MouseOverBackColor = UI.IsDark ? Color.FromArgb(45, 48, 52) : Color.FromArgb(243, 244, 246);
        btnDash.FlatAppearance.MouseDownBackColor = UI.IsDark ? Color.FromArgb(55, 58, 62) : Color.FromArgb(235, 237, 240);
        btnDash.Font = new Font("Segoe UI", 8.5f);
        btnDash.Padding = new Padding(UI.S(8), UI.S(3), UI.S(8), UI.S(3));
        btnDash.Margin = new Padding(0, UI.S(2), 0, 0);
        btnDash.AutoSize = true;
        btnDash.Cursor = Cursors.Hand;
        btnDash.UseVisualStyleBackColor = false;
        Tip(btnDash, "Öffnet das interaktive Dashboard zum Vergleich mit anderen Systemen.");
        btnDash.Click += delegate { OpenDashboard(); };
        pnlButtons.Controls.Add(btnDash);
        actGrid.Controls.Add(pnlButtons, 0, 0);

        string befundeText = "Befunde: keine";
        Color befundeColor = UI.Ok;
        if (lastRun != null && lastRun.Befunde.Length > 0 && lastRun.Befunde != "0 / 0 / 0")
        {
            befundeText = "Befunde: " + lastRun.Befunde;
            befundeColor = UI.Warn;
        }
        Label lblBef = Lbl(befundeText, 8.25f, true, befundeColor);
        lblBef.Anchor = AnchorStyles.Right;
        lblBef.TextAlign = ContentAlignment.MiddleRight;
        lblBef.AutoSize = true;
        lblBef.Margin = new Padding(0, UI.S(4), 0, 0);
        Tip(lblBef, "Befundzusammenfassung (Kritisch / Warnungen / Hinweise) des letzten Laufs.");
        actGrid.Controls.Add(lblBef, 1, 0);
        lastLayout.Controls.Add(actGrid, 0, 2);

        cardLast.Controls.Add(lastLayout);
        grid2x2.Controls.Add(cardLast, 0, 0);

        // --- Kachel 2 (rechts oben): Aufgaben ---
        Panel cardTasks = new Panel();
        cardTasks.Dock = DockStyle.Fill;
        cardTasks.BackColor = UI.Panel;
        cardTasks.Margin = new Padding(0, 0, 0, UI.S(12));
        cardTasks.Padding = new Padding(UI.S(14), UI.S(12), UI.S(14), UI.S(10));
        cardTasks.Paint += delegate(object sender, PaintEventArgs pe) {
            pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath path = UI.Round(new RectangleF(0.5f, 0.5f, cardTasks.Width - 1.5f, cardTasks.Height - 1.5f), UI.SF(8)))
            using (Pen pen = new Pen(UI.Line)) pe.Graphics.DrawPath(pen, path);
        };

        TableLayoutPanel tasksLayout = new TableLayoutPanel();
        tasksLayout.Dock = DockStyle.Fill;
        tasksLayout.ColumnCount = 1;
        tasksLayout.RowCount = 2;
        tasksLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, UI.S(24)));
        tasksLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));

        Label lblTHead = Lbl("Aufgaben", 10.5f, true, UI.Text);
        lblTHead.Margin = new Padding(0);
        Tip(lblTHead, "Aufgaben zur schnellen Auswahl und Durchführung.");
        tasksLayout.Controls.Add(lblTHead, 0, 0);

        TableLayoutPanel taskList = new TableLayoutPanel();
        taskList.Dock = DockStyle.Fill;
        taskList.RowCount = 4;
        taskList.ColumnCount = 1;
        taskList.RowStyles.Add(new RowStyle(SizeType.Percent, 25f));
        taskList.RowStyles.Add(new RowStyle(SizeType.Percent, 25f));
        taskList.RowStyles.Add(new RowStyle(SizeType.Percent, 25f));
        taskList.RowStyles.Add(new RowStyle(SizeType.Percent, 25f));
        taskList.Margin = new Padding(0);

        StartTaskRow tr1 = new StartTaskRow("PC durchchecken", "Diagnose, Benchmark, Lasttest", "Lesen", "ok", UI.IcoDiag);
        tr1.Dock = DockStyle.Fill;
        Tip(tr1, "Startet Diagnose, Benchmark und Lasttest zur vollständigen Überprüfung von Hardware, Leistung und Stabilität.");
        tr1.RowClicked += delegate { SelectTask("PC durchchecken"); };

        string bSub = "Benchmark · ca. 7 Min." + (lastBenchDate.Length > 0 ? " · zuletzt " + lastBenchDate : " · noch nie");
        StartTaskRow tr2 = new StartTaskRow("Leistung messen", bSub, "Lesen", "ok", UI.IcoSpeed);
        tr2.Dock = DockStyle.Fill;
        Tip(tr2, "Startet den Leistungsbenchmark für CPU, RAM, Grafikkarte und Datenträger.");
        tr2.RowClicked += delegate { SelectTask("Leistung messen"); };

        string lSub = "Lasttest · ab 2 Min." + (lastLoadDate.Length > 0 ? " · zuletzt " + lastLoadDate : " · noch nie");
        StartTaskRow tr3 = new StartTaskRow("Stabilität prüfen", lSub, "Lesen", "ok", UI.IcoFlame);
        tr3.Dock = DockStyle.Fill;
        Tip(tr3, "Startet den Stabilitätstest unter Volllast zur Erkennung von Überhitzung und Instabilitäten.");
        tr3.RowClicked += delegate { SelectTask("Stabilität prüfen"); };

        StartTaskRow tr4 = new StartTaskRow("Pflegen und beschleunigen", "Wartung, Optimierung", "Ändert", "warn", UI.IcoWartung);
        tr4.Dock = DockStyle.Fill;
        Tip(tr4, "Startet Wartung und Optimierung zur Systembereinigung und Leistungsverbesserung.");
        tr4.RowClicked += delegate { SelectTask("Pflegen und beschleunigen"); };

        taskList.Controls.Add(tr1, 0, 0);
        taskList.Controls.Add(tr2, 0, 1);
        taskList.Controls.Add(tr3, 0, 2);
        taskList.Controls.Add(tr4, 0, 3);
        tasksLayout.Controls.Add(taskList, 0, 1);
        cardTasks.Controls.Add(tasksLayout);
        grid2x2.Controls.Add(cardTasks, 1, 0);

        // --- Kachel 3 (links unten): Schnell behebbar ---
        Panel cardQuick = new Panel();
        cardQuick.Dock = DockStyle.Fill;
        cardQuick.BackColor = UI.Panel;
        cardQuick.Margin = new Padding(0, 0, UI.S(12), 0);
        cardQuick.Padding = new Padding(UI.S(14), UI.S(12), UI.S(14), UI.S(10));
        cardQuick.Paint += delegate(object sender, PaintEventArgs pe) {
            pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath path = UI.Round(new RectangleF(0.5f, 0.5f, cardQuick.Width - 1.5f, cardQuick.Height - 1.5f), UI.SF(8)))
            using (Pen pen = new Pen(UI.Line)) pe.Graphics.DrawPath(pen, path);
        };

        TableLayoutPanel quickLayout = new TableLayoutPanel();
        quickLayout.Dock = DockStyle.Fill;
        quickLayout.ColumnCount = 1;
        quickLayout.RowCount = 2;
        quickLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, UI.S(24)));
        quickLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));

        TableLayoutPanel qHead = new TableLayoutPanel();
        qHead.Dock = DockStyle.Fill;
        qHead.ColumnCount = 2;
        qHead.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 45f));
        qHead.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 55f));
        qHead.Margin = new Padding(0);
        Label lblQTitle = Lbl("Schnell behebbar", 10.5f, true, UI.Text);
        lblQTitle.Margin = new Padding(0);
        Label lblQSub = Lbl("beim Start erkannt, ohne Messung", 8f, false, UI.Muted);
        lblQSub.Anchor = AnchorStyles.Right;
        lblQSub.Margin = new Padding(0);
        Tip(lblQTitle, "Häufige Konfigurationsbremsen, die ohne Neustart oder Messung erkannt werden.");
        Tip(lblQSub, "Konfigurationsprüfungen laufen asynchron im Hintergrund.");
        qHead.Controls.Add(lblQTitle, 0, 0);
        qHead.Controls.Add(lblQSub, 1, 0);
        quickLayout.Controls.Add(qHead, 0, 0);

        Panel pQuickFixes = new Panel();
        pQuickFixes.Dock = DockStyle.Fill;
        pQuickFixes.BackColor = UI.Panel;
        Label lblLoad = Lbl("Konfiguration wird im Hintergrund geprüft ...", 8.5f, false, UI.Muted);
        lblLoad.Location = new Point(0, UI.S(16));
        lblLoad.AutoSize = true;
        Tip(lblLoad, "Prüfungen laufen ...");
        pQuickFixes.Controls.Add(lblLoad);
        quickLayout.Controls.Add(pQuickFixes, 0, 1);
        cardQuick.Controls.Add(quickLayout);
        grid2x2.Controls.Add(cardQuick, 0, 1);

        StartQuickFixChecks(pQuickFixes, lastLoadDt > DateTime.MinValue);

        // --- Kachel 4 (rechts unten): Werkzeuge ---
        Panel cardToolsB = new Panel();
        cardToolsB.Dock = DockStyle.Fill;
        cardToolsB.BackColor = UI.Panel;
        cardToolsB.Margin = new Padding(0);
        cardToolsB.Padding = new Padding(UI.S(14), UI.S(12), UI.S(14), UI.S(10));
        cardToolsB.Paint += delegate(object sender, PaintEventArgs pe) {
            pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath path = UI.Round(new RectangleF(0.5f, 0.5f, cardToolsB.Width - 1.5f, cardToolsB.Height - 1.5f), UI.SF(8)))
            using (Pen pen = new Pen(UI.Line)) pe.Graphics.DrawPath(pen, path);
        };

        TableLayoutPanel toolsLayoutB = new TableLayoutPanel();
        toolsLayoutB.Dock = DockStyle.Fill;
        toolsLayoutB.ColumnCount = 1;
        toolsLayoutB.RowCount = 2;
        toolsLayoutB.RowStyles.Add(new RowStyle(SizeType.Absolute, UI.S(24)));
        toolsLayoutB.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));

        Label lblWHead = Lbl("Werkzeuge", 10.5f, true, UI.Text);
        lblWHead.Margin = new Padding(0);
        Tip(lblWHead, "Schnellzugriff auf integrierte Werkzeuge und Übersichten.");
        toolsLayoutB.Controls.Add(lblWHead, 0, 0);

        TableLayoutPanel toolsListB = new TableLayoutPanel();
        toolsListB.Dock = DockStyle.Fill;
        toolsListB.RowCount = 3;
        toolsListB.ColumnCount = 1;
        toolsListB.RowStyles.Add(new RowStyle(SizeType.Percent, 33.3f));
        toolsListB.RowStyles.Add(new RowStyle(SizeType.Percent, 33.3f));
        toolsListB.RowStyles.Add(new RowStyle(SizeType.Percent, 33.4f));
        toolsListB.Margin = new Padding(0);

        Control rowSensB = CreateToolRowB(UI.IcoSens, "Sensoren live", "CPU [°C] · GPU [°C]", delegate { ShowPage(7); }, "Öffnet die Live-Sensoranzeige für Temperaturen, Taktraten und Spannungen.");
        Control rowDbB = CreateToolRowB(UI.IcoDb, "Vergleichsdatenbank", db.Count + " Systeme", delegate { ShowPage(8); }, "Öffnet die Vergleichsdatenbank aller gespeicherten Messungen.");
        int openChanges = 0;
        foreach (ChangeEntry ce in changes) if (ce.Undoable) openChanges++;
        string chgInfo = openChanges == 0 ? "keine offenen" : (openChanges + " offen");
        Control rowChgB = CreateToolRowB(UI.IcoChg, "Systemänderungen", chgInfo, delegate { ShowPage(9); }, "Öffnet das Protokoll der Systemänderungen mit Rückgängig-Funktion.");

        toolsListB.Controls.Add(rowSensB, 0, 0);
        toolsListB.Controls.Add(rowDbB, 0, 1);
        toolsListB.Controls.Add(rowChgB, 0, 2);
        toolsLayoutB.Controls.Add(toolsListB, 0, 1);
        cardToolsB.Controls.Add(toolsLayoutB);
        grid2x2.Controls.Add(cardToolsB, 1, 1);

        p.Controls.Add(grid2x2);

        // 4. Abschlussleiste
        p.Controls.Add(BuildStartFooter());

        f.Controls.Add(p);
    }

    Control CreateToolRowB(string icon, string title, string rightText, Action click, string tipText)
    {
        Panel row = new Panel();
        row.Dock = DockStyle.Fill;
        row.Cursor = Cursors.Hand;
        row.Margin = new Padding(0, 0, 0, UI.S(2));
        bool hover = false;

        row.MouseEnter += delegate { hover = true; row.Invalidate(); };
        row.MouseLeave += delegate { hover = false; row.Invalidate(); };

        Panel capturedRow = row;
        row.Paint += delegate(object sender, PaintEventArgs pe) {
            if (hover)
            {
                pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                Color hbg = UI.IsDark ? Color.FromArgb(46, 48, 52) : Color.FromArgb(240, 242, 246);
                using (GraphicsPath p = UI.Round(new RectangleF(0.5f, 0.5f, capturedRow.Width - 1.5f, capturedRow.Height - 1.5f), UI.SF(6)))
                using (SolidBrush b = new SolidBrush(hbg)) pe.Graphics.FillPath(b, p);
            }
        };

        Label lblIco = Lbl(icon, 11f, false, UI.Accent);
        lblIco.Font = UI.SymbolFont(11f);
        lblIco.Location = new Point(UI.S(8), UI.S(10));
        lblIco.Size = new Size(UI.S(22), UI.S(22));

        Label lblT = Lbl(title, 9f, true, UI.Text);
        lblT.Location = new Point(UI.S(36), UI.S(11));
        lblT.AutoSize = true;

        Label lblR = Lbl(rightText, 8.5f, false, UI.Muted);
        lblR.Dock = DockStyle.Right;
        lblR.TextAlign = ContentAlignment.MiddleRight;
        lblR.Padding = new Padding(0, 0, UI.S(10), 0);
        lblR.AutoSize = false;
        lblR.Width = UI.S(180);

        Tip(row, tipText);
        Tip(lblIco, tipText);
        Tip(lblT, tipText);
        Tip(lblR, tipText);

        EventHandler eh = delegate { if (click != null) click(); };
        row.Click += eh;
        lblIco.Click += eh;
        lblT.Click += eh;
        lblR.Click += eh;

        EventHandler onEnter = delegate { hover = true; capturedRow.Invalidate(); };
        EventHandler onLeave = delegate { hover = false; capturedRow.Invalidate(); };
        lblIco.MouseEnter += onEnter; lblIco.MouseLeave += onLeave;
        lblT.MouseEnter += onEnter; lblT.MouseLeave += onLeave;
        lblR.MouseEnter += onEnter; lblR.MouseLeave += onLeave;

        row.Controls.Add(lblR);
        row.Controls.Add(lblIco);
        row.Controls.Add(lblT);
        return row;
    }

    Control CreateToolItem(string icon, string title, string sub, Action click, string tipText)
    {
        Panel row = new Panel();
        row.Dock = DockStyle.Fill;
        row.Cursor = Cursors.Hand;
        row.Margin = new Padding(0);
        bool hover = false;

        row.MouseEnter += delegate { hover = true; row.Invalidate(); };
        row.MouseLeave += delegate { hover = false; row.Invalidate(); };

        Panel capturedRow = row;
        row.Paint += delegate(object sender, PaintEventArgs pe) {
            if (hover)
            {
                pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                Color hbg = UI.IsDark ? Color.FromArgb(46, 48, 52) : Color.FromArgb(240, 242, 246);
                using (GraphicsPath p = UI.Round(new RectangleF(0.5f, 0.5f, capturedRow.Width - 1.5f, capturedRow.Height - 1.5f), UI.SF(6)))
                using (SolidBrush b = new SolidBrush(hbg)) pe.Graphics.FillPath(b, p);
            }
        };

        Label lblIco = Lbl(icon, 11f, false, UI.Accent);
        lblIco.Font = UI.SymbolFont(11f);
        lblIco.Location = new Point(UI.S(6), UI.S(7));
        lblIco.Size = new Size(UI.S(22), UI.S(22));

        Label lblT = Lbl(title, 9f, true, UI.Text);
        lblT.Location = new Point(UI.S(34), UI.S(3));
        lblT.AutoSize = true;

        Label lblS = Lbl(sub, 8f, false, UI.Muted);
        lblS.Location = new Point(UI.S(34), UI.S(20));
        lblS.AutoSize = true;

        Tip(row, tipText);
        Tip(lblIco, tipText);
        Tip(lblT, tipText);
        Tip(lblS, tipText);

        EventHandler eh = delegate { if (click != null) click(); };
        row.Click += eh;
        lblIco.Click += eh;
        lblT.Click += eh;
        lblS.Click += eh;

        EventHandler onEnter = delegate { hover = true; capturedRow.Invalidate(); };
        EventHandler onLeave = delegate { hover = false; capturedRow.Invalidate(); };
        lblIco.MouseEnter += onEnter; lblIco.MouseLeave += onLeave;
        lblT.MouseEnter += onEnter; lblT.MouseLeave += onLeave;
        lblS.MouseEnter += onEnter; lblS.MouseLeave += onLeave;

        row.Controls.Add(lblIco);
        row.Controls.Add(lblT);
        row.Controls.Add(lblS);
        return row;
    }

    Control BuildStartFooter()
    {
        FlowLayoutPanel foot = new FlowLayoutPanel();
        foot.Width = UI.S(UI.Gruppenbreite);
        foot.AutoSize = true;
        foot.WrapContents = false;
        foot.BackColor = UI.Panel;
        foot.Margin = new Padding(0, UI.S(4), 0, UI.S(14));

        CheckBox chkShowStart = Chk("Beim Start diese Seite zeigen", LoadStartPagePreference());
        chkShowStart.Margin = new Padding(0, UI.S(2), UI.S(24), 0);
        Tip(chkShowStart, "Legt fest, ob beim Programmstart standardmäßig diese Startseite geöffnet wird.");
        chkShowStart.CheckedChanged += delegate {
            SaveStartPagePreference(chkShowStart.Checked);
        };
        foot.Controls.Add(chkShowStart);

        string seenVer = LoadSeenVersionPreference();
        bool isNew = (seenVer != this.version);

        LinkLabel lnkNew = new LinkLabel();
        lnkNew.Text = "Was ist neu";
        lnkNew.Font = new Font("Segoe UI", 9f);
        lnkNew.LinkColor = UI.Accent;
        lnkNew.ActiveLinkColor = UI.AccentHover;
        lnkNew.LinkBehavior = LinkBehavior.HoverUnderline;
        lnkNew.AutoSize = true;
        lnkNew.Margin = new Padding(0, UI.S(4), UI.S(6), 0);
        Tip(lnkNew, "Zeigt die Neuerungen dieser Version in der Versionshistorie.");
        lnkNew.LinkClicked += delegate {
            SaveSeenVersionPreference(this.version);
            ShowPage(versionPage);
        };
        foot.Controls.Add(lnkNew);

        if (isNew)
        {
            Badge bNew = new Badge("Neu", "info");
            bNew.Margin = new Padding(0, UI.S(4), UI.S(18), 0);
            Tip(bNew, "Neuerungen in Version " + this.version);
            foot.Controls.Add(bNew);
        }

        LinkLabel lnkGuide = new LinkLabel();
        lnkGuide.Text = "Kurzanleitung";
        lnkGuide.Font = new Font("Segoe UI", 9f);
        lnkGuide.LinkColor = UI.Accent;
        lnkGuide.ActiveLinkColor = UI.AccentHover;
        lnkGuide.LinkBehavior = LinkBehavior.HoverUnderline;
        lnkGuide.AutoSize = true;
        lnkGuide.Margin = new Padding(UI.S(12), UI.S(4), 0, 0);
        Tip(lnkGuide, "Öffnet eine kompakte Kurzanleitung zur Bedienung von Leos Minibench.");
        lnkGuide.LinkClicked += delegate {
            ShowGuideDialog();
        };
        foot.Controls.Add(lnkGuide);

        return foot;
    }

    void SelectTask(string name)
    {
        for (int i = 1; i <= 5 && i < nav.Count; i++) nav[i].Checked = false;

        if (name == "PC durchchecken")
        {
            if (nav.Count > 1) nav[1].Checked = true;
            if (nav.Count > 2) nav[2].Checked = true;
            if (nav.Count > 3) nav[3].Checked = true;
            if (rbVoll != null) rbVoll.Checked = true;
            ShowPage(1);
        }
        else if (name == "Leistung messen")
        {
            if (nav.Count > 2) nav[2].Checked = true;
            ShowPage(2);
        }
        else if (name == "Stabilität prüfen")
        {
            if (nav.Count > 3) nav[3].Checked = true;
            ShowPage(3);
        }
        else if (name == "Pflegen und beschleunigen")
        {
            if (nav.Count > 4) nav[4].Checked = true;
            if (nav.Count > 5) nav[5].Checked = true;
            ShowPage(4);
        }
        UpdateSummary();
    }

    string GetDisksSummary()
    {
        if (this.disks == null || this.disks.Length == 0)
        {
            try
            {
                DriveInfo[] drvs = DriveInfo.GetDrives();
                long tot = 0; int cnt = 0;
                foreach (DriveInfo d in drvs)
                {
                    if (d.IsReady && d.DriveType == DriveType.Fixed) { tot += d.TotalSize; cnt++; }
                }
                if (cnt > 0)
                {
                    double tb = tot / (1024.0 * 1024.0 * 1024.0 * 1024.0);
                    return String.Format("{0}x Datenträger · {1:F1} TB", cnt, tb).Replace('.', ',');
                }
            }
            catch { }
            return "Datenträger";
        }

        int nvme = 0, sataSsd = 0, hdd = 0, other = 0;
        double totalBytes = 0;
        foreach (string d in this.disks)
        {
            string[] x = d.Split('|');
            if (x.Length < 7) continue;
            string bus = x[2], med = x[3], sizeStr = x[4];
            if (bus.IndexOf("NVMe", StringComparison.OrdinalIgnoreCase) >= 0) nvme++;
            else if (med.IndexOf("SSD", StringComparison.OrdinalIgnoreCase) >= 0) sataSsd++;
            else if (med.IndexOf("HDD", StringComparison.OrdinalIgnoreCase) >= 0) hdd++;
            else other++;

            if (sizeStr.IndexOf("TB", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                double val;
                string num = sizeStr.Replace("TB", "").Trim().Replace(',', '.');
                if (double.TryParse(num, NumberStyles.Any, CultureInfo.InvariantCulture, out val)) totalBytes += val * 1024.0 * 1024.0 * 1024.0 * 1024.0;
            }
            else if (sizeStr.IndexOf("GB", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                double val;
                string num = sizeStr.Replace("GB", "").Trim().Replace(',', '.');
                if (double.TryParse(num, NumberStyles.Any, CultureInfo.InvariantCulture, out val)) totalBytes += val * 1024.0 * 1024.0 * 1024.0;
            }
        }

        List<string> parts = new List<string>();
        if (nvme > 0) parts.Add(nvme + "x NVMe");
        if (sataSsd > 0) parts.Add(sataSsd + "x SATA-SSD");
        if (hdd > 0) parts.Add(hdd + "x HDD");
        if (parts.Count == 0 && other > 0) parts.Add(other + "x Datenträger");
        if (parts.Count == 0) return "Datenträger";

        string types = String.Join(", ", parts.ToArray());
        double totTb = totalBytes / (1024.0 * 1024.0 * 1024.0 * 1024.0);
        if (totTb >= 1.0)
        {
            return String.Format("{0} · {1:F1} TB", types, totTb).Replace('.', ',');
        }
        double totGb = totalBytes / (1024.0 * 1024.0 * 1024.0);
        if (totGb > 0)
        {
            return String.Format("{0} · {1:F0} GB", types, totGb);
        }
        return types;
    }

    void StartQuickFixChecks(Panel container, bool hadLasttestOnThisPc)
    {
        if (container == null) return;
        System.ComponentModel.BackgroundWorker bw = new System.ComponentModel.BackgroundWorker();
        bw.DoWork += delegate(object sender, System.ComponentModel.DoWorkEventArgs e)
        {
            List<QuickFixItem> items = new List<QuickFixItem>();

            // 1. RAM Clock / XMP Check
            try
            {
                if (!HwIsLaptop && HwRam.Length > 0)
                {
                    if (HwRam.IndexOf("DDR4-2133", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        HwRam.IndexOf("DDR4-2400", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        QuickFixItem it = new QuickFixItem();
                        it.Level = "warn";
                        it.Badge = "Warnung";
                        it.Title = "Arbeitsspeicher läuft nur mit 2133 MT/s";
                        it.Desc = "Das XMP-Profil ist vermutlich nicht aktiv. Im BIOS einschalten, danach Lasttest Arbeitsspeicher.";
                        it.ButtonText = "Anleitung";
                        it.Action = delegate { ShowXmpInstructionsDialog(); };
                        it.Tip = "Öffnet eine Schritt-für-Schritt-Anleitung zur Aktivierung von XMP/EXPO im BIOS.";
                        items.Add(it);
                    }
                    else if (HwRam.IndexOf("DDR5-4800", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        QuickFixItem it = new QuickFixItem();
                        it.Level = "warn";
                        it.Badge = "Warnung";
                        it.Title = "Arbeitsspeicher läuft nur mit 4800 MT/s";
                        it.Desc = "Das XMP- oder EXPO-Profil ist vermutlich nicht aktiv. Im BIOS einschalten.";
                        it.ButtonText = "Anleitung";
                        it.Action = delegate { ShowXmpInstructionsDialog(); };
                        it.Tip = "Öffnet eine Schritt-für-Schritt-Anleitung zur Aktivierung von XMP/EXPO im BIOS.";
                        items.Add(it);
                    }
                }
            }
            catch { }

            // 2. Lasttest check auf diesem PC
            try
            {
                if (!hadLasttestOnThisPc)
                {
                    QuickFixItem it = new QuickFixItem();
                    it.Level = "info";
                    it.Badge = "Hinweis";
                    it.Title = "Noch kein Lasttest auf diesem PC";
                    it.Desc = "Ein Lasttest zeigt, ob Kühlung und Netzteil unter Dauerlast mithalten.";
                    it.ButtonText = "Einrichten";
                    it.Action = delegate { SelectTask("Stabilität prüfen"); };
                    it.Tip = "Wechselt zur Einrichtung des Stabilitätstests.";
                    items.Add(it);
                }
            }
            catch { }

            // 3. BIOS Date check (> 2 Jahre)
            try
            {
                using (Microsoft.Win32.RegistryKey rk = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\BIOS"))
                {
                    if (rk != null)
                    {
                        object bDate = rk.GetValue("BIOSReleaseDate");
                        if (bDate != null)
                        {
                            string sDate = bDate.ToString().Trim();
                            DateTime dtBios;
                            if (DateTime.TryParse(sDate, CultureInfo.InvariantCulture, DateTimeStyles.None, out dtBios) ||
                                DateTime.TryParse(sDate, CultureInfo.CurrentCulture, DateTimeStyles.None, out dtBios))
                            {
                                if (DateTime.Now.Subtract(dtBios).TotalDays > 730)
                                {
                                    QuickFixItem it = new QuickFixItem();
                                    it.Level = "info";
                                    it.Badge = "Hinweis";
                                    it.Title = "BIOS-Version ist über 2 Jahre alt (" + dtBios.ToString("dd.MM.yyyy") + ")";
                                    it.Desc = "Ein BIOS-Update bringt oft Fehlerbehebungen, neue CPU-Mikrocodes und Stabilitätsverbesserungen.";
                                    it.ButtonText = "Inventar";
                                    it.Action = delegate { ShowInventoryDialog(); };
                                    it.Tip = "Zeigt Mainboard-Modell und BIOS-Stand im Inventar an.";
                                    items.Add(it);
                                }
                            }
                        }
                    }
                }
            }
            catch { }

            // 4. LAN-Link 100 Mbit/s check
            try
            {
                foreach (System.Net.NetworkInformation.NetworkInterface nic in System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (nic.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up &&
                        nic.NetworkInterfaceType == System.Net.NetworkInformation.NetworkInterfaceType.Ethernet)
                    {
                        if (nic.Speed == 100000000)
                        {
                            QuickFixItem it = new QuickFixItem();
                            it.Level = "warn";
                            it.Badge = "Warnung";
                            it.Title = "LAN-Verbindung verhandelt nur 100 Mbit/s";
                            it.Desc = "Netzwerkkarte oder Switch-Port ist auf 100 Mbit/s gedrosselt (Kabel oder Port prüfen).";
                            it.ButtonText = "Prüfen";
                            it.Action = delegate {
                                try { System.Diagnostics.Process.Start("ncpa.cpl"); } catch { }
                            };
                            it.Tip = "Öffnet die Windows-Netzwerkverbindungen zur Überprüfung der Verbindungseigenschaften.";
                            items.Add(it);
                            break;
                        }
                    }
                }
            }
            catch { }

            e.Result = items;
        };

        bw.RunWorkerCompleted += delegate(object sender, System.ComponentModel.RunWorkerCompletedEventArgs e)
        {
            if (e.Error != null || container.IsDisposed) return;
            List<QuickFixItem> items = e.Result as List<QuickFixItem>;
            if (items == null) return;

            container.SuspendLayout();
            container.Controls.Clear();

            if (items.Count == 0)
            {
                Label lblOk = Lbl("Keine Auffälligkeiten erkannt. Das System ist optimal konfiguriert.", 9f, false, UI.Ok);
                lblOk.Location = new Point(0, UI.S(16));
                lblOk.AutoSize = true;
                Tip(lblOk, "Alle schnellen Konfigurationsprüfungen sind unauffällig.");
                container.Controls.Add(lblOk);
            }
            else
            {
                int curY = 0;
                for (int i = 0; i < items.Count && i < 2; i++)
                {
                    QuickFixItem it = items[i];
                    Panel row = new Panel();
                    row.Location = new Point(0, curY);
                    row.Width = Math.Max(UI.S(300), container.ClientSize.Width);
                    row.Height = UI.S(54);
                    row.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right;

                    Color bbg = it.Level == "warn" ? (UI.IsDark ? Color.FromArgb(54, 44, 18) : Color.FromArgb(254, 249, 231)) : (UI.IsDark ? Color.FromArgb(22, 40, 60) : Color.FromArgb(235, 243, 250));
                    Color borderColor = it.Level == "warn" ? (UI.IsDark ? Color.FromArgb(217, 155, 0) : Color.FromArgb(190, 135, 0)) : (UI.IsDark ? Color.FromArgb(0, 120, 212) : Color.FromArgb(0, 100, 180));

                    Panel capturedRow = row;
                    row.Paint += delegate(object s, PaintEventArgs pe) {
                        pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                        using (GraphicsPath rp = UI.Round(new RectangleF(0.5f, 0.5f, capturedRow.Width - 1.5f, capturedRow.Height - 1.5f), UI.SF(6)))
                        {
                            using (SolidBrush rb = new SolidBrush(bbg)) pe.Graphics.FillPath(rb, rp);
                            using (Pen rpen = new Pen(borderColor)) pe.Graphics.DrawPath(rpen, rp);
                        }
                    };

                    Badge badge = new Badge(it.Badge, it.Level);
                    badge.Location = new Point(UI.S(10), UI.S(12));
                    Tip(badge, it.Badge + ": " + it.Title);

                    int textX = UI.S(84);
                    int textW = Math.Max(UI.S(100), row.Width - textX - UI.S(80));

                    Label lblT = Lbl(it.Title, 8.75f, true, UI.Text);
                    lblT.AutoSize = false;
                    lblT.Location = new Point(textX, UI.S(8));
                    lblT.Size = new Size(textW, UI.S(18));
                    lblT.AutoEllipsis = true;
                    lblT.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right;
                    Tip(lblT, it.Title);

                    Label lblD = Lbl(it.Desc, 7.75f, false, UI.Muted);
                    lblD.AutoSize = false;
                    lblD.Location = new Point(textX, UI.S(27));
                    lblD.Size = new Size(textW, UI.S(24));
                    lblD.AutoEllipsis = true;
                    lblD.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right;
                    Tip(lblD, it.Desc);

                    LinkLabel lnkAct = new LinkLabel();
                    lnkAct.Text = it.ButtonText;
                    lnkAct.Font = new Font("Segoe UI Semibold", 8.75f);
                    lnkAct.LinkColor = UI.Accent;
                    lnkAct.ActiveLinkColor = UI.AccentHover;
                    lnkAct.LinkBehavior = LinkBehavior.HoverUnderline;
                    lnkAct.AutoSize = false;
                    lnkAct.Size = new Size(UI.S(72), UI.S(20));
                    lnkAct.TextAlign = ContentAlignment.MiddleRight;
                    lnkAct.Location = new Point(row.Width - UI.S(80), UI.S(17));
                    lnkAct.Anchor = AnchorStyles.Right | AnchorStyles.Top;
                    Tip(lnkAct, it.Tip);
                    QuickFixItem capturedIt = it;
                    lnkAct.LinkClicked += delegate { if (capturedIt.Action != null) capturedIt.Action(); };

                    row.Resize += delegate {
                        int w = Math.Max(UI.S(100), capturedRow.Width - textX - UI.S(80));
                        lblT.Size = new Size(w, UI.S(18));
                        lblD.Size = new Size(w, UI.S(24));
                        lnkAct.Location = new Point(capturedRow.Width - UI.S(80), UI.S(17));
                    };

                    row.Controls.Add(badge);
                    row.Controls.Add(lblT);
                    row.Controls.Add(lblD);
                    row.Controls.Add(lnkAct);
                    container.Controls.Add(row);

                    curY += UI.S(60);
                }
            }
            container.ResumeLayout(true);
        };

        bw.RunWorkerAsync();
    }

    void ShowInventoryDialog()
    {
        using (Form dlg = new Form())
        {
            dlg.Text = "Hardware-Inventar";
            dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
            dlg.MaximizeBox = false; dlg.MinimizeBox = false;
            dlg.StartPosition = FormStartPosition.CenterParent;
            dlg.ClientSize = new Size(UI.S(560), UI.S(400));
            dlg.BackColor = UI.Bg; dlg.Font = new Font("Segoe UI", 9.5f);

            Panel p = new Panel(); p.Dock = DockStyle.Fill; p.Padding = new Padding(UI.S(16)); p.BackColor = UI.Bg;
            Label lt = Lbl("Übersicht der erkannten Hardware", 12f, true, UI.Text);
            lt.Dock = DockStyle.Top; lt.Height = UI.S(32); p.Controls.Add(lt);

            TableLayoutPanel t = new TableLayoutPanel();
            t.Dock = DockStyle.Fill; t.ColumnCount = 2; t.AutoScroll = true;
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, UI.S(140)));
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));

            string cleanCpu = DbEntry.CleanCpuName(HwCpu);
            string cpuVal = cleanCpu.Length > 0 ? (cleanCpu + (HwCores > 0 ? " (" + HwCores + " Kerne, " + HwThreads + " Threads)" : "")) : "Standard-Prozessor";

            string[][] rows = new string[][] {
                new string[] { "Computer", Environment.MachineName },
                new string[] { "Betriebssystem", OsName() },
                new string[] { "Prozessor", cpuVal },
                new string[] { "Mainboard", HwBoard.Length > 0 ? HwBoard : "Standard-Mainboard" },
                new string[] { "Arbeitsspeicher", HwRam.Length > 0 ? HwRam : "Arbeitsspeicher" },
                new string[] { "Grafik", GpuNames.Length > 0 ? String.Join(", ", GpuNames) : "Standard-Grafik" },
                new string[] { "Datenträger", GetDisksSummary() }
            };

            for (int i = 0; i < rows.Length; i++)
            {
                Label lKey = Lbl(rows[i][0], 9.25f, true, UI.Muted);
                lKey.Margin = new Padding(0, UI.S(6), UI.S(8), UI.S(6));
                Label lVal = Lbl(rows[i][1], 9.25f, false, UI.Text);
                lVal.Margin = new Padding(0, UI.S(6), 0, UI.S(6));
                t.Controls.Add(lKey, 0, i);
                t.Controls.Add(lVal, 1, i);
            }

            FlowLayoutPanel bf = new FlowLayoutPanel(); bf.Dock = DockStyle.Bottom; bf.Height = UI.S(44); bf.FlowDirection = FlowDirection.RightToLeft;
            Button btnClose = UI.Primary("Schließen"); btnClose.DialogResult = DialogResult.OK;
            Tip(btnClose, "Schließt das Inventarfenster.");
            bf.Controls.Add(btnClose);

            p.Controls.Add(t);
            t.BringToFront();
            p.Controls.Add(bf);
            dlg.Controls.Add(p);
            dlg.AcceptButton = btnClose;
            UI.ThemeDialog(dlg);
            dlg.ShowDialog(this);
        }
    }

    void ShowGuideDialog()
    {
        using (Form dlg = new Form())
        {
            dlg.Text = "Kurzanleitung";
            dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
            dlg.MaximizeBox = false; dlg.MinimizeBox = false;
            dlg.StartPosition = FormStartPosition.CenterParent;
            dlg.ClientSize = new Size(UI.S(540), UI.S(420));
            dlg.BackColor = UI.Bg; dlg.Font = new Font("Segoe UI", 9.5f);

            Panel p = new Panel(); p.Dock = DockStyle.Fill; p.Padding = new Padding(UI.S(16)); p.BackColor = UI.Bg;
            Label lt = Lbl("So bedienst du Leos Minibench", 12f, true, UI.Text);
            lt.Dock = DockStyle.Top; lt.Height = UI.S(32); p.Controls.Add(lt);

            RichTextBox rt = new RichTextBox(); rt.ReadOnly = true; rt.BorderStyle = BorderStyle.None; rt.BackColor = UI.Bg; rt.ForeColor = UI.Text;
            rt.Dock = DockStyle.Fill; rt.Font = new Font("Segoe UI", 9.5f);
            Font fh = new Font("Segoe UI Semibold", 10f); Font fb = new Font("Segoe UI", 9f);

            string[][] steps = new string[][] {
                new string[] { "1. Ablauf wählen", "Hake in der linken Leiste die gewünschten Module an (Diagnose, Benchmark, Lasttest, Wartung oder Optimierung). Du kannst mehrere Module beliebig kombinieren." },
                new string[] { "2. Starten", "Klicke unten rechts auf den Startknopf. Vor dem Start zeigt die Leiste die geschätzte Gesamtdauer aller gewählten Prüfungen an." },
                new string[] { "3. Bericht lesen", "Nach Abschluss öffnet sich automatisch der detaillierte HTML-Bericht. Alle Befunde sind nach Dringlichkeit (Kritisch, Warnung, Hinweis) gegliedert." },
                new string[] { "4. Änderungen rückgängig machen", "Wartungs- und Optimierungsmaßnahmen werden im Änderungsprotokoll erfasst und können auf der Seite Systemänderungen einzeln zurückgenommen werden." }
            };

            foreach (string[] st in steps)
            {
                rt.SelectionFont = fh; rt.SelectionColor = UI.Text;
                rt.AppendText(st[0] + "\r\n");
                rt.SelectionFont = fb; rt.SelectionColor = UI.Muted;
                rt.AppendText(st[1] + "\r\n\r\n");
            }
            rt.SelectionStart = 0; rt.ScrollToCaret();

            FlowLayoutPanel bf = new FlowLayoutPanel(); bf.Dock = DockStyle.Bottom; bf.Height = UI.S(44); bf.FlowDirection = FlowDirection.RightToLeft;
            Button btnClose = UI.Primary("Schließen"); btnClose.DialogResult = DialogResult.OK;
            Tip(btnClose, "Schließt die Kurzanleitung.");
            bf.Controls.Add(btnClose);

            p.Controls.Add(rt);
            rt.BringToFront();
            p.Controls.Add(bf);
            dlg.Controls.Add(p);
            dlg.AcceptButton = btnClose;
            UI.ThemeDialog(dlg);
            dlg.ShowDialog(this);
        }
    }

    void ShowXmpInstructionsDialog()
    {
        using (Form dlg = new Form())
        {
            dlg.Text = "XMP / EXPO im BIOS aktivieren";
            dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
            dlg.MaximizeBox = false; dlg.MinimizeBox = false;
            dlg.StartPosition = FormStartPosition.CenterParent;
            dlg.ClientSize = new Size(UI.S(540), UI.S(400));
            dlg.BackColor = UI.Bg; dlg.Font = new Font("Segoe UI", 9.5f);

            Panel p = new Panel(); p.Dock = DockStyle.Fill; p.Padding = new Padding(UI.S(16)); p.BackColor = UI.Bg;
            Label lt = Lbl("Arbeitsspeicher mit voller Geschwindigkeit betreiben", 12f, true, UI.Text);
            lt.Dock = DockStyle.Top; lt.Height = UI.S(32); p.Controls.Add(lt);

            RichTextBox rt = new RichTextBox(); rt.ReadOnly = true; rt.BorderStyle = BorderStyle.None; rt.BackColor = UI.Bg; rt.ForeColor = UI.Text;
            rt.Dock = DockStyle.Fill; rt.Font = new Font("Segoe UI", 9.5f);
            Font fh = new Font("Segoe UI Semibold", 10f); Font fb = new Font("Segoe UI", 9f);

            string[][] steps = new string[][] {
                new string[] { "Warum ist das wichtig?", "Ohne XMP oder EXPO läuft der Arbeitsspeicher nur mit dem JEDEC-Basistakt (z. B. 2133 MT/s bei DDR4 oder 4800 MT/s bei DDR5). Dadurch verschenkst du spürbar Prozessor- und Spieleleistung." },
                new string[] { "Schritt 1: BIOS aufrufen", "Starte den Computer neu und drücke beim Einschalten wiederholt die Taste Entf oder F2, um ins BIOS bzw. UEFI zu gelangen." },
                new string[] { "Schritt 2: Profil auswählen", "Suche im Menü nach der Option XMP (Intel/manche AMD), DOCP (ASUS AMD) oder EXPO (AMD DDR5) und wähle Profil 1." },
                new string[] { "Schritt 3: Speichern und neu starten", "Drücke Taste F10 zum Speichern und Neustarten. Windows startet nun mit dem höheren Speichertakt." },
                new string[] { "Schritt 4: Stabilität prüfen", "Führe in Leos Minibench einen Lasttest für den Arbeitsspeicher durch, um sicherzustellen, dass das System absolut stabil arbeitet." }
            };

            foreach (string[] st in steps)
            {
                rt.SelectionFont = fh; rt.SelectionColor = UI.Text;
                rt.AppendText(st[0] + "\r\n");
                rt.SelectionFont = fb; rt.SelectionColor = UI.Muted;
                rt.AppendText(st[1] + "\r\n\r\n");
            }
            rt.SelectionStart = 0; rt.ScrollToCaret();

            FlowLayoutPanel bf = new FlowLayoutPanel(); bf.Dock = DockStyle.Bottom; bf.Height = UI.S(44); bf.FlowDirection = FlowDirection.RightToLeft;
            Button btnClose = UI.Primary("Schließen"); btnClose.DialogResult = DialogResult.OK;
            Tip(btnClose, "Schließt die Anleitung.");
            bf.Controls.Add(btnClose);

            p.Controls.Add(rt);
            rt.BringToFront();
            p.Controls.Add(bf);
            dlg.Controls.Add(p);
            dlg.AcceptButton = btnClose;
            UI.ThemeDialog(dlg);
            dlg.ShowDialog(this);
        }
    }
}

