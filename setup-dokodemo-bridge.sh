#!/bin/bash

################################################################################
# Dokodemo-door Bridge Setup Script for 3x-ui
#
# Description: Automates the setup of a Russian VPS as a bridge using
#              Dokodemo-door inbounds to proxy traffic to Finnish servers
#
# Usage: sudo ./setup-dokodemo-bridge.sh [--config config.json]
################################################################################

set -euo pipefail

################################################################################
# GLOBAL VARIABLES
################################################################################

SCRIPT_VERSION="1.0.0"
XUI_INSTALL_URL="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
XUI_DIR="/usr/local/x-ui"
XUI_PROCESS="x-ui"

# Default API settings
DEFAULT_PANEL_URL="http://localhost:2053"
DEFAULT_USERNAME="admin"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Arrays to store server configurations
declare -a SERVER_NAMES=()
declare -a SERVER_IPS=()
declare -a SERVER_PORTS=()
declare -a LOCAL_PORTS=()
declare -a INBOUND_STATUS=()
declare -a CREATED_INBOUND_IDS=()

# API credentials
PANEL_URL=""
API_USERNAME=""
API_PASSWORD=""
SESSION_COOKIE=""

# Config file mode
CONFIG_FILE=""

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Print colored messages
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_header() {
    echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}\n"
}

# Exit with error message
die() {
    print_error "$1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Этот скрипт должен быть запущен с правами root (используйте sudo)"
    fi
}

# Detect OS for package management
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        die "Не удалось определить операционную систему"
    fi

    print_info "Обнаружена ОС: $OS $OS_VERSION"
}

# Install required dependencies
install_dependencies() {
    print_header "Проверка зависимостей"

    local packages_to_install=()

    # Check for curl
    if ! command -v curl &> /dev/null; then
        print_warning "curl не установлен"
        packages_to_install+=("curl")
    else
        print_success "curl установлен"
    fi

    # Check for jq
    if ! command -v jq &> /dev/null; then
        print_warning "jq не установлен"
        packages_to_install+=("jq")
    else
        print_success "jq установлен"
    fi

    # Check for sqlite3
    if ! command -v sqlite3 &> /dev/null; then
        print_warning "sqlite3 не установлен"
        packages_to_install+=("sqlite3")
    else
        print_success "sqlite3 установлен"
    fi

    # Install missing packages
    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        print_info "Установка недостающих пакетов: ${packages_to_install[*]}"

        case "$OS" in
            ubuntu|debian)
                apt-get update -qq
                apt-get install -y -qq "${packages_to_install[@]}"
                ;;
            centos|rhel)
                yum install -y -q "${packages_to_install[@]}"
                ;;
            *)
                die "Неподдерживаемая ОС для автоматической установки зависимостей"
                ;;
        esac

        print_success "Зависимости установлены"
    else
        print_success "Все зависимости уже установлены"
    fi
}

################################################################################
# 3X-UI INSTALLATION FUNCTIONS
################################################################################

