#!/bin/bash

# SSH Security Module v1.0
# Модуль настройки безопасности SSH

# Константы модуля
readonly SSH_CONFIG="/etc/ssh/sshd_config"
readonly SSH_SERVICE="sshd"
readonly AUTHORIZED_KEYS_DIR="/root/.ssh"
readonly DEFAULT_NEW_PORT=2222

# Проверка, что модуль загружается корректно
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    echo "ERROR: SSH Security Module должен загружаться из main.sh"
    exit 1
fi

# === БАЗОВЫЕ ФУНКЦИИ ===

# Создание резервной копии SSH конфигурации
backup_ssh_config() {
    local backup_file="${SSH_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    
    log_info "Создание резервной копии SSH конфигурации..."
    
    if [[ ! -f "$SSH_CONFIG" ]]; then
        log_error "SSH конфигурация не найдена: $SSH_CONFIG"
        return 1
    fi
    
    if cp "$SSH_CONFIG" "$backup_file"; then
        log_success "Резервная копия создана: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_error "Не удалось создать резервную копию"
        return 1
    fi
}

# Проверка валидности SSH конфигурации
validate_ssh_config() {
    log_info "Проверка валидности SSH конфигурации..."
    
    if sshd -t 2>/dev/null; then
        log_success "SSH конфигурация валидна"
        return 0
    else
        log_error "SSH конфигурация содержит ошибки"
        log_info "Подробности ошибок:"
        sshd -t
        return 1
    fi
}

# Перезапуск SSH сервиса с проверками
restart_ssh_service() {
    log_info "Перезапуск SSH службы..."
    
    # Проверяем конфигурацию перед перезапуском
    if ! validate_ssh_config; then
        log_error "Не перезапускаем SSH из-за ошибок в конфигурации"
        return 1
    fi
    
    # Перезапускаем службу
    if systemctl restart "$SSH_SERVICE"; then
        sleep 2  # Даем время на запуск
        
        if systemctl is-active "$SSH_SERVICE" &>/dev/null; then
            log_success "SSH служба успешно перезапущена"
            return 0
        else
            log_error "SSH служба не запустилась после перезапуска"
            return 1
        fi
    else
        log_error "Ошибка перезапуска SSH службы"
        return 1
    fi
}

# === ФУНКЦИИ ИЗМЕНЕНИЯ КОНФИГУРАЦИИ ===

# Изменение параметра в SSH конфигурации
modify_ssh_parameter() {
    local parameter="$1"
    local new_value="$2"
    local comment="${3:-}"
    
    log_debug "Изменение параметра SSH: $parameter = $new_value"
    
    # Создаем временный файл
    local temp_file="/tmp/sshd_config.tmp"
    cp "$SSH_CONFIG" "$temp_file"
    
    # Удаляем существующие строки с параметром (закомментированные и активные)
    sed -i "/^#*$parameter /d" "$temp_file"
    
    # Добавляем новый параметр
    if [[ -n "$comment" ]]; then
        echo "# $comment" >> "$temp_file"
    fi
    echo "$parameter $new_value" >> "$temp_file"
    
    # Проверяем результат
    if sshd -t -f "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$SSH_CONFIG"
        log_success "Параметр $parameter установлен в: $new_value"
        return 0
    else
        rm -f "$temp_file"
        log_error "Ошибка при изменении параметра $parameter"
        return 1
    fi
}

# === ОСНОВНЫЕ ФУНКЦИИ БЕЗОПАСНОСТИ ===

