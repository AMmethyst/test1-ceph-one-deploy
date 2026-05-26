#!/bin/bash
#############################################################################
# Скрипт развёртывания кластера Ceph
# Должен быть запущен на узле astra-monitor1 (admin node)
# 
# Использование: sudo ./02_ceph_deploy.sh [cluster_name]
# Пример: sudo ./02_ceph_deploy.sh ceph
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

CLUSTER_NAME="${1:-ceph}"
CLUSTER_DIR="/etc/ceph"
FSID=$(uuidgen)

log_info "===== РАЗВЁРТЫВАНИЕ КЛАСТЕРА CEPH ====="
log_info "Имя кластера: $CLUSTER_NAME"
log_info "FSID: $FSID"
log_info "Директория конфигурации: $CLUSTER_DIR"

# Создание конфигурационного файла Ceph
log_info "Создание конфигурационного файла $CLUSTER_NAME.conf..."

cat > "$CLUSTER_DIR/$CLUSTER_NAME.conf" <<EOF
[global]
fsid = $FSID
mon_initial_members = astra-monitor1
mon_host = 192.168.1.100
auth_cluster_required = cephx
auth_service_required = cephx
auth_client_required = cephx

# Public network for client communication
public_network = 192.168.1.0/24

# Cluster network for OSD-OSD communication (more secure, requires separate network)
cluster_network = 192.168.2.0/24

# Общие параметры производительности
mon_max_pg_per_osd = 200
osd_pool_default_size = 3
osd_pool_default_min_size = 2
osd_pool_default_pg_num = 128
osd_pool_default_pgp_num = 128

# Параметры для небольших кластеров (тестирование)
mon_pg_warn_max_per_osd = 300
mon_pg_warn_min_per_osd = 30

# Управление памятью OSD
osd_memory_target = 4294967296

# Параметры журналирования
osd_journal_size = 10240

# Параметры восстановления
osd_max_backfills = 1
osd_recovery_max_active = 3
osd_recovery_op_priority = 63

# Blustore конфигурация (для новых OSD)
osd_objectstore = bluestore

# РВД параметры
rbd_cache = true
rbd_cache_size = 335544320

# RGW параметры (для Object Storage)
[client.rgw.a]
rgw_frontends = beast port=7480

# Параметры безопасности (уровень "Орёл")
[osd]
osd_crush_update_on_start = true
osd_client_message_size_cap = 2147483648

[mon]
mon_allow_pool_delete = false
mon_max_osd = 256

EOF

chmod 644 "$CLUSTER_DIR/$CLUSTER_NAME.conf"
log_info "Конфигурационный файл создан"

# Генерирование ключей
log_info "Генирование ключей кластера..."
mkdir -p "$CLUSTER_DIR"

# Создание ключа для сервиса bootstrap
ceph-authtool --create-keyring "$CLUSTER_DIR/$CLUSTER_NAME.client.admin.keyring" \
    --gen-key -n client.admin --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' \
    2>/dev/null || log_warn "Ключ admin может быть создан позже"

# Инициализация Monitor
log_info "Инициализация Ceph Monitor на $(hostname)..."

MON_KEYRING="$CLUSTER_DIR/$CLUSTER_NAME.mon.keyring"
ceph-authtool --create-keyring "$MON_KEYRING" --gen-key -n mon. --cap mon 'allow *' 2>/dev/null || true

MON_MAP_FILE="$CLUSTER_DIR/$CLUSTER_NAME.monmap"
if [[ ! -f "$MON_MAP_FILE" ]]; then
    monmaptool --create --clobber \
        --add astra-monitor1 192.168.1.100 \
        --fsid "$FSID" \
        "$MON_MAP_FILE"
    log_info "Mon map создана"
fi

# Создание данных монитора
MON_DATA_DIR="/var/lib/ceph/mon/$CLUSTER_NAME-astra-monitor1"
if [[ ! -d "$MON_DATA_DIR" ]]; then
    mkdir -p "$MON_DATA_DIR"
    log_info "Инициализация данных монитора..."
    
    # Выполняем инициализацию с выводом ошибок
    if ceph-mon --mkfs -i astra-monitor1 --monmap "$MON_MAP_FILE" \
        --keyring "$MON_KEYRING" --fsid "$FSID"; then
        log_info "Данные монитора инициализированы успешно"
    else
        log_error "Ошибка при инициализации монитора! Проверьте конфиг и логи."
    fi
    
    chown -R astraadm:astraadm "$MON_DATA_DIR"
    chmod -R 755 "$MON_DATA_DIR"
    log_info "Установлены правильные права доступа на $MON_DATA_DIR"
