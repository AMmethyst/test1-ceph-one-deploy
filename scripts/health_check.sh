#!/bin/bash
#############################################################################
# Проверка здоровья и диагностика Ceph кластера
# 
# Использование: ./health_check.sh [options]
#############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CLUSTER_NAME="${CLUSTER_NAME:-ceph}"
CRITICAL_ISSUES=0
WARNING_ISSUES=0

print_check() {
    local status=$1
    local message=$2
    
    case $status in
        ok)
            echo -e "${GREEN}[✓]${NC} $message"
            ;;
        warn)
            echo -e "${YELLOW}[!]${NC} $message"
            ((WARNING_ISSUES++))
            ;;
        fail)
            echo -e "${RED}[✗]${NC} $message"
            ((CRITICAL_ISSUES++))
            ;;
    esac
}

echo "===== ДИАГНОСТИКА CEPH КЛАСТЕРА ====="
echo ""

# 1. Проверка статуса кластера
echo "=== Статус кластера ==="
if ceph health --cluster "$CLUSTER_NAME" &>/dev/null; then
    HEALTH=$(ceph health --cluster "$CLUSTER_NAME" | head -1)
    
    if [[ "$HEALTH" == "HEALTH_OK" ]]; then
        print_check "ok" "Кластер здоров"
    elif [[ "$HEALTH" == *"HEALTH_WARN"* ]]; then
        print_check "warn" "Кластер в режиме предупреждения"
        ceph health detail --cluster "$CLUSTER_NAME" | head -10
    else
        print_check "fail" "Кластер имеет критические проблемы"
        ceph health detail --cluster "$CLUSTER_NAME" | head -10
    fi
else
    print_check "fail" "Не удаётся подключиться к кластеру"
fi

echo ""

# 2. Проверка Monitor узлов
echo "=== Monitor узлы ==="
if ceph mon stat --cluster "$CLUSTER_NAME" &>/dev/null; then
    MON_COUNT=$(ceph mon stat --cluster "$CLUSTER_NAME" | grep -o "quorum.*" | wc -w)
    print_check "ok" "Monitor узлы: $MON_COUNT"
else
    print_check "fail" "Не удаётся получить информацию Monitor узлов"
fi

echo ""

# 3. Проверка OSD узлов
echo "=== OSD узлы ==="
OSD_IN=$(ceph osd stat --cluster "$CLUSTER_NAME" 2>/dev/null | grep -o "[0-9]* osds: [0-9]* up" | grep -o "[0-9]* up" | grep -o "^[0-9]*" || echo "0")
OSD_TOTAL=$(ceph osd stat --cluster "$CLUSTER_NAME" 2>/dev/null | grep -o "[0-9]* osds:" | grep -o "^[0-9]*" || echo "0")

if [[ "$OSD_IN" == "$OSD_TOTAL" ]] && [[ "$OSD_TOTAL" -gt 0 ]]; then
    print_check "ok" "Все OSD узлы up ($OSD_IN/$OSD_TOTAL)"
elif [[ "$OSD_IN" -gt 0 ]]; then
    print_check "warn" "Некоторые OSD узлы down ($OSD_IN/$OSD_TOTAL)"
else
    print_check "fail" "OSD узлы не найдены"
fi

echo ""

# 4. Проверка PG статуса
echo "=== Placement Groups (PG) ==="
PG_STATS=$(ceph pg stat --cluster "$CLUSTER_NAME" 2>/dev/null || echo "")

if [[ -n "$PG_STATS" ]]; then
    if [[ "$PG_STATS" == *"active+clean"* ]]; then
        print_check "ok" "Все PG активны и чистые"
    else
        print_check "warn" "PG не в оптимальном состоянии"
        echo "$PG_STATS" | head -5
    fi
else
    print_check "warn" "Информация о PG недоступна"
fi

echo ""

