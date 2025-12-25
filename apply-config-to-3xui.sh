#!/bin/bash

################################################################################
# Auto-apply ByeDPI Config to 3x-ui
#
# Description: Automatically applies ByeDPI balancer configuration to 3x-ui
#              using various methods (API, direct file edit, or manual)
#
# Usage: sudo ./apply-config-to-3xui.sh [OPTIONS]
#
# Options:
#   --config FILE             Path to config file (default: /root/byedpi-config/xray-balancer-config.json)
#   --method api|file|manual  Application method (default: auto-detect)
#   --3xui-url URL           3x-ui panel URL (e.g., http://localhost:54321)
#   --3xui-user USER         3x-ui username
#   --3xui-pass PASS         3x-ui password
#
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
CONFIG_FILE="/root/byedpi-config/xray-balancer-config.json"
METHOD="auto"
XRAY_CONFIG_PATH="/usr/local/x-ui/bin/config.json"
XUI_DB="/etc/x-ui/x-ui.db"
XUI_URL=""
XUI_USER=""
XUI_PASS=""

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_step() {
    echo -e "${CYAN}${BOLD}==>${NC} $*"
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --method)
                METHOD="$2"
                shift 2
                ;;
            --3xui-url)
                XUI_URL="$2"
                shift 2
                ;;
            --3xui-user)
                XUI_USER="$2"
                shift 2
                ;;
            --3xui-pass)
                XUI_PASS="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
${BOLD}Auto-apply ByeDPI Config to 3x-ui${NC}

${BOLD}Usage:${NC}
    sudo $0 [OPTIONS]

${BOLD}Options:${NC}
    --config FILE             Path to config file
    --method api|file|manual  Application method
    --3xui-url URL           3x-ui panel URL
    --3xui-user USER         3x-ui username
    --3xui-pass PASS         3x-ui password
    -h, --help               Show this help

${BOLD}Examples:${NC}
    # Auto-detect and apply
    sudo $0

    # Apply using API
    sudo $0 --method api --3xui-url http://localhost:54321 --3xui-user admin --3xui-pass admin

    # Apply by editing file directly
    sudo $0 --method file

    # Show manual instructions
    sudo $0 --method manual

EOF
}

# Detect 3x-ui installation
detect_3xui() {
    log_step "Определение метода установки 3x-ui..."

    # Check if x-ui service exists
    if systemctl list-units --full -all | grep -q "x-ui.service"; then
        log_success "3x-ui сервис обнаружен"

        # Check if config file exists
        if [[ -f "$XRAY_CONFIG_PATH" ]]; then
            log_success "Конфигурация Xray найдена: $XRAY_CONFIG_PATH"
            return 0
        fi
    fi

    # Check if database exists
    if [[ -f "$XUI_DB" ]]; then
        log_success "База данных 3x-ui найдена: $XUI_DB"
        return 0
    fi

    log_warn "3x-ui не обнаружен на этом сервере"
    return 1
}

# Method 1: Apply via API
apply_via_api() {
    log_step "Применение конфигурации через 3x-ui API..."

    if [[ -z "$XUI_URL" ]] || [[ -z "$XUI_USER" ]] || [[ -z "$XUI_PASS" ]]; then
        log_error "Для использования API требуются: --3xui-url, --3xui-user, --3xui-pass"
        return 1
    fi

    # Login to get session
    log_info "Авторизация в 3x-ui..."
    local session=$(curl -s -X POST "$XUI_URL/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=$XUI_USER&password=$XUI_PASS" \
        -c /tmp/3xui-cookies.txt)

    if [[ $? -ne 0 ]]; then
        log_error "Не удалось авторизоваться в 3x-ui"
        return 1
    fi

    # Get current config
    log_info "Получение текущей конфигурации..."
    local current_config=$(curl -s -X GET "$XUI_URL/xui/API/inbounds/get" \
        -b /tmp/3xui-cookies.txt)

    # Merge configurations
    log_info "Объединение конфигураций..."
    # This would need jq to merge JSONs properly

    log_warn "API метод требует доработки для вашей версии 3x-ui"
    log_info "Используйте --method file или --method manual"

    rm -f /tmp/3xui-cookies.txt
    return 1
}

