# Timer Configuration Guide

## Overview

This guide explains how to configure systemd timers for automated backups.

## Available Timer Templates

The system provides three timer templates in `/systemd/`:

1. **backup-system-daily.timer.example** - Daily system backup (10:00 AM)
2. **backup-system-weekly.timer.example** - Weekly system backup (Sunday 02:00 AM)
3. **backup-system-dev-data-daily.timer.example** - Daily Docker/Nextcloud backup (00:00 midnight)

## Configuration Strategy

### Template vs Production Files

```
systemd/
├── backup-system-daily.timer.example          ← Template (in Git)
├── backup-system-weekly.timer.example         ← Template (in Git)
├── backup-system-dev-data-daily.timer.example ← Template (in Git)
└── backup-system@.service                     ← Service template (in Git)

/etc/systemd/system/
├── backup-system-daily.timer                  ← Production (NOT in Git)
├── backup-system-weekly.timer                 ← Production (NOT in Git)
├── backup-system-dev-data-daily.timer         ← Production (NOT in Git)
└── backup-system@.service                     ← Production service
```

**Why separate?**
- Templates are deployment-agnostic (safe to share)
- Production timers contain your specific schedule (deployment-specific)
- Allows different schedules per deployment without Git conflicts

## Setup Instructions

### 1. Choose Your Timer Strategy

**Option A: Daily System Backup**
```bash
sudo cp /opt/backup-system/systemd/backup-system-daily.timer.example \
        /etc/systemd/system/backup-system-daily.timer
```

**Option B: Weekly System Backup**
```bash
sudo cp /opt/backup-system/systemd/backup-system-weekly.timer.example \
        /etc/systemd/system/backup-system-weekly.timer
```

**Option C: Both (Daily + Docker/Nextcloud)**
```bash
# System backup daily
sudo cp /opt/backup-system/systemd/backup-system-daily.timer.example \
        /etc/systemd/system/backup-system-daily.timer

# Docker/Nextcloud backup daily
sudo cp /opt/backup-system/systemd/backup-system-dev-data-daily.timer.example \
        /etc/systemd/system/backup-system-dev-data-daily.timer
```

### 2. Customize Schedule (Optional)

Edit the production timer to match your needs:

```bash
sudo nano /etc/systemd/system/backup-system-daily.timer
```

Examples:

**Run at 3:00 AM instead of 10:00 AM:**
```ini
[Timer]
OnCalendar=*-*-* 03:00:00
```

**Run twice daily (6:00 AM and 6:00 PM):**
```ini
[Timer]
OnCalendar=*-*-* 06:00:00
OnCalendar=*-*-* 18:00:00
```

**Run every 6 hours:**
```ini
[Timer]
OnCalendar=*-*-* 00/6:00:00
```

### 3. Enable and Start Timer

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable timer (start on boot)
sudo systemctl enable backup-system-daily.timer

# Start timer now
sudo systemctl start backup-system-daily.timer

# Verify
systemctl status backup-system-daily.timer
systemctl list-timers | grep backup-system
```

## Timer Options Explained

### Basic Options

```ini
[Timer]
Unit=backup-system@system.service  # Service to trigger
OnCalendar=*-*-* 10:00:00          # When to run (daily at 10:00)
Persistent=true                     # Run missed jobs after boot
RandomizedDelaySec=5min            # Random delay (avoid exact scheduling)
```

### OnCalendar Syntax

| Schedule | OnCalendar Value | Description |
|----------|------------------|-------------|
| Daily at 10:00 | `*-*-* 10:00:00` | Every day at 10:00 AM |
| Midnight | `daily` or `*-*-* 00:00:00` | Every day at midnight |
| Weekly on Sunday | `Sun *-*-* 02:00:00` | Sunday at 2:00 AM |
| Every 6 hours | `*-*-* 00/6:00:00` | 00:00, 06:00, 12:00, 18:00 |
| Twice daily | Two `OnCalendar` lines | Multiple triggers |
| First of month | `*-*-01 02:00:00` | 1st day of month at 2:00 AM |

### Advanced Options

```ini
[Timer]
# Run 15 minutes after boot if missed
Persistent=true

# Random delay up to 15 minutes
RandomizedDelaySec=15min

# Run even if previous job still running (careful!)
# AllowSimultaneousJobs=true

# Wait for other timers to finish (if multiple)
# After=backup-system-other.timer
```

## Multiple Profiles

### Running Multiple Backups

You can run multiple backup profiles on different schedules:

```bash
# System backup: Daily at 10:00
/etc/systemd/system/backup-system-daily.timer
  → triggers backup-system@system.service

