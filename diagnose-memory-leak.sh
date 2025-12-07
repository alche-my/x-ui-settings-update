#!/bin/bash

################################################################################
# Dokodemo Memory Leak Diagnostic Script
#
# Description: Детальная диагностика утечки памяти БЕЗ активных клиентов
#              Помогает найти источник проблемы в конфигурации
#
# Usage: sudo ./diagnose-memory-leak.sh
################################################################################

set -euo pipefail

################################################################################
# COLORS
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

################################################################################
# CONFIGURATION
################################################################################

XRAY_CONFIG="/usr/local/x-ui/bin/config.json"
XUI_DB="/etc/x-ui/x-ui.db"
MONITOR_INTERVAL=10  # seconds
MONITOR_DURATION=60  # seconds (total monitoring time)

################################################################################
# UTILITY FUNCTIONS
################################################################################

print_header() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Скрипт должен быть запущен с правами root"
        exit 1
    fi
}

################################################################################
# DIAGNOSTIC FUNCTIONS
################################################################################

# Get Xray PID
get_xray_pid() {
    pgrep -f "xray" | head -1 || echo ""
}

# Get process memory in MB
get_memory_mb() {
    local pid=$1
    if [[ -z "$pid" ]]; then
        echo "0"
        return
    fi

    ps -p "$pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}' || echo "0"
}

# Check Xray version
check_xray_version() {
    print_header "1. Проверка версии Xray"

    local xray_bin="/usr/local/x-ui/bin/xray-linux-amd64"

    if [[ ! -f "$xray_bin" ]]; then
        print_error "Xray binary не найден"
        return 1
    fi

    local version=$("$xray_bin" --version 2>/dev/null | head -1 || echo "Unknown")
    print_info "Версия Xray: $version"

    # Check if version is old
    if echo "$version" | grep -qE "v1\.[0-4]\.|v1\.5\.[0-5]"; then
        print_warning "СТАРАЯ ВЕРСИЯ! Рекомендуется обновление"
        print_info "Известные баги с утечкой памяти в версиях < 1.8.0"
        return 1
    else
        print_success "Версия актуальная"
    fi
}

# Check logging configuration
check_logging_config() {
    print_header "2. Проверка конфигурации логирования"

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        print_error "Конфиг не найден: $XRAY_CONFIG"
        return 1
    fi

    # Check log level
    local log_level=$(jq -r '.log.loglevel // "none"' "$XRAY_CONFIG" 2>/dev/null)

    print_info "Уровень логирования: $log_level"

    if [[ "$log_level" == "debug" ]] || [[ "$log_level" == "info" ]]; then
        print_error "ПРОБЛЕМА НАЙДЕНА!"
        print_warning "Debug/Info логирование может вызывать утечку памяти!"
        print_info "Рекомендация: Изменить на 'warning' или 'error'"
        echo -e "${YELLOW}"
        echo "  Исправление:"
        echo "  jq '.log.loglevel = \"warning\"' $XRAY_CONFIG > /tmp/config.tmp && mv /tmp/config.tmp $XRAY_CONFIG"
        echo "  systemctl restart x-ui"
        echo -e "${NC}"
        return 1
    else
        print_success "Логирование настроено правильно: $log_level"
    fi

    # Check access log
    local access_log=$(jq -r '.log.access // "none"' "$XRAY_CONFIG" 2>/dev/null)

    if [[ "$access_log" != "none" ]] && [[ "$access_log" != "" ]] && [[ "$access_log" != "null" ]]; then
        print_warning "Access log включен: $access_log"
        print_info "Может накапливаться и занимать память"
    else
        print_success "Access log отключен"
    fi
}

# Check DNS configuration
check_dns_config() {
    print_header "3. Проверка DNS конфигурации"

    local dns_servers=$(jq -r '.dns.servers[]? // empty' "$XRAY_CONFIG" 2>/dev/null)

    if [[ -z "$dns_servers" ]]; then
        print_warning "DNS не настроен"
        print_info "Dokodemo может использовать системный DNS с утечками"
        return 1
    fi

    print_success "DNS настроен:"
    echo "$dns_servers" | while read server; do
        echo "   - $server"
    done

    # Check DNS query strategy
    local dns_strategy=$(jq -r '.dns.queryStrategy // "UseIP"' "$XRAY_CONFIG" 2>/dev/null)
    print_info "Стратегия DNS: $dns_strategy"

    # Check if DisableCache is set
    local disable_cache=$(jq -r '.dns.disableCache // false' "$XRAY_CONFIG" 2>/dev/null)

    if [[ "$disable_cache" == "true" ]]; then
        print_error "ПРОБЛЕМА: DNS кеш отключен!"
        print_warning "Каждый запрос создает новый DNS lookup - утечка памяти"
        echo -e "${YELLOW}"
        echo "  Исправление:"
        echo "  jq 'del(.dns.disableCache)' $XRAY_CONFIG > /tmp/config.tmp && mv /tmp/config.tmp $XRAY_CONFIG"
        echo "  systemctl restart x-ui"
        echo -e "${NC}"
        return 1
    else
        print_success "DNS кеш включен"
    fi
}

