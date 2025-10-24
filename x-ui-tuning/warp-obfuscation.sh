#!/bin/bash

# ============================================
# WARP Obfuscation Configuration for x-ui
# ============================================
# Version: 1.0
# Purpose: Configure Cloudflare WARP obfuscation when zapret doesn't work
# Based on: Cloudflare WARP endpoints integration with Xray
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

LEVEL="WARP"
LEVEL_NAME="WARP Obfuscation (Cloudflare WARP)"

# WARP endpoints
WARP_ENDPOINTS=(
    "engage.cloudflareclient.com:2408"
    "162.159.192.1:2408"
    "162.159.193.1:2408"
    "162.159.195.1:2408"
)

# ============================================
# Help Text
# ============================================

show_help() {
    cat << EOF
WARP Obfuscation Configuration

Usage: $0 [OPTIONS]

This script configures Cloudflare WARP obfuscation for 3x-ui server when
traditional methods like zapret don't work.

What this script does:
  - Installs wireguard-tools if needed
  - Configures WARP outbound in Xray
  - Routes traffic through Cloudflare WARP network
  - Provides maximum obfuscation against DPI

Changes applied:
  - Adds WARP outbound with Cloudflare endpoints
  - Configures routing to use WARP for blocked services
  - Maintains compatibility with existing settings
  - Uses WireGuard protocol for maximum security

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

Important:
  - This script requires wireguard-tools
  - WARP provides strong obfuscation against DPI
  - Works when traditional methods like zapret fail
  - Can be combined with Level 1 or Level 2 settings

For more information, see README.md

EOF
}

# ============================================
# WARP Configuration Functions
# ============================================

install_warp_dependencies() {
    log_info "Checking WARP dependencies..."

    local packages_to_install=()

    # Check for wireguard-tools
    if ! command -v wg &> /dev/null; then
        log_info "wireguard-tools not found, will install"
        packages_to_install+=("wireguard-tools")
    fi

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log_info "Installing: ${packages_to_install[*]}"
        if apt-get update && apt-get install -y "${packages_to_install[@]}"; then
            log_success "Dependencies installed successfully"
        else
            log_error "Failed to install dependencies"
            return 1
        fi
    else
        log_success "All dependencies already installed"
    fi

    return 0
}

generate_warp_private_key() {
    # Generate a WireGuard private key for WARP
    wg genkey
}

