# Deployment Guide

## Overview

This guide explains how to deploy updates from the development repository to the production backup system.

## Architecture

```
Windows (Development)                Ubuntu Host (Production)
E:\Projects\linux-backup-system  →  /opt/backup-system
     ↓ SMB Share                         ↓ Running System
     ↓ Git Repository                    ↓ Active Backups
```

## Critical Concepts

### Configuration Files: .example vs Production

**Why separate files?**

```
Git Repository (Shared):          Production (Deployment-Specific):
config/common.env.example         /opt/backup-system/config/common.env
config/profiles/system.env.example → /opt/backup-system/config/profiles/system.env
config/profiles/dev-data.env.example → /opt/backup-system/config/profiles/dev-data.env
```

**Reason:** Production configs contain:
- Database passwords
- Device UUIDs (your specific hardware)
- IP addresses (your network)
- Borg passphrase paths
- Host-specific settings

**.gitignore protects these:**
```bash
# In .gitignore:
config/profiles/system.env       # NOT in Git
config/profiles/dev-data.env     # NOT in Git
config/common.env                # NOT in Git
```

### The Deployment Workflow

1. **Update .example files** (safe templates)
2. **Git commit + push** (shared code)
3. **Deploy to production**
4. **Merge changes into production configs** (preserve secrets)
5. **Test manually** before relying on timers

---

## Deployment Methods

### Method 1: Via /tmp (Recommended for SMB)

When accessing files via SMB share on Ubuntu:

#### Step 1: Copy as normal user (jo)

```bash
# Files are on SMB at: /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/...
# Root cannot access user's GVFS mounts!

# Copy from SMB to /tmp
cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/segments/FILENAME.sh /tmp/

cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/systemd/FILENAME.sh /tmp/
```

#### Step 2: Copy as root to production

```bash
# Copy from /tmp to production
sudo cp /tmp/FILENAME.sh /opt/backup-system/segments/
sudo cp /tmp/FILENAME.sh /opt/backup-system/systemd/

# Set executable permissions
sudo chmod +x /opt/backup-system/segments/FILENAME.sh
sudo chmod +x /opt/backup-system/systemd/FILENAME.sh

# Cleanup
rm /tmp/FILENAME.sh

# Reload systemd if needed
sudo systemctl daemon-reload
```

### Method 2: Via Git (Recommended for regular updates)

If you have a local Git clone on Ubuntu:

```bash
# 1. Update local repository
cd ~/segmented-borg-backup-system  # or your local clone path
git pull origin main

# 2. Deploy to production
sudo cp main.sh /opt/backup-system/
sudo cp run-backup.sh /opt/backup-system/
sudo cp segments/*.sh /opt/backup-system/segments/
sudo cp systemd/*.sh /opt/backup-system/systemd/

# 3. Set permissions
sudo chmod +x /opt/backup-system/main.sh
sudo chmod +x /opt/backup-system/run-backup.sh
sudo chmod +x /opt/backup-system/segments/*.sh
sudo chmod +x /opt/backup-system/systemd/*.sh

# 4. Reload systemd
sudo systemctl daemon-reload
```

---

## Common Deployment Scenarios

### Updating a Segment

```bash
# As user
cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/segments/05_mount_backup.sh /tmp/

# As root
sudo cp /tmp/05_mount_backup.sh /opt/backup-system/segments/
sudo chmod +x /opt/backup-system/segments/05_mount_backup.sh
rm /tmp/05_mount_backup.sh
```

### Updating Core Scripts (main.sh, run-backup.sh)

```bash
# As user (copy both)
cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/main.sh /tmp/
cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/run-backup.sh /tmp/

# As root
sudo cp /tmp/main.sh /opt/backup-system/
sudo cp /tmp/run-backup.sh /opt/backup-system/
sudo chmod +x /opt/backup-system/main.sh
sudo chmod +x /opt/backup-system/run-backup.sh

# Verify version
head -20 /opt/backup-system/main.sh | grep version

# Cleanup
rm /tmp/main.sh /tmp/run-backup.sh
```

### Updating Configuration Files

**⚠️ CRITICAL: Never overwrite production configs directly!**

Production configs contain secrets (passwords, UUIDs) that must be preserved.

#### Step 1: Backup production config

```bash
sudo cp /opt/backup-system/config/profiles/dev-data.env \
        /opt/backup-system/config/profiles/dev-data.env.backup.$(date +%F)
```

