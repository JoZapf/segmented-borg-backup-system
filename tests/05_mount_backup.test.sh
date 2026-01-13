#!/usr/bin/env bash
# tests/05_mount_backup.test.sh
# @version 1.0.0
# @description Unit test for mount backup segment (requires real hardware)
# @author Jo
# @changed 2026-01-12

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
SEGMENT="${PROJECT_ROOT}/segments/05_mount_backup.sh"

echo "=== TEST: 05_mount_backup ==="
echo "[INFO] This test requires real hardware to be available"

# Load test profile
source "${PROJECT_ROOT}/config/common.env"
source "${PROJECT_ROOT}/config/profiles/system.env"

# Test 1: Backup device must be available
echo "[TEST] Check backup device availability"
if [ -b "${BACKUP_DEV}" ]; then
  echo "[PASS] Backup device available: ${BACKUP_DEV}"
else
  echo "[SKIP] Backup device not available - cannot test mount"
  echo "[INFO] Device expected: ${BACKUP_DEV}"
  exit 0  # Skip test, don't fail
fi

# Test 2: Execute mount segment
echo "[TEST] Execute mount segment"
if "${SEGMENT}"; then
  echo "[PASS] Mount segment executed"
else
  echo "[FAIL] Mount segment failed"
  exit 1
fi

# Test 3: Verify mount is active
echo "[TEST] Verify mount is active"
if findmnt -M "${BACKUP_MNT}" >/dev/null 2>&1; then
  echo "[PASS] Mount point is active: ${BACKUP_MNT}"
else
  echo "[FAIL] Mount point not found: ${BACKUP_MNT}"
  exit 1
fi

# Test 4: Verify correct filesystem type
echo "[TEST] Verify filesystem type"
fstype=$(findmnt -rn -M "${BACKUP_MNT}" -o FSTYPE)
if [ "${fstype}" = "ext4" ]; then
  echo "[PASS] Correct filesystem type: ${fstype}"
else
  echo "[FAIL] Wrong filesystem type: ${fstype} (expected ext4)"
  exit 1
fi

# Test 5: Verify UUID matches
echo "[TEST] Verify UUID matches"
mounted_uuid=$(findmnt -rn -M "${BACKUP_MNT}" -o UUID | tr -d '[:space:]')
if [ "${mounted_uuid}" = "${BACKUP_UUID}" ]; then
  echo "[PASS] Correct UUID mounted: ${mounted_uuid}"
else
  echo "[FAIL] Wrong UUID: ${mounted_uuid} (expected ${BACKUP_UUID})"
  exit 1
fi

# Test 6: Verify mount point is writable
echo "[TEST] Verify mount point is writable"
test_file="${TARGET_DIR}/.write_test_$$"
if touch "${test_file}" 2>/dev/null; then
  rm -f "${test_file}"
  echo "[PASS] Mount point is writable"
else
  echo "[FAIL] Mount point is not writable"
  exit 1
fi

echo "=== TEST COMPLETE: 05_mount_backup [SUCCESS] ==="
exit 0
