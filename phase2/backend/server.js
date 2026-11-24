// CN Project backend — same file on Mac 3 (A) and Mac 4 (B). No npm packages.
//   BACKEND=A PORT=3001 node server.js      BACKEND=B PORT=3002 node server.js
// GET /            HTML page showing which backend served it
// GET /api/status  {"backend","status":"ok",...}   Cache-Control: no-store
// GET /api/info    identical JSON on A and B       Cache-Control: public, max-age=60 + ETag (304 on match)
// Every response carries X-Backend: A|B
const http = require('http'), os = require('os'), crypto = require('crypto');

const BACKEND = (process.env.BACKEND || 'A').toUpperCase();
const PORT = parseInt(process.env.PORT || (BACKEND === 'A' ? '3001' : '3002'), 10);
const HOST = '0.0.0.0';   // all interfaces, so the edge can reach us over the LAN

const INFO_BODY = JSON.stringify({ service: 'team1 private network service', version: '2.0.0',
  note: 'Cacheable for 60 seconds, then revalidated with its ETag.' }, null, 2) + '\n';
const INFO_ETAG = '"' + crypto.createHash('sha1').update(INFO_BODY).digest('hex').slice(0, 16) + '"';

function send(res, status, headers, body = '') {
  const buf = Buffer.from(body);
  const all = { 'X-Backend': BACKEND, ...headers };
  if (status !== 304) all['Content-Length'] = buf.length;   // a 304 has no body
  res.writeHead(status, all);
  res.end(status === 304 ? undefined : buf);
}
const etagMatches = h => !!h && h.split(',').map(t => t.trim().replace(/^W\//, '')).some(t => t === INFO_ETAG || t === '*');

function page() {
  const accent = BACKEND === 'A' ? '#2457c5' : '#a8641a';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>team1.test - backend ${BACKEND}</title><style>
body{margin:0;font:16px/1.5 -apple-system,Helvetica,sans-serif;background:#fbfbfc;color:#1b1f24}
main{max-width:640px;margin:0 auto;padding:48px 24px}.who{display:flex;gap:20px;align-items:center;border-left:6px solid ${accent};padding-left:20px}
.l{font-size:88px;font-weight:700;line-height:1;color:${accent}}h1{margin:0;font-size:22px}p{margin:4px 0 0;color:#5b6470}
button{font:inherit;padding:10px 16px;border-radius:6px;border:1px solid #d9dde3;background:#fff;margin:32px 8px 12px 0;cursor:pointer}
pre{background:#fff;border:1px solid #d9dde3;border-radius:6px;padding:16px;font:13px/1.5 Menlo,monospace;min-height:110px}</style></head>
<body><main><div class="who"><div class="l">${BACKEND}</div><div><h1>Served by backend ${BACKEND}</h1>
<p>${os.hostname()} on port ${PORT}, reached through the nginx edge.</p></div></div>
<button id="s">Call /api/status</button><button id="i">Call /api/info (cached 60 s)</button>
<pre id="o">Open DevTools &gt; Network, then press a button.</pre></main><script>
const o=document.getElementById('o');async function c(p){const t=performance.now();const r=await fetch(p);const b=await r.text();
o.textContent='GET '+p+' -> HTTP '+r.status+'\\nX-Backend: '+r.headers.get('X-Backend')+'\\nCache-Control: '+r.headers.get('Cache-Control')+
'\\nETag: '+r.headers.get('ETag')+'\\ntime: '+Math.round(performance.now()-t)+' ms\\n\\n'+b}
document.getElementById('s').onclick=()=>c('/api/status');document.getElementById('i').onclick=()=>c('/api/info');</script></body></html>`;
}

const server = http.createServer((req, res) => {
  const t0 = Date.now(), path = req.url.split('?')[0];
  res.on('finish', () => console.log(`${new Date().toISOString()}  from=${req.socket.remoteAddress}  client=${req.headers['x-forwarded-for'] || '-'}  ${req.method} ${req.url} -> ${res.statusCode}  ${Date.now() - t0}ms`));
  if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, { 'Content-Type': 'application/json', Allow: 'GET, HEAD' }, '{"error":"method not allowed"}\n');
  if (path === '/') return send(res, 200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache' }, page());
  if (path === '/api/status') return send(res, 200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    JSON.stringify({ backend: BACKEND, status: 'ok', host: os.hostname(), port: PORT, time: new Date().toISOString() }, null, 2) + '\n');
  if (path === '/api/info') {
    const h = { 'Cache-Control': 'public, max-age=60', ETag: INFO_ETAG };
    if (etagMatches(req.headers['if-none-match'])) return send(res, 304, h);
    return send(res, 200, { ...h, 'Content-Type': 'application/json' }, INFO_BODY);
  }
  return send(res, 404, { 'Content-Type': 'application/json' }, JSON.stringify({ error: 'not found', path }) + '\n');
});
server.on('error', e => { console.error(e.code === 'EADDRINUSE' ? `Port ${PORT} is already in use.` : e); process.exit(1); });
server.listen(PORT, HOST, () => {
  const ips = Object.values(os.networkInterfaces()).flat().filter(i => i && i.family === 'IPv4' && !i.internal).map(i => i.address);
  console.log(`Backend ${BACKEND} listening on http://${HOST}:${PORT}   ETag(/api/info)=${INFO_ETAG}`);
  console.log(`Reachable on the LAN at: ${ips.map(ip => `http://${ip}:${PORT}`).join('  ')}`);
});
