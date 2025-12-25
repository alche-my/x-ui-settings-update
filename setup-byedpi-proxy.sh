#!/bin/bash

################################################################################
# ByeDPI Proxy Setup Script for 3x-ui
#
# Description: Automates the installation and configuration of ByeDPI
#              as a SOCKS5 proxy for DPI bypass on RU servers with 3x-ui
#
# Usage: sudo ./setup-byedpi-proxy.sh [OPTIONS]
#
# Options:
#   --non-ru-ip IP            Non-RU server IP address (required)
#   --non-ru-port PORT        Non-RU server port (default: 443)
#   --non-ru-uuid UUID        Non-RU server UUID (required for VLESS)
#   --byedpi-port PORT        ByeDPI SOCKS5 port (default: 1080)
#   --generate-uuid           Generate new UUID and exit
#   --non-interactive         Run without user prompts
#   --uninstall              Remove ByeDPI installation
#
################################################################################

set -euo pipefail

################################################################################
# GLOBAL VARIABLES
################################################################################

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"

# Directories
BYEDPI_DIR="/opt/byedpi"
BYEDPI_BIN="/usr/local/bin/ciadpi"
XRAY_CONFIG_DIR="/usr/local/x-ui/bin/config"
CONFIG_OUTPUT_DIR="/root/byedpi-config"

# Service
SERVICE_NAME="byedpi"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Logging
LOG_DIR="/var/log/byedpi"
LOG_FILE="${LOG_DIR}/setup.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration variables
NON_RU_IP=""
NON_RU_PORT="443"
NON_RU_UUID=""
BYEDPI_PORT="1080"
NON_INTERACTIVE=false
UNINSTALL=false

################################################################################
# LOGGING FUNCTIONS
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "${CYAN}${BOLD}==>${NC} $*" | tee -a "$LOG_FILE"
}

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-ru-ip)
                NON_RU_IP="$2"
                shift 2
                ;;
            --non-ru-port)
                NON_RU_PORT="$2"
                shift 2
                ;;
            --non-ru-uuid)
                NON_RU_UUID="$2"
                shift 2
                ;;
            --byedpi-port)
                BYEDPI_PORT="$2"
                shift 2
                ;;
            --generate-uuid)
                echo "$(generate_uuid)"
                exit 0
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --uninstall)
                UNINSTALL=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}[ERROR]${NC} Неизвестная опция: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help
show_help() {
    cat << EOF
${BOLD}ByeDPI Proxy Setup Script${NC}

${BOLD}Использование:${NC}
    sudo $SCRIPT_NAME [OPTIONS]

${BOLD}Опции:${NC}
    --non-ru-ip IP            IP адрес Non-RU сервера (обязательно)
    --non-ru-port PORT        Порт Non-RU сервера (по умолчанию: 443)
    --non-ru-uuid UUID        UUID Non-RU сервера для VLESS (обязательно)
    --byedpi-port PORT        Порт SOCKS5 прокси ByeDPI (по умолчанию: 1080)
    --generate-uuid           Сгенерировать UUID и выйти
    --non-interactive         Запуск без интерактивных запросов
    --uninstall              Удалить установку ByeDPI
    -h, --help               Показать эту справку

${BOLD}Примеры:${NC}
    # Сгенерировать UUID
    $SCRIPT_NAME --generate-uuid

    # Установка с параметрами
    sudo $SCRIPT_NAME --non-ru-ip 1.2.3.4 --non-ru-uuid "\$(./setup-byedpi-proxy.sh --generate-uuid)"

    # Или в две команды
    UUID=\$(./setup-byedpi-proxy.sh --generate-uuid)
    sudo $SCRIPT_NAME --non-ru-ip 1.2.3.4 --non-ru-uuid "\$UUID"

    # Интерактивная установка (скрипт спросит все параметры)
    sudo $SCRIPT_NAME

    # Удаление
    sudo $SCRIPT_NAME --uninstall

EOF
}

