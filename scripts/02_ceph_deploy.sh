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

# Использование переменных из конфига, если доступны, иначе значения по умолчанию
MONITOR_NODE="${MONITOR_NODE:-astra-front}"
MONITOR_IP="${MONITOR_IP:-172.30.120.21}"
PUBLIC_NETWORK="${PUBLIC_NETWORK:-192.168.1.0/24}"
CLUSTER_NETWORK="${CLUSTER_NETWORK:-192.168.2.0/24}"
COMPUTE_IPS="${COMPUTE_IPS:-192.168.1.101 192.168.1.102 192.168.1.103}"

log_info "===== РАЗВЁРТЫВАНИЕ КЛАСТЕРА CEPH ====="
log_info "Имя кластера: $CLUSTER_NAME"
log_info "FSID: $FSID"
log_info "Monitor узел: $MONITOR_NODE ($MONITOR_IP)"
log_info "Public сеть: $PUBLIC_NETWORK"
log_info "Cluster сеть: $CLUSTER_NETWORK"
log_info "Директория конфигурации: $CLUSTER_DIR"
log_info "Переменные окружения:"
log_info "  MONITOR_NODE=${MONITOR_NODE}"
log_info "  MONITOR_IP=${MONITOR_IP}"
log_info "  PUBLIC_NETWORK=${PUBLIC_NETWORK}"
log_info "  CLUSTER_NETWORK=${CLUSTER_NETWORK}"

# Создание конфигурационного файла Ceph
log_info "Создание конфигурационного файла $CLUSTER_NAME.conf..."

cat > "$CLUSTER_DIR/$CLUSTER_NAME.conf" <<EOF
[global]
fsid = $FSID
mon_initial_members = $MONITOR_NODE
mon_host = $MONITOR_IP
auth_cluster_required = cephx
auth_service_required = cephx
auth_client_required = cephx

# Public network for client communication
public_network = $PUBLIC_NETWORK

# Cluster network for OSD-OSD communication (more secure, requires separate network)
cluster_network = $CLUSTER_NETWORK

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

# Проверяем нужно ли пересоздать монmap
# Пересоздаём если файла нет или IP адрес изменился
RECREATE_MONMAP=0
if [[ ! -f "$MON_MAP_FILE" ]]; then
    log_info "Monmap файл не найден, будет создан новый"
    RECREATE_MONMAP=1
else
    # Проверяем содержит ли монmap текущий IP адрес
    if ! grep -q "$MONITOR_IP" "$MON_MAP_FILE" 2>/dev/null; then
        log_warn "IP адрес в монmap не совпадает с текущим ($MONITOR_IP), пересоздаём"
        RECREATE_MONMAP=1
    fi
fi

if [[ $RECREATE_MONMAP -eq 1 ]]; then
    log_info "Создание новой монmap с параметрами: $MONITOR_NODE ($MONITOR_IP)"
    # Удаляем старую если есть
    rm -f "$MON_MAP_FILE"
    monmaptool --create --clobber \
        --add "$MONITOR_NODE" "$MONITOR_IP" \
        --fsid "$FSID" \
        "$MON_MAP_FILE"
    log_info "Новая Mon map создана"
    
    # Если IP изменился, нужно очистить старые данные монитора
    log_info "Очистка старых данных монитора перед переинициализацией..."
    systemctl stop "ceph-mon@$MONITOR_NODE" 2>/dev/null || true
    sleep 2
    rm -rf "/var/lib/ceph/mon/$CLUSTER_NAME-$MONITOR_NODE"
    log_info "Данные монитора очищены"
else
    log_info "Используется существующая Mon map"
fi

# Создание данных монитора
MON_DATA_DIR="/var/lib/ceph/mon/$CLUSTER_NAME-$MONITOR_NODE"
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
    log_info "Выполнение: ceph-mon --mkfs -i $MONITOR_NODE --monmap $MON_MAP_FILE --keyring $MON_KEYRING --fsid $FSID"
    
    MK_OUTPUT=$(mktemp)
    if ceph-mon --mkfs -i "$MONITOR_NODE" --monmap "$MON_MAP_FILE" \
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
log_info "Выполнение: chown -R astraadm:astraadm $MON_DATA_DIR"
if chown -R astraadm:astraadm "$MON_DATA_DIR"; then
    log_info "✓ chown выполнен успешно"
