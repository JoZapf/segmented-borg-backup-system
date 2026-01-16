#!/usr/bin/env bash
# segments/03_shelly_power_on.sh
# @version 1.1.0
# @description Powers on external HDD via Shelly Plug Plus with auto-off timer
# @author Jo Zapf
# @changed 2026-01-16 - Increased HDD spin-up wait time from 10s to 20s
# @requires SHELLY_ENABLED, SHELLY_IP, SHELLY_TOGGLE_AFTER_SEC

set -euo pipefail

echo "[03] Checking Shelly power control..."

# Skip if Shelly control is disabled
if [ "${SHELLY_ENABLED:-false}" != "true" ]; then
  echo "[03] Shelly power control disabled - skipping"
  exit 0
fi

echo "[03] Powering on Shelly Plug at ${SHELLY_IP}..."

# Send power-on command with auto-off timer
if curl -fSs --retry 5 --retry-delay 1 \
  "http://${SHELLY_IP}/rpc/Switch.Set?id=0&on=true&toggle_after=${SHELLY_TOGGLE_AFTER_SEC}" \
  >/dev/null 2>&1; then
  echo "[03] Shelly powered ON (auto-off after ${SHELLY_TOGGLE_AFTER_SEC}s)"
else
  echo "[ERROR] Failed to power on Shelly Plug"
  exit 1
fi

# Wait for HDD to spin up (increased from 10s to 20s for large HDDs)
echo "[03] Waiting 20s for HDD spin-up..."
sleep 20

echo "[03] Shelly power-on complete"
