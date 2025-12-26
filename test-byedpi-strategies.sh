#!/bin/bash

################################################################################
# ByeDPI Strategy Auto-Selector v2.0
#
# Автоматически тестирует разные стратегии обхода DPI и выбирает лучшую
# Использует правильный синтаксис ciadpi (не мобильного приложения!)
#
# Usage: sudo ./test-byedpi-strategies.sh <non-ru-server-ip>
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

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

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

check_byedpi() {
    if ! command -v ciadpi &> /dev/null; then
        log_error "ByeDPI не установлен. Запустите install-byedpi-3xui.sh сначала"
        exit 1
    fi

    log_debug "ByeDPI найден: $(which ciadpi)"
}

# Правильные стратегии для ciadpi (НЕ из мобильного приложения!)
# Источник: https://github.com/hufrea/byedpi
declare -A STRATEGIES=(
    # Базовая (текущая)
    ["basic"]="--disorder 1 --auto=torst"

    # С OOB (Out-Of-Band)
    ["oob-basic"]="--oob 1 --disorder 1 --auto=torst"

    # Split + disorder
    ["split-disorder"]="--split 1 --disorder 3 --auto=torst"

    # Split в разных позициях
    ["split-pos2"]="--split 2 --disorder 1"

    ["split-pos3"]="--split 3 --disorder 2"

    # Fake packets (без TTL для совместимости)
    ["fake-basic"]="--fake 1 --disorder 2"

    ["fake-advanced"]="--fake 2 --split 1 --disorder 1"

    # TTL manipulation (осторожно!)
    ["ttl-low"]="--ttl 5 --disorder 1"

    ["ttl-high"]="--ttl 128 --split 1"

    # HTTP modification
    ["mod-http"]="--mod-http=h,d --split 1 --disorder 1"

    # Комбинированные
    ["combo-light"]="--oob 1 --split 1 --disorder 1"

    ["combo-medium"]="--oob 1 --split 2 --disorder 2 --fake 1"

    ["combo-heavy"]="--split 3 --disorder 3 --fake 2 --mod-http=h,d"

    # Агрессивная
    ["aggressive"]="--oob 1 --split 1 --disorder 3 --fake 2 --auto=torst"
)

# Остановить все процессы ciadpi
stop_byedpi() {
    pkill -9 ciadpi 2>/dev/null || true
    sleep 1
    log_debug "Все процессы ciadpi остановлены"
}

# Запустить ByeDPI с заданными параметрами
start_byedpi_with_params() {
    local strategy_name="$1"
    local params="$2"

    stop_byedpi

    local full_cmd="/usr/local/bin/ciadpi --ip 127.0.0.1 --port 1080 $params"

    log_debug "Запуск: $full_cmd"

    # Запустить в фоне и сохранить PID
    $full_cmd &>/tmp/byedpi-${strategy_name}.log &
    local pid=$!

    sleep 2

    # Проверить, что процесс запущен
    if ! kill -0 $pid 2>/dev/null; then
        log_debug "Процесс завершился. Лог:"
        cat /tmp/byedpi-${strategy_name}.log 2>/dev/null || echo "Нет лога"
        return 1
    fi

    # Проверить, что порт слушается
    if ! ss -tln 2>/dev/null | grep -q ":1080 "; then
        log_debug "Порт 1080 не прослушивается"
        kill -9 $pid 2>/dev/null || true
        return 1
    fi

    log_debug "ByeDPI запущен с PID $pid"
    return 0
}

# Тестирование соединения через SOCKS5
test_socks5_connection() {
    local test_url="$1"
    local attempts=3
    local success=0
    local timeout=10

    for i in $(seq 1 $attempts); do
        log_debug "Попытка $i/$attempts: curl --socks5 127.0.0.1:1080 $test_url"

        local http_code
        http_code=$(timeout $timeout curl --socks5 127.0.0.1:1080 \
            -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 5 \
            --max-time $timeout \
            "$test_url" 2>/dev/null || echo "000")

        log_debug "HTTP код: $http_code"

        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]; then
            ((success++))
            log_debug "Успех!"
        else
            log_debug "Неудача (код $http_code)"
        fi

        sleep 1
    done

    # Процент успешности
    local percent=$((success * 100 / attempts))
    log_debug "Успешность: $success/$attempts ($percent%)"
    echo $percent
}

