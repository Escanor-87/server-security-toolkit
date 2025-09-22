#!/bin/bash

# SSH Security Module v1.0

readonly SSH_CONFIG="/etc/ssh/sshd_config"

# Вспомогательная функция: идемпотентная установка опции в sshd_config
set_sshd_config_option() {
    # usage: set_sshd_config_option "Directive" "value"
    local directive="$1"
    local value="$2"
    if grep -Eq "^#?${directive}\\b" "$SSH_CONFIG"; then
        # Заменяем существующую строку (включая закомментированную)
        sed -i "s~^#\?${directive}.*~${directive} ${value}~" "$SSH_CONFIG"
    else
        echo "${directive} ${value}" >> "$SSH_CONFIG"
    fi
}

# Резервная копия SSH конфигурации
backup_ssh_config() {
    local backup_file
    backup_file="${SSH_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    if cp "$SSH_CONFIG" "$backup_file" 2>/dev/null; then
        log_success "Резервная копия: $backup_file"
        return 0
    else
        log_error "Не удалось создать резервную копию"
        return 1
    fi
}

# Автоматическое обновление UFW для SSH порта
update_ufw_ssh_port() {
    local old_port="$1"
    local new_port="$2"
    
    if ! command -v ufw &>/dev/null; then
        log_warning "UFW не установлен, пропускаем обновление правил"
        return 0
    fi
    
    # Проверяем, включен ли UFW
    if ! ufw status | grep -q "Status: active"; then
        log_warning "UFW не активен, пропускаем обновление правил"
        return 0
    fi
    
    log_info "Обновление правил UFW..."
    
    # Удаляем старое правило, если оно существует и порт не 22
    if [[ "$old_port" != "22" ]] && ufw status numbered | grep -q "$old_port/tcp"; then
        log_info "Удаление старого правила для порта $old_port"
        ufw delete allow "$old_port/tcp" 2>/dev/null || true
    fi
    
    # Добавляем новое правило
    log_info "Добавление правила для нового SSH порта $new_port"
    ufw allow "$new_port/tcp" comment "SSH"
    
    log_success "UFW правила обновлены для SSH порта $new_port"
}

# Изменение SSH порта
change_ssh_port() {
    clear
    log_info "🔧 Изменение SSH порта (с автообновлением UFW)"
    echo
    
    local current_port
    current_port=$(grep "^Port" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "22")
    echo "Текущий SSH порт: $current_port"
    echo
    
    local new_port
    while true; do
        read -p "Введите новый SSH порт (например: 2222, 2200, 22000): " -r new_port
        
        if [[ -z "$new_port" ]]; then
            log_warning "Порт не может быть пустым. Попробуйте снова."
            continue
        fi
        
        if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1024 ]] || [[ "$new_port" -gt 65535 ]]; then
            log_error "Неверный порт. Используйте порт от 1024 до 65535"
            continue
        fi
        
        break
    done
    
    if [[ "$new_port" == "$current_port" ]]; then
        log_warning "Новый порт совпадает с текущим"
        return 0
    fi
    
    # Предупреждение об изменении UFW
    echo
    log_warning "⚠️  ВНИМАНИЕ: Будут автоматически обновлены правила UFW!"
    echo "   - Старый порт $current_port будет удален из UFW (если не 22)"
    echo "   - Новый порт $new_port будет добавлен в UFW"
    echo
    read -p "Продолжить изменение порта и обновление UFW? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Операция отменена"
        return 0
    fi
    
    # Создаем резервную копию
    backup_ssh_config
    
    # Изменяем порт
    set_sshd_config_option "Port" "$new_port"
    
    # Обновляем UFW правила
    update_ufw_ssh_port "$current_port" "$new_port"
    
    log_success "SSH порт изменен на $new_port"
    log_info "🔥 UFW правила обновлены автоматически"
    log_warning "⚠️  Обязательно протестируйте SSH подключение в новой сессии!"
}

