#!/bin/bash

################################################################################
# Fix Xray config.json для интеграции с ByeDPI
# Исправляет ошибку "unable to send through: byedpi-socks"
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "=== Fix Xray Config for ByeDPI Integration ==="
echo ""

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Запустите с sudo"
    exit 1
fi

CONFIG_PATH="/usr/local/x-ui/bin/config.json"
BACKUP_PATH="/usr/local/x-ui/bin/config.json.backup-$(date +%Y%m%d-%H%M%S)"
XRAY_BIN="/usr/local/x-ui/bin/xray-linux-amd64"

# Проверка наличия файлов
if [[ ! -f "$CONFIG_PATH" ]]; then
    echo -e "${RED}[ERROR]${NC} Конфиг не найден: $CONFIG_PATH"
    exit 1
fi

if [[ ! -f "$XRAY_BIN" ]]; then
    echo -e "${RED}[ERROR]${NC} Xray не найден: $XRAY_BIN"
    exit 1
fi

echo -e "${YELLOW}[1/5]${NC} Создание бэкапа..."
cp "$CONFIG_PATH" "$BACKUP_PATH"
echo -e "${GREEN}[OK]${NC} Бэкап создан: $BACKUP_PATH"
echo ""

echo -e "${YELLOW}[2/5]${NC} Анализ текущего config.json..."

