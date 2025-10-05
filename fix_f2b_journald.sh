#!/bin/bash
# Быстрое исправление fail2ban для journald-only систем
# Использование: sudo bash fix_f2b_journald.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Исправление конфигурации fail2ban для journald${NC}"
echo

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ошибка: требуются права root${NC}"
    echo "Запустите: sudo bash $0"
    exit 1
fi

# Определяем SSH порт
SSH_PORT=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "ssh")
if [[ "$SSH_PORT" != "22" ]] && [[ "$SSH_PORT" != "ssh" ]]; then
    SSH_PORT="ssh,$SSH_PORT"
else
    SSH_PORT="ssh"
fi

echo -e "${YELLOW}Обнаруженный SSH порт: $SSH_PORT${NC}"

# Проверяем наличие auth.log
if [[ -f "/var/log/auth.log" ]]; then
    echo -e "${GREEN}✓ Обнаружен /var/log/auth.log${NC}"
    HAS_AUTH_LOG="yes"
else
    echo -e "${YELLOW}⚠ Файл /var/log/auth.log не найден, используем journald${NC}"
    HAS_AUTH_LOG="no"
fi

# Создаем резервную копию
if [[ -f /etc/fail2ban/jail.local ]]; then
    cp /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${GREEN}✓ Создана резервная копия jail.local${NC}"
fi

# Генерируем правильную конфигурацию
echo
echo -e "${BLUE}Применяем конфигурацию...${NC}"

if [[ "$HAS_AUTH_LOG" == "yes" ]]; then
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 2
backend = auto

[sshd]
enabled = true
port = $SSH_PORT
logpath = %(sshd_log)s
EOF
    echo -e "${GREEN}✓ Конфигурация для файловых логов применена${NC}"
else
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 2

[sshd]
enabled = true
port = $SSH_PORT
backend = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
EOF
    echo -e "${GREEN}✓ Конфигурация для journald применена${NC}"
fi

# Проверяем конфигурацию
echo
echo -e "${BLUE}Проверка конфигурации...${NC}"
if fail2ban-client -t 2>&1 | grep -q "OK"; then
    echo -e "${GREEN}✓ Конфигурация корректна${NC}"
else
    echo -e "${RED}✗ Ошибка в конфигурации!${NC}"
    fail2ban-client -t
    exit 1
fi

# Перезапускаем fail2ban
echo
echo -e "${BLUE}Перезапуск fail2ban...${NC}"
systemctl restart fail2ban

# Ждем запуска
sleep 2

# Проверяем статус
if systemctl is-active --quiet fail2ban; then
    echo -e "${GREEN}✓ fail2ban успешно запущен!${NC}"
    echo
    echo -e "${BLUE}Статус jail'ов:${NC}"
    fail2ban-client status
else
    echo -e "${RED}✗ fail2ban не запустился${NC}"
    echo
    echo -e "${YELLOW}Последние 20 строк лога:${NC}"
    journalctl -u fail2ban -n 20 --no-pager
    exit 1
fi

echo
echo -e "${GREEN}✅ Исправление завершено успешно!${NC}"
echo
echo -e "${YELLOW}Полезные команды:${NC}"
echo "  fail2ban-client status sshd  - статус sshd jail"
echo "  f2b list                     - список забаненных IP"
echo "  journalctl -u fail2ban -f    - мониторинг логов в реальном времени"
