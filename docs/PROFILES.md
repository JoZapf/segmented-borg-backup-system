# Backup Profile Configuration Strategies

> **Version**: 1.0.0  
> **Date**: 2026-01-20  
> **Author**: Segmented Borg Backup System

---

## Table of Contents

1. [Overview](#overview)
2. [Profile Comparison](#profile-comparison)
3. [Mount Strategies](#mount-strategies)
4. [Cleanup Strategies](#cleanup-strategies)
5. [Power Management](#power-management)
6. [Design Decision Framework](#design-decision-framework)
7. [Common Patterns](#common-patterns)
8. [Troubleshooting](#troubleshooting)

---

## Overview

This backup system supports multiple backup profiles, each optimized for different hardware configurations and use cases. The two reference profiles demonstrate fundamentally different approaches to backup management based on storage device characteristics.

### Key Principle

> Different storage types require different management strategies.

The profile system allows customization of:
- **Mount behavior** (persistent vs on-demand)
- **Cleanup procedures** (unmount vs spindown)
- **Power management** (external control vs software control)
- **Segment execution** (profile-specific pre/post operations)

---

## Profile Comparison

### system Profile: External USB HDD

**Use case:** External USB backup drive with power control

```bash
# Characteristics
Storage Type:     External USB HDD
Power Control:    Shelly Plug (hardware-controlled)
Access Pattern:   On-demand (backup runs only)
Mount Strategy:   Automount
Cleanup Strategy: Full unmount + power-off
```

**Configuration:**
```bash
# system.env
export BACKUP_MNT="/mnt/extern_backup"
export BACKUP_UUID="<external-hdd-uuid>"
export BACKUP_DEV="/dev/disk/by-uuid/${BACKUP_UUID}"

export SHELLY_ENABLED="true"
export SHELLY_PLUG_IP="192.168.x.x"

export HDD_SPINDOWN_ENABLED="true"
export HDD_DEVICE="/dev/disk/by-id/usb-..."  # Stable USB device ID
```

**fstab entry:**
```bash
UUID=<uuid>  /mnt/extern_backup  ext4  defaults,nofail,x-systemd.automount,x-systemd.device-timeout=5s  0  2
```

**Execution Flow:**
```
Phase 1: PRE_BACKUP
  (none - no application-specific preparation)

Phase 2: MAIN_PART1
  [03] Shelly power ON → HDD spins up
  [04] Wait for device readiness
  [05] Trigger fstab automount
  [06] Validate correct UUID mounted
  [07] Initialize Borg repository
  [08] Create backup

Phase 3: POST_BACKUP
  post_01 - Export recovery keys

Phase 4: MAIN_PART2
  [09] Verify backup
  [10] Prune old archives

Phase 5: CLEANUP
  [11] HDD spindown (park heads)
  [12] Unmount /mnt/extern_backup
  [13] Shelly power OFF → HDD powered down
```

---

### dev-data Profile: Internal SATA HDD

**Use case:** Internal backup drive, always powered

```bash
# Characteristics
Storage Type:     Internal SATA HDD
Power Control:    Software spindown only
Access Pattern:   Persistent (potentially frequent access)
Mount Strategy:   Persistent mount
Cleanup Strategy: Spindown only (no unmount)
```

**Configuration:**
```bash
# dev-data.env
export BACKUP_MNT="/mnt/system_backup"
export BACKUP_UUID="<internal-hdd-uuid>"
export BACKUP_DEV="/dev/disk/by-uuid/${BACKUP_UUID}"

export SHELLY_ENABLED="false"  # No external power control

export HDD_SPINDOWN_ENABLED="true"
export HDD_DEVICE="/dev/sda"   # Internal SATA device

export DOCKER_ENABLED="true"
export NEXTCLOUD_ENABLED="true"
```

**fstab entry:**
```bash
UUID=<uuid>  /mnt/system_backup  ext4  defaults,acl,nofail  0  2
```

**Execution Flow:**
```
Phase 1: PRE_BACKUP
  pre_01 - Nextcloud DB dump
  pre_02 - Docker stop

Phase 2: MAIN_PART1
  [01] Validate configuration
  [02] Initialize logging
  [03] (Skip - no Shelly)
  [04] Verify device ready (already mounted)
  [05] Validate mount (already active)
  [06] Validate correct UUID
  [07] Initialize Borg repository
  [08] Create backup

Phase 3: POST_BACKUP
  post_01 - Docker start (services back online)
  post_02 - Export recovery keys

Phase 4: MAIN_PART2
  [09] Verify backup (services running)
  [10] Prune old archives (services running)

Phase 5: CLEANUP
  [11] HDD spindown (software-managed)
  [12] (No unmount - persistent mount)
  [13] (Skip - no Shelly)
```

---

## Mount Strategies

### Automount (system profile)

**fstab configuration:**
```bash
UUID=...  /mnt/extern_backup  ext4  ...,x-systemd.automount,...  0  2
```

**How it works:**
1. systemd creates automount unit: `mnt-extern_backup.automount`
2. Access to `/mnt/extern_backup` triggers mount
3. segment 05 triggers via `ls /mnt/extern_backup`
4. systemd mounts device automatically

**Benefits:**
- ✅ Mount only when needed
- ✅ Easy unmount (systemd manages units)
- ✅ Automatic timeout (configurable)
- ✅ Clean state when not in use

**Trade-offs:**
- ⚠️ Mount overhead on each backup
- ⚠️ Requires systemd automount support

**When to use:**
- External HDDs with power control
- Infrequently accessed storage
- Devices that should be unmounted when idle

---

### Persistent Mount (dev-data profile)

**fstab configuration:**
```bash
UUID=...  /mnt/system_backup  ext4  defaults,acl,nofail  0  2
```

**How it works:**
1. Mount happens at boot via fstab
2. Mount persists until manual unmount or shutdown
3. No automount unit created
4. segment 05 validates existing mount

**Benefits:**
- ✅ No mount overhead
- ✅ Always available for manual access
- ✅ Simpler configuration
- ✅ Faster backup start

**Trade-offs:**
- ⚠️ Always mounted (filesystem exposure)
- ⚠️ Manual unmount if needed

**When to use:**
- Internal HDDs (always powered)
- Frequently accessed storage
- Systems where mount overhead matters
- Storage without external power control

---

## Cleanup Strategies

### Full Unmount (system profile)

**segment 12 behavior:**
```bash
# Stop automount and mount units
systemctl stop mnt-extern_backup.automount
systemctl stop mnt-extern_backup.mount

# Unmount filesystem
umount /mnt/extern_backup

# Verify unmount succeeded
findmnt -M /mnt/extern_backup || success
```

**Benefits:**
- ✅ Clean state for external devices
- ✅ Prepares for physical disconnect
- ✅ Required before power-off (segment 13)
- ✅ Prevents data corruption on power loss

**When to use:**
- Before external power-off (Shelly Plug)
- External USB devices (can be unplugged)
- Devices with power management

---

### Spindown Only (dev-data profile)

**segment 11 behavior:**
```bash
# Park heads and spin down platters
hdparm -y /dev/sda

# Verify standby state
hdparm -C /dev/sda  # Should show "standby"
```

**segment 12 behavior:**
```bash
# Attempts unmount but gracefully fails
# Mount remains active - this is intentional
```

**Benefits:**
- ✅ No unmount overhead
- ✅ Power saving via spindown
- ✅ Immediate access for next backup
- ✅ No filesystem state changes

**Trade-offs:**
- ⚠️ Filesystem remains mounted
- ⚠️ Requires HDD to support spindown

**When to use:**
- Internal SATA HDDs
- Always-powered storage
- When unmount provides no benefit
- Systems requiring fast backup starts

---

## Power Management

### Hardware-Controlled (system profile)

**Method:** Shelly Plug smart switch

```bash
# segment 03 - Power ON
curl "http://${SHELLY_PLUG_IP}/relay/0?turn=on"

# segment 13 - Power OFF (after unmount)
curl "http://${SHELLY_PLUG_IP}/relay/0?turn=off"
```

**Benefits:**
- ✅ Complete power disconnect
- ✅ Zero power consumption when idle
- ✅ Physical disconnect protection
- ✅ Reduces HDD wear

**Requirements:**
- Hardware: Smart plug (Shelly, TP-Link, etc.)
- Network: Accessible IP address
- Timing: Adequate spin-up delay (segment 04)

---

### Software-Controlled (dev-data profile)

**Method:** hdparm spindown

```bash
# Immediate spindown
hdparm -y /dev/sda

# Standby state (heads parked, low power)
# HDD still powered, but platters stopped
```

**Benefits:**
- ✅ No external hardware needed
- ✅ Fast wake-up (no full power cycle)
- ✅ Adequate for internal HDDs

**Limitations:**
- ⚠️ HDD still powered (minimal consumption)
- ⚠️ Some HDD models have proprietary power management
- ⚠️ Timer-based spindown (`-S`) may not work on all HDDs

**HDD-Specific Considerations:**

Certain HDD models have proprietary power management that interferes with hdparm:
- Built-in idle timers that override `-S` setting
- Aggressive head-parking (e.g., IntelliPark)
- APM (Advanced Power Management) may not be supported

**Solution for incompatible HDDs:**
```bash
# Instead of timer: hdparm -S 60
# Use immediate spindown in segment 11:
hdparm -y /dev/sda  # Always works
```

---

## Design Decision Framework

### When designing a new profile, consider:

#### 1. Storage Type

| Type | Recommended Strategy |
|------|---------------------|
| **External USB** | Automount + Full unmount + Power-off |
| **Internal SATA** | Persistent mount + Spindown only |
| **NVMe** | Persistent mount + No spindown (NVMe has own PM) |
| **Network (NFS/SMB)** | Automount + No spindown |

#### 2. Access Pattern

| Pattern | Recommended Strategy |
|---------|---------------------|
| **Daily backup only** | Automount preferred |
| **Frequent manual access** | Persistent mount preferred |
| **Backup + monitoring** | Persistent mount preferred |

#### 3. Power Control

| Control | Recommended Strategy |
|---------|---------------------|
| **Smart plug available** | Full unmount + Power-off |
| **Always powered** | Spindown only |
| **Battery/UPS** | Unmount for safety |

#### 4. Performance Requirements

| Requirement | Recommended Strategy |
|-------------|---------------------|
| **Fast backup start** | Persistent mount |
| **Minimal resource use** | Automount + Unmount |
| **Always available** | Persistent mount |

---

## Common Patterns

### Pattern 1: External USB with Power Control

```bash
# Profile configuration
BACKUP_MNT="/mnt/extern_backup"
SHELLY_ENABLED="true"
HDD_SPINDOWN_ENABLED="true"

# fstab
UUID=...  /mnt/extern_backup  ext4  ...,x-systemd.automount,...

# Segments active
03 - Shelly ON
11 - Spindown
12 - Unmount
13 - Shelly OFF
```

### Pattern 2: Internal HDD with Docker Services

```bash
# Profile configuration
BACKUP_MNT="/mnt/system_backup"
SHELLY_ENABLED="false"
DOCKER_ENABLED="true"

# fstab
UUID=...  /mnt/system_backup  ext4  defaults,acl,nofail

# Segments active
PRE_BACKUP - Docker stop
POST_BACKUP - Docker start
11 - Spindown
```

### Pattern 3: NFS/Network Storage

```bash
# Profile configuration
BACKUP_MNT="/mnt/nfs_backup"
SHELLY_ENABLED="false"
HDD_SPINDOWN_ENABLED="false"

# fstab
nas:/backup  /mnt/nfs_backup  nfs  ...,x-systemd.automount,...

# Segments active
(minimal - network manages power)
```

---

## Troubleshooting

### Segment 12 Does Not Unmount

**Symptom:** Internal HDD remains mounted after backup

**Diagnosis:**
```bash
# Check mount type
findmnt /mnt/system_backup

# Check for automount unit
systemctl status mnt-system_backup.automount
# If "could not be found" → Expected for persistent mounts
```

**Resolution:** This is intentional for internal HDDs with persistent mounts.

**Verify spindown works:**
```bash
# Wait 2 minutes after backup, then:
sudo hdparm -C /dev/sda
# Should show: "drive state is: standby"
```

---

### Automount Not Triggering

**Symptom:** segment 05 fails, mount not appearing

**Diagnosis:**
```bash
# Check fstab entry
grep -E "BACKUP_MNT|UUID" /etc/fstab

# Check automount unit
systemctl status mnt-*.automount

# Check if device exists
ls -la /dev/disk/by-uuid/<uuid>
```

**Common causes:**
1. Missing `x-systemd.automount` in fstab
2. Wrong mount point in fstab vs profile config
3. Device not ready (timing issue)

---

### HDD Does Not Spindown

**Symptom:** HDD stays active after backup

**Diagnosis:**
```bash
# Test manual spindown
sudo hdparm -y /dev/sda
sudo hdparm -C /dev/sda  # Should show "standby"

# Check for open files
sudo lsof +f -- /mnt/system_backup

# Check spindown is enabled
grep HDD_SPINDOWN config/profiles/<profile>.env
```

**Common causes:**
1. `HDD_SPINDOWN_ENABLED="false"` in profile
2. File manager or process accessing mount
3. HDD does not support hdparm spindown
4. Proprietary power management interference

**Solution for proprietary HDD power management:**
- segment 11 already uses immediate spindown (`hdparm -y`)
- This works even when timer-based spindown (`-S`) does not
- No configuration change needed

---

### Shelly Plug Not Responding

**Symptom:** segment 03 or 13 fails

**Diagnosis:**
```bash
# Test Shelly connectivity
ping <shelly-ip>

# Test manual control
curl "http://<shelly-ip>/relay/0?turn=on"

# Check profile config
grep SHELLY config/profiles/<profile>.env
```

**Common causes:**
1. Wrong IP address in profile config
2. Shelly not on same network
3. Shelly disabled in profile (`SHELLY_ENABLED="false"`)

---

## Best Practices

### Profile Design

1. **Match hardware characteristics**
   - External → Automount + Unmount
   - Internal → Persistent + Spindown

2. **Consider access patterns**
   - Infrequent → Automount saves resources
   - Frequent → Persistent avoids overhead

3. **Test spindown compatibility**
   - Verify `hdparm -y` works before relying on it
   - Some HDDs need proprietary tools

4. **Use stable device identifiers**
   - `/dev/disk/by-id/*` for USB (stable across reboots)
   - `/dev/sdX` acceptable for internal SATA (usually stable)
   - Never use `/dev/sdX` for USB (can change)

5. **Document deviations**
   - If your profile differs from reference patterns, document why
   - Help future maintainers understand design decisions

### Testing New Profiles

```bash
# 1. Test mount
sudo /opt/backup-system/segments/05_mount_backup.sh
findmnt <BACKUP_MNT>

# 2. Test backup
sudo /opt/backup-system/run-backup.sh <profile>

# 3. Test spindown (if enabled)
sleep 120
sudo hdparm -C <HDD_DEVICE>

# 4. Test unmount (if expected)
findmnt <BACKUP_MNT>  # Should be empty if unmounted

# 5. Check logs
tail -100 /var/log/extern_backup/<profile>_*.log
```

---

## Conclusion

Profile-specific strategies allow the backup system to adapt to different hardware configurations while maintaining consistent reliability. Understanding the trade-offs between automount vs persistent mounting and unmount vs spindown enables informed decisions for new profiles.

**Key takeaway:** Different storage types have different optimal management strategies. The profile system makes these differences explicit and manageable.

---

**Document version:** 1.0.0  
**Last updated:** 2026-01-20
