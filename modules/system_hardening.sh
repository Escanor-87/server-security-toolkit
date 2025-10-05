#!/bin/bash

# System Hardening Module v1.0

# Обновление системы
update_system() {
    clear
    log_info "🔄 Обновление системы"
    echo
    
    read -p "Обновить систему? (Enter = да, 0 = отмена): " -r
    echo
    if [[ "$REPLY" == "0" ]]; then
        return 0
    fi
    
    log_info "Обновление списка пакетов..."
    apt update
    
    log_info "Установка обновлений..."
    apt upgrade -y
    
    log_success "Система обновлена"
}

# Установка fail2ban
install_fail2ban() {
    clear
    log_info "🛡️ Установка fail2ban"
    echo
    
    if command -v fail2ban-server &>/dev/null; then
        log_success "fail2ban уже установлен"
        return 0
    fi
    
    read -p "Установить fail2ban? (Enter = да, 0 = отмена): " -r
    echo
    if [[ "$REPLY" == "0" ]]; then
        return 0
    fi
    
    log_info "Установка fail2ban..."
    if apt install -y fail2ban; then
        log_info "Запуск fail2ban..."
        systemctl enable fail2ban
        systemctl start fail2ban
        log_success "fail2ban установлен и запущен"
    else
        log_error "Ошибка установки fail2ban"
    fi
}

# Базовая конфигурация fail2ban (jail.local)
configure_fail2ban_basic() {
    clear
    log_info "🧩 Базовая конфигурация fail2ban (sshd)"
    echo
    if ! command -v fail2ban-server &>/dev/null; then
        log_error "fail2ban не установлен. Сначала выполните установку."
        return 1
    fi
    
    # Получаем текущий SSH порт для конфигурации
    local ssh_port
    ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "ssh")
    if [[ "$ssh_port" != "22" ]] && [[ "$ssh_port" != "ssh" ]]; then
        ssh_port="ssh,$ssh_port"
    else
        ssh_port="ssh"
    fi
    # Определяем тип логирования: файл или только journald
    local has_auth_log="no"
    if [[ -f "/var/log/auth.log" ]]; then
        # если присутствует файл журнала аутентификации — используем его
        has_auth_log="yes"
    fi

    local jail_conf="/etc/fail2ban/jail.local"
    if [[ ! -f "$jail_conf" ]]; then
        if [[ "$has_auth_log" == "yes" ]]; then
            cat > "$jail_conf" <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 2

[sshd]
enabled = true
port = $ssh_port
logpath = %(sshd_log)s
backend = auto
EOF
        else
            cat > "$jail_conf" <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 2

