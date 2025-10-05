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
    
    # Показываем предупреждение о том, что будет сделано
    echo -e "${YELLOW}💡 Эта операция выполнит следующие действия:${NC}"
    echo -e "${YELLOW}   • Сбросит все текущие правила UFW${NC}"
    echo -e "${YELLOW}   • Настроит SSH (текущий порт)${NC}"
    echo -e "${YELLOW}   • Откроет HTTP (80) и HTTPS (443)${NC}"
    echo -e "${YELLOW}   • Установит политику: Deny incoming / Allow outgoing${NC}"
    echo
    
    read -p "Продолжить? (Enter = да, 0 = отмена): " -r
    if [[ "$REPLY" == "0" ]]; then
        log_info "Операция отменена"
        return 0
    fi
    
    # Создаем резервную копию текущих правил UFW
    local backup_dir="$SCRIPT_DIR/Backups"
    local backup_file
    backup_file="$backup_dir/ufw_rules_$(date +%Y%m%d_%H%M%S).tar.gz"
    
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
    
    # SSH порт (безопасное определение, не ломается при pipefail)
    local ssh_port
    ssh_port=$(awk '/^Port[[:space:]]+[0-9]+/{p=$2} END{if(p)print p; else print 22}' /etc/ssh/sshd_config 2>/dev/null)
    log_info "Разрешение SSH на порту $ssh_port..."
    exec_logged "ufw allow $ssh_port/tcp" ufw allow "$ssh_port"/tcp || true
    
    # Веб-серверы
    log_info "Разрешение HTTP/HTTPS..."
    exec_logged "ufw allow 80/tcp" ufw allow 80/tcp || true
    exec_logged "ufw allow 443/tcp" ufw allow 443/tcp || true
    
    log_info "Включение UFW..."
    exec_logged "ufw --force enable" ufw --force enable || true
    
    log_success "Базовый файрвол настроен"
    exec_logged "ufw status verbose" ufw status verbose || true
}

# Показать статус UFW
show_firewall_status() {
    clear
    log_info "📋 Статус файрвола"
    echo "════════════════════════════════════════"
    
    if command -v ufw &>/dev/null; then
        exec_logged "ufw status verbose" ufw status verbose || true
        ufw status verbose || true
    else
        echo "UFW не установлен"
    fi
    
    echo "════════════════════════════════════════"
}

# Нормализация строки правила (убираем лишние пробелы)
normalize_firewall_rule_text() {
    local text="$1"
    # Сжимаем повторяющиеся пробелы и обрезаем пробелы по краям
    text=$(echo "$text" | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ //; s/ $//')
    echo "$text"
}

# Поиск текущего номера правила по сохраненной строке
get_current_rule_number() {
    local target_raw="$1"
    local target
    target=$(normalize_firewall_rule_text "$target_raw")

    local status_output
    status_output=$(ufw status numbered 2>/dev/null)

    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*\[[[:space:]]*([0-9]+)\][[:space:]]*(.*)$ ]]; then
            local number="${BASH_REMATCH[1]}"
            local content="${BASH_REMATCH[2]}"
            content=$(normalize_firewall_rule_text "$content")
            if [[ "$content" == "$target" ]]; then
                echo "$number"
                return 0
            fi
        fi
    done <<< "$status_output"

    return 1
}

