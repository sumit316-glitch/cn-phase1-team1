#!/bin/bash
# Install this Mac's tools
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s02_install