[sshd]
enabled = true
port = $ssh_port
backend = systemd
# Используем системный журнал (journald). journalmatch уточняет поток для sshd
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
EOF
        fi
        log_success "Создан $jail_conf с базовыми настройками (has_auth_log=$has_auth_log)"
    else
        # Обновляем DEFAULT секцию с новыми настройками
        if grep -q "^\[DEFAULT\]" "$jail_conf"; then
            sed -i '/^\[DEFAULT\]/,/^\[/{s/^bantime.*/bantime = 1h/}' "$jail_conf"
            sed -i '/^\[DEFAULT\]/,/^\[/{s/^maxretry.*/maxretry = 2/}' "$jail_conf"
            sed -i '/^\[DEFAULT\]/,/^\[/{s/^findtime.*/findtime = 10m/}' "$jail_conf"
        else
            # Добавляем DEFAULT секцию в начало файла если её нет
            sed -i '1i[DEFAULT]\nbantime = 1h\nfindtime = 10m\nmaxretry = 2\n' "$jail_conf"
        fi
        
        # Идемпотентно гарантируем enabled=true для sshd и обновляем порт
        if grep -q "^\[sshd\]" "$jail_conf"; then
            sed -i '/^\[sshd\]/,/^\[/{s/^enabled.*/enabled = true/}' "$jail_conf"
            sed -i '/^\[sshd\]/,/^\[/{s/^port.*/port = '"$ssh_port"'/}' "$jail_conf"
            if [[ "$has_auth_log" == "yes" ]]; then
                # Убедимся, что задан logpath и корректный backend для файловых логов
                if grep -q "^logpath" "$jail_conf"; then
                    sed -i '/^\[sshd\]/,/^\[/{s/^logpath.*/logpath = %(sshd_log)s/}' "$jail_conf"
                else
                    sed -i '/^\[sshd\]/,/^\[/{/enabled = true/a logpath = %(sshd_log)s
}' "$jail_conf"
                fi
                if grep -q "^backend" "$jail_conf"; then
                    sed -i '/^\[sshd\]/,/^\[/{s/^backend.*/backend = auto/}' "$jail_conf"
                else
                    sed -i '/^\[sshd\]/,/^\[/{/enabled = true/a backend = auto
}' "$jail_conf"
                fi
                # Удаляем journalmatch, если он был задан ранее
                sed -i '/^\[sshd\]/,/^\[/{/^[[:space:]]*journalmatch/d}' "$jail_conf"
            else
                # Журналы только в systemd: удаляем logpath, выставляем backend=systemd и добавляем journalmatch
                sed -i '/^\[sshd\]/,/^\[/{/^[[:space:]]*logpath/d}' "$jail_conf"
                if grep -q "^backend" "$jail_conf"; then
                    sed -i '/^\[sshd\]/,/^\[/{s/^backend.*/backend = systemd/}' "$jail_conf"
                else
                    sed -i '/^\[sshd\]/,/^\[/{/enabled = true/a backend = systemd
}' "$jail_conf"
                fi
                if grep -q "journalmatch" "$jail_conf"; then
                    sed -i '/^\[sshd\]/,/^\[/{s/^journalmatch.*/journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd/}' "$jail_conf"
                else
                    sed -i '/^\[sshd\]/,/^\[/{/backend = systemd/a journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
}' "$jail_conf"
                fi
            fi
        else
            if [[ "$has_auth_log" == "yes" ]]; then
                cat >> "$jail_conf" <<EOF

[sshd]
enabled = true
port = $ssh_port
logpath = %(sshd_log)s
backend = auto
EOF
            else
                cat >> "$jail_conf" <<EOF

[sshd]
enabled = true
port = $ssh_port
backend = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
EOF
            fi
        fi
        log_success "Обновлен $jail_conf (sshd enabled, port: $ssh_port, has_auth_log=$has_auth_log)"
    fi
    # Перезагружаем/запускаем fail2ban и ждём его активности
    systemctl daemon-reload || true
    if systemctl is-enabled --quiet fail2ban 2>/dev/null; then
        systemctl restart fail2ban || true
    else
        systemctl enable --now fail2ban || true
    fi
    # Ожидание до 10 секунд, чтобы сервис успел подняться на медленных системах
    local __tries=0
    while ! systemctl is-active --quiet fail2ban; do
        ((__tries++))
        if (( __tries >= 10 )); then
            log_warning "fail2ban не активен после перезапуска (истёк таймаут ожидания)"
            log_info "Последние логи fail2ban:"
            journalctl -u fail2ban -n 50 --no-pager 2>/dev/null || true
            break
        fi
        sleep 1
    done
    if systemctl is-active --quiet fail2ban; then
        log_success "fail2ban запущен"
    fi
}

# Установка и настройка автоматических обновлений
install_unattended_upgrades() {
    clear
    log_info "🛠️ Установка unattended-upgrades"
    echo
    
    # Проверяем ОС для специфичных настроек
    local os_id=""
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        os_id="$ID"
    fi
    
    if command -v unattended-upgrade &>/dev/null; then
        log_success "unattended-upgrades уже установлен"
    else
        if apt update && apt install -y unattended-upgrades apt-listchanges; then
            log_success "unattended-upgrades установлен"
        else
            log_error "Не удалось установить unattended-upgrades"
            return 1
        fi
    fi

    log_info "Включение автоматических обновлений..."
    dpkg-reconfigure -f noninteractive unattended-upgrades || true

    # Конфигурация автообновлений
    local auto_conf="/etc/apt/apt.conf.d/20auto-upgrades"
    cat > "$auto_conf" <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
    log_success "Настроен $auto_conf"

    # Дополнительная конфигурация для Debian
    if [[ "$os_id" == "debian" ]]; then
        local unattended_conf="/etc/apt/apt.conf.d/50unattended-upgrades"
        if [[ -f "$unattended_conf" ]]; then
            # Убеждаемся, что security обновления включены для Debian
            if ! grep -q "Debian-Security" "$unattended_conf"; then
                log_info "Настройка security обновлений для Debian..."
                sed -i "/Unattended-Upgrade::Allowed-Origins {/a\\\\\\t\\\"origin=Debian,codename=\${distro_codename}-security\\\";" "$unattended_conf"
            fi
        fi
    fi

    systemctl enable unattended-upgrades || true
    systemctl restart unattended-upgrades || true
    log_success "Автообновления включены"
}

