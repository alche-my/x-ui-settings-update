#!/bin/bash

################################################################################
# Reality VPN Bridge Setup Script for 3x-ui
#
# Description: Automates the setup of Reality bridge (entry/exit) nodes
#              using 3x-ui on Ubuntu 22.04/24.04
#
# Usage: sudo ./rvpn-bridge-setup.sh [OPTIONS]
#
# Options:
#   --role entry|exit         Server role (required)
#   --non-interactive         Run without user prompts
#   --log-level info|debug    Logging level (default: info)
#   --entry-port PORT         Entry server port
#   --entry-sni SNI           Entry server SNI
#   --entry-fp FINGERPRINT    Entry server fingerprint
#   --exit-ip IP              Exit server IP address
#   --exit-port PORT          Exit server port
#   --exit-sni SNI            Exit server SNI
#   --exit-pbk PUBLIC_KEY     Exit server public key
#   --exit-sid SHORT_ID       Exit server short ID
#   --exit-uuid UUID          Exit server UUID
#
################################################################################

set -euo pipefail

################################################################################
# GLOBAL VARIABLES
################################################################################

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_START_TIME=$(date +%s)

# Directories
RVPN_BASE_DIR="/root/rvpn-bridge"
RVPN_DIAG_DIR="${RVPN_BASE_DIR}/diagnostics"
RVPN_ARTIFACTS="${RVPN_BASE_DIR}/artifacts.json"

# Logging
LOG_DIR="/var/log/rvpn-bridge"
LOG_FILE="${LOG_DIR}/setup.log"
LOG_LEVEL="info"

# 3x-ui settings
XUI_INSTALL_URL="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
XUI_DIR="/usr/local/x-ui"
XUI_DB="/etc/x-ui/x-ui.db"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration variables
ROLE=""
NON_INTERACTIVE=false

# Entry server settings
ENTRY_PORT=""
ENTRY_SNI=""
ENTRY_FP=""
ENTRY_PBK=""
ENTRY_SID=""

# Exit server settings
EXIT_IP=""
EXIT_PORT=""
EXIT_SNI=""
EXIT_PBK=""
EXIT_SID=""
EXIT_UUID=""

# Runtime variables
CURRENT_STEP=""
TRAP_ACTIVE=false

################################################################################
# TRAP HANDLERS
################################################################################

# Error handler
handle_error() {
    local exit_code=$?
    local line_number=$1

    if [[ "$TRAP_ACTIVE" == "true" ]]; then
        return
    fi
    TRAP_ACTIVE=true

    log_error "Ошибка на строке ${line_number}, код выхода: ${exit_code}"
    if [[ -n "$CURRENT_STEP" ]]; then
        log_error "Текущий шаг: ${CURRENT_STEP}"
    fi

    log_info "Сбор диагностической информации..."
    collect_diagnostics "error" "${exit_code}"

    log_error "Установка прервана с ошибкой. Диагностика сохранена в: ${RVPN_DIAG_DIR}"
    exit "${exit_code}"
}

# Exit handler
handle_exit() {
    local exit_code=$?

    if [[ "$TRAP_ACTIVE" == "true" ]]; then
        return
    fi

    if [[ $exit_code -eq 0 ]]; then
        local duration=$(($(date +%s) - SCRIPT_START_TIME))
        log_success "Скрипт завершен успешно за ${duration} секунд"
        collect_diagnostics "success" "0"
    fi
}

trap 'handle_error ${LINENO}' ERR
trap 'handle_exit' EXIT

################################################################################
# LOGGING FUNCTIONS
################################################################################

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$RVPN_BASE_DIR"
    mkdir -p "$RVPN_DIAG_DIR"

    # Clear old log if starting fresh
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
    fi

    log_info "=========================================="
    log_info "Reality VPN Bridge Setup v${SCRIPT_VERSION}"
    log_info "Начало: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "=========================================="
}

# Generic log function
log_message() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_line="${timestamp} [${level}] ${message}"

    # Write to log file
    echo "${log_line}" >> "$LOG_FILE"

    # Output to stdout based on level and color
    case "$level" in
        ERROR)
            echo -e "${RED}✗ [ERROR]${NC} ${message}" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}✓ [SUCCESS]${NC} ${message}"
            ;;
        WARN)
            echo -e "${YELLOW}⚠ [WARN]${NC} ${message}"
            ;;
        INFO)
            echo -e "${BLUE}ℹ [INFO]${NC} ${message}"
            ;;
        DEBUG)
            if [[ "$LOG_LEVEL" == "debug" ]]; then
                echo -e "${MAGENTA}⚙ [DEBUG]${NC} ${message}"
            fi
            ;;
        STEP)
            echo -e "\n${BOLD}${CYAN}━━━ $message ━━━${NC}\n"
            ;;
    esac
}

log_error() { log_message "ERROR" "$@"; }
log_success() { log_message "SUCCESS" "$@"; }
log_warn() { log_message "WARN" "$@"; }
log_info() { log_message "INFO" "$@"; }
log_debug() { log_message "DEBUG" "$@"; }
log_step() {
    CURRENT_STEP="$*"
    log_message "STEP" "$@"
}

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        log_info "Используйте: sudo $0 $*"
        exit 1
    fi
}

# Show usage information
show_usage() {
    cat << EOF
Использование: sudo ${SCRIPT_NAME} [OPTIONS]

Опции:
  --role entry|exit         Роль сервера (обязательно)
  --non-interactive         Запуск без интерактивных вопросов
  --log-level info|debug    Уровень логирования (по умолчанию: info)

  Настройки ENTRY сервера:
  --entry-port PORT         Порт входящих подключений
  --entry-sni SNI           Server Name Indication
  --entry-fp FINGERPRINT    Browser fingerprint

  Настройки EXIT сервера:
  --exit-ip IP              IP адрес EXIT сервера
  --exit-port PORT          Порт EXIT сервера
  --exit-sni SNI            SNI для EXIT сервера
  --exit-pbk PUBLIC_KEY     Public key EXIT сервера
  --exit-sid SHORT_ID       Short ID EXIT сервера
  --exit-uuid UUID          UUID клиента на EXIT сервере

Примеры:
  # Настроить EXIT сервер в интерактивном режиме
  sudo ${SCRIPT_NAME} --role exit

  # Настроить ENTRY сервер с параметрами
  sudo ${SCRIPT_NAME} --role entry \\
    --exit-ip 1.2.3.4 \\
    --exit-port 443 \\
    --exit-sni example.com \\
    --exit-pbk <public-key> \\
    --exit-sid <short-id>

EOF
}

################################################################################
# ARTIFACTS MANAGEMENT
################################################################################

# Initialize artifacts.json
init_artifacts() {
    if [[ ! -f "$RVPN_ARTIFACTS" ]]; then
        log_debug "Создание нового файла артефактов"
        cat > "$RVPN_ARTIFACTS" << 'EOF'
{
  "version": "1.0.0",
  "created_at": "",
  "updated_at": "",
  "role": "",
  "entry": {},
  "exit": {},
  "metadata": {}
}
EOF
    fi

    # Update timestamps
    update_artifact "created_at" "$(date -Iseconds)" "keep-existing"
    update_artifact "updated_at" "$(date -Iseconds)"
}

# Update artifact value
# Usage: update_artifact "path.to.field" "value" ["keep-existing"]
update_artifact() {
    local path=$1
    local value=$2
    local keep_existing=${3:-}

    if [[ ! -f "$RVPN_ARTIFACTS" ]]; then
        init_artifacts
    fi

    # Check if value already exists and keep-existing flag is set
    if [[ "$keep_existing" == "keep-existing" ]]; then
        local existing=$(jq -r ".${path}" "$RVPN_ARTIFACTS" 2>/dev/null || echo "null")
        if [[ "$existing" != "null" && "$existing" != "" ]]; then
            log_debug "Пропуск обновления ${path}: значение уже существует"
            return 0
        fi
    fi

    # Create temporary file
    local temp_file=$(mktemp)

    # Update the value
    jq ".${path} = \"${value}\"" "$RVPN_ARTIFACTS" > "$temp_file"
    mv "$temp_file" "$RVPN_ARTIFACTS"

    log_debug "Артефакт обновлен: ${path} = ${value}"
}

