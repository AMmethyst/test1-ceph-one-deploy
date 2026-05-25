#!/bin/bash
#############################################################################
# Проверка целостности проекта
# Убедитесь, что все необходимые файлы присутствуют
#
# Использование: ./check_project.sh
#############################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISSING_FILES=0
FOUND_FILES=0

echo "===== ПРОВЕРКА ЦЕЛОСТНОСТИ ПРОЕКТА ====="
echo "Директория: $SCRIPT_DIR"
echo ""

# Массив необходимых файлов
REQUIRED_FILES=(
    "scripts/deploy.sh"
    "scripts/00_prerequisites.sh"
    "scripts/01_node_prepare.sh"
    "scripts/02_ceph_deploy.sh"
    "scripts/03_osd_add.sh"
    "scripts/04_opennebula_install.sh"
    "scripts/05_prometheus_install.sh"
    "scripts/06_grafana_install.sh"
    "scripts/ceph_manage.sh"
    "scripts/health_check.sh"
    "scripts/start_services.sh"
    "scripts/stop_services.sh"
    ".deployment.conf"
    "deployment-lab.conf"
    "deployment-prod.conf"
    "README.md"
    "QUICKSTART.md"
    "INDEX.md"
    "TROUBLESHOOTING.md"
    "ASTRA_LINUX_NOTES.md"
    "MISSING_PACKAGES.md"
)

echo "===== ПРОВЕРКА ОБЯЗАТЕЛЬНЫХ ФАЙЛОВ ====="
for file in "${REQUIRED_FILES[@]}"; do
    full_path="$SCRIPT_DIR/$file"
    if [[ -f "$full_path" ]]; then
        echo -e "${GREEN}✓${NC} $file"
        ((FOUND_FILES++))
    else
        echo -e "${RED}✗${NC} $file (ОТСУТСТВУЕТ)"
        ((MISSING_FILES++))
    fi
done

echo ""
echo "===== СТАТИСТИКА ====="
echo "Найдено файлов: $FOUND_FILES"
echo "Отсутствует файлов: $MISSING_FILES"

echo ""
echo "===== ПРОВЕРКА ДИРЕКТОРИЙ ====="
for dir in scripts config monitoring deb; do
    full_path="$SCRIPT_DIR/$dir"
    if [[ -d "$full_path" ]]; then
        count=$(find "$full_path" -type f | wc -l)
        echo -e "${GREEN}✓${NC} $dir/ ($count файлов)"
    else
        echo -e "${YELLOW}!${NC} $dir/ (может быть создана позже)"
    fi
done

echo ""
echo "===== ПРОВЕРКА РАЗРЕШЕНИЙ ====="
# Проверка исполняемых скриптов
for script in scripts/*.sh; do
    if [[ -f "$script" ]]; then
        if [[ -x "$script" ]]; then
            echo -e "${GREEN}✓${NC} $(basename "$script") (исполняемый)"
        else
            echo -e "${YELLOW}!${NC} $(basename "$script") (НЕ исполняемый)"
            echo "    Выполните: chmod +x $script"
        fi
    fi
done

echo ""
echo "===== ПРОВЕРКА КОНФИГУРАЦИИ ====="
if [[ -f "$SCRIPT_DIR/.deployment.conf" ]]; then
    echo -e "${GREEN}✓${NC} .deployment.conf найден"
    
    # Проверка основных параметров
    if grep -q "CLUSTER_NAME=" "$SCRIPT_DIR/.deployment.conf"; then
        echo "  ✓ CLUSTER_NAME определён"
    fi
    if grep -q "MONITOR_NODE=" "$SCRIPT_DIR/.deployment.conf"; then
        echo "  ✓ MONITOR_NODE определён"
    fi
    if grep -q "COMPUTE_NODES=" "$SCRIPT_DIR/.deployment.conf"; then
        echo "  ✓ COMPUTE_NODES определён"
    fi
fi

echo ""
echo "===== ПРОВЕРКА DEB ФАЙЛОВ ====="
if [[ -d "$SCRIPT_DIR/deb" ]]; then
    DEB_COUNT=$(ls "$SCRIPT_DIR/deb"/*.deb 2>/dev/null | wc -l)
    if [[ $DEB_COUNT -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} Найдено $DEB_COUNT .deb файлов"
    else
        echo -e "${YELLOW}!${NC} .deb файлы не найдены"
        echo "    Поместите OpenNebula .deb файлы в deb/ директорию"
    fi
else
    echo -e "${YELLOW}!${NC} Директория deb/ не создана"
    echo "    Создайте: mkdir -p deb"
fi

echo ""
echo "===== ИНФОРМАЦИЯ О СИСТЕМЕ ====="
echo "ОС: $(lsb_release -d | cut -f2) || $(cat /etc/os-release | grep PRETTY_NAME)"
echo "Ядро: $(uname -r)"
echo "Хостнейм: $(hostname)"
echo "IP адреса: $(hostname -I)"

echo ""
if [[ $MISSING_FILES -eq 0 ]]; then
    echo -e "${GREEN}===== ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ! =====${NC}"
    echo "Проект готов к развёртыванию"
    echo ""
    echo "Следующие шаги:"
    echo "1. Прочитайте QUICKSTART.md"
    echo "2. Отредактируйте .deployment.conf (если нужно)"
    echo "3. Поместите OpenNebula .deb файлы в deb/"
    echo "4. Запустите: sudo ./scripts/deploy.sh all .deployment.conf"
else
    echo -e "${RED}===== ОБНАРУЖЕНЫ ПРОБЛЕМЫ =====${NC}"
    echo "Пожалуйста, создайте отсутствующие файлы или директории"
    exit 1
fi

echo ""
echo "Для справки читайте: README.md или INDEX.md"
