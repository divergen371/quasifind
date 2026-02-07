# Daemon Mode Experiment Implementation Plan (Phase 1: PoC)

## Goal Description

Implement the core data structures and logic for the Daemon Mode experiment. This phase focuses on the "Brain" of the daemon: the in-memory filesystem representation (Trie) and the ability to populate it from a directory scan.

## User Review Required

> [!NOTE]
> This work is experimental and will be done on the `experiment/daemon-mode` branch. It will not affect the main `quasifind` binary until explicitly merged.

## Proposed Changes

### [NEW] [lib/quasifind/vfs.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/vfs.ml) (Virtual File System)

- Define `inode` type (size, mtime, perm).
- Define `node` type (File, Dir) using `Saturn.Skip_list` or `Map` for concurrency?
  - _Decision_: Start with standard `Map` protected by `Eio.Mutex` or `Atomic` for simplicity in PoC. Or better, use an immutable tree stored in an `Atomic` ref.
- Implement `insert` and `lookup` functions.
- Implement `of_traversal` to build the tree from a traversal stream.

### [NEW] [lib/quasifind/daemon.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/daemon.ml)

- Define the main entry point for the daemon command.
- Implement the startup logic:
  1. Initialize VFS (empty).
  2. Perform initial scan of Root Scope (`.`).
  3. Populate VFS.
  4. (Mock) Start an event loop that just sleeps for now (Phase 2 will add Watcher).

### [MODIFY] [bin/main.ml](file:///Users/atsushi/OCaml/quasifind/bin/main.ml)

- Add `daemon` subcommand to CLI.

### [MODIFY] [lib/quasifind/dune](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/dune)

- Add `vfs` and `daemon` to modules list.

## Verification Plan

### Automated Tests

- **VFS Unit Tests**: Verify insertion, lookup, and tree structure integrity.
- **Benchmark**: Measure memory usage and build time for a medium-sized directory (e.g., the project itself).

### Manual Verification

- Run `dune exec bin/main.exe -- daemon` and verify it starts and scans without crashing.
