#!/bin/bash
#############################################################################
# Скрипт быстрого запуска всех сервисов после перезагрузки
# 
# Использование: sudo ./start_services.sh
#############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "===== ЗАПУСК ВСЕХ СЕРВИСОВ CEPH ====="

# Запуск Ceph Monitor
echo -n "Monitor... "
systemctl start ceph-mon@$(hostname) && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Запуск Ceph Manager
echo -n "Manager... "
systemctl start ceph-mgr@$(hostname) && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Запуск Ceph OSD
echo -n "OSD диски... "
systemctl start ceph-osd@\* && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Запуск Node Exporter
echo -n "Node Exporter... "
systemctl start node_exporter 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Запуск Prometheus (если на этом узле)
echo -n "Prometheus... "
systemctl start prometheus 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Запуск Grafana (если на этом узле)
echo -n "Grafana... "
systemctl start grafana-server 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Запуск OpenNebula (если на этом узле)
echo -n "OpenNebula... "
systemctl start opennebula 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

echo -n "OpenNebula Sunstone... "
systemctl start opennebula-sunstone 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

echo ""
echo "Ожидание инициализации (10 сек)..."
sleep 10

echo ""
echo "===== СТАТУС СЕРВИСОВ ====="
ceph -s