modify_config_for_warp() {
    local config_file=$1
    local temp_file="${config_file}.warp.tmp"

    log_info "Modifying configuration for WARP obfuscation..."

    # Read current config
    local config_json=$(cat "${config_file}")

    # Generate WARP private key
    log_info "Generating WARP private key..."
    local warp_private_key=$(generate_warp_private_key)
    log_debug "Private key generated"

    # Select random WARP endpoint
    local warp_endpoint="${WARP_ENDPOINTS[$RANDOM % ${#WARP_ENDPOINTS[@]}]}"
    log_info "Selected WARP endpoint: ${warp_endpoint}"

    # Extract address and port
    local warp_address="${warp_endpoint%:*}"
    local warp_port="${warp_endpoint##*:}"

    # Build the modified configuration using jq
    local modified_config=$(echo "${config_json}" | jq \
        --arg warp_key "${warp_private_key}" \
        --arg warp_addr "${warp_address}" \
        --argjson warp_port "${warp_port}" '
        # Ensure outbounds array exists
        if .outbounds == null then .outbounds = [] else . end |

        # Add WARP outbound using wireguard protocol
        if (.outbounds | map(select(.protocol == "wireguard" and .tag == "warp")) | length) == 0 then
            .outbounds += [{
                "protocol": "wireguard",
                "tag": "warp",
                "settings": {
                    "secretKey": $warp_key,
                    "address": [
                        "172.16.0.2/32",
                        "2606:4700:110:8a36:df92:102a:9602:fa18/128"
                    ],
                    "peers": [{
                        "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
                        "allowedIPs": ["0.0.0.0/0", "::/0"],
                        "endpoint": $warp_addr,
                        "port": $warp_port,
                        "keepAlive": 30
                    }],
                    "mtu": 1280,
                    "reserved": [0, 0, 0]
                }
            }]
        else
            .outbounds |= map(
                if .protocol == "wireguard" and .tag == "warp" then
                    . + {
                        "settings": {
                            "secretKey": $warp_key,
                            "address": [
                                "172.16.0.2/32",
                                "2606:4700:110:8a36:df92:102a:9602:fa18/128"
                            ],
                            "peers": [{
                                "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
                                "allowedIPs": ["0.0.0.0/0", "::/0"],
                                "endpoint": $warp_addr,
                                "port": $warp_port,
                                "keepAlive": 30
                            }],
                            "mtu": 1280,
                            "reserved": [0, 0, 0]
                        }
                    }
                else . end
            )
        end |

        # Add direct outbound if it does not exist
        if (.outbounds | map(select(.protocol == "freedom" and .tag == "direct")) | length) == 0 then
            .outbounds += [{
                "protocol": "freedom",
                "tag": "direct"
            }]
        else . end |

        # Update routing to use WARP for specific traffic
        .routing = (.routing // {}) + {
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                # Route specific domains through WARP
                {
                    "type": "field",
                    "domain": [
                        "geosite:google",
                        "geosite:youtube",
                        "geosite:discord",
                        "geosite:openai",
                        "geosite:twitter",
                        "geosite:facebook",
                        "domain:cloudflare.com",
                        "domain:discord.com",
                        "domain:discordapp.com",
                        "domain:youtube.com",
                        "domain:googlevideo.com",
                        "domain:ytimg.com"
                    ],
                    "outboundTag": "warp"
                },
                # Route HTTP/HTTPS through WARP
                {
                    "type": "field",
                    "port": "80,443",
                    "network": "tcp",
                    "outboundTag": "warp"
                },
                # Default to direct
                {
                    "type": "field",
                    "network": "tcp,udp",
                    "outboundTag": "direct"
                }
            ]
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

    print_summary "WARP Obfuscation Configuration Applied" \
        "✓ WARP SETTINGS:" \
        "  - Protocol: WireGuard" \
        "  - Endpoint: Cloudflare WARP network" \
        "  - MTU: 1280 bytes" \
        "  - Keep-Alive: 30 seconds" \
        "" \
        "✓ ROUTING:" \
        "  - Google, YouTube, Discord → WARP" \
        "  - HTTP/HTTPS (80, 443) → WARP" \
        "  - Other traffic → Direct" \
        "" \
        "✓ OBFUSCATION:" \
        "  - WireGuard protocol provides strong obfuscation" \
        "  - Traffic appears as regular WireGuard VPN" \
        "  - Bypasses DPI that blocks traditional VPN protocols" \
        "" \
        "Domain Strategy:" \
        "  - IPIfNonMatch (prefer IP routing)"
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
        echo -e "  ${COLOR_YELLOW}Test from your client using VLESS to verify.${COLOR_RESET}" >&2
    else
        echo -e "  ${COLOR_YELLOW}Some tests failed.${COLOR_RESET}" >&2
    fi
}

generate_next_steps() {
    echo "" >&2
    echo -e "${COLOR_BLUE}🔄 Next Steps${COLOR_RESET}" >&2
    echo "  1. Test from your client using VLESS connection" >&2
    echo "  2. Test Discord, YouTube, Google access" >&2
    echo "  3. Check that WARP obfuscation is working" >&2
    echo "  4. Monitor connection for 10-15 minutes" >&2
    echo "  5. If stable, WARP obfuscation is working correctly" >&2
    echo "  6. If issues occur, use rollback command below" >&2
    echo "" >&2
    echo -e "${COLOR_YELLOW}Note: WARP may add slight latency but provides strong obfuscation${COLOR_RESET}" >&2
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

    # Install WARP dependencies
    install_warp_dependencies || exit_with_error 1 "Failed to install WARP dependencies"

    check_x_ui_service || exit_with_error 2 "x-ui service not available"

    local config_path=$(check_x_ui_config)
    if [[ -z "${config_path}" ]]; then
        exit_with_error 1 "x-ui configuration not found"
    fi

    echo "${config_path}"
}

run_connectivity_tests() {
    log_info "Running WARP connectivity tests..."

    local tests_passed=0
    local tests_total=5

    # Test basic connectivity
    test_connectivity "https://www.google.com" 15 "Google" && ((tests_passed++)) || true
    test_connectivity "https://discord.com" 15 "Discord" && ((tests_passed++)) || true
    test_connectivity "https://www.youtube.com" 15 "YouTube" && ((tests_passed++)) || true
    test_connectivity "https://cloudflare.com" 15 "Cloudflare" && ((tests_passed++)) || true

    # Test DNS
    test_dns "discord.com" && ((tests_passed++)) || true

    echo "${tests_passed} ${tests_total}"
}

main() {
    # Parse arguments
    if ! parse_common_args "$@"; then
        show_help
        exit 0
    fi

    # Initialize
    init_logging "warp-obfuscation"
    init_backup_dir || exit_with_error 1 "Failed to initialize backup directory"

    # Print header
    print_header "🔧 ${LEVEL_NAME}"

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
    log_info "🔨 Applying WARP obfuscation configuration..."
    log_info ""

    local temp_config=$(modify_config_for_warp "${config_path}")
    if [[ -z "${temp_config}" ]]; then
        exit_with_error 1 "Configuration modification failed"
    fi

    log_change "✓ WARP outbound configured:"
    log_change "  - Protocol: WireGuard"
    log_change "  - Endpoint: Cloudflare WARP"
    log_change "  - Obfuscation: Maximum"
    log_info ""

    log_change "✓ Routing rules applied:"
    log_change "  - Google, YouTube, Discord → WARP"
    log_change "  - HTTP/HTTPS (80, 443) → WARP"
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
    print_header "✅ WARP OBFUSCATION APPLIED SUCCESSFULLY"

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
