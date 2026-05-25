#!/bin/bash
#############################################################################
# Скрипт проверки совместимости с Astra Linux 1.7
# 
# Использование: ./verify_astra_linux.sh
#############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===== ПРОВЕРКА СОВМЕСТИМОСТИ С ASTRA LINUX 1.7 =====${NC}\n"

# Счётчики
PASS=0
FAIL=0
WARN=0

check_result() {
    if [[ $1 -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} $2"
        ((PASS++))
    elif [[ $1 -eq 2 ]]; then
        echo -e "${YELLOW}!${NC} $2"
        ((WARN++))
    else
        echo -e "${RED}✗${NC} $2"
        ((FAIL++))
    fi
}

# 1. Проверка ОС
echo "=== Проверка операционной системы ==="
if lsb_release -d 2>/dev/null | grep -q "Astra Linux"; then
    ASTRA_VERSION=$(lsb_release -r | awk '{print $2}')
    if [[ "$ASTRA_VERSION" == "1.7" ]]; then
        check_result 0 "Astra Linux 1.7 обнаружена"
    else
        check_result 1 "Astra Linux версия $ASTRA_VERSION (требуется 1.7)"
    fi
else
    check_result 1 "Astra Linux не обнаружена"
    lsb_release -a 2>/dev/null || cat /etc/os-release | head -3
fi

# 2. Проверка ядра
echo ""
echo "=== Проверка ядра ==="
KERNEL_VERSION=$(uname -r)
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)

if [[ $KERNEL_MAJOR -gt 5 ]] || [[ $KERNEL_MAJOR -eq 5 && $KERNEL_MINOR -ge 15 ]]; then
    check_result 0 "Ядро $KERNEL_VERSION (требуется 5.15+)"
else
    check_result 1 "Ядро $KERNEL_VERSION (требуется 5.15+)"
fi

# 3. Проверка уровня защиты
echo ""
echo "=== Проверка уровня защиты ==="
if grep -q "eagle\|orël" /etc/issue* /etc/os-release 2>/dev/null; then
    check_result 0 "Уровень защиты 'Орёл' обнаружен"
else
    check_result 2 "Уровень защиты не подтверждён (может быть другой)"
fi

# 4. Проверка AppArmor
echo ""
echo "=== Проверка AppArmor ==="
if command -v aa-status &>/dev/null; then
    if systemctl is-active --quiet apparmor; then
        check_result 0 "AppArmor установлен и активен"
    else
        check_result 2 "AppArmor установлен но не активен"
    fi
else
    check_result 2 "AppArmor не установлен (опционально для Astra Linux)"
fi

# 5. Проверка UFW
echo ""
echo "=== Проверка UFW (Firewall) ==="
if command -v ufw &>/dev/null; then
    if ufw status | grep -q "Status: active"; then
        check_result 0 "UFW активен"
    else
        check_result 2 "UFW установлен но неактивен"
    fi
else
    check_result 2 "UFW не установлен"
fi

# 6. Проверка apt-get upgrade
echo ""
echo "=== Проверка apt-get upgrade ==="
if apt-get upgrade -s &>/dev/null 2>&1; then
    check_result 0 "apt-get upgrade доступен"
elif apt-get -o APT::Get::AutomaticReboot=false -o APT::Get::EnableUpgrade=true upgrade -s &>/dev/null 2>&1; then
    check_result 2 "apt-get upgrade отключена, но может быть включена опцией APT::Get::EnableUpgrade (это нормально для 'Орла')"
else
    check_result 2 "apt-get upgrade отключена (это нормально для 'Орла')"
fi

# 7. Проверка требуемых пакетов
echo ""
echo "=== Проверка требуемых пакетов ==="
PACKAGES=("curl" "wget" "git" "openssh-server" "python3" "pip3" "jq")

for pkg in "${PACKAGES[@]}"; do
    if command -v "$pkg" &>/dev/null || dpkg -l | grep -q "^ii.*$pkg"; then
        check_result 0 "$pkg установлен"
    else
        check_result 2 "$pkg не установлен (будет установлен скриптами)"
    fi
done

# 8. Проверка памяти
echo ""
echo "=== Проверка ресурсов ==="
RAM_GB=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
if [[ $RAM_GB -ge 4 ]]; then
    check_result 0 "RAM: ${RAM_GB}GB (требуется минимум 4GB)"
else
    check_result 1 "RAM: ${RAM_GB}GB (требуется минимум 4GB)"
fi

DISK_GB=$(df -BG / | tail -1 | awk '{print $2}' | sed 's/G//')
if [[ $DISK_GB -ge 20 ]]; then
    check_result 0 "Дисковое пространство: ${DISK_GB}GB (требуется минимум 20GB)"
else
    check_result 1 "Дисковое пространство: ${DISK_GB}GB (требуется минимум 20GB)"
fi

# 9. Проверка сетевого подключения
echo ""
echo "=== Проверка сети ==="
if ping -c 1 8.8.8.8 &>/dev/null 2>&1; then
    check_result 0 "Интернет доступен"
else
    check_result 2 "Интернет недоступен (может потребоваться для скачивания пакетов)"
fi

# 10. Проверка SSH
echo ""
echo "=== Проверка SSH ==="
if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
    check_result 0 "SSH сервер запущен"
else
    check_result 2 "SSH сервер не запущен (будет включен скриптами)"
fi

# Итоговый результат
echo ""
echo -e "${BLUE}===== ИТОГИ ПРОВЕРКИ =====${NC}"
echo "✓ Пройдено проверок: $PASS"
echo "! Предупреждений: $WARN"
echo "✗ Ошибок: $FAIL"

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}===== СИСТЕМА СОВМЕСТИМА С ASTRA LINUX 1.7 =====${NC}"
    echo ""
    echo "Вы можете начать развёртывание:"
    echo "  sudo ./scripts/deploy.sh all .deployment.conf"
    exit 0
else
    echo ""
    echo -e "${RED}===== ОБНАРУЖЕНЫ КРИТИЧЕСКИЕ ПРОБЛЕМЫ =====${NC}"
    echo ""
    echo "Пожалуйста, исправьте ошибки перед развёртыванием"
    exit 1
fi
