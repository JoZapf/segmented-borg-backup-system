#!/usr/bin/env bash
# segments/02_init_logging.sh
# @version 1.0.0
# @description Initializes dual logging (local fallback + backup location)
# @author Jo Zapf
# @changed 2026-01-12
# @requires common.env, LOCAL_LOG_DIR

set -euo pipefail

echo "[02] Initializing logging..."

# Create log directory if it doesn't exist
mkdir -p "${LOCAL_LOG_DIR}"

# Generate timestamp for this backup run
export TIMESTAMP=$(date +"%F_%H%M%S")

# Set log file paths
export LOCAL_LOG="${LOCAL_LOG_DIR}/${BACKUP_PROFILE}_${TIMESTAMP}.log"

# Backup log will be set later when mount is confirmed
export BACKUP_LOG=""

# Redirect all output to log file (while maintaining stdout)
exec > >(tee -a "${LOCAL_LOG}") 2>&1

echo "==============================================================================="
echo "  BACKUP SYSTEM v${BACKUP_SYSTEM_VERSION}"
echo "==============================================================================="
echo "Started: $(date -Iseconds)"
echo "Profile: ${BACKUP_PROFILE}"
echo "Log: ${LOCAL_LOG}"
echo "==============================================================================="
echo ""

echo "[02] Logging initialized"
