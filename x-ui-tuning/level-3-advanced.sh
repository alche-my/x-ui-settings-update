#!/bin/bash

################################################################################
# Level 3: Advanced DPI Bypass Script для RU → Non-RU каскада
#
# Description: Настраивает DPI bypass на ИСХОДЯЩЕМ (outbound) соединении
#              от RU VPS к Non-RU VPS с автоматическим подбором стратегий
#
# Usage: ./level-3-advanced.sh --method [xray-fragment|byedpi|zapret] --non-ru-ip IP [OPTIONS]
#
# Options:
#   --method METHOD         Метод DPI bypass (xray-fragment/byedpi/zapret)
#   --non-ru-ip IP          IP адрес вашего Non-RU VPS
#   --non-ru-port PORT      Порт Non-RU VPS (default: 443)
#   --auto-strategy         Включить автоматический подбор стратегий
#   --test-only             Только протестировать соединение
#   --dry-run               Показать изменения без применения
#   --verbose               Подробный вывод
################################################################################

set -euo pipefail

# ============================================
# Global Variables
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEVEL=3
LEVEL_NAME="Advanced DPI Bypass (RU → Non-RU)"

# Source common functions
if [[ -f "${SCRIPT_DIR}/common-functions.sh" ]]; then
    source "${SCRIPT_DIR}/common-functions.sh"
else
    echo "Error: common-functions.sh not found"
    exit 1
fi

# Level 3 specific variables
METHOD=""
NON_RU_IP=""
NON_RU_PORT=443
AUTO_STRATEGY=false
TEST_ONLY=false

# Paths
STRATEGY_DB="/opt/dpi-strategies.json"
HEALTH_CHECK_SCRIPT="/opt/health-check.sh"
AUTO_SELECTOR_SCRIPT="/opt/auto-strategy-selector.sh"
CURRENT_STRATEGY_FILE="/var/run/current-dpi-strategy"

# ByeDPI specific
BYEDPI_BIN="/usr/local/bin/byedpi"
BYEDPI_SERVICE="/etc/systemd/system/byedpi.service"

# Zapret specific
ZAPRET_DIR="/opt/zapret"

# ============================================
# Parse Arguments
# ============================================

parse_level3_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --method)
                METHOD="$2"
                shift 2
                ;;
            --non-ru-ip)
                NON_RU_IP="$2"
                shift 2
                ;;
            --non-ru-port)
                NON_RU_PORT="$2"
                shift 2
                ;;
            --auto-strategy)
                AUTO_STRATEGY=true
                shift
                ;;
            --test-only)
                TEST_ONLY=true
                shift
                ;;
            *)
                # Pass to common args parser
                shift
                ;;
        esac
    done

    # Validate required args
    if [[ -z "$METHOD" ]] && [[ "$TEST_ONLY" == "false" ]]; then
        log_error "Метод DPI bypass не указан. Используйте --method [xray-fragment|byedpi|zapret]"
        exit 1
    fi

    if [[ -z "$NON_RU_IP" ]]; then
        log_error "IP адрес Non-RU VPS не указан. Используйте --non-ru-ip IP"
        exit 1
    fi

    # Validate method
    if [[ -n "$METHOD" ]] && [[ ! "$METHOD" =~ ^(xray-fragment|byedpi|zapret)$ ]]; then
        log_error "Неверный метод: $METHOD. Допустимые: xray-fragment, byedpi, zapret"
        exit 1
    fi
}

# ============================================
# Connection Testing
# ============================================

test_connection_to_non_ru() {
    local ip=$1
    local port=$2
    local timeout=5

    log_info "Тестирование соединения к $ip:$port..."

    if timeout $timeout bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null; then
        log_success "Соединение успешно установлено"
        return 0
    else
        log_error "Не удалось подключиться к $ip:$port"
        return 1
    fi
}

# ============================================
# Strategy Database
# ============================================

create_strategy_database() {
    log_info "Создание базы стратегий DPI bypass..."

    cat > "$STRATEGY_DB" <<'EOF'
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
EOF

    log_success "База стратегий создана: $STRATEGY_DB"
}

