# systemd Guide - Backup System v2.0.1

Complete guide for systemd integration, scheduling, and troubleshooting.

## systemd Units Overview

The backup system uses four systemd units:

1. **mnt-extern_backup.mount** - Mounts the backup device
2. **mnt-extern_backup.automount** - Automatic mount on access
3. **backup-system@.service** - Parametric service for backup profiles
4. **backup-system-weekly.timer** - Weekly schedule for system backup

---

## Mount Units

### mnt-extern_backup.mount

Handles the actual mounting of the backup device.

```ini
[Unit]
Description=External Backup Drive Mount
After=blockdev@dev-disk-by\x2duuid-f2c4624a\x2d72ee\x2d5e4b\x2d85f8\x2da0d7f02e702f.target

[Mount]
What=/dev/disk/by-uuid/f2c4624a-72ee-5e4b-85f8-a0d7f02e702f
Where=/mnt/extern_backup
Type=ext4
Options=defaults,noatime

[Install]
WantedBy=multi-user.target
```

**Key points:**
- Uses UUID to identify correct device
- `noatime` reduces write operations to extend HDD life
- Only mounts when explicitly triggered (by automount or manual command)

### mnt-extern_backup.automount

Triggers mount automatically when `/mnt/extern_backup` is accessed.

```ini
[Unit]
Description=External Backup Drive Automount
Before=mnt-extern_backup.mount

[Automount]
Where=/mnt/extern_backup
TimeoutIdleSec=300

[Install]
WantedBy=multi-user.target
```

**Key points:**
- `TimeoutIdleSec=300` - Unmounts after 5 minutes of inactivity
- Triggered by any access to `/mnt/extern_backup`
- Perfect for backup scripts that power on HDD dynamically

### Commands

```bash
# Status
systemctl status mnt-extern_backup.automount
systemctl status mnt-extern_backup.mount

# Start/Stop
sudo systemctl start mnt-extern_backup.automount
sudo systemctl stop mnt-extern_backup.automount

# Enable/Disable (persistence across reboots)
sudo systemctl enable mnt-extern_backup.automount
sudo systemctl disable mnt-extern_backup.automount

# Check if mounted
findmnt /mnt/extern_backup

# Manual mount (bypasses automount)
sudo systemctl start mnt-extern_backup.mount
```

---

## Backup Service

### backup-system@.service

Parametric service that accepts profile name as parameter.

```ini
[Unit]
Description=Backup System (%i profile)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/backup-system/main.sh %i
User=root
Group=root

# Security hardening
NoNewPrivileges=false
PrivateTmp=true
ProtectSystem=strict
ProtectHome=false
ReadWritePaths=/mnt/extern_backup /var/log/extern_backup

# Resource limits
CPUQuota=80%
MemoryMax=2G

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=backup-system-%i

[Install]
WantedBy=multi-user.target
```

**Key features:**
- `%i` = profile name (e.g., "system", "data")
- `Type=oneshot` - Runs once and exits
- Resource limits prevent backup from overwhelming system
- Security hardening restricts file system access

### Commands

```bash
# Run backup manually
sudo systemctl start backup-system@system.service
sudo systemctl start backup-system@data.service

# View status
systemctl status backup-system@system.service

# View logs (recent)
journalctl -u backup-system@system.service -n 100

# View logs (live)
journalctl -u backup-system@system.service -f

# View logs (since date)
journalctl -u backup-system@system.service --since "2026-01-01"

# View only errors
journalctl -u backup-system@system.service -p err

# Export logs
journalctl -u backup-system@system.service > backup-logs.txt
```

---

## Timer Units

### backup-system-weekly.timer

Schedules system backup every Sunday at 02:00.

```ini
[Unit]
Description=Weekly System Backup Timer
Requires=backup-system@system.service

[Timer]
OnCalendar=Sun *-*-* 02:00:00
Persistent=true
RandomizedDelaySec=15min

[Install]
WantedBy=timers.target
```

**Key features:**
- `Persistent=true` - Runs missed backups after system boot
- `RandomizedDelaySec=15min` - Random 0-15min delay to avoid load spikes
- Tied to `backup-system@system.service`

### Timer Commands

```bash
# Enable timer
sudo systemctl enable backup-system-weekly.timer
sudo systemctl start backup-system-weekly.timer

# Disable timer
sudo systemctl disable backup-system-weekly.timer
sudo systemctl stop backup-system-weekly.timer

# List all timers
systemctl list-timers

# List specific timer
systemctl list-timers backup-system-weekly.timer

# Force trigger now (don't wait for schedule)
sudo systemctl start backup-system@system.service
```

