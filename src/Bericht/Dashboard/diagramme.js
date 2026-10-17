  function renderFindingsGrid() {
    if (!findingsGrid) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    let html = '';
    comparedSystems.forEach((s, idx) => {
      const color = getSysColor(idx, isDark);
      const b = s.Befunde || { Kritisch: 0, Warnungen: 0, Hinweise: 0, Liste: [] };
      const list = b.Liste || [];

      const sName = escapeHtml(s.DisplayName || s.Computer);
      const repUrl = s.ReportUrl ? escapeHtml(s.ReportUrl) : '';
      const nameLink = repUrl
        ? `<a href="${repUrl}" target="_blank" title="Diagnosebericht für ${sName} im Browser öffnen" style="color:inherit; text-decoration:underline; font-weight:600; cursor:pointer;">${sName}</a>`
        : `<span>${sName}</span>`;
      const repBadge = repUrl
        ? `<a href="${repUrl}" target="_blank" class="report-badge-btn" title="Diagnosebericht öffnen" style="margin-left:auto; display:inline-flex; align-items:center; gap:3px; padding:2px 8px; font-size:0.75rem; border-radius:4px; background:var(--accent-subtle); color:var(--accent); text-decoration:none; border:1px solid var(--accent); font-weight:600; cursor:pointer;">Bericht</a>`
        : '';

      html += `<div class="finding-card">
        <div class="finding-card-head" style="display:flex; align-items:center; gap:6px;">
          <span class="sys-dot" style="background: ${color};"></span>
          ${nameLink}
          ${repBadge}
        </div>
        <div class="finding-card-badges">
          <span class="badge ${b.Kritisch > 0 ? 'crit' : 'neutral'}">${b.Kritisch} kritisch</span>
          <span class="badge ${b.Warnungen > 0 ? 'warn' : 'neutral'}">${b.Warnungen} Warnungen</span>
          <span class="badge info">${b.Hinweise} Hinweise</span>
        </div>`;

      if (list.length > 0) {
        html += `<details>
          <summary>${list.length} Befunde anzeigen</summary>
          <div class="findings-list">`;
        list.forEach(f => {
          let bCls = 'info';
          let txt = String(f);
          if (txt.includes('[KRITISCH]') || txt.includes('[FEHLER]')) bCls = 'crit';
          else if (txt.includes('[WARNUNG]')) bCls = 'warn';

          html += `<div class="finding-item">
            <span class="badge ${bCls}" style="flex-shrink: 0;">${bCls.toUpperCase()}</span>
            <span>${escapeHtml(txt.replace(/^\[\w+\]\s*/, ''))}</span>
          </div>`;
        });
        html += `</div></details>`;
      } else {
        html += `<div style="font-size: 0.8rem; color: var(--text-muted);">Keine Auffälligkeiten oder Befunde dokumentiert.</div>`;
      }

      html += `</div>`;
    });

    findingsGrid.innerHTML = html;
  }

  // 5. CHART-LEGENDE
  function renderChartLegend() {
    if (!chartLegend) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    let html = '';
    comparedSystems.forEach((s, idx) => {
      const color = getSysColor(idx, isDark);
      const isBase = (String(s.Id) === String(baseSystem?.Id));
      const sName = escapeHtml(s.DisplayName || s.Computer);
      const label = (isBase ? 'Basis: ' : '') + sName;
      const hasSeries = (s.Telemetry?.Series && s.Telemetry.Series.length > 0);
      let testType = hasSeries ? (s.Telemetry?.TestType || 'Lasttest') : 'keine Zeitreihe';
      if (testType === 'Benchmark') testType = 'Benchmark-Messung';
      html += `<div class="legend-item">
        <div class="legend-color" style="background: ${color};"></div>
        <span>${label} (${escapeHtml(testType)})</span>
      </div>`;
    });

    const subTitleEl = document.querySelector('.dash-card .card-head p');
    if (subTitleEl) {
      const anyBenchmark = comparedSystems.some(s => s.Telemetry?.TestType === 'Benchmark');
      const allBenchmark = comparedSystems.length > 0 && comparedSystems.every(s => s.Telemetry?.TestType === 'Benchmark' || !s.Telemetry?.Series?.length);
      if (allBenchmark && anyBenchmark) {
        subTitleEl.textContent = 'Sensorverlauf (Benchmark-Messung) über die Messphasen mit Farbcodierung je System.';
      } else if (anyBenchmark) {
        subTitleEl.textContent = 'Sensorverlauf (Lasttest & Benchmark-Messung) über die Belastungsdauer mit Farbcodierung je System.';
      } else {
        subTitleEl.textContent = 'Sensorverlauf über die Belastungsdauer mit Farbcodierung je System.';
      }
    }

    if (chartMode !== 'watt') {
      html += `<div class="legend-item" style="margin-left: auto; gap: 12px; font-weight: 500;">
        <span><strong style="color:${isDark ? '#60A5FA' : '#0078D4'};">―</strong> Temperatur (°C)</span>
        <span><strong style="color:${isDark ? '#6CCB5F' : '#107C41'};">- -</strong> Leistung (W)</span>
      </div>`;
    }

    chartLegend.innerHTML = html;
  }

  // 6. CANVAS CHART RENDERING (MULTI-SYSTEM CANVAS)
  function renderChart() {
    if (!canvas || !chartWrapper) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    const dpr = window.devicePixelRatio || 1;
    const rect = chartWrapper.getBoundingClientRect();
    const width = rect.width;
    const height = rect.height;

    canvas.width = width * dpr;
    canvas.height = height * dpr;
    canvas.style.width = width + 'px';
    canvas.style.height = height + 'px';

    const ctx = canvas.getContext('2d');
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, width, height);

    if (comparedSystems.length === 0) {
      ctx.fillStyle = isDark ? '#A0A0A0' : '#5F6368';
      ctx.font = '14px system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('Keine Systeme zur Anzeige ausgewählt.', width / 2, height / 2);
      return;
    }

    const padding = { top: 32, right: 65, bottom: 40, left: 60 };
    const chartW = width - padding.left - padding.right;
    const chartH = height - padding.top - padding.bottom;

    // Maximale Zeit ermitteln
    let tMax = 120;
    comparedSystems.forEach(s => {
      const srs = s.Telemetry?.Series || [];
      if (srs.length > 0) {
        const lastT = srs[srs.length - 1].T;
        if (lastT > tMax) tMax = lastT;
      }
    });

    let maxWatt = 200;
    comparedSystems.forEach(s => {
      (s.Telemetry?.Series || []).forEach(pt => {
        const w = (chartMode === 'gpu')
          ? (pt.GpuW != null ? pt.GpuW : (pt.IGpuW != null ? pt.IGpuW : 0))
          : ((pt.SysW != null && pt.SysW > 0) ? pt.SysW : (pt.CpuW != null ? pt.CpuW : 0));
        if (w > maxWatt) maxWatt = w;
      });
    });
    maxWatt = Math.min(1000, Math.ceil((maxWatt * 1.15) / 50) * 50);

    const tempMax = 100;
    const getX = t => padding.left + (t / tMax) * chartW;
    const getYTemp = deg => padding.top + chartH - (deg / tempMax) * chartH;
    const getYWatt = w => padding.top + chartH - (w / maxWatt) * chartH;
    const getYVal = (chartMode === 'watt') ? getYWatt : getYTemp;

    // GRID LINES & ACHSEN
    ctx.font = '11px system-ui, sans-serif';
    const gridFractions = [0, 0.25, 0.5, 0.75, 1.0];

    gridFractions.forEach(f => {
      const y = padding.top + chartH - f * chartH;
      ctx.strokeStyle = isDark ? '#363636' : '#ECEFF1';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(padding.left + chartW, y);
      ctx.stroke();

      if (chartMode === 'watt') {
        const w = Math.round(f * maxWatt);
        ctx.fillStyle = isDark ? '#34D399' : '#059669';
        ctx.textAlign = 'right';
        ctx.fillText(w + ' W', padding.left - 8, y + 4);
        ctx.textAlign = 'left';
        ctx.fillText(w + ' W', padding.left + chartW + 8, y + 4);
      } else {
        const deg = Math.round(f * tempMax);
        ctx.fillStyle = isDark ? '#60A5FA' : '#2563EB';
        ctx.textAlign = 'right';
        ctx.fillText(deg + ' °C', padding.left - 8, y + 4);

        const w = Math.round(f * maxWatt);
        ctx.fillStyle = isDark ? '#34D399' : '#059669';
        ctx.textAlign = 'left';
        ctx.fillText(w + ' W', padding.left + chartW + 8, y + 4);
      }
    });

    // Achsen-Beschriftungen oben
    ctx.font = '600 11px system-ui, sans-serif';
    if (chartMode === 'watt') {
      ctx.fillStyle = isDark ? '#34D399' : '#059669';
      ctx.textAlign = 'left';
      ctx.fillText('Leistung (W)', padding.left, padding.top - 12);
    } else {
      ctx.fillStyle = isDark ? '#60A5FA' : '#2563EB';
      ctx.textAlign = 'left';
      ctx.fillText('Temperatur (°C)', padding.left, padding.top - 12);

      ctx.fillStyle = isDark ? '#34D399' : '#059669';
      ctx.textAlign = 'left';
      ctx.fillText('Leistung (W)', padding.left + chartW + 8, padding.top - 12);
    }

    // X Axis Time Labels
    ctx.textAlign = 'center';
    ctx.fillStyle = isDark ? '#808080' : '#888888';
    ctx.font = '11px system-ui, sans-serif';
    const xStep = tMax <= 120 ? 30 : 60;
    for (let sec = 0; sec <= tMax; sec += xStep) {
      const x = getX(sec);
      const mm = Math.floor(sec / 60);
      const ss = Math.floor(sec % 60);
      const timeStr = String(mm).padStart(2, '0') + ':' + String(ss).padStart(2, '0');
      ctx.fillText(timeStr, x, padding.top + chartH + 20);
    }

    // Prüfen, ob Zeitreihen-Daten vorliegen
    const hasAnySeries = comparedSystems.some(s => (s.Telemetry?.Series && s.Telemetry.Series.length >= 2));

    if (!hasAnySeries) {
      let peakInfo = '';
      const sysForPeak = baseSystem || (comparedSystems.length > 0 ? comparedSystems[0] : null);
      if (sysForPeak && sysForPeak.Metrics) {
        const m = sysForPeak.Metrics;
        const parts = [];
        if (m.LAST_CpuTemp != null && m.LAST_CpuTemp > 0) parts.push('CPU ' + Math.round(m.LAST_CpuTemp) + ' °C');
        if (m.LAST_GpuTemp != null && m.LAST_GpuTemp > 0) parts.push('GPU ' + Math.round(m.LAST_GpuTemp) + ' °C');
        if (m.GPU_REND != null && m.GPU_REND > 0) parts.push(Math.round(m.GPU_REND) + ' FPS');
        if (m.LAST_CpuWatt != null && m.LAST_CpuWatt > 0 && parts.length < 3) parts.push(Math.round(m.LAST_CpuWatt) + ' W');
        if (parts.length > 0) {
          peakInfo = 'Peak: ' + parts.join(' · ');
        }
      }

      const cardW = Math.min(width - 60, 440);
      const cardH = 68;
      const cardX = (width - cardW) / 2;
      const cardY = padding.top + (chartH - cardH) / 2;

      ctx.save();
      ctx.fillStyle = isDark ? 'rgba(32, 36, 42, 0.94)' : 'rgba(255, 255, 255, 0.94)';
      ctx.strokeStyle = isDark ? '#475569' : '#CBD5E1';
      ctx.lineWidth = 1;

      if (typeof ctx.roundRect === 'function') {
        ctx.beginPath();
        ctx.roundRect(cardX, cardY, cardW, cardH, 8);
        ctx.fill();
        ctx.stroke();
      } else {
        ctx.fillRect(cardX, cardY, cardW, cardH);
        ctx.strokeRect(cardX, cardY, cardW, cardH);
      }

      ctx.textAlign = 'center';
      ctx.fillStyle = isDark ? '#F1F5F9' : '#0F172A';
      ctx.font = '600 13px system-ui, sans-serif';
      ctx.fillText('Keine Zeitreihe vorhanden', width / 2, cardY + 26);

      ctx.fillStyle = isDark ? '#94A3B8' : '#64748B';
      ctx.font = '12px system-ui, sans-serif';
      ctx.fillText(peakInfo ? peakInfo : 'Für dieses Profil liegen keine zeitaufgelösten Messkurven vor.', width / 2, cardY + 48);
      ctx.restore();

      canvas.onmousemove = null;
      canvas.onmouseleave = null;
      return;
    }

    // KURVEN ZEICHNEN
    comparedSystems.forEach((s, idx) => {
      const srs = s.Telemetry?.Series || [];
      if (srs.length < 2) return;
      const isBase = (String(s.Id) === String(baseSystem?.Id));

      if (chartMode !== 'watt') {
        // 1. Temperatur-Kurve (Solid)
        const tempColor = (idx === 0)
          ? (isDark ? '#4CC2FF' : '#0078D4')
          : (idx === 1)
            ? (isDark ? '#FFA057' : '#F7630C')
            : getSysColor(idx, isDark);

        ctx.save();
        ctx.strokeStyle = tempColor;
        ctx.lineWidth = isBase ? 2.8 : 2.0;
        ctx.setLineDash([]);

        let inSegment = false;
        srs.forEach(pt => {
          const val = (chartMode === 'cpu')
            ? pt.Temp
            : (pt.GpuTemp != null ? pt.GpuTemp : pt.IGpuTemp);

          if (val != null && val > 0) {
            const x = getX(pt.T);
            const y = getYTemp(val);
            if (!inSegment) {
              ctx.beginPath();
              ctx.moveTo(x, y);
              inSegment = true;
            } else {
              ctx.lineTo(x, y);
            }
          } else {
            if (inSegment) {
              ctx.stroke();
              inSegment = false;
            }
          }
        });
        if (inSegment) ctx.stroke();
        ctx.restore();

        // 2. Leistungskurve (Dashed, Watt)
        const wattColor = (idx === 0)
          ? (isDark ? '#6CCB5F' : '#107C41')
          : (idx === 1)
            ? (isDark ? '#FBBF24' : '#D97706')
            : getSysColor(idx, isDark);

        ctx.save();
        ctx.strokeStyle = wattColor;
        ctx.lineWidth = isBase ? 2.2 : 1.6;
        ctx.setLineDash([4, 3]);

        let inWattSegment = false;
        srs.forEach(pt => {
          const wVal = (chartMode === 'cpu')
            ? ((pt.SysW != null && pt.SysW > 0) ? pt.SysW : pt.CpuW)
            : (pt.GpuW != null ? pt.GpuW : pt.IGpuW);

          if (wVal != null && wVal > 0) {
            const x = getX(pt.T);
            const y = getYWatt(wVal);
            if (!inWattSegment) {
              ctx.beginPath();
              ctx.moveTo(x, y);
              inWattSegment = true;
            } else {
              ctx.lineTo(x, y);
            }
          } else {
            if (inWattSegment) {
              ctx.stroke();
              inWattSegment = false;
            }
          }
        });
        if (inWattSegment) ctx.stroke();
        ctx.restore();
      } else {
        // Reiner Watt-Modus
        const color = getSysColor(idx, isDark);
        ctx.save();
        ctx.strokeStyle = color;
        ctx.lineWidth = isBase ? 3.0 : 2.0;
        if (!isBase && idx % 2 === 1) ctx.setLineDash([6, 3]);

        let inSegment = false;
        srs.forEach(pt => {
          const val = (pt.SysW != null && pt.SysW > 0) ? pt.SysW : pt.CpuW;
          if (val != null && val > 0) {
            const x = getX(pt.T);
            const y = getYWatt(val);
            if (!inSegment) {
              ctx.beginPath();
              ctx.moveTo(x, y);
              inSegment = true;
            } else {
              ctx.lineTo(x, y);
            }
          } else {
            if (inSegment) {
              ctx.stroke();
              inSegment = false;
            }
          }
        });
        if (inSegment) ctx.stroke();
        ctx.restore();
      }
    });

    // HOVER INTERACTION
    canvas.onmousemove = function(e) {
      const mouseRect = canvas.getBoundingClientRect();
      const mouseX = e.clientX - mouseRect.left;
      if (mouseX < padding.left || mouseX > padding.left + chartW) {
        tooltip.style.display = 'none';
        renderChartStatic();
        return;
      }

      const ratio = (mouseX - padding.left) / chartW;
      const targetT = ratio * tMax;

      renderChartStatic();

      const cx = padding.left + ratio * chartW;

      // Crosshair
      ctx.save();
      ctx.strokeStyle = isDark ? '#707070' : '#A0A0A0';
      ctx.setLineDash([2, 2]);
      ctx.beginPath();
      ctx.moveTo(cx, padding.top);
      ctx.lineTo(cx, padding.top + chartH);
      ctx.stroke();

      // Tooltip HTML bauen
      const mm = Math.floor(targetT / 60);
      const ss = Math.floor(targetT % 60);
      const timeStr = String(mm).padStart(2, '0') + ':' + String(ss).padStart(2, '0');

      let tipHtml = `
        <div style="font-weight: 700; margin-bottom: 6px; border-bottom: 1px solid var(--card-border); padding-bottom: 3px;">
          Zeit: ${timeStr} (${targetT.toFixed(0)} s)
        </div>
      `;

      comparedSystems.forEach((s, idx) => {
        const isBase = (String(s.Id) === String(baseSystem?.Id));
        const color = getSysColor(idx, isDark);
        const sName = getShortSysName(s);
        const isBench = s.Telemetry?.TestType === 'Benchmark';
        const typeBadge = isBench ? ' [Benchmark-Messung]' : '';
        const name = (isBase ? 'Basis: ' : '') + sName + typeBadge;

        const srs = s.Telemetry?.Series || [];
        if (srs.length === 0) {
          if (isBase) {
            tipHtml += `<div style="margin-top: 5px; font-size: 11px; line-height: 1.35;">
              <div style="color: ${color}; font-weight: 600; white-space: nowrap;">● ${escapeHtml(name)}</div>
              <div style="padding-left: 14px; font-style: italic; color: var(--text-muted); white-space: nowrap;">(keine Zeitreihe)</div>
            </div>`;
          }
          return;
        }

        let closest = srs[0];
        let minDiff = Infinity;
        srs.forEach(pt => {
          const diff = Math.abs(pt.T - targetT);
          if (diff < minDiff) { minDiff = diff; closest = pt; }
        });

        let valStr = '';
        if (chartMode === 'cpu') {
          const tempStr = closest.Temp != null ? closest.Temp.toFixed(1) + ' °C' : 'n/v';
          const mhzStr = closest.MHz != null ? closest.MHz.toFixed(0) + ' MHz' : 'n/v';
          const wattStr = closest.CpuW != null ? closest.CpuW.toFixed(1) + ' W' : 'n/v';
          valStr = `${tempStr} &middot; ${mhzStr} &middot; ${wattStr}`;

          if (closest.Temp != null && closest.Temp > 0) {
            const tDotColor = (idx === 0) ? (isDark ? '#4CC2FF' : '#0078D4') : (idx === 1 ? (isDark ? '#FFA057' : '#F7630C') : color);
            ctx.fillStyle = tDotColor;
            ctx.beginPath();
            ctx.arc(cx, getYTemp(closest.Temp), 4.5, 0, Math.PI * 2);
            ctx.fill();
          }
          if (closest.CpuW != null && closest.CpuW > 0) {
            const wDotColor = (idx === 0) ? (isDark ? '#6CCB5F' : '#107C41') : (idx === 1 ? (isDark ? '#FBBF24' : '#D97706') : color);
            ctx.fillStyle = wDotColor;
            ctx.beginPath();
            ctx.arc(cx, getYWatt(closest.CpuW), 4.0, 0, Math.PI * 2);
            ctx.fill();
          }
        } else if (chartMode === 'gpu') {
          // GPU
          const gTemp = closest.GpuTemp != null ? closest.GpuTemp : closest.IGpuTemp;
          const gMhz = closest.GpuMHz != null ? closest.GpuMHz : closest.IGpuMHz;
          const gWatt = closest.GpuW != null ? closest.GpuW : closest.IGpuW;

          const tempStr = gTemp != null ? gTemp.toFixed(1) + ' °C' : 'n/v';
          const mhzStr = gMhz != null ? gMhz.toFixed(0) + ' MHz' : 'n/v';
          const wattStr = gWatt != null ? gWatt.toFixed(1) + ' W' : 'n/v';
          const fpsStr = closest.Fps != null ? (' &middot; ' + closest.Fps.toFixed(0) + ' Bilder/s') : '';
          valStr = `${tempStr} &middot; ${mhzStr} &middot; ${wattStr}${fpsStr}`;

          if (gTemp != null && gTemp > 0) {
            const tDotColor = (idx === 0) ? (isDark ? '#4CC2FF' : '#0078D4') : (idx === 1 ? (isDark ? '#FFA057' : '#F7630C') : color);
            ctx.fillStyle = tDotColor;
            ctx.beginPath();
            ctx.arc(cx, getYTemp(gTemp), 4.5, 0, Math.PI * 2);
            ctx.fill();
          }
          if (gWatt != null && gWatt > 0) {
            const wDotColor = (idx === 0) ? (isDark ? '#6CCB5F' : '#107C41') : (idx === 1 ? (isDark ? '#FBBF24' : '#D97706') : color);
            ctx.fillStyle = wDotColor;
            ctx.beginPath();
            ctx.arc(cx, getYWatt(gWatt), 4.0, 0, Math.PI * 2);
            ctx.fill();
          }
        } else {
          // Watt
          const sysWStr = closest.SysW != null ? '~' + closest.SysW.toFixed(0) + ' W (System)' : 'n/v';
          const cpuWStr = closest.CpuW != null ? closest.CpuW.toFixed(1) + ' W (CPU)' : 'n/v';
          const gpuWStr = closest.GpuW != null ? closest.GpuW.toFixed(1) + ' W (GPU)' : '';
          valStr = [sysWStr, cpuWStr, gpuWStr].filter(Boolean).join(' · ');

          const pPlot = closest.SysW != null ? closest.SysW : closest.CpuW;
          if (pPlot != null && pPlot > 0) {
            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.arc(cx, getYWatt(pPlot), 4.5, 0, Math.PI * 2);
            ctx.fill();
          }
        }

        tipHtml += `<div style="margin-top: 5px; font-size: 11px; line-height: 1.35;">
          <div style="color: ${color}; font-weight: 600; white-space: nowrap;">● ${escapeHtml(name)}</div>
          <div style="padding-left: 14px; font-weight: 700; white-space: nowrap;">${valStr}</div>
        </div>`;
      });

      ctx.restore();

      tooltip.innerHTML = tipHtml;
      tooltip.style.display = 'block';

      const tipW = Math.max(260, tooltip.offsetWidth || 280);
      let tooltipX = cx + 15;
      if (tooltipX + tipW > width) tooltipX = cx - tipW - 15;
      tooltip.style.left = Math.max(10, tooltipX) + 'px';
      tooltip.style.top = (padding.top + 10) + 'px';
    };

    canvas.onmouseleave = function() {
      tooltip.style.display = 'none';
      renderChartStatic();
    };

    function renderChartStatic() {
      renderChartNoHover();
    }
  }

  function renderChartNoHover() {
    renderChart();
  }

  // DOM READY
