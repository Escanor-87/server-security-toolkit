#!/bin/bash
# Server Security Toolkit - One-line installer
# Usage: bash <(curl -Ls https://raw.githubusercontent.com/Escanor-87/server-security-toolkit/main/install.sh)

set -euo pipefail

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Конфигурация
readonly REPO_URL="https://github.com/Escanor-87/server-security-toolkit.git"
readonly INSTALL_DIR="/opt/server-security-toolkit"
readonly SYMLINK_PATH="/usr/local/bin/security-toolkit"

# Функции логирования
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен запускаться с правами root"
        log_info "Запустите: sudo bash <(curl -Ls https://raw.githubusercontent.com/Escanor-87/server-security-toolkit/main/install.sh)"
        exit 1
    fi
}

# Проверка ОС
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
                read -p "Продолжить установку? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Установка прервана пользователем"
                    exit 1
                fi
            fi
            ;;
        *)
            log_warning "Скрипт оптимизирован для Ubuntu и Debian 12"
            log_info "Обнаружена ОС: $PRETTY_NAME"
            read -p "Продолжить установку? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Установка прервана пользователем"
                exit 1
            fi
            ;;
    esac
}

# Установка зависимостей
install_dependencies() {
    log_info "Установка зависимостей..."
    
    apt update
    apt install -y git curl wget
    
    log_success "Зависимости установлены"
}

# Клонирование репозитория
clone_repository() {
    log_info "Клонирование Server Security Toolkit..."
    
    # Удаляем старую установку если есть
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warning "Найдена существующая установка в $INSTALL_DIR"
        read -p "Удалить и переустановить? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
            log_info "Старая установка удалена"
        else
            log_info "Установка прервана"
            exit 1
        fi
    fi
    
    # Клонируем репозиторий
    git clone "$REPO_URL" "$INSTALL_DIR"
    
    log_success "Репозиторий склонирован в $INSTALL_DIR"
}

# Настройка прав доступа
setup_permissions() {
    log_info "Настройка прав доступа..."
    
    cd "$INSTALL_DIR"
    chmod +x main.sh modules/*.sh tests/*.sh
    
    # Создаем символическую ссылку для удобства
    if [[ -L "$SYMLINK_PATH" ]] || [[ -f "$SYMLINK_PATH" ]]; then
        rm "$SYMLINK_PATH"
    fi
    ln -s "$INSTALL_DIR/main.sh" "$SYMLINK_PATH"
    
    # Проверяем, что символическая ссылка работает
    if [[ -L "$SYMLINK_PATH" ]] && [[ -f "$(readlink -f "$SYMLINK_PATH")" ]]; then
        log_success "Символическая ссылка создана и проверена"
    else
        log_warning "Проблема с символической ссылкой, используйте прямой путь"
    fi
    
    log_success "Права доступа настроены"
    log_info "Создана символическая ссылка: $SYMLINK_PATH"
}

# Показать информацию об установке
show_installation_info() {
    echo
    log_success "🎉 Server Security Toolkit успешно установлен!"
    echo
    echo "📍 Расположение: $INSTALL_DIR"
    echo "🔗 Команда: security-toolkit (или $SYMLINK_PATH)"
    echo
    echo "🚀 Быстрый старт:"
    echo "   sudo security-toolkit"
    echo
    echo "📋 Или перейдите в директорию:"
    echo "   cd $INSTALL_DIR"
    echo "   sudo ./main.sh"
    echo
    echo "🔧 Рекомендуемый порядок настройки:"
    echo "   1. SSH Security → Импорт ключей"
    echo "   2. SSH Security → Смена порта"
    echo "   3. Firewall Setup → Базовая настройка"
    echo "   4. System Hardening → fail2ban + автообновления"
    echo
    echo "⚡ Автоматическая настройка:"
    echo "   sudo security-toolkit → 4. Full Security Setup"
    echo
}

# Главная функция
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║       Server Security Toolkit Installer         ║"
    echo "║            One-line Installation                 ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
    
    check_root
    check_os
    install_dependencies
    clone_repository
    setup_permissions
    show_installation_info
}

# Запуск установки
main "$@"
