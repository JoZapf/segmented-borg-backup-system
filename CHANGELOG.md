# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.9.0] - 2026-02-09

### Fixed

- **CRITICAL**: Fixed execution order - PRE segments ran before backup target was mounted
  - **Issue (dev-data)**: `pre_01_nextcloud_db_dump.sh` failed with `mkdir: Vorgang nicht zulässig` because TARGET_DIR was not yet mounted
  - **Root Cause**: PRE_BACKUP_SEGMENTS executed before segments 03-06 (Shelly, device-wait, mount, validate-mount)
  - **Solution**: New `EARLY_SEGMENTS` phase (01-06) runs before PRE_BACKUP_SEGMENTS

- **CRITICAL**: Fixed systemd automount creating root-filesystem bind mounts at backup mountpoints
  - **Issue (system)**: `/dev/nvme1n1p2` (root FS) was bound to `/mnt/extern_backup`, blocking the real backup device
  - **Root Cause**: `x-systemd.automount` in fstab triggered before USB HDD was available (Shelly off), systemd created fallback bind mount from root FS
  - **Solution**: Removed automount from fstab, masked automount unit, added detection in code

### Changed

- **main.sh**: v2.8.3 → v2.9.0
  - **New**: `EARLY_SEGMENTS` array (segments 01-06) executes before `PRE_BACKUP_SEGMENTS`
  - **Changed**: `MAIN_SEGMENTS_PART1` now contains only segments 07-08 (Borg init + backup)
  - **New execution order**: EARLY → PRE_BACKUP → MAIN_PART1 → POST_BACKUP → MAIN_PART2 → CLEANUP

- **segments/05_mount_backup.sh**: v2.1.0 → v2.2.0
  - **New**: Root-filesystem detection in `safe_unmount()` - skips expensive `fuser` analysis when root FS is mounted at backup point (previously listed 400+ system processes)
  - **New**: Stacked mount detection (Phase 0) in `validate_and_mount()` - detects and resolves multiple devices on same mountpoint before normal validation
  - **New**: Recovery instructions for systemd automount misconfiguration

- **segments/pre_01_nextcloud_db_dump.sh**: v2.1.0 → v2.2.0
  - **New**: UUID validation before `mkdir -p` on TARGET_DIR (defense-in-depth)
  - Verifies TARGET_DIR is on expected backup filesystem via `findmnt` + `blkid`
  - Prevents writing to wrong mount (e.g. root filesystem or unmounted autofs layer)

### Infrastructure (Production System)

- **fstab**: Removed `x-systemd.automount` and `x-systemd.idle-timeout`, added `noauto` for extern_backup
- **systemd**: Masked `mnt-extern_backup.automount` (generator kept recreating it despite fstab fix)
- **systemd**: Disabled and stopped `mnt-system_backup.automount` + `mnt-system_backup.mount`

### Documentation

- **docs/fehleranalyse_2026-02-09.md**: Complete root cause analysis (German) with error logs, architecture diagrams, and 5 prioritized solution measures

### Migration

**Code update (automatic):**
```bash
cd ~/Projekte/segmented-borg-backup-system
git pull origin main
```

**Production system (manual, already applied 2026-02-09):**
```bash
# 1. Fix fstab - remove automount for extern_backup
sudo sed -i 's|x-systemd.automount,||; s|,x-systemd.idle-timeout=300||' /etc/fstab
# Add noauto if not present

# 2. Mask automount unit
sudo systemctl mask mnt-extern_backup.automount

# 3. Disable system_backup automount
sudo systemctl disable --now mnt-system_backup.automount
sudo systemctl disable --now mnt-system_backup.mount

# 4. Reload
sudo systemctl daemon-reload

# 5. Verify
systemctl status mnt-extern_backup.automount  # Should show "masked"
findmnt -t autofs  # Should be empty for backup mounts
```

---

## [2.8.3] - 2026-02-04

### Fixed

- **CRITICAL**: Fixed hard abort on "already mounted" error in mount/unmount segments
  - **Issue**: Race conditions and stale mounts caused backup failures with no recovery
  - **Root Cause**: Simple unmount logic with hard exits, no retry mechanism
  - **Impact**: Backup aborted on first mount/unmount error, requiring manual intervention
  - **Solution**: Implemented multi-stage error recovery with process safety

### Changed

