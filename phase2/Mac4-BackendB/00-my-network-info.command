#!/bin/bash
# Show this Mac's IP etc.
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s00_netinfo
