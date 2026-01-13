# Installation Guide - Backup System v2.0.1

Step-by-step installation instructions for Ubuntu 24.04 LTS.

## Prerequisites

### 1. System Requirements

- Ubuntu 24.04 LTS (or compatible Debian-based system)
- Root access
- External HDD with ext4 filesystem
- Shelly Plug Plus (optional, can be disabled in config)

### 2. Install Required Packages

```bash
sudo apt update
sudo apt install -y borgbackup curl hdparm lsof util-linux
```

Verify installations:
```bash
borg --version          # Should show BorgBackup version
curl --version          # Should show curl version
hdparm -V               # Should show hdparm version
```

### 3. Prepare External HDD

#### Option A: HDD Already Formatted as ext4

Skip to step 4 if your HDD is already formatted.

#### Option B: Format New HDD

**⚠️ WARNING: This will erase all data on the drive!**

```bash
# Find your device (e.g., /dev/sdc)
lsblk

# Format as ext4 (REPLACE /dev/sdX with your device!)
sudo mkfs.ext4 -L "BackupDrive" /dev/sdX1

# Get UUID
sudo blkid /dev/sdX1
# Example output: UUID="f2c4624a-72ee-5e4b-85f8-a0d7f02e702f"
```

**Save the UUID** - you'll need it for configuration!

---

## Installation Steps

### Step 1: Extract Backup System

```bash
# Create installation directory
sudo mkdir -p /opt/backup-system

# Extract archive
sudo unzip backup-system.zip -d /opt/

# Verify structure
ls -la /opt/backup-system/
```

Expected structure:
```
/opt/backup-system/
├── main.sh
├── config/
├── segments/
├── tests/
├── systemd/
└── docs/
```

### Step 1a: Create Convenience Wrapper (Optional but Recommended)

For easier command-line access, create a wrapper script in `/usr/local/bin/`:

```bash
# Create wrapper script
sudo tee /usr/local/bin/backup-system > /dev/null << 'EOF'
#!/bin/bash
# Backup System Wrapper
exec /opt/backup-system/main.sh "$@"
EOF

# Make it executable
sudo chmod +x /usr/local/bin/backup-system

# Test it
backup-system
# Should show: [ERROR] Profile not found: system (this is OK - config not done yet)
```

**Why a wrapper instead of a symlink?**
- Symlinks can confuse path resolution in scripts
- Wrapper ensures correct working directory
- More reliable for systemd integration

**Usage after installation:**
```bash
# With wrapper (short)
sudo backup-system system

# Without wrapper (full path)
sudo /opt/backup-system/main.sh system
```

### Step 2: Configure Mount Point

#### Create Mount Directory

```bash
sudo mkdir -p /mnt/extern_backup
```

#### Add to /etc/fstab

```bash
sudo nano /etc/fstab
```

Add this line (replace UUID with yours):
```
UUID=f2c4624a-72ee-5e4b-85f8-a0d7f02e702f /mnt/extern_backup ext4 noauto,x-systemd.automount 0 2
```

**Important flags:**
- `noauto` - Don't mount automatically at boot
- `x-systemd.automount` - Enable systemd automount

Save and exit (Ctrl+X, Y, Enter).

#### Verify fstab Entry

```bash
# Test mount without actually mounting
sudo mount -fav

# Should show: /mnt/extern_backup : successfully simulated
```

### Step 3: Configure Backup Profiles

#### Configure Common Settings

```bash
# Copy example file
sudo cp /opt/backup-system/config/common.env.example /opt/backup-system/config/common.env

# Edit configuration
sudo nano /opt/backup-system/config/common.env
```

Adjust these values:
```bash
# Shelly Plug IP address (REPLACE with your IP)
export SHELLY_IP="192.168.X.X"

# Auto-off timeout (12 hours = 43200 seconds)
export SHELLY_TOGGLE_AFTER_SEC="43200"
```

#### Configure System Profile

```bash
# Copy example file
sudo cp /opt/backup-system/config/profiles/system.env.example /opt/backup-system/config/profiles/system.env

# Edit configuration
sudo nano /opt/backup-system/config/profiles/system.env
```

**Must adjust:**
```bash
# UUID of your backup drive (find with: sudo blkid)
export BACKUP_UUID="REPLACE-WITH-YOUR-BACKUP-HDD-UUID"

# Target directory (REPLACE 'hostname' with your actual hostname)
export TARGET_DIR="${BACKUP_MNT}/hostname_nvme0n1_System"

# HDD device for spindown (find with: lsblk)
export HDD_DEVICE="/dev/sdX"

# Archive name prefix (REPLACE 'hostname' with your actual hostname)
export ARCHIVE_PREFIX="hostname-nvme0n1-system"
```

