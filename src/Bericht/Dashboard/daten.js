  let data = window.MINIBENCH_DASHBOARD_DATA;
  let baseSystem = null;
  let comparedSystems = [];
  let selectedCompareIds = new Set();
  let chartMode = 'cpu'; // 'cpu', 'gpu'

  function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // Farbpalette für bis zu N Systeme
  const SYSTEM_COLORS = [
    { stroke: '#0078D4', strokeDark: '#4CC2FF', fill: 'rgba(0, 120, 212, 0.12)', fillDark: 'rgba(76, 194, 255, 0.12)' },
    { stroke: '#E81123', strokeDark: '#FF5A5A', fill: 'rgba(232, 17, 35, 0.12)', fillDark: 'rgba(255, 90, 90, 0.12)' },
    { stroke: '#107C41', strokeDark: '#6CCB5F', fill: 'rgba(16, 124, 65, 0.12)', fillDark: 'rgba(108, 203, 95, 0.12)' },
    { stroke: '#8E44AD', strokeDark: '#B388FF', fill: 'rgba(142, 68, 173, 0.12)', fillDark: 'rgba(179, 136, 255, 0.12)' },
    { stroke: '#F7630C', strokeDark: '#FFA057', fill: 'rgba(247, 99, 12, 0.12)', fillDark: 'rgba(255, 160, 87, 0.12)' },
    { stroke: '#009688', strokeDark: '#26A69A', fill: 'rgba(0, 150, 136, 0.12)', fillDark: 'rgba(38, 166, 154, 0.12)' },
    { stroke: '#C239B3', strokeDark: '#FF77E9', fill: 'rgba(194, 57, 179, 0.12)', fillDark: 'rgba(255, 119, 233, 0.12)' },
    { stroke: '#D83B01', strokeDark: '#FF8A65', fill: 'rgba(216, 59, 1, 0.12)', fillDark: 'rgba(255, 138, 101, 0.12)' }
  ];

  function getSysColor(idx, isDark) {
    const c = SYSTEM_COLORS[idx % SYSTEM_COLORS.length];
    return isDark ? c.strokeDark : c.stroke;
  }

  function getShortSysName(s) {
    if (!s) return '';
    if (s.IsReference) {
      return s.DisplayName || s.Computer || 'Referenz';
    }
    const comp = s.Computer || (s.DisplayName ? s.DisplayName.split('(')[0].trim() : 'System');
    const cpu = s.Hardware?.CleanCpu || s.Hardware?.CpuKurz || '';
    let gpu = s.Hardware?.GPU || '';
    if (gpu) {
      gpu = gpu.replace(/NVIDIA\s+GeForce\s+/i, '')
               .replace(/AMD\s+Radeon\s+RX\s+/i, 'RX ')
               .replace(/AMD\s+Radeon\s+/i, '')
               .replace(/Radeon\s+RX\s+/i, 'RX ')
               .replace(/Radeon\s+/i, '')
               .replace(/Intel\s+Arc\s+/i, 'Arc ')
               .replace(/Intel\s+/i, '')
               .replace(/\s*\(.*?\)/g, '')
               .trim();
    }
    const parts = [cpu, gpu].filter(Boolean);
    if (parts.length > 0) {
      return `${comp} (${parts.join(' · ')})`;
    }
    return s.DisplayName || comp;
  }

  function formatDiskSummary(raw) {
    if (!raw || raw === '-' || raw === 'n/v') return '-';
    const items = raw.split(';').map(x => x.trim()).filter(Boolean);
    if (items.length === 0) return escapeHtml(raw);

    let nvmeCount = 0;
    let sataSsdCount = 0;
    let otherSsdCount = 0;
    let hddCount = 0;
    let totalGb = 0;

    items.forEach(it => {
      if (/\bUSB\b/i.test(it)) return;

      let gb = 0;
      const mCap = it.match(/([\d\.,]+)\s*(TB|GB|MB)/i);
      if (mCap) {
        const num = parseFloat(mCap[1].replace(',', '.'));
        const unit = mCap[2].toUpperCase();
        if (unit === 'TB') gb = num * 1000;
        else if (unit === 'GB') gb = num;
        else if (unit === 'MB') gb = num / 1000;
        totalGb += gb;
      }

      const isNvme = /\bNVMe\b/i.test(it);
      const isHdd = /\b(HDD|Festplatte|ST\d{3,}|WD\d{3,}[A-Z])\b/i.test(it) && !/\bSSD\b/i.test(it);
      const isSsdGeneric = /\b(SSD|Solid State|EVO|PRO|FireCuda\s+SSD)\b/i.test(it);

      if (isNvme) {
        nvmeCount++;
      } else if (isHdd) {
        hddCount++;
      } else if (/\bSATA\b/i.test(it) || isSsdGeneric) {
        sataSsdCount++;
      } else {
        otherSsdCount++;
      }
    });

    const parts = [];
    const totalSsd = nvmeCount + sataSsdCount + otherSsdCount;

    if (nvmeCount > 0 && sataSsdCount > 0) {
      parts.push(nvmeCount + 'x NVMe');
      parts.push(sataSsdCount + 'x SATA-SSD');
      if (otherSsdCount > 0) parts.push(otherSsdCount + 'x weitere SSD');
    } else if (nvmeCount > 0 && sataSsdCount === 0 && otherSsdCount === 0) {
      parts.push(nvmeCount + 'x NVMe-SSD');
    } else if (sataSsdCount > 0 && nvmeCount === 0 && otherSsdCount === 0) {
      parts.push(sataSsdCount + 'x SATA-SSD');
    } else if (totalSsd > 0) {
      parts.push(totalSsd + 'x SSD');
    }

    if (hddCount > 0) {
      parts.push(hddCount + 'x HDD');
    }

    if (parts.length === 0) return escapeHtml(raw);

    let capStr = '';
    if (totalGb >= 1000) {
      capStr = (totalGb / 1000).toFixed(1).replace('.', ',') + ' TB';
    } else if (totalGb > 0) {
      capStr = Math.round(totalGb) + ' GB';
    }

    const countStr = parts.join(', ');
    return capStr ? `${countStr} · ${capStr} Gesamt` : countStr;
  }

  // DOM-Elemente
  const themeToggle = document.getElementById('themeToggle');
  const baseSelect = document.getElementById('baseSelect');
  const compareChips = document.getElementById('compareChips');
  const comparedCountBadge = document.getElementById('comparedCountBadge');
  const specsTable = document.getElementById('specsTable');
  const profilesGrid = document.getElementById('profilesGrid');
  const matrixTable = document.getElementById('matrixTable');
  const findingsGrid = document.getElementById('findingsGrid');
  const chartWrapper = document.getElementById('chartWrapper');
  const canvas = document.getElementById('telemetryCanvas');
  const tooltip = document.getElementById('chartTooltip');
  const chartLegend = document.getElementById('chartLegend');

  const btnModeCpu = document.getElementById('btnModeCpu');
  const btnModeGpu = document.getElementById('btnModeGpu');
  const btnModeWatt = document.getElementById('btnModeWatt');

  const btnSelectAll = document.getElementById('btnSelectAll');
  const btnSelectNone = document.getElementById('btnSelectNone');
  const btnSelectDbOnly = document.getElementById('btnSelectDbOnly');
  const btnSelectRefOnly = document.getElementById('btnSelectRefOnly');

  // THEME MANAGEMENT
  function initTheme() {
    const saved = localStorage.getItem('minibench_theme');
    const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    const isDark = saved ? saved === 'dark' : prefersDark;
    setTheme(isDark);
  }

  function setTheme(isDark) {
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
    themeToggle.setAttribute('aria-checked', isDark ? 'true' : 'false');
    localStorage.setItem('minibench_theme', isDark ? 'dark' : 'light');
    renderChart();
  }

  themeToggle.addEventListener('click', () => {
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    setTheme(!isDark);
  });

  // HILFSFUNKTIONEN
  function getAllSystems() {
    if (!data) return [];
    const list = [];
    const seen = new Set();
    const addSys = s => {
      if (!s) return;
      const key = String(s.Id || s.DisplayName || s.Computer || '').trim().toLowerCase();
      if (key && !seen.has(key)) {
        seen.add(key);
        list.push(s);
      }
    };
    (data.Systems || []).forEach(addSys);
    (data.References || []).forEach(addSys);
    return list;
  }

  function getSystemById(id) {
    if (!id) return null;
    const sId = String(id);
    return getAllSystems().find(s => String(s.Id) === sId) || null;
  }

  function fmtNum(n, decimals = 0) {
    if (n === null || n === undefined || isNaN(n) || n === 0) return '-';
    return Number(n).toLocaleString('de-DE', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
  }

  function calcDelta(currVal, refVal, lowerIsBetter = false, unit = '') {
    if (currVal === null || currVal === undefined || isNaN(currVal) ||
        refVal === null || refVal === undefined || isNaN(refVal) ||
        currVal <= 0 || refVal <= 0) {
      return null;
    }

    if (unit === '°C') {
      const diff = currVal - refVal;
      const sign = diff > 0 ? '+' : '';
      const text = sign + diff.toLocaleString('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + ' °C';
      let cls = 'neutral';
      if (diff <= -1.0) cls = 'ok';
      else if (diff >= 2.0) cls = 'crit';
      return { text: text, cls: cls, value: diff, type: '°C' };
    }

    if (unit === '%') {
      const diff = currVal - refVal;
      const sign = diff > 0 ? '+' : '';
      const text = sign + diff.toLocaleString('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + ' %';
      let cls = 'neutral';
      if (lowerIsBetter) {
        if (diff <= -1.0) cls = 'ok';
        else if (diff >= 2.0) cls = 'crit';
      } else {
        if (diff >= 1.0) cls = 'ok';
        else if (diff <= -2.0) cls = 'crit';
      }
      return { text: text, cls: cls, value: diff, type: '%' };
    }

    // Standard relative percentage delta
    let pct = 0;
    if (lowerIsBetter) {
      pct = ((refVal - currVal) / refVal) * 100.0;
    } else {
      pct = ((currVal - refVal) / refVal) * 100.0;
    }
    const sign = pct > 0 ? '+' : '';
    const text = sign + pct.toLocaleString('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + ' %';
    let cls = 'neutral';
    if (pct >= 2.0) cls = 'ok';
    else if (pct <= -5.0) cls = 'crit';
    return { text: text, cls: cls, value: pct, type: '%' };
  }

  function renderPill(delta, lowerIsBetter = false) {
    if (!delta) return '<span class="pill neutral">n/v</span>';
    if (typeof delta === 'object' && delta.text) {
      return `<span class="pill ${delta.cls}">${delta.text}</span>`;
    }
    const pct = Number(delta);
    if (isNaN(pct)) return '<span class="pill neutral">n/v</span>';
    const sign = pct > 0 ? '+' : '';
    const txt = sign + pct.toLocaleString('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + ' %';
    let cls = 'neutral';
    if (pct >= 2.0) cls = 'ok';
    else if (pct <= -5.0) cls = 'crit';
    return `<span class="pill ${cls}">${txt}</span>`;
  }

  function getRatingWord(score) {
    if (score >= 130) return 'Exzellent';
    if (score >= 115) return 'Sehr gut';
    if (score >= 100) return 'Referenzniveau';
    if (score >= 85) return 'Gut';
    if (score >= 70) return 'Befriedigend';
    if (score >= 50) return 'Mäßig';
    return 'Schwach';
  }

  function parseDateScore(dStr) {
    if (!dStr || typeof dStr !== 'string') return 0;
    const str = dStr.trim();
    // 1. dd.MM.yyyy HH:mm[:ss] oder dd.MM.yyyy
    const mDe = str.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?/);
    if (mDe) {
      const day = parseInt(mDe[1], 10);
      const month = parseInt(mDe[2], 10) - 1;
      const year = parseInt(mDe[3], 10);
      const hour = mDe[4] ? parseInt(mDe[4], 10) : 0;
      const min = mDe[5] ? parseInt(mDe[5], 10) : 0;
      const sec = mDe[6] ? parseInt(mDe[6], 10) : 0;
      const dt = new Date(year, month, day, hour, min, sec);
      return isNaN(dt.getTime()) ? 0 : dt.getTime();
    }
    // 2. yyyy-MM-dd HH:mm[:ss] oder yyyy-MM-dd
    const mIso = str.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[\sT]+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?/);
    if (mIso) {
      const year = parseInt(mIso[1], 10);
      const month = parseInt(mIso[2], 10) - 1;
      const day = parseInt(mIso[3], 10);
      const hour = mIso[4] ? parseInt(mIso[4], 10) : 0;
      const min = mIso[5] ? parseInt(mIso[5], 10) : 0;
      const sec = mIso[6] ? parseInt(mIso[6], 10) : 0;
      const dt = new Date(year, month, day, hour, min, sec);
      return isNaN(dt.getTime()) ? 0 : dt.getTime();
    }
    const t = Date.parse(str);
    return isNaN(t) ? 0 : t;
  }

  // INITIALISIERUNG
  function init() {
    initTheme();
    if (!data || (!data.Systems && !data.References)) {
      console.warn('Keine Benchmark-Daten eingebettet.');
      return;
    }

    // Gespeicherte Systeme standardmäßig absteigend nach Datum sortieren (neuestes zuerst)
    if (data.Systems && Array.isArray(data.Systems)) {
      data.Systems.sort((itemA, itemB) => {
        const ta = parseDateScore(itemA.Datum);
        const tb = parseDateScore(itemB.Datum);
        if (tb !== ta) return tb - ta;
        return String(itemB.Id || '').localeCompare(String(itemA.Id || ''));
      });
    }

    populateBaseSelect();

    // Vorauswahl ermitteln
    const preselected = data.PreselectedIds || [];
    if (preselected && preselected.length > 0) {
      baseSelect.value = String(preselected[0]);
      selectedCompareIds.clear();
      for (let i = 1; i < preselected.length; i++) {
        selectedCompareIds.add(String(preselected[i]));
      }
    } else {
      if (data.Systems && data.Systems.length > 0) {
        baseSelect.value = String(data.Systems[0].Id);
      }
      selectedCompareIds.clear();
      if (data.References && data.References.length > 0) {
        const mid = data.References.find(r => r.DisplayName.includes('Mittelklasse')) || data.References[0];
        selectedCompareIds.add(String(mid.Id));
      } else if (data.Systems && data.Systems.length > 1) {
        selectedCompareIds.add(String(data.Systems[1].Id));
      }
    }

    // URL-Parameter oder Hash für System-Vorauswahl prüfen (?system=... oder #...)
    let paramSys = null;
    try {
      const urlParams = new URLSearchParams(window.location.search);
      paramSys = urlParams.get('system') || urlParams.get('pc') || urlParams.get('id');
      if (!paramSys && window.location.hash) {
        paramSys = decodeURIComponent(window.location.hash.replace(/^#/, ''));
      }
    } catch(e) {}
    if (paramSys) {
      const targetStr = String(paramSys).trim().toLowerCase();
      const all = getAllSystems();
      const match = all.find(s =>
        (s.Id && String(s.Id).toLowerCase() === targetStr) ||
        (s.Computer && String(s.Computer).toLowerCase() === targetStr) ||
        (s.DisplayName && String(s.DisplayName).toLowerCase().includes(targetStr))
      );
      if (match) {
        baseSelect.value = String(match.Id);
        selectedCompareIds.delete(String(match.Id));
        if (selectedCompareIds.size === 0) {
          if (data.References && data.References.length > 0) {
            const mid = data.References.find(r => r.DisplayName && r.DisplayName.includes('Mittelklasse')) || data.References[0];
            selectedCompareIds.add(String(mid.Id));
          } else {
            const other = all.find(s => String(s.Id) !== String(match.Id));
            if (other) selectedCompareIds.add(String(other.Id));
          }
        }
      }
    }

    renderCompareChips();
    updateDashboard();

    baseSelect.addEventListener('change', () => {
      // Falls das neue Basissystem in der Vergleichsauswahl war, entfernen
      selectedCompareIds.delete(baseSelect.value);
      renderCompareChips();
      updateDashboard();
    });

    btnSelectAll.addEventListener('click', () => {
      getAllSystems().forEach(s => {
        if (String(s.Id) !== baseSelect.value) selectedCompareIds.add(String(s.Id));
      });
      renderCompareChips();
      updateDashboard();
    });

    btnSelectNone.addEventListener('click', () => {
      selectedCompareIds.clear();
      renderCompareChips();
      updateDashboard();
    });

    btnSelectDbOnly.addEventListener('click', () => {
      selectedCompareIds.clear();
      (data.Systems || []).forEach(s => {
        if (String(s.Id) !== baseSelect.value) selectedCompareIds.add(String(s.Id));
      });
      renderCompareChips();
      updateDashboard();
    });

    btnSelectRefOnly.addEventListener('click', () => {
      selectedCompareIds.clear();
      (data.References || []).forEach(r => {
        if (String(r.Id) !== baseSelect.value) selectedCompareIds.add(String(r.Id));
      });
      renderCompareChips();
      updateDashboard();
    });

    // Chart Modus-Umschalter
    btnModeCpu.addEventListener('click', () => { setChartMode('cpu'); });
    btnModeGpu.addEventListener('click', () => { setChartMode('gpu'); });
    if (btnModeWatt) btnModeWatt.addEventListener('click', () => { setChartMode('watt'); });

    window.addEventListener('resize', renderChart);
  }

  function setChartMode(mode) {
    chartMode = mode;
    btnModeCpu.classList.toggle('active', mode === 'cpu');
    btnModeGpu.classList.toggle('active', mode === 'gpu');
    if (btnModeWatt) btnModeWatt.classList.toggle('active', mode === 'watt');
    renderChartLegend();
    renderChart();
  }

  function populateBaseSelect() {
    baseSelect.innerHTML = '';
    const sysGroup = document.createElement('optgroup');
    sysGroup.label = 'Geprüfte Systeme (Datenbank)';
    const refGroup = document.createElement('optgroup');
    refGroup.label = 'Referenzprofile (Eingebettet)';

    if (data.Systems) {
      data.Systems.forEach(s => {
        const opt = document.createElement('option');
        opt.value = String(s.Id);
        opt.textContent = s.DisplayName + (s.Datum ? ' (' + s.Datum + ')' : '');
        sysGroup.appendChild(opt);
      });
    }

    if (data.References) {
      data.References.forEach(r => {
        const opt = document.createElement('option');
        opt.value = String(r.Id);
        opt.textContent = r.DisplayName;
        refGroup.appendChild(opt);
      });
    }

    baseSelect.appendChild(sysGroup);
    baseSelect.appendChild(refGroup);
  }

  function renderCompareChips() {
    compareChips.innerHTML = '';
    const all = getAllSystems();
    const curBaseId = baseSelect.value;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    let colorIdx = 1;
    all.forEach(sys => {
      const sId = String(sys.Id);
      if (sId === curBaseId) return; // Basissystem nicht in Vergleichsliste anzeigen

      const isChecked = selectedCompareIds.has(sId);
      const label = document.createElement('label');
      label.className = 'compare-chip' + (isChecked ? ' active' : '');

      const chk = document.createElement('input');
      chk.type = 'checkbox';
      chk.checked = isChecked;
      chk.value = sId;
      chk.addEventListener('change', () => {
        if (chk.checked) selectedCompareIds.add(sId);
        else selectedCompareIds.delete(sId);
        label.classList.toggle('active', chk.checked);
        updateDashboard();
      });

      const dot = document.createElement('span');
      dot.className = 'sys-dot';
      dot.style.background = isChecked ? getSysColor(colorIdx, isDark) : 'var(--text-subtle)';

      const txt = document.createElement('span');
      txt.textContent = sys.DisplayName + (sys.Datum ? ' (' + sys.Datum.split(' ')[0] + ')' : '');

      label.appendChild(chk);
      label.appendChild(dot);
      label.appendChild(txt);
      compareChips.appendChild(label);

      if (isChecked) colorIdx++;
    });
  }

  function updateDashboard() {
    baseSystem = getSystemById(baseSelect.value);
    if (!baseSystem && getAllSystems().length > 0) {
      baseSystem = getAllSystems()[0];
      baseSelect.value = String(baseSystem.Id);
    }

    // Liste aller aktiven Systeme: Basissystem zuerst, dann die angehakten
    comparedSystems = [];
    if (baseSystem) comparedSystems.push(baseSystem);

    selectedCompareIds.forEach(id => {
      const s = getSystemById(id);
      if (s && s !== baseSystem) comparedSystems.push(s);
    });

    const totalN = comparedSystems.length;
    comparedCountBadge.textContent = totalN + (totalN === 1 ? ' System' : ' Systeme im Vergleich');

    renderSpecsTable();
    renderProfilesGrid();
    renderMatrixTable();
    renderFindingsGrid();
    renderChartLegend();
    renderChart();
  }

  // 1. HARDWARE-SPEZIFIKATIONEN TABELLE
  function renderSpecsTable() {
    if (!specsTable) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    let html = '<thead><tr><th class="col-feature">Merkmal</th>';
    comparedSystems.forEach((s, idx) => {
      const color = getSysColor(idx, isDark);
      const isBase = (idx === 0);
      const sName = escapeHtml(s.DisplayName || s.Computer);
      const repUrl = s.ReportUrl ? escapeHtml(s.ReportUrl) : '';
      const nameHtml = repUrl
        ? `<a href="${repUrl}" target="_blank" title="Diagnosebericht für ${sName} im Browser öffnen" style="color:inherit; text-decoration:underline; font-weight:600; cursor:pointer;">${sName}</a>`
        : `<span>${sName}</span>`;
      const repBadge = repUrl
        ? `<a href="${repUrl}" target="_blank" class="report-badge-btn" title="Diagnosebericht öffnen" style="margin-left:auto; display:inline-flex; align-items:center; gap:3px; padding:2px 8px; font-size:0.75rem; border-radius:4px; background:var(--accent-subtle); color:var(--accent); text-decoration:none; border:1px solid var(--accent); font-weight:600; cursor:pointer;">Bericht</a>`
        : '';
      html += `<th class="${isBase ? 'col-base' : ''}" style="${isBase ? 'background: var(--accent-subtle);' : ''}">
        <div style="display: flex; align-items: center; gap: 6px;">
          <span class="sys-dot" style="background: ${color};"></span>
          ${nameHtml}
          ${isBase ? '<span class="pill ok" style="font-weight:700;">100 % Basis</span>' : ''}
          ${repBadge}
        </div>
        <div style="font-size: 0.72rem; color: var(--text-muted); font-weight: normal;">${escapeHtml(s.Datum || 'Referenz')}</div>
      </th>`;
    });
    html += '</tr></thead><tbody>';

    const rows = [
      { key: 'Computer', label: 'Rechnername', get: s => escapeHtml(s.Computer || '-') },
      { key: 'CPU', label: 'Prozessor (CPU)', get: s => escapeHtml(s.Hardware?.CpuKurz || s.Hardware?.CPU || '-') },
      { key: 'KerneThreads', label: 'Kerne / Threads', get: s => escapeHtml((s.Hardware?.Kerne && s.Hardware?.Threads) ? `${s.Hardware.Kerne} / ${s.Hardware.Threads}` : (s.Hardware?.KerneThreads || 'n/v')) },
      { key: 'RAM', label: 'Arbeitsspeicher (RAM)', get: s => escapeHtml(s.Hardware?.RAM || '-') },
      { key: 'GPU', label: 'Grafikkarte (GPU)', get: s => escapeHtml(s.Hardware?.GPU || '-') },
      { key: 'Disk', label: 'Datenträger', get: s => {
        const raw = s.Hardware?.Datentraeger || s.Hardware?.FastestDisk || '';
        if (!raw || raw === 'n/v' || raw === '-') return '<span style="color:var(--text-muted);">-</span>';
        const summary = formatDiskSummary(raw);
        return `<span title="${escapeHtml(raw)}" style="cursor:help; border-bottom:1px dotted var(--text-muted);">${escapeHtml(summary)}</span>`;
      }},
      { key: 'Mainboard', label: 'Mainboard / System', get: s => escapeHtml(s.Hardware?.Mainboard || s.Hardware?.System || '-') },
      { key: 'OS', label: 'Betriebssystem', get: s => escapeHtml(s.OS || s.Hardware?.Betriebssystem || '-') },
      { key: 'Installiert', label: 'Windows installiert', get: s => escapeHtml(s.Hardware?.WindowsInstalliert || '-') },
      { key: 'Verbrauch', label: 'Geschätzter Systemverbrauch (Last / Leerlauf)', get: s => {
        const v = s.Hardware?.PowerDisplay;
        if (!v || v === 'n/v') {
          const l = s.Metrics?.POWER_LOAD;
          const i = s.Metrics?.POWER_IDLE;
          if (l || i) return `~${Math.round(l || 0)} W / ~${Math.round(i || 0)} W`;
          return '<span style="color:var(--text-muted);">n/v (kein Leistungssensor)</span>';
        }
        const tip = escapeHtml(s.Hardware?.PowerLoadTip || 'Mathematisch modellierter Gesamtverbrauch');
        return `<span class="hit" title="${tip}" style="cursor:help; border-bottom:1px dotted var(--text-muted); font-weight:600; color:#d97706;">${escapeHtml(v)}</span>`;
      }},
      { key: 'Befunde', label: 'Diagnose-Befunde', get: s => {
        const b = s.Befunde || { Kritisch: 0, Warnungen: 0, Hinweise: 0 };
        return `<span class="badge ${b.Kritisch > 0 ? 'crit' : 'neutral'}">${b.Kritisch} kritisch</span>
                <span class="badge ${b.Warnungen > 0 ? 'warn' : 'neutral'}">${b.Warnungen} Warnungen</span>
                <span class="badge info">${b.Hinweise} Hinweise</span>`;
      }}
    ];

    rows.forEach(r => {
      html += `<tr><td class="col-feature">${r.label}</td>`;
      comparedSystems.forEach((s, idx) => {
        const isBase = (idx === 0);
        html += `<td class="${isBase ? 'col-base' : ''}" style="${isBase ? 'background: var(--accent-subtle);' : ''}">${r.get(s)}</td>`;
      });
      html += '</tr>';
    });

    html += '</tbody>';
    specsTable.innerHTML = html;
  }

