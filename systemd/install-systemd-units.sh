#!/usr/bin/env bash
# systemd/install-systemd-units.sh
# @version 1.0.0
# @description Installs systemd units for backup system
# @author Jo
# @changed 2026-01-12
# @requires root privileges

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] This script must be run as root"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="/etc/systemd/system"

echo "==============================================================================="
echo "  Installing systemd units for Backup System"
echo "==============================================================================="
echo ""

# Install mount units
echo "[1/4] Installing mount units..."
cp "${SCRIPT_DIR}/mnt-extern_backup.mount" "${SYSTEMD_DIR}/"
cp "${SCRIPT_DIR}/mnt-extern_backup.automount" "${SYSTEMD_DIR}/"
echo "  ✓ mnt-extern_backup.mount"
echo "  ✓ mnt-extern_backup.automount"

# Install backup service and timer
echo ""
echo "[2/4] Installing backup service and timer..."
cp "${SCRIPT_DIR}/backup-system@.service" "${SYSTEMD_DIR}/"
cp "${SCRIPT_DIR}/backup-system-weekly.timer" "${SYSTEMD_DIR}/"
echo "  ✓ backup-system@.service"
echo "  ✓ backup-system-weekly.timer"

# Reload systemd
echo ""
echo "[3/4] Reloading systemd daemon..."
systemctl daemon-reload
echo "  ✓ Daemon reloaded"

# Enable units (don't start yet - user should review first)
echo ""
echo "[4/4] Enabling units..."
systemctl enable mnt-extern_backup.automount
systemctl enable backup-system-weekly.timer
echo "  ✓ Automount enabled"
echo "  ✓ Weekly timer enabled"

echo ""
echo "==============================================================================="
echo "  Installation Complete"
echo "==============================================================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Review and adjust timer schedule if needed:"
echo "   sudo systemctl edit backup-system-weekly.timer"
echo ""
echo "2. Test manual backup:"
echo "   sudo systemctl start backup-system@system.service"
echo ""
echo "3. Start automount (optional - will start automatically on next boot):"
echo "   sudo systemctl start mnt-extern_backup.automount"
echo ""
echo "4. Check timer status:"
echo "   systemctl list-timers backup-system-weekly.timer"
echo ""
echo "5. View logs:"
echo "   journalctl -u backup-system@system.service"
echo ""
echo "==============================================================================="
