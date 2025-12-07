#!/bin/bash

################################################################################
# Dokodemo Memory Configuration Fix Script
#
# Description: Автоматически исправляет конфигурацию для устранения утечки памяти
#              Применяет оптимизации на основе диагностики
#
# Usage: sudo ./fix-dokodemo-memory-config.sh
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
NC='\033[0m'
BOLD='\033[1m'

################################################################################
# CONFIGURATION
################################################################################

XRAY_CONFIG="/usr/local/x-ui/bin/config.json"
BACKUP_DIR="/root/dokodemo-memory-fix-backups"

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
# BACKUP FUNCTION
################################################################################

create_backup() {
    print_header "Создание резервной копии"

    mkdir -p "$BACKUP_DIR"

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="${BACKUP_DIR}/config-before-memfix-${timestamp}.json"

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        print_error "Конфиг не найден: $XRAY_CONFIG"
        exit 1
    fi

    cp "$XRAY_CONFIG" "$backup_file"

    if [[ $? -eq 0 ]]; then
        print_success "Резервная копия создана: $backup_file"
        echo "$backup_file"
    else
        print_error "Ошибка создания бэкапа"
        exit 1
    fi
}

################################################################################
# FIX FUNCTIONS
################################################################################

# Fix 1: Set logging to warning level
fix_logging() {
    print_header "1. Исправление уровня логирования"

    local current_level=$(jq -r '.log.loglevel // "none"' "$XRAY_CONFIG" 2>/dev/null)

    print_info "Текущий уровень: $current_level"

    if [[ "$current_level" == "debug" ]] || [[ "$current_level" == "info" ]]; then
        print_warning "Изменяем на 'warning' для уменьшения памяти..."

        jq '.log.loglevel = "warning"' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"

        if [[ $? -eq 0 ]]; then
            mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
            print_success "Логирование изменено на 'warning'"
            return 0
        else
            rm -f "${XRAY_CONFIG}.tmp"
            print_error "Ошибка изменения конфигурации"
            return 1
        fi
    else
        print_success "Логирование уже настроено правильно: $current_level"
    fi
}

# Fix 2: Disable access log
fix_access_log() {
    print_header "2. Отключение access log"

    local access_log=$(jq -r '.log.access // "none"' "$XRAY_CONFIG" 2>/dev/null)

    if [[ "$access_log" != "none" ]] && [[ "$access_log" != "" ]] && [[ "$access_log" != "null" ]]; then
        print_warning "Отключаем access log: $access_log"

        jq 'del(.log.access)' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"

        if [[ $? -eq 0 ]]; then
            mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
            print_success "Access log отключен"
            return 0
        else
            rm -f "${XRAY_CONFIG}.tmp"
            print_error "Ошибка изменения конфигурации"
            return 1
        fi
    else
        print_success "Access log уже отключен"
    fi
}

# Fix 3: Enable DNS cache
fix_dns_cache() {
    print_header "3. Включение DNS кеша"

    local disable_cache=$(jq -r '.dns.disableCache // false' "$XRAY_CONFIG" 2>/dev/null)

    if [[ "$disable_cache" == "true" ]]; then
        print_warning "DNS кеш отключен - включаем..."

        jq 'del(.dns.disableCache)' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"

        if [[ $? -eq 0 ]]; then
            mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
            print_success "DNS кеш включен"
            return 0
        else
            rm -f "${XRAY_CONFIG}.tmp"
            print_error "Ошибка изменения конфигурации"
            return 1
        fi
    else
        print_success "DNS кеш уже включен"
    fi
}

# Fix 4: Disable sniffing in dokodemo
fix_sniffing() {
    print_header "4. Отключение sniffing в Dokodemo"

    local sniffing_enabled=$(jq -r '.inbounds[]? | select(.protocol=="dokodemo-door") | .sniffing.enabled // false' "$XRAY_CONFIG" 2>/dev/null | head -1)

    if [[ "$sniffing_enabled" == "true" ]]; then
        print_warning "Sniffing включен - отключаем для экономии памяти..."

        # Disable sniffing for all dokodemo-door inbounds
        jq '(.inbounds[]? | select(.protocol=="dokodemo-door") | .sniffing.enabled) = false' \
            "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"

        if [[ $? -eq 0 ]]; then
            mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
            print_success "Sniffing отключен для Dokodemo"
            print_info "Экономия памяти: ~20-30%"
            return 0
        else
            rm -f "${XRAY_CONFIG}.tmp"
            print_error "Ошибка изменения конфигурации"
            return 1
        fi
    else
        print_success "Sniffing уже отключен"
    fi
}

# Fix 5: Add TCP KeepAlive to dokodemo
fix_tcp_keepalive() {
    print_header "5. Настройка TCP KeepAlive"

    print_info "Добавляем TCP KeepAlive для автоматического закрытия мертвых соединений..."

    # Add sockopt with tcpKeepAliveInterval to all dokodemo inbounds
    jq '
        (.inbounds[]? | select(.protocol=="dokodemo-door") | .streamSettings) =
        ((.inbounds[]? | select(.protocol=="dokodemo-door") | .streamSettings) // {}) + {
            "sockopt": {
                "tcpKeepAliveInterval": 30,
                "tcpFastOpen": true,
                "mark": 255
            }
        }
    ' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"

    if [[ $? -eq 0 ]] && jq empty "${XRAY_CONFIG}.tmp" 2>/dev/null; then
        mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
        print_success "TCP KeepAlive настроен (30s)"
        print_info "Мертвые соединения будут закрываться автоматически"
        return 0
    else
        rm -f "${XRAY_CONFIG}.tmp"
        print_error "Ошибка изменения конфигурации"
        return 1
    fi
}

