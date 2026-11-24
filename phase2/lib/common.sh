#!/bin/bash
# Shared helpers for every step. Sourced by the .command files.
# macOS ships bash 3.2, so nothing here needs a newer bash.

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -f "$KIT/team.env" ]; then echo "team.env not found in $KIT"; read -r -p "Press Enter to close"; exit 1; fi
# shellcheck disable=SC1091
source "$KIT/team.env"

DOMAIN="${TEAM}.test"
APP="app.${DOMAIN}"
API="api.${DOMAIN}"
URL="https://${APP}"
PORT_A=3001
PORT_B=3002
CA_NAME="CN Project ${TEAM} Root CA"

# Homebrew on PATH (Apple Silicon or Intel)
if   [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ];   then eval "$(/usr/local/bin/brew shellenv)"; fi
PREFIX="$(brew --prefix 2>/dev/null)"

IFACE="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"; IFACE="${IFACE:-en0}"
MYIP="$(ipconfig getifaddr "$IFACE" 2>/dev/null)"

EVID="$KIT/evidence"; STATE="$KIT/state"
mkdir -p "$EVID" "$STATE"
export CURL_CA_BUNDLE="$HOME/.cn-ca-bundle.pem"
[ -f "$CURL_CA_BUNDLE" ] || unset CURL_CA_BUNDLE

# ---------- printing ----------
B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; C=$'\033[36m'; N=$'\033[0m'
title() { echo; echo "${B}${C}==================================================================${N}"; echo "${B}${C}  $*${N}"; echo "${B}${C}==================================================================${N}"; }
part()  { echo; echo "${B}--- $* ---${N}"; }
ok()    { echo "${G}✅ $*${N}"; }
bad()   { echo "${R}❌ $*${N}"; FAILED=1; }
warn()  { echo "${Y}⚠️  $*${N}"; }
info()  { echo "   $*"; }
say()   { echo "${B}👉 $*${N}"; }
show()  { echo "${C}\$ $*${N}"; bash -c "$*" 2>&1; }   # print a command, then run it

wait_enter() { echo; read -r -p "${B}${Y}⏸  $* — then press Enter here to continue...${N}" _; echo; }

finish() {
  echo
  if [ -n "$FAILED" ]; then echo "${R}${B}Something above shows ❌. Read the message next to it, fix it, and run this step again.${N}"
  else echo "${G}${B}Step finished. Everything checked out.${N}"; fi
  [ -n "$LOGFILE" ] && echo "Output saved to: $LOGFILE"
  echo; read -r -p "Press Enter to close this window..." _
}

# Save everything this step prints into evidence/
start_log() {  # start_log <step-name>
  LOGFILE="$EVID/$1-mac${THIS_MAC}-$(date +%H%M%S).txt"
  exec > >(tee -a "$LOGFILE") 2>&1
  echo "### $1 | Mac $THIS_MAC ($MYIP) | $(date '+%Y-%m-%d %H:%M:%S')"
}

# ---------- which Mac am I ----------
THIS_MAC=0
[ "$MYIP" = "$MAC1_IP" ] && THIS_MAC=1
[ "$MYIP" = "$MAC2_IP" ] && THIS_MAC=2
[ "$MYIP" = "$MAC3_IP" ] && THIS_MAC=3
[ "$MYIP" = "$MAC4_IP" ] && THIS_MAC=4

mac_ip() { eval "echo \$MAC${1}_IP"; }

need_mac() {  # need_mac 2   or   need_mac "1 4"
  for m in $1; do [ "$THIS_MAC" = "$m" ] && return 0; done
  warn "This step is meant for Mac $1, but this Mac's IP is ${MYIP:-unknown} (THIS_MAC=$THIS_MAC)."
  info "team.env says: Mac1=$MAC1_IP Mac2=$MAC2_IP Mac3=$MAC3_IP Mac4=$MAC4_IP"
  info "If this Mac's IP changed, fix team.env on ALL Macs first (and rerun the DNS/edge steps)."
  read -r -p "Continue anyway? [y/N] " a; [ "$a" = "y" ] || [ "$a" = "Y" ] || { finish; exit 1; }
}

need_brew() {
  if [ -z "$PREFIX" ]; then
    bad "Homebrew is not installed. Paste this in Terminal, then run this step again:"
    info '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    finish; exit 1
  fi
}

wifi_service() {  # the network service name (e.g. "Wi-Fi") that owns $IFACE
  networksetup -listnetworkserviceorder 2>/dev/null | awk -v dev="$IFACE" '
    /^\([0-9]+\)/ { name=$0; sub(/^\([0-9]+\) /,"",name) }
    index($0, "Device: " dev ")") { print name; exit }'
}

flush_dns() { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder 2>/dev/null; sleep 1; }

# OS resolver answer (uses the macOS cache, unlike dig)
os_lookup() {
  local a; a="$(dscacheutil -q host -a name "$1" 2>/dev/null | awk '/ip_address:/{print $2; exit}')"
  [ -z "$a" ] && a="$(ping -c 1 -t 1 "$1" 2>/dev/null | sed -n '1s/.*(\([0-9.]*\)).*/\1/p')"
  echo "${a:-unresolved}"
}

# ask for sudo once at the start so later prompts don't interrupt a demo
get_sudo() { echo "This step needs your Mac password (for sudo):"; sudo -v || { bad "sudo failed"; finish; exit 1; }; }
