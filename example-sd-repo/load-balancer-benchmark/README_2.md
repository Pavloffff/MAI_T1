# Load Balancer Benchmark — Local Demo Guide

Сравниваем **HAProxy**, **Nginx** и **Traefik** на локальной машине с помощью Docker и бомбардировщика [Bombardier](https://github.com/codesenberg/bombardier).

## Архитектура

```
Bombardier (клиент)
       │
  ─────┼─────────────────────────────
  │         │              │
:8080     :8081          :8082
Traefik   HAProxy         Nginx
  │         │              │
  └────┬────┘──────────────┘
       │
  ─────┼──────────
  │              │
backend0:3000  backend1:3000
(Node.js Express — симулирует I/O: 10–300 мс)
```

### Node.js бэкенд

Каждый бэкенд циклически чередует два типа задержек:

```
25 "кэш"-запросов    → 10–58 мс   (среднее ≈ 34 мс)
25 "БД"-запросов     → 50–290 мс  (среднее ≈ 170 мс)
Суммарное среднее    ≈ 102 мс
```

Это намеренно симулирует реальный сервис, у которого часть запросов быстрая (кэш), а часть — медленная (IO/база).

---

## Быстрый старт

```bash
# 1. Поднять стек
docker-compose -f docker-compose-dev.yml up -d --build

# 2. Запустить benchmark
bash script.sh

# 3. Сгенерировать графики и отчёт
python3 script.py

# 4. Остановить стек
docker-compose -f docker-compose-dev.yml down
```

Для запуска без открытия окон (headless):

```bash
python3 script.py --no-show
```

---

## Как настроить тест

Все параметры переопределяются через переменные окружения:

```bash
# Показать разницу между LB: убираем backend-задержку, повышаем нагрузку
ENDPOINT=/ CONCURRENCIES="100 500 1000" DURATION=10s bash script.sh

# Более длинный/точный прогон на /io
DURATION=30s bash script.sh

# Только один уровень конкурентности
CONCURRENCIES="500" ENDPOINT=/ bash script.sh
```

### Почему `/` показывает разницу, а `/io` нет?

| Endpoint | Что измеряем | Bottleneck |
|----------|--------------|------------|
| `/io` | корректность балансировки, поведение при насыщении | 2 бэкенда × ~102 мс задержки |
| `/` | **чистый overhead LB** (routing, connection management) | сам балансировщик |

Реальные результаты на Mac с Docker с `/` endpoint:

```
c=100:   HAProxy=44 600 RPS   Nginx=29 474 RPS   Traefik=44 105 RPS
c=500:   HAProxy=25 558 RPS   Nginx=26 691 RPS   Traefik=27 417 RPS
c=1000:  HAProxy=25 865 RPS   Nginx=24 974 RPS   Traefik=20 706 RPS
```

**Вывод**: при высоком concurrency Traefik заметно деградирует (Go runtime + goroutine overhead).
HAProxy стабилен. Nginx при c=100 медленнее из-за ограничения `keepalive 32` в upstream-пуле нашего конфига.

---

## Параметры теста по умолчанию

| Параметр | Значение |
|----------|----------|
| Уровни конкурентности | 10, 50, 100, 200 |
| Длительность теста | 15 секунд на тест |
| Endpoint | `/io` (с симулированной задержкой) |
| HTTP версия | HTTP/1.1 |
| Инструмент | Bombardier (alpine/bombardier) |