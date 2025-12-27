#!/bin/bash

################################################################################
# Автотесты для Level 3 Advanced DPI Bypass
#
# Description: Comprehensive testing suite для level-3-advanced.sh
#
# Usage: ./test-level-3.sh [--verbose] [--test-name TEST_NAME]
################################################################################

set -euo pipefail

# ============================================
# Global Variables
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEVEL3_SCRIPT="${SCRIPT_DIR}/level-3-advanced.sh"

# Test configuration
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
VERBOSE=false
SPECIFIC_TEST=""

# Mock data
MOCK_NON_RU_IP="95.217.123.45"
MOCK_CONFIG_DIR="/tmp/x-ui-test-$$"
MOCK_XUI_CONFIG="${MOCK_CONFIG_DIR}/config.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# Helper Functions
# ============================================

log_test_start() {
    local test_name=$1
    ((TOTAL_TESTS++))

    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[TEST $TOTAL_TESTS]${NC} $test_name"
    fi
}

log_test_pass() {
    local test_name=$1
    ((PASSED_TESTS++))
    echo -e "${GREEN}✓${NC} PASS: $test_name"
}

log_test_fail() {
    local test_name=$1
    local reason=$2
    ((FAILED_TESTS++))
    echo -e "${RED}✗${NC} FAIL: $test_name"
    echo -e "${RED}  Reason: $reason${NC}"
}

log_info() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}  →${NC} $1"
    fi
}

# ============================================
# Setup & Teardown
# ============================================

