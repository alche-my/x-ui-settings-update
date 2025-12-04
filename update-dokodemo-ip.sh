#!/bin/bash

################################################################################
# Dokodemo-door IP Update Script for 3x-ui
#
# Description: Updates the target IP address of existing Dokodemo-door inbounds
#
# Usage: sudo ./update-dokodemo-ip.sh
################################################################################

set -euo pipefail

################################################################################
# GLOBAL VARIABLES
################################################################################

SCRIPT_VERSION="1.0.0"

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

# API credentials
PANEL_URL=""
API_USERNAME=""
API_PASSWORD=""
SESSION_COOKIE=""

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

################################################################################
# 3X-UI API FUNCTIONS
################################################################################

# Get API credentials
get_api_credentials() {
    print_header "Настройка доступа к 3x-ui"

    # Get panel URL
    read -p "URL панели 3x-ui (по умолчанию $DEFAULT_PANEL_URL): " PANEL_URL
    PANEL_URL=${PANEL_URL:-$DEFAULT_PANEL_URL}

    # Remove trailing slash from URL to avoid double slashes
    PANEL_URL=${PANEL_URL%/}

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
    print_info "Используется URL: $PANEL_URL"
}

# Login to 3x-ui API and get session cookie
api_login() {
    print_info "Аутентификация в 3x-ui API..."

    local login_url="${PANEL_URL}/login"
    print_info "URL запроса: $login_url"

    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" -X POST "$login_url" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${API_USERNAME}\",\"password\":\"${API_PASSWORD}\"}" \
        -c /tmp/xui-cookie.txt)

    http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -n -1)

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
        print_info "Ответ сервера: $body"
        return 1
    else
        print_error "Ошибка аутентификации (HTTP $http_code)"
        print_error "Проверьте URL, логин и пароль"
        if [[ -n "$body" ]]; then
            print_info "Ответ сервера: $body"
        fi
        return 1
    fi
}

# Get list of all inbounds
get_inbounds_list() {
    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" -X GET "${PANEL_URL}/panel/api/inbounds/list" \
        -H "Accept: application/json" \
        -H "Cookie: 3x-ui=${SESSION_COOKIE}")

    http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -n -1)

    if [[ "$http_code" -eq 200 ]]; then
        echo "$body"
        return 0
    else
        print_error "Ошибка получения списка инбаундов (HTTP $http_code)"
        return 1
    fi
}

# Update inbound
update_inbound() {
    local inbound_id=$1
    local inbound_json=$2

    print_info "Обновление инбаунда ID: $inbound_id..."

    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" -X POST "${PANEL_URL}/panel/api/inbounds/update/${inbound_id}" \
        -H "Content-Type: application/json" \
        -H "Cookie: 3x-ui=${SESSION_COOKIE}" \
        -d "$inbound_json")

    http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -n -1)

    if [[ "$http_code" -eq 200 ]]; then
        local success=$(echo "$body" | jq -r '.success // false' 2>/dev/null || echo "false")

        if [[ "$success" == "true" ]]; then
            print_success "Инбаунд успешно обновлен"
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

################################################################################
# INTERACTIVE FUNCTIONS
################################################################################

# Display Dokodemo-door inbounds and let user select one
select_dokodemo_inbound() {
    print_header "Поиск Dokodemo-door инбаундов"

    local inbounds_response
    inbounds_response=$(get_inbounds_list) || die "Не удалось получить список инбаундов"

    # Check if response is valid JSON
    if ! echo "$inbounds_response" | jq empty 2>/dev/null; then
        die "Неверный формат ответа от API"
    fi

    # Extract Dokodemo-door inbounds
    local dokodemo_inbounds=$(echo "$inbounds_response" | jq -c '[.obj[] | select(.protocol == "dokodemo-door")]')
    local count=$(echo "$dokodemo_inbounds" | jq 'length')

    if [[ $count -eq 0 ]]; then
        die "Dokodemo-door инбаунды не найдены"
    fi

    print_success "Найдено Dokodemo-door инбаундов: $count"
    echo

    # Display list
    echo -e "${BOLD}Доступные Dokodemo-door инбаунды:${NC}\n"

    for ((i=0; i<count; i++)); do
        local inbound=$(echo "$dokodemo_inbounds" | jq -r ".[$i]")
        local id=$(echo "$inbound" | jq -r '.id')
        local remark=$(echo "$inbound" | jq -r '.remark')
        local port=$(echo "$inbound" | jq -r '.port')
        local settings=$(echo "$inbound" | jq -r '.settings')
        local address=$(echo "$settings" | jq -r '.address // "N/A"')
        local remote_port=$(echo "$settings" | jq -r '.port // "N/A"')

        echo -e "${CYAN}[$((i+1))]${NC} ${BOLD}$remark${NC}"
        echo -e "    ID: $id"
        echo -e "    Локальный порт: ${BLUE}$port${NC}"
        echo -e "    Перенаправление: ${BLUE}$address:$remote_port${NC}"
        echo
    done

    # Ask user to select
    local selection
    while true; do
        read -p "Выберите номер инбаунда для обновления (1-$count): " selection

        if [[ $selection =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le $count ]]; then
            break
        else
            print_error "Введите число от 1 до $count"
        fi
    done

    # Return selected inbound as JSON
    echo "$dokodemo_inbounds" | jq -c ".[$((selection-1))]"
}

