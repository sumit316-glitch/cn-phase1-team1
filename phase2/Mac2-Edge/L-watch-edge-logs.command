#!/bin/bash
# Live nginx logs
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s_watch_edge
