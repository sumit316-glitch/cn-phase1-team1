#!/usr/bin/env bash
# Task F: full request -> conditional request (304) -> mismatched ETag (200).
# Usage: bash cache-test.sh [url]
URL="${1:-https://app.team1.test/api/info}"
show() { grep -iE '^(HTTP|cache-control|etag|x-backend|content-length)' | tr -d '\r'; }

echo "== 1) Full request: no validator sent, server returns 200 + body =="
curl -s -D - -o /dev/null "$URL" | show
ETAG="$(curl -s -D - -o /dev/null "$URL" | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r')"
echo
echo "== 2) Conditional requests: If-None-Match: $ETAG  (sent twice, so both backends answer) =="
for i in 1 2; do curl -s -D - -o /dev/null -H "If-None-Match: $ETAG" "$URL" | show; echo; done
echo "== 3) Validator that does not match: server sends a fresh 200 =="
curl -s -D - -o /dev/null -H 'If-None-Match: "outdated"' "$URL" | show
