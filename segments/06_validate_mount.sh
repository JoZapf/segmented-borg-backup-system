#!/usr/bin/env bash
# segments/06_validate_mount.sh
# @version 1.1.0
# @description Validates that correct UUID is mounted at backup location
# @author Jo Zapf
# @changed 2026-01-25 - Added critical mountpoint verification to prevent root filesystem writes
# @changed 2026-01-13 - Fixed: Handle multiple mount entries by using only first line
# @requires BACKUP_MNT, BACKUP_UUID

set -euo pipefail

echo "[06] Validating mount..."

# Get mount information (only first line if multiple mounts exist)
mount_info=$(findmnt -rn -t ext4 -M "${BACKUP_MNT}" -o UUID,SOURCE,FSTYPE 2>/dev/null | head -1 || true)

if [ -z "${mount_info}" ]; then
  echo "[ERROR] No ext4 mount found at ${BACKUP_MNT}"
  echo "[DEBUG] All mounts:"
  findmnt || true
  exit 1
fi

# Parse mount info
mounted_uuid=$(echo "${mount_info}" | awk '{print $1}' | tr -d '[:space:]')
mounted_source=$(echo "${mount_info}" | awk '{print $2}' | tr -d '[:space:]')
mounted_fstype=$(echo "${mount_info}" | awk '{print $3}' | tr -d '[:space:]')

echo "[06] Mounted device: ${mounted_source}"
echo "[06] UUID: ${mounted_uuid}"
echo "[06] Filesystem: ${mounted_fstype}"

# Validate filesystem type
if [ "${mounted_fstype}" != "ext4" ]; then
  echo "[ERROR] Wrong filesystem type: ${mounted_fstype} (expected ext4)"
  exit 1
fi

# Validate UUID
if [ "${mounted_uuid}" != "${BACKUP_UUID}" ]; then
  echo "[ERROR] Wrong UUID mounted!"
  echo "[ERROR] Expected: ${BACKUP_UUID}"
  echo "[ERROR] Got: ${mounted_uuid}"
  echo "[ERROR] This could be a different disk - aborting for safety"
  exit 1
fi

# CRITICAL: Verify mount point is actually mounted (not just a directory on root)
# This prevents catastrophic writes to root filesystem if mount fails
if ! mountpoint -q "${BACKUP_MNT}"; then
  echo "[CRITICAL] ${BACKUP_MNT} is NOT a mount point!"
  echo "[CRITICAL] This is a directory on the root filesystem"
  echo "[CRITICAL] ABORTING to prevent writing backups to root partition"
  echo "[CRITICAL] "
  echo "[CRITICAL] Possible causes:"
  echo "[CRITICAL] 1. Device failed to mount (check segment 05 output)"
  echo "[CRITICAL] 2. Mount was unmounted after validation"
  echo "[CRITICAL] 3. systemd mount unit failed"
  echo "[CRITICAL] "
  echo "[CRITICAL] Debug information:"
  mount | grep "${BACKUP_MNT}" || echo "[CRITICAL] No mount found for ${BACKUP_MNT}"
  echo "[CRITICAL] "
  echo "[CRITICAL] If mount-point has immutable flag, this is working as designed!"
  echo "[CRITICAL] The immutable flag prevents accidental writes to root filesystem."
  exit 1
fi

# Additional safety: Verify source device is a block device (not bind mount)
if [[ "${mounted_source}" == *"["* ]]; then
  echo "[CRITICAL] Detected bind mount or overlay: ${mounted_source}"
  echo "[CRITICAL] This is NOT a proper block device mount"
  echo "[CRITICAL] ABORTING to prevent data corruption"
  exit 1
fi

# Check if mount point is busy (conflicting file managers, etc.)
if lsof +f -- "${BACKUP_MNT}" 2>/dev/null | grep -q .; then
  echo "[WARN] Mount point has open file handles:"
  lsof +f -- "${BACKUP_MNT}" | head -n 20 || true
  echo "[WARN] This may cause unmount issues later"
fi

# Set backup log path now that mount is confirmed
export BACKUP_LOG="${TARGET_DIR}/${BACKUP_LOG_SUBDIR}/${BACKUP_PROFILE}_${TIMESTAMP}.log"
mkdir -p "${TARGET_DIR}/${BACKUP_LOG_SUBDIR}"

echo "[06] Mount validation successful"
echo "[06] Confirmed: ${BACKUP_MNT} is a proper block device mount"
echo "[06] Backup log will be saved to: ${BACKUP_LOG}"
