#!/bin/bash

################################################################################
# ByeDPI Strategy Auto-Selector
#
# Автоматически тестирует разные стратегии обхода DPI и выбирает лучшую
#
# Usage: sudo ./test-byedpi-strategies.sh
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Проверка наличия ByeDPI
check_byedpi() {
    if ! command -v ciadpi &> /dev/null; then
        log_error "ByeDPI не установлен. Запустите install-byedpi-3xui.sh сначала"
        exit 1
    fi
}

# Список стратегий для тестирования (без --tlsrec для совместимости с Reality)
declare -A STRATEGIES=(
    # Стратегия из мобильного приложения (90% success)
    ["google-ttl-mss"]="--ip 127.0.0.1 --port 1080 -n google.com -Qr -f-204 -s1.5+sm -a1 -As -d1 -s3+s -s5+s -q7 -a1 -As -o2 -f-43 -a1 -As -r5 -Mh -s1:5+s -s3:7+sm -a1"

    # OOB + множественные разделения (47% success)
    ["oob-multi-split"]="--ip 127.0.0.1 --port 1080 -o1 -d1 -a1 -At,r,s -s1 -d1 -s5+s -s10+s -s15+s -s20+s -r1+s -S -a1"

    # Множественные позиции (42% success)
    ["multi-position"]="--ip 127.0.0.1 --port 1080 -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1"

    # Большие позиции + TTL (38% success)
    ["large-positions"]="--ip 127.0.0.1 --port 1080 -d1+s -s50+s -a1 -As -f20 -r2+s -a1 -At -d2 -s1+s -s5+s -s10+s -s15+s -s25+s -s35+s -s50+s -s60+s -a1"

    # OOB + google.com (33% success)
    ["oob-google"]="--ip 127.0.0.1 --port 1080 -o1 -a1 -At,r,s -f-1 -a1 -At,r,s -d1:11+sm -S -a1 -At,r,s -n google.com -Qr -f1 -d1:11+sm -s1:11+sm -S -a1"

    # Упрощенная (совместимая с Reality)
    ["simple-reality"]="--ip 127.0.0.1 --port 1080 -o2 -a1 -s1 -s3+s -s5+s -d1 -r2+s"

    # Текущая (базовая)
    ["current-basic"]="--ip 127.0.0.1 --port 1080 --oob 1 --disorder 1 --auto=torst"

    # Агрессивная (без TTL)
    ["aggressive"]="--ip 127.0.0.1 --port 1080 -o2 -d1 -s1 -s2+s -s3+s -s5+s -s10+s -r3+s -a1 -As"

    # Минималистичная
    ["minimal"]="--ip 127.0.0.1 --port 1080 -o1 -d1 -s5+s"
)

# Функция для запуска ByeDPI с заданными параметрами
start_byedpi_with_params() {
    local params="$1"

    # Остановить текущий процесс
    pkill -9 ciadpi 2>/dev/null || true
    sleep 1

    # Запустить с новыми параметрами в фоне
    eval "/usr/local/bin/ciadpi $params" &>/dev/null &
    local pid=$!

    sleep 2

    # Проверить, что процесс запущен
    if ! kill -0 $pid 2>/dev/null; then
        return 1
    fi

    return 0
}

# Функция для тестирования соединения через ByeDPI
test_connection() {
    local test_url="$1"
    local attempts=3
    local success=0

    for i in $(seq 1 $attempts); do
        if timeout 10 curl --socks5 127.0.0.1:1080 -s -o /dev/null -w "%{http_code}" "$test_url" 2>/dev/null | grep -q "200"; then
            ((success++))
        fi
        sleep 1
    done

    # Процент успешности
    echo $((success * 100 / attempts))
}

