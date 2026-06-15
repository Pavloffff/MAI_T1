# Подготовка Patroni HA-кластера

$Root = Split-Path $PSScriptRoot -Parent
$PostgresHa = Join-Path $Root "..\example-sd-repo\postgres-ha"
$PatroniMaster = Join-Path $PostgresHa "patroni-master"

Write-Host "==> Building patroni image..."
Set-Location $PatroniMaster
docker build -t patroni .

Write-Host "==> Starting cluster (postgres-ha/docker-compose.yml)..."
Set-Location $PostgresHa
docker compose up -d

Write-Host "Waiting 25s for leader election..."
Start-Sleep -Seconds 25

Write-Host "==> Cluster status:"
docker exec demo-patroni1 patronictl list

Write-Host "`n==> Applying SQL schema..."
docker cp (Join-Path $Root "sql\init_schema.sql") demo-haproxy:/tmp/init_schema.sql
docker exec -e PGPASSWORD=postgres demo-haproxy psql -h localhost -p 5000 -U postgres -f /tmp/init_schema.sql

Write-Host "`nPorts:"
Write-Host "  Master (write): localhost:5002  (HAProxy -> :5000)"
Write-Host "  Replicas (read): localhost:5001"
Write-Host "  HAProxy stats:  http://localhost:7001/"
Write-Host "  Grafana:        http://localhost:3000 (admin/admin)"
Write-Host "  Prometheus:     http://localhost:9090"
