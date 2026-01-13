#!/usr/bin/env bash
# segments/04_wait_device.sh
# @version 1.0.0
# @description Waits for backup device to become available with timeout
# @author Jo
# @changed 2026-01-12
# @requires BACKUP_DEV, DEVICE_WAIT_SECONDS

set -euo pipefail

echo "[04] Waiting for backup device..."

echo "[04] Device: ${BACKUP_DEV}"
echo "[04] Timeout: ${DEVICE_WAIT_SECONDS}s"

# Poll for device availability
for i in $(seq 1 "${DEVICE_WAIT_SECONDS}"); do
  if [ -b "${BACKUP_DEV}" ]; then
    echo "[04] Device available after ${i}s"
    
    # Show device info
    if command -v lsblk >/dev/null 2>&1; then
      echo "[04] Device info:"
      lsblk "${BACKUP_DEV}" || true
    fi
    
    exit 0
  fi
  
  # Progress indicator every 10 seconds
  if [ $((i % 10)) -eq 0 ]; then
    echo "[04] Still waiting... (${i}/${DEVICE_WAIT_SECONDS}s)"
  fi
  
  sleep 1
done

echo "[ERROR] Device not available after ${DEVICE_WAIT_SECONDS}s timeout"
echo "[ERROR] Device: ${BACKUP_DEV}"
exit 1
