#!/usr/bin/env bash
# Prints the network facts Task A asks for.
# Usage: bash mac-info.sh            (auto-detects the active interface)
#        bash mac-info.sh en0
IF="${1:-$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')}"
IF="${IF:-en0}"
MASK="$(ipconfig getoption "$IF" subnet_mask 2>/dev/null)"
PREFIX="$(echo "$MASK" | awk -F. '{n=0; for(i=1;i<=4;i++){x=$i; while(x>0){n+=x%2; x=int(x/2)}} print n}')"
echo "Computer name : $(scutil --get ComputerName 2>/dev/null || hostname)"
echo "Interface     : $IF"
echo "IPv4 address  : $(ipconfig getifaddr "$IF")"
echo "Subnet mask   : $MASK  (/$PREFIX)"
echo "Gateway       : $(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')"
echo "MAC address   : $(ifconfig "$IF" | awk '/ether/{print $2}')"
echo "DNS servers   : $(scutil --dns | awk '/nameserver\[[0-9]+\]/{print $3}' | awk '!seen[$0]++' | head -3 | tr '\n' ' ')"
echo "Date          : $(date)"
