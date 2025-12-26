#!/bin/bash

# Скрипт для исправления проблем с подключением клиентов к 3x-ui
# Автоматически проверяет и исправляет распространенные проблемы

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Fix Client Connection Issues - 3x-ui + ByeDPI          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Функция для проверки и перезапуска сервиса
restart_service() {
    local service=$1
    echo -e "${YELLOW}Перезапуск $service...${NC}"
    sudo systemctl restart $service
    sleep 2
    if sudo systemctl is-active --quiet $service; then
        echo -e "${GREEN}✓ $service успешно перезапущен${NC}"
        return 0
    else
        echo -e "${RED}✗ Ошибка перезапуска $service${NC}"
        return 1
    fi
}

# Функция для проверки порта
check_port() {
    local port=$1
    local result=$(sudo ss -tlnp 2>/dev/null | grep ":$port " || echo "")
    if [ -n "$result" ]; then
        echo -e "${GREEN}✓ Порт $port прослушивается${NC}"
        return 0
    else
        echo -e "${RED}✗ Порт $port НЕ прослушивается${NC}"
        return 1
    fi
}

# 1. Проверка текущего статуса
echo -e "${YELLOW}[1/6] Проверка текущего статуса сервисов...${NC}"
echo ""

X_UI_RUNNING=false
BYEDPI_RUNNING=false

if sudo systemctl is-active --quiet x-ui 2>/dev/null; then
    echo -e "${GREEN}✓ x-ui запущен${NC}"
    X_UI_RUNNING=true
else
    echo -e "${RED}✗ x-ui НЕ запущен${NC}"
fi

if sudo systemctl is-active --quiet byedpi 2>/dev/null; then
    echo -e "${GREEN}✓ byedpi запущен${NC}"
    BYEDPI_RUNNING=true
else
    echo -e "${YELLOW}⚠ byedpi НЕ запущен (это нормально, если не используется)${NC}"
fi
echo ""

# 2. Перезапуск x-ui
echo -e "${YELLOW}[2/6] Перезапуск x-ui для применения конфигурации...${NC}"
if ! restart_service "x-ui"; then
    echo -e "${RED}ОШИБКА: Не удалось перезапустить x-ui${NC}"
    echo "Проверьте логи: sudo journalctl -u x-ui -n 50"
    exit 1
fi
echo ""

# 3. Проверка портов
echo -e "${YELLOW}[3/6] Проверка прослушиваемых портов...${NC}"
PORTS_OK=true
for port in 8443 8080 7443; do
    if ! check_port $port; then
        PORTS_OK=false
    fi
done

if [ "$PORTS_OK" = false ]; then
    echo -e "${YELLOW}⚠ Не все порты прослушиваются!${NC}"
    echo "Возможные причины:"
    echo "  - Inbound не включен в панели x-ui"
    echo "  - Конфликт портов с другими сервисами"
    echo "  - Ошибка в конфигурации Xray"
    echo ""
    echo "Проверьте панель x-ui: http://$(curl -s ifconfig.me):2096"
else
    echo -e "${GREEN}✓ Все порты прослушиваются корректно${NC}"
fi
echo ""

# 4. Проверка firewall
echo -e "${YELLOW}[4/6] Проверка и настройка firewall...${NC}"
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(sudo ufw status | grep -i "Status:" | awk '{print $2}')
    if [ "$UFW_STATUS" = "active" ]; then
        echo "UFW активен, добавляем правила..."
        sudo ufw allow 8443/tcp > /dev/null 2>&1 || true
        sudo ufw allow 8080/tcp > /dev/null 2>&1 || true
        sudo ufw allow 7443/tcp > /dev/null 2>&1 || true
        echo -e "${GREEN}✓ Правила firewall добавлены${NC}"
    else
        echo -e "${GREEN}✓ UFW неактивен, пропускаем${NC}"
    fi
else
    echo -e "${YELLOW}⚠ UFW не установлен, пропускаем${NC}"
fi
echo ""

# 5. Тест доступности портов
echo -e "${YELLOW}[5/6] Тестирование доступности портов...${NC}"
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
echo "IP сервера: $SERVER_IP"
echo ""

ALL_ACCESSIBLE=true
for port in 8443 8080 7443; do
    echo -n "Проверка порта $port: "
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$SERVER_IP/$port" 2>/dev/null; then
        echo -e "${GREEN}ДОСТУПЕН${NC}"
    else
        echo -e "${RED}НЕДОСТУПЕН${NC}"
        ALL_ACCESSIBLE=false
    fi
done
echo ""

if [ "$ALL_ACCESSIBLE" = false ]; then
    echo -e "${YELLOW}⚠ Некоторые порты недоступны извне!${NC}"
    echo "Возможные причины:"
    echo "  - Внешний firewall на VPS провайдере"
    echo "  - CloudFlare или другой CDN блокирует порты"
    echo "  - Неправильная настройка Security Groups (AWS/GCP/etc)"
fi
echo ""

# 6. Итоговая информация
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ИТОГИ И РЕКОМЕНДАЦИИ                                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$PORTS_OK" = true ] && [ "$ALL_ACCESSIBLE" = true ]; then
    echo -e "${GREEN}✓ Серверная часть настроена корректно!${NC}"
    echo ""
    echo "Если клиент все еще не подключается, проблема в конфигурации клиента:"
    echo ""
    echo "1. Получите правильную конфигурацию из панели x-ui:"
    echo "   - Откройте: http://$SERVER_IP:2096"
    echo "   - Inbounds → нажмите на иконку QR-кода"
    echo "   - Скопируйте vless:// ссылку"
    echo ""
    echo "2. Проверьте в клиенте:"
    echo "   - UUID должен совпадать с сервером"
    echo "   - Reality publicKey, shortId, serverName должны совпадать"
    echo "   - Тип сети (network): grpc, xhttp или tcp"
    echo "   - Порт должен быть правильным (8443, 8080 или 7443)"
    echo ""
    echo "3. Если используете subscription link:"
    echo "   - Обновите подписку в клиенте"
    echo "   - Или используйте прямую vless:// ссылку из панели"
else
    echo -e "${RED}✗ Обнаружены проблемы с серверной частью${NC}"
    echo ""
    echo "Следующие шаги:"
    echo "1. Проверьте логи x-ui:"
    echo "   sudo journalctl -u x-ui -n 50 --no-pager"
    echo ""
    echo "2. Проверьте конфигурацию в панели x-ui:"
    echo "   http://$SERVER_IP:2096"
    echo "   → Inbounds: убедитесь, что все включены"
    echo ""
    echo "3. Если порты не прослушиваются:"
    echo "   - Проверьте, нет ли конфликтов портов"
    echo "   - Перезапустите сервер: sudo reboot"
    echo ""
    echo "4. Если порты недоступны извне:"
    echo "   - Проверьте firewall на VPS панели провайдера"
    echo "   - Проверьте Security Groups (если используете облачный VPS)"
fi
echo ""

echo -e "${BLUE}Скрипт завершен!${NC}"