# Отключение парольной авторизации
disable_password_auth() {
    clear
    log_info "🔒 Отключение парольной авторизации"
    echo
    
    local current_setting
    current_setting=$(grep "^PasswordAuthentication" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "yes")
    echo "Текущая настройка: $current_setting"
    
    if [[ "$current_setting" == "no" ]]; then
        log_info "Парольная авторизация уже отключена"
        return 0
    fi
    
    log_warning "ВНИМАНИЕ! Убедитесь, что SSH ключи настроены!"
    read -p "Отключить парольную авторизацию? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        backup_ssh_config
        set_sshd_config_option "PasswordAuthentication" "no"
        log_success "Парольная авторизация отключена"
    else
        log_info "Операция отменена"
    fi
}

# Отключение root входа
disable_root_login() {
    clear
    log_info "🚫 Отключение SSH входа для root"
    echo
    local current_setting
    current_setting=$(grep "^PermitRootLogin" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "yes")
    echo "Текущая настройка PermitRootLogin: $current_setting"
    echo
    read -p "Отключить вход root (PermitRootLogin no)? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        backup_ssh_config
        set_sshd_config_option "PermitRootLogin" "no"
        log_success "Root вход по SSH отключен"
    else
        log_info "Операция отменена"
    fi
}

# Генерация SSH ключей с копированием в буфер
generate_ssh_key() {
    clear
    log_info "🔑 Генерация SSH ключей"
    echo
    
    # Выбор типа ключа
    echo "Выберите тип ключа:"
    echo "1. Ed25519 (рекомендуется, современный)"
    echo "2. RSA 4096 (совместимость)"
    echo
    read -p "Выберите тип [1-2]: " -n 1 -r key_type
    echo
    
    local key_file="/root/.ssh/id_ed25519"
    local key_params="-t ed25519"
    
    case $key_type in
        1)
            key_file="/root/.ssh/id_ed25519"
            key_params="-t ed25519"
            log_info "Выбран тип: Ed25519"
            ;;
        2)
            key_file="/root/.ssh/id_rsa"
            key_params="-t rsa -b 4096"
            log_info "Выбран тип: RSA 4096"
            ;;
        *)
            log_warning "Неверный выбор, используется Ed25519 по умолчанию"
            ;;
    esac
    
    # Проверяем существующий ключ
    if [[ -f "$key_file" ]]; then
        echo
        log_warning "Ключ уже существует: $key_file"
        read -p "Перезаписать существующий ключ? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Генерация отменена"
            return 0
        fi
    fi
    
    # Генерируем ключ
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    
    log_info "Генерация ключа..."
    if ssh-keygen $key_params -f "$key_file" -N "" -C "root@$(hostname)"; then
        log_success "Ключ сгенерирован: $key_file"
        
        # Копируем публичный ключ в буфер обмена и показываем
        local pub_key_file="${key_file}.pub"
        if [[ -f "$pub_key_file" ]]; then
            local pub_key_content
            pub_key_content=$(cat "$pub_key_file")
            
            # Пытаемся скопировать в буфер обмена
            if command -v xclip &>/dev/null; then
                echo "$pub_key_content" | xclip -selection clipboard
                log_success "Публичный ключ скопирован в буфер обмена (xclip)"
            elif command -v pbcopy &>/dev/null; then
                echo "$pub_key_content" | pbcopy
                log_success "Публичный ключ скопирован в буфер обмена (pbcopy)"
            elif command -v wl-copy &>/dev/null; then
                echo "$pub_key_content" | wl-copy
                log_success "Публичный ключ скопирован в буфер обмена (wl-copy)"
            else
                log_warning "Утилиты для буфера обмена не найдены (xclip/pbcopy/wl-copy)"
            fi
            
            # Показываем публичный ключ
            echo
            log_info "📋 Сгенерированный публичный ключ:"
            echo "════════════════════════════════════════════════════════════════"
            cat "$pub_key_file"
            echo "════════════════════════════════════════════════════════════════"
            echo
            log_info "💡 Теперь можете:"
            log_info "   1. Добавить его на этом сервере: пункт 3 → вставить из буфера"
            log_info "   2. Добавить на других серверах: sudo ss → 3. Импорт ключа"
            echo
            read -p "Нажмите Enter для продолжения..." -r
        fi
    else
        log_error "Ошибка генерации ключа"
        return 1
    fi
}

