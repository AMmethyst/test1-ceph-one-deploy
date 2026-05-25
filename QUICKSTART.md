# Быстрый старт: Развёртывание Ceph + OpenNebula на Astra Linux

**Время развёртывания:** ~30-60 минут (в зависимости от железа и интернета)

## Шаг 1: Подготовка окружения

### На каждой виртуальной машине

1. **Установите Astra Linux 1.7** (или убедитесь, что оно установлено)

2. **Проверьте сеть:**
   ```bash
   ip addr show
   ping 8.8.8.8  # интернет
   ```

3. **Отредактируйте /etc/hostname:**
   ```bash
   sudo nano /etc/hostname
   # astra-monitor1  для монитор-узла
   # astra-node1     для узлов хранения
   # astra-node2
   # astra-node3
   ```

4. **Обновите /etc/hosts:**
   ```bash
   sudo nano /etc/hosts
   ```
   Добавьте:
   ```
   192.168.1.100  astra-monitor1
   192.168.1.101  astra-node1
   192.168.1.102  astra-node2
   192.168.1.103  astra-node3
   ```

5. **Перезагрузитесь:**
   ```bash
   sudo reboot
   ```

## Шаг 2: Подготовка скриптов

### На astra-monitor1

1. **Клонируйте репозиторий:**
   ```bash
   cd /tmp
   git clone <repo-url> ceph-deploy
   cd ceph-deploy
   ```

2. **Установите права:**
   ```bash
   chmod +x scripts/*.sh
   ```

3. **Скопируйте OpenNebula .deb файлы:**
   ```bash
   mkdir -p deb
   # Поместите сюда .deb файлы OpenNebula
   cp /path/to/*.deb deb/
   ```

4. **Отредактируйте конфигурацию (если нужно):**
   ```bash
   nano .deployment.conf
   ```

## Шаг 3: Развёртывание

### Вариант 1: Полное автоматическое развёртывание

```bash
sudo ./scripts/deploy.sh all .deployment.conf
```

Ждите завершения (20-40 минут). Скрипт:
- Подготовит окружение на всех узлах
- Инициализирует Ceph кластер
- Добавит OSD диски
- Установит OpenNebula, Prometheus, Grafana

### Вариант 2: Пошаговое развёртывание

**На каждом узле (astra-monitor1, astra-node1-3):**

```bash
# 1. Подготовка окружения
sudo ./scripts/00_prerequisites.sh

# 2. Подготовка конкретного узла
sudo ./scripts/01_node_prepare.sh $(hostname) $(hostname -I | awk '{print $1}')

# 3. Перезагрузитесь
sudo reboot
```

**На astra-monitor1:**

```bash
# 4. Инициализация Ceph
sudo ./scripts/02_ceph_deploy.sh ceph

# 5. Проверка Monitor
ceph -s  # должен показать "HEALTH_OK"

# 6. Установка мониторинга
sudo ./scripts/05_prometheus_install.sh
sudo ./scripts/06_grafana_install.sh

# 7. Установка OpenNebula
sudo ./scripts/04_opennebula_install.sh ./deb
```

**На astra-node1, astra-node2, astra-node3:**

```bash
# 8. Добавление OSD дисков (на каждом узле)
sudo ./scripts/03_osd_add.sh /dev/sdb ceph
sudo ./scripts/03_osd_add.sh /dev/sdc ceph  # если есть второй диск
```

## Шаг 4: Проверка статуса

```bash
# Статус Ceph
sudo ceph -s

# Должно вывести что-то вроде:
# cluster:
#   id:     12345678-1234-1234-1234-123456789012
#   health: HEALTH_OK

# Статус OSD
sudo ceph osd tree

# Проверка мониторинга
curl http://localhost:9090  # Prometheus
curl http://localhost:3000   # Grafana
```

## Шаг 5: Начальная конфигурация

### Prometheus

