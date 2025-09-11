#!/bin/bash

# Firewall Module v1.0  
# Модуль настройки файрвола UFW

# Проверка загрузки модуля
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    echo "ERROR: Firewall Module должен загружаться из main.sh"
    exit 1
fi

# === БАЗОВЫЕ ФУНКЦИИ UFW ===

# Установка UFW
install_ufw() {
    log_info "📦 Проверка установки UFW..."
    
    if command -v ufw &>/dev/null; then
        log_success "UFW уже установлен"
        return 0
    fi
    
    log_info "Установка UFW..."
    if apt update && apt install -y ufw; then
        log_success "UFW установлен успешно"
        return 0
    else
        log_error "Не удалось установить UFW"
        return 1
    fi
}

# Базовая настройка UFW
configure_basic_firewall() {
    log_info "🛡️ Базовая настройка файрвола UFW..."
    
    # Устанавливаем UFW если нужно
    if ! install_ufw; then
        return 1
    fi
    
    # Сброс к умолчаниям
    log_info "Сброс правил UFW к умолчаниям..."
    ufw --force reset
    
    # Базовые политики
    log_info "Установка базовых политик..."
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH порт (получаем из конфигурации)
    local ssh_port
    ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    
    log_info "Разрешение SSH подключений на порту $ssh_port..."
    ufw allow "$ssh_port"/tcp comment "SSH"
    
    # Веб-серверы (для nginx)
    log_info "Разрешение HTTP/HTTPS трафика..."
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS"
    
    # Включаем UFW
    log_info "Включение UFW..."
    ufw --force enable
    
    log_success "Базовая настройка файрвола завершена"
    ufw status verbose
    
    return 0
}

# Главная функция модуля
configure_firewall() {
    log_info "🛡️ Запуск модуля Firewall..."
    
    # Проверяем права root
    if [[ $EUID -ne 0 ]]; then
        log_error "Firewall модуль требует права root"
        return 1
    fi
    
    configure_basic_firewall
}

log_success "Firewall Module загружен успешно"
