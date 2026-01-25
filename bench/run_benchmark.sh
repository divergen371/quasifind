#!/bin/bash
# Run benchmarks and save results as JSON
# Usage: ./run_benchmark.sh [SCALE] [BASE_DIR]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCALE="${1:-B}"
BASE_DIR="${2:-/tmp/quasifind_bench}"
RESULT_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$RESULT_DIR/benchmark_${SCALE}_${TIMESTAMP}.json"

# Ensure quasifind is built
echo "Building quasifind..."
cd "$SCRIPT_DIR/.."
dune build

QUASIFIND="$SCRIPT_DIR/../_build/default/bin/main.exe"

# Create results directory
mkdir -p "$RESULT_DIR"

# Step 1: Generate Test Data
echo ""
echo "=== Step 1: Generate Test Data (Fast) ==="
python3 "$SCRIPT_DIR/fast_generate.py" "$SCALE" "$BASE_DIR"

# Step 2: Warm up cache (optional read to populate disk cache)
echo ""
echo "=== Step 2: Warming up disk cache ==="
find "$BASE_DIR" -type f -name "*.jpg" > /dev/null 2>&1 || true

# Step 3: Run benchmarks with hyperfine
echo ""
echo "=== Step 3: Running Benchmarks ==="
echo "Pattern: [0-9].jpg"
echo "Results will be saved to: $RESULT_FILE"
echo ""

# Count expected matches for verification
expected_matches=$(find "$BASE_DIR" -type f -name '*[0-9].jpg' | wc -l | tr -d ' ')
echo "Expected matching files: $expected_matches"
echo ""

# Run hyperfine with JSON export
hyperfine \
    --warmup 2 \
    --runs 10 \
    --export-json "$RESULT_FILE" \
    --command-name "quasifind" \
        "$QUASIFIND $BASE_DIR 'name =~ /[0-9]\\.jpg\$/'" \
    --command-name "find" \
        "find $BASE_DIR -type f -name '*[0-9].jpg'" \
    --command-name "fd" \
        "fd '[0-9]\\.jpg$' $BASE_DIR" \
    2>&1

echo ""
echo "=== Benchmark Complete ==="
echo "Results saved to: $RESULT_FILE"

# Step 4: Cleanup
echo ""
echo "=== Step 4: Cleanup ==="
echo "Removing test data at $BASE_DIR..."
rm -rf "$BASE_DIR"
echo "Cleanup complete."

# Display summary from JSON
echo ""
echo "=== Summary ==="
if command -v jq &> /dev/null; then
    jq -r '.results[] | "\(.command): \(.mean * 1000 | floor)ms ± \(.stddev * 1000 | floor)ms"' "$RESULT_FILE"
else
    echo "Install jq to see summary. Results are in: $RESULT_FILE"
fi