# Update IP address for selected inbound
update_inbound_ip() {
    local inbound_json=$1

    local id=$(echo "$inbound_json" | jq -r '.id')
    local remark=$(echo "$inbound_json" | jq -r '.remark')
    local current_settings=$(echo "$inbound_json" | jq -r '.settings')
    local current_address=$(echo "$current_settings" | jq -r '.address')

    print_header "Обновление IP-адреса"

    echo -e "${BOLD}Выбран инбаунд:${NC} $remark"
    echo -e "${BOLD}Текущий IP:${NC} ${RED}$current_address${NC}"
    echo

    # Get new IP
    local new_ip
    while true; do
        read -p "Введите новый IP-адрес: " new_ip

        if validate_ip "$new_ip"; then
            break
        else
            print_error "Неверный формат IP-адреса"
        fi
    done

    # Confirm change
    echo
    echo -e "${YELLOW}Вы уверены, что хотите изменить IP?${NC}"
    echo -e "  Старый IP: ${RED}$current_address${NC}"
    echo -e "  Новый IP:  ${GREEN}$new_ip${NC}"
    echo
    read -p "Продолжить? (y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Обновление отменено"
        return 1
    fi

    # Update settings JSON
    local updated_settings=$(echo "$current_settings" | jq --arg new_addr "$new_ip" '.address = $new_addr')
    local updated_inbound=$(echo "$inbound_json" | jq --argjson settings "$updated_settings" '.settings = $settings')

    # Update via API
    if update_inbound "$id" "$updated_inbound"; then
        print_success "IP-адрес успешно обновлен!"
        echo
        echo -e "${BOLD}Изменения:${NC}"
        echo -e "  Инбаунд: ${CYAN}$remark${NC}"
        echo -e "  Старый IP: ${RED}$current_address${NC}"
        echo -e "  Новый IP:  ${GREEN}$new_ip${NC}"
        echo
        print_info "Изменения вступили в силу немедленно"
        return 0
    else
        print_error "Не удалось обновить IP-адрес"
        return 1
    fi
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
    echo "║  Dokodemo-door IP Update Script for 3x-ui             ║"
    echo "║  Version: $SCRIPT_VERSION                                   ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Check dependencies
    if ! command -v jq &> /dev/null; then
        die "jq не установлен. Установите его: apt install jq (Ubuntu/Debian) или yum install jq (CentOS)"
    fi

    if ! command -v curl &> /dev/null; then
        die "curl не установлен. Установите его: apt install curl (Ubuntu/Debian) или yum install curl (CentOS)"
    fi

    # Check root (commented out as it might not be needed for API access)
    # check_root

    # Get API credentials
    get_api_credentials

    # Login to API
    if ! api_login; then
        die "Не удалось аутентифицироваться в 3x-ui API"
    fi

    # Select inbound to update
    local selected_inbound
    selected_inbound=$(select_dokodemo_inbound) || die "Не удалось выбрать инбаунд"

    # Update IP address
    if update_inbound_ip "$selected_inbound"; then
        print_header "Готово!"
        print_success "IP-адрес успешно обновлен"
        exit 0
    else
        die "Не удалось обновить IP-адрес"
    fi
}

################################################################################
# ENTRY POINT
################################################################################

main "$@"
