#!/usr/bin/env bash
# segments/05_mount_backup.sh
# @version 1.0.0
# @description Idempotently mounts backup device via systemd automount
# @author Jo Zapf
# @changed 2026-01-12
# @requires BACKUP_MNT, TARGET_DIR

set -euo pipefail

echo "[05] Mounting backup device..."

# Create mount directories if they don't exist
mkdir -p "${BACKUP_MNT}" "${TARGET_DIR}"

# Trigger automount by accessing the path
echo "[05] Triggering automount..."
ls "${BACKUP_MNT}" >/dev/null 2>&1 || true

# Check if already mounted (ext4 filesystem)
if findmnt -rn -t ext4 -M "${BACKUP_MNT}" >/dev/null 2>&1; then
  echo "[05] Backup device already mounted (ext4)"
  exit 0
fi

# Attempt explicit mount (tolerates "already mounted" error)
echo "[05] Attempting explicit mount..."
mount "${BACKUP_MNT}" 2>&1 || {
  # Check if mount succeeded despite error message
  if findmnt -rn -t ext4 -M "${BACKUP_MNT}" >/dev/null 2>&1; then
    echo "[05] Mount succeeded (error message was benign)"
    exit 0
  fi
  
  echo "[WARN] Mount command returned error, but checking final state..."
}

# Trigger automount again and verify
ls "${BACKUP_MNT}" >/dev/null 2>&1 || true
sleep 2

# Final verification
if findmnt -rn -t ext4 -M "${BACKUP_MNT}" >/dev/null 2>&1; then
  echo "[05] Mount successful"
  exit 0
else
  echo "[ERROR] Mount failed - ext4 filesystem not found at ${BACKUP_MNT}"
  echo "[DEBUG] Current mounts at ${BACKUP_MNT}:"
  findmnt -M "${BACKUP_MNT}" || echo "  (none)"
  exit 1
fi
