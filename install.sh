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
    
    # Проверяем существующую установку
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warning "Найдена существующая установка в $INSTALL_DIR"
        read -p "Обновить установку? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
            log_info "Старая установка удалена для обновления"
            # Клонируем репозиторий
            git clone "$REPO_URL" "$INSTALL_DIR"
            log_success "Репозиторий обновлен в $INSTALL_DIR"
        else
            log_info "Используем существующую установку"
            # Запускаем существующую версию
            log_success "Запуск установленной версии Security Toolkit..."
            exec "$INSTALL_DIR/main.sh"
        fi
    else
        # Клонируем репозиторий (новая установка)
        git clone "$REPO_URL" "$INSTALL_DIR"
        log_success "Репозиторий склонирован в $INSTALL_DIR"
    fi
}

# Настройка прав доступа
setup_permissions() {
    log_info "Настройка прав доступа..."
    
    cd "$INSTALL_DIR"
    chmod +x main.sh modules/*.sh tests/*.sh
    
    # Удаляем старый алиас ss если существует
    if [[ -L "/usr/local/bin/ss" ]] || [[ -f "/usr/local/bin/ss" ]]; then
        rm "/usr/local/bin/ss"
        log_info "Удален старый алиас ss"
    fi
    
    # Создаем символическую ссылку для удобства
    if [[ -L "$SYMLINK_PATH" ]] || [[ -f "$SYMLINK_PATH" ]]; then
        rm "$SYMLINK_PATH"
    fi
    ln -s "$INSTALL_DIR/main.sh" "$SYMLINK_PATH"
    
    # Создаем короткий алиас sst
    local short_alias="/usr/local/bin/sst"
    if [[ -L "$short_alias" ]] || [[ -f "$short_alias" ]]; then
        rm "$short_alias"
    fi
    ln -s "$INSTALL_DIR/main.sh" "$short_alias"
    
    # Проверяем, что символические ссылки работают
    if [[ -L "$SYMLINK_PATH" ]] && [[ -f "$(readlink -f "$SYMLINK_PATH")" ]]; then
        log_success "Символическая ссылка security-toolkit создана и проверена"
    else
        log_warning "Проблема с символической ссылкой security-toolkit"
    fi
    
    if [[ -L "$short_alias" ]] && [[ -f "$(readlink -f "$short_alias")" ]]; then
        log_success "Короткий алиас sst создан и проверен"
    else
        log_warning "Проблема с алиасом sst"
    fi
    
    # Создаем алиасы для fail2ban
    create_fail2ban_aliases
    
    log_success "Права доступа настроены"
    log_info "Создана символическая ссылка: $SYMLINK_PATH"
}

# Создание алиасов для fail2ban
create_fail2ban_aliases() {
    log_info "Создание алиасов для fail2ban..."
    
    # Создаем скрипт-обертку для fail2ban
    cat > /usr/local/bin/f2b << 'EOF'
#!/bin/bash
# fail2ban alias wrapper

case "${1:-help}" in
    "list"|"l")
        if ! command -v fail2ban-client &>/dev/null; then
            echo "❌ fail2ban не установлен"
            exit 1
        fi
        
        echo "🔒 Статус fail2ban и заблокированные IP:"
        echo "════════════════════════════════════════"
        
        # Получаем список jail'ов
        jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | sed 's/.*Jail list://' | tr ',' ' ')
        
        if [[ -z "$jails" ]]; then
            echo "⚠️  Нет активных jail'ов"
            exit 0
        fi
        
        total_banned=0
        for jail in $jails; do
            jail=$(echo "$jail" | xargs)  # trim whitespace
            if [[ -n "$jail" ]]; then
                jail_status=$(fail2ban-client status "$jail" 2>/dev/null)
                banned_count=$(echo "$jail_status" | grep "Currently banned:" | awk '{print $3}')
                banned_ips=$(echo "$jail_status" | grep "Banned IP list:" | sed 's/.*Banned IP list://')
                
                echo "📋 Jail: $jail"
                echo "   Заблокировано: ${banned_count:-0} IP"
                if [[ -n "$banned_ips" && "$banned_ips" != " " ]]; then
                    echo "   IP адреса: $banned_ips"
                    if [[ "$banned_count" =~ ^[0-9]+$ ]]; then
                        total_banned=$((total_banned + banned_count))
                    fi
                fi
                echo
            fi
        done
        
        echo "📊 Всего заблокировано IP: $total_banned"
        ;;
    "status"|"s")
        echo "📊 Статус fail2ban:"
        echo "════════════════════════════════════════"
        fail2ban-client status
        ;;
    "unban"|"u")
        if [[ -z "$2" ]]; then
            echo "❌ Укажите IP для разблокировки: f2b unban <IP>"
            exit 1
        fi
        echo "🔓 Разблокировка IP: $2"
        fail2ban-client set sshd unbanip "$2"
        ;;
    "ban"|"b")
        if [[ -z "$2" ]]; then
            echo "❌ Укажите IP для блокировки: f2b ban <IP>"
            exit 1
        fi
        echo "🔒 Блокировка IP: $2"
        fail2ban-client set sshd banip "$2"
        ;;
    "reload"|"r")
        echo "🔄 Перезагрузка fail2ban..."
        systemctl reload fail2ban
        echo "✅ fail2ban перезагружен"
        ;;
    "log"|"logs")
        echo "📋 Последние логи fail2ban:"
        echo "════════════════════════════════════════"
        journalctl -u fail2ban -n 20 --no-pager
        ;;
    "help"|"h"|*)
        echo "🛡️  fail2ban Quick Commands (f2b):"
        echo "════════════════════════════════════════"
        echo "f2b list     (l) - Показать заблокированные IP"
        echo "f2b status   (s) - Статус fail2ban"
        echo "f2b ban <IP> (b) - Заблокировать IP"
        echo "f2b unban <IP> (u) - Разблокировать IP"
        echo "f2b reload   (r) - Перезагрузить fail2ban"
        echo "f2b log      - Показать логи"
        echo "f2b help     (h) - Эта справка"
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/f2b
    
    if [[ -f /usr/local/bin/f2b ]]; then
        log_success "Алиас f2b создан (fail2ban quick commands)"
        log_info "Использование: f2b list, f2b status, f2b ban <IP>, f2b unban <IP>"
    else
        log_warning "Не удалось создать алиас f2b"
    fi
}

# Показать информацию об установке
show_installation_info() {
    echo
    log_success "🎉 Server Security Toolkit успешно установлен!"
    echo
    echo "📍 Расположение: $INSTALL_DIR"
    echo "🔗 Команды: sst | security-toolkit | f2b"
    echo
    echo "🚀 Быстрый старт:"
    echo "   sudo sst             # Security Toolkit"
    echo "   f2b list             # fail2ban статус"
    echo "   f2b help             # fail2ban команды"
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
