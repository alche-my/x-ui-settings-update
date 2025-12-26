#!/bin/bash

################################################################################
# ByeDPI Standalone Installer
#
# Быстрая установка только ByeDPI (без конфигурации 3x-ui)
#
# Usage: sudo ./install-byedpi-only.sh
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

BYEDPI_REPO="https://github.com/hufrea/byedpi.git"
BYEDPI_DIR="/opt/byedpi"
BYEDPI_PORT="1080"

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

install_dependencies() {
    log_step "Установка зависимостей..."

    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq gcc make git curl
    elif command -v yum &> /dev/null; then
        yum install -y gcc make git curl
    else
        log_error "Неподдерживаемый менеджер пакетов"
        exit 1
    fi

    log_success "Зависимости установлены"
}

install_byedpi() {
    log_step "Установка ByeDPI..."

    # Удалить старую версию если есть
    if [[ -d "$BYEDPI_DIR" ]]; then
        log_warn "Удаляем старую установку..."
        rm -rf "$BYEDPI_DIR"
    fi

    # Clone repository
    log_info "Клонирование репозитория..."
    git clone "$BYEDPI_REPO" "$BYEDPI_DIR" --quiet

    # Compile
    log_info "Компиляция ByeDPI..."
    cd "$BYEDPI_DIR"
    make

    # Install binary
    log_info "Установка бинарника..."
    cp ciadpi /usr/local/bin/
    chmod +x /usr/local/bin/ciadpi

    log_success "ByeDPI установлен в /usr/local/bin/ciadpi"
}

create_byedpi_service() {
    log_step "Создание systemd сервиса..."

    cat > /etc/systemd/system/byedpi.service << EOF
[Unit]
Description=ByeDPI SOCKS5 Proxy for DPI Bypass
Documentation=https://github.com/hufrea/byedpi
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ciadpi --ip 127.0.0.1 --port $BYEDPI_PORT --oob 1 --disorder 1 --auto=torst
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable byedpi
    systemctl restart byedpi

    sleep 2

    if systemctl is-active --quiet byedpi; then
        log_success "ByeDPI сервис запущен"
    else
        log_error "Не удалось запустить ByeDPI"
        log_info "Проверьте логи: journalctl -u byedpi -n 50"
        exit 1
    fi
}

test_byedpi() {
    log_step "Тестирование ByeDPI..."

    echo ""
    echo "Проверка 1: Статус сервиса"
    systemctl status byedpi --no-pager | head -5
    echo ""

    echo "Проверка 2: Порт 1080"
    if netstat -tln 2>/dev/null | grep -q ":1080" || lsof -i :1080 2>/dev/null | grep -q ciadpi; then
        log_success "Порт 1080 прослушивается"
    else
        log_error "Порт 1080 НЕ прослушивается"
    fi
    echo ""

    echo "Проверка 3: SOCKS5 прокси"
    if timeout 10 curl --socks5 127.0.0.1:1080 -s https://ifconfig.me > /dev/null 2>&1; then
        log_success "SOCKS5 прокси работает!"
        echo "Ваш IP через ByeDPI: $(curl --socks5 127.0.0.1:1080 -s https://ifconfig.me)"
    else
        log_warn "SOCKS5 не отвечает (это нормально, если DPI блокирует)"
    fi
    echo ""
}

show_instructions() {
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║  ✓ ByeDPI успешно установлен!                            ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "Управление сервисом:"
    echo "  sudo systemctl status byedpi   - статус"
    echo "  sudo systemctl restart byedpi  - перезапуск"
    echo "  sudo systemctl stop byedpi     - остановка"
    echo "  sudo journalctl -u byedpi -f   - логи в реальном времени"
    echo ""

    log_info "Тестирование:"
    echo "  curl --socks5 127.0.0.1:1080 https://google.com"
    echo "  curl --socks5 127.0.0.1:1080 https://ifconfig.me"
    echo ""

    log_info "Следующие шаги:"
    echo "1. Запустите тестирование стратегий:"
    echo -e "   ${YELLOW}curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/test-byedpi-strategies.sh | sudo bash${NC}"
    echo ""
    echo "2. Или настройте 3x-ui интеграцию:"
    echo -e "   ${YELLOW}curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/install-byedpi-3xui.sh | sudo bash${NC}"
    echo ""
}

main() {
    echo ""
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  ByeDPI Standalone Installer                              ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_root
    install_dependencies
    install_byedpi
    create_byedpi_service
    test_byedpi
    show_instructions
}

main "$@"
