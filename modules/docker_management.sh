#!/bin/bash

# Docker Management Module v1.0

# Поиск Docker Compose файлов
find_docker_compose_files() {
    local search_dirs=("$HOME" "/opt" "/var/www" "/srv" "/docker" "/app")
    local compose_files=()
    
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r -d '' file; do
                compose_files+=("$file")
            done < <(find "$dir" -maxdepth 3 -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) -print0 2>/dev/null)
        fi
    done
    
    # Удаляем дубликаты и фильтруем
    local unique_files=()
    for file in "${compose_files[@]}"; do
        # Пропускаем файлы в текущей директории (.)
        local dir_name
        dir_name=$(dirname "$file")
        if [[ "$dir_name" == "." ]]; then
            continue
        fi
        
        local found=false
        for unique in "${unique_files[@]}"; do
            if [[ "$file" == "$unique" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            unique_files+=("$file")
        fi
    done
    
    printf '%s\n' "${unique_files[@]}"
}

# Обновление одного Docker Compose проекта
update_docker_compose() {
    local compose_file="$1"
    local compose_dir
    compose_dir=$(dirname "$compose_file")
    
    log_info "🐳 Обновление $(basename "$compose_file") в $compose_dir"
    
    cd "$compose_dir" || {
        log_error "Не удалось перейти в директорию $compose_dir"
        return 1
    }
    
    # Проверяем, что Docker Compose доступен
    local compose_cmd=""
    if command -v docker-compose &>/dev/null; then
        compose_cmd="docker-compose"
    elif docker compose version &>/dev/null; then
        compose_cmd="docker compose"
    else
        log_error "Docker Compose не найден"
        return 1
    fi
    
    echo
    log_info "Текущие контейнеры:"
    $compose_cmd ps
    
    echo
    log_info "Загрузка новых образов..."
    if $compose_cmd pull; then
        log_success "Образы обновлены"
    else
        log_warning "Не все образы удалось обновить"
    fi
    
    echo
    log_info "Перезапуск контейнеров..."
    if $compose_cmd down && $compose_cmd up -d; then
        log_success "Контейнеры перезапущены (down + up -d)"
    else
        log_error "Ошибка перезапуска контейнеров"
        return 1
    fi
    
    echo
    log_info "Статус после обновления:"
    $compose_cmd ps
    
    # Очистка неиспользуемых образов
    echo
    while true; do
        read -p "Очистить неиспользуемые Docker образы? (y/N): " -n 1 -r
        echo
        case $REPLY in
            [Yy])
                log_info "Очистка неиспользуемых образов..."
                docker image prune -f
                log_success "Очистка завершена"
                break
                ;;
            [Nn]|"")
                log_info "Очистка образов пропущена"
                break
                ;;
            *)
                log_error "Введите 'y' для очистки образов или 'n' для пропуска"
                ;;
        esac
    done
    return 0  # Возврат в меню после завершения обновления
}

# Обновление всех найденных проектов
update_all_docker_projects() {
    local compose_files
    mapfile -t compose_files < <(find_docker_compose_files)
    
    if [[ ${#compose_files[@]} -eq 0 ]]; then
        log_warning "Docker Compose файлы не найдены"
        return 0
    fi
    
    log_info "🚀 Обновление всех Docker проектов (${#compose_files[@]} найдено)"
    echo
    
    local updated_count=0
    local failed_count=0
    
    for compose_file in "${compose_files[@]}"; do
        echo "════════════════════════════════════════════════════════════════"
        log_info "Обработка: $compose_file"
        echo "════════════════════════════════════════════════════════════════"
        
        if update_docker_compose "$compose_file"; then
            ((updated_count++))
            log_success "✅ Проект обновлен: $(dirname "$compose_file")"
        else
            ((failed_count++))
            log_error "❌ Ошибка обновления: $(dirname "$compose_file")"
        fi
        
        echo
        if [[ $compose_file != "${compose_files[-1]}" ]]; then
            while true; do
                read -p "Продолжить со следующим проектом? (Y/n): " -n 1 -r
                echo
                case $REPLY in
                    [Yy]|"")
                        break
                        ;;
                    [Nn])
                        log_info "Обновление прервано пользователем"
                        break 2  # Выход из внешнего цикла
                        ;;
                    *)
                        log_error "Введите 'y' для продолжения или 'n' для остановки"
                        ;;
                esac
            done
        fi
    done
    
    echo
    echo "════════════════════════════════════════════════════════════════"
    log_success "📊 Итоги обновления:"
    echo "• Успешно обновлено: $updated_count"
    echo "• Ошибок: $failed_count"
    echo "• Всего проектов: ${#compose_files[@]}"
    echo "════════════════════════════════════════════════════════════════"
    
    return 0  # Возврат в меню Docker Management
}

