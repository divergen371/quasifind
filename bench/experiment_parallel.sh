#!/bin/bash
# Experimental benchmark to test parallelism impact
# Usage: ./bench/experiment_parallel.sh [BASE_DIR]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="${1:-/tmp/quasifind_bench}"
RESULT_FILE="$SCRIPT_DIR/results/experiment_parallel.json"
QUASIFIND="$SCRIPT_DIR/../_build/default/bin/main.exe"

# Ensure data exists (fast check)
if [ ! -d "$BASE_DIR" ]; then
    echo "Bench data not found at $BASE_DIR. Generating Scale B..."
    python3 "$SCRIPT_DIR/fast_generate.py" B "$BASE_DIR"
fi

echo "=== Running Parallelism Experiment ==="
echo "Base Dir: $BASE_DIR"
echo "Comparing -j 1 (default) vs -j 8 (parallel)"

hyperfine \
    --warmup 1 \
    --runs 5 \
    --export-json "$RESULT_FILE" \
    --command-name "quasifind (j=1)" \
        "$QUASIFIND $BASE_DIR 'name =~ /[0-9]\\.jpg\$/'" \
    --command-name "quasifind (j=8)" \
        "$QUASIFIND $BASE_DIR 'name =~ /[0-9]\\.jpg\$/' -j 8" \
    --command-name "fd (j=8 equivalent)" \
        "fd -j 8 '[0-9]\\.jpg$' $BASE_DIR" \
    2>&1

echo ""
echo "Results saved to: $RESULT_FILE"
