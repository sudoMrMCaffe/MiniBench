<# : batch
@echo off
setlocal
title Leos Minibench bauen
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([IO.File]::ReadAllText('%~f0', [Text.Encoding]::UTF8))) '%~dp0' '%~1'"
set rc=%errorlevel%
echo.
pause
exit /b %rc%
: #>
param([string]$Here, [string]$A1 = '')
# Baut Leos Minibench aus dem Ordner src in den Ordner "Aktueller Build":
#   1. fügt src laut src\Bauplan.txt zusammen und prüft die Syntax
#   2. führt die Pester-Tests in tests aus (falls Pester 5 installiert ist); bei Fehlern bleibt der Aktuelle Build unverändert
#   3. baut die exe und legt exe, ps1, LeosMinibench.cmd und Stand.txt in "Aktueller Build"
#   4. ab v2.7: verschiebt den vorigen Build nach Archiv\v<alte Version> und räumt die Daten im Aktuellen Build auf
#      (Datenpflege: Lasttests vor v2.67, unvollständige und kurze Läufe nach Archiv\Minibench-Daten)
#   5. passt README.md automatisch an die gebaute Version an
# Aufruf: Bauen.cmd [ohnetests]
# Benötigt nur Windows (csc.exe des .NET Framework 4), keine Downloads.
$ohneTests = ([string]$A1).Trim().ToLowerInvariant() -eq 'ohnetests'

$launcher = @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Leos Minibench")]
[assembly: AssemblyProduct("Leos Minibench")]
[assembly: AssemblyDescription("Diagnose, Benchmark, Lasttest, Reparatur und Sensoren für Windows")]
[assembly: AssemblyVersion("@@VERSION@@")]
[assembly: AssemblyFileVersion("@@VERSION@@")]

// Startfenster (ab v2.6, Roadmap v2.5): erscheint sofort nach dem Doppelklick, zeigt Symbol, Version und die Startphase,
// bis die Oberfläche gezeichnet ist (benanntes Ereignis LEOSMINIBENCH_BEREIT) oder PowerShell endet.
class Splash : Form
{
    Label status;
    ProgressBar bar;
    public Splash(string version)
    {
        FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.CenterScreen; ShowInTaskbar = true;
        Text = "Leos Minibench"; BackColor = Color.FromArgb(17, 24, 39); ForeColor = Color.White;
        ClientSize = new Size(440, 168); Font = new Font("Segoe UI", 9.75f);
        PictureBox pb = new PictureBox(); pb.Size = new Size(72, 72); pb.Location = new Point(24, 26); pb.SizeMode = PictureBoxSizeMode.Zoom;
        // Symbol aus der eingebetteten ico-Datei (alle Größen), sonst aus der exe
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
        try { using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Symbol.png")) pb.Image = new Bitmap(Image.FromStream(s)); }
        catch { try { pb.Image = Icon.ToBitmap(); } catch { } }
        Label t = new Label(); t.Text = "Leos Minibench"; t.Font = new Font("Segoe UI Semibold", 17f); t.AutoSize = true; t.Location = new Point(108, 26); t.ForeColor = Color.White;
        Label v = new Label(); v.Text = "Version " + version; v.AutoSize = true; v.Location = new Point(111, 64); v.ForeColor = Color.FromArgb(160, 174, 192);
        status = new Label(); status.Text = "wird gestartet ..."; status.AutoSize = false; status.Size = new Size(392, 20); status.Location = new Point(24, 112); status.ForeColor = Color.FromArgb(203, 213, 225);
        bar = new ProgressBar(); bar.Location = new Point(24, 136); bar.Size = new Size(392, 10); bar.Style = ProgressBarStyle.Continuous; bar.Maximum = 100;
        Controls.Add(pb); Controls.Add(t); Controls.Add(v); Controls.Add(status); Controls.Add(bar);
    }
    public void SetStatus(string text, int percent)
    {
        if (text != null && status.Text != text) status.Text = text;
        int p = Math.Max(0, Math.Min(100, percent));
        if (bar.Value != p) bar.Value = p;
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        using (Pen p = new Pen(Color.FromArgb(37, 99, 235), 2)) e.Graphics.DrawRectangle(p, 1, 1, ClientSize.Width - 2, ClientSize.Height - 2);
    }
}

static class Program
{
    static string statusFile;

