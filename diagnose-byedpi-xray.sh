#!/bin/bash

################################################################################
# Диагностика интеграции ByeDPI + Xray
# Собирает все логи и данные для поиска решения
################################################################################

set +e  # Не прерывать при ошибках

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_FILE="/tmp/byedpi-xray-diagnostic-$(date +%Y%m%d-%H%M%S).txt"

echo "=== ByeDPI + Xray Diagnostic Report ===" | tee "$REPORT_FILE"
echo "Дата: $(date)" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# Функция для добавления в отчет
report() {
    echo "$@" | tee -a "$REPORT_FILE"
}

# 1. Информация о системе
report "========================================="
report "1. СИСТЕМА"
report "========================================="
report ""
uname -a | tee -a "$REPORT_FILE"
report ""

# 2. Проверка ByeDPI
report "========================================="
report "2. BYEDPI"
report "========================================="
report ""

if systemctl is-active --quiet byedpi 2>/dev/null; then
    report "[✓] ByeDPI активен"
    systemctl status byedpi --no-pager | tee -a "$REPORT_FILE"
else
    report "[✗] ByeDPI НЕ активен"
fi

report ""
report "ByeDPI systemd config:"
cat /etc/systemd/system/byedpi.service 2>/dev/null | tee -a "$REPORT_FILE" || report "Файл не найден"

report ""
report "ByeDPI процесс:"
ps aux | grep ciadpi | grep -v grep | tee -a "$REPORT_FILE" || report "Процесс не запущен"

report ""
report "Порт 1080:"
netstat -tln 2>/dev/null | grep ":1080" | tee -a "$REPORT_FILE" || lsof -i :1080 2>/dev/null | tee -a "$REPORT_FILE" || report "Порт не прослушивается"

report ""
report "Тест SOCKS5:"
HTTP_CODE=$(timeout 10 curl --socks5 127.0.0.1:1080 -s -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null || echo "000")
report "HTTP код: $HTTP_CODE"
if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    report "[✓] ByeDPI SOCKS5 работает"
else
    report "[✗] ByeDPI SOCKS5 НЕ работает"
fi

# 3. Проверка x-ui и Xray
report ""
report "========================================="
report "3. X-UI / XRAY"
report "========================================="
report ""

if systemctl is-active --quiet x-ui 2>/dev/null; then
    report "[✓] x-ui активен"
else
    report "[✗] x-ui НЕ активен"
fi

report ""
report "x-ui процессы:"
ps aux | grep -E "(x-ui|xray)" | grep -v grep | tee -a "$REPORT_FILE"

report ""
report "Версия Xray:"
/usr/local/x-ui/bin/xray-linux-amd64 version 2>/dev/null | tee -a "$REPORT_FILE" || report "Не найден"

# 4. Текущая конфигурация Xray
report ""
report "========================================="
report "4. ТЕКУЩАЯ КОНФИГУРАЦИЯ XRAY"
report "========================================="
report ""

if [[ -f /usr/local/x-ui/bin/config.json ]]; then
    report "Файл: /usr/local/x-ui/bin/config.json"
    report ""
    cat /usr/local/x-ui/bin/config.json | tee -a "$REPORT_FILE"
else
    report "[✗] config.json не найден"
fi

# 5. Попытка применить тестовый конфиг с ByeDPI
report ""
report "========================================="
report "5. ТЕСТ КОНФИГУРАЦИИ С BYEDPI"
report "========================================="
report ""

report "Создаем тестовый конфиг..."

# Бэкап текущего конфига
if [[ -f /usr/local/x-ui/bin/config.json ]]; then
    cp /usr/local/x-ui/bin/config.json /tmp/config.json.backup
    report "Бэкап создан: /tmp/config.json.backup"
fi

# Создать тестовый конфиг
cat > /tmp/test-config.json << 'EOF'
{
  "log": {
    "loglevel": "debug"
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
      "tag": "test-vless",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "45.12.135.9",
            "port": 9443,
            "users": [
              {
                "id": "c46cf6c7-b795-4740-ad05-7e43ee8f1f77",
                "flow": "xtls-rprx-vision",
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
          "publicKey": "MfH0tto3CvGYIwZM4PxOHtuzTTIFNZthTbvB5Ns-20c",
          "fingerprint": "chrome",
          "serverName": "github.com",
          "shortId": "29214fb59be9124d",
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

report ""
report "Тестовый конфиг создан: /tmp/test-config.json"
report ""
cat /tmp/test-config.json | tee -a "$REPORT_FILE"

report ""
report "Проверка валидности конфига Xray..."
/usr/local/x-ui/bin/xray-linux-amd64 test -c /tmp/test-config.json 2>&1 | tee -a "$REPORT_FILE"
XRAY_TEST_EXIT=$?

if [[ $XRAY_TEST_EXIT -eq 0 ]]; then
    report ""
    report "[✓] Xray принимает конфигурацию с sockopt.dialerProxy"
else
    report ""
    report "[✗] Xray НЕ принимает конфигурацию"
    report "Exit code: $XRAY_TEST_EXIT"
fi

# 6. Логи x-ui
report ""
report "========================================="
report "6. ЛОГИ X-UI (последние 50 строк)"
report "========================================="
report ""

journalctl -u x-ui -n 50 --no-pager 2>/dev/null | tee -a "$REPORT_FILE" || report "Логи недоступны (systemd не используется)"

# 7. Проверка сети
report ""
report "========================================="
report "7. СЕТЬ"
report "========================================="
report ""

report "Прямое подключение к Non-RU серверу (без ByeDPI):"
timeout 5 curl -v https://45.12.135.9:9443 2>&1 | head -20 | tee -a "$REPORT_FILE"

report ""
report "Через ByeDPI:"
timeout 5 curl --socks5 127.0.0.1:1080 -v https://45.12.135.9:9443 2>&1 | head -20 | tee -a "$REPORT_FILE"

# 8. Итоги
report ""
report "========================================="
report "8. ИТОГИ"
report "========================================="
report ""

report "КРИТИЧЕСКИЕ ПРОБЛЕМЫ:"
report ""

if [[ ! -f /usr/local/x-ui/bin/xray-linux-amd64 ]]; then
    report "• Xray не найден"
fi

if [[ $HTTP_CODE != "200" ]] && [[ $HTTP_CODE != "301" ]] && [[ $HTTP_CODE != "302" ]]; then
    report "• ByeDPI SOCKS5 не работает (HTTP код: $HTTP_CODE)"
fi

if [[ $XRAY_TEST_EXIT -ne 0 ]]; then
    report "• Xray не принимает конфигурацию с sockopt.dialerProxy"
    report "  Возможные причины:"
    report "  1. Старая версия Xray (не поддерживает dialerProxy)"
    report "  2. Синтаксическая ошибка в конфиге"
    report "  3. dialerProxy не поддерживается для Reality"
fi

if ! systemctl is-active --quiet x-ui 2>/dev/null; then
    report "• x-ui не запущен"
fi

report ""
report "========================================="
report "ОТЧЕТ СОХРАНЕН: $REPORT_FILE"
report "========================================="
report ""
report "Следующие шаги:"
report "1. Отправьте этот файл для анализа:"
report "   cat $REPORT_FILE"
report ""
report "2. Или загрузите в pastebin:"
report "   cat $REPORT_FILE | curl -F 'f:1=<-' ix.io"
report ""
report "3. Проверьте логи вручную:"
report "   journalctl -u x-ui -f"
report ""

echo ""
echo -e "${GREEN}Диагностика завершена!${NC}"
echo "Отчет: $REPORT_FILE"
echo ""
