#!/bin/bash
# Every numbered step. Each .command file calls exactly one of these.
source "$KIT/lib/dns.sh"
source "$KIT/lib/edge.sh"

hdr() { curl -s -D - -o /dev/null --connect-timeout 4 "$@"; }
hval() { awk -F': ' -v k="$1" 'tolower($1)==k{print $2}' | tr -d '\r'; }

# ======================================================================
# PART 1 — rebuild the Phase 1 base
# ======================================================================

s00_netinfo() {
  title "00 · This Mac's network facts (Task A)"
  start_log 00-network-info
  echo "Computer name : $(scutil --get ComputerName 2>/dev/null)"
  echo "Interface     : $IFACE"
  echo "IPv4 address  : ${MYIP:-NOT CONNECTED}"
  local mask; mask="$(ipconfig getoption "$IFACE" subnet_mask 2>/dev/null)"
  echo "Subnet mask   : $mask"
  echo "Gateway       : $(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')"
  echo "MAC address   : $(ifconfig "$IFACE" | awk '/ether/{print $2}')"
  echo "DNS servers   : $(scutil --dns | awk '/nameserver\[[0-9]+\]/{print $3}' | awk '!s[$0]++' | head -3 | tr '\n' ' ')"
  echo
  if [ "$THIS_MAC" = "0" ]; then
    warn "This IP ($MYIP) is not in team.env yet."
    info "Write it into team.env on ALL four Macs (open team.env in TextEdit), then continue."
  else ok "team.env recognises this Mac as Mac $THIS_MAC"; fi
  local fw; fw="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)"
  echo "$fw" | grep -qi "disabled" && ok "macOS Firewall is off" || warn "macOS Firewall is ON — step 02 turns it off"
  finish
}

s02_install() {
  title "02 · Install what this Mac needs"
  start_log 02-install
  need_brew
  local pk=""
  case "$THIS_MAC" in
    1) pk="dnsmasq" ;;
    2) pk="nginx openssl@3" ;;
    3) pk="node dnsmasq nginx" ;;     # backend A + backup DNS + standby edge
    4) pk="node" ;;
    *) warn "Unknown Mac — fix team.env first (step 00)"; finish; return ;;
  esac
  for p in $pk; do
    if brew list --formula "$p" >/dev/null 2>&1; then ok "$p already installed"
    else say "Installing $p ..."; brew install "$p" && ok "$p installed" || bad "brew install $p failed"; fi
  done
  case "$THIS_MAC" in 2|3) nginx -v 2>&1 | sed 's/^/   /' ;; esac
  case "$THIS_MAC" in 3|4) echo "   node $(node -v 2>/dev/null)" ;; esac
  if [ "$THIS_MAC" = "1" ] || [ "$THIS_MAC" = "4" ]; then
    [ -d /Applications/Wireshark.app ] && ok "Wireshark installed" \
      || warn "Wireshark missing: download from wireshark.org, and also run 'Install ChmodBPF.pkg' from its disk image"
  fi
  if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -qi enabled; then
    say "Turning the macOS app Firewall off (it hides ping and turns 'refused' into timeouts)"
    get_sudo; sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off >/dev/null && ok "Firewall off"
  else ok "macOS Firewall already off"; fi
  finish
}

s03_ping() {
  title "03 · Ping every other Mac (Task A)"
  start_log 03-ping
  local m ip out loss avg
  for m in 1 2 3 4; do
    [ "$m" = "$THIS_MAC" ] && continue
    ip="$(mac_ip $m)"
    out="$(ping -c 4 -t 6 "$ip" 2>&1)"
    loss="$(echo "$out" | grep -o '[0-9.]*% packet loss')"
    avg="$(echo "$out" | awk -F'/' '/round-trip/{print $5}')"
    if echo "$loss" | grep -q '^0.0%'; then ok "Mac$THIS_MAC -> Mac$m  ping $ip — 4 packets, $loss, avg ${avg} ms"
    else bad "Mac$THIS_MAC -> Mac$m  ping $ip — ${loss:-no reply}"; fi
  done
  echo; show "arp -an | grep -E '$(echo "$MAC1_IP|$MAC2_IP|$MAC3_IP|$MAC4_IP" | sed 's/\./\\./g')'"
  finish
}

