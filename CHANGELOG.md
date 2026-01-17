# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

### Fixed

- **Critical**: Recovery key export failing silently in POST_CLEANUP phase
  - **Root Cause**: `borg info` requires mounted repository for ID extraction
  - **Error**: "Repository not accessible" after HDD unmount in cleanup
  - **Solution**: Execute in POST_BACKUP phase while HDD is still mounted

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
