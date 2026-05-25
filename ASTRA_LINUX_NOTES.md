# Специфика работы с Astra Linux 1.7

## 🔒 Уровень защиты "Орёл"

Astra Linux 1.7 с уровнем защиты "Орёл" имеет ряд ограничений в целях безопасности. Наши скрипты специально адаптированы для работы с этими ограничениями.

## ⚠️ Ошибка: apt-get upgrade отключена

### Проблема

```
E: 'apt-get upgrade' отключена, поскольку это может привести систему в нерабочее состояние.
```

### Почему это происходит?

На Astra Linux 1.7 с уровнем защиты "Орёл" полное обновление пакетов (`apt-get upgrade`) отключено по умолчанию. Это специальная политика безопасности, которая предотвращает потенциальные проблемы при обновлении системы.

### Решение

**Скрипты автоматически обрабатывают эту ошибку** - она безопасно игнорируется и развёртывание продолжается дальше.

Если вы видите эту ошибку при выполнении:
```bash
sudo ./scripts/deploy.sh all .deployment.conf
```

Это **нормально** и **ожидаемо**. Просто дождитесь завершения скрипта.

### Если вы хотите принудительно обновить пакеты

Используйте опцию APT:

```bash
sudo apt-get -o APT::Get::AutomaticReboot=false -o APT::Get::EnableUpgrade=true upgrade -y
```

Или отредактируйте `/etc/apt/apt.conf.d/50unattended-upgrades`:

```bash
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
# Найдите строку:
# //Unattended-Upgrade::AutoFixInterruptedDpkg "true";
# И раскомментируйте, изменив на:
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
```

## 🔐 Другие особенности Astra Linux "Орёл"

### 1. AppArmor вместо SELinux

Astra Linux использует **AppArmor** для управления доступом:

```bash
# Проверить статус AppArmor
sudo aa-status

# Посмотреть профили
sudo aa-enabled

# Выключить профиль (если нужно)
sudo aa-complain /etc/apparmor.d/usr.bin.ceph-mon
```

### 2. Брандмауэр UFW

Брандмауэр включается автоматически, как часть политики "Орёл":

```bash
# Проверить статус
sudo ufw status

# Если требуется открыть порт
sudo ufw allow 6789/tcp  # Ceph Monitor

# Включить/отключить
sudo ufw enable
sudo ufw disable
```

### 3. Аудит системы

На Astra Linux "Орёл" включён аудит:

```bash
# Просмотр логов аудита
sudo ausearch -m FILE

# Добавить монитор файла
sudo auditctl -w /etc/ceph/ -p wa -k ceph_changes

# Сохранить rules
sudo auditctl -l > /etc/audit/rules.d/custom.rules
```

### 4. Ограничения на запись в некоторые директории

```bash
# Если возникают проблемы с правами доступа
sudo chown -R ceph:ceph /var/lib/ceph
sudo chmod 750 /var/lib/ceph
sudo chmod 750 /etc/ceph
```

## 🐧 Проверка версии Astra Linux

```bash
# Полная информация о системе
lsb_release -a

# Должно быть:
# LSB Version:	:core-4.1-amd64:core-4.1-noarch
# Distributor ID:	Astra Linux
# Release:	1.7
# Codename:	orel

# Версия ядра
uname -r
# Должно быть 5.15.x или выше
```

## 🛡️ Совместимость компонентов с Astra Linux "Орёл"

### Ceph
- ✅ Полностью поддерживается
- Versions: Octopus, Pacific, Quincy
- AppArmor профили автоматически загружаются

### OpenNebula
- ✅ Совместима (из .deb пакетов)
- Требует MySQL/MariaDB
- Работает с AppArmor

### Prometheus
- ✅ Полностью поддерживается
- Node Exporter работает корректно
- AppArmor не мешает

### Grafana
- ✅ Полностью поддерживается
- SSL/TLS работает с самоподписанными сертификатами
- Порт 3000 открывается автоматически

## 🔧 Полезные команды для Astra Linux

### Проверка статуса безопасности

```bash
# AppArmor
sudo systemctl status apparmor

# Firewall
sudo ufw status verbose

# Аудит
sudo systemctl status auditd
journalctl -u auditd -n 20

# Логирование
sudo systemctl status rsyslog
tail -f /var/log/syslog
```

### Исправление проблем с разрешениями

```bash
# Если Ceph не может читать файлы
sudo setfacl -R -m u:ceph:rx /var/lib/ceph
sudo setfacl -R -m u:ceph:rx /etc/ceph

# Проверить ACL
sudo getfacl /var/lib/ceph/mon
```

### Отключение рестриктивных политик (только для тестирования!)

```bash
# ВНИМАНИЕ: Только для отладки, не для production!

# Отключить AppArmor временно
sudo aa-disable /etc/apparmor.d/usr.bin.ceph-mon

# Отключить firewall временно
sudo ufw disable

# Вернуть обратно
sudo aa-enforce /etc/apparmor.d/usr.bin.ceph-mon
sudo ufw enable
```

## 📋 Чек-лист для успешного развёртывания на Astra Linux

- ✅ Установлена Astra Linux 1.7 с уровнем "Орёл"
- ✅ Ядро версии 5.15+
- ✅ Интернет доступ для скачивания пакетов
- ✅ Между узлами настроена сетевая связь (ping друг на друга)
- ✅ На каждом узле отредактированы /etc/hostname и /etc/hosts
- ✅ SSH доступ между узлами настроен (без пароля через ключи)
- ✅ OpenNebula .deb файлы скопированы в папку deb/
- ✅ Скрипты сделаны исполняемыми: `chmod +x scripts/*.sh`
- ✅ Прочитана эта документация о специфике Astra Linux

## 🐛 Логирование ошибок

Все логи записываются в:
```bash
/var/log/ceph_deployment.log
```

Если что-то пошло не так, посмотрите логи:
```bash
sudo tail -f /var/log/ceph_deployment.log
```

## 📞 Получение помощи

Если скрипты работают некорректно на вашей установке Astra Linux:

1. **Собрите информацию:**
```bash
lsb_release -a > /tmp/astra_info.txt
uname -a >> /tmp/astra_info.txt
sudo cat /etc/apt/sources.list >> /tmp/astra_info.txt
sudo aa-status >> /tmp/astra_info.txt
sudo ufw status >> /tmp/astra_info.txt
```

2. **Проверьте логи:**
```bash
tail -n 100 /var/log/ceph_deployment.log > /tmp/deployment.log
sudo journalctl -u ceph-\* -n 50 >> /tmp/ceph_logs.log
```

3. **Запустите диагностику:**
```bash
sudo ./scripts/health_check.sh > /tmp/health_check.log 2>&1
```

4. **Поделитесь информацией:**
   - Прикрепите файлы из `/tmp/` к вашему вопросу
   - Опишите точно, на каком этапе произошла ошибка
   - Укажите версию Astra Linux и ядра

## 🎯 Успешное развёртывание

После успешного развёртывания проверьте:

```bash
# Ceph статус
sudo ceph -s
# Должен показать HEALTH_OK

# OpenNebula
sudo su - oneadmin -c "onehost list"

# Prometheus
curl http://localhost:9090/api/v1/query?query=up

# Grafana
curl http://localhost:3000/api/health
```

---

Всё готово! Начните развёртывание:
```bash
sudo ./scripts/deploy.sh all .deployment.conf
```

И не волнуйтесь о предупреждении про `apt-get upgrade` - это нормально для Astra Linux "Орёл" 🎯
