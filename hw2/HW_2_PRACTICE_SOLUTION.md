# HW2 - Patroni PostgreSQL HA Cluster

---

## 1. Архитектура кластера

```
                    Application (traffic-generator.py)
                              │
                              ▼
                    HAProxy :5002 (write) / :5001 (read)
                     │ REST API health-check
         ┌───────────┼───────────┐
         ▼           ▼           ▼
    patroni1     patroni2     patroni3
    PostgreSQL   PostgreSQL   PostgreSQL
    + Patroni    + Patroni    + Patroni
         │           │           │
         └───────────┼───────────┘
                     ▼
              etcd1 / etcd2 / etcd3
              (DCS, Raft quorum)
```

| Компонент | Роль |
|-----------|------|
| **etcd** | DCS - хранит leader key, конфиг кластера, состояние нод (Raft, нужен кворум 2/3) |
| **Patroni** | На каждой ноде: мониторит PostgreSQL, борется за leader key, управляет failover |
| **PostgreSQL** | Данные; одна нода Leader (read-write), остальные Replica (streaming replication) |
| **HAProxy** | Единая точка входа для приложения; опрашивает Patroni REST API и маршрутизирует на Leader / Replicas |

---

## 2. Запуск кластера

```powershell
# 1. Собрать образ (из patroni-master)
cd example-sd-repo\postgres-ha\patroni-master
docker build -t patroni .

# 2. Поднять кластер (в задании указано hw3 - фактически postgres-ha)
cd ..\ 
docker compose up -d

# Или одной командой:
.\hw2\scripts\setup.ps1
```

---

## 3. `patronictl list` - состав кластера

Фактический вывод после запуска (см. также `results/patronictl_output.txt`):

```
+ Cluster: demo (7651139678570078230) --------+----+-------------+-----+------------+-----+
| Member   | Host       | Role    | State     | TL | Receive LSN | Lag | Replay LSN | Lag |
+----------+------------+---------+-----------+----+-------------+-----+------------+-----+
| patroni1 | 172.19.0.2 | Replica | streaming |  2 |   0/4048BD8 |   0 |  0/4048BD8 |   0 |
| patroni2 | 172.19.0.5 | Leader  | running   |  2 |             |     |            |     |
| patroni3 | 172.19.0.9 | Replica | streaming |  2 |   0/4048BD8 |   0 |  0/4048BD8 |   0 |
+----------+------------+---------+-----------+----+-------------+-----+------------+-----+
```

### Из чего состоит кластер

| Элемент | Описание |
|---------|----------|
| **Cluster: demo** | Имя кластера (`PATRONI_SCOPE=demo`) |
| **Member** | Имя ноды Patroni (patroni1/2/3) |
| **Role** | `Leader` - мастер (принимает записи); `Replica` - реплика |
| **State** | `running` / `streaming` / `stopped` |
| **TL** | Timeline - увеличивается при failover (был 1, стал 2 после переключения) |
| **Lag** | Отставание реплики от лидера (0 = синхронно) |

### Ключи в etcd (`/service/demo/`)

```
/service/demo/config      - конфигурация кластера
/service/demo/leader      - кто сейчас лидер
/service/demo/members/*   - регистрация каждой ноды
/service/demo/status      - общий статус
/service/demo/initialize  - флаг инициализации
```

---

## 4. HAProxy - http://localhost:7001/

HAProxy предоставляет:
- **Порт 5002** (внешний) -> **5000** (внутренний) - только **Leader** (запись)
- **Порт 5001** - балансировка между **Replica** (чтение)

Проверка через psql:

| Порт | `pg_is_in_recovery()` | IP ноды | Назначение |
|------|----------------------|---------|------------|
| 5000 (внутр.) / **5002** (внешн.) | `f` (false) | 172.19.0.5 | **Master** - запись |
| **5001** | `t` (true) | 172.19.0.2 | **Replica** - чтение |

> В тексте задания порты 5001/5002 указаны наоборот относительно docker-compose. Фактическая маппинг из `postgres-ha/docker-compose.yml`: write = **localhost:5002**, read = **localhost:5001**.

На странице статистики HAProxy видны backend'ы `patroni1`, `patroni2`, `patroni3` - Patroni REST API сообщает HAProxy, кто Leader (active UP), кто Replica.

