#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POSTGRES_HA="$(cd "$ROOT/../example-sd-repo/postgres-ha" && pwd)"
PATRONI_MASTER="$POSTGRES_HA/patroni-master"

echo "==> Building patroni image..."
cd "$PATRONI_MASTER"
docker build -t patroni .

echo "==> Starting cluster (postgres-ha/docker-compose.yml)..."
cd "$POSTGRES_HA"
docker compose up -d

echo "Waiting 25s for leader election..."
sleep 25

echo "==> Cluster status:"
docker exec demo-patroni1 patronictl list

echo ""
echo "==> Applying SQL schema..."
docker cp "$ROOT/sql/init_schema.sql" demo-haproxy:/tmp/init_schema.sql
docker exec -e PGPASSWORD=postgres demo-haproxy psql -h localhost -p 5000 -U postgres -f /tmp/init_schema.sql

echo ""
echo "Ports:"
echo "  Master (write): localhost:5002  (HAProxy -> :5000)"
echo "  Replicas (read): localhost:5001"
echo "  HAProxy stats:  http://localhost:7001/"
echo "  Grafana:        http://localhost:3000 (admin/admin)"
echo "  Prometheus:     http://localhost:9090"