else
    log_error "✗ Ошибка при chown!"
fi

log_info "Выполнение: chmod -R 755 $MON_DATA_DIR"
if chmod -R 755 "$MON_DATA_DIR"; then
    log_info "✓ chmod выполнен успешно"
else
    log_error "✗ Ошибка при chmod!"
fi

# Проверяем что права действительно изменились
log_info "Статус прав доступа после установки:"
ls -la "$MON_DATA_DIR" 2>&1 | tee -a "$LOG_FILE" || true

# Убеждаемся что все файлы имеют правильного владельца
BAD_PERMS=$(find "$MON_DATA_DIR" ! -user astraadm 2>/dev/null | wc -l)
if [[ $BAD_PERMS -gt 0 ]]; then
    log_error "✗ Обнаружено $BAD_PERMS файлов с неправильным владельцем!"
    find "$MON_DATA_DIR" ! -user astraadm 2>/dev/null | tee -a "$LOG_FILE"
    log_error "Пытаемся исправить с -R флагом..."
    chown -R astraadm:astraadm "$MON_DATA_DIR" || log_error "Повторная попытка chown не удалась"
else
    log_info "✓ Все файлы имеют владельца astraadm"
fi

# Проверка конфиг файлов
log_info "Проверка конфиг файлов:"
log_info "Содержимое ceph.conf (первые 30 строк):"
head -30 "$CLUSTER_DIR/$CLUSTER_NAME.conf" | tee -a "$LOG_FILE" || log_error "Ошибка при чтении ceph.conf"

log_info "Проверка монmap:"
monmaptool --print "$MON_MAP_FILE" 2>&1 | tee -a "$LOG_FILE" || log_error "Ошибка при чтении монmap"

# Определение пользователя для Ceph
# Обычно это ceph или astraadm
# ВАЖНО: Если указан ceph но пользователя нет, скрипт запущен от astraadm и мы должны использовать astraadm
CEPH_USER="astraadm"

# Проверяем есть ли пользователь ceph (если есть пакеты ceph)
if id "ceph" &>/dev/null 2>&1; then
    CEPH_USER="ceph"
    log_info "Найден пользователь ceph, будет использован: $CEPH_USER"
else
    log_warn "Пользователь ceph НЕ найден, будет использован: $CEPH_USER"
fi

log_info "Выбран пользователь Ceph: $CEPH_USER"

# Проверка конфигурации перед запуском Monitor
log_info "Проверка конфигурации перед запуском Monitor..."

# Проверка прав на файлах в /etc/ceph ДО исправления
log_info "Статус файлов в $CLUSTER_DIR (ДО исправления):"
ls -la "$CLUSTER_DIR"/ 2>&1 | tee -a "$LOG_FILE" || true

# Исправление владельца и прав для конфига
if [[ -f "$CLUSTER_DIR/$CLUSTER_NAME.conf" ]]; then
    chown root:root "$CLUSTER_DIR/$CLUSTER_NAME.conf"
    chmod 644 "$CLUSTER_DIR/$CLUSTER_NAME.conf"
    log_info "✓ Config: владелец=root:root, права=644"
else
    log_error "Конфиг не найден: $CLUSTER_DIR/$CLUSTER_NAME.conf"
fi

# Исправление владельца и прав для монmap
if [[ -f "$MON_MAP_FILE" ]]; then
    chown root:root "$MON_MAP_FILE"
    chmod 644 "$MON_MAP_FILE"
    log_info "✓ Monmap: владелец=root:root, права=644"
else
    log_error "Монmap не найден: $MON_MAP_FILE"
fi

# Исправление владельца и прав для keyring файлов - КРИТИЧНО!
if [[ -f "$CLUSTER_DIR/$CLUSTER_NAME.client.admin.keyring" ]]; then
    chown "$CEPH_USER:$CEPH_USER" "$CLUSTER_DIR/$CLUSTER_NAME.client.admin.keyring"
    chmod 640 "$CLUSTER_DIR/$CLUSTER_NAME.client.admin.keyring"
    log_info "✓ Admin keyring: владелец=$CEPH_USER:$CEPH_USER, права=640"
