#!/usr/bin/env bash
# deploy.sh
# @version 1.0.0
# @description Deploy backup system from development directory to production
# @author Jo Zapf
# @date 2026-01-22
#
# Purpose:
# - Copy backup system files from Git repo to /opt/backup-system
# - Set correct permissions and ownership
# - Preserve secrets.env (don't overwrite production secrets)
# - Restart systemd timers if they exist
#
# Usage:
# sudo ./deploy.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="/opt/backup-system"
BACKUP_SUFFIX=".pre-deploy-$(date +%Y%m%d-%H%M%S)"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Create backup of production if exists
backup_production() {
    if [ -d "$TARGET_DIR" ]; then
        log_info "Creating backup of current production..."
        local backup_dir="${TARGET_DIR}${BACKUP_SUFFIX}"
        cp -a "$TARGET_DIR" "$backup_dir"
        log_success "Backup created: $backup_dir"
    fi
}

# Deploy files
deploy_files() {
    log_info "Deploying from: $SOURCE_DIR"
    log_info "Deploying to: $TARGET_DIR"
    
    # Create target directory if it doesn't exist
    mkdir -p "$TARGET_DIR"
    
    # Copy main script
    log_info "Copying run-backup.sh..."
    cp -v "$SOURCE_DIR/run-backup.sh" "$TARGET_DIR/"
    chmod +x "$TARGET_DIR/run-backup.sh"
    
    # Copy segments directory
    log_info "Copying segments..."
    rm -rf "$TARGET_DIR/segments"
    cp -r "$SOURCE_DIR/segments" "$TARGET_DIR/"
    chmod +x "$TARGET_DIR/segments"/*.sh
    
    # Copy lib directory (optional - may not exist yet)
    if [ -d "$SOURCE_DIR/lib" ]; then
        log_info "Copying lib..."
        rm -rf "$TARGET_DIR/lib"
        cp -r "$SOURCE_DIR/lib" "$TARGET_DIR/"
    else
        log_info "No lib directory found (skipping - optional)"
        # Remove old lib directory if it exists from previous deploys
        if [ -d "$TARGET_DIR/lib" ]; then
            log_info "Removing old lib directory from production"
            rm -rf "$TARGET_DIR/lib"
        fi
    fi
    
    # Copy config directory (carefully!)
    log_info "Copying config..."
    
    # Create config directory structure
    mkdir -p "$TARGET_DIR/config/profiles"
    
    # Copy profile templates
    cp -v "$SOURCE_DIR/config/profiles"/*.env "$TARGET_DIR/config/profiles/" || true
    
    # Copy secrets.env.example (NOT secrets.env - preserve production secrets!)
    if [ -f "$SOURCE_DIR/config/secrets.env.example" ]; then
        cp -v "$SOURCE_DIR/config/secrets.env.example" "$TARGET_DIR/config/"
    fi
    
    # Copy common.env
    if [ -f "$SOURCE_DIR/config/common.env" ]; then
        cp -v "$SOURCE_DIR/config/common.env" "$TARGET_DIR/config/"
    fi
    
    # Preserve production secrets.env if it exists
    if [ -f "$TARGET_DIR/config/secrets.env" ]; then
        log_warn "Preserving existing secrets.env (not overwritten)"
    else
        log_warn "No secrets.env found in production - copy secrets.env.example and configure it!"
        log_warn "  sudo cp $TARGET_DIR/config/secrets.env.example $TARGET_DIR/config/secrets.env"
        log_warn "  sudo nano $TARGET_DIR/config/secrets.env"
    fi
    
    # Copy documentation
    log_info "Copying documentation..."
    cp -v "$SOURCE_DIR/README.md" "$TARGET_DIR/" || true
    cp -v "$SOURCE_DIR/CHANGELOG.md" "$TARGET_DIR/" || true
    
    log_success "Files deployed successfully"
}

# Set permissions
set_permissions() {
    log_info "Setting permissions..."
    
    # Main script
    chmod 750 "$TARGET_DIR/run-backup.sh"
    
    # Segments
    chmod 750 "$TARGET_DIR/segments"/*.sh
    
    # Config files (protect secrets!)
    chmod 750 "$TARGET_DIR/config"
    chmod 640 "$TARGET_DIR/config"/*.env 2>/dev/null || true
    chmod 640 "$TARGET_DIR/config/profiles"/*.env 2>/dev/null || true
    
    # secrets.env needs stricter permissions (600 = owner only)
    if [ -f "$TARGET_DIR/config/secrets.env" ]; then
        chmod 600 "$TARGET_DIR/config/secrets.env"
        log_info "Set secrets.env permissions to 600 (owner only)"
    fi
    
    # Lib files (optional)
    if [ -d "$TARGET_DIR/lib" ]; then
        chmod 644 "$TARGET_DIR/lib"/*.sh
    fi
    
    # Set ownership (root:root for security)
    chown -R root:root "$TARGET_DIR"
    
    log_success "Permissions set"
}

# Check systemd timers
check_systemd_timers() {
    log_info "Checking systemd timers..."
    
    local timers_found=false
    
    if systemctl list-unit-files | grep -q "backup-system.*timer"; then
        log_info "Found backup-system timers:"
        systemctl list-unit-files | grep "backup-system.*timer" || true
        timers_found=true
    fi
    
    if [ "$timers_found" = true ]; then
        read -p "Reload systemd daemon and restart timers? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Reloading systemd daemon..."
            systemctl daemon-reload
            
            # Restart all backup-system timers
            for timer in $(systemctl list-unit-files | grep "backup-system.*timer" | awk '{print $1}'); do
                log_info "Restarting $timer..."
                systemctl restart "$timer"
            done
            
            log_success "Systemd timers restarted"
        fi
    else
        log_info "No systemd timers found (manual setup required)"
    fi
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    local errors=0
    
    # Check main script
    if [ ! -x "$TARGET_DIR/run-backup.sh" ]; then
        log_error "run-backup.sh not found or not executable"
        ((errors++))
    fi
    
    # Check segments
    if [ ! -d "$TARGET_DIR/segments" ]; then
        log_error "segments directory not found"
        ((errors++))
    fi
    
    # Check config
    if [ ! -d "$TARGET_DIR/config" ]; then
        log_error "config directory not found"
        ((errors++))
    fi
    
    # Note: lib directory is optional (may not exist)
    
    # Check secrets.env
    if [ ! -f "$TARGET_DIR/config/secrets.env" ]; then
        log_warn "secrets.env not configured - deployment incomplete!"
        log_warn "Configure secrets before running backups"
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "Deployment verified successfully"
        return 0
    else
        log_error "Deployment verification failed with $errors errors"
        return 1
    fi
}

# Show deployment summary
show_summary() {
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}DEPLOYMENT COMPLETED${NC}"
    echo "==============================================================================="
    echo "Source: $SOURCE_DIR"
    echo "Target: $TARGET_DIR"
    echo "Backup: ${TARGET_DIR}${BACKUP_SUFFIX} (if existed)"
    echo ""
    echo "Next steps:"
    echo "1. Verify secrets.env is configured:"
    echo "   sudo cat $TARGET_DIR/config/secrets.env"
    echo ""
    echo "2. Test a backup manually:"
    echo "   sudo $TARGET_DIR/run-backup.sh system"
    echo ""
    echo "3. Check systemd timers (if using automation):"
    echo "   systemctl list-timers | grep backup"
    echo "==============================================================================="
}

# Main execution
main() {
    echo "==============================================================================="
    echo "BACKUP SYSTEM DEPLOYMENT"
    echo "==============================================================================="
    
    check_root
    backup_production
    deploy_files
    set_permissions
    check_systemd_timers
    
    if verify_deployment; then
        show_summary
        exit 0
    else
        log_error "Deployment failed - check errors above"
        exit 1
    fi
}

# Execute
main "$@"
