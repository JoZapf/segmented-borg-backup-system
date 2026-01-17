#!/usr/bin/env bash
# post_01_export_recovery_keys.sh (for system profile)
# @version 1.2.0
# @description Export Borg repository keys and recovery information to encrypted ZIP archive
# @author JoZapf
# @changed 2026-01-17 - Fixed passphrase handling: read from BORG_PASSPHRASE_FILE
# @date 2026-01-16
#
# Purpose:
# - Automatically exports Borg repository keys after successful backups
# - Creates password-protected ZIP archives with recovery information
# - Only creates new exports when repository is new or keys are missing
# - Ensures recovery keys are available for disaster recovery
#
# Requirements:
# - zip command (apt install zip)
# - borg command (apt install borgbackup)
# - Variables from profile and common.env
#
# Usage:
# Automatically called by main.sh as POST_BACKUP segment
#
# Configuration (common.env):
# - RECOVERY_ENABLED="true"               # Enable/disable recovery key export
# - RECOVERY_DIR="/path/to/recovery"      # Where to store recovery ZIPs
# - RECOVERY_ZIP_PASSWORD="password"      # ZIP encryption password (leave empty for no password)
# - RECOVERY_OWNER="user:group"           # File ownership (e.g., "jo:jo")

set -euo pipefail

# Source common functions if available
if [ -f "${SCRIPT_DIR:-/opt/backup-system}/lib/common.sh" ]; then
    source "${SCRIPT_DIR}/lib/common.sh"
fi

# Logging function fallback
log() {
    local level="$1"
    shift
    local message="$*"
    local prefix="[POST-01]"
    
    case "$level" in
        INFO)  echo "$prefix $message" ;;
        WARN)  echo "$prefix [WARN] $message" ;;
        ERROR) echo "$prefix [ERROR] $message" >&2 ;;
    esac
}

# Check if recovery export is enabled
check_recovery_enabled() {
    if [ "${RECOVERY_ENABLED:-false}" != "true" ]; then
        log INFO "Recovery key export disabled (RECOVERY_ENABLED != true)"
        log INFO "Enable in common.env: export RECOVERY_ENABLED=\"true\""
        return 1
    fi
    return 0
}

# Validate recovery configuration
validate_recovery_config() {
    log INFO "Validating recovery configuration..."
    
    # Check RECOVERY_DIR
    if [ -z "${RECOVERY_DIR:-}" ]; then
        log ERROR "RECOVERY_DIR not configured in common.env"
        return 1
    fi
    
    # Create recovery directory if needed
    if [ ! -d "$RECOVERY_DIR" ]; then
        log INFO "Creating recovery directory: $RECOVERY_DIR"
        mkdir -p "$RECOVERY_DIR"
        
        # Set ownership if specified
        if [ -n "${RECOVERY_OWNER:-}" ]; then
            chown "$RECOVERY_OWNER" "$RECOVERY_DIR"
        fi
    fi
    
    # Check for zip command
    if ! command -v zip &> /dev/null; then
        log ERROR "zip command not found. Install: apt install zip"
        return 1
    fi
    
    # Warn if no password set
    if [ -z "${RECOVERY_ZIP_PASSWORD:-}" ]; then
        log WARN "RECOVERY_ZIP_PASSWORD not set - ZIPs will be unencrypted!"
        log WARN "Set in common.env: export RECOVERY_ZIP_PASSWORD=\"your-password\""
    fi
    
    log INFO "Recovery configuration valid"
    return 0
}

# Get repository ID
get_repo_id() {
    local repo_path="$1"
    
    log INFO "Getting repository ID from: $repo_path"
    
    # Ensure BORG_PASSPHRASE is set from file if available
    if [ -n "${BORG_PASSPHRASE_FILE:-}" ] && [ -f "$BORG_PASSPHRASE_FILE" ]; then
        export BORG_PASSPHRASE=$(cat "$BORG_PASSPHRASE_FILE")
    fi
    
    # Get full repo info
    local repo_info
    if ! repo_info=$(borg info "$repo_path" 2>&1); then
        log ERROR "Failed to get repository info"
        log ERROR "$repo_info"
        return 1
    fi
    
    # Extract Repository ID
    local repo_id
    repo_id=$(echo "$repo_info" | grep "Repository ID:" | awk '{print $3}')
    
    if [ -z "$repo_id" ]; then
        log ERROR "Could not extract Repository ID from borg info"
        return 1
    fi
    
    log INFO "Repository ID: $repo_id"
    echo "$repo_id"
}

