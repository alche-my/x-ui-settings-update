#!/bin/bash

# ============================================
# Level 2: CDN Bypass Configuration
# ============================================
# Version: 1.0
# Purpose: Configure CDN bypass for 3x-ui (VLESS+Reality)
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

LEVEL="2"
LEVEL_NAME="CDN Bypass (Cloudflare, Discord, YouTube)"

# Cloudflare domains file
CLOUDFLARE_DOMAINS_FILE="${SCRIPT_DIR}/configs/cloudflare-domains.txt"

# ============================================
# Help Text
# ============================================

show_help() {
    cat << EOF
Level 2: CDN Bypass Configuration

Usage: $0 [OPTIONS]

This script configures CDN bypass for 3x-ui server running VLESS+Reality.
It includes ALL Level 1 settings PLUS additional optimizations for Cloudflare,
Discord voice, and YouTube video streaming.

Changes applied (cumulative with Level 1):

  FROM LEVEL 1:
  - Fragment settings for TLS Client Hello (100-200 bytes, 10-20ms interval)
  - TCP Fast Open for reduced latency
  - TCP Keep-Alive optimization
  - Packet marking for system routing
  - Basic routing rules for HTTP/HTTPS (ports 80, 443)

  NEW IN LEVEL 2:
  - Cloudflare special ports routing (2053, 2083, 2087, 2096, 8443)
  - Cloudflare domain-specific routing (~30 domains)
  - Discord UDP voice ports optimization (19294-19344)
  - More aggressive fragmentation for CDN traffic (50-150 bytes)
  - YouTube video optimization

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
  - Level 2 is CUMULATIVE: it includes all Level 1 settings
  - To return to Level 1 only: rollback to backup before Level 2, then re-run level-1
  - Test Discord voice and YouTube after applying

For more information, see README.md

EOF
}

# ============================================
# Configuration Modification Functions
# ============================================