### Customizing Schedule

#### Edit Timer

```bash
sudo systemctl edit backup-system-weekly.timer
```

This creates override file: `/etc/systemd/system/backup-system-weekly.timer.d/override.conf`

#### Example: Change to Daily 03:00

```ini
[Timer]
OnCalendar=
OnCalendar=*-*-* 03:00:00
```

**Important:** Empty `OnCalendar=` first to clear default!

#### Example: Change to Every 6 Hours

```ini
[Timer]
OnCalendar=
OnCalendar=*-*-* 00,06,12,18:00:00
```

#### Example: First Monday of Month

```ini
[Timer]
OnCalendar=
OnCalendar=Mon *-*-01..07 02:00:00
```

#### Example: Weekdays Only

```ini
[Timer]
OnCalendar=
OnCalendar=Mon,Tue,Wed,Thu,Fri *-*-* 02:00:00
```

#### Apply Changes

```bash
sudo systemctl daemon-reload
sudo systemctl restart backup-system-weekly.timer
systemctl list-timers backup-system-weekly.timer
```

---

## Creating Additional Timers

### Daily Data Backup Timer

Create file: `/etc/systemd/system/backup-data-daily.timer`

```ini
[Unit]
Description=Daily Data Backup Timer
Requires=backup-system@data.service

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
```

Enable:
```bash
sudo systemctl daemon-reload
sudo systemctl enable backup-data-daily.timer
sudo systemctl start backup-data-daily.timer
systemctl list-timers backup-data-daily.timer
```

---

## Email Notifications

### Setup (Using mail command)

Install mail utilities:
```bash
sudo apt install mailutils postfix
```

### Create Notification Service

Create: `/etc/systemd/system/backup-notify@.service`

```ini
[Unit]
Description=Backup Notification (%i)

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c 'echo "Backup %i completed at $(date)" | mail -s "Backup %i: $SERVICE_RESULT" your-email@example.com'
```

### Link to Backup Service

```bash
sudo systemctl edit backup-system@system.service
```

Add:
```ini
[Unit]
OnSuccess=backup-notify@system.service
OnFailure=backup-notify@system.service
```

Reload:
```bash
sudo systemctl daemon-reload
```

### Test

```bash
sudo systemctl start backup-system@system.service
# Check email
```

---

## Monitoring and Logging

### Check Timer Status

```bash
# List all timers
systemctl list-timers --all

# Check specific timer
systemctl status backup-system-weekly.timer

# View next scheduled run
systemctl list-timers backup-system-weekly.timer | grep backup
```

### View Service Logs

```bash
# Recent logs
journalctl -u backup-system@system.service -n 50

# Logs from last boot
journalctl -u backup-system@system.service -b

# Logs from specific date range
journalctl -u backup-system@system.service --since "2026-01-10" --until "2026-01-12"

# Follow logs live
journalctl -u backup-system@system.service -f

# Only show errors
journalctl -u backup-system@system.service -p err

# Export to file
journalctl -u backup-system@system.service --since "2026-01-01" > backup-logs.txt
```

### Local Log Files

systemd journal is complemented by local log files:

```bash
# List log files
ls -la /var/log/extern_backup/

# View specific log
cat /var/log/extern_backup/system_2026-01-12_020000.log

# View latest log
tail -f /var/log/extern_backup/system_*.log
```

---

## Troubleshooting

### Timer Not Triggering

```bash
# Check timer is active
systemctl list-timers backup-system-weekly.timer

# Check timer status
systemctl status backup-system-weekly.timer

# Verify timer is enabled
systemctl is-enabled backup-system-weekly.timer

# Manual trigger
sudo systemctl start backup-system@system.service
```

### Service Fails to Start

```bash
# Check service status
systemctl status backup-system@system.service

# View detailed errors
journalctl -u backup-system@system.service -n 100

# Test script manually
sudo /opt/backup-system/main.sh system

# Check configuration
sudo /opt/backup-system/segments/01_validate_config.sh
```

### Mount Issues

```bash
# Check automount status
systemctl status mnt-extern_backup.automount

# Check mount status
systemctl status mnt-extern_backup.mount
findmnt /mnt/extern_backup

# Restart automount
sudo systemctl restart mnt-extern_backup.automount

# Check device availability
ls -la /dev/disk/by-uuid/
```

### Shelly Connection Failed

