#!/bin/bash
# nginx edge helpers — Mac 2 (primary edge) and Mac 3 (standby edge, Ext E).

CERTDIR="$HOME/${TEAM}-certs"
NGX="$PREFIX/bin/nginx"
NGXCONF="$PREFIX/etc/nginx/servers/${TEAM}.conf"

make_certs() {
  if [ -f "$CERTDIR/ca.crt" ] && [ -f "$CERTDIR/${APP}.crt" ] && [ -f "$CERTDIR/${APP}.key" ]; then
    ok "Certificates already exist in $CERTDIR (kept, so clients don't need to re-trust)"; return 0; fi
  local OSSL="openssl"; [ -x "$(brew --prefix openssl@3 2>/dev/null)/bin/openssl" ] && OSSL="$(brew --prefix openssl@3)/bin/openssl"
  mkdir -p "$CERTDIR"; cd "$CERTDIR" || return 1
  printf '[req]\ndistinguished_name=dn\nx509_extensions=v3\nprompt=no\n[dn]\nCN=%s\nO=CN Project %s\n[v3]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n' "$CA_NAME" "$DOMAIN" > ca.cnf
  "$OSSL" req -x509 -new -nodes -newkey rsa:2048 -sha256 -days 825 -keyout ca.key -out ca.crt -config ca.cnf 2>/dev/null
  printf '[req]\ndistinguished_name=dn\nprompt=no\n[dn]\nCN=%s\nO=CN Project %s\n' "$APP" "$DOMAIN" > server.cnf
  "$OSSL" req -new -nodes -newkey rsa:2048 -sha256 -keyout "${APP}.key" -out "${APP}.csr" -config server.cnf 2>/dev/null
  printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:%s,DNS:%s\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid,issuer\n' "$APP" "$API" > server.ext
  "$OSSL" x509 -req -in "${APP}.csr" -CA ca.crt -CAkey ca.key -CAcreateserial -out "${APP}.crt" -days 365 -sha256 -extfile server.ext 2>/dev/null
  chmod 600 ca.key "${APP}.key"
  cd "$KIT" || return 1
  if openssl verify -CAfile "$CERTDIR/ca.crt" "$CERTDIR/${APP}.crt" | grep -q ": OK"; then ok "Created local CA + server certificate (SAN: $APP, $API)"
  else bad "Certificate creation failed"; return 1; fi
}

edge_write_conf() {  # edge_write_conf <edge-name> <certs-source-dir>
  local name="$1" src="$2"
  mkdir -p "$PREFIX/etc/nginx/certs" "$PREFIX/var/log/nginx" "$PREFIX/etc/nginx/servers"
  cp "$src/${APP}.crt" "$src/${APP}.key" "$PREFIX/etc/nginx/certs/"
  cat > "$NGXCONF" <<'EOF'
# nginx edge for __DOMAIN__ — __EDGE__
# Reverse proxy + round-robin load balancer + TLS termination
log_format edge '$remote_addr [$time_local] "$request" $status '
                'upstream=$upstream_addr upstream_status=$upstream_status '
                'proto=$server_protocol tls=$ssl_protocol rt=$request_time';

upstream __TEAM___backends {
    zone __TEAM___backends 1m;                 # one shared round-robin state for all workers
    # Passive health check (Ext D): 1 failed connect -> skip that backend for 10 s
    server __A__:3001 max_fails=1 fail_timeout=10s;   # Backend A (Mac 3)
    server __B__:3002 max_fails=1 fail_timeout=10s;   # Backend B (Mac 4)
}

server {                                      # plain HTTP -> HTTPS
    listen 80;
    server_name __APP__ __API__;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name __APP__ __API__;

    ssl_certificate     __PREFIX__/etc/nginx/certs/__APP__.crt;
    ssl_certificate_key __PREFIX__/etc/nginx/certs/__APP__.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:TLS:1m;

    access_log __PREFIX__/var/log/nginx/__TEAM___access.log edge;
    error_log  __PREFIX__/var/log/nginx/__TEAM___error.log warn;

    location = /favicon.ico { access_log off; return 204; }

    location / {
        proxy_pass http://__TEAM___backends;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout     2s;      # a dead backend is detected within 2 s
        proxy_read_timeout        10s;
        proxy_next_upstream       error timeout http_502 http_503 http_504;   # retry on the other backend
        proxy_next_upstream_tries 2;
        add_header X-Edge     "__EDGE__" always;
        add_header X-Upstream $upstream_addr always;
    }
}
EOF
  sed -i '' -e "s|__DOMAIN__|$DOMAIN|g" -e "s|__EDGE__|$name|g" -e "s|__TEAM__|$TEAM|g" \
            -e "s|__A__|$MAC3_IP|g" -e "s|__B__|$MAC4_IP|g" -e "s|__APP__|$APP|g" \
            -e "s|__API__|$API|g" -e "s|__PREFIX__|$PREFIX|g" "$NGXCONF"
  grep -q "include servers/\*" "$PREFIX/etc/nginx/nginx.conf" && ok "nginx.conf includes servers/*" \
    || bad "nginx.conf has no 'include servers/*;' line"
  ok "Wrote $NGXCONF (X-Edge: $name)"
}

edge_start() {
  if sudo "$NGX" -t 2>&1 | tee /dev/stderr | grep -q "test is successful"; then ok "nginx config test passed"
  else bad "nginx config test failed (message above)"; return 1; fi
  if pgrep -x nginx >/dev/null; then sudo "$NGX" -s reload && ok "nginx reloaded"
  else sudo "$NGX" && ok "nginx started"; fi
  sleep 1
  sudo lsof -nP -iTCP -sTCP:LISTEN | grep -q 'nginx.*:443' && ok "Listening on port 443" || bad "nginx is not listening on 443"
}

edge_selftest() {  # edge_selftest <ca file> <expected edge name>
  local ca="$1" want="$2" i h be edge seenA="" seenB=""
  for i in 1 2 3 4; do
    h="$(curl -s -D - -o /dev/null --cacert "$ca" --resolve "$APP:443:127.0.0.1" "$URL/api/status")"
    be="$(echo "$h" | awk -F': ' 'tolower($1)=="x-backend"{print $2}' | tr -d '\r')"
    edge="$(echo "$h" | awk -F': ' 'tolower($1)=="x-edge"{print $2}' | tr -d '\r')"
    info "request $i -> $(echo "$h" | head -1 | tr -d '\r')  X-Backend: ${be:-none}  X-Edge: ${edge:-none}"
    [ "$be" = "A" ] && seenA=1; [ "$be" = "B" ] && seenB=1
  done
  [ -n "$seenA" ] && [ -n "$seenB" ] && ok "HTTPS works and both backends answer through $want" \
    || bad "Did not see both A and B — are both backends running (steps 05 and 06)?"
}
