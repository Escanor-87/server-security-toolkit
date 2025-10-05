#!/bin/bash

# Backup Manager Module v1.0
# Централизованная система бекапов с ротацией

readonly BACKUP_ROOT="$SCRIPT_DIR/Backups"
readonly MAX_BACKUPS=7

# Создание структуры директорий для бекапов
init_backup_structure() {
    mkdir -p "$BACKUP_ROOT"/{ssh,ufw,fail2ban,authorized_keys}
    log_info "Структура бекапов инициализирована: $BACKUP_ROOT"
}

# Универсальная функция создания бекапа с ротацией
# Использование: create_backup "категория" "исходный_файл_или_директория" "описание"
create_backup() {
    local category="$1"
    local source="$2"
    local description="${3:-backup}"
    
    local backup_dir="$BACKUP_ROOT/$category"
    mkdir -p "$backup_dir"
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="${description}_${timestamp}"
    
    # Определяем расширение в зависимости от типа источника
    local backup_file
    if [[ -d "$source" ]]; then
        backup_file="$backup_dir/${backup_name}.tar.gz"
        tar -czf "$backup_file" -C "$(dirname "$source")" "$(basename "$source")" 2>/dev/null || {
            log_error "Не удалось создать бекап директории: $source"
            return 1
        }
    elif [[ -f "$source" ]]; then
        backup_file="$backup_dir/${backup_name}"
        cp "$source" "$backup_file" 2>/dev/null || {
            log_error "Не удалось создать бекап файла: $source"
            return 1
        }
    else
        log_error "Источник не найден: $source"
        return 1
    fi
    
    log_success "Бекап создан: $(basename "$backup_file")"
    
    # Ротация: удаляем старые бекапы если их больше MAX_BACKUPS
    rotate_backups "$backup_dir"
    
    echo "$backup_file"
}

# Ротация бекапов: оставляем только последние MAX_BACKUPS
rotate_backups() {
    local backup_dir="$1"
    
    # Подсчитываем количество бекапов
    local backup_count
    backup_count=$(find "$backup_dir" -type f | wc -l)
    
    if [[ $backup_count -gt $MAX_BACKUPS ]]; then
        local to_delete=$((backup_count - MAX_BACKUPS))
        log_info "Удаляем $to_delete старых бекапов..."
        
        # Удаляем самые старые файлы
        find "$backup_dir" -type f -printf '%T+ %p\n' | sort | head -n "$to_delete" | cut -d' ' -f2- | while read -r old_backup; do
            rm -f "$old_backup"
            log_info "Удалён старый бекап: $(basename "$old_backup")"
        done
    fi
}

# Список бекапов для категории
list_backups() {
    local category="$1"
    local backup_dir="$BACKUP_ROOT/$category"
    
    if [[ ! -d "$backup_dir" ]]; then
        echo "Бекапы не найдены для категории: $category"
        return 1
    fi
    
    local backups
    mapfile -t backups < <(find "$backup_dir" -type f -printf '%T+ %p\n' | sort -r | cut -d' ' -f2-)
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "Бекапы не найдены"
        return 1
    fi
    
    echo "Найдено бекапов: ${#backups[@]}"
    echo "════════════════════════════════════════════════════"
    local i=1
    for backup in "${backups[@]}"; do
        local backup_date backup_size
        backup_date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        backup_size=$(stat -c %s "$backup" 2>/dev/null | numfmt --to=iec 2>/dev/null || stat -c %s "$backup" 2>/dev/null)
        echo "$i. $(basename "$backup")"
        echo "   Дата: $backup_date | Размер: $backup_size"
        ((i++))
    done
    echo "════════════════════════════════════════════════════"
}

# Восстановление из бекапа
restore_backup() {
    local category="$1"
    local backup_number="$2"
    local destination="$3"
    
    local backup_dir="$BACKUP_ROOT/$category"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Директория бекапов не найдена: $backup_dir"
        return 1
    fi
    
    local backups
    mapfile -t backups < <(find "$backup_dir" -type f -printf '%T+ %p\n' | sort -r | cut -d' ' -f2-)
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_error "Бекапы не найдены"
        return 1
    fi
    
    if [[ $backup_number -lt 1 ]] || [[ $backup_number -gt ${#backups[@]} ]]; then
        log_error "Неверный номер бекапа"
        return 1
    fi
    
    local selected_backup="${backups[$((backup_number-1))]}"
    
    # Создаём бекап текущего состояния перед восстановлением
    if [[ -e "$destination" ]]; then
        create_backup "$category" "$destination" "before_restore"
    fi
    
    # Восстанавливаем
    if [[ "$selected_backup" == *.tar.gz ]]; then
        tar -xzf "$selected_backup" -C "$(dirname "$destination")" 2>/dev/null || {
            log_error "Не удалось восстановить из архива"
            return 1
        }
    else
        cp "$selected_backup" "$destination" 2>/dev/null || {
            log_error "Не удалось восстановить файл"
            return 1
        }
    fi
    
    log_success "Восстановлено из: $(basename "$selected_backup")"
    return 0
}

# Инициализация при загрузке модуля
init_backup_structure
