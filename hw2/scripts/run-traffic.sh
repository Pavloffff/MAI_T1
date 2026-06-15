#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HW2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# pip падает с FileNotFoundError, если текущая cwd удалена или недоступна
cd "$HW2_DIR"

if ! python3 -c "import psycopg2" 2>/dev/null; then
    python3 -m pip install --user psycopg2-binary -q
fi

python3 "$HW2_DIR/traffic-generator.py"
