#!/bin/bash

# Server Security Toolkit v1.0
# Модульный инструмент безопасности для Ubuntu серверов

set -euo pipefail

# Версия скрипта (автоматически на основе числа коммитов)
# Формат: 0.<десятки коммитов>.<единицы коммитов>, напр. 68 коммитов -> 0.6.8
# Безопасно при отсутствии .git (не падаем под set -euo pipefail)
commit_count=$( (git rev-list --count HEAD 2>/dev/null) || echo 0 )
VERSION=$(awk -v n="$commit_count" 'BEGIN{printf "0.%d.%d", int(n/10), n%10}')
if [[ -z "$VERSION" ]]; then VERSION="0.0.0"; fi
# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Store original script arguments for restart functionality
ORIGINAL_ARGS=("$@")

# Директории проекта - исправляем SC2155 и поддерживаем символические ссылки
if [[ -L "${BASH_SOURCE[0]}" ]]; then
    # Если запущен через символическую ссылку, получаем реальный путь
    SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
else
    # Обычное определение директории
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
readonly SCRIPT_DIR
readonly MODULES_DIR="${SCRIPT_DIR}/modules"
# Логи теперь хранятся в отдельной папке logs в директории скрипта
readonly LOGS_DIR="${SCRIPT_DIR}/logs"

# Создаем папку логов
mkdir -p "$LOGS_DIR"

# Файл логов - теперь один файл на все время работы, с ротацией по размеру
LOG_FILE="${LOGS_DIR}/security-toolkit.log"
readonly LOG_FILE

# Конфигурация ротации логов
readonly MAX_LOG_FILES=3  # Оставляем только последние 3 файла
readonly MAX_LOG_SIZE=$((5 * 1024 * 1024))  # 5MB вместо 10MB для более частой ротации

