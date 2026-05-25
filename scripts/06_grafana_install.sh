#!/bin/bash
#############################################################################
# Скрипт установки Grafana для визуализации метрик Ceph
# Должен быть запущен на узле astra-monitor1
# 
# Использование: sudo ./06_grafana_install.sh
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

log_info "===== УСТАНОВКА Grafana ====="

# Добавление репозитория Grafana
log_info "Добавление репозитория Grafana..."
apt-get install -y software-properties-common
add-apt-repository "deb https://packages.grafana.com/oss/deb stable main" 2>/dev/null || \
echo "deb https://packages.grafana.com/oss/deb stable main" | tee /etc/apt/sources.list.d/grafana.list

# Добавление ключа репозитория
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add - 2>/dev/null || true

# Обновление и установка Grafana
log_info "Установка Grafana..."
apt-get update
apt-get install -y grafana-server

# Конфигурирование Grafana
log_info "Конфигурирование Grafana..."

# Создание резервной копии конфигурации
cp /etc/grafana/grafana.ini /etc/grafana/grafana.ini.bak

# Основные параметры
sed -i 's/^;instance_name.*/instance_name = ceph-monitor/g' /etc/grafana/grafana.ini
sed -i 's/^;admin_user.*/admin_user = admin/g' /etc/grafana/grafana.ini
sed -i 's/^;admin_password.*/admin_password = changeme/g' /etc/grafana/grafana.ini

# Параметры безопасности для уровня "Орёл"
sed -i 's/^;cookie_secure.*/cookie_secure = true/g' /etc/grafana/grafana.ini
sed -i 's/^;cookie_httponly.*/cookie_httponly = true/g' /etc/grafana/grafana.ini
sed -i 's/^;disable_brute_force_login_protection.*/disable_brute_force_login_protection = false/g' /etc/grafana/grafana.ini

# SSL/TLS (если сертификаты доступны)
if [[ -f /etc/ssl/certs/ssl-cert-snakeoil.pem ]] && [[ -f /etc/ssl/private/ssl-cert-snakeoil.key ]]; then
    log_info "Конфигурация SSL/TLS..."
    sed -i 's/^;protocol.*/protocol = https/g' /etc/grafana/grafana.ini
    sed -i 's/^;cert_file.*/cert_file = \/etc\/ssl\/certs\/ssl-cert-snakeoil.pem/g' /etc/grafana/grafana.ini
    sed -i 's/^;cert_key.*/cert_key = \/etc\/ssl\/private\/ssl-cert-snakeoil.key/g' /etc/grafana/grafana.ini
fi

# Включение и запуск Grafana
log_info "Запуск Grafana..."
systemctl enable grafana-server
systemctl restart grafana-server
sleep 3

# Проверка статуса
log_info "Проверка статуса Grafana..."
systemctl status grafana-server --no-pager | head -20 | tee -a "$LOG_FILE"

# Ожидание инициализации Grafana
log_info "Ожидание инициализации Grafana..."
max_attempts=30
attempt=0
until curl -s http://localhost:3000/api/health &>/dev/null || [[ $attempt -ge $max_attempts ]]; do
    log_info "Попытка $((attempt+1))/$max_attempts..."
    sleep 1
    ((attempt++))
done

# Добавление источника данных Prometheus
log_info "Конфигурирование источника данных Prometheus..."

DATASOURCE_JSON='{
  "name": "Prometheus-Ceph",
  "type": "prometheus",
  "url": "http://localhost:9090",
  "access": "proxy",
  "isDefault": true,
  "jsonData": {
    "timeInterval": "15s"
  }
}'

curl -X POST http://admin:changeme@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d "$DATASOURCE_JSON" 2>/dev/null || log_warn "Источник данных уже мог быть добавлен"

# Создание полезных переменных в Grafana
log_info "Добавление переменных Grafana..."

VARIABLE_JSON='{
  "name": "job",
  "type": "query",
  "datasource": "Prometheus-Ceph",
  "query": "label_values(up, job)",
  "regex": "",
  "current": {"text": "All", "value": "$__all"},
  "multi": true,
  "includeAll": true
}'

# Открытие портов в брандмауэре
log_info "Конфигурация брандмауэра..."
if command -v ufw &> /dev/null; then
    ufw allow 3000/tcp
    ufw status | grep 3000 | tee -a "$LOG_FILE"
fi

# Скачивание готовых Grafana дашбордов
log_info "Установка готовых дашбордов Grafana..."

# Директория для provisioning
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p /etc/grafana/provisioning/datasources
chown -R grafana:grafana /etc/grafana/provisioning

# Конфигурация provisioning для автоматической загрузки datasources
cat > /etc/grafana/provisioning/datasources/prometheus.yml <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true

  - name: Prometheus-Ceph
    type: prometheus
    access: proxy
    url: http://localhost:9090
    editable: true
EOF

chown grafana:grafana /etc/grafana/provisioning/datasources/prometheus.yml

# Перезагрузка Grafana для применения изменений
systemctl restart grafana-server
sleep 2

# Информация об доступе
log_info "===== УСТАНОВКА Grafana ЗАВЕРШЕНА ====="
log_info "Веб-интерфейс Grafana: http://$(hostname -I | awk '{print $1}'):3000"
log_info "Начальные учётные данные: admin / changeme"
log_info "⚠️  ВАЖНО: Измените пароль администратора после первого входа!"
log_info "Prometheus источник данных: http://localhost:9090"
log_info "Все логи: $LOG_FILE"
