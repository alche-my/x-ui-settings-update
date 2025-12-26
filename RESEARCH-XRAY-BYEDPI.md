# Исследование: Правильная настройка Xray + ByeDPI

## Проблема
В 3x-ui GUI нет поддержки `proxySettings` для outbound. Нужно найти правильный способ.

## Возможные решения

### Вариант 1: sockopt.dialerProxy (НЕ работает с gRPC)
```json
{
  "streamSettings": {
    "sockopt": {
      "dialerProxy": "byedpi-socks"
    }
  }
}
```
❌ Не работает с gRPC (GitHub Issue #2232)

### Вариант 2: proxySettings (документация Xray)
```json
{
  "proxySettings": {
    "tag": "byedpi-socks",
    "transportLayer": true
  }
}
```
❓ Неизвестно, поддерживается ли в 3x-ui GUI

### Вариант 3: Chainable outbound (новый Xray)
Возможно в новых версиях Xray есть другой синтаксис

### Вариант 4: Прямое редактирование JSON
Редактировать `/usr/local/x-ui/bin/config.json` напрямую, минуя GUI

## Текущий статус
- ByeDPI работает: ✓
- ByeDPI SOCKS5 (127.0.0.1:1080): ✓
- Тест к google.com через ByeDPI: ✓ HTTP 200
- Интеграция с Xray: ❓ Нужно проверить

## Следующие шаги
1. Проверить текущий config.json на сервере
2. Попробовать применить JSON с proxySettings напрямую
3. Протестировать подключение клиента
4. Если не работает - искать альтернативные методы

## Источники для изучения
- https://github.com/XTLS/Xray-examples
- https://github.com/hufrea/byedpi/discussions/195 (туннелирование трафика)
- https://github.com/MHSanaei/3x-ui/wiki/Advanced (3x-ui advanced)