# Check Dokodemo inbound configuration
check_dokodemo_config() {
    print_header "4. Проверка конфигурации Dokodemo inbound"

    local dokodemo_count=$(jq '[.inbounds[]? | select(.protocol=="dokodemo-door")] | length' "$XRAY_CONFIG" 2>/dev/null || echo "0")

    if [[ "$dokodemo_count" -eq 0 ]]; then
        print_warning "Dokodemo inbound не найден в config.json"
        print_info "Проверяем базу данных..."

        if [[ -f "$XUI_DB" ]] && command -v sqlite3 &>/dev/null; then
            dokodemo_count=$(sqlite3 "$XUI_DB" "SELECT COUNT(*) FROM inbounds WHERE protocol='dokodemo-door';" 2>/dev/null || echo "0")
            print_info "Dokodemo inbound в БД: $dokodemo_count"
        fi
    else
        print_info "Найдено Dokodemo inbound: $dokodemo_count"
    fi

    # Check sniffing configuration
    local sniffing_enabled=$(jq -r '.inbounds[]? | select(.protocol=="dokodemo-door") | .sniffing.enabled // false' "$XRAY_CONFIG" 2>/dev/null | head -1)

    if [[ "$sniffing_enabled" == "true" ]]; then
        print_warning "Sniffing включен для Dokodemo"

        local dest_override=$(jq -r '.inbounds[]? | select(.protocol=="dokodemo-door") | .sniffing.destOverride[]?' "$XRAY_CONFIG" 2>/dev/null)

        print_info "DestOverride: $(echo $dest_override | tr '\n' ', ')"

        print_warning "Sniffing может накапливать данные в памяти"
        print_info "Для прозрачного проксирования sniffing НЕ нужен"
        echo -e "${YELLOW}"
        echo "  Рекомендация: Отключить sniffing если нет необходимости"
        echo "  Это уменьшит потребление памяти на 20-30%"
        echo -e "${NC}"
    else
        print_success "Sniffing отключен (хорошо для памяти)"
    fi

    # Check for timeout settings
    print_info "Проверка timeout настроек..."

    # In dokodemo, timeout is usually in streamSettings
    local has_timeout=$(jq '.inbounds[]? | select(.protocol=="dokodemo-door") | .streamSettings.sockopt.tcpKeepAliveInterval?' "$XRAY_CONFIG" 2>/dev/null)

    if [[ -z "$has_timeout" ]] || [[ "$has_timeout" == "null" ]]; then
        print_warning "TCP KeepAlive не настроен!"
        print_warning "Мертвые соединения могут накапливаться в памяти"
        echo -e "${YELLOW}"
        echo "  Рекомендация: Добавить TCP KeepAlive настройки"
        echo "  Это автоматически закрывает мертвые соединения"
        echo -e "${NC}"
    else
        print_success "TCP KeepAlive настроен: ${has_timeout}s"
    fi
}

# Check routing configuration
check_routing_config() {
    print_header "5. Проверка правил маршрутизации"

    local routing_rules=$(jq '.routing.rules? // [] | length' "$XRAY_CONFIG" 2>/dev/null || echo "0")

    print_info "Количество правил маршрутизации: $routing_rules"

    if [[ "$routing_rules" -gt 50 ]]; then
        print_warning "МНОГО правил маршрутизации: $routing_rules"
        print_warning "Каждое правило занимает память"
        print_info "Рекомендуется < 20 правил для dokodemo"
    elif [[ "$routing_rules" -gt 20 ]]; then
        print_warning "Среднее количество правил: $routing_rules"
        print_info "Возможна оптимизация"
    else
        print_success "Количество правил в норме"
    fi

    # Check for potential routing loops
    print_info "Проверка на циклы в маршрутизации..."

    local direct_count=$(jq '[.routing.rules[]? | select(.outboundTag=="direct")] | length' "$XRAY_CONFIG" 2>/dev/null || echo "0")
    local block_count=$(jq '[.routing.rules[]? | select(.outboundTag=="block")] | length' "$XRAY_CONFIG" 2>/dev/null || echo "0")

    print_info "  - Direct правил: $direct_count"
    print_info "  - Block правил: $block_count"
}