s04_primary_dns() {
  title "04 · Start the PRIMARY DNS server (Mac 1)"
  need_mac 1; start_log 04-primary-dns; need_brew; get_sudo
  part "Writing dnsmasq.conf"; dns_write_conf "primary DNS on Mac 1"
  part "Starting dnsmasq"; dns_restart
  part "Mac 1 uses its own DNS"
  set_resolvers "$(cat "$STATE/resolver-mode" 2>/dev/null || echo phase1)"
  show "dig $APP +noall +answer +stats | grep -E '$APP|SERVER'"
  finish
}

s05_backendA() { s_backend A $PORT_A 3; }
s06_backendB() { s_backend B $PORT_B 4; }
s_backend() {
  local id="$1" port="$2" mac="$3"
  title "0$((mac+2)) · Backend $id on port $port (Mac $mac) — KEEP THIS WINDOW OPEN"
  need_mac "$mac"
  command -v node >/dev/null || { bad "Node is not installed — run step 02"; finish; return; }
  local old; old="$(lsof -ti tcp:"$port" -sTCP:LISTEN 2>/dev/null)"
  [ -n "$old" ] && { warn "Stopping an older copy on port $port (PID $old)"; kill $old; sleep 1; }
  say "To STOP this backend later (Ext D demo): click this window and press Ctrl+C."
  say "To START it again: double-click this same file."
  echo
  LOGFILE="$EVID/0$((mac+2))-backend-$id-mac$mac.txt"
  BACKEND=$id PORT=$port node "$KIT/backend/server.js" 2>&1 | tee -a "$LOGFILE"
  echo; warn "Backend $id has stopped."; read -r -p "Press Enter to close this window..." _
}

s07_edge() {
  title "07 · Start the PRIMARY EDGE: certificates + nginx (Mac 2)"
  need_mac 2; start_log 07-edge; need_brew; get_sudo
  part "TLS certificates"; make_certs || { finish; return; }
  openssl x509 -in "$CERTDIR/${APP}.crt" -noout -subject -issuer -enddate | sed 's/^/   /'
  part "nginx configuration"; edge_write_conf "mac2-primary" "$CERTDIR"
  part "Start nginx"; edge_start || { finish; return; }
  part "Self-test through the edge (TLS verified with our CA)"; edge_selftest "$CERTDIR/ca.crt" "Mac 2"
  part "Files to AirDrop"
  local d1="$HOME/Desktop/CN-share-for-all-Macs" d2="$HOME/Desktop/CN-share-for-Mac3-only"
  mkdir -p "$d1" "$d2"
  cp "$CERTDIR/ca.crt" "$d1/"
  cp "$CERTDIR/ca.crt" "$CERTDIR/${APP}.crt" "$CERTDIR/${APP}.key" "$d2/"
  mkdir -p "$KIT/certs"; cp "$CERTDIR/ca.crt" "$KIT/certs/"
  ok "Desktop/CN-share-for-all-Macs   -> AirDrop to Mac 1, Mac 3, Mac 4 (public CA only)"
  ok "Desktop/CN-share-for-Mac3-only  -> AirDrop to Mac 3 ONLY (server key for the standby edge)"
  warn "ca.key never leaves this Mac."
  finish
}

s08_resolvers_p1() {
  title "08 · Use the team DNS server (Mac 1)"
  start_log 08-use-team-dns; get_sudo
  set_resolvers phase1
  local got; got="$(dig "$APP" +short | tail -1)"
  [ "$got" = "$MAC2_IP" ] && ok "$APP -> $got (Mac 2, the edge)" || bad "$APP -> '${got:-nothing}', expected $MAC2_IP. Is step 04 done on Mac 1?"
  show "dig $APP | grep -E 'status|$APP\.|SERVER'"
  finish
}

