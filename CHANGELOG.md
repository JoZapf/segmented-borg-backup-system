# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.8.2] - 2026-01-26

### Changed

- **segments/05_mount_backup.sh**: v1.4.0 → v2.0.0
  - **Complete Rewrite**: Direct mount via `mount` command instead of automount triggering
  - **Issue**: systemd automount created stacked mounts (root dir + device mount at same location)
  - **Root Cause**: `x-systemd.automount` in fstab caused systemd to create overlayfs-like structure
  - **Impact**: CRITICAL - Wrong device detected, backup failures, stacked mounts at boot
  - **Solution**: Remove automount dependency, use simple direct mount
  - **Benefits**:
    - Eliminates stacked mount problem completely
    - Simpler code (50% reduction)
    - More reliable mount detection
    - Faster mount operation (no automount delay)
  - **Breaking Change**: Requires fstab modification (see Migration section)

- **fstab Configuration**: Backup mount entries updated
  - **Removed**: `x-systemd.automount` option (caused stacked mounts)
  - **Removed**: `x-systemd.idle-timeout=300` (could unmount during backup!)
  - **Added**: `noauto` option (manual mount only, no boot mount)
  - **Kept**: `x-systemd.device-timeout=30` (optional, helps with device detection)
  - **Impact**: Devices no longer mount automatically at boot
  - **Benefit**: Clean mount state, segment 05 has full control

### Fixed

- **Stacked Mounts Problem**:
  - **Symptom**: `findmnt` showed two mounts at `/mnt/extern_backup`:
    ```
    /mnt/extern_backup /dev/nvme0n1p2[/mnt/extern_backup]  ← ROOT!
    /mnt/extern_backup /dev/sdc1                           ← Device
    ```
  - **Timeline**:
    - 2026-01-26 10:04: Backup failed with "Wrong device mounted"
    - systemd created mount-point directory on root at boot
    - systemd automount layered device mount on top
    - Segment 05 detected wrong device but couldn't fix it
  - **Solution**: Remove automount, use direct mount with clean state

### Migration

**CRITICAL: Manual fstab update required!**

This update changes how backup devices are mounted. You MUST update `/etc/fstab`:

```bash
# 1. Edit fstab
sudo nano /etc/fstab

# 2. Find these lines:
UUID=9d5bdf3a-ede2-472e-a463-741836755d1b /mnt/system_backup ext4 defaults,nofail,acl,x-systemd.automount,x-systemd.device-timeout=30,x-systemd.idle-timeout=300 0 2
UUID=f2c4624a-72ee-5e4b-85f8-a0d7f02e702f /mnt/extern_backup ext4 defaults,nofail,acl,x-systemd.automount,x-systemd.device-timeout=30,x-systemd.idle-timeout=300 0 2

# 3. Replace with (remove automount, add noauto):
UUID=9d5bdf3a-ede2-472e-a463-741836755d1b /mnt/system_backup ext4 defaults,nofail,acl,noauto,x-systemd.device-timeout=30 0 2
UUID=f2c4624a-72ee-5e4b-85f8-a0d7f02e702f /mnt/extern_backup ext4 defaults,nofail,acl,noauto,x-systemd.device-timeout=30 0 2

# Optional: Remove x-systemd.device-timeout=30 for even simpler config:
UUID=9d5bdf3a-ede2-472e-a463-741836755d1b /mnt/system_backup ext4 defaults,nofail,acl,noauto 0 2
UUID=f2c4624a-72ee-5e4b-85f8-a0d7f02e702f /mnt/extern_backup ext4 defaults,nofail,acl,noauto 0 2

# 4. Save and reload
sudo systemctl daemon-reload

# 5. Test mount
sudo mount /mnt/extern_backup
findmnt /mnt/extern_backup
# Should show ONLY ONE mount line with /dev/sdc1

# 6. Update backup system
cd ~/Projekte/segmented-borg-backup-system
git pull origin main
sudo ./deploy.sh

# 7. Test backup
sudo /opt/backup-system/run-backup.sh system
```

**What changed:**
- Devices no longer auto-mount at boot (segment 05 handles mounting)
- No more systemd automount units (simpler, cleaner)
- Eliminates stacked mount issue permanently

**Rollback (if issues):**
```bash
# Revert fstab to old automount config
sudo nano /etc/fstab
# Add back: x-systemd.automount,x-systemd.device-timeout=30,x-systemd.idle-timeout=300
# Remove: noauto
sudo systemctl daemon-reload
```

## [2.8.1] - 2026-01-25

### Added

- **Mount-Point Protection**:
  - **Critical Safety Check**: Added `mountpoint -q` validation in segment 06
  - **Bind-Mount Detection**: Prevents backup to overlays or bind-mounts
  - **Immutable Flag Support**: Mount-points can be protected with `chattr +i`
  - **Issue**: Backup wrote to root filesystem when mount failed (logged as /dev/nvme0n1p2[/mnt/extern_backup])
  - **Root Cause**: Mount-point directories existed on root, no write protection
  - **Impact**: CRITICAL - Backup data accumulated on root partition, wasting space
  - **Solution**: Triple-layer protection:
    1. Mountpoint validation (exits if not a real mount)
    2. Bind-mount detection (rejects overlays)
    3. Immutable flags (prevents writes when unmounted)

- **Cleanup Tooling**:
  - **tests/cleanup_root_backup_dirs.sh**: Safe cleanup of accidentally created backup data on root
  - Features: Safety checks, size reporting, confirmation prompt, immutable flag management
  - Purpose: One-time cleanup of directories created before protection was active

- **Documentation**:
  - **DEPLOYMENT_2.8.1_mount_protection.md**: Complete deployment guide
  - **tests/MOUNT_VALIDATION_ANALYSIS_2026-01-25.md**: Root cause analysis
  - Includes troubleshooting, verification steps, rollback procedures

### Changed

- **segments/06_validate_mount.sh**: v1.0.1 → v1.1.0
  - Enhanced with critical mountpoint verification
  - Now exits with detailed error messages if mount-point is a directory on root
  - Detects and rejects bind-mounts and overlays
  - Added confirmation message: "Confirmed: [PATH] is a proper block device mount"

