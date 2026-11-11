# Домашнее задание: «Микросервисы: принципы»

---

## Задача 1: API Gateway

### Сравнительная таблица решений

| Критерий | NGINX / NGINX Plus | Kong | Traefik | Envoy | AWS API Gateway |
|---|---|---|---|---|---|
| Маршрутизация по конфигу | Да (location / upstream) | Да (routes / services) | Да (динамически, labels) | Да (listeners / routes) | Да (resources / methods) |
| Проверка аутентификации | Да (`auth_request`, JWT-модули; Plus — больше из коробки) | Да (JWT, OAuth2, Key Auth, плагины) | Да (middleware: JWT, basic, OIDC) | Да (ext_authz, JWT filter) | Да (IAM, Cognito, Lambda authorizer) |
| Терминация HTTPS | Да (TLS на входе) | Да | Да | Да | Да (управляется AWS) |
| Сложность эксплуатации | Низкая / средняя | Средняя | Низкая в K8s | Средняя / высокая | Низкая (managed), vendor lock-in |
| Где особенно уместен | Универсальный reverse proxy | API-платформа с плагинами | Kubernetes / Docker | Service mesh (Istio) | Облако AWS |
| Стоимость | Open Source / Plus платный | Open Source / Enterprise | Open Source | Open Source | Pay-as-you-go |

### Выбор: **NGINX**

**Почему:**

1. Закрывает все требования: маршрутизация по конфигу, проверка auth (`auth_request` к сервису `security`), терминация HTTPS.
2. Простая эксплуатация для DevOps: один конфиг, предсказуемое поведение, отличная документация.
3. Хорошо работает в Docker / Kubernetes / bare metal без привязки к облаку.
4. Достаточен для большинства внутренних платформ; при росте требований можно перейти на Kong/Envoy, сохранив тот же паттерн «единой точки входа».

Альтернативы: Kong — если нужна богатая плагинная экосистема «из коробки»; Traefik — если основной runtime — Kubernetes и важна автоконфигурация.

---

## Задача 2: Брокер сообщений

### Сравнительная таблица брокеров

| Критерий | Apache Kafka | RabbitMQ | Apache Pulsar | NATS / JetStream | Amazon SQS |
|---|---|---|---|---|---|
| Кластеризация / надёжность | Да (брокеры + репликация партиций) | Да (кластер, quorum queues) | Да (bookies + brokers) | Да (кластер JetStream) | Да (managed, multi-AZ) |
| Хранение на диске при доставке | Да (лог на диске) | Да (durable queues / messages) | Да | Да (JetStream) | Да |
| Высокая скорость / throughput | Очень высокая | Высокая | Очень высокая | Очень высокая (особенно core NATS) | Высокая, но с лимитами сервиса |
| Форматы сообщений | Любые байты (JSON, Avro, Protobuf…) | Любые байты + типы контента | Любые байты + схема-реестр | Любые байты | Любые (с лимитом размера) |
| Разграничение прав на потоки | Да (ACL на topics) | Да (vhost, user permissions) | Да (namespaces, topics) | Да (accounts / authorization) | Да (IAM policies) |
| Простота эксплуатации | Средняя / сложная (ZooKeeper/KRaft, тюнинг) | Относительно простая | Сложнее (больше компонентов) | Проще Kafka | Самая простая (managed), vendor lock-in |
| Модель | Log / streaming | Очереди / routing | Hybrid (queue + stream) | Pub/Sub + persistence | Очереди |

### Выбор: **RabbitMQ**

**Почему (под требования задания):**

1. **Кластеризация** — из коробки, понятная модель узлов и зеркалирования / quorum queues.
2. **Хранение на диске** — durable queues и persistent messages.
3. **Скорость** — достаточна для типичных микросервисных сценариев (команды, события, задачи); для экстремального streaming лучше Kafka, но ценой сложности.
4. **Форматы** — брокер не навязывает формат: JSON, Protobuf, Avro и др.
5. **Права доступа** — пользователи, vhost’ы, permissions на exchange/queue.
6. **Простота эксплуатации** — ключевой плюс против Kafka/Pulsar: проще поставить, мониторить и объяснять команде; есть веб-UI Management Plugin.

