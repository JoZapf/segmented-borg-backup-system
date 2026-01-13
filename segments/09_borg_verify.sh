#!/usr/bin/env bash
# segments/09_borg_verify.sh
# @version 1.0.0
# @description Verifies integrity of latest Borg backup archive
# @author Jo Zapf
# @changed 2026-01-12
# @requires REPO, BORG_PASSPHRASE_FILE

set -euo pipefail

echo "[09] Verifying backup integrity..."

# Set Borg environment variables
export BORG_PASSCOMMAND="cat ${BORG_PASSPHRASE_FILE}"
export BORG_LOCK_WAIT="${BORG_LOCK_WAIT}"

# Get latest archive name
latest_archive=$(borg list --last 1 --format '{archive}' "${REPO}" 2>/dev/null || echo "")

if [ -z "${latest_archive}" ]; then
  echo "[ERROR] No archive found to verify"
  exit 1
fi

echo "[09] Verifying archive: ${latest_archive}"
echo "[09] This performs a full data integrity check..."
echo ""

# Verify archive data integrity
if borg check --verify-data "${REPO}::${latest_archive}"; then
  echo ""
  echo "[09] Verification successful - archive integrity confirmed"
  exit 0
else
  echo ""
  echo "[ERROR] Verification failed - archive may be corrupted"
  exit 1
fi
