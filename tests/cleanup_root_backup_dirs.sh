#!/bin/bash
################################################################################
# Cleanup Script: Remove accidentally created backup directories on root FS
# Version: 1.0.0
# Purpose: Clean up backup data that was written to mount-points on root
#          filesystem instead of mounted backup devices
#
# CRITICAL: This script removes data from /mnt/extern_backup and 
#           /mnt/system_backup that exists on the ROOT filesystem
#
# Usage: sudo ./cleanup_root_backup_dirs.sh
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "==============================================================================="
echo "  BACKUP SYSTEM - ROOT FILESYSTEM CLEANUP"
echo "==============================================================================="
echo ""
echo -e "${RED}WARNING: This script will delete data from mount-points on root filesystem!${NC}"
echo ""
echo "This cleanup is necessary when backup data was accidentally written to"
echo "mount-point directories instead of mounted backup devices."
echo ""
echo "Affected directories:"
echo "  - /mnt/extern_backup"
echo "  - /mnt/system_backup"
echo ""
echo -e "${YELLOW}IMPORTANT: Devices must be UNMOUNTED before running this script!${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Safety checks
echo "=== Pre-flight Safety Checks ==="
echo ""

# 1. Check if mount-points are actually unmounted
for mount_point in /mnt/extern_backup /mnt/system_backup; do
    echo "Checking: ${mount_point}"
    
    if mountpoint -q "${mount_point}"; then
        echo -e "${RED}ERROR: ${mount_point} is currently MOUNTED!${NC}"
        echo -e "${RED}You must unmount it first: sudo umount ${mount_point}${NC}"
        exit 1
    fi
    
    # Check immutable flag
    if lsattr -d "${mount_point}" 2>/dev/null | grep -q "i"; then
        echo "  ✓ Has immutable flag (good - protected)"
    else
        echo -e "  ${YELLOW}⚠ Missing immutable flag${NC}"
    fi
    
    # Check if directory exists and has content
    if [ -d "${mount_point}" ]; then
        content_count=$(ls -A "${mount_point}" 2>/dev/null | wc -l)
        if [ "${content_count}" -gt 0 ]; then
            echo -e "  ${YELLOW}⚠ Contains ${content_count} items${NC}"
        else
            echo "  ✓ Empty"
        fi
    else
        echo "  ℹ Does not exist"
    fi
    echo ""
done

# 2. Show what will be deleted
echo "=== Data to be deleted ==="
echo ""
for mount_point in /mnt/extern_backup /mnt/system_backup; do
    if [ -d "${mount_point}" ] && [ "$(ls -A "${mount_point}" 2>/dev/null)" ]; then
        echo "Directory: ${mount_point}"
        echo "Contents:"
        ls -lh "${mount_point}" | tail -n +2
        
        # Calculate size
        size=$(du -sh "${mount_point}" 2>/dev/null | cut -f1)
        echo ""
        echo "Total size: ${size}"
        echo ""
    fi
done

# 3. Confirmation prompt
echo "==============================================================================="
echo -e "${RED}FINAL CONFIRMATION${NC}"
echo "==============================================================================="
echo ""
echo "This will:"
echo "  1. Remove immutable flags from mount-points"
echo "  2. Delete ALL content from unmounted mount-point directories"
echo "  3. Recreate empty mount-point directories"
echo "  4. Restore immutable flags"
echo ""
echo -ne "${YELLOW}Type 'DELETE' (all caps) to confirm: ${NC}"
read -r confirmation

if [ "${confirmation}" != "DELETE" ]; then
    echo ""
    echo -e "${GREEN}Cleanup cancelled. No changes made.${NC}"
    exit 0
fi

# 4. Perform cleanup
echo ""
echo "==============================================================================="
echo "  EXECUTING CLEANUP"
echo "==============================================================================="
echo ""

for mount_point in /mnt/extern_backup /mnt/system_backup; do
    if [ ! -d "${mount_point}" ]; then
        echo "Skipping ${mount_point} (does not exist)"
        continue
    fi
    
    echo "Processing: ${mount_point}"
    
    # Remove immutable flag
    echo "  - Removing immutable flag..."
    chattr -i "${mount_point}" 2>/dev/null || true
    
    # Count items before deletion
    item_count=$(ls -A "${mount_point}" 2>/dev/null | wc -l)
    
    if [ "${item_count}" -gt 0 ]; then
        # Delete contents
        echo "  - Deleting ${item_count} items..."
        rm -rf "${mount_point:?}"/*
        rm -rf "${mount_point:?}"/.[!.]*
        
        # Verify deletion
        remaining=$(ls -A "${mount_point}" 2>/dev/null | wc -l)
        if [ "${remaining}" -eq 0 ]; then
            echo -e "  ${GREEN}✓ All items deleted${NC}"
        else
            echo -e "  ${RED}✗ ${remaining} items remaining (manual cleanup needed)${NC}"
        fi
    else
        echo "  - Directory already empty"
    fi
    
    # Restore immutable flag
    echo "  - Restoring immutable flag..."
    chattr +i "${mount_point}"
    
    # Verify
    if lsattr -d "${mount_point}" 2>/dev/null | grep -q "i"; then
        echo -e "  ${GREEN}✓ Immutable flag restored${NC}"
    else
        echo -e "  ${RED}✗ Failed to set immutable flag${NC}"
    fi
    
    echo ""
done

echo "==============================================================================="
echo "  CLEANUP COMPLETE"
echo "==============================================================================="
echo ""
echo -e "${GREEN}Mount-points have been cleaned and protected.${NC}"
echo ""
echo "Next steps:"
echo "  1. Mount backup devices: sudo mount -a"
echo "  2. Verify mounts: findmnt /mnt/extern_backup /mnt/system_backup"
echo "  3. Test backup: sudo /opt/backup-system/run-backup.sh <profile>"
echo ""