# Диагностика fail2ban
diagnose_fail2ban() {
    clear
    log_info "🔍 Диагностика fail2ban"
    echo
    
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Диагностика fail2ban         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo
    
    # Проверка установки
    if ! command -v fail2ban-server &>/dev/null; then
        log_error "fail2ban не установлен"
        return 1
    fi
    
    # Статус сервиса
    local service_status
    service_status=$(systemctl is-active fail2ban 2>/dev/null || echo "inactive")
    echo -e "🔧 ${BLUE}Статус сервиса:${NC} $service_status"
    
    # Проверка конфигурации
    local jail_conf="/etc/fail2ban/jail.local"
    if [[ -f "$jail_conf" ]]; then
        echo -e "📋 ${BLUE}Конфигурация:${NC} $jail_conf найден"
        
        # Показываем основные настройки
        local bantime maxretry findtime
        bantime=$(grep "^bantime" "$jail_conf" | head -1 | awk '{print $3}' || echo "не задано")
        maxretry=$(grep "^maxretry" "$jail_conf" | head -1 | awk '{print $3}' || echo "не задано")
        findtime=$(grep "^findtime" "$jail_conf" | head -1 | awk '{print $3}' || echo "не задано")
        
        echo -e "   • ${BLUE}bantime:${NC} $bantime"
        echo -e "   • ${BLUE}maxretry:${NC} $maxretry"
        echo -e "   • ${BLUE}findtime:${NC} $findtime"
    else
        log_warning "Конфигурация jail.local не найдена"
    fi
    
    # Проверка логов
    echo
    echo -e "📊 ${BLUE}Проверка источников логов:${NC}"
    if [[ -f "/var/log/auth.log" ]]; then
        local auth_size
        auth_size=$(stat -c%s "/var/log/auth.log" 2>/dev/null || echo "0")
        echo -e "   • ${GREEN}/var/log/auth.log:${NC} найден (${auth_size} байт)"
    else
        echo -e "   • ${YELLOW}/var/log/auth.log:${NC} не найден (используется journald)"
    fi
    
    # Проверка systemd журнала
    local ssh_entries
    ssh_entries=$(journalctl -u ssh.service --since "1 hour ago" 2>/dev/null | wc -l || echo "0")
    echo -e "   • ${BLUE}journald (ssh.service):${NC} $ssh_entries записей за час"
    
    # Проверка активных jail'ов
    echo
    if [[ "$service_status" == "active" ]]; then
        echo -e "🔒 ${BLUE}Активные jail'ы:${NC}"
        local jail_status
        jail_status=$(fail2ban-client status 2>/dev/null)
        if [[ -n "$jail_status" ]]; then
            echo "$jail_status" | while IFS= read -r line; do
                if [[ "$line" =~ Jail\ list: ]]; then
                    echo -e "   ${GREEN}$line${NC}"
                else
                    echo "   $line"
                fi
            done
        else
            echo -e "   ${YELLOW}⚠️ Нет активных jail'ов${NC}"
        fi
        
        # Детали sshd jail если активен
        if fail2ban-client status sshd &>/dev/null; then
            echo
            echo -e "🛡️ ${BLUE}Детали sshd jail:${NC}"
            fail2ban-client status sshd 2>/dev/null | while IFS= read -r line; do
                if [[ "$line" =~ Currently\ banned: ]]; then
                    echo -e "   ${RED}$line${NC}"
                elif [[ "$line" =~ Total\ banned: ]]; then
                    echo -e "   ${YELLOW}$line${NC}"
                else
                    echo "   $line"
                fi
            done
        fi
    else
        echo -e "❌ ${RED}fail2ban неактивен - невозможно получить статус jail'ов${NC}"
    fi
    
    # Последние ошибки
    echo
    echo -e "📋 ${BLUE}Последние ошибки/предупреждения:${NC}"
    echo "════════════════════════════════════════"
    journalctl -u fail2ban --since "1 hour ago" -p warning 2>/dev/null | tail -10 | while IFS= read -r line; do
        if [[ "$line" =~ ERROR ]]; then
            echo -e "${RED}$line${NC}"
        elif [[ "$line" =~ WARNING ]]; then
            echo -e "${YELLOW}$line${NC}"
        else
            echo "$line"
        fi
    done
    
    echo
    echo "📊 Информация о банах/установках появится после первых попыток взлома"
    
    echo
    echo -e "${BLUE}💡 Рекомендации по дополнительным jail'ам для усиления безопасности:${NC}"
    echo "• nginx-http-auth - защита от брутфорса HTTP Basic Auth"
    echo "• apache - защита Apache от сканирования и атак"
    echo "• vsftpd - защита FTP сервера"
    echo "• postfix - защита почтового сервера"
    echo "• dovecot - защита IMAP/POP3"
    echo "• recidive - повторные баны для часто атакующих IP"
}

