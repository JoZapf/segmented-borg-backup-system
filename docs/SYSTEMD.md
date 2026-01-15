# Systemd Integration Guide

## Overview

This backup system integrates with systemd for automated scheduling and mount management.

## Components

### 1. Systemd Timers

Located in `/systemd/`:
- `backup-system@.service` - Template service for running backups
- `backup-system-weekly.timer` - Weekly system backup (Sunday 02:00)
- `backup-system-dev-data-daily.timer` - Daily Docker/Nextcloud backup (00:00)

### 2. Mount Configuration

**IMPORTANT:** Mounts are configured in `/etc/fstab`, NOT as separate systemd units.

## Installation

### 1. Install Timer Units

```bash
cd /opt/backup-system/systemd
sudo ./install-systemd-units.sh
```

### 2. Configure Mount in fstab

Edit `/etc/fstab` and add entries for your backup devices:

#### Example: External Backup HDD (via Shelly Plug)

```fstab
# External Backup HDD (Shelly-controlled, automount on access)
UUID=f2c4624a-72ee-5e4b-85f8-a0d7f02e702f  /mnt/extern_backup  ext4  \
  defaults,nofail,acl,x-systemd.automount,\
  x-systemd.device-timeout=30,x-systemd.idle-timeout=300  0  2
```

#### Example: Internal Backup HDD (always powered)

```fstab
# Internal Backup HDD (automount on access)
UUID=9d5bdf3a-ede2-472e-a463-741836755d1b  /mnt/system_backup  ext4  \
  defaults,nofail,acl,x-systemd.automount,\
  x-systemd.device-timeout=30,x-systemd.idle-timeout=300  0  2
```

### 3. Apply Changes

```bash
# Reload systemd to recognize fstab changes
sudo systemctl daemon-reload

# Verify automount units were created
systemctl list-unit-files | grep "mnt-.*\.automount"

# Expected output:
# mnt-extern_backup.automount    generated  enabled
# mnt-system_backup.automount    generated  enabled
```

## Mount Configuration Options

### fstab Options Explained

- `defaults` - Standard mount options (rw, suid, dev, exec, auto, nouser, async)
- `nofail` - Boot continues even if device is not present
- `acl` - Enable POSIX Access Control Lists
- `x-systemd.automount` - Create systemd automount unit
- `x-systemd.device-timeout=30` - Wait max 30s for device
- `x-systemd.idle-timeout=300` - Unmount after 300s idle (optional)

### Why fstab Instead of Systemd Units?

**Advantages:**
1. **Single source of truth** - One configuration file
2. **Automatic systemd integration** - `x-systemd.automount` generates mount units
3. **Standard approach** - Works with all Linux tools
4. **Less maintenance** - No duplicate configurations

**What NOT to do:**
- ❌ Don't create manual `/etc/systemd/system/mnt-*.mount` files
- ❌ Don't mix fstab and systemd units for the same mount
- ❌ Don't use explicit `mount` commands in segments

## Timer Management

### List Active Timers

```bash
systemctl list-timers | grep backup-system
```

Example output:
```
NEXT                        LEFT       UNIT
Fri 2026-01-16 00:00:00 CET 13h left  backup-system-dev-data-daily.timer
Sun 2026-01-19 02:00:00 CET 4d left   backup-system-weekly.timer
```

### Enable/Disable Timers

```bash
# Enable
sudo systemctl enable backup-system-dev-data-daily.timer
sudo systemctl start backup-system-dev-data-daily.timer

# Disable
sudo systemctl stop backup-system-dev-data-daily.timer
sudo systemctl disable backup-system-dev-data-daily.timer
```

### Customize Timer Schedule

```bash
# Edit timer
sudo systemctl edit backup-system-dev-data-daily.timer
```

Add override:
```ini
[Timer]
OnCalendar=
OnCalendar=*-*-* 02:00:00
```

## Manual Backup Execution

```bash
# Run backup for specific profile
sudo systemctl start backup-system@system.service
sudo systemctl start backup-system@dev-data.service

# Monitor execution
journalctl -u backup-system@system.service -f
```

## Troubleshooting

### Check Timer Status

```bash
systemctl status backup-system-dev-data-daily.timer
```

### Check Last Backup Execution

```bash
journalctl -u backup-system@dev-data.service --since today
```

### Verify Mount Configuration

```bash
# Check if automount units exist
systemctl list-unit-files | grep automount

# Check mount status
findmnt /mnt/extern_backup
findmnt /mnt/system_backup

# Test automount trigger
ls /mnt/extern_backup
findmnt /mnt/extern_backup  # Should show mounted
```

### Common Issues

#### Mount Not Working

**Problem:** Device not mounting automatically

**Solution:**
1. Check fstab syntax: `sudo mount -a`
2. Verify UUID: `sudo blkid`
3. Check systemd: `sudo systemctl daemon-reload`
4. View logs: `journalctl -xe`

#### Wrong Device Mounted

**Problem:** Segment 06 reports UUID mismatch

**Cause:** Multiple mount configurations (fstab + systemd units)

**Solution:**
1. Remove manual systemd units:
   ```bash
   sudo systemctl stop mnt-extern_backup.automount
   sudo systemctl disable mnt-extern_backup.automount
   sudo rm /etc/systemd/system/mnt-extern_backup.*
   sudo systemctl daemon-reload
   ```
2. Keep only fstab entry with `x-systemd.automount`

#### Timer Not Triggering

**Problem:** Backup doesn't run at scheduled time

**Solution:**
1. Check timer is enabled: `systemctl is-enabled backup-system-dev-data-daily.timer`
2. Check next trigger: `systemctl list-timers`
3. View timer logs: `journalctl -u backup-system-dev-data-daily.timer`

## Migration from Old Configuration

If you have existing `/etc/systemd/system/mnt-*.mount` files:

```bash
# 1. Stop and disable old units
sudo systemctl stop mnt-extern_backup.automount
sudo systemctl disable mnt-extern_backup.automount

# 2. Remove old files
sudo rm /etc/systemd/system/mnt-extern_backup.mount
sudo rm /etc/systemd/system/mnt-extern_backup.automount

# 3. Ensure fstab entry has x-systemd.automount
sudo nano /etc/fstab

# 4. Reload
sudo systemctl daemon-reload

# 5. Test
ls /mnt/extern_backup
findmnt /mnt/extern_backup
```

## Security Considerations

### Service Hardening

The backup service runs with security hardening:
- `NoNewPrivileges=false` - Required for borg
- `PrivateTmp=true` - Isolated /tmp
- `ProtectSystem=strict` - Read-only /usr, /boot
- `ProtectHome=false` - Access to home (for docker data)

### Resource Limits

- `CPUQuota=80%` - Max 80% CPU usage
- `MemoryMax=2G` - Max 2GB RAM

### Logging

All output goes to:
1. Local log: `/var/log/extern_backup/{profile}_{timestamp}.log`
2. Systemd journal: `journalctl -u backup-system@{profile}.service`
3. Backup log: `{TARGET_DIR}/logs/{profile}_{timestamp}.log`

## See Also

- [Main README](../README.md)
- [Docker/Nextcloud Integration](DOCKER_NEXTCLOUD.md)
- [Segment Documentation](../segments/)
