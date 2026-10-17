#!/usr/bin/env bash
# Аудит конфигурации devops-vm. Запускать на сервере.
# Порог срока сертификата (дней) можно переопределить: CERT_DAYS=400 scripts/audit.sh
set -uo pipefail
PASS=0; FAIL=0
CERT_DAYS="${CERT_DAYS:-30}"
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
check "Порт SSH отличен от 22"             "yes" "$([[ "$(sudo sshd -T | awk '/^port/{print $2}')" != "22" ]] && echo yes || echo no)"
check "MaxAuthTries равно 3"               "3"   "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Политика входящих — deny" "deny"   "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Веб-сервер"
check "Служба nginx активна"                       "active" "$(systemctl is-active nginx)"
sudo nginx -t >/dev/null 2>&1; check "Конфигурация nginx корректна" "0" "$?"
openssl x509 -checkend $((CERT_DAYS * 86400)) -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1
check "Сертификат действителен ещё не менее ${CERT_DAYS} дн." "0" "$?"
check "В каталоге ресурса нет файлов, доступных для записи всем" "0" "$(find /var/www/devops-site -perm -o+w | wc -l | tr -d ' ')"
check "Права закрытого ключа равны 600"            "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
