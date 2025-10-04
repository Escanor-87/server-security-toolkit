#!/bin/bash
# Скрипт для обновления f2b алиаса

echo "🔧 Обновление f2b алиаса и удаление старого ss..."

# Удаляем старый алиас ss если существует
if [[ -L "/usr/local/bin/ss" ]] || [[ -f "/usr/local/bin/ss" ]]; then
    rm "/usr/local/bin/ss"
    echo "✅ Удален старый алиас ss"
fi

# Создаем новый f2b скрипт
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

echo "✅ f2b алиас обновлен!"
echo "Проверьте: f2b help"