# Get strategy by priority
get_strategy_by_priority() {
    local priority=$1

    if [[ ! -f "$STRATEGY_DB" ]]; then
        log_error "База стратегий не найдена"
        return 1
    fi

    jq -r ".strategies[] | select(.priority == $priority)" "$STRATEGY_DB"
}

# Get current strategy priority
get_current_strategy_priority() {
    if [[ -f "$CURRENT_STRATEGY_FILE" ]]; then
        cat "$CURRENT_STRATEGY_FILE"
    else
        echo "1"  # Default to first strategy
    fi
}

# Set current strategy priority
set_current_strategy_priority() {
    local priority=$1
    echo "$priority" > "$CURRENT_STRATEGY_FILE"
}

# ============================================
# Xray Fragment Implementation
# ============================================

apply_xray_fragment() {
    local config_path=$1
    local strategy=$2

    log_info "Применение Xray Fragment стратегии..."

    # Parse strategy config
    local packets=$(echo "$strategy" | jq -r '.config.packets')
    local length=$(echo "$strategy" | jq -r '.config.length')
    local interval=$(echo "$strategy" | jq -r '.config.interval')
    local strategy_name=$(echo "$strategy" | jq -r '.name')

    log_info "Стратегия: $strategy_name"
    log_info "  packets: $packets"
    log_info "  length: $length"
    log_info "  interval: $interval"

    # Create temporary config
    local temp_file=$(mktemp)

    # Modify config with fragment outbound
    jq --arg non_ru_ip "$NON_RU_IP" \
       --arg non_ru_port "$NON_RU_PORT" \
       --arg packets "$packets" \
       --arg length "$length" \
       --arg interval "$interval" \
    '.outbounds += [
        {
            "tag": "fragment",
            "protocol": "freedom",
            "settings": {
                "fragment": {
                    "packets": $packets,
                    "length": $length,
                    "interval": $interval
                }
            },
            "streamSettings": {
                "sockopt": {
                    "tcpNoDelay": true
                }
            }
        }
    ] |
    # Найти первый VLESS outbound и добавить dialerProxy
    .outbounds |= map(
        if .protocol == "vless" and .tag != "fragment" then
            .streamSettings.sockopt.dialerProxy = "fragment" |
            .streamSettings.sockopt.tcpFastOpen = true |
            .streamSettings.sockopt.tcpKeepAliveInterval = 15
        else
            .
        end
    )' "$config_path" > "$temp_file"

    # Validate JSON
    if ! validate_json "$temp_file"; then
        rm -f "$temp_file"
        log_error "Ошибка генерации конфигурации"
        return 1
    fi

    echo "$temp_file"
}

# ============================================
# ByeDPI Implementation
# ============================================

install_byedpi() {
    log_info "Установка ByeDPI..."

    # Check if already installed
    if [[ -f "$BYEDPI_BIN" ]]; then
        log_warning "ByeDPI уже установлен"
        return 0
    fi

    # Download ByeDPI
    local byedpi_url="https://github.com/hufrea/byedpi/releases/latest/download/byedpi-linux-x86_64.tar.gz"
    local temp_dir=$(mktemp -d)

    cd "$temp_dir"
    curl -L -o byedpi.tar.gz "$byedpi_url" || {
        log_error "Не удалось скачать ByeDPI"
        return 1
    }

    tar -xzf byedpi.tar.gz
    mv ciadpi "$BYEDPI_BIN"
    chmod +x "$BYEDPI_BIN"

    cd - > /dev/null
    rm -rf "$temp_dir"

    log_success "ByeDPI установлен: $BYEDPI_BIN"
}

create_byedpi_service() {
    local strategy_params=$1

    log_info "Создание systemd сервиса для ByeDPI..."

    cat > "$BYEDPI_SERVICE" <<EOF
[Unit]
Description=ByeDPI SOCKS5 Proxy для DPI Bypass
After=network.target

[Service]
Type=simple
User=root
ExecStart=$BYEDPI_BIN --ip 127.0.0.1 --port 1080 $strategy_params
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable byedpi
    systemctl restart byedpi

    # Wait for service to start
    sleep 2

    if systemctl is-active --quiet byedpi; then
        log_success "ByeDPI сервис запущен"
    else
        log_error "Не удалось запустить ByeDPI сервис"
        return 1
    fi
}

