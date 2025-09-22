# 🛡️ Server Security Toolkit

Модульный инструмент для автоматизации настройки безопасности Ubuntu серверов. Создан для управления безопасностью множественных серверов с NetBird, nginx, Docker и другими сервисами.

## ✨ Основные возможности

- 🔐 **SSH Security**: Смена портов, отключение паролей, настройка ключевой авторизации
- 🛡️ **Firewall Management**: Автоматическая настройка UFW с поддержкой Docker и NetBird
- 🔧 **System Hardening**: Укрепление системы безопасности и автоматические обновления
- 🔑 **SSH Key Management**: Генерация, импорт и распределение ключей по серверам
- 📊 **Comprehensive Logging**: Подробное логирование всех операций
- 🧪 **Safe Testing Mode**: Безопасное тестирование без изменения системы
- 🔄 **Rollback Support**: Автоматическое создание резервных копий конфигураций
 - 🧱 **CrowdSec (опционально)**: Установка ядра и firewall-bouncer

## 🏗️ Архитектура проекта

server-security-toolkit/
├── main.sh # 🚀 Главный скрипт с интерактивным меню
├── modules/ # 📦 Модули функциональности
│ ├── ssh_security.sh # 🔐 SSH безопасность и ключи
│ ├── firewall.sh # 🛡️ Настройка UFW файрвола
│ └── system_hardening.sh # 🔧 Укрепление системы
├── configs/ # ⚙️ Шаблоны конфигураций
├── keys/ # 🔑 SSH ключи (игнорируются Git)
├── logs/ # 📋 Файлы логов (игнорируются Git)
├── scripts/ # 🛠️ Вспомогательные скрипты
├── tests/ # 🧪 Тестовые скрипты
├── docs/ # 📚 Документация
└── .vscode/ # 💻 Настройки VS Code
├── settings.json # Конфигурация редактора
└── tasks.json # Задачи для разработки

text

## 🚀 Быстрый старт

