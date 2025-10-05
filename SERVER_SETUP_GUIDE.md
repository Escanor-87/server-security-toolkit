# 🚀 Server Security Toolkit - Полное руководство

## Быстрый старт

### 1. Установка (5 минут)

```bash
# Однострочная установка
bash <(curl -Ls https://raw.githubusercontent.com/Escanor-87/server-security-toolkit/main/install.sh)

# Или клонируйте репозиторий
git clone https://github.com/Escanor-87/server-security-toolkit.git
cd server-security-toolkit
sudo bash install.sh
```

### 2. Первый запуск

```bash
sudo sst
```

Вы увидите главное меню с цветовыми индикаторами:
- 🟢 = сервис работает
- 🟡 = сервис включён, но не запущен
- 🔴 = сервис отключён или отсутствует

### 3. Рекомендуемый порядок настройки

**Важно:** Следуйте этому порядку для безопасной настройки!

#### Шаг 1: Настройка SSH ключей
```
2. SSH Security → 1. Import/Generate SSH Keys
```
- Импортируйте существующие ключи
- Или сгенерируйте новые (они автоматически скопируются в буфер)
- Убедитесь, что ключи добавлены в `~/.ssh/authorized_keys`

#### Шаг 2: Проверка SSH доступа
**НЕ ЗАКРЫВАЙТЕ текущую SSH сессию!**

Откройте **новое** SSH соединение и проверьте, что можете войти по ключу:
```bash
ssh -i ~/.ssh/your_key root@your_server_ip
```

Если вход успешен → продолжайте. Если нет → исправьте проблему перед следующими шагами!

#### Шаг 3: Смена SSH порта
```
2. SSH Security → 2. Change SSH Port
```
- Выберите нестандартный порт (например, 23321)
- **Firewall (UFW) обновится автоматически!**
- SSH сервис перезапустится

Проверьте доступ на новом порту:
```bash
ssh -p 23321 -i ~/.ssh/your_key root@your_server_ip
```

#### Шаг 4: Настройка файрвола
```
3. Firewall Setup → 1. Basic Configuration
```
- UFW будет активирован
- SSH порт уже открыт (из предыдущего шага)
- Добавьте другие нужные порты (80, 443, и т.д.)

#### Шаг 5: Установка fail2ban
```
4. System Hardening → 1. Configure fail2ban
```
- fail2ban автоматически определит тип логирования
- Для journald-only систем конфигурация будет создана автоматически
- Банить будет после 2 неудачных попыток за 10 минут

#### Шаг 6: Отключение парольной авторизации
```
2. SSH Security → 3. Disable Password Authentication
```
**ВАЖНО:** Делайте это ТОЛЬКО после проверки входа по ключу!

- Парольная авторизация будет отключена
- Root доступ будет ограничен (только по ключу)
- После этого вход возможен ТОЛЬКО по SSH ключу

### 4. Проверка безопасности

```bash
sudo sst
# Выберите: 6. System Status
```

Вы увидите:
- ✅ Что настроено правильно
- ⚠️ Что требует внимания
- 💡 Конкретные рекомендации по исправлению

---

## Решение проблем

### Проблема: fail2ban не запускается

**Ошибка:**
```
ERROR Failed during configuration: Have not found any log file for sshd jail
```

**Решение:**

```bash
# Скачайте скрипт исправления
cd /opt/server-security-toolkit
wget https://raw.githubusercontent.com/Escanor-87/server-security-toolkit/main/fix_f2b_journald.sh
sudo bash fix_f2b_journald.sh
```

Скрипт автоматически:
1. Определит тип логирования (файлы vs journald)
2. Создаст правильную конфигурацию
3. Перезапустит fail2ban
4. Проверит работоспособность

### Проблема: Не могу войти по SSH после изменений

**Если вы заблокировали себя:**

1. **Через консоль провайдера** (VNC/Serial Console):
   ```bash
   # Восстановите SSH конфигурацию
   cd /opt/server-security-toolkit
   sudo bash main.sh
   # Выберите: 2. SSH Security → Restore SSH Config
   ```

2. **Аварийный скрипт** (если установлен):
   ```bash
   sudo bash /opt/server-security-toolkit/emergency_ssh_fix.sh
   ```

