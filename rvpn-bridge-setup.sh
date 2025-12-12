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
# MAIN SETUP FUNCTIONS (STUBS)
################################################################################

# Install dependencies
install_deps() {
    log_step "Установка зависимостей"

    local missing_pkgs=()

    # Check curl
    if ! command -v curl &> /dev/null; then
        missing_pkgs+=("curl")
        log_debug "Отсутствует: curl"
    else
        log_debug "Найден: curl"
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_pkgs+=("jq")
        log_debug "Отсутствует: jq"
    else
        log_debug "Найден: jq"
    fi

    # Check sqlite3
    if ! command -v sqlite3 &> /dev/null; then
        missing_pkgs+=("sqlite3")
        log_debug "Отсутствует: sqlite3"
    else
        log_debug "Найден: sqlite3"
    fi

    # Check netcat (nc command)
    if ! command -v nc &> /dev/null; then
        missing_pkgs+=("netcat-openbsd")
        log_debug "Отсутствует: nc (netcat)"
    else
        log_debug "Найден: nc (netcat)"
    fi

    # Check net-tools (netstat command)
    if ! command -v netstat &> /dev/null; then
        missing_pkgs+=("net-tools")
        log_debug "Отсутствует: netstat (net-tools)"
    else
        log_debug "Найден: netstat (net-tools)"
    fi

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        log_info "Установка недостающих пакетов: ${missing_pkgs[*]}"

        # Update package lists (allow warnings)
        set +e
        DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>&1
        local update_status=$?
        set -e

        if [[ $update_status -ne 0 ]]; then
            log_warn "apt-get update завершился с предупреждениями (код: ${update_status})"
        fi

        # Install packages
        set +e
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_pkgs[@]}" 2>&1
        local install_status=$?
        set -e

        if [[ $install_status -eq 0 ]]; then
            log_success "Зависимости установлены"
        else
            log_warn "Некоторые пакеты не удалось установить (код: ${install_status}). Продолжаем..."
        fi
    else
        log_success "Все зависимости уже установлены"
    fi
}

# Ensure 3x-ui is installed and running
ensure_3xui() {
    log_step "Проверка 3x-ui"

    if [[ -d "$XUI_DIR" ]]; then
        log_success "3x-ui уже установлен"
    else
        log_warn "3x-ui не найден, начинается установка..."
        log_info "TODO: Установка 3x-ui (будет реализовано в следующих задачах)"
        # bash <(curl -Ls "$XUI_INSTALL_URL")
    fi

    # Check service status
    if systemctl is-active --quiet x-ui; then
        log_success "Сервис x-ui запущен"
    else
        log_warn "Сервис x-ui не запущен"
        log_info "TODO: Запуск сервиса x-ui (будет реализовано в следующих задачах)"
    fi
}

# Setup EXIT bridge
setup_exit_bridge() {
    log_step "Настройка EXIT моста"
    log_info "TODO: Создание EXIT inbound + bridge client (будет реализовано в следующих задачах)"

    # Stub: будет реализовано позже
    update_artifact "exit.configured" "true"
    update_artifact "exit.configured_at" "$(date -Iseconds)"
}

# Setup ENTRY bridge
setup_entry_bridge() {
    log_step "Настройка ENTRY моста"
    log_info "TODO: Создание ENTRY inbound + outbound на EXIT + routing (будет реализовано в следующих задачах)"

    # Stub: будет реализовано позже
    update_artifact "entry.configured" "true"
    update_artifact "entry.configured_at" "$(date -Iseconds)"
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

    # Execute setup steps
    install_deps
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
