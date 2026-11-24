#!/bin/bash
# app -> Mac3
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s25_cutover
