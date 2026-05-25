#!/bin/bash
#############################################################################
# Скрипт подготовки узлов кластера Ceph
# Выполняется на каждом узле (astra-monitor1, astra-node1-3)
# 
# Использование: sudo ./01_node_prepare.sh [node_name] [node_ip]
# Пример: sudo ./01_node_prepare.sh astra-node1 192.168.1.101
#############################################################################

set -e

LOG_FILE="/var/log/ceph_deployment.log"

log_info() {
    echo "[INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "[WARN] $1" | tee -a "$LOG_FILE"
}

# Проверка возможности использования sudo
if ! sudo -n true 2>/dev/null; then
   log_warn "Требуется доступ к sudo. Введите пароль..."
   sudo true || { log_error "Нет доступа к sudo"; exit 1; }
fi

# Получение параметров
NODE_NAME="${1:-$(hostname)}"
NODE_IP="${2:-$(hostname -I | awk '{print $1}')}"

log_info "===== ПОДГОТОВКА УЗЛА: $NODE_NAME ($NODE_IP) ====="

# Конфигурация имени хоста
if [[ $(hostname) != "$NODE_NAME" ]]; then
    log_info "Установка имени хоста на: $NODE_NAME"
    hostnamectl set-hostname "$NODE_NAME"
fi

# Обновление /etc/hosts
log_info "Обновление /etc/hosts..."
if ! grep -q "$NODE_IP.*$NODE_NAME" /etc/hosts; then
    echo "$NODE_IP  $NODE_NAME" >> /etc/hosts
fi

# Обновление репозиториев
log_info "Обновление репозиториев..."
apt-get update 2>/dev/null || log_warn "Ошибка при обновлении репозиториев, продолжаем"

# Получение информации об устройствах хранения
log_info "Информация об устройствах хранения:"
lsblk -n -o NAME,SIZE,TYPE | grep -E "^(sd|nvme|vd)" | head -20 | tee -a "$LOG_FILE"

# Конфигурация сетевых интерфейсов для разных сетей Ceph
log_info "Конфигурация сетевых интерфейсов..."
ip addr show | tee -a "$LOG_FILE"

# Проверка и создание необходимых директорий
log_info "Создание необходимых директорий..."
mkdir -p /etc/ceph
mkdir -p /var/lib/ceph/{mon,osd,mds,mgr,tmp}
mkdir -p /var/log/ceph

# Конфигурация директорий для OSD
if [[ "$NODE_NAME" == *"node"* ]]; then
    log_info "Подготовка хранилищ OSD..."
    
    # Создание точек монтирования для OSD (если используются отдельные диски)
    for i in {1..3}; do
        OSD_PATH="/var/lib/ceph/osd/osd-$i"
        if [[ ! -d "$OSD_PATH" ]]; then
            mkdir -p "$OSD_PATH"
            log_info "Создана директория OSD: $OSD_PATH"
        fi
    done
fi

# Установка утилит мониторинга
log_info "Установка утилит мониторинга..."
apt-get install -y sysstat || true

# Установка опциональных утилит мониторинга
log_info "Установка мониторинга I/O..."
for pkg in iotop-c iotop blktrace fio; do
    apt-get install -y "$pkg" 2>/dev/null && { log_info "Пакет $pkg установлен"; break; } || true
done

# Конфигурация логирования
log_info "Конфигурация логирования..."
mkdir -p /var/log/ceph
touch /var/log/ceph/ceph.log
chown -R ceph:ceph /var/log/ceph

# Установка Node Exporter для Prometheus
log_info "Установка Node Exporter..."
if ! command -v node_exporter &> /dev/null; then
    LATEST_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
    cd /tmp
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${LATEST_VERSION}/node_exporter-${LATEST_VERSION}.linux-amd64.tar.gz"
    tar xzf "node_exporter-${LATEST_VERSION}.linux-amd64.tar.gz"
    cp "node_exporter-${LATEST_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
    rm -rf "node_exporter-${LATEST_VERSION}.linux-amd64"*
    
    # Создание systemd сервиса для Node Exporter
    cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter \\
  --collector.filesystem.mount-points-exclude=^/(proc|sys|dev|host|etc)($$|/)
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
    log_info "Node Exporter установлен и запущен"
else
    log_info "Node Exporter уже установлен"
fi

# Установка Ceph exporter для дополнительного мониторинга
log_info "Установка Ceph Exporter..."
pip3 install --upgrade ceph-exporter 2>/dev/null || log_info "Ceph Exporter уже установлен или недоступен"

# Конфигурация SELinux/AppArmor для уровня защиты "Орёл"
log_info "Проверка политик безопасности..."
if command -v aa-enforce &> /dev/null; then
    log_info "AppArmor обнаружен, текущий режим: $(aa-status 2>/dev/null | grep 'mode:' | head -1)"
fi

# Опциональная конфигурация управления питанием для лучшей стабильности
# (может быть недоступно на защищённых системах - пропускаем с warning)
log_info "Попытка конфигурации управления питанием..."
if command -v cpupower &> /dev/null; then
    if cpupower idle-set -D 0 2>/dev/null; then
        log_info "Энергосбережение отключено через cpupower"
    else
        log_warn "Не удалось отключить энергосбережение (может быть ограничено на защищённых системах)"
    fi
else
    log_warn "cpupower недоступен - управление питанием пропускается (это нормально)"
fi

# Включение IPv6 (если требуется)
log_info "Проверка IPv6..."
if grep -q "ipv6.disable=1" /boot/grub/grub.cfg; then
    log_info "IPv6 отключен"
fi

log_info "===== ПОДГОТОВКА УЗЛА $NODE_NAME ЗАВЕРШЕНА ====="
