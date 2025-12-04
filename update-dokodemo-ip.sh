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

# Print colored messages (all to stderr to avoid capture in subshells)
print_success() {
    echo -e "${GREEN}✓${NC} $1" >&2
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1" >&2
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1" >&2
}

print_header() {
    echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}\n" >&2
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

    # Try different possible login endpoints
    local login_endpoints=("login" "panel/login" "api/login")
    local success=false

    for endpoint in "${login_endpoints[@]}"; do
        local login_url="${PANEL_URL}/${endpoint}"
        print_info "Попытка входа через: $login_url"

        local response
        local http_code

        response=$(curl -s -w "\n%{http_code}" -X POST "$login_url" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"${API_USERNAME}\",\"password\":\"${API_PASSWORD}\"}" \
            -c /tmp/xui-cookie.txt 2>&1)

        http_code=$(echo "$response" | tail -1)
        local body=$(echo "$response" | head -n -1)

        print_info "HTTP код ответа: $http_code"

        if [[ "$http_code" -eq 200 ]]; then
            # Extract session cookie
            if [[ -f /tmp/xui-cookie.txt ]]; then
                SESSION_COOKIE=$(grep -oP '(?<=3x-ui\s)[^\s]+' /tmp/xui-cookie.txt 2>/dev/null || echo "")

                if [[ -n "$SESSION_COOKIE" ]]; then
                    print_success "Успешная аутентификация через: $endpoint"
                    success=true
                    break
                fi
            fi

            # Check if response contains success indicator
            if echo "$body" | jq -e '.success == true' >/dev/null 2>&1; then
                print_success "Успешная аутентификация (по ответу API)"
                success=true
                break
            fi
        fi

        if [[ "$http_code" != "404" ]]; then
            print_warning "Endpoint $endpoint вернул код $http_code"
            if [[ -n "$body" ]] && [[ ${#body} -lt 200 ]]; then
                print_info "Ответ: $body"
            fi
        fi
    done

    if [[ "$success" == "true" ]]; then
        return 0
    else
        print_error "Не удалось аутентифицироваться"
        print_error "Проверьте:"
        print_error "  1. Правильность URL панели (включая секретный путь)"
        print_error "  2. Логин и пароль"
        print_error "  3. Доступность панели: curl ${PANEL_URL}"
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

    # Try to extract JSON from response (in case there's extra text)
    local json_response=$(echo "$inbounds_response" | grep -o '{.*}' | head -1)

    # If grep didn't find JSON, try the original response
    if [[ -z "$json_response" ]]; then
        json_response="$inbounds_response"
    fi

    # Check if response is valid JSON
    if ! echo "$json_response" | jq empty 2>/dev/null; then
        print_error "Неверный формат ответа от API"
        print_info "Ответ сервера (первые 500 символов):"
        echo "$inbounds_response" | head -c 500 >&2
        echo >&2
        die "Не удалось распарсить ответ API"
    fi

    # Extract Dokodemo-door inbounds
    local dokodemo_inbounds=$(echo "$json_response" | jq -c '[.obj[]? // .[] | select(.protocol == "dokodemo-door")]' 2>/dev/null)

    if [[ -z "$dokodemo_inbounds" ]] || [[ "$dokodemo_inbounds" == "null" ]]; then
        print_error "Не удалось извлечь инбаунды из ответа"
        print_info "JSON ответ:"
        echo "$json_response" | jq '.' 2>&1 >&2 || echo "$json_response" >&2
        die "Dokodemo-door инбаунды не найдены"
    fi

    local count=$(echo "$dokodemo_inbounds" | jq 'length' 2>/dev/null || echo "0")

    if [[ $count -eq 0 ]]; then
        die "Dokodemo-door инбаунды не найдены"
    fi

    print_success "Найдено Dokodemo-door инбаундов: $count"
    echo >&2

    # Display list
    echo -e "${BOLD}Доступные Dokodemo-door инбаунды:${NC}\n" >&2

    for ((i=0; i<count; i++)); do
        local inbound=$(echo "$dokodemo_inbounds" | jq -c ".[$i]" 2>/dev/null)
        local id=$(echo "$inbound" | jq -r '.id // "N/A"' 2>/dev/null)
        local remark=$(echo "$inbound" | jq -r '.remark // "N/A"' 2>/dev/null)
        local port=$(echo "$inbound" | jq -r '.port // "N/A"' 2>/dev/null)

        # Parse settings - it might be a string or object
        local settings=$(echo "$inbound" | jq -r '.settings // "{}"' 2>/dev/null)

        # Try to parse settings if it's a JSON string
        if [[ "$settings" == "{"* ]]; then
            local address=$(echo "$settings" | jq -r '.address // "N/A"' 2>/dev/null)
            local remote_port=$(echo "$settings" | jq -r '.port // "N/A"' 2>/dev/null)
        else
            # Settings might be a JSON string that needs parsing
            local address=$(echo "$settings" | jq -r 'fromjson? | .address // "N/A"' 2>/dev/null || echo "N/A")
            local remote_port=$(echo "$settings" | jq -r 'fromjson? | .port // "N/A"' 2>/dev/null || echo "N/A")
        fi

        echo -e "${CYAN}[$((i+1))]${NC} ${BOLD}$remark${NC}" >&2
        echo -e "    ID: $id" >&2
        echo -e "    Локальный порт: ${BLUE}$port${NC}" >&2
        echo -e "    Перенаправление: ${BLUE}$address:$remote_port${NC}" >&2
        echo >&2
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

    local id=$(echo "$inbound_json" | jq -r '.id // "N/A"' 2>/dev/null)
    local remark=$(echo "$inbound_json" | jq -r '.remark // "N/A"' 2>/dev/null)

    # Get settings - might be a string or object
    local current_settings=$(echo "$inbound_json" | jq -r '.settings // "{}"' 2>/dev/null)

    # Parse settings if it's a JSON string
    local current_address
    if [[ "$current_settings" == "{"* ]]; then
        current_address=$(echo "$current_settings" | jq -r '.address // "N/A"' 2>/dev/null)
    else
        # Try to parse as JSON string
        current_address=$(echo "$current_settings" | jq -r 'fromjson? | .address // "N/A"' 2>/dev/null)
        if [[ "$current_address" == "N/A" ]] || [[ -z "$current_address" ]]; then
            # If still N/A, try without fromjson
            current_address=$(echo "$inbound_json" | jq -r '.settings.address // "N/A"' 2>/dev/null)
        fi
    fi

    print_header "Обновление IP-адреса"

    echo -e "${BOLD}Выбран инбаунд:${NC} $remark" >&2
    echo -e "${BOLD}ID:${NC} $id" >&2
    echo -e "${BOLD}Текущий IP:${NC} ${RED}$current_address${NC}" >&2
    echo >&2

    # Validate that we have a current address
    if [[ "$current_address" == "N/A" ]] || [[ -z "$current_address" ]] || [[ "$current_address" == "null" ]]; then
        print_error "Не удалось определить текущий IP-адрес"
        print_info "JSON инбаунда:"
        echo "$inbound_json" | jq '.' 2>&1 >&2 || echo "$inbound_json" >&2
        return 1
    fi

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
    echo >&2
    echo -e "${YELLOW}Вы уверены, что хотите изменить IP?${NC}" >&2
    echo -e "  Старый IP: ${RED}$current_address${NC}" >&2
    echo -e "  Новый IP:  ${GREEN}$new_ip${NC}" >&2
    echo >&2
    read -p "Продолжить? (y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Обновление отменено"
        return 1
    fi

    # Parse current settings properly
    local settings_obj
    if [[ "$current_settings" == "{"* ]]; then
        settings_obj="$current_settings"
    else
        settings_obj=$(echo "$current_settings" | jq -r 'fromjson? // .' 2>/dev/null)
    fi

    # Update settings JSON
    local updated_settings=$(echo "$settings_obj" | jq --arg new_addr "$new_ip" '.address = $new_addr' 2>/dev/null)

    # Create updated inbound - settings might need to be stringified
    local updated_inbound=$(echo "$inbound_json" | jq --arg settings_str "$updated_settings" '.settings = $settings_str' 2>/dev/null)

    # Update via API
    if update_inbound "$id" "$updated_inbound"; then
        print_success "IP-адрес успешно обновлен!"
        echo >&2
        echo -e "${BOLD}Изменения:${NC}" >&2
        echo -e "  Инбаунд: ${CYAN}$remark${NC}" >&2
        echo -e "  Старый IP: ${RED}$current_address${NC}" >&2
        echo -e "  Новый IP:  ${GREEN}$new_ip${NC}" >&2
        echo >&2
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
