function Get-ReportCss {
    return @'
:root{--bg:#f5f6f8;--panel:#fff;--text:#1c2330;--muted:#5f6878;--line:#e2e5ea;--code:#f1f3f6;
--crit:#b42318;--crit-bg:#fdeceb;--warn:#9a5b00;--warn-bg:#fdf2d8;--info:#1f5bc4;--info-bg:#e7efff;--ok:#11703f;--ok-bg:#e2f5e9;--skip:#667085;--skip-bg:#eceef2}
@media (prefers-color-scheme:dark){:root{--bg:#111419;--panel:#1a1f27;--text:#e5e8ee;--muted:#98a1b0;--line:#2b323d;--code:#141820;
--crit:#ff8f86;--crit-bg:#3b1d1c;--warn:#f3c26e;--warn-bg:#3a2d12;--info:#94b6ff;--info-bg:#1b2944;--ok:#7cd6a0;--ok-bg:#14321f;--skip:#a3abb8;--skip-bg:#252b35}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 "Segoe UI",system-ui,-apple-system,sans-serif}
main{max-width:1200px;margin:0 auto;padding:28px 20px 60px}
header{display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap;margin-bottom:22px}
h1{margin:0;font-size:27px;font-weight:650}
h1 span{color:var(--muted);font-weight:400}
.meta{margin:4px 0 0;color:var(--muted);font-size:13.5px}
.verdict{padding:9px 18px;border-radius:999px;font-weight:650;font-size:15px}
.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-bottom:20px}
.card{background:var(--panel);border:1px solid var(--line);border-left:6px solid var(--line);border-radius:12px;padding:14px 18px}
.card b{display:block;font-size:32px;line-height:1.15;font-variant-numeric:tabular-nums}
.card span{color:var(--muted)}
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
.cards{grid-template-columns:repeat(auto-fit,minmax(170px,1fr))}
.card.st,.card.st.ok,.card.st.info,.card.st.warn{background:var(--panel);color:var(--text)}
.card.st.ok{border-left-color:var(--ok)} .card.st.ok b{color:var(--ok)} .card.st.info{border-left-color:var(--info)} .card.st.info b{color:var(--info)} .card.st.warn{border-left-color:var(--warn)} .card.st.warn b{color:var(--warn)}
.card.bench{background:var(--panel);color:var(--text);border-left-color:var(--accent,#2563eb)} .card.bench b{color:var(--accent,#2563eb)}
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
.chart .hit{fill:transparent}
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
a.tile,.tile{display:block;text-decoration:none;color:inherit;background:var(--panel);border:1px solid var(--line);border-top:4px solid var(--line);border-radius:10px;padding:11px 14px 12px}
a.tile:hover,.tile:hover{border-color:var(--muted)}
.tile.profile{border-top-width:5px}
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
@media print{body{background:#fff}button{display:none}.box{break-inside:avoid}}
'@
}

