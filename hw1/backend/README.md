## Применение

```bash
cp hw1/backend/main.go example-sd-repo/demo-app-1/backend/main.go
cd example-sd-repo/demo-app-1
docker compose up -d --build backend
```

## PromQL-примеры

```promql
# p95 латентности INSERT
histogram_quantile(0.95, sum(rate(db_query_duration_seconds_bucket{operation="insert_order"}[1m])) by (le))

# Доля ошибок БД
rate(db_errors_total[1m])

# RPS создания заказов
rate(orders_created_total[1m])
```
