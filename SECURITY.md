# Security

## Sensitive Data Protection

**NEVER commit to Git:**
- `config/common.env` - Shelly IP, shared settings
- `config/profiles/*.env` - UUIDs, hostnames, credentials  
- `/root/.config/borg/passphrase` - Backup encryption key
- `logs/` - May contain sensitive paths

**Protected by `.gitignore`** - These files are automatically excluded.

---

## File Permissions

Production configs must be root-only:

```bash
sudo chmod 600 /opt/backup-system/config/common.env
sudo chmod 600 /opt/backup-system/config/profiles/*.env
sudo chmod 600 /root/.config/borg/passphrase
```

---

## Templates

Use `*.example` files as templates:
- `config/common.env.example`
- `config/profiles/system.env.example`
- `config/profiles/data.env.example`
- `config/profiles/dev-data.env.example`

Copy and customize with your real values.

---

## Borg Passphrase

**Critical:** Without the passphrase, backups are unrecoverable.

**Store securely:**
- Password manager (recommended)
- Encrypted USB drive (offline)
- Printed backup in safe

**Never:**
- Plain text on system
- Email or cloud (unless encrypted)

---

## AI Assistants

Project includes `AI_GUIDELINES.md` and git hooks to prevent:
- AI credits in commits
- Unauthorized author modifications
- Attribution claims

See [AI_GUIDELINES.md](AI_GUIDELINES.md) for details.

---

## Pre-Commit Checklist

Before pushing to public repositories:

```bash
# Verify no sensitive data leaked
git grep -i "uuid" | grep -v "REPLACE" | grep -v "example"
git grep "192.168"
git status --ignored

# Ensure hooks active
test -x .git/hooks/commit-msg && echo "✓ Hook active"
```

---

## Backup System Security Features

**Built-in protections:**
- UUID validation prevents wrong disk writes
- Borg encryption (repokey BLAKE2b)
- Safe HDD head parking before power-off
- Comprehensive error handling
- Dual logging for audit trail

See [VERIFICATION.md](docs/VERIFICATION.md) for testing procedures.