else
    log_warn "Admin keyring не найден: $CLUSTER_DIR/$CLUSTER_NAME.client.admin.keyring"
fi

if [[ -f "$MON_KEYRING" ]]; then
    chown "$CEPH_USER:$CEPH_USER" "$MON_KEYRING"
    chmod 640 "$MON_KEYRING"
    log_info "✓ Mon keyring: владелец=$CEPH_USER:$CEPH_USER, права=640"
else
    log_warn "Mon keyring не найден: $MON_KEYRING"
fi

# Проверка прав на директориях
log_info "Проверка прав доступа..."
log_info "Содержимое /var/lib/ceph:"
find /var/lib/ceph -type f -o -type d | head -30 | tee -a "$LOG_FILE"

# Исправление прав на директории монитора - КРИТИЧНО для работы сервиса
log_info "Исправление прав доступа на директории монитора..."
if [[ -d "$MON_DATA_DIR" ]]; then
    log_info "Директория: $MON_DATA_DIR"
    log_info "Установка владельца: $CEPH_USER:$CEPH_USER"
    
    chown -R "$CEPH_USER:$CEPH_USER" "$MON_DATA_DIR"
    chmod -R 755 "$MON_DATA_DIR"
    
    # Особая проверка для критического файла LOCK
    if [[ -f "$MON_DATA_DIR/store.db/LOCK" ]]; then
        chmod 644 "$MON_DATA_DIR/store.db/LOCK"
        log_info "✓ Права на LOCK файл установлены: 644"
    fi
    
    # Проверка результата
    ACTUAL_OWNER=$(ls -ld "$MON_DATA_DIR" | awk '{print $3":"$4}')
    log_info "✓ Текущий владелец директории: $ACTUAL_OWNER"
else
    log_warn "Директория монитора не найдена: $MON_DATA_DIR"
fi

# Проверка после исправления
log_info "Статус файлов в $CLUSTER_DIR (ПОСЛЕ исправления):"
ls -la "$CLUSTER_DIR"/ 2>&1 | tee -a "$LOG_FILE" || true

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
log_info "Запуск: /usr/bin/ceph-mon -i \"$MONITOR_NODE\" -c \"$CLUSTER_DIR/$CLUSTER_NAME.conf\" --debug-mon 5"
if timeout 5 /usr/bin/ceph-mon -i "$MONITOR_NODE" -c "$CLUSTER_DIR/$CLUSTER_NAME.conf" --debug-mon 5 >"$LOG_OUTPUT" 2>&1; then
    log_info "Диагностический запуск завершился успешно"
else
    EXIT_CODE=$?
    log_info "Диагностический запуск завершился с кодом: $EXIT_CODE (может быть нормально)"
fi

log_info "Вывод диагностического запуска:"
if [[ -s "$LOG_OUTPUT" ]]; then
    cat "$LOG_OUTPUT" | tee -a "$LOG_FILE"
else
    log_info "(вывод пуст)"
fi
rm -f "$LOG_OUTPUT"

# Корректное завершение процесса
log_info "Корректное завершение ceph-mon процессов..."
systemctl stop "ceph-mon@$MONITOR_NODE" 2>/dev/null || true
sleep 2

# Принудительное завершение оставшихся процессов
if pgrep -f "ceph-mon" >/dev/null 2>&1; then
    log_warn "ceph-mon процессы ещё активны, принудительное завершение..."
    pkill -9 -f "ceph-mon" || true
    sleep 2
fi

# Удаление lockfile если он остался
if [[ -f "/var/lib/ceph/mon/$CLUSTER_NAME-$MONITOR_NODE/lock" ]]; then
    log_info "Удаление lock file..."
    rm -f "/var/lib/ceph/mon/$CLUSTER_NAME-$MONITOR_NODE/lock"
fi

# Включение сервиса Monitor
log_info "Запуск Ceph Monitor через systemd..."

