# Quick Start Guide

Быстрая инструкция по применению Level 1 для обхода блокировок в РФ.

## 🚀 Быстрый старт (5 минут)

### 1. Подключитесь к серверу

```bash
ssh root@your-server-ip
```

### 2. Установите зависимости

```bash
apt-get update && apt-get install -y jq curl dnsutils
```

### 3. Загрузите скрипты на сервер

**Вариант A: Если репозиторий доступен**
```bash
cd /root
git clone <repository-url> x-ui-tuning
cd x-ui-tuning
```

**Вариант B: Ручная загрузка**
```bash
# С вашего локального компьютера
scp -r ./x-ui-tuning root@your-server-ip:/root/
```

### 4. Сделайте скрипты исполняемыми (если нужно)

```bash
cd /root/x-ui-tuning
chmod +x *.sh
```

### 5. Примените Level 1

```bash
./level-1-basic-dpi.sh
```

### 6. Проверьте с клиента

1. Откройте v2Ray клиент на вашем компьютере
2. Используйте ваш существующий VLESS ключ (не меняется!)
3. Подключитесь
4. Проверьте доступ:
   - https://discord.com
   - https://youtube.com
   - https://google.com

## ✅ Успех!

Если сайты открываются, Level 1 работает!

## ❌ Не работает?

### Откатить изменения:

```bash
./rollback.sh /root/3x-ui-backups/config-<timestamp>.json
```

### Проверить логи:

```bash
journalctl -u x-ui -n 50
```

### Посмотреть доступные бэкапы:

```bash
ls -lh /root/3x-ui-backups/
```

## 📚 Подробная документация

Для детальной информации читайте [README.md](README.md)

## ⚠️ Важно

- Скрипты меняют только серверную конфигурацию
- Клиентский VLESS ключ не меняется
- Всегда делается бэкап перед изменениями
- Можно откатить в любой момент

## 🆘 Проблемы?

1. Проверьте что x-ui запущен: `systemctl status x-ui`
2. Проверьте логи: `journalctl -u x-ui -n 50`
3. Откатите изменения если нужно: `./rollback.sh <backup-file>`

## 📞 Поддержка

Для вопросов создайте Issue в репозитории с подробным описанием и логами.
