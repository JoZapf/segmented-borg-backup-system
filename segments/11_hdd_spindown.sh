#!/usr/bin/env bash
# segments/11_hdd_spindown.sh
# @version 1.0.0
# @description Parks HDD read/write heads and spins down drive before power-off
# @author Jo Zapf
# @changed 2026-01-12
# @requires HDD_SPINDOWN_ENABLED, HDD_DEVICE

set -euo pipefail

echo "[11] Checking HDD spindown..."

# Skip if spindown is disabled
if [ "${HDD_SPINDOWN_ENABLED:-false}" != "true" ]; then
  echo "[11] HDD spindown disabled - skipping"
  exit 0
fi

# Validate HDD device
if [ -z "${HDD_DEVICE:-}" ]; then
  echo "[WARN] HDD_DEVICE not configured - skipping spindown"
  exit 0
fi

if [ ! -b "${HDD_DEVICE}" ]; then
  echo "[WARN] Device not found: ${HDD_DEVICE} - skipping spindown"
  exit 0
fi

echo "[11] Spinning down HDD: ${HDD_DEVICE}"

# Method 1: hdparm (preferred - direct hardware control)
if command -v hdparm >/dev/null 2>&1; then
  echo "[11] Using hdparm for spindown..."
  
  # Standby mode (parks heads, low power)
  if hdparm -y "${HDD_DEVICE}"; then
    echo "[11] HDD set to standby mode (heads parked)"
    sleep 3
    
    # Sleep mode (complete spindown)
    if hdparm -Y "${HDD_DEVICE}"; then
      echo "[11] HDD spun down completely"
    else
      echo "[WARN] Sleep command failed, but standby succeeded"
    fi
    
    exit 0
  else
    echo "[WARN] hdparm standby command failed"
  fi
fi

# Method 2: udisks2 (fallback)
if command -v udisksctl >/dev/null 2>&1; then
  echo "[11] Using udisksctl for power-off..."
  
  if udisksctl power-off -b "${HDD_DEVICE}"; then
    echo "[11] HDD powered off via udisksctl"
    exit 0
  else
    echo "[WARN] udisksctl power-off failed"
  fi
fi

# If we get here, no method worked
echo "[WARN] HDD spindown failed - no working method available"
echo "[WARN] Continuing anyway (Shelly auto-off will still protect drive)"
exit 0