# 5. Проверка использования хранилища
echo "=== Использование хранилища ==="
USED=$(ceph df --cluster "$CLUSTER_NAME" 2>/dev/null | awk '/GLOBAL/,/TOTAL/{if(/TOTAL/) print}' | awk '{print $3}' || echo "unknown")
AVAIL=$(ceph df --cluster "$CLUSTER_NAME" 2>/dev/null | awk '/GLOBAL/,/TOTAL/{if(/TOTAL/) print}' | awk '{print $4}' || echo "unknown")

if [[ "$USED" != "unknown" ]]; then
    print_check "ok" "Использовано: $USED, Доступно: $AVAIL"
else
    print_check "warn" "Информация об использовании недоступна"
fi

echo ""

# 6. Проверка целостности данных
echo "=== Целостность данных ==="
INCONSISTENT_PG=$(ceph pg stat --cluster "$CLUSTER_NAME" 2>/dev/null | grep -o "[0-9]* inconsistent" | grep -o "^[0-9]*" || echo "0")

if [[ "$INCONSISTENT_PG" == "0" ]]; then
    print_check "ok" "Нет несогласованных PG"
else
    print_check "fail" "Обнаружено $INCONSISTENT_PG несогласованных PG"
fi

echo ""

# 7. Проверка Backfill/Recovery
echo "=== Процессы восстановления ==="
BACKFILL=$(ceph pg stat --cluster "$CLUSTER_NAME" 2>/dev/null | grep -o "backfilling" | wc -l || echo "0")
RECOVERING=$(ceph pg stat --cluster "$CLUSTER_NAME" 2>/dev/null | grep -o "recovering" | wc -l || echo "0")

if [[ "$BACKFILL" == "0" ]] && [[ "$RECOVERING" == "0" ]]; then
    print_check "ok" "Нет активных процессов восстановления"
else
    if [[ "$BACKFILL" -gt 0 ]]; then
        print_check "warn" "Активный backfill ($BACKFILL процессов)"
    fi
    if [[ "$RECOVERING" -gt 0 ]]; then
        print_check "warn" "Активное восстановление ($RECOVERING процессов)"
    fi
fi

echo ""

# 8. Проверка версии Ceph
echo "=== Версия Ceph ==="
CEPH_VERSION=$(ceph version --cluster "$CLUSTER_NAME" 2>/dev/null | grep -o "version [^/]*" || echo "unknown")
print_check "ok" "Ceph версия: $CEPH_VERSION"

echo ""

# 9. Проверка дисков на ошибки
echo "=== Проверка дисков ==="
for osd in $(ceph osd ls --cluster "$CLUSTER_NAME" 2>/dev/null || echo ""); do
    OSD_STATUS=$(ceph osd dump --cluster "$CLUSTER_NAME" 2>/dev/null | grep "osd.$osd " | grep -o "down" || echo "up")
    if [[ "$OSD_STATUS" == "down" ]]; then
        print_check "fail" "OSD.$osd не в сети"
    fi
done

echo ""

# 10. Проверка процессов
echo "=== Процессы Ceph ==="
if pgrep -x "ceph-mon" > /dev/null; then
    print_check "ok" "Monitor процесс запущен"
else
    print_check "fail" "Monitor процесс не запущен"
fi

if pgrep -x "ceph-osd" > /dev/null; then
    OSD_PROC_COUNT=$(pgrep -x "ceph-osd" | wc -l)
    print_check "ok" "OSD процессы запущены ($OSD_PROC_COUNT)"
else
    print_check "warn" "OSD процессы не запущены"
fi

if pgrep -x "ceph-mgr" > /dev/null; then
    print_check "ok" "Manager процесс запущен"
else
    print_check "warn" "Manager процесс не запущен"
fi

echo ""
echo "===== ИТОГИ ДИАГНОСТИКИ ====="
echo "Критические проблемы: $CRITICAL_ISSUES"
echo "Предупреждения: $WARNING_ISSUES"

if [[ $CRITICAL_ISSUES -gt 0 ]]; then
    exit 1
elif [[ $WARNING_ISSUES -gt 0 ]]; then
    exit 2
else
    echo -e "${GREEN}Система работает нормально${NC}"
    exit 0
fi
