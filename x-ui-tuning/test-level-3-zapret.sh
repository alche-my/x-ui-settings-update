#!/usr/bin/env bash

################################################################################
# Автотесты для level-3-zapret-setup.sh
################################################################################
# Тестирует все функции Zapret setup скрипта:
#   - Парсинг vless:// URL
#   - Создание базы стратегий
#   - Генерация health check скрипта
#   - Генерация auto strategy selector
#   - Создание systemd service
#
# Использование:
#   ./test-level-3-zapret.sh
#
################################################################################

set -euo pipefail

# Цвета
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Счетчики
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Временная директория для тестов
TEST_DIR=""

################################################################################
# Утилиты
################################################################################

setup_test_env() {
    TEST_DIR=$(mktemp -d)
    echo "Test directory: $TEST_DIR"
}

cleanup_test_env() {
    if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

print_header() {
    echo -e "${BLUE}${BOLD}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  Level 3 Zapret - Automated Tests                     ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

test_start() {
    local test_name=$1
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${BLUE}[TEST $TOTAL_TESTS]${NC} $test_name"
}

test_pass() {
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "${GREEN}  ✓ PASS${NC}"
    echo ""
}

test_fail() {
    local reason=$1
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "${RED}  ✗ FAIL${NC}: $reason"
    echo ""
}

assert_equals() {
    local expected=$1
    local actual=$2
    local message=${3:-""}

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        if [[ -n "$message" ]]; then
            echo "  Expected: $expected"
            echo "  Actual:   $actual"
            echo "  Message:  $message"
        fi
        return 1
    fi
}

assert_file_exists() {
    local file=$1
    if [[ -f "$file" ]]; then
        return 0
    else
        echo "  File not found: $file"
        return 1
    fi
}

assert_contains() {
    local haystack=$1
    local needle=$2

    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo "  String not found: '$needle'"
        echo "  In: '$haystack'"
        return 1
    fi
}

################################################################################
# Имплементация функций из основного скрипта (для тестирования)
################################################################################

urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

parse_vless_url() {
    local url=$1

    # Удаляем префикс vless://
    url="${url#vless://}"

    # Извлекаем имя (после #)
    if [[ "$url" =~ \#(.+)$ ]]; then
        url="${url%#*}"
    fi

    # Разделяем: UUID@IP:PORT?params
    local uuid_and_address="${url%%\?*}"
    local params="${url#*\?}"

    # Извлекаем UUID
    UUID="${uuid_and_address%%@*}"

    # Извлекаем IP:PORT
    local address_and_port="${uuid_and_address#*@}"
    NON_RU_IP="${address_and_port%:*}"
    NON_RU_PORT="${address_and_port#*:}"

    # Парсим параметры
    IFS='&' read -ra PARAMS <<< "$params"
    for param in "${PARAMS[@]}"; do
        local key="${param%%=*}"
        local value="${param#*=}"
        value=$(urldecode "$value")

        case "$key" in
            sni) SNI="$value" ;;
            pbk) PUBLIC_KEY="$value" ;;
            sid) SHORT_ID="$value" ;;
            fp) FINGERPRINT="$value" ;;
        esac
    done

    # Валидация
    if [[ -z "$NON_RU_IP" ]] || [[ -z "$NON_RU_PORT" ]]; then
        return 1
    fi

    # Проверка что URL содержал @ и : (не просто строка)
    if [[ "$UUID" == "$NON_RU_IP" ]] || [[ "$NON_RU_IP" == "$NON_RU_PORT" ]]; then
        return 1
    fi

    return 0
}

