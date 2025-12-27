#!/bin/bash

################################################################################
# Level 3 Quick Setup - Parse VLESS URL and Configure DPI Bypass
#
# Description: Простая настройка Level 3 через vless:// ссылку на Non-RU VPS
#
# Usage: ./level-3-quick-setup.sh
################################################################################

set -euo pipefail

# ============================================
# Global Variables
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Parsed values
VLESS_URL=""
NON_RU_IP=""
NON_RU_PORT=""
UUID=""
SNI=""
PUBLIC_KEY=""
SHORT_ID=""
FINGERPRINT=""

# ============================================
# Utility Functions
# ============================================

print_header() {
    echo -e "\n${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  Level 3 Quick Setup - VLESS URL Parser               ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}\n"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# ============================================
# URL Parsing Functions
# ============================================

urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

parse_vless_url() {
    local url=$1

    log_info "Парсинг VLESS URL..."

    # Check if URL starts with vless://
    if [[ ! "$url" =~ ^vless:// ]]; then
        log_error "URL должен начинаться с vless://"
        return 1
    fi

    # Remove vless:// prefix
    url="${url#vless://}"

    # Extract name (after #)
    local name=""
    if [[ "$url" =~ \#(.+)$ ]]; then
        name="${BASH_REMATCH[1]}"
        url="${url%#*}"
    fi

    # Split into parts: UUID@IP:PORT?params
    local uuid_and_address="${url%%\?*}"
    local params="${url#*\?}"

    # Extract UUID and address
    UUID="${uuid_and_address%%@*}"
    local address_and_port="${uuid_and_address#*@}"

    # Extract IP and port
    NON_RU_IP="${address_and_port%:*}"
    NON_RU_PORT="${address_and_port#*:}"

    # Parse parameters
    IFS='&' read -ra PARAMS <<< "$params"
    for param in "${PARAMS[@]}"; do
        local key="${param%%=*}"
        local value="${param#*=}"
        value=$(urldecode "$value")

        case "$key" in
            sni)
                SNI="$value"
                ;;
            pbk)
                PUBLIC_KEY="$value"
                ;;
            sid)
                SHORT_ID="$value"
                ;;
            fp)
                FINGERPRINT="$value"
                ;;
        esac
    done

    # Validate required fields
    if [[ -z "$NON_RU_IP" ]] || [[ -z "$NON_RU_PORT" ]] || [[ -z "$UUID" ]]; then
        log_error "Не удалось извлечь обязательные параметры (IP, PORT, UUID)"
        return 1
    fi

    log_success "VLESS URL успешно распарсен"
    echo ""
    log_info "Параметры Non-RU VPS:"
    echo "  IP:          $NON_RU_IP"
    echo "  Port:        $NON_RU_PORT"
    echo "  UUID:        $UUID"
    echo "  SNI:         ${SNI:-не указан}"
    echo "  Public Key:  ${PUBLIC_KEY:-не указан}"
    echo "  Short ID:    ${SHORT_ID:-не указан}"
    echo "  Fingerprint: ${FINGERPRINT:-chrome}"
    echo ""

    return 0
}

# ============================================
# Main Setup Function
# ============================================

ask_for_vless_url() {
    echo -e "${YELLOW}${BOLD}Вставьте vless:// ссылку на ваш Non-RU VPS:${NC}"
    echo -e "${CYAN}(Пример: vless://UUID@IP:PORT?type=tcp&security=reality&pbk=KEY&sni=SNI...)${NC}"
    echo ""
    read -r VLESS_URL

    if [[ -z "$VLESS_URL" ]]; then
        log_error "VLESS URL не может быть пустым"
        return 1
    fi

    echo ""
}

confirm_setup() {
    echo ""
    echo -e "${YELLOW}${BOLD}Подтвердите настройки:${NC}"
    echo "  1. RU VPS (этот сервер) → Non-RU VPS ($NON_RU_IP:$NON_RU_PORT)"
    echo "  2. Метод: Xray Fragment с автоподбором стратегий"
    echo "  3. Health Check: каждые 5 минут"
    echo ""

    read -p "Продолжить? (y/n): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Настройка отменена"
        return 1
    fi

    return 0
}

run_level3_setup() {
    log_info "Запуск Level 3 Advanced с методом Xray Fragment..."
    echo ""

    # Run level-3-advanced.sh
    if [[ -f "${SCRIPT_DIR}/level-3-advanced.sh" ]]; then
        "${SCRIPT_DIR}/level-3-advanced.sh" \
            --method xray-fragment \
            --non-ru-ip "$NON_RU_IP" \
            --non-ru-port "$NON_RU_PORT" \
            --auto-strategy
    else
        log_error "Скрипт level-3-advanced.sh не найден в $SCRIPT_DIR"
        return 1
    fi
}

create_client_guide() {
    log_info ""
    log_info "📱 Создание инструкции для клиента..."

    local guide_file="/root/client-connection-guide.txt"

    cat > "$guide_file" <<EOF
╔════════════════════════════════════════════════════════════════╗
║  Инструкция по подключению клиента                             ║
╚════════════════════════════════════════════════════════════════╝

✅ Level 3 DPI Bypass успешно настроен на вашем RU VPS!

📊 Архитектура:
   Клиент → RU VPS ($(hostname -I | awk '{print $1}')) → Non-RU VPS ($NON_RU_IP) → Internet
                        ↓
                 DPI обходится здесь!

🔗 Для подключения используйте ОДИН из вариантов:

═══════════════════════════════════════════════════════════════

ВАРИАНТ 1: Подключение к RU VPS (РЕКОМЕНДУЕТСЯ)
───────────────────────────────────────────────────────────────

📱 Создайте НОВОЕ соединение в вашем клиенте со следующими настройками:

  Протокол:    VLESS
  Адрес:       $(hostname -I | awk '{print $1}')
  Порт:        8443 (или ваш порт из 3x-ui)
  UUID:        [Ваш UUID из 3x-ui на RU VPS]
  Шифрование:  none
  Flow:        (оставить пустым)
  Network:     gRPC
  Security:    reality
  SNI:         web.max.ru
  Fingerprint: chrome
  Public Key:  [Ваш Public Key из 3x-ui на RU VPS]
  Short ID:    [Ваш Short ID из 3x-ui на RU VPS]

⚠️ Важно: Используйте UUID и ключи от ВАШЕГО RU VPS, не от Non-RU!

═══════════════════════════════════════════════════════════════

ВАРИАНТ 2: Прямое подключение к Non-RU VPS (без DPI bypass)
───────────────────────────────────────────────────────────────

📱 Используйте вашу оригинальную vless:// ссылку:

$VLESS_URL

⚠️ Внимание: Этот вариант может НЕ работать из-за блокировок DPI!

═══════════════════════════════════════════════════════════════

🤖 Автоматический подбор стратегий:

  • Health Check запускается каждые 5 минут
  • При падении соединения автоматически переключается стратегия
  • Логи: tail -f /var/log/dpi-health-check.log

📊 Мониторинг:

  • Статус x-ui:      systemctl status x-ui
  • Логи x-ui:        journalctl -u x-ui -f
  • Текущая стратегия: cat /var/run/current-dpi-strategy
  • Health Check:     tail -f /var/log/dpi-health-check.log

🔧 Управление:

  • Переключить стратегию: /opt/auto-strategy-selector.sh switch-next
  • Откат:                 cd /root/x-ui-settings-update/x-ui-tuning
                           ./rollback.sh [backup-file]

═══════════════════════════════════════════════════════════════

Дата настройки: $(date)
RU VPS IP:      $(hostname -I | awk '{print $1}')
Non-RU VPS IP:  $NON_RU_IP:$NON_RU_PORT

╚════════════════════════════════════════════════════════════════╝
EOF

    log_success "Инструкция сохранена: $guide_file"
    echo ""
    cat "$guide_file"
}

show_next_steps() {
    echo ""
    echo -e "${BOLD}${GREEN}✅ Level 3 успешно настроен!${NC}"
    echo ""
    echo -e "${YELLOW}📋 Следующие шаги:${NC}"
    echo ""
    echo "1. 📱 Настройте клиент для подключения к RU VPS"
    echo "   (инструкция выше и в /root/client-connection-guide.txt)"
    echo ""
    echo "2. 🧪 Протестируйте соединение"
    echo ""
    echo "3. 📊 Мониторинг:"
    echo "   tail -f /var/log/dpi-health-check.log"
    echo ""
    echo "4. 🔧 Управление стратегиями:"
    echo "   /opt/auto-strategy-selector.sh switch-next"
    echo ""
}

# ============================================
# Main
# ============================================

main() {
    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi

    print_header

    # Ask for VLESS URL
    ask_for_vless_url || exit 1

    # Parse URL
    parse_vless_url "$VLESS_URL" || exit 1

    # Confirm
    confirm_setup || exit 1

    # Run Level 3 setup
    run_level3_setup || exit 1

    # Create client guide
    create_client_guide

    # Show next steps
    show_next_steps
}

# Run if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