# Диагностика systemd unit файла
log_info "Поиск systemd unit файла для ceph-mon..."
if [[ -f "/usr/lib/systemd/system/ceph-mon@.service" ]]; then
    UNIT_FILE="/usr/lib/systemd/system/ceph-mon@.service"
    log_info "Unit файл найден: $UNIT_FILE"
    
    # Всегда проверяем и исправляем User/Group если нужно
    UNIT_USER=$(grep "^User=" "$UNIT_FILE" | head -1 | cut -d= -f2 | tr -d ' ')
    UNIT_GROUP=$(grep "^Group=" "$UNIT_FILE" | head -1 | cut -d= -f2 | tr -d ' ')
    
    log_info "Текущий User в unit файле: ${UNIT_USER:-(не указан)}"
    log_info "Текущий Group в unit файле: ${UNIT_GROUP:-(не указан)}"
    log_info "Требуемый пользователь: $CEPH_USER"
    
    # Если пользователь ceph не существует и указан в unit, нужно заменить на astraadm
    if [[ "$UNIT_USER" == "ceph" ]] && [[ "$CEPH_USER" == "astraadm" ]]; then
        log_warn "КРИТИЧЕСКАЯ ПРОБЛЕМА: Unit файл указывает User=ceph, но пользователя ceph НЕ существует!"
        log_info "Будет выполнено исправление unit файла..."
        
        # Создание резервной копии
        cp "$UNIT_FILE" "$UNIT_FILE.backup"
        log_info "✓ Резервная копия сохранена: $UNIT_FILE.backup"
        
        # Замена пользователя
        sed -i "s/^User=ceph/User=astraadm/" "$UNIT_FILE"
        sed -i "s/^Group=ceph/Group=astraadm/" "$UNIT_FILE"
        
        log_info "✓ Unit файл исправлен (ceph -> astraadm)"
        log_info "Новое содержимое User/Group:"
        grep -E "^(User|Group)=" "$UNIT_FILE" | tee -a "$LOG_FILE"
    elif [[ "$UNIT_USER" != "$CEPH_USER" ]] && [[ -n "$UNIT_USER" ]]; then
        log_warn "User в unit файле ($UNIT_USER) отличается от требуемого ($CEPH_USER)"
        
        cp "$UNIT_FILE" "$UNIT_FILE.backup"
        sed -i "s/^User=.*/User=$CEPH_USER/" "$UNIT_FILE"
        sed -i "s/^Group=.*/Group=$CEPH_USER/" "$UNIT_FILE"
        
        log_info "✓ Unit файл обновлён ($UNIT_USER -> $CEPH_USER)"
        grep -E "^(User|Group)=" "$UNIT_FILE" | tee -a "$LOG_FILE"
    else
        log_info "✓ Unit файл уже настроен правильно"
    fi
else
    log_warn "Unit файл не найден в /usr/lib/systemd/system/"
    log_info "Проверка /etc/systemd/system/..."
    if [[ -f "/etc/systemd/system/ceph-mon@.service" ]]; then
        UNIT_FILE="/etc/systemd/system/ceph-mon@.service"
        log_info "Unit файл найден: $UNIT_FILE"
        
        UNIT_USER=$(grep "^User=" "$UNIT_FILE" | head -1 | cut -d= -f2 | tr -d ' ')
        if [[ "$UNIT_USER" == "ceph" ]] && [[ "$CEPH_USER" == "astraadm" ]]; then
            log_warn "Исправление unit файла в /etc/systemd..."
            cp "$UNIT_FILE" "$UNIT_FILE.backup"
            sed -i "s/^User=ceph/User=astraadm/" "$UNIT_FILE"
            sed -i "s/^Group=ceph/Group=astraadm/" "$UNIT_FILE"
            log_info "✓ Unit файл исправлен"
        fi
    else
        log_error "Unit файл не найден!"
    fi
fi

systemctl daemon-reload
log_info "✓ Systemd daemon перезагружен"

# Важно: останавливаем старый сервис перед запуском
log_info "Остановка старого сервиса..."
systemctl stop "ceph-mon@$MONITOR_NODE" 2>/dev/null || true
sleep 2

# Убедимся что процесс действительно остановлен
if pgrep -f "ceph-mon" >/dev/null 2>&1; then
    log_warn "Процессы ceph-mon ещё активны, принудительное завершение..."
    pkill -9 -f "ceph-mon" || true
    sleep 2
fi

log_info "Включение сервиса в автозагрузку..."
if systemctl enable "ceph-mon@$MONITOR_NODE"; then
    log_info "✓ Сервис включен в автозагрузку"
