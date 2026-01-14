#!/usr/bin/env bash
# segments/pre_02_docker_stop.sh
# @version 1.0.0
# @description Stops Docker containers and saves running container IDs
# @author Jo Zapf
# @changed 2026-01-13
# @requires DOCKER_ENABLED

set -euo pipefail

echo "[PRE-02] Checking Docker containers..."

# Skip if Docker control is disabled
if [ "${DOCKER_ENABLED:-false}" != "true" ]; then
  echo "[PRE-02] Docker container management disabled - skipping"
  exit 0
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

# Create state directory for storing running container IDs
STATE_DIR="${STATE_DIR:-/tmp/backup-system-state}"
mkdir -p "${STATE_DIR}"
CONTAINER_IDS_FILE="${STATE_DIR}/running_containers.txt"

# Get list of currently running containers
echo "[PRE-02] Detecting running containers..."
running_containers=$(docker ps --format '{{.ID}} {{.Names}}' 2>/dev/null || true)

if [ -z "${running_containers}" ]; then
  echo "[PRE-02] No running containers found"
  echo "" > "${CONTAINER_IDS_FILE}"
  exit 0
fi

# Count containers
container_count=$(echo "${running_containers}" | wc -l)
echo "[PRE-02] Found ${container_count} running containers"

# Save container IDs to file
echo "${running_containers}" | awk '{print $1}' > "${CONTAINER_IDS_FILE}"

# Display containers to be stopped
echo "[PRE-02] Containers to be stopped:"
while IFS= read -r line; do
  container_id=$(echo "${line}" | awk '{print $1}')
  container_name=$(echo "${line}" | awk '{print $2}')
  echo "[PRE-02]   - ${container_name} (${container_id})"
done <<< "${running_containers}"

# Optional: Graceful shutdown with timeout
DOCKER_STOP_TIMEOUT="${DOCKER_STOP_TIMEOUT:-30}"
echo ""
echo "[PRE-02] Stopping containers (timeout: ${DOCKER_STOP_TIMEOUT}s)..."

# Stop containers one by one with progress
stopped=0
failed=0

set +eo pipefail  # Disable errexit AND pipefail for while loop

while IFS= read -r line; do
  container_id=$(echo "${line}" | awk '{print $1}')
  container_name=$(echo "${line}" | awk '{print $2}')
  
  echo -n "[PRE-02] Stopping ${container_name}... "
  
  if docker stop --time="${DOCKER_STOP_TIMEOUT}" "${container_id}" >/dev/null 2>&1; then
    echo "OK"
    ((stopped++))
  else
    echo "FAILED"
    ((failed++))
  fi
done <<< "${running_containers}"

set -eo pipefail  # Re-enable errexit AND pipefail

echo ""
echo "[PRE-02] Container stop summary:"
echo "[PRE-02]   Stopped: ${stopped}"
echo "[PRE-02]   Failed: ${failed}"

if [ ${failed} -gt 0 ]; then
  echo "[WARN] Some containers failed to stop gracefully"
  echo "[WARN] Backup will proceed, but data consistency may be affected"
fi

# Verify all containers are stopped
echo "[PRE-02] Verifying container states..."
still_running=$(docker ps -q | wc -l)

if [ ${still_running} -gt 0 ]; then
  echo "[WARN] ${still_running} containers are still running"
  docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'
else
  echo "[PRE-02] All containers stopped successfully"
fi

# Save timestamp
echo "$(date -Iseconds)" > "${STATE_DIR}/docker_stop_timestamp.txt"

echo "[PRE-02] Container IDs saved to: ${CONTAINER_IDS_FILE}"
echo "[PRE-02] Docker containers stopped"