# Get short repository ID (first 8 chars)
get_short_repo_id() {
    local repo_id="$1"
    echo "${repo_id:0:8}"
}

# Check if recovery export already exists for this repository
check_existing_export() {
    local profile="$1"
    local repo_id_short="$2"
    
    log INFO "Checking for existing recovery export..."
    log INFO "Pattern: ${profile}_*_${repo_id_short}_*.zip"
    
    # Search for existing export with this repo ID
    local existing_exports
    existing_exports=$(find "$RECOVERY_DIR" -maxdepth 1 -name "${profile}_*_${repo_id_short}_*.zip" 2>/dev/null || true)
    
    if [ -n "$existing_exports" ]; then
        log INFO "Found existing recovery export(s):"
        echo "$existing_exports" | while read -r export_file; do
            log INFO "  - $(basename "$export_file")"
        done
        return 0  # Export exists
    else
        log INFO "No existing recovery export found for this repository"
        return 1  # No export found
    fi
}

# Create recovery information file
create_recovery_info() {
    local output_file="$1"
    
    log INFO "Creating recovery information file..."
    
    cat > "$output_file" <<EOF
===============================================================================
BORG BACKUP RECOVERY INFORMATION
===============================================================================

Profile: ${BACKUP_PROFILE}
Hostname: $(hostname)
Backup System Version: ${BACKUP_SYSTEM_VERSION:-unknown}
Export Date: $(date '+%Y-%m-%d %H:%M:%S')

===============================================================================
REPOSITORY INFORMATION
===============================================================================

Repository ID: ${REPO_ID}
Repository Path: ${REPO}
Backup Device: ${BACKUP_DEV}
Device UUID: ${BACKUP_UUID}
Mount Point: ${BACKUP_MNT}
Target Directory: ${TARGET_DIR}

Archive Prefix: ${ARCHIVE_PREFIX}
Encryption: repokey BLAKE2b

===============================================================================
BORG PASSPHRASE LOCATION
===============================================================================

The Borg passphrase is stored separately at:
${BORG_PASSPHRASE_FILE:-/root/.config/borg/passphrase}

⚠️  IMPORTANT: You need BOTH the repository key (in this ZIP) AND the 
passphrase to restore backups!

Backup the passphrase separately and securely:
- Password manager (LastPass, 1Password, Bitwarden)
- Encrypted USB drive in safe location
- Paper backup in secure location
- Multiple secure locations for redundancy

===============================================================================
BACKUP SOURCES
===============================================================================

Sources: ${BACKUP_SOURCES}
One File System: ${BACKUP_ONE_FILE_SYSTEM:-false}
Exclude Caches: ${BACKUP_EXCLUDE_CACHES:-false}
Excludes: ${BACKUP_EXCLUDES:-none}

===============================================================================
RETENTION POLICY
===============================================================================

Daily: ${KEEP_DAILY:-7} days
Weekly: ${KEEP_WEEKLY:-4} weeks
Monthly: ${KEEP_MONTHLY:-6} months

===============================================================================
PROFILE-SPECIFIC CONFIGURATION
===============================================================================

EOF

    # Add profile-specific info
    if [ "${DOCKER_ENABLED:-false}" = "true" ]; then
        cat >> "$output_file" <<EOF
Docker Integration: Enabled
Container Stop Timeout: ${DOCKER_STOP_TIMEOUT:-30}s
State Directory: ${STATE_DIR:-/tmp/backup-system-state}

EOF
    fi
    
    if [ "${NEXTCLOUD_ENABLED:-false}" = "true" ]; then
        cat >> "$output_file" <<EOF
Nextcloud Integration: Enabled
App Container: ${NEXTCLOUD_DOCKER_APP_CONTAINER:-unknown}
DB Container: ${NEXTCLOUD_DOCKER_DB_CONTAINER:-unknown}
DB Type: ${NEXTCLOUD_DB_TYPE:-unknown}
DB Name: ${NEXTCLOUD_DB_NAME:-unknown}
DB User: ${NEXTCLOUD_DB_USER:-unknown}

⚠️  DB Password is stored separately in production config:
/opt/backup-system/config/profiles/${BACKUP_PROFILE}.env
Variable: NEXTCLOUD_DB_PASSWORD

EOF
    fi
    
    if [ "${SHELLY_ENABLED:-false}" = "true" ]; then
        cat >> "$output_file" <<EOF
Shelly Plug Integration: Enabled
Shelly IP: ${SHELLY_IP:-unknown}

EOF
    fi
    
    if [ "${HDD_SPINDOWN_ENABLED:-false}" = "true" ]; then
        cat >> "$output_file" <<EOF
HDD Spindown: Enabled
HDD Device: ${HDD_DEVICE:-unknown}

EOF
    fi
    
    cat >> "$output_file" <<EOF
===============================================================================
DISASTER RECOVERY NOTES
===============================================================================

This ZIP archive contains:
1. Repository Key (repo-key.txt) - Required to access encrypted backups
2. Recovery Information (this file) - Repository configuration details
3. Recovery README - Step-by-step restore instructions

To restore from this backup you will need:
✓ This repository key
✓ The Borg passphrase (stored separately!)
✓ The backup device (or access to backup location)
✓ BorgBackup installed (apt install borgbackup)

See RECOVERY-README.txt for detailed restore instructions.

===============================================================================
EOF

    log INFO "Recovery information created: $(basename "$output_file")"
}