else
    log_warn "Не удалось включить в автозагрузку"
fi

log_info "Запуск сервиса от пользователя: $CEPH_USER"
if systemctl start "ceph-mon@$MONITOR_NODE"; then
    log_info "✓ Команда systemctl start выполнена"
else
    log_warn "Команда systemctl start вернула ошибку (может быть норм)"
fi

# Ожидание инициализации сервиса
log_info "Ожидание инициализации сервиса (до 30 сек)..."
sleep 3
for i in {1..10}; do
    if systemctl is-active --quiet "ceph-mon@$MONITOR_NODE"; then
        log_info "✓ Сервис активен на попытке $i"
        break
    fi
    if [[ $i -lt 10 ]]; then
        log_info "Попытка $i: сервис ещё не активен, ожидание..."
        sleep 3
    fi
done

# Проверка статуса сервиса (финальная)
if systemctl is-active --quiet "ceph-mon@$MONITOR_NODE"; then
    log_info "✓ Сервис ceph-mon@$MONITOR_NODE активен и работает"
else
    log_error "✗ Сервис ceph-mon@$MONITOR_NODE НЕ активен!"
    log_error ""
    log_error "Статус сервиса:"
    systemctl status "ceph-mon@$MONITOR_NODE" | tee -a "$LOG_FILE" || true
    
    log_error ""
    log_error "Последние логи журнала (100 строк):"
    journalctl -u "ceph-mon@$MONITOR_NODE" -n 100 --no-pager | tee -a "$LOG_FILE" || true
    
    log_error ""
    log_error "Проверка ошибок systemd:"
    journalctl -u "ceph-mon@$MONITOR_NODE" -p err -n 20 --no-pager | tee -a "$LOG_FILE" || true
    
    log_error ""
    log_error "Процессы ceph:"
    ps aux | grep -i ceph | grep -v grep | tee -a "$LOG_FILE" || true
    
    log_error ""
    log_error "Содержимое директории монитора:"
    ls -laR "$MON_DATA_DIR" 2>&1 | head -50 | tee -a "$LOG_FILE" || true
    
    log_error ""
    log_error "Информация о unit файле:"
    if [[ -f "/usr/lib/systemd/system/ceph-mon@.service" ]]; then
        log_error "Unit: /usr/lib/systemd/system/ceph-mon@.service"
        grep -E "^(User|Group|ExecStart)" "/usr/lib/systemd/system/ceph-mon@.service" | tee -a "$LOG_FILE" || true
    elif [[ -f "/etc/systemd/system/ceph-mon@.service" ]]; then
        log_error "Unit: /etc/systemd/system/ceph-mon@.service"
        grep -E "^(User|Group|ExecStart)" "/etc/systemd/system/ceph-mon@.service" | tee -a "$LOG_FILE" || true
    fi
    
    log_error ""
    log_error "РЕКОМЕНДУЕМЫЕ ДЕЙСТВИЯ:"
    log_error "1. Проверьте логи в реальном времени:"
    log_error "   journalctl -u ceph-mon@$MONITOR_NODE -f"
    log_error "2. Попробуйте запустить вручную:"
    log_error "   /usr/bin/ceph-mon -i $MONITOR_NODE -c $CLUSTER_DIR/$CLUSTER_NAME.conf --debug-mon 10"
    log_error "3. Проверьте права доступа:"
    log_error "   ls -la $CLUSTER_DIR/"
    log_error "   ls -la $MON_DATA_DIR/"
    log_error "4. Проверьте пользователя в unit файле:"
    log_error "   grep User= /usr/lib/systemd/system/ceph-mon@.service"
    log_error "5. Если пользователь в unit файле не существует, отредактируйте его!"
    log_error ""
    log_error "Исправьте проблему и повторите запуск скрипта"
    exit 1
fi

# Проверка статуса Monitor
log_info "Проверка статуса Monitor..."
log_info "Ожидание инициализации Monitor (до 60 сек)..."
# Проверка статуса Monitor и ожидание его инициализации
log_info "Проверка статуса сервиса Monitor..."
if ! systemctl is-active --quiet "ceph-mon@$MONITOR_NODE"; then
    log_warn "Сервис ceph-mon@$MONITOR_NODE НЕ активен, пытаемся его запустить..."
    systemctl start "ceph-mon@$MONITOR_NODE" 2>/dev/null || log_error "Не удалось запустить сервис"
    sleep 3