3. **Ручное восстановление**:
   ```bash
   # Откройте нужный порт в UFW
   sudo ufw allow 22/tcp
   
   # Восстановите стандартный SSH порт
   sudo sed -i 's/^Port .*/Port 22/' /etc/ssh/sshd_config
   sudo systemctl restart sshd
   
   # Включите парольную авторизацию (временно)
   sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
   sudo systemctl restart sshd
   ```

### Проблема: UFW блокирует SSH после активации

**Не должно происходить**, но если случилось:

```bash
# Через консоль провайдера
sudo ufw disable
sudo ufw allow [your_ssh_port]/tcp
sudo ufw enable
```

---

## Полезные команды

### Проверка статусов

```bash
# Статус SSH
systemctl status sshd
ss -tlnp | grep sshd  # Какой порт слушает

# Статус UFW
sudo ufw status verbose

# Статус fail2ban
sudo systemctl status fail2ban
f2b list  # Забаненные IP (алиас)
fail2ban-client status sshd  # Детальный статус

# Логи
sudo journalctl -u sshd -f  # SSH логи
sudo journalctl -u fail2ban -f  # fail2ban логи
```

### Управление fail2ban

```bash
# Список забаненных IP
f2b list
# или
fail2ban-client banned

# Разбанить IP
sudo fail2ban-client unban 1.2.3.4

# Забанить IP вручную
sudo fail2ban-client set sshd banip 1.2.3.4

# Статус конкретного jail
fail2ban-client status sshd

# Перезапуск fail2ban
sudo systemctl restart fail2ban
```

### Управление UFW

```bash
# Посмотреть правила с номерами
sudo ufw status numbered

# Удалить правило
sudo ufw delete [номер]

# Добавить правило
sudo ufw allow 80/tcp
sudo ufw allow from 1.2.3.4 to any port 22

# Сбросить все правила
sudo ufw reset
```

---

## Оптимизация безопасности

### Ужесточение fail2ban

Отредактируйте `/etc/fail2ban/jail.local`:

```ini
[DEFAULT]
bantime = 24h        # Бан на сутки вместо 1 часа
findtime = 10m
maxretry = 1         # Всего 1 попытка вместо 2

[recidive]
enabled = true
bantime = 1w         # Повторные нарушители на неделю
findtime = 1d
maxretry = 3
```

Перезапустите:
```bash
sudo systemctl restart fail2ban
```

### Дополнительные jail'ы fail2ban

```ini
# В /etc/fail2ban/jail.local добавьте:

[sshd-ddos]
enabled = true
port = ssh,[ваш_порт]
maxretry = 2
findtime = 5m
bantime = 12h

[nginx-http-auth]
enabled = true
port = http,https
logpath = %(nginx_error_log)s

[nginx-noscript]
enabled = true
port = http,https
logpath = %(nginx_access_log)s
```

### Автоматические обновления безопасности

```bash
sudo sst
# 4. System Hardening → 3. Configure Automatic Updates
```

Будут установлены только обновления безопасности, сервер не будет перезагружаться автоматически.

### Дополнительное укрепление SSH

Отредактируйте `/etc/ssh/sshd_config`:

```
# Отключите всё лишнее
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 2
MaxSessions 2
ClientAliveInterval 300
ClientAliveCountMax 2

# Разрешите вход только конкретным пользователям
AllowUsers root admin

# Или конкретным группам
AllowGroups sshusers
```

Перезапустите SSH:
```bash
sudo systemctl restart sshd
```

---

## Мониторинг и аудит

### Просмотр логов Security Toolkit

```bash
sudo sst
# 7. View Logs

# Или напрямую
cat /var/log/server-security-toolkit/security-toolkit.log
```

### Мониторинг SSH попыток входа

```bash
# Последние попытки входа
sudo journalctl -u sshd | grep "Failed password"

# Успешные входы
sudo journalctl -u sshd | grep "Accepted"

# Реалтайм мониторинг
sudo journalctl -u sshd -f
```

### Мониторинг fail2ban активности