# Генерация SSH ключей (старая функция для совместимости)
generate_ssh_key() {
    clear
    log_info "🔑 Генерация SSH ключей"
    echo
    
    local key_name="server_security_key"
    local key_dir="/root/.ssh"
    local key_path="$key_dir/$key_name"
    
    mkdir -p "$key_dir"
    
    if [[ -f "$key_path" ]]; then
        log_warning "Ключ уже существует: $key_path"
        read -p "Перегенерировать? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    log_info "Генерация RSA ключа 4096 бит..."
    local key_comment
    key_comment="Server Security Toolkit $(date +%Y-%m-%d)"
    
    if ssh-keygen -t rsa -b 4096 -f "$key_path" -N "" -C "$key_comment"; then
        chmod 600 "$key_path"
        chmod 644 "$key_path.pub"
        
        log_success "SSH ключ сгенерирован успешно!"
        echo
        echo "Публичный ключ:"
        echo "════════════════════════════════════════"
        cat "$key_path.pub"
        echo "════════════════════════════════════════"
    else
        log_error "Ошибка генерации ключа"
    fi
}

# Импорт публичного ключа в authorized_keys
install_public_key() {
    clear
    log_info "📥 Импорт публичного ключа в authorized_keys"
    echo
    local auth_dir="/root/.ssh"
    local auth_file="$auth_dir/authorized_keys"
    mkdir -p "$auth_dir"
    chmod 700 "$auth_dir"

    echo "Выберите источник ключа:"
    echo "1. Вставить ключ вручную"
    echo "2. Путь к файлу с ключом (.pub)"
    echo "0. 🔙 Назад в SSH меню"
    read -p "Выбор [0-2]: " -n 1 -r src_choice
    echo

    local pubkey
    case "$src_choice" in
        1)
            while true; do
                echo "Вставьте публичный ключ (начиная с ssh-rsa/ssh-ed25519) и нажмите Enter:"
                read -r pubkey
                
                if [[ -z "$pubkey" ]]; then
                    log_warning "Ключ не может быть пустым. Попробуйте снова или нажмите Ctrl+C для отмены."
                    continue
                fi
                
                if [[ ! "$pubkey" =~ ^ssh- ]]; then
                    log_error "Некорректный формат ключа. Ключ должен начинаться с ssh-rsa, ssh-ed25519 и т.д."
                    echo "Попробуйте снова или нажмите Ctrl+C для отмены."
                    continue
                fi
                
                break
            done
            ;;
        2)
            while true; do
                read -p "Укажите путь к файлу публичного ключа: " -r key_path
                
                if [[ -z "$key_path" ]]; then
                    log_warning "Путь не может быть пустым. Попробуйте снова."
                    continue
                fi
                
                if [[ ! -f "$key_path" ]]; then
                    log_error "Файл не найден: $key_path"
                    echo "Попробуйте снова или нажмите Ctrl+C для отмены."
                    continue
                fi
                
                pubkey=$(sed -n '1p' "$key_path")
                if [[ -z "$pubkey" ]] || [[ ! "$pubkey" =~ ^ssh- ]]; then
                    log_error "Файл не содержит корректный SSH ключ"
                    echo "Попробуйте снова или нажмите Ctrl+C для отмены."
                    continue
                fi
                
                break
            done
            ;;
        0)
            return 0
            ;;
        *)
            log_error "Неверный выбор"
            return 1
            ;;
    esac

    touch "$auth_file"
    chmod 600 "$auth_file"

    if grep -Fxq "$pubkey" "$auth_file"; then
        log_warning "Такой ключ уже присутствует в authorized_keys"
        return 0
    fi

    echo "$pubkey" >> "$auth_file"
    log_success "Ключ добавлен в $auth_file"
}

# Список ключей в authorized_keys
list_authorized_keys() {
    clear
    log_info "📋 Список ключей в /root/.ssh/authorized_keys"
    echo "════════════════════════════════════════"
    local auth_file="/root/.ssh/authorized_keys"
    if [[ -s "$auth_file" ]]; then
        nl -ba "$auth_file"
    else
        echo "Нет ключей"
    fi
    echo "════════════════════════════════════════"
}

