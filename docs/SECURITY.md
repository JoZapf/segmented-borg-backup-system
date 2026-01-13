# Security & Privacy Guide

## Overview

This backup system handles sensitive information that must be protected from unauthorized access and should never be committed to version control.

---

## 🔒 Sensitive Data Classification

### CRITICAL (Never share publicly)
- **Borg Passphrase** (`/root/.config/borg/passphrase`)
  - Required to decrypt backups
  - Without this, backups are unrecoverable
  - Store securely offline (password manager, encrypted USB)

### PRIVATE (Do not commit to Git)
- **HDD UUIDs** (in `config/profiles/*.env`)
  - Unique identifier for your backup drives
  - Not directly exploitable, but reveals hardware config
  
- **IP Addresses** (in `config/common.env`)
  - Shelly Plug IP address
  - Reveals local network topology
  
- **Hostnames** (in `config/profiles/*.env`)
  - Archive prefixes and target directories
  - Can reveal system/organization names
  
- **Device Paths** (in `config/profiles/*.env`)
  - HDD device names (/dev/sdc, etc.)
  - Reveals hardware configuration

### PUBLIC (Safe to share)
- All code in `segments/`, `tests/`, `systemd/`
- Documentation in `docs/`
- Example configurations (`*.example` files)

---

## 🛡️ Protection Mechanisms

### 1. .gitignore Protection

The following files are **automatically excluded from Git**:

```
config/common.env           # Contains Shelly IP
config/profiles/system.env  # Contains UUIDs, hostnames
config/profiles/data.env    # Contains UUIDs, hostnames
```

### 2. Example Files (Safe Templates)

Anonymized versions provided for reference:

```
config/common.env.example           # Template with placeholders
config/profiles/system.env.example  # Template with placeholders
config/profiles/data.env.example    # Template with placeholders
```

### 3. File Permissions

Configuration files should be readable only by root:

```bash
sudo chmod 600 /opt/backup-system/config/common.env
sudo chmod 600 /opt/backup-system/config/profiles/*.env
sudo chmod 600 /root/.config/borg/passphrase
```

---

## 🚨 What to Do Before Sharing

### Sharing Code on GitHub

✅ **Safe to commit:**
- All code files (`main.sh`, `segments/*.sh`)
- All documentation (`docs/*.md`)
- All tests (`tests/*.test.sh`)
- Example configs (`*.example`)
- systemd unit files

❌ **NEVER commit:**
- Actual config files (`common.env`, `system.env`, `data.env`)
- Borg passphrase
- Log files
- Any files containing real UUIDs, IPs, or hostnames

### Sharing Logs for Troubleshooting

When sharing logs, **redact** the following:

```bash
# Replace real values with placeholders
sed -i 's/f2c4624a-72ee-5e4b-85f8-a0d7f02e702f/REDACTED-UUID/g' logfile.txt
sed -i 's/192\.168\.10\.164/192.168.X.X/g' logfile.txt
sed -i 's/creaThink/HOSTNAME/g' logfile.txt
```

---

## 🔐 Backup Security Best Practices

### 1. Borg Passphrase

**Storage:**
- ✅ Password manager (LastPass, 1Password, Bitwarden)
- ✅ Encrypted USB drive (stored separately from backup HDD)
- ✅ Printed on paper in safe
- ❌ Plain text file on same computer
- ❌ Email to yourself
- ❌ Cloud storage (unless encrypted)

**Strength:**
```bash
# WEAK (❌)
mypassword

# MEDIUM (⚠️)
MyP@ssw0rd2024

# STRONG (✅)
correct-horse-battery-staple-7394
# or
Tr0ub4dor&3-elephant-window-cascade
```

### 2. Config Files

**On Production System:**
```bash
# Correct permissions
-rw------- root root common.env
-rw------- root root system.env

# Anyone can read (❌ BAD!)
-rw-r--r-- root root common.env
```

**Backup Your Configs:**
```bash
# Create encrypted backup of configs
sudo tar czf ~/backup-configs.tar.gz /opt/backup-system/config/
gpg --symmetric --cipher-algo AES256 ~/backup-configs.tar.gz
# Store backup-configs.tar.gz.gpg securely offline
```

### 3. Network Security

**Shelly Plug:**
- ✅ Use static IP or DHCP reservation
- ✅ Keep on isolated VLAN (if possible)
- ✅ Disable cloud access if not needed
- ✅ Update firmware regularly
- ❌ Expose to internet

---

## 📋 Security Checklist

Before going public with your backup system:

- [ ] Verify `.gitignore` includes actual config files
- [ ] Check no real UUIDs in committed files (`git grep "f2c4624a"`)
- [ ] Check no real IPs in committed files (`git grep "192.168"`)
- [ ] Check no hostnames in committed files (`git grep "creaThink"`)
- [ ] Borg passphrase backed up securely offline
- [ ] Config files have 600 permissions
- [ ] Example files contain only placeholders
- [ ] Logs directory not committed (`logs/` in .gitignore)
- [ ] No test archives committed (`.zip`, `.tar.gz` in .gitignore)

---

## 🔍 Verifying Clean Repository

```bash
# Check for potential leaks
cd /path/to/backup-system
git grep -i "uuid" | grep -v "REPLACE"
git grep -i "192.168"
git grep -i "your-hostname"

# Check .gitignore is working
git status --ignored

# Check what would be committed
git add -A --dry-run
```

---

## 🆘 If You Accidentally Commit Sensitive Data

### Remove from Git History

```bash
# Remove file from all commits (⚠️ REWRITES HISTORY!)
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch config/profiles/system.env" \
  --prune-empty --tag-name-filter cat -- --all

# Force push (⚠️ ONLY if not yet public!)
git push --force --all
```

### After Public Exposure

If sensitive data was already pushed publicly:

1. **Borg Passphrase leaked?**
   - Create new Borg repository with new passphrase
   - Migrate backups to new repository
   - Old backups are compromised!

2. **UUID/IP leaked?**
   - Low risk if no other info leaked
   - Consider rotating if very security-sensitive

3. **Hostname leaked?**
   - Low risk unless combined with other info
   - May reveal personal/company identity

---

## 📚 References

- [Git Secret Management](https://git-secret.io/)
- [Borg Security Docs](https://borgbackup.readthedocs.io/en/stable/quickstart.html#encryption)
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)

---

## ✅ Summary

**Golden Rules:**
1. Never commit actual config files to Git
2. Always use `.example` files for templates
3. Back up Borg passphrase securely offline
4. Use 600 permissions for sensitive files
5. Redact sensitive data before sharing logs

**Remember:** Security is not about perfection, it's about making attack harder than the value of the data.
