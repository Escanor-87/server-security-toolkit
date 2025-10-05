#!/bin/bash

# 🚨 ЭКСТРЕННОЕ ВОССТАНОВЛЕНИЕ SSH ДОСТУПА
# Этот скрипт поможет восстановить SSH доступ после проблем с конфигурацией

echo "🚨 ЭКСТРЕННОЕ ВОССТАНОВЛЕНИЕ SSH ДОСТУПА"
echo "========================================"
echo

# Проверяем права root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Этот скрипт должен запускаться с правами root"
    echo "Используйте: sudo $0"
    exit 1
fi

# Функция логирования
log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ $1"
}

log_warning() {
    echo "⚠️  $1"
}

echo "Что произошло с SSH?"
echo "1. 🔍 Диагностика текущего состояния"
echo "2. 🔧 Восстановить SSH порт на 22"
echo "3. 🛡️  Открыть все SSH порты в UFW (временно)"
echo "4. 🔄 Перезапустить SSH службу"
echo "5. 📋 Показать текущую SSH конфигурацию"
echo "6. 🔙 Восстановить из последнего бекапа"
echo "0. 🚪 Выход"
echo

read -p "Выберите действие [0-6]: " -n 1 -r choice
echo
echo

case $choice in
    1)
        log_info "🔍 ДИАГНОСТИКА SSH"
        echo "==================="
        
        echo "📋 Текущий SSH порт в конфигурации:"
        grep "^Port" /etc/ssh/sshd_config 2>/dev/null || echo "Порт не задан (по умолчанию 22)"
        
        echo
        echo "🔥 Статус SSH службы:"
        systemctl status ssh --no-pager -l
        
        echo
        echo "🛡️  Статус UFW:"
        ufw status numbered
        
        echo
        echo "🔍 Активные SSH соединения:"
        ss -tlnp | grep ssh || echo "SSH соединения не найдены"
        
        echo
        echo "📝 Последние строки SSH лога:"
        journalctl -u ssh -n 10 --no-pager
        ;;
        
    2)
        log_info "🔧 ВОССТАНОВЛЕНИЕ SSH ПОРТА НА 22"
        echo "=================================="
        
        # Создаем бекап
        cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.emergency_backup.$(date +%Y%m%d_%H%M%S)"
        log_success "Создан бекап конфигурации"
        
        # Устанавливаем порт 22
        if grep -q "^Port" /etc/ssh/sshd_config; then
            sed -i 's/^Port.*/Port 22/' /etc/ssh/sshd_config
        else
            echo "Port 22" >> /etc/ssh/sshd_config
        fi
        log_success "SSH порт установлен на 22"
        
        # Проверяем конфигурацию
        if sshd -t; then
            log_success "Конфигурация SSH корректна"
            systemctl restart ssh
            log_success "SSH служба перезапущена"
        else
            log_error "Ошибка в конфигурации SSH!"
            sshd -t
        fi
        ;;
        
    3)
        log_info "🛡️  ОТКРЫТИЕ ВСЕХ SSH ПОРТОВ В UFW"
        echo "=================================="
        
        if command -v ufw &>/dev/null; then
            # Открываем стандартные SSH порты
            for port in 22 2222 2200 2022; do
                ufw allow $port/tcp comment "Emergency SSH"
                log_success "Открыт порт $port/tcp"
            done
            
            ufw status numbered
        else
            log_warning "UFW не установлен"
        fi
        ;;
        
    4)
        log_info "🔄 ПЕРЕЗАПУСК SSH СЛУЖБЫ"
        echo "========================"
        
        # Проверяем конфигурацию
        if sshd -t; then
            log_success "Конфигурация SSH корректна"
            systemctl restart ssh
            if systemctl is-active --quiet ssh; then
                log_success "SSH служба успешно перезапущена"
                
                # Показываем на каких портах слушает SSH
                echo
                log_info "SSH слушает на портах:"
                ss -tlnp | grep ssh
            else
                log_error "SSH служба не запустилась!"
                systemctl status ssh --no-pager
            fi
        else
            log_error "Ошибка в конфигурации SSH!"
            sshd -t
        fi
        ;;
        
    5)
        log_info "📋 ТЕКУЩАЯ SSH КОНФИГУРАЦИЯ"
        echo "==========================="
        
        echo "Файл: /etc/ssh/sshd_config"
        echo "=========================="
        grep -E "^(Port|PasswordAuthentication|PermitRootLogin|PubkeyAuthentication)" /etc/ssh/sshd_config || echo "Основные параметры используют значения по умолчанию"
        
        echo
        echo "Все активные параметры:"
        echo "======================"
        grep -v "^#" /etc/ssh/sshd_config | grep -v "^$"
        ;;
        
    6)
        log_info "🔙 ВОССТАНОВЛЕНИЕ ИЗ БЕКАПА"
        echo "=========================="
        
        # Ищем бекапы
        mapfile -t backup_files < <(find /etc/ssh -name "sshd_config.backup.*" 2>/dev/null | sort -r)
        
        if [[ ${#backup_files[@]} -eq 0 ]]; then
            log_warning "Резервные копии SSH конфигурации не найдены"
        else
            echo "Найденные резервные копии:"
            for i in "${!backup_files[@]}"; do
                echo "$((i+1)). $(basename "${backup_files[$i]}")"
            done
            
            echo
            read -p "Введите номер бекапа для восстановления [1-${#backup_files[@]}]: " -r backup_num
            
            if [[ "$backup_num" =~ ^[0-9]+$ ]] && [[ "$backup_num" -ge 1 ]] && [[ "$backup_num" -le ${#backup_files[@]} ]]; then
                selected_backup="${backup_files[$((backup_num-1))]}"
                
                # Создаем бекап текущего файла
                cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.before_restore.$(date +%Y%m%d_%H%M%S)"
                
                # Восстанавливаем
                cp "$selected_backup" /etc/ssh/sshd_config
                log_success "Конфигурация восстановлена из $(basename "$selected_backup")"
                
                # Проверяем и перезапускаем
                if sshd -t; then
                    systemctl restart ssh
                    log_success "SSH служба перезапущена"
                else
                    log_error "Восстановленная конфигурация содержит ошибки!"
                    sshd -t
                fi
            else
                log_error "Неверный номер бекапа"
            fi
        fi
        ;;
        
    0)
        log_info "Выход из скрипта восстановления"
        exit 0
        ;;
        
    *)
        log_error "Неверный выбор: '$choice'"
        ;;
esac

echo
echo "🔧 РЕКОМЕНДАЦИИ ПО ВОССТАНОВЛЕНИЮ ДОСТУПА:"
echo "========================================="
echo "1. Если у вас есть физический доступ к серверу - используйте его"
echo "2. Если есть другой способ подключения (VNC, консоль) - используйте его"
echo "3. Попробуйте подключиться к разным портам: 22, 2222, 2200, 2022"
echo "4. Проверьте UFW правила: sudo ufw status"
echo "5. Проверьте SSH службу: sudo systemctl status ssh"
echo
echo "🚨 В КРИТИЧЕСКОЙ СИТУАЦИИ:"
echo "========================="
echo "sudo systemctl stop ufw    # Отключить файрвол"
echo "sudo ufw --force reset     # Сбросить все правила UFW"
echo "sudo ufw allow 22/tcp      # Открыть SSH"
echo "sudo ufw enable            # Включить UFW"
echo
read -p "Нажмите Enter для завершения..." -r