# Управление authorized_keys (объединенная функция)
manage_authorized_keys() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║      Управление authorized_keys      ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo
        
        if [[ ! -f /root/.ssh/authorized_keys ]]; then
            log_warning "Файл authorized_keys не существует"
            echo
            echo "1. 🔙 Назад в SSH меню"
            echo
            read -p "Нажмите 1 для возврата: " -n 1 -r choice
            echo
            if [[ "$choice" == "1" ]]; then
                return 0
            fi
            continue
        fi
        
        local key_count
        if [[ -s /root/.ssh/authorized_keys ]]; then
            key_count=$(grep -c "^ssh-" /root/.ssh/authorized_keys 2>/dev/null || echo "0")
        else
            key_count="0"
        fi
        
        if [[ "$key_count" -eq 0 ]]; then
            log_warning "В authorized_keys нет SSH ключей"
            echo
            echo "1. 🔙 Назад в SSH меню"
            echo
            read -p "Нажмите 1 для возврата: " -n 1 -r choice
            echo
            if [[ "$choice" == "1" ]]; then
                return 0
            fi
            continue
        fi
        
        log_info "📋 Найдено ключей: $key_count"
        echo "════════════════════════════════════════════════════════════════"
        
        local line_num=1
        while IFS= read -r line; do
            if [[ "$line" =~ ^ssh- ]]; then
                local key_type="${line%% *}"
                local key_comment="${line##* }"
                if [[ "$key_comment" == "$line" ]]; then
                    key_comment="(без комментария)"
                fi
                echo "$line_num. $key_type ... $key_comment"
                ((line_num++))
            fi
        done < /root/.ssh/authorized_keys
        
        echo "════════════════════════════════════════════════════════════════"
        echo
        echo "Выберите действие:"
        echo "1. 📋 Скопировать ключ в буфер обмена"
        echo "2. 🗑️  Удалить ключ"
        echo "3. 👁️  Показать полный ключ"
        echo "0. 🔙 Назад в SSH меню"
        echo
        read -p "Выберите действие [0-3]: " -n 1 -r action
        echo
        
        case $action in
            1) copy_authorized_key "$key_count" ;;
            2) remove_authorized_key "$key_count" ;;
            3) show_full_key "$key_count" ;;
            0) return 0 ;;
            *)
                log_error "Неверный выбор: '$action'"
                sleep 2
                continue
                ;;
        esac
        
        if [[ "$action" != "0" ]]; then
            echo
            read -p "Нажмите Enter для продолжения..." -r
        fi
    done
}

# Копирование ключа в буфер обмена
copy_authorized_key() {
    local max_keys="$1"
    read -p "Введите номер ключа для копирования [1-$max_keys]: " -r key_num
    
    if [[ ! "$key_num" =~ ^[0-9]+$ ]] || [[ "$key_num" -lt 1 ]] || [[ "$key_num" -gt "$max_keys" ]]; then
        log_error "Неверный номер ключа"
        return 1
    fi
    
    local line_num=1
    local found_key=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^ssh- ]]; then
            if [[ "$line_num" -eq "$key_num" ]]; then
                found_key="$line"
                break
            fi
            ((line_num++))
        fi
    done < /root/.ssh/authorized_keys
    
    if [[ -n "$found_key" ]]; then
        # Пытаемся скопировать в буфер обмена
        if command -v xclip &>/dev/null; then
            echo "$found_key" | xclip -selection clipboard
            log_success "Ключ скопирован в буфер обмена (xclip)"
        elif command -v pbcopy &>/dev/null; then
            echo "$found_key" | pbcopy
            log_success "Ключ скопирован в буфер обмена (pbcopy)"
        elif command -v wl-copy &>/dev/null; then
            echo "$found_key" | wl-copy
            log_success "Ключ скопирован в буфер обмена (wl-copy)"
        else
            log_warning "Утилиты для буфера обмена не найдены"
            echo "Ключ:"
            echo "$found_key"
        fi
    else
        log_error "Ключ не найден"
    fi
}

# Показ полного ключа
show_full_key() {
    local max_keys="$1"
    read -p "Введите номер ключа для просмотра [1-$max_keys]: " -r key_num
    
    if [[ ! "$key_num" =~ ^[0-9]+$ ]] || [[ "$key_num" -lt 1 ]] || [[ "$key_num" -gt "$max_keys" ]]; then
        log_error "Неверный номер ключа"
        return 1
    fi
    
    local line_num=1
    while IFS= read -r line; do
        if [[ "$line" =~ ^ssh- ]]; then
            if [[ "$line_num" -eq "$key_num" ]]; then
                echo "════════════════════════════════════════════════════════════════"
                echo "$line"
                echo "════════════════════════════════════════════════════════════════"
                return 0
            fi
            ((line_num++))
        fi
    done < /root/.ssh/authorized_keys
    
    log_error "Ключ не найден"
}

