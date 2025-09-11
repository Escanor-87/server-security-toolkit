#!/bin/bash

# Server Security Toolkit v1.0
# Модульный инструмент безопасности для Ubuntu серверов

set -euo pipefail

# Версия скрипта
VERSION="1.0.0"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Директории проекта - исправляем SC2155
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODULES_DIR="${SCRIPT_DIR}/modules"
readonly LOGS_DIR="${SCRIPT_DIR}/logs"

# Создаем папку логов
mkdir -p "$LOGS_DIR"

# Файл логов - исправляем SC2155  
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
}

# Проверка операционной системы - исправляем SC1091
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Не удается определить операционную систему"
        exit 1
    fi
    
    # shellcheck disable=SC1091
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
    fi
}

# Проверка системных требований
check_requirements() {
    local missing_tools=()
    local required_tools=("ssh" "systemctl" "sed" "grep" "awk")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Отсутствуют необходимые инструменты: ${missing_tools[*]}"
        exit 1
    fi
}

# Загрузка модулей
load_modules() {
    for module in "${MODULES_DIR}"/*.sh; do
        if [[ -f "$module" ]]; then
            # shellcheck source=/dev/null
            source "$module"
        fi
    done
}

# Главное меню
show_menu() {
    show_header
    echo "🔧 Выберите действие:"
    echo
    echo "1. 🔐 SSH Security - Настройка безопасности SSH"
    echo "2. 🛡️  Firewall Setup - Настройка файрвола UFW"
    echo "3. 🔧 System Hardening - Укрепление системы"
    echo "4. 🚀 Full Security Setup - Полная настройка безопасности"
    echo "5. ℹ️  System Information - Информация о системе"
    echo "6. 📋 View Logs - Просмотр логов"
    echo "0. 🚪 Exit - Выход"
    echo
    echo -n "Введите номер действия [0-6]: "
}

# Информация о системе - исправляем SC2155
show_system_info() {
    show_header
    log_info "Информация о системе:"
    echo "════════════════════════════════════════════════════"
    echo "Hostname: $(hostname)"
    echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
    
    local ssh_status
    ssh_status=$(systemctl is-active ssh 2>/dev/null || echo "unknown")
    echo "SSH Service: $ssh_status"
    
    # SSH конфигурация
    if [[ -f /etc/ssh/sshd_config ]]; then
        local ssh_port
        local password_auth
        ssh_port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}' || echo "22")
        password_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}' || echo "yes")
        echo "SSH Port: $ssh_port"
        echo "Password Auth: $password_auth"
    fi
    
    # UFW статус
    if command -v ufw &>/dev/null; then
        echo "UFW Status: $(ufw status | head -1)"
    else
        echo "UFW Status: not installed"
    fi
    
    echo "════════════════════════════════════════════════════"
}

# Просмотр логов
view_logs() {
    show_header
    if [[ -f "$LOG_FILE" ]]; then
        log_info "Содержимое лога:"
        echo "════════════════════════════════════════════════════"
        cat "$LOG_FILE"
        echo "════════════════════════════════════════════════════"
    else
        log_warning "Файл лога пуст или не найден"
    fi
}

# Полная настройка безопасности
full_security_setup() {
    show_header
    log_warning "🚀 Полная настройка безопасности"
    echo
    echo "Это действие выполнит:"
    echo "  1. Настройку SSH безопасности"
    echo "  2. Конфигурацию файрвола"
    echo "  3. Укрепление системы"
    echo
    read -p "Продолжить? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi
    
    configure_ssh_security
    configure_firewall  
    system_hardening
    
    log_success "🎉 Полная настройка завершена!"
}

# Главная функция
main() {
    # Проверки
    check_root
    check_os
    check_requirements
    
    # Загружаем модули
    load_modules
    
    # Главный цикл
    while true; do
        show_menu
        read -r choice
        echo
        
        case $choice in
            1) configure_ssh_security ;;
            2) configure_firewall ;;
            3) system_hardening ;;
            4) full_security_setup ;;
            5) show_system_info ;;
            6) view_logs ;;
            0) 
                log_info "До свидания! 👋"
                exit 0
                ;;
            *)
                log_error "Неверный выбор: '$choice'"
                sleep 2
                continue
                ;;
        esac
        
        echo
        echo -e "${YELLOW}Нажмите Enter для возврата в главное меню...${NC}"
        read -r
    done
}

# Запуск
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
