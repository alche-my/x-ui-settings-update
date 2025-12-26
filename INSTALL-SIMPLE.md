# ByeDPI + 3x-ui: Установка одной командой

## 🚀 Быстрая установка

```bash
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/install-byedpi-3xui.sh -o install-byedpi-3xui.sh && chmod +x install-byedpi-3xui.sh && sudo ./install-byedpi-3xui.sh
```

## Что делает скрипт?

1. ✅ Устанавливает ByeDPI
2. ✅ Создает systemd сервис
3. ✅ Собирает информацию о ваших Non-RU серверах
4. ✅ Генерирует **полный** JSON конфиг для 3x-ui
5. ✅ Выводит готовый JSON для copy-paste в панель

## Что скрипт спросит?

- Количество Non-RU серверов
- Для каждого сервера:
  - IP адрес
  - Порт (по умолчанию 443)
  - UUID
  - Reality настройки (Public Key, Short ID, SNI, Fingerprint)
  - gRPC Service Name
- Стратегию балансировки (если серверов >1)

## После установки

1. Скопируйте JSON конфигурацию:
   ```bash
   cat /root/byedpi-config/3xui-full-config.json
   ```

2. Откройте 3x-ui панель в браузере

3. Перейдите: **Panel Settings → Xray Configs**

4. **Замените весь JSON** на скопированный

5. Нажмите **Save** и **Restart Xray**

6. ⚠️ **ВАЖНО**: Добавьте UUID на каждый Non-RU сервер в его 3x-ui панели!

## Проверка

```bash
# ByeDPI
sudo systemctl status byedpi

# 3x-ui
sudo systemctl status x-ui

# Логи
sudo journalctl -u byedpi -f
sudo journalctl -u x-ui -f
```

## Архитектура

```
Клиенты в РФ → RU-сервер (3x-ui) → ByeDPI (DPI bypass) → {
    Non-RU-1 (Reality + gRPC)
    Non-RU-2 (Reality + gRPC)
    Non-RU-3 (Reality + gRPC)
} → Интернет
```

## Формат конфига

Скрипт генерирует **полный** JSON конфиг 3x-ui со всеми секциями:
- `log` - настройки логирования
- `api` - API для управления
- `inbounds` - API tunnel
- `outbounds` - ByeDPI SOCKS + все Non-RU серверы с `dialerProxy`
- `policy` - политики статистики
- `routing` - маршрутизация с балансером (если серверов >1)
- `stats` - статистика
- `metrics` - метрики

## Пример outbound с ByeDPI

```json
{
  "protocol": "vless",
  "settings": {
    "address": "45.12.135.9",
    "port": 443,
    "id": "206b7a77-6295-4f2b-999a-125db3982084",
    "flow": "",
    "encryption": "none"
  },
  "tag": "non-ru-1-via-byedpi",
  "streamSettings": {
    "network": "grpc",
    "security": "reality",
    "realitySettings": {
      "publicKey": "Q_KUAYTAc05sE4CbLnq9vznhan1o4zzAsUwTHPVc9nM",
      "fingerprint": "edge",
      "serverName": "github.com",
      "shortId": "6d12731746e56ad2",
      "spiderX": "/",
      "mldsa65Verify": ""
    },
    "grpcSettings": {
      "serviceName": "svc",
      "authority": "",
      "multiMode": false
    },
    "sockopt": {
      "dialerProxy": "byedpi-socks",  ← Весь трафик через ByeDPI!
      "tcpFastOpen": false,
      "tcpKeepAliveInterval": 0,
      "tcpMptcp": false,
      "penetrate": false,
      "addressPortStrategy": "none"
    }
  }
}
```

## Удаление

```bash
sudo systemctl stop byedpi
sudo systemctl disable byedpi
sudo rm /etc/systemd/system/byedpi.service
sudo rm /usr/local/bin/ciadpi
sudo rm -rf /opt/byedpi
sudo systemctl daemon-reload
```

---

**Время установки:** 2-3 минуты ⚡
**Время настройки:** 1 минута (copy-paste JSON) 📋
**Всего:** ~5 минут 🎯
