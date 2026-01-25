#!/bin/bash
# Benchmark data generator for quasifind
# Supports multiple scales: A (full), B (medium), C (small)

set -e

SCALE="${1:-B}"
BASE_DIR="${2:-/tmp/quasifind_bench}"

case "$SCALE" in
    A|a|full)
        # Full scale: ~750,000 dirs, ~4,000,000 files
        DIRS_L1=100
        DIRS_L2=75
        DIRS_L3=100
        FILES_PER_DIR=5
        ;;
    B|b|medium)
        # Medium scale: ~75,000 dirs, ~400,000 files
        DIRS_L1=50
        DIRS_L2=30
        DIRS_L3=50
        FILES_PER_DIR=5
        ;;
    C|c|small)
        # Small scale: ~7,500 dirs, ~40,000 files
        DIRS_L1=25
        DIRS_L2=15
        DIRS_L3=20
        FILES_PER_DIR=5
        ;;
    *)
        echo "Unknown scale: $SCALE (use A, B, or C)"
        exit 1
        ;;
esac

TOTAL_DIRS=$((DIRS_L1 * DIRS_L2 * DIRS_L3))
TOTAL_FILES=$((TOTAL_DIRS * FILES_PER_DIR))

echo "=== Benchmark Data Generator ==="
echo "Scale: $SCALE"
echo "Base directory: $BASE_DIR"
echo "Structure: $DIRS_L1 x $DIRS_L2 x $DIRS_L3 = $TOTAL_DIRS leaf dirs"
echo "Files per leaf: $FILES_PER_DIR"
echo "Estimated total files: $TOTAL_FILES"
echo ""

# Cleanup existing
if [ -d "$BASE_DIR" ]; then
    echo "Removing existing directory..."
    rm -rf "$BASE_DIR"
fi
mkdir -p "$BASE_DIR"

# Extensions for variety
EXTENSIONS=("txt" "log" "jpg" "png" "pdf" "doc" "xml" "json" "csv" "html")

count=0
start_time=$(date +%s)

echo "Generating directories and files..."

for i in $(seq 1 $DIRS_L1); do
    l1_dir="$BASE_DIR/dir_$i"
    mkdir -p "$l1_dir"
    
    for j in $(seq 1 $DIRS_L2); do
        l2_dir="$l1_dir/sub_$j"
        mkdir -p "$l2_dir"
        
        for k in $(seq 1 $DIRS_L3); do
            l3_dir="$l2_dir/leaf_$k"
            mkdir -p "$l3_dir"
            
            # Create files - some match [0-9].jpg pattern
            for f in $(seq 1 $FILES_PER_DIR); do
                if [ $((RANDOM % 10)) -eq 0 ]; then
                    # Target: ends with digit.jpg (~10% of files)
                    touch "$l3_dir/image_$((RANDOM % 10)).jpg"
                else
                    ext=${EXTENSIONS[$((f % ${#EXTENSIONS[@]}))]}
                    touch "$l3_dir/file_$f.$ext"
                fi
            done
            
            count=$((count + 1))
            if [ $((count % 5000)) -eq 0 ]; then
                pct=$((count * 100 / TOTAL_DIRS))
                elapsed=$(($(date +%s) - start_time))
                echo "Progress: $count / $TOTAL_DIRS dirs ($pct%) - ${elapsed}s elapsed"
            fi
        done
    done
done

end_time=$(date +%s)
elapsed=$((end_time - start_time))

# Get actual counts
actual_files=$(find "$BASE_DIR" -type f | wc -l | tr -d ' ')
actual_dirs=$(find "$BASE_DIR" -type d | wc -l | tr -d ' ')

echo ""
echo "=== Generation Complete ==="
echo "Time: ${elapsed}s"
echo "Directories: $actual_dirs"
echo "Files: $actual_files"
echo "Ready for benchmarking at: $BASE_DIR"