# Generate UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# Interactive prompt for missing parameters
prompt_params() {
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        return
    fi

    echo ""
    log_info "Интерактивная настройка параметров"
    echo ""

    # Prompt for IP address
    while [[ -z "$NON_RU_IP" ]]; do
        read -p "Введите IP адрес Non-RU сервера: " NON_RU_IP
        if [[ -z "$NON_RU_IP" ]]; then
            echo -e "${RED}Ошибка: IP адрес не может быть пустым${NC}"
        fi
    done

    # Prompt for UUID
    if [[ -z "$NON_RU_UUID" ]]; then
        echo ""
        echo -e "${YELLOW}UUID для Non-RU сервера${NC}"
        echo "Это UUID, который используется на вашем Non-RU сервере для VLESS подключения"
        echo ""
        echo "Опции:"
        echo "  1) Ввести существующий UUID с Non-RU сервера"
        echo "  2) Сгенерировать новый UUID (затем добавьте его на Non-RU сервер)"
        echo ""

        local uuid_choice
        while [[ -z "$uuid_choice" || ! "$uuid_choice" =~ ^[12]$ ]]; do
            read -p "Выберите [1-2]: " uuid_choice
            if [[ ! "$uuid_choice" =~ ^[12]$ ]]; then
                echo -e "${RED}Ошибка: Выберите 1 или 2${NC}"
            fi
        done

        if [[ "$uuid_choice" == "2" ]]; then
            NON_RU_UUID=$(generate_uuid)
            echo ""
            log_success "Сгенерирован новый UUID: $NON_RU_UUID"
            echo ""
            log_warn "ВАЖНО: Добавьте этот UUID на ваш Non-RU сервер в настройках VLESS!"
            echo ""
            read -p "Нажмите Enter для продолжения..."
        else
            while [[ -z "$NON_RU_UUID" ]]; do
                read -p "Введите UUID с Non-RU сервера: " NON_RU_UUID
                if [[ -z "$NON_RU_UUID" ]]; then
                    echo -e "${RED}Ошибка: UUID не может быть пустым${NC}"
                    echo "Пример: $(generate_uuid)"
                fi
            done
        fi
    fi

    read -p "Порт Non-RU сервера [${NON_RU_PORT}]: " input_port
    NON_RU_PORT="${input_port:-$NON_RU_PORT}"

    read -p "Порт SOCKS5 прокси ByeDPI [${BYEDPI_PORT}]: " input_byedpi
    BYEDPI_PORT="${input_byedpi:-$BYEDPI_PORT}"
}