- **segments/05_mount_backup.sh**: v2.0.0 → v2.1.0 (backward compatible)
  - **Enhanced**: Added multi-stage mount error recovery (backward compatible)
  - **API**: External interface unchanged - accepts same inputs, provides same outputs
  - **New Features**:
    - Multi-stage unmount recovery (normal → force → lazy → process termination)
    - Intelligent "already mounted" error handling with UUID verification
    - Try-catch-like error recovery instead of immediate exit on error
    - Process blacklist for critical process protection
    - Enhanced debugging output with detailed recovery instructions
  - **Helper Functions**:
    - `safe_unmount()`: 4-stage unmount with escalating force levels
    - `validate_and_mount()`: Comprehensive 4-phase mount validation
  - **Process Safety**:
    - Blacklist prevents killing critical processes (borg, docker, databases)
    - Safety abort if protected processes block mount
    - Manual intervention instructions provided
  - **Error Handling**:
    - Detects and recovers from wrong device mounts
    - No longer aborts on spurious "already mounted" errors
    - Validates mount state after every operation
    - Provides actionable recovery steps on failure
  - **Debugging**:
    - Process blocking detection (lsof + fuser)
    - Detailed mount state analysis
    - Concrete recovery commands for users

- **segments/12_unmount_backup.sh**: v1.3.0 → v2.0.0 (BREAKING CHANGE)
  - **Complete Rewrite**: Cleanup-safe unmount with soft-fail behavior
  - **BREAKING**: Exit behavior changed - now always returns exit 0 in cleanup context
    - Ensures HDD spindown (segment 11) always executes
    - Ensures Shelly power-off (segment 13) always executes
    - Warnings instead of errors for unmount failures
  - **New Features**:
    - Same multi-stage unmount recovery as segment 05
    - Same process blacklist for safety
    - Cleanup-safe mode (always returns exit 0)
    - Informational-only process analysis in cleanup context
  - **Helper Function**:
    - `safe_unmount_cleanup()`: Cleanup-optimized version of safe_unmount
  - **Behavior**:
    - Attempts all unmount strategies (normal → force → lazy → analyze)
    - Never kills processes in cleanup context
    - Provides informational messages about blocking processes
    - Device remains mounted if all attempts fail (non-critical in cleanup)
    - System will auto-unmount on reboot

### Security

- **Process Blacklist Protection**:
  - Protected processes: `borg`, `docker`, `dockerd`, `containerd`, `mysql`, `mysqld`, 
    `postgres`, `mongod`, `redis-server`, `systemd`, `rsync`
  - Prevents accidental termination of critical backup/database processes
  - Safety abort if protected processes would be killed
  - Manual intervention required for protected processes

- **Cleanup Safety**:
  - Segment 12 now never aborts, ensuring cleanup always completes
  - HDD spindown and power-off execute even if unmount fails
  - Non-critical warnings instead of critical errors

### Technical Details

#### Mount Recovery Stages (Segment 05)

**Stage 1 - Graceful Unmount:**
- 3 attempts with 2-second waits
- Shows blocking processes (lsof)
- Non-destructive

**Stage 2 - Force Unmount:**
- `umount -f` if stage 1 fails
- Attempts to force busy filesystems

**Stage 3 - Lazy Unmount:**
- `umount -l` as fallback
- Detaches immediately, kernel cleans up later
- Safe for most cases

**Stage 4 - Intelligent Process Termination:**
- Analyzes blocking processes via fuser
- Checks against blacklist
- **Protected processes → Safety abort with manual instructions**
- **Safe processes → Graceful termination (SIGTERM → SIGKILL)**

#### Unmount Recovery Stages (Segment 12)

Same 4-stage approach as segment 05, but with cleanup-safe behavior:
- All stages attempt unmount
- Stage 4 analyzes processes but **never kills** in cleanup context
- Always returns exit 0 (success)
- Warnings instead of errors

#### Error Recovery Flow

```
Mount/Unmount Error
  ↓
Stage 1: Normal umount (3 attempts)
  ↓ failed
Stage 2: Force umount (-f)
  ↓ failed
Stage 3: Lazy umount (-l)
  ↓ failed
Stage 4: Process Analysis
  ↓
  ├─ Protected process? (borg, docker, mysql, etc.)
  │    └─ Safety Abort + Manual Instructions
  │
  └─ Safe process? (bash, vim, tail, etc.)
       ├─ Segment 05: Kill processes + retry
       └─ Segment 12: Warn only (cleanup-safe)
```

#### "Already Mounted" Error Handling

**Before:**
```bash
mount command failed: "already mounted"
→ exit 1  # Hard abort
```

**After:**
```bash
mount error: "already mounted"
→ Verify which device is mounted
  ├─ Correct UUID? → Success (continue)
  └─ Wrong UUID? → Error with details
```

### Documentation

- **docs/MOUNT_FIX_DETAILED.md**: Complete technical analysis and implementation guide
  - Problem analysis with actual error logs
  - Multi-stage recovery concept explanation
  - Try-catch-like error handling patterns
  - Testing strategy with concrete scenarios
  - Deployment guide with rollback procedures

- **docs/PROCESS_TERMINATION_EXPLAINED.md**: Process handling safety guide
  - Distinction: "Gekillt" (forced) vs "Gestoppt" (graceful)
  - Docker container management (Pre/Post-segments vs emergency kill)
  - Process blacklist rationale and examples
  - Critical process protection scenarios
  - Safety abort behavior with recovery instructions

