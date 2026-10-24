// Total.js Center — the Total.js Developer control panel.
//
// A single self-contained, ZERO-dependency Node server (no total5/npm to
// resolve under /opt, so it can never fail to start). It serves a dark,
// Total.js-branded dashboard on :8010 that shows everything a developer needs
// to find their way around the VM: the network address, the local domain,
// where PostgreSQL lives, and the status of
// every service. Open it from the desktop menu, from totaljs.developer, or from
// http://<vm-ip>:8010.
'use strict';

const http = require('http');
const os = require('os');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PORT = 8010;
const GREEN = '#6ac043';

// The official Total.js mark, shipped beside this file. Read once at startup
// and served at /logo.svg; falls back to an empty string if missing.
const LOGO_SVG = (() => {
  try { return fs.readFileSync(path.join(__dirname, 'logo.svg'), 'utf8'); }
  catch (_) { return ''; }
})();

// --- tiny helpers -----------------------------------------------------------

function sh(cmd) {
  try {
    return execSync(cmd, { timeout: 2500, stdio: ['ignore', 'pipe', 'ignore'] })
      .toString().trim();
  } catch (_) {
    return '';
  }
}

function readFile(path, fallback) {
  try { return fs.readFileSync(path, 'utf8').trim(); } catch (_) { return fallback; }
}

function primaryIP() {
  // The source address of the default route — the real LAN/NAT address the Mac
  // can reach, NOT docker's bridge.
  const out = sh("ip route get 1.1.1.1");
  const m = out.match(/\bsrc\s+(\d+\.\d+\.\d+\.\d+)/);
  if (m) return m[1];
  const hi = sh("hostname -I").split(/\s+/)[0];
  return hi || '127.0.0.1';
}

function serviceState(unit) {
  return sh(`systemctl is-active ${unit}`) || 'unknown';
}

function dockerState(name) {
  // Returns 'running' / 'exited ...' / '' (absent).
  return sh(`docker inspect -f '{{.State.Status}}' ${name}`);
}

// --- data gathering ---------------------------------------------------------

function gather() {
  const ip = primaryIP();
  const domain = readFile('/etc/totalvm/domain', 'totaljs.developer');

  const osRelease = readFile('/etc/os-release', '');
  const prettyMatch = osRelease.match(/PRETTY_NAME="?([^"\n]+)"?/);
  const distroName = readFile('/etc/totalvm/release', '')
    .match(/TOTALVM_NAME="?([^"\n]+)"?/)?.[1]
    || (prettyMatch ? prettyMatch[1] : 'Total.js Developer');

  const mem = os.totalmem();
  const freemem = os.freemem();
  const disk = sh("df -h --output=used,size,pcent / | tail -1").replace(/\s+/g, ' ').trim();

  return {
    hostname: os.hostname(),
    distro: distroName,
    kernel: os.release(),
    uptime: Math.floor(os.uptime()),
    cpu: (os.cpus()[0] || {}).model || os.arch(),
    cores: os.cpus().length,
    loadavg: os.loadavg().map((n) => n.toFixed(2)),
    memUsedMB: Math.round((mem - freemem) / 1048576),
    memTotalMB: Math.round(mem / 1048576),
    disk,
    ip,
    domain,
    rootUrl: `http://${domain}`,
    codeUrl: `http://code.${domain}`,
    flowUrl: `http://flow.${domain}`,
    pgadminUrl: `http://pgadmin.${domain}`,
    services: {
      code: dockerState('code') || 'absent',
      flow: dockerState('flow') || 'absent',
      proxy: dockerState('totalvm-proxy') || 'absent',
      postgresql: dockerState('postgres') || 'absent',
      pgadmin: dockerState('pgadmin') || 'absent',
      docker: serviceState('docker'),
      dnsmasq: serviceState('totaljs-dnsmasq'),
    },
    postgres: {
      host: 'postgres',
      port: 5432,
      superuser: 'totaljs',
      config: '/www/services/postgres/docker-compose.yml',
      note: 'Available to project containers on the Docker network. Edit ' +
            '/www/services/postgres/docker-compose.yml to change the version or publish it to the host.',
    },
    timestamp: new Date().toISOString(),
  };
}