# Validate parameters
validate_params() {
    if [[ -z "$NON_RU_IP" ]]; then
        log_error "IP адрес Non-RU сервера обязателен"
        exit 1
    fi

    if [[ -z "$NON_RU_UUID" ]]; then
        log_error "UUID Non-RU сервера обязателен"
        exit 1
    fi

    # Validate IP format
    if ! [[ "$NON_RU_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Неверный формат IP адреса: $NON_RU_IP"
        exit 1
    fi

    # Validate UUID format
    if ! [[ "$NON_RU_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        log_error "Неверный формат UUID: $NON_RU_UUID"
        echo ""
        echo -e "${YELLOW}Пример правильного UUID:${NC} $(generate_uuid)"
        echo ""
        echo -e "${CYAN}Сгенерировать новый UUID:${NC}"
        echo "  $SCRIPT_NAME --generate-uuid"
        echo ""
        exit 1
    fi
}

################################################################################
# INSTALLATION FUNCTIONS
################################################################################

# Install dependencies
install_dependencies() {
    log_step "Установка зависимостей..."

    apt-get update -qq
    apt-get install -y -qq \
        build-essential \
        git \
        curl \
        jq \
        || {
            log_error "Не удалось установить зависимости"
            exit 1
        }

    log_success "Зависимости установлены"
}

# Clone and compile ByeDPI
install_byedpi() {
    log_step "Установка ByeDPI..."

    # Remove old installation if exists
    if [[ -d "$BYEDPI_DIR" ]]; then
        log_warn "Удаление старой установки ByeDPI..."
        rm -rf "$BYEDPI_DIR"
    fi

    # Clone repository
    log_info "Клонирование репозитория ByeDPI..."
    git clone https://github.com/hufrea/byedpi.git "$BYEDPI_DIR" 2>&1 | tee -a "$LOG_FILE" || {
        log_error "Не удалось клонировать репозиторий ByeDPI"
        exit 1
    }

    # Compile
    log_info "Компиляция ByeDPI..."
    cd "$BYEDPI_DIR"
    make 2>&1 | tee -a "$LOG_FILE" || {
        log_error "Не удалось скомпилировать ByeDPI"
        exit 1
    }

    # Install binary
    log_info "Установка бинарного файла..."
    cp "$BYEDPI_DIR/ciadpi" "$BYEDPI_BIN"
    chmod +x "$BYEDPI_BIN"

    log_success "ByeDPI установлен в $BYEDPI_BIN"
}

# Create systemd service
create_systemd_service() {
    log_step "Создание systemd сервиса..."

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=ByeDPI SOCKS5 Proxy for DPI Bypass
After=network.target
Documentation=https://github.com/hufrea/byedpi

[Service]
Type=simple
User=root
ExecStart=$BYEDPI_BIN --ip 127.0.0.1 --port $BYEDPI_PORT --disorder 1 --split 2 --tlsrec 1+s --auto=torst
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=byedpi

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/byedpi

[Install]
WantedBy=multi-user.target
EOF

    log_success "Systemd сервис создан: $SERVICE_FILE"
}

# Start and enable service
start_service() {
    log_step "Запуск ByeDPI сервиса..."

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" 2>&1 | tee -a "$LOG_FILE"
    systemctl start "$SERVICE_NAME" 2>&1 | tee -a "$LOG_FILE"

    # Wait a bit for service to start
    sleep 2

    # Check service status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "ByeDPI сервис запущен и работает"
    else
        log_error "ByeDPI сервис не запустился"
        systemctl status "$SERVICE_NAME" --no-pager | tee -a "$LOG_FILE"
        exit 1
    fi
}

# Generate Xray configuration
generate_xray_config() {
    log_step "Генерация конфигурации Xray..."

    mkdir -p "$CONFIG_OUTPUT_DIR"

    # Generate outbound configuration
    cat > "$CONFIG_OUTPUT_DIR/xray-outbound-config.json" << EOF
{
  "outbounds": [
    {
      "tag": "non-ru-via-byedpi",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$NON_RU_IP",
            "port": $NON_RU_PORT,
            "users": [
              {
                "id": "$NON_RU_UUID",
                "encryption": "none",
                "flow": ""
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "",
          "allowInsecure": false
        }
      },
      "proxySettings": {
        "tag": "byedpi-socks"
      }
    },
    {
      "tag": "byedpi-socks",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": $BYEDPI_PORT
          }
        ]
      }
    }
  ]
}
EOF

    log_success "Конфигурация Xray сохранена в $CONFIG_OUTPUT_DIR/xray-outbound-config.json"
}

