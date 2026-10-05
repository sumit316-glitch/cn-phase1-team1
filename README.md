# CN Phase 1 — Private Network Service Platform

**Computer Networks Course · Phase 1: Build & Observe**
**Team:** Team1 · **Section:** `C` · **Submission type:** Type 1 — 4 physical macOS laptops on the same LAN

A client resolves `app.team1.test` through our own DNS server, connects over HTTPS to an nginx edge that terminates TLS, and is load-balanced round-robin across two Node.js backends. Everything runs locally on four Macs; no cloud.

## Team members

| Enrollment no. | Name | Machine / role |
| --- | --- | --- |
| 2401010180 | Harsh Raj | Mac 1 — Private DNS server (dnsmasq) + test client |
| 2401010464 | Sumit Yadav | Mac 2 — Edge: nginx reverse proxy, load balancer, TLS |
| 2401010005 | Adil Mirza | Mac 3 — Backend A (Node.js, port 3001) |
| 2401010114 | Augustya Purohit | Mac 4 — Backend B (Node.js, port 3002) + test client |

## Topology

```
                    Private Wi-Fi LAN
 ┌──────────────────────────────────────────────────────────────┐
 │  Client (Mac 4 / Mac 1)  ──1. DNS, UDP 53──▶  Mac 1 10.7.3.72 │
 │        │                                     dnsmasq          │
 │        │ 2. HTTPS, TCP 443 (TLS)                               │
 │        ▼                                                       │
 │  Mac 2 10.7.27.22  nginx edge: TLS termination + round-robin   │
 │        │ 3. plain HTTP                                         │
 │        ├──────────▶ Mac 3 10.7.2.33:3001   Backend A           │
 │        └──────────▶ Mac 4 10.7.27.28:3002  Backend B           │
 └──────────────────────────────────────────────────────────────┘
```

| Machine | IPv4 | Services | Cloud equivalent |
| --- | --- | --- | --- |
| Mac 1 | 10.7.3.72 | dnsmasq :53 (UDP/TCP) | Route 53 private hosted zone |
| Mac 2 | 10.7.27.22 | nginx :80 (redirect), :443 (HTTPS, HTTP/2) | AWS ALB / CDN edge |
| Mac 3 | 10.7.2.33 | Backend A :3001 | Instance in a target group |
| Mac 4 | 10.7.27.28 | Backend B :3002 | Instance in a target group |

DNS records (served by Mac 1, TTL 60 s): `app.team1.test → 10.7.27.22`, `api.team1.test → 10.7.27.22`. Both names point to the edge; clients never learn backend IPs.

## How to run the backends

Requirements: Node.js 18+ (`brew install node`). No npm packages are needed.

```bash
# Mac 3 — Backend A
cd backend
BACKEND=A PORT=3001 node server.js

# Mac 4 — Backend B
cd backend
BACKEND=B PORT=3002 node server.js
```

Both listen on `0.0.0.0` (all interfaces) so the edge can reach them over the LAN. Check from Mac 2:

```bash
curl -i http://10.7.2.33:3001/api/status     # X-Backend: A
curl -i http://10.7.27.28:3002/api/status    # X-Backend: B
```

| Endpoint | Response | Key headers |
| --- | --- | --- |
| `GET /` | HTML page showing which backend served it | `X-Backend`, `Cache-Control: no-cache` |
| `GET /api/status` | `{"backend":"A","status":"ok",...}` | `X-Backend`, `Cache-Control: no-store` |
| `GET /api/info` | JSON identical on A and B | `X-Backend`, `Cache-Control: public, max-age=60`, `ETag`; returns `304` on matching `If-None-Match` |

## How to run the rest of the system

**Mac 1 — DNS**
```bash
cp config/mac1-dns/dnsmasq.conf /opt/homebrew/etc/dnsmasq.conf
dnsmasq --test --conf-file=/opt/homebrew/etc/dnsmasq.conf
sudo brew services start dnsmasq
networksetup -setdnsservers Wi-Fi 127.0.0.1
```

**Mac 2 — TLS certificates and edge**
```bash
bash config/mac2-edge/make-certs.sh                  # local root CA + server cert (SAN app/api.team1.test)
mkdir -p /opt/homebrew/etc/nginx/certs
cp ~/team1-certs/app.team1.test.crt ~/team1-certs/app.team1.test.key /opt/homebrew/etc/nginx/certs/
cp config/mac2-edge/team1.conf /opt/homebrew/etc/nginx/servers/team1.conf
sudo nginx -t && sudo nginx
```

**Client Macs (Mac 2, 3, 4 use Mac 1 for DNS; Mac 1 and Mac 4 trust the CA)**
```bash
networksetup -setdnsservers Wi-Fi 10.7.3.72
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain certs/ca.crt
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

**Verify (by domain name, certificate validation on, no `-k`)**
```bash
dig app.team1.test
curl -i https://app.team1.test/api/status
bash scripts/lb-test.sh 6          # X-Backend alternates A, B, A, B ...
bash scripts/cache-test.sh         # 200 -> 304 (both backends) -> 200
```

## Repository layout

| Path | Contents |
| --- | --- |
| `backend/server.js` | Backend source (same file on Mac 3 and Mac 4) |
| `config/mac1-dns/dnsmasq.conf` | DNS configuration as running on Mac 1 |
| `config/mac2-edge/team1.conf` | nginx configuration as running on Mac 2 |
| `config/mac2-edge/make-certs.sh` | Creates the local CA and server certificate (TLS setup notes are in the script) |
| `certs/ca.crt` | Public root CA certificate clients trust. Private keys are never committed. |
| `scripts/` | `mac-info.sh`, `ping-all.sh`, `lb-test.sh`, `cache-test.sh`, `http-versions.sh`, `collect-evidence.sh` |
| `docs/` | Architecture document, topology and request-flow diagrams |
| `evidence/` | Screenshots, Wireshark captures (`.pcapng`) and raw terminal outputs, by task |

## Evidence index

| Task | Folder | Contents |
| --- | --- | --- |
| A — LAN | `evidence/A_lan/` | IP/mask/gateway/MAC per Mac, ping matrix, ARP table |
| B — DNS | `evidence/B_dns/` | dig / nslookup from clients, dnsmasq config and query log |
| C, D — Backends + LB | `evidence/CD_backends_lb/` | Direct backend checks from Mac 2, A/B alternation, nginx access log, X-Forwarded-For logs |
| E — TLS | `evidence/E_tls/` | Certificate creation, Keychain trust, browser padlock, `curl -v` |
| F — Caching | `evidence/F_cache/` | `Cache-Control`/`ETag`, 304 from both backends, browser memory-cache hit |
| G — Packet capture | `evidence/G_capture/` | G1 TLS 1.3 full flow, G2 TLS 1.2 certificate, G3 plaintext edge→backend hop |
| Failure demos | `evidence/failures/` | Wrong DNS server, wrong record, one backend down, 502, wrong port |
| Raw outputs | `evidence/outputs/` | Unedited terminal output from `collect-evidence.sh` |

## Security notes

- The CA private key (`ca.key`) and server key never leave Mac 2 and are excluded by `.gitignore`.
- Certificate validation is never bypassed (no `curl -k`); clients trust our local root CA through the System keychain.
- `.test` is used (reserved, RFC 6761) instead of `.local`, which macOS reserves for mDNS.