s09_trust() {
  title "09 · Trust the team's root CA (so HTTPS shows no warning, no -k ever)"
  start_log 09-trust-ca; get_sudo
  local ca="" c
  for c in "$KIT/certs/ca.crt" "$HOME/Downloads/CN-share-for-all-Macs/ca.crt" "$HOME/Downloads/CN-share-for-Mac3-only/ca.crt" \
           "$HOME/Downloads/ca.crt" "$HOME/Desktop/CN-share-for-all-Macs/ca.crt" "$HOME/${TEAM}-certs/ca.crt"; do
    [ -f "$c" ] && { ca="$c"; break; }; done
  # prefer the newest copy from Downloads/Desktop over an old kit copy
  for c in "$HOME/Downloads/CN-share-for-all-Macs/ca.crt" "$HOME/Desktop/CN-share-for-all-Macs/ca.crt" "$HOME/${TEAM}-certs/ca.crt"; do
    [ -f "$c" ] && { ca="$c"; break; }; done
  [ -z "$ca" ] && { bad "ca.crt not found. AirDrop 'CN-share-for-all-Macs' from Mac 2's Desktop first."; finish; return; }
  info "Using $ca"
  mkdir -p "$KIT/certs"; [ "$ca" != "$KIT/certs/ca.crt" ] && cp "$ca" "$KIT/certs/ca.crt"
  while sudo security delete-certificate -c "$CA_NAME" /Library/Keychains/System.keychain >/dev/null 2>&1; do :; done
  while sudo security delete-certificate -c "Team1 Local Root CA" /Library/Keychains/System.keychain >/dev/null 2>&1; do :; done
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$KIT/certs/ca.crt" \
    && ok "Trusted in the System keychain (Safari/Chrome)" || bad "Keychain import failed"
  cat /etc/ssl/cert.pem "$KIT/certs/ca.crt" > "$HOME/.cn-ca-bundle.pem"
  grep -q "cn-ca-bundle" "$HOME/.zshrc" 2>/dev/null || echo 'export CURL_CA_BUNDLE=$HOME/.cn-ca-bundle.pem' >> "$HOME/.zshrc"
  export CURL_CA_BUNDLE="$HOME/.cn-ca-bundle.pem"
  ok "curl trusts it too (CURL_CA_BUNDLE in ~/.zshrc)"
  local code; code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$URL/api/status")"
  [ "$code" = "200" ] && ok "curl $URL/api/status -> 200 with certificate validation ON" \
    || warn "curl got '$code' — fine if the DNS/edge steps aren't done yet on this Mac"
  info "Restart Safari/Chrome once so they pick up the new CA."
  finish
}

lb_round() {  # lb_round <n> : prints each request, sets CNT_A CNT_B CNT_OK
  local n="$1" i h code be up t
  CNT_A=0; CNT_B=0; CNT_OK=0
  for i in $(seq 1 "$n"); do
    h="$(curl -s -D - -o /dev/null -w 'TIME=%{time_total}' --connect-timeout 5 "$URL/api/status")"
    code="$(echo "$h" | head -1 | awk '{print $2}')"
    be="$(echo "$h" | hval x-backend)"; up="$(echo "$h" | hval x-upstream)"; t="$(echo "$h" | sed -n 's/.*TIME=//p')"
    printf '   request %d -> HTTP %s   X-Backend: %-2s via %-22s %ss\n' "$i" "${code:-ERR}" "${be:--}" "${up:--}" "$t"
    [ "$code" = "200" ] && CNT_OK=$((CNT_OK+1))
    [ "$be" = "A" ] && CNT_A=$((CNT_A+1)); [ "$be" = "B" ] && CNT_B=$((CNT_B+1))
  done
}

s10_gate() {
  title "10 · Phase 1 gate check (run on Mac 4, then Mac 1)"
  need_mac "1 4"; start_log 10-phase1-gate; get_sudo; flush_dns
  part "DNS (Task B)"; show "dig $APP"
  part "HTTPS + certificate (Task E) — no -k"; show "curl -v $URL/api/status"
  part "Load balancing (Task D)"; lb_round 6
  [ "$CNT_A" -gt 0 ] && [ "$CNT_B" -gt 0 ] && ok "Both backends answered (A=$CNT_A, B=$CNT_B)" || bad "Not both backends (A=$CNT_A, B=$CNT_B)"
  part "Caching (Task F)"; show "curl -sI $URL/api/info"
  local etag c1 c2; etag="$(hdr "$URL/api/info" | hval etag)"
  c1="$(curl -s -o /dev/null -w '%{http_code}' -H "If-None-Match: $etag" "$URL/api/info")"
  c2="$(curl -s -o /dev/null -w '%{http_code}' -H "If-None-Match: $etag" "$URL/api/info")"
  info "Conditional requests with If-None-Match: $etag -> $c1, $c2"
  [ "$c1" = "304" ] && [ "$c2" = "304" ] && ok "304 Not Modified from both backends" || bad "Expected 304, 304"
  part "HTTP -> HTTPS redirect"; show "curl -sI http://$APP/ | head -3"
  part "HTTP versions"
  show "curl -s -o /dev/null -w 'protocol=%{http_version} status=%{http_code}\n' --http1.1 $URL/api/status"
  show "curl -s -o /dev/null -w 'protocol=%{http_version} status=%{http_code}\n' --http2 $URL/api/status"
  say "Now open $URL in Safari: padlock, no warning, big A or B; reload to switch."
  finish
}