#### Step 2: Copy new .example template

```bash
# As user
cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/config/profiles/dev-data.env.example /tmp/

# Review what changed
sudo diff /opt/backup-system/config/profiles/dev-data.env /tmp/dev-data.env.example
```

#### Step 3: Merge changes manually

```bash
# Open both files side-by-side
sudo nano /opt/backup-system/config/profiles/dev-data.env

# Compare with:
cat /tmp/dev-data.env.example

# Merge new settings while preserving:
# - Passwords (NEXTCLOUD_DB_PASSWORD)
# - UUIDs (BACKUP_UUID)
# - IP addresses (SHELLY_IP)
# - Paths (/mnt/...)
```

#### Step 4: Verify critical settings

```bash
# Check for new phase configurations
grep -E "PRE_BACKUP|POST_BACKUP|POST_CLEANUP" /opt/backup-system/config/profiles/dev-data.env

# Expected output (v2.2.0+):
# export PRE_BACKUP_SEGMENTS=(...)
# export POST_BACKUP_SEGMENTS=(...)  ← Must exist!
```

### Example: Adding POST_BACKUP Phase

**Scenario:** Upgrade from v2.0.0 to v2.2.0 (add POST_BACKUP for container restart)

```bash
# 1. Backup current config
sudo cp /opt/backup-system/config/profiles/dev-data.env \
        /opt/backup-system/config/profiles/dev-data.env.v2.0.0

# 2. Edit production config
sudo nano /opt/backup-system/config/profiles/dev-data.env

# 3. Find this section:
# OLD (v2.0.0):
export POST_CLEANUP_SEGMENTS=(
  "post_01_docker_start.sh"
)

# 4. Change to:
# NEW (v2.2.0):
export POST_BACKUP_SEGMENTS=(
  "post_01_docker_start.sh"
)
# export POST_CLEANUP_SEGMENTS=()

# 5. Save and verify
grep POST_BACKUP /opt/backup-system/config/profiles/dev-data.env
# Should show: export POST_BACKUP_SEGMENTS=(...)
```

**Why this matters:**
- `POST_CLEANUP`: Runs after verify (~5 hours later)
- `POST_BACKUP`: Runs after backup (~10 min later)
- Container downtime: 5 hours → 10 minutes! (98% reduction)

### Updating Systemd Timers

```bash
# Copy timer template
cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/systemd/backup-system-daily.timer.example /tmp/

# Customize for your schedule
nano /tmp/backup-system-daily.timer.example
# Edit OnCalendar= to your preferred time

# Deploy to systemd
sudo cp /tmp/backup-system-daily.timer.example /etc/systemd/system/backup-system-daily.timer
sudo systemctl daemon-reload
sudo systemctl enable backup-system-daily.timer
sudo systemctl start backup-system-daily.timer

# Verify
systemctl status backup-system-daily.timer

# Cleanup
rm /tmp/backup-system-daily.timer.example
```

### Full System Update with Config Merge

```bash
# 1. Stop timers
sudo systemctl stop backup-system-daily.timer
sudo systemctl stop backup-system-dev-data-daily.timer

# 2. Backup current installation
sudo tar -czf /tmp/backup-system-backup-$(date +%F).tar.gz /opt/backup-system/

# 3. Update files (via SMB)
# Copy main.sh
cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/main.sh /tmp/
cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/run-backup.sh /tmp/

# Copy all segments (bulk)
cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/segments/*.sh /tmp/segments/

# Copy config templates
cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/config/common.env.example /tmp/
cp /run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/linux-backup-system/config/profiles/dev-data.env.example /tmp/

# 4. Deploy scripts
sudo cp /tmp/main.sh /opt/backup-system/
sudo cp /tmp/run-backup.sh /opt/backup-system/
sudo cp /tmp/segments/*.sh /opt/backup-system/segments/

# 5. Set permissions
sudo chmod +x /opt/backup-system/main.sh
sudo chmod +x /opt/backup-system/run-backup.sh
sudo chmod +x /opt/backup-system/segments/*.sh

# 6. Review config changes
diff /opt/backup-system/config/common.env /tmp/common.env.example
diff /opt/backup-system/config/profiles/dev-data.env /tmp/dev-data.env.example

# 7. Merge config changes manually
sudo nano /opt/backup-system/config/common.env
# Update version: BACKUP_SYSTEM_VERSION="2.2.0"
# Add any new settings from .example

sudo nano /opt/backup-system/config/profiles/dev-data.env
# Add POST_BACKUP_SEGMENTS if missing
# Preserve all passwords, UUIDs, IPs!

# 8. Cleanup
rm /tmp/main.sh /tmp/run-backup.sh
rm -r /tmp/segments/
rm /tmp/common.env.example /tmp/dev-data.env.example

# 9. Test manually
sudo /opt/backup-system/run-backup.sh system

# 10. Restart timers
sudo systemctl daemon-reload
sudo systemctl start backup-system-daily.timer
sudo systemctl start backup-system-dev-data-daily.timer

# 11. Verify
systemctl list-timers | grep backup-system
```

