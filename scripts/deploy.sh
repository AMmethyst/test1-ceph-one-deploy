#!/bin/bash
#############################################################################
# ГЛАВНЫЙ СКРИПТ РАЗВЁРТЫВАНИЯ
# Orchestration скрипт для автоматизации всей системы
# 
# Использование: sudo ./deploy.sh [mode] [config_file]
# Режимы: all, prerequisites, nodes, ceph, opennebula, monitoring
# 
# Пример: sudo ./deploy.sh all /path/to/deployment.conf
#############################################################################

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOG_FILE="/var/log/ceph_deployment.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Функции логирования
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n" | tee -a "$LOG_FILE"
}

# Проверка возможности использования sudo
if ! sudo -n true 2>/dev/null; then
   log_warn "Скрипт требует доступ к sudo. Введите пароль если требуется..."
   sudo true || { log_error "Нет доступа к sudo"; exit 1; }
fi

# Загрузка конфигурации
CONFIG_FILE="${2:-.deployment.conf}"

if [[ -f "$CONFIG_FILE" ]]; then
    log_info "Загрузка конфигурации из: $CONFIG_FILE"
    source "$CONFIG_FILE"
else
    log_warn "Файл конфигурации не найден: $CONFIG_FILE"
    log_info "Используются параметры по умолчанию"
    
    # Параметры по умолчанию
    CLUSTER_NAME="ceph"
    MONITOR_NODE="astra-monitor1"
    COMPUTE_NODES=("astra-node1" "astra-node2" "astra-node3")
    OSD_DEVICES=("/dev/sdb" "/dev/sdc" "/dev/sdd")
    DEB_PATH="./deb"
    SSH_USER="$(whoami)"  # Используем текущего пользователя
    ENABLE_OPENNEBULA=true
    ENABLE_PROMETHEUS=true
    ENABLE_GRAFANA=true
fi

# Функция для проверки наличия скриптов
check_scripts() {
    local scripts=("00_prerequisites.sh" "01_node_prepare.sh" "02_ceph_deploy.sh" \
                   "03_osd_add.sh" "04_opennebula_install.sh" \
                   "05_prometheus_install.sh" "06_grafana_install.sh")
    
    for script in "${scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            log_error "Скрипт не найден: $SCRIPT_DIR/$script"
            return 1
        fi
    done
    return 0
}

# Функция для проверки доступности хостов
check_hosts() {
    log_info "Проверка доступности хостов..."
    
    for host in "$MONITOR_NODE" "${COMPUTE_NODES[@]}"; do
        if ping -c 1 "$host" &>/dev/null; then
            log_info "✓ Хост доступен: $host"
        else
            log_warn "✗ Хост недоступен: $host (может потребоваться SSH)"
        fi
    done
}

# Функция для подготовки окружения
deploy_prerequisites() {
    log_section "ПОДГОТОВКА ОКРУЖЕНИЯ"
    
    log_info "Выполнение: 00_prerequisites.sh"
    bash "$SCRIPT_DIR/00_prerequisites.sh"
    
    log_info "Предварительная подготовка завершена"
}

# Функция для подготовки узлов
deploy_nodes() {
    log_section "ПОДГОТОВКА УЗЛОВ КЛАСТЕРА"
    
    # Подготовка текущего узла
    log_info "Подготовка текущего узла ($(hostname))..."
    bash "$SCRIPT_DIR/01_node_prepare.sh" "$(hostname)" "$(hostname -I | awk '{print $1}')"
    
    # Подготовка других узлов (если доступны через SSH)
    for node in "${COMPUTE_NODES[@]}"; do
        if ssh -o ConnectTimeout=5 "${SSH_USER}@${node}" "echo 'OK'" &>/dev/null; then
            log_info "Подготовка удалённого узла: $node"
            ssh "${SSH_USER}@${node}" "cd $SCRIPT_DIR && sudo bash 01_node_prepare.sh '$node'" || \
            log_warn "Не удалось подготовить узел: $node"
        else
            log_warn "Узел $node недоступен через SSH"
        fi
    done
}

# Функция для развёртывания Ceph
deploy_ceph() {
    log_section "РАЗВЁРТЫВАНИЕ КEPH КЛАСТЕРА"
    
    log_info "Инициализация Ceph кластера: $CLUSTER_NAME"
    bash "$SCRIPT_DIR/02_ceph_deploy.sh" "$CLUSTER_NAME"
    
    # Проверка добавления OSD дисков
    log_info "Текущий узел: $(hostname)"
    if [[ "$(hostname)" == *"node"* ]]; then
        log_warn "Это node, OSD диски будут добавлены здесь"
    elif [[ "$(hostname)" == "$MONITOR_NODE" ]]; then
        log_info "Это монитор-узел, добавление OSD с удалённых узлов..."
        
        # Попытка добавления OSD дисков с удалённых узлов
        for i in "${!COMPUTE_NODES[@]}"; do
            node="${COMPUTE_NODES[$i]}"
            device="${OSD_DEVICES[$i]}"
            
            if ssh -o ConnectTimeout=5 "${SSH_USER}@${node}" "echo 'OK'" &>/dev/null; then
                log_info "Добавление OSD на узле $node ($device)..."
                ssh "${SSH_USER}@${node}" "cd $SCRIPT_DIR && sudo bash 03_osd_add.sh '$device' '$CLUSTER_NAME'" || \
                log_warn "Не удалось добавить OSD на $node"
            fi
        done
    fi
    
    log_info "Ceph развёртывание завершено"
}

