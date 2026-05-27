#!/bin/bash
#############################################################################
# Скрипт подготовки окружения для развёртывания Ceph кластера
# Astra Linux 1.7 (Debian 10), уровень защиты "Орёл"
# 
# Использование: sudo ./00_prerequisites.sh
#############################################################################

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Логирование
LOG_FILE="/var/log/ceph_deployment.log"
mkdir -p "$(dirname "$LOG_FILE")"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

# Проверка возможности использования sudo
if ! sudo -n true 2>/dev/null; then
   log_warn "Требуется доступ к sudo. Введите пароль..."
   sudo true || { log_error "Нет доступа к sudo"; exit 1; }
fi

log_info "===== НАЧАЛО ПОДГОТОВКИ ОКРУЖЕНИЯ ====="
log_info "Хост: $(hostname)"
log_info "ОС: $(lsb_release -d | cut -f2)"
log_info "Ядро: $(uname -r)"

# Обновление системы
log_info "Обновление репозиториев и пакетов..."
apt-get update

# Для Astra Linux: полное обновление отключено по умолчанию
apt-get upgrade -y 2>/dev/null || \
log_warn "apt-get upgrade отключена в системе (Astra Linux). Это нормально для уровня защиты 'Орёл'. Продолжаем без полного обновления."

# Установка базовых утилит (минимальный набор)
log_info "Установка базовых утилит..."
apt-get install -y \
    curl \
    wget \
    net-tools \
    chrony \
    parted \
    lvm2 \
    xfsprogs \
    python3 || true

# Установка опциональных утилит для мониторинга (очень опционально)
log_info "Пакеты мониторинга пропущены (iotop, blktrace и т.д. устанавливаются по требованию)"
# for pkg in iotop-c iotop blktrace fio; do
#     apt-get install -y "$pkg" 2>/dev/null && { log_info "Пакет $pkg установлен"; break; } || true
# done

# Конфигурация NTP/Chrony для синхронизации времени
log_info "Конфигурация синхронизации времени (chrony)..."
systemctl enable chrony
systemctl restart chrony
chronyc tracking

# Отключение SELinux (Astra Linux 1.7 обычно его не использует, но проверим)
log_warn "Проверка SELinux..."
if command -v getenforce &> /dev/null; then
    log_info "SELinux найден. Текущий статус: $(getenforce)"
else
    log_info "SELinux не установлен"
fi

# Конфигурация сети
log_info "Конфигурация сетевых параметров..."
cat >> /etc/sysctl.conf <<EOF

# Параметры для Ceph
net.ipv4.tcp_max_syn_backlog = 4096
net.core.somaxconn = 4096
net.ipv4.tcp_tw_reuse = 1
EOF
sysctl -p 2>/dev/null || log_warn "Некоторые параметры sysctl могут быть недоступны"

# Конфигурация лимитов для Ceph
log_info "Конфигурация пользовательских лимитов..."
cat >> /etc/security/limits.conf <<EOF

# Лимиты для Ceph
* soft nofile 655360
* hard nofile 655360
* soft nproc 655360
* hard nproc 655360
EOF

# Отключение защиты от рассеяния адреса (если требуется)
if grep -q "GRUB_CMDLINE_LINUX" /etc/default/grub; then
    log_info "Проверка параметров GRUB..."
    if ! grep -q "disable_aslr" /etc/default/grub; then
        log_warn "ASLR не отключена. Для критичных приложений может потребоваться отключение."
    fi
fi

# Создание пользователя ceph (если его нет)
if ! id -u ceph &>/dev/null; then
    log_info "Создание пользователя ceph..."
    useradd -m -s /bin/bash ceph
    echo "ceph ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/ceph
    chmod 440 /etc/sudoers.d/ceph
else
    log_info "Пользователь ceph уже существует"
fi

# Конфигурация SSH для бесконтактного доступа
log_info "Проверка SSH конфигурации..."
# NOTE: sshd_config не трогаем - это может вызвать интерактивный диалог системы
log_info "SSH конфигурация оставлена без изменений (используется стандартная Astra Linux)"


# Загрузка модулей ядра
log_info "Проверка необходимых модулей ядра..."
modprobe ceph

# Установка Ceph репозитория
log_info "Добавление репозитория Ceph (Octopus для Debian 10)..."
wget -q -O- 'https://download.ceph.com/keys/release.asc' | apt-key add - 2>/dev/null || true
echo "deb https://download.ceph.com/debian-octopus buster main" | tee /etc/apt/sources.list.d/ceph.list
apt-get update

# Установка базовых пакетов Ceph
log_info "Установка пакетов Ceph..."
apt-get install -y ceph-common ceph-mon ceph-osd ceph-mgr ceph-mds

# Установка поддерживающих инструментов (только необходимые)
log_info "Поддерживающие инструменты пропущены (можно установить вручную при необходимости)"
# Убрано: ceph-deploy (deprecated), radosgw (по требованию), ceph-test (для тестирования)

# Создание директорий для Ceph
log_info "Создание директорий Ceph..."
mkdir -p /etc/ceph
mkdir -p /var/lib/ceph/mon
mkdir -p /var/lib/ceph/osd
mkdir -p /var/lib/ceph/mds
mkdir -p /var/lib/ceph/mgr
mkdir -p /var/lib/ceph/tmp
chown -R astraadm:astraadm /var/lib/ceph
chmod -R 755 /var/lib/ceph

# Установка Python пакетов для мониторинга
log_info "Установка Python зависимостей..."
pip3 install --upgrade pip
pip3 install \
    ansible \
    pyyaml \
    requests

# Конфигурация брандмауэра (UFW)
log_info "Конфигурация брандмауэра..."
if command -v ufw &> /dev/null; then
    ufw default deny incoming
    ufw default allow outgoing
    
    # Порты для Ceph
    ufw allow 22/tcp      # SSH
    ufw allow 6789/tcp    # Ceph Monitor
    ufw allow 6800:7300/tcp # Ceph OSD/MDS
    
    # Порты для OpenNebula
    ufw allow 9869/tcp    # OpenNebula XML-RPC
    ufw allow 4567/tcp    # OpenNebula Sunstone
    
    # Порты для мониторинга
    ufw allow 9090/tcp    # Prometheus
    ufw allow 3000/tcp    # Grafana
    ufw allow 9100/tcp    # Node Exporter
    
    echo "y" | ufw enable
    ufw status
else
    log_warn "UFW не установлен, используется iptables"
fi

log_info "===== ПОДГОТОВКА ОКРУЖЕНИЯ ЗАВЕРШЕНА ====="
log_info "Все логи сохранены в: $LOG_FILE"