# ======================================================================
# PART 2 — Phase 2 extensions
# ======================================================================

s11_backup_dns() {
  title "11 · Ext A — start the BACKUP DNS server (Mac 3)"
  need_mac 3; start_log 11-ExtA-backup-dns; need_brew; get_sudo
  part "Same records as the primary"; dns_write_conf "BACKUP DNS on Mac 3"
  part "Starting dnsmasq"; dns_restart
  show "dig @$MYIP TXT dns-server.$DOMAIN +short"
  finish
}

s12_resolvers_p2() {
  title "12 · Ext A — list BOTH DNS servers (primary Mac 1, backup Mac 3)"
  start_log 12-ExtA-two-dns-servers; get_sudo
  set_resolvers phase2
  show "dig $APP +noall +answer +stats | grep -E '$APP|SERVER'"
  finish
}

s13_extA_demo() {
  title "13 · Ext A — GUIDED DNS failover demo (Mac 4)"
  need_mac "4 2"; start_log 13-ExtA-demo; get_sudo
  part "BEFORE — primary answers"
  flush_dns
  show "dig $APP | grep -E 'status:|^$APP|SERVER'"
  show "dig TXT dns-server.$DOMAIN +short"
  wait_enter "On MAC 1 double-click 14-ExtA-stop-primary-dns.command"
  part "DURING — primary DNS is down"
  show "dig @$MAC1_IP $APP +time=2 +tries=1 | grep -E 'status|connection|timed out|SERVER' ; true"
  flush_dns
  show "dig $APP | grep -E 'status:|^$APP|SERVER|communications'"
  show "dig TXT dns-server.$DOMAIN +short"
  local code; code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$URL/api/status")"
  [ "$code" = "200" ] && ok "Service still works by name (HTTP $code) — the backup DNS answered" || bad "curl got $code"
  info "DNS service failure = names stop resolving (nothing connects, even though servers are healthy)."
  info "Application failure = names resolve fine, but the service behind them errors (e.g. 502)."
  wait_enter "On MAC 1 double-click 15-ExtA-restart-primary-dns.command"
  part "AFTER — primary is back"
  flush_dns
  show "dig $APP | grep -E 'status:|^$APP|SERVER'"
  finish
}

s14_stop_primary() {
  title "14 · Ext A — STOP the primary DNS (Mac 1)"
  need_mac 1; start_log 14-ExtA-stop-primary; get_sudo
  sudo brew services stop dnsmasq >/dev/null 2>&1; sudo pkill -x dnsmasq 2>/dev/null; sleep 1
  if sudo lsof -nP -i :53 | grep -q dnsmasq; then bad "dnsmasq still running"; else ok "Primary DNS stopped — port 53 on Mac 1 is closed"; fi
  show "dig @127.0.0.1 $APP +time=2 +tries=1 | grep -E 'connection|timed out|status' ; true"
  finish
}

s15_restart_primary() { s04_primary_dns; }

s16_extB_demo() {
  title "16 · Ext B — GUIDED TTL demo (Mac 4)"
  need_mac "4 2"; start_log 16-ExtB-ttl-demo; get_sudo
  part "1. Cache the current answer"
  flush_dns
  show "dig $API +noall +answer"
  info "macOS (the OS cache) now resolves $API to: $(os_lookup "$API")   — cached for ${DNS_TTL}s"
  local t0; t0="$(date +%s)"
  wait_enter "QUICKLY (within ~15 s): on MAC 1 double-click 17-ExtB-move-api-record.command"
  part "2. Watch the cached answer survive until the TTL runs out"
  printf '   %-8s %-26s %-26s\n' "elapsed" "this Mac (OS cache)" "DNS server (dig @Mac1)"
  local i os srv flipped=""
  for i in $(seq 1 16); do
    os="$(os_lookup "$API")"; srv="$(dig @"$MAC1_IP" "$API" +short +time=2 +tries=1 | tail -1)"
    printf '   %-8s %-26s %-26s\n' "$(( $(date +%s) - t0 ))s" "$os" "$srv"
    [ "$os" = "$srv" ] && [ "$srv" = "$MAC3_IP" ] && { flipped=1; break; }
    sleep 3
  done
  [ -n "$flipped" ] && ok "The OS switched only after its cached copy expired (TTL ${DNS_TTL}s)" \
    || warn "No switch seen — if it switched on the first line, you were slower than the TTL; run 18 on Mac 1 and try again"
  part "3. Manual flush = immediate change"
  wait_enter "On MAC 1 double-click 18-ExtB-restore-api-record.command"
  info "Right after the restore:  OS cache = $(os_lookup "$API")   server = $(dig @"$MAC1_IP" "$API" +short | tail -1)"
  say "Flushing this Mac's DNS cache now..."; flush_dns
  info "After the flush:          OS cache = $(os_lookup "$API")   (changed immediately)"
  info "Production meaning: lower the TTL before a migration, change the record, and clients move within one TTL."
  finish
}

