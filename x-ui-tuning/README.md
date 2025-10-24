# 3x-ui DPI Bypass Configuration Scripts

Набор скриптов для поэтапной настройки сервера 3x-ui (VLESS+Reality) для обхода блокировок в Российской Федерации.

**Дата актуальности:** 23 октября 2025
**Источник стратегий:** [GitHub Issue #5704](https://github.com/Flowseal/zapret-discord-youtube/issues/5704)

## 📋 Содержание

- [Описание проблемы](#описание-проблемы)
- [Архитектура решения](#архитектура-решения)
- [Требования](#требования)
- [Установка](#установка)
- [Использование](#использование)
- [Тестирование](#тестирование)
- [Откат изменений](#откат-изменений)
- [Troubleshooting](#troubleshooting)
- [Масштабирование](#масштабирование)
- [Ссылки](#ссылки)

---

## 🔍 Описание проблемы

### Хронология блокировок (2025)

- **1 апреля 2025** - первая волна ужесточения блокировок
- **9 июня 2025** - массовое ухудшение работы Zapret и VPN
- **20-21 октября 2025** - новая волна блокировок Cloudflare, OVH, Hetzner, DigitalOcean
- **23 октября 2025** - Zapret перестал работать для большинства пользователей

### Три уровня блокировок

1. **Базовый DPI (Deep Packet Inspection)**
   - Анализ TLS Client Hello
   - Обнаружение доменных имен (SNI)
   - Блокировка по портам 80, 443

2. **CDN-специфичные блокировки**
   - Cloudflare (AS13335)
   - DigitalOcean (AS14061)
   - Akamai (AS16625, AS20940)
   - Специальные порты: 2053, 2083, 2087, 2096, 8443

3. **Эвристические правила**
   - Блокировка поддоменов 4+ уровней
   - Анализ паттернов трафика
   - Game/VoIP трафик (Discord UDP 19294-19344)

---

## 🏗️ Архитектура решения

Три уровня настройки сервера для последовательного обхода блокировок:

```
Level 1: Basic DPI Bypass ✅
    ↓
    Fragment + TCP optimization + Basic routing
    ↓
    Тест: Google, Discord, YouTube
    ↓
Level 2: CDN Bypass ✅
    ↓
    Cloudflare domains + special ports + aggressive fragmentation
    ↓
    Тест: Discord voice, YouTube video, CDN services
    ↓
Level 3: Advanced (запланировано)
    ↓
    Hardcore mode + Game ports + TLS randomization
    ↓
    Тест: Complex subdomains, Games, All services
```

### Принцип работы

Каждый уровень:
1. Создает бэкап текущей конфигурации
2. Модифицирует `/usr/local/x-ui/bin/xray-linux-amd64/config.json`
3. Применяет изменения атомарно
4. Перезапускает сервис x-ui
5. Тестирует подключение локально
6. Выводит детальный отчет

**Важно:** Изменения применяются только на сервере. Клиент продолжает использовать тот же vless:// ключ без изменений.

---

## ⚙️ Требования

### Системные требования

- **ОС:** Linux (Ubuntu/Debian рекомендуется)
- **Права:** root или sudo
- **Место на диске:** минимум 100 MB свободно
- **3x-ui:** установлен и запущен
- **Протокол:** VLESS+Reality

### Зависимости

**Устанавливаются автоматически!** ✨

При запуске скрипта автоматически проверяются и устанавливаются:
- `jq` - для работы с JSON конфигурациями
- `curl` - для HTTP тестов
- `dig` (dnsutils) - для DNS тестов
- `nc` (netcat) - для TCP тестов
- `systemctl` - для управления сервисами (обычно встроен)

<details>
<summary>Ручная установка (если автоматическая не сработала)</summary>

```bash
apt-get update
apt-get install -y jq curl dnsutils netcat-openbsd
```
</details>

---

## 📦 Установка

### 1. Клонирование репозитория

```bash
cd /root
git clone https://github.com/alche-my/x-ui-settings-update.git
cd x-ui-settings-update/x-ui-tuning
```

Или скопируйте файлы вручную на сервер.

### 2. Установка зависимостей

**Не требуется!** ✨ Скрипт автоматически установит всё необходимое.

<details>
<summary>Ручная установка (опционально)</summary>

Если хотите установить зависимости заранее:

```bash
apt-get update
apt-get install -y jq curl dnsutils netcat-openbsd
```
</details>

### 3. Проверка структуры

```bash
ls -lh
```

Должны быть:
```
common-functions.sh
level-1-basic-dpi.sh     ✅ Level 1
level-2-cdn-bypass.sh    ✅ Level 2
test-suite.sh
rollback.sh
configs/
  └── cloudflare-domains.txt
README.md
QUICKSTART.md
```

---

## 🚀 Использование

### Level 1: Basic DPI Bypass

Базовый обход DPI фильтрации провайдеров РФ.

#### Что делает Level 1?

1. **Fragment (фрагментация пакетов)**
   - Режет TLS Client Hello на куски 100-200 байт
   - Интервал между фрагментами 10-20 мс
   - DPI не видит полное доменное имя

2. **TCP оптимизации**
   - TCP Fast Open (быстрый старт соединения)
   - Keep-Alive каждые 30 секунд
   - Packet marking (метка 255)

3. **Routing правила**
   - Порты 80, 443 (HTTP/HTTPS)
   - Стратегия: IPIfNonMatch

#### Применение

```bash
# Предпросмотр изменений (dry-run)
./level-1-basic-dpi.sh --dry-run

# Применить с подробным выводом
./level-1-basic-dpi.sh --verbose

# Применить без тестов (быстрее)
./level-1-basic-dpi.sh --skip-tests

# Обычное применение
./level-1-basic-dpi.sh
```

#### Пример вывода

```
==================================================
🔧 Level 1: Basic DPI Bypass
==================================================

[ℹ] Running preflight checks...
[✓] Root access confirmed
[✓] x-ui service is running
[✓] Configuration file found and valid

[ℹ] 📦 Creating backup...
[✓] Backup created: /root/3x-ui-backups/config-2025-10-23-14-30-00.json

[ℹ] 🔨 Applying Level 1 configuration...

[+] Fragment settings added:
[+]   - packets: tlshello
[+]   - length: 100-200 bytes
[+]   - interval: 10-20 ms

[+] TCP optimizations added:
[+]   - tcpFastOpen: true
[+]   - tcpKeepAliveInterval: 30s
[+]   - mark: 255

[✓] Configuration applied successfully

[ℹ] 🔄 Restarting x-ui service...
[✓] x-ui service restarted successfully

[ℹ] 🧪 Running connectivity tests...
[✓] Google: HTTP 200 OK (45ms)
[✓] Discord: HTTP 200 OK (67ms)
[✓] YouTube: HTTP 200 OK (89ms)

==================================================
✅ LEVEL 1 APPLIED SUCCESSFULLY
==================================================

🔄 Next Steps:
  1. Test from your client using v2Ray with your VLESS key
  2. Check access to Discord, YouTube, Google
  3. If stable after 5-10 minutes, proceed to Level 2

⚠️  Rollback Command (if needed):
  /root/x-ui-tuning/rollback.sh /root/3x-ui-backups/config-2025-10-23-14-30-00.json

==================================================
```

#### Тестирование с клиента

После применения Level 1:

1. **Откройте v2Ray клиент** (v2rayN, v2rayNG, Qv2ray)
2. **Используйте ваш существующий VLESS ключ** (не меняется!)
3. **Подключитесь к серверу**
4. **Протестируйте доступ:**
   - https://discord.com
   - https://www.youtube.com
   - https://google.com

5. **Если работает стабильно 5-10 минут**, можно переходить к Level 2 (когда будет готов)

#### Если Level 1 не работает

1. **Проверьте логи сервиса:**
   ```bash
   journalctl -u x-ui -n 50 --no-pager
   ```

2. **Проверьте статус:**
   ```bash
   systemctl status x-ui
   ```

3. **Сделайте откат:**
   ```bash
   ./rollback.sh /root/3x-ui-backups/config-<timestamp>.json
   ```

---

### Level 2: CDN Bypass

Обход блокировок CDN-провайдеров (Cloudflare, DigitalOcean, Akamai) и оптимизация для голосовых/видео сервисов.

#### Что делает Level 2?

**ВАЖНО:** Level 2 - это **кумулятивная** конфигурация. Он включает ВСЕ настройки Level 1 + добавляет новые оптимизации.

1. **Все настройки Level 1 (сохраняются)**
   - Fragment: 100-200 байт, 10-20 мс
   - TCP Fast Open, Keep-Alive 30s
   - Routing для 80, 443

2. **CDN-оптимизированная фрагментация (NEW)**
   - Более агрессивная фрагментация: 50-150 байт
   - Более быстрый интервал: 5-15 мс
   - Keep-Alive: 15 секунд
   - Для CDN трафика (Cloudflare, YouTube, Discord)

3. **Cloudflare специальные порты (NEW)**
   - Порты: 2053, 2083, 2087, 2096, 8443
   - Роутинг через cdn-direct outbound
   - Обход блокировок Cloudflare AS13335

4. **Cloudflare домены (NEW)**
   - ~30 доменов Cloudflare
   - cloudflare.com, cloudflare.net, 1.1.1.1
   - cloudflarestream.com, workers.dev
   - Роутинг через cdn-direct outbound

5. **Discord UDP оптимизация (NEW)**
   - UDP порты 19294-19344 (голосовые каналы)
   - Специальный outbound для UDP
   - Без фрагментации (UDP не поддерживает)

6. **Routing стратегия**
   - IPIfNonMatch (предпочитает IP)
   - 4 правила роутинга:
     - HTTP/HTTPS (80, 443) → direct
     - CF порты (2053, 2083, 2087, 2096, 8443) → cdn-direct
     - CF домены (~30 доменов) → cdn-direct
     - Discord UDP (19294-19344) → discord-udp

#### Применение

```bash
# Предпросмотр изменений
./level-2-cdn-bypass.sh --dry-run

# Применить с подробным выводом
./level-2-cdn-bypass.sh --verbose

# Применить без тестов (быстрее)
./level-2-cdn-bypass.sh --skip-tests

# Обычное применение
./level-2-cdn-bypass.sh
```

#### Пример вывода

```
==================================================
🔧 Level 2: CDN Bypass (Cloudflare, Discord, YouTube)
==================================================

[ℹ] Running preflight checks...
[✓] Root access confirmed
[✓] All dependencies already installed
[✓] x-ui service is running
[✓] Cloudflare domains file found
[✓] Configuration file found and valid

[ℹ] 📦 Creating backup...
[✓] Backup created: /root/3x-ui-backups/config-2025-10-24-10-20-00.json

[ℹ] 🔨 Applying Level 2 configuration...

[+] ✓ Level 1 settings applied (cumulative):
[+]   - Fragment: 100-200 bytes, 10-20ms
[+]   - TCP Fast Open, Keep-Alive: 30s
[+]   - Ports: 80, 443

[+] ✓ Level 2 CDN optimizations added:
[+]   - CDN fragment: 50-150 bytes, 5-15ms (aggressive)
[+]   - Cloudflare ports: 2053, 2083, 2087, 2096, 8443
[+]   - Cloudflare domains: ~30 domains
[+]   - Discord UDP: 19294-19344

[✓] Configuration applied successfully

[ℹ] 🔄 Restarting x-ui service...
[✓] x-ui service restarted successfully

[ℹ] 🧪 Running Level 2 connectivity tests...
[✓] Google: HTTP 200 OK (42ms)
[✓] Cloudflare: HTTP 200 OK (38ms)
[✓] Discord: HTTP 200 OK (56ms)
[✓] YouTube: HTTP 200 OK (71ms)
[✓] DNS (discord.com): Resolved (8ms)
[✓] DNS (cloudflare.com): Resolved (6ms)

==================================================
✅ LEVEL 2 APPLIED SUCCESSFULLY
==================================================

📊 Configuration Changes Applied (Level 1 + Level 2)

✓ LEVEL 1 SETTINGS (INCLUDED):
  - Fragment: 100-200 bytes, 10-20ms interval
  - TCP Fast Open: ENABLED
  - Keep-Alive: 30 seconds
  - Ports: 80, 443 (HTTP/HTTPS)

✓ LEVEL 2 ADDITIONS (NEW):
  CDN-Optimized Fragmentation:
    - Fragment: 50-150 bytes (more aggressive)
    - Interval: 5-15ms (faster)
    - Keep-Alive: 15 seconds

  Cloudflare Special Ports:
    - 2053, 2083, 2087, 2096, 8443
    - Uses cdn-direct outbound

  Cloudflare Domains:
    - ~30 Cloudflare domains routed
    - cloudflare.com, cloudflare.net, etc.

  Discord UDP Voice:
    - Ports: 19294-19344
    - Optimized for voice traffic

Domain Strategy:
  - IPIfNonMatch (prefer IP routing)

🔄 Next Steps:
  1. Test from your client using v2Ray with your VLESS key
  2. IMPORTANT: Test Discord voice calls (UDP 19294-19344)
  3. IMPORTANT: Test YouTube video playback
  4. Check Cloudflare services (cloudflare.com, 1.1.1.1)
  5. If stable after 10-15 minutes, Level 2 is working
  6. If issues occur, use rollback command below

Note: Level 2 is more aggressive and may take longer to stabilize

⚠️  Rollback Command (if needed):
  /root/x-ui-tuning/rollback.sh /root/3x-ui-backups/config-2025-10-24-10-20-00.json

==================================================
```

#### Тестирование с клиента

После применения Level 2:

1. **Откройте v2Ray клиент** (не меняйте настройки!)
2. **Подключитесь к серверу**
3. **Протестируйте Discord voice:**
   - Откройте Discord
   - Зайдите в голосовой канал
   - Проверьте качество связи
   - Проверьте стабильность (5-10 минут разговора)

4. **Протестируйте YouTube:**
   - Откройте https://www.youtube.com
   - Включите видео в HD (1080p) или 4K
   - Проверьте скорость загрузки (должно быть без буферизации)
   - Перемотайте видео (должно быстро загружаться)

5. **Протестируйте Cloudflare:**
   - Откройте https://cloudflare.com
   - Откройте https://1.1.1.1
   - Проверьте скорость загрузки страниц

6. **Дайте время на стабилизацию:**
   - Level 2 более агрессивен
   - Может занять 10-15 минут для стабилизации
   - Не переживайте если первые 2-3 минуты есть микро-лаги

#### Переключение между уровнями

**Level 2 включает Level 1!** Вы НЕ можете "переключиться" между ними - Level 2 это Level 1 + дополнения.

Если нужно вернуться к Level 1 only:

```bash
# 1. Откатитесь к бэкапу ДО Level 2
./rollback.sh /root/3x-ui-backups/config-<timestamp-before-level2>.json

# 2. Примените Level 1 снова
./level-1-basic-dpi.sh
```

#### Если Level 2 не работает

1. **Проверьте логи:**
   ```bash
   journalctl -u x-ui -n 100 --no-pager
   ```

2. **Проверьте статус:**
   ```bash
   systemctl status x-ui
   ```

3. **Проверьте конфигурацию:**
   ```bash
   cat /usr/local/x-ui/bin/xray-linux-amd64/config.json | jq .
   ```

4. **Сделайте откат к Level 1:**
   ```bash
   # Найдите бэкап ДО Level 2
   ls -lah /root/3x-ui-backups/

   # Откатитесь
   ./rollback.sh /root/3x-ui-backups/config-<timestamp>.json
   ```

5. **Если Level 1 работал, но Level 2 нет:**
   - Возможно, ваш провайдер особенно агрессивно блокирует CDN
   - Вернитесь к Level 1
   - Создайте Issue с описанием провайдера и региона
   - Дождитесь Level 3 (более хардкорный режим)

#### Ограничения Level 2

**Что работает:**
- ✅ Discord voice (стабильно)
- ✅ YouTube HD/4K видео (быстро)
- ✅ Cloudflare сервисы
- ✅ Google Meet видеоконференции
- ✅ Все из Level 1 (улучшено)

**Что может не работать:**
- ⚠️ Игры (требуется Level 3)
- ⚠️ Некоторые региональные CDN (DigitalOcean, Akamai)
- ⚠️ Сложные поддомены 4+ уровней (требуется Level 3)

**Если Level 2 недостаточно** → Ждите Level 3 (запланировано)

---

## 🧪 Тестирование

### Автоматические тесты

Используйте `test-suite.sh` для проверки доступности сервисов:

```bash
# Запустить все тесты
./test-suite.sh

# Только Level 1 тесты
./test-suite.sh 1

# Только DNS тесты
./test-suite.sh dns

# С подробным выводом
./test-suite.sh --verbose all
```

### Ручное тестирование

#### С сервера (локально)

```bash
# HTTP тесты
curl -I https://google.com
curl -I https://discord.com
curl -I https://youtube.com

# DNS тесты
dig discord.com @8.8.8.8
dig youtube.com @8.8.8.8

# TCP тесты
nc -zv discord.com 443
nc -zv youtube.com 443
```

#### С клиента (через VPN)

1. Подключитесь через v2Ray
2. Откройте браузер
3. Проверьте сайты:
   - https://discord.com (должна открыться страница)
   - https://www.youtube.com (должны грузиться видео)
   - https://dnsleaktest.com (проверка DNS)
   - https://ipleak.net (проверка IP)

### Что считается успехом?

**Level 1:**
- ✅ Сайты открываются
- ✅ Discord подключается
- ✅ YouTube видео начинают грузиться (может быть медленно)
- ✅ Latency < 100ms

**Частичный успех (норма для Level 1):**
- ⚠️ YouTube видео грузятся медленно → Используйте Level 2!
- ⚠️ Discord voice каналы не работают → Используйте Level 2!
- ⚠️ Некоторые CDN сервисы недоступны → Используйте Level 2!

**Level 2:**
- ✅ YouTube HD/4K без буферизации
- ✅ Discord voice стабильно работает
- ✅ Cloudflare сервисы доступны
- ✅ Все из Level 1 работает лучше

---

## 🔄 Откат изменений

### Автоматический откат

```bash
# Список доступных бэкапов
ls -lh /root/3x-ui-backups/

# Откат на конкретный бэкап
./rollback.sh /root/3x-ui-backups/config-2025-10-23-14-30-00.json

# Откат без подтверждения
./rollback.sh --force /root/3x-ui-backups/config-2025-10-23-14-30-00.json

# Откат без перезапуска сервиса (только замена файла)
./rollback.sh --no-restart /root/3x-ui-backups/config-2025-10-23-14-30-00.json
```

### Ручной откат

```bash
# 1. Найти бэкап
ls -lh /root/3x-ui-backups/

# 2. Скопировать бэкап
cp /root/3x-ui-backups/config-<timestamp>.json /usr/local/x-ui/bin/xray-linux-amd64/config.json

# 3. Перезапустить сервис
systemctl restart x-ui

# 4. Проверить статус
systemctl status x-ui
```

---

## 🔧 Troubleshooting

### Проблема: "x-ui service not running"

**Решение:**
```bash
# Запустить сервис
systemctl start x-ui

# Проверить статус
systemctl status x-ui

# Если не запускается, проверить логи
journalctl -u x-ui -n 100 --no-pager
```

### Проблема: "Configuration file not found"

**Решение:**
```bash
# Найти конфиг вручную
find /usr/local/x-ui -name "config.json"
find /etc/x-ui -name "config.json"

# Обновить путь в common-functions.sh (переменная X_UI_CONFIG_PATHS)
```

### Проблема: "Invalid JSON in configuration file"

**Решение:**
```bash
# Проверить JSON вручную
jq . /usr/local/x-ui/bin/xray-linux-amd64/config.json

# Если ошибка, восстановить из бэкапа
./rollback.sh /root/3x-ui-backups/config-<последний-рабочий>.json
```

### Проблема: "Missing dependencies: jq"

**Решение:**
```bash
# Установить зависимости
apt-get update
apt-get install -y jq curl dnsutils netcat-openbsd
```

### Проблема: Сервер после Level 1 не работает

**Симптомы:**
- Клиент не может подключиться
- Соединение обрывается
- Timeout при подключении

**Решение:**

1. **Проверить логи сервиса:**
   ```bash
   journalctl -u x-ui -n 50 --no-pager
   ```

2. **Откатить изменения:**
   ```bash
   ./rollback.sh /root/3x-ui-backups/config-<timestamp>.json
   ```

3. **Проверить что откат помог:**
   - Подключиться с клиента
   - Если работает, значит проблема была в Level 1

4. **Попробовать dry-run для диагностики:**
   ```bash
   ./level-1-basic-dpi.sh --dry-run --verbose
   ```

### Проблема: Тесты падают с "All tests failed"

**Это нормально** если вы запускаете тесты с сервера!

Тесты с сервера проверяют только что конфиг валиден и сервис запустился.

**Главное:** тестировать с клиента через v2Ray подключение.

### Проблема: YouTube видео не грузятся после Level 1

**Это ожидаемо!** Level 1 делает только базовый обход.

YouTube требует Level 2 (CDN bypass) который будет добавлен позже.

**Временное решение:**
- Discord должен работать
- Google должен работать
- YouTube страницы должны открываться (но видео могут не грузиться)

---

## 📈 Масштабирование

### Несколько серверов

Для управления несколькими серверами 3x-ui:

```bash
# Создать список серверов
cat > servers.txt << EOF
server1.example.com
server2.example.com
server3.example.com
EOF

# Запустить на всех серверах
while read server; do
    echo "=== Configuring $server ==="
    ssh root@$server 'bash -s' < level-1-basic-dpi.sh
done < servers.txt
```

### Ansible playbook (будущее)

Планируется создание Ansible playbook для автоматизации:

```yaml
# playbook.yml (пример структуры)
- hosts: vpn_servers
  tasks:
    - name: Upload x-ui-tuning scripts
      copy:
        src: ./x-ui-tuning/
        dest: /root/x-ui-tuning/

    - name: Apply Level 1
      shell: /root/x-ui-tuning/level-1-basic-dpi.sh
```

### CI/CD интеграция

Для автоматического применения при деплое нового сервера:

```bash
# В вашем CI/CD pipeline
- name: Configure DPI bypass
  run: |
    scp -r ./x-ui-tuning root@${{ secrets.SERVER_IP }}:/root/
    ssh root@${{ secrets.SERVER_IP }} '/root/x-ui-tuning/level-1-basic-dpi.sh'
```

---

## 📚 Ссылки

### Основные источники

- **GitHub Issue #5704** (Oct 23, 2025)
  https://github.com/Flowseal/zapret-discord-youtube/issues/5704

- **ntc.party обсуждение**
  https://ntc.party/t/блокировка-cloudflare-ovh-hetzner-digitalocean-09062025-xxxxxxxx/17013/173

- **V3nilla IPSets для обхода в РФ**
  https://github.com/V3nilla/IPSets-For-Bypass-in-Russia

- **DPI тест**
  https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/

### Репозитории Zapret

- https://github.com/Flowseal/zapret-discord-youtube
- https://github.com/ankddev/zapret-discord-youtube
- https://github.com/youtubediscord/zapret

### Дополнительные инструменты

- **AmneziaWG** (альтернатива для мобильных)
  https://github.com/vayulqq/amneziawg-windows-client

- **ProtonVPN Converter** (генератор пейлоадов)
  https://protontestguide.github.io/ProtonVPN-Converter/

---

## 📝 Changelog

### v1.0 (23 октября 2025)

**Добавлено:**
- Level 1: Basic DPI Bypass
  - Fragment для TLS Client Hello
  - TCP оптимизации
  - Базовые routing правила
- common-functions.sh с общими утилитами
- test-suite.sh для автоматического тестирования
- rollback.sh для отката конфигурации
- Подробная документация

**Планируется:**
- Level 2: CDN Bypass (Cloudflare, DO, Akamai)
- Level 3: Advanced (хардкорный режим, игровые порты)

---

## 🤝 Вклад

Если у вас есть предложения по улучшению или вы нашли баг:

1. Создайте Issue
2. Опишите проблему или предложение
3. Приложите логи если это баг

---

## ⚖️ Лицензия

Эти скрипты предоставляются "как есть" для образовательных целей.

**Disclaimer:** Использование этих скриптов для обхода блокировок может нарушать законы вашей страны. Автор не несет ответственности за использование.

---

## 📞 Поддержка

Для вопросов и обсуждений используйте Issues в репозитории.

**Удачной настройки! 🚀**