# Показать Docker статус
show_docker_status() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Docker Status              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo
    
    # Проверка Docker
    if ! command -v docker &>/dev/null; then
        log_error "Docker не установлен"
        return 1
    fi
    
    # Docker версия
    echo -e "${BLUE}🐳 Docker версия:${NC}"
    docker --version
    echo
    
    # Docker Compose версия
    echo -e "${BLUE}📦 Docker Compose версия:${NC}"
    if command -v docker-compose &>/dev/null; then
        docker-compose --version
    elif docker compose version &>/dev/null; then
        docker compose version
    else
        echo "Docker Compose не найден"
    fi
    echo
    
    # Запущенные контейнеры
    echo -e "${BLUE}🏃 Запущенные контейнеры:${NC}"
    echo "════════════════════════════════════════"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Нет запущенных контейнеров"
    echo
    
    # Все контейнеры
    local total_containers
    total_containers=$(docker ps -a --format "{{.Names}}" 2>/dev/null | wc -l)
    echo -e "${BLUE}📊 Всего контейнеров:${NC} $total_containers"
    
    # Образы
    local total_images
    total_images=$(docker images --format "{{.Repository}}" 2>/dev/null | wc -l)
    echo -e "${BLUE}🖼️  Всего образов:${NC} $total_images"
    
    # Использование диска
    echo
    echo -e "${BLUE}💾 Использование диска Docker:${NC}"
    echo "════════════════════════════════════════"
    docker system df 2>/dev/null || echo "Не удалось получить информацию о диске"
}

# Главное меню Docker Management
docker_management() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║        Docker Management Menu        ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo
        
        # Проверка Docker
        if ! command -v docker &>/dev/null; then
            log_error "Docker не установлен на этой системе"
            echo
            echo "1. 📥 Установить Docker"
            echo "0. 🔙 Назад в главное меню"
            echo
            read -p "Выберите действие [0-1]: " -n 1 -r choice
            echo
            
            case $choice in
                1) install_docker ;;
                0) return 0 ;;
                *) log_error "Неверный выбор"; sleep 1 ;;
            esac
            continue
        fi
        
        echo "1. 🔍 Найти Docker Compose проекты"
        echo "2. 🚀 Обновить все проекты (docker pull + restart)"
        echo "3. 🐳 Обновить конкретный проект"
        echo "4. 📊 Показать статус Docker"
        echo "5. 🧹 Очистка Docker (образы, контейнеры, volumes)"
        echo "6. 📋 Управление контейнерами"
        echo "0. 🔙 Назад в главное меню"
        echo
        read -p "Выберите действие [0-6]: " -n 1 -r choice
        echo
        
        case $choice in
            1) list_docker_projects ;;
            2) update_all_docker_projects ;;
            3) select_and_update_project ;;
            4) show_docker_status ;;
            5) docker_cleanup ;;
            6) manage_containers ;;
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

