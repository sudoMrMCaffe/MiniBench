  function renderMatrixTable() {
    if (!matrixTable) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    let headCells = '<th class="col-feature">Messgröße</th>';
    comparedSystems.forEach((s, idx) => {
      const color = getSysColor(idx, isDark);
      const isBase = (idx === 0);
      const sName = escapeHtml(s.DisplayName || s.Computer);
      const repUrl = s.ReportUrl ? escapeHtml(s.ReportUrl) : '';
      const nameLink = repUrl
        ? `<a href="${repUrl}" target="_blank" title="Diagnosebericht für ${sName} im Browser öffnen" style="color:inherit; text-decoration:underline; font-weight:600; cursor:pointer;">${sName}</a>`
        : `<span>${sName}</span>`;
      const repBtn = repUrl
        ? `<a href="${repUrl}" target="_blank" title="Diagnosebericht öffnen" style="font-size:0.75rem; color:var(--accent); text-decoration:none; margin-left:4px;">Bericht</a>`
        : '';
      headCells += `<th class="${isBase ? 'col-base' : ''}" style="text-align: right; ${isBase ? 'background: var(--accent-subtle);' : ''}">
        <div style="display: flex; align-items: center; justify-content: flex-end; gap: 6px;">
          <span class="sys-dot" style="background: ${color};"></span>
          ${nameLink}
          ${isBase ? '<span class="pill ok" style="font-weight:700;">100 % Basis</span>' : ''}
          ${repBtn}
        </div>
      </th>`;
    });
    let html = `<thead><tr>${headCells}</tr></thead><tbody>`;

    const categories = [
      {
        name: 'Prozessor (CPU)',
        metrics: [
          { key: 'CPU_ST', label: 'Single-Thread (ST)', unit: 'Punkte', dec: 0, lower: false },
          { key: 'CPU_MT', label: 'Multi-Thread (MT)', unit: 'Punkte', dec: 0, lower: false },
          { key: 'CPU_AES', label: 'AES-256 Verschlüsselung', unit: 'MB/s', dec: 0, lower: false },
          { key: 'CPU_SHA', label: 'SHA-256 Prüfsumme', unit: 'MB/s', dec: 0, lower: false },
          { key: 'CPU_DEFL', label: 'Deflate Kompression', unit: 'MB/s', dec: 0, lower: false }
        ]
      },
      {
        name: 'Arbeitsspeicher (RAM)',
        metrics: [
          { key: 'RAM_Lesen', label: 'Lesen Durchsatz', unit: 'GB/s', dec: 1, lower: false },
          { key: 'RAM_Schreiben', label: 'Schreiben Durchsatz', unit: 'GB/s', dec: 1, lower: false },
          { key: 'RAM_Kopieren', label: 'Kopieren Durchsatz', unit: 'GB/s', dec: 1, lower: false },
          { key: 'RAM_Latenz', label: 'Zugriffslatenz', unit: 'ns', dec: 1, lower: true }
        ]
      },
      {
        name: 'Grafik (GPU)',
        metrics: [
          { key: 'GPU_REND', label: 'Renderleistung (Ø FPS)', unit: 'FPS', dec: 1, lower: false },
          { key: 'GPU_REND1', label: '1 %-Low Bildrate', unit: 'FPS', dec: 1, lower: false },
          { key: 'GPU_REND01', label: '0,1 %-Low Bildrate', unit: 'FPS', dec: 1, lower: false },
          { key: 'GPU_STUTTER', label: 'Mikroruckler-Anteil', unit: '%', dec: 1, lower: true },
          { key: 'GPU_VMB', label: 'Videospeicher-Bandbreite', unit: 'GB/s', dec: 1, lower: false }
        ]
      },
      {
        name: 'Datenträger (Speicher)',
        metrics: [
          { key: 'DISK_SR', label: 'Sequentiell Lesen', unit: 'MB/s', dec: 0, lower: false, get: s => s.Metrics?.FastestDisk?.SR || s.RawValues?.['DISK|NVMe4|SR'] || 0 },
          { key: 'DISK_SW', label: 'Sequentiell Schreiben', unit: 'MB/s', dec: 0, lower: false, get: s => s.Metrics?.FastestDisk?.SW || s.RawValues?.['DISK|NVMe4|SW'] || 0 },
          { key: 'DISK_R1', label: '4K Zufall QD1', unit: 'IOPS', dec: 0, lower: false, get: s => s.Metrics?.FastestDisk?.R1 || s.RawValues?.['DISK|NVMe4|R1'] || 0 },
          { key: 'DISK_R8', label: '4K Zufall 8 Threads', unit: 'IOPS', dec: 0, lower: false, get: s => s.Metrics?.FastestDisk?.R8 || s.RawValues?.['DISK|NVMe4|R8'] || 0 },
          { key: 'DISK_W1', label: '4K Schreiben', unit: 'IOPS', dec: 0, lower: false, get: s => s.Metrics?.FastestDisk?.W1 || s.RawValues?.['DISK|NVMe4|W1'] || 0 }
        ]
      },
      {
        name: 'Lasttest & Telemetrie',
        metrics: [
          { key: 'LAST_CpuTemp', label: 'CPU-Höchsttemperatur', unit: '°C', dec: 0, lower: true },
          { key: 'LAST_GpuTemp', label: 'GPU-Höchsttemperatur', unit: '°C', dec: 0, lower: true },
          { key: 'LAST_CpuWatt', label: 'CPU-Spitzenleistung', unit: 'W', dec: 0, lower: false },
          { key: 'LAST_TaktStab', label: 'Taktstabilität unter Last', unit: '%', dec: 1, lower: false },
          { key: 'LAST_TaktAbfall', label: 'Taktabfall (Drosselung)', unit: '%', dec: 1, lower: true }
        ]
      },
      {
        name: 'Energie & Effizienz (geschätzt)',
        metrics: [
          { key: 'POWER_LOAD', label: 'Geschätzter Volllastverbrauch', unit: 'W', dec: 0, lower: true },
          { key: 'POWER_IDLE', label: 'Geschätzter Leerlaufverbrauch', unit: 'W', dec: 0, lower: true },
          { key: 'EFF_CPU', label: 'CPU-Effizienz (MT-Score / CPU-Watt)', unit: 'Pkt/W', dec: 1, lower: false },
          { key: 'EFF_GPU', label: 'GPU-Effizienz (Render-FPS / GPU-Watt)', unit: 'FPS/W', dec: 2, lower: false },
          { key: 'EFF_SYS', label: 'Gesamtsystem-Effizienz (Gesamtscore / 100 W)', unit: 'Pkt/100W', dec: 1, lower: false }
        ]
      }
    ];

    categories.forEach(cat => {
      html += `<tr class="category-header"><td class="col-feature" colspan="${comparedSystems.length + 1}">${cat.name}</td></tr>`;

      cat.metrics.forEach(m => {
        // Werte aller Systeme sammeln
        const vals = comparedSystems.map(s => {
          if (m.get) return m.get(s);
          return s.Metrics?.[m.key] || s.RawValues?.[m.key.replace('_', '|')] || 0;
        });

        // Bestwert ermitteln (nur unter Werten > 0)
        const validVals = vals.filter(v => v !== null && v !== undefined && v > 0);
        let bestVal = null;
        if (validVals.length > 1) {
          bestVal = m.lower ? Math.min(...validVals) : Math.max(...validVals);
        }

        const baseVal = vals[0] || 0;

        html += `<tr><td class="col-feature">${m.label} <span style="font-size: 0.72rem; color: var(--text-muted);">(${m.unit}${m.lower ? ', niedriger = besser' : ''})</span></td>`;

        vals.forEach((v, idx) => {
          const isBase = (idx === 0);
          const isBest = (bestVal !== null && v === bestVal);
          const delta = (isBase || v <= 0 || baseVal <= 0) ? null : calcDelta(v, baseVal, m.lower, m.unit);

          html += `<td class="sys-val ${isBase ? 'col-base' : ''} ${isBest ? 'is-best' : ''}" style="${isBase ? 'background: var(--accent-subtle);' : ''}">
            <span class="val-main">${fmtNum(v, m.dec)}</span>
            <span class="val-sub">${m.unit}</span>
            ${isBest ? '<span class="badge-best" title="Bestwert aller Systeme">Bestwert</span>' : ''}
            ${!isBase && delta !== null ? renderPill(delta, m.lower) : ''}
          </td>`;
        });

        html += `</tr>`;
      });
    });

    html += '</tbody><tfoot><tr>' + headCells + '</tr></tfoot>';
    matrixTable.innerHTML = html;
  }