s_set_record() {  # s_set_record <app|api> <ip> <label>
  get_sudo; rec_load
  [ "$1" = "app" ] && APP_TARGET="$2" || API_TARGET="$2"
  rec_save
  local who="primary DNS on Mac 1"; [ "$THIS_MAC" = "3" ] && who="BACKUP DNS on Mac 3"
  dns_write_conf "$who"; dns_restart
  show "dig @127.0.0.1 $1.$DOMAIN +noall +answer"
  ok "$3"
}
s17_move_api()    { title "17 · Ext B — point $API to Mac 3"; need_mac 1; start_log 17-ExtB-move-api; s_set_record api "$MAC3_IP" "$API now -> $MAC3_IP"; finish; }
s18_restore_api() { title "18 · Ext B — point $API back to Mac 2"; need_mac 1; start_log 18-ExtB-restore-api; s_set_record api "$MAC2_IP" "$API restored -> $MAC2_IP"; finish; }

PF_ANCHOR="com.apple/cnproject"
s19_fw_on() {
  title "19 · Ext C — firewall ON: only Mac 2 may reach this backend"
  need_mac "3 4"; start_log 19-ExtC-firewall-on; get_sudo
  local port=$PORT_A; [ "$THIS_MAC" = "4" ] && port=$PORT_B
  mkdir -p "$KIT/firewall"
  cp /etc/pf.conf "$KIT/firewall/pf.conf.rollback-copy"
  sudo pfctl -sr 2>/dev/null > "$KIT/firewall/pf-rules-before.txt"
  cat > "$KIT/firewall/backend-mac$THIS_MAC.pf" <<EOF
# Ext C — service isolation on Mac $THIS_MAC (backend port $port)
pass in quick on lo0 all
pass in quick proto tcp from $MAC2_IP to any port $port
block drop in quick proto tcp from any to any port $port
EOF
  ok "Rollback copy saved: firewall/pf.conf.rollback-copy (we never edit /etc/pf.conf)"
  sudo pfctl -a "$PF_ANCHOR" -f "$KIT/firewall/backend-mac$THIS_MAC.pf" 2>/dev/null && ok "Rules loaded into pf anchor $PF_ANCHOR"
  sudo pfctl -E 2>&1 | awk '/Token/{print $3}' > "$STATE/pf-token"
  part "Active rules"; show "sudo pfctl -a $PF_ANCHOR -s rules"
  show "sudo pfctl -s info | head -1"
  local code; code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/api/status")"
  [ "$code" = "200" ] && ok "Backend still answers locally ($code)" || warn "Backend not answering locally — is its window still running?"
  say "Now run 20-ExtC-test-backend-access on Mac 1 (blocked) and Mac 2 (allowed)."
  finish
}

s20_fw_test() {
  title "20 · Ext C — who can reach the backend ports?"
  start_log 20-ExtC-test; local t ip port rc code
  for t in "$MAC3_IP:$PORT_A" "$MAC4_IP:$PORT_B"; do
    ip="${t%:*}"; port="${t#*:}"
    if [ "$ip" = "$MYIP" ]; then info "Skipping $t (that's this Mac's own port)"; continue; fi
    code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 4 "http://$t/api/status")"; rc=$?
    if [ "$THIS_MAC" = "2" ]; then
      [ "$code" = "200" ] && ok "Mac 2 (edge) -> $t : HTTP 200 — allowed" || bad "Mac 2 (edge) -> $t : blocked (rc=$rc) — edge must be allowed!"
    else
      if [ "$rc" = "28" ] || [ "$code" = "000" ]; then ok "Mac $THIS_MAC -> $t : no answer in 4 s (SYN dropped by pf) — blocked"
      else bad "Mac $THIS_MAC -> $t : HTTP $code — NOT blocked (is step 19 done on that Mac?)"; fi
    fi
  done
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$URL/api/status")"
  [ "$code" = "200" ] && ok "Through the edge: $URL -> 200 (the service still works)" || warn "Through the edge: $code"
  finish
}

