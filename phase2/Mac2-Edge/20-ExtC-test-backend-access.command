#!/bin/bash
# Firewall test (edge view)
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s20_fw_test