fi

# Проверка прав доступа на критических директориях
log_info "Проверка конфигурации перед запуском Monitor..."
if [[ ! -f "$CLUSTER_DIR/$CLUSTER_NAME.conf" ]]; then
    log_error "Конфиг файл не найден: $CLUSTER_DIR/$CLUSTER_NAME.conf"
fi
if [[ ! -f "$MON_KEYRING" ]]; then
    log_error "Keyring файл не найден: $MON_KEYRING"
fi
if [[ ! -d "$MON_DATA_DIR" ]]; then
    log_error "Директория монитора не создана: $MON_DATA_DIR"
fi

# Включение сервиса Monitor
log_info "Запуск Ceph Monitor..."
if ! systemctl enable ceph-mon@astra-monitor1; then
    log_warn "Не удалось включить ceph-mon@astra-monitor1 в автозагрузку"
fi

if systemctl restart ceph-mon@astra-monitor1; then
    log_info "Сервис ceph-mon@astra-monitor1 перезагружен"
else
    log_error "Ошибка при перезагрузке ceph-mon@astra-monitor1! Проверьте статус: systemctl status ceph-mon@astra-monitor1"
fi

sleep 3

# Проверка статуса сервиса
if systemctl is-active --quiet ceph-mon@astra-monitor1; then
    log_info "Сервис ceph-mon@astra-monitor1 активен"
else
    log_error "Сервис ceph-mon@astra-monitor1 НЕ активен! Вывод журнала:"
    journalctl -u ceph-mon@astra-monitor1 -n 30 | tee -a "$LOG_FILE" || true
    log_error "Исправьте проблему и повторите запуск скрипта"
fi

# Проверка статуса Monitor
log_info "Проверка статуса Monitor..."
log_info "Ожидание инициализации Monitor (до 60 сек)..."
sleep 5  # Даём больше времени на инициализацию

max_attempts=30
attempt=0
mon_ready=0

while [[ $attempt -lt $max_attempts ]]; do
    # Проверка с timeout 3 сек
    if timeout 3 ceph -s -c "$CLUSTER_DIR/$CLUSTER_NAME.conf" &>/dev/null; then
        log_info "Monitor готов! Статус кластера:"
        ceph -s -c "$CLUSTER_DIR/$CLUSTER_NAME.conf" | tee -a "$LOG_FILE"
        mon_ready=1
        break
    else
        log_info "Ожидание готовности Monitor... (попытка $((attempt+1))/$max_attempts)"
        systemctl is-active ceph-mon@astra-monitor1 >/dev/null 2>&1 || log_warn "Сервис ceph-mon не активен!"
        sleep 2
        ((attempt++))
    fi
done

if [[ $mon_ready -eq 0 ]]; then
    log_warn "Monitor не полностью готов после $((max_attempts*2)) сек, проверяем логи..."
    journalctl -u ceph-mon@astra-monitor1 -n 20 | tee -a "$LOG_FILE" || true
    log_warn "Продолжаем развёртывание, но Monitor может быть не готов"
fi

# Создание MGR (Manager)
log_info "Инициализация Ceph Manager..."
MGR_DATA_DIR="/var/lib/ceph/mgr/$CLUSTER_NAME-astra-monitor1"
mkdir -p "$MGR_DATA_DIR"
chown -R astraadm:astraadm "$MGR_DATA_DIR"

# Генирирование ключа для Manager
ceph auth get-or-create mgr.astra-monitor1 mon 'allow profile mgr' osd 'allow *' mds 'allow *' \
    -o "$CLUSTER_DIR/mgr.astra-monitor1.keyring" 2>/dev/null || true

# Запуск Manager
systemctl enable ceph-mgr@astra-monitor1
systemctl restart ceph-mgr@astra-monitor1
sleep 2

# Включение модулей Manager
log_info "Включение модулей Manager..."
ceph mgr module enable prometheus 2>/dev/null || true
ceph mgr module enable dashboard 2>/dev/null || true

# Добавление OSD узлов в конфигурацию
log_info "Подготовка OSD узлов..."

# Добавление узлов в Crush map для балансировки
for node in astra-node1 astra-node2 astra-node3; do
    log_info "Регистрация узла: $node"
    # Это будет сделано при добавлении OSD
done

log_info "===== НАЧАЛЬНОЕ РАЗВЁРТЫВАНИЕ КЛАСТЕРА ЗАВЕРШЕНО ====="
log_info "Далее нужно добавить OSD диски используя скрипт 03_osd_add.sh"
log_info "Статус кластера: ceph -s"
log_info "Все логи: $LOG_FILE"
