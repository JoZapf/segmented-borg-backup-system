# Secrets Management - Conceptual Design and Technical Planning

**Version:** 1.0.0  
**Date:** 2026-01-21  
**Author:** Jo Zapf  
**Status:** Planning / Pre-Implementation  

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [Problem Statement](#problem-statement)
4. [Solution Options](#solution-options)
5. [Recommended Solution](#recommended-solution)
6. [Technical Design](#technical-design)
7. [Implementation Plan](#implementation-plan)
8. [Migration Strategy](#migration-strategy)
9. [Security Considerations](#security-considerations)
10. [Testing Strategy](#testing-strategy)
11. [Rollback Plan](#rollback-plan)

---

## Executive Summary

This document outlines the technical design and implementation plan for improving secrets management in the Segmented Borg Backup System. The current approach stores secrets (passwords, credentials) mixed with configuration data, creating maintenance overhead and security concerns.

**Goal:** Separate secrets from configuration, eliminate `.example` file duplication, and enable production configs to be stored in Git safely.

**Recommended Solution:** Config/Secrets Split with centralized `secrets.env` file.

**Expected Benefits:**
- ✅ Eliminate `.example` file maintenance overhead
- ✅ Production configs safely versioned in Git
- ✅ Clear separation of concerns (config vs. secrets)
- ✅ Simplified deployment workflow
- ✅ Centralized secrets management

---

## Current State Analysis

### File Structure (Current)

```
/opt/backup-system/config/
├── common.env                    # Contains RECOVERY_ZIP_PASSWORD
├── common.env.example            # Duplicated structure, placeholder values
├── profiles/
│   ├── system.env                # No secrets (uses BORG_PASSPHRASE_FILE)
│   ├── system.env.example        # Duplicated anonymized structure
│   ├── dev-data.env              # Contains NEXTCLOUD_DB_PASSWORD
│   └── dev-data.env.example      # Duplicated anonymized structure
/root/.config/borg/
└── passphrase                    # BORG_PASSPHRASE (separate location)
```

### Current Secrets Storage

| Secret | Location | Access Method | Security |
|--------|----------|---------------|----------|
| BORG_PASSPHRASE | `/root/.config/borg/passphrase` | File reference | `chmod 600`, root-only |
| NEXTCLOUD_DB_PASSWORD | `dev-data.env` | Direct export | `chmod 600`, root-only |
| RECOVERY_ZIP_PASSWORD | `common.env` | Direct export | `chmod 600`, root-only |
| SHELLY_IP | `common.env` | Direct export | `chmod 600`, root-only |

### Issues with Current Approach

**1. Configuration Duplication:**
- `.example` files must be manually kept in sync with production structure
- Changes require updating both production and example files
- High maintenance overhead
- Prone to drift between example and production

**2. Secrets Scattered Across Files:**
- `common.env` contains some secrets (RECOVERY_ZIP_PASSWORD)
- `dev-data.env` contains database passwords
- `/root/.config/borg/passphrase` is separate
- No centralized secrets management

**3. Git Workflow Problems:**
- Production configs in `.gitignore` (cannot be versioned)
- Configuration changes require manual copying to production
- No version control for production config structure
- `.example` files are poor documentation substitutes

**4. Deployment Complexity:**
- Manual file copying required for config updates
- Error-prone process (forget to update production after example)
- No atomic config updates
- Difficult to track configuration changes

**5. Security Concerns:**
- Secrets in plaintext (mitigated by file permissions)
- Multiple locations to secure
- Easy to accidentally commit secrets (if .gitignore misconfigured)

---

## Problem Statement

**Primary Problem:** Configuration and secrets are mixed, preventing production configs from being safely stored in Git while creating maintenance overhead through required `.example` file duplication.

**Secondary Problems:**
1. Deployment workflow requires manual file management
2. Configuration changes are not version-controlled in production
3. Secrets management is decentralized
4. Documentation (`.example` files) easily becomes outdated

**Success Criteria:**
- Production configs can be safely committed to Git
- Secrets are centrally managed and excluded from Git
- `.example` files are eliminated
- Deployment process is simplified
- Configuration changes are version-controlled

---

## Solution Options

### Option 1: Config/Secrets Split (RECOMMENDED)

**Concept:** Separate secrets into dedicated `secrets.env` file, production configs in Git.

```
/opt/backup-system/config/
├── common.env                    # ✅ In Git - no secrets
├── profiles/
│   ├── system.env                # ✅ In Git - no secrets
│   └── dev-data.env              # ✅ In Git - no secrets
└── secrets.env                   # ❌ NOT in Git - all secrets
```

**Pros:**
- ✅ Simple architecture (just one additional file)
- ✅ Production configs versioned in Git
- ✅ Eliminates all `.example` files
- ✅ Centralized secrets management
- ✅ Minimal code changes (just add one source line)
- ✅ Easy to understand and maintain

**Cons:**
- ⚠️ Secrets still in plaintext (mitigated by chmod 600)
- ⚠️ Shared secrets across all profiles (acceptable for single-user setup)

**Complexity:** Low  
**Security Level:** Medium  
**Maintenance:** Low  

---

### Option 2: systemd EnvironmentFile

**Concept:** Use systemd native secret injection via EnvironmentFile directive.

```ini
# /etc/systemd/system/backup-system@.service
[Service]
EnvironmentFile=-/opt/backup-system/config/secrets.env
EnvironmentFile=-/opt/backup-system/config/common.env
```

**Pros:**
- ✅ systemd-native approach
- ✅ Better isolation (secrets loaded only at runtime)
- ✅ Clear separation of concerns

**Cons:**
- ⚠️ Only works for systemd-invoked backups (not manual runs)
- ⚠️ Requires changes to systemd service file
- ⚠️ Less transparent (secrets loaded "magically")

**Complexity:** Medium  
**Security Level:** Medium  
**Maintenance:** Medium  

---

### Option 3: Password Store (pass) - Encrypted

**Concept:** Use GPG-encrypted password store for secret storage.

```bash
export BORG_PASSPHRASE=$(pass show backup/borg-passphrase)
export NEXTCLOUD_DB_PASSWORD=$(pass show backup/nextcloud-db)
```

**Pros:**
- ✅ True encryption (GPG-based)
- ✅ Linux best practice for password management
- ✅ Audit trail built-in
- ✅ Can be versioned (encrypted)

**Cons:**
- ⚠️ Complex setup (GPG keys for root user)
- ⚠️ May require interactive unlock (or agent)
- ⚠️ Additional dependency (password-store package)
- ⚠️ Overkill for single-user home lab?

**Complexity:** High  
**Security Level:** High  
**Maintenance:** Medium-High  

---

### Option 4: SOPS/age - Encrypted Config Files

**Concept:** Encrypt secrets files with SOPS/age, decrypt at deployment.

```yaml
# secrets.enc.yaml (encrypted, can be in Git!)
borg_passphrase: ENC[AES256_GCM,data:xxx,tag:yyy]
nextcloud_db_password: ENC[AES256_GCM,data:yyy,tag:zzz]
```

**Pros:**
- ✅ Secrets can be safely stored in Git (encrypted)
- ✅ Team-friendly (multiple keys possible)
- ✅ Industry best practice
- ✅ Good tooling (sops, age)

**Cons:**
- ⚠️ Additional dependencies (sops, age)
- ⚠️ Deployment step required (decrypt)
- ⚠️ More complex workflow
- ⚠️ Overkill for single-user setup

**Complexity:** High  
**Security Level:** High  
**Maintenance:** Medium  

---

### Comparison Matrix

| Solution | .example removal | Secrets security | Deployment | Complexity | Home-lab fit |
|----------|------------------|------------------|------------|------------|--------------|
| **Current** | ❌ | ⚠️ Plaintext | Manual | Low | ✅ |
| **Option 1 (Split)** | ✅ | ⚠️ Plaintext (separated) | `git pull` | **Low** ✅ | ✅ |
| **Option 2 (systemd)** | ✅ | ⚠️ Plaintext | `git pull` | Medium | ✅ |
| **Option 3 (pass)** | ✅ | ✅ GPG encrypted | Automated | High | ⚠️ |
| **Option 4 (SOPS)** | ✅ | ✅ Encrypted | Decrypt step | High | ⚠️ |

---

## Recommended Solution

**Selected Option:** Option 1 - Config/Secrets Split

**Rationale:**
1. **Simplicity:** Minimal architectural changes, easy to understand
2. **Effectiveness:** Solves all primary problems (config in Git, no .example duplication)
3. **Maintainability:** Low overhead, straightforward workflow
4. **Appropriate:** Right level of security for home-lab single-user scenario
5. **Extensibility:** Can be enhanced with Option 3 (pass) later if needed

**Security Posture:**
- Secrets remain in plaintext but in separate, protected file
- `chmod 600` and root-only access maintained
- Physical security of server is primary defense
- For home lab with single user, this is acceptable risk

**Future Enhancement Path:**
- Can migrate to Option 3 (pass) if multi-user access needed
- Can add Option 4 (SOPS) if team collaboration required
- Current design doesn't prevent future improvements

---

## Technical Design

### New File Structure

```
/opt/backup-system/config/
├── common.env                    # ✅ In Git - production config, no secrets
├── profiles/
│   ├── system.env                # ✅ In Git - production config, no secrets
│   └── dev-data.env              # ✅ In Git - production config, no secrets
└── secrets.env                   # ❌ NOT in Git - all secrets, chmod 600

/root/.config/borg/
└── (removed - passphrase now in secrets.env)
```

### secrets.env Structure

```bash
#!/usr/bin/env bash
# secrets.env
# @version 1.0.0
# @description Centralized secrets management for backup system
# @author Jo Zapf
# @changed 2026-01-21 - Initial secrets.env implementation
# @security CRITICAL: chmod 600, never commit to Git!

# ============================================================================
# BORG BACKUP CREDENTIALS
# ============================================================================
# Borg repository encryption passphrase
# Used by all profiles for repository encryption
export BORG_PASSPHRASE="REPLACE-WITH-YOUR-BORG-PASSPHRASE"

# ============================================================================
# HARDWARE CREDENTIALS
# ============================================================================
# Shelly Plug IP address (could be considered semi-secret)
export SHELLY_IP="192.168.X.X"

# ============================================================================
# NEXTCLOUD / DATABASE CREDENTIALS
# ============================================================================
# Nextcloud database password (dev-data profile)
export NEXTCLOUD_DB_PASSWORD="REPLACE-WITH-YOUR-DB-PASSWORD"

# ============================================================================
# RECOVERY / EXPORT CREDENTIALS
# ============================================================================
# Password for recovery key ZIP archives
export RECOVERY_ZIP_PASSWORD="REPLACE-WITH-YOUR-ZIP-PASSWORD"

# ============================================================================
# NOTES
# ============================================================================
# This file contains all secrets for the backup system.
# 
# Security requirements:
# - chmod 600 (read/write only by root)
# - Must be in .gitignore (NEVER commit to Git!)
# - Backup this file securely (encrypted USB, password manager)
# 
# To use:
# 1. Copy secrets.env.example to secrets.env
# 2. Fill in actual secret values
# 3. Set permissions: sudo chmod 600 /opt/backup-system/config/secrets.env
```

### secrets.env.example Structure

```bash
#!/usr/bin/env bash
# secrets.env.example
# @version 1.0.0
# @description Example template for secrets.env
# @note Copy to secrets.env and replace placeholder values

# BORG_PASSPHRASE: Your Borg repository encryption password
export BORG_PASSPHRASE="REPLACE-WITH-YOUR-BORG-PASSPHRASE"

# SHELLY_IP: IP address of Shelly Plug (if used)
export SHELLY_IP="192.168.X.X"

# NEXTCLOUD_DB_PASSWORD: Nextcloud database password (dev-data profile only)
export NEXTCLOUD_DB_PASSWORD="REPLACE-WITH-YOUR-DB-PASSWORD"

# RECOVERY_ZIP_PASSWORD: Password for recovery key ZIP archives
export RECOVERY_ZIP_PASSWORD="REPLACE-WITH-YOUR-ZIP-PASSWORD"
```

### Changes to common.env

**Remove:**
```bash
export SHELLY_IP="192.168.X.X"             # → Move to secrets.env
export RECOVERY_ZIP_PASSWORD="xxx"          # → Move to secrets.env
```

**Keep:**
```bash
export BACKUP_SYSTEM_VERSION="2.6.0"
export SHELLY_TOGGLE_AFTER_SEC="43200"
export DEVICE_WAIT_SECONDS="180"
export BACKUP_MNT="/mnt/extern_backup"
# ... all non-secret config ...
```

### Changes to dev-data.env

**Remove:**
```bash
export NEXTCLOUD_DB_PASSWORD="xxx"          # → Move to secrets.env
```

**Keep:**
```bash
export BACKUP_PROFILE="dev-data"
export BACKUP_SOURCES="/mnt/docker-data"
export NEXTCLOUD_DB_NAME="nextcloud"
export NEXTCLOUD_DB_USER="dbuser"
# ... all non-secret config ...
```

### Changes to main.sh

**Add after profile loading:**

```bash
# Load profile configuration
source "${PROFILE_FILE}"

# Load centralized secrets (NEW)
SECRETS_FILE="${CONFIG_DIR}/secrets.env"
if [ ! -f "${SECRETS_FILE}" ]; then
  echo "[ERROR] Secrets file not found: ${SECRETS_FILE}"
  echo "[ERROR] Please create secrets.env from secrets.env.example"
  echo "[ERROR] See docs/secrets_management.md for details"
  exit 1
fi

# Verify secrets file has correct permissions
SECRETS_PERMS=$(stat -c %a "${SECRETS_FILE}" 2>/dev/null || stat -f %A "${SECRETS_FILE}")
if [ "${SECRETS_PERMS}" != "600" ]; then
  echo "[ERROR] Secrets file has incorrect permissions: ${SECRETS_PERMS}"
  echo "[ERROR] Required: 600 (read/write by owner only)"
  echo "[ERROR] Fix with: sudo chmod 600 ${SECRETS_FILE}"
  exit 1
fi

source "${SECRETS_FILE}"

# Export all variables for segments
set -a
source "${CONFIG_DIR}/common.env"
source "${PROFILE_FILE}"
source "${SECRETS_FILE}"
set +a
```

### Changes to .gitignore

**Add:**
```
# Secrets (NEVER commit)
config/secrets.env
```

**Remove:**
```
# Old approach - no longer needed with secrets.env
config/common.env
config/profiles/system.env
config/profiles/dev-data.env
```

---

## Implementation Plan

### Phase 1: Preparation (Pre-Implementation)

**1.1 Document Current Secrets**
```bash
# Create inventory of all secrets and their locations
grep -r "PASSWORD\|PASSPHRASE\|SECRET" config/ > secrets_inventory.txt
```

**1.2 Create Test Environment**
```bash
# Backup current configs
cp -r /opt/backup-system/config /opt/backup-system/config.backup-$(date +%Y%m%d)
```

**1.3 Create secrets.env Template**
- Create `config/secrets.env.example`
- Document all required secrets with placeholders

### Phase 2: Code Changes

**2.1 Update main.sh**
- Add secrets.env loading
- Add permission validation
- Add error handling for missing secrets.env

**2.2 Create secrets.env**
- Copy from secrets.env.example
- Fill with actual production values
- Set `chmod 600`

**2.3 Update Config Files**
- Remove secrets from `common.env`
- Remove secrets from `dev-data.env`
- Keep all non-secret configuration

**2.4 Update .gitignore**
- Add `config/secrets.env`
- Remove exclusions for production configs

**2.5 Remove .example Files**
- Delete `common.env.example`
- Delete `system.env.example`
- Delete `dev-data.env.example`
- Keep only `secrets.env.example`

### Phase 3: Testing

**3.1 Validation Tests**
```bash
# Test 1: secrets.env missing
sudo rm /opt/backup-system/config/secrets.env
sudo /opt/backup-system/run-backup.sh system
# Expected: Error message about missing secrets.env

# Test 2: secrets.env wrong permissions
sudo chmod 644 /opt/backup-system/config/secrets.env
sudo /opt/backup-system/run-backup.sh system
# Expected: Error message about incorrect permissions

# Test 3: secrets.env correct
sudo chmod 600 /opt/backup-system/config/secrets.env
sudo /opt/backup-system/run-backup.sh system
# Expected: Backup succeeds
```

**3.2 Integration Tests**
```bash
# Test system profile backup
sudo /opt/backup-system/run-backup.sh system

# Test dev-data profile backup
sudo /opt/backup-system/run-backup.sh dev-data

# Verify secrets are loaded correctly
sudo /opt/backup-system/run-backup.sh system 2>&1 | grep -i "passphrase"
# Expected: No "passphrase missing" errors
```

**3.3 Git Tests**
```bash
# Verify production configs can be committed
git add config/common.env config/profiles/*.env
git status
# Expected: Files staged for commit

# Verify secrets.env is ignored
git status
# Expected: secrets.env NOT in "Changes to be committed"
```

### Phase 4: Documentation

**4.1 Update README.md**
- Update "Configuration" section
- Document new secrets.env approach
- Remove .example file references

**4.2 Update DEPLOYMENT.md**
- New deployment workflow
- secrets.env setup instructions

**4.3 Create SECRETS_MANAGEMENT.md**
- Detailed secrets.env guide
- Security best practices
- Troubleshooting

**4.4 Update CHANGELOG.md**
- Document breaking changes
- Migration instructions

### Phase 5: Deployment

**5.1 Development Environment (Windows)**
```bash
cd E:\Projects\linux-backup-system
git add config/common.env config/profiles/*.env config/secrets.env.example
git add .gitignore main.sh docs/
git commit -m "feat: Implement centralized secrets management (v2.7.0)"
git push
```

**5.2 Production Environment (Ubuntu)**
```bash
# Pull latest changes
cd /opt/backup-system
sudo git pull

# Create secrets.env from current production values
sudo cp config/secrets.env.example config/secrets.env
sudo nano config/secrets.env  # Fill in actual values
sudo chmod 600 config/secrets.env

# Verify ownership
sudo chown root:root config/secrets.env

# Test
sudo /opt/backup-system/run-backup.sh system --dry-run
```

---

## Migration Strategy

### Pre-Migration Checklist

- [ ] Backup current `/opt/backup-system/config/` directory
- [ ] Document all current secret values
- [ ] Test environment prepared
- [ ] All changes reviewed and approved
- [ ] Documentation updated

### Migration Steps

**Step 1: Extract Secrets**

```bash
# Create secrets inventory from current config
cd /opt/backup-system/config

# Extract BORG_PASSPHRASE
cat /root/.config/borg/passphrase

# Extract SHELLY_IP
grep SHELLY_IP common.env

# Extract NEXTCLOUD_DB_PASSWORD
grep NEXTCLOUD_DB_PASSWORD profiles/dev-data.env

# Extract RECOVERY_ZIP_PASSWORD
grep RECOVERY_ZIP_PASSWORD common.env
```

**Step 2: Create secrets.env**

```bash
# Copy template
sudo cp secrets.env.example secrets.env

# Edit with actual values
sudo nano secrets.env
# (paste extracted secrets)

# Secure permissions
sudo chmod 600 secrets.env
sudo chown root:root secrets.env
```

**Step 3: Update Config Files**

```bash
# Remove secrets from common.env
sudo nano common.env
# Delete SHELLY_IP line
# Delete RECOVERY_ZIP_PASSWORD line

# Remove secrets from dev-data.env
sudo nano profiles/dev-data.env
# Delete NEXTCLOUD_DB_PASSWORD line
```

**Step 4: Test New Configuration**

```bash
# Dry-run test
sudo /opt/backup-system/run-backup.sh system --dry-run

# Full test (verify mode, won't create backup)
sudo /opt/backup-system/main.sh system
# Watch for secret loading errors
```

**Step 5: Commit Changes to Git**

```bash
# Stage production configs (now safe!)
git add config/common.env
git add config/profiles/system.env
git add config/profiles/dev-data.env
git add config/secrets.env.example
git add .gitignore

# Commit
git commit -m "feat: Migrate to centralized secrets.env"
git push
```

**Step 6: Cleanup**

```bash
# Remove /root/.config/borg/passphrase (now in secrets.env)
sudo rm /root/.config/borg/passphrase

# Remove .example files (no longer needed)
sudo rm config/common.env.example
sudo rm config/profiles/*.env.example
```

### Rollback Procedure

If issues occur during migration:

```bash
# Restore backup
sudo rm -rf /opt/backup-system/config
sudo cp -r /opt/backup-system/config.backup-$(date +%Y%m%d) \
  /opt/backup-system/config

# Revert Git changes
cd /opt/backup-system
git reset --hard HEAD~1

# Test old configuration
sudo /opt/backup-system/run-backup.sh system
```

---

## Security Considerations

### Threat Model

**Primary Threats:**
1. Unauthorized access to backup system
2. Accidental exposure of secrets (Git commit)
3. Secrets leakage through logs
4. Lateral movement after server compromise

**Mitigations:**

| Threat | Current Mitigation | Additional Measures |
|--------|-------------------|---------------------|
| Unauthorized access | SSH key auth, firewall | Fail2ban, security updates |
| Git commit leak | .gitignore, pre-commit hooks | secrets.env separate file |
| Log leakage | Secrets not logged | Audit logging code |
| Lateral movement | Minimal services, root-only | AppArmor, least privilege |

### File Permissions

```bash
# secrets.env
-rw------- 1 root root  secrets.env          # 600

# Config files (no secrets)
-rw-r--r-- 1 root root  common.env           # 644 (can be relaxed)
-rw-r--r-- 1 root root  system.env           # 644 (can be relaxed)
-rw-r--r-- 1 root root  dev-data.env         # 644 (can be relaxed)
```

**Rationale:** With secrets separated, config files don't need strict permissions and can be world-readable (still root-owned).

### Backup Strategy for Secrets

**Critical:** secrets.env must be backed up separately!

**Options:**

1. **Encrypted USB Drive** (recommended)
   ```bash
   sudo cp /opt/backup-system/config/secrets.env /media/usb-encrypted/
   ```

2. **Password Manager**
   - Store secrets.env content in BitWarden/LastPass/1Password
   - Tag as "backup-system-secrets"

3. **Encrypted Cloud Storage**
   ```bash
   gpg -c secrets.env
   # Upload secrets.env.gpg to Nextcloud/Dropbox
   ```

4. **Paper Backup** (for disaster recovery)
   - Print secrets.env
   - Store in safe/lockbox

**⚠️ CRITICAL:** Without secrets.env backup, encrypted Borg repositories are unrecoverable!

### Audit Logging

Add logging for secrets.env access:

```bash
# In main.sh, after loading secrets.env
logger -t backup-system "Secrets loaded from ${SECRETS_FILE} by $(whoami)"
```

Review with:
```bash
journalctl -t backup-system | grep "Secrets loaded"
```

### Regular Security Checks

```bash
# Check secrets.env permissions
find /opt/backup-system/config -name "secrets.env" -exec ls -la {} \;

# Verify secrets.env is not in Git
git ls-files | grep secrets.env
# Expected: (empty - no output)

# Check for secrets in Git history
git log -p | grep -i "password\|passphrase"
# Expected: (none found, except in documentation)
```

---

## Testing Strategy

### Unit Tests

**Test 1: secrets.env Missing**
```bash
test_missing_secrets_env() {
  sudo mv /opt/backup-system/config/secrets.env \
    /opt/backup-system/config/secrets.env.bak
  
  result=$(sudo /opt/backup-system/run-backup.sh system 2>&1)
  
  if echo "$result" | grep -q "Secrets file not found"; then
    echo "✅ PASS: Missing secrets.env detected"
  else
    echo "❌ FAIL: Missing secrets.env not detected"
  fi
  
  sudo mv /opt/backup-system/config/secrets.env.bak \
    /opt/backup-system/config/secrets.env
}
```

**Test 2: Wrong Permissions**
```bash
test_wrong_permissions() {
  sudo chmod 644 /opt/backup-system/config/secrets.env
  
  result=$(sudo /opt/backup-system/run-backup.sh system 2>&1)
  
  if echo "$result" | grep -q "incorrect permissions"; then
    echo "✅ PASS: Wrong permissions detected"
  else
    echo "❌ FAIL: Wrong permissions not detected"
  fi
  
  sudo chmod 600 /opt/backup-system/config/secrets.env
}
```

**Test 3: Secret Loading**
```bash
test_secret_loading() {
  # Run backup script and check if BORG_PASSPHRASE is set
  sudo bash -c '
    source /opt/backup-system/config/secrets.env
    if [ -n "$BORG_PASSPHRASE" ]; then
      echo "✅ PASS: BORG_PASSPHRASE loaded"
    else
      echo "❌ FAIL: BORG_PASSPHRASE not loaded"
    fi
  '
}
```

### Integration Tests

**Test 4: Full Backup Cycle**
```bash
test_full_backup_cycle() {
  # Run complete backup
  sudo /opt/backup-system/run-backup.sh system
  
  # Check exit code
  if [ $? -eq 0 ]; then
    echo "✅ PASS: Full backup completed successfully"
  else
    echo "❌ FAIL: Backup failed"
  fi
  
  # Verify secrets were used correctly
  if sudo borg list /mnt/extern_backup/.../borgrepo >/dev/null 2>&1; then
    echo "✅ PASS: Borg repository accessible (passphrase correct)"
  else
    echo "❌ FAIL: Borg repository not accessible"
  fi
}
```

### Security Tests

**Test 5: Git Ignore**
```bash
test_git_ignore() {
  cd /opt/backup-system
  
  if git status | grep -q "secrets.env"; then
    echo "❌ FAIL: secrets.env appears in git status"
  else
    echo "✅ PASS: secrets.env properly ignored by Git"
  fi
}
```

**Test 6: File Permissions**
```bash
test_file_permissions() {
  perms=$(stat -c %a /opt/backup-system/config/secrets.env)
  
  if [ "$perms" = "600" ]; then
    echo "✅ PASS: secrets.env has correct permissions (600)"
  else
    echo "❌ FAIL: secrets.env has wrong permissions ($perms)"
  fi
}
```

---

## Rollback Plan

### Trigger Conditions

Rollback if:
- [ ] Backup fails after migration
- [ ] Secrets not loading correctly
- [ ] Production issues within 24 hours
- [ ] Critical secrets exposed

### Rollback Steps

**1. Immediate Rollback (< 1 hour after migration)**

```bash
# Stop any running backups
sudo systemctl stop backup-system@system.service
sudo systemctl stop backup-system@dev-data.service

# Restore config backup
sudo rm -rf /opt/backup-system/config
sudo cp -r /opt/backup-system/config.backup-$(date +%Y%m%d) \
  /opt/backup-system/config

# Revert Git changes
cd /opt/backup-system
git reset --hard HEAD~1

# Test old configuration
sudo /opt/backup-system/run-backup.sh system --dry-run

# If successful, resume normal operations
sudo systemctl start backup-system@system.timer
sudo systemctl start backup-system@dev-data-daily.timer
```

**2. Partial Rollback (Keep Git changes, restore secrets to old locations)**

```bash
# Restore /root/.config/borg/passphrase
sudo mkdir -p /root/.config/borg
echo "$BORG_PASSPHRASE" | sudo tee /root/.config/borg/passphrase
sudo chmod 600 /root/.config/borg/passphrase

# Re-add secrets to config files
sudo nano /opt/backup-system/config/common.env
# Add back SHELLY_IP, RECOVERY_ZIP_PASSWORD

sudo nano /opt/backup-system/config/profiles/dev-data.env
# Add back NEXTCLOUD_DB_PASSWORD

# Modify main.sh to skip secrets.env loading
sudo nano /opt/backup-system/main.sh
# Comment out secrets.env loading section

# Test
sudo /opt/backup-system/run-backup.sh system
```

**3. Complete Rollback (> 24 hours, Git history cleanup)**

```bash
# Revert Git commits
cd /opt/backup-system
git log --oneline -5  # Find commit hash before migration
git reset --hard <commit-hash>
git push --force-with-lease

# Restore production configs
# (Follow Immediate Rollback steps)

# Document lessons learned
echo "Migration failed: <reason>" >> MIGRATION_LOG.md
```

### Post-Rollback Checklist

- [ ] Verify backups are running
- [ ] Check systemd timers are active
- [ ] Test manual backup run
- [ ] Document rollback reason
- [ ] Plan remediation for next attempt

---

## Appendix

### A: File Checksums (Pre-Migration)

```bash
# Generate checksums before migration
cd /opt/backup-system
sha256sum config/common.env > config-checksums-before.txt
sha256sum config/profiles/*.env >> config-checksums-before.txt
sha256sum /root/.config/borg/passphrase >> config-checksums-before.txt
```

### B: Secrets Inventory Template

```
Secret Name: BORG_PASSPHRASE
Current Location: /root/.config/borg/passphrase
Used By: All profiles
New Location: config/secrets.env
Migration Status: [ ] Not Started [ ] In Progress [ ] Complete

Secret Name: NEXTCLOUD_DB_PASSWORD
Current Location: config/profiles/dev-data.env
Used By: dev-data profile
New Location: config/secrets.env
Migration Status: [ ] Not Started [ ] In Progress [ ] Complete

...
```

### C: Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-01-21 | Jo Zapf | Initial planning document |

---

**End of Document**
