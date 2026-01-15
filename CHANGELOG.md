# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
