#!/usr/bin/env bash
# tests/run_all_tests.sh
# @version 1.0.0
# @description Runs all unit tests and collects results
# @author Jo
# @changed 2026-01-12

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Load configuration
PROFILE="${1:-system}"
PROFILE_FILE="${PROJECT_ROOT}/config/profiles/${PROFILE}.env"

if [ ! -f "${PROFILE_FILE}" ]; then
  echo "[ERROR] Profile not found: ${PROFILE}"
  exit 1
fi

source "${PROJECT_ROOT}/config/common.env"
source "${PROFILE_FILE}"

# Create test log directory
TEST_LOG_DIR="${LOCAL_LOG_DIR}/tests"
mkdir -p "${TEST_LOG_DIR}"

MASTER_LOG="${TEST_LOG_DIR}/test_run_$(date +%F_%H%M%S).log"

echo "==============================================================================="
echo "  BACKUP SYSTEM TEST SUITE v${BACKUP_SYSTEM_VERSION}"
echo "==============================================================================="
echo "Profile: ${PROFILE}"
echo "Started: $(date -Iseconds)"
echo "Log: ${MASTER_LOG}"
echo "==============================================================================="
echo "" | tee "${MASTER_LOG}"

# Find all test files
test_files=()
while IFS= read -r -d '' file; do
  test_files+=("$file")
done < <(find "${SCRIPT_DIR}" -name "*.test.sh" -type f -print0 | sort -z)

if [ ${#test_files[@]} -eq 0 ]; then
  echo "[WARN] No test files found" | tee -a "${MASTER_LOG}"
  exit 0
fi

# Run tests
passed=0
failed=0
skipped=0

for test_file in "${test_files[@]}"; do
  test_name=$(basename "${test_file}" .test.sh)
  echo "Running: ${test_name}..." | tee -a "${MASTER_LOG}"
  
  if bash "${test_file}" >> "${MASTER_LOG}" 2>&1; then
    echo "  [PASS] ${test_name}" | tee -a "${MASTER_LOG}"
    ((passed++))
  else
    echo "  [FAIL] ${test_name}" | tee -a "${MASTER_LOG}"
    ((failed++))
  fi
  echo "" | tee -a "${MASTER_LOG}"
done

# Summary
echo "===============================================================================" | tee -a "${MASTER_LOG}"
echo "  TEST SUMMARY" | tee -a "${MASTER_LOG}"
echo "===============================================================================" | tee -a "${MASTER_LOG}"
echo "Total: $((passed + failed))" | tee -a "${MASTER_LOG}"
echo "Passed: ${passed}" | tee -a "${MASTER_LOG}"
echo "Failed: ${failed}" | tee -a "${MASTER_LOG}"
echo "===============================================================================" | tee -a "${MASTER_LOG}"

if [ ${failed} -gt 0 ]; then
  exit 1
fi

exit 0
