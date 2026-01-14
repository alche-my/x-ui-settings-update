#!/usr/bin/env bash

################################################################################
# Level 3 Zapret Setup - System-level DPI Bypass
################################################################################
# Автоматическая настройка Zapret (nfqws) для обхода DPI блокировок
# на исходящих соединениях от RU VPS → Non-RU VPS
#
# Архитектура:
#   Client → RU VPS (3x-ui) → [Zapret/nfqws DPI bypass] → Non-RU VPS → Internet
#
# Преимущества Zapret:
#   ✅ Работает на системном уровне (kernel space)
#   ✅ Не зависит от config.json 3x-ui
#   ✅ Persistence - не теряется при входе в web-панель
#   ✅ Высокая производительность
#   ✅ Автоподбор стратегий
#
# Использование:
#   bash <(curl -Ls https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/mobile-network-bypass-YNzFF/x-ui-tuning/level-3-zapret-setup.sh)
#
################################################################################

set -euo pipefail

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Константы
readonly ZAPRET_DIR="/opt/zapret"
readonly ZAPRET_BIN="/opt/zapret/nfqws/nfqws"
readonly STRATEGY_DB="/opt/zapret-strategies.json"
readonly CURRENT_STRATEGY="/opt/zapret-current-strategy.json"
readonly HEALTH_CHECK_SCRIPT="/opt/zapret-health-check.sh"
readonly AUTO_STRATEGY_SCRIPT="/opt/zapret-auto-strategy.sh"
readonly HEALTH_CHECK_LOG="/var/log/zapret-health-check.log"

# Глобальные переменные (будут заполнены из vless:// URL)
NON_RU_IP=""
NON_RU_PORT=""
UUID=""
SNI=""
PUBLIC_KEY=""
SHORT_ID=""
FINGERPRINT=""

################################################################################
# Утилиты
################################################################################

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  Level 3 Zapret Setup - System DPI Bypass             ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

################################################################################
# Парсинг vless:// URL
################################################################################

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
        log_error "Не удалось извлечь IP или PORT из vless:// URL"
        return 1
    fi

    # Проверка что URL содержал @ и : (не просто строка)
    if [[ "$UUID" == "$NON_RU_IP" ]] || [[ "$NON_RU_IP" == "$NON_RU_PORT" ]]; then
        log_error "Невалидный формат vless:// URL (отсутствует @ или :)"
        return 1
    fi

    log_success "VLESS URL успешно распарсен"
    echo ""
    log_info "Параметры Non-RU VPS:"
    echo "  IP:          $NON_RU_IP"
    echo "  Port:        $NON_RU_PORT"
    echo "  UUID:        ${UUID:0:8}...${UUID: -4}"
    [[ -n "$SNI" ]] && echo "  SNI:         $SNI"
    [[ -n "$PUBLIC_KEY" ]] && echo "  Public Key:  ${PUBLIC_KEY:0:16}..."
    [[ -n "$SHORT_ID" ]] && echo "  Short ID:    $SHORT_ID"
    [[ -n "$FINGERPRINT" ]] && echo "  Fingerprint: $FINGERPRINT"
    echo ""
}

################################################################################
# Установка зависимостей
################################################################################

install_dependencies() {
    log_info "Установка зависимостей..."

    # Обновляем список пакетов
    apt-get update -qq

    # Устанавливаем необходимые пакеты
    apt-get install -y -qq \
        git \
        build-essential \
        iptables \
        iptables-persistent \
        libnetfilter-queue-dev \
        libcap2-bin \
        curl \
        jq \
        netcat-openbsd

    log_success "Зависимости установлены"
}

################################################################################
# Клонирование и сборка Zapret
################################################################################

clone_and_build_zapret() {
    log_info "Клонирование Zapret из GitHub..."

    # Удаляем старую версию если есть
    if [[ -d "$ZAPRET_DIR" ]]; then
        log_warning "Удаление старой версии Zapret..."
        rm -rf "$ZAPRET_DIR"
    fi

    # Клонируем репозиторий
    git clone --depth=1 https://github.com/bol-van/zapret.git "$ZAPRET_DIR" 2>&1 | grep -v "Cloning into" || true

    log_success "Zapret клонирован"

    log_info "Компиляция nfqws..."

    # Собираем nfqws
    cd "$ZAPRET_DIR/nfqws"
    make 2>&1 | tail -n 5

    # Проверяем что бинарник создан
    if [[ ! -f "$ZAPRET_BIN" ]]; then
        log_error "Ошибка компиляции nfqws"
        return 1
    fi

    # Даем права на использование raw sockets
    setcap cap_net_admin,cap_net_raw=eip "$ZAPRET_BIN"

    log_success "nfqws успешно скомпилирован: $ZAPRET_BIN"
}

