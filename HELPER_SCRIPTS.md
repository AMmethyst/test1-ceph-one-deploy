# Вспомогательные скрипты для Astra Linux 1.7

## 🔧 verify_astra_linux.sh

Проверяет совместимость вашей системы с требованиями проекта.

**Когда использовать:** Перед началом развёртывания

**Команда:**
```bash
sudo ./verify_astra_linux.sh
```

**Что проверяет:**
- ✓ Версия Astra Linux (должна быть 1.7)
- ✓ Версия ядра (должна быть 5.15+)
- ✓ Уровень защиты "Орёл"
- ✓ AppArmor конфигурация
- ✓ UFW Firewall
- ✓ Доступность apt-get upgrade
- ✓ Установленные пакеты
- ✓ Объём памяти (минимум 4GB)
- ✓ Дисковое пространство (минимум 20GB)
- ✓ Интернет соединение
- ✓ SSH сервер

**Пример вывода:**
```
✓ Astra Linux 1.7 обнаружена
✓ Ядро 5.15.0-generic (требуется 5.15+)
✓ Уровень защиты 'Орёл' обнаружен
✓ AppArmor установлен и активен
✓ UFW активен
! apt-get upgrade отключена (это нормально для 'Орла')
✓ Все необходимые пакеты установлены
✓ RAM: 8GB (требуется минимум 4GB)
✓ Дисковое пространство: 50GB (требуется минимум 20GB)
✓ Интернет доступен
✓ SSH сервер запущен

===== СИСТЕМА СОВМЕСТИМА С ASTRA LINUX 1.7 =====

Вы можете начать развёртывание:
  sudo ./scripts/deploy.sh all .deployment.conf
```

## 🔧 fix_apt_upgrade.sh

Помогает решить проблему с отключённой командой `apt-get upgrade`.

**Когда использовать:** Если вы видите ошибку про apt-get upgrade

**Команда:**
```bash
sudo ./fix_apt_upgrade.sh
```

**Что делает:**
1. Проверяет текущее состояние apt-get upgrade
2. Если отключена, предлагает варианты решения:
   - **Способ 1:** Обновить один раз с опцией APT::Get::EnableUpgrade=true
   - **Способ 2:** Добавить постоянную конфигурацию в /etc/apt/apt.conf.d/

**Пример использования:**
```bash
$ sudo fix_apt_upgrade.sh
===== ИСПРАВЛЕНИЕ apt-get upgrade =====

=== Проверка текущего состояния ===
! apt-get upgrade отключена

=== Способ 1: Обновление с опцией APT (рекомендуется) ===
Выполнение: apt-get upgrade с APT::Get::EnableUpgrade=true

(процесс обновления...)

✓ apt-get upgrade выполнен успешно

=== Дополнительные параметры APT ===

Хотите добавить конфигурацию для постоянного включения apt-get upgrade? (y/n): y
Добавление конфигурации...
✓ Конфигурация добавлена

===== ЗАВЕРШЕНО =====
```

## 🚀 Использование вспомогательных скриптов

### Полный цикл подготовки:

```bash
# 1. Навигируйте в директорию проекта
cd /path/to/ceph-deploy

# 2. Сделайте все скрипты исполняемыми
chmod +x scripts/*.sh
chmod +x *.sh

# 3. Проверьте совместимость
sudo ./verify_astra_linux.sh

# 4. Если есть проблемы - исправьте их
sudo ./fix_apt_upgrade.sh

# 5. Запустите развёртывание
sudo ./scripts/deploy.sh all .deployment.conf

# 6. Мониторьте процесс
tail -f /var/log/ceph_deployment.log
```

## 📝 Расширенное использование

### Проверка совместимости с сохранением результатов

```bash
# Сохраните результат проверки
sudo ./verify_astra_linux.sh | tee verify_results.txt

# Отправьте при необходимости в техподдержку
cat verify_results.txt
```

### Диагностика проблем с apt

```bash
# Проверьте детально
sudo apt-get update -v
sudo apt-get upgrade -s

# Если upgrade отключена:
sudo ./fix_apt_upgrade.sh

# Проверьте конфигурацию APT
sudo cat /etc/apt/apt.conf.d/50unattended-upgrades | grep -i upgrade
```

## 🐛 Решение проблем

### verify_astra_linux.sh показывает ошибки

**Ошибка: "Astra Linux 1.7 не обнаружена"**
```bash
# Проверьте версию вручную
lsb_release -a
# Должно быть:
# Distributor ID: Astra Linux
# Release: 1.7
```

**Ошибка: "Ядро 5.15+ не найдено"**
```bash
# Обновите ядро:
sudo apt-get update
sudo apt-get -o APT::Get::EnableUpgrade=true upgrade -y

# Перезагрузитесь:
sudo reboot
```

**Ошибка: "apt-get upgrade отключена"**
```bash
# Это НОРМАЛЬНО для Astra Linux "Орёл"!
# Используйте fix_apt_upgrade.sh:
sudo ./fix_apt_upgrade.sh
```

### fix_apt_upgrade.sh не работает

**Ошибка: "Permission denied"**
```bash
# Сделайте скрипт исполняемым:
chmod +x fix_apt_upgrade.sh
```

**Ошибка при добавлении конфигурации**
```bash
# Проверьте наличие файла:
ls -la /etc/apt/apt.conf.d/50unattended-upgrades

# Если файла нет, создайте его:
sudo touch /etc/apt/apt.conf.d/50unattended-upgrades

# Попробуйте снова:
sudo ./fix_apt_upgrade.sh
```

## 📚 Дополнительная информация

Для подробной информации об Astra Linux и специфике развёртывания читайте:

- **ASTRA_LINUX_NOTES.md** - Полное руководство по Astra Linux
- **APT_UPGRADE_FIX.md** - Решение проблемы с apt-get upgrade
- **QUICKSTART.md** - Быстрый старт развёртывания
- **README.md** - Основная документация

## 🎯 Итог

✓ **verify_astra_linux.sh** - проверьте систему перед началом  
✓ **fix_apt_upgrade.sh** - исправьте проблему с apt если понадобится  
✓ **deploy.sh** - запустите развёртывание  

**Готово!** 🚀