s21_fw_off() {
  title "21 · Ext C — firewall OFF (rollback)"
  need_mac "3 4"; start_log 21-ExtC-rollback; get_sudo
  sudo pfctl -a "$PF_ANCHOR" -F all 2>/dev/null && ok "Our rules removed from $PF_ANCHOR"
  local tok; tok="$(cat "$STATE/pf-token" 2>/dev/null)"
  [ -n "$tok" ] && sudo pfctl -X "$tok" >/dev/null 2>&1 && ok "Released our pf enable token"
  show "sudo pfctl -a $PF_ANCHOR -s rules ; echo '(empty = no project rules)'"
  if [ -f "$KIT/firewall/pf.conf.rollback-copy" ] && diff -q /etc/pf.conf "$KIT/firewall/pf.conf.rollback-copy" >/dev/null; then
    ok "/etc/pf.conf identical to the rollback copy — original configuration restored"; fi
  finish
}

s22_extD_demo() {
  title "22 · Ext D — GUIDED high-availability failover demo (Mac 4)"
  need_mac "4 1 2"; start_log 22-ExtD-demo
  part "BEFORE — both backends"; lb_round 6
  say "Tip: on Mac 2 open L-watch-edge-logs.command to show nginx's view."
  wait_enter "On MAC 3 click the Backend A window and press Ctrl+C (Backend A dies)"
  part "DURING — Backend A is down"; lb_round 6
  [ "$CNT_OK" = "6" ] && [ "$CNT_A" = "0" ] && ok "All 6 requests succeeded, all served by B — failure masked" \
    || bad "Expected 6x HTTP 200 from B (got OK=$CNT_OK, A=$CNT_A, B=$CNT_B)"
  wait_enter "On MAC 3 double-click 05-start-backend-A.command again"
  local s; for s in 12 9 6 3; do info "waiting for nginx to re-test A ... ${s}s"; sleep 3; done
  part "AFTER — Backend A is back"; lb_round 6
  [ "$CNT_A" -gt 0 ] && [ "$CNT_B" -gt 0 ] && ok "Load balancing resumed across A and B" || warn "A not back yet — wait 10 s and run again"
  info "Single point of failure that remains: the edge (nginx on Mac 2). Ext E shows the fix: a standby edge + DNS cutover."
  finish
}

s23_standby_edge() {
  title "23 · Ext E — start the STANDBY EDGE (Mac 3)"
  need_mac 3; start_log 23-ExtE-standby-edge; need_brew; get_sudo
  local src="$HOME/Downloads/CN-share-for-Mac3-only"
  [ -f "$src/${APP}.key" ] || { bad "Missing $src — AirDrop 'CN-share-for-Mac3-only' from Mac 2's Desktop first"; finish; return; }
  part "Same certificate + same config as the primary"; edge_write_conf "mac3-standby" "$src"
  part "Start nginx"; edge_start || { finish; return; }
  part "Self-test"; edge_selftest "$src/ca.crt" "Mac 3 (standby)"
  finish
}