- **segments/12_unmount_backup.sh**: v1.2.0 → v1.3.0
  - **Fixed Race Condition**: Now checks if mount point is still active before attempting unmount
  - **Issue**: Script reported false-positive "Unmount failed" errors when systemd successfully unmounted
  - **Root Cause**: Script tried to unmount after systemd already completed unmount operation
  - **Solution**: Added `mountpoint -q` check before unmount attempt
  - **Result**: Eliminates false error messages, clearer success reporting
  - New message: "Already unmounted by systemd - backup quasi-offline (ransomware protection)"

- **systemd Timer Units**: All timer templates updated
  - **Changed**: `Persistent=true` → `Persistent=false` in all timer files
  - **Issue**: Backups ran immediately after every system boot
  - **Root Cause**: `Persistent=true` causes systemd to run missed backups on boot
  - **Impact**: Unexpected backup execution after restart, potential resource contention
  - **Files Updated**:
    - systemd/backup-system-daily.timer.example
    - systemd/backup-system-dev-data-daily.timer
    - systemd/backup-system-dev-data-daily.timer.example
    - systemd/backup-system-weekly.timer.example
  - **Behavior**: Backups now only run at scheduled times, not after boot
  - **Note**: Set `Persistent=true` manually if you want catch-up behavior

### Fixed

- **Root Filesystem Contamination**:
  - **Symptom**: system-Profile backup failed with "Wrong device mounted: /dev/nvme0n1p2[/mnt/extern_backup]"
  - **Analysis**: Mount-point existed as regular directory on root partition
  - **Timeline**: 
    - 2026-01-25 10:04: system-Backup attempted, mount failed
    - Mount validation detected wrong device but continued
    - Borg wrote backup data directly to /mnt/extern_backup on root filesystem
  - **Prevention**: New mountpoint checks abort backup before Borg can write

### Security

- **Immutable Mount-Point Protection**:
  - Mount-points can now be protected with `chattr +i /mnt/extern_backup`
  - Prevents ANY writes when device is not mounted
  - Recommended for all production deployments
  - Documented in deployment guide

### Migration

**Required for all existing installations:**

```bash
# 1. Update code
cd ~/Projekte/segmented-borg-backup-system
git pull origin main
sudo ./deploy.sh

# 2. Protect mount-points (NEW - CRITICAL)
sudo chattr +i /mnt/extern_backup
sudo chattr +i /mnt/system_backup

# 3. Clean up existing backup data on root (if present)
cd ~/Projekte/segmented-borg-backup-system/tests
chmod +x cleanup_root_backup_dirs.sh
sudo ./cleanup_root_backup_dirs.sh
# Follow prompts, type "DELETE" to confirm

# 4. Verify protection
echo "test" | sudo tee /mnt/extern_backup/test.txt
# Should fail with "Operation not permitted"

# 5. Remount devices
sudo mount -a

# 6. Test backup
sudo /opt/backup-system/run-backup.sh system
```

**Expected behavior after update:**
- Backup will ABORT with CRITICAL error if mount-point is not mounted
- This is CORRECT behavior - prevents root filesystem writes
- Check mount status before running backup

### Technical Details

**Mount Validation Sequence (segment 06):**
1. Check UUID matches expected device ✓ (existing)
2. **NEW:** Verify mount-point is actually mounted (`mountpoint -q`)
3. **NEW:** Verify source is block device (not bind-mount)
4. Check for open file handles ✓ (existing)

**Error Messages:**
- `[CRITICAL] /mnt/extern_backup is NOT a mount point!` → Mount failed, backup aborted
- `[CRITICAL] Detected bind mount or overlay` → Invalid mount type, backup aborted
- Both indicate safety mechanisms working correctly

**Recovery from Mount Failure:**
```bash
# Check Shelly status (for system-Profile)
curl http://192.168.10.164/relay/0

# Check device availability
lsblk | grep sdc1

# Manual mount if needed
sudo mount /mnt/extern_backup

# Verify mount
findmnt /mnt/extern_backup

# Retry backup
sudo /opt/backup-system/run-backup.sh system
```

## [2.7.3] - 2026-01-22

### Fixed

- **deploy.sh**:
  - **Security Fix**: Set `secrets.env` to 600 permissions (owner only)
  - **Issue**: deploy.sh set 640 (group readable), but backup system requires 600
  - **Impact**: Backup failed with "secrets.env has incorrect permissions: 640"
  - **Solution**: Added explicit `chmod 600` for secrets.env after general config permissions
  - **Security**: Prevents accidental exposure of credentials to group members

- **Version Consistency**:
  - **main.sh**: Updated version header from 2.8.0 → 2.7.3
  - **common.env**: Updated `BACKUP_SYSTEM_VERSION` from 2.8.0 → 2.7.3
  - **Issue**: Version numbers were inconsistent across files
  - **Impact**: Logs showed incorrect version 2.8.0 instead of current release
  - **Solution**: Synchronized all version numbers with CHANGELOG and README

### Changed

- **deploy.sh**:
  - Added informational message when setting secrets.env permissions
  - Improved security compliance with backup system requirements

### Migration

**Existing installations:**
```bash
# Fix permissions manually (one-time)
sudo chmod 600 /opt/backup-system/config/secrets.env

# Or redeploy to apply automatically
cd ~/Projekte/segmented-borg-backup-system
git pull
sudo ./deploy.sh
```

**No other changes required** - this is a security and consistency fix.

## [2.7.2] - 2026-01-22

### Fixed

- **segments/05_mount_backup.sh** (v1.3.0 → v1.4.0):
  - **Critical Bug**: Mount validation failed with systemd automount (x-systemd.automount in fstab)
  - **Issue**: Script checked autofs layer ("systemd-1") instead of ext4 filesystem layer
  - **Impact**: System profile backups failed with "Wrong device mounted" error even though mount was correct
  - **Root Cause**: `findmnt -o SOURCE` returns the top-most mount (autofs), not the actual device
  - **Solution**: Added `-t ext4` filter to check only ext4 layer: `findmnt -rn -t ext4 -o SOURCE`
  - **Affected**: Initial mount check (line 20) and retry validation loop (line 84)
  - **Technical Details**:
    - Automount creates TWO mount entries (normal behavior):
      - `systemd-1` (autofs) ← Auto-trigger layer
      - `/dev/sdX` (ext4) ← Actual block device
    - Old code: Tried `blkid "systemd-1"` → failed (not a block device)
    - New code: Only checks ext4 layer → validates correct device
  - **Testing**: Verified system profile with USB HDD + Shelly automount

### Changed

- **segments/05_mount_backup.sh**:
  - Added explanatory comments about autofs vs ext4 layers
  - Consistent use of `-t ext4` filter throughout validation logic
  - Improved error messages to distinguish mount layers