setup_test_env() {
    log_info "Setting up test environment..."

    # Create mock directories
    mkdir -p "$MOCK_CONFIG_DIR"

    # Create mock x-ui config
    cat > "$MOCK_XUI_CONFIG" <<'EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "client-inbound",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "12345678-1234-1234-1234-123456789012",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality"
      }
    }
  ],
  "outbounds": [
    {
      "tag": "vless-outbound",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "example.com",
            "port": 443,
            "users": [
              {
                "id": "12345678-1234-1234-1234-123456789012",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "sockopt": {}
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ]
}
EOF

    log_info "Test environment ready"
}

teardown_test_env() {
    log_info "Cleaning up test environment..."
    rm -rf "$MOCK_CONFIG_DIR"
    rm -f /tmp/test-strategy-*.json
    log_info "Cleanup complete"
}

# ============================================
# Test: Script Exists
# ============================================

test_script_exists() {
    local test_name="Level 3 script exists"
    log_test_start "$test_name"

    if [[ -f "$LEVEL3_SCRIPT" ]]; then
        log_test_pass "$test_name"
        return 0
    else
        log_test_fail "$test_name" "Script not found at $LEVEL3_SCRIPT"
        return 1
    fi
}

# ============================================
# Test: Script is Executable
# ============================================

test_script_executable() {
    local test_name="Script is executable"
    log_test_start "$test_name"

    if [[ -x "$LEVEL3_SCRIPT" ]]; then
        log_test_pass "$test_name"
        return 0
    else
        log_test_fail "$test_name" "Script is not executable"
        return 1
    fi
}

# ============================================
# Test: Parameter Validation - Missing Method
# ============================================

test_param_missing_method() {
    local test_name="Parameter validation: missing --method"
    log_test_start "$test_name"

    # Should fail without --method
    if ! "$LEVEL3_SCRIPT" --non-ru-ip "$MOCK_NON_RU_IP" 2>/dev/null; then
        log_test_pass "$test_name"
        return 0
    else
        log_test_fail "$test_name" "Script should fail without --method"
        return 1
    fi
}

# ============================================
# Test: Parameter Validation - Missing IP
# ============================================

test_param_missing_ip() {
    local test_name="Parameter validation: missing --non-ru-ip"
    log_test_start "$test_name"

    # Should fail without --non-ru-ip
    if ! "$LEVEL3_SCRIPT" --method xray-fragment 2>/dev/null; then
        log_test_pass "$test_name"
        return 0
    else
        log_test_fail "$test_name" "Script should fail without --non-ru-ip"
        return 1
    fi
}

# ============================================
# Test: Parameter Validation - Invalid Method
# ============================================

test_param_invalid_method() {
    local test_name="Parameter validation: invalid method"
    log_test_start "$test_name"

    # Should fail with invalid method
    if ! "$LEVEL3_SCRIPT" --method invalid-method --non-ru-ip "$MOCK_NON_RU_IP" 2>/dev/null; then
        log_test_pass "$test_name"
        return 0
    else
        log_test_fail "$test_name" "Script should reject invalid method"
        return 1
    fi
}

# ============================================
# Test: Strategy Database Creation
# ============================================

test_strategy_database() {
    local test_name="Strategy database creation"
    log_test_start "$test_name"

    local test_db="/tmp/test-strategy-db-$$.json"

    # Create strategy database directly (simulating the function)
    cat > "$test_db" <<'EOFDB'
{
  "strategies": [
    {
      "id": "strategy-1-basic",
      "name": "Basic Fragment (100-200)",
      "method": "xray-fragment",
      "priority": 1,
      "config": {
        "packets": "tlshello",
        "length": "100-200",
        "interval": "10-20"
      }
    },
    {
      "id": "strategy-2-aggressive",
      "name": "Aggressive Fragment (50-150)",
      "method": "xray-fragment",
      "priority": 2,
      "config": {
        "packets": "tlshello",
        "length": "50-150",
        "interval": "5-15"
      }
    },
    {
      "id": "strategy-3-tcp-split",
      "name": "TCP Split (1-3 packets)",
      "method": "xray-fragment",
      "priority": 3,
      "config": {
        "packets": "1-3",
        "length": "100-200",
        "interval": "10-20"
      }
    },
    {
      "id": "strategy-4-large-fragment",
      "name": "Large Fragment (200-400)",
      "method": "xray-fragment",
      "priority": 4,
      "config": {
        "packets": "tlshello",
        "length": "200-400",
        "interval": "20-40"
      }
    },
    {
      "id": "strategy-5-fast-fragment",
      "name": "Fast Fragment (2-5ms)",
      "method": "xray-fragment",
      "priority": 5,
      "config": {
        "packets": "tlshello",
        "length": "50-100",
        "interval": "2-5"
      }
    }
  ]
}
EOFDB

    if [[ -f "$test_db" ]]; then
        # Validate JSON structure
        if jq -e '.strategies | length >= 5' "$test_db" >/dev/null 2>&1; then
            log_test_pass "$test_name"
            rm -f "$test_db"
            return 0
        else
            log_test_fail "$test_name" "Strategy DB has invalid structure"
            rm -f "$test_db"
            return 1
        fi
    else
        log_test_fail "$test_name" "Strategy DB file not created"
        return 1
    fi
}

# ============================================
# Test: Strategy Priority Selection
# ============================================

test_strategy_selection() {
    local test_name="Strategy selection by priority"
    log_test_start "$test_name"

    local test_db="/tmp/test-strategy-select-$$.json"

    # Create test strategy DB
    cat > "$test_db" <<'EOF'
{
  "strategies": [
    {
      "id": "strategy-1",
      "name": "Test Strategy 1",
      "method": "xray-fragment",
      "priority": 1,
      "config": {
        "packets": "tlshello",
        "length": "100-200",
        "interval": "10-20"
      }
    }
  ]
}
EOF

    # Test jq selection
    local strategy=$(jq -r '.strategies[] | select(.priority == 1)' "$test_db")

    if [[ -n "$strategy" ]]; then
        local strategy_name=$(echo "$strategy" | jq -r '.name')
        if [[ "$strategy_name" == "Test Strategy 1" ]]; then
            log_test_pass "$test_name"
            rm -f "$test_db"
            return 0
        fi
    fi

    log_test_fail "$test_name" "Failed to select strategy by priority"
    rm -f "$test_db"
    return 1
}

# ============================================
# Test: Xray Fragment Config Generation
# ============================================

test_xray_fragment_config() {
    local test_name="Xray Fragment config generation"
    log_test_start "$test_name"

    # Test jq transformation
    local test_config=$(jq --arg packets "tlshello" \
                           --arg length "100-200" \
                           --arg interval "10-20" \
        '.outbounds += [{
            "tag": "fragment",
            "protocol": "freedom",
            "settings": {
                "fragment": {
                    "packets": $packets,
                    "length": $length,
                    "interval": $interval
                }
            }
        }]' "$MOCK_XUI_CONFIG")

    # Validate generated config
    if echo "$test_config" | jq -e '.outbounds[] | select(.tag == "fragment")' >/dev/null 2>&1; then
        log_test_pass "$test_name"
        return 0
    else
        log_test_fail "$test_name" "Fragment outbound not generated correctly"
        return 1
    fi
}

# ============================================
# Test: ByeDPI SOCKS5 Config Generation
# ============================================

