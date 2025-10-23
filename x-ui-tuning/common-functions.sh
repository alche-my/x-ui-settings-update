#!/bin/bash

# ============================================
# Common Functions for 3x-ui Tuning Scripts
# ============================================
# Version: 1.0
# Purpose: Shared utilities for DPI bypass configuration
# ============================================

# Color codes for output
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_MAGENTA='\033[0;35m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'

# Logging configuration
LOG_DIR="/var/log/x-ui-tuning"
BACKUP_DIR="/root/3x-ui-backups"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)

# Configuration paths
X_UI_CONFIG_PATHS=(
    "/usr/local/x-ui/bin/xray-linux-amd64/config.json"
    "/usr/local/x-ui/bin/config.json"
    "/etc/x-ui/config.json"
)

# Global variables
DRY_RUN=false
VERBOSE=false
SKIP_TESTS=false
SCRIPT_NAME=""
LOG_FILE=""

# ============================================
# Logging Functions
# ============================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Prepare log entry
    local log_entry="[${timestamp}] [${level}] ${message}"

    # Write to log file if set
    if [[ -n "${LOG_FILE}" ]]; then
        echo "${log_entry}" >> "${LOG_FILE}"
    fi

    # Output to console with colors
    case "${level}" in
        "INFO")
            echo -e "${COLOR_CYAN}[ℹ]${COLOR_RESET} ${message}"
            ;;
        "SUCCESS")
            echo -e "${COLOR_GREEN}[✓]${COLOR_RESET} ${message}"
            ;;
        "WARNING")
            echo -e "${COLOR_YELLOW}[⚠]${COLOR_RESET} ${message}"
            ;;
        "ERROR")
            echo -e "${COLOR_RED}[✗]${COLOR_RESET} ${message}"
            ;;
        "DEBUG")
            if [[ "${VERBOSE}" == "true" ]]; then
                echo -e "${COLOR_MAGENTA}[DEBUG]${COLOR_RESET} ${message}"
            fi
            ;;
        "CHANGE")
            echo -e "${COLOR_BLUE}[+]${COLOR_RESET} ${message}"
            ;;
        *)
            echo "${message}"
            ;;
    esac
}

log_info() {
    log "INFO" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

log_warning() {
    log "WARNING" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_debug() {
    log "DEBUG" "$@"
}

log_change() {
    log "CHANGE" "$@"
}

# ============================================
# Initialization Functions
# ============================================

init_logging() {
    local script_name=$1
    SCRIPT_NAME="${script_name}"

    # Create log directory
    mkdir -p "${LOG_DIR}" 2>/dev/null

    # Set log file path
    LOG_FILE="${LOG_DIR}/${script_name}-${TIMESTAMP}.log"

    # Create log file
    touch "${LOG_FILE}" 2>/dev/null || {
        log_warning "Cannot create log file ${LOG_FILE}, logging to console only"
        LOG_FILE=""
    }

    log_debug "Logging initialized: ${LOG_FILE}"
}

init_backup_dir() {
    mkdir -p "${BACKUP_DIR}" 2>/dev/null || {
        log_error "Failed to create backup directory: ${BACKUP_DIR}"
        return 1
    }
    log_debug "Backup directory ready: ${BACKUP_DIR}"
    return 0
}

# ============================================
# Validation Functions
# ============================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        log_info "Please run: sudo $0"
        return 1
    fi
    log_success "Root access confirmed"
    return 0
}

check_disk_space() {
    local required_mb=${1:-100}
    local available_kb=$(df /root | tail -1 | awk '{print $4}')
    local available_mb=$((available_kb / 1024))

    if [[ ${available_mb} -lt ${required_mb} ]]; then
        log_error "Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
        return 1
    fi

    log_success "Disk space available: ${available_mb}MB"
    return 0
}

check_dependencies() {
    local deps=("jq" "curl" "systemctl")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            missing+=("${dep}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Install with: apt-get install ${missing[*]} -y"
        return 1
    fi

    log_success "All dependencies installed"
    return 0
}

check_x_ui_service() {
    if ! systemctl is-active --quiet x-ui; then
        log_warning "x-ui service is not running"
        log_info "Attempting to start x-ui..."
        systemctl start x-ui
        sleep 2
        if ! systemctl is-active --quiet x-ui; then
            log_error "Failed to start x-ui service"
            return 1
        fi
    fi
    log_success "x-ui service is running"
    return 0
}

find_x_ui_config() {
    for config_path in "${X_UI_CONFIG_PATHS[@]}"; do
        if [[ -f "${config_path}" ]]; then
            echo "${config_path}"
            return 0
        fi
    done
    return 1
}

check_x_ui_config() {
    local config_path=$(find_x_ui_config)

    if [[ -z "${config_path}" ]]; then
        log_error "x-ui configuration file not found"
        log_info "Searched paths:"
        for path in "${X_UI_CONFIG_PATHS[@]}"; do
            log_info "  - ${path}"
        done
        return 1
    fi

    if [[ ! -r "${config_path}" ]]; then
        log_error "Cannot read configuration file: ${config_path}"
        return 1
    fi

    # Validate JSON
    if ! jq empty "${config_path}" 2>/dev/null; then
        log_error "Invalid JSON in configuration file: ${config_path}"
        return 1
    fi

    log_success "Configuration file found and valid: ${config_path}"
    echo "${config_path}"
    return 0
}

# ============================================
# Backup Functions
# ============================================

backup_config() {
    local config_path=$1
    local backup_name="${BACKUP_DIR}/config-${TIMESTAMP}.json"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would backup ${config_path} to ${backup_name}"
        echo "${backup_name}"
        return 0
    fi

    cp "${config_path}" "${backup_name}" || {
        log_error "Failed to create backup"
        return 1
    }

    log_success "Backup created: ${backup_name}"
    echo "${backup_name}"
    return 0
}

# ============================================
# Configuration Modification Functions
# ============================================

validate_json() {
    local json_file=$1

    if ! jq empty "${json_file}" 2>/dev/null; then
        log_error "JSON validation failed for: ${json_file}"
        return 1
    fi

    log_success "JSON validation passed"
    return 0
}

apply_config() {
    local temp_config=$1
    local target_config=$2

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would replace ${target_config} with new configuration"
        log_info "[DRY RUN] New configuration preview:"
        if [[ "${VERBOSE}" == "true" ]]; then
            jq . "${temp_config}"
        fi
        return 0
    fi

    # Validate before replacing
    if ! validate_json "${temp_config}"; then
        log_error "Cannot apply invalid configuration"
        return 1
    fi

    # Atomic replacement
    mv "${temp_config}" "${target_config}" || {
        log_error "Failed to apply new configuration"
        return 1
    }

    log_success "Configuration applied successfully"
    return 0
}

# ============================================
# Service Management Functions
# ============================================

restart_x_ui() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would restart x-ui service"
        return 0
    fi

    log_info "Restarting x-ui service..."
    systemctl restart x-ui || {
        log_error "Failed to restart x-ui service"
        return 1
    }

    # Wait for service to start
    sleep 3

    if ! systemctl is-active --quiet x-ui; then
        log_error "x-ui service failed to start"
        log_info "Check logs with: journalctl -u x-ui -n 50"
        return 1
    fi

    log_success "x-ui service restarted successfully"
    return 0
}

# ============================================
# Testing Functions
# ============================================

test_connectivity() {
    local url=$1
    local timeout=${2:-5}
    local test_name=${3:-"${url}"}

    if [[ "${SKIP_TESTS}" == "true" ]]; then
        log_info "Skipping test: ${test_name}"
        return 0
    fi

    log_info "Testing ${test_name}..."

    local start_time=$(date +%s%3N)
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "${timeout}" "${url}" 2>/dev/null)
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    if [[ "${http_code}" == "200" ]] || [[ "${http_code}" == "301" ]] || [[ "${http_code}" == "302" ]]; then
        log_success "${test_name}: HTTP ${http_code} (${duration}ms)"
        return 0
    else
        log_error "${test_name}: HTTP ${http_code} (${duration}ms)"
        return 1
    fi
}

