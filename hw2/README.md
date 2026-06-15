# Домашнее задание №2

## Подготовил студент группы М8О-106СВ-21 Павлов Иван Дмитриевич


| Файл задания | Содержание | Решение |
|--------------|----------|---------|
| `hws/hw2.md` | HLD: модули, БД, инфраструктура (на базе HW1) | [`HW_2_HLD_SOLUTION.md`](HW_2_HLD_SOLUTION.md) |
| `hws/hw2_practice.md` | Patroni PostgreSQL HA, failover-тесты | [`HW_2_PRACTICE_SOLUTION.md`](HW_2_PRACTICE_SOLUTION.md) |

---

## Структура папки

```
hw2/
├── README.md                      # этот файл
├── HW_2_HLD_SOLUTION.md           # Part 1–3: HLD Ticket to Serve
├── HW_2_PRACTICE_SOLUTION.md      # Patroni HA: отчёт по практике
├── sql/
│   └── init_schema.sql            # DDL owners + events
├── traffic-generator.py           # скрипт-стрелялка (из postgres-ha)
├── scripts/
│   ├── setup.ps1                  # build patroni + docker compose up + SQL
│   ├── run-traffic.ps1            # запуск генератора нагрузки
│   └── failover-tests.ps1         # сценарии отказов
└── results/
    ├── patronictl_output.txt      # вывод patronictl
    └── haproxy_stats.html         # страница статистики HAProxy
```

## Быстрый старт

```powershell
# 1. Поднять кластер
.\hw2\scripts\setup.ps1

# 2. Генератор нагрузки (в отдельном терминале)
.\hw2\scripts\run-traffic.ps1

# 3. Тесты отказоустойчивости
.\hw2\scripts\failover-tests.ps1 -Action stop-leader
.\hw2\scripts\failover-tests.ps1 -Action restore
```

### Порты

| Сервис | URL / Порт |
|--------|------------|
| PostgreSQL Master (write) | `localhost:5002` |
| PostgreSQL Replicas (read) | `localhost:5001` |
| HAProxy stats | http://localhost:7001/ |
| Grafana | http://localhost:3000 (admin/admin) |
| Prometheus | http://localhost:9090 |

### Учётные данные PostgreSQL

- User: `postgres`
- Password: `postgres`
- Database: `postgres`