# Create recovery README
create_recovery_readme() {
    local output_file="$1"
    
    log INFO "Creating recovery README..."
    
    cat > "$output_file" <<'EOF'
===============================================================================
DISASTER RECOVERY GUIDE - BORG BACKUP RESTORATION
===============================================================================

This guide explains how to restore your backups using the exported repository
key and recovery information in this archive.

===============================================================================
PREREQUISITES
===============================================================================

1. Install BorgBackup:
   sudo apt update
   sudo apt install borgbackup

2. You need THREE things to restore:
   ✓ Repository key (repo-key.txt - in this ZIP)
   ✓ Borg passphrase (stored separately!)
   ✓ Access to backup device/location

3. Import the repository key:
   borg key import /path/to/repository repo-key.txt

===============================================================================
STEP 1: CONNECT BACKUP DEVICE
===============================================================================

# Find your backup device UUID (from recovery-info.txt)
lsblk -o NAME,UUID,SIZE,FSTYPE

# Mount the device
sudo mkdir -p /mnt/recovery
sudo mount UUID=<your-uuid> /mnt/recovery

# Verify repository exists
ls -la /mnt/recovery/<target-directory>/borgrepo

===============================================================================
STEP 2: IMPORT REPOSITORY KEY
===============================================================================

# Extract repo-key.txt from this ZIP
unzip recovery-archive.zip

# Import the key
borg key import /mnt/recovery/<target-directory>/borgrepo repo-key.txt

# Borg will ask for the passphrase - enter it now!

===============================================================================
STEP 3: VERIFY ACCESS TO REPOSITORY
===============================================================================

# Set passphrase environment variable (or use interactive prompt)
export BORG_PASSPHRASE='your-passphrase'

# Test repository access
borg list /mnt/recovery/<target-directory>/borgrepo

# You should see a list of all backup archives

===============================================================================
STEP 4: CHOOSE WHAT TO RESTORE
===============================================================================

# List archives with details
borg list /mnt/recovery/<target-directory>/borgrepo

# Example output:
# creaThink-system-2026-01-15_100000  Tue, 2026-01-15 10:00:00
# creaThink-system-2026-01-16_100000  Wed, 2026-01-16 10:00:00

# List contents of specific archive
borg list /mnt/recovery/<target-directory>/borgrepo::creaThink-system-2026-01-16_100000

===============================================================================
STEP 5: RESTORE FILES
===============================================================================

Option A: Restore Everything
-----------------------------
# Restore entire archive to current directory
borg extract /mnt/recovery/<target-directory>/borgrepo::creaThink-system-2026-01-16_100000

Option B: Restore Specific Directories
---------------------------------------
# Restore only /home directory
borg extract /mnt/recovery/<target-directory>/borgrepo::creaThink-system-2026-01-16_100000 home/

# Restore multiple specific paths
borg extract /mnt/recovery/<target-directory>/borgrepo::creaThink-system-2026-01-16_100000 \
    home/user/Documents \
    home/user/Pictures

Option C: Restore to Different Location
----------------------------------------
# Change to target directory first
cd /restore-target
borg extract /mnt/recovery/<target-directory>/borgrepo::creaThink-system-2026-01-16_100000

Option D: Restore with Original Paths (System Restore)
-------------------------------------------------------
# ⚠️  WARNING: This overwrites existing files!
cd /
sudo borg extract /mnt/recovery/<target-directory>/borgrepo::creaThink-system-2026-01-16_100000

===============================================================================
DOCKER/NEXTCLOUD SPECIFIC RESTORE
===============================================================================

If this is a dev-data backup (Docker containers + Nextcloud):

1. Stop all containers:
   docker stop $(docker ps -aq)

2. Restore docker-data:
   cd /mnt
   sudo borg extract /mnt/recovery/<target-directory>/borgrepo::latest docker-data/

3. Restore database dump:
   # Database dumps are in the backup at:
   # /mnt/docker-data/database-dumps/nextcloud_db-dump_*.sql.gz
   
   # Extract latest dump
   gunzip nextcloud_db-dump_YYYY-MM-DD_HH-MM-SS.sql.gz
   
   # Import to database
   docker exec -i nextcloud-db mysql -u ncadmin -p nextcloud < dump.sql

4. Start containers:
   docker start $(docker ps -aq)

===============================================================================
VERIFICATION AFTER RESTORE
===============================================================================

# Check restored files
ls -la /restored/location

# Verify file permissions
# Verify file contents
# Test applications/services

===============================================================================
TROUBLESHOOTING
===============================================================================

Problem: "Repository does not exist"
Solution: Check mount point and repository path in recovery-info.txt

Problem: "Passphrase wrong"
Solution: Ensure you're using the correct passphrase. Check your password manager
         or secure backup location.

Problem: "Failed to import key"
Solution: Ensure the key file is intact. Try extracting ZIP again.

Problem: Permission denied during restore
Solution: Run with sudo for system restores: sudo borg extract ...

Problem: No space left on device
Solution: Ensure target has enough free space. Check with: df -h

===============================================================================
IMPORTANT SECURITY NOTES
===============================================================================

⚠️  Keep this recovery archive SECURE!
   - It contains your repository key
   - Anyone with this key + passphrase can decrypt your backups

✓ Store in multiple secure locations:
   - Encrypted USB drive (offsite)
   - Secure cloud storage (encrypted)
   - Physical safe
   - Trusted family member/colleague

✓ Test your recovery process periodically:
   - Verify you can mount the backup device
   - Verify you can list archives
   - Test restoring a small file
   - Document any changes to the process

===============================================================================
NEED HELP?
===============================================================================

Borg Documentation: https://borgbackup.readthedocs.io/
Recovery Guide: https://borgbackup.readthedocs.io/en/stable/usage/extract.html

For issues with the backup system:
GitHub: https://github.com/JoZapf/segmented-borg-backup-system

===============================================================================
EOF

    log INFO "Recovery README created: $(basename "$output_file")"
}

