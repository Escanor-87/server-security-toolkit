#!/bin/bash

# Firewall Module v1.0

# Установка UFW
install_ufw() {
    if command -v ufw &>/dev/null; then
        log_success "UFW уже установлен"
        return 0
    fi
    
    log_info "Установка UFW..."
    if apt update && apt install -y ufw; then
        log_success "UFW установлен"
        return 0
    else
        log_error "Ошибка установки UFW"
        return 1
    fi
}

# Настройка базового файрвола
setup_basic_firewall() {
    clear
    log_info "🛡️ Настройка базового файрвола"
    echo
    
    if ! command -v ufw &>/dev/null; then
        log_error "UFW не установлен"
        return 1
    fi
    
    read -p "Настроить базовые правила файрвола? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi
    
    # Создаем резервную копию текущих правил UFW
    local backup_dir="/etc/ufw/backup"
    local backup_file="$backup_dir/ufw_rules_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    mkdir -p "$backup_dir"
    if tar -czf "$backup_file" -C /etc/ufw . 2>/dev/null; then
        log_success "Резервная копия UFW: $backup_file"
    else
        log_warning "Не удалось создать резервную копию UFW"
    fi
    
    log_info "Сброс правил UFW..."
    ufw --force reset
    
    log_info "Установка базовых политик..."
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH порт
    local ssh_port
    ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    log_info "Разрешение SSH на порту $ssh_port..."
    ufw allow "$ssh_port"/tcp
    
    # Веб-серверы
    log_info "Разрешение HTTP/HTTPS..."
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    log_info "Включение UFW..."
    ufw --force enable
    
    log_success "Базовый файрвол настроен"
    ufw status verbose
}

# Показать статус UFW
show_firewall_status() {
    clear
    log_info "📋 Статус файрвола"
    echo "════════════════════════════════════════"
    
    if command -v ufw &>/dev/null; then
        ufw status verbose
    else
        echo "UFW не установлен"
    fi
    
    echo "════════════════════════════════════════"
}

# Добавить правило
add_firewall_rule() {
    clear
    log_info "➕ Добавление правила файрвола"
    echo
    
    local port
    while true; do
        read -p "Введите порт: " -r port
        
        if [[ -z "$port" ]]; then
            log_warning "Порт не может быть пустым. Попробуйте снова."
            continue
        fi
        
        if [[ ! "$port" =~ ^[0-9]+$ ]]; then
            log_error "Неверный формат порта. Используйте только цифры."
            continue
        fi
        
        if [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
            log_error "Порт должен быть от 1 до 65535"
            continue
        fi
        
        break
    done
    
    echo "Выберите протокол:"
    echo "1. TCP"
    echo "2. UDP" 
    echo "3. TCP и UDP"
    echo "0. 🔙 Назад в меню файрвола"
    local proto_choice
    read -p "Выбор [0-3]: " -n 1 -r proto_choice
    echo
    
    local protocol
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="" ;;
        0) return 0 ;;
        *) log_error "Неверный выбор"; return 1 ;;
    esac
    
    local comment
    read -p "Комментарий (опционально): " -r comment
    
    if [[ -n "$protocol" ]]; then
        if [[ -n "$comment" ]]; then
            ufw allow "$port"/"$protocol" comment "$comment"
        else
            ufw allow "$port"/"$protocol"
        fi
    else
        if [[ -n "$comment" ]]; then
            ufw allow "$port" comment "$comment"
        else
            ufw allow "$port"
        fi
    fi
    
    log_success "Правило добавлено для порта $port"
}

# Главное меню Firewall модуля
configure_firewall() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║         Firewall Setup Menu          ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo
        echo "1. 📦 Установить UFW"
        echo "2. 🛡️ Настроить базовый файрвол"
        echo "3. ➕ Добавить правило"
        echo "4. 📋 Показать статус"
        echo "5. 🔙 Восстановить из резервной копии"
        echo "0. ⬅️  Назад в главное меню"
        echo
        read -p "Выберите действие [0-5]: " -n 1 -r choice
        echo
        
        case $choice in
            1) install_ufw ;;
            2) setup_basic_firewall ;;
            3) add_firewall_rule ;;
            4) show_firewall_status ;;
            5) restore_firewall_backup ;;
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

# Восстановление firewall из резервной копии
restore_firewall_backup() {
    clear
    log_info "🔙 Восстановление UFW из резервной копии"
    echo
    
    local backup_dir="/etc/ufw/backup"
    if [[ ! -d "$backup_dir" ]]; then
        log_warning "Директория резервных копий не найдена: $backup_dir"
        return 0
    fi
    
    # Ищем резервные копии UFW
    local backup_files
    mapfile -t backup_files < <(find "$backup_dir" -name "ufw_rules_*.tar.gz" 2>/dev/null | sort -r)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log_warning "Резервные копии UFW не найдены"
        return 0
    fi
    
    echo "Найденные резервные копии UFW:"
    echo "════════════════════════════════════════════════════"
    local i=1
    for backup in "${backup_files[@]}"; do
        local backup_date backup_size
        backup_date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2)
        backup_size=$(stat -c %s "$backup" 2>/dev/null)
        echo "$i. $(basename "$backup") (создан: $backup_date, размер: $backup_size байт)"
        ((i++))
    done
    echo "════════════════════════════════════════════════════"
    echo
    
    read -p "Введите номер резервной копии для восстановления [1-$((i-1))] или 0 для отмены: " -r backup_num
    
    if [[ "$backup_num" == "0" ]]; then
        log_info "Восстановление отменено"
        return 0
    fi
    
    if [[ ! "$backup_num" =~ ^[0-9]+$ ]] || [[ "$backup_num" -lt 1 ]] || [[ "$backup_num" -gt $((i-1)) ]]; then
        log_error "Неверный номер резервной копии"
        return 1
    fi
    
    local selected_backup="${backup_files[$((backup_num-1))]}"
    
    echo
    log_warning "⚠️  ВНИМАНИЕ: Это действие перезапишет текущие правила UFW!"
    echo "Будет восстановлен файл: $(basename "$selected_backup")"
    echo
    read -p "Продолжить восстановление? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Восстановление отменено"
        return 0
    fi
    
    # Создаем резервную копию текущих правил перед восстановлением
    local current_backup="$backup_dir/ufw_rules_before_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
    if tar -czf "$current_backup" -C /etc/ufw . 2>/dev/null; then
        log_info "Текущие правила сохранены как: $(basename "$current_backup")"
    fi
    
    # Останавливаем UFW
    log_info "Остановка UFW..."
    ufw --force disable
    
    # Восстанавливаем из резервной копии
    log_info "Восстановление правил UFW..."
    if tar -xzf "$selected_backup" -C /etc/ufw; then
        log_success "Правила UFW восстановлены из $(basename "$selected_backup")"
        
        # Перезапускаем UFW
        log_info "Запуск UFW..."
        if ufw --force enable; then
            log_success "UFW запущен с восстановленными правилами"
            echo
            log_info "Текущий статус UFW:"
            ufw status verbose
        else
            log_error "Ошибка запуска UFW"
            return 1
        fi
    else
        log_error "Ошибка восстановления правил UFW"
        return 1
    fi
}
