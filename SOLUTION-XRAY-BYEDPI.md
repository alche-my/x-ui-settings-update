# Решение: Интеграция ByeDPI + 3x-ui (Xray)

## Проблема

**Ошибка:** `infra/conf: unable to send through: byedpi-socks`

### Причина

Из исследования исходного кода Xray-core (`infra/conf/xray.go`):

```go
if address.Family().IsDomain() {
    domain := address.Address.Domain()
    if domain != "origin" && domain != "srcip" {
        return nil, errors.New("unable to send through: " + address.String())
    }
}
```

**Что происходит:**
1. Поле `sendThrough` предназначено для IP адреса источника (например, "0.0.0.0")
2. Допустимые значения: IP адреса или специальные слова "origin"/"srcip"
3. 3x-ui GUI **ошибочно записывает** tag outbound-а ("byedpi-socks") в поле `sendThrough`
4. Это вызывает ошибку валидации конфигурации

### Что такое sendThrough?

`sendThrough` — это параметр для выбора **исходящего IP адреса** на серверах с несколькими сетевыми интерфейсами. Он **НЕ** предназначен для proxy chaining.

---

## Правильные методы proxy chaining

### Вариант 1: proxySettings

```json
{
  "tag": "my-vless",
  "protocol": "vless",
  "settings": { ... },
  "proxySettings": {
    "tag": "byedpi-socks"
  }
}
```

**Особенности:**
- ✅ Поддерживается в Xray-core
- ❌ "Does not go through the underlying transport"
- ❌ Может не работать с некоторыми протоколами (gRPC, Reality)

### Вариант 2: dialerProxy (РЕКОМЕНДУЕТСЯ)

```json
{
  "tag": "my-vless",
  "protocol": "vless",
  "settings": { ... },
  "streamSettings": {
    "security": "reality",
    "sockopt": {
      "dialerProxy": "byedpi-socks"
    }
  }
}
```

**Особенности:**
- ✅ Поддерживается в Xray-core
- ✅ **Поддерживает underlying transport** (важно для Reality/TLS)
- ✅ Работает с Reality, Vision, gRPC

---

## Правильная структура конфигурации

### Полный пример config.json

```json
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
      "tag": "RAWR-FL0-TCP-RAWR-FL-TEST",
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
```

### Важные детали

1. **Порядок outbounds:** SOCKS outbound (`byedpi-socks`) должен быть определен **ДО** того, как на него ссылаются
2. **Структура vnext:** Используйте `vnext` для VLESS (не старый формат `address`/`port` напрямую)
3. **dialerProxy в sockopt:** Размещается в `streamSettings.sockopt.dialerProxy`
4. **НЕ использовать sendThrough** для proxy chaining

---

## Решение: Автоматическое исправление

### Использование скрипта fix-xray-config-byedpi.sh

```bash
sudo bash fix-xray-config-byedpi.sh
```

**Что делает скрипт:**
1. Создает бэкап текущего `config.json`
2. Извлекает параметры VLESS из текущей конфигурации
3. Генерирует правильную конфигурацию с `dialerProxy`
4. Проверяет валидность с помощью `xray test`
5. Применяет конфигурацию и перезапускает x-ui
6. Проверяет логи на наличие ошибок
7. В случае проблем — предлагает восстановить бэкап

---

## Проверка работы

### 1. Проверка ByeDPI
```bash
systemctl status byedpi
curl --socks5 127.0.0.1:1080 https://www.google.com
```

**Ожидаемый результат:** HTTP 200/301/302

### 2. Проверка Xray логов
```bash
journalctl -u x-ui -f
```

**Не должно быть:**
- ❌ `unable to send through: byedpi-socks`

**Должно быть:**
- ✅ Xray запущен без ошибок

### 3. Тестирование клиента

Подключитесь клиентом и проверьте:
```bash
# На клиенте
curl --interface <vpn-interface> https://ifconfig.me
```

---

## Ручное исправление

Если скрипт не подходит, исправьте вручную:

### 1. Создать бэкап
```bash
sudo cp /usr/local/x-ui/bin/config.json /usr/local/x-ui/bin/config.json.backup
```

### 2. Отредактировать config.json
```bash
sudo nano /usr/local/x-ui/bin/config.json
```

**Найдите outbound с VLESS и замените структуру:**

❌ **Неправильно:**
```json
{
  "protocol": "vless",
  "sendThrough": "byedpi-socks",  // ← ОШИБКА!
  "settings": {
    "address": "45.12.135.9",
    "port": 9443,
    ...
  }
}
```

✅ **Правильно:**
```json
{
  "protocol": "vless",
  "settings": {
    "vnext": [{
      "address": "45.12.135.9",
      "port": 9443,
      "users": [{ ... }]
    }]
  },
  "streamSettings": {
    "sockopt": {
      "dialerProxy": "byedpi-socks"
    }
  }
}
```

### 3. Проверить и применить
```bash
sudo /usr/local/x-ui/bin/xray-linux-amd64 test -c /usr/local/x-ui/bin/config.json
sudo systemctl restart x-ui
journalctl -u x-ui -f
```

---

## Альтернативное решение: Обход 3x-ui GUI

### Проблема с GUI

3x-ui GUI имеет баг:
- Поле "Отправить через" записывает значение в `sendThrough` вместо `proxySettings` или `dialerProxy`
- Это вызывает ошибку валидации

### Решение

**НЕ используйте** поле "Отправить через" в 3x-ui GUI.

Вместо этого:
1. Создайте outbound через GUI (без proxy chaining)
2. Остановите x-ui: `sudo systemctl stop x-ui`
3. Отредактируйте `/usr/local/x-ui/bin/config.json` вручную
4. Добавьте `dialerProxy` в нужный outbound
5. Запустите x-ui: `sudo systemctl start x-ui`

---

## Источники и документация

### Официальная документация
- [Xray Outbound Configuration](https://xtls.github.io/en/config/outbound.html)
- [Xray Transport Settings](https://xtls.github.io/en/config/transport.html)
- [OneXray Xray Settings](https://onexray.com/docs/home/outbound/xraySetting/)

### Исходный код
- [Xray-core infra/conf/xray.go](https://github.com/XTLS/Xray-core/blob/main/infra/conf/xray.go) - источник ошибки "unable to send through"

### Примеры конфигураций
- [Multi-level proxy scheme with Xray (Gist)](https://gist.github.com/rz6agx/7ff6a6ada0ccc1613b38b50f81749e78)
- [VLESS + Reality Tutorial](https://github.com/wpdevelopment11/xray-tutorial)
- [Xray Introduction (Habr, RU)](https://habr.com/ru/articles/961346/)

### Обсуждения
- [VLESS + Reality Discussion (RU)](https://github.com/XTLS/Xray-core/discussions/3518)
- [gRPC cannot be proxied with dialerProxy](https://github.com/XTLS/Xray-core/issues/2232)

---

## Итоги

✅ **ByeDPI работает:** SOCKS5 на 127.0.0.1:1080
✅ **Рабочая стратегия:** `-s1 -d1`
✅ **Ошибка найдена:** 3x-ui GUI записывает tag в `sendThrough`
✅ **Решение:** Использовать `dialerProxy` в `streamSettings.sockopt`
✅ **Скрипт готов:** `fix-xray-config-byedpi.sh`

**Следующие шаги:**
1. Запустить `sudo bash fix-xray-config-byedpi.sh`
2. Проверить логи: `journalctl -u x-ui -f`
3. Протестировать подключение клиента