# Export repository key and create recovery archive
export_recovery_archive() {
    local profile="$1"
    local repo_path="$2"
    local repo_id="$3"
    local repo_id_short="$4"
    
    log INFO "Creating recovery archive for profile: $profile"
    
    # Create temporary directory for staging files
    local temp_dir
    temp_dir=$(mktemp -d)
    local staging_dir="${temp_dir}/${profile}_$(hostname)_${repo_id_short}_$(date +%Y-%m-%d)"
    mkdir -p "$staging_dir"
    
    log INFO "Staging directory: $staging_dir"
    
    # Ensure BORG_PASSPHRASE is set from file if available
    if [ -n "${BORG_PASSPHRASE_FILE:-}" ] && [ -f "$BORG_PASSPHRASE_FILE" ]; then
        export BORG_PASSPHRASE=$(cat "$BORG_PASSPHRASE_FILE")
    fi
    
    # Export repository key
    log INFO "Exporting repository key..."
    local key_file="${staging_dir}/repo-key.txt"
    if ! borg key export "$repo_path" "$key_file" 2>&1; then
        log ERROR "Failed to export repository key"
        rm -rf "$temp_dir"
        return 1
    fi
    log INFO "Repository key exported successfully"
    
    # Create recovery information file
    local info_file="${staging_dir}/recovery-info.txt"
    REPO_ID="$repo_id" create_recovery_info "$info_file"
    
    # Create recovery README
    local readme_file="${staging_dir}/RECOVERY-README.txt"
    create_recovery_readme "$readme_file"
    
    # Create ZIP archive
    local zip_name="${profile}_$(hostname)_${repo_id_short}_$(date +%Y-%m-%d).zip"
    local zip_path="${RECOVERY_DIR}/${zip_name}"
    
    log INFO "Creating encrypted ZIP archive: $zip_name"
    
    # Build zip command
    local zip_cmd="zip -r -j"
    
    # Add password if configured
    if [ -n "${RECOVERY_ZIP_PASSWORD:-}" ]; then
        zip_cmd="$zip_cmd -P \"$RECOVERY_ZIP_PASSWORD\""
        log INFO "ZIP will be password-protected"
    else
        log WARN "Creating unencrypted ZIP (no password configured)"
    fi
    
    # Create ZIP (change to temp dir to avoid path issues)
    cd "$temp_dir"
    if eval "$zip_cmd \"$zip_path\" \"$staging_dir\"/*" >/dev/null 2>&1; then
        log INFO "Recovery archive created successfully"
        
        # Set ownership if specified
        if [ -n "${RECOVERY_OWNER:-}" ]; then
            chown "$RECOVERY_OWNER" "$zip_path"
            log INFO "Set ownership: $RECOVERY_OWNER"
        fi
        
        # Show file info
        local zip_size
        zip_size=$(du -h "$zip_path" | cut -f1)
        log INFO "Archive size: $zip_size"
        log INFO "Archive location: $zip_path"
        
        # Cleanup temp directory
        rm -rf "$temp_dir"
        
        log INFO "Recovery archive export completed successfully"
        return 0
    else
        log ERROR "Failed to create ZIP archive"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Main execution
main() {
    log INFO "==================================================================="
    log INFO "Starting recovery key export for profile: ${BACKUP_PROFILE}"
    log INFO "==================================================================="
    
    # Check if enabled
    if ! check_recovery_enabled; then
        log INFO "Recovery key export skipped"
        return 0
    fi
    
    # Validate configuration
    if ! validate_recovery_config; then
        log ERROR "Recovery configuration validation failed"
        return 1
    fi
    
    # Check if repository is mounted/accessible
    if [ ! -d "$REPO" ]; then
        log ERROR "Repository not accessible: $REPO"
        log ERROR "Ensure backup device is still mounted"
        return 1
    fi
    
    # Get repository ID
    local repo_id
    if ! repo_id=$(get_repo_id "$REPO"); then
        log ERROR "Failed to get repository ID"
        return 1
    fi
    
    local repo_id_short
    repo_id_short=$(get_short_repo_id "$repo_id")
    log INFO "Short repository ID: $repo_id_short"
    
    # Check if export already exists
    if check_existing_export "$BACKUP_PROFILE" "$repo_id_short"; then
        log INFO "Recovery export already exists for this repository"
        log INFO "Skipping export to avoid duplicates"
        log INFO "Delete existing export if you want to recreate it"
        return 0
    fi
    
    # Create new recovery export
    if ! export_recovery_archive "$BACKUP_PROFILE" "$REPO" "$repo_id" "$repo_id_short"; then
        log ERROR "Failed to create recovery archive"
        return 1
    fi
    
    log INFO "==================================================================="
    log INFO "Recovery key export completed successfully"
    log INFO "==================================================================="
    
    return 0
}

# Execute main function
main "$@"
