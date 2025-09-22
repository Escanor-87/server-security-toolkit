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
readonly LOGS_DIR="${SCRIPT_DIR}/logs"

# Создаем папку логов
mkdir -p "$LOGS_DIR"

# Файл логов - исправляем SC2155  
LOG_FILE="${LOGS_DIR}/security-$(date +%Y%m%d_%H%M%S).log"
readonly LOG_FILE

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
    echo "║       Ubuntu/Debian Server Hardening Script      ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

# Проверка прав root
check_root() {
    log_info "Проверка прав root..."
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен запускаться с правами root"
        log_info "Запустите: sudo bash $0"
        exit 1
    fi
    log_success "Права root подтверждены"
}

# Проверка операционной системы - исправляем SC1091
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Не удается определить операционную систему"
        exit 1
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
                read -p "Продолжить выполнение? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Выполнение прервано пользователем"
                    exit 1
                fi
            fi
            ;;
        *)
            log_warning "Скрипт оптимизирован для Ubuntu и Debian 12"
            log_info "Обнаружена ОС: $PRETTY_NAME"
            read -p "Продолжить выполнение? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Выполнение прервано пользователем"
                exit 1
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
        exit 1
    fi
    
    log_success "Все системные требования выполнены"
}

# Загрузка модулей
load_modules() {
    log_info "Загрузка модулей из $MODULES_DIR"
    local loaded_count=0
    
    for module in "${MODULES_DIR}"/*.sh; do
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
                    read -p "Очистить все логи? (y/N): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        > "$LOG_FILE"
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
        else
            log_warning "📄 Файл лога пуст или не найден: $LOG_FILE"
            echo
            echo "1. 🔙 Назад в главное меню"
            echo
            read -p "Нажмите 1 для возврата: " -n 1 -r choice
            echo
            if [[ "$choice" == "1" ]]; then
                return 0
            fi
            continue
        fi
        
        if [[ "$choice" != "0" ]]; then
            echo
            read -p "Нажмите Enter для продолжения..." -r
        fi
    done
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
        read -p "Использовать автоматические настройки из конфигурации? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
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
    read -p "Продолжить полную настройку? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
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

# Интерактивная настройка
full_security_setup_interactive() {
    log_info "🎯 Запуск интерактивной настройки..."
    
    configure_ssh_security
    configure_firewall  
    system_hardening
}

# Главная функция
main() {
    log_info "🚀 Запуск Server Security Toolkit v$VERSION"
    log_info "Скрипт запущен из: ${BASH_SOURCE[0]}"
    if [[ -L "${BASH_SOURCE[0]}" ]]; then
        log_info "Символическая ссылка указывает на: $(readlink -f "${BASH_SOURCE[0]}")"
    fi
    log_info "Рабочая директория: $SCRIPT_DIR"
    log_info "Директория модулей: $MODULES_DIR"
    log_info "Файл логов: $LOG_FILE"
    
    # Проверки
    log_info "Выполнение предварительных проверок..."
    check_root
    check_os
    check_requirements
    
    # Загружаем модули
    log_info "Загрузка модулей..."
    if ! load_modules; then
        log_error "Критическая ошибка: не удалось загрузить модули"
        exit 1
    fi
    
    # Главный цикл
    while true; do
        show_menu
        read -r choice
        echo
        
        case $choice in
            1) 
                log_info "Пользователь выбрал: SSH Security"
                if declare -f configure_ssh_security &>/dev/null; then
                    configure_ssh_security
                else
                    log_error "Функция configure_ssh_security не найдена"
                fi
                ;;
            2) 
                log_info "Пользователь выбрал: Firewall Setup"
                if declare -f configure_firewall &>/dev/null; then
                    configure_firewall
                else
                    log_error "Функция configure_firewall не найдена"
                fi
                ;;
            3) 
                log_info "Пользователь выбрал: System Hardening"
                if declare -f system_hardening &>/dev/null; then
                    system_hardening
                else
                    log_error "Функция system_hardening не найдена"
                fi
                ;;
            4) 
                log_info "Пользователь выбрал: Full Security Setup"
                if declare -f full_security_setup &>/dev/null; then
                    full_security_setup
                else
                    log_error "Функция full_security_setup не найдена"
                fi
                ;;
            5) 
                log_info "Пользователь выбрал: System Information"
                show_system_info 
                ;;
            6) 
                log_info "Пользователь выбрал: View Logs"
                view_logs 
                ;;
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
        
        # Подтверждение только для информационных пунктов
        if [[ "$choice" == "5" || "$choice" == "6" ]]; then
            echo
            echo -e "${YELLOW}Нажмите Enter для возврата в главное меню...${NC}"
            read -r
        fi
    done
}

# Запуск
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
