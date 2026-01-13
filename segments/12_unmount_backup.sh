#!/usr/bin/env bash
# segments/12_unmount_backup.sh
# @version 1.0.0
# @description Safely unmounts backup device after ensuring no open file handles
# @author Jo Zapf
# @changed 2026-01-12
# @requires BACKUP_MNT

set -euo pipefail

echo "[12] Unmounting backup device..."

# Change to safe directory (not on backup mount)
cd /

# Sync filesystem buffers
echo "[12] Syncing filesystem buffers..."
sync

# Check for open file handles before unmounting
echo "[12] Checking for open file handles..."
if lsof +f -- "${BACKUP_MNT}" 2>/dev/null | grep -q .; then
  echo "[WARN] Open file handles detected:"
  lsof +f -- "${BACKUP_MNT}" | head -n 50 || true
  echo ""
  echo "[ERROR] Cannot safely unmount - close all file managers and retry"
  echo "[HINT] Use: sudo systemctl stop mnt-extern_backup.automount"
  echo "[HINT] Then: sudo umount ${BACKUP_MNT}"
  exit 1
fi

# Stop systemd automount and mount units
echo "[12] Stopping systemd mount units..."
systemctl stop mnt-extern_backup.automount 2>/dev/null || true
systemctl stop mnt-extern_backup.mount 2>/dev/null || true

# Wait a moment for systemd to settle
sleep 2

# Attempt unmount
echo "[12] Unmounting ${BACKUP_MNT}..."
if umount "${BACKUP_MNT}" 2>/dev/null; then
  echo "[12] Unmount command executed"
else
  # Check if actually unmounted despite error
  if ! findmnt -M "${BACKUP_MNT}" >/dev/null 2>&1; then
    echo "[12] Device successfully unmounted (benign error message)"
  else
    echo "[WARN] Unmount command returned error, checking state..."
  fi
fi

# Final sync
sync

# Verify unmount succeeded
sleep 1
if findmnt -rn -t ext4 -M "${BACKUP_MNT}" >/dev/null 2>&1; then
  echo "[ERROR] Unmount failed - ext4 filesystem still mounted"
  echo "[ERROR] Manual intervention required:"
  echo "  1. sudo systemctl stop mnt-extern_backup.automount"
  echo "  2. Close all file managers"
  echo "  3. sudo umount ${BACKUP_MNT}"
  exit 1
fi

echo "[12] Unmount successful"

# Copy log to backup location if it was set
if [ -n "${BACKUP_LOG:-}" ] && [ -f "${LOCAL_LOG:-}" ]; then
  echo "[12] Note: Log was saved during backup run"
  echo "[12] Local log: ${LOCAL_LOG}"
fi

exit 0
