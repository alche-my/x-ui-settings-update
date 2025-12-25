# ByeDPI Шпаргалка - Быстрые команды

## 🚀 Установка

```bash
# Базовая установка
sudo ./setup-byedpi-proxy.sh \
  --non-ru-ip 1.2.3.4 \
  --non-ru-uuid "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# С дополнительными параметрами
sudo ./setup-byedpi-proxy.sh \
  --non-ru-ip 1.2.3.4 \
  --non-ru-port 8443 \
  --non-ru-uuid "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  --byedpi-port 2080

# Интерактивный режим
sudo ./setup-byedpi-proxy.sh
```

## 🔧 Управление сервисом

```bash
# Запустить
sudo systemctl start byedpi

# Остановить
sudo systemctl stop byedpi

# Перезапустить
sudo systemctl restart byedpi

# Статус
sudo systemctl status byedpi

# Включить автозапуск
sudo systemctl enable byedpi

# Отключить автозапуск
sudo systemctl disable byedpi
```

## 📊 Логи и мониторинг

```bash
# Логи в реальном времени
sudo journalctl -u byedpi -f

# Последние 50 строк
sudo journalctl -u byedpi -n 50

# Логи за последний час
sudo journalctl -u byedpi --since "1 hour ago"

# Логи с ошибками
sudo journalctl -u byedpi -p err

# Все логи без пагинации
sudo journalctl -u byedpi --no-pager
```

## ✅ Проверка работы

```bash
# Проверить, что SOCKS5 работает
curl --socks5 127.0.0.1:1080 https://www.google.com

# Проверить, что порт открыт
sudo netstat -tlnp | grep 1080

# Или через ss
sudo ss -tlnp | grep 1080

# Проверить процесс
ps aux | grep ciadpi

# Проверить подключения
sudo lsof -i :1080
```

## 🔧 Редактирование конфигурации

```bash
# Открыть systemd сервис
sudo nano /etc/systemd/system/byedpi.service

# После изменений - перезагрузить
sudo systemctl daemon-reload
sudo systemctl restart byedpi
```

## ⚙️ Популярные конфигурации ByeDPI

### Стандартная (по умолчанию)
```bash
ExecStart=/usr/local/bin/ciadpi --ip 127.0.0.1 --port 1080 --disorder 1 --split 2 --tlsrec 1+s --auto=torst
```

### Для мобильных операторов
```bash
ExecStart=/usr/local/bin/ciadpi --port 1080 --split 2 --disorder 1 --fake
```

### Для МТС
```bash
ExecStart=/usr/local/bin/ciadpi --port 1080 --disorder 1 --split 3 --fake --ttl 8
```

### Для Билайн
```bash
ExecStart=/usr/local/bin/ciadpi --port 1080 --split-pos 2 --disorder 2 --tlsrec 1+s
```

### Для Мегафон
```bash
ExecStart=/usr/local/bin/ciadpi --port 1080 --split 2 --disorder 1 --fake --auto=torst
```

### Для Ростелеком
```bash
ExecStart=/usr/local/bin/ciadpi --port 1080 --tlsrec 1+s --split-pos 2 --disorder 1
```

### Для МГТС
```bash
ExecStart=/usr/local/bin/ciadpi --port 1080 --split 3 --tlsrec 1+s
```

### Агрессивный режим
```bash
ExecStart=/usr/local/bin/ciadpi --port 1080 --disorder 3 --split 3 --tlsrec 1+s --fake --ttl 5 --auto=torst
```

### Минимальный (для теста)
```bash
ExecStart=/usr/local/bin/ciadpi --port 1080
```

## 🗑️ Удаление

```bash
# Полное удаление
sudo ./setup-byedpi-proxy.sh --uninstall

# Или вручную
sudo systemctl stop byedpi
sudo systemctl disable byedpi
sudo rm /etc/systemd/system/byedpi.service
sudo rm /usr/local/bin/ciadpi
sudo rm -rf /opt/byedpi
sudo systemctl daemon-reload
```

## 🔍 Диагностика проблем

