#!/bin/bash
#############################################################################
# Скрипт установки Prometheus для мониторинга Ceph
# Должен быть запущен на узле astra-monitor1
# 
# Использование: sudo ./05_prometheus_install.sh
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

if [[ $EUID -ne 0 ]]; then
   log_error "Этот скрипт должен быть запущен с правами root"
fi

log_info "===== УСТАНОВКА Prometheus ====="

# Создание пользователя prometheus
if ! id -u prometheus &>/dev/null; then
    log_info "Создание пользователя prometheus..."
    useradd --no-create-home --shell /bin/false prometheus
fi

# Создание директорий
log_info "Создание директорий..."
mkdir -p /etc/prometheus
mkdir -p /var/lib/prometheus
chown prometheus:prometheus /etc/prometheus
chown prometheus:prometheus /var/lib/prometheus

# Загрузка и установка Prometheus
log_info "Загрузка Prometheus..."
cd /tmp
LATEST_VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
log_info "Версия Prometheus: $LATEST_VERSION"

wget -q "https://github.com/prometheus/prometheus/releases/download/v${LATEST_VERSION}/prometheus-${LATEST_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${LATEST_VERSION}.linux-amd64.tar.gz"

# Установка бинарников
log_info "Установка бинарников Prometheus..."
cp "prometheus-${LATEST_VERSION}.linux-amd64/prometheus" /usr/local/bin/
cp "prometheus-${LATEST_VERSION}.linux-amd64/promtool" /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus
chown prometheus:prometheus /usr/local/bin/promtool

# Копирование консолей (опционально)
cp -r "prometheus-${LATEST_VERSION}.linux-amd64/consoles" /etc/prometheus/
cp -r "prometheus-${LATEST_VERSION}.linux-amd64/console_libraries" /etc/prometheus/
chown -R prometheus:prometheus /etc/prometheus/consoles
chown -R prometheus:prometheus /etc/prometheus/console_libraries

# Очистка
rm -rf "prometheus-${LATEST_VERSION}.linux-amd64"*

# Создание конфигурационного файла Prometheus
log_info "Создание конфигурационного файла Prometheus..."
cat > /etc/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s
  external_labels:
    monitor: 'ceph-cluster'
    environment: 'production'
    security_level: 'eagle'

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets: []

# Load rules once and periodically evaluate them
rule_files:
  - /etc/prometheus/rules/*.yml

# Scrape configurations
scrape_configs:
  # Prometheus сам
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter для сбора метрик с хостов
  - job_name: 'node-exporter'
    static_configs:
      - targets:
          - 'astra-monitor1:9100'
          - 'astra-node1:9100'
          - 'astra-node2:9100'
          - 'astra-node3:9100'

  # Ceph Manager (Prometheus module)
  - job_name: 'ceph'
    static_configs:
      - targets:
          - 'astra-monitor1:9283'
    metrics_path: '/metrics'

  # Ceph Exporter (если используется отдельный)
  - job_name: 'ceph-exporter'
    static_configs:
      - targets:
          - 'astra-monitor1:9926'

  # OpenNebula метрики (если доступны)
  - job_name: 'opennebula'
    static_configs:
      - targets:
          - 'astra-monitor1:9269'

  # Blackbox Exporter для проверки доступности услуг
  - job_name: 'blackbox'
    metrics_path: /probe
    static_configs:
      - targets:
          - 'http://astra-monitor1:4567'  # OpenNebula Sunstone
          - 'http://astra-monitor1:9869'  # OpenNebula XML-RPC
          - 'http://astra-node1:9100'     # Node Exporter
          - 'http://astra-node2:9100'
          - 'http://astra-node3:9100'
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115

  # Prometheus RGW Gateway (для Object Storage)
  - job_name: 'rgw'
    static_configs:
      - targets:
          - 'astra-monitor1:7480'
EOF

chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Создание директории для правил
mkdir -p /etc/prometheus/rules
chown prometheus:prometheus /etc/prometheus/rules

# Создание файла правил для алертинга
log_info "Создание правил алертинга..."
cat > /etc/prometheus/rules/ceph_alerts.yml <<'EOF'
groups:
  - name: ceph_cluster
    interval: 30s
    rules:
      - alert: CephClusterDown
        expr: up{job="ceph"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Ceph кластер недоступен"
          description: "Ceph Monitor на {{ $labels.instance }} не отвечает"

      - alert: CephOSDDown
        expr: ceph_osd_up == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "OSD диск вышел из строя"
          description: "OSD {{ $labels.ceph_daemon }} вышел из строя"

      - alert: CephPGIncomplete
        expr: ceph_pg_incomplete > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Незавершённые PG"
          description: "Обнаружено {{ $value }} незавершённых placement groups"

      - alert: CephHealthWarn
        expr: ceph_health_status > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Ceph здоровье в режиме предупреждения"
          description: "Ceph кластер в режиме WARN"

  - name: node_alerts
    interval: 30s
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Высокое использование CPU на {{ $labels.instance }}"
          description: "CPU использование: {{ $value | humanize }}%"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Высокое использование памяти на {{ $labels.instance }}"
          description: "Память использование: {{ $value | humanize }}%"

      - alert: DiskSpaceWarning
        expr: (1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Мало свободного места на диске {{ $labels.device }}"
          description: "Использование диска: {{ $value | humanize }}%"

      - alert: HighDiskIO
        expr: rate(node_disk_io_time_seconds_total[5m]) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Высокая нагрузка на диск {{ $labels.device }}"
          description: "Нагрузка на диск: {{ $value | humanize }}"
EOF

chown prometheus:prometheus /etc/prometheus/rules/ceph_alerts.yml

# Создание systemd сервиса для Prometheus
log_info "Создание systemd сервиса Prometheus..."
cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target
AssertFileIsExecutable=/usr/local/bin/prometheus

[Service]
Type=simple
User=prometheus
Group=prometheus
ProtectSystem=full
ProtectHome=yes
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes

ExecStart=/usr/local/bin/prometheus \\
  --config.file=/etc/prometheus/prometheus.yml \\
  --storage.tsdb.path=/var/lib/prometheus/ \\
  --storage.tsdb.retention.time=30d \\
  --web.console.templates=/etc/prometheus/consoles \\
  --web.console.libraries=/etc/prometheus/console_libraries \\
  --web.enable-lifecycle \\
  --web.max-connections=512

Restart=on-failure
RestartSec=5s

SyslogIdentifier=prometheus
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Включение и запуск Prometheus
log_info "Запуск Prometheus..."
systemctl daemon-reload
systemctl enable prometheus
systemctl restart prometheus
sleep 3

# Проверка статуса
log_info "Проверка статуса Prometheus..."
systemctl status prometheus --no-pager | head -20 | tee -a "$LOG_FILE"

# Открытие портов в брандмауэре
log_info "Конфигурация брандмауэра..."
if command -v ufw &> /dev/null; then
    ufw allow 9090/tcp
    ufw status | grep 9090 | tee -a "$LOG_FILE"
fi

log_info "===== УСТАНОВКА Prometheus ЗАВЕРШЕНА ====="
log_info "Веб-интерфейс Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
log_info "Все логи: $LOG_FILE"
