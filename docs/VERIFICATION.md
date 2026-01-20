# Backup Verification and Logging Architecture

> **Version**: 1.0.0  
> **Date**: 2026-01-20  
> **Author**: Segmented Borg Backup System

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Why Verification Matters](#why-verification-matters)
3. [Dual-Logging Architecture](#dual-logging-architecture)
4. [Verification Strategy](#verification-strategy)
5. [The POST_BACKUP Innovation](#the-post_backup-innovation)
6. [Technical Implementation](#technical-implementation)
7. [Verification Process Deep Dive](#verification-process-deep-dive)
8. [Troubleshooting and Diagnostics](#troubleshooting-and-diagnostics)
9. [Best Practices](#best-practices)

---

## Executive Summary

This backup system implements a **three-tier verification and logging architecture** that ensures:

✅ **Complete auditability** via dual-logging (local + backup location)  
✅ **Cryptographic integrity verification** via Borg's built-in verify  
✅ **Minimal service downtime** through phase separation (services offline only during backup creation, online while verify)  
✅ **Production readiness** through systematic validation at every stage

**Key Innovation:** Verification runs **after** services are restored online, leveraging Borg's deduplication architecture to verify backup integrity without additional downtime. Services are only offline during backup creation—verification runs in parallel with live operations.

---

## Why Verification Matters

### The Backup Paradox

> "A backup that hasn't been tested is not a backup—it's a hope."

Verification answers three critical questions:

1. **Is the backup complete?** (All files captured)
2. **Is the backup intact?** (No corruption during storage)
3. **Can the backup be restored?** (Restoration path validated)

### Real-World Failure Scenarios

Without verification, you only discover backup failures when you need to restore:

- **Silent corruption**: Storage media degradation over time
- **Incomplete backups**: Process interrupted, partial data written
- **Repository corruption**: Filesystem issues, power failures
- **Configuration drift**: Source paths changed, excludes misconfigured

**Our solution:** Every backup run automatically verifies integrity before cleanup.

---

## Dual-Logging Architecture

### Design Goals

1. **Persistence**: Logs survive even if backup device fails
2. **Accessibility**: Always available for troubleshooting
3. **Correlation**: Match logs to specific backup runs
4. **Completeness**: Capture every stage of the backup process

### Implementation

```
┌─────────────────────────────────────────────────────────────┐
│                    Backup Execution Flow                     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
         ┌──────────────────────────────────────┐
         │     run-backup.sh (wrapper)          │
         │  - Redirects ALL output to tee       │
         │  - Ensures atomic log writing        │
         └──────────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
    ┌─────────────────┐         ┌─────────────────┐
    │  LOCAL LOG      │         │  SYSTEMD        │
    │  /var/log/      │         │  JOURNAL        │
    │  extern_backup/ │         │  journalctl     │
    └─────────────────┘         └─────────────────┘
              │
              │ (02_init_logging.sh)
              ▼
    ┌─────────────────┐
    │  BACKUP LOG     │
    │  /mnt/backup/   │
    │  hostname_*/    │
    │  logs/          │
    └─────────────────┘
```

### Log Locations

| Location | Path Template | Purpose | Persistence |
|----------|---------------|---------|-------------|
| **Local** | `/var/log/extern_backup/<profile>_YYYYMMDD-HHMMSS.log` | Real-time monitoring | Until log rotation |
| **Backup** | `<backup-target>/<hostname>_<profile>/logs/<profile>_YYYYMMDD-HHMMSS.log` | Long-term audit trail | Lifetime of backup |
| **Journal** | `journalctl -u backup-system@<profile>.service` | System integration | Per systemd config |

### Key Features

#### 1. Atomic Log Creation

**Problem:** Previous implementations using `exec > >(tee ...)` caused incomplete logs.

**Solution:** Wrapper script (`run-backup.sh`) handles I/O redirection:

```bash
#!/usr/bin/env bash
# run-backup.sh - Reliable logging wrapper

PROFILE="${1:-system}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/var/log/extern_backup/${PROFILE}_${TIMESTAMP}.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Execute backup with atomic logging
/opt/backup-system/main.sh "$PROFILE" 2>&1 | tee "$LOG_FILE"

exit ${PIPESTATUS[0]}  # Preserve main.sh exit code
```

#### 2. Backup-Side Log Persistence

Segment `02_init_logging.sh` copies the local log to backup media:

```bash
# Inside 02_init_logging.sh
BACKUP_LOG_DIR="${TARGET_DIR}/logs"
mkdir -p "$BACKUP_LOG_DIR"

# Copy in real-time (background process)
tail -f "$LOCAL_LOG" > "$BACKUP_LOG" &
TAIL_PID=$!

# Cleanup on exit
trap "kill $TAIL_PID 2>/dev/null" EXIT
```

This ensures:
- ✅ Log survives even if backup device is later damaged
- ✅ Each backup has its own timestamped log
- ✅ Complete audit trail for forensic analysis

#### 3. Structured Log Format

Every segment produces standardized output:

```
[NN] Stage description...
[NN] Substep details...
[NN] Status: Success/Warning/Error
```

Example:
```
[05] Mounting backup device...
[05] Verifying device readiness...
[05] Device /dev/disk/by-uuid/f2c4624a-... is ready
[05] Triggering fstab automount...
[05] Backup device mounted successfully
[05] Device: /dev/sdX1
[05] UUID verified: f2c4624a-72ee-5e4b-85f8-a0d7f02e702f
```

This enables:
- Quick visual scanning during debugging
- Automated log parsing for monitoring systems
- Clear correlation between log entries and script segments

---

## Verification Strategy

### Borg's Verification Model

BorgBackup uses **cryptographic verification** at multiple levels:

```
┌─────────────────────────────────────────────────────────────┐
│                 Borg Repository Structure                    │
└─────────────────────────────────────────────────────────────┘

Repository (Deduplicated Pool)
├── Data Chunks (encrypted, content-addressable)
│   ├── Chunk ID = HASH(data)
│   ├── Chunk data (encrypted with repo key)
│   └── Chunk index (integrity checksums)
│
└── Archives (metadata snapshots)
    ├── Archive manifest (chunk references)
    ├── File metadata (paths, permissions, timestamps)
    └── Cryptographic signature

Verification Process:
1. Read archive manifest
2. For each referenced chunk:
   - Verify chunk exists in repository
   - Verify chunk ID matches content hash
   - Verify chunk integrity checksum
3. Confirm all chunks accessible
4. Report any missing/corrupt chunks
```

### What Borg Verify Checks

| Check | Description | Detects |
|-------|-------------|---------|
| **Manifest integrity** | Archive metadata structure | Metadata corruption |
| **Chunk existence** | All referenced chunks present | Incomplete backups |
| **Chunk checksums** | Content matches stored hash | Bit rot, corruption |
| **Repository structure** | Index consistency | Repository damage |

### What Borg Verify Does NOT Check

❌ **File content restoration** (doesn't extract files)  
❌ **Application-level consistency** (database corruption within backups)  
❌ **Source data changes** (verifies backup as-is, not vs current state)  

**Rationale:** Full restoration testing is expensive. Borg's cryptographic verification provides high confidence without full extraction overhead.

---

## The POST_BACKUP Innovation

### The Container Downtime Problem

**Traditional backup approach:**

```
1. Stop containers          ← Service offline
2. Create backup            ← Service offline
3. Verify backup            ← Service offline
4. Prune old backups        ← Service offline
5. Start containers         ← Service back online

Downtime = Backup duration + Verification duration + Pruning duration
```

**Problem:** For daily backups, extended downtime is problematic—especially when verification is a time-consuming but necessary step.

### Our Solution: Architectural Phase Separation

```
┌─────────────────────────────────────────────────────────────┐
│             Segmented Backup Execution Phases                │
└─────────────────────────────────────────────────────────────┘

Phase 1: PRE_BACKUP
├── pre_01_nextcloud_db_dump.sh    (Database snapshot)
└── pre_02_docker_stop.sh          (Container shutdown)

Phase 2: MAIN_SEGMENTS_PART1 (Backup Creation)
├── 01_validate_config.sh
├── 02_init_logging.sh
├── 03_shelly_power_on.sh          (External HDD power-on)
├── 04_wait_device.sh
├── 05_mount_backup.sh             ← Repository mounted
├── 06_validate_mount.sh
├── 07_init_borg_repo.sh
└── 08_borg_backup.sh              (Backup creation - services offline)

Phase 3: POST_BACKUP ⬅️ KEY INNOVATION
├── post_01_docker_start.sh        ← CONTAINERS BACK ONLINE
└── post_02_export_recovery_keys.sh

Phase 4: MAIN_SEGMENTS_PART2 (Verification while services run)
├── 09_borg_verify.sh              (Verify backup integrity)
└── 10_borg_prune.sh               (Cleanup old backups)

Phase 5: CLEANUP
├── 11_hdd_spindown.sh
├── 12_unmount_backup.sh           ← Repository unmounted
└── 13_shelly_power_off.sh

Service downtime: Only during backup creation (Phases 1-2)
Verification impact: None - runs while services are already online (Phase 4)
```

### Why This Works: Borg's Deduplication Architecture

**Critical insight:** Borg verification reads from the **already-created backup**, not from the live source data.

```
Backup Creation (Phase 2):
Source Data ──────> Borg ──────> Repository
/mnt/docker-data            /mnt/backup/hostname_*/borgrepo
                                      │
                                      │ Archive created
                                      │ All chunks written
                                      ▼
                            [Archive: hostname-profile-20260120_100000]

Container Restart (Phase 3):
/mnt/docker-data ──────> Docker starts
                         Nextcloud online
                         Services resume

Verification (Phase 4):
Repository ──────> Borg Verify ──────> Cryptographic Check
                                        - Chunk IDs valid?
                                        - Chunk data intact?
                                        - Manifest consistent?
                                              │
                                              ▼
                                      [Verification Result]
                                      ✅ Archive valid
                                      ✅ N chunks verified
                                      ✅ No corruption detected
```

**Key properties:**

1. **Archive is immutable** once created
2. **Verification reads repository**, not source
3. **Source can change** during verification without affecting result
4. **Containers can run** because verification doesn't touch `/mnt/docker-data`

### Trade-offs and Considerations

#### ✅ Advantages

- **Reduced downtime**: Services offline only during backup creation, not during verification
- **Verification adds zero downtime**: Services already online when verify runs
- **Safe verification**: No risk of service I/O interfering with verify process
- **Parallel operations**: Services continue serving requests during verification
- **Better resource usage**: Verification I/O doesn't impact running services

#### ⚠️ Considerations

- **Disk changes during verify**: New data written after backup won't be in verified archive (expected behavior)
- **Resource contention**: Verify uses disk I/O (mitigated by Borg's sequential reads)
- **Recovery key export timing**: Must run BEFORE unmount (handled in POST_BACKUP)

#### 🔍 Edge Cases

**Q: What if container writes corrupt the backup repository during verify?**

**A:** Not possible. The repository mount is **read-only** for verification:
- Borg verify opens repository in read-only mode
- Container writes go to `/mnt/docker-data` (different mount)
- Repository at `/mnt/backup/hostname_*/borgrepo` is isolated

**Q: What if container crashes during verify?**

**A:** No impact on verification:
- Verify reads completed archive
- Container crash doesn't affect repository data
- If container crash indicates underlying storage issue, verify may detect repository corruption

---

## Technical Implementation

### Segment 09: Borg Verify

```bash
#!/usr/bin/env bash
# segments/09_borg_verify.sh
# @version 1.0.0
# @description Verify integrity of the most recent backup archive

set -euo pipefail

echo "[09] Verifying backup integrity..."

# Get the most recent archive name
LATEST_ARCHIVE=$(borg list --short "$REPO" | tail -n 1)

if [ -z "$LATEST_ARCHIVE" ]; then
  echo "[ERROR] No archives found in repository"
  exit 1
fi

echo "[09] Verifying archive: $LATEST_ARCHIVE"

# Verify the archive
# --verify-data: Check chunk data integrity (slow but thorough)
# Without --verify-data, only checks metadata and chunk existence (faster)
if borg check --verify-data --last=1 "$REPO"; then
  echo "[09] Backup verification successful"
  echo "[09] Archive verified: $LATEST_ARCHIVE"
else
  echo "[ERROR] Backup verification failed!"
  echo "[ERROR] Repository may be corrupted or incomplete"
  exit 1
fi

exit 0
```

### Verification Modes

Borg offers different verification depths:

| Mode | Command | Checks | Use Case |
|------|---------|--------|----------|
| **Fast** | `borg check` | Metadata + chunk existence | Daily verification |
| **Thorough** | `borg check --verify-data` | + Cryptographic chunk validation | Weekly verification |
| **Complete** | `borg check --verify-data --repository` | + Repository structure | Monthly verification |

**Our default:** `--verify-data --last=1` (thorough check of most recent archive)

**Rationale:**
- Recent backup is most critical to verify
- Older archives verified during their creation
- Balance between thoroughness and performance

### Verification Output

Successful verification:
```
[09] Verifying backup integrity...
[09] Verifying archive: hostname-profile-20260120_100000
[09] Archive: hostname-profile-20260120_100000
[09] Checking archive consistency...
[09] Checking chunk integrity (verify-data mode)...
[09] Archive consistency check complete
[09] Backup verification successful
[09] Archive verified: hostname-profile-20260120_100000
```

Failed verification (corruption detected):
```
[09] Verifying backup integrity...
[09] Verifying archive: hostname-profile-20260120_100000
[ERROR] Archive check failed
[ERROR] Chunk <ID> is missing or corrupt
[ERROR] Backup verification failed!
[ERROR] Repository may be corrupted or incomplete
```

---

## Verification Process Deep Dive

### What Happens During Verification

```
┌─────────────────────────────────────────────────────────────┐
│          Borg Verification Internal Process                  │
└─────────────────────────────────────────────────────────────┘

1. Open Repository (Read-Only)
   ├── Load repository config
   ├── Verify repository key access
   └── Initialize chunk index

2. Load Archive Manifest
   ├── Read archive metadata
   ├── Parse chunk reference list
   └── Verify manifest signature

3. For Each Chunk in Archive:
   ├── Locate chunk in repository
   │   └── Chunk missing? → ERROR
   ├── Read chunk data
   │   └── Read error? → ERROR
   ├── Verify chunk ID = HASH(data)
   │   └── Mismatch? → ERROR (corruption)
   └── Verify chunk checksum
       └── Invalid? → ERROR (bit rot)

4. Report Results
   ├── Total chunks verified
   ├── Corruption detected (if any)
   └── Exit code: 0 (success) or 1 (failure)
```

### Verification Timeline

**Example backup run flow:**

```
Backup Started
│
├─ [PRE_BACKUP] Database dump created
├─ [PRE_BACKUP] Containers stopped ◄── DOWNTIME BEGINS
│
├─ [MAIN_PART1] HDD powered on
├─ [MAIN_PART1] HDD mounted
├─ [MAIN_PART1] Borg backup starts
│
├─ [MAIN_PART1] Borg backup complete
│   ✅ Archive created
│   ✅ All chunks written
│   ✅ Archive immutable
│
├─ [POST_BACKUP] Containers restarted ◄── DOWNTIME ENDS
├─ [POST_BACKUP] Recovery keys exported
│
├─ [MAIN_PART2] Verification starts ◄── Services already online
│   ├── Repository still mounted
│   ├── Archive already complete
│   ├── Containers running (no impact)
│   └── Cryptographic verification in progress
│
├─ [MAIN_PART2] Verification complete
│   ✅ All chunks validated
│   ✅ No corruption detected
│
├─ [MAIN_PART2] Pruning old backups
│
├─ [CLEANUP] HDD spindown
├─ [CLEANUP] HDD unmount
└─ [CLEANUP] HDD power off

Key metrics:
- Service downtime = Backup creation phase only
- Verification adds ZERO additional downtime (runs while services are online)
- Total runtime = Downtime + Verification (in parallel) + Cleanup
```

### Verification Guarantees

After successful verification, you have cryptographic proof:

✅ **Archive completeness**: All referenced chunks exist  
✅ **Data integrity**: No corruption (bit rot, bad sectors)  
✅ **Chunk authenticity**: Content matches cryptographic hash  
✅ **Repository consistency**: Index and data structures valid  

### What Verification Cannot Guarantee

❌ **Application consistency**: Backup may contain in-progress database transactions  
   → **Mitigation**: PRE_BACKUP database dump (consistent snapshot)

❌ **Restoration success**: Files may be corrupt at source  
   → **Mitigation**: Periodic test restores (recommended monthly)

❌ **Future integrity**: Storage may degrade after verification  
   → **Mitigation**: Regular re-verification of old archives

---

## Troubleshooting and Diagnostics

### Verification Failures

#### Scenario 1: Chunk Missing

**Symptom:**
```
[ERROR] Chunk <ID> not found in repository
```

**Possible causes:**
1. Backup interrupted before completion
2. Repository corruption (filesystem issue)
3. Partial backup due to source errors

**Diagnosis:**
```bash
# Check last backup segment completion
tail -n 100 /var/log/extern_backup/<profile>_*.log | grep -i "backup.*complete"

# Check for segment errors
grep -i "error\|fail" /var/log/extern_backup/<profile>_*.log

# Check repository health
borg check --repository "$REPO"
```

**Resolution:**
1. Delete incomplete archive: `borg delete "$REPO::$ARCHIVE"`
2. Re-run backup
3. If persistent: Check source disk health

#### Scenario 2: Chunk Corruption

**Symptom:**
```
[ERROR] Chunk <ID> hash mismatch (expected: <hash>, got: <hash>)
```

**Possible causes:**
1. Storage media bit rot
2. Filesystem corruption
3. Hardware failure (disk, controller, cable)

**Diagnosis:**
```bash
# Check filesystem integrity
sudo fsck.ext4 -n /dev/disk/by-uuid/<backup-device-uuid>

# Check SMART status
sudo smartctl -a /dev/<backup-device>

# Check kernel logs for I/O errors
sudo journalctl -k --since "today" | grep -iE "i/o error|ext4|ata|scsi"
```

**Resolution:**
1. **Critical:** Copy intact archives to new media
2. Run filesystem repair: `sudo fsck.ext4 -y /dev/<device>`
3. Replace failing hardware
4. Re-run backup to create new intact archive

#### Scenario 3: Repository Locked

**Symptom:**
```
[ERROR] Repository is locked by another process
```

**Possible causes:**
1. Previous backup still running
2. Backup was interrupted (stale lock)
3. Multiple backups started simultaneously

**Diagnosis:**
```bash
# Check for running backup processes
ps aux | grep -E "borg|backup-system"

# Check repository lock
ls -la "$REPO/lock.roster"
```

**Resolution:**
```bash
# If no backup is running, break lock
borg break-lock "$REPO"

# Then retry
sudo /opt/backup-system/run-backup.sh <profile>
```

### Log Analysis

#### Essential Log Patterns

**Success indicators:**
```bash
grep -E "\[09\].*verification successful" /var/log/extern_backup/*.log
```

**Failure indicators:**
```bash
grep -iE "error|fail|corrupt|abort" /var/log/extern_backup/*.log
```

**Performance metrics:**
```bash
# Extract backup duration
grep -E "\[(08|09|10)\]" /var/log/extern_backup/<profile>_*.log | \
  grep -E "complete|successful"
```

#### Automated Monitoring

**Example: Daily verification check**

```bash
#!/bin/bash
# /usr/local/bin/check-backup-verification.sh

PROFILE="$1"
LOG_DIR="/var/log/extern_backup"

# Get most recent log
LATEST_LOG=$(ls -t "$LOG_DIR/${PROFILE}_"*.log | head -n 1)

if [ -z "$LATEST_LOG" ]; then
  echo "ERROR: No log found for profile: $PROFILE"
  exit 1
fi

# Check verification result
if grep -q "\[09\].*verification successful" "$LATEST_LOG"; then
  echo "OK: Backup verified successfully"
  exit 0
else
  echo "CRITICAL: Backup verification failed or missing"
  grep -i "error\|fail" "$LATEST_LOG" | tail -n 10
  exit 2
fi
```

**Integration with monitoring:**

```bash
# Add to cron or systemd timer
0 2 * * * /usr/local/bin/check-backup-verification.sh system >> /var/log/backup-check.log 2>&1
0 3 * * * /usr/local/bin/check-backup-verification.sh dev-data >> /var/log/backup-check.log 2>&1
```

---

## Best Practices

### 1. Verification Cadence

| Frequency | Verification Type | Scope |
|-----------|-------------------|-------|
| **Daily** | Fast check | Most recent archive (--last=1) |
| **Weekly** | Thorough check | All recent archives (--verify-data) |
| **Monthly** | Complete check | Entire repository (--repository) |
| **Quarterly** | Test restore | Random files from old archives |

### 2. Retention and Verification

**Problem:** Old archives may degrade without detection.

**Solution:** Periodic re-verification of historical archives:

```bash
# Monthly: Verify random old archive
RANDOM_ARCHIVE=$(borg list --short "$REPO" | shuf -n 1)
borg check --verify-data "$REPO::$RANDOM_ARCHIVE"
```

### 3. Verification Log Retention

**Recommendation:**

- **Local logs**: Retain 30 days (log rotation)
- **Backup logs**: Retain lifetime of backup (inside repository)
- **Summary logs**: Retain indefinitely (verification results only)

```bash
# Example: Extract verification results to summary
grep -h "\[09\].*verification" /var/log/extern_backup/*.log >> \
  /var/log/extern_backup/verification-summary.log
```

### 4. Alert Thresholds

Configure monitoring alerts for:

| Condition | Severity | Action |
|-----------|----------|--------|
| Verification fails | **CRITICAL** | Immediate investigation |
| Verification skipped | **WARNING** | Check backup process |
| Verification unusually slow | **INFO** | Performance review |
| No backup in 48h | **CRITICAL** | Check timer/scheduling |

### 5. Documentation

**Maintain verification runbook:**

1. Common failure scenarios
2. Resolution procedures
3. Escalation contacts
4. Recovery key locations
5. Test restore procedures

---

## Appendix: Quick Reference

### Verification Commands

```bash
# Verify most recent archive (fast)
borg check --last=1 "$REPO"

# Verify with data integrity (thorough)
borg check --verify-data --last=1 "$REPO"

# Verify entire repository (complete)
borg check --verify-data --repository "$REPO"

# Verify specific archive
borg check --verify-data "$REPO::$ARCHIVE_NAME"
```

### Log Locations

```bash
# Local logs
/var/log/extern_backup/<profile>_YYYYMMDD-HHMMSS.log

# Backup logs
<backup-mount>/<hostname>_<profile>/logs/<profile>_YYYYMMDD-HHMMSS.log

# Systemd journal
journalctl -u backup-system@<profile>.service
```

### Emergency Procedures

**Verification failure:**
```bash
1. Isolate backup media (prevent further writes)
2. Copy latest log: cp /var/log/extern_backup/<latest> ~/backup-failure.log
3. Check repository: borg check --repository "$REPO"
4. If repository intact: Re-run backup
5. If repository corrupt: Restore from previous backup, replace media
```

**Recovery key needed:**
```bash
1. Locate recovery ZIP: ~/recovery/<profile>_*_<repo-id>_*.zip
2. Extract: unzip <recovery-zip>
3. Import key: borg key import "$REPO" repo-key.txt
4. Follow RECOVERY-README.txt
```

---

## Conclusion

This verification and logging architecture provides:

✅ **Complete audit trail** through dual logging  
✅ **Cryptographic integrity verification** after every backup  
✅ **Minimized service downtime** through phase separation  
✅ **Production-ready reliability** through systematic validation  

The key innovation—running verification after service restoration—eliminates the traditional backup/downtime trade-off while maintaining cryptographic guarantees of backup integrity.

**Remember:** Verification proves the backup is intact. **Test restores** prove you can actually use it in an emergency.

---

**Next steps:**

1. Review verification logs regularly
2. Schedule periodic test restores
3. Update recovery documentation
4. Integrate with monitoring systems

**Document version:** 1.0.0  
**Last updated:** 2026-01-20