s24_extE_demo() {
  title "24 · Ext E — GUIDED DNS-based edge cutover (Mac 4)"
  need_mac "4 2"; start_log 24-ExtE-demo; get_sudo
  part "1. This client resolves the name now (and caches it for ${DNS_TTL}s)"
  flush_dns
  info "OS answer: $APP -> $(os_lookup "$APP")"
  info "X-Edge:    $(hdr "$URL/api/status" | hval x-edge)"
  local t0; t0="$(date +%s)"
  wait_enter "QUICKLY: on MAC 1 double-click 25-ExtE-cutover-to-standby.command"
  say "While this runs: on MAC 1 double-click 26-ExtE-fresh-client-check (a NEW lookup goes straight to standby)."
  part "2. Cached client keeps the old edge until the TTL expires"
  printf '   %-8s %-18s %-16s %-18s\n' "elapsed" "OS answer" "X-Edge" "server (dig @Mac1)"
  local i os edge srv done=""
  for i in $(seq 1 16); do
    os="$(os_lookup "$APP")"; edge="$(hdr "$URL/api/status" | hval x-edge)"; srv="$(dig @"$MAC1_IP" "$APP" +short +time=2 +tries=1 | tail -1)"
    printf '   %-8s %-18s %-16s %-18s\n' "$(( $(date +%s) - t0 ))s" "$os" "${edge:-error}" "$srv"
    [ "$edge" = "mac3-standby" ] && { done=1; break; }
    sleep 3
  done
  [ -n "$done" ] && ok "Cutover complete: this client now uses the standby edge (no client config changed)" \
    || warn "Not switched yet — wait a few seconds and check: curl -sI $URL/api/status | grep x-edge"
  say "Afterwards: run 25 on MAC 3 too (keep the backup DNS consistent), and 27 on Mac 1 + Mac 3 to roll back."
  finish
}

s25_cutover() { title "25 · Ext E — point $APP to the STANDBY edge (Mac 3)"; need_mac "1 3"; start_log 25-ExtE-cutover; s_set_record app "$MAC3_IP" "$APP now -> $MAC3_IP (standby edge)"; finish; }
s27_rollback() { title "27 · Ext E — point $APP back to the PRIMARY edge"; need_mac "1 3"; start_log 27-ExtE-rollback; s_set_record app "$MAC2_IP" "$APP restored -> $MAC2_IP (primary edge)"; finish; }

s26_fresh_client() {
  title "26 · Ext E — a fresh client after the cutover (Mac 1)"
  need_mac "1"; start_log 26-ExtE-fresh-client; get_sudo; flush_dns
  show "dig $APP +short"
  local e; e="$(hdr "$URL/api/status" | hval x-edge)"
  [ "$e" = "mac3-standby" ] && ok "New lookup -> standby edge (X-Edge: $e), certificate still valid" || warn "X-Edge: ${e:-none}"
  finish
}