# Смена SSH порта
change_ssh_port() {
    log_info "🔧 Настройка SSH порта..."
    
    # Получаем текущий порт
    local current_port
    current_port=$(grep "^Port " "$SSH_CONFIG" 2>/dev/null | awk '{print $2}')
    if [[ -z "$current_port" ]]; then
        current_port="22"
    fi
    
    log_info "Текущий SSH порт: $current_port"
    
    # Спрашиваем новый порт
    local new_port
    while true; do
        echo
        read -p "Введите новый SSH порт [$DEFAULT_NEW_PORT]: " new_port
        new_port=${new_port:-$DEFAULT_NEW_PORT}
        
        # Проверяем валидность порта
        if [[ "$new_port" =~ ^[0-9]+$ ]] && [[ "$new_port" -ge 1024 ]] && [[ "$new_port" -le 65535 ]]; then
            if [[ "$new_port" != "$current_port" ]]; then
                break
            else
                log_warning "Новый порт совпадает с текущим"
            fi
        else
            log_error "Порт должен быть числом от 1024 до 65535"
        fi
    done
    
    # Проверяем, не занят ли порт
    if ss -tulpn | grep ":$new_port " &>/dev/null; then
        log_warning "Порт $new_port уже используется другим сервисом"
        read -p "Продолжить? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Создаем резервную копию
    local backup_file
    if ! backup_file=$(backup_ssh_config); then
        return 1
    fi
    
    # Изменяем порт
    if modify_ssh_parameter "Port" "$new_port" "Custom SSH port for security"; then
        log_success "SSH порт изменен с $current_port на $new_port"
        
        # Важное предупреждение
        log_warning "ВАЖНО! Не забудьте:"
        echo "  1. Открыть порт $new_port в файрволе"
        echo "  2. Обновить настройки клиентов SSH"
        echo "  3. Проверить доступ ПЕРЕД закрытием текущей сессии"
        echo
        
        return 0
    else
        log_error "Не удалось изменить SSH порт"
        return 1
    fi
}

# Отключение парольной авторизации
disable_password_auth() {
    log_info "🔒 Отключение парольной авторизации SSH..."
    
    # Проверяем текущее состояние
    local current_setting
    current_setting=$(grep "^PasswordAuthentication" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}')
    if [[ -z "$current_setting" ]]; then
        current_setting="yes"  # По умолчанию включено
    fi
    
    log_info "Текущая настройка PasswordAuthentication: $current_setting"
    
    if [[ "$current_setting" == "no" ]]; then
        log_info "Парольная авторизация уже отключена"
        return 0
    fi
    
    # Предупреждение
    log_warning "ВНИМАНИЕ! Парольная авторизация будет отключена"
    log_info "Убедитесь, что SSH ключи настроены и работают!"
    echo
    read -p "Продолжить отключение парольной авторизации? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Отключение парольной авторизации отменено"
        return 0
    fi
    
    # Создаем резервную копию
    if ! backup_ssh_config >/dev/null; then
        return 1
    fi
    
    # Отключаем парольную авторизацию
    if modify_ssh_parameter "PasswordAuthentication" "no" "Disable password authentication for security"; then
        log_success "Парольная авторизация отключена"
        
        log_warning "КРИТИЧЕСКИ ВАЖНО!"
        echo "  • Проверьте доступ по SSH ключу ПЕРЕД перезапуском SSH"
        echo "  • Не закрывайте текущую сессию до проверки"
        echo "  • Имейте план восстановления доступа"
        echo
        
        return 0
    else
        log_error "Не удалось отключить парольную авторизацию"
        return 1
    fi
}

