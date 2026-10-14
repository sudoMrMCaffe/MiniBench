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
}
