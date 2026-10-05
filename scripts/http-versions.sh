#!/usr/bin/env bash
# Shows the same URL over HTTP/1.1 and HTTP/2 (negotiated with TLS ALPN).
URL="${1:-https://app.team1.test/api/status}"
echo "== Forced HTTP/1.1 =="; curl -s -o /dev/null -w "protocol=%{http_version}  status=%{http_code}\n" --http1.1 "$URL"
echo "== HTTP/2 (ALPN h2) =="; curl -s -o /dev/null -w "protocol=%{http_version}  status=%{http_code}\n" --http2 "$URL"
echo; echo "ALPN negotiation as curl reports it:"; curl -sv --http2 -o /dev/null "$URL" 2>&1 | grep -iE "ALPN|using HTTP"
