#!/usr/bin/env bash
# segments/post_01_docker_start.sh
# @version 1.1.0
# @description Restarts Docker containers that were running before backup (runs in POST_BACKUP phase)
# @author Jo Zapf
# @changed 2026-01-14 - Now runs in POST_BACKUP phase (after backup, before verify) to minimize downtime
# @requires DOCKER_ENABLED

set -euo pipefail

echo "[POST-01] Checking Docker container restart..."
echo "[POST-01] Running in POST_BACKUP phase - containers restart BEFORE verify/prune"

# Skip if Docker control is disabled
if [ "${DOCKER_ENABLED:-false}" != "true" ]; then
  echo "[POST-01] Docker container management disabled - skipping"
  exit 0
fi

# Check if docker is available
if ! command -v docker >/dev/null 2>&1; then
  echo "[WARN] Docker command not found - cannot restart containers"
  return 0  # Don't fail backup if docker is missing
fi

# Check if docker daemon is running
if ! docker info >/dev/null 2>&1; then
  echo "[WARN] Docker daemon is not running - cannot restart containers"
  return 0
fi

# Get state directory
STATE_DIR="${STATE_DIR:-/tmp/backup-system-state}"
CONTAINER_IDS_FILE="${STATE_DIR}/running_containers.txt"

# Check if container IDs file exists
if [ ! -f "${CONTAINER_IDS_FILE}" ]; then
  echo "[POST-01] No container IDs file found - nothing to restart"
  return 0
fi

# Read container IDs
mapfile -t container_ids < "${CONTAINER_IDS_FILE}"

# Check if any containers to restart
if [ ${#container_ids[@]} -eq 0 ] || [ -z "${container_ids[0]}" ]; then
  echo "[POST-01] No containers to restart"
  return 0
fi

echo "[POST-01] Found ${#container_ids[@]} containers to restart"

# Start containers
started=0
failed=0
not_found=0

set +eo pipefail  # Disable errexit AND pipefail for while loop

for container_id in "${container_ids[@]}"; do
  # Skip empty lines
  if [ -z "${container_id}" ]; then
    continue
  fi
  
  # Get container name for logging
  container_name=$(docker ps -a --filter "id=${container_id}" --format '{{.Names}}' 2>/dev/null || echo "unknown")
  
  # Check if container exists
  if ! docker ps -a --filter "id=${container_id}" --format '{{.ID}}' | grep -q "${container_id}"; then
    echo "[WARN] Container ${container_id} (${container_name}) not found - may have been removed"
    ((not_found++))
    continue
  fi
  
  echo -n "[POST-01] Starting ${container_name} (${container_id})... "
  
  if docker start "${container_id}" >/dev/null 2>&1; then
    echo "OK"
    ((started++))
  else
    echo "FAILED"
    ((failed++))
    
    # Get container logs for debugging
    echo "[POST-01] Last 5 log lines:"
    docker logs --tail 5 "${container_id}" 2>&1 | sed 's/^/[POST-01]   /'
  fi
done

set -eo pipefail  # Re-enable errexit AND pipefail

echo ""
echo "[POST-01] Container start summary:"
echo "[POST-01]   Started: ${started}"
echo "[POST-01]   Failed: ${failed}"
echo "[POST-01]   Not found: ${not_found}"

# Verify containers are running
echo "[POST-01] Verifying container states..."
now_running=$(docker ps -q | wc -l)
echo "[POST-01] Currently running containers: ${now_running}"

if [ ${failed} -gt 0 ]; then
  echo "[WARN] Some containers failed to start"
  echo "[WARN] Manual intervention may be required"
  docker ps -a --filter "status=exited" --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'
fi

# Calculate downtime
if [ -f "${STATE_DIR}/docker_stop_timestamp.txt" ]; then
  stop_time=$(cat "${STATE_DIR}/docker_stop_timestamp.txt")
  start_time=$(date -Iseconds)
  
  # Simple duration calculation (seconds)
  stop_epoch=$(date -d "${stop_time}" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${stop_time}" +%s 2>/dev/null || echo "0")
  start_epoch=$(date -d "${start_time}" +%s 2>/dev/null || date +%s)
  
  if [ "${stop_epoch}" != "0" ]; then
    downtime=$((start_epoch - stop_epoch))
    downtime_min=$((downtime / 60))
    downtime_sec=$((downtime % 60))
    echo "[POST-01] ✅ Container downtime: ${downtime_min}m ${downtime_sec}s (verify/prune run with containers online!)"
  fi
fi

# Cleanup state files
rm -f "${CONTAINER_IDS_FILE}" "${STATE_DIR}/docker_stop_timestamp.txt"

echo "[POST-01] Docker container restart completed"
