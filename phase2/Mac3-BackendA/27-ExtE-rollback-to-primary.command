#!/bin/bash
# app -> Mac2 (backup DNS)
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s27_rollback
