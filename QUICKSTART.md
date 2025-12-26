# ByeDPI + 3x-ui: Быстрый старт

## ⚡ Установка (1 команда)

```bash
curl -fsSL https://raw.githubusercontent.com/alche-my/x-ui-settings-update/claude/byedpi-3xui-compatibility-ihDW2/install-byedpi-3xui.sh -o install-byedpi-3xui.sh && chmod +x install-byedpi-3xui.sh && sudo ./install-byedpi-3xui.sh
```

## 📋 Что спросит скрипт?

1. **Количество Non-RU серверов** (например: 3)

2. **Для каждого сервера:**
   - vless:// ссылку (просто вставьте - всё распарсится автоматически!)

3. **Стратегию балансировки** (если серверов >1):
   - 1 = random (рекомендуется)
   - 2 = leastPing
   - 3 = leastLoad

**Всё!** IP, UUID, Public Key, SNI, fingerprint, service name - всё автоматически извлекается из vless:// ссылки! 🎯

### Пример vless:// ссылки

```
vless://206b7a77-6295-4f2b-999a-125db3982084@45.12.135.9:443?type=grpc&security=reality&pbk=Q_KUAYTAc05sE4CbLnq9vznhan1o4zzAsUwTHPVc9nM&fp=edge&sni=github.com&sid=6d12731746e56ad2&serviceName=svc#Server1
```

Скрипт автоматически извлечет:
- UUID: `206b7a77-6295-4f2b-999a-125db3982084`
- IP: `45.12.135.9`
- Порт: `443`
- Тип: `grpc`
- Безопасность: `reality`
- Public Key: `Q_KUAYTAc05sE4CbLnq9vznhan1o4zzAsUwTHPVc9nM`
- Fingerprint: `edge`
- SNI: `github.com`
- Short ID: `6d12731746e56ad2`
- Service Name: `svc`

## ✅ После установки

1. **Скопируйте JSON:**
   ```bash
   cat /root/byedpi-config/3xui-full-config.json
   ```

2. **Откройте 3x-ui панель** в браузере

3. **Перейдите:** Panel Settings → Xray Configs

4. **Замените весь JSON** на скопированный

5. **Save → Restart Xray**

6. ⚠️ **Добавьте UUID на Non-RU серверы!**

## 🔍 Проверка

```bash
# ByeDPI работает?
sudo systemctl status byedpi

# 3x-ui работает?
sudo systemctl status x-ui

# Логи
sudo journalctl -u x-ui -f
```

## 🎯 Схема работы

```
Клиенты → RU-сервер (3x-ui) → ByeDPI → Балансер → {
    Non-RU-1
    Non-RU-2
    Non-RU-3
} → Интернет
```

## ⏱️ Время

- Установка: 2-3 мин
- Настройка: 1 мин (copy-paste)
- **Всего: ~5 минут**

---

📚 [Полная документация](README-BYEDPI-SETUP.md) | 🔧 [Решение проблем](README-BYEDPI-SETUP.md#-решение-проблем)