**Optional adjustments:**
```bash
# Backup sources (semicolon-separated)
export BACKUP_SOURCES="/;/boot/efi"

# Excludes (semicolon-separated)
export BACKUP_EXCLUDES="/proc;/sys;/dev;/run;/tmp;/var/tmp;${BACKUP_MNT}"

# Retention policy
export KEEP_DAILY="7"
export KEEP_WEEKLY="4"
export KEEP_MONTHLY="6"

# Disable Shelly if not using
export SHELLY_ENABLED="false"
```

### Step 4: Create Borg Passphrase

```bash
# Create config directory
sudo mkdir -p /root/.config/borg

# Create passphrase file (use a strong passphrase!)
echo "your-very-secure-passphrase-here" | sudo tee /root/.config/borg/passphrase

# Secure the file
sudo chmod 600 /root/.config/borg/passphrase

# Verify
sudo cat /root/.config/borg/passphrase
```

**⚠️ IMPORTANT:** Back up this passphrase securely! Without it, your backups are unrecoverable!

### Step 5: Create Log Directory

```bash
sudo mkdir -p /var/log/extern_backup
```

### Step 6: Verify Configuration

```bash
cd /opt/backup-system
sudo ./segments/01_validate_config.sh
```

Should output:
```
[01] Configuration valid
[01] Profile: system
[01] Sources: /;/boot/efi
...
```

If errors occur, review your configuration files.

### Step 7: Test Segment Execution (Optional)

Test individual segments without running full backup:

```bash
# Test Shelly connection (if enabled)
sudo ./segments/03_shelly_power_on.sh

# Wait for device
sudo ./segments/04_wait_device.sh

# Test mount
sudo ./segments/05_mount_backup.sh

# Validate mount
sudo ./segments/06_validate_mount.sh

# Clean up
sudo ./segments/12_unmount_backup.sh
sudo ./segments/13_shelly_power_off.sh
```

### Step 8: First Manual Backup

**⚠️ This will power on your HDD and create your first backup!**

```bash
# Run backup
sudo /opt/backup-system/main.sh system

# Monitor progress (will take some time for first backup)
```

Expected output:
```
===============================================================================
  BACKUP SYSTEM v2.0.1
===============================================================================
Profile: system
Started: 2026-01-12T10:30:00+01:00
===============================================================================

[01] Validating configuration...
[01] Configuration valid
...
[08] Creating Borg backup archive...
[08] Archive created successfully
[09] Verifying backup integrity...
[09] Verification successful
...
===============================================================================
  BACKUP COMPLETED SUCCESSFULLY
===============================================================================
```

Check logs:
```bash
ls -la /var/log/extern_backup/
cat /var/log/extern_backup/system_*.log
```

### Step 9: Install systemd Units

```bash
cd /opt/backup-system/systemd
sudo ./install-systemd-units.sh
```

This installs:
- Mount and automount units
- Backup service (parametric for profiles)
- Weekly timer

### Step 10: Enable Scheduled Backups

```bash
# Enable weekly timer
sudo systemctl enable backup-system-weekly.timer

# Start timer
sudo systemctl start backup-system-weekly.timer

# Verify next run time
systemctl list-timers backup-system-weekly.timer
```

Expected output:
```
NEXT                        LEFT          LAST  PASSED  UNIT
Sun 2026-01-13 02:00:00 CET 15h left      n/a   n/a     backup-system-weekly.timer
```

---

## Post-Installation

### Test systemd Service

```bash
# Trigger backup via systemd
sudo systemctl start backup-system@system.service

# View live logs
journalctl -u backup-system@system.service -f

# Check status
sudo systemctl status backup-system@system.service
```

### Run Test Suite

```bash
cd /opt/backup-system/tests
sudo ./run_all_tests.sh system
```

### Verify Backup Contents

```bash
# List archives (after first successful backup)
sudo borg list /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo

# List files in latest archive
sudo borg list /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo::your-archive-name
```

---

## Adding Second HDD (Data Backup)

### 1. Prepare Second Profile

```bash
cd /opt/backup-system/config/profiles
sudo cp data.env.example data.env
sudo nano data.env
```

Adjust:
- `BACKUP_UUID` - UUID of second HDD
- `BACKUP_SOURCES` - What to backup
- `SHELLY_ENABLED` - Probably "false" if always-on
- `HDD_SPINDOWN_ENABLED` - Probably "false"

### 2. Add systemd Timer (Optional)

```bash
sudo nano /etc/systemd/system/backup-data-daily.timer
```

```ini
[Unit]
Description=Daily Data Backup Timer
Requires=backup-system@data.service

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:
```bash
sudo systemctl enable backup-data-daily.timer
sudo systemctl start backup-data-daily.timer
```

### 3. Test Data Backup

```bash
sudo /opt/backup-system/main.sh data
```

---

## Troubleshooting

### "Device not found"

```bash
# Check device exists
ls -la /dev/disk/by-uuid/

# Verify UUID matches config
sudo blkid

# Check Shelly is powered on
curl http://192.168.10.164/rpc/Switch.GetStatus?id=0
```

### "Mount failed"

```bash
# Check fstab entry
cat /etc/fstab | grep extern_backup

