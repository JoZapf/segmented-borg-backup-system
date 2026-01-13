#!/usr/bin/env bash
# segments/10_borg_prune.sh
# @version 1.0.0
# @description Prunes old archives according to retention policy and compacts repo
# @author Jo
# @changed 2026-01-12
# @requires REPO, retention policy variables

set -euo pipefail

echo "[10] Pruning old archives..."

# Set Borg environment variables
export BORG_PASSCOMMAND="cat ${BORG_PASSPHRASE_FILE}"
export BORG_LOCK_WAIT="${BORG_LOCK_WAIT}"

echo "[10] Retention policy:"
echo "[10]   Daily: ${KEEP_DAILY}"
echo "[10]   Weekly: ${KEEP_WEEKLY:-0}"
echo "[10]   Monthly: ${KEEP_MONTHLY:-0}"
echo ""

# Build prune command
prune_cmd=(
  borg prune
  --list
  --stats
  --keep-daily="${KEEP_DAILY}"
)

# Add weekly retention if set
if [ -n "${KEEP_WEEKLY:-}" ] && [ "${KEEP_WEEKLY}" -gt 0 ]; then
  prune_cmd+=(--keep-weekly="${KEEP_WEEKLY}")
fi

# Add monthly retention if set
if [ -n "${KEEP_MONTHLY:-}" ] && [ "${KEEP_MONTHLY}" -gt 0 ]; then
  prune_cmd+=(--keep-monthly="${KEEP_MONTHLY}")
fi

# Add repository
prune_cmd+=("${REPO}")

# Execute prune
echo "[10] Pruning archives..."
if "${prune_cmd[@]}"; then
  echo ""
  echo "[10] Prune completed successfully"
else
  echo ""
  echo "[ERROR] Prune failed"
  exit 1
fi

# Compact repository to reclaim space
echo ""
echo "[10] Compacting repository..."
if borg compact "${REPO}"; then
  echo "[10] Compact completed successfully"
  
  # Show final repository statistics
  echo ""
  echo "[10] Repository statistics:"
  borg info "${REPO}" | grep -E "(Original size|Compressed size|Deduplicated size)" || true
  
  exit 0
else
  echo "[ERROR] Compact failed"
  exit 1
fi
