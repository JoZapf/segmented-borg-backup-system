# Docker & Nextcloud Backup Profile

Guide for backing up Docker containers with Nextcloud database dumps.

---

## Overview

The `dev-data` profile is designed for backing up Docker development environments that include Nextcloud instances. It provides:

- ✅ **Automated DB Dumps** - Nextcloud database dumped before backup
- ✅ **Container Management** - Stops containers before backup, restarts after
- ✅ **State Preservation** - Saves and restores exact container states
- ✅ **Consistency Checks** - Verifies database dump integrity
- ✅ **Downtime Tracking** - Logs how long containers were offline

---

## Backup Flow

**Important:** The dev-data profile defines PRE/POST segments that run **in addition to** the standard MAIN segments (01-13) that all profiles execute.

```
┌─────────────────────────────────────────────────┐
│ PRE-BACKUP Phase                                │
├─────────────────────────────────────────────────┤
│ 1. Nextcloud DB Dump                            │
│    → Export database to SQL dump                │
│    → Verify dump integrity                      │
│    → Compress dump (gzip)                       │
│    → Store in backup target                     │
│                                                  │
│ 2. Docker Container Stop                        │
│    → Save list of running containers            │
│    → Stop all containers gracefully             │
│    → Verify all stopped                         │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ MAIN BACKUP Phase                               │
├─────────────────────────────────────────────────┤
│ 3-12. Standard Borg Backup                      │
│    → Mount, validate, backup, verify, prune     │
│    (Shelly power control DISABLED)              │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ POST-CLEANUP Phase                              │
├─────────────────────────────────────────────────┤
│ 13. Docker Container Start                      │
│    → Read saved container IDs                   │
│    → Restart containers in same order           │
│    → Verify all restarted                       │
│    → Calculate downtime                         │
└─────────────────────────────────────────────────┘
```

---

## Configuration

### Step 1: Copy Example Config

```bash
sudo cp /opt/backup-system/config/profiles/dev-data.env.example \
        /opt/backup-system/config/profiles/dev-data.env
```

### Step 2: Configure Profile

```bash
sudo nano /opt/backup-system/config/profiles/dev-data.env
```

**Required Changes:**

```bash
# 1. Backup Source (your Docker data directory)
export BACKUP_SOURCES="/mnt/docker-data"

# 2. Backup Target UUID
export BACKUP_UUID="your-backup-hdd-uuid-here"

# 3. HDD Device
export HDD_DEVICE="/dev/sda"  # Your backup HDD

# 4. Archive Prefix
export ARCHIVE_PREFIX="yourhostname-docker-data"

# 5. Nextcloud Database Credentials
export NEXTCLOUD_DB_PASSWORD="your-nextcloud-db-password"
export NEXTCLOUD_DB_NAME="nextcloud"
export NEXTCLOUD_DB_USER="nextcloud"
```

**Optional Settings:**

```bash
# Docker stop timeout (seconds)
export DOCKER_STOP_TIMEOUT="30"

# Database type
export NEXTCLOUD_DB_TYPE="mariadb"  # or: mysql, postgresql, postgres

# Disable Nextcloud dumps (if not using Nextcloud)
export NEXTCLOUD_ENABLED="false"

# Disable Docker management (backup only, no container control)
export DOCKER_ENABLED="false"
```

---

## Finding Required Values

### Get Backup HDD UUID

```bash
sudo blkid | grep sda
# Look for UUID="..."
```

### Get Nextcloud DB Password

```bash
# From Nextcloud config
sudo cat /var/www/nextcloud/config/config.php | grep dbpassword

# Or from Docker compose
sudo cat /path/to/docker-compose.yml | grep MYSQL_PASSWORD
```

### Verify Docker is Running

```bash
docker ps
# Should list running containers
```

---

## Testing

### Test 1: Database Dump

```bash
# Test DB dump segment only
sudo /opt/backup-system/segments/pre_01_nextcloud_db_dump.sh

# Check dump was created
ls -lh /mnt/system_backup/creaThink_docker-data/database-dumps/
```

Expected output:
```
[PRE-01] Nextcloud DB dump completed successfully
[PRE-01] Dump size: 45 MB
[PRE-01] Compressed size: 12 MB
[PRE-01] Compression ratio: 73%
```

### Test 2: Docker Stop/Start

```bash
# Test Docker control segments
sudo /opt/backup-system/segments/pre_02_docker_stop.sh
docker ps  # Should show no containers

sudo /opt/backup-system/segments/post_01_docker_start.sh
docker ps  # Should show containers again
```

Expected output:
```
[PRE-02] Found 8 running containers
[PRE-02] Container stop summary:
[PRE-02]   Stopped: 8
[PRE-02]   Failed: 0

[POST-01] Container start summary:
[POST-01]   Started: 8
[POST-01]   Failed: 0
[POST-01] Container downtime: 2m 15s
```

### Test 3: Full Backup

```bash
# Run full backup with dev-data profile
sudo /opt/backup-system/main.sh dev-data

# Monitor logs
journalctl -u backup-system@dev-data.service -f
```

---

## Automated Scheduling

### Daily Backup Timer

```bash
# Create timer for dev-data profile
sudo tee /etc/systemd/system/backup-dev-data-daily.timer > /dev/null << 'EOF'
[Unit]
Description=Daily Docker Data Backup Timer
Requires=backup-system@dev-data.service

[Timer]
Unit=backup-system@dev-data.service
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable backup-dev-data-daily.timer
sudo systemctl start backup-dev-data-daily.timer

# Check schedule
systemctl list-timers backup-dev-data-daily.timer
```