### Migration

**Automatic migration (recommended):**

```bash
# 1. On Windows development system
cd E:\Projects\linux-backup-system
git pull

# 2. Deploy to Ubuntu production
cd /opt/backup-system
sudo git pull

# Or copy segments manually
sudo rsync -av E:\Projects\linux-backup-system\segments\ \
  /opt/backup-system/segments\

# 3. Set permissions
sudo chmod +x /opt/backup-system/segments/*.sh

# 4. Test single segment
sudo /opt/backup-system/segments/05_mount_backup.sh

# 5. Test full backup
sudo /opt/backup-system/run-backup.sh system
```

**Manual verification:**

```bash
# Verify segment versions
grep "@version" /opt/backup-system/segments/05_mount_backup.sh
# Expected: @version 2.2.0

grep "@version" /opt/backup-system/segments/12_unmount_backup.sh
# Expected: @version 2.0.0

# Test mount segment behavior
sudo /opt/backup-system/segments/05_mount_backup.sh
# Should complete without errors

# Monitor backup logs
sudo tail -f /var/log/extern_backup/*.log
```

**No configuration changes required** - these are pure segment improvements.

### Testing Scenarios

**Test 1 - Wrong Device Mounted:**
```bash
# Simulate wrong device
sudo umount /mnt/extern_backup 2>/dev/null || true
sudo mount /dev/nvme0n1p2 /mnt/extern_backup

# Run segment 05
sudo /opt/backup-system/segments/05_mount_backup.sh

# Expected:
# [WARN] Wrong device detected
# [05] Safe unmount: /mnt/extern_backup
# [05] Unmount attempt 1/3 (normal)...
# [05] ✓ Unmounted successfully (graceful)
# [05] Mounting device via fstab...
# [05] ✓ Mount command successful
# [05] ✓ Backup device mounted and validated
```

**Test 2 - Process Blocking Mount:**
```bash
# Simulate blocking process
cd /mnt/extern_backup
# (keep terminal open in mount point)

# Run segment 05 from another terminal
sudo /opt/backup-system/segments/05_mount_backup.sh

# Expected:
# [05] Warning: 1 process(es) blocking unmount
# [SAFE] ✓ Can terminate: bash (PID: xxx)
# [WARN] Terminating PID xxx (SIGTERM)...
# [05] ✓ Unmounted after graceful termination
```

**Test 3 - Critical Process Blocking:**
```bash
# Simulate borg running
borg create /mnt/extern_backup/test-repo::test &
BORG_PID=$!

# Run segment 05
sudo /opt/backup-system/segments/05_mount_backup.sh

# Expected:
# [CRITICAL] ⛔ Protected process found: borg
# ===============================================================================
#  CRITICAL PROCESSES DETECTED - SAFETY ABORT
# ===============================================================================
#  - PID xxx: borg (PROTECTED)
#  ⚠️ WILL NOT KILL THESE PROCESSES AUTOMATICALLY!
# [Manual intervention instructions...]

kill $BORG_PID
```

**Test 4 - Cleanup with Unmount Failure:**
```bash
# Simulate cleanup with blocking process
cd /mnt/extern_backup

# Run segment 12
sudo /opt/backup-system/segments/12_unmount_backup.sh

# Expected:
# [12] Unmount attempt 1/3 (normal)...
# [WARN] All unmount attempts failed
# [WARN] Device remains mounted but backup completed successfully
# [WARN] System will auto-unmount on reboot
# (exits with 0 - cleanup continues)
```

### Rollback

If issues occur, rollback to v2.8.2:

```bash
# Backup current version
cd /opt/backup-system
sudo cp segments/05_mount_backup.sh segments/05_mount_backup.sh.v2.2.0
sudo cp segments/12_unmount_backup.sh segments/12_unmount_backup.sh.v2.0.0

# Restore from Git
sudo git reset --hard v2.8.2

# Or restore from backup
sudo cp segments/05_mount_backup.sh.backup segments/05_mount_backup.sh
sudo cp segments/12_unmount_backup.sh.backup segments/12_unmount_backup.sh

# Test
sudo /opt/backup-system/run-backup.sh system
```

### Performance

- **Overhead**: +2-3 seconds per mount operation (multi-stage retries)
- **Recovery Time**: 0-10 seconds depending on stage reached
- **Normal Case**: No overhead (stage 1 succeeds immediately)
- **Cleanup**: Always completes (no blocking on unmount failure)

### Benefits

**Robustness:**
- ✅ No more hard aborts on transient mount errors
- ✅ Automatic recovery from stale mounts
- ✅ Graceful handling of "already mounted" errors
- ✅ Protection against killing critical processes