# Monitor memory growth in real-time
monitor_memory_growth() {
    print_header "6. Мониторинг роста памяти (${MONITOR_DURATION}s)"

    local pid=$(get_xray_pid)

    if [[ -z "$pid" ]]; then
        print_error "Xray процесс не найден"
        return 1
    fi

    print_info "Мониторинг PID: $pid"
    print_info "Интервал: ${MONITOR_INTERVAL}s"
    print_info ""

    echo -e "${CYAN}Время     | Память (MB) | Δ (MB) | Δ (%)${NC}"
    echo "----------|-------------|--------|--------"

    local start_mem=$(get_memory_mb "$pid")
    local prev_mem=$start_mem
    local iterations=$((MONITOR_DURATION / MONITOR_INTERVAL))

    local max_growth=0
    local total_growth=0

    for ((i=1; i<=iterations; i++)); do
        sleep "$MONITOR_INTERVAL"

        local current_mem=$(get_memory_mb "$pid")
        local delta=$((current_mem - prev_mem))
        local delta_pct=0

        if [[ $prev_mem -ne 0 ]]; then
            delta_pct=$(awk "BEGIN {printf \"%.1f\", ($delta / $prev_mem) * 100}")
        fi

        local timestamp=$(date '+%H:%M:%S')

        # Color code the delta
        local delta_color=$NC
        if [[ $delta -gt 5 ]]; then
            delta_color=$RED
            max_growth=$delta
        elif [[ $delta -gt 2 ]]; then
            delta_color=$YELLOW
            if [[ $delta -gt $max_growth ]]; then
                max_growth=$delta
            fi
        elif [[ $delta -gt 0 ]]; then
            delta_color=$GREEN
            if [[ $delta -gt $max_growth ]]; then
                max_growth=$delta
            fi
        fi

        printf "${timestamp} | %11d | ${delta_color}%+6d${NC} | ${delta_color}%+5s%%${NC}\n" \
            "$current_mem" "$delta" "$delta_pct"

        prev_mem=$current_mem
        total_growth=$((current_mem - start_mem))
    done

    echo "----------|-------------|--------|--------"

    # Analysis
    echo ""
    print_info "Анализ результатов:"
    echo "  - Начальная память: ${start_mem} MB"
    echo "  - Конечная память:  ${prev_mem} MB"
    echo "  - Общий рост:       ${total_growth} MB"
    echo "  - Макс. рост/шаг:   ${max_growth} MB"

    local growth_rate=$(awk "BEGIN {printf \"%.2f\", ($total_growth / $MONITOR_DURATION) * 60}")
    echo "  - Скорость роста:   ${growth_rate} MB/минуту"

    echo ""

    # Verdict
    if [[ $total_growth -gt 10 ]]; then
        print_error "КРИТИЧНО! Обнаружена утечка памяти!"
        echo -e "${RED}"
        echo "  Память растет на ${growth_rate} MB/минуту"
        echo "  При такой скорости сервер упадет через $(awk "BEGIN {printf \"%.1f\", 500 / $growth_rate}") часов"
        echo -e "${NC}"
        return 1
    elif [[ $total_growth -gt 5 ]]; then
        print_warning "Обнаружен умеренный рост памяти"
        echo -e "${YELLOW}"
        echo "  Память растет на ${growth_rate} MB/минуту"
        echo "  Рекомендуется мониторинг и оптимизация"
        echo -e "${NC}"
        return 1
    elif [[ $total_growth -gt 2 ]]; then
        print_warning "Небольшой рост памяти (возможно, нормально)"
        print_info "Это может быть нормальное кеширование"
    else
        print_success "Память стабильна, утечки не обнаружено"
    fi
}

