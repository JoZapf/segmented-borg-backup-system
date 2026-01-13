# Changelog - Backup System

All notable changes to this project will be documented in this file.

## [2.0.1] - 2026-01-13

### Fixed
- **CRITICAL:** Fixed exit code handling in segment 08_borg_backup.sh
  - Issue: `set -e` caused script to abort on Borg exit code 1 (warnings)
  - Impact: Backups were marked as failed even when successful with warnings
  - Fix: Temporarily disable `set -e` during borg execution to properly capture exit codes
  - Borg exit codes now properly handled: 0=success, 1=warning (acceptable), 2+=error
- **CRITICAL:** Fixed mount validation in segment 06_validate_mount.sh
  - Issue: Multiple mount entries (systemd automount + fstab) caused concatenated output
  - Impact: UUID/filesystem validation failed with errors like "ext4ext4ext4" or wrong UUID detection
  - Fix: Use only first mount entry with `head -1` to handle multiple mounts correctly
  - Affects systemd-based backups where automount and manual mounts may coexist
- Improved error messages to distinguish between warnings and actual failures

### Documentation
- Updated INSTALLATION.md with wrapper script approach instead of symlink
- Clarified that SHELLY_TOGGLE_AFTER_SEC is already correctly set to 43200 (12h) in common.env

### Notes
- All backups with "file changed while we backed it up" warnings are now correctly recognized as successful
- This is expected behavior for log files and system journals during backup

## [2.0.0] - 2026-01-12

### Added
- **Profile-based architecture** - Support for multiple backup jobs with single installation
- **13 independent segments** - Modular design for maintainability
  - 01_validate_config.sh - Configuration validation
  - 02_init_logging.sh - Dual logging setup
  - 03_shelly_power_on.sh - HDD power management
  - 04_wait_device.sh - Device availability polling
  - 05_mount_backup.sh - Idempotent mounting
  - 06_validate_mount.sh - UUID safety verification
  - 07_init_borg_repo.sh - Repository initialization
  - 08_borg_backup.sh - Archive creation
  - 09_borg_verify.sh - Data integrity check
  - 10_borg_prune.sh - Retention policy enforcement
  - 11_hdd_spindown.sh - Safe HDD shutdown
  - 12_unmount_backup.sh - Clean unmount
  - 13_shelly_power_off.sh - Power-off management
- **systemd integration**
  - Mount and automount units
  - Parametric service for profiles
  - Timer-based scheduling
  - Resource limits and security hardening
- **Comprehensive testing framework**
  - Unit tests for each segment
  - Test runner with result collection
  - Hardware validation tests
- **HDD head parking** - Safe spindown before power-off
- **Dual logging** - Local fallback + backup location
- **Complete documentation**
  - README.md - Overview and quick start
  - INSTALLATION.md - Step-by-step setup
  - SYSTEMD.md - Advanced systemd configuration

### Changed
- Restructured from monolithic script to modular segments
- Enhanced error handling with per-segment validation
- Improved mount safety with UUID verification
- Separated concerns for better maintainability

### Security
- Added UUID validation to prevent wrong disk access
- Implemented open file handle detection
- Added HDD head parking before power-off
- systemd security hardening (ProtectSystem, PrivateTmp, resource limits)

### Configuration
- `config/common.env` - Shared configuration
- `config/profiles/system.env` - System backup profile
- `config/profiles/data.env.example` - Template for additional profiles

### Infrastructure
- `/opt/backup-system` - Standard installation path
- `/var/log/extern_backup` - Centralized logging
- `/etc/systemd/system` - systemd unit files

## [1.0.0] - 2025-XX-XX

### Initial Implementation
- Monolithic backup script
- Basic Borg integration
- Shelly Plug power control
- Manual execution only
- System partition backup

---

## Future Enhancements

### Planned for v2.1.0
- [ ] Email notifications for backup status
- [ ] Backup integrity monitoring dashboard
- [ ] Remote backup support (rsync, rclone)
- [ ] Web UI for configuration and monitoring
- [ ] Automated restore testing

### Planned for v2.2.0
- [ ] Cloud backup integration (S3, B2)
- [ ] Incremental backup to multiple destinations
- [ ] Backup encryption key rotation
- [ ] Advanced retention policies (GFS)
- [ ] Backup performance metrics

### Planned for v3.0.0
- [ ] Multi-server support
- [ ] Centralized backup management
- [ ] Real-time backup monitoring
- [ ] Automated disaster recovery
- [ ] Compliance reporting

---

## Version History Summary

| Version | Date | Key Features |
|---------|------|--------------|
| 2.0.1 | 2026-01-13 | Bugfix: Exit code handling |
| 2.0.0 | 2026-01-12 | Profile-based, modular, systemd, testing |
| 1.0.0 | 2025-XX-XX | Initial monolithic implementation |

---

## Breaking Changes

### v2.0.0
- Complete restructure - not compatible with v1.0.0
- New configuration format (profile-based)
- New installation path (`/opt/backup-system`)
- systemd units required for scheduled backups
- Migration from v1.0.0 requires manual reconfiguration

---

## Upgrade Notes

### From v2.0.0 to v2.0.1

**Simple update - no configuration changes required:**

1. Update file: `segments/08_borg_backup.sh`
2. No other changes needed
3. Existing backups remain valid
4. Next backup will correctly handle warnings

### From v1.0.0 to v2.0.0

**Not a direct upgrade - requires fresh installation:**

1. Back up v1.0.0 configuration
2. Install v2.0.0 following INSTALLATION.md
3. Migrate settings to new profile format
4. Existing Borg repositories are compatible (no re-backup needed)
5. Test thoroughly before removing v1.0.0

---

## Author

Created by Jo
Berlin, Germany
2026

## License

For personal and professional use
