#!/bin/bash

# ============================================
# Level 1: Basic DPI Bypass Configuration
# ============================================
# Version: 1.0
# Purpose: Configure basic DPI bypass for 3x-ui (VLESS+Reality)
# Based on: GitHub Issue #5704 (Oct 23, 2025)
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
# Script Configuration
# ============================================

LEVEL="1"
LEVEL_NAME="Basic DPI Bypass"

# ============================================
# Help Text
# ============================================

show_help() {
    cat << EOF
Level 1: Basic DPI Bypass Configuration

Usage: $0 [OPTIONS]

This script configures basic DPI bypass for 3x-ui server running VLESS+Reality.
It modifies the Xray configuration to add fragment, TCP optimizations, and
basic obfuscation to bypass Russian ISP DPI filtering.

Changes applied:
  - Fragment settings for TLS Client Hello (100-200 bytes, 10-20ms interval)
  - TCP Fast Open for reduced latency
  - TCP Keep-Alive optimization
  - Packet marking for system routing
  - Basic routing rules for HTTP/HTTPS (ports 80, 443)

Options:
  --dry-run       Show what would be changed without applying
  --verbose       Enable detailed debug output
  --skip-tests    Skip connectivity tests after applying configuration
  -h, --help      Show this help message

Examples:
  # Preview changes without applying
  $0 --dry-run

  # Apply configuration with detailed output
  $0 --verbose

  # Apply without running tests (faster)
  $0 --skip-tests

Rollback:
  If something goes wrong, use rollback.sh with the backup file path
  shown in the output.

For more information, see README.md

EOF
}

# ============================================
# Configuration Modification Functions
# ============================================

modify_outbound_config() {
    local config_file=$1
    local temp_file="${config_file}.level1.tmp"

    log_info "Modifying outbound configuration..."

    # Read current config
    local config_json=$(cat "${config_file}")

    # Build the modified configuration using jq
    # We'll add fragment and sockopt settings to the freedom outbound
    local modified_config=$(echo "${config_json}" | jq '
        # Ensure outbounds array exists
        if .outbounds == null then .outbounds = [] else . end |

        # Find or create freedom outbound
        if (.outbounds | map(select(.protocol == "freedom")) | length) == 0 then
            .outbounds += [{
                "protocol": "freedom",
                "tag": "direct",
                "settings": {}
            }]
        else . end |

        # Modify freedom outbound with Level 1 settings
        .outbounds |= map(
            if .protocol == "freedom" then
                . + {
                    "settings": (.settings // {}) + {
                        "domainStrategy": "UseIP",
                        "fragment": {
                            "packets": "tlshello",
                            "length": "100-200",
                            "interval": "10-20"
                        }
                    },
                    "streamSettings": (.streamSettings // {}) + {
                        "sockopt": {
                            "tcpFastOpen": true,
                            "tcpKeepAliveInterval": 30,
                            "mark": 255
                        }
                    }
                }
            else . end
        ) |

        # Ensure blackhole outbound exists
        if (.outbounds | map(select(.protocol == "blackhole")) | length) == 0 then
            .outbounds += [{
                "protocol": "blackhole",
                "tag": "block"
            }]
        else . end |

        # Add/update routing configuration
        .routing = (.routing // {}) + {
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                {
                    "type": "field",
                    "port": "80,443",
                    "network": "tcp",
                    "outboundTag": "direct"
                }
            ] + (if .routing.rules then .routing.rules else [] end | map(select(.type != "field" or .port != "80,443")))
        }
    ')

    # Write to temporary file
    echo "${modified_config}" | jq . > "${temp_file}"

    # Validate the generated JSON
    if ! validate_json "${temp_file}"; then
        rm -f "${temp_file}"
        return 1
    fi

    echo "${temp_file}"
    return 0
}

# ============================================
# Report Generation Functions
# ============================================

generate_change_report() {
    local backup_file=$1

    print_summary "Configuration Changes Applied" \
        "Fragment settings:" \
        "  - Packets: tlshello (Client Hello only)" \
        "  - Length: 100-200 bytes per fragment" \
        "  - Interval: 10-20 ms between fragments" \
        "" \
        "TCP Optimizations:" \
        "  - TCP Fast Open: ENABLED" \
        "  - Keep-Alive Interval: 30 seconds" \
        "  - Packet Mark: 255" \
        "" \
        "Routing Rules:" \
        "  - Ports: 80 (HTTP), 443 (HTTPS)" \
        "  - Network: TCP" \
        "  - Strategy: IPIfNonMatch" \
        "" \
        "Domain Strategy:" \
        "  - UseIP (resolve domains to IPs)"
}

generate_test_report() {
    local tests_passed=$1
    local tests_total=$2

    echo "" >&2
    echo -e "${COLOR_BLUE}🧪 Connectivity Test Results${COLOR_RESET}" >&2
    echo -e "  Tests passed: ${tests_passed}/${tests_total}" >&2

    if [[ ${tests_passed} -eq ${tests_total} ]]; then
        echo -e "  ${COLOR_GREEN}All tests passed!${COLOR_RESET}" >&2
    elif [[ ${tests_passed} -eq 0 ]]; then
        echo -e "  ${COLOR_RED}All tests failed!${COLOR_RESET}" >&2
        echo -e "  ${COLOR_YELLOW}This might be normal if testing from the server itself.${COLOR_RESET}" >&2
        echo -e "  ${COLOR_YELLOW}Test from your client using v2Ray to verify.${COLOR_RESET}" >&2
    else
        echo -e "  ${COLOR_YELLOW}Some tests failed.${COLOR_RESET}" >&2
    fi
}