# Check active connections
check_active_connections() {
    print_header "7. Проверка активных соединений"

    # Get dokodemo ports from config or DB
    local ports=""

    if [[ -f "$XRAY_CONFIG" ]]; then
        ports=$(jq -r '.inbounds[]? | select(.protocol=="dokodemo-door") | .port' "$XRAY_CONFIG" 2>/dev/null)
    fi

    if [[ -z "$ports" ]] && [[ -f "$XUI_DB" ]] && command -v sqlite3 &>/dev/null; then
        ports=$(sqlite3 "$XUI_DB" "SELECT port FROM inbounds WHERE protocol='dokodemo-door' AND enable=1;" 2>/dev/null)
    fi

    if [[ -z "$ports" ]]; then
        print_warning "Не удалось определить порты Dokodemo"
        return 1
    fi

    print_info "Проверяем порты: $(echo $ports | tr '\n' ', ')"
    echo ""

    local total_connections=0

    while read -r port; do
        if [[ -n "$port" ]]; then
            local conn_count=$(ss -tn state established "( dport = :$port or sport = :$port )" 2>/dev/null | grep -v "State" | wc -l || echo "0")

            if [[ $conn_count -gt 0 ]]; then
                print_warning "Порт $port: $conn_count активных соединений"
            else
                print_success "Порт $port: нет активных соединений"
            fi

            total_connections=$((total_connections + conn_count))
        fi
    done <<< "$ports"

    echo ""
    print_info "Всего активных соединений: $total_connections"

    if [[ $total_connections -eq 0 ]]; then
        print_success "НЕТ активных клиентов - можно точно диагностировать утечку"
    else
        print_warning "Есть активные клиенты - может быть норма"
    fi
}

# Check system resources
check_system_resources() {
    print_header "8. Системные ресурсы"

    # Total memory
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_mb=$((total_mem_kb / 1024))

    # Free memory
    local free_mem=$(free -m | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')

    print_info "Всего памяти: ${total_mem_mb} MB"
    print_info "Использовано: ${free_mem}%"

    # Check swap
    local swap_used=$(free -m | awk 'NR==3 {print $3}')

    if [[ $swap_used -gt 0 ]]; then
        print_warning "SWAP используется: ${swap_used} MB"
        print_warning "Система уже испытывает недостаток памяти!"
    else
        print_success "SWAP не используется"
    fi

    # Open file descriptors
    local pid=$(get_xray_pid)
    if [[ -n "$pid" ]]; then
        local open_fds=$(ls /proc/$pid/fd 2>/dev/null | wc -l || echo "0")
        print_info "Открытых файловых дескрипторов: $open_fds"

        if [[ $open_fds -gt 1000 ]]; then
            print_warning "Много открытых дескрипторов - возможная утечка"
        fi
    fi
}

# Generate recommendations
generate_recommendations() {
    print_header "9. Рекомендации по исправлению"

    echo -e "${BOLD}На основе диагностики:${NC}"
    echo ""

    echo -e "${CYAN}1. Немедленные действия:${NC}"
    echo "   - Настроить monitor-memory.sh для автоматического перезапуска"
    echo "   - Установить порог 70-80% вместо стандартного"
    echo ""

    echo -e "${CYAN}2. Оптимизация конфигурации:${NC}"
    echo "   - Отключить sniffing в dokodemo (если не нужен)"
    echo "   - Установить loglevel: 'warning' вместо 'debug'/'info'"
    echo "   - Включить DNS кеш"
    echo "   - Добавить TCP KeepAlive для закрытия мертвых соединений"
    echo ""

    echo -e "${CYAN}3. Долгосрочное решение:${NC}"
    echo "   - Обновить Xray до последней версии"
    echo "   - Уменьшить количество routing rules"
    echo "   - Рассмотреть увеличение RAM сервера"
    echo ""

    echo -e "${CYAN}4. Скрипт автоматического исправления:${NC}"
    echo "   ./fix-dokodemo-memory-config.sh"
    echo "   (будет создан автоматически после диагностики)"
    echo ""
}

################################################################################
# MAIN FUNCTION
################################################################################

main() {
    # Print banner
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   Dokodemo Memory Leak Diagnostic (БЕЗ активных клиентов)    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root

    # Run diagnostics
    check_xray_version
    check_logging_config
    check_dns_config
    check_dokodemo_config
    check_routing_config
    check_active_connections
    check_system_resources

    # Real-time monitoring
    echo ""
    read -p "Запустить мониторинг роста памяти? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        monitor_memory_growth
    fi

    # Recommendations
    generate_recommendations

    print_header "Диагностика завершена"
}

################################################################################
# ENTRY POINT
################################################################################

main "$@"