# Check if 3x-ui is installed
check_xui_installed() {
    if [[ -d "$XUI_DIR" ]] || pgrep -x "$XUI_PROCESS" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Get 3x-ui version
get_xui_version() {
    if [[ -f "$XUI_DIR/bin/xray-linux-amd64" ]]; then
        "$XUI_DIR/bin/xray-linux-amd64" --version 2>/dev/null | head -1 || echo "Unknown"
    else
        echo "Unknown"
    fi
}

# Install 3x-ui
install_xui() {
    print_header "Установка 3x-ui"

    print_info "Загрузка установочного скрипта с $XUI_INSTALL_URL"
    print_warning "Этот процесс может занять несколько минут..."

    if bash <(curl -Ls "$XUI_INSTALL_URL"); then
        print_success "3x-ui успешно установлен"

        # Wait for service to start
        sleep 3

        # Verify installation
        if check_xui_installed; then
            print_success "Установка проверена"
            print_warning "ВАЖНО: Рекомендуется сменить дефолтный пароль 3x-ui!"
            return 0
        else
            print_error "Установка не подтверждена"
            return 1
        fi
    else
        print_error "Ошибка при установке 3x-ui"
        return 1
    fi
}

# Check and optionally install 3x-ui
check_and_install_xui() {
    print_header "Проверка 3x-ui"

    if check_xui_installed; then
        local version=$(get_xui_version)
        print_success "3x-ui уже установлен"
        print_info "Версия: $version"
        return 0
    else
        print_warning "3x-ui не обнаружен"

        # Ask user if they want to install
        read -p "Установить 3x-ui сейчас? (y/n): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_xui || die "Не удалось установить 3x-ui"
        else
            die "3x-ui требуется для работы скрипта. Установка отменена."
        fi
    fi
}

################################################################################
# VALIDATION FUNCTIONS
################################################################################

# Validate IPv4 address
validate_ipv4() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        [[ ${ADDR[0]} -le 255 && ${ADDR[1]} -le 255 && ${ADDR[2]} -le 255 && ${ADDR[3]} -le 255 ]]
        stat=$?
    fi

    return $stat
}

# Validate IPv6 address (basic check)
validate_ipv6() {
    local ip=$1
    [[ $ip =~ ^([0-9a-fA-F]{0,4}:){7}[0-9a-fA-F]{0,4}$ ]]
    return $?
}

# Validate IP address (IPv4 or IPv6)
validate_ip() {
    local ip=$1

    if validate_ipv4 "$ip" || validate_ipv6 "$ip"; then
        return 0
    else
        return 1
    fi
}

# Validate port number
validate_port() {
    local port=$1

    if [[ $port =~ ^[0-9]+$ ]] && [[ $port -ge 1 ]] && [[ $port -le 65535 ]]; then
        return 0
    else
        return 1
    fi
}

# Check if port is already used in our configuration
check_port_conflict() {
    local port=$1

    for used_port in "${LOCAL_PORTS[@]}"; do
        if [[ "$used_port" == "$port" ]]; then
            return 1
        fi
    done

    return 0
}

################################################################################
# INTERACTIVE INPUT FUNCTIONS
################################################################################

# Get number of servers to configure
get_server_count() {
    local count

    while true; do
        read -p "Сколько финских серверов нужно настроить? (1-20): " count

        if [[ $count =~ ^[0-9]+$ ]] && [[ $count -ge 1 ]] && [[ $count -le 20 ]]; then
            echo "$count"
            return 0
        else
            print_error "Введите число от 1 до 20"
        fi
    done
}

# Get server configuration from user
get_server_config() {
    local server_num=$1
    local name ip port local_port

    print_header "Настройка сервера #$server_num"

    # Get server name
    while true; do
        read -p "Название/описание (например: Finland-Helsinki-1): " name

        if [[ -n "$name" ]]; then
            break
        else
            print_error "Название не может быть пустым"
        fi
    done

    # Get IP address
    while true; do
        read -p "IP-адрес финского сервера: " ip

        if validate_ip "$ip"; then
            break
        else
            print_error "Неверный формат IP-адреса"
        fi
    done

    # Get remote port
    while true; do
        read -p "Порт на финском сервере (обычно 443): " port

        if validate_port "$port"; then
            break
        else
            print_error "Неверный порт (должен быть от 1 до 65535)"
        fi
    done

    # Get local listening port
    while true; do
        read -p "Порт для прослушивания на этом VPS (например: 443, 8443, 2053): " local_port

        if ! validate_port "$local_port"; then
            print_error "Неверный порт (должен быть от 1 до 65535)"
            continue
        fi

        if ! check_port_conflict "$local_port"; then
            print_error "Порт $local_port уже используется в конфигурации другого сервера"
            continue
        fi

        break
    done

    # Store configuration
    SERVER_NAMES+=("$name")
    SERVER_IPS+=("$ip")
    SERVER_PORTS+=("$port")
    LOCAL_PORTS+=("$local_port")

    print_success "Конфигурация сервера #$server_num сохранена"
}