# Функция очистки старых логов (оставляет только последние N файлов)
cleanup_old_logs() {
    local keep_count="${1:-$MAX_LOG_FILES}"
    
    # Получаем список всех лог-файлов (включая текущий и архивные)
    local all_logs=()
    while IFS= read -r -d '' log_file; do
        all_logs+=("$log_file")
    done < <(find "${LOGS_DIR}" -maxdepth 1 -name "security-toolkit*.log" -type f -print0 2>/dev/null)
    
    # Если файлов меньше или равно нужному количеству - ничего не делаем
    if [[ ${#all_logs[@]} -le $keep_count ]]; then
        return 0
    fi
    
    # Сортируем по времени модификации (старые первыми)
    local sorted_logs=()
    if command -v stat &>/dev/null; then
        # Используем stat для получения времени модификации
        while IFS= read -r line; do
            [[ -n "$line" ]] && sorted_logs+=("$line")
        done < <(for log in "${all_logs[@]}"; do
            local mtime
            mtime=$(stat -f '%m %N' "$log" 2>/dev/null || stat -c '%Y %n' "$log" 2>/dev/null)
            echo "$mtime"
        done | sort -n | cut -d' ' -f2-)
    else
        # Fallback: сортируем по имени (timestamp в имени файла)
        mapfile -t sorted_logs < <(printf '%s\n' "${all_logs[@]}" | sort)
    fi
    
    # Удаляем старые файлы (оставляем только последние keep_count)
    local to_delete=$((${#sorted_logs[@]} - keep_count))
    if [[ $to_delete -gt 0 ]]; then
        local deleted=0
        for ((i=0; i<to_delete; i++)); do
            local old_file="${sorted_logs[i]}"
            if [[ -f "$old_file" ]] && [[ "$old_file" != "$LOG_FILE" ]]; then
                rm -f "$old_file" 2>/dev/null && ((deleted++))
            fi
        done
        if [[ $deleted -gt 0 ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Удалено старых логов: $deleted" >> "$LOG_FILE" 2>/dev/null || true
        fi
    fi
}

# Функция ротации логов
rotate_logs() {
    # Проверяем размер файла логов
    if [[ -f "$LOG_FILE" ]]; then
        local file_size
        file_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
        
        if [[ $file_size -gt $MAX_LOG_SIZE ]]; then
            local timestamp
            timestamp=$(date '+%Y%m%d_%H%M%S')
            local backup_file="${LOGS_DIR}/security-toolkit-${timestamp}.log"
            
            # Перемещаем текущий лог в архив
            mv "$LOG_FILE" "$backup_file" 2>/dev/null || true
            
            # Логируем ротацию (в новый файл, так как старый перемещен)
            {
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Лог файл был ротирован: $(basename "$backup_file")"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Размер предыдущего лога: $((file_size / 1024 / 1024))MB"
            } >> "$LOG_FILE" 2>/dev/null || true
        fi
    fi
    
    # Всегда очищаем старые логи (оставляем только последние MAX_LOG_FILES)
    cleanup_old_logs "$MAX_LOG_FILES"
}

# Устанавливаем ловушки для диагностики неожиданных выходов
install_traps() {
    set -E
    trap 'rc=$?; log_error "ERR trap: cmd=\"$BASH_COMMAND\" rc=$rc at ${BASH_SOURCE[0]}:$LINENO (func=${FUNCNAME[*]})"' ERR
    trap 'rc=$?; if (( rc != 0 )); then log_info "EXIT trap: rc=$rc. Если rc!=0 — смотрите предыдущие [COMMAND]/[ERROR] записи."; fi' EXIT
}

# Отображение сводки изменений перед применением
show_changes_summary() {
    local title="$1"
    shift
    local changes=("$@")
    
    echo
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Сводка предстоящих изменений               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}$title${NC}"
    echo
    
    if [[ ${#changes[@]} -gt 0 ]]; then
        for change in "${changes[@]}"; do
            echo -e "  ${GREEN}→${NC} $change"
        done
    else
        echo -e "  ${YELLOW}Нет изменений${NC}"
    fi
    
    echo
}

# Безопасный запуск действий меню: не даёт всему скрипту завершиться при ошибке
run_action() {
    local desc="$1"; shift
    set +e
    "$@"
    local rc=$?
    set -e
    if (( rc != 0 )); then
        log_error "Действие '$desc' завершилось с кодом $rc"
        return $rc
    fi
    return 0
}

# Функция санитизации логов (удаление чувствительных данных)
# ИСПРАВЛЕНО: Фильтрация чувствительных данных
sanitize_log() {
    local text="$1"
    
    # Удаляем SSH приватные ключи
    text=$(echo "$text" | sed 's/-----BEGIN.*PRIVATE KEY-----.*-----END.*PRIVATE KEY-----/[REDACTED_PRIVATE_KEY]/g')
    
    # Удаляем SSH публичные ключи (частично, оставляем только тип и fingerprint)
    text=$(echo "$text" | sed 's/ssh-[a-z0-9-]\+ [A-Za-z0-9+\/=]\{100,\}/[REDACTED_PUBLIC_KEY]/g')
    
    # Удаляем пароли в различных форматах
    text=$(echo "$text" | sed 's/password[=:][^[:space:]]*/password=[REDACTED]/gi')
    text=$(echo "$text" | sed 's/PASSWORD[=:][^[:space:]]*/PASSWORD=[REDACTED]/g')
    text=$(echo "$text" | sed 's/--password[= ][^[:space:]]*/--password=[REDACTED]/gi')
    
    # Удаляем токены и API ключи
    text=$(echo "$text" | sed 's/\(api[_-]key\|token\|secret\)[=:][^[:space:]]*/\1=[REDACTED]/gi')
    
    # Удаляем длинные строки, похожие на ключи (более 50 символов без пробелов)
    text=$(echo "$text" | sed 's/[A-Za-z0-9+\/=]\{50,\}/[REDACTED_LONG_STRING]/g')
    
    echo "$text"
}

# Функции логирования с санитизацией
log_info() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local sanitized_msg
    sanitized_msg=$(sanitize_log "$1")
    echo -e "${BLUE}[$timestamp] [INFO]${NC} $sanitized_msg" | tee -a "$LOG_FILE"
}

log_success() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local sanitized_msg
    sanitized_msg=$(sanitize_log "$1")
    echo -e "${GREEN}[$timestamp] [SUCCESS]${NC} $sanitized_msg" | tee -a "$LOG_FILE"
}

log_warning() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local sanitized_msg
    sanitized_msg=$(sanitize_log "$1")
    echo -e "${YELLOW}[$timestamp] [WARNING]${NC} $sanitized_msg" | tee -a "$LOG_FILE"
}

log_error() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local sanitized_msg
    sanitized_msg=$(sanitize_log "$1")
    echo -e "${RED}[$timestamp] [ERROR]${NC} $sanitized_msg" | tee -a "$LOG_FILE"
}

# Простой прогресс-индикатор
show_progress() {
    local message="$1"
    local duration=${2:-3}
    echo -ne "${BLUE}$message${NC}"
    for ((i=0; i<duration; i++)); do
        sleep 1
        echo -n "."
    done
    echo -e " ${GREEN}✓${NC}"
}

# Запуск команды с расширенным логированием: команда, код выхода, STDOUT/STDERR
# ИСПРАВЛЕНО: Безопасная работа с временными файлами
exec_logged() {
    local desc="$1"; shift
    local timestamp cmd_str rc stdout_file stderr_file
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    cmd_str="$*"
    
    # Создаем временные файлы с безопасным шаблоном
    stdout_file=$(mktemp "${TMPDIR:-/tmp}/sst-stdout-XXXXXX" 2>/dev/null || mktemp /tmp/sst-stdout-XXXXXX)
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/sst-stderr-XXXXXX" 2>/dev/null || mktemp /tmp/sst-stderr-XXXXXX)
    
    # Устанавливаем trap для гарантированной очистки
    trap "rm -f '$stdout_file' '$stderr_file'" EXIT INT TERM
    
    # Не даём set -e оборвать выполнение внутри
    set +e
    "$@" >"$stdout_file" 2>"$stderr_file"
    rc=$?
    set -e
    
    {
        echo "[$timestamp] [COMMAND] $desc"
        echo "  cwd: $(pwd)"
        echo "  cmd: $cmd_str"
        echo "  exit: $rc"
        if [[ -s "$stdout_file" ]]; then
            echo "  --- STDOUT ---"
            cat "$stdout_file"
        fi
        if [[ -s "$stderr_file" ]]; then
            echo "  --- STDERR ---"
            cat "$stderr_file"
        fi
        echo "  ---------------"
    } >> "$LOG_FILE"
    
    # Удаляем временные файлы и снимаем trap
    rm -f "$stdout_file" "$stderr_file"
    trap - EXIT INT TERM
    
    return $rc
}

# Логирование изменений конфигурации
log_config_change() {
    local file="$1"
    local change="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [CONFIG] $file: $change" >> "$LOG_FILE"
}

# Единая функция для определения текущего SSH порта
# Возвращает порт или 22 по умолчанию
get_ssh_port() {
    local ssh_config="/etc/ssh/sshd_config"
    local port
    
    # Пытаемся извлечь порт из конфигурации
    if [[ -f "$ssh_config" ]]; then
        port=$(grep -E "^[[:space:]]*Port[[:space:]]+[0-9]+" "$ssh_config" | tail -1 | awk '{print $2}')
    fi
    
    # Если порт не найден или некорректен, возвращаем 22
    if [[ -z "$port" ]] || [[ ! "$port" =~ ^[0-9]+$ ]]; then
        port="22"
    fi
    
    echo "$port"
}

# Валидация SSH порта
# ИСПРАВЛЕНО: Добавлена валидация портов
validate_ssh_port() {
    local port="$1"
    
    # Проверка на пустое значение
    if [[ -z "$port" ]]; then
        log_error "Порт не может быть пустым"
        return 1
    fi
    
    # Проверка на числовое значение
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        log_error "Порт должен быть числом: $port"
        return 1
    fi
    
    # Проверка диапазона
    if [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
        log_error "Порт должен быть в диапазоне 1-65535: $port"
        return 1
    fi
    
    # Проверка на привилегированные порты (для не-root пользователей)
    if [[ $port -lt 1024 ]] && [[ $EUID -ne 0 ]]; then
        log_error "Порты < 1024 требуют root прав. Текущий порт: $port"
        return 1
    fi
    
    # Проверка на занятость порта
    if ! is_port_available "$port"; then
        log_warning "Порт $port уже занят, но это может быть нормально для SSH"
        # Не возвращаем ошибку, так как SSH может уже слушать этот порт
    fi
    
    return 0
}

# Проверка, занят ли порт (для валидации)
# Возвращает 0 если порт свободен, 1 если занят
is_port_available() {
    local port="$1"
    
    # Проверяем через ss (современная утилита)
    if command -v ss &>/dev/null; then
        if ss -tuln | grep -q ":${port}[[:space:]]"; then
            return 1  # Порт занят
        fi
    # Fallback на netstat
    elif command -v netstat &>/dev/null; then
        if netstat -tuln | grep -q ":${port}[[:space:]]"; then
            return 1  # Порт занят
        fi
    fi
    
    return 0  # Порт свободен
}

# Функция для отображения заголовка
show_header() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════╗"
    echo "║       Server Security Toolkit v${VERSION}      ║"
    echo "║     Ubuntu/Debian Server Hardening Script      ║"
    echo "╚════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

# Проверка прав root
check_root() {
    log_info "Проверка прав root..."
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен запускаться с правами root"
        log_info "Запустите: sudo bash $0"
        return 1
    fi
    log_success "Права root подтверждены"
}

# Проверка операционной системы - исправляем SC1091
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Не удается определить операционную систему"
        return 1
    fi
    
    # shellcheck disable=SC1091
    source /etc/os-release
    
    case "$ID" in
        ubuntu)
            log_info "Обнаружена поддерживаемая ОС: $PRETTY_NAME"
            ;;
        debian)
            if [[ "$VERSION_ID" == "12" ]]; then
                log_info "Обнаружена поддерживаемая ОС: $PRETTY_NAME"
            else
                log_warning "Обнаружен Debian $VERSION_ID. Рекомендуется Debian 12"
                log_info "Обнаружена ОС: $PRETTY_NAME"
                read -p "Продолжить выполнение? (Enter = да, 0 = отмена): " -r
                echo
                if [[ "$REPLY" == "0" ]]; then
                    log_info "Выполнение прервано пользователем"
        return 1
                fi
            fi
            ;;
        *)
            log_warning "Скрипт оптимизирован для Ubuntu и Debian 12"
            log_info "Обнаружена ОС: $PRETTY_NAME"
            read -p "Продолжить выполнение? (Enter = да, 0 = отмена): " -r
            echo
            if [[ "$REPLY" == "0" ]]; then
                log_info "Выполнение прервано пользователем"
        return 1
            fi
            ;;
    esac
}

# Проверка системных требований
check_requirements() {
    log_info "Проверка системных требований..."
    local missing_tools=()
    local required_tools=("ssh" "systemctl" "sed" "grep" "awk")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
            log_warning "Инструмент не найден: $tool"
        else
            log_info "Инструмент найден: $tool"
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Отсутствуют необходимые инструменты: ${missing_tools[*]}"
        return 1
    fi
    
    log_success "Все системные требования выполнены"
}

# Загрузка модулей
load_modules() {
    log_info "Загрузка модулей из $MODULES_DIR"
    local loaded_count=0
    
    # Сначала загружаем utils.sh, если он существует
    local utils_module="${MODULES_DIR}/utils.sh"
    if [[ -f "$utils_module" ]]; then
        log_info "Загружаем модуль: utils.sh"
        # shellcheck source=/dev/null
        if source "$utils_module"; then
            log_success "Модуль utils.sh загружен успешно"
            ((loaded_count++))
        else
            log_warning "Не удалось загрузить utils.sh (продолжаем без него)"
        fi
    fi
    
    # Затем загружаем остальные модули
    for module in "${MODULES_DIR}"/*.sh; do
        # Пропускаем utils.sh, так как он уже загружен
        if [[ "$(basename "$module")" == "utils.sh" ]]; then
            continue
        fi
        
        if [[ -f "$module" ]]; then
            local module_name
            module_name=$(basename "$module")
            log_info "Загружаем модуль: $module_name"
            
            # shellcheck source=/dev/null
            if source "$module"; then
                log_success "Модуль $module_name загружен успешно"
                ((loaded_count++))
            else
                log_error "Ошибка загрузки модуля: $module_name"
                return 1
            fi
        fi
    done
    
    if [[ $loaded_count -eq 0 ]]; then
        log_error "Не найдено ни одного модуля в $MODULES_DIR"
        return 1
    fi
    
    log_success "Загружено модулей: $loaded_count"
}

# Функция для получения статуса сервиса с цветовым индикатором
get_service_status() {
    local service=$1
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "${GREEN}🟢${NC}"
    elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        echo -e "${YELLOW}🟡${NC}"
    else
        echo -e "${RED}🔴${NC}"
    fi
}

# Главное меню
show_menu() {
    show_header
    
    # Показываем уведомление об обновлении если оно доступно
    if [[ "$UPDATE_AVAILABLE" == "true" ]]; then
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║                     ОБНОВЛЕНИЕ ДОСТУПНО!                      ║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo
    fi
    
    # Получаем статусы для индикаторов
    local ssh_status ufw_status f2b_status
    ssh_status=$(get_service_status ssh)
    ufw_status=$(get_service_status ufw)
    f2b_status=$(get_service_status fail2ban)
    
    echo "🔧 Выберите действие:"
    echo
    echo "1. 🚀 Full Security Setup     - Интерактивная настройка"
    echo "2. 🔐 SSH Security ${ssh_status}          - Настройка SSH"
    echo "3. 🛡️  Firewall Setup ${ufw_status}       - Настройка UFW"
    echo "4. 🔧 System Hardening ${f2b_status}      - fail2ban, обновления"
    echo "5. 🐳 Docker Management        - Управление контейнерами"
    echo "6. 📊 System Status            - Статус системы"
    echo "7. 📋 View Logs                - Просмотр логов"
    
    # Добавляем пункт обновления если обновление доступно
    if [[ "$UPDATE_AVAILABLE" == "true" ]]; then
        echo "8. 🔄 Update Toolkit           - Обновить"
        echo "9. 🗑️  Uninstall               - Удалить"
        echo
        echo -e "${YELLOW}[q=выход, h=помощь]${NC}"
        echo
        echo -n "Выберите [0-9/q/h]: "
    else
        echo "8. 🗑️  Uninstall               - Удалить"
        echo
        echo -e "${YELLOW}[q=выход, h=помощь]${NC}"
        echo
        echo -n "Выберите [0-8/q/h]: "
    fi
}

# Анализ безопасности и рекомендации
analyze_security() {
    local recommendations=()
    local warnings=()
    local ok_items=()
    
    # Проверка SSH
    if [[ -f /etc/ssh/sshd_config ]]; then
        local ssh_port password_auth root_login
        ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
        password_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "yes")
        root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "yes")
        
        if [[ "$ssh_port" == "22" ]]; then
            warnings+=("SSH использует стандартный порт 22")
            recommendations+=("2. SSH Security → Смена SSH порта")
        else
            ok_items+=("SSH порт: $ssh_port (изменён)")
        fi
        
        if [[ "$password_auth" == "yes" ]]; then
            warnings+=("Парольная авторизация SSH включена")
            recommendations+=("2. SSH Security → Отключение парольной авторизации")
        else
            ok_items+=("Парольная авторизация: отключена")
        fi
        
        if [[ "$root_login" == "yes" ]]; then
            warnings+=("Root доступ по SSH разрешён")
            recommendations+=("2. SSH Security → Отключение root доступа")
        else
            ok_items+=("Root доступ: запрещён/ограничен")
        fi
        
        # Проверка наличия SSH ключей
        if [[ ! -f /root/.ssh/authorized_keys ]] || [[ ! -s /root/.ssh/authorized_keys ]]; then
            warnings+=("Нет SSH ключей в authorized_keys")
            recommendations+=("2. SSH Security → Импорт/генерация ключей")
        else
            local key_count
            key_count=$(grep -c "^ssh-" /root/.ssh/authorized_keys 2>/dev/null || echo "0")
            ok_items+=("SSH ключи: $key_count")
        fi
    fi
    
    # Проверка UFW
    if command -v ufw &>/dev/null; then
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1 | awk '{print $2}')
        if [[ "$ufw_status" != "active" ]]; then
            warnings+=("Firewall UFW не активен")
            recommendations+=("3. Firewall Setup → Базовая настройка")
        else
            ok_items+=("UFW: активен")
        fi
    else
        warnings+=("UFW не установлен")
        recommendations+=("3. Firewall Setup → Установка UFW")
    fi
    
    # Проверка fail2ban
    if command -v fail2ban-client &>/dev/null; then
        if systemctl is-active --quiet fail2ban; then
            ok_items+=("fail2ban: активен")
        else
            warnings+=("fail2ban установлен, но не запущен")
            recommendations+=("4. System Hardening → Настройка fail2ban")
        fi
    else
        warnings+=("fail2ban не установлен")
        recommendations+=("4. System Hardening → Установка fail2ban")
    fi
    
    # Вывод результатов
    echo
    if [[ ${#ok_items[@]} -gt 0 ]]; then
        echo -e "${GREEN}✅ Всё хорошо:${NC}"
        for item in "${ok_items[@]}"; do
            echo -e "  ${GREEN}•${NC} $item"
        done
        echo
    fi
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Требует внимания:${NC}"
        for warning in "${warnings[@]}"; do
            echo -e "  ${YELLOW}•${NC} $warning"
        done
        echo
    fi
    
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        echo -e "${BLUE}💡 Рекомендуемые действия:${NC}"
        # Удаляем дубликаты
        local unique_recs=()
        for rec in "${recommendations[@]}"; do
            local pattern=" $rec "
            if [[ ! " ${unique_recs[*]} " =~ $pattern ]]; then
                unique_recs+=("$rec")
            fi
        done
        for rec in "${unique_recs[@]}"; do
            echo -e "  ${BLUE}→${NC} $rec"
        done
        echo
    fi
    
    # Всегда возвращаем успешный код (функция информационная)
    return 0
}

# Показать справку
show_help() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Server Security Toolkit - Справка    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${GREEN}Горячие клавиши:${NC}"
    echo "  q - Выход из программы"
    echo "  h - Показать эту справку"
    echo "  0 - Выход"
    echo
    echo -e "${GREEN}Цветовые индикаторы статуса:${NC}"
    echo -e "  ${GREEN}🟢${NC} - Сервис активен и работает"
    echo -e "  ${YELLOW}🟡${NC} - Сервис включён, но не запущен"
    echo -e "  ${RED}🔴${NC} - Сервис отключён или не установлен"
    echo
    echo -e "${GREEN}Основные команды:${NC}"
    echo "  sst          - Запустить Security Toolkit"
    echo "  f2b list     - Показать забаненные IP (fail2ban)"
    echo "  f2b status   - Статус fail2ban"
    echo "  f2b help     - Справка по fail2ban"
    echo
    echo -e "${GREEN}Рекомендуемый порядок настройки:${NC}"
    echo "  1. SSH Security → Импорт/генерация ключей"
    echo "  2. SSH Security → Смена SSH порта"
    echo "  3. Firewall Setup → Базовая настройка UFW"
    echo "  4. System Hardening → Установка fail2ban"
    echo "  5. SSH Security → Отключение парольной авторизации"
    echo
    echo -e "${YELLOW}Файлы логов:${NC} $LOGS_DIR/security-toolkit.log"
    echo -e "${YELLOW}Директория:${NC} $SCRIPT_DIR"
    echo
    echo -e "${YELLOW}Нажмите Enter для возврата в меню...${NC}"
    read -r
}

# Объединённый статус системы и безопасности
show_unified_status() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    System Status & Security          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo
    
    # UFW Firewall
    echo -e "${BLUE}🔥 FIREWALL (UFW):${NC}"
    if command -v ufw &>/dev/null; then
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1 | awk '{print $2}')
        case $ufw_status in
            active) echo -e "  Status: ${GREEN}active${NC}" ;;
            inactive) echo -e "  Status: ${RED}inactive${NC}" ;;
            *) echo -e "  Status: ${YELLOW}$ufw_status${NC}" ;;
        esac
        
        echo
        echo "  Правила:"
        ufw status numbered 2>/dev/null | grep -E "^\[.*\]" || echo "  Правила не найдены"
    else
        echo -e "  Status: ${YELLOW}не установлен${NC}"
    fi
    echo
    
    # Fail2ban
    echo -e "${BLUE}🛡️  FAIL2BAN:${NC}"
    if command -v fail2ban-client &>/dev/null; then
        if systemctl is-active --quiet fail2ban; then
            echo -e "  Status: ${GREEN}active${NC}"
            echo "  Jails:"
            fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*://; s/,/\n/g' | while read -r jail; do
                jail=$(echo "$jail" | xargs)
                if [[ -n "$jail" ]]; then
                    local banned
                    banned=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
                    echo "    • $jail: $banned banned IPs"
                fi
            done
        else
            echo -e "  Status: ${RED}inactive${NC}"
        fi
    else
        echo -e "  Status: ${YELLOW}не установлен${NC}"
    fi
    echo
    
    # Docker
    echo -e "${BLUE}📦 DOCKER:${NC}"
    if command -v docker &>/dev/null; then
        local containers images volumes
        containers=$(docker ps -q 2>/dev/null | wc -l)
        images=$(docker images -q 2>/dev/null | wc -l)
        volumes=$(docker volume ls -q 2>/dev/null | wc -l)
        echo "  • Running containers: $containers"
        echo "  • Images: $images"
        echo "  • Volumes: $volumes"
    else
        echo -e "  Status: ${YELLOW}не установлен${NC}"
    fi
    
    echo
    read -p "Нажмите Enter для возврата..." -r
}

# Информация о системе - расширенная версия
show_system_info() {
    show_header
    log_info "ℹ️  Информация о системе и безопасность"
    echo "════════════════════════════════════════════════════"
    
    # Основная информация о системе
    echo -e "${BLUE}🖥️  СИСТЕМНАЯ ИНФОРМАЦИЯ:${NC}"
    echo "════════════════════════════════════════════════════"
    echo "📍 Hostname: $(hostname)"
    echo "🐧 OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
    echo "⚙️  Kernel: $(uname -r)"
    echo "⏱️  Uptime: $(uptime -p 2>/dev/null || uptime)"
    
    # CPU и память
    local cpu_info mem_info
    cpu_info=$(nproc 2>/dev/null || echo "Unknown")
    mem_info=$(free -h 2>/dev/null | grep "^Mem:" | awk '{print $3"/"$2}' || echo "Unknown")
    echo "🧠 CPU cores: $cpu_info"
    echo "💾 Memory: $mem_info"
    
    # Дисковое пространство
    local disk_info
    disk_info=$(df -h / 2>/dev/null | tail -1 | awk '{print $3"/"$2" ("$5" used)"}' || echo "Unknown")
    echo "💿 Disk (/): $disk_info"
    echo
    
    # Статус сервисов
    echo -e "${BLUE}🔧 СТАТУС СЕРВИСОВ:${NC}"
    echo "════════════════════════════════════════════════════"
    
    local ssh_status
    ssh_status=$(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo "unknown")
    case $ssh_status in
        active) echo -e "🔐 SSH Service: ${GREEN}активен${NC}" ;;
        inactive) echo -e "🔐 SSH Service: ${RED}неактивен${NC}" ;;
        *) echo -e "🔐 SSH Service: ${YELLOW}$ssh_status${NC}" ;;
    esac
    
    # fail2ban статус
    if command -v fail2ban-client &>/dev/null; then
        if systemctl is-active --quiet fail2ban; then
            echo -e "🛡️  fail2ban: ${GREEN}активен${NC}"
        else
            echo -e "🛡️  fail2ban: ${RED}неактивен${NC}"
        fi
    else
        echo -e "🛡️  fail2ban: ${YELLOW}не установлен${NC}"
    fi
    
    # CrowdSec статус
    if command -v cscli &>/dev/null; then
        if systemctl is-active --quiet crowdsec; then
            echo -e "👥 CrowdSec: ${GREEN}активен${NC}"
        else
            echo -e "👥 CrowdSec: ${RED}неактивен${NC}"
        fi
    else
        echo -e "👥 CrowdSec: ${YELLOW}не установлен${NC}"
    fi
    
    # Docker статус
    if command -v docker &>/dev/null; then
        if systemctl is-active --quiet docker; then
            echo -e "🐳 Docker: ${GREEN}активен${NC}"
        else
            echo -e "🐳 Docker: ${RED}неактивен${NC}"
        fi
    else
        echo -e "🐳 Docker: ${YELLOW}не установлен${NC}"
    fi
    echo
    
    # SSH конфигурация
    echo -e "${BLUE}🔐 SSH КОНФИГУРАЦИЯ:${NC}"
    echo "════════════════════════════════════════════════════"
    if [[ -f /etc/ssh/sshd_config ]]; then
        local ssh_port password_auth root_login permit_empty
        ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
        password_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "yes")
        root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "yes")
        permit_empty=$(grep "^PermitEmptyPasswords" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "no")
        
        echo "🔌 SSH Port: $ssh_port"
        
        case $password_auth in
            no) echo -e "🔑 Password Auth: ${GREEN}отключена${NC}" ;;
            yes) echo -e "🔑 Password Auth: ${RED}включена${NC}" ;;
            *) echo -e "🔑 Password Auth: ${YELLOW}$password_auth${NC}" ;;
        esac
        
        case $root_login in
            no) echo -e "👑 Root Login: ${GREEN}запрещен${NC}" ;;
            prohibit-password) echo -e "👑 Root Login: ${GREEN}только по ключу${NC}" ;;
            yes) echo -e "👑 Root Login: ${RED}разрешен${NC}" ;;
            *) echo -e "👑 Root Login: ${YELLOW}$root_login${NC}" ;;
        esac
        
        case $permit_empty in
            no) echo -e "🚫 Empty Passwords: ${GREEN}запрещены${NC}" ;;
            yes) echo -e "🚫 Empty Passwords: ${RED}разрешены${NC}" ;;
            *) echo -e "🚫 Empty Passwords: ${YELLOW}$permit_empty${NC}" ;;
        esac
    else
        echo -e "${RED}❌ SSH конфигурация не найдена${NC}"
    fi
    echo
    
    # UFW статус
    echo -e "${BLUE}🛡️  UFW СТАТУС:${NC}"
    echo "════════════════════════════════════════════════════"
    if command -v ufw &>/dev/null; then
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1 | awk '{print $2}')
        case $ufw_status in
            active) echo -e "🛡️  UFW Status: ${GREEN}активен${NC}" ;;
            inactive) echo -e "🛡️  UFW Status: ${RED}неактивен${NC}" ;;
            *) echo -e "🛡️  UFW Status: ${YELLOW}$ufw_status${NC}" ;;
        esac
        
        # Показать основные правила
        echo
        echo "📋 Основные правила:"
        ufw status numbered 2>/dev/null | grep -E "^\[.*\].*(ALLOW|DENY)" | head -5 || echo "Правила не найдены"
    else
        echo -e "🛡️  UFW Status: ${YELLOW}не установлен${NC}"
    fi
    
    echo
    echo -e "${BLUE}🔧 СИСТЕМНАЯ ЗАЩИТА:${NC}"
    echo "════════════════════════════════════════════════════"
    
    # Последнее обновление
    local last_update
    last_update=$(stat -c %y /var/lib/apt/lists/ 2>/dev/null | head -1 | cut -d' ' -f1 || echo "unknown")
    echo -e "📅 Последнее обновление: ${BLUE}$last_update${NC}"
    
    # Автообновления
    local auto_updates
    auto_updates=$(systemctl is-enabled unattended-upgrades 2>/dev/null || echo "not configured")
    if [[ "$auto_updates" == "enabled" ]]; then
        echo -e "🔄 Автообновления: ${GREEN}✅ включены${NC}"
    else
        echo -e "🔄 Автообновления: ${RED}❌ не настроены${NC}"
    fi
    
    # CrowdSec Bouncer статус
    local bouncer_status
    bouncer_status=$(systemctl is-active crowdsec-firewall-bouncer 2>/dev/null || echo "not installed")
    if [[ "$bouncer_status" == "active" ]]; then
        echo -e "🚪 CrowdSec Bouncer: ${GREEN}✅ активен${NC}"
    elif [[ "$bouncer_status" == "inactive" ]]; then
        echo -e "🚪 CrowdSec Bouncer: ${YELLOW}⚠️ неактивен${NC}"
    else
        echo -e "🚪 CrowdSec Bouncer: ${RED}❌ не установлен${NC}"
    fi
    
    echo
}

# Просмотр логов
view_logs() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║            Просмотр логов            ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo
        
        # Статистика по логам
        if [[ -f "$LOG_FILE" ]]; then
            local total_lines success_count error_count warning_count info_count
            total_lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")
            success_count=$(grep -c "\[SUCCESS\]" "$LOG_FILE" 2>/dev/null || echo "0")
            error_count=$(grep -c "\[ERROR\]" "$LOG_FILE" 2>/dev/null || echo "0")
            warning_count=$(grep -c "\[WARNING\]" "$LOG_FILE" 2>/dev/null || echo "0")
            info_count=$(grep -c "\[INFO\]" "$LOG_FILE" 2>/dev/null || echo "0")
            
            echo -e "${GREEN}📊 Статистика логов:${NC}"
            echo "════════════════════════════════════════════════════"
            echo -e "📄 Всего записей: ${BLUE}$total_lines${NC}"
            echo -e "✅ Успешных операций: ${GREEN}$success_count${NC}"
            echo -e "❌ Ошибок: ${RED}$error_count${NC}"
            echo -e "⚠️  Предупреждений: ${YELLOW}$warning_count${NC}"
            echo -e "ℹ️  Информационных: ${BLUE}$info_count${NC}"
            echo "════════════════════════════════════════════════════"
            echo
            
            echo "Выберите действие:"
            echo "1. 📋 Показать все логи"
            echo "2. ✅ Показать только успешные операции"
            echo "3. ❌ Показать только ошибки"
            echo "4. ⚠️  Показать только предупреждения"
            echo "5. 📊 Показать последние 20 записей"
            echo "6. 🔍 Поиск в логах"
            echo "7. 🗑️  Очистить логи"
            echo "0. 🔙 Назад в главное меню"
            echo
            read -p "Выберите действие [0-7]: " -n 1 -r choice
            echo
            
            case $choice in
                1) 
                    echo -e "${GREEN}📋 Все логи:${NC}"
                    echo "════════════════════════════════════════════════════"
                    cat "$LOG_FILE" | while IFS= read -r line; do
                        if [[ "$line" =~ \[SUCCESS\] ]]; then
                            echo -e "${GREEN}$line${NC}"
                        elif [[ "$line" =~ \[ERROR\] ]]; then
                            echo -e "${RED}$line${NC}"
                        elif [[ "$line" =~ \[WARNING\] ]]; then
                            echo -e "${YELLOW}$line${NC}"
                        elif [[ "$line" =~ \[INFO\] ]]; then
                            echo -e "${BLUE}$line${NC}"
                        else
                            echo "$line"
                        fi
                    done
                    echo "════════════════════════════════════════════════════"
                    ;;
                2)
                    echo -e "${GREEN}✅ Успешные операции:${NC}"
                    echo "════════════════════════════════════════════════════"
                    grep "\[SUCCESS\]" "$LOG_FILE" | while IFS= read -r line; do
                        echo -e "${GREEN}$line${NC}"
                    done
                    echo "════════════════════════════════════════════════════"
                    ;;
                3)
                    echo -e "${RED}❌ Ошибки:${NC}"
                    echo "════════════════════════════════════════════════════"
                    grep "\[ERROR\]" "$LOG_FILE" | while IFS= read -r line; do
                        echo -e "${RED}$line${NC}"
                    done
                    echo "════════════════════════════════════════════════════"
                    ;;
                4)
                    echo -e "${YELLOW}⚠️  Предупреждения:${NC}"
                    echo "════════════════════════════════════════════════════"
                    grep "\[WARNING\]" "$LOG_FILE" | while IFS= read -r line; do
                        echo -e "${YELLOW}$line${NC}"
                    done
                    echo "════════════════════════════════════════════════════"
                    ;;
                5)
                    echo -e "${BLUE}📊 Последние 20 записей:${NC}"
                    echo "════════════════════════════════════════════════════"
                    tail -20 "$LOG_FILE" | while IFS= read -r line; do
                        if [[ "$line" =~ \[SUCCESS\] ]]; then
                            echo -e "${GREEN}$line${NC}"
                        elif [[ "$line" =~ \[ERROR\] ]]; then
                            echo -e "${RED}$line${NC}"
                        elif [[ "$line" =~ \[WARNING\] ]]; then
                            echo -e "${YELLOW}$line${NC}"
                        elif [[ "$line" =~ \[INFO\] ]]; then
                            echo -e "${BLUE}$line${NC}"
                        else
                            echo "$line"
                        fi
                    done
                    echo "════════════════════════════════════════════════════"
                    ;;
                6)
                    read -p "Введите поисковый запрос: " -r search_term
                    if [[ -n "$search_term" ]]; then
                        echo -e "${BLUE}🔍 Результаты поиска для '$search_term':${NC}"
                        echo "════════════════════════════════════════════════════"
                        grep -i "$search_term" "$LOG_FILE" | while IFS= read -r line; do
                            if [[ "$line" =~ \[SUCCESS\] ]]; then
                                echo -e "${GREEN}$line${NC}"
                            elif [[ "$line" =~ \[ERROR\] ]]; then
                                echo -e "${RED}$line${NC}"
                            elif [[ "$line" =~ \[WARNING\] ]]; then
                                echo -e "${YELLOW}$line${NC}"
                            elif [[ "$line" =~ \[INFO\] ]]; then
                                echo -e "${BLUE}$line${NC}"
                            else
                                echo "$line"
                            fi
                        done
                        echo "════════════════════════════════════════════════════"
                    fi
                    ;;
                7)
                    read -p "Очистить все логи? (Enter = да, 0 = отмена): " -r
                    echo
                    if [[ "$REPLY" != "0" ]]; then
                        : > "$LOG_FILE"
                        log_success "Логи очищены"
                    fi
                    ;;
                0) return 0 ;;
                *)
                    log_error "Неверный выбор: '$choice'"
                    sleep 1
                    continue
                    ;;
            esac
            
            # Автовозврат в меню логов с возможностью выхода
            if [[ "$choice" != "0" ]]; then
                echo
                echo -e "${YELLOW}[Enter=продолжить, q=выход в главное меню]${NC}"
                read -n 1 -r key
                if [[ "$key" == "q" ]] || [[ "$key" == "Q" ]]; then
                    return 0
                fi
            fi
        else
            log_warning "📄 Файл лога пуст или не найден: $LOG_FILE"
            echo
            read -p "Нажмите Enter для возврата..." -r
            return 0
        fi
    done
}

# Функция удаления Security Toolkit
uninstall_toolkit() {
    clear
    echo -e "${RED}╔══════════════════════════════════════╗${NC}"
    echo -e "${RED}║        Удаление Security Toolkit     ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════╝${NC}"
    echo
    
    log_warning "⚠️  ВНИМАНИЕ: Это действие полностью удалит Security Toolkit!"
    echo
    echo "Будет удалено:"
    echo "• Исполняемые файлы и модули"
    echo "• Символические ссылки (/usr/local/bin/security-toolkit, /usr/local/bin/ss)"
    echo "• Конфигурационные файлы"
    echo "• Логи (опционально) - теперь хранятся отдельно в /var/log/server-security-toolkit"
    echo "• Резервные копии SSH и UFW (опционально)"
    echo
    
    read -p "Продолжить удаление? (Enter = да, 0 = отмена): " -r
    echo
    if [[ "$REPLY" == "0" ]]; then
        log_info "Удаление отменено"
        return 0
    fi
    
    echo
    read -p "Удалить также резервные копии SSH и UFW? (Enter = да, 0 = отмена): " -r
    echo
    local remove_backups="false"
    if [[ "$REPLY" != "0" ]]; then
        remove_backups="true"
        log_warning "Резервные копии будут удалены!"
    else
        log_info "Резервные копии будут сохранены"
    fi
    
    echo
    read -p "Удалить логи? (Enter = да, 0 = отмена): " -r
    echo
    local remove_logs="false"
    if [[ "$REPLY" != "0" ]]; then
        remove_logs="true"
        log_warning "Логи будут удалены!"
    else
        log_info "Логи будут сохранены"
    fi
    
    echo
    log_info "Начинаю удаление..."
    
    # Удаляем символические ссылки
    if [[ -L "/usr/local/bin/security-toolkit" ]]; then
        rm -f "/usr/local/bin/security-toolkit"
        log_success "Удалена ссылка: /usr/local/bin/security-toolkit"
    fi
    
    if [[ -L "/usr/local/bin/ss" ]]; then
        rm -f "/usr/local/bin/ss"
        log_success "Удалена ссылка: /usr/local/bin/ss"
    fi
    
    # Удаляем резервные копии SSH
    if [[ "$remove_backups" == "true" ]]; then
        if [[ -d "/etc/ssh" ]]; then
            find /etc/ssh -name "sshd_config.backup.*" -delete 2>/dev/null
            log_success "Удалены резервные копии SSH конфигурации"
        fi
        
        if [[ -d "/root/.ssh" ]]; then
            find /root/.ssh -name "authorized_keys.backup.*" -delete 2>/dev/null
            log_success "Удалены резервные копии authorized_keys"
        fi
        
        if [[ -d "/etc/ufw/backup" ]]; then
            rm -rf "/etc/ufw/backup"
            log_success "Удалены резервные копии UFW"
        fi
    fi
    
    # Удаляем логи
    if [[ "$remove_logs" == "true" ]]; then
        if [[ -d "/var/log/server-security-toolkit" ]]; then
            rm -rf "/var/log/server-security-toolkit"
            log_success "Удалены логи из /var/log/server-security-toolkit"
        fi
    fi
    
    # Удаляем основную директорию (кроме логов если они сохраняются)
    local items_to_remove=(
        "$SCRIPT_DIR/main.sh"
        "$SCRIPT_DIR/install.sh"
        "$SCRIPT_DIR/modules"
        "$SCRIPT_DIR/configs"
        "$SCRIPT_DIR/keys"
        "$SCRIPT_DIR/scripts"
        "$SCRIPT_DIR/tests"
        "$SCRIPT_DIR/docs"
        "$SCRIPT_DIR/.vscode"
        "$SCRIPT_DIR/README.md"
        "$SCRIPT_DIR/QUICKSTART.md"
        "$SCRIPT_DIR/.gitignore"
    )
    
    for item in "${items_to_remove[@]}"; do
        if [[ -e "$item" ]]; then
            rm -rf "$item"
            log_success "Удален: $(basename "$item")"
        fi
    done
    
    # Удаляем пустую директорию если логи тоже удалены
    if [[ "$remove_logs" == "true" && -d "$SCRIPT_DIR" ]]; then
        rmdir "$SCRIPT_DIR" 2>/dev/null && log_success "Удалена директория: $SCRIPT_DIR"
    fi
    
    echo
    log_success "🎉 Security Toolkit успешно удален!"
    
    if [[ "$remove_backups" == "false" ]]; then
        echo
        log_info "📋 Сохраненные резервные копии:"
        echo "• SSH конфигурация: $SCRIPT_DIR/Backups/sshd_config.backup.*"
        echo "• authorized_keys: $SCRIPT_DIR/Backups/authorized_keys.backup.*"
        echo "• UFW правила: $SCRIPT_DIR/Backups/ufw_rules_*.tar.gz"
    fi
    
    if [[ "$remove_logs" == "false" ]]; then
        echo
        log_info "📋 Сохраненные логи: /var/log/server-security-toolkit/"
    fi
    
    echo
    log_info "Спасибо за использование Server Security Toolkit! 👋"
    echo
    read -p "Нажмите Enter для выхода..." -r
    exit 0
}

# Загрузка конфигурации по умолчанию
load_default_config() {
    local config_file="${SCRIPT_DIR}/configs/defaults.env"
    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
        log_info "Загружена конфигурация: $config_file"
        return 0
    else
        log_warning "Файл конфигурации не найден: $config_file"
        return 1
    fi
}

# Полная настройка безопасности
full_security_setup() {
    show_header
    log_warning "🚀 Полная настройка безопасности"
    echo
    
    # Пытаемся загрузить конфигурацию
    local use_config=false
    if load_default_config; then
        echo "📋 Найден файл конфигурации configs/defaults.env"
        echo
        read -p "Использовать автоматические настройки из конфигурации? (Enter = да, 0 = отмена): " -r
        echo
        if [[ "$REPLY" == "0" ]]; then
            use_config=false
            log_info "Будет использован интерактивный режим"
        else
            use_config=true
            log_info "Будут применены настройки из конфигурации"
        fi
    else
        log_info "Будет использован интерактивный режим"
    fi
    
    echo
    echo "Это действие выполнит:"
    echo "  1. 🔐 Настройку SSH безопасности"
    echo "  2. 🛡️ Конфигурацию файрвола"  
    echo "  3. 🔧 Укрепление системы"
    if [[ "$use_config" == "true" ]]; then
        echo "  📋 Согласно настройкам в configs/defaults.env"
    fi
    echo
    read -p "Продолжить полную настройку? (Enter = да, 0 = отмена): " -r
    echo
    if [[ "$REPLY" == "0" ]]; then
        return 0
    fi
    
    if [[ "$use_config" == "true" ]]; then
        full_security_setup_automated
    else
        full_security_setup_interactive
    fi
    
    log_success "🎉 Полная настройка завершена!"
}

# Автоматизированная настройка с использованием конфигурации
full_security_setup_automated() {
    log_info "🤖 Запуск автоматизированной настройки..."
    
    # SSH настройки
    if [[ "${SETUP_BASIC_FIREWALL:-true}" == "true" ]]; then
        log_info "Настройка базового файрвола..."
        setup_basic_firewall
    fi
    
    # System Hardening
    if [[ "${INSTALL_FAIL2BAN:-true}" == "true" ]]; then
        log_info "Установка fail2ban..."
        install_fail2ban
    fi
    
    if [[ "${CONFIGURE_FAIL2BAN_BASIC:-true}" == "true" ]]; then
        log_info "Базовая конфигурация fail2ban..."
        configure_fail2ban_basic
    fi
    
    if [[ "${INSTALL_UNATTENDED_UPGRADES:-true}" == "true" ]]; then
        log_info "Установка автоматических обновлений..."
        install_unattended_upgrades
    fi
    
    if [[ "${INSTALL_CROWDSEC:-false}" == "true" ]]; then
        log_info "Установка CrowdSec..."
        install_crowdsec
    fi
    
    if [[ "${INSTALL_CROWDSEC_BOUNCER:-false}" == "true" ]]; then
        log_info "Установка CrowdSec Bouncer..."
        install_crowdsec_bouncer
    fi
    
    log_warning "⚠️  SSH настройки требуют ручной настройки для безопасности"
    log_info "Используйте меню 'SSH Security' для:"
    log_info "  - Импорта SSH ключей"
    log_info "  - Смены SSH порта"
    log_info "  - Отключения парольной авторизации"
}

# Интерактивная настройка с пошаговым гидом
full_security_setup_interactive() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              🚀 ИНТЕРАКТИВНАЯ НАСТРОЙКА БЕЗОПАСНОСТИ         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    log_info "Добро пожаловать в интерактивный гид по настройке безопасности!"
    echo
    echo "Мы пройдем через все основные этапы настройки:"
    echo "1. 🔐 Настройка SSH (ключи, порт, отключение паролей)"
    echo "2. 🛡️  Настройка файрвола UFW"
    echo "3. 🔧 Установка системы защиты (fail2ban, CrowdSec)"
    echo "4. 📊 Проверка и финальная настройка"
    echo
    echo "После каждого шага будут созданы резервные копии."
    echo
    
    read -p "Начать интерактивную настройку? (Enter = да, 0 = отмена): " -r
    echo
    if [[ "$REPLY" == "0" ]]; then
        log_info "Настройка отменена"
        return 0
    fi
    
    # Этап 1: SSH Security
    echo
    echo "═══════════════════════════════════════════════════════════════"
    log_info "🔐 ЭТАП 1: Настройка SSH безопасности"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    echo "Настроим SSH для максимальной безопасности:"
    echo "• Импорт или генерация SSH ключей"
    echo "• Смена SSH порта (рекомендуется)"
    echo "• Отключение парольной авторизации"
    echo "• Отключение root доступа"
    echo
    
    read -p "Настроить SSH безопасность? (Enter = да, 0 = пропустить): " -r
    echo
    if [[ "$REPLY" != "0" ]]; then
        log_info "Создание бекапа SSH конфигурации..."
        backup_ssh_config
        configure_ssh_security
        log_success "✅ SSH настройка завершена"
    else
        log_info "SSH настройка пропущена"
    fi
    
    # Этап 2: Firewall
    echo
    echo "═══════════════════════════════════════════════════════════════"
    log_info "🛡️  ЭТАП 2: Настройка файрвола UFW"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    echo "Настроим файрвол для защиты сервера:"
    echo "• Базовые правила (SSH, HTTP, HTTPS)"
    echo "• Настройка портов и исключений"
    echo "• Активация файрвола"
    echo
    
    read -p "Настроить файрвол UFW? (Enter = да, 0 = пропустить): " -r
    echo
    if [[ "$REPLY" != "0" ]]; then
        log_info "Создание бекапа UFW правил..."
        # Создаем бекап UFW
        mkdir -p /etc/ufw/backup
        cp -r /etc/ufw/user*.rules /etc/ufw/backup/ 2>/dev/null || true
        configure_firewall
        log_success "✅ Файрвол настроен"
    else
        log_info "Настройка файрвола пропущена"
    fi
    
    # Этап 3: System Hardening
    echo
    echo "═══════════════════════════════════════════════════════════════"
    log_info "🔧 ЭТАП 3: Укрепление системы"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    echo "Установим дополнительную защиту:"
    echo "• fail2ban - защита от брутфорса"
    echo "• Автоматические обновления безопасности"
    echo "• CrowdSec - коллективная защита (опционально)"
    echo
    
    read -p "Установить системы защиты? (Enter = да, 0 = пропустить): " -r
    echo
    if [[ "$REPLY" != "0" ]]; then
        log_info "Создание бекапа системных настроек..."
        # Создаем бекап важных системных файлов
        mkdir -p /opt/server-security-toolkit/backups/system
        cp /etc/fail2ban/jail.local /opt/server-security-toolkit/backups/system/ 2>/dev/null || true
        system_hardening
        log_success "✅ Система укреплена"
    else
        log_info "Укрепление системы пропущено"
    fi
    
    # Этап 4: Финальная проверка
    echo
    echo "═══════════════════════════════════════════════════════════════"
    log_info "📊 ЭТАП 4: Финальная проверка и рекомендации"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    
    show_security_summary
    
    echo
    log_success "🎉 Интерактивная настройка безопасности завершена!"
    echo
    echo "📋 Полезные команды:"
    echo "• ss - запуск Security Toolkit"
    echo "• f2b list - просмотр заблокированных IP"
    echo "• f2b help - справка по fail2ban"
    echo
    echo "💾 Все изменения сохранены в резервных копиях"
    echo
    
    read -p "Нажмите Enter для возврата в главное меню..." -r
}

# Показать сводку безопасности
show_security_summary() {
    echo -e "${BLUE}🔍 ТЕКУЩЕЕ СОСТОЯНИЕ БЕЗОПАСНОСТИ:${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    
    # SSH статус - расширенная информация
    echo -e "${GREEN}🔐 SSH КОНФИГУРАЦИЯ:${NC}"
    if [[ -f /etc/ssh/sshd_config ]]; then
        local ssh_port password_auth root_login permit_empty
        ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
        password_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "yes")
        root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "yes")
        permit_empty=$(grep "^PermitEmptyPasswords" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "no")
        
        echo "   🔌 Порт SSH: $ssh_port $([[ "$ssh_port" != "22" ]] && echo "✅ (изменен)" || echo "⚠️  (стандартный)")"
        
        case $password_auth in
            no) echo -e "   🔑 Парольная авторизация: ${GREEN}отключена ✅${NC}" ;;
            yes) echo -e "   🔑 Парольная авторизация: ${RED}включена ⚠️${NC}" ;;
            *) echo -e "   🔑 Парольная авторизация: ${YELLOW}$password_auth ❓${NC}" ;;
        esac
        
        case $root_login in
            no) echo -e "   👑 Root доступ: ${GREEN}запрещен ✅${NC}" ;;
            prohibit-password) echo -e "   👑 Root доступ: ${GREEN}только по ключу ✅${NC}" ;;
            yes) echo -e "   👑 Root доступ: ${RED}разрешен ⚠️${NC}" ;;
            *) echo -e "   👑 Root доступ: ${YELLOW}$root_login ❓${NC}" ;;
        esac
        
        case $permit_empty in
            no) echo -e "   🚫 Пустые пароли: ${GREEN}запрещены ✅${NC}" ;;
            yes) echo -e "   🚫 Пустые пароли: ${RED}разрешены ⚠️${NC}" ;;
            *) echo -e "   🚫 Пустые пароли: ${YELLOW}$permit_empty ❓${NC}" ;;
        esac
    else
        echo -e "   ${RED}❌ SSH конфигурация не найдена${NC}"
    fi
    echo
    
    # UFW статус
    echo -e "${GREEN}🛡️  ФАЙРВОЛ UFW:${NC}"
    if command -v ufw &>/dev/null; then
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1 | awk '{print $2}')
        case $ufw_status in
            active) echo -e "   🛡️  Статус: ${GREEN}активен ✅${NC}" ;;
            inactive) echo -e "   🛡️  Статус: ${RED}неактивен ⚠️${NC}" ;;
            *) echo -e "   🛡️  Статус: ${YELLOW}$ufw_status ❓${NC}" ;;
        esac
        
        # Количество правил
        local rule_count
        rule_count=$(ufw status numbered 2>/dev/null | grep -c "^\s*\[" || echo "0")
        echo "   📋 Правила: $rule_count $([[ $rule_count -gt 0 ]] && echo "✅" || echo "⚠️")"
    else
        echo -e "   🛡️  UFW: ${YELLOW}не установлен${NC}"
    fi
    echo
    
    # Системы защиты
    echo -e "${GREEN}🔒 СИСТЕМЫ ЗАЩИТЫ:${NC}"
    
    # fail2ban статус
    if command -v fail2ban-client &>/dev/null; then
        if systemctl is-active --quiet fail2ban; then
            echo -e "   🔒 fail2ban: ${GREEN}активен ✅${NC}"
            
            # Показать заблокированные IP
            local banned_count
            banned_count=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned:" | awk '{print $3}' 2>/dev/null || echo "0")
            echo "   🚫 Заблокировано IP: $banned_count"
        else
            echo -e "   🔒 fail2ban: ${RED}неактивен ⚠️${NC}"
        fi
    else
        echo -e "   🔒 fail2ban: ${YELLOW}не установлен${NC}"
    fi
    
    # CrowdSec статус
    if command -v cscli &>/dev/null; then
        if systemctl is-active --quiet crowdsec; then
            echo -e "   👥 CrowdSec: ${GREEN}активен ✅${NC}"
        else
            echo -e "   👥 CrowdSec: ${RED}неактивен ⚠️${NC}"
        fi
    else
        echo -e "   👥 CrowdSec: ${YELLOW}не установлен${NC}"
    fi
    
    # Примечание о компонентах
    local fail2ban_installed crowdsec_installed
    fail2ban_installed=$(command -v fail2ban-client &>/dev/null && echo "yes" || echo "no")
    crowdsec_installed=$(command -v cscli &>/dev/null && echo "yes" || echo "no")
    
    if [[ "$fail2ban_installed" == "yes" && "$crowdsec_installed" == "yes" ]]; then
        echo -e "   ${BLUE}ℹ️  Оба компонента установлены - отличная защита!${NC}"
    elif [[ "$fail2ban_installed" == "yes" || "$crowdsec_installed" == "yes" ]]; then
        echo -e "   ${BLUE}ℹ️  Один компонент установлен - базовая защита активна${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Рекомендуется установить fail2ban или CrowdSec${NC}"
    fi
    
    echo "═══════════════════════════════════════════════════════════════"
}

# Проверка обновлений при запуске
check_for_updates_silent() {
    # Тихая проверка обновлений - не блокирует запуск
    local current_dir
    current_dir=$(pwd)

    # Переходим в директорию скрипта
    cd "$SCRIPT_DIR" 2>/dev/null || return 1

    # Проверяем, есть ли git репозиторий
    if [[ ! -d ".git" ]]; then
        cd "$current_dir" 2>/dev/null || true
        return 1
    fi

    # Получаем текущий коммит
    local current_commit
    current_commit=$(git rev-parse HEAD 2>/dev/null)

    # Проверяем обновления
    if git fetch origin main >/dev/null 2>&1; then
        local remote_commit
        remote_commit=$(git rev-parse origin/main 2>/dev/null)

        if [[ "$current_commit" != "$remote_commit" ]]; then
            cd "$current_dir" 2>/dev/null || true
            return 0  # Обновления есть
        fi
    fi

    # Возвращаемся в исходную директорию
    cd "$current_dir" 2>/dev/null || true
    return 1  # Обновлений нет
}

# Глобальная переменная для отслеживания обновлений
UPDATE_AVAILABLE=false

# Функция обновления Security Toolkit
update_toolkit() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           🔄 ОБНОВЛЕНИЕ SECURITY TOOLKIT         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo
    
    log_info "🔄 Начинаем процесс обновления..."
    echo
    
    # Проверяем наличие git
    if ! command -v git &>/dev/null; then
        log_error "❌ Git не установлен. Невозможно выполнить обновление"
        echo
        read -p "Нажмите Enter для возврата в главное меню..." -r
        return 1
    fi
    
    # Сохраняем текущую директорию
    local current_dir
    current_dir=$(pwd)
    
    # Переходим в директорию скрипта
    cd "$SCRIPT_DIR" 2>/dev/null || {
        log_error "❌ Не удалось перейти в директорию скрипта: $SCRIPT_DIR"
        cd "$current_dir" 2>/dev/null || true
        echo
        read -p "Нажмите Enter для возврата в главное меню..." -r
        return 1
    }
    
    # Проверяем, что это git репозиторий
    if [[ ! -d ".git" ]]; then
        log_error "❌ Директория $SCRIPT_DIR не является git репозиторием"
        cd "$current_dir" 2>/dev/null || true
        echo
        read -p "Нажмите Enter для возврата в главное меню..." -r
        return 1
    fi
    
    echo "📦 Скачиваем обновления..."
    if ! git fetch origin main 2>/dev/null; then
        log_error "❌ Не удалось скачать обновления"
        cd "$current_dir" 2>/dev/null || true
        echo
        read -p "Нажмите Enter для возврата в главное меню..." -r
        return 1
    fi
    
    # Получаем информацию о коммитах
    local current_commit remote_commit commits_behind
    current_commit=$(git rev-parse HEAD 2>/dev/null)
    remote_commit=$(git rev-parse origin/main 2>/dev/null)
    commits_behind=$(git rev-list --count "$current_commit..$remote_commit" 2>/dev/null || echo "несколько")
    
    if [[ "$current_commit" == "$remote_commit" ]]; then
        log_success "✅ У вас уже установлена последняя версия"
        cd "$current_dir" 2>/dev/null || true
        echo
        read -p "Нажмите Enter для возврата в главное меню..." -r
        return 0
    fi
    
    echo -e "${BLUE}📊 Информация об обновлении:${NC}"
    echo "   Текущий коммит: ${current_commit:0:7}"
    echo "   Новый коммит:    ${remote_commit:0:7}"
    echo "   Новых коммитов:  $commits_behind"
    echo
    
    # Показываем изменения
    echo -e "${BLUE}📋 Изменения в обновлении:${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    git log --oneline --no-merges "$current_commit..$remote_commit" 2>/dev/null || echo "Не удалось получить список изменений"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    
    # Запрашиваем подтверждение обновления
    read -p "Применить обновление? (Enter = да, 0 = отмена): " -r
    if [[ "$REPLY" == "0" ]]; then
        log_info "Обновление отменено"
        cd "$current_dir" 2>/dev/null || true
        echo
        read -p "Нажмите Enter для возврата в главное меню..." -r
        return 0
    fi
    
    echo
    log_info "🔄 Применяем обновление..."
    
    # Выполняем обновление (подавляем предупреждения о перезаписи)
    if git reset --hard origin/main >/dev/null 2>&1; then
        log_success "✅ Обновление успешно применено!"
        
        # Восстанавливаем права доступа после обновления
        chmod +x "$SCRIPT_DIR/main.sh" "$SCRIPT_DIR/modules"/*.sh 2>/dev/null || true
        log_info "Права доступа восстановлены"
        
        echo
        
        # Обновляем статус обновлений
        UPDATE_AVAILABLE=false
        
        # Показываем сообщение о перезапуске
        echo -e "${GREEN}🔄 Скрипт будет автоматически перезапущен через 3 секунды...${NC}"
        echo -e "${YELLOW}💡 Если перезапуск не сработает, запустите скрипт вручную${NC}"
        echo
        
        # Возвращаемся в исходную директорию
        cd "$current_dir" 2>/dev/null || true
        
        # Перезапускаем скрипт
        sleep 3
        exec "$SCRIPT_DIR/main.sh" "${ORIGINAL_ARGS[@]}"
    else
        log_error "❌ Ошибка при применении обновления"
        cd "$current_dir" 2>/dev/null || true
        echo
        read -p "Нажмите Enter для возврата в главное меню..." -r
        return 1
    fi
}

# Главная функция
main() {
    # Очищаем старые логи при запуске (оставляем только последние MAX_LOG_FILES)
    cleanup_old_logs "$MAX_LOG_FILES" >/dev/null 2>&1
    
    # Ротируем логи при запуске (тихо)
    rotate_logs >/dev/null 2>&1
    
    # Тихое логирование технической информации (только в файл)
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] 🚀 Запуск Server Security Toolkit v$VERSION"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Скрипт запущен из: ${BASH_SOURCE[0]}"
        if [[ -L "${BASH_SOURCE[0]}" ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Символическая ссылка: $(readlink -f "${BASH_SOURCE[0]}")"
        fi
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Рабочая директория: $SCRIPT_DIR"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Директория модулей: $MODULES_DIR"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Файл логов: $LOG_FILE"
    } >> "$LOG_FILE"
    
    # Тихие проверки (ошибки все равно выведутся если есть)
    check_root >/dev/null 2>&1 || { log_error "Требуются права root. Запустите: sudo sst"; exit 1; }
    check_os >/dev/null 2>&1 || true
    check_requirements >/dev/null 2>&1 || true
    install_traps
    
    # Загружаем модули тихо
    if ! load_modules >/dev/null 2>&1; then
        log_error "Критическая ошибка: не удалось загрузить модули"
        exit 1
    fi
    
    # Проверяем обновления тихо
    if check_for_updates_silent; then
        UPDATE_AVAILABLE=true
    else
        UPDATE_AVAILABLE=false
    fi
    
    # Главный цикл
    while true; do
        show_menu
        read -n 1 -r choice || choice=""
        echo
        
        # Обработка горячих клавиш
        case $choice in
            q|Q)
                log_info "До свидания! 👋"
                exit 0
                ;;
            h|H)
                show_help
                ;;
            1) 
                log_info "Пользователь выбрал: Full Security Setup"
                if declare -f full_security_setup &>/dev/null; then
                    run_action "Full Security Setup" full_security_setup
                else
                    log_error "Функция full_security_setup не найдена"
                fi
                ;;
            2) 
                log_info "Пользователь выбрал: SSH Security"
                if declare -f configure_ssh_security &>/dev/null; then
                    run_action "SSH Security" configure_ssh_security
                else
                    log_error "Функция configure_ssh_security не найдена"
                fi
                ;;
            3) 
                log_info "Пользователь выбрал: Firewall Setup"
                if declare -f configure_firewall &>/dev/null; then
                    run_action "Firewall Setup" configure_firewall
                else
                    log_error "Функция configure_firewall не найдена"
                fi
                ;;
            4) 
                log_info "Пользователь выбрал: System Hardening"
                if declare -f system_hardening &>/dev/null; then
                    run_action "System Hardening" system_hardening
                else
                    log_error "Функция system_hardening не найдена"
                fi
                ;;
            5) 
                log_info "Пользователь выбрал: Docker Management"
                if declare -f docker_management &>/dev/null; then
                    run_action "Docker Management" docker_management
                else
                    log_error "Функция docker_management не найдена"
                fi
                ;;
            6) 
                log_info "Пользователь выбрал: System Status & Security"
                show_unified_status
                echo
                # Показываем рекомендации
                analyze_security
                echo -e "${YELLOW}Нажмите Enter для возврата...${NC}"
                read -r
                ;;
            7) 
                log_info "Пользователь выбрал: View Logs"
                view_logs
                ;;
            8) 
                if [[ "$UPDATE_AVAILABLE" == "true" ]]; then
                    log_info "Пользователь выбрал: Update Toolkit"
                    update_toolkit
                else
                    log_info "Пользователь выбрал: Uninstall"
                    uninstall_toolkit
                fi
                ;;
            9) 
                if [[ "$UPDATE_AVAILABLE" == "true" ]]; then
                    log_info "Пользователь выбрал: Uninstall"
                    uninstall_toolkit
                else
                    log_error "Неверный выбор: '$choice'"
                    sleep 1
                    continue
                fi
                ;;
            0) 
                log_info "До свидания! 👋"
                exit 0
                ;;
            *)
                log_error "Неверный выбор: '$choice'"
                sleep 1
                continue
                ;;
        esac
    done
}

# Запуск
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
