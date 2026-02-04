#!/usr/bin/env bash
# segments/05_mount_backup.sh
# @version 2.1.0
# @description Mounts backup device with robust error recovery
# @author Jo Zapf
# @changed 2026-02-04 - Added multi-stage error recovery (backward compatible)
# @requires BACKUP_MNT, TARGET_DIR, BACKUP_UUID, BACKUP_DEV

set -euo pipefail

echo "[05] Mounting backup device..."

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly MAX_UNMOUNT_RETRIES=3
readonly MAX_DEVICE_WAIT=30
readonly UNMOUNT_WAIT=2

# Processes that should NEVER be automatically killed
# Add your critical processes here!
readonly NEVER_KILL_PROCESSES=(
    "borg"              # Borg Backup - CRITICAL!
    "docker"            # Docker daemon
    "dockerd"           # Docker daemon
    "containerd"        # Container runtime
    "mysql"             # MySQL/MariaDB
    "mysqld"            # MySQL daemon
    "postgres"          # PostgreSQL
    "mongod"            # MongoDB
    "redis-server"      # Redis
    "systemd"           # System processes
    "rsync"             # Rsync transfers
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# @brief Safely unmounts with intelligent process handling and blacklist protection
# @description
#   Enhanced unmount with 4-stage approach and process safety:
#   1. Normal umount (graceful) - 3 attempts
#   2. Force umount -f (if processes block)
#   3. Lazy umount -l (detach immediately, cleanup later)
#   4. Intelligent process termination (with blacklist protection)
#   
#   Stage 4 enhancement: Analyzes blocking processes against blacklist.
#   Protected processes (borg, docker, databases) will NEVER be killed.
#   If critical processes are found, unmount is aborted with manual
#   intervention instructions.
#
# @arg $1 string Mount point to unmount
# @global NEVER_KILL_PROCESSES Array of process names to protect
# @stdout Progress messages, safety warnings, and process analysis
# @stderr Critical process warnings and manual intervention instructions
# @exitcode 0 Successfully unmounted
# @exitcode 1 Unmount failed (critical processes blocking or other error)
# @see validate_and_mount()
# @example
#   safe_unmount "/mnt/extern_backup"
safe_unmount() {
    local mount_point="$1"
    local retry=0
    
    # Build regex pattern from blacklist
    local never_kill_pattern
    never_kill_pattern=$(IFS="|"; echo "${NEVER_KILL_PROCESSES[*]}")
    
    echo "[05] Safe unmount: ${mount_point}"
    echo "[05] Protected processes: ${NEVER_KILL_PROCESSES[*]}"
    
    # Check if actually mounted
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        echo "[05] Not mounted - nothing to unmount"
        return 0
    fi
    
    # ========================================================================
    # STAGE 1: Graceful umount with retries
    # ========================================================================
    
    while [ $retry -lt $MAX_UNMOUNT_RETRIES ]; do
        retry=$((retry + 1))
        echo "[05] Unmount attempt $retry/$MAX_UNMOUNT_RETRIES (normal)..."
        
        if umount "$mount_point" 2>/dev/null; then
            echo "[05] ✓ Unmounted successfully (graceful)"
            sleep 1
            return 0
        fi
        
        # Show blocking processes for debugging (non-invasive)
        if command -v lsof >/dev/null 2>&1; then
            local blocking_count
            blocking_count=$(lsof +D "$mount_point" 2>/dev/null | tail -n +2 | wc -l)
            if [ "$blocking_count" -gt 0 ]; then
                echo "[05] Warning: $blocking_count process(es) blocking unmount"
                lsof +D "$mount_point" 2>/dev/null | head -5 || true
            fi
        fi
        
        sleep "$UNMOUNT_WAIT"
    done
    
    # ========================================================================
    # STAGE 2: Force umount
    # ========================================================================
    
    echo "[05] Unmount attempt (force: umount -f)..."
    if umount -f "$mount_point" 2>/dev/null; then
        echo "[05] ✓ Unmounted successfully (force)"
        sleep 2
        return 0
    fi
    
    # ========================================================================
    # STAGE 3: Lazy umount
    # ========================================================================
    
    echo "[05] Unmount attempt (lazy: umount -l)..."
    if umount -l "$mount_point" 2>/dev/null; then
        echo "[05] ✓ Unmounted successfully (lazy)"
        echo "[05] Note: Kernel will cleanup when processes release handles"
        sleep 3
        
        # Verify detachment
        if ! mountpoint -q "$mount_point" 2>/dev/null; then
            echo "[05] Verified: Mount point detached"
            return 0
        fi
        
        echo "[05] Lazy unmount active (kernel cleanup pending)"
        return 0
    fi
    
    # ========================================================================
    # STAGE 4: Intelligent process termination with safety
    # ========================================================================
    
    echo "[WARN] ⚠ All non-destructive unmount attempts failed"
    echo "[WARN] Analyzing blocking processes for safe termination..."
    
    # Check if fuser is available
    if ! command -v fuser >/dev/null 2>&1; then
        echo "[ERROR] fuser command not available - cannot identify blocking processes"
        echo "[ERROR] Install: sudo apt install psmisc"
        echo "[ERROR] Or use lazy unmount: umount -l $mount_point"
        return 1
    fi
    
    # Get detailed process information
    local blocking_processes
    blocking_processes=$(fuser -vm "$mount_point" 2>&1 | tail -n +2 || echo "")
    
    if [ -z "$blocking_processes" ]; then
        echo "[ERROR] No processes found, but unmount still fails"
        echo "[ERROR] Possible kernel or filesystem issue"
        return 1
    fi
    
    echo "[WARN] Blocking processes detected:"
    echo "---"
    echo "$blocking_processes"
    echo "---"
    
    # Analyze processes and check against blacklist
    local has_critical_processes=false
    local safe_pids=()
    local critical_info=""
    
    while IFS= read -r line; do
        # Skip header and empty lines
        if [[ -z "$line" ]] || [[ "$line" == *"USER"* ]]; then
            continue
        fi
        
        # Extract PID and command
        local pid=$(echo "$line" | awk '{print $2}')
        local cmd=$(echo "$line" | awk '{print $4}')
        
        if [ -z "$pid" ] || [ -z "$cmd" ]; then
            continue
        fi
        
        # Check if process is in blacklist
        if echo "$cmd" | grep -qE "($never_kill_pattern)"; then
            has_critical_processes=true
            critical_info+="  - PID $pid: $cmd (PROTECTED)\n"
            echo "[CRITICAL] ⛔ Protected process found: $cmd (PID: $pid)"
        else
            safe_pids+=("$pid")
            echo "[SAFE] ✓ Can terminate: $cmd (PID: $pid)"
        fi
    done <<< "$blocking_processes"
    
    # If critical processes found, ABORT
    if [ "$has_critical_processes" = true ]; then
        echo ""
        echo "==============================================================================="
        echo " CRITICAL PROCESSES DETECTED - SAFETY ABORT"
        echo "==============================================================================="
        echo ""
        echo "The following PROTECTED processes are blocking the mount point:"
        echo -e "$critical_info"
        echo ""
        echo "⚠️  WILL NOT KILL THESE PROCESSES AUTOMATICALLY!"
        echo ""
        echo "Why this is critical:"
        echo "  - Killing borg: Could corrupt backup repository"
        echo "  - Killing docker: Could lose container data"
        echo "  - Killing database: Could corrupt data"
        echo ""
        echo "Manual intervention required:"
        echo ""
        echo "  1. Identify what the process is doing:"
        echo "     ps aux | grep -E '(borg|docker|mysql)'"
        echo ""
        echo "  2. Option A - Wait for process to finish:"
        echo "     # If it's a backup or important operation, let it complete"
        echo ""
        echo "  3. Option B - Stop gracefully:"
        echo "     sudo systemctl stop <service>"
        echo "     # or: sudo docker stop <container>"
        echo ""
        echo "  4. Option C - Use lazy unmount (usually safe):"
        echo "     sudo umount -l $mount_point"
        echo "     # Detaches mount immediately, kernel cleans up when process exits"
        echo ""
        echo "  5. After resolving, retry backup:"
        echo "     sudo /opt/backup-system/run-backup.sh $BACKUP_PROFILE"
        echo ""
        echo "==============================================================================="
        
        return 1
    fi
    
    # Only safe processes found - proceed with termination
    if [ ${#safe_pids[@]} -eq 0 ]; then
        echo "[ERROR] No processes to terminate, but unmount still fails"
        echo "[ERROR] Unknown blocking condition - try lazy unmount manually"
        return 1
    fi
    
    echo ""
    echo "[WARN] Safe to terminate ${#safe_pids[@]} non-critical process(es)"
    echo "[WARN] These are likely shells, file managers, or text editors"
    echo "[WARN] Sending SIGTERM (graceful shutdown)..."
    
    # Terminate safe processes gracefully (SIGTERM)
    for pid in "${safe_pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "[WARN] Terminating PID $pid (SIGTERM)..."
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    
    sleep 3
    
    # Try unmount after graceful termination
    if umount "$mount_point" 2>/dev/null; then
        echo "[05] ✓ Unmounted after graceful process termination"
        return 0
    fi
    
    # If still blocked, force kill remaining safe processes
    echo "[WARN] Graceful termination insufficient - using SIGKILL..."
    
    for pid in "${safe_pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "[WARN] Force killing PID $pid (SIGKILL)..."
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
    
    sleep 2
    
    # Final unmount attempt
    if umount "$mount_point" 2>/dev/null || umount -l "$mount_point" 2>/dev/null; then
        echo "[05] ✓ Unmounted after force termination"
        return 0
    fi
    
    echo "[ERROR] All unmount strategies failed"
    return 1
}

# @brief Validates and mounts backup device with comprehensive error recovery
# @description
#   Comprehensive mount handling with multiple safety checks and recovery:
#   1. Check if already correctly mounted → exit success (no action needed)
#   2. Check if wrong device mounted → safe unmount + remount with recovery
#   3. Check if not mounted → perform mount with validation
#   4. Post-mount validation → UUID verification and accessibility check
#   
#   Error handling uses temporary disable of errexit (set +e) during
#   recovery operations to allow proper error analysis and graceful handling.
#
# @global BACKUP_MNT Mount point path
# @global BACKUP_DEV Device path (by-uuid symlink)
# @global BACKUP_UUID Expected UUID for validation
# @global TARGET_DIR Target directory that should be accessible after mount
# @stdout Progress messages, validation results, and status indicators
# @stderr Error details, recovery instructions, and debugging information
# @exitcode 0 Successfully mounted (or already correctly mounted)
# @exitcode 1 Mount failed after all recovery attempts
# @exitcode 2 Mount succeeded but UUID validation failed (critical)
# @see safe_unmount()
# @example
#   validate_and_mount
#   # Returns 0 if mount successful or already correct
validate_and_mount() {
    echo "[05] Validating mount state..."
    
    # ========================================================================
    # Phase 1: Check current mount state
    # ========================================================================
    
    local current_mount
    current_mount=$(findmnt -rn -t ext4 -o SOURCE -M "${BACKUP_MNT}" 2>/dev/null || echo "")
    
    if [ -n "$current_mount" ]; then
        # Something is mounted - check if it's the correct device
        local current_uuid
        current_uuid=$(blkid -s UUID -o value "$current_mount" 2>/dev/null || echo "")
        
        if [ "$current_uuid" = "$BACKUP_UUID" ]; then
            # Perfect - already correctly mounted
            echo "[05] ✓ Backup device already mounted correctly"
            echo "[05] Device: $current_mount"
            echo "[05] UUID: $current_uuid"
            return 0
        else
            # Wrong device mounted - need recovery
            echo "[WARN] ⚠ Wrong device mounted at ${BACKUP_MNT}"
            echo "[WARN] Mounted device: $current_mount"
            echo "[WARN] Current UUID: ${current_uuid:-<unknown>}"
            echo "[WARN] Expected UUID: $BACKUP_UUID"
            echo "[WARN] Initiating recovery procedure..."
            
            # Disable errexit temporarily for safe recovery
            set +e
            safe_unmount "${BACKUP_MNT}"
            local unmount_result=$?
            set -e
            
            if [ $unmount_result -ne 0 ]; then
                echo "[ERROR] Recovery failed: Cannot unmount wrong device"
                echo "[ERROR] See error messages above for details"
                return 1
            fi
            
            echo "[05] ✓ Wrong device successfully unmounted"
            sleep 2  # Let system stabilize after unmount
        fi
    else
        echo "[05] Mount point is clean (not mounted)"
    fi
    
    # ========================================================================
    # Phase 2: Verify device readiness
    # ========================================================================
    
    echo "[05] Verifying device readiness..."
    local device_wait=0
    
    while [ $device_wait -lt $MAX_DEVICE_WAIT ]; do
        if [ -e "$BACKUP_DEV" ] && blkid -s UUID -o value "$BACKUP_DEV" >/dev/null 2>&1; then
            local found_uuid
            found_uuid=$(blkid -s UUID -o value "$BACKUP_DEV")
            echo "[05] ✓ Device ready: $BACKUP_DEV"
            echo "[05] UUID: $found_uuid"
            break
        fi
        
        if [ $device_wait -eq 0 ]; then
            echo "[05] Waiting for device to become ready..."
        fi
        
        device_wait=$((device_wait + 1))
        sleep 1
    done
    
    if [ $device_wait -eq $MAX_DEVICE_WAIT ]; then
        echo "[ERROR] Device not ready after ${MAX_DEVICE_WAIT}s timeout"
        echo "[ERROR] Device: $BACKUP_DEV"
        echo "[ERROR] Expected UUID: $BACKUP_UUID"
        return 1
    fi
    
    # ========================================================================
    # Phase 3: Attempt mount
    # ========================================================================
    
    echo "[05] Mounting device via fstab..."
    
    # Disable errexit for mount attempt - we handle errors manually
    set +e
    local mount_output
    mount_output=$(mount "${BACKUP_MNT}" 2>&1)
    local mount_result=$?
    set -e
    
    if [ $mount_result -eq 0 ]; then
        echo "[05] ✓ Mount command successful"
    elif echo "$mount_output" | grep -iq "already.*mount"; then
        # Special case: "Already mounted" error
        echo "[WARN] Mount reports 'already mounted' - verifying state..."
        
        local verify_mount
        verify_mount=$(findmnt -rn -t ext4 -o SOURCE -M "${BACKUP_MNT}" 2>/dev/null || echo "")
        
        if [ -n "$verify_mount" ]; then
            local verify_uuid
            verify_uuid=$(blkid -s UUID -o value "$verify_mount" 2>/dev/null || echo "")
            
            if [ "$verify_uuid" = "$BACKUP_UUID" ]; then
                echo "[05] ✓ Verified: Correct device is actually mounted"
                echo "[05] Device: $verify_mount"
                return 0
            else
                echo "[ERROR] Wrong device still mounted after mount attempt"
                echo "[ERROR] Mounted: $verify_mount (UUID: $verify_uuid)"
                echo "[ERROR] Expected UUID: $BACKUP_UUID"
                return 2
            fi
        else
            echo "[ERROR] Mount reports 'already mounted' but device not found in mount table"
            echo "[ERROR] Try: sudo systemctl daemon-reload && mount -a"
            return 2
        fi
    else
        echo "[ERROR] Mount command failed"
        echo "[ERROR] Output: $mount_output"
        
        # Provide debugging information
        echo ""
        echo "[DEBUG] Current filesystem status:"
        mount | grep -E "(extern_backup|sdc)" || echo "  No relevant mounts found"
        echo ""
        echo "[DEBUG] Device information:"
        lsblk "$BACKUP_DEV" 2>&1 || echo "  Device not found"
        
        return 1
    fi
    
    # ========================================================================
    # Phase 4: Post-mount validation
    # ========================================================================
    
    sleep 2  # Let mount fully stabilize
    
    echo "[05] Validating mount..."
    local mounted_dev
    mounted_dev=$(findmnt -rn -t ext4 -o SOURCE -M "${BACKUP_MNT}" 2>/dev/null || echo "")
    
    if [ -z "$mounted_dev" ]; then
        echo "[ERROR] Validation failed: No ext4 filesystem found at ${BACKUP_MNT}"
        return 2
    fi
    
    local mounted_uuid
    mounted_uuid=$(blkid -s UUID -o value "$mounted_dev" 2>/dev/null || echo "")
    
    if [ "$mounted_uuid" != "$BACKUP_UUID" ]; then
        echo "[ERROR] UUID validation failed after mount"
        echo "[ERROR] Mounted device: $mounted_dev"
        echo "[ERROR] Found UUID: $mounted_uuid"
        echo "[ERROR] Expected UUID: $BACKUP_UUID"
        return 2
    fi
    
    # Final check: Verify target directory is accessible
    if [ ! -d "$TARGET_DIR" ]; then
        echo "[ERROR] Target directory not accessible: $TARGET_DIR"
        return 2
    fi
    
    echo "[05] ✓ Backup device mounted and validated successfully"
    echo "[05] Device: $mounted_dev"
    echo "[05] Mount point: ${BACKUP_MNT}"
    echo "[05] UUID: $mounted_uuid"
    echo "[05] Target: $TARGET_DIR"
    echo ""
    echo "[05] ℹ️  Note: Backup will now proceed with remaining segments"
    
    return 0
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

# Create mount directories if they don't exist
mkdir -p "${BACKUP_MNT}" "${TARGET_DIR}"

# Execute robust mount with comprehensive error recovery
if ! validate_and_mount; then
    echo ""
    echo "==============================================================================="
    echo " MOUNT FAILED - BACKUP ABORTED"
    echo "==============================================================================="
    echo ""
    echo "⛔ The backup device could not be mounted."
    echo "   Backup process will NOT continue to protect data integrity."
    echo ""
    echo "Possible causes:"
    echo "  1. Device not available or disconnected"
    echo "  2. Filesystem errors (needs fsck)"
    echo "  3. Permissions issue"
    echo "  4. fstab misconfiguration"
    echo "  5. Systemd mount unit conflict"
    echo "  6. Critical processes blocking unmount (see above)"
    echo ""
    echo "Manual recovery steps:"
    echo ""
    echo "  1. Check device exists:"
    echo "     ls -la $BACKUP_DEV"
    echo "     lsblk | grep sdc"
    echo ""
    echo "  2. Verify UUID:"
    echo "     blkid $BACKUP_DEV"
    echo "     # Should show: UUID=\"$BACKUP_UUID\""
    echo ""
    echo "  3. Force unmount if needed:"
    echo "     sudo systemctl stop mnt-extern_backup.automount"
    echo "     sudo systemctl stop mnt-extern_backup.mount"
    echo "     sudo umount -l ${BACKUP_MNT}"
    echo ""
    echo "  4. Check filesystem integrity:"
    echo "     sudo fsck -n $BACKUP_DEV  # Read-only check"
    echo "     sudo fsck -y $BACKUP_DEV  # Repair if needed"
    echo ""
    echo "  5. Test manual mount:"
    echo "     sudo mount ${BACKUP_MNT}"
    echo "     findmnt ${BACKUP_MNT}"
    echo ""
    echo "  6. Verify fstab:"
    echo "     grep extern_backup /etc/fstab"
    echo ""
    echo "  7. Reload and retry:"
    echo "     sudo systemctl daemon-reload"
    echo "     sudo /opt/backup-system/run-backup.sh $BACKUP_PROFILE"
    echo ""
    echo "==============================================================================="
    exit 1
fi

# Success - backup will continue
exit 0
