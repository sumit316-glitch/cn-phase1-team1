#!/usr/bin/env bash
# Pings every team Mac 3 times and prints a one-line verdict per IP.
# Usage: bash ping-all.sh 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14
[ $# -eq 0 ] && { echo "Usage: bash ping-all.sh <ip1> <ip2> ..."; exit 1; }
echo "From $(scutil --get ComputerName 2>/dev/null || hostname) ($(ipconfig getifaddr en0 2>/dev/null))"
for ip in "$@"; do
  out="$(ping -c 3 -t 5 "$ip" 2>&1)"
  loss="$(echo "$out" | grep -o '[0-9.]*% packet loss')"
  rtt="$(echo "$out" | awk -F'/' '/round-trip|rtt/{print $5" ms avg"}')"
  if echo "$loss" | grep -q '^0.0%'; then echo "OK    $ip   $loss   $rtt"; else echo "FAIL  $ip   ${loss:-no reply}"; fi
done
