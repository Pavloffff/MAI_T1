# MAI_T1 — System Design (домашние задания)

Репозиторий с решениями HW1 и HW2. Все практические части запускаются на **macOS** и **Linux**.

---

## Требования

| Инструмент | Назначение |
|------------|------------|
| Docker + Docker Compose v2 | Поднятие учебных стендов |
| bash | Скрипты в `hw1/scripts/` и `hw2/scripts/` |
| curl | Health-check, seed данных |
| python3 + pip3 | traffic-generator (HW2) |
| jq (опционально) | Парсинг `patronictl` в failover-тестах HW2; без jq используется python3 |

Перед первым запуском сделайте скрипты исполняемыми:

```bash
chmod +x hw1/scripts/*.sh hw2/scripts/*.sh
```

---

## Структура репозитория

| Путь | Содержание |
|------|------------|
| [`hws/`](hws/) | Тексты заданий (ТЗ) |
| [`hw1/`](hw1/) | HW1: Architectural Kata + нагрузочное тестирование |
| [`hw2/`](hw2/) | HW2: HLD + Patroni PostgreSQL HA |
| [`example-sd-repo/`](example-sd-repo/) | Учебные стенды (`demo-app-1`, `postgres-ha`) |

---

## Порядок проверки

HW1 и HW2 practice используют **одни и те же порты** (Grafana `:3000`, Prometheus `:9090`). Проверяйте **по очереди**: сначала HW1, затем `docker compose down`, потом HW2.

---

## HW1 — Architectural Kata (теория)

**ТЗ:** [`hws/hw1.md`](hws/hw1.md)  
**Решение:** [`hw1/HW_1_KATA_SOLUTION.md`](hw1/HW_1_KATA_SOLUTION.md)

Проверка: открыть отчёт, убедиться в наличии разделов (отсев, scope, ФТ, НФТ, ограничения, расчёт нагрузки). Запуск не требуется.

---

## HW1 — Practice (нагрузочное тестирование)

**ТЗ:** [`hws/hw1_practice.md`](hws/hw1_practice.md)  
**Решение:** [`hw1/HW_1_SOLUTION.md`](hw1/HW_1_SOLUTION.md)

### 1. Поднять стек

Из корня репозитория:

```bash
./hw1/scripts/setup.sh
```

Скрипт патчит backend метриками, копирует k6-сценарии и запускает [`example-sd-repo/demo-app-1`](example-sd-repo/demo-app-1).

### 2. Проверить, что сервисы живы

```bash
curl -s http://localhost:8081/api/users
```

Ожидается JSON (пустой массив `[]` или список пользователей).

| Сервис | URL |
|--------|-----|
| UI (Nginx) | http://localhost:8080 |
| Backend API | http://localhost:8081/api |
| Grafana | http://localhost:3000 (`admin` / `admin`) |
| Prometheus | http://localhost:9090 |

### 3. Запустить нагрузочные тесты

```bash
./hw1/scripts/run-load-tests.sh          # все сценарии
./hw1/scripts/run-load-tests.sh storm    # только «Шторм»
./hw1/scripts/run-load-tests.sh wave     # только «Волна»
./hw1/scripts/run-load-tests.sh custom   # только «Пила»
```

Результаты: summary JSON в [`hw1/results/`](hw1/results/), метрики в Grafana.

### 4. Остановить стенд

```bash
cd example-sd-repo/demo-app-1
docker compose down
cd ../..
```

---

## HW2 — HLD (теория)

**ТЗ:** [`hws/hw2.md`](hws/hw2.md)  
**Решение:** [`hw2/HW_2_HLD_SOLUTION.md`](hw2/HW_2_HLD_SOLUTION.md)

Проверка: открыть отчёт, убедиться в наличии C4-диаграмм (PNG в [`hw2/images/`](hw2/images/)), матрицы БД, MUST/SHOULD компонентов. Запуск не требуется.

---

## HW2 — Practice (Patroni PostgreSQL HA)

**ТЗ:** [`hws/hw2_practice.md`](hws/hw2_practice.md)  
**Решение:** [`hw2/HW_2_PRACTICE_SOLUTION.md`](hw2/HW_2_PRACTICE_SOLUTION.md)

### 1. Поднять кластер

```bash
./hw2/scripts/setup.sh
```

Скрипт собирает образ Patroni, поднимает [`example-sd-repo/postgres-ha`](example-sd-repo/postgres-ha) и применяет SQL-схему.

### 2. Проверить состояние кластера

```bash
docker exec demo-patroni1 patronictl list
```

Ожидается 3 ноды: одна `Leader`, две `Replica`. Также откройте:

- HAProxy stats: http://localhost:7001/
- Grafana: http://localhost:3000 (`admin` / `admin`)

### 3. Запустить генератор нагрузки (отдельный терминал)

```bash
./hw2/scripts/run-traffic.sh
```

Ожидаются логи INSERT/SELECT каждые 1–2 секунды.

### 4. Тесты отказоустойчивости

В третьем терминале (при работающем traffic-generator):

```bash
./hw2/scripts/failover-tests.sh status
./hw2/scripts/failover-tests.sh stop-leader
./hw2/scripts/failover-tests.sh restore
```

Дополнительные сценарии: `stop-replica`, `stop-etcd`, `stop-haproxy`.

### 5. Остановить стенд

```bash
cd example-sd-repo/postgres-ha
docker compose down
cd ../..
```

---

## Чеклист полной проверки

- [ ] HW1 Kata — отчёт [`hw1/HW_1_KATA_SOLUTION.md`](hw1/HW_1_KATA_SOLUTION.md)
- [ ] HW1 Practice — `setup.sh` → `curl` → `run-load-tests.sh` → Grafana → `docker compose down`
- [ ] HW2 HLD — отчёт [`hw2/HW_2_HLD_SOLUTION.md`](hw2/HW_2_HLD_SOLUTION.md) с диаграммами
- [ ] HW2 Practice — `setup.sh` → `patronictl list` → `run-traffic.sh` → failover-тесты → `docker compose down`
