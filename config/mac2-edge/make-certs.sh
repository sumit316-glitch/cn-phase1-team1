#!/usr/bin/env bash
# ============================================================
# Mac 2 - create a local Certificate Authority (CA) and a server
# certificate for app.team1.test + api.team1.test, signed by that CA.
#
# Usage:  bash make-certs.sh            (writes to ~/team1-certs)
# Output: ca.crt      -> copy to every CLIENT Mac and trust it
#         ca.key      -> SECRET. Never leaves Mac 2.
#         app.team1.test.crt / .key -> used by nginx
# ============================================================
set -euo pipefail

DOMAIN="team1.test"                 # <-- CHANGE if your team number is not 1
OUT="${1:-$HOME/team1-certs}"

# Prefer Homebrew's OpenSSL 3; fall back to the system one.
if command -v brew >/dev/null && [ -x "$(brew --prefix openssl@3 2>/dev/null)/bin/openssl" ]; then
  OPENSSL="$(brew --prefix openssl@3)/bin/openssl"
else
  OPENSSL="openssl"
fi
echo "Using: $($OPENSSL version)"

mkdir -p "$OUT"
cd "$OUT"

# ---------- 1. The CA: a self-signed root certificate ----------
cat > ca.cnf <<CNF
[req]
distinguished_name = dn
x509_extensions    = v3_ca
prompt             = no
[dn]
CN = Team1 Local Root CA
O  = CN Project ${DOMAIN}
[v3_ca]
basicConstraints     = critical, CA:TRUE
keyUsage             = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
CNF
"$OPENSSL" req -x509 -new -nodes -newkey rsa:2048 -sha256 -days 825 \
  -keyout ca.key -out ca.crt -config ca.cnf

# ---------- 2. Server private key + certificate signing request ----------
cat > server.cnf <<CNF
[req]
distinguished_name = dn
prompt             = no
[dn]
CN = app.${DOMAIN}
O  = CN Project ${DOMAIN}
CNF
"$OPENSSL" req -new -nodes -newkey rsa:2048 -sha256 \
  -keyout "app.${DOMAIN}.key" -out "app.${DOMAIN}.csr" -config server.cnf

# ---------- 3. CA signs the server certificate ----------
# macOS requires: SAN (the CN is ignored), EKU serverAuth, SHA-256,
# RSA >= 2048, validity <= 825 days. We use 365.
cat > server.ext <<CNF
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectAltName         = DNS:app.${DOMAIN}, DNS:api.${DOMAIN}
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
CNF
"$OPENSSL" x509 -req -in "app.${DOMAIN}.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out "app.${DOMAIN}.crt" -days 365 -sha256 -extfile server.ext

chmod 600 ca.key "app.${DOMAIN}.key"

# ---------- 4. Checks ----------
echo
"$OPENSSL" verify -CAfile ca.crt "app.${DOMAIN}.crt"
"$OPENSSL" x509 -in "app.${DOMAIN}.crt" -noout -subject -issuer -dates
"$OPENSSL" x509 -in "app.${DOMAIN}.crt" -noout -text | grep -A1 -E "Subject Alternative Name|Extended Key Usage"
echo
echo "Done. Files in $OUT:"
ls -l "$OUT"
echo
echo "Next:"
echo "  1) Copy app.${DOMAIN}.crt and app.${DOMAIN}.key to \$(brew --prefix)/etc/nginx/certs/"
echo "  2) AirDrop ca.crt (NOT ca.key) to every client Mac and trust it."