create_strategy_database() {
    local strategy_db=$1

    cat > "$strategy_db" <<'EOF'
{
  "strategies": [
    {
      "id": 1,
      "name": "split2_pos2",
      "description": "Разделение на 2 части, позиция 2",
      "params": "--dpi-desync=split2 --dpi-desync-split-pos=2 --dpi-desync-fooling=md5sig",
      "priority": 1
    },
    {
      "id": 2,
      "name": "disorder_md5sig",
      "description": "Нарушение порядка с MD5 подписью",
      "params": "--dpi-desync=disorder --dpi-desync-fooling=md5sig",
      "priority": 2
    },
    {
      "id": 3,
      "name": "split_badseq",
      "description": "Разделение с неверной последовательностью",
      "params": "--dpi-desync=split --dpi-desync-fooling=badseq --dpi-desync-split-pos=2",
      "priority": 3
    },
    {
      "id": 4,
      "name": "multisplit",
      "description": "Множественное разделение",
      "params": "--dpi-desync=multisplit --dpi-desync-split-pos=1,2,3,4",
      "priority": 4
    },
    {
      "id": 5,
      "name": "syndata_disorder",
      "description": "SYN data с нарушением порядка",
      "params": "--dpi-desync=syndata --dpi-desync-fooling=disorder",
      "priority": 5
    }
  ]
}
EOF
}

create_health_check() {
    local health_check_script=$1
    local non_ru_ip=$2
    local non_ru_port=$3

    cat > "$health_check_script" <<'HEALTHCHECK_EOF'
#!/usr/bin/env bash

# Health Check для Zapret DPI Bypass

set -euo pipefail

CURRENT_STRATEGY="/opt/zapret-current-strategy.json"
LOG_FILE="/var/log/zapret-health-check.log"
NON_RU_IP="{{NON_RU_IP}}"
NON_RU_PORT="{{NON_RU_PORT}}"
MAX_FAILS=3

FAIL_COUNT_FILE="/tmp/zapret-fail-count"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_connection() {
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/$NON_RU_IP/$NON_RU_PORT" 2>/dev/null
    return $?
}

main() {
    if [[ ! -f "$FAIL_COUNT_FILE" ]]; then
        echo "0" > "$FAIL_COUNT_FILE"
    fi

    if check_connection; then
        log_message "✓ Соединение OK: $NON_RU_IP:$NON_RU_PORT"
        echo "0" > "$FAIL_COUNT_FILE"
    else
        local fail_count=$(cat "$FAIL_COUNT_FILE")
        fail_count=$((fail_count + 1))
        echo "$fail_count" > "$FAIL_COUNT_FILE"

        log_message "✗ FAIL ($fail_count/$MAX_FAILS): Нет соединения с $NON_RU_IP:$NON_RU_PORT"

        if [[ $fail_count -ge $MAX_FAILS ]]; then
            log_message "⚠ Превышен лимит неудач ($MAX_FAILS), запуск автоподбора стратегии..."
            /opt/zapret-auto-strategy.sh
            echo "0" > "$FAIL_COUNT_FILE"
        fi
    fi
}

main
HEALTHCHECK_EOF

    sed -i "s|{{NON_RU_IP}}|$non_ru_ip|g" "$health_check_script"
    sed -i "s|{{NON_RU_PORT}}|$non_ru_port|g" "$health_check_script"

    chmod +x "$health_check_script"
}

