#!/bin/bash

################################################################################
# Auto ByeDPI Setup & Strategy Testing
# Автоматическая установка ByeDPI и подбор лучшей стратегии
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=== Auto ByeDPI Setup & Strategy Testing ==="
echo ""

# Проверка root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Запустите с sudo"
    exit 1
fi

# Шаг 1: Установка зависимостей
echo -e "${YELLOW}[1/5]${NC} Установка зависимостей..."
apt-get update -qq
apt-get install -y -qq gcc make git curl net-tools iproute2 lsof 2>/dev/null || {
    echo -e "${RED}[ERROR]${NC} Не удалось установить зависимости"
    exit 1
}
echo -e "${GREEN}[OK]${NC} Зависимости установлены"
echo ""

# Шаг 2: Установка ByeDPI
echo -e "${YELLOW}[2/5]${NC} Установка ByeDPI..."

if [[ -f /usr/local/bin/ciadpi ]]; then
    echo -e "${GREEN}[OK]${NC} ByeDPI уже установлен"
else
    BYEDPI_DIR="/opt/byedpi"

    # Удалить старую директорию
    rm -rf "$BYEDPI_DIR" 2>/dev/null || true

    # Клонировать и компилировать
    git clone https://github.com/hufrea/byedpi.git "$BYEDPI_DIR" --quiet
    cd "$BYEDPI_DIR"
    make
    cp ciadpi /usr/local/bin/
    chmod +x /usr/local/bin/ciadpi

    echo -e "${GREEN}[OK]${NC} ByeDPI установлен: /usr/local/bin/ciadpi"
fi
echo ""

# Шаг 3: Создание systemd сервиса
echo -e "${YELLOW}[3/5]${NC} Настройка systemd сервиса..."

cat > /etc/systemd/system/byedpi.service << 'EOF'
[Unit]
Description=ByeDPI SOCKS5 Proxy for DPI Bypass
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ciadpi --ip 127.0.0.1 --port 1080 --oob 1 --disorder 1 --auto=torst
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable byedpi --quiet
systemctl restart byedpi

sleep 2

if systemctl is-active --quiet byedpi; then
    echo -e "${GREEN}[OK]${NC} Сервис byedpi запущен"
else
    echo -e "${RED}[ERROR]${NC} Не удалось запустить byedpi"
    journalctl -u byedpi -n 10 --no-pager
    exit 1
fi
echo ""

# Шаг 4: Проверка базовой работы
echo -e "${YELLOW}[4/5]${NC} Проверка базовой работы ByeDPI..."

# Проверка процесса
if pgrep -x ciadpi > /dev/null; then
    echo -e "${GREEN}[OK]${NC} Процесс ciadpi запущен"
else
    echo -e "${RED}[ERROR]${NC} Процесс ciadpi не запущен"
    exit 1
fi

# Проверка порта
if netstat -tln 2>/dev/null | grep -q ":1080" || lsof -i :1080 2>/dev/null | grep -q ciadpi; then
    echo -e "${GREEN}[OK]${NC} Порт 1080 прослушивается"
else
    echo -e "${RED}[ERROR]${NC} Порт 1080 не прослушивается"
    exit 1
fi

# Проверка SOCKS5
if timeout 10 curl --socks5 127.0.0.1:1080 -s https://ifconfig.me > /dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} SOCKS5 прокси работает"
else
    echo -e "${YELLOW}[WARN]${NC} SOCKS5 не отвечает (может быть из-за DPI)"
fi
echo ""

# Шаг 5: Тестирование стратегий
echo -e "${YELLOW}[5/5]${NC} Тестирование стратегий обхода DPI..."
echo ""

# Получить адрес Non-RU сервера
read -p "Введите IP вашего Non-RU сервера (например, 45.12.135.9): " NON_RU_SERVER

if [[ -z "$NON_RU_SERVER" ]]; then
    echo -e "${RED}[ERROR]${NC} Адрес не может быть пустым"
    exit 1
fi

echo ""
echo "Тестируем стратегии на сервере: $NON_RU_SERVER"
echo "Это займет около 2-3 минут..."
echo ""

# Определить стратегии
declare -A STRATEGIES=(
    ["basic"]="--disorder 1 --auto=torst"
    ["oob"]="--oob 1 --disorder 1 --auto=torst"
    ["split"]="--split 1 --disorder 2"
    ["split2"]="--split 2 --disorder 1"
    ["split3"]="--split 3 --disorder 2"
    ["fake"]="--fake 1 --disorder 2"
    ["fake2"]="--fake 2 --split 1"
    ["ttl5"]="--ttl 5 --disorder 1"
    ["ttl128"]="--ttl 128 --split 1"
    ["combo1"]="--oob 1 --split 1 --disorder 1"
    ["combo2"]="--oob 1 --split 2 --disorder 2"
    ["combo3"]="--split 3 --disorder 3 --fake 2"
)

declare -A RESULTS