# Docker/Nextcloud: Daily at 00:00
/etc/systemd/system/backup-system-dev-data-daily.timer
  → triggers backup-system@dev-data.service
```

**Both can coexist!** They use different:
- Target directories
- Borg repositories
- Source paths

## Monitoring

### Check Timer Status

```bash
# List all backup timers
systemctl list-timers | grep backup-system

# Detailed status
systemctl status backup-system-daily.timer

# View logs
journalctl -u backup-system-daily.timer
journalctl -u backup-system@system.service
```

### Expected Output

```
NEXT                        LEFT       LAST                        PASSED UNIT
Thu 2026-01-16 10:00:00 CET 23h left  Wed 2026-01-15 10:00:00 CET 2h ago backup-system-daily.timer
Fri 2026-01-16 00:00:00 CET 11h left  Thu 2026-01-15 00:05:51 CET 12h ago backup-system-dev-data-daily.timer
```

## Troubleshooting

### Timer Not Triggering

**Problem:** Timer exists but backup doesn't run

**Solutions:**
1. Check timer is enabled:
   ```bash
   systemctl is-enabled backup-system-daily.timer
   ```

2. Check timer is active:
   ```bash
   systemctl status backup-system-daily.timer
   ```

3. Check next trigger time:
   ```bash
   systemctl list-timers | grep backup-system
   ```

4. View timer logs:
   ```bash
   journalctl -u backup-system-daily.timer -n 50
   ```

### Wrong Profile Running

**Problem:** Timer runs but wrong profile executes

**Cause:** `Unit=` in timer doesn't match desired profile

**Solution:** Edit timer file:
```bash
sudo nano /etc/systemd/system/backup-system-daily.timer

# Ensure correct profile:
[Timer]
Unit=backup-system@system.service      # For system profile
# OR
Unit=backup-system@dev-data.service    # For dev-data profile
```

### Timer Conflict

**Problem:** Multiple timers trigger at same time

**Solution:** Stagger schedules or use `RandomizedDelaySec`:
```bash
# Timer 1: Exactly at 10:00
OnCalendar=*-*-* 10:00:00
RandomizedDelaySec=0

# Timer 2: Between 11:00-11:15
OnCalendar=*-*-* 11:00:00
RandomizedDelaySec=15min
```

## Migration from Old Configuration

### From Cron to Systemd Timers

If you previously used cron:

```bash
# 1. Remove old crontab entry
sudo crontab -e
# Remove line like: 0 10 * * * /opt/backup-system/main.sh system

# 2. Install systemd timer
sudo cp /opt/backup-system/systemd/backup-system-daily.timer.example \
        /etc/systemd/system/backup-system-daily.timer

# 3. Enable and start
sudo systemctl daemon-reload
sudo systemctl enable --now backup-system-daily.timer
```

### From backup-system-daily.timer to backup-system-weekly.timer

If switching strategies:

```bash
# 1. Stop and disable old timer
sudo systemctl stop backup-system-daily.timer
sudo systemctl disable backup-system-daily.timer

# 2. Install new timer
sudo cp /opt/backup-system/systemd/backup-system-weekly.timer.example \
        /etc/systemd/system/backup-system-weekly.timer

# 3. Enable and start new timer
sudo systemctl daemon-reload
sudo systemctl enable --now backup-system-weekly.timer
```

## Best Practices

### 1. Stagger Backup Times

If running multiple backups, avoid conflicts:
- System backup: 10:00 AM
- Docker backup: 00:00 AM (midnight)
- Separate by at least 2-3 hours

### 2. Use Persistent=true

Always enable `Persistent=true` so missed backups run after reboot.

### 3. Add Randomization

Use `RandomizedDelaySec` to:
- Avoid exact scheduling (better for cloud sync)
- Reduce load spikes if multiple systems
- Spread backup load over time

### 4. Monitor Regularly

Check timer status weekly:
```bash
systemctl list-timers | grep backup-system
journalctl -u backup-system@system.service --since "7 days ago"
```

### 5. Test After Changes

After modifying timers:
```bash
# Reload
sudo systemctl daemon-reload

# Test manually
sudo systemctl start backup-system@system.service

# Check logs
journalctl -u backup-system@system.service -f
```

## See Also

- [Systemd Integration Guide](SYSTEMD.md)
- [Main README](../README.md)
- [Deployment Guide](DEPLOYMENT.md)
