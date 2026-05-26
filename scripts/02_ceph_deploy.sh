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
mkdir -p "$MON_DATA_DIR"

log_info "Статус директории монитора до инициализации:"
ls -la "$MON_DATA_DIR" 2>&1 | tee -a "$LOG_FILE" || true
echo "---" | tee -a "$LOG_FILE"

# Проверяем есть ли файлы в директории (любые, не только keyring)
EXISTING_FILES=$(find "$MON_DATA_DIR" -type f 2>/dev/null | wc -l)

if [[ $EXISTING_FILES -eq 0 ]]; then
    log_info "Директория пуста, выполняем инициализацию монитора..."
    
    # Проверяем входные файлы перед mkfs
    log_info "Проверка необходимых файлов:"
    log_info "  - Монmap: $MON_MAP_FILE $(test -f "$MON_MAP_FILE" && echo '✓' || echo '✗')"
    log_info "  - Keyring: $MON_KEYRING $(test -f "$MON_KEYRING" && echo '✓' || echo '✗')"
    log_info "  - Config: $CLUSTER_DIR/$CLUSTER_NAME.conf $(test -f "$CLUSTER_DIR/$CLUSTER_NAME.conf" && echo '✓' || echo '✗')"
    
    # Выполняем инициализацию с детальным логированием
    log_info "Выполнение: ceph-mon --mkfs -i astra-monitor1 --monmap $MON_MAP_FILE --keyring $MON_KEYRING --fsid $FSID"
    
    MK_OUTPUT=$(mktemp)
    if ceph-mon --mkfs -i astra-monitor1 --monmap "$MON_MAP_FILE" \
        --keyring "$MON_KEYRING" --fsid "$FSID" >"$MK_OUTPUT" 2>&1; then
        log_info "mkfs завершился успешно"
        cat "$MK_OUTPUT" | tee -a "$LOG_FILE"
    else
        log_warn "mkfs завершился с кодом ошибки, но продолжаем:"
        cat "$MK_OUTPUT" | tee -a "$LOG_FILE"
    fi
    rm -f "$MK_OUTPUT"
    
    log_info "Статус директории монитора после инициализации:"
    ls -la "$MON_DATA_DIR" 2>&1 | tee -a "$LOG_FILE" || true
    
    # Проверяем что получилось
    FILES_AFTER=$(find "$MON_DATA_DIR" -type f 2>/dev/null | wc -l)
    if [[ $FILES_AFTER -gt 0 ]]; then
        log_info "✓ Инициализация успешна, создано файлов: $FILES_AFTER"
    else
        log_error "✗ После mkfs директория всё ещё пуста! Это критическая ошибка."
        log_error "Проверьте права доступа и конфигурацию Ceph"
        ls -la /var/lib/ceph/ | tee -a "$LOG_FILE"
        exit 1
    fi
else
    log_info "✓ Директория уже содержит файлы ($EXISTING_FILES), используем существующие данные"
    ls -la "$MON_DATA_DIR" 2>&1 | tee -a "$LOG_FILE" || true
fi

# Убеждаемся в правильных правах
log_info "Установка правильных прав доступа..."
chown -R astraadm:astraadm "$MON_DATA_DIR"
chmod -R 755 "$MON_DATA_DIR"
log_info "Проверены права доступа на $MON_DATA_DIR"

# Проверка прав доступа на критических директориях
log_info "Проверка конфигурации перед запуском Monitor..."

# Проверка прав на директориях
log_info "Проверка прав доступа..."
if [[ ! -w "$MON_DATA_DIR" ]]; then
    log_warn "Директория $MON_DATA_DIR недоступна для записи, исправляем..."
    chmod -R 777 "$MON_DATA_DIR"
fi

if [[ ! -f "$CLUSTER_DIR/$CLUSTER_NAME.conf" ]]; then
    log_error "Конфиг файл не найден: $CLUSTER_DIR/$CLUSTER_NAME.conf"
fi
if [[ ! -f "$MON_KEYRING" ]]; then
    log_error "Keyring файл не найден: $MON_KEYRING"
fi
if [[ ! -d "$MON_DATA_DIR" ]]; then
    log_error "Директория монитора не создана: $MON_DATA_DIR"
fi

# Проверка портов
log_info "Проверка доступности портов..."
if netstat -tlnp 2>/dev/null | grep -q :6789; then
    log_warn "Порт 6789 уже используется, пытаемся остановить старый процесс..."
    pkill -f "ceph-mon" || true
    sleep 2
fi

# Тестовый запуск ceph-mon для диагностики
log_info "Диагностический запуск ceph-mon..."
LOG_OUTPUT=$(mktemp)
timeout 5 /usr/bin/ceph-mon -i astra-monitor1 -c "$CLUSTER_DIR/$CLUSTER_NAME.conf" --debug-mon 5 >"$LOG_OUTPUT" 2>&1 || true
log_info "Вывод диагностического запуска:"
cat "$LOG_OUTPUT" | tee -a "$LOG_FILE" | head -50
rm -f "$LOG_OUTPUT"
pkill -f "ceph-mon" || true

sleep 2

# Включение сервиса Monitor
log_info "Запуск Ceph Monitor через systemd..."
systemctl daemon-reload
if ! systemctl enable ceph-mon@astra-monitor1; then
    log_warn "Не удалось включить ceph-mon@astra-monitor1 в автозагрузку"
fi

systemctl stop ceph-mon@astra-monitor1 2>/dev/null || true
sleep 1

if systemctl start ceph-mon@astra-monitor1; then
    log_info "Сервис ceph-mon@astra-monitor1 запущен"
else
    log_warn "Команда systemctl start вернула ошибку"
fi

sleep 5

# Проверка статуса сервиса
if systemctl is-active --quiet ceph-mon@astra-monitor1; then
    log_info "✓ Сервис ceph-mon@astra-monitor1 активен и работает"
else
    log_error "✗ Сервис ceph-mon@astra-monitor1 НЕ активен!"
    log_error "Статус сервиса:"
    systemctl status ceph-mon@astra-monitor1 | tee -a "$LOG_FILE" || true
    log_error "Последние логи journalctl:"
    journalctl -u ceph-mon@astra-monitor1 -n 50 | tee -a "$LOG_FILE" || true
    log_error "Попытка получить информацию о сбое процесса..."
    ps aux | grep -i ceph | grep -v grep | tee -a "$LOG_FILE" || true
    log_error ""
    log_error "ДИАГНОСТИКА:"
    log_error "1. Проверьте права доступа: ls -la $MON_DATA_DIR"
    log_error "2. Проверьте конфиг: ceph-conf -c $CLUSTER_DIR/$CLUSTER_NAME.conf --show-config"
    log_error "3. Запустите вручную: /usr/bin/ceph-mon -i astra-monitor1 -c $CLUSTER_DIR/$CLUSTER_NAME.conf --debug-mon 5"
    log_error "Исправьте проблему и повторите запуск скрипта"
    exit 1
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
