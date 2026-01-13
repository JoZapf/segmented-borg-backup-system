#!/usr/bin/env bash
# segments/01_validate_config.sh
# @version 1.0.0
# @description Validates all required configuration variables and dependencies
# @author Jo
# @changed 2026-01-12
# @requires common.env, profile.env

set -euo pipefail

echo "[01] Validating configuration..."

# Check if required variables are set and non-empty
required_vars=(
  "BACKUP_PROFILE"
  "BACKUP_SOURCES"
  "BACKUP_UUID"
  "BACKUP_DEV"
  "BACKUP_MNT"
  "TARGET_DIR"
  "REPO"
  "BORG_PASSPHRASE_FILE"
  "LOCAL_LOG_DIR"
)

missing_vars=()
for var in "${required_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    missing_vars+=("${var}")
  fi
done

if [ ${#missing_vars[@]} -gt 0 ]; then
  echo "[ERROR] Missing required variables: ${missing_vars[*]}"
  exit 1
fi

# Validate Borg passphrase file exists and is readable
if [ ! -f "${BORG_PASSPHRASE_FILE}" ]; then
  echo "[ERROR] Borg passphrase file not found: ${BORG_PASSPHRASE_FILE}"
  exit 1
fi

if [ ! -r "${BORG_PASSPHRASE_FILE}" ]; then
  echo "[ERROR] Borg passphrase file not readable: ${BORG_PASSPHRASE_FILE}"
  exit 1
fi

if [ ! -s "${BORG_PASSPHRASE_FILE}" ]; then
  echo "[ERROR] Borg passphrase file is empty: ${BORG_PASSPHRASE_FILE}"
  exit 1
fi

# Check required commands
required_commands=("borg" "curl" "findmnt" "lsof")
missing_commands=()
for cmd in "${required_commands[@]}"; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    missing_commands+=("${cmd}")
  fi
done

if [ ${#missing_commands[@]} -gt 0 ]; then
  echo "[ERROR] Missing required commands: ${missing_commands[*]}"
  exit 1
fi

# Check hdparm if spindown is enabled
if [ "${HDD_SPINDOWN_ENABLED:-false}" = "true" ]; then
  if ! command -v hdparm >/dev/null 2>&1 && ! command -v udisksctl >/dev/null 2>&1; then
    echo "[ERROR] HDD spindown enabled but neither hdparm nor udisksctl available"
    exit 1
  fi
fi

echo "[01] Configuration valid"
echo "[01] Profile: ${BACKUP_PROFILE}"
echo "[01] Sources: ${BACKUP_SOURCES}"
echo "[01] Target: ${TARGET_DIR}"
echo "[01] Shelly: ${SHELLY_ENABLED:-false}"
echo "[01] HDD Spindown: ${HDD_SPINDOWN_ENABLED:-false}"
