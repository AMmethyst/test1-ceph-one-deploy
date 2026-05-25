# Развёртывание Ceph кластера с OpenNebula на Astra Linux 1.7

Автоматизированное решение для развёртывания системы хранения данных на базе **Ceph** с интеграцией **OpenNebula**, **Prometheus** и **Grafana** на **Astra Linux 1.7** (Debian 10) с уровнем защиты "Орёл".

## 📋 Оглавление

- [Архитектура](#архитектура)
- [Требования](#требования)
- [Специфика Astra Linux](#специфика-astra-linux)
- [Быстрый старт](#быстрый-старт)
- [Структура проекта](#структура-проекта)
- [Описание скриптов](#описание-скриптов)
- [Конфигурация](#конфигурация)
- [Развёртывание](#развёртывание)
- [Управление и мониторинг](#управление-и-мониторинг)
- [Диагностика](#диагностика)
- [Резервное копирование](#резервное-копирование)
- [Безопасность](#безопасность)
- [Решение проблем](#решение-проблем)

## 🏗️ Архитектура

### Компоненты системы

```
┌─────────────────────────────────────────────────────────────┐
│              ASTRA LINUX 1.7 КЛАСТЕР                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐   ┌──────────────────┐                │
│  │ astra-monitor1   │   │  astra-node1-3   │                │
│  │  (Admin node)    │   │  (OSD Storage)   │                │
│  ├──────────────────┤   ├──────────────────┤                │
│  │ • Ceph Monitor   │   │ • Ceph OSD x3    │                │
│  │ • Ceph Manager   │   │ • Ceph MDS       │                │
│  │ • OpenNebula     │   │                  │                │
│  │ • Prometheus     │   │                  │                │
│  │ • Grafana        │   │                  │                │
│  │ • RGW (optional) │   │                  │                │
│  └──────────────────┘   └──────────────────┘                │
│        │                        │                            │
│        └────────────────────────┘                            │
│         (Ceph Cluster Network)                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Сетевые интерфейсы

- **Public Network (192.168.1.0/24)**: Клиентский трафик, управление
- **Cluster Network (192.168.2.0/24)**: Внутренний трафик OSD-OSD (рекомендуется)

## ✅ Требования

### Аппаратное обеспечение

**Минимум:**
- 4 виртуальных машины (1 monitor + 3 compute/storage nodes)
- 4 GB RAM на каждом узле (рекомендуется 8 GB)
- 20 GB системный диск на каждом узле
- Дополнительные диски для OSD (рекомендуется NVMe или SSD):
  - 1-3 диска на каждый compute node (для демо можно по 1 диску 20GB)

**Рекомендуется для production:**
- 16+ GB RAM на OSD узлах
- Отдельные диски для журналов (если используется filestore)
- Сетевой интерфейс 10GbE для cluster network

### Программное обеспечение

- **ОС**: Astra Linux 1.7 (Debian 10 based)
- **Ядро**: linux-5.15-generic или выше
- **Уровень защиты**: Eagle
- **Дополнительно**:
  - OpenNebula .deb пакеты (в папке `./deb/`)
  - SSH доступ между узлами
  - Интернет доступ для скачивания пакетов

## ⚠️ Специфика Astra Linux

### Уровень защиты "Орёл"

Astra Linux 1.7 с уровнем защиты "Орёл" имеет ряд ограничений в целях безопасности, которые наши скрипты **полностью поддерживают**:

- **AppArmor** вместо SELinux - ограничение доступа процессов
- **UFW Firewall** - автоматическое управление портами
- **apt-get upgrade отключена** - полное обновление отключено в целях безопасности (это нормально!)
- **Аудит системы** - логирование всех действий
- **Ограниченные разрешения файлов** - минимальный доступ по умолчанию
- **Недоступные пакеты** - некоторые пакеты могут отсутствовать в репозитории (iotop, blktrace, fio)

**Все эти ограничения автоматически обрабатываются скриптами развёртывания.**

Если вы видите сообщение об ошибке:
```
E: 'apt-get upgrade' отключена, поскольку это может привести систему в нерабочее состояние
```
**Это нормально!** Скрипты продолжат работу. Подробнее смотрите [ASTRA_LINUX_NOTES.md](ASTRA_LINUX_NOTES.md).

Если вы видите:
```
E: Для пакета "iotop" не найден кандидат на установку
```
**Это тоже нормально!** Скрипты пропустят недоступные пакеты и продолжат работу. Подробнее смотрите [MISSING_PACKAGES.md](MISSING_PACKAGES.md).

## 🚀 Быстрый старт

### 1. Подготовка

```bash
# Клонировать/скачать репозиторий
cd /path/to/deployment

# Сделать скрипты исполняемыми
chmod +x scripts/*.sh

# Поместить OpenNebula .deb файлы в папку deb/
mkdir -p deb
cp /path/to/opennebula/*.deb deb/

# Отредактировать конфигурацию (опционально)
cp .deployment.conf.example .deployment.conf
nano .deployment.conf
```

### 2. Развёртывание (все компоненты)

```bash
# На узле astra-monitor1 (или с SSH доступом к узлам)
sudo ./scripts/deploy.sh all .deployment.conf
```

### 3. Проверка статуса

```bash
# Статус Ceph
sudo ceph -s

# Статус Grafana
curl http://localhost:3000

# Статус OpenNebula
sudo su - oneadmin -c "onevm list"
```

## 📁 Структура проекта

```
test1-ceph-one-deploy/
├── scripts/                          # Основные скрипты развёртывания
│   ├── deploy.sh                    # Главный orchestration скрипт
│   ├── 00_prerequisites.sh          # Подготовка окружения
│   ├── 01_node_prepare.sh           # Подготовка узлов
│   ├── 02_ceph_deploy.sh            # Развёртывание Ceph
│   ├── 03_osd_add.sh                # Добавление OSD дисков
│   ├── 04_opennebula_install.sh     # Установка OpenNebula
│   ├── 05_prometheus_install.sh     # Установка Prometheus
│   ├── 06_grafana_install.sh        # Установка Grafana
│   ├── ceph_manage.sh               # Утилита управления Ceph
│   ├── health_check.sh              # Проверка здоровья кластера
│   ├── start_services.sh            # Запуск всех сервисов
│   └── stop_services.sh             # Остановка сервисов
│
├── config/                           # Конфигурационные файлы
│   ├── ceph.conf                    # (генерируется автоматически)
│   └── monitoring.conf              # Конфигурация мониторинга
│
├── monitoring/                       # Файлы мониторинга
│   ├── prometheus/
│   │   ├── prometheus.yml           # Конфигурация Prometheus
│   │   └── rules/                   # Правила алертинга
│   ├── grafana/
│   │   ├── dashboards/             # Готовые дашборды
│   │   └── provisioning/           # Автоматическая конфигурация
│   └── alerts/
│       ├── rules.yml               # Правила проверки
│       └── templates/              # Шаблоны уведомлений
│
├── deb/                             # OpenNebula .deb файлы
│   └── *.deb                       # (размещить сюда)
│
├── .deployment.conf                # Основной конфиг развёртывания
├── .deployment.conf.example        # Пример конфигурации
└── README.md                        # Этот файл
```

## 📝 Описание скриптов

### 00_prerequisites.sh
Подготовка окружения на каждом узле:
- Обновление системы и установка базовых пакетов
- Добавление Ceph репозитория
- Установка Ceph компонентов
- Конфигурация сети и брандмауэра
- Создание пользователя ceph
- Установка Node Exporter для мониторинга

**Использование:**
```bash
sudo ./scripts/00_prerequisites.sh
```

### 01_node_prepare.sh
Подготовка отдельного узла:
- Конфигурация имени хоста
- Обновление /etc/hosts
- Проверка дисков
- Создание директорий для Ceph
- Установка утилит мониторинга
- Конфигурация безопасности

**Использование:**
```bash
sudo ./scripts/01_node_prepare.sh [node_name] [node_ip]
sudo ./scripts/01_node_prepare.sh astra-node1 192.168.1.101
```

### 02_ceph_deploy.sh
Инициализация Ceph кластера:
- Генерирование FSID и ключей кластера
- Создание конфигурационного файла ceph.conf
- Инициализация Ceph Monitor
- Запуск Ceph Manager
- Включение модулей Prometheus и Dashboard

**Использование:**
```bash
sudo ./scripts/02_ceph_deploy.sh [cluster_name]
sudo ./scripts/02_ceph_deploy.sh ceph
```

### 03_osd_add.sh
Добавление OSD дисков в кластер:
- Проверка доступности диска
- Форматирование и подготовка диска
- Использование ceph-volume (рекомендуется)
- Интеграция с CRUSH map
- Конфигурация параметров OSD

**Использование:**
```bash
sudo ./scripts/03_osd_add.sh [device] [cluster_name]
sudo ./scripts/03_osd_add.sh /dev/sdb ceph
```

### 04_opennebula_install.sh
Установка OpenNebula из .deb файлов:
- Установка зависимостей
- Создание пользователя oneadmin
- Инициализация базы данных MySQL
- Конфигурация Sunstone (веб-интерфейс)
- Интеграция с Ceph (RBD)
- Создание начального администратора

**Использование:**
```bash
sudo ./scripts/04_opennebula_install.sh [deb_path]
sudo ./scripts/04_opennebula_install.sh ./deb
```

### 05_prometheus_install.sh
Установка Prometheus:
- Скачивание и установка Prometheus
- Создание конфигурации с целевыми узлами
- Добавление правил алертинга
- Создание systemd сервиса
- Конфигурация брандмауэра
- Включение Blackbox Exporter

**Использование:**
```bash
sudo ./scripts/05_prometheus_install.sh
```

### 06_grafana_install.sh
Установка Grafana:
- Добавление репозитория Grafana
- Установка пакета
- Конфигурация параметров безопасности
- Добавление Prometheus как источника данных
- Конфигурация SSL/TLS
- Создание provisioning конфигурации

**Использование:**
```bash
sudo ./scripts/06_grafana_install.sh
```

### ceph_manage.sh
Утилита для управления Ceph:

**Доступные команды:**
- `status` - Общий статус кластера
- `health` - Детальное состояние здоровья
- `pools` - Список пулов и использование
- `osds` - Статус OSD дисков
- `mons` - Информация о Monitor узлах
- `rgw` - Статус RADOS Gateway
- `backup` - Резервная копия конфигурации
- `restore [file]` - Восстановление из резервной копии
- `benchmark` - Тест производительности

**Использование:**
```bash
sudo ./scripts/ceph_manage.sh status
sudo ./scripts/ceph_manage.sh backup
```

### health_check.sh
Проверка здоровья кластера:
- Статус Monitor узлов
- Статус OSD дисков
- Состояние Placement Groups
- Использование хранилища
- Целостность данных
- Статус процессов
- Обнаружение проблем

**Использование:**
```bash
sudo ./scripts/health_check.sh
```

## ⚙️ Конфигурация

### .deployment.conf

Основной конфигурационный файл развёртывания. Основные параметры:

```bash
# Информация о кластере
CLUSTER_NAME="ceph"
MONITOR_NODE="astra-monitor1"
COMPUTE_NODES=("astra-node1" "astra-node2" "astra-node3")

# Сетевая конфигурация
PUBLIC_NETWORK="192.168.1.0/24"
CLUSTER_NETWORK="192.168.2.0/24"

# Хранилище
OSD_DEVICES=("/dev/sdb" "/dev/sdc" "/dev/sdd")
POOL_DEFAULT_SIZE=3

# Компоненты
ENABLE_OPENNEBULA=true
ENABLE_PROMETHEUS=true
ENABLE_GRAFANA=true
```

### ceph.conf

Генерируется автоматически скриптом `02_ceph_deploy.sh`. Основные параметры:

```ini
[global]
fsid = <generated-uuid>
mon_initial_members = astra-monitor1
mon_host = 192.168.1.100
public_network = 192.168.1.0/24
cluster_network = 192.168.2.0/24

[osd]
osd_pool_default_size = 3
osd_pool_default_pg_num = 128
```

## 🔧 Развёртывание

### Режимы развёртывания

```bash
# Полное развёртывание (все компоненты)
sudo ./scripts/deploy.sh all

# Только подготовка окружения
sudo ./scripts/deploy.sh prerequisites

# Только подготовка узлов
sudo ./scripts/deploy.sh nodes

# Только Ceph
sudo ./scripts/deploy.sh ceph

# Только мониторинг (Prometheus + Grafana)
sudo ./scripts/deploy.sh monitoring

# Только OpenNebula
sudo ./scripts/deploy.sh opennebula
```

### Пошаговое развёртывание

```bash
# 1. На каждом узле: подготовка окружения
sudo ./scripts/00_prerequisites.sh

# 2. На каждом узле: подготовка конкретного узла
sudo ./scripts/01_node_prepare.sh astra-monitor1 192.168.1.100

# 3. На astra-monitor1: инициализация Ceph
sudo ./scripts/02_ceph_deploy.sh ceph

# 4. На каждом compute узле: добавление OSD дисков
sudo ./scripts/03_osd_add.sh /dev/sdb ceph
sudo ./scripts/03_osd_add.sh /dev/sdc ceph

# 5. На astra-monitor1: установка OpenNebula
sudo ./scripts/04_opennebula_install.sh ./deb

# 6. На astra-monitor1: установка Prometheus
sudo ./scripts/05_prometheus_install.sh

# 7. На astra-monitor1: установка Grafana
sudo ./scripts/06_grafana_install.sh
```

## 📊 Управление и мониторинг

### Ceph Commands

```bash
# Статус кластера
ceph -s
ceph status

# Статус узлов
ceph osd tree
ceph osd df
ceph node ls

# Информация о пулах
ceph osd pool ls
ceph osd pool stats
ceph df

# Статус Monitor
ceph mon stat
ceph quorum_status

# Детальное здоровье
ceph health detail

# Смотреть события в реальном времени
ceph -w
```

### OpenNebula Commands

```bash
# Переключение на пользователя oneadmin
sudo su - oneadmin

# Статус хостов
onehost list

# Статус виртуальных машин
onevm list

# Информация о Ceph интеграции
onedatastore list
oneimage list
```

### Prometheus

**URL:** `http://astra-monitor1:9090`

- Graph - Исторические графики
- Alerts - Активные оповещения
- Status - Информация о серверах

### Grafana

**URL:** `http://astra-monitor1:3000`

Учётные данные по умолчанию: `admin` / `changeme` (нужно изменить!)

Встроенные дашборды:
- Ceph Cluster Health
- Node System Metrics
- Storage Performance
- OpenNebula Resources

## 🔍 Диагностика

### Проверка здоровья кластера

```bash
# Полная диагностика
sudo ./scripts/health_check.sh

# Используя встроенные команды
ceph health detail
ceph osd dump
ceph mon dump
```

### Часто встречающиеся проблемы

**1. OSD в режиме "down":**
```bash
# Перезагрузить OSD
sudo systemctl restart ceph-osd@<osd-id>

# Проверить дисковое пространство
df -h
```

**2. PG в режиме "degraded":**
```bash
# Проверить статус восстановления
ceph pg stat
ceph -w
```

**3. Monitor недоступен:**
```bash
# Перезагрузить Monitor
sudo systemctl restart ceph-mon@astra-monitor1

# Проверить журналы
sudo journalctl -u ceph-mon@astra-monitor1 -f
```

**4. Отсутствует кластер network:**
```bash
# Проверить сетевые интерфейсы
ip addr show
ip route show

# Пинг между узлами
ping -I 192.168.2.100 192.168.2.101
```

### Просмотр логов

```bash
# Логи скриптов развёртывания
tail -f /var/log/ceph_deployment.log

# Логи Ceph
sudo journalctl -u ceph-\* -f

# Логи OpenNebula
sudo tail -f /var/log/opennebula/oned.log

# Логи Prometheus
sudo journalctl -u prometheus -f

# Логи Grafana
sudo journalctl -u grafana-server -f
```

## 💾 Резервное копирование

### Резервная копия конфигурации Ceph

```bash
# Автоматическое резервное копирование
sudo ./scripts/ceph_manage.sh backup

# Файлы сохраняются в:
/var/backups/ceph-config/

# Ручное резервное копирование
sudo tar czf /var/backups/ceph-full-$(date +%Y%m%d).tar.gz \
    /etc/ceph \
    /var/lib/ceph/bootstrap-*
```

### Восстановление из резервной копии

```bash
# Восстановление конфигурации
sudo ./scripts/ceph_manage.sh restore /var/backups/ceph-config/ceph_config_*.tar.gz

# Перезагрузка сервисов
sudo systemctl restart ceph-\*
```

## 🔒 Безопасность

### Уровень защиты "Орёл"

Скрипты автоматически конфигурируют:

1. **Брандмауэр (UFW)**
   - Запрет входящего трафика по умолчанию
   - Разрешение только необходимых портов

2. **SSH Security**
   - Отключение root login с паролем
   - Использование публичных ключей

3. **SSL/TLS**
   - HTTPS для Grafana и OpenNebula Sunstone
   - Самоподписанные сертификаты по умолчанию

4. **Cephx Authentication**
   - Все клиенты требуют аутентификации
   - Отдельные ключи для разных сервисов

5. **AppArmor/SELinux**
   - Политики безопасности для процессов
   - Ограничение доступа к файлам

### Рекомендации безопасности

```bash
# 1. Изменить пароли администраторов
# Grafana
curl -X PUT http://admin:changeme@localhost:3000/api/admin/users/1/password \
  -H "Content-Type: application/json" \
  -d '{"password": "NEW_PASSWORD"}'

# OpenNebula
sudo su - oneadmin -c "oneuser passwd admin new_password"

# 2. Сгенерировать SSL сертификаты
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/ceph.key -out /etc/ssl/certs/ceph.crt

# 3. Включить аудит
sudo auditctl -w /etc/ceph/ -p wa -k ceph_config_changes

# 4. Настроить firewall правила для ограничения доступа
sudo ufw default deny incoming
sudo ufw allow from 192.168.1.0/24 to any port 6789
```

## 🛠️ Решение проблем

### Скрипты не запускаются

```bash
# Сделать скрипты исполняемыми
chmod +x scripts/*.sh

# Проверить права доступа
ls -la scripts/
```

### Нет доступа к удалённым узлам

```bash
# Проверить SSH
ssh -v astra-node1 "echo OK"

# Установить публичные ключи
ssh-copy-id root@astra-node1
```

### Диск не найден для OSD

```bash
# Списать все диски
lsblk -n -o NAME,SIZE,TYPE

# Проверить текущее использование
mount | grep sdb

# Если диск смонтирован, отмонтировать
sudo umount /dev/sdb*
```

### Prometheus не видит метрики

```bash
# Проверить доступность Node Exporter
curl http://astra-node1:9100/metrics

# Проверить конфигурацию Prometheus
cat /etc/prometheus/prometheus.yml

# Перезагрузить Prometheus
sudo systemctl restart prometheus
```

### Grafana не видит Prometheus

```bash
# Проверить соединение Prometheus из Grafana
curl http://localhost:9090/api/v1/query?query=up

# В Grafana: Configuration -> Data Sources -> Test
```

## 📞 Поддержка и документация

### Официальная документация

- [Ceph Documentation](https://docs.ceph.com/)
- [OpenNebula Documentation](https://docs.opennebula.org/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

### Полезные ресурсы

- [Astra Linux](https://astralinux.ru/)
- [Ceph Community Forum](https://ceph.io/community/)
- [OpenNebula Community](https://opennebula.org/community/)

## 📄 Лицензия

Этот проект является автоматизацией развёртывания открытых компонентов.

---

**Версия:** 1.0  
**Дата обновления:** 2024  
**Совместимость:** Astra Linux 1.7 (Debian 10), kernel 5.15+