################################################################################
# Создание базы стратегий
################################################################################

create_strategy_database() {
    log_info "Создание базы данных стратегий DPI bypass..."

    cat > "$STRATEGY_DB" <<'EOF'
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

    # Устанавливаем первую стратегию как текущую
    jq '.strategies[0]' "$STRATEGY_DB" > "$CURRENT_STRATEGY"

    log_success "База стратегий создана: $STRATEGY_DB"
    log_info "Доступно стратегий: $(jq '.strategies | length' "$STRATEGY_DB")"
}

################################################################################
# Настройка правил iptables
################################################################################

apply_iptables_rules() {
    log_info "Настройка правил iptables для $NON_RU_IP:$NON_RU_PORT..."

    # Удаляем старые правила если есть
    iptables -t mangle -D OUTPUT -d "$NON_RU_IP" -p tcp --dport "$NON_RU_PORT" -j NFQUEUE --queue-num 200 2>/dev/null || true

    # Добавляем новое правило
    iptables -t mangle -A OUTPUT \
        -d "$NON_RU_IP" \
        -p tcp --dport "$NON_RU_PORT" \
        -j NFQUEUE --queue-num 200

    log_success "Правило iptables добавлено"

    # Сохраняем правила
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
        log_success "Правила iptables сохранены (будут восстановлены после перезагрузки)"
    fi
}

################################################################################
# Создание systemd service для nfqws
################################################################################

create_nfqws_service() {
    log_info "Создание systemd service для nfqws..."

    local strategy_params
    strategy_params=$(jq -r '.params' "$CURRENT_STRATEGY")

    cat > /etc/systemd/system/zapret-nfqws.service <<EOF
[Unit]
Description=Zapret nfqws - DPI Bypass Service
After=network.target iptables.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$ZAPRET_BIN --qnum=200 $strategy_params
Restart=always
RestartSec=5
User=root

# Security
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    # Перезагружаем systemd
    systemctl daemon-reload

    # Запускаем сервис
    systemctl enable zapret-nfqws.service
    systemctl restart zapret-nfqws.service

    sleep 2

    # Проверяем статус
    if systemctl is-active --quiet zapret-nfqws.service; then
        log_success "Сервис zapret-nfqws запущен и добавлен в автозагрузку"
    else
        log_error "Ошибка запуска сервиса zapret-nfqws"
        journalctl -u zapret-nfqws.service -n 20 --no-pager
        return 1
    fi
}

################################################################################
# Health Check скрипт
################################################################################

create_health_check() {
    log_info "Создание скрипта мониторинга здоровья соединения..."

    cat > "$HEALTH_CHECK_SCRIPT" <<'HEALTHCHECK_EOF'
#!/usr/bin/env bash

# Health Check для Zapret DPI Bypass
# Проверяет доступность Non-RU VPS каждые 5 минут

set -euo pipefail

CURRENT_STRATEGY="/opt/zapret-current-strategy.json"
LOG_FILE="/var/log/zapret-health-check.log"
NON_RU_IP="{{NON_RU_IP}}"
NON_RU_PORT="{{NON_RU_PORT}}"
MAX_FAILS=3

# Счетчик неудачных попыток
FAIL_COUNT_FILE="/tmp/zapret-fail-count"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_connection() {
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/$NON_RU_IP/$NON_RU_PORT" 2>/dev/null
    return $?
}

main() {
    # Инициализируем счетчик если нет
    if [[ ! -f "$FAIL_COUNT_FILE" ]]; then
        echo "0" > "$FAIL_COUNT_FILE"
    fi

    # Проверяем соединение
    if check_connection; then
        log_message "✓ Соединение OK: $NON_RU_IP:$NON_RU_PORT"
        # Сбрасываем счетчик неудач
        echo "0" > "$FAIL_COUNT_FILE"
    else
        # Увеличиваем счетчик
        local fail_count=$(cat "$FAIL_COUNT_FILE")
        fail_count=$((fail_count + 1))
        echo "$fail_count" > "$FAIL_COUNT_FILE"

        log_message "✗ FAIL ($fail_count/$MAX_FAILS): Нет соединения с $NON_RU_IP:$NON_RU_PORT"

        # Если достигли лимита - запускаем автоподбор стратегии
        if [[ $fail_count -ge $MAX_FAILS ]]; then
            log_message "⚠ Превышен лимит неудач ($MAX_FAILS), запуск автоподбора стратегии..."
            /opt/zapret-auto-strategy.sh
            # Сбрасываем счетчик
            echo "0" > "$FAIL_COUNT_FILE"
        fi
    fi
}

main
HEALTHCHECK_EOF

    # Подставляем переменные
    sed -i "s|{{NON_RU_IP}}|$NON_RU_IP|g" "$HEALTH_CHECK_SCRIPT"
    sed -i "s|{{NON_RU_PORT}}|$NON_RU_PORT|g" "$HEALTH_CHECK_SCRIPT"

    chmod +x "$HEALTH_CHECK_SCRIPT"

    # Создаем лог файл
    touch "$HEALTH_CHECK_LOG"

    log_success "Health check скрипт создан: $HEALTH_CHECK_SCRIPT"

    # Добавляем в crontab (каждые 5 минут)
    local cron_entry="*/5 * * * * $HEALTH_CHECK_SCRIPT"

    # Проверяем есть ли уже такая запись
    if ! crontab -l 2>/dev/null | grep -q "$HEALTH_CHECK_SCRIPT"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        log_success "Health check добавлен в crontab (каждые 5 минут)"
    else
        log_info "Health check уже есть в crontab"
    fi
}

