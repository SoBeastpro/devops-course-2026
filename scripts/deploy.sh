#!/usr/bin/env bash
# Доставка статического сайта на devops-vm
# Использование: scripts/deploy.sh [--dry-run]

set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

# Определяем корень репозитория независимо от текущей директории
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Ошибка: скрипт должен запускаться внутри Git-репозитория." >&2
    exit 1
}

LOCAL_DIR="${REPO_ROOT}/site/"

# Разбираем аргументы
DRY_RUN=false

if [[ "$#" -gt 1 ]]; then
    echo "Использование: $0 [--dry-run]" >&2
    exit 2
fi

if [[ "$#" -eq 1 ]]; then
    if [[ "$1" == "--dry-run" ]]; then
        DRY_RUN=true
    else
        echo "Ошибка: неизвестный аргумент: $1" >&2
        echo "Использование: $0 [--dry-run]" >&2
        exit 2
    fi
fi

# Проверяем наличие главной страницы
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: ${LOCAL_DIR}index.html не найден. Деплой отменён." >&2
    exit 1
fi

# Запрещаем деплой при любых незакоммиченных изменениях
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "Ошибка: есть незакоммиченные изменения. Сначала создайте коммит." >&2
    exit 1
fi

# Проверяем наличие сертификата для проверки HTTPS
if [[ ! -f "$CA_CERT" ]]; then
    echo "Ошибка: сертификат не найден: $CA_CERT" >&2
    exit 1
fi

# Запоминаем коммит, который собираемся развернуть
COMMIT_HASH="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

# План деплоя или реальная синхронизация
RSYNC_OPTIONS=(-avz --delete --chmod=D755,F644)
SSH_OPTIONS="-o BatchMode=yes -o ConnectTimeout=5"

if [[ "$DRY_RUN" == true ]]; then
    RSYNC_OPTIONS+=(--dry-run)
    echo "Режим dry-run: изменения на сервере не выполняются."
fi

echo "Коммит: $COMMIT_HASH"
echo "Источник: $LOCAL_DIR"
echo "Назначение: ${REMOTE}:${REMOTE_DIR}/"

rsync "${RSYNC_OPTIONS[@]}" \
    -e "ssh $SSH_OPTIONS" \
    "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"

# В режиме dry-run не проверяем доступность сайта
if [[ "$DRY_RUN" == true ]]; then
    echo "План синхронизации успешно проверен."
    exit 0
fi

# Проверяем HTTPS без отключения проверки сертификата
if ! curl --cacert "$CA_CERT" --fail --silent --show-error \
    "$SITE_URL" --output /dev/null; then
    echo "Ошибка: сайт недоступен или проверка HTTPS не пройдена." >&2
    exit 1
fi

echo "Деплой успешно завершён. Коммит: $COMMIT_HASH"
exit 0