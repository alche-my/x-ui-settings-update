#!/bin/bash

################################################################################
# Xray Balancer Config Generator for ByeDPI
#
# Description: Generates Xray configuration for load balancing across
#              multiple Non-RU servers through a single ByeDPI proxy
#
# Usage: ./generate-balancer-config.sh
#
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

CONFIG_OUTPUT_DIR="/root/byedpi-config"
BYEDPI_PORT="1080"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_step() {
    echo -e "${CYAN}${BOLD}==>${NC} $*"
}

# Create output directory
mkdir -p "$CONFIG_OUTPUT_DIR"

echo ""
echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║  Генератор конфигурации балансировщика для ByeDPI          ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Prompt for number of servers
echo -e "${YELLOW}Сколько Non-RU серверов вы хотите добавить в балансировщик?${NC}"
read -p "Количество серверов [3]: " server_count
server_count=${server_count:-3}

# Validate number
if ! [[ "$server_count" =~ ^[0-9]+$ ]] || [[ "$server_count" -lt 1 ]]; then
    echo -e "${RED}Ошибка: Некорректное количество серверов${NC}"
    exit 1
fi

echo ""
log_info "Будет создана конфигурация для $server_count серверов"
echo ""

# Arrays for server data
declare -a server_ips
declare -a server_ports
declare -a server_uuids
declare -a server_tags

# Collect server information
for i in $(seq 1 $server_count); do
    echo -e "${CYAN}${BOLD}=== Сервер #$i ===${NC}"

    # IP
    while true; do
        read -p "IP адрес сервера #$i: " ip
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            server_ips+=("$ip")
            break
        else
            echo -e "${RED}Некорректный IP адрес${NC}"
        fi
    done

    # Port
    read -p "Порт сервера #$i [443]: " port
    port=${port:-443}
    server_ports+=("$port")

    # UUID
    while true; do
        read -p "UUID сервера #$i: " uuid
        if [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
            server_uuids+=("$uuid")
            break
        else
            echo -e "${RED}Некорректный UUID${NC}"
        fi
    done

    # Tag
    server_tags+=("non-ru-${i}-via-byedpi")

    echo ""
done

# Balance strategy
echo -e "${YELLOW}Стратегия балансировки:${NC}"
echo "  1) random   - случайный выбор сервера"
echo "  2) leastPing - выбор сервера с наименьшим пингом"
echo "  3) leastLoad - выбор наименее загруженного сервера"
read -p "Выберите стратегию [1-3]: " strategy_choice

case "$strategy_choice" in
    2)
        strategy_type="leastPing"
        ;;
    3)
        strategy_type="leastLoad"
        ;;
    *)
        strategy_type="random"
        ;;
esac

log_step "Генерация конфигурации..."

# Generate outbounds
outbounds_json="["

# ByeDPI SOCKS outbound
outbounds_json+='
    {
      "tag": "byedpi-socks",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": '$BYEDPI_PORT'
          }
        ]
      }
    }'

# Server outbounds
for i in $(seq 0 $((server_count - 1))); do
    outbounds_json+=','
    outbounds_json+='
    {
      "tag": "'${server_tags[$i]}'",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "'${server_ips[$i]}'",
            "port": '${server_ports[$i]}',
            "users": [
              {
                "id": "'${server_uuids[$i]}'",
                "encryption": "none",
                "flow": ""
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "",
          "allowInsecure": false,
          "fingerprint": "chrome"
        }
      },
      "proxySettings": {
        "tag": "byedpi-socks",
        "transportLayer": false
      }
    }'
done

outbounds_json+='
  ]'

# Generate balancer selector
selector_json="["
for i in $(seq 0 $((server_count - 1))); do
    if [[ $i -gt 0 ]]; then
        selector_json+=', '
    fi
    selector_json+='"'${server_tags[$i]}'"'
done
selector_json+="]"

# Generate routing configuration
routing_json='{
    "domainStrategy": "AsIs",
    "balancers": [
      {
        "tag": "balancer",
        "selector": '$selector_json',
        "strategy": {
          "type": "'$strategy_type'"
        }
      }
    ],
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "balancerTag": "balancer"
      }
    ]
  }'

# Generate full config
full_config='{
  "outbounds": '$outbounds_json',
  "routing": '$routing_json'
}'

# Save configuration
echo "$full_config" | jq '.' > "$CONFIG_OUTPUT_DIR/xray-balancer-config.json" 2>/dev/null || {
    echo "$full_config" > "$CONFIG_OUTPUT_DIR/xray-balancer-config.json"
}