# Тестировать каждую стратегию
COUNT=1
TOTAL=${#STRATEGIES[@]}

for STRATEGY_NAME in "${!STRATEGIES[@]}"; do
    PARAMS="${STRATEGIES[$STRATEGY_NAME]}"

    echo -n "[$COUNT/$TOTAL] Тест $STRATEGY_NAME ... "

    # Остановить byedpi
    systemctl stop byedpi 2>/dev/null || true
    pkill -9 ciadpi 2>/dev/null || true
    sleep 1

    # Запустить с новыми параметрами
    /usr/local/bin/ciadpi --ip 127.0.0.1 --port 1080 $PARAMS &>/tmp/byedpi-test.log &
    CIADPI_PID=$!

    sleep 2

    # Проверить что запустился
    if ! kill -0 $CIADPI_PID 2>/dev/null; then
        echo -e "${RED}FAIL (не запустился)${NC}"
        RESULTS[$STRATEGY_NAME]=0
        ((COUNT++))
        continue
    fi

    # Тестировать соединение
    SUCCESS=0
    ATTEMPTS=3

    for i in $(seq 1 $ATTEMPTS); do
        HTTP_CODE=$(timeout 10 curl --socks5 127.0.0.1:1080 -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 5 --max-time 10 \
            "https://$NON_RU_SERVER" 2>/dev/null || echo "000")

        if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "301" ]] || [[ "$HTTP_CODE" == "302" ]]; then
            ((SUCCESS++))
        fi

        sleep 1
    done

    PERCENT=$((SUCCESS * 100 / ATTEMPTS))
    RESULTS[$STRATEGY_NAME]=$PERCENT

    # Остановить
    kill -9 $CIADPI_PID 2>/dev/null || true

    if [[ $PERCENT -ge 66 ]]; then
        echo -e "${GREEN}${PERCENT}%${NC}"
    elif [[ $PERCENT -ge 33 ]]; then
        echo -e "${YELLOW}${PERCENT}%${NC}"
    else
        echo -e "${RED}${PERCENT}%${NC}"
    fi

    ((COUNT++))
done

echo ""
echo "=== РЕЗУЛЬТАТЫ ==="
echo ""

# Найти лучшую стратегию
BEST_STRATEGY=""
BEST_RATE=0

for STRATEGY_NAME in $(for k in "${!RESULTS[@]}"; do echo "$k ${RESULTS[$k]}"; done | sort -k2 -rn | awk '{print $1}'); do
    RATE=${RESULTS[$STRATEGY_NAME]}
    PARAMS="${STRATEGIES[$STRATEGY_NAME]}"

    if [[ $RATE -gt $BEST_RATE ]]; then
        BEST_RATE=$RATE
        BEST_STRATEGY="$STRATEGY_NAME"
    fi

    if [[ $RATE -ge 66 ]]; then
        echo -e "${GREEN}✓${NC} $STRATEGY_NAME: $RATE%"
        echo "  $PARAMS"
    elif [[ $RATE -ge 33 ]]; then
        echo -e "${YELLOW}○${NC} $STRATEGY_NAME: $RATE%"
        echo "  $PARAMS"
    else
        echo -e "${RED}✗${NC} $STRATEGY_NAME: $RATE%"
    fi
done

echo ""

if [[ $BEST_RATE -eq 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Ни одна стратегия не сработала!"
    echo ""
    echo "Возможные причины:"
    echo "1. Non-RU сервер недоступен"
    echo "2. DPI блокирует все методы"
    echo "3. Неправильный IP адрес"
    echo ""
    echo "Проверьте:"
    echo "  curl -v https://$NON_RU_SERVER"
    echo ""
    exit 1
fi

echo -e "${GREEN}[ЛУЧШАЯ СТРАТЕГИЯ]${NC} $BEST_STRATEGY ($BEST_RATE%)"
echo "Параметры: ${STRATEGIES[$BEST_STRATEGY]}"
echo ""

read -p "Применить эту стратегию? [Y/n]: " APPLY

if [[ ! "$APPLY" =~ ^[Nn]$ ]]; then
    # Обновить systemd сервис
    cat > /etc/systemd/system/byedpi.service << EOF
[Unit]
Description=ByeDPI SOCKS5 Proxy (Strategy: $BEST_STRATEGY)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ciadpi --ip 127.0.0.1 --port 1080 ${STRATEGIES[$BEST_STRATEGY]}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl restart byedpi

    sleep 2

    if systemctl is-active --quiet byedpi; then
        echo -e "${GREEN}[OK]${NC} Стратегия применена и сервис перезапущен"
        echo ""
        echo "Следующие шаги:"
        echo "1. Перезапустите x-ui:"
        echo "   sudo systemctl restart x-ui"
        echo ""
        echo "2. Проверьте статус:"
        echo "   systemctl status byedpi"
        echo ""
        echo "3. Протестируйте соединение в клиенте"
    else
        echo -e "${RED}[ERROR]${NC} Не удалось запустить byedpi"
        systemctl status byedpi --no-pager
    fi
else
    echo "Стратегия не применена"
    systemctl restart byedpi
fi

echo ""
echo -e "${GREEN}=== Готово! ===${NC}"
echo ""
