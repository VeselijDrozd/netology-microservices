# Домашнее задание: «Микросервисы: подходы»

Источник: https://github.com/netology-code/micros-homeworks/blob/main/11-microservices-03-approaches.md

---

## Задача 1: Обеспечить разработку

### Выбор: GitLab (GitLab.com / self-managed)

Для организации процесса разработки предлагается **GitLab** как единая платформа: хранение кода, CI/CD, секреты, артефакты и контейнерный registry в одном контуре.

GitLab удовлетворяет всем требованиям задания и является полноценной экосистемой. Это обеспечит стандартизацию при организации автоматизации сборки, развёртывания, хранения артефактов и образов — особенно важно в крупной компании с множеством микросервисов и команд.

Альтернативы вроде GitHub + Actions + GHCR или связки Bitbucket + Jenkins + Nexus тоже возможны, но дают больше точек интеграции и сопровождения. GitLab закрывает тот же контур «из коробки».

### Компоненты решения

| Компонент | Назначение |
|---|---|
| **GitLab Projects / Git** | хранение исходного кода, MR, ветвление |
| **GitLab CI/CD** (`.gitlab-ci.yml`) | описание пайплайнов, джобов, правил запуска |
| **GitLab Runners** | агенты, выполняющие сборки и тесты |
| **CI/CD Variables** (masked / protected) | секреты: пароли, токены, ключи |
| **Container Registry** | хранение docker-образов сервисов |
| **Package Registry / Job Artifacts** | пакеты и артефакты сборок |
| **CI/CD templates / `include`** | переиспользуемые шаблоны пайплайнов |

### Соответствие требованиям

| Требование | Как закрывается в GitLab |
|---|---|
| облачная система | GitLab.com (SaaS) или self-managed в облаке компании |
| система контроля версий Git | встроенный Git в каждом проекте |
| репозиторий на каждый сервис | отдельный project/repo на микросервис (group на команду/домен) |
| запуск сборки по событию из VCS | `rules` / `only`/`except`: push, merge request, tag, schedule |
| запуск сборки по кнопке с параметрами | `when: manual`, `workflow:rules`, pipeline inputs / variables при Run pipeline |
| настройки, привязанные к каждой сборке | переменные job/pipeline, `environment`, артефакты и metadata пайплайна |
| шаблоны конфигураций сборок | `include: template/project/remote`, центральные CI-шаблоны в отдельном репо |
| безопасное хранение секретов | CI/CD Variables: masked, protected, environment-scoped; File variables; интеграция с Vault при необходимости |
| несколько конфигураций из одного репозитория | несколько pipeline definitions / jobs с разными `rules`, `workflow`, child pipelines |
| кастомные шаги при сборке | произвольные `script`/`before_script`/`after_script`, свои stages и jobs |
| собственные docker-образы для сборки | `image:` в job — любой образ из Registry или внешнего registry |
| агенты сборки на своих серверах | self-hosted GitLab Runner (shell/docker/kubernetes executor) |
| параллельный запуск сборок | несколько runners / concurrent jobs на runner |
| параллельный запуск тестов | `parallel:` / `parallel:matrix` в jobs, независимые test-jobs в одном stage |

### Взаимодействие компонентов

```text
Разработчик
   │  git push / Merge Request
   ▼
GitLab (репозиторий сервиса)
   │  событие VCS или ручной Run pipeline
   ▼
GitLab CI/CD (`.gitlab-ci.yml` + шаблоны include)
   │  ставит jobs в очередь
   ▼
GitLab Runner(ы)  ──►  docker image для job
   │                    (тесты / build / lint параллельно)
   ▼
Результаты:
  • Container Registry  — образ сервиса
  • Artifacts/Packages  — отчёты, бинарники
  • (опционально) deploy job → стенд/прод
```

Принцип: **один сервис — один репозиторий — свой пайплайн** (часто на общем корпоративном шаблоне). Секреты не хранятся в Git, а подставляются Runner’у из Variables на этапе выполнения. Параллельность достигается несколькими jobs/runners, а не одним монолитным скриптом.

---

## Задача 2: Логи

### Выбор: ELK + Filebeat (+ Kafka)

