#!/bin/bash
# Two DNS servers
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s12_resolvers_p2
