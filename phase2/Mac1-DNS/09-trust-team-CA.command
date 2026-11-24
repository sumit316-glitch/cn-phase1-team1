#!/bin/bash
# Trust CA
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s09_trust