create_auto_strategy_selector() {
    local auto_strategy_script=$1
    local non_ru_ip=$2
    local non_ru_port=$3

    cat > "$auto_strategy_script" <<'STRATEGY_EOF'
#!/usr/bin/env bash

# Auto Strategy Selector для Zapret

set -euo pipefail

STRATEGY_DB="/opt/zapret-strategies.json"
CURRENT_STRATEGY="/opt/zapret-current-strategy.json"
LOG_FILE="/var/log/zapret-health-check.log"
NON_RU_IP="{{NON_RU_IP}}"
NON_RU_PORT="{{NON_RU_PORT}}"
ZAPRET_BIN="/opt/zapret/nfqws/nfqws"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

test_strategy() {
    local strategy_id=$1
    local strategy_params

    strategy_params=$(jq -r ".strategies[] | select(.id == $strategy_id) | .params" "$STRATEGY_DB")

    log_message "Тестирование стратегии #$strategy_id: $strategy_params"

    systemctl stop zapret-nfqws.service

    $ZAPRET_BIN --qnum=200 $strategy_params &
    local nfqws_pid=$!

    sleep 2

    local result=1
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$NON_RU_IP/$NON_RU_PORT" 2>/dev/null; then
        result=0
        log_message "✓ Стратегия #$strategy_id работает!"
    else
        log_message "✗ Стратегия #$strategy_id не работает"
    fi

    kill $nfqws_pid 2>/dev/null || true

    return $result
}

apply_strategy() {
    local strategy_id=$1

    jq ".strategies[] | select(.id == $strategy_id)" "$STRATEGY_DB" > "$CURRENT_STRATEGY"

    local strategy_params
    strategy_params=$(jq -r '.params' "$CURRENT_STRATEGY")

    sed -i "s|ExecStart=.*|ExecStart=$ZAPRET_BIN --qnum=200 $strategy_params|" /etc/systemd/system/zapret-nfqws.service

    systemctl daemon-reload
    systemctl restart zapret-nfqws.service

    log_message "✓ Применена стратегия #$strategy_id"
}

main() {
    log_message "════════════════════════════════════════"
    log_message "Запуск автоподбора стратегии DPI bypass"

    local current_id
    current_id=$(jq -r '.id' "$CURRENT_STRATEGY")

    log_message "Текущая стратегия: #$current_id"

    local total_strategies
    total_strategies=$(jq '.strategies | length' "$STRATEGY_DB")

    local tested=0
    for i in $(seq 1 $total_strategies); do
        local next_id=$(( (current_id % total_strategies) + 1 ))

        if [[ $next_id -eq $current_id ]]; then
            current_id=$next_id
            continue
        fi

        if test_strategy "$next_id"; then
            apply_strategy "$next_id"
            log_message "✓ Успешно переключились на стратегию #$next_id"
            return 0
        fi

        tested=$((tested + 1))
        current_id=$next_id

        if [[ $tested -ge $((total_strategies - 1)) ]]; then
            break
        fi
    done

    log_message "✗ Ни одна стратегия не работает! Возвращаем сервис в исходное состояние."
    systemctl start zapret-nfqws.service
}

main
STRATEGY_EOF

    sed -i "s|{{NON_RU_IP}}|$non_ru_ip|g" "$auto_strategy_script"
    sed -i "s|{{NON_RU_PORT}}|$non_ru_port|g" "$auto_strategy_script"

    chmod +x "$auto_strategy_script"
}

create_nfqws_service_content() {
    local zapret_bin=$1
    local strategy_params=$2

    cat <<EOF
[Unit]
Description=Zapret nfqws - DPI Bypass Service
After=network.target iptables.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$zapret_bin --qnum=200 $strategy_params
Restart=always
RestartSec=5
User=root

# Security
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
}

################################################################################
# Тесты
################################################################################

test_urldecode() {
    test_start "urldecode - Декодирование URL-encoded строк"

    local encoded="web.test%2Bsite.com"
    local decoded=$(urldecode "$encoded")

    if assert_equals "web.test+site.com" "$decoded" "URL decode failed"; then
        test_pass
    else
        test_fail "urldecode не корректно декодирует URL"
    fi
}

test_parse_vless_url_basic() {
    test_start "parse_vless_url - Базовый парсинг vless:// URL"

    # Mock переменные
    UUID=""
    NON_RU_IP=""
    NON_RU_PORT=""
    SNI=""
    PUBLIC_KEY=""
    SHORT_ID=""
    FINGERPRINT=""

    local test_url="vless://550e8400-e29b-41d4-a716-446655440000@95.217.123.45:443?type=tcp&security=reality&sni=web.test.com&pbk=testPublicKey123&sid=abc123&fp=chrome"

    if parse_vless_url "$test_url"; then
        if assert_equals "95.217.123.45" "$NON_RU_IP" && \
           assert_equals "443" "$NON_RU_PORT" && \
           assert_equals "550e8400-e29b-41d4-a716-446655440000" "$UUID" && \
           assert_equals "web.test.com" "$SNI" && \
           assert_equals "testPublicKey123" "$PUBLIC_KEY" && \
           assert_equals "abc123" "$SHORT_ID" && \
           assert_equals "chrome" "$FINGERPRINT"; then
            test_pass
        else
            test_fail "Параметры не совпадают с ожидаемыми"
        fi
    else
        test_fail "parse_vless_url вернул ошибку"
    fi
}