```bash
# Статистика
sudo fail2ban-client status sshd

# Логи fail2ban
sudo journalctl -u fail2ban -n 100

# Реалтайм
sudo journalctl -u fail2ban -f
```

---

## Резервное копирование

### Автоматические бекапы

Security Toolkit автоматически создаёт резервные копии перед изменениями:
- SSH конфигурация → `/opt/server-security-toolkit/backups/ssh/`
- authorized_keys → `/opt/server-security-toolkit/backups/ssh/`
- UFW правила → `/etc/ufw/backup/`
- fail2ban конфигурация → `/opt/server-security-toolkit/backups/system/`

### Восстановление из бекапа

```bash
sudo sst
# 2. SSH Security → 4. Restore SSH Config
# или
# 2. SSH Security → 5. Restore authorized_keys
```

Выберите дату бекапа из списка.

### Ручное создание бекапа

```bash
# SSH
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)
sudo cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.backup.$(date +%Y%m%d)

# UFW
sudo cp -r /etc/ufw /etc/ufw.backup.$(date +%Y%m%d)

# fail2ban
sudo cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.backup.$(date +%Y%m%d)
```

---

## Продвинутое использование

### Автоматическая настройка через конфиг

1. Отредактируйте `/opt/server-security-toolkit/configs/defaults.env`:

```bash
# SSH настройки
SSH_PORT=23321
DISABLE_ROOT_LOGIN=yes
DISABLE_PASSWORD_AUTH=yes

# UFW настройки
UFW_ENABLE=yes
UFW_ADDITIONAL_PORTS="80,443,3000"

# fail2ban
FAIL2BAN_ENABLE=yes
FAIL2BAN_BANTIME="1h"
FAIL2BAN_MAXRETRY=2
```

2. Запустите автоматическую настройку:

```bash
sudo sst
# 1. Full Security Setup
# Выберите "использовать настройки из конфигурации"
```

### Использование в CI/CD

```bash
# Неинтерактивный режим с конфигом
cd /opt/server-security-toolkit
sudo AUTO_MODE=yes bash main.sh --auto-config
```

---

## FAQ

**Q: Безопасно ли менять SSH порт?**  
A: Да, но только после того, как вы убедились, что можете войти по ключу. Toolkit автоматически обновляет UFW.

**Q: Что делать, если забыл новый SSH порт?**  
A: `grep "^Port" /etc/ssh/sshd_config` или `ss -tlnp | grep sshd`

**Q: Можно ли использовать несколько SSH ключей?**  
A: Да, просто импортируйте их по очереди. Все добавятся в `authorized_keys`.

**Q: Как проверить, что fail2ban работает?**  
A: `sudo fail2ban-client status` и `f2b list`. Должны быть активные jail'ы.

**Q: Можно ли удалить Security Toolkit после настройки?**  
A: Да, но рекомендуется оставить для будущих обновлений и восстановления из бекапов.

**Q: Как обновить Security Toolkit?**  
A: `sudo sst` → выберите пункт "Update Toolkit" (если доступно обновление)

**Q: Поддерживаются ли другие дистрибутивы кроме Ubuntu/Debian?**  
A: Оптимизировано для Ubuntu 20.04/22.04/24.04 и Debian 12. Другие дистрибутивы могут работать, но не тестировались.

---

## Поддержка

- **GitHub Issues**: https://github.com/Escanor-87/server-security-toolkit/issues
- **Документация**: https://github.com/Escanor-87/server-security-toolkit
- **Changelog UX**: `/opt/server-security-toolkit/CHANGELOG_UX.md`

---

## Контрольный чеклист безопасности

После полной настройки убедитесь:

- [ ] SSH работает на нестандартном порту
- [ ] Вход по SSH ключу работает
- [ ] Парольная авторизация отключена
- [ ] Root доступ ограничен или отключён
- [ ] UFW активен и настроен
- [ ] fail2ban запущен и активен
- [ ] Автоматические обновления безопасности включены
- [ ] Создан бекап SSH конфигурации
- [ ] Проверен вход с нового устройства
- [ ] Записан новый SSH порт в надёжном месте

**Сервер защищён! 🛡️**

---

**Версия**: 1.1  
**Дата**: 2025-10-05  
**Автор**: Security Toolkit Team
