#!/bin/bash
# Benchmark: SIMD content search (memmem) vs grep vs ripgrep
# Usage: ./bench_content.sh [NUM_FILES] [BASE_DIR]
#
# Generates files with realistic text content and benchmarks
# literal string search via quasifind content == "..." vs grep -rl

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NUM_FILES="${1:-5000}"
BASE_DIR="${2:-/tmp/quasifind_content_bench}"
RESULT_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$RESULT_DIR/bench_content_${TIMESTAMP}.json"

# Build
echo "Building quasifind..."
cd "$SCRIPT_DIR/.."
dune build
QUASIFIND="$SCRIPT_DIR/../_build/default/bin/main.exe"
mkdir -p "$RESULT_DIR"

# ── Cleanup ──
cleanup() {
    echo ""
    echo "=== Cleanup ==="
    rm -rf "$BASE_DIR"
    echo "Done."
}
trap cleanup EXIT ERR INT TERM

# ── Step 1: Generate test data with content ──
echo ""
echo "=== Step 1: Generating $NUM_FILES files with text content ==="
rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"

python3 -c "
import os, random, string, sys

base = '$BASE_DIR'
n = $NUM_FILES
needle = 'SEARCH_TARGET_MARKER'
hit_pct = 10  # 10% of files contain the needle

# Some realistic-ish text blocks
lorem = '''Lorem ipsum dolor sit amet, consectetur adipiscing elit.
Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum.'''

code = '''let process_entry path stat_info =
  let name = Filename.basename path in
  let size = stat_info.Unix.st_size in
  if size > threshold then Some (name, size)
  else None'''

log = '''2024-01-15 08:32:11 [INFO] Starting batch processing pipeline
2024-01-15 08:32:12 [WARN] Connection pool reaching capacity (85%)
2024-01-15 08:32:15 [ERROR] Failed to resolve host: db-replica-3.internal'''

blocks = [lorem, code, log]

# Create 10 subdirectories
dirs = [os.path.join(base, f'dir_{i}') for i in range(10)]
for d in dirs:
    os.makedirs(d, exist_ok=True)

exts = ['.txt', '.log', '.ml', '.py', '.json', '.xml', '.csv', '.md', '.rs', '.c']
hits = 0

for i in range(n):
    d = dirs[i % len(dirs)]
    ext = exts[i % len(exts)]
    path = os.path.join(d, f'file_{i:06d}{ext}')

    # Build file content: 1-4KB of text
    lines = []
    for _ in range(random.randint(3, 12)):
        lines.append(random.choice(blocks))

    # Insert needle in ~10% of files
    if random.randint(0, 99) < hit_pct:
        insert_pos = random.randint(0, len(lines))
        lines.insert(insert_pos, f'  {needle}  ')
        hits += 1

    with open(path, 'w') as f:
        f.write('\n'.join(lines))

print(f'Generated {n} files ({hits} contain needle \"{needle}\")')
"

# ── Step 2: Warm disk cache ──
echo ""
echo "=== Step 2: Warming disk cache ==="
cat "$BASE_DIR"/dir_0/*.txt > /dev/null 2>&1 || true
find "$BASE_DIR" -type f | head -100 | xargs cat > /dev/null 2>&1 || true

# ── Step 3: Count expected matches ──
echo ""
echo "=== Step 3: Counting expected matches ==="
expected=$(grep -rl "SEARCH_TARGET_MARKER" "$BASE_DIR" | wc -l | tr -d ' ')
echo "Files containing needle: $expected"

# ── Step 4: Run benchmarks ──
echo ""
echo "=== Step 4: Running content search benchmarks ==="
echo "Needle: SEARCH_TARGET_MARKER"
echo ""

hyperfine \
    --warmup 2 \
    --runs 10 \
    --export-json "$RESULT_FILE" \
    --command-name "quasifind content ==" \
        "$QUASIFIND $BASE_DIR 'content == \"SEARCH_TARGET_MARKER\"' > /dev/null" \
    --command-name "quasifind -j8 content ==" \
        "$QUASIFIND -j 8 $BASE_DIR 'content == \"SEARCH_TARGET_MARKER\"' > /dev/null" \
    --command-name "quasifind content =~ (regex)" \
        "$QUASIFIND $BASE_DIR 'content =~ /SEARCH_TARGET_MARKER/' > /dev/null" \
    --command-name "quasifind -j8 content =~ (regex)" \
        "$QUASIFIND -j 8 $BASE_DIR 'content =~ /SEARCH_TARGET_MARKER/' > /dev/null" \
    --command-name "grep -rl" \
        "grep -rl 'SEARCH_TARGET_MARKER' $BASE_DIR > /dev/null" \
    --command-name "rg -l" \
        "rg -l 'SEARCH_TARGET_MARKER' $BASE_DIR > /dev/null" \
    2>&1

echo ""
echo "=== Benchmark Complete ==="
echo "Results: $RESULT_FILE"

# ── Summary ──
echo ""
echo "=== Summary ==="
if command -v jq &> /dev/null; then
    jq -r '.results[] | "\(.command): \(.mean * 1000 | floor)ms ± \(.stddev * 1000 | floor)ms"' "$RESULT_FILE"
else
    echo "Install jq to see summary. Results in: $RESULT_FILE"
fi