# Основная функция тестирования
test_strategies() {
    local test_server="$1"
    local test_url="https://${test_server}"

    echo ""
    log_step "Начинаем тестирование стратегий..."
    echo ""

    declare -A results

    for strategy_name in "${!STRATEGIES[@]}"; do
        echo -e "${YELLOW}Тестирование: $strategy_name${NC}"

        # Запустить ByeDPI с параметрами стратегии
        if ! start_byedpi_with_params "${STRATEGIES[$strategy_name]}"; then
            log_error "Не удалось запустить ByeDPI с параметрами $strategy_name"
            results[$strategy_name]=0
            continue
        fi

        # Протестировать соединение
        success_rate=$(test_connection "$test_url")
        results[$strategy_name]=$success_rate

        echo -e "${CYAN}  Результат: ${success_rate}% успешных соединений${NC}"
        echo ""
    done

    # Остановить ByeDPI
    pkill -9 ciadpi 2>/dev/null || true

    # Найти лучшую стратегию
    local best_strategy=""
    local best_rate=0

    for strategy_name in "${!results[@]}"; do
        if [[ ${results[$strategy_name]} -gt $best_rate ]]; then
            best_rate=${results[$strategy_name]}
            best_strategy="$strategy_name"
        fi
    done

    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║  РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ                                   ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Вывести результаты, отсортированные по успешности
    for strategy_name in $(for k in "${!results[@]}"; do echo "$k ${results[$k]}"; done | sort -k2 -rn | awk '{print $1}'); do
        rate=${results[$strategy_name]}
        if [[ $rate -ge 66 ]]; then
            echo -e "${GREEN}✓ $strategy_name: ${rate}%${NC}"
        elif [[ $rate -ge 33 ]]; then
            echo -e "${YELLOW}○ $strategy_name: ${rate}%${NC}"
        else
            echo -e "${RED}✗ $strategy_name: ${rate}%${NC}"
        fi
    done

    echo ""

    if [[ $best_rate -eq 0 ]]; then
        log_error "Ни одна стратегия не сработала!"
        echo ""
        echo "Возможные причины:"
        echo "  1. Non-RU сервер недоступен"
        echo "  2. DPI блокирует все методы обхода"
        echo "  3. Неправильный адрес сервера"
        echo ""
        return 1
    fi

    log_success "Лучшая стратегия: ${BOLD}$best_strategy${NC} (${best_rate}% успешности)"
    echo ""

    # Спросить, применить ли эту стратегию
    read -p "Применить эту стратегию к ByeDPI сервису? [Y/n]: " apply </dev/tty

    if [[ ! "$apply" =~ ^[Nn]$ ]]; then
        apply_strategy "$best_strategy"
    else
        log_info "Стратегия не применена. Перезапускаем ByeDPI с базовыми параметрами..."
        systemctl restart byedpi
    fi
}

# Применить стратегию к systemd сервису
apply_strategy() {
    local strategy_name="$1"
    local params="${STRATEGIES[$strategy_name]}"

    log_step "Применение стратегии $strategy_name..."

    # Создать новый systemd сервис
    cat > /etc/systemd/system/byedpi.service << EOF
[Unit]
Description=ByeDPI SOCKS5 Proxy for DPI Bypass
Documentation=https://github.com/hufrea/byedpi
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ciadpi $params
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
        log_info "Параметры:"
        echo "  $params"
        echo ""
        log_info "Теперь перезапустите x-ui для применения изменений:"
        echo -e "${YELLOW}sudo systemctl restart x-ui${NC}"
    else
        log_error "Не удалось запустить ByeDPI с новыми параметрами"
        systemctl status byedpi
        return 1
    fi
}

main() {
    echo ""
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  ByeDPI Strategy Auto-Selector                            ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_root
    check_byedpi

    echo -e "${YELLOW}Для тестирования стратегий нужен адрес вашего Non-RU сервера${NC}"
    echo ""
    read -p "Введите IP или домен Non-RU сервера (например, 45.12.135.9): " test_server </dev/tty

    if [[ -z "$test_server" ]]; then
        log_error "Адрес сервера не может быть пустым"
        exit 1
    fi

    echo ""
    log_info "Будет протестировано ${#STRATEGIES[@]} стратегий"
    log_warn "Это займет около 2-3 минут..."
    echo ""

    read -p "Начать тестирование? [Y/n]: " confirm </dev/tty
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "Тестирование отменено"
        exit 0
    fi

    test_strategies "$test_server"
}

main "$@"
