#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_APP="$(cd "$SCRIPT_DIR/../../example-sd-repo/demo-app-1" && pwd)"
SCRIPTS_PATH="$SCRIPT_DIR/../k6/scripts"
RESULTS_PATH="$SCRIPT_DIR/../results"
SCENARIO="${1:-all}"

if [[ ! -d "$DEMO_APP" ]]; then
    echo "demo-app-1 not found at $DEMO_APP" >&2
    exit 1
fi

declare -A SCRIPTS=(
    [storm]=storm.js
    [wave]=wave.js
    [custom]=custom-sawtooth.js
)

if [[ "$SCENARIO" != "all" && -z "${SCRIPTS[$SCENARIO]:-}" ]]; then
    echo "Usage: $0 [storm|wave|custom|all]" >&2
    exit 1
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
    K6_EXTRA=(
        --add-host=host.docker.internal:host-gateway
        -e BASE_URL=http://host.docker.internal:8080
        -e API_DIRECT_URL=http://host.docker.internal:8081
        -e K6_PROMETHEUS_RW_SERVER_URL=http://host.docker.internal:9090/api/v1/write
    )
else
    K6_EXTRA=(--network host)
fi

run_k6() {
    local script_name="$1"
    local base_name="${script_name%.js}"
    mkdir -p "$RESULTS_PATH"
    echo ""
    echo "==> Running $script_name ..."
    docker run --rm "${K6_EXTRA[@]}" \
        -v "${SCRIPTS_PATH}:/scripts:ro" \
        -v "${RESULTS_PATH}:/results" \
        -e K6_PROMETHEUS_RW_TREND_STATS='p(95),p(99),min,max' \
        grafana/k6:latest run --summary-export="/results/${base_name}_summary.json" "/scripts/$script_name"
}

echo "==> Seeding test users..."
curl -s -X POST http://localhost:8081/api/users \
    -H "Content-Type: application/json" \
    -d '{"name":"User1","email":"user1@test.local"}' > /dev/null
curl -s -X POST http://localhost:8081/api/users \
    -H "Content-Type: application/json" \
    -d '{"name":"User2","email":"user2@test.local"}' > /dev/null

if [[ "$SCENARIO" == "all" ]]; then
    for script in "${SCRIPTS[@]}"; do
        run_k6 "$script"
    done
else
    run_k6 "${SCRIPTS[$SCENARIO]}"
fi

echo ""
echo "Done. Check Grafana at http://localhost:3000 and results in hw1/results/"
