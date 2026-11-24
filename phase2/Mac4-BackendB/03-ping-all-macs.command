#!/bin/bash
# Ping the other Macs
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s03_ping