---

## Version-Specific Migration Guides

### Migrating to v2.2.0 (POST_BACKUP Phase)

**Breaking Changes:**
1. Logging now handled by `run-backup.sh` wrapper
2. Mount configuration moved to fstab
3. POST_BACKUP phase added for container restart

**Required Actions:**

#### 1. Deploy new scripts

```bash
# Copy main.sh v2.2.0
cp /run/user/1000/gvfs/.../main.sh /tmp/
sudo cp /tmp/main.sh /opt/backup-system/
sudo chmod +x /opt/backup-system/main.sh

# Copy run-backup.sh (NEW)
cp /run/user/1000/gvfs/.../run-backup.sh /tmp/
sudo cp /tmp/run-backup.sh /opt/backup-system/
sudo chmod +x /opt/backup-system/run-backup.sh

# Update segments
cp /run/user/1000/gvfs/.../segments/02_init_logging.sh /tmp/
cp /run/user/1000/gvfs/.../segments/05_mount_backup.sh /tmp/
sudo cp /tmp/02_init_logging.sh /opt/backup-system/segments/
sudo cp /tmp/05_mount_backup.sh /opt/backup-system/segments/
sudo chmod +x /opt/backup-system/segments/*.sh
```

#### 2. Update systemd service

```bash
# Copy new service file
cp /run/user/1000/gvfs/.../systemd/backup-system@.service /tmp/
sudo cp /tmp/backup-system@.service /etc/systemd/system/
sudo systemctl daemon-reload
```

#### 3. Update config files

```bash
# common.env
sudo nano /opt/backup-system/config/common.env
# Change: BACKUP_SYSTEM_VERSION="2.2.0"

# dev-data.env
sudo nano /opt/backup-system/config/profiles/dev-data.env
# Change:
#   OLD: export POST_CLEANUP_SEGMENTS=("post_01_docker_start.sh")
#   NEW: export POST_BACKUP_SEGMENTS=("post_01_docker_start.sh")
```

#### 4. Configure fstab (one-time)

```bash
# Edit fstab
sudo nano /etc/fstab

# Add automount options:
UUID=9d5bdf3a-ede2-472e-a463-741836755d1b  /mnt/system_backup  ext4  \
  defaults,nofail,acl,x-systemd.automount,\
  x-systemd.device-timeout=30,x-systemd.idle-timeout=300  0  2

# Remove old systemd mount units
sudo systemctl stop mnt-system_backup.automount
sudo systemctl disable mnt-system_backup.automount
sudo rm /etc/systemd/system/mnt-system_backup.*
sudo systemctl daemon-reload
```

#### 5. Test

```bash
# Test manually
sudo /opt/backup-system/run-backup.sh dev-data

# Check logs for POST_BACKUP phase
journalctl -u backup-system@dev-data.service | grep "POST_BACKUP"

# Expected output:
# ===============================================================================
#   POST-BACKUP (Profile-Specific)
# ===============================================================================
# [POST-01] Starting Docker containers...
```

---

## Troubleshooting

### Permission Denied on SMB

**Problem:**
```
sudo cp /run/user/1000/gvfs/... 
cp: Permission denied
```

**Cause:** Root cannot access user's GVFS mounts

**Solution:** Use 2-step process via /tmp (see Method 1)

### File Not Found

**Problem:**
```
cp: cannot stat 'smb://192.168.10.10/e/...'
```

**Cause:** SMB paths must use GVFS mount point, not `smb://` URLs

