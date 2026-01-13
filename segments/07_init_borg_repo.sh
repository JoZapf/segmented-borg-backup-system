#!/usr/bin/env bash
# segments/07_init_borg_repo.sh
# @version 1.0.0
# @description Initializes Borg repository if it doesn't exist
# @author Jo
# @changed 2026-01-12
# @requires REPO, BORG_PASSPHRASE_FILE

set -euo pipefail

echo "[07] Checking Borg repository..."

# Set Borg environment variables
export BORG_PASSCOMMAND="cat ${BORG_PASSPHRASE_FILE}"
export BORG_LOCK_WAIT="${BORG_LOCK_WAIT}"

# Check if repository exists
if borg info "${REPO}" >/dev/null 2>&1; then
  echo "[07] Repository exists: ${REPO}"
  
  # Show repository info
  echo "[07] Repository info:"
  borg info "${REPO}" | head -n 15 || true
  
  exit 0
fi

# Initialize new repository
echo "[07] Initializing new repository: ${REPO}"
echo "[07] Encryption: repokey-blake2"

if borg init --encryption=repokey-blake2 "${REPO}"; then
  echo "[07] Repository initialized successfully"
  echo "[IMPORTANT] Repository key stored in repository config"
  echo "[IMPORTANT] Passphrase stored in: ${BORG_PASSPHRASE_FILE}"
  echo "[IMPORTANT] Back up both for disaster recovery!"
else
  echo "[ERROR] Failed to initialize repository"
  exit 1
fi