generate_next_steps() {
    echo "" >&2
    echo -e "${COLOR_BLUE}🔄 Next Steps${COLOR_RESET}" >&2
    echo "  1. Test from your client using v2Ray with your VLESS key" >&2
    echo "  2. Check access to Discord, YouTube, Google" >&2
    echo "  3. If stable after 5-10 minutes, proceed to Level 2" >&2
    echo "  4. If issues occur, use rollback command below" >&2
}

generate_rollback_info() {
    local backup_file=$1

    echo "" >&2
    echo -e "${COLOR_YELLOW}⚠️  Rollback Command (if needed)${COLOR_RESET}" >&2
    echo "  ${SCRIPT_DIR}/rollback.sh ${backup_file}" >&2
}

# ============================================
# Main Execution Functions
# ============================================

run_preflight_checks() {
    log_info "Running preflight checks..."

    check_root || exit_with_error 4 "Root privileges required"
    check_disk_space 100 || exit_with_error 1 "Insufficient disk space"

    # Auto-install dependencies if needed
    install_dependencies_if_needed || exit_with_error 1 "Failed to install dependencies"

    check_x_ui_service || exit_with_error 2 "x-ui service not available"

    local config_path=$(check_x_ui_config)
    if [[ -z "${config_path}" ]]; then
        exit_with_error 1 "x-ui configuration not found"
    fi

    echo "${config_path}"
}

run_connectivity_tests() {
    log_info "Running connectivity tests..."

    local tests_passed=0
    local tests_total=3

    # Test basic connectivity
    test_connectivity "https://www.google.com" 10 "Google" && ((tests_passed++)) || true
    test_connectivity "https://discord.com" 10 "Discord" && ((tests_passed++)) || true
    test_connectivity "https://www.youtube.com" 10 "YouTube" && ((tests_passed++)) || true

    echo "${tests_passed} ${tests_total}"
}

main() {
    # Parse arguments
    if ! parse_common_args "$@"; then
        show_help
        exit 0
    fi

    # Initialize
    init_logging "level-${LEVEL}"
    init_backup_dir || exit_with_error 1 "Failed to initialize backup directory"

    # Print header
    print_header "🔧 Level ${LEVEL}: ${LEVEL_NAME}"

    log_info "Script started at $(date)"
    log_info "Log file: ${LOG_FILE}"

    # Preflight checks
    log_info ""
    local config_path=$(run_preflight_checks)
    log_debug "Configuration path: ${config_path}"

    # Create backup
    log_info ""
    log_info "📦 Creating backup..."
    local backup_file=$(backup_config "${config_path}")
    if [[ -z "${backup_file}" ]]; then
        exit_with_error 1 "Backup failed"
    fi

    # Modify configuration
    log_info ""
    log_info "🔨 Applying Level ${LEVEL} configuration..."
    log_info ""

    local temp_config=$(modify_outbound_config "${config_path}")
    if [[ -z "${temp_config}" ]]; then
        exit_with_error 1 "Configuration modification failed"
    fi

    log_change "Fragment settings added:"
    log_change "  - packets: tlshello"
    log_change "  - length: 100-200 bytes"
    log_change "  - interval: 10-20 ms"
    log_info ""

    log_change "TCP optimizations added:"
    log_change "  - tcpFastOpen: true"
    log_change "  - tcpKeepAliveInterval: 30s"
    log_change "  - mark: 255"
    log_info ""

    log_change "Routing rules added:"
    log_change "  - Ports: 80, 443 (HTTP/HTTPS)"
    log_change "  - Network: TCP"
    log_change "  - Strategy: IPIfNonMatch"
    log_info ""

    # Show diff if verbose
    if [[ "${VERBOSE}" == "true" ]] && [[ "${DRY_RUN}" == "false" ]]; then
        log_debug "Configuration diff:"
        diff -u "${config_path}" "${temp_config}" || true
    fi

    # Apply configuration
    if ! apply_config "${temp_config}" "${config_path}"; then
        rm -f "${temp_config}"
        exit_with_error 1 "Failed to apply configuration"
    fi

    # Restart service
    log_info ""
    if ! restart_x_ui; then
        log_error "Service restart failed, attempting rollback..."
        cp "${backup_file}" "${config_path}"
        systemctl restart x-ui
        exit_with_error 2 "Service restart failed, configuration rolled back"
    fi

    # Run tests
    log_info ""
    local test_results=($(run_connectivity_tests))
    local tests_passed=${test_results[0]}
    local tests_total=${test_results[1]}

    # Generate reports
    log_info ""
    print_header "✅ LEVEL ${LEVEL} APPLIED SUCCESSFULLY"

    generate_change_report "${backup_file}"
    generate_test_report ${tests_passed} ${tests_total}
    generate_next_steps
    generate_rollback_info "${backup_file}"

    print_footer

    log_info "Script completed successfully at $(date)"

    # Exit with appropriate code
    if [[ ${tests_passed} -eq 0 ]] && [[ "${SKIP_TESTS}" == "false" ]]; then
        exit 3
    fi

    exit 0
}

# ============================================
# Script Entry Point
# ============================================

main "$@"