# Get artifact value
# Usage: get_artifact "path.to.field"
get_artifact() {
    local path=$1

    if [[ ! -f "$RVPN_ARTIFACTS" ]]; then
        echo ""
        return 1
    fi

    jq -r ".${path}" "$RVPN_ARTIFACTS" 2>/dev/null || echo ""
}

# Save all current configuration to artifacts
save_config_to_artifacts() {
    log_debug "Сохранение конфигурации в артефакты"

    update_artifact "role" "$ROLE"
    update_artifact "updated_at" "$(date -Iseconds)"

    if [[ "$ROLE" == "entry" ]]; then
        [[ -n "$ENTRY_PORT" ]] && update_artifact "entry.port" "$ENTRY_PORT"
        [[ -n "$ENTRY_SNI" ]] && update_artifact "entry.sni" "$ENTRY_SNI"
        [[ -n "$ENTRY_FP" ]] && update_artifact "entry.fingerprint" "$ENTRY_FP"
        [[ -n "$EXIT_IP" ]] && update_artifact "exit.ip" "$EXIT_IP"
        [[ -n "$EXIT_PORT" ]] && update_artifact "exit.port" "$EXIT_PORT"
        [[ -n "$EXIT_SNI" ]] && update_artifact "exit.sni" "$EXIT_SNI"
        [[ -n "$EXIT_PBK" ]] && update_artifact "exit.public_key" "$EXIT_PBK"
        [[ -n "$EXIT_SID" ]] && update_artifact "exit.short_id" "$EXIT_SID"
        [[ -n "$EXIT_UUID" ]] && update_artifact "exit.uuid" "$EXIT_UUID"
    elif [[ "$ROLE" == "exit" ]]; then
        [[ -n "$EXIT_PORT" ]] && update_artifact "exit.port" "$EXIT_PORT"
        [[ -n "$EXIT_SNI" ]] && update_artifact "exit.sni" "$EXIT_SNI"
    fi
}

################################################################################
# CLI ARGUMENT PARSING
################################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --role)
                ROLE="$2"
                if [[ "$ROLE" != "entry" && "$ROLE" != "exit" ]]; then
                    log_error "Недопустимая роль: ${ROLE}. Используйте 'entry' или 'exit'"
                    exit 1
                fi
                shift 2
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --log-level)
                LOG_LEVEL="$2"
                if [[ "$LOG_LEVEL" != "info" && "$LOG_LEVEL" != "debug" ]]; then
                    log_error "Недопустимый уровень логирования: ${LOG_LEVEL}"
                    exit 1
                fi
                shift 2
                ;;
            --entry-port)
                ENTRY_PORT="$2"
                shift 2
                ;;
            --entry-sni)
                ENTRY_SNI="$2"
                shift 2
                ;;
            --entry-fp)
                ENTRY_FP="$2"
                shift 2
                ;;
            --exit-ip)
                EXIT_IP="$2"
                shift 2
                ;;
            --exit-port)
                EXIT_PORT="$2"
                shift 2
                ;;
            --exit-sni)
                EXIT_SNI="$2"
                shift 2
                ;;
            --exit-pbk)
                EXIT_PBK="$2"
                shift 2
                ;;
            --exit-sid)
                EXIT_SID="$2"
                shift 2
                ;;
            --exit-uuid)
                EXIT_UUID="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Неизвестный параметр: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

################################################################################
# INTERACTIVE MODE
################################################################################

# Ask user for role
ask_role() {
    if [[ -n "$ROLE" ]]; then
        return 0
    fi

    echo -e "\n${BOLD}${CYAN}Выберите роль этого сервера:${NC}"
    echo "1) ENTRY (ВХОД) - клиенты подключаются к этому серверу"
    echo "2) EXIT (ВЫХОД) - сервер для проксирования трафика"
    echo

    local choice
    read -p "Введите номер (1 или 2): " choice

    case $choice in
        1)
            ROLE="entry"
            log_info "Выбрана роль: ENTRY"
            ;;
        2)
            ROLE="exit"
            log_info "Выбрана роль: EXIT"
            ;;
        *)
            log_error "Недопустимый выбор"
            exit 1
            ;;
    esac
}

# Ask for exit server parameters (for ENTRY role)
ask_exit_parameters() {
    if [[ "$ROLE" != "entry" ]]; then
        return 0
    fi

    # Try to load from artifacts first
    if [[ -f "$RVPN_ARTIFACTS" ]]; then
        local saved_exit_ip=$(get_artifact "exit.ip")
        if [[ -n "$saved_exit_ip" && "$saved_exit_ip" != "null" ]]; then
            log_info "Найдены сохраненные параметры EXIT сервера"
            EXIT_IP=${EXIT_IP:-$saved_exit_ip}
            EXIT_PORT=${EXIT_PORT:-$(get_artifact "exit.port")}
            EXIT_SNI=${EXIT_SNI:-$(get_artifact "exit.sni")}
            EXIT_PBK=${EXIT_PBK:-$(get_artifact "exit.public_key")}
            EXIT_SID=${EXIT_SID:-$(get_artifact "exit.short_id")}
            EXIT_UUID=${EXIT_UUID:-$(get_artifact "exit.uuid")}

            log_info "EXIT IP: ${EXIT_IP}"
            log_info "EXIT Port: ${EXIT_PORT}"
            log_info "EXIT SNI: ${EXIT_SNI}"
            return 0
        fi
    fi

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        if [[ -z "$EXIT_IP" || -z "$EXIT_PORT" || -z "$EXIT_SNI" ]]; then
            log_error "В неинтерактивном режиме требуются параметры EXIT сервера"
            exit 1
        fi
        return 0
    fi

    echo -e "\n${BOLD}${CYAN}Настройка параметров EXIT сервера:${NC}\n"

    if [[ -z "$EXIT_IP" ]]; then
        read -p "IP адрес EXIT сервера: " EXIT_IP
    fi

    if [[ -z "$EXIT_PORT" ]]; then
        read -p "Порт EXIT сервера [443]: " EXIT_PORT
        EXIT_PORT=${EXIT_PORT:-443}
    fi

    if [[ -z "$EXIT_SNI" ]]; then
        read -p "SNI для EXIT сервера: " EXIT_SNI
    fi

    if [[ -z "$EXIT_PBK" ]]; then
        read -p "Public Key EXIT сервера (оставьте пустым для получения позже): " EXIT_PBK
    fi

    if [[ -z "$EXIT_SID" ]]; then
        read -p "Short ID EXIT сервера (оставьте пустым для получения позже): " EXIT_SID
    fi

    if [[ -z "$EXIT_UUID" ]]; then
        read -p "UUID клиента на EXIT (оставьте пустым для создания нового): " EXIT_UUID
    fi
}

################################################################################
# SYSTEM CHECK FUNCTIONS
################################################################################

# Check if port is listening
# Usage: is_port_listening 443
is_port_listening() {
    local port=$1

    if [[ -z "$port" ]]; then
        log_error "is_port_listening: порт не указан"
        return 2
    fi

    # Use ss to check if port is listening
    if command -v ss &> /dev/null; then
        if ss -lntup 2>/dev/null | grep -q ":${port} "; then
            log_debug "Порт ${port} занят"
            return 0
        else
            log_debug "Порт ${port} свободен"
            return 1
        fi
    else
        log_warn "ss не найден, используем netstat"
        if netstat -lntup 2>/dev/null | grep -q ":${port} "; then
            log_debug "Порт ${port} занят"
            return 0
        else
            log_debug "Порт ${port} свободен"
            return 1
        fi
    fi
}

