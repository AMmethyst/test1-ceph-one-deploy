# Руководство по устранению неполадок Ceph на Astra Linux

## 🔴 Критические проблемы

### 1. Ceph Monitor не запускается

**Симптомы:**
```
systemctl status ceph-mon@hostname
● ceph-mon@hostname.service - Ceph cluster monitor daemon
   Loaded: loaded
   Active: failed (Result: exit-code)
```

**Решение:**

```bash
# 1. Проверьте логи
sudo journalctl -u ceph-mon@$(hostname) -n 50 -e

# 2. Проверьте конфигурацию
sudo cat /etc/ceph/ceph.conf

# 3. Проверьте FSID
sudo cat /var/lib/ceph/mon/*/keyring

# 4. Если монmap повреждена, пересоздайте
sudo rm -rf /var/lib/ceph/mon/ceph-$(hostname)
sudo monmaptool --create --add $(hostname) $(hostname -I | awk '{print $1}') \
  --fsid $(cat /etc/ceph/ceph.conf | grep fsid | awk '{print $3}') \
  /tmp/monmap

# 5. Переинициализируйте Monitor
FSID=$(cat /etc/ceph/ceph.conf | grep fsid | awk '{print $3}')
ceph-mon --mkfs -i $(hostname) --monmap /tmp/monmap --fsid $FSID \
  -c /etc/ceph/ceph.conf

# 6. Запустите
sudo systemctl restart ceph-mon@$(hostname)
```

### 2. OSD диски не присоединяются

**Симптомы:**
```
ceph osd tree
    # OSD не показаны или помечены как "down"
```

**Решение:**

```bash
# 1. Проверьте статус OSD
sudo systemctl status ceph-osd@0

# 2. Проверьте, смонтирован ли диск
mount | grep sdb

# 3. Если нет, попробуйте переинициализировать
sudo systemctl stop ceph-osd@0
sudo rm -rf /var/lib/ceph/osd/ceph-0/*

# 4. Используйте ceph-volume для пересоздания
sudo ceph-volume lvm list
sudo ceph-volume lvm zap /dev/sdb

# 5. Пересоздайте OSD
sudo ./scripts/03_osd_add.sh /dev/sdb ceph

# 6. Проверьте логи
sudo journalctl -u ceph-osd@0 -n 20 -e

# 7. Если диск физически повреждён
sudo smartctl -a /dev/sdb  # Проверка S.M.A.R.T.
```

### 3. Placement Groups (PG) в "degraded" или "peering"

**Симптомы:**
```
ceph pg stat
    # degraded PGs, peering PGs
```

**Решение:**

```bash
# 1. Проверьте общий статус
ceph health detail

# 2. Если OSD down:
sudo systemctl restart ceph-osd@<id>

# 3. Дождитесь восстановления
ceph -w

# 4. Если PG stuck:
sudo ceph pg repair <pg-id>

# 5. Для ускорения восстановления (осторожно!)
sudo ceph tell osd.\* injectargs '--osd_max_backfills 4'

# 6. После восстановления верните значение
sudo ceph tell osd.\* injectargs '--osd_max_backfills 1'
```

### 4. Кластер в режиме HEALTH_ERR

**Симптомы:**
```
ceph health detail
HEALTH_ERR mon clock skew detected
```

**Решение:**

```bash
# 1. Синхронизируйте время на всех узлах
sudo timedatectl set-ntp true
sudo systemctl restart chrony

# 2. Проверьте время
date
timedatectl

# 3. Для других ошибок читайте детальный статус
ceph health detail | tee /tmp/health.log

# 4. Используйте диагностику
./scripts/health_check.sh
```

## 🟡 Предупреждения (Warning)

### 1. Monitor in quorum but one is down

**Решение:**

```bash
# 1. Перезагрузите Monitor
sudo systemctl restart ceph-mon@$(hostname)

# 2. Проверьте кворум
sudo ceph quorum_status

# 3. Если проблема настояется:
sudo ceph mon remove $(hostname)
sudo systemctl stop ceph-mon@$(hostname)
sudo rm -rf /var/lib/ceph/mon/ceph-$(hostname)
sudo systemctl start ceph-mon@$(hostname)
```

### 2. Slow requests detected

**Причины:** Высокая нагрузка, медленные диски, сетевые проблемы

**Решение:**

```bash
# 1. Проверьте загрузку
top
iostat -xz 1

# 2. Проверьте I/O операции
ceph osd perf

# 3. Отмоніторьте запросы
ceph daemon osd.0 ops
```

### 3. Deep Scrub errors

**Решение:**

```bash
# 1. Запустите скраб
sudo ceph osd scrub <osd-id>

# 2. Или для всего кластера
sudo ceph osd pool scrub <pool-name>

# 3. Если ошибки остаются:
sudo ceph pg repair <pg-id>
```

## 🔧 Сетевые проблемы

### 1. Cluster network не работает

**Проверка:**

```bash
# 1. Проверьте интерфейсы
ip addr show

# 2. Пингуйте другие узлы
ping -I 192.168.2.100 192.168.2.101

# 3. Проверьте маршруты
ip route show

# 4. Проверьте firewall
sudo ufw status
sudo iptables -L | grep REJECT

# 5. Откройте портов
sudo ufw allow 6800:7300/tcp
sudo ufw reload
```

### 2. Public network недоступна