// --- presentation -----------------------------------------------------------

function fmtUptime(s) {
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  return [d && `${d}d`, h && `${h}h`, `${m}m`].filter(Boolean).join(' ');
}

function page() {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Total.js Center — Total.js Developer</title>
<style>
  :root { --green:${GREEN}; --bg:#0f1316; --panel:#171c21; --panel2:#1c2228;
          --line:#2a3036; --fg:#e6e8ea; --muted:#8b949e; --soft:#12181d; }
  * { box-sizing:border-box; }
  body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Ubuntu,sans-serif;
         background:
           radial-gradient(900px 520px at 78% -10%, #20321d 0%, transparent 58%),
           linear-gradient(180deg,#11171b 0%,var(--bg) 100%) fixed;
         color:var(--fg); -webkit-font-smoothing:antialiased; }
  .wrap { max-width:1120px; margin:0 auto; padding:28px 22px 58px; }
  header { display:flex; align-items:center; gap:16px; margin-bottom:6px; }
  header h1 { font-size:22px; margin:0; font-weight:650; letter-spacing:.2px; }
  header .sub { color:var(--muted); font-size:13px; margin-top:2px; }
  .pillbar { margin-left:auto; display:flex; gap:8px; align-items:center; }
  .hero { margin-top:22px; padding:28px; border:1px solid #314029;
          border-radius:18px; background:linear-gradient(135deg,#182019 0%,#10161a 68%);
          box-shadow:0 22px 70px rgba(0,0,0,.28); }
  .hero-top { display:flex; gap:22px; align-items:flex-start; }
  .hero h2 { margin:0; font-size:44px; line-height:1; letter-spacing:-.02em; }
  .hero p { margin:12px 0 0; color:#b8c2bc; max-width:720px; font-size:16px; line-height:1.55; }
  .hero-actions { display:flex; flex-wrap:wrap; gap:10px; margin-top:22px; }
  .hero-stat { margin-left:auto; text-align:right; color:var(--muted); min-width:170px; }
  .hero-stat strong { display:block; color:var(--fg); font-size:26px; line-height:1.15; }
  .grid { display:grid; grid-template-columns:repeat(2,1fr); gap:16px; margin-top:24px; }
  .card { background:linear-gradient(180deg,var(--panel) 0%,var(--panel2) 100%);
          border:1px solid var(--line); border-radius:12px; padding:18px 20px; }
  .card.full { grid-column:1 / -1; }
  .card h2 { font-size:12px; text-transform:uppercase; letter-spacing:.12em;
             color:var(--muted); margin:0 0 14px; font-weight:600; }
  .row { display:flex; justify-content:space-between; align-items:baseline;
         padding:7px 0; border-bottom:1px dashed #232a30; gap:12px; }
  .row:last-child { border-bottom:0; }
  .row .k { color:var(--muted); font-size:13px; }
  .row .v { font-size:14px; text-align:right; word-break:break-word; }
  .mono { font-family:"Fira Code",ui-monospace,SFMono-Regular,Menlo,monospace; }
  a { color:var(--green); text-decoration:none; }
  a:hover { text-decoration:underline; }
  .big { font-size:26px; font-weight:650; }
  .badge { display:inline-flex; align-items:center; gap:6px; font-size:12px;
           padding:3px 9px; border-radius:999px; border:1px solid var(--line);
           background:#11161a; color:var(--muted); }
  .badge .dot { width:8px; height:8px; border-radius:50%; background:#5a6066; }
  .badge.ok { color:#bdeaa0; border-color:#2f4d22; } .badge.ok .dot { background:var(--green); }
  .badge.bad { color:#e7a3a3; border-color:#5a2a2a; } .badge.bad .dot { background:#e75a5a; }
  .svc { display:flex; flex-wrap:wrap; gap:10px; }
  pre { background:#0b0f12; border:1px solid var(--line); border-radius:10px;
        padding:14px 16px; overflow:auto; font-size:13px; line-height:1.5;
        font-family:"Fira Code",ui-monospace,SFMono-Regular,Menlo,monospace; color:#cdd2d6; }
  .hint { color:var(--muted); font-size:12.5px; margin-top:10px; line-height:1.55; }
  .cta { display:inline-flex; align-items:center; justify-content:center; gap:8px;
         background:var(--green); color:#0b0f12; font-weight:700;
         padding:10px 16px; border-radius:8px; min-height:40px; }
  .cta.secondary { background:#1c242a; color:var(--fg); border:1px solid var(--line); }
  .cta:hover { background:#7bd24d; text-decoration:none; }
  .cta.secondary:hover { background:#242e35; }
  footer { color:var(--muted); font-size:12px; margin-top:28px; text-align:center; }
  .copybtn { cursor:pointer; font-size:11px; color:var(--muted); border:1px solid var(--line);
             background:#11161a; border-radius:7px; padding:3px 8px; float:right; }
  .copybtn:hover { color:var(--fg); }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <img src="/logo.svg" width="44" height="44" alt="Total.js" style="display:block">
    <div>
      <h1>Total.js Center</h1>
      <div class="sub">Total.js Developer — environment entry point</div>
    </div>
    <div class="pillbar"><span id="clock" class="badge"><span class="dot"></span>live</span></div>
  </header>

  <section class="hero" id="hero"></section>

  <div class="grid" id="grid"><div class="card full"><h2>Loading…</h2></div></div>

  <footer>Total.js Developer environment · running on Apple Virtualization</footer>
</div>

<script>
const GREEN = '${GREEN}';
function esc(s){ return String(s).replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])); }
function row(k,v,mono){ return '<div class="row"><span class="k">'+esc(k)+'</span><span class="v '+(mono?'mono':'')+'">'+v+'</span></div>'; }
function badge(label,state){
  const ok = state==='running' || state==='active';
  const bad = state && state!=='running' && state!=='active' && state!=='unknown';
  const cls = ok?'ok':(bad?'bad':'');
  return '<span class="badge '+cls+'"><span class="dot"></span>'+esc(label)+' · '+esc(state)+'</span>';
}
function fmtUptime(s){ const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);
  return [d?d+'d':'',h?h+'h':'',m+'m'].filter(Boolean).join(' '); }
function copy(id){ const el=document.getElementById(id); navigator.clipboard && navigator.clipboard.writeText(el.innerText); }

function render(d){
  const svc = Object.entries(d.services).map(([k,v])=>badge(k,v)).join('');
  document.getElementById('hero').innerHTML =
    '<div class="hero-top">' +
      '<div>' +
        '<h2>Total.js Center</h2>' +
        '<p>Everything in this VM starts here. Open the editor, Flow, pgAdmin or any project from the local Total.js domain.</p>' +
      '</div>' +
      '<div class="hero-stat"><strong>'+esc(d.domain)+'</strong><span>main domain</span></div>' +
    '</div>' +
    '<div class="hero-actions">' +
      '<a class="cta" href="'+esc(d.rootUrl)+'" target="_blank">Center</a>' +
      '<a class="cta secondary" href="'+esc(d.codeUrl)+'" target="_blank">Code</a>' +
      '<a class="cta secondary" href="'+esc(d.flowUrl)+'" target="_blank">Flow</a>' +
      '<a class="cta secondary" href="'+esc(d.pgadminUrl)+'" target="_blank">pgAdmin</a>' +
    '</div>';
  const grid = [
    '<div class="card"><h2>Environment</h2>' +
      row('Distro', esc(d.distro)) +
      row('Hostname', esc(d.hostname), true) +
      row('Kernel', esc(d.kernel), true) +
      row('Uptime', fmtUptime(d.uptime)) +
      row('CPU', esc(d.cpu)+' ('+d.cores+')') +
      row('Memory', d.memUsedMB+' / '+d.memTotalMB+' MiB') +
      row('Disk /', esc(d.disk), true) +
    '</div>',

    '<div class="card"><h2>Network &amp; domain</h2>' +
      '<div class="big mono" style="color:'+GREEN+'">'+esc(d.ip)+'</div>' +
      '<div class="hint">This VM\\'s address on your network.</div>' +
      row('Local domain', esc(d.domain), true) +
      row('Center', '<a href="'+esc(d.rootUrl)+'" target="_blank">'+esc(d.rootUrl)+'</a>') +
      row('Code', '<a href="'+esc(d.codeUrl)+'" target="_blank">'+esc(d.codeUrl)+'</a>') +
      row('Flow', '<a href="'+esc(d.flowUrl)+'" target="_blank">'+esc(d.flowUrl)+'</a>') +
      row('pgAdmin', '<a href="'+esc(d.pgadminUrl)+'" target="_blank">'+esc(d.pgadminUrl)+'</a>') +
      row('Per project', '<span class="mono">&lt;project&gt;.'+esc(d.domain)+'</span>') +
      '<div class="hint">TotalVM makes this domain available automatically on the host Mac while the environment is running.</div>' +
    '</div>',

    '<div class="card"><h2>PostgreSQL</h2>' +
      row('Host', esc(d.postgres.host), true) +
      row('Port', d.postgres.port, true) +
      row('Superuser', esc(d.postgres.superuser), true) +
      row('Compose', esc(d.postgres.config), true) +
      row('pgAdmin', '<a href="'+esc(d.pgadminUrl)+'" target="_blank">'+esc(d.pgadminUrl)+'</a>') +
      '<div class="hint">'+esc(d.postgres.note)+'</div>' +
    '</div>',

    '<div class="card"><h2>Services</h2><div class="svc">'+svc+'</div>' +
      '<div style="margin-top:16px;display:flex;gap:8px;flex-wrap:wrap">' +
      '<a class="cta" href="'+esc(d.codeUrl)+'" target="_blank">Code →</a>' +
      '<a class="cta" href="'+esc(d.flowUrl)+'" target="_blank">Flow →</a>' +
      '<a class="cta" href="'+esc(d.pgadminUrl)+'" target="_blank">pgAdmin →</a></div>' +
    '</div>',
  ].join('');
  document.getElementById('grid').innerHTML = grid;
  document.getElementById('clock').innerHTML = '<span class="dot"></span>updated ' + new Date().toLocaleTimeString();
}

async function tick(){
  try { const r = await fetch('/api/status', {cache:'no-store'}); render(await r.json()); }
  catch(e){ /* keep last view */ }
}
tick(); setInterval(tick, 5000);
</script>
</body>
</html>`;
}

// --- server -----------------------------------------------------------------

const server = http.createServer((req, res) => {
  if (req.url === '/api/status') {
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(gather()));
    return;
  }
  if (req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end('{"ok":true}');
    return;
  }
  if (req.url === '/logo.svg') {
    res.writeHead(200, { 'Content-Type': 'image/svg+xml; charset=utf-8', 'Cache-Control': 'max-age=3600' });
    res.end(LOGO_SVG);
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(page());
});

// Never let a transient startup hiccup (e.g. the port still held by a previous
// instance during a restart) crash-loop the service under systemd — log it and
// retry instead of exiting non-zero.
server.on('error', (err) => {
  console.error('[totaljs-center] server error:', err && err.message);
  setTimeout(() => { try { server.close(); } catch (_) {} server.listen(PORT, '0.0.0.0'); }, 3000);
});
process.on('uncaughtException', (err) => {
  console.error('[totaljs-center] uncaught:', (err && err.stack) || err);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[totaljs-center] control panel on http://0.0.0.0:${PORT}`);
});