# Показать статус безопасности
show_security_status() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Статус безопасности системы    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo
    
    # Последнее обновление
    local last_update
    last_update=$(stat -c %y /var/lib/apt/lists/ 2>/dev/null | head -1 | cut -d' ' -f1 || echo "unknown")
    echo -e "📅 ${BLUE}Последнее обновление:${NC} $last_update"
    
    # fail2ban статус
    local fail2ban_status
    fail2ban_status=$(systemctl is-active fail2ban 2>/dev/null || echo "not installed")
    if [[ "$fail2ban_status" == "active" ]]; then
        echo -e "🛡️  ${BLUE}fail2ban:${NC} ${GREEN}✅ активен${NC}"
    elif [[ "$fail2ban_status" == "inactive" ]]; then
        echo -e "🛡️  ${BLUE}fail2ban:${NC} ${YELLOW}⚠️ неактивен${NC}"
    else
        echo -e "🛡️  ${BLUE}fail2ban:${NC} ${RED}❌ не установлен${NC}"
    fi
    
    # Автообновления
    local auto_updates
    auto_updates=$(systemctl is-enabled unattended-upgrades 2>/dev/null || echo "not configured")
    if [[ "$auto_updates" == "enabled" ]]; then
        echo -e "🔄 ${BLUE}Автообновления:${NC} ${GREEN}✅ включены${NC}"
    else
        echo -e "🔄 ${BLUE}Автообновления:${NC} ${RED}❌ не настроены${NC}"
    fi
    
    # CrowdSec статус
    local crowdsec_status
    crowdsec_status=$(systemctl is-active crowdsec 2>/dev/null || echo "not installed")
    if [[ "$crowdsec_status" == "active" ]]; then
        echo -e "🧱 ${BLUE}CrowdSec:${NC} ${GREEN}✅ активен${NC}"
    elif [[ "$crowdsec_status" == "inactive" ]]; then
        echo -e "🧱 ${BLUE}CrowdSec:${NC} ${YELLOW}⚠️ неактивен${NC}"
    else
        echo -e "🧱 ${BLUE}CrowdSec:${NC} ${RED}❌ не установлен${NC}"
    fi
    
    # CrowdSec Bouncer статус
    local bouncer_status
    bouncer_status=$(systemctl is-active crowdsec-firewall-bouncer 2>/dev/null || echo "not installed")
    if [[ "$bouncer_status" == "active" ]]; then
        echo -e "🚪 ${BLUE}CrowdSec Bouncer:${NC} ${GREEN}✅ активен${NC}"
    elif [[ "$bouncer_status" == "inactive" ]]; then
        echo -e "🚪 ${BLUE}CrowdSec Bouncer:${NC} ${YELLOW}⚠️ неактивен${NC}"
    else
        echo -e "🚪 ${BLUE}CrowdSec Bouncer:${NC} ${RED}❌ не установлен${NC}"
    fi
    
    # fail2ban jails детали
    if command -v fail2ban-client &>/dev/null && [[ "$fail2ban_status" == "active" ]]; then
        echo
        echo -e "${BLUE}🔒 fail2ban jails:${NC}"
        echo "════════════════════════════════════════"
        local jail_status
        jail_status=$(fail2ban-client status 2>/dev/null)
        if [[ -n "$jail_status" ]]; then
            echo "$jail_status" | while IFS= read -r line; do
                if [[ "$line" =~ Jail\ list: ]]; then
                    echo -e "${GREEN}$line${NC}"
                else
                    echo "$line"
                fi
            done
        else
            echo -e "${YELLOW}⚠️ fail2ban запущен, но нет активных jails${NC}"
        fi
    fi
    
    echo
    echo "════════════════════════════════════════"
}

