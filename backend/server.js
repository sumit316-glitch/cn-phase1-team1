// ============================================================
// CN Project - Phase 1 backend (same file runs on Mac 3 and Mac 4)
//
//   Mac 3:  BACKEND=A PORT=3001 node server.js
//   Mac 4:  BACKEND=B PORT=3002 node server.js
//
// Zero dependencies: only Node's built-in modules. No npm install.
//
// Endpoints
//   GET /            small HTML page (buttons call the two APIs below)
//   GET /api/status  JSON {backend, status, ...}   Cache-Control: no-store
//   GET /api/info    JSON identical on A and B     Cache-Control: max-age=60 + ETag
//                    -> If-None-Match with the same ETag returns 304 Not Modified
// Every response carries the header  X-Backend: A  (or B)
// ============================================================

const http = require('http');
const os = require('os');
const crypto = require('crypto');

const BACKEND = (process.env.BACKEND || 'A').toUpperCase();
const PORT = parseInt(process.env.PORT || (BACKEND === 'A' ? '3001' : '3002'), 10);
const HOST = '0.0.0.0'; // listen on ALL interfaces, not just 127.0.0.1, so Mac 2 can reach us

// ---- Cacheable content -------------------------------------------------
// This body is byte-for-byte the SAME on both backends, so its ETag is the
// same too. That way a conditional request gets 304 no matter which backend
// the load balancer picks.
const INFO_BODY = JSON.stringify({
  service: 'team1 private network service',
  version: '1.0.0',
  note: 'This response may be cached for 60 seconds, then revalidated with its ETag.'
}, null, 2) + '\n';
const INFO_ETAG = '"' + crypto.createHash('sha1').update(INFO_BODY).digest('hex').slice(0, 16) + '"';

// ---- Helpers -----------------------------------------------------------
function send(res, status, headers, body = '') {
  const buf = Buffer.from(body);
  const all = { 'X-Backend': BACKEND, ...headers };
  if (status !== 304) all['Content-Length'] = buf.length; // 304 must not carry a body
  res.writeHead(status, all);
  res.end(status === 304 ? undefined : buf);
}

function etagMatches(header) {
  if (!header) return false;
  return header.split(',')
    .map(t => t.trim().replace(/^W\//, ''))
    .some(t => t === INFO_ETAG || t === '*');
}

function pageHtml() {
  const accent = BACKEND === 'A' ? '#2457c5' : '#a8641a';
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>team1.test - served by backend ${BACKEND}</title>
<style>
  :root { --accent: ${accent}; --ink: #1b1f24; --quiet: #5b6470; --line: #d9dde3; --bg: #fbfbfc; }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--ink);
         font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
  main { max-width: 680px; margin: 0 auto; padding: 48px 24px; }
  .who { display: flex; align-items: center; gap: 20px; border-left: 6px solid var(--accent); padding-left: 20px; }
  .letter { font-size: 88px; line-height: 1; font-weight: 700; color: var(--accent); }
  h1 { margin: 0; font-size: 22px; }
  p { color: var(--quiet); margin: 4px 0 0; }
  .actions { display: flex; flex-wrap: wrap; gap: 12px; margin: 36px 0 16px; }
  button { font: inherit; padding: 10px 16px; border-radius: 6px; border: 1px solid var(--line);
           background: #fff; color: var(--ink); cursor: pointer; }
  button:hover { border-color: var(--accent); }
  button:focus-visible { outline: 3px solid var(--accent); outline-offset: 2px; }
  pre { background: #fff; border: 1px solid var(--line); border-radius: 6px; padding: 16px;
        font: 13px/1.5 ui-monospace, Menlo, monospace; overflow-x: auto; min-height: 120px; }
</style>
</head>
<body>
<main>
  <div class="who">
    <div class="letter" aria-hidden="true">${BACKEND}</div>
    <div>
      <h1>This page was served by backend ${BACKEND}</h1>
      <p>${os.hostname()} on port ${PORT}, reached through the nginx edge.</p>
    </div>
  </div>
  <div class="actions">
    <button id="status">Call /api/status</button>
    <button id="info">Call /api/info (cached 60 s)</button>
  </div>
  <pre id="out">Press a button. Open DevTools > Network to watch each request.</pre>
</main>
<script>
  const out = document.getElementById('out');
  async function call(path) {
    const t0 = performance.now();
    const r = await fetch(path);
    const body = await r.text();
    out.textContent =
      'GET ' + path + '  ->  HTTP ' + r.status + '\\n' +
      'X-Backend: ' + r.headers.get('X-Backend') + '\\n' +
      'Cache-Control: ' + r.headers.get('Cache-Control') + '\\n' +
      'ETag: ' + r.headers.get('ETag') + '\\n' +
      'time: ' + Math.round(performance.now() - t0) + ' ms\\n\\n' + body;
  }
  document.getElementById('status').onclick = () => call('/api/status');
  document.getElementById('info').onclick = () => call('/api/info');
</script>
</body>
</html>
`;
}

// ---- Request handler ---------------------------------------------------
const server = http.createServer((req, res) => {
  const started = Date.now();
  const path = req.url.split('?')[0];

  // One log line per request. remoteAddress should be Mac 2 (the edge);
  // X-Forwarded-For carries the real client's IP, added by nginx.
  res.on('finish', () => {
    console.log(`${new Date().toISOString()}  from=${req.socket.remoteAddress}  ` +
      `client=${req.headers['x-forwarded-for'] || '-'}  host=${req.headers.host}  ` +
      `${req.method} ${req.url} -> ${res.statusCode}  ${Date.now() - started}ms`);
  });

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return send(res, 405, { 'Content-Type': 'application/json', 'Allow': 'GET, HEAD' },
      JSON.stringify({ error: 'method not allowed' }) + '\n');
  }

  if (path === '/') {
    return send(res, 200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-cache'
    }, pageHtml());
  }

  if (path === '/api/status') {
    return send(res, 200, {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store' // never cache: keeps the A/B alternation visible
    }, JSON.stringify({
      backend: BACKEND,
      status: 'ok',
      host: os.hostname(),
      port: PORT,
      time: new Date().toISOString()
    }, null, 2) + '\n');
  }

  if (path === '/api/info') {
    const cacheHeaders = { 'Cache-Control': 'public, max-age=60', 'ETag': INFO_ETAG };
    if (etagMatches(req.headers['if-none-match'])) {
      return send(res, 304, cacheHeaders); // client's copy is still valid: no body
    }
    return send(res, 200, { ...cacheHeaders, 'Content-Type': 'application/json' }, INFO_BODY);
  }

  return send(res, 404, { 'Content-Type': 'application/json' },
    JSON.stringify({ error: 'not found', path }) + '\n');
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') console.error(`Port ${PORT} is already in use. Stop the other process or pick another port.`);
  else console.error(err);
  process.exit(1);
});

server.listen(PORT, HOST, () => {
  console.log(`Backend ${BACKEND} listening on http://${HOST}:${PORT}  (ETag for /api/info = ${INFO_ETAG})`);
  const ips = Object.values(os.networkInterfaces()).flat()
    .filter(i => i && i.family === 'IPv4' && !i.internal).map(i => i.address);
  console.log(`Reachable on this LAN at: ${ips.map(ip => `http://${ip}:${PORT}`).join('  ') || '(no LAN IPv4 found)'}`);
});
