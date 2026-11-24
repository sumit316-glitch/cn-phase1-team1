#!/bin/bash
# Zip evidence to Desktop
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s98_pack
