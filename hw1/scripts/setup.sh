#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEMO_APP="$(cd "$ROOT/../example-sd-repo/demo-app-1" && pwd)"
HW1_BACKEND="$ROOT/backend/main.go"

echo "==> Applying enhanced backend with extra metrics..."
cp "$HW1_BACKEND" "$DEMO_APP/backend/main.go"

echo "==> Copying k6 scripts to demo-app-1..."
K6_DEST="$DEMO_APP/k6/scripts/hw_1"
mkdir -p "$K6_DEST"
cp "$ROOT/k6/scripts/"* "$K6_DEST/"

echo "==> Starting docker compose..."
cd "$DEMO_APP"
docker compose up -d --build

echo ""
echo "Wait 20 seconds for services to start..."
sleep 20

echo "==> Health check..."
curl -s http://localhost:8081/api/users
echo ""
echo ""
echo "Setup complete. Run: ./hw1/scripts/run-load-tests.sh"