# Generate instructions
generate_instructions() {
    log_step "Создание инструкций по настройке..."

    cat > "$CONFIG_OUTPUT_DIR/SETUP-INSTRUCTIONS.md" << 'EOF'
# Инструкция по настройке 3x-ui с ByeDPI

## 📋 Что было установлено

1. **ByeDPI SOCKS5 прокси** запущен на порту `{BYEDPI_PORT}`
2. **Systemd сервис** настроен и работает
3. **Конфигурация Xray** сгенерирована

## 🔧 Настройка 3x-ui через веб-интерфейс

### Вариант 1: Через JSON конфигурацию (рекомендуется)

1. Откройте веб-панель 3x-ui
2. Перейдите в **Xray Configuration** или **Config**
3. Найдите секцию `"outbounds": [...]`
4. Добавьте содержимое файла `xray-outbound-config.json` в массив outbounds

### Вариант 2: Через веб-интерфейс 3x-ui вручную

#### Шаг 1: Создать SOCKS5 Outbound для ByeDPI

1. В панели 3x-ui перейдите в **Outbounds**
2. Нажмите **Add Outbound**
3. Заполните:
   - **Tag**: `byedpi-socks`
   - **Protocol**: `SOCKS`
   - **Address**: `127.0.0.1`
   - **Port**: `{BYEDPI_PORT}`
4. Сохраните

#### Шаг 2: Создать VLESS Outbound через ByeDPI

1. Снова нажмите **Add Outbound**
2. Заполните:
   - **Tag**: `non-ru-via-byedpi`
   - **Protocol**: `VLESS`
   - **Address**: `{NON_RU_IP}`
   - **Port**: `{NON_RU_PORT}`
   - **UUID**: `{NON_RU_UUID}`
   - **Encryption**: `none`
   - **Network**: `tcp`
   - **Security**: `tls`
3. В разделе **Proxy Settings**:
   - **Tag**: `byedpi-socks`
4. Сохраните

#### Шаг 3: Настроить роутинг

1. Перейдите в **Routing Rules**
2. Создайте правило для направления трафика через `non-ru-via-byedpi`
3. Или используйте этот outbound как **default outbound**

## ✅ Проверка работоспособности

### Проверка ByeDPI сервиса

```bash
# Проверить статус
sudo systemctl status byedpi

# Проверить логи
sudo journalctl -u byedpi -f

# Проверить, что SOCKS5 работает
curl --socks5 127.0.0.1:{BYEDPI_PORT} https://www.google.com
```

### Проверка Xray

```bash
# Перезапустить 3x-ui
sudo systemctl restart x-ui

# Проверить статус
sudo systemctl status x-ui

# Проверить логи Xray
sudo journalctl -u x-ui -f
```

## 🔍 Диагностика проблем

### ByeDPI не запускается

```bash
# Проверить логи
sudo journalctl -u byedpi --no-pager -n 50

# Проверить, что порт свободен
sudo netstat -tlnp | grep {BYEDPI_PORT}

# Перезапустить сервис
sudo systemctl restart byedpi
```

### Xray не подключается через ByeDPI

1. Убедитесь, что в конфигурации Xray указан правильный `proxySettings.tag`
2. Проверьте, что ByeDPI работает: `systemctl status byedpi`
3. Проверьте логи Xray: `journalctl -u x-ui -f`

## ⚙️ Настройка параметров ByeDPI

Если стандартные параметры не работают, отредактируйте `/etc/systemd/system/byedpi.service`:

```bash
sudo nano /etc/systemd/system/byedpi.service
```

Измените строку `ExecStart` с разными параметрами:

### Для мобильных операторов:
```
ExecStart=/usr/local/bin/ciadpi --port {BYEDPI_PORT} --split 2 --disorder 1 --fake
```

### Для проводных провайдеров:
```
ExecStart=/usr/local/bin/ciadpi --port {BYEDPI_PORT} --tlsrec 1+s --split-pos 2
```

### Агрессивный режим:
```
ExecStart=/usr/local/bin/ciadpi --port {BYEDPI_PORT} --disorder 3 --split 3 --tlsrec 1+s --fake --auto=torst
```

После изменений:
```bash
sudo systemctl daemon-reload
sudo systemctl restart byedpi
```

## 📝 Файлы конфигурации

- Systemd сервис: `/etc/systemd/system/byedpi.service`
- Бинарный файл: `/usr/local/bin/ciadpi`
- Логи: `journalctl -u byedpi`
- Конфигурация Xray: `{CONFIG_OUTPUT_DIR}/xray-outbound-config.json`

## 🔄 Управление сервисом

```bash
# Запустить
sudo systemctl start byedpi

# Остановить
sudo systemctl stop byedpi

# Перезапустить
sudo systemctl restart byedpi

# Посмотреть статус
sudo systemctl status byedpi

# Включить автозапуск
sudo systemctl enable byedpi

# Отключить автозапуск
sudo systemctl disable byedpi
```

## 📚 Дополнительные ресурсы

- GitHub ByeDPI: https://github.com/hufrea/byedpi
- GitHub 3x-ui: https://github.com/MHSanaei/3x-ui
- Xray Documentation: https://xtls.github.io/
EOF

    # Replace placeholders
    sed -i "s/{BYEDPI_PORT}/$BYEDPI_PORT/g" "$CONFIG_OUTPUT_DIR/SETUP-INSTRUCTIONS.md"
    sed -i "s/{NON_RU_IP}/$NON_RU_IP/g" "$CONFIG_OUTPUT_DIR/SETUP-INSTRUCTIONS.md"
    sed -i "s/{NON_RU_PORT}/$NON_RU_PORT/g" "$CONFIG_OUTPUT_DIR/SETUP-INSTRUCTIONS.md"
    sed -i "s/{NON_RU_UUID}/$NON_RU_UUID/g" "$CONFIG_OUTPUT_DIR/SETUP-INSTRUCTIONS.md"
    sed -i "s|{CONFIG_OUTPUT_DIR}|$CONFIG_OUTPUT_DIR|g" "$CONFIG_OUTPUT_DIR/SETUP-INSTRUCTIONS.md"

    log_success "Инструкции сохранены в $CONFIG_OUTPUT_DIR/SETUP-INSTRUCTIONS.md"
}

