# shdoc-Dokumentation Update v2.8.3

**Datum:** 2026-02-04  
**Änderung:** Mount/Unmount Error Recovery Implementation  
**Impact:** +5 Stunden Dokumentationsaufwand  
**Versioning:** SemVer-strict (Option B)

---

## 📝 SemVer-Begründung

### Warum unterschiedliche Version Bumps?

**Segment 05: v2.0.0 → v2.1.0 (Minor)**
- ✅ **API Backward Compatible**: Inputs/Outputs unchanged
- ✅ **No Breaking Changes**: External behavior identical
- ✅ **New Features**: Internal error recovery enhancements
- ➡️ **SemVer Classification**: Minor version bump

**Segment 12: v1.3.0 → v2.0.0 (Major)**
- ❌ **API Breaking Change**: Exit code behavior changed
- ❌ **Behavioral Change**: exit 1 → exit 0 (always succeeds)
- ❌ **Impact**: Downstream segments (11, 13) behavior affected
- ➡️ **SemVer Classification**: Major version bump

**Why this matters:**
- Users know: Major = "Review before upgrading"
- Users know: Minor = "Safe to upgrade automatically"
- Consistency with SemVer principles
- Clear communication of impact

---

## 📊 Aufwandsänderungen

### Segment 05: mount_backup.sh

**Alt (v2.0.0):**
- Zeilen: 126
- Funktionen: 0
- Komplexität: Mittel-Hoch
- Aufwand: 2h

**Neu (v2.1.0):** [SemVer: Minor - Backward Compatible]
- Zeilen: 432 (+243%)
- Funktionen: 2 (`safe_unmount`, `validate_and_mount`)
- Komplexität: **Sehr Hoch**
- Aufwand: **5h (+3h)**
- **API**: Unchanged (same inputs/outputs)

**Neue Features:**
- Multi-stage unmount recovery (4 Stufen)
- Process blacklist protection (10+ Prozesse)
- Try-catch-ähnliche Fehlerbehandlung
- "Already mounted" Error Recovery
- Umfangreiche Debugging-Ausgabe

---

### Segment 12: unmount_backup.sh

**Alt (v1.3.0):**
- Zeilen: 103
- Funktionen: 0
- Komplexität: Mittel
- Aufwand: 1.5h

**Neu (v2.0.0):** [SemVer: Major - BREAKING CHANGE]
- Zeilen: 351 (+241%)
- Funktionen: 1 (`safe_unmount_cleanup`)
- Komplexität: **Hoch**
- Aufwand: **3.5h (+2h)**
- **Breaking**: Exit code changed (1 → 0)

**Neue Features:**
- Cleanup-safe unmount (soft-fail mode)
- Dieselbe Multi-stage-Logik wie Segment 05
- Process blacklist integration
- Always-succeed für Cleanup-Kontext
- Informational process analysis

---

## 🎯 Aktualisierte Prioritäten

### Priorität 2: Mount & Storage Management

**Alt:** 5h Gesamtaufwand  
**Neu:** **10h Gesamtaufwand (+5h)**

| Segment | Alt | Neu | Δ | SemVer |
|---------|-----|-----|---|--------|
| 05_mount_backup.sh | 2h | **5h** | +3h | v2.1.0 (Minor) |
| 06_validate_mount.sh | 1.5h | 1.5h | - | - |
| 12_unmount_backup.sh | 1.5h | **3.5h** | +2h | v2.0.0 (Major) |

---

## 📅 Aktualisierter Zeitplan

### Gesamtaufwand

**Alt:** ~42h (5-6 Arbeitstage)  
**Neu:** ~47h (6 Arbeitstage)

### Tag-für-Tag Anpassungen

**Tag 2 - Nachmittag:**
```
Alt:
- 04:00-06:00: 05_mount_backup.sh (2h)
- 06:00-07:30: 06_validate_mount.sh (1.5h)
- 07:30-08:00: Buffer (0.5h)

Neu:
- 04:00-08:00: 05_mount_backup.sh (4h)
  → Segment 06 verschoben auf Tag 3
```

**Tag 3 - Vormittag:**
```
Alt:
- 00:00-01:00: 12_unmount_backup.sh (1h)
- 01:00-02:00: 01_validate_config.sh (1h)
- 02:00-03:00: 02_init_logging.sh (1h)
- 03:00-04:00: 07_init_borg_repo.sh (1h)

Neu:
- 00:00-01:00: 05_mount_backup.sh fertigstellen (1h)
- 01:00-02:30: 06_validate_mount.sh (1.5h)
- 02:30-04:00: 12_unmount_backup.sh Start (1.5h)
```

**Tag 3 - Nachmittag:**
```
Alt:
- 04:00-05:00: 08_borg_backup.sh (1h)
- 05:00-06:00: 09_borg_verify.sh (1h)
- 06:00-07:00: 10_borg_prune.sh (1h)
- 07:00-08:00: Buffer (1h)

Neu:
- 04:00-06:00: 12_unmount_backup.sh fertig (2h)
- 06:00-07:00: 01_validate_config.sh (1h)
- 07:00-08:00: Buffer/Review (1h)
```

**Tag 4 - Vormittag:**
```
Neu:
- 00:00-01:00: 02_init_logging.sh (1h)
- 01:00-02:00: 07_init_borg_repo.sh (1h)
- 02:00-03:00: 08_borg_backup.sh (1h)
- 03:00-04:00: 09_borg_verify.sh (1h)
```

