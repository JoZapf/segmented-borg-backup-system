# Segments Documentation

## Overview

The backup system is built from 16 independent segments (13 main + 3 PRE/POST). Each segment handles one specific task and can be tested individually.

---

## Segment Architecture

### Execution Flow

```
┌─────────────────────────────────────────────────────┐
│ PRE-BACKUP Phase (Profile-Specific, Optional)      │
├─────────────────────────────────────────────────────┤
│ • pre_01_nextcloud_db_dump.sh                      │
│ • pre_02_docker_stop.sh                            │
└─────────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────┐
│ MAIN BACKUP Phase (All Profiles)                   │
├─────────────────────────────────────────────────────┤
│ 01. validate_config.sh                              │
│ 02. init_logging.sh                                 │
│ 03. shelly_power_on.sh                              │
│ 04. wait_device.sh                                  │
│ 05. mount_backup.sh                                 │
│ 06. validate_mount.sh                               │
│ 07. init_borg_repo.sh                               │
│ 08. borg_backup.sh                                  │
│ 09. borg_verify.sh                                  │
│ 10. borg_prune.sh                                   │
│ 11. hdd_spindown.sh                                 │
│ 12. unmount_backup.sh                               │
│ 13. shelly_power_off.sh                             │
└─────────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────┐
│ POST-CLEANUP Phase (Profile-Specific, Optional)    │
├─────────────────────────────────────────────────────┤
│ • post_01_docker_start.sh                          │
└─────────────────────────────────────────────────────┘
```

---

## Main Segments (01-13)

### 01_validate_config.sh
**Purpose:** Validates profile configuration  
**Dependencies:** None  
**Exit Codes:** 0=valid, 1=invalid

**Checks:**
- Required variables set
- Paths exist
- Dependencies installed (borg, curl, hdparm)
- Valid UUID format

**Test:**
```bash
sudo /opt/backup-system/segments/01_validate_config.sh
```

---

### 02_init_logging.sh
**Purpose:** Sets up dual logging system  
**Dependencies:** 01  
**Exit Codes:** 0=success, 1=error

**Actions:**
- Creates local log directory (`/var/log/extern_backup/`)
- Redirects stdout/stderr to logfile
- Logs backup start time and profile

**Test:**
```bash
sudo /opt/backup-system/segments/02_init_logging.sh
ls /var/log/extern_backup/
```

---

### 03_shelly_power_on.sh
**Purpose:** Powers on external HDD via Shelly Plug  
**Dependencies:** 01  
**Exit Codes:** 0=success, 1=error, 77=skipped

**Actions:**
- Checks if Shelly enabled
- Sends HTTP request to Shelly API
- Configures auto-off timer

**Test:**
```bash
sudo /opt/backup-system/segments/03_shelly_power_on.sh
# Check plug status
curl http://192.168.X.X/rpc/Switch.GetStatus?id=0
```

---

### 04_wait_device.sh
**Purpose:** Waits for backup device to become available  
**Dependencies:** 03  
**Exit Codes:** 0=available, 1=timeout

**Actions:**
- Polls for device every second
- Times out after 180 seconds (configurable)
- Logs device availability

**Test:**
```bash
sudo /opt/backup-system/segments/04_wait_device.sh
```

---

### 05_mount_backup.sh
**Purpose:** Mounts backup device  
**Dependencies:** 04  
**Exit Codes:** 0=success, 1=error