# Get API credentials
get_api_credentials() {
    print_header "Настройка доступа к 3x-ui"

    # Get panel URL
    read -p "URL панели 3x-ui (по умолчанию $DEFAULT_PANEL_URL): " PANEL_URL
    PANEL_URL=${PANEL_URL:-$DEFAULT_PANEL_URL}

    # Get username
    read -p "Логин администратора (по умолчанию $DEFAULT_USERNAME): " API_USERNAME
    API_USERNAME=${API_USERNAME:-$DEFAULT_USERNAME}

    # Get password (hidden input)
    while true; do
        read -s -p "Пароль администратора: " API_PASSWORD
        echo

        if [[ -n "$API_PASSWORD" ]]; then
            break
        else
            print_error "Пароль не может быть пустым"
        fi
    done

    print_success "Учетные данные сохранены"
}

# Collect all configuration interactively
collect_configuration() {
    print_header "Интерактивная настройка"

    # Get number of servers
    local server_count=$(get_server_count)

    # Get configuration for each server
    for ((i=1; i<=server_count; i++)); do
        get_server_config "$i"
    done

    # Get API credentials
    get_api_credentials
}

################################################################################
# 3X-UI API FUNCTIONS
################################################################################

# Login to 3x-ui API and get session cookie
api_login() {
    print_info "Аутентификация в 3x-ui API..."

    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" -X POST "${PANEL_URL}/login" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${API_USERNAME}\",\"password\":\"${API_PASSWORD}\"}" \
        -c /tmp/xui-cookie.txt)

    http_code=$(echo "$response" | tail -1)

    if [[ "$http_code" -eq 200 ]]; then
        # Extract session cookie
        if [[ -f /tmp/xui-cookie.txt ]]; then
            SESSION_COOKIE=$(grep -oP '(?<=3x-ui\s)[^\s]+' /tmp/xui-cookie.txt || echo "")

            if [[ -n "$SESSION_COOKIE" ]]; then
                print_success "Успешная аутентификация"
                return 0
            fi
        fi

        print_error "Не удалось получить сессию"
        return 1
    else
        print_error "Ошибка аутентификации (HTTP $http_code)"
        print_error "Проверьте URL, логин и пароль"
        return 1
    fi
}

# Create Dokodemo-door inbound via API
create_dokodemo_inbound() {
    local name=$1
    local remote_ip=$2
    local remote_port=$3
    local local_port=$4

    print_info "Создание inbound: Dokodemo -> $name"

    # Prepare settings as JSON string (3x-ui API requirement)
    local settings_json=$(jq -n \
        --arg address "$remote_ip" \
        --argjson port "$remote_port" \
        '{
            address: $address,
            port: $port,
            network: "tcp,udp"
        }' | jq -c .)

    # Prepare streamSettings as JSON string (3x-ui API requirement)
    local stream_settings_json=$(jq -n \
        '{
            network: "tcp",
            security: "none"
        }' | jq -c .)

    # Prepare sniffing as JSON string (3x-ui API requirement)
    local sniffing_json=$(jq -n \
        '{
            enabled: true,
            destOverride: ["http", "tls"]
        }' | jq -c .)

    # Prepare final JSON payload with stringified fields
    local json_payload=$(jq -n \
        --arg remark "Dokodemo -> $name" \
        --arg listen "0.0.0.0" \
        --argjson port "$local_port" \
        --arg protocol "dokodemo-door" \
        --arg settings "$settings_json" \
        --arg streamSettings "$stream_settings_json" \
        --arg sniffing "$sniffing_json" \
        '{
            enable: true,
            remark: $remark,
            listen: $listen,
            port: $port,
            protocol: $protocol,
            settings: $settings,
            streamSettings: $streamSettings,
            sniffing: $sniffing
        }')

    # Make API request
    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" -X POST "${PANEL_URL}/panel/api/inbounds/add" \
        -H "Content-Type: application/json" \
        -H "Cookie: 3x-ui=${SESSION_COOKIE}" \
        -d "$json_payload")

    http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -n -1)

    if [[ "$http_code" -eq 200 ]]; then
        # Check if response indicates success
        local success=$(echo "$body" | jq -r '.success // false' 2>/dev/null || echo "false")

        if [[ "$success" == "true" ]]; then
            print_success "Inbound успешно создан"

            # Try to extract inbound ID if available
            local inbound_id=$(echo "$body" | jq -r '.obj.id // "N/A"' 2>/dev/null || echo "N/A")
            CREATED_INBOUND_IDS+=("$inbound_id")

            return 0
        else
            local msg=$(echo "$body" | jq -r '.msg // "Unknown error"' 2>/dev/null || echo "Unknown error")
            print_error "API вернул ошибку: $msg"
            return 1
        fi
    else
        print_error "HTTP ошибка: $http_code"
        return 1
    fi
}

