#!/usr/bin/env bash
# run-backup.sh
# @version 1.0.0
# @description Wrapper script for backup execution with proper logging
# @author Jo Zapf
# @changed 2026-01-15
# @usage ./run-backup.sh <profile>
# @example ./run-backup.sh system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${1:-system}"
TIMESTAMP=$(date +"%F_%H%M%S")
LOG_DIR="/var/log/extern_backup"
LOG_FILE="${LOG_DIR}/${PROFILE}_${TIMESTAMP}.log"

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Execute main script with full logging to both file and stdout
exec "${SCRIPT_DIR}/main.sh" "$PROFILE" 2>&1 | tee -a "$LOG_FILE"