# Pick a free port starting from preferred
# Usage: pick_free_port 443
pick_free_port() {
    local preferred_port=$1
    local max_attempts=100
    local current_port=$preferred_port

    if [[ -z "$preferred_port" ]]; then
        log_error "pick_free_port: предпочтительный порт не указан"
        return 1
    fi

    log_debug "Поиск свободного порта, начиная с ${preferred_port}"

    # Try preferred port first
    if ! is_port_listening "$current_port"; then
        log_info "Использую порт: ${current_port}"
        echo "$current_port"
        return 0
    fi

    log_warn "Порт ${preferred_port} занят, ищу альтернативу"

    # Try sequential ports
    for i in $(seq 1 10); do
        current_port=$((preferred_port + i))
        if ! is_port_listening "$current_port"; then
            log_info "Найден свободный порт: ${current_port} (предпочтительный ${preferred_port} был занят)"
            echo "$current_port"
            return 0
        fi
    done

    # Try random ports in range 20000-60000
    for i in $(seq 1 $max_attempts); do
        current_port=$((20000 + RANDOM % 40000))
        if ! is_port_listening "$current_port"; then
            log_info "Найден свободный порт: ${current_port} (случайный выбор)"
            echo "$current_port"
            return 0
        fi
    done

    log_error "Не удалось найти свободный порт после ${max_attempts} попыток"
    return 1
}

# Check DNS resolution
check_dns() {
    log_debug "Проверка DNS резолюции"

    local test_domains=("github.com" "google.com" "cloudflare.com")
    local success=false

    for domain in "${test_domains[@]}"; do
        if getent hosts "$domain" &> /dev/null; then
            log_success "DNS работает (проверка: ${domain})"
            success=true
            break
        else
            log_debug "DNS не смог разрешить ${domain}"
        fi
    done

    if [[ "$success" == "false" ]]; then
        log_warn "DNS резолюция не работает"
        return 1
    fi

    return 0
}

# Check outbound internet connectivity
check_outbound_internet() {
    log_debug "Проверка исходящего интернет соединения"

    local test_urls=("https://www.google.com" "https://www.cloudflare.com" "https://1.1.1.1")
    local success=false

    for url in "${test_urls[@]}"; do
        if curl -I --max-time 5 --silent --fail "$url" &> /dev/null; then
            log_success "Исходящее интернет соединение работает (проверка: ${url})"
            success=true
            break
        else
            log_debug "Не удалось подключиться к ${url}"
        fi
    done

    if [[ "$success" == "false" ]]; then
        log_warn "Исходящее интернет соединение не работает"
        return 1
    fi

    return 0
}

# Check OS version
check_os() {
    log_debug "Проверка операционной системы"

    if [[ ! -f /etc/os-release ]]; then
        log_warn "Не удалось определить ОС (/etc/os-release не найден)"
        return 1
    fi

    # Read OS info without sourcing
    local os_id=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
    local os_version_id=$(grep "^VERSION_ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
    local os_name=$(grep "^NAME=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
    local os_version=$(grep "^VERSION=" /etc/os-release | cut -d'=' -f2 | tr -d '"')

    log_info "ОС: ${os_name} ${os_version}"

    if [[ "$os_id" != "ubuntu" ]]; then
        log_warn "Этот скрипт предназначен для Ubuntu, обнаружено: ${os_name}"
        log_warn "Продолжаем на свой страх и риск..."
        return 1
    fi

    # Check Ubuntu version
    case "$os_version_id" in
        "22.04"|"24.04")
            log_success "Поддерживаемая версия Ubuntu: ${os_version_id}"
            return 0
            ;;
        *)
            log_warn "Рекомендуется Ubuntu 22.04 или 24.04, обнаружено: ${os_version_id}"
            log_warn "Продолжаем, но могут возникнуть проблемы"
            return 1
            ;;
    esac
}

################################################################################
# MAIN SETUP FUNCTIONS (STUBS)
################################################################################