apply_byedpi_proxy() {
    local config_path=$1

    log_info "Настройка Xray для использования ByeDPI SOCKS5 прокси..."

    local temp_file=$(mktemp)

    # Add SOCKS5 outbound and proxySettings
    jq '.outbounds += [
        {
            "tag": "byedpi-proxy",
            "protocol": "socks",
            "settings": {
                "servers": [{
                    "address": "127.0.0.1",
                    "port": 1080
                }]
            }
        }
    ] |
    # Add proxySettings to VLESS outbound
    .outbounds |= map(
        if .protocol == "vless" and .tag != "byedpi-proxy" then
            .proxySettings = {"tag": "byedpi-proxy"}
        else
            .
        end
    )' "$config_path" > "$temp_file"

    if ! validate_json "$temp_file"; then
        rm -f "$temp_file"
        log_error "Ошибка генерации конфигурации"
        return 1
    fi

    echo "$temp_file"
}

# ============================================
# Zapret Implementation
# ============================================

install_zapret() {
    log_info "Установка Zapret..."

    if [[ -d "$ZAPRET_DIR" ]]; then
        log_warning "Zapret уже установлен в $ZAPRET_DIR"
        return 0
    fi

    # Install dependencies
    apt-get update
    apt-get install -y git iptables

    # Clone Zapret
    git clone https://github.com/bol-van/zapret.git "$ZAPRET_DIR"

    cd "$ZAPRET_DIR"
    ./install_easy.sh

    log_success "Zapret установлен"
}

configure_zapret() {
    local non_ru_ip=$1
    local strategy_params=$2

    log_info "Настройка Zapret для DPI bypass..."

    # Create config
    cat > "$ZAPRET_DIR/config" <<EOF
# Zapret configuration для обхода DPI на исходящем трафике к Non-RU VPS
MODE=nfqws
DISABLE_IPV6=1

# DPI bypass стратегии
NFQWS_OPT_DESYNC="$strategy_params"
NFQWS_OPT_DESYNC_HTTP="--dpi-desync=split2"
NFQWS_OPT_DESYNC_HTTPS="$strategy_params"
NFQWS_OPT_DESYNC_QUIC="--dpi-desync=fake --dpi-desync-repeats=6"
EOF

    # Create iptables rules for specific IP
    iptables -t mangle -D POSTROUTING -d "$non_ru_ip" -p tcp --dport "$NON_RU_PORT" -j NFQUEUE --queue-num 200 --queue-bypass 2>/dev/null || true

    iptables -t mangle -I POSTROUTING -d "$non_ru_ip" -p tcp --dport "$NON_RU_PORT" \
      -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:6 \
      -m mark ! --mark 0x40000000/0x40000000 \
      -j NFQUEUE --queue-num 200 --queue-bypass

    log_success "Zapret настроен для $non_ru_ip:$NON_RU_PORT"

    # Restart zapret service
    systemctl restart zapret || {
        log_error "Не удалось перезапустить Zapret"
        return 1
    }
}

# ============================================
# Health Check & Auto Strategy Selector
# ============================================