---

## 📝 shdoc-Dokumentations-Fokus

### Segment 05 (v2.1.0): safe_unmount()

**Zu dokumentieren:**

```bash
# @brief Safely unmounts with intelligent process handling
# @description
#   Multi-stage unmount strategy:
#   1. Normal umount (3 attempts)
#   2. Force umount -f
#   3. Lazy umount -l
#   4. Process termination with blacklist protection
#
# @arg $1 string Mount point to unmount
# @global NEVER_KILL_PROCESSES Blacklist array
# @stdout Progress messages with stage indicators
# @stderr Error details and process information
# @exitcode 0 Successfully unmounted
# @exitcode 1 All unmount strategies failed
# @see validate_and_mount()
# @example
#   safe_unmount "/mnt/extern_backup"
```

### Segment 05 (v2.1.0): validate_and_mount()

**Zu dokumentieren:**

```bash
# @brief Validates and mounts backup device with error recovery
# @description
#   4-phase mount validation:
#   1. Check if already correctly mounted
#   2. Check if wrong device mounted → recovery
#   3. Verify device readiness
#   4. Attempt mount with validation
#
# @global BACKUP_MNT Mount point path
# @global BACKUP_DEV Device path (by-uuid)
# @global BACKUP_UUID Expected UUID
# @global TARGET_DIR Target directory for validation
# @stdout Progress messages and validation results
# @stderr Error details and recovery instructions
# @exitcode 0 Successfully mounted or already correct
# @exitcode 1 Mount failed after all recovery attempts
# @exitcode 2 Mount succeeded but UUID validation failed
# @see safe_unmount()
```

### Segment 12 (v2.0.0): safe_unmount_cleanup()

**Zu dokumentieren:

```bash
# @brief Cleanup-safe unmount (always succeeds)
# @description
#   Same multi-stage approach as segment 05, but:
#   - Never kills processes in cleanup context
#   - Always returns exit 0
#   - Provides warnings instead of errors
#   - Ensures HDD spindown and power-off execute
#
# @arg $1 string Mount point to unmount
# @global NEVER_KILL_PROCESSES Blacklist array
# @stdout Progress and informational messages
# @stderr Non-critical warnings
# @exitcode 0 Always (cleanup-safe mode)
# @see 05_mount_backup.sh safe_unmount()
```

---

## 🔍 Besondere Dokumentations-Anforderungen

### Process Blacklist

**Muss dokumentiert werden:**
- Welche Prozesse geschützt sind
- Warum sie geschützt sind
- Was passiert bei Detection
- Wie Manual Intervention aussieht

**Beispiel:**
```bash
# @global NEVER_KILL_PROCESSES Protected process names
#   - borg: Active backup operations
#   - docker/dockerd: Container runtime
#   - mysql/postgres: Database servers
#   - systemd: System processes
#   
# When protected process found:
#   - Safety abort with exit 1
#   - Manual intervention instructions
#   - Process details (PID, command)
```

### Error Recovery Stages

**Muss dokumentiert werden:**
- 4 Stufen mit Eskalation
- Wann welche Stufe greift
- Was jede Stufe tut
- Wann abgebrochen wird

**Beispiel:**
```bash
# Stage 1: Normal umount (graceful)
#   - 3 attempts with 2s waits
#   - Shows blocking processes (lsof)
#   - Non-destructive
#
# Stage 2: Force umount (-f)
#   - If stage 1 fails
#   - Attempts busy filesystem force
#
# Stage 3: Lazy umount (-l)
#   - Detaches immediately
#   - Kernel cleanup later
#   - Safe for most cases
#
# Stage 4: Process termination
#   - Analyzes blocking processes
#   - Checks against blacklist
#   - Protected → abort
#   - Safe → kill (SIGTERM → SIGKILL)
```

---

## ✅ Checkliste für Dokumentation

### Segment 05

- [ ] File header (@brief, @description, @version, @changed)
- [ ] Configuration constants documentation
- [ ] NEVER_KILL_PROCESSES array mit Rationale
- [ ] safe_unmount() function (vollständig)
- [ ] validate_and_mount() function (vollständig)
- [ ] Error recovery stages documented
- [ ] Process blacklist logic explained
- [ ] Examples for common scenarios
- [ ] @see cross-references

### Segment 12

- [ ] File header mit cleanup-safe Erklärung
- [ ] NEVER_KILL_PROCESSES (shared with 05)
- [ ] safe_unmount_cleanup() function
- [ ] Unterschied zu Segment 05 erklärt
- [ ] Why always exit 0 documented
- [ ] Cleanup context rationale
- [ ] Examples for cleanup scenarios
- [ ] @see cross-reference to segment 05

---

## 📈 Impact Assessment

**Positive Auswirkungen:**
- ✅ Dokumentation reflektiert aktuelle Komplexität
- ✅ Error Recovery klar erklärt
- ✅ Process Safety dokumentiert
- ✅ Wartbarkeit verbessert

**Herausforderungen:**
- ⚠️ +5h Dokumentationsaufwand
- ⚠️ Komplexere Funktions-Dokumentation
- ⚠️ Mehr Examples benötigt

**Fazit:**
- Lohnenswert: Kritische Segmente mit hoher Komplexität
- Dokumentation wird Portfolio-Quality erreichen
- Zusatzaufwand ist gerechtfertigt

---

**Status:** Update dokumentiert  
**Nächster Schritt:** Implementierung gemäß aktualisiertem Zeitplan starten
