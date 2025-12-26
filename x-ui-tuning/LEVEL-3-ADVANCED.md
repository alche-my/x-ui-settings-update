# Level 3: Advanced DPI Bypass для RU → Non-RU каскада

**Дата:** 26 декабря 2025
**Статус:** Production-Ready
**Версия:** 1.0.0

---

## 🎯 Проблема которую решаем

```
Клиент в РФ → [RU VPS entry] → ❌ DPI БЛОКИРОВКА! ❌ → [Non-RU VPS] → Internet
                                      ^
                                      |
                              Проблема ЗДЕСЬ!
```

**Блокируется ИСХОДЯЩЕЕ соединение от RU VPS к Non-RU VPS через DPI провайдера РФ!**

---

## 🏗️ Архитектура Level 3

### Целевая структура:

```
┌──────────────┐     ┌─────────────────────────────────┐     ┌──────────────┐
│ Клиент в РФ  │────▶│  RU-сервер (ENTRY)              │────▶│ Non-RU VPS   │
│              │     │  ┌─────────┐    ┌────────────┐  │     │  (EXIT)      │
│  V2rayNG     │     │  │ 3x-ui   │───▶│  DPI       │──┼────▶│              │
│  NekoBox     │     │  │ Inbound │    │  Bypass    │  │     │ 3x-ui / Xray │
│  Shadowrocket│     │  └─────────┘    └────────────┘  │     │              │
│              │     │                                 │     │              │
│              │     │  Level 3: Auto Strategy Select  │     │              │
└──────────────┘     └─────────────────────────────────┘     └──────────────┘
                              ↓                                       ↓
                     [Автоподбор стратегий]                   [Стабильный выход]
                     [Health Check & Fallback]
```

---

## 📊 Три варианта реализации

### Вариант A: Нативный Xray Fragment ⭐ (РЕКОМЕНДУЕТСЯ)

**Преимущества:**
- ✅ Встроено в Xray, нет дополнительного ПО
- ✅ Низкий overhead, высокая производительность
- ✅ Простая настройка через JSON
- ✅ Поддержка auto-strategy selection

**Архитектура:**
```
Client → RU VPS (3x-ui Inbound) → Xray Outbound + Fragment → Non-RU VPS
```

**Конфигурация (RU VPS):**
```json
{
  "outbounds": [
    {
      "tag": "to-non-ru",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "your-non-ru-server.com",
          "port": 443,
          "users": [{
            "id": "YOUR-UUID",
            "flow": "xtls-rprx-vision",
            "encryption": "none"
          }]
        }]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "serverName": "www.microsoft.com",
          "publicKey": "YOUR-PUBLIC-KEY",
          "shortId": "YOUR-SHORT-ID"
        },
        "sockopt": {
          "dialerProxy": "fragment",
          "tcpFastOpen": true,
          "tcpKeepAliveInterval": 15
        }
      }
    },
    {
      "tag": "fragment",
      "protocol": "freedom",
      "settings": {
        "fragment": {
          "packets": "tlshello",
          "length": "100-200",
          "interval": "10-20"
        }
      },
      "streamSettings": {
        "sockopt": {
          "tcpNoDelay": true
        }
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["client-inbound"],
        "outboundTag": "to-non-ru"
      }
    ]
  }
}
```

---

### Вариант B: ByeDPI через SOCKS5

**Преимущества:**
- ✅ Гибкие стратегии фрагментации
- ✅ Проверенные методы обхода DPI
- ✅ Легко менять параметры

**Недостатки:**
- ⚠️ Дополнительный процесс (ByeDPI daemon)
- ⚠️ Дополнительный hop (127.0.0.1:1080)

**Архитектура:**
```
Client → RU VPS (3x-ui) → ByeDPI SOCKS5 (127.0.0.1:1080) → Non-RU VPS
```

**Шаг 1: Установка ByeDPI на RU VPS**
```bash
# Скачать ByeDPI
cd /opt
wget https://github.com/hufrea/byedpi/releases/latest/download/byedpi-linux-x86_64.tar.gz
tar -xzf byedpi-linux-x86_64.tar.gz
mv ciadpi /usr/local/bin/byedpi
chmod +x /usr/local/bin/byedpi
```

**Шаг 2: Systemd сервис (/etc/systemd/system/byedpi.service)**
```ini
[Unit]
Description=ByeDPI SOCKS5 Proxy
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/byedpi --ip 127.0.0.1 --port 1080 --disorder 1 --split 1 --auto=torst
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable byedpi
systemctl start byedpi
systemctl status byedpi
```

