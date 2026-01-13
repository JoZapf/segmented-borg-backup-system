#!/usr/bin/env bash
# tests/01_validate_config.test.sh
# @version 1.0.0
# @description Unit test for configuration validation segment
# @author Jo
# @changed 2026-01-12

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
SEGMENT="${PROJECT_ROOT}/segments/01_validate_config.sh"

echo "=== TEST: 01_validate_config ==="

# Load test profile
source "${PROJECT_ROOT}/config/common.env"
source "${PROJECT_ROOT}/config/profiles/system.env"

# Test 1: Segment exists and is executable
echo "[TEST] Check segment exists and is executable"
if [ -x "${SEGMENT}" ]; then
  echo "[PASS] Segment is executable"
else
  echo "[FAIL] Segment not found or not executable"
  exit 1
fi

# Test 2: Required commands are available
echo "[TEST] Check required commands"
for cmd in borg curl findmnt lsof; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    echo "[PASS] Command available: ${cmd}"
  else
    echo "[FAIL] Command not available: ${cmd}"
    exit 1
  fi
done

# Test 3: Configuration variables are set
echo "[TEST] Check configuration variables"
required_vars=(
  "BACKUP_PROFILE"
  "BACKUP_SOURCES"
  "BACKUP_UUID"
  "BACKUP_DEV"
)

for var in "${required_vars[@]}"; do
  if [ -n "${!var:-}" ]; then
    echo "[PASS] Variable set: ${var}"
  else
    echo "[FAIL] Variable not set: ${var}"
    exit 1
  fi
done

# Test 4: Execute segment (dry-run style - just validates, doesn't change system)
echo "[TEST] Execute segment"
if "${SEGMENT}"; then
  echo "[PASS] Segment executed successfully"
else
  echo "[FAIL] Segment execution failed"
  exit 1
fi

echo "=== TEST COMPLETE: 01_validate_config [SUCCESS] ==="
exit 0
