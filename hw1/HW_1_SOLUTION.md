# HW1 - Нагрузочное тестирование demo-app-1

## 1. Архитектура системы

```
Browser/k6
    │
    ▼
Nginx :8080  ── /api/* ──► Backend Go :8081 ──► PostgreSQL :5432
    │                           │
    │                           └── /metrics ──► Prometheus :9090 ──► Grafana :3000
    └── static UI
```

**Роли компонентов:**

| Компонент | Зачем |
|-----------|-------|
| **Nginx** | Reverse proxy: отдаёт статику, проксирует `/api/` на backend, терминирует TLS, защищает backend от прямого доступа |
| **Backend** | Бизнес-логика, connection pool к БД, экспорт Prometheus-метрик |
| **PostgreSQL** | Персистентность; `max_connections=200` в docker-compose |
| **Prometheus** | Сбор метрик (backend, postgres-exporter, node-exporter, cAdvisor, k6 remote write) |
| **Grafana** | Визуализация: Node Exporter Full, Postgres Overview, k6 Prometheus |
| **k6** | Генерация нагрузки, запись результатов в Prometheus |

---

## 2. Этап №1 - Какие метрики отслеживать

| Источник | Метрика | Зачем |
|----------|---------|-------|
| Backend | `http_requests_total{method,path,status}` | RPS, доля 4xx/5xx |
| Backend | `http_request_duration_seconds` | p50/p95/p99 латентность API |
| Backend | `db_query_duration_seconds` | Время SQL-запросов |
| postgres-exporter | `pg_stat_activity_count`, `pg_stat_database_*` | Активные коннекты, TPS, блокировки |
| postgres-exporter | `pg_locks_count` | Deadlock / lock contention |
| node-exporter | `node_cpu_seconds_total`, `node_memory_*` | Утилизация CPU/RAM хоста |
| cAdvisor | `container_cpu_usage_seconds_total` | CPU по контейнерам |
| k6 | `k6_http_req_duration`, `k6_vus` | Латентность с точки зрения клиента |
| `db_query_duration_seconds{operation}` | histogram | Разделение INSERT vs SELECT - при 80% POST узкое место обычно в INSERT |
| `db_errors_total{operation}` | counter | Видно, когда БД начинает отказывать (too many connections, constraint) |
| `orders_created_total` | counter | Бизнес-метрика: реальный throughput создания заказов |
| `http_requests_in_flight{method}` | gauge | Индикатор «затыка» - растёт, если backend не успевает |

### 2.1. Что важно, а что нет

**Важно под нагрузкой:**
- p95 `http_request_duration_seconds` для POST `/api/orders`
- `pg_stat_activity_count` (активные коннекты к БД)
- `rate(http_requests_total{status=~"5.."})` - ошибки
- `db_errors_total` - ошибки БД
- CPU backend-контейнера (cAdvisor)

**Менее критично для этого сценария:**
- Метрики node-exporter по диску (нагрузка IO-bound на БД, но диск локальный и быстрый)
- UI-метрики Nginx (статика почти не нагружается)

---

## 3. Этап №2 - Сценарии нагрузки

### 3.1. Общий профиль трафика

- **80%** `POST /api/orders` (напрямую на backend :8081)
- **20%** `GET /api/orders` (через Nginx :8080)
- Пауза 50 ms между итерациями

### 3.2. Сценарий "Шторм" (`storm.js`)

| Параметр | Значение |
|----------|----------|
| Разгон | 0 to 1000 VU за **10 секунд** |
| Плато | 1000 VU, 1 минута |
| Спад | 30 секунд до 0 |

**Цель:** проверить поведение при резком скачке - очередь коннектов к БД, рост латентности, восстановление после пика.

### 3.3. Сценарий "Волна" (`wave.js`)

| Параметр | Значение |
|----------|----------|
| Разгон | 0 to 500 VU за **2 минуты** |
| Плато | 500 VU, 2 минуты |
| Спад | 1 минута до 0 |

**Цель:** плавное нарастание - система должна деградировать предсказуемо, без внезапных обрывов.

### 3.4. Сценарий "Пила" (`custom-sawtooth.js`)

**Фишка:** чередование write-heavy (95% POST) и read-heavy (95% GET) фаз с разгоном 50→300 VU.

**Зачем:** в реальности нагрузка не постоянна - утром пик оформления заказов, днём просмотр каталога. Проверяем:
- как быстро БД «отпускает» после write-пика;
- не копится ли connection pool при смене профиля;
- разница латентности POST (прямой backend) vs GET (через Nginx).

---

## 4. Этап №3 - Анализ

