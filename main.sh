#!/bin/bash

# Server Security Toolkit v1.0
# Модульный инструмент безопасности для Ubuntu серверов
# Автор: Ваше имя

set -euo pipefail

# Версия скрипта
VERSION="1.0.0"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Директории проекта
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODULES_DIR="${SCRIPT_DIR}/modules"
readonly CONFIGS_DIR="${SCRIPT_DIR}/configs"
readonly KEYS_DIR="${SCRIPT_DIR}/keys"
readonly LOGS_DIR="${SCRIPT_DIR}/logs"

# Создаем папку логов
mkdir -p "$LOGS_DIR"

# Файл логов
readonly LOG_FILE="${LOGS_DIR}/security-$(date +%Y%m%d_%H%M%S).log"

# Функции логирования
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

# Функция для отображения заголовка
show_header() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║         Server Security Toolkit v${VERSION}         ║"
    echo "║          Ubuntu Server Hardening Script          ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен запускаться с правами root"
        log_info "Запустите: sudo bash $0"
        exit 1
    fi
    log_success "Права администратора подтверждены"
}

# Проверка операционной системы
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Не удается определить операционную систему"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_warning "Скрипт оптимизирован для Ubuntu"
        log_info "Обнаружена ОС: $PRETTY_NAME"
        read -p "Продолжить выполнение? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Выполнение прервано пользователем"
            exit 1
        fi
    else
        log_success "Обнаружена Ubuntu $VERSION_ID"
    fi
}

# Создание резервной копии
create_backup() {
    local file_path="$1"
    local backup_path="${file_path}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file_path" ]]; then
        cp "$file_path" "$backup_path"
        log_success "Резервная копия создана: $backup_path"
        return 0
    else
        log_warning "Файл для резервного копирования не найден: $file_path"
        return 1
    fi
}