```bash
# 1. Проверьте конфигурацию сети
sudo cat /etc/ceph/ceph.conf | grep network

# 2. Проверьте IP адреса
hostname -I

# 3. Обновите ceph.conf если нужно
sudo nano /etc/ceph/ceph.conf

# 4. Перезагрузите Monitor
sudo systemctl restart ceph-mon@$(hostname)
```

## 🗄️ Проблемы хранилища

### 1. Недостаточно свободного места на диске

```bash
# 1. Проверьте использование
df -h
ceph df

# 2. Удалите ненужные пулы/образы
sudo rbd rm <pool>/<image>

# 3. Или добавьте новый OSD диск
./scripts/03_osd_add.sh /dev/sdd ceph
```

### 2. OSD полный (full flag set)

**Решение:**

```bash
# 1. Проверьте флаги OSD
ceph osd dump | grep full

# 2. Удалите данные или добавьте место
# Удаление (ОСТОРОЖНО!):
sudo ceph tell osd.\* injectargs '--osd_reserved_percent 5'

# 3. Или добавьте новый OSD:
./scripts/03_osd_add.sh /dev/sdd ceph
```

## 🔐 Проблемы безопасности и разрешений

### 1. Permission denied при доступе к файлам Ceph

```bash
# 1. Проверьте владельца
ls -la /var/lib/ceph/

# 2. Исправьте владельца
sudo chown -R ceph:ceph /var/lib/ceph

# 3. Проверьте разрешения
sudo chmod 700 /var/lib/ceph/mon
sudo chmod 755 /var/lib/ceph/osd
```

### 2. Authentication failed

```bash
# 1. Проверьте ключи
sudo cat /etc/ceph/ceph.client.admin.keyring

# 2. Проверьте разрешение
sudo cat /etc/ceph/ceph.conf | grep auth

# 3. Переэкспортируйте ключ если нужно
ceph auth get client.admin -o /etc/ceph/ceph.client.admin.keyring
```

## 📊 Проблемы мониторинга

### 1. Prometheus не собирает метрики

```bash
# 1. Проверьте конфигурацию Prometheus
sudo cat /etc/prometheus/prometheus.yml

# 2. Проверьте доступность целей
curl http://astra-node1:9100/metrics

# 3. Перезагрузите Prometheus
sudo systemctl restart prometheus

# 4. Проверьте логи
sudo journalctl -u prometheus -n 20
```

### 2. Grafana не видит Prometheus

```bash
# 1. В Grafana: Configuration -> Data Sources
# 2. Проверьте URL: http://localhost:9090
# 3. Нажмите "Test"

# Или через CLI:
curl -u admin:changeme \
  'http://localhost:3000/api/datasources' | jq .
```

### 3. Оповещение Alertmanager не отправляются

```bash
# 1. Проверьте конфигурацию
sudo cat /etc/prometheus/alertmanager.yml

# 2. Проверьте правила
sudo cat /etc/prometheus/rules/*.yml

# 3. Запустите Alertmanager
sudo systemctl restart alertmanager

# 4. Проверьте статус
curl http://localhost:9093/api/v1/alerts
```

## 🆘 Экстренные ситуации

### Откат системы к состоянию восстановления

```bash
# 1. Остановите все сервисы
sudo ./scripts/stop_services.sh

# 2. Восстановите конфигурацию из резервной копии
sudo ./scripts/ceph_manage.sh restore /var/backups/ceph-config/latest.tar.gz

# 3. Перезагрузите систему
sudo reboot

# 4. Запустите сервисы
sudo ./scripts/start_services.sh

# 5. Проверьте статус
sudo ceph -s
```

### Переустановка Monitor

```bash
# ОСТОРОЖНО! Это экстренная процедура!

# 1. Удалите старый Monitor
sudo systemctl stop ceph-mon@$(hostname)
sudo rm -rf /var/lib/ceph/mon/ceph-$(hostname)

# 2. Пересоздайте
sudo ./scripts/02_ceph_deploy.sh ceph

# 3. Добавьте OSD диски заново
sudo ./scripts/03_osd_add.sh /dev/sdb ceph
```

### Форсированное восстановление (последняя мера)

```bash
# ИСПОЛЬЗОВАТЬ ТОЛЬКО В КРИТИЧЕСКИХ СЛУЧАЯХ!

# 1. Остановьте все OSD
for i in {0..9}; do
  sudo systemctl stop ceph-osd@$i 2>/dev/null || true
done

# 2. Очистите флаги
sudo ceph osd set nodown
sudo ceph osd set noup
sudo ceph osd set noin

# 3. Запустите OSD
sudo systemctl start ceph-osd@\*

# 4. Снимите флаги постепенно
sleep 30
sudo ceph osd unset noin
sleep 30
sudo ceph osd unset noup
sleep 30
sudo ceph osd unset nodown
```

## 📞 Получение помощи

Если проблема не решена:

1. **Собери информацию:**
```bash
sudo ceph health detail > /tmp/ceph_health.log
sudo ceph osd tree > /tmp/ceph_osd_tree.log
sudo journalctl -u ceph-\* > /tmp/ceph_logs.txt
sudo cat /etc/ceph/ceph.conf > /tmp/ceph_config.txt

# Создайте архив
tar czf /tmp/ceph_debug_$(date +%Y%m%d_%H%M%S).tar.gz \
  /tmp/ceph_*.log /tmp/ceph_*.txt /var/log/ceph_deployment.log
```

2. **Обратитесь к:**
   - Ceph Community: https://ceph.io/community/
   - Stack Overflow (tag: ceph)
   - Ваш провайдер поддержки

---

**Помните:** Всегда делайте резервные копии перед экспериментами!