# Удаление ключа по номеру строки
remove_authorized_key() {
    local max_keys="$1"
    read -p "Введите номер ключа для удаления [1-$max_keys]: " -r key_num
    
    if [[ ! "$key_num" =~ ^[0-9]+$ ]] || [[ "$key_num" -lt 1 ]] || [[ "$key_num" -gt "$max_keys" ]]; then
        log_error "Неверный номер ключа"
        return 1
    fi
    
    # Показываем ключ, который будет удален
    local line_num=1
    local found_key=""
    local key_comment=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^ssh- ]]; then
            if [[ "$line_num" -eq "$key_num" ]]; then
                found_key="$line"
                key_comment="${line##* }"
                if [[ "$key_comment" == "$line" ]]; then
                    key_comment="(без комментария)"
                fi
                break
            fi
            ((line_num++))
        fi
    done < /root/.ssh/authorized_keys
    
    if [[ -z "$found_key" ]]; then
        log_error "Ключ не найден"
        return 1
    fi
    
    echo
    log_warning "Будет удален ключ: $key_comment"
    echo "Ключ: ${found_key:0:50}..."
    echo
    read -p "Подтвердите удаление (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Удаление отменено"
        return 0
    fi
    
    # Создаем резервную копию
    local backup_file
    backup_file="/root/.ssh/authorized_keys.backup.$(date +%Y%m%d_%H%M%S)"
    cp /root/.ssh/authorized_keys "$backup_file"
    log_info "Резервная копия: $backup_file"
    
    # Удаляем ключ
    local temp_file
    temp_file=$(mktemp)
    line_num=1
    while IFS= read -r line; do
        if [[ "$line" =~ ^ssh- ]]; then
            if [[ "$line_num" -ne "$key_num" ]]; then
                echo "$line" >> "$temp_file"
            fi
            ((line_num++))
        else
            echo "$line" >> "$temp_file"
        fi
    done < /root/.ssh/authorized_keys
    
    mv "$temp_file" /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    
    log_success "Ключ удален успешно"
}

# Показать текущие настройки SSH
show_ssh_status() {
    clear
    log_info "📋 Текущие настройки SSH"
    echo "════════════════════════════════════════"
    
    local port
    local password_auth
    local root_login
    
    port=$(grep "^Port" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "22 (default)")
    password_auth=$(grep "^PasswordAuthentication" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "yes (default)")
    root_login=$(grep "^PermitRootLogin" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "yes (default)")
    
    echo "SSH Port: $port"
    echo "Password Authentication: $password_auth"
    echo "Root Login: $root_login"
    echo "SSH Service: $(systemctl is-active ssh 2>/dev/null)"
    
    if [[ -f /root/.ssh/authorized_keys ]]; then
        local key_count
        key_count=$(grep -c "^ssh-" /root/.ssh/authorized_keys 2>/dev/null || echo "0")
        echo "Authorized Keys: $key_count"
    else
        echo "Authorized Keys: none"
    fi
    
    # UFW статус для SSH
    if command -v ufw &>/dev/null; then
        echo "UFW Status: $(ufw status | head -1)"
        if ufw status | grep -q "Status: active"; then
            local ssh_rules
            ssh_rules=$(ufw status | grep -E "^$port|^22" | grep -c "tcp" || echo "0")
            echo "UFW SSH Rules: $ssh_rules active"
        fi
    else
        echo "UFW: not installed"
    fi
    
    echo "════════════════════════════════════════"
}

# Перезапуск SSH
restart_ssh() {
    clear
    log_info "🔄 Перезапуск SSH службы"
    echo
    
    # Проверяем конфигурацию
    if ! sshd -t 2>/dev/null; then
        log_error "Ошибки в SSH конфигурации:"
        sshd -t
        return 1
    fi
    
    read -p "Перезапустить SSH службу? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if systemctl restart ssh; then
            log_success "SSH служба перезапущена"
        else
            log_error "Ошибка перезапуска SSH"
        fi
    fi
}