# Удалить правило (с циклом для множественного удаления)
delete_firewall_rule() {
    while true; do
        clear
        log_info "🗑️ Удаление правила файрвола"
        echo

        if ! command -v ufw &>/dev/null; then
            log_error "UFW не установлен"
            return 1
        fi

        echo -e "${BLUE}Текущие правила UFW:${NC}"
        echo "════════════════════════════════════════"
        ufw status numbered 2>/dev/null || echo "UFW неактивен"
        echo "════════════════════════════════════════"
        echo

        # Получаем список правил с номерами
        local rules_output
        rules_output=$(ufw status numbered 2>/dev/null)

        if [[ -z "$rules_output" ]] || [[ "$rules_output" == *"Status: inactive"* ]]; then
            log_warning "UFW неактивен или нет правил"
            return 0
        fi

        # Извлекаем номера правил
        local rule_numbers=()
        local rule_lines=()
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*\[[[:space:]]*([0-9]+)\][[:space:]]*(.*)$ ]]; then
                local rule_num="${BASH_REMATCH[1]}"
                local rule_text="${BASH_REMATCH[2]}"
                rule_numbers+=("$rule_num")
                rule_lines+=("$(normalize_firewall_rule_text "$rule_text")")
            fi
        done <<< "$rules_output"

        if [[ ${#rule_numbers[@]} -eq 0 ]]; then
            log_info "Нет правил для удаления"
            return 0
        fi

        echo "Введите номер правила для удаления (или 0 для выхода в меню):"
        echo

        local rule_input
        read -p "Номер правила: " -r rule_input

        # Выход в меню
        if [[ "$rule_input" == "0" ]] || [[ -z "$rule_input" ]]; then
            log_info "Возврат в меню файрвола"
            return 0
        fi

        # Проверка корректности ввода
        if [[ ! "$rule_input" =~ ^[0-9]+$ ]]; then
            log_error "Некорректный номер правила: '$rule_input'"
            sleep 2
            continue
        fi

        # Проверка существования правила
        local found=false
        local rule_signature=""
        for idx in "${!rule_numbers[@]}"; do
            if [[ "$rule_input" == "${rule_numbers[$idx]}" ]]; then
                found=true
                rule_signature="${rule_lines[$idx]}"
                break
            fi
        done

        if [[ "$found" == "false" ]]; then
            log_error "Правило #$rule_input не найдено в списке"
            sleep 2
            continue
        fi

        # Подтверждение удаления
        echo
        log_warning "⚠️  Будет удалено правило #$rule_input: $rule_signature"
        echo
        read -p "Подтвердить удаление? (Enter = да, 0 = отмена): " -r

        if [[ "$REPLY" == "0" ]]; then
            log_info "Удаление отменено"
            sleep 1
            continue
        fi

        # Создаём бекап ПЕРЕД удалением правила
        log_info "Создание бекапа текущих правил..."
        local backup_file="$SCRIPT_DIR/Backups/ufw/before_delete_rule_$(date +%Y%m%d_%H%M%S).txt"
        mkdir -p "$SCRIPT_DIR/Backups/ufw"
        ufw status numbered > "$backup_file" 2>/dev/null || log_warning "Не удалось создать бекап"
        
        # Ротация: оставляем только последние 7 бекапов
        local old_backups
        mapfile -t old_backups < <(find "$SCRIPT_DIR/Backups/ufw" -name "before_*.txt" 2>/dev/null | sort -r | tail -n +8)
        for old_backup in "${old_backups[@]}"; do
            rm -f "$old_backup" 2>/dev/null
        done
        
        # Удаление правила
        log_info "Удаление правила #$rule_input..."
        
        local delete_result=0
        # Безопасное подтверждение удаления, с логированием
        if ! exec_logged "ufw delete $rule_input" bash -lc "printf 'y\n' | ufw delete $rule_input"; then
            delete_result=$?
        else
            delete_result=0
        fi
        
        if [[ $delete_result -eq 0 ]]; then
            log_success "Правило #$rule_input удалено успешно"
        else
            log_error "Не удалось удалить правило #$rule_input"
        fi

        echo
        sleep 1
    done
}
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
        "") 
            log_error "Выбор не может быть пустым"
            sleep 2
            return 0
            ;;
        *) 
            log_error "Неверный выбор: '$proto_choice'"
            sleep 2
            return 0
            ;;
    esac
    
    local comment
    read -p "Комментарий (опционально): " -r comment
    
    # Создаём бекап ПЕРЕД добавлением правила
    log_info "Создание бекапа текущих правил..."
    local backup_file="$SCRIPT_DIR/Backups/ufw/before_add_rule_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$SCRIPT_DIR/Backups/ufw"
    ufw status numbered > "$backup_file" 2>/dev/null || log_warning "Не удалось создать бекап"
    
    # Ротация: оставляем только последние 7 бекапов
    local old_backups
    mapfile -t old_backups < <(find "$SCRIPT_DIR/Backups/ufw" -name "before_*.txt" 2>/dev/null | sort -r | tail -n +8)
    for old_backup in "${old_backups[@]}"; do
        rm -f "$old_backup" 2>/dev/null
    done
    
    if [[ -n "$protocol" ]]; then
        if [[ -n "$comment" ]]; then
            exec_logged "ufw allow $port/$protocol comment \"$comment\"" ufw allow "$port"/"$protocol" comment "$comment" || true
        else
            exec_logged "ufw allow $port/$protocol" ufw allow "$port"/"$protocol" || true
        fi
    else
        if [[ -n "$comment" ]]; then
            exec_logged "ufw allow $port comment \"$comment\"" ufw allow "$port" comment "$comment" || true
        else
            exec_logged "ufw allow $port" ufw allow "$port" || true
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
        echo "1. 🛡️  Настроить базовый файрвол"
        echo "2. ➕ Добавить правило"
        echo "3. 🗑️  Удалить правило"
        echo "4. 📋 Показать статус"
        echo "5. 🔙 Восстановить из резервной копии"
        echo "6. 📦 Установить UFW"
        echo "0. ⬅️  Назад в главное меню"
        echo
        read -p "Выберите действие [0-6]: " -n 1 -r choice
        echo
        
        case $choice in
            1) setup_basic_firewall ;;
            2) add_firewall_rule ;;
            3) delete_firewall_rule 
               continue ;;  # delete_firewall_rule имеет свой read, пропускаем общий
            4) show_firewall_status ;;
            5) restore_firewall_backup ;;
            6) install_ufw ;;
            0) return 0 ;;
            *) 
                log_error "Неверный выбор"
                sleep 1
                ;;
        esac
        
        if [[ "$choice" != "0" && "$choice" != "3" ]]; then
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
    
    local backup_dir="$SCRIPT_DIR/Backups/ufw"
    if [[ ! -d "$backup_dir" ]]; then
        log_warning "Директория резервных копий не найдена: $backup_dir"
        return 0
    fi
    
    # Ищем резервные копии UFW (текстовые файлы с правилами)
    local backup_files
    mapfile -t backup_files < <(find "$backup_dir" -type f -name "before_*.txt" 2>/dev/null | sort -r)
    
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
        sleep 2
        return 0
    fi
    
    local selected_backup="${backup_files[$((backup_num-1))]}"
    
    echo
    log_warning "⚠️  ВНИМАНИЕ: Это действие перезапишет текущие правила UFW!"
    echo "Будет восстановлен файл: $(basename "$selected_backup")"
    echo
    read -p "Продолжить восстановление? (Enter = да, 0 = отмена): " -r
    if [[ "$REPLY" == "0" ]]; then
        log_info "Восстановление отменено"
        return 0
    fi
    
    # Создаём резервную копию текущих правил перед восстановлением
    log_info "Создание резервной копии текущих правил..."
    local current_backup_dir="$SCRIPT_DIR/Backups/ufw"
    mkdir -p "$current_backup_dir"
    local current_backup="$current_backup_dir/before_restore_$(date +%Y%m%d_%H%M%S).txt"
    ufw status numbered > "$current_backup" 2>/dev/null
    
    # Восстанавливаем правила
    log_info "Восстановление правил UFW из: $(basename "$selected_backup")"
    
    # Безопасный сброс и базовые политики
    log_warning "Сброс текущих правил UFW..."
    exec_logged "ufw --force reset" ufw --force reset || true
    exec_logged "ufw default deny incoming" ufw default deny incoming || true
    exec_logged "ufw default allow outgoing" ufw default allow outgoing || true
    
    # Fail-safe: разрешаем текущий SSH порт прежде всего
    local ssh_port
    ssh_port=$(grep -E "^Port[[:space:]]+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -1)
    [[ -z "$ssh_port" ]] && ssh_port=22
    log_info "Fail-safe: разрешаем SSH порт $ssh_port/tcp"
    exec_logged "ufw allow $ssh_port/tcp" ufw allow "$ssh_port"/tcp || true
    
    # Применяем правила из бекапа
    log_info "Применение правил из бекапа..."
    local rules_applied=0
    while IFS= read -r line; do
        # Пропускаем пустые строки и заголовки
        [[ -z "$line" || "$line" =~ ^(Status|To|--) ]] && continue
        
        # Форматы:
        # [ n] 443/tcp ALLOW IN Anywhere
        # [ n] 23321/tcp (v6) ALLOW IN Anywhere (v6)
        # [ n] 2222 ALLOW IN 100.67.79.226
        if [[ "$line" =~ \[[[:space:]]*[0-9]+\][[:space:]]+([0-9]+(/[a-z]+)?)([[:space:]]+\(v6\))?[[:space:]]+ALLOW[[:space:]]+IN[[:space:]]+([^[:space:]#]+) ]]; then
            local port="${BASH_REMATCH[1]}"
            local source="${BASH_REMATCH[4]}"
            if [[ "$source" == "Anywhere" || "$source" == "Anywhere (v6)" ]]; then
                log_info "Применение: ufw allow $port"
                # Избегаем дублирования fail-safe SSH
                if [[ "$port" != "$ssh_port" && "$port" != "$ssh_port/tcp" ]]; then
                    if exec_logged "ufw allow $port" ufw allow "$port"; then rules_applied=$((rules_applied+1)); fi
                else
                    log_info "Правило SSH уже применено fail-safe, пропускаем"
                fi
            else
                # Удаляем протокол для конструкции "to any port"
                local ponly
                ponly="${port%/*}"
                log_info "Применение: ufw allow from $source to any port $ponly"
                if exec_logged "ufw allow from $source to any port $ponly" ufw allow from "$source" to any port "$ponly"; then rules_applied=$((rules_applied+1)); fi
            fi
        fi
    done < "$selected_backup"
    
    # Включаем UFW и показываем статус
    log_info "Включение UFW..."
    if exec_logged "ufw --force enable" ufw --force enable; then
        log_success "UFW восстановлен. Применено правил: $rules_applied"
        echo
        exec_logged "ufw status numbered" ufw status numbered || true
    else
        log_error "Ошибка включения UFW"
    fi
    
    echo
    read -p "Нажмите Enter для возврата в меню..." -r
}
