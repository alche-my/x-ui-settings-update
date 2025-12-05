#!/bin/bash

################################################################################
# Dokodemo-door Bridge Diagnostic Script
#
# Description: Comprehensive diagnostics for Dokodemo-door bridge setup
# Usage: sudo ./diagnose-dokodemo-bridge.sh
################################################################################

set -euo pipefail

################################################################################
# GLOBAL VARIABLES
################################################################################

SCRIPT_VERSION="1.0.0"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Status counters
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# Issues and recommendations
declare -a ISSUES=()
declare -a RECOMMENDATIONS=()

################################################################################
# UTILITY FUNCTIONS
################################################################################

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_header() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

add_issue() {
    ISSUES+=("$1")
}

add_recommendation() {
    RECOMMENDATIONS+=("$1")
}

################################################################################
# DIAGNOSTIC FUNCTIONS
################################################################################

# Check root privileges
check_root() {
    print_header "1. Проверка прав доступа"

    if [[ $EUID -eq 0 ]]; then
        print_success "Скрипт запущен с правами root"
    else
        print_error "Скрипт должен быть запущен с правами root"
        add_issue "Недостаточно прав для диагностики"
        add_recommendation "Запустите: sudo $0"
        return 1
    fi
}

# Check dependencies
check_dependencies() {
    print_header "2. Проверка зависимостей"

    local missing_deps=()

    for cmd in jq curl ss netstat ping nc traceroute; do
        if command -v "$cmd" &> /dev/null; then
            print_success "$cmd установлен"
        else
            print_warning "$cmd не установлен (опционально)"
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        add_recommendation "Установите недостающие пакеты: apt-get install -y ${missing_deps[*]}"
    fi
}

# Check system resources
check_system_resources() {
    print_header "3. Проверка системных ресурсов"

    # Disk space
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -lt 80 ]]; then
        print_success "Место на диске: ${disk_usage}% использовано"
    elif [[ $disk_usage -lt 90 ]]; then
        print_warning "Место на диске: ${disk_usage}% использовано"
    else
        print_error "Место на диске: ${disk_usage}% использовано (критично)"
        add_issue "Недостаточно места на диске"
        add_recommendation "Освободите место на диске"
    fi

    # Memory
    local mem_usage=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')
    if [[ $mem_usage -lt 80 ]]; then
        print_success "Использование памяти: ${mem_usage}%"
    else
        print_warning "Использование памяти: ${mem_usage}%"
    fi

    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)
    print_info "Load average: $load_avg"
}

# Check x-ui service
check_xui_service() {
    print_header "4. Проверка сервиса x-ui"

    # Check if x-ui is installed
    if [[ -d "/usr/local/x-ui" ]]; then
        print_success "x-ui установлен (/usr/local/x-ui)"
    else
        print_error "x-ui не установлен"
        add_issue "x-ui не найден"
        add_recommendation "Установите x-ui: bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)"
        return 1
    fi

    # Check service status
    if systemctl is-active --quiet x-ui; then
        print_success "Сервис x-ui активен"
    else
        print_error "Сервис x-ui не запущен"
        add_issue "x-ui сервис не работает"
        add_recommendation "Запустите: systemctl start x-ui"
        add_recommendation "Проверьте логи: journalctl -u x-ui -n 50"
        return 1
    fi

    # Check if enabled
    if systemctl is-enabled --quiet x-ui; then
        print_success "x-ui включен в автозапуск"
    else
        print_warning "x-ui не включен в автозапуск"
        add_recommendation "Включите автозапуск: systemctl enable x-ui"
    fi

    # Check Xray process
    if pgrep -x "xray-linux-amd64" > /dev/null || pgrep -f "xray" > /dev/null; then
        print_success "Процесс Xray запущен"
        local xray_pid=$(pgrep -x "xray-linux-amd64" || pgrep -f "xray" | head -1)
        print_info "PID Xray: $xray_pid"
    else
        print_error "Процесс Xray не найден"
        add_issue "Xray не запущен"
        add_recommendation "Перезапустите x-ui: systemctl restart x-ui"
    fi
}