# Create all configured inbounds
create_all_inbounds() {
    print_header "Создание Dokodemo-door inbound'ов"

    # Login first
    if ! api_login; then
        die "Не удалось аутентифицироваться в 3x-ui API"
    fi

    # Create each inbound
    local total=${#SERVER_NAMES[@]}

    for ((i=0; i<total; i++)); do
        echo
        print_info "Обработка сервера $((i+1))/$total..."

        if create_dokodemo_inbound \
            "${SERVER_NAMES[$i]}" \
            "${SERVER_IPS[$i]}" \
            "${SERVER_PORTS[$i]}" \
            "${LOCAL_PORTS[$i]}"; then
            INBOUND_STATUS+=("success")
        else
            INBOUND_STATUS+=("failed")
            print_warning "Продолжаем с оставшимися серверами..."
        fi
    done

    # Cleanup cookie file
    rm -f /tmp/xui-cookie.txt
}

# Configure DNS in Xray config via database
configure_dns() {
    print_header "Настройка DNS для Xray"

    local db_file="/etc/x-ui/x-ui.db"
    local config_file="/usr/local/x-ui/bin/config.json"

    # Check if database exists
    if [[ ! -f "$db_file" ]]; then
        print_warning "База данных x-ui не найдена: $db_file"
        print_info "DNS будет настроен при следующей конфигурации через панель"
        return 0
    fi

    # Check if sqlite3 is available
    if ! command -v sqlite3 &> /dev/null; then
        print_warning "sqlite3 не установлен, пропускаем настройку DNS"
        return 0
    fi

    # Check current DNS configuration in database
    local current_dns=$(sqlite3 "$db_file" "SELECT value FROM settings WHERE key='xrayTemplateConfig';" 2>/dev/null)

    if echo "$current_dns" | jq -e '.dns.servers[]?' &>/dev/null; then
        print_success "DNS уже настроен в базе данных"
        return 0
    fi

    print_info "Добавление DNS конфигурации в базу данных..."

    # Stop x-ui to safely modify database
    print_info "Остановка x-ui..."
    systemctl stop x-ui
    sleep 2

    # Get current config template from database
    local current_config=$(sqlite3 "$db_file" "SELECT value FROM settings WHERE key='xrayTemplateConfig';" 2>/dev/null)

    if [[ -z "$current_config" ]] || [[ "$current_config" == "null" ]]; then
        # No template exists, create one from current config
        if [[ -f "$config_file" ]]; then
            current_config=$(cat "$config_file")
        else
            print_warning "Не найден шаблон конфигурации"
            systemctl start x-ui
            return 0
        fi
    fi

    # Add DNS to config
    local new_config=$(echo "$current_config" | jq '. + {
        "dns": {
            "servers": [
                "1.1.1.1",
                "8.8.8.8",
                "https://dns.google/dns-query"
            ],
            "queryStrategy": "UseIP",
            "tag": "dns_inbound"
        }
    }')

    if [[ $? -ne 0 ]] || [[ -z "$new_config" ]]; then
        print_error "Ошибка при обработке JSON"
        systemctl start x-ui
        return 1
    fi

    # Escape single quotes for SQL
    new_config=$(echo "$new_config" | sed "s/'/''/g")

    # Update database
    sqlite3 "$db_file" "UPDATE settings SET value='$new_config' WHERE key='xrayTemplateConfig';" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "DNS конфигурация добавлена в базу данных"
    else
        print_error "Ошибка при обновлении базы данных"
        systemctl start x-ui
        return 1
    fi

    # Start x-ui
    print_info "Запуск x-ui..."
    systemctl start x-ui

    # Wait for service to start
    sleep 3

    # Check if service started successfully
    if systemctl is-active --quiet x-ui; then
        print_success "x-ui успешно запущен с DNS конфигурацией"

        # Restart x-ui to apply changes
        print_info "Перезапуск x-ui для применения DNS..."
        systemctl restart x-ui
        sleep 2

        if systemctl is-active --quiet x-ui; then
            print_success "DNS конфигурация применена"
            return 0
        fi
    else
        print_error "x-ui не запустился"
        return 1
    fi
}

################################################################################
# OUTPUT FUNCTIONS
################################################################################

# Get external IP address
get_external_ip() {
    local ip

    # Try multiple services
    ip=$(curl -s -4 ifconfig.me 2>/dev/null) || \
    ip=$(curl -s -4 icanhazip.com 2>/dev/null) || \
    ip=$(curl -s -4 ipinfo.io/ip 2>/dev/null) || \
    ip="N/A"

    echo "$ip"
}

# Print final summary
print_summary() {
    local external_ip=$(get_external_ip)
    local total=${#SERVER_NAMES[@]}
    local success_count=0

    # Count successes
    for status in "${INBOUND_STATUS[@]}"; do
        [[ "$status" == "success" ]] && ((success_count++))
    done

    print_header "Настройка завершена"

    echo -e "${BOLD}Создано инбаундов: $success_count из $total${NC}\n"

    # Print each server status
    for ((i=0; i<total; i++)); do
        local status_icon="✗"
        local status_color=$RED
        local status_text="Ошибка при создании"

        if [[ "${INBOUND_STATUS[$i]}" == "success" ]]; then
            status_icon="✓"
            status_color=$GREEN
            status_text="Успешно создан"
        fi

        echo -e "${BOLD}Сервер #$((i+1)): ${SERVER_NAMES[$i]}${NC}"
        echo -e "  - Локальный порт: ${CYAN}${LOCAL_PORTS[$i]}${NC}"
        echo -e "  - Перенаправление: ${CYAN}${SERVER_IPS[$i]}:${SERVER_PORTS[$i]}${NC}"
        echo -e "  - Статус: ${status_color}${status_icon} ${status_text}${NC}"
        echo
    done

    # Print bridge IP info
    print_header "IP этого моста"
    echo -e "${BOLD}Внешний IP:${NC} ${GREEN}$external_ip${NC}\n"

    echo -e "${BOLD}Для обновления клиентских конфигов замените:${NC}"
    echo -e "  - Старый IP финского сервера → ${GREEN}$external_ip${NC}"
    echo -e "  - Старый порт → соответствующий порт из таблицы выше\n"

    # Extract port from PANEL_URL for display
    local panel_port=$(echo "$PANEL_URL" | grep -oP ':\K[0-9]+' || echo "2053")
    echo -e "${BOLD}Панель управления 3x-ui:${NC} ${BLUE}http://$external_ip:$panel_port${NC}\n"

    if [[ $success_count -lt $total ]]; then
        print_warning "Некоторые inbound'ы не были созданы. Проверьте ошибки выше."
        return 1
    else
        print_success "Все inbound'ы успешно созданы!"
        return 0
    fi
}

################################################################################
# CONFIG FILE FUNCTIONS
################################################################################

# Load configuration from JSON file
load_config_file() {
    local config_file=$1

    if [[ ! -f "$config_file" ]]; then
        die "Файл конфигурации не найден: $config_file"
    fi

    print_info "Загрузка конфигурации из $config_file"

    # Validate JSON
    if ! jq empty "$config_file" 2>/dev/null; then
        die "Неверный формат JSON в файле конфигурации"
    fi

    # Load API settings
    PANEL_URL=$(jq -r '.api.panel_url // "http://localhost:2053"' "$config_file")
    API_USERNAME=$(jq -r '.api.username // "admin"' "$config_file")
    API_PASSWORD=$(jq -r '.api.password // ""' "$config_file")

    if [[ -z "$API_PASSWORD" ]]; then
        die "Пароль API не указан в файле конфигурации"
    fi

    # Load servers
    local server_count=$(jq '.servers | length' "$config_file")

    if [[ $server_count -eq 0 ]]; then
        die "В файле конфигурации не указано ни одного сервера"
    fi

    for ((i=0; i<server_count; i++)); do
        local name=$(jq -r ".servers[$i].name" "$config_file")
        local ip=$(jq -r ".servers[$i].ip" "$config_file")
        local port=$(jq -r ".servers[$i].port" "$config_file")
        local local_port=$(jq -r ".servers[$i].local_port" "$config_file")

        # Validate
        if [[ -z "$name" ]] || [[ -z "$ip" ]] || [[ -z "$port" ]] || [[ -z "$local_port" ]]; then
            die "Неполная конфигурация для сервера #$((i+1))"
        fi

        if ! validate_ip "$ip"; then
            die "Неверный IP адрес для сервера #$((i+1)): $ip"
        fi

        if ! validate_port "$port" || ! validate_port "$local_port"; then
            die "Неверный порт для сервера #$((i+1))"
        fi

        # Store
        SERVER_NAMES+=("$name")
        SERVER_IPS+=("$ip")
        SERVER_PORTS+=("$port")
        LOCAL_PORTS+=("$local_port")
    done

    print_success "Загружено серверов: $server_count"
}

################################################################################
# CLEANUP AND SIGNAL HANDLING
################################################################################

# Cleanup on exit
cleanup() {
    rm -f /tmp/xui-cookie.txt
}

# Handle Ctrl+C
handle_interrupt() {
    echo
    print_warning "Прервано пользователем"
    cleanup
    exit 130
}

trap cleanup EXIT
trap handle_interrupt INT TERM

################################################################################
# MAIN FUNCTION
################################################################################

main() {
    # Print banner
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  Dokodemo-door Bridge Setup Script for 3x-ui          ║"
    echo "║  Version: $SCRIPT_VERSION                                   ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [--config config.json]"
                echo
                echo "Options:"
                echo "  --config FILE    Load configuration from JSON file"
                echo "  --help           Show this help message"
                exit 0
                ;;
            *)
                die "Неизвестный параметр: $1 (используйте --help для справки)"
                ;;
        esac
    done

    # Step 1: Check root privileges
    check_root

    # Step 2: Detect OS
    detect_os

    # Step 3: Install dependencies
    install_dependencies

    # Step 4: Check and install 3x-ui
    check_and_install_xui

    # Step 5: Collect configuration
    if [[ -n "$CONFIG_FILE" ]]; then
        load_config_file "$CONFIG_FILE"
    else
        collect_configuration
    fi

    # Step 6: Create inbounds
    create_all_inbounds

    # Step 7: Configure DNS
    echo
    configure_dns

    # Step 8: Print summary
    echo
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

################################################################################
# ENTRY POINT
################################################################################

main "$@"
