#!/bin/bash

# ==============================================================================
# 📘 UNIVERSAL SYSTEM CLEANER & LOG ROTATOR (Linux)
#
# Этот скрипт помогает обслуживать Linux-серверы:
# ▪ Настраивает автоматическую ротацию логов (logrotate + journald)
# ▪ Очищает системные и бинарные логи вручную
# ▪ Удаляет Docker-мусор (контейнеры, образы, сети)
# ▪ Удаляет временные архивы
# ▪ Очищает системный и пользовательский кэш
#
# 🔧 Поддерживает безопасную автоматизацию для продакшн-серверов
# 💣 Поддерживает ручную глубокую очистку (если нужно освободить место)
# 📋 Предлагает меню, чтобы выбрать нужные действия
#
# Поддержка: Ubuntu, Debian, Linux VPS
# ==============================================================================

### 🔹 Общая функция: подтверждение действия пользователя
confirm() {
    local prompt="$1"
    read -p "$prompt [y/n, Enter = yes]: " choice
    case "$choice" in
        ""|y|Y|yes|Yes) return 0 ;;    # Подтверждение
        n|N|no|No) return 1 ;;         # Отказ
        *) echo "Пожалуйста, введите y или n."; confirm "$prompt" ;;  # Повтор при ошибке
    esac
}

### 🔹 Проверка на ошибку после команды (и аварийный выход)
check_success() {
    if [ $? -ne 0 ]; then
        echo "❌ Ошибка на этапе: $1"
        exit 1
    fi
}

### 1️⃣ Настройка logrotate для автоматической ротации логов
# Создаёт файл /etc/logrotate.d/my_syslog_kernlog
# Ограничивает syslog и kern.log до 100MB, с ежедневной ротацией
setup_logrotate() {
    echo "Установка и настройка logrotate..."
    sudo apt update && sudo apt install -y logrotate
    check_success "установка logrotate"

    sudo tee /etc/logrotate.d/my_syslog_kernlog > /dev/null <<EOL
/var/log/syslog /var/log/kern.log {
    daily
    rotate 1
    size 100M
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    postrotate
        systemctl reload rsyslog > /dev/null 2>/dev/null || true
    endscript
}
EOL
    sudo logrotate -f /etc/logrotate.d/my_syslog_kernlog -v
    echo "✅ logrotate настроен для syslog и kern.log"
}

### 2️⃣ Настройка journald — ограничивает бинарные логи systemd
# Задаёт лимит по размеру (100MB) и времени хранения (2 дня)
setup_journald() {
    echo "Настройка journald..."
    sudo tee /etc/systemd/journald.conf > /dev/null <<EOL
[Journal]
SystemMaxUse=100M
MaxRetentionSec=2d
EOL
    sudo systemctl restart systemd-journald.socket
    sudo systemctl restart systemd-journald
    echo "✅ journald настроен"
}

### 3️⃣ Установка rsyslog — логирует события в /var/log
# Если по каким-то причинам отсутствует (редко)
install_rsyslog() {
    echo "Установка rsyslog..."
    sudo apt update && sudo apt install -y rsyslog
    check_success "установка rsyslog"
    echo "✅ rsyslog установлен"
}

### 4️⃣ Очистка логов вручную (агрессивный способ)
# Удаляет syslog, kern.log, бинарные журналы journald и архивы логов
# Использовать осторожно (например, при нехватке места)
clear_logs() {
    if confirm "Удалить все системные и бинарные логи?"; then
        sudo journalctl --vacuum-time=1s
        sudo find /var/log -type f \( -name "*.gz" -o -name "*.xz" -o -name "*.tar" -o -name "*.zip" \) -delete
        sudo rm -f /var/log/syslog* /var/log/kern.log*
        sudo systemctl restart rsyslog
        echo "✅ Логи очищены"
    fi
}

### 5️⃣ Очистка Docker: удаляет неиспользуемые контейнеры, образы, тома и сети
# Используется, если вы тестировали и оставили мусор в Docker
clear_docker() {
    if confirm "Удалить все неиспользуемые docker-ресурсы (контейнеры, образы, сети)?"; then
        sudo docker system prune -a -f
        echo "✅ Docker очищен"
    fi
}

### 6️⃣ Удаление архивов в текущей директории (*.tar, *.gz, *.zip)
# Удобно для быстрой чистки папки загрузок или билдов
delete_archives() {
    if confirm "Удалить все архивы в текущей директории (*.tar, *.gz, *.zip)?"; then
        find . -type f \( -name "*.tar" -o -name "*.gz" -o -name "*.zip" \) -exec rm -v {} \;
        echo "✅ Архивы удалены"
    fi
}

### 7️⃣ Очистка системного и пользовательского кэша
# Удаляет: apt-кэш, пакеты, thumbnails, pagecache
# Полезно после обновлений, сборок, длительной работы
clear_cache() {
    if confirm "Очистить кэш (apt, thumbnails, drop_caches)?"; then
        sudo apt clean
        sudo apt autoremove --purge -y
        sudo sync; sudo sysctl -w vm.drop_caches=3
        rm -rf ~/.cache/thumbnails/*
        echo "✅ Кэш очищен"
    fi
}

### 8️⃣ Главное меню
# Предлагает выбор действия: безопасная настройка или агрессивная очистка
main_menu() {
    while true; do
        echo ""
        echo "========= 🧹 UNIVERSAL SYSTEM CLEANER ========="
        echo "1) Настроить logrotate (ротация логов)"
        echo "2) Настроить journald (лимит бинарных логов)"
        echo "3) Установить rsyslog (если не установлен)"
        echo "4) Очистить логи вручную (агрессивно)"
        echo "5) Очистить Docker (контейнеры/образы)"
        echo "6) Удалить архивы в текущей папке"
        echo "7) Очистить системный кэш"
        echo "8) Выполнить всё сразу (Safe Mode: 1–3 + 5–7)"
        echo "0) Выйти"
        echo "==============================================="
        read -p "Выберите действие: " choice

        case "$choice" in
            1) setup_logrotate ;;
            2) setup_journald ;;
            3) install_rsyslog ;;
            4) clear_logs ;;
            5) clear_docker ;;
            6) delete_archives ;;
            7) clear_cache ;;
            8)
                setup_logrotate
                setup_journald
                install_rsyslog
                clear_docker
                delete_archives
                clear_cache
                ;;
            0) echo "Выход."; exit 0 ;;
            *) echo "❌ Неверный выбор. Попробуйте снова." ;;
        esac
    done
}

# Запуск основного меню
main_menu