### 🎯 Однострочная установка (рекомендуется)

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Escanor-87/server-security-toolkit/main/install.sh)
```

После установки запуск:
```bash
sudo security-toolkit
```

### 📦 Ручная установка

1. Клонирование репозитория
```bash
git clone https://github.com/Escanor-87/server-security-toolkit.git
cd server-security-toolkit
```

2. Настройка прав доступа
```bash
chmod +x main.sh modules/*.sh
```

3. Запуск
```bash
sudo ./main.sh
```

### Рекомендуемый порядок настройки

1. **🧪 Тестовый режим** - проверка текущих настроек
2. **🔑 SSH ключи** - генерация и установка ключей
3. **🔐 SSH безопасность** - смена порта, отключение паролей
4. **🛡️ Файрвол** - настройка UFW правил
5. **🔧 Системное укрепление** - fail2ban, обновления

## 📋 Поддерживаемые системы

- ✅ **Ubuntu 20.04 LTS** (рекомендуется)
- ✅ **Ubuntu 22.04 LTS** (полная поддержка)
- ✅ **Ubuntu 24.04 LTS** (тестируется)
- ⚠️ **Другие Debian-based** (частичная поддержка)

## 🔧 Системные требования

### Обязательные
- `bash` 4.0+
- `systemctl` (systemd)
- `ssh` / `openssh-server`
- Права `root` или `sudo`

### Автоматически устанавливаемые
- `ufw` (Uncomplicated Firewall)
- `fail2ban` (защита от брутфорса)

## 📖 Подробное использование

### SSH Security Module

Интерактивное меню SSH настроек
sudo ./main.sh

Выберите опцию 1
Доступные функции:
🔧 Смена SSH порта (с автообновлением UFW)
🔑 Генерация RSA/Ed25519 ключей
📥 Импорт публичного ключа в authorized_keys
📜 Просмотр и 🗑️ удаление ключей из authorized_keys
🔒 Отключение парольной авторизации (идемпотентно)
🚫 Отключение root входа (PermitRootLogin no)
🛡️ Доп. проверки и безопасный перезапуск sshd
text

### Firewall Module

Настройка базового файрвола
sudo ./main.sh

Выберите опцию 2
Автоматически настраивается:
- Базовые политики (deny incoming, allow outgoing)
- SSH порт (текущий или измененный)
- HTTP/HTTPS (80, 443) для веб-серверов
- Совместимость с Docker и NetBird
text

### Управление одним ключом для всех серверов

1. Генерируем мастер-ключ на первом сервере
sudo ./main.sh → SSH Security → Generate SSH Key

2. Копируем приватный ключ на локальную машину
scp root@server1:/root/server-security-toolkit/keys/server_security_key ~/.ssh/

3. На остальных серверах импортируем публичный ключ
sudo ./main.sh → SSH Security → Import public key → вставить/указать .pub

### System Hardening Module

Укрепление системы безопасности
sudo ./main.sh

Выберите опцию 3
Доступные функции:
🔧 Установка и настройка fail2ban
🔄 Настройка автоматических обновлений (unattended-upgrades)
text

### CrowdSec Module (optional)

Установка CrowdSec ядра и firewall-bouncer
sudo ./main.sh

Выберите опцию 4
Доступные функции:
🔧 Установка CrowdSec ядра
🔄 Установка firewall-bouncer
text

## 🔍 Логирование и мониторинг

Все операции подробно логируются:

Просмотр логов текущей сессии
sudo ./main.sh → View Logs (опция 7)

Логи сохраняются в:
logs/security-YYYYMMDD_HHMMSS.log

Структура лога:
[2025-09-11 19:34:15] [INFO] [SSH] Changed port from 22 to 2222
[2025-09-11 19:34:16] [SUCCESS] [SSH] Disabled password authentication
[2025-09-11 19:34:17] [WARNING] [UFW] Manual review needed for Docker rules

text

## 🛠️ Разработка и тестирование

### Настройка среды разработки

Установка VS Code расширений (автоматически при открытии проекта):
- ShellCheck (проверка bash синтаксиса)
- GitLens (продвинутая работа с Git)
Открытие проекта в VS Code
code .

Тестирование на macOS (режим разработки)
DEVELOPMENT_MODE=true ./main.sh

text

### Структура модулей

Каждый модуль следует единой структуре:

#!/bin/bash

Module Name v1.0
Проверка корректной загрузки
if [[ -z "${SCRIPT_DIR:-}" ]]; then
echo "ERROR: Module должен загружаться из main.sh"
exit 1
fi

Основные функции модуля
function_name() {
log_info "Описание действия..."
# Логика функции
}

Главная функция модуля
main_module_function() {
# Интерактивное меню или автоматическое выполнение
}

log_success "Module загружен успешно"

text

## 🚧 Roadmap разработки

### Фаза 1 - Основа (✅ Завершено)
- [x] Архитектура проекта и модульная система
- [x] SSH Security модуль (базовый функционал)
- [x] Firewall модуль (UFW настройка)
- [x] System Hardening (заготовка)
- [x] Логирование и безопасное тестирование

### Фаза 2 - Расширенный функционал (🚧 В разработке)
- [x] Полная реализация SSH Security функций (импорт/список/удаление ключей, запрет root)
- [ ] Продвинутые правила файрвола
- [x] Автоматические обновления системы (unattended-upgrades)
- [x] Базовая конфигурация fail2ban (sshd jail)
- [ ] Мониторинг и алерты
- [x] Опциональная интеграция CrowdSec и Firewall Bouncer

### Фаза 3 - Автоматизация (📋 Планируется)
- [ ] Multi-server deployment
- [ ] Централизованное управление ключами
- [ ] NetBird и CertWarden интеграции
- [ ] Docker security hardening
- [ ] Scheduled maintenance tasks

## 🤝 Участие в разработке

### Создание Issue

Если нашли баг или хотите предложить функцию:

1. Перейдите в [Issues](https://github.com/Escanor-87/server-security-toolkit/issues)
2. Нажмите "New Issue"
3. Выберите шаблон (Bug Report / Feature Request)
4. Заполните детали

### Pull Requests

1. Форкните репозиторий
2. Создайте feature ветку: `git checkout -b feature/amazing-feature`
3. Внесите изменения и добавьте тесты
4. Коммитьте: `git commit -m 'Add amazing feature'`
5. Отправьте в ветку: `git push origin feature/amazing-feature`
6. Создайте Pull Request

## 📞 Поддержка

- 🐛 **Баги**: [GitHub Issues](https://github.com/Escanor-87/server-security-toolkit/issues)
- 💡 **Предложения**: [GitHub Discussions](https://github.com/Escanor-87/server-security-toolkit/discussions)
- 📧 **Прямой контакт**: создайте Issue с меткой `question`

## ⚖️ Лицензия

Этот проект распространяется под лицензией MIT. См. файл [LICENSE](LICENSE) для подробностей.

## 🙏 Благодарности

- Ubuntu Security Team за документацию
- OpenSSH разработчики за надежный SSH
- UFW команда за простой файрвол
- Сообщество за feedback и тестирование

---

## 🔒 Важные замечания по безопасности

⚠️ **ВСЕГДА имейте план восстановления доступа к серверу**

⚠️ **Тестируйте SSH доступ в новой сессии перед закрытием текущей**

⚠️ **Создавайте резервные копии важных конфигураций**

⚠️ **Используйте тестовый режим перед применением на продакшене**

---
*Создано с ❤️ для безопасности серверов*