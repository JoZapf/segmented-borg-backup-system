#!/usr/bin/env bash
# segments/08_borg_backup.sh
# @version 1.0.1
# @description Creates Borg backup archive from configured sources
# @author Jo Zapf
# @changed 2026-01-13 - Fixed: Disable set -e during borg execution to properly handle exit code 1 (warnings)
# @requires All Borg configuration variables

set -euo pipefail

echo "[08] Creating Borg backup archive..."

# Set Borg environment variables
export BORG_PASSCOMMAND="cat ${BORG_PASSPHRASE_FILE}"
export BORG_LOCK_WAIT="${BORG_LOCK_WAIT}"

# Generate archive name with timestamp
archive="${ARCHIVE_PREFIX}-{now:%Y-%m-%d_%H%M%S}"

echo "[08] Archive name pattern: ${archive}"
echo "[08] Sources: ${BACKUP_SOURCES}"
echo "[08] Compression: ${BORG_COMPRESSION}"

# Build borg create command dynamically
borg_cmd=(
  borg create
  --stats
  --progress
  --compression "${BORG_COMPRESSION}"
)

# Add one-file-system flag if enabled
if [ "${BACKUP_ONE_FILE_SYSTEM}" = "true" ]; then
  borg_cmd+=(--one-file-system)
  echo "[08] Option: one-file-system (stay within filesystem boundaries)"
fi

# Add exclude-caches flag if enabled
if [ "${BACKUP_EXCLUDE_CACHES}" = "true" ]; then
  borg_cmd+=(--exclude-caches)
  echo "[08] Option: exclude-caches (skip cache directories)"
fi

# Add excludes
IFS=';' read -ra excludes <<< "${BACKUP_EXCLUDES}"
for excl in "${excludes[@]}"; do
  if [ -n "${excl}" ]; then
    borg_cmd+=(--exclude "${excl}")
    echo "[08] Exclude: ${excl}"
  fi
done

# Add repository and archive name
borg_cmd+=("${REPO}::${archive}")

# Add source paths
IFS=';' read -ra sources <<< "${BACKUP_SOURCES}"
borg_cmd+=("${sources[@]}")

echo ""
echo "[08] Starting backup..."
echo "[08] Command: ${borg_cmd[*]}"
echo ""

# Execute backup
# Temporarily disable errexit to capture borg's exit code
# Borg returns: 0=success, 1=warning (files changed), 2+=error
set +e
"${borg_cmd[@]}"
borg_exit=$?
set -e

# Handle exit codes: 0 and 1 are acceptable (success/warning)
if [ $borg_exit -eq 0 ] || [ $borg_exit -eq 1 ]; then
  echo ""
  if [ $borg_exit -eq 1 ]; then
    echo "[08] Backup completed with warnings (files changed during backup)"
  else
    echo "[08] Backup archive created successfully"
  fi
  
  # Store archive name for next segments
  export LATEST_ARCHIVE=$(borg list --last 1 --format '{archive}' "${REPO}")
  echo "[08] Latest archive: ${LATEST_ARCHIVE}"
  
  exit 0
else
  echo ""
  echo "[ERROR] Backup failed with exit code ${borg_exit}"
  exit 1
fi