```bash
# Test Shelly connectivity
curl http://192.168.10.164/rpc/Switch.GetStatus?id=0

# Test from backup script
sudo /opt/backup-system/segments/03_shelly_power_on.sh

# Check network
ping 192.168.10.164
```

### Backup Process Hangs

```bash
# Check if process is running
ps aux | grep backup

# Check what's locking the mount
sudo lsof +f -- /mnt/extern_backup

# Kill stuck process (last resort)
sudo systemctl stop backup-system@system.service
sudo pkill -9 -f backup-system
```

---

## Backup Restoration

### List Available Archives

```bash
# Power on HDD manually if needed
curl "http://192.168.10.164/rpc/Switch.Set?id=0&on=true"

# Mount backup drive
sudo mount /mnt/extern_backup

# List archives
sudo borg list /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo
```

### Restore Entire System

**⚠️ WARNING: This will overwrite your current system!**

```bash
# Boot from Ubuntu Live USB
# Mount your system partition
sudo mount /dev/nvme0n1p2 /mnt

# Mount backup drive
sudo mount /mnt/extern_backup

# Restore (CAREFUL!)
sudo borg extract /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo::archive-name

# Restore to /mnt instead
cd /mnt
sudo borg extract /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo::archive-name
```

### Restore Individual Files

```bash
# Mount backup
sudo mount /mnt/extern_backup

# List files in archive
sudo borg list /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo::archive-name | grep filename

# Extract specific file
sudo borg extract /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo::archive-name path/to/file

# Extract to specific location
mkdir ~/restore
cd ~/restore
sudo borg extract /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo::archive-name path/to/file
```

### Restore from Borg Repository

For detailed Borg recovery procedures, see:
```bash
man borg-extract
borg extract --help
```

---

## Best Practices

### 1. Test Backups Regularly

```bash
# Monthly restore test
sudo borg list /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo
sudo borg info /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo::latest-archive
```

### 2. Monitor Timer Execution

```bash
# Add to crontab to email weekly summary
0 9 * * 1 systemctl list-timers | grep backup | mail -s "Backup Timer Status" you@example.com
```

### 3. Keep Logs

```bash
# Backup logs monthly
tar czf ~/backup-logs-$(date +%Y-%m).tar.gz /var/log/extern_backup/
```

### 4. Document Passphrase Location

Create file: `/root/BACKUP_RECOVERY_INFO.txt`
```
Borg Passphrase Location: /root/.config/borg/passphrase
Backup Location (secure): [your backup location]
Repository Path: /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo
```

Store copy in password manager or encrypted external drive.

---

## Security Considerations

### Passphrase Security

```bash
# Passphrase permissions (only root readable)
sudo chmod 600 /root/.config/borg/passphrase
sudo chown root:root /root/.config/borg/passphrase
```

### Service Hardening

The backup service includes security restrictions:
- `ProtectSystem=strict` - Read-only system files
- `PrivateTmp=true` - Isolated /tmp
- `ReadWritePaths` - Explicit write permissions
- `CPUQuota` - Resource limits

### Network Security

For Shelly Plug:
- Use local network only (no internet exposure)
- Consider static DHCP reservation
- Optional: Restrict by MAC address in router

---

## Appendix: systemd Calendar Syntax

### Time Formats

```
Syntax: DayOfWeek Year-Month-Day Hour:Minute:Second

Examples:
*-*-* 02:00:00           # Daily at 02:00
Mon *-*-* 02:00:00       # Every Monday at 02:00
*-*-01 02:00:00          # First day of month at 02:00
*-01,07-01 02:00:00      # Jan 1 and Jul 1 at 02:00
Mon..Fri *-*-* 02:00:00  # Weekdays at 02:00
*/2-*-* 00:00:00         # Every 2 hours
```

### Test Calendar Expression

```bash
systemd-analyze calendar "Mon *-*-* 02:00:00"
```

Output shows next 10 occurrences.

---

## Quick Reference

### Common Commands

```bash
# Start backup now
sudo systemctl start backup-system@system.service

# View logs
journalctl -u backup-system@system.service -f

# Check next run
systemctl list-timers backup-system-weekly.timer

# Edit schedule
sudo systemctl edit backup-system-weekly.timer

# Reload after changes
sudo systemctl daemon-reload
```

### File Locations

```
/opt/backup-system/                      # Installation
/etc/systemd/system/backup-system*.      # systemd units
/var/log/extern_backup/                  # Local logs
/root/.config/borg/passphrase            # Borg passphrase
/mnt/extern_backup/                      # Mount point
```
