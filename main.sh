#!/usr/bin/env bash
# main.sh
# @version 2.4.0
# @description Main orchestrator for profile-based backup system with POST_BACKUP_SEGMENTS support
# @author Jo Zapf
# @changed 2026-01-17 - Version bump for recovery key export POST_BACKUP migration
# @usage ./main.sh [profile_name]
# @example ./main.sh system

set -euo pipefail

# ============================================================================
# Configuration Loading
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEGMENTS_DIR="${SCRIPT_DIR}/segments"
CONFIG_DIR="${SCRIPT_DIR}/config"

# Get profile from command line argument (default: system)
PROFILE="${1:-system}"
PROFILE_FILE="${CONFIG_DIR}/profiles/${PROFILE}.env"

# Validate profile exists
if [ ! -f "${PROFILE_FILE}" ]; then
  echo "[ERROR] Profile not found: ${PROFILE}"
  echo "[ERROR] File does not exist: ${PROFILE_FILE}"
  echo ""
  echo "Available profiles:"
  ls -1 "${CONFIG_DIR}/profiles"/*.env 2>/dev/null | xargs -n1 basename | sed 's/.env$//' || echo "  (none)"
  exit 1
fi

# Load common configuration
if [ ! -f "${CONFIG_DIR}/common.env" ]; then
  echo "[ERROR] Common configuration not found: ${CONFIG_DIR}/common.env"
  exit 1
fi

source "${CONFIG_DIR}/common.env"

# Load profile configuration
source "${PROFILE_FILE}"

# Export all variables for segments
set -a
source "${CONFIG_DIR}/common.env"
source "${PROFILE_FILE}"
set +a

# ============================================================================
# Segment Definitions
# ============================================================================

# Pre-backup segments (profile-specific, executed before main segments)
# Can be overridden in profile config
PRE_BACKUP_SEGMENTS=(${PRE_BACKUP_SEGMENTS[@]:-})

# Main backup segments - Part 1 (up to and including backup creation)
MAIN_SEGMENTS_PART1=(
  "01_validate_config.sh"
  "02_init_logging.sh"
  "03_shelly_power_on.sh"
  "04_wait_device.sh"
  "05_mount_backup.sh"
  "06_validate_mount.sh"
  "07_init_borg_repo.sh"
  "08_borg_backup.sh"
)

# Post-backup segments (profile-specific, executed after backup but before verify)
# Use this for time-critical cleanup like restarting containers
# Can be overridden in profile config
POST_BACKUP_SEGMENTS=(${POST_BACKUP_SEGMENTS[@]:-})

# Main backup segments - Part 2 (verify and prune - can run while services are back online)
MAIN_SEGMENTS_PART2=(
  "09_borg_verify.sh"
  "10_borg_prune.sh"
)

# Cleanup segments (executed on EXIT, even if main fails)
CLEANUP_SEGMENTS=(
  "11_hdd_spindown.sh"
  "12_unmount_backup.sh"
  "13_shelly_power_off.sh"
)

# Post-cleanup segments (profile-specific, executed after cleanup)
# Use this for final notifications or logging
# Can be overridden in profile config
POST_CLEANUP_SEGMENTS=(${POST_CLEANUP_SEGMENTS[@]:-})

# ============================================================================
# Cleanup Handler
# ============================================================================

cleanup() {
  local exit_code=$?
  
  set +e  # Don't exit on errors during cleanup
  
  echo ""
  echo "==============================================================================="
  echo "  CLEANUP"
  echo "==============================================================================="
  
  for segment in "${CLEANUP_SEGMENTS[@]}"; do
    echo ""
    if [ -x "${SEGMENTS_DIR}/${segment}" ]; then
      "${SEGMENTS_DIR}/${segment}" || echo "[WARN] Cleanup segment ${segment} failed (continuing)"
    else
      echo "[WARN] Cleanup segment not found or not executable: ${segment}"
    fi
  done
  
  # Execute post-cleanup segments (profile-specific)
  if [ ${#POST_CLEANUP_SEGMENTS[@]} -gt 0 ]; then
    echo ""
    echo "==============================================================================="
    echo "  POST-CLEANUP (Profile-Specific)"
    echo "==============================================================================="
    
    for segment in "${POST_CLEANUP_SEGMENTS[@]}"; do
      echo ""
      if [ -x "${SEGMENTS_DIR}/${segment}" ]; then
        "${SEGMENTS_DIR}/${segment}" || echo "[WARN] Post-cleanup segment ${segment} failed (continuing)"
      else
        echo "[WARN] Post-cleanup segment not found or not executable: ${segment}"
      fi
    done
  fi
  
  echo ""
  echo "==============================================================================="
  if [ ${exit_code} -eq 0 ]; then
    echo "  BACKUP COMPLETED SUCCESSFULLY"
  else
    echo "  BACKUP FAILED (exit code: ${exit_code})"
  fi
  echo "==============================================================================="
  echo "Finished: $(date -Iseconds)"
  echo "==============================================================================="
  
  exit ${exit_code}
}

trap cleanup EXIT

# ============================================================================
# Main Execution
# ============================================================================

echo "==============================================================================="
echo "  BACKUP SYSTEM v${BACKUP_SYSTEM_VERSION}"
echo "==============================================================================="
echo "Profile: ${PROFILE}"
echo "Started: $(date -Iseconds)"
echo "==============================================================================="
echo ""

# Execute pre-backup segments (profile-specific)
if [ ${#PRE_BACKUP_SEGMENTS[@]} -gt 0 ]; then
  echo "==============================================================================="
  echo "  PRE-BACKUP (Profile-Specific)"
  echo "==============================================================================="
  
  for segment in "${PRE_BACKUP_SEGMENTS[@]}"; do
    echo ""
    if [ ! -x "${SEGMENTS_DIR}/${segment}" ]; then
      echo "[ERROR] Pre-backup segment not found or not executable: ${segment}"
      exit 1
    fi
    
    if ! "${SEGMENTS_DIR}/${segment}"; then
      echo ""
      echo "[ERROR] Pre-backup segment failed: ${segment}"
      echo "[ERROR] Aborting backup process"
      exit 1
    fi
  done
  
  echo ""
  echo "==============================================================================="
  echo "  PRE-BACKUP COMPLETED"
  echo "==============================================================================="
  echo ""
fi

# Execute main segments - Part 1 (up to backup creation)
for segment in "${MAIN_SEGMENTS_PART1[@]}"; do
  echo ""
  if [ ! -x "${SEGMENTS_DIR}/${segment}" ]; then
    echo "[ERROR] Segment not found or not executable: ${segment}"
    exit 1
  fi
  
  if ! "${SEGMENTS_DIR}/${segment}"; then
    echo ""
    echo "[ERROR] Segment failed: ${segment}"
    echo "[ERROR] Aborting backup process"
    exit 1
  fi
done

echo ""
echo "==============================================================================="
echo "  BACKUP CREATED - EXECUTING POST-BACKUP CLEANUP"
echo "==============================================================================="
echo ""

# Execute post-backup segments (profile-specific, after backup but before verify)
if [ ${#POST_BACKUP_SEGMENTS[@]} -gt 0 ]; then
  echo "==============================================================================="
  echo "  POST-BACKUP (Profile-Specific)"
  echo "==============================================================================="
  
  for segment in "${POST_BACKUP_SEGMENTS[@]}"; do
    echo ""
    if [ ! -x "${SEGMENTS_DIR}/${segment}" ]; then
      echo "[WARN] Post-backup segment not found or not executable: ${segment}"
      echo "[WARN] Continuing with verification..."
    else
      if ! "${SEGMENTS_DIR}/${segment}"; then
        echo ""
        echo "[WARN] Post-backup segment failed: ${segment}"
        echo "[WARN] Continuing with verification..."
      fi
    fi
  done
  
  echo ""
  echo "==============================================================================="
  echo "  POST-BACKUP COMPLETED - SERVICES SHOULD BE ONLINE"
  echo "==============================================================================="
  echo ""
fi

# Execute main segments - Part 2 (verify and prune)
echo "==============================================================================="
echo "  VERIFICATION AND PRUNING"
echo "==============================================================================="

for segment in "${MAIN_SEGMENTS_PART2[@]}"; do
  echo ""
  if [ ! -x "${SEGMENTS_DIR}/${segment}" ]; then
    echo "[ERROR] Segment not found or not executable: ${segment}"
    exit 1
  fi
  
  if ! "${SEGMENTS_DIR}/${segment}"; then
    echo ""
    echo "[ERROR] Segment failed: ${segment}"
    echo "[ERROR] Aborting backup process"
    exit 1
  fi
done

echo ""
echo "==============================================================================="
echo "  ALL MAIN SEGMENTS COMPLETED"
echo "==============================================================================="

# Exit with success (cleanup will run automatically via trap)
exit 0
