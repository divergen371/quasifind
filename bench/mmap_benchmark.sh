#!/bin/bash
set -e

# Benchmark Mmap Optimization

TARGET_DIR="/tmp/quasifind_bench"
mkdir -p "$TARGET_DIR"
TARGET_FILE="$TARGET_DIR/large_file.log"

echo "[Setup] Creating 512MB dummy file..."
# Create 512MB file (faster than 1GB for quick bench)
mkfile -n 512m "$TARGET_FILE" || dd if=/dev/zero of="$TARGET_FILE" bs=1024 count=524288 2>/dev/null

echo "needle_string" >> "$TARGET_FILE"
echo "[Setup] File created at $TARGET_FILE"

echo "---------------------------------------------------"
echo "Running Benchmark..."
echo "---------------------------------------------------"

# 1. Fast Path (Mmap + POSIX Regex)
echo "[1] Fast Path (Mmap): Searching for /needle_string/ ..."
echo "    Command: quasifind \"$TARGET_DIR\" 'content =~ /needle_string/'"
time dune exec quasifind -- "$TARGET_DIR" 'content =~ /needle_string/'

echo "---------------------------------------------------"

# 2. Slow Path (Fallback to OCaml Re due to non-POSIX syntax)
# We use a non-capturing group '(?:s)' which is valid PCRE but invalid POSIX Extended.
echo "[2] Slow Path (Legacy Read+GC): Searching for /needle_string(?:s)/ ..."
echo "    Command: quasifind \"$TARGET_DIR\" 'content =~ /needle_string(?:s)/'"
time dune exec quasifind -- "$TARGET_DIR" 'content =~ /needle_string(?:s)/'

echo "---------------------------------------------------"
echo "[Cleanup] Removing temp file..."
rm -rf "$TARGET_DIR"
echo "Done."