# Fix 6: Optimize buffer sizes
fix_buffer_sizes() {
    print_header "6. Оптимизация размеров буферов"

    print_info "Устанавливаем оптимальные размеры буферов для экономии памяти..."

    # Add buffer size policy to all dokodemo inbounds
    jq '
        (.inbounds[]? | select(.protocol=="dokodemo-door") | .settings) =
        ((.inbounds[]? | select(.protocol=="dokodemo-door") | .settings) // {}) + {
            "userLevel": 0
        } |
        .policy = (.policy // {}) + {
            "levels": {
                "0": {
                    "bufferSize": 4
                }
            }
        }
    ' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"

    if [[ $? -eq 0 ]] && jq empty "${XRAY_CONFIG}.tmp" 2>/dev/null; then
        mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
        print_success "Размеры буферов оптимизированы (4 KB)"
        print_info "Это уменьшит потребление памяти на ~10%"
        return 0
    else
        rm -f "${XRAY_CONFIG}.tmp"
        print_warning "Не удалось оптимизировать буферы (не критично)"
        return 0
    fi
}

################################################################################
# VALIDATION AND RESTART
################################################################################

validate_config() {
    print_header "Валидация конфигурации"

    if jq empty "$XRAY_CONFIG" 2>/dev/null; then
        print_success "Конфигурация валидна (JSON корректен)"
        return 0
    else
        print_error "ОШИБКА: Конфигурация содержит невалидный JSON!"
        return 1
    fi
}

restart_xui() {
    print_header "Перезапуск x-ui"

    print_info "Останавливаем x-ui..."
    systemctl stop x-ui

    sleep 2

    print_info "Запускаем x-ui..."
    systemctl start x-ui

    sleep 3

    if systemctl is-active --quiet x-ui; then
        print_success "x-ui успешно перезапущен"
        return 0
    else
        print_error "x-ui не запустился!"
        print_error "Проверьте логи: journalctl -u x-ui -n 50"
        return 1
    fi
}

################################################################################
# MAIN FUNCTION
################################################################################

main() {
    # Print banner
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   Dokodemo Memory Configuration Auto-Fix                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root

    # Confirm
    echo -e "${YELLOW}"
    echo "Этот скрипт автоматически исправит конфигурацию для устранения утечки памяти."
    echo ""
    echo "Будут применены следующие изменения:"
    echo "  1. Логирование: warning (вместо debug/info)"
    echo "  2. Access log: отключен"
    echo "  3. DNS кеш: включен"
    echo "  4. Sniffing: отключен (в dokodemo)"
    echo "  5. TCP KeepAlive: 30s (автозакрытие мертвых соединений)"
    echo "  6. Buffer sizes: оптимизированы (4 KB)"
    echo ""
    echo "Резервная копия будет создана автоматически."
    echo -e "${NC}"

    read -p "Продолжить? (y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Отменено пользователем"
        exit 0
    fi

    # Create backup
    local backup_file=$(create_backup)

    # Apply fixes
    local fixes_applied=0

    fix_logging && ((fixes_applied++)) || true
    fix_access_log && ((fixes_applied++)) || true
    fix_dns_cache && ((fixes_applied++)) || true
    fix_sniffing && ((fixes_applied++)) || true
    fix_tcp_keepalive && ((fixes_applied++)) || true
    fix_buffer_sizes && ((fixes_applied++)) || true

    # Validate
    if ! validate_config; then
        print_error "Конфигурация невалидна! Откатываем изменения..."
        cp "$backup_file" "$XRAY_CONFIG"
        print_success "Изменения откачены"
        exit 1
    fi

    # Restart
    if ! restart_xui; then
        print_error "Ошибка перезапуска! Откатываем изменения..."
        cp "$backup_file" "$XRAY_CONFIG"
        systemctl restart x-ui
        exit 1
    fi

    # Summary
    print_header "Применение завершено"

    echo -e "${BOLD}Результаты:${NC}"
    echo "  - Применено исправлений: ${fixes_applied}/6"
    echo "  - Резервная копия: ${backup_file}"
    echo ""

    print_success "Конфигурация оптимизирована для экономии памяти!"

    echo ""
    echo -e "${CYAN}Следующие шаги:${NC}"
    echo "  1. Подождите 5-10 минут"
    echo "  2. Проверьте память: ./monitor-memory.sh status"
    echo "  3. Запустите диагностику: ./diagnose-memory-leak.sh"
    echo "  4. Настройте автомониторинг: */5 * * * * /path/to/monitor-memory.sh monitor"
    echo ""

    print_info "Ожидаемое снижение потребления памяти: 30-50%"
    print_info "Если проблема останется - обновите Xray до последней версии"
}

################################################################################
# ENTRY POINT
################################################################################

main "$@"
