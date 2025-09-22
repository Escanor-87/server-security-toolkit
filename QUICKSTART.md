# 🚀 Server Security Toolkit - Quick Start

## Однострочная установка

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Escanor-87/server-security-toolkit/main/install.sh)
```

## Быстрая настройка безопасности

### 1. Запуск
```bash
sudo security-toolkit
```

### 2. Автоматическая настройка (рекомендуется)
```
4. Full Security Setup → Y (использовать конфигурацию)
```

### 3. Ручная настройка SSH
```
1. SSH Security →
   3. Импорт публичного ключа
   1. Смена SSH порта (например: 2200, 2222, 22000)
   5. Отключение парольной авторизации
   6. Отключение root входа
   9. Перезапуск SSH
```

### 4. Проверка статуса
```
1. SSH Security → 4. Показать текущие настройки
3. System Hardening → 7. Показать статус безопасности
```

## ⚠️ Важные моменты

1. **SSH ключи**: Обязательно импортируйте SSH ключи ПЕРЕД отключением парольной авторизации
2. **Тестирование**: Всегда тестируйте SSH подключение в новой сессии перед закрытием текущей
3. **Порты**: При смене SSH порта UFW правила обновляются автоматически
4. **Резервные копии**: Все конфигурации автоматически резервируются

## 🔧 Кастомизация

Отредактируйте `/opt/server-security-toolkit/configs/defaults.env` для автоматизации:

```bash
nano /opt/server-security-toolkit/configs/defaults.env
```

## 📞 Поддержка

- GitHub Issues: https://github.com/Escanor-87/server-security-toolkit/issues
- Документация: README.md в директории установки