# Объединенное управление SSH ключами
ssh_key_management() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║        Управление SSH ключами        ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo
        
        echo "Выберите действие:"
        echo "1. 🔑 Генерировать новые SSH ключи"
        echo "2. 📥 Импортировать публичный ключ"
        echo "3. 📜 Управление authorized_keys (просмотр/копирование/удаление)"
        echo "0. 🔙 Назад в SSH меню"
        echo
        read -p "Выберите действие [0-3]: " -n 1 -r key_choice
        echo
        
        case $key_choice in
            1) generate_ssh_key ;;
            2) install_public_key ;;
            3) manage_authorized_keys ;;
            0) return 0 ;;
            *)
                log_error "Неверный выбор: '$key_choice'"
                sleep 1
                continue
                ;;
        esac
        
        if [[ "$key_choice" != "0" ]]; then
            echo
            read -p "Нажмите Enter для продолжения..." -r
        fi
    done
}

# Восстановление из резервной копии
restore_from_backup() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║      Восстановление из бекапа        ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo
        
        echo "Выберите тип восстановления:"
        echo "1. 🔧 Восстановить SSH конфигурацию (/etc/ssh/sshd_config)"
        echo "2. 🔑 Восстановить authorized_keys"
        echo "3. 📋 Показать доступные резервные копии"
        echo "0. 🔙 Назад в SSH меню"
        echo
        read -p "Выберите действие [0-3]: " -n 1 -r restore_choice
        echo
        
        case $restore_choice in
            1) restore_ssh_config ;;
            2) restore_authorized_keys ;;
            3) show_backup_files ;;
            0) return 0 ;;
            *)
                log_error "Неверный выбор: '$restore_choice'"
                sleep 1
                continue
                ;;
        esac
        
        if [[ "$restore_choice" != "0" ]]; then
            echo
            read -p "Нажмите Enter для продолжения..." -r
        fi
    done
}

# Восстановление SSH конфигурации
restore_ssh_config() {
    clear
    log_info "🔧 Восстановление SSH конфигурации"
    echo
    
    # Ищем резервные копии SSH конфигурации
    local backup_files
    mapfile -t backup_files < <(find /etc/ssh -name "sshd_config.backup.*" 2>/dev/null | sort -r)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log_warning "Резервные копии SSH конфигурации не найдены"
        return 0
    fi
    
    echo "Найденные резервные копии SSH конфигурации:"
    echo "════════════════════════════════════════════════════"
    local i=1
    for backup in "${backup_files[@]}"; do
        local backup_date
        backup_date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2)
        echo "$i. $(basename "$backup") (создан: $backup_date)"
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
    log_warning "⚠️  ВНИМАНИЕ: Это действие перезапишет текущую SSH конфигурацию!"
    echo "Будет восстановлен файл: $(basename "$selected_backup")"
    echo
    read -p "Продолжить восстановление? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Восстановление отменено"
        return 0
    fi
    
    # Создаем резервную копию текущей конфигурации перед восстановлением
    backup_ssh_config
    
    # Восстанавливаем из резервной копии
    if cp "$selected_backup" "$SSH_CONFIG"; then
        log_success "SSH конфигурация восстановлена из $(basename "$selected_backup")"
        log_warning "⚠️  Необходимо перезапустить SSH службу для применения изменений!"
        echo
        read -p "Перезапустить SSH службу сейчас? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            restart_ssh
        fi
    else
        log_error "Ошибка восстановления SSH конфигурации"
        return 1
    fi
}