# Функция для установки OpenNebula
deploy_opennebula() {
    if [[ "$ENABLE_OPENNEBULA" != "true" ]]; then
        log_warn "OpenNebula отключена в конфигурации"
        return
    fi
    
    log_section "УСТАНОВКА OpenNebula"
    
    if [[ ! -d "$DEB_PATH" ]] || ! ls "$DEB_PATH"/*.deb &>/dev/null; then
        log_warn "OpenNebula .deb файлы не найдены в: $DEB_PATH"
        log_warn "OpenNebula установка пропущена"
        return
    fi
    
    log_info "Выполнение установки OpenNebula"
    bash "$SCRIPT_DIR/04_opennebula_install.sh" "$DEB_PATH"
}

# Функция для установки Prometheus
deploy_prometheus() {
    if [[ "$ENABLE_PROMETHEUS" != "true" ]]; then
        log_warn "Prometheus отключена в конфигурации"
        return
    fi
    
    log_section "УСТАНОВКА Prometheus"
    
    log_info "Выполнение установки Prometheus"
    bash "$SCRIPT_DIR/05_prometheus_install.sh"
}

# Функция для установки Grafana
deploy_grafana() {
    if [[ "$ENABLE_GRAFANA" != "true" ]]; then
        log_warn "Grafana отключена в конфигурации"
        return
    fi
    
    log_section "УСТАНОВКА Grafana"
    
    log_info "Выполнение установки Grafana"
    bash "$SCRIPT_DIR/06_grafana_install.sh"
}

# Функция для вывода сводки
show_summary() {
    log_section "СВОДКА РАЗВЁРТЫВАНИЯ"
    
    echo "Кластер Ceph: $CLUSTER_NAME"
    echo "Монитор-узел: $MONITOR_NODE"
    echo "Узлы вычислений: ${COMPUTE_NODES[*]}"
    echo ""
    echo "Конфигурация:"
    echo "  OpenNebula: $ENABLE_OPENNEBULA"
    echo "  Prometheus: $ENABLE_PROMETHEUS"
    echo "  Grafana: $ENABLE_GRAFANA"
    echo ""
    echo "Логи развёртывания: $LOG_FILE"
    echo ""
    echo "Полезные команды:"
    echo "  Статус Ceph: ceph -s"
    echo "  Статус OSD: ceph osd tree"
    echo "  Логи Ceph: journalctl -u ceph-mon@* -f"
    echo "  Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
    echo "  Grafana: http://$(hostname -I | awk '{print $1}'):3000"
    
    if [[ "$ENABLE_OPENNEBULA" == "true" ]]; then
        echo "  OpenNebula Sunstone: https://$(hostname -I | awk '{print $1}'):4567"
    fi
}

# Главная логика
DEPLOY_MODE="${1:-all}"

log_section "CEPH DEPLOY ORCHESTRATION - Astra Linux 1.7"
log_info "Начало развёртывания: $(date)"
log_info "Режим: $DEPLOY_MODE"

# Проверка скриптов
if ! check_scripts; then
    log_error "Обязательные скрипты не найдены в: $SCRIPT_DIR"
    exit 1
fi

# Проверка доступности хостов (информативная)
check_hosts || log_warn "Проверка хостов завершена с предупреждениями"

# Выполнение в зависимости от режима
case "$DEPLOY_MODE" in
    all)
        deploy_prerequisites
        deploy_nodes
        deploy_ceph
        deploy_prometheus
        deploy_grafana
        deploy_opennebula
        ;;
    prerequisites)
        deploy_prerequisites
        ;;
    nodes)
        deploy_nodes
        ;;
    ceph)
        deploy_ceph
        ;;
    opennebula)
        deploy_opennebula
        ;;
    prometheus)
        deploy_prometheus
        ;;
    grafana)
        deploy_grafana
        ;;
    monitoring)
        deploy_prometheus
        deploy_grafana
        ;;
    *)
        log_error "Неизвестный режим: $DEPLOY_MODE"
        echo "Доступные режимы: all, prerequisites, nodes, ceph, opennebula, prometheus, grafana, monitoring"
        exit 1
        ;;
esac

show_summary

log_info "Развёртывание завершено: $(date)"
log_info "Все операции логированы в: $LOG_FILE"