# Список Docker проектов
list_docker_projects() {
    clear
    log_info "🔍 Поиск Docker Compose проектов"
    echo
    
    local compose_files
    mapfile -t compose_files < <(find_docker_compose_files)
    
    if [[ ${#compose_files[@]} -eq 0 ]]; then
        log_warning "Docker Compose файлы не найдены"
        echo
        echo "Поиск выполнялся в директориях:"
        echo "• $HOME"
        echo "• /opt"
        echo "• /var/www"
        echo "• /srv"
        echo "• /docker"
        echo "• /app"
        echo "• $(pwd) (текущая директория)"
        return 0
    fi
    
    echo -e "${GREEN}📋 Найдено ${#compose_files[@]} Docker Compose проектов:${NC}"
    echo "════════════════════════════════════════════════════════════════"
    
    local i=1
    for compose_file in "${compose_files[@]}"; do
        local dir_name
        dir_name=$(dirname "$compose_file")
        local file_name
        file_name=$(basename "$compose_file")
        
        echo "$i. $dir_name"
        echo "   Файл: $file_name"
        
        # Показываем статус контейнеров если возможно
        local compose_cmd=""
        if command -v docker-compose &>/dev/null; then
            compose_cmd="docker-compose"
        elif docker compose version &>/dev/null; then
            compose_cmd="docker compose"
        fi
        
        if [[ -n "$compose_cmd" ]]; then
            cd "$dir_name" || continue
            local containers
            containers=$($compose_cmd ps --services 2>/dev/null | wc -l)
            local running
            running=$($compose_cmd ps --filter "status=running" --services 2>/dev/null | wc -l)
            echo "   Контейнеры: $running/$containers запущено"
        fi
        
        echo
        ((i++))
    done
}

# Выбор и обновление конкретного проекта
select_and_update_project() {
    clear
    log_info "🐳 Выбор проекта для обновления"
    echo
    
    local compose_files
    mapfile -t compose_files < <(find_docker_compose_files)
    
    if [[ ${#compose_files[@]} -eq 0 ]]; then
        log_warning "Docker Compose файлы не найдены"
        return 0
    fi
    
    echo -e "${BLUE}Доступные проекты:${NC}"
    echo "════════════════════════════════════════"
    
    local i=1
    for compose_file in "${compose_files[@]}"; do
        echo "$i. $(dirname "$compose_file") ($(basename "$compose_file"))"
        ((i++))
    done
    
    echo "0. 🔙 Назад"
    echo
    read -p "Выберите проект [0-$((${#compose_files[@]})): " -r project_choice
    
    if [[ "$project_choice" == "0" ]]; then
        return 0
    fi
    
    if [[ "$project_choice" =~ ^[0-9]+$ ]] && [[ "$project_choice" -ge 1 ]] && [[ "$project_choice" -le ${#compose_files[@]} ]]; then
        local selected_file="${compose_files[$((project_choice-1))]}"
        echo
        log_info "Выбран проект: $(dirname "$selected_file")"
        echo
        update_docker_compose "$selected_file"
    else
        log_error "Неверный выбор"
    fi
}

# Очистка Docker
docker_cleanup() {
    clear
    log_info "🧹 Очистка Docker"
    echo
    
    echo "Выберите тип очистки:"
    echo "1. 🖼️  Удалить неиспользуемые образы"
    echo "2. 📦 Удалить остановленные контейнеры"
    echo "3. 💾 Удалить неиспользуемые volumes"
    echo "4. 🌐 Удалить неиспользуемые networks"
    echo "5. 🧹 Полная очистка (все вышеперечисленное)"
    echo "0. 🔙 Назад"
    echo
    read -p "Выберите действие [0-5]: " -n 1 -r cleanup_choice
    echo
    
    case $cleanup_choice in
        1)
            log_info "Удаление неиспользуемых образов..."
            docker image prune -f
            ;;
        2)
            log_info "Удаление остановленных контейнеров..."
            docker container prune -f
            ;;
        3)
            log_info "Удаление неиспользуемых volumes..."
            docker volume prune -f
            ;;
        4)
            log_info "Удаление неиспользуемых networks..."
            docker network prune -f
            ;;
        5)
            log_warning "⚠️  ВНИМАНИЕ: Будет выполнена полная очистка Docker!"
            read -p "Продолжить? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Полная очистка Docker..."
                docker system prune -af --volumes
                log_success "Очистка завершена"
            else
                log_info "Очистка отменена"
            fi
            ;;
        0) return 0 ;;
        *) log_error "Неверный выбор" ;;
    esac
}

# Управление контейнерами
manage_containers() {
    clear
    log_info "📋 Управление контейнерами"
    echo
    
    # Получаем список контейнеров
    local containers
    mapfile -t containers < <(docker ps --format "{{.Names}}" 2>/dev/null)
    
    if [[ ${#containers[@]} -eq 0 ]]; then
        log_warning "Нет запущенных контейнеров"
        echo
        while true; do
            read -p "Показать все контейнеры (включая остановленные)? (y/N): " -n 1 -r
            echo
            case $REPLY in
                [Yy])
                    mapfile -t containers < <(docker ps -a --format "{{.Names}}" 2>/dev/null)
                    if [[ ${#containers[@]} -eq 0 ]]; then
                        log_error "Контейнеры не найдены"
                        return 0
                    fi
                    break
                    ;;
                [Nn]|"")
                    log_info "Показ запущенных контейнеров отменен"
                    return 0
                    ;;
                *)
                    log_error "Введите 'y' для показа всех контейнеров или 'n' для отмены"
                    ;;
            esac
        done
    fi
    
    echo -e "${BLUE}Доступные контейнеры:${NC}"
    echo "════════════════════════════════════════"
    
    local i=1
    for container in "${containers[@]}"; do
        local status
        status=$(docker ps -a --filter "name=^${container}$" --format "{{.Status}}" 2>/dev/null)
        local image
        image=$(docker ps -a --filter "name=^${container}$" --format "{{.Image}}" 2>/dev/null)
        echo "$i. $container"
        echo "   Образ: $image"
        echo "   Статус: $status"
        echo
        ((i++))
    done
    
    echo "Выберите действие:"
    echo "1. 🔄 Перезапустить контейнер"
    echo "2. ⏹️  Остановить контейнер"
    echo "3. ▶️  Запустить контейнер"
    echo "4. 📋 Показать логи контейнера"
    echo "5. 💻 Войти в контейнер (bash/sh)"
    echo "0. 🔙 Назад"
    echo
    read -p "Выберите действие [0-5]: " -n 1 -r container_choice
    echo
    
    case $container_choice in
        1|2|3|4|5)
            echo
            read -p "Введите номер контейнера [1-${#containers[@]}]: " -r container_num
            
            if [[ ! "$container_num" =~ ^[0-9]+$ ]] || [[ "$container_num" -lt 1 ]] || [[ "$container_num" -gt ${#containers[@]} ]]; then
                log_error "Неверный номер контейнера"
                return 1
            fi
            
            local container_name="${containers[$((container_num-1))]}"
            echo
            log_info "Выбран контейнер: $container_name"
            echo
            
            case $container_choice in
                1)
                    log_info "Перезапуск контейнера $container_name..."
                    docker restart "$container_name"
                    log_success "Контейнер перезапущен"
                    ;;
                2)
                    log_info "Остановка контейнера $container_name..."
                    docker stop "$container_name"
                    log_success "Контейнер остановлен"
                    ;;
                3)
                    log_info "Запуск контейнера $container_name..."
                    docker start "$container_name"
                    log_success "Контейнер запущен"
                    ;;
                4)
                    log_info "Логи контейнера $container_name:"
                    echo "════════════════════════════════════════"
                    docker logs --tail 50 "$container_name"
                    ;;
                5)
                    log_info "Вход в контейнер $container_name..."
                    if docker exec -it "$container_name" bash 2>/dev/null; then
                        :
                    elif docker exec -it "$container_name" sh 2>/dev/null; then
                        :
                    else
                        log_error "Не удалось войти в контейнер"
                    fi
                    ;;
            esac
            ;;
        0) return 0 ;;
        *) log_error "Неверный выбор" ;;
    esac
}

# Установка Docker (базовая)
install_docker() {
    clear
    log_info "📥 Установка Docker"
    echo
    
    log_warning "⚠️  Эта функция выполнит базовую установку Docker"
    echo "Для продакшн-серверов рекомендуется ручная установка"
    echo
    read -p "Продолжить автоматическую установку? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Установка отменена"
        echo
        echo "Для ручной установки используйте:"
        echo "• Ubuntu/Debian: https://docs.docker.com/engine/install/ubuntu/"
        echo "• Другие системы: https://docs.docker.com/engine/install/"
        return 0
    fi
    
    log_info "Обновление пакетов..."
    apt update
    
    log_info "Установка зависимостей..."
    apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    log_info "Добавление GPG ключа Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    log_info "Добавление репозитория Docker..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    log_info "Установка Docker..."
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    log_info "Запуск Docker..."
    systemctl enable docker
    systemctl start docker
    
    if systemctl is-active --quiet docker; then
        log_success "Docker успешно установлен и запущен!"
        echo
        docker --version
        docker compose version
    else
        log_error "Ошибка установки Docker"
    fi
}