# Извлечь параметры VLESS из текущего конфига
VLESS_ADDRESS=$(jq -r '.outbounds[] | select(.protocol == "vless") |
    if .settings.vnext then .settings.vnext[0].address
    elif .settings.address then .settings.address
    else empty end' "$CONFIG_PATH" 2>/dev/null | head -1)

VLESS_PORT=$(jq -r '.outbounds[] | select(.protocol == "vless") |
    if .settings.vnext then .settings.vnext[0].port
    elif .settings.port then .settings.port
    else empty end' "$CONFIG_PATH" 2>/dev/null | head -1)

VLESS_UUID=$(jq -r '.outbounds[] | select(.protocol == "vless") |
    if .settings.vnext then .settings.vnext[0].users[0].id
    elif .settings.id then .settings.id
    else empty end' "$CONFIG_PATH" 2>/dev/null | head -1)

VLESS_FLOW=$(jq -r '.outbounds[] | select(.protocol == "vless") |
    if .settings.vnext then .settings.vnext[0].users[0].flow
    elif .settings.flow then .settings.flow
    else empty end' "$CONFIG_PATH" 2>/dev/null | head -1)

VLESS_TAG=$(jq -r '.outbounds[] | select(.protocol == "vless") | .tag' "$CONFIG_PATH" 2>/dev/null | head -1)

# Reality settings
REALITY_PUBLIC_KEY=$(jq -r '.outbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.publicKey // empty' "$CONFIG_PATH" 2>/dev/null | head -1)
REALITY_FINGERPRINT=$(jq -r '.outbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.fingerprint // empty' "$CONFIG_PATH" 2>/dev/null | head -1)
REALITY_SERVER_NAME=$(jq -r '.outbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.serverName // empty' "$CONFIG_PATH" 2>/dev/null | head -1)
REALITY_SHORT_ID=$(jq -r '.outbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.shortId // empty' "$CONFIG_PATH" 2>/dev/null | head -1)

echo "Найдено:"
echo "  VLESS Server: ${VLESS_ADDRESS}:${VLESS_PORT}"
echo "  UUID: ${VLESS_UUID}"
echo "  Flow: ${VLESS_FLOW}"
echo "  Tag: ${VLESS_TAG}"
echo "  Reality PublicKey: ${REALITY_PUBLIC_KEY}"
echo "  Reality ServerName: ${REALITY_SERVER_NAME}"
echo ""

if [[ -z "$VLESS_ADDRESS" ]] || [[ -z "$VLESS_UUID" ]]; then
    echo -e "${RED}[ERROR]${NC} Не удалось извлечь параметры VLESS из конфига"
    echo "Проверьте формат config.json вручную"
    exit 1
fi

echo -e "${YELLOW}[3/5]${NC} Создание исправленного конфига..."

# Создать новый корректный конфиг
cat > /tmp/fixed-config.json << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "outbounds": [
    {
      "tag": "byedpi-socks",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 1080
          }
        ]
      }
    },
    {
      "tag": "${VLESS_TAG}",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${VLESS_ADDRESS}",
            "port": ${VLESS_PORT},
            "users": [
              {
                "id": "${VLESS_UUID}",
                "flow": "${VLESS_FLOW}",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "publicKey": "${REALITY_PUBLIC_KEY}",
          "fingerprint": "${REALITY_FINGERPRINT}",
          "serverName": "${REALITY_SERVER_NAME}",
          "shortId": "${REALITY_SHORT_ID}",
          "spiderX": "/"
        },
        "sockopt": {
          "dialerProxy": "byedpi-socks"
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ]
}
EOF

echo -e "${GREEN}[OK]${NC} Конфиг создан: /tmp/fixed-config.json"
echo ""

echo -e "${YELLOW}[4/5]${NC} Проверка валидности конфига..."
if $XRAY_BIN test -c /tmp/fixed-config.json 2>&1 | tee /tmp/xray-test.log; then
    echo ""
    echo -e "${GREEN}[OK]${NC} Конфигурация валидна!"
else
    echo ""
    echo -e "${RED}[ERROR]${NC} Конфигурация невалидна!"
    echo "Лог:"
    cat /tmp/xray-test.log
    echo ""
    echo "Бэкап сохранен: $BACKUP_PATH"
    exit 1
fi

echo ""
echo -e "${YELLOW}[5/5]${NC} Применение конфигурации..."
echo ""
echo "ВНИМАНИЕ:"
echo "  Текущий конфиг: $CONFIG_PATH"
echo "  Бэкап:          $BACKUP_PATH"
echo "  Новый конфиг:   /tmp/fixed-config.json"
echo ""
echo -e "${YELLOW}Применить новую конфигурацию? [y/N]${NC}"
read -t 30 APPLY || APPLY="n"

if [[ "$APPLY" =~ ^[Yy]$ ]]; then
    cp /tmp/fixed-config.json "$CONFIG_PATH"
    echo -e "${GREEN}[OK]${NC} Конфигурация применена"

    echo ""
    echo "Перезапуск x-ui..."
    systemctl restart x-ui

    sleep 3

    if systemctl is-active --quiet x-ui; then
        echo -e "${GREEN}[OK]${NC} x-ui перезапущен успешно"

        echo ""
        echo "Проверка логов..."
        sleep 2

        if journalctl -u x-ui -n 20 --no-pager | grep -q "unable to send through"; then
            echo -e "${RED}[ERROR]${NC} Ошибка 'unable to send through' все еще присутствует!"
            echo ""
            journalctl -u x-ui -n 20 --no-pager
            echo ""
            echo "Восстановить бэкап? [y/N]"
            read -t 10 RESTORE || RESTORE="n"

            if [[ "$RESTORE" =~ ^[Yy]$ ]]; then
                cp "$BACKUP_PATH" "$CONFIG_PATH"
                systemctl restart x-ui
                echo -e "${YELLOW}[WARN]${NC} Бэкап восстановлен"
            fi
        else
            echo -e "${GREEN}[OK]${NC} Ошибки 'unable to send through' нет!"
            echo ""
            echo "=== УСПЕШНО ==="
            echo ""
            echo "Следующие шаги:"
            echo "1. Проверьте работу:"
            echo "   journalctl -u x-ui -f"
            echo ""
            echo "2. Протестируйте подключение клиента"
            echo ""
            echo "3. Если не работает, восстановите бэкап:"
            echo "   sudo cp $BACKUP_PATH $CONFIG_PATH"
            echo "   sudo systemctl restart x-ui"
        fi
    else
        echo -e "${RED}[ERROR]${NC} x-ui не запустился!"
        systemctl status x-ui --no-pager

        echo ""
        echo "Восстановить бэкап? [Y/n]"
        read -t 10 RESTORE || RESTORE="y"

        if [[ ! "$RESTORE" =~ ^[Nn]$ ]]; then
            cp "$BACKUP_PATH" "$CONFIG_PATH"
            systemctl restart x-ui
            echo -e "${YELLOW}[WARN]${NC} Бэкап восстановлен"
        fi
    fi
else
    echo "Конфигурация НЕ применена"
    echo ""
    echo "Для применения вручную:"
    echo "  sudo cp /tmp/fixed-config.json $CONFIG_PATH"
    echo "  sudo systemctl restart x-ui"
fi

echo ""
echo -e "${GREEN}=== Готово! ===${NC}"
echo ""
