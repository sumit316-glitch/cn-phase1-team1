#!/bin/bash
# Primary DNS
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s04_primary_dns
