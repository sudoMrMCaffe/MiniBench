  function renderProfilesGrid() {
    if (!profilesGrid) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    const profiles = [
      { key: 'Gaming', icon: '🎮', title: 'Gaming', desc: 'GPU- & Single-Thread-Fokus', tip: 'Gaming-Profil: 70 % GPU-Bildrate, 20 % CPU Single-Core, 10 % RAM und SSD (Kerne > 8 neutral)' },
      { key: 'Desktop', icon: '💼', title: 'Büro / Desktop', desc: 'Reaktionszeit & SSD-Leistung', tip: 'Büro- und Desktop-Profil: 45 % SSD-Reaktionszeit (4K), 35 % CPU Single-Core, 20 % RAM-Latenz (0 % GPU/Multi-Core)' },
      { key: 'Workstation', icon: '🚀', title: 'Workstation', desc: 'Mehrkern- & RAM-Durchsatz', tip: 'Workstation-Profil: 60 % CPU Multi-Core, 15 % RAM, 10 % Datenträger (I/O), 10 % GPU-Beschleunigung, 5 % CPU Single-Core' }
    ];

    let html = '';
    profiles.forEach(p => {
      const baseScore = baseSystem?.Scores?.[p.key] || 0;
      html += `<div class="profile-card">
        <div class="profile-header" title="${escapeHtml(p.tip)}" style="cursor: help;">
          <span><span style="margin-right: 6px;">${p.icon}</span>${escapeHtml(p.title)}</span>
          <span style="font-size: 0.78rem; color: var(--text-muted); font-weight: normal;">${escapeHtml(p.desc)}</span>
        </div>
        <div class="profile-sys-list">`;

      const items = comparedSystems.map((s, idx) => {
        const sc = s.Scores?.[p.key];
        const hasScore = (typeof sc === 'number' && sc > 0);
        const isBase = (String(s.Id) === String(baseSystem?.Id));
        return {
          sys: s,
          idx: idx,
          score: hasScore ? sc : 0,
          hasScore: hasScore,
          isBase: isBase
        };
      });

      items.sort((a, b) => {
        if (a.hasScore && b.hasScore) return b.score - a.score;
        if (a.hasScore && !b.hasScore) return -1;
        if (!a.hasScore && b.hasScore) return 1;
        return a.idx - b.idx;
      });

      items.forEach(item => {
        const s = item.sys;
        const sc = item.score;
        const isBase = item.isBase;
        const color = getSysColor(item.idx, isDark);
        const sName = escapeHtml(s.DisplayName || s.Computer);
        const repUrl = s.ReportUrl ? escapeHtml(s.ReportUrl) : '';

        const delta = isBase ? 0 : (item.hasScore && baseScore > 0 ? calcDelta(sc, baseScore) : null);
        let deltaHtml = '';
        if (isBase) {
          deltaHtml = '<span class="pill ok">100 % (Basis)</span>';
        } else if (delta !== null) {
          deltaHtml = renderPill(delta);
        } else {
          deltaHtml = '<span class="pill neutral">n/v</span>';
        }

        const scoreText = item.hasScore ? fmtNum(sc) : 'n/v';

        const nameLink = repUrl
          ? `<a href="${repUrl}" target="_blank" title="Diagnosebericht für ${sName} öffnen" style="color:inherit; text-decoration:underline; cursor:pointer;">${sName}</a>`
          : `<span>${sName}</span>`;

        html += `<div class="profile-sys-row ${isBase ? 'is-base' : ''}">
          <div style="display: flex; align-items: center; gap: 6px;">
            <span class="sys-dot" style="background: ${color};"></span>
            <span style="max-width: 150px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${nameLink}</span>
          </div>
          <div style="display: flex; align-items: center; gap: 4px;">
            <span style="font-weight: 700;">${scoreText}</span>
            ${deltaHtml}
          </div>
        </div>`;
      });

      html += `</div></div>`;
    });

    profilesGrid.innerHTML = html;
  }