### Migration

**No configuration changes required** - pure bug fix for automount environments.

**Who is affected:**
- Users with `x-systemd.automount` in fstab (system profile)
- Users with external HDDs controlled by Shelly smart plugs
- Does NOT affect profiles without automount (dev-data profile works fine)

**Testing Recommendations:**
1. Power off external HDD
2. Run: `sudo /opt/backup-system/run-backup.sh system`
3. Verify: Segment 05 completes without "Wrong device mounted" warnings

## [2.7.1] - 2026-01-22

### Fixed

- **segments/12_unmount_backup.sh** (v1.1.0 → v1.2.0):
  - **Critical Bug**: Fixed hardcoded systemd unit names for dev-data profile
  - **Issue**: Error hints showed `mnt-extern_backup.automount` for all profiles
  - **Impact**: Incorrect unmount hints prevented manual recovery for dev-data backups
  - **Solution**: Dynamically derive systemd unit name from `BACKUP_MNT` variable
  - **Example**: `/mnt/system_backup` → `mnt-system_backup.automount`
  - **Affected**: All three systemd stop operations and error hint messages
  - **Testing**: Verified correct hints for both system and dev-data profiles

- **segments/pre_01_nextcloud_db_dump.sh** (v2.0.0 → v2.1.0):
  - **Bug**: DB dump cleanup only removed `.sql.gz` files, ignored `.sql` files
  - **Issue**: Old uncompressed dumps (from before compression feature) accumulated
  - **Impact**: Wasted 1.2 GB disk space per old dump
  - **Solution**: Changed pattern from `*.sql.gz` to `*.sql*` (matches both)
  - **Enhancement**: Made retention configurable via `DB_DUMP_RETENTION` variable
  - **Default**: Keep last 7 dumps (unchanged behavior)
  - **Usage**: Set `export DB_DUMP_RETENTION="14"` in profile for custom retention
  - **Logging**: Added "Retention policy" message showing configured value

### Changed

- **segments/12_unmount_backup.sh**:
  - Systemd unit derivation logic: `SYSTEMD_UNIT=$(echo "${BACKUP_MNT}" | sed 's|^/||; s|/|-|g')`
  - Applied to 3 locations: error hints (line 24), systemd stop (line 38), verify error (line 66)
  - Improved maintainability: Single point of change for mount-to-unit translation

- **segments/pre_01_nextcloud_db_dump.sh**:
  - Step 6 cleanup logic rewritten for clarity and configurability
  - Added retention policy logging for transparency
  - Better error handling for edge cases (empty directory, no matches)

### Migration

**No configuration changes required** - these are pure bug fixes.

**Optional cleanup** (recommended):
```bash
# Remove old uncompressed DB dumps manually
sudo rm /mnt/system_backup/creaThink_docker-data/database-dumps/nextcloud_db-dump_*-*-*_*-*-*.sql

# Verify cleanup
ls -lh /mnt/system_backup/creaThink_docker-data/database-dumps/
# Should only show .sql.gz files
```

**Custom retention** (optional):
```bash
# In config/profiles/dev-data.env, add:
export DB_DUMP_RETENTION="14"  # Keep 14 dumps instead of default 7
```

### Testing

**Test 1 - Segment 12 Dynamic Unit Detection:**
```bash
# Trigger unmount error (open file manager in backup dir)
nautilus /mnt/system_backup/creaThink_docker-data &
sudo /opt/backup-system/run-backup.sh dev-data

# Expected output:
# [HINT] Use: sudo systemctl stop mnt-system_backup.automount
#                                      ^^^ Correct unit name!

# Before fix showed:
# [HINT] Use: sudo systemctl stop mnt-extern_backup.automount
#                                      ^^^ Wrong for dev-data!
```

**Test 2 - DB Dump Cleanup:**
```bash
# Create test dumps
touch /tmp/test-{1..10}.sql
touch /tmp/test-{1..10}.sql.gz

# Run cleanup logic
DB_DUMP_DIR="/tmp" DB_DUMP_RETENTION=7 \
  bash -c 'old=$(ls -t /tmp/test-*.sql* | tail -n +8); echo "$old" | xargs rm -f'

# Verify: Should have exactly 7 files remaining (mixed .sql and .sql.gz)
ls -1 /tmp/test-* | wc -l  # Expected: 7
```

**Test 3 - Full Backup Run:**
```bash
# Deploy fixes to production
cd ~/Projekte/segmented-borg-backup-system
git pull
sudo rsync -av --delete segments/ /opt/backup-system/segments/

# Run backup
sudo /opt/backup-system/run-backup.sh dev-data 2>&1 | tee /tmp/bugfix-test.log

# Verify in log:
grep "Retention policy" /tmp/bugfix-test.log
# Expected: [PRE-01] Retention policy: Keep last 7 dumps

grep "Stopping systemd mount units" /tmp/bugfix-test.log -A2
# Expected: systemctl stop mnt-system_backup.automount
```

### Documentation

- Updated segment version headers with @changed timestamps
- Added inline comments explaining systemd unit derivation logic
- Enhanced cleanup step logging for troubleshooting

### Notes

- **Patch Release**: Bug fixes only, no new features or breaking changes
- **Backward Compatible**: Works with all existing configurations
- **Production Ready**: Tested on both system and dev-data profiles
- **Deployment**: Standard `git pull` + `rsync` workflow (see Migration section)

## [2.7.0] - 2026-01-21

### Added

- **config/secrets.env.example**: Template for centralized secrets management
  - All secrets (passwords, credentials, IPs) now in one file
  - Comprehensive documentation and security guidelines
  - Backup strategies explained (password manager, encrypted USB, etc.)
  - Setup instructions and verification commands

- **docs/secrets_conceptual_design_and_technical_planning.md**:
  - Technical planning document for secrets management implementation
  - Comparison of 4 solution options (Config/Secrets Split, systemd, pass, SOPS)
  - Detailed implementation plan with 5 phases
  - Migration strategy and rollback procedures
  - Security considerations and threat model
  - Testing strategy with concrete test cases

### Changed

- **main.sh** (v2.6.0 → v2.7.0):
  - **BREAKING**: Now requires `config/secrets.env` file
  - Added centralized secrets loading after profile configuration
  - Added secrets.env existence validation
  - Added permission validation (must be chmod 600)
  - Added helpful error messages with setup instructions
  - Sources secrets.env in variable export section