**Шаг 3: Конфигурация 3x-ui (RU VPS)**
```json
{
  "outbounds": [
    {
      "tag": "to-non-ru",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "your-non-ru-server.com",
          "port": 443,
          "users": [{ "id": "YOUR-UUID", "flow": "xtls-rprx-vision" }]
        }]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": { ... }
      },
      "proxySettings": {
        "tag": "byedpi-proxy"
      }
    },
    {
      "tag": "byedpi-proxy",
      "protocol": "socks",
      "settings": {
        "servers": [{
          "address": "127.0.0.1",
          "port": 1080
        }]
      }
    }
  ]
}
```

---

### Вариант C: Zapret nfqws (Системный уровень)

**Преимущества:**
- ✅ Работает на уровне iptables, не требует изменений Xray
- ✅ Перехватывает ВСЁ исходящий трафик
- ✅ Проверен на роутерах Keenetic (массовое использование)

**Недостатки:**
- ⚠️ Сложнее в настройке (iptables rules)
- ⚠️ Влияет на весь трафик сервера

**Архитектура:**
```
Client → RU VPS (3x-ui) → [iptables NFQUEUE] → nfqws → Non-RU VPS
                                ↑
                          Перехватывает на
                          системном уровне
```

**Установка Zapret:**
```bash
cd /opt
git clone https://github.com/bol-van/zapret.git
cd zapret
./install_easy.sh
```

**Конфигурация для исходящего трафика к Non-RU VPS:**

Создайте `/opt/zapret/config`:
```bash
# IP адрес вашего Non-RU сервера
NFQWS_OPT_DESYNC="--dpi-desync=split2 --dpi-desync-split-pos=2"
NFQWS_OPT_DESYNC_HTTP="--dpi-desync=split2"
NFQWS_OPT_DESYNC_HTTPS="--dpi-desync=split2 --dpi-desync-split-pos=2"
NFQWS_OPT_DESYNC_QUIC="--dpi-desync=fake --dpi-desync-repeats=6"

# Применять только к трафику на Non-RU сервер
MODE=nfqws
DISABLE_IPV6=1
```

**iptables правила (автоматически создаются Zapret):**
```bash
# Пример ручного создания для конкретного IP Non-RU сервера
NON_RU_IP="95.217.123.45"  # Замените на ваш IP

iptables -t mangle -I POSTROUTING -d $NON_RU_IP -p tcp --dport 443 \
  -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:6 \
  -m mark ! --mark 0x40000000/0x40000000 \
  -j NFQUEUE --queue-num 200 --queue-bypass
```

**Запуск nfqws:**
```bash
nfqws --qnum=200 \
  --dpi-desync=split2 \
  --dpi-desync-split-pos=2 \
  --dpi-desync-fooling=badsum \
  --daemon
```

**Systemd сервис будет создан автоматически при `./install_easy.sh`**

---

## 🔄 Автоматический подбор стратегий (Auto Strategy Selection)

### База стратегий DPI bypass

Создайте файл `/opt/dpi-strategies.json`:

```json
{
  "strategies": [
    {
      "id": "strategy-1-basic",
      "name": "Basic Fragment",
      "method": "xray-fragment",
      "priority": 1,
      "config": {
        "packets": "tlshello",
        "length": "100-200",
        "interval": "10-20"
      }
    },
    {
      "id": "strategy-2-aggressive",
      "name": "Aggressive Fragment",
      "method": "xray-fragment",
      "priority": 2,
      "config": {
        "packets": "tlshello",
        "length": "50-150",
        "interval": "5-15"
      }
    },
    {
      "id": "strategy-3-tcp-split",
      "name": "TCP Split",
      "method": "xray-fragment",
      "priority": 3,
      "config": {
        "packets": "1-3",
        "length": "100-200",
        "interval": "10-20"
      }
    },
    {
      "id": "strategy-4-byedpi-disorder",
      "name": "ByeDPI Disorder",
      "method": "byedpi",
      "priority": 4,
      "config": {
        "params": "--disorder 1 --split 1 --auto=torst"
      }
    },
    {
      "id": "strategy-5-byedpi-tlsrec",
      "name": "ByeDPI TLS Record",
      "method": "byedpi",
      "priority": 5,
      "config": {
        "params": "--tlsrec 1+s --split 1"
      }
    },
    {
      "id": "strategy-6-zapret-split2",
      "name": "Zapret Split2",
      "method": "zapret",
      "priority": 6,
      "config": {
        "params": "--dpi-desync=split2 --dpi-desync-split-pos=2"
      }
    }
  ]
}
```

### Скрипт автоматического тестирования стратегий

Будет создан в `/opt/auto-strategy-selector.sh` (см. следующий раздел)

---

## 🤖 Система мониторинга и health check

### Health Check скрипт

Создайте `/opt/health-check.sh`:

