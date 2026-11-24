#!/bin/bash
# Live DNS log
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s_watch_dns
