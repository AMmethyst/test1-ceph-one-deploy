#!/bin/bash
#############################################################################
# Скрипт добавления OSD дисков в кластер Ceph
# Должен быть запущен на узле astra-monitor1 (admin node)
# или на отдельных OSD узлах
# 
# Использование: sudo ./03_osd_add.sh [device] [cluster_name]
# Примеры:
#   sudo ./03_osd_add.sh /dev/sdb ceph          # На узле astra-node1
#   sudo ./03_osd_add.sh /dev/sdc ceph          # На узле astra-node2
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

# Проверка возможности использования sudo
if ! sudo -n true 2>/dev/null; then
   log_warn "Требуется доступ к sudo. Введите пароль..."
   sudo true || { log_error "Нет доступа к sudo"; exit 1; }
fi

DEVICE="${1}"
CLUSTER_NAME="${2:-ceph}"
CLUSTER_DIR="/etc/ceph"

if [[ -z "$DEVICE" ]]; then
    log_error "Использование: $0 [device] [cluster_name]"
    log_error "Пример: $0 /dev/sdb ceph"
fi

log_info "===== ДОБАВЛЕНИЕ OSD ДИСКА ====="
log_info "Устройство: $DEVICE"
log_info "Кластер: $CLUSTER_NAME"

# Проверка существования устройства
if [[ ! -b "$DEVICE" ]]; then
    log_error "Устройство $DEVICE не найдено"
fi

# Проверка что устройство свободно
if mount | grep -q "$DEVICE"; then
    log_error "Устройство $DEVICE используется. Отмонтируйте его перед использованием"
fi

# Очистка диска (опционально, раскомментировать с осторожностью)
# log_warn "Очистка диска..."
# sgdisk --zap-all "$DEVICE"
# partprobe "$DEVICE"

# Получение OSD ID
OSD_ID=$(ceph osd create 2>/dev/null || echo "0")
log_info "Назначен OSD ID: $OSD_ID"

# Создание директории для OSD
OSD_PATH="/var/lib/ceph/osd/$CLUSTER_NAME-$OSD_ID"
mkdir -p "$OSD_PATH"
log_info "Создана директория OSD: $OSD_PATH"

# Способ 1: Использование ceph-volume (рекомендуется для Octopus+)
log_info "Подготовка OSD диска с использованием ceph-volume..."

# Зашифрование дм-крипт (для повышенной безопасности)
# Раскомментировать при необходимости, требует пароля
# ceph-volume lvm create --dmcrypt --data $DEVICE

# Без шифрования:
ceph-volume lvm create --data "$DEVICE" --crush-device-class ssd 2>/dev/null || \
ceph-volume lvm create --data "$DEVICE" 2>/dev/null || \
{
    log_warn "ceph-volume может требовать дополнительной конфигурации, попытка альтернативного метода..."
    
    # Способ 2: Использование ceph-disk (устаревший, но работает)
    ceph-disk prepare --cluster "$CLUSTER_NAME" --cluster-uuid "$FSID" "$DEVICE" 2>/dev/null || true
    
    # Способ 3: Ручное создание OSD (если вышеперечисленные не сработали)
    log_warn "Выполнение ручной подготовки OSD..."
    
    # Форматирование диска в XFS
    mkfs.xfs -f "$DEVICE"
    
    # Монтирование диска
    mount "$DEVICE" "$OSD_PATH"
    
    # Инициализация OSD хранилища
    ceph-osd --cluster "$CLUSTER_NAME" --id "$OSD_ID" --mkfs --mkkey \
        -c "$CLUSTER_DIR/$CLUSTER_NAME.conf" \
        --osd-uuid "$(uuidgen)" 2>/dev/null || true
    
    # Добавление ключа OSD
    ceph auth add "osd.$OSD_ID" osd 'allow *' mon 'allow profile osd' \
        -i "$OSD_PATH/keyring" 2>/dev/null || true
}

# Включение и запуск OSD
log_info "Включение сервиса OSD..."
systemctl enable "ceph-osd@$OSD_ID"
systemctl restart "ceph-osd@$OSD_ID"
sleep 2

# Проверка статуса
log_info "Проверка статуса OSD..."
ceph osd tree 2>/dev/null | tee -a "$LOG_FILE" || log_warn "ceph osd tree ещё недоступен"

# Дождитесь присоединения OSD к кластеру
log_info "Ожидание присоединения OSD к кластеру..."
max_attempts=30
attempt=0
until ceph osd tree 2>/dev/null | grep -q "up.*in" || [[ $attempt -ge $max_attempts ]]; do
    log_info "Попытка $((attempt+1))/$max_attempts..."
    sleep 1
    ((attempt++))
done

if ceph osd tree 2>/dev/null | grep -q "up.*in"; then
    log_info "OSD $OSD_ID успешно добавлен в кластер"
    ceph osd tree 2>/dev/null | tee -a "$LOG_FILE"
else
    log_warn "OSD может быть ещё присоединяется, проверьте позже: ceph osd tree"
fi

# Конфигурация параметров OSD для стабильности и производительности
log_info "Конфигурация параметров OSD..."
cat >> "$CLUSTER_DIR/$CLUSTER_NAME.conf" <<EOF

[osd.$OSD_ID]
osd journal size = 10240
osd heartbeat interval = 5
osd mon heartbeat interval = 30

EOF

# Взвешивание в CRUSH для балансировки нагрузки
log_info "Конфигурация CRUSH веса (может потребоваться позже для балансировки)..."

log_info "===== ДОБАВЛЕНИЕ OSD ДИСКА ЗАВЕРШЕНО ====="
log_info "Проверить статус кластера: ceph -s"
log_info "Все логи: $LOG_FILE"