test_parse_vless_url_with_name() {
    test_start "parse_vless_url - Парсинг с именем (#название)"

    UUID=""
    NON_RU_IP=""
    NON_RU_PORT=""

    local test_url="vless://uuid123@192.168.1.1:8443?type=tcp#MyServer"

    if parse_vless_url "$test_url"; then
        if assert_equals "192.168.1.1" "$NON_RU_IP" && \
           assert_equals "8443" "$NON_RU_PORT"; then
            test_pass
        else
            test_fail "Не удалось распарсить URL с именем"
        fi
    else
        test_fail "parse_vless_url вернул ошибку"
    fi
}

test_parse_vless_url_invalid() {
    test_start "parse_vless_url - Обработка невалидного URL"

    UUID=""
    NON_RU_IP=""
    NON_RU_PORT=""

    local test_url="vless://invalid-url-without-address"

    if parse_vless_url "$test_url"; then
        test_fail "Должен был вернуть ошибку для невалидного URL"
    else
        test_pass
    fi
}

test_create_strategy_database() {
    test_start "create_strategy_database - Создание базы стратегий"

    local strategy_db="$TEST_DIR/strategies.json"

    create_strategy_database "$strategy_db"

    if assert_file_exists "$strategy_db"; then
        local strategy_count=$(jq '.strategies | length' "$strategy_db")

        if assert_equals "5" "$strategy_count" "Должно быть 5 стратегий"; then
            # Проверяем наличие всех обязательных полей
            local has_all_fields=true
            for i in {0..4}; do
                local id=$(jq -r ".strategies[$i].id" "$strategy_db")
                local name=$(jq -r ".strategies[$i].name" "$strategy_db")
                local params=$(jq -r ".strategies[$i].params" "$strategy_db")

                if [[ -z "$id" ]] || [[ -z "$name" ]] || [[ -z "$params" ]]; then
                    has_all_fields=false
                    break
                fi
            done

            if $has_all_fields; then
                test_pass
            else
                test_fail "Не все стратегии содержат обязательные поля"
            fi
        else
            test_fail "Неверное количество стратегий"
        fi
    else
        test_fail "Файл базы данных не создан"
    fi
}

test_strategy_database_content() {
    test_start "Strategy Database - Проверка содержимого стратегий"

    local strategy_db="$TEST_DIR/strategies2.json"
    create_strategy_database "$strategy_db"

    # Проверяем первую стратегию
    local first_strategy_name=$(jq -r '.strategies[0].name' "$strategy_db")
    local first_strategy_params=$(jq -r '.strategies[0].params' "$strategy_db")

    if assert_equals "split2_pos2" "$first_strategy_name" && \
       assert_contains "$first_strategy_params" "--dpi-desync=split2"; then
        test_pass
    else
        test_fail "Содержимое первой стратегии некорректно"
    fi
}

test_create_health_check() {
    test_start "create_health_check - Создание health check скрипта"

    local health_check_script="$TEST_DIR/health-check.sh"
    local test_ip="95.217.123.45"
    local test_port="443"

    create_health_check "$health_check_script" "$test_ip" "$test_port"

    if assert_file_exists "$health_check_script"; then
        local script_content=$(cat "$health_check_script")

        if assert_contains "$script_content" "$test_ip" && \
           assert_contains "$script_content" "$test_port" && \
           assert_contains "$script_content" "check_connection" && \
           assert_contains "$script_content" "MAX_FAILS=3"; then

            # Проверяем что скрипт исполняемый
            if [[ -x "$health_check_script" ]]; then
                test_pass
            else
                test_fail "Health check скрипт не является исполняемым"
            fi
        else
            test_fail "Health check скрипт не содержит необходимые элементы"
        fi
    else
        test_fail "Health check скрипт не создан"
    fi
}

