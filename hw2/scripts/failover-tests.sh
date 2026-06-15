#!/usr/bin/env bash
# Сценарии отказоустойчивости для ручного тестирования
# Запускайте при работающем traffic-generator.py

set -euo pipefail

ACTION="${1:-status}"

show_status() {
    echo ""
    echo "=== patronictl list ==="
    if ! docker exec demo-patroni1 patronictl list 2>/dev/null; then
        docker exec demo-patroni2 patronictl list
    fi
}

get_leader() {
    local json
    json="$(docker exec demo-patroni1 patronictl list -f json 2>/dev/null || true)"
    if [[ -z "$json" ]]; then
        echo "Failed to get cluster status" >&2
        exit 1
    fi
    if command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -r '.[] | select(.Role=="Leader") | .Member'
    else
        python3 -c '
import json, sys
data = json.load(sys.stdin)
for item in data:
    if item.get("Role") == "Leader":
        print(item["Member"])
        break
' <<< "$json"
    fi
}

case "$ACTION" in
    status)
        show_status
        ;;
    stop-leader)
        leader="$(get_leader)"
        echo "Stopping leader: $leader"
        docker stop "demo-$leader"
        sleep 20
        show_status
        ;;
    stop-replica)
        echo "Stopping replica: patroni1"
        docker stop demo-patroni1
        sleep 5
        show_status
        ;;
    stop-etcd)
        echo "Stopping etcd1 (quorum 2/3 remains)"
        docker stop demo-etcd1
        sleep 5
        show_status
        ;;
    stop-haproxy)
        echo "Stopping HAProxy - apps lose DB endpoint"
        docker stop demo-haproxy
        ;;
    restore)
        docker start demo-patroni1 demo-patroni2 demo-patroni3 demo-etcd1 demo-etcd2 demo-etcd3 demo-haproxy 2>/dev/null || true
        sleep 15
        show_status
        ;;
    *)
        echo "Usage: $0 [status|stop-leader|stop-replica|stop-etcd|stop-haproxy|restore]" >&2
        exit 1
        ;;
esac
