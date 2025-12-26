#!/bin/bash

################################################################################
# ByeDPI Strategy Tester v3.0
# Использует ПРАВИЛЬНЫЙ синтаксис ciadpi
# Тестирует через ByeDPI к google.com, а не напрямую к Non-RU серверу
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=== ByeDPI Strategy Tester v3.0 ==="
echo ""

# Проверка ByeDPI
if ! command -v ciadpi &>/dev/null; then
    echo -e "${RED}[ERROR]${NC} ciadpi не найден. Установите ByeDPI сначала."
    exit 1
fi

# Получить путь к ciadpi
CIADPI_PATH=$(which ciadpi)
echo "ByeDPI найден: $CIADPI_PATH"
echo ""

# Определить стратегии (короткий синтаксис на основе реальных примеров)
declare -A STRATEGIES=(
    ["basic"]="-d1"
    ["oob-basic"]="-o1 -d1"
    ["split-basic"]="-s1 -d1"
    ["split-oob"]="-s1 -o1 -d1"
    ["split2"]="-s2 -d1"
    ["split3"]="-s3 -d2"
    ["fake"]="-f-1 -d1"
    ["rostelecom"]="-s1 -q1 -Y -Ar -s5 -o1+s -At -f-1 -r1+s -As -s1 -o1+s -s-1 -An"
    ["combo1"]="-o1 -s2 -d2"
    ["combo2"]="-s1 -o1 -d1 -f-1"
)

echo "Стратегий для тестирования: ${#STRATEGIES[@]}"
echo ""

# Остановить все процессы ciadpi
pkill -9 ciadpi 2>/dev/null || true
sleep 1

declare -A RESULTS
COUNT=1
TOTAL=${#STRATEGIES[@]}

for STRATEGY_NAME in "${!STRATEGIES[@]}"; do
    PARAMS="${STRATEGIES[$STRATEGY_NAME]}"

    echo -n "[$COUNT/$TOTAL] Тест $STRATEGY_NAME ... "

    # Запустить ciadpi
    $CIADPI_PATH -i 127.0.0.1 -p 1080 $PARAMS &>/tmp/byedpi-${STRATEGY_NAME}.log &
    PID=$!

    sleep 2

    # Проверить что запустился
    if ! kill -0 $PID 2>/dev/null; then
        echo -e "${RED}FAIL (не запустился)${NC}"
        echo "  Лог: $(cat /tmp/byedpi-${STRATEGY_NAME}.log 2>/dev/null || echo 'пусто')"
        RESULTS[$STRATEGY_NAME]=0
        ((COUNT++))
        continue
    fi

    # Проверить порт
    sleep 1
    if ! (netstat -tln 2>/dev/null | grep -q ":1080" || lsof -i :1080 2>/dev/null | grep -q ciadpi); then
        echo -e "${RED}FAIL (порт не слушается)${NC}"
        kill -9 $PID 2>/dev/null || true
        RESULTS[$STRATEGY_NAME]=0
        ((COUNT++))
        continue
    fi

    # Тестировать соединение через ByeDPI к google.com
    SUCCESS=0
    ATTEMPTS=3

    for i in $(seq 1 $ATTEMPTS); do
        HTTP_CODE=$(timeout 10 curl --socks5 127.0.0.1:1080 \
            -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 5 --max-time 10 \
            https://www.google.com 2>/dev/null || echo "000")

        if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
            ((SUCCESS++))
        fi

        sleep 1
    done

    PERCENT=$((SUCCESS * 100 / ATTEMPTS))
    RESULTS[$STRATEGY_NAME]=$PERCENT

    # Остановить
    kill -9 $PID 2>/dev/null || true

    if [[ $PERCENT -ge 66 ]]; then
        echo -e "${GREEN}${PERCENT}%${NC}"
    elif [[ $PERCENT -ge 33 ]]; then
        echo -e "${YELLOW}${PERCENT}%${NC}"
    else
        echo -e "${RED}${PERCENT}%${NC}"
    fi

    ((COUNT++))
    sleep 1
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
    echo "Проверьте:"
    echo "1. ciadpi работает вручную:"
    echo "   ciadpi -i 127.0.0.1 -p 1080 -d1 &"
    echo "   curl --socks5 127.0.0.1:1080 https://google.com"
    echo ""
    echo "2. Просмотрите логи:"
    echo "   ls -la /tmp/byedpi-*.log"
    echo ""
    exit 1
fi

echo -e "${GREEN}[ЛУЧШАЯ СТРАТЕГИЯ]${NC} $BEST_STRATEGY ($BEST_RATE%)"
echo "Параметры: ${STRATEGIES[$BEST_STRATEGY]}"
echo ""

# Сохранить в файл
cat > /tmp/byedpi-best-strategy.txt << EOF
# Лучшая стратегия ByeDPI
# Тест проведен: $(date)
# Успешность: $BEST_RATE%

Стратегия: $BEST_STRATEGY
Параметры: ${STRATEGIES[$BEST_STRATEGY]}

Команда запуска:
ciadpi -i 127.0.0.1 -p 1080 ${STRATEGIES[$BEST_STRATEGY]}

Для systemd (/etc/systemd/system/byedpi.service):
ExecStart=$CIADPI_PATH -i 127.0.0.1 -p 1080 ${STRATEGIES[$BEST_STRATEGY]}
EOF

echo "Результаты сохранены в: /tmp/byedpi-best-strategy.txt"
echo ""

read -p "Обновить systemd сервис byedpi? [y/N]: " UPDATE

if [[ "$UPDATE" =~ ^[Yy]$ ]]; then
    cat > /etc/systemd/system/byedpi.service << EOF
[Unit]
Description=ByeDPI SOCKS5 Proxy (Strategy: $BEST_STRATEGY)
After=network.target

[Service]
Type=simple
ExecStart=$CIADPI_PATH -i 127.0.0.1 -p 1080 ${STRATEGIES[$BEST_STRATEGY]}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl restart byedpi

    sleep 2

    if systemctl is-active --quiet byedpi; then
        echo -e "${GREEN}[OK]${NC} Сервис byedpi обновлен и перезапущен"
        echo ""
        echo "Следующие шаги:"
        echo "1. Перезапустите x-ui:"
        echo "   systemctl restart x-ui"
        echo ""
        echo "2. Протестируйте в клиенте"
    else
        echo -e "${RED}[ERROR]${NC} Не удалось запустить byedpi"
        systemctl status byedpi --no-pager
    fi
else
    echo "Сервис не обновлен"
fi

echo ""
echo -e "${GREEN}=== Готово! ===${NC}"
echo ""
