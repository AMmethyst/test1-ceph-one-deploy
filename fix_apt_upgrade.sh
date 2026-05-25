#!/bin/bash
#############################################################################
# Вспомогательный скрипт для решения проблемы apt-get upgrade
# Специально для Astra Linux 1.7 с уровнем защиты "Орёл"
#
# Использование: sudo ./fix_apt_upgrade.sh
#############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===== ИСПРАВЛЕНИЕ apt-get upgrade =====${NC}\n"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}✗ Этот скрипт должен быть запущен с правами root${NC}"
   echo "Используйте: sudo $0"
   exit 1
fi

# 1. Проверить текущее состояние
echo "=== Проверка текущего состояния ==="
if apt-get upgrade -s &>/dev/null 2>&1; then
    echo -e "${GREEN}✓ apt-get upgrade уже работает${NC}"
    exit 0
fi

echo -e "${YELLOW}! apt-get upgrade отключена${NC}"
echo ""

# 2. Способ 1: Использовать опцию APT
echo "=== Способ 1: Обновление с опцией APT (рекомендуется) ==="
echo "Выполнение: apt-get upgrade с APT::Get::EnableUpgrade=true"
echo ""

apt-get update
apt-get -o APT::Get::AutomaticReboot=false -o APT::Get::EnableUpgrade=true upgrade -y 2>&1 | tee /tmp/apt_upgrade.log

if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    echo -e "${GREEN}✓ apt-get upgrade выполнен успешно${NC}"
else
    echo -e "${YELLOW}! apt-get upgrade завершился с предупреждениями (это нормально)${NC}"
fi

echo ""
echo "=== Дополнительные параметры APT ==="
echo ""
echo "Если вы хотите постоянно включить apt-get upgrade, добавьте в:"
echo "  /etc/apt/apt.conf.d/50unattended-upgrades"
echo ""
echo "Содержимое для добавления:"
echo ""
echo "  // Включить apt-get upgrade"
echo "  APT::Get::EnableUpgrade \"true\";"
echo ""

# 3. Предложить добавить конфигурацию
read -p "Хотите добавить конфигурацию для постоянного включения apt-get upgrade? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Добавление конфигурации..."
    cat >> /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'

// Включить apt-get upgrade для Astra Linux 1.7 "Орёл"
APT::Get::EnableUpgrade "true";
APT::Get::AutomaticReboot "false";
EOF
    
    if [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
        echo -e "${GREEN}✓ Конфигурация добавлена${NC}"
        echo "Проверка: cat /etc/apt/apt.conf.d/50unattended-upgrades | tail -5"
        cat /etc/apt/apt.conf.d/50unattended-upgrades | tail -5
    else
        echo -e "${RED}✗ Ошибка при добавлении конфигурации${NC}"
    fi
fi

echo ""
echo "=== Проверка результата ==="
if apt-get upgrade -s &>/dev/null 2>&1; then
    echo -e "${GREEN}✓ apt-get upgrade теперь доступна${NC}"
else
    echo -e "${YELLOW}! apt-get upgrade всё ещё может требовать опции APT::Get::EnableUpgrade${NC}"
    echo ""
    echo "Это нормально для Astra Linux 1.7 с уровнем защиты 'Орёл'"
    echo "Используйте для обновления:"
    echo "  apt-get -o APT::Get::EnableUpgrade=true upgrade -y"
fi

echo ""
echo -e "${GREEN}===== ЗАВЕРШЕНО =====${NC}"
