#!/usr/bin/env bash
# Shows which backend served each request (round-robin evidence).
# Usage: bash lb-test.sh [count] [url]
N="${1:-10}"
URL="${2:-https://app.team1.test/api/status}"
echo "Sending $N requests to $URL"
for i in $(seq 1 "$N"); do
  hdr="$(curl -s -D - -o /dev/null "$URL")" || { echo "request $i -> curl failed (exit $?)"; continue; }
  code="$(echo "$hdr" | awk 'NR==1{print $2}')"
  be="$(echo "$hdr" | awk -F': ' 'tolower($1)=="x-backend"{print $2}' | tr -d '\r')"
  up="$(echo "$hdr" | awk -F': ' 'tolower($1)=="x-upstream"{print $2}' | tr -d '\r')"
  echo "request $i -> HTTP $code   X-Backend: ${be:-none}   via ${up:-?}"
done