- **config/common.env** (v2.6.0 → v2.7.0):
  - **Removed secrets** (moved to secrets.env):
    * `SHELLY_IP` → secrets.env
    * `RECOVERY_ZIP_PASSWORD` → secrets.env
    * `BORG_PASSPHRASE_FILE` removed (now `BORG_PASSPHRASE` in secrets.env)
  - Added comments indicating where secrets moved
  - Updated @version and @changed headers
  - **Can now be safely committed to Git!**

- **config/profiles/system.env** (v2.6.0 → v2.7.0):
  - No secrets removed (didn't contain any)
  - Updated @version and description
  - **Can now be safely committed to Git!**

- **config/profiles/dev-data.env** (v1.3.0 → v1.4.0):
  - **Removed secrets** (moved to secrets.env):
    * `NEXTCLOUD_DB_PASSWORD` → secrets.env
  - Added comment indicating password location
  - Updated @version and @changed headers
  - **Can now be safely committed to Git!**

- **.gitignore**:
  - **Removed exclusions** for production config files:
    * `config/common.env` → **now tracked in Git** ✅
    * `config/profiles/system.env` → **now tracked in Git** ✅
    * `config/profiles/dev-data.env` → **now tracked in Git** ✅
  - **Added exclusion** for secrets:
    * `config/secrets.env` → **never in Git** ❌

- **README.md**:
  - Updated version badge from 2.6.0 to 2.7.0

### Removed

- **config/common.env.example** (eliminated with secrets.env approach):
  - No longer needed – production `common.env` now in Git
  - Eliminates maintenance overhead of keeping .example in sync

- **config/profiles/system.env.example** (eliminated with secrets.env approach):
  - No longer needed – production `system.env` now in Git
  - Eliminates duplication and drift between example and production

- **config/profiles/dev-data.env.example** (eliminated with secrets.env approach):
  - No longer needed – production `dev-data.env` now in Git
  - Single source of truth for configuration structure

- **BORG_PASSPHRASE_FILE** approach:
  - Previous: `/root/.config/borg/passphrase` (separate file)
  - Now: `BORG_PASSPHRASE` in `secrets.env` (centralized)
  - Simplifies secrets management (one file for all secrets)

### Security

**Centralized Secrets Management:**

All secrets now consolidated in `config/secrets.env`:
- `BORG_PASSPHRASE` (repository encryption)
- `SHELLY_IP` (hardware control)
- `NEXTCLOUD_DB_PASSWORD` (database access)
- `RECOVERY_ZIP_PASSWORD` (recovery key encryption)

**Security Improvements:**
- ✅ **Single Point of Control**: One file to secure, one file to backup
- ✅ **Clear Separation**: Configuration vs. secrets cleanly separated
- ✅ **Git Safety**: Production configs safely in Git, secrets excluded
- ✅ **Permission Enforcement**: main.sh validates chmod 600 before proceeding
- ✅ **Better Documentation**: Comprehensive backup strategies documented

**Security Requirements:**
```bash
# secrets.env must have correct permissions
chmod 600 /opt/backup-system/config/secrets.env
chown root:root /opt/backup-system/config/secrets.env

# Verify in .gitignore
grep "secrets.env" /opt/backup-system/.gitignore
# Expected: config/secrets.env
```

**Backup Strategies for secrets.env:**
1. Password Manager (BitWarden, LastPass, 1Password)
2. Encrypted USB Drive (offsite storage)
3. Encrypted Cloud Storage (GPG + Nextcloud/Dropbox)
4. Paper Copy (safe/lockbox for disaster recovery)

**⚠️ CRITICAL:** Without `secrets.env` backup, encrypted repositories are unrecoverable!

### Migration

**Automated Migration (Recommended):**

```bash
# 1. Pull latest changes (development)
cd E:\Projects\linux-backup-system
git pull

# 2. Create secrets.env from current values
cp config/secrets.env.example config/secrets.env
nano config/secrets.env  # Fill TODO with actual passphrase
chmod 600 config/secrets.env

# 3. Deploy to production
cd /opt/backup-system
sudo git pull

# 4. Copy development secrets.env to production
sudo cp E:\Projects\linux-backup-system\config\secrets.env \
  /opt/backup-system/config/secrets.env
sudo chmod 600 /opt/backup-system/config/secrets.env
sudo chown root:root /opt/backup-system/config/secrets.env

# 5. Test
sudo /opt/backup-system/run-backup.sh system --dry-run

# 6. Remove old passphrase file (optional cleanup)
sudo rm /root/.config/borg/passphrase
```

**Manual Migration Steps:**

1. **Extract current secrets:**
   ```bash
   # BORG_PASSPHRASE
   cat /root/.config/borg/passphrase
   
   # SHELLY_IP
   grep SHELLY_IP /opt/backup-system/config/common.env
   
   # NEXTCLOUD_DB_PASSWORD
   grep NEXTCLOUD_DB_PASSWORD /opt/backup-system/config/profiles/dev-data.env
   
   # RECOVERY_ZIP_PASSWORD
   grep RECOVERY_ZIP_PASSWORD /opt/backup-system/config/common.env
   ```

2. **Create secrets.env:**
   ```bash
   cd /opt/backup-system/config
   sudo cp secrets.env.example secrets.env
   sudo nano secrets.env  # Fill in extracted values
   sudo chmod 600 secrets.env
   sudo chown root:root secrets.env
   ```

3. **Verify permissions:**
   ```bash
   ls -la /opt/backup-system/config/secrets.env
   # Expected: -rw------- 1 root root ... secrets.env
   ```

4. **Test backup:**
   ```bash
   sudo /opt/backup-system/run-backup.sh system
   ```

**Rollback (if needed):**

If issues occur, restore old configuration:
```bash
# Restore config backup
sudo cp -r /opt/backup-system/config.backup-$(date +%Y%m%d) \
  /opt/backup-system/config

# Revert Git
cd /opt/backup-system
sudo git reset --hard v2.6.0

# Test
sudo /opt/backup-system/run-backup.sh system
```

### Benefits

**Deployment Workflow:**
- ✅ **Before**: Manual copy of config changes from .example to production
- ✅ **After**: `git pull` – production configs automatically updated

**Maintenance Overhead:**
- ✅ **Before**: Keep 3x `.example` files in sync with production structure
- ✅ **After**: Only 1x `secrets.env.example` to maintain

**Version Control:**
- ✅ **Before**: Production configs not in Git (only .example files)
- ✅ **After**: Production configs in Git, full change history

**Configuration Updates:**
- ✅ **Before**: Update .example, manually copy to production
- ✅ **After**: Update production config, commit, `git pull` in production

**Secret Management:**
- ✅ **Before**: Secrets scattered (common.env, dev-data.env, /root/.config)
- ✅ **After**: All secrets in `secrets.env` (single file to secure/backup)

### Testing

**Test secrets.env Missing:**
```bash
sudo mv config/secrets.env config/secrets.env.bak
sudo /opt/backup-system/run-backup.sh system
# Expected: Error with setup instructions
sudo mv config/secrets.env.bak config/secrets.env
```

**Test Wrong Permissions:**
```bash
sudo chmod 644 config/secrets.env
sudo /opt/backup-system/run-backup.sh system
# Expected: Error about incorrect permissions
sudo chmod 600 config/secrets.env
```

**Test Full Backup:**
```bash
sudo /opt/backup-system/run-backup.sh system
# Expected: Backup succeeds with secrets loaded
```

**Test Git Ignore:**
```bash
cd /opt/backup-system
git status
# Expected: secrets.env NOT shown (ignored)
# Expected: common.env, system.env, dev-data.env shown (tracked)
```

### Documentation

- **docs/secrets_conceptual_design_and_technical_planning.md**: Complete technical design
- **config/secrets.env.example**: Setup and security documentation
- **CHANGELOG.md**: Migration guide and rollback procedures

### Notes

- **Breaking Change**: Requires `secrets.env` creation before first run
- **Backward Compatible**: Old `/root/.config/borg/passphrase` still works until cleanup
- **Production Ready**: Tested migration path with rollback option
- **Security Focused**: Permission validation, backup strategies, audit logging

## [2.6.0] - 2026-01-21

### Changed

- **segments/12_unmount_backup.sh** (v1.0.0 → v1.1.0):
  - Force unmount for **ALL profiles** (security improvement)
  - dev-data profile now also unmounts backup device after completion
  - Added lazy unmount (`umount -l`) as fallback for busy filesystems
  - Improved error handling with explicit exit on unmount failure
  - Updated logging: "backup quasi-offline (ransomware protection)"

- **config/common.env** (v2.5.0 → v2.6.0):
  - Updated BACKUP_SYSTEM_VERSION from "2.5.0" to "2.6.0"
  - Updated @version header from 2.5.0 to 2.6.0
  - Updated @changed date to 2026-01-21

- **config/common.env.example** (v2.5.0 → v2.6.0):
  - Updated BACKUP_SYSTEM_VERSION from "2.5.0" to "2.6.0"
  - Updated @version header from 2.5.0 to 2.6.0
  - Updated @changed date to 2026-01-21

- **config/profiles/system.env** (v2.2.0 → v2.6.0):
  - Updated @version header from 2.2.0 to 2.6.0
  - Updated @changed date to 2026-01-21

- **config/profiles/system.env.example** (v2.2.0 → v2.6.0):
  - Updated @version header from 2.2.0 to 2.6.0
  - Updated @changed date to 2026-01-21

- **config/profiles/dev-data.env** (v1.2.0 → v1.3.0):
  - Updated @version header from 1.2.0 to 1.3.0
  - Updated @changed date to 2026-01-21

- **config/profiles/dev-data.env.example** (v1.2.0 → v1.3.0):
  - Updated @version header from 1.2.0 to 1.3.0
  - Updated @changed date to 2026-01-21
  - Aligned retention rules with production values:
    * KEEP_DAILY: 14 → 7 days
    * KEEP_WEEKLY: 8 → 4 weeks
    * KEEP_MONTHLY: 12 → 6 months
  - Updated example timeline calculation

- **main.sh** (v2.5.0 → v2.6.0):
  - Updated @version header from 2.5.0 to 2.6.0
  - Updated @changed date to 2026-01-21

- **README.md**:
  - Updated version badge from 2.5.0 to 2.6.0

### Security

**Quasi-Offline Backup Protection (All Profiles):**

Previously, only the system profile (external USB HDD) unmounted the backup device after completion, providing "air gap" protection. The dev-data profile (internal SATA HDD) kept the device mounted persistently.

**New Behavior (v2.6.0):**
- **system profile**: Unmount + Power OFF (Shelly Plug) → **TRUE AIR GAP** (physically offline)
- **dev-data profile**: Unmount (stays powered) → **QUASI-OFFLINE** (ransomware/malware cannot access)

**Security Benefits:**
- ✅ **Ransomware Protection**: Unmounted backups cannot be encrypted by malware
- ✅ **Malware Protection**: Running processes cannot access backup data
- ✅ **Accidental Deletion**: Unmounted devices protected from user errors
- ✅ **Consistent Security**: Both profiles now benefit from unmount protection

**Trade-offs:**
- dev-data: +2 seconds overhead at next backup start (remount time)
- dev-data: Manual access requires `sudo mount /mnt/system_backup` between backups

**Note:** Internal HDDs remain physically connected and powered (no true air gap possible), but filesystem-level protection significantly reduces attack surface.

### Technical Details

**Segment 12 Optimization:**

Before (v1.0.0):
```bash
# Error-tolerant execution for dev-data
umount "${BACKUP_MNT}" 2>/dev/null || true  # Failure ignored
# → Persistent mount remained active
```

After (v1.1.0):
```bash
# Force unmount for ALL profiles
if umount "${BACKUP_MNT}" 2>/dev/null; then
  echo "[12] Unmount successful"
elif umount -l "${BACKUP_MNT}" 2>/dev/null; then  # Lazy unmount fallback
  echo "[12] Lazy unmount successful"
else
  echo "[ERROR] Unmount failed"
  exit 1  # Explicit failure, no silent degradation
fi
```

**Why Universal Segment with Error Handling?**
- Simpler architecture: One segment for all profiles
- Better maintainability: Single cleanup logic
- Explicit failure: No silent degradation
- Lazy unmount: Handles busy filesystems gracefully

**Mount/Unmount Cycle:**
```
Backup Start:
  segment 05: Check if mounted → trigger automount if needed
  segment 06: Validate UUID
  
Backup End:
  segment 11: HDD spindown (hdparm -y)
  segment 12: Unmount (ALL profiles) ← NEW
  segment 13: Power OFF (system only)
  
Next Backup:
  segment 05: Remount automatically (fstab/systemd.automount)
```

### Documentation

- Updated architecture visualization (PlantUML)
- Updated PROFILES.md references to segment 12 behavior
- Updated security comparison tables

### Removed

- Obsolete `hdparm-wd-green-spindown.service` systemd service
  - HDD spindown now exclusively managed by segment 11 (part of backup script)
  - Timer-based spindown (`hdparm -S`) replaced by immediate spindown (`hdparm -y`)
  - Reason: More reliable across different HDD models (WD Green IntelliPark compatibility)

### Migration Notes

**For existing dev-data installations:**

1. **No configuration changes required** - segment 12 is universal
2. **Behavior change**: Backup device will be unmounted after each backup
3. **Manual access**: Between backups, mount manually if needed:
   ```bash
   sudo mount /mnt/system_backup
   ```
4. **Automatic remount**: Next backup automatically remounts via segment 05
5. **Security benefit**: Backup data now protected from ransomware/malware

**Compatibility:**
- ✅ Fully backward compatible
- ✅ No profile configuration changes needed
- ✅ Existing fstab entries remain valid
- ✅ No changes to system profile behavior

## [2.5.0] - 2026-01-20

### Added

- **docs/VERIFICATION.md**: Comprehensive verification and logging architecture documentation
  - Complete explanation of cryptographic integrity verification via Borg
  - Dual-logging system architecture (local + backup + systemd journal)
  - POST_BACKUP phase innovation: Why services can run during verification
  - Borg deduplication architecture explanation (verification reads repository, not source)
  - Detailed troubleshooting scenarios with resolution procedures
  - Best practices for verification cadence and monitoring
  - Alert threshold recommendations for production environments
  - All examples anonymized for general applicability

- **docs/PROFILES.md**: Profile-specific configuration strategies
  - Comparison of system profile (external USB HDD) vs dev-data profile (internal SATA HDD)
  - Mount strategies: automount vs persistent mounting
  - Cleanup strategies: unmount vs spindown-only
  - Hardware-specific considerations for different HDD types
  - Power management strategies for internal vs external storage
  - Profile design best practices and decision framework

### Changed

- **config/common.env** (v2.4.0 → v2.5.0):
  - Updated BACKUP_SYSTEM_VERSION from "2.4.0" to "2.5.0"
  - Updated @version header from 2.4.0 to 2.5.0
  - Updated @changed date to 2026-01-20

- **config/common.env.example** (v2.2.0 → v2.5.0):
  - Updated BACKUP_SYSTEM_VERSION from "2.3.0" to "2.5.0"
  - Updated @version header from 2.2.0 to 2.5.0
  - Updated @changed date to 2026-01-20

- **config/profiles/dev-data.env.example** (v1.2.0):
  - Updated @changed date to 2026-01-20
  - Simplified POST_BACKUP comment (removed redundant explanatory text)
  - Changed BACKUP_MNT default from `/mnt/extern_backup` to `/mnt/system_backup`
  - Added comment explaining internal vs external HDD mount point conventions
  - Changed HDD_DEVICE example from `/dev/sdX` to `/dev/sda`
  - Added comment explaining device path differences (internal SATA vs external USB)

- **Mount Architecture Documentation**:
  - Clarified that segment 05_mount_backup.sh (v1.3.0+) no longer executes manual `mount` commands
  - Documents device readiness checks, fstab automount triggering, and mount validation
  - Explains systemd integration benefits and elimination of duplicate mount configurations
  - Notes that actual mounting is handled entirely by fstab/systemd

### Technical Details

#### Profile-Specific Cleanup Strategies

**system profile (external USB HDD):**
- Mount strategy: `x-systemd.automount` in fstab (on-demand mounting)
- Cleanup: Full unmount after backup (segment 12)
- Power: Shelly Plug control (segment 13)
- Rationale: Power saving, physical disconnect protection

**dev-data profile (internal SATA HDD):**
- Mount strategy: Persistent mount (no automount, always available)
- Cleanup: Spindown only (segment 11), no unmount
- Power: Always powered, software-managed spindown
- Rationale: Internal HDD has no external power control, spindown sufficient
- Note: Certain HDD models with proprietary power management features may not support
  hdparm timer-based spindown (`-S` option). For these devices, immediate spindown
  (`hdparm -y`) at end of backup is recommended instead of idle timers.

#### Segment 12 Behavior

- Current implementation: Attempts to unmount using hardcoded systemd unit names
- Works correctly for: system profile (`mnt-extern_backup.{automount,mount}`)
- Gracefully degrades for: dev-data profile (no automount unit exists, mount remains active)
- Design rationale: Internal SATA HDDs benefit from persistent mounting:
  - No power-saving requirement (always powered)
  - Faster subsequent backup starts (no mount overhead)
  - Spindown (segment 11) provides adequate power management
  - Persistent mount eliminates mount/unmount cycles

#### Verification Architecture

- Service downtime: Only during backup creation (phases 1-2)
- Verification impact: Zero additional downtime (runs while services already online)
- Architecture principle: Verification reads immutable archive from repository,
  not from live source data, allowing safe parallel service operation
- Mount timing: Repository must remain mounted during verification (phase 4),
  unmount only occurs in cleanup (phase 5)

### Documentation

- **VERIFICATION.md**: Production-ready verification strategy reference
- **PROFILES.md**: Profile design and configuration decision framework
- **CHANGELOG.md**: Extended technical details for profile-specific behaviors
- All documentation uses anonymized examples and generic hardware references

### Notes

- Profile-specific cleanup strategies are intentional architectural decisions,
  not bugs or configuration errors
- Different HDD types (external USB vs internal SATA) have different optimal
  management strategies
- Persistent mounting for internal backup HDDs is recommended over automount
  when no power-saving requirement exists
- Spindown is effective power management for internal HDDs even without unmounting

## [2.4.0] - 2026-01-17

### Changed

- **System Version**: Bumped from v2.3.0 to v2.4.0 in common.env
  - Updated `BACKUP_SYSTEM_VERSION` for correct version display in logs
  
- **BREAKING**: Recovery key export moved from POST_CLEANUP to POST_BACKUP phase
  - **Reason**: POST_CLEANUP runs after HDD unmount, preventing repository access
  - **Impact**: Keys now exported while repository is still accessible
  - **Trade-off**: +5 seconds container downtime for dev-data profile (acceptable)
  
- **Segments Renamed**:
  - ❌ `post_99_export_recovery_keys.sh` → REMOVED (POST_CLEANUP timing was incorrect)
  - ✅ `post_01_export_recovery_keys.sh` → ADDED (for system profile)
  - ✅ `post_02_export_recovery_keys.sh` → ADDED (for dev-data profile, post_01 is docker_start)
  - Log prefixes updated: `[POST-01]` and `[POST-02]` instead of `[POST-99]`

- **config/profiles/system.env.example** (v2.1.0 → v2.2.0):
  - Changed `POST_CLEANUP_SEGMENTS` to `POST_BACKUP_SEGMENTS`
  - Updated recovery key export segment reference
  - Updated @changed header to reflect POST_BACKUP migration

- **config/profiles/dev-data.env.example** (v1.1.0 → v1.2.0):
  - Added `post_02_export_recovery_keys.sh` to `POST_BACKUP_SEGMENTS`
  - Recovery export now runs after docker_start but before verify
  - Updated @changed header to reflect POST_BACKUP migration

- **config/profiles/system.env.example** (v2.2.0):
  - Changed `HDD_DEVICE` to use `/dev/disk/by-id/*` instead of `/dev/sdX`
  - Improved stability: Device ID no longer changes between reboots
  - Added documentation for finding USB device by-id

- **segments/post_01_export_recovery_keys.sh** (v1.1.0 → v1.2.0):
  - Fixed passphrase handling: Now reads from BORG_PASSPHRASE_FILE correctly
  - Eliminates manual passphrase prompt during recovery key export
  
- **segments/post_02_export_recovery_keys.sh** (v1.1.0 → v1.2.0):
  - Fixed passphrase handling: Now reads from BORG_PASSPHRASE_FILE correctly
  - Eliminates manual passphrase prompt during recovery key export

### Fixed

- **Critical**: Recovery key export failing silently in POST_CLEANUP phase
  - **Root Cause**: `borg info` requires mounted repository for ID extraction
  - **Error**: "Repository not accessible" after HDD unmount in cleanup
  - **Solution**: Execute in POST_BACKUP phase while HDD is still mounted

- **Critical**: Recovery key export requesting manual passphrase input
  - **Root Cause**: BORG_PASSPHRASE_FILE not properly inherited in segment subshells
  - **Error**: "Enter passphrase for key..." prompt during automated backup
  - **Solution**: Explicitly read passphrase from file and export as BORG_PASSPHRASE
  - **Impact**: Recovery key export now fully automated, no manual intervention required

### Documentation

- **tests/RECOVERY_KEY_EXPORT_FIX.md** (v1.0 → v1.1):
  - Added UPDATE section documenting POST_BACKUP migration
  - Detailed timing analysis showing repository access requirements
  - Trade-off analysis for dev-data container downtime

### Execution Flow (New Timing)

```
[08] Borg Backup              (HDD mounted, ~7 min)
---
[POST_BACKUP Phase]:
  post_01 - Docker Start       (~30s)  ← Container back online
  post_01 - Export Keys        (~5s)   ← System profile
  post_02 - Export Keys        (~5s)   ← Dev-data profile  
---
[09] Verify                    (~7 min, container running)
[10] Prune                     (~30s, container running)
[11] HDD Spindown
[12] Unmount                   (HDD unmounted)
[13] Shelly OFF
```

### Migration Guide

**For existing installations:**

1. Update config examples (already done in v2.4.0)
2. Update production configs:
   ```bash
   # system.env:
   # Change: export POST_CLEANUP_SEGMENTS=("post_99_export_recovery_keys.sh")
   # To:     export POST_BACKUP_SEGMENTS=("post_01_export_recovery_keys.sh")
   
   # dev-data.env:
   # Change: export POST_CLEANUP_SEGMENTS=("post_99_export_recovery_keys.sh")
   # To:     export POST_BACKUP_SEGMENTS=(
   #           "post_01_docker_start.sh"
   #           "post_02_export_recovery_keys.sh"
   #         )
   ```
3. Deploy updated segments from Git
4. Remove old `post_99_export_recovery_keys.sh` from production
5. Test backup to verify key export works

## [2.3.0] - 2026-01-16

### Added

- **Automated Recovery Key Export**: New `post_99_export_recovery_keys.sh` segment
  - Automatically exports Borg repository keys after successful backups
  - Creates password-protected ZIP archives with recovery information
  - Smart detection: Only creates new exports when repository is new or keys missing
  - Prevents duplicate exports via repository ID tracking
  - ZIP filename format: `{PROFILE}_{HOSTNAME}_{REPO-ID-SHORT}_{DATE}.zip`
  - Example: `system_CREA-think_2d92c4c5_2026-01-16.zip`
  - ZIP contents:
    - `repo-key.txt`: Exported Borg repository key
    - `recovery-info.txt`: Complete recovery metadata (UUIDs, paths, credentials)
    - `RECOVERY-README.txt`: Step-by-step disaster recovery guide
  - Configurable via `common.env`:
    - `RECOVERY_ENABLED`: Enable/disable feature (default: true)
    - `RECOVERY_DIR`: Storage location for recovery archives
    - `RECOVERY_ZIP_PASSWORD`: ZIP encryption password (optional)
    - `RECOVERY_OWNER`: File ownership (e.g., "jo:jo")

### Changed

- **common.env.example** (v2.2.0 → v2.3.0):
  - Added recovery key export configuration section
  - New variables: `RECOVERY_ENABLED`, `RECOVERY_DIR`, `RECOVERY_ZIP_PASSWORD`, `RECOVERY_OWNER`
- **config/profiles/system.env.example** (v2.0.1 → v2.1.0):
  - Added `POST_CLEANUP_SEGMENTS` with recovery key export
  - Added profile-specific segments section for consistency
- **config/profiles/dev-data.env.example** (v1.0.2 → v1.1.0):
  - Added `post_99_export_recovery_keys.sh` to `POST_CLEANUP_SEGMENTS`
- **.gitignore**:
  - Added `recovery/` directory to protect exported keys
- **README.md**:
  - Added comprehensive "/opt/ vs. project directory" explanation
  - New "Installation Paths: Development vs. Production" section
  - Security rationale for separate production installation
  - Recommended workflow documentation
  - File permissions reference table
- **docs/DEPLOYMENT.md** (v1.0.0 → v1.1.0):
  - Added "Critical Concepts" section explaining .example vs production configs
  - Added detailed configuration update workflows
  - New "Example: Adding POST_BACKUP Phase" guide
  - Added "Version-Specific Migration Guides" for v2.2.0
  - New "Configuration File Workflow" section
  - Added comprehensive deployment checklist
  - Enhanced troubleshooting section

### Security

- **Recovery Archives Protection**:
  - ZIP archives can be password-protected via `RECOVERY_ZIP_PASSWORD`
  - Recovery directory excluded from Git via `.gitignore`
  - Archives contain sensitive repository keys - must be stored securely
  - File ownership configurable to restrict access

### Documentation

- Enhanced deployment documentation with config management workflows
- Added security section explaining production vs. development file locations
- Comprehensive recovery key export documentation

### Notes

- Recovery key export runs in POST_CLEANUP phase (after all backup operations)
- Repository keys are static (don't change with each backup)
- Only one export needed per repository (automatically detected)
- Passphrase must be backed up separately (not in recovery archives)
- For disaster recovery, you need BOTH repository key AND passphrase

## [2.2.0] - 2026-01-15

### Added

- **POST_BACKUP Phase**: New execution phase between backup creation and verification
  - Allows time-critical cleanup (e.g., container restart) before lengthy verify
  - Reduces container downtime from 6-10 hours to 8-12 minutes (98% reduction!)
  - Configure via `POST_BACKUP_SEGMENTS` array in profile configs
- **Logging Wrapper**: New `run-backup.sh` wrapper script for reliable file + journal logging
  - Fixes incomplete local log files
  - Ensures consistency between file logs and systemd journal
- **Documentation**: 
  - `docs/DEPLOYMENT.md`: Comprehensive deployment guide with SMB and Git workflows
  - `docs/SYSTEMD.md`: Systemd integration guide with fstab configuration examples
  - `tests/2026-01-15_mount-logging-fixes.md`: Detailed test report for this release

### Changed

- **BREAKING**: Mount configuration moved from systemd units to fstab
  - Removed manual systemd mount/automount units
  - Now relies on fstab with `x-systemd.automount` option
  - **Migration Required**: Remove old systemd units, configure fstab (see docs/SYSTEMD.md)
- **main.sh** (v2.0.0 → v2.2.0):
  - Split `MAIN_SEGMENTS` into `MAIN_SEGMENTS_PART1` (backup) and `MAIN_SEGMENTS_PART2` (verify/prune)
  - Added `POST_BACKUP_SEGMENTS` execution phase
  - Improved output formatting and status messages
- **segments/02_init_logging.sh** (v1.0.0 → v1.1.0):
  - Removed problematic `exec > >(tee ...)` redirection
  - Logging now handled by `run-backup.sh` wrapper
  - Simpler, more reliable implementation
- **segments/05_mount_backup.sh** (v1.0.0 → v1.1.0):
  - Removed explicit `mount` command
  - Now only triggers fstab automount via `ls` and verifies
  - Added better error messages with troubleshooting hints
- **segments/post_01_docker_start.sh** (v1.0.0 → v1.1.0):
  - Updated for POST_BACKUP phase usage
  - Now runs after backup but before verify
  - Improved logging messages
- **systemd/backup-system@.service**:
  - Changed `ExecStart` to use `run-backup.sh` wrapper
  - Added `/mnt/system_backup` to `ReadWritePaths`
- **systemd/backup-system-dev-data-daily.timer**:
  - Added missing `Unit=backup-system@dev-data.service` directive
  - Fixed timer activation issues
- **systemd/install-systemd-units.sh** (v1.0.0 → v1.2.0):
  - No longer installs mount/automount units
  - Added guidance for fstab configuration
  - Updated installation messages
- **config/profiles/dev-data.env.example**:
  - Moved `post_01_docker_start.sh` from `POST_CLEANUP_SEGMENTS` to `POST_BACKUP_SEGMENTS`
  - Added explanatory comments
- **docs/DOCKER_NEXTCLOUD.md**:
  - Updated with POST_BACKUP phase flow diagram
  - Updated downtime estimates (8-12 min vs 6-10 hours)
- **README.md**:
  - Updated backup flow documentation
  - Added POST_BACKUP phase explanation
- **.gitignore**:
  - Added `docs/` directory (work in progress documentation)

### Fixed

- **Mount System**: Fixed UUID validation failures caused by duplicate mount configurations
  - Issue: Wrong device mounted due to conflict between fstab and systemd units
  - Solution: Removed duplicate systemd units, rely only on fstab with automount
- **Logging System**: Fixed incomplete local log files
  - Issue: Local logs stopped after segment 02 due to `exec tee` issues in systemd
  - Solution: Created wrapper script for reliable file logging
- **Timer Activation**: Fixed dev-data timer not starting
  - Issue: Missing `Unit=` directive in timer file
  - Solution: Added proper unit reference to timer configuration

### Testing

- Verified mount system with correct UUID validation
- Verified complete logging to both file and journal
- Verified both systemd timers (system at 10:00, dev-data at 00:00) operational
- End-to-end backup test successful with all segments

## [2.0.0] - 2026-01-13

### Added

- Initial release of profile-based backup system
- Support for multiple backup profiles (system, dev-data)
- Borg backup integration with encryption
- Shelly Plug power control for external HDDs
- Systemd timer integration
- Docker container management
- Nextcloud database dump integration
- Comprehensive segment-based architecture
- UUID-based mount validation
- Dual logging (local + backup location)

### Segments

- 01_validate_config.sh: Configuration validation
- 02_init_logging.sh: Logging initialization
- 03_shelly_power_on.sh: Power on external HDD
- 04_wait_device.sh: Wait for device availability
- 05_mount_backup.sh: Mount backup device
- 06_validate_mount.sh: Validate correct device mounted
- 07_init_borg_repo.sh: Initialize or verify Borg repository
- 08_borg_backup.sh: Create backup
- 09_borg_verify.sh: Verify backup integrity
- 10_borg_prune.sh: Prune old backups
- 11_hdd_spindown.sh: Spin down HDD
- 12_unmount_backup.sh: Unmount backup device
- 13_shelly_power_off.sh: Power off external HDD
- pre_01_nextcloud_db_dump.sh: Dump Nextcloud database
- pre_02_docker_stop.sh: Stop Docker containers
- post_01_docker_start.sh: Start Docker containers

[2.2.0]: https://github.com/JoZapf/segmented-borg-backup-system/compare/v2.0.0...v2.2.0
[2.0.0]: https://github.com/JoZapf/segmented-borg-backup-system/releases/tag/v2.0.0
