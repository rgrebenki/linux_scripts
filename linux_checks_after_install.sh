#!/bin/bash

#todo закоментировать в /etc/apt/sources.list.d/ceph и enterprise
#todo добавить no-subscription для pve
#todo apt upgrade
#todo https://github.com/Wladimir-N/ispconfig/blob/debian12/ispconfig-debian12.sh#L12-L13 12 и 13 строчка выполняем команды
#todo SLOG и ARC
#todo ssh-key

# Цветовое оформление вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Проверка на права root
if [ "$(id -u)" -ne 0 ]; then
   echo -e "${RED}Этот скрипт должен быть запущен с правами root${NC}" 
   exit 1
fi

# Массив для хранения ошибок/недостатков
declare -a issues
declare -a descriptions

# Функция для проверки и добавления проблемы в список
add_issue() {
  local number=$1
  local description=$2
  local check_command=$3
  
  if eval "$check_command"; then
    issues+=($number)
    descriptions+=("$description")
  fi
}

echo -e "${BLUE}Проверка текущей конфигурации...${NC}"

# Получение текущего региона и часового пояса
current_timezone=$(cat /etc/timezone 2>/dev/null || echo "Не установлен")
current_locale=$(locale | grep LANG | cut -d= -f2 | sed 's/"//g')

# 1. Проверка часового пояса
add_issue 1 "Текущий часовой пояс: $current_timezone" "true"

# 2. Проверка локали
add_issue 2 "Локаль ru_RU.UTF-8 не активирована (Текущая локаль: $current_locale)" "! grep -q 'ru_RU.UTF-8 UTF-8' /etc/locale.gen || grep -q '^# ru_RU.UTF-8 UTF-8' /etc/locale.gen"

# 3. Проверка настроек SSH
add_issue 3 "Настройки SSH требуют обновления (ClientAliveInterval, ClientAliveCountMax, UsePAM)" "! grep -q 'ClientAliveInterval 60' /etc/ssh/sshd_config || ! grep -q 'ClientAliveCountMax 360' /etc/ssh/sshd_config || ! grep -q '^#UsePAM' /etc/ssh/sshd_config"

# 4. Проверка fail2ban
add_issue 4 "fail2ban не установлен" "! dpkg -l | grep -q fail2ban"

# 5. Проверка rsyslog
add_issue 5 "rsyslog не установлен" "! dpkg -l | grep -q rsyslog"

# 6. Проверка конфигурации fail2ban для Proxmox
add_issue 6 "Отсутствует конфигурация fail2ban для Proxmox или файл фильтра" "[ ! -f /etc/fail2ban/jail.local ] || ! grep -q '\[proxmox\]' /etc/fail2ban/jail.local || [ ! -f /etc/fail2ban/filter.d/proxmox.conf ]"

# 7. Проверка установки Proxmox Backup Server
add_issue 7 "Proxmox Backup Server не установлен" "! dpkg -l | grep -q proxmox-backup-server"

# 8. Проверка конфигурации fail2ban для PBS
add_issue 8 "Отсутствует конфигурация fail2ban для PBS или файл фильтра" "[ ! -f /etc/fail2ban/jail.local ] || ! grep -q '\[proxmox-backup-server\]' /etc/fail2ban/jail.local || [ ! -f /etc/fail2ban/filter.d/proxmox-backup-server.conf ]"

# 9. Проверка zfs_arc_max
add_issue 9 "zfs_arc_max не закомментирован" "[ -f /etc/modprobe.d/zfs.conf ] && grep -q '^options zfs zfs_arc_max=' /etc/modprobe.d/zfs.conf"

# 10. Проверка скрипта очистки кэша и его наличия в cron
add_issue 10 "Скрипт очистки кэша отсутствует или не добавлен в cron" "[ ! -f /usr/local/bin/clear_cache ] || ! crontab -l 2>/dev/null | grep -q '/usr/local/bin/clear_cache'"

# 11. Проверка ZFS пула для PBS
add_issue 11 "ZFS раздел rpool/pbs не создан" "! zfs list | grep -q rpool/pbs"

# 12-14. Проверка ZFS настроек для пула PBS
add_issue 12 "ZFS compression не установлен в zle для rpool/pbs" "! zfs get compression rpool/pbs 2>/dev/null | grep -q 'zle'"
add_issue 13 "ZFS recordsize не установлен в 1M для rpool/pbs" "! zfs get recordsize rpool/pbs 2>/dev/null | grep -q '1M'"
add_issue 14 "ZFS quota не установлена для rpool/pbs" "! zfs get quota rpool/pbs 2>/dev/null | grep -q -v 'none'"

