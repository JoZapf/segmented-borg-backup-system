#!/usr/bin/env bash
# segments/13_shelly_power_off.sh
# @version 1.0.0
# @description Powers off external HDD via Shelly Plug Plus
# @author Jo Zapf
# @changed 2026-01-12
# @requires SHELLY_ENABLED, SHELLY_IP

set -euo pipefail

echo "[13] Checking Shelly power control..."

# Skip if Shelly control is disabled
if [ "${SHELLY_ENABLED:-false}" != "true" ]; then
  echo "[13] Shelly power control disabled - skipping"
  exit 0
fi

echo "[13] Powering off Shelly Plug at ${SHELLY_IP}..."

# Wait a moment to ensure HDD is fully spun down
sleep 2

# Send power-off command
if curl -fSs --retry 5 --retry-delay 1 \
  "http://${SHELLY_IP}/rpc/Switch.Set?id=0&on=false" \
  >/dev/null 2>&1; then
  echo "[13] Shelly powered OFF"
else
  echo "[WARN] Failed to power off Shelly Plug"
  echo "[WARN] HDD may remain powered on"
  echo "[WARN] Manual power-off may be required"
  # Don't fail the script - backup was successful
  exit 0
fi

echo "[13] Shelly power-off complete"
