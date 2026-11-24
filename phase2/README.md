# Phase 2 — Harden & Recover

This folder holds everything for Phase 2: a click-to-run kit with one folder per Mac (`Mac1-DNS`, `Mac2-Edge`, `Mac3-BackendA`, `Mac4-BackendB`). Each numbered `.command` file does one step, checks it, and saves its output to `evidence/`. Start with [`README-START-HERE.txt`](README-START-HERE.txt).

| Extension | What it adds | Where it runs | Demo file |
| --- | --- | --- | --- |
| A — Backup DNS | Second dnsmasq with identical records; clients list both | Mac 3 | `13-ExtA-dns-failover-demo` (Mac 4) |
| B — TTL | `local-ttl=30`; record change observed in the OS cache | Mac 1 | `16-ExtB-ttl-demo` (Mac 4) |
| C — Service isolation | pf anchor: only Mac 2 may reach ports 3001/3002; rollback | Mac 3, Mac 4 | `19` / `20` / `21` |
| D — HA failover | `max_fails=1 fail_timeout=10s`, `proxy_next_upstream`, 2 s connect timeout | Mac 2 | `22-ExtD-failover-demo` (Mac 4) |
| E — Edge cutover | Standby nginx on Mac 3 (same cert); `app.team1.test` moved by DNS | Mac 3 | `24-ExtE-cutover-demo` (Mac 4) |
| F — Troubleshooting | Layer-by-layer diagnosis DNS → IP → TCP → TLS → HTTP | any Mac | `F-diagnose-layer-by-layer` |

**Updated roles:** Mac 1 primary DNS + client · Mac 2 primary edge · Mac 3 Backend A + backup DNS + standby edge · Mac 4 Backend B + main client.

**Phase 2 Final Report:** [`REPORT.pdf`](REPORT.pdf) · **Evidence:** `evidence/macN/`
