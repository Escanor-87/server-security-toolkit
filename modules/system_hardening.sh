#!/bin/bash

# System Hardening Module v1.0

# Обновление системы
update_system() {
    clear
    log_info "🔄 Обновление системы"
    echo
    
    read -p "Обновить систему? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
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
    
    read -p "Установить fail2ban? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
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
    
    local jail_conf="/etc/fail2ban/jail.local"
    if [[ ! -f "$jail_conf" ]]; then
        cat > "$jail_conf" <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = $ssh_port
logpath = %(sshd_log)s
backend = systemd
EOF
        log_success "Создан $jail_conf с базовыми настройками"
    else
        # Идемпотентно гарантируем enabled=true для sshd и обновляем порт
        if grep -q "^\[sshd\]" "$jail_conf"; then
            sed -i '/^\[sshd\]/,/^\[/{s/^enabled.*/enabled = true/}' "$jail_conf"
            sed -i '/^\[sshd\]/,/^\[/{s/^port.*/port = '"$ssh_port"'/}' "$jail_conf"
        else
            cat >> "$jail_conf" <<EOF

[sshd]
enabled = true
port = $ssh_port
logpath = %(sshd_log)s
backend = systemd
EOF
        fi
        log_success "Обновлен $jail_conf (sshd enabled, port: $ssh_port)"
    fi
    systemctl restart fail2ban || true
    sleep 1
    systemctl is-active --quiet fail2ban && log_success "fail2ban перезапущен" || log_warning "fail2ban не активен"
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
                sed -i '/Unattended-Upgrade::Allowed-Origins {/a\\t"origin=Debian,codename=${distro_codename}-security";' "$unattended_conf"
            fi
        fi
    fi

    systemctl enable unattended-upgrades || true
    systemctl restart unattended-upgrades || true
    log_success "Автообновления включены"
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
                if [[ "$line" =~ "Jail list:" ]]; then
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
        echo "7. 📋 Показать статус безопасности"
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
            7) show_security_status ;;
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
        systemctl is-active --quiet crowdsec && log_success "CrowdSec установлен и запущен" || log_warning "CrowdSec установлен, но не активен"
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
        systemctl is-active --quiet crowdsec-firewall-bouncer && log_success "Bouncer установлен и запущен" || log_warning "Bouncer установлен, но не активен"
    else
        log_error "Не удалось установить Firewall Bouncer."
        log_info "Если используется nftables, установите пакет crowdsec-firewall-bouncer-nftables"
    fi
}
