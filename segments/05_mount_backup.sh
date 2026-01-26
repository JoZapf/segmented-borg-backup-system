#!/usr/bin/env bash
# segments/05_mount_backup.sh
# @version 2.0.0
# @description Mounts backup device using direct fstab mount (no automount)
# @author Jo Zapf
# @changed 2026-01-26 - Complete rewrite: Direct mount instead of automount triggering
# @changed 2026-01-22 - Fixed validation to handle systemd autofs layer correctly
# @requires BACKUP_MNT, TARGET_DIR, BACKUP_UUID, BACKUP_DEV
# @note Requires fstab entry with 'noauto' option (manual mount, no automount)

set -euo pipefail

echo "[05] Mounting backup device..."

# Create mount directories if they don't exist
mkdir -p "${BACKUP_MNT}" "${TARGET_DIR}"

# Check if already mounted with correct device
CURRENT_MOUNT=$(findmnt -rn -t ext4 -o SOURCE -M "${BACKUP_MNT}" 2>/dev/null || echo "")
if [ -n "$CURRENT_MOUNT" ]; then
  # ext4 filesystem is mounted, verify it's the correct device
  CURRENT_UUID=$(blkid -s UUID -o value "$CURRENT_MOUNT" 2>/dev/null || echo "")
  if [ "$CURRENT_UUID" = "$BACKUP_UUID" ]; then
    echo "[05] Backup device already mounted correctly"
    echo "[05] Device: $CURRENT_MOUNT"
    echo "[05] UUID: $CURRENT_UUID"
    exit 0
  else
    echo "[WARN] Wrong device mounted at ${BACKUP_MNT}: $CURRENT_MOUNT"
    echo "[WARN] Current UUID: $CURRENT_UUID"
    echo "[WARN] Expected UUID: $BACKUP_UUID"
    echo "[WARN] Attempting to unmount and remount..."
    umount "${BACKUP_MNT}" 2>/dev/null || true
    sleep 2
  fi
fi

# CRITICAL: Verify device exists and is readable BEFORE mounting
echo "[05] Verifying device readiness..."
MAX_DEVICE_WAIT=30
DEVICE_WAIT_COUNT=0
while [ $DEVICE_WAIT_COUNT -lt $MAX_DEVICE_WAIT ]; do
  if [ -e "$BACKUP_DEV" ] && blkid -s UUID -o value "$BACKUP_DEV" >/dev/null 2>&1; then
    FOUND_UUID=$(blkid -s UUID -o value "$BACKUP_DEV")
    echo "[05] Device $BACKUP_DEV is ready"
    echo "[05] UUID: $FOUND_UUID"
    break
  fi
  
  if [ $DEVICE_WAIT_COUNT -eq 0 ]; then
    echo "[WARN] Device $BACKUP_DEV not ready yet, waiting..."
  fi
  
  DEVICE_WAIT_COUNT=$((DEVICE_WAIT_COUNT + 1))
  sleep 1
done

if [ $DEVICE_WAIT_COUNT -eq $MAX_DEVICE_WAIT ]; then
  echo "[ERROR] Device $BACKUP_DEV not ready after ${MAX_DEVICE_WAIT}s"
  echo "[ERROR] Check if HDD has spun up (Shelly power-on delay may be insufficient)"
  echo "[DEBUG] Device path: $BACKUP_DEV"
  echo "[DEBUG] Expected UUID: $BACKUP_UUID"
  ls -la "$BACKUP_DEV" 2>&1 || echo "[DEBUG] Device does not exist"
  exit 1
fi

# Mount the device using fstab entry
echo "[05] Mounting device via fstab..."
if mount "${BACKUP_MNT}" 2>/dev/null; then
  echo "[05] Mount command successful"
else
  echo "[ERROR] Mount command failed"
  echo "[DEBUG] Attempting mount with verbose output..."
  mount -v "${BACKUP_MNT}" || true
  exit 1
fi

# Wait briefly for mount to stabilize
sleep 2

# Verify mount succeeded
MOUNTED_DEV=$(findmnt -rn -t ext4 -o SOURCE -M "${BACKUP_MNT}" 2>/dev/null || echo "")
if [ -z "$MOUNTED_DEV" ]; then
  echo "[ERROR] Mount verification failed - no ext4 filesystem at ${BACKUP_MNT}"
  echo "[DEBUG] Current mounts:"
  findmnt -M "${BACKUP_MNT}" 2>&1 || echo "  (none)"
  exit 1
fi

# Verify it's the correct device
MOUNTED_UUID=$(blkid -s UUID -o value "$MOUNTED_DEV" 2>/dev/null || echo "")
if [ "$MOUNTED_UUID" != "$BACKUP_UUID" ]; then
  echo "[ERROR] Wrong device mounted!"
  echo "[ERROR] Mounted: $MOUNTED_DEV (UUID: $MOUNTED_UUID)"
  echo "[ERROR] Expected UUID: $BACKUP_UUID"
  exit 1
fi

echo "[05] Backup device mounted successfully"
echo "[05] Device: $MOUNTED_DEV"
echo "[05] Mount point: ${BACKUP_MNT}"
echo "[05] UUID verified: $MOUNTED_UUID"

exit 0
