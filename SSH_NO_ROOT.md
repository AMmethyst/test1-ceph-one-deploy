# 🔐 SSH Доступ без Root пользователя

## Обзор

Все скрипты теперь используют обычного пользователя для SSH подключений вместо root.

**Поддерживаемая конфигурация:**
- ✅ Локальное выполнение от обычного пользователя с `sudo`
- ✅ SSH подключения от обычного пользователя
- ✅ Удалённое выполнение команд с `sudo` через SSH

## 🚀 Быстрая настройка

### Шаг 1: Создайте пользователя на всех узлах

На каждом узле (astra-monitor1, astra-node1/2/3):

```bash
# Создайте пользователя (например: astraadm, ceph-deploy и т.д.)
sudo useradd -m -s /bin/bash astraadm

# Добавьте в группу sudo для доступа без пароля
sudo usermod -aG sudo astraadm

# Отредактируйте sudoers
sudo visudo

# Найдите строку %sudo и убедитесь что там NOPASSWD
# Или добавьте строку в конец файла:
astraadm ALL=(ALL) NOPASSWD: ALL
```

### Шаг 2: Настройте SSH ключи

На управляющем узле (откуда вы запускаете скрипт):

```bash
# Создайте SSH ключ если его нет
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# Скопируйте ключ на все узлы (используйте нужного пользователя)
for node in astra-monitor1 astra-node1 astra-node2 astra-node3; do
    ssh-copy-id -i ~/.ssh/id_rsa.pub astraadm@$node
done

# Проверьте что SSH работает без пароля
ssh astraadm@astra-monitor1 "echo OK"
```

### Шаг 3: Обновите конфигурацию развёртывания

В файле `.deployment.conf` (или вашей конфиге):

```bash
# SSH пользователь (должен быть создан на всех узлах)
SSH_USER="astraadm"

# Узлы для подключения
MONITOR_NODE="astra-monitor1"
COMPUTE_NODES=("astra-node1" "astra-node2" "astra-node3")
```

### Шаг 4: Запустите развёртывание

От обычного пользователя на управляющем узле:

```bash
# Запустите основной скрипт
sudo ./scripts/deploy.sh all .deployment.conf

# Если SSH требует пароль:
# sudo ./scripts/deploy.sh all .deployment.conf
# (введите пароль когда будет запрос)
```

## 🔍 Проверка настройки

### Проверить доступ к sudo без пароля на удалённом узле

```bash
ssh astraadm@astra-node1 "sudo -n true && echo 'sudo OK' || echo 'sudo password required'"
```

### Проверить SSH без пароля

```bash
ssh astraadm@astra-node1 "echo 'SSH OK'"
```

Если запросит пароль - нужно переделать Step 2.

### Проверить что пользователь в группе sudo

```bash
ssh astraadm@astra-node1 "groups | grep sudo"
```

Должен вывести что-то типа: `astraadm sudo`

## 📋 Альтернативные варианты

### Вариант 1: Использовать существующего пользователя

Если у вас уже есть пользователь (например, `astraadm`, `ubuntu`, `debian`):

```bash
# В конфиге используйте:
SSH_USER="astraadm"

# Убедитесь что пользователь в группе sudo и может выполнять sudo без пароля
```

### Вариант 2: Запросить пароль при выполнении

Если вы не хотите использовать NOPASSWD в sudoers:

```bash
# Просто запустите скрипт и вводите пароль когда будет запрос
sudo ./scripts/deploy.sh all .deployment.conf
```

### Вариант 3: SSH с парольной фразой на ключе

Если ваш SSH ключ защищён парольной фразой:

```bash
# Добавьте ключ в ssh-agent перед запуском скрипта
ssh-add ~/.ssh/id_rsa

# Затем запустите скрипт
sudo ./scripts/deploy.sh all .deployment.conf
```

## 🔒 Безопасность

### Минимальные привилегии (рекомендуется)

Вместо `astraadm ALL=(ALL) NOPASSWD: ALL` используйте более узкие разрешения:

```bash
sudo visudo

# Добавьте только необходимые команды:
astraadm ALL=(ALL) NOPASSWD: /usr/bin/bash
astraadm ALL=(ALL) NOPASSWD: /usr/bin/apt-get
astraadm ALL=(ALL) NOPASSWD: /usr/bin/systemctl
astraadm ALL=(ALL) NOPASSWD: /usr/sbin/useradd
astraadm ALL=(ALL) NOPASSWD: /bin/mkdir
astraadm ALL=(ALL) NOPASSWD: /bin/chmod
# И т.д. для всех команд которые использует скрипт
```

### Аудит

Все sudo команды логируются в `/var/log/auth.log` или `/var/log/secure`:

```bash
# Посмотрите логи sudo
sudo tail -f /var/log/auth.log | grep astraadm
```

## ⚠️ Решение проблем

### SSH: "Permission denied (publickey)"
- ✅ Убедитесь что SSH ключ скопирован: `ssh-copy-id ...`
- ✅ Проверьте разрешения на `~/.ssh`: `chmod 700 ~/.ssh`
- ✅ Проверьте разрешения на `~/.ssh/authorized_keys`: `chmod 600 ~/.ssh/authorized_keys`

### SSH: "Connection refused"
- ✅ Проверьте что SSH сервер запущен: `sudo systemctl status ssh`
- ✅ Проверьте IP адреса узлов в конфиге
- ✅ Проверьте брандмауэр: `sudo ufw status`

### "sudo: no password was provided, but a password is required"
- ✅ Убедитесь что NOPASSWD в sudoers для пользователя
- ✅ Используйте `sudo visudo` для редактирования

### "permission denied while trying to connect to Docker daemon"
- ✅ Это может произойти если скрипт пытается использовать Docker
- ✅ Добавьте пользователя в группу docker: `sudo usermod -aG docker ceph-deploy`

---

**Готово!** Теперь ваши скрипты работают без root пользователя. 🚀🔐

---

## 💡 Быстрое изменение SSH пользователя

Если вам нужно изменить пользователя для SSH подключений, отредактируйте конфиг:

```bash
# Отредактируйте конфиг (например .deployment.conf)
nano .deployment.conf

# Найдите строку:
SSH_USER="astraadm"

# Измените на нужного пользователя:
SSH_USER="ubuntu"    # или другой пользователь

# Сохраните (Ctrl+O, Enter, Ctrl+X)
```

Или используйте sed:
```bash
sed -i 's/SSH_USER=".*"/SSH_USER="ubuntu"/g' .deployment.conf
```
