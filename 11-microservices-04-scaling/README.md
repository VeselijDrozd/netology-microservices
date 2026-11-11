# Домашнее задание: «Микросервисы: масштабирование»

Источник: https://github.com/netology-code/micros-homeworks/blob/main/11-microservices-04-scaling.md

---

## Задача 1: Кластеризация

### Выбор: Kubernetes

Для развёртывания, запуска и управления микросервисами предлагается **Kubernetes** (управляемый облачный кластер — EKS / GKE / AKS — или self-managed).

Альтернативы вроде Docker Swarm или Nomad закрывают часть требований, но хуже стандартизированы в индустрии и слабее по экосистеме автоскейлинга, Ingress и Secrets. Для крупной компании Kubernetes — базовый и ожидаемый выбор.

### Компоненты решения

| Компонент | Назначение |
|---|---|
| **Kubernetes cluster** (control plane + worker nodes) | оркестрация контейнеров |
| **Deployment / StatefulSet / DaemonSet** | запуск и обновление приложений |
| **Service** (ClusterIP / NodePort / LoadBalancer) | обнаружение сервисов и маршрутизация внутри/снаружи |
| **Ingress** (+ Ingress Controller) | HTTP(S)-вход извне, маршрутизация по host/path |
| **HPA** (Horizontal Pod Autoscaler) | автоматическое горизонтальное масштабирование по CPU/RAM/custom metrics |
| **Cluster Autoscaler** (опционально) | добавление/удаление нод под нагрузку |
| **ConfigMap** | конфигурация через переменные среды / файлы |
| **Secret** | чувствительные данные (пароли, ключи); при необходимости — внешний vault (External Secrets) |
| **NetworkPolicy** | явное разделение сетевого доступа |

### Взаимодействие компонентов

```text
Клиент (извне)
    │
    ▼
Ingress / LoadBalancer          ← внешний контур
    │
    ▼
Service (ClusterIP)             ← внутренний DNS: my-svc.ns.svc.cluster.local
    │
    ├─ Pod replica 1
    ├─ Pod replica 2            ← горизонтальное масштабирование (replicas / HPA)
    └─ Pod replica N
         │
         ├─ env из ConfigMap
         └─ env/файлы из Secret
```

Принцип: приложение упаковано в контейнер (образ из Registry). Kubernetes обеспечивает желаемое число реплик, перезапуск при падении, балансировку через Service и автоскейл через HPA. Снаружи система доступна только через Ingress/LB; внутренние сервисы по умолчанию остаются на ClusterIP.

### Соответствие требованиям

| Требование | Как закрывается |
|---|---|
| поддержка контейнеров | Pod запускает container images (Docker/OCI) |
| обнаружение сервисов и маршрутизация | kube-dns / CoreDNS + Service; снаружи — Ingress |
| горизонтальное масштабирование | `replicas` в Deployment; ручное `kubectl scale` |
| автоматическое масштабирование | **HPA** (по метрикам); при росте кластера — Cluster Autoscaler |
| разделение ресурсов снаружи / внутри | Ingress/LoadBalancer vs ClusterIP; NetworkPolicy; отдельные namespaces |
| конфигурация через env + безопасные секреты | ConfigMap → env; Secret → env/volume; опционально Sealed Secrets / External Secrets / Vault |

### Обоснование

Kubernetes закрывает все пункты задания одной согласованной платформой и является стандартом де-факто для микросервисов в крупных компаниях. Он хорошо стыкуется с уже выбранным ранее контуром: GitLab CI собирает образы → Registry → деплой в Kubernetes; логи/метрики (Vector/ELK, Prometheus/Grafana) снимаются с Pod’ов и нод кластера.

---

## Задача 2: Распределённый кеш * (необязательная)

Поднят **Redis Cluster**: **3 шарда × (1 master + 2 replicas)** = **9 узлов** (`--cluster-replicas 2`).

### Схема (из задания)

![Redis Cluster](https://user-images.githubusercontent.com/1122523/114282923-9b16f900-9a4f-11eb-80aa-61ed09725760.png)

### Реализация

Файлы:

- `docker-compose.yaml` — 9 узлов `redis:7.2-alpine` + init-контейнер
- `redis/redis.conf` — `cluster-enabled yes`

Узлы в сети `172.30.0.0/24` с фиксированными IP (`cluster-announce-ip`), порты на хосте: `7001–7009`.

| Шард | Master | Replicas |
|---|---|---|
| 1 (slots 0–5460) | redis-1 (`172.30.0.11`) | 2 replicas |
| 2 (slots 5461–10922) | redis-2 (`172.30.0.12`) | 2 replicas |
| 3 (slots 10923–16383) | redis-3 (`172.30.0.13`) | 2 replicas |

`redis-cluster-init` ждёт PONG от всех узлов и выполняет:

```bash
redis-cli --cluster create ... --cluster-replicas 2 --cluster-yes
```

### Запуск

```bash
cd 11-microservices-04-scaling
docker compose up -d
docker compose logs redis-cluster-init
```

### Проверка

```bash
# состояние кластера
docker compose exec redis-1 redis-cli cluster info
# → cluster_state:ok, cluster_size:3, cluster_known_nodes:9

docker compose exec redis-1 redis-cli cluster nodes

# запись сессии (режим -c — follow redirects между шардами)
docker compose exec redis-1 redis-cli -c set session:user:1 '{"token":"abc"}'
docker compose exec redis-1 redis-cli -c get session:user:1
```

С хоста (если установлен `redis-cli`):

```bash
redis-cli -c -p 7001 cluster info
redis-cli -c -p 7001 set session:user:2 data2
```