**Solution:** Use full GVFS path:
```bash
/run/user/1000/gvfs/smb-share:server=192.168.10.10,share=e/Projects/...
```

### Changes Not Taking Effect

**Problem:** Updated files but backup behavior unchanged

**Solution:**
```bash
# 1. Verify files were copied
ls -la /opt/backup-system/main.sh
cat /opt/backup-system/main.sh | head -30  # Check version

# 2. Verify permissions
ls -la /opt/backup-system/segments/*.sh  # Should have 'x' flag

# 3. Check config was updated
grep POST_BACKUP /opt/backup-system/config/profiles/dev-data.env

# 4. Reload systemd
sudo systemctl daemon-reload

# 5. Test manually (shows version)
sudo /opt/backup-system/run-backup.sh system
```

### POST_BACKUP Not Running

**Problem:** Containers still down after backup

**Symptoms:**
```bash
# Log shows:
[08] Backup completed
[09] Verify started  ← Containers still stopped!

# Missing:
# POST-BACKUP phase
# [POST-01] Starting containers
```

**Cause:** Config still uses old `POST_CLEANUP_SEGMENTS`

**Solution:**
```bash
# Check current config
grep -E "POST_BACKUP|POST_CLEANUP" /opt/backup-system/config/profiles/dev-data.env

# Should see:
export POST_BACKUP_SEGMENTS=("post_01_docker_start.sh")  ← CORRECT!

# NOT:
export POST_CLEANUP_SEGMENTS=("post_01_docker_start.sh")  ← WRONG!

# Fix:
sudo nano /opt/backup-system/config/profiles/dev-data.env
# Move post_01_docker_start.sh from POST_CLEANUP to POST_BACKUP
```

---

## Best Practices

### 1. Always Test First

```bash
# Test manually before relying on timer
sudo /opt/backup-system/run-backup.sh system

# Check logs
journalctl -u backup-system@system.service -n 100

# For dev-data, verify container downtime
sudo /opt/backup-system/run-backup.sh dev-data
# Time the downtime: from Docker stop to Docker start
```

### 2. Backup Before Updates

```bash
# Backup entire installation
sudo tar -czf /tmp/backup-system-backup-$(date +%F).tar.gz /opt/backup-system/

# Or just configs
sudo cp -r /opt/backup-system/config /tmp/backup-system-config-backup-$(date +%F)
```

### 3. Version Control

```bash
# Always commit changes to Git before deploying
cd E:\Projects\linux-backup-system  # On Windows
git add .
git commit -m "feat: Update mount handling"
git push origin main

# Then deploy to Ubuntu
```

### 4. Staged Rollout

```bash
# Test on dev-data first (smaller, less critical)
sudo /opt/backup-system/run-backup.sh dev-data

# If successful, then test system
sudo /opt/backup-system/run-backup.sh system
```

### 5. Keep .example Files Updated

When you make production config changes that should be shared:

```bash
# 1. Update .example template (remove secrets!)
# E:\Projects\linux-backup-system\config\profiles\dev-data.env.example

# 2. Commit to Git
git add config/profiles/dev-data.env.example
git commit -m "Update dev-data.env.example with POST_BACKUP"
git push

# 3. Others can now deploy your changes
```

### 6. Document Custom Settings

Add comments in production configs:

```bash
# /opt/backup-system/config/profiles/dev-data.env

# Custom: Changed from POST_CLEANUP to POST_BACKUP (v2.2.0)
# Reduces container downtime from 5h to 10min
export POST_BACKUP_SEGMENTS=(
  "post_01_docker_start.sh"
)
```

---

## File Locations Reference

### Development (Windows)
```
E:\Projects\linux-backup-system\
├── main.sh
├── run-backup.sh
├── segments/
│   ├── 01_validate_config.sh
│   ├── 02_init_logging.sh
│   └── ...
├── config/
│   ├── common.env                ← Local copy (NOT in Git)
│   ├── common.env.example        ← Template (IN Git)
│   └── profiles/
│       ├── system.env            ← Local copy (NOT in Git)
│       ├── system.env.example    ← Template (IN Git)
│       ├── dev-data.env          ← Local copy (NOT in Git)
│       └── dev-data.env.example  ← Template (IN Git)
└── systemd/
    ├── backup-system@.service
    ├── backup-system-daily.timer.example
    └── install-systemd-units.sh
```

