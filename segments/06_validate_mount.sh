#!/usr/bin/env bash
# segments/06_validate_mount.sh
# @version 1.0.1
# @description Validates that correct UUID is mounted at backup location
# @author Jo Zapf
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
echo "[06] Backup log will be saved to: ${BACKUP_LOG}"
