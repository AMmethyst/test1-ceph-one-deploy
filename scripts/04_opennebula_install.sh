#!/bin/bash
#############################################################################
# Скрипт установки OpenNebula из .deb файлов
# Использует .deb файлы из текущей директории или указанной папки
# 
# Использование: sudo ./04_opennebula_install.sh [deb_path]
# Пример: sudo ./04_opennebula_install.sh /path/to/deb/files
#############################################################################

set -e

LOG_FILE="/var/log/ceph_deployment.log"

log_info() {
    echo "[INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $1" | tee -a "$LOG_FILE"
    exit 1
}

log_warn() {
    echo "[WARN] $1" | tee -a "$LOG_FILE"
}

if [[ $EUID -ne 0 ]]; then
   log_error "Этот скрипт должен быть запущен с правами root"
fi

# Путь к .deb файлам
DEB_PATH="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info "===== УСТАНОВКА OpenNebula ====="
log_info "Директория .deb файлов: $DEB_PATH"

# Проверка наличия .deb файлов
if ! ls "$DEB_PATH"/*.deb &>/dev/null; then
    log_error "Не найдены .deb файлы в: $DEB_PATH"
fi

log_info "Найдены .deb файлы:"
ls -lh "$DEB_PATH"/*.deb | tee -a "$LOG_FILE"

# Установка зависимостей
log_info "Установка зависимостей..."
apt-get update
apt-get install -y \
    mysql-server \
    ruby \
    ruby-dev \
    libmysql++-dev \
    libcurl4-gnutls-dev \
    libssl-dev \
    libxml2-dev \
    build-essential \
    g++ \
    libsqlite3-dev \
    git \
    wget \
    curl \
    openssh-server

# Создание пользователя oneadmin (если его нет)
if ! id -u oneadmin &>/dev/null; then
    log_info "Создание пользователя oneadmin..."
    useradd -m -s /bin/bash oneadmin
    usermod -aG sudo oneadmin
    
    # Настройка sudoers для oneadmin
    echo "oneadmin ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/oneadmin
    chmod 440 /etc/sudoers.d/oneadmin
else
    log_info "Пользователь oneadmin уже существует"
fi

# Установка .deb пакетов
log_info "Установка OpenNebula пакетов..."
for deb_file in "$DEB_PATH"/*.deb; do
    log_info "Установка: $(basename "$deb_file")"
    dpkg -i "$deb_file" || apt-get install -f -y
done

# Разрешение зависимостей
log_info "Разрешение зависимостей..."
apt-get install -f -y

# Конфигурация MySQL для OpenNebula
log_info "Конфигурация базы данных MySQL..."
systemctl enable mysql
systemctl restart mysql

# Создание базы данных для OpenNebula
MYSQL_PASS=$(openssl rand -base64 12)
log_info "Пароль MySQL для OpenNebula (сохраните в безопасном месте): $MYSQL_PASS"

mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS opennebula CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 'oneadmin'@'localhost' IDENTIFIED BY '$MYSQL_PASS';
GRANT ALL PRIVILEGES ON opennebula.* TO 'oneadmin'@'localhost';
FLUSH PRIVILEGES;
EOF

# Сохранение пароля для дальнейшего использования
echo "$MYSQL_PASS" > /etc/opennebula/db_password.txt
chown oneadmin:oneadmin /etc/opennebula/db_password.txt
chmod 600 /etc/opennebula/db_password.txt

# Конфигурация OpenNebula
log_info "Конфигурация OpenNebula..."

# Обновление конфигурационного файла для использования MySQL
if [[ -f /etc/opennebula/oned.conf ]]; then
    sed -i "s/^#\?DB = \[ backend = \"sqlite\" \]/DB = [ backend = \"mysql\", server = \"localhost\", user = \"oneadmin\", passwd = \"$MYSQL_PASS\", db_name = \"opennebula\" ]/g" /etc/opennebula/oned.conf
    log_info "oned.conf обновлен для использования MySQL"
fi

# Инициализация БД OpenNebula
log_info "Инициализация базы данных OpenNebula..."
su - oneadmin -c "onedb create -s mysql://oneadmin:$MYSQL_PASS@localhost/opennebula" 2>/dev/null || \
log_warn "База данных могла быть уже инициализирована"

# Включение и запуск OpenNebula демона
log_info "Запуск OpenNebula сервисов..."
systemctl enable opennebula
systemctl enable opennebula-sunstone
systemctl restart opennebula
systemctl restart opennebula-sunstone
sleep 3

# Проверка статуса
log_info "Проверка статуса OpenNebula..."
su - oneadmin -c "onehost list" | tee -a "$LOG_FILE" || log_warn "OpenNebula ещё инициализируется"
su - oneadmin -c "onevm list" | tee -a "$LOG_FILE" || log_warn "onevm list ещё недоступен"

# Конфигурирование интеграции с Ceph (RBD)
log_info "Конфигурирование интеграции OpenNebula с Ceph..."

# Получение ключа Ceph для OpenNebula
if [[ -f /etc/ceph/ceph.client.admin.keyring ]]; then
    # Создание пула для VM дисков (если используется)
    ceph osd pool create one-compute 32 32 2>/dev/null || log_warn "Пул one-compute уже существует"
    
    # Копирование ключей Ceph для OpenNebula
    mkdir -p /etc/opennebula/ceph
    cp /etc/ceph/ceph.client.admin.keyring /etc/opennebula/ceph/
    chown -R oneadmin:oneadmin /etc/opennebula/ceph
    chmod 600 /etc/opennebula/ceph/ceph.client.admin.keyring
    
    log_info "Ключи Ceph скопированы для OpenNebula"
fi

# Конфигурация Sunstone (веб-интерфейс)
log_info "Конфигурация Sunstone веб-интерфейса..."

if [[ -f /etc/opennebula/sunstone-server.conf ]]; then
    # Включение SSL/TLS (рекомендуется для "Орла")
    sed -i 's/:host:.*/&\n:secure: true/' /etc/opennebula/sunstone-server.conf || true
fi

# Создание начального пользователя (если требуется)
log_info "Создание начального администратора (если требуется)..."
su - oneadmin -c "oneuser show admin &>/dev/null" || {
    ADMIN_PASS=$(openssl rand -base64 12)
    su - oneadmin -c "oneuser create admin '$ADMIN_PASS'"
    su - oneadmin -c "oneuser grant admin 0 A"
    log_info "Администратор 'admin' создан, пароль: $ADMIN_PASS"
    echo "admin:$ADMIN_PASS" >> /etc/opennebula/initial_credentials.txt
}

# Открытие портов в брандмауэре
log_info "Конфигурация брандмауэра для OpenNebula..."
if command -v ufw &> /dev/null; then
    ufw allow 4567/tcp  # Sunstone
    ufw allow 9869/tcp  # XML-RPC
    ufw allow 5640/tcp  # VNC
    ufw status | tee -a "$LOG_FILE"
fi

log_info "===== УСТАНОВКА OpenNebula ЗАВЕРШЕНА ====="
log_info "Sunstone (веб): https://$(hostname -I | awk '{print $1}'):4567"
log_info "XML-RPC порт: 9869"
log_info "Начальные учётные данные сохранены в: /etc/opennebula/initial_credentials.txt"
log_info "Пароль MySQL: /etc/opennebula/db_password.txt"
log_info "Все логи: $LOG_FILE"