Когда выбрать иначе: **Kafka** — если нужен высокий throughput, долгое хранение лога и replay событий; **SQS** — если всё уже в AWS и не хочется сопровождать брокер самим.

---

## Итог выбора

| Компонент | Решение | Главная причина |
|---|---|---|
| API Gateway | **NGINX** | Закрывает routing + auth + TLS, просто эксплуатировать |
| Брокер сообщений | **RabbitMQ** | Надёжность и ACL при более простой эксплуатации, чем у Kafka |

---

## Задача 3: API Gateway на практике

Каркас сервисов (`security`, `uploader`, MinIO) и `docker-compose` взяты из материалов Нетологии:

https://github.com/netology-code/devkub-homeworks/tree/main/11-microservices-02-principles

Реализация gateway — конфиг `gateway/nginx.conf`.

### Маршруты

| Внешний путь | Auth | Куда |
|---|---|---|
| `POST /token` | нет | `security` → `POST /v1/token` |
| `POST /register` | нет | `security` → `POST /v1/user` |
| `GET /user` | да (`auth_request`) | `security` → `GET /v1/user` |
| `POST /upload` | да (`auth_request`) | `uploader` → `POST /v1/upload` |
| `GET /images/{file}` | нет* | MinIO → `/data/{file}` |

\*В условии задания для картинок указана проверка токена, но в проверочных `curl` из readme Нетологии `Authorization` не передаётся, бакет открыт политикой `download` — поэтому `/images/` отдаётся без `auth_request`.

Проверка токена: внутренний `location = /_auth` ходит в `GET /v1/token/validation` сервиса `security`. Nginx `auth_request` пропускает основной запрос только при ответе 2xx.

### Запуск

```bash
docker compose up --build
```

### Проверка

```bash
# логин → JWT
curl -X POST -H 'Content-Type: application/json' \
  -d '{"login":"bob","password":"qwe123"}' \
  http://localhost/token

# загрузка (подставить токен из ответа выше)
curl -X POST \
  -H 'Authorization: Bearer <TOKEN>' \
  -H 'Content-Type: octet/stream' \
  --data-binary @1.jpg \
  http://localhost/upload
# → {"filename":"<uuid>.jpg"}

# скачивание
curl -o out.jpg http://localhost/images/<uuid>.jpg
```

### Замечание по образам MinIO

Официальные `minio/minio` и `minio/mc` сняты с Docker Hub (source-only). В `docker-compose.yaml` для локального ДЗ используются community-сборки `netvark/minio` и `netvark/mc`. У `security` дополнительно закреплены совместимые версии Jinja2/Werkzeug под старый Flask из каркаса.

---

## Логи (задача 4 из «подходы»)

В этот же `docker-compose` добавлены **Vector + Elasticsearch + Kibana**:

```text
stdout (gateway/security/uploader/storage)
  → Vector (/var/run/docker.sock)
  → Elasticsearch (индекс api-logs)
  → Kibana ← kibana-proxy :8081
```

- UI: http://localhost:8081  
- Логин / пароль: `admin` / `qwerty123456`  
- Конфиг Vector: `logging/vector.toml`  
- Index pattern: `api-logs*` (создаётся автоматически)  
- Dashboard в Kibana: **Dashboard → API Logs**  
- Сырые логи: **Discover** (не Security / Fleet — их можно игнорировать)

## Мониторинг (задача 5 из «подходы»)

Добавлены **Prometheus + Grafana**:

```text
security:/metrics
uploader:/metrics
storage:/minio/v2/metrics/cluster
        ↓ scrape
   Prometheus
        ↓
    Grafana :8082
```

- UI: http://localhost:8082  
- Логин / пароль: `admin` / `qwerty123456`  
- Dashboard: **API: распределение запросов по сервисам**  
- Конфиги: `monitoring/`

### Порты UI

| Сервис | Порт | Учётка |
|---|---|---|
| API Gateway | `:80` | — |
| Kibana (логи) | `:8081` | admin / qwerty123456 |
| Grafana (метрики) | `:8082` | admin / qwerty123456 |

В условии обеих задач указан `:8081`; порты разведены, чтобы стеки работали одновременно.