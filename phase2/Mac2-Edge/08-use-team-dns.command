#!/bin/bash
# Use Mac1 DNS
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s08_resolvers_p1