################################################################################
# Auto Strategy Selector
################################################################################

create_auto_strategy_selector() {
    log_info "Создание скрипта автоподбора стратегий..."

    cat > "$AUTO_STRATEGY_SCRIPT" <<'STRATEGY_EOF'
#!/usr/bin/env bash

# Auto Strategy Selector для Zapret
# Автоматически переключает стратегии DPI bypass при проблемах с соединением

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

    # Останавливаем текущий сервис
    systemctl stop zapret-nfqws.service

    # Запускаем nfqws с новой стратегией
    $ZAPRET_BIN --qnum=200 $strategy_params &
    local nfqws_pid=$!

    sleep 2

    # Проверяем соединение
    local result=1
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$NON_RU_IP/$NON_RU_PORT" 2>/dev/null; then
        result=0
        log_message "✓ Стратегия #$strategy_id работает!"
    else
        log_message "✗ Стратегия #$strategy_id не работает"
    fi

    # Останавливаем тестовый процесс
    kill $nfqws_pid 2>/dev/null || true

    return $result
}

apply_strategy() {
    local strategy_id=$1

    # Сохраняем как текущую стратегию
    jq ".strategies[] | select(.id == $strategy_id)" "$STRATEGY_DB" > "$CURRENT_STRATEGY"

    # Обновляем systemd service
    local strategy_params
    strategy_params=$(jq -r '.params' "$CURRENT_STRATEGY")

    sed -i "s|ExecStart=.*|ExecStart=$ZAPRET_BIN --qnum=200 $strategy_params|" /etc/systemd/system/zapret-nfqws.service

    # Перезапускаем сервис
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

    # Получаем список всех стратегий
    local total_strategies
    total_strategies=$(jq '.strategies | length' "$STRATEGY_DB")

    # Перебираем стратегии начиная со следующей
    local tested=0
    for i in $(seq 1 $total_strategies); do
        local next_id=$(( (current_id % total_strategies) + 1 ))

        # Пропускаем текущую стратегию
        if [[ $next_id -eq $current_id ]]; then
            current_id=$next_id
            continue
        fi

        # Тестируем стратегию
        if test_strategy "$next_id"; then
            apply_strategy "$next_id"
            log_message "✓ Успешно переключились на стратегию #$next_id"
            return 0
        fi

        tested=$((tested + 1))
        current_id=$next_id

        # Если протестировали все - выходим
        if [[ $tested -ge $((total_strategies - 1)) ]]; then
            break
        fi
    done

    log_message "✗ Ни одна стратегия не работает! Возвращаем сервис в исходное состояние."
    systemctl start zapret-nfqws.service
}

main
STRATEGY_EOF

    # Подставляем переменные
    sed -i "s|{{NON_RU_IP}}|$NON_RU_IP|g" "$AUTO_STRATEGY_SCRIPT"
    sed -i "s|{{NON_RU_PORT}}|$NON_RU_PORT|g" "$AUTO_STRATEGY_SCRIPT"

    chmod +x "$AUTO_STRATEGY_SCRIPT"

    log_success "Auto strategy selector создан: $AUTO_STRATEGY_SCRIPT"
}

################################################################################
# Гайд по проверке
################################################################################

