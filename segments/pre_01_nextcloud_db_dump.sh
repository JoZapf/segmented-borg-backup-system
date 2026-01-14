#!/usr/bin/env bash
# segments/pre_01_nextcloud_db_dump.sh
# @version 2.0.0
# @description Dumps Nextcloud database using Docker exec (container-based approach)
# @author Jo Zapf
# @changed 2026-01-13 - Rewritten to use Docker exec method with maintenance mode
# @requires NEXTCLOUD_ENABLED, NEXTCLOUD_DOCKER_*, TARGET_DIR

set -euo pipefail

echo "[PRE-01] Checking Nextcloud database dump..."

# Skip if Nextcloud dump is disabled
if [ "${NEXTCLOUD_ENABLED:-false}" != "true" ]; then
  echo "[PRE-01] Nextcloud DB dump disabled - skipping"
  exit 0
fi

# Validate required variables for Docker-based approach
required_vars=(
  "NEXTCLOUD_DOCKER_APP_CONTAINER"
  "NEXTCLOUD_DOCKER_DB_CONTAINER"
  "NEXTCLOUD_DB_NAME"
  "NEXTCLOUD_DB_USER"
  "NEXTCLOUD_DB_PASSWORD"
  "TARGET_DIR"
)

missing_vars=()
for var in "${required_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    missing_vars+=("${var}")
  fi
done

if [ ${#missing_vars[@]} -gt 0 ]; then
  echo "[ERROR] Missing required Nextcloud variables: ${missing_vars[*]}"
  exit 1
fi

# Check if docker is available
if ! command -v docker >/dev/null 2>&1; then
  echo "[ERROR] Docker command not found"
  exit 1
fi

# Check if docker daemon is running
if ! docker info >/dev/null 2>&1; then
  echo "[ERROR] Docker daemon is not running"
  exit 1
fi

# Verify containers exist and are running
for container in "${NEXTCLOUD_DOCKER_APP_CONTAINER}" "${NEXTCLOUD_DOCKER_DB_CONTAINER}"; do
  if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
    echo "[ERROR] Container not running: ${container}"
    echo "[ERROR] Running containers:"
    docker ps --format 'table {{.Names}}\t{{.Status}}'
    exit 1
  fi
done

echo "[PRE-01] Nextcloud App Container: ${NEXTCLOUD_DOCKER_APP_CONTAINER}"
echo "[PRE-01] Nextcloud DB Container: ${NEXTCLOUD_DOCKER_DB_CONTAINER}"
echo "[PRE-01] Database: ${NEXTCLOUD_DB_NAME}"

# Create database dumps directory
DB_DUMP_DIR="${TARGET_DIR}/database-dumps"
mkdir -p "${DB_DUMP_DIR}"

# Generate dump filename with timestamp
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
DUMP_FILENAME="nextcloud_db-dump_${TIMESTAMP}.sql"
CONTAINER_DUMP_PATH="/tmp/${DUMP_FILENAME}"
HOST_DUMP_PATH="${DB_DUMP_DIR}/${DUMP_FILENAME}"

echo "[PRE-01] Dump file: ${DUMP_FILENAME}"
echo ""

# ============================================================================
# STEP 1: Enable Nextcloud Maintenance Mode
# ============================================================================
echo "[PRE-01] Step 1: Enabling Nextcloud maintenance mode..."

if docker exec -u www-data "${NEXTCLOUD_DOCKER_APP_CONTAINER}" \
  php occ maintenance:mode --on 2>&1 | tee /tmp/nc_maintenance_on.log; then
  echo "[PRE-01] Maintenance mode enabled"
else
  echo "[ERROR] Failed to enable maintenance mode"
  cat /tmp/nc_maintenance_on.log
  exit 1
fi

# Function to disable maintenance mode (cleanup)
disable_maintenance_mode() {
  echo "[PRE-01] Disabling maintenance mode..."
  if docker exec -u www-data "${NEXTCLOUD_DOCKER_APP_CONTAINER}" \
    php occ maintenance:mode --off >/dev/null 2>&1; then
    echo "[PRE-01] Maintenance mode disabled"
  else
    echo "[WARN] Failed to disable maintenance mode - manual intervention may be required"
    echo "[WARN] Run: docker exec -u www-data ${NEXTCLOUD_DOCKER_APP_CONTAINER} php occ maintenance:mode --off"
  fi
}

# Ensure maintenance mode is disabled on exit (even if script fails)
trap disable_maintenance_mode EXIT

# ============================================================================
# STEP 2: Create Database Dump inside Container
# ============================================================================
echo ""
echo "[PRE-01] Step 2: Creating database dump inside container..."

# Determine dump command based on database type
case "${NEXTCLOUD_DB_TYPE:-mariadb}" in
  "mysql"|"mariadb")
    DUMP_CMD="mariadb-dump -u ${NEXTCLOUD_DB_USER} -p'${NEXTCLOUD_DB_PASSWORD}' ${NEXTCLOUD_DB_NAME}"
    ;;
  "postgresql"|"postgres")
    DUMP_CMD="PGPASSWORD='${NEXTCLOUD_DB_PASSWORD}' pg_dump -U ${NEXTCLOUD_DB_USER} ${NEXTCLOUD_DB_NAME}"
    ;;
  *)
    echo "[ERROR] Unsupported database type: ${NEXTCLOUD_DB_TYPE}"
    exit 1
    ;;
esac

# Execute dump inside container
echo "[PRE-01] Executing: ${DUMP_CMD} > ${CONTAINER_DUMP_PATH}"