create_health_check_script() {
    log_info "Создание Health Check скрипта..."

    cat > "$HEALTH_CHECK_SCRIPT" <<EOF
#!/bin/bash
################################################################################
# Health Check для RU → Non-RU VPS соединения
################################################################################

NON_RU_IP="$NON_RU_IP"
NON_RU_PORT=$NON_RU_PORT
TIMEOUT=5
LOG_FILE="/var/log/dpi-health-check.log"

check_connection() {
    local ip=\$1
    local port=\$2
    local timeout=\$3

    if timeout \$timeout bash -c "echo >/dev/tcp/\$ip/\$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

main() {
    echo "[\$(date)] Testing connection to \$NON_RU_IP:\$NON_RU_PORT" | tee -a \$LOG_FILE

    if check_connection \$NON_RU_IP \$NON_RU_PORT \$TIMEOUT; then
        echo "[\$(date)] ✓ Connection successful" | tee -a \$LOG_FILE
        exit 0
    else
        echo "[\$(date)] ✗ Connection failed" | tee -a \$LOG_FILE

        # Trigger strategy switch
        if [[ -f "$AUTO_SELECTOR_SCRIPT" ]]; then
            $AUTO_SELECTOR_SCRIPT switch-next
        fi

        exit 1
    fi
}

main
EOF

    chmod +x "$HEALTH_CHECK_SCRIPT"
    log_success "Health Check скрипт создан: $HEALTH_CHECK_SCRIPT"
}

create_auto_strategy_selector() {
    log_info "Создание Auto Strategy Selector..."

    cat > "$AUTO_SELECTOR_SCRIPT" <<'EOFSCRIPT'
#!/bin/bash
################################################################################
# Auto Strategy Selector - автоматическое переключение стратегий DPI bypass
################################################################################

STRATEGY_DB="/opt/dpi-strategies.json"
CURRENT_STRATEGY_FILE="/var/run/current-dpi-strategy"
LEVEL3_SCRIPT="/root/x-ui-settings-update/x-ui-tuning/level-3-advanced.sh"
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
        echo "Достигнут последний стратегий, возврат к первой"
        next_priority=1
    fi

    echo "Переключение со стратегии #$current_priority на #$next_priority"

    # Reapply Level 3 with new strategy
    $LEVEL3_SCRIPT --method xray-fragment --non-ru-ip "$NON_RU_IP" --strategy-priority $next_priority

    set_current_priority $next_priority
}

case "${1:-}" in
    switch-next)
        switch_to_next_strategy
        ;;
    *)
        echo "Usage: $0 switch-next"
        exit 1
        ;;
esac
EOFSCRIPT

    chmod +x "$AUTO_SELECTOR_SCRIPT"
    log_success "Auto Strategy Selector создан: $AUTO_SELECTOR_SCRIPT"
}

setup_health_check_cron() {
    log_info "Настройка cron задачи для Health Check..."

    # Remove old cron if exists
    crontab -l 2>/dev/null | grep -v "$HEALTH_CHECK_SCRIPT" | crontab - 2>/dev/null || true

    # Add new cron (every 5 minutes)
    (crontab -l 2>/dev/null; echo "*/5 * * * * $HEALTH_CHECK_SCRIPT") | crontab -

    log_success "Cron задача настроена (каждые 5 минут)"
}

# ============================================
# Main Application Logic
# ============================================

apply_level3_config() {
    local config_path=$1
    local temp_config=""

    case "$METHOD" in
        xray-fragment)
            log_info "Применение метода: Xray Fragment"

            # Get strategy
            local current_priority=$(get_current_strategy_priority)
            local strategy=$(get_strategy_by_priority "$current_priority")

            if [[ -z "$strategy" ]]; then
                log_error "Стратегия с приоритетом $current_priority не найдена"
                return 1
            fi

            temp_config=$(apply_xray_fragment "$config_path" "$strategy")
            ;;

        byedpi)
            log_info "Применение метода: ByeDPI SOCKS5"

            install_byedpi || return 1

            # Default ByeDPI params (can be made dynamic based on strategy)
            local byedpi_params="--disorder 1 --split 1 --auto=torst"
            create_byedpi_service "$byedpi_params" || return 1

            temp_config=$(apply_byedpi_proxy "$config_path")
            ;;

        zapret)
            log_info "Применение метода: Zapret nfqws"

            install_zapret || return 1

            # Default Zapret params
            local zapret_params="--dpi-desync=split2 --dpi-desync-split-pos=2"
            configure_zapret "$NON_RU_IP" "$zapret_params" || return 1

            # For Zapret, we don't modify Xray config
            temp_config=""
            ;;

        *)
            log_error "Неизвестный метод: $METHOD"
            return 1
            ;;
    esac

    echo "$temp_config"
}