# Method 2: Apply by editing file directly
apply_via_file() {
    log_step "Применение конфигурации через редактирование файла..."

    if [[ ! -f "$XRAY_CONFIG_PATH" ]]; then
        log_error "Конфигурация Xray не найдена: $XRAY_CONFIG_PATH"
        log_info "Возможно, 3x-ui установлен в другой директории"
        return 1
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Конфигурация ByeDPI не найдена: $CONFIG_FILE"
        return 1
    fi

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_warn "jq не установлен. Установка..."
        apt-get update -qq && apt-get install -y -qq jq || {
            log_error "Не удалось установить jq"
            return 1
        }
    fi

    # Backup current config
    log_info "Создание резервной копии..."
    cp "$XRAY_CONFIG_PATH" "${XRAY_CONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"

    # Merge configurations
    log_info "Объединение конфигураций..."

    local new_outbounds=$(jq '.outbounds' "$CONFIG_FILE")
    local new_routing=$(jq '.routing' "$CONFIG_FILE")

    # Update outbounds
    jq --argjson outbounds "$new_outbounds" '.outbounds = $outbounds' "$XRAY_CONFIG_PATH" > /tmp/xray-config-temp.json

    # Update routing
    jq --argjson routing "$new_routing" '.routing = $routing' /tmp/xray-config-temp.json > "${XRAY_CONFIG_PATH}.new"

    # Validate JSON
    if jq empty "${XRAY_CONFIG_PATH}.new" 2>/dev/null; then
        mv "${XRAY_CONFIG_PATH}.new" "$XRAY_CONFIG_PATH"
        rm -f /tmp/xray-config-temp.json
        log_success "Конфигурация успешно обновлена"

        # Restart x-ui
        log_info "Перезапуск x-ui..."
        systemctl restart x-ui

        if systemctl is-active --quiet x-ui; then
            log_success "x-ui успешно перезапущен"
            return 0
        else
            log_error "x-ui не запустился. Восстановление из резервной копии..."
            cp "${XRAY_CONFIG_PATH}.backup."* "$XRAY_CONFIG_PATH"
            systemctl restart x-ui
            return 1
        fi
    else
        log_error "Новая конфигурация содержит ошибки JSON"
        rm -f "${XRAY_CONFIG_PATH}.new" /tmp/xray-config-temp.json
        return 1
    fi
}

# Method 3: Show manual instructions
apply_manual() {
    log_step "Инструкция по ручной настройке..."

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Конфигурация не найдена: $CONFIG_FILE"
        return 1
    fi

    echo ""
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  Инструкция по применению конфигурации                    ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "📋 Шаг 1: Откройте веб-панель 3x-ui в браузере"
    echo ""

    log_info "📋 Шаг 2: Перейдите в Xray Configs (или Panel Settings → Xray Configs)"
    echo ""

    log_info "📋 Шаг 3: Скопируйте конфигурацию из файла:"
    echo -e "${YELLOW}cat $CONFIG_FILE${NC}"
    echo ""

    log_info "📋 Шаг 4: В JSON редакторе панели замените:"
    echo "  - Секцию \"outbounds\": [...]"
    echo "  - Секцию \"routing\": {...}"
    echo ""

    log_info "📋 Шаг 5: Нажмите Save Config и Restart Xray"
    echo ""

    echo -e "${CYAN}Или скопируйте команду:${NC}"
    echo ""
    echo "cat $CONFIG_FILE"
    echo ""

    # Optionally display the config
    read -p "Показать конфигурацию сейчас? [y/N]: " show_config
    if [[ "$show_config" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}=== Конфигурация ===${NC}"
        cat "$CONFIG_FILE"
        echo ""
    fi

    log_info "💡 После применения перезапустите x-ui:"
    echo -e "${YELLOW}sudo systemctl restart x-ui${NC}"
    echo ""

    return 0
}

# Main function
main() {
    parse_args "$@"

    echo ""
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  Автоматическое применение конфигурации ByeDPI           ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Конфигурация не найдена: $CONFIG_FILE"
        log_info "Сначала запустите: ./generate-balancer-config.sh"
        exit 1
    fi

    # Detect method if auto
    if [[ "$METHOD" == "auto" ]]; then
        if detect_3xui; then
            METHOD="file"
            log_info "Выбран метод: прямое редактирование файла"
        else
            METHOD="manual"
            log_info "Выбран метод: ручная настройка"
        fi
    fi

    # Apply based on method
    case "$METHOD" in
        api)
            apply_via_api
            ;;
        file)
            apply_via_file
            ;;
        manual)
            apply_manual
            ;;
        *)
            log_error "Неизвестный метод: $METHOD"
            log_info "Доступные методы: api, file, manual"
            exit 1
            ;;
    esac

    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}${BOLD}║  ✓ Конфигурация успешно применена!                        ║${NC}"
        echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        log_info "Проверьте статус: sudo systemctl status x-ui"
        log_info "Проверьте логи: sudo journalctl -u x-ui -f"
        echo ""
    fi

    exit $exit_code
}

main "$@"
