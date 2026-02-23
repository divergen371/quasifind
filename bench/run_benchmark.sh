#!/bin/bash
# Run benchmarks and save results as JSON
# Usage: ./run_benchmark.sh [SCALE] [BASE_DIR]
#
# Modes benchmarked:
#   - quasifind (single-threaded)
#   - quasifind (parallel, -j 8)
#   - quasifind (daemon, --daemon)
#   - find (system)
#   - fd

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCALE="${1:-B}"
BASE_DIR="${2:-/tmp/quasifind_bench}"
RESULT_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$RESULT_DIR/benchmark_${SCALE}_${TIMESTAMP}.json"
SOCK_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/quasifind/daemon.sock"
DAEMON_PID=""

# Ensure quasifind is built
echo "Building quasifind..."
cd "$SCRIPT_DIR/.."
dune build

QUASIFIND="$SCRIPT_DIR/../_build/default/bin/main.exe"

# Create results directory
mkdir -p "$RESULT_DIR"

# ── Kill daemon reliably ──
kill_daemon() {
    if [ -z "$DAEMON_PID" ]; then return; fi
    if ! kill -0 "$DAEMON_PID" 2>/dev/null; then DAEMON_PID=""; return; fi

    echo "Stopping daemon (PID: $DAEMON_PID)..."

    # 1) Try IPC shutdown command (graceful)
    "$QUASIFIND" shutdown 2>/dev/null || true

    # 2) SIGTERM + wait up to 3 seconds
    if kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill "$DAEMON_PID" 2>/dev/null || true
        for _ in 1 2 3; do
            sleep 1
            kill -0 "$DAEMON_PID" 2>/dev/null || break
        done
    fi

    # 3) SIGKILL as last resort
    if kill -0 "$DAEMON_PID" 2>/dev/null; then
        echo "Daemon did not exit, sending SIGKILL..."
        kill -9 "$DAEMON_PID" 2>/dev/null || true
    fi

    wait "$DAEMON_PID" 2>/dev/null || true
    DAEMON_PID=""
    echo "Daemon stopped."
}

# ── Cleanup function (called on EXIT, ERR, INT, TERM) ──
cleanup() {
    echo ""
    echo "=== Cleanup ==="
    kill_daemon
    rm -f "$SOCK_PATH"
    pkill -9 -f "quasifind.*daemon" 2>/dev/null || true
    echo "Cleanup complete."
}
trap cleanup EXIT ERR INT TERM

# ── Step 1: Generate Test Data ──
echo ""
echo "=== Step 1: Generate Test Data (Scale: $SCALE) ==="
python3 "$SCRIPT_DIR/fast_generate.py" "$SCALE" "$BASE_DIR"

# ── Step 2: Warm up disk cache ──
echo ""
echo "=== Step 2: Warming up disk cache ==="
find "$BASE_DIR" -type f -name "*.jpg" > /dev/null 2>&1 || true

# ── Step 3: Count expected matches ──
echo ""
echo "=== Step 3: Counting expected matches ==="
expected_matches=$(find "$BASE_DIR" -type f -name '*[0-9].jpg' | wc -l | tr -d ' ')
echo "Expected matching files: $expected_matches"

# ── Step 4: Start daemon for --daemon benchmarks ──
echo ""
echo "=== Step 4: Starting daemon ==="
rm -f "$SOCK_PATH"
"$QUASIFIND" daemon > /dev/null 2>&1 &
DAEMON_PID=$!
echo "Daemon started (PID: $DAEMON_PID)"

# Wait for socket to become available (max 120s)
echo -n "Waiting for daemon socket..."
WAIT_COUNT=0
MAX_WAIT=120
while [ ! -S "$SOCK_PATH" ]; do
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
        echo " TIMEOUT (${MAX_WAIT}s). Daemon failed to start."
        exit 1
    fi
    echo -n "."
done
echo " ready! (${WAIT_COUNT}s)"

# ── Step 5: Run benchmarks with hyperfine ──
echo ""
echo "=== Step 5: Running Benchmarks ==="
echo "Pattern: [0-9].jpg"
echo "Results will be saved to: $RESULT_FILE"
echo ""

hyperfine \
    --warmup 2 \
    --runs 10 \
    --export-json "$RESULT_FILE" \
    --command-name "quasifind" \
        "$QUASIFIND $BASE_DIR 'name =~ /[0-9]\\.jpg\$/'" \
    --command-name "quasifind (parallel)" \
        "$QUASIFIND -j 8 $BASE_DIR 'name =~ /[0-9]\\.jpg\$/'" \
    --command-name "quasifind (daemon)" \
        "$QUASIFIND $BASE_DIR 'name =~ /[0-9]\\.jpg\$/' --daemon" \
    --command-name "find" \
        "find $BASE_DIR -type f -name '*[0-9].jpg'" \
    --command-name "fd" \
        "fd '[0-9]\\.jpg$' $BASE_DIR" \
    2>&1

echo ""
echo "=== Benchmark Complete ==="
echo "Results saved to: $RESULT_FILE"

# ── Step 6: Stop daemon ──
echo ""
echo "=== Step 6: Stopping daemon ==="
kill_daemon

# ── Step 7: Remove test data ──
echo ""
echo "=== Step 7: Removing test data ==="
rm -rf "$BASE_DIR"
echo "Test data removed."

# ── Summary ──
echo ""
echo "=== Summary ==="
if command -v jq &> /dev/null; then
    jq -r '.results[] | "\(.command): \(.mean * 1000 | floor)ms ± \(.stddev * 1000 | floor)ms"' "$RESULT_FILE"
else
    echo "Install jq to see summary. Results are in: $RESULT_FILE"
fi
