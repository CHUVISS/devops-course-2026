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
echo "[5] Контейнеризация"
check "Служба docker активна"                      "active"  "$(systemctl is-active docker)"
check "Контейнер СУБД в состоянии healthy"         "healthy" "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo 'нет контейнера')"
check "Порты 5000 и 5432 только на 127.0.0.1"      "0"       "$(ss -tlnH | awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:/' | wc -l | tr -d ' ')"
check "Права файла ~/app/.env равны 600"           "600"     "$(stat -c '%a' "$HOME/app/.env" 2>/dev/null || echo 'нет файла')"
echo "[6] Контрольная работа № 2"
KR2_DIR="$HOME/kr2"; KR2_PORT=8002
kr2_redis_id="$(docker compose --project-directory "$KR2_DIR" ps -q redis 2>/dev/null)"
check "Контейнер сервиса redis в состоянии healthy" "healthy" "$(docker inspect -f '{{.State.Health.Status}}' "$kr2_redis_id" 2>/dev/null || echo 'нет контейнера')"
check "Порт ${KR2_PORT} опубликован только на 127.0.0.1" "127.0.0.1:${KR2_PORT}" "$(docker compose --project-directory "$KR2_DIR" port app "$KR2_PORT" 2>/dev/null | sort -u | paste -sd' ' -)"
check "Права файла ~/kr2/.env равны 600"            "600" "$(stat -c '%a' "$KR2_DIR/.env" 2>/dev/null || echo 'нет файла')"
openssl x509 -checkend $((30 * 86400)) -noout -in /etc/ssl/certs/kr2.crt >/dev/null 2>&1
check "Сертификат kr2 действителен ещё не менее 30 дн." "0" "$?"
check "Ресурс kr2 активирован в sites-enabled"     "/etc/nginx/sites-available/kr2" "$(readlink -f /etc/nginx/sites-enabled/kr2 2>/dev/null || echo 'нет ссылки')"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