test_dns() {
    local domain=$1

    if [[ "${SKIP_TESTS}" == "true" ]]; then
        log_info "Skipping DNS test: ${domain}"
        return 0
    fi

    log_info "Testing DNS resolution for ${domain}..."

    if dig +short "${domain}" @8.8.8.8 | grep -qE '^[0-9.]+$'; then
        log_success "DNS resolution successful: ${domain}"
        return 0
    else
        log_error "DNS resolution failed: ${domain}"
        return 1
    fi
}

# ============================================
# Utility Functions
# ============================================

print_header() {
    local title=$1
    local width=50

    echo ""
    echo -e "${COLOR_CYAN}$(printf '=%.0s' {1..50})${COLOR_RESET}"
    echo -e "${COLOR_CYAN}${title}${COLOR_RESET}"
    echo -e "${COLOR_CYAN}$(printf '=%.0s' {1..50})${COLOR_RESET}"
    echo ""
}

print_footer() {
    echo ""
    echo -e "${COLOR_CYAN}$(printf '=%.0s' {1..50})${COLOR_RESET}"
    echo ""
}

print_summary() {
    local title=$1
    shift
    local items=("$@")

    echo ""
    echo -e "${COLOR_BLUE}📊 ${title}${COLOR_RESET}"
    for item in "${items[@]}"; do
        echo -e "  ${item}"
    done
}

confirm_action() {
    local message=$1

    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    echo -e "${COLOR_YELLOW}${message}${COLOR_RESET}"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Operation cancelled by user"
        return 1
    fi
    return 0
}

# ============================================
# Error Handling
# ============================================

exit_with_error() {
    local exit_code=$1
    shift
    local message="$*"

    log_error "${message}"
    print_footer
    exit "${exit_code}"
}

# ============================================
# Argument Parsing
# ============================================

parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log_warning "DRY RUN MODE: No changes will be applied"
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            -h|--help)
                return 1
                ;;
            *)
                log_warning "Unknown option: $1"
                shift
                ;;
        esac
    done
    return 0
}

# Export functions
export -f log log_info log_success log_warning log_error log_debug log_change
export -f init_logging init_backup_dir
export -f check_root check_disk_space check_dependencies check_x_ui_service check_x_ui_config find_x_ui_config
export -f backup_config validate_json apply_config
export -f restart_x_ui
export -f test_connectivity test_dns
export -f print_header print_footer print_summary confirm_action
export -f exit_with_error parse_common_args