    // Argument nach den Regeln von CommandLineToArgvW: Backslashes vor einem Anführungszeichen und am Ende verdoppeln
    static string Quote(string s)
    {
        if (s.Length > 0 && s.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) return s;
        StringBuilder b = new StringBuilder("\"");
        int bs = 0;
        foreach (char c in s)
        {
            if (c == '\\') { bs++; continue; }
            if (c == '"') { b.Append('\\', bs * 2 + 1); b.Append('"'); }
            else { b.Append('\\', bs); b.Append(c); }
            bs = 0;
        }
        b.Append('\\', bs * 2);
        b.Append('"');
        return b.ToString();
    }

    // Startphase in die Statusdatei (Zeitstempel|Quelle|Text), Quelle L = exe
    static void Phase(DateTime t, string text)
    {
        if (statusFile == null) return;
        try { File.AppendAllText(statusFile, t.Ticks.ToString(System.Globalization.CultureInfo.InvariantCulture) + "|L|" + text + "\r\n", Encoding.UTF8); } catch { }
    }

    static bool Alive(string file, string prefix)
    {
        int pid; string n = Path.GetFileNameWithoutExtension(file);
        if (!n.StartsWith(prefix) || !int.TryParse(n.Substring(prefix.Length), out pid)) return true;
        try { using (Process op = Process.GetProcessById(pid)) { return !op.HasExited && op.ProcessName.StartsWith("LeosMinibench", StringComparison.OrdinalIgnoreCase); } } catch { return false; }
    }

