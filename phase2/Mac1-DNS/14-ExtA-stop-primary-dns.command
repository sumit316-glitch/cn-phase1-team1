#!/bin/bash
# Stop primary DNS
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s14_stop_primary
