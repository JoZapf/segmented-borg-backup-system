# Segmented Borg Backup System

[![Version](https://img.shields.io/badge/version-2.1.0-blue.svg)](https://github.com/JoZapf/segmented-borg-backup-system/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)](https://www.linux.org/)
[![Shell](https://img.shields.io/badge/shell-bash-89e051.svg)](https://www.gnu.org/software/bash/)
[![BorgBackup](https://img.shields.io/badge/BorgBackup-1.2%2B-00ADD8.svg)](https://borgbackup.readthedocs.io/)
[![Security](https://img.shields.io/badge/security-secrets%20management-orange.svg)](docs/SECURITY.md)

Profile-based backup orchestration for Ubuntu using BorgBackup with external HDD power management.

---

## 🎯 Key Features

- **🧩 Modular Architecture** - 13 main + 3 PRE/POST segments, independently testable
- **📋 Profile-Based** - Multiple backup configurations, one installation
- **🐳 Docker Integration** - Automated container stop/start with state preservation
- **🗄️ Database Automation** - Nextcloud DB dumps with maintenance mode & compression
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
- **[Docker & Nextcloud Backup](docs/DOCKER_NEXTCLOUD.md)** - Container & database backup guide
- **[systemd Integration](docs/SYSTEMD.md)** - Timer configuration and troubleshooting
- **[Testing Documentation](docs/TESTING.md)** - Test results and validation
- **[Security Guide](docs/SECURITY.md)** - Security best practices

---

## 🏗️ Architecture

```
backup-system/
├── main.sh                    # Orchestrator with PRE/POST support
├── config/
│   ├── common.env.example     # Shared configuration template
│   └── profiles/
│       ├── system.env.example   # System backup template
│       ├── data.env.example     # Data backup template
│       └── dev-data.env.example # Docker/Nextcloud backup template
├── segments/                  # 13 main + 3 PRE/POST segments
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
│   ├── 13_shelly_power_off.sh
│   ├── pre_01_nextcloud_db_dump.sh   # PRE: Nextcloud DB dump
│   ├── pre_02_docker_stop.sh         # PRE: Docker stop
│   └── post_01_docker_start.sh       # POST: Docker start
└── systemd/                   # systemd integration
    ├── backup-system@.service
    ├── backup-system-daily.timer
    ├── mnt-extern_backup.mount
    └── mnt-extern_backup.automount
```

---

## 🎬 How It Works

### Backup Flow

**PRE-BACKUP Phase** (Profile-specific, optional)
- **Pre-01** Nextcloud DB dump with maintenance mode (if enabled)
- **Pre-02** Docker container stop with state preservation (if enabled)

**MAIN BACKUP Phase - Part 1** (All profiles)
1. **Validate** configuration and dependencies
2. **Initialize** logging (local + backup location)
3. **Power On** external HDD via Shelly Plug
4. **Wait** for device availability
5. **Mount** backup device (with automount fallback)
6. **Validate** correct UUID is mounted (safety check!)
7. **Initialize** Borg repository (if needed)
8. **Backup** configured sources with Borg

**POST-BACKUP Phase** (Profile-specific, optional)
- **Docker container restart** (if enabled) ← Services back online!
- Time-critical cleanup runs here
- **Container downtime: Only 7-10 minutes!**

**MAIN BACKUP Phase - Part 2** (All profiles, services online!)
9. **Verify** backup integrity (full data check)
10. **Prune** old backups per retention policy

**CLEANUP Phase** (All profiles)
11. **Spindown** HDD (park heads safely)
12. **Unmount** backup device
13. **Power Off** HDD via Shelly Plug

**POST-CLEANUP Phase** (Profile-specific, optional)
- Final notifications or logging

### Why Segmented?

- ✅ **Testable** - Each segment can be tested independently
- ✅ **Maintainable** - Easy to modify or replace segments
- ✅ **Debuggable** - Clear error location in logs
- ✅ **Flexible** - Segments can be enabled/disabled
- ✅ **Reusable** - Segments can be shared across profiles
- ✅ **Profile-Specific** - PRE/POST segments run only for configured profiles

### Segment Types: Universal vs. Profile-Specific

**MAIN_SEGMENTS (Universal)** - Defined in `main.sh`  
→ Run for **ALL profiles** (system, data, dev-data)  
→ Core backup logic: mount, backup, verify, unmount  

**PRE/POST_SEGMENTS (Profile-Specific)** - Defined in `profile.env`  
→ Run **ONLY for profiles that define them**  
→ Custom actions: DB dumps, container management, notifications  

```
Profile: system.env               Profile: dev-data.env
┌─────────────────────┐          ┌─────────────────────────────────┐
│ No PRE segments     │          │ PRE_BACKUP_SEGMENTS:            │
└─────────────────────┘          │  - pre_01_nextcloud_db_dump.sh  │
         ↓                       │  - pre_02_docker_stop.sh        │
┌─────────────────────┐          └─────────────────────────────────┘
│ MAIN_SEGMENTS       │                      ↓
│  (01-13)            │◄─────────┌─────────────────────┐
│ Same for all!       │          │ MAIN_SEGMENTS       │
└─────────────────────┘          │  (01-13)            │
         ↓                       │ Same for all!       │
┌─────────────────────┐          └─────────────────────┘
│ No POST segments    │                      ↓
└─────────────────────┘          ┌─────────────────────────────────┐
                                  │ POST_CLEANUP_SEGMENTS:          │
                                  │  - post_01_docker_start.sh      │
                                  └─────────────────────────────────┘
```

**Why separate?**  
- System backup doesn't need Docker segments
- Docker backup doesn't need Shelly Plug segments  
- Each profile gets exactly what it needs

---

## 🔧 Orchestration

The `main.sh` orchestrator dynamically executes segments based on profile configuration:

```bash
# 1. Source profile config
source /opt/backup-system/config/profiles/${PROFILE}.env

# 2. Run PRE-BACKUP segments (if defined in profile)
if [ -n "${PRE_BACKUP_SEGMENTS:-}" ]; then
  for segment in "${PRE_BACKUP_SEGMENTS[@]}"; do
    execute_segment "$segment"
  done
fi

# 3. Run MAIN segments (always, for all profiles)
for segment in "${MAIN_SEGMENTS[@]}"; do
  execute_segment "$segment"
done

# 4. Run POST-CLEANUP segments (if defined in profile)
if [ -n "${POST_CLEANUP_SEGMENTS:-}" ]; then
  for segment in "${POST_CLEANUP_SEGMENTS[@]}"; do
    execute_segment "$segment"
  done
fi
```

**Result:** Profiles are modular and composable!

---

## 🔒 Security Features

### Encryption & Safety
- ✅ Encrypted backups (Borg repokey BLAKE2b)
- ✅ UUID validation prevents wrong disk writes
- ✅ Safe HDD head parking before power-off
- ✅ Comprehensive error handling
- ✅ Dual logging for audit trail

### 🔐 Secrets Management

**Protected Configuration Files:**
```bash
# Never committed to Git (protected by .gitignore)
config/common.env           # Shelly Plug IP, shared settings
config/profiles/system.env  # System backup credentials, UUIDs
config/profiles/data.env    # Data backup credentials, UUIDs
config/profiles/dev-data.env # Docker credentials, DB passwords, UUIDs
/root/.config/borg/passphrase # Borg encryption passphrase
```

**Template Files (Safe to share):**
```bash
# Committed to Git with placeholder values
config/common.env.example
config/profiles/system.env.example
config/profiles/data.env.example
config/profiles/dev-data.env.example
```

**Security Best Practices:**

1. **File Permissions** - All config files must be `600` (root only)
   ```bash
   sudo chmod 600 /opt/backup-system/config/common.env
   sudo chmod 600 /opt/backup-system/config/profiles/*.env
   sudo chmod 600 /root/.config/borg/passphrase
   ```

2. **Borg Passphrase** - Store separately and back up securely
   - Password manager (LastPass, 1Password, Bitwarden)
   - Encrypted USB drive in safe
   - Paper backup in secure location
   - **Critical:** Without passphrase, backups are unrecoverable!

3. **Sensitive Data in Configs**
   - Database passwords (Nextcloud, MariaDB, PostgreSQL)
   - Device UUIDs (backup HDD identifiers)
   - IP addresses (Shelly Plug, internal network)
   - Hostnames (system identifiers)

4. **Git Safety** - `.gitignore` protects:
   ```
   config/common.env
   config/profiles/*.env
   !config/profiles/*.example
   /root/.config/borg/passphrase
   *.key
   *.pem
   ```

**See [Security Guide](docs/SECURITY.md) for complete security documentation.**

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
