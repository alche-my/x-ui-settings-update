#!/bin/bash

################################################################################
# Простой тестер ByeDPI - с подробной диагностикой
################################################################################

set +e  # НЕ прерывать при ошибках

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=== Simple ByeDPI Test ==="
echo ""

# Найти ciadpi
CIADPI=$(which ciadpi 2>/dev/null || echo "/usr/local/bin/ciadpi")
if [ ! -f "$CIADPI" ]; then
    echo -e "${RED}ERROR:${NC} ciadpi не найден"
    exit 1
fi

echo "1. ciadpi найден: $CIADPI"
echo ""

# Остановить все процессы
echo "2. Остановка всех процессов ciadpi..."
pkill -9 ciadpi 2>/dev/null || true
sleep 2
echo "   OK"
echo ""

# Тест 1: Базовый запуск
echo "3. Тест базового запуска (без параметров обхода DPI)..."
$CIADPI -i 127.0.0.1 -p 1080 &>/tmp/ciadpi-basic.log &
PID=$!
echo "   PID: $PID"
sleep 3

if kill -0 $PID 2>/dev/null; then
    echo -e "   ${GREEN}✓ Процесс запущен${NC}"

    # Проверить порт
    if netstat -tln 2>/dev/null | grep -q ":1080"; then
        echo -e "   ${GREEN}✓ Порт 1080 прослушивается${NC}"

        # Тест SOCKS5
        echo ""
        echo "4. Тест SOCKS5 к google.com..."
        HTTP_CODE=$(timeout 15 curl --socks5 127.0.0.1:1080 -s -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null || echo "000")

        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
            echo -e "   ${GREEN}✓ SOCKS5 работает! (HTTP $HTTP_CODE)${NC}"
        else
            echo -e "   ${RED}✗ SOCKS5 не работает (HTTP $HTTP_CODE)${NC}"
        fi
    else
        echo -e "   ${RED}✗ Порт 1080 НЕ прослушивается${NC}"
    fi

    kill -9 $PID 2>/dev/null || true
else
    echo -e "   ${RED}✗ Процесс упал${NC}"
    echo "   Лог:"
    cat /tmp/ciadpi-basic.log 2>/dev/null || echo "   (пусто)"
fi

echo ""
sleep 2

# Тест 2: С параметром -d1 (disorder)
echo "5. Тест с -d1 (disorder)..."
pkill -9 ciadpi 2>/dev/null || true
sleep 1

$CIADPI -i 127.0.0.1 -p 1080 -d1 &>/tmp/ciadpi-d1.log &
PID=$!
sleep 3

if kill -0 $PID 2>/dev/null; then
    echo -e "   ${GREEN}✓ Запустился с -d1${NC}"

    HTTP_CODE=$(timeout 15 curl --socks5 127.0.0.1:1080 -s -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo -e "   ${GREEN}✓ SOCKS5 работает с -d1! (HTTP $HTTP_CODE)${NC}"
    else
        echo -e "   ${RED}✗ SOCKS5 не работает (HTTP $HTTP_CODE)${NC}"
    fi

    kill -9 $PID 2>/dev/null || true
else
    echo -e "   ${RED}✗ Не запустился с -d1${NC}"
    cat /tmp/ciadpi-d1.log
fi

echo ""
sleep 2

# Тест 3: С параметром -s1 (split)
echo "6. Тест с -s1 (split)..."
pkill -9 ciadpi 2>/dev/null || true
sleep 1

$CIADPI -i 127.0.0.1 -p 1080 -s1 &>/tmp/ciadpi-s1.log &
PID=$!
sleep 3

if kill -0 $PID 2>/dev/null; then
    echo -e "   ${GREEN}✓ Запустился с -s1${NC}"

    HTTP_CODE=$(timeout 15 curl --socks5 127.0.0.1:1080 -s -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo -e "   ${GREEN}✓ SOCKS5 работает с -s1! (HTTP $HTTP_CODE)${NC}"
    else
        echo -e "   ${RED}✗ SOCKS5 не работает (HTTP $HTTP_CODE)${NC}"
    fi

    kill -9 $PID 2>/dev/null || true
else
    echo -e "   ${RED}✗ Не запустился с -s1${NC}"
    cat /tmp/ciadpi-s1.log
fi

echo ""
sleep 2

# Тест 4: Комбинация -s1 -d1
echo "7. Тест с -s1 -d1 (split + disorder)..."
pkill -9 ciadpi 2>/dev/null || true
sleep 1

$CIADPI -i 127.0.0.1 -p 1080 -s1 -d1 &>/tmp/ciadpi-s1d1.log &
PID=$!
sleep 3

if kill -0 $PID 2>/dev/null; then
    echo -e "   ${GREEN}✓ Запустился с -s1 -d1${NC}"

    HTTP_CODE=$(timeout 15 curl --socks5 127.0.0.1:1080 -s -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo -e "   ${GREEN}✓ SOCKS5 работает с -s1 -d1! (HTTP $HTTP_CODE)${NC}"
        BEST="-s1 -d1"
    else
        echo -e "   ${RED}✗ SOCKS5 не работает (HTTP $HTTP_CODE)${NC}"
    fi

    kill -9 $PID 2>/dev/null || true
else
    echo -e "   ${RED}✗ Не запустился с -s1 -d1${NC}"
    cat /tmp/ciadpi-s1d1.log
fi

echo ""
pkill -9 ciadpi 2>/dev/null || true

echo "=== ИТОГИ ==="
echo ""
echo "Логи сохранены в:"
echo "  /tmp/ciadpi-basic.log"
echo "  /tmp/ciadpi-d1.log"
echo "  /tmp/ciadpi-s1.log"
echo "  /tmp/ciadpi-s1d1.log"
echo ""

if [ -n "${BEST:-}" ]; then
    echo -e "${GREEN}Рабочая комбинация: $BEST${NC}"
    echo ""
    echo "Обновить systemd сервис? [y/N]"
    read -t 10 UPDATE || UPDATE="n"

    if [ "$UPDATE" = "y" ] || [ "$UPDATE" = "Y" ]; then
        cat > /etc/systemd/system/byedpi.service << EOF
[Unit]
Description=ByeDPI SOCKS5 Proxy
After=network.target

[Service]
Type=simple
ExecStart=$CIADPI -i 127.0.0.1 -p 1080 $BEST
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl restart byedpi
        echo ""
        echo -e "${GREEN}Сервис обновлен!${NC}"
        echo "systemctl status byedpi"
    fi
else
    echo -e "${RED}Ни одна конфигурация не сработала${NC}"
    echo ""
    echo "Просмотрите логи и попробуйте запустить вручную:"
    echo "  $CIADPI -i 127.0.0.1 -p 1080 -d1"
    echo "  curl --socks5 127.0.0.1:1080 https://google.com"
fi

echo ""
echo "=== Готово! ==="
