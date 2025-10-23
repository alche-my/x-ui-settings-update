#!/bin/bash

# ============================================
# Test Suite for 3x-ui DPI Bypass
# ============================================
# Version: 1.0
# Purpose: Comprehensive connectivity testing
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
# Test Configuration
# ============================================

# Test groups
LEVEL_1_TESTS=(
    "https://www.google.com:Google"
    "https://discord.com:Discord"
    "https://www.youtube.com:YouTube"
    "https://cloudflare.com:Cloudflare"
)

LEVEL_2_TESTS=(
    "https://discord.com/api/v9/gateway:Discord API"
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ:YouTube Video"
    "https://dnsleaktest.com:DNS Leak Test"
    "https://browserleaks.com:Browser Leaks"
)

LEVEL_3_TESTS=(
    "https://api.github.com:GitHub API"
    "https://registry.npmjs.org:NPM Registry"
)

# DNS test domains
DNS_TEST_DOMAINS=(
    "discord.com"
    "youtube.com"
    "cloudflare.com"
)

# ============================================
# Test Functions
# ============================================

run_http_test() {
    local url=$1
    local name=$2
    local timeout=${3:-10}

    local start_time=$(date +%s%3N)
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "${timeout}" \
        --max-time $((timeout * 2)) \
        -L \
        "${url}" 2>/dev/null || echo "000")
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    # Check if successful
    if [[ "${http_code}" =~ ^(200|301|302|304|403|405)$ ]]; then
        log_success "${name}: HTTP ${http_code} (${duration}ms)"
        return 0
    else
        log_error "${name}: HTTP ${http_code} (${duration}ms)"
        return 1
    fi
}

run_dns_test() {
    local domain=$1
    local timeout=${2:-5}

    local start_time=$(date +%s%3N)
    local ip=$(dig +short +time="${timeout}" "${domain}" @8.8.8.8 2>/dev/null | head -1)
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    if [[ -n "${ip}" ]] && [[ "${ip}" =~ ^[0-9.]+$ ]]; then
        log_success "${domain}: ${ip} (${duration}ms)"
        return 0
    else
        log_error "${domain}: DNS resolution failed (${duration}ms)"
        return 1
    fi
}

run_tcp_test() {
    local host=$1
    local port=$2
    local timeout=${3:-5}

    if timeout "${timeout}" bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null; then
        log_success "${host}:${port}: TCP connection successful"
        return 0
    else
        log_error "${host}:${port}: TCP connection failed"
        return 1
    fi
}

# ============================================
# Test Suites
# ============================================

run_basic_tests() {
    log_info "Running Level 1 tests (basic connectivity)..."
    echo ""

    local passed=0
    local total=${#LEVEL_1_TESTS[@]}

    for test_entry in "${LEVEL_1_TESTS[@]}"; do
        IFS=: read -r url name <<< "${test_entry}"
        if run_http_test "${url}" "${name}"; then
            ((passed++))
        fi
    done

    echo ""
    log_info "Level 1 tests: ${passed}/${total} passed"
    return 0
}

run_cdn_tests() {
    log_info "Running Level 2 tests (CDN and services)..."
    echo ""

    local passed=0
    local total=${#LEVEL_2_TESTS[@]}

    for test_entry in "${LEVEL_2_TESTS[@]}"; do
        IFS=: read -r url name <<< "${test_entry}"
        if run_http_test "${url}" "${name}" 15; then
            ((passed++))
        fi
    done

    echo ""
    log_info "Level 2 tests: ${passed}/${total} passed"
    return 0
}

run_advanced_tests() {
    log_info "Running Level 3 tests (advanced)..."
    echo ""

    local passed=0
    local total=${#LEVEL_3_TESTS[@]}

    for test_entry in "${LEVEL_3_TESTS[@]}"; do
        IFS=: read -r url name <<< "${test_entry}"
        if run_http_test "${url}" "${name}"; then
            ((passed++))
        fi
    done

    echo ""
    log_info "Level 3 tests: ${passed}/${total} passed"
    return 0
}

run_dns_tests() {
    log_info "Running DNS tests..."
    echo ""

    local passed=0
    local total=${#DNS_TEST_DOMAINS[@]}

    for domain in "${DNS_TEST_DOMAINS[@]}"; do
        if run_dns_test "${domain}"; then
            ((passed++))
        fi
    done

    echo ""
    log_info "DNS tests: ${passed}/${total} passed"
    return 0
}

run_tcp_tests() {
    log_info "Running TCP port tests..."
    echo ""

    local tests=(
        "discord.com:443"
        "www.youtube.com:443"
        "cloudflare.com:443"
    )

    local passed=0
    local total=${#tests[@]}

    for test_entry in "${tests[@]}"; do
        IFS=: read -r host port <<< "${test_entry}"
        if run_tcp_test "${host}" "${port}"; then
            ((passed++))
        fi
    done

    echo ""
    log_info "TCP tests: ${passed}/${total} passed"
    return 0
}

# ============================================
# Main Functions
# ============================================

show_help() {
    cat << EOF
Test Suite for 3x-ui DPI Bypass

Usage: $0 [OPTIONS] [TEST_LEVEL]

Test levels:
  1, basic      Run Level 1 tests (basic connectivity)
  2, cdn        Run Level 2 tests (CDN and services)
  3, advanced   Run Level 3 tests (advanced)
  dns           Run DNS resolution tests
  tcp           Run TCP port connectivity tests
  all           Run all tests (default)

Options:
  --verbose     Enable detailed debug output
  -h, --help    Show this help message

Examples:
  # Run all tests
  $0

  # Run only Level 1 tests
  $0 1

  # Run DNS tests with verbose output
  $0 --verbose dns

EOF
}

main() {
    local test_level="all"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            1|basic)
                test_level="basic"
                shift
                ;;
            2|cdn)
                test_level="cdn"
                shift
                ;;
            3|advanced)
                test_level="advanced"
                shift
                ;;
            dns)
                test_level="dns"
                shift
                ;;
            tcp)
                test_level="tcp"
                shift
                ;;
            all)
                test_level="all"
                shift
                ;;
            *)
                log_warning "Unknown option: $1"
                shift
                ;;
        esac
    done

    # Initialize
    init_logging "test-suite"

    print_header "🧪 3x-ui DPI Bypass Test Suite"

    log_info "Test level: ${test_level}"
    log_info "Started at: $(date)"
    echo ""

    # Run tests based on level
    case "${test_level}" in
        basic)
            run_basic_tests
            ;;
        cdn)
            run_cdn_tests
            ;;
        advanced)
            run_advanced_tests
            ;;
        dns)
            run_dns_tests
            ;;
        tcp)
            run_tcp_tests
            ;;
        all)
            run_basic_tests
            echo ""
            run_cdn_tests
            echo ""
            run_advanced_tests
            echo ""
            run_dns_tests
            echo ""
            run_tcp_tests
            ;;
    esac

    print_footer

    log_info "Completed at: $(date)"
}

# ============================================
# Script Entry Point
# ============================================

main "$@"
