function Get-ReportCss {
    return @'
:root{--bg:#f5f6f8;--panel:#fff;--text:#1c2330;--muted:#5f6878;--line:#e2e5ea;--code:#f1f3f6;
--accent:#0067c0;--accent-hover:#005a9e;--accent-soft:#ebf3fb;--accent-border:#bdd7ee;
--crit:#b42318;--crit-bg:#fdeceb;--warn:#9a5b00;--warn-bg:#fdf2d8;--info:#1f5bc4;--info-bg:#e7efff;--ok:#11703f;--ok-bg:#e2f5e9;--skip:#667085;--skip-bg:#eceef2}
@media (prefers-color-scheme:dark){:root{--bg:#111419;--panel:#1a1f27;--text:#e5e8ee;--muted:#98a1b0;--line:#2b323d;--code:#141820;
--accent:#4cc2ff;--accent-hover:#60cdff;--accent-soft:#233446;--accent-border:#1e4e79;
--crit:#ff8f86;--crit-bg:#3b1d1c;--warn:#f3c26e;--warn-bg:#3a2d12;--info:#94b6ff;--info-bg:#1b2944;--ok:#7cd6a0;--ok-bg:#14321f;--skip:#a3abb8;--skip-bg:#252b35}}
.report-nav{position:sticky;top:0;z-index:100;background:var(--bg);padding:10px 0;margin-bottom:18px;border-bottom:1px solid var(--line);display:flex;gap:8px;flex-wrap:wrap;align-items:center;box-shadow:0 2px 8px rgba(0,0,0,0.06)}
.tab-btn{font:inherit;font-size:13.5px;font-weight:600;padding:7px 16px;border-radius:8px;border:1px solid var(--line);background:var(--panel);color:var(--text);cursor:pointer;transition:all .15s ease}
.tab-btn:hover{border-color:var(--muted);background:var(--code)}
.tab-btn.active{background:var(--accent);color:#fff;border-color:var(--accent);box-shadow:0 2px 6px rgba(0,103,192,0.25)}
a.tab-btn{text-decoration:none;display:inline-flex;align-items:center}
.tab-btn.btn-dash{margin-left:auto;text-decoration:none;color:var(--accent);border-color:var(--accent);background:var(--panel);font-weight:650}
.tab-btn.btn-dash:hover{background:var(--accent);color:var(--bg);border-color:var(--accent);box-shadow:0 2px 8px rgba(0,103,192,0.3)}
.filter-bar{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-bottom:14px;padding:10px 14px;background:var(--code);border-radius:10px;border:1px solid var(--line)}
.search-input{flex:1;min-width:220px;padding:8px 12px;border-radius:8px;border:1px solid var(--line);background:var(--panel);color:var(--text);font:inherit;font-size:13.5px;outline:none}
.search-input:focus{border-color:var(--accent)}
.filter-chips{display:flex;gap:6px;flex-wrap:wrap;align-items:center}
.fchip{font:inherit;font-size:12px;font-weight:650;padding:5px 12px;border-radius:999px;border:1px solid var(--line);background:var(--panel);color:var(--muted);cursor:pointer;transition:all .12s ease;text-transform:uppercase}
.fchip:hover{border-color:var(--text);color:var(--text)}
.fchip.active{background:var(--text);color:var(--bg);border-color:var(--text)}
.fchip.chip-crit.active{background:var(--crit);color:#fff;border-color:var(--crit)}
.fchip.chip-warn.active{background:var(--warn);color:#fff;border-color:var(--warn)}
.fchip.chip-info.active{background:var(--info);color:#fff;border-color:var(--info)}
.filter-count{font-size:12.5px;color:var(--muted);font-weight:600;white-space:nowrap;margin-left:auto}
.chart-tooltip{position:absolute;pointer-events:none;z-index:1000;padding:8px 12px;border-radius:8px;font-size:12.5px;font-weight:500;line-height:1.45;background:var(--panel);color:var(--text);border:1px solid var(--line);box-shadow:0 8px 24px rgba(0,0,0,0.2);transition:opacity .1s ease;min-width:140px;max-width:320px}
.back-to-top{position:fixed;bottom:24px;right:24px;width:40px;height:40px;border-radius:50%;background:var(--panel);border:1px solid var(--line);color:var(--text);font-size:16px;cursor:pointer;display:flex;align-items:center;justify-content:center;box-shadow:0 3px 10px rgba(0,0,0,0.15);opacity:0;visibility:hidden;transition:all .2s ease;z-index:99}
.back-to-top.visible{opacity:.9;visibility:visible}
.back-to-top:hover{opacity:1;background:var(--accent);color:#fff;border-color:var(--accent);transform:translateY(-2px);box-shadow:0 4px 12px rgba(0,103,192,0.35)}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 "Segoe UI",system-ui,-apple-system,sans-serif}
main{max-width:1200px;margin:0 auto;padding:28px 20px 60px}
header{display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap;margin-bottom:22px}
h1{margin:0;font-size:27px;font-weight:650}
h1 span{color:var(--muted);font-weight:400}
.meta{margin:4px 0 0;color:var(--muted);font-size:13.5px}
.verdict{padding:9px 18px;border-radius:999px;font-weight:650;font-size:15px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:10px;margin-bottom:20px}
.card{background:var(--panel);border:1px solid var(--line);border-left:5px solid var(--line);border-radius:10px;padding:10px 12px}
.card b{display:block;font-size:25px;line-height:1.15;font-variant-numeric:tabular-nums}
.card span{color:var(--muted);font-size:12px;line-height:1.3;display:block;margin-top:3px}
.box{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:18px 22px;margin-bottom:18px;overflow-x:auto}
.box h2{font-size:17px;margin:0 0 12px;font-weight:650}
dl{display:grid;grid-template-columns:190px 1fr;gap:7px 18px;margin:0}
dt{color:var(--muted)} dd{margin:0}
table{width:100%;border-collapse:collapse;font-size:14px}
th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
tr:last-child td{border-bottom:0}
th{color:var(--muted);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.05em}
.badge{display:inline-block;padding:2px 10px;border-radius:999px;font-size:12px;font-weight:650;white-space:nowrap;text-transform:uppercase}
.crit{background:var(--crit-bg);color:var(--crit)} .warn{background:var(--warn-bg);color:var(--warn)}
.info{background:var(--info-bg);color:var(--info)} .ok{background:var(--ok-bg);color:var(--ok)} .skip{background:var(--skip-bg);color:var(--skip)}
.card.crit,.card.warn,.card.info{background:var(--panel)}
.card.crit{border-left-color:var(--crit)} .card.crit b{color:var(--crit)}
.card.warn{border-left-color:var(--warn)} .card.warn b{color:var(--warn)}
.card.info{border-left-color:var(--info)} .card.info b{color:var(--info)}
.card.ok{border-left-color:var(--ok)} .card.ok b{color:var(--ok)}
.cards{grid-template-columns:repeat(auto-fit,minmax(120px,1fr))}
.card.st,.card.st.ok,.card.st.info,.card.st.warn{background:var(--panel);color:var(--text)}
.card.st.ok{border-left-color:var(--ok)} .card.st.ok b{color:var(--ok)} .card.st.info{border-left-color:var(--info)} .card.st.info b{color:var(--info)} .card.st.warn{border-left-color:var(--warn)} .card.st.warn b{color:var(--warn)}
.card.bench{background:var(--panel);color:var(--text);border-left-color:var(--accent,#2563eb)} .card.bench b{color:var(--accent,#2563eb)} .card.pwr{background:var(--panel);color:var(--text);border-left-color:#d97706} .card.pwr b{color:#d97706}
.card.eff{background:var(--panel);color:var(--text);border-left-color:#10b981} .card.eff b{color:#10b981}
.card.metric{background:var(--panel);color:var(--text);border-left-color:var(--accent,#2563eb)} .card.metric b{color:var(--accent,#2563eb)}
.card.metric.cpu{border-left-color:var(--info)} .card.metric.cpu b{color:var(--info)}
.card.metric.gpu{border-left-color:#c2410c} .card.metric.gpu b{color:#c2410c}
.card.metric.disk{border-left-color:#0f766e} .card.metric.disk b{color:#0f766e}
.card b small{font-size:12px;font-weight:600;color:var(--muted);margin-left:2px}
.box.stab,.box.stab.warn,.box.stab.info,.box.stab.ok{background:var(--panel);color:var(--text);border-left:6px solid var(--line)}
.box.stab.warn{border-left-color:var(--warn)} .box.stab.info{border-left-color:var(--info)} .box.stab p{margin:0}
.empty{color:var(--muted);margin:0}
.bar{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:8px}
.bar h2{margin:0}
button{font:inherit;font-size:13px;padding:5px 12px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--text);cursor:pointer}
details{border-top:1px solid var(--line)} details:first-of-type{border-top:0}
summary{cursor:pointer;padding:10px 2px;font-weight:600}
pre{margin:0 0 14px;padding:14px;background:var(--code);border-radius:8px;overflow:auto;font:12.5px/1.45 Consolas,"Cascadia Mono",monospace;white-space:pre}
footer{color:var(--muted);font-size:12.5px;margin-top:26px}
.note{color:var(--muted);font-size:13px;margin:-4px 0 12px}
.box h3{font-size:14px;font-weight:600;margin:14px 0 6px}
td.num{white-space:nowrap;font-variant-numeric:tabular-nums}
td.idx{white-space:nowrap}
.ib{position:relative;display:inline-block;width:130px;height:8px;border-radius:4px;background:var(--skip-bg);vertical-align:middle;margin-right:8px}
.ibf{position:absolute;left:0;top:0;bottom:0;border-radius:4px}
.ibf.ok{background:var(--ok)} .ibf.warn{background:var(--warn)} .ibf.crit{background:var(--crit)} .ibf.info{background:var(--info)} .ibf.skip{background:var(--skip)}
.ibm{position:absolute;left:66.7%;top:-3px;bottom:-3px;width:2px;background:var(--muted)}
.ib.s{width:64px}
details.grp{border:1px solid var(--line);border-radius:10px;margin:10px 0 0;padding:0 14px}
details.grp:first-of-type{border-top:1px solid var(--line)}
details.grp>summary{display:flex;align-items:center;gap:14px;flex-wrap:wrap;list-style:none;padding:12px 0}
details.grp>summary::-webkit-details-marker{display:none}
details.grp>summary::before{content:"";width:7px;height:7px;border-right:2px solid var(--muted);border-bottom:2px solid var(--muted);transform:rotate(-45deg);transition:transform .15s;margin:0 2px 0 2px}
details.grp[open]>summary::before{transform:rotate(45deg)}
details.grp[open]>summary{border-bottom:1px solid var(--line)}
details.grp table{margin:6px 0 10px}
.gname{font-weight:650;min-width:135px}
.gsub{flex:1;color:var(--muted);font-weight:400;font-size:14px;min-width:200px}
.gref{color:var(--muted);font-weight:400;font-size:13.5px;white-space:nowrap}
.gref b{color:var(--text);font-variant-numeric:tabular-nums}
th.r,td.r{text-align:right}
td.muted{color:var(--muted)}
td small{color:var(--muted);font-size:12px}
small.hint{display:block;color:var(--muted);font-size:12.5px;line-height:1.35;margin-top:1px}
table.disks td,table.disks th{padding:8px 8px}
table.disks th{white-space:nowrap}
.note.tight{margin:0 0 12px}
.tw{overflow-x:auto}
td.nw{white-space:nowrap}
th small{font-weight:400;text-transform:none;letter-spacing:0}
.chart{width:100%;height:auto;display:block}
.chart text{fill:var(--muted);font-size:12px;font-family:inherit}
.chart .grid{stroke:var(--line);stroke-width:1}
.chart .tick{stroke:var(--line)}
.chart .line{fill:none;stroke:var(--info);stroke-width:2;stroke-linejoin:round;stroke-linecap:round}
.chart .hit{fill:transparent;stroke:transparent;stroke-width:10}
.chart .hit:hover{fill:var(--info)}
.chart .line.s1{stroke:var(--info)} .chart .line.s2{stroke:#c2410c} .chart .line.s3{stroke:#0f766e} .chart .line.s4{stroke:#7c3aed} .chart .line.s5{stroke:#ca8a04;stroke-dasharray:5 3}
.chart .hit.s2:hover{fill:#c2410c} .chart .hit.s3:hover{fill:#0f766e} .chart .hit.s4:hover{fill:#7c3aed} .chart .hit.s5:hover{fill:#ca8a04}
.chart line.lim{stroke:var(--crit);stroke-width:1.5;stroke-dasharray:6 4} .chart line.tj{stroke:var(--warn);stroke-width:1.5;stroke-dasharray:2 4}
.chart line.mark{stroke:var(--muted);stroke-width:1;stroke-dasharray:3 3} .chart text.mk{font-size:11px;paint-order:stroke;stroke:var(--panel);stroke-width:3px;stroke-linejoin:round}
.lgd{display:flex;flex-wrap:wrap;gap:4px 18px;margin:0 0 4px;font-size:13px} .lgd small{color:var(--muted)}
i.sw.s1{background:var(--info)} i.sw.s2{background:#c2410c} i.sw.s3{background:#0f766e} i.sw.s4{background:#7c3aed} i.sw.s5{background:#ca8a04}
i.sw.lim{background:transparent;border-top:2px dashed var(--crit);border-radius:0;height:0;width:16px;vertical-align:3px}
i.sw.tj{background:transparent;border-top:2px dotted var(--warn);border-radius:0;height:0;width:16px;vertical-align:3px}
.thr{border:1px solid var(--line);border-left:6px solid var(--line);border-radius:10px;padding:10px 14px;margin:8px 0 14px}
.thr.warn{border-left-color:var(--warn);background:var(--panel);color:var(--text)} .thr.info{border-left-color:var(--info);background:var(--panel);color:var(--text)} .thr.ok{border-left-color:var(--ok);background:var(--panel);color:var(--text)}
.thr ul{margin:6px 0 0;padding-left:18px;color:var(--muted);font-size:13.5px}
@media (prefers-color-scheme:dark){.chart .line.s2{stroke:#fb923c} .chart .line.s3{stroke:#2dd4bf} .chart .line.s4{stroke:#c4b5fd} i.sw.s2{background:#fb923c} i.sw.s3{background:#2dd4bf} i.sw.s4{background:#c4b5fd} .chart .line.s5{stroke:#facc15} i.sw.s5{background:#facc15}}
small.okt{color:var(--ok)} small.warnt{color:var(--warn)}
.ov{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin:2px 0 14px}
.ov.profile-grid{gap:14px;margin:4px 0 18px}
a.tile,.tile{display:block;text-decoration:none;color:inherit;background:var(--panel);border:1px solid var(--line);border-top:4px solid var(--line);border-radius:10px;padding:11px 14px 12px}
a.tile:hover,.tile:hover{border-color:var(--muted)}
.tile.profile{background:var(--accent-soft);border:1px solid var(--accent-border);border-top:5px solid var(--accent);box-shadow:0 1px 4px rgba(0,0,0,0.04);cursor:help}
.tile.profile h4{color:var(--text);font-size:13px;letter-spacing:0;text-transform:none}
.tile.profile .pword{font-weight:600;font-size:13px;color:var(--accent);margin:2px 0 6px}
.tile.tok,a.tile.tok{border-top-color:var(--ok)} .tile.twarn,a.tile.twarn{border-top-color:var(--warn)} .tile.tcrit,a.tile.tcrit{border-top-color:var(--crit)} .tile.tinfo,a.tile.tinfo{border-top-color:var(--info)}
.tile h4{display:flex;justify-content:space-between;align-items:center;gap:8px;margin:0;font-size:12.5px;color:var(--muted);font-weight:600;text-transform:uppercase;letter-spacing:.04em}
.tile h4 .dot{width:9px;height:9px;border-radius:50%;flex:none}
.dot.ok{background:var(--ok)} .dot.warn{background:var(--warn)} .dot.crit{background:var(--crit)} .dot.info{background:var(--info)}
.tile .big{font-size:27px;font-weight:650;font-variant-numeric:tabular-nums;line-height:1.2;margin:6px 0 8px}
.tile .big small{font-size:13px;color:var(--muted);font-weight:400}
.tile p{margin:8px 0 0;font-size:12.5px;color:var(--muted);line-height:1.35}
.rb{position:relative;display:block;height:9px;border-radius:5px;background:var(--skip-bg)}
.rb.s{display:inline-block;width:80px;height:7px;vertical-align:middle;margin-right:8px}
.rbf{position:absolute;left:0;top:0;bottom:0;border-radius:5px}
.rbf.ok{background:var(--ok)} .rbf.warn{background:var(--warn)} .rbf.crit{background:var(--crit)} .rbf.info{background:var(--info)} .rbf.skip{background:var(--skip)}
.rbm{position:absolute;left:66.7%;top:-3px;bottom:-3px;width:2px;background:var(--text);opacity:.45}
.dl{color:var(--muted);font-size:12px;margin-left:6px;white-space:nowrap} .dl.okt{color:var(--ok)} .dl.warnt{color:var(--warn)}
td .dl{margin-left:0}
.grp-head{display:flex;justify-content:space-between;align-items:center;padding:12px 0;border-bottom:1px solid var(--line);margin-bottom:8px;flex-wrap:wrap;gap:8px}
.comp-title{font-size:16px;font-weight:700}
.comp-score{font-size:15px;font-variant-numeric:tabular-nums;text-align:right}
.gh-bar{margin-top:4px}
.pword{font-weight:600;color:var(--muted)}
.bench-cols{display:grid;grid-template-columns:180px repeat(auto-fit,minmax(120px,1fr));gap:12px;padding:12px 0}
.bcol{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px 12px;display:flex;flex-direction:column;justify-content:space-between;gap:6px}
.bcol-main{background:var(--skip-bg);border-color:var(--muted)}
.bname{font-size:12px;color:var(--muted);font-weight:600;text-transform:uppercase;letter-spacing:.03em;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bscore{font-size:24px;font-weight:750;font-variant-numeric:tabular-nums}
.bword{font-size:13px;font-weight:600;color:var(--muted);margin-bottom:2px}
.bval{font-size:18px;font-weight:700;font-variant-numeric:tabular-nums}
.bbar{margin:3px 0}
.bdelta{font-size:12px;color:var(--muted);white-space:nowrap}
.chart.ws{max-width:860px}
.chart.ws rect.bg{fill:var(--skip-bg)}
.chart.ws rect.b-ok{fill:var(--ok)} .chart.ws rect.b-info{fill:var(--info)} .chart.ws rect.b-warn{fill:var(--warn)} .chart.ws rect.b-crit{fill:var(--crit)}
.chart.ws text.l{fill:var(--text);font-size:13.5px}
.chart.ws text.v{fill:var(--text);font-size:14px;font-weight:650}
.chart.ws tspan.d{fill:var(--muted);font-weight:400;font-size:12px}
.chart.ws line.tot{stroke:var(--text);stroke-width:1.5;stroke-dasharray:5 4;opacity:.6}
.chart.ws text.tl{fill:var(--text);font-size:12px;font-weight:600}
:root{--s0:#2f6fde;--s1:#e07a1f;--s2:#1f9d8a;--s3:#9b4dca;--s4:#d14b4b;--s5:#6b7a8f}
@media (prefers-color-scheme:dark){:root{--s0:#6e9cf5;--s1:#f0a057;--s2:#4cc7b3;--s3:#c08ae6;--s4:#ef7f7f;--s5:#9aa7b8}}
.c0{background:var(--s0)} .c1{background:var(--s1)} .c2{background:var(--s2)} .c3{background:var(--s3)} .c4{background:var(--s4)} .c5{background:var(--s5)}
i.sw{display:inline-block;width:11px;height:11px;border-radius:3px;margin-right:7px;vertical-align:-1px;flex:none}
.mrow{display:grid;grid-template-columns:240px 1fr;gap:6px 20px;padding:11px 0;border-top:1px solid var(--line)}
.box h2+.mrow,.box .note+.mrow,.mgh+.mrow{border-top:0}
.mlab{font-weight:600;font-size:14px;line-height:1.35}
.mlab small{display:block;color:var(--muted);font-weight:400;font-size:12px;margin-top:2px}
.mb{display:grid;grid-template-columns:minmax(90px,170px) 1fr minmax(120px,190px);align-items:center;gap:10px;font-size:13px;margin:3px 0}
.mn{display:flex;align-items:center;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mt{height:13px;border-radius:7px;background:var(--skip-bg);position:relative;overflow:hidden}
.mf{position:absolute;left:0;top:0;bottom:0;border-radius:7px}
.mv{font-variant-numeric:tabular-nums;white-space:nowrap}
.mv.na{color:var(--muted);font-style:italic}
.mb.best .mv{font-weight:650}
.mb.own .mn{color:var(--text);font-weight:700}.mb.own .mt{outline:2px solid var(--accent,#2563eb);outline-offset:1px;border-radius:4px}
.mb.own .mn::after{content:" (dieser PC)";font-weight:400;color:var(--muted)}
.mgh{font-size:13px;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;font-weight:600;margin:16px 0 2px}
.mgh:first-of-type{margin-top:4px}
.syscards{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px;margin-bottom:18px}
.sys{background:var(--panel);border:1px solid var(--line);border-top:5px solid var(--line);border-radius:12px;padding:14px 18px}
.sys.k0{border-top-color:var(--s0)} .sys.k1{border-top-color:var(--s1)} .sys.k2{border-top-color:var(--s2)} .sys.k3{border-top-color:var(--s3)} .sys.k4{border-top-color:var(--s4)} .sys.k5{border-top-color:var(--s5)}
.sys h3{margin:0;font-size:18px;display:flex;align-items:center}
.sys .meta{margin:0 0 10px}
.sys dl{grid-template-columns:110px 1fr;font-size:13.5px;gap:4px 12px}
.bfc{margin:12px 0 0}
.mini{display:inline-block;position:relative;width:60px;height:6px;border-radius:3px;background:var(--skip-bg);overflow:hidden;vertical-align:middle;margin-right:8px}
.mini .mf{border-radius:3px}
@media (max-width:700px){.mrow{grid-template-columns:1fr}.mb{grid-template-columns:90px 1fr 120px}}
@media (max-width:700px){.cards{grid-template-columns:1fr}dl{grid-template-columns:1fr}dt{margin-top:6px}.bench-cols{grid-template-columns:1fr}}
.pwr-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px;margin:12px 0 16px}
.pwr-card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px 16px}
.pwr-card h4{margin:0 0 4px;font-size:12.5px;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}
.pwr-card .pwr-val{font-size:24px;font-weight:700;color:var(--text);line-height:1.2}
.pwr-card .pwr-sub{font-size:12px;color:var(--muted);margin-top:2px}
.calc-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin-top:10px;padding:14px;background:var(--code);border-radius:10px;border:1px solid var(--line)}
.calc-field{display:flex;flex-direction:column;gap:4px}
.calc-field label{font-size:12px;font-weight:600;color:var(--muted)}
.calc-field input{font:inherit;font-size:13.5px;padding:6px 10px;border-radius:6px;border:1px solid var(--line);background:var(--panel);color:var(--text)}
.calc-res{display:flex;flex-direction:column;justify-content:center;padding:10px 14px;background:var(--panel);border-radius:8px;border:1px solid var(--line)}
.calc-res b{font-size:20px;color:var(--accent,#0067c0);line-height:1.2}
.boot-bar-container{margin:12px 0 10px;background:var(--code);border-radius:8px;padding:3px;border:1px solid var(--line)}
.boot-bar{display:flex;height:24px;border-radius:6px;overflow:hidden;font-size:11px;font-weight:650;color:#fff;line-height:24px;text-align:center}
.boot-seg{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;padding:0 6px;transition:opacity .15s}
.boot-seg:hover{opacity:.85}
.boot-bios{background:#8b5cf6}
.boot-kernel{background:#2563eb}
.boot-post{background:#f59e0b}
.boot-legend{display:flex;gap:16px;flex-wrap:wrap;font-size:13px;margin-top:8px}
.boot-leg-item{display:inline-flex;align-items:center;gap:6px}
.boot-dot{width:10px;height:10px;border-radius:50%;display:inline-block}
@media print{body{background:#fff}button{display:none}.box{break-inside:avoid}}
'@
}