# Восстановление authorized_keys
restore_authorized_keys() {
    clear
    log_info "🔑 Восстановление authorized_keys"
    echo
    
    # Ищем резервные копии authorized_keys
    local backup_files
    mapfile -t backup_files < <(find /root/.ssh -name "authorized_keys.backup.*" 2>/dev/null | sort -r)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log_warning "Резервные копии authorized_keys не найдены"
        return 0
    fi
    
    echo "Найденные резервные копии authorized_keys:"
    echo "════════════════════════════════════════════════════"
    local i=1
    for backup in "${backup_files[@]}"; do
        local backup_date key_count
        backup_date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2)
        key_count=$(grep -c "^ssh-" "$backup" 2>/dev/null || echo "0")
        echo "$i. $(basename "$backup") (создан: $backup_date, ключей: $key_count)"
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
    log_warning "⚠️  ВНИМАНИЕ: Это действие перезапишет текущий authorized_keys!"
    echo "Будет восстановлен файл: $(basename "$selected_backup")"
    echo
    read -p "Продолжить восстановление? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Восстановление отменено"
        return 0
    fi
    
    # Создаем резервную копию текущего файла перед восстановлением
    if [[ -f /root/.ssh/authorized_keys ]]; then
        local current_backup
        current_backup="/root/.ssh/authorized_keys.backup.$(date +%Y%m%d_%H%M%S)"
        cp /root/.ssh/authorized_keys "$current_backup"
        log_info "Текущий файл сохранен как: $(basename "$current_backup")"
    fi
    
    # Восстанавливаем из резервной копии
    if cp "$selected_backup" /root/.ssh/authorized_keys; then
        chmod 600 /root/.ssh/authorized_keys
        log_success "authorized_keys восстановлен из $(basename "$selected_backup")"
    else
        log_error "Ошибка восстановления authorized_keys"
        return 1
    fi
}

# Показать доступные резервные копии
show_backup_files() {
    clear
    log_info "📋 Доступные резервные копии"
    echo
    
    # SSH конфигурация
    echo -e "${BLUE}🔧 SSH конфигурация (sshd_config):${NC}"
    echo "════════════════════════════════════════════════════"
    local ssh_backups
    mapfile -t ssh_backups < <(find /etc/ssh -name "sshd_config.backup.*" 2>/dev/null | sort -r)
    
    if [[ ${#ssh_backups[@]} -eq 0 ]]; then
        echo "Резервные копии не найдены"
    else
        for backup in "${ssh_backups[@]}"; do
            local backup_date backup_size
            backup_date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2)
            backup_size=$(stat -c %s "$backup" 2>/dev/null)
            echo "📄 $(basename "$backup")"
            echo "   Создан: $backup_date"
            echo "   Размер: $backup_size байт"
            echo
        done
    fi
    
    echo
    # authorized_keys
    echo -e "${BLUE}🔑 Authorized Keys:${NC}"
    echo "════════════════════════════════════════════════════"
    local key_backups
    mapfile -t key_backups < <(find /root/.ssh -name "authorized_keys.backup.*" 2>/dev/null | sort -r)
    
    if [[ ${#key_backups[@]} -eq 0 ]]; then
        echo "Резервные копии не найдены"
    else
        for backup in "${key_backups[@]}"; do
            local backup_date backup_size key_count
            backup_date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2)
            backup_size=$(stat -c %s "$backup" 2>/dev/null)
            key_count=$(grep -c "^ssh-" "$backup" 2>/dev/null || echo "0")
            echo "📄 $(basename "$backup")"
            echo "   Создан: $backup_date"
            echo "   Размер: $backup_size байт"
            echo "   Ключей: $key_count"
            echo
        done
    fi
    
    echo "════════════════════════════════════════════════════"
}

# Главное меню SSH модуля
configure_ssh_security() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║          SSH Security Menu           ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo
        echo "1. 🔧 Изменить SSH порт (+ автообновление UFW)"
        echo "2. 🔑 Управление SSH ключами (генерация/импорт/просмотр/удаление)"
        echo "3. 📋 Показать текущие настройки"
        echo "4. 🔒 Отключить парольную авторизацию"
        echo "5. 🚫 Отключить root SSH вход"
        echo "6. 🔄 Перезапустить SSH службу"
        echo "7. 🔙 Восстановить из резервной копии"
        echo "0. ⬅️  Назад в главное меню"
        echo
        read -p "Выберите действие [0-7]: " -n 1 -r choice
        echo
        
        case $choice in
            1) change_ssh_port ;;
            2) ssh_key_management ;;
            3) show_ssh_status ;;
            4) disable_password_auth ;;
            5) disable_root_login ;;
            6) restart_ssh ;;
            7) restore_from_backup ;;
            0) return 0 ;;
            *)
                log_error "Неверный выбор: '$choice'"
                sleep 2
                continue
                ;;
        esac
        
        if [[ "$choice" != "0" ]]; then
            echo
            read -p "Нажмите Enter для продолжения..." -r
        fi
    done
}