```bash
# Проверить, что порт не занят
sudo lsof -i :1080

# Убить процесс на порту
sudo lsof -ti:1080 | xargs kill -9

# Проверить firewall
sudo ufw status
sudo iptables -L -n -v

# Проверить доступность Non-RU сервера
ping NON-RU-IP
telnet NON-RU-IP 443

# Тест через ByeDPI к Non-RU серверу
curl -v --socks5 127.0.0.1:1080 https://NON-RU-IP:443
```

## 📝 3x-ui команды

```bash
# Перезапустить 3x-ui
sudo systemctl restart x-ui

# Статус 3x-ui
sudo systemctl status x-ui

# Логи 3x-ui
sudo journalctl -u x-ui -f

# Открыть панель 3x-ui (найти порт)
sudo x-ui

# Сбросить пароль 3x-ui
sudo x-ui reset

# Обновить 3x-ui
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

## 📂 Важные файлы и пути

```bash
# Systemd сервис
/etc/systemd/system/byedpi.service

# Бинарный файл ByeDPI
/usr/local/bin/ciadpi

# Исходники ByeDPI
/opt/byedpi/

# Конфигурация Xray
/root/byedpi-config/xray-outbound-config.json

# Инструкции
/root/byedpi-config/SETUP-INSTRUCTIONS.md

# Логи ByeDPI
journalctl -u byedpi

# База данных 3x-ui
/etc/x-ui/x-ui.db

# Конфигурация Xray (3x-ui)
/usr/local/x-ui/bin/config.json
```

## 🧪 Тестирование разных параметров

```bash
# Тест вручную (без systemd)
sudo /usr/local/bin/ciadpi --port 1080 --disorder 1 --split 2

# С выводом в консоль
sudo /usr/local/bin/ciadpi --port 1080 --disorder 1 --split 2 -v

# Тест подключения
curl -x socks5://127.0.0.1:1080 https://www.google.com

# Тест с таймаутом
timeout 5 curl -x socks5://127.0.0.1:1080 https://www.google.com
```

## 📊 Мониторинг производительности

```bash
# CPU и память ByeDPI
ps aux | grep ciadpi

# Подробная статистика
top -p $(pидof ciadpi)

# Сетевая активность
sudo iftop -f "port 1080"

# Статистика соединений
sudo netstat -anp | grep 1080 | wc -l
```

## 🔄 Бэкап и восстановление

```bash
# Бэкап конфигурации
sudo cp /etc/systemd/system/byedpi.service /root/byedpi.service.backup

# Бэкап конфигурации Xray
sudo cp /root/byedpi-config/xray-outbound-config.json /root/xray-config.backup.json

# Восстановление
sudo cp /root/byedpi.service.backup /etc/systemd/system/byedpi.service
sudo systemctl daemon-reload
sudo systemctl restart byedpi
```

## 🚨 Аварийное восстановление

```bash
# Если ByeDPI сломался - откатиться
sudo systemctl stop byedpi
sudo systemctl disable byedpi

# Перезапустить 3x-ui без ByeDPI
# (удалить proxySettings из конфигурации Xray)
sudo systemctl restart x-ui

# Переустановить ByeDPI
cd /home/user/x-ui-settings-update
sudo ./setup-byedpi-proxy.sh --uninstall
sudo ./setup-byedpi-proxy.sh --non-ru-ip X.X.X.X --non-ru-uuid "UUID"
```

## 💡 Полезные трюки

```bash
# Автоматический перезапуск при падении (уже в systemd)
# Но можно добавить watchdog:
# WatchdogSec=30s

# Запустить в debug режиме
sudo /usr/local/bin/ciadpi --port 1080 --disorder 1 --split 2 -v

# Посмотреть все параметры
/usr/local/bin/ciadpi --help

# Проверить версию
/usr/local/bin/ciadpi --version || echo "No version flag"
```

## 📚 Дополнительные ресурсы

- Логи: `journalctl -u byedpi -f`
- GitHub: https://github.com/hufrea/byedpi
- Issues: https://github.com/hufrea/byedpi/issues