Для сбора, хранения и анализа логов предлагается стек:

| Компонент | Роль |
|---|---|
| **Filebeat** | агент на хостах: забирает логи приложений из stdout/журналов контейнеров |
| **Kafka** | буфер между агентами и хранилищем — надёжная доставка при пиках и недоступности ES |
| **Logstash** (опционально) | парсинг/обогащение; при необходимости — persistent queue на диске |
| **Elasticsearch** | центральное хранилище и поисковый движок |
| **Kibana** | UI: поиск, фильтры, дашборды, доступ разработчикам, сохранённые поиски |

**Elastic Agent + Fleet** тоже умеют собирать логи (и многое другое: метрики, трейсы, security), но для задачи «только логи из stdout» часто **избыточны**: сложнее в эксплуатации, чем Filebeat. Их имеет смысл рассматривать позже, если нужна единая платформа Elastic на все типы телеметрии.

Минимальный рабочий контур без лишнего: `Filebeat → Kafka → Elasticsearch → Kibana`.  
Logstash добавляем, если нужен сложный парсинг или дополнительная persistent queue.

### Взаимодействие компонентов

```text
микросервисы → пишут логи в stdout
      ↓
Filebeat (на хостах / нодах)  — читает container/journald логи
      ↓
Kafka                         — буфер, ACK, ретеншн
      ↓
Logstash (опционально)        — parse/enrich + persistent queue
      ↓
Elasticsearch                 — индексация и хранение
      ↓
Kibana                        — UI для людей
```

### Соответствие требованиям

| Требование | Как закрывается |
|---|---|
| сбор логов в центральное хранилище со всех хостов | Filebeat на каждом хосте/ноде → единый Elasticsearch |
| минимальные требования к приложениям, сбор из stdout | приложения только пишут в stdout; агент забирает логи контейнеров/хоста без правок кода |
| гарантированная доставка | Filebeat ACK + **Kafka** как надёжный буфер; опционально persistent queue в Logstash |
| поиск и фильтрация по записям | Elasticsearch + Query DSL / KQL в Kibana Discover |
| UI с доступом разработчикам | Kibana: роли, Spaces, отдельные учётки — разработчики ищут логи без доступа на хосты |
| ссылка на сохранённый поиск | Kibana Saved Search / Share URL на Discover — можно отправить коллеге готовую выборку |

### Обоснование

ELK — зрелый и распространённый стек для централизованных логов в микросервисной архитектуре. Filebeat даёт «тонкий» сбор со stdout без нагрузки на приложения. Kafka закрывает требование гарантированной доставки лучше, чем прямая отправка в Elasticsearch: при падении или деградации ES логи не теряются, а копятся в топиках. Kibana закрывает человеческий контур: доступ, поиск и шаринг сохранённых запросов.

---

## Задача 3: Мониторинг

### Выбор: Prometheus + Grafana

Для сбора и анализа состояния хостов и сервисов предлагается стек **Prometheus + Grafana**.

Оба популярных варианта — **Zabbix** и **Prometheus + Grafana** — могут закрыть требования задания. Разница не только в способе сбора: у стеков разная «родные» модель и сильные стороны. Для микросервисной архитектуры предпочтителен Prometheus + Grafana; Zabbix остаётся сильной альтернативой как более монолитное решение «из коробки» для классического инфраструктурного мониторинга.

| | Prometheus + Grafana | Zabbix |
|---|---|---|
| Модель сбора | в основном **pull** (`/metrics`) | чаще **agent** + активные проверки |
| Сильная сторона | микросервисы, app-метрики, PromQL | хосты, железо, триггеры/алерты «из коробки» |
| Агенты/экспортёры | `node_exporter`, cAdvisor и т.п. | Zabbix Agent (тоже нужен на хостах) |
| UI | Grafana: Explore, dashboards | свой UI (+ можно подключить Grafana) |

### Компоненты решения

| Компонент | Роль |
|---|---|
| **Prometheus** | сбор, хранение time-series, язык запросов PromQL |
| **node_exporter** | метрики хоста: CPU, RAM, диск, сеть |
| **cAdvisor** (или метрики контейнерной платформы) | ресурсы по контейнерам/сервисам: CPU, RAM, FS, сеть |
| **`/metrics` приложений** | специфичные метрики сервисов (latency, RPS, ошибки…) |
| **Grafana** | UI: запросы, агрегации, дашборды, доступ командам |

