#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- parameters (override via env vars) ----------
# Examples:
#   ENDPOINT=/ CONCURRENCIES="100 500 1000" bash script.sh   # fast endpoint, high conc
#   DURATION=30s bash script.sh                              # longer run
IFS=' ' read -r -a CONCURRENCIES <<< "${CONCURRENCIES:-10 50 100 200}"
DURATION="${DURATION:-15s}"
TIMEOUT="${TIMEOUT:-30s}"
# /io  -> simulates 10-300ms backend delay  (shows LB correctness, NOT raw perf)
# /    -> instant response                  (shows LB raw throughput differences)
ENDPOINT="${ENDPOINT:-/io}"

echo -e "${BOLD}${YELLOW}=== Load Balancer Benchmark: HAProxy vs Nginx vs Traefik ===${NC}"
echo "Endpoint: ${ENDPOINT}   Duration: ${DURATION}   Concurrencies: ${CONCURRENCIES[*]}"
echo ""

# Port order MUST match docker-compose-dev.yml:
#   traefik -> 8080, haproxy -> 8081, nginx -> 8082
TARGETS=("8080" "8081" "8082")
LB_NAMES=("traefik" "haproxy" "nginx")

RESULTS_DIR="results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
# --------------------------------

mkdir -p "$RESULTS_DIR"

# Wait up to 60s for a service to accept HTTP connections
wait_for() {
    local port=$1 name=$2
    printf "  %-10s (:%s) ... " "$name" "$port"
    for _ in $(seq 1 30); do
        curl -sf "http://localhost:$port/" >/dev/null 2>&1 && echo -e "${GREEN}OK${NC}" && return 0
        sleep 2
    done
    echo -e "${RED}TIMEOUT${NC}"; return 1
}

echo -e "${YELLOW}Checking services:${NC}"
all_up=true
for i in "${!TARGETS[@]}"; do
    wait_for "${TARGETS[$i]}" "${LB_NAMES[$i]}" || all_up=false
done

if [ "$all_up" = false ]; then
    echo ""
    echo -e "${RED}One or more services are not reachable.${NC}"
    echo "Start the stack first:"
    echo "  docker-compose -f docker-compose-dev.yml up -d --build"
    exit 1
fi

echo ""

# Print result row — uses python3 if available to parse the JSON in-place
print_result() {
    local file=$1 name=$2 conc=$3
    if [ -f "$file" ] && command -v python3 >/dev/null 2>&1; then
        python3 - "$file" "$name" "$conc" <<'PY'
import json, sys
path, lb, c = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    # Robust load: handles files that may contain progress-bar text before JSON
    raw = open(path).read()
    start = raw.index('{')
    d = json.loads(raw[start:])
    r    = d['result']
    rps  = r['rps']['mean']
    mean = r['latency']['mean'] / 1000        # microseconds -> ms
    p99  = r['latency']['percentiles']['99'] / 1000
    errs = r['others']
    color = '\033[0;31m' if errs > 0 else '\033[0;32m'
    reset = '\033[0m'
    print(f"  {color}{lb:<12}{c:<8}{rps:>10.0f}{mean:>12.1f}{p99:>10.1f}{errs:>8}{reset}")
except Exception as e:
    print(f"  {lb}: parse error – {e}")
PY
    else
        echo "  $name c=$conc -> saved: $file"
    fi
}

# Run a single bombardier test and save JSON
run_test() {
    local port=$1 name=$2 conc=$3
    local out="$RESULTS_DIR/${name}_c${conc}_${TIMESTAMP}.json"

    # tail -1 extracts only the JSON line (bombardier also prints a progress bar to stdout)
    docker run --rm --network=host alpine/bombardier \
        --http1 -c "$conc" -d "$DURATION" -t "$TIMEOUT" -l \
        --format=json \
        "http://localhost:${port}${ENDPOINT}" 2>/dev/null | tail -1 > "$out"

    print_result "$out" "$name" "$conc"
}

# Header for result table
print_header() {
    printf "${BOLD}  %-12s %-8s %10s %12s %10s %8s${NC}\n" \
        "LB" "conc" "RPS" "mean (ms)" "p99 (ms)" "errors"
    printf '  '; printf '%0.s─' {1..60}; echo ""
}

# Main benchmark loop
for conc in "${CONCURRENCIES[@]}"; do
    echo -e "${YELLOW}Concurrency: $conc  (duration: $DURATION)${NC}"
    print_header
    for i in "${!TARGETS[@]}"; do
        run_test "${TARGETS[$i]}" "${LB_NAMES[$i]}" "$conc"
        # short pause so the previous LB drains before next test starts
        sleep 3
    done
    echo ""
done

echo -e "${GREEN}Benchmark complete!${NC}"
echo "  Raw JSON results : $RESULTS_DIR/"
echo "  Charts & report  : python3 script.py"