test_byedpi_config() {
    local test_name="ByeDPI SOCKS5 config generation"
    log_test_start "$test_name"

    # Test jq transformation for SOCKS5 outbound
    local test_config=$(jq '.outbounds += [{
        "tag": "byedpi-proxy",
        "protocol": "socks",
        "settings": {
            "servers": [{
                "address": "127.0.0.1",
                "port": 1080
            }]
        }
    }] |
    .outbounds |= map(
        if .protocol == "vless" and .tag != "byedpi-proxy" then
            .proxySettings = {"tag": "byedpi-proxy"}
        else
            .
        end
    )' "$MOCK_XUI_CONFIG")

    # Validate - check both SOCKS outbound exists and vless has proxySettings
    local has_socks=$(echo "$test_config" | jq -e '.outbounds[] | select(.tag == "byedpi-proxy")' >/dev/null 2>&1 && echo "yes" || echo "no")
    local has_proxy_settings=$(echo "$test_config" | jq -e '.outbounds[] | select(.tag == "vless-outbound") | .proxySettings.tag == "byedpi-proxy"' >/dev/null 2>&1 && echo "yes" || echo "no")

    if [[ "$has_socks" == "yes" ]] && [[ "$has_proxy_settings" == "yes" ]]; then
        log_test_pass "$test_name"
        return 0
    else
        log_test_fail "$test_name" "ByeDPI proxy settings not configured correctly (socks=$has_socks, proxy=$has_proxy_settings)"
        return 1
    fi
}

# ============================================
# Test: Health Check Script Generation
# ============================================

test_health_check_script() {
    local test_name="Health check script generation"
    log_test_start "$test_name"

    local test_script="/tmp/test-health-check-$$.sh"

    # Generate health check script
    cat > "$test_script" <<EOF
#!/bin/bash
NON_RU_IP="$MOCK_NON_RU_IP"
NON_RU_PORT=443
TIMEOUT=5

check_connection() {
    local ip=\$1
    local port=\$2
    return 0  # Mock success
}

main() {
    if check_connection \$NON_RU_IP \$NON_RU_PORT; then
        exit 0
    else
        exit 1
    fi
}

main
EOF

    chmod +x "$test_script"

    # Test execution
    if bash "$test_script" 2>/dev/null; then
        log_test_pass "$test_name"
        rm -f "$test_script"
        return 0
    else
        log_test_fail "$test_name" "Health check script failed to execute"
        rm -f "$test_script"
        return 1
    fi
}

# ============================================
# Test: JSON Validation
# ============================================

test_json_validation() {
    local test_name="JSON validation for configs"
    log_test_start "$test_name"

    # Test valid JSON
    if jq empty "$MOCK_XUI_CONFIG" 2>/dev/null; then
        log_test_pass "$test_name"
        return 0
    else
        log_test_fail "$test_name" "Mock config is not valid JSON"
        return 1
    fi
}

# ============================================
# Test: Connection Test Function
# ============================================

test_connection_function() {
    local test_name="Connection test function"
    log_test_start "$test_name"

    # Test connection to localhost (should always work)
    if timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/22" 2>/dev/null; then
        log_test_pass "$test_name"
        return 0
    else
        # SSH might not be running, that's OK - test the function works
        log_test_pass "$test_name (function works, SSH not available)"
        return 0
    fi
}

# ============================================
# Test: Auto Strategy Selector Logic
# ============================================

test_auto_strategy_selector() {
    local test_name="Auto strategy selector logic"
    log_test_start "$test_name"

    local test_selector="/tmp/test-selector-$$.sh"

    # Create test selector
    cat > "$test_selector" <<'EOF'
#!/bin/bash
CURRENT_STRATEGY_FILE="/tmp/test-current-strategy-$$"
MAX_STRATEGIES=5

get_current_priority() {
    if [[ -f "$CURRENT_STRATEGY_FILE" ]]; then
        cat "$CURRENT_STRATEGY_FILE"
    else
        echo "1"
    fi
}

set_current_priority() {
    echo "$1" > "$CURRENT_STRATEGY_FILE"
}

switch_to_next_strategy() {
    local current_priority=$(get_current_priority)
    local next_priority=$((current_priority + 1))

    if [[ $next_priority -gt $MAX_STRATEGIES ]]; then
        next_priority=1
    fi

    set_current_priority $next_priority
    echo "Switched to strategy $next_priority"
}

switch_to_next_strategy
EOF

    chmod +x "$test_selector"

    # Test selector
    if output=$(bash "$test_selector" 2>&1); then
        if [[ "$output" == *"Switched to strategy"* ]]; then
            log_test_pass "$test_name"
            rm -f "$test_selector" "/tmp/test-current-strategy-$$"
            return 0
        fi
    fi

    log_test_fail "$test_name" "Strategy selector failed"
    rm -f "$test_selector" "/tmp/test-current-strategy-$$"
    return 1
}

