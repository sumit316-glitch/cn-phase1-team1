#!/usr/bin/env bash
# ============================================================
# Saves REAL terminal output (the command line + its output) into
# evidence/outputs/*.txt, ready to paste into the submission form.
# Rules respected: never uses -k, always uses the domain name in URLs.
#
# Run from the repo folder:
#   bash scripts/collect-evidence.sh client    # on Mac 4, then on Mac 1
#   bash scripts/collect-evidence.sh dns       # on Mac 1
#   bash scripts/collect-evidence.sh edge      # on Mac 2
#   bash scripts/collect-evidence.sh backend   # on Mac 3 and on Mac 4
# ============================================================
ROLE="${1:-client}"
NAME="$(scutil --get ComputerName 2>/dev/null || hostname)"
TAG="$(echo "$NAME" | tr ' ' '_')"
OUT="$(cd "$(dirname "$0")/.." && pwd)/evidence/outputs"
mkdir -p "$OUT"
URL="https://app.team1.test"

# run <file> <command string>: prints a header, the command, and its output; also saves it
run() {
  local file="$OUT/$1" cmd="$2"
  {
    echo "### $NAME | $(date '+%Y-%m-%d %H:%M:%S')"
    echo "\$ $cmd"
    bash -c "$cmd" 2>&1
    echo
  } | tee -a "$file"
}

case "$ROLE" in
  client)
    run "${TAG}_01_dns.txt"           "dig app.team1.test"
    run "${TAG}_01_dns.txt"           "nslookup api.team1.test"
    run "${TAG}_01_dns.txt"           "scutil --dns | grep nameserver | head -3"
    run "${TAG}_02_https.txt"         "curl -v $URL/api/status"
    run "${TAG}_03_load_balance.txt"  "for i in 1 2 3 4 5 6; do curl -s -D - -o /dev/null $URL/api/status | grep -iE '^(HTTP|x-backend|x-upstream)'; echo ---; done"
    run "${TAG}_04_cache.txt"         "curl -I $URL/api/info"
    ETAG="$(curl -s -D - -o /dev/null "$URL/api/info" | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r')"
    run "${TAG}_04_cache.txt"         "curl -s -D - -o /dev/null -H 'If-None-Match: $ETAG' $URL/api/info"
    run "${TAG}_04_cache.txt"         "curl -s -D - -o /dev/null -H 'If-None-Match: $ETAG' $URL/api/info"
    run "${TAG}_05_http_versions.txt" "curl -s -o /dev/null -w 'protocol=%{http_version} status=%{http_code}\n' --http1.1 $URL/api/status"
    run "${TAG}_05_http_versions.txt" "curl -s -o /dev/null -w 'protocol=%{http_version} status=%{http_code}\n' --http2 $URL/api/status"
    run "${TAG}_06_redirect.txt"      "curl -I http://app.team1.test/"
    run "${TAG}_07_tls12.txt"         "curl -v --tlsv1.2 --tls-max 1.2 -o /dev/null $URL/api/status"
    run "${TAG}_08_ports.txt"         "nc -vz app.team1.test 443"
    run "${TAG}_08_ports.txt"         "nc -vz app.team1.test 80"
    ;;
  dns)
    run "mac1_dns.txt"     "grep -v '^#' /opt/homebrew/etc/dnsmasq.conf | grep -v '^\$'"
    run "mac1_dns.txt"     "sudo lsof -nP -i :53"
    run "mac1_dns.txt"     "dig @127.0.0.1 app.team1.test"
    run "mac1_dns_log.txt" "tail -40 /opt/homebrew/var/log/dnsmasq.log"
    ;;
  edge)
    run "mac2_edge.txt"            "nginx -v"
    run "mac2_edge.txt"            "sudo nginx -t"
    run "mac2_edge.txt"            "sudo lsof -nP -iTCP -sTCP:LISTEN | grep nginx"
    run "mac2_edge.txt"            "openssl x509 -in /opt/homebrew/etc/nginx/certs/app.team1.test.crt -noout -text | grep -A1 -E 'Issuer:|Subject:|Not After|Alternative Name'"
    run "mac2_access_log.txt"      "tail -30 /opt/homebrew/var/log/nginx/team1_access.log"
    run "mac2_backends_direct.txt" "curl -s -i http://10.7.2.33:3001/api/status"
    run "mac2_backends_direct.txt" "curl -s -i http://10.7.27.28:3002/api/status"
    ;;
  backend)
    run "${TAG}_backend.txt" "lsof -nP -iTCP -sTCP:LISTEN | grep node"
    ;;
  *)
    echo "Usage: bash scripts/collect-evidence.sh client|dns|edge|backend"; exit 1 ;;
esac
echo "Saved to $OUT"
