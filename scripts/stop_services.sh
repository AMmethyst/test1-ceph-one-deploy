#!/bin/bash
#############################################################################
# Скрипт остановки всех сервисов
# 
# Использование: sudo ./stop_services.sh
#############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}===== ОСТАНОВКА ВСЕХ СЕРВИСОВ CEPH =====${NC}"
echo -e "${YELLOW}⚠️  Это остановит все хранилища и приложения!${NC}"
read -p "Продолжить? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Отменено"
    exit 1
fi

echo ""
echo "Остановка сервисов..."

# Остановка OpenNebula (если на этом узле)
echo -n "OpenNebula Sunstone... "
systemctl stop opennebula-sunstone 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

echo -n "OpenNebula... "
systemctl stop opennebula 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Остановка Grafana (если на этом узле)
echo -n "Grafana... "
systemctl stop grafana-server 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Остановка Prometheus (если на этом узле)
echo -n "Prometheus... "
systemctl stop prometheus 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Остановка Node Exporter
echo -n "Node Exporter... "
systemctl stop node_exporter 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Остановка Ceph OSD
echo -n "OSD диски... "
systemctl stop ceph-osd@\* 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Остановка Ceph Manager
echo -n "Manager... "
systemctl stop ceph-mgr@$(hostname) 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Остановка Ceph Monitor (в последнюю очередь)
echo -n "Monitor... "
systemctl stop ceph-mon@$(hostname) 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

echo ""
echo -e "${GREEN}===== ВСЕ СЕРВИСЫ ОСТАНОВЛЕНЫ =====${NC}"
