# Backup Profiles Guide

## Overview

Profiles allow multiple backup configurations to coexist in a single installation. Each profile defines what to backup, where to backup, and how to backup.

---

## Available Profiles

### system - System Partition Backup
**Purpose:** Backs up root filesystem and boot partition  
**Use Case:** System recovery, OS migration, disaster recovery  
**Target:** External HDD via Shelly Plug  
**Schedule:** Weekly (default)

**Sources:**
- `/` (root filesystem)
- `/boot/efi` (EFI partition)

**Excludes:**
- `/proc`, `/sys`, `/dev` (pseudo-filesystems)
- `/run`, `/tmp` (temporary data)
- Backup mount point itself

**Retention:**
- 7 daily archives
- 4 weekly archives  
- 6 monthly archives

**Hardware:**
- Shelly Plug: Enabled
- HDD Spindown: Enabled

---

### data - User Data Backup
**Purpose:** Backs up user files and documents  
**Use Case:** Personal files, photos, documents  
**Target:** Secondary external HDD or NAS  
**Schedule:** Daily (optional)

**Sources:**
- `/home` (user directories)
- `/opt` (optional applications)
- `/srv` (service data)

**Retention:**
- 14 daily archives
- 8 weekly archives
- 12 monthly archives

**Hardware:**
- Shelly Plug: Optional (depends on HDD type)
- HDD Spindown: Optional

---

### dev-data - Docker & Nextcloud Backup
**Purpose:** Backs up Docker containers with Nextcloud database dumps  
**Use Case:** Development environments, self-hosted services  
**Target:** Internal HDD (always-on)  
**Schedule:** Daily at 02:00 (recommended)

**Sources:**
- `/mnt/docker-data` (Docker volumes)

**Special Features:**
- **PRE-BACKUP:** Nextcloud DB dump with maintenance mode
- **PRE-BACKUP:** Docker container graceful stop
- **POST-CLEANUP:** Docker container restart

**Retention:**
- 14 daily archives
- 8 weekly archives
- 12 monthly archives

**Hardware:**
- Shelly Plug: Disabled (internal HDD)
- HDD Spindown: Enabled

**Additional Artifacts:**
- Database dumps: `TARGET_DIR/database-dumps/`
- Keeps last 7 dumps
- Compression: ~84% (gzip)

---

## Segment Architecture: MAIN vs. PRE/POST

### Where Segments Are Defined

**MAIN_SEGMENTS** - Defined in `main.sh` (universal)
```bash
# In /opt/backup-system/main.sh
MAIN_SEGMENTS=(
  "01_validate_config.sh"
  "02_init_logging.sh"
  "03_shelly_power_on.sh"
  # ... segments 04-13
)
```
→ Run for **ALL profiles** (system, data, dev-data)  
→ Core backup logic (mount, backup, verify, unmount)  
→ Cannot be customized per profile

**PRE/POST_SEGMENTS** - Defined in `profile.env` (profile-specific)
```bash
# In /opt/backup-system/config/profiles/dev-data.env
export PRE_BACKUP_SEGMENTS=(
  "pre_01_nextcloud_db_dump.sh"
  "pre_02_docker_stop.sh"
)
export POST_CLEANUP_SEGMENTS=(
  "post_01_docker_start.sh"
)
```
→ Run **ONLY for profiles that define them**  
→ Custom actions (DB dumps, container management)  
→ Completely optional

### Execution Flow Example

**Profile: system.env** (no PRE/POST)
```
1. MAIN_SEGMENTS (01-13)  ← Only these run
```

**Profile: dev-data.env** (with PRE/POST)
```
1. PRE_BACKUP_SEGMENTS    ← DB dump, Docker stop
2. MAIN_SEGMENTS (01-13)  ← Standard backup
3. POST_CLEANUP_SEGMENTS  ← Docker start
```

### Why Separate?

**Problem if all in MAIN_SEGMENTS:**
- System backup would try to dump Nextcloud DB (doesn't exist!)
- Data backup would try to stop Docker (not installed!)
- Every profile forced to handle all scenarios

**Solution with PRE/POST:**
- System profile: Clean, simple, just MAIN segments
- Docker profile: Adds PRE/POST for container management
- Future profiles: Can define own custom segments

---

## Creating a New Profile

### 1. Copy Template

```bash
cd /opt/backup-system/config/profiles
sudo cp system.env.example my-profile.env
```

### 2. Edit Configuration

```bash
sudo nano my-profile.env
```

**Required Changes:**
- `BACKUP_PROFILE` - Unique profile name
- `BACKUP_SOURCES` - What to backup
- `BACKUP_UUID` - Target HDD UUID
- `TARGET_DIR` - Backup destination path
- `ARCHIVE_PREFIX` - Archive naming prefix

### 3. Test & Schedule

```bash
# Test backup
sudo /opt/backup-system/main.sh my-profile

# Create timer (optional)
sudo systemctl enable backup-my-profile-daily.timer
```

---

## Profile Best Practices

### Security
- File permissions: `chmod 600 *.env`
- Never commit actual configs to Git
- Back up config files separately

### Retention Policy
- **Critical data:** 14d/8w/12m
- **Regular data:** 7d/4w/6m
- **Temporary data:** 3d/0w/0m

### Scheduling
- **System:** Weekly
- **User data:** Daily
- **Docker:** Daily at 02:00
- **Databases:** Multiple times daily

---

## Related Documentation

- [INSTALLATION.md](INSTALLATION.md) - Setup instructions
- [DOCKER_NEXTCLOUD.md](DOCKER_NEXTCLOUD.md) - Docker backup guide
- [SECURITY.md](SECURITY.md) - Security best practices