# Отключение root авторизации
disable_root_login() {
    log_info "🚫 Отключение прямого входа под root..."
    
    # Проверяем текущее состояние
    local current_setting
    current_setting=$(grep "^PermitRootLogin" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}')
    if [[ -z "$current_setting" ]]; then
        current_setting="yes"  # По умолчанию разрешено
    fi
    
    log_info "Текущая настройка PermitRootLogin: $current_setting"
    
    if [[ "$current_setting" == "no" ]]; then
        log_info "Вход под root уже отключен"
        return 0
    fi
    
    # Предупреждение
    log_warning "ВНИМАНИЕ! Прямой вход под root будет отключен"
    log_info "Убедитесь, что есть другой пользователь с sudo правами!"
    echo
    read -p "Продолжить отключение root входа? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Отключение root входа отменено"
        return 0
    fi
    
    # Создаем резервную копию
    if ! backup_ssh_config >/dev/null; then
        return 1
    fi
    
    # Отключаем root вход
    if modify_ssh_parameter "PermitRootLogin" "no" "Disable direct root login for security"; then
        log_success "Прямой вход под root отключен"
        
        log_warning "ВАЖНО! Убедитесь, что у вас есть:"
        echo "  • Другой пользователь с sudo правами"
        echo "  • Возможность войти под этим пользователем"
        echo "  • План восстановления доступа"
        echo
        
        return 0
    else
        log_error "Не удалось отключить root вход"
        return 1
    fi
}

# === УПРАВЛЕНИЕ SSH КЛЮЧАМИ ===

# Генерация SSH ключа
generate_ssh_key() {
    log_info "🔑 Генерация SSH ключа..."
    
    local key_name="server_security_key"
    local key_path="${KEYS_DIR}/${key_name}"
    local key_comment="Generated by Server Security Toolkit $(date +%Y-%m-%d)"
    
    # Создаем директорию для ключей
    mkdir -p "$KEYS_DIR"
    
    # Проверяем, существует ли уже ключ
    if [[ -f "${key_path}" ]]; then
        log_warning "Ключ уже существует: ${key_path}"
        read -p "Перегенерировать ключ? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    # Генерируем ключ
    log_info "Генерация RSA ключа 4096 бит..."
    if ssh-keygen -t rsa -b 4096 -f "$key_path" -N "" -C "$key_comment"; then
        log_success "SSH ключ сгенерирован:"
        echo "  Приватный ключ: ${key_path}"
        echo "  Публичный ключ: ${key_path}.pub"
        
        # Устанавливаем правильные права
        chmod 600 "$key_path"
        chmod 644 "${key_path}.pub"
        
        log_info "Содержимое публичного ключа:"
        echo "════════════════════════════════════════"
        cat "${key_path}.pub"
        echo "════════════════════════════════════════"
        
        return 0
    else
        log_error "Не удалось сгенерировать SSH ключ"
        return 1
    fi
}

# Установка SSH ключа
install_ssh_key() {
    log_info "📥 Установка SSH ключа для авторизации..."
    
    # Опции установки
    echo "Выберите способ установки ключа:"
    echo "1. Использовать сгенерированный ключ"
    echo "2. Импортировать существующий ключ"
    echo "3. Ввести публичный ключ вручную"
    echo "0. Отмена"
    echo
    read -p "Выберите опцию [1-3, 0]: " -n 1 -r choice
    echo
    
    local public_key_content=""
    
    case $choice in
        1)
            # Используем сгенерированный ключ
            local generated_key="${KEYS_DIR}/server_security_key.pub"
            if [[ -f "$generated_key" ]]; then
                public_key_content=$(cat "$generated_key")
                log_info "Используем сгенерированный ключ"
            else
                log_error "Сгенерированный ключ не найден. Сначала генерируйте ключ."
                return 1
            fi
            ;;
        2)
            # Импортируем существующий ключ
            read -p "Путь к файлу публичного ключа: " key_file
            if [[ -f "$key_file" ]]; then
                public_key_content=$(cat "$key_file")
                log_success "Ключ загружен из: $key_file"
            else
                log_error "Файл не найден: $key_file"
                return 1
            fi
            ;;
        3)
            # Вводим ключ вручную
            echo "Вставьте публичный ключ (начинается с ssh-rsa, ssh-ed25519 и т.д.):"
            read -r public_key_content
            ;;
        0)
            log_info "Установка ключа отменена"
            return 0
            ;;
        *)
            log_error "Неверный выбор"
            return 1
            ;;
    esac
    
    # Проверяем формат ключа
    if [[ ! "$public_key_content" =~ ^ssh-[a-z0-9]+ ]]; then
        log_error "Неверный формат SSH ключа"
        return 1
    fi
    
    # Создаем директорию .ssh
    mkdir -p "$AUTHORIZED_KEYS_DIR"
    chmod 700 "$AUTHORIZED_KEYS_DIR"
    
    # Добавляем ключ в authorized_keys
    local authorized_keys_file="${AUTHORIZED_KEYS_DIR}/authorized_keys"
    
    # Проверяем, не добавлен ли уже этот ключ
    if [[ -f "$authorized_keys_file" ]] && grep -Fq "$public_key_content" "$authorized_keys_file"; then
        log_info "Ключ уже добавлен в authorized_keys"
        return 0
    fi
    
    # Добавляем ключ
    echo "$public_key_content" >> "$authorized_keys_file"
    chmod 600 "$authorized_keys_file"
    
    log_success "SSH ключ добавлен в authorized_keys"
    log_info "Теперь можно подключаться по SSH ключу"
    
    return 0
}

# === ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ БЕЗОПАСНОСТИ ===

# Настройка дополнительных параметров безопасности
configure_additional_security() {
    log_info "🛡️ Настройка дополнительных параметров безопасности SSH..."
    
    # Создаем резервную копию
    if ! backup_ssh_config >/dev/null; then
        return 1
    fi
    
    local changes_made=false
    
    # Ограничение попыток авторизации
    if modify_ssh_parameter "MaxAuthTries" "3" "Limit authentication attempts"; then
        changes_made=true
    fi
    
    # Таймаут неактивности
    if modify_ssh_parameter "ClientAliveInterval" "300" "Client timeout (5 minutes)"; then
        changes_made=true
    fi
    
    # Максимальное количество неактивных сессий
    if modify_ssh_parameter "ClientAliveCountMax" "2" "Max inactive sessions"; then
        changes_made=true
    fi
    
    # Отключение X11 forwarding
    if modify_ssh_parameter "X11Forwarding" "no" "Disable X11 forwarding for security"; then
        changes_made=true
    fi
    
    # Отключение forwarding для агента
    if modify_ssh_parameter "AllowAgentForwarding" "no" "Disable agent forwarding for security"; then
        changes_made=true
    fi
    
    if [[ "$changes_made" == true ]]; then
        log_success "Дополнительные параметры безопасности настроены"
    else
        log_warning "Не удалось применить некоторые настройки безопасности"
    fi
}

# === ГЛАВНАЯ ФУНКЦИЯ МОДУЛЯ ===

# Главная функция SSH Security модуля
configure_ssh_security() {
    log_info "🔐 Запуск модуля SSH Security..."
    echo
    
    # Проверяем права root
    if [[ $EUID -ne 0 ]]; then
        log_error "SSH Security модуль требует права root"
        return 1
    fi
    
    # Проверяем наличие SSH
    if ! systemctl list-unit-files | grep -q "^$SSH_SERVICE"; then
        log_error "SSH сервис не найден в системе"
        return 1
    fi
    
    # Меню модуля
    while true; do
        echo
        echo "=== SSH Security Configuration ==="
        echo "1. 🔧 Изменить SSH порт"
        echo "2. 🔑 Генерировать SSH ключи"
        echo "3. 📥 Установить SSH ключ для авторизации"
        echo "4. 🔒 Отключить парольную авторизацию"
        echo "5. 🚫 Отключить прямой вход под root"
        echo "6. 🛡️ Настроить дополнительную безопасность"
        echo "7. 🔄 Перезапустить SSH сервис"
        echo "8. ℹ️  Показать текущие настройки SSH"
        echo "9. 🚀 Полная настройка SSH безопасности"
        echo "0. ⬅️ Вернуться в главное меню"
        echo
        read -p "Выберите действие [0-9]: " -n 1 -r choice
        echo
        echo
        
        case $choice in
            1) change_ssh_port ;;
            2) generate_ssh_key ;;
            3) install_ssh_key ;;
            4) disable_password_auth ;;
            5) disable_root_login ;;
            6) configure_additional_security ;;
            7) restart_ssh_service ;;
            8) show_current_ssh_config ;;
            9) full_ssh_security_setup ;;
            0) return 0 ;;
            *) log_error "Неверный выбор: '$choice'" ;;
        esac
        
        if [[ "$choice" != "0" ]]; then
            echo
            echo -e "${YELLOW}Нажмите Enter для продолжения...${NC}"
            read -r
        fi
    done
}

