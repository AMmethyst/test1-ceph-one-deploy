# Структура проекта и краткий справочник

## 📁 Файлы и директории

```
test1-ceph-one-deploy/
│
├── 🚀 БЫСТРЫЙ СТАРТ
│   ├── QUICKSTART.md              ⭐ Начните отсюда!
│   └── README.md                  📚 Полная документация
│
├── 🔧 ОСНОВНЫЕ СКРИПТЫ РАЗВЁРТЫВАНИЯ
│   ├── scripts/
│   │   ├── deploy.sh              🎯 Главный скрипт развёртывания
│   │   ├── 00_prerequisites.sh    📦 Подготовка окружения
│   │   ├── 01_node_prepare.sh     🖥️  Подготовка узлов
│   │   ├── 02_ceph_deploy.sh      🗄️  Инициализация Ceph
│   │   ├── 03_osd_add.sh          💾 Добавление OSD дисков
│   │   ├── 04_opennebula_install.sh  ☁️  Установка OpenNebula
│   │   ├── 05_prometheus_install.sh  📊 Установка Prometheus
│   │   ├── 06_grafana_install.sh     📈 Установка Grafana
│   │   ├── start_services.sh         ▶️  Запуск всех сервисов
│   │   ├── stop_services.sh          ⏹️  Остановка сервисов
│   │   ├── ceph_manage.sh            🛠️  Управление Ceph
│   │   └── health_check.sh           🏥 Проверка здоровья
│
├── ⚙️ КОНФИГУРАЦИОННЫЕ ФАЙЛЫ
│   ├── .deployment.conf           🔧 Основная конфигурация
│   ├── deployment-lab.conf        🧪 Конфиг для лабораторной установки
│   ├── deployment-prod.conf       🏢 Конфиг для production
│   │
│   └── config/
│       ├── ceph.conf              (генерируется автоматически)
│       └── monitoring.conf        (опционально)
│
├── 📊 МОНИТОРИНГ И КОНФИГУРАЦИЯ
│   └── monitoring/
│       ├── prometheus/
│       │   ├── prometheus.yml     (генерируется 05_prometheus_install.sh)
│       │   └── rules/
│       │       └── ceph_alerts.yml
│       ├── grafana/
│       │   ├── dashboards/        (автоматическое provisioning)
│       │   └── provisioning/
│       └── alerts/
│
├── 📦 OPENNEBULA ПАКЕТЫ
│   └── deb/
│       ├── *.deb                  📥 Размещайте OpenNebula .deb файлы здесь
│       └── (заполняется вручную)
│
├── 📚 ДОКУМЕНТАЦИЯ
│   ├── README.md                  📖 Основная документация
│   ├── QUICKSTART.md              🚀 Быстрый старт (30-60 мин)
│   ├── ASTRA_LINUX_NOTES.md       🔒 Специфика Astra Linux "Орёл"
│   ├── TROUBLESHOOTING.md         🆘 Решение проблем
│   └── ARCHITECTURE.md            (при наличии)
│
└── 📝 ЭТОТ ФАЙЛ
    └── INDEX.md                   ← Вы здесь
```

## 🚀 Как начать

### Вариант 1: Самый быстрый (для демонстрации)

```bash
# 1. Прочитайте в течение 5 минут
less QUICKSTART.md

# 2. Скопируйте конфиг для лабораторной установки
cp deployment-lab.conf .deployment.conf

# 3. Поместите OpenNebula .deb файлы
mkdir -p deb
cp /path/to/opennebula/*.deb deb/

# 4. Запустите полное развёртывание
sudo ./scripts/deploy.sh all .deployment.conf

# 5. Дождитесь завершения (20-40 минут)
```

### Вариант 2: Пошаговое (для понимания)

```bash
# Читайте QUICKSTART.md и выполняйте скрипты поэтапно
sudo ./scripts/00_prerequisites.sh
sudo ./scripts/01_node_prepare.sh
sudo ./scripts/02_ceph_deploy.sh
sudo ./scripts/03_osd_add.sh
sudo ./scripts/04_opennebula_install.sh
sudo ./scripts/05_prometheus_install.sh
sudo ./scripts/06_grafana_install.sh
```

### Вариант 3: Production (для боевых систем)

```bash
# 1. Отредактируйте production конфиг
nano deployment-prod.conf
# Адаптируйте IP адреса, диски, параметры безопасности

# 2. Запустите
sudo ./scripts/deploy.sh all deployment-prod.conf

# 3. Следите за процессом
tail -f /var/log/ceph_deployment.log
```

## 📋 Режимы развёртывания

```bash
# Все компоненты
sudo ./scripts/deploy.sh all

# Только подготовка
sudo ./scripts/deploy.sh prerequisites

# Только Ceph
sudo ./scripts/deploy.sh ceph

# Только мониторинг
sudo ./scripts/deploy.sh monitoring

# Только OpenNebula
sudo ./scripts/deploy.sh opennebula

# Только Prometheus
sudo ./scripts/deploy.sh prometheus

# Только Grafana
sudo ./scripts/deploy.sh grafana
```

## 🎯 Проверка статуса