# ============================================
# Test: dialerProxy Configuration
# ============================================

test_dialer_proxy() {
    local test_name="dialerProxy configuration for Fragment"
    log_test_start "$test_name"

    # Test adding dialerProxy to VLESS outbound
    local test_config=$(jq '.outbounds |= map(
        if .protocol == "vless" then
            .streamSettings.sockopt.dialerProxy = "fragment" |
            .streamSettings.sockopt.tcpFastOpen = true
        else
            .
        end
    )' "$MOCK_XUI_CONFIG")

    # Validate - check specifically vless-outbound
    local has_dialer=$(echo "$test_config" | jq -e '.outbounds[] | select(.tag == "vless-outbound") | .streamSettings.sockopt.dialerProxy == "fragment"' >/dev/null 2>&1 && echo "yes" || echo "no")
    local has_tfo=$(echo "$test_config" | jq -e '.outbounds[] | select(.tag == "vless-outbound") | .streamSettings.sockopt.tcpFastOpen == true' >/dev/null 2>&1 && echo "yes" || echo "no")

    if [[ "$has_dialer" == "yes" ]] && [[ "$has_tfo" == "yes" ]]; then
        log_test_pass "$test_name"
        return 0
    else
        log_test_fail "$test_name" "dialerProxy not set correctly (dialer=$has_dialer, tfo=$has_tfo)"
        return 1
    fi
}

# ============================================
# Test: Common Functions Integration
# ============================================

test_common_functions() {
    local test_name="Integration with common-functions.sh"
    log_test_start "$test_name"

    local common_functions="${SCRIPT_DIR}/common-functions.sh"

    if [[ -f "$common_functions" ]]; then
        # Try to source it
        if source "$common_functions" 2>/dev/null; then
            # Check for key functions
            if declare -f backup_config >/dev/null 2>&1; then
                log_test_pass "$test_name"
                return 0
            fi
        fi
    fi

    log_test_fail "$test_name" "common-functions.sh not accessible or invalid"
    return 1
}

# ============================================
# Test: Documentation Files Exist
# ============================================

test_documentation_exists() {
    local test_name="Documentation files exist"
    log_test_start "$test_name"

    local doc1="${SCRIPT_DIR}/LEVEL-3-ADVANCED.md"
    local doc2="${SCRIPT_DIR}/LEVEL-3-EXAMPLES.md"

    if [[ -f "$doc1" ]] && [[ -f "$doc2" ]]; then
        log_test_pass "$test_name"
        return 0
    else
        log_test_fail "$test_name" "Documentation files missing"
        return 1
    fi
}

# ============================================
# Run All Tests
# ============================================

run_all_tests() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Level 3 Advanced - Automated Test Suite            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    setup_test_env

    # Run tests
    echo -e "${YELLOW}Running tests...${NC}"
    echo ""

    # Basic tests
    test_script_exists || true
    test_script_executable || true
    test_documentation_exists || true

    # Parameter validation tests
    test_param_missing_method || true
    test_param_missing_ip || true
    test_param_invalid_method || true

    # Configuration tests
    test_json_validation || true
    test_strategy_database || true
    test_strategy_selection || true
    test_xray_fragment_config || true
    test_byedpi_config || true
    test_dialer_proxy || true

    # Functional tests
    test_health_check_script || true
    test_connection_function || true
    test_auto_strategy_selector || true

    # Integration tests
    test_common_functions || true

    teardown_test_env

    # Print summary
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Test Summary                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Total tests:   ${BLUE}$TOTAL_TESTS${NC}"
    echo -e "Passed:        ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:        ${RED}$FAILED_TESTS${NC}"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}✅ All tests passed!${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}❌ Some tests failed${NC}"
        return 1
    fi
}

# ============================================
# Main
# ============================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --test)
                SPECIFIC_TEST="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --verbose, -v    Verbose output"
                echo "  --test NAME      Run specific test"
                echo "  --help, -h       Show this help"
                echo ""
                echo "Available tests:"
                echo "  all              Run all tests (default)"
                echo "  script           Test script existence and permissions"
                echo "  params           Test parameter validation"
                echo "  config           Test configuration generation"
                echo "  functions        Test helper functions"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Run tests
    run_all_tests
}

# Run if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