# Test manual mount
sudo mount /mnt/extern_backup

# Check systemd units
systemctl status mnt-extern_backup.automount
```

### "Unmount failed - busy"

```bash
# Find what's using the mount
sudo lsof +f -- /mnt/extern_backup

# Kill offending processes or close file managers
```

### View Detailed Logs

```bash
# Local logs
ls -la /var/log/extern_backup/
tail -f /var/log/extern_backup/system_*.log

# systemd journal
journalctl -u backup-system@system.service -n 100

# Follow live
journalctl -u backup-system@system.service -f
```

---

## Backup and Recovery

### Backup Your Backup Configuration

```bash
# Backup passphrase
sudo cp /root/.config/borg/passphrase ~/borg-passphrase-backup.txt

# Backup configs
sudo tar czf ~/backup-system-configs.tar.gz /opt/backup-system/config/
```

Store these files securely (encrypted USB, password manager, etc.)!

### Restore from Backup

See SYSTEMD.md for detailed restore procedures.

---

## Advanced: Disabling Segment 09 (Verify) for Faster Backups

### Performance Impact

**With Verify (Segment 09):**
- Duration: ~60 minutes per backup
- Full data integrity check every backup
- Recommended for: Weekly or less frequent backups

**Without Verify (Segment 09 disabled):**
- Duration: ~2 minutes per backup  
- Backup still safe, just no immediate verification
- Recommended for: Daily backups
- **Important:** Run manual verify monthly!

### How to Disable Segment 09

**⚠️ CRITICAL:** Disabling Segment 09 affects **ALL** backups (manual AND systemd)!

```bash
sudo nano /opt/backup-system/main.sh
```

Find this section (around line 40):
```bash
MAIN_SEGMENTS=(
  "01_validate_config.sh"
  "02_init_logging.sh"
  "03_shelly_power_on.sh"
  "04_wait_device.sh"
  "05_mount_backup.sh"
  "06_validate_mount.sh"
  "07_init_borg_repo.sh"
  "08_borg_backup.sh"
  "09_borg_verify.sh"      # ← Comment out this line
  "10_borg_prune.sh"
)
```

Change to:
```bash
MAIN_SEGMENTS=(
  "01_validate_config.sh"
  "02_init_logging.sh"
  "03_shelly_power_on.sh"
  "04_wait_device.sh"
  "05_mount_backup.sh"
  "06_validate_mount.sh"
  "07_init_borg_repo.sh"
  "08_borg_backup.sh"
  # "09_borg_verify.sh"    # Disabled for daily fast backups
  "10_borg_prune.sh"
)
```

**Save:** Ctrl+X, then Y, then Enter

### Manual Verification (Monthly Recommended)

**Option 1: Manual Command**
```bash
# Run once per month
sudo borg check --verify-data /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo
```

**Option 2: Monthly systemd Timer (Automated)**

Create monthly verification timer:
```bash
# Create timer
sudo tee /etc/systemd/system/backup-system-monthly-verify.timer > /dev/null << 'EOF'
[Unit]
Description=Monthly Backup Verification Timer

[Timer]
OnCalendar=*-*-01 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Create service
sudo tee /etc/systemd/system/backup-system-monthly-verify.service > /dev/null << 'EOF'
[Unit]
Description=Monthly Backup Verification
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/borg check --verify-data /mnt/extern_backup/creaThink_nvme0n1_System/borgrepo
User=root
Environment="BORG_PASSCOMMAND=cat /root/.config/borg/passphrase"
StandardOutput=journal
StandardError=journal
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable backup-system-monthly-verify.timer
sudo systemctl start backup-system-monthly-verify.timer
```

Verify:
```bash
systemctl list-timers backup-system-monthly-verify.timer
```

### Important Notes

**❌ Common Misconception:**
"Daily timer runs without verify, weekly timer runs with verify"

**✅ Reality:**
Both timers use the same `main.sh`. If Segment 09 is commented out:
- Manual backups: NO verify
- Daily timer: NO verify  
- Weekly timer: NO verify
- **ALL backups use the same configuration!**

**For different verify behavior per schedule, you need:**
1. Two separate profiles (e.g., `system.env` and `system-full.env`)
2. Two timers pointing to different profiles
3. Segment 09 enabled, but separate configs

This is an advanced setup not covered in this guide.

---

## Next Steps

1. ✅ Monitor first few scheduled backups
2. ✅ Test restore procedure (mount repo, list files)
3. ✅ Document your passphrase location
4. ✅ Set up second profile for data backup (optional)
5. ✅ Configure email notifications (see SYSTEMD.md)

---

## Support

For issues or questions:
1. Check logs: `/var/log/extern_backup/`
2. Review systemd status: `systemctl status backup-system@system.service`
3. Run tests: `sudo ./tests/run_all_tests.sh system`
4. Verify hardware: `lsblk`, `sudo hdparm -C /dev/sdc`