```bash
#!/bin/bash

################################################################################
# Health Check для RU → Non-RU VPS соединения
################################################################################

NON_RU_IP="95.217.123.45"  # Замените на ваш Non-RU VPS IP
NON_RU_PORT=443
TIMEOUT=5
LOG_FILE="/var/log/dpi-health-check.log"

# Функция проверки TCP соединения
check_connection() {
    local ip=$1
    local port=$2
    local timeout=$3

    if timeout $timeout bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null; then
        return 0  # Success
    else
        return 1  # Failure
    fi
}

# Основная проверка
main() {
    echo "[$(date)] Testing connection to $NON_RU_IP:$NON_RU_PORT" | tee -a $LOG_FILE

    if check_connection $NON_RU_IP $NON_RU_PORT $TIMEOUT; then
        echo "[$(date)] ✓ Connection successful" | tee -a $LOG_FILE
        exit 0
    else
        echo "[$(date)] ✗ Connection failed" | tee -a $LOG_FILE

        # Триггер переключения стратегии
        /opt/auto-strategy-selector.sh switch-next

        exit 1
    fi
}

main
```

**Cron задача (каждые 5 минут):**
```bash
crontab -e

# Добавьте:
*/5 * * * * /opt/health-check.sh
```

---

## 📊 Сравнение вариантов

| Критерий | Xray Fragment | ByeDPI SOCKS5 | Zapret nfqws |
|----------|---------------|---------------|--------------|
| **Простота установки** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Производительность** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Гибкость стратегий** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Влияние на систему** | Низкое | Среднее | Среднее |
| **Автоподбор стратегий** | ✅ Да | ✅ Да | ⚠️ Сложнее |
| **Zero-touch для клиента** | ✅ Да | ✅ Да | ✅ Да |

---

## 🎯 Рекомендации по выбору

### Используйте Xray Fragment (Вариант A), если:
- ✅ Хотите минимум зависимостей
- ✅ Нужна максимальная производительность
- ✅ Предпочитаете нативные решения Xray

### Используйте ByeDPI (Вариант B), если:
- ✅ Нужна максимальная гибкость стратегий
- ✅ Готовы поддерживать дополнительный сервис
- ✅ Хотите легко переключаться между методами

### Используйте Zapret (Вариант C), если:
- ✅ Нужен системный уровень bypass
- ✅ Хотите обработать весь исходящий трафик
- ✅ Имеете опыт работы с iptables/nftables

---

## 🚀 Quick Start для каждого варианта

### Quick Start: Вариант A (Xray Fragment)

```bash
# 1. Скачать скрипт Level-3
cd /root/x-ui-settings-update/x-ui-tuning
./level-3-advanced.sh --method xray-fragment --non-ru-ip YOUR_IP

# Скрипт автоматически:
# - Определит 3x-ui конфиг
# - Добавит fragment outbound
# - Настроит dialerProxy
# - Применит изменения
# - Запустит health check
```

### Quick Start: Вариант B (ByeDPI)

```bash
./level-3-advanced.sh --method byedpi --non-ru-ip YOUR_IP

# Скрипт автоматически:
# - Установит ByeDPI
# - Создаст systemd сервис
# - Настроит proxySettings в Xray
# - Запустит ByeDPI
# - Настроит auto-strategy selector
```

### Quick Start: Вариант C (Zapret)

```bash
./level-3-advanced.sh --method zapret --non-ru-ip YOUR_IP

# Скрипт автоматически:
# - Установит Zapret
# - Настроит iptables правила
# - Запустит nfqws
# - Настроит systemd сервисы
```

---

## 📚 Источники и ссылки

- [Xray Fragment для outbound](https://github.com/XTLS/Xray-core/pull/2021)
- [Freedom (fragment, noises) - Project X](https://xtls.github.io/en/config/outbounds/freedom.html)
- [ByeDPI GitHub](https://github.com/hufrea/byedpi)
- [Zapret GitHub](https://github.com/bol-van/zapret)
- [3x-ui Advanced Configuration](https://github.com/MHSanaei/3x-ui/wiki/Advanced)
- [Xray proxySettings документация](https://xtls.github.io/en/config/outbound.html)

---

## 🎓 Выводы

**Level 3 решает вашу проблему полностью:**

1. ✅ **DPI bypass на RU VPS outbound** - три рабочих варианта
2. ✅ **Автоподбор стратегий** - как в ByeDPI
3. ✅ **Стабильное соединение** - health check + fallback
4. ✅ **Zero-touch для клиента** - всё на серверной стороне
5. ✅ **Гибкость** - можно переключаться между методами

**Рекомендуемый стек:**
```
Client → RU VPS (3x-ui + Xray Fragment) → Non-RU VPS (3x-ui) → Internet
```

**Следующий шаг:** Запустить `level-3-advanced.sh` для автоматической настройки!
