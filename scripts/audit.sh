#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo " [OK]    $desc"; ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

actual_port="$(sudo sshd -T | awk '/^port/{print $2; exit}')"
if [[ "$actual_port" != "22" ]]; then
    check "SSH использует нестандартный порт" "non-22" "non-22"
else
    check "SSH использует нестандартный порт" "non-22" "22"
fi

check "Максимум попыток аутентификации равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

incoming_policy="$(sudo ufw status verbose | grep 'Default:' | sed -E 's/.*Default: ([^ ]+) \(incoming\).*/\1/')"
check "Политика входящего трафика — deny" "deny" "$incoming_policy"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "              %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"

# а) служба nginx активна
nginx_status=$(systemctl is-active nginx)
check "Служба Nginx активна" "active" "$nginx_status"

# б) конфигурация nginx синтаксически корректна
if sudo nginx -t > /dev/null 2>&1; then
    check "Конфигурация Nginx валидна" "success" "success"
else
    check "Конфигурация Nginx валидна" "success" "failed"
fi

# в) сертификат истекает не ранее чем через 30 дней
cert_path="/etc/ssl/certs/devops.crt"
if sudo test -f "$cert_path"; then
    if openssl x509 -in "$cert_path" -noout -checkend 2592000 > /dev/null 2>&1; then
        check "Сертификат действителен более 30 дней" "valid" "valid"
    else
        check "Сертификат действителен более 30 дней" "valid" "expiring_soon_or_expired"
    fi
else
    check "Сертификат существует" "exists" "missing"
fi

# г) права ключа равны 600
key_path="/etc/ssl/private/devops.key"

# Используем sudo для проверки существования, так как /etc/ssl/private недоступен для devops
if sudo test -f "$key_path"; then
    key_perms=$(sudo stat -c '%a' "$key_path")
    check "Права закрытого ключа SSL равны 600" "600" "$key_perms"
else
    check "Закрытый ключ SSL существует" "exists" "missing"
fi

key_path="/etc/ssl/private/devops.key"
if [[ -f "$key_path" ]]; then
    key_perms=$(sudo stat -c '%a' "$key_path")
    check "Права закрытого ключа SSL равны 600" "600" "$key_perms"
else
    check "Закрытый ключ SSL существует" "exists" "missing"
fi

echo "[5] Контейнеризация"

# а) служба docker активна
docker_status=$(systemctl is-active docker)
check "Служба Docker активна" "active" "$docker_status"

# б) контейнер СУБД находится в состоянии healthy
# Имя контейнера app-db-1 соответствует стандартному неймингу docker compose для сервиса db проекта app
db_health=$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo "error")
check "Контейнер БД здоров (healthy)" "healthy" "$db_health"

# в) порты 5000 и 5432 не прослушиваются ни на одном адресе, кроме 127.0.0.1
# Получаем все слушающие TCP сокеты
ss_output=$(ss -tln)

bad_bindings=""
while IFS= read -r line; do
    # Извлекаем локальный адрес (обычно 4-й столбец в ss -tln)
    local_addr=$(echo "$line" | awk '{print $4}')
    
    # Проверяем наличие интересующих нас портов (5000 или 5432)
    if echo "$local_addr" | grep -qE ':(5000|5432)$'; then
        # Если адрес НЕ начинается с 127.0.0.1 или ::1, это нарушение
        if ! echo "$local_addr" | grep -qE '^127\.0\.0\.1:|^::1:'; then
            bad_bindings="$bad_bindings\n$local_addr"
        fi
    fi
done <<< "$ss_output"

if [ -z "$bad_bindings" ]; then
    check "Порты 5000/5432 доступны только локально" "true" "true"
else
    # Выводим плохие привязки в сообщение об ошибке
    clean_bad=$(echo -e "$bad_bindings" | tr '\n' ', ')
    check "Порты 5000/5432 доступны только локально" "true" "false ($clean_bad)"
fi

# г) права файла ~/app/.env равны 600
env_path="$HOME/app/.env"
if [[ -f "$env_path" ]]; then
    env_perms=$(stat -c '%a' "$env_path")
    check "Права файла .env равны 600" "600" "$env_perms"
else
    check "Файл .env существует" "exists" "missing"
fi

echo
echo "Итого: OK=$PASS, FAIL=$FAIL"

if (( FAIL > 0 )); then
    exit 1
fi
exit 0