# Конфигурация виртуальной машины devops-vm

Документ описывает конфигурацию учебного сервера. Разделы 1–7 относятся к практической работе № 5, раздел 8 — к практической работе № 6, раздел 9 — к практической работе № 7. Используется как исходные данные для Ansible-роли в практической работе № 11.

## 1. Параметры машины

- Гипервизор: UTM (QEMU 10.0, архитектура ARM), ОС Ubuntu 26.04.1 LTS, имя узла devops-vm.devops.local
- Оперативная память: около 2 ГБ (в гостевой системе доступно 1,6 ГиБ)
- Процессор: 2 ядра
- Диск: 25 ГБ (устройство vda), корневая файловая система на LVM, размер 11 ГБ

## 2. Сетевые интерфейсы

| Интерфейс | Тип адаптера | Адрес | Назначение |
|---|---|---|---|
| enp0s1 | Shared Network (NAT средствами UTM) | 192.168.64.2/24 | выход в Интернет, доступ с хоста |
| enp0s2 | Host Only | 192.168.128.2/24 | изолированная сеть хост — гость |

Адреса назначаются по DHCP и могут измениться. Имя devops.local разрешается на хосте средствами mDNS.

## 3. Правило проброса портов

Проброс портов не используется: доступ с хоста выполняется напрямую по адресу Shared Network (SSH — порт 2222, HTTP/HTTPS — порты 80 и 443).

## 4. Учётные записи

| Имя | Группы | Аутентификация |
|---|---|---|
| devops (uid 1001) | devops, sudo, users | только по SSH-ключу (ed25519), пароль используется для sudo |
| chuviss (uid 1000) | учётная запись установщика | вход по SSH запрещён (AllowUsers devops) |

Открытый ключ хоста находится в /home/devops/.ssh/authorized_keys (права 600, каталог .ssh — 700).

## 5. Служба SSH

Файл конфигурации: /etc/ssh/sshd_config; изменения вынесены в /etc/ssh/sshd_config.d/99-hardening.conf.

| Директива | Значение |
|---|---|
| Port | 2222 |
| PermitRootLogin | no |
| PasswordAuthentication | no |
| PubkeyAuthentication | yes |
| PermitEmptyPasswords | no |
| MaxAuthTries | 3 |
| LoginGraceTime | 30 |
| AllowUsers | devops |
| X11Forwarding | no |
| ClientAliveInterval / ClientAliveCountMax | 300 / 2 |

После изменения конфигурации применять: sudo sshd -t && sudo systemctl reload ssh (с проверкой входа во второй сессии).

## 6. Правила межсетевого экрана

Политики по умолчанию: входящие deny, исходящие allow, маршрутизация disabled. Журналирование: medium.

| Правило | Действие | Комментарий |
|---|---|---|
| 80/tcp | ALLOW IN | HTTP |
| 443/tcp | ALLOW IN | HTTPS |
| 2222/tcp | LIMIT IN | SSH, ограничение частоты соединений |

Правила для IPv4 и IPv6 аналогичны.

## 7. Снимки состояния

| Наименование | Момент создания | Состояние |
|---|---|---|
| 01-clean-install | 09.10.2026 | чистая установка |
| 02-keys-configured | 09.10.2026 | настроен вход по ключу |
| 03-ssh-hardened | 09.10.2026 | усилена конфигурация SSH |
| 04-nginx-https | 17.10.2026 | установлен Nginx, сайт переведён на HTTPS |
| 05-docker-compose | 04.11.2026 | установлен Docker, запущен проект «приложение + СУБД», приложение опубликовано через Nginx |

## 8. Веб-сервер

- Устанавливаемый пакет: nginx (sudo apt install -y nginx), версия 1.28.3.
- Конфигурация ресурса: /etc/nginx/sites-available/devops-site, активируется символической ссылкой в /etc/nginx/sites-enabled/ (стандартный ресурс default отключён удалением ссылки). Два блока server: перенаправление HTTP → HTTPS (return 301) и обслуживание на порту 443 (TLS 1.2 и 1.3). Журналы ресурса: /var/log/nginx/devops-site.access.log и devops-site.error.log (блок перенаправления пишет в общий журнал /var/log/nginx/access.log).
- Каталог ресурса: /var/www/devops-site, владелец devops:devops, права 755 на каталоги и 644 на файлы. Содержимое доставляется командой scripts/deploy.sh (rsync с параметром --chmod=D755,F644).
- Сертификат: /etc/ssl/certs/devops.crt (644, владелец root); закрытый ключ: /etc/ssl/private/devops.key (600, владелец root). Закрытый ключ копировать за пределы /etc/ssl/private и добавлять в репозиторий нельзя.
- Команда формирования сертификата (самоподписанный, срок действия 365 дней, с полем SAN):

  ```
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/devops.key \
    -out /etc/ssl/certs/devops.crt \
    -subj "/CN=devops.local" \
    -addext "subjectAltName=DNS:devops.local"
  ```