fi

log_info "Ожидание инициализации Monitor (до 90 сек)..."
sleep 5  # Даём больше времени на инициализацию

max_attempts=45
attempt=0
mon_ready=0

while [[ $attempt -lt $max_attempts ]]; do
    # Проверка статуса сервиса
    if ! systemctl is-active --quiet "ceph-mon@$MONITOR_NODE"; then
        log_warn "Сервис ceph-mon не активен! Попытка перезапуска..."
        systemctl restart "ceph-mon@$MONITOR_NODE" 2>/dev/null || true
        sleep 3
        ((attempt++))
        continue
    fi
    
    # Проверка готовности через ceph -s
    if timeout 5 ceph -s -c "$CLUSTER_DIR/$CLUSTER_NAME.conf" &>/dev/null; then
        log_info "✓ Monitor готов! Статус кластера:"
        ceph -s -c "$CLUSTER_DIR/$CLUSTER_NAME.conf" | tee -a "$LOG_FILE"
        mon_ready=1
        break
    else
        log_info "Ожидание готовности Monitor... (попытка $((attempt+1))/$max_attempts, ~$(( (max_attempts-attempt)*2 )) сек осталось)"
        sleep 2
        ((attempt++))
    fi
done

if [[ $mon_ready -eq 0 ]]; then
    log_warn "Monitor не полностью готов после ~$((max_attempts*2)) сек"
    log_warn "Проверяем статус сервиса и логи..."
    systemctl status "ceph-mon@$MONITOR_NODE" | tee -a "$LOG_FILE" || true
    journalctl -u "ceph-mon@$MONITOR_NODE" -n 30 | tee -a "$LOG_FILE" || true
    log_warn "Продолжаем развёртывание, Monitor может быть не полностью инициализирован"
fi

# Создание MGR (Manager)
log_info "Инициализация Ceph Manager..."
MGR_DATA_DIR="/var/lib/ceph/mgr/$CLUSTER_NAME-$MONITOR_NODE"
mkdir -p "$MGR_DATA_DIR"
chown -R "$CEPH_USER:$CEPH_USER" "$MGR_DATA_DIR"
chmod -R 755 "$MGR_DATA_DIR"

# Генирирование ключа для Manager
log_info "Генирирование ключа Manager..."
ceph auth get-or-create "mgr.$MONITOR_NODE" mon 'allow profile mgr' osd 'allow *' mds 'allow *' \
    -o "$CLUSTER_DIR/ceph.mgr.$MONITOR_NODE.keyring" -c "$CLUSTER_DIR/$CLUSTER_NAME.conf" 2>&1 | tee -a "$LOG_FILE" || true

# Убедимся что файл keyring имеет правильные права
if [[ -f "$CLUSTER_DIR/ceph.mgr.$MONITOR_NODE.keyring" ]]; then
    chown "$CEPH_USER:$CEPH_USER" "$CLUSTER_DIR/ceph.mgr.$MONITOR_NODE.keyring"
    chmod 640 "$CLUSTER_DIR/ceph.mgr.$MONITOR_NODE.keyring"
fi

# Запуск Manager
log_info "Запуск Manager сервиса..."
systemctl enable "ceph-mgr@$MONITOR_NODE"
systemctl start "ceph-mgr@$MONITOR_NODE"
sleep 3

# Проверка статуса Manager
if systemctl is-active --quiet "ceph-mgr@$MONITOR_NODE"; then
    log_info "✓ Manager успешно запущен"
else
    log_warn "Manager не активен, проверяем логи..."
    journalctl -u "ceph-mgr@$MONITOR_NODE" -n 20 | tee -a "$LOG_FILE" || true
fi

# Включение модулей Manager (если Monitor готов)
log_info "Включение модулей Manager..."
ceph mgr module enable prometheus 2>/dev/null || log_warn "Не удалось включить prometheus модуль"
ceph mgr module enable dashboard 2>/dev/null || log_warn "Не удалось включить dashboard модуль"

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