1. Откройте http://astra-monitor1:9090
2. Перейдите в Status -> Targets
3. Проверьте, что все targets in "UP"

### Grafana

1. Откройте http://astra-monitor1:3000
2. Логин: admin, пароль: changeme
3. **ВАЖНО:** Измените пароль! (admin -> admin password)
4. Добавьте дашборды для Ceph

### OpenNebula Sunstone

1. Откройте https://astra-monitor1:4567
2. Логин: admin, пароль: (см. `/etc/opennebula/initial_credentials.txt`)
3. Добавьте аккаунты хостов:
   - Infrastructure -> Hosts -> Add
   - Добавьте узлы (astra-node1-3)

## Шаг 6: Создание пула хранения (Ceph)

```bash
# Создать пул для VM дисков
sudo ceph osd pool create one-compute 32 32

# Создать образ (image) в пуле
sudo rbd create -p one-compute disk1 --size 10G

# Проверить
sudo rbd ls -p one-compute
```

## Шаг 7: Первый VM в OpenNebula

1. В Sunstone перейдите: Virtual -> Images
2. Create -> Create image from Ceph
3. Создайте VM из этого образа

## Полезные команды

```bash
# Статус кластера
sudo ceph -s
sudo ceph health detail

# Статус OSD
sudo ceph osd tree
sudo ceph osd status

# Статус пулов
sudo ceph osd pool ls
sudo ceph df

# Просмотр логов
sudo journalctl -u ceph-mon@$(hostname) -f
sudo journalctl -u ceph-osd@\* -f

# Диагностика
sudo ./scripts/health_check.sh

# Управление
sudo ./scripts/ceph_manage.sh status
sudo ./scripts/ceph_manage.sh backup
```

## Решение проблем

### OSD не присоединяется

```bash
# Проверить диск
sudo lsblk | grep sdb

# Попробовать добавить снова
sudo ./scripts/03_osd_add.sh /dev/sdb ceph

# Проверить логи
sudo journalctl -u ceph-osd@0 -n 50
```

### Prometheus не видит метрики

```bash
# Проверить Node Exporter
curl http://astra-node1:9100/metrics

# Перезагрузить Prometheus
sudo systemctl restart prometheus
```

### Grafana не видит Prometheus

```bash
# В Grafana: Configuration -> Data Sources
# Проверьте URL: http://localhost:9090
# Нажмите "Test"
```

### OpenNebula не подключается к Ceph

```bash
# Проверить ключи Ceph
sudo ls -la /etc/opennebula/ceph/

# Проверить RBD
sudo rbd ls
```

## Производительность и тюнинг

Для production среды рекомендуется:

```bash
# Увеличить RAM для OSD
# В /etc/ceph/ceph.conf добавить:
# [osd]
# osd_memory_target = 8589934592  # 8 GB

# Использовать отдельные диски для WAL/DB
# ceph-volume lvm create --data /dev/sdb --wal /dev/sdc --db /dev/sdd

# Увеличить количество threads
# [osd]
# osd_op_threads = 8
# osd_disk_threads = 4
```

## Безопасность

1. **Измените все пароли по умолчанию:**
   ```bash
   # Grafana
   # OpenNebula
   # MySQL (if applicable)
   ```

2. **Включите SSL сертификаты:**
   ```bash
   # Для Grafana и OpenNebula
   sudo openssl req -x509 -nodes -days 365 \
     -newkey rsa:2048 \
     -keyout /etc/ssl/private/ceph.key \
     -out /etc/ssl/certs/ceph.crt
   ```

3. **Конфигурируйте брандмауэр:**
   ```bash
   # UFW должна быть уже настроена
   sudo ufw status
   ```

## Поддержка

- Читайте README.md для детальной документации
- Проверяйте логи: `/var/log/ceph_deployment.log`
- Запускайте диагностику: `sudo ./scripts/health_check.sh`

---

**Успешного развёртывания!** 🚀
