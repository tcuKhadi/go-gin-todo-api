#!/usr/bin/env bash
set -euo pipefail

# Usage (server host, manserve):
#   ./scripts/api.sh deploy                build, restart server in release mode, verify
#   ./scripts/api.sh status                server process, Air, log health
#   ./scripts/api.sh stop                  stop Air and the server
#   ./scripts/api.sh logs                  follow the server log
#   ./scripts/api.sh ramp                  hey ramp: 25..800 connections, 20s each, stops on errors
#
# Usage (any machine that can reach the server):
#   ./scripts/api.sh test                  smoke test all endpoints
#   ./scripts/api.sh load [-n N] [-c C]    smoke test, then hey load test (default 1000 requests, 10 concurrent)
#   BASE_URL=http://localhost:3000 ./scripts/api.sh test
#
# Background ramp:
#   ./scripts/api.sh ramp > tmp/ramp.log 2>&1 &
#   tail -f tmp/ramp.log

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# Load .env line by line, skipping comments and blank lines
if [[ -f .env ]]; then
    while IFS='=' read -r key value; do
        key="${key//[[:space:]]/}"
        value="${value%$'\r'}"
        [[ -z "$key" || "$key" == \#* || -z "$value" ]] && continue
        export "$key=$value"
    done < .env
fi

BASE_URL="${BASE_URL:-http://100.95.105.4:3000}"
PORT="${PORT:-3000}"
BIN="tmp/api"
LOG="tmp/api.log"
PIDFILE="tmp/api.pid"
STEP_SECONDS="${STEP_SECONDS:-20}"
RAMP_STEPS=(25 50 100 200 400 800)

COMMAND="${1:-help}"
[[ $# -gt 0 ]] && shift

REQUESTS=1000
CONCURRENCY=10
while getopts "n:c:" opt; do
    case $opt in
        n) REQUESTS="$OPTARG" ;;
        c) CONCURRENCY="$OPTARG" ;;
        *) echo "Invalid flag. Use -n requests and -c concurrency."; exit 1 ;;
    esac
done

usage() {
    grep '^#   ' "$0" | sed 's/^#   //'
}

require_server_host() {
    if ! command -v ss >/dev/null 2>&1; then
        echo "'$COMMAND' must run on the server host (needs ss and the local process)."
        exit 1
    fi
    mkdir -p tmp
}

require_hey() {
    if ! command -v hey >/dev/null 2>&1; then
        echo "hey not found. Install: go install github.com/rakyll/hey@latest"
        echo "Then make sure \$(go env GOPATH)/bin is on PATH."
        exit 1
    fi
}

# PID of the process listening on $PORT, or empty
port_pid() {
    ss -tlnp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p"$"' \
        | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -n1
}

stop_server() {
    if pgrep -x air >/dev/null 2>&1; then
        echo "Stopping Air"
        pkill -x air || true
        sleep 1
    fi

    local pid
    pid="$(port_pid || true)"
    if [[ -z "$pid" ]]; then
        echo "No process on port $PORT"
    else
        # Refuse to stop anything not started from this project
        if [[ "$(readlink -f "/proc/$pid/cwd")" != "$ROOT" ]]; then
            echo "Port $PORT is held by pid $pid outside this project. Not stopping it."
            exit 1
        fi
        echo "Stopping pid $pid"
        kill "$pid" 2>/dev/null || true
        for _ in $(seq 1 10); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.5
        done
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
}

build() {
    echo "Building $BIN"
    go build -o "$BIN" ./cmd/api
}

start_server() {
    echo "=== deploy $(date -Is) ===" >> "$LOG"
    GIN_MODE=release nohup "$ROOT/$BIN" >> "$LOG" 2>&1 &
    echo $! > "$PIDFILE"
    echo "Started pid $! (log: $LOG)"
}

verify() {
    for _ in $(seq 1 20); do
        if curl -sf -o /dev/null "http://localhost:$PORT/"; then
            echo "OK: GET / responded on port $PORT"
            return 0
        fi
        sleep 0.5
    done
    echo "FAIL: no response on port $PORT"
    return 1
}

show_status() {
    local pid
    pid="$(port_pid || true)"
    if [[ -n "$pid" ]]; then
        echo "Server: pid $pid on port $PORT"
        ps -o pid,etime,rss,cmd -p "$pid"
    else
        echo "Server: not running on port $PORT"
    fi

    if pgrep -x air >/dev/null 2>&1; then
        echo "Air: running"
    else
        echo "Air: not running"
    fi

    if [[ -f "$LOG" ]]; then
        local errors
        errors="$(grep -ciE 'error|fatal|panic|\| 5[0-9]{2} ' "$LOG" || true)"
        echo "Log: $LOG (error and 5xx lines: ${errors:-0})"
        echo "--- last 10 log lines ---"
        tail -n 10 "$LOG"
    else
        echo "Log: none yet"
    fi
}

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
PASS=0
FAIL=0

# check LABEL EXPECTED_CODE CURL_ARGS...
check() {
    local label="$1" expected="$2"
    shift 2
    local code
    code=$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$@" || true)
    if [[ "$code" == "$expected" ]]; then
        echo "PASS  $label -> $code"
        PASS=$((PASS + 1))
    else
        echo "FAIL  $label -> got ${code:-no response}, expected $expected"
        cat "$BODY_FILE"; echo
        FAIL=$((FAIL + 1))
    fi
}

run_smoke() {
    check "GET /"                  200 "$BASE_URL/"
    check "POST /todos (valid)"    201 -X POST "$BASE_URL/todos" \
          -H "Content-Type: application/json" \
          -d '{"title":"script test"}'
    check "POST /todos (bad JSON)" 400 -X POST "$BASE_URL/todos" \
          -H "Content-Type: application/json" \
          -d '{"title":'
    check "GET /todos"             200 "$BASE_URL/todos"

    echo
    echo "Passed: $PASS  Failed: $FAIL"
    [[ "$FAIL" -eq 0 ]] || exit 1
}

run_load() {
    require_hey
    echo
    hey -n "$REQUESTS" -c "$CONCURRENCY" "$BASE_URL/todos"
}

run_ramp() {
    require_hey
    local url="$BASE_URL/todos" c out bad
    for c in "${RAMP_STEPS[@]}"; do
        echo "== $c connections"
        out=$(hey -z "${STEP_SECONDS}s" -t 5 -c "$c" "$url")
        echo "$out" | grep -E "Requests/sec|99%|responses" || true

        bad=0
        echo "$out" | grep -q "Error distribution" && bad=1
        # Status summary lines look like: "  [200]	3974 responses"
        echo "$out" | grep -E '^\s*\[[0-9]{3}\][[:space:]]+[0-9]+ responses' | grep -qv '\[200\]' && bad=1

        if [[ "$bad" -eq 1 ]]; then
            echo "Errors at $c connections. Stopping."
            exit 1
        fi
    done
    echo "Ramp complete: no errors up to ${RAMP_STEPS[-1]} connections."
}

case "$COMMAND" in
    deploy)
        require_server_host
        build                  # build first, so a failed build leaves the old server running
        stop_server
        start_server
        if ! verify; then
            echo "--- last 20 log lines ---"
            tail -n 20 "$LOG"
            exit 1
        fi
        show_status
        ;;
    status)
        require_server_host
        show_status
        ;;
    stop)
        require_server_host
        stop_server
        ;;
    logs)
        [[ -f "$LOG" ]] || { echo "No log yet. Run deploy first."; exit 1; }
        tail -f "$LOG"
        ;;
    test)
        run_smoke
        ;;
    load)
        run_smoke
        run_load
        ;;
    ramp)
        run_ramp
        ;;
    *)
        usage
        exit 1
        ;;
esac
