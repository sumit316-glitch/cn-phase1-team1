#!/bin/bash
# Backup DNS
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
source "$KIT/lib/steps.sh"
s11_backup_dns
