#!/usr/bin/env bash
# segments/05_mount_backup.sh
# @version 1.1.0
# @description Triggers fstab automount and verifies mount
# @author Jo Zapf
# @changed 2026-01-15 - Removed explicit mount command, rely on fstab automount only
# @requires BACKUP_MNT, TARGET_DIR
# @note Mount is handled by fstab entry with x-systemd.automount option

set -euo pipefail

echo "[05] Mounting backup device..."

# Create mount directories if they don't exist
mkdir -p "${BACKUP_MNT}" "${TARGET_DIR}"

# Trigger automount by accessing the path (fstab handles the actual mount)
echo "[05] Triggering fstab automount..."
ls "${BACKUP_MNT}" >/dev/null 2>&1 || true

# Give automount time to complete
sleep 2

# Verify mount succeeded
if findmnt -rn -t ext4 -M "${BACKUP_MNT}" >/dev/null 2>&1; then
  echo "[05] Backup device mounted successfully via fstab automount"
  exit 0
else
  echo "[ERROR] Automount failed - ext4 filesystem not found at ${BACKUP_MNT}"
  echo "[ERROR] Check fstab entry and systemd automount configuration"
  echo "[DEBUG] Current mounts at ${BACKUP_MNT}:"
  findmnt -M "${BACKUP_MNT}" || echo "  (none)"
  echo "[DEBUG] Expected UUID: ${BACKUP_UUID}"
  echo "[DEBUG] fstab entry should contain: x-systemd.automount"
  exit 1
fi
