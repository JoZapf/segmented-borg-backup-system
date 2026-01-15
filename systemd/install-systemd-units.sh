#!/usr/bin/env bash
# systemd/install-systemd-units.sh
# @version 1.2.0
# @description Installs systemd timer units for backup system
# @author Jo
# @changed 2026-01-15 - Removed mount units (now handled by fstab)
# @requires root privileges
# @note Mount configuration should be in /etc/fstab with x-systemd.automount option

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

# Install backup service and timers
echo "[1/3] Installing backup service and timers..."
cp "${SCRIPT_DIR}/backup-system@.service" "${SYSTEMD_DIR}/"
cp "${SCRIPT_DIR}/backup-system-weekly.timer" "${SYSTEMD_DIR}/"
cp "${SCRIPT_DIR}/backup-system-dev-data-daily.timer" "${SYSTEMD_DIR}/"
echo "  ✓ backup-system@.service"
echo "  ✓ backup-system-weekly.timer (system profile)"
echo "  ✓ backup-system-dev-data-daily.timer (dev-data profile)"

# Reload systemd
echo ""
echo "[2/3] Reloading systemd daemon..."
systemctl daemon-reload
echo "  ✓ Daemon reloaded"

# Enable units (don't start yet - user should review first)
echo ""
echo "[3/3] Enabling units..."
systemctl enable backup-system-weekly.timer
systemctl enable backup-system-dev-data-daily.timer
echo "  ✓ Weekly timer enabled (system)"
echo "  ✓ Daily timer enabled (dev-data)"

echo ""
echo "==============================================================================="
echo "  Installation Complete"
echo "==============================================================================="
echo ""
echo "IMPORTANT: Mount configuration"
echo ""
echo "Backup mounts should be configured in /etc/fstab with automount option."
echo "Example fstab entry for external backup HDD:"
echo ""
echo "  # External Backup HDD (via Shelly Plug)"
echo "  UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX  /mnt/extern_backup  ext4  \\"
echo "    defaults,nofail,acl,x-systemd.automount,\\"
echo "    x-systemd.device-timeout=30,x-systemd.idle-timeout=300  0  2"
echo ""
echo "This automatically creates systemd mount and automount units."
echo ""
echo "==============================================================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Configure /etc/fstab entries for backup devices"
echo ""
echo "2. Review and adjust timer schedules if needed:"
echo "   sudo systemctl edit backup-system-weekly.timer"
echo "   sudo systemctl edit backup-system-dev-data-daily.timer"
echo ""
echo "3. Test manual backups:"
echo "   sudo systemctl start backup-system@system.service"
echo "   sudo systemctl start backup-system@dev-data.service"
echo ""
echo "4. Check timer status:"
echo "   systemctl list-timers"
echo ""
echo "5. View logs:"
echo "   journalctl -u backup-system@system.service"
echo "   journalctl -u backup-system@dev-data.service"
echo ""
echo "==============================================================================="
