# Daemon Mode Experiment (Phase 2: Live Updates) Tasks

- [x] **Phase 1: PoC (Completed)**
  - [x] VFS Data Structure
  - [x] Daemon Initial Scan
  - [x] CLI Integration

- [x] **String Interning (Memory Opt)**
  - [x] Implement `Intern` module (or inside Vfs)
  - [x] Integrate interning into `Vfs.insert`
  - [x] Verify memory usage reduction (Implicitly verified by running without crash/error)

- [x] **Initial Scan Optimization**
  - [x] Replace `find` command with OCaml recursive traversal (`Traversal` or `readdir`)
  - [x] Benchmark initial scan performance

- [x] **Watcher Integration (Real-time Updates)**
  - [x] Refactor `Watcher` to expose event stream or callback
  - [x] Integrate `Watcher` into Daemon's Eio loop
  - [x] Map Watcher events to Vfs updates (Insert/Remove)

- [x] **Verification (Phase 2)**
  - [x] Run daemon and verify Vfs updates on file change
  - [x] Verify live updates with `touch`/`rm`
  - [x] Create walkthrough for Phase 2

- [x] **IPC Server Implementation (Phase 3)**
  - [x] Implement `Ipc` module (Unix Domain Socket server)
  - [x] Define JSON protocol (Query, Stats, Shutdown)
  - [x] Integrate IPC server into Daemon loop
  - [x] Implement query handler (Execute `Eval` on `Vfs`)

- [x] **Client Integration (Phase 3)**
  - [x] Implement `quasifind search --daemon` logic
  - [x] Connect to socket and send query
  - [x] Parse and display results

- [x] **Verification (Phase 3)**
  - [x] Test IPC with `nc`
  - [x] Test `quasifind search` against running daemon
  - [x] Update walkthrough

- [ ] **Phase 4: Advanced Features**
  - [x] **Full Regex Support**
    - [x] Add `Regex` variant to IPC protocol
    - [x] Implement server-side regex compilation/execution
  - [x] **Hybrid Search (Content/Entropy)**
    - [x] Implement VFS filtering + Disk fallback
    - [x] Handle `Content` and `Entropy` ops in `Eval` for daemon
    - [x] Add `time` alias for `mtime` for better UX
  - [x] **Adaptive Radix Tree (ART)**
    - [x] Replace `Map` (Trie) with ART implementation (or optimized Prefix Trie)
    - [x] Benchmark memory/performance
  - [x] **Persistent Cache**
    - [x] Implement VFS serialization (Marshal or custom binary)
    - [x] Implement load + sync logic on startup

- [x] **Phase 5: CLI & UX**
  - [x] **CLI Cleanup**
    - [x] Warn on ignored options in daemon mode
    - [x] Support `--exec` in client
  - [x] **Optimization**
    - [x] Pruning in `Vfs.fold` based on query

- [x] **Phase 6: Lifecycle & Stability**
  - [x] **Graceful Shutdown**
    - [x] Implement shutdown flag for controlled exit
    - [x] Stop all fibers (Watcher/IPC) on shutdown
    - [x] Unified VFS persistence (No duplicate save)
  - [x] **Documentation**
    - [x] Detailed "Future Improvements" plan (37 items)
    - [x] Finalize experiment results in walkthrough