print_verification_guide() {
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════╗"
    echo -e "║  ✓ Zapret успешно установлен и настроен!              ║"
    echo -e "╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${CYAN}${BOLD}📋 Команды для проверки:${NC}"
    echo ""

    echo -e "${YELLOW}1. Проверить статус nfqws сервиса:${NC}"
    echo "   systemctl status zapret-nfqws"
    echo ""

    echo -e "${YELLOW}2. Проверить правила iptables:${NC}"
    echo "   iptables -t mangle -L OUTPUT -n -v | grep $NON_RU_IP"
    echo ""

    echo -e "${YELLOW}3. Проверить что nfqws работает:${NC}"
    echo "   ps aux | grep nfqws"
    echo ""

    echo -e "${YELLOW}4. Проверить логи nfqws:${NC}"
    echo "   journalctl -u zapret-nfqws -n 50 -f"
    echo ""

    echo -e "${YELLOW}5. Тест соединения с Non-RU VPS:${NC}"
    echo "   timeout 5 bash -c \"cat < /dev/null > /dev/tcp/$NON_RU_IP/$NON_RU_PORT\" && echo '✅ OK' || echo '❌ FAIL'"
    echo ""

    echo -e "${YELLOW}6. Проверить текущую стратегию:${NC}"
    echo "   cat $CURRENT_STRATEGY | jq '.name, .description'"
    echo ""

    echo -e "${YELLOW}7. Просмотр health check логов:${NC}"
    echo "   tail -f $HEALTH_CHECK_LOG"
    echo ""

    echo -e "${YELLOW}8. Ручной запуск автоподбора стратегий:${NC}"
    echo "   $AUTO_STRATEGY_SCRIPT"
    echo ""

    echo -e "${YELLOW}9. Проверить crontab:${NC}"
    echo "   crontab -l | grep zapret"
    echo ""

    echo -e "${CYAN}${BOLD}📁 Важные файлы:${NC}"
    echo "   • Бинарник:          $ZAPRET_BIN"
    echo "   • Systemd service:   /etc/systemd/system/zapret-nfqws.service"
    echo "   • База стратегий:    $STRATEGY_DB"
    echo "   • Текущая стратегия: $CURRENT_STRATEGY"
    echo "   • Health check:      $HEALTH_CHECK_SCRIPT"
    echo "   • Auto strategy:     $AUTO_STRATEGY_SCRIPT"
    echo "   • Логи:              $HEALTH_CHECK_LOG"
    echo ""

    echo -e "${CYAN}${BOLD}🔧 Управление сервисом:${NC}"
    echo "   systemctl start zapret-nfqws    # Запустить"
    echo "   systemctl stop zapret-nfqws     # Остановить"
    echo "   systemctl restart zapret-nfqws  # Перезапустить"
    echo "   systemctl status zapret-nfqws   # Статус"
    echo ""

    echo -e "${GREEN}${BOLD}✨ Все готово! Теперь DPI bypass работает на системном уровне.${NC}"
    echo -e "${GREEN}   Конфигурация не зависит от 3x-ui и не потеряется при входе в web-панель.${NC}"
    echo ""
}

################################################################################
# Основная функция
################################################################################

main() {
    # Проверка root
    if [[ $EUID -ne 0 ]]; then
        log_error "Скрипт должен быть запущен с правами root"
        echo "Используйте: sudo bash $0"
        exit 1
    fi

    print_header

    # Запрашиваем vless:// URL
    echo -e "${CYAN}Вставьте vless:// ссылку на ваш Non-RU VPS:${NC}"
    echo -e "${CYAN}(Пример: vless://UUID@IP:PORT?type=tcp&security=reality&pbk=KEY&sni=SNI...)${NC}"
    echo ""
    read -p "> " vless_url

    if [[ -z "$vless_url" ]]; then
        log_error "vless:// URL не может быть пустым"
        exit 1
    fi

    echo ""
    log_info "Парсинг VLESS URL..."

    if ! parse_vless_url "$vless_url"; then
        exit 1
    fi

    # Подтверждение
    echo -e "${YELLOW}Подтвердите настройки:${NC}"
    echo "  1. Target: $NON_RU_IP:$NON_RU_PORT"
    echo "  2. Метод: Zapret (nfqws) на системном уровне"
    echo "  3. Автоподбор стратегий: каждые 5 минут"
    echo "  4. Доступно стратегий: 5"
    echo ""
    read -p "Продолжить? (y/n): " confirm

    if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
        log_info "Установка отменена"
        exit 0
    fi

    echo ""

    # Выполняем установку
    install_dependencies
    clone_and_build_zapret
    create_strategy_database
    apply_iptables_rules
    create_nfqws_service
    create_health_check
    create_auto_strategy_selector

    # Выводим гайд
    print_verification_guide

    # Запускаем первую проверку
    log_info "Запуск первой проверки соединения..."
    sleep 2

    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$NON_RU_IP/$NON_RU_PORT" 2>/dev/null; then
        log_success "✅ Соединение с $NON_RU_IP:$NON_RU_PORT работает!"
    else
        log_warning "⚠ Соединение не установлено. Попробуйте запустить автоподбор стратегий:"
        echo "   $AUTO_STRATEGY_SCRIPT"
    fi
}

# Запуск
main "$@"
