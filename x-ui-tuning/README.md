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
Level 1: Basic DPI Bypass
    ↓
    Fragment + TCP optimization + Basic routing
    ↓
    Тест: Google, Discord, YouTube
    ↓
Level 2: CDN Bypass (планируется)
    ↓
    Cloudflare domains + IP sets + CF proxy strategy
    ↓
    Тест: Discord voice, YouTube video, CDN services
    ↓
Level 3: Advanced (планируется)
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

```bash
# Установить все зависимости
apt-get update
apt-get install -y jq curl dnsutils netcat-openbsd
```

Список зависимостей:
- `jq` - для работы с JSON конфигурациями
- `curl` - для HTTP тестов
- `dig` (dnsutils) - для DNS тестов
- `nc` (netcat) - для TCP тестов
- `systemctl` - для управления сервисами (обычно встроен)

---

## 📦 Установка

### 1. Клонирование репозитория

```bash
cd /root
git clone <repository-url> x-ui-tuning
cd x-ui-tuning
```

Или скопируйте файлы вручную на сервер.

### 2. Установка зависимостей

```bash
apt-get update
apt-get install -y jq curl dnsutils netcat-openbsd
```

### 3. Проверка прав

```bash
chmod +x *.sh
```

### 4. Проверка структуры

```bash
ls -lh
```

Должны быть:
```
common-functions.sh
level-1-basic-dpi.sh
test-suite.sh
rollback.sh
configs/
  └── cloudflare-domains.txt
README.md
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
- ⚠️ YouTube видео грузятся медленно (это решит Level 2)
- ⚠️ Discord voice каналы не работают (это решит Level 2)
- ⚠️ Некоторые CDN сервисы недоступны (это решит Level 2)

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
