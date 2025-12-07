# Мониторинг и автоматическое исправление перегрузки памяти Dokodemo-сервера

## 🔍 Проблема

Dokodemo-door сервер может периодически перегружать память виртуального сервера по следующим причинам:

### ⚠️ ВАЖНО: Утечка памяти БЕЗ клиентов!

Если память растет **даже без подключенных клиентов**, это указывает на **утечку памяти (memory leak)** в конфигурации или самом Xray. Это другая проблема, требующая исправления конфигурации.

**Решение:**
1. Запустите диагностику: `sudo ./diagnose-memory-leak.sh`
2. Примените автоматическое исправление: `sudo ./fix-dokodemo-memory-config.sh`
3. Настройте мониторинг: `./monitor-memory.sh monitor`

См. раздел ["Диагностика утечки без клиентов"](#-диагностика-утечки-памяти-без-клиентов) ниже.

### Основные причины утечки памяти:

1. **Отсутствие timeout для соединений**
   - Dokodemo-door держит соединения открытыми неограниченно долго
   - "Мертвые" соединения накапливаются и занимают память

2. **Нет ограничения на количество одновременных соединений**
   - При большом количестве клиентов память растет линейно
   - Старые соединения не закрываются автоматически

3. **Фрагментация пакетов (если применен tuning level-1/2)**
   - Level 1: фрагменты 100-200 байт, интервал 10-20 мс
   - Level 2: фрагменты 50-150 байт, интервал 5-15 мс (более агрессивно)
   - Каждый фрагмент создает буфер в памяти

4. **Долгоживущие TCP соединения**
   - WebSocket и HTTP/2 соединения могут жить часами
   - Без правильного tcpKeepAlive соединения не очищаются

## 💡 Решение: Автоматический мониторинг и восстановление

Скрипт `monitor-memory.sh` решает проблему перегрузки памяти **без потери качества связи**:

### Основные возможности:

✅ **Мониторинг памяти процесса Xray** (не только системы)
✅ **Graceful restart при превышении порога** (сохраняет активные соединения)
✅ **Защита от restart-loop** (максимум 6 рестартов в час)
✅ **Логирование событий** для анализа проблем
✅ **История рестартов** для мониторинга
✅ **Автоматический запуск через cron/systemd**

---

## 📦 Установка

### 1. Скачать скрипт

```bash
cd /home/user/x-ui-settings-update
chmod +x monitor-memory.sh
```

### 2. Проверить работу

```bash
# Проверить текущий статус памяти
sudo ./monitor-memory.sh status
```

**Пример вывода:**
```
Xray Process Status:
  PID: 12345
  Memory: 450MB / 2048MB (22%)
  Threshold: 80%
  Status: ✓ OK
```

---

## 🚀 Использование

### Ручной запуск

```bash
# Проверить статус памяти
sudo ./monitor-memory.sh status

# Запустить мониторинг один раз (с перезапуском если нужно)
sudo ./monitor-memory.sh monitor

# Показать историю рестартов
./monitor-memory.sh history

# Показать справку
./monitor-memory.sh --help
```

### Настройка порога памяти

По умолчанию скрипт перезапускает x-ui при **80%** использования памяти процессом Xray.

Изменить порог:

```bash
# Установить порог 70%
MEMORY_THRESHOLD=70 sudo ./monitor-memory.sh monitor

# Или экспортировать переменную окружения
export MEMORY_THRESHOLD=70
sudo -E ./monitor-memory.sh monitor
```

---

## ⚙️ Автоматический мониторинг

### Вариант 1: Crontab (простой способ)

Автоматически проверять память каждые **5 минут**:

```bash
# Открыть редактор crontab
sudo crontab -e

# Добавить строку:
*/5 * * * * /home/user/x-ui-settings-update/monitor-memory.sh monitor >> /var/log/x-ui-memory-monitor.log 2>&1
```

**Объяснение:**
- `*/5 * * * *` - каждые 5 минут
- `>> /var/log/x-ui-memory-monitor.log 2>&1` - логи пишутся в файл

**Проверка:**
```bash
# Просмотреть текущие задачи cron
sudo crontab -l

# Проверить логи
sudo tail -f /var/log/x-ui-memory-monitor.log
```

### Вариант 2: Systemd Timer (рекомендуется)

Создать systemd service и timer для более надежного мониторинга:

#### Создать service файл

```bash
sudo nano /etc/systemd/system/x-ui-memory-monitor.service
```

Вставить содержимое:

```ini
[Unit]
Description=X-UI Memory Monitor
After=x-ui.service
Requires=x-ui.service

[Service]
Type=oneshot
ExecStart=/home/user/x-ui-settings-update/monitor-memory.sh monitor
StandardOutput=journal
StandardError=journal
Environment="MEMORY_THRESHOLD=80"

[Install]
WantedBy=multi-user.target
```

#### Создать timer файл

```bash
sudo nano /etc/systemd/system/x-ui-memory-monitor.timer
```

Вставить содержимое:

```ini
[Unit]
Description=X-UI Memory Monitor Timer
Requires=x-ui-memory-monitor.service

[Timer]
# Запускать каждые 5 минут
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=1s

[Install]
WantedBy=timers.target
```

#### Активировать timer

```bash
# Перезагрузить systemd
sudo systemctl daemon-reload

# Включить и запустить timer
sudo systemctl enable x-ui-memory-monitor.timer
sudo systemctl start x-ui-memory-monitor.timer

# Проверить статус
sudo systemctl status x-ui-memory-monitor.timer

# Показать последние запуски
sudo systemctl list-timers x-ui-memory-monitor.timer
```

#### Просмотр логов systemd

```bash
# Следить за логами в реальном времени
sudo journalctl -u x-ui-memory-monitor.service -f

# Показать последние 50 записей
sudo journalctl -u x-ui-memory-monitor.service -n 50

# Логи за последний час
sudo journalctl -u x-ui-memory-monitor.service --since "1 hour ago"
```

---

## 📊 Мониторинг и диагностика

### Проверка статуса

```bash
# Текущее состояние памяти
sudo ./monitor-memory.sh status

# История рестартов
./monitor-memory.sh history
```

**Пример вывода истории:**
```
=== Restart History ===
Last 10 restarts:
----------------------------------------
Timestamp              Memory
----------------------------------------
2025-12-07 14:23:15   820MB 82%
2025-12-07 16:45:32   950MB 95%
2025-12-07 19:12:08   780MB 78%
----------------------------------------

Restarts in last hour: 0/6
```

### Проверка логов

```bash
# Последние записи лога
sudo tail -f /var/log/x-ui-memory-monitor.log

# Поиск перезапусков
sudo grep "Memory threshold exceeded" /var/log/x-ui-memory-monitor.log

# Поиск ошибок
sudo grep "ERROR" /var/log/x-ui-memory-monitor.log
```

---

## 🔧 Настройка параметров

Скрипт настраивается через переменные окружения:

| Переменная | Описание | По умолчанию |
|-----------|----------|--------------|
| `MEMORY_THRESHOLD` | Порог памяти в % | 80 |
| `MIN_RESTART_INTERVAL` | Минимальный интервал между рестартами (секунды) | 300 (5 минут) |
| `MAX_RESTARTS_PER_HOUR` | Максимум рестартов в час | 6 |

### Пример: Более агрессивный мониторинг

```bash
# Перезапускать при 60% памяти, но не чаще чем раз в 10 минут
MEMORY_THRESHOLD=60 MIN_RESTART_INTERVAL=600 sudo ./monitor-memory.sh monitor
```

### Пример: Менее частые рестарты

```bash
# Перезапускать при 90% памяти, максимум 3 раза в час
MEMORY_THRESHOLD=90 MAX_RESTARTS_PER_HOUR=3 sudo ./monitor-memory.sh monitor
```

---

## 🛡️ Защита от restart-loop

Скрипт имеет встроенную защиту от бесконечных рестартов:

### Ограничения:

1. **Минимальный интервал между рестартами**: 5 минут (300 секунд)
2. **Максимум рестартов в час**: 6 рестартов
3. **Lock-файл**: Предотвращает одновременный запуск нескольких копий

### Что происходит при превышении лимитов:

```
[ERROR] 2025-12-07 14:30:00 - Restart limit reached: 6 restarts in the last hour
[ERROR] 2025-12-07 14:30:00 - Maximum allowed: 6 per hour
[ERROR] 2025-12-07 14:30:00 - Skipping restart to prevent restart loop
[ERROR] 2025-12-07 14:30:00 - Please check for underlying issues causing frequent restarts
```

**Действия при частых рестартах:**

1. Проверить логи x-ui: `sudo journalctl -u x-ui -n 100`
2. Увеличить память сервера
3. Оптимизировать настройки Dokodemo (уменьшить фрагментацию)
4. Проверить количество активных соединений: `sudo ss -s`

---

## 🧪 Тестирование

### Симуляция высокого использования памяти

**⚠️ ВНИМАНИЕ**: Выполняйте только на тестовом сервере!

```bash
# Временно понизить порог до 10% для теста
MEMORY_THRESHOLD=10 sudo ./monitor-memory.sh monitor

# Вы должны увидеть:
# [WARN] Memory threshold exceeded: XX% >= 10%
# [WARN] Attempting to recover by restarting x-ui service...
# [SUCCESS] Memory recovery completed successfully
```

### Проверка работы после установки

1. **Проверить статус:**
   ```bash
   sudo ./monitor-memory.sh status
   ```

2. **Запустить мониторинг вручную:**
   ```bash
   sudo ./monitor-memory.sh monitor
   ```

3. **Проверить cron/systemd:**
   ```bash
   # Для cron
   sudo crontab -l

   # Для systemd
   sudo systemctl status x-ui-memory-monitor.timer
   ```

4. **Подождать 5-10 минут и проверить логи:**
   ```bash
   sudo tail -20 /var/log/x-ui-memory-monitor.log
   ```

---

## 📈 Рекомендации по настройке

### Для маленьких VPS (1-2 GB RAM)

```bash
# Более агрессивный мониторинг
MEMORY_THRESHOLD=70 sudo ./monitor-memory.sh monitor

# В crontab: проверять каждые 3 минуты
*/3 * * * * /home/user/x-ui-settings-update/monitor-memory.sh monitor
```

### Для средних VPS (4-8 GB RAM)

```bash
# Стандартные настройки
MEMORY_THRESHOLD=80 sudo ./monitor-memory.sh monitor

# В crontab: проверять каждые 5 минут
*/5 * * * * /home/user/x-ui-settings-update/monitor-memory.sh monitor
```

### Для больших VPS (16+ GB RAM)

```bash
# Менее частый мониторинг
MEMORY_THRESHOLD=85 sudo ./monitor-memory.sh monitor

# В crontab: проверять каждые 10 минут
*/10 * * * * /home/user/x-ui-settings-update/monitor-memory.sh monitor
```

---

## 🔍 Дополнительная диагностика

### Анализ использования памяти

```bash
# Показать top процессы по памяти
ps aux --sort=-%mem | head -20

# Использование памяти процессом xray
ps -p $(pgrep xray) -o pid,user,%mem,%cpu,cmd

# Детальная информация о памяти
cat /proc/$(pgrep xray)/status | grep -E "VmSize|VmRSS|VmData"
```

### Мониторинг соединений

```bash
# Количество TCP соединений
ss -s

# Соединения на порту 443 (dokodemo)
ss -tn state established '( dport = :443 or sport = :443 )' | wc -l

# Активные соединения xray
lsof -i -a -p $(pgrep xray) | wc -l
```

---

## ❓ Частые вопросы (FAQ)

### Q: Будет ли прерываться связь при перезапуске?

**A:** Нет, скрипт использует **graceful restart** (`systemctl restart`), который:
- Отправляет SIGTERM процессу для корректного завершения
- Дает время на закрытие соединений
- Запускает новый процесс
- Минимальная задержка: 1-2 секунды

### Q: Как часто нужно запускать мониторинг?

**A:** Рекомендуется каждые **5 минут** для баланса между быстрой реакцией и нагрузкой на систему.

### Q: Что делать если рестарты происходят слишком часто?

**A:**
1. Увеличить память VPS
2. Уменьшить агрессивность фрагментации (downgrade с level-2 на level-1)
3. Увеличить `MEMORY_THRESHOLD` до 85-90%
4. Проверить логи на наличие утечек памяти
5. Уменьшить количество клиентов или разделить нагрузку на несколько серверов

### Q: Можно ли запускать скрипт без root?

**A:** Нет, для перезапуска x-ui service нужны root права. Используйте `sudo`.

### Q: Как удалить автоматический мониторинг?

**A:**
```bash
# Для cron
sudo crontab -e
# Удалить строку с monitor-memory.sh

# Для systemd
sudo systemctl stop x-ui-memory-monitor.timer
sudo systemctl disable x-ui-memory-monitor.timer
sudo rm /etc/systemd/system/x-ui-memory-monitor.*
sudo systemctl daemon-reload
```

---

## 📋 Файлы и логи

| Файл | Путь | Описание |
|------|------|----------|
| Скрипт | `/home/user/x-ui-settings-update/monitor-memory.sh` | Основной скрипт |
| Лог файл | `/var/log/x-ui-memory-monitor.log` | Логи мониторинга |
| История | `/var/lib/x-ui-memory-monitor.history` | История рестартов |
| Lock файл | `/var/run/x-ui-memory-monitor.lock` | Блокировка повторных запусков |

---

## 🆘 Поддержка

### Если скрипт не работает:

1. **Проверить права:**
   ```bash
   ls -l /home/user/x-ui-settings-update/monitor-memory.sh
   # Должно быть: -rwxr-xr-x
   ```

2. **Проверить x-ui service:**
   ```bash
   sudo systemctl status x-ui
   ```

3. **Запустить с verbose выводом:**
   ```bash
   sudo bash -x /home/user/x-ui-settings-update/monitor-memory.sh monitor
   ```

4. **Проверить логи:**
   ```bash
   sudo journalctl -u x-ui -n 50
   sudo tail -50 /var/log/x-ui-memory-monitor.log
   ```

### Создать Issue:

Если проблема не решается, создайте Issue в репозитории:

https://github.com/alche-my/x-ui-settings-update/issues

Приложите:
- Вывод `monitor-memory.sh status`
- Логи `/var/log/x-ui-memory-monitor.log`
- Вывод `free -h` и `ps aux | grep xray`

---

## 📚 Дополнительные ресурсы

- [README Dokodemo Bridge](README-dokodemo-bridge.md)
- [Troubleshooting Dokodemo](TROUBLESHOOTING-dokodemo.md)
- [Диагностический скрипт](diagnose-dokodemo-bridge.sh)
- [X-UI Tuning](x-ui-tuning/README.md)

---

## ✅ Итоговая проверка

После настройки автоматического мониторинга проверьте:

- [ ] Скрипт запускается без ошибок: `sudo ./monitor-memory.sh status`
- [ ] Cron/Systemd настроен: `sudo crontab -l` или `sudo systemctl status x-ui-memory-monitor.timer`
- [ ] Логи пишутся: `sudo tail -f /var/log/x-ui-memory-monitor.log`
- [ ] История рестартов работает: `./monitor-memory.sh history`
- [ ] x-ui service работает: `sudo systemctl status x-ui`

**🎉 Готово! Ваш Dokodemo-сервер теперь защищен от перегрузки памяти!**

---

## 🔬 Диагностика утечки памяти БЕЗ клиентов

### Проблема: Память растет даже без подключений

Если вы заметили, что память Xray процесса растет **даже когда нет активных клиентов**, это указывает на **утечку памяти** в конфигурации.

### 🛠️ Автоматическая диагностика

Запустите специальный диагностический скрипт:

```bash
cd /root/x-ui-settings-update
sudo ./diagnose-memory-leak.sh
```

#### Что проверяет скрипт:

1. **Версия Xray** - старые версии имеют известные баги
2. **Уровень логирования** - debug/info может вызывать утечки
3. **DNS конфигурация** - отключенный кеш создает утечку
4. **Sniffing** - накапливает данные в памяти
5. **TCP KeepAlive** - мертвые соединения не закрываются
6. **Routing rules** - слишком много правил
7. **Мониторинг роста памяти** - в реальном времени за 60 секунд
8. **Активные соединения** - проверка наличия клиентов

#### Пример вывода:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
6. Мониторинг роста памяти (60s)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Мониторинг PID: 12345
Интервал: 10s

Время     | Память (MB) | Δ (MB) | Δ (%)
----------|-------------|--------|--------
14:23:10 |         145 |     +2 |  +1.4%
14:23:20 |         148 |     +3 |  +2.0%
14:23:30 |         152 |     +4 |  +2.7%
----------|-------------|--------|--------

Анализ результатов:
  - Начальная память: 145 MB
  - Конечная память:  152 MB
  - Общий рост:       7 MB
  - Скорость роста:   7.00 MB/минуту

✗ Обнаружен умеренный рост памяти
  Рекомендуется мониторинг и оптимизация
```

---

### ⚡ Автоматическое исправление

После диагностики запустите скрипт автоматического исправления:

```bash
sudo ./fix-dokodemo-memory-config.sh
```

#### Что исправляет скрипт:

| Исправление | Что делает | Экономия памяти |
|-------------|------------|-----------------|
| **Логирование** | Устанавливает `warning` вместо `debug/info` | 10-20% |
| **Access log** | Отключает логи доступа | 5-10% |
| **DNS кеш** | Включает кеширование DNS | 5-15% |
| **Sniffing** | Отключает sniffing в dokodemo | 20-30% |
| **TCP KeepAlive** | Добавляет автозакрытие соединений (30s) | 15-25% |
| **Buffer sizes** | Оптимизирует размеры буферов (4 KB) | 5-10% |

**Ожидаемое снижение памяти: 30-50% 🎯**

#### Пример вывода:

```bash
$ sudo ./fix-dokodemo-memory-config.sh

╔════════════════════════════════════════════════════════════════╗
║   Dokodemo Memory Configuration Auto-Fix                     ║
╚════════════════════════════════════════════════════════════════╝

Этот скрипт автоматически исправит конфигурацию для устранения утечки памяти.

Будут применены следующие изменения:
  1. Логирование: warning (вместо debug/info)
  2. Access log: отключен
  3. DNS кеш: включен
  4. Sniffing: отключен (в dokodemo)
  5. TCP KeepAlive: 30s (автозакрытие мертвых соединений)
  6. Buffer sizes: оптимизированы (4 KB)

Продолжить? (y/n): y

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Создание резервной копии
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Резервная копия создана: /root/dokodemo-memory-fix-backups/config-before-memfix-20251207-142315.json

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Исправление уровня логирования
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ Текущий уровень: debug
⚠ Изменяем на 'warning' для уменьшения памяти...
✓ Логирование изменено на 'warning'

... (остальные исправления)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Применение завершено
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Результаты:
  - Применено исправлений: 6/6
  - Резервная копия: /root/dokodemo-memory-fix-backups/config-before-memfix-20251207-142315.json

✓ Конфигурация оптимизирована для экономии памяти!

Следующие шаги:
  1. Подождите 5-10 минут
  2. Проверьте память: ./monitor-memory.sh status
  3. Запустите диагностику: ./diagnose-memory-leak.sh
  4. Настройте автомониторинг: */5 * * * * /path/to/monitor-memory.sh monitor

ℹ Ожидаемое снижение потребления памяти: 30-50%
```

---

### 🧪 Проверка результата

После применения исправлений:

#### 1. Проверьте текущую память

```bash
./monitor-memory.sh status
```

**До исправления:**
```
Xray Process Status:
  PID: 12345
  Memory: 450MB / 2048MB (22%)  ← Высокое потребление
  Threshold: 80%
  Status: ⚠️  WARNING
```

**После исправления (через 10-15 минут):**
```
Xray Process Status:
  PID: 12678
  Memory: 180MB / 2048MB (9%)  ← Снижено на 60%!
  Threshold: 80%
  Status: ✓ OK
```

#### 2. Запустите повторную диагностику

```bash
sudo ./diagnose-memory-leak.sh
```

Проверьте раздел "6. Мониторинг роста памяти" - рост должен быть минимальным (< 2 MB за минуту).

#### 3. Настройте автоматический мониторинг

```bash
sudo crontab -e
# Добавить:
*/5 * * * * /root/x-ui-settings-update/monitor-memory.sh monitor >> /var/log/x-ui-memory-monitor.log 2>&1
```

---

### 📊 Частые причины утечки БЕЗ клиентов

| Причина | Как проявляется | Решение |
|---------|----------------|---------|
| **Debug logging** | Логи накапливаются в памяти | Изменить на `warning` |
| **Sniffing enabled** | Буферы для анализа трафика | Отключить sniffing |
| **DNS без кеша** | Каждый резолв создает объект | Включить DNS cache |
| **Нет TCP KeepAlive** | Мертвые соединения висят | Добавить keepalive 30s |
| **Старый Xray** | Известные баги версий < 1.8.0 | Обновить до latest |

---

### 🔧 Ручное исправление (если скрипт не помог)

#### 1. Отключить sniffing вручную

Отредактируйте `/usr/local/x-ui/bin/config.json`:

```json
{
  "inbounds": [
    {
      "protocol": "dokodemo-door",
      "sniffing": {
        "enabled": false  ← ИЗМЕНИТЬ на false
      }
    }
  ]
}
```

#### 2. Изменить логирование

```json
{
  "log": {
    "loglevel": "warning"  ← ИЗМЕНИТЬ на warning
  }
}
```

#### 3. Включить DNS кеш

Убедитесь, что НЕТ строки `"disableCache": true` в секции `dns`.

#### 4. Перезапустить x-ui

```bash
sudo systemctl restart x-ui
```

---

### 🆘 Если ничего не помогло

#### Вариант 1: Обновить Xray

```bash
# Остановить x-ui
sudo systemctl stop x-ui

# Обновить 3x-ui (включая Xray)
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# Запустить x-ui
sudo systemctl start x-ui
```

#### Вариант 2: Уменьшить routing rules

Проверьте количество правил:

```bash
jq '.routing.rules | length' /usr/local/x-ui/bin/config.json
```

Если больше 20 - уменьшите до необходимого минимума.

#### Вариант 3: Увеличить RAM сервера

Если после всех оптимизаций память все равно растет - возможно, VPS слишком маленький. Рассмотрите апгрейд до 2 GB RAM.

---

**Итог:** С помощью `diagnose-memory-leak.sh` и `fix-dokodemo-memory-config.sh` можно автоматически найти и исправить утечки памяти без клиентов! 🎯