main() {
    # Parse arguments
    parse_level3_args "$@"
    parse_common_args "$@"

    # Initialize
    init_logging "level-${LEVEL}"
    init_backup_dir || exit_with_error 1 "Failed to initialize backup directory"

    # Print header
    print_header "🚀 Level ${LEVEL}: ${LEVEL_NAME}"

    log_info "Метод: $METHOD"
    log_info "Non-RU VPS: $NON_RU_IP:$NON_RU_PORT"
    log_info "Auto Strategy: $AUTO_STRATEGY"

    # Test connection first
    if ! test_connection_to_non_ru "$NON_RU_IP" "$NON_RU_PORT"; then
        log_warning "Не удалось подключиться к Non-RU VPS. Продолжаем настройку для исправления..."
    fi

    if [[ "$TEST_ONLY" == "true" ]]; then
        log_info "Режим тестирования. Выход."
        exit 0
    fi

    # Preflight checks
    check_root || exit_with_error 4 "Root privileges required"
    install_dependencies_if_needed || exit_with_error 1 "Failed to install dependencies"
    check_x_ui_service || exit_with_error 2 "x-ui service not available"

    local config_path=$(check_x_ui_config)
    if [[ -z "${config_path}" ]]; then
        exit_with_error 1 "x-ui configuration not found"
    fi

    # Create strategy database
    create_strategy_database

    # Create backup
    log_info ""
    log_info "📦 Creating backup..."
    local backup_file=$(backup_config "${config_path}")
    if [[ -z "${backup_file}" ]]; then
        exit_with_error 1 "Backup failed"
    fi

    # Apply Level 3 configuration
    log_info ""
    log_info "🔨 Applying Level ${LEVEL} configuration..."

    local temp_config=$(apply_level3_config "$config_path")

    # For Zapret, skip config replacement (it works at iptables level)
    if [[ "$METHOD" != "zapret" ]] && [[ -n "$temp_config" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN: Would replace config"
            cat "$temp_config" | jq .
        else
            cp "$temp_config" "$config_path"
            rm -f "$temp_config"

            # Restart x-ui
            restart_x_ui_service
        fi
    fi

    # Setup auto strategy selector if enabled
    if [[ "$AUTO_STRATEGY" == "true" ]]; then
        log_info ""
        log_info "🤖 Настройка автоматического подбора стратегий..."

        create_health_check_script
        create_auto_strategy_selector
        setup_health_check_cron
    fi

    # Final test
    log_info ""
    log_info "🧪 Финальный тест соединения..."
    sleep 3

    if test_connection_to_non_ru "$NON_RU_IP" "$NON_RU_PORT"; then
        log_success "✅ Level 3 успешно применен!"
    else
        log_warning "⚠️ Соединение все еще не работает. Проверьте:"
        log_warning "  1. Firewall правила на Non-RU VPS"
        log_warning "  2. Правильность IP и порта"
        log_warning "  3. Логи: journalctl -u x-ui -f"

        if [[ "$AUTO_STRATEGY" == "true" ]]; then
            log_info "Auto Strategy включен - система автоматически попробует другие стратегии"
        fi
    fi

    # Print summary
    log_info ""
    print_summary "Level 3 Configuration Summary" \
        "Method: $METHOD" \
        "Target: $NON_RU_IP:$NON_RU_PORT" \
        "Auto Strategy: $AUTO_STRATEGY" \
        "Health Check: $([ "$AUTO_STRATEGY" == "true" ] && echo "Enabled (every 5 min)" || echo "Disabled")" \
        "Backup: $backup_file"

    log_info ""
    log_info "📖 Документация: $SCRIPT_DIR/LEVEL-3-ADVANCED.md"
    log_info "🔄 Rollback: ./rollback.sh $backup_file"

    if [[ "$AUTO_STRATEGY" == "true" ]]; then
        log_info "🤖 Manual strategy switch: $AUTO_SELECTOR_SCRIPT switch-next"
        log_info "📊 Health check logs: tail -f /var/log/dpi-health-check.log"
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
