#!/usr/bin/env bash
# segments/12_unmount_backup.sh
# @version 1.2.0
# @description Safely unmounts backup device for ALL profiles (security improvement)
# @author Jo Zapf
# @changed 2026-01-22 - Fixed dynamic systemd unit detection (Bug fix for dev-data profile)
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
  # Derive systemd unit name from mount point (e.g., /mnt/system_backup -> mnt-system_backup)
  SYSTEMD_UNIT=$(echo "${BACKUP_MNT}" | sed 's|^/||; s|/|-|g')
  
  echo "[WARN] Open file handles detected:"
  lsof +f -- "${BACKUP_MNT}" | head -n 50 || true
  echo ""
  echo "[ERROR] Cannot safely unmount - close all file managers and retry"
  echo "[HINT] Use: sudo systemctl stop ${SYSTEMD_UNIT}.automount"
  echo "[HINT] Then: sudo umount ${BACKUP_MNT}"
  exit 1
fi

# Stop systemd automount and mount units (dynamically derived from BACKUP_MNT)
echo "[12] Stopping systemd mount units..."
# Derive systemd unit name from mount point (e.g., /mnt/system_backup -> mnt-system_backup)
SYSTEMD_UNIT=$(echo "${BACKUP_MNT}" | sed 's|^/||; s|/|-|g')
systemctl stop "${SYSTEMD_UNIT}.automount" 2>/dev/null || true
systemctl stop "${SYSTEMD_UNIT}.mount" 2>/dev/null || true

# Wait a moment for systemd to settle
sleep 2

# Force unmount for ALL profiles (security improvement: quasi-offline protection)
echo "[12] Unmounting ${BACKUP_MNT}..."
if umount "${BACKUP_MNT}" 2>/dev/null; then
  echo "[12] Unmount successful - backup quasi-offline (ransomware protection)"
elif umount -l "${BACKUP_MNT}" 2>/dev/null; then
  echo "[12] Lazy unmount successful (busy filesystem)"
  sleep 2
else
  echo "[ERROR] Unmount failed - manual intervention required"
  echo "[ERROR] Device: ${BACKUP_MNT}"
  findmnt -M "${BACKUP_MNT}" 2>&1 || true
  exit 1
fi

# Final sync
sync

# Verify unmount succeeded
sleep 1
if findmnt -rn -t ext4 -M "${BACKUP_MNT}" >/dev/null 2>&1; then
  # Derive systemd unit name from mount point
  SYSTEMD_UNIT=$(echo "${BACKUP_MNT}" | sed 's|^/||; s|/|-|g')
  
  echo "[ERROR] Unmount failed - ext4 filesystem still mounted"
  echo "[ERROR] Manual intervention required:"
  echo "  1. sudo systemctl stop ${SYSTEMD_UNIT}.automount"
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
