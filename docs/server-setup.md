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

## 8. Веб-сервер
*   **Пакет:** `nginx` (установлен из репозитория Ubuntu).
*   **Конфигурация ресурса:** `/etc/nginx/sites-available/devops-site` (симлинк в `/etc/nginx/sites-enabled/`).
*   **Каталог ресурса:** `/var/www/devops-site`, владелец `devops:devops`, права на каталоги `755`, на файлы `644`.
*   **Сертификат:** `/etc/ssl/certs/devops.crt` (права `644`, владелец `root`).
*   **Закрытый ключ:** `/etc/ssl/private/devops.key` (права `600`, владелец `root`).
*   **Команда формирования сертификата:**
    ```bash
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/ssl/private/devops.key \
      -out /etc/ssl/certs/devops.crt \
      -subj "/CN=devops.local" \
      -addext "subjectAltName=DNS:devops.local"
    ```
*   **Срок действия:** 365 дней.

## 9. Контейнеризация
*   **Установка Docker:** Из официального репозитория Docker по инструкции [ссылка], версия `27.x.x` (укажите вашу из `docker version`). Пакет `docker.io` не использовался.
*   **Группа docker:** Учётная запись `devops` добавлена в группу `docker` командой `sudo usermod -aG docker devops`.
*   **Расположение проекта:** `~/app` (доставляется через `rsync` из репозитория).
*   **Файл .env:** Расположен в `~/app/.env`, права `600`, владелец `devops`. Создаётся только на сервере, в репозиторий не добавлен (в `.gitignore` и `.dockerignore`).
*   **Публикуемые порты:**
    *   Приложение: `127.0.0.1:5000` (доступно только локально для Nginx).
    *   СУБД (PostgreSQL): порт не опубликован, доступен только внутри сети `app_backend` по имени `db`.
*   **Именованные тома:** `app_db_data` (хранит данные PostgreSQL в `/var/lib/postgresql/data`).
*   **Обратный прокси-сервер:** В конфигурации Nginx (`/etc/nginx/sites-available/devops-site`) в блоке HTTPS добавлен location:
    ```nginx
    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    ```
