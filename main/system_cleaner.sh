#!/bin/bash

# ===== Загрузка логотипа из GitHub =====
LOGO_URL="https://raw.githubusercontent.com/Sshadow84/system_cleaner/main/logo_new.sh"
TMP_LOGO="/tmp/logo_new.sh"

curl -sL "$LOGO_URL" -o "$TMP_LOGO"
if [[ -f "$TMP_LOGO" ]]; then
  source "$TMP_LOGO"
  channel_logo
  rm -f "$TMP_LOGO"
else
  echo "🔕 Логотип не загружен. Продолжаем без логотипа."
fi

# ===== Подтверждение =====
confirm() {
    local prompt="$1"
    read -p "$prompt [y/n, Enter = yes]: " choice
    case "$choice" in
        ""|y|Y|yes|Yes) return 0 ;;
        n|N|no|No) return 1 ;;
        *) echo "Пожалуйста, введите y или n."; confirm "$prompt" ;;
    esac
}

# ===== Ошибки =====
check_success() {
    if [ $? -ne 0 ]; then
        echo "❌ Ошибка на этапе: $1"
        exit 1
    fi
}

# ===== logrotate =====
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
    echo "✅ logrotate настроен"
}

# ===== journald =====
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

# ===== rsyslog =====
install_rsyslog() {
    echo "Установка rsyslog..."
    sudo apt update && sudo apt install -y rsyslog
    check_success "установка rsyslog"
    echo "✅ rsyslog установлен"
}

# ===== Очистка логов =====
clear_logs() {
    if confirm "Удалить все системные и бинарные логи?"; then
        sudo journalctl --vacuum-time=1s
        sudo find /var/log -type f \( -name "*.gz" -o -name "*.xz" -o -name "*.tar" -o -name "*.zip" \) -delete
        sudo rm -f /var/log/syslog* /var/log/kern.log*
        sudo systemctl restart rsyslog
        echo "✅ Логи очищены"
    fi
}

# ===== Docker =====
clear_docker() {
    if confirm "Удалить все неиспользуемые docker-ресурсы?"; then
        sudo docker system prune -a -f
        echo "✅ Docker очищен"
    fi
}

# ===== Архивы =====
delete_archives() {
    if confirm "Удалить все архивы в текущей директории (*.tar, *.gz, *.zip)?"; then
        find . -type f \( -name "*.tar" -o -name "*.gz" -o -name "*.zip" \) -exec rm -v {} \;
        echo "✅ Архивы удалены"
    fi
}

# ===== Кэш =====
clear_cache() {
    if confirm "Очистить кэш (apt, thumbnails, drop_caches)?"; then
        sudo apt clean
        sudo apt autoremove --purge -y
        sudo sync; sudo sysctl -w vm.drop_caches=3
        rm -rf ~/.cache/thumbnails/*
        echo "✅ Кэш очищен"
    fi
}

# ===== Главное меню =====
main_menu() {
    while true; do
        echo ""
        echo "========= 🧹 UNIVERSAL SYSTEM CLEANER ========="
        echo "1) Настроить logrotate"
        echo "2) Настроить journald"
        echo "3) Установить rsyslog"
        echo "4) Очистить логи вручную"
        echo "5) Очистить Docker"
        echo "6) Удалить архивы"
        echo "7) Очистить системный кэш"
        echo "8) Выполнить всё сразу (Safe Mode)"
        echo "0) Выйти"
        echo "==============================================="
        read -rp "Выберите действие: " choice

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

main_menu