- Срок действия сертификата: с 17.10.2026 по 17.10.2027; обновить заранее (команда выше с теми же параметрами, затем sudo nginx -t && sudo systemctl reload nginx).
- Применение конфигурации: только sudo nginx -t && sudo systemctl reload nginx (не restart).
- HSTS не включён: сертификат самоподписанный.
- Доверие на клиенте: сертификат копируется по SSH (scp devops:/etc/ssl/certs/devops.crt ~/devops.crt) и указывается явно (curl --cacert ~/devops.crt).

## 9. Контейнеризация

- Способ установки: Docker Engine из официального репозитория Docker (https://download.docker.com/linux/ubuntu, ветка stable, набор resolute), пакеты docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin. Пакет docker.io из репозитория Ubuntu не используется (перед установкой удаляются docker.io, docker-compose, podman-docker, containerd, runc).
- Подключение репозитория: ключ /etc/apt/keyrings/docker.asc (644), источник /etc/apt/sources.list.d/docker.sources (формат deb822, Signed-By: /etc/apt/keyrings/docker.asc). Ключ загружается до первого apt-get update.
- Версии: Docker Engine 29.9.3 (API 1.56), containerd 2.4.2, runc 1.5.2, Docker Compose v5.7.0. Служба docker включена в автозапуск (systemctl is-enabled docker — enabled).
- Перед установкой проверить системное время (timedatectl): при отставании часов apt отклоняет файлы Release («is not valid yet»). Время синхронизирует служба chrony.
- Участники группы docker: devops (sudo usermod -aG docker devops, затем новая SSH-сессия). Членство в группе docker равнозначно правам root, поэтому в неё включаются только учётные записи с правом sudo.
- Расположение проекта: /home/devops/app (Dockerfile, docker-compose.yml, app.py, requirements.txt, .dockerignore, .env.example). Исходный код хранится в репозитории (каталог app/) и доставляется с хоста командой rsync -avz --delete --exclude=.env app/ devops:app/ (исключение .env обязательно).
- Файл переменных окружения: /home/devops/app/.env, владелец devops:devops, права 600. Создаётся только на сервере из шаблона: cp .env.example .env && chmod 600 .env, пароль POSTGRES_PASSWORD формируется командой openssl rand -hex 16. Файл исключён из репозитория (.gitignore) и из контекста сборки (.dockerignore).
- Образ приложения: devops-app:1.0 (база python:3.12-slim, процесс gunicorn от непривилегированного пользователя app, uid 999). СУБД: postgres:16-alpine (основная версия зафиксирована).
- Запуск и обновление: cd ~/app && docker compose up -d --build; состояние — docker compose ps (у db ожидается healthy). Приложение стартует после успешной проверки pg_isready (depends_on: condition: service_healthy). Политика перезапуска обоих сервисов — unless-stopped.

| Сервис | Контейнер | Публикация порта | Доступ |
|---|---|---|---|
| app | app-app-1 | 127.0.0.1:5000 → 5000/tcp | только с самого сервера (для Nginx) |
| db | app-db-1 | не публикуется (5432/tcp внутри сети) | только из сети app_backend по имени db |

- Сеть проекта: app_backend (bridge); приложение обращается к СУБД по имени db (встроенный DNS Docker, DB_HOST=db).
- Именованные тома: app_db_data → /var/lib/postgresql/data (данные PostgreSQL). Сохраняется при docker compose down; удаляется только командой docker compose down -v — на рабочем сервере не использовать.
- Публикация на 0.0.0.0 (например, -p 5001:5000) обходит UFW: правила DNAT Docker обрабатываются раньше цепочек UFW. Порты контейнеров публикуются только на 127.0.0.1.
- Обратный прокси-сервер: в блок server порта 443 файла /etc/nginx/sites-available/devops-site добавлено расположение (статический ресурс location / сохранён):

  ```
  location /app/ {
      proxy_pass http://127.0.0.1:5000/;
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
  }
  ```

  Завершающий / в proxy_pass заменяет префикс /app/ на /. Применение: sudo nginx -t && sudo systemctl reload nginx. Проверка: curl --cacert ~/devops.crt https://devops.local/app/health → ok.
- Диагностика: 502 Bad Gateway и запись connect() failed (111: Connection refused) while connecting to upstream в /var/log/nginx/devops-site.error.log означают, что контейнер приложения не принимает соединения на 127.0.0.1:5000 (docker compose ps, docker compose logs app).
