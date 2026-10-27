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
SITE_DIR="/var/www/devops-site"
CERT_FILE="/etc/ssl/certs/devops.crt"
KEY_FILE="/etc/ssl/private/devops.key"
CERT_MIN_DAYS="${CERT_MIN_DAYS:-30}"

check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
check "Конфигурация nginx корректна (nginx -t)" "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
check "Сертификат действует ещё не менее ${CERT_MIN_DAYS} дн." "0" \
    "$(openssl x509 -checkend $((CERT_MIN_DAYS * 86400)) -noout -in "$CERT_FILE" >/dev/null 2>&1; echo $?)"
check "В ${SITE_DIR} нет файлов, доступных для записи всем" "" "$(find "$SITE_DIR" -perm -o+w 2>&1)"
check "Права ключа ${KEY_FILE} равны 600" "600" "$(sudo stat -c '%a' "$KEY_FILE" 2>&1)"

echo
echo "Итого: OK=$PASS, FAIL=$FAIL"

if (( FAIL > 0 )); then
    exit 1
fi
exit 0