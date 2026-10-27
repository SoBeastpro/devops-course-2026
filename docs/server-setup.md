# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

- Операционная система: Ubuntu Server 26.04.1 LTS.
- Оперативная память, видимая системе: 1,6 GiB; доступно на момент проверки — 1,2 GiB.
- Процессоры: 2.
- Корневой раздел: 12 GiB, занято 5,5 GiB, свободно 5,2 GiB.
- Swap: 2,0 GiB.
- Размер виртуального диска: не указан, требует проверки в настройках VirtualBox.

## 2. Сетевые интерфейсы

- `enp0s3` — сетевой адаптер NAT, IPv4-адрес `10.0.2.15/24`.
- `enp0s8` — сетевой адаптер Host-only, IPv4-адрес `192.168.56.102/24`.
- `lo` — локальный интерфейс `127.0.0.1/8`.

## 3. Правило проброса портов

- Протокол: TCP.
- IP хоста: `127.0.0.1`.
- Порт хоста: `2222`.
- IP гостя: не задан.
- Порт гостя: `2222`.
- Назначение: подключение к SSH виртуальной машины через localhost хостовой системы.

## 4. Учётные записи

- `devops` — рабочая учётная запись, UID 1000, домашний каталог `/home/devops`, оболочка `/bin/bash`.
- Группы пользователя: `devops`, `adm`, `cdrom`, `sudo`, `dip`, `plugdev`, `users`, `lxd`.
- Аутентификация по SSH выполняется с использованием ключа.
- Учётная запись `student` отсутствует.
- Вход по SSH от имени `root` запрещён.

## 5. Служба SSH

- Файл дополнительной конфигурации: `/etc/ssh/sshd_config.d/99-hardening.conf`.
- Порт: `2222`.
- `PermitRootLogin no`.
- `PasswordAuthentication no`.
- `PubkeyAuthentication yes`.
- `PermitEmptyPasswords no`.
- `MaxAuthTries 3`.
- `LoginGraceTime 30`.
- `AllowUsers devops`.
- `X11Forwarding no`.
- `ClientAliveInterval 300`.
- `ClientAliveCountMax 2`.

## 6. Правила межсетевого экрана

- UFW активен.
- Политика по умолчанию для входящего трафика: `deny`.
- Политика по умолчанию для исходящего трафика: `allow`.
- Маршрутизируемый трафик: `disabled`.
- `80/tcp` — `ALLOW IN` (HTTP), IPv4 и IPv6.
- `443/tcp` — `ALLOW IN` (HTTPS), IPv4 и IPv6.
- `2222/tcp` — `LIMIT IN` (SSH), IPv4 и IPv6.
- Журналирование: `medium`.

## 7. Снимки состояния

- `01-clean-install` — исходное состояние после установки ОС.
- `02-keys-configured` — состояние после настройки доступа по SSH-ключу.
- `03-ssh-hardened` — состояние после настройки SSH и межсетевого экрана.
- `04-nginx-https` — состояние после установки Nginx и перевода ресурса на HTTPS.

## 8. Веб-сервер

### 8.1. Пакет и служба

- Пакет: `nginx` из репозитория Ubuntu (`sudo apt install -y nginx`), версия `nginx/1.28.3 (Ubuntu)`.
- Служба `nginx` включена в автозапуск (`enabled`) и активна.
- Главный процесс работает от `root`, рабочие процессы — от `www-data`.
- Правила UFW для портов `80/tcp` и `443/tcp` уже есть (раздел 6); профиль `Nginx Full` не добавляется.
- Изменения конфигурации применяются только командой `sudo nginx -t && sudo systemctl reload nginx`.

### 8.2. Конфигурация ресурса

- Файл конфигурации: `/etc/nginx/sites-available/devops-site`, владелец `root:root`, права `644`.
- Активация: символическая ссылка `/etc/nginx/sites-enabled/devops-site -> /etc/nginx/sites-available/devops-site`.
- Стандартный ресурс отключён: ссылка `/etc/nginx/sites-enabled/default` удалена, файл `/etc/nginx/sites-available/default` сохранён.
- Журналы: `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log`.
- HSTS не используется (сертификат самоподписанный).

Полный текст конфигурации:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    root /var/www/devops-site;
    index index.html;

    ssl_certificate /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

### 8.3. Каталог ресурса

- Каталог: `/var/www/devops-site`, владелец `devops:devops`.
- Права: каталоги `755` (`drwxr-xr-x`), файлы `644` (`-rw-r--r--`). Модель «владелец пишет, веб-сервер читает»: `www-data` читает файлы как «остальные», но не может их изменять.
- Файлов с правом записи для всех быть не должно: `find /var/www/devops-site -perm -o+w` — пустой вывод.
- Содержимое доставляется только сценарием `scripts/deploy.sh` (rsync с `--delete --chmod=D755,F644`), ручные изменения на сервере не допускаются.

Создание каталога:

```bash
sudo mkdir -p /var/www/devops-site
sudo chown -R devops:devops /var/www/devops-site
```

### 8.4. Сертификат TLS

- Сертификат: `/etc/ssl/certs/devops.crt`, владелец `root:root`, права `644`.
- Закрытый ключ: `/etc/ssl/private/devops.key`, владелец `root:root`, права `600`. Ключ за пределы `/etc/ssl/private` не копируется и в репозиторий не добавляется.
- Тип: самоподписанный (`subject` = `issuer` = `CN=devops.local`), RSA 2048, SAN `DNS:devops.local`.
- Срок действия: 365 дней, с 27.10.2026 по 27.10.2027.
- На хостовой системе копия сертификата лежит в `~/devops.crt` (получена через `scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`) и используется как доверенная: `curl --cacert ~/devops.crt`.

Команда формирования:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
sudo chmod 600 /etc/ssl/private/devops.key
```

### 8.5. Проверка

- `sudo nginx -t` — синтаксис корректен.
- `curl -I http://devops.local` — `301`, `Location: https://devops.local/`.
- `curl --cacert ~/devops.crt -I https://devops.local` — `200 OK`.
- `scripts/audit.sh`, раздел `[4] Веб-сервер` — все проверки `[OK]`, код возврата `0`.