log_success "Конфигурация сохранена в $CONFIG_OUTPUT_DIR/xray-balancer-config.json"

# Generate summary
cat > "$CONFIG_OUTPUT_DIR/BALANCER-SETUP.md" << EOF
# Настройка балансировщика Xray с ByeDPI

## 📊 Сводка конфигурации

**Количество серверов:** $server_count
**Стратегия балансировки:** $strategy_type
**ByeDPI SOCKS5 порт:** $BYEDPI_PORT

### Серверы:

EOF

for i in $(seq 0 $((server_count - 1))); do
    cat >> "$CONFIG_OUTPUT_DIR/BALANCER-SETUP.md" << EOF
**Сервер #$((i+1)):**
- IP: ${server_ips[$i]}
- Порт: ${server_ports[$i]}
- UUID: ${server_uuids[$i]}
- Tag: ${server_tags[$i]}

EOF
done

cat >> "$CONFIG_OUTPUT_DIR/BALANCER-SETUP.md" << 'EOF'
## 🔧 Установка конфигурации

### Шаг 1: Убедитесь, что ByeDPI запущен

```bash
sudo systemctl status byedpi
```

Если не запущен:
```bash
sudo systemctl start byedpi
```

### Шаг 2: Настройте 3x-ui

#### Вариант A: Через JSON (рекомендуется)

1. Откройте веб-панель 3x-ui
2. Перейдите в **Panel Settings → Xray Configs** (или **Config**)
3. Скопируйте содержимое файла `xray-balancer-config.json`
4. Вставьте секции `outbounds` и `routing` в соответствующие места конфигурации
5. Нажмите **Save** и **Restart Xray**

#### Вариант B: Вручную через интерфейс

1. **Создайте SOCKS5 Outbound для ByeDPI:**
   - Tag: `byedpi-socks`
   - Protocol: `SOCKS`
   - Address: `127.0.0.1`
   - Port: `1080`

2. **Создайте Outbound для каждого Non-RU сервера:**
   - Для каждого сервера создайте VLESS outbound
   - В **Proxy Settings** укажите: `byedpi-socks`

3. **Настройте балансировщик в Routing:**
   - Создайте Balancer с тегом `balancer`
   - Добавьте все server tags в selector
   - Установите стратегию балансировки

### Шаг 3: Проверка

```bash
# Перезапустите 3x-ui
sudo systemctl restart x-ui

# Проверьте статус
sudo systemctl status x-ui

# Проверьте логи
sudo journalctl -u x-ui -f
```

## 🎯 Как работает балансировка

### Стратегии:

- **random**: Каждое новое соединение направляется на случайный сервер
- **leastPing**: Выбирается сервер с наименьшим пингом (требуется Xray 1.8.0+)
- **leastLoad**: Выбирается наименее загруженный сервер

### Схема работы:

```
Клиент → RU-сервер (3x-ui) → ByeDPI (DPI bypass) → Балансировщик → {
    Non-RU-1
    Non-RU-2
    Non-RU-3
} → Интернет
```

## ✅ Проверка балансировки

Подключите клиента и проверьте логи Xray:

```bash
sudo journalctl -u x-ui -f | grep balancer
```

Вы должны увидеть, как трафик распределяется между серверами.

## 🔧 Изменение стратегии балансировки

Отредактируйте конфигурацию и измените `strategy.type`:

```json
"strategy": {
  "type": "leastPing"  // или "random", "leastLoad"
}
```

## 📚 Дополнительная информация

- Все outbound-ы используют **один ByeDPI прокси** (порт 1080)
- ByeDPI применяет DPI bypass ко всем исходящим соединениям
- Балансировка происходит на уровне Xray после ByeDPI

## ⚙️ UUID на Non-RU серверах

**ВАЖНО:** Убедитесь, что на каждом Non-RU сервере добавлен соответствующий UUID в настройках VLESS inbound!

EOF

log_success "Инструкция сохранена в $CONFIG_OUTPUT_DIR/BALANCER-SETUP.md"

echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  ✓ Конфигурация балансировщика создана!                   ║${NC}"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
log_info "📁 Файлы конфигурации:"
echo "   - $CONFIG_OUTPUT_DIR/xray-balancer-config.json"
echo "   - $CONFIG_OUTPUT_DIR/BALANCER-SETUP.md"
echo ""
log_info "📖 Следующие шаги:"
echo "   1. Прочитайте: cat $CONFIG_OUTPUT_DIR/BALANCER-SETUP.md"
echo "   2. Примените конфигурацию в 3x-ui"
echo "   3. Перезапустите: sudo systemctl restart x-ui"
echo ""