# Основная функция тестирования
test_strategies() {
    local test_server="$1"

    # Определить URL для тестирования
    local test_urls=(
        "https://www.google.com"
        "https://ifconfig.me"
        "https://$test_server"
    )

    echo ""
    log_step "Начинаем тестирование стратегий..."
    log_info "Non-RU сервер: $test_server"
    log_info "Стратегий для тестирования: ${#STRATEGIES[@]}"
    echo ""

    declare -A results
    local test_count=0

    for strategy_name in "${!STRATEGIES[@]}"; do
        ((test_count++))
        echo -e "${CYAN}[$test_count/${#STRATEGIES[@]}]${NC} ${YELLOW}Тестирование: ${BOLD}$strategy_name${NC}"
        echo -e "  Параметры: ${STRATEGIES[$strategy_name]}"

        # Запустить ByeDPI с параметрами стратегии
        if ! start_byedpi_with_params "$strategy_name" "${STRATEGIES[$strategy_name]}"; then
            log_error "  ✗ Не удалось запустить ByeDPI"
            results[$strategy_name]=0
            echo ""
            continue
        fi

        # Протестировать соединения
        local total_success=0
        local url_count=0

        for url in "${test_urls[@]}"; do
            log_debug "Тестирую URL: $url"
            local success_rate=$(test_socks5_connection "$url")
            total_success=$((total_success + success_rate))
            ((url_count++))
        done

        # Средний процент успешности
        local avg_success=$((total_success / url_count))
        results[$strategy_name]=$avg_success

        if [[ $avg_success -ge 66 ]]; then
            echo -e "  ${GREEN}✓ Результат: ${avg_success}% успешных соединений${NC}"
        elif [[ $avg_success -ge 33 ]]; then
            echo -e "  ${YELLOW}○ Результат: ${avg_success}% успешных соединений${NC}"
        else
            echo -e "  ${RED}✗ Результат: ${avg_success}% успешных соединений${NC}"
        fi
        echo ""

        sleep 1
    done

    # Остановить ByeDPI
    stop_byedpi

    # Найти лучшую стратегию
    local best_strategy=""
    local best_rate=0

    for strategy_name in "${!results[@]}"; do
        if [[ ${results[$strategy_name]} -gt $best_rate ]]; then
            best_rate=${results[$strategy_name]}
            best_strategy="$strategy_name"
        fi
    done

    # Вывод результатов
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║  РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ                                   ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Отсортировать и вывести результаты
    for strategy_name in $(for k in "${!results[@]}"; do echo "$k ${results[$k]}"; done | sort -k2 -rn | awk '{print $1}'); do
        rate=${results[$strategy_name]}
        local params="${STRATEGIES[$strategy_name]}"

        if [[ $rate -ge 66 ]]; then
            echo -e "${GREEN}✓ $strategy_name: ${rate}%${NC}"
            echo -e "  $params"
        elif [[ $rate -ge 33 ]]; then
            echo -e "${YELLOW}○ $strategy_name: ${rate}%${NC}"
            echo -e "  $params"
        else
            echo -e "${RED}✗ $strategy_name: ${rate}%${NC}"
        fi
        echo ""
    done

    if [[ $best_rate -eq 0 ]]; then
        log_error "Ни одна стратегия не сработала!"
        echo ""
        echo "Попробуйте:"
        echo "1. Проверить доступность Non-RU сервера:"
        echo "   curl -v https://$test_server"
        echo ""
        echo "2. Проверить базовый SOCKS5 (запустите вручную):"
        echo "   ciadpi --ip 127.0.0.1 --port 1080 --disorder 1"
        echo "   curl --socks5 127.0.0.1:1080 https://google.com"
        echo ""
        echo "3. Запустить с DEBUG=1 для подробных логов:"
        echo "   DEBUG=1 sudo ./test-byedpi-strategies.sh $test_server"
        echo ""
        return 1
    fi

    log_success "Лучшая стратегия: ${BOLD}$best_strategy${NC} (${best_rate}% успешности)"
    echo -e "  Параметры: ${STRATEGIES[$best_strategy]}"
    echo ""

    # Спросить, применить ли эту стратегию
    read -p "Применить эту стратегию к ByeDPI сервису? [Y/n]: " apply </dev/tty

    if [[ ! "$apply" =~ ^[Nn]$ ]]; then
        apply_strategy "$best_strategy"
    else
        log_info "Стратегия не применена. Перезапускаем ByeDPI с дефолтными параметрами..."
        systemctl restart byedpi
    fi
}

# Применить стратегию к systemd сервису
apply_strategy() {
    local strategy_name="$1"
    local params="${STRATEGIES[$strategy_name]}"

    log_step "Применение стратегии: $strategy_name"

    # Создать новый systemd сервис
    cat > /etc/systemd/system/byedpi.service << EOF
[Unit]
Description=ByeDPI SOCKS5 Proxy for DPI Bypass (Strategy: $strategy_name)
Documentation=https://github.com/hufrea/byedpi
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ciadpi --ip 127.0.0.1 --port 1080 $params
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl restart byedpi

    sleep 2

    if systemctl is-active --quiet byedpi; then
        log_success "ByeDPI сервис обновлен и перезапущен"
        echo ""
        log_info "Стратегия: $strategy_name"
        log_info "Параметры: $params"
        echo ""
        log_warn "Теперь перезапустите x-ui для применения изменений:"
        echo -e "${YELLOW}sudo systemctl restart x-ui${NC}"
        echo ""
        log_info "Проверьте работу:"
        echo "  systemctl status byedpi"
        echo "  curl --socks5 127.0.0.1:1080 https://google.com"
    else
        log_error "Не удалось запустить ByeDPI с новыми параметрами"
        echo ""
        echo "Проверьте логи:"
        echo "  systemctl status byedpi"
        echo "  journalctl -u byedpi -n 50"
        return 1
    fi
}

main() {
    echo ""
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  ByeDPI Strategy Auto-Selector v2.0                       ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_root
    check_byedpi

    local test_server=""

    # Получить адрес сервера из аргумента или запросить
    if [[ -n "${1:-}" ]]; then
        test_server="$1"
        log_info "Используем адрес из аргумента: $test_server"
    else
        echo -e "${YELLOW}Для тестирования нужен адрес вашего Non-RU сервера${NC}"
        echo ""
        read -p "Введите IP или домен Non-RU сервера: " test_server </dev/tty
    fi

    if [[ -z "$test_server" ]]; then
        log_error "Адрес сервера не может быть пустым"
        exit 1
    fi

    echo ""
    log_info "Будет протестировано ${#STRATEGIES[@]} стратегий"
    log_warn "Это займет около 3-5 минут..."
    echo ""

    if [[ "${DEBUG:-0}" == "1" ]]; then
        log_warn "DEBUG режим включен"
    else
        log_info "Для подробных логов: DEBUG=1 sudo $0 $test_server"
    fi
    echo ""

    read -p "Начать тестирование? [Y/n]: " confirm </dev/tty
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "Тестирование отменено"
        exit 0
    fi

    test_strategies "$test_server"
}

main "$@"