# Install dependencies
install_deps() {
    log_step "Установка зависимостей"

    # Check OS first
    check_os

    local missing_pkgs=()

    # Essential utilities
    local required_commands=(
        "curl:curl"
        "jq:jq"
        "sqlite3:sqlite3"
        "openssl:openssl"
        "nc:netcat-openbsd"
        "netstat:net-tools"
        "ss:iproute2"
        "lsof:lsof"
        "getent:libc-bin"
    )

    # Optional utilities
    local optional_commands=(
        "unzip:unzip"
        "tar:tar"
    )

    log_info "Проверка обязательных утилит..."

    # Check required commands
    for entry in "${required_commands[@]}"; do
        local cmd="${entry%%:*}"
        local pkg="${entry##*:}"

        if ! command -v "$cmd" &> /dev/null; then
            missing_pkgs+=("$pkg")
            log_debug "Отсутствует: $cmd (пакет: $pkg)"
        else
            local version=""
            case "$cmd" in
                curl)
                    version=$(curl --version 2>/dev/null | head -n1)
                    ;;
                jq)
                    version=$(jq --version 2>/dev/null)
                    ;;
                openssl)
                    version=$(openssl version 2>/dev/null)
                    ;;
                sqlite3)
                    version=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1)
                    ;;
            esac

            if [[ -n "$version" ]]; then
                log_debug "Найден: $cmd ($version)"
            else
                log_debug "Найден: $cmd"
            fi
        fi
    done

    # Check optional commands
    log_info "Проверка опциональных утилит..."
    for entry in "${optional_commands[@]}"; do
        local cmd="${entry%%:*}"
        local pkg="${entry##*:}"

        if ! command -v "$cmd" &> /dev/null; then
            missing_pkgs+=("$pkg")
            log_debug "Отсутствует (опционально): $cmd (пакет: $pkg)"
        else
            log_debug "Найден: $cmd"
        fi
    done

    # Add ca-certificates if needed
    if [[ ! -d /etc/ssl/certs ]] || [[ $(ls -1 /etc/ssl/certs/*.pem 2>/dev/null | wc -l) -eq 0 ]]; then
        log_debug "CA сертификаты требуют обновления"
        if [[ ! " ${missing_pkgs[*]} " =~ " ca-certificates " ]]; then
            missing_pkgs+=("ca-certificates")
        fi
    fi

    # Remove duplicates
    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        local unique_pkgs=($(printf '%s\n' "${missing_pkgs[@]}" | sort -u))
        missing_pkgs=("${unique_pkgs[@]}")
    fi

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        log_info "Требуется установка пакетов: ${missing_pkgs[*]}"

        # Update package lists (allow warnings)
        log_info "Обновление списка пакетов..."
        set +e
        DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>&1
        local update_status=$?
        set -e

        if [[ $update_status -ne 0 ]]; then
            log_warn "apt-get update завершился с предупреждениями (код: ${update_status})"
        fi

        # Install packages
        log_info "Установка пакетов..."
        set +e
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_pkgs[@]}" 2>&1
        local install_status=$?
        set -e

        if [[ $install_status -eq 0 ]]; then
            log_success "Все зависимости успешно установлены"
        else
            log_warn "Некоторые пакеты не удалось установить (код: ${install_status})"

            # Verify critical packages
            local critical_missing=()
            for entry in "${required_commands[@]}"; do
                local cmd="${entry%%:*}"
                if ! command -v "$cmd" &> /dev/null; then
                    critical_missing+=("$cmd")
                fi
            done

            if [[ ${#critical_missing[@]} -gt 0 ]]; then
                log_error "Критические утилиты отсутствуют: ${critical_missing[*]}"
                log_error "Невозможно продолжить без этих утилит"
                return 1
            else
                log_warn "Продолжаем с установленными пакетами..."
            fi
        fi
    else
        log_success "Все зависимости уже установлены"
    fi

    # Run network checks
    log_info "Выполнение сетевых проверок..."
    check_dns || log_warn "DNS проверка не пройдена (не критично)"
    check_outbound_internet || log_warn "Проверка интернета не пройдена (может повлиять на загрузку компонентов)"

    log_success "Проверка зависимостей завершена"
}

################################################################################
# 3X-UI MANAGEMENT FUNCTIONS
################################################################################

# Determine x-ui service name
xui_service_name() {
    log_debug "Определение имени сервиса x-ui"

    # Check common service names
    local possible_services=("x-ui" "3x-ui" "xui")

    for service in "${possible_services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            log_debug "Найден сервис: ${service}"
            echo "$service"
            return 0
        fi
    done

    # Fallback: check if x-ui command exists
    if command -v x-ui &> /dev/null; then
        log_debug "Найдена команда x-ui, используем имя сервиса: x-ui"
        echo "x-ui"
        return 0
    fi

    log_debug "Сервис x-ui не найден"
    return 1
}

# Backup x-ui and xray configs
backup_configs() {
    log_debug "Создание резервной копии конфигураций"

    local backup_base="${RVPN_BASE_DIR}/backups"
    local backup_date=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${backup_base}/${backup_date}"

    mkdir -p "$backup_dir"

    local backed_up=false

    # Backup x-ui database
    if [[ -f "$XUI_DB" ]]; then
        cp "$XUI_DB" "${backup_dir}/x-ui.db"
        log_debug "Скопирован: ${XUI_DB}"
        backed_up=true
    fi

    # Backup xray config.json
    local xray_config="/usr/local/x-ui/bin/config.json"
    if [[ -f "$xray_config" ]]; then
        cp "$xray_config" "${backup_dir}/config.json"
        log_debug "Скопирован: ${xray_config}"
        backed_up=true
    fi

    # Backup x-ui config
    local xui_config="/etc/x-ui/x-ui.conf"
    if [[ -f "$xui_config" ]]; then
        cp "$xui_config" "${backup_dir}/x-ui.conf"
        log_debug "Скопирован: ${xui_config}"
        backed_up=true
    fi

    if [[ "$backed_up" == "true" ]]; then
        log_success "Резервная копия создана: ${backup_dir}"
        echo "$backup_dir"
        return 0
    else
        log_warn "Нет файлов для резервного копирования"
        return 1
    fi
}

# Get Xray config.json
get_xray_config_json() {
    log_debug "Получение конфигурации Xray"

    # Try common locations
    local config_locations=(
        "/usr/local/x-ui/bin/config.json"
        "/etc/xray/config.json"
        "/etc/v2ray/config.json"
        "/usr/local/etc/xray/config.json"
    )

    for config_path in "${config_locations[@]}"; do
        if [[ -f "$config_path" ]]; then
            log_debug "Найден конфиг: ${config_path}"

            # Validate JSON
            if jq empty "$config_path" 2>/dev/null; then
                log_success "Конфигурация Xray получена: ${config_path}"
                echo "$config_path"
                return 0
            else
                log_warn "Файл ${config_path} содержит невалидный JSON"
            fi
        fi
    done

    log_error "Не удалось найти конфигурацию Xray"
    return 1
}

# Restart x-ui service
xui_restart() {
    log_debug "Перезапуск сервиса x-ui"

    local service_name
    service_name=$(xui_service_name)

    if [[ -z "$service_name" ]]; then
        log_error "Не удалось определить имя сервиса x-ui"
        return 1
    fi

    log_info "Перезапуск сервиса: ${service_name}"

    if systemctl restart "$service_name"; then
        sleep 2  # Wait for service to start

        if systemctl is-active --quiet "$service_name"; then
            log_success "Сервис ${service_name} успешно перезапущен"
            return 0
        else
            log_error "Сервис ${service_name} не запустился после перезапуска"
            systemctl status "$service_name" --no-pager || true
            return 1
        fi
    else
        log_error "Не удалось перезапустить сервис ${service_name}"
        return 1
    fi
}

# Ensure 3x-ui is installed and running
ensure_3xui() {
    log_step "Проверка 3x-ui"

    local installed=false
    local service_name

    # Check if already installed
    if [[ -d "$XUI_DIR" ]]; then
        log_success "3x-ui уже установлен в: ${XUI_DIR}"
        installed=true
    elif command -v x-ui &> /dev/null; then
        log_success "Команда x-ui найдена"
        installed=true
    fi

    # Install if not present
    if [[ "$installed" == "false" ]]; then
        log_warn "3x-ui не найден, начинается установка..."

        # Ask for confirmation in interactive mode
        if [[ "$NON_INTERACTIVE" != "true" ]]; then
            echo ""
            read -p "Установить 3x-ui сейчас? (y/n): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Установка 3x-ui отменена пользователем"
                log_error "3x-ui обязателен для работы скрипта"
                return 1
            fi
        fi

        log_info "Загрузка установщика 3x-ui..."

        # Download and run installer
        local install_script=$(mktemp)

        if curl -sL "$XUI_INSTALL_URL" -o "$install_script"; then
            log_info "Запуск установщика 3x-ui..."

            # Run installer in non-interactive mode
            if bash "$install_script" <<< "0" 2>&1 | tee -a "$LOG_FILE"; then
                log_success "3x-ui успешно установлен"
                installed=true
            else
                log_error "Ошибка при установке 3x-ui"
                rm -f "$install_script"
                return 1
            fi

            rm -f "$install_script"
        else
            log_error "Не удалось загрузить установщик 3x-ui"
            log_error "URL: ${XUI_INSTALL_URL}"
            return 1
        fi
    fi

    # Determine service name
    service_name=$(xui_service_name)

    if [[ -z "$service_name" ]]; then
        log_warn "Не удалось определить имя сервиса x-ui"
        log_warn "Попробуем использовать имя по умолчанию: x-ui"
        service_name="x-ui"
    fi

    log_debug "Используется сервис: ${service_name}"

    # Check service status
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log_success "Сервис ${service_name} запущен"
    else
        log_warn "Сервис ${service_name} не запущен"
        log_info "Попытка запуска сервиса..."

        # Enable and start service
        if systemctl enable "$service_name" 2>&1 | tee -a "$LOG_FILE"; then
            log_debug "Сервис ${service_name} включен в автозагрузку"
        else
            log_warn "Не удалось включить сервис в автозагрузку"
        fi

        if systemctl start "$service_name" 2>&1 | tee -a "$LOG_FILE"; then
            sleep 2  # Wait for service to start

            if systemctl is-active --quiet "$service_name"; then
                log_success "Сервис ${service_name} успешно запущен"
            else
                log_error "Сервис ${service_name} не активен после запуска"
                systemctl status "$service_name" --no-pager 2>&1 | tee -a "$LOG_FILE" || true
                return 1
            fi
        else
            log_error "Не удалось запустить сервис ${service_name}"
            systemctl status "$service_name" --no-pager 2>&1 | tee -a "$LOG_FILE" || true
            return 1
        fi
    fi

    # Verify installation
    log_info "Проверка конфигурации Xray..."
    local xray_config
    xray_config=$(get_xray_config_json)

    if [[ -n "$xray_config" ]]; then
        log_success "Конфигурация Xray доступна: ${xray_config}"

        # Create initial backup
        backup_configs || log_warn "Не удалось создать резервную копию"
    else
        log_warn "Конфигурация Xray не найдена (это нормально для новой установки)"
    fi

    log_success "Проверка 3x-ui завершена успешно"
    return 0
}

################################################################################
# REALITY KEY GENERATION FUNCTIONS
################################################################################

# Find xray binary
find_xray_binary() {
    local possible_paths=(
        "/usr/local/x-ui/bin/xray-linux-amd64"
        "/usr/local/x-ui/bin/xray"
        "/usr/bin/xray"
        "/usr/local/bin/xray"
    )

    for path in "${possible_paths[@]}"; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    log_error "Xray binary не найден"
    return 1
}

# Generate Reality keypair using xray x25519
# Returns: "PRIVATE_KEY:PUBLIC_KEY"
generate_reality_keypair() {
    log_debug "Генерация Reality keypair"

    local xray_bin
    xray_bin=$(find_xray_binary)

    if [[ -z "$xray_bin" ]]; then
        return 1
    fi

    # Run xray x25519 command
    local output
    output=$("$xray_bin" x25519 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        log_error "Не удалось сгенерировать ключи Reality"
        return 1
    fi

    # Parse output
    # Expected format:
    # Private key: <base64>
    # Public key: <base64>
    local private_key=$(echo "$output" | grep -i "Private key" | awk '{print $NF}')
    local public_key=$(echo "$output" | grep -i "Public key" | awk '{print $NF}')

    if [[ -z "$private_key" ]] || [[ -z "$public_key" ]]; then
        log_error "Не удалось распарсить ключи Reality"
        log_debug "Output: $output"
        return 1
    fi

    log_debug "Private key: ${private_key:0:20}..."
    log_debug "Public key: ${public_key:0:20}..."

    echo "${private_key}:${public_key}"
    return 0
}

# Generate random UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        # Fallback: generate UUID v4 using /dev/urandom
        cat /proc/sys/kernel/random/uuid
    fi
}

# Generate random short ID (8-16 hex chars)
generate_short_id() {
    local length=${1:-8}  # Default 8 chars
    openssl rand -hex $((length / 2)) | cut -c1-${length}
}

################################################################################
# DATABASE FUNCTIONS FOR INBOUNDS
################################################################################

# Check if inbound exists by tag
# Usage: inbound_exists_by_tag "EXIT_IN"
# Returns: 0 if exists, 1 if not
inbound_exists_by_tag() {
    local tag=$1

    if [[ ! -f "$XUI_DB" ]]; then
        log_debug "БД не найдена: ${XUI_DB}"
        return 1
    fi

    local count
    count=$(sqlite3 "$XUI_DB" "SELECT COUNT(*) FROM inbounds WHERE tag='${tag}';" 2>/dev/null || echo "0")

    if [[ "$count" -gt 0 ]]; then
        log_debug "Inbound с tag='${tag}' существует (count=${count})"
        return 0
    else
        log_debug "Inbound с tag='${tag}' не найден"
        return 1
    fi
}

# Get inbound ID by tag
# Usage: get_inbound_id_by_tag "EXIT_IN"
get_inbound_id_by_tag() {
    local tag=$1

    if [[ ! -f "$XUI_DB" ]]; then
        return 1
    fi

    sqlite3 "$XUI_DB" "SELECT id FROM inbounds WHERE tag='${tag}' LIMIT 1;" 2>/dev/null || echo ""
}

# Get inbound port by tag
get_inbound_port_by_tag() {
    local tag=$1

    if [[ ! -f "$XUI_DB" ]]; then
        return 1
    fi

    sqlite3 "$XUI_DB" "SELECT port FROM inbounds WHERE tag='${tag}' LIMIT 1;" 2>/dev/null || echo ""
}

# Get inbound settings by tag (JSON)
get_inbound_settings_by_tag() {
    local tag=$1

    if [[ ! -f "$XUI_DB" ]]; then
        return 1
    fi

    sqlite3 "$XUI_DB" "SELECT settings FROM inbounds WHERE tag='${tag}' LIMIT 1;" 2>/dev/null || echo ""
}

# Get inbound stream_settings by tag (JSON)
get_inbound_stream_settings_by_tag() {
    local tag=$1

    if [[ ! -f "$XUI_DB" ]]; then
        return 1
    fi

    sqlite3 "$XUI_DB" "SELECT stream_settings FROM inbounds WHERE tag='${tag}' LIMIT 1;" 2>/dev/null || echo ""
}

# Extract Reality public key from stream_settings
extract_reality_public_key() {
    local stream_settings=$1
    echo "$stream_settings" | jq -r '.realitySettings.publicKey // empty' 2>/dev/null || echo ""
}

# Extract Reality short IDs from stream_settings
extract_reality_short_ids() {
    local stream_settings=$1
    echo "$stream_settings" | jq -r '.realitySettings.shortIds[0] // empty' 2>/dev/null || echo ""
}

# Extract client UUID by email from settings
extract_client_uuid_by_email() {
    local settings=$1
    local email=$2
    echo "$settings" | jq -r ".clients[] | select(.email==\"${email}\") | .id" 2>/dev/null || echo ""
}

################################################################################
# API FUNCTIONS FOR 3X-UI
################################################################################

# Global variable for session cookie
XUI_SESSION_COOKIE=""

# Login to 3x-ui API
# Sets XUI_SESSION_COOKIE on success
xui_api_login() {
    log_debug "Аутентификация в 3x-ui API"

    # Default credentials
    local username="${XUI_API_USERNAME:-admin}"
    local password="${XUI_API_PASSWORD:-admin}"
    local panel_url="${XUI_API_URL:-http://localhost:2053}"

    local response
    local http_code
    local cookie_file=$(mktemp)

    response=$(curl -s -w "\n%{http_code}" -X POST "${panel_url}/login" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${username}\",\"password\":\"${password}\"}" \
        -c "$cookie_file" 2>&1)

    http_code=$(echo "$response" | tail -1)

    if [[ "$http_code" -eq 200 ]]; then
        if [[ -f "$cookie_file" ]]; then
            XUI_SESSION_COOKIE=$(grep -oP '(?<=3x-ui\s)[^\s]+' "$cookie_file" 2>/dev/null || echo "")

            if [[ -n "$XUI_SESSION_COOKIE" ]]; then
                log_success "Успешная аутентификация в 3x-ui API"
                rm -f "$cookie_file"
                return 0
            fi
        fi

        log_error "Не удалось получить сессию"
        rm -f "$cookie_file"
        return 1
    else
        log_error "Ошибка аутентификации (HTTP ${http_code})"
        rm -f "$cookie_file"
        return 1
    fi
}

################################################################################
# EXIT BRIDGE INBOUND CREATION
################################################################################

# Create EXIT inbound with Reality
# This function is idempotent - it won't create duplicates
create_exit_inbound_reality() {
    log_step "Создание EXIT inbound с Reality"

    local inbound_tag="EXIT_IN"
    local preferred_port=${EXIT_PORT:-443}
    local sni=${EXIT_SNI:-github.com}
    local fingerprint="chrome"

    # Check if inbound already exists
    if inbound_exists_by_tag "$inbound_tag"; then
        log_success "Inbound '${inbound_tag}' уже существует"

        local existing_id=$(get_inbound_id_by_tag "$inbound_tag")
        local existing_port=$(get_inbound_port_by_tag "$inbound_tag")
        local existing_settings=$(get_inbound_settings_by_tag "$inbound_tag")
        local existing_stream=$(get_inbound_stream_settings_by_tag "$inbound_tag")

        log_info "Существующий inbound ID: ${existing_id}"
        log_info "Порт: ${existing_port}"

        # Extract existing parameters
        EXIT_PORT="$existing_port"
        EXIT_PBK=$(extract_reality_public_key "$existing_stream")
        EXIT_SID=$(extract_reality_short_ids "$existing_stream")
        EXIT_UUID=$(extract_client_uuid_by_email "$existing_settings" "bridge-ru@local")

        if [[ -z "$EXIT_UUID" ]]; then
            log_warn "Bridge клиент не найден, UUID будет сгенерирован при следующем запуске"
        fi

        log_success "Параметры загружены из существующего inbound"
        return 0
    fi

    log_info "Создание нового EXIT inbound с Reality"

    # Pick free port
    local actual_port
    actual_port=$(pick_free_port "$preferred_port")

    if [[ -z "$actual_port" ]]; then
        log_error "Не удалось найти свободный порт"
        return 1
    fi

    EXIT_PORT="$actual_port"

    if [[ "$actual_port" != "$preferred_port" ]]; then
        log_warn "Порт ${preferred_port} занят, используется ${actual_port}"
    fi

    # Generate Reality keypair
    log_info "Генерация Reality ключей..."
    local keypair
    keypair=$(generate_reality_keypair)

    if [[ $? -ne 0 ]] || [[ -z "$keypair" ]]; then
        log_error "Не удалось сгенерировать Reality ключи"
        return 1
    fi

    local private_key="${keypair%%:*}"
    local public_key="${keypair##*:}"

    log_success "Reality ключи сгенерированы"

    # Generate short IDs
    local short_id_1=$(generate_short_id 8)
    local short_id_2=$(generate_short_id 16)

    log_debug "Short IDs: ${short_id_1}, ${short_id_2}"

    # Save to global variables (will be used later)
    EXIT_PBK="$public_key"
    EXIT_SID="$short_id_1"

    # Generate bridge client UUID if not set
    if [[ -z "$EXIT_UUID" ]]; then
        EXIT_UUID=$(generate_uuid)
        log_info "Сгенерирован bridge UUID: ${EXIT_UUID}"
    fi

    # Prepare VLESS client settings
    local settings_json=$(jq -n \
        --arg uuid "$EXIT_UUID" \
        --arg email "bridge-ru@local" \
        '{
            clients: [{
                id: $uuid,
                email: $email,
                flow: "",
                limitIp: 0,
                totalGB: 0,
                expiryTime: 0,
                enable: true,
                tgId: "",
                subId: ""
            }],
            decryption: "none",
            fallbacks: []
        }' | jq -c .)

    # Prepare Reality stream settings
    local stream_settings_json=$(jq -n \
        --arg sni "$sni" \
        --arg fp "$fingerprint" \
        --arg pvk "$private_key" \
        --arg pbk "$public_key" \
        --arg sid1 "$short_id_1" \
        --arg sid2 "$short_id_2" \
        '{
            network: "tcp",
            security: "reality",
            realitySettings: {
                show: false,
                dest: ($sni + ":443"),
                xver: 0,
                serverNames: [$sni],
                privateKey: $pvk,
                publicKey: $pbk,
                shortIds: [$sid1, $sid2],
                fingerprint: $fp,
                spiderX: ""
            },
            tcpSettings: {
                acceptProxyProtocol: false,
                header: {
                    type: "none"
                }
            }
        }' | jq -c .)

    # Prepare sniffing
    local sniffing_json=$(jq -n \
        '{
            enabled: true,
            destOverride: ["http", "tls", "quic"]
        }' | jq -c .)

    # Create inbound via API
    log_info "Создание inbound через API..."

    # Login first
    if ! xui_api_login; then
        log_warn "Не удалось авторизоваться в API, пробуем создать через БД"
        create_exit_inbound_via_db "$inbound_tag" "$actual_port" "$settings_json" "$stream_settings_json" "$sniffing_json"
        return $?
    fi

    local panel_url="${XUI_API_URL:-http://localhost:2053}"

    # Prepare full payload
    local json_payload=$(jq -n \
        --argjson enable true \
        --arg remark "EXIT Reality Inbound (bridge)" \
        --arg listen "0.0.0.0" \
        --argjson port "$actual_port" \
        --arg protocol "vless" \
        --arg settings "$settings_json" \
        --arg streamSettings "$stream_settings_json" \
        --arg sniffing "$sniffing_json" \
        --arg tag "$inbound_tag" \
        '{
            enable: $enable,
            remark: $remark,
            listen: $listen,
            port: $port,
            protocol: $protocol,
            settings: $settings,
            streamSettings: $streamSettings,
            sniffing: $sniffing,
            tag: $tag
        }')

    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" -X POST "${panel_url}/panel/api/inbounds/add" \
        -H "Content-Type: application/json" \
        -H "Cookie: 3x-ui=${XUI_SESSION_COOKIE}" \
        -d "$json_payload" 2>&1)

    http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -n -1)

    if [[ "$http_code" -eq 200 ]]; then
        local success=$(echo "$body" | jq -r '.success // false' 2>/dev/null || echo "false")

        if [[ "$success" == "true" ]]; then
            log_success "EXIT inbound успешно создан через API"
            return 0
        else
            local msg=$(echo "$body" | jq -r '.msg // "Unknown error"' 2>/dev/null || echo "Unknown error")
            log_warn "API вернул ошибку: ${msg}"
            log_info "Пробуем создать через БД..."
            create_exit_inbound_via_db "$inbound_tag" "$actual_port" "$settings_json" "$stream_settings_json" "$sniffing_json"
            return $?
        fi
    else
        log_warn "HTTP ошибка: ${http_code}, пробуем через БД"
        create_exit_inbound_via_db "$inbound_tag" "$actual_port" "$settings_json" "$stream_settings_json" "$sniffing_json"
        return $?
    fi
}

# Create EXIT inbound via direct database insertion (fallback)
create_exit_inbound_via_db() {
    local tag=$1
    local port=$2
    local settings=$3
    local stream_settings=$4
    local sniffing=$5

    log_info "Создание inbound напрямую в БД"

    if [[ ! -f "$XUI_DB" ]]; then
        log_error "БД не найдена: ${XUI_DB}"
        return 1
    fi

    # Escape single quotes for SQL
    settings=$(echo "$settings" | sed "s/'/''/g")
    stream_settings=$(echo "$stream_settings" | sed "s/'/''/g")
    sniffing=$(echo "$sniffing" | sed "s/'/''/g")

    local sql="INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing)
               VALUES (1, 0, 0, 0, 'EXIT Reality Inbound (bridge)', 1, 0, '0.0.0.0', ${port}, 'vless', '${settings}', '${stream_settings}', '${tag}', '${sniffing}');"

    # Stop x-ui before modifying DB
    log_info "Остановка x-ui для модификации БД..."
    systemctl stop x-ui
    sleep 2

    # Execute SQL
    if sqlite3 "$XUI_DB" "$sql" 2>&1; then
        log_success "Inbound создан в БД"

        # Start x-ui
        log_info "Запуск x-ui..."
        systemctl start x-ui
        sleep 3

        if systemctl is-active --quiet x-ui; then
            log_success "x-ui успешно запущен"
            return 0
        else
            log_error "x-ui не запустился"
            return 1
        fi
    else
        log_error "Ошибка при вставке в БД"
        systemctl start x-ui
        return 1
    fi
}

################################################################################
# ENTRY BRIDGE INBOUND CREATION
################################################################################

# Create ENTRY inbound with Reality
# This function is idempotent - it won't create duplicates
create_entry_inbound_reality() {
    log_step "Создание ENTRY inbound с Reality"

    local inbound_tag="ENTRY_IN"
    local preferred_port=${ENTRY_PORT:-8443}
    local sni=${ENTRY_SNI:-yandex.ru}
    local fingerprint=${ENTRY_FP:-chrome}

    # Check if inbound already exists
    if inbound_exists_by_tag "$inbound_tag"; then
        log_success "Inbound '${inbound_tag}' уже существует"

        local existing_id=$(get_inbound_id_by_tag "$inbound_tag")
        local existing_port=$(get_inbound_port_by_tag "$inbound_tag")
        local existing_stream=$(get_inbound_stream_settings_by_tag "$inbound_tag")

        log_info "Существующий inbound ID: ${existing_id}"
        log_info "Порт: ${existing_port}"

        # Extract existing parameters
        ENTRY_PORT="$existing_port"
        ENTRY_PBK=$(extract_reality_public_key "$existing_stream")
        ENTRY_SID=$(extract_reality_short_ids "$existing_stream")
        ENTRY_SNI=$(echo "$existing_stream" | jq -r '.realitySettings.serverNames[0] // empty' 2>/dev/null || echo "$sni")

        log_success "Параметры загружены из существующего inbound"
        return 0
    fi

    log_info "Создание нового ENTRY inbound с Reality"

    # Pick free port
    local actual_port
    actual_port=$(pick_free_port "$preferred_port")

    if [[ -z "$actual_port" ]]; then
        log_error "Не удалось найти свободный порт"
        return 1
    fi

    ENTRY_PORT="$actual_port"

    if [[ "$actual_port" != "$preferred_port" ]]; then
        log_warn "Порт ${preferred_port} занят, используется ${actual_port}"
    fi

    # Generate Reality keypair
    log_info "Генерация Reality ключей..."
    local keypair
    keypair=$(generate_reality_keypair)

    if [[ $? -ne 0 ]] || [[ -z "$keypair" ]]; then
        log_error "Не удалось сгенерировать Reality ключи"
        return 1
    fi

    local private_key="${keypair%%:*}"
    local public_key="${keypair##*:}"

    log_success "Reality ключи сгенерированы"

    # Generate short IDs
    local short_id_1=$(generate_short_id 8)
    local short_id_2=$(generate_short_id 16)

    log_debug "Short IDs: ${short_id_1}, ${short_id_2}"

    # Save to global variables
    ENTRY_PBK="$public_key"
    ENTRY_SID="$short_id_1"
    ENTRY_SNI="$sni"
    ENTRY_FP="$fingerprint"

    # Prepare VLESS client settings (empty clients array for now)
    local settings_json=$(jq -n \
        '{
            clients: [],
            decryption: "none",
            fallbacks: []
        }' | jq -c .)

    # Prepare Reality stream settings
    local stream_settings_json=$(jq -n \
        --arg sni "$sni" \
        --arg fp "$fingerprint" \
        --arg pvk "$private_key" \
        --arg pbk "$public_key" \
        --arg sid1 "$short_id_1" \
        --arg sid2 "$short_id_2" \
        '{
            network: "tcp",
            security: "reality",
            realitySettings: {
                show: false,
                dest: ($sni + ":443"),
                xver: 0,
                serverNames: [$sni],
                privateKey: $pvk,
                publicKey: $pbk,
                shortIds: [$sid1, $sid2],
                fingerprint: $fp,
                spiderX: ""
            },
            tcpSettings: {
                acceptProxyProtocol: false,
                header: {
                    type: "none"
                }
            }
        }' | jq -c .)

    # Prepare sniffing
    local sniffing_json=$(jq -n \
        '{
            enabled: true,
            destOverride: ["http", "tls", "quic", "fakedns"]
        }' | jq -c .)

    # Create inbound via API
    log_info "Создание inbound через API..."

    # Login first
    if ! xui_api_login; then
        log_warn "Не удалось авторизоваться в API, пробуем создать через БД"
        create_entry_inbound_via_db "$inbound_tag" "$actual_port" "$settings_json" "$stream_settings_json" "$sniffing_json"
        return $?
    fi

    local panel_url="${XUI_API_URL:-http://localhost:2053}"

    # Prepare full payload
    local json_payload=$(jq -n \
        --argjson enable true \
        --arg remark "ENTRY Reality Inbound (users)" \
        --arg listen "0.0.0.0" \
        --argjson port "$actual_port" \
        --arg protocol "vless" \
        --arg settings "$settings_json" \
        --arg streamSettings "$stream_settings_json" \
        --arg sniffing "$sniffing_json" \
        --arg tag "$inbound_tag" \
        '{
            enable: $enable,
            remark: $remark,
            listen: $listen,
            port: $port,
            protocol: $protocol,
            settings: $settings,
            streamSettings: $streamSettings,
            sniffing: $sniffing,
            tag: $tag
        }')

    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" -X POST "${panel_url}/panel/api/inbounds/add" \
        -H "Content-Type: application/json" \
        -H "Cookie: 3x-ui=${XUI_SESSION_COOKIE}" \
        -d "$json_payload" 2>&1)

    http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -n -1)

    if [[ "$http_code" -eq 200 ]]; then
        local success=$(echo "$body" | jq -r '.success // false' 2>/dev/null || echo "false")

        if [[ "$success" == "true" ]]; then
            log_success "ENTRY inbound успешно создан через API"
            return 0
        else
            local msg=$(echo "$body" | jq -r '.msg // "Unknown error"' 2>/dev/null || echo "Unknown error")
            log_warn "API вернул ошибку: ${msg}"
            log_info "Пробуем создать через БД..."
            create_entry_inbound_via_db "$inbound_tag" "$actual_port" "$settings_json" "$stream_settings_json" "$sniffing_json"
            return $?
        fi
    else
        log_warn "HTTP ошибка: ${http_code}, пробуем через БД"
        create_entry_inbound_via_db "$inbound_tag" "$actual_port" "$settings_json" "$stream_settings_json" "$sniffing_json"
        return $?
    fi
}

# Create ENTRY inbound via direct database insertion (fallback)
create_entry_inbound_via_db() {
    local tag=$1
    local port=$2
    local settings=$3
    local stream_settings=$4
    local sniffing=$5

    log_info "Создание inbound напрямую в БД"

    if [[ ! -f "$XUI_DB" ]]; then
        log_error "БД не найдена: ${XUI_DB}"
        return 1
    fi

    # Escape single quotes for SQL
    settings=$(echo "$settings" | sed "s/'/''/g")
    stream_settings=$(echo "$stream_settings" | sed "s/'/''/g")
    sniffing=$(echo "$sniffing" | sed "s/'/''/g")

    local sql="INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing)
               VALUES (1, 0, 0, 0, 'ENTRY Reality Inbound (users)', 1, 0, '0.0.0.0', ${port}, 'vless', '${settings}', '${stream_settings}', '${tag}', '${sniffing}');"

    # Stop x-ui before modifying DB
    log_info "Остановка x-ui для модификации БД..."
    systemctl stop x-ui
    sleep 2

    # Execute SQL
    if sqlite3 "$XUI_DB" "$sql" 2>&1; then
        log_success "Inbound создан в БД"

        # Start x-ui
        log_info "Запуск x-ui..."
        systemctl start x-ui
        sleep 3

        if systemctl is-active --quiet x-ui; then
            log_success "x-ui успешно запущен"
            return 0
        else
            log_error "x-ui не запустился"
            return 1
        fi
    else
        log_error "Ошибка при вставке в БД"
        systemctl start x-ui
        return 1
    fi
}

################################################################################
# VLESS LINK GENERATION
################################################################################

# Generate VLESS link for bridge client
# ⚠️ НЕ ВЫДАВАТЬ ПОЛЬЗОВАТЕЛЯМ - только для ENTRY сервера
generate_bridge_vless_link() {
    local uuid=$1
    local server_ip=$2
    local port=$3
    local sni=$4
    local public_key=$5
    local short_id=$6
    local fp=${7:-chrome}

    # URL encode function
    urlencode() {
        local string="$1"
        echo -n "$string" | jq -sRr @uri
    }

    # Build VLESS URL
    # Format: vless://UUID@IP:PORT?security=reality&sni=SNI&fp=FP&pbk=PBK&sid=SID&type=tcp&flow=#NAME
    local name="EXIT-Bridge-RU"
    local encoded_name=$(urlencode "$name")

    local vless_url="vless://${uuid}@${server_ip}:${port}?encryption=none&security=reality&sni=${sni}&fp=${fp}&pbk=${public_key}&sid=${short_id}&type=tcp&flow=#${encoded_name}"

    echo "$vless_url"
}

# Setup EXIT bridge
setup_exit_bridge() {
    log_step "Настройка EXIT моста"

    # Set default SNI if not provided
    EXIT_SNI=${EXIT_SNI:-github.com}
    EXIT_PORT=${EXIT_PORT:-443}

    # Create EXIT inbound with Reality
    create_exit_inbound_reality || {
        log_error "Не удалось создать EXIT inbound"
        return 1
    }

    # Get server IP
    local server_ip
    server_ip=$(curl -s -4 ifconfig.me 2>/dev/null) || \
    server_ip=$(curl -s -4 icanhazip.com 2>/dev/null) || \
    server_ip=$(hostname -I | awk '{print $1}')

    if [[ -z "$server_ip" ]]; then
        log_warn "Не удалось определить внешний IP"
        server_ip="UNKNOWN_IP"
    fi

    log_info "Внешний IP сервера: ${server_ip}"

    # Save all bridge artifacts
    log_info "Сохранение артефактов..."

    update_artifact "role" "exit"
    update_artifact "exit.ip" "$server_ip"
    update_artifact "exit.port" "$EXIT_PORT"
    update_artifact "exit.sni" "$EXIT_SNI"
    update_artifact "exit.fingerprint" "chrome"
    update_artifact "exit.publicKey" "$EXIT_PBK"
    update_artifact "exit.shortId" "$EXIT_SID"
    update_artifact "exit.bridgeUuid" "$EXIT_UUID"
    update_artifact "exit.configured" "true"
    update_artifact "exit.configured_at" "$(date -Iseconds)"

    # Generate bridge VLESS link
    log_info "Генерация bridge VLESS ссылки..."
    local vless_link
    vless_link=$(generate_bridge_vless_link "$EXIT_UUID" "$server_ip" "$EXIT_PORT" "$EXIT_SNI" "$EXIT_PBK" "$EXIT_SID")

    update_artifact "exit.bridgeVlessLink" "$vless_link"

    log_success "Артефакты сохранены в: ${RVPN_ARTIFACTS}"

    # Display configuration
    log_step "EXIT Конфигурация"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "IP адрес:        ${server_ip}"
    log_info "Порт:            ${EXIT_PORT}"
    log_info "SNI:             ${EXIT_SNI}"
    log_info "Fingerprint:     chrome"
    log_info "Public Key:      ${EXIT_PBK:0:32}..."
    log_info "Short ID:        ${EXIT_SID}"
    log_info "Bridge UUID:     ${EXIT_UUID}"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_warn ""
    log_warn "⚠️  ВАЖНО: Bridge VLESS ссылка - НЕ ДЛЯ ПОЛЬЗОВАТЕЛЕЙ!"
    log_warn "⚠️  Используется ТОЛЬКО ENTRY сервером для подключения"
    log_warn ""
    log_info "Bridge VLESS Link:"
    echo "$vless_link"
    log_warn ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Verify port is listening
    log_step "Проверка EXIT inbound"

    sleep 3  # Wait for service to bind

    if is_port_listening "$EXIT_PORT"; then
        log_success "Порт ${EXIT_PORT} прослушивается"
    else
        log_warn "Порт ${EXIT_PORT} не прослушивается (может потребоваться время)"
    fi

    # Verify inbound exists in config
    local xray_config
    xray_config=$(get_xray_config_json)

    if [[ -n "$xray_config" ]]; then
        if jq -e ".inbounds[] | select(.tag==\"EXIT_IN\")" "$xray_config" &>/dev/null; then
            log_success "Inbound 'EXIT_IN' присутствует в config.json"
        else
            log_warn "Inbound 'EXIT_IN' не найден в config.json (может быть в БД)"
        fi
    fi

    log_success "EXIT сервер настроен и готов принимать подключения"
    return 0
}

# Setup ENTRY bridge
setup_entry_bridge() {
    log_step "Настройка ENTRY моста"

    # Set default SNI if not provided
    ENTRY_SNI=${ENTRY_SNI:-yandex.ru}
    ENTRY_PORT=${ENTRY_PORT:-8443}
    ENTRY_FP=${ENTRY_FP:-chrome}

    # Create ENTRY inbound with Reality
    create_entry_inbound_reality || {
        log_error "Не удалось создать ENTRY inbound"
        return 1
    }

    # Get server IP
    local server_ip
    server_ip=$(curl -s -4 ifconfig.me 2>/dev/null) || \
    server_ip=$(curl -s -4 icanhazip.com 2>/dev/null) || \
    server_ip=$(hostname -I | awk '{print $1}')

    if [[ -z "$server_ip" ]]; then
        log_warn "Не удалось определить внешний IP"
        server_ip="UNKNOWN_IP"
    fi

    log_info "Внешний IP сервера: ${server_ip}"

    # Save all ENTRY artifacts
    log_info "Сохранение артефактов ENTRY..."

    update_artifact "entry.ip" "$server_ip"
    update_artifact "entry.port" "$ENTRY_PORT"
    update_artifact "entry.sni" "$ENTRY_SNI"
    update_artifact "entry.fingerprint" "$ENTRY_FP"
    update_artifact "entry.publicKey" "$ENTRY_PBK"
    update_artifact "entry.shortId" "$ENTRY_SID"
    update_artifact "entry.configured" "true"
    update_artifact "entry.configured_at" "$(date -Iseconds)"

    log_success "Артефакты сохранены в: ${RVPN_ARTIFACTS}"

    # Display configuration
    log_step "ENTRY Конфигурация"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "IP адрес:        ${server_ip}"
    log_info "Порт:            ${ENTRY_PORT}"
    log_info "SNI:             ${ENTRY_SNI}"
    log_info "Fingerprint:     ${ENTRY_FP}"
    log_info "Public Key:      ${ENTRY_PBK:0:32}..."
    log_info "Short ID:        ${ENTRY_SID}"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_warn ""
    log_warn "⚠️  ВАЖНО: ENTRY inbound готов для подключения пользователей"
    log_warn "⚠️  Outbound и routing будут настроены в следующих подзадачах"
    log_warn ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Verify port is listening
    log_step "Проверка ENTRY inbound"

    sleep 3  # Wait for service to bind

    if is_port_listening "$ENTRY_PORT"; then
        log_success "Порт ${ENTRY_PORT} прослушивается"
    else
        log_warn "Порт ${ENTRY_PORT} не прослушивается (может потребоваться время)"
    fi

    # Verify inbound exists in config
    local xray_config
    xray_config=$(get_xray_config_json)

    if [[ -n "$xray_config" ]]; then
        if jq -e ".inbounds[] | select(.tag==\"ENTRY_IN\")" "$xray_config" &>/dev/null; then
            log_success "Inbound 'ENTRY_IN' присутствует в config.json"
        else
            log_warn "Inbound 'ENTRY_IN' не найден в config.json (может быть в БД)"
        fi
    fi

    log_success "ENTRY сервер настроен и готов принимать пользователей"
    log_info "TODO: Outbound на EXIT + routing (следующие подзадачи)"
    return 0
}

# Create test client
create_test_client() {
    log_step "Создание тестового клиента"
    log_info "TODO: Создание тестового клиента на ENTRY (будет реализовано в следующих задачах)"

    # Stub: будет реализовано позже
    update_artifact "test_client.created" "true"
}

# Run tests
run_tests() {
    log_step "Запуск тестов"
    log_info "TODO: Выполнение тестов (порты, доступность, routing) (будет реализовано в следующих задачах)"

    # Stub: будет реализовано позже
    log_success "Базовые проверки пройдены (stub)"
}

# Collect diagnostics
collect_diagnostics() {
    local status=${1:-"unknown"}
    local exit_code=${2:-"0"}

    log_debug "Сбор диагностики: status=${status}, exit_code=${exit_code}"

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local diag_file="${RVPN_DIAG_DIR}/diagnostics_${timestamp}.log"

    {
        echo "=========================================="
        echo "Reality VPN Bridge Diagnostics"
        echo "=========================================="
        echo "Timestamp: $(date -Iseconds)"
        echo "Status: ${status}"
        echo "Exit Code: ${exit_code}"
        echo "Role: ${ROLE}"
        echo ""
        echo "=========================================="
        echo "System Information"
        echo "=========================================="
        uname -a
        echo ""
        echo "--- OS Release ---"
        cat /etc/os-release 2>/dev/null || echo "N/A"
        echo ""
        echo "=========================================="
        echo "Artifacts"
        echo "=========================================="
        if [[ -f "$RVPN_ARTIFACTS" ]]; then
            cat "$RVPN_ARTIFACTS"
        else
            echo "Artifacts file not found"
        fi
        echo ""
        echo "=========================================="
        echo "Setup Log (last 100 lines)"
        echo "=========================================="
        if [[ -f "$LOG_FILE" ]]; then
            tail -n 100 "$LOG_FILE"
        else
            echo "Log file not found"
        fi
        echo ""
        echo "=========================================="
        echo "3x-ui Service Status"
        echo "=========================================="
        systemctl status x-ui 2>&1 || echo "Service not found"
        echo ""
    } > "$diag_file"

    log_debug "Диагностика сохранена: ${diag_file}"

    # Update artifacts with diagnostic info
    update_artifact "metadata.last_diagnostic" "$diag_file"
    update_artifact "metadata.last_status" "$status"
}

################################################################################
# MAIN FUNCTION
################################################################################

main() {
    # Initialize
    check_root "$@"
    init_logging
    init_artifacts

    # Parse arguments
    parse_arguments "$@"

    # Interactive mode
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
        ask_role
        ask_exit_parameters
    fi

    # Validate required parameters
    if [[ -z "$ROLE" ]]; then
        log_error "Роль сервера не указана. Используйте --role entry|exit"
        show_usage
        exit 1
    fi

    log_info "Роль сервера: ${ROLE}"

    # Save configuration
    save_config_to_artifacts
    log_info "Конфигурация сохранена"

    # Execute setup steps
    log_info "Начинаем установку зависимостей"
    install_deps
    log_info "Зависимости установлены, проверяем 3x-ui"
    ensure_3xui

    if [[ "$ROLE" == "exit" ]]; then
        setup_exit_bridge
    elif [[ "$ROLE" == "entry" ]]; then
        setup_entry_bridge
        create_test_client
    fi

    run_tests

    log_success "=========================================="
    log_success "Настройка завершена!"
    log_success "=========================================="
    log_info "Артефакты: ${RVPN_ARTIFACTS}"
    log_info "Логи: ${LOG_FILE}"
    log_info "Диагностика: ${RVPN_DIAG_DIR}"
}

# Run main function
main "$@"
