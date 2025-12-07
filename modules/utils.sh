#!/bin/bash

# Utils Module v1.0
# Общие утилиты для всех модулей

# Проверка установки пакета
is_package_installed() {
    local package="$1"
    if dpkg -l 2>/dev/null | grep -q "^ii[[:space:]]*${package}[[:space:]]"; then
        return 0
    fi
    return 1
}

# Установка пакета с проверкой
install_package() {
    local package="$1"
    local description="${2:-$package}"
    
    if is_package_installed "$package"; then
        log_success "$description уже установлен"
        return 0
    fi
    
    log_info "Установка $description..."
    if apt update >/dev/null 2>&1 && apt install -y "$package" >/dev/null 2>&1; then
        log_success "$description установлен"
        return 0
    else
        log_error "Ошибка установки $description"
        return 1
    fi
}

# Проверка доступности порта
is_port_available() {
    local port="$1"
    
    # Проверяем через ss (современная утилита)
    if command -v ss &>/dev/null; then
        if ss -tuln 2>/dev/null | grep -q ":${port}[[:space:]]"; then
            return 1  # Порт занят
        fi
    # Fallback на netstat
    elif command -v netstat &>/dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":${port}[[:space:]]"; then
            return 1  # Порт занят
        fi
    fi
    
    return 0  # Порт свободен
}

# Проверка дискового пространства
check_disk_space() {
    local path="$1"
    local required_mb="${2:-100}"  # 100MB по умолчанию
    
    if [[ ! -d "$path" ]]; then
        path=$(dirname "$path")
    fi
    
    local available_mb
    available_mb=$(df -m "$path" 2>/dev/null | tail -1 | awk '{print $4}')
    
    if [[ -z "$available_mb" ]] || [[ ! "$available_mb" =~ ^[0-9]+$ ]]; then
        log_warning "Не удалось определить доступное место на диске"
        return 0  # Продолжаем, если не можем проверить
    fi
    
    if [[ $available_mb -lt $required_mb ]]; then
        log_error "Недостаточно места на диске: требуется ${required_mb}MB, доступно ${available_mb}MB"
        return 1
    fi
    
    return 0
}

# Безопасное выполнение команды с обработкой ошибок
safe_exec() {
    local desc="$1"
    shift
    local cmd=("$@")
    
    set +e
    "${cmd[@]}"
    local rc=$?
    set -e
    
    if (( rc != 0 )); then
        log_error "Ошибка выполнения '$desc': код $rc"
        return $rc
    fi
    return 0
}

# Проверка версии bash
check_bash_version() {
    local required_version="4.0"
    local current_version
    current_version=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    
    if [[ -z "$current_version" ]]; then
        log_warning "Не удалось определить версию bash"
        return 0
    fi
    
    # Простая проверка версии
    local required_major
    required_major=$(echo "$required_version" | cut -d. -f1)
    local current_major
    current_major=$(echo "$current_version" | cut -d. -f1)
    
    if [[ $current_major -lt $required_major ]]; then
        log_error "Требуется bash >= $required_version, установлен $current_version"
        return 1
    fi
    
    return 0
}

# Проверка прав доступа к файлу/директории
check_file_permissions() {
    local path="$1"
    local check_type="${2:-write}"  # write или read
    
    if [[ "$check_type" == "write" ]]; then
        local dir_path
        dir_path=$(dirname "$path")
        if [[ ! -w "$dir_path" ]] && [[ -e "$dir_path" ]]; then
            log_error "Нет прав на запись в $(dirname "$path")"
            return 1
        fi
    elif [[ "$check_type" == "read" ]]; then
        if [[ ! -r "$path" ]] && [[ -e "$path" ]]; then
            log_error "Нет прав на чтение $path"
            return 1
        fi
    fi
    
    return 0
}

# Получение размера файла в байтах
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Форматирование размера файла (человекочитаемый формат)
format_file_size() {
    local bytes="$1"
    local mb=$((bytes / 1024 / 1024))
    local kb=$((bytes / 1024))
    
    if [[ $mb -gt 0 ]]; then
        echo "${mb}MB"
    elif [[ $kb -gt 0 ]]; then
        echo "${kb}KB"
    else
        echo "${bytes}B"
    fi
}