---

## Troubleshooting

### Issue: Database Dump Fails

**Error:** `mysqldump: Access denied`

**Solution:**
```bash
# Test database connection
mysql -h localhost -u nextcloud -p nextcloud
# If this fails, check credentials in dev-data.env
```

---

### Issue: Docker Containers Don't Restart

**Error:** `Container X failed to start`

**Solution:**
```bash
# Check container logs
docker logs container_name

# Manually start failed container
docker start container_name

# Check for dependency issues
docker-compose up -d
```

---

### Issue: Container IDs File Not Found

**Error:** `No container IDs file found`

**Solution:**
This is normal if no containers were running before backup. If containers *were* running:

```bash
# Check state directory
ls -la /tmp/backup-system-state/

# Verify containers were saved
cat /tmp/backup-system-state/running_containers.txt
```

---

## Expected Downtime

**Typical backup duration:**
```
DB Dump:          30-60 seconds
Container Stop:   10-20 seconds
Backup (1st):     10-15 minutes (full)
Backup (incremental): 1-2 minutes
Verify:           45-60 minutes (optional)
Container Start:  10-20 seconds

Total Downtime (without verify): 2-3 minutes
Total Downtime (with verify):    46-61 minutes
```

**Recommendation:** Disable segment 09 (verify) for daily backups to minimize downtime.

---

## Safety Features

### Database Dump Verification

- ✅ Checks dump file is not empty
- ✅ Verifies completion markers
- ✅ Scans for SQL errors
- ✅ Logs dump size and compression ratio
- ✅ Fails backup if dump is invalid

### Container State Preservation

- ✅ Saves exact list of running containers
- ✅ Preserves container start order
- ✅ Graceful shutdown (configurable timeout)
- ✅ Logs which containers failed to start
- ✅ Calculates total downtime

### Error Handling

- ✅ Backup aborts if DB dump fails
- ✅ Backup aborts if containers can't be stopped
- ✅ Containers restart even if backup fails
- ✅ Warnings logged for partial failures

---

## Maintenance

### Cleanup Old DB Dumps

Database dumps are automatically cleaned up (keeps last 7). Manual cleanup:

```bash
# List all dumps
ls -lh /mnt/system_backup/creaThink_docker-data/database-dumps/

# Remove dumps older than 30 days
find /mnt/system_backup/creaThink_docker-data/database-dumps/ \
  -name "nextcloud_*.sql.gz" -mtime +30 -delete
```

### Monitor Backup Size

```bash
# Check repository size
sudo borg info /mnt/system_backup/creaThink_docker-data/borgrepo

# Check Docker data size
du -sh /mnt/docker-data
```

---

## Advanced Configuration

### Multiple Nextcloud Instances

If you have multiple Nextcloud instances, create multiple profiles:

```bash
# dev-data-nc1.env
export NEXTCLOUD_DB_NAME="nextcloud1"
export NEXTCLOUD_DB_USER="nc1_user"

# dev-data-nc2.env  
export NEXTCLOUD_DB_NAME="nextcloud2"
export NEXTCLOUD_DB_USER="nc2_user"
```

### Disable Nextcloud but Keep Docker

```bash
# In dev-data.env
export NEXTCLOUD_ENABLED="false"
export DOCKER_ENABLED="true"
```

### Backup Without Stopping Containers

**Not recommended** (data inconsistency), but possible:

```bash
# In dev-data.env
export DOCKER_ENABLED="false"

# Remove PRE_BACKUP_SEGMENTS and POST_CLEANUP_SEGMENTS
unset PRE_BACKUP_SEGMENTS
unset POST_CLEANUP_SEGMENTS
```

---

## Security Notes

**⚠️ CRITICAL: Database Password in Config**

The `dev-data.env` file contains your Nextcloud database password in plain text!

**Protection:**
```bash
# Ensure restrictive permissions
sudo chmod 600 /opt/backup-system/config/profiles/dev-data.env

# Verify
ls -l /opt/backup-system/config/profiles/dev-data.env
# Should show: -rw------- root root
```

**Never commit actual config:**
- ✅ `dev-data.env.example` is safe (no real password)
- ❌ `dev-data.env` is in `.gitignore` (has real password)

---

## Monitoring

### Check Last Backup

```bash
# Via systemd
systemctl status backup-system@dev-data.service

# Via borg
sudo borg list /mnt/system_backup/creaThink_docker-data/borgrepo | tail -5
```

### View Backup Logs

```bash
# systemd logs
journalctl -u backup-system@dev-data.service -n 100

# Local logs
ls -lt /var/log/extern_backup/dev-data_*.log | head -1
tail -f /var/log/extern_backup/dev-data_$(date +%Y-%m-%d)_*.log
```

---

## FAQ

**Q: Can I run system and dev-data backups simultaneously?**  
A: No, they use the same Borg lock. Schedule them at different times.

**Q: What if my backup takes longer than the container stop timeout?**  
A: Containers restart in POST-CLEANUP phase, which runs *after* backup completes. Backup duration doesn't affect timeout.

**Q: Do I need to backup the database separately if it's in a Docker volume?**  
A: Yes! Docker volumes may not capture database state correctly. DB dumps ensure consistency.

**Q: Can I use this for PostgreSQL?**  
A: Yes! Set `NEXTCLOUD_DB_TYPE="postgresql"` in config.

---

## Related Documentation

- [Main Installation Guide](INSTALLATION.md)
- [systemd Integration](SYSTEMD.md)
- [Security Guide](SECURITY.md)