**Debugging:**
- ✅ Detailed error messages with root cause analysis
- ✅ Concrete recovery commands (copy-paste ready)
- ✅ Process blocking detection and reporting
- ✅ Mount state validation after every step

**Safety:**
- ✅ Critical processes never killed automatically
- ✅ Cleanup always completes (HDD spindown + power-off)
- ✅ Manual intervention for protected processes
- ✅ Soft failures in cleanup context

### Breaking Changes

**Segment 12 only** - exit code behavior changed for cleanup safety:

- **Segment 05**: No breaking changes (backward compatible)
  - Same inputs: BACKUP_MNT, BACKUP_DEV, BACKUP_UUID
  - Same outputs: exit 0 (success) or exit 1 (failure)
  - Enhanced internal error recovery does not affect external API

- **Segment 12**: Exit behavior changed (BREAKING)
  - Old: exit 1 on unmount failure (aborts cleanup)
  - New: exit 0 always (cleanup continues)
  - Impact: HDD spindown and power-off now always execute

### Known Issues

**None** - this release specifically fixes the mount/unmount failure issues.

### Next Steps

Recommended follow-up tasks:
1. Monitor first few backups after update
2. Check `/var/log/extern_backup/*.log` for any warnings
3. Consider enabling `DEBUG=1` for verbose logging if issues occur
4. Document any edge cases encountered

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

- **USB Autosuspend Issue** (discovered during v2.8.2 testing):
  - **Symptom**: External USB backup devices disconnect during backup with I/O errors
  - **Timeline**:
    - 2026-01-26 17:04: Backup failed during Segment 08 (Borg create)
    - USB reset after 43 seconds, followed by disconnect 11 seconds later
    - EXT4 errors: "Cannot read block bitmap", "I/O error while writing superblock"
    - Device completely disappeared from system during cleanup
  - **Root Cause**: Kernel USB autosuspend (default: 2 seconds) suspends USB device while Borg buffers data in memory
  - **Analysis**:
    - Borg writes data in chunks with buffering between writes
    - Kernel detects >2s idle period → suspends USB device
    - Borg attempts next write → USB device needs wake-up
    - USB resume fails → I/O errors → complete disconnect
  - **Solution**: Disable USB autosuspend via kernel parameter
  - **Fix**: Add to `/etc/default/grub`:
    ```bash
    # Edit GRUB configuration
    sudo nano /etc/default/grub
    
    # Modify GRUB_CMDLINE_LINUX_DEFAULT line:
    GRUB_CMDLINE_LINUX_DEFAULT="quiet splash usbcore.autosuspend=-1"
    
    # Update GRUB and reboot
    sudo update-grub
    sudo reboot
    ```
  - **Verification**: `cat /sys/module/usbcore/parameters/autosuspend` should show `-1` (disabled)
  - **Immediate Workaround** (without reboot):
    ```bash
    # Disable autosuspend temporarily (until next reboot)
    echo -1 | sudo tee /sys/module/usbcore/parameters/autosuspend
    
    # Disable for all currently connected USB devices
    for device in /sys/bus/usb/devices/*/power/control; do
      echo on | sudo tee $device 2>/dev/null || true
    done
    ```
  - **Note**: This is a system-level configuration, not a code change. Affects all USB devices on the system.

### Migration

**CRITICAL: Manual fstab update required!**

This update changes how backup devices are mounted. You MUST update `/etc/fstab`:

```bash
# 1. Edit fstab
sudo nano /etc/fstab

# 2. Find these lines (replace UUIDs with your actual device UUIDs):
UUID=YOUR-INTERNAL-HDD-UUID /mnt/system_backup ext4 defaults,nofail,acl,x-systemd.automount,x-systemd.device-timeout=30,x-systemd.idle-timeout=300 0 2
UUID=YOUR-EXTERNAL-HDD-UUID /mnt/extern_backup ext4 defaults,nofail,acl,x-systemd.automount,x-systemd.device-timeout=30,x-systemd.idle-timeout=300 0 2

# 3. Replace with (remove automount, add noauto):
UUID=YOUR-INTERNAL-HDD-UUID /mnt/system_backup ext4 defaults,nofail,acl,noauto,x-systemd.device-timeout=30 0 2
UUID=YOUR-EXTERNAL-HDD-UUID /mnt/extern_backup ext4 defaults,nofail,acl,noauto,x-systemd.device-timeout=30 0 2

# Optional: Remove x-systemd.device-timeout=30 for even simpler config:
UUID=YOUR-INTERNAL-HDD-UUID /mnt/system_backup ext4 defaults,nofail,acl,noauto 0 2
UUID=YOUR-EXTERNAL-HDD-UUID /mnt/extern_backup ext4 defaults,nofail,acl,noauto 0 2

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

[Rest of CHANGELOG continues unchanged...]