### Взаимодействие компонентов

```text
хосты          → node_exporter :9100/metrics
контейнеры     → cAdvisor / kubelet metrics
сервисы        → /metrics (Prometheus format)

        ▲ scrape (pull)
        │
   Prometheus
        │
        ▼  datasource
     Grafana  → Explore (запросы) + Dashboards (панели)
```

### Соответствие требованиям

| Требование | Как закрывается |
|---|---|
| сбор метрик со всех хостов | Prometheus scrape targets на каждый хост/экспортёр |
| метрики ресурсов хостов (CPU, RAM, HDD, Network) | **node_exporter** |
| метрики ресурсов каждого сервиса (CPU, RAM, HDD, Network) | **cAdvisor** / метрики оркестратора по контейнерам и pod’ам |
| метрики, специфичные для сервиса | эндпоинты `/metrics` приложений (счётчики, гистограммы, gauges) |
| UI: запросы и агрегация | Grafana Explore + PromQL (`rate`, `sum by`, …) |
| UI: настраиваемые панели состояния системы | Grafana Dashboards (готовые и свои панели) |

### Обоснование

В микросервисной среде сервисы естественно отдают метрики в формате Prometheus; Prometheus единообразно собирает host-, container- и app-метрики, Grafana закрывает и ad-hoc анализ, и постоянные дашборды.

**Zabbix** имеет смысл, если приоритет — единый продукт с агентами, шаблонами и алертингом без сборки стека. Для app-метрик микросервисов он обычно менее удобен, чем Prometheus.

---

## Задача 4: Логи * (необязательная)

Практическая реализация добавлена в стек API Gateway:

`../11-microservices-02-principles/`

### Состав

| Сервис | Роль |
|---|---|
| **vector** | читает stdout контейнеров через Docker socket → Elasticsearch |
| **elasticsearch** | центральное хранилище индекса `api-logs` |
| **kibana** | UI поиска по логам |
| **kibana-proxy** | вход на **`:8081`** с basic auth |

Собираются логи сервисов API: `gateway`, `security`, `uploader`, `storage`.

### Запуск

```bash
cd ../11-microservices-02-principles
docker compose up -d --build
```

### Проверка

1. Открыть http://localhost:8081  
   Логин: `admin`  
   Пароль: `qwerty123456`
2. Сгенерировать логи, например:

```bash
curl -X POST -H 'Content-Type: application/json' \
  -d '{"login":"bob","password":"qwe123"}' \
  http://localhost/token
```

3. В Kibana: **Stack Management → Index Patterns → Create**  
   Pattern: `api-logs*`  
   Time field: `timestamp`  
4. **Discover** — должны быть записи от `security` / `gateway` / `uploader`.

Конфиг Vector: `../11-microservices-02-principles/logging/vector.toml`

> В задании для Kibana и Grafana указан один и тот же порт `8081`.  
> Чтобы оба UI работали одновременно, порты разведены: **Kibana → 8081**, **Grafana → 8082**.

---

## Задача 5: Мониторинг * (необязательная)

Практическая реализация в том же compose: `../11-microservices-02-principles/`

### Состав

| Сервис | Роль |
|---|---|
| **prometheus** | scrape метрик `security`, `uploader`, `storage` |
| **grafana** | UI и dashboard распределения запросов (**`:8082`**) |

Targets:

| Job | Endpoint |
|---|---|
| security | `http://security:3000/metrics` |
| uploader | `http://uploader:3000/metrics` |
| storage | `http://storage:9000/minio/v2/metrics/cluster` |

### Запуск

Тот же `docker compose up -d --build` из каталога principles.

### Проверка

1. Открыть http://localhost:8082  
   Логин: `admin`  
   Пароль: `qwerty123456`
2. Dashboard **«API: распределение запросов по сервисам»** (home dashboard) — pie chart + RPS + counters.
3. Сгенерировать нагрузку (`/token`, `/upload`) и обновить графики.

Конфиги: `../11-microservices-02-principles/monitoring/`