    [STAThread]
    static int Main(string[] args)
    {
        DateTime t0 = DateTime.Now;
        try { t0 = Process.GetCurrentProcess().StartTime; } catch { }
        string exe = Assembly.GetExecutingAssembly().Location;
        string exeDir = Path.GetDirectoryName(exe);
        string dataDir = Path.Combine(exeDir, "Minibench-Daten");
        string oldData = Path.Combine(exeDir, "PC-Diagnose-Daten");
        try { if (!Directory.Exists(dataDir) && Directory.Exists(oldData)) Directory.Move(oldData, dataDir); } catch { }

        // Startfenster zuerst, vor allem anderen
        Application.EnableVisualStyles();
        Splash sp = new Splash("@@VERSION_TEXT@@");
        sp.Show(); sp.Refresh(); Application.DoEvents();

        int me = Process.GetCurrentProcess().Id;
        string tmpBase = Path.Combine(Path.GetTempPath(), "LeosMinibench");
        try { Directory.CreateDirectory(tmpBase); statusFile = Path.Combine(tmpBase, "Start_" + me + ".log"); File.WriteAllText(statusFile, "", Encoding.UTF8); } catch { statusFile = null; }
        Phase(t0, "Programm gestartet");
        Phase(DateTime.Now, "Startfenster sichtbar");

        // Reste früherer Starts entfernen: entpackte Skripte und Statusdateien, deren Prozess nicht mehr läuft
        foreach (string d in new string[] { Path.Combine(dataDir, "Laufzeit"), tmpBase })
        {
            try
            {
                if (!Directory.Exists(d)) continue;
                foreach (string old in Directory.GetFiles(d, "LeosMinibench_*.ps1")) if (!Alive(old, "LeosMinibench_")) { try { File.Delete(old); } catch { } }
                foreach (string old in Directory.GetFiles(d, "Start_*.log")) if (!Alive(old, "Start_")) { try { File.Delete(old); } catch { } }
            }
            catch { }
        }

        // Skript entpacken: bevorzugt ins lokale TEMP (schnell, schont den Stick), sonst in den Datenordner
        string ps1 = null, runDir = null;
        foreach (string d in new string[] { tmpBase, Path.Combine(dataDir, "Laufzeit") })
        {
            try
            {
                Directory.CreateDirectory(d);
                string f = Path.Combine(d, "LeosMinibench_" + me + ".ps1");
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("LeosMinibench.ps1"))
                using (FileStream fs = File.Create(f)) { s.CopyTo(fs); }
                ps1 = f; runDir = d; break;
            }
            catch { }
        }
        if (ps1 == null)
        {
            sp.Close();
            MessageBox.Show("Das Skript konnte weder im TEMP-Ordner noch neben der exe abgelegt werden.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        Phase(DateTime.Now, runDir == tmpBase ? "Skript entpackt (lokales TEMP)" : "Skript entpackt (Datenordner)");

        StringBuilder extra = new StringBuilder();
        foreach (string a in args) extra.Append(' ').Append(Quote(a));
        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        if (!File.Exists(ps)) ps = "powershell.exe";

        string evName = "Local\\LeosMinibench-Bereit-" + me;
        EventWaitHandle ready = null;
        try { ready = new EventWaitHandle(false, EventResetMode.ManualReset, evName); } catch { ready = null; }
        ProcessStartInfo psi = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " + Quote(ps1) + " -DatenDir " + Quote(dataDir) + extra.ToString());
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        if (statusFile != null) psi.EnvironmentVariables["LEOSMINIBENCH_START"] = statusFile;
        psi.EnvironmentVariables["LEOSMINIBENCH_EXE"] = exe;
        if (ready != null) psi.EnvironmentVariables["LEOSMINIBENCH_BEREIT"] = evName;
        int code;
        try
        {
            DateTime ts = DateTime.Now;
            using (Process p = Process.Start(psi))
            {
                Phase(DateTime.Now, "PowerShell gestartet");
                // Startfenster stehen lassen, bis die Oberfläche gezeichnet ist (oder PowerShell endet, höchstens 3 Minuten)
                System.Windows.Forms.Timer tm = new System.Windows.Forms.Timer(); tm.Interval = 120;
                long seen = 0; int phases = 4; string last = "PowerShell startet ...";
                tm.Tick += delegate
                {
                    bool fin = (ready != null && ready.WaitOne(0)) || p.HasExited || (DateTime.Now - ts).TotalSeconds > 180;
                    if (!fin && statusFile != null)
                    {
                        try
                        {
                            FileInfo fi = new FileInfo(statusFile);
                            if (fi.Exists && fi.Length != seen)
                            {
                                seen = fi.Length;
                                // mit FileShare.ReadWrite lesen, damit Skript und Oberfläche gleichzeitig anhängen können
                                string[] ls;
                                using (FileStream rs = new FileStream(statusFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                                using (StreamReader rd = new StreamReader(rs, Encoding.UTF8)) ls = rd.ReadToEnd().Split(new string[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
                                phases = ls.Length;
                                for (int i = ls.Length - 1; i >= 0; i--) { string[] x = ls[i].Split(new char[] { '|' }, 3); if (x.Length == 3) { last = x[2]; break; } }
                            }
                        }
                        catch { }
                    }
                    if (fin) { tm.Stop(); sp.Close(); }
                    else sp.SetStatus(last, (int)(phases * 100.0 / 12.0));
                };
                tm.Start();
                Application.Run(sp);
                p.WaitForExit(); code = p.ExitCode;
            }
            if (code != 0 && (DateTime.Now - ts).TotalSeconds < 20)
                MessageBox.Show("PowerShell wurde mit Code " + code + " beendet. Bitte LeosMinibench.cmd verwenden oder die Ausführung von PowerShell-Skripten prüfen.", "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        catch (Exception ex)
        {
            try { sp.Close(); } catch { }
            MessageBox.Show("PowerShell konnte nicht gestartet werden: " + ex.Message, "Leos Minibench", MessageBoxButtons.OK, MessageBoxIcon.Error);
            code = 1;
        }
        // entpacktes Skript, Statusdatei und leere Ordner wieder entfernen
        try { File.Delete(ps1); } catch { }
        try { if (statusFile != null) File.Delete(statusFile); } catch { }
        try { if (Directory.GetFileSystemEntries(runDir).Length == 0) Directory.Delete(runDir); } catch { }
        try { if (Directory.Exists(tmpBase) && Directory.GetFileSystemEntries(tmpBase).Length == 0) Directory.Delete(tmpBase); } catch { }
        if (ready != null) ready.Dispose();
        return code;
    }
}
'@

$manifest = @'
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="LeosMinibench.app"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2, PerMonitor</dpiAwareness>
    </windowsSettings>
  </application>
</assembly>
'@

# Programmsymbol (blaues L als Rakete, ab v2.6): src\Oberflaeche\Symbol.ico, Entwürfe in Doku\Symbol

Write-Host ''
Write-Host '  Leos Minibench wird gebaut' -ForegroundColor Cyan
Write-Host ''
$work = ''
try {
    if (-not $Here) { $Here = (Get-Location).Path }
    $Here = $Here.TrimEnd('\')
    $sysMod = Join-Path $env:windir 'system32\WindowsPowerShell\v1.0\Modules'
    $userMod = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'
    $progMod = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
    $modPaths = @($userMod, $progMod, $sysMod) | Where-Object { Test-Path -LiteralPath $_ }
    if ($modPaths.Count) { $env:PSModulePath = ($modPaths + ($env:PSModulePath -split ';' | Where-Object { $_ })) -join ';' }
    $srcDir = Join-Path $Here 'src'
    $build = Join-Path $Here 'Aktueller Build'
    if (-not (Test-Path (Join-Path $srcDir 'Bauplan.txt'))) { throw ('Der Quelltextordner src mit Bauplan.txt fehlt in {0}.' -f $Here) }

    # 1. Zusammenbau (erst im Speicher; geschrieben wird nur ein vollständiger, geprüfter Stand)
    . (Join-Path $srcDir 'Zusammenbau.ps1')
    $r = Invoke-MinibenchBuild -SrcDir $srcDir
    foreach ($w in $r.Warnungen) { Write-Host ('  Hinweis  : {0}' -f $w) -ForegroundColor Yellow }
    if ($r.Fehler.Count) {
        foreach ($e in $r.Fehler) { Write-Host ('  FEHLER   : {0}' -f $e) -ForegroundColor Red }
        throw 'Der Zusammenbau ist fehlgeschlagen, der Aktuelle Build bleibt unverändert.'
    }
    $ver = $r.Version
    $notes = Join-Path $Here ('Doku\Änderungen_v{0}.txt' -f $ver)
    if (-not (Test-Path -LiteralPath $notes)) { throw ('Doku\Änderungen_v{0}.txt fehlt. Zu jeder Version gehört eine Änderungsdatei.' -f $ver) }
    Write-Host ('  Skript   : Version {0}, {1} Teile, {2:N0} Zeilen' -f $ver, $r.Teile.Count, $r.Zeilen)

    # 2. Tests
    $testInfo = ''
    if ($ohneTests) {
        $testInfo = 'nicht ausgeführt (Bauen.cmd ohnetests)'
        Write-Host '  Tests    : übersprungen (ohnetests)' -ForegroundColor Yellow
    } else {
        $runner = Join-Path $Here 'tests\Testen.ps1'
        $sumFile = Join-Path $env:TEMP ('LeosMinibench-Tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Kurz -Zusammenfassung $sumFile
        $tc = $LASTEXITCODE
        $sum = ''; if (Test-Path -LiteralPath $sumFile) { $sum = ([IO.File]::ReadAllText($sumFile)).Trim(); Remove-Item -LiteralPath $sumFile -Force -ErrorAction SilentlyContinue }
        if ($tc -eq 99) { $testInfo = 'nicht ausgeführt (Pester 5 fehlt)'; Write-Host '  Tests    : Pester 5 fehlt, Tests übersprungen (siehe oben)' -ForegroundColor Yellow }
        elseif ($tc -ne 0) { throw ('{0} Tests sind fehlgeschlagen. Der Aktuelle Build bleibt unverändert (Bauen.cmd ohnetests erzwingt den Bau).' -f $tc) }
        else { $testInfo = $(if ($sum) { $sum } else { 'alle bestanden' }); Write-Host ('  Tests    : {0}' -f $testInfo) -ForegroundColor Green }
    }

    # 3. exe in einem Arbeitsordner bauen
    $csc = @("$env:windir\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:windir\Microsoft.NET\Framework\v4.0.30319\csc.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $csc) { throw 'Der C#-Compiler des .NET Framework 4 (csc.exe) wurde nicht gefunden.' }
    Write-Host ('  Compiler : {0}' -f $csc)
    # Dateiversion: Nachkommastellen zweistellig (2.7 wird 2.70, liegt also nach 2.67)
    $vp = @(($ver -split '\.') + @('0', '0', '0', '0'))[0..3]
    if ($vp[1].Length -eq 1) { $vp[1] = $vp[1] + '0' }
    $asmVer = ($vp | ForEach-Object { [int]$_ }) -join '.'
    $work = Join-Path $env:TEMP ('LeosMinibench-Build-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $utf8Bom = New-Object Text.UTF8Encoding($true)
    $fPs1 = Join-Path $work 'LeosMinibench.ps1'; $fCs = Join-Path $work 'Launcher.cs'
    $fMan = Join-Path $work 'app.manifest';    $fIco = Join-Path $work 'app.ico'; $fExe = Join-Path $work 'LeosMinibench.exe'
    [IO.File]::WriteAllText($fPs1, $r.Text, $utf8Bom)
    [IO.File]::WriteAllText($fCs, $launcher.Replace('@@VERSION@@', $asmVer).Replace('@@VERSION_TEXT@@', $ver), $utf8Bom)
    [IO.File]::WriteAllText($fMan, $manifest, $utf8Bom)
    $icoSrc = Join-Path $srcDir 'Oberflaeche\Symbol.ico'
    if (-not (Test-Path -LiteralPath $icoSrc)) { throw ('Das Programmsymbol {0} fehlt.' -f $icoSrc) }
    Copy-Item -LiteralPath $icoSrc -Destination $fIco -Force
    $cscArgs = '/nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll ' +
               ('/out:"{0}" /win32manifest:"{1}" /win32icon:"{2}" /resource:"{3}",LeosMinibench.ps1 /resource:"{5}",Symbol.png "{4}"' -f $fExe, $fMan, $fIco, $fPs1, $fCs, (Join-Path $srcDir 'Oberflaeche\Symbol.png'))
    $psi = New-Object System.Diagnostics.ProcessStartInfo($csc, $cscArgs)
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync(); $stdout = $p.StandardOutput.ReadToEnd(); $stderr = $errTask.Result
    $p.WaitForExit()
    if ($p.ExitCode -ne 0 -or -not (Test-Path $fExe)) { Write-Host $stdout; Write-Host $stderr; throw ('csc.exe hat den Fehlercode {0} gemeldet.' -f $p.ExitCode) }

    # 4. in "Aktueller Build" übernehmen. Ein dort vorhandener Ordner Minibench-Daten bleibt unberührt.
    New-Item -ItemType Directory -Path $build -Force | Out-Null
    $exe = Join-Path $build 'LeosMinibench.exe'
    # ab v2.7: Der vorige Build (andere Version) wandert nach Archiv\v<alte Version>: exe, ps1, Stand und Änderungsdatei.
    # Gleiche Version (neuer Bau desselben Stands) wird wie bisher ersetzt.
    $oldVer = ''
    $oldStand = Join-Path $build 'Stand.txt'
    if (Test-Path -LiteralPath $oldStand) { $st0 = [IO.File]::ReadAllText($oldStand); if ($st0 -match 'Version\s*:\s*([\d.]+)') { $oldVer = $Matches[1] } }
    if ($oldVer -and $oldVer -ne $ver -and (Test-Path -LiteralPath $exe)) {
        $arc = Join-Path $Here ('Archiv\v{0}' -f $oldVer)
        New-Item -ItemType Directory -Path $arc -Force | Out-Null
        $moves = @(@('LeosMinibench.exe', 'LeosMinibench.exe'), @('LeosMinibench.ps1', 'LeosMinibench.ps1'), @('Stand.txt', ('Stand_v{0}.txt' -f $oldVer)), @(('Änderungen_v{0}.txt' -f $oldVer), ('Änderungen_v{0}.txt' -f $oldVer)))
        foreach ($m in $moves) {
            $src = Join-Path $build $m[0]; $dst = Join-Path $arc $m[1]
            if (-not (Test-Path -LiteralPath $src)) { continue }
            if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue; continue }
            try { Move-Item -LiteralPath $src -Destination $dst -ErrorAction Stop } catch { throw ('{0} lässt sich nicht nach {1} verschieben ({2}). Leos Minibench schließen und erneut bauen.' -f $src, $arc, $_.Exception.Message) }
        }
        Write-Host ('  Archiv   : Version {0} nach {1} verschoben' -f $oldVer, $arc)
    }
    if (Test-Path $exe) { try { Remove-Item $exe -Force -ErrorAction Stop } catch { throw ('{0} ist noch geöffnet. Leos Minibench schließen und erneut bauen.' -f $exe) } }
    Copy-Item -LiteralPath $fExe -Destination $exe -Force
    Copy-Item -LiteralPath $fPs1 -Destination (Join-Path $build 'LeosMinibench.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $srcDir 'LeosMinibench.cmd') -Destination (Join-Path $build 'LeosMinibench.cmd') -Force
    # ab v2.7 ohne Änderungsdatei: Sie liegt in Doku, die Versionshistorie steht im Programm (Seite Versionen)
    Get-ChildItem -LiteralPath $build -Filter 'Änderungen_v*.txt' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $files = @('LeosMinibench.exe', 'LeosMinibench.ps1', 'LeosMinibench.cmd')
    $st = New-Object System.Text.StringBuilder
    [void]$st.AppendLine('LEOS MINIBENCH: AKTUELLER BUILD')
    [void]$st.AppendLine('===============================')
    [void]$st.AppendLine(('Version   : {0} (Dateiversion {1})' -f $ver, $asmVer))
    [void]$st.AppendLine(('Gebaut    : {0:dd.MM.yyyy HH:mm} auf {1}' -f (Get-Date), $env:COMPUTERNAME))
    [void]$st.AppendLine(('Tests     : {0}' -f $testInfo))
    [void]$st.AppendLine(('Quelltext : {0} Teile aus src, {1:N0} Zeilen' -f $r.Teile.Count, $r.Zeilen))
    [void]$st.AppendLine('')
    function Get-Sha256Hex([string]$Path) {
        if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
            try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } catch { }
        }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            $bytes = $sha.ComputeHash($fs)
            return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
        } finally { $fs.Dispose(); $sha.Dispose() }
    }
    [void]$st.AppendLine('Dateien (SHA-256 zur Kontrolle auf dem Stick: Get-FileHash <Datei>)')
    foreach ($f in $files) {
        $fi = Get-Item -LiteralPath (Join-Path $build $f)
        [void]$st.AppendLine(('  {0,-22} {1,8:N0} KB  {2}' -f $f, [math]::Ceiling($fi.Length / 1KB), (Get-Sha256Hex $fi.FullName)))
    }
    [void]$st.AppendLine('')
    [void]$st.AppendLine('Für den USB-Stick: den Inhalt dieses Ordners auf den Stick kopieren und vorhandene Dateien ersetzen.')
    [void]$st.AppendLine('LeosMinibench.exe genügt allein; LeosMinibench.ps1 und .cmd sind für den Start ohne exe.')
    [void]$st.AppendLine(('Änderungen dieser Version: Doku\Änderungen_v{0}.txt; alle Versionen: Seite Versionen im Programm und Doku\Versionshistorie.txt.' -f $ver))
    [void]$st.AppendLine('Der Ordner Minibench-Daten auf dem Stick (Berichte, Datenbank, Tools, Änderungsprotokoll) bleibt dabei erhalten.')
    [void]$st.AppendLine('Ein Ordner Minibench-Daten hier im Aktuellen Build entsteht nur, wenn das Programm von hier gestartet wurde; er gehört nicht auf den Stick.')
    [void]$st.AppendLine('Diesen Ordner nicht von Hand ändern: Bauen.cmd erzeugt ihn bei jedem Bau neu aus src.')
    [IO.File]::WriteAllText((Join-Path $build 'Stand.txt'), $st.ToString(), $utf8Bom)

    # 5. README.md an die aktuelle Version anpassen
    $readmeFile = Join-Path $Here 'README.md'
    if (Test-Path -LiteralPath $readmeFile) {
        $rmText = [IO.File]::ReadAllText($readmeFile, [Text.Encoding]::UTF8)
        $rmText = [regex]::Replace($rmText, '(?i)(https://img\.shields\.io/badge/Version-)[^-\s]+(-[0-9a-fA-F]+\.svg)', ('${1}' + $ver + '${2}'))
        $rmText = [regex]::Replace($rmText, '(?i)(Download-LeosMinibench\.exe%20\(v)[^\)]+(\))', ('${1}' + $ver + '${2}'))
        $rmText = [regex]::Replace($rmText, 'alt="Leos Minibench [0-9.]+', ('alt="Leos Minibench ' + $ver))
        if ($testInfo -match '(\d+)\s+bestanden') {
            $passCount = [int]$Matches[1]
            $roundedTests = [math]::Floor($passCount / 10) * 10
            $rmText = [regex]::Replace($rmText, '(?i)(https://img\.shields\.io/badge/Tests-)\d+%2B(%20bestanden-[0-9a-fA-F]+\.svg)', ('${1}' + $roundedTests + '%2B${2}'))
        }
        [IO.File]::WriteAllText($readmeFile, $rmText, $utf8Bom)
        Write-Host ('  README   : Version {0} in README.md aktualisiert' -f $ver)
    }

    # 5. Datenpflege im Aktuellen Build (ab v2.7): Lasttests vor v2.67, unvollständige und kurze Läufe nach
    #    Archiv\Minibench-Daten des Projektordners. Fehler hier verhindern den Bau nicht.
    $bData = Join-Path $build 'Minibench-Daten'
    if (Test-Path -LiteralPath $bData) {
        Write-Host '  Daten    : Datenpflege im Ordner Minibench-Daten ...'
        try {
            $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $build 'LeosMinibench.ps1') -Datenpflege -DatenDir $bData -ArchivDir (Join-Path $Here 'Archiv\Minibench-Daten') 2>&1
            foreach ($l in @($out)) { $t = [string]$l; if ($t.Trim()) { Write-Host ('             ' + $t.Trim()) } }
        } catch { Write-Host ('  Hinweis  : Datenpflege nicht möglich: {0}' -f $_.Exception.Message) -ForegroundColor Yellow }
    }

    # 6. Git-Automatisierung (ab v3.31): Nach erfolgreichem Bau und bestandenen Tests lokalen Commit erzeugen
    $gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
    $isGitRepo = Test-Path -LiteralPath (Join-Path $Here '.git')
    if ($gitCmd -and $isGitRepo) {
        Write-Host '  Git      : Automatische Aktualisierung ...'
        try {
            $stageFiles = @('src', 'Doku', 'tests', 'Bauen.cmd', 'README.md', 'CHANGELOG.md', 'Aktueller Build', 'Archiv')
            & git.exe -C $Here add $stageFiles 2>&1 | Out-Null
            $status = & git.exe -C $Here status --porcelain 2>&1
            if ($status) {
                $commitMsg = if ($ver -eq '3.5') { ('Release v{0}: Taskleisten-Bugfix, Minimal-Preset, winget & NAS-Integration' -f $ver) } elseif ($ver -eq '3.4') { ('Release v{0}: Modul Tools, Task beenden & interaktiver Hauptbericht' -f $ver) } elseif ($ver -eq '3.32') { ('Release v{0}: Dark-Mode-Feinschliff & Konsolidierung des Systemvergleichs' -f $ver) } else { ('Release v{0}: Multi-System Dashboard, nativer GUI Dark Mode & Build-Sync' -f $ver) }
                $commitOut = & git.exe -C $Here commit -m $commitMsg 2>&1
                Write-Host ('  Git      : Stand lokal committed ({0})' -f $commitMsg) -ForegroundColor Green
                Write-Host '  Git      : Bereit zur Übertragung mit "git push".' -ForegroundColor Cyan
            } else {
                Write-Host '  Git      : Keine uncommitteten Änderungen vorhanden.' -ForegroundColor Gray
            }
        } catch {
            Write-Host ('  Hinweis  : Git-Commit nicht möglich: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
        }
    }

    Write-Host ''
    Write-Host ('  Fertig: {0}' -f $build) -ForegroundColor Green
    Write-Host ('  Version {0}, exe {1:N0} KB. Stand.txt nennt Datum, Tests und Prüfsummen.' -f $asmVer, ((Get-Item $exe).Length / 1KB))
    Write-Host '  Für den Stick den Inhalt von "Aktueller Build" kopieren. Änderungen nur in src vornehmen und neu bauen.'
} catch {
    Write-Host ''
    Write-Host ('  FEHLER: {0}' -f $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}