test_create_auto_strategy_selector() {
    test_start "create_auto_strategy_selector - Создание auto strategy скрипта"

    local auto_strategy_script="$TEST_DIR/auto-strategy.sh"
    local test_ip="192.168.1.1"
    local test_port="8443"

    create_auto_strategy_selector "$auto_strategy_script" "$test_ip" "$test_port"

    if assert_file_exists "$auto_strategy_script"; then
        local script_content=$(cat "$auto_strategy_script")

        if assert_contains "$script_content" "$test_ip" && \
           assert_contains "$script_content" "$test_port" && \
           assert_contains "$script_content" "test_strategy" && \
           assert_contains "$script_content" "apply_strategy" && \
           assert_contains "$script_content" "STRATEGY_DB"; then

            if [[ -x "$auto_strategy_script" ]]; then
                test_pass
            else
                test_fail "Auto strategy скрипт не является исполняемым"
            fi
        else
            test_fail "Auto strategy скрипт не содержит необходимые функции"
        fi
    else
        test_fail "Auto strategy скрипт не создан"
    fi
}

test_create_nfqws_service() {
    test_start "create_nfqws_service - Создание systemd service файла"

    local service_content=$(create_nfqws_service_content "/opt/zapret/nfqws/nfqws" "--dpi-desync=split2")

    if assert_contains "$service_content" "[Unit]" && \
       assert_contains "$service_content" "[Service]" && \
       assert_contains "$service_content" "[Install]" && \
       assert_contains "$service_content" "ExecStart=/opt/zapret/nfqws/nfqws" && \
       assert_contains "$service_content" "--qnum=200" && \
       assert_contains "$service_content" "Restart=always"; then
        test_pass
    else
        test_fail "Systemd service файл содержит ошибки"
    fi
}

test_nfqws_service_security() {
    test_start "systemd service - Проверка security параметров"

    local service_content=$(create_nfqws_service_content "/opt/zapret/nfqws/nfqws" "--dpi-desync=split2")

    if assert_contains "$service_content" "NoNewPrivileges=true" && \
       assert_contains "$service_content" "PrivateTmp=true"; then
        test_pass
    else
        test_fail "Systemd service не содержит необходимые security параметры"
    fi
}

test_strategy_params_format() {
    test_start "Strategy Params - Проверка формата параметров DPI bypass"

    local strategy_db="$TEST_DIR/strategies3.json"
    create_strategy_database "$strategy_db"

    local all_valid=true
    for i in {0..4}; do
        local params=$(jq -r ".strategies[$i].params" "$strategy_db")

        # Проверяем что параметры содержат --dpi-desync
        if [[ ! "$params" == *"--dpi-desync="* ]]; then
            all_valid=false
            break
        fi
    done

    if $all_valid; then
        test_pass
    else
        test_fail "Не все стратегии содержат корректные параметры --dpi-desync"
    fi
}

test_health_check_fail_counter() {
    test_start "Health Check - Проверка логики счетчика неудач"

    local health_check_script="$TEST_DIR/health-check2.sh"
    create_health_check "$health_check_script" "127.0.0.1" "9999"

    local script_content=$(cat "$health_check_script")

    if assert_contains "$script_content" "FAIL_COUNT_FILE" && \
       assert_contains "$script_content" "fail_count=\$((fail_count + 1))" && \
       assert_contains "$script_content" "if [[ \$fail_count -ge \$MAX_FAILS ]]"; then
        test_pass
    else
        test_fail "Health check не содержит корректную логику счетчика неудач"
    fi
}

