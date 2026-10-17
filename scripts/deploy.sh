#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=0
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN=1 ;;
    *)         echo "Использование: $0 [--dry-run]" >&2; exit 2 ;;
esac

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: нет файла site/index.html, доставка отменена" >&2
    exit 1
fi
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения, доставка отменена" >&2
    exit 1
fi

# 3. Синхронизация каталога ${LOCAL_DIR} на ${REMOTE}:${REMOTE_DIR}
RSYNC_OPTS=(-avz --delete --chmod=D755,F644 --exclude='.DS_Store'
            -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ ${DRY_RUN} -eq 1 ]]; then
    RSYNC_OPTS+=(--dry-run)
fi
if ! rsync "${RSYNC_OPTS[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"; then
    echo "Ошибка: синхронизация не выполнена" >&2
    exit 1
fi

# 4. При --dry-run — завершение с кодом 0 без проверки доступности
if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "Пробный запуск завершён, сервер не изменён"
    exit 0
fi

# 5. Проверка доступности ${SITE_URL} и завершение с корректным кодом возврата
if ! curl -fsS --max-time 10 --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}"; then
    echo "Ошибка: синхронизация выполнена, но ${SITE_URL} недоступен" >&2
    exit 1
fi
echo "Доставлено: $(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