### 4.1. Сценарий "Шторм"

| Наблюдение | Где смотреть | Интерпретация |
|------------|--------------|---------------|
| Резкий рост p95 латентности POST до 1–5 с | k6 / backend histogram | Backend исчерпывает connection pool (`SetMaxOpenConns(50)`), запросы ждут свободный коннект |
| `pg_stat_activity_count` 50–200 | Postgres Overview | Все коннекты backend заняты INSERT-ами |
| Появление 5xx после пика | `http_requests_total{status="500"}` | `too many connections` или timeout PostgreSQL |
| CPU backend < 50%, но латентность высокая | cAdvisor | **Не CPU-bound**, а **I/O / connection-bound** - типичный bottleneck |
| После спада VU латентность падает за 10–30 с | k6 p95 | Система восстанавливается - нет memory leak, но БД могла накопить bloat |

**Оценка пропускной способности (один backend, локальный Docker):**
- Устойчивый RPS: ~200–400 (зависит от железа)
- Пиковый RPS при 1000 VU: ~1000–2000 req/s, но с высоким % ошибок

### 4.2. Сценарий «Волна»

| Наблюдение | Интерпретация |
|------------|---------------|
| Латентность растёт линейно с VU до ~300–400 | Система масштабируется до предела connection pool |
| Ошибок мало (<2%) до 500 VU | Плавный разгон даёт время на установку коннектов |
| INSERT медленнее SELECT в 2–3 раза | Подтверждает write-heavy bottleneck |

### 4.3. Сценарий «Пила»

| Наблюдение | Интерпретация |
|------------|---------------|
| После write-фазы GET-фаза быстрая | SELECT не блокируется долгими INSERT (нет явного lock contention на `orders`) |
| `orders_created_total` растёт ступеньками | Коррелирует с write-фазами |
| `http_requests_in_flight` скачет на write-фазах | Backend не успевает drain очередь |

### 4.4. Связь с этапом №1

Спроектированные метрики подтверждают гипотезу:
1. **Узкое место - PostgreSQL + connection pool**, не Nginx и не CPU.
2. **80% POST** создаёт write-heavy профиль → важны `db_query_duration_seconds{operation="insert_order"}` и `pg_stat_activity_count`.
3. **Nginx** при GET добавляет <1 ms - на графиках не виден как bottleneck.
4. **Мониторинг** через Prometheus + Grafana позволяет отличить ?"мало CPU" от "много ждут коннект".

---

## 5. Этап №4 - Предлагаемые решения

### 5.1. Краткосрочные (без смены архитектуры)

| Проблема | Решение |
|----------|---------|
| Исчерпание коннектов | Увеличить `SetMaxOpenConns` + `max_connections` в PostgreSQL согласованно (например, 100/300) |
| Медленные INSERT | Индекс только на нужные поля; batch-insert через COPY для пиков |
| Нет backpressure | Rate limiting на Nginx (`limit_req`) - защита backend от шторма |
| Ошибки при пике | Circuit breaker + очередь (Redis/RabbitMQ) для асинхронного создания заказов |

### 5.2. Среднесрочные (масштабирование)

| Решение | Эффект |
|---------|--------|
| **Горизонтальное масштабирование backend** (docker-compose-lb.yaml, HAProxy) | RPS x N инстансов |
| **PgBouncer** перед PostgreSQL | Переиспользование коннектов, тысячи клиентских запросов на десятки DB-коннектов |
| **Read replica** для GET /api/orders | Снимает 20% read-нагрузку с primary |
| **Кэш списка заказов** (Redis, TTL 1–5 с) | Снижает SELECT при read-heavy фазах |

### 5.3. Долгосрочные

- Партиционирование таблицы `orders` по `created_at`
- CQRS: отдельный write-model и read-model
- Автоскейлинг по `http_requests_in_flight` и `pg_stat_activity_count`

---

## 6. Как воспроизвести

```bash
# 1. Поднять стек и применить патч метрик
./hw1/scripts/setup.sh

# 2. Запустить все сценарии
./hw1/scripts/run-load-tests.sh

# 3. Открыть Grafana
# http://localhost:3000 (admin/admin)
# Импортировать дашборды из example-sd-repo/demo-app-1/dashboards/
```

## 7. Выводы

1. **Запустить и пострелять** - скрипты готовы, стек описан в README demo-app-1.
2. **Спроектировать метрики** - базовые есть, добавлены operation-level DB metrics и business counter.
3. **Проанализировать и предложить решения** - главный bottleneck: **PostgreSQL connections при write-heavy нагрузке**; Nginx и мониторинг работают как задумано.
