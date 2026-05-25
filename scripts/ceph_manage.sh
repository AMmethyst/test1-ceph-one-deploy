#!/bin/bash
#############################################################################
# Утилита для управления Ceph кластером после развёртывания
# 
# Использование: ./ceph_manage.sh [command] [options]
# Доступные команды: status, health, pools, osds, mons, rgw, backup, restore
#############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLUSTER_NAME="${CLUSTER_NAME:-ceph}"

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

cmd_status() {
    print_header "СТАТУС CEPH КЛАСТЕРА"
    ceph -s --cluster "$CLUSTER_NAME"
}

cmd_health() {
    print_header "ЗДОРОВЬЕ КЛАСТЕРА"
    ceph health detail --cluster "$CLUSTER_NAME"
}

cmd_pools() {
    print_header "ПУЛЫ ХРАНЕНИЯ"
    ceph osd pool ls --cluster "$CLUSTER_NAME"
    echo ""
    ceph df --cluster "$CLUSTER_NAME"
}

cmd_osds() {
    print_header "OSD ДИСКИ"
    echo "=== OSD Tree ==="
    ceph osd tree --cluster "$CLUSTER_NAME"
    echo ""
    echo "=== OSD Status ==="
    ceph osd status --cluster "$CLUSTER_NAME" 2>/dev/null || \
    for osd in $(ceph osd ls --cluster "$CLUSTER_NAME"); do
        echo "OSD.$osd:"
        ceph osd find "$osd" --cluster "$CLUSTER_NAME" 2>/dev/null || true
    done
}

cmd_mons() {
    print_header "MONITORS"
    ceph mon stat --cluster "$CLUSTER_NAME"
    echo ""
    ceph mon dump --cluster "$CLUSTER_NAME"
}

cmd_rgw() {
    print_header "RADOS GATEWAY STATUS"
    
    # Проверка процесса RGW
    if pgrep -x "radosgw" > /dev/null; then
        echo -e "${GREEN}✓ RGW процесс запущен${NC}"
        ps aux | grep radosgw | grep -v grep
    else
        echo -e "${RED}✗ RGW процесс не запущен${NC}"
    fi
    
    echo ""
    echo "=== RGW Сервис ==="
    systemctl status ceph-radosgw --cluster "$CLUSTER_NAME" --no-pager 2>/dev/null || \
    echo "RGW не конфигурирован"
}

cmd_backup() {
    print_header "РЕЗЕРВНАЯ КОПИЯ КОНФИГУРАЦИИ"
    
    BACKUP_DIR="/var/backups/ceph-config"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/ceph_config_$TIMESTAMP.tar.gz"
    
    mkdir -p "$BACKUP_DIR"
    
    echo "Резервная копия в: $BACKUP_FILE"
    tar czf "$BACKUP_FILE" \
        /etc/ceph/ \
        /var/lib/ceph/bootstrap-* \
        2>/dev/null || true
    
    echo "✓ Резервная копия создана"
    ls -lh "$BACKUP_FILE"
}

cmd_restore() {
    print_header "ВОССТАНОВЛЕНИЕ ИЗ РЕЗЕРВНОЙ КОПИИ"
    
    BACKUP_FILE="${1}"
    
    if [[ -z "$BACKUP_FILE" ]]; then
        echo "Использование: ./ceph_manage.sh restore [backup_file]"
        ls -lt /var/backups/ceph-config/ 2>/dev/null | head -5 || echo "Резервные копии не найдены"
        return 1
    fi
    
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo -e "${RED}✗ Файл резервной копии не найден: $BACKUP_FILE${NC}"
        return 1
    fi
    
    echo "Восстановление из: $BACKUP_FILE"
    tar xzf "$BACKUP_FILE" -C / --warning=no-timestamp
    echo "✓ Восстановление завершено"
}

cmd_benchmark() {
    print_header "ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ"
    
    echo "=== RBD Performance Test ==="
    rbd create --cluster "$CLUSTER_NAME" \
        --size 1024 bench-test 2>/dev/null || true
    
    rbd bench-write bench-test --cluster "$CLUSTER_NAME" \
        --io-size 4096 --io-threads 16 --total-bytes 1073741824 \
        2>/dev/null || true
    
    rbd rm --cluster "$CLUSTER_NAME" bench-test 2>/dev/null || true
}

cmd_help() {
    cat <<EOF
Утилита для управления Ceph кластером

Использование: ./ceph_manage.sh [command] [options]

Команды:
  status          - Показать общий статус кластера
  health          - Показать детальное состояние здоровья
  pools           - Показать пулы и использование хранилища
  osds            - Показать OSD диски и их статус
  mons            - Показать Monitor узлы
  rgw             - Показать статус RADOS Gateway
  backup          - Создать резервную копию конфигурации
  restore <file>  - Восстановить конфигурацию из резервной копии
  benchmark       - Запустить тест производительности
  help            - Показать эту справку

Примеры:
  ./ceph_manage.sh status
  ./ceph_manage.sh backup
  ./ceph_manage.sh restore /var/backups/ceph-config/ceph_config_20240101_120000.tar.gz

EOF
}

# Главная логика
COMMAND="${1:-help}"

case "$COMMAND" in
    status)
        cmd_status
        ;;
    health)
        cmd_health
        ;;
    pools)
        cmd_pools
        ;;
    osds)
        cmd_osds
        ;;
    mons)
        cmd_mons
        ;;
    rgw)
        cmd_rgw
        ;;
    backup)
        cmd_backup
        ;;
    restore)
        cmd_restore "$2"
        ;;
    benchmark)
        cmd_benchmark
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        echo -e "${RED}Неизвестная команда: $COMMAND${NC}"
        cmd_help
        exit 1
        ;;
esac