# Test ByeDPI connection
test_byedpi() {
    log_step "Тестирование ByeDPI SOCKS5 прокси..."

    if command -v curl &> /dev/null; then
        log_info "Попытка подключения через ByeDPI..."
        if timeout 10 curl -s --socks5 "127.0.0.1:$BYEDPI_PORT" https://www.google.com > /dev/null 2>&1; then
            log_success "ByeDPI SOCKS5 прокси работает корректно"
        else
            log_warn "Не удалось подключиться через ByeDPI (это нормально на данном этапе)"
            log_warn "ByeDPI будет работать после настройки роутинга к Non-RU серверу"
        fi
    else
        log_warn "curl не установлен, пропуск теста"
    fi
}

################################################################################
# UNINSTALLATION FUNCTIONS
################################################################################

uninstall_byedpi() {
    log_step "Удаление ByeDPI..."

    # Stop and disable service
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "Остановка сервиса..."
        systemctl stop "$SERVICE_NAME"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_info "Отключение автозапуска..."
        systemctl disable "$SERVICE_NAME"
    fi

    # Remove service file
    if [[ -f "$SERVICE_FILE" ]]; then
        log_info "Удаление systemd сервиса..."
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    # Remove binary
    if [[ -f "$BYEDPI_BIN" ]]; then
        log_info "Удаление бинарного файла..."
        rm -f "$BYEDPI_BIN"
    fi

    # Remove source directory
    if [[ -d "$BYEDPI_DIR" ]]; then
        log_info "Удаление исходников..."
        rm -rf "$BYEDPI_DIR"
    fi

    # Remove config directory
    if [[ -d "$CONFIG_OUTPUT_DIR" ]]; then
        log_info "Удаление конфигурации..."
        rm -rf "$CONFIG_OUTPUT_DIR"
    fi

    log_success "ByeDPI полностью удален"
}

################################################################################
# MAIN FUNCTION
################################################################################

main() {
    # Setup logging
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"

    log_info "=== ByeDPI Setup Script v${SCRIPT_VERSION} ==="
    log_info "Время запуска: $(date)"

    # Check root
    check_root

    # Parse arguments
    parse_args "$@"

    # Handle uninstall
    if [[ "$UNINSTALL" == "true" ]]; then
        uninstall_byedpi
        log_success "Удаление завершено"
        exit 0
    fi

    # Prompt for missing parameters
    prompt_params

    # Validate parameters
    validate_params

    # Show configuration
    log_info "Конфигурация:"
    log_info "  Non-RU IP: $NON_RU_IP"
    log_info "  Non-RU Port: $NON_RU_PORT"
    log_info "  Non-RU UUID: $NON_RU_UUID"
    log_info "  ByeDPI Port: $BYEDPI_PORT"

    # Install
    install_dependencies
    install_byedpi
    create_systemd_service
    start_service
    generate_xray_config
    generate_instructions
    test_byedpi

    # Final message
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║  ✓ ByeDPI успешно установлен и запущен!                   ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_success "SOCKS5 прокси работает на порту: $BYEDPI_PORT"
    log_success "Конфигурация сохранена в: $CONFIG_OUTPUT_DIR"
    echo ""
    log_info "📖 Следующие шаги:"
    echo -e "   1. Прочитайте инструкцию: ${CYAN}$CONFIG_OUTPUT_DIR/SETUP-INSTRUCTIONS.md${NC}"
    echo -e "   2. Настройте 3x-ui используя: ${CYAN}$CONFIG_OUTPUT_DIR/xray-outbound-config.json${NC}"
    echo -e "   3. Перезапустите 3x-ui: ${YELLOW}sudo systemctl restart x-ui${NC}"
    echo ""
    log_info "📊 Полезные команды:"
    echo -e "   Статус ByeDPI: ${YELLOW}sudo systemctl status byedpi${NC}"
    echo -e "   Логи ByeDPI:   ${YELLOW}sudo journalctl -u byedpi -f${NC}"
    echo ""
}

################################################################################
# SCRIPT ENTRY POINT
################################################################################

main "$@"
