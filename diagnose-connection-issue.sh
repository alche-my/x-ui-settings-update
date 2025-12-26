#!/bin/bash

# ByeDPI + 3x-ui Connection Diagnostic Script
# Выполняет полную диагностику проблем с подключением клиентов

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== ByeDPI + 3x-ui Connection Diagnostic ===${NC}\n"

# 1. Проверка портов
echo -e "${YELLOW}1. Проверка прослушиваемых портов:${NC}"
echo "Xray процессы и их порты:"
sudo ss -tlnp | grep -E 'xray|x-ui' || echo "Не найдено процессов Xray/x-ui"
echo ""

# 2. Проверка процессов
echo -e "${YELLOW}2. Проверка запущенных процессов:${NC}"
ps aux | grep -E '[x]-ui|[x]ray' || echo "Процессы не найдены"
echo ""

# 3. Проверка конфигурации Xray
echo -e "${YELLOW}3. Поиск конфигурационного файла Xray:${NC}"
XRAY_CONFIG=""
for path in "/usr/local/x-ui/bin/config.json" "/etc/xray/config.json" "/usr/local/etc/xray/config.json"; do
    if [ -f "$path" ]; then
        XRAY_CONFIG="$path"
        echo -e "${GREEN}Найден: $path${NC}"
        break
    fi
done

if [ -z "$XRAY_CONFIG" ]; then
    echo -e "${RED}Конфигурация Xray не найдена!${NC}"
    echo "Возможные причины:"
    echo "  - x-ui не установлен"
    echo "  - конфигурация в нестандартном месте"
else
    echo -e "\n${YELLOW}Содержимое конфигурации (первые 50 строк):${NC}"
    sudo cat "$XRAY_CONFIG" | head -50
    echo ""

    echo -e "${YELLOW}Inbounds в конфигурации:${NC}"
    sudo cat "$XRAY_CONFIG" | jq '.inbounds[] | {port, protocol, tag}' 2>/dev/null || echo "jq не установлен, показываю сырые данные:"
    sudo cat "$XRAY_CONFIG" | grep -A 5 '"inbounds"' || echo "Не удалось извлечь inbounds"
fi
echo ""

# 4. Проверка логов Xray
echo -e "${YELLOW}4. Последние логи x-ui (если systemd):${NC}"
sudo journalctl -u x-ui -n 30 --no-pager 2>/dev/null || echo "systemd недоступен или нет логов"
echo ""

# 5. Проверка файрвола
echo -e "${YELLOW}5. Проверка firewall:${NC}"
sudo ufw status 2>/dev/null || echo "ufw не установлен"
sudo iptables -L -n | grep -E '8443|8080|7443' || echo "Нет правил iptables для этих портов"
echo ""

# 6. Проверка доступности портов извне
echo -e "${YELLOW}6. Тест доступности портов:${NC}"
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
echo "IP сервера: $SERVER_IP"

for port in 8443 8080 7443; do
    echo -n "Порт $port: "
    timeout 2 bash -c "cat < /dev/null > /dev/tcp/$SERVER_IP/$port" 2>/dev/null && echo -e "${GREEN}ОТКРЫТ${NC}" || echo -e "${RED}ЗАКРЫТ${NC}"
done
echo ""

# 7. Проверка ByeDPI
echo -e "${YELLOW}7. Статус ByeDPI:${NC}"
sudo systemctl status byedpi --no-pager 2>/dev/null || echo "ByeDPI не запущен через systemd"
echo ""

echo -e "${YELLOW}8. ByeDPI SOCKS5 работает:${NC}"
curl --socks5 127.0.0.1:1080 -m 5 -s https://ifconfig.me 2>/dev/null && echo -e "${GREEN}ByeDPI работает!${NC}" || echo -e "${RED}ByeDPI не работает${NC}"
echo ""

# 9. Проверка панели x-ui
echo -e "${YELLOW}9. Доступ к панели x-ui:${NC}"
curl -s http://localhost:2096 > /dev/null && echo -e "${GREEN}Панель x-ui доступна на :2096${NC}" || echo -e "${RED}Панель недоступна${NC}"
echo ""

# 10. Рекомендации
echo -e "${YELLOW}=== РЕКОМЕНДАЦИИ ===${NC}"
echo ""
echo "Если порты закрыты:"
echo "  1. Проверьте, запущен ли Xray: sudo systemctl restart x-ui"
echo "  2. Проверьте firewall: sudo ufw allow 8443/tcp"
echo ""
echo "Если порты открыты, но клиент не подключается:"
echo "  1. Проверьте UUID клиента совпадает с сервером"
echo "  2. Проверьте Reality keys (publicKey, shortId, serverName)"
echo "  3. Экспортируйте новую конфигурацию из панели x-ui"
echo ""
echo "Для получения конфигурации клиента из панели:"
echo "  - Откройте панель x-ui: http://$SERVER_IP:2096"
echo "  - Inbounds → нажмите на QR код нужного inbound"
echo "  - Скопируйте vless:// ссылку и проверьте в клиенте"
echo ""
