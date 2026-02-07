# Daemon Mode Experiment (Phase 1: PoC) Tasks

- [x] **Core Data Structure (VFS)**
  - [x] Define `Vfs` module with `inode` and `node` types (`lib/quasifind/vfs.ml`)
  - [x] Implement `insert_path` function to add paths to the Trie
  - [x] Implement `lookup_path` function to retrieve nodes
  - [x] Add unit tests for `Vfs` module

- [x] **Daemon Logic**
  - [x] Implement `Daemon` module (`lib/quasifind/daemon.ml`)
  - [x] Implement `build_initial_vfs` using `Traversal` module
  - [x] Add basic event loop (placeholder)

- [x] **CLI Integration**
  - [x] Add `daemon` command to `bin/main.ml`
  - [x] Update `lib/dune` to include new modules

- [x] **Verification**
  - [x] Run benchmark (memory usage & startup time)
  - [x] Create walkthrough document