if docker exec "${NEXTCLOUD_DOCKER_DB_CONTAINER}" \
  sh -c "${DUMP_CMD} > ${CONTAINER_DUMP_PATH}" 2>/tmp/nc_dump_error.log; then
  echo "[PRE-01] Database dump created in container"
else
  echo "[ERROR] Database dump failed"
  cat /tmp/nc_dump_error.log
  exit 1
fi

# ============================================================================
# STEP 3: Copy Dump from Container to Host
# ============================================================================
echo ""
echo "[PRE-01] Step 3: Copying dump from container to host..."

if docker cp "${NEXTCLOUD_DOCKER_DB_CONTAINER}:${CONTAINER_DUMP_PATH}" "${HOST_DUMP_PATH}"; then
  echo "[PRE-01] Dump copied to: ${HOST_DUMP_PATH}"
else
  echo "[ERROR] Failed to copy dump from container"
  exit 1
fi

# Clean up dump in container
docker exec "${NEXTCLOUD_DOCKER_DB_CONTAINER}" rm -f "${CONTAINER_DUMP_PATH}" 2>/dev/null || true

# ============================================================================
# STEP 4: Verify Dump Integrity (Health Check)
# ============================================================================
echo ""
echo "[PRE-01] Step 4: Verifying dump integrity..."

# Check file exists and is not empty
if [ ! -s "${HOST_DUMP_PATH}" ]; then
  echo "[ERROR] Dump file is empty or does not exist"
  exit 1
fi

# Get dump size
dump_size=$(stat -c%s "${HOST_DUMP_PATH}" 2>/dev/null || stat -f%z "${HOST_DUMP_PATH}" 2>/dev/null)
dump_size_mb=$((dump_size / 1024 / 1024))
echo "[PRE-01] Dump size: ${dump_size_mb} MB"

# Health check: Verify dump header (first 20 lines)
echo "[PRE-01] Checking dump header..."
if head -n 20 "${HOST_DUMP_PATH}" | grep -q "MySQL dump\|MariaDB dump\|PostgreSQL database dump"; then
  echo "[PRE-01] Dump header: OK"
else
  echo "[WARN] Dump header does not contain expected markers"
fi

# Health check: Verify dump footer (last 20 lines)
echo "[PRE-01] Checking dump footer..."
if tail -n 20 "${HOST_DUMP_PATH}" | grep -q "Dump completed\|-- Dump completed"; then
  echo "[PRE-01] Dump footer: OK (completion marker found)"
else
  echo "[WARN] Dump may be incomplete (no completion marker)"
fi

# Check for SQL errors in dump
if grep -i "error" "${HOST_DUMP_PATH}" >/dev/null 2>&1; then
  echo "[WARN] Dump contains error messages"
  echo "[WARN] First error found:"
  grep -i "error" "${HOST_DUMP_PATH}" | head -3 | sed 's/^/[PRE-01]   /' || true
fi

# Detailed health check output
echo "[PRE-01] Health check - First 10 lines:"
head -n 10 "${HOST_DUMP_PATH}" | sed 's/^/[PRE-01]   /'
echo "[PRE-01] Health check - Last 10 lines:"
tail -n 10 "${HOST_DUMP_PATH}" | sed 's/^/[PRE-01]   /'

# ============================================================================
# STEP 5: Compress Dump
# ============================================================================
echo ""
echo "[PRE-01] Step 5: Compressing dump..."

if gzip -f "${HOST_DUMP_PATH}"; then
  COMPRESSED_PATH="${HOST_DUMP_PATH}.gz"
  
  compressed_size=$(stat -c%s "${COMPRESSED_PATH}" 2>/dev/null || stat -f%z "${COMPRESSED_PATH}" 2>/dev/null)
  compressed_size_mb=$((compressed_size / 1024 / 1024))
  compression_ratio=$((100 - (compressed_size * 100 / dump_size)))
  
  echo "[PRE-01] Compressed to: ${COMPRESSED_PATH}"
  echo "[PRE-01] Compressed size: ${compressed_size_mb} MB"
  echo "[PRE-01] Compression ratio: ${compression_ratio}%"
else
  echo "[WARN] Compression failed - keeping uncompressed dump"
  COMPRESSED_PATH="${HOST_DUMP_PATH}"
fi

# ============================================================================
# STEP 6: Cleanup Old Dumps
# ============================================================================
echo ""
echo "[PRE-01] Step 6: Cleaning up old dumps..."

# Keep last 7 dumps
old_dumps=$(ls -t "${DB_DUMP_DIR}"/nextcloud_db-dump_*.sql.gz 2>/dev/null | tail -n +8)
if [ -n "${old_dumps}" ]; then
  echo "${old_dumps}" | xargs rm -f
  removed_count=$(echo "${old_dumps}" | wc -l)
  echo "[PRE-01] Removed ${removed_count} old dump(s)"
else
  echo "[PRE-01] No old dumps to remove"
fi

# ============================================================================
# STEP 7: Summary
# ============================================================================
echo ""
echo "[PRE-01] ============================================================="
echo "[PRE-01] Nextcloud DB Dump Summary:"
echo "[PRE-01]   Database: ${NEXTCLOUD_DB_NAME}"
echo "[PRE-01]   Original size: ${dump_size_mb} MB"
echo "[PRE-01]   Compressed size: ${compressed_size_mb} MB"
echo "[PRE-01]   Compression: ${compression_ratio}%"
echo "[PRE-01]   Location: ${COMPRESSED_PATH}"
echo "[PRE-01] ============================================================="
echo "[PRE-01] Nextcloud DB dump completed successfully"

# Maintenance mode will be disabled by trap on EXIT