```bash
# Проверить здоровье кластера
sudo ./scripts/health_check.sh

# Управление Ceph
sudo ./scripts/ceph_manage.sh status
sudo ./scripts/ceph_manage.sh pools
sudo ./scripts/ceph_manage.sh osds

# Веб-интерфейсы
# Prometheus: http://astra-monitor1:9090
# Grafana:    http://astra-monitor1:3000
# OpenNebula: https://astra-monitor1:4567
```

## 🔍 Основные команды

### Ceph

```bash
ceph -s                    # Статус кластера
ceph health detail         # Детальное здоровье
ceph osd tree              # Структура OSD
ceph osd df                # Использование дисков
ceph pool ls               # Список пулов
```

### OpenNebula

```bash
sudo su - oneadmin
onehost list               # Хосты
onevm list                 # Виртуальные машины
onedatastore list          # Хранилища
oneimage list              # Образы
```

### Systemd

```bash
# Ceph
sudo systemctl restart ceph-mon@$(hostname)
sudo systemctl restart ceph-osd@\*
sudo systemctl restart ceph-mgr@$(hostname)

# Мониторинг
sudo systemctl restart prometheus
sudo systemctl restart grafana-server

# OpenNebula
sudo systemctl restart opennebula
sudo systemctl restart opennebula-sunstone
```

## 📊 Веб-интерфейсы

### Prometheus (http://astra-monitor1:9090)
- **Graph**: Исторические метрики
- **Alerts**: Активные оповещения
- **Status**: Информация о серверах

### Grafana (http://astra-monitor1:3000)
- **Dashboards**: Визуализация метрик
- **Data Sources**: Подключенные базы (Prometheus)
- **Alerting**: Правила оповещения
- **Учётные данные по умолчанию**: admin / changeme (ИЗМЕНИТЕ!)

### OpenNebula Sunstone (https://astra-monitor1:4567)
- **Dashboard**: Общая статистика
- **Infrastructure**: Хосты, кластеры, сети
- **Virtual**: VMs, образы, сети
- **Admin**: Управление пользователями, VDC

## 🆘 Решение проблем

**Смотрите TROUBLESHOOTING.md для:**
- Ceph проблемы (Monitor down, OSD down, PG issues)
- Сетевые проблемы
- Проблемы хранилища
- Проблемы мониторинга
- Экстренные ситуации

**Специфика Astra Linux смотрите в ASTRA_LINUX_NOTES.md:**
- Ошибка `apt-get upgrade отключена` (РЕШЕНО - это нормально!)
- AppArmor конфигурация
- Брандмауэр UFW
- Уровень защиты "Орёл"

Быстрые решения:
```bash
# 1. Запустите диагностику
sudo ./scripts/health_check.sh

# 2. Проверьте логи
tail -f /var/log/ceph_deployment.log
sudo journalctl -u ceph-\* -f

# 3. Перезагрузите сервисы
sudo ./scripts/stop_services.sh
sudo ./scripts/start_services.sh
```

## 📚 Документация

| Файл | Назначение |
|------|-----------|
| **QUICKSTART.md** | Развёртывание за 30-60 минут |
| **README.md** | Полная документация всех компонентов |
| **ASTRA_LINUX_NOTES.md** | Специфика Astra Linux, уровень "Орёл", решение ошибок |
| **TROUBLESHOOTING.md** | Диагностика и решение проблем |
| **.deployment.conf** | Конфигурация развёртывания |
| **deployment-lab.conf** | Конфиг для тестирования |
| **deployment-prod.conf** | Конфиг для production |

## ✅ Чеклист развёртывания

- [ ] Все ВМ имеют Astra Linux 1.7
- [ ] Сеть настроена между узлами
- [ ] Скрипты сделаны исполняемыми (`chmod +x scripts/*.sh`)
- [ ] OpenNebula .deb файлы размещены в `deb/`
- [ ] Отредактирована конфигурация `.deployment.conf`
- [ ] Запущен главный скрипт: `sudo ./scripts/deploy.sh all`
- [ ] Проверен статус: `sudo ceph -s`
- [ ] Проверены веб-интерфейсы (Prometheus, Grafana)
- [ ] Изменены пароли администраторов
- [ ] Создана резервная копия конфигурации
- [ ] Протестировано создание VM в OpenNebula

## 🔐 Безопасность

После развёртывания ОБЯЗАТЕЛЬНО:

1. **Измените пароли:**
   - Grafana admin (changeme → новый пароль)
   - OpenNebula admin
   - MySQL (если используется)

2. **Включите SSL/TLS** для всех веб-интерфейсов

3. **Настройте брандмауэр** для ограничения доступа

4. **Создайте резервные копии** конфигурации

```bash
# Резервная копия
sudo ./scripts/ceph_manage.sh backup

# Восстановление (если потребуется)
sudo ./scripts/ceph_manage.sh restore /path/to/backup.tar.gz
```

## 📞 Поддержка

- **Документация Ceph**: https://docs.ceph.com/
- **OpenNebula Docs**: https://docs.opennebula.org/
- **Prometheus Docs**: https://prometheus.io/docs/
- **Grafana Docs**: https://grafana.com/docs/
- **Astra Linux**: https://astralinux.ru/

---

**Версия:** 1.0  
**Дата:** 2024  
**Платформа:** Astra Linux 1.7 (Debian 10), kernel 5.15+

**Начните с QUICKSTART.md!** ⭐