load_cloudflare_domains() {
    local domains_file=$1
    local domains=()

    if [[ ! -f "${domains_file}" ]]; then
        log_warning "Cloudflare domains file not found: ${domains_file}"
        return 1
    fi

    # Read domains from file, skip comments and empty lines
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "${line}" =~ ^#.*$ ]] && continue
        [[ -z "${line}" ]] && continue

        # Add domain with "domain:" prefix for Xray routing
        domains+=("domain:${line}")
    done < "${domains_file}"

    if [[ ${#domains[@]} -eq 0 ]]; then
        log_warning "No domains loaded from ${domains_file}"
        return 1
    fi

    log_debug "Loaded ${#domains[@]} Cloudflare domains"

    # Output as JSON array for jq
    printf '%s\n' "${domains[@]}" | jq -R . | jq -s .
}

modify_outbound_config() {
    local config_file=$1
    local temp_file="${config_file}.level2.tmp"

    log_info "Modifying outbound configuration for Level 2..."

    # Load Cloudflare domains
    local cloudflare_domains_json=$(load_cloudflare_domains "${CLOUDFLARE_DOMAINS_FILE}")
    if [[ -z "${cloudflare_domains_json}" ]]; then
        log_error "Failed to load Cloudflare domains"
        return 1
    fi

    log_debug "Cloudflare domains JSON prepared"

    # Read current config
    local config_json=$(cat "${config_file}")

    # Build the modified configuration using jq
    # Level 2 includes ALL Level 1 settings PLUS Level 2 additions
    local modified_config=$(echo "${config_json}" | jq --argjson cf_domains "${cloudflare_domains_json}" '
        # Ensure outbounds array exists
        if .outbounds == null then .outbounds = [] else . end |

        # Find or create freedom outbound (Level 1 settings)
        if (.outbounds | map(select(.protocol == "freedom" and .tag == "direct")) | length) == 0 then
            .outbounds += [{
                "protocol": "freedom",
                "tag": "direct",
                "settings": {}
            }]
        else . end |

        # Modify freedom outbound with Level 1 + Level 2 settings
        .outbounds |= map(
            if .protocol == "freedom" and .tag == "direct" then
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

        # Add CDN-optimized outbound (Level 2 - more aggressive fragmentation)
        if (.outbounds | map(select(.protocol == "freedom" and .tag == "cdn-direct")) | length) == 0 then
            .outbounds += [{
                "protocol": "freedom",
                "tag": "cdn-direct",
                "settings": {
                    "domainStrategy": "UseIP",
                    "fragment": {
                        "packets": "tlshello",
                        "length": "50-150",
                        "interval": "5-15"
                    }
                },
                "streamSettings": {
                    "sockopt": {
                        "tcpFastOpen": true,
                        "tcpKeepAliveInterval": 15,
                        "mark": 255
                    }
                }
            }]
        else
            .outbounds |= map(
                if .protocol == "freedom" and .tag == "cdn-direct" then
                    . + {
                        "settings": {
                            "domainStrategy": "UseIP",
                            "fragment": {
                                "packets": "tlshello",
                                "length": "50-150",
                                "interval": "5-15"
                            }
                        },
                        "streamSettings": {
                            "sockopt": {
                                "tcpFastOpen": true,
                                "tcpKeepAliveInterval": 15,
                                "mark": 255
                            }
                        }
                    }
                else . end
            )
        end |

        # Add Discord UDP outbound (Level 2)
        if (.outbounds | map(select(.protocol == "freedom" and .tag == "discord-udp")) | length) == 0 then
            .outbounds += [{
                "protocol": "freedom",
                "tag": "discord-udp",
                "settings": {
                    "domainStrategy": "UseIP"
                },
                "streamSettings": {
                    "sockopt": {
                        "mark": 255
                    }
                }
            }]
        else
            .outbounds |= map(
                if .protocol == "freedom" and .tag == "discord-udp" then
                    . + {
                        "settings": {
                            "domainStrategy": "UseIP"
                        },
                        "streamSettings": {
                            "sockopt": {
                                "mark": 255
                            }
                        }
                    }
                else . end
            )
        end |

        # Ensure blackhole outbound exists
        if (.outbounds | map(select(.protocol == "blackhole")) | length) == 0 then
            .outbounds += [{
                "protocol": "blackhole",
                "tag": "block"
            }]
        else . end |

        # Add/update routing configuration (Level 1 + Level 2 rules)
        .routing = (.routing // {}) + {
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                # Level 1: Basic HTTP/HTTPS
                {
                    "type": "field",
                    "port": "80,443",
                    "network": "tcp",
                    "outboundTag": "direct"
                },
                # Level 2: Cloudflare special ports
                {
                    "type": "field",
                    "port": "2053,2083,2087,2096,8443",
                    "network": "tcp",
                    "outboundTag": "cdn-direct"
                },
                # Level 2: Cloudflare domains
                {
                    "type": "field",
                    "domain": $cf_domains,
                    "outboundTag": "cdn-direct"
                },
                # Level 2: Discord UDP voice ports
                {
                    "type": "field",
                    "port": "19294-19344",
                    "network": "udp",
                    "outboundTag": "discord-udp"
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

    print_summary "Configuration Changes Applied (Level 1 + Level 2)" \
        "✓ LEVEL 1 SETTINGS (INCLUDED):" \
        "  - Fragment: 100-200 bytes, 10-20ms interval" \
        "  - TCP Fast Open: ENABLED" \
        "  - Keep-Alive: 30 seconds" \
        "  - Ports: 80, 443 (HTTP/HTTPS)" \
        "" \
        "✓ LEVEL 2 ADDITIONS (NEW):" \
        "  CDN-Optimized Fragmentation:" \
        "    - Fragment: 50-150 bytes (more aggressive)" \
        "    - Interval: 5-15ms (faster)" \
        "    - Keep-Alive: 15 seconds" \
        "" \
        "  Cloudflare Special Ports:" \
        "    - 2053, 2083, 2087, 2096, 8443" \
        "    - Uses cdn-direct outbound" \
        "" \
        "  Cloudflare Domains:" \
        "    - ~30 Cloudflare domains routed" \
        "    - cloudflare.com, cloudflare.net, etc." \
        "" \
        "  Discord UDP Voice:" \
        "    - Ports: 19294-19344" \
        "    - Optimized for voice traffic" \
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
        echo -e "  ${COLOR_YELLOW}Test from your client using v2Ray to verify.${COLOR_RESET}" >&2
    else
        echo -e "  ${COLOR_YELLOW}Some tests failed.${COLOR_RESET}" >&2
    fi
}

generate_next_steps() {
    echo "" >&2
    echo -e "${COLOR_BLUE}🔄 Next Steps${COLOR_RESET}" >&2
    echo "  1. Test from your client using v2Ray with your VLESS key" >&2
    echo "  2. IMPORTANT: Test Discord voice calls (UDP 19294-19344)" >&2
    echo "  3. IMPORTANT: Test YouTube video playback" >&2
    echo "  4. Check Cloudflare services (cloudflare.com, 1.1.1.1)" >&2
    echo "  5. If stable after 10-15 minutes, Level 2 is working" >&2
    echo "  6. If issues occur, use rollback command below" >&2
    echo "" >&2
    echo -e "${COLOR_YELLOW}Note: Level 2 is more aggressive and may take longer to stabilize${COLOR_RESET}" >&2
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

    # Check Cloudflare domains file
    if [[ ! -f "${CLOUDFLARE_DOMAINS_FILE}" ]]; then
        log_error "Cloudflare domains file not found: ${CLOUDFLARE_DOMAINS_FILE}"
        exit_with_error 1 "Missing configuration file"
    fi
    log_success "Cloudflare domains file found: ${CLOUDFLARE_DOMAINS_FILE}"

    local config_path=$(check_x_ui_config)
    if [[ -z "${config_path}" ]]; then
        exit_with_error 1 "x-ui configuration not found"
    fi

    echo "${config_path}"
}

run_connectivity_tests() {
    log_info "Running Level 2 connectivity tests..."

    local tests_passed=0
    local tests_total=6

    # Test basic connectivity (Level 1)
    test_connectivity "https://www.google.com" 10 "Google" && ((tests_passed++)) || true

    # Test CDN services (Level 2)
    test_connectivity "https://cloudflare.com" 10 "Cloudflare" && ((tests_passed++)) || true
    test_connectivity "https://discord.com" 10 "Discord" && ((tests_passed++)) || true
    test_connectivity "https://www.youtube.com" 10 "YouTube" && ((tests_passed++)) || true

    # Test DNS
    test_dns "discord.com" && ((tests_passed++)) || true
    test_dns "cloudflare.com" && ((tests_passed++)) || true

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

    log_change "✓ Level 1 settings applied (cumulative):"
    log_change "  - Fragment: 100-200 bytes, 10-20ms"
    log_change "  - TCP Fast Open, Keep-Alive: 30s"
    log_change "  - Ports: 80, 443"
    log_info ""

    log_change "✓ Level 2 CDN optimizations added:"
    log_change "  - CDN fragment: 50-150 bytes, 5-15ms (aggressive)"
    log_change "  - Cloudflare ports: 2053, 2083, 2087, 2096, 8443"
    log_change "  - Cloudflare domains: ~30 domains"
    log_change "  - Discord UDP: 19294-19344"
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
