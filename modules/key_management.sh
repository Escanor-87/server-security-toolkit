#!/bin/bash

# Key Management Module v1.0
# Модуль управления SSH ключами

# Проверка загрузки модуля
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    echo "ERROR: Key Management Module должен загружаться из main.sh"
    return 1 2>/dev/null || exit 1
fi

# Главная функция модуля
manage_ssh_keys() {
    log_info "🔑 Запуск модуля управления SSH ключами..."
    
    # Вызываем функции из SSH Security модуля
    if declare -f generate_ssh_key &>/dev/null; then
        generate_ssh_key
    else
        log_error "Функция генерации ключей не доступна"
        log_info "Убедитесь, что SSH Security модуль загружен"
    fi
}

log_success "Key Management Module загружен успешно"