# Главное меню System Hardening модуля
system_hardening() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║       System Hardening Menu          ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo
        echo "1. 🔄 Обновить систему"
        echo "2. 🛡️ Установить fail2ban"
        echo "3. 🧩 Базовая конфигурация fail2ban (sshd)"
        echo "4. ⚙️  Установить и включить unattended-upgrades"
        echo "5. 🧱 Установить CrowdSec"
        echo "6. 🚪 Установить CrowdSec Firewall Bouncer (iptables)"
        echo "7. 🔍 Диагностика fail2ban"
        echo "0. ⬅️  Назад в главное меню"
        echo
        read -p "Выберите действие [0-7]: " -n 1 -r choice
        echo
        case $choice in
            1) update_system ;;
            2) install_fail2ban ;;
            3) configure_fail2ban_basic ;;
            4) install_unattended_upgrades ;;
            5) install_crowdsec ;;
            6) install_crowdsec_bouncer ;;
            7) diagnose_fail2ban ;;
            0) return 0 ;;
            *) 
                log_error "Неверный выбор"
                sleep 1
                ;;
        esac
        
        if [[ "$choice" != "0" ]]; then
            echo
            read -p "Нажмите Enter для продолжения..." -r
        fi
    done
}

# Установка CrowdSec
install_crowdsec() {
    clear
    log_info "🧱 Установка CrowdSec"
    echo
    if systemctl is-active --quiet crowdsec 2>/dev/null; then
        log_success "CrowdSec уже установлен и запущен"
        return 0
    fi
    if apt update && apt install -y crowdsec; then
        systemctl enable crowdsec || true
        systemctl start crowdsec || true
        if systemctl is-active --quiet crowdsec; then
            log_success "CrowdSec установлен и запущен"
        else
            log_warning "CrowdSec установлен, но не активен"
        fi
    else
        log_error "Не удалось установить CrowdSec. Возможно, пакет недоступен в репозиториях."
        log_info "См. официальную документацию: https://docs.crowdsec.net/docs/getting_started/install/"
    fi
}

# Установка CrowdSec Firewall Bouncer (iptables)
install_crowdsec_bouncer() {
    clear
    log_info "🚪 Установка CrowdSec Firewall Bouncer (iptables)"
    echo
    if systemctl is-active --quiet crowdsec-firewall-bouncer 2>/dev/null; then
        log_success "Firewall Bouncer уже установлен и запущен"
        return 0
    fi
    if apt update && apt install -y crowdsec-firewall-bouncer-iptables; then
        systemctl enable crowdsec-firewall-bouncer || true
        systemctl start crowdsec-firewall-bouncer || true
        if systemctl is-active --quiet crowdsec-firewall-bouncer; then
            log_success "Bouncer установлен и запущен"
        else
            log_warning "Bouncer установлен, но не активен"
        fi
    else
        log_error "Не удалось установить Firewall Bouncer."
        log_info "Если используется nftables, установите пакет crowdsec-firewall-bouncer-nftables"
    fi
}
