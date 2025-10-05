#!/bin/bash

# Docker Management Module - DISABLED
# Модуль временно отключен

find_docker_compose_files() {
    # Поиск docker-compose файлов в безопасных директориях
    local roots=("/opt" "/srv" "/var/www" "/docker" "/app" "$HOME" "/root")
    local patterns=("docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml")
    local results=()

    for root in "${roots[@]}"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r -d '' file; do
            results+=("$file")
        done < <(find "$root" -maxdepth 4 -type f \( -name "${patterns[0]}" -o -name "${patterns[1]}" -o -name "${patterns[2]}" -o -name "${patterns[3]}" \) -print0 2>/dev/null)
    done

    # Уникализация и сортировка
    if [[ ${#results[@]} -gt 0 ]]; then
        printf '%s\n' "${results[@]}" | awk '!seen[$0]++' | sort -u
    fi
}

get_compose_cmd() {
    # Определяем доступную команду docker compose
    if docker compose version &>/dev/null; then
        echo "docker compose"
        return 0
    elif command -v docker-compose &>/dev/null; then
        echo "docker-compose"
        return 0
    else
        return 1
    fi
}

update_docker_compose() {
    local compose_file="$1"
    local quiet="${2:-yes}"   # yes = не задавать вопросы

    local cmd
    cmd=$(get_compose_cmd) || { log_error "Docker Compose не найден"; return 1; }

    local dir base
    dir=$(dirname "$compose_file"); base=$(basename "$compose_file")
    log_info "🐳 Обновление $base в $dir"

    # Текущие контейнеры проекта
    $cmd -f "$compose_file" ps || true

    # Pull и перезапуск
    log_info "Загрузка новых образов..."
    $cmd -f "$compose_file" pull || log_warning "Не все образы удалось обновить"

    log_info "Перезапуск контейнеров..."
    if $cmd -f "$compose_file" down && $cmd -f "$compose_file" up -d; then
        log_success "Контейнеры перезапущены"
    else
        log_error "Ошибка перезапуска контейнеров"
        return 1
    fi

    # Итоговый статус
    log_info "Статус после обновления:"
    $cmd -f "$compose_file" ps || true

    if [[ "$quiet" != "yes" ]]; then
        echo
        read -p "Нажмите Enter для возврата..." -r
    fi
    return 0
}

update_all_docker_projects() {
    local files
    mapfile -t files < <(find_docker_compose_files)
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warning "Docker Compose файлы не найдены"
        return 0
    fi

    local cmd
    cmd=$(get_compose_cmd) || { log_error "Docker Compose не найден"; return 1; }

    log_info "🚀 Обновление всех Docker проектов (${#files[@]} найдено)"
    echo
    local ok=0 fail=0
    for f in "${files[@]}"; do
        echo "════════════════════════════════════════════════════════════════"
        log_info "Обработка: $f"
        echo "════════════════════════════════════════════════════════════════"
        if update_docker_compose "$f" "yes"; then
            ((ok++))
            log_success "✅ Проект обновлен: $(dirname "$f")"
        else
            ((fail++))
            log_error "❌ Ошибка обновления: $(dirname "$f")"
        fi
        echo
        sleep 1
    done

    echo
    echo "════════════════════════════════════════════════════════════════"
    log_success "📊 Итоги обновления:"
    echo "• Успешно: $ok"
    echo "• Ошибок: $fail"
    echo "• Всего: ${#files[@]}"
    echo "════════════════════════════════════════════════════════════════"

    # Предложить очистку один раз
    if [[ $ok -gt 0 ]]; then
        echo
        read -p "Очистить неиспользуемые Docker образы? (y/N): " -n 1 -r ans; echo
        if [[ $ans =~ ^[Yy]$ ]]; then
            log_info "Очистка неиспользуемых образов..."
            docker image prune -f || log_warning "Не удалось очистить образы"
            log_success "Очистка завершена"
        else
            log_info "Очистка пропущена"
        fi
    fi

    echo
    read -p "Нажмите Enter для возврата в меню..." -r
    return 0
}

show_docker_status() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Docker Status              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo
    if ! command -v docker &>/dev/null; then
        log_error "Docker не установлен"
        echo; read -p "Нажмите Enter для возврата..." -r; return 0
    fi
    echo -e "${BLUE}🐳 Docker версия:${NC}"; docker --version; echo
    echo -e "${BLUE}📦 Docker Compose версия:${NC}"
    if docker compose version &>/dev/null; then docker compose version; 
    elif command -v docker-compose &>/dev/null; then docker-compose --version; else echo "Не найден"; fi
    echo
    echo -e "${BLUE}🏃 Запущенные контейнеры:${NC}"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" || true
    echo
    echo -e "${BLUE}💾 Использование диска:${NC}"
    docker system df || true
    echo; read -p "Нажмите Enter для возврата..." -r
}

docker_management() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║           Docker Management          ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo
        echo "1. 🔍 Найти Docker Compose проекты"
        echo "2. 🚀 Обновить все проекты (pull + restart)"
        echo "3. 🐳 Обновить конкретный проект"
        echo "4. 📊 Показать статус Docker"
        echo "5. 🧹 Очистка (images)"
        echo "0. 🔙 Назад"
        echo
        read -p "Выберите действие [0-5]: " -n 1 -r choice; echo
        case $choice in
            1) list_docker_projects ;;
            2) update_all_docker_projects ;;
            3) select_and_update_project ;;
            4) show_docker_status ;;
            5) docker_cleanup ;;
            0) return 0 ;;
            *) log_error "Неверный выбор"; sleep 1 ;;
        esac
    done
}

