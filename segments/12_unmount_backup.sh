#!/usr/bin/env bash
# segments/12_unmount_backup.sh
# @version 2.0.0
# @description Safely unmounts backup device with robust error recovery (cleanup-safe)
# @author Jo Zapf
# @changed 2026-02-04 - Added multi-stage unmount with process blacklist (matching 05 v2.1.0)
# @changed 2026-02-04 - Converted to soft-fail mode for cleanup context (warnings instead of exits)
# @changed 2026-01-25 - Fixed race condition: Check if already unmounted by systemd
# @changed 2026-01-22 - Fixed dynamic systemd unit detection for dev-data profile
# @requires BACKUP_MNT

set -euo pipefail

echo "[12] Unmounting backup device..."

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly MAX_UNMOUNT_RETRIES=3
readonly UNMOUNT_WAIT=2

# Process blacklist (same as 05_mount_backup.sh for consistency)
# These processes should never be automatically killed
readonly NEVER_KILL_PROCESSES=(
    "borg"              # Borg Backup (should be finished, but safety first)
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

# @brief Safely unmounts with intelligent process handling (cleanup-safe version)
# @description
#   Multi-stage unmount strategy with process safety:
#   1. Normal umount (graceful) - 3 attempts
#   2. Force umount -f (if processes block)
#   3. Lazy umount -l (preferred in cleanup context!)
#   4. Intelligent process termination (with blacklist protection)
#   
#   CLEANUP MODE: This version is designed for cleanup context.
#   Unlike the mount segment version, this will NOT exit on failure
#   but will always return 0 after attempting all strategies.
#   This ensures HDD spindown and Shelly power-off still execute.
#
# @arg $1 string Mount point to unmount
# @global NEVER_KILL_PROCESSES Array of process names to protect
# @stdout Progress messages and warnings
# @stderr Process warnings and recommendations
# @exitcode 0 Always (cleanup-safe - never aborts)
# @see 05_mount_backup.sh safe_unmount() for mount-context version
# @example
#   safe_unmount_cleanup "/mnt/extern_backup"
#   # Always returns 0, even on failure
safe_unmount_cleanup() {
    local mount_point="$1"
    local retry=0
    
    # Build regex pattern from blacklist
    local never_kill_pattern
    never_kill_pattern=$(IFS="|"; echo "${NEVER_KILL_PROCESSES[*]}")
    
    echo "[12] Safe unmount (cleanup mode): ${mount_point}"
    
    # Check if actually mounted
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        echo "[12] ✓ Not mounted - already clean"
        return 0
    fi
    
    # ========================================================================
    # STAGE 1: Graceful umount with retries
    # ========================================================================
    
    while [ $retry -lt $MAX_UNMOUNT_RETRIES ]; do
        retry=$((retry + 1))
        echo "[12] Unmount attempt $retry/$MAX_UNMOUNT_RETRIES (normal)..."
        
        if umount "$mount_point" 2>/dev/null; then
            echo "[12] ✓ Unmounted successfully (graceful)"
            sleep 1
            return 0
        fi
        
        # Show blocking processes for debugging (non-invasive)
        if command -v lsof >/dev/null 2>&1; then
            local blocking_count
            blocking_count=$(lsof +D "$mount_point" 2>/dev/null | tail -n +2 | wc -l)
            if [ "$blocking_count" -gt 0 ]; then
                echo "[12] Warning: $blocking_count process(es) blocking unmount"
                if [ $retry -eq 1 ]; then
                    # Only show details on first attempt
                    lsof +D "$mount_point" 2>/dev/null | head -5 || true
                fi
            fi
        fi
        
        sleep "$UNMOUNT_WAIT"
    done
    
    # ========================================================================
    # STAGE 2: Force umount
    # ========================================================================
    
    echo "[12] Unmount attempt (force: umount -f)..."
    if umount -f "$mount_point" 2>/dev/null; then
        echo "[12] ✓ Unmounted successfully (force)"
        sleep 2
        return 0
    fi
    
    # ========================================================================
    # STAGE 3: Lazy umount (PREFERRED in cleanup context)
    # ========================================================================
    
    echo "[12] Unmount attempt (lazy: umount -l)..."
    if umount -l "$mount_point" 2>/dev/null; then
        echo "[12] ✓ Unmounted successfully (lazy)"
        echo "[12] Note: Kernel will cleanup when processes release handles"
        echo "[12] This is safe for cleanup - backup is quasi-offline"
        sleep 3
        
        # Verify detachment (lazy unmount may still show as mounted)
        if ! mountpoint -q "$mount_point" 2>/dev/null; then
            echo "[12] Verified: Mount point detached"
            return 0
        fi
        
        # Lazy unmount succeeded even if still shows as mounted
        echo "[12] Lazy unmount active (kernel cleanup pending)"
        echo "[12] Backup device will be fully unmounted when processes exit"
        return 0
    fi
    
    # ========================================================================
    # STAGE 4: Process analysis (informational only in cleanup)
    # ========================================================================
    
    echo "[WARN] ⚠ All unmount attempts failed"
    echo "[WARN] Analyzing blocking processes..."
    
    if ! command -v fuser >/dev/null 2>&1; then
        echo "[WARN] fuser not available - cannot identify blocking processes"
        echo "[WARN] Device remains mounted but backup has completed"
        echo "[WARN] Device will be unmounted on next reboot"
        return 0  # Soft fail - cleanup continues
    fi
    
    # Get process information
    local blocking_processes
    blocking_processes=$(fuser -vm "$mount_point" 2>&1 | tail -n +2 || echo "")
    
    if [ -z "$blocking_processes" ]; then
        echo "[WARN] No processes found, but unmount still fails"
        echo "[WARN] Possible kernel or filesystem issue"
        echo "[WARN] Device will be unmounted on next reboot"
        return 0  # Soft fail
    fi
    
    echo "[WARN] Blocking processes detected:"
    echo "---"
    echo "$blocking_processes"
    echo "---"
    
    # Analyze processes against blacklist (informational only)
    local has_critical_processes=false
    local critical_info=""
    
    while IFS= read -r line; do
        if [[ -z "$line" ]] || [[ "$line" == *"USER"* ]]; then
            continue
        fi
        
        local pid=$(echo "$line" | awk '{print $2}')
        local cmd=$(echo "$line" | awk '{print $4}')
        
        if [ -z "$pid" ] || [ -z "$cmd" ]; then
            continue
        fi
        
        if echo "$cmd" | grep -qE "($never_kill_pattern)"; then
            has_critical_processes=true
            critical_info+="  - PID $pid: $cmd (PROTECTED)\n"
            echo "[WARN] Protected process: $cmd (PID: $pid)"
        else
            echo "[INFO] Safe process: $cmd (PID: $pid)"
        fi
    done <<< "$blocking_processes"
    
    # In cleanup context, we NEVER kill processes
    # We just inform the user and let the system handle it
    
    if [ "$has_critical_processes" = true ]; then
        echo ""
        echo "[WARN] ⚠ Critical processes are blocking unmount:"
        echo -e "$critical_info"
        echo ""
        echo "This is non-critical in cleanup phase:"
        echo "  - Backup has completed successfully"
        echo "  - These processes are protected from auto-termination"
        echo "  - Device will remain mounted until processes finish"
        echo "  - System will auto-unmount on next boot"
        echo ""
        echo "Optional manual cleanup:"
        echo "  1. Wait for processes to finish naturally"
        echo "  2. Or stop them gracefully:"
        echo "     sudo systemctl stop <service>"
        echo "  3. Then unmount manually:"
        echo "     sudo umount $mount_point"
    else
        echo ""
        echo "[WARN] Non-critical processes blocking unmount"
        echo "[WARN] Device remains mounted but backup completed successfully"
        echo "[WARN] System will auto-unmount on reboot"
        echo ""
        echo "Optional: Close file managers and retry manually:"
        echo "  sudo umount $mount_point"
    fi
    
    return 0  # Always soft fail in cleanup context
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

# Change to safe directory (not on backup mount)
cd /

# Sync filesystem buffers
echo "[12] Syncing filesystem buffers..."
sync

# Check for open file handles (informational only - not blocking)
echo "[12] Checking for open file handles..."
if command -v lsof >/dev/null 2>&1; then
    if lsof +f -- "${BACKUP_MNT}" 2>/dev/null | grep -q .; then
        echo "[12] Warning: Open file handles detected"
        lsof +f -- "${BACKUP_MNT}" 2>/dev/null | head -10 || true
        echo "[12] Will attempt unmount anyway (cleanup context)"
    else
        echo "[12] No open file handles detected"
    fi
fi

# Stop systemd automount and mount units
echo "[12] Stopping systemd mount units..."
SYSTEMD_UNIT=$(echo "${BACKUP_MNT}" | sed 's|^/||; s|/|-|g')
systemctl stop "${SYSTEMD_UNIT}.automount" 2>/dev/null || true
systemctl stop "${SYSTEMD_UNIT}.mount" 2>/dev/null || true

# Wait for systemd to settle
sleep 2

# Check if already unmounted by systemd
if ! mountpoint -q "${BACKUP_MNT}"; then
    echo "[12] ✓ Already unmounted by systemd - backup quasi-offline"
    sync
    exit 0
fi

# Attempt unmount with multi-stage recovery (always succeeds)
echo "[12] Mount point still active, attempting unmount..."
safe_unmount_cleanup "${BACKUP_MNT}"

# Final sync
sync

# Verify unmount status (informational only)
sleep 1
if mountpoint -q "${BACKUP_MNT}"; then
    echo "[WARN] ⚠ Device still mounted after unmount attempts"
    echo "[WARN] This is non-critical - backup has completed successfully"
    echo "[WARN] Current mount status:"
    findmnt -M "${BACKUP_MNT}" 2>&1 || true
    echo ""
    echo "[WARN] Device will be auto-unmounted on next boot"
    echo "[WARN] Or unmount manually later:"
    echo "  sudo systemctl stop ${SYSTEMD_UNIT}.automount"
    echo "  sudo umount -l ${BACKUP_MNT}"
else
    echo "[12] ✓ Unmount verified - device fully offline (ransomware protection)"
fi

# Copy log to backup location if it was set (informational only)
if [ -n "${BACKUP_LOG:-}" ] && [ -f "${LOCAL_LOG:-}" ]; then
    echo "[12] Note: Log was saved during backup run"
    echo "[12] Local log: ${LOCAL_LOG}"
fi

# Always succeed in cleanup context
# This ensures HDD spindown (segment 11) and Shelly power-off (segment 13) still execute
exit 0