# 15. Проверка опций ядра
add_issue 15 "Опция mitigations=off не добавлена" "[ -f /etc/kernel/cmdline ] && ! grep -q 'mitigations=off' /etc/kernel/cmdline"

# Если нет проблем, сообщаем об этом и выходим
if [ ${#issues[@]} -eq 0 ]; then
  echo -e "${GREEN}Система уже полностью настроена. Никаких действий не требуется.${NC}"
  exit 0
fi

# Вывод обнаруженных проблем
echo -e "${YELLOW}Обнаружены следующие проблемы:${NC}"
for i in "${!issues[@]}"; do
  echo -e "${RED}${issues[$i]}. ${descriptions[$i]}${NC}"
done

# Запрос у пользователя, какие проблемы нужно исправить
echo ""
echo -e "${BLUE}Введите номера проблем через пробел, которые нужно исправить.${NC}"
echo -e "${BLUE}Варианты:${NC}"
echo -e "${BLUE}- 'all' для исправления всех проблем${NC}"
echo -e "${BLUE}- числа через пробел (например: 1 3 5) для исправления конкретных проблем${NC}"
echo -e "${BLUE}- числа со знаком минус (например: all -5 -7) для исправления всех проблем кроме указанных${NC}"
read fix_input

# Преобразование ввода в массив
declare -a fix_array
declare -a exclude_array

# Разбираем ввод
for item in $fix_input; do
  if [ "$item" == "all" ]; then
    fix_array=("${issues[@]}")
  elif [[ "$item" == -* ]]; then
    # Добавляем в массив исключений (без минуса)
    exclude_array+=(${item:1})
  else
    fix_array+=($item)
  fi
done

# Если указано "all" и есть исключения, убираем исключения из массива
if [[ " ${fix_input} " == *" all "* ]] && [ ${#exclude_array[@]} -gt 0 ]; then
  # Создаем временный массив
  declare -a temp_array
  
  for item in "${fix_array[@]}"; do
    exclude=0
    for excl in "${exclude_array[@]}"; do
      if [ "$item" == "$excl" ]; then
        exclude=1
        break
      fi
    done
    if [ $exclude -eq 0 ]; then
      temp_array+=($item)
    fi
  done
  
  fix_array=("${temp_array[@]}")
fi

# Функция для проверки, нужно ли исправлять данную проблему
need_fix() {
  local number=$1
  for fix in "${fix_array[@]}"; do
    if [ "$fix" == "$number" ]; then
      return 0
    fi
  done
  return 1
}

# Функция исправления проблем
fix_issues() {
  # 1. Настройка часового пояса
  if need_fix 1; then
    echo -e "${GREEN}Настройка часового пояса...${NC}"
    
    # Вывод информации о текущем часовом поясе
    echo -e "${YELLOW}Текущий часовой пояс: $current_timezone${NC}"
    echo -e "${BLUE}Примеры часовых поясов:${NC}"
    echo -e "Europe/Moscow"
    echo -e "Europe/Kiev"
    echo -e "Europe/Minsk"
    echo -e "${BLUE}Введите идентификатор часового пояса:${NC}"
    read TZ
      
    if [ -z "$TZ" ]; then
      TZ="Europe/Moscow"
      echo -e "${YELLOW}Выбран часовой пояс по умолчанию: Europe/Moscow${NC}" 
    fi
      
    echo $TZ > /etc/timezone
    dpkg-reconfigure --frontend=noninteractive tzdata
    echo -e "${GREEN}Часовой пояс установлен: $TZ${NC}"
  fi

  # 2. Настройка локали
  if need_fix 2; then
    echo -e "${GREEN}Настройка локали...${NC}"
    sed -i 's/# ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen
    update-locale LANG=ru_RU.UTF-8
    echo -e "${GREEN}Локаль установлена: ru_RU.UTF-8${NC}"
  fi

  # 3. Настройка SSH (все настройки SSH в одном блоке)
  if need_fix 3; then
    echo -e "${GREEN}Настройка SSH...${NC}"
    if ! grep -q "ClientAliveInterval 60" /etc/ssh/sshd_config; then
      echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
    fi
    if ! grep -q "ClientAliveCountMax 360" /etc/ssh/sshd_config; then
      echo "ClientAliveCountMax 360" >> /etc/ssh/sshd_config
    fi
    # Комментирование UsePAM
    sed -i 's/^\(UsePAM\s\+\).*/#\1&/' /etc/ssh/sshd_config
    systemctl restart ssh
  fi

  # 4. Установка fail2ban
  if need_fix 4; then
    echo -e "${GREEN}Установка fail2ban...${NC}"
    apt update
    apt install -y fail2ban
  fi

  # 5. Установка rsyslog
  if need_fix 5; then
    echo -e "${GREEN}Установка rsyslog...${NC}"
    apt install -y --no-install-recommends rsyslog
  fi

  # 6. Настройка fail2ban для Proxmox и создание фильтра
  if need_fix 6; then
    echo -e "${GREEN}Настройка fail2ban для Proxmox...${NC}"
    if [ ! -f /etc/fail2ban/jail.local ]; then
      cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    fi
    if ! grep -q "\[proxmox\]" /etc/fail2ban/jail.local; then
      cat << 'EOF' >> /etc/fail2ban/jail.local
[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
backend = systemd
maxretry = 3
findtime = 2d
bantime = 1h
EOF
    fi
    
    echo -e "${GREEN}Создание фильтра для Proxmox...${NC}"
    cat << 'EOF' > /etc/fail2ban/filter.d/proxmox.conf
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
journalmatch = _SYSTEMD_UNIT=pvedaemon.service
EOF
  fi

  # 7. Установка Proxmox Backup Server
  if need_fix 7; then
    echo -e "${GREEN}Установка Proxmox Backup Server...${NC}"
    if ! grep -q "download.proxmox.com/debian/pbs" /etc/apt/sources.list; then
      echo "deb http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription" >> /etc/apt/sources.list
      apt update
    fi
    apt install -y proxmox-backup-server
  fi

  # 8. Настройка fail2ban для PBS и создание фильтра
  if need_fix 8; then
    echo -e "${GREEN}Настройка fail2ban для Proxmox Backup Server...${NC}"
    if [ ! -f /etc/fail2ban/jail.local ]; then
      cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    fi
    if ! grep -q "\[proxmox-backup-server\]" /etc/fail2ban/jail.local; then
      cat << 'EOF' >> /etc/fail2ban/jail.local
[proxmox-backup-server]
enabled = true
port = https,http,8007
filter = proxmox-backup-server
logpath = /var/log/proxmox-backup/api/auth.log
maxretry = 3
findtime = 2d
bantime = 1h
EOF
    fi
    
    echo -e "${GREEN}Создание фильтра для Proxmox Backup Server...${NC}"
    cat << 'EOF' > /etc/fail2ban/filter.d/proxmox-backup-server.conf
[Definition]
failregex = authentication failure; rhost=\[<HOST>\]:\d+ user=.* msg=.*
ignoreregex =
EOF
  fi

  # Перезапуск fail2ban при изменении настроек
  if need_fix 4 || need_fix 6 || need_fix 8; then
    echo -e "${GREEN}Перезапуск fail2ban...${NC}"
    systemctl restart fail2ban
    
    # Проверка статуса fail2ban после перезапуска
    sleep 2
    if ! systemctl is-active --quiet fail2ban; then
      echo -e "${RED}Fail2ban не запустился. Проверяем журнал ошибок...${NC}"
      journalctl -u fail2ban -n 10
      
      if need_fix 5; then  # Если rsyslog был только что установлен
        echo -e "${YELLOW}Для корректной работы fail2ban может потребоваться файл журнала.${NC}"
        echo -e "${YELLOW}Пожалуйста, откройте еще одну консоль и попробуйте войти в систему (пароль не обязан быть правильным, надо просто создать запись о попытке входе), затем вернитесь сюда и нажмите Enter.${NC}"
        read -p "Нажмите Enter после выполнения попытки входа в другой консоли..."
        
        # Еще одна попытка перезапуска после создания файла журнала
        systemctl restart fail2ban
        sleep 2
        if systemctl is-active --quiet fail2ban; then
          echo -e "${GREEN}Теперь fail2ban успешно запущен.${NC}"
        else
          echo -e "${RED}Fail2ban все еще не запускается. Пожалуйста, проверьте конфигурацию вручную.${NC}"
        fi
      fi
    else
      echo -e "${GREEN}Fail2ban успешно перезапущен.${NC}"
    fi
  fi

  # 9. Настройка ZFS arc_max
  if need_fix 9; then
    echo -e "${GREEN}Настройка ZFS arc_max...${NC}"
    if [ -f /etc/modprobe.d/zfs.conf ]; then
      sed -i 's/^options zfs zfs_arc_max=/#options zfs zfs_arc_max=/' /etc/modprobe.d/zfs.conf
    fi
  fi

  # 10. Создание скрипта очистки кэша и добавление в cron
  if need_fix 10; then
    echo -e "${GREEN}Создание скрипта очистки кэша...${NC}"
    cat << 'EOF' > /usr/local/bin/clear_cache
#!/bin/bash
check=$(ps aux | grep -i clear_cache | grep -v grep | wc -l)
if [ "$check" -le "2" ]
then
        echo 4294967298 > /sys/module/zfs/parameters/zfs_arc_sys_free
        if [ $(free -m | awk '{print $4}' | head -2 | tail -1) -le 3072 ]
        then
                sync
                echo 3 > /proc/sys/vm/drop_caches
                echo 'clear cache'
        fi
fi
EOF
    chmod +x /usr/local/bin/clear_cache
    
    # Добавление скрипта в cron
    if ! crontab -l 2>/dev/null | grep -q '/usr/local/bin/clear_cache'; then
      (crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/clear_cache") | crontab -
      echo -e "${GREEN}Скрипт добавлен в crontab${NC}"
    fi
  fi

  # 11. Создание ZFS раздела для PBS
  if need_fix 11; then
    echo -e "${GREEN}Создание ZFS раздела для PBS...${NC}"
    zfs create rpool/pbs
  fi

  # 12. Настройка ZFS compression
  if need_fix 12; then
    echo -e "${GREEN}Настройка ZFS compression=zle для rpool/pbs...${NC}"
    zfs set compression=zle rpool/pbs
  fi

  # 13. Настройка ZFS recordsize
  if need_fix 13; then
    echo -e "${GREEN}Настройка ZFS recordsize=1M для rpool/pbs...${NC}"
    zfs set recordsize=1M rpool/pbs
  fi

  # 14. Настройка ZFS quota
  if need_fix 14; then
    # Получаем размер rpool
    rpool_size=$(zfs list rpool -o available -H | numfmt --to=iec)
    rpool_size_bytes=$(zfs list rpool -o available -H -p)
    
    # Расчет квоты (79% от доступного) и округление вниз до целых гигабайт
    quota_suggested=$((rpool_size_bytes * 79 / 100))
    quota_suggested_gb=$((quota_suggested / 1024 / 1024 / 1024))
    quota_suggested_human="${quota_suggested_gb}G"
    
    echo -e "${BLUE}Рекомендуемый размер quota (79% от доступного в rpool = $rpool_size): $quota_suggested_human${NC}"
    echo -e "${BLUE}Введите размер quota для rpool/pbs (например: 1.3T, 500G и т.д.) или нажмите Enter для использования рекомендуемого значения:${NC}"
    read quota_input
    
    if [ -z "$quota_input" ]; then
      quota_value="$quota_suggested_human"
    else
      quota_value="$quota_input"
    fi
    
    echo -e "${GREEN}Установка ZFS quota=$quota_value для rpool/pbs...${NC}"
    zfs set quota=$quota_value rpool/pbs
  fi

  # 15. Настройка опций ядра
  if need_fix 15; then
    echo -e "${GREEN}Настройка опций ядра...${NC}"
    if [ -f /etc/kernel/cmdline ]; then
      if ! grep -q "mitigations=off" /etc/kernel/cmdline; then
        sed -i 's/$/ mitigations=off/' /etc/kernel/cmdline
      fi
    else
      # Получаем текущую командную строку ядра и добавляем mitigations=off
      current_cmdline=$(cat /proc/cmdline)
      echo "${current_cmdline} mitigations=off" > /etc/kernel/cmdline
    fi

    # Обновление GRUB
    if [ -x /etc/kernel/postinst.d/zz-update-grub ]; then
      /etc/kernel/postinst.d/zz-update-grub
    fi
  fi
}

# Вызов функции исправления
fix_issues

echo -e "${GREEN}Выбранные настройки применены успешно.${NC}"

# Предложение о перезагрузке
if need_fix 1 || need_fix 2 || need_fix 9 || need_fix 15; then
  echo -e "${YELLOW}Некоторые изменения требуют перезагрузки системы.${NC}"
  echo -e "${BLUE}Выполнить перезагрузку сейчас? (y/n)${NC}"
  read answer
  if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    reboot
  fi
fi