# Показ текущих настроек SSH
show_current_ssh_config() {
    log_info "📋 Текущие настройки SSH:"
    echo "═══════════════════════════════════════════════════"
    
    local port=$(grep "^Port" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "22 (default)")
    local password_auth=$(grep "^PasswordAuthentication" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "yes (default)")
    local root_login=$(grep "^PermitRootLogin" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "yes (default)")
    local max_auth=$(grep "^MaxAuthTries" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "6 (default)")
    
    echo "SSH Port: $port"
    echo "Password Authentication: $password_auth"
    echo "Root Login: $root_login"
    echo "Max Auth Tries: $max_auth"
    echo "SSH Service Status: $(systemctl is-active $SSH_SERVICE 2>/dev/null || echo "unknown")"
    
    if [[ -f "${AUTHORIZED_KEYS_DIR}/authorized_keys" ]]; then
        local key_count=$(grep -c "^ssh-" "${AUTHORIZED_KEYS_DIR}/authorized_keys" 2>/dev/null || echo "0")
        echo "Authorized Keys: $key_count ключей"
    else
        echo "Authorized Keys: файл не найден"
    fi
    
    echo "═══════════════════════════════════════════════════"
}

# Полная настройка SSH безопасности
full_ssh_security_setup() {
    log_info "🚀 Запуск полной настройки SSH безопасности..."
    
    log_warning "Эта операция выполнит следующие действия:"
    echo "  1. Генерация SSH ключей"
    echo "  2. Установка ключей для авторизации"
    echo "  3. Изменение SSH порта"
    echo "  4. Отключение парольной авторизации"
    echo "  5. Отключение root входа"
    echo "  6. Настройка дополнительной безопасности"
    echo "  7. Перезапуск SSH сервиса"
    echo
    
    read -p "Продолжить полную настройку? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Полная настройка отменена"
        return 0
    fi
    
    # Выполняем настройку по порядку
    log_info "Шаг 1/7: Генерация SSH ключей..."
    generate_ssh_key
    
    log_info "Шаг 2/7: Установка SSH ключей..."
    install_ssh_key
    
    log_info "Шаг 3/7: Изменение SSH порта..."
    change_ssh_port
    
    log_info "Шаг 4/7: Настройка дополнительной безопасности..."
    configure_additional_security
    
    log_info "Шаг 5/7: Отключение парольной авторизации..."
    disable_password_auth
    
    log_info "Шаг 6/7: Отключение root входа..."
    disable_root_login
    
    log_info "Шаг 7/7: Перезапуск SSH сервиса..."
    if restart_ssh_service; then
        echo
        log_success "🎉 Полная настройка SSH безопасности завершена!"
        
        echo
        log_warning "КРИТИЧЕСКИ ВАЖНЫЕ НАПОМИНАНИЯ:"
        echo "  ✓ Проверьте SSH доступ в новой сессии"
        echo "  ✓ Не закрывайте текущую сессию до проверки"
        echo "  ✓ Обновите клиенты SSH с новым портом"
        echo "  ✓ Настройте файрвол для нового SSH порта"
        echo
    else
        log_error "Ошибка при перезапуске SSH. Проверьте конфигурацию!"
    fi
}

log_success "SSH Security Module загружен успешно"
