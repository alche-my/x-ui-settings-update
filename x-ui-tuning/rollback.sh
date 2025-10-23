#!/bin/bash

# ============================================
# Rollback Script for 3x-ui Configuration
# ============================================
# Version: 1.0
# Purpose: Restore previous configuration from backup
# ============================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
if [[ ! -f "${SCRIPT_DIR}/common-functions.sh" ]]; then
    echo "ERROR: common-functions.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

source "${SCRIPT_DIR}/common-functions.sh"

# ============================================
# Help Text
# ============================================

show_help() {
    cat << EOF
Rollback Script for 3x-ui Configuration

Usage: $0 <backup_file>

This script restores a previous 3x-ui configuration from a backup file.
The backup file should be a JSON configuration file created by one of the
level configuration scripts.

Arguments:
  backup_file   Path to the backup configuration file

Options:
  --force       Skip confirmation prompt
  --no-restart  Don't restart x-ui service after rollback
  -h, --help    Show this help message

Examples:
  # Restore from backup (with confirmation)
  $0 /root/3x-ui-backups/config-2025-10-23-14-30-00.json

  # Restore without confirmation
  $0 --force /root/3x-ui-backups/config-2025-10-23-14-30-00.json

  # List available backups
  ls -lh /root/3x-ui-backups/

EOF
}

# ============================================
# Rollback Functions
# ============================================

list_backups() {
    local backup_dir="/root/3x-ui-backups"

    if [[ ! -d "${backup_dir}" ]]; then
        log_warning "No backup directory found: ${backup_dir}"
        return 1
    fi

    local backups=($(ls -t "${backup_dir}"/config-*.json 2>/dev/null || true))

    if [[ ${#backups[@]} -eq 0 ]]; then
        log_warning "No backups found in ${backup_dir}"
        return 1
    fi

    echo ""
    log_info "Available backups (newest first):"
    echo ""

    local count=1
    for backup in "${backups[@]}"; do
        local size=$(du -h "${backup}" | cut -f1)
        local date=$(stat -c %y "${backup}" | cut -d' ' -f1,2 | cut -d'.' -f1)
        printf "  %2d. %s\n" "${count}" "$(basename ${backup})"
        printf "      Size: %s | Date: %s\n" "${size}" "${date}"
        ((count++))
    done

    echo ""
    return 0
}

validate_backup() {
    local backup_file=$1

    # Check if file exists
    if [[ ! -f "${backup_file}" ]]; then
        log_error "Backup file not found: ${backup_file}"
        return 1
    fi

    # Check if readable
    if [[ ! -r "${backup_file}" ]]; then
        log_error "Cannot read backup file: ${backup_file}"
        return 1
    fi

    # Validate JSON
    if ! jq empty "${backup_file}" 2>/dev/null; then
        log_error "Invalid JSON in backup file: ${backup_file}"
        return 1
    fi

    log_success "Backup file is valid: ${backup_file}"
    return 0
}

show_backup_info() {
    local backup_file=$1

    log_info "Backup file information:"
    echo ""

    local size=$(du -h "${backup_file}" | cut -f1)
    local date=$(stat -c %y "${backup_file}" | cut -d' ' -f1,2 | cut -d'.' -f1)

    echo "  File: $(basename ${backup_file})"
    echo "  Path: ${backup_file}"
    echo "  Size: ${size}"
    echo "  Date: ${date}"
    echo ""

    # Show inbounds count
    local inbounds=$(jq '.inbounds | length' "${backup_file}" 2>/dev/null || echo "unknown")
    local outbounds=$(jq '.outbounds | length' "${backup_file}" 2>/dev/null || echo "unknown")

    echo "  Inbounds: ${inbounds}"
    echo "  Outbounds: ${outbounds}"
    echo ""
}

perform_rollback() {
    local backup_file=$1
    local target_config=$2

    log_info "Rolling back configuration..."

    # Create a backup of current config before rollback
    local pre_rollback_backup="${BACKUP_DIR}/pre-rollback-${TIMESTAMP}.json"
    cp "${target_config}" "${pre_rollback_backup}" || {
        log_error "Failed to backup current configuration"
        return 1
    }
    log_info "Current configuration backed up to: ${pre_rollback_backup}"

    # Copy backup to target
    cp "${backup_file}" "${target_config}" || {
        log_error "Failed to restore backup"
        # Try to restore the pre-rollback backup
        cp "${pre_rollback_backup}" "${target_config}"
        return 1
    }

    log_success "Configuration restored from backup"
    return 0
}

# ============================================
# Main Function
# ============================================

main() {
    local backup_file=""
    local force=false
    local no_restart=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            --no-restart)
                no_restart=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --list)
                list_backups
                exit 0
                ;;
            *)
                if [[ -z "${backup_file}" ]]; then
                    backup_file="$1"
                fi
                shift
                ;;
        esac
    done

    # Initialize
    init_logging "rollback"
    init_backup_dir || exit_with_error 1 "Failed to initialize backup directory"

    print_header "🔄 Configuration Rollback"

    # Check if backup file provided
    if [[ -z "${backup_file}" ]]; then
        log_error "No backup file specified"
        echo ""
        list_backups
        echo ""
        log_info "Usage: $0 <backup_file>"
        log_info "For more options, run: $0 --help"
        exit 1
    fi

    # Preflight checks
    check_root || exit_with_error 4 "Root privileges required"
    check_x_ui_service || exit_with_error 2 "x-ui service not available"

    local config_path=$(check_x_ui_config)
    if [[ -z "${config_path}" ]]; then
        exit_with_error 1 "x-ui configuration not found"
    fi

    # Validate backup
    log_info ""
    if ! validate_backup "${backup_file}"; then
        exit_with_error 1 "Invalid backup file"
    fi

    # Show backup info
    log_info ""
    show_backup_info "${backup_file}"

    # Confirm action
    if [[ "${force}" == "false" ]]; then
        if ! confirm_action "⚠️  This will restore the configuration from the backup file."; then
            log_info "Rollback cancelled"
            exit 0
        fi
    fi

    # Perform rollback
    log_info ""
    if ! perform_rollback "${backup_file}" "${config_path}"; then
        exit_with_error 1 "Rollback failed"
    fi

    # Restart service
    if [[ "${no_restart}" == "false" ]]; then
        log_info ""
        if ! restart_x_ui; then
            log_error "Service restart failed after rollback"
            log_warning "Configuration was restored, but service needs manual restart"
            log_info "Try: systemctl restart x-ui"
            exit_with_error 2 "Service restart failed"
        fi
    else
        log_warning "Service restart skipped (--no-restart flag)"
        log_info "Remember to restart x-ui manually: systemctl restart x-ui"
    fi

    # Success
    print_header "✅ ROLLBACK COMPLETED SUCCESSFULLY"

    log_info "Configuration restored from:"
    log_info "  ${backup_file}"
    log_info ""
    log_info "x-ui service has been restarted"
    log_info ""
    log_info "Test connectivity from your client to verify the rollback"

    print_footer

    exit 0
}

# ============================================
# Script Entry Point
# ============================================

main "$@"
