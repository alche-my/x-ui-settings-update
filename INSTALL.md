# Быстрая установка через curl

## 🚀 Установка ByeDPI одной командой

### Вариант 1: Скачать и запустить интерактивно

```bash
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/setup-byedpi-proxy.sh -o setup-byedpi-proxy.sh && \
chmod +x setup-byedpi-proxy.sh && \
sudo ./setup-byedpi-proxy.sh
```

Скрипт спросит IP, UUID, порты.

### Вариант 2: Установка с параметрами

```bash
# Скачать скрипт
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/setup-byedpi-proxy.sh -o setup-byedpi-proxy.sh && \
chmod +x setup-byedpi-proxy.sh

# Сгенерировать UUID
UUID=$(./setup-byedpi-proxy.sh --generate-uuid)

# Установить с параметрами
sudo ./setup-byedpi-proxy.sh \
  --non-ru-ip 185.1.2.3 \
  --non-ru-uuid "$UUID"
```

### Вариант 3: Прямой запуск (без сохранения файла)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/setup-byedpi-proxy.sh)
```

**Внимание:** Требуется sudo, поэтому лучше сначала скачать и проверить скрипт.

---

## 🔧 Генератор балансировщика

### Скачать генератор балансировщика

```bash
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/generate-balancer-config.sh -o generate-balancer-config.sh && \
chmod +x generate-balancer-config.sh && \
./generate-balancer-config.sh
```

---

## 📦 Скачать все файлы одной командой

```bash
# Создать директорию
mkdir -p ~/byedpi-setup && cd ~/byedpi-setup

# Скачать все скрипты
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/setup-byedpi-proxy.sh -o setup-byedpi-proxy.sh && \
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/generate-balancer-config.sh -o generate-balancer-config.sh && \
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/README-byedpi.md -o README-byedpi.md && \
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/README-balancer.md -o README-balancer.md && \
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/QUICKSTART-byedpi.md -o QUICKSTART-byedpi.md && \
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/CHEATSHEET-byedpi.md -o CHEATSHEET-byedpi.md

# Сделать скрипты исполняемыми
chmod +x setup-byedpi-proxy.sh generate-balancer-config.sh

# Показать файлы
ls -lh
```

---

## 🎯 Рекомендуемый workflow

### Для одного сервера:

```bash
# 1. Скачать скрипт
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/setup-byedpi-proxy.sh -o setup-byedpi-proxy.sh
chmod +x setup-byedpi-proxy.sh

# 2. Запустить интерактивно
sudo ./setup-byedpi-proxy.sh

# 3. Прочитать инструкцию
cat /root/byedpi-config/SETUP-INSTRUCTIONS.md

# 4. Применить конфиг в 3x-ui и перезапустить
sudo systemctl restart x-ui
```

### Для балансировки (несколько серверов):

```bash
# 1. Скачать оба скрипта
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/setup-byedpi-proxy.sh -o setup-byedpi-proxy.sh
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/generate-balancer-config.sh -o generate-balancer-config.sh
chmod +x setup-byedpi-proxy.sh generate-balancer-config.sh

# 2. Установить ByeDPI
sudo ./setup-byedpi-proxy.sh

# 3. Создать конфиг балансировщика
./generate-balancer-config.sh

# 4. Прочитать инструкцию
cat /root/byedpi-config/BALANCER-SETUP.md

# 5. Применить конфиг в 3x-ui
cat /root/byedpi-config/xray-balancer-config.json
# Скопировать в 3x-ui → Xray Config

# 6. Перезапустить
sudo systemctl restart x-ui
```

---

## ⚡ One-liner для продакшена

### Автоматическая установка с вашими параметрами:

```bash
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/setup-byedpi-proxy.sh | \
sudo bash -s -- \
  --non-ru-ip 185.1.2.3 \
  --non-ru-uuid "ваш-uuid-здесь" \
  --non-interactive
```

**Замените:**
- `185.1.2.3` → IP вашего Non-RU сервера
- `ваш-uuid-здесь` → ваш реальный UUID

---

## 🔐 Безопасность

**Важно:** Всегда проверяйте скрипты перед запуском с sudo!

```bash
# Скачать и просмотреть перед запуском
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/setup-byedpi-proxy.sh -o setup-byedpi-proxy.sh

# Прочитать скрипт
less setup-byedpi-proxy.sh

# Или открыть в редакторе
nano setup-byedpi-proxy.sh

# Если все ОК - запустить
chmod +x setup-byedpi-proxy.sh
sudo ./setup-byedpi-proxy.sh
```

---

## 🆘 Решение проблем

### curl: command not found

```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y curl

# CentOS/RHEL
sudo yum install -y curl
```

### Permission denied

```bash
# Сделать скрипт исполняемым
chmod +x setup-byedpi-proxy.sh
```

### SSL certificate problem

```bash
# Обновить сертификаты
sudo apt-get install -y ca-certificates
sudo update-ca-certificates
```

---

## 📚 Дополнительные ресурсы

- **GitHub репозиторий:** https://github.com/alche-my/x-ui-settings-update
- **ByeDPI:** https://github.com/hufrea/byedpi
- **3x-ui:** https://github.com/MHSanaei/3x-ui

---

## 💡 Полезные команды

```bash
# Показать версию скрипта
./setup-byedpi-proxy.sh --help | head -1

# Сгенерировать UUID
./setup-byedpi-proxy.sh --generate-uuid

# Проверить статус ByeDPI
sudo systemctl status byedpi

# Удалить ByeDPI
sudo ./setup-byedpi-proxy.sh --uninstall
```
