# Backup System v2.0.1

Professional profile-based backup system for Ubuntu using BorgBackup with external HDD power management via Shelly Plug Plus.

## Features

- **Profile-based configuration** - Multiple backup jobs with one installation
- **13 independent segments** - Each segment is standalone and testable
- **Hardware power management** - Automatic HDD spin-up/down via Shelly Plug
- **Safe HDD shutdown** - Parks read/write heads before power-off
- **systemd integration** - Scheduled backups with timer units
- **Comprehensive testing** - Unit tests for each segment
- **Dual logging** - Local fallback + backup location
- **Mount safety** - UUID validation prevents wrong disk access

## Architecture

```
backup-system/
├── main.sh                    # Orchestrator (profile-based)
├── config/
│   ├── common.env             # Shared configuration
│   └── profiles/
│       ├── system.env         # System backup profile
│       └── data.env.example   # Template for additional profiles
├── segments/                  # 13 independent segments
│   ├── 01_validate_config.sh
│   ├── 02_init_logging.sh
│   ├── 03_shelly_power_on.sh
│   ├── 04_wait_device.sh
│   ├── 05_mount_backup.sh
│   ├── 06_validate_mount.sh
│   ├── 07_init_borg_repo.sh
│   ├── 08_borg_backup.sh
│   ├── 09_borg_verify.sh
│   ├── 10_borg_prune.sh
│   ├── 11_hdd_spindown.sh
│   ├── 12_unmount_backup.sh
│   └── 13_shelly_power_off.sh
├── tests/                     # Unit tests
│   ├── run_all_tests.sh
│   └── *.test.sh
├── systemd/                   # systemd units
│   ├── mnt-extern_backup.mount
│   ├── mnt-extern_backup.automount
│   ├── backup-system@.service
│   ├── backup-system-weekly.timer
│   └── install-systemd-units.sh
└── docs/
    ├── INSTALLATION.md        # Step-by-step installation
    └── SYSTEMD.md             # systemd configuration guide
```

## Quick Start

```bash
# 1. Extract archive
sudo unzip backup-system.zip -d /opt/

# 2. Configure system profile
sudo nano /opt/backup-system/config/profiles/system.env

# 3. Create Borg passphrase
sudo mkdir -p /root/.config/borg
echo "your-secure-passphrase" | sudo tee /root/.config/borg/passphrase
sudo chmod 600 /root/.config/borg/passphrase

# 4. Install systemd units
cd /opt/backup-system/systemd
sudo ./install-systemd-units.sh

# 5. Test manual backup
sudo /opt/backup-system/main.sh system
```

## Usage

### Manual Backup

```bash
# System backup
sudo /opt/backup-system/main.sh system

# Data backup (after configuring data.env)
sudo /opt/backup-system/main.sh data
```

### Scheduled Backup (systemd)

```bash
# Enable weekly timer
sudo systemctl enable backup-system-weekly.timer
sudo systemctl start backup-system-weekly.timer

# Check next run time
systemctl list-timers backup-system-weekly.timer

# View logs
journalctl -u backup-system@system.service
```

### Testing

```bash
# Run all tests
cd /opt/backup-system/tests
sudo ./run_all_tests.sh system
```

## Configuration

### Adding a New Profile

1. Copy template:
   ```bash
   cd /opt/backup-system/config/profiles
   sudo cp data.env.example data.env
   ```

2. Edit configuration:
   ```bash
   sudo nano data.env
   ```

3. Run backup:
   ```bash
   sudo /opt/backup-system/main.sh data
   ```

### Adjusting Timer Schedule

```bash
# Edit timer
sudo systemctl edit backup-system-weekly.timer

# Example: Change to daily at 03:00
[Timer]
OnCalendar=
OnCalendar=*-*-* 03:00:00
```

## Requirements

- Ubuntu 24.04 LTS (or compatible)
- BorgBackup (`sudo apt install borgbackup`)
- curl (`sudo apt install curl`)
- hdparm (`sudo apt install hdparm`) - for HDD spindown
- Shelly Plug Plus (optional, can be disabled)
- External HDD with ext4 filesystem

## Backup Process Flow

1. **Validate Configuration** - Check all required variables and dependencies
2. **Initialize Logging** - Set up dual logging (local + backup)
3. **Power On** - Turn on Shelly Plug (if enabled)
4. **Wait for Device** - Poll for backup device availability
5. **Mount** - Idempotently mount backup device
6. **Validate Mount** - Verify correct UUID is mounted
7. **Initialize Repository** - Create Borg repo if needed
8. **Backup** - Create Borg archive with configured sources
9. **Verify** - Full data integrity check
10. **Prune** - Remove old archives per retention policy
11. **Spindown** - Park HDD heads and spin down drive
12. **Unmount** - Safely unmount backup device
13. **Power Off** - Turn off Shelly Plug (if enabled)

## Safety Features

- **UUID validation** - Prevents accidental backup to wrong disk
- **HDD head parking** - Protects drive from damage during power-off
- **Open file handle detection** - Prevents unmount issues
- **Cleanup on failure** - Ensures safe shutdown even if backup fails
- **Comprehensive logging** - All operations logged for troubleshooting

## Documentation

- [INSTALLATION.md](docs/INSTALLATION.md) - Detailed installation instructions
- [SYSTEMD.md](docs/SYSTEMD.md) - systemd configuration and troubleshooting
- [TESTING.md](docs/TESTING.md) - Test results and validation evidence
- [SECURITY.md](docs/SECURITY.md) - Security best practices and sensitive data handling

## License

Created by Jo, 2026
For personal and professional use

## Version History

### v2.0.1 (2026-01-13)
- **CRITICAL BUGFIX:** Fixed exit code handling in segment 08
- **CRITICAL BUGFIX:** Fixed mount validation in segment 06
- Borg warnings (exit code 1) now correctly treated as success
- Multiple mount entries (systemd automount) now handled correctly
- Improved error messages

### v2.0.0 (2026-01-12)
- Initial profile-based architecture
- 13 independent segments
- systemd integration
- Comprehensive testing framework
- HDD spindown support