---

## 5. SQL-схема

Скрипт применён на master через HAProxy (`hw2/sql/init_schema.sql`):

- Таблицы `owners`, `events` с FK
- Индексы на `timestamp`, `owner_name`
- 3 владельца, 2 начальных события

Подключение:
- **Master (DBeaver/psql):** `localhost:5002`, user `postgres`, password `postgres`
- **Replica:** `localhost:5001`

---

## 6. Traffic generator

```powershell
pip install psycopg2-binary
.\hw2\scripts\run-traffic.ps1
```

Скрипт подключается к `localhost:5002` с `target_session_attrs=read-write` - PostgreSQL libpq гарантирует подключение к мастеру.

**Поведение:**
- Каждую 1 с - INSERT в `events`
- Каждые 2 с - SELECT последних 3 записей
- При потере соединения (failover) - переподключение

**Наблюдение:** пишется и читается **с мастера** через HAProxy:5002. Чтение с реплики - через порт 5001 (отдельное подключение).

---

## 7. Эксперименты с отказоустойчивостью

### 7.1. Остановка Leader (patroni3)

| Этап | Результат |
|------|-----------|
| До | patroni3 = Leader |
| `docker stop demo-patroni3` | traffic-generator: `CONNECTION LOST (Failover in progress?)` на 10–35 с |
| После ~35 с | patroni2 = новый Leader, TL=2, patroni3 исчез из списка |
| Запись | `INSERT after_failover` - **успешно** |

**Вывод:** приложение **восстанавливается** после failover. Пауза - время выборов нового лидера в etcd + переключение HAProxy.

### 7.2. Остановка Replica (patroni1)

| Результат |
|-----------|
| patroni1 `stopped`, patroni2 остаётся Leader |
| Запись/чтение **продолжают работать** |
| Потеря одной реплики не влияет на доступность записи |

### 7.3. Остановка etcd-ноды (1 из 3)

| Сценарий | Поведение |
|----------|-----------|
| 1 etcd down (кворум 2/3) | Кластер **работает**, failover возможен |
| 2 etcd down (нет кворума) | Patroni **не может** провести выборы лидера - **запись блокируется** при падении текущего лидера |
| 3 etcd down | Полная потеря DCS - автоматический failover невозможен |

### 7.4. Остановка HAProxy

| Результат |
|-----------|
| Приложение **не может** подключиться к БД (единственная точка входа) |
| Сам кластер PostgreSQL **жив** - patronictl показывает Leader |
| **HAProxy - SPOF** в текущей конфигурации |

**Как избежать в продакшене:**
- HAProxy в паре (active/passive) с Keepalived/VRRP - виртуальный IP
- Или managed LB (Yandex ALB / NLB) с health-check на Patroni
- DNS failover между двумя HAProxy
- Минимум 2 независимых пути к БД для критичных сервисов

---

## 8. Grafana

URL: http://localhost:3000 (admin/admin)

Дашборды из `example-sd-repo/postgres-ha/grafana_dashboards/`:
- `first.json` - Postgres performance
- `second.json`, `third.json` - Patroni/etcd метрики

Prometheus scrape: patroni1/2/3:8008, postgres_exporter:9187.

**На что смотреть:**
- Replication lag (должен быть 0)
- Timeline changes при failover
- Количество активных коннектов
- Patroni role per node

---

## 9. Итоговые выводы

1. **Patroni + etcd** убирают SPOF на уровне PostgreSQL - автоматический failover за ~15–40 с.
2. **HAProxy** абстрагирует приложение от смены лидера - не нужно знать IP мастера.
3. **etcd** критичен: без кворума DCS failover невозможен.
4. **HAProxy** в demo - SPOF; в проде нужна его HA-пара.
5. **traffic-generator** с `target_session_attrs=read-write` - правильный паттерн для приложений: всегда писать в мастер, читать - с реплик при необходимости.

---

## 10. Скрипты для воспроизведения

```powershell
.\hw2\scripts\setup.ps1              # build + up + SQL
.\hw2\scripts\run-traffic.ps1        # генератор нагрузки
.\hw2\scripts\failover-tests.ps1 -Action stop-leader
.\hw2\scripts\failover-tests.ps1 -Action restore
```
