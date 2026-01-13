# Segmented Borg Backup System

[![Version](https://img.shields.io/badge/version-2.0.1-blue.svg)](https://github.com/JoZapf/segmented-borg-backup-system/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)](https://www.linux.org/)
[![Shell](https://img.shields.io/badge/shell-bash-89e051.svg)](https://www.gnu.org/software/bash/)
[![BorgBackup](https://img.shields.io/badge/BorgBackup-1.2%2B-00ADD8.svg)](https://borgbackup.readthedocs.io/)

Profile-based backup orchestration for Ubuntu using BorgBackup with external HDD power management.

---

## 🎯 Key Features

- **🧩 Modular Architecture** - 13 independent, testable segments
- **📋 Profile-Based** - Multiple backup configurations, one installation
- **⚡ Hardware Integration** - Shelly Plug power management for external HDDs
- **🔒 Safe HDD Shutdown** - Automatic head parking and spindown
- **⏰ systemd Integration** - Scheduled backups with timer units
- **✅ Production-Ready** - Comprehensive testing and error handling
- **📊 Dual Logging** - Local and backup location logging
- **🛡️ UUID Validation** - Prevents accidental backup to wrong disk

---

## 📦 Quick Start

```bash
# 1. Clone repository
git clone https://github.com/JoZapf/segmented-borg-backup-system.git
cd segmented-borg-backup-system

# 2. Copy example configurations
sudo cp config/common.env.example config/common.env
sudo cp config/profiles/system.env.example config/profiles/system.env

# 3. Edit configurations (adjust UUID, hostname, etc.)
sudo nano config/common.env
sudo nano config/profiles/system.env

# 4. Create Borg passphrase
sudo mkdir -p /root/.config/borg
echo "your-secure-passphrase" | sudo tee /root/.config/borg/passphrase
sudo chmod 600 /root/.config/borg/passphrase

# 5. Install to /opt
sudo mkdir -p /opt/backup-system
sudo cp -r * /opt/backup-system/

# 6. Install systemd units
cd /opt/backup-system/systemd
sudo ./install-systemd-units.sh

# 7. Test manual backup
sudo /opt/backup-system/main.sh system
```

---

## 📚 Documentation

- **[Full Documentation](docs/README.md)** - Complete feature overview
- **[Installation Guide](docs/INSTALLATION.md)** - Detailed setup instructions  
- **[systemd Integration](docs/SYSTEMD.md)** - Timer configuration and troubleshooting
- **[Testing Documentation](docs/TESTING.md)** - Test results and validation
- **[Security Guide](docs/SECURITY.md)** - Security best practices

---

## 🏗️ Architecture

```
backup-system/
├── main.sh                    # Orchestrator
├── config/
│   ├── common.env.example     # Shared configuration template
│   └── profiles/
│       ├── system.env.example # System backup template
│       └── data.env.example   # Data backup template
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
└── systemd/                   # systemd integration
    ├── backup-system@.service
    ├── backup-system-daily.timer
    ├── mnt-extern_backup.mount
    └── mnt-extern_backup.automount
```

---

## 🎬 How It Works

### Backup Flow

1. **Validate** configuration and dependencies
2. **Initialize** logging (local + backup location)
3. **Power On** external HDD via Shelly Plug
4. **Wait** for device availability
5. **Mount** backup device (with automount fallback)
6. **Validate** correct UUID is mounted (safety check!)
7. **Initialize** Borg repository (if needed)
8. **Backup** configured sources with Borg
9. **Verify** backup integrity (full data check)
10. **Prune** old backups per retention policy
11. **Spindown** HDD (park heads safely)
12. **Unmount** backup device
13. **Power Off** HDD via Shelly Plug

### Why Segmented?

- ✅ **Testable** - Each segment can be tested independently
- ✅ **Maintainable** - Easy to modify or replace segments
- ✅ **Debuggable** - Clear error location in logs
- ✅ **Flexible** - Segments can be enabled/disabled
- ✅ **Reusable** - Segments can be shared across profiles

---

## 🔒 Security Features

- ✅ Encrypted backups (Borg repokey BLAKE2b)
- ✅ UUID validation prevents wrong disk writes
- ✅ Safe HDD head parking before power-off
- ✅ Config files excluded from Git (.gitignore)
- ✅ Comprehensive error handling
- ✅ Dual logging for audit trail

---

## 🛠️ Requirements

- Ubuntu 24.04 LTS (or compatible)
- BorgBackup (`sudo apt install borgbackup`)
- curl (`sudo apt install curl`)
- hdparm (`sudo apt install hdparm`) - for HDD spindown
- Shelly Plug Plus (optional, can be disabled)
- External HDD with ext4 filesystem

---

## 📜 License

MIT License - see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- [BorgBackup](https://borgbackup.readthedocs.io/) - The excellent deduplicating backup program

---

## ⭐ Star this repository if you find it useful!

**Questions? Issues? [Open an issue](https://github.com/JoZapf/segmented-borg-backup-system/issues)!**
