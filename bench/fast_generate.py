#!/usr/bin/env python3
import os
import sys
import random
import time
import concurrent.futures
import shutil

# Scale definitions
SCALES = {
    'A': {'L1': 100, 'L2': 75, 'L3': 100, 'FILES': 5},  # Full: ~750k dirs, 3.75M files
    'B': {'L1': 50,  'L2': 30, 'L3': 50,  'FILES': 5},  # Medium: ~75k dirs, 375k files
    'C': {'L1': 25,  'L2': 15, 'L3': 20,  'FILES': 5},  # Small: ~7.5k dirs, 37.5k files
}

EXTENSIONS = ["txt", "log", "jpg", "png", "pdf", "doc", "xml", "json", "csv", "html"]

def create_leaf(path, num_files):
    """Create a leaf directory and populate it with empty files."""
    try:
        os.makedirs(path, exist_ok=True)
        for f in range(1, num_files + 1):
            # 10% chance to be target file (ends with digit.jpg)
            if random.randint(0, 9) == 0:
                name = f"image_{random.randint(0, 9)}.jpg"
            else:
                ext = EXTENSIONS[f % len(EXTENSIONS)]
                name = f"file_{f}.{ext}"
            
            # Create empty file efficiently
            with open(os.path.join(path, name), 'w') as _:
                pass
    except Exception as e:
        print(f"Error creating {path}: {e}", file=sys.stderr)

def generate_l2_structure(base_dir, l1_idx, config):
    """Generate all L2 and L3 directories for a single L1 directory."""
    l1_path = os.path.join(base_dir, f"dir_{l1_idx}")
    l3_count = config['L3']
    files_per_dir = config['FILES']
    
    tasks = []
    # Pre-calculate paths to reduce overhead
    for j in range(1, config['L2'] + 1):
        l2_path = os.path.join(l1_path, f"sub_{j}")
        for k in range(1, l3_count + 1):
            l3_path = os.path.join(l2_path, f"leaf_{k}")
            tasks.append((l3_path, files_per_dir))
            
    return tasks

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fast_generate.py [SCALE] [BASE_DIR]")
        print("Scales: A (Full), B (Medium), C (Small)")
        sys.exit(1)

    scale_key = sys.argv[1].upper()
    if scale_key not in SCALES:
        # Alias mapping
        if scale_key in ['FULL']: scale_key = 'A'
        elif scale_key in ['MEDIUM']: scale_key = 'B'
        elif scale_key in ['SMALL']: scale_key = 'C'
        else:
            print(f"Unknown scale: {scale_key}")
            sys.exit(1)

    config = SCALES[scale_key]
    base_dir = sys.argv[2] if len(sys.argv) > 2 else "/tmp/quasifind_bench"

    total_dirs = config['L1'] * config['L2'] * config['L3']
    total_files = total_dirs * config['FILES']

    print(f"=== Fast Data Generator ===")
    print(f"Scale: {scale_key}")
    print(f"Path : {base_dir}")
    print(f"Total: {total_dirs:,} dirs, {total_files:,} files")
    
    if os.path.exists(base_dir):
        print("Cleaning up old data...")
        shutil.rmtree(base_dir)
    os.makedirs(base_dir)

    start_time = time.time()
    
    # Strategy: Parallelize at L2/L3 creation level
    # We use ProcessPool for CPU-bound path generation or ThreadPool for I/O
    # File creation on fast SSD IS extremely I/O / syscall bound. 
    # ThreadPoolExecutor is usually sufficient and has less overhead than ProcessPool.
    
    print("Generating structure...")
    
    all_leaf_tasks = []
    for i in range(1, config['L1'] + 1):
        all_leaf_tasks.extend(generate_l2_structure(base_dir, i, config))
    
    print(f"Prepared {len(all_leaf_tasks):,} directory tasks. Executing...")
    
    # Number of workers
    workers = os.cpu_count() * 4
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        # Map tasks to executor
        # Using map is faster than submit loop for many tiny tasks
        list(executor.map(lambda p: create_leaf(*p), all_leaf_tasks))

    elapsed = time.time() - start_time
    print(f"\nGeneration Complete in {elapsed:.2f} seconds")
    print(f"Rate: {total_files / elapsed:.0f} files/sec")

if __name__ == "__main__":
    main()