**Actions:**
- Attempts systemd automount trigger
- Falls back to explicit mount
- Idempotent (won't fail if already mounted)

**Test:**
```bash
sudo /opt/backup-system/segments/05_mount_backup.sh
mount | grep extern_backup
```

---

### 06_validate_mount.sh
**Purpose:** Verifies correct disk is mounted  
**Dependencies:** 05  
**Exit Codes:** 0=valid, 1=error

**Safety Checks:**
- Verifies UUID matches config
- Checks filesystem type (ext4)
- Handles multiple mount entries (systemd + fstab)

**Test:**
```bash
sudo /opt/backup-system/segments/06_validate_mount.sh
```

---

### 07_init_borg_repo.sh
**Purpose:** Initializes Borg repository if needed  
**Dependencies:** 06  
**Exit Codes:** 0=success, 77=exists

**Actions:**
- Checks if repo exists
- Creates repo with repokey-blake2 encryption
- Displays passphrase reminder

**Test:**
```bash
sudo /opt/backup-system/segments/07_init_borg_repo.sh
```

---

### 08_borg_backup.sh
**Purpose:** Creates Borg backup archive  
**Dependencies:** 07  
**Exit Codes:** 0=success, 1=warnings, 2+=error

**Actions:**
- Runs `borg create` with configured options
- Handles exit codes correctly (1=warning is OK)
- Logs statistics

**Test:**
```bash
sudo /opt/backup-system/segments/08_borg_backup.sh
```

---

### 09_borg_verify.sh
**Purpose:** Verifies backup integrity  
**Dependencies:** 08  
**Exit Codes:** 0=success, 1=error

**Actions:**
- Runs `borg check --verify-data`
- Full data integrity check
- **Note:** Can be disabled for faster backups

**Test:**
```bash
sudo /opt/backup-system/segments/09_borg_verify.sh
```

---

### 10_borg_prune.sh
**Purpose:** Removes old archives per retention policy  
**Dependencies:** 09  
**Exit Codes:** 0=success, 1=error

**Actions:**
- Applies KEEP_DAILY/WEEKLY/MONTHLY rules
- Compacts repository
- Logs freed space

**Test:**
```bash
sudo /opt/backup-system/segments/10_borg_prune.sh
```

---

### 11_hdd_spindown.sh
**Purpose:** Safely spins down HDD  
**Dependencies:** 10  
**Exit Codes:** 0=success, 77=skipped

**Actions:**
- Parks read/write heads (`hdparm -y`)
- Spins down drive (`hdparm -Y`)
- Only if HDD_SPINDOWN_ENABLED=true

**Test:**
```bash
sudo /opt/backup-system/segments/11_hdd_spindown.sh
sudo hdparm -C /dev/sdX  # Check power state
```

---

### 12_unmount_backup.sh
**Purpose:** Unmounts backup device  
**Dependencies:** 11  
**Exit Codes:** 0=success, 1=error

**Actions:**
- Syncs filesystem buffers
- Checks for open file handles
- Stops systemd automount
- Unmounts device

**Test:**
```bash
sudo /opt/backup-system/segments/12_unmount_backup.sh
mount | grep extern_backup  # Should be empty
```

---

### 13_shelly_power_off.sh
**Purpose:** Powers off external HDD  
**Dependencies:** 12  
**Exit Codes:** 0=success, 77=skipped

**Actions:**
- Waits for spindown to complete
- Sends power-off command to Shelly
- Only if SHELLY_ENABLED=true

**Test:**
```bash
sudo /opt/backup-system/segments/13_shelly_power_off.sh
```

---

## PRE/POST Segments

### pre_01_nextcloud_db_dump.sh
**Purpose:** Dumps Nextcloud database  
**Profile:** dev-data  
**Exit Codes:** 0=success, 1=error

**Actions:**
1. Enables Nextcloud maintenance mode
2. Dumps database via Docker exec
3. Copies dump to host
4. Verifies dump integrity
5. Compresses dump (gzip)
6. Cleans up old dumps
7. Disables maintenance mode

**Configuration:**
```bash
export NEXTCLOUD_ENABLED="true"
export NEXTCLOUD_DB_TYPE="mariadb"
export NEXTCLOUD_DB_NAME="nextcloud"
export NEXTCLOUD_DB_USER="ncadmin"
export NEXTCLOUD_DB_PASSWORD="secret"
```

**Test:**
```bash
sudo -E /opt/backup-system/segments/pre_01_nextcloud_db_dump.sh
ls -lh ${TARGET_DIR}/database-dumps/
```

---

### pre_02_docker_stop.sh
**Purpose:** Stops Docker containers gracefully  
**Profile:** dev-data  
**Exit Codes:** 0=success, 1=error

**Actions:**
1. Detects running containers
2. Saves container IDs to STATE_DIR
3. Stops each container (timeout: 30s)
4. Verifies all stopped

**Configuration:**
```bash
export DOCKER_ENABLED="true"
export DOCKER_STOP_TIMEOUT="30"
export STATE_DIR="/tmp/backup-system-state"
```

**Test:**
```bash
sudo -E /opt/backup-system/segments/pre_02_docker_stop.sh
docker ps  # Should show no containers
```

---

### post_01_docker_start.sh
**Purpose:** Restarts Docker containers  
**Profile:** dev-data  
**Exit Codes:** 0=success (always)

**Actions:**
1. Reads container IDs from STATE_DIR
2. Starts each container
3. Verifies restart
4. Calculates downtime
5. **Runs even if backup failed** (via trap)

**Test:**
```bash
sudo -E /opt/backup-system/segments/post_01_docker_start.sh
docker ps  # Should show containers again
```

---

## Creating Custom Segments

### Template

```bash
#!/usr/bin/env bash
# custom_segment.sh
# @version 1.0.0
# @description Brief description
# @author Your Name
# @changed YYYY-MM-DD

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ============================================================================
# CONFIGURATION
# ============================================================================
# Source profile config
if [ -z "${BACKUP_PROFILE:-}" ]; then
  echo "[ERROR] BACKUP_PROFILE not set"
  exit 1
fi

PROFILE_CONFIG="/opt/backup-system/config/profiles/${BACKUP_PROFILE}.env"
if [ ! -f "$PROFILE_CONFIG" ]; then
  echo "[ERROR] Profile config not found: $PROFILE_CONFIG"
  exit 1
fi

source "$PROFILE_CONFIG"

# ============================================================================
# SEGMENT LOGIC
# ============================================================================
echo "[CUSTOM] Starting custom action..."

# Your code here

echo "[CUSTOM] Custom action completed"
exit 0
```

### Best Practices

1. **Always use `set -euo pipefail`**
   - Except when wrapping commands that may fail intentionally

2. **Check dependencies**
   - Verify required variables are set
   - Check required tools are installed

3. **Exit codes**
   - 0 = Success
   - 1 = Error (will abort backup)
   - 77 = Skipped (not an error)

4. **Logging**
   - Prefix with `[SEGMENT-NAME]`
   - Log start and completion
   - Log errors clearly

5. **Idempotency**
   - Segment should be safe to run multiple times
   - Check state before making changes

---

## Troubleshooting Segments

### Test Individual Segment

```bash
# Source profile config
export BACKUP_PROFILE="system"
source /opt/backup-system/config/profiles/system.env

# Run segment
sudo -E /opt/backup-system/segments/08_borg_backup.sh
```

### Debug Mode

```bash
# Add debug output
bash -x /opt/backup-system/segments/segment_name.sh
```

### Check Dependencies

```bash
# Verify segment 05 depends on 04
# If 04 fails, 05 should not run
sudo /opt/backup-system/segments/04_wait_device.sh || echo "04 failed"
sudo /opt/backup-system/segments/05_mount_backup.sh  # Should not run
```

---

## Segment Variables

### Common Variables (All Segments)

- `BACKUP_PROFILE` - Profile name
- `TARGET_DIR` - Backup destination
- `REPO` - Borg repository path
- `BACKUP_UUID` - Device UUID

### Segment-Specific Variables

| Segment | Variables |
|---------|-----------|
| 03, 13 | `SHELLY_ENABLED`, `SHELLY_IP` |
| 04 | `BACKUP_DEV`, `DEVICE_WAIT_TIMEOUT` |
| 08 | `BACKUP_SOURCES`, `BACKUP_EXCLUDES` |
| 10 | `KEEP_DAILY`, `KEEP_WEEKLY`, `KEEP_MONTHLY` |
| 11 | `HDD_SPINDOWN_ENABLED`, `HDD_DEVICE` |

---

## Related Documentation

- [PROFILES.md](PROFILES.md) - Profile configuration guide
- [DOCKER_NEXTCLOUD.md](DOCKER_NEXTCLOUD.md) - Docker segment usage
- [TESTING.md](TESTING.md) - Segment testing procedures
