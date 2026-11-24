#!/bin/bash
# Restart primary DNS
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s15_restart_primary