list_docker_projects() {
    clear
    log_info "🔍 Поиск Docker Compose проектов"
    echo
    local files
    mapfile -t files < <(find_docker_compose_files)
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warning "Docker Compose файлы не найдены"
        echo
        read -p "Нажмите Enter для возврата..." -r
        return 0
    fi

    echo "📋 Найдено ${#files[@]} проектов:"
    echo "════════════════════════════════════════════════════════"
    local i=1
    for f in "${files[@]}"; do
        local dir base
        dir=$(dirname "$f"); base=$(basename "$f")
        echo "$i. $dir"
        echo "   Файл: $base"
        echo "────────────────────────────────────────────────────────"
        ((i++))
    done
    echo
    read -p "Нажмите Enter для возврата..." -r
    return 0
}

select_and_update_project() {
    clear
    log_info "🐳 Выбор проекта для обновления"
    echo
    local files
    mapfile -t files < <(find_docker_compose_files)
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warning "Проекты не найдены"; echo; read -p "Enter для возврата..." -r; return 0
    fi
    local i=1
    for f in "${files[@]}"; do
        echo "$i) $(dirname "$f") ($(basename "$f"))"; ((i++))
    done
    echo "0) Назад"; echo
    read -p "Выберите проект [0-$((i-1))]: " -r n; echo
    [[ "$n" == "0" ]] && return 0
    if [[ ! "$n" =~ ^[0-9]+$ ]] || (( n<1 || n>i-1 )); then log_error "Неверный выбор"; sleep 1; return 0; fi
    local sel="${files[$((n-1))]}"
    update_docker_compose "$sel" "no"
}

docker_cleanup() {
    clear
    log_info "🧹 Очистка Docker образов"
    echo
    read -p "Удалить неиспользуемые образы? (y/N): " -n 1 -r ans; echo
    if [[ $ans =~ ^[Yy]$ ]]; then
        docker image prune -f || log_warning "Не удалось очистить образы"
        log_success "Очистка завершена"
    else
        log_info "Очистка пропущена"
    fi
    echo; read -p "Нажмите Enter для возврата..." -r
    return 0
}

manage_containers() {
    clear
    log_info "📋 Управление контейнерами"
    echo
    local names
    mapfile -t names < <(docker ps -a --format '{{.Names}}')
    if [[ ${#names[@]} -eq 0 ]]; then log_warning "Контейнеров не найдено"; read -p "Enter..." -r; return 0; fi
    local i=1
    for n in "${names[@]}"; do echo "$i) $n"; ((i++)); done; echo "0) Назад"; echo
    read -p "Выберите контейнер [0-$((i-1))]: " -r k; echo
    [[ "$k" == "0" ]] && return 0
    if [[ ! "$k" =~ ^[0-9]+$ ]] || (( k<1 || k>i-1 )); then log_error "Неверный выбор"; sleep 1; return 0; fi
    local cname="${names[$((k-1))]}"
    echo "1) 🔄 Перезапустить  2) ⏹️ Остановить  3) ▶️ Запустить  4) 📋 Логи  0) Назад"; echo
    read -p "Действие [0-4]: " -n 1 -r act; echo
    case $act in
        1) docker restart "$cname" && log_success "Перезапущен" || log_error "Ошибка" ;;
        2) docker stop "$cname" && log_success "Остановлен" || log_error "Ошибка" ;;
        3) docker start "$cname" && log_success "Запущен" || log_error "Ошибка" ;;
        4) docker logs --tail 100 "$cname"; echo; read -p "Enter для возврата..." -r ;;
        0) return 0 ;;
        *) log_error "Неверный выбор" ;;
    esac
    echo; read -p "Нажмите Enter для возврата..." -r
    return 0
}
