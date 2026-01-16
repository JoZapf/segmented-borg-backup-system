#!/usr/bin/env bash
# segments/05_mount_backup.sh
# @version 1.3.0
# @description Triggers fstab automount with improved device readiness checks
# @author Jo Zapf
# @changed 2026-01-16 - Added device readiness verification before automount trigger
# @requires BACKUP_MNT, TARGET_DIR, BACKUP_UUID, BACKUP_DEV
# @note Mount is handled by fstab entry with x-systemd.automount option

set -euo pipefail

echo "[05] Mounting backup device..."

# Create mount directories if they don't exist
mkdir -p "${BACKUP_MNT}" "${TARGET_DIR}"

# Check if already mounted with correct device
CURRENT_MOUNT=$(findmnt -rn -o SOURCE -M "${BACKUP_MNT}" 2>/dev/null || echo "")
if [ -n "$CURRENT_MOUNT" ]; then
  # Something is mounted, verify it's the correct device
  CURRENT_UUID=$(blkid -s UUID -o value "$CURRENT_MOUNT" 2>/dev/null || echo "")
  if [ "$CURRENT_UUID" = "$BACKUP_UUID" ]; then
    echo "[05] Backup device already mounted correctly"
    exit 0
  else
    echo "[WARN] Wrong device mounted at ${BACKUP_MNT}: $CURRENT_MOUNT (UUID: $CURRENT_UUID)"
    echo "[WARN] Expected UUID: $BACKUP_UUID"
    echo "[WARN] Attempting to unmount and remount..."
    sudo umount "${BACKUP_MNT}" || true
    sleep 1
  fi
fi

# CRITICAL: Verify device exists and is readable BEFORE triggering automount
echo "[05] Verifying device readiness..."
MAX_DEVICE_WAIT=30
DEVICE_WAIT_COUNT=0
while [ $DEVICE_WAIT_COUNT -lt $MAX_DEVICE_WAIT ]; do
  if [ -e "$BACKUP_DEV" ] && blkid -s UUID -o value "$BACKUP_DEV" >/dev/null 2>&1; then
    echo "[05] Device $BACKUP_DEV is ready"
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

# Trigger automount by accessing the path (fstab handles the actual mount)
echo "[05] Triggering fstab automount..."

# Try multiple trigger methods
# Method 1: ls (most common)
ls "${BACKUP_MNT}" >/dev/null 2>&1 || true

# Method 2: stat (alternative trigger)
stat "${BACKUP_MNT}" >/dev/null 2>&1 || true

# Wait for automount to complete (increased wait time)
echo "[05] Waiting for automount to complete..."
sleep 5

# Verify mount succeeded with retries
MAX_RETRIES=10
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  # Check if ext4 filesystem is mounted
  if findmnt -rn -t ext4 -M "${BACKUP_MNT}" >/dev/null 2>&1; then
    # Mounted, verify it's the CORRECT device
    MOUNTED_DEV=$(findmnt -rn -o SOURCE -M "${BACKUP_MNT}" 2>/dev/null)
    MOUNTED_UUID=$(blkid -s UUID -o value "$MOUNTED_DEV" 2>/dev/null || echo "")
    
    if [ "$MOUNTED_UUID" = "$BACKUP_UUID" ]; then
      echo "[05] Backup device mounted successfully via fstab automount"
      echo "[05] Device: $MOUNTED_DEV"
      echo "[05] UUID verified: $MOUNTED_UUID"
      exit 0
    else
      echo "[WARN] Wrong device mounted: $MOUNTED_DEV (UUID: $MOUNTED_UUID)"
      echo "[WARN] Expected UUID: $BACKUP_UUID"
    fi
  fi
  
  # Check systemd automount unit status
  if systemctl is-active mnt-extern_backup.automount >/dev/null 2>&1; then
    if [ $((RETRY_COUNT % 3)) -eq 0 ]; then
      # Every 3rd retry, try to trigger again
      echo "[DEBUG] Re-triggering automount (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
      ls "${BACKUP_MNT}" >/dev/null 2>&1 || true
    fi
  else
    echo "[WARN] Automount unit not active, attempting to start..."
    sudo systemctl start mnt-extern_backup.automount || true
    sleep 2
    ls "${BACKUP_MNT}" >/dev/null 2>&1 || true
  fi
  
  # Not mounted yet, wait and retry
  if [ $RETRY_COUNT -eq 0 ]; then
    echo "[DEBUG] Waiting for mount to appear..."
  fi
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  sleep 2
done

# All retries failed
echo "[ERROR] Automount failed after $MAX_RETRIES attempts"
echo "[ERROR] ext4 filesystem not found at ${BACKUP_MNT}"
echo ""
echo "[DEBUG] ===== DIAGNOSTIC INFORMATION ====="
echo "[DEBUG] Expected UUID: ${BACKUP_UUID}"
echo "[DEBUG] Device path: ${BACKUP_DEV}"
echo ""
echo "[DEBUG] Current mounts at ${BACKUP_MNT}:"
findmnt -M "${BACKUP_MNT}" 2>&1 || echo "  (none)"
echo ""
echo "[DEBUG] Automount unit status:"
systemctl status mnt-extern_backup.automount --no-pager -l 2>&1 || echo "  (not found)"
echo ""
echo "[DEBUG] Mount unit status:"
systemctl status mnt-extern_backup.mount --no-pager -l 2>&1 || echo "  (not found)"
echo ""
echo "[DEBUG] Device status:"
ls -la "${BACKUP_DEV}" 2>&1 || echo "  Device does not exist"
blkid "${BACKUP_DEV}" 2>&1 || echo "  Cannot read device UUID"
echo ""
echo "[DEBUG] fstab entry:"
grep extern_backup /etc/fstab 2>&1 || echo "  (not found)"
echo ""
echo "[DEBUG] systemd-fstab-generator output:"
ls -la /run/systemd/generator/mnt-extern_backup.* 2>&1 || echo "  (no generated units)"
echo ""
echo "[DEBUG] Journal errors (last 20 lines):"
journalctl -u mnt-extern_backup.mount -u mnt-extern_backup.automount -n 20 --no-pager 2>&1 || echo "  (no journal)"
echo "[DEBUG] ===== END DIAGNOSTIC INFORMATION ====="
echo ""
echo "[CRITICAL] Possible causes:"
echo "[CRITICAL] 1. HDD not spun up yet (increase wait time in segment 03)"
echo "[CRITICAL] 2. Device UUID changed (check with: sudo blkid | grep sdc1)"
echo "[CRITICAL] 3. Automount unit not properly configured"
echo "[CRITICAL] 4. /mnt/extern_backup directory not empty on root partition"
echo "[CRITICAL] 5. Filesystem error on device (check dmesg)"
exit 1