# ======================================================================
# Ext F — layer-by-layer diagnosis (any Mac)
# ======================================================================
s_diagnose() {
  title "F · Layer-by-layer diagnosis — say each result out loud"
  start_log F-diagnose; get_sudo
  local first="" ip rc code nc_out

  part "Layer 1 · DNS — does the name resolve, and to the edge?"
  show "scutil --dns | grep 'nameserver\[' | head -3"
  grep -i "$DOMAIN" /etc/hosts >/dev/null && { warn "/etc/hosts overrides $DOMAIN on this Mac:"; grep -i "$DOMAIN" /etc/hosts; }
  ip="$(dig "$APP" +short +time=2 +tries=1 | tail -1)"
  for s in "$MAC1_IP" "$MAC3_IP"; do info "dig @$s $APP -> $(dig @"$s" "$APP" +short +time=2 +tries=1 2>&1 | tail -1)"; done
  if [ -z "$ip" ]; then bad "DNS: $APP does not resolve"; first="${first:-DNS}"
  elif [ "$ip" != "$MAC2_IP" ] && [ "$ip" != "$MAC3_IP" ]; then bad "DNS: $APP -> $ip, which is not an edge ($MAC2_IP / $MAC3_IP)"; first="${first:-DNS (wrong record)}"
  else ok "DNS: $APP -> $ip"; fi
  [ -z "$ip" ] && ip="$MAC2_IP"

  part "Layer 2/3 · IP — is the host reachable?"
  ping -c 2 -t 4 "$ip" >/dev/null 2>&1 && ok "ping $ip answers" || { bad "ping $ip fails"; first="${first:-IP / network}"; }

  part "Layer 4 · TCP — is anything listening on 443?"
  nc_out="$(nc -vz -G 3 "$ip" 443 2>&1)"; info "$nc_out"
  if echo "$nc_out" | grep -q succeeded; then ok "TCP 443 open"
  elif echo "$nc_out" | grep -qi refused; then bad "TCP 443 refused — host up, nothing listening (nginx down / wrong port)"; first="${first:-TCP (port 443)}"
  else bad "TCP 443 timed out — packets dropped (firewall?)"; first="${first:-TCP (blocked)}"; fi

  part "Layer 5/6 · TLS — handshake and certificate"
  echo | openssl s_client -connect "$ip:443" -servername "$APP" 2>/dev/null | grep -E "^subject=|^issuer=" | sed 's/^/   /'
  curl -s -o /dev/null --connect-timeout 5 --resolve "$APP:443:$ip" "$URL/"; rc=$?
  case "$rc" in
    0) ok "TLS OK — certificate valid for $APP and trusted" ;;
    35) bad "TLS handshake failed (curl 35)"; first="${first:-TLS handshake}" ;;
    51|60) bad "Certificate not trusted / wrong name (curl $rc) — run step 09, check the cert SAN"; first="${first:-TLS certificate}" ;;
    7|28) info "(skipped — TCP already failed)" ;;
    *) bad "curl exit $rc"; first="${first:-TLS}" ;;
  esac

  part "Layer 7 · HTTP — what does the application return?"
  lb_round 4
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --resolve "$APP:443:$ip" "$URL/api/status")"
  case "$code" in
    200) ok "HTTP 200 (A=$CNT_A, B=$CNT_B)" ;;
    502|504) bad "HTTP $code from the edge — the edge is fine, the backends behind it are not reachable"; first="${first:-Application (backends)}" ;;
    000) : ;;
    *) bad "HTTP $code"; first="${first:-Application}" ;;
  esac

  case "$THIS_MAC" in
    1|3) part "This Mac's DNS server"
         sudo lsof -nP -i :53 | grep -q dnsmasq && ok "dnsmasq listening on 53" || warn "dnsmasq not running here"
         show "grep -E '^(address|listen|interface|local)' $PREFIX/etc/dnsmasq.conf" ;;
  esac
  if pgrep -x nginx >/dev/null && [ -f "$NGXCONF" ]; then
    part "This Mac's nginx edge"
    sudo "$NGX" -t 2>&1 | grep -q successful && ok "nginx -t OK" || { bad "nginx -t FAILS"; sudo "$NGX" -t; }
    for t in "$MAC3_IP:$PORT_A" "$MAC4_IP:$PORT_B"; do
      code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "http://$t/api/status")"
      [ "$code" = "200" ] && ok "edge -> backend $t : 200" || bad "edge -> backend $t : ${code} (backend down, wrong IP/port, or firewall)"
    done
    show "tail -4 $PREFIX/var/log/nginx/${TEAM}_error.log"
  fi
  case "$THIS_MAC" in
    3|4) local p=$PORT_A; [ "$THIS_MAC" = "4" ] && p=$PORT_B
         part "This Mac's backend"
         lsof -nP -iTCP:"$p" -sTCP:LISTEN | grep -q '\*:'"$p" && ok "backend listening on *:$p (all interfaces)" \
           || { lsof -nP -iTCP:"$p" -sTCP:LISTEN | grep -q "127.0.0.1:$p" && bad "backend bound to 127.0.0.1 only!" || bad "nothing listening on $p"; } ;;
  esac

  echo
  if [ -z "$first" ]; then ok "${B}All layers pass.${N}"
  else echo "${R}${B}First failing layer: $first  ← fix this one first; layers above it can't work until it does.${N}"; fi
  finish
}

s_watch_edge() { title "Live nginx logs (Ctrl+C to stop)"; tail -n 5 -f "$PREFIX/var/log/nginx/${TEAM}_access.log" "$PREFIX/var/log/nginx/${TEAM}_error.log"; }
s_watch_dns()  { title "Live DNS query log (Ctrl+C to stop)"; tail -n 5 -f "$PREFIX/var/log/dnsmasq.log"; }

s98_pack() {
  title "98 · Pack this Mac's evidence + configs"
  local cfg="$EVID/configs-mac$THIS_MAC"; mkdir -p "$cfg"
  [ -f "$PREFIX/etc/dnsmasq.conf" ] && cp "$PREFIX/etc/dnsmasq.conf" "$cfg/"
  [ -f "$NGXCONF" ] && cp "$NGXCONF" "$cfg/nginx-${TEAM}.conf"
  [ -d "$KIT/firewall" ] && cp "$KIT"/firewall/* "$cfg/" 2>/dev/null
  [ -f "$KIT/certs/ca.crt" ] && cp "$KIT/certs/ca.crt" "$cfg/"
  local z="$HOME/Desktop/CN-evidence-mac$THIS_MAC.zip"
  (cd "$KIT" && zip -qr "$z" evidence) && ok "Saved $z — AirDrop it to the Mac that builds the GitHub repo"
  finish
}