### Production (Ubuntu)
```
/opt/backup-system/
├── main.sh                    # Executable
├── run-backup.sh              # Wrapper script
├── segments/                  # All executable
│   ├── 01_validate_config.sh
│   ├── 02_init_logging.sh
│   └── ...
├── config/
│   ├── common.env            # Production secrets! (NOT synced)
│   └── profiles/
│       ├── system.env        # Production config! (NOT synced)
│       └── dev-data.env      # Production config! (NOT synced)
└── systemd/
    └── install-systemd-units.sh

/etc/systemd/system/
├── backup-system@.service
├── backup-system-daily.timer
└── backup-system-dev-data-daily.timer
```

---

## Configuration File Workflow

### Initial Setup (First Time)

```bash
# 1. Copy templates to production
sudo cp /opt/backup-system/config/common.env.example \
        /opt/backup-system/config/common.env

sudo cp /opt/backup-system/config/profiles/system.env.example \
        /opt/backup-system/config/profiles/system.env

# 2. Customize with your settings
sudo nano /opt/backup-system/config/common.env
# Set: SHELLY_IP, BORG_PASSPHRASE_FILE, etc.

sudo nano /opt/backup-system/config/profiles/system.env
# Set: BACKUP_UUID, ARCHIVE_PREFIX, etc.

# 3. Protect with permissions
sudo chmod 600 /opt/backup-system/config/common.env
sudo chmod 600 /opt/backup-system/config/profiles/*.env
```

### Updating Existing Config

```bash
# 1. Backup current
sudo cp /opt/backup-system/config/profiles/dev-data.env \
        /opt/backup-system/config/profiles/dev-data.env.backup

# 2. Get new template
cp /run/user/1000/gvfs/.../config/profiles/dev-data.env.example /tmp/

# 3. Compare
diff /opt/backup-system/config/profiles/dev-data.env /tmp/dev-data.env.example

# 4. Merge manually (preserve secrets!)
sudo nano /opt/backup-system/config/profiles/dev-data.env

# 5. Cleanup
rm /tmp/dev-data.env.example
```

---

## Security Considerations

### Never Commit Secrets

Files that should NEVER be in Git:
- `/opt/backup-system/config/common.env` (Borg passphrase path, Shelly IP)
- `/opt/backup-system/config/profiles/*.env` (UUIDs, passwords, paths)

These files are deployment-specific and contain sensitive information.

### Use .example Files

Development repository contains `.example` files:
- `config/common.env.example`
- `config/profiles/system.env.example`
- `config/profiles/dev-data.env.example`

These are safe templates without secrets.

### Protect Production Configs

```bash
# Set restrictive permissions
sudo chmod 600 /opt/backup-system/config/common.env
sudo chmod 600 /opt/backup-system/config/profiles/*.env
sudo chown root:root /opt/backup-system/config/*.env
sudo chown root:root /opt/backup-system/config/profiles/*.env
```

---

## Deployment Checklist

Use this checklist for major updates:

```
[ ] 1. Backup current installation
       sudo tar -czf /tmp/backup-system-backup-$(date +%F).tar.gz /opt/backup-system/

[ ] 2. Stop timers
       sudo systemctl stop backup-system-*.timer

[ ] 3. Copy new main.sh and run-backup.sh
       Check version in file header

[ ] 4. Copy updated segments
       Verify executable permissions

[ ] 5. Review .example config files
       Compare with production configs

[ ] 6. Merge config changes
       Preserve all secrets (passwords, UUIDs)
       Add new phase configurations (POST_BACKUP, etc.)

[ ] 7. Update systemd units if needed
       Copy .example timers, customize schedules

[ ] 8. Reload systemd
       sudo systemctl daemon-reload

[ ] 9. Test manually
       sudo /opt/backup-system/run-backup.sh system
       Check for new phase outputs

[ ] 10. Verify logs
        journalctl -u backup-system@system.service
        Look for version number, new phases

[ ] 11. Restart timers
        sudo systemctl start backup-system-*.timer

[ ] 12. Verify timer schedules
        systemctl list-timers | grep backup-system
```

---

## See Also

- [Main README](../README.md)
- [Timer Configuration Guide](TIMERS.md) - Detailed timer setup
- [Systemd Integration](SYSTEMD.md) - fstab and systemd configuration
- [Docker/Nextcloud Integration](DOCKER_NEXTCLOUD.md) - Container backup details