# Check x-ui configuration file
check_xui_config() {
    print_header "5. Проверка конфигурации Xray"

    local config_file="/usr/local/x-ui/bin/config.json"

    if [[ ! -f "$config_file" ]]; then
        print_error "Файл конфигурации не найден: $config_file"
        add_issue "Отсутствует config.json"
        return 1
    fi

    print_success "Файл конфигурации найден"

    # Validate JSON
    if jq empty "$config_file" 2>/dev/null; then
        print_success "JSON конфигурация валидна"
    else
        print_error "JSON конфигурация содержит ошибки"
        add_issue "Невалидный JSON в config.json"
        add_recommendation "Восстановите из бэкапа: ls -la /usr/local/x-ui/bin/config.json.backup-*"
        return 1
    fi

    # Check DNS configuration
    local dns_servers=$(jq -r '.dns.servers[]?' "$config_file" 2>/dev/null)
    if [[ -n "$dns_servers" ]]; then
        print_success "DNS конфигурация найдена"
        echo -e "${CYAN}   Серверы:${NC}"
        echo "$dns_servers" | while read server; do
            echo "   - $server"
        done
    else
        print_warning "DNS не настроен"
        add_issue "Отсутствует DNS конфигурация"
        add_recommendation "Добавьте DNS вручную или запустите скрипт setup-dokodemo-bridge.sh заново"
    fi

    # Check inbounds count
    local inbound_count=$(jq '.inbounds | length' "$config_file" 2>/dev/null || echo "0")
    print_info "Всего inbound'ов: $inbound_count"

    # Check Dokodemo inbounds
    local dokodemo_count=$(jq '[.inbounds[] | select(.protocol=="dokodemo-door")] | length' "$config_file" 2>/dev/null || echo "0")

    if [[ $dokodemo_count -gt 0 ]]; then
        print_success "Найдено Dokodemo-door inbound'ов: $dokodemo_count"

        # Show Dokodemo details
        echo -e "${CYAN}   Детали Dokodemo inbound'ов:${NC}"
        jq -r '.inbounds[] | select(.protocol=="dokodemo-door") |
            "   • Порт \(.port) → \(.settings.address):\(.settings.port) [\(.tag)]"' \
            "$config_file" 2>/dev/null || print_warning "   Не удалось прочитать детали"
    else
        print_warning "Dokodemo-door inbound'ы не найдены в config.json"
        print_info "Проверяем базу данных x-ui..."
    fi

    # Check for duplicate inbounds
    local dup_check=$(jq '[.inbounds[] | select(.protocol=="dokodemo-door") | .tag] |
        group_by(.) | map(select(length > 1)) | length' "$config_file" 2>/dev/null || echo "0")

    if [[ $dup_check -gt 0 ]]; then
        print_error "Обнаружены дублирующиеся inbound'ы"
        add_issue "Дублирование inbound'ов в config.json"
        add_recommendation "Удалите дубликаты вручную через панель x-ui"
    fi
}

# Check x-ui database
check_xui_database() {
    print_header "6. Проверка базы данных x-ui"

    local db_file="/etc/x-ui/x-ui.db"

    if [[ ! -f "$db_file" ]]; then
        print_error "База данных не найдена: $db_file"
        add_issue "Отсутствует БД x-ui"
        return 1
    fi

    print_success "База данных найдена"

    # Check if sqlite3 is available
    if ! command -v sqlite3 &> /dev/null; then
        print_warning "sqlite3 не установлен, пропускаем проверку БД"
        add_recommendation "Установите sqlite3: apt-get install -y sqlite3"
        return 0
    fi

    # Count Dokodemo inbounds in DB
    local db_dokodemo_count=$(sqlite3 "$db_file" \
        "SELECT COUNT(*) FROM inbounds WHERE protocol='dokodemo-door';" 2>/dev/null || echo "0")

    if [[ $db_dokodemo_count -gt 0 ]]; then
        print_success "Dokodemo inbound'ов в БД: $db_dokodemo_count"

        # Show details with settings
        echo -e "${CYAN}   Детали из БД:${NC}"
        sqlite3 "$db_file" "SELECT id, remark, port, enable, settings FROM inbounds WHERE protocol='dokodemo-door';" 2>/dev/null | \
            while IFS='|' read -r id remark port enable settings; do
                local status="выключен"
                [[ "$enable" == "1" ]] && status="включен"

                # Parse settings JSON to extract target address and port
                local target_info=""
                if [[ -n "$settings" ]]; then
                    local target_addr=$(echo "$settings" | jq -r '.address // "N/A"' 2>/dev/null)
                    local target_port=$(echo "$settings" | jq -r '.port // "N/A"' 2>/dev/null)
                    target_info=" → ${target_addr}:${target_port}"
                fi

                echo "   • ID:$id Port:$port${target_info} [$remark] - $status"
            done
    else
        print_error "Dokodemo inbound'ы не найдены в БД"
        add_issue "Отсутствуют inbound'ы в базе данных"
        add_recommendation "Создайте inbound'ы через API или панель"
    fi
}

# Check network ports
check_network_ports() {
    print_header "7. Проверка сетевых портов"

    # Check if ss or netstat is available
    local port_cmd=""
    if command -v ss &> /dev/null; then
        port_cmd="ss"
    elif command -v netstat &> /dev/null; then
        port_cmd="netstat"
    else
        print_warning "ss и netstat не найдены, пропускаем проверку портов"
        return 0
    fi

    # Try to get ports from database first
    local ports=""
    local db_file="/etc/x-ui/x-ui.db"

    if [[ -f "$db_file" ]] && command -v sqlite3 &> /dev/null; then
        ports=$(sqlite3 "$db_file" "SELECT port FROM inbounds WHERE protocol='dokodemo-door' AND enable=1;" 2>/dev/null)
    fi

    # Fallback to config file
    if [[ -z "$ports" ]]; then
        local config_file="/usr/local/x-ui/bin/config.json"
        if [[ -f "$config_file" ]]; then
            ports=$(jq -r '.inbounds[] | select(.protocol=="dokodemo-door") | .port' \
                "$config_file" 2>/dev/null)
        fi
    fi

    if [[ -z "$ports" ]]; then
        print_warning "Dokodemo порты не найдены"
        return 0
    fi

    # Check each port
    echo "$ports" | while read port; do
        if [[ "$port_cmd" == "ss" ]]; then
            if ss -tlnp 2>/dev/null | grep -q ":$port "; then
                print_success "Порт $port слушается"
            else
                print_error "Порт $port НЕ слушается"
                add_issue "Порт $port не открыт"
                add_recommendation "Проверьте что x-ui запущен и inbound включен"
            fi
        else
            if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
                print_success "Порт $port слушается"
            else
                print_error "Порт $port НЕ слушается"
                add_issue "Порт $port не открыт"
            fi
        fi
    done
}

# Check firewall
check_firewall() {
    print_header "8. Проверка firewall"

    # Check UFW
    if command -v ufw &> /dev/null; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            print_info "UFW активен"

            # Try to get ports from database first
            local ports=""
            local db_file="/etc/x-ui/x-ui.db"

            if [[ -f "$db_file" ]] && command -v sqlite3 &> /dev/null; then
                ports=$(sqlite3 "$db_file" "SELECT port FROM inbounds WHERE protocol='dokodemo-door' AND enable=1;" 2>/dev/null)
            fi

            # Fallback to config file
            if [[ -z "$ports" ]]; then
                local config_file="/usr/local/x-ui/bin/config.json"
                if [[ -f "$config_file" ]]; then
                    ports=$(jq -r '.inbounds[] | select(.protocol=="dokodemo-door") | .port' \
                        "$config_file" 2>/dev/null)
                fi
            fi

            if [[ -n "$ports" ]]; then
                echo "$ports" | while read port; do
                    if ufw status 2>/dev/null | grep -qE "${port}/tcp.*ALLOW"; then
                        print_success "Порт $port разрешен в UFW"
                    else
                        print_warning "Порт $port не разрешен в UFW"
                        add_recommendation "Откройте порт: ufw allow $port/tcp && ufw allow $port/udp"
                    fi
                done
            fi
        else
            print_info "UFW неактивен"
        fi
    fi

    # Check iptables
    if command -v iptables &> /dev/null; then
        local rules_count=$(iptables -L -n 2>/dev/null | wc -l)
        print_info "Правил iptables: $rules_count"
    fi
}

# Check connectivity to Finnish servers
check_finnish_servers() {
    print_header "9. Проверка доступности финских серверов"

    # Try to get servers from database first
    local servers=""
    local db_file="/etc/x-ui/x-ui.db"

    if [[ -f "$db_file" ]] && command -v sqlite3 &> /dev/null && command -v jq &> /dev/null; then
        # Get settings from database and parse JSON
        local db_settings=$(sqlite3 "$db_file" "SELECT settings FROM inbounds WHERE protocol='dokodemo-door';" 2>/dev/null)

        if [[ -n "$db_settings" ]]; then
            servers=$(echo "$db_settings" | while read -r settings; do
                if [[ -n "$settings" ]]; then
                    echo "$settings" | jq -r 'select(.address != null and .port != null) | "\(.address):\(.port)"' 2>/dev/null
                fi
            done)
        fi
    fi

    # Fallback to config file
    if [[ -z "$servers" ]]; then
        local config_file="/usr/local/x-ui/bin/config.json"
        if [[ -f "$config_file" ]]; then
            servers=$(jq -r '.inbounds[] | select(.protocol=="dokodemo-door") |
                "\(.settings.address):\(.settings.port)"' "$config_file" 2>/dev/null)
        fi
    fi

    if [[ -z "$servers" ]]; then
        print_warning "Целевые серверы не найдены"
        return 0
    fi

    # Check each server
    echo "$servers" | while IFS=':' read -r ip port; do
        echo -e "${CYAN}   Проверка $ip:$port${NC}"

        # Ping test
        if command -v ping &> /dev/null; then
            if ping -c 2 -W 3 "$ip" &>/dev/null; then
                print_success "   Ping к $ip успешен"
            else
                print_error "   Ping к $ip не прошел"
                add_issue "Финский сервер $ip недоступен (ping)"
            fi
        fi

        # TCP connection test - try multiple methods
        local tcp_success=false

        # Method 1: Try bash /dev/tcp (most reliable for SSL)
        if timeout 3 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; then
            tcp_success=true
        # Method 2: Try nc without -z flag (better for SSL)
        elif command -v nc &> /dev/null; then
            if timeout 3 nc -w 2 "$ip" "$port" </dev/null &>/dev/null; then
                tcp_success=true
            fi
        # Method 3: Try telnet
        elif command -v telnet &> /dev/null; then
            if timeout 3 bash -c "echo 'quit' | telnet $ip $port 2>/dev/null | grep -q 'Connected\\|Escape'"; then
                tcp_success=true
            fi
        fi

        if [[ "$tcp_success" == "true" ]]; then
            print_success "   TCP соединение $ip:$port успешно"
        else
            print_warning "   TCP соединение $ip:$port не удалось (но это может быть нормально для SSL)"
            # Don't add as critical issue since SSL connections may fail basic TCP tests
        fi
    done
}

# Check x-ui logs for errors
check_xui_logs() {
    print_header "10. Проверка логов x-ui"

    if ! command -v journalctl &> /dev/null; then
        print_warning "journalctl не найден, пропускаем проверку логов"
        return 0
    fi

    # Check for recent errors
    local error_count=$(journalctl -u x-ui --since "10 minutes ago" 2>/dev/null | \
        grep -c "ERROR" 2>/dev/null || true)

    # Ensure error_count is a valid number
    error_count=${error_count:-0}
    error_count=$(echo "$error_count" | tr -d '\n' | grep -o '[0-9]*' | head -1)
    error_count=${error_count:-0}

    if [[ $error_count -eq 0 ]]; then
        print_success "Ошибок в логах за последние 10 минут не найдено"
    elif [[ $error_count -lt 10 ]]; then
        print_warning "Найдено ошибок в логах: $error_count"
        echo -e "${YELLOW}   Последние ошибки:${NC}"
        journalctl -u x-ui --since "10 minutes ago" 2>/dev/null | \
            grep "ERROR" | tail -3 | sed 's/^/   /'
    else
        print_error "Много ошибок в логах: $error_count"
        add_issue "Множественные ошибки в логах x-ui"
        add_recommendation "Проверьте логи: journalctl -u x-ui -n 50"
        echo -e "${RED}   Последние ошибки:${NC}"
        journalctl -u x-ui --since "10 minutes ago" 2>/dev/null | \
            grep "ERROR" | tail -5 | sed 's/^/   /'
    fi

    # Check if Xray is restarting
    local restart_count=$(journalctl -u x-ui --since "10 minutes ago" 2>/dev/null | \
        grep -c "started" 2>/dev/null || true)

    # Ensure restart_count is a valid number
    restart_count=${restart_count:-0}
    restart_count=$(echo "$restart_count" | tr -d '\n' | grep -o '[0-9]*' | head -1)
    restart_count=${restart_count:-0}

    if [[ $restart_count -gt 3 ]]; then
        print_warning "Xray перезапускался $restart_count раз за последние 10 минут"
        add_issue "Частые перезапуски Xray"
        add_recommendation "Проверьте конфигурацию на ошибки"
    fi
}

# Check external IP
check_external_ip() {
    print_header "11. Проверка внешнего IP"

    local external_ip=""

    if command -v curl &> /dev/null; then
        external_ip=$(curl -s -4 --max-time 5 ifconfig.me 2>/dev/null || \
                     curl -s -4 --max-time 5 icanhazip.com 2>/dev/null || \
                     curl -s -4 --max-time 5 ipinfo.io/ip 2>/dev/null || \
                     echo "N/A")
    fi

    if [[ "$external_ip" != "N/A" ]] && [[ -n "$external_ip" ]]; then
        print_success "Внешний IP: $external_ip"
        echo -e "${CYAN}   Используйте этот IP в клиентских конфигурациях${NC}"
    else
        print_warning "Не удалось определить внешний IP"
    fi
}

# Final summary
print_summary() {
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BOLD}ИТОГОВЫЙ ОТЧЕТ${NC}\n"

    # Status counts
    echo -e "${GREEN}✓ Проверок пройдено:${NC} $PASS_COUNT"
    echo -e "${YELLOW}⚠ Предупреждений:${NC} $WARN_COUNT"
    echo -e "${RED}✗ Ошибок:${NC} $FAIL_COUNT"

    # Overall status
    echo
    if [[ $FAIL_COUNT -eq 0 ]] && [[ $WARN_COUNT -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ ВСЁ ОТЛИЧНО!${NC} Мост работает корректно."
    elif [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${YELLOW}${BOLD}⚠ ЕСТЬ ПРЕДУПРЕЖДЕНИЯ${NC} Мост работает, но есть рекомендации."
    else
        echo -e "${RED}${BOLD}✗ ОБНАРУЖЕНЫ ПРОБЛЕМЫ${NC} Требуется исправление."
    fi

    # Issues
    if [[ ${#ISSUES[@]} -gt 0 ]]; then
        echo
        echo -e "${RED}${BOLD}Обнаруженные проблемы:${NC}"
        for issue in "${ISSUES[@]}"; do
            echo -e "${RED}  ✗${NC} $issue"
        done
    fi

    # Recommendations
    if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
        echo
        echo -e "${CYAN}${BOLD}Рекомендации по исправлению:${NC}"
        local idx=1
        for rec in "${RECOMMENDATIONS[@]}"; do
            echo -e "${CYAN}  $idx.${NC} $rec"
            idx=$((idx + 1))
        done
    fi

    # Quick fix commands
    if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
        echo
        echo -e "${MAGENTA}${BOLD}Быстрые команды для исправления:${NC}"
        echo -e "${MAGENTA}  # Перезапуск x-ui:${NC}"
        echo "  systemctl restart x-ui"
        echo
        echo -e "${MAGENTA}  # Просмотр логов:${NC}"
        echo "  journalctl -u x-ui -f"
        echo
        echo -e "${MAGENTA}  # Проверка портов:${NC}"
        echo "  ss -tlnp | grep -E ':443|:8443'"
    fi

    echo
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

################################################################################
# MAIN FUNCTION
################################################################################

main() {
    # Print banner
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     Dokodemo-door Bridge Diagnostic Tool                      ║"
    echo "║     Version: $SCRIPT_VERSION                                        ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Run diagnostics
    check_root || exit 1
    check_dependencies
    check_system_resources
    check_xui_service
    check_xui_config
    check_xui_database
    check_network_ports
    check_firewall
    check_finnish_servers
    check_xui_logs
    check_external_ip

    # Print summary
    print_summary

    # Exit code based on failures
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

################################################################################
# ENTRY POINT
################################################################################

main "$@"