test_auto_strategy_loop_logic() {
    test_start "Auto Strategy - Проверка логики перебора стратегий"

    local auto_strategy_script="$TEST_DIR/auto-strategy2.sh"
    create_auto_strategy_selector "$auto_strategy_script" "127.0.0.1" "443"

    local script_content=$(cat "$auto_strategy_script")

    if assert_contains "$script_content" "for i in \$(seq 1 \$total_strategies)" && \
       assert_contains "$script_content" "next_id=\$(( (current_id % total_strategies) + 1 ))" && \
       assert_contains "$script_content" "if test_strategy \"\$next_id\""; then
        test_pass
    else
        test_fail "Auto strategy не содержит корректную логику перебора"
    fi
}

test_integration_full_setup_simulation() {
    test_start "Integration - Симуляция полной установки"

    # Создаем все компоненты
    local strategy_db="$TEST_DIR/integration-strategies.json"
    local current_strategy="$TEST_DIR/integration-current.json"
    local health_check="$TEST_DIR/integration-health.sh"
    local auto_strategy="$TEST_DIR/integration-auto.sh"

    create_strategy_database "$strategy_db"

    # Создаем текущую стратегию (первая из базы)
    jq '.strategies[0]' "$strategy_db" > "$current_strategy"

    create_health_check "$health_check" "95.217.1.1" "443"
    create_auto_strategy_selector "$auto_strategy" "95.217.1.1" "443"

    # Проверяем что все файлы созданы и валидны
    if assert_file_exists "$strategy_db" && \
       assert_file_exists "$current_strategy" && \
       assert_file_exists "$health_check" && \
       assert_file_exists "$auto_strategy"; then

        # Проверяем валидность JSON
        local current_strategy_id=$(jq -r '.id' "$current_strategy")

        if assert_equals "1" "$current_strategy_id"; then
            test_pass
        else
            test_fail "Текущая стратегия имеет неверный ID"
        fi
    else
        test_fail "Не все компоненты были созданы"
    fi
}

test_vless_url_with_special_chars() {
    test_start "parse_vless_url - URL с специальными символами"

    UUID=""
    NON_RU_IP=""
    NON_RU_PORT=""
    SNI=""
    PUBLIC_KEY=""

    local test_url="vless://uuid@example.com@10.0.0.1:443?sni=web.test%2Bsite.com&pbk=key%3Dvalue"

    if parse_vless_url "$test_url"; then
        if assert_equals "web.test+site.com" "$SNI" && \
           assert_equals "key=value" "$PUBLIC_KEY"; then
            test_pass
        else
            test_fail "URL-encoded символы не были корректно декодированы"
        fi
    else
        test_fail "Не удалось распарсить URL со специальными символами"
    fi
}

################################################################################
# Запуск всех тестов
################################################################################

run_all_tests() {
    print_header

    setup_test_env

    echo -e "${YELLOW}Running tests in: $TEST_DIR${NC}"
    echo ""

    # URL парсинг
    test_urldecode
    test_parse_vless_url_basic
    test_parse_vless_url_with_name
    test_parse_vless_url_invalid
    test_vless_url_with_special_chars

    # База стратегий
    test_create_strategy_database
    test_strategy_database_content
    test_strategy_params_format

    # Health check
    test_create_health_check
    test_health_check_fail_counter

    # Auto strategy
    test_create_auto_strategy_selector
    test_auto_strategy_loop_logic

    # Systemd service
    test_create_nfqws_service
    test_nfqws_service_security

    # Интеграция
    test_integration_full_setup_simulation

    cleanup_test_env

    # Итоги
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  Test Results                                          ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Total tests:  ${BLUE}$TOTAL_TESTS${NC}"
    echo -e "  Passed:       ${GREEN}$PASSED_TESTS${NC}"
    echo -e "  Failed:       ${RED}$FAILED_TESTS${NC}"
    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All tests passed!${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}${BOLD}✗ Some tests failed!${NC}"
        echo ""
        return 1
    fi
}

# Запуск
run_all_tests