# Загрузка модулей
load_modules() {
    local loaded_count=0
    
    log_info "Загрузка модулей..."
    
    for module in "${MODULES_DIR}"/*.sh; do
        if [[ -f "$module" ]]; then
            # shellcheck source=/dev/null
            source "$module"
            log_success "Загружен модуль: $(basename "$module" .sh)"
            ((loaded_count++))
        fi
    done
    
    if [[ $loaded_count -eq 0 ]]; then
        log_warning "Модули не найдены в $MODULES_DIR"
        log_info "Создайте модули или запустите в тестовом режиме"
    else
        log_success "Загружено модулей: $loaded_count"
    fi
}

# Проверка системных требований
check_requirements() {
    local missing_tools=()
    
    log_info "Проверка системных требований..."
    
    # Проверяем необходимые инструменты
    local required_tools=("ssh" "ufw" "systemctl" "sed" "grep" "awk")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Отсутствуют необходимые инструменты: ${missing_tools[*]}"
        log_info "Установите недостающие пакеты: sudo apt install ${missing_tools[*]}"
        return 1
    fi
    
    log_success "Все системные требования выполнены"
    return 0
}

# Информация о текущей системе
show_system_info() {
    log_info "Информация о системе:"
    echo "════════════════════════════════════════════════════"
    echo "Hostname: $(hostname)"
    echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
    echo "SSH Service: $(systemctl is-active ssh 2>/dev/null || echo "unknown")"
    echo "UFW Status: $(ufw status 2>/dev/null | head -1 || echo "unknown")"
    echo "Current User: $(whoami)"
    echo "Script Location: $SCRIPT_DIR"
    echo "Log File: $LOG_FILE"
    echo "════════════════════════════════════════════════════"
}

# Главное меню
show_menu() {
    show_header
    echo "🔧 Выберите действие:"
    echo
    echo "1. 🔐 SSH Security - Настройка безопасности SSH"
    echo "2. 🛡️  Firewall Setup - Настройка файрвола UFW"
    echo "3. 🔧 System Hardening - Укрепление системы"
    echo "4. 🔑 SSH Key Management - Управление SSH ключами"
    echo "5. 🚀 Full Security Setup - Полная настройка безопасности"
    echo "6. ℹ️  System Information - Информация о системе"
    echo "7. 📋 View Logs - Просмотр логов"
    echo "8. 🧪 Test Mode - Тестовый режим (безопасно)"
    echo "0. 🚪 Exit - Выход"
    echo
    echo -n "Введите номер действия [0-8]: "
}

# Просмотр логов
view_logs() {
    if [[ -f "$LOG_FILE" ]]; then
        log_info "Последние записи лога:"
        tail -20 "$LOG_FILE"
        echo
        read -p "Показать весь лог? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            less "$LOG_FILE"
        fi
    else
        log_warning "Файл лога не найден: $LOG_FILE"
    fi
}

# Тестовый режим
test_mode() {
    log_info "🧪 Запуск в тестовом режиме..."
    echo
    log_info "Этот режим покажет, какие изменения будут внесены"
    log_warning "Никакие системные файлы изменены не будут"
    echo
    
    # Проверка SSH конфигурации
    log_info "Анализ текущей SSH конфигурации:"
    if [[ -f /etc/ssh/sshd_config ]]; then
        local current_port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}' || echo "22")
        local password_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}' || echo "yes")
        local root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}' || echo "yes")
        
        echo "  - SSH Port: $current_port"
        echo "  - Password Auth: $password_auth"
        echo "  - Root Login: $root_login"
    else
        log_warning "SSH конфигурация не найдена"
    fi
    
    # Проверка UFW статуса
    log_info "Статус файрвола:"
    if command -v ufw &> /dev/null; then
        ufw status | head -5
    else
        log_warning "UFW не установлен"
    fi
    
    echo
    log_success "Тестовый режим завершен"
}

# Заглушки для модулей (будут заменены реальными функциями)
configure_ssh_security() {
    if declare -f configure_ssh_security &>/dev/null; then
        configure_ssh_security
    else
        log_error "SSH Security модуль не загружен"
    fi
}

configure_firewall() {
    if declare -f configure_firewall &>/dev/null; then
        configure_firewall  
    else
        log_error "Firewall модуль не загружен"
    fi
}

system_hardening() {
    log_info "🔧 Укрепление системы..."
    log_warning "Модуль в разработке"
    echo "Планируемые функции:"
    echo "  ✓ Обновление системы"
    echo "  ✓ Установка и настройка fail2ban"
    echo "  ✓ Отключение ненужных сервисов"
    echo "  ✓ Настройка автоматических обновлений"
    echo "  ✓ Конфигурация логирования"
    echo "  ✓ Настройка системных лимитов"
}

manage_ssh_keys() {
    if declare -f manage_ssh_keys &>/dev/null; then
        manage_ssh_keys
    else
        log_error "Key Management модуль не загружен"
    fi
}

full_security_setup() {
    log_info "🚀 Полная настройка безопасности..."
    log_warning "Это выполнит все модули последовательно"
    
    read -p "Продолжить? Это может занять время (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Операция отменена пользователем"
        return
    fi
    
    log_info "Начинаем полную настройку..."
    
    manage_ssh_keys
    echo && sleep 2
    
    configure_ssh_security
    echo && sleep 2
    
    configure_firewall
    echo && sleep 2
    
    system_hardening
    echo && sleep 2
    
    log_success "🎉 Полная настройка безопасности завершена!"
    log_info "Проверьте лог файл: $LOG_FILE"
}

# Функция очистки при выходе
cleanup() {
    log_info "Завершение работы скрипта..."
    log_info "Лог сохранен в: $LOG_FILE"
}

# Установка ловушки для корректного завершения
trap cleanup EXIT

# Главная функция
main() {
    # Показываем заголовок
    show_header
    
    # Инициализация
    log_info "Запуск Server Security Toolkit v$VERSION"
    
    # Для тестирования отключаем проверки root и ОС
    # В продакшене раскомментируйте эти строки:
    # check_root
    # check_os
    
    # Проверяем системные требования
    if ! check_requirements; then
        log_error "Системные требования не выполнены"
        exit 1
    fi
    
    # Загружаем модули
    load_modules
    
    # Главный цикл
    while true; do
        show_menu
        read -r choice
        echo
        
        case $choice in
            1)
                configure_ssh_security
                ;;
            2)
                configure_firewall
                ;;
            3)
                system_hardening
                ;;
            4)
                manage_ssh_keys
                ;;
            5)
                full_security_setup
                ;;
            6)
                show_system_info
                ;;
            7)
                view_logs
                ;;
            8)
                test_mode
                ;;
            0)
                log_info "До свидания! 👋"
                exit 0
                ;;
            *)
                log_error "Неверный выбор: '$choice'"
                log_info "Выберите число от 0 до 8"
                ;;
        esac
        
        echo
        echo -e "${YELLOW}Нажмите Enter для продолжения...${NC}"
        read -r
    done
}

# Проверяем, что скрипт запущен напрямую, а не через source
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

